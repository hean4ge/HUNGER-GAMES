"""
items_consumables.py - drinks, food and medical items for the Items category (built by items.py).
Held-item convention: the hand grip point is at the origin (centre of what the hand closes around),
the item's natural up is +Z and its front faces +Y.
"""
import math
import random

from mathutils import Matrix, Vector

import ls_common as ls
import items_kit as kit
from items_kit import curve, lerp, smoothstep

D = math.radians
TAU = math.pi * 2.0


def orient(obj, origin, z_axis, normal_hint):
    """Rotate a +Z-pointing local shape so +Z follows z_axis and local Y (thickness) faces normal_hint."""
    zv = Vector(z_axis).normalized()
    yv = Vector(normal_hint)
    yv = (yv - zv * yv.dot(zv)).normalized()
    xv = yv.cross(zv)
    m = Matrix((xv, yv, zv)).transposed().to_4x4()
    obj.matrix_world = Matrix.Translation(Vector(origin)) @ m
    ls.refresh()
    return obj


def round_leaf(name, length, width, thick=0.016):
    """6-point rounded leaf (sage/mint) in the XZ plane, pointing +Z."""
    w = width
    return ls.extrude_profile(name, [(0.0, 0.0), (0.5 * w, 0.3 * length), (0.36 * w, 0.72 * length), (0.0, length),
                                     (-0.36 * w, 0.72 * length), (-0.5 * w, 0.3 * length)], thick)


ZB = -0.40   # bottle base (grip at mid body)


def _bottle_profile(open_mouth):
    zb = ZB
    p = [(0.0, zb + 0.025), (0.13, zb), (0.2, zb + 0.02), (0.21, zb + 0.07), (0.21, zb + 0.58),
         (0.19, zb + 0.67), (0.12, zb + 0.76), (0.082, zb + 0.8), (0.08, zb + 0.865), (0.089, zb + 0.875),
         (0.089, zb + 0.9)]
    if open_mouth:
        p += [(0.063, zb + 0.902), (0.06, zb + 0.84), (0.0, zb + 0.83)]
    else:
        p += [(0.0, zb + 0.9)]
    return p


def _cap(name, z0):
    return kit.revolve(name, [(0.096, z0), (0.104, z0 + 0.012), (0.104, z0 + 0.135), (0.092, z0 + 0.156),
                              (0.0, z0 + 0.16)], segs=12, r_fn=lambda a, z: 1.0 + 0.035 * math.cos(6 * a))


def _glass(lib, root, obj, rgb=None):
    obj = kit.part(lib, root, obj, "Glass", rgb=rgb, smooth=45)
    mat = obj.data.materials[0]
    mat.diffuse_color = (mat.diffuse_color[0], mat.diffuse_color[1], mat.diffuse_color[2], 0.38)  # preview only
    return obj


def water_bottle(lib):
    root = lib.begin_held("water_bottle", "Drink", tags=["Drink"],
                          notes="Glass bottle with water, knurled tin cap, leather sleeve. Grip = body centre at origin. "
                                "Glass needs Transparency (~0.45) in Roblox so the WaterFill reads.")
    _glass(lib, root, kit.revolve("wb_glass", _bottle_profile(False), segs=12))
    water = kit.revolve("wb_water", [(0.0, ZB + 0.04), (0.17, ZB + 0.035), (0.186, ZB + 0.07), (0.186, 0.09),
                                     (0.0, 0.09)], segs=10)
    kit.part(lib, root, water, "WaterFill", smooth=45)
    kit.part(lib, root, _cap("wb_cap", 0.44), "Tin", smooth=None)
    band = kit.revolve("wb_band", [(0.205, -0.11), (0.224, -0.1), (0.224, 0.05), (0.205, 0.06)], segs=12, closed=True)
    kit.part(lib, root, band, "Leather", smooth=50)
    kit.grip(lib, root)
    lib.attach(root, "Mouth", (0, 0, 0.6), look=(0, 0, 1))
    lib.finish(root)


def empty_bottle(lib):
    root = lib.begin_held("empty_bottle", "Drink", tags=["Drink", "Refillable"],
                          notes="Same bottle, empty and open; the cap hangs from a cord. Grip = body centre at origin.")
    _glass(lib, root, kit.revolve("eb_glass", _bottle_profile(True), segs=12), rgb=(178, 210, 204))
    cap = _cap("eb_cap", 0.0)
    kit.place(cap, loc=(0.335, 0.05, 0.13), rot=(D(8), D(-14), 0))
    kit.part(lib, root, cap, "Tin")
    collar = ls.torus("eb_collar", major=0.086, minor=0.014, major_segments=10, minor_segments=4)
    kit.place(collar, loc=(0, 0, ZB + 0.825))
    cord = kit.sweep("eb_cord", [(0.09, 0.0, ZB + 0.825), (0.18, 0.02, ZB + 0.8), (0.27, 0.04, ZB + 0.74),
                                 (0.315, 0.05, 0.3)], kit.circle(5, 0.012))
    kit.part(lib, root, kit.join([collar, cord], "eb_cords"), "Rope", smooth=55, shadow=False)
    kit.grip(lib, root)
    lib.attach(root, "Mouth", (0, 0, ZB + 0.9), look=(0, 0, 1))
    lib.finish(root)


