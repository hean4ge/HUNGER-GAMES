"""
style_c_nature.py - Variant C ("smooth stylized realism") organic assets: spruce, oak, boulder.

Every asset is sculpted as a signed-distance field (smooth unions of round cones / ellipsoids / planes with gentle
fBm), meshed with surface nets, decimated to budget and smooth-shaded: closed, rounded volumes with no alpha cards.
Each asset gets ONE unique 1024 texture page: colour (painted gradients x baked AO), OpenGL normal (soft procedural
detail through a Bump node) and roughness.

Each builder returns a dict:
  parts   [(obj, role, detail_fn, part_flags)]   detail_fn(nt, obj_coords) -> (height, aux, bump_strength, dist)
  paint   function(data) -> (srgb H x W x 3, rough H x W)    data = Baker.run() arrays
  attach  {name: (pos, look, up)} in Blender space
  ao      (near, far) bake distances
"""
import math

import numpy as np

import style_c_lib as L
import tex_ground as tg

TAU = 2.0 * math.pi


# =============================================================================================== detail nodes
def det_needles(nt, co):
    """Spruce canopy: soft rounded tufts (0.6-0.9 stud lumps), no fine grain."""
    p = nt.mapping(co, (1.0, 1.0, 1.35))
    v = nt.voronoi(p, 1.05, "F1", "EUCLIDEAN", 1.0, "Distance")
    lump = nt.maprange(v, 0.05, 0.62, 1.0, 0.0, interp="SMOOTHSTEP")
    n = nt.noise(co, 0.55, 2.0, 0.5)
    h = nt.math("MULTIPLY_ADD", n, 0.35, nt.math("MULTIPLY", lump, 0.65))
    return h, nt.noise(co, 0.18, 2.0, 0.5), 0.42, 0.18


def det_spruce_bark(nt, co):
    """Spruce: fine, flaky vertical ridges (stretched noise folded around 0.5), no cell network."""
    p = nt.mapping(co, (3.2, 3.2, 0.7))
    n1 = nt.noise(p, 1.6, 3.0, 0.55)
    fold = nt.math("ABSOLUTE", nt.math("SUBTRACT", n1, 0.5))
    ridge = nt.maprange(fold, 0.0, 0.14, 0.0, 1.0, interp="SMOOTHSTEP")
    n2 = nt.noise(co, 1.8, 2.0, 0.5)
    h = nt.math("MULTIPLY_ADD", n2, 0.35, nt.math("MULTIPLY", ridge, 0.65))
    return h, nt.noise(co, 0.35, 2.0, 0.5), 0.55, 0.06


def det_leaves(nt, co):
    """Oak canopy: rounded leaf-mass lumps."""
    v = nt.voronoi(co, 1.15, "F1", "EUCLIDEAN", 1.0, "Distance")
    lump = nt.maprange(v, 0.05, 0.6, 1.0, 0.0, interp="SMOOTHSTEP")
    v2 = nt.voronoi(co, 2.6, "F1", "EUCLIDEAN", 1.0, "Distance")
    lump2 = nt.maprange(v2, 0.05, 0.55, 1.0, 0.0, interp="SMOOTHSTEP")
    h = nt.math("MULTIPLY_ADD", lump2, 0.3, nt.math("MULTIPLY", lump, 0.7))
    return h, nt.noise(co, 0.16, 2.0, 0.5), 0.38, 0.2


def det_oak_bark(nt, co):
    """Soft, long bark ridges (stretched noise folded around 0.5 = furrows), low contrast."""
    p = nt.mapping(co, (2.3, 2.3, 0.5))
    n1 = nt.noise(p, 1.5, 3.0, 0.55)
    fold = nt.math("ABSOLUTE", nt.math("SUBTRACT", n1, 0.5))
    ridge = nt.maprange(fold, 0.0, 0.16, 0.0, 1.0, interp="SMOOTHSTEP")
    n2 = nt.noise(co, 0.9, 2.0, 0.5)
    h = nt.math("MULTIPLY_ADD", n2, 0.3, nt.math("MULTIPLY", ridge, 0.7))
    return h, nt.noise(co, 0.3, 2.0, 0.5), 0.6, 0.08


