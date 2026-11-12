"""bld_water.py - waterside structures: Bridge, FishingShack, Jetty, StiltHut, WalkwaySegment."""
import math
import random

from mathutils import Vector as V

import ls_common as ls
import bld_kit as k


def corrugated(name, x0, x1, y0, y1, waves, amp=0.16, thick=0.08):
    """Corrugated tin sheet lying flat (ridges along Y) between x0..x1, y0..y1, bottom at z=0."""
    n = waves * 2
    top = [(x0 + (x1 - x0) * i / n, amp if i % 2 else 0.0) for i in range(n + 1)]
    pts = top + [(x, z - thick) for (x, z) in reversed(top)]
    pts = [(x, z + thick) for (x, z) in pts]
    return k.prism(name, pts, y0, y1, axis="y")


def plank_run(name, p_start, p_end, width, length, thick, n_up, gap=0.08, jit_len=0.3, bev=0.04, tilt=0.0):
    """Deck planks laid across a straight run (planks perpendicular to the run, lying on its top).
    n_up = the deck normal. Returns a list of planks."""
    a, b = V(p_start), V(p_end)
    d = (b - a)
    L = d.length
    dn = d.normalized()
    side = V(n_up).cross(dn).normalized()
    out = []
    count = max(1, int(L / (width + gap)))
    w = L / count - gap
    for i in range(count):
        c = a + dn * ((i + 0.5) * (w + gap)) - V(n_up) * (thick / 2) + V(n_up) * random.uniform(-0.015, 0.015)
        e0 = length / 2 + random.uniform(0, jit_len)
        e1 = length / 2 + random.uniform(0, jit_len)
        up = (V(n_up) + dn * random.uniform(-tilt, tilt)).normalized()
        out.append(k.beam(name, c - side * e0, c + side * e1, w, thick, up=up, bev=bev))
    return out


