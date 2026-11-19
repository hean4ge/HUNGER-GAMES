"""Common: the moves every melee weapon shares (Combat_v3 1.3, 1.8, 2.3, 7.2): guard, block, parry, kick, dodges, hit
reactions, staggers, knockdown, the general skills. Authored with a longsword in hand (held-item agnostic: the hand
does the same with any one-handed weapon). Reactions are upper-body and additive (a change from their first sample, on
top of whatever the body does); staggers, dodges and the knockdown own the legs."""
import math

from mathutils import Matrix, Vector

import fight_lib as fl
from fight_lib import HP
from fight_moves import body, hold_clip, mirror_body, off, pose_clip, stepping_feet

FAMILY = "Common"
ITEMS = {"sword": ("sword_t3", "RightHand")}
COMMON = dict(item="sword", kind="Blade", family=FAMILY)

GUARD = HP((1.05, 0.95, -0.10), (-0.20, 0.45, 0.87), (0.0, 0.9, -0.45), (0.6, -0.5, -1.0))
OFF_G = off((-1.05, 0.55, -0.55))
BG = body(pelvis=(-10, 0), move=(0, 0, -0.05), chest=(-8, 3))
# the block: forearm up across the chest, the blade slanted up and to the left in front of the face, edge out
BLOCK = HP((0.70, 1.15, 0.55), (-0.80, 0.20, 0.56), (0.0, 1.0, 0.0), (0.8, -0.3, -0.6))
BLOCK_OFF = off((-0.55, 1.05, 0.30), (-0.8, -0.4, -0.5))
B_BLOCK = body((-6, 2), (0, -0.04, -0.16), (-4, 7))


def guard_set():
    out = []
    out.append(pose_clip("guard_in", 0.10, [(0, GUARD), (0.10, BLOCK)], [(0, OFF_G), (0.10, BLOCK_OFF)],
                         [(0, BG), (0.10, B_BLOCK)], guardness=lambda t: 1 - t / 0.10, **COMMON))
    out.append(hold_clip("guard_hold", 1.0, BLOCK, BLOCK_OFF, B_BLOCK, breathe=0.015, **COMMON))
    out.append(pose_clip("guard_out", 0.12, [(0, BLOCK), (0.12, GUARD)], [(0, BLOCK_OFF), (0.12, OFF_G)],
                         [(0, B_BLOCK), (0.12, BG)], guardness=lambda t: t / 0.12, **COMMON))
    jolt = BLOCK.moved((0.05, -0.28, 0.06))
    out.append(pose_clip("block_hit", 0.25, [(0, BLOCK), (0.03, BLOCK.moved((0.02, -0.12, 0.03))), (0.07, jolt), (0.25, BLOCK)],
                         [(0, BLOCK_OFF), (0.07, BLOCK_OFF.moved((0, -0.2, 0.03))), (0.25, BLOCK_OFF)],
                         [(0, B_BLOCK), (0.07, body((-8, -3), (0, -0.12, -0.18), (-6, -4))), (0.25, B_BLOCK)],
                         hit=0.03, guardness=lambda t: 0.0, **COMMON))
    gb = pose_clip("guard_break", 0.80,
                   [(0, BLOCK), (0.12, HP((1.45, 0.20, 0.85), (0.30, -0.20, 0.93), (0, 1, 0), (1.0, -0.3, -0.2))),
                    (0.35, HP((1.40, 0.35, 0.40), (0.20, 0.10, 0.97), (0, 1, 0), (1.0, -0.4, -0.5))), (0.80, GUARD)],
                   [(0, BLOCK_OFF), (0.12, off((-1.45, 0.20, 0.30), (-1, -0.3, -0.3))), (0.35, off((-1.35, 0.20, -0.20))), (0.80, OFF_G)],
                   [(0, B_BLOCK), (0.12, body((-14, -10), (0, -0.30, -0.12), (-10, -16, 3), (0, 10))),
                    (0.35, body((-12, -6), (0, -0.45, -0.25), (-6, -6, 2))), (0.80, BG)],
                   mask="full", look=(0.5, 0.3, 0.3), **COMMON)
    out.append(stepping_feet(gb, {"Right": [(0, (0, 0, 0), 0), (0.12, (0, -0.25, 0.25), 0), (0.26, (0.05, -0.75, 0), -8),
                                            (0.55, (0.05, -0.75, 0), -8), (0.68, (0, -0.3, 0.2), 0), (0.80, (0, 0, 0), 0)],
                                  "Left": [(0, (0, 0, 0), 0), (0.26, (0, -0.15, 0), 0), (0.60, (0, -0.15, 0), 0), (0.80, (0, 0, 0), 0)]}))
    # parry: meet the blow early and beat it aside to the right, then back to guard (the counter can follow)
    meet = HP((0.80, 1.30, 0.55), (-0.45, 0.45, 0.77), (-0.4, 0.8, 0), (0.8, -0.3, -0.6))
    beat = HP((1.35, 1.05, 0.65), (0.55, 0.55, 0.63), (0.7, 0.6, 0), (0.9, -0.3, -0.4))
    out.append(pose_clip("parry", 0.30, [(0, GUARD), (0.05, meet), (0.12, beat), (0.18, beat.moved((0.03, -0.05, -0.03))), (0.30, GUARD)],
                         [(0, OFF_G), (0.05, BLOCK_OFF), (0.30, OFF_G)],
                         [(0, BG), (0.05, body((-4, 3), (0, 0.05, -0.12), (2, 6))), (0.12, body((-14, 2), (0.03, 0.02, -0.12), (-18, 4))),
                          (0.30, BG)], hit=0.05, markers={"Deflect": 0.05}, **COMMON))
    return out