def det_rock(nt, co):
    """Soft chisel undulation + a sparse, shallow fracture network (kept low so it never reads as a shell)."""
    e = nt.voronoi(co, 0.42, "DISTANCE_TO_EDGE", "EUCLIDEAN", 1.0, "Distance")
    ridge = nt.maprange(e, 0.0, 0.12, 0.0, 1.0, interp="SMOOTHSTEP")
    n = nt.noise(co, 1.1, 3.0, 0.45)
    h = nt.math("MULTIPLY_ADD", n, 0.8, nt.math("MULTIPLY", ridge, 0.2))
    return h, nt.noise(co, 0.45, 2.0, 0.5), 0.26, 0.12


def buried_ao(P, ao1, ao2):
    """Below the pivot the bake's ground plane makes AO collapse to black; keep buried skirts a neutral dark
    earth instead (they show on slopes)."""
    below = L.ss(0.1, -0.35, P[:, 2])
    return np.maximum(ao1, below * 0.6), np.maximum(ao2, below * 0.7)


# =============================================================================================== spruce
SPRUCE = dict(H=44.0, zc0=6.2, Rb=7.4)


def spruce_crown_r(z):
    H, zc0, Rb = SPRUCE["H"], SPRUCE["zc0"], SPRUCE["Rb"]
    t = np.clip((H - z) / (H - zc0), 0.0, 1.0)
    return Rb * t ** 0.92


def build_spruce(seed=11):
    rng = np.random.RandomState(seed)
    H, zc0 = SPRUCE["H"], SPRUCE["zc0"]
    can = L.SDF(block=3.0)
    tiers = []
    z = zc0
    while z < H - 3.0:
        R = float(spruce_crown_r(z)) * rng.uniform(0.9, 1.07)
        tiers.append((z, max(R, 0.9)))
        z += (0.33 * R + 0.9) * rng.uniform(0.82, 1.18)
    phase = rng.uniform(0, TAU)
    for (zt, R) in tiers:
        n = int(np.clip(round(4.5 + 0.7 * R + rng.uniform(-1.2, 1.2)), 4, 10))
        droop = 0.38 * R * rng.uniform(0.85, 1.15)
        phase += 2.39996
        tilt = rng.uniform(-0.1, 0.1, 2) * R
        can.ellipsoid((0, 0, zt - 0.1 * droop), (0.40 * R + 0.55, 0.40 * R + 0.55, 0.22 * R + 0.55), k=0.6)
        for i in range(n):
            phi = phase + TAU * i / n + rng.uniform(-0.25, 0.25) * TAU / n
            Ln = R * (rng.uniform(0.92, 1.06) if i % 2 == 0 else rng.uniform(0.74, 0.92))
            c, s = math.cos(phi), math.sin(phi)
            dz = tilt[0] * c + tilt[1] * s
            p0 = (0.12 * R * c, 0.12 * R * s, zt + 0.12 * R)
            p1 = (0.52 * Ln * c, 0.52 * Ln * s, zt - 0.14 * droop + 0.5 * dz)
            p2 = (Ln * c, Ln * s, zt - droop * rng.uniform(0.85, 1.12) + dz)
            r0, r1, r2 = 0.13 * R + 0.28, 0.15 * R + 0.27, 0.03 * R + 0.13
            can.chain([p0, p1, p2], [r0, r1, r2], k=0.4, squash=0.6)
            if R > 2.2:
                # side sprays: the bough fans out into 2 drooping tips (ragged, spruce-like edge)
                for side in (-1, 1):
                    if rng.rand() < 0.25:
                        continue
                    ph2 = phi + side * rng.uniform(0.16, 0.26)
                    L2 = Ln * rng.uniform(0.62, 0.8)
                    q0 = np.array(p1) * 0.85 + np.array([0, 0, 0.1])
                    q1 = (L2 * math.cos(ph2), L2 * math.sin(ph2), zt - droop * rng.uniform(0.75, 1.0) + dz)
                    can.round_cone(q0, q1, 0.11 * R + 0.22, 0.03 * R + 0.12, k=0.36, squash=0.58)
    can.round_cone((0, 0, H - 4.2), (0, 0, H), 0.6, 0.07, k=0.5)
    can.displace(0.17, 0.55, 3, seed=seed)
    can.displace(0.06, 1.8, 2, seed=seed + 1)
    Rb = SPRUCE["Rb"]
    canopy = L.sdf_mesh("Spruce_Needles", can, (-Rb - 2.5, -Rb - 2.5, zc0 - 0.5 * Rb - 2.0),
                        (Rb + 2.5, Rb + 2.5, H + 0.6), 0.2, target_tris=9200)

    tr = L.SDF(block=2.0)
    tr.round_cone((0, 0, -0.8), (0, 0, 30.0), 1.0, 0.34, k=0.0)
    for i in range(5):
        th = TAU * i / 5 + rng.uniform(-0.35, 0.35)
        c, s = math.cos(th), math.sin(th)
        ln = rng.uniform(1.9, 2.4)
        tr.round_cone((0.25 * c, 0.25 * s, 1.9), (ln * c, ln * s, -0.45), 0.52, 0.2, k=0.75)
    for i in range(4):
        th = rng.uniform(0, TAU)
        zz = rng.uniform(3.2, 6.0)
        c, s = math.cos(th), math.sin(th)
        ln = rng.uniform(1.1, 1.6)
        tr.round_cone((0.5 * c, 0.5 * s, zz), (ln * c, ln * s, zz - 0.25), 0.16, 0.09, k=0.12)
    tr.displace(0.03, 1.4, 2, seed=seed + 2)
    trunk = L.sdf_mesh("Spruce_Bark", tr, (-3.2, -3.2, -1.3), (3.2, 3.2, 30.6), 0.11, target_tris=1500)

    def paint(d):
        return paint_spruce(d, seed)

    return {
        "parts": [(canopy, "Needles", det_needles, dict(collide=False, collision="Box", castShadow=True)),
                  (trunk, "Bark", det_spruce_bark, dict(collide=True, collision="Hull", castShadow=True))],
        "paint": paint, "attach": {}, "ao": (1.6, 5.0),
        "notes": "Spruce, %.0f studs. Canopy = %d drooping tiers of sculpted boughs (non-colliding, players can hide "
                 "in it); trunk + root flare collide (Hull)." % (H, len(tiers)),
    }


