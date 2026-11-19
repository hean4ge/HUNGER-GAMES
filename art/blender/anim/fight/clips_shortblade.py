"""Short blades (Combat_v3 1.4, 1.5, 2.2): Hunting Knife, Leaf Dagger, Ring Blade; the lunging stab heavy, the counter,
Chained Strikes (five quick strikes that grow), the dagger's ring flourish. Short, tight arcs close to the body; the
knife leads with the hips and the off hand guards the face."""
from fight_lib import HP, Arc, Line, key_hand
from fight_moves import attack, body, chain, hold_clip, off, pose_clip, stepping_feet

FAMILY = "ShortBlade"
ITEMS = {"knife": ("knife_t3", "RightHand"), "dagger": ("leaf_dagger_t3", "RightHand"), "ring": ("ring_blade_t3", "RightHand")}

GUARD = HP((0.85, 1.05, 0.05), (-0.15, 0.80, 0.58), (0.0, 0.58, -0.80), (0.6, -0.5, -1.0))
OFF_G = off((-0.75, 1.00, 0.30), (-0.7, -0.4, -0.8))
BG = body((-14, 3), (0, 0, -0.14), (-8, 6))
OFFS = {"guard": OFF_G, "w": off((-0.65, 1.15, 0.35), (-0.7, -0.4, -0.8)), "h": off((-1.05, 0.35, -0.25)), "f": off((-1.10, 0.25, -0.30))}

SL_RL = Arc((1.30, 0.60, 0.75), (0.30, 1.40, 0.40), (-0.35, 0.95, 0.05), elbow=(0.6, -0.4, -0.7),
            blades=[(0, (0.55, 0.35, 0.76)), (1, (-0.25, 0.95, 0.10)), ("e", (-0.80, 0.50, -0.30))])
SL_LR = Arc((-0.30, 1.00, 0.10), (0.55, 1.40, 0.35), (1.35, 0.55, 0.55), elbow=(0.5, -0.4, -0.8),
            blades=[(0, (-0.75, 0.45, -0.20)), (1, (0.20, 0.97, 0.10)), ("e", (0.80, 0.40, 0.40))])
STAB = Line((0.95, 0.45, 0.10), (0.40, 1.58, 0.62), (-0.10, 0.95, 0.30), (0.0, 0.0, -1.0), (0.7, -0.4, -0.6), (0.4, -0.5, -0.8),
            blade0=(-0.10, 0.90, 0.40))
HOOK_STAB = Arc((1.35, 0.50, 0.95), (0.35, 1.45, 0.45), (0.05, 1.05, -0.05), elbow=(0.9, -0.2, 0.2), elbow_hit=(0.5, -0.4, -0.8),
                blades=[(0, (-0.10, 0.60, 0.80)), (1, (-0.30, 0.85, -0.45)), ("e", (-0.30, 0.55, -0.78))])
RING_RL = Arc((1.30, 0.55, 0.50), (0.25, 1.35, 0.35), (-0.40, 0.90, 0.20), elbow=(0.5, -0.4, -0.8),
              blades=[(0, (0.65, 0.20, 0.73)), (1, (-0.20, 0.90, 0.40)), ("e", (-0.85, 0.40, 0.35))])
RING_LR = Arc((-0.35, 0.95, 0.20), (0.55, 1.35, 0.35), (1.35, 0.50, 0.45), elbow=(0.5, -0.4, -0.8),
              blades=[(0, (-0.80, 0.40, 0.45)), (1, (0.20, 0.90, 0.40)), ("e", (0.85, 0.25, 0.45))])
PUNCHY = Line((0.90, 0.60, 0.25), (0.40, 1.60, 0.40), (-0.05, 0.75, 0.66), (0.0, 0.66, -0.75), (0.6, -0.5, -0.7), (0.4, -0.4, -0.8))

B_RL = {"guard": BG, "w": body((-18, 2), (0.04, -0.06, -0.14), (-22, 2)), "h": body((8, 6), (-0.02, 0.15, -0.18), (14, 10)),
        "f": body((14, 6), (-0.02, 0.15, -0.18), (24, 10))}
B_LR = {"guard": BG, "w": body((12, 4), (-0.03, 0.02, -0.16), (20, 6)), "h": body((-10, 5), (0.02, 0.14, -0.18), (-12, 8)),
        "f": body((-16, 5), (0.03, 0.12, -0.17), (-24, 8))}
