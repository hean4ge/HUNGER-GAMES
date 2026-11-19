"""
fight_lib.py - Combat v3 fight clips: authoring helpers, Blender bake, checks, encoding into Luau modules.

Built on ../ls_anim.py (the proven rig: r15_rig.json -> armature, rest pose from the rig attachments, analytic arm and
leg IK every frame). What this adds:
  * Smooth tracks: monotone cubic (PCHIP) splines over timed keys, per component, so holds never overshoot and moves
    ease in and out. Every clip is evaluated in seconds, not frames.
  * A sample grid per clip whose step lands the hit exactly on a sample (dt = hit / round(hit * 30)): the strike the
    server times is a real key, never between two.
  * Cuts as arcs through three wrist points (wind-up, hit, end): the blade rides the radius, the edge leads along the
    tangent, so a slash stays on its circle instead of cutting the chord between two keys.
  * Chains: a step can start from the previous step's follow-through pose (hand and body), so a chain flows.
  * Exports per clip: third person (joint Transforms; upper-body clips fold the pelvis turn into the waist so the chest
    keeps its authored orientation while the legs keep the locomotion) and first person (wrist frames and elbow poles
    in camera space for the block viewmodel arms, derived from the same motion, settling onto the viewmodel's own
    hold at the ends).
  * Encoding: 12-bit values as two characters of a 64-letter alphabet (quaternions: all four components; positions:
    +-8 studs third person, +-4 first person).

Conventions (as ls_anim): Blender x right, y forward, z up; Roblox (x, y, z) = Blender (x, z, -y). Chest space =
UpperTorso part space (x right, y forward, z up, origin at the chest centre; the right shoulder joint is about
(0.97, 0, 0.60), the arm reaches 1.73). yaw + = turn left, pitch + = lean forward, roll + = tip right.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import bpy  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import ls_anim as la  # noqa: E402

FPS = 30
ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
UPPER_JOINTS = ["Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist"]
FULL_JOINTS = ["Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow",
               "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"]
JOINT_PART = {"Root": "LowerTorso", "Waist": "UpperTorso", "Neck": "Head", "RightShoulder": "RightUpperArm",
              "RightElbow": "RightLowerArm", "RightWrist": "RightHand", "LeftShoulder": "LeftUpperArm",
              "LeftElbow": "LeftLowerArm", "LeftWrist": "LeftHand", "RightHip": "RightUpperLeg",
              "RightKnee": "RightLowerLeg", "RightAnkle": "RightFoot", "LeftHip": "LeftUpperLeg",
              "LeftKnee": "LeftLowerLeg", "LeftAnkle": "LeftFoot"}
# first person (ViewmodelController: Rig.FACETED_SHOULDER, the block arms' reach 0.95 + 0.85)
FP_SHOULDER = {"Right": Vector((0.5, -0.72, 0.15)), "Left": Vector((-0.5, -0.72, 0.15))}
FP_REACH = 1.8
TP_REACH = 1.73
FP_MIN_EYE = 0.78  # a wrist never comes nearer the eye than this (Blocky.NEAR_HIDE)


def V(*a):
    return Vector(a if len(a) == 3 else a[0])


# ------------------------------------------------------------------------------------------------ splines
class Spline:
    """Monotone cubic Hermite (Fritsch-Carlson) per component over (t, value) keys; flat ends; clamps outside."""

    def __init__(self, keys):
        keys = sorted(keys, key=lambda k: k[0])
        self.t = [float(k[0]) for k in keys]
        self.v = [tuple(float(x) for x in (k[1] if isinstance(k[1], (tuple, list, Vector)) else (k[1],))) for k in keys]
        self.dim = len(self.v[0])
        n = len(self.t)
        self.m = []
        for c in range(self.dim):
            d = []
            for i in range(n - 1):
                h = max(self.t[i + 1] - self.t[i], 1e-9)
                d.append((self.v[i + 1][c] - self.v[i][c]) / h)
            m = [0.0] * n
            for i in range(1, n - 1):
                if d[i - 1] * d[i] > 0:
                    h0 = self.t[i] - self.t[i - 1]
                    h1 = self.t[i + 1] - self.t[i]
                    w1, w2 = 2 * h1 + h0, h1 + 2 * h0
                    m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
            self.m.append(m)

    def __call__(self, t):
        T = self.t
        if t <= T[0]:
            return self.v[0] if self.dim > 1 else self.v[0][0]
        if t >= T[-1]:
            return self.v[-1] if self.dim > 1 else self.v[-1][0]
        i = 0
        while T[i + 1] < t:
            i += 1
        h = T[i + 1] - T[i]
        s = (t - T[i]) / h
        h00 = 2 * s ** 3 - 3 * s ** 2 + 1
        h10 = s ** 3 - 2 * s ** 2 + s
        h01 = -2 * s ** 3 + 3 * s ** 2
        h11 = s ** 3 - s ** 2
        out = []
        for c in range(self.dim):
            out.append(h00 * self.v[i][c] + h10 * h * self.m[c][i] + h01 * self.v[i + 1][c] + h11 * h * self.m[c][i + 1])
        return tuple(out) if self.dim > 1 else out[0]


def smooth01(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def ramp(t, t0, t1):
    if t1 <= t0:
        return 1.0 if t >= t1 else 0.0
    return smooth01((t - t0) / (t1 - t0))


def nlerp(a, b, k):
    v = Vector(a).lerp(Vector(b), k)
    if v.length < 1e-6:
        v = Vector(b)
    return v.normalized()


# ------------------------------------------------------------------------------------------------ hand poses
class HandPose:
    """A wrist in chest space, where the held item (or the fist's knuckles) points (`blade`), where its edge leads
    (`edge`), and the elbow's direction from the shoulder."""

    __slots__ = ("wrist", "blade", "edge", "elbow")

    def __init__(self, wrist, blade, edge, elbow):
        self.wrist = Vector(wrist)
        self.blade = Vector(blade).normalized()
        self.edge = Vector(edge).normalized()
        self.elbow = Vector(elbow).normalized()

    def blend(self, other, k):
        if k <= 0:
            return self
        if k >= 1:
            return other
        return HandPose(self.wrist.lerp(other.wrist, k), nlerp(self.blade, other.blade, k),
                        nlerp(self.edge, other.edge, k), nlerp(self.elbow, other.elbow, k))

    def moved(self, d=(0, 0, 0), blade=None, edge=None, elbow=None):
        return HandPose(self.wrist + Vector(d), blade or self.blade, edge or self.edge, elbow or self.elbow)


def HP(wrist, blade, edge, elbow):
    return HandPose(wrist, blade, edge, elbow)


def key_hand(keys):
    """keys: [(t, HandPose)] -> f(t) with every channel splined."""
    ts = [k[0] for k in keys]
    sw = Spline([(t, tuple(p.wrist)) for t, p in keys])
    sb = Spline([(t, tuple(p.blade)) for t, p in keys])
    se = Spline([(t, tuple(p.edge)) for t, p in keys])
    so = Spline([(t, tuple(p.elbow)) for t, p in keys])
    del ts

    def f(t):
        return HandPose(sw(t), sb(t), se(t), so(t))
    return f


def circle3(a, b, c):
    a, b, c = Vector(a), Vector(b), Vector(c)
    ab, ac = b - a, c - a
    n = ab.cross(ac)
    if n.length < 1e-6:
        return None
    n2 = n.length_squared
    center = a + (n.cross(ab) * ac.length_squared + ac.cross(n) * ab.length_squared) / (2 * n2)
    return center, n.normalized(), (a - center).length


class Arc:
    """The wrist on the circle through the wind-up point (s = 0), the hit point (s = 1) and the end point. The blade
    points along the radius (outward, leaned by `lean`), the edge leads along the motion (toward increasing s)."""

    def __init__(self, pw, ph, pe, lean=(0, 0.3, 0), elbow=(0.5, -0.4, -1.0), elbow_hit=None, blade_flip=False,
                 radial=1.0, fixed_blade=None, blades=None):
        self.c, self.n, self.r = circle3(pw, ph, pe)
        self.a = (Vector(pw) - self.c).normalized()
        self.b = self.n.cross(self.a)

        def ang(p):
            d = (Vector(p) - self.c).normalized()
            x = math.atan2(d.dot(self.b), d.dot(self.a))
            return x
        self.ah = ang(ph)
        self.ae = ang(pe)
        if self.ah < 0:  # the hit always lies ahead of the wind-up (positive direction)
            self.n = -self.n
            self.b = -self.b
            self.ah, self.ae = -self.ah, -self.ae
        while self.ae < self.ah:
            self.ae += 2 * math.pi
        self.se = self.ae / self.ah
        self.lean = Vector(lean)
        self.elbow = Vector(elbow)
        self.elbow_hit = Vector(elbow_hit) if elbow_hit is not None else self.elbow
        self.flip = blade_flip
        self.radial = radial
        self.fixed_blade = Vector(fixed_blade) if fixed_blade else None
        # blades: [(s, direction)] keys along the arc (s = 0 wind-up, 1 hit; "e" = the end point) instead of the radius
        self.blades = None
        if blades:
            self.blades = Spline([((self.se if k == "e" else k), tuple(Vector(b).normalized())) for k, b in blades])

    def __call__(self, s):
        x = s * self.ah
        d = self.a * math.cos(x) + self.b * math.sin(x)
        tang = -self.a * math.sin(x) + self.b * math.cos(x)
        wrist = self.c + d * self.r
        if self.blades is not None:
            blade = Vector(self.blades(s))
        else:
            blade = self.fixed_blade if self.fixed_blade is not None else (d * self.radial + self.lean)
        if self.flip:
            blade = -blade
        k = min(max(s, 0.0), 1.0)
        return HandPose(wrist, blade, tang, self.elbow.lerp(self.elbow_hit, k))


class Line:
    """The wrist along a straight line (thrusts, punches): s = 0 chambered, s = 1 at the hit; blade and edge fixed."""

    def __init__(self, p0, p1, blade, edge, elbow0, elbow1=None, blade0=None, edge0=None):
        self.p0, self.p1 = Vector(p0), Vector(p1)
        self.blade, self.edge = Vector(blade), Vector(edge)
        self.blade0 = Vector(blade0) if blade0 else self.blade
        self.edge0 = Vector(edge0) if edge0 else self.edge
        self.e0 = Vector(elbow0)
        self.e1 = Vector(elbow1) if elbow1 is not None else self.e0

    def __call__(self, s):
        k = min(max(s, 0.0), 1.0)
        return HandPose(self.p0.lerp(self.p1, s), nlerp(self.blade0, self.blade, k), nlerp(self.edge0, self.edge, k),
                        self.e0.lerp(self.e1, k))


def strike_hand(path, guard, tw, th, tf, tend, start=None, settle=0.06, over=0.06, s_end=None, accel=0.2,
                hold=0.0, s_start=0.0, back=None, pre=None):
    """The striking hand: from `start` (default: the guard) onto the path's wind-up point by tw (anticipation), held
    `hold` s, accelerated through the hit at th, past the end point (overshoot `over`) at tf, settled, then back to the
    guard by tend. Returns (f(t), guardness(t)): guardness is 1 where the pose is the guard (first person settles onto
    its own hold there)."""
    se = s_end if s_end is not None else getattr(path, "se", 1.25)
    start = start or guard
    tw0 = tw + hold
    keys = [(0.0, s_start), (tw, 0.0)]
    if hold > 0:
        keys.append((tw0, -0.02))
    keys += [(tw0 + (th - tw0) * 0.45, accel), (th, 1.0), (tf, se * (1 + over)), (tf + settle, se)]
    sched = Spline(keys)
    t_back = tf + settle
    from_guard = start is guard

    def f(t):
        s = sched(t)
        p = path(s)
        if pre is not None and t < tw:  # the anticipation passes a waypoint (e.g. over the head)
            if t < tw * 0.5:
                p = start.blend(pre, ramp(t, 0.0, tw * 0.5))
            else:
                p = pre.blend(p, ramp(t, tw * 0.5, tw))
        else:
            a = ramp(t, 0.0, tw) if tw > 0 else 1.0
            p = start.blend(p, a)
        r = ramp(t, t_back, tend - 1.0 / FPS)
        if back is not None and r > 0:  # an optional waypoint on the way back (e.g. the blade turned over)
            mid = 1 - abs(2 * r - 1)
            p = p.blend(back, mid * 0.6)
        return p.blend(guard, r)

    def guardness(t):
        r = ramp(t, t_back, tend - 1.0 / FPS)
        if from_guard:
            return max(1 - ramp(t, 0.0, max(tw * 0.8, 1.0 / FPS)), r)
        return r
    return f, guardness


# ------------------------------------------------------------------------------------------------ body
BODY_KEYS = ("pelvis", "move", "chest", "head")
ZERO = {"pelvis": (0, 0, 0), "move": (0, 0, 0), "chest": (0, 0, 0), "head": (0, 0, 0)}


def body_track(keys, lead=0.025, look=(0.9, 0.7, 0.6)):
    """keys: [(t, {pelvis: (yaw, pitch, roll), move: (x, y, z), chest: (...), head: (...)})], missing channels carry
    over. The pelvis runs `lead` s ahead of the chest (the hips lead the shoulders)."""
    cur = dict(ZERO)
    full = []
    for t, d in sorted(keys, key=lambda k: k[0]):
        cur = dict(cur)
        for k, v in d.items():
            cur[k] = tuple(v) + (0,) * (3 - len(v))
        full.append((t, cur))
    sp = {k: Spline([(t, d[k]) for t, d in full]) for k in BODY_KEYS}

    def f(t):
        pel, ch, hd = sp["pelvis"](t + lead), sp["chest"](t), sp["head"](t)
        if look:  # the neck keeps the eyes on the target: it takes out most of the hips' and chest's turn and pitch
            hd = (hd[0] - look[0] * (pel[0] + ch[0]), hd[1] - look[1] * (pel[1] + ch[1]), hd[2] - look[2] * (pel[2] + ch[2]))
        return {"pelvis": pel, "move": sp["move"](t + lead), "chest": ch, "head": hd}

    def raw(t):
        return {k: tuple(sp[k](t)) for k in BODY_KEYS}
    f.raw = raw
    return f


def add_body(a, b, k=1.0):
    return {key: tuple(x + k * y for x, y in zip(a[key], b[key])) for key in BODY_KEYS}


# ------------------------------------------------------------------------------------------------ clip
class Clip:
    def __init__(self, name, length, hit=None, mask="upper", loop=False, item=None, off_item=None, kind="Blade",
                 markers=None, additive=False, fp=True, planted=True, note="", fp_left=False, family=None):
        self.name, self.length, self.hit = name, float(length), hit
        self.mask, self.loop, self.item, self.off_item = mask, loop, item, off_item
        self.kind = kind  # first person hold: Fists | Blade | Spear | Throwable | Bow
        self.markers = dict(markers or {})
        if hit is not None:
            self.markers.setdefault("Hit", hit)
        self.additive, self.fp, self.planted, self.note, self.fp_left = additive, fp, planted, note, fp_left
        self.family = family
        self.body = lambda t: dict(ZERO)
        self.right = None
        self.left = None
        self.left_on = None  # (offset along the blade, extra) when the left hand holds the right's handle
        self.feet = None
        self.guardness = lambda t: 0.0
        self.end_hand = None
        self.end_body = None
        if hit is not None and hit > 0:
            n = max(1, int(round(hit * FPS)))
            self.dt = hit / n
        else:
            self.dt = 1.0 / FPS
        self.n = int(math.ceil(self.length / self.dt - 1e-6))

    def times(self):
        return [min(i * self.dt, self.length) for i in range(self.n + 1)]


# ------------------------------------------------------------------------------------------------ scene
class Scene:
    def __init__(self, glb, items):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.scene = bpy.context.scene
        self.scene.render.fps = FPS
        self.scene.unit_settings.system = "NONE"
        self.rig = la.Rig(os.path.join(os.path.dirname(HERE), "r15_rig.json")).build("R15")
        self.rig.build_controls()
        self.items = {}
        self._import(glb, items)
        R = self.rig
        self.S = {s: R.rest["UpperTorso"].inverted() @ R.jpos[s + "UpperArm"] for s in ("Right", "Left")}
        self.stance = {s: R.jpos[s + "Foot"].copy() for s in ("Right", "Left")}

    def _import(self, glb, wanted):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=glb)
        new = [o for o in bpy.data.objects if o not in before]
        bpy.context.view_layer.update()
        keep = set()
        for key, (asset, hand) in wanted.items():
            root = next((o for o in new if o.name == asset), None) or next(
                (o for o in new if o.name.split(".")[0] == asset), None)
            if root is None:
                print("WARNING item %s not in glb" % asset)
                continue
            stack, objs = [root], []
            while stack:
                o = stack.pop()
                objs.append(o)
                stack += list(o.children)
            origin = Matrix.Translation(root.matrix_world.translation)
            meshes = []
            for o in objs:
                if o.type != "MESH":
                    continue
                # a private copy so one asset can sit in a hand while another clip uses its own
                c = o.copy()
                c.data = o.data
                bpy.context.scene.collection.objects.link(c)
                meshes.append((c, origin.inverted() @ o.matrix_world))
            grip = "RightGripAttachment" if hand == "RightHand" else "LeftGripAttachment"
            grip_cf = la.cf_to_mat(self.rig.data["attachments"][grip]["cframe"])
            in_hand = grip_cf @ la.cf_to_mat(la.HANDLE_IN_ASSET).inverted()
            lo, hi = 1e9, -1e9
            for c, local in meshes:
                c.parent = None
                self.rig.bone_parent(c, hand, in_hand @ local)
                for v in c.data.vertices:
                    z = (local @ v.co).z
                    lo, hi = min(lo, z), max(hi, z)
            self.items[key] = {"asset": key, "hand": hand, "in_hand": in_hand,
                               "meshes": [c for c, _ in meshes], "span": (lo, hi)}
            keep.update(c for c, _ in meshes)
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)

    def show_items(self, keys):
        self.rig.items = []
        for k, it in self.items.items():
            on = k in keys
            for m in it["meshes"]:
                m.hide_render = not on
                m.hide_viewport = not on
            if on:
                self.rig.items.append(it)

    # -- keying one clip ----------------------------------------------------------------------------------
    def clear(self):
        R = self.rig
        for ob in [R.arm] + list(R.ctl.values()):
            ob.animation_data_clear()
        R._last_q = {}
        for pb in R.arm.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)

    def key(self, clip):
        R = self.rig
        self.clear()
        times = clip.times()
        scene = self.scene
        scene.frame_start, scene.frame_end = 0, clip.n
        free_left = clip.off_item is None and clip.left_on is None
        for f, t in enumerate(times):
            b = clip.body(t)
            R.key_joint("LowerTorso", la.torso_rot(*b["pelvis"]), f, loc=b["move"])
            R.key_joint("UpperTorso", la.torso_rot(*b["chest"]), f)
            R.key_joint("Head", la.torso_rot(*b["head"]), f)
            rp = clip.right(t)
            R.key_ctl("RightHand", f, pos=rp.wrist, rot=la.blade_frame(rp.blade, rp.edge))
            R.key_ctl("RightElbow", f, pos=self.S["Right"] + rp.elbow * 1.5)
            if clip.left_on is not None:
                along, extra = clip.left_on(t) if callable(clip.left_on) else clip.left_on
                lw = rp.wrist + rp.blade * along + Vector(extra)
                lq = la.blade_frame(rp.blade, rp.edge)
                le = Vector((-0.7, -0.4, -1.0)).normalized()
                w = clip.left_on_w(t) if getattr(clip, "left_on_w", None) else 1.0
                if w < 1 and clip.left is not None:  # the hand comes onto the haft from where it was
                    lp = clip.left(t)
                    lw = lp.wrist.lerp(lw, w)
                    lq = la.blade_frame(lp.blade, lp.edge).slerp(lq, w)
                    le = lp.elbow.lerp(le, w)
                R.key_ctl("LeftHand", f, pos=lw, rot=lq)
                R.key_ctl("LeftElbow", f, pos=self.S["Left"] + le.normalized() * 1.5)
            elif clip.left is not None:
                lp = clip.left(t)
                R.key_ctl("LeftHand", f, pos=lp.wrist, rot=la.blade_frame(lp.blade, lp.edge))
                R.key_ctl("LeftElbow", f, pos=self.S["Left"] + lp.elbow * 1.5)
            if getattr(clip, "pivot_feet", None) is not None:  # the feet turn with the hips about the root (a spin)
                a = math.radians(clip.pivot_feet(t))
                Rz = Matrix.Rotation(a, 3, "Z")
                lift = 0.25 * math.sin(math.pi * min(max((t - 0.35) / 0.3, 0), 1))
                for side in ("Right", "Left"):
                    p0 = self.stance[side]
                    p1 = Rz @ Vector((p0.x, p0.y, 0)) + Vector((0, 0, p0.z + (lift if side == "Right" else 0)))
                    R.key_ctl(side + "Foot", f, pos=p1, rot=la.rz(clip.pivot_feet(t)))
            elif clip.feet is not None:
                for side in ("Right", "Left"):
                    off_, yaw = clip.feet[side](t)  # offset from the rest stance (armature space) and turn
                    R.key_ctl(side + "Foot", f, pos=self.stance[side] + Vector(off_), rot=la.rz(yaw))
            else:
                for side in ("Right", "Left"):
                    R.key_ctl(side + "Foot", f, pos=self.stance[side], rot=Quaternion())
        report = R.bake_limbs(0, clip.n, follow_forearm=("Left",) if free_left else ())
        warn = []
        for f, part, ok, wrist in report:
            if not ok:
                warn.append("unreachable f%d %s" % (f, part))
            if wrist > 85:
                warn.append("wrist f%d %s %.0f" % (f, part, wrist))
        return warn

    # -- checks ------------------------------------------------------------------------------------------
    def check(self, clip):
        R = self.rig
        lines = []
        up = -R.ground
        foot0 = {}
        for f in range(clip.n + 1):
            D = R.deltas(f)
            if clip.planted and clip.feet is None:
                for ft in ("LeftFoot", "RightFoot"):
                    p = (D[ft] @ R.rest[ft]).translation
                    foot0.setdefault(ft, p.copy())
                    if (p - foot0[ft]).length > 2e-3:
                        lines.append("FOOT_SLIDE f%d %s %.3f" % (f, ft, (p - foot0[ft]).length))
            # hands and forearms never sink into the trunk, the head or the legs
            for side in ("Right", "Left"):
                for limb in (side + "Hand", side + "LowerArm"):
                    p = (D[limb] @ R.rest[limb]).translation
                    for n in ("UpperTorso", "LowerTorso", "Head", "RightUpperLeg", "LeftUpperLeg"):
                        q = (D[n] @ R.rest[n]).inverted() @ p
                        sx, sy, sz = R.parts[n]["size"]
                        if abs(q.x) < sx / 2 - 0.05 and abs(q.y) < sz / 2 - 0.05 and abs(q.z) < sy / 2 - 0.05:
                            lines.append("LIMB_IN_BODY f%d %s in %s" % (f, limb, n))
            for it in R.items:
                Wm = D[it["hand"]] @ R.rest[it["hand"]] @ it["in_hand"]
                lo, hi = it["span"]
                a, b = Vector((0, 0, max(lo, 0.25) if lo < 0.25 else lo)), Vector((0, 0, hi))
                side = "Right" if it["hand"] == "RightHand" else "Left"
                skip = {side + "Hand", side + "LowerArm", la.ROOT}
                if clip.left_on is not None:
                    skip |= {"LeftHand", "LeftLowerArm"}
                low = min((Wm @ a).z, (Wm @ b).z) + up
                if low < 0.05:
                    lines.append("BLADE_GROUND f%d %s %.2f" % (f, it["asset"], low))
                hits = {}
                for i in range(1, 21):
                    p = Wm @ a.lerp(b, i / 20.0)
                    for n in R.order:
                        if n in skip:
                            continue
                        q = (D[n] @ R.rest[n]).inverted() @ p
                        sx, sy, sz = R.parts[n]["size"]
                        if abs(q.x) < sx / 2 - 0.03 and abs(q.y) < sz / 2 - 0.03 and abs(q.z) < sy / 2 - 0.03:
                            hits[n] = hits.get(n, 0) + 1
                for n, c in hits.items():
                    lines.append("BLADE_IN_BODY f%d %s %s %d/20" % (f, it["asset"], n, c))
        return lines

    # -- export ------------------------------------------------------------------------------------------
    def transforms(self, clip):
        """Per sample: {joint: Matrix} (Blender axes) of the joint Transform the game sets."""
        R = self.rig
        out = []
        for f in range(clip.n + 1):
            D = R.deltas(f)
            row = {}
            for j in FULL_JOINTS:
                n = JOINT_PART[j]
                p = R.parent[n]
                if clip.mask != "full" and j == "Waist":
                    # the pelvis turn folded into the waist: the chest keeps its authored orientation over the rest
                    # pelvis (the legs belong to the locomotion)
                    M = (R.rest[p] @ R.c0[n]).inverted() @ (D[n] @ R.rest[n] @ R.c1[n])
                    M = M.to_3x3().normalized().to_4x4()
                else:
                    M = (D[p] @ R.rest[p] @ R.c0[n]).inverted() @ (D[n] @ R.rest[n] @ R.c1[n])
                row[j] = M
            out.append(row)
        return out

    def fp_frames(self, clip, hold):
        """First person: per sample (rightCF, leftCF, rightPole, leftPole) in camera space (Roblox axes)."""
        R = self.rig
        raw = []
        for f in range(clip.n + 1):
            D = R.deltas(f)
            fr = {}
            for side in ("Right", "Left"):
                ua, la_, hd = side + "UpperArm", side + "LowerArm", side + "Hand"
                S = (D[ua] @ R.rest[ua] @ R.c1[ua]).translation
                E = (D[la_] @ R.rest[la_] @ R.c1[la_]).translation
                W = (D[hd] @ R.rest[hd] @ R.c1[hd]).translation
                rel = (W - S) * (FP_REACH / TP_REACH)
                pos = FP_SHOULDER[side] + b2cam(rel)
                if pos.length < FP_MIN_EYE:
                    pos = pos.normalized() * FP_MIN_EYE
                axis = (W - S).normalized()
                pole = (E - S) - axis * (E - S).dot(axis)
                pole = b2cam(pole.normalized() if pole.length > 1e-4 else Vector((0, 0, -1)))
                Rm = D[hd].to_3x3().normalized()
                blade = b2cam(Rm @ Vector((0, 0, -1)))
                edge = b2cam(Rm @ Vector((0, -1, 0)))
                if clip.kind == "Fists" or (side == "Left" and clip.left_on is None and clip.off_item is None):
                    thumb, knuckles = -edge, blade
                else:
                    thumb, knuckles = blade, edge
                fr[side] = (hand_cf(pos, thumb, knuckles), pole)
            raw.append(fr)
        end = raw[-1] if not clip.loop else raw[0]
        out = []
        for f, t in enumerate(clip.times()):
            g = clip.guardness(t)
            row = []
            for side in ("Right", "Left"):
                cf, pole = raw[f][side]
                ecf, epole = end[side]
                hcf = hold[side]
                # relative to the clip's own guard, laid onto the viewmodel's hold
                rpos = hcf[0] + (cf[0] - ecf[0])
                rq = (cf[1] @ ecf[1].inverted()) @ hcf[1]
                pos = rpos.lerp(cf[0], 1 - g)
                q = rq.slerp(cf[1], 1 - g) if g < 1 else rq
                row.append(((pos, q), pole))
            out.append(row)
        return out


