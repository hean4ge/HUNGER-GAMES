"""
items_melee.py - melee weapons for the Items category (built by items.py).
Held-item convention: hand grip at the origin, item points up +Z, edge/front faces +Y.
Blades are sliced horizontally: Steel body + darker Metal ground-edge bands.
"""
import math

import ls_common as ls
import items_kit as kit
from items_kit import curve, lerp, smoothstep

D = math.radians


def _scale2(fn):
    return lambda t: (fn(t), fn(t))


# ------------------------------------------------------------------ knife
def knife(lib):
    root = lib.begin_held("knife", "Weapon", tags=["Melee", "Blade"],
                          notes="Survival knife. Grip (handle centre) at origin, blade +Z, edge +Y.")
    z0, z1, tip_y = 0.285, 1.02, 0.03
    back = lambda s: curve([(0, -0.062), (0.6, -0.062), (0.84, -0.045), (1.0, tip_y)], s)
    front = lambda s: curve([(0, 0.122), (0.06, 0.138), (0.52, 0.142), (0.78, 0.12), (0.93, 0.076), (1.0, tip_y)], s)
    sts = kit.stations(z0, z1, 14, back, front, power=1.25)

    def hx(s, u, y):
        h = lerp(0.056, 0.036, s) / 2.0
        return h * 0.58 if u == 0.0 else h * (1.0 - 0.1 * u)

    body, edge = kit.blade("knife_blade", sts, hx, across=(0.0, 0.1, 1.0), grind_front=0.05)
    kit.part(lib, root, body, "Steel", rgb=(178, 181, 186))
    kit.part(lib, root, edge, "Metal")
    guard = kit.chamfer_box("knife_guard", (0.125, 0.31, 0.058), 0.018, loc=(0, 0.035, 0.262))
    handle = kit.wrap_grip("knife_handle", -0.255, 0.24, 0.058, 0.077, bands=6, bulge=0.009,
                           flare=lambda t: curve([(0, 1.08), (0.15, 1.0), (0.5, 1.06), (0.9, 0.97), (1.0, 0.96)], t))
    kit.part(lib, root, handle, "DarkLeather", smooth=50)
    pommel = kit.revolve("knife_pommel", [(0.0, -0.318), (0.06, -0.318), (0.08, -0.305), (0.086, -0.285),
                                          (0.08, -0.262), (0.066, -0.25)], segs=12)
    kit.place(pommel, scale=(0.86, 1.1, 1.0))
    kit.part(lib, root, kit.join([guard, pommel], "knife_fittings"), "DarkMetal", smooth=40)
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, tip_y, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------ throwing knife
def throwing_knife(lib):
    root = lib.begin_held("throwing_knife", "Weapon", tags=["Thrown", "Blade"],
                          notes="Balanced double-edged throwing knife, cord wrap, ring pommel. Grip at origin.")
    z0, z1 = 0.08, 0.66
    hw = lambda s: curve([(0, 0.04), (0.28, 0.08), (0.7, 0.05), (1.0, 0.0)], s)
    sts = kit.stations(z0, z1, 12, lambda s: -hw(s), hw, power=1.2)

    def hx(s, u, y):
        h = lerp(0.044, 0.03, s) / 2.0
        return h * (0.78 + 0.22 * (1.0 - abs(2.0 * u - 1.0)))

    body, edges = kit.blade("tk_blade", sts, hx, across=(0.0, 0.5, 1.0), grind_front=0.03, grind_back=0.03)
    neck = kit.revolve("tk_neck", [(0.0, -0.255), (0.02, -0.255), (0.027, -0.235), (0.028, -0.2)], segs=8)
    kit.place(neck, scale=(0.8, 1.2, 1.0))
    kit.part(lib, root, kit.join([body, neck], "tk_steel"), "Steel", rgb=(186, 190, 196))
    kit.part(lib, root, edges, "Metal")
    collar = kit.revolve("tk_collar", [(0.036, 0.035), (0.047, 0.042), (0.049, 0.07), (0.04, 0.1)], segs=10)
    kit.place(collar, scale=(0.82, 1.28, 1.0))
    wrap = kit.wrap_grip("tk_wrap", -0.215, 0.05, 0.03, 0.046, bands=8, bulge=0.007, tilt_deg=18)
    kit.part(lib, root, wrap, "Rope", smooth=55)
    ring = ls.torus("tk_ring", major=0.052, minor=0.015, major_segments=14, minor_segments=6)
    kit.place(ring, loc=(0, 0, -0.292), rot=(0, D(90), 0))
    kit.part(lib, root, kit.join([collar, ring], "tk_fittings"), "Metal", rgb=(108, 112, 118), smooth=45)
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, 0, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------ machete
def machete(lib):
    root = lib.begin_held("machete", "Weapon", tags=["Melee", "Blade"],
                          notes="Wide machete with upswept tip, full tang, wood scales, brass rivets. Grip at origin.")
    z0, z1 = 0.30, 2.08
    back = lambda s: curve([(0, -0.052), (0.78, -0.052), (0.9, -0.01), (0.96, 0.08), (1.0, 0.19)], s)
    front = lambda s: curve([(0, 0.118), (0.4, 0.17), (0.75, 0.245), (0.88, 0.27), (0.96, 0.245), (1.0, 0.19)], s)
    sts = kit.stations(z0, z1, 18, back, front, power=1.3)

    def hx(s, u, y):
        h = lerp(0.05, 0.03, s) / 2.0
        return h * 0.6 if u == 0.0 else h

    body, edge = kit.blade("machete_blade", sts, hx, across=(0.0, 0.06, 1.0), grind_front=0.06)
    path = [(0, 0.0, 0.33), (0, 0.0, 0.2), (0, 0.0, 0.05), (0, 0.004, -0.1), (0, 0.012, -0.22),
            (0, 0.028, -0.31), (0, 0.05, -0.36)]
    hscale = lambda t: (curve([(0, 1.0), (0.5, 0.95), (0.88, 1.08), (1.0, 1.02)], t),
                        curve([(0, 1.0), (0.5, 0.94), (0.88, 1.12), (1.0, 1.06)], t))
    scales = kit.sweep("machete_scales", path, kit.rrect(0.1, 0.155, 0.035), hscale)
    tang_path = path[:-1] + [(0, 0.056, -0.366)]
    tang = kit.sweep("machete_tang", tang_path, kit.rrect(0.032, 0.168, 0.006), hscale)
    kit.part(lib, root, kit.join([body, tang], "machete_steel"), "Steel", rgb=(152, 154, 154))
    kit.part(lib, root, edge, "Metal", rgb=(106, 110, 116))
    kit.part(lib, root, scales, "Wood", rgb=(96, 64, 44), smooth=45)
    bolster = kit.revolve("machete_bolster", [(0.05, 0.268), (0.062, 0.28), (0.064, 0.33), (0.055, 0.362)], segs=12)
    kit.place(bolster, loc=(0, 0.022, 0), scale=(0.95, 1.68, 1.0))
    rivets = [kit.rod("machete_rivet%d" % i, 0.021, 0.114, 8, (0, 0.004 + 0.01 * (i == 0), z), "X")
              for i, z in enumerate((-0.19, 0.0, 0.18))]
    kit.part(lib, root, kit.join([bolster] + rivets, "machete_brass"), "Brass", smooth=40)
    lanyard = ls.torus("machete_lanyard", major=0.055, minor=0.014, major_segments=12, minor_segments=5)
    kit.place(lanyard, loc=(0, 0.035, -0.372), rot=(D(90), 0, 0))
    kit.part(lib, root, lanyard, "Rope", smooth=50, shadow=False)
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, 0.19, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------ hatchet
def hatchet(lib):
    root = lib.begin_held("hatchet", "Weapon", tags=["Melee", "Axe"],
                          notes="Bearded hatchet, ash haft with leather grip. Grip at origin, bit faces +Y.")
    zs = [-0.40, -0.385, -0.36, -0.32, -0.25, -0.1, 0.3, 0.8, 1.2, 1.45, 1.71]
    path = [(0, curve([(-0.40, -0.026), (-0.25, -0.01), (0.3, 0.004), (1.0, -0.004), (1.71, 0.0)], z), z) for z in zs]
    hs = lambda t: curve([(0, 1.12), (0.008, 1.24), (0.019, 1.27), (0.038, 1.2), (0.072, 1.0), (0.14, 0.96),
                          (0.5, 0.93), (0.8, 1.0), (1.0, 1.0)], t)
    haft = kit.sweep("hatchet_haft", path, kit.rrect(0.094, 0.14, 0.04), _scale2(hs))
    kit.part(lib, root, haft, "Wood", rgb=(132, 98, 64), smooth=45)
    wrap = kit.wrap_grip("hatchet_wrap", -0.24, 0.36, 0.056, 0.084, bands=7, bulge=0.008)
    kit.part(lib, root, wrap, "DarkLeather", smooth=50)
    # head: horizontal slices from the beard heel (z 1.18) to the toe (z 1.72)
    zh = [1.18, 1.2, 1.23, 1.27, 1.31, 1.35, 1.39, 1.42, 1.46, 1.51, 1.56, 1.6, 1.625, 1.65, 1.675, 1.698, 1.72]
    yf = lambda z: curve([(1.18, 0.40), (1.26, 0.462), (1.36, 0.492), (1.46, 0.5), (1.56, 0.494),
                          (1.64, 0.478), (1.72, 0.448)], z)

    def yb(z):
        if z <= 1.42:
            return curve([(1.18, 0.40), (1.21, 0.285), (1.25, 0.17), (1.3, 0.07), (1.35, -0.03),
                          (1.39, -0.115), (1.42, -0.15)], z)
        if z <= 1.6:
            return -0.15
        return lerp(-0.15, 0.448, ((z - 1.6) / 0.12) ** 1.6)

    sts = [(z, yb(z), yf(z), (z - 1.18) / 0.54) for z in zh]
    thick = lambda y: curve([(-0.2, 0.098), (0.06, 0.098), (0.22, 0.058), (0.42, 0.03), (0.5, 0.026)], y)

    def hx(s, u, y):
        return thick(y) * (0.8 if u == 0.0 else 1.0)

    body, edge = kit.blade("hatchet_head", sts, hx, across=(0.0, 0.05, 0.35, 0.7, 1.0), grind_front=0.055)
    kit.part(lib, root, body, "Steel", rgb=(158, 160, 160))
    kit.part(lib, root, edge, "Metal")
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, 0.5, 1.46), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------ spear
def spear(lib):
    root = lib.begin_held("spear", "Weapon", tags=["Melee", "Thrown", "Polearm"],
                          notes="7-stud ash spear, leaf head, rope binding and a red rag. Grip (balance point) at origin.")
    shaft = kit.sweep("spear_shaft", [(0, 0, -2.52), (0, 0, 0.0), (0, 0, 3.52)], kit.circle(8, 1.0),
                      _scale2(lambda t: lerp(0.07, 0.06, t)))
    kit.part(lib, root, shaft, "Wood", rgb=(146, 112, 76), smooth=50)
    ferrule = kit.revolve("spear_butt", [(0.0, -2.62), (0.05, -2.62), (0.074, -2.6), (0.08, -2.56),
                                         (0.08, -2.44), (0.074, -2.42)], segs=10)
    socket = kit.revolve("spear_socket", [(0.072, 3.28), (0.09, 3.29), (0.09, 3.35), (0.08, 3.37),
                                          (0.056, 3.6), (0.04, 3.68)], segs=10)
    kit.part(lib, root, kit.join([ferrule, socket], "spear_iron"), "DarkMetal", smooth=40)
    wrap = kit.wrap_grip("spear_wrap", -0.4, 0.4, 0.078, 0.078, bands=8, bulge=0.009)
    kit.part(lib, root, wrap, "Leather", smooth=50)
    binding = kit.wrap_grip("spear_binding", 3.14, 3.3, 0.074, 0.074, bands=4, bulge=0.011, tilt_deg=10)
    kit.part(lib, root, binding, "Rope", smooth=55)
    z0, z1 = 3.62, 4.40
    hw = lambda s: curve([(0, 0.034), (0.1, 0.115), (0.3, 0.178), (0.58, 0.142), (0.85, 0.07), (1.0, 0.0)], s)
    sts = kit.stations(z0, z1, 12, lambda s: -hw(s), hw, power=1.2)

    def hx(s, u, y):
        return lerp(0.05, 0.026, s) * (0.42 + 0.58 * (1.0 - abs(2.0 * u - 1.0)))

    body, edges = kit.blade("spear_head", sts, hx, across=(0.0, 0.5, 1.0), grind_front=0.042, grind_back=0.042)
    kit.part(lib, root, body, "Steel", rgb=(170, 172, 174))
    kit.part(lib, root, edges, "Metal")
    knot = ls.torus("spear_knot", major=0.074, minor=0.022, major_segments=12, minor_segments=5)
    kit.place(knot, loc=(0, 0, 3.07))
    strip_a = kit.sweep("spear_rag_a", [(0.06, 0.01, 3.06), (0.095, 0.03, 2.95), (0.118, 0.05, 2.8),
                                        (0.13, 0.03, 2.64), (0.152, 0.06, 2.47)],
                        kit.rrect(0.13, 0.024, 0.008), lambda t: (1.0 - 0.35 * t, 1.0), up=(0, 1, 0))
    strip_b = kit.sweep("spear_rag_b", [(0.04, -0.05, 3.06), (0.062, -0.085, 2.96), (0.075, -0.104, 2.84),
                                        (0.095, -0.096, 2.72)],
                        kit.rrect(0.1, 0.022, 0.007), lambda t: (1.0 - 0.4 * t, 1.0), up=(1, -0.6, 0))
    kit.part(lib, root, kit.join([knot, strip_a, strip_b], "spear_rag"), "Cloth", rgb=(150, 58, 44),
             smooth=45, shadow=False)
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, 0, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------ mace
def mace(lib):
    root = lib.begin_held("mace", "Weapon", tags=["Melee", "Blunt"],
                          notes="Flanged iron mace on a wooden haft. Grip at origin, head +Z, a flange faces +Y.")
    haft = kit.sweep("mace_haft", [(0, 0, -0.36), (0, 0, 0.8), (0, 0, 1.78)], kit.circle(8, 1.0),
                     _scale2(lambda t: lerp(0.06, 0.056, t)))
    kit.part(lib, root, haft, "Wood", rgb=(98, 70, 48), smooth=50)
    wrap = kit.wrap_grip("mace_wrap", -0.3, 0.34, 0.068, 0.068, bands=7, bulge=0.009)
    kit.part(lib, root, wrap, "DarkLeather", smooth=50)
    pommel = kit.revolve("mace_pommel", [(0.0, -0.42), (0.045, -0.42), (0.078, -0.395), (0.088, -0.36),
                                         (0.078, -0.325), (0.066, -0.3)], segs=10)
    kit.part(lib, root, pommel, "Metal", smooth=40)
    collar = kit.revolve("mace_collar", [(0.062, 1.52), (0.078, 1.53), (0.078, 1.58), (0.065, 1.6), (0.065, 1.64),
                                         (0.078, 1.66), (0.078, 1.7), (0.062, 1.71)], segs=10)
    core = kit.revolve("mace_core", [(0.062, 1.7), (0.09, 1.74), (0.125, 1.84), (0.135, 1.94), (0.125, 2.04),
                                     (0.095, 2.12), (0.055, 2.16), (0.0, 2.17)], segs=12)
    kit.part(lib, root, kit.join([collar, core], "mace_iron"), "DarkMetal", smooth=35)
    flanges = []
    prof = [(0.07, 1.74), (0.17, 1.79), (0.235, 1.9), (0.24, 1.98), (0.2, 2.08), (0.1, 2.15), (0.06, 2.12)]
    for k in range(6):
        f = ls.extrude_profile("mace_flange%d" % k, prof, 0.075)
        ls.bevel(f, width=0.014, segments=1, angle_deg=30)
        kit.place(f, rot=(0, 0, D(90 + 60 * k)))
        flanges.append(f)
    spike = kit.revolve("mace_spike", [(0.05, 2.12), (0.053, 2.15), (0.03, 2.27), (0.0, 2.38)], segs=8)
    kit.part(lib, root, kit.join(flanges + [spike], "mace_steel"), "Steel", rgb=(166, 168, 170))
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, 0, 2.38), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------ sword
def sword(lib):
    root = lib.begin_held("sword", "Weapon", tags=["Melee", "Blade"],
                          notes="Arming sword with fuller, blackened crossguard, brass wheel pommel. Grip at origin.")
    z0, z1 = 0.46, 3.05
    hw = lambda s: curve([(0, 0.148), (0.1, 0.142), (0.7, 0.118), (0.86, 0.098), (0.95, 0.05), (1.0, 0.0)], s)
    sts = kit.stations(z0, z1, 18, lambda s: -hw(s), hw, power=1.35)

    def hx(s, u, y):
        h = lerp(0.066, 0.042, s) / 2.0
        if u == 0.0 or u == 1.0:
            return h * 0.86
        if abs(u - 0.5) < 1e-6:
            return h - 0.011 * (1.0 - smoothstep(0.52, 0.66, s)) * smoothstep(0.0, 0.03, s)
        return h

    body, edges = kit.blade("sword_blade", sts, hx, across=(0.0, 0.34, 0.5, 0.66, 1.0),
                            grind_front=0.045, grind_back=0.045)
    kit.part(lib, root, body, "Steel", rgb=(184, 188, 192))
    kit.part(lib, root, edges, "Metal")
    ys = [-0.4, -0.37, -0.3, -0.16, 0.0, 0.16, 0.3, 0.37, 0.4]
    gpath = [(0, y, 0.43 + 0.06 * (y / 0.4) ** 2) for y in ys]
    gs = lambda t: curve([(0, 1.0), (0.4, 0.82), (0.85, 0.66), (0.93, 0.92), (1.0, 0.74)], abs(2 * t - 1))
    guard = kit.sweep("sword_guard", gpath, kit.rrect(0.11, 0.085, 0.026), _scale2(gs))
    kit.part(lib, root, guard, "DarkMetal", smooth=35)
    grip_mesh = kit.wrap_grip("sword_grip", -0.38, 0.4, 0.056, 0.068, bands=8, bulge=0.008,
                              flare=lambda t: 1.0 + 0.06 * math.sin(math.pi * t))
    kit.part(lib, root, grip_mesh, "Leather", smooth=50)
    pommel = kit.revolve("sword_pommel", [(0.0, -0.585), (0.05, -0.585), (0.095, -0.56), (0.115, -0.52),
                                          (0.112, -0.47), (0.09, -0.43), (0.058, -0.4), (0.05, -0.385)], segs=12)
    kit.place(pommel, scale=(0.72, 1.0, 1.0))
    kit.part(lib, root, pommel, "Brass", smooth=40)
    kit.grip(lib, root)
    lib.attach(root, "Tip", (0, 0, z1), look=(0, 0, 1))
    lib.finish(root)


BUILDERS = [knife, throwing_knife, machete, hatchet, spear, mace, sword]
