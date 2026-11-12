"""
tex_items_mats.py - procedural real-world materials for the ItemsReal texture bakes (numpy).

Every material is evaluated per texel from the baked data passes (see tex_items): asset-local position P, normal
N, piece grain coordinates G (x = along the grain / blade / strand), per-piece random value, material-specific
attributes a0..a3, ambient occlusion at a small and a large radius (aos, aol), "inside" occlusion (1 - aoi is a
convex-edge mask), bevel convexity, and the world size of a texel (for anti-aliasing the noise).

A material writes linear albedo, roughness, metalness, a height field in studs (turned into the normal map), the
alpha channel (opacity for glass / tint mask for skin) and a baked-occlusion value (stored in the ORM red channel).
Values follow measured PBR references: metals F0 0.5-0.9 (linear), dielectric albedo 0.03-0.8, rust 0.1-0.2.
"""
import math

import numpy as np

from tex_items import (C, cell_rand, fbm, perlin, ridged, scratches, smoothstep, voronoi)

# Material ids (the 'mid' face attribute; the bake stores mid + 100 * asset index)
STEEL, IRON, BRASS, WOOD, PLANK, LEATHER, CORD, CANVAS, GAUZE, GLASS, WATER, TIN, PAINT, APPLE, BERRY, MEAT, \
    LEAF, STEM, FEATHER, HORN, SKIN, NAIL, GLOVE, FABRIC, LINEN, PAPER, EMBER, BONE, STRING, WAX = range(1, 31)

NAMES = {v: k for k, v in dict(STEEL=STEEL, IRON=IRON, BRASS=BRASS, WOOD=WOOD, PLANK=PLANK, LEATHER=LEATHER,
                                CORD=CORD, CANVAS=CANVAS, GAUZE=GAUZE, GLASS=GLASS, WATER=WATER, TIN=TIN, PAINT=PAINT,
                                APPLE=APPLE, BERRY=BERRY, MEAT=MEAT, LEAF=LEAF, STEM=STEM, FEATHER=FEATHER, HORN=HORN,
                                SKIN=SKIN, NAIL=NAIL, GLOVE=GLOVE, FABRIC=FABRIC, LINEN=LINEN, PAPER=PAPER,
                                EMBER=EMBER, BONE=BONE, STRING=STRING, WAX=WAX).items()}


class Texels:
    """The texels of one material inside one asset (all arrays length n)."""

    def __init__(self, d, idx, ts):
        self.idx = idx
        self.P = d["P"][idx]
        self.N = d["N"][idx]
        self.G = d["G"][idx]
        m = d["M"][idx]
        a = d["A"][idx]
        o = d["O"][idx]
        e = d["E"][idx]
        self.rnd = m[:, 1]
        self.a0 = m[:, 2]
        self.a1, self.a2, self.a3 = a[:, 0], a[:, 1], a[:, 2]
        self.aos = np.clip(o[:, 0], 0, 1)
        self.aol = np.clip(o[:, 1], 0, 1)
        self.aoi = np.clip(o[:, 2], 0, 1)
        self.cvx = np.clip(e[:, 0], 0, 2)
        self.cvx2 = np.clip(e[:, 1], 0, 2)
        self.ts = ts[idx]
        n = len(idx)
        self.n = n
        self.albedo = np.zeros((n, 3))
        self.rough = np.full(n, 0.6)
        self.metal = np.zeros(n)
        self.height = np.zeros(n)
        self.alpha = np.ones(n)
        self.ao = np.ones(n)

    def subset(self, sel):
        import copy
        sub = copy.copy(self)
        for k in ("idx", "P", "N", "G", "rnd", "a0", "a1", "a2", "a3", "aos", "aol", "aoi", "cvx", "cvx2", "ts",
                  "albedo", "rough", "metal", "height", "alpha", "ao"):
            setattr(sub, k, getattr(self, k)[sel])
        sub.n = len(sel)
        return sub

    # ---------------------------------------------------------------- masks
    def edge(self, lo=0.25, hi=0.75, noise=0.35, freq=40.0, seed=0):
        """Convex-edge wear mask: bevel convexity (wide radius) where the surface is not occluded (a concave
        corner is occluded, a convex edge is not), broken up by noise. lo/hi act on a 0..1 edge measure."""
        c = np.clip(self.cvx2 / 0.22, 0, 1.5) * smoothstep(0.55, 0.85, self.aos)
        nz = fbm(self.P, freq, 3, seed=seed) * noise
        return smoothstep(lo, hi, c + nz)

    def crevice(self, lo=0.05, hi=0.5):
        return smoothstep(lo, hi, (1.0 - self.aos) * 1.2 + (1.0 - self.aol) * 0.5)

    def aa(self, freq):
        """Attenuation for a noise of `freq` cycles per stud on these texels (1 = resolvable, 0 = alias)."""
        return smoothstep(0.45, 0.2, freq * self.ts)

    def fbm_aa(self, P, freq, octaves=4, seed=0, gain=0.5, lac=2.03):
        out = np.zeros(self.n)
        amp, norm, f = 1.0, 0.0, freq
        from tex_items import _ROTS
        for o in range(octaves):
            w = self.aa(f)
            out += amp * w * perlin((P @ _ROTS[o % 12]) * f, seed + o * 101)
            norm += amp
            amp *= gain
            f *= lac
        return out / norm

    def finish_ao(self, strength=0.75, grime=None):
        """Bake soft occlusion into the albedo (Roblox has no AO map) and store it for the ORM red channel."""
        occ = np.clip(self.aos * 0.6 + self.aol * 0.4, 0, 1)
        self.ao = occ
        k = 1.0 - strength * (1.0 - occ)
        self.albedo = self.albedo * k[:, None]