def b2cam(v):
    """Blender armature axes -> Roblox camera space (x right, y up, z back)."""
    return Vector((v.x, v.z, -v.y))


def hand_cf(pos, thumb, knuckles):
    """Poses.hand: y = thumb, z = -(knuckles orthogonalised), x = y x z. Returns (pos, Quaternion) in Roblox axes."""
    y = thumb.normalized()
    e = knuckles - y * knuckles.dot(y)
    if e.length < 1e-4:
        e = Vector((0, 0, -1)) - y * (-y.z)
    z = -e.normalized()
    x = y.cross(z)
    M = Matrix((x, y, z)).transposed()
    return (Vector(pos), M.to_quaternion())


def poses_hand(pos, thumb, knuckles):
    return hand_cf(Vector(pos), Vector(thumb), Vector(knuckles))


def faceted_hand(wrist, fingers, palm, left=False):
    f = Vector(fingers).normalized()
    p = Vector(palm) - f * Vector(palm).dot(f)
    p = p.normalized() if p.length > 1e-3 else Vector((0, -1, 0))
    return hand_cf(Vector(wrist), p.cross(f) if left else f.cross(p), f)


F_LOW_LEFT = faceted_hand((-0.62, -1.25, -0.75), (0.25, 0.3, -0.92), (0.6, -0.8, 0), True)
# The Blocky viewmodel's holds (Blocky.poses over Poses.FACETED), the right and left wrist frames per kind.
FP_HOLD = {
    "Fists": {"Right": poses_hand((0.70, -0.72, -1.08), (-0.3, 0.95, 0.12), (-0.22, 0.28, -0.94)),
              "Left": poses_hand((-0.70, -0.74, -1.10), (0.3, 0.95, 0.12), (0.22, 0.28, -0.94))},
    "Blade": {"Right": poses_hand((0.9, -0.66, -1.05), (0.22, 1, -0.3), (-0.12, 0.15, -1)), "Left": F_LOW_LEFT},
    "Throwable": {"Right": poses_hand((0.9, -0.66, -1.05), (0.15, 0.85, -0.5), (-0.12, 0.45, -0.88)), "Left": F_LOW_LEFT},
    "Spear": {"Right": poses_hand((0.33, -0.97, -0.7), (-0.74, 0.4, -0.54), (-0.25, -0.88, -0.3)),
              "Left": poses_hand((-0.597, -0.964, -1.247), (-0.742, 0.363, -0.564), (0.670, 0.359, -0.650))},
    "Bow": {"Right": poses_hand((0.55, -1.3, -1.1), (-0.1, 1, -0.2), (-0.3, -0.2, -1)),
            "Left": poses_hand((-0.703, -1.315, -1.376), (-0.555, 0.822, 0.128), (-0.431, -0.153, -0.889))},
}
FP_HOLD["Paired"] = {"Right": FP_HOLD["Blade"]["Right"],
                     "Left": poses_hand((-0.9, -0.66, -1.05), (-0.22, 1, -0.3), (0.12, 0.15, -1))}


