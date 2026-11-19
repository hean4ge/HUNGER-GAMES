"""Spear (Combat_v3 1.4, 1.5, 2.2): two thrusts and a butt swing, the lunge heavy, the counter, the Vault Kick. Two
hands on the shaft throughout: the right hand at the back, the left forward toward the head; the thrust drives from the
back foot through the hips, the shaft slides forward through the left hand."""
import fight_lib as fl
from fight_lib import HP, Arc, Line
from fight_moves import attack, body, chain, hold_clip, off, pose_clip, stepping_feet

FAMILY = "Spear"
ITEMS = {"spear": ("spear_t3", "RightHand")}
SPEAR = dict(item="spear", kind="Spear", family=FAMILY, fp_left=True)

GUARD = HP((0.85, 0.20, -0.30), (-0.25, 0.95, 0.15), (0.0, 0.0, 1.0), (0.7, -0.6, -0.6))
BG = body((-22, 2), (0.04, 0, -0.14), (-14, 5))
OFF_G = off((-0.75, 1.10, -0.10))

THRUST = Line((0.95, -0.20, -0.25), (0.45, 1.20, 0.10), (-0.18, 0.98, 0.08), (0, 0, 1), (0.8, -0.6, -0.4), (0.5, -0.5, -0.8),
              blade0=(-0.25, 0.95, 0.18))
THRUST_HI = Line((0.95, -0.15, 0.05), (0.40, 1.20, 0.45), (-0.15, 0.97, 0.20), (0, 0, 1), (0.8, -0.6, -0.4), (0.5, -0.5, -0.7),
                 blade0=(-0.25, 0.94, 0.25))
BUTT = Arc((0.90, 0.70, -0.20), (0.25, 1.30, 0.40), (-0.35, 0.95, 0.75), elbow=(0.6, -0.5, -0.6),
           blades=[(0, (-0.20, 0.97, 0.10)), (1, (0.75, -0.55, -0.35)), ("e", (0.85, -0.35, -0.40))])
B_THRUST = {"guard": BG, "w": body((-28, 0), (0.06, -0.18, -0.18), (-18, 2)), "h": body((-6, 10), (0.0, 0.32, -0.26), (-2, 10)),
            "f": body((-6, 10), (0.0, 0.34, -0.26), (-2, 10))}
B_BUTT = {"guard": BG, "w": body((-26, 2), (0.05, -0.05, -0.16), (-22, 4)), "h": body((14, 6), (-0.04, 0.18, -0.20), (26, 8, 3)),
          "f": body((18, 6), (-0.04, 0.18, -0.20), (32, 8, 3))}


def grip(c, along=1.05, extra=(-0.10, 0.0, 0.0)):
    c.left_on = (along, extra)
    return c


