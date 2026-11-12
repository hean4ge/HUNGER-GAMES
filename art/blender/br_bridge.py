"""br_bridge.py - Footbridge (BuildingsReal): a plank-and-rope suspension footbridge over the river gorge.

Span along X: EndA (x = -20) and EndB (x = +20) sit at deck level (z = 1.5) on the two banks; the deck sags 1.2 at
mid-span. Two galvanised wire ropes carry the cross planks (4.6 long, 0.74 wide, small gaps); two thick manila
handrail ropes sag from portal posts at each end (peeled poles with a cap log, raking struts and log crib sills on
bank stones) and tie back to buried deadman logs; hanger ropes every ~1.7 lash the handrails to the deck. The deck
is five Hull segments (walkable, Floor); ropes and cables do not collide.
"""
import math
import random

from mathutils import Vector as V

import br_kit as K

TAU = 2.0 * math.pi
HALF = 20.0
Z_END = 1.5
SAG = 1.2
W2 = 2.3          # half deck width (plank length 4.6)
CAB_Y = 1.95      # deck cables
POST_X = 19.3
POST_Y = 2.75
POST_TOP = 6.0


def z_deck(x):
    t = (x + HALF) / (2 * HALF)
    return Z_END - SAG * 4.0 * t * (1.0 - t)


def slope(x):
    t = (x + HALF) / (2 * HALF)
    return -SAG * 4.0 * (1.0 - 2.0 * t) / (2 * HALF)


def ends(rng):
    return K.R("Log", "end_%d" % rng.randrange(6))


