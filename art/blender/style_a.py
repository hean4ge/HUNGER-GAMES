"""
style_a.py - LAST STANDING style test, Variant A: "Low-poly realism" (Blender 5.3, headless).

The user found the photo-textured trees, buildings and grainy terrain variants tacky and asked for assets made by us
in Blender, "realistic blockish": Roblox-flavoured chunky geometric forms with realistic proportions, colour and
lighting. This script makes the small style-test set for direction A, using only procedural / hand-placed geometry
and Blender-baked textures (no downloaded models or textures, no AI images):

  StyleA_Spruce       ~42-stud spruce: 7-sided tapered trunk with root flare, drooping star-lobed faceted needle tiers,
                      dead twig stubs below the crown
  StyleA_Oak          ~27-stud oak: 9-sided trunk + buttress roots, 6 limbs (2 standable: Perch1-2, ~9 up) with
                      secondary branches, ~60 flat-bottomed convex-hull foliage clumps
  StyleA_HunterCabin  hewn-log cabin, 16 x 12 log walls + 5-deep porch, door opening 4 x 7.5 (door open inward),
                      geometric shingle strips, fieldstone chimney and foundation, 3 windows, small interior
  StyleA_Boulder      ~6-stud jointed boulder with crisp large facets (two overlapping blocks + a spall)
  StyleA_PebblePath / StyleA_ForestFloor   tiling terrain MaterialVariant maps (Color, Normal, Roughness; 1024 px)

How the look is made
- Geometry: flat-shaded facets, sized to the object (1-2.5 studs on trees and the cabin, 0.5-2 on the boulder).
  Canopies are closed faceted volumes (no alpha cards); trunks are tapered faceted prisms.
- Colour: every face corner gets a painted colour (palette + soft gradients: base-to-tip, inside-to-outside,
  per-volume and per-facet jitter), plus a very soft object-space colour drift; Cycles bakes that, two ambient
  occlusion radii and a bevel/bark normal into ONE texture set per asset (Color, Normal, Roughness). The baked
  textures carry only low-frequency information; the facets and the lighting carry the realism.
- Ground tiles: discrete modelled pebbles / leaves / twigs / moss rendered orthographically (seamless wrap copies),
  with soft contact AO and no photo grain.

Run
  blender --background --factory-startup --python art/blender/style_a.py -- <out_dir> <preview_dir> [stages]
  stages: comma list of ground, assets, preview (default: all three)
  out_dir     default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/StyleTest/A
  preview_dir default art/previews/StyleTest/A
Outputs
  <out_dir>/StyleTest_A.glb, StyleTest_A.manifest.json, textures/*.png (upload), textures/glb_only/*_MR.png (embedded
  packed metallicRoughness copies, never upload), previews in <preview_dir>.
"""
import json
import math
import os
import random
import struct
import sys
import tempfile
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)
import tex_ground as tg  # noqa: E402  shared helpers: PNG writer, push-pull fill, periodic noise, GPU setup

TAU = 2.0 * math.pi
UP = Vector((0.0, 0.0, 1.0))
T0 = time.time()


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
EXPORTS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")
OUT = os.path.abspath(ARGV[0]) if len(ARGV) > 0 else os.path.join(EXPORTS, "StyleTest", "A")
PREV = (os.path.abspath(ARGV[1]) if len(ARGV) > 1
        else os.path.normpath(os.path.join(HERE, "..", "previews", "StyleTest", "A")))
STAGES = set((ARGV[2] if len(ARGV) > 2 else "ground,assets,preview").split(","))
TEX = os.path.join(OUT, "textures")
GLB_ONLY = os.path.join(TEX, "glb_only")
EXPORT_ROOT = os.path.dirname(os.path.dirname(OUT))           # BlenderExports: manifest paths are relative to it
REL_TEX = os.path.relpath(TEX, EXPORT_ROOT).replace("\\", "/")
REL_OUT = os.path.relpath(OUT, EXPORT_ROOT).replace("\\", "/")
WORK = os.path.join(tempfile.gettempdir(), "StyleA_build")
GLB_NAME = "StyleTest_A"
for _d in (OUT, TEX, GLB_ONLY, PREV, WORK):
    os.makedirs(_d, exist_ok=True)

STYLE_RULES = [
    "True-scale realistic silhouettes (1 stud = 0.28 m) built from a few chunky volumes; never alpha cards, photo "
    "textures or texture noise.",
    "Flat-shaded facets sized to the object: 1-2.5 studs on trees and buildings, 0.5-1.5 on rocks and props, "
    "nothing under ~0.1 stud except trim.",
    "Foliage is closed faceted volumes: conifers as drooping star-lobed tiers, broadleaf as flat-bottomed "
    "convex-hull clumps on visible branches; trunks are tapered 7-9-sided prisms with root flare.",
    "Colour is painted, not detailed: dark inside/underneath to light tips/tops, +-6% per volume and +-3% per facet, "
    "slight warm/cool hue drift.",
    "One baked set per asset (Color/Normal/Roughness, 512-1024 px, ~10-25 px/stud): two-radius AO multiplied into "
    "Color at 60-78%; the normal map only rounds edges (bevel 0.03-0.12) plus broad bark plates or adze dimples.",
    "Built things are assembled from real members: octagonal hewn logs with chamfers, proud corner ends and recessed "
    "chinking; plank-by-plank decks; single fieldstones with mortar gaps; shingles as staggered tilted strips.",
    "Muted mid-value palette: needles 26-98 green, leaves 30-108, bark 66-114, weathered wood 96-132, stone "
    "93-146, chinking ~165; no pure black/white, no saturated accents on world assets.",
    "Matte surfaces (roughness 0.8-0.95, metal 0) so Roblox Realistic lighting and cast shadows do the shading; "
    "glass is the only glossy surface.",
    "Terrain tiles are modelled at true scale from discrete shapes (rounded pebbles, folded leaves, duff flakes, "
    "twigs, moss) with soft contact AO and low value contrast, so they stay calm at distance; seamless, 8-10 "
    "StudsPerTile.",
    "Budgets: trees 3.5-5k tris, cabin ~16k split by collision part (each <5k), boulders <300; pipeline collision "
    "rules (Hull trunks/roofs/rocks, PreciseConvexDecomposition walls and climbable limbs, canopies non-colliding).",
]


# =============================================================================================== colour helpers
def s2l(c):
    """sRGB 0-255 -> linear 0-1 (numpy)."""
    return tg.srgb_to_lin(np.asarray(c, np.float64) / 255.0)


def l2s255(c):
    return np.clip(tg.lin_to_srgb(np.asarray(c, np.float64)) * 255.0, 0, 255)


def hashf(x, salt=0):
    """Deterministic 0..1 hash of integer array x."""
    x = np.asarray(x).astype(np.uint64)
    x = (x * np.uint64(2654435761) + np.uint64((salt * 7919 + 104729) & 0xFFFFFFFF)) & np.uint64(0xFFFFFFFF)
    x ^= x >> np.uint64(16)
    x = (x * np.uint64(0x45D9F3B)) & np.uint64(0xFFFFFFFF)
    x ^= x >> np.uint64(16)
    x = (x * np.uint64(0x45D9F3B)) & np.uint64(0xFFFFFFFF)
    x ^= x >> np.uint64(16)
    return (x & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


def lerp3(a, b, t):
    a = np.asarray(a, np.float64)
    b = np.asarray(b, np.float64)
    t = np.asarray(t, np.float64)
    return a + (b - a) * t[..., None]


def ramp3(stops, t):
    """Piecewise-linear colour ramp. stops: [(pos, rgb)...] sorted; t: (n,)."""
    t = np.clip(np.asarray(t, np.float64), stops[0][0], stops[-1][0])
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= p0) & (t <= p1)
        u = (t[m] - p0) / max(p1 - p0, 1e-6)
        out[m] = lerp3(c0, c1, u)
    return out


def smooth01(e0, e1, x):
    return tg.smoothstep(e0, e1, x)


def jitter(c, vol, fid, kv=0.06, kf=0.03, kh=0.02, salt=0):
    """Per-volume value + hue jitter and per-facet value jitter (sRGB 0-255 colours)."""
    rv = hashf(vol, salt) * 2 - 1
    rf = hashf(fid, salt + 11) * 2 - 1
    rh = hashf(vol, salt + 23) * 2 - 1
    c = c * (1.0 + kv * rv + kf * rf)[:, None]
    c = c + (kh * 255.0 * rh)[:, None] * np.array([0.8, 0.25, -0.9])
    return c


# =============================================================================================== material keys
# key -> (roughness, bevel radius for the baked normal, bark-plate bump mask, adze-dimple bump mask)
MATS = {
    "bark_spr": (0.9, 0.07, 1.0, 0.0), "root_spr": (0.92, 0.06, 0.6, 0.0), "needle": (0.86, 0.0, 0.0, 0.0),
    "deadwood": (0.9, 0.0, 0.0, 0.0), "bark_oak": (0.9, 0.09, 1.0, 0.0), "limb_oak": (0.9, 0.07, 0.0, 0.5),
    "leaf": (0.8, 0.0, 0.0, 0.0), "log": (0.86, 0.11, 0.0, 1.0), "log_end": (0.9, 0.06, 0.0, 0.0),
    "chink": (0.95, 0.0, 0.0, 0.0), "shingle": (0.9, 0.035, 0.0, 0.0), "ridge": (0.88, 0.05, 0.0, 0.4),
    "deck": (0.88, 0.04, 0.0, 0.0), "plank": (0.82, 0.045, 0.0, 0.25), "post": (0.85, 0.08, 0.0, 0.8),
    "door": (0.8, 0.03, 0.0, 0.0), "iron": (0.62, 0.02, 0.0, 0.0), "frame": (0.84, 0.04, 0.0, 0.3),
    "glass": (0.1, 0.0, 0.0, 0.0), "stone": (0.88, 0.07, 0.0, 0.0), "mortar": (0.95, 0.0, 0.0, 0.0),
    "flue": (0.95, 0.0, 0.0, 0.0), "fstone": (0.9, 0.08, 0.0, 0.0), "rock": (0.86, 0.1, 0.0, 0.0),
    "cloth": (0.95, 0.03, 0.0, 0.0),
}
MK = list(MATS.keys())
MKI = {k: i for i, k in enumerate(MK)}


def shade(mk, P, N, G, VOL, FID, ctx):
    """Painted colour per face corner. Returns sRGB (n,3) 0-255 and an optional roughness override (n,) or None."""
    n = len(P)
    rough = None
    z = P[:, 2]
    if mk in ("bark_spr", "root_spr"):
        t = np.clip(z / 40.0, 0, 1)
        c = lerp3((66, 52, 44), (100, 82, 68), t ** 0.7)
        if mk == "root_spr":
            c = np.tile(np.array([[64, 52, 43]], np.float64), (n, 1))
        c = c * np.where(N[:, 2] < -0.3, 0.85, 1.0)[:, None]
        c = jitter(c, VOL, FID, 0.04, 0.05, 0.01, 1)
    elif mk == "needle":
        t = ctx["crown_t"](z)
        c = ramp3([(0.0, (26, 42, 33)), (0.45, (40, 64, 44)), (0.82, (54, 82, 50)), (1.0, (70, 98, 58))], G)
        c = c * (0.9 + 0.16 * t)[:, None] + (t * 6.0)[:, None] * np.array([0.6, 1.0, -0.2])
        c = c * np.where(N[:, 2] < -0.15, 0.78, 1.0)[:, None]
        c = jitter(c, VOL, FID, 0.06, 0.035, 0.012, 2)
    elif mk == "deadwood":
        c = lerp3((104, 96, 86), (82, 74, 66), np.clip(G, 0, 1))
        c = jitter(c, VOL, FID, 0.06, 0.03, 0.0, 3)
    elif mk in ("bark_oak", "limb_oak"):
        t = np.clip(z / 20.0, 0, 1)
        c = lerp3((84, 80, 70), (114, 106, 94), np.clip(t * 1.6, 0, 1))
        # damp mossy foot on the north (-Y) side of the trunk base
        moss = smooth01(1.8, 0.2, z) * smooth01(0.2, -0.7, N[:, 1]) * 0.55
        c = lerp3(c, (74, 84, 50), moss)
        c = c * np.where(N[:, 2] < -0.3, 0.85, 1.0)[:, None]
        c = jitter(c, VOL, FID, 0.04, 0.05, 0.012, 4)
    elif mk == "leaf":
        c = ramp3([(0.0, (30, 44, 24)), (0.4, (46, 66, 32)), (0.75, (66, 88, 40)), (1.0, (88, 108, 48))], G)
        c = jitter(c, VOL, FID, 0.07, 0.04, 0.02, 5)
    elif mk == "log":
        c = np.tile(np.array([[118, 98, 78]], np.float64), (n, 1))
        up = N[:, 2]
        c = c * (1.0 + 0.1 * np.clip(up, 0, 1) - 0.12 * np.clip(-up, 0, 1))[:, None]
        c = lerp3(c, (132, 124, 112), 0.35 * np.clip(up, 0, 1))          # sun-bleached grey tops
        c = lerp3(c, (90, 86, 64), smooth01(2.2, 0.4, z) * 0.35)          # damp lower courses
        c = jitter(c, VOL, FID, 0.08, 0.025, 0.02, 6)
    elif mk == "log_end":
        c = lerp3((92, 70, 52), (150, 120, 88), np.clip(G, 0, 1) ** 0.6)  # centre dark (G = 0) -> pale rim
        c = jitter(c, VOL, FID, 0.06, 0.0, 0.015, 7)
    elif mk == "chink":
        c = np.tile(np.array([[168, 160, 144]], np.float64), (n, 1))
        c = jitter(c, VOL, FID, 0.03, 0.0, 0.006, 8)
    elif mk == "shingle":
        base = np.tile(np.array([[110, 99, 87]], np.float64), (n, 1))
        dark = hashf(VOL, 31) < 0.12
        base[dark] = np.array([86, 78, 68])
        c = base * np.where(N[:, 2] < 0.0, 0.74, 1.0)[:, None]              # butt ends darker
        moss = np.clip((0.3 - G) / 0.3, 0, 1) * (hashf(VOL, 37) < 0.55) * 0.45 + (hashf(VOL, 41) < 0.06) * 0.35
        c = lerp3(c, (86, 98, 64), np.clip(moss, 0, 0.6))
        c = jitter(c, VOL, FID, 0.11, 0.02, 0.025, 9)
    elif mk == "ridge":
        c = jitter(np.tile(np.array([[98, 82, 66]], np.float64), (n, 1)), VOL, FID, 0.05, 0.02, 0.01, 10)
    elif mk == "deck":
        c = jitter(np.tile(np.array([[112, 92, 72]], np.float64), (n, 1)), VOL, FID, 0.07, 0.02, 0.012, 11)
    elif mk == "plank":
        c = np.tile(np.array([[128, 104, 80]], np.float64), (n, 1))
        c = c * (1.0 + 0.06 * np.clip(N[:, 2], 0, 1))[:, None]
        c = jitter(c, VOL, FID, 0.08, 0.02, 0.015, 12)
    elif mk == "post":
        c = jitter(np.tile(np.array([[114, 92, 70]], np.float64), (n, 1)), VOL, FID, 0.06, 0.03, 0.012, 13)
    elif mk == "door":
        c = jitter(np.tile(np.array([[100, 76, 56]], np.float64), (n, 1)), VOL, FID, 0.07, 0.02, 0.01, 14)
    elif mk == "iron":
        c = jitter(np.tile(np.array([[54, 51, 48]], np.float64), (n, 1)), VOL, FID, 0.05, 0.02, 0.0, 15)
    elif mk == "frame":
        c = jitter(np.tile(np.array([[106, 86, 66]], np.float64), (n, 1)), VOL, FID, 0.05, 0.02, 0.01, 16)
    elif mk == "glass":
        c = np.tile(np.array([[40, 50, 54]], np.float64), (n, 1))
    elif mk in ("stone", "fstone"):
        pal = np.array([(136, 131, 122), (118, 114, 106), (146, 138, 124), (108, 104, 100), (128, 116, 100),
                        (100, 98, 94), (124, 122, 118)], np.float64)
        k = (hashf(VOL, 51) * len(pal)).astype(int) % len(pal)
        c = pal[k] * (1.0 + 0.07 * np.clip(N[:, 2], 0, 1))[:, None]
        if mk == "fstone":
            c = c * 0.9
            c = lerp3(c, (80, 92, 56), smooth01(0.0, 0.5, N[:, 2]) * (hashf(VOL, 53) < 0.4) * 0.4)
        c = jitter(c, VOL, FID, 0.05, 0.035, 0.01, 17)
    elif mk == "mortar":
        c = jitter(np.tile(np.array([[148, 142, 130]], np.float64), (n, 1)), VOL, FID, 0.03, 0.0, 0.0, 18)
    elif mk == "flue":
        c = np.tile(np.array([[30, 28, 26]], np.float64), (n, 1))
    elif mk == "cloth":
        c = jitter(np.tile(np.array([[118, 64, 50]], np.float64), (n, 1)), VOL, FID, 0.05, 0.03, 0.0, 19)
    elif mk == "rock":
        c = np.tile(np.array([[108, 105, 98]], np.float64), (n, 1))
        c = c * (1.0 + 0.07 * np.clip(N[:, 2], 0, 1) - 0.1 * np.clip(-N[:, 2], 0, 1))[:, None]
        c = jitter(c, VOL, FID, 0.03, 0.075, 0.012, 20)
        moss = smooth01(0.58, 0.9, N[:, 2]) * smooth01(0.9, 1.9, z) * 0.85
        c = lerp3(c, (66, 84, 44), moss)
        c = lerp3(c, (98, 88, 74), smooth01(0.45, 0.0, z) * 0.6)             # soil splash at the base
        rough = 0.86 + 0.09 * moss
    else:
        raise ValueError("no shade rule for " + mk)
    return np.clip(c, 0, 255), rough


