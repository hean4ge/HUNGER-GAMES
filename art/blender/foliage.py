"""
foliage.py - LAST STANDING "Foliage" category generator (Blender 5.3, headless).

Builds Foliage.glb + Foliage.manifest.json (+ PNG previews):
  PineA-C, OakA-B, BirchA-B, DeadTreeA-B, BushA-C, BerryBush, FernClump, ReedsClump,
  MushroomCluster, Stump, FallenLog.

Run:
  blender --background --factory-startup --python foliage.py -- <out_dir> <preview_dir>

Conventions (see ls_common.py): 1 unit = 1 stud, base on z = 0, front = +Y, one material role per mesh.
Everything is procedural and seeded, so re-running gives identical meshes.

Building blocks
- tube():        swept, tapered, optionally lobed/twisted section along a Catmull-Rom path (trunks, branches,
                 roots, logs). Returns TubeInfo so moss / bark bands / limbs can be placed exactly on it.
- pine_tier():   one drooping whorl of scalloped branch clumps with a thick rim (pines).
- cloud_into():  leafy cloud of decimated "florets" over an ellipsoid envelope (oak/birch canopies, bushes).
- conform_blob(): moss cushion wrapped onto a tube (dead tree, log).
- wrap_patch():  closed shell hugging a tube (birch bands and dark base).
"""
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls
import ls_patch  # noqa: F401  (art-direction fixes on top of ls_common: hard edges, bounds, query flags)

import math
import random
import shutil

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

out_dir, preview_dir = ls.args()
ls.reset()
ls.seed(5150)
lib = ls.Library("Foliage")

UP = Vector((0.0, 0.0, 1.0))
TAU = 2.0 * math.pi


# ================================================================================================
# Small math helpers
# ================================================================================================
def clamp(x, a, b):
    return a if x < a else (b if x > b else x)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    if abs(e1 - e0) < 1e-9:
        return 0.0 if x < e0 else 1.0
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def interp(vals, t):
    """Piecewise-linear lookup in a list of values spread evenly over t = 0..1."""
    n = len(vals) - 1
    x = clamp(t, 0.0, 1.0) * n
    i = min(int(x), n - 1)
    f = x - i
    return vals[i] + (vals[i + 1] - vals[i]) * f


def hdir(a):
    return Vector((math.cos(a), math.sin(a), 0.0))


def rvec(rng, s=50.0):
    return Vector((rng.uniform(-s, s), rng.uniform(-s, s), rng.uniform(-s, s)))


def runit(rng):
    while True:
        v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if 0.05 < v.length <= 1.0:
            return v.normalized()


def taper_shape(r0, k=0.7, sx=1.0, sy=1.0):
    """Round (or elliptical) cross-section whose radius shrinks linearly by factor k along the tube."""
    def shape(th, t):
        r = r0 * (1.0 - k * t)
        return (math.cos(th) * r * sx, math.sin(th) * r * sy)
    return shape


def clamp_bm(bm, z=0.0):
    for v in bm.verts:
        if v.co.z < z:
            v.co.z = z


def clamp_floor(obj, z=0.0):
    for v in obj.data.vertices:
        if v.co.z < z:
            v.co.z = z
    obj.data.update()


def decimate_to(obj, target):
    """Collapse-decimate to roughly `target` triangles (irregular facets read as leaves, not geodesic balls)."""
    tris = ls.tri_count(obj)
    if tris > target:
        ls.decimate(obj, target / float(tris))
    return obj


def remesh_voxel(obj, voxel):
    """Voxel-remesh: fuses overlapping florets into ONE leafy surface (no hidden interior triangles)."""
    mod = obj.modifiers.new("Remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel
    mod.adaptivity = 0.0
    return ls.apply_modifiers(obj)


def tidy(obj, dist=2e-3):
    """Make a decimated mesh export-clean: merge near-duplicate verts, drop degenerate/duplicate faces and loose
    bits, then let Blender validate it (the glTF exporter warns about invalid meshes)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=dist)
    bm.verts.index_update()
    seen, dup = set(), []
    for f in bm.faces:
        key = tuple(sorted(v.index for v in f.verts))
        if key in seen or len(set(key)) < 3 or f.calc_area() < 1e-7:
            dup.append(f)
        else:
            seen.add(key)
    if dup:
        bmesh.ops.delete(bm, geom=dup, context="FACES")
    loose_e = [e for e in bm.edges if not e.link_faces]
    if loose_e:
        bmesh.ops.delete(bm, geom=loose_e, context="EDGES")
    loose_v = [v for v in bm.verts if not v.link_faces]
    if loose_v:
        bmesh.ops.delete(bm, geom=loose_v, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.validate()
    obj.data.update()
    return obj


def foliage_mesh(bm, name, tris, voxel, rng, jitter=0.06, floor=None):
    """Florets bmesh -> fused, decimated, jittered foliage object (flat-shaded later by lib.add)."""
    obj = finish_bm(bm, name)
    remesh_voxel(obj, voxel)
    decimate_to(obj, tris)
    ls.jitter(obj, jitter, rng)
    if floor is not None:
        # sit exactly on the ground: drop the mesh so its lowest point is the floor, then flatten anything below
        lowest = min(v.co.z for v in obj.data.vertices)
        for v in obj.data.vertices:
            v.co.z -= (lowest - floor)
        clamp_floor(obj, floor)
    return tidy(obj)


def finish_bm(bm, name, triangulate=False):
    if triangulate:
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def aim_matrix(loc, direction):
    """4x4 matrix placing local +Z along `direction` at `loc`."""
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    return Matrix.Translation(Vector(loc)) @ q.to_matrix().to_4x4()


# ================================================================================================
# Paths and swept tubes (trunks, branches, roots, logs)
# ================================================================================================
def catmull_dense(ctrl, per=12):
    pts = [Vector(p) for p in ctrl]
    if len(pts) == 2:
        return [pts[0].lerp(pts[1], i / per) for i in range(per + 1)]
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(per):
            t = s / per
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * (t * t)
                              + (3 * p1 - p0 - 3 * p2 + p3) * (t * t * t)))
    out.append(pts[-1].copy())
    return out


def resample(dense, ts):
    """Points at arc-length fractions ts (increasing, 0..1) along a dense polyline."""
    L = [0.0]
    for a, b in zip(dense, dense[1:]):
        L.append(L[-1] + (b - a).length)
    total = L[-1]
    out = []
    j = 0
    for t in ts:
        target = total * t
        while j < len(L) - 2 and L[j + 1] < target:
            j += 1
        seg = L[j + 1] - L[j]
        f = 0.0 if seg < 1e-9 else (target - L[j]) / seg
        out.append(dense[j].lerp(dense[j + 1], clamp(f, 0.0, 1.0)))
    return out, total


def frames_for(path, up_ref=None, first_up=None):
    """(T, S, U) per path point. With up_ref the frame keeps U as close to up_ref as possible
    (level flat-topped branches); otherwise parallel transport (no twisting)."""
    n = len(path)
    tans = []
    for i in range(n):
        d = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
        if d.length < 1e-8:
            d = Vector((0, 0, 1))
        tans.append(d.normalized())
    out = []
    if up_ref is not None:
        up_ref = Vector(up_ref)
        for T in tans:
            U = up_ref - T * up_ref.dot(T)
            if U.length < 1e-4:
                U = Vector((1, 0, 0)) - T * T.x
            U.normalize()
            out.append((T, T.cross(U), U))
        return out
    T0 = tans[0]
    ref = Vector(first_up) if first_up is not None else (Vector((0, 1, 0)) if abs(T0.y) < 0.95 else Vector((1, 0, 0)))
    U = (ref - T0 * ref.dot(T0)).normalized()
    prev = T0
    for T in tans:
        U = prev.rotation_difference(T) @ U
        U = (U - T * U.dot(T)).normalized()
        out.append((T, T.cross(U), U))
        prev = T
    return out


class TubeInfo:
    """Keeps a swept tube's rings so other parts (moss, bark bands, limbs) can sit exactly on it."""

    def __init__(self, path, frames, ts, ring_pts, seg, twist):
        self.path, self.frames, self.ts = path, frames, ts
        self.ring_pts, self.seg, self.twist = ring_pts, seg, twist

    def _locate(self, t):
        ts = self.ts
        t = clamp(t, ts[0], ts[-1])
        i = 0
        while i < len(ts) - 2 and ts[i + 1] < t:
            i += 1
        f = (t - ts[i]) / max(ts[i + 1] - ts[i], 1e-9)
        return i, clamp(f, 0.0, 1.0)

    def center(self, t):
        i, f = self._locate(t)
        return self.path[i].lerp(self.path[i + 1], f)

    def frame(self, t):
        i, f = self._locate(t)
        a, b = self.frames[i], self.frames[i + 1]
        return tuple(a[k].lerp(b[k], f).normalized() for k in range(3))

    def _ring(self, r, theta):
        a = (theta - self.twist * self.ts[r]) / TAU * self.seg
        k = math.floor(a)
        g = a - k
        k = int(k) % self.seg
        return self.ring_pts[r][k].lerp(self.ring_pts[r][(k + 1) % self.seg], g)

    def point(self, t, theta, offset=0.0):
        """Point on the (faceted) tube surface at arc fraction t and section angle theta, pushed
        `offset` studs outward (negative = inside)."""
        i, f = self._locate(t)
        P = self._ring(i, theta).lerp(self._ring(i + 1, theta), f)
        C = self.center(t)
        T = self.frame(t)[0]
        d = P - C
        d -= T * d.dot(T)
        if d.length > 1e-6:
            P = P + d.normalized() * offset
        return P

    def theta_toward(self, t, direction):
        _, S, U = self.frame(t)
        return math.atan2(U.dot(direction), S.dot(direction))

    def lobe_dirs(self, t, lobes, phase):
        """World-space horizontal directions of the bulges of a section modulated by cos(lobes*theta + phase)."""
        out = []
        C = self.center(t)
        for k in range(lobes):
            d = self.point(t, (TAU * k - phase) / lobes) - C
            d.z = 0.0
            out.append(d.normalized())
        return out

    def radius_at(self, t):
        i, f = self._locate(t)

        def ring_r(r):
            C = self.path[r]
            return sum((p - C).length for p in self.ring_pts[r]) / self.seg
        return lerp(ring_r(i), ring_r(i + 1), f)


def tube(bm, ctrl, ts, shape, segments=10, up_ref=None, first_up=None, twist=0.0,
         start="cap", end="cap", tip_len=0.0, clamp_z=None, jag=0.6, rng=None, lip=(0.12, 0.12), base_z=None):
    """Sweep shape(theta, t) -> (x, y) (x = frame side, y = frame up, in studs) along a Catmull-Rom
    path through ctrl, sampled at arc-length fractions ts. Appends to bm and returns TubeInfo.
    start: 'cap' | 'open' | 'lip' (recessed cut face, see lip=(width, depth))
    end:   'cap' | 'tip' (cone point) | 'jag' (splintered break with a hollow centre) | 'open'.
    base_z: snap the first ring to this height (trunks sit exactly on the ground)."""
    path, _ = resample(catmull_dense(ctrl), ts)
    frs = frames_for(path, up_ref, first_up)
    rings, ring_pts = [], []
    for i, (C, (T, S, U)) in enumerate(zip(path, frs)):
        t = ts[i]
        ring, pts = [], []
        for k in range(segments):
            th = TAU * k / segments + twist * t
            x, y = shape(th, t)
            p = C + S * x + U * y
            if i == 0 and base_z is not None:
                p.z = base_z
            if clamp_z is not None and p.z < clamp_z:
                p.z = clamp_z
            pts.append(p.copy())
            ring.append(bm.verts.new(p))
        rings.append(ring)
        ring_pts.append(pts)
    for i in range(len(rings) - 1):
        for k in range(segments):
            k2 = (k + 1) % segments
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    if start == "cap":
        bm.faces.new(list(reversed(rings[0])))
    elif start == "lip":
        C0, T0 = path[0], frs[0][0]
        r0 = sum((p - C0).length for p in ring_pts[0]) / segments
        s = 1.0 - lip[0] / max(r0, 1e-3)
        lip0 = [bm.verts.new(C0 + (p - C0) * s) for p in ring_pts[0]]
        lip1 = [bm.verts.new(v.co + T0 * lip[1]) for v in lip0]
        for k in range(segments):
            k2 = (k + 1) % segments
            bm.faces.new((rings[0][k], rings[0][k2], lip0[k2], lip0[k]))
            bm.faces.new((lip0[k], lip0[k2], lip1[k2], lip1[k]))
        bm.faces.new(list(reversed(lip1)))
    T_end = frs[-1][0]
    if end == "cap":
        bm.faces.new(rings[-1])
    elif end == "tip":
        tv = bm.verts.new(path[-1] + T_end * tip_len)
        for k in range(segments):
            bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segments], tv))
    elif end == "jag":
        rng = rng or random
        for k, v in enumerate(rings[-1]):
            amt = rng.uniform(0.35, 1.0) if k % 2 == 0 else rng.uniform(-0.35, 0.15)
            v.co += T_end * (jag * amt)
        cv = bm.verts.new(path[-1] - T_end * jag * 0.45)
        for k in range(segments):
            bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segments], cv))
    return TubeInfo(path, frs, ts, ring_pts, segments, twist)