def lerp3(a, b, t):
    """Blend colours: a, b are (3,) or (n, 3); t is a scalar or (n,)."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    t = np.asarray(t, dtype=np.float64)
    if t.ndim == 1:
        t = t[:, None]
    return a * (1.0 - t) + b * t


def tint(base, var, amount):
    """base colour (3,) varied by a signed noise (n,) -> (n, 3), multiplicative in linear space."""
    return base[None, :] * np.exp(np.asarray(var)[:, None] * amount)


# =============================================================================================== metals
def mat_steel(t, p):
    """Forged carbon-steel blade: satin grind streaks along the blade, grey patina, bright honed edge band
    (a0 = 1 on the sharpened bevel), scattered scratches, a little rust in crevices and pits."""
    G, P = t.G, t.P
    wear = p.get("wear", 0.5)
    bright = p.get("bright", 0.47)
    base = np.array([bright, bright * 1.005, bright * 1.015])
    # long grinding streaks (gco x = along the blade)
    streak = t.fbm_aa(np.stack([G[:, 0] * 2.0, G[:, 1] * 160.0, G[:, 2] * 160.0], 1), 1.0, 3, seed=11)
    fine = t.fbm_aa(np.stack([G[:, 0] * 6.0, G[:, 1] * 700.0, G[:, 2] * 700.0], 1), 1.0, 2, seed=12)
    # patina blotches (forced/oxidation patina of carbon steel)
    pat = smoothstep(-0.35, 0.45, fbm(P, p.get("patina_f", 4.0), 5, seed=13) + 0.3 * fbm(P, 14.0, 3, seed=14)) * p.get("patina", 0.55)
    grind = smoothstep(0.15, 0.6, np.clip(t.a0, 0, 1))
    col = tint(base, streak * 0.16 + fine * 0.08, 1.0)
    pat_col = np.array([0.22, 0.215, 0.2]) * p.get("patina_dark", 1.0)
    pat_col = pat_col * np.exp(fbm(P, 25.0, 3, seed=21) * 0.25)[:, None]
    col = lerp3(col, pat_col, pat * (1 - grind) * 0.85)
    # handling: duller fingerprint smears and an oil film near fittings
    smear = smoothstep(0.35, 0.8, fbm(P, 9.0, 4, seed=22) * 0.5 + 0.45) * 0.5
    col = col * (1 - 0.12 * smear)[:, None]
    # honed edge band: brighter, sharpening scratches across the band
    hone = t.fbm_aa(np.stack([G[:, 0] * 500.0, G[:, 1] * 4.0, G[:, 2] * 40.0], 1), 1.0, 2, seed=15)
    col = lerp3(col, np.array([0.6, 0.6, 0.61]) * (1 + hone[:, None] * 0.1), grind * 0.95)
    sc = scratches(P, density=0.7 + wear * 0.8, freq=90.0, width=0.07, seed=16, layers=7, length=0.18)
    sc *= t.aa(90.0)
    sw = p.get("stonewash", 0.0)
    if sw:
        # tumbled finish: dense short scratches in every direction, mottled grey
        sc2 = scratches(P, density=1.4, freq=140.0, width=0.08, seed=26, layers=9, length=0.05) * t.aa(140.0)
        sc = np.maximum(sc, sc2 * sw)
        col = col * np.exp(fbm(P, 30.0, 3, seed=27) * 0.18 * sw)[:, None]
    col = col * (1 + 0.35 * sc[:, None])
    edge = t.edge(0.3, 0.8, 0.3, 50.0, seed=23)
    col = lerp3(col, np.array([0.62, 0.62, 0.63]), edge * 0.5 * (1 - grind))
    # rust: crevices near fittings + sparse pits
    pits_f1, _, _ = voronoi(P, 55.0, seed=17)
    pit = smoothstep(0.22, 0.08, pits_f1) * smoothstep(0.55, 0.8, fbm(P, 6.0, 3, seed=18) * 0.5 + 0.5)
    rust = np.clip(t.crevice(0.15, 0.6) * smoothstep(0.0, 0.5, fbm(P, 8.0, 3, seed=19) + 0.3) * p.get("rust", 0.5)
                   + pit * p.get("pits", 0.6), 0, 1) * (1 - grind)
    rust_col = lerp3(C(110, 52, 26), C(62, 30, 16), smoothstep(-0.3, 0.4, fbm(P, 30.0, 3, seed=20)))
    t.albedo = lerp3(col, rust_col, rust)
    t.metal = 1.0 - rust * 0.95
    r = 0.36 + streak * 0.07 + pat * p.get("patina_rough", 0.16) + smear * 0.12 - grind * 0.16 - sc * 0.08 - edge * 0.1
    t.rough = np.clip(np.where(rust > 0.5, 0.85, r) * (1 - rust) + 0.85 * rust, 0.08, 1.0)
    t.height = -0.00035 * sc - 0.0004 * pit + 0.0003 * rust + 0.00008 * streak
    t.finish_ao(0.5)


def mat_iron(t, p):
    """Hand-forged iron: blackened forge scale with hammer facets, pitting, bright steel on worn edges and rust
    in pits / crevices (p['rust'] 0..1; p['streaks'] adds rain-run rust for outdoor pieces)."""
    P = t.P
    rust_amt = p.get("rust", 0.35)
    f1, f2, cid = voronoi(P, p.get("hammer", 26.0), seed=31)
    facet = -(1.0 - np.clip(f1 / 0.75, 0, 1)) ** 2 * 0.0018
    scale_var = fbm(P, 9.0, 4, seed=32)
    col = tint(C(40, 41, 44), scale_var * 0.45 + fbm(P, 40.0, 2, seed=43) * 0.15, 1.0)
    # thin brownish temper film over parts of the scale
    col = lerp3(col, C(52, 46, 40), smoothstep(0.1, 0.6, fbm(P, 3.0, 3, seed=44)) * 0.5)
    # pitting
    pf1, _, _ = voronoi(P, 120.0, seed=33)
    pit = smoothstep(0.25, 0.1, pf1) * smoothstep(0.35, 0.7, fbm(P, 5.0, 3, seed=34) * 0.5 + 0.5) * t.aa(120.0)
    edge = t.edge(0.3, 0.8, 0.4, 30.0, seed=35) * p.get("edge_wear", 0.8)
    steel = np.array([0.42, 0.42, 0.43])
    col = lerp3(col, steel, edge)
    spots = smoothstep(0.62, 0.85, fbm(P, 7.0, 4, seed=36) * 0.5 + 0.5)
    rmask = np.clip(t.crevice(0.15, 0.6) * 0.8 + pit * 0.8 + spots * 0.7, 0, 1) * rust_amt
    if p.get("streaks", 0.0) > 0:
        Q = np.stack([P[:, 0] * 30.0, P[:, 1] * 30.0, P[:, 2] * 2.5], 1)
        st = smoothstep(0.1, 0.6, fbm(Q, 1.0, 3, seed=37)) * smoothstep(0.3, 0.9, np.abs(t.N[:, 2]) * -1 + 1.0)
        rmask = np.clip(rmask + st * p["streaks"], 0, 1)
    rmask = rmask * (1 - edge * 0.8)
    ground = np.zeros(t.n)
    if p.get("ground", 0.0) > 0:
        # bright ground bevel with a wavy grind line and grind streaks running away from the edge (gco x)
        G = t.G
        wav = fbm(P, 18.0, 3, seed=41) * p.get("ground_wav", 0.12)
        ground = smoothstep(0.02, 0.1, t.a0 + wav) * p["ground"]
        gstreak = t.fbm_aa(np.stack([G[:, 0] * 8.0, G[:, 1] * 400.0, G[:, 2] * 400.0], 1), 1.0, 2, seed=42)
        gcol = np.array([0.56, 0.56, 0.57]) * np.exp(gstreak * 0.12)[:, None]
        col = lerp3(col, gcol, ground)
        rmask = rmask * (1 - ground)
    rust_col = lerp3(C(122, 58, 28), C(70, 34, 18), smoothstep(-0.4, 0.5, fbm(P, 40.0, 3, seed=38)))
    rust_col = lerp3(rust_col, C(150, 84, 40), smoothstep(0.3, 0.8, fbm(P, 15.0, 2, seed=39)) * 0.5)
    riv = np.zeros(t.n)
    dome = np.zeros(t.n)
    rr = p.get("rivet_r", 0.022)
    for (rx, ry, rz) in p.get("rivets", []):
        d = np.sqrt(np.sum((P - np.array([rx, ry, rz])) ** 2, 1))
        riv = np.maximum(riv, smoothstep(rr + 0.012, rr, d))
        dome = np.maximum(dome, np.sqrt(np.clip(1.0 - (d / rr) ** 2, 0, 1)))
    if p.get("rivets"):
        rmask = np.clip(rmask + riv * (1 - dome) * 0.8 * rust_amt, 0, 1)
        col = lerp3(col, steel * 0.9, dome * smoothstep(0.6, 1.0, dome) * 0.5)
    t.albedo = col * (1 - rmask[:, None]) + rust_col * rmask[:, None]
    t.metal = (0.75 + 0.25 * np.maximum(edge, ground)) * (1 - rmask)
    t.rough = np.clip((0.62 + scale_var * 0.1 - edge * 0.3 - ground * 0.36) * (1 - rmask) + rmask * 0.9, 0.15, 1.0)
    t.height = (facet * (1 - edge * 0.5) * (1 - ground) - 0.0012 * pit * (1 - ground)
                + 0.0006 * rmask * (fbm(P, 60.0, 2, seed=40) * 0.5 + 0.5)) * (1 - dome) + dome * rr * 0.35
    t.finish_ao(0.6)


def mat_brass(t, p):
    P = t.P
    base = np.array([0.62, 0.46, 0.21])
    var = fbm(P, 12.0, 3, seed=51)
    tarnish = smoothstep(0.0, 0.7, t.crevice(0.05, 0.5) + fbm(P, 5.0, 4, seed=52) * 0.5 + 0.35) * p.get("tarnish", 0.85)
    edge = t.edge(0.3, 0.8, 0.3, 40.0, seed=53)
    col = tint(base, var * 0.2, 1.0)
    tcol = lerp3(np.array([0.2, 0.14, 0.07]), np.array([0.13, 0.11, 0.06]), smoothstep(-0.3, 0.5, fbm(P, 18.0, 3, seed=56)))
    col = lerp3(col, tcol, tarnish * 0.9 * (1 - edge))
    col = lerp3(col, np.array([0.78, 0.6, 0.32]), edge * 0.75)
    verd = smoothstep(0.65, 0.95, t.crevice(0.1, 0.7) * (fbm(P, 20.0, 3, seed=54) * 0.5 + 0.6)) * p.get("verdigris", 0.4)
    t.albedo = lerp3(col, C(84, 120, 98), verd)
    t.metal = 1.0 - verd
    t.rough = np.clip(0.36 + tarnish * 0.28 - edge * 0.2 + verd * 0.4, 0.12, 1.0)
    sc = scratches(P, 0.8, 120.0, 0.07, seed=55, layers=4, length=0.1) * t.aa(120.0)
    t.height = -0.0003 * sc + 0.0004 * verd
    t.finish_ao(0.5)


def mat_tin(t, p):
    """Tinned / galvanised sheet steel: dull grey with oxidation mottling, scratches, dents, rust at rims."""
    P = t.P
    var = fbm(P, 5.0, 4, seed=61)
    col = tint(np.asarray(p.get("base", np.array([0.52, 0.52, 0.50]))), var * 0.25, 1.0)
    mott = smoothstep(0.0, 0.5, fbm(P, 14.0, 3, seed=62))
    col = lerp3(col, np.array([0.33, 0.33, 0.31]), mott * 0.5)
    sc = scratches(P, 1.0, 100.0, 0.06, seed=63, layers=5, length=0.12) * t.aa(100.0)
    col = col * (1 + 0.2 * sc[:, None])
    rust = smoothstep(0.35, 0.75, t.crevice(0.1, 0.6) + (1 - t.aoi) * 0.5 + fbm(P, 20.0, 3, seed=64) * 0.4) * p.get("rust", 0.4)
    t.albedo = lerp3(col, C(104, 56, 30), rust)
    t.metal = 1 - rust
    t.rough = np.clip(p.get("rough", 0.38) + mott * 0.18 - sc * 0.08 + rust * 0.5, 0.15, 1)
    dent = fbm(P, 3.0, 3, seed=65) * 0.002 * p.get("dents", 1.0)
    t.height = dent - sc * 0.0003 + rust * 0.0003
    kn = p.get("knurl")
    if kn:
        # knurled cap skirt (a0 = 1): fine vertical ridges around the piece axis (gco x = axis, rnd = 0)
        sel = np.clip(t.a0, 0, 1)
        ang = np.arctan2(t.G[:, 2], t.G[:, 1])
        ridge = (0.5 + 0.5 * np.cos(ang * kn)) * t.aa(kn / (2 * math.pi * 0.1))
        t.height = t.height + 0.0012 * ridge * sel
        t.albedo = t.albedo * (1 - 0.3 * (1 - ridge) * sel)[:, None]
        t.rough = t.rough + 0.08 * (1 - ridge) * sel
    t.finish_ao(0.55)


def mat_paint(t, p):
    """Painted tin (olive drab) with chipped paint on rims / edges showing metal and rust."""
    P = t.P
    base = np.asarray(p.get("color", C(78, 80, 46)))
    var = fbm(P, 6.0, 4, seed=71)
    col = tint(base, var * 0.18, 1.0)
    chip = smoothstep(0.45, 0.6, (1 - t.aoi) * 1.4 + fbm(P, 35.0, 4, seed=72) * 0.6) * p.get("chips", 0.7)
    chip = np.maximum(chip, smoothstep(0.82, 0.9, fbm(P, 25.0, 4, seed=73) * 0.5 + 0.5) * 0.9)
    metal_col = np.array([0.46, 0.46, 0.45])
    rust = chip * smoothstep(0.2, 0.7, fbm(P, 30.0, 3, seed=74) * 0.5 + 0.5)
    under = lerp3(metal_col, C(110, 58, 30), rust)
    t.albedo = col * (1 - chip[:, None]) + under * chip[:, None]
    t.metal = chip * (1 - rust)
    t.rough = np.clip(0.55 + var * 0.08 + chip * (0.35 - 0.55) + rust * 0.4, 0.2, 1)
    t.height = -0.0006 * chip + 0.0001 * var
    stencil = p.get("stencil")
    if stencil is not None:
        m = stencil(t)
        t.albedo = lerp3(t.albedo, C(206, 200, 176), m * (1 - chip))
        t.rough = t.rough + m * 0.05
    t.finish_ao(0.55)


# =============================================================================================== wood
def _rings(t, ring_freq, pith, distort=0.6, seed=0):
    G = t.G
    y = G[:, 1] + pith[0]
    z = G[:, 2] + pith[1]
    warp = fbm(np.stack([G[:, 0] * 0.6, G[:, 1] * 2.0, G[:, 2] * 2.0], 1), 1.0, 4, seed=seed) * distort
    r = np.sqrt(y * y + z * z) * ring_freq + warp * 3.0 + G[:, 0] * 0.15
    fr = r - np.floor(r)
    late = smoothstep(0.55, 0.85, fr) * smoothstep(1.0, 0.9, fr)
    return late, r


def mat_wood(t, p):
    """Oiled hardwood (ash / hickory / walnut): growth rings in the piece frame (x along the grain), open pores,
    darker hand-grime where it is held (a1 = grip zone weight), lighter worn edges, dirt in crevices."""
    G, P = t.G, t.P
    light = np.asarray(p.get("light", C(176, 134, 92)))
    dark = np.asarray(p.get("dark", C(118, 82, 52)))
    late, r = _rings(t, p.get("rings", 26.0), p.get("pith", (0.9, 0.35)), seed=81)
    fibre = t.fbm_aa(np.stack([G[:, 0] * 3.0, G[:, 1] * 260.0, G[:, 2] * 260.0], 1), 1.0, 3, seed=82)
    pores = smoothstep(0.35, 0.75, t.fbm_aa(np.stack([G[:, 0] * 30.0, G[:, 1] * 500.0, G[:, 2] * 500.0], 1), 1.0, 2,
                                            seed=83) * 0.5 + 0.5) * t.aa(500.0)
    piece = (t.rnd - 0.5) * 0.25
    streaks = t.fbm_aa(np.stack([G[:, 0] * 0.8, G[:, 1] * 30.0, G[:, 2] * 30.0], 1), 1.0, 3, seed=87)
    col = lerp3(light, dark, np.clip(late * 0.9 + fibre * 0.35 + streaks * 0.35 + 0.1, 0, 1))
    col = col * np.exp(piece)[:, None] * np.exp(fbm(P, 2.0, 3, seed=84) * 0.22)[:, None]
    col = col * (1 - 0.4 * pores[:, None])
    # mineral streaks / water stains along the grain
    stain = smoothstep(0.55, 0.85, fbm(np.stack([G[:, 0] * 0.6, G[:, 1] * 6.0, G[:, 2] * 6.0], 1), 1.0, 3,
                                       seed=88) * 0.5 + 0.5)
    col = lerp3(col, col * np.array([0.6, 0.55, 0.5]), stain * p.get("stains", 0.5))
    grip = np.clip(t.a1, 0, 1) * p.get("grime", 0.6)
    col = lerp3(col, col * np.array([0.5, 0.44, 0.38]), grip * smoothstep(-0.3, 0.5, fbm(P, 8.0, 3, seed=85) + 0.3))
    col = lerp3(col, col * np.array([0.78, 0.74, 0.7]), smoothstep(0.2, 0.8, fbm(P, 1.5, 3, seed=89) * 0.5 + 0.5)
                * p.get("use_grime", 0.5))
    edge = t.edge(0.3, 0.8, 0.35, 25.0, seed=86) * p.get("edge_wear", 0.6)
    col = lerp3(col, np.minimum(col * 1.45, 1.0), edge * 0.6)
    dirt = t.crevice(0.1, 0.6) * p.get("dirt", 0.6)
    col = lerp3(col, C(58, 46, 34), dirt * 0.6)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(p.get("rough", 0.55) + late * 0.06 + pores * 0.14 - grip * 0.14 + edge * 0.1 + dirt * 0.15
                      + stain * 0.08, 0.2, 1)
    t.height = -0.0012 * pores - 0.0005 * late + 0.0002 * fibre
    # end grain (a2 = 1 on cut ends): rings show as circles, darker and rougher
    t.finish_ao(0.6)


def mat_plank(t, p):
    """Weathered, silvered crate planks: raised grain (soft earlywood eroded), checks along the grain, end grain
    on cut faces (a1..a3 = grain axis), sun-silvering on exposed faces, brown where sheltered, grime at the ground
    and in joints, rust stains running down from nails (p['nails'][asset] = list of nail positions)."""
    G, P, N = t.G, t.P, t.N
    late, r = _rings(t, p.get("rings", 17.0), (p.get("pith", 1.4), 0.6), distort=p.get("distort", 0.1), seed=91)
    fibre = t.fbm_aa(np.stack([G[:, 0] * 1.5, G[:, 1] * 120.0, G[:, 2] * 120.0], 1), 1.0, 4, seed=92)
    axis = np.stack([t.a1, t.a2, t.a3], 1)
    endg = smoothstep(0.75, 0.9, np.abs(np.sum(axis * N, 1)))
    silver = np.asarray(p.get("silver", C(150, 142, 128)))
    brown = np.asarray(p.get("brown", C(122, 92, 62)))
    groove = np.asarray(p.get("groove", C(64, 56, 48)))
    expo = np.clip(t.aol * 1.2 - 0.1, 0, 1)
    weather = np.clip(p.get("weather", 0.75) * expo + fbm(P, 1.2, 3, seed=93) * 0.25 + (t.rnd - 0.5) * 0.3, 0, 1)
    col = lerp3(brown, silver, weather)
    if "alt" in p:
        col = lerp3(col, col * np.asarray(p["alt"]), np.clip(t.a0, 0, 1))
    burn = np.zeros(t.n)
    if "brand" in p:
        burn = brand_mask(P, N, p["brand"])
    col = col * np.exp((t.rnd - 0.5) * 0.35 + fbm(P, 0.8, 2, seed=94) * 0.15)[:, None]
    col = col * (1 + fibre[:, None] * 0.18)
    col = col * (1 + t.fbm_aa(np.stack([G[:, 0] * 0.7, G[:, 1] * 45.0, G[:, 2] * 45.0], 1), 1.0, 3,
                                  seed=102)[:, None] * 0.12)
    col = lerp3(col, groove, late * p.get("late", 0.22))
    # checks / cracks along the grain
    ck = np.abs(perlin(np.stack([G[:, 0] * 0.9, G[:, 1] * 9.0, G[:, 2] * 9.0], 1), 95))
    gate = smoothstep(0.1, 0.5, fbm(np.stack([G[:, 0] * 1.4, G[:, 1] * 3, G[:, 2] * 3], 1), 1.0, 2, seed=96))
    crack = smoothstep(0.035, 0.0, ck) * gate * p.get("cracks", 0.8) * (1 - endg)
    col = lerp3(col, C(40, 33, 27), crack * 0.85)
    # end grain: concentric rings, darker and rougher
    eg_rings = 0.5 + 0.5 * np.sin(r * 2 * math.pi)
    eg_col = lerp3(C(96, 80, 62), C(66, 54, 42), eg_rings) * np.exp(fbm(P, 20.0, 3, seed=97) * 0.2)[:, None]
    col = lerp3(col, eg_col, endg)
    # grime: low on the crate, in joints and corners
    low = smoothstep(0.6, 0.0, P[:, 2]) * p.get("ground_grime", 0.7)
    grime = np.clip(t.crevice(0.1, 0.55) * 0.8 + low * (0.5 + 0.5 * fbm(P, 3.0, 3, seed=98)), 0, 1)
    col = lerp3(col, C(52, 44, 34), grime * 0.7)
    moss = smoothstep(0.55, 0.85, low * (fbm(P, 6.0, 4, seed=99) * 0.5 + 0.6)) * p.get("moss", 0.35)
    col = lerp3(col, C(70, 82, 40), moss * 0.8)
    # nail rust stains (halo + rain streak downward)
    stain = np.zeros(t.n)
    head = np.zeros(t.n)
    for (nx, ny, nz) in p.get("nails_now", []):
        d = P - np.array([nx, ny, nz])
        head = np.maximum(head, smoothstep(0.0135, 0.0095, np.sqrt(np.sum(d * d, 1))))
        dz = d[:, 2]
        horiz = np.sqrt(np.maximum(np.sum(d * d, 1) - dz * dz, 0.0))
        halo = np.exp(-(np.sqrt(np.sum(d * d, 1)) / 0.045) ** 2)
        down = np.exp(-(horiz / (0.022 + 0.02 * np.clip(-dz, 0, 0.6))) ** 2) * np.exp(-np.clip(-dz, 0, None) / 0.25) * (dz < 0.01)
        stain = np.maximum(stain, np.maximum(halo, down * 0.75))
    stain = np.clip(stain * (0.75 + 0.5 * fbm(P, 25.0, 3, seed=100)), 0, 1) * p.get("nail_stain", 0.85)
    col = lerp3(col, C(84, 46, 26), stain * 0.85)
    # burnt-in brand: charred black core, scorched brown halo, slightly sunken
    if "brand" in p:
        core, halo = burn
        col = lerp3(col, C(66, 44, 30), halo * 0.7)
        col = lerp3(col, C(22, 16, 13), core * 0.92)
    # forged nail heads: dark scaled iron, rusty rim, slightly domed
    hcol = lerp3(C(46, 42, 38), C(96, 52, 30), smoothstep(-0.2, 0.5, fbm(P, 90.0, 2, seed=101)))
    col = lerp3(col, hcol, head)
    t.albedo = col
    t.metal = head * 0.45
    t.rough = np.clip(0.78 + late * 0.06 + crack * 0.15 + endg * 0.1 - stain * 0.05 + moss * 0.1, 0.4, 1)
    t.rough = t.rough * (1 - head) + 0.72 * head
    if "brand" in p:
        t.rough = np.clip(t.rough + burn[0] * 0.08, 0, 1)
    t.height = (-0.004 * (1 - late) * (1 - endg) * p.get("relief", 1.0) + 0.0012 * fibre - 0.012 * crack
                - 0.002 * eg_rings * endg) * (1 - head) + 0.0015 * head
    if "brand" in p:
        t.height = t.height - 0.0015 * burn[0]
    t.finish_ao(0.7)


def brand_mask(P, N, spec):
    """The arena sigil, the Spire 'Cleft', burnt into an upward-facing board: a tapering stone monolith split down its
    upper half, two iron bands, a fire basket with three flames. spec = dict(center=(x, y, z), size, up_axis='y').
    Returns (core, halo) masks. Purely our own iconography."""
    cx, cy, cz = spec["center"]
    sz = spec.get("size", 1.0)
    u = (P[:, 0] - cx) / sz
    v = (P[:, 1] - cy) / sz
    facing = smoothstep(0.6, 0.9, N[:, 2]) * smoothstep(0.05, 0.0, np.abs(P[:, 2] - cz))
    hw = 0.1 - 0.025 * np.clip((v + 0.32) / 0.58, 0, 1)
    sd = np.maximum(np.abs(u) - hw, np.maximum(-0.32 - v, v - 0.26))                 # monolith box
    sd = np.maximum(sd, np.minimum(0.016 - np.abs(u), v))                           # cleft: upper half split
    for b in (-0.1, 0.1):                                                            # iron bands
        sd = np.minimum(sd, np.maximum(np.abs(u) - 0.128, np.abs(v - b) - 0.022))
    bowl = np.maximum(np.abs(u) - (0.07 + (v - 0.28) * 0.9), np.maximum(0.28 - v, v - 0.35))
    sd = np.minimum(sd, bowl)                                                        # fire basket
    for fx, fh in ((-0.035, 0.07), (0.0, 0.11), (0.035, 0.07)):                      # three flames
        ecy = 0.35 + fh * 0.5
        e = (np.sqrt(((u - fx) / 0.02) ** 2 + ((v - ecy) / (fh * 0.5)) ** 2) - 1.0) * 0.02
        sd = np.minimum(sd, e)
    core = smoothstep(0.004, -0.004, sd) * facing
    halo = smoothstep(0.045, 0.0, sd) * facing
    return core, halo


# =============================================================================================== leather, cord, cloth
def mat_leather(t, p):
    """Vegetable-tanned / oiled leather: pebble grain, creases, darker oil + dirt in crevices, lighter scuffed
    convex edges (worn top grain), burnished glossy spots where handled. p: color, dark, grain, crease, scuff."""
    P = t.P
    base = np.asarray(p.get("color", C(96, 62, 40)))
    darkc = np.asarray(p.get("dark", C(52, 34, 24)))
    trim = np.clip(t.a3, 0, 1)
    if "trim" in p:
        base = base[None, :] * (1 - trim[:, None]) + np.asarray(p["trim"])[None, :] * trim[:, None]
    f1, f2, cid = voronoi(P, p.get("grain", 140.0), seed=111)
    pebble = (f2 - f1)
    pebble_h = smoothstep(0.0, 0.35, pebble) * t.aa(p.get("grain", 140.0) * 0.6)
    cd = p.get("crease_dir", (1.0, 1.0, 1.0))
    crease = ridged(np.stack([P[:, 0] * cd[0], P[:, 1] * cd[1], P[:, 2] * cd[2]], 1), p.get("crease_f", 9.0), 4, seed=112)
    crease = smoothstep(0.82, 0.97, crease) * p.get("crease", 0.8)
    var = fbm(P, 5.0, 4, seed=113)
    if base.ndim == 2:
        col = base * np.exp(var * 0.35 + (t.rnd - 0.5) * 0.2)[:, None]
    else:
        col = tint(base, var * 0.35 + (t.rnd - 0.5) * 0.2, 1.0)
    col = lerp3(col, darkc, smoothstep(-0.1, 0.6, fbm(P, 2.5, 3, seed=114)) * p.get("mottle", 0.45))
    scuff = t.edge(0.25, 0.8, 0.5, 30.0, seed=115) * p.get("scuff", 0.8)
    col = lerp3(col, np.minimum(col * 1.8 + 0.01, 1.0), scuff * 0.7)
    dirt = t.crevice(0.1, 0.6) * p.get("dirt", 0.6)
    col = lerp3(col, darkc * 0.6, dirt * 0.7)
    col = lerp3(col, darkc * 0.7, crease * p.get("crease_dark", 0.5))
    t.albedo = col * (1 - 0.12 * (1 - pebble_h))[:, None]
    polish = smoothstep(0.2, 0.7, fbm(P, 4.0, 3, seed=116) * 0.5 + 0.4) * p.get("polish", 0.4)
    t.metal = np.zeros(t.n)
    t.rough = np.clip(p.get("rough", 0.62) - polish * 0.2 + scuff * 0.15 + crease * 0.1 + (1 - pebble_h) * 0.06, 0.25, 1)
    t.height = 0.00045 * pebble_h - 0.0012 * crease + 0.0002 * var
    G = t.G
    if p.get("washers"):
        # stacked leather washers: each ring its own tone, compressed dark line between rings
        k = G[:, 0] / p["washers"]
        wid = np.floor(k)
        tone = (cell_rand(np.stack([wid, wid * 0.0, wid * 0.0], 1), 1.0, 117) - 0.5)
        fr = k - wid
        line = smoothstep(0.12, 0.0, np.minimum(fr, 1 - fr))
        t.albedo = t.albedo * np.exp(tone * 0.5)[:, None] * (1 - 0.55 * line)[:, None]
        t.height = t.height - 0.0007 * line
        t.rough = t.rough + 0.08 * line
    if p.get("spiral"):
        # leather strip wrapped in a helix: a0 = angle phase around the item
        ph = G[:, 0] * p["spiral"] - t.a0
        fr = ph - np.floor(ph)
        gap = smoothstep(0.06, 0.0, np.minimum(fr, 1 - fr))
        roll = 1.0 - (2 * fr - 1) ** 2
        t.albedo = t.albedo * (1 - 0.6 * gap)[:, None] * (0.85 + 0.15 * roll)[:, None]
        t.height = t.height + 0.0012 * roll - 0.0012 * gap
    if p.get("seam"):
        # stitched seam (a1 = angle from the seam line, radians; p['seam_r'] = radius -> studs): a dark butt joint
        # and a row of small slanted stitches each side, 3.5 mm from the joint, 7 stitches per inch
        dist = np.abs(np.arctan2(np.sin(t.a1), np.cos(t.a1))) * p.get("seam_r", 0.05)
        seam = smoothstep(0.0022, 0.0006, dist)
        row = smoothstep(0.0016, 0.0005, np.abs(dist - 0.0105))
        ph = G[:, 0] * p.get("spi", 90.0) + dist * 25.0
        dash = smoothstep(0.15, 0.45, 0.5 + 0.5 * np.sin(ph * 2 * math.pi))
        stitch = row * dash * t.aa(p.get("spi", 90.0) * 0.5)
        holes = row * (1 - dash) * t.aa(p.get("spi", 90.0) * 0.5)
        t.albedo = lerp3(t.albedo, t.albedo * 0.45, seam)
        t.albedo = lerp3(t.albedo, t.albedo * 0.7, holes * 0.6)
        t.albedo = lerp3(t.albedo, np.asarray(p.get("thread", C(132, 112, 84))), stitch * 0.85)
        t.rough = t.rough + 0.1 * stitch
        t.height = t.height - 0.0007 * seam + 0.00035 * stitch - 0.0002 * holes
    st = p.get("stitch")
    if st is not None:
        m, thread_h = st(t)
        t.albedo = lerp3(t.albedo, np.asarray(p.get("thread", C(150, 128, 92))), m)
        t.rough = t.rough * (1 - m) + 0.8 * m
        t.height = t.height + thread_h
    t.finish_ao(0.65)


def mat_cord(t, p):
    """Twisted cord / twine wrap. gco x runs along the wrapped item; a0 = angular phase around it (0..1)."""
    G, P = t.G, t.P
    base = np.asarray(p.get("color", C(150, 122, 84)))
    turns = p.get("turns", 40.0)          # wraps per stud along the item
    strands = p.get("strands", 3)
    ang = t.a0
    if p.get("rope"):
        # swept rope, tagged with seed_offset=False: gco = (arc length, section a, section b)
        ang = (np.arctan2(G[:, 2], G[:, 1]) / (2 * math.pi)) % 1.0
    s = G[:, 0] * turns - ang * p.get("around", 1)
    cord = 0.5 - 0.5 * np.cos(2 * math.pi * s)                 # 1 at the cord crest, 0 in the gaps
    twist = 0.5 + 0.5 * np.cos(2 * math.pi * (s * strands + ang * strands * 6.0 + G[:, 0] * turns * 2.0))
    fuzz = t.fbm_aa(P, 300.0, 2, seed=121)
    col = tint(base, fuzz * 0.25 + fbm(P, 6, 3, seed=122) * 0.25 + (twist - 0.5) * 0.25, 1.0)
    col = col * (0.55 + 0.45 * cord)[:, None]
    dirt = t.crevice(0.1, 0.6) * p.get("dirt", 0.5) + smoothstep(0.2, 0.7, fbm(P, 3.0, 3, seed=123)) * p.get("grime", 0.4)
    col = lerp3(col, C(60, 48, 34), np.clip(dirt, 0, 1) * 0.6)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.82 + fuzz * 0.08, 0.5, 1)
    t.height = 0.002 * cord * t.aa(turns) + 0.0005 * twist * t.aa(turns * strands * 2) + 0.0002 * fuzz
    t.finish_ao(0.6)


def weave(u, v, f, t, kind="plain"):
    """Woven cloth height (0..1) in a 2D cloth frame; f threads per stud. kind plain | twill."""
    a = u * f
    b = v * f
    if kind == "twill":
        warp = 0.5 + 0.5 * np.cos(2 * math.pi * a)
        diag = ((np.floor(a) + np.floor(b)) % 4) < 2
        h = np.where(diag, warp * (0.6 + 0.4 * np.abs(np.cos(math.pi * b))), 0.5 + 0.5 * np.cos(2 * math.pi * b))
    else:
        over = ((np.floor(a) + np.floor(b)) % 2) < 1
        h = np.where(over, (0.5 + 0.5 * np.cos(2 * math.pi * a)) * np.abs(np.sin(math.pi * b)) ** 0.5,
                     (0.5 + 0.5 * np.cos(2 * math.pi * b)) * np.abs(np.sin(math.pi * a)) ** 0.5)
    return h * t.aa(f)


def cloth_uv(t, mode="gco", center=(0.0, 0.0)):
    """2D cloth coordinates (studs). gco: piece frame (x along the panel / strip / path); tri: box projection by
    the dominant object-space normal (bags, boxes); cyl: arc length around the object Z axis + height (garments)."""
    G, P, N = t.G, t.P, t.N
    if mode == "tri":
        ax = np.argmax(np.abs(N), axis=1)
        u = np.where(ax == 0, P[:, 1], P[:, 0])
        v = np.where(ax == 2, P[:, 1], P[:, 2])
        return u, v
    if mode == "cyl":
        x, y = P[:, 0] - center[0], P[:, 1] - center[1]
        r = np.sqrt(x * x + y * y)
        return np.arctan2(y, x) * np.maximum(r, 0.05), P[:, 2]
    return G[:, 0], G[:, 1] + G[:, 2]


def mat_canvas(t, p):
    """Waxed cotton canvas / duck: plain weave, uneven dye, darker wax-rubbed creases, lighter worn edges,
    dirt in folds and seams, stains."""
    P = t.P
    base = np.asarray(p.get("color", C(138, 58, 40)))
    u, v = cloth_uv(t, p.get("cloth", "gco"), p.get("center", (0.0, 0.0)))
    w = weave(u, v, p.get("threads", 70.0), t, p.get("kind", "plain"))
    slub = t.fbm_aa(np.stack([u * 4, v * 180.0, P[:, 2] * 4], 1), 1.0, 2, seed=131)
    var = fbm(P, 3.0, 4, seed=132)
    wr = ridged(P * np.array([1.0, 1.0, 2.2]), p.get("wrinkle_f", 7.0), 3, seed=135)
    wrinkle = smoothstep(0.7, 0.95, wr) * p.get("wrinkles", 0.6)
    fade = smoothstep(0.2, 0.9, t.N[:, 2]) * p.get("sun_fade", 0.25)
    col = tint(base, var * 0.22 + slub * 0.1 + (w - 0.5) * 0.08 - wrinkle * 0.25, 1.0)
    col = lerp3(col, col * np.array([1.25, 1.2, 1.18]) + 0.02, fade)
    edge = t.edge(0.25, 0.8, 0.5, 25.0, seed=133) * p.get("edge_wear", 0.7)
    col = lerp3(col, np.minimum(col * 1.6 + np.array([0.04, 0.03, 0.02]), 1), edge * 0.55)
    dirt = np.clip(t.crevice(0.08, 0.55) * 0.8 + smoothstep(0.3, 0.8, fbm(P, 2.0, 4, seed=134)) * p.get("stains", 0.4), 0, 1)
    col = lerp3(col, np.asarray(p.get("dirt_col", C(62, 48, 36))), dirt * 0.55)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(p.get("rough", 0.8) + (w - 0.5) * 0.08 - dirt * 0.1 + edge * 0.08 - wrinkle * 0.05, 0.4, 1)
    t.height = 0.0006 * (w - 0.5) + 0.0004 * slub - 0.0022 * wrinkle
    st = p.get("stitch")
    if st is not None:
        m, h = st(t)
        t.albedo = lerp3(t.albedo, np.asarray(p.get("thread", C(200, 190, 160))), m)
        t.height = t.height + h
    patch = p.get("patch")
    if patch is not None:
        patch(t)
    t.finish_ao(0.65)


def mat_gauze(t, p):
    """Open-weave cotton gauze: cream-white, soft fuzz, grubby where handled; the wound layers show as fine
    concentric rings on a roll's end faces (a0 = 1 there, p['roll'] = (y, z) of the roll axis along X)."""
    P = t.P
    u, v = cloth_uv(t, p.get("cloth", "gco"))
    w = weave(u, v, p.get("threads", 110.0), t, "plain")
    col = tint(np.asarray(p.get("color", C(226, 222, 206))), fbm(P, 4.0, 3, seed=141) * 0.06
               + (w - 0.5) * p.get("weave_contrast", 0.12), 1.0)
    endf = np.clip(t.a0, 0, 1)
    if p.get("mesh"):
        # open gauze: thin warp and weft threads with see-through gaps (darker: deeper layers show through)
        f = p["mesh"]
        fu = 0.5 + 0.5 * np.cos(2 * math.pi * (u * f + fbm(P, 20.0, 2, seed=145) * 0.15))
        fv = 0.5 + 0.5 * np.cos(2 * math.pi * (v * f + fbm(P, 20.0, 2, seed=146) * 0.15))
        thread = np.maximum(smoothstep(0.45, 0.85, fu), smoothstep(0.45, 0.85, fv)) * t.aa(f)
        gap = (1.0 - thread) * t.aa(f) * (1 - endf)
        col = col * (1.0 - p.get("gap_dark", 0.2) * gap)[:, None]
        w = thread
    if "roll" in p:
        cy, cz = p["roll"]
        rr = np.sqrt((P[:, 1] - cy) ** 2 + (P[:, 2] - cz) ** 2)
        layer = p.get("layer", 0.014)
        wob = fbm(P, 30.0, 2, seed=143) * 0.25
        ring = 0.5 + 0.5 * np.cos(2 * math.pi * (rr / layer + wob))
        ring = ring * t.aa(1.0 / layer)
        col = lerp3(col, col * np.array([0.74, 0.72, 0.68]), ring * endf * 0.55)
        w = w * (1 - endf) + ring * endf
    dirt = np.clip(t.crevice(0.1, 0.6) * 0.7 + smoothstep(0.35, 0.9, fbm(P, 3.0, 4, seed=142)) * p.get("stains", 0.35), 0, 1)
    col = lerp3(col, C(150, 132, 104), dirt * 0.5)
    crinkle = t.fbm_aa(np.stack([u * 3.0, v * 40.0, P[:, 2] * 3.0], 1), 1.0, 3, seed=144) * (1 - endf)
    col = col * (1 + 0.06 * crinkle)[:, None]
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.88 + (w - 0.5) * 0.05, 0, 1)
    t.height = 0.0009 * (w - 0.5) + 0.0009 * crinkle
    t.finish_ao(p.get("ao", 0.55))