# =============================================================================================== mesh accumulator
class MB:
    """Vertices with a gradient value g; faces with a material key, a volume id and a smooth flag."""

    def __init__(self):
        self.V, self.G, self.F, self.FM, self.FV, self.FS = [], [], [], [], [], []
        self.vol = 0

    def new_vol(self):
        self.vol += 1
        return self.vol

    def v(self, co, g=0.0):
        self.V.append((float(co[0]), float(co[1]), float(co[2])))
        self.G.append(float(g))
        return len(self.V) - 1

    def f(self, idx, mk, smooth=False, vol=None):
        idx = [int(i) for i in idx]
        if len(set(idx)) < 3:
            return
        self.F.append(tuple(idx))
        self.FM.append(MKI[mk])
        self.FV.append(self.vol if vol is None else vol)
        self.FS.append(bool(smooth))

    def fo(self, idx, mk, outward, smooth=False):
        """Face whose winding is chosen so that its normal points along 'outward'."""
        p = [Vector(self.V[i]) for i in idx]
        nrm = Vector((0, 0, 0))
        for i in range(1, len(p) - 1):
            nrm += (p[i] - p[0]).cross(p[i + 1] - p[0])
        if nrm.dot(Vector(outward)) < 0:
            idx = list(reversed(idx))
        self.f(idx, mk, smooth)

    def mesh(self, verts, faces, mk, g=None, smooth=False):
        base = len(self.V)
        for i, co in enumerate(verts):
            self.v(co, 0.0 if g is None else g[i])
        for f in faces:
            self.f([base + i for i in f], mk, smooth)
        return base

    def transform(self, start, mat):
        """Apply a 4x4 matrix to vertices start..end."""
        for i in range(start, len(self.V)):
            self.V[i] = tuple(mat @ Vector(self.V[i]))

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.V, [], self.F)
        me.update(calc_edges=True)
        a = me.attributes.new("mk", "INT", "FACE")
        a.data.foreach_set("value", np.array(self.FM, np.int32))
        a = me.attributes.new("vol", "INT", "FACE")
        a.data.foreach_set("value", np.array(self.FV, np.int32))
        a = me.attributes.new("g", "FLOAT", "POINT")
        a.data.foreach_set("value", np.array(self.G, np.float32))
        me.polygons.foreach_set("use_smooth", np.array(self.FS, bool))
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def finalize(obj, ctx):
    """Triangulate (the bake and the GLB tangents then see the same triangles) and paint the corner colours."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    me = obj.data
    me.update()
    nV, nP, nL = len(me.vertices), len(me.polygons), len(me.loops)
    co = np.empty(nV * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3).astype(np.float64)
    g = np.empty(nV, np.float32)
    me.attributes["g"].data.foreach_get("value", g)
    mk = np.empty(nP, np.int32)
    me.attributes["mk"].data.foreach_get("value", mk)
    vol = np.empty(nP, np.int32)
    me.attributes["vol"].data.foreach_get("value", vol)
    pn = np.empty(nP * 3, np.float32)
    me.polygons.foreach_get("normal", pn)
    pn = pn.reshape(-1, 3).astype(np.float64)
    lt = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_total", lt)
    lv = np.empty(nL, np.int32)
    me.loops.foreach_get("vertex_index", lv)
    lp = np.repeat(np.arange(nP), lt)
    col = np.ones((nL, 4))
    misc = np.ones((nL, 4))
    mkl = mk[lp]
    for k in np.unique(mkl):
        sel = np.nonzero(mkl == k)[0]
        key = MK[k]
        P = co[lv[sel]]
        srgb, rough = shade(key, P, pn[lp[sel]], g[lv[sel]].astype(np.float64), vol[lp[sel]], lp[sel], ctx)
        col[sel, :3] = s2l(srgb)
        r, bev, bump, dimple = MATS[key]
        misc[sel, 0] = r if rough is None else rough
        misc[sel, 1] = bump
        misc[sel, 2] = bev
        misc[sel, 3] = dimple
    a = me.color_attributes.new("bk_col", "FLOAT_COLOR", "CORNER")
    a.data.foreach_set("color", col.astype(np.float32).ravel())
    a = me.color_attributes.new("bk_misc", "FLOAT_COLOR", "CORNER")
    a.data.foreach_set("color", misc.astype(np.float32).ravel())
    # mean painted colour (fallback MeshPart.Color)
    obj["rgb"] = [int(round(v)) for v in l2s255(col[:, :3].mean(0))]
    return obj


# =============================================================================================== geometry helpers
def frames(path):
    P = [Vector(p) for p in path]
    n = len(P)
    T = []
    for i in range(n):
        if i == 0:
            t = P[1] - P[0]
        elif i == n - 1:
            t = P[-1] - P[-2]
        else:
            t = P[i + 1] - P[i - 1]
        T.append(t.normalized())
    ref = Vector((1, 0, 0)) if abs(T[0].x) < 0.9 else Vector((0, 1, 0))
    N = (ref - T[0] * ref.dot(T[0])).normalized()
    out = []
    for i in range(n):
        if i > 0:
            N = (N - T[i] * N.dot(T[i])).normalized()
        out.append((T[i], N, T[i].cross(N)))
    return P, out


def tube(mb, path, radii, sides, mk, g=None, cap0=True, cap1=True, apex1=None, rot0=0.0, twist=0.0, rjit=0.0,
         rng=None, new_vol=True):
    """Faceted prism along a polyline (parallel-transport frames), optional caps / apex."""
    if new_vol:
        mb.new_vol()
    P, fr = frames(path)
    rings = []
    for i, p in enumerate(P):
        T, N, B = fr[i]
        ring = []
        for j in range(sides):
            a = rot0 + twist * i + TAU * j / sides
            r = radii[i] * (1.0 + (rng.uniform(-rjit, rjit) if rjit else 0.0))
            ring.append(mb.v(p + (N * math.cos(a) + B * math.sin(a)) * r, g[i] if g is not None else 0.0))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            mb.f((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]), mk)
    if cap0:
        c = mb.v(P[0], g[0] if g is not None else 0.0)
        for j in range(sides):
            mb.f((c, rings[0][(j + 1) % sides], rings[0][j]), mk)
    if apex1 is not None:
        c = mb.v(apex1, g[-1] if g is not None else 0.0)
        for j in range(sides):
            mb.f((c, rings[-1][j], rings[-1][(j + 1) % sides]), mk)
    elif cap1:
        c = mb.v(P[-1], g[-1] if g is not None else 0.0)
        for j in range(sides):
            mb.f((c, rings[-1][j], rings[-1][(j + 1) % sides]), mk)
    return rings


def box(mb, lo, hi, mk, skip=(), jit=0.0, rng=None, mat=None, new_vol=True, g=0.5):
    """Axis-aligned box lo..hi (optionally transformed by a 4x4 matrix), outward faces."""
    if new_vol:
        mb.new_vol()
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    cs = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1),
          (x0, y1, z1)]
    idx = []
    for q in cs:
        q = Vector(q)
        if jit:
            q += Vector((rng.uniform(-jit, jit), rng.uniform(-jit, jit), rng.uniform(-jit, jit)))
        if mat is not None:
            q = mat @ q
        idx.append(mb.v(q, g))
    faces = {"-z": (0, 3, 2, 1), "+z": (4, 5, 6, 7), "-y": (0, 1, 5, 4), "+y": (2, 3, 7, 6), "-x": (3, 0, 4, 7),
             "+x": (1, 2, 6, 5)}
    for k, f in faces.items():
        if k not in skip:
            mb.f([idx[i] for i in f], mk)
    return idx


def hull(points, dissolve_deg=1.5):
    """Convex hull of points -> (verts, faces) with coplanar triangles merged into facets."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in points]
    bmesh.ops.convex_hull(bm, input=vs)
    loose = [v for v in bm.verts if not v.link_faces]
    for v in loose:
        bm.verts.remove(v)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.015)
    if dissolve_deg:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve_deg), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.verts.index_update()
    verts = [v.co.copy() for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return verts, faces


def rock_points(rng, a, b, c, n=34, p=2.4, rj=0.06):
    pts = []
    for _ in range(n):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        r = 1.0 / ((abs(d.x / a) ** p + abs(d.y / b) ** p + abs(d.z / c) ** p) ** (1.0 / p))
        pts.append(d * r * rng.uniform(1.0 - rj, 1.0 + rj * 0.4))
    return pts


def cut(pts, nrm, frac):
    """Project points beyond the plane (normal nrm, at frac of the extent along nrm) onto it."""
    nrm = Vector(nrm).normalized()
    ext = max(q.dot(nrm) for q in pts)
    off = ext * frac
    return [q - nrm * (q.dot(nrm) - off) if q.dot(nrm) > off else q.copy() for q in pts]


def chunk_rock(mb, rng, centre, a, b, c, mk="fstone", n=14, cuts=3, flat_top=None, flat_bottom=0.55):
    pts = rock_points(rng, a, b, c, n=n, p=2.2, rj=0.1)
    for _ in range(cuts):
        nv = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1))).normalized()
        pts = cut(pts, nv, rng.uniform(0.72, 0.88))
    pts = cut(pts, (0, 0, -1), flat_bottom)
    if flat_top:
        pts = cut(pts, (0, 0, 1), flat_top)
    v, f = hull(pts)
    mb.new_vol()
    mb.mesh([Vector(centre) + q for q in v], f, mk)


# =============================================================================================== SPRUCE
def build_spruce(seed=7):
    rng = random.Random(seed)
    H = 42.0

    def ax(z):
        return Vector((0.16 * math.sin(z * 0.13 + 0.6), 0.12 * math.sin(z * 0.09 + 2.1), z))

    def rad(z):
        zz = max(z, 0.0)
        return 0.09 + 0.72 * (1.0 - zz / H) ** 1.05 + 0.5 * math.exp(-zz / 0.8)

    bark = MB()
    zs = [-0.9, 0.0, 0.45, 1.3, 3.0, 6.0, 10.0, 15.0, 20.0, 25.0, 30.0, 34.5, 38.0, 40.6]
    tube(bark, [ax(z) for z in zs], [rad(z) for z in zs], 7, "bark_spr", g=[max(z, 0) / H for z in zs],
         cap0=True, apex1=ax(H - 0.6), rjit=0.06, rng=rng, twist=0.05)
    for k in range(5):
        a = TAU * k / 5 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        L = rng.uniform(1.5, 2.3)
        tube(bark, [Vector((0, 0, 1.0)) + d * 0.25, d * (0.75 + L * 0.45) + Vector((0, 0, 0.12)),
                    d * (0.8 + L) + Vector((0, 0, -0.4))], [0.42, 0.3, 0.07], 4, "root_spr", cap0=False,
             rot0=rng.uniform(0, 1))

    nd = MB()
    z_base, z_top = 6.6, H - 1.6
    tiers = []
    z = z_base
    while z < z_top - 0.3:
        t = (z - z_base) / (z_top - z_base)
        R = 6.7 * (1.0 - t) ** 0.95 * (0.8 + 0.2 * min(1.0, t * 6.0)) + 0.5
        tiers.append((z, R, t))
        z += (2.4 - 1.35 * t) * rng.uniform(0.88, 1.12)
    for (zc, R, t) in tiers:
        spruce_tier(nd, ax(zc), R, rng, ragged=0.12 + 0.22 * max(0.0, 0.3 - t) / 0.3)
    spruce_tier(nd, ax(H - 1.5), 0.85, rng, lobes=5)
    tube(nd, [ax(H - 2.6), ax(H + 0.4)], [0.2, 0.05], 4, "needle", g=[0.6, 1.0], cap0=True, apex1=ax(H + 0.6))

    dw = MB()
    for k in range(9):
        zz = rng.uniform(2.4, z_base - 0.2)
        a = rng.uniform(0, TAU)
        d = Vector((math.cos(a), math.sin(a), rng.uniform(-0.3, 0.02))).normalized()
        L = rng.uniform(0.8, 1.9)
        tube(dw, [ax(zz) + d * 0.15, ax(zz) + d * L], [0.075, 0.025], 3, "deadwood", g=[0.0, 1.0], cap0=False,
             apex1=ax(zz) + d * (L + 0.12), rot0=rng.uniform(0, 1))
    ctx = {"crown_t": lambda zz: np.clip((zz - z_base) / (z_top - z_base), 0, 1)}
    return {"Bark": bark, "Needles": nd, "Deadwood": dw}, ctx, {"tiers": len(tiers) + 1}


def spruce_tier(mb, c, R, rng, lobes=None, ragged=0.12):
    """One drooping needle tier: closed faceted volume with a star-lobed rim (branch tips) - not a card."""
    mb.new_vol()
    L = lobes or max(5, min(11, int(round(4 + R * 1.05))))
    rot0 = rng.uniform(0, TAU)
    droop = (0.28 * R + 0.35) * rng.uniform(0.9, 1.1)
    rise = 0.34 * R + 0.25
    dA = TAU / L
    rim = []
    for j in range(L):
        th = rot0 + j * dA + rng.uniform(-0.12, 0.12) * dA
        tip = R * rng.uniform(0.84, 1.08) * (rng.uniform(0.6, 0.78) if rng.random() < ragged else 1.0)
        dz = droop * rng.uniform(0.85, 1.15)
        rim.append((th - 0.27 * dA, tip * 0.8, -dz * 0.78, 0.84))
        rim.append((th, tip, -dz, 1.0))
        rim.append((th + 0.27 * dA, tip * 0.8, -dz * 0.8, 0.84))
        rim.append((th + 0.5 * dA, R * rng.uniform(0.5, 0.62), -dz * 0.42, 0.62))
    apex = mb.v(c + Vector((0, 0, rise)), 0.0)
    uapex = mb.v(c + Vector((0, 0, -0.08 * R)), 0.0)
    tm, rv, bm_ = [], [], []
    for (th, r, dz, g) in rim:
        d = Vector((math.cos(th), math.sin(th), 0.0))
        rv.append(mb.v(c + d * r + Vector((0, 0, dz)), g))
        zt = rise + (dz - rise) * 0.5 + 0.1 * R
        tm.append(mb.v(c + d * (r * 0.5) + Vector((0, 0, zt)), 0.42 * g + 0.12))
        zb = dz * 0.55 - 0.12 * R
        bm_.append(mb.v(c + d * (r * 0.52) + Vector((0, 0, zb)), 0.22 * g))
    n = len(rim)
    for i in range(n):
        k = (i + 1) % n
        mb.f((apex, tm[i], tm[k]), "needle")
        mb.f((tm[i], rv[i], rv[k], tm[k]), "needle")
        mb.f((rv[i], bm_[i], bm_[k], rv[k]), "needle")
        mb.f((bm_[i], uapex, bm_[k]), "needle")


