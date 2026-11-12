"""bld_props.py - small camp / settlement props (Props category)."""
import math
import random

from mathutils import Vector as V

import ls_common as ls
import bld_kit as k

CORNERS = ((1, 1), (-1, 1), (-1, -1), (1, -1))


def tri_panel(name, a, b, c, thick):
    """Thin triangular solid (a flap of cloth, a gusset)."""
    a, b, c = V(a), V(b), V(c)
    n = (b - a).cross(c - a).normalized() * thick
    return k.mesh_obj(name, [a, b, c, a + n, b + n, c + n],
                      [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)])


def placed(obj, loc, rz=0.0, rx=0.0, ry=0.0):
    obj.rotation_euler = (rx, ry, rz)
    obj.location = loc
    return obj


# ------------------------------------------------------------------------------------------------
def build_tent(lib):
    random.seed(2101)
    root = lib.begin("Tent", kind="Prop", tags=["Camp"],
                     notes="A-frame canvas tent, entrance at the front (+Y), one flap rolled, one staked open.")
    L, Wh, H = 7.6, 3.0, 4.7
    y0, y1 = -L / 2, L / 2
    canvas = []
    for side in (-1, 1):
        def fn(u, v, side=side):
            y = y0 + (y1 - y0) * u
            sag = 0.22 * math.sin(math.pi * u) * math.sin(math.pi * min(v * 1.25, 1.0))
            x = side * (0.06 + (Wh - 0.06) * v + 0.28 * v * v)
            z = H - (H - 0.14) * v - sag + 0.1 * v * math.sin(math.pi * u)
            return (x, y, z)
        canvas.append(k.grid_solid("tn_canvas", 6, 4, fn, 0.08, side=(side, 0, 1)))
    canvas.append(k.prism("tn_back", [(-Wh - 0.26, 0.14), (Wh + 0.26, 0.14), (0.0, H - 0.02)], y0 - 0.02, y0 + 0.06,
                          axis="y"))
    canvas.append(tri_panel("tn_flap", (0.12, y1 - 0.02, H - 0.1), (Wh + 0.24, y1 - 0.02, 0.16),
                            (Wh * 0.55, y1 + 1.5, 0.18), 0.07))
    k.add(lib, root, canvas, "Canvas", collision="Default", smooth_angle=50)
    roll = [k.tube("tn_roll", (-0.35, y1 + 0.06, H - 0.75), (-Wh - 0.2, y1 + 0.1, 0.35), 0.2, 0.16, segs=7, rings=3,
                   bend=0.05)]
    k.add(lib, root, roll, "Canvas", rgb=(160, 148, 118), collide=False, smooth_angle=60)
    bed = [k.tube("tn_bedroll", (-1.6, -1.2, 0.36), (-1.6, 1.4, 0.36), 0.36, segs=9, phase=0.0)]
    k.add(lib, root, bed, "Cloth", rgb=(92, 104, 84), collide=False, smooth_angle=50)
    wood = [k.tube("tn_pole", (0, y, 0.0), (0, y, H + 0.45), 0.1, 0.08, segs=6) for y in (y0 - 0.12, y1 + 0.12)]
    wood.append(k.tube("tn_ridge", (0, y0 - 0.35, H + 0.04), (0, y1 + 0.35, H + 0.04), 0.09, segs=6))
    stakes = [(0, y1 + 2.6), (0, y0 - 2.6), (Wh * 0.55, y1 + 1.6)] + [(sx * (Wh + 0.45), sy * (L / 2 - 0.3))
                                                                    for (sx, sy) in CORNERS]
    for (x, y) in stakes:
        wood.append(k.beam("tn_stake", (x, y, 0.02), (x, y, 0.45), 0.12, 0.12, up=(0, 1, 0)))
    k.add(lib, root, wood, "Wood", rgb=(132, 102, 70), collide=False)
    ropes = [k.tube("tn_guy", (0, y1 + 0.12, H + 0.3), (0, y1 + 2.6, 0.35), 0.045, segs=5),
             k.tube("tn_guy", (0, y0 - 0.12, H + 0.3), (0, y0 - 2.6, 0.35), 0.045, segs=5),
             k.tube("tn_tie", (-1.1, y1 + 0.1, H - 1.6), (-1.1, y1 + 0.25, H - 2.2), 0.05, segs=5)]
    k.add(lib, root, ropes, "Rope", collide=False)
    lib.finish(root)
    return root


