"""
ir_supplies.py - realistic drinks, food and medical items for the ItemsReal set (built by items_real.py).
Held-item convention (unchanged from v1): the hand grip point is at the origin, the item's natural up is +Z and
its front faces +Y. v1 attachments are kept: Grip on every item, Mouth on the bottles (same positions).
Sizes follow real objects (1 stud ~ 0.33 m) while staying readable in the hand: a 10 cm apple, 2-3 cm berries,
a 1.4 l glass bottle, a 15 x 22 cm ration tin, an 8 cm gauze roll, a 34 x 20 x 14 cm canvas medic bag.
"""
import math
import random

import numpy as np
from mathutils import Matrix, Vector

import ir_geo as g
import items_kit as kit
import tex_items_mats as M
from ir_geo import curve, lerp, smoothstep
from tex_items import C

V = Vector
D = math.radians
TAU = 2.0 * math.pi
SET = "IR_Supplies"
RNG = random.Random(9071)


def _grip(lib, root):
    lib.attach(root, "Grip", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))


# =============================================================================================== small builders
def leaf(name, length, width, thick=0.005, fold=0.18, curl=0.0, n=6, shape=None, tip=0.004):
    """Thin solid leaf pointing +Z (base at the origin), width along Y, upper surface facing +X: a V-folded midrib
    (fold = rise per stud of distance from the midrib) and a tip curl toward +X (negative droops).
    Vertex attribute a3 (set later by piece) marks the upper surface."""
    shape = shape or (lambda s: math.sin(math.pi * min(1.0, s ** 0.85)) ** 0.75)
    rings = []
    for k in range(n + 1):
        s = k / n
        hw = max(width * 0.5 * shape(s), tip * (0.5 if 0 < k < n else 0.25))
        h = thick * 0.5 * (1.0 - 0.5 * s)
        z = s * length
        rings.append([(0.0, -hw, z), (h, 0.0, z), (0.0, hw, z), (-h, 0.0, z)])     # edge, top, edge, underside
    ob = g.rings_mesh(name, rings, cap_start="flat", cap_end="flat")
    for v in ob.data.vertices:
        s = max(v.co.z, 0.0) / length
        v.co.x += fold * abs(v.co.y) + curl * s * s
    ob.data.update()
    return ob


def leaf_piece(ob, base, direction, across, mid, rnd=None, bevr=0.0015):
    """Orient a leaf() (local +Z -> direction, +Y -> across) and tag it in its own frame (exact midrib)."""
    d = V(direction).normalized()
    a = V(across)
    a = (a - d * a.dot(d)).normalized()
    up_side = a.cross(d)        # local +X after orient_to
    g.orient_to(ob, base, d, a)
    # a0..a2 = the leaf's upper-side direction: the material compares it with the baked normal per texel
    return g.piece(ob, mid, axis=tuple(d), origin=tuple(base), up=tuple(a), bevr=bevr, rnd=rnd, seed_offset=False,
                   a={"a0": up_side.x, "a1": up_side.y, "a2": up_side.z}, shade=35)


def stem(name, path, r0, r1=None, segs=5, n=10):
    pts = g.smooth_path(path, n) if len(path) > 2 else path
    r1 = r0 if r1 is None else r1
    return g.sweep(name, pts, kit.circle(segs, 1.0), lambda t: (lerp(r0, r1, t), lerp(r0, r1, t)))


def closed_ring_mesh(name, profile, segs, phase=0.0):
    """Revolved closed loop (r, z) around Z (a band / ring with thickness), UV'd."""
    rings = [g.ring((0, 0, z), r, r, segs, phase=phase) for (r, z) in profile]
    return g.rings_mesh(name, rings, cap_start=None, cap_end=None, close_v=True)


# =============================================================================================== bottles
ZB = -0.40   # bottle base (grip at mid body)


def _bottle_profile(open_mouth):
    zb = ZB
    p = [(0.0, zb + 0.032), (0.06, zb + 0.024), (0.12, zb + 0.006), (0.168, zb), (0.197, zb + 0.012),
         (0.208, zb + 0.04), (0.21, zb + 0.085), (0.21, zb + 0.3), (0.21, zb + 0.555), (0.205, zb + 0.615),
         (0.188, zb + 0.668), (0.156, zb + 0.718), (0.119, zb + 0.76), (0.093, zb + 0.793), (0.083, zb + 0.82),
         (0.08, zb + 0.857), (0.089, zb + 0.866), (0.092, zb + 0.879), (0.092, zb + 0.893), (0.086, zb + 0.9)]
    if open_mouth:
        p += [(0.07, zb + 0.902), (0.064, zb + 0.886), (0.062, zb + 0.84), (0.0, zb + 0.826)]
    else:
        p += [(0.0, zb + 0.9)]
    return p


def _glass_piece(ob):
    thick = lambda co: max(smoothstep(-0.34, -0.39, co.z), smoothstep(0.17, 0.32, co.z))
    return g.piece(ob, M.GLASS, axis=(0, 0, 1), bevr=0.004, a={"a0": thick, "a1": lambda co: co.y}, shade=60,
                   uvw=0.8)