def build(lib):
    rng = random.Random(5301)
    root = lib.begin("Footbridge", kind="Building", tags=["Bridge", "River"],
                     notes="Plank-and-rope suspension footbridge spanning X: EndA (x -20) and EndB (x +20) at deck "
                           "level 1.5 on the banks, deck 4.6 wide, 1.2 sag at mid-span. Five Hull plank segments are "
                           "the walkable deck; ropes, cables, hangers do not collide (nothing stops a fall off the "
                           "side). Sink the crib sills and bank stones into the bank; the deadman logs lie at "
                           "x = +-23.8.")
    wood = K.R("Wood", "board_grey")
    pole, lw, rp = K.R("Log", "pole"), K.R("Log", "log_wall"), K.R("Log", "rope")
    wire, ireg = K.R("Kit", "wire"), K.R("Kit", "iron")

    # ---------------- deck planks in five Hull segments
    nseg = 5
    x0p, x1p = -HALF + 0.55, HALF - 0.55
    pitch = 0.86
    n = int((x1p - x0p) / pitch) + 1
    xs = [x0p + i * (x1p - x0p) / (n - 1) for i in range(n)]
    seg_of = [min(nseg - 1, int((x - x0p) / ((x1p - x0p) / nseg + 1e-6))) for x in xs]
    for s in range(nseg):
        mb = K.MB("Wood")
        for x, sg in zip(xs, seg_of):
            if sg != s:
                continue
            z = z_deck(x)
            sl = slope(x)
            ax = V((1.0, 0.0, sl)).normalized()
            up = V((-sl, rng.uniform(-0.02, 0.02), 1.0)).normalized()
            w = rng.uniform(0.66, 0.76)
            c = V((x + rng.uniform(-0.03, 0.03), 0.0, z - 0.08))
            e0, e1 = W2 + rng.uniform(-0.12, 0.08), W2 + rng.uniform(-0.12, 0.08)
            # plank across the deck (along Y): width along the span, thickness along the deck normal
            K.timber(mb, c - V((0, e0, 0)), c + V((0, e1, 0)), w, 0.16,
                     K.R("Wood", rng.choice(("board_grey", "board_grey", "board_silver", "board_damp"))),
                     K.R("Wood", "end_sq_%d" % rng.randrange(8)), up=up, ch=0.02, rng=rng,
                     twist=rng.uniform(-0.03, 0.03))
        K.part(lib, root, mb, "Planks", collision="Hull", tags=["Floor"], smooth_angle=30,
               notes="Deck planks, segment %d of %d (Hull, walkable)." % (s + 1, nseg))

    # ---------------- deck wire ropes + clamps (Kit)
    kit = K.MB("Kit")
    for y in (-CAB_Y, CAB_Y):
        pts = [V((x, y, z_deck(x) - 0.23)) for x in [-HALF - 1.2 + i * (2 * HALF + 2.4) / 32 for i in range(33)]]
        for p in pts:
            if abs(p.x) > HALF:
                p.z = Z_END - 0.23 - (abs(p.x) - HALF) * 0.35
        K.rope(kit, pts, 0.07, wire, segs=6, rng=rng)
        for x in (-HALF + 0.3, HALF - 0.3):  # cable clamps at the sills
            for k in range(3):
                xc = x + (0.3 * k if x < 0 else -0.3 * k)
                c = V((xc, y, z_deck(xc) - 0.23))
                K.timber(kit, c - V((0.05, 0, 0)), c + V((0.05, 0, 0)), 0.24, 0.24, ireg, ireg, up=(0, 0, 1), ch=0.03,
                         rng=rng)
    K.part(lib, root, kit, "Rust", collide=False, cast_shadow=False, smooth_angle=50,
           notes="Galvanised deck wire ropes and clamps (visual).")

    # ---------------- portal posts, cap logs, raking struts, crib sills (Log)
    posts = K.MB("Log")
    for sx in (-1, 1):
        for sy in (-1, 1):
            base = V((sx * POST_X, sy * POST_Y, -0.03))
            topp = V((sx * (POST_X + 0.25), sy * (POST_Y + 0.05), POST_TOP))
            K.log(posts, base, topp, 0.36, 0.3, reg=pole, end_reg=(ends(rng), ends(rng)), segs=9, rings=3, rng=rng,
                  up=(1, 0, 0), bow=0.05, chamfer=(0.0, 0.06))
            # raking strut on the bank side, footed beside the crib
            K.log(posts, V((sx * (POST_X + 2.6), sy * (POST_Y + 0.2), 0.14)),
                  V((sx * (POST_X + 0.3), sy * (POST_Y + 0.05), 3.6)), 0.2, 0.18, reg=pole,
                  end_reg=(ends(rng), ends(rng)), segs=7, rings=2, rng=rng, bow=0.03)
        K.log(posts, V((sx * (POST_X + 0.28), -POST_Y - 0.7, POST_TOP - 0.55)),
              V((sx * (POST_X + 0.28), POST_Y + 0.7, POST_TOP - 0.55)), 0.3, 0.28, reg=lw,
              end_reg=(ends(rng), ends(rng)), segs=9, rings=2, rng=rng, chamfer=(0.06, 0.06))
    K.part(lib, root, posts, "Logs", collision="PreciseConvexDecomposition", smooth_angle=60,
           notes="Portal posts, cap logs and raking struts.")
    for sx in (-1, 1):
        crib = K.MB("Log")
        xs_ = sx * (HALF - 0.1)
        K.log(crib, V((xs_, -POST_Y - 0.9, 0.45)), V((xs_, POST_Y + 0.9, 0.45)), 0.42, 0.4, reg=lw,
              end_reg=(ends(rng), ends(rng)), segs=10, rings=2, rng=rng, chamfer=(0.06, 0.06))
        K.log(crib, V((sx * (HALF + 1.2), -POST_Y - 0.6, 0.38)), V((sx * (HALF + 1.2), POST_Y + 0.6, 0.38)), 0.38, 0.36,
              reg=lw, end_reg=(ends(rng), ends(rng)), segs=10, rings=2, rng=rng, chamfer=(0.06, 0.06))
        for y in (-CAB_Y - 0.6, CAB_Y + 0.6):
            K.log(crib, V((sx * (HALF - 0.6), y, 0.75)), V((sx * (HALF + 1.7), y, 0.75)), 0.3, 0.28, reg=lw,
                  end_reg=(ends(rng), ends(rng)), segs=8, rings=2, rng=rng)
        K.part(lib, root, crib, "Logs", collision="Box", smooth_angle=60,
               notes="Log crib sill at the %s bank (crib top ~0.9, deck end 1.5)." % ("west" if sx < 0 else "east"))

    # ---------------- handrail ropes, hangers, back stays, lashings (Log rope)
    ropes = K.MB("Log")
    for sy in (-1, 1):
        y_t = sy * (POST_Y + 0.05)
        a = V((-(POST_X + 0.25), y_t, POST_TOP - 0.25))
        b = V(((POST_X + 0.25), y_t, POST_TOP - 0.25))
        mid_drop = (POST_TOP - 0.25) - (z_deck(0.0) + 3.3)
        hand = K.catenary(a, b, mid_drop, 40)
        # pull the rope in toward the deck edge away from the posts
        for p in hand:
            f = 1.0 - min(1.0, abs(p.x) / POST_X) ** 2
            p.y = y_t + (sy * (W2 + 0.12) - y_t) * min(1.0, 1.5 * f)
        K.rope(ropes, hand, 0.1, rp, segs=7, rng=rng)
        # back stays from the post tops down to deadman logs
        for sx in (-1, 1):
            K.rope(ropes, [V((sx * (POST_X + 0.25), y_t, POST_TOP - 0.25)), V((sx * 22.0, y_t, 2.4)),
                           V((sx * 23.8, y_t, 0.45))], 0.09, rp, segs=6, rng=rng)
        # hangers: handrail -> deck edge
        for p in hand[3:-3:2]:
            if abs(p.x) > POST_X - 1.0:
                continue
            q = V((p.x, sy * (W2 - 0.05), z_deck(p.x) - 0.05))
            K.rope(ropes, [p - V((0, 0, 0.05)), q], 0.035, rp, segs=4, rng=rng)
    # lashings where the handrails cross the post tops
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = V((sx * (POST_X + 0.25), sy * (POST_Y + 0.05), POST_TOP - 0.3))
            ring = [c + V((0.42 * math.cos(TAU * k / 8), 0.42 * math.sin(TAU * k / 8), 0.05 * math.sin(3 * k)))
                    for k in range(9)]
            K.rope(ropes, ring, 0.05, rp, segs=4, rng=rng, cap=False)
    K.part(lib, root, ropes, "Rope", collide=False, cast_shadow=True, smooth_angle=60,
           notes="Manila handrails, hangers, back stays and lashings (non-colliding).")

    # ---------------- deadman logs + bank stones (visual)
    dm = K.MB("Log")
    for sx in (-1, 1):
        K.log(dm, V((sx * 23.9, -POST_Y - 1.0, 0.33)), V((sx * 23.9, POST_Y + 1.0, 0.35)), 0.36, 0.34, reg=lw,
              end_reg=(ends(rng), ends(rng)), segs=9, rings=2, rng=rng)
    K.part(lib, root, dm, "Logs", collide=False, smooth_angle=60, notes="Deadman anchor logs (half sunk into the bank).")
    st = K.MB("Stone")
    rk = K.R("Stone", "rock")
    for sx in (-1, 1):
        for (dx, dy, s) in ((0.6, -3.6, 1.2), (1.6, 3.7, 1.0), (-0.2, 4.0, 0.8), (2.4, -3.9, 0.9), (0.4, 0.0, 0.0)):
            if s <= 0:
                continue
            K.rock(st, (sx * (HALF + dx), dy, -0.01), (s, s * 0.85, s * 0.6), rk, rng, subdiv=1, rough=0.3, facets=4)
    K.part(lib, root, st, "Stone", collide=False, smooth_angle=38, notes="Bank stones round the sills (visual).")
    lib.attach(root, "EndA", (-HALF, 0.0, Z_END), look=(-1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "EndB", (HALF, 0.0, Z_END), look=(1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "MidSpan", (0.0, 0.0, z_deck(0.0)), look=(0, 1, 0), up=(0, 0, 1))
    lib.finish(root)
    return root


def review_views(name):
    return [
        ("deck", (-17.5, 0.6, z_deck(-17.5) + 5.0), (6.0, -0.3, 1.0), 70, (36, 60), 0.0, [], (-12.0, 0.4, z_deck(-12.0))),
        ("anchor", (14.0, 9.5, 3.4), (20.5, 0.5, 2.2), 50, (34, 40)),
        ("under", (-6.0, -9.0, -2.4), (2.0, 0.0, 0.0), 55, (40, 160)),
    ]


def preview_setup(P):
    """Review renders only: cut a gorge into the preview ground so the sag reads (banks at |x| > 18.6)."""
    import bpy
    from mathutils import Vector
    g = P._STATE["ground"]
    P._STATE["ground_z"] = g.location.z
    g.location.z = -14.0
    made = []
    for sx in (-1, 1):
        o = P.ls.cube("_BRP_Bank", size=(60.0, 140.0, 14.0), loc=(sx * (18.6 + 30.0), 0.0, -7.0))
        o.data.materials.append(P._ground_material())
        made.append(o)
    P._STATE["banks"] = made


def preview_teardown(P):
    import bpy
    for o in P._STATE.pop("banks", []):
        bpy.data.objects.remove(o, do_unlink=True)
    P._STATE["ground"].location.z = P._STATE.get("ground_z", -0.1)
