"""
arms.py - LAST STANDING first-person viewmodel arms  ->  Arms.glb + Arms.manifest.json

Rigid pieces that the ViewmodelController animates procedurally (no rig, no skinning).

FRAME CONVENTION (every piece, Blender coordinates; Roblox = (x, z, -y)):
  origin  the PROXIMAL joint pivot (shoulder / elbow / wrist)
  +Z      bone axis, proximal -> distal            (Roblox +Y, the part's UpVector)
  +Y      back of the arm / back of the hand        (Roblox -Z, the part's LookVector)
  -Y      palm side / inside of the elbow (the elbow flexes toward -Y)
  +X      thumb side on R_ pieces                   (Roblox +X); L_ pieces are exact mirrors (thumb on -X)
With every joint at zero rotation the pieces chain straight up +Z: shoulder -> elbow (1.9) -> wrist (+1.7)
in modelling units; the export is scaled by KIT_SCALE = 0.5 to world scale (elbow 0.95, wrist +0.85), see below.
Each parent piece owns the rounded joint cover (the upper arm's elbow ball, the forearm's wrist end tucked
into the glove cuff), so children start at their pivot and the joints stay closed when bent.

Run (headless):
  blender --background --factory-startup --python arms.py -- <out_dir> <preview_dir>
Optional env: ARMS_DEBUG_DIR=<folder> renders extra close-up contact sheets for art review.
"""
import os
import sys
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls  # noqa: E402
import ls_patch  # noqa: F401,E402  (art-direction fixes on top of ls_common: hard edges, bounds, query flags)

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

out_dir, preview_dir = ls.args()
ls.reset()
ls.seed(1907)

DEBUG_DIR = os.environ.get("ARMS_DEBUG_DIR")
TAU = 2.0 * math.pi
V = Vector

# WORLD SCALE (art direction). The kit is modelled at 2x (all constants below: upper arm 1.9, forearm 1.7, grip
# around a 0.3 handle) and every piece is scaled by KIT_SCALE about its pivot just before export, so the exported
# arms match the 5.5-stud player (upper arm 0.95, forearm 0.85, hand ~0.55) and the Items handles (0.12-0.17
# across) sit 1:1 in the grip hand (~0.15 handle). The review renders are scale-invariant and run before that.
KIT_SCALE = 0.5


def ws(x):
    """A modelling-space length as the exported (world-scale) number, for notes."""
    return "%g" % round(x * KIT_SCALE, 3)


