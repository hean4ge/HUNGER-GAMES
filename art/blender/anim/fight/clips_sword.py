"""Sword family: Longsword, Machete, Paired Blades (Combat_v3 1.4, 1.5, 2.2, 7.2). Chest space, see fight_lib.

Every light step's hit is the weapon's 1-star windup (the server's strike time); steps after the first start from the
previous step's follow-through, so a chain flows: the diagonal ends low left, where the rising cut starts; the rising
cut ends high right, where the flat cut starts; the flat cut ends left, from where the blade goes over the head into the
overhead.
"""
from fight_lib import HP, Arc, Line
from fight_moves import (Mirrored, attack, body, chain, hold_clip, lerp_body, mirror_body, mirror_hp, off, pose_clip,
                         second_hand, stepping_feet)

FAMILY = "Sword"
ITEMS = {"sword": ("sword_t3", "RightHand"), "machete": ("machete_t3", "RightHand"),
         "paired_R": ("paired_blades_t3", "RightHand"), "paired_L": ("paired_blades_L_t3", "LeftHand")}

GUARD = HP((1.05, 0.95, -0.10), (-0.20, 0.45, 0.87), (0.0, 0.9, -0.45), (0.6, -0.5, -1.0))
OFF_G = off((-1.05, 0.55, -0.55))
BG = body(pelvis=(-10, 0), move=(0, 0, -0.05), chest=(-8, 3))
OFFS = {"guard": OFF_G, "w": off((-0.85, 1.05, 0.02), (-0.7, -0.6, -0.7)), "h": off((-1.30, 0.05, -0.75), (-0.6, -1, -0.2)),
        "f": off((-1.35, -0.30, -0.70), (-0.6, -1, -0.1))}
OFFS_R = {"guard": OFF_G, "w": off((-1.30, 0.10, -0.70)), "h": off((-0.85, 1.05, 0.0), (-0.7, -0.6, -0.7)),
          "f": off((-0.75, 1.15, 0.15), (-0.7, -0.6, -0.7))}

# -- paths -------------------------------------------------------------------------------------------------------------
DIAG = Arc((1.30, -0.24, 1.30), (0.55, 1.42, 0.20), (0.40, 1.00, -0.62), elbow=(1.0, -0.2, 0.2), elbow_hit=(0.5, -0.3, -1.0),
           blades=[(0, (-0.22, -0.52, 0.83)), (0.35, (-0.18, 0.05, 0.98)), (0.7, (-0.28, 0.62, 0.73)),
                   (1, (-0.40, 0.91, -0.02)), ("e", (-0.78, 0.48, -0.40))])
RISE = Arc((0.25, 1.00, -0.45), (0.85, 1.40, 0.30), (1.35, 0.55, 1.10), elbow=(0.5, -0.3, -1.0), elbow_hit=(0.8, -0.4, -0.5),
           blades=[(0, (-0.75, 0.35, -0.55)), (0.5, (0.05, 0.85, -0.5)), (1, (0.35, 0.92, 0.15)), ("e", (0.55, 0.05, 0.83))])
FLAT = Arc((1.45, 0.05, 0.70), (0.35, 1.40, 0.45), (-0.30, 1.00, 0.40), elbow=(0.4, -0.3, -1.0),
           blades=[(0, (0.75, -0.25, 0.60)), (0.5, (0.45, 0.89, 0.05)), (1, (-0.05, 1.0, 0.0)), ("e", (-0.85, 0.52, -0.05))])
OVER = Arc((1.10, -0.15, 1.55), (0.40, 1.45, 0.35), (0.35, 1.20, -0.35), elbow=(0.9, -0.1, 0.3), elbow_hit=(0.6, -0.3, -0.8),
           blades=[(0, (0.0, -0.75, 0.66)), (0.45, (0.0, 0.35, 0.94)), (1, (0.0, 0.94, 0.35)), ("e", (0.0, 0.90, 0.35))])