# ------------------------------------------------------------------------------------------------
def build_bridge(lib):
    random.seed(1401)
    half, W, rise, h_end = 18.0, 8.0, 2.4, 0.95
    root = lib.begin("Bridge", kind="Building", tags=["Bridge", "River"],
                     notes="36 x 8 timber arch bridge spanning Blender/Roblox X. Deck top z=0.95 at the ends, "
                           "3.35 at mid-span. Ends rest on stone abutments at z=0.")

    def dz(x):
        return h_end + rise * (1 - (x / half) ** 2)

    def nrm(x):
        return V((2 * rise * x / half ** 2, 0, 1)).normalized()

    segs = [(-half, -6.0), (-6.0, 6.0), (6.0, half)]
    for (xa, xb) in segs:
        planks = []
        n = int(round((xb - xa) / 0.98))
        for i in range(n):
            x = xa + (i + 0.5) * (xb - xa) / n
            up = nrm(x)
            c = V((x, 0, dz(x))) - up * 0.16 + V((0, 0, random.uniform(-0.02, 0.02)))
            e0, e1 = W / 2 + random.uniform(0.05, 0.35), W / 2 + random.uniform(0.05, 0.35)
            planks.append(k.beam("br_plank", c - V((0, e0, 0)), c + V((0, e1, 0)), (xb - xa) / n - 0.08, 0.32,
                                 up=(up + V((random.uniform(-0.02, 0.02), 0, 0))).normalized(), bev=0.04))
        k.add(lib, root, planks, "Planks", rgb=k.tint("Planks", 6), collision="PreciseConvexDecomposition",
              tags=["Floor"])

    # arched stringers (3) + knee struts down to the abutments
    under = []
    xs = [-half + 0.4 + i * (2 * half - 0.8) / 12 for i in range(13)]
    for y in (-3.3, 0.0, 3.3):
        deep = 1.15 if abs(y) > 1 else 0.8
        for i in range(12):
            a, b = xs[i], xs[i + 1]
            dd = min(deep, min(dz(a), dz(b)) - 0.32 - 0.12)
            pa = V((a, y, dz(a) - 0.32 - dd / 2))
            pb = V((b, y, dz(b) - 0.32 - dd / 2))
            under.append(k.beam("br_stringer", pa, pb, 0.55, dd, ext=0.12))
    for sx in (-1, 1):
        for y in (-3.3, 3.3):
            xe = sx * (half - 7.0)
            under.append(k.beam("br_strut", (sx * (half - 1.6), y, 0.55), (xe, y, dz(xe) - 1.3), 0.45, 0.5,
                                up=(0, 1, 0), bev=0.04, ext=0.2))
        for x in (sx * (half - 4.2), sx * (half - 9.5)):
            under.append(k.beam("br_cross", (x, -3.9, dz(x) - 0.75), (x, 3.9, dz(x) - 0.75), 0.4, 0.45, bev=0.03))
    k.add(lib, root, under, "Wood", rgb=(100, 74, 52), collide=False)

    stones = []
    for sx in (-1, 1):
        y = -4.9
        while y < 4.9:
            w = min(random.uniform(2.0, 3.2), 4.9 - y)
            x0, x1 = sorted((sx * (half - 2.6 + random.uniform(-0.2, 0.2)), sx * (half + 0.7)))
            stones.append(k.rock("br_abut", (x0, y, 0.04), (x1, y + w - 0.06, random.uniform(0.62, 0.78)), 0.14, 0.07))
            y += w
        for y in (-4.6, 4.6):  # wing stones
            x0, x1 = sorted((sx * (half - 0.6), sx * (half + 1.5)))
            stones.append(k.rock("br_wing", (x0, y - 0.9, 0.04), (x1, y + 0.9, 1.25), 0.16, 0.08))
    k.add(lib, root, stones, "Stone", collision="Box")

    for sy in (-1, 1):
        y = sy * (W / 2 - 0.3)
        rail = k.railing("br_rail", ((-half + 0.9, y), (half - 0.9, y)), lambda x, yy: dz(x), height=3.1,
                         post_every=4.2, post=0.38, rail=(0.26, 0.3), mid=True)
        for sx in (-1, 1):  # chunky newel posts at the ends
            rail.append(k.tube("br_newel", (sx * (half - 0.3), y, 0.05), (sx * (half - 0.3), y, dz(half) + 4.0),
                               0.42, 0.38, segs=8, ch1=0.14))
        k.add(lib, root, rail, "Wood", rgb=(116, 86, 58), collision="Hull")
    lib.attach(root, "EndWest", (-half, 0, h_end), look=(-1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "EndEast", (half, 0, h_end), look=(1, 0, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------
def build_shack(lib):
    random.seed(1501)
    HX, HY, t, ft = 5.7, 4.7, 0.6, 1.0
    root = lib.begin("FishingShack", kind="Building", tags=["Enterable", "Lakeside"],
                     notes="12 x 10 plank shack on a low deck with a covered porch (front +Y). Floor top z=1.0. "
                           "Rusty corrugated shed roof (high side at the front).")
    p = math.radians(9.0)
    tp = math.tan(p)
    yf, zf = HY + t / 2, 12.0

    def zu(y):  # roof underside
        return zf - (yf - y) * tp

    deck = k.abox("fs_deck", (-HX - 0.6, -HY - 0.6, 0.62), (HX + 0.6, HY + 3.6, ft))
    k.add(lib, root, deck, "Planks", rgb=(118, 92, 66), collision="Box", tags=["Floor"])
    k.add(lib, root, k.abox("fs_step", (-1.9, HY + 3.55, 0.0), (1.9, HY + 4.6, 0.5), 0.05), "Wood",
          rgb=(110, 84, 58), collision="Box")
    posts = []
    for x in (-HX - 0.2, 0.0, HX + 0.2):
        for y in (-HY - 0.2, HY + 3.2):
            posts.append(k.tube("fs_pile", (x, y, 0.0), (x, y, 0.66), 0.34, 0.3, segs=8))
    k.add(lib, root, posts, "Logs", rgb=(92, 72, 52), collide=False, smooth_angle=50)

    door = k.door_opening(-1.6, ft)   # standard 4 x 7.5 opening
    win_f = (2.0, 4.6, 4.6, 7.2)
    win_b = (-1.3, 1.3, 5.0, 7.0)
    win_e = (-1.6, 1.4, 4.6, 7.2)
    front = k.wall_boxes("fs_wall", "x", HY, t, -HX - t / 2, HX + t / 2, ft, zu(HY + t / 2) - 0.02,
                         [door, win_f])
    back = k.wall_boxes("fs_wall", "x", -HY, t, -HX - t / 2, HX + t / 2, ft, zu(-HY - t / 2) - 0.02, [win_b])
    k.add(lib, root, front, "Planks", collision="PreciseConvexDecomposition")
    k.add(lib, root, back, "Planks", rgb=k.tint("Planks", 4), collision="PreciseConvexDecomposition")
    zlo = zu(-HY - t / 2) - 0.02
    for (x, ops) in ((HX, [win_e]), (-HX, [])):
        wall = k.wall_boxes("fs_wall", "y", x, t, -HY + t / 2, HY - t / 2, ft, zlo, ops)
        wall.append(k.prism("fs_wedge", [(-HY + t / 2, zlo - 0.05), (HY - t / 2, zlo - 0.05),
                                         (HY - t / 2, zu(HY - t / 2) - 0.03), (-HY + t / 2, zu(-HY + t / 2) - 0.03)],
                            x - t / 2, x + t / 2, axis="x"))
        k.add(lib, root, wall, "Planks", rgb=k.tint("Planks", 4),
              collision="PreciseConvexDecomposition" if ops else "Hull")

    # battens + corner boards (exterior detail)
    bat = []
    opens = {"f": [door, win_f], "b": [win_b], "e": [win_e], "w": []}
    for (key, axis, c, a0, a1) in (("f", "x", HY + t / 2, -HX, HX), ("b", "x", -HY - t / 2, -HX, HX),
                                   ("e", "y", HX + t / 2, -HY, HY), ("w", "y", -HX - t / 2, -HY, HY)):
        n_b = int((a1 - a0) / 1.45)
        sgn = 1 if c > 0 else -1
        for i in range(1, n_b):
            a = a0 + i * (a1 - a0) / n_b + random.uniform(-0.1, 0.1)
            top = zu(c if axis == "x" else a) - 0.05
            spans = [(ft, top)]
            for (lo, hi, zl, zh) in opens[key]:
                if lo - 0.55 < a < hi + 0.55:
                    spans = [(z0, z1) for (z0, z1) in spans for (z0, z1) in
                             ((z0, min(z1, zl - 0.5)), (max(z0, zh + 0.5), z1)) if z1 - z0 > 0.4]
            for (z0, z1) in spans:
                if axis == "x":
                    bat.append(k.abox("fs_batten", (a - 0.13, c - sgn * 0.05, z0), (a + 0.13, c + sgn * 0.11, z1)))
                else:
                    bat.append(k.abox("fs_batten", (c - sgn * 0.05, a - 0.13, z0), (c + sgn * 0.11, a + 0.13, z1)))
    for (sx, sy) in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        x, y = sx * (HX + t / 2), sy * (HY + t / 2)
        bat.append(k.abox("fs_corner", (x - 0.42, y - 0.42, ft - 0.05), (x + 0.42, y + 0.42, zu(y) - 0.04), 0.05))
    k.add(lib, root, bat, "DarkPlanks", rgb=(80, 62, 46), collide=False)

    trim = k.frame_boards("fs_frame", "x", HY, t, door[0], door[1], door[2], door[3], b=0.32, sill=False)
    trim += k.frame_boards("fs_frame", "x", HY, t, *win_f, b=0.3)
    trim += k.frame_boards("fs_frame", "x", -HY, t, *win_b, b=0.3)
    trim += k.frame_boards("fs_frame", "y", HX, t, *win_e, b=0.3)
    # porch: two tall posts + beam under the high front eave
    yp = HY + 3.2
    pw = [k.beam("fs_pbeam", (-HX - 0.9, yp, zu(yp) - 0.33), (HX + 0.9, yp, zu(yp) - 0.33), 0.4, 0.6, bev=0.04)]
    for y in (-3.3, -0.6, 2.1, 4.0):  # purlins under the sheets
        pw.append(k.beam("fs_purlin", (-HX - 1.0, y, zu(y) - 0.2), (HX + 1.0, y, zu(y) - 0.2), 0.32, 0.4, bev=0.03))
    k.add(lib, root, trim + pw, "Wood", rgb=(126, 96, 66), collide=False)
    pposts = [k.tube("fs_post", (x, yp, 0.62), (x, yp, zu(yp) - 0.55), 0.3, 0.27, segs=8) for x in (-HX - 0.3, HX + 0.3)]
    k.add(lib, root, pposts, "Logs", rgb=(98, 76, 54), collision="PreciseConvexDecomposition", smooth_angle=50)

    # rusty corrugated roof: 3 sheets, tilted to the pitch (two tints)
    y_back, y_front = -HY - t / 2 - 1.1, HY + 3.9
    L = (y_front - y_back) / math.cos(p)
    sheets = {0: [], 1: []}
    xs = [-HX - 1.1, -2.15, 2.25, HX + 1.1]
    for i in range(3):
        sh = corrugated("fs_sheet", xs[i] + 0.02, xs[i + 1] - 0.02, 0.0, L, waves=7)
        sh.rotation_euler = (p, 0, 0)
        sh.location = (0.0, y_back, zu(y_back) + 0.01 + 0.03 * (i % 2))
        sheets[i % 2].append(sh)
    k.add(lib, root, sheets[0], "Rust", rgb=(122, 82, 58), collision="Hull")
    k.add(lib, root, sheets[1], "Rust", rgb=(108, 76, 60), collision="Hull")

    # stove pipe, shutter, net with floats, oars
    pipe = [k.tube("fs_pipe", (-3.4, -2.4, 7.5), (-3.4, -2.4, zu(-2.4) + 2.6), 0.3, segs=10, phase=0.0),
            k.ring("fs_pipecap", 0.0, 0.55, 0.0, 0.12, segs=10, c=(-3.4, -2.4, zu(-2.4) + 2.75)),
            k.ring("fs_collar", 0.28, 0.5, 0.0, 0.25, segs=10, c=(-3.4, -2.4, zu(-2.4) + 0.12))]
    k.add(lib, root, pipe, "DarkMetal", collide=False, smooth_angle=40)
    # top-hinged shutter propped open (hangs out and down from the hinge) + its prop stick
    hinge = V((HX + t / 2 + 0.15, (win_e[0] + win_e[1]) / 2, win_e[3] + 0.38))
    ang = math.radians(58)
    dvec = V((math.sin(ang), 0, -math.cos(ang)))
    cen = hinge + dvec * 1.5
    shutter = [k.beam("fs_shutter", cen - V((0, 1.7, 0)), cen + V((0, 1.7, 0)), 0.14, 3.0, up=dvec, bev=0.03),
               k.beam("fs_prop", (HX + t / 2 + 0.1, cen.y + 1.2, win_e[2] - 0.3), hinge + dvec * 2.9 + V((0, 1.2, 0)),
                      0.12, 0.12)]
    k.add(lib, root, shutter, "DarkPlanks", rgb=(70, 84, 76), collide=False)
    net = k.grid_solid("fs_net", 6, 3, lambda u, v: (-HX - t / 2 - 0.2 - 0.25 * math.sin(math.pi * u) * v,
                                                    -3.6 + 5.0 * u, 8.6 - 3.6 * v - 0.8 * math.sin(math.pi * u) * v),
                       0.05, side=(-1, 0, 0))
    k.add(lib, root, net, "Rope", rgb=(150, 128, 96), collide=False)
    floats = [ls.uvsphere("fs_float", 0.32, segments=6, rings=4, loc=(-HX - t / 2 - 0.45, y, z))
              for (y, z) in ((-2.4, 5.6), (-0.6, 5.0), (0.9, 5.5))]
    k.add(lib, root, floats, "Banner", rgb=(196, 88, 44), collide=False, smooth_angle=60)
    oars = []
    for (x, lean) in ((-5.1, 0.22), (-4.4, 0.3)):
        base = V((x, HY + t / 2 + 0.35, ft + 0.05))
        topp = base + V((random.uniform(-0.3, 0.3), -lean * 0.6, 6.6))
        oars.append(k.tube("fs_oar", base + (topp - base) * 0.28, topp, 0.1, segs=6))
        oars.append(k.beam("fs_blade", base, base + (topp - base) * 0.3, 0.55, 0.1, up=(0, 1, 0), bev=0.03))
    k.add(lib, root, oars, "Wood", rgb=(150, 116, 78), collide=False)
    lib.attach(root, "Door", ((door[0] + door[1]) / 2, HY + t / 2, ft), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------
def build_jetty(lib):
    random.seed(1601)
    top, hw = 3.0, 3.0
    root = lib.begin("Jetty", kind="Building", tags=["Lakeside", "Water"],
                     notes="24-stud pier along +Y (shore end at -Y, water end at +Y). Deck top z=3.0; sink the "
                           "posts into the water/lake bed as needed.")
    planks = []
    y, i = -12.0, 0
    while y < 11.95:
        w = random.uniform(0.82, 0.95)
        y1 = min(y + w, 12.0)
        loose = (i == 17)
        e0, e1 = hw + random.uniform(0.0, 0.32), hw + random.uniform(0.0, 0.32)
        rz = math.radians(random.uniform(-1.2, 1.2) + (3.5 if loose else 0.0))
        zt = top + random.uniform(-0.02, 0.02) + (0.05 if loose else 0.0)
        planks.append(k.abox("jt_plank", (-e0, y + 0.04, zt - 0.3), (e1, y1 - 0.04, zt), 0.04, rz=rz))
        y, i = y1, i + 1
    k.add(lib, root, planks, "Planks", rgb=(120, 94, 68), collision="Box", tags=["Floor"])
    frame = []
    for x in (-2.2, 2.2):
        frame.append(k.beam("jt_stringer", (x, -12.1, top - 0.52), (x, 12.1, top - 0.52), 0.45, 0.45, bev=0.04))
    ys = [-11.4, -7.6, -3.8, 0.0, 3.8, 7.6, 11.4]
    for y in ys:
        frame.append(k.beam("jt_cap", (-hw, y, top - 0.95), (hw, y, top - 0.95), 0.5, 0.42, bev=0.04))
    k.add(lib, root, frame, "Wood", rgb=(100, 76, 54), collision="Box")
    posts, braces = [], []
    for j, y in enumerate(ys):
        for x in (-2.6, 2.6):
            lean = V((random.uniform(-0.12, 0.12), random.uniform(-0.12, 0.12), 0))
            posts.append(k.tube("jt_post", V((x, y, 0.0)) + lean, (x, y, top - 1.1), random.uniform(0.34, 0.42),
                                segs=8, ch1=0.08))
        if j % 2 == 1:
            braces.append(k.beam("jt_brace", (-2.6, y, 0.4), (2.6, y, top - 1.25), 0.24, 0.3, up=(0, 1, 0), bev=0.03))
            braces.append(k.beam("jt_brace", (2.6, y + 0.3, 0.4), (-2.6, y + 0.3, top - 1.25), 0.24, 0.3, up=(0, 1, 0),
                                 bev=0.03))
    k.add(lib, root, posts, "Logs", rgb=(84, 70, 56), collision="Box", smooth_angle=50)
    k.add(lib, root, braces, "Wood", rgb=(96, 76, 56), collide=False)
    for (x, y, h) in ((hw - 0.1, 11.7, 5.0), (-hw + 0.1, 3.0, 4.4)):
        k.add(lib, root, k.tube("jt_bollard", (x, y, 0.0), (x, y, h), 0.42, 0.38, segs=8, ch1=0.12), "Logs",
              rgb=(90, 72, 54), collision="Hull", smooth_angle=50)
    ropes = [k.ring("jt_wrap", 0.4, 0.5, 3.6, 3.85, segs=8, c=(hw - 0.1, 11.7, 0)),
             k.ring("jt_wrap", 0.4, 0.5, 4.05, 4.3, segs=8, c=(hw - 0.1, 11.7, 0)),
             k.ring("jt_coil", 0.3, 0.62, top, top + 0.16, segs=10, c=(1.2, 9.6, 0)),
             k.ring("jt_coil", 0.32, 0.52, top + 0.14, top + 0.28, segs=10, c=(1.25, 9.62, 0))]
    k.add(lib, root, ropes, "Rope", collide=False)
    lad = k.ladder("jt_ladder", (-1.2, 12.25, 0.0), top - 0.1, width=1.4, axis="x", step=0.9, top_ext=1.0)
    k.add(lib, root, lad, "Wood", rgb=(126, 96, 66), collide=False, tags=["LadderVisual"])
    lib.attach(root, "ShoreEnd", (0, -12, top), look=(0, -1, 0), up=(0, 0, 1))
    lib.attach(root, "WaterEnd", (0, 12, top), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root
