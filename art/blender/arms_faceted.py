"""
arms_faceted.py - LAST STANDING first-person viewmodel arms in the faceted style A ("blockish realistic-ish")
                  -> ArmsFaceted.glb + ArmsFaceted.manifest.json + textures/ArmsFaceted/*.png + review previews

The owner on the first-person hands: "keep the roblox aesthetic and make it look realistic thats all - mainly
shading", and after the block fists, the leather gloves and the avatar arms: "dont make the hands like before js make
them one blockish realistic ish". This kit is bare human hands and forearms with believable proportions and poses,
built from chunky flat-shaded facets in the world's chosen style (docs/design/ArtStyle.md, style A "faceted
realism": rule 2 facets of 0.1-0.4 stud on items and hands, rule 4 painted colour, rule 5 matte, rule 6 values):
  - hands: a palm block of a few broad planes (a convex hull of fixed-normal rings), one convex thenar-and-web wedge
    the thumb grows out of, four separate fingers of three faceted phalanges with knuckles (one band per phalanx),
    a thumb tapering over its two phalanges to a padded tip, a wrist that rolls on the forearm's wrist ball; all
    unioned into ONE closed skin per hand (exact boolean: no shell intersections); no nails;
  - a plain charcoal sleeve on the upper arm and forearm with a clean cuff at the wrist.
Round 2 (art direction, 2026-11-14): relaxed low idle as the first view (fists only while punching), no wrist seam,
the thumb root rebuilt, the grip closed round its handle, the bow view recomposed, broader facets, PBR Neutral view.

Pieces (same names, pivots, chain and attachments as the previous kit, art/blender/arms.py and art/README.md
section 4 "Arms"), each a root EMPTY <Asset> with one MeshPart per surface:
  R_/L_UpperArm  (Sleeve)          R_/L_Forearm (Sleeve, Skin)
  R_/L_HandFist  R_/L_HandGrip  R_/L_HandOpen  R_/L_HandRelaxed (extra idle shape)  (Skin)
FRAME CONVENTION (Blender; Roblox = (x, z, -y)): origin = the proximal joint (shoulder / elbow / wrist), +Z = bone
axis (Roblox +Y, the part's UpVector), +Y = back of the arm / hand (Roblox -Z, LookVector), -Y = palm / inner elbow,
+X = thumb side on R_ pieces; L_ pieces are exact X-mirrors (thumb on -X). Chain: UpperArm.Elbow (0, 0.95, 0) ->
Forearm origin; Forearm.Wrist (0, 0.85, 0) -> hand origin. World scale (no KIT_SCALE step).

Surfaces (style A rules 4-5): every facet carries a flat painted value (per-volume and per-facet jitter, warmer
knuckles and fingertips, lighter palms), multiplied by baked two-radius AO, plus a tiny bevel normal, baked into one
1024 texture set per surface: ArmsFaceted_Skin (all hands + the wrist skin) and ArmsFaceted_Sleeve. Both ColorMaps
are NEUTRAL LIGHT bases: the game sets SurfaceAppearance.Color to the player's skin tone (BodyColors arm colour) and,
if wanted, a sleeve colour; the facet values and AO multiply through any tint. Matte: roughness 0.78-0.95, metal 0.

Run (headless, from the repo root; see art/README.md section 1):
  blender --background --factory-startup --python art/blender/arms_faceted.py -- <out_dir> <preview_dir> [stages]
  stages (comma list, default build,preview):
    build    geometry, painting, UVs, bakes, ArmsFaceted.glb + manifest (+ copy in art/manifests), textures
    preview  review renders from the EXPORTED GLB (+ ItemsReal.glb for the sword, bow, arrow and apple) into
             <preview_dir>/ArmsFaceted/: firstperson_sheet.png, skin_tones.png, pieces.png, compare.png
             (preview:sheet / preview:tones / preview:pieces / preview:compare render just that sheet)
    quick    fast look-dev renders straight from the painted meshes (no bake / export) into the work folder
  env ARMS_FACETED_WORK  work folder (default %TEMP%/ArmsFaceted_build)
  env ARMS_FACETED_ITEMS ItemsReal.glb to hold in the previews (default <out_dir>/ItemsReal.glb)
"""
import json
import math
import os
import shutil
import struct
import sys
import tempfile
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)
import ls_common as ls  # noqa: E402  (frozen shared library: roles and the Roblox axis convention; read only)
import tex_ground as tg  # noqa: E402  (PNG writer, push-pull bleed, colour maths, GPU setup)

T0 = time.time()


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
EXPORTS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")
OUT = os.path.abspath(ARGV[0]) if len(ARGV) > 0 else EXPORTS
PREV_ROOT = (os.path.abspath(ARGV[1]) if len(ARGV) > 1
             else os.path.normpath(os.path.join(HERE, "..", "previews")))
STAGES = set((ARGV[2] if len(ARGV) > 2 else "build,preview").split(","))
CATEGORY = "ArmsFaceted"
PREV = os.path.join(PREV_ROOT, CATEGORY)
TEX = os.path.join(OUT, "textures", CATEGORY)
GLB_ONLY = os.path.join(TEX, "glb_only")
REL_TEX = os.path.relpath(TEX, OUT).replace("\\", "/")
WORK = os.environ.get("ARMS_FACETED_WORK") or os.path.join(tempfile.gettempdir(), "ArmsFaceted_build")
ART = os.path.normpath(os.path.join(HERE, ".."))
REPO_MANIFESTS = os.path.join(ART, "manifests")
HAND_VERSIONS = os.path.join(ART, "previews", "Viewmodel", "HandVersions.jpg")
ITEMS_GLB = os.environ.get("ARMS_FACETED_ITEMS") or os.path.join(OUT, "ItemsReal.glb")
GLB_PATH = os.path.join(OUT, CATEGORY + ".glb")
MANIFEST_PATH = os.path.join(OUT, CATEGORY + ".manifest.json")

TAU = 2.0 * math.pi
HALF_PI = 0.5 * math.pi
V = Vector

UPPER_LEN = 0.95      # shoulder -> elbow (UpperArm.Elbow)
FORE_LEN = 0.85       # elbow -> wrist (Forearm.Wrist)

# Painted bases (sRGB). Both are near-neutral light values: the tint (SurfaceAppearance.Color) gives the hue.
SKIN_BASE = (246, 236, 225)   # neutral light, a touch warm (round 2)
SLEEVE_BASE = (224, 224, 226)
SKIN_TINT_DEFAULT = (234, 184, 146)      # Roblox "Light orange"; the game sets the avatar's arm colour instead
SLEEVE_TINT_DEFAULT = (96, 88, 80)       # charcoal, warm enough that the blue sky fill keeps it grey
SKIN_TONES = [("Light", "Light orange", (234, 184, 146)), ("Medium", "Nougat", (204, 142, 105)),
              ("Dark", "Reddish brown", (105, 64, 40))]
ROUGH = {"Skin": 0.80, "Sleeve": 0.92}
TEX_SIZE = {"Skin": 1024, "Sleeve": 1024}


# =============================================================================================== small maths
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


def frame4(pos, z_dir, x_hint):
    z = V(z_dir).normalized()
    x = V(x_hint)
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = V(pos)
    return m


def look_up_frame(pos, look, up):
    """4x4 frame with z = look, y = up (orthogonalised), x = y cross z (right-handed). Used to align Grip frames."""
    z = V(look).normalized()
    y = V(up)
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = V(pos)
    return m


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


def hash01(i, salt=0):
    x = (int(i) * 2654435761 + (salt * 7919 + 104729)) & 0xFFFFFFFF
    x ^= x >> 16
    x = (x * 0x45D9F3B) & 0xFFFFFFFF
    x ^= x >> 16
    x = (x * 0x45D9F3B) & 0xFFFFFFFF
    x ^= x >> 16
    return (x & 0xFFFFFF) / float(0xFFFFFF)


def s2l(c):
    return tuple(float(v) for v in tg.srgb_to_lin(np.asarray(c, np.float64) / 255.0))


# =============================================================================================== kinematic chain
class Chain:
    """Finger / thumb bones. f[0] is the base frame before joint 0, f[s+1] the frame of the segment from joint s
    to joint s+1 (columns x, y, z; z along the bone, y = back of the finger)."""

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


# =============================================================================================== mesh accumulator
_FID = [0]   # facet ids, unique across every mesh of a run (they survive the boolean union and the triangulation)


class MB:
    """Vertices with painting attributes (dors: +1 back / -1 palm side of their own bone, warm: knuckle weight,
    tip: fingertip weight) and faces with a volume id (one per phalanx / pad / sleeve panel) and a facet id (one per
    modelled face: the triangles of a face are painted as one facet)."""

    def __init__(self):
        self.V, self.D, self.W, self.T = [], [], [], []
        self.F, self.FV, self.FI = [], [], []

    def v(self, co, dors=0.0, warm=0.0, tip=0.0):
        self.V.append((float(co[0]), float(co[1]), float(co[2])))
        self.D.append(float(dors))
        self.W.append(float(warm))
        self.T.append(float(tip))
        return len(self.V) - 1

    def f(self, idx, vol):
        idx = [int(i) for i in idx]
        if len(set(idx)) >= 3:
            _FID[0] += 1
            self.F.append(tuple(idx))
            self.FV.append(int(vol))
            self.FI.append(_FID[0])

    def loft(self, rings, vols, start="flat", end="flat", closed=False):
        """rings: list of (points, dors list, warm, tip); vols: one volume id per band (len(rings) - 1, or
        len(rings) when closed). start / end: "flat" (n-gon cap), a point (pole fan) or None (open)."""
        ids = []
        for pts, dors, warm, tip in rings:
            w = warm if isinstance(warm, (list, tuple)) else [warm] * len(pts)
            ids.append([self.v(p, d, ww, tip) for p, d, ww in zip(pts, dors, w)])
        n = len(ids[0])
        count = len(ids) if closed else len(ids) - 1
        for k in range(count):
            a, b = ids[k], ids[(k + 1) % len(ids)]
            for i in range(n):
                j = (i + 1) % n
                self.f((a[i], a[j], b[j], b[i]), vols[min(k, len(vols) - 1)])
        if closed:
            return

        def cap(rv, where, vol, rings_k):
            if where is None:
                return
            if isinstance(where, str):
                self.f(list(reversed(rv)), vol)
                return
            pts, dors, warm, tip = rings_k
            pv = self.v(where, sum(dors) / len(dors), warm if not isinstance(warm, (list, tuple)) else 0.0, tip)
            for i in range(n):
                j = (i + 1) % n
                self.f((rv[j], rv[i], pv), vol)
        cap(ids[0], start, vols[0], rings[0])
        cap(ids[-1], end, vols[-1], rings[-1])

    def hull(self, points, vol, dors_fn, warm=0.0, warm_fn=None):
        bm = bmesh.new()
        for p in points:
            bm.verts.new(p)
        res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
        drop = list({g for g in res.get("geom_interior", []) + res.get("geom_unused", [])
                     if isinstance(g, bmesh.types.BMVert) and g.is_valid})
        if drop:
            bmesh.ops.delete(bm, geom=drop, context="VERTS")
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:])
        bm.verts.index_update()
        base = {v.index: self.v(v.co, dors_fn(v.co), warm_fn(v.co) if warm_fn else warm, 0.0) for v in bm.verts}
        for f in bm.faces:
            self.f([base[v.index] for v in f.verts], vol)
        bm.free()

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.V, [], self.F)
        me.update(calc_edges=True)
        a = me.attributes.new("vol", "INT", "FACE")
        a.data.foreach_set("value", np.array(self.FV, np.int32))
        a = me.attributes.new("fid", "INT", "FACE")
        a.data.foreach_set("value", np.array(self.FI, np.int32))
        for nm, vals in (("dors", self.D), ("warm", self.W), ("tip", self.T)):
            a = me.attributes.new(nm, "FLOAT", "POINT")
            a.data.foreach_set("value", np.array(vals, np.float32))
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        finish_mesh(obj)
        return obj