# ------------------------------------------------------------------------------------------------
# Preview camera: ls_common frames on cam.data.angle, which is the horizontal FOV by default, so tall
# arm pieces were cropped top/bottom. ls_common reuses an existing "_PreviewCam", so creating it here
# with a vertical sensor fit only changes this category's framing (the bounding sphere fits both ways).
# ------------------------------------------------------------------------------------------------
def make_preview_cam():
    cam_data = bpy.data.cameras.new("_PreviewCam")
    cam_data.lens = 50
    cam_data.sensor_fit = "VERTICAL"
    cam_data.sensor_height = 27.0
    cam_data.clip_start = 0.02
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new("_PreviewCam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    return cam


make_preview_cam()


# ------------------------------------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------------------------------------
def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def interp_table(table, x):
    """table: list of (x, v0, v1, ...) sorted by x -> linearly interpolated tuple of values."""
    if x <= table[0][0]:
        return table[0][1:]
    for a, b in zip(table, table[1:]):
        if x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return tuple(lerp(p, q, t) for p, q in zip(a[1:], b[1:]))
    return table[-1][1:]


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def frame_from(z_dir, y_hint):
    """3x3 frame (columns x, y, z) with z along z_dir and y as close as possible to y_hint."""
    z = V(z_dir).normalized()
    y = V(y_hint)
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


def ring_pts(center, fx, fy, rxp, rxn, ryp, ryn, n, phase=math.pi / 2, ex_d=2.0, ex_p=2.0, radial=None):
    """Closed ring of n points around center in the plane (fx, fy). Asymmetric half-sizes:
    rxp (+x), rxn (-x), ryp (+y), ryn (-y). ex_d / ex_p: superellipse exponents of the +y / -y halves
    (2 = ellipse, >2 boxier). radial(angle) -> extra outward offset (studs) for folds and bumps."""
    pts = []
    for i in range(n):
        a = phase + TAU * i / n
        c, s = math.cos(a), math.sin(a)
        e = 2.0 / (ex_d if s >= 0 else ex_p)
        x = math.copysign(abs(c) ** e, c) * (rxp if c >= 0 else rxn)
        y = math.copysign(abs(s) ** e, s) * (ryp if s >= 0 else ryn)
        if radial is not None:
            off = radial(a)
            ln = math.hypot(x, y)
            if ln > 1e-6:
                x += x / ln * off
                y += y / ln * off
        pts.append(V(center) + fx * x + fy * y)
    return pts


def loft(name, rings, start=None, end=None, closed=False):
    """Skin a list of equal-length rings with quads. start/end: None (open), "flat" (n-gon cap) or a
    point (pole fan). closed=True joins the last ring back to the first (a band / torus)."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    count = len(vr) if closed else len(vr) - 1
    for k in range(count):
        a, b = vr[k], vr[(k + 1) % len(vr)]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))

    def cap(rv, where, reverse):
        if where is None:
            return
        if isinstance(where, str):
            bm.faces.new(list(reversed(rv)) if reverse else rv)
            return
        pv = bm.verts.new(V(where))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rv[j], rv[i], pv) if reverse else (rv[i], rv[j], pv))

    if not closed:
        cap(vr[0], start, True)
        cap(vr[-1], end, False)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def union_all(base, others, name):
    """Boolean-union closed shells into one manifold (EXACT solver). Grazing intersections become real
    edges that smooth-shade into a seamless blend, and buried caps / hidden insides are removed."""
    coll = bpy.data.collections.new(name + "_ops")
    bpy.context.scene.collection.children.link(coll)
    for o in others:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    mod = base.modifiers.new("Union", "BOOLEAN")
    mod.operation = "UNION"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    mod.solver = "EXACT"
    mod.use_self = True
    mod.use_hole_tolerant = True
    ls.apply_modifiers(base)
    for o in others:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(coll)
    base.name = name
    return base


def mirror_x(obj):
    """True mirror across the YZ plane with outward normals restored."""
    obj.data.transform(Matrix.Scale(-1.0, 4, (1.0, 0.0, 0.0)))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def mx(v, side):
    return V((v[0] * side, v[1], v[2]))


def seg_seg_dist(p1, q1, p2, q2):
    """Closest distance between segments p1q1 and p2q2."""
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = d1.dot(d1), d2.dot(d2), d2.dot(r)
    if a < 1e-12 and e < 1e-12:
        return r.length
    if a < 1e-12:
        s, t = 0.0, max(0.0, min(1.0, f / e))
    else:
        c = d1.dot(r)
        if e < 1e-12:
            t, s = 0.0, max(0.0, min(1.0, -c / a))
        else:
            b = d1.dot(d2)
            den = a * e - b * b
            s = max(0.0, min(1.0, (b * f - c * e) / den)) if den > 1e-12 else 0.0
            t = (b * s + f) / e
            if t < 0.0:
                t, s = 0.0, max(0.0, min(1.0, -c / a))
            elif t > 1.0:
                t, s = 1.0, max(0.0, min(1.0, (b - c) / a))
    return ((p1 + d1 * s) - (p2 + d2 * t)).length


# ------------------------------------------------------------------------------------------------
# Kinematic chain (fingers / thumb). f[0] is the base frame before joint 0, f[s+1] the frame of the
# segment from joint s to joint s+1 (columns x, y, z; z along the bone, y = back of the finger / nail).
# ------------------------------------------------------------------------------------------------
class Chain:
    def __init__(self, p0, frames, lengths):
        self.L = list(lengths)
        self.f = [F.copy() for F in frames]
        self.p = [V(p0)]
        for s, L in enumerate(lengths):
            self.p.append(self.p[-1] + self.f[s + 1].col[2] * L)
        self.u = [0.0]
        for L in lengths:
            self.u.append(self.u[-1] + L)
        self.ang = [math.degrees(self.f[k].col[2].angle(self.f[k + 1].col[2], 0.0)) for k in range(len(lengths))]

    @classmethod
    def fk(cls, p0, f0, lengths, angles):
        """Flexion = rotation about the local +X axis, swinging the bone (+Z) toward the palm (-Y)."""
        frames, F = [f0.copy()], f0.copy()
        for a in angles:
            F = F @ rot("X", a)
            frames.append(F.copy())
        return cls(p0, frames, lengths)

    @classmethod
    def from_dirs(cls, p0, dirs, backs, lengths):
        frames = [frame_from(d, b) for d, b in zip(dirs, backs)]
        return cls(p0, [frames[0]] + frames, lengths)

    def at(self, u):
        """(position, frame) at arc length u (u < 0 runs back along the base frame)."""
        if u <= 0.0:
            return self.p[0] + self.f[0].col[2] * u, self.f[0]
        for s in range(len(self.L)):
            if u <= self.u[s + 1] or s == len(self.L) - 1:
                return self.p[s] + self.f[s + 1].col[2] * (u - self.u[s]), self.f[s + 1]

    def joint_frame(self, k):
        q0 = self.f[k].to_quaternion()
        q1 = self.f[k + 1].to_quaternion()
        if q0.dot(q1) < 0:
            q1.negate()
        return q0.slerp(q1, 0.5).to_matrix()

    def bend_out(self, k):
        d = self.f[k].col[2] - self.f[k + 1].col[2]
        return d.normalized() if d.length > 1e-5 else None

    def segments(self):
        return [(self.p[s], self.p[s + 1]) for s in range(len(self.L))]


def _knuckle(pts, pos, b, half, bulge, crease, weight=1.0):
    """Outside of a bent joint bulges (knuckle), inside tucks in (crease). Linear falloff spreads the
    bulge over several ring vertices so the crest stays round."""
    grow = bulge * (1.0 / math.cos(half) - 1.0) * weight
    shrink = crease * math.sin(half) * weight
    for p in pts:
        off = p - pos
        c = off.normalized().dot(b)
        k_ = 1.0 + grow * c if c > 0 else 1.0 - shrink * (-c) ** 1.2
        k_ *= 1.0 + 0.04 * math.sin(half) * weight
        p.xyz = pos + off * k_


def tube_rings(chain, stations, prof, n, bulge=0.75, crease=0.22, ex_d=2.0, ex_p=2.0, phase=math.pi / 2):
    """stations: ("u", u) plain ring | ("j", k) one ring on joint k's bisector | ("f", (k, d, m)) m rings
    along a fillet (quadratic Bezier) between u_k - d and u_k + d, for deep bends. prof(u) -> half sizes."""
    rings = []
    for kind, val in stations:
        if kind == "j":
            k = val
            pos, F = chain.p[k], chain.joint_frame(k)
            pts = ring_pts(pos, F.col[0], F.col[1], *prof(chain.u[k]), n, phase=phase, ex_d=ex_d, ex_p=ex_p)
            b = chain.bend_out(k)
            half = math.radians(chain.ang[k]) * 0.5
            if b is not None and half > 1e-3:
                _knuckle(pts, pos, b, half, bulge, crease)
            rings.append(pts)
        elif kind == "f":
            k, d, m = val
            J = chain.p[k]
            A = J - chain.f[k].col[2] * d
            B = J + chain.f[k + 1].col[2] * d
            q0, q1 = chain.f[k].to_quaternion(), chain.f[k + 1].to_quaternion()
            if q0.dot(q1) < 0:
                q1.negate()
            b = chain.bend_out(k)
            half = math.radians(chain.ang[k]) * 0.5
            for i in range(1, m + 1):
                t = i / (m + 1.0)
                pos = A * (1 - t) ** 2 + J * (2 * t * (1 - t)) + B * (t * t)
                F = q0.slerp(q1, t).to_matrix()
                pts = ring_pts(pos, F.col[0], F.col[1], *prof(chain.u[k] + (2 * t - 1) * d), n, phase=phase,
                               ex_d=ex_d, ex_p=ex_p)
                if b is not None:   # the fillet already rounds the bend: only a light knuckle on top
                    _knuckle(pts, pos, b, half, bulge * 0.45, crease, weight=math.sin(math.pi * t))
                rings.append(pts)
        else:
            pos, F = chain.at(val)
            rings.append(ring_pts(pos, F.col[0], F.col[1], *prof(val), n, phase=phase, ex_d=ex_d, ex_p=ex_p))
    return rings


def joint_delta(chain, k, r, lo=0.026, frac=0.42):
    """Distance of the rings either side of joint k so a sharp bend doesn't fold the tube."""
    half = math.radians(chain.ang[k]) * 0.5
    d = max(lo, r * math.tan(half) * 1.1)
    lim = frac * min(chain.L[k - 1] if k > 0 else 1.0, chain.L[k] if k < len(chain.L) else 1.0)
    return min(d, lim)


def tip_cap(chain, u0, u_end, prof, n, pad_shift=0.25):
    """Rounded fingertip from arc length u0 (last shaft ring) to u_end: three closing rings on a
    rounded profile and a pole, pulled slightly toward the pad (-Y)."""
    rings = []
    base = prof(u0)
    cap_len = u_end - u0
    for t, sc in ((0.45, 0.96), (0.78, 0.74), (0.94, 0.40)):
        u = u0 + cap_len * t
        pos, F = chain.at(u)
        shift = -F.col[1] * base[3] * pad_shift * t
        rxp, rxn, ryp, ryn = base
        rings.append(ring_pts(pos + shift, F.col[0], F.col[1], rxp * sc, rxn * sc, ryp * sc, ryn * sc, n))
    pos, F = chain.at(u_end)
    pole = pos - F.col[1] * base[3] * pad_shift * 1.05
    return rings, pole


# ------------------------------------------------------------------------------------------------
# Hand anatomy (RIGHT hand, studs). Hand frame: origin = wrist pivot, +Z toward the fingers,
# +Y back of the hand, +X thumb side. Proportions: palm ~0.52 wide, hand ~1.2 long (matches the
# 1.9 / 1.7 arm segments), fingers a touch chunkier than life for readability.
# ------------------------------------------------------------------------------------------------
LEATHER = 0.016          # glove thickness over the skin
SKIN_SEG = 10            # ring segments: fingers (skin)
SKIN_SEG_SMALL = 8       # little finger
GLOVE_SEG = 8            # finger sleeves of the glove
THUMB_GLOVE_SEG = 10
PALM_SEG = 12            # glove palm shell
PALM_EXD, PALM_EXP = 2.7, 2.2   # palm cross-section superellipse (boxier back of the hand)
STRAP_SEG = 12

FINGERS = [
    # name, MCP joint centre (x, y, z), phalanx lengths (prox, mid, dist incl. tip), half width, half depth
    ("Index", (0.166, 0.028, 0.585), (0.255, 0.150, 0.128), 0.065, 0.057),
    ("Middle", (0.055, 0.034, 0.608), (0.275, 0.168, 0.134), 0.068, 0.059),
    ("Ring", (-0.058, 0.030, 0.590), (0.258, 0.160, 0.130), 0.064, 0.056),
    ("Little", (-0.163, 0.016, 0.535), (0.205, 0.122, 0.114), 0.055, 0.049),
]
THUMB = dict(base=(0.116, -0.050, 0.110), L=(0.280, 0.195, 0.175), w=0.072, d=0.062)

# Glove palm shell (outer surface): z, half width thumb side, half width little side, back, palm, centre y
PALM = [
    (0.000, 0.198, 0.196, 0.146, 0.148, 0.000),
    (0.100, 0.206, 0.204, 0.148, 0.152, 0.000),
    (0.220, 0.232, 0.226, 0.136, 0.150, -0.004),
    (0.360, 0.256, 0.247, 0.121, 0.128, -0.004),
    (0.490, 0.266, 0.255, 0.108, 0.110, 0.003),
    (0.575, 0.262, 0.244, 0.100, 0.098, 0.010),
]
PALM_END = 0.580

# Forearm skin cross-section (forearm frame z): z, half width, back, palm
FOREARM_SKIN = [
    (0.96, 0.200, 0.172, 0.168),
    (1.10, 0.196, 0.164, 0.160),
    (1.26, 0.189, 0.152, 0.150),
    (1.40, 0.182, 0.141, 0.139),
    (1.52, 0.176, 0.132, 0.130),
    (1.62, 0.172, 0.126, 0.125),
    (1.70, 0.170, 0.124, 0.123),
]
UPPER_LEN = 1.9
FORE_LEN = 1.7


def finger_prof(w, d, L, extra=0.0):
    u1, u2 = L[0], L[0] + L[1]
    u3 = u2 + L[2]
    # u, width scale, back scale, palm scale
    keys = [(-0.30, 1.06, 0.98, 1.00), (0.00, 1.07, 1.00, 1.00), (u1 * 0.5, 1.00, 0.92, 1.00),
            (u1, 0.98, 0.90, 0.94), ((u1 + u2) * 0.5, 0.89, 0.84, 0.92), (u2, 0.88, 0.80, 0.86),
            (u2 + 0.5 * L[2], 0.88, 0.74, 0.92), (u3, 0.83, 0.70, 0.86)]

    def f(u):
        ws, ds, ps = interp_table(keys, u)
        return (w * ws + extra, w * ws + extra, d * ds + extra, d * ps + extra)
    return f


def thumb_prof(w, d, L, extra=0.0):
    um, up = L[0], L[0] + L[1]
    ue = up + L[2]
    keys = [(-0.20, 1.22, 0.95, 1.30), (0.00, 1.25, 0.98, 1.38), (um * 0.55, 1.18, 0.98, 1.30),
            (um, 1.06, 1.00, 1.04), ((um + up) * 0.5, 1.00, 0.96, 0.98), (up, 0.98, 0.92, 0.92),
            (up + 0.5 * L[2], 1.00, 0.80, 0.98), (ue, 0.92, 0.74, 0.90)]

    def f(u):
        ws, ds, ps = interp_table(keys, u)
        return (w * ws + extra, w * ws + extra, d * ds + extra, d * ps + extra)
    return f


# ------------------------------------------------------------------------------------------------
# Poses. Fingers: (mcp, pip, dip flexion deg, splay deg (+ toward the thumb), roll deg).
# Thumb: explicit bone directions + back-of-thumb (nail side) directions for metacarpal / proximal / distal.
# ------------------------------------------------------------------------------------------------
POSES = {
    "Open": dict(
        cup=0.012, pads=(0.026, 0.012),
        fingers={"Index": (10, 14, 8, 4.5, 0), "Middle": (13, 18, 10, 0.5, 0),
                 "Ring": (16, 23, 12, -3.5, 0), "Little": (21, 28, 15, -8.0, 0)},
        thumb=dict(dirs=[(0.45, -0.31, 0.83), (0.10, -0.30, 0.95), (-0.02, -0.34, 0.94)],
                   backs=[(0.80, 0.50, -0.20), (0.90, 0.35, 0.00), (0.90, 0.30, 0.05)]),
    ),
    "Fist": dict(
        cup=0.040, pads=(0.036, 0.016),
        fingers={"Index": (86, 100, 58, -1.0, -6), "Middle": (89, 102, 58, 0.0, -2),
                 "Ring": (91, 102, 58, 1.0, 2), "Little": (94, 100, 56, 3.0, 7)},
        thumb=dict(dirs=[(0.22, -0.80, 0.56), (-0.40, -0.45, 0.80), (-0.90, 0.00, 0.43)],
                   backs=[(0.90, 0.10, -0.30), (0.30, -0.90, -0.10), (0.00, -1.00, 0.10)]),
    ),
    "Grip": dict(
        # thumb wraps the back (wrist side) of the handle: MCP at ~268 deg, IP ~220, tip ~180 around the axis
        cup=0.030, pads=(0.032, 0.014),
        fingers={"Index": (0, 0, 0, 1.0, -4), "Middle": (0, 0, 0, 0.0, -1),
                 "Ring": (0, 0, 0, -1.0, 2), "Little": (0, 0, 0, -2.5, 5)},
        thumb=dict(dirs=[(0.321, -0.698, 0.642), (-0.05, -0.81, 0.585), (-0.05, -0.60, 0.79)],
                   backs=[(0.50, 0.10, -0.80), (0.30, -0.44, -0.90), (0.30, -0.94, -0.34)]),
        handle=dict(centre=(0.0, -0.235, 0.510), tilt=10.0, radius=0.150),
    ),
}


def finger_base(name, mcp, pose):
    x, y, z = mcp
    y -= pose["cup"] * (x / 0.17) ** 2
    _, _, _, splay, roll = pose["fingers"][name]
    return V((x, y, z)), rot("Y", splay) @ rot("Z", roll)


def dist_to_line(p, a, d):
    v = p - a
    return (v - d * v.dot(d)).length


def seg_clearance(chain, s, rfn, H, D, R):
    worst = 1e9
    a, b = chain.p[s], chain.p[s + 1]
    for i in range(9):
        t = i / 8.0
        worst = min(worst, dist_to_line(a.lerp(b, t), H, D) - R - rfn(chain.u[s] + t * chain.L[s]))
    return worst


def close_on_handle(make_chain, start, ratios, maxes, H, D, R, rfn, tol=0.008, step=0.5):
    """Underactuated grasp: all joints close together; a segment touching the handle freezes the joints
    that drive it, the rest keep curling until they touch too (or reach their limits)."""
    ang = list(start)
    active = [True] * len(ang)
    for _ in range(1500):
        if not any(active):
            break
        trial = [min(m, a + step * r) if act else a for a, r, act, m in zip(ang, ratios, active, maxes)]
        ch = make_chain(trial)
        hit = None
        for s in range(len(trial)):
            if seg_clearance(ch, s, rfn, H, D, R) < -tol:
                hit = s
                break
        if hit is None:
            ang = trial
            active = [act and a < m - 1e-6 for act, a, m in zip(active, ang, maxes)]
        else:
            for j in range(hit + 1):
                active[j] = False
    return ang


def solve_pose(pose_name):
    """-> (dict name -> Chain for the four fingers and 'Thumb', info)."""
    pose = POSES[pose_name]
    chains, info = {}, {}
    handle = pose.get("handle")
    if handle:
        H = V(handle["centre"])
        t = math.radians(handle["tilt"])
        D = V((math.cos(t), 0.0, math.sin(t))).normalized()
        info["handle"] = (H, D, handle["radius"])
    for name, mcp, L, w, d in FINGERS:
        p0, f0 = finger_base(name, mcp, pose)
        angles = pose["fingers"][name][:3]
        if handle:
            rg, rs = finger_prof(w, d, L, LEATHER), finger_prof(w, d, L)
            rim = L[0] * 0.56

            def rfn(u, rg=rg, rs=rs, rim=rim):
                v = rg(u) if u < rim else rs(u)
                return 0.5 * (v[0] + v[3])

            def make(a, p0=p0, f0=f0, L=L):
                return Chain.fk(p0, f0, L, a)
            angles = close_on_handle(make, (8.0, 6.0, 4.0), (1.0, 0.95, 0.7), (92.0, 108.0, 80.0),
                                     info["handle"][0], info["handle"][1], info["handle"][2], rfn)
        chains[name] = Chain.fk(p0, f0, L, angles)
    t = pose["thumb"]
    chains["Thumb"] = Chain.from_dirs(THUMB["base"], t["dirs"], t["backs"], THUMB["L"])
    info["angles"] = {k: [round(a, 1) for a in c.ang] for k, c in chains.items()}
    # diagnostics: thumb clearance against the fingers (+ handle) - negative = interpenetration
    tg = thumb_prof(THUMB["w"], THUMB["d"], THUMB["L"])
    th = chains["Thumb"]
    diag = []
    for name, mcp, L, w, d in FINGERS[:3]:
        fp = finger_prof(w, d, L)
        c = chains[name]
        worst = 1e9
        for s1 in (1, 2):
            for s2 in range(3):
                r1 = tg(th.u[s1] + th.L[s1] * 0.5)
                r2 = fp(c.u[s2] + c.L[s2] * 0.5)
                dd = seg_seg_dist(th.p[s1], th.p[s1 + 1], c.p[s2], c.p[s2 + 1])
                worst = min(worst, dd - 0.5 * (r1[0] + r1[3]) - 0.5 * (r2[0] + r2[2]))
        diag.append("%s %.3f" % (name, worst))
    if handle:
        H, D, R = info["handle"]
        for s in range(3):
            def rft(u):
                v = tg(u)
                return 0.5 * (v[0] + v[3])
            diag.append("handle[%d] %.3f" % (s, seg_clearance(th, s, rft, H, D, R)))
    info["thumb_diag"] = ", ".join(diag)
    return chains, info


# ------------------------------------------------------------------------------------------------
# Hand construction
# ------------------------------------------------------------------------------------------------
def palm_pads(a, z, thenar, hypo):
    """Thenar (thumb-side heel) and hypothenar (little-finger heel) pads on the palm side of the glove.
    a = ring angle (0 = thumb side, +90 = back of hand, -90 = palm)."""
    def bump(a0, aw, z0, zw, amp):
        da = math.atan2(math.sin(a - a0), math.cos(a - a0))
        return amp * math.exp(-(da / aw) ** 2) * math.exp(-((z - z0) / zw) ** 2)
    return (bump(math.radians(-36), 0.60, 0.25, 0.13, thenar) +
            bump(math.radians(-146), 0.50, 0.22, 0.12, hypo))


def build_palm(name, cup, thenar=0.030, hypo=0.014):
    rings = []
    X, Y = V((1, 0, 0)), V((0, 1, 0))
    # cuff opening: inner return (hidden), rolled rim, then the outer shell up to the knuckles
    w0 = FOREARM_SKIN[-1]
    inner = (w0[1] + 0.010, w0[1] + 0.010, w0[2] + 0.010, w0[3] + 0.010)
    o = PALM[0]
    outer = (o[1] + 0.010, o[2] + 0.010, o[3] + 0.010, o[4] + 0.010)
    rings.append(ring_pts(V((0, 0, 0.030)), X, Y, *inner, PALM_SEG))
    rings.append(ring_pts(V((0, 0, -0.032)), X, Y, *inner, PALM_SEG))
    rings.append(ring_pts(V((0, 0, -0.045)), X, Y, *[lerp(i, q, 0.55) for i, q in zip(inner, outer)], PALM_SEG))
    rings.append(ring_pts(V((0, 0, -0.030)), X, Y, *outer, PALM_SEG))
    for z in (-0.010, 0.150, 0.250, 0.350, 0.450, 0.530, PALM_END):
        rxp, rxn, ryp, ryn, cy = interp_table(PALM, max(z, 0.0))
        bl = smoothstep(0.15, 0.55, z)
        pts = ring_pts(V((0, cy, z)), X, Y, rxp, rxn, ryp, ryn, PALM_SEG, ex_d=PALM_EXD, ex_p=PALM_EXP,
                       radial=lambda a, z=z: palm_pads(a, z, thenar, hypo))
        for p in pts:   # transverse arch: the sides of the palm curl toward the palm side
            p.y -= cup * (p.x / 0.25) ** 2 * bl
        rings.append(pts)
    # low rounded cap over the knuckle line (kept short so flexed knuckles stay on top; stays wide so the
    # index / little finger sleeves meet the palm edge without a notch)
    rxp, rxn, ryp, ryn, cy = PALM[-1][1:]
    for dz, sx, sy in ((0.028, 0.94, 0.84), (0.046, 0.74, 0.52)):
        pts = ring_pts(V((0, cy, PALM_END + dz)), X, Y, rxp * sx, rxn * sx, ryp * sy, ryn * sy, PALM_SEG,
                       ex_d=PALM_EXD, ex_p=PALM_EXP)
        for p in pts:
            p.y -= cup * (p.x / 0.25) ** 2
        rings.append(pts)
    return loft(name, rings, start="flat", end=V((0, cy, PALM_END + 0.054)))


def glove_sleeve(name, chain, prof, n, rim_u, st_pre, bulge=0.45, bury=0.84):
    """Leather sleeve over a proximal phalanx: a tapered start buried in the palm, the knuckle bend, and a
    rolled hem whose flat end face shows the leather thickness around the bare finger. Rings are rotated
    half a segment so a knuckle crest falls on an edge (rounded) instead of a single vertex (pointy)."""
    phase = math.pi / 2 + math.pi / n
    rings = tube_rings(chain, st_pre, prof, n, bulge=bulge, crease=0.3, phase=phase)
    c0 = sum(rings[0], V()) / len(rings[0])
    for p in rings[0]:   # taper the buried start so it can't graze the palm's rounded edges
        p.xyz = c0 + (p - c0) * bury
    for du, add in ((-0.012, 0.006), (0.0, -0.003)):
        pos, F = chain.at(rim_u + du)
        rxp, rxn, ryp, ryn = prof(rim_u + du)
        rings.append(ring_pts(pos, F.col[0], F.col[1], rxp + add, rxn + add, ryp + add, ryn + add, n, phase=phase))
    return loft(name, rings, start="flat", end="flat")


def finger_skin(name, chain, prof, n, start_u, joints, pad_shift=0.22):
    """Bare finger from inside the glove hem to the tip (the last joint ring opens the rounded tip)."""
    st = [("u", start_u)]
    for k in joints:
        r = prof(chain.u[k])
        dk = joint_delta(chain, k, 0.5 * (r[0] + r[2]))
        st += [("u", chain.u[k] - dk), ("j", k), ("u", chain.u[k] + dk)]
    rings = tube_rings(chain, st, prof, n, bulge=0.45, crease=0.25)
    tr, pole = tip_cap(chain, st[-1][1], chain.u[-1], prof, n, pad_shift=pad_shift)
    return loft(name, rings + tr, start="flat", end=pole)


def build_strap(name):
    """Wrist strap band around the glove cuff (closed band, inner side buried in the glove)."""
    rings = []
    for z, add in ((0.040, -0.012), (0.044, 0.011), (0.126, 0.011), (0.130, -0.012)):
        rxp, rxn, ryp, ryn, cy = interp_table(PALM, z)
        rings.append(ring_pts(V((0, cy, z)), V((1, 0, 0)), V((0, 1, 0)), rxp + add, rxn + add, ryp + add,
                              ryn + add, STRAP_SEG, ex_d=PALM_EXD, ex_p=PALM_EXP))
    return loft(name, rings, closed=True)


def build_tab_and_snap(name):
    """Strap tab on the back of the wrist (offset to the thumb side) and its press stud."""
    rxp, rxn, ryp, ryn, cy = interp_table(PALM, 0.085)
    top = cy + ryp + 0.011
    tab = ls.cube(name + "_tab", size=(0.15, 0.030, 0.098), loc=(0.055, top + 0.004, 0.085))
    ls.bevel(tab, width=0.008, segments=1, angle_deg=30)
    snap = ls.cylinder(name + "_snap", radius=0.028, radius_top=0.022, depth=0.026, segments=8,
                       loc=(0.085, top + 0.012, 0.085), rot=(-math.pi / 2, 0, 0))
    return tab, snap


def build_hand(name, pose_name, side):
    chains, info = solve_pose(pose_name)
    pose = POSES[pose_name]
    glove, skin = [], []
    glove.append(build_palm(name + "_palm", pose["cup"], *pose["pads"]))
    for fname, mcp, L, w, d in FINGERS:
        ch = chains[fname]
        n = SKIN_SEG_SMALL if fname == "Little" else SKIN_SEG
        rim_u = L[0] * 0.56
        gp = finger_prof(w, d, L, LEATHER)
        r0 = gp(0.0)
        d0 = joint_delta(ch, 0, 0.5 * (r0[0] + r0[2]))
        if d0 >= 0.07:   # deep knuckle bend (fist): filleted bend
            st = [("u", -d0 - 0.035), ("u", -d0), ("f", (0, d0, 2)), ("u", d0)]
        else:
            st = [("u", min(-0.10, -d0 - 0.03)), ("u", -d0), ("j", 0), ("u", d0)]
        glove.append(glove_sleeve(name + "_gs" + fname, ch, gp, GLOVE_SEG, rim_u, st))
        skin.append(finger_skin(name + "_sk" + fname, ch, finger_prof(w, d, L), n, rim_u - 0.06, (1, 2)))
    th = chains["Thumb"]
    L = THUMB["L"]
    rim_u = L[0] + L[1] * 0.32
    tg = thumb_prof(THUMB["w"], THUMB["d"], L, LEATHER)
    r1 = tg(L[0])
    d1 = joint_delta(th, 1, 0.5 * (r1[0] + r1[2]))
    st = [("u", -0.08), ("u", L[0] * 0.5), ("u", L[0] - d1), ("j", 1), ("u", L[0] + d1)]
    glove.append(glove_sleeve(name + "_gsThumb", th, tg, THUMB_GLOVE_SEG, rim_u, st, bulge=0.8))
    skin.append(finger_skin(name + "_skThumb", th, thumb_prof(THUMB["w"], THUMB["d"], L), SKIN_SEG, rim_u - 0.06,
                            (2,), pad_shift=0.18))
    glove.append(build_strap(name + "_strap"))
    tab, snap = build_tab_and_snap(name)
    glove.append(tab)

    # the thumb sleeve leaves the palm at a grazing angle (thenar): boolean-union it into the palm so it
    # blends cleanly; finger sleeves, strap and tab meet the palm steeply and stay separate shells (cheaper)
    palm, finger_sleeves, thumb_sleeve, strap_tab = glove[0], glove[1:5], glove[5], glove[6:]
    shell = union_all(palm, [thumb_sleeve], name + "_GloveShell")
    glove_obj = ls.join([shell] + finger_sleeves + strap_tab, name + "_GloveMesh")
    skin_obj = ls.join(skin, name + "_SkinMesh")
    snap_obj = ls.join([snap], name + "_SnapMesh")
    if side < 0:
        for o in (glove_obj, skin_obj, snap_obj):
            mirror_x(o)
    return glove_obj, skin_obj, snap_obj, chains, info


# ------------------------------------------------------------------------------------------------
# Sleeves (fabric folds)
# ------------------------------------------------------------------------------------------------
def make_folds(spec):
    """spec: list of (z, angle_deg, amplitude, width, tilt, arc_power)."""
    return [dict(z=z, th=math.radians(a), amp=amp, w=w, tilt=tilt, arc=arc) for z, a, amp, w, tilt, arc in spec]


def fold_disp(folds, theta, z):
    d = 0.0
    for f in folds:
        zc = f["z"] + f["tilt"] * math.sin(theta - f["th"])
        ang = (0.5 + 0.5 * math.cos(theta - f["th"])) ** f["arc"]
        d += f["amp"] * math.exp(-((z - zc) / f["w"]) ** 2) * ang
    return d


def build_upper_arm(name):
    n = 16
    folds = make_folds([
        # inner-elbow compression folds (-Y = 270 deg): stacked, alternating tilt
        (1.46, 262, 0.040, 0.050, 0.08, 1.2), (1.60, 282, 0.046, 0.048, -0.09, 1.1),
        (1.74, 255, 0.040, 0.046, 0.07, 1.2), (1.53, 300, -0.020, 0.040, 0.03, 1.8),
        (1.67, 235, -0.018, 0.040, -0.03, 1.8),
        # spiral drape folds around the upper arm
        (0.46, 30, 0.030, 0.080, 0.22, 1.0), (0.80, 150, 0.032, 0.075, -0.24, 1.0),
        (1.10, 60, 0.030, 0.070, 0.20, 1.1), (1.30, 205, 0.026, 0.065, -0.16, 1.2),
        (0.24, 250, 0.020, 0.080, 0.12, 1.0), (0.64, 300, -0.016, 0.070, 0.15, 1.4),
        # tension folds radiating from the elbow point (+Y)
        (1.70, 90, 0.020, 0.055, 0.14, 2.2), (1.58, 115, 0.018, 0.055, -0.14, 2.2),
    ])

    def base_r(z):
        # half width (x), back (+y), front (-y): deltoid swell near the shoulder, taper to the elbow
        return interp_table([(0.0, 0.300, 0.300, 0.300), (0.22, 0.308, 0.306, 0.310), (0.55, 0.296, 0.300, 0.300),
                             (1.00, 0.280, 0.290, 0.282), (1.45, 0.264, 0.272, 0.268), (1.90, 0.250, 0.252, 0.252)], z)

    rings = []
    zs = [0.0, 0.13, 0.30, 0.47, 0.64, 0.81, 0.97, 1.12, 1.25, 1.36, 1.44, 1.51, 1.58, 1.64, 1.70, 1.76, 1.82,
          1.90]
    rx, ryb, ryf = base_r(0.0)
    for z, sc in ((-0.040, 0.55), (-0.022, 0.86)):   # shoulder end: a low dome that stays above z = -0.05
        rings.append(ring_pts(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), rx * sc, rx * sc, ryb * sc, ryf * sc, n))
    for z in zs:
        rx, ryb, ryf = base_r(z)
        fade = smoothstep(0.0, 0.14, z) * (1.0 - smoothstep(1.85, 1.9, z))
        rings.append(ring_pts(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), rx, rx, ryb, ryf, n,
                              radial=lambda a, z=z, fade=fade: fold_disp(folds, a, z) * fade))
    r = 0.252   # elbow ball, centred on the elbow pivot
    for deg in (30, 56, 78):
        t = math.radians(deg)
        rings.append(ring_pts(V((0, 0, UPPER_LEN + r * math.sin(t))), V((1, 0, 0)), V((0, 1, 0)),
                              r * math.cos(t), r * math.cos(t), r * math.cos(t), r * math.cos(t), n))
    return loft(name, rings, start=V((0, 0, -0.046)), end=V((0, 0, UPPER_LEN + r)))