def _cap(name, z0, segs=20):
    """Pressed tin screw cap with a knurled skirt (knurl in the normal map; a0 = 1 on the skirt)."""
    h = 0.155
    prof = [(0.0, z0 + h), (0.07, z0 + h), (0.088, z0 + h - 0.003), (0.099, z0 + h - 0.011), (0.102, z0 + h - 0.024),
            (0.102, z0 + 0.012), (0.098, z0 + 0.002), (0.09, z0), (0.0, z0 + 0.004)]
    return g.lathe(name, prof, segs=segs)


def _cap_piece(ob, z0, axis_m=None):
    """Tag a cap built around +Z from z0 (axis_m: rotation applied afterwards, so the knurl frame follows)."""
    skirt = lambda co: smoothstep(0.093, 0.1, math.hypot(co.x, co.y)) * smoothstep(z0 + 0.15, z0 + 0.135, co.z)
    # attributes in the cap's own frame first (a0 = skirt), then place it
    g.tx.tag(ob, M.TIN, a={"a0": skirt})
    a0 = np.empty(len(ob.data.vertices), dtype=np.float32)
    ob.data.attributes["a0"].data.foreach_get("value", a0)
    if axis_m is not None:
        g.xform(ob, axis_m)
    axis = (axis_m.to_3x3() @ V((0, 0, 1))) if axis_m is not None else V((0, 0, 1))
    origin = (axis_m @ V((0, 0, z0))) if axis_m is not None else V((0, 0, z0))
    g.piece(ob, M.TIN, axis=tuple(axis), origin=tuple(origin), bevr=0.003, rnd=0.0, seed_offset=False, shade=50)
    ob.data.attributes["a0"].data.foreach_set("value", a0)
    ob.data.update()
    return ob


def water_bottle(lib):
    root = lib.begin("water_bottle", "Drink", tags=["Drink"], held=True,
                     notes="Heavy old green-tinted bottle glass (seed bubbles, mould seams, smudges) holding water, "
                           "knurled tin screw cap, stitched leather sleeve. Grip = body centre at origin. Glass and "
                           "WaterFill use AlphaMode Transparency with MeshPart.Transparency 0.02 (alpha = opacity).")
    glass = g.lathe("wb_glass", _bottle_profile(False), segs=20)
    _glass_piece(glass)
    water = g.lathe("wb_water", [(0.0, ZB + 0.036), (0.15, ZB + 0.03), (0.182, ZB + 0.046), (0.19, ZB + 0.08),
                                 (0.19, 0.118), (0.0, 0.118)], segs=20)
    g.piece(water, M.WATER, bevr=0.003, shade=60, uvw=0.35)
    cap = _cap("wb_cap", 0.445)
    _cap_piece(cap, 0.445)
    sleeve = closed_ring_mesh("wb_sleeve", [(0.2105, -0.125), (0.219, -0.123), (0.2245, -0.112), (0.2245, 0.058),
                                            (0.219, 0.069), (0.2105, 0.071)], 20)
    g.piece(sleeve, M.LEATHER, axis=(0, 0, 1), bevr=0.004, a={"a1": lambda co: math.atan2(co.x, -co.y)}, shade=50)
    lib.part(root, [glass], "Glass", SET, alpha="Transparency", transparency=0.02, weight=1.0)
    lib.part(root, [water], "WaterFill", SET, alpha="Transparency", transparency=0.02, weight=0.6,
             cast_shadow=False)
    lib.part(root, [cap], "Tin", SET, weight=1.3)
    lib.part(root, [sleeve], "Leather", SET, weight=1.2)
    lib.params(root, M.GLASS, dict(color=C(116, 156, 124), opacity=0.1, smudge=0.55, dirt=0.45))
    lib.params(root, M.WATER, dict(color=C(64, 98, 94), opacity=0.3))
    lib.params(root, M.TIN, dict(knurl=56.0, rust=0.35, dents=0.4, rough=0.46))
    lib.params(root, M.LEATHER, dict(color=C(92, 60, 38), seam=True, seam_r=0.222, spi=34.0, crease=0.5, scuff=0.8,
                                     polish=0.5))
    _grip(lib, root)
    lib.attach(root, "Mouth", (0, 0, 0.6), look=(0, 0, 1))
    lib.finish(root)


