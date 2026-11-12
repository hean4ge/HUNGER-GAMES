"""
items_crates.py - SupplyCrate1/2/3 for the Items category (built by items.py).
Static props: base on z = 0, centred, front +Y. Hollow body (you can see inside when the lid opens).
Lid parts are named <Crate>_Lid (main planks) and <Crate>_Lid<Role> (fittings that ride on the lid),
tagged "Lid"; LidHinge sits on the back top edge, its look axis (+X) is the hinge axis.
"""
import math

import ls_common as ls
import items_kit as kit

W, DP = 4.0, 2.6
BODY_TOP = 1.94
POST, RAIL_H, FRAME_IN, BOARD_T, RECESS = 0.24, 0.22, 0.12, 0.1, 0.05
HW, HD = W / 2.0, DP / 2.0


def body_parts(prefix, boards_per_wall, post_chamfer=True):
    """(boards + floor objects, frame objects: corner posts + top/bottom rails)."""
    frame, boards = [], []
    for sx in (-1, 1):
        for sy in (-1, 1):
            loc = (sx * (HW - POST / 2), sy * (HD - POST / 2), BODY_TOP / 2)
            if post_chamfer:
                frame.append(kit.chamfer_box(prefix + "post", (POST, POST, BODY_TOP), 0.035, loc=loc))
            else:
                frame.append(kit.board(prefix + "post", (POST, POST, BODY_TOP), 0.035, axis=2, loc=loc))
    for z in (RAIL_H / 2, BODY_TOP - RAIL_H / 2):
        for sy in (-1, 1):
            frame.append(kit.board(prefix + "rail", (W - 2 * POST + 0.04, FRAME_IN, RAIL_H), 0.03, axis=0,
                                   loc=(0, sy * (HD - FRAME_IN / 2), z)))
        for sx in (-1, 1):
            frame.append(kit.board(prefix + "rail", (FRAME_IN, DP - 2 * POST + 0.04, RAIL_H), 0.03, axis=1,
                                   loc=(sx * (HW - FRAME_IN / 2), 0, z)))
    z_lo, z_hi = RAIL_H, BODY_TOP - RAIL_H
    bh = (z_hi - z_lo) / boards_per_wall
    ov = 0.008   # boards overlap slightly: no coincident vertices -> every shell stays manifold after clean()
    for i in range(boards_per_wall):
        zc = z_lo + bh * (i + 0.5)
        for sy in (-1, 1):
            boards.append(kit.board(prefix + "board", (W - 2 * POST + 0.04, BOARD_T, bh + ov), 0.03, axis=0,
                                    loc=(0, sy * (HD - RECESS - BOARD_T / 2), zc)))
        for sx in (-1, 1):
            boards.append(kit.board(prefix + "board", (BOARD_T, DP - 2 * POST + 0.04, bh + ov), 0.03, axis=1,
                                    loc=(sx * (HW - RECESS - BOARD_T / 2), 0, zc)))
    boards.append(kit.board(prefix + "floor", (W - 0.3, DP - 0.3, 0.08), 0.02, axis=0, loc=(0, 0, 0.12)))
    return boards, frame


def lid_parts(prefix, z0, cleat_h=0.14):
    """Three lid planks along X plus two cleats along Y on top."""
    parts = []
    bw = DP / 3.0
    for i in (-1, 0, 1):
        parts.append(kit.board(prefix + "lidboard", (W, bw + 0.008, 0.1), 0.028, axis=0, loc=(0, i * bw, z0 + 0.05)))
    for sx in (-1, 1):
        parts.append(kit.board(prefix + "cleat", (0.26, DP - 0.12, cleat_h), 0.03, axis=1,
                               loc=(sx * 1.55, 0, z0 + 0.1 + cleat_h / 2)))
    return parts


def _begin(lib, name, tier, notes):
    return lib.begin(name, kind="Crate", tags=["LootCrate", "Tier%d" % tier], notes=notes)


def _lid(lib, root, obj, role, rgb=None, suffix=""):
    obj = lib.add(root, obj, role, rgb=rgb, collide=True, collision="Box", tags=["Lid"])
    return lib.rename(root, obj, "%s_Lid%s" % (root.name, suffix))


def _lid_fitting(lib, root, obj, role, rgb=None):
    obj = lib.add(root, obj, role, rgb=rgb, collide=False, collision="Box", tags=["Lid"], cast_shadow=False)
    return lib.rename(root, obj, "%s_Lid%s" % (root.name, role))