# ------------------------------------------------------------------------------------------------ encoding
def enc(v, lo, hi):
    x = int(round((min(max(v, lo), hi) - lo) / (hi - lo) * 4095))
    return ALPHA[x >> 6] + ALPHA[x & 63]


def enc_quat(q, prev):
    if prev is not None and q.dot(prev) < 0:
        q = -q
    return "".join(enc(c, -1, 1) for c in (q.x, q.y, q.z, q.w)), q


def roblox_quat(M):
    """Blender-axes rotation matrix -> quaternion in Roblox axes."""
    R3 = la.C_B2R @ M.to_3x3().normalized() @ la.C_R2B
    q = R3.to_quaternion()
    q.normalize()
    return q


def encode_tp(clip, rows):
    joints = FULL_JOINTS if clip.mask == "full" else UPPER_JOINTS
    prev = {}
    out = []
    root_pos = clip.mask == "full"
    for row in rows:
        s = []
        for j in joints:
            M = row[j]
            q = roblox_quat(M)
            txt, prev[j] = enc_quat(q, prev.get(j))
            s.append(txt)
            if j == "Root" and root_pos:
                p = la.C_B2R @ M.translation
                s.append("".join(enc(c, -8, 8) for c in p))
        out.append("".join(s))
    return "".join(out), joints