def finish_mesh(obj):
    """Merge exact duplicates, triangulate (the bake, the tangents and the GLB then see the same triangles), fix the
    winding per closed shell and flat-shade every facet."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges[:])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY",
                          ngon_method="BEAUTY")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = False
    obj.data.update()


# =============================================================================================== cross sections
def section(center, fx, fy, prof, n, ex_t=2.6, ex_b=2.2, radial=None):
    """Closed ring of n points with a flat face centred on top (+fy). prof = (+x, -x, +y, -y) half sizes; ex_t /
    ex_b: superellipse exponents of the top / bottom halves (2 = ellipse, larger = boxier). radial(angle, x, y) ->
    outward offset. Returns (points, dors) with dors = sin(angle) (+1 top, -1 bottom). Used by the sleeves."""
    wp, wn, dt, db = prof
    pts, dors = [], []
    for i in range(n):
        a = HALF_PI + math.pi / n + TAU * i / n
        c, s = math.cos(a), math.sin(a)
        e = 2.0 / (ex_t if s >= 0 else ex_b)
        x = math.copysign(abs(c) ** e, c) * (wp if c >= 0 else wn)
        y = math.copysign(abs(s) ** e, s) * (dt if s >= 0 else db)
        if radial is not None:
            off = radial(a, x, y)
            ln = math.hypot(x, y)
            if ln > 1e-9:
                x += x / ln * off
                y += y / ln * off
        pts.append(V(center) + fx * x + fy * y)
        dors.append(s)
    return pts, dors


# Skin rings with FIXED face directions. Each face of such a ring keeps its direction from ring to ring, so a band
# between two rings of the same orientation is made of planar trapezoids - one flat facet each, whatever the widths
# do - the carved planes of style A instead of twisted quads that crumple into small triangles.
PALM_NORMALS = (90, 112, 148, 180, 214, 250, 270, 290, 326, 0, 32, 68)   # degrees, CCW from +X (the thumb side)
DIGIT_NORMALS = (90, 150, 210, 270, 330, 30)                               # 6 sides: a flat back and a flat pad
PALM_BOXY = 0.55
DIGIT_BOXY = 0.42


def support(theta, prof, boxy):
    """Support distance in direction theta of a rounded box: quarter ellipses blended toward a rectangle by boxy.
    prof = (+x half width, -x half width, back depth, palm depth[, palm-side centre shift])."""
    wp, wn, dt, db = prof[:4]
    cy = prof[4] if len(prof) > 4 else 0.0
    c, s = math.cos(theta), math.sin(theta)
    a = wp if c >= 0 else wn
    b = dt if s >= 0 else db
    ell = math.hypot(a * c, b * s)
    h = ell + (abs(a * c) + abs(b * s) - ell) * boxy
    if s < 0:
        h += s * cy
    return h


def facet_ring(center, fx, fy, prof, normals, boxy, extra=None):
    """Ring of len(normals) corners: the polygon round the profile whose faces point in fixed directions (degrees,
    CCW from fx in the fx / fy plane). extra(nx, ny) -> extra outward offset of a face (knuckles, creases). Corner j
    lies between faces j and j + 1. Returns (points, dors), dors = the corner's height over the back (+1) or palm
    (-1) depth."""
    th = [math.radians(a) for a in normals]
    N = [(math.cos(t), math.sin(t)) for t in th]
    H = [support(t, prof, boxy) + (extra(*n) if extra else 0.0) for t, n in zip(th, N)]
    m = len(th)
    pts, dors = [], []
    for j in range(m):
        k = (j + 1) % m
        (a1, b1), (a2, b2) = N[j], N[k]
        det = a1 * b2 - a2 * b1
        x = (H[j] * b2 - H[k] * b1) / det
        y = (a1 * H[k] - a2 * H[j]) / det
        pts.append(V(center) + fx * x + fy * y)
        dors.append(max(-1.0, min(1.0, y / (prof[2] if y >= 0 else prof[3]))))
    return pts, dors


# =============================================================================================== hand anatomy
# RIGHT hand, world studs. Hand frame: origin = wrist pivot, +Z toward the fingers, +Y back of the hand, +X thumb.
# Slightly chunky Roblox proportions: fingers ~15% thicker than life, hand ~0.56 long (forearm 0.85).
FINGERS = [
    # name, MCP joint centre (x, y, z), phalanx lengths (prox, mid, dist incl. tip), half width, half depth
    ("Index", (0.103, 0.002, 0.276), (0.118, 0.072, 0.066), 0.0385, 0.0340),
    ("Middle", (0.035, 0.006, 0.286), (0.128, 0.079, 0.069), 0.0395, 0.0350),
    ("Ring", (-0.034, 0.003, 0.277), (0.120, 0.075, 0.067), 0.0375, 0.0330),
    ("Little", (-0.100, -0.005, 0.253), (0.094, 0.057, 0.059), 0.0325, 0.0290),
]
THUMB = dict(base=(0.056, -0.030, 0.046), L=(0.130, 0.090, 0.080), w=0.0415, d=0.0355)

# The wrist ring that every hand and the forearm's wrist skin share at the pivot: the skin runs on without a step.
WRIST_PROF = (0.097, 0.097, 0.059, 0.061, 0.0)
WRIST_ARCS = (0.020, 0.038, 0.052)   # stations of the wrist's rolling arcs either side of the pivot


def wrist_arc_prof(z, inset):
    """The wrist ring shrunk onto arcs centred on the pivot at distance z from it (minus inset): each of the four
    half sizes r becomes sqrt(r^2 - z^2), so the end rolls along itself when the wrist flexes or deviates."""
    wp, wn, dt, db, cy = WRIST_PROF
    f = lambda r: max(0.25 * r, math.sqrt(max(0.0, r * r - z * z))) - inset
    return (f(wp), f(wn), f(dt), f(db), cy)


# Palm stations: z, half width thumb side, half width little side, back depth, palm depth, palm-side centre shift.
# Few stations, so the back and the palm are a handful of broad planes (0.08-0.14 stud).
PALM_ST = [
    (0.000,) + WRIST_PROF,
    (0.080, 0.115, 0.124, 0.061, 0.068, -0.004),   # heel of the hand: the hypothenar widens the little-finger side
    (0.165, 0.130, 0.134, 0.052, 0.062, -0.004),
    (0.238, 0.139, 0.134, 0.040, 0.052, 0.000),    # knuckle line: the MCP heads stand a little proud of it
]
PALM_CAP = [(0.257, 0.94, 0.86, 0.72), (0.273, 0.80, 0.46, 0.38)]   # z, width / back / palm scale
# Thenar and web wedge (add_thenar): the ring round the thumb's MCP (scale of the thumb profile) and its anchors on the
# thumb side of the palm - z, back height (x back depth), side (x half width), palm-side corner (x half width) and an
# inner palm point (x half width). The thumb tube starts inside the wedge at this fraction of the metacarpal.
THENAR_RING = 1.12
THENAR_ANCHORS = [
    (0.010, 0.30, 0.94, 0.70, 0.35),
    (0.075, 0.40, 0.95, 0.72, 0.38),
    (0.140, 0.45, 0.94, 0.68, 0.40),
    (0.205, 0.50, 0.90, 0.55, 0.40),
]
THUMB_TUBE_START = 0.55
JOINT_SPLIT = 40.0   # bends above this get two extra rings (a two-facet knuckle); smaller ones one mitred ring


def finger_prof(w, d, L):
    u1, u2 = L[0], L[0] + L[1]
    u3 = u2 + L[2]
    # u, width, back, palm scale: swollen joints, slimmer shafts, a pad on the last phalanx
    keys = [(-0.045, 0.92, 0.88, 0.92), (0.00, 1.06, 1.04, 1.00), (u1, 1.01, 0.98, 0.95),
            (u2, 0.95, 0.88, 0.92), (u2 + L[2] * 0.5, 0.92, 0.80, 0.98), (u3, 0.86, 0.72, 0.88)]

    def f(u):
        ws, ts, bs = interp_table(keys, u)
        return (w * ws, w * ws, d * ts, d * bs)
    return f


def thumb_prof(w, d, L):
    um, up = L[0], L[0] + L[1]
    ue = up + L[2]
    # a thick first phalanx tapering to a padded tip
    keys = [(0.0, 1.00, 0.95, 1.00), (um, 1.06, 1.02, 1.04), (um + 0.5 * L[1], 1.00, 0.94, 1.00),
            (up, 0.98, 0.90, 0.95), (up + 0.5 * L[2], 0.95, 0.82, 1.04), (ue, 0.86, 0.72, 0.90)]

    def f(u):
        ws, ts, bs = interp_table(keys, u)
        return (w * ws, w * ws, d * ts, d * bs)
    return f


# Poses. Fingers: (mcp, pip, dip flexion deg, splay deg (+ toward the thumb), roll deg); a "wrap" pose solves the
# finger angles round its handle. Thumb: az / el = the metacarpal's direction (az from +Z toward the thumb side,
# el toward the palm), roll = its nail turned from the thumb side toward the back of the hand (+), mcp / ip =
# flexion; "wrap" solves it round the handle onto the fingers. cup: the little-finger side of the palm curls in.
POSES = {
    "Relaxed": dict(   # idle: fingers in an easy cascade, more curl toward the little finger; thumb by the index
        cup=0.008,
        fingers={"Index": (12, 18, 9, 3.0, 0), "Middle": (15, 22, 11, 0.5, 0),
                 "Ring": (19, 27, 13, -2.5, 0), "Little": (23, 32, 15, -6.0, 0)},
        thumb=dict(az=22.0, el=24.0, roll=45.0, mcp=12.0, ip=16.0),
    ),
    "Open": dict(   # relaxed cupped hand that cradles an apple or a bottle on the palm
        cup=0.012,
        fingers={"Index": (22, 28, 14, 5.5, 0), "Middle": (25, 31, 15, 1.0, 0),
                 "Ring": (28, 34, 16, -3.0, 0), "Little": (32, 38, 17, -8.0, 0)},
        thumb=dict(az=40.0, el=26.0, roll=36.0, mcp=12.0, ip=12.0),
    ),
    "Fist": dict(
        cup=0.024,
        fingers={"Index": (86, 106, 66, -1.0, -6), "Middle": (89, 108, 66, 0.0, -2),
                 "Ring": (91, 108, 64, 1.0, 2), "Little": (94, 104, 60, 3.0, 7)},
        thumb=dict(az=21.0, el=53.0, roll=6.0, mcp=44.0, ip=45.0),
    ),
    "Grip": dict(
        cup=0.022,
        fingers={"Index": "wrap", "Middle": "wrap", "Ring": "wrap", "Little": "wrap"},
        splay={"Index": (1.0, -4), "Middle": (0.0, -1), "Ring": (-1.0, 2), "Little": (-2.5, 5)},
        thumb="wrap",
        # the previous kit's handle: 0.15 across, 10 degrees off the X axis, so R_HandGrip.Grip stays where it was;
        # the finger pads may press up to 'press' into it
        handle=dict(centre=(0.0, -0.1175, 0.255), tilt=10.0, radius=0.075, press=0.026),
    ),
}
GRIP_ATTACH = (0.0131, -0.1175, 0.2573)   # previous kit's R_HandGrip.Grip (Blender), on the handle axis


def cup_y(x, cup):
    """The palm cups round a handle: the little-finger side (the mobile 4th and 5th metacarpals) curls palmward."""
    return -cup * (max(0.0, -x) / 0.10) ** 2


def finger_base(mcp, pose, name):
    x, y, z = mcp
    y += cup_y(x, pose["cup"])
    f = pose["fingers"][name]
    splay, roll = pose["splay"][name] if f == "wrap" else f[3:5]
    return V((x, y, z)), rot("Y", splay) @ rot("Z", roll)


def thumb_chain(t):
    """Thumb chain from its pose angles (see POSES)."""
    az, el, roll = (math.radians(t[k]) for k in ("az", "el", "roll"))
    d = V((math.sin(az) * math.cos(el), -math.sin(el), math.cos(az) * math.cos(el)))
    side = V((math.cos(az), 0.0, -math.sin(az)))
    side = (side - d * side.dot(d)).normalized()
    back = Matrix.Rotation(roll, 3, d) @ side
    Fm = frame_from(d, back)
    Fp = Fm @ rot("X", t["mcp"])
    Fd = Fp @ rot("X", t["ip"])
    return Chain(V(THUMB["base"]), [Fm, Fm, Fp, Fd], THUMB["L"])


def dist_to_line(p, a, d):
    v = p - a
    return (v - d * v.dot(d)).length


def wrap_axes(D):
    """Axes across a handle along D: ey toward the back of the hand, ez toward the fingers. Wrap angle psi = 0 at
    the back-of-hand side, 90 at the finger side, 180 on the far side, 270 at the thenar side."""
    ey = V((0.0, 1.0, 0.0))
    ey = (ey - D * ey.dot(D)).normalized()
    return ey, D.cross(ey).normalized()


def unwrapped_psi(points, H, ey, ez):
    out, prev = [], None
    for p in points:
        q = p - H
        a = math.degrees(math.atan2(q.dot(ez), q.dot(ey)))
        if prev is not None:
            while a - prev > 180.0:
                a -= 360.0
            while a - prev < -180.0:
                a += 360.0
        out.append(a)
        prev = a
    return out


def handle_clearance(ch, s, prof, H, D, R, side=3, n=7):
    """Clearance between segment s of a chain (its pad side) and the handle surface (negative = pressed in)."""
    worst = 1e9
    a, b = ch.p[s], ch.p[s + 1]
    for i in range(n):
        t_ = i / (n - 1.0)
        r = prof(ch.u[s] + t_ * ch.L[s])
        worst = min(worst, dist_to_line(a.lerp(b, t_), H, D) - R - r[side])
    return worst


def solve_wrap(p0, f0, L, prof, H, D, R, press):
    """Finger angles that wrap the finger furthest round the handle: the fingertip's wrap angle is maximised over the
    MCP / PIP / DIP flexions, no segment pressing more than 'press' into the handle, the pads hugging it."""
    ey, ez = wrap_axes(D)

    def evaluate(a):
        ch = Chain.fk(p0, f0, L, a)
        cl = [handle_clearance(ch, s, prof, H, D, R) for s in range(3)]
        if min(cl) < -press:
            return None
        tip = ch.p[3] - ch.f[3].col[1] * prof(ch.u[3])[3] * 0.5
        psi = unwrapped_psi(ch.p + [tip], H, ey, ez)[-1]
        gap = max(0.0, cl[1]) + max(0.0, cl[2])
        # the fingertip as far round as it goes, hugging the handle, with a natural PIP >= DIP coupling
        return psi - 250.0 * gap - 0.05 * abs(a[2] - 0.7 * a[1])
    best = None
    for mcp in range(0, 94, 3):
        for pip in range(0, 110, 3):
            for k in (0.55, 0.7, 0.85):
                a = (float(mcp), float(pip), min(80.0, pip * k))
                s = evaluate(a)
                if s is not None and (best is None or s > best[0]):
                    best = (s, a)
    s0, a0 = best
    step = 1.0
    for _ in range(60):   # coordinate refinement
        improved = False
        for j in range(3):
            for dlt in (-step, step):
                a = list(a0)
                a[j] = max(0.0, min((95.0, 110.0, 85.0)[j], a[j] + dlt))
                s = evaluate(a)
                if s is not None and s > s0 + 1e-6:
                    s0, a0, improved = s, tuple(a), True
        if not improved:
            if step < 0.26:
                break
            step *= 0.5
    return a0


def seg_clear_chains(c1, s1, r1, c2, s2, r2):
    return seg_seg_dist(c1.p[s1], c1.p[s1 + 1], c2.p[s2], c2.p[s2 + 1]) - r1 - r2


def solve_grip_thumb(chains, H, D, R, press, start):
    """Grip thumb: wraps round the handle from the thenar side, the other way from the fingers, as far as it goes -
    its pad hugging the handle and then lying over the curled fingers - never pressing more than 'press' into the
    handle or into a finger. Seeded scan, then coordinate refinement."""
    ey, ez = wrap_axes(D)
    tp = thumb_prof(THUMB["w"], THUMB["d"], THUMB["L"])
    fingers = [(chains[f[0]], 0.5 * (f[3] + f[4])) for f in FINGERS]
    r_th = 0.5 * (THUMB["w"] + THUMB["d"])

    def cost(t):
        ch = thumb_chain(t)
        tip = ch.p[3] - ch.f[3].col[1] * THUMB["d"] * 0.35
        psi = unwrapped_psi([ch.p[0], ch.p[1], ch.p[2], ch.p[3], tip], H, ey, ez)[-1]
        c = psi
        hug = []
        for s in range(3):
            cl = handle_clearance(ch, s, tp, H, D, R, side=3)
            if cl < -press:
                c += 4000.0 * (-press - cl)
            fc = 1e9
            if s > 0:
                for fch, fr in fingers:
                    for s2 in range(3):
                        fc = min(fc, seg_clear_chains(ch, s, r_th * 0.92, fch, s2, fr * 0.92))
                if fc < -0.004:
                    c += 4000.0 * (-0.004 - fc)
            hug.append(min(cl, fc))
        # the phalanges rest on the handle or the fingers instead of floating round them
        c += 600.0 * (max(0.0, hug[1] - 0.004) + max(0.0, hug[2] - 0.004))
        # a natural thumb: its joints a little flexed, not a straight stick
        c += 0.5 * max(0.0, 18.0 - t["ip"]) + 0.3 * max(0.0, 12.0 - t["mcp"])
        # the pad faces the handle, not the sky
        q = tip - H
        q = (q - D * q.dot(D)).normalized()
        face = (-ch.f[3].col[1]).dot(-q)
        if face < 0.3:
            c += 60.0 * (0.3 - face)
        return c
    keys = ("az", "el", "roll", "mcp", "ip")
    lo = dict(az=-15.0, el=15.0, roll=-100.0, mcp=0.0, ip=0.0)
    hi = dict(az=60.0, el=85.0, roll=50.0, mcp=75.0, ip=80.0)
    best = (cost(start), dict(start))
    for i in range(6000):   # seeded scan, then coordinate refinement
        t = {k: lo[k] + (hi[k] - lo[k]) * hash01(i * 5 + j, 41) for j, k in enumerate(keys)}
        c = cost(t)
        if c < best[0]:
            best = (c, t)
    c0, t0 = best
    step = 4.0
    for _ in range(300):
        improved = False
        for k in keys:
            for dlt in (-step, step):
                t = dict(t0)
                t[k] = max(lo[k], min(hi[k], t[k] + dlt))
                c = cost(t)
                if c < c0 - 1e-9:
                    c0, t0, improved = c, t, True
        if not improved:
            if step < 0.26:
                break
            step *= 0.5
    return {k: round(v, 2) for k, v in t0.items()}, c0


def solve_pose(pose_name):
    pose = POSES[pose_name]
    chains, info = {}, {}
    handle = pose.get("handle")
    if handle:
        H = V(handle["centre"])
        t = math.radians(handle["tilt"])
        D = V((math.cos(t), 0.0, math.sin(t))).normalized()
        info["handle"] = (H, D, handle["radius"])
    for name, mcp, L, w, d in FINGERS:
        p0, f0 = finger_base(mcp, pose, name)
        spec = pose["fingers"][name]
        if spec == "wrap":
            angles = solve_wrap(p0, f0, L, finger_prof(w, d, L), H, D, handle["radius"], handle["press"])
        else:
            angles = spec[:3]
        chains[name] = Chain.fk(p0, f0, L, angles)
    if pose["thumb"] == "wrap":
        start = dict(az=27.0, el=44.0, roll=-18.0, mcp=30.0, ip=25.0)
        tparams, tcost = solve_grip_thumb(chains, H, D, handle["radius"], handle["press"], start)
        info["thumb_cost"] = round(tcost, 5)
    else:
        tparams = dict(pose["thumb"])
    chains["Thumb"] = thumb_chain(tparams)
    info["thumb"] = tparams
    info["angles"] = {k: [round(a, 1) for a in c.ang] for k, c in chains.items()}
    if handle:
        ey, ez = wrap_axes(D)
        info["tip_psi"] = {k: round(unwrapped_psi(chains[k].p, H, ey, ez)[-1], 1) for k, *_ in FINGERS}
        th = chains["Thumb"]
        info["thumb_psi"] = [round(a, 1) for a in unwrapped_psi(th.p, H, ey, ez)]
    # diagnostics: thumb clearance against the fingers - negative = interpenetration
    th = chains["Thumb"]
    diag = []
    for name, mcp, L, w, d in FINGERS[:3]:
        c = chains[name]
        worst = 1e9
        for s1 in (1, 2):
            for s2 in range(3):
                worst = min(worst, seg_clear_chains(th, s1, 0.5 * (THUMB["w"] + THUMB["d"]), c, s2, 0.5 * (w + d)))
        diag.append("%s %.3f" % (name, worst))
    info["thumb_diag"] = ", ".join(diag)
    return chains, info


# =============================================================================================== hand construction
def joint_delta(chain, k, r, lo=0.010, frac=0.40):
    """Half spacing of the two rings either side of joint k so a deep bend keeps its volume."""
    half = math.radians(chain.ang[k]) * 0.5
    d = max(lo, r * math.tan(half) * 1.05)
    lim = frac * min(chain.L[k - 1] if k > 0 else 1.0, chain.L[k] if k < len(chain.L) else 1.0)
    return min(d, lim)


def joint_stations(chain, prof, joints, u_start):
    """Ring stations along a finger / thumb: ("u", arc length) plain rings and ("j", k) joint rings, with one more
    ring either side of a deep bend. No mid-phalanx rings: each phalanx is one band of long facets."""
    st = [("u", u_start)] if u_start is not None else []
    for k in joints:
        r = prof(chain.u[k])
        uk = chain.u[k]
        if chain.ang[k] > JOINT_SPLIT:
            dk = joint_delta(chain, k, 0.5 * (r[0] + r[2]))
            st += [("u", uk - dk), ("j", k), ("u", uk + dk)]
        else:
            st.append(("j", k))
    return st


def st_u(chain, s):
    return chain.u[s[1]] if s[0] == "j" else s[1]


def digit_rings(chain, stations, prof, bulge=0.9, crease=0.25, joint_warm=1.0):
    """Fixed-normal hexagon rings; a joint ring takes the halfway frame, its outside bulges (knuckle) and its inside
    tucks in (crease); a straight joint still shows a low knuckle on the back."""
    rings = []
    for kind, val in stations:
        if kind == "j":
            k = val
            pos, F = chain.p[k], chain.joint_frame(k)
            r = prof(chain.u[k])
            half = math.radians(chain.ang[k]) * 0.5
            b = chain.bend_out(k)
            rr = 0.5 * (r[2] + r[3])
            lift = (0.009 if k == 0 else 0.0045) * (1.0 - min(1.0, half / 0.35))

            def extra(nx, ny, F=F, b=b, half=half, rr=rr, lift=lift):
                e = lift * max(0.0, ny)
                if b is not None and half > 1e-3:
                    c = (F.col[0] * nx + F.col[1] * ny).dot(b)
                    if c > 0:
                        e += bulge * (1.0 / math.cos(half) - 1.0) * rr * c
                    else:
                        e -= crease * math.sin(half) * rr * (-c) ** 1.2
                return e
            pts, dors = facet_ring(pos, F.col[0], F.col[1], r, DIGIT_NORMALS, DIGIT_BOXY, extra)
            rings.append((pts, dors, [joint_warm * max(0.0, d) for d in dors], 0.0))
        else:
            pos, F = chain.at(val)
            pts, dors = facet_ring(pos, F.col[0], F.col[1], prof(val), DIGIT_NORMALS, DIGIT_BOXY)
            rings.append((pts, dors, 0.0, 0.0))
    return rings


def tip_rings(chain, u_end, prof, pad=0.22):
    """Blocky rounded fingertip: a last full ring, then a smaller end ring pulled toward the pad (the flat end cap)."""
    base = prof(u_end)
    rings = []
    for du, sw, st_, sb, sh, tip in ((0.024, 1.00, 1.00, 1.00, 0.12, 0.5), (0.0, 0.60, 0.40, 0.68, 0.62, 1.0)):
        pos, F = chain.at(u_end - du)
        pos = pos - F.col[1] * base[3] * pad * sh
        pts, dors = facet_ring(pos, F.col[0], F.col[1], (base[0] * sw, base[1] * sw, base[2] * st_, base[3] * sb),
                               DIGIT_NORMALS, DIGIT_BOXY)
        rings.append((pts, dors, 0.0, tip))
    return rings


def band_vols(chain, us, vol0):
    vols = []
    for a, b in zip(us, us[1:]):
        m = 0.5 * (a + b)
        vols.append(vol0 + (0 if m < chain.u[1] else (1 if m < chain.u[2] else 2)))
    return vols


def add_finger(mb, chain, prof, vol0, u_start=-0.045):
    st = joint_stations(chain, prof, (0, 1, 2), u_start)
    u_end = chain.u[-1]
    st = [s for s in st if st_u(chain, s) < u_end - 0.034]
    rings = digit_rings(chain, st, prof) + tip_rings(chain, u_end, prof)
    us = [st_u(chain, s) for s in st] + [u_end - 0.024, u_end]
    mb.loft(rings, band_vols(chain, us, vol0), start="flat", end="flat")


def add_thumb(mb, chain, vol0):
    """The thumb's two phalanges and padded tip as one tube that starts inside the thenar wedge (add_thenar) halfway
    along the metacarpal and tapers to the tip, a knuckle at each joint."""
    prof = thumb_prof(THUMB["w"], THUMB["d"], THUMB["L"])
    st = joint_stations(chain, prof, (1, 2), THUMB_TUBE_START * chain.L[0])
    u_end = chain.u[-1]
    st = [s for s in st if st_u(chain, s) < u_end - 0.034]
    rings = digit_rings(chain, st, prof, bulge=1.0) + tip_rings(chain, u_end, prof, pad=0.26)
    us = [st_u(chain, s) for s in st] + [u_end - 0.024, u_end]
    mb.loft(rings, band_vols(chain, us, vol0), start="flat", end="flat")


def add_thenar(mb, chain, vol):
    """Thenar and web as ONE convex faceted wedge: from the thumb side of the palm (wrist crease to the index
    knuckle, its anchors just inside the palm's surface) out to a ring round the thumb's MCP joint and the root of the
    first phalanx. Its palm-side planes are the thenar mound, its back-side plane the web between thumb and index;
    unioned with the palm and the thumb tube it is one volume growing out of the palm."""
    prof = thumb_prof(THUMB["w"], THUMB["d"], THUMB["L"])
    L0, L1 = chain.L[0], chain.L[1]
    pts = []
    for u, sc in ((0.15 * L0, 0.90), (0.86 * L0, THENAR_RING), (L0 + 0.30 * L1, 0.74)):
        p, F = chain.at(u)
        pts += facet_ring(p, F.col[0], F.col[1], tuple(v * sc for v in prof(u)), DIGIT_NORMALS, DIGIT_BOXY)[0]
    for z, back, side, palm_out, palm_in in THENAR_ANCHORS:
        wp, wn, dt, db, cy = interp_table(PALM_ST, z)
        pts += [V((0.90 * wp, back * dt, z)), V((side * wp, -0.30 * db + cy, z)),
                V((palm_out * wp, -0.72 * db + cy, z)), V((palm_in * wp, -0.55 * db + cy, z))]
    mb.hull(pts, vol, lambda co: max(-1.0, min(1.0, co[1] / 0.05)))


def add_fist_core(mb, chains, vol):
    """Hidden flesh inside a tight fist: the convex hull of the curled fingers' bone points, so no daylight shows
    through the loop of a finger from the side."""
    pts = []
    for fname, mcp, L, w, d in FINGERS:
        c = chains[fname]
        for k in range(4):
            pts.append(c.p[k].copy())
        pts.append(c.p[0] + V((0, 0, -0.03)))
    th = chains["Thumb"]
    for k in (1, 2, 3):   # and the tunnel between the tucked thumb and the curled index finger
        pts.append(th.p[k].copy())
    # points 70% of the way out to the surfaces of the curled index and the tucked thumb, so the core also fills the
    # crevice between them on the thumb side of the fist (no dark hole into the fist)
    for c, w, d in ((chains["Index"], FINGERS[0][3], FINGERS[0][4]), (th, THUMB["w"], THUMB["d"])):
        for s_ in range(1, 3):
            for t_ in (0.25, 0.75):
                p, F = c.at(c.u[s_] + t_ * c.L[s_])
                for ax, r in ((F.col[0], w), (-F.col[0], w), (F.col[1], d), (-F.col[1], d)):
                    pts.append(p + ax * (0.7 * r))
    mb.hull(pts, vol, lambda co: -1.0)


def palm_zoff(x):
    # the knuckle line runs back toward the little finger (its MCP sits 0.03 nearer the wrist)
    return -0.030 * smoothstep(-0.05, -0.14, x)


def add_palm(mb, vol):
    """The palm block: the convex hull of a few fixed-normal 12-sided rings (the arched back in three planes, bevelled
    sides, a three-plane palm) from the shared wrist ring to the knuckle line and a two-ring cap under the finger
    roots. Every face of the hull is one flat facet, the knuckle line's slope toward the little finger included."""
    X, Y = V((1, 0, 0)), V((0, 1, 0))
    # behind the shared wrist ring the hand ends in a rolling "heel": rings on arcs centred on the wrist pivot (back and
    # palm arcs about the flexion axis, side arcs about the deviation axis), inside the forearm's wrist skin at a
    # straight wrist. When the hand bends, this heel rolls out of the wrist skin along its own circle, so the stretched
    # side of the wrist stays one smooth skin surface instead of opening a lip (the forearm's wrist ball, see
    # build_forearm, sits on the same arcs a hair inside)
    pts = []
    for z in WRIST_ARCS:
        pts += facet_ring(V((0, 0, -z)), X, Y, wrist_arc_prof(z, 0.0), PALM_NORMALS, PALM_BOXY)[0]
    for z, wp, wn, dt, db, cy in PALM_ST:
        pts += facet_ring(V((0, 0, z)), X, Y, (wp, wn, dt, db, cy), PALM_NORMALS, PALM_BOXY)[0]
    z0, wp, wn, dt, db, cy = PALM_ST[-1]
    for z, sw, st_, sb in PALM_CAP:
        pts += facet_ring(V((0, 0, z)), X, Y, (wp * sw, wn * sw, dt * st_, db * sb, cy), PALM_NORMALS, PALM_BOXY)[0]
    for p in pts:
        p.z += palm_zoff(p.x) * smoothstep(0.17, 0.236, p.z)
    mb.hull(pts, vol, lambda co: max(-1.0, min(1.0, co[1] / (0.05 if co[1] >= 0 else 0.06))),
            warm_fn=lambda co: 0.35 * max(0.0, min(1.0, co[1] / 0.04)) * smoothstep(0.2, 0.236, co[2]))


UNION_WELD = 0.0008   # studs: vertices this close after the boolean are welded, edges this short collapsed


def union_shells(name, shells):
    """Exact boolean union of closed shells -> one closed skin: no hidden faces, no shell intersections, the parts
    meet in clean crease lines. Face (vol, fid) and point attributes carry over."""
    base = shells[0]
    col = bpy.data.collections.new(name + "_ops")
    bpy.context.scene.collection.children.link(col)
    for o in shells[1:]:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
    m = base.modifiers.new("Union", "BOOLEAN")
    m.operation = "UNION"
    m.solver = "EXACT"
    m.operand_type = "COLLECTION"
    m.collection = col
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    base.modifiers.remove(m)
    old = base.data
    base.data = me
    bpy.data.meshes.remove(old)
    for o in shells[1:]:
        d = o.data
        bpy.data.objects.remove(o)
        bpy.data.meshes.remove(d)
    bpy.data.collections.remove(col)
    base.name = name
    me.name = name
    me.materials.clear()   # the boolean leaves an empty material slot
    # tidy the cut lines: weld near-coincident vertices, collapse the sliver edges and faces the intersections leave,
    # and merge coplanar neighbours into one facet (they are one plane anyway), then re-triangulate (finish_mesh)
    def closed(bm_):
        return all(e.is_manifold for e in bm_.edges)
    bm = bmesh.new()
    bm.from_mesh(me)
    steps = (lambda b: bmesh.ops.remove_doubles(b, verts=b.verts, dist=UNION_WELD),
             lambda b: bmesh.ops.dissolve_degenerate(b, dist=UNION_WELD, edges=b.edges[:]),
             lambda b: bmesh.ops.dissolve_limit(b, angle_limit=math.radians(0.5), verts=b.verts[:], edges=b.edges[:]))
    for step in steps:   # each clean-up step is kept only if the skin stays closed and manifold
        trial = bm.copy()
        step(trial)
        if closed(trial):
            bm.free()
            bm = trial
        else:
            trial.free()
    bm.to_mesh(me)
    bm.free()
    finish_mesh(base)
    return base


def build_hand(pose_name):
    chains, info = solve_pose(pose_name)
    pose = POSES[pose_name]
    name = "R_Hand%s_Skin" % pose_name
    shells = []
    mb = MB()
    add_palm(mb, vol=1)
    shells.append(mb.build(name))
    mb = MB()
    add_thenar(mb, chains["Thumb"], vol=2)
    shells.append(mb.build(name + "_thenar"))
    mb = MB()
    add_thumb(mb, chains["Thumb"], vol0=30)
    shells.append(mb.build(name + "_thumb"))
    for i, (fname, mcp, L, w, d) in enumerate(FINGERS):
        mb = MB()
        add_finger(mb, chains[fname], finger_prof(w, d, L), vol0=10 + 4 * i)
        shells.append(mb.build(name + "_" + fname))
    if pose_name == "Fist":
        mb = MB()
        add_fist_core(mb, chains, vol=3)
        shells.append(mb.build(name + "_core"))
    obj = union_shells(name, shells)
    return obj, chains, info


# =============================================================================================== sleeves
SLEEVE_SIDES = 10


def fold_fn(folds):
    """folds: [(z, angle_deg, amplitude, width, tilt)] -> radial(a, x, y) offsets at height z."""
    def make(z):
        def radial(a, x, y):
            d = 0.0
            for zf, ang, amp, w, tilt in folds:
                th = math.radians(ang)
                zc = zf + tilt * math.sin(a - th)
                around = (0.5 + 0.5 * math.cos(a - th)) ** 1.5
                d += amp * math.exp(-((z - zc) / w) ** 2) * around
            return d
        return radial
    return make


def build_upper_arm():
    mb = MB()
    folds = fold_fn([(0.30, 40, 0.010, 0.10, 0.10), (0.55, 200, 0.011, 0.09, -0.12), (0.74, 265, 0.012, 0.05, 0.04),
                     (0.84, 290, 0.010, 0.04, -0.04), (0.20, 300, -0.008, 0.08, 0.10)])
    st = [(0.000, 0.150, 0.150, 0.150, 0.150), (0.20, 0.156, 0.156, 0.154, 0.156), (0.45, 0.150, 0.150, 0.150, 0.152),
          (0.68, 0.142, 0.142, 0.140, 0.142), (0.86, 0.136, 0.136, 0.133, 0.134), (0.95, 0.134, 0.134, 0.132, 0.132)]
    X, Y = V((1, 0, 0)), V((0, 1, 0))
    rings = []
    for z, sc in ((-0.045, 0.60), (-0.022, 0.90)):   # shoulder dome (never seen in first person)
        pts, dors = section(V((0, 0, z)), X, Y, tuple(v * sc for v in st[0][1:]), SLEEVE_SIDES, 2.3, 2.3)
        rings.append((pts, dors, 0.0, 0.0))
    for z, wp, wn, dt, db in st:
        pts, dors = section(V((0, 0, z)), X, Y, (wp, wn, dt, db), SLEEVE_SIDES, 2.3, 2.3, radial=folds(z))
        rings.append((pts, dors, 0.0, 0.0))
    r = 0.134   # elbow cap centred on the elbow pivot: covers the joint when the forearm bends
    for deg in (34, 62):
        t = math.radians(deg)
        pts, dors = section(V((0, 0, UPPER_LEN + r * math.sin(t))), X, Y, (r * math.cos(t),) * 4, SLEEVE_SIDES,
                            2.3, 2.3)
        rings.append((pts, dors, 0.0, 0.0))
    vols = [1, 1] + [2, 2, 3, 3, 3] + [4, 4, 4]
    mb.loft(rings, vols[:len(rings) - 1], start=V((0, 0, -0.050)), end="flat")
    return mb


FOREARM_SKIN = [   # z (forearm frame), profile (+x, -x, back, palm, palm-side shift); the last ring IS the hands'
    (0.700, (0.093, 0.093, 0.057, 0.059, 0.0)),   # wrist ring (WRIST_PROF) at the pivot, so the skin runs on
    (0.790, (0.100, 0.100, 0.061, 0.063, 0.0)),   # into the hand without a step (both rings inside the cuff)
    (FORE_LEN, WRIST_PROF),
]
# Past the pivot the wrist skin ends in a ball on the same arcs as the hand's rolling heel (WRIST_ARCS), 0.002 inside
# them: hidden in the hand at a straight wrist, flush with the heel when the hand bends.
WRIST_BALL_INSET = 0.002


def skin_prof(z):
    """The forearm's wrist-skin profile at z (linear between the FOREARM_SKIN rings)."""
    table = [(zz,) + tuple(pr[:4]) for zz, pr in FOREARM_SKIN]
    return interp_table(table, z)


CUFF_Z0, CUFF_Z1 = 0.700, 0.792


def build_forearm():
    sl, sk = MB(), MB()
    X, Y = V((1, 0, 0)), V((0, 1, 0))
    folds = fold_fn([(0.16, 250, 0.012, 0.07, 0.06), (0.40, 70, 0.010, 0.09, -0.10), (0.56, 300, 0.012, 0.06, 0.08),
                     (0.64, 140, 0.009, 0.05, -0.06)])
    st = [(-0.040, 0.124, 0.124, 0.120, 0.120), (0.06, 0.134, 0.134, 0.126, 0.126), (0.24, 0.138, 0.138, 0.122, 0.124),
          (0.44, 0.130, 0.130, 0.112, 0.114), (0.62, 0.120, 0.120, 0.100, 0.100), (0.72, 0.116, 0.116, 0.095, 0.095)]
    rings = []
    for z, wp, wn, dt, db in st:
        fade = smoothstep(-0.04, 0.06, z) * (1.0 - smoothstep(0.64, 0.72, z))
        pts, dors = section(V((0, 0, z)), X, Y, (wp, wn, dt, db), SLEEVE_SIDES, 2.4, 2.4,
                            radial=lambda a, x, y, z=z, fade=fade: folds(z)(a, x, y) * fade)
        rings.append((pts, dors, 0.0, 0.0))
    sl.loft(rings, [1, 1, 2, 2, 2], start="flat", end="flat")
    # clean cuff: a band that stands proud of the sleeve, chamfered edges, its end face closing onto the wrist
    rings = []
    for z, add in ((CUFF_Z0 - 0.004, -0.004), (CUFF_Z0 + 0.008, 0.012), (CUFF_Z1 - 0.008, 0.012), (CUFF_Z1, 0.0)):
        pts, dors = section(V((0, 0, z)), X, Y, (0.116 + add, 0.116 + add, 0.095 + add, 0.095 + add), SLEEVE_SIDES,
                            2.4, 2.4)
        rings.append((pts, dors, 0.0, 0.0))
    for z in (CUFF_Z1, CUFF_Z0 + 0.010):   # inner face, just inside the wrist skin (hidden)
        wp, wn, dt, db = skin_prof(z)
        pts, dors = section(V((0, 0, z)), X, Y, (wp - 0.004, wn - 0.004, dt - 0.004, db - 0.004), SLEEVE_SIDES,
                            2.4, 2.4)
        rings.append((pts, dors, 0.0, 0.0))
    sl.loft(rings, [5, 5, 5, 6, 7, 7], closed=True)
    # wrist skin from inside the cuff to the pivot: its last ring is the hands' own wrist ring, so at a straight wrist
    # the skin runs on into the hand in one crease line; past the pivot a rounded end stays inside the hand and fills
    # the stretched side of the wrist when the hand bends (0-30 degrees)
    rings = []
    for z, prof in FOREARM_SKIN:
        pts, dors = facet_ring(V((0, 0, z)), X, Y, prof, PALM_NORMALS, PALM_BOXY)
        rings.append((pts, dors, 0.0, 0.0))
    for dz in WRIST_ARCS:
        pts, dors = facet_ring(V((0, 0, FORE_LEN + dz)), X, Y, wrist_arc_prof(dz, WRIST_BALL_INSET), PALM_NORMALS,
                               PALM_BOXY)
        rings.append((pts, dors, 0.0, 0.0))
    sk.loft(rings, [40] * (len(rings) - 1), start="flat", end="flat")
    return sl, sk


# =============================================================================================== painting
def jit(i, salt):
    return hash01(i, salt) * 2.0 - 1.0


def paint(obj, kind):
    """Painted corner colours, ONE flat colour per modelled facet (all triangles of a face share its value) ->
    colour attribute bk_col (linear)."""
    me = obj.data
    nP, nL, nV = len(me.polygons), len(me.loops), len(me.vertices)
    vol = np.empty(nP, np.int32)
    me.attributes["vol"].data.foreach_get("value", vol)
    fid = np.empty(nP, np.int32)
    me.attributes["fid"].data.foreach_get("value", fid)
    att = {}
    for nm in ("dors", "warm", "tip"):
        a = np.empty(nV, np.float32)
        me.attributes[nm].data.foreach_get("value", a)
        att[nm] = a
    lt = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_total", lt)
    ls_ = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_start", ls_)
    lv = np.empty(nL, np.int32)
    me.loops.foreach_get("vertex_index", lv)
    area = np.empty(nP, np.float32)
    me.polygons.foreach_get("area", area)
    area = np.maximum(area.astype(np.float64), 1e-12)
    # per-facet (fid) area-weighted means of the painting attributes
    per = {nm: np.array([float(att[nm][lv[ls_[pi]:ls_[pi] + lt[pi]]].mean()) for pi in range(nP)])
           for nm in ("dors", "warm", "tip")}
    ufid, inv = np.unique(fid, return_inverse=True)
    wsum = np.bincount(inv, weights=area)
    grp = {nm: (np.bincount(inv, weights=per[nm] * area) / wsum)[inv] for nm in per}
    col = np.ones((nL, 4), np.float32)
    base = np.asarray(SKIN_BASE if kind == "Skin" else SLEEVE_BASE, np.float64) / 255.0
    for pi in range(nP):
        d, w, t = grp["dors"][pi], grp["warm"][pi], grp["tip"][pi]
        vv, ff = int(vol[pi]), int(fid[pi])
        if kind == "Skin":
            val = 1.0 + 0.035 * jit(vv, 3) + 0.030 * jit(ff, 5)
            if d < -0.35:
                val *= 1.035           # palms and pads a touch lighter
            elif abs(d) < 0.35:
                val *= 0.985           # sides
            c = base * val
            c = c + 0.012 * jit(vv, 7) * np.array([0.8, 0.25, -0.9])      # slight warm / cool drift
            c = c * (1.0 + w * (np.array([1.0, 0.925, 0.90]) - 1.0))      # knuckles a little redder
            c = c * (1.0 + t * (np.array([1.0, 0.935, 0.915]) - 1.0))    # fingertips too
        else:
            val = 1.0 + 0.03 * jit(vv, 13) + 0.030 * jit(ff, 17)
            if vv == 6:
                val *= 0.86            # cuff end face
            elif vv == 7:
                val *= 0.55            # cuff inside (hidden)
            elif vv == 5:
                val *= 0.94            # cuff band
            c = base * val
        c = np.clip(c, 0.0, 1.0)
        lin = tg.srgb_to_lin(c)
        col[ls_[pi]:ls_[pi] + lt[pi], :3] = lin
    a = me.color_attributes.new("bk_col", "FLOAT_COLOR", "CORNER")
    a.data.foreach_set("color", col.ravel())
    return obj


# =============================================================================================== assets (R side)
PIECES = [   # name, kind, texture set per part
    ("UpperArm", "ViewmodelArm"), ("Forearm", "ViewmodelArm"),
    ("HandGrip", "ViewmodelHand"), ("HandOpen", "ViewmodelHand"), ("HandFist", "ViewmodelHand"),
    ("HandRelaxed", "ViewmodelHand"),
]


def build_right_side():
    """-> dict piece -> {"parts": [(role, obj)], "attach": {name: (pos, look, up)}, "info": {...}}"""
    out = {}
    up = build_upper_arm().build("R_UpperArm_Sleeve")
    paint(up, "Sleeve")
    out["UpperArm"] = dict(parts=[("Sleeve", up)], attach={
        "Shoulder": (V((0, 0, 0)), V((0, 0, 1)), V((0, 1, 0))),
        "Elbow": (V((0, 0, UPPER_LEN)), V((0, 0, 1)), V((0, 1, 0)))}, info={})
    sl, sk = build_forearm()
    slo = sl.build("R_Forearm_Sleeve")
    paint(slo, "Sleeve")
    sko = sk.build("R_Forearm_Skin")
    paint(sko, "Skin")
    out["Forearm"] = dict(parts=[("Sleeve", slo), ("Skin", sko)], attach={
        "Elbow": (V((0, 0, 0)), V((0, 0, 1)), V((0, 1, 0))),
        "Wrist": (V((0, 0, FORE_LEN)), V((0, 0, 1)), V((0, 1, 0)))}, info={})
    for pose in ("Grip", "Open", "Fist", "Relaxed"):
        obj, chains, info = build_hand(pose)
        paint(obj, "Skin")
        att = {"Wrist": (V((0, 0, 0)), V((0, 0, 1)), V((0, 1, 0)))}
        if pose == "Grip":
            H, D, R = info["handle"]
            info["coverage"] = grip_coverage(obj, H, D, R)
            g = V(GRIP_ATTACH)
            ts = [(chains[f].p[0].lerp(chains[f].p[1], 0.5) - H).dot(D) for f, *_ in FINGERS]
            info["fist_centre"] = tuple(round(v, 4) for v in (H + D * (sum(ts) / len(ts))))
            upv = (V((0, 0, 1)) - D * D.z).normalized()
            att["Grip"] = (g, D.copy(), upv)
        elif pose in ("Open", "Relaxed"):
            p = palm_surface(obj, 0.0, 0.18)
            att["Palm"] = (p, V((0, -1, 0)), V((0, 0, 1)))
            info["palm"] = tuple(round(v, 4) for v in p)
        elif pose == "Fist":
            pts = []
            for fname in ("Index", "Middle"):
                c = chains[fname]
                pts.append(c.p[0].lerp(c.p[1], 0.30) + c.f[1].col[1] * 0.040)
            kn = (pts[0] + pts[1]) * 0.5
            att["Knuckles"] = (kn, V((0, 0, 1)), V((0, 1, 0)))
            info["knuckles"] = tuple(round(v, 4) for v in kn)
        out["Hand" + pose] = dict(parts=[("Skin", obj)], attach=att, info=info, chains=chains)
        log("POSE %-5s angles %s | thumb clearance %s" % (pose, info["angles"], info["thumb_diag"]))
    return out


def grip_coverage(obj, H, D, R, step=5):
    """Degrees of the circle round the handle axis that meet skin, cast outward from the axis at each finger's
    position along the handle (index, middle, ring, little)."""
    bpy.context.view_layer.update()
    ey, ez = wrap_axes(D)
    out = {}
    for name, mcp, *_ in FINGERS:
        c = H + D * (V(mcp) - H).dot(D)
        hits = 0
        for a in range(0, 360, step):
            d = ey * math.cos(math.radians(a)) + ez * math.sin(math.radians(a))
            ok = obj.ray_cast(c + d * (0.5 * R), d, distance=0.35)[0]
            hits += 1 if ok else 0
        out[name] = hits * step
    return out


def palm_surface(obj, x, z):
    """Palm-side surface point of a hand mesh at (x, z): ray from below (-Y) up to the first hit."""
    bpy.context.view_layer.update()
    ok, loc, nrm, idx = obj.ray_cast(V((x, -1.0, z)), V((0, 1, 0)))
    return V(loc) if ok else V((x, -0.066, z))


# =============================================================================================== scene helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_material(name):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    return m


def link_only(nt, out_socket, in_socket):
    for l_ in list(in_socket.links):
        nt.links.remove(l_)
    nt.links.new(out_socket, in_socket)


def tint_node(nt, color_socket, name, rgb):
    """Insert ColorMap x tint (SurfaceAppearance.Color) in front of a colour socket; returns the mix node."""
    mx_ = nt.nodes.new("ShaderNodeMix")
    mx_.data_type = "RGBA"
    mx_.blend_type = "MULTIPLY"
    mx_.name = name
    mx_.label = name
    mx_.inputs[0].default_value = 1.0
    nt.links.new(color_socket, mx_.inputs[6])
    mx_.inputs[7].default_value = (*s2l(rgb), 1.0)
    return mx_


def quick_material(kind):
    m = new_material("Q_" + kind)
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "bk_col"
    mx_ = tint_node(nt, at.outputs["Color"], "Tint", SKIN_TINT_DEFAULT if kind == "Skin" else SLEEVE_TINT_DEFAULT)
    nt.links.new(mx_.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = ROUGH[kind]
    return m


def mirror_copy(obj, name):
    """Exact X-mirror of a finished mesh (UVs, colours and materials kept, outward winding restored)."""
    me = obj.data.copy()
    me.name = name
    me.transform(Matrix.Scale(-1.0, 4, (1.0, 0.0, 0.0)))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def make_roots(built, mirror=True):
    """Asset roots (empties at the origin) with their part meshes; L_ = mirrored copies. -> dict name -> root."""
    roots = {}
    for side, pre in ((1, "R_"), (-1, "L_")):
        if side < 0 and not mirror:
            continue
        for piece, kind in PIECES:
            nm = pre + piece
            root = bpy.data.objects.new(nm, None)
            root.empty_display_type = "PLAIN_AXES"
            bpy.context.scene.collection.objects.link(root)
            for role, obj in built[piece]["parts"]:
                o = obj if side > 0 else mirror_copy(obj, "%s_%s" % (nm, role))
                o.parent = root
                o["role"] = role
            roots[nm] = root
    return roots


# =============================================================================================== posing (previews)
def ik_dirs(S, W, pole):
    """Two-bone IK: upper-arm and forearm directions reaching W from S, elbow toward pole."""
    cv = W - S
    c = min(cv.length, UPPER_LEN + FORE_LEN - 1e-4)
    cd = cv.normalized()
    cos_a = (UPPER_LEN ** 2 + c * c - FORE_LEN ** 2) / (2 * UPPER_LEN * c)
    al = math.acos(max(-1.0, min(1.0, cos_a)))
    p = V(pole)
    p = (p - cd * p.dot(cd)).normalized()
    d1 = cd * math.cos(al) + p * math.sin(al)
    E = S + d1 * UPPER_LEN
    return d1, (S + cd * c - E).normalized()


def hand_frame(side, W, bone, thumb):
    """World matrix of a hand piece: wrist at W, fingers along bone, thumb toward thumb (L pieces carry the thumb
    on their local -X)."""
    z = V(bone).normalized()
    t = V(thumb)
    t = (t - z * t.dot(z)).normalized()
    x = t if side > 0 else -t
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = V(W)
    return m


def auto_pole(S, Mh, hint, weight=0.35):
    """Elbow pole that lines the forearm up with the hand (like the game's Rig.AUTO_POLE): the elbow swings round
    the shoulder-wrist axis to the place that minimises the wrist bend plus weight x the swing away from the hint;
    the elbow never rises above the shoulder."""
    W = Mh.translation.copy()
    axis = (W - V(S)).normalized()
    h = V(hint)
    h = (h - axis * h.dot(axis)).normalized()
    bone = Mh.to_3x3().col[2].normalized()
    best = None
    for i in range(120):
        a = TAU * i / 120.0
        p = (Matrix.Rotation(a, 3, axis) @ h).normalized()
        d1, d2 = ik_dirs(V(S), W, p)
        E = V(S) + d1 * UPPER_LEN
        if E.z > V(S).z + 0.05:
            continue
        swing = math.degrees(min(a, TAU - a))
        cost = math.degrees(d2.angle(bone)) + weight * swing
        if best is None or cost < best[0]:
            best = (cost, p)
    return best[1] if best else h


def arm_matrices(side, S, Mh, pole):
    """Upper arm and forearm matrices that reach the hand's wrist (two-bone IK), forearm rolled with the hand."""
    W = Mh.translation.copy()
    d1, d2 = ik_dirs(V(S), W, pole)
    E = V(S) + d1 * UPPER_LEN
    Mf = frame4(E, d2, Mh.to_3x3().col[0])
    bend = d2 - d1 * d2.dot(d1)
    if bend.length < 1e-4:
        bend = V(pole)
    y_u = -bend.normalized()
    x_u = y_u.cross(d1)
    Mu = Matrix((x_u, y_u, d1)).transposed().to_4x4()
    Mu.translation = V(S)
    wrist_bend = math.degrees(d2.angle(Mh.to_3x3().col[2]))
    reach = (E + d2 * FORE_LEN - W).length
    return Mu, Mf, wrist_bend, reach


def grip_local(roots_info, side):
    """The hand's Grip frame (hand space) as a 4x4, mirrored for L."""
    g, D, U = roots_info
    return look_up_frame(mx(g, side), mx(D, side), mx(U, side))


# =============================================================================================== look / lighting
def render_setup(scene, res, samples, denoise=True):
    tg.enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.015
    c.use_denoising = denoise
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.transparent_max_bounces = 8
    c.caustics_reflective = False
    c.caustics_refractive = False
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.film_transparent = False
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    # Khronos PBR Neutral keeps the base colours' hue and saturation (AgX's high-contrast look turned the skin pale
    # and pinkish-grey under the blue sky fill); closest of Blender's transforms to how Roblox shows painted colour
    try:
        scene.view_settings.view_transform = "Khronos PBR Neutral"
        scene.view_settings.look = "None"
    except TypeError:
        scene.view_settings.view_transform = "AgX"


LIGHTS = {
    # sun elevation / azimuth (deg, azimuth 0 = from straight ahead (+Y), +90 = from the right), sun colour and
    # strength, sky strength, exposure, the Shade-module key light above the arms (strength 0 = off), ground albedo
    "midday": dict(elev=54.0, azim=-118.0, sun=(1.0, 0.95, 0.86), sun_w=4.0, sky=0.12, exposure=-0.45, key=0.0,
                   ground=(84, 128, 46), aerosol=0.7),
    "dusk": dict(elev=6.0, azim=-62.0, sun=(1.0, 0.56, 0.30), sun_w=2.4, sky=0.10, exposure=0.1, key=6.0,
                 ground=(84, 128, 46), aerosol=1.0),
    # piece close-ups: a neutral grey ground, little sky, the sun over the camera's shoulder (piece_views turns it
    # with each view), so the sheet shows the painted colours instead of the blue sky fill
    "studio": dict(elev=45.0, azim=-100.0, sun=(1.0, 0.96, 0.9), sun_w=3.2, sky=0.06, exposure=0.1, key=0.0,
                   ground=(140, 140, 130), aerosol=0.7),
}


def light_scene(scene, key):
    L = LIGHTS[key]
    world = bpy.data.worlds.get("AF_Sky") or bpy.data.worlds.new("AF_Sky")
    if world.node_tree is None:
        world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "MULTIPLE_SCATTERING"
    except TypeError:
        sky.sky_type = "NISHITA"
    sky.sun_disc = False
    sky.altitude = 300.0
    try:
        sky.aerosol_density = L.get("aerosol", 1.0)
    except AttributeError:
        pass
    sky.sun_elevation = math.radians(max(L["elev"], 1.0))
    # sky node: sun_rotation 0 = sun toward +Y? We aim it with the same azimuth as the lamp below.
    sky.sun_rotation = math.radians(L["azim"]) + math.pi
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = L["sky"]
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    scene.world = world
    scene.view_settings.exposure = L["exposure"]
    sun = bpy.data.objects.get("AF_Sun")
    if sun is None:
        sun = bpy.data.objects.new("AF_Sun", bpy.data.lights.new("AF_Sun", "SUN"))
        scene.collection.objects.link(sun)
    sun.data.color = L["sun"]
    sun.data.energy = L["sun_w"]
    sun.data.angle = math.radians(1.5)
    e, a = math.radians(L["elev"]), math.radians(L["azim"])
    to_sun = V((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    sun.rotation_euler = (-to_sun).to_track_quat("-Z", "Y").to_euler()
    key_l = bpy.data.objects.get("AF_Key")
    if key_l is None:
        key_l = bpy.data.objects.new("AF_Key", bpy.data.lights.new("AF_Key", "AREA"))
        scene.collection.objects.link(key_l)
        key_l.data.shape = "DISK"
        key_l.data.size = 1.5
    key_l.data.energy = L["key"]
    key_l.data.color = (0.86, 0.88, 1.0)
    key_l.hide_render = L["key"] <= 0.0
    key_l.location = (0.0, 0.9, 1.4)
    key_l.rotation_euler = (V((0.0, 0.9, -0.5)) - V((0.0, 0.9, 1.4))).to_track_quat("-Z", "Y").to_euler()
    g = bpy.data.objects.get("AF_Ground")
    if g is not None:
        m = g.data.materials[0]
        m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*s2l(L["ground"]), 1.0)
    return sun


def ground(scene, z=-4.6):
    g = bpy.data.objects.get("AF_Ground")
    if g is None:
        me = bpy.data.meshes.new("AF_Ground")
        s = 2000.0
        me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
        g = bpy.data.objects.new("AF_Ground", me)
        scene.collection.objects.link(g)
        m = new_material("AF_GroundMat")
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Roughness"].default_value = 0.95
        me.materials.append(m)
    g.location = (0, 0, z)
    return g


def camera(scene, loc, target, vfov=70.0, res=None, up=(0, 0, 1)):
    cam = bpy.data.objects.get("AF_Cam")
    if cam is None:
        cam = bpy.data.objects.new("AF_Cam", bpy.data.cameras.new("AF_Cam"))
        scene.collection.objects.link(cam)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(vfov)
    cam.data.clip_start = 0.02
    cam.data.clip_end = 3000
    cam.location = V(loc)
    cam.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    if res:
        scene.render.resolution_x, scene.render.resolution_y = res
    return cam


def render_to(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log("RENDER %s (%.0fs)" % (os.path.basename(path), time.time() - t))
    return path


# =============================================================================================== image sheets
_TEXT_CACHE = {}


def text_tris(text):
    if text in _TEXT_CACHE:
        return _TEXT_CACHE[text]
    curve = bpy.data.curves.new("_lbl", type="FONT")
    curve.body = text
    curve.size = 1.0
    obj = bpy.data.objects.new("_lbl", curve)
    bpy.context.scene.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    verts = np.array([v.co[:2] for v in me.vertices], np.float64)
    tris = np.array([t.vertices[:] for t in me.loop_triangles], np.int64)
    ev.to_mesh_clear()
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    res = verts[tris] if len(tris) else np.zeros((0, 3, 2))
    _TEXT_CACHE[text] = res
    return res


def draw_text(img, text, x, y, size, rgb=(1, 1, 1), ss=3):
    """Rasterise text (Blender's built-in font) onto img (H x W x 3, row 0 = top) with its baseline at y."""
    tris = text_tris(text)
    if len(tris) == 0:
        return
    H, W = img.shape[:2]
    pts = tris * size
    pts[..., 0] += x
    pts[..., 1] = y - pts[..., 1]
    x0 = int(max(0, math.floor(pts[..., 0].min())))
    x1 = int(min(W, math.ceil(pts[..., 0].max()) + 1))
    y0 = int(max(0, math.floor(pts[..., 1].min())))
    y1 = int(min(H, math.ceil(pts[..., 1].max()) + 1))
    if x1 <= x0 or y1 <= y0:
        return
    hs, ws = (y1 - y0) * ss, (x1 - x0) * ss
    cov = np.zeros((hs, ws), bool)
    P = (pts - np.array([x0, y0])) * ss
    for t in P:
        bx0, by0 = int(max(0, math.floor(t[:, 0].min()))), int(max(0, math.floor(t[:, 1].min())))
        bx1, by1 = int(min(ws, math.ceil(t[:, 0].max()) + 1)), int(min(hs, math.ceil(t[:, 1].max()) + 1))
        if bx1 <= bx0 or by1 <= by0:
            continue
        yy, xx = np.mgrid[by0:by1, bx0:bx1]
        px, py = xx + 0.5, yy + 0.5
        a, b, c = t
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / d
        l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / d
        l3 = 1 - l1 - l2
        cov[by0:by1, bx0:bx1] |= (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
    alpha = cov.reshape(y1 - y0, ss, x1 - x0, ss).mean(axis=(1, 3))[..., None]
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - alpha) + np.asarray(rgb)[None, None, :] * alpha


def load_rgb(path):
    """Image file -> float sRGB H x W x 3, row 0 = top."""
    a = tg.load_image_np(path, "sRGB")[..., :3]
    return np.flipud(a).astype(np.float64)


def resize(img, w, h):
    """Area-ish resample (bilinear on a box-prefiltered image) to w x h."""
    H, W = img.shape[:2]
    f = max(1, int(min(H / h, W / w)))
    if f > 1:
        img = img[:H - H % f, :W - W % f].reshape(H // f, f, W // f, f, -1).mean(axis=(1, 3))
        H, W = img.shape[:2]
    ys = (np.arange(h) + 0.5) * H / h - 0.5
    xs = (np.arange(w) + 0.5) * W / w - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, H - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, W - 1)
    y1 = np.clip(y0 + 1, 0, H - 1)
    x1 = np.clip(x0 + 1, 0, W - 1)
    fy = np.clip(ys - y0, 0, 1)[:, None, None]
    fx = np.clip(xs - x0, 0, 1)[None, :, None]
    a = img[y0][:, x0]
    b = img[y0][:, x1]
    c = img[y1][:, x0]
    d = img[y1][:, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def compose(panels, cols, out_path, title=None, subtitle=None, label_h=40, pad=8, bg=(0.086, 0.094, 0.11),
            label_rgb=(0.93, 0.84, 0.67), size=21):
    """panels: [(image row0=top, label)] -> sheet PNG with a label strip above every panel."""
    h, w = panels[0][0].shape[:2]
    rows = (len(panels) + cols - 1) // cols
    top = 0
    if title:
        top = 64 if subtitle else 46
    W = cols * w + (cols + 1) * pad
    H = top + rows * (h + label_h) + (rows + 1) * pad
    sheet = np.ones((H, W, 3)) * np.asarray(bg)
    if title:
        draw_text(sheet, title, pad + 4, 32, 26, (0.97, 0.97, 0.97))
        if subtitle:
            draw_text(sheet, subtitle, pad + 4, 56, 16, (0.72, 0.74, 0.78))
    for i, (im, lab) in enumerate(panels):
        r, c = divmod(i, cols)
        x = pad + c * (w + pad)
        y = top + pad + r * (h + label_h + pad)
        if lab:
            draw_text(sheet, lab, x + 4, y + label_h - 12, size, label_rgb)
        sheet[y + label_h:y + label_h + h, x:x + w] = im[:h, :w]
    tg.write_png(out_path, np.flipud(np.clip(sheet, 0, 1)), quantize=False)
    log("SHEET", out_path, "%dx%d" % (W, H))
    return out_path


# =============================================================================================== shots
SHOULDER = {1: V((0.40, -0.25, -0.50)), -1: V((-0.40, -0.25, -0.50))}   # eye at the origin, looking +Y
EYE = V((0.0, 0.0, 0.0))
PITCH = 18.0                                                             # camera looks this far down
LOOK = V((0.0, math.cos(math.radians(PITCH)), -math.sin(math.radians(PITCH))))


class Stage:
    """The assets of a review render: arm pieces (live meshes in 'quick', the imported GLB in 'preview') and the
    held items, each a root whose origin is its pivot (items: their Grip)."""

    def __init__(self, roots, grip, palm, items=None):
        self.roots = roots
        self.grip = grip            # (g, D, U) of R_HandGrip.Grip in hand space (Blender)
        self.palm = palm            # R_HandOpen.Palm position (hand space)
        self.items = items or {}
        self.items_bottom = {}
        self.notes = []

    def hide_all(self):
        for r in list(self.roots.values()) + list(self.items.values()):
            for o in [r] + list(r.children_recursive):
                o.hide_render = True
        self.notes = []

    def show(self, root, M):
        root.matrix_world = M
        for o in [root] + list(root.children_recursive):
            o.hide_render = False
            o.visible_shadow = False          # the viewmodel casts no shadows in game (Config.Viewmodel.ArmShadows)

    def arm(self, side, hand, Mh, pole, auto=False, weight=0.35):
        pre = "R_" if side > 0 else "L_"
        p = auto_pole(SHOULDER[side], Mh, pole, weight) if auto else V(pole)
        Mu, Mf, bend, gap = arm_matrices(side, SHOULDER[side], Mh, p)
        self.show(self.roots[pre + "UpperArm"], Mu)
        self.show(self.roots[pre + "Forearm"], Mf)
        self.show(self.roots[pre + hand], Mh)
        self.notes.append("%s%s wrist bend %.0f deg, reach gap %.3f" % (pre, hand, bend, gap))

    def item(self, name, M):
        if name in self.items:
            self.show(self.items[name], M)


def hand_on_forearm(side, W, pole, thumb, flex=0.0, dev=0.0):
    """Hand frame at wrist W continuing the forearm the IK gives for this pole, thumb toward 'thumb', then bent at
    the wrist: flex (+ toward the palm) and dev (+ toward the thumb, radial; - ulnar), degrees."""
    d1, d2 = ik_dirs(SHOULDER[side], V(W), V(pole))
    R = hand_frame(side, W, d2, thumb).to_3x3() @ rot("X", flex) @ rot("Y", dev * side)
    M = R.to_4x4()
    M.translation = V(W)
    return M


def grip_hand_matrix(side, item_M, grip):
    """Hand matrix that puts the hand's Grip frame on the item's Grip frame (item_M = item pivot world matrix)."""
    return item_M @ grip_local(grip, side).inverted()


FIST_THUMB = (-0.55, 0.30, 0.78)   # thumb direction (R; L mirrored): up and in, so the tucked thumb shows
FIST_FLEX = 20.0


def shot_fists(st):
    # guard low on each side, clear of the crosshair: knuckles forward, thumbs up and in
    for side, W in ((1, (0.34, 0.88, -0.46)), (-1, (-0.36, 0.84, -0.49))):
        pole = (0.35 * side, -0.1, -1.0)
        t = FIST_THUMB
        Mh = hand_on_forearm(side, W, pole, (t[0] * side, t[1], t[2]), flex=FIST_FLEX, dev=-4)
        st.arm(side, "HandFist", Mh, pole)


RELAX = dict(wrist=(0.62, 0.90, -0.98), pole=(0.4, -0.3, -0.86), thumb=(-0.8, 0.0, 0.6), flex=15.0, dev=-5.0)


def shot_relaxed(st):
    # the idle (empty hands; fists only while punching): hands low in the bottom corners, forearms coming in from
    # below, palms turned in, thumbs on top, fingers easy and pointing forward and down (ulnar wrist deviation); the
    # middle of the view stays clear
    r = RELAX
    for side in (1, -1):
        W = V((r["wrist"][0] * side, r["wrist"][1], r["wrist"][2]))
        pole = V((r["pole"][0] * side, r["pole"][1], r["pole"][2]))
        t = r["thumb"]
        Mh = hand_on_forearm(side, W, pole, (t[0] * side, t[1], t[2]), flex=r["flex"], dev=r["dev"])
        st.arm(side, "HandRelaxed", Mh, pole)


def shot_sword(st):
    # blade up the right of the view: the hand continues the forearm, cocked toward the little finger (ulnar)
    W = (0.38, 0.86, -0.47)
    pole = (0.6, -0.1, -1.0)
    Mh = hand_on_forearm(1, W, pole, (-0.20, 0.05, 1.0), flex=-4, dev=-26)
    st.item("sword", Mh @ grip_local(st.grip, 1))
    st.arm(1, "HandGrip", Mh, pole)


def hook_hand(side, H, axis, pole, iters=6, weight=0.25):
    """Hand frame whose Grip sits on point H with its handle axis along 'axis' (a bow string) and whose fingers
    continue its own forearm: for each elbow pole round the shoulder-hook line, iterate hand -> wrist -> IK forearm
    direction -> hand; keep the pole with the straightest wrist (plus weight x the swing from the hint)."""
    S = SHOULDER[side]
    line = (H - S).normalized()
    h = V(pole)
    h = (h - line * h.dot(line)).normalized()
    best = None
    for i in range(36):
        a = TAU * i / 36.0
        p = (Matrix.Rotation(a, 3, line) @ h).normalized()
        toward = H - S
        up = (toward - axis * toward.dot(axis)).normalized()
        M = None
        d2 = None
        for _ in range(iters):
            M = grip_hand_matrix(side, look_up_frame(H, axis, up), GRIP_FRAME[0])
            d1, d2 = ik_dirs(S, M.translation.copy(), p)
            up = (d2 - axis * d2.dot(axis)).normalized()
        E = S + ik_dirs(S, M.translation.copy(), p)[0] * UPPER_LEN
        if E.z > S.z + 0.05:
            continue
        bend = math.degrees(d2.angle(M.to_3x3().col[2]))
        cost = bend + weight * math.degrees(min(a, TAU - a))
        if best is None or cost < best[0]:
            best = (cost, M, p)
    return best[1], best[2]


GRIP_FRAME = [None]


# Bow view, low ready like the game's BowReady (found by a search over bow placements): the bow canted 35 degrees to
# the left, the bow hand fully in view left of centre, the string hand at the lower left hooking the string with its
# forearm rising from below and its wrist within a few degrees of straight, clear of the bow hand.
BOW = dict(pos=(-0.50, 1.50, -0.55), cant=35.0, front=(0.50, 0.866, 0.10), draw=0.25, hook_below=0.12,
           pole_hint=(0.6, -0.4, -0.7), pole_weight=0.3)


def shot_bow(st):
    # the start of a draw: the bow in the left hand left of centre, canted a little to the left, the arrow on the
    # string; the right hand hooks the string with three fingers just under the arrow, its wrist in line with its
    # forearm. The string is drawn as two straight segments through the nock (as the game does with two Beams).
    b = BOW
    GRIP_FRAME[0] = st.grip
    cant = math.radians(b["cant"])
    look = V((-math.sin(cant), 0.0, math.cos(cant)))           # bow axis (top limb)
    bow_M = look_up_frame(b["pos"], look, V(b["front"]))        # y = shot direction
    ML = grip_hand_matrix(-1, bow_M, st.grip)
    st.item("bow", bow_M)
    for c in (st.items["bow"].children if "bow" in st.items else []):
        if c.name.startswith("bow_Rope") or c.name.startswith("q_string"):
            c.hide_render = True
    st.arm(-1, "HandGrip", ML, (-0.8, -0.3, -0.7), auto=True)
    R3 = bow_M.to_3x3()
    shot = (R3 @ V((0, 1, 0))).normalized()
    s_axis = (R3 @ V((0, 0, 1))).normalized()
    nock = bow_M @ V((0.0, -0.4168, 0.2)) - shot * b["draw"]   # string centre: Roblox (0, 0.2, 0.4168)
    top = bow_M @ V((0.0, -0.4168, 2.32))                          # StringTop
    bottom = bow_M @ V((0.0, -0.4168, -1.92))                      # StringBottom
    for nm, a, c in (("string_top", top, nock), ("string_bottom", nock, bottom)):
        if nm in st.items:
            d = c - a
            M = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
            M.translation = a
            st.show(st.items[nm], M @ Matrix.Diagonal((1.0, 1.0, d.length, 1.0)))
    hook_axis = (top - bottom).normalized()
    MR, poleR = hook_hand(1, nock - hook_axis * b["hook_below"], hook_axis, b["pole_hint"], weight=b["pole_weight"])
    st.arm(1, "HandGrip", MR, poleR)
    rest = bow_M @ V((-0.04, 0.035, 0.2))           # ArrowRest: Roblox (-0.04, 0.2, -0.035)
    st.item("arrow", look_up_frame(nock, (rest - nock).normalized(), s_axis))


def shot_apple(st):
    W = (0.36, 0.80, -0.53)
    pole = (0.7, -0.3, -0.9)
    Mh = hand_on_forearm(1, W, pole, (1.0, 0.15, 0.25), flex=-26, dev=4)
    up = -(Mh.to_3x3() @ V((0, 1, 0))).normalized()          # out of the palm
    bottom = st.items_bottom.get("apple", 0.13)
    centre = Mh @ V(st.palm) + up * (bottom + 0.004)
    Ma = up.to_track_quat("Z", "Y").to_matrix().to_4x4()      # the apple's own up (Blender +Z) out of the palm
    Ma.translation = centre
    st.item("apple", Ma)
    st.arm(1, "HandOpen", Mh, pole)


def shot_sword_game(st):
    # like the in-game captures: the fist bigger and lower right (closer to the eye)
    W = (0.32, 0.66, -0.55)
    pole = (0.6, -0.1, -1.0)
    Mh = hand_on_forearm(1, W, pole, (-0.12, 0.05, 1.0), flex=-6, dev=-30)
    st.item("sword", Mh @ grip_local(st.grip, 1))
    st.arm(1, "HandGrip", Mh, pole)


SHOTS = {"sword_game": shot_sword_game, "fists": shot_fists, "relaxed": shot_relaxed, "sword": shot_sword, "bow": shot_bow, "apple": shot_apple}


def fp_camera(scene, res):
    return camera(scene, EYE, EYE + LOOK, vfov=70.0, res=res)


def render_shot(scene, st, key, light, path, res, samples=None, tint=None):
    st.hide_all()
    SHOTS[key](st)
    light_scene(scene, light)
    fp_camera(scene, res)
    if samples:
        scene.cycles.samples = samples
    if tint is not None:
        set_tint("Skin", tint)
    for n in st.notes:
        log("  %s %s: %s" % (key, light, n))
    return render_to(scene, path)


# =============================================================================================== tint (preview)
TINT_NODES = {"Skin": [], "Sleeve": []}


def set_tint(kind, rgb):
    for n in TINT_NODES[kind]:
        n.inputs[7].default_value = (*s2l(rgb), 1.0)


# =============================================================================================== baking
BAKE = {   # AO radii (studs), AO exponents, AO strength (term floor = 1 - strength), warm AO, bevel normal radius
    "Skin": dict(near=0.014, far=0.065, pn=1.0, pf=0.7, strength=0.36, warm=(0.80, 1.0, 1.08), bevel=0.0085),
    "Sleeve": dict(near=0.050, far=0.18, pn=1.0, pf=0.8, strength=0.36, warm=(1.0, 1.0, 1.0), bevel=0.013),
}


def bake_material(name, near, far, bevel):
    m = new_material(name)
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    ac = N.new("ShaderNodeAttribute")
    ac.attribute_name = "bk_col"
    em = N.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    aon = N.new("ShaderNodeAmbientOcclusion")
    aon.samples = 16
    aon.inputs["Distance"].default_value = near
    aof = N.new("ShaderNodeAmbientOcclusion")
    aof.samples = 16
    aof.inputs["Distance"].default_value = far
    bev = N.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = bevel
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    L.new(bev.outputs["Normal"], bsdf.inputs["Normal"])
    img = N.new("ShaderNodeTexImage")
    N.active = img
    return m, dict(nt=nt, out=out, em=em, ac=ac, aon=aon, aof=aof, bsdf=bsdf, img=img)


def set_bake_pass(h, which):
    nt, em, out = h["nt"], h["em"], h["out"]
    for l_ in list(em.inputs["Color"].links):
        nt.links.remove(l_)
    if which == "normal":
        link_only(nt, h["bsdf"].outputs["BSDF"], out.inputs["Surface"])
        return
    link_only(nt, em.outputs["Emission"], out.inputs["Surface"])
    src = {"color": h["ac"].outputs["Color"], "aon": h["aon"].outputs["AO"], "aof": h["aof"].outputs["AO"]}.get(which)
    if src is None:
        em.inputs["Color"].default_value = (1, 1, 1, 1)
    else:
        nt.links.new(src, em.inputs["Color"])


def uv_unwrap(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(52.0), island_margin=0.003, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", scale=True, margin_method="FRACTION", margin=0.004,
                            shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")


def blur_masked(a, m, sigma):
    w = m.astype(np.float64)
    num = tg.pblur(a * w, sigma)
    den = tg.pblur(w, sigma)
    out = np.where(den > 1e-4, num / np.maximum(den, 1e-4), a)
    return np.where(m, out, a)


def bake_set(kind, objs):
    """UV-unwrap the set's (right-side) parts together and bake painted colour x two-radius AO, roughness and a
    bevel normal into one texture set. Returns the file names and stats."""
    p = BAKE[kind]
    size = TEX_SIZE[kind]
    scene = bpy.context.scene
    uv_unwrap(objs)
    mat, h = bake_material("BK_" + kind, p["near"], p["far"], p["bevel"])
    home = []
    for i, o in enumerate(objs):   # pieces share the origin: spread them out so they don't occlude each other
        home.append(o.location.copy())
        o.location = (4.0 * i, 0.0, 0.0)
        o.data.materials.clear()
        o.data.materials.append(mat)
    bpy.context.view_layer.update()
    for o in scene.objects:
        o.hide_render = o not in objs
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    maps = {}
    for which, spp in (("cover", 1), ("color", 4), ("aon", 64), ("aof", 96), ("normal", 16)):
        img = bpy.data.images.new("bk_%s_%s" % (kind, which), size, size, alpha=True, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        h["img"].image = img
        h["nt"].nodes.active = h["img"]
        set_bake_pass(h, which)
        scene.cycles.samples = spp
        if which == "normal":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y",
                                normal_b="POS_Z", margin=0, use_clear=True, target="IMAGE_TEXTURES")
        else:
            bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True, target="IMAGE_TEXTURES")
        maps[which] = tg.image_to_np(img).astype(np.float64)
        bpy.data.images.remove(img)
    for o, loc in zip(objs, home):
        o.location = loc
    for o in scene.objects:
        o.hide_render = False
    cov = maps["cover"][..., 0] > 0.5
    col = maps["color"][..., :3]
    aon = blur_masked(np.clip(maps["aon"][..., 0], 0, 1), cov, 1.0)
    aof = blur_masked(np.clip(maps["aof"][..., 0], 0, 1), cov, 1.6)
    ao = np.clip(aon, 0, 1) ** p["pn"] * np.clip(aof, 0, 1) ** p["pf"]
    term = 1.0 - p["strength"] * (1.0 - ao)[..., None] * np.asarray(p["warm"])[None, None, :]
    term = np.clip(term, 0.5, 1.0)                     # rule 5: never below half the painted value
    out = col * term
    rough = np.clip(ROUGH[kind] + 0.06 * (1.0 - aon), 0.75, 0.95)
    nrm = maps["normal"][..., :3]
    w = cov.astype(np.float64)
    out = tg.pushpull(out, w)
    rough = tg.pushpull(rough[..., None], w)[..., 0]
    nrm = tg.pushpull(nrm, w)
    nrm = tg.encode_normal(nrm * 2.0 - 1.0)
    base = "%s_%s" % (CATEGORY, kind)
    files = {"color": base + "_Color.png", "normal": base + "_Normal.png", "rough": base + "_Rough.png",
             "mr": base + "_MR.png"}
    os.makedirs(GLB_ONLY, exist_ok=True)
    tg.write_png(os.path.join(TEX, files["color"]), tg.lin_to_srgb(out))
    tg.write_png(os.path.join(TEX, files["normal"]), nrm, quantize=False)
    tg.write_png(os.path.join(TEX, files["rough"]), rough)
    r2 = rough
    while r2.shape[0] > 512:
        r2 = 0.25 * (r2[0::2, 0::2] + r2[1::2, 0::2] + r2[0::2, 1::2] + r2[1::2, 1::2])
    tg.write_png(os.path.join(GLB_ONLY, files["mr"]), np.stack([r2, r2, np.zeros_like(r2)], axis=2))
    srgb_mean = [int(round(v)) for v in tg.lin_to_srgb(out[cov].mean(0)) * 255]
    stats = dict(coverage=round(float(cov.mean()), 3), meanColorSRGB=srgb_mean,
                 aoTermMin=round(float(term[cov].min()), 3),
                 roughness=[round(float(rough[cov].min()), 3), round(float(rough[cov].max()), 3)])
    log("  baked %s: coverage %.1f%%, mean ColorMap sRGB %s, AO term min %.2f" % (
        kind, 100 * stats["coverage"], srgb_mean, stats["aoTermMin"]))
    return files, stats


def export_material(kind, files):
    m = new_material("%s_%s" % (CATEGORY, kind))
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def img(path, cs):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    tc = img(os.path.join(TEX, files["color"]), "sRGB")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = img(os.path.join(TEX, files["normal"]), "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tr = img(os.path.join(GLB_ONLY, files["mr"]), "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    m.use_backface_culling = True
    return m


# =============================================================================================== GLB checks
def _glb_split(data):
    magic, ver, length = struct.unpack("<III", data[:12])
    clen, ctype = struct.unpack("<II", data[12:20])
    return ver, json.loads(data[20:20 + clen].decode("utf-8")), data[20 + clen:]


def glb_patch_and_check(path):
    """metallicFactor 0 on every material (patched in the JSON chunk), then: POSITION/NORMAL/TANGENT/TEXCOORD_0 on
    every primitive, no vertex colours, no doubleSided material, textures present, size."""
    with open(path, "rb") as f:
        data = f.read()
    ver, js, rest = _glb_split(data)
    for m in js.get("materials", []):
        m.setdefault("pbrMetallicRoughness", {})["metallicFactor"] = 0
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, ver, 12 + len(body)) + body)
    problems = []
    need = ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0")
    nprim = 0
    for me in js.get("meshes", []):
        for prim in me.get("primitives", []):
            nprim += 1
            miss = [k for k in need if k not in prim.get("attributes", {})]
            if miss:
                problems.append("%s lacks %s" % (me.get("name"), ",".join(miss)))
            if "COLOR_0" in prim.get("attributes", {}):
                problems.append("%s carries vertex colours" % me.get("name"))
    for m in js.get("materials", []):
        if m.get("doubleSided"):
            problems.append("material %s is doubleSided" % m.get("name"))
        if "normalTexture" not in m or "baseColorTexture" not in m.get("pbrMetallicRoughness", {}):
            problems.append("material %s lacks textures" % m.get("name"))
    size = os.path.getsize(path)
    if size >= 19_000_000:
        problems.append("GLB is %.2f MB" % (size / 1e6))
    return {"primitives": nprim, "meshes": len(js.get("meshes", [])),
            "images": [i.get("name") for i in js.get("images", [])],
            "materials": [m.get("name") for m in js.get("materials", [])], "bytes": size,
            "tangentsOnEveryPrimitive": not any("TANGENT" in p for p in problems)}, problems


def png_info(path):
    with open(path, "rb") as f:
        head = f.read(33)
    w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
    return {"size": [w, h], "bitDepth": bd, "channels": {0: "gray", 2: "RGB", 4: "gray+alpha", 6: "RGBA"}.get(ct)}


def to_roblox(v):
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def to_blender(r):
    return V((r[0], -r[2], r[1]))


# =============================================================================================== BUILD
STYLE_NOTES = [
    "Faceted realism (docs/design/ArtStyle.md style A): real hand and forearm proportions built from chunky "
    "flat-shaded facets, like a carved figure. Skin rings have FIXED face directions, so every band between two rings "
    "is a flat facet (no twisted quads crumpling into small triangles); the palm and the thenar-and-web wedge are "
    "convex hulls (every face one plane). 6-sided fingers and thumb with one band per phalanx, a 12-sided palm block "
    "(three-plane back and palm, bevelled sides), 10-sided sleeves; no nails or wrinkles.",
    "One skin per hand: palm, thenar-and-web wedge, thumb and fingers (and the hidden core of the fist) are unioned "
    "into one closed mesh (exact boolean), so the parts meet in clean crease lines with no shell intersections.",
    "Painted, not textured: one flat value per modelled facet (+-3.5% per phalanx or panel, +-3% per facet, slight "
    "warm/cool drift; all triangles of a face share it), warmer knuckles and fingertips, lighter palms; two-radius AO "
    "multiplied in (never below half the painted value; warm on the skin); a 0.0085-0.013-stud bevel normal only "
    "rounds the facet edges.",
    "Matte: roughness 0.80-0.86 skin, 0.92-0.95 sleeve; metalness 0.",
    "Tintable: both ColorMaps are neutral light bases. SurfaceAppearance.Color multiplies them: the avatar's arm "
    "colour on the Skin parts, any colour on the Sleeve parts (default charcoal).",
]

NOTES = {
    "UpperArm": "Sleeve from the shoulder (y=0) to the elbow (y=0.95) with a faceted elbow cap centred on the elbow "
                "pivot, so the joint stays closed when the forearm bends toward Roblox +Z. Attachments: Shoulder "
                "(origin), Elbow (0, 0.95, 0).",
    "Forearm": "Sleeve from the elbow to a clean cuff band (y 0.70-0.79), then the bare wrist (Skin) to the wrist "
               "pivot (y=0.85), whose last ring IS every hand's wrist ring, so at a straight wrist the skin runs on "
               "into the hand without a step. Past the pivot it ends in a ball on arcs centred on the pivot (inside "
               "the hand), which the hand's rolling heel slides over when the wrist bends up to 30 degrees. "
               "Attachments: Elbow (origin), Wrist (0, 0.85, 0).",
    "HandGrip": "Hand closed round a 0.15-stud handle (power grip; Items handles are 0.10-0.19 across); also hooks "
                "the bow string. The fingers are solved to wrap as far round the handle as they reach (pads pressing "
                "up to 0.026 into it) and the thumb wraps the other way onto the index finger. Grip = on the handle "
                "axis at the centre of the fist: look = handle axis toward the thumb / index side, up = toward the "
                "fingers. Same Grip as the previous kit, so items line up unchanged.",
    "HandOpen": "Cupped open hand that cradles an apple or a bottle on the palm (fingers curled 22-38 degrees at "
                "each joint, thumb out to the side). Palm = centre of the palm surface, look = out of the palm, "
                "up = toward the fingers; a round item of radius r sits with its centre at Palm + look * r.",
    "HandFist": "Tight punching fist, thumb across the index and middle fingers. Use it only while punching. Knuckles "
                "= on the striking knuckles (index + middle proximal phalanges), look = punch direction, up = back "
                "of the hand.",
    "HandRelaxed": "Relaxed idle hand, the shape for empty hands (the owner: fists only while punching): fingers in "
                   "an easy cascade, more curl toward the little finger, thumb resting by the index. Palm as on "
                   "HandOpen.",
}


def build_stage():
    reset()
    scene = bpy.context.scene
    tg.enable_gpu(scene)
    scene.cycles.use_denoising = False
    built = build_right_side()
    for d in built.values():
        for role, o in d["parts"]:
            o["role"] = role
    # texture sets: right-side parts only (the L pieces are mirrors and reuse the same UVs and texels)
    sets = {"Skin": [], "Sleeve": []}
    for piece, kind in PIECES:
        for role, o in built[piece]["parts"]:
            sets[role].append(o)
    files, stats = {}, {}
    for kind, objs in sets.items():
        t = time.time()
        files[kind], stats[kind] = bake_set(kind, objs)
        log("BAKE %s (%d parts) %.0fs" % (kind, len(objs), time.time() - t))
    rgb = {}
    for kind in sets:   # fallback MeshPart.Color = mean ColorMap x default tint
        lin = np.asarray(s2l(stats[kind]["meanColorSRGB"])) * np.asarray(
            s2l(SKIN_TINT_DEFAULT if kind == "Skin" else SLEEVE_TINT_DEFAULT))
        rgb[kind] = [int(round(v)) for v in tg.lin_to_srgb(lin) * 255]
    mats = {k: export_material(k, f) for k, f in files.items()}
    for kind, objs in sets.items():
        for o in objs:
            o.data.materials.clear()
            o.data.materials.append(mats[kind])
            for an in ("vol", "dors", "warm", "tip"):
                a = o.data.attributes.get(an)
                if a is not None:
                    o.data.attributes.remove(a)
            a = o.data.color_attributes.get("bk_col")
            if a is not None:
                o.data.color_attributes.remove(a)
            o.data.uv_layers[0].name = "UVMap"
    roots = make_roots(built)
    # layout in a row along X; manifest entries
    entries = []
    x = 0.0
    bpy.context.view_layer.update()
    for side, pre in ((1, "R_"), (-1, "L_")):
        for piece, kind in PIECES:
            nm = pre + piece
            root = roots[nm]
            parts = [c for c in root.children if c.type == "MESH"]
            lo = np.array([1e9] * 3)
            hi = np.array([-1e9] * 3)
            pentries = []
            for o in sorted(parts, key=lambda o: o.name):
                co = np.empty(len(o.data.vertices) * 3, np.float32)
                o.data.vertices.foreach_get("co", co)
                co = co.reshape(-1, 3)
                lo = np.minimum(lo, co.min(0))
                hi = np.maximum(hi, co.max(0))
                role = o["role"]
                f = files[role]
                tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
                info = ls.ROLES[role]
                pentries.append({
                    "name": o.name, "role": role, "robloxMaterial": info["roblox"], "rgb": rgb[role],
                    "collide": False, "collision": "Box", "castShadow": False, "canQuery": False, "canTouch": False,
                    "tags": ["Tintable"], "tris": tris, "textureSet": "%s_%s" % (CATEGORY, role),
                    "surfaceAppearance": {
                        "colorMap": REL_TEX + "/" + f["color"], "normalMap": REL_TEX + "/" + f["normal"],
                        "roughnessMap": REL_TEX + "/" + f["rough"], "metalnessMap": None, "alphaMode": "Overlay",
                        "color": list(SKIN_TINT_DEFAULT if role == "Skin" else SLEEVE_TINT_DEFAULT)},
                    "tint": ("SurfaceAppearance.Color = the avatar's arm colour (BodyColors.%sArmColor3)" %
                             ("Right" if side > 0 else "Left")) if role == "Skin" else
                            "SurfaceAppearance.Color = sleeve colour (default charcoal)",
                    "transparency": 0, "doubleSided": False, "backFacesInMesh": False, "neon": False,
                    "renderFidelity": "Automatic"})
            d = built[piece]
            att = {}
            for an, (pos, look, up) in d["attach"].items():
                att[an] = {"position": to_roblox(mx(pos, side)), "look": to_roblox(mx(look, side).normalized()),
                           "up": to_roblox(mx(up, side).normalized())}
            a, b = to_roblox(lo), to_roblox(hi)
            pivot = {"UpperArm": "shoulder", "Forearm": "elbow"}.get(piece, "wrist")
            tags = ["Viewmodel", "Right" if side > 0 else "Left", "Faceted"]
            tags += (["Hand", piece[4:]] if piece.startswith("Hand") else [piece])
            e = {"name": nm, "kind": kind, "tags": tags,
                 "notes": ("Bone axis = Roblox +Y (UpVector), pivot (origin) at the %s; LookVector (Roblox -Z) = back "
                           "of the arm / hand; thumb on %s. " % (
                               pivot, "+X" if side > 0 else "-X (exact X-mirror of the R_ piece)")) + NOTES[piece],
                 "glb": CATEGORY + ".glb", "pivot": pivot,
                 "boundsMin": [min(p, q) for p, q in zip(a, b)], "boundsMax": [max(p, q) for p, q in zip(a, b)],
                 "size": [round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3),
                          round(float(hi[1] - lo[1]), 3)],
                 "tris": sum(p["tris"] for p in pentries), "parts": pentries, "attachments": att}
            offset = x - float(lo[0])
            root.location = (offset, 0.0, 0.0)
            e["origin"] = [round(offset, 4), 0.0, 0.0]
            x += float(hi[0] - lo[0]) + 0.5
            entries.append(e)
    bpy.context.view_layer.update()
    for o in scene.objects:
        o.select_set(False)
    for r in roots.values():
        r.select_set(True)
        for c in r.children:
            c.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_image_format="AUTO", export_materials="EXPORT", export_normals=True,
                              export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
                              export_attributes=False)
    check, problems = glb_patch_and_check(GLB_PATH)
    log("GLBCHECK %s: %d meshes, %d primitives, %.2f MB, tangents everywhere %s, problems %s" % (
        os.path.basename(GLB_PATH), check["meshes"], check["primitives"], check["bytes"] / 1e6,
        check["tangentsOnEveryPrimitive"], problems))
    warnings = list(problems)
    for e in entries:
        hand = e["kind"] == "ViewmodelHand"
        lo_, hi_ = (300, 1500) if hand else (1, 600)
        if not lo_ <= e["tris"] <= hi_:
            warnings.append("%s has %d triangles (budget %d-%d)" % (e["name"], e["tris"], lo_, hi_))
    upload = []
    for kind, f in files.items():
        for k in ("color", "normal", "rough"):
            upload.append(dict(file=REL_TEX + "/" + f[k], kind={"rough": "roughness"}.get(k, k),
                               set="%s_%s" % (CATEGORY, kind), **png_info(os.path.join(TEX, f[k]))))
    pose_info = {}
    for piece in ("HandGrip", "HandOpen", "HandFist", "HandRelaxed"):
        i = built[piece]["info"]
        pose_info[piece] = {"jointAnglesDeg": i["angles"], "thumbClearance": i["thumb_diag"],
                            "thumbPose": i["thumb"]}
        if "fist_centre" in i:
            pose_info[piece]["fistCentreOnHandle"] = to_roblox(i["fist_centre"])
        if "tip_psi" in i:
            pose_info[piece]["wrapAngleDeg"] = dict(
                note="round the handle axis from the back-of-hand side: 90 = finger side, 180 = far side",
                fingertips=i["tip_psi"], thumbTip=round(360.0 + i["thumb_psi"][-1], 1))
            pose_info[piece]["skinCoverageDeg"] = i["coverage"]
    manifest = {
        "schema": "LS-Real-1 (viewmodel arms)", "category": CATEGORY, "glb": CATEGORY + ".glb",
        "glbs": [{"file": CATEGORY + ".glb", "assets": [e["name"] for e in entries], "bytes": check["bytes"],
                  "sizeMB": round(check["bytes"] / 1e6, 2), "embeddedImages": check["images"]}],
        "units": "1 Blender unit = 1 Roblox stud (world scale)",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y). Arm pieces: origin = proximal joint, bone axis = Roblox +Y "
                "(UpVector), LookVector (-Z) = back of the arm / hand, thumb +X on R_ pieces; L_ = exact X-mirrors.",
        "chain": {"UpperArm.Elbow": [0, UPPER_LEN, 0], "Forearm.Wrist": [0, FORE_LEN, 0],
                  "note": "UpperArm.Elbow -> Forearm origin; Forearm.Wrist -> hand origin; bend the elbow toward "
                          "Roblox +Z (inner elbow)."},
        "textureFolder": REL_TEX, "uploadTextures": upload,
        "glbOnlyTextures": [REL_TEX + "/glb_only/" + f["mr"] for f in files.values()],
        "textureSets": {"%s_%s" % (CATEGORY, k): dict(colorMap=REL_TEX + "/" + v["color"],
                                                      normalMap=REL_TEX + "/" + v["normal"],
                                                      roughnessMap=REL_TEX + "/" + v["rough"], metalnessMap=None,
                                                      size=TEX_SIZE[k], **stats[k]) for k, v in files.items()},
        "tinting": {
            "skin": "Every *_Skin part: SurfaceAppearance.Color = the player's arm colour (BodyColors.RightArmColor3 "
                    "on R_, LeftArmColor3 on L_). The ColorMap is a neutral light base (mean sRGB %s), so the "
                    "facet values, warm knuckles and AO multiply through any tone." % stats["Skin"]["meanColorSRGB"],
            "sleeve": "Every *_Sleeve part: SurfaceAppearance.Color = %s (charcoal) by default; any colour works "
                      "(neutral light ColorMap, mean sRGB %s)." % (list(SLEEVE_TINT_DEFAULT),
                                                                  stats["Sleeve"]["meanColorSRGB"]),
            "checkedTones": {n: list(c) for _, n, c in SKIN_TONES},
            "fallback": "Without a SurfaceAppearance, MeshPart.Color = the tone (the facets still read from the flat "
                        "shading).",
        },
        "poses": pose_info,
        "import": [
            "Import the GLB; each asset root is a Model of MeshParts <Asset>_<Role>. Re-centre with 'origin' "
            "(WorldPivot = CFrame.new(origin), then PivotTo); measure and undo the importer's 180-degree turn about "
            "Y as ItemAssets does.",
            "Give every part ONE SurfaceAppearance from its 'surfaceAppearance' block (ColorMap, NormalMap, "
            "RoughnessMap; MetalnessMap empty; AlphaMode Overlay); set its Color per 'tinting' at runtime.",
            "Every part: CanCollide/CanQuery/CanTouch false, CastShadow false (Config.Viewmodel.ArmShadows may turn "
            "it on), CollisionFidelity Box, Anchored, Material = robloxMaterial, Color = rgb (fallback).",
            "Attachments: create each one under the asset's first part with WorldCFrame = pivot * "
            "CFrame.lookAt(position, position + look, up) (art/README.md section 4).",
            "Hold items by aligning the item's Grip frame with R_/L_HandGrip.Grip (item:PivotTo(handGrip.WorldCFrame "
            "* itemGripLocal:Inverse())). Round food sits on Palm: centre = Palm + look * radius.",
        ],
        "glbCheck": dict(check, problems=problems),
        "styleRules": STYLE_NOTES,
        "assets": entries,
        "warnings": warnings,
    }
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    os.makedirs(REPO_MANIFESTS, exist_ok=True)
    shutil.copyfile(MANIFEST_PATH, os.path.join(REPO_MANIFESTS, CATEGORY + ".manifest.json"))
    log("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (GLB_PATH, check["bytes"] / 1e6, len(entries),
                                                           len(warnings)))
    for w in warnings:
        log("WARNING " + w)
    for e in entries:
        log("ASSET %-14s tris %4d  size %s  parts %s  attach %s" % (
            e["name"], e["tris"], e["size"], ", ".join("%s:%d" % (p["role"], p["tris"]) for p in e["parts"]),
            {k: v["position"] for k, v in e["attachments"].items()}))
    for piece, i in pose_info.items():
        log("POSE %-11s %s" % (piece, i))
    return manifest


