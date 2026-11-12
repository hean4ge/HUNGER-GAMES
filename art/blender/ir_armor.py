"""
ir_armor.py - leather_vest and padded_armor for the ItemsReal set (built through ir_crates.BUILDERS_B, texture set
IR_CratesB). The torso shells reuse the v1 superellipse body (items_armor: same outer size, same ~2.05 x 1.15
cavity for a blocky R15 torso) and the v1 grip/attachment maths, so Grip (back of the collar, the vest hangs below)
and Torso (cavity centre, look = vest front) sit exactly where they did in v1.
"""
import math

import items_armor as arm
import items_kit as kit
import ir_geo as g
import tex_items_mats as M
from items_kit import curve, lerp
from tex_items import C

SET = "IR_CratesB"
TAU = 2.0 * math.pi


def _grip_and_torso(lib, root, grip_body):
    lib.attach(root, "Grip", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "Torso", (0, -grip_body[1], 1.15 - grip_body[2]), look=(0, 1, 0), up=(0, 0, 1))


def _shift(objs, off):
    for o in objs:
        kit.shift(o, off)
    return objs


def leather_vest(lib):
    root = lib.begin("leather_vest", "Armor", tags=["Armor", "Wearable"], held=True,
                     notes="Oil-tanned leather vest: pebbled grain, creases at the arm holes and waist, scuffed lighter "
                           "edges, darker hand-worn trim at the hem and placket, three brass toggles, laced sides. "
                           "Grip = back of the collar at origin (vest hangs below); 'Torso' = cavity centre for wearing.")
    T_V1 = 0.08                       # v1 shell thickness: keeps the v1 grip / Torso positions exactly
    T = 0.05                          # thinner, more leather-like shell (outer surface unchanged)
    A, B, Z_ARM, Z_TOP = arm.A, arm.B, arm.Z_ARM, arm.Z_TOP
    arm_fn = lambda z: curve([(Z_ARM, 0.02), (1.75, 0.3), (2.0, 0.44), (Z_TOP, 0.5)], z)
    neck = lambda z: curve([(Z_ARM, 1.5), (1.8, 1.32), (2.05, 1.14), (Z_TOP, 1.05)], z)
    grip_body = (0.0, -(B(Z_TOP) - T_V1 / 2), Z_TOP)
    off = (-grip_body[0], -grip_body[1], -grip_body[2])
    panels = [arm.torso_panel("lv_band", 0.0, Z_ARM, 32, 3, T, A, B),
              arm.torso_panel("lv_front_r", Z_ARM, Z_TOP, 7, 4, T, A, B, arm_fn, neck),
              arm.torso_panel("lv_front_l", Z_ARM, Z_TOP, 7, 4, T, A, B,
                              lambda z: math.pi - neck(z), lambda z: math.pi - arm_fn(z)),
              arm.torso_panel("lv_back", Z_ARM, Z_TOP, 14, 4, T, A, B,
                              lambda z: math.pi + arm_fn(z), lambda z: TAU - arm_fn(z)),
              arm.shoulder_bridge("lv_bridge_r", arm_fn(Z_TOP), neck(Z_TOP), T, A, B),
              arm.shoulder_bridge("lv_bridge_l", math.pi - arm_fn(Z_TOP), math.pi - neck(Z_TOP), T, A, B)]
    trim = [arm.torso_panel("lv_hem", -0.012, 0.1, 28, 1, 0.07, lambda z: A(z) + 0.012, lambda z: B(z) + 0.012),
            kit.sweep("lv_placket", [(0, B(z) + 0.01, z) for z in (-0.005, 0.5, 1.0, Z_ARM + 0.02)],
                      kit.rrect(0.13, 0.026, 0.008))]
    toggles = [kit.rod("lv_toggle%d" % i, 0.024, 0.12, 8, (0, B(z) + 0.034, z), "X") for i, z in
               enumerate((0.35, 0.8, 1.25))]
    loops = [g.torus("lv_loop%d" % i, 0.03, 0.0065, segs=10, minor_segs=5, center=(0.045, B(z) + 0.03, z),
                     axis=(0, 1, 0)) for i, z in enumerate((0.35, 0.8, 1.25))]
    laces = []
    for sx in (1, -1):
        pts = [(sx * (A(z) + 0.012), (0.07 if i % 2 == 0 else -0.07), z)
               for i, z in enumerate([lerp(0.25, 1.3, k / 7.0) for k in range(8)])]
        laces.append(g.sweep("lv_lace", pts, kit.circle(5, 0.012), up=(0, 0, 1)))
    allp = panels + trim + toggles + loops + laces
    _shift(allp, off)
    for o in panels:
        g.piece(o, M.LEATHER, axis=(0, 0, 1), bevr=0.014, shade=50)
    for o in trim:
        g.piece(o, M.LEATHER, axis=(0, 0, 1), bevr=0.01, a={"a3": 1.0}, shade=50)
    for o in toggles:
        g.piece(o, M.BRASS, axis=(1, 0, 0), bevr=0.004, shade=50)
    for o in loops + laces:
        g.piece(o, M.CORD, bevr=0.003, shade=60)
    lib.part(root, panels + trim, "Leather", SET, weight=1.0)
    lib.part(root, toggles, "Brass", SET, weight=1.2, cast_shadow=False)
    lib.part(root, loops + laces, "Rope", SET, weight=1.0, cast_shadow=False)
    lib.params(root, M.LEATHER, dict(color=C(112, 72, 44), trim=C(62, 40, 28), dark=C(62, 40, 27), grain=110.0,
                                     crease=0.7, crease_f=5.0, crease_dir=(1.0, 1.0, 3.2), crease_dark=0.28,
                                     mottle=0.22, scuff=0.85, polish=0.4, dirt=0.6, rough=0.6))
    lib.params(root, M.BRASS, dict(tarnish=0.9, verdigris=0.35))
    lib.params(root, M.CORD, dict(color=C(92, 66, 44), turns=50.0, strands=2, dirt=0.5))
    _grip_and_torso(lib, root, grip_body)
    lib.finish(root)


