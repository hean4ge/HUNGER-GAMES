"""
ir_crates.py - SupplyCrate1/2/3 for the ItemsReal set (built by items_real.py), realistic and textured.
Static props: base centre on z = 0, front +Y, 4.0 x 2.6 body, lid on top (v1 gameplay dimensions: they fit the
Spire's 5.4 x 3.3 x 4.8 alcoves with room for the lid to open). Hollow body, so the inside shows when the lid opens.
Lid parts keep the v1 names: <Crate>_Lid (planks) and <Crate>_Lid<Role> (fittings riding on it), tagged "Lid";
LidHinge on the back top edge (look = hinge axis +X), Prompt in front, LootPoint inside on the floor.
Tiers read apart at a glance:
  1  plain crate of weathered, silvered pine: nailed boards, diagonal braces, leather strap hinges
  2  sturdier warm-pine crate: riveted steel corner caps, a tag plate, rope handles through iron eyes
  3  dark-stained, iron-banded chest: iron corners, straps, hinges and hasp, the Spire 'Cleft' sigil burnt into the
     lid and a faint ember glow leaking from the lid seam (separate SupplyCrate3_Ember part, Neon)
"""
import math
import random

from mathutils import Matrix, Vector

import ir_geo as g
import items_kit as kit
import tex_items_mats as M
from tex_items import C

V = Vector
D = math.radians
W, DP = 4.0, 2.6
BODY_TOP = 1.94
POST, RAIL_H, FRAME_IN, BOARD_T, RECESS = 0.24, 0.22, 0.12, 0.1, 0.05
HW, HD = W / 2.0, DP / 2.0
SET_A, SET_B = "IR_CratesA", "IR_CratesB"
RNG = random.Random(2207)


def _uvw_crate(c, n):
    """Texel weights per face: the underside gets almost nothing, faces inside the box less than outside."""
    if n.z < -0.7 and c.z < 0.3:
        return 0.12
    inside = abs(c.x) < HW - RECESS - BOARD_T + 0.01 and abs(c.y) < HD - RECESS - BOARD_T + 0.01 and c.z < BODY_TOP
    return 0.55 if inside else 1.0


def board(name, size, axis, loc, rot=(0, 0, 0), chamfer=0.014, jitter=True):
    """Plank / rail: 8-sided prism along `axis`, with a little hand-built irregularity."""
    if jitter:
        rot = (rot[0] + RNG.uniform(-0.003, 0.003), rot[1] + RNG.uniform(-0.003, 0.003),
               rot[2] + RNG.uniform(-0.003, 0.003))
        loc = (loc[0] + RNG.uniform(-0.003, 0.003), loc[1] + RNG.uniform(-0.002, 0.002),
               loc[2] + RNG.uniform(-0.003, 0.003))
    ob = kit.board(name, size, chamfer, axis=axis, loc=loc, rot=rot)
    return g.tx.bake_xform(ob)          # keep the location/rotation kit.board set on the object


def wall_rows(n, z_lo, z_hi, rng, gap=0.012):
    """n board rows between z_lo and z_hi with slightly uneven widths and small gaps."""
    w = [1.0 + rng.uniform(-0.12, 0.12) for _ in range(n)]
    tot = sum(w)
    span = z_hi - z_lo - gap * (n - 1)
    rows, z = [], z_lo
    for k in range(n):
        h = span * w[k] / tot
        rows.append((z + h / 2, h))
        z += h + gap
    return rows


