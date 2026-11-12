"""bld_swamp.py - StiltHut (thatched plank hut on 7-stud stilts, porch + ramp) and WalkwaySegment."""
import math
import random

from mathutils import Vector as V

import bld_kit as k
from bld_water import plank_run


def build_stilthut(lib):
    random.seed(1701)
    ft, HX, HY, t = 7.0, 7.0, 6.0, 0.6
    ox, oy = HX + t / 2, HY + t / 2
    py1 = 10.4
    root = lib.begin("StiltHut", kind="Building", tags=["Enterable", "Swamp"],
                     notes="14 x 12 hut, floor top z=7.0 on log stilts. Porch on the front (+Y) under the thatch "
                           "hood; the ramp leaves the porch's east end and lands at x=20.6 (z=0).")
    # ---------------- platform, stilts, braces ----------------
    k.add(lib, root, k.abox("sh_deck", (-ox - 0.3, -oy - 0.3, ft - 0.4), (ox + 0.3, py1, ft)), "Planks",
          rgb=(112, 90, 66), collision="Box", tags=["Floor"])
    rim = []
    for (a, b) in (((-ox - 0.4, py1 - 0.2), (ox + 0.4, py1 - 0.2)), ((-ox - 0.4, -oy - 0.15), (ox + 0.4, -oy - 0.15)),
                   ((-ox - 0.15, -oy - 0.4), (-ox - 0.15, py1)), ((ox + 0.15, -oy - 0.4), (ox + 0.15, py1))):
        rim.append(k.beam("sh_rim", (a[0], a[1], ft - 0.55), (b[0], b[1], ft - 0.55), 0.42, 0.72, bev=0.04))
    stilts = []
    sx_list, sy_list = (-HX - 0.1, 0.0, HX + 0.1), (-HY - 0.1, 0.0, HY + 0.1, py1 - 0.5)
    for x in sx_list:
        for y in sy_list:
            base = V((x + random.uniform(-0.3, 0.3), y + random.uniform(-0.3, 0.3), 0.0))
            stilts.append(k.tube("sh_stilt", base, (x, y, ft - 0.3), random.uniform(0.4, 0.5),
                                 random.uniform(0.32, 0.4), segs=8, ch0=0.1))
    k.add(lib, root, stilts, "Logs", rgb=(80, 66, 52), collision="PreciseConvexDecomposition", smooth_angle=50)
    br = []

    def xbrace(a, b, n):
        br.append(k.beam("sh_brace", V((a[0], a[1], 0.7)) + n * 0.44, V((b[0], b[1], ft - 1.0)) + n * 0.44,
                         0.26, 0.34, bev=0.03, ext=0.25))
        br.append(k.beam("sh_brace", V((b[0], b[1], 0.7)) + n * 0.62, V((a[0], a[1], ft - 1.0)) + n * 0.62,
                         0.26, 0.34, bev=0.03, ext=0.25))
    for sx in (-1, 1):
        x = sx * (HX + 0.1)
        xbrace((x, -HY - 0.1), (x, 0.0), V((sx, 0, 0)))
        xbrace((x, 0.0), (x, HY + 0.1), V((sx, 0, 0)))
    xbrace((-HX - 0.1, -HY - 0.1), (0.0, -HY - 0.1), V((0, -1, 0)))
    xbrace((0.0, -HY - 0.1), (HX + 0.1, -HY - 0.1), V((0, -1, 0)))
    k.add(lib, root, br, "Wood", rgb=(96, 78, 58), collision="PreciseConvexDecomposition")

    # ---------------- plank walls with gables (ridge runs along Y, gable faces the porch) ----------------
    pitch = 42.0
    tp = math.tan(math.radians(pitch))
    z_pl = ft + 9.6
    z_ru = z_pl + ox * tp
    door = k.door_opening(0.0, ft)   # standard 4 x 7.5 opening
    win = (-1.4, 1.4, ft + 3.6, ft + 6.0)

    def gable(yc):
        return k.prism("sh_gable", [(-ox, z_pl - 0.05), (ox, z_pl - 0.05), (0.0, z_ru - 0.15)], yc - t / 2,
                       yc + t / 2, axis="y")
    k.add(lib, root, k.wall_boxes("sh_wall", "x", HY, t, -ox, ox, ft, z_pl, [door]) + [gable(HY)], "DarkPlanks",
          collision="PreciseConvexDecomposition")
    k.add(lib, root, k.wall_boxes("sh_wall", "x", -HY, t, -ox, ox, ft, z_pl, []) + [gable(-HY)], "DarkPlanks",
          rgb=k.tint("DarkPlanks", 4), collision="Hull")
    for x in (HX, -HX):
        k.add(lib, root, k.wall_boxes("sh_wall", "y", x, t, -HY + t / 2, HY - t / 2, ft, z_pl, [win]),
              "DarkPlanks", rgb=k.tint("DarkPlanks", 4), collision="PreciseConvexDecomposition")

    # ---------------- thatch roof ----------------
    a0, a1, run, rth = -oy - 1.3, py1 + 1.4, ox + 1.6, 1.0
    thatch = []
    for side in (1, -1):
        slab = k.roof_slab("sh_roof", a0, a1, run, pitch, z_ru, rth, side=side, axis="y", nu=7, nv=3, jit=0.12)
        k.add(lib, root, slab, "Thatch", collision="Hull")
        thatch += k.shake_roof("sh_thatch", a0 - 0.15, a1 + 0.15, run, pitch, z_ru, rth, side=side, axis="y",
                               courses=3, lap=0.45, strip=0.38, lift_deg=6.0, nu=6, jit=0.14)
    z_top = z_ru + rth / math.cos(math.radians(pitch)) + 0.38 / math.cos(math.radians(pitch - 6.0))
    thatch.append(k.tube("sh_ridge", (0, a0 - 0.3, z_top - 0.2), (0, a1 + 0.3, z_top - 0.2), 0.7, 0.66, segs=8,
                         rings=3, bend=0.08, phase=0.0))
    k.add(lib, root, thatch, "Thatch", rgb=(150, 130, 84), collide=False, smooth_angle=55)

    # ---------------- porch: posts, hood truss, railings, frames ----------------
    yp = py1 - 0.45
    z_tie = z_pl - 0.55
    wood = [k.beam("sh_tie", (-ox - 0.4, yp, z_tie), (ox + 0.4, yp, z_tie), 0.42, 0.6, bev=0.04),
            k.beam("sh_king", (0, yp, z_tie), (0, yp, z_ru - 0.3), 0.36, 0.36, up=(0, 1, 0), bev=0.03)]
    for s in (-1, 1):
        wood.append(k.beam("sh_rafter", (s * (ox + 1.2), yp + 0.9, z_pl - 1.2 * tp - 0.25),
                           (0, yp + 0.9, z_ru - 0.25), 0.36, 0.42, up=(0, 1, 0), bev=0.03, ext=0.1))
        wood.append(k.beam("sh_strut", (0, yp, z_tie + 0.3), (s * ox * 0.55, yp, z_ru - ox * 0.55 * tp - 0.3),
                           0.28, 0.3, up=(0, 1, 0), bev=0.03))
    wood += k.frame_boards("sh_frame", "x", HY, t, door[0], door[1], door[2], door[3], b=0.34, sill=False)
    for x in (HX, -HX):
        wood += k.frame_boards("sh_frame", "y", x, t, *win, b=0.3)
    k.add(lib, root, wood + rim, "Wood", rgb=(108, 84, 60), collide=False)
    posts = [k.tube("sh_post", (s * (ox - 0.3), yp, ft - 0.4), (s * (ox - 0.3), yp, z_tie - 0.25), 0.34, 0.3, segs=8)
             for s in (-1, 1)]
    k.add(lib, root, posts, "Logs", rgb=(86, 70, 54), collision="PreciseConvexDecomposition", smooth_angle=50)
    flat = lambda x, y: ft  # noqa: E731
    k.add(lib, root, k.railing("sh_rail", ((-ox + 0.3, yp), (ox - 0.3, yp)), flat, height=3.0, post_every=2.4,
                               post=0.28, skip_first=True, skip_last=True), "Wood", rgb=(118, 92, 64), collision="Box")
    k.add(lib, root, k.railing("sh_rail", ((-ox - 0.05, oy + 0.15), (-ox - 0.05, yp)), flat, height=3.0,
                               post_every=2.0, post=0.28, skip_last=True), "Wood", rgb=(118, 92, 64), collision="Box")

    # ---------------- ramp off the porch's east end ----------------
    ry0, ry1 = 6.9, 9.7
    x0, x1 = ox + 0.3, ox + 13.3
    z1 = 0.62
    rmid = (ry0 + ry1) / 2
    d = V((x1 - x0, 0, z1 - ft)).normalized()
    n_up = V((-d.z, 0, d.x))

    def rz(x):
        return ft + (x - x0) * (z1 - ft) / (x1 - x0)
    planks = plank_run("sh_ramp", (x0 - 0.15, rmid, ft), (x1, rmid, z1), 0.85, ry1 - ry0, 0.3, n_up, gap=0.1,
                       jit_len=0.25)
    k.add(lib, root, planks, "Planks", rgb=(118, 94, 68), collision="Hull", tags=["Floor"])
    under = []
    for y in (ry0 + 0.4, ry1 - 0.4):
        under.append(k.beam("sh_rstring", V((x0 - 0.3, y, ft - 0.3)) - n_up * 0.3, V((x1 - 0.9, y, z1 + 0.3)) - n_up * 0.3,
                            0.36, 0.5, up=n_up, bev=0.03))
    for xp in (x0 + 3.6, x0 + 7.6):
        for y in (ry0 + 0.4, ry1 - 0.4):
            under.append(k.tube("sh_rpost", (xp, y, 0.0), (xp, y, rz(xp) - 0.75), 0.3, 0.26, segs=8))
    k.add(lib, root, under, "Logs", rgb=(84, 68, 52), collision="PreciseConvexDecomposition", smooth_angle=50)
    hand = k.railing("sh_hand", ((x0 + 1.0, ry1 + 0.15), (x1 - 0.6, ry1 + 0.15)), lambda x, y: rz(x), height=3.0,
                     post_every=3.8, post=0.26, mid=False)
    k.add(lib, root, hand, "Wood", rgb=(118, 92, 64), collision="Hull")

    # reed bundles leaning by the door
    reeds = []
    for (x, y) in ((-5.6, 7.0), (-4.7, 6.9)):
        b0 = V((x, y, ft))
        b1 = b0 + V((random.uniform(-0.4, 0.4), -0.55, 5.6))
        reeds.append(k.tube("sh_reed", b0, b1, 0.42, 0.18, segs=7, rings=3, bulge=0.25))
    k.add(lib, root, reeds, "Reed", collide=False, smooth_angle=60)
    lib.attach(root, "Door", (0, oy, ft), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "RampFoot", (x1, rmid, 0.0), look=(1, 0, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


def build_walkway(lib):
    random.seed(1801)
    top = 2.0
    root = lib.begin("WalkwaySegment", kind="Building", tags=["Swamp", "Walkway"],
                     notes="12-stud plank walkway along Y, deck top z=2.0. Chain segments end to end: EndB of one "
                           "segment = EndA of the next (12 studs apart).")
    planks = plank_run("wk_plank", (0, -6.0, top), (0, 6.0, top), 0.84, 4.0, 0.28, (0, 0, 1), gap=0.1,
                       jit_len=0.28, tilt=0.03)
    k.add(lib, root, planks, "Planks", rgb=(116, 92, 66), collision="Box", tags=["Floor"])
    frame = [k.beam("wk_string", (x, -6.0, top - 0.48), (x, 6.0, top - 0.48), 0.4, 0.4, bev=0.03) for x in (-1.35, 1.35)]
    frame += [k.beam("wk_cap", (-2.0, y, top - 0.88), (2.0, y, top - 0.88), 0.45, 0.4, bev=0.03) for y in (-4.6, 4.6)]
    k.add(lib, root, frame, "Wood", rgb=(98, 76, 54), collision="Box")
    posts = []
    for y in (-4.6, 4.6):
        for x in (-1.55, 1.55):
            base = V((x + random.uniform(-0.15, 0.15), y + random.uniform(-0.15, 0.15), 0.07))
            posts.append(k.tube("wk_post", base, (x, y, top - 1.0), 0.34, 0.3, segs=8))
    k.add(lib, root, posts, "Logs", rgb=(82, 68, 54), collision="Box", smooth_angle=50)
    lib.attach(root, "EndA", (0, -6.0, top), look=(0, -1, 0), up=(0, 0, 1))
    lib.attach(root, "EndB", (0, 6.0, top), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root