def empty_bottle(lib):
    root = lib.begin("empty_bottle", "Drink", tags=["Drink", "Refillable"], held=True,
                     notes="The same bottle, empty and open; the tin cap hangs on a twine cord from a wire collar round "
                           "the neck. Grip = body centre at origin. Glass: AlphaMode Transparency, Transparency 0.02.")
    glass = g.lathe("eb_glass", _bottle_profile(True), segs=20)
    _glass_piece(glass)
    cap = _cap("eb_cap", 0.0)
    m = Matrix.Translation((0.335, 0.05, 0.05)) @ Matrix.Rotation(D(-14), 4, "Y") @ Matrix.Rotation(D(8), 4, "X")
    _cap_piece(cap, 0.0, m)
    collar = g.torus("eb_collar", 0.087, 0.0075, segs=18, minor_segs=6, center=(0, 0, ZB + 0.828))
    g.piece(collar, M.CORD, axis=(0, 0, 1), bevr=0.002, a={"a0": g.angle_attr(collar)}, shade=60)
    top = m @ V((0, 0, 0.155))
    cord = stem("eb_cord", [(0.093, 0.004, ZB + 0.826), (0.16, 0.02, ZB + 0.805), (0.23, 0.032, ZB + 0.75),
                            (0.28, 0.03, top.z + 0.07), (top.x - 0.002, top.y, top.z + 0.01)], 0.0068, segs=6, n=12)
    g.piece(cord, M.CORD, axis=(0, 0, 1), bevr=0.002, shade=60)
    lib.part(root, [glass], "Glass", SET, alpha="Transparency", transparency=0.02, weight=1.0)
    lib.part(root, [cap], "Tin", SET, weight=1.3)
    lib.part(root, [collar, cord], "Rope", SET, weight=1.2, cast_shadow=False)
    lib.params(root, M.GLASS, dict(color=C(120, 160, 128), opacity=0.1, smudge=0.7, dirt=0.6))
    lib.params(root, M.TIN, dict(knurl=56.0, rust=0.5, dents=0.6, rough=0.5))
    lib.params(root, M.CORD, dict(color=C(150, 128, 92), turns=70.0, strands=3, dirt=0.5))
    _grip(lib, root)
    lib.attach(root, "Mouth", (0, 0, ZB + 0.9), look=(0, 0, 1))
    lib.finish(root)


# =============================================================================================== food
def berry_mesh(name, r):
    """Berry around +Z: pedicel dimple at +Z, blossom end (calyx scar) at -Z."""
    prof = [(0.0, -0.92 * r), (0.42 * r, -0.86 * r), (0.78 * r, -0.6 * r), (0.97 * r, -0.2 * r), (0.98 * r, 0.22 * r),
            (0.8 * r, 0.62 * r), (0.36 * r, 0.9 * r), (0.0, 0.8 * r)]
    return g.lathe(name, prof, segs=10, r_fn=lambda a, z: 1.0 + 0.025 * math.cos(3 * a + r * 40))


def berries(lib):
    root = lib.begin("berries", "Food", tags=["Food"], held=True,
                     notes="Sprig of glossy wild berries (ripe dark red to a few lighter, 2.3-3.3 cm) on fine stalks from "
                           "a woody twig with three leaves. Grip = cluster centre at origin.")
    rng = random.Random(41)
    node = V((0.0, 0.0, 0.14))
    berries_o, stalks = [], []
    spots = []
    # two racemes hang from the twig node; berries on short pedicels alternate along each rachis
    for k, (dx, dy) in enumerate(((0.06, 0.035), (-0.055, -0.03))):
        rach = [node, node + V((dx * 0.5, dy * 0.5, -0.05)), node + V((dx, dy, -0.14)), node + V((dx * 1.2, dy * 1.1, -0.24))]
        rpath = g.smooth_path([tuple(q) for q in rach], 8)
        rs = stem("berry_rachis%d" % k, rpath, 0.0042, 0.003, segs=4, n=8)
        g.piece(rs, M.STEM, axis=(0, 0, -1), bevr=0.001, shade=60, uvw=0.7)
        stalks.append(rs)
        pts = [V(q) for q in rpath]
        for j in range(6):
            t = 0.18 + 0.8 * j / 5.0
            i0 = min(len(pts) - 2, int(t * (len(pts) - 1)))
            base = pts[i0].lerp(pts[i0 + 1], t * (len(pts) - 1) - i0)
            a = TAU * (j * 0.38 + k * 0.5) + rng.uniform(-0.3, 0.3)
            out = V((math.cos(a), math.sin(a), -0.35)).normalized()
            spots.append((base + out * 0.06, base))
    for i, (c, base) in enumerate(spots):
        r = rng.uniform(0.032, 0.045)
        b = berry_mesh("berry%d" % i, r)
        to_node = (base + V((0, 0, 0.03)) - c).normalized()
        g.orient_to(b, tuple(c), tuple(to_node), (rng.uniform(-1, 1), rng.uniform(-1, 1), 0.3))
        axis = to_node
        scar = lambda co, c=c, axis=axis, r=r: smoothstep(-0.6, -0.86, (V(co) - c).dot(axis) / r)
        g.piece(b, M.BERRY, axis=tuple(axis), origin=tuple(c), bevr=0.004, rnd=rng.random(), a={"a0": scar}, shade=80)
        berries_o.append(b)
        top = c + axis * (r * 0.8)
        mid = (top + base) * 0.5 + V((0, 0, 0.012))
        s = stem("berry_stalk%d" % i, [tuple(top), tuple(mid), tuple(base)], 0.0026, 0.0022, segs=4, n=4)
        g.piece(s, M.STEM, axis=tuple((base - top).normalized()), bevr=0.001, shade=60, uvw=0.6)
        stalks.append(s)
    twig = stem("berry_twig", [(0.0, 0.0, 0.1), (0.0, 0.0, 0.16), (0.02, -0.01, 0.26), (0.055, -0.03, 0.34),
                               (0.09, -0.04, 0.4)], 0.0115, 0.006, segs=6, n=10)
    g.piece(twig, M.STEM, axis=(0, 0, 1), bevr=0.002, shade=60)
    leaves = []
    for i, (base, d, acr, ln, wd) in enumerate((
            ((0.02, -0.01, 0.26), (-0.75, 0.25, 0.62), (0.3, 1.0, 0.0), 0.2, 0.085),
            ((0.055, -0.03, 0.34), (0.8, 0.35, 0.5), (-0.4, 1.0, 0.0), 0.18, 0.08),
            ((0.09, -0.04, 0.4), (0.35, -0.2, 0.92), (1.0, 0.3, 0.0), 0.15, 0.065))):
        lf = leaf("berry_leaf%d" % i, ln, wd, thick=0.0045, fold=0.22, curl=-0.025, n=6)
        leaf_piece(lf, base, d, acr, M.LEAF, rnd=0.3 + 0.2 * i)
        leaves.append(lf)
    lib.part(root, berries_o, "Berry", SET, weight=1.3)
    lib.part(root, [twig] + stalks, "Wood", SET, weight=1.0)
    lib.part(root, leaves, "Leaves", SET, weight=1.1, cast_shadow=False)
    lib.params(root, M.BERRY, dict(color=C(118, 14, 30), dark=C(56, 6, 24), dark_frac=0.7, rough=0.22))
    lib.params(root, M.STEM, dict(color=C(92, 64, 44), dark=C(58, 40, 28)))
    lib.params(root, M.LEAF, dict(color=C(58, 86, 40), under=C(112, 134, 82), length=0.2, veins=30.0, rough=0.45,
                                  dry=0.25, side_attr=True))
    _grip(lib, root)
    lib.finish(root)