def kick():
    k = pose_clip("kick", 0.59, [(0, GUARD), (0.16, GUARD.moved((0.05, -0.15, 0.15))), (0.59, GUARD)],
                  [(0, OFF_G), (0.12, off((-1.0, 0.9, 0.2), (-0.8, -0.4, -0.5))), (0.59, OFF_G)],
                  [(0, BG), (0.10, body((-6, -6), (0, -0.05, -0.10), (-6, -2))), (0.16, body((-4, -14), (0, -0.18, -0.08), (-4, -6))),
                   (0.30, body((-6, -8), (0, -0.10, -0.10), (-6, 0))), (0.59, BG)],
                  hit=0.16, mask="full", **COMMON)
    return stepping_feet(k, {"Right": [(0, (0, 0, 0), 0), (0.09, (0, 0.30, 0.75), 0), (0.16, (0, 1.55, 1.35), 0),
                                       (0.24, (0, 1.30, 1.10), 0), (0.38, (0, 0.40, 0.55), 0), (0.52, (0, 0, 0), 0)],
                             "Left": [(0, (0, 0, 0), 0), (0.59, (0, 0, 0), 0)]})


def dodges():
    out = []
    low = body((-6, 8), (0, 0, -0.45), (-6, 10))
    d = pose_clip("dodge_back", 0.55, [(0, GUARD), (0.15, GUARD.moved((0, -0.1, -0.1))), (0.55, GUARD)],
                  [(0, OFF_G), (0.15, off((-1.0, 0.8, -0.2))), (0.55, OFF_G)],
                  [(0, BG), (0.12, low), (0.25, body((-6, -8), (0, 0, -0.15), (-6, -8))), (0.40, body((-6, 10), (0, 0, -0.40), (-6, 8))), (0.55, BG)],
                  mask="full", markers={"Travel": 0.15, "Land": 0.40}, fp=False, **COMMON)
    out.append(stepping_feet(d, {"Right": [(0, (0, 0, 0), 0), (0.15, (0, 0, 0), 0), (0.25, (0, 0.15, 0.35), 0), (0.40, (0, 0, 0), 0)],
                                 "Left": [(0, (0, 0, 0), 0), (0.15, (0, 0, 0), 0), (0.25, (0, 0.25, 0.40), 0), (0.40, (0, 0, 0), 0)]}))
    for side, sgn in (("left", -1), ("right", 1)):
        lean = body((-10, 4), (0.15 * sgn, 0, -0.35), (-8, 4, 14 * sgn))
        air = body((-10, 0), (0.05 * sgn, 0, -0.10), (-8, 0, 10 * sgn))
        lead = "Left" if sgn < 0 else "Right"
        trail = "Right" if sgn < 0 else "Left"
        d = pose_clip("dodge_" + side, 0.55, [(0, GUARD), (0.55, GUARD)], [(0, OFF_G), (0.25, off((-1.25, 0.6, -0.2))), (0.55, OFF_G)],
                      [(0, BG), (0.13, lean), (0.27, air), (0.40, lean), (0.55, BG)], mask="full",
                      markers={"Travel": 0.15, "Land": 0.40}, fp=False, **COMMON)
        out.append(stepping_feet(d, {lead: [(0, (0, 0, 0), 0), (0.15, (0, 0, 0), 0), (0.27, (0.25 * sgn, 0, 0.45), 0), (0.40, (0, 0, 0), 0)],
                                     trail: [(0, (0, 0, 0), 0), (0.18, (0, 0, 0), 0), (0.30, (0.15 * sgn, 0, 0.35), 0), (0.42, (0, 0, 0), 0)]}))
    out.append(roll())
    return out


