"""
items_armor.py - leather_vest and padded_armor for the Items category (built by items.py).
Torso vests open at the neck and arms, ~2.5 studs tall, inner cavity ~2.05 x 1.15 studs (fits an R15 torso).
Built in "body space" (hem on z = 0) and then shifted so the Grip (back of the collar, where a hand
holds the vest up) sits at the origin. A "Torso" attachment marks the cavity centre for wearing it.
"""
import math

import items_kit as kit
from items_kit import curve, lerp

TAU = math.pi * 2.0
P = 2.4
Z_ARM, Z_TOP = 1.55, 2.28
A = lambda z: curve([(0, 1.1), (0.5, 1.06), (1.0, 1.08), (1.5, 1.14), (1.9, 1.12), (2.3, 1.02)], z)
B = lambda z: curve([(0, 0.66), (0.5, 0.62), (1.0, 0.64), (1.5, 0.68), (1.9, 0.62), (2.3, 0.44)], z)


def torso_pt(th, z, d, a_fn, b_fn, extra=0.0):
    a, b = a_fn(z) - d + extra, b_fn(z) - d + extra
    c, s = math.cos(th), math.sin(th)
    return (a * math.copysign(abs(c) ** (2.0 / P), c), b * math.copysign(abs(s) ** (2.0 / P), s), z)


def torso_panel(name, z0, z1, nu, nv, thick, a_fn, b_fn, th_lo=None, th_hi=None, ridge=0.0):
    """Thick panel on a superellipse torso. th_lo/th_hi(z) bound the angles (0 = +X, pi/2 = front);
    omit them for a closed ring. ridge adds quilting: every other outer vertex pushed out."""
    zs = [lerp(z0, z1, j / nv) for j in range(nv + 1)]
    if th_lo is None:
        ths = [TAU * i / nu for i in range(nu)]
        outer = [[torso_pt(t, z, 0.0, a_fn, b_fn, ridge if i % 2 == 0 else 0.0) for i, t in enumerate(ths)] for z in zs]
        inner = [[torso_pt(t, z, thick, a_fn, b_fn) for t in ths] for z in zs]
        return kit.grid_mesh(name, outer + inner[::-1], close_u=True, close_v=True)
    rows = []
    for z in zs:
        lo, hi = th_lo(z), th_hi(z)
        ths = [lerp(lo, hi, i / nu) for i in range(nu + 1)]
        o = [torso_pt(t, z, 0.0, a_fn, b_fn, ridge if i % 2 == 0 else 0.0) for i, t in enumerate(ths)]
        n = [torso_pt(t, z, thick, a_fn, b_fn) for t in ths]
        rows.append(o + n[::-1])
    return kit.grid_mesh(name, rows, close_u=True)


def shoulder_bridge(name, th_arm, th_neck, thick, a_fn, b_fn, lift=0.05, width_pad=0.02):
    """Strap over one shoulder joining the front and back panels at Z_TOP (sign of cos(th) picks the side)."""
    pa = torso_pt(th_arm, Z_TOP, thick / 2, a_fn, b_fn)
    pn = torso_pt(th_neck, Z_TOP, thick / 2, a_fn, b_fn)
    x = (pa[0] + pn[0]) / 2.0
    w = abs(pa[0] - pn[0]) + width_pad
    yf = (pa[1] + pn[1]) / 2.0
    path = [(x, yf + 0.004, Z_TOP - 0.08), (x, yf * 0.78, Z_TOP + lift * 0.6), (x, yf * 0.32, Z_TOP + lift),
            (x, -yf * 0.32, Z_TOP + lift), (x, -yf * 0.78, Z_TOP + lift * 0.6), (x, -yf - 0.004, Z_TOP - 0.08)]
    return kit.sweep(name, path, kit.rrect(w, thick, 0.03))


def _finish_vest(lib, root, grip_body):
    kit.grip(lib, root)
    lib.attach(root, "Torso", (0, -grip_body[1], 1.15 - grip_body[2]), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)