def apple(lib):
    root = lib.begin("apple", "Food", tags=["Food"], held=True,
                     notes="10 cm red apple: streaky blush over yellow-green ground colour, lenticel specks, waxy bloom, "
                           "russet stem cavity, calyx basin, woody stem and one leaf. Grip = apple centre at origin.")
    R = 0.16
    prof = [(0.0, -0.68), (0.12, -0.74), (0.3, -0.8), (0.52, -0.77), (0.74, -0.62), (0.9, -0.37), (0.99, -0.06),
            (0.985, 0.25), (0.89, 0.52), (0.71, 0.74), (0.49, 0.84), (0.29, 0.8), (0.15, 0.67), (0.06, 0.6),
            (0.0, 0.58)]
    prof = [(r * R, z * R) for (r, z) in prof]
    rng = random.Random(5)
    body = g.lathe("apple_body", prof, segs=24,
                   r_fn=lambda a, z: (1.0 + 0.04 * math.cos(5 * a + 0.4) * smoothstep(0.02, -0.12, z)
                                      + 0.018 * math.cos(a - 0.9) * smoothstep(-0.1, 0.1, z)))
    g.noise_displace(body, 0.0014, 0.1, seed=21)
    g.piece(body, M.APPLE, axis=(0, 0, 1), bevr=0.01, shade=70)
    stm = stem("apple_stem", [(0.0, 0.0, 0.09), (0.003, 0.0, 0.13), (0.012, 0.004, 0.16), (0.026, 0.008, 0.178)],
               0.0072, 0.0052, segs=6, n=8)
    g.piece(stm, M.STEM, axis=(0, 0, 1), bevr=0.0015, shade=60)
    lf = leaf("apple_leaf", 0.125, 0.056, thick=0.0045, fold=0.2, curl=0.02, n=6)
    leaf_piece(lf, (0.008, 0.0, 0.15), (0.85, 0.3, 0.42), (-0.3, 1.0, 0.1), M.LEAF, rnd=0.5)
    lib.part(root, [body], "Food", SET, weight=1.25)
    lib.part(root, [stm], "Wood", SET, weight=1.0)
    lib.part(root, [lf], "Leaves", SET, weight=1.0, cast_shadow=False)
    lib.params(root, M.APPLE, dict(sun=0.9, red_base=0.45))
    lib.params(root, M.STEM, dict(color=C(96, 70, 46), dark=C(60, 44, 30)))
    lib.params(root, M.LEAF, dict(color=C(52, 78, 34), under=C(108, 128, 80), length=0.125, veins=34.0, rough=0.5,
                                  dry=0.3, side_attr=True))
    _grip(lib, root)
    lib.finish(root)