def mat_linen(t, p):
    """Quilted linen / wool padding (gambeson): coarse plain weave, quilting channels (a0 = channel phase),
    stitched seams in the valleys, sweat / dirt stains, faded high points."""
    P = t.P
    base = np.asarray(p.get("color", C(170, 152, 118)))
    u, v = cloth_uv(t, p.get("cloth", "gco"), p.get("center", (0.0, 0.0)))
    w = weave(u, v, p.get("threads", 55.0), t)
    var = fbm(P, 2.5, 4, seed=151)
    col = tint(base, var * 0.18 + (w - 0.5) * 0.2 + (t.rnd - 0.5) * 0.1, 1.0)
    if p.get("quilt"):
        q = u / p["quilt"] + fbm(P, 3.0, 2, seed=155) * 0.025
        along = v
    else:
        q = t.a0
        along = G_along(t)
    dq = np.abs(q - np.round(q))
    valley = smoothstep(0.1, 0.0, dq)
    pillow = np.sin(np.clip(dq * 2.0, 0, 1) * math.pi * 0.5)      # 0 in the seam, 1 mid-channel
    stitch = smoothstep(0.035, 0.0, dq) * (0.5 + 0.5 * np.sign(np.sin(along * 2 * math.pi * 40.0)))
    strip = np.clip(t.a3, 0, 1)                                  # a3 = 1 on unquilted strips (edges, collars)
    valley, pillow, stitch = valley * (1 - strip), pillow * (1 - strip) + strip, stitch * (1 - strip)
    col = lerp3(col, col * 0.62, valley * 0.6)
    col = col * (1.0 - p.get("pillow_shade", 0.0) * (1.0 - pillow))[:, None]
    col = lerp3(col, np.asarray(p.get("thread", C(120, 100, 72))), stitch * 0.6 * t.aa(45.0))
    edge = t.edge(0.25, 0.8, 0.5, 20.0, seed=152)
    col = lerp3(col, np.minimum(col * 1.25, 1), edge * 0.5)
    dirt = np.clip(t.crevice(0.08, 0.5) * 0.8 + smoothstep(0.2, 0.8, fbm(P, 1.5, 4, seed=153)) * p.get("stains", 0.45), 0, 1)
    col = lerp3(col, C(92, 76, 56), dirt * 0.55)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.86 + (w - 0.5) * 0.06, 0, 1)
    t.height = 0.001 * (w - 0.5) + p.get("puff", 0.006) * pillow - 0.0015 * valley + 0.0004 * stitch
    t.finish_ao(0.65)