def padded_armor(lib):
    root = lib.begin("padded_armor", "Armor", tags=["Armor", "Wearable"], held=True,
                     notes="Quilted linen gambeson (vertical stitched channels, stuffed and puffy, faded and grubby), "
                           "leather standing collar, placket and hem, three leather straps with brass buckles. Grip = back "
                           "of the collar at origin; 'Torso' = cavity centre for wearing.")
    A, B, P, Z_ARM, Z_TOP = arm.A, arm.B, arm.P, arm.Z_ARM, arm.Z_TOP
    T = 0.13
    AP = lambda z: A(z) + 0.05
    BP = lambda z: B(z) + 0.05
    arm_fn = lambda z: curve([(Z_ARM, 0.02), (1.75, 0.3), (2.0, 0.46), (Z_TOP, 0.52)], z)
    collar_a, collar_b, collar_top = 0.52, 0.44, Z_TOP + 0.2
    grip_body = (0.0, -(collar_b - 0.045), collar_top)
    off = (0.0, -grip_body[1], -grip_body[2])
    neck_th = math.acos(min(1.0, ((collar_a - 0.02) / AP(Z_TOP)) ** (P / 2.0)))
    cloth = [arm.torso_panel("pa_band", 0.0, Z_ARM, 32, 3, T, AP, BP),
             arm.torso_panel("pa_front", Z_ARM, Z_TOP, 14, 4, T, AP, BP, arm_fn, lambda z: math.pi - arm_fn(z)),
             arm.torso_panel("pa_back", Z_ARM, Z_TOP, 14, 4, T, AP, BP,
                             lambda z: math.pi + arm_fn(z), lambda z: TAU - arm_fn(z)),
             arm.shoulder_bridge("pa_bridge_r", arm_fn(Z_TOP), neck_th, T, AP, BP, lift=0.07, width_pad=0.06),
             arm.shoulder_bridge("pa_bridge_l", math.pi - arm_fn(Z_TOP), math.pi - neck_th, T, AP, BP, lift=0.07,
                                 width_pad=0.06)]
    leather = [arm.torso_panel("pa_hem", -0.012, 0.09, 28, 1, 0.19, lambda z: AP(z) + 0.012, lambda z: BP(z) + 0.012),
               arm.torso_panel("pa_collar", Z_TOP - 0.1, collar_top, 16, 1, 0.07, lambda z: collar_a,
                               lambda z: collar_b),
               kit.sweep("pa_placket", [(0, BP(z) + 0.022, z) for z in (-0.005, 0.7, 1.4, Z_ARM, 1.95, Z_TOP - 0.02)],
                         kit.rrect(0.12, 0.04, 0.01))]
    zs = (0.5, 1.03, Z_ARM)
    for i, z in enumerate(zs):
        leather.append(kit.board("pa_strap%d" % i, (0.42, 0.022, 0.09), 0.008, axis=0, loc=(0, BP(z) + 0.05, z)))
    buckles = []
    for i, z in enumerate(zs):
        fr = kit.rect_frame("pa_buckle%d" % i, (0.11, 0.12), (0.076, 0.086), -0.006, 0.006)
        g.place(fr, loc=(0.1, BP(z) + 0.068, z), rot=(math.pi / 2, 0, 0))
        tongue = g.cyl("pa_tongue%d" % i, 0.0055, -0.002, 0.07, segs=6, loc=(0.07, BP(z) + 0.07, z), rot=(0, math.pi / 2, 0))
        buckles += [fr, tongue]
    allp = cloth + leather + buckles
    _shift(allp, off)
    center = (0.0, -grip_body[1])
    for o in cloth:
        g.piece(o, M.LINEN, axis=(0, 0, 1), bevr=0.02, shade=55)
    for o in leather:
        g.piece(o, M.LEATHER, axis=(0, 0, 1), bevr=0.008, shade=45)
    for o in buckles:
        g.piece(o, M.BRASS, bevr=0.003, shade=45)
    lib.part(root, cloth, "Cloth", SET, weight=1.0)
    lib.part(root, leather, "Leather", SET, weight=1.0)
    lib.part(root, buckles, "Brass", SET, weight=1.2, cast_shadow=False)
    lib.params(root, M.LINEN, dict(color=C(194, 160, 108), threads=48.0, cloth="tri", center=center, quilt=0.15,
                                   puff=0.008, pillow_shade=0.22, stains=0.5, thread=C(118, 98, 70)))
    lib.params(root, M.LEATHER, dict(color=C(92, 60, 40), dark=C(56, 38, 26), grain=120.0, crease=0.5,
                                     crease_dir=(1.0, 1.0, 3.0), crease_dark=0.3, mottle=0.25, scuff=0.8, polish=0.4,
                                     dirt=0.6))
    lib.params(root, M.BRASS, dict(tarnish=0.85, verdigris=0.3))
    _grip_and_torso(lib, root, grip_body)
    lib.finish(root)


BUILDERS = [leather_vest, padded_armor]