def dried_meat(lib):
    root = lib.begin("dried_meat", "Food", tags=["Food"], held=True,
                     notes="Smoke-cured shank of meat on the bone: dark crusted outside with pale fat seams and cracked "
                           "pepper, a cut top face showing lean and marbling, two turns of twine; the hock bone sticks "
                           "out below and is the grip (origin).")
    zm = 0.1
    top = 0.655
    prof = [(0.036, zm), (0.058, zm + 0.03), (0.092, zm + 0.08), (0.13, zm + 0.16), (0.163, zm + 0.26),
            (0.181, zm + 0.36), (0.18, zm + 0.45), (0.166, top - 0.05), (0.15, top - 0.012), (0.146, top - 0.003)]
    meat = g.lathe("meat_body", prof + [(0.0, top)], segs=16,
                   r_fn=lambda a, z: 1.0 + 0.06 * math.cos(3 * a + 1.0) * smoothstep(zm, zm + 0.3, z)
                   + 0.035 * math.cos(5 * a + 2.0) * smoothstep(zm + 0.2, zm + 0.45, z))
    for v in meat.data.vertices:
        v.co.y *= 0.76
        v.co.x += 0.03 * math.sin((v.co.z - zm) * 3.2)          # a slight bend, not a turned drumstick
    g.noise_displace(meat, 0.02, 0.085, seed=13, fn=lambda co: smoothstep(top - 0.01, top - 0.06, co.z))
    cut = lambda co: 1.0 if co.z > top - 0.0045 else 0.0
    g.piece(meat, M.MEAT, axis=(0, 0, 1), bevr=0.012, a={"a0": cut}, shade=65)
    # hock bone, sawn straight across (marrow shows on the cut), slightly flared toward the joint
    bone = g.lathe("meat_bone", [(0.0, -0.19), (0.036, -0.19), (0.038, -0.186), (0.036, -0.16), (0.031, -0.1),
                                 (0.03, -0.02), (0.034, 0.06), (0.04, 0.12), (0.0, 0.13)], segs=12,
                   r_fn=lambda a, z: 1.0 + 0.12 * math.cos(2 * a + 0.5) * smoothstep(0.0, 0.12, z))
    g.noise_displace(bone, 0.0015, 0.05, seed=17)
    sawn = lambda co: 1.0 if co.z < -0.1885 else 0.0
    g.piece(bone, M.BONE, axis=(0, 0, 1), bevr=0.004, a={"a0": sawn}, rnd=0.0, seed_offset=False, shade=60)
    twine = []
    for i, (z, r) in enumerate(((zm + 0.2, 0.146), (zm + 0.40, 0.176))):
        t = g.torus("meat_twine%d" % i, r, 0.0062, segs=24, minor_segs=5, center=(0, 0, z), sx=1.0, sy=0.76)
        for v in t.data.vertices:
            a = math.atan2(v.co.y / 0.76, v.co.x)
            v.co.z += 0.008 * math.cos(3 * a + 1.0 + i)
            v.co.x += 0.03 * math.sin((v.co.z - zm) * 3.2)
        t.data.update()
        g.piece(t, M.CORD, axis=(0, 0, 1), bevr=0.002, a={"a0": g.angle_attr(t)}, shade=60)
        twine.append(t)
    kx = 0.03 * math.sin(0.40 * 3.2)
    knot = g.lathe("meat_knot", [(0.0, -0.012), (0.011, -0.008), (0.013, 0.0), (0.011, 0.008), (0.0, 0.012)], segs=8)
    g.place(knot, loc=(kx, 0.176 * 0.76 + 0.004, zm + 0.40), rot=(0.5, 0.3, 0.0))
    g.piece(knot, M.CORD, axis=(0, 0, 1), bevr=0.002, shade=60)
    lib.part(root, [meat], "Food", SET, weight=1.2)
    lib.part(root, [bone], "Plaster", SET, weight=1.1)
    lib.part(root, twine + [knot], "Rope", SET, weight=1.2, cast_shadow=False)
    lib.params(root, M.CORD, dict(color=C(150, 126, 90), turns=80.0, strands=2, dirt=0.7, grime=0.7))
    lib.params(root, M.MEAT, dict(light=C(88, 36, 22), dark=C(40, 16, 10), fat=C(172, 140, 92)))
    lib.params(root, M.BONE, dict(color=C(196, 178, 142), bone_r=0.036))
    _grip(lib, root)
    lib.finish(root)


def ration(lib):
    root = lib.begin("ration", "Food", tags=["Food"], held=True,
                     notes="Tinplate ration tin with rolled double-seam rims, beading, a pull ring on the lid, rust at the "
                           "seams; aged olive paper label (cream band, unreadable small print, rust-red rules). "
                           "Grip = tin centre at origin.")
    prof = [(0.0, -0.318), (0.165, -0.318), (0.19, -0.322), (0.207, -0.331), (0.226, -0.333), (0.241, -0.327),
            (0.245, -0.314), (0.243, -0.298), (0.236, -0.288), (0.236, -0.262), (0.231, -0.254), (0.236, -0.246),
            (0.236, -0.224), (0.236, 0.224), (0.236, 0.246), (0.231, 0.254), (0.236, 0.262), (0.236, 0.288),
            (0.243, 0.298), (0.245, 0.314), (0.241, 0.327), (0.226, 0.333), (0.207, 0.331), (0.19, 0.318),
            (0.165, 0.314), (0.12, 0.317), (0.105, 0.314), (0.0, 0.315)]
    can = g.lathe("ration_can", prof, segs=22)
    g.piece(can, M.TIN, axis=(0, 0, 1), bevr=0.003, shade=40)
    tab = g.cbox("ration_tab", (0.07, 0.05, 0.008), 0.003, loc=(0.035, 0.0, 0.32))
    g.piece(tab, M.TIN, bevr=0.002, shade=40)
    ring = g.torus("ration_ring", 0.046, 0.0075, segs=16, minor_segs=6, center=(0.1, 0.0, 0.322), sx=1.0, sy=0.9)
    g.piece(ring, M.TIN, bevr=0.002, shade=60)
    label = closed_ring_mesh("ration_label", [(0.2363, -0.205), (0.2385, -0.205), (0.2385, 0.205), (0.2363, 0.205)], 22)
    g.piece(label, M.PAPER, axis=(0, 0, 1), bevr=0.002, shade=40)
    lib.part(root, [can, tab, ring], "Tin", SET, weight=1.0)
    lib.part(root, [label], "Paper", SET, weight=1.15)
    lib.params(root, M.TIN, dict(rust=0.6, dents=0.8, rough=0.5, base=C(150, 150, 144)))
    lib.params(root, M.PAPER, dict(label=True, half=0.205, ground=C(84, 90, 54), front=math.pi / 2))
    _grip(lib, root)
    lib.finish(root)