def paint_spruce(d, seed):
    cov = d["cover"]
    P = d["pos"][cov]
    N = d["nrm"][cov]
    pid = d["pid"][cov]
    det = d["det"][cov]
    ao1, ao2 = buried_ao(P, np.clip(d["ao1"][cov], 0, 1), np.clip(d["ao2"][cov], 0, 1))
    H, zc0 = SPRUCE["H"], SPRUCE["zc0"]
    per = tg.Perlin(seed + 7)
    n_lo = per.fbm(P, 0.09, 3)
    n_mid = per.fbm(P, 0.35, 2, offset=(3.1, 1.7, 5.3))
    out = np.zeros((len(P), 3))
    rough = np.zeros(len(P))
    # ---------------- needles
    m = pid == 0
    if m.any():
        p, n = P[m], N[m]
        z = p[:, 2]
        R = np.maximum(spruce_crown_r(z), 0.7)
        r = np.hypot(p[:, 0], p[:, 1]) / R
        hz = np.clip((z - zc0) / (H - zc0), 0, 1)
        up = n[:, 2] * 0.5 + 0.5
        e = (0.46 * L.ss(0.35, 1.0, r) ** 1.3 + 0.28 * up + 0.12 * hz + 0.14 * det[m, 0]
             + 0.06 * n_mid[m] - 0.05)
        base = L.ramp(e, [(0.0, (18, 32, 28)), (0.28, (26, 48, 40)), (0.50, (38, 66, 48)),
                          (0.72, (58, 90, 54)), (0.9, (88, 116, 62)), (1.05, (112, 132, 70))])
        warm = L.mixc(base, base * np.array([1.08, 1.05, 0.86]), np.clip(n_lo[m] * 1.6, 0, 1) * 0.7)
        cool = L.mixc(warm, warm * np.array([0.9, 1.0, 1.1]), np.clip(-n_lo[m] * 1.6, 0, 1) * 0.6)
        lin = L.srgb2lin(cool)
        lin *= ((0.40 + 0.60 * ao1[m] ** 1.1) * (0.70 + 0.30 * ao2[m]))[:, None]
        out[m] = L.lin2srgb(lin)
        rough[m] = 0.80 + 0.06 * (1 - ao1[m]) + 0.03 * n_mid[m]
    # ---------------- bark
    m = pid == 1
    if m.any():
        p, n = P[m], N[m]
        g = det[m, 0]
        base = L.ramp(g + 0.25 * n_mid[m], [(0.0, (56, 40, 32)), (0.35, (80, 58, 44)), (0.65, (102, 76, 58)),
                                           (1.0, (124, 100, 82))])
        soil = L.ss(1.4, 0.0, p[:, 2])
        base = L.mixc(base, base * np.array([0.78, 0.74, 0.7]), soil * 0.6)
        moss = L.ss(0.25, 0.65, n[:, 2] + 0.15 * n_lo[m]) * L.ss(2.8, 0.6, p[:, 2]) * L.ss(-0.1, 0.4, p[:, 2])
        base = L.mixc(base, np.array([74, 90, 46]) / 255.0 * (0.85 + 0.3 * g[:, None]), moss * 0.85)
        lin = L.srgb2lin(base)
        lin *= ((0.38 + 0.62 * ao1[m] ** 1.2) * (0.62 + 0.38 * ao2[m]))[:, None]
        out[m] = L.lin2srgb(lin)
        rough[m] = 0.9 + 0.05 * (1 - g)
    return out, rough


