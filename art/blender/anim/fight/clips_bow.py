"""Bow (Combat_v3 7.2, the owner's list): nock, draw, hold (loop), release, the let-down for a dodge, equip. The bow is
in the LEFT hand (InventoryService welds it there). Side-on: the hips and chest turn right so the left shoulder points
at the target, the bow arm straight out, the string hand drawn to the jaw with the elbow high and back. The draw's
length is the bow's draw time (Recurve 0.9 s; ClipPlayer fits `total` to the Short Bow's 0.6)."""
from fight_lib import HP
from fight_moves import body, hold_clip, pose_clip

FAMILY = "Bow"
ITEMS = {"bow": ("bow_t3", "LeftHand")}
BOW = dict(off_item="bow", kind="Bow", family=FAMILY, fp_left=True)

# low ready: the bow low in front, the string hand on the nock
READY_L = HP((-0.85, 1.00, -0.35), (0.25, 0.30, 0.92), (0.0, 1.0, 0.0), (-0.5, -0.6, -0.8))
READY_R = HP((-0.20, 1.05, -0.30), (0, 0.3, -0.95), (0, 0, 1), (0.6, -0.5, -0.7))
B_READY = body((-14, 4), (0, 0, -0.08), (-10, 6))
# drawn: side-on; target forward in the world = chest space (-0.97, 0.26, 0) when the trunk turns 75 degrees right
AIM = (-0.97, 0.26, 0.04)
DRAWN_L = HP((-2.55, 0.45, 0.62), (0.12, 0.05, 0.99), AIM, (-0.2, -0.4, -1.0))
NOCK_R = HP((-2.15, 0.50, 0.60), (-0.97, 0.26, 0.0), (0, 0, 1), (0.8, -0.3, -0.4))
ANCHOR_R = HP((-0.68, 0.42, 0.78), (-0.97, 0.26, 0.0), (0, 0, 1), (0.9, -0.3, 0.45))
B_DRAWN = body((-40, 0), (0.05, -0.04, -0.10), (-35, 2, -3))


def clips():
    out = []
    out.append(pose_clip("bow_nock", 0.30, [(0, READY_R), (0.15, READY_R.moved((0.05, -0.15, 0.10))), (0.30, READY_R)],
                         [(0, READY_L), (0.30, READY_L.moved((0, 0.05, 0.05)))], [(0, B_READY), (0.30, B_READY)], **BOW))
    out.append(pose_clip("bow_draw", 0.90, [(0, READY_R), (0.18, NOCK_R), (0.55, NOCK_R.moved((1.0, -0.15, 0.30))), (0.90, ANCHOR_R)],
                         [(0, READY_L), (0.25, DRAWN_L.moved((0.5, 0.0, -0.3))), (0.55, DRAWN_L), (0.90, DRAWN_L)],
                         [(0, B_READY), (0.30, body((-30, 0), (0.03, -0.02, -0.10), (-26, 2, -2))), (0.70, B_DRAWN), (0.90, B_DRAWN)],
                         guardness=lambda t: max(0.0, 1 - t / 0.2), **BOW))
    out.append(hold_clip("bow_hold", 1.0, ANCHOR_R, DRAWN_L, B_DRAWN, breathe=0.008, **BOW))
    loose = HP((0.10, -0.15, 0.80), (-0.80, 0.30, 0.50), (0, 0, 1), (0.9, -0.3, 0.45))
    out.append(pose_clip("bow_release", 0.32, [(0, ANCHOR_R), (0.04, loose), (0.14, loose.moved((0.05, 0, -0.05))), (0.32, READY_R)],
                         [(0, DRAWN_L), (0.06, DRAWN_L.moved((0.0, 0.05, -0.10))), (0.16, DRAWN_L.moved((0.2, 0.0, -0.25))), (0.32, READY_L)],
                         [(0, B_DRAWN), (0.08, B_DRAWN), (0.32, B_READY)], hit=0.033, markers={"Release": 0.0},
                         guardness=lambda t: max(0.0, (t - 0.14) / 0.18), **BOW))
    out.append(pose_clip("bow_dodge_letdown", 0.25, [(0, ANCHOR_R), (0.12, NOCK_R.moved((0.6, 0, -0.1))), (0.25, READY_R)],
                         [(0, DRAWN_L), (0.25, READY_L)], [(0, B_DRAWN), (0.25, B_READY)], guardness=lambda t: t / 0.25, **BOW))
    out.append(pose_clip("equip_bow", 0.32, [(0, READY_R.moved((0.6, -0.4, -0.6))), (0.32, READY_R)],
                         [(0, HP((-1.0, -0.3, 0.9), (0.2, -0.3, 0.93), (0, 1, 0), (-0.8, -0.3, -0.4))), (0.18, READY_L.moved((0, 0, 0.25))), (0.32, READY_L)],
                         [(0, body((0, 0), (0, 0, -0.05), (0, 0))), (0.32, B_READY)], guardness=lambda t: (t / 0.32) ** 2, **BOW))
    return out


SHEET_VIEW = dict(azim=-70.0, elev=12.0, dist=19.0, target=(-0.5, 0.6, 3.4))
SHEET = [("bow_nock", 0.0, "low ready"), ("bow_nock", 0.15, "nock"), ("bow_draw", 0.25, "raise, turn side-on"), ("bow_draw", 0.55, "draw"),
         ("bow_draw", 0.90, "anchor"), ("bow_release", 0.04, "RELEASE"), ("bow_release", 0.14, "follow-through"), ("bow_release", 0.32, "back to ready")]
