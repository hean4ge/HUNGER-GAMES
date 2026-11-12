"""
ir_weapons.py - realistic held weapons for the ItemsReal set (built by items_real.py).
Held-item convention (unchanged from v1): hand grip at the origin, item points up +Z, edge / front faces +Y.
Every v1 attachment (Grip, Tip, Nock, StringTop, StringBottom, ArrowRest) keeps its exact position.
Real-world proportions: blades 4-8 mm thick, handles 3-5 cm across, 1 stud ~ 0.33 m.
"""
import math

import ir_geo as g
import tex_items_mats as M
from ir_geo import curve, lerp, smoothstep

D = math.radians
SET = "IR_Weapons"


def _grip(lib, root):
    lib.attach(root, "Grip", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))


# ------------------------------------------------------------------------------------------------ knife
def knife(lib):
    root = lib.begin("knife", "Weapon", tags=["Melee", "Blade"], held=True,
                     notes="Clip-point survival knife: carbon-steel blade with a saber grind and honed edge, oval steel "
                           "guard, stacked-leather-washer handle with fibre spacers, steel pommel with peened tang nut. "
                           "Grip (handle centre) at origin, blade +Z, edge +Y.")
    z0, z1, tip_y = 0.285, 1.02, 0.03
    back = lambda s: curve([(0, -0.058), (0.56, -0.058), (0.72, -0.046), (0.88, -0.014), (1.0, tip_y)], s)
    front = lambda s: curve([(0, 0.112), (0.06, 0.124), (0.5, 0.13), (0.76, 0.114), (0.91, 0.074), (1.0, tip_y)], s)
    sts = g.stations(z0, z1, 20, back, front, power=1.2)

    def section(s, z, yb, yf):
        w = max(yf - yb, 1e-4)
        hs = lerp(0.0115, 0.006, s) * (1.0 - 0.45 * smoothstep(0.6, 1.0, s))
        return [(yb, hs * 0.9), (yb + min(0.004, w * 0.08), hs), (yb + w * 0.44, hs), (yb + w * 0.7, hs * 0.52),
                (yf - min(0.014, w * 0.12), 0.0016), (yf, 0.0004)]
    bl = g.blade("knife_blade", sts, section, edges=("front",), band=0.018)
    g.piece(bl, M.STEEL, axis=(0, 0, 1), bevr=0.0025)
    guard = g.cbox("knife_guard", (0.066, 0.27, 0.046), 0.012, loc=(0, 0.03, 0.262))
    g.piece(guard, M.IRON, axis=(0, 1, 0), bevr=0.008, shade=50)
    flare = lambda t: curve([(0, 1.02), (0.12, 0.97), (0.5, 1.05), (0.85, 0.98), (1.0, 0.95)], t)
    handle = g.ribbed_grip("knife_handle", -0.236, 0.232, 0.05, 0.064, segs=14, ribs=9, depth=0.0035, flare=flare,
                           rows_per_rib=3, offset=(0, 0.004))
    g.piece(handle, M.LEATHER, axis=(0, 0, 1), bevr=0.006)
    spacers = [g.lathe("knife_sp%d" % i, [(0.0, z), (0.05, z), (0.052, z + 0.004), (0.052, z + 0.014), (0.05, z + 0.018),
                                          (0.0, z + 0.018)], segs=16, sy=1.28) for i, z in enumerate((0.232, -0.254))]
    for sp in spacers:
        g.place(sp, loc=(0, 0.004, 0))
        g.piece(sp, M.WAX, bevr=0.003)
    pommel = g.lathe("knife_pommel", [(0.0, -0.318), (0.03, -0.318), (0.05, -0.31), (0.06, -0.295), (0.062, -0.272),
                                      (0.058, -0.256), (0.0, -0.254)], segs=16, sx=0.86, sy=1.12)
    nut = g.lathe("knife_nut", [(0.0, -0.33), (0.016, -0.33), (0.02, -0.325), (0.02, -0.316), (0.0, -0.316)], segs=8)
    g.piece(pommel, M.IRON, bevr=0.006, shade=60)
    g.piece(nut, M.STEEL, bevr=0.002, shade=50)
    lib.part(root, [bl, guard, pommel, nut], "Steel", SET, weight=1.15)
    lib.part(root, [handle] + spacers, "Leather", SET, weight=1.3, smooth=50)
    lib.params(root, M.STEEL, dict(wear=0.6, patina=0.5, rust=0.35, pits=0.3))
    lib.params(root, M.IRON, dict(rust=0.25, edge_wear=0.9, hammer=60.0))
    lib.params(root, M.LEATHER, dict(color=g_c(92, 58, 36), washers=0.0105, crease=0.3, scuff=0.6, polish=0.6))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, tip_y, z1), look=(0, 0, 1))
    lib.finish(root)


def g_c(r, gg, b):
    from tex_items import C
    return C(r, gg, b)