def berries(lib):
    root = lib.begin_held("berries", "Food", tags=["Food"], notes="Wild berry cluster on a twig. Grip = cluster centre.")
    rng = random.Random(41)
    spots = [(D(20 + 90 * i), 0.115, -0.07) for i in range(4)] + [(D(60 + 180 * i), 0.068, 0.055) for i in range(2)]
    spots.append((0.3, 0.02, 0.15))
    light, dark = [], []
    for i, (a, r, z) in enumerate(spots):
        rad = rng.uniform(0.08, 0.092)
        b = ls.uvsphere("berry%d" % i, radius=rad, segments=7, rings=5,
                        loc=(r * math.cos(a) + rng.uniform(-0.01, 0.01), r * math.sin(a) + rng.uniform(-0.01, 0.01), z),
                        rot=(rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0, 3)))
        (dark if i in (1, 4) else light).append(b)
    kit.part(lib, root, kit.join(light, "berries_a"), "Berry", smooth=80)
    kit.part(lib, root, kit.join(dark, "berries_b"), "Berry", rgb=(116, 24, 46), smooth=80)
    twig = kit.sweep("berry_twig", [(0, 0, 0.17), (0.02, -0.01, 0.27), (0.06, -0.035, 0.34), (0.1, -0.04, 0.37)],
                     kit.circle(5, 0.014), lambda t: (1.0 - 0.4 * t, 1.0 - 0.4 * t))
    kit.part(lib, root, twig, "Wood", rgb=(92, 66, 44), smooth=50)
    l1 = orient(kit.leaf("berry_leaf1", 0.22, 0.11, 0.016), (0.03, -0.015, 0.29), (-0.55, 0.15, 0.8), (0.2, 1.0, 0.4))
    l2 = orient(kit.leaf("berry_leaf2", 0.19, 0.1, 0.016), (0.07, -0.035, 0.345), (0.75, 0.25, 0.55), (-0.3, 1.0, 0.5))
    kit.part(lib, root, kit.join([l1, l2], "berry_leaves"), "Leaves", smooth=None, shadow=False)
    kit.grip(lib, root)
    lib.finish(root)


def apple(lib):
    root = lib.begin_held("apple", "Food", tags=["Food"], notes="Red apple. Grip = apple centre at origin.")
    prof = [(0.0, -0.17), (0.05, -0.185), (0.12, -0.19), (0.17, -0.155), (0.205, -0.075), (0.215, 0.02),
            (0.205, 0.1), (0.17, 0.165), (0.1, 0.19), (0.045, 0.172), (0.0, 0.15)]
    body = kit.revolve("apple_body", prof, segs=12,
                       r_fn=lambda a, z: 1.0 + 0.04 * math.cos(5 * a) * smoothstep(-0.2, 0.17, z))
    ls.jitter(body, 0.004, random.Random(5))
    kit.part(lib, root, body, "Food", rgb=(168, 44, 36), smooth=70)
    stem = kit.sweep("apple_stem", [(0, 0, 0.13), (0.004, 0.0, 0.2), (0.02, 0.006, 0.255)], kit.circle(5, 0.013))
    kit.part(lib, root, stem, "Wood", rgb=(84, 60, 40), smooth=50)
    lf = orient(kit.leaf("apple_leaf", 0.17, 0.085, 0.016, tip_curl=0.02), (0.008, 0.0, 0.2), (0.8, 0.25, 0.45),
                (-0.4, 0.2, 1.0))
    kit.part(lib, root, lf, "Leaves", rgb=(88, 122, 52), shadow=False)
    kit.grip(lib, root)
    lib.finish(root)