def build_forearm(name):
    n_sl, n_sk, n_cf = 14, 12, 12
    folds = make_folds([
        # bunching above the rolled cuff: three chunky rolls of fabric with valleys between
        (0.76, 35, 0.040, 0.045, 0.07, 0.9), (0.86, 205, 0.044, 0.042, -0.07, 0.9),
        (0.96, 110, 0.036, 0.040, 0.06, 1.0), (0.81, 290, -0.016, 0.035, 0.0, 1.6),
        (0.91, 20, -0.014, 0.035, 0.0, 1.6),
        # elbow side
        (0.12, 270, 0.028, 0.06, 0.08, 1.3), (0.30, 80, 0.024, 0.075, -0.14, 1.1),
        (0.48, 185, 0.022, 0.08, 0.16, 1.0), (0.62, 330, 0.018, 0.07, -0.12, 1.2),
    ])

    def sl_r(z):
        return interp_table([(-0.04, 0.236, 0.236), (0.10, 0.248, 0.246), (0.36, 0.258, 0.250),
                             (0.62, 0.246, 0.234), (0.86, 0.234, 0.218), (1.06, 0.226, 0.208)], z)

    rings = []
    for z in (-0.040, 0.08, 0.22, 0.36, 0.50, 0.62, 0.71, 0.76, 0.81, 0.86, 0.91, 0.96, 1.01, 1.06):
        rx, ry = sl_r(z)
        fade = smoothstep(-0.04, 0.08, z)
        rings.append(ring_pts(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), rx, rx, ry, ry, n_sl,
                              radial=lambda a, z=z, fade=fade: fold_disp(folds, a, z) * fade))
    sleeve = loft(name + "_sleeve", rings, start="flat", end="flat")

    # rolled cuff: two rolls, slightly tilted and uneven (closed band)
    def cuff_ring(z, add, wob):
        rx, ryb, ryp = interp_table(FOREARM_SKIN, z)
        return ring_pts(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), rx + add, rx + add, ryb + add, ryp + add, n_cf,
                        radial=lambda a: wob * (math.sin(2 * a + 0.7) * 0.6 + math.sin(3 * a + 2.1) * 0.4))
    tilt = 0.020
    cuff_rings = []
    for z, add, wob in ((0.985, -0.012, 0.0), (0.996, 0.034, 0.005), (1.036, 0.062, 0.007), (1.080, 0.048, 0.006),
                        (1.122, 0.062, 0.007), (1.168, 0.040, 0.005), (1.192, -0.012, 0.0)):
        r = cuff_ring(z, add, wob)
        for p in r:
            p.z += tilt * math.sin(math.atan2(p.y, p.x) - 0.6)
        cuff_rings.append(r)
    cuff = loft(name + "_cuff", cuff_rings, closed=True)

    # bare forearm skin from inside the cuff to the wrist, rounded end tucked into the glove cuff
    def ulnar_bump(a, z):
        # ulnar head: back / little-finger side just above the wrist
        da = math.atan2(math.sin(a - math.radians(132)), math.cos(a - math.radians(132)))
        return 0.012 * math.exp(-(da / 0.45) ** 2) * math.exp(-((z - 1.60) / 0.05) ** 2)
    skin_rings = []
    for z in (0.96, 1.18, 1.34, 1.48, 1.58, 1.66, 1.72):
        rx, ryb, ryp = interp_table(FOREARM_SKIN, min(z, 1.70))
        skin_rings.append(ring_pts(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), rx, rx, ryb, ryp, n_sk,
                                   radial=lambda a, z=z: ulnar_bump(a, z)))
    rx, ryb, ryp = FOREARM_SKIN[-1][1:]
    for z, sc in ((1.778, 0.90), (1.818, 0.70), (1.844, 0.40)):
        skin_rings.append(ring_pts(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), rx * sc, rx * sc, ryb * sc, ryp * sc,
                                   n_sk))
    skin = loft(name + "_skin", skin_rings, start="flat", end=V((0, 0, 1.853)))
    return sleeve, cuff, skin