def G_along(t):
    return t.G[:, 0]


def mat_fabric(t, p):
    """Charcoal cotton twill (sleeves): diagonal twill weave, heathered yarn, lighter worn fold crests,
    fuzz, dust in folds; a0 = 1 along seams (stitch lines)."""
    P = t.P
    base = np.asarray(p.get("color", C(56, 59, 64)))
    u, v = cloth_uv(t, p.get("cloth", "gco"))
    w = weave(u, v, p.get("threads", 110.0), t, "twill")
    heather = t.fbm_aa(np.stack([u * 2.0, v * 220.0, P[:, 2] * 3.0], 1), 1.0, 3, seed=161)
    var = fbm(P, 3.0, 4, seed=162)
    col = tint(base, heather * 0.18 + var * 0.12 + (w - 0.5) * 0.25, 1.0)
    crest = t.edge(0.15, 0.7, 0.5, 18.0, seed=163) * p.get("wear", 0.7)
    col = lerp3(col, np.minimum(col * 1.7 + 0.01, 1), crest * 0.55)
    dust = np.clip(t.crevice(0.06, 0.5) * 0.7 + smoothstep(0.35, 0.9, fbm(P, 2.0, 4, seed=164)) * p.get("dust", 0.35), 0, 1)
    col = lerp3(col, C(92, 86, 76), dust * 0.35)
    seam = np.clip(t.a0, 0, 1)
    stitch = seam * (0.5 + 0.5 * np.sign(np.sin(G_along(t) * 2 * math.pi * p.get("spi", 60.0))))
    col = lerp3(col, col * 0.55, seam * 0.5)
    col = lerp3(col, np.asarray(p.get("thread", C(78, 80, 84))), stitch * 0.8 * t.aa(60.0))
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.88 + (w - 0.5) * 0.06 - crest * 0.04, 0, 1)
    t.height = 0.0006 * (w - 0.5) + 0.0002 * heather - 0.0008 * seam + 0.0004 * stitch
    t.finish_ao(0.6)