def build_campfire(lib):
    random.seed(2201)
    root = lib.begin("Campfire", kind="Prop", tags=["Camp", "Fire"],
                     notes="Stone ring + teepee logs + glowing coals. Attach fire particles / PointLight / crackle "
                           "sound at FireCenter.")
    stones = []
    n = 10
    for i in range(n):
        a = k.TAU * i / n + random.uniform(-0.08, 0.08)
        r = 1.55 + random.uniform(-0.08, 0.1)
        sx, sy, sz = random.uniform(0.75, 0.95), random.uniform(0.55, 0.7), random.uniform(0.42, 0.58)
        st = k.rock("cf_stone", (-sx / 2, -sy / 2, 0.08), (sx / 2, sy / 2, sz), 0.12, 0.05)
        stones.append(placed(st, (r * math.cos(a), r * math.sin(a), 0.0), a + math.pi / 2,
                             random.uniform(-0.08, 0.08), random.uniform(-0.08, 0.08)))
    k.add(lib, root, stones, "Stone", rgb=(122, 118, 110), collision="Box")
    k.add(lib, root, k.tube("cf_ash", (0, 0, 0.0), (0, 0, 0.09), 1.3, segs=10), "Dirt", rgb=(58, 50, 44),
          collide=False)
    logs = []
    for i in range(4):
        a = k.TAU * i / 4 + 0.4
        logs.append(k.tube("cf_log", (1.05 * math.cos(a), 1.05 * math.sin(a), 0.16),
                           (0.18 * math.cos(a + 0.5), 0.18 * math.sin(a + 0.5), 1.3), 0.17, 0.12, segs=6))
    logs.append(k.tube("cf_log", (-1.1, -0.35, 0.2), (1.1, 0.4, 0.22), 0.16, 0.14, segs=6))
    k.add(lib, root, logs, "Logs", rgb=(64, 50, 40), collide=False)
    coals = []
    for i in range(6):
        a = k.TAU * i / 6 + random.uniform(-0.3, 0.3)
        r = random.uniform(0.15, 0.6)
        s = random.uniform(0.16, 0.26)
        c = k.rock("cf_coal", (-s, -s * 0.8, 0.04), (s, s * 0.8, 0.04 + s), 0.0, 0.04)
        coals.append(placed(c, (r * math.cos(a), r * math.sin(a), 0.0), random.uniform(0, 3)))
    k.add(lib, root, coals, "Ember", collide=False, cast_shadow=False)
    lib.attach(root, "FireCenter", (0, 0, 0.6), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


def build_fence(lib):
    random.seed(2301)
    root = lib.begin("FenceSegment", kind="Prop", tags=["Fence"],
                     notes="8-stud post-and-rail segment along X (posts at x=+-3.8). Place segments 8 studs apart.")
    posts = []
    for x in (-3.8, 3.8):
        h = 4.2 + random.uniform(-0.15, 0.15)
        posts.append(k.beam("fn_post", (x, 0, 0.0), (x, 0, h), 0.48, 0.48, up=(0, 1, 0), bev=0.06))
        posts.append(ls.lathe("fn_cap", [(0.36, h - 0.02), (0.08, h + 0.32)], segments=4,
                              loc=(x, 0, 0), rot=(0, 0, math.radians(45))))
    k.add(lib, root, posts, "Wood", rgb=(104, 80, 58), collision="Box")
    rails = []
    for z in (0.95, 2.2, 3.4):
        dz = random.uniform(-0.08, 0.08)
        rails.append(k.tube("fn_rail", (-4.05, random.uniform(-0.04, 0.04), z + dz),
                            (4.05, random.uniform(-0.04, 0.04), z - dz), 0.21, 0.18, segs=6, rings=3, bend=0.06))
    k.add(lib, root, rails, "DeadWood", collision="Box")
    lib.finish(root)
    return root


def _crate(size, frames, bodies, loc, rz):
    s = size / 2
    S = size
    parts_b = [k.abox("cp_body", (-s * 0.97, -s * 0.97, 0.0), (s * 0.97, s * 0.97, S * 0.97), 0.05)]
    parts_f = []
    for (sx, sy) in CORNERS:
        parts_f.append(k.abox("cp_edge", (sx * s - 0.16, sy * s - 0.16, 0.0), (sx * s + 0.16, sy * s + 0.16, S)))
    for z in (0.0, S - 0.28):
        for sy in (-1, 1):
            parts_f.append(k.abox("cp_edge", (-s + 0.1, sy * s - 0.14, z), (s - 0.1, sy * s + 0.14, z + 0.28)))
        for sx in (-1, 1):
            parts_f.append(k.abox("cp_edge", (sx * s - 0.13, -s + 0.1, z + 0.01), (sx * s + 0.13, s - 0.1, z + 0.27)))
    for sy in (-1, 1):
        parts_f.append(k.beam("cp_diag", (-s + 0.2, sy * (s + 0.02), 0.3), (s - 0.2, sy * (s + 0.02), S - 0.3), 0.26,
                              0.12, up=(0, 1, 0)))
    for o in parts_b + parts_f:
        placed(o, loc, rz)
    bodies += parts_b
    frames += parts_f


def build_cratepile(lib):
    random.seed(2401)
    root = lib.begin("CratePile", kind="Prop", tags=["Cover"], notes="Decorative stack of 4 crates (one Box collider).")
    bodies, frames = [], []
    _crate(3.0, frames, bodies, (-1.55, -0.1, 0.0), 0.06)
    _crate(2.7, frames, bodies, (1.45, 0.25, 0.0), -0.14)
    _crate(2.5, frames, bodies, (-1.2, -0.05, 3.0 * 0.97 + 0.02), 0.38)
    _crate(1.8, frames, bodies, (0.9, 2.45, 0.0), 0.62)
    k.add(lib, root, bodies, "Planks", rgb=(136, 104, 70), collision="Box")
    k.add(lib, root, frames, "Wood", rgb=(96, 70, 48), collide=False)
    lib.finish(root)
    return root


def build_barrel(lib):
    random.seed(2501)
    root = lib.begin("Barrel", kind="Prop", tags=["Container", "Cover"])
    prof = [(0.93, 0.0), (1.02, 0.35), (1.12, 0.95), (1.16, 1.6), (1.12, 2.25), (1.02, 2.85), (0.93, 3.2),
            (0.84, 3.2), (0.84, 3.06)]
    k.add(lib, root, ls.lathe("bl_body", prof, segments=14, rot=(0, 0, 0.1)), "Wood", rgb=(126, 90, 58),
          collision="Hull")

    def r_at(z):
        for (ra, za), (rb, zb) in zip(prof[:6], prof[1:7]):
            if za <= z <= zb:
                return ra + (rb - ra) * (z - za) / (zb - za)
        return prof[0][0]
    hoops = []
    for (z0, z1) in ((0.26, 0.48), (0.86, 1.06), (2.14, 2.34), (2.72, 2.94)):
        rmax = max(r_at(z0), r_at(z1), r_at((z0 + z1) / 2))
        hoops.append(k.ring("bl_hoop", rmax - 0.04, rmax + 0.05, z0, z1, segs=14))
    k.add(lib, root, hoops, "DarkMetal", collide=False, smooth_angle=40)
    lib.finish(root)
    return root


def build_lantern(lib):
    random.seed(2601)
    root = lib.begin("Lantern", kind="Prop", tags=["Light"],
                     notes="Hanging lantern: hang from HangPoint; put a warm PointLight at Glow. No collision.")
    metal = [k.abox("ln_base", (-0.45, -0.45, 0.0), (0.45, 0.45, 0.16), 0.04),
             k.abox("ln_band", (-0.42, -0.42, 1.04), (0.42, 0.42, 1.16), 0.03)]
    for (sx, sy) in CORNERS:
        metal.append(k.abox("ln_rod", (sx * 0.37 - 0.05, sy * 0.37 - 0.05, 0.1), (sx * 0.37 + 0.05, sy * 0.37 + 0.05,
                                                                                    1.1)))
    metal.append(ls.lathe("ln_cap", [(0.54, 1.12), (0.54, 1.22), (0.17, 1.55), (0.17, 1.68)], segments=4,
                          rot=(0, 0, math.radians(45))))
    metal.append(ls.torus("ln_handle", major=0.24, minor=0.055, major_segments=12, minor_segments=4, loc=(0, 0, 1.9),
                          rot=(math.pi / 2, 0, 0)))
    k.add(lib, root, metal, "DarkMetal", collide=False, cast_shadow=False)
    k.add(lib, root, k.tube("ln_glass", (0, 0, 0.15), (0, 0, 1.05), 0.33, segs=6, phase=math.pi / 6), "Ember",
          collide=False, cast_shadow=False)
    lib.attach(root, "HangPoint", (0, 0, 2.19), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "Glow", (0, 0, 0.6), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


def build_well(lib):
    random.seed(2701)
    root = lib.begin("Well", kind="Prop", tags=["Water"],
                     notes="Stone well with windlass and bucket. Hull colliders make the shaft solid (no falling in).")
    k.add(lib, root, k.ring("wl_wall", 2.25, 3.0, 0.02, 2.62, segs=14, jit=0.06), "Stone", collision="Hull")
    k.add(lib, root, k.ring("wl_cope", 2.05, 3.25, 2.55, 2.95, segs=14, phase=0.22, jit=0.05), "Granite",
          rgb=(138, 132, 124), collision="Hull")
    k.add(lib, root, k.tube("wl_floor", (0, 0, 0.02), (0, 0, 0.12), 2.3, segs=14, phase=0.0), "DarkStone",
          collide=False)
    k.add(lib, root, k.tube("wl_water", (0, 0, 0.14), (0, 0, 0.75), 2.3, segs=14, phase=0.0), "WaterFill",
          collide=False, cast_shadow=False)
    posts = [k.beam("wl_post", (x, 0, 0.6), (x, 0, 6.75), 0.45, 0.45, up=(0, 1, 0), bev=0.05) for x in (-2.65, 2.65)]
    k.add(lib, root, posts, "Wood", rgb=(108, 80, 56), collision="PreciseConvexDecomposition")
    wood = [k.beam("wl_ridge", (-3.4, 0, 6.62), (3.4, 0, 6.62), 0.36, 0.4, bev=0.04),
            k.tube("wl_axle", (-2.95, 0, 4.6), (3.45, 0, 4.6), 0.14, segs=8, phase=0.0),
            k.tube("wl_drum", (-1.2, 0, 4.6), (1.2, 0, 4.6), 0.42, segs=10, phase=0.0)]
    wood.append(ls.lathe("wl_bucket", [(0.36, 2.25), (0.47, 3.0), (0.41, 3.0), (0.41, 2.36)], segments=10))
    k.add(lib, root, wood, "Wood", rgb=(122, 92, 62), collide=False)
    metal = [k.beam("wl_crank", (3.45, 0, 4.6), (3.45, 0, 5.45), 0.12, 0.14, up=(1, 0, 0)),
             k.tube("wl_grip", (3.45, 0, 5.4), (4.0, 0, 5.4), 0.07, segs=6),
             k.ring("wl_band", 0.43, 0.49, 2.72, 2.84, segs=10),
             ls.torus("wl_bail", major=0.45, minor=0.03, major_segments=10, minor_segments=4, loc=(0, 0, 3.0),
                      rot=(math.pi / 2, 0, 0))]
    k.add(lib, root, metal, "DarkMetal", collide=False)
    k.add(lib, root, [k.tube("wl_rope", (0, 0, 4.2), (0, 0, 3.42), 0.05, segs=5),
                      k.ring("wl_wrap", 0.4, 0.5, -0.55, 0.55, segs=10, axis="x", c=(0, 0, 4.6))], "Rope",
          collide=False)
    roof = []
    for side in (1, -1):
        roof.append(k.roof_slab("wl_roof", -3.5, 3.5, 2.5, 36.0, 6.85, 0.28, side=side, nu=2, nv=1))
    k.add(lib, root, roof, "Shingles", rgb=(92, 84, 76), collision="Hull")
    sh = []
    for side in (1, -1):
        sh += k.shake_roof("wl_shake", -3.55, 3.55, 2.5, 36.0, 6.85, 0.28, side=side, courses=2, lap=0.2, strip=0.1,
                           lift_deg=4.0, nu=2)
    k.add(lib, root, sh, "Shingles", rgb=(100, 90, 80), collide=False)
    lib.finish(root)
    return root


def build_woodpile(lib):
    random.seed(2801)
    root = lib.begin("Woodpile", kind="Prop", tags=["Camp", "Cover"],
                     notes="Split firewood stacked between stakes, end grain facing the front (+Y).")
    logs, ends, frame = [], [], []
    for y in (-0.8, 0.8):
        frame.append(k.tube("wp_rail", (-3.0, y, 0.2), (3.0, y, 0.2), 0.2, segs=6))
    for row, count in enumerate((7, 7, 6, 5)):
        z = 0.62 + row * 0.6
        span = 5.4 - row * 0.35
        for i in range(count):
            x = -span / 2 + (i + 0.5) * span / count + random.uniform(-0.06, 0.06)
            r = random.uniform(0.27, 0.34)
            L0, L1 = random.uniform(1.25, 1.5), random.uniform(1.25, 1.5)
            zz = z + random.uniform(-0.03, 0.03)
            ph = random.uniform(0, 6.3)
            logs.append(k.tube("wp_log", (x, -L0, zz), (x, L1, zz), r, r * 0.96, segs=5, phase=ph))
            ends.append(k.tube("wp_end", (x, L1 - 0.02, zz), (x, L1 + 0.04, zz), r * 0.82, segs=5, phase=ph))
    k.add(lib, root, logs, "Logs", rgb=(110, 84, 60), collision="Box")
    k.add(lib, root, ends, "Wood", rgb=(188, 150, 104), collide=False)
    for x in (-3.05, 3.05):
        for y in (-0.75, 0.75):
            frame.append(k.beam("wp_stake", (x, y, 0.02), (x + random.uniform(-0.1, 0.1), y, 3.1), 0.2, 0.2,
                                up=(0, 1, 0)))
    k.add(lib, root, frame, "Wood", rgb=(96, 74, 52), collide=False)
    lib.finish(root)
    return root


def build_sign(lib):
    random.seed(2901)
    root = lib.begin("Sign", kind="Prop", tags=["Sign"],
                     notes="Blank plank sign on a post (+ a blank arrow board). Put a SurfaceGui on the main board "
                           "front at SignFace.")
    post = [k.beam("sg_post", (0, 0, 0.0), (0, 0, 6.3), 0.5, 0.5, up=(0, 1, 0), bev=0.06),
            ls.lathe("sg_cap", [(0.37, 6.28), (0.08, 6.6)], segments=4, rot=(0, 0, math.radians(45)))]
    k.add(lib, root, post, "Wood", rgb=(100, 76, 54), collision="Box")
    boards = []
    for (z, dz) in ((4.95, 0.05), (5.85, -0.04)):
        boards.append(k.beam("sg_board", (-2.45, 0.37, z - dz), (2.4, 0.37, z + dz), 0.84, 0.22, up=(0, 1, 0), bev=0.04))
    boards.append(k.prism("sg_arrow", [(0.35, 3.1), (2.6, 3.1), (3.15, 3.45), (2.6, 3.8), (0.35, 3.8)], 0.26, 0.46,
                          axis="y"))
    k.add(lib, root, boards, "Planks", rgb=(140, 108, 74), collision="Box")
    stones = [k.rock("sg_stone", (x - 0.4, y - 0.35, 0.03), (x + 0.4, y + 0.35, 0.42), 0.1, 0.04,
                     rz=random.uniform(0, 3)) for (x, y) in ((0.55, 0.35), (-0.5, -0.4), (-0.35, 0.55))]
    k.add(lib, root, stones, "Stone", collide=False)
    lib.attach(root, "SignFace", (0, 0.49, 5.4), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root