def body(prefix, n_rows, rng):
    """(boards, frame, nails): wall boards + floor, corner posts + top/bottom rails, nail head positions."""
    boards, frame, nails = [], [], []
    for sx in (-1, 1):
        for sy in (-1, 1):
            loc = (sx * (HW - POST / 2), sy * (HD - POST / 2), BODY_TOP / 2)
            frame.append(board(prefix + "post", (POST, POST, BODY_TOP), 2, loc, chamfer=0.03))
    for z in (RAIL_H / 2, BODY_TOP - RAIL_H / 2):
        for sy in (-1, 1):
            frame.append(board(prefix + "rail", (W - 2 * POST + 0.04, FRAME_IN, RAIL_H), 0,
                               (0, sy * (HD - FRAME_IN / 2), z), chamfer=0.022))
        for sx in (-1, 1):
            frame.append(board(prefix + "rail", (FRAME_IN, DP - 2 * POST + 0.04, RAIL_H), 1,
                               (sx * (HW - FRAME_IN / 2), 0, z), chamfer=0.022))
    for (zc, h) in wall_rows(n_rows, RAIL_H + 0.006, BODY_TOP - RAIL_H - 0.006, rng):
        for sy in (-1, 1):
            yo = sy * (HD - RECESS - BOARD_T / 2)
            boards.append(board(prefix + "board", (W - 2 * POST + 0.04, BOARD_T, h), 0, (0, yo, zc)))
            for sx in (-1, 1):
                for dz in (-0.28, 0.28):
                    nails.append((sx * (HW - POST - 0.07), sy * (HD - RECESS), zc + dz * h))
        for sx in (-1, 1):
            xo = sx * (HW - RECESS - BOARD_T / 2)
            boards.append(board(prefix + "board", (BOARD_T, DP - 2 * POST + 0.04, h), 1, (xo, 0, zc)))
            for sy in (-1, 1):
                for dz in (-0.28, 0.28):
                    nails.append((sx * (HW - RECESS), sy * (HD - POST - 0.07), zc + dz * h))
    # rails nailed through into the posts
    for z in (RAIL_H / 2, BODY_TOP - RAIL_H / 2):
        for sx in (-1, 1):
            for sy in (-1, 1):
                nails.append((sx * (HW - POST - 0.06), sy * HD, z))
                nails.append((sx * HW, sy * (HD - POST - 0.06), z))
    boards.append(board(prefix + "floor", (W - 0.3, DP - 0.3, 0.08), 0, (0, 0, 0.12), chamfer=0.01, jitter=False))
    return boards, frame, nails


def lid(prefix, z0, cleat_h=0.14, n=3, rng=None):
    """Lid planks along X plus two cleats along Y on top; returns (pieces, nails)."""
    parts, nails = [], []
    gap = 0.01
    bw = (DP - gap * (n - 1)) / n
    for i in range(n):
        yc = -HD + bw / 2 + i * (bw + gap)
        parts.append(board(prefix + "lidboard", (W, bw, 0.1), 0, (0, yc, z0 + 0.05), chamfer=0.016))
        for sx in (-1, 1):
            for dy in (-0.25, 0.25):
                nails.append((sx * 1.55, yc + dy * bw, z0 + 0.1 + cleat_h))
    for sx in (-1, 1):
        parts.append(board(prefix + "cleat", (0.26, DP - 0.12, cleat_h), 1, (sx * 1.55, 0, z0 + 0.1 + cleat_h / 2),
                           chamfer=0.02))
    return parts, nails


def _principal(o):
    """Centre and long axis (PCA) of a board's vertices: the grain runs along the board even when it is rotated."""
    import numpy as np
    co = np.array([tuple(v.co) for v in o.data.vertices])
    c = co.mean(axis=0)
    w, vec = np.linalg.eigh((co - c).T @ (co - c))
    ax = vec[:, int(np.argmax(w))]
    if ax[int(np.argmax(np.abs(ax)))] < 0:
        ax = -ax
    return tuple(c), tuple(float(x) for x in ax)


def _plank_pieces(objs, mid=M.PLANK, alt=0.0):
    for o in objs:
        g.tx.bake_xform(o)
        c, axis = _principal(o)
        up = (0, 0, 1) if abs(axis[2]) < 0.9 else (1, 0, 0)
        g.piece(o, mid, axis=axis, origin=c, up=up, bevr=0.014,
                a={"a0": alt, "a1": abs(axis[0]), "a2": abs(axis[1]), "a3": abs(axis[2])}, uvw=_uvw_crate, shade=None)
    return objs