# =============================================================================================== oak
OAK_LIMBS = {
    # name: (points, radii, perch segment index or None)
    "L1": ([(0.3, 0.0, 6.4), (2.6, 0.3, 8.6), (5.4, 0.8, 9.7), (8.2, 1.3, 10.5), (10.6, 1.9, 12.2),
            (12.4, 2.4, 14.4)], [1.02, 0.94, 0.86, 0.72, 0.52, 0.36], 2),
    "L2": ([(-0.2, 0.3, 7.0), (-2.2, 2.0, 9.6), (-4.2, 3.7, 11.4), (-6.4, 5.3, 12.1), (-8.4, 6.8, 13.6),
            (-9.8, 8.0, 15.8)], [1.0, 0.9, 0.82, 0.74, 0.52, 0.36], 2),
    "L3": ([(0.1, -0.3, 6.2), (0.5, -2.8, 7.9), (1.0, -5.6, 8.6), (1.5, -8.4, 9.4), (2.0, -10.8, 11.4),
            (2.4, -12.6, 13.8)], [1.02, 0.92, 0.84, 0.72, 0.52, 0.36], 1),
    "L4": ([(0.1, 0.0, 6.6), (-0.3, -0.3, 10.4), (-0.8, -0.5, 13.8), (-1.0, -0.2, 16.8), (-0.6, 0.4, 19.6)],
           [1.14, 1.0, 0.86, 0.7, 0.5], None),
    "L5": ([(-0.6, -0.4, 12.4), (1.8, -2.6, 13.6), (4.0, -4.6, 14.3), (6.2, -6.4, 15.4), (7.8, -7.8, 17.2)],
           [0.86, 0.82, 0.76, 0.56, 0.38], 1),
    "L6": ([(-0.4, -0.2, 9.8), (-2.8, -1.2, 11.6), (-5.4, -2.0, 12.8), (-8.0, -2.6, 14.6), (-10.0, -3.2, 16.8)],
           [0.8, 0.72, 0.64, 0.48, 0.34], None),
    "L7": ([(0.2, 0.4, 7.2), (1.8, 2.6, 9.8), (3.4, 5.0, 12.0), (5.0, 7.4, 14.2), (6.0, 9.4, 16.4)],
           [0.82, 0.72, 0.62, 0.48, 0.34], None),
    "U1": ([(-1.0, -0.2, 16.8), (-3.6, -2.2, 18.8), (-5.8, -3.8, 20.4)], [0.56, 0.42, 0.28], None),
    "U2": ([(-0.6, 0.4, 19.6), (1.4, 2.0, 21.4), (3.2, 3.6, 22.6)], [0.48, 0.38, 0.26], None),
    "U3": ([(-0.6, 0.4, 19.6), (-1.2, 1.0, 22.4), (-1.0, 0.6, 24.4)], [0.44, 0.32, 0.22], None),
}
OAK_TWIGS = {   # limb -> extra twig tips from its last point
    "L1": [(13.8, 1.2, 17.0), (12.0, 4.8, 16.4)],
    "L2": [(-11.0, 7.2, 18.0), (-9.0, 10.2, 17.2)],
    "L3": [(1.0, -14.2, 16.2), (4.2, -13.4, 15.6)],
    "L5": [(9.2, -6.6, 19.0), (7.6, -10.0, 18.4)],
    "L6": [(-11.8, -2.0, 18.6), (-10.6, -5.6, 18.2)],
    "L7": [(7.8, 9.6, 18.2), (4.6, 11.2, 17.6)],
}
OAK_CROWN = dict(c=(0.0, -1.0, 18.5), r=(16.5, 16.5, 10.0))