OVER_PRE = HP((0.55, 0.85, 1.60), (0.1, 0.2, 1.0), (1, 0, 0), (0.9, -0.2, 0.0))
# machete: lower, wider sweeps and a short chop
M_FORE = Arc((1.45, 0.10, 0.40), (0.35, 1.35, 0.15), (-0.30, 0.95, 0.05), elbow=(0.4, -0.3, -1.0),
             blades=[(0, (0.75, -0.30, 0.55)), (0.5, (0.45, 0.89, 0.0)), (1, (-0.05, 1.0, -0.05)), ("e", (-0.85, 0.50, -0.10))])
M_BACK = Arc((-0.25, 0.95, 0.15), (0.60, 1.40, 0.20), (1.45, 0.45, 0.35), elbow=(0.6, -0.5, -0.6),
             blades=[(0, (-0.80, 0.55, 0.10)), (1, (0.05, 1.0, 0.0)), ("e", (0.80, 0.45, 0.30))])
# the Running Cut: a low flat sweep from the right hip across to the left
RUN_CUT = Arc((1.20, -0.30, -0.45), (0.55, 1.35, -0.05), (-0.45, 0.90, 0.00), elbow=(0.5, -0.4, -0.8),
              blades=[(0, (0.45, -0.55, -0.70)), (0.6, (0.60, 0.80, 0.10)), (1, (0.0, 1.0, 0.25)), ("e", (-0.90, 0.40, 0.15))])
COUNTER_CUT = Arc((-0.10, 1.00, 1.00), (0.55, 1.40, 0.45), (1.40, 0.60, 0.30), elbow=(0.5, -0.4, -0.8),
                  blades=[(0, (-0.85, 0.25, 0.45)), (1, (0.10, 1.0, 0.0)), ("e", (0.80, 0.45, 0.20))])
COUNTER_START = HP((0.15, 1.05, 0.95), (-0.90, 0.30, 0.30), (0, 0, 1), (0.6, -0.5, -0.6))

B_DIAG = {"guard": BG, "w": body((-20, -2), (0.05, -0.13, -0.10), (-30, -6, -4)), "h": body((6, 5), (-0.02, 0.14, -0.18), (14, 10, 2)),
          "f": body((12, 6), (-0.03, 0.17, -0.23), (28, 14, 3))}
B_RISE = {"guard": BG, "w": body((14, 4), (-0.04, 0.05, -0.20), (26, 12, 5)), "h": body((-6, 2), (0.02, 0.13, -0.14), (-12, 2, -3)),
          "f": body((-16, -2), (0.04, 0.10, -0.08), (-30, -6, -5))}
B_FLAT = {"guard": BG, "w": body((-20, 0), (0.06, -0.10, -0.10), (-36, 0, -2)), "h": body((8, 3), (-0.02, 0.15, -0.17), (10, 6, 0)),
          "f": body((18, 4), (-0.05, 0.13, -0.18), (36, 8, 3))}
B_BACK = {"guard": BG, "w": body((16, 2), (-0.05, -0.05, -0.12), (32, 4, 2)), "h": body((-6, 3), (0.02, 0.15, -0.17), (-8, 6, 0)),
          "f": body((-16, 3), (0.05, 0.12, -0.16), (-32, 6, -3))}
B_OVER = {"guard": BG, "w": body((-6, -4), (0.0, -0.14, -0.06), (-8, -14, 0)), "h": body((4, 8), (0.0, 0.22, -0.26), (4, 18, 0)),
          "f": body((4, 10), (0.0, 0.24, -0.30), (4, 26, 0))}
OFFS_OVER = {"guard": OFF_G, "w": off((-0.55, 0.75, 0.75), (-0.9, -0.3, -0.2)), "h": off((-0.9, 0.9, -0.2)), "f": off((-1.1, 0.4, -0.6))}
OFFS_BACK = {"guard": OFF_G, "w": off((-0.95, 0.95, -0.15), (-0.7, -0.6, -0.6)), "h": off((-1.30, -0.05, -0.70)),
             "f": off((-1.35, -0.35, -0.65))}