def bandage(lib):
    root = lib.begin("bandage", "Medical", tags=["Medical", "Heal"], held=True,
                     notes="Roll of open-weave cotton gauze (axis X, wound layers on the dished ends) with the loose end "
                           "hanging and two toothed steel clips. Grip = roll centre at origin.")
    # 10.5 cm wide roll, 5.7 cm across (a real gauze roll, not a paper-towel log)
    prof = [(0.0, -0.152), (0.04, -0.155), (0.07, -0.16), (0.081, -0.157), (0.085, -0.146), (0.0855, -0.07),
            (0.086, 0.0), (0.0855, 0.07), (0.085, 0.146), (0.081, 0.157), (0.07, 0.16), (0.04, 0.155), (0.0, 0.152)]
    roll = g.lathe("bandage_roll", prof, segs=20)
    g.place(roll, rot=(0, D(90), 0))
    g.noise_displace(roll, 0.0018, 0.05, seed=29)
    ends = lambda co: smoothstep(0.079, 0.073, math.hypot(co.y, co.z)) * smoothstep(0.143, 0.152, abs(co.x))
    g.piece(roll, M.GAUZE, axis=(1, 0, 0), bevr=0.006, a={"a0": ends}, shade=50)
    path = [(0, 0.0, -0.0838), (0, 0.05, -0.0858), (0, 0.098, -0.1), (0, 0.136, -0.135), (0, 0.16, -0.19),
            (0, 0.171, -0.26), (0, 0.176, -0.33)]
    tail = g.sweep("bandage_tail", g.smooth_path(path, 14), kit.rrect(0.29, 0.0045, 0.002),
                   lambda t: (1.0 - 0.04 * t, 1.0), up=(1, 0, 0))
    frng = random.Random(77)
    for v in tail.data.vertices:          # frayed, slightly uneven cut end
        if v.co.z < -0.33:
            v.co.z += frng.uniform(-0.006, 0.004)
    for v in tail.data.vertices:          # gentle ripple of the whole sheet (never thins it)
        v.co.y += 0.004 * math.sin(v.co.x * 23.0 + v.co.z * 9.0) * smoothstep(-0.12, -0.2, v.co.z)
    tail.data.update()
    g.piece(tail, M.GAUZE, axis=(0, 0, -1), bevr=0.002, shade=50)
    clips = []
    for i, sgn in enumerate((-1, 1)):
        z = -0.3 - 0.02 * i
        cp = [(sgn * 0.104, 0.1665, z), (sgn * 0.141, 0.1665, z), (sgn * 0.15, 0.1725, z), (sgn * 0.141, 0.1785, z),
              (sgn * 0.104, 0.1785, z)]
        c = g.sweep("bandage_clip%d" % i, cp, kit.rrect(0.034, 0.0028, 0.001), up=(0, 0, 1))
        g.piece(c, M.TIN, axis=(1, 0, 0), bevr=0.001, shade=40)
        clips.append(c)
    lib.part(root, [roll, tail], "Bandage", SET, weight=1.15)
    lib.part(root, clips, "Metal", SET, weight=1.0, cast_shadow=False)
    lib.params(root, M.GAUZE, dict(color=C(224, 218, 202), threads=64.0, stains=0.45, roll=(0.0, 0.0), layer=0.012,
                                   cloth="gco", weave_contrast=0.0, mesh=48.0, gap_dark=0.24))
    lib.params(root, M.TIN, dict(rust=0.15, dents=0.2))
    _grip(lib, root)
    lib.finish(root)