# =============================================================================================== OAK
def build_oak(seed=3):
    rng = random.Random(seed)

    def tax(z):
        return Vector((0.32 * math.sin(z * 0.17 + 0.3), -0.24 * math.sin(z * 0.11 + 1.3), z))

    def trad(z):
        zz = max(z, 0.0)
        return 1.3 - 0.034 * zz + 0.85 * math.exp(-zz / 0.9)

    bark = MB()
    tz = [-0.8, 0.0, 0.6, 1.6, 3.2, 5.0, 6.8, 8.2, 9.4]
    tube(bark, [tax(z) for z in tz], [trad(z) for z in tz], 9, "bark_oak", cap0=True, cap1=True, rjit=0.07, rng=rng,
         twist=0.04)
    for k in range(5):
        a = TAU * k / 5 + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        L = rng.uniform(2.2, 3.0)
        tube(bark, [Vector((0, 0, 2.2)) + d * 0.5, d * (1.3 + L * 0.4) + Vector((0, 0, 0.35)),
                    d * (1.5 + L) + Vector((0, 0, -0.45))], [0.75, 0.55, 0.14], 5, "bark_oak", cap0=False,
             rot0=rng.uniform(0, 1))
    # limbs: (azimuth, elev0, elev1, length, r0, r1, start z, perch)
    limbs = [(18, 7, 40, 10.0, 0.82, 0.3, 8.0, True), (140, 24, 48, 8.6, 0.76, 0.28, 8.6, False),
             (252, 6, 38, 9.8, 0.8, 0.3, 7.8, True), (322, 60, 76, 8.4, 0.95, 0.4, 8.8, False),
             (75, 34, 58, 7.6, 0.6, 0.24, 9.0, False), (200, 38, 62, 7.2, 0.58, 0.24, 9.2, False)]
    ends, perches, limb_ends = [], [], []
    for li, (az, e0, e1, L, r0, r1, z0, perch) in enumerate(limbs):
        a = math.radians(az)
        start = tax(z0) + Vector((math.cos(a), math.sin(a), 0.0)) * 0.2
        pts, n = [start], 5
        p = start.copy()
        dirs = []
        for k in range(1, n + 1):
            t = k / n
            e = math.radians(e0 + (e1 - e0) * t * t)
            d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
            dirs.append(d)
            a += rng.uniform(-0.07, 0.07)
            p = p + d * (L / n)
            pts.append(p.copy())
        radii = [r0 + (r1 - r0) * (k / n) ** 0.9 for k in range(n + 1)]
        tube(bark, pts, radii, 7, "limb_oak", cap0=False, cap1=True, rjit=0.05, rng=rng, rot0=rng.uniform(0, 1))
        ends.append((pts[-1], dirs[-1], 3.6 if li < 4 else 3.2))
        limb_ends.append(pts[-1])
        if perch:
            k = 2
            q = pts[k] + UP * radii[k] * 0.92
            dd = (pts[k + 1] - pts[k - 1])
            perches.append((q, Vector((dd.x, dd.y, 0)).normalized()))
        # secondary branches (alternating sides) carry most of the foliage clumps
        side = rng.choice((-1, 1))
        for tk in (0.45, 0.65, 0.85):
            side = -side
            i0 = min(int(round(tk * n)), n - 1)
            b0 = pts[i0]
            ab = math.atan2(dirs[i0].y, dirs[i0].x) + side * math.radians(rng.uniform(32, 58))
            eb = math.radians(rng.uniform(28, 55))
            Ls = rng.uniform(2.8, 4.6) * (1.0 if li < 4 else 0.8)
            db = Vector((math.cos(ab) * math.cos(eb), math.sin(ab) * math.cos(eb), math.sin(eb)))
            b1 = b0 + db * (Ls * 0.55) + UP * 0.25
            b2 = b0 + db * Ls + UP * 0.55
            rb = radii[i0] * 0.55
            tube(bark, [b0, b1, b2], [rb, rb * 0.7, rb * 0.38], 5, "limb_oak", cap0=False, cap1=True,
                 rot0=rng.uniform(0, 1))
            ends.append((b2, db, rng.uniform(2.6, 3.3)))
    # leader split
    lead_end = limb_ends[3]
    for (az, el, Ls) in ((285, 46, 5.5), (35, 52, 5.2)):
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        tube(bark, [lead_end - d * 0.3, lead_end + d * Ls * 0.5, lead_end + d * Ls], [0.36, 0.26, 0.12], 5,
             "limb_oak", cap0=False, rot0=rng.uniform(0, 1))
        ends.append((lead_end + d * Ls, d, 4.1))

    leaves = MB()
    crown_c = Vector((0.0, 0.0, 17.5))
    centres = []
    for (p, d, R) in ends:                      # a clump on every branch end, plus a smaller satellite
        centres.append((p + d * (R * 0.2) + UP * 0.5, R))
        a = rng.uniform(0, TAU)
        centres.append((p + Vector((math.cos(a), math.sin(a), rng.uniform(0.1, 0.6))) * R * 0.9,
                        R * rng.uniform(0.6, 0.8)))
    for _ in range(14):                         # fill the upper dome so the crown reads as one broad mass
        a = rng.uniform(0, TAU)
        rr = rng.uniform(0.15, 0.75)
        z = rng.uniform(19.0, 24.5)
        centres.append((Vector((math.cos(a) * rr * 9.5, math.sin(a) * rr * 9.5, z)), rng.uniform(2.8, 3.8)))
    ells = [leaf_clump(leaves, cc, R, rng, crown_c) for (cc, R) in centres]
    culled = cull_hidden(leaves, ells, shrink=0.72)
    ctx = {}
    return {"Bark": bark, "Leaves": leaves}, ctx, {"perches": perches, "culled": culled, "clumps": len(centres)}


def leaf_clump(mb, c, R, rng, crown_c, flat=0.42):
    """Foliage clump: convex hull of jittered points on a flattened ellipsoid -> a few large crisp facets and a
    flat underside (the way sunlit leaf clusters read from a distance)."""
    vol = mb.new_vol()
    rx, ry, rz = R * rng.uniform(1.0, 1.25), R * rng.uniform(0.85, 1.05), R * rng.uniform(0.64, 0.8)
    rot = Matrix.Rotation(rng.uniform(0, TAU), 3, "Z")
    npts = 36 if R > 2.4 else 24
    pts = []
    for _ in range(npts):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        k = rng.uniform(0.84, 1.08)
        pts.append(Vector((d.x * rx * k, d.y * ry * k, d.z * rz * k)))
    pts = cut(pts, (0, 0, -1), flat)
    v, f = hull(pts, dissolve_deg=3.0)
    out_dir = c - crown_c
    out_dir = out_dir.normalized() if out_dir.length > 1e-3 else UP
    world, gs = [], []
    for q in v:
        p = rot @ q
        hz = 0.5 + 0.5 * max(-1.0, min(1.0, q.z / (rz * 0.85)))
        outw = 0.5 + 0.5 * p.normalized().dot(out_dir) if p.length > 1e-4 else 0.5
        gs.append(max(0.0, min(1.0, 0.6 * hz + 0.4 * outw)))
        world.append(c + p)
    mb.mesh(world, f, "leaf", g=gs)
    M = np.array(rot) @ np.diag([rx, ry, rz])
    return (vol, np.array(c), np.linalg.inv(M), -flat + 0.08)


def cull_hidden(mb, ells, shrink=0.74):
    """Drop leaf-mass faces buried inside another mass (saves triangles and texture space)."""
    keep = []
    V = np.array(mb.V)
    for fi, f in enumerate(mb.F):
        vol = mb.FV[fi]
        pts = V[list(f)]
        hidden = False
        for (evol, c, inv, lowz) in ells:
            if evol == vol:
                continue
            q = (pts - c) @ inv.T
            if np.all(np.linalg.norm(q, axis=1) < shrink) and np.all(q[:, 2] > lowz):
                hidden = True
                break
        keep.append(not hidden)
    n0 = len(mb.F)
    mb.F = [f for f, k in zip(mb.F, keep) if k]
    mb.FM = [f for f, k in zip(mb.FM, keep) if k]
    mb.FV = [f for f, k in zip(mb.FV, keep) if k]
    mb.FS = [f for f, k in zip(mb.FS, keep) if k]
    return n0 - len(mb.F)


