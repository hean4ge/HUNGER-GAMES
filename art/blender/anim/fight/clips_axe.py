"""Axes (Combat_v3 1.4, 1.5, 2.2): Hatchet, Twin-Bit Axe (two hands), Climbing Pick; the overhead heavies, the counter,
Whirl. Heavier than blades: longer wind-ups that sink the weight back, a committed drop of the hips into the hit, and a
slow recovery (the weight of the head)."""
import math

from mathutils import Matrix, Vector

import fight_lib as fl
from fight_lib import HP, Arc, Line
from fight_moves import attack, body, chain, hold_clip, off, pose_clip, stepping_feet

FAMILY = "Axe"
ITEMS = {"hatchet": ("hatchet_t3", "RightHand"), "twin": ("twin_axe_t3", "RightHand"), "pick": ("climb_pick_t3", "RightHand")}

GUARD = HP((1.00, 0.85, -0.05), (-0.10, 0.35, 0.93), (0.0, 1.0, 0.0), (0.6, -0.5, -1.0))
OFF_G = off((-1.00, 0.70, -0.40))
BG = body((-12, 2), (0, 0, -0.10), (-8, 5))
OFFS = {"guard": OFF_G, "w": off((-0.80, 1.10, 0.05), (-0.7, -0.6, -0.7)), "h": off((-1.25, 0.10, -0.70)), "f": off((-1.30, -0.25, -0.70))}
OFFS_R = {"guard": OFF_G, "w": off((-1.25, 0.15, -0.60)), "h": off((-0.85, 1.05, -0.05), (-0.7, -0.6, -0.7)), "f": off((-0.80, 1.10, 0.05))}

CHOP = Arc((1.30, -0.20, 1.35), (0.50, 1.40, 0.20), (0.35, 0.95, -0.55), elbow=(1.0, -0.2, 0.2), elbow_hit=(0.5, -0.3, -1.0),
           blades=[(0, (-0.15, -0.55, 0.82)), (0.4, (-0.15, 0.10, 0.98)), (1, (-0.35, 0.90, 0.25)), ("e", (-0.55, 0.75, -0.30))])
BACKCHOP = Arc((-0.35, 0.85, 1.30), (0.70, 1.40, 0.25), (1.30, 0.80, -0.45), elbow=(0.3, -0.5, -0.6), elbow_hit=(0.7, -0.3, -0.7),
               blades=[(0, (0.20, -0.45, 0.87)), (1, (0.35, 0.90, 0.20)), ("e", (0.65, 0.65, -0.35))])
OVERHEAD = Arc((1.05, -0.20, 1.55), (0.45, 1.40, 0.35), (0.40, 1.15, -0.40), elbow=(0.9, -0.1, 0.3), elbow_hit=(0.6, -0.3, -0.8),
               blades=[(0, (0.0, -0.75, 0.66)), (0.45, (0.0, 0.30, 0.95)), (1, (0.0, 0.92, 0.38)), ("e", (0.0, 0.85, 0.10))])
OVER_PRE = HP((0.60, 0.90, 1.55), (0.1, 0.2, 1.0), (0, 1, 0), (0.9, -0.2, 0.0))
PECK = Arc((1.00, 0.20, 1.40), (0.50, 1.35, 0.40), (0.45, 1.10, -0.10), elbow=(0.9, -0.1, 0.2), elbow_hit=(0.6, -0.3, -0.8),
           blades=[(0, (0.0, -0.40, 0.92)), (1, (0.0, 0.95, 0.30)), ("e", (0.0, 0.85, 0.10))])
HOOKPULL = Arc((0.95, 0.40, 1.30), (0.45, 1.40, 0.30), (0.75, 0.35, -0.35), elbow=(0.9, -0.1, 0.2), elbow_hit=(0.7, -0.5, -0.6),
               blades=[(0, (0.0, -0.20, 0.98)), (1, (0.0, 0.95, 0.30)), ("e", (0.05, 0.85, -0.20))])
# twin axe: two hands, the left low on the haft
T_GUARD = HP((0.30, 1.00, 0.10), (0.50, 0.10, 0.85), (0.0, 1.0, 0.0), (0.6, -0.5, -1.0))
SWEEP_RL = Arc((1.45, -0.10, 0.75), (0.40, 1.40, 0.40), (-0.60, 0.70, 0.30), elbow=(0.4, -0.3, -1.0),
               blades=[(0, (0.70, -0.55, 0.45)), (0.5, (0.55, 0.83, 0.10)), (1, (-0.10, 1.0, 0.05)), ("e", (-0.90, 0.40, 0.0))])
SWEEP_LR = Arc((-0.55, 0.75, 0.35), (0.55, 1.40, 0.40), (1.45, 0.20, 0.55), elbow=(0.5, -0.4, -0.8),
               blades=[(0, (-0.90, 0.40, 0.0)), (1, (0.15, 1.0, 0.05)), ("e", (0.85, -0.10, 0.30))])