# =============================================================================================== PREVIEW
def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def add_tints():
    TINT_NODES["Skin"].clear()
    TINT_NODES["Sleeve"].clear()
    for m in bpy.data.materials:
        kind = "Skin" if m.name.startswith(CATEGORY + "_Skin") else (
            "Sleeve" if m.name.startswith(CATEGORY + "_Sleeve") else None)
        if kind is None or m.node_tree is None:
            continue
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        src = bsdf.inputs["Base Color"].links[0].from_socket
        mx_ = tint_node(nt, src, "Tint", SKIN_TINT_DEFAULT if kind == "Skin" else SLEEVE_TINT_DEFAULT)
        link_only(nt, mx_.outputs[2], bsdf.inputs["Base Color"])
        TINT_NODES[kind].append(mx_)


def preview_scene():
    """Fresh scene with the exported arms (and the ItemsReal items) -> Stage."""
    reset()
    scene = bpy.context.scene
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        man = json.load(f)
    arms = import_glb(GLB_PATH)
    for o in arms:
        o.hide_render = True
    roots = {e["name"]: bpy.data.objects[e["name"]] for e in man["assets"]}
    add_tints()
    ent = {e["name"]: e for e in man["assets"]}
    g = ent["R_HandGrip"]["attachments"]["Grip"]
    grip = (to_blender(g["position"]), to_blender(g["look"]), to_blender(g["up"]))
    palm = to_blender(ent["R_HandOpen"]["attachments"]["Palm"]["position"])
    items = {}
    bottoms = {}
    if os.path.exists(ITEMS_GLB):
        objs = import_glb(ITEMS_GLB)
        for o in objs:
            o.hide_render = True
        imani = os.path.splitext(ITEMS_GLB)[0] + ".manifest.json"
        im = {}
        if os.path.exists(imani):
            with open(imani, encoding="utf-8") as f:
                im = {e["name"]: e for e in json.load(f)["assets"]}
        for nm in ("sword", "bow", "arrow", "apple"):
            o = bpy.data.objects.get(nm)
            if o is not None:
                items[nm] = o
                if nm in im:
                    bottoms[nm] = -im[nm]["boundsMin"][1]
        log("ITEMS from %s: %s" % (ITEMS_GLB, sorted(items)))
    else:
        log("WARNING no %s: items are not shown" % ITEMS_GLB)
    for nm in ("string_top", "string_bottom"):
        items[nm] = string_obj(nm)
    st = Stage(roots, grip, palm, items)
    st.items_bottom = bottoms
    ground(scene)
    return scene, st, man