def wrap_patch(bm, tinfo, param, outer, nu, nv, depth=0.08, wrap_v=False):
    """Closed shell hugging a tube: param(u, v) -> (t, theta), outer(u, v) -> outward offset of the
    top surface (negative = sunk into the tube, which hides its ends). The inner surface sits `depth`
    inside the tube, so the patch is watertight and stands proud of the bark (no z-fighting)."""
    cols = nv if wrap_v else nv + 1
    O, I = [], []
    for i in range(nu + 1):
        u = i / nu
        orow, irow = [], []
        for j in range(cols):
            v = j / nv
            t, th = param(u, v)
            orow.append(bm.verts.new(tinfo.point(t, th, max(outer(u, v), -depth * 0.6))))
            irow.append(bm.verts.new(tinfo.point(t, th, -depth)))
        O.append(orow)
        I.append(irow)
    for i in range(nu):
        for j in range(nv):
            j2 = (j + 1) % cols
            bm.faces.new((O[i][j], O[i + 1][j], O[i + 1][j2], O[i][j2]))
            bm.faces.new((I[i][j2], I[i + 1][j2], I[i + 1][j], I[i][j]))
    for j in range(nv):
        j2 = (j + 1) % cols
        bm.faces.new((O[0][j2], O[0][j], I[0][j], I[0][j2]))
        bm.faces.new((O[nu][j], O[nu][j2], I[nu][j2], I[nu][j]))
    if not wrap_v:
        for i in range(nu):
            bm.faces.new((O[i][0], I[i][0], I[i + 1][0], O[i + 1][0]))
            bm.faces.new((O[i + 1][nv], I[i + 1][nv], I[i][nv], O[i][nv]))


def conform_blob(bm, tinfo, tc, thc, half_t, half_th, height, sink, rng, below=None, subdiv=2, wob=0.22):
    """Moss cushion: an icosphere mapped onto a tube surface (x -> along, y -> around, z -> outward).
    Its lower half is buried in the wood, so only a soft irregular cushion shows - no floating edges."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = rvec(rng)
    below = height if below is None else below
    for v in res["verts"]:
        n = v.co.normalized()
        s = 1.0 + wob * noise.noise(n * 1.7 + off)
        x, y, z = n.x * s, n.y * s, n.z * s
        h = (z * height if z > 0 else z * below) - sink
        v.co = tinfo.point(tc + x * half_t, thc + y * half_th, h)
    return res["verts"]


# ================================================================================================
# Foliage clouds (canopies, bushes), lathes, small solids
# ================================================================================================
def floret_into(bm, c, radii, rng, subdiv=2, amp=0.2, under=0.35, floor=None, drip=0.0):
    """One leaf clump: a noisy icosphere, squashed underneath (or pulled into a hanging drip)."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = rvec(rng)
    yaw = rng.uniform(0.0, TAU)
    cy, sy = math.cos(yaw), math.sin(yaw)
    c = Vector(c)
    for v in res["verts"]:
        n = v.co.normalized()
        s = 1.0 + amp * noise.noise(n * 1.9 + off)
        p = Vector((n.x * radii[0], n.y * radii[1], n.z * radii[2])) * s
        if p.z < 0.0:
            if drip > 0.0:
                k = -n.z
                p.x *= 1.0 - drip * 0.4 * k
                p.y *= 1.0 - drip * 0.4 * k
                p.z *= 1.0 + drip
            else:
                p.z *= (1.0 - under)
        p = Vector((p.x * cy - p.y * sy, p.x * sy + p.y * cy, p.z)) + c
        if floor is not None and p.z < floor:
            p.z = floor
        v.co = p
    return res["verts"]


def cloud_into(bm, center, radii, n, r_lo, r_hi, rng, z_min=-0.35, flat=0.85, under=0.35, floor=None,
               core=True, core_under=0.55, drip=0.0, subdiv=2, spread=0.78, skip=0.0, groups=None, split_z=None):
    """Foliage cloud: n florets spread (golden-angle) over the upper part of an ellipsoid envelope, bigger
    low down and smaller on top, around a squashed core. Reads as a dense clump of leafy lobes.
    skip: chance to leave a floret out (airy crowns with holes). groups + split_z: florets below split_z
    go to groups[0], the rest to groups[1] (two-tone canopies); otherwise everything goes to bm."""
    ga = math.pi * (3.0 - math.sqrt(5.0))
    c = Vector(center)
    a0 = rng.uniform(0.0, TAU)
    for i in range(n):
        z = 1.0 - (i + 0.5) / n * (1.0 - z_min)
        rr = math.sqrt(max(0.0, 1.0 - z * z))
        a = a0 + i * ga + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a) * rr * radii[0], math.sin(a) * rr * radii[1], z * radii[2])) * spread
        r = lerp(r_hi, r_lo, (z - z_min) / (1.0 - z_min)) * rng.uniform(0.85, 1.15)
        if skip > 0.0 and i > 0 and rng.random() < skip:
            continue
        target = bm
        if groups is not None:
            target = groups[0] if (c + d).z < split_z else groups[1]
        floret_into(target, c + d, (r, r * rng.uniform(0.85, 1.0), r * flat), rng, subdiv=subdiv, under=under,
                    floor=floor, drip=drip)
    if core:
        floret_into(bm if groups is None else groups[0], c, (radii[0] * 0.8, radii[1] * 0.8, radii[2] * 0.8), rng,
                    subdiv=1, amp=0.1, under=core_under, floor=floor)


def lathe_into(bm, profile, segments, mat=None, phase=0.0):
    """Revolve (radius, z) points (bottom to top) around local Z, transformed by mat. r = 0 makes a pole."""
    mat = mat or Matrix.Identity(4)
    rings = []
    for (r, z) in profile:
        if r < 1e-4:
            rings.append([bm.verts.new(mat @ Vector((0.0, 0.0, z)))])
        else:
            rings.append([bm.verts.new(mat @ Vector((r * math.cos(TAU * i / segments + phase),
                                                     r * math.sin(TAU * i / segments + phase), z)))
                          for i in range(segments)])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segments):
            j = (i + 1) % segments
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    return rings


