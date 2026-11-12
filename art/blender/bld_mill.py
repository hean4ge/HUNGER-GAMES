"""bld_mill.py - RiverMill (stone ground floor, half-timbered upper storey, clay-tile roof, wheel bearings and a
plank tailrace on the east side) and the separate WaterWheel (centred on its axle at the origin, axle along X)."""
import math
import random

from mathutils import Vector as V

import ls_common as ls
import bld_kit as k

AXLE = (13.6, 0.0, 7.4)  # wheel centre in RiverMill space (WheelAxle attachment)


def build_mill(lib):
    random.seed(1301)
    root = lib.begin("RiverMill", kind="Building", tags=["Enterable", "Woodland", "River"],
                     notes="Enterable stone ground floor (floor top z=0.4, door front-left). Put the WaterWheel "
                           "asset at the WheelAxle attachment (same orientation) and spin it about X. The plank "
                           "tailrace + water strip under the wheel is part of the mill.")
    HX, HY, t = 10.0, 8.0, 1.2
    zw, floor_top = 10.0, 0.4
    ox, oy = HX + t / 2, HY + t / 2  # outer faces 10.6 / 8.6
    door = k.door_opening(-3.3, floor_top)   # standard 4 x 7.5 opening
    win_f = (3.0, 6.0, 3.8, 7.0)
    win_w = (-1.5, 1.5, 3.8, 7.0)
    win_b = (-2.5, 0.5, 4.2, 6.8)

    # ---------------- stone storey ----------------
    walls = [
        (k.wall_boxes("ml_wall", "x", HY, t, -HX + t / 2, HX - t / 2, 0.0, zw, [door[:4], win_f], 0.07),
         "PreciseConvexDecomposition"),
        (k.wall_boxes("ml_wall", "x", -HY, t, -HX + t / 2, HX - t / 2, 0.0, zw, [win_b], 0.07),
         "PreciseConvexDecomposition"),
        (k.wall_boxes("ml_wall", "y", -HX, t, -oy, oy, 0.0, zw, [win_w], 0.07), "PreciseConvexDecomposition"),
        (k.wall_boxes("ml_wall", "y", HX, t, -oy, oy, 0.0, zw, [], 0.07), "Box"),
    ]
    for (pieces, col) in walls:
        k.add(lib, root, pieces, "Stone", rgb=k.tint("Stone", 4), collision=col)
    dress = []
    for (a0, a1) in ((-ox - 0.15, door[0] - 0.05), (door[1] + 0.05, ox + 0.15)):  # plinth course (gap at door)
        dress.append(k.rock("ml_plinth", (a0, oy - 0.45, 0.03), (a1, oy + 0.16, 0.8), 0.06, 0.02))
    dress.append(k.rock("ml_plinth", (-ox - 0.15, -oy - 0.16, 0.03), (ox + 0.15, -oy + 0.45, 0.8), 0.06, 0.02))
    for sx in (-1, 1):
        dress.append(k.rock("ml_plinth", (sx * ox - 0.16 * (sx < 0) - 0.45 * (sx > 0), -oy + 0.3, 0.03),
                            (sx * ox + 0.16 * (sx > 0) + 0.45 * (sx < 0), oy - 0.3, 0.8), 0.06, 0.02))
    for (sx, sy) in ((1, 1), (-1, 1), (-1, -1), (1, -1)):  # quoins
        z, i = 0.8, random.randint(0, 1)
        while z < zw - 0.4:
            h = min(random.uniform(1.0, 1.25), zw - z)
            lx, ly = (1.9, 1.05) if i % 2 == 0 else (1.05, 1.9)
            xo, yo = sx * (ox + 0.12), sy * (oy + 0.12)
            dress.append(k.rock("ml_quoin", (min(xo, xo - sx * lx), min(yo, yo - sy * ly), z),
                                (max(xo, xo - sx * lx), max(yo, yo - sy * ly), z + h - 0.05), 0.08, 0.025))
            z += h
            i += 1
    for (axis, c, (lo, hi, zl, zh), sill) in (("x", HY, win_f, True), ("x", -HY, win_b, True),
                                             ("y", -HX, win_w, True), ("x", HY, door[:4], False)):
        d = t / 2 + 0.13
        if axis == "x":
            dress.append(k.rock("ml_lintel", (lo - 0.55, c - d, zh), (hi + 0.55, c + d, zh + 0.85), 0.07, 0.02))
            if sill:
                dress.append(k.rock("ml_sill", (lo - 0.3, c - d - 0.12, zl - 0.32), (hi + 0.3, c + d + 0.12, zl),
                                    0.05, 0.01))
        else:
            dress.append(k.rock("ml_lintel", (c - d, lo - 0.55, zh), (c + d, hi + 0.55, zh + 0.85), 0.07, 0.02))
            dress.append(k.rock("ml_sill", (c - d - 0.12, lo - 0.3, zl - 0.32), (c + d + 0.12, hi + 0.3, zl),
                                0.05, 0.01))
    dress.append(k.rock("ml_corbel", (ox - 0.1, -0.8, 5.5), (ox + 0.7, 0.8, 6.55), 0.06, 0.03))
    k.add(lib, root, dress, "Granite", rgb=(146, 140, 130), collide=False)

    k.add(lib, root, k.abox("ml_floor", (-HX + 0.5, -HY + 0.5, 0.0), (HX - 0.5, HY - 0.5, floor_top)),
          "Planks", collision="Box", tags=["Floor"])
    k.add(lib, root, k.abox("ml_ceiling", (-HX + 0.5, -HY + 0.5, zw - 0.4), (HX - 0.5, HY - 0.5, zw + 0.05)),
          "Planks", rgb=(110, 82, 56), collision="Box")

    # ---------------- half-timbered upper storey (solid attic volume) + timber dressing ----------------
    pitch, ux, uy, z_eave = 40.0, ox + 0.2, oy + 0.2, 14.2
    tp = math.tan(math.radians(pitch))
    z_ru = z_eave + uy * tp
    attic = [k.abox("ml_attic", (-ux, -uy, zw + 0.55), (ux, uy, z_eave)),
             k.prism("ml_gable", [(-uy, z_eave - 0.05), (uy, z_eave - 0.05), (0.0, z_ru - 0.15)], -ux, ux, axis="x")]
    k.add(lib, root, attic, "Plaster", rgb=(204, 194, 172), collision="Box")
    tim = []
    for (axis, c, n) in (("x", uy, 1), ("x", -uy, -1), ("y", ux, 1), ("y", -ux, -1)):
        a1 = ux if axis == "x" else uy
        o = c + n * 0.08
        P = (lambda a, z, o=o: V((a, o, z))) if axis == "x" else (lambda a, z, o=o: V((o, a, z)))
        up = (0, 1, 0) if axis == "x" else (1, 0, 0)
        tim.append(k.beam("ml_sillb", P(-a1 - 0.35, zw + 0.3), P(a1 + 0.35, zw + 0.3), 0.6, 0.62, up=(0, 0, 1),
                          bev=0.05))
        tim.append(k.beam("ml_rail", P(-a1, z_eave - 0.2), P(a1, z_eave - 0.2), 0.4, 0.34, up=(0, 0, 1)))
        tim.append(k.beam("ml_mid", P(-a1, 12.35), P(a1, 12.35), 0.3, 0.28, up=(0, 0, 1)))
        n_p = 6 if axis == "x" else 5
        xs = [-a1 + 0.2 + i * (2 * a1 - 0.4) / n_p for i in range(n_p + 1)]
        for i, a in enumerate(xs):
            tim.append(k.beam("ml_stud", P(a, zw + 0.55), P(a, z_eave - 0.05), 0.34, 0.3, up=up))
            if i < n_p and i % 2 == 0:
                tim.append(k.beam("ml_diag", P(a, zw + 0.6), P(xs[i + 1], 12.3), 0.26, 0.28, up=up))
                tim.append(k.beam("ml_diag", P(xs[i + 1], 12.4), P(a, z_eave - 0.3), 0.26, 0.28, up=up))
        if axis == "y":  # gable timbers: king post + struts
            tim.append(k.beam("ml_king", P(0.0, z_eave), P(0.0, z_ru - 0.3), 0.36, 0.3, up=up))
            for s in (-1, 1):
                tim.append(k.beam("ml_strut", P(s * uy * 0.85, z_eave + 0.1), P(0.0, z_eave + uy * tp * 0.7),
                                  0.28, 0.28, up=up))
    tim.append(k.abox("ml_hoistdoor", (-ux - 0.18, -1.3, 15.0), (-ux + 0.1, 1.3, 18.0), 0.05))
    k.add(lib, root, tim, "DarkPlanks", rgb=(74, 56, 42), collide=False)

    # ---------------- clay-tile roof ----------------
    run, RX = uy + 1.3, ux + 1.1
    st, ct = math.sin(math.radians(pitch)), math.cos(math.radians(pitch))
    rth = 0.5
    tiles = []
    for side in (1, -1):
        slab = k.roof_slab("ml_roof", -RX, RX, run, pitch, z_ru, rth, side=side, nu=4, nv=2)
        k.add(lib, root, slab, "RoofTiles", rgb=(118, 68, 52), collision="Hull")
        tiles += k.shake_roof("ml_tiles", -RX - 0.06, RX + 0.06, run, pitch, z_ru, rth, side=side, courses=6,
                              lap=0.25, strip=0.14, lift_deg=3.5)
    k.add(lib, root, tiles, "RoofTiles", rgb=(128, 74, 54), collide=False)
    zt = z_ru + rth / ct + 0.14 / math.cos(math.radians(pitch - 3.5)) + 0.02
    ridge = k.tube("ml_ridge", (-RX - 0.15, 0, zt - 0.1), (RX + 0.15, 0, zt - 0.1), 0.42, segs=8, rings=2, phase=0.0)
    k.add(lib, root, ridge, "RoofTiles", rgb=(104, 60, 46), collide=False, smooth_angle=50)
    trim = []
    for side in (1, -1):
        for x in (-RX - 0.12, RX + 0.12):
            m0 = V((x, side * rth / 2 * st, z_ru + rth / 2 * ct + 0.25))
            m1 = V((x, side * (run + rth / 2 * st), z_ru - run * tp + rth / 2 * ct + 0.25))
            trim.append(k.beam("ml_barge", m0, m1, 0.22, rth + 0.9, up=(0, side * st, ct), bev=0.04, ext=0.2))
        e = V((0, side * (run + rth / 2 * st + 0.09 * ct), z_ru - run * tp + rth / 2 * ct - 0.09 * st))
        trim.append(k.beam("ml_fascia", e + V((-RX, 0, 0)), e + V((RX, 0, 0)), 0.18, rth + 0.35,
                           up=(0, side * st, ct), bev=0.03))

    # ---------------- door frame, shutters, hoist ----------------
    trim += k.frame_boards("ml_door", "x", HY, t, door[0], door[1], door[2], door[3], b=0.34, proud=0.05,
                           sill=False)
    k.add(lib, root, trim, "Wood", rgb=(116, 86, 58), collide=False)
    shut = []
    for (hx, sx) in ((win_f[0] - 0.08, -1), (win_f[1] + 0.08, 1)):
        ang = math.radians(random.uniform(12, 24))
        p0 = V((hx, oy + 0.16, (win_f[2] + win_f[3]) / 2))
        shut.append(k.beam("ml_shutter", p0, p0 + V((sx * math.cos(ang) * 1.5, math.sin(ang) * 1.5, 0)), 0.15,
                           win_f[3] - win_f[2] + 0.1, bev=0.04))
    k.add(lib, root, shut, "DarkPlanks", rgb=(70, 82, 70), collide=False)
    hoist = [k.beam("ml_hoist", (-ux + 0.3, 0, 19.3), (-ux - 2.9, 0, 19.3), 0.55, 0.6, bev=0.05),
             k.beam("ml_hbrace", (-ux - 0.05, 0, 17.6), (-ux - 1.6, 0, 19.1), 0.3, 0.32, up=(0, 1, 0), bev=0.03)]
    k.add(lib, root, hoist, "Wood", rgb=(100, 74, 52), collide=False)
    k.add(lib, root, [k.tube("ml_rope", (-ux - 2.55, 0, 19.0), (-ux - 2.55, 0, 15.2), 0.07, segs=6),
                      k.ring("ml_coil", 0.18, 0.32, 15.0, 15.25, segs=8, c=(-ux - 2.55, 0, 0))],
          "Rope", collide=False)

    # ---------------- wheel bearings, A-frame, tailrace ----------------
    ax, ay, az = AXLE
    bear = [k.abox("ml_bear", (ox - 0.1, -0.9, az - 0.9), (ox + 0.9, 0.9, az + 0.9), 0.08),
            k.abox("ml_bear2", (ax + 2.15, -0.85, az - 0.9), (ax + 3.1, 0.85, az + 0.9), 0.08)]
    xa = ax + 2.62
    for s in (-1, 1):
        bear.append(k.beam("ml_aleg", (xa, s * 3.4, 0.45), (xa, s * 0.6, az + 0.6), 0.5, 0.55, up=(1, 0, 0),
                           bev=0.05))
    bear.append(k.beam("ml_atie", (xa, -2.7, 2.4), (xa, 2.7, 2.4), 0.36, 0.42, bev=0.04))
    bear.append(k.beam("ml_asill", (xa, -4.0, 0.25), (xa, 4.0, 0.25), 0.7, 0.5, bev=0.05))
    k.add(lib, root, bear, "Wood", rgb=(96, 72, 50), collision="PreciseConvexDecomposition")
    straps = [k.ring("ml_strap", 0.44, 0.62, x - 0.12, x + 0.12, segs=10, axis="x", c=(0, 0, az))
              for x in (ox + 0.9, ax + 2.15)]
    k.add(lib, root, straps, "DarkMetal", collide=False)
    race_y = 9.2
    race = [k.abox("ml_race", (ax - 2.0, -race_y, 0.02), (ax + 2.0, race_y, 0.3)),
            k.abox("ml_race", (ax - 2.0, -race_y, 0.25), (ax - 1.62, race_y, 1.3), 0.04),
            k.abox("ml_race", (ax + 1.62, -race_y, 0.25), (ax + 2.0, race_y, 1.3), 0.04)]
    k.add(lib, root, race, "Planks", rgb=(98, 76, 56), collision="PreciseConvexDecomposition")
    k.add(lib, root, k.abox("ml_water", (ax - 1.64, -race_y + 0.05, 0.3), (ax + 1.64, race_y - 0.05, 0.85)),
          "WaterFill", collide=False, cast_shadow=False)
    lib.attach(root, "WheelAxle", AXLE, look=(1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "Door", ((door[0] + door[1]) / 2, oy, floor_top), look=(0, 1, 0), up=(0, 0, 1))

    # ---------------- interior: millstones + flour sacks ----------------
    k.add(lib, root, k.abox("ml_stand", (3.2, -5.0, floor_top - 0.05), (7.0, -1.2, 1.5), 0.06), "Wood",
          rgb=(110, 82, 56), collision="Box")
    stones = [k.tube("ml_bedstone", (5.1, -3.1, 1.45), (5.1, -3.1, 2.1), 1.55, segs=14, phase=0.0),
              k.tube("ml_runner", (5.1, -3.1, 2.12), (5.1, -3.1, 2.78), 1.45, 1.4, segs=14, phase=0.2)]
    k.add(lib, root, stones, "Granite", collision="Hull")
    sacks = []
    for (x, y, rz) in ((-7.6, -6.2, 0.3), (-6.3, -6.5, -0.4), (-7.0, -5.0, 1.1)):
        sk = ls.uvsphere("ml_sack", 1.0, segments=8, rings=5, loc=(x, y, 0.95 + floor_top), rot=(0, 0, rz),
                         scale=(0.85, 0.7, 0.98))
        ls.jitter(sk, 0.05)
        sacks.append(sk)
    k.add(lib, root, sacks, "Canvas", rgb=(196, 182, 150), collide=False, smooth_angle=60)
    lib.finish(root)
    return root


def build_wheel(lib):
    random.seed(1302)
    root = lib.begin("WaterWheel", kind="Mechanism", tags=["Spin"],
                     notes="Diameter 14. Pivot = axle centre at the origin, axle along X (Roblox X). Place at "
                           "RiverMill.WheelAxle and rotate about the part's X axis. Below-zero extent is intentional.")
    rims = [k.ring("ww_rim", 6.1, 6.62, x - 0.22, x + 0.22, segs=20, axis="x") for x in (-1.3, 1.3)]
    spokes = []
    for xs in (-1.3, 1.3):
        for i in range(8):
            a = k.TAU * i / 8
            d = V((0, math.cos(a), math.sin(a)))
            spokes.append(k.beam("ww_spoke", V((xs, 0, 0)) + d * 1.0, V((xs, 0, 0)) + d * 6.35, 0.42, 0.36,
                                 up=(1, 0, 0), bev=0.04))
    k.add(lib, root, rims + spokes, "Wood", rgb=(110, 80, 54), collision="Hull")
    paddles = []
    for i in range(16):
        a = k.TAU * (i + 0.5) / 16
        d = V((0, math.cos(a), math.sin(a)))
        tg = V((0, -math.sin(a), math.cos(a)))
        c = d * 6.3
        up = d * math.cos(0.28) + tg * math.sin(0.28)
        paddles.append(k.beam("ww_paddle", c + V((-1.5, 0, 0)), c + V((1.5, 0, 0)), 0.22, 1.4, up=up, bev=0.04))
    k.add(lib, root, paddles, "Planks", rgb=(122, 92, 62), collide=False)
    hub = [k.tube("ww_hub", (-1.75, 0, 0), (1.75, 0, 0), 1.05, segs=12, phase=0.0),
           k.tube("ww_axle", (-3.05, 0, 0), (3.25, 0, 0), 0.42, segs=10, phase=0.0)]
    for x in (-1.3, 1.3):
        hub.append(k.ring("ww_flange", 0.9, 1.55, x - 0.3, x + 0.3, segs=12, axis="x"))
    k.add(lib, root, hub, "DarkMetal", collide=False, smooth_angle=40)
    lib.attach(root, "Axle", (0, 0, 0), look=(1, 0, 0), up=(0, 0, 1))
    n = len(lib.warnings)
    lib.finish(root)
    # The wheel is pivoted on its axle (so it can spin), so dipping below z = 0 is by design: report it as a NOTE
    # (like the held items) instead of leaving a manifest warning that every importer run would flag.
    for w in lib.warnings[n:]:
        if "below z = 0" in w:
            print("NOTE " + w + " [axle-centred pivot by design]")
    lib.warnings[n:] = [w for w in lib.warnings[n:] if "below z = 0" not in w]
    return root