def mat_feather(t, p):
    """Fletching vane: barbs angled back from the rachis (gco x = along the shaft, y = out from the shaft).
    p['per_piece'] = list of param dicts picked by the piece's rnd (rnd < 1/3 -> [0] ...)."""
    if "per_piece" in p:
        pp = p["per_piece"]
        k = np.clip((t.rnd * len(pp)).astype(int), 0, len(pp) - 1)
        alb = np.zeros((t.n, 3))
        rough = np.zeros(t.n)
        hgt = np.zeros(t.n)
        ao = np.ones(t.n)
        for i, q in enumerate(pp):
            sel = np.nonzero(k == i)[0]
            if len(sel) == 0:
                continue
            sub = t.subset(sel)
            mat_feather(sub, q)
            alb[sel], rough[sel], hgt[sel], ao[sel] = sub.albedo, sub.rough, sub.height, sub.ao
        t.albedo, t.rough, t.height, t.ao, t.metal = alb, rough, hgt, ao, np.zeros(t.n)
        return
    G, P = t.G, t.P
    base = np.asarray(p.get("color", C(206, 196, 176)))
    bar = p.get("bars")
    x, y = G[:, 0], np.abs(G[:, 1]) + np.abs(G[:, 2])
    barb = 0.5 + 0.5 * np.cos(2 * math.pi * (x * 1.0 + y * 0.9) * 90.0)
    split = smoothstep(0.6, 0.9, fbm(np.stack([x * 4.0 + y * 3.6, y * 2, x * 0.1], 1), 6.0, 3, seed=171) * 0.5 + 0.5)
    col = tint(base, (barb - 0.5) * 0.2 + fbm(P, 8, 3, seed=172) * 0.2, 1.0)
    if bar is not None:
        bars = 0.5 + 0.5 * np.sin(2 * math.pi * (x + y * 0.6) * bar)
        col = lerp3(col, np.asarray(p.get("bar_col", C(70, 52, 38))), smoothstep(0.55, 0.75, bars) * 0.8)
    rachis = smoothstep(0.012, 0.004, y)
    col = lerp3(col, C(232, 226, 210), rachis * 0.8)
    col = col * (1 - 0.35 * split)[:, None]
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.7 + 0.1 * barb, 0, 1)
    t.height = 0.0005 * barb * t.aa(90.0) - 0.0008 * split + 0.0008 * rachis
    t.finish_ao(0.5)