# ------------------------------------------------------------------------------------------------ throwing knife
def throwing_knife(lib):
    root = lib.begin("throwing_knife", "Weapon", tags=["Thrown", "Blade"], held=True,
                     notes="One-piece stonewashed throwing knife: double-edged spear-point blade, flat tang under an "
                           "olive paracord wrap, steel ring pommel. Grip at origin, blade +Z.")
    z0, z1 = 0.08, 0.66
    hw = lambda s: curve([(0, 0.04), (0.26, 0.076), (0.66, 0.05), (1.0, 0.0)], s)
    sts = g.stations(z0, z1, 16, lambda s: -hw(s), hw, power=1.15)

    def section(s, z, yb, yf):
        w = max(yf - yb, 1e-4)
        h = lerp(0.008, 0.005, s)
        return [(yb, 0.0005), (yb + w * 0.08, 0.0018), (yb + w * 0.3, h * 0.8), (yb + w * 0.5, h),
                (yf - w * 0.3, h * 0.8), (yf - w * 0.08, 0.0018), (yf, 0.0005)]
    bl = g.blade("tk_blade", sts, section, edges=("front", "back"), band=0.014)
    g.piece(bl, M.STEEL, bevr=0.002)
    tang = g.cbox("tk_tang", (0.016, 0.07, 0.36), 0.004, loc=(0, 0, -0.1))
    g.piece(tang, M.STEEL, bevr=0.002)
    ring = g.torus("tk_ring", 0.05, 0.011, segs=20, minor_segs=8, center=(0, 0, -0.302), axis=(1, 0, 0))
    g.piece(ring, M.STEEL, bevr=0.003, shade=70)
    wrap = g.ribbed_grip("tk_wrap", -0.24, 0.06, 0.024, 0.044, segs=10, ribs=16, depth=0.0035, rows_per_rib=2, p=2.6,
                         tilt=0.6)
    g.piece(wrap, M.CORD, axis=(0, 0, 1), bevr=0.004, a={"a0": g.angle_attr(wrap)})
    lib.part(root, [bl, tang, ring], "Steel", SET, weight=1.2)
    lib.part(root, [wrap], "Rope", SET, weight=1.2, smooth=55)
    lib.params(root, M.STEEL, dict(stonewash=1.0, patina=0.25, bright=0.5, rust=0.2, pits=0.15))
    lib.params(root, M.CORD, dict(color=g_c(84, 86, 58), turns=53.0, strands=2, dirt=0.4))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, 0, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ machete
def machete(lib):
    root = lib.begin("machete", "Weapon", tags=["Melee", "Blade"], held=True,
                     notes="Latin machete with an upswept tip: blackened carbon steel worn to bare metal at the edge "
                           "(file-sharpened band), full tang between hardwood scales with three brass-lined rivets, "
                           "cord lanyard. Grip at origin.")
    z0, z1 = 0.30, 2.08
    back = lambda s: curve([(0, -0.05), (0.78, -0.05), (0.9, -0.012), (0.96, 0.08), (1.0, 0.19)], s)
    front = lambda s: curve([(0, 0.112), (0.4, 0.16), (0.75, 0.236), (0.88, 0.262), (0.96, 0.24), (1.0, 0.19)], s)
    sts = g.stations(z0, z1, 22, back, front, power=1.25)

    def section(s, z, yb, yf):
        w = max(yf - yb, 1e-4)
        hs = lerp(0.0078, 0.0048, s)
        return [(yb, hs * 0.85), (yb + 0.003, hs), (yb + w * 0.5, hs * 0.86), (yf - min(0.03, w * 0.2), 0.0022),
                (yf, 0.0005)]
    bl = g.blade("machete_blade", sts, section, edges=("front",), band=0.035)
    g.piece(bl, M.STEEL, bevr=0.002)
    path = [(0, 0.0, 0.33), (0, 0.0, 0.2), (0, 0.0, 0.05), (0, 0.004, -0.1), (0, 0.012, -0.22), (0, 0.028, -0.31),
            (0, 0.05, -0.36)]
    hscale = lambda t: (curve([(0, 1.0), (0.5, 0.95), (0.88, 1.08), (1.0, 1.02)], t),
                        curve([(0, 1.0), (0.5, 0.94), (0.88, 1.12), (1.0, 1.06)], t))
    import items_kit as kit
    scales = g.sweep("machete_scales", path, kit.rrect(0.094, 0.148, 0.034), hscale)
    g.piece(scales, M.WOOD, axis=(0, 0, 1), bevr=0.008, a={"a1": 1.0})
    tang = g.sweep("machete_tang", path[:-1] + [(0, 0.056, -0.366)], kit.rrect(0.012, 0.158, 0.003), hscale)
    g.piece(tang, M.STEEL, axis=(0, 0, 1), bevr=0.002)
    rivets = []
    for i, z in enumerate((-0.19, 0.0, 0.18)):
        r = g.cyl("machete_rivet%d" % i, 0.017, -0.05, 0.05, segs=12, loc=(0, 0.004 + 0.01 * (i == 0), z), rot=(0, D(90), 0))
        g.piece(r, M.BRASS, bevr=0.003, shade=50)
        rivets.append(r)
    lan = g.torus("machete_lanyard", 0.05, 0.0085, segs=16, minor_segs=6, center=(0, 0.035, -0.395),
                  axis=(0.14, -1.0, 0.0))
    g.piece(lan, M.CORD, axis=(1, 0, 0), bevr=0.003, a={"a0": g.angle_attr(lan, axis="X")})
    lib.part(root, [bl, tang] + rivets, "Steel", SET, weight=1.0)
    lib.part(root, [scales, lan], "Wood", SET, weight=1.3, smooth=45)
    lib.params(root, M.STEEL, dict(bright=0.42, patina=0.75, patina_dark=0.62, patina_f=2.5, patina_rough=0.3, wear=0.8,
                                   rust=0.5, pits=0.45))
    lib.params(root, M.WOOD, dict(light=g_c(112, 70, 44), dark=g_c(64, 38, 24), rings=40.0, pith=(1.6, 0.3),
                                  rough=0.48, grime=0.5))
    lib.params(root, M.CORD, dict(color=g_c(70, 60, 48), turns=60.0))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, 0.19, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ hatchet