def build_oak(seed=23):
    rng = np.random.RandomState(seed)
    wood = L.SDF(block=2.5)
    for i in range(6):
        th = TAU * i / 6 + rng.uniform(-0.3, 0.3)
        c, s = math.cos(th), math.sin(th)
        ln = rng.uniform(2.5, 3.0)
        wood.round_cone((0.5 * c, 0.5 * s, 2.3), (ln * c, ln * s, -0.55), 0.95, 0.34, k=0.95)
    wood.chain([(0, 0, -0.8), (0.05, 0.0, 3.5), (0.15, 0.1, 6.6)], [1.62, 1.4, 1.3], k=0.5)
    tips = []
    drops = []
    perches = []
    for name, (pts, radii, perch) in OAK_LIMBS.items():
        wood.chain(pts, radii, k=0.45)
        for tw in OAK_TWIGS.get(name, []):
            mid = (np.array(pts[-1]) * 0.45 + np.array(tw) * 0.55) + np.array([0, 0, 0.5])
            wood.chain([pts[-1], tuple(mid), tw], [radii[-1] * 0.85, radii[-1] * 0.62, 0.17], k=0.25)
            tips.append(tw)
        if name not in OAK_TWIGS:
            tips.append(pts[-1])
        if name in ("L1", "L2", "L3", "L5", "L6", "L7"):
            # a drooping outer branch: the crown skirts down past the perches like an open-grown oak
            base = np.array(pts[4], float)
            out = base[:2] / max(np.linalg.norm(base[:2]), 1e-6)
            tip = base + np.array([out[0] * 2.5, out[1] * 2.5, -1.7])
            mid = base + np.array([out[0] * 1.4, out[1] * 1.4, -0.4])
            wood.chain([tuple(base), tuple(mid), tuple(tip)], [radii[4] * 0.7, 0.26, 0.16], k=0.25)
            drops.append(tip)
        if perch is not None:
            a, b = np.array(pts[perch]), np.array(pts[perch + 1])
            r = 0.5 * (radii[perch] + radii[perch + 1])
            mid = 0.5 * (a + b)
            perches.append(((mid[0], mid[1], mid[2] + r * 0.98), tuple(b - a), 2 * r))
    wood.displace(0.05, 0.9, 2, seed=seed)
    bark = L.sdf_mesh("Oak_Bark", wood, (-14.6, -15.6, -1.4), (16.4, 13.6, 25.2), 0.13, target_tris=4800)

    can = L.SDF(block=3.0)
    clumps = []
    for t in tips:                                   # twig tips: the outer crown
        t = np.array(t, float)
        clumps.append((t + np.array([0, 0, 0.5]), rng.uniform(2.9, 3.5)))
    for t in drops:                                  # drooping skirt clumps, merged into the crown above
        clumps.append((np.array(t, float) + np.array([0, 0, 1.1]), rng.uniform(3.1, 3.6)))
    for name, (pts, radii, perch) in OAK_LIMBS.items():
        if len(pts) >= 5:                            # leaf masses along the outer limbs bring the crown down
            for j in ((4,) if perch is not None else (3, 4)):
                p = np.array(pts[j], float)
                side = np.array([rng.uniform(-1, 1), rng.uniform(-1, 1), 0.0])
                clumps.append((p + side * 0.8 + np.array([0, 0, 2.2]), rng.uniform(2.6, 3.2)))
    for cpos, R in [((-1.0, 0.4, 23.6), 4.2), ((2.6, 2.6, 22.2), 3.6), ((-4.8, -3.0, 21.2), 3.8),
                    ((4.4, -3.6, 20.2), 3.6), ((-3.2, 4.4, 20.4), 3.7), ((0.8, -7.4, 18.6), 3.4),
                    ((-7.4, 1.6, 19.2), 3.4), ((7.4, 3.4, 18.6), 3.4), ((0.6, 7.0, 19.4), 3.2),
                    ((-6.0, -7.6, 17.8), 3.0), ((9.6, -2.0, 17.0), 3.0)]:
        clumps.append((np.array(cpos, float), R))
    # one crown core so the clumps read as lobes of a single mass (not separate puffs)
    can.ellipsoid((0.0, -0.6, 19.0), (11.0, 11.0, 4.8), rz_bottom=3.6, k=1.4)
    can.ellipsoid((-0.6, 0.2, 22.2), (6.5, 6.5, 3.4), k=1.2)
    for (cpos, R) in clumps:
        can.ellipsoid(cpos, (R, R * rng.uniform(0.9, 1.05), 0.78 * R), rz_bottom=0.62 * R, k=1.5)
    for (cpos, R) in clumps:
        nsub = rng.randint(7, 11)
        ph = rng.uniform(0, TAU)
        for j in range(nsub):
            az = ph + TAU * j / nsub + rng.uniform(-0.35, 0.35)
            el = rng.uniform(-0.1, 1.0)
            rr = R * rng.uniform(0.26, 0.38)
            off = R * 0.8 * np.array([math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el) * 0.75])
            can.sphere(cpos + off, rr, k=0.45)
    can.displace(0.36, 0.28, 3, seed=seed + 3)
    can.displace(0.16, 0.75, 2, seed=seed + 4)
    can.displace(0.06, 1.8, 2, seed=seed + 5)
    leaves = L.sdf_mesh("Oak_Leaves", can, (-19.5, -21.5, 6.2), (21.0, 18.5, 30.5), 0.22, target_tris=9800)

    attach = {}
    for i, (pos, look, width) in enumerate(perches):
        lk = np.array(look, float)
        lk[2] = 0.0
        attach["Perch%d" % (i + 1)] = (pos, tuple(lk / np.linalg.norm(lk)), (0, 0, 1))

    def paint(d):
        return paint_oak(d, seed)

    return {
        "parts": [(leaves, "Leaves", det_leaves, dict(collide=False, collision="Box", castShadow=True)),
                  (bark, "Bark", det_oak_bark, dict(collide=True, collision="PreciseConvexDecomposition",
                                                    castShadow=True, tags=["Climbable"]))],
        "paint": paint, "attach": attach, "ao": (1.8, 6.0),
        "perchWidths": [round(p[2], 2) for p in perches],
        "notes": "Broadleaf oak. Bark part (trunk + limbs) is climbable: tag Climbable, PreciseConvexDecomposition; "
                 "Perch1-%d sit on the level tops of standable limbs (look = along the limb). Leaves are a "
                 "non-colliding sculpted crown of %d clumps." % (len(perches), len(clumps)),
    }