def herbs(lib):
    root = lib.begin("herbs", "Medical", tags=["Medical", "Heal"], held=True,
                     notes="Bundle of fresh sage: seven square stems with soft grey-green, velvety, pebbled leaves in "
                           "opposite pairs, tied with two turns of twine. Grip = the tie at origin.")
    rng = random.Random(7)
    stems, leaves = [], []
    for k in range(6):
        ang = TAU * k / 6 + rng.uniform(-0.25, 0.25)
        out = V((math.cos(ang), math.sin(ang) * 0.85, 0.0))
        h = 0.42 + rng.uniform(-0.06, 0.06)
        spread = 0.12 + rng.uniform(-0.03, 0.04)
        top = V((out.x * spread, out.y * spread, h))
        bend = V((-out.y, out.x, 0.0)) * rng.uniform(-0.03, 0.03)
        path = [(-out.x * 0.016, -out.y * 0.016, -0.2 + rng.uniform(-0.02, 0.02)), (out.x * 0.007, out.y * 0.007, 0.0),
                tuple(V((out.x * spread * 0.35, out.y * spread * 0.35, h * 0.45)) + bend), tuple(top + bend * 1.5)]
        sp = g.smooth_path(path, 7)
        st = g.sweep("herb_stem%d" % k, sp, [(0.004, 0.0), (0.0, 0.004), (-0.004, 0.0), (0.0, -0.004)],
                     lambda t: (lerp(1.0, 0.55, t), lerp(1.0, 0.55, t)))
        g.piece(st, M.STEM, axis=(0, 0, 1), bevr=0.0015, shade=35)
        stems.append(st)
        # opposite leaf pairs along the upper stem (rotated 90 degrees per node), a small pair at the tip
        pts = [V(p) for p in sp]
        for j, (t, ln) in enumerate(((0.5, 0.13), (0.72, 0.12), (0.93, 0.085))):
            i0 = min(len(pts) - 2, int(t * (len(pts) - 1)))
            base = pts[i0]
            sd = (pts[i0 + 1] - pts[i0]).normalized()
            side = sd.cross(V((0, 0, 1)))
            if side.length < 1e-4:
                side = V((1, 0, 0))
            side.normalize()
            if j % 2:
                side = sd.cross(side).normalized()
            for sgn in ((1, -1) if j < 2 else (1,)):
                d = (sd * 0.75 + side * (0.85 * sgn)).normalized()
                acr = sd.cross(d)
                if acr.length < 1e-4:
                    acr = V((0, 1, 0))
                lf = leaf("herb_leaf%d_%d_%d" % (k, j, sgn + 1), ln * rng.uniform(0.88, 1.08), 0.05, thick=0.0045,
                          fold=0.32, curl=-0.035 if j < 2 else 0.02, n=6,
                          shape=lambda s: math.sin(math.pi * min(1.0, s ** 0.75)) ** 0.7)
                leaf_piece(lf, tuple(base + d * 0.004), tuple(d), tuple(acr), M.LEAF, rnd=rng.random())
                leaves.append(lf)
    tie = g.ribbed_grip("herb_tie", -0.022, 0.022, 0.019, 0.018, segs=10, ribs=5, depth=0.0012, rows_per_rib=2, tilt=0.3)
    g.piece(tie, M.CORD, axis=(0, 0, 1), bevr=0.002, a={"a0": g.angle_attr(tie)}, shade=60)
    ends = [stem("herb_tie_end%d" % i, [(0.012 * sx, 0.016, 0.0), (0.026 * sx, 0.032, -0.03), (0.034 * sx, 0.038, -0.08)],
                 0.0032, 0.0028, segs=5, n=5) for i, sx in enumerate((-1, 1))]
    for e in ends:
        g.piece(e, M.CORD, axis=(0, 0, -1), bevr=0.0015, shade=60)
    lib.part(root, leaves, "Fern", SET, weight=1.0)
    lib.part(root, stems, "Fern", SET, name="herbs_Fern_2", weight=0.8)
    lib.part(root, [tie] + ends, "Rope", SET, weight=1.1, cast_shadow=False)
    lib.params(root, M.LEAF, dict(color=C(84, 102, 70), under=C(132, 144, 116), length=0.13, veins=26.0, rough=0.8,
                                  dry=0.25, fuzz=1.0, side_attr=True))
    lib.params(root, M.STEM, dict(color=C(96, 104, 70), dark=C(70, 74, 50)))
    lib.params(root, M.CORD, dict(color=C(138, 116, 82), turns=90.0, strands=2, dirt=0.6))
    _grip(lib, root)
    lib.finish(root)


