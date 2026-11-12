"""br_tower.py - Watchtower (BuildingsReal): a timber fire-lookout tower on a ridge.

Four weathered, slightly bowed peeled-pole legs splayed on concrete footings (anchor bolts), sawn girts and X-bracing
fixed with square-headed steel carriage bolts (front bottom bay left open as the walk-in bay, knee braces only), a
plank deck at z = 22 in four Box groups round a 2.5 x 2.5 ladder well, a sawn railing, the legs carried on as roof
posts to a small hip roof of cedar shakes, and a pole ladder from the ground to the deck. Front = +Y.
"""
import math
import random

from mathutils import Vector as V

import br_kit as K

TAU = 2.0 * math.pi
DECK = 22.0
B, T = 6.0, 4.3                 # leg half-spread at the ground / at the deck
FOOT = 0.9                      # footing top
WELL = (0.5, 3.0, -3.0, -0.5)   # ladder well x0, x1, y0, y1
DECK_E = 5.6                    # deck half-size
Z_POST = 29.0                   # roof post tops
EAVE, Z_EAVE, Z_APEX = 6.1, 27.95, 31.75


def leg(sx, sy, z):
    h = B + (T - B) * (z / DECK)
    return V((sx * h, sy * h, z))


CORNERS = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
SIDES = [((1, 1), (-1, 1), V((0, 1, 0))), ((-1, 1), (-1, -1), V((-1, 0, 0))), ((-1, -1), (1, -1), V((0, -1, 0))),
         ((1, -1), (1, 1), V((1, 0, 0)))]


def ends(rng):
    return K.R("Log", "end_%d" % rng.randrange(6))


def esq(rng):
    return K.R("Wood", "end_sq_%d" % rng.randrange(8))