def mat_horn(t, p):
    """Horn / bone nock overlays: translucent-looking tan to black streaks, polished."""
    G, P = t.G, t.P
    s = fbm(np.stack([G[:, 0] * 2, G[:, 1] * 40, G[:, 2] * 40], 1), 1.0, 4, seed=181)
    col = lerp3(C(196, 176, 140), C(40, 32, 26), smoothstep(-0.3, 0.4, s))
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.28 + s * 0.05, 0, 1)
    t.height = 0.0002 * s
    t.finish_ao(0.5)


# =============================================================================================== glass & water
def mat_glass(t, p):
    """Thick old bottle glass: pale green tint, alpha = opacity (Roblox AlphaMode Transparency), more opaque
    where the glass is thick (base, shoulder, neck: a0 = thickness 0..1), smudges and fingerprints, seed bubbles,
    two mould seams (a1 = distance to seam)."""
    P = t.P
    tint_c = np.asarray(p.get("color", C(150, 190, 168)))
    thick = np.clip(t.a0, 0, 1)
    smudge = smoothstep(0.1, 0.7, fbm(P, 6.0, 5, seed=191) * 0.6 + 0.3) * p.get("smudge", 0.6)
    finger = smoothstep(0.6, 0.95, (0.5 + 0.5 * np.sin(np.linalg.norm(P - np.array([0.1, 0.2, 0.0]), axis=1) * 900.0))
                        * smoothstep(0.05, 0.0, np.linalg.norm(P[:, :2] - np.array([0.12, 0.12]), axis=1) - 0.04)) * t.aa(150.0)
    bubbles_f1, _, _ = voronoi(P, 90.0, seed=192)
    bub = smoothstep(0.08, 0.02, bubbles_f1) * smoothstep(0.6, 0.8, fbm(P, 9.0, 2, seed=193) * 0.5 + 0.5)
    seam = smoothstep(0.004, 0.0, np.abs(t.a1)) * (1 - thick * 0.5)
    dirt = t.crevice(0.15, 0.6) * p.get("dirt", 0.5)
    col = tint(tint_c, fbm(P, 3.0, 3, seed=194) * 0.08, 1.0)
    col = lerp3(col, tint_c * 0.55, thick * 0.6)
    col = lerp3(col, C(150, 140, 120), np.clip(dirt + smudge * 0.25, 0, 1) * 0.6)
    t.albedo = col
    t.alpha = np.clip(p.get("opacity", 0.22) + thick * 0.35 + smudge * 0.12 + finger * 0.1 + dirt * 0.4 + bub * 0.2
                      + seam * 0.15, 0, 1)
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.05 + smudge * 0.25 + finger * 0.2 + dirt * 0.5, 0, 1)
    t.height = 0.0004 * seam - 0.0003 * bub + 0.0002 * fbm(P, 20.0, 3, seed=195) * (1 - thick)
    t.ao = np.ones(t.n)


def mat_water(t, p):
    P = t.P
    col = tint(np.asarray(p.get("color", C(86, 120, 112))), fbm(P, 4.0, 3, seed=201) * 0.1, 1.0)
    t.albedo = col
    t.alpha = np.clip(p.get("opacity", 0.42) + fbm(P, 3.0, 3, seed=202) * 0.05, 0, 1)
    t.metal = np.zeros(t.n)
    t.rough = np.full(t.n, 0.04)
    t.height = 0.0002 * fbm(P, 15.0, 3, seed=203)
    t.ao = np.ones(t.n)


# =============================================================================================== food & plants
def mat_apple(t, p):
    """Apple skin: streaky red blush over yellow-green ground colour (streaks run stem -> calyx), lenticel
    specks, waxy bloom, russet in the stem cavity. Object z axis = core axis."""
    P = t.P
    zc = P[:, 2]
    ang = np.arctan2(P[:, 1], P[:, 0])
    ground = np.asarray(p.get("ground", C(176, 158, 70)))
    red = np.asarray(p.get("red", C(138, 26, 24)))
    deep = np.asarray(p.get("deep", C(84, 14, 18)))
    streak = fbm(np.stack([np.cos(ang) * 6.0, np.sin(ang) * 6.0, zc * 2.0], 1), 1.6, 4, seed=211)
    blush_side = smoothstep(-0.8, 0.6, np.cos(ang - p.get("sun", 0.6)) + fbm(P, 3.0, 3, seed=212) * 0.8)
    red_amt = np.clip(blush_side * 0.7 + streak * 0.3 + p.get("red_base", 0.42), 0, 1)
    fine_streak = 0.5 + 0.5 * np.sin(ang * 74.0 + fbm(P, 9.0, 3, seed=213) * 7.0 + zc * 20.0)
    fine_streak = fine_streak * t.aa(74.0 / (2 * math.pi * 0.12))
    col = lerp3(ground, red, red_amt)
    col = lerp3(col, deep, smoothstep(0.55, 1.0, red_amt) * fine_streak * 0.38)
    col = col * np.exp(fbm(P, 22.0, 3, seed=219) * 0.12)[:, None]
    lf1, _, _ = voronoi(P, 120.0, seed=214)
    lent = smoothstep(0.12, 0.05, lf1) * t.aa(120.0) * smoothstep(0.35, 0.6, cell_rand(P, 120.0, 220))
    col = lerp3(col, C(206, 182, 120), lent * 0.42)
    r = np.sqrt(P[:, 0] ** 2 + P[:, 1] ** 2)
    cavity = smoothstep(0.06, 0.0, r) * (zc > 0)
    russet = cavity * smoothstep(0.0, 0.5, fbm(P, 30.0, 3, seed=215) * 0.5 + 0.6)
    col = lerp3(col, C(130, 96, 52), russet * 0.85)
    calyx = smoothstep(0.05, 0.0, r) * (zc < 0)
    col = lerp3(col, C(80, 66, 40), calyx * 0.8)
    bruise = smoothstep(0.75, 0.95, fbm(P, 5.0, 3, seed=216) * 0.5 + 0.55) * 0.5
    col = lerp3(col, col * np.array([0.6, 0.45, 0.35]), bruise)
    t.albedo = col
    t.metal = np.zeros(t.n)
    bloom = smoothstep(0.2, 0.8, fbm(P, 4.0, 3, seed=217) * 0.5 + 0.5)
    t.rough = np.clip(0.3 + bloom * 0.2 + russet * 0.4 + calyx * 0.3 - lent * 0.05, 0, 1)
    t.height = 0.0003 * lent + 0.0004 * fbm(P, 12.0, 3, seed=218) - 0.0008 * calyx
    t.finish_ao(0.6)


