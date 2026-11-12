"""bld_tower.py - Watchtower: 32-stud timber lookout. Splayed log legs with girts and X-braces (front bottom bay
left open as the way in), a plank deck at z=22 with a 2.5x2.5 ladder well, railing, pyramid shingle roof + pennant."""
import math
import random

from mathutils import Vector as V

import ls_common as ls
import bld_kit as k


def build(lib):
    random.seed(1201)
    deck = 22.0
    root = lib.begin("Watchtower", kind="Building", tags=["Lookout"],
                     notes="Deck top z=22. Ladder well x 0.5..3.0, y -3.0..-0.5: place a 2x22x2 TrussPart "
                           "(Transparency 1) between LadderBase and LadderTop; the wooden ladder mesh is visual only. "
                           "Walk in through the open front (+Y) bottom bay.")
    B, T = 6.0, 4.3

    def leg(sx, sy, z):
        h = B + (T - B) * (z / deck)
        return V((sx * h, sy * h, z))

    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    hx0, hx1, hy0, hy1 = 0.5, 3.0, -3.0, -0.5
    hc = ((hx0 + hx1) / 2, (hy0 + hy1) / 2)
    z_e, fas, z_p, E = 27.8, 0.42, 32.0, 6.5
    z_ap = z_p - 0.65
    d_post = leg(1, 1, 28.5).x * math.sqrt(2)
    z_plate = z_ap - (z_ap - z_e) * d_post / (E * math.sqrt(2))

    # ---------------- legs (continue up as roof posts) + footings ----------------
    legs = [k.tube("tw_leg", leg(sx, sy, 0.6), leg(sx, sy, z_plate - 0.2), 0.56, 0.42, segs=10, rings=3, bend=0.06,
                   ch1=0.1) for (sx, sy) in corners]
    k.add(lib, root, legs, "Logs", rgb=(100, 76, 54), collision="PreciseConvexDecomposition", smooth_angle=50)
    foot = []
    for (sx, sy) in corners:
        p = leg(sx, sy, 0)
        foot.append(k.rock("tw_foot", (p.x - 1.0, p.y - 1.0, 0.05), (p.x + 1.0, p.y + 1.0, 0.9), 0.14, 0.07,
                           rz=random.uniform(-0.2, 0.2)))
    k.add(lib, root, foot, "Stone", collision="Box")

    # ---------------- girts, X-braces, ring beams ----------------
    frame = []
    sides = [((1, 1), (-1, 1), V((0, 1, 0))), ((-1, 1), (-1, -1), V((-1, 0, 0))),
             ((-1, -1), (1, -1), V((0, -1, 0))), ((1, -1), (1, 1), V((1, 0, 0)))]
    bays = [(1.0, 7.5), (7.5, 15.0), (15.0, 20.8)]
    for (c1, c2, n) in sides:
        for z in (7.5, 15.0):
            frame.append(k.beam("tw_girt", leg(*c1, z) + n * 0.3, leg(*c2, z) + n * 0.3, 0.4, 0.5, bev=0.04,
                                ext=0.45))
        for bi, (za, zb) in enumerate(bays):
            if n.y > 0.5 and bi == 0:  # open front bottom bay: knee braces only
                for (ca, cb) in ((c1, c2), (c2, c1)):
                    pa = leg(*ca, 4.6) + n * 0.42
                    pb = leg(*ca, 7.5) + (leg(*cb, 7.5) - leg(*ca, 7.5)).normalized() * 2.4 + n * 0.42
                    frame.append(k.beam("tw_knee", pa, pb, 0.3, 0.4, bev=0.04, ext=0.15))
                continue
            frame.append(k.beam("tw_brace", leg(*c1, za) + n * 0.45, leg(*c2, zb) + n * 0.45, 0.3, 0.42, bev=0.04,
                                ext=0.2))
            frame.append(k.beam("tw_brace", leg(*c2, za) + n * 0.62, leg(*c1, zb) + n * 0.62, 0.3, 0.42, bev=0.04,
                                ext=0.2))
    k.add(lib, root, frame, "Wood", rgb=(112, 84, 58), collision="PreciseConvexDecomposition")

    under = []
    for (c1, c2, n) in sides:
        under.append(k.beam("tw_ring", leg(*c1, deck - 1.0), leg(*c2, deck - 1.0), 0.5, 0.7, bev=0.05, ext=0.9))
    for y in (4.0, 1.7, hy1 + 0.2, hy0 - 0.2, -5.0):
        under.append(k.beam("tw_joist", (-5.65, y, deck - 0.5), (5.65, y, deck - 0.5), 0.4, 0.32, bev=0.03))
    k.add(lib, root, under, "Wood", rgb=(104, 78, 54), collision="Box")

    # ---------------- deck planks in 4 groups (Box collision each keeps the ladder well open) ----------------
    groups = {"L": [], "R": [], "F": [], "K": []}
    edges = [-5.6, -4.55, -3.5, -2.5, -1.5, -0.5, hx0, 1.75, hx1, 4.3, 5.6]
    for i in range(len(edges) - 1):
        x0, x1 = edges[i] + 0.035, edges[i + 1] - 0.035
        top = deck + random.uniform(-0.015, 0.015)
        e0, e1 = -5.6 - random.uniform(0, 0.12), 5.6 + random.uniform(0, 0.12)
        if x1 <= hx0:
            groups["L"].append(k.abox("tw_plank", (x0, e0, deck - 0.35), (x1, e1, top), 0.04))
        elif x0 >= hx1:
            groups["R"].append(k.abox("tw_plank", (x0, e0, deck - 0.35), (x1, e1, top), 0.04))
        else:
            groups["F"].append(k.abox("tw_plank", (x0, hy1, deck - 0.35), (x1, e1, top), 0.04))
            groups["K"].append(k.abox("tw_plank", (x0, e0, deck - 0.35), (x1, hy0, top), 0.04))
    for g in ("L", "R", "F", "K"):
        k.add(lib, root, groups[g], "Planks", rgb=k.tint("Planks", 5), collision="Box", tags=["Floor"])

    # ---------------- railing (one Box part per side) ----------------
    q = 5.42
    flat = lambda x, y: deck  # noqa: E731
    k.add(lib, root, k.railing("tw_rail", ((-q, q), (q, q)), flat, height=3.4, post_every=q, post=0.36),
          "Wood", rgb=(120, 90, 62), collision="Box")
    k.add(lib, root, k.railing("tw_rail", ((q, -q), (-q, -q)), flat, height=3.4, post_every=q, post=0.36),
          "Wood", rgb=(120, 90, 62), collision="Box")
    k.add(lib, root, k.railing("tw_rail", ((-q, -q), (-q, q)), flat, height=3.4, post_every=q, post=0.36,
                               skip_first=True, skip_last=True), "Wood", rgb=(120, 90, 62), collision="Box")
    k.add(lib, root, k.railing("tw_rail", ((q, q), (q, -q)), flat, height=3.4, post_every=q, post=0.36,
                               skip_first=True, skip_last=True), "Wood", rgb=(120, 90, 62), collision="Box")

    # ---------------- roof: top plates, knee braces, pyramid shell, hips, pennant ----------------
    top = []
    for (c1, c2, n) in sides:
        top.append(k.beam("tw_plate", leg(*c1, z_plate - 0.3), leg(*c2, z_plate - 0.3), 0.4, 0.6, bev=0.04,
                          ext=0.5))
        for (ca, cb) in ((c1, c2), (c2, c1)):
            pa = leg(*ca, z_plate - 2.2)
            pb = leg(*ca, z_plate - 0.5) + (leg(*cb, z_plate - 0.5) - leg(*ca, z_plate - 0.5)).normalized() * 1.6
            top.append(k.beam("tw_rknee", pa, pb, 0.24, 0.3, bev=0.03, ext=0.1))
    k.add(lib, root, top, "Wood", rgb=(108, 80, 56), collide=False)
    shell = ls.lathe("tw_roof", [(0.0, z_ap), (E * math.sqrt(2), z_e), (E * math.sqrt(2), z_e + fas), (0.0, z_p)],
                     segments=4, rot=(0, 0, math.radians(45)))
    k.add(lib, root, shell, "Shingles", rgb=(86, 78, 70), collision="Hull")  # sloped roofs are Hull everywhere
    D = E * math.sqrt(2)

    def zs(r):  # roof top surface height at diagonal radius r
        return z_p - (z_p - (z_e + fas)) * r / D
    courses = []
    for (f0, f1) in ((0.0, 0.37), (0.31, 0.69), (0.63, 1.03)):
        r0, r1 = f0 * D, f1 * D
        courses.append(ls.lathe("tw_course", [(r0, zs(r0) - 0.25), (r1, zs(r1) - 0.25), (r1, zs(r1) + 0.32),
                                              (r0, zs(r0) + 0.08)], segments=4, rot=(0, 0, math.radians(45))))
    k.add(lib, root, courses, "Shingles", rgb=(96, 86, 76), collide=False)
    hips = []
    for (sx, sy) in corners:
        hips.append(k.beam("tw_hip", (sx * (E + 0.2), sy * (E + 0.2), z_e + fas + 0.3), (0, 0, z_p + 0.42),
                           0.34, 0.26, bev=0.03))
    hips.append(k.tube("tw_pole", (0, 0, z_p - 0.4), (0, 0, z_p + 3.4), 0.1, 0.08, segs=6))
    k.add(lib, root, hips, "Wood", rgb=(96, 72, 50), collide=False)
    flag = k.grid_solid("tw_flag", 4, 1, lambda u, v: (0.05 + 0.25 * math.sin(u * 3.0) * u, 0.1 + u * 2.1,
                                                         z_p + 3.3 - v * (1.1 - 0.75 * u) - u * 0.25), 0.06,
                        side=(1, 0, 0))
    k.add(lib, root, flag, "Banner", collide=False)

    # ---------------- visual ladder + TrussPart markers ----------------
    lad = k.ladder("tw_ladder", (hc[0], hc[1], 0.0), deck, width=1.5, axis="x", step=1.0, top_ext=1.1)
    k.add(lib, root, lad, "Wood", rgb=(140, 106, 70), collide=False, tags=["LadderVisual"])
    lib.attach(root, "LadderBase", (hc[0], hc[1], 0.0), look=(0, -1, 0), up=(0, 0, 1))
    lib.attach(root, "LadderTop", (hc[0], hc[1], deck), look=(0, -1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root