def deck_group(mb, x0, x1, y0, y1, rng):
    """Deck boards running along Y (Box part), every row one board wide."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
    K.board_box(mb, (cx - hy, cy - hx, DECK - 0.22), (cx + hy, cy + hx, DECK), K.R("Wood", "board_grey"), board=0.74,
                rz=math.pi / 2, c=(cx, cy, 0.0), rng=rng, z_rows=1)


def build(lib):
    rng = random.Random(5201)
    root = lib.begin("Watchtower", kind="Building", tags=["Lookout"],
                     notes="Timber fire lookout. Deck top z = 22 (four Box plank groups) with a 2.5 x 2.5 ladder "
                           "well at x 0.5..3.0, y -3.0..-0.5: place a 2x22x2 TrussPart (Transparency 1) from "
                           "LadderBase to LadderTop; the pole ladder is visual only. Walk in through the open front "
                           "(+Y) bottom bay. Roof is Hull; bolts, joists, roof frame and shakes do not collide.")
    pole = K.R("Log", "pole")
    beam, grey = K.R("Wood", "beam"), K.R("Wood", "board_grey")
    iron = K.MB("Kit")
    ireg = K.R("Kit", "iron")

    # ---------------- legs (continue up as roof posts), bowed peeled poles
    legs = K.MB("Log")
    for (sx, sy) in CORNERS:
        K.log(legs, leg(sx, sy, FOOT - 0.02), leg(sx, sy, Z_POST), 0.47, 0.36, reg=pole, end_reg=(ends(rng), ends(rng)),
              segs=10, rings=5, rng=rng, up=(1, 0, 0), bow=0.07, oval=0.05, wob=0.03, chamfer=(0.0, 0.06))
    K.part(lib, root, legs, "Logs", collision="PreciseConvexDecomposition", smooth_angle=60,
           notes="Four peeled-pole legs, continued as roof posts.")

    # ---------------- concrete footings with anchor straps
    st = K.MB("Stone")
    conc = K.R("Stone", "concrete")
    for (sx, sy) in CORNERS:
        p = leg(sx, sy, 0.0)
        lo_o = [(p.x - 0.95, p.y - 0.95), (p.x + 0.95, p.y - 0.95), (p.x + 0.95, p.y + 0.95), (p.x - 0.95, p.y + 0.95)]
        hi_o = [(p.x - 0.72, p.y - 0.72), (p.x + 0.72, p.y - 0.72), (p.x + 0.72, p.y + 0.72), (p.x - 0.72, p.y + 0.72)]
        n = 4
        lo = [st.v((x, y, -0.04)) for (x, y) in lo_o]
        hi = [st.v((x, y, FOOT)) for (x, y) in hi_o]
        s = rng.uniform(0, 20)
        for i in range(n):
            j = (i + 1) % n
            st.f((lo[i], lo[j], hi[j], hi[i]), [K.suv(conc, s, 0.0), K.suv(conc, s + 1.9, 0.0), K.suv(conc, s + 1.44, 1.0),
                                                K.suv(conc, s + 0.24, 1.0)], conc)
            s += 1.9
        st.f(hi, [K.box_uv_face(conc, V((0, 0, 1)), st.co[k], V((p.x - 1, p.y - 1, 0)), 1.0, (0, 2)) for k in hi], conc)
        for (dx, dy) in ((1, 0), (-1, 0)):
            q = V((p.x + dx * 0.5, p.y, FOOT))
            K.timber(iron, q - V((0, 0, 0.02)), q + V((0, 0, 0.75)), 0.3, 0.06, ireg, ireg, up=(dx, 0, 0), ch=0.0,
                     rng=rng)
            K.bolt(iron, q + V((dx * 0.03, 0, 0.45)), (dx, 0, 0), ireg, r=0.06, h=0.05, rng=rng)
    K.part(lib, root, st, "Concrete", collision="Box", smooth_angle=20, notes="Concrete footings.")

    # ---------------- girts, X-braces, knee braces (sawn timber) + carriage bolts
    frame = K.MB("Wood")
    bays = [(FOOT + 0.6, 7.5), (7.5, 15.0), (15.0, DECK - 1.0)]

    def bolt_at(p, n):
        K.bolt(iron, p, n, ireg, r=0.055, h=0.045, rng=rng)
    for (c1, c2, n) in SIDES:
        for z in (7.5, 15.0):
            a, b = leg(*c1, z) + n * 0.42, leg(*c2, z) + n * 0.42
            K.timber(frame, a, b, 0.42, 0.26, beam, esq(rng), up=n, ch=0.03, rng=rng, ext=0.42)
            for p in (a, b):
                bolt_at(p + n * 0.13 + (b - a).normalized() * (0.0), n)
        for bi, (za, zb) in enumerate(bays):
            if n.y > 0.5 and bi == 0:
                for (ca, cb) in ((c1, c2), (c2, c1)):
                    pa = leg(*ca, 4.8) + n * 0.42
                    pb = leg(*ca, 7.5) + (leg(*cb, 7.5) - leg(*ca, 7.5)).normalized() * 2.4 + n * 0.42
                    K.timber(frame, pa, pb, 0.3, 0.2, grey, esq(rng), up=n, ch=0.025, rng=rng, ext=0.15)
                    bolt_at(pa + n * 0.1, n)
                    bolt_at(pb + n * 0.1, n)
                continue
            a0, b0 = leg(*c1, za) + n * 0.42, leg(*c2, zb) + n * 0.42
            a1, b1 = leg(*c2, za) + n * 0.62, leg(*c1, zb) + n * 0.62
            K.timber(frame, a0, b0, 0.32, 0.2, grey, esq(rng), up=n, ch=0.025, rng=rng, ext=0.2)
            K.timber(frame, a1, b1, 0.32, 0.2, grey, esq(rng), up=n, ch=0.025, rng=rng, ext=0.2)
            for p in (a0, b0):
                bolt_at(p + n * 0.1, n)
            for p in (a1, b1):
                bolt_at(p + n * 0.1, n)
            # where the two braces cross
            mid = (a1 + b1) / 2
            bolt_at(mid + n * 0.1, n)
    K.part(lib, root, frame, "Wood", collision="PreciseConvexDecomposition", smooth_angle=30,
           notes="Girts, X-braces and knee braces (front bottom bay open).")

    # ---------------- deck framing (visual), deck boards (4 Box groups), railing (4 Box sides)
    under = K.MB("Wood")
    for (c1, c2, n) in SIDES:
        K.timber(under, leg(*c1, DECK - 0.62) + n * 0.42, leg(*c2, DECK - 0.62) + n * 0.42, 0.62, 0.3, beam, esq(rng),
                 up=n, ch=0.03, rng=rng, ext=0.85)
    for x in (-4.6, -2.3, WELL[0] - 0.15, WELL[1] + 0.15, 4.6):
        K.timber(under, (x, -DECK_E + 0.15, DECK - 0.4), (x, DECK_E - 0.15, DECK - 0.4), 0.36, 0.3, grey, esq(rng),
                 up=(0, 0, 1), ch=0.02, rng=rng)
    for y in (WELL[2] - 0.15, WELL[3] + 0.15):
        K.timber(under, (WELL[0] - 0.3, y, DECK - 0.4), (WELL[1] + 0.3, y, DECK - 0.4), 0.3, 0.3, grey, esq(rng),
                 up=(0, 0, 1), ch=0.02, rng=rng)
    K.part(lib, root, under, "Wood", collide=False, smooth_angle=30, notes="Deck ring beams and joists (visual).")
    x0, x1, y0, y1 = WELL
    for (gx0, gx1, gy0, gy1) in ((-DECK_E, x0, -DECK_E, DECK_E), (x1, DECK_E, -DECK_E, DECK_E),
                                 (x0, x1, y1, DECK_E), (x0, x1, -DECK_E, y0)):
        g = K.MB("Wood")
        deck_group(g, gx0, gx1, gy0, gy1, rng)
        K.part(lib, root, g, "Planks", collision="Box", tags=["Floor"], smooth_angle=30, notes="Deck boards.")
    q = DECK_E - 0.2
    for (c1, c2, n) in SIDES:
        rail = K.MB("Wood")
        a, b = V((c1[0] * q, c1[1] * q, DECK)), V((c2[0] * q, c2[1] * q, DECK))
        mid = (a + b) / 2
        for p in (a.lerp(b, 0.25), mid, a.lerp(b, 0.75)):
            K.timber(rail, p, p + V((0, 0, 3.45)), 0.3, 0.3, beam, esq(rng), up=n, ch=0.03, rng=rng)
        for p in (a, b):
            K.timber(rail, p, p + V((0, 0, 3.45)), 0.34, 0.34, beam, esq(rng), up=n, ch=0.03, rng=rng)
        for (z, wv) in ((3.32, 0.3), (1.8, 0.26)):
            K.timber(rail, a + V((0, 0, z)) + n * 0.17, b + V((0, 0, z)) + n * 0.17, wv, 0.14, grey, esq(rng), up=n,
                     ch=0.02, rng=rng, ext=0.15)
        K.timber(rail, a + V((0, 0, 3.55)), b + V((0, 0, 3.55)), 0.42, 0.12, grey, esq(rng), up=(0, 0, 1), ch=0.02,
                 rng=rng, ext=0.2)
        K.part(lib, root, rail, "Planks", collision="Box", smooth_angle=30, notes="Deck railing (3.6 tall).")

    # ---------------- roof frame (plates + knee braces), hip roof of shakes over board sheathing
    top = K.MB("Wood")
    for (c1, c2, n) in SIDES:
        pa, pb = leg(*c1, Z_POST - 0.3), leg(*c2, Z_POST - 0.3)
        K.timber(top, pa, pb, 0.5, 0.3, beam, esq(rng), up=(0, 0, 1), ch=0.03, rng=rng, ext=0.5)
        for (ca, cb) in ((c1, c2), (c2, c1)):
            p0 = leg(*ca, Z_POST - 2.3)
            p1 = leg(*ca, Z_POST - 0.6) + (leg(*cb, Z_POST - 0.6) - leg(*ca, Z_POST - 0.6)).normalized() * 1.6
            K.timber(top, p0, p1, 0.26, 0.22, grey, esq(rng), up=n, ch=0.02, rng=rng, ext=0.1)
    K.part(lib, root, top, "Wood", collide=False, smooth_angle=30, notes="Roof plates and knee braces (visual).")
    roof = K.MB("Wood")
    shake = K.MB("Shake")
    hips = K.MB("Wood")
    apex = V((0, 0, Z_APEX))
    rise = Z_APEX - Z_EAVE
    L_s = math.hypot(EAVE, rise)
    th = 0.2
    for (c1, c2, n) in SIDES:
        e1 = V((c1[0] * EAVE, c1[1] * EAVE, Z_EAVE))
        e2 = V((c2[0] * EAVE, c2[1] * EAVE, Z_EAVE))
        em = (e1 + e2) / 2
        down = (em - apex).normalized()
        nrm = (e2 - e1).normalized().cross(down) * -1.0
        if nrm.z < 0:
            nrm = -nrm
        tip = apex + down * 0.02
        tl, tr = tip + (e1 - em).normalized() * 0.02, tip + (e2 - em).normalized() * 0.02
        T_ = nrm * th
        # underside sheathing (boards parallel to the eave), top, eave edge; hips closed by the neighbours
        rows = 8
        a, b, c, d = e1, e2, tr, tl
        if (b - a).cross(d - a).dot(-nrm) < 0:
            a, b, c, d = b, a, d, c
        K.quad_rows(roof, a, b, c, d, grey, rows, rng.uniform(0, 30))
        a, b, c, d = e1 + T_, e2 + T_, tr + T_, tl + T_
        if (b - a).cross(d - a).dot(nrm) < 0:
            a, b, c, d = b, a, d, c
        K.quad_rows(roof, a, b, c, d, K.R("Wood", "board_damp"), 1)
        a, b, c, d = e1, e2, e2 + T_, e1 + T_
        if (b - a).cross(d - a).dot(down) < 0:
            a, b, c, d = b, a, d, c
        K.quad_rows(roof, a, b, c, d, grey, 1, v_span=(0.0, 0.3))
        for (p, q_) in ((e1, tl), (tr, e2)):
            a, b, c, d = p, q_, q_ + T_, p + T_
            out = (p - em) if p is e1 else (q_ - em)
            out = V((out.x, out.y, 0)).normalized()
            if (b - a).cross(d - a).dot(out) < 0:
                a, b, c, d = b, a, d, c
            K.quad_rows(roof, a, b, c, d, grey, 1, v_span=(0.0, 0.3))
        # shake courses, widest at the eave
        O = apex + T_
        d_ = L_s + 0.1
        while d_ > 0.25:
            frac = d_ / L_s
            idx = max(0, min(6, int(round(1.0 + 3.0 * frac ** 2 + (1.2 if n.y < 0 else 0.0) + rng.uniform(-0.8, 0.8)))))
            hw = EAVE * min(1.0, d_ / L_s) + 0.12
            ph = rng.uniform(0, TAU)

            def warp(aa, dd, ph=ph):
                return 0.02 * math.sin(aa * 1.1 + ph) + 0.012 * math.sin(aa * 3.1 + 2 * ph)
            K.course(shake, O, (e2 - e1).normalized(), down, nrm, -hw, hw, d_, min(0.75, d_), 0.1,
                     K.R("Shake", "course_%d" % idx), K.R("Shake", "butt"), rng.uniform(0, 40), nu=4, warp=warp)
            d_ -= 0.75
        # hip board from this face's left eave corner to the apex
        hip_dir = (apex - e1).normalized()
        out = V((e1.x, e1.y, 0)).normalized()
        upv = (out + V((0, 0, 1.6))).normalized()
        K.timber(hips, e1 + upv * 0.32 - hip_dir * 0.15, apex + upv * 0.32, 0.5, 0.12, grey, esq(rng), up=upv,
                 ch=0.02, rng=rng)
    K.timber(hips, apex + V((0, 0, 0.1)), apex + V((0, 0, 0.85)), 0.42, 0.42, beam, esq(rng), up=(0, 1, 0), ch=0.06,
             rng=rng)
    K.part(lib, root, roof, "Planks", collision="Hull", smooth_angle=20, notes="Hip roof sheathing (Hull).")
    K.part(lib, root, shake, "Shingles", collide=False, smooth_angle=25, notes="Cedar shakes.")
    K.part(lib, root, hips, "Wood", collide=False, smooth_angle=30, notes="Hip boards and finial.")

    # ---------------- ladder (visual) with stays to the back girts
    lad = K.MB("Log")
    lx, ly = (WELL[0] + WELL[1]) / 2, (WELL[2] + WELL[3]) / 2
    yl = ly - 0.62
    for dx in (-0.72, 0.72):
        K.log(lad, (lx + dx, yl, 0.0), (lx + dx, yl, DECK + 1.15), 0.12, 0.1, reg=pole, end_reg=(ends(rng), ends(rng)),
              segs=7, rings=3, rng=rng, up=(0, 1, 0), bow=0.03)
    z = 0.95
    while z < DECK + 0.9:
        K.log(lad, (lx - 0.85, yl, z), (lx + 0.85, yl, z + rng.uniform(-0.03, 0.03)), 0.07, 0.065, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=6, rings=2, rng=rng)
        z += 1.0
    K.part(lib, root, lad, "Logs", collide=False, tags=["LadderVisual"], smooth_angle=60,
           notes="Pole ladder (visual): the TrussPart between LadderBase and LadderTop does the climbing.")
    stays = K.MB("Wood")
    for zz in (7.5, 15.0):
        yb = -leg(1, 1, zz).y + 0.42
        for dx in (-0.72, 0.72):
            K.timber(stays, (lx + dx, yl - 0.1, zz + 0.05), (lx + dx, yb, zz + 0.05), 0.22, 0.14, grey, esq(rng),
                     up=(1, 0, 0), ch=0.015, rng=rng)
            bolt_at(V((lx + dx + 0.07, yl - 0.25, zz + 0.05)), (1, 0, 0))
    K.part(lib, root, stays, "Wood", collide=False, smooth_angle=30, notes="Ladder stays (visual).")
    K.part(lib, root, iron, "Rust", collide=False, cast_shadow=False, smooth_angle=30,
           notes="Square-headed carriage bolts and footing anchor straps.")
    lib.attach(root, "LadderBase", (lx, ly, 0.0), look=(0, -1, 0), up=(0, 0, 1))
    lib.attach(root, "LadderTop", (lx, ly, DECK), look=(0, -1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


def review_views(name):
    return [
        ("deck", (-1.6, 2.8, DECK + 5.0), (3.2, -4.0, DECK + 0.6), 72, (36, 60), 0.0, [], (-2.5, -2.6, DECK)),
        ("base", (3.5, 14.0, 3.0), (0.0, 0.0, 6.0), 60, (30, 40), 0.0, [], (1.0, 6.2, 0.0)),
        ("joint", (-8.8, 9.0, 9.0), (-5.4, 5.4, 7.5), 40, (34, -30)),
    ]