def mat_berry(t, p):
    """Glossy dark-red berries (wild cherry / lingonberry): deep red with lighter flush, tiny pale specks,
    calyx scar (a0 = 1 near the blossom end), very low roughness."""
    P = t.P
    base = np.asarray(p.get("color", C(120, 12, 26)))
    var = fbm(P, 20.0, 3, seed=221)
    col = tint(base, var * 0.35 + (t.rnd - 0.5) * 0.5, 1.0)
    flush = smoothstep(0.2, 0.8, fbm(P, 10.0, 3, seed=222) * 0.5 + 0.5) * 0.4
    col = lerp3(col, C(176, 40, 46), flush * (t.rnd > 0.3))
    sp1, _, _ = voronoi(P, 160.0, seed=223)
    spk = smoothstep(0.12, 0.05, sp1) * t.aa(160.0)
    col = lerp3(col, C(196, 120, 110), spk * 0.4)
    scar = np.clip(t.a0, 0, 1)
    col = lerp3(col, C(40, 26, 20), scar * 0.9)
    t.albedo = col
    t.metal = np.zeros(t.n)
    dark = smoothstep(0.35, 0.9, t.rnd) * p.get("dark_frac", 0.6)
    t.albedo = lerp3(t.albedo, np.asarray(p.get("dark", C(52, 6, 22))), dark * 0.75)
    dimple = t.fbm_aa(P, 140.0, 2, seed=224)
    t.rough = np.clip(p.get("rough", 0.24) + var * 0.05 + scar * 0.55 + (1 - t.aos) * 0.1, 0, 1)
    t.height = 0.0002 * var - 0.0005 * scar + 0.00012 * dimple
    t.finish_ao(0.6)


def mat_meat(t, p):
    """Dried / cured meat (jerky, biltong): dark red-brown muscle with fibres along gco x, darker crusted
    edges, pale fat streaks, cracked pepper specks, oily sheen patches."""
    G, P = t.G, t.P
    fib = t.fbm_aa(np.stack([G[:, 0] * 3.0, G[:, 1] * 180.0, G[:, 2] * 180.0], 1), 1.0, 3, seed=231)
    fib2 = t.fbm_aa(np.stack([G[:, 0] * 1.0, G[:, 1] * 40.0, G[:, 2] * 40.0], 1), 1.0, 3, seed=232)
    col = lerp3(np.asarray(p.get("light", C(92, 38, 24))), np.asarray(p.get("dark", C(44, 18, 11))),
                smoothstep(-0.4, 0.5, fib2 + fib * 0.4))
    col = col * np.exp((t.rnd - 0.5) * 0.3)[:, None]
    fat = smoothstep(0.62, 0.8, fbm(np.stack([G[:, 0] * 2.0, G[:, 1] * 22.0, G[:, 2] * 22.0], 1), 1.0, 3, seed=233) * 0.5 + 0.5)
    col = lerp3(col, np.asarray(p.get("fat", C(178, 146, 98))), fat * 0.55)
    crust = t.edge(0.2, 0.7, 0.4, 30.0, seed=234)
    col = lerp3(col, C(30, 13, 9), crust * 0.65)
    pf1, _, _ = voronoi(P, 50.0, seed=235)
    pep = smoothstep(0.1, 0.05, pf1) * smoothstep(0.4, 0.6, cell_rand(P, 50.0, 236)) * t.aa(50.0)
    col = lerp3(col, C(26, 22, 18), pep * 0.9)
    cut = np.clip(t.a0, 0, 1)
    if cut.max() > 0:
        lean = lerp3(C(132, 34, 30), C(84, 20, 20), smoothstep(-0.3, 0.5, fbm(P, 22.0, 3, seed=238)))
        marb = smoothstep(0.55, 0.75, np.abs(fbm(P, 9.0, 4, seed=239)) * 2.2)
        lean = lerp3(lean, C(212, 186, 150), marb * 0.85)
        rim = smoothstep(0.35, 0.8, t.edge(0.2, 0.7, 0.2, 30.0, seed=240))
        lean = lerp3(lean, C(226, 204, 168), rim * 0.7)
        col = lerp3(col, lean, cut)
        fat = fat * (1 - cut) + marb * cut
    t.albedo = col
    t.metal = np.zeros(t.n)
    sheen = smoothstep(0.1, 0.6, fbm(P, 6.0, 3, seed=237) * 0.5 + 0.4)
    t.rough = np.clip(0.62 - sheen * 0.25 - fat * 0.15 + pep * 0.2 - cut * 0.12, 0.2, 1)
    t.height = (0.0012 * fib + 0.0015 * fib2 + 0.0008 * pep + 0.0004 * fat) * (1 - cut * 0.7)
    t.finish_ao(0.65)


def mat_leaf(t, p):
    """Leaf blade: gco x from base to tip, y across. Midrib + pinnate lateral veins, paler underside (normal z),
    velvety for sage (p['fuzz']), dry edges."""
    G, P = t.G, t.P
    x, y = G[:, 0], G[:, 1]
    length = p.get("length", 0.2)
    xn = np.clip(x / max(length, 1e-3), 0, 1)
    top = np.asarray(p.get("color", C(86, 108, 62)))
    under = np.asarray(p.get("under", C(136, 150, 112)))
    if p.get("side_attr"):
        upv = np.stack([t.a0, t.a1, t.a2], 1)          # the leaf's upper-side direction (per piece)
        side = smoothstep(-0.25, 0.25, np.sum(t.N * upv, 1))
    else:
        side = smoothstep(-0.2, 0.2, t.N[:, 2] * p.get("up_sign", 1.0))
    col = lerp3(under, top, side)
    mid = smoothstep(0.006, 0.0015, np.abs(y))
    lat = 0.5 + 0.5 * np.cos(2 * math.pi * (x - np.abs(y) * 1.4) * p.get("veins", 38.0))
    lat = smoothstep(0.9, 0.98, lat) * smoothstep(0.004, 0.012, np.abs(y))
    col = col * np.exp(fbm(P, 30.0, 3, seed=241) * 0.18 + (t.rnd - 0.5) * 0.25)[:, None]
    col = lerp3(col, np.minimum(col * 1.35 + 0.02, 1), np.clip(mid + lat * 0.6, 0, 1))
    dry = smoothstep(0.5, 0.95, (1 - t.aoi) * 1.2 + fbm(P, 15.0, 3, seed=242) * 0.4) * p.get("dry", 0.4)
    col = lerp3(col, C(130, 112, 66), dry * 0.6)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(p.get("rough", 0.55) + dry * 0.2, 0, 1)
    t.height = -0.0006 * mid - 0.0003 * lat + 0.0002 * fbm(P, 60.0, 2, seed=243) * p.get("fuzz", 0.0) * 4
    t.finish_ao(0.5)


def mat_stem(t, p):
    G, P = t.G, t.P
    s = fbm(np.stack([G[:, 0] * 3, G[:, 1] * 80, G[:, 2] * 80], 1), 1.0, 3, seed=251)
    col = lerp3(np.asarray(p.get("color", C(96, 72, 46))), np.asarray(p.get("dark", C(60, 44, 30))), smoothstep(-0.4, 0.4, s))
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.7 + 0.08 * s, 0, 1)
    t.height = 0.0004 * s
    t.finish_ao(0.5)