def roll():
    """dodge_roll: a compact forward roll in place (the body travels by physics): tuck, one turn, up into the guard."""
    L = 0.60
    tuck_hand_R = HP((0.55, 1.00, -0.75), (-0.2, 0.9, -0.3), (0, 0, 1), (0.6, -0.2, -1.0))
    c = pose_clip("dodge_roll", L, [(0, GUARD), (0.10, tuck_hand_R), (0.48, tuck_hand_R), (0.60, GUARD)],
                  [(0, OFF_G), (0.10, off((-0.55, 1.00, -0.75))), (0.48, off((-0.55, 1.00, -0.75))), (0.60, OFF_G)],
                  [(0, BG), (0.60, BG)], mask="full", markers={"Travel": 0.15, "Land": 0.45}, fp=False, look=None, **COMMON)
    pitch = fl.Spline([(0, 0), (0.10, 25), (0.15, 70), (0.27, 180), (0.39, 290), (0.47, 350), (0.54, 360), (0.60, 360)])
    drop = fl.Spline([(0, -0.05), (0.10, -0.6), (0.18, -1.35), (0.38, -1.35), (0.48, -0.7), (0.60, -0.05)])
    chest = fl.Spline([(0, 3), (0.10, 25), (0.45, 25), (0.60, 3)])

    def bodyf(t):
        return {"pelvis": (0, pitch(t), 0), "move": (0, 0, drop(t)), "chest": (0, chest(t), 0), "head": (0, 20 if 0.08 < t < 0.5 else 0, 0)}
    bodyf.raw = bodyf
    c.body = bodyf
    # feet tucked under the pelvis, carried round with it
    knee = fl.Spline([(0, 0), (0.12, 1), (0.46, 1), (0.60, 0)])
    feet = {}
    for side, x in (("Right", 0.45), ("Left", -0.45)):
        def ff(t, x=x, side=side):
            k = knee(t)
            th = math.radians(pitch(t))
            R = Matrix.Rotation(-th, 3, "X")  # (pitch + = forward: about -X)
            pel = Vector((0, 0, 3.0 + drop(t)))  # pelvis height above the feet's rest (approx.)
            tucked = pel + R @ Vector((0, 0.35, -1.25))
            rest = Vector((0, 0, 0))
            p = rest.lerp(tucked - Vector((0, 0, 3.0)), k)
            return p, 0.0
        feet[side] = ff
    c.feet = feet
    c.planted = False
    return c