def string_obj(name, radius=0.0065):
    """A unit-length bow-string segment along +Z (scaled to length when placed)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=radius, radius2=radius, depth=1.0)
    bmesh.ops.translate(bm, vec=V((0, 0, 0.5)), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    o = bpy.data.objects.new(name + "_mesh", me)
    bpy.context.scene.collection.objects.link(o)
    o.parent = root
    m = new_material(name)
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*s2l((196, 184, 156)), 1.0)
    b.inputs["Roughness"].default_value = 0.8
    me.materials.append(m)
    root.hide_render = True
    o.hide_render = True
    return root


def hand_versions_crops():
    """The three past versions from HandVersions.jpg (panels found by the dark separators)."""
    img = load_rgb(HAND_VERSIONS)
    H, W = img.shape[:2]
    lum = img.mean(axis=2)
    band = lum[int(H * 0.25):int(H * 0.95)]
    dark = band.max(axis=0) < 0.16
    spans = []
    x = 0
    while x < W:
        if not dark[x]:
            x0 = x
            while x < W and not dark[x]:
                x += 1
            if x - x0 > W * 0.15:
                spans.append((x0, x))
        x += 1
    boxes = []
    for x0, x1 in spans[:3]:
        col = lum[:, x0:x1]
        lit = (col > 0.16).mean(axis=1)          # the picture fills its rows; the title text only speckles them
        y0 = next(y for y in range(int(H * 0.04), H) if lit[y] > 0.9 and lit[min(H - 1, y + 3)] > 0.9)
        y1 = max(y for y in range(H) if lit[y] > 0.9) + 1
        boxes.append((x0, x1, y0, y1))
    # the three panels share one layout (dark sleeves can fool the row test on one of them)
    y0 = int(np.median([b[2] for b in boxes]))
    y1 = max(b[3] for b in boxes)
    crops = [img[y0:y1, x0:x1] for x0, x1, _, _ in boxes]
    log("HandVersions crops: %s" % [c.shape[:2] for c in crops])
    return crops


def piece_views(scene, st, nm, res=(420, 420)):
    root = st.roots[nm]
    st.hide_all()
    st.show(root, Matrix.Identity(4))
    meshes = [c for c in root.children if c.type == "MESH"]
    bpy.context.view_layer.update()
    pts = [c.matrix_world @ v.co for c in meshes for v in c.data.vertices]
    lo = V((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = V((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo + hi) / 2
    r = max((hi - lo).length / 2, 0.15)
    out = []
    for tag, el, az in (("front", 18, 30), ("back", 30, 210)):
        LIGHTS["studio"]["azim"] = az + 35.0
        light_scene(scene, "studio")
        e, a = math.radians(el), math.radians(az)
        d = V((math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)))
        fov = 30.0
        dist = r / math.sin(math.radians(fov) / 2) * 1.05
        camera(scene, c + d * dist, c, vfov=fov, res=res)
        out.append((tag, render_to(scene, os.path.join(WORK, "pc_%s_%s.png" % (nm, tag)))))
    return out


def preview_stage(only=None):
    scene, st, man = preview_scene()
    os.makedirs(PREV, exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    res = (1120, 630)
    render_setup(scene, res, 128)
    todo = set(only or ("sheet", "tones", "pieces", "compare"))
    if "sheet" in todo:   # 1. the key image: first-person sheet
        panels = []
        for key, light, label in (("relaxed", "midday", "1 Empty hands at rest (the idle), midday"),
                                  ("relaxed", "dusk", "2 Empty hands at rest, dusk (17:30-18:00 light)"),
                                  ("fists", "midday", "3 Punch (fists only while punching), midday"),
                                  ("sword", "midday", "4 Sword grip, midday"),
                                  ("bow", "midday", "5 Bow in the left hand, the right hand hooks the string"),
                                  ("apple", "midday", "6 Apple cradled in the open right hand")):
            p = render_shot(scene, st, key, light, os.path.join(WORK, "fp_%s_%s.png" % (key, light)), res, 128,
                            SKIN_TINT_DEFAULT)
            panels.append((load_rgb(p), label))
        compose(panels, 2, os.path.join(PREV, "firstperson_sheet.png"),
                title="LAST STANDING - faceted first-person hands (ArmsFaceted)",
                subtitle="Cycles preview built from the exported GLB (Khronos PBR Neutral view). Eye at the camera, 70 "
                         "degree FOV, shoulders 0.5 below and 0.4 to each side; idle hands low in the corners, fists "
                         "only while punching. Skin: Light orange. No arm shadows (as in game).")
    if "tones" in todo:   # 2. skin tones: the same fist view in three tones (+ the apple at dusk)
        panels = []
        for tone, name, rgb in SKIN_TONES:
            p = render_shot(scene, st, "fists", "midday", os.path.join(WORK, "tone_%s.png" % tone), res, 128, rgb)
            panels.append((load_rgb(p), "%s - %s %s, midday" % (tone, name, tuple(rgb))))
        for tone, name, rgb in SKIN_TONES:
            p = render_shot(scene, st, "relaxed", "dusk", os.path.join(WORK, "tone_dusk_%s.png" % tone), res, 128, rgb)
            panels.append((load_rgb(p), "%s - %s, idle at dusk" % (tone, name)))
        compose(panels, 3, os.path.join(PREV, "skin_tones.png"),
                title="Skin tones: one tintable skin (SurfaceAppearance.Color = the avatar's arm colour)",
                subtitle="Same ColorMap in three BodyColors tones (top: punch fists at midday, bottom: the idle at "
                         "dusk); the facet values and the warm AO multiply through.")
        set_tint("Skin", SKIN_TINT_DEFAULT)
    if "pieces" in todo:   # 3. every piece, front and back
        light_scene(scene, "studio")
        scene.cycles.samples = 96
        tiles = []
        ent = {e["name"]: e for e in man["assets"]}
        for piece, kind in PIECES:
            for pre in ("R_", "L_"):
                for tag, p in piece_views(scene, st, pre + piece):
                    tiles.append((load_rgb(p), "%s %s (%d tris)" % (pre + piece, tag, ent[pre + piece]["tris"])))
        compose(tiles, 4, os.path.join(PREV, "pieces.png"), size=15, label_h=26,
                title="ArmsFaceted pieces: front = back of the arm / hand, back = palm side",
                subtitle="R_ pieces and their exact X-mirrors L_; skin Light orange, sleeve charcoal.")
    if "compare" in todo:   # 4. the three past versions and the new set
        crops = hand_versions_crops()
        ch = 360
        row = []
        for c in crops:
            h, w = c.shape[:2]
            row.append(resize(c, int(round(w * ch / h)), ch))
        cw = row[0].shape[1]
        cres = (int(round(cw * 2)), ch * 2)
        p = render_shot(scene, st, "sword_game", "midday", os.path.join(WORK, "compare_new.png"), cres, 128,
                        SKIN_TINT_DEFAULT)
        new = resize(load_rgb(p), cw, ch)
        labels = ["1 - Block hands, dark sleeves (11 Nov)", "2 - Realistic gloves (11 Nov, removed)",
                  "3 - Avatar arms (now)", "4 - NEW: faceted hands (ArmsFaceted)"]
        w = max(r.shape[1] for r in row + [new])
        panels = []
        for im, lab in zip(row + [new], labels):
            pad = np.ones((ch, w, 3)) * np.array([0.086, 0.094, 0.11])
            pad[:, :min(w, im.shape[1])] = im[:, :w]
            panels.append((pad, lab))
        compose(panels, 2, os.path.join(PREV, "compare.png"),
                title="First-person hands: the three past versions and the new faceted set",
                subtitle="1 and 3 are Studio captures and 2 a Blender render (HandVersions.jpg); 4 is the new set "
                         "holding the ItemsReal sword, framed like the in-game captures (Blender preview).")
    log("PREVIEW done: %s" % PREV)


# =============================================================================================== QUICK (look-dev)
def quick_stage():
    reset()
    scene = bpy.context.scene
    built = build_right_side()
    mats = {"Skin": quick_material("Skin"), "Sleeve": quick_material("Sleeve")}
    for piece, d in built.items():
        for role, o in d["parts"]:
            o.data.materials.append(mats[role])
    roots = make_roots(built)
    st = Stage(roots, built["HandGrip"]["attach"]["Grip"], built["HandOpen"]["attach"]["Palm"][0])
    h = bpy.data.objects.new("q_sword", None)
    scene.collection.objects.link(h)
    make_cyl("q_handle", 0.075, 1.4, (0.45, 0.32, 0.2)).parent = h
    st.items["sword"] = h
    ap = bpy.data.objects.new("q_apple", None)
    scene.collection.objects.link(ap)
    make_ball("q_ball", 0.16, (0.7, 0.12, 0.1)).parent = ap
    st.items["apple"] = ap
    st.items_bottom = {"apple": 0.16}
    bw = bpy.data.objects.new("q_bow", None)
    scene.collection.objects.link(bw)
    limb = make_cyl("q_limb", 0.05, 4.4, (0.42, 0.28, 0.16))
    limb.location = (0, 0, 0.2)
    limb.parent = bw
    string = make_cyl("q_string", 0.006, 4.24, (0.9, 0.88, 0.8))
    string.location = (0, -0.4168, 0.2)
    string.parent = bw
    st.items["bow"] = bw
    ar = bpy.data.objects.new("q_arrow", None)
    scene.collection.objects.link(ar)
    shaft = make_cyl("q_shaft", 0.012, 3.0, (0.6, 0.5, 0.35))
    shaft.location = (0, 0, 1.5)
    shaft.parent = ar
    st.items["arrow"] = ar
    for nm in ("string_top", "string_bottom"):
        st.items[nm] = string_obj(nm)
    TINT_NODES["Skin"][:] = [mats["Skin"].node_tree.nodes["Tint"]]
    render_setup(scene, (960, 540), 48)
    ground(scene)
    os.makedirs(WORK, exist_ok=True)
    tiles = []
    for key, light in (("fists", "midday"), ("sword", "midday"), ("bow", "midday"), ("apple", "midday"),
                       ("relaxed", "midday"), ("sword", "dusk")):
        p = render_shot(scene, st, key, light, os.path.join(WORK, "q_%s_%s.png" % (key, light)), (960, 540))
        tiles.append((load_rgb(p), "%s, %s" % (key, light)))
    compose(tiles, 2, os.path.join(WORK, "quick_fp.png"), size=18, label_h=30)
    for nm, d in built.items():
        log("TRIS %-11s %d" % (nm, sum(len(o.data.polygons) for _, o in d["parts"])))


def make_cyl(name, r, length, rgb):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=r, radius2=r, depth=length)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    m = new_material(name)
    m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*s2l([v * 255 for v in rgb]), 1)
    me.materials.append(m)
    return o


def make_ball(name, r, rgb):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    m = new_material(name)
    m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*s2l([v * 255 for v in rgb]), 1)
    me.materials.append(m)
    return o


# =============================================================================================== main
def main():
    log("arms_faceted.py OUT=%s PREV=%s WORK=%s stages=%s" % (OUT, PREV, WORK, sorted(STAGES)))
    if "quick" in STAGES:
        quick_stage()
    if "build" in STAGES:
        build_stage()
    if "preview" in STAGES:
        only = [s[len("preview:"):] for s in STAGES if s.startswith("preview:")]
        preview_stage(only or None)
    elif any(s.startswith("preview:") for s in STAGES):
        preview_stage([s[len("preview:"):] for s in STAGES if s.startswith("preview:")])
    log("DONE")


if __name__ == "__main__":
    main()