def leaf_mass(mb, c, R, rng, crown_c, subdiv=3, squash=0.78, flat=0.42):
    """Lumpy faceted leaf mass (icosphere-based). Returns its ellipsoid for hidden-face culling."""
    vol = mb.new_vol()
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    bm.verts.index_update()
    verts = [v.co.copy() for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    sx, sy, sz = R * rng.uniform(1.0, 1.2), R * rng.uniform(0.88, 1.05), R * squash * rng.uniform(0.92, 1.08)
    rot = Matrix.Rotation(rng.uniform(0, TAU), 3, "Z")
    w = [Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized() for _ in range(3)]
    ph = [rng.uniform(0, TAU) for _ in range(3)]
    out_dir = (c - crown_c)
    out_dir = out_dir.normalized() if out_dir.length > 1e-3 else UP
    pts, gs = [], []
    for v in verts:
        k = 1.0 + 0.12 * sum(math.sin(v.dot(w[i]) * 2.6 + ph[i]) for i in range(3)) / 1.5
        p = Vector((v.x * sx * k, v.y * sy * k, v.z * sz * k))
        if p.z < -flat * sz:
            p.z = -flat * sz + (p.z + flat * sz) * 0.3
        p = rot @ p
        hz = 0.5 + 0.5 * max(-1.0, min(1.0, p.z / (sz * 0.9)))
        outw = 0.5 + 0.5 * v.normalized().dot(out_dir)
        gs.append(max(0.0, min(1.0, 0.62 * hz + 0.38 * outw)))
        pts.append(c + p)
    mb.mesh(pts, faces, "leaf", g=gs)
    M = np.array(rot) @ np.diag([sx, sy, sz])
    return (vol, np.array(c), np.linalg.inv(M), -0.3)


# =============================================================================================== BOULDER
def jointed_hull(rng, a, b, c, n, cuts, chamfers, p=3.0, base=0.55):
    """Blocky jointed rock: boxy superellipsoid points, big joint-plane cuts, a flat bed, chamfered corners."""
    pts = rock_points(rng, a, b, c, n=n, p=p, rj=0.06)
    for nv, fr in cuts:
        pts = cut(pts, nv, fr)
    pts = cut(pts, (0, 0, -1), base)
    v, f = hull(pts, dissolve_deg=2.5)
    for _ in range(chamfers):
        q = max(v, key=lambda pp: pp.length * rng.uniform(0.8, 1.0))
        v, f = hull(cut(v, q, rng.uniform(0.9, 0.95)), dissolve_deg=2.5)
    return v, f


def build_boulder(seed=19):
    rng = random.Random(seed)
    rk = MB()
    main_cuts = [((0.1, 0.95, 0.3), 0.86), ((-0.92, 0.25, 0.22), 0.84), ((0.25, -0.6, 0.78), 0.82),
                 ((0.88, -0.3, -0.05), 0.88), ((-0.3, -0.85, 0.4), 0.85), ((0.5, 0.4, 0.78), 0.86),
                 ((-0.55, 0.55, 0.62), 0.88), ((0.0, 0.0, 1.0), 0.9)]
    v, f = jointed_hull(rng, 3.0, 2.45, 2.4, 72, main_cuts, 5)
    rk.new_vol()
    rk.mesh(v, f, "rock")
    # an overlapping second block (same rock, split along a joint) gives a concave notch, not a gem
    lobe_cuts = [((0.2, 0.9, 0.35), 0.84), ((0.9, -0.1, 0.35), 0.82), ((-0.3, 0.35, 0.88), 0.82),
                 ((0.4, -0.8, 0.3), 0.86)]
    v2, f2 = jointed_hull(rng, 2.0, 1.6, 1.55, 44, lobe_cuts, 3)
    rk.new_vol()
    rk.mesh([q + Vector((1.75, 1.0, -0.3)) for q in v2], f2, "rock")
    # a small spall at the foot grounds it
    v3, f3 = jointed_hull(rng, 0.62, 0.5, 0.36, 20, [((0.3, 0.2, 0.9), 0.8)], 1)
    rk.new_vol()
    rk.mesh([q + Vector((-2.6, 1.9, -0.6)) for q in v3], f3, "rock")
    zmin = min(p[2] for p in rk.V[:len(rk.V) - len(v3)])
    rk.V = [(p[0], p[1], p[2] - zmin - 0.45) for p in rk.V]
    return {"Rock": rk}, {}, {}


# =============================================================================================== CABIN
W2, D2 = 8.0, 6.0                  # outer half extents of the log walls (16 x 12)
LW, LH, LC = 0.9, 1.0, 0.17        # hewn log thickness, height, chamfer
S = 1.22                           # course spacing (0.22 chinked gap)
XC, YC = W2 - LW / 2, D2 - LW / 2  # wall centre lines
PROJ = 0.6                         # log ends project past the corners
Z0F = 0.85                         # front/back course 0 centre
Z0S = Z0F + S / 2                  # side course 0 centre (half-course stagger)
FLOOR = Z0F + LH / 2               # 1.35
PITCH = math.radians(38.0)
TP = math.tan(PITCH)
PLATE = Z0F + 8 * S + LH / 2       # 11.11: top of the front/back plate logs
RIDGE_U = PLATE + D2 * TP          # roof underside at the ridge
EAVE_F, EAVE_B = 0.45, 1.25        # front eave short (the porch roof tucks under it), back eave full
ROOF_X0, ROOF_X1 = -W2 - 0.9, W2 + 0.3
PORCH_Y1 = 11.0                    # porch deck front edge
PORCH_PITCH = math.radians(12.0)
PZ = 10.1                          # porch roof deck underside at the wall
DECK_TOP = 1.3
DOOR = (-2.0, 2.0, FLOOR, Z0F + 7 * S - LH / 2)       # x0, x1, z0, z1 (clear 4 x 7.54)
WIN_F = (3.1, 5.5, Z0F + 2 * S + LH / 2, Z0F + 5 * S - LH / 2)
WIN_B = (-5.8, -3.4) + WIN_F[2:]
WIN_W = (-1.2, 1.2, Z0S + 2 * S + LH / 2, Z0S + 5 * S - LH / 2)
JAMB = 0.24


def cut_intervals(a0, a1, cuts):
    out = [(a0, a1)]
    for (c0, c1) in cuts:
        nxt = []
        for (lo, hi) in out:
            if c1 <= lo or c0 >= hi:
                nxt.append((lo, hi))
                continue
            if c0 > lo:
                nxt.append((lo, c0))
            if c1 < hi:
                nxt.append((c1, hi))
        out = nxt
    return out


def gable_clip(q):
    ymax = (RIDGE_U - q.z) / TP - 0.03
    if q.y > ymax:
        q.y = ymax
    if q.y < -ymax:
        q.y = -ymax
    return q


def hewn(mb, p0, p1, w, h, c, rng, mk="log", end_mk="log_end", up=UP, segs=None, clip=None, bow=0.0, jit=0.022,
         caps=(True, True)):
    """Hewn timber: octagonal (chamfered rectangle) faceted prism p0 -> p1, separate end-grain caps."""
    p0, p1 = Vector(p0), Vector(p1)
    T = p1 - p0
    L = T.length
    T.normalize()
    U = Vector(up).cross(T).normalized()
    Vv = T.cross(U).normalized()
    prof = [(-w / 2, -h / 2 + c), (-w / 2 + c, -h / 2), (w / 2 - c, -h / 2), (w / 2, -h / 2 + c), (w / 2, h / 2 - c),
            (w / 2 - c, h / 2), (-w / 2 + c, h / 2), (-w / 2, h / 2 - c)]
    nseg = segs or max(1, int(round(L / 4.5)))
    mb.new_vol()
    rings = []
    for k in range(nseg + 1):
        t = k / nseg
        ctr = p0 + T * (L * t) + Vv * (bow * math.sin(math.pi * t))
        ring = []
        for (u, v) in prof:
            q = ctr + U * (u + rng.uniform(-jit, jit)) + Vv * (v + rng.uniform(-jit, jit))
            if clip is not None and k in (0, nseg):
                q = clip(q)
            ring.append(q)
        rings.append(ring)
    ids = [[mb.v(q, 0.5) for q in ring] for ring in rings]
    m = len(prof)
    for k in range(nseg):
        for j in range(m):
            jj = (j + 1) % m
            mb.f((ids[k][j], ids[k][jj], ids[k + 1][jj], ids[k + 1][j]), mk)
    for which, ring in ((0, rings[0]), (1, rings[-1])):
        if not caps[which]:
            continue
        cen = sum(ring, Vector((0, 0, 0))) / len(ring)
        ci = mb.v(cen, 0.0)
        rim = [mb.v(q, 1.0) for q in ring]
        for j in range(m):
            jj = (j + 1) % m
            if which == 0:
                mb.f((ci, rim[jj], rim[j]), end_mk)
            else:
                mb.f((ci, rim[j], rim[jj]), end_mk)


def wall(mbl, mbc, axis, c, zs, openings, rng, clip=None, heights=None):
    """One hewn-log wall. axis 'x': logs along X at y = c; 'y': along Y at x = c."""
    half = (W2 if axis == "x" else D2) + PROJ
    inner = (W2 if axis == "x" else D2) - 0.25
    for i, zc in enumerate(zs):
        h = (heights[i] if heights else LH) * rng.uniform(0.97, 1.03)
        a0, a1 = -half - rng.uniform(-0.1, 0.14), half + rng.uniform(-0.1, 0.14)
        if clip is not None:
            ylim = (RIDGE_U - (zc - h / 2)) / TP
            if ylim < 0.8:
                continue
        cuts = [(lo, hi) for (lo, hi, zl, zh) in openings if zc + h / 2 > zl + 0.02 and zc - h / 2 < zh - 0.02]
        for (lo, hi) in cut_intervals(a0, a1, cuts):
            if hi - lo < 0.5:
                continue
            p0 = (lo, c, zc) if axis == "x" else (c, lo, zc)
            p1 = (hi, c, zc) if axis == "x" else (c, hi, zc)
            hewn(mbl, p0, p1, LW * rng.uniform(0.96, 1.02), h, LC, rng, clip=clip,
                 segs=1 if clip is not None and zc > PLATE - 1.0 else None, bow=rng.uniform(-0.05, 0.05))
    for i in range(len(zs) - 1):
        top_i = zs[i] + (heights[i] if heights else LH) / 2
        bot_n = zs[i + 1] - LH / 2
        zl, zh = top_i - 0.08, bot_n + 0.08
        e = inner
        if clip is not None:
            e = min(e, (RIDGE_U - zh) / TP - 0.35)
            if e < 0.6:
                continue
        cuts = [(lo, hi) for (lo, hi, ozl, ozh) in openings if zh > ozl + 0.02 and zl < ozh - 0.02]
        for (lo, hi) in cut_intervals(-e, e, cuts):
            if hi - lo < 0.3:
                continue
            if axis == "x":
                box(mbc, (lo, c - 0.31, zl), (hi, c + 0.31, zh), "chink")
            else:
                box(mbc, (c - 0.31, lo, zl), (c + 0.31, hi, zh), "chink")


class Slope:
    """Roof plane frame: P(x, s, n) = origin + x X + s * down-slope + n * outward normal."""

    def __init__(self, origin, ang, sign):
        self.o = Vector(origin)
        self.ds = Vector((0.0, sign * math.cos(ang), -math.sin(ang)))
        self.ns = Vector((0.0, sign * math.sin(ang), math.cos(ang)))

    def P(self, x, s, n):
        return self.o + Vector((x, 0.0, 0.0)) + self.ds * s + self.ns * n


def slab(mb, sl, xa, xb, sa, sb, na, nb, mk, skip=(), g=0.5):
    """Box in slope coordinates (x, s, n) with outward faces."""
    mb.new_vol()
    q = {}
    for ix, x in enumerate((xa, xb)):
        for js, s in enumerate((sa, sb)):
            for kn, n in enumerate((na, nb)):
                q[(ix, js, kn)] = mb.v(sl.P(x, s, n), g)
    X = Vector((1, 0, 0))
    faces = {"n+": ([(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], sl.ns),
             "n-": ([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], -sl.ns),
             "s+": ([(0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)], sl.ds),
             "s-": ([(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], -sl.ds),
             "x+": ([(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], X),
             "x-": ([(0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)], -X)}
    for k, (cs, out) in faces.items():
        if k not in skip:
            mb.fo([q[c] for c in cs], mk, out)


def shingles(mb, sl, x0, x1, s_eave, s_top, rng, d0=0.22, t=0.12, e=0.72, Lsh=1.55):
    """Staggered rows of tilted shingle strips; each row rests on the one below (visible butt edge)."""
    tan_a = t / e
    rows = []
    sb = s_eave + 0.12
    while sb - e > s_top - 0.45:
        rows.append(sb)
        sb -= e
    nrow = len(rows)
    for r, sb in enumerate(rows):
        st = max(sb - Lsh, s_top - 0.12)
        x = x0 - rng.uniform(0.0, 0.7)
        while x < x1:
            wd = rng.uniform(0.62, 1.32)
            xa, xb = max(x, x0), min(x + wd - 0.06, x1)
            x += wd
            if xb - xa < 0.25:
                continue
            sbj = sb + rng.uniform(-0.05, 0.05)
            tt = t * rng.uniform(0.85, 1.15)
            g = r / max(nrow - 1, 1)
            mb.new_vol()

            def nb(s, r=r, st=st):
                return d0 if r == 0 else d0 + (s - st) * tan_a

            def ntop(s, st=st, tt=tt):
                return d0 + (s - st) * tan_a + tt
            A, B = mb.v(sl.P(xa, st, nb(st)), g), mb.v(sl.P(xb, st, nb(st)), g)
            C, D = mb.v(sl.P(xb, sbj, nb(sbj)), g), mb.v(sl.P(xa, sbj, nb(sbj)), g)
            A2, B2 = mb.v(sl.P(xa, st, ntop(st)), g), mb.v(sl.P(xb, st, ntop(st)), g)
            C2, D2_ = mb.v(sl.P(xb, sbj, ntop(sbj)), g), mb.v(sl.P(xa, sbj, ntop(sbj)), g)
            mb.fo((A2, B2, C2, D2_), "shingle", sl.ns)
            mb.fo((D, C, C2, D2_), "shingle", sl.ds)
            mb.fo((A, D, D2_, A2), "shingle", Vector((-1, 0, 0)))
            mb.fo((B, B2, C2, C), "shingle", Vector((1, 0, 0)))
            if r == nrow - 1:
                mb.fo((A, A2, B2, B), "shingle", -sl.ds)
    return nrow


def stone_face(mb, origin, u_dir, out_dir, length, z0, z1, rng, depth=0.45, prot=0.12, gap=0.08, slope=None):
    """Courses of individual fieldstones over a rectangular face: irregular clipped-corner outlines, uneven
    heights and protrusion, so the mortar lines wander (not brick courses)."""
    o, U, O = Vector(origin), Vector(u_dir).normalized(), Vector(out_dir).normalized()

    def P(uu, vv, oo):
        return o + U * uu + UP * vv + O * oo
    z = z0
    while z < z1 - 0.15:
        hc = min(rng.uniform(0.55, 0.95), z1 - z)
        if z1 - (z + hc) < 0.3:
            hc = z1 - z
        u = -rng.uniform(0.0, 0.6)
        while u < length:
            sw = rng.uniform(0.6, 1.6)
            ua, ub = max(u, 0.0), min(u + sw - gap, length)
            u += sw
            if ub - ua < 0.22:
                continue
            va = z + gap / 2 + rng.uniform(0.0, 0.07)
            vb = z + hc - gap / 2 - rng.uniform(0.0, 0.1)
            w, h = ub - ua, vb - va
            pr = prot * rng.uniform(0.5, 1.5)
            cs = [rng.uniform(0.08, 0.3) * min(w, h) for _ in range(4)]
            outline = [(ua + cs[0], va), (ub - cs[1], va), (ub, va + cs[1]), (ub, vb - cs[2]), (ub - cs[2], vb),
                       (ua + cs[3], vb), (ua, vb - cs[3]), (ua, va + cs[0])]
            if rng.random() < 0.5:                        # square two opposite corners: 6-sided stone
                k0 = rng.randint(0, 1)
                corner = [(ua, va), (ub, va), (ub, vb), (ua, vb)]
                keep = []
                for ci in range(4):
                    if ci % 2 == k0:
                        keep.append(corner[ci])
                    else:
                        keep += [outline[(2 * ci - 1) % 8], outline[2 * ci]]
                outline = keep
            mb.new_vol()
            cu, cv = (ua + ub) / 2, (va + vb) / 2
            fr, bk = [], []
            for (uu, vv) in outline:
                # the face bulges a little: corners sit back, so each stone reads as a rounded block
                fr.append(mb.v(P(uu + rng.uniform(-0.03, 0.03), vv + rng.uniform(-0.03, 0.03),
                                 pr * rng.uniform(0.55, 0.85))))
                bk.append(mb.v(P(uu, vv, -depth)))
            ctr = mb.v(P(cu + rng.uniform(-0.08, 0.08), cv + rng.uniform(-0.06, 0.06), pr * 1.05))
            m = len(outline)
            cpt = P(cu, cv, -depth * 0.5)
            for j in range(m):
                jj = (j + 1) % m
                mb.fo((ctr, fr[j], fr[jj]), "stone", O)
                mid = (Vector(mb.V[fr[j]]) + Vector(mb.V[fr[jj]])) / 2
                mb.fo((bk[j], bk[jj], fr[jj], fr[j]), "stone", mid - cpt - O * (mid - cpt).dot(O))
        z += hc


def wbox(mb, axis, cl, a0, a1, w0, w1, z0, z1, mk, rng=None, jit=0.0):
    """Box in wall coordinates: along-wall a, across-wall w (offset from the centre line cl), height z."""
    a0, a1 = min(a0, a1), max(a0, a1)
    w0, w1 = min(w0, w1), max(w0, w1)
    if axis == "x":
        return box(mb, (a0, cl + w0, z0), (a1, cl + w1, z1), mk, jit=jit, rng=rng)
    return box(mb, (cl + w0, a0, z0), (cl + w1, a1, z1), mk, jit=jit, rng=rng)


def window(trim, glass, axis, cl, op, out_sign, rng, shutter=False):
    """Chunky window: jamb/head boards, a sill that juts outside, 2 x 2 panes, optional open board shutter."""
    a0, a1, z0, z1 = op
    d0, d1 = -0.5, 0.52
    fr = 0.2
    wbox(trim, axis, cl, a0 - fr, a0, d0, d1, z0, z1, "frame")
    wbox(trim, axis, cl, a1, a1 + fr, d0, d1, z0, z1, "frame")
    s0, s1 = (d0 - 0.02, d1 + 0.24) if out_sign > 0 else (d0 - 0.24, d1 + 0.02)
    wbox(trim, axis, cl, a0 - fr - 0.12, a1 + fr + 0.12, s0, s1, z0 - 0.04, z0 + 0.16, "frame")
    wbox(trim, axis, cl, a0 - fr, a1 + fr, d0, d1, z1 - 0.16, z1, "frame")
    wbox(glass, axis, cl, a0, a1, -0.03, 0.03, z0 + 0.16, z1 - 0.16, "glass")
    am, zm = (a0 + a1) / 2, (z0 + z1) / 2
    wbox(trim, axis, cl, am - 0.05, am + 0.05, -0.09, 0.09, z0 + 0.16, z1 - 0.16, "frame")
    wbox(trim, axis, cl, a0, a1, -0.09, 0.09, zm - 0.05, zm + 0.05, "frame")
    if shutter:
        # one board shutter (half of the pair) swung open flat against the outside wall face
        wout = out_sign * (LW / 2 + 0.07)
        x = a1 + fr + 0.05
        bw = (a1 - a0) / 4 + 0.02
        for k in range(2):
            wbox(trim, axis, cl, x + k * bw, x + (k + 1) * bw - 0.03, wout - 0.06, wout + 0.06,
                 z0 - 0.05 + rng.uniform(-0.03, 0.03), z1 + 0.05 + rng.uniform(-0.03, 0.03), "door")
        for zz in (z0 + 0.35, z1 - 0.6):
            wbox(trim, axis, cl, x + 0.08, x + 2 * bw - 0.12, wout + out_sign * 0.06, wout + out_sign * 0.15,
                 zz, zz + 0.28, "door")


def build_cabin(seed=11):
    rng = random.Random(seed)
    logs, chink, floor, porch, steps, posts = MB(), MB(), MB(), MB(), MB(), MB()
    roof, proof, stone, found, trim, glass, interior = MB(), MB(), MB(), MB(), MB(), MB(), MB()

    # ---------------------------------------------------------------- log walls
    zf = [Z0F + i * S for i in range(9)]
    door_cut = (DOOR[0] - JAMB, DOOR[1] + JAMB, DOOR[2], DOOR[3])
    winf_cut = (WIN_F[0] - 0.2, WIN_F[1] + 0.2, WIN_F[2], WIN_F[3])
    winb_cut = (WIN_B[0] - 0.2, WIN_B[1] + 0.2, WIN_B[2], WIN_B[3])
    wall(logs, chink, "x", YC, zf, [door_cut, winf_cut], rng)
    wall(logs, chink, "x", -YC, zf, [winb_cut], rng)
    zs = [0.655] + [Z0S + i * S for i in range(12)]
    hs = [0.61] + [LH] * 12
    winw_cut = (WIN_W[0] - 0.2, WIN_W[1] + 0.2, WIN_W[2], WIN_W[3])
    wall(logs, chink, "y", -XC, zs, [winw_cut], rng, clip=gable_clip, heights=hs)
    wall(logs, chink, "y", XC, zs, [], rng, clip=gable_clip, heights=hs)

    # ---------------------------------------------------------------- foundation (crisp fieldstones under the sills)
    for (axis, c) in (("x", YC), ("x", -YC), ("y", XC), ("y", -XC)):
        half = (W2 if axis == "x" else D2) + 0.2
        a = -half
        while a < half:
            ln = rng.uniform(0.9, 1.5)
            mid = min(a + ln / 2, half - 0.3)
            off = rng.uniform(-0.12, 0.12)
            ctr = (mid, c + off, 0.0) if axis == "x" else (c + off, mid, 0.0)
            chunk_rock(found, rng, ctr, ln / 2 + 0.08, 0.55, 0.42, mk="fstone", n=14, cuts=2, flat_top=0.82)
            a += ln * 0.92
    # ---------------------------------------------------------------- floor (interior planks along X)
    y = -D2 + LW - 0.05
    while y < D2 - LW + 0.05 - 0.3:
        wdt = min(0.92, D2 - LW + 0.05 - y)
        box(floor, (-W2 + LW - 0.05, y, FLOOR - 0.2 + rng.uniform(-0.01, 0.0)), (W2 - LW + 0.05, y + wdt - 0.03,
                                                                                     FLOOR), "plank")
        y += wdt
    # ---------------------------------------------------------------- porch deck, rim, piers, steps
    x = -W2 + 0.4
    while x < W2 - 0.4 - 0.2:
        wdt = min(0.92, W2 - 0.4 - x)
        box(porch, (x, D2, DECK_TOP - 0.18 + rng.uniform(-0.015, 0.0)),
            (x + wdt - 0.06, PORCH_Y1 + rng.uniform(-0.06, 0.14), DECK_TOP + rng.uniform(-0.01, 0.01)), "plank")
        x += wdt
    hewn(porch, (-W2 + 0.35, PORCH_Y1 - 0.3, 0.85), (W2 - 0.35, PORCH_Y1 - 0.3, 0.85), 0.55, 0.62, 0.1, rng,
         mk="post", end_mk="log_end")
    for sx in (-1, 1):
        hewn(porch, (sx * (W2 - 0.65), D2 - 0.1, 0.85), (sx * (W2 - 0.65), PORCH_Y1 - 0.4, 0.85), 0.5, 0.62, 0.1,
             rng, mk="post", end_mk="log_end")
    for px in (-W2 + 0.7, -3.4, 3.4, W2 - 0.7):
        chunk_rock(porch, rng, (px, PORCH_Y1 - 0.3, 0.2), 0.62, 0.55, 0.42, mk="fstone", n=12, cuts=2,
                   flat_top=0.85)
    hewn(steps, (-2.45, PORCH_Y1 + 0.42, 0.44), (2.45, PORCH_Y1 + 0.42, 0.44), 0.85, 0.88, 0.1, rng, mk="post",
         end_mk="log_end")
    hewn(steps, (-2.35, PORCH_Y1 + 1.25, 0.2), (2.35, PORCH_Y1 + 1.25, 0.2), 0.85, 0.5, 0.09, rng, mk="post",
         end_mk="log_end")

    # ---------------------------------------------------------------- posts, beam, braces
    beam_y = PORCH_Y1 - 0.25
    under = PZ - (beam_y - D2) * math.tan(PORCH_PITCH)          # porch roof deck underside above the beam
    beam_top = under - 0.36                                      # rafters sit on the beam
    beam_bot = beam_top - 0.56
    post_x = (-W2 + 0.85, -2.7, 2.7, W2 - 0.85)
    for px in post_x:
        hewn(posts, (px, beam_y, DECK_TOP), (px, beam_y, beam_bot + 0.05), 0.62, 0.62, 0.13, rng, mk="post",
             end_mk="log_end", up=Vector((0, 1, 0)))
    hewn(posts, (-W2 + 0.2, beam_y, beam_bot + 0.28), (W2 - 0.2, beam_y, beam_bot + 0.28), 0.52, 0.56, 0.1, rng,
         mk="post", end_mk="log_end")
    for (px, dirx) in ((post_x[0], 1), (post_x[1], -1), (post_x[2], 1), (post_x[3], -1)):
        a = Vector((px + dirx * 0.25, beam_y, beam_bot - 1.15))
        b = Vector((px + dirx * 1.35, beam_y, beam_bot + 0.1))
        hewn(posts, a, b, 0.26, 0.3, 0.06, rng, mk="post", end_mk="log_end", up=Vector((0, 1, 0)))

    # ---------------------------------------------------------------- main roof (deck, shingles, ridge, barge boards)
    s_front = (D2 + EAVE_F) / math.cos(PITCH)
    s_back = (D2 + EAVE_B) / math.cos(PITCH)
    for sign, s_e in ((1, s_front), (-1, s_back)):
        sl = Slope((0.0, 0.0, RIDGE_U), PITCH, sign)
        slab(roof, sl, ROOF_X0, ROOF_X1, -0.02, s_e, 0.0, 0.22, "deck")
        shingles(roof, sl, ROOF_X0, ROOF_X1, s_e, 0.0, rng)
        slab(roof, sl, ROOF_X0 - 0.06, ROOF_X1 + 0.06, -0.14, 0.72, 0.44, 0.58, "ridge")
        for bx in (ROOF_X0 - 0.1, ROOF_X1 + 0.1):
            slab(roof, sl, bx - 0.1, bx + 0.1, -0.05, s_e + 0.05, -0.12, 0.62, "ridge")
    # ---------------------------------------------------------------- porch roof (lean-to under the short front eave)
    slp = Slope((0.0, D2, PZ), PORCH_PITCH, 1)
    s_p = (PORCH_Y1 + 0.55 - D2) / math.cos(PORCH_PITCH)
    px0, px1 = -W2 - 0.25, W2 + 0.25
    slab(proof, slp, px0, px1, 0.0, s_p, 0.0, 0.2, "deck")
    shingles(proof, slp, px0, px1, s_p, 0.05, rng)
    for bx in (px0 - 0.08, px1 + 0.08):
        slab(proof, slp, bx - 0.09, bx + 0.09, 0.0, s_p + 0.04, -0.1, 0.5, "ridge")
    for rx in np.linspace(-W2 + 0.5, W2 - 0.5, 7):
        slab(proof, slp, rx - 0.15, rx + 0.15, 0.05, s_p - 0.2, -0.36, 0.0, "deck")
    slab(proof, slp, -W2 + 0.2, W2 - 0.2, 0.0, 0.32, -0.62, -0.36, "deck")        # ledger on the wall

    # ---------------------------------------------------------------- chimney (east gable): core + stone blocks
    fb = (W2, W2 + 2.6, -1.55, 1.55, -0.3, 5.6)
    st = (W2 + 0.45, W2 + 2.05, -0.9, 0.9, 6.9, 18.3)
    box(stone, (fb[0], fb[2], fb[4]), (fb[1] - 0.02, fb[3], fb[5]), "mortar")
    box(stone, (st[0] + 0.02, st[2] + 0.02, fb[5] - 0.2), (st[1] - 0.02, st[3] - 0.02, st[5]), "mortar")
    stone_face(stone, (fb[1], fb[2], 0), (0, 1, 0), (1, 0, 0), fb[3] - fb[2], fb[4], fb[5], rng)
    stone_face(stone, (fb[0], fb[3], 0), (1, 0, 0), (0, 1, 0), fb[1] - fb[0], fb[4], fb[5], rng)
    stone_face(stone, (fb[1], fb[2], 0), (-1, 0, 0), (0, -1, 0), fb[1] - fb[0], fb[4], fb[5], rng)
    stone_face(stone, (st[1], st[2], 0), (0, 1, 0), (1, 0, 0), st[3] - st[2], st[4], st[5], rng)
    stone_face(stone, (st[0], st[3], 0), (1, 0, 0), (0, 1, 0), st[1] - st[0], st[4], st[5], rng)
    stone_face(stone, (st[1], st[2], 0), (-1, 0, 0), (0, -1, 0), st[1] - st[0], st[4], st[5], rng)
    stone_face(stone, (st[0], st[3], 0), (0, -1, 0), (-1, 0, 0), st[3] - st[2], st[4], st[5], rng)
    # shoulder: sloped stone weathering from the firebox to the stack
    stone.new_vol()
    lo = [Vector((fb[0], fb[2] - 0.12, fb[5])), Vector((fb[1] + 0.12, fb[2] - 0.12, fb[5])),
          Vector((fb[1] + 0.12, fb[3] + 0.12, fb[5])), Vector((fb[0], fb[3] + 0.12, fb[5]))]
    hi = [Vector((st[0], st[2] - 0.1, st[4])), Vector((st[1] + 0.1, st[2] - 0.1, st[4])),
          Vector((st[1] + 0.1, st[3] + 0.1, st[4])), Vector((st[0], st[3] + 0.1, st[4]))]
    li = [stone.v(q) for q in lo]
    hi_ = [stone.v(q) for q in hi]
    for k in range(4):
        kk = (k + 1) % 4
        mid = (lo[k] + lo[kk] + hi[k] + hi[kk]) / 4
        out = mid - Vector(((fb[0] + fb[1]) / 2, 0.0, mid.z))
        out.z = 0.6
        stone.fo((li[k], li[kk], hi_[kk], hi_[k]), "stone", out)
    stone.fo(li, "stone", -UP)
    box(stone, (st[0] - 0.18, st[2] - 0.18, st[5]), (st[1] + 0.18, st[3] + 0.18, st[5] + 0.26), "stone")
    box(stone, (st[0] + 0.45, st[2] + 0.42, st[5] + 0.1), (st[1] - 0.45, st[3] - 0.42, st[5] + 0.28), "flue")

    # ---------------------------------------------------------------- door, jambs, windows
    for jx in ((DOOR[0] - JAMB, DOOR[0]), (DOOR[1], DOOR[1] + JAMB)):
        box(trim, (jx[0], YC - 0.5, DOOR[2]), (jx[1], YC + 0.55, DOOR[3]), "frame")
    box(trim, (DOOR[0] - JAMB - 0.06, YC - 0.5, DOOR[3]), (DOOR[1] + JAMB + 0.06, YC + 0.58, DOOR[3] + 0.18), "frame")
    d_start = len(trim.V)
    hinge = Vector((DOOR[0] + 0.05, YC - 0.3, 0.0))
    bw = (DOOR[1] - DOOR[0] - 0.1) / 5
    for k in range(5):
        xa = DOOR[0] + 0.05 + k * bw
        box(trim, (xa, YC - 0.38, DOOR[2] + 0.02), (xa + bw - 0.03, YC - 0.2, DOOR[3] - 0.04 + rng.uniform(-0.04, 0.0)),
            "door")
    for zz in (DOOR[2] + 0.9, DOOR[3] - 1.3):
        box(trim, (DOOR[0] + 0.2, YC - 0.5, zz), (DOOR[1] - 0.2, YC - 0.38, zz + 0.42), "door")
        box(trim, (DOOR[0] + 0.05, YC - 0.2, zz + 0.1), (DOOR[0] + 2.7, YC - 0.16, zz + 0.26), "iron")
    brace = Matrix.Translation(((DOOR[0] + DOOR[1]) / 2, YC - 0.44, (DOOR[2] + DOOR[3]) / 2 - 0.2)) @ \
        Matrix.Rotation(math.atan2(4.4, 3.2), 4, "Y").inverted()
    box(trim, (-2.65, -0.06, -0.19), (2.65, 0.06, 0.19), "door", mat=brace)
    box(trim, (DOOR[1] - 0.45, YC - 0.17, 4.9), (DOOR[1] - 0.3, YC - 0.08, 5.15), "iron")
    trim.transform(d_start, Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(-98), 4, "Z") @
                   Matrix.Translation(-hinge))
    window(trim, glass, "x", YC, WIN_F, 1, rng, shutter=True)
    window(trim, glass, "x", -YC, WIN_B, -1, rng)
    window(trim, glass, "y", -XC, WIN_W, -1, rng)

    # ---------------------------------------------------------------- interior (seen through the door)
    for (lo_, hi_) in (((-6.6, -4.4, FLOOR), (-6.35, -4.15, FLOOR + 2.4)), ((-4.4, -4.4, FLOOR), (-4.15, -4.15, FLOOR + 2.4)),
                       ((-6.6, -3.2, FLOOR), (-6.35, -2.95, FLOOR + 2.4)), ((-4.4, -3.2, FLOOR), (-4.15, -2.95, FLOOR + 2.4))):
        box(interior, lo_, hi_, "post")
    box(interior, (-6.8, -4.6, FLOOR + 2.4), (-3.95, -2.75, FLOOR + 2.62), "plank")
    box(interior, (-6.8, -2.3, FLOOR + 1.35), (-3.95, -1.75, FLOOR + 1.5), "plank")
    for bx in (-6.5, -4.3):
        box(interior, (bx, -2.2, FLOOR), (bx + 0.2, -1.85, FLOOR + 1.35), "post")
    box(interior, (3.2, -5.05, FLOOR), (7.05, -2.2, FLOOR + 1.6), "post")
    box(interior, (3.35, -4.95, FLOOR + 1.6), (6.95, -2.3, FLOOR + 2.0), "cloth")
    for zz in (FLOOR + 3.8, FLOOR + 5.0):
        box(interior, (-1.5, -5.08, zz), (1.5, -4.6, zz + 0.12), "plank")

    parts = {"Logs": logs, "Chinking": chink, "Floor": floor, "Porch": porch, "Steps": steps, "Posts": posts,
             "Roof": roof, "PorchRoof": proof, "Chimney": stone, "Foundation": found, "Trim": trim, "Glass": glass,
             "Interior": interior}
    info = {"door": (0.0, D2, FLOOR)}
    return parts, {}, info


# =============================================================================================== asset table
# part -> (role, robloxMaterial, collide, collision, castShadow, tags, transparency, texture set)
ASSETS = [
    {"name": "StyleA_Spruce", "kind": "Tree", "build": build_spruce, "sets": {"StyleA_Spruce": 1024},
     "notes": "Low-poly realism spruce ~42 studs. Needle tiers are closed faceted volumes (no cards).",
     "parts": {"Bark": ("Bark", "Wood", True, "Hull", True, [], 0.0, "StyleA_Spruce"),
               "Needles": ("PineNeedles", "LeafyGrass", False, "Box", True, [], 0.0, "StyleA_Spruce"),
               "Deadwood": ("DeadWood", "Wood", False, "Box", False, [], 0.0, "StyleA_Spruce")}},
    {"name": "StyleA_Oak", "kind": "Tree", "build": build_oak, "sets": {"StyleA_Oak": 1024},
     "notes": "Low-poly realism oak ~27 studs; climbable trunk and limbs (Climbable, Perch1-2).",
     "parts": {"Bark": ("Bark", "Wood", True, "PreciseConvexDecomposition", True, ["Climbable"], 0.0, "StyleA_Oak"),
               "Leaves": ("Leaves", "LeafyGrass", False, "Box", True, [], 0.0, "StyleA_Oak")}},
    {"name": "StyleA_HunterCabin", "kind": "Building", "build": build_cabin,
     "sets": {"StyleA_Cabin": 1024, "StyleA_CabinRoof": 1024},
     "notes": "Hewn-log hunter's cabin: log walls 16 x 12, porch 5 deep, door opening 4 x 7.5 (door open inward).",
     "parts": {"Logs": ("Logs", "Wood", True, "PreciseConvexDecomposition", True, [], 0.0, "StyleA_Cabin"),
               "Chinking": ("Plaster", "Plaster", False, "Box", True, [], 0.0, "StyleA_Cabin"),
               "Floor": ("Planks", "WoodPlanks", True, "Box", True, ["Floor"], 0.0, "StyleA_Cabin"),
               "Porch": ("Planks", "WoodPlanks", True, "Box", True, ["Floor"], 0.0, "StyleA_Cabin"),
               "Steps": ("Wood", "Wood", True, "Hull", True, [], 0.0, "StyleA_Cabin"),
               "Posts": ("Wood", "Wood", True, "PreciseConvexDecomposition", True, [], 0.0, "StyleA_Cabin"),
               "Roof": ("Shingles", "WoodPlanks", True, "Hull", True, [], 0.0, "StyleA_CabinRoof"),
               "PorchRoof": ("Shingles", "WoodPlanks", True, "Hull", True, [], 0.0, "StyleA_CabinRoof"),
               "Chimney": ("Stone", "Cobblestone", True, "Hull", True, [], 0.0, "StyleA_Cabin"),
               "Foundation": ("Stone", "Rock", False, "Box", True, [], 0.0, "StyleA_Cabin"),
               "Trim": ("Wood", "Wood", False, "Box", True, [], 0.0, "StyleA_Cabin"),
               "Glass": ("Glass", "Glass", False, "Box", False, [], 0.15, "StyleA_Cabin"),
               "Interior": ("Wood", "Wood", False, "Box", True, [], 0.0, "StyleA_Cabin")}},
    {"name": "StyleA_Boulder", "kind": "Rock", "build": build_boulder, "sets": {"StyleA_Boulder": 512},
     "notes": "Low-poly realism boulder ~6 studs, base sunk 0.45 below the pivot so it seats into terrain.",
     "parts": {"Rock": ("Stone", "Rock", True, "Hull", True, [], 0.0, "StyleA_Boulder")}},
]
# bake parameters per texture set: AO near / far distance, AO strength, normal bump
BAKE = {"StyleA_Spruce": dict(near=1.2, far=7.0, strength=0.78, pn=0.8, pf=0.9),
        "StyleA_Oak": dict(near=1.2, far=7.0, strength=0.76, pn=0.8, pf=0.9),
        "StyleA_Cabin": dict(near=0.7, far=4.0, strength=0.7, pn=0.9, pf=0.7),
        "StyleA_CabinRoof": dict(near=0.5, far=3.0, strength=0.62, pn=0.9, pf=0.6),
        "StyleA_Boulder": dict(near=0.6, far=2.5, strength=0.6, pn=0.8, pf=0.6)}


# =============================================================================================== scene / cycles
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_material(name):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    return m


def cycles_setup(scene, samples, denoise=False):
    dev = tg.enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = False
    c.use_denoising = denoise
    return dev


def link_only(nt, out_socket, in_socket):
    for l in list(in_socket.links):
        nt.links.remove(l)
    nt.links.new(out_socket, in_socket)


# =============================================================================================== baking
def bake_material(name, near, far):
    m = new_material(name)
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    ac = N.new("ShaderNodeAttribute")
    ac.attribute_name = "bk_col"
    am = N.new("ShaderNodeAttribute")
    am.attribute_name = "bk_misc"
    sep = N.new("ShaderNodeSeparateColor")
    L.new(am.outputs["Color"], sep.inputs["Color"])
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.2
    nz.inputs["Detail"].default_value = 1.0
    nz.inputs["Roughness"].default_value = 0.5
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    mr = N.new("ShaderNodeMapRange")
    mr.clamp = True
    mr.inputs[1].default_value = 0.3
    mr.inputs[2].default_value = 0.7
    mr.inputs[3].default_value = 0.93
    mr.inputs[4].default_value = 1.07
    L.new(nz.outputs[0], mr.inputs[0])
    mul = N.new("ShaderNodeVectorMath")
    mul.operation = "SCALE"
    L.new(ac.outputs["Color"], mul.inputs[0])
    L.new(mr.outputs[0], mul.inputs["Scale"])
    em = N.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    aon = N.new("ShaderNodeAmbientOcclusion")
    aon.samples = 16
    aon.inputs["Distance"].default_value = near
    aof = N.new("ShaderNodeAmbientOcclusion")
    aof.samples = 16
    aof.inputs["Distance"].default_value = far
    bev = N.new("ShaderNodeBevel")
    bev.samples = 8
    L.new(sep.outputs["Blue"], bev.inputs["Radius"])
    sc = N.new("ShaderNodeVectorMath")
    sc.operation = "MULTIPLY"
    sc.inputs[1].default_value = (2.2, 2.2, 0.5)
    L.new(tc.outputs["Object"], sc.inputs[0])
    vor = N.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 1.0
    L.new(sc.outputs[0], vor.inputs["Vector"])
    hm = N.new("ShaderNodeMapRange")
    hm.clamp = True
    hm.inputs[1].default_value = 0.0
    hm.inputs[2].default_value = 0.22
    L.new(vor.outputs["Distance"], hm.inputs[0])
    mm = N.new("ShaderNodeMath")
    mm.operation = "MULTIPLY"
    L.new(hm.outputs[0], mm.inputs[0])
    L.new(sep.outputs["Green"], mm.inputs[1])
    vd = N.new("ShaderNodeTexVoronoi")
    vd.feature = "F1"
    vd.inputs["Scale"].default_value = 2.4
    vd.inputs["Randomness"].default_value = 0.8
    L.new(tc.outputs["Object"], vd.inputs["Vector"])
    dmr = N.new("ShaderNodeMapRange")
    dmr.interpolation_type = "SMOOTHSTEP"
    dmr.clamp = True
    dmr.inputs[1].default_value = 0.0
    dmr.inputs[2].default_value = 0.62
    dmr.inputs[3].default_value = 0.0
    dmr.inputs[4].default_value = 0.4
    L.new(vd.outputs["Distance"], dmr.inputs[0])
    dmm = N.new("ShaderNodeMath")
    dmm.operation = "MULTIPLY"
    L.new(dmr.outputs[0], dmm.inputs[0])
    L.new(am.outputs["Alpha"], dmm.inputs[1])
    hsum = N.new("ShaderNodeMath")
    hsum.operation = "ADD"
    L.new(mm.outputs[0], hsum.inputs[0])
    L.new(dmm.outputs[0], hsum.inputs[1])
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.05
    L.new(hsum.outputs[0], bump.inputs["Height"])
    L.new(bev.outputs["Normal"], bump.inputs["Normal"])
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    img = N.new("ShaderNodeTexImage")
    N.active = img
    return m, {"nt": nt, "out": out, "em": em, "mul": mul, "aon": aon, "aof": aof, "sep": sep, "bsdf": bsdf,
               "img": img}


def set_bake_pass(h, which):
    nt, em, out = h["nt"], h["em"], h["out"]
    for l in list(em.inputs["Color"].links):
        nt.links.remove(l)
    if which == "normal":
        link_only(nt, h["bsdf"].outputs["BSDF"], out.inputs["Surface"])
        return
    link_only(nt, em.outputs["Emission"], out.inputs["Surface"])
    src = {"color": h["mul"].outputs[0], "aon": h["aon"].outputs["AO"], "aof": h["aof"].outputs["AO"],
           "rough": h["sep"].outputs["Red"]}.get(which)
    if src is None:
        em.inputs["Color"].default_value = (1, 1, 1, 1)
    else:
        nt.links.new(src, em.inputs["Color"])


def uv_unwrap(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.002, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", scale=True, margin_method="FRACTION", margin=0.0016,
                            shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")


def blur_masked(a, m, sigma):
    w = m.astype(np.float64)
    num = tg.pblur(a * w, sigma)
    den = tg.pblur(w, sigma)
    out = np.where(den > 1e-4, num / np.maximum(den, 1e-4), a)
    return np.where(m, out, a)


def bake_set(set_name, objs, size, scene, ground):
    """UV-unwrap the set's parts together and bake colour, AO (2 radii), roughness and normal into one texture set."""
    p = BAKE[set_name]
    uv_unwrap(objs)
    mat, h = bake_material("BK_" + set_name, p["near"], p["far"])
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    for o in scene.objects:
        o.hide_render = not (o in objs or o is ground)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    rb = scene.render.bake
    rb.margin = 0
    rb.use_clear = True
    rb.target = "IMAGE_TEXTURES"
    maps = {}
    for which, spp in (("cover", 1), ("color", 4), ("rough", 1), ("aon", 48), ("aof", 64), ("normal", 16)):
        img = bpy.data.images.new("bk_%s_%s" % (set_name, which), size, size, alpha=True, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        h["img"].image = img
        h["nt"].nodes.active = h["img"]
        set_bake_pass(h, which)
        scene.cycles.samples = spp
        t = time.time()
        if which == "normal":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y",
                                normal_b="POS_Z", margin=0, use_clear=True, target="IMAGE_TEXTURES")
        else:
            bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True, target="IMAGE_TEXTURES")
        maps[which] = tg.image_to_np(img).astype(np.float64)
        bpy.data.images.remove(img)
        log("  bake %s %s %.1fs" % (set_name, which, time.time() - t))
    for o in scene.objects:
        o.hide_render = False
    cov = maps["cover"][..., 0] > 0.5
    col = maps["color"][..., :3]
    aon = blur_masked(np.clip(maps["aon"][..., 0], 0, 1), cov, 1.1)
    aof = blur_masked(np.clip(maps["aof"][..., 0], 0, 1), cov, 1.8)
    ao = np.clip(aon, 0, 1) ** p["pn"] * np.clip(aof, 0, 1) ** p["pf"]
    term = 1.0 - p["strength"] * (1.0 - ao)
    out = col * term[..., None]
    rough = np.clip(maps["rough"][..., 0] + 0.05 * (1.0 - aon), 0.02, 1.0)
    nrm = maps["normal"][..., :3]
    w = cov.astype(np.float64)
    out = tg.pushpull(out, w)
    rough = tg.pushpull(rough[..., None], w)[..., 0]
    nrm = tg.pushpull(nrm, w)
    nrm = tg.encode_normal(nrm * 2.0 - 1.0)
    files = {"color": set_name + "_Color.png", "normal": set_name + "_Normal.png", "rough": set_name + "_Rough.png",
             "mr": set_name + "_MR.png"}
    tg.write_png(os.path.join(TEX, files["color"]), tg.lin_to_srgb(out))
    tg.write_png(os.path.join(TEX, files["normal"]), nrm, quantize=False)
    tg.write_png(os.path.join(TEX, files["rough"]), rough)
    r2 = rough
    while r2.shape[0] > 512:
        r2 = 0.25 * (r2[0::2, 0::2] + r2[1::2, 0::2] + r2[0::2, 1::2] + r2[1::2, 1::2])
    tg.write_png(os.path.join(GLB_ONLY, files["mr"]), np.stack([r2, r2, np.zeros_like(r2)], axis=2))
    coverage = float(cov.mean())
    log("  set %s: coverage %.1f%%, mean albedo sRGB %s" % (set_name, 100 * coverage,
                                                             [int(v) for v in l2s255(out[cov].mean(0))]))
    return files, coverage, mat


def export_material(set_name, files):
    m = new_material(set_name)
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf is None:
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def img(path, cs):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    tc = img(os.path.join(TEX, files["color"]), "sRGB")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = img(os.path.join(TEX, files["normal"]), "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tr = img(os.path.join(GLB_ONLY, files["mr"]), "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    m.use_backface_culling = True
    return m


# =============================================================================================== GLB checks
def _glb_split(data):
    magic, ver, length = struct.unpack("<III", data[:12])
    clen, ctype = struct.unpack("<II", data[12:20])
    return ver, json.loads(data[20:20 + clen].decode("utf-8")), data[20 + clen:]


def glb_patch_and_check(path):
    with open(path, "rb") as f:
        data = f.read()
    ver, js, rest = _glb_split(data)
    for m in js.get("materials", []):
        m.setdefault("pbrMetallicRoughness", {})["metallicFactor"] = 0
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, ver, 12 + len(body)) + body)
    problems = []
    need = ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0")
    nprim = 0
    for me in js.get("meshes", []):
        for prim in me.get("primitives", []):
            nprim += 1
            miss = [k for k in need if k not in prim.get("attributes", {})]
            if miss:
                problems.append("%s lacks %s" % (me.get("name"), ",".join(miss)))
    for m in js.get("materials", []):
        if m.get("doubleSided"):
            problems.append("material %s is doubleSided" % m.get("name"))
        if "normalTexture" not in m or "baseColorTexture" not in m.get("pbrMetallicRoughness", {}):
            problems.append("material %s lacks textures" % m.get("name"))
    size = os.path.getsize(path)
    if size >= 19_000_000:
        problems.append("GLB is %.2f MB" % (size / 1e6))
    return {"primitives": nprim, "meshes": len(js.get("meshes", [])), "images": [i.get("name") for i in
                                                                                   js.get("images", [])],
            "materials": [m.get("name") for m in js.get("materials", [])], "bytes": size,
            "tangentsOnEveryPrimitive": not any("TANGENT" in p for p in problems)}, problems


def png_info(path):
    with open(path, "rb") as f:
        head = f.read(33)
    w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
    return {"size": [w, h], "bitDepth": bd, "channels": {0: "gray", 2: "RGB", 4: "gray+alpha", 6: "RGBA"}.get(ct),
            "bytes": os.path.getsize(path)}


def to_roblox(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


# =============================================================================================== ASSETS STAGE
def assets_stage():
    reset()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    dev = cycles_setup(scene, 16)
    log("ASSETS on", dev)
    built = []
    for spec in ASSETS:
        t = time.time()
        mbs, ctx, info = spec["build"]()
        root = bpy.data.objects.new(spec["name"], None)
        root.empty_display_type = "PLAIN_AXES"
        scene.collection.objects.link(root)
        parts = []
        for pname, mb in mbs.items():
            if not mb.F:
                continue
            obj = mb.build("%s_%s" % (spec["name"], pname))
            finalize(obj, ctx)
            obj.parent = root
            parts.append((pname, obj))
        built.append((spec, root, parts, info))
        log("built %s: %s (%.1fs)" % (spec["name"], ", ".join("%s %d" % (n, len(o.data.polygons)) for n, o in parts),
                                      time.time() - t))
    # ground plane for contact AO during the bakes
    gme = bpy.data.meshes.new("_BakeGround")
    gme.from_pydata([(-200, -200, 0), (200, -200, 0), (200, 200, 0), (-200, 200, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new("_BakeGround", gme)
    scene.collection.objects.link(ground)
    gm = new_material("_BakeGroundMat")
    ground.data.materials.append(gm)
    set_files = {}
    for spec, root, parts, info in built:
        for set_name, size in spec["sets"].items():
            objs = [o for (pn, o) in parts if spec["parts"][pn][7] == set_name]
            t = time.time()
            files, cov, _m = bake_set(set_name, objs, size, scene, ground)
            set_files[set_name] = dict(files, size=size, coverage=cov)
            log("baked %s (%d parts) in %.1fs" % (set_name, len(objs), time.time() - t))
    bpy.data.objects.remove(ground, do_unlink=True)
    # export materials, strip bake attributes
    exp_mats = {k: export_material(k, v) for k, v in set_files.items()}
    for spec, root, parts, info in built:
        for pn, o in parts:
            o.data.materials.clear()
            o.data.materials.append(exp_mats[spec["parts"][pn][7]])
            for an in ("mk", "vol", "g"):
                a = o.data.attributes.get(an)
                if a is not None:
                    o.data.attributes.remove(a)
            for an in ("bk_col", "bk_misc"):
                a = o.data.color_attributes.get(an)
                if a is not None:
                    o.data.color_attributes.remove(a)
    # manifest entries + row layout
    entries = []
    x = 0.0
    bpy.context.view_layer.update()
    for spec, root, parts, info in built:
        lo = np.array([1e9] * 3)
        hi = np.array([-1e9] * 3)
        pentries = []
        for pn, o in parts:
            co = np.empty(len(o.data.vertices) * 3, np.float32)
            o.data.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            lo = np.minimum(lo, co.min(0))
            hi = np.maximum(hi, co.max(0))
            role, rmat, collide, coll, shadow, tags, transp, set_name = spec["parts"][pn]
            f = set_files[set_name]
            tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
            if tris > 20000:
                raise ValueError("%s has %d tris" % (o.name, tris))
            pentries.append({
                "name": o.name, "role": role, "robloxMaterial": rmat, "rgb": list(o["rgb"]),
                "collide": bool(collide), "collision": coll if collide else "Box", "castShadow": bool(shadow),
                "canQuery": bool(collide), "canTouch": bool(collide), "tags": list(tags), "tris": tris,
                "textureSet": set_name,
                "surfaceAppearance": {"colorMap": REL_TEX + "/" + f["color"], "normalMap": REL_TEX + "/" + f["normal"],
                                      "roughnessMap": REL_TEX + "/" + f["rough"], "metalnessMap": None,
                                      "alphaMode": "Overlay", "color": [255, 255, 255]},
                "transparency": transp, "doubleSided": False, "backFacesInMesh": False, "neon": False,
                "renderFidelity": "Automatic"})
        a, b = to_roblox(lo), to_roblox(hi)
        e = {"name": spec["name"], "kind": spec["kind"], "tags": ["StyleTest", "VariantA"], "notes": spec["notes"],
             "glb": GLB_NAME + ".glb",
             "boundsMin": [min(p, q) for p, q in zip(a, b)], "boundsMax": [max(p, q) for p, q in zip(a, b)],
             "size": [round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3), round(float(hi[1] - lo[1]), 3)],
             "tris": sum(p["tris"] for p in pentries), "parts": pentries, "attachments": {}}
        if lo[2] < -0.05:
            e["buriedDepth"] = round(float(-lo[2]), 3)
        if spec["name"] == "StyleA_Oak":
            for i, (q, d) in enumerate(info["perches"]):
                e["attachments"]["Perch%d" % (i + 1)] = {"position": to_roblox(q), "look": to_roblox(d),
                                                         "up": to_roblox(UP)}
        if spec["name"] == "StyleA_HunterCabin":
            e["attachments"]["Door"] = {"position": to_roblox(Vector(info["door"])), "look": to_roblox((0, 1, 0)),
                                        "up": to_roblox(UP)}
        offset = x - float(lo[0])
        root.location = (offset, 0.0, 0.0)
        e["origin"] = [round(offset, 4), 0.0, 0.0]
        x += float(hi[0] - lo[0]) + 8.0
        entries.append(e)
    bpy.context.view_layer.update()
    for o in scene.objects:
        o.select_set(False)
    for spec, root, parts, info in built:
        root.select_set(True)
        for pn, o in parts:
            o.select_set(True)
    glb = os.path.join(OUT, GLB_NAME + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_image_format="AUTO", export_materials="EXPORT", export_normals=True,
                              export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
                              export_attributes=False)
    check, problems = glb_patch_and_check(glb)
    log("GLBCHECK %s: %d meshes, %d primitives, %.2f MB, tangents everywhere %s, problems %s" % (
        os.path.basename(glb), check["meshes"], check["primitives"], check["bytes"] / 1e6,
        check["tangentsOnEveryPrimitive"], problems))
    upload = []
    for set_name, f in set_files.items():
        for kind in ("color", "normal", "rough"):
            info_ = png_info(os.path.join(TEX, f[kind]))
            upload.append(dict(file=REL_TEX + "/" + f[kind], kind={"rough": "roughness"}.get(kind, kind),
                               set=set_name, **info_))
    terrain = []
    for tname, tile, base in (("PebblePath", 8.0, "Pebble"), ("ForestFloor", 10.0, "Ground")):
        fn = {k: "StyleA_%s_%s.png" % (tname, k) for k in ("Color", "Normal", "Rough")}
        if all(os.path.exists(os.path.join(TEX, v)) for v in fn.values()):
            terrain.append({"name": "LS_StyleA_" + tname, "suggestedBaseMaterial": base,
                            "colorMap": REL_TEX + "/" + fn["Color"], "normalMap": REL_TEX + "/" + fn["Normal"],
                            "roughnessMap": REL_TEX + "/" + fn["Rough"], "metalnessMap": None,
                            "studsPerTile": tile, "materialPattern": "Organic",
                            "notes": "Seamless tile, modelled at true scale for StudsPerTile = %g. Organic pattern "
                                     "hides the repeat of the larger features (moss patches, big pebbles)." % tile})
            for k, v in fn.items():
                upload.append(dict(file=REL_TEX + "/" + v, kind={"Rough": "roughness"}.get(k, k.lower()),
                                   set="terrain:" + tname, **png_info(os.path.join(TEX, v))))
    manifest = {
        "schema": "LS-Real-1 (style test)", "category": GLB_NAME, "variant": "A", "styleName": "Low-poly realism",
        "glb": REL_OUT + "/" + GLB_NAME + ".glb",
        "glbs": [{"file": REL_OUT + "/" + GLB_NAME + ".glb", "assets": [e["name"] for e in entries],
                  "bytes": check["bytes"], "sizeMB": round(check["bytes"] / 1e6, 2),
                  "embeddedImages": check["images"]}],
        "units": "1 Blender unit = 1 Roblox stud",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
        "textureFolder": REL_TEX, "uploadTextures": upload,
        "glbOnlyTextures": [REL_TEX + "/glb_only/" + f["mr"] for f in set_files.values()],
        "textureSets": {k: {"colorMap": REL_TEX + "/" + v["color"], "normalMap": REL_TEX + "/" + v["normal"],
                            "roughnessMap": REL_TEX + "/" + v["rough"], "metalnessMap": None, "size": v["size"],
                            "uvCoverage": round(v["coverage"], 3)} for k, v in set_files.items()},
        "terrainMaterials": terrain,
        "import": [
            "Import the GLB; each asset root is a Model of MeshParts <Asset>_<Part>. Re-centre with 'origin' "
            "(WorldPivot = CFrame.new(origin), then PivotTo); the importer turns every asset 180 degrees about Y "
            "(measure and undo it as RealAssets does).",
            "Give every part ONE SurfaceAppearance from its 'surfaceAppearance' block (ColorMap, NormalMap, "
            "RoughnessMap; MetalnessMap empty; AlphaMode Overlay; Color white). Parts of one asset share one texture "
            "set, so upload each PNG once and reuse the ids.",
            "Per part: CanCollide = collide, CollisionFidelity = collision (edit time, via CreateMeshPartAsync), "
            "CastShadow, CanQuery, CanTouch, Anchored, Material = robloxMaterial, Color = rgb, Transparency = "
            "transparency (0.15 on the cabin glass), DoubleSided false.",
            "Tags: StyleA_Oak_Bark gets the CollectionService tag Climbable (Perch1-2 attachments on the limbs); "
            "StyleA_HunterCabin_Floor / _Porch get Floor. Door attachment = threshold centre, facing out.",
            "Terrain: create one MaterialVariant per 'terrainMaterials' entry (BaseMaterial as suggested, "
            "StudsPerTile as given) from the three PNGs.",
        ],
        "glbCheck": dict(check, problems=problems),
        "styleRules": STYLE_RULES,
        "assets": entries,
        "warnings": problems,
    }
    mpath = os.path.join(OUT, GLB_NAME + ".manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    repo = os.path.normpath(os.path.join(HERE, "..", "manifests"))
    os.makedirs(repo, exist_ok=True)
    with open(os.path.join(repo, GLB_NAME + ".manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    log("MANIFEST", mpath, "(+ copy in art/manifests)")
    for e in entries:
        log("ASSET %-20s size %s tris %d parts %s" % (e["name"], e["size"], e["tris"],
                                                     ", ".join("%s:%d" % (p["name"].split("_")[-1], p["tris"])
                                                               for p in e["parts"])))
    return manifest


# =============================================================================================== GROUND TILES
def data_material(ao_dist):
    m = new_material("GroundData")
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    ac = N.new("ShaderNodeAttribute")
    ac.attribute_name = "albedo"
    ar = N.new("ShaderNodeAttribute")
    ar.attribute_name = "rough"
    geo = N.new("ShaderNodeNewGeometry")
    vm = N.new("ShaderNodeVectorMath")
    vm.operation = "MULTIPLY_ADD"
    L.new(geo.outputs["Normal"], vm.inputs[0])
    vm.inputs[1].default_value = (0.5, 0.5, 0.5)
    vm.inputs[2].default_value = (0.5, 0.5, 0.5)
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.samples = 8
    ao.inputs["Distance"].default_value = ao_dist
    em = N.new("ShaderNodeEmission")
    L.new(em.outputs["Emission"], out.inputs["Surface"])
    return m, {"nt": nt, "em": em, "src": {"albedo": ac.outputs["Color"], "rough": ar.outputs["Factor"],
                                            "normal": vm.outputs[0], "ao": ao.outputs["AO"]}}


def periodic_height(T, seed, amp):
    rng = np.random.RandomState(seed)
    waves = []
    for _ in range(7):
        kx, ky = rng.randint(-3, 4), rng.randint(-3, 4)
        if kx == 0 and ky == 0:
            kx = 1
        waves.append((kx, ky, rng.uniform(0, TAU), amp * rng.uniform(0.4, 1.0) / math.hypot(kx, ky) ** 0.5))

    def h(x, y):
        return sum(a * np.sin(TAU * (kx * x + ky * y) / T + ph) for (kx, ky, ph, a) in waves)
    return h


def ground_plane(T, colour, rough, h, step=0.06, margin=0.8):
    n = int(round((T + 2 * margin) / step)) + 1
    xs = np.linspace(-margin, T + margin, n)
    X, Y = np.meshgrid(xs, xs)
    Z = h(X, Y)
    V = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    idx = np.arange(n * n).reshape(n, n)
    F = np.stack([idx[:-1, :-1].ravel(), idx[:-1, 1:].ravel(), idx[1:, 1:].ravel(), idx[1:, :-1].ravel()], 1)
    obj = tg.mesh_object("GroundBase", V, F)
    tg.set_point_color(obj.data, "albedo", np.tile(s2l(colour), (len(V), 1)))
    tg.set_point_float(obj.data, "rough", np.full(len(V), rough))
    obj.data.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    return obj


class Acc:
    """Fast accumulation of many small elements (numpy) with per-vertex albedo / roughness."""

    def __init__(self):
        self.V, self.F, self.C, self.R, self.S = [], [], [], [], []
        self.n = 0

    def add(self, V, F, col, rough, smooth):
        V = np.asarray(V, np.float64)
        F = np.asarray(F, np.int64)
        if F.shape[1] == 4:                      # keep one face size so the mesh can be built from arrays
            F = np.concatenate([F[:, [0, 1, 2]], F[:, [0, 2, 3]]])
        self.V.append(V)
        self.F.append(F + self.n)
        c = np.asarray(col, np.float64)
        self.C.append(np.tile(c, (len(V), 1)) if c.ndim == 1 else c)
        r = np.asarray(rough, np.float64)
        self.R.append(np.full(len(V), float(r)) if r.ndim == 0 else r)
        self.S.append(np.full(len(F), smooth, bool))
        self.n += len(V)

    def build(self, name):
        V = np.concatenate(self.V)
        F = np.concatenate(self.F)
        obj = tg.mesh_object(name, V, F)
        tg.set_point_color(obj.data, "albedo", np.concatenate(self.C))
        tg.set_point_float(obj.data, "rough", np.concatenate(self.R))
        obj.data.polygons.foreach_set("use_smooth", np.concatenate(self.S))
        return obj


def ico(sub):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    bm.verts.index_update()
    V = np.array([v.co[:] for v in bm.verts], np.float64)
    F = np.array([[v.index for v in f.verts] for f in bm.faces], np.int64)
    bm.free()
    return V, F


def wrap_offsets(x, y, r, T, m=0.8):
    out = []
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            cx, cy = x + i * T, y + j * T
            if cx + r > -m and cx - r < T + m and cy + r > -m and cy - r < T + m:
                out.append((i * T, j * T))
    return out


def poisson_periodic(rng, T, items, existing=None, tries=40, slack=0.9):
    """items: list of radii (placed largest first). Returns [(x, y, r)] without overlaps on the torus."""
    placed = list(existing or [])
    P = np.array([(p[0], p[1]) for p in placed], np.float64).reshape(-1, 2)
    Rr = np.array([p[2] for p in placed], np.float64)
    out = []
    for r in items:
        for _ in range(tries):
            x, y = rng.uniform(0, T), rng.uniform(0, T)
            if len(P):
                d = np.abs(P - (x, y))
                d = np.minimum(d, T - d)
                dist = np.hypot(d[:, 0], d[:, 1])
                if np.any(dist < (Rr + r) * slack):
                    continue
            P = np.vstack([P, (x, y)])
            Rr = np.append(Rr, r)
            out.append((x, y, r))
            break
    return out


def pebble_geom(rng, base, x, y, r, flat=(0.42, 0.7), sink=(-0.3, 0.1)):
    V0, F0 = base
    a, b = r * rng.uniform(1.0, 1.32), r * rng.uniform(0.74, 1.0)
    c = r * rng.uniform(*flat)
    w = rng.normal(size=(3, 3))
    w /= np.linalg.norm(w, axis=1, keepdims=True)
    ph = rng.uniform(0, TAU, 3)
    k = 1.0 + 0.07 * np.sin(V0 @ w.T * 2.2 + ph).sum(1)
    V = V0 * k[:, None]
    bottom = V[:, 2] < -0.25
    V[bottom, 2] = -0.25 + (V[bottom, 2] + 0.25) * 0.4          # flatter underside
    V = V * np.array([a, b, c])
    th, tilt = rng.uniform(0, TAU), rng.uniform(-0.18, 0.18)
    Rz = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
    Rx = np.array([[1, 0, 0], [0, math.cos(tilt), -math.sin(tilt)], [0, math.sin(tilt), math.cos(tilt)]])
    V = V @ (Rz @ Rx).T
    V += np.array([x, y, c * rng.uniform(*sink)])
    return V, F0


PEBBLE_PAL = [(146, 140, 128), (126, 120, 110), (106, 102, 96), (152, 132, 106), (130, 110, 88), (116, 116, 112),
              (164, 156, 142), (94, 88, 80), (138, 124, 100), (120, 106, 92)]


def build_pebble_tile(T, rng):
    h = periodic_height(T, 5, 0.035)
    objs = [ground_plane(T, (122, 104, 82), 0.94, h)]
    acc = Acc()
    big, mid_, small = ico(3), ico(3), ico(2)
    items = sorted([rng.uniform(0.3, 0.52) for _ in range(46)] + [rng.uniform(0.17, 0.3) for _ in range(210)] +
                   [rng.uniform(0.075, 0.16) for _ in range(900)], reverse=True)
    for (x, y, r) in poisson_periodic(rng, T, items, tries=60, slack=0.95):
        base = big if r > 0.3 else (mid_ if r > 0.16 else small)
        V, F = pebble_geom(rng, base, 0.0, 0.0, r, flat=(0.34, 0.56), sink=(-0.4, -0.05))
        col = np.array(PEBBLE_PAL[rng.randint(len(PEBBLE_PAL))], np.float64) * rng.uniform(0.94, 1.06)
        col = col + (np.array((122.0, 104.0, 82.0)) - col) * 0.14          # dusted with path dirt
        zt = (V[:, 2] - V[:, 2].min()) / max(np.ptp(V[:, 2]), 1e-6)
        cv = s2l(np.clip(col[None, :] * (0.9 + 0.14 * zt[:, None]), 0, 255))
        rough = rng.uniform(0.58, 0.8)
        for (dx, dy) in wrap_offsets(x, y, r * 1.4, T):
            Vw = V + np.array([x + dx, y + dy, h(x + dx, y + dy)])
            acc.add(Vw, F, cv, rough, True)
    objs.append(acc.build("Pebbles"))
    return objs


def leaf_geom(rng, kind):
    if kind == "oak":
        L = rng.uniform(0.34, 0.52)
        W = L * rng.uniform(0.44, 0.56)
        lobes = rng.choice([4, 5])
        n = 2 * lobes + 3
        xs = np.linspace(0, L, n)
        env = np.sin(np.pi * np.clip(xs / L, 0, 1) ** 0.75) ** 0.85
        w = 0.5 * W * env * (0.6 + 0.4 * np.abs(np.cos(np.pi * lobes * xs / L)))
    elif kind == "birch":
        L = rng.uniform(0.2, 0.3)
        W = L * rng.uniform(0.58, 0.7)
        n = 8
        xs = np.linspace(0, L, n)
        w = 0.5 * W * np.sin(np.pi * np.clip(xs / L, 0, 1) ** 0.7) ** 1.1
    else:                                   # long willow/aspen-like
        L = rng.uniform(0.26, 0.36)
        W = L * rng.uniform(0.3, 0.38)
        n = 8
        xs = np.linspace(0, L, n)
        w = 0.5 * W * np.sin(np.pi * np.clip(xs / L, 0, 1) ** 0.9)
    w[0] = 0.01
    w[-1] = 0.0
    fold = rng.uniform(0.15, 0.5) * rng.choice([-1, 1])
    V = []
    for i in range(n):
        V.append((xs[i], 0.0, abs(w[i]) * fold * 0.6))
        V.append((xs[i], w[i], 0.0))
        V.append((xs[i], -w[i], 0.0))
    V = np.array(V, np.float64)
    curl = rng.uniform(-0.25, 0.45) * L
    V[:, 2] += curl * (V[:, 0] / L) ** 2 + rng.uniform(-0.6, 0.6) * V[:, 1] ** 2 / max(W, 1e-3)
    F = []
    for i in range(n - 1):
        m0, l0, r0 = 3 * i, 3 * i + 1, 3 * i + 2
        m1, l1, r1 = 3 * i + 3, 3 * i + 4, 3 * i + 5
        F.append((m0, m1, l1, l0))
        F.append((m0, r0, r1, m1))
    return V, np.array(F, np.int64), L


LEAF_PAL = [(112, 92, 72), (120, 98, 76), (104, 86, 68), (126, 106, 82), (98, 82, 66), (116, 100, 78),
            (108, 96, 76), (118, 94, 72), (96, 80, 64), (124, 110, 90)]
LEAF_GREEN = [(98, 100, 60), (90, 98, 58), (106, 104, 64)]
DUFF_PAL = [(88, 74, 60), (96, 80, 64), (82, 68, 56), (100, 86, 68), (92, 78, 62), (98, 82, 64)]


def duff_geom(rng, r):
    """Small flat irregular fragment of decayed litter (5-7 sided polygon, slightly tilted)."""
    k = rng.randint(5, 8)
    ang = np.sort(rng.uniform(0, TAU, k))
    rad = r * rng.uniform(0.55, 1.0, k)
    V = np.stack([np.cos(ang) * rad * rng.uniform(1.0, 1.6), np.sin(ang) * rad, np.zeros(k)], 1)
    V[:, 2] = V[:, 0] * rng.uniform(-0.15, 0.15) + V[:, 1] * rng.uniform(-0.15, 0.15)
    V = np.vstack([[0.0, 0.0, 0.004], V])
    F = np.array([(0, i + 1, (i + 1) % k + 1) for i in range(k)], np.int64)
    return V, F


def build_litter_tile(T, rng):
    h = periodic_height(T, 9, 0.03)
    objs = [ground_plane(T, (84, 70, 56), 0.95, h)]
    dens = tg.band_noise(rng, 64, 1, 3, beta=1.0)
    dens = (dens - dens.min()) / (dens.max() - dens.min())

    def density(x, y):
        return dens[int(y / T * 64) % 64, int(x / T * 64) % 64]
    acc = Acc()
    ico1, ico2 = ico(2), ico(3)
    # duff: small flat fragments of decayed litter cover most of the soil (discrete shapes, not grain)
    for _ in range(2600):
        x, y = rng.uniform(0, T), rng.uniform(0, T)
        r = rng.uniform(0.05, 0.11)
        V, F = duff_geom(rng, r)
        th = rng.uniform(0, TAU)
        Rz = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
        V = V @ Rz.T
        col = s2l(np.array(DUFF_PAL[rng.randint(len(DUFF_PAL))]) * rng.uniform(0.92, 1.08))
        z0 = rng.uniform(0.002, 0.01)
        for (dx, dy) in wrap_offsets(x, y, r * 1.6, T):
            acc.add(V + np.array([x + dx, y + dy, h(x + dx, y + dy) + z0]), F, col, 0.9, False)
    # moss cushions (under the litter)
    for _ in range(7):
        cx, cy = rng.uniform(0, T), rng.uniform(0, T)
        if density(cx, cy) > 0.6:
            continue
        for _ in range(rng.randint(36, 60)):
            a, d = rng.uniform(0, TAU), abs(rng.normal(0, 0.5))
            x, y = cx + math.cos(a) * d * 1.3, cy + math.sin(a) * d
            r = rng.uniform(0.07, 0.16)
            V, F = pebble_geom(rng, ico1, 0, 0, r, flat=(0.5, 0.75), sink=(-0.2, 0.0))
            col = s2l(np.array((72, 94, 44)) * rng.uniform(0.85, 1.2) + np.array((rng.uniform(-6, 10), 0, 0)))
            for (dx, dy) in wrap_offsets(x, y, r, T):
                acc.add(V + np.array([x + dx, y + dy, h(x + dx, y + dy)]), F, col, 0.95, True)
    # small stones
    for (x, y, r) in poisson_periodic(rng, T, [rng.uniform(0.07, 0.2) for _ in range(22)]):
        V, F = pebble_geom(rng, ico2, 0, 0, r)
        col = s2l(np.array(PEBBLE_PAL[rng.randint(len(PEBBLE_PAL))]) * 0.92)
        for (dx, dy) in wrap_offsets(x, y, r, T):
            acc.add(V + np.array([x + dx, y + dy, h(x + dx, y + dy)]), F, col, 0.75, True)
    # leaves: layered, patchy
    nleaf = 0
    z_layer = 0.012
    attempts = 0
    while nleaf < 2300 and attempts < 9000:
        attempts += 1
        x, y = rng.uniform(0, T), rng.uniform(0, T)
        if rng.uniform() > 0.3 + 0.9 * density(x, y):
            continue
        kind = rng.choice(["oak", "oak", "oak", "birch", "long"])
        V, F, L = leaf_geom(rng, kind)
        th = rng.uniform(0, TAU)
        Rz = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
        V = V @ Rz.T
        pal = LEAF_GREEN if rng.uniform() < 0.07 else LEAF_PAL
        col = np.array(pal[rng.randint(len(pal))], np.float64) * rng.uniform(0.94, 1.05)
        t = np.clip(np.linalg.norm(V[:, :2], axis=1) / L, 0, 1)       # 0 at the stalk, 1 at the tip
        cv = s2l(np.clip(col[None, :] * (0.92 + 0.12 * t[:, None]), 0, 255))
        z_layer += 0.00011
        for (dx, dy) in wrap_offsets(x, y, L, T):
            acc.add(V + np.array([x + dx, y + dy, h(x + dx, y + dy) + z_layer + rng.uniform(0, 0.012)]), F, cv,
                    rng.uniform(0.68, 0.82), False)
        nleaf += 1
    # twigs (hexagonal sticks with a side fork)
    for _ in range(20):
        x, y = rng.uniform(0, T), rng.uniform(0, T)
        L = rng.uniform(0.6, 1.7)
        r = rng.uniform(0.032, 0.06)
        th = rng.uniform(0, TAU)
        d = np.array([math.cos(th), math.sin(th), 0.0])
        pts = [np.zeros(3)]
        for k in range(3):
            th += rng.uniform(-0.35, 0.35)
            pts.append(pts[-1] + np.array([math.cos(th), math.sin(th), 0.0]) * L / 3)
        stick = twig_geom(pts, r)
        col = s2l(np.array((98, 82, 66)) * rng.uniform(0.9, 1.1))
        z0 = 0.05 + z_layer * rng.uniform(0.3, 1.0)
        for (dx, dy) in wrap_offsets(x, y, L, T):
            acc.add(stick[0] + np.array([x + dx, y + dy, h(x + dx, y + dy) + z0]), stick[1], col, 0.85, False)
        nb = pts[1] + (pts[2] - pts[1]) * 0.5
        a2 = th + rng.choice([-1, 1]) * 0.7
        side = twig_geom([nb, nb + np.array([math.cos(a2), math.sin(a2), 0.02]) * L * 0.35], r * 0.7)
        for (dx, dy) in wrap_offsets(x, y, L, T):
            acc.add(side[0] + np.array([x + dx, y + dy, h(x + dx, y + dy) + z0]), side[1], col, 0.85, False)
    # spruce cones
    for _ in range(9):
        x, y = rng.uniform(0, T), rng.uniform(0, T)
        V, F = cone_geom(rng)
        th = rng.uniform(0, TAU)
        Rz = np.array([[math.cos(th), -math.sin(th), 0], [math.sin(th), math.cos(th), 0], [0, 0, 1]])
        V = V @ Rz.T
        col = s2l(np.array((112, 78, 52)) * rng.uniform(0.9, 1.1))
        for (dx, dy) in wrap_offsets(x, y, 0.4, T):
            acc.add(V + np.array([x + dx, y + dy, h(x + dx, y + dy) + 0.06 + z_layer * 0.8]), F, col, 0.85, False)
    objs.append(acc.build("Litter"))
    log("  litter: %d leaves" % nleaf)
    return objs


def twig_geom(pts, r, sides=6):
    pts = [np.asarray(p, np.float64) for p in pts]
    V, F = [], []
    n = len(pts)
    for i, p in enumerate(pts):
        t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t) + 1e-9
        a = np.cross(t, [0, 0, 1.0])
        a /= np.linalg.norm(a) + 1e-9
        b = np.cross(t, a)
        rr = r * (1.0 - 0.45 * i / max(n - 1, 1))
        for j in range(sides):
            ang = TAU * j / sides
            V.append(p + (a * math.cos(ang) + b * math.sin(ang)) * rr + np.array([0, 0, rr]))
    for i in range(n - 1):
        for j in range(sides):
            k = (j + 1) % sides
            F.append((i * sides + j, i * sides + k, (i + 1) * sides + k, (i + 1) * sides + j))
    return np.array(V), np.array(F, np.int64)


def cone_geom(rng):
    """Small spruce cone: lathe with a zig-zag profile (scales), lying on its side."""
    L = rng.uniform(0.3, 0.42)
    R = L * 0.24
    rings = 7
    sides = 8
    V = []
    for i in range(rings + 1):
        t = i / rings
        rr = R * math.sin(math.pi * (0.12 + 0.8 * t)) * (1.15 if i % 2 else 0.85)
        for j in range(sides):
            a = TAU * j / sides + (0.3 if i % 2 else 0.0)
            V.append((t * L, rr * math.cos(a), rr * math.sin(a) + R))
    F = []
    for i in range(rings):
        for j in range(sides):
            k = (j + 1) % sides
            F.append((i * sides + j, i * sides + k, (i + 1) * sides + k, (i + 1) * sides + j))
    return np.array(V, np.float64), np.array(F, np.int64)


def ground_stage():
    for (name, T, builder, ao_dist, ao_floor, flatten, seed) in (
            ("PebblePath", 8.0, build_pebble_tile, 0.16, 0.32, 0.2, 101),
            ("ForestFloor", 10.0, build_litter_tile, 0.2, 0.34, 0.12, 202)):
        reset()
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        cycles_setup(scene, 16)
        c = scene.cycles
        c.max_bounces = 0
        c.diffuse_bounces = 0
        c.glossy_bounces = 0
        c.transmission_bounces = 0
        c.filter_width = 1.2
        r = scene.render
        r.resolution_x = r.resolution_y = 1024
        r.resolution_percentage = 100
        r.film_transparent = False
        r.image_settings.file_format = "OPEN_EXR"
        r.image_settings.color_depth = "32"
        r.image_settings.color_mode = "RGBA"
        try:
            scene.view_settings.view_transform = "Standard"
            scene.view_settings.look = "None"
        except TypeError:
            pass
        world = bpy.data.worlds.new("Black")
        scene.world = world
        try:
            world.color = (0, 0, 0)
        except AttributeError:
            pass
        rng = np.random.RandomState(seed)
        t = time.time()
        objs = builder(T, rng)
        mat, h = data_material(ao_dist)
        for o in objs:
            o.data.materials.append(mat)
        tg.ortho_camera(scene, 0.0, 0.0, T, T, z=8.0)
        log("ground %s: %d objects, %d verts (%.1fs)" % (name, len(objs), sum(len(o.data.vertices) for o in objs),
                                                         time.time() - t))
        maps = {}
        for which, spp in (("albedo", 24), ("normal", 24), ("rough", 8), ("ao", 256)):
            link_only(h["nt"], h["src"][which], h["em"].inputs["Color"])
            scene.cycles.samples = spp
            t = time.time()
            maps[which] = tg.render_exr(scene, os.path.join(WORK, "%s_%s.exr" % (name, which)))[..., :3].astype(
                np.float64)
            log("  render %s %s %.1fs" % (name, which, time.time() - t))
        alb = maps["albedo"]
        ao = np.clip(maps["ao"][..., 0], 0, 1)
        ao = tg.pblur(ao, 0.7)
        term = ao_floor + (1.0 - ao_floor) * np.clip(ao, 0, 1) ** 1.15
        macro = 1.0 + 0.06 * tg.band_noise(rng, 1024, 1, 3, beta=1.0)
        col = alb * (term * macro)[..., None]
        n = maps["normal"] * 2.0 - 1.0
        n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
        n = n * (1.0 - flatten) + np.array([0, 0, 1.0]) * flatten
        nrm = tg.encode_normal(n)
        rough = np.clip(maps["rough"][..., 0] + 0.04 * (1.0 - ao), 0, 1)
        base = os.path.join(TEX, "StyleA_%s_" % name)
        tg.write_png(base + "Color.png", tg.lin_to_srgb(col))
        tg.write_png(base + "Normal.png", nrm, quantize=False)
        tg.write_png(base + "Rough.png", rough)
        log("GROUND %s: mean sRGB %s, roughness %.2f, written %sColor/Normal/Rough.png" % (
            name, [int(v) for v in l2s255(col.reshape(-1, 3).mean(0))], rough.mean(), base))


# =============================================================================================== PREVIEW
LIGHTS = {"midday": dict(elev=58.0, bearing=-38.0, strength=0.075, exposure=-0.25),
          "afternoon": dict(elev=8.5, bearing=62.0, strength=0.075, exposure=0.95)}


def preview_setup(res=(1600, 900), samples=128):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    cycles_setup(scene, samples, denoise=True)
    c = scene.cycles
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.transmission_bounces = 4
    c.transparent_max_bounces = 8
    c.caustics_reflective = False
    c.caustics_refractive = False
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        log("WARNING AgX not available, view transform stays", scene.view_settings.view_transform)
    world = bpy.data.worlds.new("Sky")
    if world.node_tree is None:
        world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = True
    sky.altitude = 300.0
    try:
        sky.aerosol_density = 1.6
    except AttributeError:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    scene.world = world
    return scene


def set_light(scene, key):
    L = LIGHTS[key]
    nt = scene.world.node_tree
    sky = [n for n in nt.nodes if n.type == "TEX_SKY"][0]
    bg = [n for n in nt.nodes if n.type == "BACKGROUND"][0]
    sky.sun_elevation = math.radians(L["elev"])
    sky.sun_rotation = math.radians(L["bearing"])
    bg.inputs["Strength"].default_value = L["strength"]
    scene.view_settings.exposure = L["exposure"]


def camera(scene, loc, target, vfov=50.0, res=None):
    cam = bpy.data.objects.get("PrevCam")
    if cam is None:
        cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
        scene.collection.objects.link(cam)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(vfov)
    cam.data.clip_start = 0.05
    cam.data.clip_end = 2000
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    if res:
        scene.render.resolution_x, scene.render.resolution_y = res
    return cam


def render_to(scene, path):
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log("RENDER %s (%.0fs)" % (path, time.time() - t))
    return path


def path_mask(path_png, area, res=1024, seed=5):
    """Soft pebble-path mask over area (x0, y0, size) in scene coordinates."""
    x0, y0, size = area
    rng = np.random.RandomState(seed)
    ys, xs = (np.mgrid[0:res, 0:res] + 0.5) / res * size
    X, Y = xs + x0, ys + y0
    wob = tg.band_noise(rng, res, 4, 12, beta=1.0) * 0.32
    xc = 0.9 * np.sin((Y + 5.0) * 0.075) - 0.4
    hw = 2.05 + 0.25 * np.sin(Y * 0.45 + 1.0)
    d = np.abs(X - xc) - hw + wob
    m = 1.0 - tg.smoothstep(-0.35, 0.35, d)
    m *= tg.smoothstep(-6.4, -5.6, Y)                # starts at the porch steps
    near = np.hypot(X - 0.2, (Y + 5.4) * 1.3) - 3.6 + wob     # small apron in front of the steps
    m = np.maximum(m, (1.0 - tg.smoothstep(-0.35, 0.35, near)) * tg.smoothstep(-6.4, -5.6, Y))
    tg.write_png(path_png, m)


def ground_material(mask_png, area):
    m = new_material("PrevGround")
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    bsdf = N.get("Principled BSDF")
    tc = N.new("ShaderNodeTexCoord")

    def mapped(scale, off=(0, 0, 0)):
        mp = N.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = scale
        mp.inputs["Location"].default_value = off
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        return mp

    def tex(path, cs, vec, ext="REPEAT"):
        n = N.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path, check_existing=True)
        n.image.colorspace_settings.name = cs
        n.extension = ext
        n.interpolation = "Cubic"
        L.new(vec.outputs["Vector"], n.inputs["Vector"])
        return n
    mf = mapped((1 / 10.0, 1 / 10.0, 1))
    mpth = mapped((1 / 8.0, 1 / 8.0, 1))
    x0, y0, size = area
    mm = mapped((1 / size, 1 / size, 1), (-x0 / size, -y0 / size, 0))
    fc = tex(os.path.join(TEX, "StyleA_ForestFloor_Color.png"), "sRGB", mf)
    fn = tex(os.path.join(TEX, "StyleA_ForestFloor_Normal.png"), "Non-Color", mf)
    fr = tex(os.path.join(TEX, "StyleA_ForestFloor_Rough.png"), "Non-Color", mf)
    pc = tex(os.path.join(TEX, "StyleA_PebblePath_Color.png"), "sRGB", mpth)
    pn = tex(os.path.join(TEX, "StyleA_PebblePath_Normal.png"), "Non-Color", mpth)
    pr = tex(os.path.join(TEX, "StyleA_PebblePath_Rough.png"), "Non-Color", mpth)
    mk = tex(mask_png, "Non-Color", mm, ext="CLIP")

    def mix(a, b):
        mx = N.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        L.new(mk.outputs["Color"], mx.inputs[0])
        L.new(a.outputs["Color"], mx.inputs[6])
        L.new(b.outputs["Color"], mx.inputs[7])
        return mx.outputs[2]
    L.new(mix(fc, pc), bsdf.inputs["Base Color"])
    nm = N.new("ShaderNodeNormalMap")
    L.new(mix(fn, pn), nm.inputs["Color"])
    L.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    sep = N.new("ShaderNodeSeparateColor")
    L.new(mix(fr, pr), sep.inputs["Color"])
    L.new(sep.outputs["Red"], bsdf.inputs["Roughness"])
    return m


def figure(scene, loc, yaw=0.0):
    """Blocky 5.5-stud Roblox-style avatar (legs 2.3, torso 2.0, head 1.2)."""
    mb = bmesh.new()
    parts = [((-0.5, 0, 1.15), (0.95, 0.95, 2.3), (54, 58, 66)), ((0.5, 0, 1.15), (0.95, 0.95, 2.3), (54, 58, 66)),
             ((0, 0, 3.3), (2.0, 1.0, 2.0), (66, 92, 120)), ((-1.5, 0, 3.3), (0.95, 0.95, 2.0), (66, 92, 120)),
             ((1.5, 0, 3.3), (0.95, 0.95, 2.0), (66, 92, 120)), ((0, 0, 4.9), (1.15, 1.15, 1.2), (204, 162, 128))]
    objs = []
    for i, (c, s, col) in enumerate(parts):
        me = bpy.data.meshes.new("Fig%d" % i)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(s), verts=bm.verts)
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.06, segments=2, affect="EDGES")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("Fig%d" % i, me)
        scene.collection.objects.link(ob)
        m = new_material("FigMat%d" % i)
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*s2l(col), 1)
        b.inputs["Roughness"].default_value = 0.7
        me.materials.append(m)
        ob.location = Vector(loc) + Matrix.Rotation(yaw, 3, "Z") @ Vector(c)
        ob.rotation_euler = (0, 0, yaw)
        objs.append(ob)
    mb.free()
    return objs


def place(root, loc, rot=0.0, scale=1.0, dup=False, scene=None):
    if dup:
        new = root.copy()
        scene.collection.objects.link(new)
        for c in root.children:
            nc = c.copy()
            scene.collection.objects.link(nc)
            nc.parent = new
        root = new
    root.location = Vector(loc)
    root.rotation_euler = (0, 0, rot)
    root.scale = (scale, scale, scale)
    return root


def sheet(paths, cols, out_path):
    imgs = [tg.load_image_np(p, "sRGB")[..., :3] for p in paths]
    h, w = imgs[0].shape[:2]
    rows = (len(imgs) + cols - 1) // cols
    canvas = np.ones((rows * h + (rows - 1) * 6, cols * w + (cols - 1) * 6, 3)) * 0.12
    for i, im in enumerate(imgs):
        r, c = i // cols, i % cols
        y0 = (rows - 1 - r) * (h + 6)
        canvas[y0:y0 + h, c * (w + 6):c * (w + 6) + w] = im
    tg.write_png(out_path, np.clip(canvas, 0, 1), quantize=False)
    log("SHEET", out_path)


def preview_stage(views="all"):
    reset()
    scene = preview_setup()
    glb = os.path.join(OUT, GLB_NAME + ".glb")
    with open(os.path.join(OUT, GLB_NAME + ".manifest.json"), encoding="utf-8") as f:
        man = json.load(f)
    bpy.ops.import_scene.gltf(filepath=glb)
    roots = {e["name"]: bpy.data.objects[e["name"]] for e in man["assets"]}
    for o in scene.objects:
        o.select_set(False)
    cab = place(roots["StyleA_HunterCabin"], (0, -18, 0))
    spr = place(roots["StyleA_Spruce"], (-18.0, -24.0, 0), 0.4)
    oak = place(roots["StyleA_Oak"], (21.0, -6.0, 0), 0.7)
    bld = place(roots["StyleA_Boulder"], (-6.5, -1.5, 0), 0.5)
    rng = random.Random(4)
    for (x, y) in ((-31, -40), (-12, -47), (7, -52), (25, -44), (-42, -16), (36, -30), (-26, -64), (42, -58),
                   (-52, -42), (18, -72), (-6, -76), (54, -20), (-62, -10), (30, -90), (-40, -86)):
        place(roots["StyleA_Spruce"], (x + rng.uniform(-3, 3), y, 0), rng.uniform(0, TAU), rng.uniform(0.82, 1.15),
              dup=True, scene=scene)
    for (x, y) in ((-40, 4), (44, 2), (-22, -30), (34, -60)):
        place(roots["StyleA_Oak"], (x, y, 0), rng.uniform(0, TAU), rng.uniform(0.85, 1.05), dup=True, scene=scene)
    place(roots["StyleA_Boulder"], (11.0, 7.0, 0), 2.0, 0.55, dup=True, scene=scene)
    place(roots["StyleA_Boulder"], (-13.0, 9.0, -0.1), 4.1, 0.4, dup=True, scene=scene)
    place(roots["StyleA_Boulder"], (24.0, -16.0, 0), 1.0, 0.8, dup=True, scene=scene)
    area = (-64.0, -64.0, 128.0)
    mask_png = os.path.join(WORK, "path_mask.png")
    path_mask(mask_png, area)
    gme = bpy.data.meshes.new("PrevGround")
    s = 1500
    gme.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    gme.uv_layers.new(name="UVMap")
    gob = bpy.data.objects.new("PrevGround", gme)
    scene.collection.objects.link(gob)
    gme.materials.append(ground_material(mask_png, area))
    figure(scene, (2.4, 0.5, 0.0), yaw=math.radians(-25))
    bpy.context.view_layer.update()
    tag = os.environ.get("STYLEA_TAG", "")
    shots = {
        "set": ((7.0, 38.0, 5.0), (1.0, -16.0, 10.5), 55.0),
        "porch": ((4.0, -1.0, 5.0), (-0.6, -12.5, 5.4), 70.0),
        "oak": ((13.5, 3.0, 5.0), (21.0, -6.0, 9.5), 70.0),
        "boulder": ((-3.0, 5.0, 5.0), (-6.5, -1.5, 1.2), 70.0),
        "ground": ((1.6, 6.5, 5.0), (0.6, 1.2, 0.0), 70.0),
        "spruce": ((-11.5, -14.5, 5.0), (-18.0, -24.0, 15.0), 70.0),
        "side": ((16.0, -31.0, 5.0), (5.0, -18.0, 8.0), 70.0),
    }
    out = []
    for light in ("midday", "afternoon"):
        set_light(scene, light)
        camera(scene, *shots["set"][:2], vfov=shots["set"][2], res=(1600, 900))
        scene.cycles.samples = 160
        out.append(render_to(scene, os.path.join(PREV, "A_set_%s%s.png" % (light, tag))))
        tiles = []
        for k in ("porch", "oak", "boulder", "ground", "spruce", "side"):
            loc, tgt, fov = shots[k]
            camera(scene, loc, tgt, vfov=fov, res=(800, 450))
            scene.cycles.samples = 96
            tiles.append(render_to(scene, os.path.join(WORK, "close_%s_%s.png" % (light, k))))
        sp = os.path.join(PREV, "A_closeups_%s%s.png" % (light, tag))
        sheet(tiles, 3, sp)
        out.append(sp)
    # lineup at eye level, midday
    set_light(scene, "midday")
    for o in list(scene.objects):
        if o.parent is None and o.type == "EMPTY" and o not in roots.values():
            for c in o.children:
                c.hide_render = True
    place(cab, (300 + 22, 0, 0))
    place(spr, (300 - 26, 0, 0), 0.4)
    place(oak, (300 - 4, 0, 0), 0.7)
    place(bld, (300 + 42, 2, 0), 0.5)
    fig = figure(scene, (300 + 8.5, 9.0, 0), yaw=math.radians(-10))
    camera(scene, (300 + 6, 80, 5.0), (300 + 6, 0, 14.0), vfov=42.0, res=(1800, 760))
    scene.cycles.samples = 128
    out.append(render_to(scene, os.path.join(PREV, "A_lineup_midday%s.png" % tag)))
    # ground maps 2x2 tiled (seam check)
    tiles = []
    for name in ("PebblePath", "ForestFloor"):
        im = tg.load_image_np(os.path.join(TEX, "StyleA_%s_Color.png" % name), "sRGB")[..., :3]
        big = np.concatenate([np.concatenate([im, im], 1)] * 2, 0)
        tiles.append(big[::2, ::2])
    tg.write_png(os.path.join(PREV, "A_ground_maps%s.png" % tag), np.concatenate(tiles, 1), quantize=False)
    out.append(os.path.join(PREV, "A_ground_maps%s.png" % tag))
    for p in out:
        log("PREVIEW", p)
    return out


# =============================================================================================== main
def main():
    log("style_a.py OUT=%s PREV=%s stages=%s" % (OUT, PREV, sorted(STAGES)))
    if "ground" in STAGES:
        ground_stage()
    if "assets" in STAGES:
        assets_stage()
    if "preview" in STAGES:
        preview_stage()
    log("DONE")


if __name__ == "__main__":
    main()