def clips():
    out = [grip(c) for c in chain([
        dict(name="spear_light_1", L=0.70, H=0.20, path=THRUST, bodies=B_THRUST, over=0.0, tf=0.30, **SPEAR),
        dict(name="spear_light_2", L=0.70, H=0.20, path=THRUST_HI, bodies=B_THRUST, over=0.0, tf=0.30, **SPEAR),
        dict(name="spear_light_3", L=0.70, H=0.16, path=BUTT, bodies=B_BUTT, tf=0.30, **SPEAR),
    ], GUARD, OFF_G)]
    back = HP((1.05, -0.65, -0.15), (-0.22, 0.96, 0.15), (0, 0, 1), (0.9, -0.5, -0.2))
    b_back = body((-34, 0), (0.08, -0.30, -0.24), (-20, 0))
    out.append(grip(hold_clip("spear_heavy_charge", 0.5, back, None, b_back, sway=(0, 0.02, 0), **SPEAR)))
    h = attack("spear_heavy", 0.79, 0.16, Line((1.05, -0.65, -0.15), (0.45, 1.30, 0.12), (-0.18, 0.98, 0.06), (0, 0, 1), (0.9, -0.5, -0.2),
                                              (0.5, -0.5, -0.8), blade0=(-0.22, 0.96, 0.15)),
               GUARD, {"guard": BG, "w": b_back, "h": body((-4, 14), (0, 0.65, -0.45), (0, 12)), "f": body((-4, 14), (0, 0.68, -0.46), (0, 12))},
               start=back, start_body=b_back, tw=0.04, over=0.0, tf=0.30, mask="full", **SPEAR)
    out.append(stepping_feet(grip(h), {"Left": [(0, (0, 0, 0), 0), (0.05, (0, 0.45, 0.25), 0), (0.15, (0, 1.20, 0), 0), (0.48, (0, 1.20, 0), 0),
                                                (0.62, (0, 0.6, 0.22), 0), (0.77, (0, 0, 0), 0)], "Right": [(0, (0, 0, 0), 0), (0.79, (0, 0, 0), 0)]}))
    out.append(grip(attack("spear_counter", 0.47, 0.06, THRUST, GUARD, B_THRUST, tw=0.02, over=0.0, **SPEAR)))
    out.append(vault_kick())
    out.append(grip(pose_clip("equip_spear", 0.32, [(0, HP((1.00, 0.0, -0.60), (0.0, 0.3, 0.95), (0, 0, 1), (0.7, -0.6, -0.6))),
                                                    (0.18, GUARD.moved((0, 0, 0.15))), (0.32, GUARD)],
                              None, [(0, body((0, 0), (0, 0, -0.05), (0, 0))), (0.32, BG)], guardness=lambda t: (t / 0.32) ** 2, **SPEAR)))
    return out


def vault_kick():
    """Plant the spear ahead (0.3 s), vault up on it and kick with both feet (lands 0.75 s after the press), land."""
    L = 1.25
    plant = HP((0.55, 1.10, 0.45), (0.05, 0.45, -0.89), (0, 1, 0), (0.6, -0.5, -0.6))
    hold_up = HP((0.40, 0.70, -0.10), (0.05, 0.20, -0.98), (0, 1, 0), (0.6, -0.4, -0.8))
    c = pose_clip("spear_skill_vault_kick", L, [(0, GUARD), (0.25, plant), (0.30, plant), (0.55, hold_up), (0.80, hold_up), (1.05, GUARD.moved((0, 0.1, 0.1))), (L, GUARD)],
                  None, [(0, BG), (0.25, body((-10, 10), (0, 0.15, -0.30), (-6, 10))), (0.45, body((0, -18), (0, 0.10, 0.40), (0, -6), (0, 10))),
                         (0.75, body((0, -40), (0, 0.0, 0.70), (0, -10), (0, 20))), (0.95, body((0, 6), (0, 0.10, -0.40), (0, 8))), (L, BG)],
                  hit=0.75, mask="full", look=(0.6, 0.5, 0.5), **SPEAR)
    c.left_on = (0.55, (-0.12, 0, 0))
    return stepping_feet(c, {"Right": [(0, (0, 0, 0), 0), (0.30, (0, 0, 0), 0), (0.50, (0, 0.30, 1.40), 0), (0.75, (0, 1.40, 2.10), 0),
                                       (0.90, (0, 0.30, 0.60), 0), (1.00, (0, 0, 0), 0)],
                             "Left": [(0, (0, 0, 0), 0), (0.32, (0, 0, 0), 0), (0.52, (0, 0.20, 1.30), 0), (0.75, (0, 1.30, 2.00), 0),
                                      (0.92, (0, 0.40, 0.50), 0), (1.02, (0, 0, 0), 0)]})


SHEET_VIEW = dict(azim=-55.0, elev=12.0, dist=20.0, target=(0.0, 0.9, 3.2))
SHEET = [("spear_light_1", 0.0, "guard"), ("spear_light_1", 0.11, "draw back"), ("spear_light_1", 0.20, "THRUST"),
         ("spear_light_3", 0.16, "BUTT SWING"), ("spear_heavy", 0.16, "LUNGE"), ("spear_skill_vault_kick", 0.30, "vault: plant"),
         ("spear_skill_vault_kick", 0.75, "VAULT KICK"), ("spear_skill_vault_kick", 1.0, "land")]