# ------------------------------------------------------------------------------------------------
# Assets
# ------------------------------------------------------------------------------------------------
lib = ls.Library("Arms")
BUILT = {}
HAND_INFO = {}

AXIS_NOTE = ("Bone axis = Blender +Z (Roblox +Y, the part UpVector), proximal -> distal; pivot (origin) at the {pivot}. "
             "Blender +Y (Roblox -Z, LookVector) = back of the arm/hand; -Y = palm / inner elbow; "
             "thumb side = {thumb}. ")


def side_info(side):
    return ("Right", "+X (Roblox +X)") if side > 0 else ("Left", "-X (Roblox -X); exact mirror of the R_ piece")


def add_upper_arm(side):
    nm = ("R_" if side > 0 else "L_") + "UpperArm"
    s, thumb = side_info(side)
    notes = AXIS_NOTE.format(pivot="SHOULDER", thumb=thumb) + (
        "Sleeve from the shoulder (z=0) to the elbow (z={e}); the rounded end past z={e} is the elbow ball that "
        "covers the joint when the forearm bends (bend the forearm toward -Y). Attachments: Shoulder (origin), "
        "Elbow (z={e}). collide=False, castShadow=False.").format(e=ws(UPPER_LEN))
    root = lib.begin(nm, kind="ViewmodelArm", tags=["Viewmodel", s, "UpperArm"], notes=notes)
    sl = build_upper_arm(nm + "_sl")
    if side < 0:
        mirror_x(sl)
    lib.add(root, sl, "Sleeve", collide=False, cast_shadow=False, smooth_angle=60)
    lib.attach(root, "Shoulder", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "Elbow", (0, 0, UPPER_LEN), look=(0, 0, 1), up=(0, 1, 0))
    lib.finish(root)
    BUILT[nm] = root