def reactions():
    out = []
    dirs = {"F": (body((0, -4), (0, -0.06, -0.03), (0, -10), (0, -14)), (0, -0.18, 0.05)),
            "B": (body((0, 4), (0, 0.06, -0.05), (0, 10), (0, 12)), (0, 0.10, -0.05)),
            "L": (body((-6, 0, 4), (0.06, 0, -0.03), (-8, 0, 10), (-6, 0, 10)), (0.12, 0, 0)),
            "R": (body((6, 0, -4), (-0.06, 0, -0.03), (8, 0, -10), (6, 0, -10)), (-0.12, 0, 0))}
    for k, (b, push) in dirs.items():
        hit = {key: tuple(x + y for x, y in zip(BG[key], b[key])) for key in BG}
        back = {key: tuple(x + 0.35 * y for x, y in zip(BG[key], b[key])) for key in BG}
        out.append(pose_clip("react_light_" + k, 0.33, [(0, GUARD), (0.07, GUARD.moved(push)), (0.33, GUARD)],
                             [(0, OFF_G), (0.07, OFF_G.moved((push[0], push[1] * 0.8, push[2] + 0.08))), (0.33, OFF_G)],
                             [(0, BG), (0.07, hit), (0.16, back), (0.33, BG)], additive=True, fp=False, look=None,
                             guardness=lambda t: 0.0, **COMMON))
    # staggers: the torso turns into the hit and one foot steps back (front), forward (back), aside (sides)
    st = {"F": (body((0, -10), (0, -0.30, -0.18), (0, -14), (0, -10)), {"Right": (0.05, -0.70, 0), "Left": (0, -0.15, 0)}),
          "B": (body((0, 12), (0, 0.25, -0.18), (0, 14), (0, 8)), {"Left": (0, 0.70, 0), "Right": (0, 0.15, 0)}),
          "L": (body((-14, 0, 8), (0.25, 0, -0.18), (-12, 0, 12)), {"Right": (0.55, -0.10, 0), "Left": (0.20, 0, 0)}),
          "R": (body((14, 0, -8), (-0.25, 0, -0.18), (12, 0, -12)), {"Left": (-0.55, -0.10, 0), "Right": (-0.20, 0, 0)})}
    for k, (b, steps) in st.items():
        hit = {key: tuple(x + y for x, y in zip(BG[key], b[key])) for key in BG}
        c = pose_clip("stagger_" + k, 0.60, [(0, GUARD), (0.10, GUARD.moved((0.25, -0.35, 0.35))), (0.30, GUARD.moved((0.1, -0.15, 0.1))), (0.60, GUARD)],
                      [(0, OFF_G), (0.10, off((-1.35, 0.3, 0.1))), (0.60, OFF_G)],
                      [(0, BG), (0.10, hit), (0.30, lerp(hit, BG, 0.4)), (0.60, BG)], mask="full", fp=False, look=(0.5, 0.4, 0.3), **COMMON)
        feet = {}
        for side in ("Right", "Left"):
            s = steps.get(side, (0, 0, 0))
            feet[side] = [(0, (0, 0, 0), 0), (0.06, (s[0] * 0.4, s[1] * 0.4, 0.22 if abs(s[0]) + abs(s[1]) > 0.3 else 0), 0),
                          (0.16, s, 0), (0.42, s, 0), (0.52, (s[0] * 0.5, s[1] * 0.5, 0.12 if abs(s[0]) + abs(s[1]) > 0.3 else 0), 0),
                          (0.60, (0, 0, 0), 0)]
        out.append(stepping_feet(c, feet))
    for k, sgn in (("F", 1), ("B", -1)):
        b = body((-22 * sgn, -16 * sgn), (0, -0.45 * sgn, -0.30), (-18 * sgn, -20 * sgn, 6), (0, -12 * sgn))
        hit = {key: tuple(x + y for x, y in zip(BG[key], b[key])) for key in BG}
        c = pose_clip("heavy_stagger_" + k, 0.90,
                      [(0, GUARD), (0.12, HP((1.45, 0.10, 0.75), (0.25, -0.2, 0.95), (0, 1, 0), (1.0, -0.3, -0.2))), (0.45, GUARD.moved((0.2, -0.2, 0))), (0.90, GUARD)],
                      [(0, OFF_G), (0.12, off((-1.45, 0.2, 0.3))), (0.90, OFF_G)],
                      [(0, BG), (0.14, hit), (0.45, lerp(hit, BG, 0.45)), (0.90, BG)], mask="full", fp=False, look=(0.4, 0.3, 0.3), **COMMON)
        back = "Right" if sgn > 0 else "Left"
        other = "Left" if sgn > 0 else "Right"
        out.append(stepping_feet(c, {back: [(0, (0, 0, 0), 0), (0.08, (0, -0.4 * sgn, 0.3), 0), (0.20, (0.1, -1.05 * sgn, 0), -15),
                                            (0.60, (0.1, -1.05 * sgn, 0), -15), (0.75, (0, -0.5 * sgn, 0.25), 0), (0.88, (0, 0, 0), 0)],
                                     other: [(0, (0, 0, 0), 0), (0.25, (0, -0.25 * sgn, 0), 0), (0.65, (0, -0.25 * sgn, 0), 0), (0.88, (0, 0, 0), 0)]}))
    return out