SWORD = dict(item="sword", kind="Blade", family=FAMILY)
MACHETE = dict(item="machete", kind="Blade", family=FAMILY)
PAIRED = dict(item="paired_R", off_item="paired_L", kind="Paired", family=FAMILY, fp_left=True)


def longsword():
    return chain([
        dict(name="sword_light_1", L=0.62, H=0.16, path=DIAG, bodies=B_DIAG, offs=OFFS, **SWORD),
        dict(name="sword_light_2", L=0.62, H=0.16, path=RISE, bodies=B_RISE, offs=OFFS_R, **SWORD),
        dict(name="sword_light_3", L=0.62, H=0.16, path=FLAT, bodies=B_FLAT, offs=OFFS, **SWORD),
        dict(name="sword_light_4", L=0.72, H=0.20, path=OVER, bodies=B_OVER, offs=OFFS_OVER, over=0.04, pre=OVER_PRE, **SWORD),
    ], GUARD, OFF_G)


def machete():
    return chain([
        dict(name="machete_light_1", L=0.55, H=0.14, path=M_FORE, bodies=B_FLAT, offs=OFFS, **MACHETE),
        dict(name="machete_light_2", L=0.55, H=0.14, path=M_BACK, bodies=B_BACK, offs=OFFS_BACK, **MACHETE),
        dict(name="machete_light_3", L=0.62, H=0.17, path=OVER, bodies=B_OVER, offs=OFFS_OVER, over=0.04, **MACHETE),
    ], GUARD, OFF_G)


# -- paired blades: a blade in each hand, edges forward ----------------------------------------------------------------
P_GUARD_R = HP((1.00, 1.00, -0.15), (-0.25, 0.55, 0.80), (0.0, 0.9, -0.45), (0.6, -0.5, -1.0))
P_GUARD_L = mirror_hp(P_GUARD_R)


def p_offs(g):
    return {"guard": g, "w": g.moved((0, 0.15, 0.05)), "h": g.moved((0, -0.30, -0.10)), "f": g.moved((0, -0.35, -0.12))}


SHORT_DIAG = Arc((1.25, 0.05, 1.10), (0.55, 1.40, 0.15), (0.35, 1.00, -0.55), elbow=(1.0, -0.2, 0.0), elbow_hit=(0.5, -0.3, -1.0),
                 blades=[(0, (-0.10, -0.25, 0.96)), (0.5, (-0.25, 0.65, 0.72)), (1, (-0.40, 0.91, -0.02)), ("e", (-0.75, 0.50, -0.40))])
B_PR = {"guard": BG, "w": body((-12, 0), (0.04, -0.06, -0.08), (-18, -3, -2)), "h": body((6, 4), (-0.02, 0.12, -0.14), (12, 8, 1)),
        "f": body((10, 5), (-0.02, 0.12, -0.16), (20, 10, 2))}
B_PL = {k: mirror_body(v) for k, v in B_PR.items()}
B_PL["guard"] = BG
B_CROSS = {"guard": BG, "w": body((-4, -3), (0, -0.10, -0.06), (-4, -10, 0)), "h": body((0, 8), (0, 0.20, -0.24), (0, 16, 0)),
           "f": body((0, 10), (0, 0.22, -0.28), (0, 22, 0))}
X_R = Arc((1.35, 0.10, 1.25), (0.45, 1.45, 0.25), (-0.30, 1.00, -0.45), elbow=(1.0, -0.2, 0.2), elbow_hit=(0.6, -0.3, -0.9),
          blades=[(0, (0.10, -0.30, 0.95)), (1, (-0.55, 0.83, -0.05)), ("e", (-0.80, 0.40, -0.45))])