def mat_paper(t, p):
    """Paper. p['label'] = True prints an aged tin label around the object Z axis: faded olive ground, a cream
    band with rows of tiny dark 'small print' dashes (unreadable: no text, no logos), rust-red rules, water stains,
    scuffed rims and the glued overlap seam at the back."""
    P = t.P
    col = tint(np.asarray(p.get("color", C(200, 188, 156))), fbm(P, 6.0, 4, seed=261) * 0.1, 1.0)
    rough = np.full(t.n, 0.85)
    h = 0.0002 * fbm(P, 40.0, 3, seed=262)
    if p.get("label"):
        r = np.sqrt(P[:, 0] ** 2 + P[:, 1] ** 2)
        ang = np.arctan2(P[:, 1], P[:, 0])
        u = ang * np.maximum(r, 0.05)
        z = P[:, 2] - p.get("zc", 0.0)
        hz = p.get("half", 0.2)
        ground = tint(np.asarray(p.get("ground", C(92, 98, 58))), fbm(P, 3.0, 4, seed=263) * 0.12, 1.0)
        band = smoothstep(0.085, 0.08, np.abs(z))
        cream = tint(C(204, 192, 152), fbm(P, 5.0, 3, seed=264) * 0.08, 1.0)
        col = lerp3(ground, cream, band)
        rules = (smoothstep(0.006, 0.003, np.abs(np.abs(z) - 0.095))
                 + smoothstep(0.004, 0.002, np.abs(np.abs(z) - hz + 0.02)))
        col = lerp3(col, C(122, 52, 34), np.clip(rules, 0, 1) * 0.9)
        # small print: rows of dashes inside the band, on the front panel only
        fa = p.get("front", math.pi / 2)
        front = smoothstep(1.3, 1.0, np.abs(np.arctan2(np.sin(ang - fa), np.cos(ang - fa))))
        rowc = np.round((z + 0.06) / 0.022)
        row = np.abs(((z + 0.06) / 0.022) - rowc)
        in_rows = smoothstep(0.075, 0.07, np.abs(z)) * smoothstep(0.3, 0.2, row)
        cell = np.floor(u / 0.011)
        word = cell_rand(np.stack([cell, rowc, cell * 0.0], 1), 1.0, 265)
        gap = cell_rand(np.stack([np.floor(u / 0.05), rowc, cell * 0.0], 1), 1.0, 266)
        ink = in_rows * (word > 0.25) * (gap > 0.18) * front * t.aa(90.0)
        col = lerp3(col, C(40, 36, 30), np.clip(ink * 0.85, 0, 1))
        # ageing
        stains = smoothstep(0.55, 0.85, fbm(P, 4.0, 4, seed=267) * 0.5 + 0.5)
        col = lerp3(col, col * np.array([0.72, 0.62, 0.48]), stains * 0.6)
        scuff = t.edge(0.2, 0.7, 0.5, 40.0, seed=268)
        col = lerp3(col, C(196, 186, 160), scuff * 0.6)
        back = np.abs(np.arctan2(np.sin(ang - fa - math.pi), np.cos(ang - fa - math.pi))) * r
        seam = smoothstep(0.03, 0.0, back)
        col = lerp3(col, col * np.array([0.8, 0.72, 0.56]), seam * 0.6)
        rough = np.clip(0.8 + stains * 0.08 - ink * 0.15 + scuff * 0.1, 0, 1)
        h = h + 0.0004 * seam - 0.0002 * ink
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = rough
    t.height = h
    t.finish_ao(0.6)


def mat_bone(t, p):
    """Dry bone: ivory to tan with brown handling stains, fine porous texture, darker in cracks, matte."""
    P = t.P
    var = fbm(P, 7.0, 4, seed=291)
    col = tint(np.asarray(p.get("color", C(208, 194, 164))), var * 0.14, 1.0)
    stain = smoothstep(0.15, 0.7, fbm(P, 3.5, 4, seed=292) * 0.5 + 0.45)
    col = lerp3(col, C(150, 116, 78), stain * 0.55)
    pf1, _, _ = voronoi(P, 140.0, seed=293)
    pore = smoothstep(0.18, 0.06, pf1) * t.aa(140.0)
    col = col * (1 - 0.25 * pore)[:, None]
    fib = t.fbm_aa(np.stack([t.G[:, 0] * 4.0, t.G[:, 1] * 120.0, t.G[:, 2] * 120.0], 1), 1.0, 2, seed=294)
    dirt = t.crevice(0.1, 0.6)
    col = lerp3(col, C(88, 70, 50), dirt * 0.6)
    col = col * np.exp(fib * 0.08)[:, None]
    saw = np.clip(t.a0, 0, 1)
    h_saw = np.zeros(t.n)
    if saw.max() > 0:
        rr = np.sqrt(t.G[:, 1] ** 2 + t.G[:, 2] ** 2) / max(p.get("bone_r", 0.03), 1e-3)
        marrow = smoothstep(0.62, 0.5, rr + fbm(P, 60.0, 2, seed=295) * 0.08)
        spongy = smoothstep(0.85, 0.7, rr) * (1 - marrow)
        sp1, _, _ = voronoi(P, 260.0, seed=296)
        cut = lerp3(C(196, 178, 146), C(150, 118, 88), spongy * smoothstep(0.25, 0.05, sp1) * 0.7)
        cut = lerp3(cut, C(104, 52, 38), marrow * 0.85)
        sawmarks = 0.5 + 0.5 * np.sin(P[:, 0] * 2 * math.pi * 160.0)
        col = lerp3(col, cut * (0.92 + 0.08 * sawmarks)[:, None], saw)
        h_saw = saw * (-0.0012 * marrow + 0.0002 * sawmarks)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.68 + pore * 0.1 - stain * 0.1, 0, 1)
    t.height = (-0.0006 * pore + 0.0003 * fib) * (1 - saw) + h_saw
    t.finish_ao(0.6)


def mat_wax(t, p):
    """Wax / resin seal, string serving: smooth with a soft sheen."""
    P = t.P
    col = tint(np.asarray(p.get("color", C(60, 44, 30))), fbm(P, 30.0, 3, seed=271) * 0.2, 1.0)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.full(t.n, p.get("rough", 0.45))
    t.height = 0.0002 * fbm(P, 40.0, 3, seed=272)
    t.finish_ao(0.5)


def mat_string(t, p):
    """Bow string (waxed linen / Dacron): fine twist along gco x."""
    G, P = t.G, t.P
    tw = 0.5 + 0.5 * np.cos(2 * math.pi * (G[:, 0] * 180.0 + np.arctan2(G[:, 2], G[:, 1]) / (2 * math.pi) * 3))
    col = tint(np.asarray(p.get("color", C(196, 184, 156))), (tw - 0.5) * 0.25 + fbm(P, 10, 3, seed=281) * 0.2, 1.0)
    serve = np.clip(t.a0, 0, 1)
    col = lerp3(col, np.asarray(p.get("serve", C(52, 44, 38))), serve)
    t.albedo = col
    t.metal = np.zeros(t.n)
    t.rough = np.clip(0.6 - serve * 0.15, 0, 1)
    t.height = 0.0002 * tw
    t.finish_ao(0.4)


def mat_ember(t, p):
    t.albedo = np.tile(C(236, 112, 44), (t.n, 1))
    t.metal = np.zeros(t.n)
    t.rough = np.full(t.n, 0.6)


REGISTRY = {
    STEEL: mat_steel, IRON: mat_iron, BRASS: mat_brass, TIN: mat_tin, PAINT: mat_paint, WOOD: mat_wood,
    PLANK: mat_plank, LEATHER: mat_leather, GLOVE: mat_leather, CORD: mat_cord, CANVAS: mat_canvas, GAUZE: mat_gauze,
    LINEN: mat_linen, FABRIC: mat_fabric, FEATHER: mat_feather, HORN: mat_horn, GLASS: mat_glass, WATER: mat_water,
    APPLE: mat_apple, BERRY: mat_berry, MEAT: mat_meat, LEAF: mat_leaf, STEM: mat_stem, PAPER: mat_paper,
    WAX: mat_wax, STRING: mat_string, EMBER: mat_ember, BONE: mat_bone,
}


def synthesize(d, params, default_params=None, asset_names=None, verbose=True):
    """Run every material over the baked data of one texture set.
    params: {(asset_index, material_id): dict} (falls back to default_params[material_id]).
    Returns dict of full-res channel arrays."""
    import time
    cov = d["cov"]
    H, W = cov.shape
    P = d["P"]
    # world size of a texel
    from tex_items import _diff
    lx = np.linalg.norm(_diff(P, cov, 1), axis=2)
    ly = np.linalg.norm(_diff(P, cov, 0), axis=2)
    ts = np.where(cov, 0.5 * (lx + ly), 0.0)
    ts = np.where(ts > 0, ts, np.median(ts[cov]) if cov.any() else 0.005)
    flat = cov.ravel()
    mid_full = np.round(d["M"][..., 0]).astype(np.int64).ravel()
    out = {"albedo": np.zeros((H * W, 3)), "alpha": np.ones(H * W), "rough": np.full(H * W, 0.6),
           "metal": np.zeros(H * W), "height": np.zeros(H * W), "ao": np.ones(H * W)}
    dd = {k: d[k].reshape(H * W, -1) for k in ("P", "N", "G", "M", "A", "O", "E")}
    tsf = ts.ravel()
    codes = np.unique(mid_full[flat])
    for code in codes:
        mat_id = int(code % 100)
        aid = int(code // 100)
        idx = np.nonzero(flat & (mid_full == code))[0]
        if len(idx) == 0:
            continue
        fn = REGISTRY.get(mat_id)
        if fn is None:
            print("WARNING no material for id %d" % mat_id)
            continue
        p = dict((default_params or {}).get(mat_id, {}))
        p.update(params.get((aid, mat_id), {}))
        t0 = time.time()
        t = Texels(dd, idx, tsf)
        fn(t, p)
        out["albedo"][idx] = np.clip(t.albedo, 0, 1)
        out["alpha"][idx] = t.alpha
        out["rough"][idx] = np.clip(t.rough, 0.02, 1)
        out["metal"][idx] = np.clip(t.metal, 0, 1)
        out["height"][idx] = t.height
        out["ao"][idx] = t.ao
        if verbose:
            nm = asset_names[aid] if asset_names and aid < len(asset_names) else str(aid)
            print("  MAT %-14s %-8s %7d texels  px/stud %5.0f  %.1fs" % (nm, NAMES.get(mat_id, mat_id), len(idx),
                                                                      1.0 / max(np.median(tsf[idx]), 1e-6), time.time() - t0))
    for k in out:
        if out[k].ndim == 2:
            out[k] = out[k].reshape(H, W, -1)
        else:
            out[k] = out[k].reshape(H, W)
    return out
