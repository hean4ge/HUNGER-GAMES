"""br_props.py - realistic campsite props for the BuildingsReal set (PropsReal.glb).

Tent, Campfire, Woodpile, Barrel, Lantern, CratePile, FenceSegment, Sign, Bedroll, LogBench. Real-world scale
(1 stud ~ 0.33 m, player 5.5); front = Blender +Y; base centre on z = 0. Every part samples one BR_ sheet.
"""
import math
import random

from mathutils import Vector as V

import br_kit as K

TAU = 2.0 * math.pi


def _ends(rng, fresh=False):
    if fresh:
        return K.R("Log", "end_fresh_%d" % rng.randrange(2))
    return K.R("Log", "end_%d" % rng.randrange(6))


def split_piece(mb, p0, p1, R, kind, rng, rot=None, fresh=None, bow=0.03, taper=0.97):
    """Split firewood from p0 to p1. kind = how many pieces the round was split into: 1 = round billet,
    2 = half, 3 = third, 4 = quarter. Bark on the outer arc, torn split faces on the cuts, end-grain caps that
    show the matching part of the growth rings (pith at the wedge point)."""
    bark, split = K.R("Log", "bark"), K.R("Log", "split")
    fresh = (rng.random() < 0.35) if fresh is None else fresh
    end = _ends(rng, fresh)
    if kind == 1:
        K.log(mb, p0, p1, R, R * taper, reg=bark, end_reg=(end, _ends(rng, fresh)), segs=8, rings=2, oval=0.06,
              wob=0.04, rng=rng, bow=bow)
        return
    span = TAU / kind
    a0 = rng.uniform(0, TAU) if rot is None else rot
    n_arc = {2: 6, 3: 4, 4: 3}.get(kind, 3)
    pts = K.arc(0.0, 0.0, R, a0, a0 + span, n_arc, jit=0.04, rng=rng)
    off = R * 0.06
    pith = (off * math.cos(a0 + span / 2), off * math.sin(a0 + span / 2))
    sec = pts + [pith]
    th = bark["tile"][1]
    arc_len = R * span
    sc = max(arc_len, th)
    em = []
    s_acc = 0.0
    uo = rng.uniform(0, 30)
    for i in range(len(pts) - 1):
        seg = math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        em.append((bark, uo, 1.0 - s_acc / sc, 1.0 - (s_acc + seg) / sc))
        s_acc += seg
    st = split["tile"][1]
    for (a, b) in ((pts[-1], pith), (pith, pts[0])):
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        em.append((split, rng.uniform(0, 30), 1.0, 1.0 - min(1.0, ln / st)))
    K.extrude(mb, p0, p1, sec, em, cap_map=(end, (0.0, 0.0), R * 1.02, rng.uniform(0, TAU)), rings=2, bow=bow,
              rng=rng, taper=taper)