def paired():
    steps = chain([
        dict(name="paired_light_1", L=0.38, H=0.07, path=SHORT_DIAG, bodies=B_PR, offs=p_offs(P_GUARD_L), **PAIRED),
        dict(name="paired_light_2", L=0.38, H=0.07, path=Mirrored(SHORT_DIAG), bodies=B_PL, offs=p_offs(P_GUARD_R),
             hand="Left", **PAIRED),
        dict(name="paired_light_3", L=0.38, H=0.07, path=RISE, bodies=B_RISE, offs=p_offs(P_GUARD_L), **PAIRED),
    ], P_GUARD_R, P_GUARD_L)
    steps = [_paired_guard(c) for c in steps]
    c4 = attack("paired_light_4", 0.50, 0.12, X_R, P_GUARD_R, B_CROSS, start=steps[-1].right(steps[-1].end_t),
                start_body=steps[-1].body.raw(steps[-1].end_t), **PAIRED)
    second_hand(c4, Mirrored(X_R), P_GUARD_L, start=steps[-1].left(steps[-1].end_t))
    steps.append(c4)
    return steps


def _paired_guard(c):
    return c


# -- heavies, counters, the skill, equip -------------------------------------------------------------------------------
CHARGE_R = HP((1.35, -0.45, 1.35), (-0.15, -0.65, 0.75), (0.1, 0.6, 0.8), (1.0, -0.3, 0.2))
CHARGE_OFF = off((-0.80, 1.10, 0.10), (-0.7, -0.6, -0.7))
B_CHARGE = body((-24, -3), (0.06, -0.18, -0.20), (-36, -8, -5))
HEAVY_DIAG = Arc((1.35, -0.45, 1.35), (0.50, 1.45, 0.15), (0.20, 0.95, -0.70), elbow=(1.0, -0.2, 0.2), elbow_hit=(0.5, -0.3, -1.0),
                 blades=[(0, (-0.15, -0.65, 0.75)), (0.4, (-0.18, 0.15, 0.97)), (0.75, (-0.30, 0.70, 0.65)),
                         (1, (-0.45, 0.89, -0.05)), ("e", (-0.85, 0.45, -0.15))])
B_HEAVY = {"guard": BG, "w": B_CHARGE, "h": body((12, 10), (-0.05, 0.55, -0.42), (18, 14, 3)),
           "f": body((18, 12), (-0.06, 0.62, -0.45), (32, 18, 4))}
LUNGE = {"Left": [(0.0, (0, 0, 0), 0), (0.06, (0, 0.45, 0.25), 0), (0.14, (0, 1.10, 0), 0), (0.50, (0, 1.10, 0), 0),
                  (0.64, (0, 0.55, 0.22), 0), (0.76, (0, 0, 0), 0)],
         "Right": [(0.0, (0, 0, 0), 0), (0.16, (0, 0, 0), 0), (0.70, (0, 0, 0), 0)]}