def leather_vest(lib):
    root = lib.begin_held("leather_vest", "Armor", tags=["Armor", "Wearable"],
                          notes="Leather vest: V-neck, open arms, toggled placket, laced sides. Grip = back of the "
                                "collar at origin (vest hangs below); 'Torso' attachment = cavity centre for wearing.")
    T = 0.08
    arm = lambda z: curve([(Z_ARM, 0.02), (1.75, 0.3), (2.0, 0.44), (Z_TOP, 0.5)], z)
    neck = lambda z: curve([(Z_ARM, 1.5), (1.8, 1.32), (2.05, 1.14), (Z_TOP, 1.05)], z)
    grip_body = (0.0, -(B(Z_TOP) - T / 2), Z_TOP)
    off = (-grip_body[0], -grip_body[1], -grip_body[2])
    pieces = [torso_panel("lv_band", 0.0, Z_ARM, 24, 2, T, A, B),
              torso_panel("lv_front_r", Z_ARM, Z_TOP, 6, 4, T, A, B, arm, neck),
              torso_panel("lv_front_l", Z_ARM, Z_TOP, 6, 4, T, A, B,
                          lambda z: math.pi - neck(z), lambda z: math.pi - arm(z)),
              torso_panel("lv_back", Z_ARM, Z_TOP, 12, 4, T, A, B,
                          lambda z: math.pi + arm(z), lambda z: TAU - arm(z)),
              shoulder_bridge("lv_bridge_r", arm(Z_TOP), neck(Z_TOP), T, A, B),
              shoulder_bridge("lv_bridge_l", math.pi - arm(Z_TOP), math.pi - neck(Z_TOP), T, A, B)]
    kit.part(lib, root, kit.shift(kit.join(pieces, "lv_leather"), off), "Leather", rgb=(114, 76, 50), smooth=40)
    trim = torso_panel("lv_hem", -0.012, 0.1, 20, 1, 0.1, lambda z: A(z) + 0.014, lambda z: B(z) + 0.014)
    placket = kit.sweep("lv_placket", [(0, B(z) + 0.012, z) for z in (-0.005, 0.5, 1.0, Z_ARM + 0.02)],
                        kit.rrect(0.13, 0.035, 0.01))
    kit.part(lib, root, kit.shift(kit.join([trim, placket], "lv_trim"), off), "DarkLeather", smooth=40)
    toggles = [kit.rod("lv_toggle%d" % i, 0.028, 0.13, 6, (0, B(z) + 0.04, z), "X") for i, z in enumerate((0.35, 0.8, 1.25))]
    kit.part(lib, root, kit.shift(kit.join(toggles, "lv_toggles"), off), "Brass", smooth=40, shadow=False)
    laces = []
    for sx in (1, -1):
        pts = [(sx * (A(z) + 0.012), (0.07 if i % 2 == 0 else -0.07), z)
               for i, z in enumerate([lerp(0.25, 1.3, k / 7.0) for k in range(8)])]
        laces.append(kit.sweep("lv_lace", pts, kit.circle(5, 0.017)))
    kit.part(lib, root, kit.shift(kit.join(laces, "lv_laces"), off), "Rope", smooth=55, shadow=False)
    _finish_vest(lib, root, grip_body)


def padded_armor(lib):
    root = lib.begin_held("padded_armor", "Armor", tags=["Armor", "Wearable"],
                          notes="Quilted padded jacket (gambeson) with leather collar, front straps and brass buckles. "
                                "Grip = back of the collar at origin; 'Torso' attachment = cavity centre for wearing.")
    T, RIDGE = 0.13, 0.03
    AP = lambda z: A(z) + 0.05
    BP = lambda z: B(z) + 0.05
    arm = lambda z: curve([(Z_ARM, 0.02), (1.75, 0.3), (2.0, 0.46), (Z_TOP, 0.52)], z)
    collar_a, collar_b, collar_top = 0.52, 0.44, Z_TOP + 0.2
    grip_body = (0.0, -(collar_b - 0.045), collar_top)
    off = (0.0, -grip_body[1], -grip_body[2])
    neck_th = math.acos(min(1.0, ((collar_a - 0.02) / AP(Z_TOP)) ** (P / 2.0)))
    pieces = [torso_panel("pa_band", 0.0, Z_ARM, 24, 2, T, AP, BP, ridge=RIDGE),
              torso_panel("pa_front", Z_ARM, Z_TOP, 12, 4, T, AP, BP, arm, lambda z: math.pi - arm(z), ridge=RIDGE),
              torso_panel("pa_back", Z_ARM, Z_TOP, 12, 4, T, AP, BP,
                          lambda z: math.pi + arm(z), lambda z: TAU - arm(z), ridge=RIDGE),
              shoulder_bridge("pa_bridge_r", arm(Z_TOP), neck_th, T, AP, BP, lift=0.07, width_pad=0.06),
              shoulder_bridge("pa_bridge_l", math.pi - arm(Z_TOP), math.pi - neck_th, T, AP, BP, lift=0.07, width_pad=0.06)]
    kit.part(lib, root, kit.shift(kit.join(pieces, "pa_cloth"), off), "Cloth", rgb=(156, 140, 108), smooth=55)
    trim = torso_panel("pa_hem", -0.012, 0.09, 16, 1, 0.19, lambda z: AP(z) + 0.06, lambda z: BP(z) + 0.06)
    collar = torso_panel("pa_collar", Z_TOP - 0.1, collar_top, 12, 1, 0.09, lambda z: collar_a, lambda z: collar_b)
    placket = kit.sweep("pa_placket", [(0, BP(z) + 0.03, z) for z in (-0.005, 0.7, 1.4, Z_ARM, 1.95, Z_TOP - 0.02)],
                        kit.rrect(0.12, 0.05, 0.012))
    zs = (0.5, 1.03, Z_ARM)
    straps = [kit.board("pa_strap%d" % i, (0.42, 0.04, 0.1), 0.014, axis=0, loc=(0, BP(z) + 0.06, z))
              for i, z in enumerate(zs)]
    kit.part(lib, root, kit.shift(kit.join([trim, collar, placket] + straps, "pa_leather"), off), "Leather", smooth=40)
    buckles = [kit.board("pa_buckle%d" % i, (0.12, 0.03, 0.13), 0.014, axis=1, loc=(0.1, BP(z) + 0.088, z))
               for i, z in enumerate(zs)]
    kit.part(lib, root, kit.shift(kit.join(buckles, "pa_buckles"), off), "Brass", shadow=False)
    _finish_vest(lib, root, grip_body)


BUILDERS = [leather_vest, padded_armor]