def dried_meat(lib):
    root = lib.begin_held("dried_meat", "Food", tags=["Food"],
                          notes="Cured, twine-tied haunch of dried meat on the bone. Grip = the bone shank at origin; "
                                "bone uses the Plaster role (matte bone white).")
    zm = 0.15                       # meat starts here; the hand holds the bone below
    meat = kit.revolve("meat_body", [(0.036, zm), (0.062, zm + 0.02), (0.112, zm + 0.08), (0.162, zm + 0.17),
                                     (0.186, zm + 0.27), (0.18, zm + 0.37), (0.15, zm + 0.45), (0.09, zm + 0.5),
                                     (0.0, zm + 0.515)], segs=12,
                       r_fn=lambda a, z: 1.0 + 0.05 * math.cos(3 * a + 1.0) * smoothstep(zm, zm + 0.3, z))
    kit.place(meat, scale=(1.0, 0.84, 1.0))
    ls.jitter(meat, 0.007, random.Random(13))
    kit.part(lib, root, meat, "Food", rgb=(134, 58, 40), smooth=60)
    shank = kit.rod("meat_bone", 0.034, 0.36, 8, (0, 0, zm - 0.1))
    knobs = [ls.uvsphere("meat_knob%d" % i, radius=0.048, segments=7, rings=5, loc=(sx * 0.024, 0, zm - 0.28),
                         scale=(1.0, 0.85, 0.9)) for i, sx in enumerate((-1, 1))]
    kit.part(lib, root, kit.join([shank] + knobs, "meat_bone"), "Plaster", rgb=(224, 214, 190), smooth=60)
    rings = []
    for i, (z, r) in enumerate(((zm + 0.17, 0.168), (zm + 0.37, 0.186))):
        t = ls.torus("meat_twine%d" % i, major=r, minor=0.016, major_segments=10, minor_segments=4)
        kit.place(t, loc=(0, 0, z), scale=(1.0, 0.85, 1.0))
        rings.append(t)
    kit.part(lib, root, kit.join(rings, "meat_twine"), "Rope", smooth=55, shadow=False)
    kit.grip(lib, root)
    lib.finish(root)


def ration(lib):
    root = lib.begin_held("ration", "Food", tags=["Food"], notes="Ration tin with olive label and pull ring. Grip = tin centre.")
    prof = [(0.0, -0.33), (0.21, -0.33), (0.24, -0.315), (0.244, -0.295), (0.236, -0.28), (0.236, 0.28),
            (0.244, 0.295), (0.24, 0.315), (0.205, 0.325), (0.195, 0.312), (0.0, 0.312)]
    can = kit.revolve("ration_can", prof, segs=14)
    tab = kit.chamfer_box("ration_tab", (0.07, 0.05, 0.014), 0.005, loc=(0.035, 0.0, 0.318))
    ring = ls.torus("ration_ring", major=0.05, minor=0.011, major_segments=10, minor_segments=4)
    kit.place(ring, loc=(0.1, 0.0, 0.322))
    kit.part(lib, root, kit.join([can, tab, ring], "ration_tin"), "Tin", smooth=40)
    label = kit.revolve("ration_label", [(0.233, -0.2), (0.242, -0.2), (0.242, 0.2), (0.233, 0.2)], segs=14, closed=True)
    kit.part(lib, root, label, "Paper", rgb=(116, 122, 78), smooth=40)
    kit.grip(lib, root)
    lib.finish(root)


def bandage(lib):
    root = lib.begin_held("bandage", "Medical", tags=["Medical", "Heal"],
                          notes="Bandage roll (axis X) with a loose tail. Grip = roll centre at origin.")
    # tight gauze roll (no cardboard core, so it never reads as a paper roll), dished ends show the wind
    roll = kit.revolve("bandage_roll", [(0.0, -0.172), (0.05, -0.176), (0.098, -0.181), (0.118, -0.168),
                                        (0.122, 0.0), (0.118, 0.168), (0.098, 0.181), (0.05, 0.176), (0.0, 0.172)],
                       segs=14)
    kit.place(roll, rot=(0, D(90), 0))
    tail = kit.sweep("bandage_tail", [(0, 0.0, -0.112), (0, 0.08, -0.124), (0, 0.155, -0.15), (0, 0.215, -0.2),
                                      (0, 0.245, -0.27), (0, 0.252, -0.335)],
                     kit.rrect(0.33, 0.022, 0.008), lambda t: (1.0 - 0.05 * t, 1.0))
    kit.part(lib, root, kit.join([roll, tail], "bandage_cloth"), "Bandage", rgb=(234, 226, 206), smooth=40)
    clips = [kit.board("bandage_clip%d" % i, (0.1, 0.044, 0.05), 0.01, axis=0, loc=(sx * 0.08, 0.252, -0.3),
                       rot=(D(-6), 0, 0)) for i, sx in enumerate((-1, 1))]
    kit.part(lib, root, kit.join(clips, "bandage_clips"), "Metal", shadow=False)
    kit.grip(lib, root)
    lib.finish(root)