def _attach(lib, root, lid_z0):
    lib.attach(root, "LidHinge", (0, -HD, lid_z0), look=(1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "Prompt", (0, HD + 0.15, 1.2), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "LootPoint", (0, 0, 0.2), look=(0, 1, 0), up=(0, 0, 1))


def crate1(lib):
    root = _begin(lib, "SupplyCrate1", 1, "Plain wooden crate 4 x 2.6 x 2.2 with diagonal braces. Lid = SupplyCrate1_Lid.")
    lid_z0 = 1.96
    boards, frame = body_parts("c1", 3)
    ang = math.atan2(BODY_TOP - 2 * RAIL_H, W - 2 * POST)
    length = math.hypot(BODY_TOP - 2 * RAIL_H, W - 2 * POST) - 0.06
    for sy in (-1, 1):
        frame.append(kit.board("c1brace", (length, 0.08, 0.2), 0.026, axis=0,
                               loc=(0, sy * (HD - 0.06), BODY_TOP / 2), rot=(0, -ang * sy, 0)))
    lib.add(root, kit.join(boards, "c1_boards"), "Planks", collide=True, collision="Box")
    lib.add(root, kit.join(frame, "c1_frame"), "Wood", rgb=(108, 78, 52), collide=True, collision="Box")
    _lid(lib, root, kit.join(lid_parts("c1", lid_z0), "c1_lid"), "DarkPlanks", rgb=(116, 86, 58))
    _attach(lib, root, lid_z0)
    lib.finish(root)


def crate2(lib):
    root = _begin(lib, "SupplyCrate2", 2, "Wooden crate with rope handles and metal corners. Lid = SupplyCrate2_Lid "
                                          "(+ SupplyCrate2_LidMetal corners riding on it).")
    lid_z0 = 1.96
    boards, frame = body_parts("c2", 2, post_chamfer=False)
    lib.add(root, kit.join(boards, "c2_boards"), "Planks", rgb=(142, 108, 72), collide=True, collision="Box")
    lib.add(root, kit.join(frame, "c2_frame"), "Wood", rgb=(112, 82, 54), collide=True, collision="Box")
    metal, ropes = [], []
    for sx in (-1, 1):
        for sy in (-1, 1):
            metal.append(kit.board("c2corner", (0.36, 0.36, 0.32), 0.04, axis=2,
                                   loc=(sx * (HW - 0.16), sy * (HD - 0.16), 0.16)))
        path = [(sx * (HW - 0.04), -0.42, 1.4), (sx * (HW + 0.06), -0.42, 1.38), (sx * (HW + 0.12), -0.3, 1.16),
                (sx * (HW + 0.14), 0.0, 1.06), (sx * (HW + 0.12), 0.3, 1.16), (sx * (HW + 0.06), 0.42, 1.38),
                (sx * (HW - 0.04), 0.42, 1.4)]
        ropes.append(kit.sweep("c2rope", path, kit.circle(6, 0.045)))
        for y in (-0.42, 0.42):
            metal.append(ls.cube("c2grommet", size=(0.09, 0.2, 0.2), loc=(sx * (HW - 0.025), y, 1.4)))
    metal.append(kit.board("c2plate", (0.62, 0.03, 0.26), 0.012, axis=0, loc=(0, HD - RECESS + 0.01, 1.345)))
    lib.add(root, kit.join(metal, "c2_metal"), "Metal", collide=False, collision="Box")
    lib.add(root, kit.join(ropes, "c2_ropes"), "Rope", collide=False, collision="Box", smooth_angle=60, cast_shadow=False)
    _lid(lib, root, kit.join(lid_parts("c2", lid_z0), "c2_lid"), "DarkPlanks")
    caps = [kit.board("c2lidcorner", (0.36, 0.36, 0.3), 0.04, axis=2,
                      loc=(sx * (HW - 0.16), sy * (HD - 0.16), lid_z0 + 0.145)) for sx in (-1, 1) for sy in (-1, 1)]
    _lid_fitting(lib, root, kit.join(caps, "c2_lidmetal"), "Metal")
    _attach(lib, root, lid_z0)
    lib.finish(root)


def crate3(lib):
    root = _begin(lib, "SupplyCrate3", 3, "Dark reinforced crate, iron bands, faint ember glow leaking from the lid seam. "
                                          "Lid = SupplyCrate3_Lid (+ SupplyCrate3_LidDarkMetal bands and hasp).")
    lid_z0 = 1.99
    boards, frame = body_parts("c3", 2, post_chamfer=False)
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.append(kit.board("c3strap", (0.2, 0.06, BODY_TOP - 0.02), 0.015, axis=2,
                                   loc=(sx * 1.0, sy * (HD - 0.035), BODY_TOP / 2)))
    frame.append(kit.board("c3lock", (0.26, 0.14, 0.22), 0.03, axis=2, loc=(0, HD + 0.04, 1.59)))
    for sx in (-1, 1):
        frame.append(kit.rod("c3hinge", 0.06, 0.34, 8, (sx * 1.0, -HD - 0.01, BODY_TOP - 0.02), "X"))
    lib.add(root, kit.join(boards, "c3_boards"), "DarkPlanks", rgb=(82, 60, 44), collide=True, collision="Box")
    lib.add(root, kit.join(frame, "c3_frame"), "DarkMetal", rgb=(58, 60, 66), collide=True, collision="Box")
    seam = kit.rect_frame("c3_seam", (W - 0.06, DP - 0.06), (W - 0.4, DP - 0.4), BODY_TOP - 0.005, BODY_TOP + 0.045)
    lib.add(root, seam, "Ember", rgb=(236, 112, 44), collide=False, collision="Box", cast_shadow=False)
    _lid(lib, root, kit.join(lid_parts("c3", lid_z0), "c3_lid"), "Planks", rgb=(70, 54, 40))
    fittings = []
    for sx in (-1, 1):
        fittings.append(kit.board("c3lidband", (0.2, DP + 0.02, 0.05), 0.012, axis=1, loc=(sx * 1.0, 0, lid_z0 + 0.115)))
        for sy in (-1, 1):
            fittings.append(kit.board("c3liddrop", (0.2, 0.05, 0.14), 0.012, axis=0,
                                      loc=(sx * 1.0, sy * (HD + 0.01), lid_z0 + 0.07)))
    fittings.append(kit.board("c3hasp", (0.2, 0.05, 0.35), 0.015, axis=2, loc=(0, HD + 0.03, lid_z0 - 0.105)))
    _lid_fitting(lib, root, kit.join(fittings, "c3_lidmetal"), "DarkMetal", rgb=(58, 60, 66))
    _attach(lib, root, lid_z0)
    lib.finish(root)


BUILDERS = [crate1, crate2, crate3]