B_CHOP = {"guard": BG, "w": body((-22, -4), (0.06, -0.18, -0.10), (-30, -10, -4)), "h": body((8, 10), (-0.02, 0.20, -0.30), (14, 16, 2)),
          "f": body((14, 12), (-0.03, 0.22, -0.34), (26, 22, 3))}
B_BACK = {"guard": BG, "w": body((18, -4), (-0.05, -0.15, -0.10), (30, -10, 4)), "h": body((-8, 10), (0.02, 0.20, -0.30), (-12, 16, -2)),
          "f": body((-14, 12), (0.03, 0.22, -0.34), (-24, 22, -3))}
B_OVER = {"guard": BG, "w": body((-6, -6), (0, -0.18, -0.08), (-8, -16)), "h": body((4, 12), (0, 0.25, -0.34), (4, 22)),
          "f": body((4, 14), (0, 0.27, -0.38), (4, 28))}
B_SWEEP_RL = {"guard": BG, "w": body((-30, 0), (0.10, -0.15, -0.20), (-40, 0, -3)), "h": body((10, 6), (-0.04, 0.18, -0.30), (16, 8, 2)),
              "f": body((28, 6), (-0.08, 0.15, -0.30), (44, 8, 4))}
B_SWEEP_LR = {"guard": BG, "w": body((28, 4), (-0.08, 0.10, -0.28), (40, 6, 3)), "h": body((-10, 6), (0.04, 0.18, -0.30), (-16, 8, -2)),
              "f": body((-28, 6), (0.10, 0.12, -0.28), (-44, 6, -4))}
OFFS_OVER = {"guard": OFF_G, "w": off((-0.55, 0.75, 0.75), (-0.9, -0.3, -0.2)), "h": off((-0.9, 0.9, -0.2)), "f": off((-1.1, 0.4, -0.6))}

HATCHET = dict(item="hatchet", kind="Blade", family=FAMILY)
TWIN = dict(item="twin", kind="Blade", family=FAMILY, fp_left=True)
PICK = dict(item="pick", kind="Blade", family=FAMILY)


def two_hands(c, along=-0.60, grip_from=None):
    """The left hand on the haft below the right; with grip_from = (t0, t1) it lets go / takes hold over that span."""
    c.left_on = (along, (0, 0, 0))
    if grip_from:
        a, b = grip_from
        c.left_on_w = lambda t: 1.0 - fl.ramp(t, a, b)
    return c


def chains():
    out = []
    out += chain([
        dict(name="hatchet_light_1", L=0.80, H=0.18, path=CHOP, bodies=B_CHOP, offs=OFFS, **HATCHET),
        dict(name="hatchet_light_2", L=0.80, H=0.18, path=BACKCHOP, bodies=B_BACK, offs=OFFS_R, **HATCHET),
        dict(name="hatchet_light_3", L=0.90, H=0.22, path=OVERHEAD, bodies=B_OVER, offs=OFFS_OVER, pre=OVER_PRE, over=0.04, **HATCHET),
    ], GUARD, OFF_G)
    tw = chain([
        dict(name="twinaxe_light_1", L=0.95, H=0.30, path=SWEEP_RL, bodies=B_SWEEP_RL, offs=OFFS, tf=0.46, settle=0.08, **TWIN),
        dict(name="twinaxe_light_2", L=0.95, H=0.26, path=SWEEP_LR, bodies=B_SWEEP_LR, offs=OFFS, tf=0.42, settle=0.08, **TWIN),
    ], T_GUARD, OFF_G)
    out += [two_hands(c) for c in tw]
    out += chain([
        dict(name="pick_light_1", L=0.65, H=0.14, path=PECK, bodies=B_OVER, offs=OFFS_OVER, over=0.03, **PICK),
        dict(name="pick_light_2", L=0.65, H=0.14, path=PECK, bodies=B_OVER, offs=OFFS_OVER, over=0.03, **PICK),
        dict(name="pick_light_3", L=0.70, H=0.16, path=HOOKPULL, bodies=B_OVER, offs=OFFS_OVER, over=0.02, tf=0.36, **PICK),
    ], GUARD, OFF_G)
    return out