B_STAB = {"guard": BG, "w": body((-14, 2), (0.0, -0.08, -0.14), (-14, 2)), "h": body((10, 10), (0, 0.30, -0.22), (8, 12)),
          "f": body((10, 10), (0, 0.30, -0.22), (8, 12))}

KNIFE = dict(item="knife", kind="Blade", family=FAMILY)
DAGGER = dict(item="dagger", kind="Blade", family=FAMILY)
RING = dict(item="ring", kind="Blade", family=FAMILY)


def chains():
    out = []
    out += chain([
        dict(name="knife_light_1", L=0.48, H=0.10, path=SL_RL, bodies=B_RL, offs=OFFS, **KNIFE),
        dict(name="knife_light_2", L=0.48, H=0.10, path=SL_LR, bodies=B_LR, offs=OFFS, **KNIFE),
        dict(name="knife_light_3", L=0.52, H=0.12, path=STAB, bodies=B_STAB, offs=OFFS, over=0.0, **KNIFE),
    ], GUARD, OFF_G)
    out += chain([
        dict(name="dagger_light_1", L=0.42, H=0.08, path=STAB, bodies=B_STAB, offs=OFFS, over=0.0, **DAGGER),
        dict(name="dagger_light_2", L=0.42, H=0.08, path=SL_LR, bodies=B_LR, offs=OFFS, **DAGGER),
        dict(name="dagger_light_3", L=0.46, H=0.10, path=HOOK_STAB, bodies=B_RL, offs=OFFS, **DAGGER),
    ], GUARD, OFF_G)
    out += chain([
        dict(name="ring_light_1", L=0.55, H=0.12, path=RING_RL, bodies=B_RL, offs=OFFS, **RING),
        dict(name="ring_light_2", L=0.55, H=0.12, path=RING_LR, bodies=B_LR, offs=OFFS, **RING),
        dict(name="ring_light_3", L=0.60, H=0.14, path=PUNCHY, bodies=B_STAB, offs=OFFS, over=0.0, **RING),
    ], GUARD, OFF_G)
    return out