def hatchet(lib):
    root = lib.begin("hatchet", "Weapon", tags=["Melee", "Axe"], held=True,
                     notes="Bearded hatchet: hand-forged head left black with forge scale, the bit ground bright; "
                           "hickory haft (oval, swelled knob) with hand grime, wedged through the eye. Grip at origin, "
                           "bit faces +Y.")
    zs = [-0.40, -0.39, -0.37, -0.33, -0.27, -0.18, -0.05, 0.15, 0.4, 0.65, 0.9, 1.1, 1.25, 1.4, 1.55, 1.7, 1.735]
    yoff = lambda z: curve([(-0.40, -0.026), (-0.25, -0.01), (0.3, 0.004), (1.0, -0.004), (1.735, 0.0)], z)
    hs = lambda t: curve([(0, 0.82), (0.006, 1.12), (0.02, 1.24), (0.04, 1.2), (0.075, 1.02), (0.14, 0.96),
                          (0.5, 0.92), (0.8, 0.99), (1.0, 1.0)], t)
    rings = []
    for z in zs:
        t = (z - zs[0]) / (zs[-1] - zs[0])
        k = hs(t)
        rings.append(g.ring((0, yoff(z), z), 0.044 * k, 0.066 * k, 16, p=2.3))
    haft = g.rings_mesh("hatchet_haft", rings, cap_start="flat", cap_end="flat")
    grip_zone = lambda co: smoothstep(-0.45, -0.25, co.z) * smoothstep(0.5, 0.3, co.z)
    g.piece(haft, M.WOOD, axis=(0, 0, 1), bevr=0.008, a={"a1": grip_zone})
    wedge = g.box("hatchet_wedge", (0.07, 0.006, 0.02), loc=(0, 0.0, 1.73))
    g.piece(wedge, M.STEEL, bevr=0.002)
    # head: horizontal slices from the beard heel (z 1.18) to the toe (z 1.72)
    zh = [1.18, 1.2, 1.23, 1.27, 1.31, 1.35, 1.39, 1.42, 1.46, 1.51, 1.56, 1.6, 1.625, 1.65, 1.675, 1.698, 1.72]
    yf = lambda z: curve([(1.18, 0.40), (1.26, 0.462), (1.36, 0.492), (1.46, 0.5), (1.56, 0.494), (1.64, 0.478),
                          (1.72, 0.448)], z)

    def yb(z):
        if z <= 1.42:
            return curve([(1.18, 0.40), (1.21, 0.285), (1.25, 0.17), (1.3, 0.07), (1.35, -0.03), (1.39, -0.115),
                          (1.42, -0.15)], z)
        if z <= 1.6:
            return -0.15
        return lerp(-0.15, 0.448, ((z - 1.6) / 0.12) ** 1.6)
    sts = [(z, yb(z), yf(z)) for z in zh]
    th = lambda y: curve([(-0.2, 0.05), (0.07, 0.052), (0.16, 0.036), (0.3, 0.016), (0.44, 0.006), (0.5, 0.003)], y)

    def section(s, z, y0, y1):
        w = max(y1 - y0, 1e-4)
        ys = [y0, y0 + min(0.006, w * 0.1), lerp(y0, y1, 0.25), lerp(y0, y1, 0.5), lerp(y0, y1, 0.72),
              y1 - min(0.03, w * 0.15), y1]
        out = []
        for i, y in enumerate(ys):
            h = th(y)
            if i == 0:
                h *= 0.9
            if i == len(ys) - 1:
                h = 0.0007
            out.append((y, max(h, 0.0007)))
        return out
    head = g.blade("hatchet_head", sts, section, edges=("front",), band=0.034)
    g.piece(head, M.IRON, axis=(0, 1, 0), bevr=0.005)
    lib.part(root, [head, wedge], "Steel", SET, weight=1.1)
    lib.part(root, [haft], "Wood", SET, weight=0.95, smooth=50)
    lib.params(root, M.IRON, dict(rust=0.3, ground=1.0, ground_wav=0.04, edge_wear=0.45, hammer=22.0))
    lib.params(root, M.WOOD, dict(light=g_c(184, 146, 100), dark=g_c(140, 100, 62), rings=22.0, grime=0.75))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, 0.5, 1.46), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ spear
