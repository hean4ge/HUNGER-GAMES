"""
fight_moves.py - move templates for the Combat v3 clips (fight_lib does the curves, the bake and the encoding).

  attack(...)   one strike: anticipation onto the wind-up, a cut that accelerates through the hit, an overshooting
                follow-through that settles, the recovery to the guard. Body, striking hand and off hand share one
                timeline; the hips lead the chest; the head keeps the target.
  chain(...)    light chains: every step after the first starts from the previous step's follow-through.
  mirror_*      the same move for the other hand (paired blades, left jab).
"""
from mathutils import Vector

import fight_lib as fl
from fight_lib import HP, Clip, body_track, key_hand, strike_hand

OFF_FREE = (0, 0.3, -1), (0, 1, 0)  # a free hand's blade / edge (unused: it follows its forearm)


def off(wrist, elbow=(-0.6, -1.0, -0.4)):
    return HP(wrist, OFF_FREE[0], OFF_FREE[1], elbow)


def body(pelvis=(0, 0, 0), move=(0, 0, 0), chest=(0, 0, 0), head=(0, 0, 0)):
    return {"pelvis": tuple(pelvis) + (0,) * (3 - len(pelvis)), "move": tuple(move),
            "chest": tuple(chest) + (0,) * (3 - len(chest)), "head": tuple(head) + (0,) * (3 - len(head))}


def mirror_v(v):
    return Vector((-v[0], v[1], v[2]))


def mirror_hp(p):
    return HP(mirror_v(p.wrist), mirror_v(p.blade), mirror_v(p.edge), mirror_v(p.elbow))


def mirror_body(b):
    return {"pelvis": (-b["pelvis"][0], b["pelvis"][1], -b["pelvis"][2]),
            "move": (-b["move"][0], b["move"][1], b["move"][2]),
            "chest": (-b["chest"][0], b["chest"][1], -b["chest"][2]),
            "head": (-b["head"][0], b["head"][1], -b["head"][2])}


def lerp_body(a, b, k):
    return {key: tuple(x + (y - x) * k for x, y in zip(a[key], b[key])) for key in a}


class Mirrored:
    def __init__(self, path):
        self.path = path
        self.se = getattr(path, "se", 1.25)

    def __call__(self, s):
        return mirror_hp(self.path(s))


def attack(name, L, H, path, guard, bodies, offs=None, start=None, start_body=None, start_off=None, tw=None, tf=None,
           settle=0.06, over=0.06, hold=0.0, back=None, lead=0.025, look=(0.9, 0.7, 0.6), hand="Right", extra_body=(),
           pre=None, accel=0.2, **clip_kw):
    """bodies: {guard, w, h, f[, s]} body dicts; offs: {guard, w, h, f} off-hand poses (or None). hand = the striking
    hand ("Left": the path and poses are for the left hand already)."""
    c = Clip(name, L, H, **clip_kw)
    tw = tw if tw is not None else max(H * 0.55, 1.0 / fl.FPS)
    tf = tf if tf is not None else H + min(0.13, (L - H) * 0.32)
    tf = min(tf, L - 0.12)
    settle = min(settle, max(L - tf - 0.1, 0.02))
    f, g = strike_hand(path, guard, tw, H, tf, L, start=start, settle=settle, over=over, hold=hold, back=back, pre=pre,
                       accel=accel)
    c.timing = (tw, H, tf, settle)
    c.guardness = g
    bg = bodies["guard"]
    keys = [(0.0, start_body or bg), (tw, bodies["w"]), (H, bodies["h"]), (tf, bodies["f"]),
            (tf + settle, bodies.get("s", lerp_body(bodies["f"], bg, 0.12))), (L, bg)]
    keys += list(extra_body)
    if hold > 0:
        keys.append((tw + hold, bodies["w"]))
    c.body = body_track(keys, lead=lead, look=look)
    if offs:
        og = offs["guard"]
        ok = [(0.0, start_off or og), (tw, offs["w"]), (H, offs["h"]), (tf, offs["f"]), (L, og)]
        if hold > 0:
            ok.append((tw + hold, offs["w"]))
        of = key_hand(sorted(ok, key=lambda k: k[0]))
    else:
        of = None
    if hand == "Right":
        c.right, c.left = f, of
    else:
        c.left, c.right = f, of
    c.end_t = tf + settle
    c.hand_side = hand
    c.strike_hand = f
    c.off_hand = of
    return c