def lerp(a, b, k):
    return {key: tuple(x + (y - x) * k for x, y in zip(a[key], b[key])) for key in a}


def knockdown():
    out = []
    down = body((0, -78), (0, -1.10, -2.20), (0, -6), (0, 30))
    c = pose_clip("knockdown", 1.00,
                  [(0, GUARD), (0.12, HP((1.40, 0.30, 0.60), (0.2, 0.2, 0.96), (0, 1, 0), (1, -0.3, -0.2))),
                   (0.45, HP((1.30, 0.20, -0.30), (0.4, 0.6, -0.7), (0, 0, 1), (1, -0.5, 0))), (1.0, HP((1.30, 0.20, -0.30), (0.4, 0.6, -0.7), (0, 0, 1), (1, -0.5, 0)))],
                  [(0, OFF_G), (0.12, off((-1.40, 0.3, 0.6))), (0.45, off((-1.30, 0.2, -0.3))), (1.0, off((-1.30, 0.2, -0.3)))],
                  [(0, BG), (0.15, body((0, -25), (0, -0.40, -0.40), (0, -14), (0, 12))), (0.42, body((0, -70), (0, -1.0, -2.0), (0, -8), (0, 28))),
                   (0.50, down), (1.0, down)], mask="full", fp=False, look=None, guardness=lambda t: 0.0, **COMMON)
    out.append(stepping_feet(c, {"Right": [(0, (0, 0, 0), 0), (0.15, (0, 0.10, 0.2), 0), (0.45, (0.05, 0.70, 0.25), 0), (1.0, (0.05, 0.70, 0.25), 0)],
                                 "Left": [(0, (0, 0, 0), 0), (0.15, (0, 0.30, 0.35), 0), (0.45, (-0.05, 0.85, 0.30), 0), (1.0, (-0.05, 0.85, 0.30), 0)]}))
    g = pose_clip("getup", 0.60,
                  [(0, HP((1.30, 0.20, -0.30), (0.4, 0.6, -0.7), (0, 0, 1), (1, -0.5, 0))), (0.25, HP((1.20, 0.60, -0.70), (0.1, 0.4, -0.9), (0, 1, 0), (1, -0.3, -0.5))), (0.60, GUARD)],
                  [(0, off((-1.30, 0.2, -0.3))), (0.20, off((-1.30, -0.3, -1.0))), (0.60, OFF_G)],
                  [(0, down), (0.20, body((0, -20), (0, -0.30, -1.30), (0, 30), (0, -10))), (0.40, body((0, 20), (0, 0.0, -0.60), (0, 15))), (0.60, BG)],
                  mask="full", fp=False, look=None, guardness=lambda t: max(0.0, (t - 0.4) / 0.2), **COMMON)
    out.append(stepping_feet(g, {"Right": [(0, (0.05, 0.70, 0.25), 0), (0.18, (0.1, 0.2, 0), 0), (0.60, (0, 0, 0), 0)],
                                 "Left": [(0, (-0.05, 0.85, 0.30), 0), (0.25, (-0.05, 0.4, 0.1), 0), (0.45, (0, 0, 0), 0), (0.60, (0, 0, 0), 0)]}))
    return out


