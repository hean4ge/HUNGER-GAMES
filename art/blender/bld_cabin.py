"""bld_cabin.py - RangerCabin: stacked-log cabin with porch, west loft (ladder gap) and an east stone chimney."""
import math
import random

from mathutils import Vector as V

import bld_kit as k


def log_wall(name, axis, c, zs, half, r, openings, b, limit=None, ext=(0.7, 1.15)):
    """Logs along 'axis' at offset c with course centres zs. half = half wall length (centre-lines).
    openings: (lo, hi, zl, zh, has_sill). limit(z) = max half-length under the roof (gables) or None.
    Returns (logs, fits) where fits[i] = (header_top, sill_bottom) that close the gap to the nearest logs."""
    logs, fits = [], []
    for (lo, hi, zl, zh, sill) in openings:
        zc0, zc1 = zl - (b if sill else 0.0), zh + b
        above = [z for z in zs if z - 0.85 * r >= zc1]
        below = [z for z in zs if z + 0.85 * r <= zc0]
        fits.append(((min(above) - 0.45 * r) if above else zh + b, (max(below) + 0.45 * r) if below else zl - b))
    for z in zs:
        a0, a1 = -half - random.uniform(*ext), half + random.uniform(*ext)
        c0 = c1 = 0.13
        if limit is not None:
            lim = limit(z)
            if lim < 0.75:
                continue
            if -lim > a0:
                a0, c0 = -lim, 0.0
            if lim < a1:
                a1, c1 = lim, 0.0
        cuts = []
        for (lo, hi, zl, zh, sill) in openings:
            if z + 0.85 * r > zl - (b if sill else 0.0) and z - 0.85 * r < zh + b:
                cuts.append((lo - b + 0.1, hi + b - 0.1))
        for (lo, hi) in k.cut_intervals(a0, a1, cuts):
            if hi - lo < 0.5:
                continue
            dz = random.uniform(-0.03, 0.03)
            p0 = (lo, c, z + dz) if axis == "x" else (c, lo, z + dz)
            p1 = (hi, c, z - dz) if axis == "x" else (c, hi, z - dz)
            rr = r * random.uniform(0.93, 1.05)
            logs.append(k.tube(name, p0, p1, rr, rr * random.uniform(0.9, 0.99), segs=8,
                               ch0=c0 if lo == a0 else 0.0, ch1=c1 if hi == a1 else 0.0))
    return logs, fits


