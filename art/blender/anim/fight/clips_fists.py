"""Fists (Combat_v3 1.4, 1.5, 2.2): jab (left), cross (right), hook (left), the haymaker heavy, the Head Kick skill.
Fist poses: `blade` = where the knuckles point, `edge` = the palm side (the thumb is -edge)."""
from fight_lib import HP, Arc, Line
from fight_moves import attack, body, chain, hold_clip, off, pose_clip, stepping_feet

FAMILY = "Fists"
ITEMS = {}
FISTS = dict(kind="Fists", family=FAMILY)

G_R = HP((0.62, 1.00, 0.42), (0.0, 0.45, 0.89), (0.0, 0.89, -0.45), (0.5, -0.4, -1.0))
G_L = HP((-0.62, 1.05, 0.48), (0.0, 0.45, 0.89), (0.0, 0.89, -0.45), (-0.5, -0.4, -1.0))
BG = body((-12, 2), (0, 0, -0.12), (-6, 6))
PUNCH = ((0.0, 1.0, 0.05), (0.0, 0.05, -1.0))  # knuckles forward, thumb up


def guard_offs(g, back=(0, -0.10, 0.05)):
    return {"guard": g, "w": g.moved((0, 0.05, 0.02)), "h": g.moved(back), "f": g.moved(back)}


JAB = Line((-0.62, 0.95, 0.42), (-0.45, 1.60, 0.52), PUNCH[0], PUNCH[1], (-0.5, -0.4, -1.0), (-0.6, -0.3, -0.6),
           blade0=(0.0, 0.45, 0.89), edge0=(0.0, 0.89, -0.45))
CROSS = Line((0.66, 0.90, 0.40), (0.42, 1.60, 0.52), PUNCH[0], PUNCH[1], (0.5, -0.4, -1.0), (0.7, -0.3, -0.5),
             blade0=(0.0, 0.45, 0.89), edge0=(0.0, 0.89, -0.45))
HOOK = Arc((-1.30, 0.55, 0.45), (-0.25, 1.35, 0.52), (0.35, 1.10, 0.45), elbow=(-1.0, -0.1, 0.1),
           blades=[(0, (0.55, 0.80, 0.0)), (1, (0.75, 0.65, 0.0)), ("e", (0.95, 0.10, 0.0))])
HAY = Arc((1.20, -0.15, 0.45), (0.20, 1.45, 0.55), (-0.45, 1.00, 0.30), elbow=(1.0, -0.1, 0.0), elbow_hit=(0.9, -0.2, 0.2),
          blades=[(0, (-0.3, 0.9, 0.2)), (1, (-0.65, 0.75, 0.05)), ("e", (-0.95, 0.1, 0.0))])
B_JAB = {"guard": BG, "w": body((-10, 2), (0, -0.03, -0.12), (-6, 4)), "h": body((-16, 4), (0, 0.10, -0.14), (-12, 8)),
         "f": body((-16, 4), (0, 0.10, -0.14), (-12, 8))}
B_CROSS = {"guard": BG, "w": body((-16, 2), (0, -0.04, -0.12), (-10, 4)), "h": body((14, 6), (0, 0.18, -0.16), (18, 10)),
           "f": body((16, 6), (0, 0.18, -0.16), (20, 10))}
B_HOOK = {"guard": BG, "w": body((8, 3), (0, 0.0, -0.14), (10, 6)), "h": body((-22, 5), (-0.03, 0.10, -0.16), (-26, 8, -4)),
          "f": body((-26, 5), (-0.04, 0.10, -0.16), (-32, 8, -4))}