def paint_oak(d, seed):
    cov = d["cover"]
    P = d["pos"][cov]
    N = d["nrm"][cov]
    pid = d["pid"][cov]
    det = d["det"][cov]
    ao1, ao2 = buried_ao(P, np.clip(d["ao1"][cov], 0, 1), np.clip(d["ao2"][cov], 0, 1))
    per = tg.Perlin(seed + 9)
    n_lo = per.fbm(P, 0.07, 3)
    n_mid = per.fbm(P, 0.3, 2, offset=(1.3, 4.1, 2.2))
    out = np.zeros((len(P), 3))
    rough = np.zeros(len(P))
    m = pid == 0
    if m.any():
        p, n = P[m], N[m]
        c = np.array(OAK_CROWN["c"])
        rr = np.array(OAK_CROWN["r"])
        q = np.linalg.norm((p - c) / rr, axis=1)
        hz = np.clip((p[:, 2] - 11.0) / 17.0, 0, 1)
        up = n[:, 2] * 0.5 + 0.5
        e = 0.36 * up + 0.28 * L.ss(0.45, 1.05, q) + 0.16 * hz + 0.16 * det[m, 0] + 0.06 * n_mid[m] - 0.03
        base = L.ramp(e, [(0.0, (24, 36, 24)), (0.30, (34, 52, 30)), (0.52, (52, 74, 38)), (0.74, (78, 100, 46)),
                          (0.92, (104, 122, 56)), (1.05, (120, 134, 64))])
        yel = L.mixc(base, base * np.array([1.08, 1.04, 0.86]), np.clip(n_lo[m] * 1.7, 0, 1) * 0.7)
        blu = L.mixc(yel, yel * np.array([0.9, 0.98, 1.06]), np.clip(-n_lo[m] * 1.7, 0, 1) * 0.6)
        lin = L.srgb2lin(blu)
        lin *= ((0.40 + 0.60 * ao1[m] ** 1.15) * (0.66 + 0.34 * ao2[m]))[:, None]
        out[m] = L.lin2srgb(lin)
        rough[m] = 0.74 + 0.08 * (1 - ao1[m]) + 0.03 * n_mid[m]
    m = pid == 1
    if m.any():
        p, n = P[m], N[m]
        g = det[m, 0]
        base = L.ramp(0.55 * g + 0.25 + 0.25 * n_mid[m], [(0.0, (58, 50, 42)), (0.4, (80, 70, 58)),
                                                         (0.7, (98, 88, 74)), (1.0, (116, 106, 90))])
        soil = L.ss(1.6, 0.0, p[:, 2])
        base = L.mixc(base, base * np.array([0.8, 0.74, 0.68]), soil * 0.6)
        moss = L.ss(0.55, 0.9, n[:, 2] + 0.25 * n_lo[m]) * L.ss(1.0, 3.0, p[:, 2]) * (0.5 + 0.5 * g)
        north = L.ss(0.2, 0.9, -n[:, 1]) * L.ss(4.5, 1.2, p[:, 2]) * L.ss(0.3, 1.0, p[:, 2]) * 0.5
        mm = np.clip(moss + north, 0, 1)
        base = L.mixc(base, np.array([66, 82, 42]) / 255.0 * (0.85 + 0.3 * g[:, None]), mm * 0.7)
        lin = L.srgb2lin(base)
        lin *= ((0.40 + 0.60 * ao1[m] ** 1.2) * (0.6 + 0.4 * ao2[m]))[:, None]
        out[m] = L.lin2srgb(lin)
        rough[m] = 0.88 + 0.06 * (1 - g) + 0.03 * mm
    return out, rough