def medkit(lib):
    root = lib.begin("medkit", "Medical", tags=["Medical", "Heal"], held=True,
                     notes="Rust-red waxed-canvas medic bag (white cross patch sewn on the front - not the protected "
                           "red-on-white emblem), flap with two leather straps and brass buckles, riveted leather carry "
                           "handle. Grip = the carry handle at origin; the bag hangs below.")
    W, Dp, H = 1.02, 0.42, 0.6
    grip_z = H + 0.155
    off = V((0, 0, -grip_z))
    belly = lambda z: 1.0 + 0.06 * smoothstep(0.0, 0.3, z) * smoothstep(H, H - 0.2, z)
    front = lambda z, lift: Dp / 2 * belly(z) + 0.004 + lift
    body = g.box("medkit_body", (W, Dp, H), loc=(0, 0, H / 2))
    import ls_common as ls
    ls.bevel(body, width=0.085, segments=3, angle_deg=40)
    g.noise_displace(body, 0.005, 0.16, seed=41)
    for v in body.data.vertices:          # soft bag: the front and back belly out a little
        v.co.y *= belly(v.co.z)
    body.data.update()
    bottom = lambda c, n: 0.3 if n.z < -0.7 else 1.0
    g.piece(body, M.CANVAS, axis=(1, 0, 0), bevr=0.012, uvw=bottom, shade=40)
    flap = g.sweep("medkit_flap", g.smooth_path([(0, -0.19, H + 0.006), (0, 0.0, H + 0.012), (0, 0.17, H + 0.01),
                                                 (0, front(H - 0.045, 0.012), H - 0.045),
                                                 (0, front(H - 0.215, 0.006), H - 0.215)], 10),
                   kit.rrect(W - 0.03, 0.01, 0.004), up=(1, 0, 0))
    g.piece(flap, M.CANVAS, axis=(0, 0, 1), bevr=0.005, shade=40)
    cross_pts = [(0.04, 0.125), (-0.04, 0.125), (-0.04, 0.04), (-0.125, 0.04), (-0.125, -0.04), (-0.04, -0.04),
                 (-0.04, -0.125), (0.04, -0.125), (0.04, -0.04), (0.125, -0.04), (0.125, 0.04), (0.04, 0.04)]
    cross = ls.extrude_profile("medkit_cross", cross_pts, 0.006, loc=(0, front(0.2, 0.003), 0.2))
    g.piece(cross, M.LINEN, axis=(1, 0, 0), bevr=0.003, a={"a3": 1.0}, shade=40)
    leather = []
    for i, sx in enumerate((-0.3, 0.3)):
        st = g.sweep("medkit_strap%d" % i, g.smooth_path([(sx, -0.13, H + 0.026), (sx, 0.12, H + 0.03),
                                                          (sx, front(H - 0.05, 0.029), H - 0.05),
                                                          (sx, front(H - 0.215, 0.022), H - 0.215),
                                                          (sx, front(H - 0.27, 0.016), H - 0.27)], 8),
                     kit.rrect(0.08, 0.009, 0.003), up=(1, 0, 0))
        tab = g.sweep("medkit_tab%d" % i, [(sx, front(0.2, 0.0045), 0.2), (sx, front(0.29, 0.0045), 0.29),
                                           (sx, front(0.33, 0.006), 0.33)], kit.rrect(0.08, 0.009, 0.003),
                      up=(1, 0, 0))
        leather += [st, tab]
    arc = [(0.19 * math.cos(a), 0.0, H + 0.02 + 0.145 * math.sin(a)) for a in
           [math.pi * (1.0 - k / 10.0) for k in range(11)]]
    handle = g.sweep("medkit_handle", arc, kit.rrect(0.07, 0.024, 0.008), up=(0, 1, 0))
    leather.append(handle)
    for o in leather:
        g.piece(o, M.LEATHER, axis=(0, 0, 1), bevr=0.004, shade=40)
    brass = []
    for i, sx in enumerate((-0.3, 0.3)):
        fr = kit.rect_frame("medkit_buckle%d" % i, (0.112, 0.085), (0.088, 0.061), -0.005, 0.005)
        yb = front(0.31, 0.018)
        g.place(fr, loc=(sx, yb, 0.31), rot=(D(90), 0, 0))
        bar = g.cyl("medkit_bar%d" % i, 0.0055, -0.056, 0.056, segs=6, loc=(sx, yb + 0.004, 0.31),
                    rot=(0, D(90), 0))
        g.piece(fr, M.BRASS, bevr=0.002, shade=40)
        g.piece(bar, M.BRASS, bevr=0.002, shade=50)
        brass += [fr, bar]
    for sx in (-0.19, 0.19):
        rv = g.cyl("medkit_rivet", 0.011, -0.012, 0.012, segs=8, loc=(sx, 0.0, H + 0.03), rot=(D(90), 0, 0))
        g.piece(rv, M.BRASS, bevr=0.002, shade=50)
        brass.append(rv)
    for o in [body, flap, cross] + leather + brass:
        g.xform(o, Matrix.Translation(off))
    lib.part(root, [body, flap, cross], "Canvas", SET, weight=0.95)
    lib.part(root, leather, "DarkLeather", SET, weight=1.0)
    lib.part(root, brass, "Brass", SET, weight=1.0, cast_shadow=False)
    lib.params(root, M.CANVAS, dict(color=C(120, 46, 34), threads=60.0, cloth="tri", stains=0.55, edge_wear=0.8,
                                    wrinkles=0.8, wrinkle_f=6.0, sun_fade=0.3))
    lib.params(root, M.LINEN, dict(color=C(204, 196, 174), threads=70.0, cloth="tri", stains=0.65, puff=0.0))
    lib.params(root, M.LEATHER, dict(color=C(78, 50, 34), crease=0.6, scuff=0.9, polish=0.5))
    lib.params(root, M.BRASS, dict(tarnish=0.8, verdigris=0.3))
    _grip(lib, root)
    lib.finish(root)


BUILDERS = [water_bottle, empty_bottle, berries, apple, dried_meat, ration, bandage, herbs, medkit]