def clips():
    out = chain([
        dict(name="fists_light_1", L=0.45, H=0.06, path=JAB, bodies=B_JAB, offs=guard_offs(G_R), hand="Left", guard=G_L, over=0.0, tw=0.02, **FISTS),
        dict(name="fists_light_2", L=0.45, H=0.06, path=CROSS, bodies=B_CROSS, offs=guard_offs(G_L, (0, -0.12, 0.0)), over=0.0, tw=0.02, **FISTS),
        dict(name="fists_light_3", L=0.52, H=0.08, path=HOOK, bodies=B_HOOK, offs=guard_offs(G_R), hand="Left", guard=G_L, tw=0.03, **FISTS),
    ], G_R, G_L)
    # first step's guards: jab steps take the right hand as the off hand
    cock = HP((1.15, -0.15, 0.45), (-0.3, 0.9, 0.2), (0, 0, -1), (1.0, -0.1, 0.0))
    b_cock = body((-22, 0), (0.05, -0.12, -0.18), (-26, 2))
    out.append(hold_clip("fists_heavy_charge", 0.5, cock, G_L, b_cock, sway=(0, 0, 0.02), **FISTS))
    out.append(attack("fists_heavy", 0.65, 0.12, HAY, G_R, {"guard": BG, "w": b_cock, "h": body((18, 6), (-0.03, 0.22, -0.18), (24, 10, 3)),
                                                              "f": body((26, 6), (-0.04, 0.22, -0.18), (34, 10, 3))},
                      offs={"guard": G_L, "w": G_L, "h": G_L.moved((-0.2, -0.2, -0.1)), "f": G_L.moved((-0.25, -0.25, -0.15))},
                      start=cock, start_body=b_cock, tw=0.04, **FISTS))
    hk = pose_clip("fists_skill_head_kick", 0.70, [(0, G_R), (0.22, G_R.moved((0.2, -0.3, 0.1))), (0.70, G_R)],
                   [(0, G_L), (0.22, G_L.moved((-0.5, -0.2, -0.3))), (0.70, G_L)],
                   [(0, BG), (0.12, body((30, -6, -8), (0.1, -0.05, -0.15), (10, -4, -6))), (0.22, body((70, -12, -22), (0.25, -0.10, -0.10), (15, -8, -10))),
                    (0.36, body((60, -8, -14), (0.15, -0.05, -0.15), (12, -4, -6))), (0.70, BG)],
                   hit=0.22, mask="full", look=(0.85, 0.6, 0.6), **FISTS)
    out.append(stepping_feet(hk, {"Right": [(0, (0, 0, 0), 0), (0.10, (0.15, 0.35, 1.00), 30), (0.22, (-0.55, 1.25, 2.70), 70),
                                            (0.34, (-0.25, 0.80, 1.50), 50), (0.50, (0.10, 0.20, 0.40), 20), (0.66, (0, 0, 0), 0)],
                                  "Left": [(0, (0, 0, 0), 0), (0.12, (0, 0, 0), 45), (0.40, (0, 0, 0), 45), (0.66, (0, 0, 0), 0)]}))
    out.append(pose_clip("equip_fists", 0.32, [(0, G_R.moved((0.35, -0.4, -1.0))), (0.20, G_R.moved((0, 0, -0.05))), (0.32, G_R)],
                         [(0, G_L.moved((-0.35, -0.4, -1.0))), (0.24, G_L.moved((0, 0, -0.05))), (0.32, G_L)],
                         [(0, body((0, 0), (0, 0, -0.05), (0, 0))), (0.32, BG)], guardness=lambda t: (t / 0.32) ** 2, **FISTS))
    return out


SHEET_VIEW = dict(azim=-40.0, elev=12.0, dist=18.0, target=(0.0, 0.6, 3.2))
SHEET = [("fists_light_1", 0.0, "guard"), ("fists_light_1", 0.06, "JAB"), ("fists_light_2", 0.03, "cross: hips turn"),
         ("fists_light_2", 0.06, "CROSS"), ("fists_light_3", 0.08, "HOOK"), ("fists_heavy_charge", 0.0, "haymaker charge"),
         ("fists_heavy", 0.12, "HAYMAKER"), ("fists_skill_head_kick", 0.22, "HEAD KICK")]