# =============================================================================================== boulder
def build_boulder(seed=5):
    rng = np.random.RandomState(seed)
    c = np.array([0.0, 0.0, 1.5])
    E = np.array([3.5, 2.9, 2.7])
    planes = []
    # a chunky block: side planes leaning in (wider base), one big sloping top facet + a smaller one, chamfers on
    # the shoulders and one deeper spall facet on a corner
    for i in range(7):
        th = TAU * i / 7 + rng.uniform(-0.25, 0.25)
        planes.append((th, rng.uniform(0.0, 0.32), rng.uniform(0.8, 0.92)))
    top = rng.uniform(0, TAU)
    planes.append((top, 1.02, 0.8))
    planes.append((top + math.pi * rng.uniform(0.7, 1.3), 1.32, 0.86))
    for i in range(9):
        planes.append((TAU * i / 9 + rng.uniform(-0.3, 0.3), rng.uniform(0.42, 0.95), rng.uniform(0.79, 0.9)))
    planes.append((rng.uniform(0, TAU), 0.42, 0.7))
    pl = []
    for th, el, f in planes:
        nv = np.array([math.cos(el) * math.cos(th), math.cos(el) * math.sin(th), math.sin(el)])
        pl.append((nv, math.sqrt(((E * nv) ** 2).sum()) * f))
    pl.append((np.array([0.0, 0.0, -1.0]), c[2] + 0.45))
    Nm = np.array([p[0] for p in pl])
    Hm = np.array([p[1] for p in pl])
    k = 0.11

    def field(P):
        Q = P - c
        d_ell = L.sd_ellipsoid(Q, E)
        D = Q @ Nm.T - Hm[None, :]
        mx = D.max(1)
        d_poly = mx + k * np.log(np.exp((D - mx[:, None]) / k).sum(1))
        return 0.95 * d_poly + 0.05 * d_ell

    sdf = L.SDF(block=2.0)
    sdf.func(field, c - E - 0.8, c + E + 0.8)
    sdf.displace(0.06, 0.6, 3, seed=seed)
    sdf.displace(0.02, 2.0, 2, seed=seed + 1)
    rock = L.sdf_mesh("Boulder_Rock", sdf, c - E - 0.6, c + E + 0.6, 0.06, target_tris=1800)

    def paint(d):
        return paint_boulder(d, seed)

    return {"parts": [(rock, "Rock", det_rock, dict(collide=True, collision="Hull", castShadow=True))],
            "paint": paint, "attach": {}, "ao": (0.7, 2.6),
            "notes": "Softly bevelled boulder (rounded facets), ~6.3 x 5.1 studs, sinks 0.45 into the terrain."}