def specials():
    out = []
    low = HP((1.00, 0.15, -0.40), (-0.10, 0.95, 0.30), (0, 0, -1), (0.8, -0.5, -0.4))
    b_low = body((-22, 6), (0.05, -0.15, -0.30), (-18, 8))
    out.append(hold_clip("shortblade_heavy_charge", 0.5, low, OFF_G, b_low, sway=(0, 0, 0.015), **KNIFE))
    h = attack("shortblade_heavy", 0.65, 0.12, Line((1.00, 0.15, -0.30), (0.35, 1.62, 0.62), (-0.10, 0.95, 0.30), (0, 0, -1),
                                                     (0.8, -0.5, -0.4), (0.4, -0.5, -0.8), blade0=(-0.10, 0.95, 0.30)),
               GUARD, {"guard": BG, "w": b_low, "h": body((12, 14), (0, 0.55, -0.40), (8, 12)), "f": body((12, 14), (0, 0.58, -0.42), (8, 12))},
               offs=OFFS, start=low, start_body=b_low, tw=0.04, over=0.0, mask="full", **KNIFE)
    out.append(stepping_feet(h, {"Left": [(0, (0, 0, 0), 0), (0.05, (0, 0.40, 0.22), 0), (0.12, (0, 1.00, 0), 0), (0.40, (0, 1.00, 0), 0),
                                          (0.52, (0, 0.5, 0.2), 0), (0.63, (0, 0, 0), 0)],
                                 "Right": [(0, (0, 0, 0), 0), (0.65, (0, 0, 0), 0)]}))
    out.append(attack("shortblade_counter", 0.47, 0.06, STAB, GUARD, B_STAB, offs=OFFS, tw=0.02, over=0.0, **KNIFE))
    # Chained Strikes: five quick strikes 0.2 s apart, alternating sides, each a little bigger, the last a stab
    hits = [0.06, 0.26, 0.46, 0.66, 0.86]
    poses = [GUARD]
    keys = [(0.0, GUARD)]
    bk = [(0.0, BG)]
    for i, t in enumerate(hits):
        grow = 1 + 0.12 * i
        if i == 4:
            p = HP((0.40, 1.65, 0.35), (-0.10, 1.0, 0.0), (0, 0, -1), (0.4, -0.5, -0.8))
            pre = HP((0.95, 0.55, 0.15), (-0.10, 0.90, 0.40), (0, 0, -1), (0.7, -0.4, -0.6))
        elif i % 2 == 0:
            p = HP((0.30 - 0.1 * i, 1.40, 0.40), (-0.25, 0.95, 0.10), (-1, 0, 0), (0.6, -0.4, -0.7))
            pre = HP((1.25 + 0.05 * i, 0.70, 0.70), (0.55, 0.35, 0.76), (-1, 0, 0), (0.6, -0.4, -0.7))
        else:
            p = HP((0.70 + 0.05 * i, 1.40, 0.35), (0.20, 0.97, 0.10), (1, 0, 0), (0.5, -0.4, -0.8))
            pre = HP((-0.20, 1.00, 0.15), (-0.75, 0.45, -0.20), (1, 0, 0), (0.5, -0.4, -0.8))
        keys.append((t - 0.05, pre))
        keys.append((t, p))
        yaw = (14 if i % 2 == 0 else -12) * grow
        bk.append((t - 0.05, body((-yaw * 0.8, 3), (0, -0.02 + 0.05 * i, -0.15), (-yaw, 4))))
        bk.append((t, body((yaw * 0.6, 6), (0, 0.10 + 0.08 * i, -0.18), (yaw, 8 + i))))
    keys.append((1.20, GUARD))
    bk.append((1.20, BG))
    ch = pose_clip("shortblade_skill_chained", 1.20, keys, [(0, OFF_G), (0.5, OFFS["h"]), (1.2, OFF_G)], bk, hit=0.06,
                   markers={"Hit2": 0.26, "Hit3": 0.46, "Hit4": 0.66, "Hit5": 0.86}, **KNIFE)
    out.append(ch)
    # the Leaf Dagger's idle flourish: a finger through the ring, one turn in the hand
    fl_keys = [(0.0, GUARD)]
    import math
    for k in range(1, 9):
        a = 2 * math.pi * k / 8
        t = 0.2 + 0.8 * k / 8
        blade = (-0.15 * math.cos(a), 0.80 * math.cos(a), 0.58 * math.cos(a) + 0.0)
        bl = (math.sin(a) * 0.9 - 0.15 * math.cos(a), 0.8 * math.cos(a), 0.58 * math.cos(a))
        fl_keys.append((t, HP((0.85, 1.10, 0.15), bl, (0, 0.58, -0.8), (0.6, -0.5, -1.0))))
    fl_keys.append((1.2, GUARD))
    out.append(pose_clip("dagger_flourish", 1.2, fl_keys, [(0, OFF_G), (1.2, OFF_G)], [(0, BG), (0.6, body((-12, 2), (0, 0, -0.13), (-6, 4), (0, 10))), (1.2, BG)],
                         **DAGGER))
    out.append(pose_clip("equip_shortblade", 0.32, [(0, HP((0.95, 0.35, -0.95), (0.0, 0.2, -0.98), (0, 1, 0), (0.6, -0.4, -1.0))),
                                                    (0.16, GUARD.moved((0.1, -0.1, -0.15))), (0.32, GUARD)],
                         [(0, off((-0.95, 0.45, -0.75))), (0.32, OFF_G)], [(0, body((0, 0), (0, 0, -0.05), (0, 0))), (0.32, BG)],
                         guardness=lambda t: (t / 0.32) ** 2, **KNIFE))
    return out


def clips():
    return chains() + specials()


SHEET_VIEW = dict(azim=70.0, elev=12.0, dist=18.0, target=(0.0, 0.6, 3.2))
SHEET = [("knife_light_1", 0.0, "guard"), ("knife_light_1", 0.05, "wind-up"), ("knife_light_1", 0.10, "HIT 1 slash"),
         ("knife_light_2", 0.10, "HIT 2 slash back"), ("knife_light_3", 0.12, "HIT 3 stab"), ("shortblade_heavy", 0.12, "LUNGING STAB"),
         ("shortblade_skill_chained", 0.66, "CHAINED 4"), ("ring_light_1", 0.12, "RING BLADE slash")]