def ellipsoid_into(bm, center, radii, normal=None, subdiv=1, rng=None, jitter=0.0):
    """Small icosphere-based ellipsoid (berries, mushroom spots) aligned so local Z = normal."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    m = aim_matrix(center, normal) if normal is not None else Matrix.Translation(Vector(center))
    for v in res["verts"]:
        p = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2]))
        if rng is not None and jitter > 0:
            p += Vector((rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter)))
        v.co = m @ p
    return res["verts"]


# ================================================================================================
# PINES
# ================================================================================================
def pine_tier(bm, c, R, h, droop, N, rot, rng, light, asym):
    """One drooping whorl of N scalloped branch clumps: ridged top, thick drooping rim, hollow underside.
    Rings: A (upper ridge, 2/clump), B1 (rim top, 4/clump: valley, shoulder, tip, shoulder),
    B2 (rim bottom, 2/clump), C (underside, 2/clump). ~20 triangles per clump."""
    w = TAU / N
    rim = clamp(R * 0.1, 0.3, 0.75)
    ks = [rng.uniform(0.86, 1.12) if rng.random() > 0.15 else rng.uniform(0.7, 0.8) for _ in range(N)]
    apex = bm.verts.new(c + Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), h)))
    under = bm.verts.new(c + UP * (h * 0.28))
    A, B1, B2, C = [], [], [], []

    def grow(ang):
        return 1.0 + asym * math.cos(ang - light)

    for j in range(N):
        a = rot + j * w + rng.uniform(-0.1, 0.1) * w
        k = ks[j]
        kv = 0.5 * (ks[j] + ks[j - 1])
        av = a - w * 0.5
        dv, dl, dt, dr = hdir(av), hdir(a - w * 0.25), hdir(a), hdir(a + w * 0.25)
        rv = R * 0.66 * kv * grow(av)
        rt = R * k * grow(a)
        rs = rt * 0.9
        dz = droop * k * rng.uniform(0.9, 1.15)
        zv = -droop * 0.42 + h * 0.1
        B1 += [c + dv * rv + UP * zv, c + dl * rs + UP * (-dz * 0.84), c + dt * rt + UP * (-dz),
               c + dr * rs + UP * (-dz * 0.84)]
        B2 += [c + dv * (rv * 0.95) + UP * (zv - rim * 0.8), c + dt * (rt * 0.95) + UP * (-dz - rim)]
        A += [c + dv * (rv * 0.6) + UP * (h * 0.47), c + dt * (rt * 0.5) + UP * (h * 0.57)]
        C += [c + dv * (rv * 0.55) + UP * (h * 0.14), c + dt * (rt * 0.55) + UP * lerp(-dz - rim, h * 0.25, 0.55)]
    A = [bm.verts.new(p) for p in A]
    B1 = [bm.verts.new(p) for p in B1]
    B2 = [bm.verts.new(p) for p in B2]
    C = [bm.verts.new(p) for p in C]
    F = bm.faces.new
    for j in range(N):
        n = (j + 1) % N
        av, at, avn = A[2 * j], A[2 * j + 1], A[2 * n]
        bv, bl, bt, br, bvn = B1[4 * j], B1[4 * j + 1], B1[4 * j + 2], B1[4 * j + 3], B1[4 * n]
        cv, ct, cvn = B2[2 * j], B2[2 * j + 1], B2[2 * n]
        uv_, ut, uvn = C[2 * j], C[2 * j + 1], C[2 * n]
        F((apex, av, at))
        F((apex, at, avn))
        F((av, bv, bl))
        F((av, bl, at))
        F((at, bl, bt))
        F((at, bt, br))
        F((at, br, avn))
        F((avn, br, bvn))
        F((bv, cv, bl))
        F((bl, cv, ct))
        F((bl, ct, bt))
        F((bt, ct, br))
        F((br, ct, cvn))
        F((br, cvn, bvn))
        F((cv, uv_, ut, ct))
        F((ct, ut, uvn, cvn))
        F((under, ut, uv_))
        F((under, uvn, ut))
    return [apex, under] + A + B1 + B2 + C


def build_pine(name, seed, H, base_r, z0, R0, R1, K, lean, rgbs, bark_rgb=None, droop=0.3,
               asym=0.12, spire=3.6, notes=""):
    rng = random.Random(seed)
    root = lib.begin(name, kind="Tree", tags=[], notes=notes)
    la = rng.uniform(0.0, TAU)
    lean_v = hdir(la) * lean
    wob_v = hdir(la + math.pi / 2) * rng.uniform(0.2, 0.45)

    def centre(z):
        s = clamp(z / H, 0.0, 1.0)
        off = lean_v * (s ** 1.7) + wob_v * (math.sin(s * math.pi * 1.4) * s)
        return Vector((off.x, off.y, z))

    # --- trunk (collides, Hull) ---
    top = H - spire * 0.35
    ctrl = [Vector((0, 0, 0)), Vector((0, 0, 1.4))] + [centre(top * f) for f in (0.2, 0.4, 0.6, 0.8, 1.0)]
    ts = [0.0, 0.012, 0.03, 0.06, 0.1, 0.16, 0.24, 0.34, 0.46, 0.58, 0.7, 0.82, 0.92, 1.0]
    ph = rng.uniform(0.0, TAU)

    def tshape(th, t):
        z = t * top
        r = base_r * (1.0 - 0.86 * t ** 0.85)
        r *= 1.0 + 0.4 * math.exp(-z / 1.0)
        r *= 1.0 + 0.07 * math.sin(3 * th + ph) * (1.0 - t)
        return (math.cos(th) * r, math.sin(th) * r)

    bm = bmesh.new()
    tube(bm, ctrl, ts, tshape, segments=9, end="tip", tip_len=1.0, base_z=0.0)
    lib.add(root, finish_bm(bm, name + "_trunk"), "Bark", rgb=bark_rgb, collide=True, collision="Hull",
            smooth_angle=55)

    # --- root flare diving into the ground + dead twig stubs (walk-through detail) ---
    bm = bmesh.new()
    n = rng.randint(5, 6)
    for i in range(n):
        a = ph + TAU * i / n + rng.uniform(-0.3, 0.3)
        d = hdir(a)
        reach = base_r * rng.uniform(1.9, 2.5)
        h0 = base_r * rng.uniform(1.3, 1.8)
        rr = base_r * rng.uniform(0.36, 0.46)
        c = [d * 0.15 + UP * h0, d * (base_r * 0.95) + UP * (h0 * 0.45), d * (reach * 0.78) + UP * 0.12,
             d * reach - UP * 0.45]
        tube(bm, c, [0.0, 0.3, 0.6, 0.85, 1.0], taper_shape(rr, 0.55, 1.35, 0.8), segments=6, up_ref=UP,
             end="cap", clamp_z=0.0)
    for i in range(rng.randint(2, 4)):
        z = rng.uniform(2.6, max(3.0, z0 - 1.8))
        d = hdir(rng.uniform(0.0, TAU))
        c0 = centre(z)
        L = rng.uniform(0.8, 1.5)
        tube(bm, [c0, c0 + d * (base_r * 0.7 + L) + UP * rng.uniform(-0.35, 0.1)], [0.0, 1.0],
             taper_shape(rng.uniform(0.09, 0.14), 0.5), segments=5, end="tip", tip_len=0.15)
    clamp_bm(bm, 0.0)
    lib.add(root, finish_bm(bm, name + "_roots"), "Bark", rgb=bark_rgb, collide=False, smooth_angle=50)

    # --- canopy: K drooping whorls in three tones (darker at the bottom) ---
    groups = [bmesh.new(), bmesh.new(), bmesh.new()]
    light = rng.uniform(0.0, TAU)
    tb = H - spire
    rot = rng.uniform(0.0, TAU)
    for k in range(K):
        f = k / (K - 1)
        z = z0 + (tb - z0) * f ** 0.92
        R = lerp(R0, R1, f ** 0.95) * rng.uniform(0.9, 1.1)
        h = max(1.9, R * rng.uniform(0.6, 0.7))
        dr = R * droop * (1.0 - 0.4 * f) * rng.uniform(0.85, 1.15)
        N = int(clamp(round(R * 1.15), 5, 9))
        rot += math.pi / N + rng.uniform(-0.3, 0.3)
        c = centre(z) + hdir(rng.uniform(0.0, TAU)) * rng.uniform(0.0, 0.25)
        g = 0 if f < 0.3 else (1 if f < 0.65 else 2)
        vs = pine_tier(groups[g], c, R, h, dr, N, rot, rng, light, asym)
        tilt = Euler((rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07), 0.0)).to_matrix()
        for v in vs:
            v.co = c + tilt @ (v.co - c)
    c = centre(tb - 0.6)
    tube(groups[2], [c, centre(H - 0.8)], [0.0, 0.5, 1.0], taper_shape(0.8, 0.8), segments=6,
         end="tip", tip_len=0.8)
    for g, rgb in enumerate(rgbs):
        obj = finish_bm(groups[g], name + "_needles%d" % g, triangulate=True)
        ls.jitter(obj, 0.08, rng)
        lib.add(root, obj, "PineNeedles", rgb=rgb, collide=False)
    lib.finish(root)


# ================================================================================================
# OAKS
# ================================================================================================
BRANCH_SEG = 10
# 10-vertex chunky section at theta = 0, 36, 72 ... deg (x = side, y = up). Vertices 2 and 3 form a LEVEL top
# face 1.64 * half-width wide (the standing surface); rounded shoulders, rounder belly.
BRANCH_SECTION = [(1.0, 0.0), (0.97, 0.6), (0.82, 0.97), (-0.82, 0.97), (-0.97, 0.6),
                  (-1.0, 0.0), (-0.85, -0.62), (-0.38, -0.97), (0.38, -0.97), (0.85, -0.62)]


def flat_top_branch_shape(w):
    """Standable branch: flat-topped section near the trunk, blending to round toward the tip."""
    def shape(th, t):
        a = w * interp([1.12, 1.06, 1.02, 0.95, 0.75, 0.52, 0.32], t)
        b = w * 0.8 * interp([1.05, 0.95, 0.86, 0.78, 0.62, 0.45, 0.3], t)
        k = int(round(th / (TAU / BRANCH_SEG))) % BRANCH_SEG
        sx, sy = BRANCH_SECTION[k]
        blend = smoothstep(0.5, 0.8, t)
        th_k = TAU * k / BRANCH_SEG
        x = lerp(sx, math.cos(th_k), blend)
        y = lerp(sy, math.sin(th_k), blend)
        return (a * x, b * y)
    return shape


def build_oak(name, seed, trunk_r, top_z, branches, crown, rgbs, canopy_tris, bark_rgb=None, notes=""):
    """branches: list of (base height, azimuth deg, reach, tip rise, width)."""
    rng = random.Random(seed)
    root = lib.begin(name, kind="Tree", tags=[], notes=notes)
    la = rng.uniform(0.0, TAU)
    lv = hdir(la) * rng.uniform(0.5, 0.9)
    pv = hdir(la + math.pi / 2) * rng.uniform(0.2, 0.4)

    def centre(z):
        s = clamp(z / top_z, 0.0, 1.0)
        off = lv * (s * s) + pv * math.sin(math.pi * s)
        return Vector((off.x, off.y, z))

    bm = bmesh.new()
    ctrl = [Vector((0, 0, 0)), Vector((0, 0, 1.5))] + [centre(top_z * f) for f in (0.3, 0.55, 0.8, 1.0)]
    ts = [0.0, 0.012, 0.03, 0.06, 0.1, 0.16, 0.24, 0.34, 0.45, 0.57, 0.7, 0.82, 0.92, 1.0]
    ph, ph2 = rng.uniform(0.0, TAU), rng.uniform(0.0, TAU)

    def tshape(th, t):
        z = t * top_z
        r = trunk_r * interp([1.0, 0.95, 0.9, 0.78, 0.55, 0.32], t)
        r *= 1.0 + 0.42 * math.exp(-z / 1.3)
        lobe = max(0.0, math.cos(5 * th + ph)) ** 2
        r *= 1.0 + 0.2 * math.exp(-z / 2.0) * lobe + 0.05 * math.sin(3 * th + ph2 + z * 0.4)
        return (math.cos(th) * r, math.sin(th) * r)

    trunk = tube(bm, ctrl, ts, tshape, segments=12, end="tip", tip_len=1.0, base_z=0.0)

    # main standable branches
    tips = []
    for i, (hb, az, reach, rise, w) in enumerate(branches):
        a = math.radians(az) + rng.uniform(-0.08, 0.08)
        d, sd = hdir(a), hdir(a + math.pi / 2)
        c0 = centre(hb)
        ctrl = [c0 - d * 0.3,
                c0 + d * (trunk_r * 0.9 + 0.9) + UP * 0.3,
                c0 + d * (reach * 0.5) + UP * 0.85 + sd * rng.uniform(-0.4, 0.4),
                c0 + d * (reach * 0.76) + UP * (rise * 0.38) + sd * rng.uniform(-0.6, 0.6),
                c0 + d * (reach * 0.92) + UP * (rise * 0.72) + sd * rng.uniform(-0.6, 0.6),
                c0 + d * reach + UP * rise + sd * rng.uniform(-0.5, 0.5)]
        info = tube(bm, ctrl, [0.0, 0.11, 0.22, 0.34, 0.47, 0.6, 0.74, 0.88, 1.0], flat_top_branch_shape(w),
                    segments=BRANCH_SEG, up_ref=UP, end="tip", tip_len=0.8)
        tips.append((info, d, sd, reach))
        lib.attach(root, "Perch%d" % (i + 1), info.point(0.3, math.pi / 2), look=d, up=UP)
        # verify the standing surface on the built rings: level top face = ring vertices 2 and 3
        rep = []
        for r in range(1, 5):
            p2, p3 = info.ring_pts[r][2], info.ring_pts[r][3]
            rep.append("%.2f@z%.1f(dz%.2f)" % ((p2 - p3).length, (p2.z + p3.z) / 2, abs(p2.z - p3.z)))
        print("PERCH %s branch %d: flat top width@height along branch: %s" % (name, i + 1, " ".join(rep)))
        # secondary limb rising into the canopy
        p = info.center(0.62)
        ldir = (d * 0.6 + UP + sd * rng.uniform(-0.6, 0.6)).normalized()
        L = rng.uniform(3.5, 5.0)
        tube(bm, [p, p + ldir * (L * 0.5) + d * 0.4, p + ldir * L + d * 0.9], [0.0, 0.35, 0.7, 1.0],
             taper_shape(w * 0.42, 0.65), segments=6, end="tip", tip_len=0.5)

    # upper forks of the leader
    fork_base = centre(top_z * 0.76)
    a0 = rng.uniform(0.0, TAU)
    for k in range(2):
        a = a0 + math.pi * k + rng.uniform(-0.4, 0.4)
        dd = (hdir(a) * 0.75 + UP).normalized()
        L = rng.uniform(5.0, 6.5)
        tube(bm, [fork_base, fork_base + dd * (L * 0.5), fork_base + dd * L + hdir(a) * 1.0],
             [0.0, 0.33, 0.66, 1.0], taper_shape(trunk_r * 0.36, 0.7), segments=7, end="tip", tip_len=0.6)
    lib.add(root, finish_bm(bm, name + "_wood"), "Bark", rgb=bark_rgb, collide=True,
            collision="PreciseConvexDecomposition", tags=["Climbable"], smooth_angle=60)

    # buttress roots diving into the ground (walk-through, so feet never snag)
    bm = bmesh.new()
    for d in trunk.lobe_dirs(0.01, 5, ph):
        d = (d + hdir(rng.uniform(0.0, TAU)) * 0.12).normalized()
        reach = trunk_r * rng.uniform(2.0, 2.6)
        h0 = trunk_r * rng.uniform(1.0, 1.4)
        rr = trunk_r * rng.uniform(0.34, 0.42)
        c = [d * 0.3 + UP * h0, d * (trunk_r * 1.1) + UP * (h0 * 0.5), d * (reach * 0.78) + UP * 0.15,
             d * reach - UP * 0.5]
        tube(bm, c, [0.0, 0.33, 0.7, 1.0], taper_shape(rr, 0.55, 1.4, 0.75), segments=6, up_ref=UP,
             end="cap", clamp_z=0.0)
    clamp_bm(bm, 0.0)
    lib.add(root, finish_bm(bm, name + "_roots"), "Bark", rgb=bark_rgb, collide=False, smooth_angle=55)

    # canopy: leafy clouds over each branch (darker), crown + fillers on top (lighter)
    groups = [bmesh.new(), bmesh.new()]
    tip_z = []
    for info, d, sd, reach in tips:
        tip = info.center(1.0)
        tip_z.append(tip.z)
        cc = tip + UP * rng.uniform(1.2, 1.9) - d * rng.uniform(0.6, 1.2)
        rx = rng.uniform(4.3, 5.0)
        cloud_into(groups[0], cc, (rx, rx * rng.uniform(0.85, 0.95), rx * 0.62), 7, 1.9, 2.6, rng, z_min=-0.3)
    ct = centre(top_z) + UP * (crown[2] * 0.3)
    cloud_into(groups[1], ct, crown, 10, 2.1, 2.8, rng, z_min=-0.2)
    order = sorted(tips, key=lambda e: math.atan2(e[1].y, e[1].x))
    n = len(order)
    avg_reach = sum(e[3] for e in tips) / n
    avg_tip = sum(tip_z) / n
    for i in range(n):
        a1 = math.atan2(order[i][1].y, order[i][1].x)
        a2 = math.atan2(order[(i + 1) % n][1].y, order[(i + 1) % n][1].x)
        if a2 <= a1:
            a2 += TAU
        am = (a1 + a2) / 2 + rng.uniform(-0.15, 0.15)
        cc = centre(avg_tip) + hdir(am) * (avg_reach * rng.uniform(0.45, 0.58))
        cc.z = avg_tip + rng.uniform(2.6, 3.6)
        r = rng.uniform(3.4, 4.0)
        cloud_into(groups[1], cc, (r, r * 0.9, r * 0.7), 4, 1.8, 2.3, rng, z_min=-0.2)
    for g, rgb in enumerate(rgbs):
        obj = foliage_mesh(groups[g], name + "_leaves%d" % g, canopy_tris[g], 0.2, rng, jitter=0.1)
        lib.add(root, obj, "Leaves", rgb=rgb, collide=False)
    lib.finish(root)


# ================================================================================================
# BIRCHES
# ================================================================================================
def build_birch(name, seed, stems, rgbs, canopy_tris, band_rgb=(58, 54, 50), notes=""):
    """stems: list of (height, lean azimuth deg, lean amount, base offset, base radius, branches, bands)."""
    rng = random.Random(seed)
    root = lib.begin(name, kind="Tree", tags=[], notes=notes)
    infos = []
    for (H, laz, lean, boff, r0, nbr, nband) in stems:
        la = math.radians(laz)
        lv = hdir(la) * lean
        pv = hdir(la + math.pi / 2) * rng.uniform(-0.5, 0.5)
        base = hdir(la) * boff

        def centre(z, H=H, lv=lv, pv=pv, base=base):
            s = clamp(z / H, 0.0, 1.0)
            off = base + lv * (s ** 1.4) + pv * math.sin(s * math.pi * 1.6)
            return Vector((off.x, off.y, z))

        top = H - 1.2
        ctrl = [base.copy(), base + UP * 1.0] + [centre(top * f) for f in (0.25, 0.5, 0.75, 1.0)]
        ts = [0.0, 0.02, 0.05, 0.1, 0.2, 0.32, 0.45, 0.58, 0.72, 0.86, 1.0]
        bm = bmesh.new()

        def tshape(th, t, r0=r0, top=top):
            z = t * top
            r = r0 * (1.0 - 0.8 * t) * (1.0 + 0.3 * math.exp(-z / 0.7))
            return (math.cos(th) * r, math.sin(th) * r)

        info = tube(bm, ctrl, ts, tshape, segments=8, end="tip", tip_len=1.2, base_z=0.0)
        lib.add(root, finish_bm(bm, name + "_stem"), "BirchBark", collide=True, collision="Hull", smooth_angle=50)
        infos.append((info, H, la, nbr, nband))

    # thin weeping branches (walk-through) + small leafy clouds hanging from them
    bmb = bmesh.new()
    groups = [bmesh.new(), bmesh.new()]
    for info, H, la, nbr, nband in infos:
        a = rng.uniform(0.0, TAU)
        for i in range(nbr):
            t = lerp(0.4, 0.86, i / max(1, nbr - 1)) + rng.uniform(-0.03, 0.03)
            a += 2.4 + rng.uniform(-0.4, 0.4)
            d = (hdir(a) + hdir(la) * 0.3).normalized()
            el = rng.uniform(0.55, 0.95)
            L = rng.uniform(2.6, 4.2) * (1.15 - 0.5 * (t - 0.4))
            p = info.center(t)
            dirv = (d * math.cos(el) + UP * math.sin(el)).normalized()
            mid = p + dirv * (L * 0.55)
            tipp = p + dirv * L + d * 0.6 - UP * 0.4
            tube(bmb, [p, mid, tipp], [0.0, 0.5, 1.0], taper_shape(rng.uniform(0.13, 0.17), 0.6),
                 segments=5, end="tip", tip_len=0.4)
            # a drooping leaf clump hanging off each branch tip; gaps between clumps keep the crown airy
            r = rng.uniform(1.5, 1.9) * (1.1 - 0.35 * (t - 0.4))
            g = 0 if t < 0.62 else 1
            cloud_into(groups[g], tipp - UP * 0.2, (r, r * 0.9, r * 1.05), 6, 0.75, 1.0, rng, z_min=-0.7,
                       drip=0.3, spread=0.6, core_under=0.2)
        # leader clumps: one on top and one hugging the upper stem
        for (t, r) in ((1.0, 2.0), (0.8, 1.6)):
            c = info.center(t) + UP * (0.5 if t == 1.0 else 0.0) + hdir(rng.uniform(0.0, TAU)) * 0.4
            cloud_into(groups[1], c, (r, r * 0.9, r * 1.2), 6, 0.8, 1.05, rng, z_min=-0.7, drip=0.3, spread=0.6,
                       core_under=0.2)
    lib.add(root, finish_bm(bmb, name + "_twigs"), "BirchBark", collide=False, smooth_angle=50)

    # dark lenticel bands and a dark rough base (second bark part, proud of the trunk -> no z-fighting)
    bmd = bmesh.new()
    for info, H, la, nbr, nband in infos:
        off = rvec(rng)

        def sock_param(u, v, off=off):
            top = 0.035 + 0.045 * (0.5 + 0.5 * noise.noise(Vector((math.cos(v * TAU) * 1.4, math.sin(v * TAU) * 1.4, 0.0)) + off))
            return (u * top, v * TAU)

        wrap_patch(bmd, info, sock_param, lambda u, v: 0.06 if u < 0.99 else 0.02, 1, 8, depth=0.06, wrap_v=True)
        for i in range(nband):
            tc = lerp(0.07, 0.72, (i + rng.uniform(0.15, 0.85)) / nband)
            span = rng.uniform(2.0, 3.6)
            th0 = rng.uniform(0.0, TAU)
            hgt = rng.uniform(0.36, 0.62)
            boff = rvec(rng)

            def band_param(u, v, tc=tc, span=span, th0=th0, hgt=hgt, boff=boff, H=H):
                jag = 0.5 * noise.noise(Vector((v * 3.0, u * 2.0, 0.0)) + boff)
                return (tc + (u - 0.5) * (hgt / H) * (1.0 + jag), th0 + span * v)

            def band_outer(u, v):
                e = smoothstep(0.0, 0.25, v) * smoothstep(1.0, 0.75, v)
                return lerp(-0.03, 0.06, e)

            wrap_patch(bmd, info, band_param, band_outer, 1, 3, depth=0.06)
    lib.add(root, finish_bm(bmd, name + "_bands"), "Bark", rgb=band_rgb, collide=False, smooth_angle=40)

    for g, rgb in enumerate(rgbs):
        obj = foliage_mesh(groups[g], name + "_leaves%d" % g, canopy_tris[g], 0.13, rng, jitter=0.05)
        lib.add(root, obj, "BirchLeaves", rgb=rgb, collide=False)
    lib.finish(root)


# ================================================================================================
# DEAD TREES (swamp snags)
# ================================================================================================
def build_dead(name, seed, H, r0, lean, nbranch, mossy, rgb=None, moss_rgb=None, notes=""):
    rng = random.Random(seed)
    root = lib.begin(name, kind="Tree", tags=[], notes=notes)
    la = rng.uniform(0.0, TAU)
    lean_dir = hdir(la)
    lean_v = lean_dir * lean
    w1 = rvec(rng)

    def centre(z):
        s = clamp(z / H, 0.0, 1.0)
        off = lean_v * (s ** 1.3)
        off = off + Vector((noise.noise(Vector((s * 2.6, 0.0, 0.0)) + w1),
                            noise.noise(Vector((0.0, s * 2.6, 0.0)) + w1), 0.0)) * (1.3 * s)
        return Vector((off.x, off.y, z))

    ctrl = [Vector((0, 0, 0)), Vector((0, 0, 1.0))] + [centre(H * f) for f in (0.2, 0.36, 0.52, 0.68, 0.84, 1.0)]
    ts = [0.0, 0.02, 0.05, 0.1, 0.17, 0.26, 0.36, 0.47, 0.58, 0.7, 0.82, 0.92, 1.0]
    ph = rng.uniform(0.0, TAU)

    def tshape(th, t):
        z = t * H
        r = r0 * interp([1.0, 0.86, 0.72, 0.6, 0.48, 0.4], t) * (1.0 + 0.5 * math.exp(-z / 1.5))
        lobe = max(0.0, math.cos(5 * th + ph)) ** 2
        r *= (1.0 + 0.3 * math.exp(-z / 1.6) * lobe + 0.14 * math.sin(4 * th + ph) * (1.0 - math.exp(-z / 2.0))
              + 0.06 * math.sin(7 * th + ph * 2.0))
        return (math.cos(th) * r, math.sin(th) * r)

    bm = bmesh.new()
    trunk = tube(bm, ctrl, ts, tshape, segments=8, twist=1.8, end="jag", jag=1.0, rng=rng, base_z=0.0)
    lib.add(root, finish_bm(bm, name + "_trunk"), "DeadWood", rgb=rgb, collide=True, collision="Hull",
            smooth_angle=50)

    # gnarled bare limbs (two thick, the rest thinner) with forks, broken stubs, swamp roots (walk-through)
    bm = bmesh.new()
    branch_infos = []
    a = rng.uniform(0.0, TAU)
    for i in range(nbranch):
        t = lerp(0.36, 0.86, i / max(1, nbranch - 1)) + rng.uniform(-0.03, 0.03)
        a += 2.3 + rng.uniform(-0.5, 0.5)
        d = hdir(a)
        thick = i < 2
        el = rng.uniform(0.45, 0.8) if thick else rng.uniform(0.3, 0.7)
        L = rng.uniform(5.2, 7.0) * (1.12 - 0.42 * t) * (1.1 if thick else 0.85)
        p0 = trunk.center(t)
        dirv = (d * math.cos(el) + UP * math.sin(el)).normalized()
        side = d.cross(UP).normalized()
        ctrl = [p0]
        for k, s in enumerate((0.3, 0.55, 0.8, 1.0)):
            q = p0 + dirv * (L * s) + side * (L * 0.12 * s * (1 if k % 2 == 0 else -1) * rng.uniform(0.5, 1.2))
            q += UP * (L * s * s * (0.25 if thick else 0.05))
            ctrl.append(q)
        rr = trunk.radius_at(t) * (0.62 if thick else 0.42)
        info = tube(bm, ctrl, [0.0, 0.25, 0.5, 0.75, 1.0], taper_shape(rr, 0.78), segments=6 if thick else 5,
                    up_ref=UP, end="tip", tip_len=0.6)
        branch_infos.append((info, L))
        for j in range(2 if thick else 1):
            tf = rng.uniform(0.4, 0.66)
            pf = info.center(tf)
            Tf = info.frame(tf)[0]
            sd = runit(rng)
            sd = (sd - Tf * sd.dot(Tf)).normalized()
            df = (Tf * 0.6 + sd * 0.6 + UP * 0.45).normalized()
            Lf = L * rng.uniform(0.4, 0.6)
            tube(bm, [pf, pf + df * (Lf * 0.5) + runit(rng) * 0.25, pf + df * Lf], [0.0, 0.5, 1.0],
                 taper_shape(rr * (1.0 - 0.78 * tf) * 0.85, 0.7), segments=5, end="tip", tip_len=0.4)
    for k in range(2):
        t = rng.uniform(0.2, 0.3) if k == 0 else rng.uniform(0.55, 0.68)
        p0 = trunk.center(t)
        d = hdir(rng.uniform(0.0, TAU))
        rr = trunk.radius_at(t) * 0.45
        tube(bm, [p0, p0 + d * (trunk.radius_at(t) + 0.8) + UP * 0.3], [0.0, 0.5, 1.0], taper_shape(rr, 0.25),
             segments=6, end="jag", jag=0.35, rng=rng)
    for d in trunk.lobe_dirs(0.02, 5, ph):
        d = (d + hdir(rng.uniform(0.0, TAU)) * 0.15).normalized()
        reach = rng.uniform(2.5, 3.1) * r0
        rr = r0 * rng.uniform(0.4, 0.48)
        c = [d * (r0 * 0.7) + UP * 1.4, d * (r0 * 1.35) + UP * 0.6, d * (reach * 0.8) + UP * 0.1, d * reach - UP * 0.45]
        tube(bm, c, [0.0, 0.33, 0.7, 1.0], taper_shape(rr, 0.5, 1.25, 0.9), segments=5, up_ref=UP, end="cap",
             clamp_z=0.0)
    clamp_bm(bm, 0.0)
    lib.add(root, finish_bm(bm, name + "_limbs"), "DeadWood", rgb=rgb, collide=False, smooth_angle=50)

    if mossy:
        bm = bmesh.new()
        # cushions around the wet base, between the buttress lobes
        for k in range(3):
            thc = TAU * k / 3 + rng.uniform(-0.3, 0.3)
            conform_blob(bm, trunk, rng.uniform(0.04, 0.06), thc, 1.6 / H, 1.1, 0.32, 0.08, rng, below=0.35)
        # cushions on the upper (leaning) face of the trunk
        for tc in (0.26, 0.46):
            thc = trunk.theta_toward(tc, lean_dir + UP * 0.3) + rng.uniform(-0.3, 0.3)
            conform_blob(bm, trunk, tc, thc, 1.6 / H, 1.0, 0.26, 0.06, rng, below=0.3)
        # moss on top of the first thick limb and beards hanging below the lower limbs
        for info, L in branch_infos[:1]:
            conform_blob(bm, info, 0.28, math.pi / 2, 1.6 / L, 1.0, 0.2, 0.05, rng, below=0.14)
        # hanging moss: tufts of 2-3 thin strands of uneven length under the lower limbs
        for bi, (info, L) in enumerate(branch_infos[:3]):
            for k in range(3 if bi < 2 else 1):
                tt = lerp(0.25, 0.7, (k + rng.uniform(0.2, 0.8)) / 3.0)
                p = info.point(tt, -math.pi / 2, -0.06)
                hl = rng.uniform(1.4, 3.4)
                sway = hdir(rng.uniform(0.0, TAU)) * rng.uniform(0.15, 0.35)
                tube(bm, [p, p - UP * (hl * 0.5) + sway, p - UP * hl + sway * 0.3], [0.0, 0.5, 1.0],
                     taper_shape(rng.uniform(0.1, 0.14), 0.45), segments=4, end="tip", tip_len=0.35)
        lib.add(root, finish_bm(bm, name + "_moss"), "Moss", rgb=moss_rgb, collide=False)
    lib.finish(root)


# ================================================================================================
# BUSHES
# ================================================================================================
def build_bush(name, seed, W, D, H, n, r_lo, r_hi, rgb, tris=570, berries=0, kind="Bush", notes=""):
    """Dome-shaped leafy cloud W x D x H resting on the ground. berries: number of red berry clusters."""
    rng = random.Random(seed)
    root = lib.begin(name, kind=kind, tags=[], notes=notes)
    bm = bmesh.new()
    cloud_into(bm, (0.0, 0.0, H * 0.42), (W * 0.475, D * 0.475, H * 0.58), n, r_lo, r_hi, rng, z_min=-0.55,
               floor=0.0, under=0.3, subdiv=3)
    obj = foliage_mesh(bm, name + "_bush", tris, 0.14, rng, jitter=0.04, floor=0.0)
    obj = lib.add(root, obj, "Bush", rgb=rgb, collide=False)
    if berries:
        me = obj.data
        bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        top = max(v.co.z for v in me.vertices)
        bmb = bmesh.new()
        a = rng.uniform(0.0, TAU)
        made = 0
        tries = 0
        while made < berries and tries < berries * 6:
            tries += 1
            a += 2.4 + rng.uniform(-0.3, 0.3)
            el = lerp(0.05, 0.95, (made + 0.5) / berries) + rng.uniform(-0.1, 0.1)
            d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
            target = Vector((0.0, 0.0, top * 0.45))
            hit, nrm, _, _ = bvh.ray_cast(target + d * 20.0, -d)
            if hit is None or hit.z < 0.7:
                continue
            made += 1
            t1 = nrm.orthogonal().normalized()
            t2 = nrm.cross(t1).normalized()
            for b in range(rng.randint(3, 5)):
                ang = TAU * b / 4.0 + rng.uniform(-0.4, 0.4)
                q = hit + (t1 * math.cos(ang) + t2 * math.sin(ang)) * (0.0 if b == 0 else rng.uniform(0.3, 0.45))
                h2, n2, _, _ = bvh.ray_cast(q + nrm * 2.0, -nrm)
                if h2 is None:
                    continue
                r = rng.uniform(0.25, 0.32)
                # subdiv=1 is already the 20-tri icosahedron (Blender clamps 0 to 1): 42 berries = 840 tris. Kept as is
                # on purpose (art-direction review): the clusters are the forage read; place BerryBush sparsely.
                ellipsoid_into(bmb, h2 + n2 * (r * 0.55), (r, r, r * 0.92), n2, subdiv=1, rng=rng, jitter=0.025)
        lib.add(root, finish_bm(bmb, name + "_berries"), "Berry", collide=False, smooth_angle=80)
    lib.finish(root)


# ================================================================================================
# GROUND PLANTS
# ================================================================================================
def frond_into(bm, P0, P1, P2, width, rows=10, th=0.045, droop=0.32, notch=0.38):
    """Fern frond: quadratic-Bezier spine, chevron section (leaflets droop to the sides), saw-tooth edge."""
    rv = []
    for i in range(rows):
        s = i / (rows - 1) * 0.94
        C = P0 * ((1 - s) ** 2) + P1 * (2 * (1 - s) * s) + P2 * (s * s)
        T = (2 * (1 - s) * (P1 - P0) + 2 * s * (P2 - P1)).normalized()
        side = T.cross(UP)
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        nrm = side.cross(T).normalized()
        if nrm.z < 0:
            nrm = -nrm
        sn = clamp(s / 0.94, 0.0, 1.0)
        prof = (max(sn, 0.04) ** 0.5) * ((1.0 - sn) ** 0.8) / 0.42 + 0.06
        w = width * prof * (1.0 if i % 2 == 1 else notch)
        if i == 0:
            w = width * 0.12
        pts = (C - side * w - nrm * (w * droop), C + nrm * th, C + side * w - nrm * (w * droop), C - nrm * th)
        rv.append([bm.verts.new(p) for p in pts])
    for i in range(rows - 1):
        a, b = rv[i], rv[i + 1]
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(list(reversed(rv[0])))
    tv = bm.verts.new(P2)
    for k in range(4):
        bm.faces.new((rv[-1][k], rv[-1][(k + 1) % 4], tv))


def build_fern(name, seed, n, L_range, rgb=None, notes=""):
    rng = random.Random(seed)
    root = lib.begin(name, kind="Plant", tags=[], notes=notes)
    bm = bmesh.new()
    a0 = rng.uniform(0.0, TAU)
    # shuttlecock rosette: fronds rise steeply from the crown, then arch outward; outer ones arch lower
    for i in range(n):
        a = a0 + TAU * i / n + rng.uniform(-0.2, 0.2)
        d = hdir(a)
        L = rng.uniform(*L_range)
        outer = (i % 2 == 0)
        base = d * 0.18 - UP * 0.02   # crown sunk a hair into the soil (it floated 0.03 above z = 0)
        P1 = base + d * (L * (0.2 if outer else 0.12)) + UP * (L * (0.8 if outer else 0.95))
        P2 = base + d * (L * (0.95 if outer else 0.75)) + UP * (L * (0.18 if outer else 0.45))
        frond_into(bm, base, P1, P2, L * rng.uniform(0.15, 0.17), rows=12, notch=0.5, droop=0.28)
    lib.add(root, finish_bm(bm, name + "_fronds"), "Fern", rgb=rgb, collide=False)
    lib.finish(root)


def blade_into(bm, base, bend_dir, H, w0, bend, rows=5, th=0.045):
    side = UP.cross(bend_dir).normalized()
    P0, P1, P2 = base, base + UP * (H * 0.55) + bend_dir * (bend * 0.25), base + UP * H + bend_dir * bend
    rv = []
    for i in range(rows):
        s = i / (rows - 1) * 0.9
        C = P0 * ((1 - s) ** 2) + P1 * (2 * (1 - s) * s) + P2 * (s * s)
        T = (2 * (1 - s) * (P1 - P0) + 2 * s * (P2 - P1)).normalized()
        nrm = T.cross(side).normalized()
        w = w0 * (1.0 - 0.75 * s / 0.9)
        pts = (C - side * w - nrm * (w * 0.3), C + nrm * th, C + side * w - nrm * (w * 0.3), C - nrm * th)
        rv.append([bm.verts.new(p) for p in pts])
    for i in range(rows - 1):
        a, b = rv[i], rv[i + 1]
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(list(reversed(rv[0])))
    tv = bm.verts.new(P2)
    for k in range(4):
        bm.faces.new((rv[-1][k], rv[-1][(k + 1) % 4], tv))


def build_reeds(name, seed, nblades, ncattail, rgb=None, head_rgb=(100, 70, 44), notes=""):
    rng = random.Random(seed)
    root = lib.begin(name, kind="Plant", tags=[], notes=notes)
    bm = bmesh.new()
    for i in range(nblades):
        a = rng.uniform(0.0, TAU)
        rr = math.sqrt(rng.random()) * 0.9
        base = hdir(a) * rr
        out = (hdir(a) * (0.4 + rr) + hdir(rng.uniform(0.0, TAU)) * 0.35).normalized()
        H = rng.uniform(3.8, 5.6)
        bend = rng.uniform(0.4, 1.6) * (0.6 + rr)
        if i % 7 == 3:
            bend = rng.uniform(2.2, 2.8)
            H *= 0.85
        blade_into(bm, base, out, H, rng.uniform(0.17, 0.24), bend)
    heads = bmesh.new()
    for i in range(ncattail):
        a = TAU * i / ncattail + rng.uniform(-0.4, 0.4)
        base = hdir(a) * rng.uniform(0.1, 0.5)
        H = rng.uniform(4.6, 5.4)
        lean = hdir(a) * rng.uniform(0.2, 0.6)
        topp = base + UP * H + lean
        tube(bm, [base, base + UP * (H * 0.5) + lean * 0.3, topp], [0.0, 0.5, 1.0], taper_shape(0.07, 0.3),
             segments=4, end="cap")
        dirv = (topp - (base + UP * (H * 0.5) + lean * 0.3)).normalized()
        hl = rng.uniform(0.85, 1.15)
        hr = rng.uniform(0.17, 0.21)
        h0 = topp - dirv * (hl + 0.25)
        tube(heads, [h0, h0 + dirv * hl], [0.0, 0.12, 0.88, 1.0],
             lambda th, t, hr=hr: (math.cos(th) * hr * (0.8 if t in (0.0, 1.0) else 1.0),
                                   math.sin(th) * hr * (0.8 if t in (0.0, 1.0) else 1.0)),
             segments=6, end="tip", tip_len=0.12)
        tube(bm, [h0 + dirv * (hl + 0.05), h0 + dirv * (hl + 0.55)], [0.0, 1.0], taper_shape(0.045, 0.5),
             segments=4, end="tip", tip_len=0.1)
    clamp_bm(bm, 0.0)
    lib.add(root, finish_bm(bm, name + "_blades"), "Reed", rgb=rgb, collide=False)
    lib.add(root, finish_bm(heads, name + "_heads"), "Reed", rgb=head_rgb, collide=False, smooth_angle=60)
    lib.finish(root)


def build_mushrooms(name, seed, specs, notes=""):
    """specs: list of (x, y, stem height, cap radius, stem radius, spots)."""
    rng = random.Random(seed)
    root = lib.begin(name, kind="Plant", tags=[], notes=notes)
    stems = bmesh.new()
    caps = bmesh.new()
    for (x, y, h, rc, rs, spots) in specs:
        out = Vector((x, y, 0.0))
        tilt_axis = Vector((-y, x, 0.0))
        if tilt_axis.length < 1e-4:
            tilt_axis = Vector((1, 0, 0))
        ang = rng.uniform(0.08, 0.2) if out.length > 0.1 else rng.uniform(0.0, 0.06)
        rot = Matrix.Rotation(ang, 4, tilt_axis.normalized()) @ Matrix.Rotation(rng.uniform(0.0, TAU), 4, "Z")
        m = Matrix.Translation(Vector((x, y, 0.0))) @ rot
        lathe_into(stems, [(rs * 1.3, 0.0), (rs * 1.08, h * 0.12), (rs * 0.9, h * 0.55), (rs * 0.95, h * 0.92),
                           (rs * 0.7, h + 0.05)], 6, m)
        prof = [(rs * 1.05, h - 0.02), (rc * 0.9, h + 0.02), (rc, h + 0.14 * rc), (rc * 0.88, h + 0.42 * rc),
                (rc * 0.6, h + 0.66 * rc), (rc * 0.28, h + 0.82 * rc), (0.0, h + 0.86 * rc)]
        lathe_into(caps, prof, 9 if rc > 0.35 else 7, m)
        for s in range(spots):
            phi = TAU * s / max(1, spots) + rng.uniform(-0.4, 0.4)
            f = rng.uniform(2.7, 4.7)
            i0 = int(f)
            g = f - i0
            r_ = lerp(prof[i0][0], prof[i0 + 1][0], g)
            z_ = lerp(prof[i0][1], prof[i0 + 1][1], g)
            p = Vector((r_ * math.cos(phi), r_ * math.sin(phi), z_))
            nrm = (p - Vector((0.0, 0.0, h + 0.1 * rc))).normalized()
            sr = rc * rng.uniform(0.1, 0.14)
            ellipsoid_into(stems, m @ (p - nrm * (sr * 0.05)), (sr, sr * rng.uniform(0.8, 1.0), sr * 0.24),
                           (m.to_3x3() @ nrm).normalized(), subdiv=1)
    clamp_bm(stems, 0.0)
    lib.add(root, finish_bm(stems, name + "_stems"), "Mushroom", collide=False, smooth_angle=60)
    lib.add(root, finish_bm(caps, name + "_caps"), "MushroomCap", collide=False, smooth_angle=50)
    lib.finish(root)


# ================================================================================================
# STUMP and FALLEN LOG
# ================================================================================================
def build_stump(name, seed, notes=""):
    rng = random.Random(seed)
    root = lib.begin(name, kind="Prop", tags=[], notes=notes)
    h, seg = 2.3, 18
    ph = rng.uniform(0.0, TAU)
    off = rvec(rng)
    tilt_dir = hdir(rng.uniform(0.0, TAU))
    tilt = 0.07

    def shear(p):
        k = smoothstep(h - 1.4, h - 0.5, p.z)
        return p + UP * (tilt * (p.x * tilt_dir.x + p.y * tilt_dir.y) * k)

    prof = [(0.0, 1.95, 1.0), (0.2, 1.74, 0.85), (0.5, 1.56, 0.55), (0.95, 1.45, 0.3), (1.5, 1.4, 0.12), (h, 1.36, 0.04)]
    bm = bmesh.new()
    rings = []
    for (z, r, lobe) in prof:
        ring = []
        for i in range(seg):
            th = TAU * i / seg
            m = (1.0 + 0.2 * lobe * max(0.0, math.cos(5 * th + ph)) ** 2
                 + 0.035 * math.sin(9 * th + ph * 3.0)
                 + 0.03 * noise.noise(Vector((math.cos(th) * 2.0, math.sin(th) * 2.0, z)) + off))
            ring.append(bm.verts.new(shear(Vector((math.cos(th) * r * m, math.sin(th) * r * m, z)))))
        rings.append(ring)
    lip_r = prof[-1][1] - 0.15
    for dz in (0.0, -0.16):
        rings.append([bm.verts.new(shear(Vector((math.cos(TAU * i / seg) * lip_r, math.sin(TAU * i / seg) * lip_r, h + dz))))
                      for i in range(seg)])
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    lib.add(root, finish_bm(bm, name + "_body"), "Bark", collide=True, collision="Hull", smooth_angle=55)

    # cut face (growth-ring grooves), recessed 0.035 below the bark rim
    bmw = bmesh.new()
    rd = lip_r - 0.025
    lathe_into(bmw, [(rd, h - 0.4), (rd, h - 0.065), (rd - 0.05, h - 0.035), (rd * 0.72, h - 0.035),
                     (rd * 0.68, h - 0.055), (rd * 0.42, h - 0.055), (rd * 0.38, h - 0.035), (rd * 0.12, h - 0.035),
                     (0.0, h - 0.05)], seg)
    for v in bmw.verts:
        v.co = shear(v.co)

    # torn hinge: an arc of splintered heartwood left standing on one side of the cut (same light Wood part)
    a0 = rng.uniform(0.0, TAU)
    span, nseg = 1.3, 6
    rin, rout = lip_r - 0.22, prof[-1][1] - 0.02
    outer_top, inner_top, outer_bot, inner_bot = [], [], [], []
    for i in range(nseg + 1):
        th = a0 + span * i / nseg
        env = math.sin(math.pi * i / nseg)
        ht = h + 0.08 + env * (0.55 if i % 2 == 1 else 0.25) * rng.uniform(0.75, 1.2)
        d = hdir(th)
        outer_top.append(bmw.verts.new(shear(d * rout + UP * ht)))
        inner_top.append(bmw.verts.new(shear(d * rin + UP * (ht - 0.06))))
        outer_bot.append(bmw.verts.new(shear(d * rout + UP * (h - 0.25))))
        inner_bot.append(bmw.verts.new(shear(d * rin + UP * (h - 0.25))))
    for i in range(nseg):
        j = i + 1
        bmw.faces.new((outer_bot[i], outer_bot[j], outer_top[j], outer_top[i]))
        bmw.faces.new((inner_top[i], inner_top[j], inner_bot[j], inner_bot[i]))
        bmw.faces.new((outer_top[i], outer_top[j], inner_top[j], inner_top[i]))
        bmw.faces.new((inner_bot[i], inner_bot[j], outer_bot[j], outer_bot[i]))
    bmw.faces.new((outer_bot[0], outer_top[0], inner_top[0], inner_bot[0]))
    bmw.faces.new((outer_bot[-1], inner_bot[-1], inner_top[-1], outer_top[-1]))
    lib.add(root, finish_bm(bmw, name + "_cut"), "Wood", rgb=(150, 118, 84), collide=False, smooth_angle=30)

    # buttress roots: run down the flank from inside the body, then flare out and dive into the ground
    bmr = bmesh.new()
    for k in range(5):
        a = (TAU * k - ph) / 5.0 + rng.uniform(-0.08, 0.08)
        d = hdir(a)
        reach = rng.uniform(2.7, 3.2)
        c = [d * 0.7 + UP * 1.45, d * 1.38 + UP * 0.85, d * 2.0 + UP * 0.3, d * (reach * 0.9) - UP * 0.05,
             d * reach - UP * 0.45]
        tube(bmr, c, [0.0, 0.3, 0.6, 0.85, 1.0], taper_shape(rng.uniform(0.44, 0.52), 0.5, 1.2, 0.95), segments=7,
             up_ref=UP, end="cap", clamp_z=0.0)
    clamp_bm(bmr, 0.0)
    lib.add(root, finish_bm(bmr, name + "_roots"), "Bark", collide=False, smooth_angle=55)
    lib.finish(root)


def build_log(name, seed, L=14.5, R0=1.25, R1=1.05, notes=""):
    rng = random.Random(seed)
    root = lib.begin(name, kind="Prop", tags=[], notes=notes)
    zc = R0 - 0.14
    ctrl = [Vector((-L / 2, 0.0, zc)), Vector((-L / 4, 0.25, zc - 0.04)), Vector((0.0, 0.35, zc - 0.08)),
            Vector((L / 4, 0.15, zc - 0.12)), Vector((L / 2, -0.2, zc - 0.16))]
    ph = rng.uniform(0.0, TAU)
    off = rvec(rng)

    def lshape(th, t):
        r = lerp(R0, R1, t)
        r *= (1.0 + 0.045 * math.sin(9 * th + ph + t * 2.0)
              + 0.035 * noise.noise(Vector((math.cos(th), math.sin(th), t * 4.0)) + off))
        return (math.cos(th) * r, math.sin(th) * r)

    bm = bmesh.new()
    ts = [i / 11.0 for i in range(12)]
    info = tube(bm, ctrl, ts, lshape, segments=14, up_ref=UP, start="lip", lip=(0.13, 0.14), end="jag", jag=0.75,
                rng=rng, clamp_z=0.0)
    clamp_bm(bm, 0.0)
    lib.add(root, finish_bm(bm, name + "_body"), "Logs", rgb=(98, 78, 58), collide=True, collision="Hull",
            smooth_angle=55)

    # cut face plug at the -X end: follows the lip outline, recessed a hair behind the bark rim
    C0, T0 = info.center(0.0), info.frame(0.0)[0]
    r0 = sum((p - C0).length for p in info.ring_pts[0]) / info.seg
    s0 = 1.0 - 0.13 / r0
    outline = [C0 + (p - C0) * s0 for p in info.ring_pts[0]]
    bmw = bmesh.new()
    layers = [(0.97, 0.3), (0.97, 0.035), (0.9, 0.02), (0.64, 0.02), (0.6, 0.04), (0.36, 0.04), (0.32, 0.02)]
    rings = []
    for (sc, dep) in layers:
        rings.append([bmw.verts.new(C0 + (p - C0) * sc + T0 * dep) for p in outline])
    cv = bmw.verts.new(C0 + T0 * 0.03)
    n = len(outline)
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            bmw.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    for i in range(n):
        bmw.faces.new((rings[-1][i], rings[-1][(i + 1) % n], cv))
    bmw.faces.new(list(reversed(rings[0])))
    lib.add(root, finish_bm(bmw, name + "_cut"), "Wood", rgb=(146, 114, 80), collide=False, smooth_angle=30)

    # broken branch stubs (walk-through)
    bms = bmesh.new()
    for (t, dth) in ((0.3, 0.95), (0.66, -1.15), (0.5, 0.25)):
        th = math.pi / 2 + dth
        p = info.point(t, th, -0.25)
        nrm = (info.point(t, th, 0.0) - info.center(t)).normalized()
        T = info.frame(t)[0]
        dirv = (nrm + T * 0.35 + UP * 0.25).normalized()
        Ls = rng.uniform(0.9, 1.3)
        tube(bms, [p, p + dirv * Ls], [0.0, 0.5, 1.0], taper_shape(rng.uniform(0.2, 0.26), 0.3), segments=6,
             end="jag", jag=0.25, rng=rng)
    lib.add(root, finish_bm(bms, name + "_stubs"), "Logs", rgb=(98, 78, 58), collide=False, smooth_angle=50)

    # moss cushions on top, some draping a little down the flanks
    bmm = bmesh.new()
    for (tc, dth, ln, wd, ht) in ((0.2, 0.25, 3.2, 1.25, 0.4), (0.27, -0.2, 1.4, 0.6, 0.5),
                                  (0.55, 0.05, 2.6, 1.15, 0.38), (0.62, 0.45, 1.2, 0.55, 0.45),
                                  (0.78, 0.3, 2.6, 1.2, 0.4), (0.88, -0.4, 1.3, 0.7, 0.36)):
        conform_blob(bmm, info, tc, math.pi / 2 + dth, (ln / 2) / L, wd, ht, 0.05, rng, below=0.3)
    lib.add(root, finish_bm(bmm, name + "_moss"), "Moss", collide=False)

    # bracket fungi stacked on the front (+Y) flank
    bmf = bmesh.new()
    front = Vector((0.0, 1.0, 0.0))
    for (tc, dz, rr) in ((0.6, 0.05, 0.74), (0.64, -0.38, 0.54), (0.42, -0.1, 0.62)):
        th = info.theta_toward(tc, front) + dz
        p = info.point(tc, th, -0.1)
        nrm = (info.point(tc, th, 0.0) - info.center(tc)).normalized()
        out = (nrm - UP * nrm.dot(UP)).normalized()
        side = out.cross(UP).normalized()
        prof = [(rr * 0.3, -0.09), (rr * 0.9, -0.05), (rr, 0.02), (rr * 0.9, 0.1), (rr * 0.55, 0.17), (0.0, 0.19)]
        for ring in lathe_into(bmf, prof, 9):
            for v in ring:
                lp = v.co.copy()
                v.co = p + out * (lp.x * 0.85 + rr * 0.6) + side * lp.y + UP * lp.z
    lib.add(root, finish_bm(bmf, name + "_fungi"), "Mushroom", rgb=(206, 184, 150), collide=False, smooth_angle=50)
    lib.finish(root)


# ================================================================================================
# BUILD
# ================================================================================================
build_pine("PineA", 101, H=34.0, base_r=1.0, z0=8.4, R0=7.4, R1=1.9, K=10, lean=0.9,
           rgbs=[(36, 62, 40), (48, 80, 50), (62, 98, 58)],
           notes="Classic spruce silhouette. Trunk collides (Hull); roots, twigs and needles are walk-through.")
build_pine("PineB", 202, H=40.0, base_r=1.1, z0=11.5, R0=6.6, R1=1.7, K=11, lean=0.6,
           rgbs=[(34, 60, 46), (44, 76, 56), (56, 92, 64)], bark_rgb=(84, 64, 52), droop=0.28,
           notes="Tall, narrow, slightly blue-green. Bare trunk to ~9 studs.")
build_pine("PineC", 303, H=28.0, base_r=0.95, z0=8.0, R0=7.8, R1=2.0, K=8, lean=1.8,
           rgbs=[(44, 68, 40), (56, 86, 48), (70, 102, 56)], bark_rgb=(92, 70, 52), droop=0.34, asym=0.22,
           notes="Shorter, broad, windswept lean; yellower needles.")

build_oak("OakA", 404, trunk_r=1.6, top_z=17.0,
          branches=[(8.6, 20, 9.0, 4.5, 1.12), (10.2, 115, 8.5, 5.0, 1.08), (11.4, 205, 9.5, 4.2, 1.12),
                    (12.6, 290, 8.0, 5.2, 1.04)],
          crown=(6.4, 6.0, 4.4), rgbs=[(68, 100, 44), (82, 116, 52)], canopy_tris=(720, 860),
          notes="4 standable branches (flat tops >= 1.6 studs wide, 9.6-14.3 studs up; Perch1-4 attachments).")
build_oak("OakB", 505, trunk_r=1.85, top_z=19.0,
          branches=[(8.4, 0, 10.0, 4.6, 1.15), (9.6, 75, 9.0, 5.2, 1.1), (11.0, 150, 10.5, 4.4, 1.15),
                    (12.2, 220, 9.2, 5.6, 1.08), (13.6, 295, 8.6, 5.0, 1.04)],
          crown=(7.0, 6.5, 4.8), rgbs=[(72, 102, 42), (88, 120, 50)], bark_rgb=(82, 64, 50), canopy_tris=(820, 860),
          notes="Old wide oak, 5 standable branches (Perch1-5 attachments).")

build_birch("BirchA", 606, stems=[(24.0, 40, 1.4, 0.0, 0.55, 7, 8)], rgbs=[(112, 142, 62), (128, 156, 70)],
            canopy_tris=(420, 640), notes="Single slender stem; dark bands are a separate Bark part.")
build_birch("BirchB", 707, stems=[(26.2, 30, 2.2, 0.3, 0.52, 5, 4), (21.5, 215, 2.6, 0.3, 0.44, 4, 3)],
            rgbs=[(118, 146, 64), (134, 160, 72)], canopy_tris=(380, 560),
            notes="Twin stems from one root; each stem has its own Hull collider.")

build_dead("DeadTreeA", 808, H=19.0, r0=0.95, lean=1.6, nbranch=5, mossy=False,
           notes="Snapped-top snag with swamp roots. Trunk collides (Hull); limbs/roots walk-through.")
build_dead("DeadTreeB", 909, H=15.5, r0=1.05, lean=2.4, nbranch=4, mossy=True, rgb=(100, 92, 80), moss_rgb=(80, 104, 52),
           notes="Leaning mossy snag with hanging moss beards.")

build_bush("BushA", 1001, 6.6, 6.2, 4.0, 20, 0.85, 1.35, rgb=(68, 102, 46), notes="Rounded dome, hides a crouching player.")
build_bush("BushB", 1102, 7.8, 6.8, 3.3, 22, 0.85, 1.3, rgb=(62, 96, 48), notes="Low and spreading.")
build_bush("BushC", 1203, 5.0, 4.6, 4.9, 18, 0.8, 1.25, rgb=(74, 106, 44), notes="Tall upright bush.")
build_bush("BerryBush", 1304, 6.0, 5.6, 3.7, 18, 0.85, 1.3, rgb=(58, 92, 50), tris=480, berries=10,
           notes="Forage bush; berries are a separate Berry part (could be hidden once picked).")

build_fern("FernClump", 1405, n=10, L_range=(2.6, 3.3), notes="Ground fern, walk-through.")
build_reeds("ReedsClump", 1506, nblades=22, ncattail=4,
            notes="Waterside reeds 4-6 studs with cattail heads (Reed role, brown rgb).")
build_mushrooms("MushroomCluster", 1607,
                specs=[(0.0, 0.0, 1.5, 0.95, 0.24, 6), (0.95, 0.45, 0.95, 0.62, 0.17, 4), (-0.7, 0.75, 0.75, 0.48, 0.14, 3),
                       (0.45, -0.85, 0.6, 0.4, 0.12, 0), (-0.95, -0.4, 0.45, 0.3, 0.09, 0), (1.3, -0.5, 0.35, 0.24, 0.07, 0)],
                notes="Toadstool cluster; spots belong to the Mushroom part.")
build_stump("Stump", 1708, notes="Stand-on stump 2.3 studs high; body collides (Hull), cut face/roots/splinters walk-through.")
build_log("FallenLog", 1809, notes="14.5-stud log lying along X (front = +Y side), ~2.3 studs high, hop-on (Hull).")

for e in lib.assets:
    print("ASSET %-16s tris=%5d size=%s parts=%d" % (e["name"], e["tris"], e["size"], len(e["parts"])))
    for p in e["parts"]:
        print("    %-28s %-12s tris=%5d collide=%s %s" % (p["name"], p["role"], p["tris"], p["collide"], p["collision"]))

manifest = lib.export(out_dir, preview_dir)
man_dir = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "manifests"))
os.makedirs(man_dir, exist_ok=True)
shutil.copy2(os.path.join(out_dir, "Foliage.manifest.json"), os.path.join(man_dir, "Foliage.manifest.json"))
print("MANIFEST COPIED to " + man_dir)