def paint_boulder(d, seed):
    cov = d["cover"]
    P = d["pos"][cov]
    N = d["nrm"][cov]
    det = d["det"][cov]
    ao1, ao2 = buried_ao(P, np.clip(d["ao1"][cov], 0, 1), np.clip(d["ao2"][cov], 0, 1))
    per = tg.Perlin(seed + 3)
    facet = per.fbm(N * 1.7 + P * 0.04, 1.0, 2)
    n_lo = per.fbm(P, 0.25, 3, offset=(2.0, 7.0, 1.0))
    g = det[:, 0]
    tone = 0.46 + 0.42 * facet + 0.22 * (N[:, 2]) + 0.1 * (g - 0.5)
    base = L.ramp(tone, [(0.0, (70, 68, 64)), (0.35, (90, 87, 82)), (0.6, (106, 102, 96)),
                         (0.85, (122, 118, 110)), (1.1, (138, 133, 124))])
    base = L.mixc(base, base * np.array([1.05, 1.0, 0.92]), np.clip(n_lo, 0, 1) * 0.6)
    base = L.mixc(base, base * np.array([0.94, 0.98, 1.04]), np.clip(-n_lo, 0, 1) * 0.6)
    F1, F2, _ = tg.worley(P, 1.3, seed=seed + 11)
    lich = L.ss(0.30, 0.16, F1) * L.ss(-0.2, 0.3, N[:, 2]) * L.ss(0.0, 0.3, n_lo + 0.1)
    base = L.mixc(base, np.array([164, 162, 142]) / 255.0, lich * 0.45)
    moss = L.ss(0.42, 0.72, N[:, 2] + 0.28 * per.fbm(P, 0.55, 3, offset=(5, 5, 5))) * L.ss(1.4, 2.6, P[:, 2])
    mcol = L.ramp(ao1 * 0.6 + g * 0.4, [(0.0, (50, 62, 36)), (0.6, (70, 86, 44)), (1.0, (92, 106, 54))])
    base = L.mixc(base, mcol, moss * 0.92)
    dirt = L.ss(0.9, 0.05, P[:, 2])
    base = L.mixc(base, np.array([88, 78, 64]) / 255.0, dirt * 0.65)
    # painted form: soft highlight on convex bevels, a touch of shade in concave creases
    pnt = d["pnt"][cov]
    base *= (1.0 + 0.16 * L.ss(0.515, 0.6, pnt) * (1 - moss) - 0.12 * L.ss(0.485, 0.42, pnt))[:, None]
    lin = L.srgb2lin(np.clip(base, 0, 1))
    lin *= ((0.48 + 0.52 * ao1 ** 1.2) * (0.74 + 0.26 * ao2))[:, None]
    out = L.lin2srgb(lin)
    rough = 0.84 + 0.04 * (1 - g) + 0.08 * moss
    return out, rough