def spear(lib):
    root = lib.begin("spear", "Weapon", tags=["Melee", "Thrown", "Polearm"], held=True,
                     notes="7-stud ash spear: hand-forged leaf head with a diamond midrib and bright honed edges on a "
                           "riveted conical socket, cord binding, leather grip at the balance point (origin), torn "
                           "red rag, iron butt spike.")
    rad = lambda z: lerp(0.05, 0.044, (z + 2.52) / 5.92)
    shafts = []
    for nm, zs, w in (("lo", [-2.52, -2.0, -1.4, -0.8, -0.4], 0.45), ("mid", [-0.4, 0.0, 0.4], 0.12),
                      ("hi", [0.4, 0.9, 1.5, 2.1, 2.7, 3.14, 3.4], 0.62)):
        sh = g.rings_mesh("spear_shaft_" + nm, [g.ring((0, 0, z), rad(z), rad(z), 12) for z in zs],
                          cap_start="flat", cap_end="flat")
        g.noise_displace(sh, 0.0025, 0.4, seed=3)
        g.piece(sh, M.WOOD, axis=(0, 0, 1), bevr=0.006, uvw=w, rnd=0.37)
        shafts.append(sh)
    wrap = g.ribbed_grip("spear_wrap", -0.4, 0.4, 0.061, 0.061, segs=10, ribs=11, depth=0.0035, rows_per_rib=2,
                         tilt=0.5)
    g.piece(wrap, M.LEATHER, axis=(0, 0, 1), bevr=0.005, a={"a0": g.angle_attr(wrap)})
    binding = g.ribbed_grip("spear_binding", 3.14, 3.31, 0.054, 0.054, segs=10, ribs=9, depth=0.003, rows_per_rib=2,
                            tilt=0.5)
    g.piece(binding, M.CORD, axis=(0, 0, 1), bevr=0.003, a={"a0": g.angle_attr(binding)})
    socket = g.lathe("spear_socket", [(0.0, 3.27), (0.058, 3.27), (0.062, 3.29), (0.06, 3.36), (0.05, 3.5),
                                      (0.038, 3.6), (0.03, 3.66), (0.0, 3.68)], segs=14)
    rivet = g.lathe("spear_rivet", [(0.0, 0.0), (0.014, 0.0), (0.012, 0.006), (0.0, 0.01)], segs=8)
    g.orient_to(rivet, (0.058, 0, 3.4), (1, 0, 0), (0, 0, 1))
    butt = g.lathe("spear_butt", [(0.0, -2.62), (0.012, -2.61), (0.036, -2.57), (0.054, -2.5), (0.056, -2.42),
                                  (0.0, -2.41)], segs=14)
    g.piece(socket, M.IRON, axis=(0, 0, 1), bevr=0.005, shade=50)
    g.piece(rivet, M.IRON, bevr=0.002, shade=60)
    g.piece(butt, M.IRON, bevr=0.005, shade=50)
    z0, z1 = 3.6, 4.40
    hw = lambda s: curve([(0, 0.03), (0.1, 0.09), (0.32, 0.15), (0.58, 0.122), (0.85, 0.06), (1.0, 0.0)], s)
    sts = g.stations(z0, z1, 14, lambda s: -hw(s), hw, power=1.15)

    def section(s, z, yb, yf):
        w = max(yf - yb, 1e-4)
        h = lerp(0.022, 0.006, s)
        return [(yb, 0.0006), (yb + w * 0.1, 0.0022), (yb + w * 0.32, h * 0.45), (yb + w * 0.5, h),
                (yf - w * 0.32, h * 0.45), (yf - w * 0.1, 0.0022), (yf, 0.0006)]
    head = g.blade("spear_head", sts, section, edges=("front", "back"), band=0.02)
    g.piece(head, M.IRON, axis=(0, 0, 1), bevr=0.003)
    # torn rag: two strips knotted round the shaft below the binding
    import items_kit as kit
    knot = g.torus("spear_knot", 0.056, 0.019, segs=14, minor_segs=6, center=(0, 0, 3.07))
    sa = g.sweep("spear_rag_a", g.smooth_path([(0.05, 0.01, 3.06), (0.08, 0.03, 2.96), (0.1, 0.05, 2.82),
                                               (0.11, 0.03, 2.66), (0.13, 0.06, 2.5)], 12),
                 kit.rrect(0.1, 0.008, 0.003), lambda t: (1.0 - 0.45 * t, 1.0), up=(0, 1, 0))
    sb = g.sweep("spear_rag_b", g.smooth_path([(0.03, -0.05, 3.06), (0.05, -0.08, 2.97), (0.065, -0.098, 2.85),
                                               (0.085, -0.09, 2.74)], 10),
                 kit.rrect(0.08, 0.008, 0.003), lambda t: (1.0 - 0.5 * t, 1.0), up=(1, -0.6, 0))
    for o in (knot, sa, sb):
        g.jitter(o, 0.0025)
        g.piece(o, M.CANVAS, axis=(0, 0, 1), bevr=0.002)
    lib.part(root, [head, socket, rivet, butt], "Steel", SET, weight=1.1)
    lib.part(root, shafts + [wrap, binding, knot, sa, sb], "Wood", SET, weight=1.0, smooth=50)
    lib.params(root, M.IRON, dict(rust=0.35, ground=1.0, edge_wear=0.8, hammer=30.0))
    lib.params(root, M.WOOD, dict(light=g_c(190, 156, 112), dark=g_c(150, 112, 74), rings=18.0, grime=0.5))
    lib.params(root, M.LEATHER, dict(color=g_c(110, 72, 44), spiral=11.0 / 0.8, crease=0.4))
    lib.params(root, M.CORD, dict(color=g_c(150, 126, 90), turns=12 / 0.17))
    lib.params(root, M.CANVAS, dict(color=g_c(142, 40, 30), threads=60.0, stains=0.5))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, 0, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ mace