def general_skills():
    out = []
    low = GUARD.moved((-0.10, -0.15, -0.35))
    out.append(pose_clip("skill_concentration", 0.50, [(0, GUARD), (0.20, low), (0.38, low), (0.50, GUARD)],
                         [(0, OFF_G), (0.20, off((-0.85, 0.7, -0.5))), (0.50, OFF_G)],
                         [(0, BG), (0.18, body((-10, 0), (0, 0, -0.04), (-8, -5), (0, 6))), (0.32, body((-10, 0), (0, 0, -0.06), (-8, -6), (0, 4))),
                          (0.50, BG)], **COMMON))
    out.append(pose_clip("skill_second_wind", 0.40, [(0, GUARD), (0.15, GUARD.moved((0, -0.1, -0.1))), (0.40, GUARD)],
                         [(0, OFF_G), (0.15, off((-0.30, 0.75, 0.30), (-0.9, -0.3, -0.3))), (0.28, off((-0.30, 0.72, 0.28), (-0.9, -0.3, -0.3))), (0.40, OFF_G)],
                         [(0, BG), (0.15, body((-10, -2), (0, 0, -0.03), (-8, -8), (0, -6))), (0.40, BG)], **COMMON))
    br = pose_clip("skill_brace", 0.40, [(0, GUARD), (0.20, GUARD.moved((-0.1, -0.05, -0.05))), (0.40, GUARD.moved((-0.1, -0.05, -0.05)))],
                   [(0, OFF_G), (0.20, off((-0.9, 0.8, -0.2))), (0.40, off((-0.9, 0.8, -0.2)))],
                   [(0, BG), (0.20, body((-10, 6), (0, 0, -0.40), (-8, 8))), (0.40, body((-10, 6), (0, 0, -0.38), (-8, 8)))],
                   mask="full", guardness=lambda t: 0.0, **COMMON)
    out.append(stepping_feet(br, {"Right": [(0, (0, 0, 0), 0), (0.08, (0.15, -0.1, 0.18), 0), (0.18, (0.30, -0.15, 0), 10), (0.40, (0.30, -0.15, 0), 10)],
                                  "Left": [(0, (0, 0, 0), 0), (0.12, (0, 0, 0), 0), (0.20, (-0.30, 0.15, 0.15), 0), (0.30, (-0.30, 0.20, 0), -10),
                                           (0.40, (-0.30, 0.20, 0), -10)]}))
    return out


def clips():
    return guard_set() + [kick()] + dodges() + reactions() + knockdown() + general_skills()


SHEET_VIEW = dict(azim=-55.0, elev=12.0, dist=19.0, target=(0.0, 0.6, 2.9))
SHEET = [("guard_in", 0.10, "guard (block)"), ("parry", 0.05, "PARRY meets"), ("parry", 0.12, "parry beats aside"),
         ("kick", 0.16, "KICK"), ("dodge_roll", 0.27, "dodge roll"), ("stagger_F", 0.16, "stagger, step back"),
         ("heavy_stagger_F", 0.20, "heavy stagger"), ("knockdown", 0.55, "knockdown")]