# ------------------------------------------------------------------------------------------------ LogBench
def build_logbench(lib):
    rng = random.Random(3101)
    root = lib.begin("LogBench", kind="Prop", tags=["Camp", "Seat"],
                     notes="Half-log bench on two log rounds. Seat top 1.66. Seat_1 / Seat_2 on the seat, facing "
                           "front (+Y Blender = Roblox -Z).")
    mb = K.MB("Log")
    bark, pole = K.R("Log", "bark"), K.R("Log", "pole")
    r, L, za = 0.7, 6.8, 1.62
    n = 9
    sec = K.arc(0.0, 0.0, r, math.pi, TAU, n, jit=0.03, rng=rng)
    sec[0] = (-r * 0.97, 0.04)
    sec[-1] = (r * 0.97, 0.04)
    em = []
    for i in range(n):
        em.append((bark, rng.uniform(0, 30), 1.0 - i / n, 1.0 - (i + 1) / n))
    em.append((pole, rng.uniform(0, 30), 1.0, 0.0))
    K.extrude(mb, (-L / 2, 0.0, za), (L / 2, 0.0, za), sec, em,
              cap_map=(_ends(rng), (0.0, 0.0), r * 1.02, rng.uniform(0, TAU)), rings=5, bow=0.05, rng=rng,
              taper=0.93, wob=0.015)
    for x in (-2.35, 2.25):
        rr = rng.uniform(0.5, 0.56)
        K.log(mb, (x, rng.uniform(-0.06, 0.06), 0.0), (x, 0.0, za - r * 0.86), rr, rr * 0.97, reg=bark,
              end_reg=(_ends(rng, True), _ends(rng, True)), segs=12, rings=2, up=(1, 0, 0), chamfer=(0.0, 0.05),
              oval=0.05, wob=0.03, rng=rng)
    K.part(lib, root, mb, "Logs", collision="Hull", smooth_angle=55)
    for i, x in enumerate((-1.7, 1.6)):
        lib.attach(root, "Seat_%d" % (i + 1), (x, 0.0, za + 0.04), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Barrel
def build_barrel(lib):
    rng = random.Random(3201)
    root = lib.begin("Barrel", kind="Prop", tags=["Container", "Cover"],
                     notes="Coopered oak barrel, 16 staves, 4 forged iron hoops, recessed boarded head.")
    wood = K.MB("Wood")
    stave = K.R("Wood", "board_brown")
    head_reg = K.R("Wood", "board_damp")
    prof = [(0.99, 0.0), (1.05, 0.35), (1.12, 0.95), (1.155, 1.6), (1.12, 2.25), (1.05, 2.85), (0.99, 3.2)]
    nst = 16
    rot = rng.uniform(0, TAU)
    cols = []
    jit = [rng.uniform(-0.012, 0.012) for _ in range(nst)]
    for s in range(nst):
        a = rot + TAU * s / nst
        ca, sa = math.cos(a), math.sin(a)
        cols.append([wood.v((r * (1 + jit[s]) * ca, r * (1 + jit[s]) * sa, z)) for (r, z) in prof])
    lens = [0.0]
    for k in range(1, len(prof)):
        lens.append(lens[-1] + math.hypot(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]))
    for s in range(nst):
        t = (s + 1) % nst
        uo = rng.uniform(0, 40)
        for k in range(len(prof) - 1):
            # stave face: CCW from outside. Column s -> s+1 runs CCW round +z; rows go up.
            wood.f((cols[s][k], cols[t][k], cols[t][k + 1], cols[s][k + 1]),
                   [K.suv(stave, uo + lens[k], 1.0), K.suv(stave, uo + lens[k], 0.0),
                    K.suv(stave, uo + lens[k + 1], 0.0), K.suv(stave, uo + lens[k + 1], 1.0)], stave)
    # chime (top rim), inner wall down to the recessed head, head boards; plain bottom
    top = len(prof) - 1
    rim_in = [wood.v((prof[top][0] * 0.91 * math.cos(rot + TAU * s / nst), prof[top][0] * 0.91 * math.sin(rot + TAU * s / nst),
                      prof[top][1])) for s in range(nst)]
    zh = prof[top][1] - 0.16
    head = [wood.v((prof[top][0] * 0.9 * math.cos(rot + TAU * s / nst), prof[top][0] * 0.9 * math.sin(rot + TAU * s / nst),
                    zh)) for s in range(nst)]
    for s in range(nst):
        t = (s + 1) % nst
        uo = rng.uniform(0, 40)
        wood.f((cols[s][top], cols[t][top], rim_in[t], rim_in[s]),
               [K.suv(stave, uo, 1.0), K.suv(stave, uo, 0.0), K.suv(stave, uo + 0.1, 0.0), K.suv(stave, uo + 0.1, 1.0)],
               stave)
        wood.f((rim_in[s], rim_in[t], head[t], head[s]),
               [K.suv(stave, uo, 1.0), K.suv(stave, uo, 0.0), K.suv(stave, uo + 0.16, 0.0), K.suv(stave, uo + 0.16, 1.0)],
               stave)
    # head: fan split into board-wide UV bands (boards run along X)
    hr = prof[top][0] * 0.9
    cen = wood.v((0, 0, zh))
    for s in range(nst):
        t = (s + 1) % nst
        pa, pb = wood.co[head[s]], wood.co[head[t]]

        def huv(p):
            y = p.y + hr
            board = min(2, int(y / (2 * hr / 3)))
            return K.suv(head_reg, p.x + 7.0 * board, (y - board * 2 * hr / 3) / (2 * hr / 3))
        wood.f((head[s], head[t], cen), [huv(pa), huv(pb), K.suv(head_reg, 0.0, 0.5)], head_reg)
    bot = [cols[s][0] for s in range(nst)]
    wood.f(list(reversed(bot)), [K.suv(stave, 0.3 * math.cos(-TAU * s / nst), 0.5 + 0.4 * math.sin(-TAU * s / nst))
                                 for s in reversed(range(nst))], stave)
    K.part(lib, root, wood, "Planks", collision="Hull", smooth_angle=40)
    # hoops: forged iron bands proud of the staves
    iron = K.MB("Kit")
    ireg = K.R("Kit", "iron")

    def r_at(z):
        for (ra, za), (rb, zb) in zip(prof[:-1], prof[1:]):
            if za <= z <= zb:
                return ra + (rb - ra) * (z - za) / (zb - za)
        return prof[-1][0]
    for (z0, z1) in ((0.18, 0.36), (0.78, 0.95), (2.25, 2.42), (2.84, 3.02)):
        ro0, ro1 = r_at(z0) + 0.035, r_at(z1) + 0.035
        ri0, ri1 = ro0 - 0.07, ro1 - 0.07
        m = 24
        uo = rng.uniform(0, 30)
        ring = []
        for i in range(m):
            a = TAU * i / m
            ca, sa = math.cos(a), math.sin(a)
            ring.append((iron.v((ri0 * ca, ri0 * sa, z0)), iron.v((ro0 * ca, ro0 * sa, z0)),
                         iron.v((ro1 * ca, ro1 * sa, z1)), iron.v((ri1 * ca, ri1 * sa, z1))))
        circ = TAU * ro0
        for i in range(m):
            j = (i + 1) % m
            A, B = ring[i], ring[j]
            ua, ub = uo + circ * i / m, uo + circ * (i + 1) / m
            iron.f((A[1], B[1], B[2], A[2]), [K.suv(ireg, ua, 0), K.suv(ireg, ub, 0), K.suv(ireg, ub, 1), K.suv(ireg, ua, 1)], ireg)
            iron.f((A[2], B[2], B[3], A[3]), [K.suv(ireg, ua, 0.85), K.suv(ireg, ub, 0.85), K.suv(ireg, ub, 1), K.suv(ireg, ua, 1)], ireg)
            iron.f((A[3], B[3], B[0], A[0]), [K.suv(ireg, ua, 0.3), K.suv(ireg, ub, 0.3), K.suv(ireg, ub, 0.5), K.suv(ireg, ua, 0.5)], ireg)
            iron.f((A[0], B[0], B[1], A[1]), [K.suv(ireg, ua, 0.0), K.suv(ireg, ub, 0.0), K.suv(ireg, ub, 0.15), K.suv(ireg, ua, 0.15)], ireg)
    K.part(lib, root, iron, "Rust", collide=False, smooth_angle=50)
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Tent
def build_tent(lib):
    rng = random.Random(3301)
    root = lib.begin("Tent", kind="Prop", tags=["Camp"],
                     notes="Weathered canvas A-frame on a ridge pole and two uprights. Door at the front (+Y): left "
                           "flap rolled and tied, right flap staked open. Canvas collides (Default fidelity); poles, "
                           "stakes and guy lines do not.")
    L, HW, H = 7.6, 2.85, 4.55
    y0, y1 = -L / 2, L / 2
    zh = 0.1
    canvas = K.MB("Kit")
    cv = K.R("Kit", "canvas")
    th = 0.035

    def side_pt(side):
        def P(a, b):
            # a along the ridge (side +1: back -> front, side -1: front -> back), b from the hem up to the ridge
            y = (y0 + L * a) if side > 0 else (y1 - L * a)
            u = (y - y0) / L
            # canvas sags between the ridge and the staked hem, most in the middle of the panel; the hem
            # scallops between its four stake loops; faint stress wrinkles run diagonally from the stakes
            belly = 0.34 * math.sin(math.pi * b) ** 0.9 * (0.5 + 0.5 * math.sin(math.pi * u))
            scal = 0.13 * (1.0 - b) ** 4 * (0.5 - 0.5 * math.cos(TAU * 3.0 * u))
            ripple = (0.03 * math.sin(u * L * 2.1 + b * 5.0 + side) + 0.02 * math.sin(u * L * 4.7 - b * 3.0)) * (1.0 - b)
            x = side * (0.07 + (HW - 0.07) * (1.0 - b) - belly + ripple)
            z = zh + (H - zh) * b - 0.14 * belly + scal
            return (x, y, z)
        return P
    slope = math.hypot(HW, H - zh)
    for side in (1, -1):
        uo = 3.1 if side > 0 else 17.4
        K.sheet(canvas, side_pt(side), 11, 7, th, cv,
                (lambda a, b, uo=uo: uo + a * L), (lambda a, b: b), edges=True)
    # back panel: triangle from the hem to the ridge (flat, slight inward belly)
    def back_pt(a, b):
        x = HW * (2.0 * a - 1.0) * (1.0 - b) + 0.02
        z = zh + (H - zh) * b
        return (x, y0 + 0.05 + 0.12 * math.sin(math.pi * b) * math.sin(math.pi * a) * (1 - b), z)
    K.sheet(canvas, back_pt, 4, 4, th, cv, lambda a, b: 30.0 + a * 2 * HW, lambda a, b: b * min(1.0, H / slope))
    # right door flap staked open: attached along the right front edge, free edge pulled out to a stake
    tip = V((HW * 0.85 + 0.5, y1 + 1.4, 0.12))
    apex = V((0.06, y1 + 0.04, H - 0.06))
    hem_att = V((HW, y1 + 0.02, zh))

    def flap_pt(a, b):
        bb = 0.04 + 0.96 * b
        free = apex.lerp(tip, bb)
        att = apex.lerp(hem_att, bb)
        p = free.lerp(att, a)
        p = p + V((0.0, 0.12, -0.06)) * (math.sin(math.pi * a) * math.sin(math.pi * bb))
        return tuple(p)
    K.sheet(canvas, flap_pt, 4, 5, th, cv, lambda a, b: 40.0 + (1.0 - a) * 2.6, lambda a, b: 1.0 - 0.85 * b)
    # left flap rolled up and tied beside the door
    K.log(canvas, (-0.25, y1 + 0.06, H - 0.35), (-HW + 0.25, y1 + 0.1, 0.42), 0.17, 0.13, reg=cv, segs=8, rings=4,
          bow=0.06, rng=rng, oval=0.12, wob=0.06, up=(0, 1, 0))
    K.part(lib, root, canvas, "Canvas", collision="Default", smooth_angle=70)

    # ---- poles, ridge, stakes (sawn sticks)
    wood = K.MB("Wood")
    bw = K.R("Wood", "board_grey")
    for y in (y0 + 0.12, y1 - 0.12):
        K.timber(wood, (0, y, 0.0), (0, y, H + 0.32), 0.13, 0.13, bw, K.R("Wood", "end_sq_%d" % rng.randrange(8)),
                 up=(0, 1, 0), ch=0.02, rng=rng)
    K.timber(wood, (0, y0 - 0.05, H - 0.1), (0, y1 + 0.05, H - 0.1), 0.12, 0.12, bw, K.R("Wood", "end_sq_2"),
             up=(0, 0, 1), ch=0.02, rng=rng)
    stakes = [(0.0, y1 + 2.55), (0.0, y0 - 2.55), (tip.x + 0.25, tip.y + 0.2)]
    for side in (1, -1):
        for y in (y0 + 0.3, -1.25, 1.25, y1 - 0.3):
            stakes.append((side * (HW + 0.6), y))
    for (x, y) in stakes:
        lean = V((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 0))
        K.timber(wood, (x, y, -0.02), V((x, y, 0.5)) + lean, 0.09, 0.09, bw, K.R("Wood", "end_sq_5"), up=(1, 0, 0),
                 ch=0.015, rng=rng)
    K.part(lib, root, wood, "Wood", collide=False, smooth_angle=30)

    # ---- guy lines + hem ties
    ropes = K.MB("Log")
    rp = K.R("Log", "rope")
    for (yt, ys) in ((y1 - 0.12, y1 + 2.55), (y0 + 0.12, y0 - 2.55)):
        K.rope(ropes, K.catenary((0, yt, H + 0.26), (0, ys, 0.42), 0.12, 8), 0.028, rp, segs=5, rng=rng)
    for side in (1, -1):
        for y in (y0 + 0.3, -1.25, 1.25, y1 - 0.3):
            K.rope(ropes, [(side * (HW + 0.02), y, zh + 0.04), (side * (HW + 0.3), y, 0.32),
                           (side * (HW + 0.6), y, 0.4)], 0.025, rp, segs=4, rng=rng)
    K.rope(ropes, [tuple(tip + V((0, 0, 0.02))), (tip.x + 0.25, tip.y + 0.2, 0.38)], 0.025, rp, segs=4, rng=rng)
    for z in (H - 1.2, 1.2):  # ties round the rolled flap
        pz = V((-0.25, y1 + 0.06, H - 0.35)).lerp(V((-HW + 0.25, y1 + 0.1, 0.42)), (H - 0.35 - z) / (H - 0.77))
        ring = [tuple(pz + V((0.19 * math.cos(a), 0.19 * math.sin(a) * 0.9, 0.0))) for a in
                [TAU * k / 7 for k in range(8)]]
        K.rope(ropes, ring, 0.022, rp, segs=4, rng=rng)
    K.part(lib, root, ropes, "Rope", collide=False, cast_shadow=False, smooth_angle=60)
    lib.attach(root, "Entrance", (0, y1 + 0.4, 0), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Campfire
def build_campfire(lib):
    rng = random.Random(3401)
    root = lib.begin("Campfire", kind="Prop", tags=["Camp", "Fire"],
                     notes="Fire ring of soot-blackened stones round an ash bed, charred logs and a coal bed. "
                           "Fire particles / PointLight / crackle sound at FireCenter. Campfire_Ember is the "
                           "emissive coal part (drive SurfaceAppearance EmissiveStrength or swap to Neon).")
    st = K.MB("Stone")
    burnt, rockr, ash = K.R("Stone", "rock_burnt"), K.R("Stone", "rock"), K.R("Stone", "ash")
    n = 10
    for i in range(n):
        a = TAU * i / n + rng.uniform(-0.1, 0.1)
        r = 1.55 + rng.uniform(-0.08, 0.1)
        sx, sy, sz = rng.uniform(0.75, 1.0), rng.uniform(0.52, 0.72), rng.uniform(0.38, 0.55)
        K.rock(st, (r * math.cos(a), r * math.sin(a), -0.02), (sx, sy, sz), burnt if i % 3 else rockr, rng, subdiv=1,
               rough=0.3, rz=a + math.pi / 2 + rng.uniform(-0.25, 0.25), facets=4)
    # ash bed: a low dome built in rows one ash-strip wide, so the strip keeps square texels
    Rb = 1.32
    th_a = ash["tile"][1]
    nrow = max(2, int(math.ceil(2 * Rb / th_a)))
    ncol = 8

    def dome(x, y):
        q = min(1.0, (x * x + y * y) / (Rb * Rb))
        return 0.13 * (1.0 - q) ** 1.3 - 0.015 + 0.012 * math.sin(3.1 * x + 1.7 * y)
    for k in range(nrow):
        ya, yb = -Rb + 2 * Rb * k / nrow, -Rb + 2 * Rb * (k + 1) / nrow
        xa = math.sqrt(max(Rb * Rb - ya * ya, 0.0)) * (0.92 + 0.08 * math.sin(3.7 * ya + 1.1))
        xb = math.sqrt(max(Rb * Rb - yb * yb, 0.0)) * (0.92 + 0.08 * math.sin(3.7 * yb + 1.1))
        uo = rng.uniform(0, 30)
        for c in range(ncol):
            t0, t1 = c / ncol, (c + 1) / ncol
            pa0, pa1 = -xa + 2 * xa * t0, -xa + 2 * xa * t1
            pb0, pb1 = -xb + 2 * xb * t0, -xb + 2 * xb * t1
            q = [st.v((pa0, ya, dome(pa0, ya))), st.v((pa1, ya, dome(pa1, ya))), st.v((pb1, yb, dome(pb1, yb))),
                 st.v((pb0, yb, dome(pb0, yb)))]
            st.f(q, [K.suv(ash, uo + pa0, 0.0), K.suv(ash, uo + pa1, 0.0), K.suv(ash, uo + pb1, 1.0),
                     K.suv(ash, uo + pb0, 1.0)], ash)
    K.part(lib, root, st, "Stone", collision="Box", smooth_angle=38)

    # charred logs: four half-burnt ends pointing into the fire + a collapsed cross piece
    ch = K.MB("Kit")
    char = K.R("Kit", "char")
    for i in range(4):
        a = TAU * i / 4 + 0.5 + rng.uniform(-0.2, 0.2)
        r0, r1 = rng.uniform(0.17, 0.22), rng.uniform(0.08, 0.12)
        out = V((1.25 * math.cos(a), 1.25 * math.sin(a), 0.2))
        inn = V((0.22 * math.cos(a + 0.4), 0.22 * math.sin(a + 0.4), 0.55 + rng.uniform(-0.1, 0.15)))
        K.log(ch, out, inn, r0, r1, reg=char, segs=7, rings=3, rng=rng, bow=0.03, oval=0.1, wob=0.08)
    K.log(ch, (-1.0, -0.3, 0.2), (0.95, 0.42, 0.28), 0.15, 0.13, reg=char, segs=7, rings=3, rng=rng, bow=0.04,
          oval=0.12, wob=0.08)
    K.part(lib, root, ch, "Logs", collide=False, smooth_angle=60)

    # coal bed (emissive): flattened chunks in the middle of the ash
    em = K.MB("Kit")
    emb = K.R("Kit", "ember")
    for i in range(9):
        a = rng.uniform(0, TAU)
        r = rng.uniform(0.0, 0.6)
        s = rng.uniform(0.16, 0.3)
        K.rock(em, (r * math.cos(a), r * math.sin(a), 0.07), (s, s * 0.8, s * 0.5), emb, rng, subdiv=0, rough=0.25)
    K.part(lib, root, em, "Ember", collide=False, cast_shadow=False, variant="Ember", smooth_angle=50,
           notes="Emissive coals: SurfaceAppearance EmissiveStrength 1-3 (night higher); no collision, no shadow.")
    lib.attach(root, "FireCenter", (0, 0, 0.6), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Woodpile
def build_woodpile(lib):
    rng = random.Random(3501)
    root = lib.begin("Woodpile", kind="Prop", tags=["Camp", "Cover"],
                     notes="Split firewood stacked between pole stakes on two ground rails, end grain to the "
                           "front (+Y); chopping round with a split billet beside it. One Box collider.")
    mb = K.MB("Log")
    pole = K.R("Log", "pole")
    for y in (-0.72, 0.72):
        K.log(mb, (-3.25, y, 0.17), (3.25, y + rng.uniform(-0.05, 0.05), 0.17), 0.17, 0.16, reg=pole,
              end_reg=(_ends(rng), _ends(rng)), segs=8, rings=2, rng=rng)
    for x in (-3.05, 3.05):
        for y in (-0.95, 0.95):
            lean = V((0.12 * (1 if x > 0 else -1) + rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0))
            K.log(mb, (x, y, 0.0), V((x, y, 3.05)) + lean, 0.11, 0.09, reg=pole, end_reg=_ends(rng), segs=7,
                  rings=2, rng=rng, cap=(False, True))
    z = 0.34
    for row, span in enumerate((5.75, 5.7, 5.6, 5.45, 5.2)):
        x = -span / 2
        hmax = 0.0
        while True:
            kind = rng.choice((1, 2, 2, 3, 3, 4, 4))
            R = rng.uniform(0.26, 0.36) if kind > 1 else rng.uniform(0.2, 0.26)
            w = 2 * R * (0.95 if kind <= 2 else 0.72)
            if x + w > span / 2 + 0.05:
                break
            L0, L1 = rng.uniform(1.15, 1.3), rng.uniform(1.15, 1.35)
            cx = x + w / 2
            zz = z + R * (0.86 if kind <= 2 else 0.7) + rng.uniform(-0.03, 0.03)
            split_piece(mb, (cx, -L0, zz), (cx + rng.uniform(-0.05, 0.05), L1, zz + rng.uniform(-0.04, 0.04)), R, kind,
                        rng, rot=rng.uniform(0, TAU))
            hmax = max(hmax, 2 * R * (0.86 if kind <= 2 else 0.75))
            x += w * rng.uniform(0.92, 1.0)
        z += hmax * 0.86
        if row == 4:
            break
    # chopping round + a billet waiting on it, two pieces on the ground
    K.log(mb, (2.1, 2.1, 0.0), (2.1, 2.1, 1.05), 0.62, 0.6, reg=K.R("Log", "bark"),
          end_reg=(_ends(rng), _ends(rng, True)), segs=12, rings=2, up=(1, 0, 0), rng=rng, cap=(False, True))
    split_piece(mb, (2.0, 2.0, 1.05), (2.12, 2.05, 2.25), 0.28, 2, rng, fresh=True)
    split_piece(mb, (-1.2, 1.7, 0.2), (0.8, 2.3, 0.2), 0.24, 3, rng, rot=-math.pi * 0.5)
    split_piece(mb, (-2.2, 1.4, 0.18), (-1.0, 2.55, 0.2), 0.22, 4, rng, rot=math.pi * 1.25)
    K.part(lib, root, mb, "Logs", collision="Box", smooth_angle=50)
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Lantern
def build_lantern(lib):
    rng = random.Random(3601)
    root = lib.begin("Lantern", kind="Prop", tags=["Light"],
                     notes="Tin hurricane lantern (real size, 1.4 tall with the bail up). Hang it from HangPoint; "
                           "put a warm PointLight (Range 16-24, Brightness 1-1.5, (255,170,100)) at Glow. "
                           "Lantern_Glass is the sooty globe (AlphaMode Transparency, MeshPart.Transparency 0.05-0.2); "
                           "Lantern_Ember is the flame (emissive). No collision.")
    tin = K.MB("Kit")
    treg, ireg = K.R("Kit", "tin"), K.R("Kit", "iron")
    K.lathe(tin, [(0.23, 0.0), (0.275, 0.02), (0.29, 0.06), (0.29, 0.14), (0.255, 0.19), (0.15, 0.215),
                  (0.135, 0.235), (0.135, 0.285), (0.11, 0.3)], 14, treg, cap_top=False)
    K.lathe(tin, [(0.1, 0.71), (0.18, 0.745), (0.235, 0.79), (0.235, 0.83), (0.15, 0.87), (0.09, 0.93),
                  (0.085, 0.985), (0.13, 1.0), (0.13, 1.02), (0.02, 1.06)], 14, treg, cap_bottom=True)
    for sx in (-1, 1):  # hot-blast side tubes
        pts = [(sx * 0.27, 0.0, 0.15), (sx * 0.29, 0.0, 0.3), (sx * 0.29, 0.0, 0.62), (sx * 0.285, 0.0, 0.76),
               (sx * 0.22, 0.0, 0.81)]
        K.rope(tin, pts, 0.032, treg, segs=6, rng=rng)
    for k in range(4):  # globe guard wires
        a = TAU * (k + 0.5) / 4
        pts = []
        for i in range(7):
            t = i / 6
            z = 0.3 + 0.42 * t
            r = 0.17 + 0.07 * math.sin(math.pi * t)
            pts.append((r * math.cos(a), r * math.sin(a), z))
        K.rope(tin, pts, 0.011, ireg, segs=3, rng=rng)
    for (z, r) in ((0.42, 0.235), (0.6, 0.232)):
        ring = [(r * math.cos(TAU * i / 12), r * math.sin(TAU * i / 12), z) for i in range(13)]
        K.rope(tin, ring, 0.011, ireg, segs=3, rng=rng, cap=False)
    bail = []
    for i in range(11):
        t = i / 10
        a = math.pi * t
        bail.append((-0.3 * math.cos(a), 0.0, 0.58 + 0.78 * math.sin(a) ** 0.9))
    K.rope(tin, bail, 0.017, ireg, segs=4, rng=rng)
    K.part(lib, root, tin, "Tin", collide=False, cast_shadow=False, smooth_angle=45)

    glass = K.MB("Kit")
    K.lathe(glass, [(0.105, 0.3), (0.165, 0.36), (0.205, 0.45), (0.21, 0.53), (0.185, 0.62), (0.13, 0.69),
                    (0.105, 0.715)], 12, K.R("Kit", "globe"), cap_bottom=False, cap_top=False)
    # inner wall (globes are thick): same profile, slightly smaller, faces turned inward by reversing the profile
    inner = [(r - 0.012, z) for (r, z) in reversed([(0.105, 0.3), (0.165, 0.36), (0.205, 0.45), (0.21, 0.53),
                                                    (0.185, 0.62), (0.13, 0.69), (0.105, 0.715)])]
    K.lathe(glass, inner, 12, K.R("Kit", "globe"), cap_bottom=False, cap_top=False, v_range=(1.0, 0.0))
    K.part(lib, root, glass, "Glass", collide=False, cast_shadow=False, variant="Glass", smooth_angle=80,
           notes="Sooty globe glass: AlphaMode Transparency with MeshPart.Transparency 0.05-0.2 (blended).")
    fl = K.MB("Kit")
    K.lathe(fl, [(0.03, 0.305), (0.045, 0.33), (0.04, 0.37), (0.022, 0.41), (0.004, 0.455)], 6, K.R("Kit", "ember"),
            cap_top=False)
    K.part(lib, root, fl, "Ember", collide=False, cast_shadow=False, variant="Ember", smooth_angle=80,
           notes="Wick flame: emissive; hide it when the lantern is out.")
    lib.attach(root, "HangPoint", (0, 0, 1.37), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "Glow", (0, 0, 0.42), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ CratePile
def _crate(mb, size, loc, rz, rng, h=None):
    s = size / 2.0
    hh = h if h is not None else size * 0.86
    cx, cy, cz = loc
    body = K.R("Wood", "board_crate")
    frame_r = K.R("Wood", "board_grey")
    K.board_box(mb, (cx - s + 0.06, cy - s + 0.06, cz), (cx + s - 0.06, cy + s - 0.06, cz + hh), body, board=0.72,
                rz=rz, c=(cx, cy, cz), rng=rng)
    ca, sa = math.cos(rz), math.sin(rz)

    def P(x, y, z):
        return V((cx + x * ca - y * sa, cy + x * sa + y * ca, z))
    t = 0.12
    w = 0.3
    for (sx, sy) in ((1, 1), (-1, 1), (-1, -1), (1, -1)):  # corner posts
        K.timber(mb, P(sx * (s - w / 2), sy * (s - t / 2 - 0.01), cz), P(sx * (s - w / 2), sy * (s - t / 2 - 0.01), cz + hh),
                 w, t, frame_r, K.R("Wood", "end_sq_%d" % rng.randrange(8)), up=P(0, sy, 0) - P(0, 0, 0), ch=0.02,
                 rng=rng)
    for z in (cz + 0.16, cz + hh - 0.16):  # rim battens on the front / back
        for sy in (1, -1):
            K.timber(mb, P(-s + w, sy * (s - t / 2 - 0.01), z), P(s - w, sy * (s - t / 2 - 0.01), z), 0.3, t, frame_r,
                     K.R("Wood", "end_sq_%d" % rng.randrange(8)), up=P(0, sy, 0) - P(0, 0, 0), ch=0.02, rng=rng)


def build_cratepile(lib):
    rng = random.Random(3701)
    root = lib.begin("CratePile", kind="Prop", tags=["Cover"],
                     notes="Four weathered pine supply crates (board faces, corner posts and rim battens). One Box "
                           "collider for the whole pile (cover).")
    mb = K.MB("Wood")
    _crate(mb, 3.0, (-1.55, -0.1, 0.0), 0.06, rng)
    _crate(mb, 2.7, (1.45, 0.25, 0.0), -0.14, rng)
    _crate(mb, 2.45, (-1.25, -0.05, 3.0 * 0.86 + 0.01), 0.38, rng)
    _crate(mb, 1.8, (0.95, 2.45, 0.0), 0.62, rng)
    K.part(lib, root, mb, "Planks", collision="Box", smooth_angle=30)
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ FenceSegment
def build_fence(lib):
    rng = random.Random(3801)
    root = lib.begin("FenceSegment", kind="Prop", tags=["Fence"],
                     notes="8-stud split-rail segment along X: paired-post style, posts at x = +-3.8, three split "
                           "rails running past the posts so neighbours (placed 8 apart) overlap. One Box collider.")
    mb = K.MB("Log")
    pole, bark, split = K.R("Log", "pole"), K.R("Log", "bark"), K.R("Log", "split")
    for x in (-3.8, 3.8):
        h = 4.3 + rng.uniform(-0.15, 0.1)
        K.log(mb, (x, 0.0, -0.02), (x + rng.uniform(-0.08, 0.08), rng.uniform(-0.06, 0.06), h), 0.27, 0.23, reg=pole,
              end_reg=_ends(rng), segs=9, rings=3, rng=rng, cap=(False, True), chamfer=(0.0, 0.06), bow=0.04)
    for z in (1.05, 2.3, 3.5):
        R = rng.uniform(0.26, 0.31)
        kind = rng.choice((2, 3))
        a0 = rng.uniform(-0.3, 0.3) + (math.pi * 0.5 if kind == 2 else math.pi * 0.25)
        dz = rng.uniform(-0.08, 0.08)
        y = rng.uniform(-0.06, 0.06)
        split_piece(mb, (-4.25, y, z + dz), (4.25, y + rng.uniform(-0.05, 0.05), z - dz), R, kind, rng, rot=a0,
                    fresh=False, bow=0.08, taper=0.92)
    K.part(lib, root, mb, "Logs", collision="Box", smooth_angle=55)
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Sign
def build_sign(lib):
    rng = random.Random(3901)
    root = lib.begin("Sign", kind="Prop", tags=["Sign"],
                     notes="Weathered hewn post with a blank two-plank board nailed to its front. SurfaceGui on "
                           "Sign_Planks, Face Front, at SignFace (board centre, 4.4 x 1.5).")
    wood = K.MB("Wood")
    beam = K.R("Wood", "beam")
    K.timber(wood, (0.0, 0.0, -0.02), (0.0, 0.0, 6.0), 0.46, 0.46, beam, K.R("Wood", "end_sq_6"), up=(0, 1, 0),
             ch=0.05, rng=rng)
    y_b = 0.23 + 0.08
    for (z, dz) in ((4.98, 0.03), (5.74, -0.02)):
        K.timber(wood, (-2.2, y_b, z - dz), (2.2, y_b, z + dz), 0.74, 0.15, K.R("Wood", "board_silver"),
                 K.R("Wood", "end_sq_%d" % rng.randrange(8)), up=(0, 1, 0), ch=0.025, rng=rng)
    for x in (-1.55, 1.55):  # back cleats holding the two planks together
        K.timber(wood, (x, 0.23 - 0.07, 4.62), (x, 0.23 - 0.07, 6.08), 0.3, 0.12, K.R("Wood", "board_grey"),
                 K.R("Wood", "end_sq_3"), up=(0, 1, 0), ch=0.02, rng=rng)
    K.part(lib, root, wood, "Planks", collision="Box", smooth_angle=30)
    st = K.MB("Stone")
    for (x, y, s) in ((0.55, 0.35, 0.8), (-0.5, -0.42, 0.7), (-0.38, 0.5, 0.55), (0.45, -0.45, 0.5)):
        K.rock(st, (x, y, -0.02), (s, s * 0.85, s * 0.55), K.R("Stone", "rock"), rng, subdiv=1, rough=0.3, facets=4)
    K.part(lib, root, st, "Stone", collide=False, cast_shadow=False, smooth_angle=38)
    lib.attach(root, "SignFace", (0.0, y_b + 0.076, 5.36), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


# ------------------------------------------------------------------------------------------------ Bedroll
def build_bedroll(lib):
    rng = random.Random(4001)
    root = lib.begin("Bedroll", kind="Prop", tags=["Camp"],
                     notes="Canvas groundsheet with a wool blanket laid out on it, top corner turned back, the head "
                           "end rolled into a pillow and strapped. Head toward -Y. Walk-over: no collision.")
    mb = K.MB("Kit")
    cv, bl, lea = K.R("Kit", "canvas"), K.R("Kit", "blanket"), K.R("Kit", "leather")
    W, L = 2.5, 6.6

    def ground(a, b):
        x = -W / 2 + W * a
        y = -L / 2 + L * b
        z = 0.03 + 0.025 * math.sin(a * 7.0 + b * 3.0) * math.sin(b * 9.0) + 0.04 * (abs(a - 0.5) * 2) ** 3
        return (x, y, z)
    K.sheet(mb, ground, 6, 10, 0.02, cv, lambda a, b: b * L, lambda a, b: 0.66 - 0.635 * a)
    bw = 2.05
    btile = bl["tile"]

    def blanket(a, b):
        x = -bw / 2 + bw * a
        y = -L / 2 + 1.0 + (L - 1.35) * b
        lump = 0.16 * math.sin(math.pi * a) ** 0.7 * (0.6 + 0.4 * math.sin(b * 5.0 + 0.7))
        z = 0.06 + lump + 0.03 * math.sin(a * 9 + b * 13)
        if b > 0.72 and a > 0.55:   # turned-back corner
            t = min(1.0, (b - 0.72) / 0.28) * min(1.0, (a - 0.55) / 0.45)
            z += 0.25 * t
        return (x, y, z)
    blen = L - 1.35
    K.sheet(mb, blanket, 6, 10, 0.05, bl, lambda a, b: 0.05 + b * min(btile[0] - 0.1, blen),
            lambda a, b: 0.97 - 0.94 * a)
    # pillow roll at the head + two leather straps
    yr = -L / 2 + 0.62
    K.log(mb, (-1.15, yr, 0.36), (1.15, yr + 0.05, 0.36), 0.34, 0.33, reg=bl, segs=10, rings=3, rng=rng, oval=0.1,
          wob=0.05, up=(0, 0, 1), u_off=0.1)
    for x in (-0.62, 0.6):
        ring = [(x, yr + 0.37 * math.cos(TAU * k / 10), 0.36 + 0.36 * math.sin(TAU * k / 10)) for k in range(11)]
        K.rope(mb, ring, 0.03, lea, segs=4, rng=rng, cap=False, u_scale=0.33)
    K.part(lib, root, mb, "Cloth", collide=False, cast_shadow=False, smooth_angle=70)
    lib.finish(root)
    return root


def review_views(name):
    return []