def mace(lib):
    root = lib.begin("mace", "Weapon", tags=["Melee", "Blunt"], held=True,
                     notes="Forged flanged mace: six pointed flanges on an iron core with a top spike, collar and "
                           "riveted langets down an oak haft, leather-wrapped grip, iron pommel. Grip at origin, a flange "
                           "faces +Y.")
    zs = [-0.36, -0.3, 0.0, 0.34, 0.4, 0.8, 1.2, 1.5, 1.74]
    haft = g.rings_mesh("mace_haft", [g.ring((0, 0, z), 0.052, 0.052, 12) for z in zs], cap_start="flat", cap_end="flat")
    g.piece(haft, M.WOOD, axis=(0, 0, 1), bevr=0.006)
    wrap = g.ribbed_grip("mace_wrap", -0.3, 0.34, 0.062, 0.062, segs=12, ribs=9, depth=0.0035, rows_per_rib=2, tilt=0.5)
    g.piece(wrap, M.LEATHER, axis=(0, 0, 1), bevr=0.005, a={"a0": g.angle_attr(wrap)})
    pommel = g.lathe("mace_pommel", [(0.0, -0.43), (0.04, -0.428), (0.07, -0.41), (0.08, -0.38), (0.074, -0.345),
                                     (0.062, -0.32), (0.06, -0.298), (0.0, -0.296)], segs=14)
    collar = g.lathe("mace_collar", [(0.0, 1.5), (0.06, 1.5), (0.072, 1.51), (0.072, 1.56), (0.062, 1.58),
                                     (0.062, 1.63), (0.074, 1.65), (0.074, 1.7), (0.0, 1.71)], segs=14)
    core = g.lathe("mace_core", [(0.0, 1.7), (0.064, 1.7), (0.09, 1.74), (0.12, 1.84), (0.128, 1.94), (0.12, 2.04),
                                 (0.092, 2.12), (0.056, 2.16), (0.0, 2.17)], segs=16)
    pieces = [pommel, collar, core]
    import ls_common as ls
    prof = [(0.07, 1.74), (0.15, 1.775), (0.215, 1.86), (0.232, 1.95), (0.226, 2.0), (0.19, 2.08), (0.11, 2.15),
            (0.06, 2.13)]
    for k in range(6):
        f = ls.extrude_profile("mace_flange%d" % k, prof, 0.044)
        ls.bevel(f, width=0.009, segments=1, angle_deg=30)
        g.place(f, rot=(0, 0, D(90 + 60 * k)))
        pieces.append(f)
    spike = g.lathe("mace_spike", [(0.0, 2.11), (0.05, 2.12), (0.052, 2.15), (0.03, 2.26), (0.0, 2.38)], segs=12)
    pieces.append(spike)
    for sx in (-1, 1):
        lg = g.cbox("mace_langet", (0.012, 0.034, 0.36), 0.003, loc=(sx * 0.056, 0, 1.33))
        pieces.append(lg)
    for p in pieces:
        rounded = p.name.startswith(("mace_pommel", "mace_collar", "mace_core", "mace_spike"))
        g.piece(p, M.IRON, axis=(0, 0, 1), bevr=0.005, shade=50 if rounded else None)
    lib.part(root, pieces, "Steel", SET, weight=1.0)
    lib.part(root, [haft, wrap], "Wood", SET, weight=1.0, smooth=50)
    lib.params(root, M.IRON, dict(rust=0.4, edge_wear=1.0, hammer=24.0))
    lib.params(root, M.WOOD, dict(light=g_c(132, 96, 62), dark=g_c(90, 62, 40), rings=30.0))
    lib.params(root, M.LEATHER, dict(color=g_c(64, 44, 32), spiral=9.0 / 0.64, crease=0.4))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, 0, 2.38), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ sword