def specials():
    out = []
    raised = HP((1.05, -0.25, 1.55), (0.0, -0.75, 0.66), (0, 1, 0), (0.9, -0.1, 0.3))
    b_raised = body((-8, -8), (0, -0.20, -0.12), (-10, -16))
    out.append(hold_clip("axe_heavy_charge", 0.5, raised, OFFS_OVER["w"], b_raised, sway=(0, 0, 0.02), **HATCHET))
    h = attack("axe_heavy", 0.79, 0.16, OVERHEAD, GUARD, {"guard": BG, "w": b_raised, "h": body((4, 16), (0, 0.55, -0.50), (4, 26)),
                                                          "f": body((4, 18), (0, 0.58, -0.55), (4, 32))},
               offs=OFFS_OVER, start=raised, start_body=b_raised, start_off=OFFS_OVER["w"], tw=0.05, over=0.03, mask="full", **HATCHET)
    step = {"Left": [(0, (0, 0, 0), 0), (0.06, (0, 0.40, 0.25), 0), (0.15, (0, 1.00, 0), 0), (0.50, (0, 1.00, 0), 0),
                     (0.64, (0, 0.50, 0.22), 0), (0.77, (0, 0, 0), 0)], "Right": [(0, (0, 0, 0), 0), (0.79, (0, 0, 0), 0)]}
    out.append(stepping_feet(h, step))
    traised = HP((0.80, -0.20, 1.50), (0.0, -0.80, 0.60), (0, 1, 0), (0.9, -0.1, 0.3))
    th = attack("twinaxe_heavy", 1.00, 0.22, OVERHEAD, T_GUARD, {"guard": BG, "w": b_raised, "h": body((2, 18), (0, 0.60, -0.55), (2, 28)),
                                                                 "f": body((2, 20), (0, 0.62, -0.60), (2, 34))},
                start=traised, start_body=b_raised, tw=0.08, over=0.02, tf=0.40, settle=0.12, mask="full", **TWIN)
    two_hands(th)
    out.append(stepping_feet(th, {"Left": [(0, (0, 0, 0), 0), (0.08, (0, 0.40, 0.25), 0), (0.20, (0, 1.05, 0), 0), (0.65, (0, 1.05, 0), 0),
                                           (0.82, (0, 0.5, 0.22), 0), (0.97, (0, 0, 0), 0)], "Right": [(0, (0, 0, 0), 0), (1.0, (0, 0, 0), 0)]}))
    out.append(attack("axe_counter", 0.47, 0.06, CHOP, GUARD, B_CHOP, offs=OFFS, tw=0.02, start=GUARD.moved((0.2, -0.4, 0.9)), **HATCHET))
    out.append(whirl())
    out.append(pose_clip("equip_axe", 0.32, [(0, HP((1.05, 0.10, -0.95), (0.1, 0.3, -0.95), (0, 1, 0), (0.6, -0.4, -1.0))),
                                             (0.18, GUARD.moved((0.1, 0.1, 0.25))), (0.32, GUARD)],
                         [(0, off((-0.95, 0.45, -0.75))), (0.32, OFF_G)], [(0, body((0, 0), (0, 0, -0.05), (0, 0))), (0.32, BG)],
                         guardness=lambda t: (t / 0.32) ** 2, **HATCHET))
    return out


def whirl():
    """Whirl: the axe pulled across the body (0.35 s, readable), one full turn (0.30 s) with the axe out at arm's length,
    then back to the guard. The feet pivot with the hips."""
    L = 1.15
    across = HP((-0.35, 1.00, 0.30), (-0.90, 0.30, 0.30), (0, 1, 0), (0.4, -0.5, -0.8))
    out_ = HP((1.55, 0.55, 0.35), (0.95, 0.25, 0.15), (0, 1, 0), (0.7, -0.6, -0.4))
    c = pose_clip("axe_skill_whirl", L, [(0, GUARD), (0.30, across), (0.38, across.moved((-0.05, 0, 0))), (0.45, out_), (0.62, out_),
                                         (0.80, GUARD.moved((0.2, 0, 0.1))), (L, GUARD)],
                  [(0, OFF_G), (0.30, off((-0.9, 0.8, 0.0))), (0.45, off((-1.30, -0.30, 0.10), (-1, -0.2, -0.2))), (0.70, off((-1.2, 0.2, -0.4))), (L, OFF_G)],
                  [(0, BG), (L, BG)], hit=0.35, markers={"TurnEnd": 0.65}, mask="full", look=None, **HATCHET)
    yaw = fl.Spline([(0, -12), (0.30, 35), (0.37, 35), (0.50, -150), (0.65, -325), (0.80, -350), (L, -372)])
    chest = fl.Spline([(0, -8), (0.30, 30), (0.40, 10), (0.55, -10), (0.70, -6), (L, -8)])
    drop = fl.Spline([(0, -0.10), (0.32, -0.30), (0.50, -0.38), (0.70, -0.30), (L, -0.10)])

    def bodyf(t):
        return {"pelvis": (yaw(t), 6, 0), "move": (0, 0, drop(t)), "chest": (chest(t), 8, 0),
                "head": (-0.6 * chest(t), -6, 0)}
    bodyf.raw = bodyf
    c.body = bodyf
    c.planted = False
    c.pivot_feet = lambda t: yaw(t) + 12
    return c


def clips():
    return chains() + specials()


SHEET_VIEW = dict(azim=55.0, elev=12.0, dist=19.0, target=(0.0, 0.6, 3.3))
SHEET = [("hatchet_light_1", 0.0, "guard"), ("hatchet_light_1", 0.10, "wind-up, weight back"), ("hatchet_light_1", 0.18, "HIT chop"),
         ("hatchet_light_1", 0.36, "follow-through"), ("twinaxe_light_1", 0.30, "TWIN AXE sweep"), ("axe_heavy", 0.16, "HEAVY overhead"),
         ("axe_skill_whirl", 0.30, "whirl: pull across"), ("axe_skill_whirl", 0.50, "WHIRL turn")]