def herbs(lib):
    root = lib.begin_held("herbs", "Medical", tags=["Medical", "Heal"],
                          notes="Bundle of healing herbs tied with twine. Grip = the tie at origin.")
    rng = random.Random(7)
    groups = ([], [])
    for k in range(5):
        ang = TAU * k / 5 + rng.uniform(-0.25, 0.25)
        out = Vector((math.cos(ang), math.sin(ang) * 0.8, 0.0))
        h = 0.44 + rng.uniform(-0.05, 0.04)
        top = Vector((out.x * 0.15, out.y * 0.15, h))
        path = [(-out.x * 0.03, -out.y * 0.03, -0.22), (0, 0, 0.0), tuple(top)]
        objs = groups[k % 2]
        objs.append(kit.sweep("herb_stem%d" % k, path, kit.circle(4, 0.012)))
        stem_dir = top.normalized()
        side = stem_dir.cross(Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        for j, t in enumerate((0.55, 0.8, 0.98)):
            base = top * t
            sgn = 1 if (j + k) % 2 == 0 else -1
            d = (stem_dir + side * (1.0 * sgn) + out * 0.35) if j < 2 else stem_dir + out * 0.2
            nrm = stem_dir.cross(d) if j < 2 else side
            if nrm.length < 1e-4:
                nrm = side
            ln = 0.17 if j < 2 else 0.15
            objs.append(orient(round_leaf("herb_leaf%d_%d" % (k, j), ln, 0.095, 0.018), tuple(base), tuple(d),
                               tuple(nrm)))
    kit.part(lib, root, kit.join(groups[0], "herbs_a"), "Fern", smooth=None)
    kit.part(lib, root, kit.join(groups[1], "herbs_b"), "Fern", rgb=(112, 138, 76), smooth=None)
    tie = kit.wrap_grip("herb_tie", -0.05, 0.05, 0.05, 0.045, bands=2, bulge=0.006, segs=8, tilt_deg=8)
    kit.part(lib, root, tie, "Rope", smooth=55, shadow=False)
    kit.grip(lib, root)
    lib.finish(root)


def medkit(lib):
    root = lib.begin_held("medkit", "Medical", tags=["Medical", "Heal"],
                          notes="Canvas medic bag with a white cross, leather straps and carry handle. "
                                "Grip = the carry handle at origin; the bag hangs below.")
    W, Dp, H = 1.02, 0.42, 0.6
    body = ls.cube("medkit_body", size=(W, Dp, H), loc=(0, 0, H / 2))
    ls.bevel(body, width=0.07, segments=2, angle_deg=40)
    flap = kit.sweep("medkit_flap", [(0, -0.17, H + 0.012), (0, 0.17, H + 0.012), (0, Dp / 2 + 0.012, H - 0.05),
                                     (0, Dp / 2 + 0.014, H - 0.22)], kit.rrect(W + 0.02, 0.035, 0.012))
    cross_pts = [(0.04, 0.13), (-0.04, 0.13), (-0.04, 0.04), (-0.13, 0.04), (-0.13, -0.04), (-0.04, -0.04),
                 (-0.04, -0.13), (0.04, -0.13), (0.04, -0.04), (0.13, -0.04), (0.13, 0.04), (0.04, 0.04)]
    cross = ls.extrude_profile("medkit_cross", cross_pts, 0.03, loc=(0, Dp / 2 + 0.006, 0.225))
    grip_z = H + 0.155
    off = (0, 0, -grip_z)
    kit.part(lib, root, kit.shift(kit.join([body, flap], "medkit_bag"), off), "Canvas", rgb=(156, 58, 44), smooth=40)
    kit.part(lib, root, kit.shift(cross, off), "Bandage")
    straps = []
    for sx in (-0.3, 0.3):
        straps.append(kit.sweep("medkit_strap", [(sx, -0.12, H + 0.041), (sx, 0.17, H + 0.041),
                                                 (sx, Dp / 2 + 0.043, H - 0.05), (sx, Dp / 2 + 0.043, H - 0.27)],
                                kit.rrect(0.085, 0.022, 0.006)))
    arc = [(0.2 * math.cos(a), 0.0, H + 0.02 + 0.15 * math.sin(a)) for a in (math.pi, 0.75 * math.pi, 0.5 * math.pi,
                                                                              0.25 * math.pi, 0.0)]
    handle = kit.sweep("medkit_handle", arc, kit.rrect(0.075, 0.032, 0.01), up=(0, 1, 0))
    kit.part(lib, root, kit.shift(kit.join(straps + [handle], "medkit_leather"), off), "DarkLeather", smooth=40)
    buckles = [kit.board("medkit_buckle", (0.12, 0.03, 0.08), 0.01, axis=1, loc=(sx, Dp / 2 + 0.05, H - 0.25))
               for sx in (-0.3, 0.3)]
    kit.part(lib, root, kit.shift(kit.join(buckles, "medkit_buckles"), off), "Brass", shadow=False)
    kit.grip(lib, root)
    lib.finish(root)


BUILDERS = [water_bottle, empty_bottle, berries, apple, dried_meat, ration, bandage, herbs, medkit]