def _attach(lib, root, lid_z0):
    lib.attach(root, "LidHinge", (0, -HD, lid_z0), look=(1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "Prompt", (0, HD + 0.15, 1.2), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "LootPoint", (0, 0, 0.2), look=(0, 1, 0), up=(0, 0, 1))


def _lid_open_pose(lib, root, lid_z0, angle=100.0):
    """During the texture bake the lid stands open, so the interior gets the light it gets when it is opened."""
    def pose(open_):
        e = lib._entry(root)
        for p, o in zip(e["parts"], e["objs"]):
            if "Lid" in p["tags"]:
                if open_:
                    piv = V((0, -HD, lid_z0))
                    o.matrix_world = (root.matrix_world @ Matrix.Translation(piv)
                                      @ Matrix.Rotation(D(angle), 4, "X") @ Matrix.Translation(-piv))
                else:
                    o.matrix_world = root.matrix_world.copy()
    lib.bake_pose[root.name] = pose


def _lid(lib, root, pieces, role, set_name, name_suffix="", fitting=False, weight=1.0, cast_shadow=True):
    name = "%s_Lid%s" % (root.name, name_suffix)
    if fitting:
        return lib.part(root, pieces, role, set_name, name=name, collide=False, tags=["Lid"], weight=weight,
                        cast_shadow=False)
    return lib.part(root, pieces, role, set_name, name=name, collide=True, collision="Box", tags=["Lid"],
                    weight=weight, cast_shadow=cast_shadow)


def _strap_hinges(prefix, lid_z0, xs=(-1.0, 1.0)):
    """Leather strap hinges over the back top edge: (body halves, lid halves)."""
    import items_kit as k
    body_p, lid_p = [], []
    for i, x in enumerate(xs):
        b = g.sweep(prefix + "hinge_b%d" % i, [(x, -HD - 0.006, BODY_TOP - 0.2), (x, -HD - 0.009, BODY_TOP - 0.02),
                                               (x, -HD - 0.008, lid_z0 - 0.004)], k.rrect(0.16, 0.012, 0.004),
                    up=(1, 0, 0))
        t = g.sweep(prefix + "hinge_t%d" % i, [(x, -HD - 0.008, lid_z0 + 0.002), (x, -HD - 0.006, lid_z0 + 0.09),
                                               (x, -HD + 0.02, lid_z0 + 0.106), (x, -HD + 0.3, lid_z0 + 0.106)],
                    k.rrect(0.16, 0.012, 0.004), up=(1, 0, 0))
        body_p.append(b)
        lid_p.append(t)
    return body_p, lid_p


# =============================================================================================== tier 1
def crate1(lib):
    root = lib.begin("SupplyCrate1", "Crate", tags=["LootCrate", "Tier1"],
                     notes="Tier 1: plain crate of weathered, sun-silvered pine boards (raised grain, checks, rusty nail "
                           "stains, grime and a little moss low down), diagonal braces, leather strap hinges. "
                           "Lid = SupplyCrate1_Lid (opens ~100 degrees about LidHinge).")
    rng = random.Random(11)
    lid_z0 = 1.96
    boards, frame, nails = body("c1", 3, rng)
    ang = math.atan2(BODY_TOP - 2 * RAIL_H, W - 2 * POST)
    length = math.hypot(BODY_TOP - 2 * RAIL_H, W - 2 * POST) - 0.06
    for sy in (-1, 1):
        frame.append(board("c1brace", (length, 0.07, 0.19), 0, (0, sy * (HD - RECESS + 0.035), BODY_TOP / 2),
                           rot=(0, -ang * sy, 0), chamfer=0.02))
        for t in (-0.42, 0.0, 0.42):
            nails.append((t * length * math.cos(ang), sy * (HD - RECESS + 0.07), BODY_TOP / 2 + t * length * math.sin(ang) * sy))
    lids, lnails = lid("c1", lid_z0, rng=rng)
    hb, ht = _strap_hinges("c1", lid_z0)
    _plank_pieces(boards)
    _plank_pieces(frame, alt=1.0)
    _plank_pieces(lids)
    for o in hb + ht:
        g.piece(o, M.LEATHER, axis=(0, 0, 1), bevr=0.004, shade=40)
    lib.part(root, boards, "Planks", SET_A, collide=True, collision="Box", weight=1.0)
    lib.part(root, frame + hb, "Wood", SET_A, collide=True, collision="Box", weight=1.0)
    _lid(lib, root, lids + ht, "DarkPlanks", SET_A)
    lib.params(root, M.PLANK, dict(silver=C(148, 142, 130), brown=C(118, 92, 66), weather=0.85, cracks=0.9,
                                   moss=0.45, nails=nails + lnails, alt=(0.9, 0.86, 0.82)))
    lib.params(root, M.LEATHER, dict(color=C(78, 52, 36), crease=0.7, scuff=0.9, dirt=0.8))
    _attach(lib, root, lid_z0)
    _lid_open_pose(lib, root, lid_z0)
    lib.finish(root)


# =============================================================================================== tier 2
def _corner_cap(name, sx, sy, z0, h, top):
    """Bent-steel corner cap over one vertical edge: two side plates + an end plate (bottom or top)."""
    t = 0.012
    L = 0.34
    pieces = [g.box(name + "a", (L, t, h), loc=(sx * (HW - L / 2 + 0.006), sy * (HD + t / 2 - 0.002), z0 + h / 2)),
              g.box(name + "b", (t, L, h), loc=(sx * (HW + t / 2 - 0.002), sy * (HD - L / 2 + 0.006), z0 + h / 2))]
    ez = z0 + h - t / 2 + 0.002 if top else z0 + t / 2 - 0.002
    pieces.append(g.box(name + "c", (L, L, t), loc=(sx * (HW - L / 2 + 0.006), sy * (HD - L / 2 + 0.006), ez)))
    rivets = []
    for k in (0.11, 0.25):
        for zz in (z0 + h * 0.3, z0 + h * 0.7):
            rivets.append((sx * (HW - k), sy * (HD + t), zz))
            rivets.append((sx * (HW + t), sy * (HD - k), zz))
    return pieces, rivets


def crate2(lib):
    root = lib.begin("SupplyCrate2", "Crate", tags=["LootCrate", "Tier2"],
                     notes="Tier 2: sturdier crate of warmer, less weathered pine with riveted bent-steel corner caps, "
                           "a riveted tag plate, laid-rope handles through iron eyes on both ends. Lid = SupplyCrate2_Lid "
                           "(+ SupplyCrate2_LidMetal corner caps riding on it).")
    rng = random.Random(22)
    lid_z0 = 1.96
    boards, frame, nails = body("c2", 2, rng)
    metal, rivets = [], []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pcs, rv = _corner_cap("c2corner", sx, sy, 0.0, 0.32, top=False)
            metal += pcs
            rivets += rv
    ropes = []
    for sx in (-1, 1):
        path = [(sx * (HW - RECESS - 0.04), -0.42, 1.42), (sx * (HW + 0.03), -0.42, 1.42),
                (sx * (HW + 0.09), -0.4, 1.36), (sx * (HW + 0.125), -0.3, 1.22), (sx * (HW + 0.135), 0.0, 1.12),
                (sx * (HW + 0.125), 0.3, 1.22), (sx * (HW + 0.09), 0.4, 1.36), (sx * (HW + 0.03), 0.42, 1.42),
                (sx * (HW - RECESS - 0.04), 0.42, 1.42)]
        rope = g.sweep("c2rope", g.smooth_path(path, 16), kit.circle(8, 0.036), up=(0, 0, 1))
        ropes.append(rope)
        for y in (-0.42, 0.42):
            eye = g.torus("c2eye", 0.056, 0.015, segs=10, minor_segs=5, center=(sx * (HW - RECESS + 0.028), y, 1.42),
                          axis=(1, 0, 0))
            plate = g.box("c2eyeplate", (0.014, 0.17, 0.17), loc=(sx * (HW - RECESS + 0.006), y, 1.42))
            metal += [eye, plate]
            rivets += [(sx * (HW - RECESS + 0.013), y + dy, 1.42 + dz) for dy in (-0.06, 0.06) for dz in (-0.06, 0.06)]
    plate = g.cbox("c2plate", (0.62, 0.012, 0.26), 0.004, loc=(0, HD - RECESS + 0.006, 1.345))
    metal.append(plate)
    rivets += [(sx * 0.27, HD - RECESS + 0.012, 1.345 + sz * 0.09) for sx in (-1, 1) for sz in (-1, 1)]
    lids, lnails = lid("c2", lid_z0, rng=rng)
    caps = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pcs, rv = _corner_cap("c2lidcorner", sx, sy, lid_z0 - 0.004, 0.115, top=True)
            caps += pcs
            rivets += rv
    _plank_pieces(boards)
    _plank_pieces(frame, alt=1.0)
    _plank_pieces(lids)
    for o in metal + caps:
        g.piece(o, M.IRON, bevr=0.004, shade=60 if (o.name.startswith("c2eye") and "plate" not in o.name) else None)
    for o in ropes:
        g.piece(o, M.CORD, bevr=0.006, seed_offset=False, shade=60)
    lib.part(root, boards, "Planks", SET_A, collide=True, collision="Box", weight=1.0)
    lib.part(root, frame, "Wood", SET_A, collide=True, collision="Box", weight=1.0)
    lib.part(root, metal, "Metal", SET_A, weight=1.2)
    lib.part(root, ropes, "Rope", SET_A, weight=1.2, cast_shadow=False)
    _lid(lib, root, lids, "DarkPlanks", SET_A)
    _lid(lib, root, caps, "Metal", SET_A, name_suffix="Metal", fitting=True, weight=1.2)
    lib.params(root, M.PLANK, dict(silver=C(150, 136, 114), brown=C(150, 112, 72), weather=0.35, cracks=0.55,
                                   moss=0.15, nails=nails + lnails, alt=(0.82, 0.78, 0.74)))
    lib.params(root, M.IRON, dict(rust=0.45, edge_wear=0.7, hammer=40.0, rivets=rivets, rivet_r=0.016, streaks=0.4))
    lib.params(root, M.CORD, dict(color=C(150, 124, 86), turns=12.0, around=3, strands=3, rope=True, dirt=0.6,
                                  grime=0.5))
    _attach(lib, root, lid_z0)
    _lid_open_pose(lib, root, lid_z0)
    lib.finish(root)


# =============================================================================================== tier 3
def crate3(lib):
    root = lib.begin("SupplyCrate3", "Crate", tags=["LootCrate", "Tier3"],
                     notes="Tier 3: dark-stained, iron-banded chest: blackened forged-iron corner angles, straps, lock "
                           "plate, hasp and strap hinges (pitted, rust in the pits, worn bright on the edges), the arena's "
                           "Spire 'Cleft' sigil burnt into the lid, a faint ember glow leaking from the lid seam "
                           "(SupplyCrate3_Ember, separate Neon part). Lid = SupplyCrate3_Lid (+ SupplyCrate3_LidDarkMetal).")
    rng = random.Random(33)
    lid_z0 = 1.99
    boards, frame, nails = body("c3", 2, rng)
    iron, rivets = [], []
    t = 0.016
    for sx in (-1, 1):
        for sy in (-1, 1):
            # forged corner angles running the full height
            iron.append(g.cbox("c3anglea", (0.2, t, BODY_TOP - 0.02), 0.005,
                               loc=(sx * (HW - 0.1 + 0.004), sy * (HD + t / 2 - 0.002), BODY_TOP / 2)))
            iron.append(g.cbox("c3angleb", (t, 0.2, BODY_TOP - 0.02), 0.005,
                               loc=(sx * (HW + t / 2 - 0.002), sy * (HD - 0.1 + 0.004), BODY_TOP / 2)))
            for zz in (0.18, 0.7, 1.24, 1.76):
                rivets += [(sx * (HW - 0.1), sy * (HD + t), zz), (sx * (HW + t), sy * (HD - 0.1), zz)]
            # vertical straps on the front and back, bent over the proud rails
            yr, yb = sy * (HD + t / 2 - 0.002), sy * (HD - RECESS + t / 2 + 0.002)
            spath = [(sx * 1.0, yr, 0.02), (sx * 1.0, yr, RAIL_H - 0.03), (sx * 1.0, yb, RAIL_H + 0.03),
                     (sx * 1.0, yb, BODY_TOP - RAIL_H - 0.03), (sx * 1.0, yr, BODY_TOP - RAIL_H + 0.03),
                     (sx * 1.0, yr, BODY_TOP - 0.02)]
            iron.append(g.sweep("c3strap", spath, kit.rrect(0.18, t, 0.005), up=(1, 0, 0)))
            for zz in (0.3, 0.97, 1.64):
                rivets.append((sx * 1.0, sy * (HD - RECESS + t + 0.002), zz))
    lock = g.cbox("c3lock", (0.28, 0.035, 0.24), 0.008, loc=(0, HD - RECESS + 0.02, 1.62))
    iron.append(lock)
    rivets += [(sx * 0.105, HD - RECESS + 0.038, 1.62 + sz * 0.085) for sx in (-1, 1) for sz in (-1, 1)]
    keyhole = g.cyl("c3keyhole", 0.024, -0.004, 0.004, segs=10, loc=(0, HD - RECESS + 0.038, 1.6), rot=(D(90), 0, 0))
    iron.append(keyhole)
    for sx in (-1, 1):
        iron.append(g.cbox("c3hingeb", (0.17, t, 0.19), 0.005, loc=(sx * 1.0, -HD - t / 2 - 0.016, BODY_TOP - 0.11)))
        rivets += [(sx * 1.0, -HD - t - 0.016, BODY_TOP - z) for z in (0.06, 0.16)]
        knuckle = g.cyl("c3knuckle", 0.03, -0.085, 0.085, segs=10, loc=(sx * 1.0, -HD - 0.03, BODY_TOP + 0.01),
                        rot=(0, D(90), 0))
        iron.append(knuckle)
    # faint ember seam: a thin glowing strip on the rail tops, set back 8 cm, seen only through the lid gap
    seam = kit.rect_frame("c3_seam", (W - 0.16, DP - 0.16), (W - 0.29, DP - 0.29), BODY_TOP + 0.01, BODY_TOP + 0.032)
    lids, lnails = lid("c3", lid_z0, rng=rng)
    fittings = []
    for sx in (-1, 1):
        fittings.append(g.cbox("c3lidband", (0.18, DP + 0.03, t), 0.005, loc=(sx * 1.0, 0, lid_z0 + 0.1 + t / 2 - 0.002)))
        for sy in (-1, 1):
            fittings.append(g.cbox("c3liddrop", (0.18, t, 0.12), 0.005,
                                   loc=(sx * 1.0, sy * (HD + t / 2 - 0.001), lid_z0 + 0.052)))
            rivets += [(sx * 1.0, sy * (HD + t - 0.001), lid_z0 + 0.05)]
        for yy in (-0.85, 0.0, 0.85):
            rivets.append((sx * 1.0, yy, lid_z0 + 0.1 + t))
    hasp = g.cbox("c3hasp", (0.13, t, 0.42), 0.006, loc=(0, HD + t / 2 + 0.008, lid_z0 - 0.11))
    staple = g.torus("c3staple", 0.03, 0.009, segs=10, minor_segs=5, center=(0, HD + 0.03, lid_z0 - 0.28), axis=(0, 0, 1))
    fittings.append(hasp)
    iron.append(staple)
    rivets += [(0, HD + t + 0.008, lid_z0 + 0.05), (0, HD + t + 0.008, lid_z0 - 0.06)]
    _plank_pieces(boards)
    _plank_pieces(frame, alt=1.0)
    _plank_pieces(lids)
    for o in iron + fittings:
        g.piece(o, M.IRON, bevr=0.005, shade=50 if o.name.startswith(("c3knuckle", "c3keyhole", "c3staple")) else None)
    g.piece(seam, M.EMBER, bevr=0.002)
    lib.part(root, boards + frame, "DarkPlanks", SET_B, collide=True, collision="Box", weight=1.0)
    lib.part(root, iron, "DarkMetal", SET_B, collide=True, collision="Box", weight=1.15)
    lib.part(root, [seam], "Ember", None, collide=False, cast_shadow=False, rgb=(236, 112, 44))
    _lid(lib, root, lids, "Planks", SET_B)
    _lid(lib, root, fittings, "DarkMetal", SET_B, name_suffix="DarkMetal", fitting=True, weight=1.15)
    lib.params(root, M.PLANK, dict(silver=C(86, 74, 62), brown=C(64, 46, 34), groove=C(34, 28, 24), weather=0.3,
                                   cracks=0.7, moss=0.1, nails=nails + lnails, alt=(0.78, 0.74, 0.7),
                                   brand=dict(center=(0.0, -0.05, lid_z0 + 0.1), size=1.0)))
    lib.params(root, M.IRON, dict(rust=0.5, edge_wear=0.9, hammer=30.0, rivets=rivets, rivet_r=0.02, streaks=0.5))
    _attach(lib, root, lid_z0)
    _lid_open_pose(lib, root, lid_z0)
    lib.finish(root)


import ir_armor  # noqa: E402

BUILDERS_A = [crate1, crate2]
BUILDERS_B = [crate3] + ir_armor.BUILDERS