def encode_fp(rows):
    prev = {}
    out = []
    for row in rows:
        s = []
        for i, ((pos, q), pole) in enumerate(row):
            s.append("".join(enc(c, -4, 4) for c in pos))
            txt, prev[i] = enc_quat(q, prev.get(i))
            s.append(txt)
        for i, (_, pole) in enumerate(row):
            s.append("".join(enc(c, -1, 1) for c in pole))
        out.append("".join(s))
    return "".join(out)


def lua_str(s):
    return '"' + s + '"'


def write_module(path, family, entries, header):
    lines = ["--[[", "\tFightClips." + family + " - generated by art/blender/anim/fight/build_fight_clips.py. Do not edit by hand.",
             "\t" + header.replace("\n", "\n\t"), "]]", "return {", '\tformat = "ls_fight/1",',
             "\tfamily = %s," % lua_str(family), "\tclips = {"]
    for e in entries:
        parts = ["len = %.4f" % e["len"], "dt = %.6f" % e["dt"], "n = %d" % e["n"], 'mask = "%s"' % e["mask"]]
        if e.get("hit") is not None:
            parts.append("hit = %.4f" % e["hit"])
        if e.get("loop"):
            parts.append("loop = true")
        if e.get("additive"):
            parts.append("additive = true")
        if e.get("item"):
            parts.append('item = "%s"' % e["item"])
        if e.get("kind"):
            parts.append('kind = "%s"' % e["kind"])
        if e.get("fpLeft"):
            parts.append("fpLeft = true")
        if e.get("markers"):
            parts.append("markers = { " + ", ".join("%s = %.4f" % (k, v) for k, v in sorted(e["markers"].items())) + " }")
        lines.append("\t\t%s = {" % e["name"])
        lines.append("\t\t\t" + ", ".join(parts) + ",")
        lines.append("\t\t\ttp = %s," % lua_str(e["tp"]))
        if e.get("fp"):
            lines.append("\t\t\tfp = %s," % lua_str(e["fp"]))
        lines.append("\t\t},")
    lines += ["\t},", "}", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    return os.path.getsize(path)


# ------------------------------------------------------------------------------------------------ preview
def setup_preview(scene):
    la.daylight(scene)
    dev = la.enable_gpu(scene)
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    try:
        scene.view_settings.view_transform = "AgX"
    except Exception:
        pass
    return dev


def render_tiles(scene, shots, out_png, tile=(480, 560), cols=4, target=(0.0, 0.6, 3.4), azim=38.0, elev=12.0,
                 dist=19.0, lens=62.0):
    """shots: [(callable that keys the scene, frame, label)] -> one contact sheet."""
    import numpy as np
    scene.render.resolution_x, scene.render.resolution_y = tile
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    cd = bpy.data.cameras.new("FC_Cam")
    cd.lens = lens
    cd.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("FC_Cam", cd)
    scene.collection.objects.link(cam)
    a, e = math.radians(azim), math.radians(elev)
    tgt = Vector(target)
    cam.location = tgt + dist * Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    fd = bpy.data.curves.new("FC_Label", "FONT")
    fd.size = 0.042
    txt = bpy.data.objects.new("FC_Label", fd)
    scene.collection.objects.link(txt)
    txt.parent = cam
    half_w = 0.5 * 36.0 / lens
    half_h = half_w * tile[1] / tile[0]
    txt.location = (-half_w * 0.94, -half_h * 0.94, -1.0)
    tm = bpy.data.materials.new("FC_Label")
    tm.use_nodes = True
    tm.node_tree.nodes.clear()
    o = tm.node_tree.nodes.new("ShaderNodeOutputMaterial")
    em = tm.node_tree.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 3.0
    tm.node_tree.links.new(em.outputs[0], o.inputs["Surface"])
    fd.materials.append(tm)
    txt.visible_shadow = False
    tmp = os.path.join(os.path.dirname(out_png), "_tiles")
    os.makedirs(tmp, exist_ok=True)
    paths = []
    for i, (prep, f, label) in enumerate(shots):
        if prep is not None:
            prep()
        scene.frame_set(f)
        fd.body = label
        p = os.path.join(tmp, "t%02d.png" % i)
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    rows = int(math.ceil(len(paths) / cols))
    W, H = tile
    sheet = np.zeros((rows * H, cols * W, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        px = np.empty(W * H * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(H, W, 4)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * H
        sheet[y0:y0 + H, c * W:(c + 1) * W, :] = px
        sheet[y0:y0 + H, c * W, :3] = 0.08
        sheet[y0, c * W:(c + 1) * W, :3] = 0.08
        bpy.data.images.remove(img)
    out = bpy.data.images.new("FC_Sheet", cols * W, rows * H, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = out_png
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    bpy.data.objects.remove(txt, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)