def heavies():
    out = []
    out.append(hold_clip("sword_heavy_charge", 0.5, CHARGE_R, CHARGE_OFF, B_CHARGE, item="sword", kind="Blade", family=FAMILY))
    h = attack("sword_heavy", 0.79, 0.16, HEAVY_DIAG, GUARD, B_HEAVY, offs={"guard": OFF_G, "w": CHARGE_OFF, "h": OFFS["h"], "f": OFFS["f"]},
               start=CHARGE_R, start_body=B_CHARGE, start_off=CHARGE_OFF, tw=0.05, mask="full", **SWORD)
    out.append(stepping_feet(h, LUNGE))
    # paired: both blades high and wide, then scissor across
    pc = attack("paired_heavy", 0.65, 0.12, X_R, P_GUARD_R, {"guard": BG, "w": body((0, -4), (0, -0.14, -0.12), (0, -10, 0)),
                "h": body((0, 10), (0, 0.30, -0.30), (0, 18, 0)), "f": body((0, 12), (0, 0.32, -0.34), (0, 24, 0))},
                tw=0.07, over=0.08, **PAIRED)
    second_hand(pc, Mirrored(X_R), P_GUARD_L)
    out.append(pc)
    out.append(attack("sword_counter", 0.47, 0.06, COUNTER_CUT, GUARD, B_BACK, offs=OFFS_BACK, start=COUNTER_START,
                      start_body=body((10, 0), (0, -0.05, -0.08), (14, -4, 0)), tw=0.03, **SWORD))
    pcn = attack("paired_counter", 0.47, 0.06, Line((0.90, 0.80, 0.20), (0.45, 1.60, 0.30), (-0.15, 1, 0.05), (0, 0, -1), (0.6, -0.5, -0.8)),
                 P_GUARD_R, {"guard": BG, "w": body((-6, 0), (0, -0.08, -0.08), (-10, 0, 0)), "h": body((4, 6), (0, 0.22, -0.18), (8, 8, 0)),
                             "f": body((4, 6), (0, 0.22, -0.18), (8, 8, 0))}, tw=0.03, over=0.0, **PAIRED)
    second_hand(pcn, Mirrored(Line((0.90, 0.80, 0.20), (0.45, 1.60, 0.30), (-0.15, 1, 0.05), (0, 0, -1), (0.6, -0.5, -0.8))),
                P_GUARD_L)
    out.append(pcn)
    # Running Cut: 0.2 s crouch with the blade chambered low behind, a 0.3 s dash cutting through the lane, recover
    rc = attack("sword_skill_running_cut", 0.90, 0.20, RUN_CUT, GUARD,
                {"guard": BG, "w": body((-28, 18), (0.08, -0.10, -0.55), (-30, 10, -4)),
                 "h": body((-8, 22), (0.00, 0.30, -0.55), (-4, 14, 0)), "f": body((20, 18), (-0.05, 0.40, -0.50), (34, 14, 3))},
                offs={"guard": OFF_G, "w": off((-0.95, 1.20, -0.10)), "h": off((-1.20, 0.30, -0.40)), "f": off((-1.30, -0.40, -0.55))},
                tw=0.17, tf=0.50, settle=0.08, mask="full", markers={"CutEnd": 0.50}, **SWORD)
    out.append(stepping_feet(rc, {
        "Left": [(0.0, (0, 0, 0), 0), (0.10, (0, 0.5, 0.2), 0), (0.18, (0, 0.95, 0), 0), (0.55, (0, 0.95, 0), 0),
                 (0.72, (0, 0.4, 0.2), 0), (0.86, (0, 0, 0), 0)],
        "Right": [(0.0, (0, 0, 0), 0), (0.18, (0, -0.55, 0), 0), (0.30, (0, -0.55, 0.15), -10), (0.45, (0, -0.55, 0), 0),
                  (0.86, (0, 0, 0), 0)]}))
    # equip: from the left hip, drawn up across the body into the guard
    out.append(pose_clip("equip_sword", 0.32,
                         [(0.0, HP((-0.15, 0.95, -0.85), (-0.10, -0.85, -0.50), (0, 0, 1), (0.6, -0.4, -1.0))),
                          (0.12, HP((0.70, 1.05, -0.10), (0.30, 0.60, 0.74), (0, 1, 0), (0.7, -0.5, -0.8))),
                          (0.22, HP((1.15, 1.00, 0.05), (-0.15, 0.40, 0.90), (0, 0.9, -0.45), (0.6, -0.5, -1.0))),
                          (0.32, GUARD)],
                         [(0.0, off((-0.95, 0.45, -0.75))), (0.32, OFF_G)],
                         [(0.0, body((8, 2), (0, 0, -0.06), (14, 4))), (0.14, body((-12, 0), (0, 0, -0.06), (-12, 3))), (0.32, BG)],
                         guardness=lambda t: (t / 0.32) ** 2,
                         **SWORD))
    return out


def clips():
    return longsword() + machete() + paired() + heavies()


SHEET_VIEW = dict(azim=55.0, elev=14.0, dist=17.0, target=(0.0, 0.8, 3.3))
SHEET = [("sword_light_1", 0.0, "guard"), ("sword_light_1", 0.09, "wind-up"), ("sword_light_1", 0.16, "HIT 1"),
         ("sword_light_1", 0.30, "follow-through"), ("sword_light_2", 0.08, "2: coil low"), ("sword_light_2", 0.16, "HIT 2 rising"),
         ("sword_light_3", 0.16, "HIT 3 flat"), ("sword_light_4", 0.20, "HIT 4 overhead")]
