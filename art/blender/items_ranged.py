"""
items_ranged.py - recurve bow and arrow for the Items category (built by items.py).
Bow: held vertically, hand grip at the origin, limbs along +/-Z, string on the -Y side, arrows fly +Y.
Arrow: origin at the nock throat (where the string sits), tip +Z.
"""
import math

import ls_common as ls
import items_kit as kit
from items_kit import curve, lerp

D = math.radians


def bow(lib):
    root = lib.begin_held("bow", "Weapon", tags=["Ranged", "Bow"],
                          notes="Recurve bow. Grip at origin (hand), string centre/nock at z=0.2 so the arrow passes "
                                "over the hand. Arrow rest on the -X side of the riser window.")
    zc = 0.20                     # string centre / arrow line height
    zn, ztip = 2.12, 2.25         # nock and ear tip, relative to zc
    main = []
    for k in range(14):
        zr = lerp(0.62, zn, k / 13.0)
        y = curve([(0.62, 0.0), (0.95, -0.02), (1.3, -0.1), (1.65, -0.235), (1.95, -0.345), (zn, -0.385)], zr)
        main.append((y, zr))
    ear = [(-0.383, 2.155), (-0.372, 2.195), (-0.35, 2.228), (-0.322, ztip)]
    limb_yz = main + ear
    lengths = [0.0]
    for (a, b) in zip(limb_yz, limb_yz[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    t_nock = lengths[len(main) - 1] / lengths[-1]
    width = lambda t: curve([(0, 0.15), (0.75, 0.098), (1.0, 0.074)], t)
    thick = lambda t: curve([(0, 0.08), (0.7, 0.054), (1.0, 0.042)], t)
    limb_scale = lambda t: (width(t), thick(t))
    sec = kit.rrect(1.0, 1.0, 0.3)
    upper = kit.sweep("bow_limb_up", [(0, y, zc + z) for (y, z) in limb_yz], sec, limb_scale)
    lower = kit.sweep("bow_limb_dn", [(0, y, zc - z) for (y, z) in limb_yz], sec, limb_scale)
    kit.part(lib, root, kit.join([upper, lower], "bow_limbs"), "Wood", rgb=(124, 88, 56), smooth=40)
    # riser with a sight window shifted to +X so the arrow can pass at x ~ -0.04
    rpath = [(0, 0.0, zc - 0.74), (0, 0.006, zc - 0.56), (0, 0.016, zc - 0.36), (0, 0.026, zc - 0.16),
             (0.042, 0.034, zc - 0.02), (0.05, 0.034, zc + 0.2), (0.024, 0.022, zc + 0.4), (0, 0.006, zc + 0.56),
             (0, 0.0, zc + 0.74)]
    rs = lambda t: (curve([(0, 1.45), (0.12, 1.16), (0.3, 1.0), (0.5, 0.95), (0.7, 1.0), (0.88, 1.16), (1.0, 1.45)], t),
                    curve([(0, 0.72), (0.12, 0.85), (0.3, 1.0), (0.5, 1.1), (0.7, 1.0), (0.88, 0.85), (1.0, 0.72)], t))
    riser = kit.sweep("bow_riser", rpath, kit.rrect(0.12, 0.17, 0.04), rs)
    kit.part(lib, root, riser, "Wood", rgb=(84, 56, 38), smooth=40)
    wrap = kit.wrap_grip("bow_wrap", -0.17, 0.13, 0.072, 0.096, bands=5, bulge=0.009, offset=(0, 0.022))
    kit.part(lib, root, wrap, "Leather", smooth=50)
    # string: touches the limb belly at the nocks, thicker serving around the nocking point
    y_s = -0.385 - thick(t_nock) / 2.0 - 0.009
    spath = [(0, y_s, zc + zn + 0.012), (0, y_s, zc + 0.27), (0, y_s, zc + 0.25), (0, y_s, zc - 0.25),
             (0, y_s, zc - 0.27), (0, y_s, zc - zn - 0.012)]
    total = (zn + 0.012) * 2.0
    sscale = lambda t: (1.4, 1.4) if abs(t * total - total / 2.0) < 0.255 else (1.0, 1.0)
    string = kit.sweep("bow_string", spath, kit.circle(6, 0.018), sscale)
    kit.part(lib, root, string, "Rope", smooth=60, shadow=False)
    bead = kit.revolve("bow_nockbead", [(0.0, 0.035), (0.026, 0.035), (0.03, 0.05), (0.026, 0.065), (0.0, 0.065)], segs=8)
    kit.place(bead, loc=(0, y_s, zc))
    kit.part(lib, root, bead, "Brass", smooth=40, shadow=False)
    kit.grip(lib, root)
    lib.attach(root, "Nock", (0, y_s, zc), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "StringTop", (0, y_s, zc + zn), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "StringBottom", (0, y_s, zc - zn), look=(0, 0, -1), up=(0, 1, 0))
    lib.attach(root, "ArrowRest", (-0.04, 0.035, zc), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)


def arrow(lib):
    root = lib.begin_held("arrow", "Ammo", tags=["Ranged", "Ammo"],
                          notes="Arrow. Origin = nock throat (Grip and Nock), tip +Z. Nock slot runs along Y "
                                "(align arrow +Y with the bow string); red cock feather points +X.")
    shaft = kit.sweep("arrow_shaft", [(0, 0, 0.04), (0, 0, 2.76)], kit.circle(6, 0.035))
    kit.part(lib, root, shaft, "Wood", rgb=(164, 134, 96), smooth=60)
    bulb = kit.revolve("arrow_nock", [(0.034, 0.0), (0.041, 0.02), (0.041, 0.06), (0.037, 0.09), (0.034, 0.11)], segs=8)
    prongs = [kit.chamfer_box("arrow_prong%d" % i, (0.026, 0.07, 0.064), 0.008, loc=(sx * 0.024, 0, -0.022))
              for i, sx in enumerate((-1, 1))]
    kit.part(lib, root, kit.join([bulb] + prongs, "arrow_nockparts"), "DarkLeather", smooth=40)
    prof = [(0.03, 0.14), (0.058, 0.16), (0.112, 0.28), (0.122, 0.44), (0.1, 0.58), (0.05, 0.665), (0.03, 0.685)]
    vanes = []
    for k in range(3):
        v = ls.extrude_profile("arrow_vane%d" % k, prof, 0.022)
        kit.place(v, rot=(0, 0, D(120 * k)))
        vanes.append(v)
    kit.part(lib, root, kit.join(vanes[1:], "arrow_vanes"), "Feather", smooth=None, shadow=False)
    kit.part(lib, root, vanes[0], "Feather", rgb=(178, 64, 42), shadow=False)
    bind = [kit.wrap_grip("arrow_bind%d" % i, z, z + 0.045, 0.04, 0.04, bands=2, bulge=0.004, tilt_deg=8)
            for i, z in enumerate((0.105, 0.675))]
    kit.part(lib, root, kit.join(bind, "arrow_binding"), "Rope", smooth=55, shadow=False)
    ferrule = kit.revolve("arrow_ferrule", [(0.036, 2.71), (0.043, 2.72), (0.043, 2.78), (0.03, 2.84)], segs=8)
    kit.part(lib, root, ferrule, "Metal", smooth=40)
    hw = lambda s: curve([(0, 0.03), (0.22, 0.082), (1.0, 0.0)], s)
    sts = kit.stations(2.8, 3.0, 8, lambda s: -hw(s), hw, power=1.1)
    hx = lambda s, u, y: lerp(0.034, 0.02, s) * max(0.14, 1.0 - abs(2.0 * u - 1.0))
    head, _ = kit.blade("arrow_head", sts, hx, across=(0.0, 0.5, 1.0))
    kit.part(lib, root, head, "Steel", rgb=(176, 178, 182))
    kit.grip(lib, root)
    lib.attach(root, "Nock", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "Tip", (0, 0, 3.0), look=(0, 0, 1))
    lib.finish(root)


BUILDERS = [bow, arrow]