def build(lib):
    random.seed(1101)
    root = lib.begin("RangerCabin", kind="Building", tags=["Enterable", "Woodland"],
                     notes="Stacked-log cabin. Door centre front (+Y), 2 front windows, loft window in the west "
                           "gable. Loft over the west third (floor top z=10.9) reached by a TrussPart at "
                           "LadderBase/LadderTop (visual wooden ladder included, collide off).")
    HX, HY, r, s = 12.0, 8.0, 0.62, 1.05
    z0, nfb, floor_top = 0.95, 11, 1.0
    plate = z0 + (nfb - 1) * s + r
    pitch = 47.0
    tp = math.tan(math.radians(pitch))
    z_ru = plate + HY * tp
    runs = {1: HY + 1.0, -1: HY + 1.9}  # front eave lands on the porch roof
    RX = HX + r + 1.7
    rth = 0.6
    b = 0.36

    def limit(z):
        return (z_ru - (z + r) + 0.3) / tp

    fb_z = [z0 + i * s for i in range(nfb)]
    side_z = [z0 + s / 2 + i * s for i in range(20)]
    # standard 4 x 7.5 opening; 7.45 keeps the course at z=9.35 whole, so the head is a slim frame, not a slab
    door = k.door_opening(0.0, floor_top, h=k.DOOR_H - 0.05) + (False,)
    win_l = (-9.3, -5.7, 4.0, 7.4, True)
    win_r = (5.7, 9.3, 4.0, 7.4, True)
    win_w = (-1.5, 1.5, 12.9, 16.3, True)

    # ---------------- log walls ----------------
    front, ffit = log_wall("cab_front", "x", HY, fb_z, HX, r, [door, win_l, win_r], b)
    back, _ = log_wall("cab_back", "x", -HY, fb_z, HX, r, [], b)
    west, wfit = log_wall("cab_west", "y", -HX, side_z, HY, r, [win_w], b, limit=limit)
    east, _ = log_wall("cab_east", "y", HX, side_z, HY, r, [], b, limit=limit)
    for x in (-HX, HX):  # sill logs under the side walls (fill the half-course stagger)
        (west if x < 0 else east).append(
            k.tube("cab_sill", (x, -HY - 0.9, 0.5), (x, HY + 0.9, 0.5), 0.48, 0.45, segs=8, ch0=0.1, ch1=0.1))
    k.add(lib, root, front, "Logs", collision="PreciseConvexDecomposition", smooth_angle=50)
    k.add(lib, root, back, "Logs", rgb=k.tint("Logs", 4), collision="Box", smooth_angle=50)
    k.add(lib, root, west, "Logs", rgb=k.tint("Logs", 4), collision="PreciseConvexDecomposition", smooth_angle=50)
    k.add(lib, root, east, "Logs", rgb=k.tint("Logs", 4), collision="Hull", smooth_angle=50)

    # ridge log + purlins (log ends show under the gable overhang)
    beams = [k.tube("cab_ridge", (-RX - 0.3, 0, z_ru - 0.4), (RX + 0.3, 0, z_ru - 0.4), 0.42, 0.4, segs=8,
                    rings=3, ch0=0.08, ch1=0.08)]
    for y in (-4.6, 4.6):
        zp = z_ru - abs(y) * tp - 0.36
        beams.append(k.tube("cab_purlin", (-RX - 0.15, y, zp), (RX + 0.15, y, zp), 0.36, 0.34, segs=8,
                            ch0=0.08, ch1=0.08))
    beams.append(k.tube("cab_loftbeam", (-4.15, -HY - 0.2, 10.0), (-4.15, HY + 0.2, 10.0), 0.4, 0.38, segs=8))
    k.add(lib, root, beams, "Logs", rgb=(96, 72, 50), collide=False, smooth_angle=50)

    # ---------------- foundation, floors ----------------
    stones = []
    for (axis, c, a0, a1) in (("x", HY, -HX - 0.9, HX + 0.9), ("x", -HY, -HX - 0.9, HX + 0.9),
                              ("y", HX, -HY + 0.7, HY - 0.7), ("y", -HX, -HY + 0.7, HY - 0.7)):
        a = a0
        while a < a1 - 0.3:
            ln = min(random.uniform(2.4, 3.6), a1 - a)
            h = random.uniform(0.5, 0.62)
            w = random.uniform(1.45, 1.65)
            if axis == "x":
                stones.append(k.rock("cab_found", (a, c - w / 2, 0.04), (a + ln - 0.05, c + w / 2, h), 0.0, 0.05))
            else:
                stones.append(k.rock("cab_found", (c - w / 2, a, 0.04), (c + w / 2, a + ln - 0.05, h), 0.0, 0.05))
            a += ln
    k.add(lib, root, stones, "Stone", collision="Box")

    floor = k.abox("cab_floor", (-HX + 0.5, -HY + 0.5, 0.5), (HX - 0.5, HY - 0.5, floor_top))
    k.add(lib, root, floor, "Planks", collision="Box", tags=["Floor"])
    loft = k.abox("cab_loft", (-HX + 0.55, -HY + 0.55, 10.4), (-4.0, HY - 0.55, 10.9))
    k.add(lib, root, loft, "Planks", rgb=k.tint("Planks", 5), collision="Box", tags=["Floor"])

    # ---------------- porch ----------------
    deck = k.abox("cab_porch", (-10.2, HY + 0.45, 0.62), (10.2, HY + 4.0, floor_top))
    k.add(lib, root, deck, "Planks", rgb=(132, 100, 70), collision="Box", tags=["Floor"])
    step = [k.abox("cab_step", (-2.6, HY + 3.95, 0.0), (2.6, HY + 5.2, 0.5), 0.05)]
    k.add(lib, root, step, "Wood", collision="Box")
    piers = []
    post_x = (-9.6, -3.4, 3.4, 9.6)
    for x in post_x:
        piers.append(k.rock("cab_pier", (x - 0.55, HY + 3.0, 0.03), (x + 0.55, HY + 4.1, 0.66), 0.08, 0.04))
    k.add(lib, root, piers, "Stone", rgb=(126, 122, 114), collide=False)

    p_pitch = 18.0
    p_th = 0.45
    p_top_wall = z_ru - (HY + 0.62) * tp - 0.3
    p_zr = p_top_wall - p_th / math.cos(math.radians(p_pitch))
    p_run = 4.6
    proof = k.roof_slab("cab_proof", -10.8, 10.8, p_run, p_pitch, p_zr, p_th, side=1, c=(0, HY + 0.3),
                        nu=6, nv=2, sag=0.06)
    k.add(lib, root, proof, "Shingles", rgb=(94, 85, 76), collision="Hull")
    tpp = math.tan(math.radians(p_pitch))
    y_post = HY + 3.55
    z_beam_top = p_zr - (y_post - (HY + 0.3)) * tpp - 0.05
    porch_wood = [k.beam("cab_pbeam", (-10.4, y_post, z_beam_top - 0.3), (10.4, y_post, z_beam_top - 0.3),
                         0.5, 0.6, bev=0.05)]
    posts, knees = [], []
    for x in post_x:
        posts.append(k.tube("cab_post", (x, y_post, 0.62), (x, y_post, z_beam_top - 0.5), 0.34, 0.3, segs=8))
        for sx in (-1, 1):  # knee braces
            if abs(x + sx * 1.3) > 10.3:
                continue
            knees.append(k.beam("cab_knee", (x, y_post, z_beam_top - 1.9),
                                     (x + sx * 1.3, y_post, z_beam_top - 0.55), 0.22, 0.28, bev=0.03))
    k.add(lib, root, posts, "Logs", rgb=(98, 74, 52), collision="PreciseConvexDecomposition", smooth_angle=50)
    rail = []
    for (pts, sf, sl) in ((((-9.6, y_post), (-3.4, y_post)), True, True),
                          (((3.4, y_post), (9.6, y_post)), True, True),
                          (((-9.6, HY + 0.75), (-9.6, y_post)), False, True),
                          (((9.6, HY + 0.75), (9.6, y_post)), False, True)):
        rail += k.railing("cab_rail", pts, lambda x, y: floor_top, height=3.0, post_every=2.2, post=0.26,
                          rail=(0.2, 0.24), mid=True, skip_first=sf, skip_last=sl)
    k.add(lib, root, rail, "Wood", rgb=(124, 92, 62), collision="PreciseConvexDecomposition")

    # ---------------- main roof: slab (collision) + stepped shake courses + trim ----------------
    shakes = []
    st, ct = math.sin(math.radians(pitch)), math.cos(math.radians(pitch))
    for side in (1, -1):
        slab = k.roof_slab("cab_roof", -RX, RX, runs[side], pitch, z_ru, rth, side=side, nu=4, nv=2)
        k.add(lib, root, slab, "Shingles", rgb=(88, 80, 72), collision="Hull")
        shakes += k.shake_roof("cab_shake", -RX - 0.08, RX + 0.08, runs[side], pitch, z_ru, rth, side=side, courses=5,
                               lap=0.3, strip=0.16, lift_deg=4.5)
        z_cap = z_ru + rth / ct + 0.01 + 0.16 / math.cos(math.radians(pitch - 4.5)) + 0.02
        shakes.append(k.roof_slab("cab_cap", -RX - 0.2, RX + 0.2, 0.7, pitch - 4.5, z_cap, 0.16, side=side,
                                  nu=1, nv=1))
    k.add(lib, root, shakes, "Shingles", rgb=(98, 88, 78), collide=False)
    trim = []
    for side in (1, -1):
        for x in (-RX - 0.12, RX + 0.12):
            m0 = V((x, side * rth / 2 * st, z_ru + rth / 2 * ct + 0.3))
            m1 = V((x, side * (runs[side] + rth / 2 * st), z_ru - runs[side] * tp + rth / 2 * ct + 0.3))
            trim.append(k.beam("cab_barge", m0, m1, 0.22, rth + 1.0, up=(0, side * st, ct), bev=0.04, ext=0.2))
        if side > 0:
            continue
        e = V((0, side * (runs[side] + rth / 2 * st + 0.09 * ct), z_ru - runs[side] * tp + rth / 2 * ct - 0.09 * st))
        trim.append(k.beam("cab_fascia", e + V((-RX - 0.05, 0, 0)), e + V((RX + 0.05, 0, 0)), 0.18, rth + 0.4,
                           up=(0, side * st, ct), bev=0.03))
    # door / window frames + threshold
    trim += k.frame_boards("cab_frame", "x", HY, 2 * r, door[0], door[1], door[2], door[3], b=0.4, sill=False,
                           head_top=ffit[0][0])
    for wi, w in ((1, win_l), (2, win_r)):
        trim += k.frame_boards("cab_frame", "x", HY, 2 * r, w[0], w[1], w[2], w[3], b=b,
                               head_top=ffit[wi][0], sill_bot=ffit[wi][1])
    trim += k.frame_boards("cab_frame", "y", -HX, 2 * r, win_w[0], win_w[1], win_w[2], win_w[3], b=b,
                           head_top=wfit[0][0], sill_bot=wfit[0][1])
    trim.append(k.abox("cab_thresh", (door[0] - 0.05, HY - 0.75, 0.5), (door[1] + 0.05, HY + 0.8, floor_top + 0.03),
                       0.04))
    k.add(lib, root, trim + knees, "Wood", rgb=(122, 90, 60), collide=False)
    k.add(lib, root, porch_wood, "Wood", rgb=(112, 82, 56), collision="Box")

    # shutters (open, slightly angled) beside the front windows
    shut = []
    for w in (win_l, win_r):
        zc = (w[2] + w[3]) / 2
        for (hx, sx) in ((w[0] - b - 0.05, -1), (w[1] + b + 0.05, 1)):
            ang = math.radians(random.uniform(14, 26))
            p0 = V((hx, HY + r + 0.12, zc))
            p1 = p0 + V((sx * math.cos(ang) * 1.75, math.sin(ang) * 1.75, 0))
            shut.append(k.beam("cab_shutter", p0, p1, 0.16, w[3] - w[2] + 0.2, bev=0.04))
    k.add(lib, root, shut, "DarkPlanks", collide=False)

    # ---------------- loft railing + ladder ----------------
    lrail_a = k.railing("cab_lrail", ((-4.15, -5.4), (-4.15, -4.15)), lambda x, y: 10.9, height=3.0,
                        post_every=2.0, post=0.26, rail=(0.2, 0.24))
    lrail_b = k.railing("cab_lrail", ((-4.15, -1.85), (-4.15, 5.4)), lambda x, y: 10.9, height=3.0,
                        post_every=2.4, post=0.26, rail=(0.2, 0.24))
    k.add(lib, root, lrail_a, "Wood", rgb=(126, 94, 62), collision="Box")
    k.add(lib, root, lrail_b, "Wood", rgb=(126, 94, 62), collision="Box")
    lad_base = (-2.75, -3.0, floor_top)
    lad = k.ladder("cab_ladder", lad_base, 10.9 - floor_top, width=1.5, axis="y", step=1.0, top_ext=1.1)
    k.add(lib, root, lad, "Wood", rgb=(140, 106, 70), collide=False, tags=["LadderVisual"])
    lib.attach(root, "LadderBase", lad_base, look=(-1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "LadderTop", (lad_base[0], lad_base[1], 10.9), look=(-1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "Door", (0, HY, floor_top), look=(0, 1, 0), up=(0, 0, 1))

    # ---------------- stone chimney (east gable, outside) ----------------
    chim = []
    x_in = HX + r - 0.12
    courses = [(1.45, 2.95, 2.35)] * 5 + [(1.1, 2.5, 1.85), (1.1, 2.15, 1.45)] + [(1.3, 2.05, 1.3)] * 11
    z = 0.0
    for i, (h, dx, dy) in enumerate(courses):
        dx *= random.uniform(0.97, 1.03)
        dy *= random.uniform(0.97, 1.03)
        bw = 0.09 if i < 5 else 0.0
        if i % 2 == 0:  # joint on the outer face
            sy = random.uniform(-0.35, 0.35) * dy
            pieces = [((x_in, -dy), (x_in + dx, sy + 0.06)), ((x_in, sy - 0.06), (x_in + dx, dy))]
        else:  # joint on the side faces
            sx = x_in + dx * random.uniform(0.42, 0.6)
            pieces = [((x_in, -dy), (sx + 0.06, dy)), ((sx - 0.06, -dy), (x_in + dx, dy))]
        for (lo, hi) in pieces:
            o = random.uniform(-0.07, 0.07)
            chim.append(k.rock("cab_chim", (lo[0], lo[1] + o * 0.5, max(z - 0.06, 0.06)), (hi[0] + o, hi[1] + o * 0.5, z + h + 0.06),
                               bw, 0.06))
        z += h
    k.add(lib, root, chim, "Stone", rgb=(122, 118, 110), collision="Hull")
    cap = [k.rock("cab_chimcap", (x_in - 0.2, -1.55, z - 0.02), (x_in + 2.3, 1.55, z + 0.38), 0.08, 0.03),
           k.abox("cab_flue", (x_in + 0.5, -0.6, z + 0.36), (x_in + 1.6, 0.6, z + 0.42))]
    k.add(lib, root, cap, "DarkStone", collide=False)
    lib.finish(root)
    return root
