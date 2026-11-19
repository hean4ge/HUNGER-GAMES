"""Throws (Combat_v3 1.2 throw, 7.2): knife flick, leaf dagger, ring (flat), hatchet, spear (javelin), twin axe (two
hands, spinning). The release is the hit sample (marker Release); the throw arm whips through from the hips, the off
arm points at the target and pulls in, the weight goes from the back foot to the front."""
from fight_lib import HP, Arc, Line
from fight_moves import attack, body, hold_clip, off, pose_clip, stepping_feet

FAMILY = "Throwing"
ITEMS = {"knife": ("throwing_knife", "RightHand"), "dagger": ("leaf_dagger_t3", "RightHand"), "ring": ("ring_blade_t3", "RightHand"),
         "hatchet": ("hatchet_t3", "RightHand"), "spear": ("spear_t3", "RightHand"), "twin": ("twin_axe_t3", "RightHand")}

HOLD = HP((0.95, 0.95, 0.00), (-0.05, 0.75, 0.66), (0.0, 0.66, -0.75), (0.6, -0.5, -1.0))
OFF_G = off((-1.00, 0.60, -0.50))
BG = body((-12, 2), (0, 0, -0.08), (-8, 4))
POINT = off((-1.10, 1.30, 0.55), (-0.8, -0.4, -0.4))  # the off arm points at the target
OFFS = {"guard": OFF_G, "w": POINT, "h": off((-1.00, 0.20, -0.45)), "f": off((-1.05, -0.20, -0.55))}

OVERARM = Arc((1.10, -0.55, 1.10), (0.75, 1.15, 0.85), (0.20, 1.10, -0.35), elbow=(0.9, -0.3, 0.3), elbow_hit=(0.6, -0.3, -0.6),
              blades=[(0, (0.05, -0.30, 0.95)), (1, (0.0, 0.85, 0.52)), ("e", (-0.30, 0.75, -0.58))])
FLICK = Arc((1.05, -0.20, 1.05), (0.80, 1.10, 0.75), (0.45, 1.05, 0.00), elbow=(0.9, -0.3, 0.2), elbow_hit=(0.7, -0.3, -0.5),
            blades=[(0, (0.05, -0.20, 0.97)), (1, (0.0, 0.80, 0.60)), ("e", (-0.20, 0.80, -0.55))])
FLAT = Arc((-0.45, 0.60, 0.35), (0.55, 1.35, 0.40), (1.40, 0.60, 0.40), elbow=(0.5, -0.5, -0.6),
           blades=[(0, (-0.85, -0.30, 0.10)), (1, (0.20, 0.97, 0.05)), ("e", (0.90, 0.20, 0.10))])
JAVELIN = Line((1.15, -0.75, 0.75), (0.75, 1.10, 1.05), (-0.10, 0.88, 0.46), (0, 0, 1), (0.9, -0.4, 0.1), (0.6, -0.4, -0.6),
               blade0=(-0.15, 0.95, 0.25))

B_OVER = {"guard": BG, "w": body((-30, -4), (0.08, -0.22, -0.15), (-30, -10, -6)), "h": body((14, 10), (-0.04, 0.22, -0.20), (24, 12, 3)),
          "f": body((22, 14), (-0.05, 0.28, -0.26), (34, 20, 3))}
B_FLAT = {"guard": BG, "w": body((26, 2), (-0.05, -0.05, -0.16), (36, 4, 3)), "h": body((-10, 6), (0.02, 0.18, -0.18), (-14, 8)),
          "f": body((-22, 6), (0.04, 0.18, -0.18), (-32, 8, -3))}
STEP = {"Left": [(0, (0, 0, 0), 0), (0.02, (0, 0.25, 0.20), 0), (0.08, (0, 0.65, 0), 0), (0.40, (0, 0.65, 0), 0), (0.50, (0, 0.3, 0.15), 0), (0.58, (0, 0, 0), 0)],
        "Right": [(0, (0, 0, 0), 0), (0.60, (0, 0, 0), 0)]}


def throw(name, L, H, path, item, bodies, step=None, kind="Throwable", **kw):
    c = attack(name, L, H, path, HOLD, bodies, offs=OFFS, item=item, kind=kind, family=FAMILY, markers={"Release": H}, **kw)
    if step:
        scale = H / 0.20
        st = {side: [(t * max(scale, 0.6), p, y) for t, p, y in ks] for side, ks in step.items()}
        stepping_feet(c, st)
        c.mask = "full"
    return c


def clips():
    out = [
        throw("throw_knife", 0.50, 0.10, FLICK, "knife", B_OVER, tw=0.05),
        throw("throw_dagger", 0.45, 0.08, FLICK, "dagger", B_OVER, tw=0.04),
        throw("throw_ring", 0.55, 0.14, FLAT, "ring", B_FLAT, tw=0.08),
        throw("throw_hatchet", 0.70, 0.20, OVERARM, "hatchet", B_OVER, step=STEP, tw=0.12),
        throw("throw_spear", 0.60, 0.22, JAVELIN, "spear", B_OVER, step=STEP, tw=0.14, over=0.0, kind="Spear"),
    ]
    tw = throw("throw_twinaxe", 0.90, 0.30, OVERARM, "twin", B_OVER, step=STEP, tw=0.18, tf=0.45)
    tw.left_on = (-0.60, (0, 0, 0))
    tw.left_on_w = lambda t: 1.0 if t < 0.27 else max(0.0, 1 - (t - 0.27) / 0.06)
    tw.fp_left = True
    out.append(tw)
    cocked = OVERARM(0.0)
    out.append(hold_clip("throw_wind", 0.4, cocked, POINT, B_OVER["w"], sway=(0, 0, 0.015), item="knife", kind="Throwable", family=FAMILY))
    out.append(pose_clip("equip_throwing", 0.32, [(0, HP((1.00, 0.30, -0.90), (0.0, 0.3, -0.95), (0, 1, 0), (0.6, -0.4, -1.0))), (0.32, HOLD)],
                         [(0, OFF_G), (0.32, OFF_G)], [(0, body((0, 0), (0, 0, -0.05), (0, 0))), (0.32, BG)],
                         guardness=lambda t: (t / 0.32) ** 2, item="knife", kind="Throwable", family=FAMILY))
    return out


SHEET_VIEW = dict(azim=65.0, elev=12.0, dist=19.0, target=(0.0, 0.8, 3.3))
SHEET = [("throw_knife", 0.0, "hold"), ("throw_knife", 0.05, "cock, point"), ("throw_knife", 0.10, "RELEASE knife"),
         ("throw_ring", 0.08, "ring: coil"), ("throw_ring", 0.14, "RELEASE ring (flat)"), ("throw_hatchet", 0.20, "RELEASE hatchet"),
         ("throw_spear", 0.14, "javelin: step"), ("throw_spear", 0.22, "RELEASE spear")]