def sword(lib):
    root = lib.begin("sword", "Weapon", tags=["Melee", "Blade"], held=True,
                     notes="Arming sword: lenticular blade with a fuller, honed edges, forged crossguard, leather "
                           "grip over cord risers with cord-bound ends, aged brass wheel pommel with a peened tang. "
                           "Grip at origin.")
    z0, z1 = 0.46, 3.05
    hw = lambda s: curve([(0, 0.112), (0.1, 0.108), (0.7, 0.09), (0.86, 0.075), (0.95, 0.04), (1.0, 0.0)], s)
    sts = g.stations(z0, z1, 18, lambda s: -hw(s), hw, power=1.3)

    def section(s, z, yb, yf):
        w = max(yf - yb, 1e-4)
        h = lerp(0.0125, 0.0055, s)
        d = 0.0035 * (1.0 - smoothstep(0.5, 0.66, s)) * smoothstep(0.0, 0.02, s)
        return [(yb, 0.0005), (yb + w * 0.07, 0.0018), (yb + w * 0.28, h * 0.72), (yb + w * 0.36, h),
                (yb + w * 0.42, h - d), (yb + w * 0.5, h - d * 1.15), (yf - w * 0.42, h - d), (yf - w * 0.36, h),
                (yf - w * 0.28, h * 0.72), (yf - w * 0.07, 0.0018), (yf, 0.0005)]
    bl = g.blade("sword_blade", sts, section, edges=("front", "back"), band=0.02)
    g.piece(bl, M.STEEL, axis=(0, 0, 1), bevr=0.002)
    ys = [-0.37, -0.355, -0.33, -0.25, -0.12, 0.0, 0.12, 0.25, 0.33, 0.355, 0.37]
    gpath = [(0, y, 0.43 + 0.045 * (y / 0.37) ** 2) for y in ys]
    gs = lambda t: curve([(0, 1.0), (0.35, 0.8), (0.82, 0.64), (0.92, 0.9), (1.0, 0.72)], abs(2 * t - 1))
    import items_kit as kit
    guard = g.sweep("sword_guard", gpath, kit.rrect(0.07, 0.06, 0.018), lambda t: (gs(t), gs(t)))
    g.piece(guard, M.IRON, axis=(0, 1, 0), bevr=0.006, shade=50)
    # grip: swelled core with three cord risers under the leather
    zg0, zg1 = -0.4, 0.405
    rows = []
    zz = [zg0 + (zg1 - zg0) * i / 22.0 for i in range(23)]
    risers = (-0.2, 0.0, 0.2)
    for z in zz:
        t = (z - zg0) / (zg1 - zg0)
        base = 1.0 + 0.07 * math.sin(math.pi * t)
        bump = sum(math.exp(-((z - zr) / 0.02) ** 2) for zr in risers) * 0.06
        k = base + bump
        rows.append(g.ring((0, 0, z), 0.044 * k, 0.054 * k, 12, p=2.2))
    grip = g.rings_mesh("sword_grip", rows, cap_start="flat", cap_end="flat")
    g.piece(grip, M.LEATHER, axis=(0, 0, 1), bevr=0.005, a={"a1": lambda co: math.atan2(co.x, -co.y)})
    cords = []
    for i, (za, zb2) in enumerate(((0.33, 0.405), (-0.4, -0.33))):
        c = g.ribbed_grip("sword_cord%d" % i, za, zb2, 0.0485, 0.0585, segs=12, ribs=5, depth=0.003, rows_per_rib=2,
                          tilt=0.4)
        g.piece(c, M.CORD, axis=(0, 0, 1), bevr=0.003, a={"a0": g.angle_attr(c)})
        cords.append(c)
    # wheel pommel: disc with its axis along X, raised bosses
    prof = [(0.0, -0.032), (0.05, -0.032), (0.07, -0.026), (0.1, -0.024), (0.112, -0.012), (0.114, 0.0),
            (0.112, 0.012), (0.1, 0.024), (0.07, 0.026), (0.05, 0.032), (0.0, 0.032)]
    pom = g.lathe("sword_pommel", prof, segs=18)
    g.orient_to(pom, (0, 0, -0.5), (1, 0, 0), (0, 0, 1))
    peen = g.lathe("sword_peen", [(0.0, -0.632), (0.016, -0.63), (0.02, -0.62), (0.02, -0.6), (0.0, -0.6)], segs=8)
    g.piece(pom, M.BRASS, axis=(1, 0, 0), bevr=0.006, shade=50)
    g.piece(peen, M.IRON, bevr=0.002, shade=60)
    lib.part(root, [bl, guard, pom, peen], "Steel", SET, weight=0.85)
    lib.part(root, [grip] + cords, "Leather", SET, weight=1.2, smooth=55)
    lib.params(root, M.STEEL, dict(bright=0.6, patina=0.35, wear=0.6, rust=0.3, pits=0.2))
    lib.params(root, M.IRON, dict(rust=0.25, edge_wear=0.9, hammer=40.0))
    lib.params(root, M.LEATHER, dict(color=g_c(70, 44, 30), seam=True, crease=0.5, polish=0.6))
    lib.params(root, M.CORD, dict(color=g_c(60, 46, 34), turns=7 / 0.075))
    _grip(lib, root)
    lib.attach(root, "Tip", (0, 0, z1), look=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ bow
def bow(lib):
    root = lib.begin("bow", "Weapon", tags=["Ranged", "Bow"], held=True,
                     notes="Traditional recurve: ash limbs with horn tip overlays, walnut riser with an arrow shelf, "
                           "stitched leather grip, waxed linen string with dark centre serving and a brass nock point. "
                           "Grip at origin; string centre / Nock at z = 0.2 so the arrow clears the hand; ArrowRest on "
                           "the -X side of the riser window. bow_Rope = string + serving + nock bead (hide it while "
                           "drawing and draw Beams StringTop -> Nock -> StringBottom).")
    zc = 0.20
    y_s = -0.4168
    zn = 2.12
    import items_kit as kit
    main = []
    for k in range(18):
        zr = lerp(0.6, zn, k / 17.0)
        y = curve([(0.6, 0.0), (0.95, -0.02), (1.3, -0.1), (1.65, -0.235), (1.95, -0.35), (zn, -0.393)], zr)
        main.append((y, zr))
    ear = [(-0.391, 2.16), (-0.381, 2.198), (-0.36, 2.228), (-0.334, 2.25)]
    limb_yz = main + ear
    width = lambda t: curve([(0, 0.13), (0.75, 0.084), (1.0, 0.06)], t)
    thick = lambda t: curve([(0, 0.05), (0.7, 0.032), (1.0, 0.026)], t)
    sec = kit.rrect(1.0, 1.0, 0.32)
    pieces_wood, pieces_horn = [], []
    n_main = len(main)
    for sgn, nm in ((1, "up"), (-1, "dn")):
        pts = [(0, y, zc + sgn * z) for (y, z) in limb_yz]
        L = [0.0]
        for a, b in zip(limb_yz, limb_yz[1:]):
            L.append(L[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
        tot = L[-1]
        split = n_main - 3
        t_split = L[split] / tot
        limb = g.sweep("bow_limb_" + nm, pts[:split + 1], sec, lambda t, ts=t_split: (width(t * ts), thick(t * ts)))
        tip = g.sweep("bow_tip_" + nm, pts[split:], sec,
                      lambda t, ts=t_split: (width(ts + t * (1 - ts)) * 1.04, thick(ts + t * (1 - ts)) * 1.12))
        g.piece(limb, M.WOOD, axis=(0, 0, 1), bevr=0.006)
        g.piece(tip, M.HORN, axis=(0, 0, 1), bevr=0.004)
        pieces_wood.append(limb)
        pieces_horn.append(tip)
    rpath = [(0, 0.0, zc - 0.74), (0, 0.006, zc - 0.56), (0, 0.016, zc - 0.36), (0, 0.026, zc - 0.16),
             (0.042, 0.034, zc - 0.02), (0.05, 0.034, zc + 0.2), (0.024, 0.022, zc + 0.4), (0, 0.006, zc + 0.56),
             (0, 0.0, zc + 0.74)]
    rs = lambda t: (curve([(0, 1.2), (0.12, 1.08), (0.3, 1.0), (0.5, 0.95), (0.7, 1.0), (0.88, 1.08), (1.0, 1.2)], t),
                    curve([(0, 0.62), (0.12, 0.8), (0.3, 1.0), (0.5, 1.1), (0.7, 1.0), (0.88, 0.8), (1.0, 0.62)], t))
    riser = g.sweep("bow_riser", g.smooth_path(rpath, 24), kit.rrect(0.11, 0.16, 0.04), rs)
    g.piece(riser, M.WOOD, axis=(0, 0, 1), bevr=0.008, a={"a2": 1.0})
    wrap = g.ribbed_grip("bow_wrap", -0.17, 0.13, 0.066, 0.09, segs=16, ribs=3, depth=0.002, rows_per_rib=4,
                         offset=(0, 0.022))
    g.piece(wrap, M.LEATHER, axis=(0, 0, 1), bevr=0.005, a={"a1": lambda co: math.atan2(co.x, -(co.y - 0.022))})
    # string, serving, loops, nock bead
    st_top, st_bot = zc + zn + 0.01, zc - zn - 0.01
    string = g.rings_mesh("bow_string", [g.ring((0, y_s, z), 0.0068, 0.0068, 8) for z in
                                         (st_bot, zc - 0.26, zc + 0.26, st_top)], cap_start="flat", cap_end="flat")
    g.piece(string, M.STRING, axis=(0, 0, 1), bevr=0.002)
    serve = g.rings_mesh("bow_serving", [g.ring((0, y_s, z), 0.0086, 0.0086, 8) for z in
                                         (zc - 0.25, zc - 0.24, zc + 0.24, zc + 0.25)], cap_start="flat", cap_end="flat")
    g.piece(serve, M.STRING, axis=(0, 0, 1), bevr=0.002, a={"a0": 1.0})
    bead = g.lathe("bow_nockbead", [(0.0, 0.035), (0.016, 0.035), (0.019, 0.05), (0.016, 0.065), (0.0, 0.065)], segs=10)
    g.place(bead, loc=(0, y_s, zc))
    g.piece(bead, M.BRASS, bevr=0.002, shade=60)
    loops = []
    for sgn in (1, -1):
        lp = g.torus("bow_loop", 0.03, 0.0068, segs=12, minor_segs=6, center=(0, y_s + 0.022, zc + sgn * zn), sx=1.4)
        g.piece(lp, M.STRING, bevr=0.002)
        loops.append(lp)
    lib.part(root, pieces_wood + pieces_horn + [riser, wrap], "Wood", SET, weight=0.8, smooth=40)
    lib.part(root, [string, serve, bead] + loops, "Rope", SET, name="bow_Rope", weight=0.7, smooth=60,
             cast_shadow=False)
    lib.params(root, M.WOOD, dict(light=g_c(168, 130, 88), dark=g_c(118, 84, 54), rings=36.0, grime=0.55))
    lib.params(root, M.LEATHER, dict(color=g_c(96, 60, 38), seam=True, crease=0.6, polish=0.5))
    _grip(lib, root)
    lib.attach(root, "Nock", (0, y_s, zc), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "StringTop", (0, y_s, zc + zn), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "StringBottom", (0, y_s, zc - zn), look=(0, 0, -1), up=(0, 1, 0))
    lib.attach(root, "ArrowRest", (-0.04, 0.035, zc), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)


# ------------------------------------------------------------------------------------------------ arrow
def arrow(lib):
    root = lib.begin("arrow", "Ammo", tags=["Ranged", "Ammo"], held=True,
                     notes="Cedar arrow: horn nock insert (origin = nock throat = Grip = Nock; slot along Y), three "
                           "shield-cut turkey fletchings (barred red cock feather points +X), sinew bindings, socketed "
                           "steel broadhead. Align arrow +Y with the bow string.")
    shaft = g.rings_mesh("arrow_shaft", [g.ring((0, 0, z), 0.0165, 0.0165, 8) for z in (0.03, 0.8, 1.8, 2.79)],
                         cap_start="flat", cap_end="flat")
    g.piece(shaft, M.WOOD, axis=(0, 0, 1), bevr=0.003)
    nock = g.lathe("arrow_nock", [(0.0, -0.01), (0.017, -0.012), (0.021, 0.005), (0.02, 0.04), (0.0175, 0.07),
                                  (0.0, 0.072)], segs=10)
    prongs = [g.cbox("arrow_prong%d" % i, (0.014, 0.034, 0.05), 0.004, loc=(sx * 0.012, 0, -0.03))
              for i, sx in enumerate((-1, 1))]
    for p in [nock] + prongs:
        g.piece(p, M.HORN, axis=(0, 0, 1), bevr=0.002)
    import ls_common as ls
    prof = [(0.016, 0.14), (0.035, 0.16), (0.09, 0.28), (0.104, 0.44), (0.09, 0.58), (0.045, 0.665), (0.016, 0.685)]
    vanes = []
    for k in range(3):
        v = ls.extrude_profile("arrow_vane%d" % k, prof, 0.004)
        g.place(v, rot=(0, 0, D(120 * k)))
        g.piece(v, M.FEATHER, axis=(0, 0, 1), bevr=0.001, rnd=0.2 + 0.3 * k)
        vanes.append(v)
    binds = []
    for i, (za, zb) in enumerate(((0.105, 0.155), (0.66, 0.71))):
        b = g.ribbed_grip("arrow_bind%d" % i, za, zb, 0.0185, 0.0185, segs=8, ribs=8, depth=0.0015, rows_per_rib=2,
                          tilt=0.3)
        g.piece(b, M.WAX, axis=(0, 0, 1), bevr=0.002)
        binds.append(b)
    ferrule = g.lathe("arrow_ferrule", [(0.0, 2.7), (0.019, 2.7), (0.021, 2.72), (0.02, 2.79), (0.012, 2.83),
                                        (0.0, 2.835)], segs=10)
    g.piece(ferrule, M.IRON, axis=(0, 0, 1), bevr=0.003, shade=50)
    hw = lambda s: curve([(0, 0.016), (0.25, 0.058), (1.0, 0.0)], s)
    sts = g.stations(2.79, 3.0, 10, lambda s: -hw(s), hw, power=1.1)

    def section(s, z, yb, yf):
        w = max(yf - yb, 1e-4)
        h = lerp(0.007, 0.003, s)
        return [(yb, 0.0005), (yb + w * 0.2, 0.0016), (yb + w * 0.5, h), (yf - w * 0.2, 0.0016), (yf, 0.0005)]
    head = g.blade("arrow_head", sts, section, edges=("front", "back"), band=0.012)
    g.piece(head, M.STEEL, axis=(0, 0, 1), bevr=0.0015)
    lib.part(root, [shaft, nock] + prongs + vanes + binds, "Wood", SET, weight=0.9, smooth=55)
    lib.part(root, [ferrule, head], "Steel", SET, weight=1.0)
    lib.params(root, M.WOOD, dict(light=g_c(200, 164, 120), dark=g_c(168, 126, 86), rings=60.0, grime=0.2,
                                  edge_wear=0.3))
    lib.params(root, M.STEEL, dict(bright=0.5, patina=0.7, rust=0.4, pits=0.3))
    lib.params(root, M.FEATHER, dict(per_piece=[dict(color=g_c(150, 52, 38), bars=26.0, bar_col=g_c(70, 30, 22)),
                                                dict(color=g_c(206, 196, 176), bars=26.0, bar_col=g_c(96, 78, 60)),
                                                dict(color=g_c(206, 196, 176), bars=26.0, bar_col=g_c(96, 78, 60))]))
    lib.params(root, M.WAX, dict(color=g_c(120, 96, 66), rough=0.6))
    _grip(lib, root)
    lib.attach(root, "Nock", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "Tip", (0, 0, 3.0), look=(0, 0, 1))
    lib.finish(root)


BUILDERS = [knife, machete, hatchet, spear, mace, sword, bow, arrow, throwing_knife]