def add_forearm(side):
    nm = ("R_" if side > 0 else "L_") + "Forearm"
    s, thumb = side_info(side)
    notes = AXIS_NOTE.format(pivot="ELBOW", thumb=thumb) + (
        "Sleeve from the elbow (z=0) to a rolled cuff (z~{c0}-{c1}), bare skin to the wrist (z={w}); the skin "
        "continues ~{t} past the wrist pivot and hides inside the glove cuff of the hand. Attachments: Elbow "
        "(origin), Wrist (z={w}). Skin can be recoloured at runtime to the avatar skin tone. collide=False, "
        "castShadow=False.").format(c0=ws(1.0), c1=ws(1.2), w=ws(FORE_LEN), t=ws(0.15))
    root = lib.begin(nm, kind="ViewmodelArm", tags=["Viewmodel", s, "Forearm"], notes=notes)
    sleeve, cuff, skin = build_forearm(nm)
    for o in (sleeve, cuff, skin):
        if side < 0:
            mirror_x(o)
    lib.add(root, sleeve, "Sleeve", collide=False, cast_shadow=False, smooth_angle=60)
    lib.add(root, cuff, "Sleeve", rgb=(76, 80, 84), collide=False, cast_shadow=False, smooth_angle=60)
    lib.add(root, skin, "Skin", collide=False, cast_shadow=False, smooth_angle=65)
    lib.attach(root, "Elbow", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
    lib.attach(root, "Wrist", (0, 0, FORE_LEN), look=(0, 0, 1), up=(0, 1, 0))
    lib.finish(root)
    BUILT[nm] = root


HAND_NOTES = {
    "Grip": "Hand closed around a " + ws(0.3) + "-stud cylindrical handle (power grip; the Items handles are "
            "0.12-0.17 across). Attachment Grip = centre of the fist on "
            "the handle axis: look = handle axis toward the thumb/index side (where a blade-up weapon exits), "
            "up = toward the knuckles/fingers (blade edge direction). Weld weapons so their handle axis runs "
            "along Grip.look.",
    "Open": "Relaxed open hand (slight natural curl). Attachment Palm = centre of the palm surface, look = out of "
            "the palm (-Y), up = toward the fingers.",
    "Fist": "Punching fist, thumb wrapped over the index/middle fingers. Attachment Knuckles = front of the "
            "fist on the striking knuckles, look = punch direction (+Z), up = back of the hand.",
}


def add_hand(pose_name, side):
    nm = ("R_" if side > 0 else "L_") + "Hand" + pose_name
    s, thumb = side_info(side)
    notes = AXIS_NOTE.format(pivot="WRIST", thumb=thumb) + HAND_NOTES[pose_name] + (
        " Fingerless leather glove (Glove) with bare fingers (Skin, can be recoloured to the avatar skin tone) "
        "and a brass press stud on the wrist strap. The glove cuff starts at the wrist pivot and sleeves the "
        "forearm's wrist end. Attachment Wrist (origin). collide=False, castShadow=False.")
    root = lib.begin(nm, kind="ViewmodelHand", tags=["Viewmodel", s, "Hand", pose_name], notes=notes)
    glove, skin, snap, chains, info = build_hand(nm, pose_name, side)
    lib.add(root, glove, "Glove", collide=False, cast_shadow=False, smooth_angle=65)
    lib.add(root, skin, "Skin", collide=False, cast_shadow=False, smooth_angle=65)
    lib.add(root, snap, "Brass", collide=False, cast_shadow=False, smooth_angle=45)
    lib.attach(root, "Wrist", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
    if pose_name == "Grip":
        H, D, R = info["handle"]
        ts = []
        for fname, *_ in FINGERS:   # centre of the fist along the handle (finger proximal phalanges)
            c = chains[fname]
            ts.append((c.p[0].lerp(c.p[1], 0.5) - H).dot(D))
        g = H + D * (sum(ts) / len(ts))
        up = (V((0, 0, 1)) - D * D.z).normalized()
        lib.attach(root, "Grip", mx(g, side), look=mx(D, side), up=mx(up, side))
        info["grip"] = (mx(g, side), mx(D, side), R)
    elif pose_name == "Open":
        z = 0.36   # centre of the palm, on the glove's palm surface
        rxp, rxn, ryp, ryn, cy = interp_table(PALM, z)
        lib.attach(root, "Palm", mx((0.0, cy - ryn, z), side), look=(0, -1, 0), up=(0, 0, 1))
        info["palm"] = (0.0, round(cy - ryn, 3), z)
    elif pose_name == "Fist":
        # striking face: front (back-of-finger side) of the index + middle proximal phalanges, punch along +Z
        pts = []
        for fname in ("Index", "Middle"):
            c = chains[fname]
            pts.append(c.p[0].lerp(c.p[1], 0.30) + c.f[1].col[1] * 0.078)
        kn = (pts[0] + pts[1]) * 0.5
        lib.attach(root, "Knuckles", mx(kn, side), look=(0, 0, 1), up=(0, 1, 0))
        info["knuckles"] = tuple(round(v, 3) for v in kn)
    lib.finish(root)
    BUILT[nm] = root
    HAND_INFO[nm] = info
    print("POSE %s %s | thumb clearance: %s | attach %s" % (
        nm, info["angles"], info["thumb_diag"],
        {k: info[k] for k in ("grip", "palm", "knuckles") if k in info}))


for side in (1, -1):
    add_upper_arm(side)
    add_forearm(side)
    add_hand("Grip", side)
    add_hand("Open", side)
    add_hand("Fist", side)

for e in lib.assets:
    print("TRIS %-14s %5d  %s" % (e["name"], e["tris"], ", ".join("%s=%d" % (p["role"], p["tris"]) for p in e["parts"])))


# ------------------------------------------------------------------------------------------------
# Review renders: assembled first-person views (saved with the previews) and debug close-ups
# ------------------------------------------------------------------------------------------------
def _render(path, visible, cam_matrix, lens=None, angle=None, res=(640, 480), ground_z=None, shadows=True):
    scene, cam, ground = lib._setup_preview_scene()
    # Workbench stencil shadows streak across the far ground in the assembled views; the pieces are
    # castShadow=False in game anyway, so those reference renders go without them
    scene.display.shading.show_shadows = shadows
    scene.render.resolution_x, scene.render.resolution_y = res
    for obj in scene.objects:
        if obj in (cam, ground):
            continue
        obj.hide_render = obj not in visible
    old_angle = cam.data.angle
    if angle is not None:
        cam.data.angle = angle
    cam.matrix_world = cam_matrix
    old_ground = ground.location.copy()
    if ground_z is not None:
        ground.location = (0, 0, ground_z)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for obj in scene.objects:
        obj.hide_render = False
    cam.data.angle = old_angle
    ground.location = old_ground
    scene.render.resolution_x, scene.render.resolution_y = 640, 480
    return path


def look_matrix(pos, target, up_hint=(0, 0, 1)):
    pos, target = V(pos), V(target)
    fwd = (target - pos).normalized()
    upv = V(up_hint)
    if abs(fwd.dot(upv.normalized())) > 0.98:
        upv = V((0, 1, 0))
    right = fwd.cross(upv).normalized()
    upc = right.cross(fwd).normalized()
    return Matrix(((right.x, upc.x, -fwd.x, pos.x), (right.y, upc.y, -fwd.y, pos.y),
                   (right.z, upc.z, -fwd.z, pos.z), (0, 0, 0, 1)))


def shoot(roots, path, view_dir, margin=1.12, res=(480, 360), extra=(), focus=None):
    visible = set(extra)
    for r in roots:
        visible.add(r)
        visible.update(r.children_recursive)
    meshes = list(focus) if focus else [o for o in visible if o.type == "MESH"]
    lo, hi = ls.world_bounds(meshes)
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 0.3)
    cam = bpy.data.objects["_PreviewCam"]
    dist = radius / math.sin(cam.data.angle / 2) * margin
    pos = center + V(view_dir).normalized() * dist
    return _render(path, visible, look_matrix(pos, center), res=res, ground_z=min(lo.z, 0) - 2.0)


def contact_sheet(paths, out, cols=3):
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        imgs.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(im)
    rows = (len(imgs) + cols - 1) // cols
    H, W = imgs[0].shape[:2]
    sheet = np.ones((rows * H, cols * W, 4), dtype=np.float32)
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        rr = rows - 1 - r
        sheet[rr * H:(rr + 1) * H, c * W:(c + 1) * W] = a
    img = bpy.data.images.new("sheet", cols * W, rows * H, alpha=True)
    img.pixels = sheet.ravel()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    for p in paths:
        os.remove(p)


def handle_obj(name, g, D, R, length=1.5):
    c = ls.cylinder(name, radius=R, depth=length, segments=20)
    c.data.transform(Matrix.Translation((0, 0, -length / 2)))
    q = V((0, 0, 1)).rotation_difference(V(D))
    c.matrix_world = Matrix.Translation(V(g)) @ q.to_matrix().to_4x4()
    c.data.materials.append(ls.material("Wood"))
    return c


def place_copy(root, M, temps):
    for ch in root.children:
        if ch.type != "MESH":
            continue
        o = bpy.data.objects.new("_tmp_" + ch.name, ch.data)
        bpy.context.scene.collection.objects.link(o)
        o.matrix_world = M
        temps.append(o)


def frame4(pos, z_dir, x_hint):
    z = V(z_dir).normalized()
    x = V(x_hint)
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = V(pos)
    return m


def ik_dirs(S, W, pole):
    """Two-bone IK: upper-arm and forearm directions reaching W from S, elbow toward pole."""
    cv = W - S
    c = min(cv.length, UPPER_LEN + FORE_LEN - 1e-3)
    cd = cv.normalized()
    cos_a = (UPPER_LEN ** 2 + c * c - FORE_LEN ** 2) / (2 * UPPER_LEN * c)
    al = math.acos(max(-1.0, min(1.0, cos_a)))
    p = V(pole)
    p = (p - cd * p.dot(cd)).normalized()
    d1 = cd * math.cos(al) + p * math.sin(al)
    E = S + d1 * UPPER_LEN
    return d1, (S + cd * c - E).normalized()


def arm_pose(side, hand, shoulder, wrist, pole, thumb_dir, hand_tilt=0.0):
    """Place copies of side's UpperArm/Forearm/<hand> as a posed arm (world thumb direction given; the L_
    pieces carry their thumb on local -X). Returns (temps, hand matrix)."""
    pre = "R_" if side > 0 else "L_"
    temps = []
    S = V(shoulder)
    d1, d2 = ik_dirs(S, V(wrist), pole)
    E = S + d1 * UPPER_LEN
    W = E + d2 * FORE_LEN
    # upper arm: elbow flexes toward its -Y
    bend = (d2 - d1 * d2.dot(d1)).normalized()
    y_u = -bend
    x_u = y_u.cross(d1)
    place_copy(BUILT[pre + "UpperArm"], frame4(S, d1, x_u), temps)
    Mf = frame4(E, d2, V(thumb_dir) * side)
    place_copy(BUILT[pre + "Forearm"], Mf, temps)
    Mh = Matrix.Translation(W) @ (Mf.to_3x3() @ rot("Y", hand_tilt * side)).to_4x4()
    place_copy(BUILT[pre + hand], Mh, temps)
    return temps, Mh


def assembled_views(folder):
    """Assembled reference renders (eye at the origin looking +Y, 70 deg vertical FOV like Roblox)."""
    shots = []
    vfov = math.radians(70)
    sR, sL = (0.80, -0.50, -1.00), (-0.80, -0.50, -1.00)
    # 1) right hand gripping a handle (blade-up hold), left hand relaxed
    temps, Mh = arm_pose(1, "HandGrip", sR, (0.55, 2.0, -1.05), (0.4, 0.0, -1.0), (0.0, 0.0, 1.0), hand_tilt=-32)
    g, D, R = HAND_INFO["R_HandGrip"]["grip"]
    temps.append(handle_obj("_tmp_handle", Mh @ V(g), (Mh.to_3x3() @ V(D)), R, length=1.6))
    t2, _ = arm_pose(-1, "HandOpen", sL, (-0.85, 1.65, -1.45), (-0.4, 0.0, -1.0), (0.8, 0.0, 0.6))
    temps += t2
    shots.append(_render(os.path.join(folder, "_assembled_fps.png"), set(temps),
                         look_matrix((0, 0, 0), (0.0, 2.6, -0.95)), angle=vfov, res=(800, 450), ground_z=-6,
                         shadows=False))
    shots.append(_render(os.path.join(folder, "_assembled_side.png"), set(temps),
                         look_matrix((4.6, 0.9, 0.3), (0.1, 0.9, -1.4)), res=(800, 450), ground_z=-6,
                         shadows=False))
    for o in temps:
        bpy.data.objects.remove(o, do_unlink=True)
    # 2) fists up (unarmed guard)
    temps, _ = arm_pose(1, "HandFist", sR, (0.52, 2.15, -1.10), (0.5, 0.0, -1.0), (-0.75, 0.0, 0.65))
    t2, _ = arm_pose(-1, "HandFist", sL, (-0.60, 1.90, -1.20), (-0.5, 0.0, -1.0), (0.75, 0.0, 0.65))
    temps += t2
    shots.append(_render(os.path.join(folder, "_assembled_fists.png"), set(temps),
                         look_matrix((0, 0, 0), (0.0, 2.6, -0.85)), angle=vfov, res=(800, 450), ground_z=-6,
                         shadows=False))
    for o in temps:
        bpy.data.objects.remove(o, do_unlink=True)
    return shots


preview_folder = os.path.join(preview_dir, "Arms")
os.makedirs(preview_folder, exist_ok=True)
assembled = assembled_views(preview_folder)
for p in assembled:
    print("PREVIEW " + p)

if DEBUG_DIR:
    os.makedirs(DEBUG_DIR, exist_ok=True)
    views = [((0, 1, 0.15), "dorsal"), ((0, -1, 0.15), "palm"), ((1, 0, 0.1), "thumb"), ((-1, 0, 0.1), "little"),
             ((0.15, 0.2, 1), "tips"), ((0.7, -0.45, -0.55), "fps")]
    for nm in ("R_HandGrip", "R_HandOpen", "R_HandFist", "L_HandGrip"):
        root = BUILT[nm]
        extra = []
        if nm.endswith("Grip"):
            g, D, R = HAND_INFO[nm]["grip"]
            extra.append(handle_obj("_dbg_handle", g, D, R, length=0.9))
        paths = [shoot([root], os.path.join(DEBUG_DIR, "%s_%s.png" % (nm, tag)), vd, extra=extra) for vd, tag in views]
        contact_sheet(paths, os.path.join(DEBUG_DIR, "sheet_%s.png" % nm))
        for o in extra:
            bpy.data.objects.remove(o, do_unlink=True)
    for nm in ("R_UpperArm", "R_Forearm"):
        root = BUILT[nm]
        paths = [shoot([root], os.path.join(DEBUG_DIR, "%s_%s.png" % (nm, tag)), vd) for vd, tag in views[:4]]
        contact_sheet(paths, os.path.join(DEBUG_DIR, "sheet_%s.png" % nm), cols=4)
    # close-ups: fingertips and knuckles
    paths = []
    for nm, vd in (("R_HandOpen", (0.1, 1, 0.5)), ("R_HandOpen", (0.5, 0.8, -0.2)), ("R_HandGrip", (0.6, -0.6, 0.3)),
                   ("R_HandFist", (0.0, 0.8, 0.6)), ("R_HandFist", (0.6, -0.7, 0.2)), ("R_HandFist", (0.0, 1.0, -0.1))):
        root = BUILT[nm]
        foc = [c for c in root.children if c.name.endswith("_Skin" if ("Open" in nm or "Grip" in nm) else "_Glove")]
        paths.append(shoot([root], os.path.join(DEBUG_DIR, "cu_%s_%d.png" % (nm, len(paths))), vd, margin=1.05,
                           focus=foc))
    contact_sheet(paths, os.path.join(DEBUG_DIR, "sheet_closeups.png"))

def to_world_scale(s):
    """Scale every built piece (mesh data and attachment positions) by s about its pivot and refresh the manifest
    entry (bounds, size). Uniform scaling keeps the L_ mirrors, normals and look/up vectors valid."""
    M = Matrix.Scale(s, 4)
    for e in lib.assets:
        root = e["root"]
        for ch in root.children:
            if ch.type == "MESH":
                ch.data.transform(M)
                ch.data.update()
        for a in e["attachments"].values():
            a["position"] = [round(v * s, 4) for v in a["position"]]
        lib.finish(root)
    for e in lib.assets:
        print("WORLD %-12s size %s  attachments %s" % (e["name"], e["size"],
                                                      {k: a["position"] for k, a in e["attachments"].items()}))


# Per-asset previews are rendered BEFORE the world-scale step: ls_common frames every preview on a bounding radius
# of at least 0.5 studs, which would leave the half-size pieces tiny in frame. The framing is otherwise
# scale-invariant, so these images are exactly what the exported pieces look like.
lib.previews(preview_dir)

to_world_scale(KIT_SCALE)

# Arm pieces are small: a tight row keeps the _overview preview readable (origins are recorded in the manifest)
lib.export(out_dir, None, gap=1.0 * KIT_SCALE)
overview = os.path.join(preview_dir, lib.category, "_overview.png")
lib.render_preview([e["root"] for e in lib.assets], overview, 30, 25, 1.05)
print("PREVIEW " + overview)