def chain(steps, guard, offs_guard):
    """steps: list of dicts of attack() arguments (without start*); each step after the first starts from the previous
    step's follow-through (hand, off hand and body)."""
    out = []
    prev = None
    for st in steps:
        kw = dict(st)
        if prev is not None and kw.pop("from_prev", True):
            t = prev.end_t
            same = kw.get("hand", "Right") == prev.hand_side
            mine = prev.strike_hand if same else prev.off_hand
            other = prev.off_hand if same else prev.strike_hand
            if mine is not None:
                kw.setdefault("start", mine(t))
            if other is not None and kw.get("offs"):
                kw.setdefault("start_off", other(t))
            kw.setdefault("start_body", prev.body.raw(t))
        kw.pop("from_prev", None)
        c = attack(guard=kw.pop("guard", guard), **kw)
        out.append(c)
        prev = c
    return out


def hold_clip(name, L, right, left, b, loop=True, breathe=0.02, sway=(0, 0, 0), **kw):
    """A held pose (charge, guard hold): a slow breath and a small sway; loops cleanly."""
    c = Clip(name, L, None, loop=loop, **kw)
    import math

    def rf(t):
        k = math.sin(2 * math.pi * t / L)
        return right.moved((sway[0] * k, sway[1] * k, sway[2] * k + breathe * k))

    def lf(t):
        if left is None:
            return None
        k = math.sin(2 * math.pi * t / L)
        return left.moved((0, 0, breathe * 0.6 * k))
    bk = []
    for i in range(5):
        t = L * i / 4
        k = math.sin(2 * math.pi * t / L)
        bb = dict(b)
        bb["chest"] = (b["chest"][0], b["chest"][1] + 1.2 * k, b["chest"][2])
        bk.append((t, bb))
    c.body = body_track(bk, lead=0.0)
    c.right = rf
    c.left = lf if left is not None else None
    c.guardness = lambda t: 0.0
    c.end_t = 0.0
    return c


def pose_clip(name, L, keys_right, keys_left, keys_body, lead=0.02, look=(0.9, 0.7, 0.6), guardness=None, feet=None,
              left_on=None, **kw):
    """A clip keyed by hand: keys_right / keys_left [(t, HandPose)], keys_body [(t, body dict)], feet {side: [(t, pos,
    yaw)]} in armature space."""
    c = Clip(name, L, kw.pop("hit", None), **kw)
    c.right = key_hand(keys_right)
    c.left = key_hand(keys_left) if keys_left else None
    c.left_on = left_on
    c.body = body_track(keys_body, lead=lead, look=look)
    if guardness is None:
        c.guardness = lambda t: max(1 - fl.ramp(t, 0, 0.08), fl.ramp(t, L - 0.12, L - 1.0 / fl.FPS))
    else:
        c.guardness = guardness
    if feet:
        c.feet = {}
        for side, ks in feet.items():
            sp = fl.Spline([(t, tuple(p) + (yaw,)) for t, p, yaw in ks])

            def ff(t, sp=sp):
                v = sp(t)
                return Vector(v[:3]), v[3]
            c.feet[side] = ff
    c.end_t = L
    return c


def second_hand(c, path, guard, start=None, settle=0.06, over=0.06, pre=None):
    """Gives an attack clip a second striking hand (the left) on the same timeline (both blades at once)."""
    tw, H, tf, st = c.timing
    f, g = strike_hand(path, guard, tw, H, tf, c.length, start=start, settle=st, over=over, pre=pre)
    c.left = f
    c.off_hand = f
    return c


def stepping_feet(c, steps):
    """Full-body clips that step: steps {side: [(t, (dx, dy, dz), yaw)]} offsets from the rest stance."""
    c.feet = {}
    for side in ("Right", "Left"):
        ks = steps.get(side) or [(0.0, (0, 0, 0), 0.0)]
        sp = fl.Spline([(t, tuple(p) + (yaw,)) for t, p, yaw in ks])

        def ff(t, sp=sp):
            v = sp(t)
            return Vector(v[:3]), v[3]
        c.feet[side] = ff
    c.planted = False
    return c
