"""
rocks.py - LAST STANDING "Rocks" category generator (Blender 5.3, headless, fully procedural).

Assets (1 Blender unit = 1 stud, front = +Y, base on z = 0, centred on the origin):
  BoulderA/B/C/D   faceted, slightly flattened boulders (3 / 5 / 8 / 13 studs). B carries a recessed DarkStone
                   bed, C and D a thin Moss cap.
  CliffChunkA/B/C  layered cliff formations for terrain cliffs: hard Stone beds and recessed DarkStone beds,
                   vertical joints that open as V-notches, a steep front (+Y) and a stepped back that slopes
                   into the hillside, talus blocks at the foot; Snow on the ledges of C.
  RockPile         eight rocks heaped into a 6-stud mound.
  Pebbles          flat scatter of small stones (no collision).
  StandingStones   ring fragment of three weathered Granite monoliths with Moss; the ring centre is in front.
  FlatStone        10 x 8 x 1.5 cracked slab players can stand on.
  RockArch         20 x 14 natural arch (an eroded fin), walkable underneath along Y; highlands landmark.

Technique: every rock starts from a simple solid that is noise-deformed and then shaved by planar cuts
(bisect + cap), so large crisp facets catch the light. Strata are V-grooves along tilted planes that fade in
and out. Moss is a thin shell projected onto the rock (ray cast), so its outline is organic.

Run:
  blender --background --factory-startup --python rocks.py -- <out_dir> <preview_dir>
"""
import os
import sys
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls
import ls_patch  # noqa: F401  (art-direction fixes on top of ls_common: hard edges, bounds, query flags)

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

out_dir, preview_dir = ls.args()
ls.reset()
ls.seed(5150)

lib = ls.Library("Rocks")

UP = Vector((0.0, 0.0, 1.0))
DOWN = Vector((0.0, 0.0, -1.0))
MOSS = ls.ROLES["Moss"]["rgb"]


# =============================================================================================
# bmesh helpers
# =============================================================================================
def geom(bm):
    return bm.verts[:] + bm.edges[:] + bm.faces[:]


def cut(bm, co, no, dist=1e-4):
    """Remove everything on the +no side of the plane through co and cap the opening."""
    no = Vector(no).normalized()
    bmesh.ops.bisect_plane(bm, geom=geom(bm), dist=dist, plane_co=Vector(co), plane_no=no,
                           clear_outer=True, clear_inner=False)
    flaps = [f for f in bm.faces if all(e.is_boundary for e in f.edges)]   # faces left lying on the plane
    if flaps:
        bmesh.ops.delete(bm, geom=flaps, context="FACES")
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        new = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)["faces"]
        dup = [f for f in new if any(g is not f and set(g.verts) == set(f.verts) for g in f.verts[0].link_faces)]
        if dup:
            bmesh.ops.delete(bm, geom=dup, context="FACES_ONLY")
    return bm


def slice_plane(bm, co, no, dist=1e-4):
    """Cut an edge loop along a plane (nothing removed). Returns the vertices on the cut."""
    res = bmesh.ops.bisect_plane(bm, geom=geom(bm), dist=dist, plane_co=Vector(co),
                                 plane_no=Vector(no).normalized())
    return [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMVert)]


def extent(bm, n):
    ps = [v.co.dot(n) for v in bm.verts]
    return min(ps), max(ps)


def chip(bm, n, frac):
    """Shave a planar facet off the side the direction n points to (frac of the extent along n)."""
    n = Vector(n).normalized()
    lo, hi = extent(bm, n)
    cut(bm, n * (hi - frac * (hi - lo)), n)


def bounds(bm):
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def move(bm, vec):
    bmesh.ops.translate(bm, vec=Vector(vec), verts=bm.verts)


def xform(bm, mat):
    bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)


def ground(bm, sink=0.0):
    """Drop the mesh so its lowest point sits `sink` below z = 0, then cut it flat at z = 0."""
    lo, _ = bounds(bm)
    move(bm, (0.0, 0.0, -lo.z - sink))
    if sink > 0.0:
        cut(bm, (0.0, 0.0, 0.0), DOWN)
    return bm


def append_bm(dst, src):
    me = bpy.data.meshes.new("_tmp")
    src.to_mesh(me)
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)


def merged(bms, free=True):
    out = bmesh.new()
    for b in bms:
        append_bm(out, b)
        if free:
            b.free()
    return out


def to_obj(name, bm):
    return ls.from_bmesh(name, bm)


def box_bm(x0, x1, y0, y1, z0, z1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((x1 if v.co.x > 0 else x0, y1 if v.co.y > 0 else y0, z1 if v.co.z > 0 else z0))
    return bm


def grid_box(sx, sy, sz, nx, ny, nz):
    """Box centred on the origin with a regular grid of quads on every side."""
    bm = box_bm(-sx / 2, sx / 2, -sy / 2, sy / 2, -sz / 2, sz / 2)
    for i in range(1, nx):
        slice_plane(bm, (-sx / 2 + sx * i / nx, 0, 0), (1, 0, 0))
    for i in range(1, ny):
        slice_plane(bm, (0, -sy / 2 + sy * i / ny, 0), (0, 1, 0))
    for i in range(1, nz):
        slice_plane(bm, (0, 0, -sz / 2 + sz * i / nz), (0, 0, 1))
    return bm


def rounded_cube(cuts, roundness):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    for v in bm.verts:
        v.co = v.co.lerp(v.co.normalized() * 0.62, roundness)
    return bm


# =============================================================================================
# noise / random helpers
# =============================================================================================
def fbm(p, octaves=2):
    total, amp, norm, f = 0.0, 1.0, 0.0, 1.0
    for _ in range(octaves):
        total += amp * noise.noise(p * f)
        norm += amp
        amp *= 0.5
        f *= 2.07
    return total / norm


def rand_dir(rng, el_lo, el_hi):
    az = rng.uniform(0.0, 2.0 * math.pi)
    el = math.radians(rng.uniform(el_lo, el_hi))
    return Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))


def rand_off(rng):
    return Vector((rng.uniform(-80, 80), rng.uniform(-80, 80), rng.uniform(-80, 80)))


def strata_normal(rng, tilt_deg):
    a = rng.uniform(0, 2 * math.pi)
    t = math.radians(tilt_deg)
    return Vector((math.sin(t) * math.cos(a), math.sin(t) * math.sin(a), math.cos(t)))


def tint(rgb, d):
    return tuple(max(0, min(255, int(round(c + dc)))) for c, dc in zip(rgb, d))


# =============================================================================================
# surface features: strata grooves and moss
# =============================================================================================
def groove(bm, origin, n, level, half_width, depth, rng=None, fade_freq=0.0, steep=0.72):
    """Strata line: three parallel slices along a plane; the middle loop is pushed into the rock.
    With fade_freq > 0 the depth is modulated by noise so the line fades in and out like real bedding."""
    n = Vector(n).normalized()
    base = Vector(origin) + n * level
    slice_plane(bm, base - n * half_width, n)
    mid = slice_plane(bm, base, n)
    slice_plane(bm, base + n * half_width, n)
    bm.normal_update()
    off = rand_off(rng) if (rng is not None and fade_freq > 0) else None
    moved = []
    for v in mid:
        vn = v.normal
        if abs(vn.dot(n)) > steep:
            continue
        d = vn - n * vn.dot(n)
        if d.length < 1e-4:
            continue
        k = 1.0
        if off is not None:
            k = max(0.0, min(1.0, 0.4 + 2.4 * fbm(v.co * fade_freq + off, 2)))
        if k < 0.04:
            continue
        moved.append((v, d.normalized() * (-depth * k)))
    for v, d in moved:
        v.co += d
    faces = list({f for v, _ in moved for f in v.link_faces})
    if faces:
        bmesh.ops.triangulate(bm, faces=faces)
    return len(moved)


def surface_basis(axis):
    ref = Vector((0.0, 0.0, 1.0)) if abs(axis.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = axis.cross(ref).normalized()
    return u, axis.cross(u).normalized()


def blob_outline(rng, cx, cy, radius, n=9):
    """Irregular convex 2D outline around (cx, cy)."""
    a0 = rng.uniform(0, 2 * math.pi)
    pts = []
    for i in range(n):
        a = a0 + 2 * math.pi * (i + rng.uniform(-0.25, 0.25)) / n
        r = radius * rng.uniform(0.7, 1.18)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return hull2d(pts)


def inside_convex(P, x, y):
    for a, b, m in poly_edges(P):
        if (x - a[0]) * m[0] + (y - a[1]) * m[1] > 0.0:
            return False
    return True


def moss_patch(src_bm, axis, blobs, rng, min_dot, lift):
    """Moss patch that hugs the rock: the faces of src_bm that face against `axis` (e.g. DOWN for a cap)
    and fall inside the union of irregular blobs, cut exactly along the blob outlines and lifted by `lift`.
    blobs: [(world point on/near the surface, radius)]. Returns an open bmesh or None."""
    axis = Vector(axis).normalized()
    u, v = surface_basis(axis)
    outlines = [(blob_outline(rng, p.dot(u), p.dot(v), r), p.dot(u), p.dot(v), r) for p, r in blobs]
    bm = src_bm.copy()
    for P, cx, cy, r in outlines:
        for a, b, m in poly_edges(P):
            # slice only the faces around this blob, so the rest of the rock is not chopped up
            near = [f for f in bm.faces if any(math.hypot(vv.co.dot(u) - cx, vv.co.dot(v) - cy) < 1.35 * r
                                               for vv in f.verts)]
            if not near:
                continue
            g = list({e for f in near for e in f.edges}) + list({vv for f in near for vv in f.verts}) + near
            bmesh.ops.bisect_plane(bm, geom=g, dist=1e-4, plane_co=u * a[0] + v * a[1],
                                   plane_no=(u * m[0] + v * m[1]).normalized())
    outlines = [o[0] for o in outlines]
    bm.normal_update()
    keep = set()
    for f in bm.faces:
        if f.normal.dot(-axis) < min_dot:
            continue
        c = f.calc_center_median()
        if any(inside_convex(P, c.dot(u), c.dot(v)) for P in outlines):
            keep.add(f)
    drop = [f for f in bm.faces if f not in keep]
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="FACES")
    if not bm.faces:
        bm.free()
        return None
    # merge the coplanar pieces the slicing produced (keeps the patch light)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), use_dissolve_boundaries=False,
                             verts=bm.verts[:], edges=bm.edges[:])
    bm.normal_update()
    for vv in bm.verts:
        vv.co += vv.normal * lift
    return bm


def shell(name, bm, thickness):
    """Solidify an open patch inward into a closed thin shell."""
    obj = to_obj(name, bm)
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_even_offset = False
    mod.use_rim = True
    ls.apply_modifiers(obj)
    return obj


def top_point(bm, rng, frac=0.25):
    """A point near the top of the mesh (inside its upper footprint), for placing moss."""
    lo, hi = bounds(bm)
    zcut = hi.z - (hi.z - lo.z) * frac
    pts = [v.co for v in bm.verts if v.co.z >= zcut]
    c = sum(pts, Vector()) / len(pts)
    return Vector((c.x, c.y, hi.z + 5.0))


# =============================================================================================
# boulders
# =============================================================================================
GOLDEN = math.pi * (3.0 - math.sqrt(5.0))


def boulder(rng, size, height=0.56, footprint=0.78, cuts=4, roundness=0.78, bumps=0.08, bump_freq=1.2,
            primary=11, secondary=10, flare=0.12, taper=0.1, shear=0.15, wedge=(0.12, 0.3), sink=0.1,
            flat_side=True, top_plane=True):
    """Faceted boulder: a lumpy rounded block whose surface is mostly replaced by planar facets.
    Character first: one end rises higher (wedge), a big sloped top plane and a flat fracture face; then
    primary facets spread evenly (Fibonacci) over flanks and shoulders, and small secondary chips that
    bevel the edges between them. Scaled so its longest horizontal side is `size`, wide at the foot,
    sunk and cut flat at z = 0."""
    bm = rounded_cube(cuts, roundness)
    xform(bm, Matrix.Diagonal((1.0, footprint, height, 1.0)))
    off = rand_off(rng)
    for v in bm.verts:
        v.co += v.co.normalized() * (bumps * fbm(v.co * bump_freq + off, 2))
    lo, hi = bounds(bm)
    shx, shy = rng.uniform(-shear, shear), rng.uniform(-shear, shear)
    wg = rng.uniform(*wedge) * rng.choice((-1.0, 1.0))
    for v in bm.verts:
        t = (v.co.z - lo.z) / max(hi.z - lo.z, 1e-6)
        s = 1.0 + flare * (1.0 - t) ** 2 - taper * t ** 1.6
        h = v.co.z - lo.z
        v.co.z = lo.z + h * (1.0 + wg * v.co.x)
        v.co.x = v.co.x * s + shx * h
        v.co.y = v.co.y * s + shy * h
    xform(bm, Matrix.Rotation(rng.uniform(0, 2 * math.pi), 4, "Z"))
    if top_plane:
        chip(bm, rand_dir(rng, 64, 78), rng.uniform(0.1, 0.16))
    if flat_side:
        chip(bm, rand_dir(rng, -2, 8), rng.uniform(0.1, 0.16))
    az0 = rng.uniform(0, 2 * math.pi)
    s_lo, s_hi = math.sin(math.radians(-4.0)), math.sin(math.radians(70.0))
    for i in range(primary):
        el = math.asin(s_lo + (s_hi - s_lo) * (i + rng.uniform(0.15, 0.85)) / primary)
        az = az0 + i * GOLDEN + rng.uniform(-0.3, 0.3)
        n = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
        deg = math.degrees(el)
        frac = rng.uniform(0.05, 0.13) if deg < 22 else rng.uniform(0.07, 0.17)
        chip(bm, n, frac)
    for _ in range(secondary):
        chip(bm, rand_dir(rng, -2, 72), rng.uniform(0.015, 0.045))
    lo, hi = bounds(bm)
    s = size / max(hi.x - lo.x, hi.y - lo.y)
    c = (lo + hi) * 0.5
    xform(bm, Matrix.Diagonal((s, s, s, 1.0)) @ Matrix.Translation(-Vector((c.x, c.y, lo.z))))
    ground(bm, sink * (hi.z - lo.z) * s)
    return bm


def finalize(root, parts):
    """parts: [(obj, role, rgb, kwargs)]. Re-centre the asset on the origin (x, y), register the parts and
    return the applied shift (build coordinates + shift = asset coordinates)."""
    objs = [p[0] for p in parts]
    lo, hi = ls.world_bounds(objs)
    shift = Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0.0)))
    for o in objs:
        o.data.transform(shift)
    for obj, role, rgb, kw in parts:
        if obj.data.validate(verbose=True):
            print("NOTE validate repaired", obj.name)
        lib.add(root, obj, role, rgb=rgb, **kw)
        if obj.data.validate(verbose=True):
            print("NOTE validate repaired after add", obj.name)
    e = lib.finish(root)
    print("ASSET %-15s tris %5d  size(w,h,d) %s  parts %s" % (root.name, e["tris"], e["size"],
                                                            [(p["name"], p["tris"]) for p in e["parts"]]))
    return shift.to_translation()     # what was added to the build coordinates (for attachments)


def build_boulders():
    # name, size, seed, height ratio, footprint ratio, grid cuts, (primary, secondary facets), strata, rgb, variant
    specs = [
        ("BoulderA", 3.0, 105, 0.6, 0.8, 5, (10, 10), (0.42,), (122, 119, 112), None),
        ("BoulderB", 5.0, 207, 0.56, 0.74, 5, (11, 10), (0.8,), (117, 115, 109), "band"),
        ("BoulderC", 8.0, 311, 0.5, 0.78, 5, (13, 11), (0.36,), (112, 110, 105), "moss"),
        ("BoulderD", 13.0, 419, 0.46, 0.72, 5, (16, 14), (0.26, 0.55), (124, 121, 114), "moss"),
    ]
    for name, size, seed, hr, fr, cuts, (prim, sec), levels, rgb, variant in specs:
        rng = random.Random(seed)
        root = lib.begin(name, kind="Rock", notes="Boulder ~%g studs across" % size)
        bm = boulder(rng, size, height=hr, footprint=fr, cuts=cuts, primary=prim, secondary=sec)
        n = strata_normal(rng, 11.0)
        top = bounds(bm)[1].z
        for f in levels:
            groove(bm, Vector((0, 0, 0)), n, f * top, 0.018 * size, 0.02 * size, rng=rng, fade_freq=1.4 / size)
        parts = []
        if variant == "band":
            # a softer DarkStone bed through the middle, eroded back a little
            l1, l2 = 0.27 * top, 0.5 * top
            lower = bm.copy()
            cut(lower, n * l1, n)
            band = bm.copy()
            cut(band, n * l2, n)
            cut(band, n * l1, -n)
            upper = bm
            cut(upper, n * l2, -n)
            blo, bhi = bounds(band)
            bc = (blo + bhi) * 0.5
            k = 1.0 - 0.13 / (0.5 * size)
            for v in band.verts:
                v.co.x = bc.x + (v.co.x - bc.x) * k
                v.co.y = bc.y + (v.co.y - bc.y) * k
            parts.append((to_obj(name + "_s", merged([lower, upper])), "Stone", rgb, dict(collision="Hull")))
            parts.append((to_obj(name + "_d", band), "DarkStone", (84, 84, 86), dict(collision="Hull")))
        else:
            moss = None
            if variant == "moss":
                tp = top_point(bm, rng, 0.3)
                blobs = [(tp, 0.27 * size),
                         (tp + Vector((0.2, -0.17, 0.0)) * size, 0.15 * size),
                         (tp + Vector((-0.19, 0.15, 0.0)) * size, 0.12 * size)]
                patch = moss_patch(bm, DOWN, blobs, rng, min_dot=0.42, lift=0.006 * size)
                if patch is not None:
                    moss = shell(name + "_m", patch, 0.016 * size)
            parts.append((to_obj(name + "_s", bm), "Stone", rgb, dict(collision="Hull")))
            if moss is not None:
                parts.append((moss, "Moss", tint(MOSS, (rng.randint(-5, 3), rng.randint(-3, 5), 0)),
                              dict(collide=False, cast_shadow=False)))
        finalize(root, parts)


# =============================================================================================
# layered cliff chunks
# =============================================================================================
def hull2d(points):
    pts = sorted(set((round(p[0], 5), round(p[1], 5)) for p in points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]   # counter-clockwise


def unit_poly(rng, sides, boxy=2.6, jitter=0.28, rad=(0.93, 1.04), front_flat=0.0):
    """Irregular boxy (superellipse) polygon of unit half-size; front_flat pulls the +Y side straight."""
    e = 2.0 / boxy
    pts = []
    for i in range(sides):
        a = 2 * math.pi * (i + rng.uniform(-jitter, jitter)) / sides
        r = rng.uniform(*rad)
        ca, sa = math.cos(a), math.sin(a)
        x, y = math.copysign(abs(ca) ** e, ca) * r, math.copysign(abs(sa) ** e, sa) * r
        if y > 0.0 and front_flat > 0.0:
            y = y + (1.0 - y) * front_flat * min(1.0, y / 0.45)
        pts.append((x, y))
    return pts


def poly_edges(P):
    """Edges (a, b, outward unit normal) of a counter-clockwise polygon."""
    out = []
    for i in range(len(P)):
        a, b = P[i], P[(i + 1) % len(P)]
        ex, ey = b[0] - a[0], b[1] - a[1]
        L = math.hypot(ex, ey) or 1.0
        out.append((a, b, (ey / L, -ex / L)))
    return out


def line_poly_hits(c, u, P):
    """The two points where the line c + s*u crosses polygon P: [(s, point, edge normal)]."""
    hits = []
    for a, b, m in poly_edges(P):
        ex, ey = b[0] - a[0], b[1] - a[1]
        det = -u[0] * ey + ex * u[1]
        if abs(det) < 1e-9:
            continue
        rx, ry = a[0] - c[0], a[1] - c[1]
        s = (-rx * ey + ex * ry) / det
        t = (u[0] * ry - u[1] * rx) / det
        if -1e-6 <= t <= 1 + 1e-6:
            hits.append((s, (c[0] + u[0] * s, c[1] + u[1] * s), m))
    if len(hits) < 2:
        return []
    hits.sort(key=lambda h: h[0])
    return [hits[0], hits[-1]]


def plane_z(base, dip):
    """Plane z = base + dip.x * x + dip.y * y as (point, upward unit normal)."""
    return Vector((0.0, 0.0, base)), Vector((-dip[0], -dip[1], 1.0)).normalized()


def make_piece(P, z0, z1, dip, rng, delta=0.0, lean=6.0, left=None, right=None, overlap=0.6,
               notch=(0.3, 0.7), notch_beta=(28.0, 42.0), chamfer_p=0.5, chamfer=(0.3, 0.9),
               undercut_p=0.15, corner_p=0.5, corner=(0.3, 0.9), chips=1, flat_bottom=False, edge_jitter=0.12):
    """One convex rock slab: the prism of polygon P (outline pushed out by `delta`, faces leaning back by
    `lean` degrees) between the strata planes z0 and z1, trimmed by joint planes (left/right, each a
    (point, direction, normal) line) that end in V-notches, with chamfered top edges, softened vertical
    corners and corner chips. Neighbouring slabs overlap behind the notches, so joints never open a
    see-through gap."""
    xs = [p[0] for p in P]
    ys = [p[1] for p in P]
    bm = box_bm(min(xs) - 3, max(xs) + 3, min(ys) - 3, max(ys) + 3, min(z0, 0.0) - 8, z1 + 8)
    if flat_bottom:
        cut(bm, (0, 0, z0), DOWN)
    else:
        co, n = plane_z(z0, dip)
        cut(bm, co, -n)
    co, n_top = plane_z(z1, dip)
    cut(bm, co, n_top)
    zc = 0.5 * (z0 + z1)
    edges = poly_edges(P)
    faces = []
    for (a, b, m) in edges:
        off = delta + rng.uniform(-edge_jitter, edge_jitter)
        le = math.radians(lean + rng.uniform(-2.0, 2.5))
        faces.append((off, le))
        nrm = Vector((m[0] * math.cos(le), m[1] * math.cos(le), math.sin(le)))
        cut(bm, Vector((a[0] + m[0] * off, a[1] + m[1] * off, zc)), nrm)
    for i in range(len(P)):
        if rng.random() > corner_p:
            continue
        m0, m1 = edges[i - 1][2], edges[i][2]
        bis = Vector((m0[0] + m1[0], m0[1] + m1[1], 0.0))
        if bis.length < 0.2:
            continue
        bis.normalize()
        tip = Vector((P[i][0], P[i][1], zc)) + bis * delta
        cut(bm, tip - bis * rng.uniform(*corner), bis)
    for sgn, J in ((-1.0, left), (1.0, right)):
        if J is None:
            continue
        c, u, w = J[0], J[1], J[2]
        major = len(J) > 3 and J[3]                  # major joints open into wide clefts
        wz = J[4] if len(J) > 4 else 0.0             # joint plane dip (0 = vertical)
        t = Vector((w[0], w[1], wz)).normalized() * sgn   # from this slab across the joint
        cut(bm, Vector((c[0], c[1], zc)) + t * overlap, t)
        for (s, q, m) in line_poly_hits(c, u, P):
            g = rng.uniform(0.75, 1.3) if major else rng.uniform(*notch)
            beta = math.radians(rng.uniform(*notch_beta))
            mo = Vector((m[0], m[1], 0.0))
            nrm = (t * math.cos(beta) + mo * math.sin(beta)).normalized()
            qv = Vector((q[0], q[1], zc)) + mo * delta
            cut(bm, qv - t * g, nrm)
    for (a, b, m), (off, le) in zip(edges, faces):
        mo = Vector((m[0], m[1], 0.0))
        mx, my = 0.5 * (a[0] + b[0]), 0.5 * (a[1] + b[1])
        if rng.random() < chamfer_p:
            ch = rng.uniform(*chamfer)
            cv = min(ch * rng.uniform(0.6, 1.4), (z1 - z0) * 0.55)
            ztop = z1 + dip[0] * mx + dip[1] * my
            face_off = off - math.tan(le) * (ztop - zc)
            cut(bm, Vector((mx, my, ztop)) + mo * (face_off - ch), (mo * cv + UP * ch).normalized())
        if not flat_bottom and rng.random() < undercut_p:
            ch = rng.uniform(0.2, 0.5)
            cv = min(ch * rng.uniform(0.6, 1.2), (z1 - z0) * 0.4)
            zbot = z0 + dip[0] * mx + dip[1] * my
            face_off = off + math.tan(le) * (zc - zbot)
            cut(bm, Vector((mx, my, zbot)) + mo * (face_off - ch), (mo * cv - UP * ch).normalized())
    if chips and len(bm.verts) > 4:
        cen = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        verts = [v.co.copy() for v in bm.verts]
        for _ in range(chips):
            d = rand_dir(rng, 8, 50)
            d = (d + (rng.choice(verts) - cen).normalized()).normalized()
            if d.z < -0.1:
                continue
            lo, hi = extent(bm, d)
            cut(bm, d * (hi - rng.uniform(0.25, 0.75)), d)
    return bm


class Mass:
    """One rock mass of a cliff chunk: an irregular convex footprint that shrinks with height (little at
    the +Y front, a lot at the back), plus vertical joint sets that change every few beds."""

    def __init__(self, rng, cx, cy, wx, wf, wb, top, shrink=(0.3, 0.2, 0.6), sides=11, boxy=2.6,
                 joint_gap=(7.0, 13.0), joint_angle=10.0, front_flat=0.35, buttress=1.7):
        self.cx, self.cy, self.wx, self.wf, self.wb, self.top = cx, cy, wx, wf, wb, top
        self.shrink = shrink
        self.unit = unit_poly(rng, sides, boxy, front_flat=front_flat)
        self.joint_gap, self.joint_angle = joint_gap, joint_angle
        self.buttress = buttress
        # one or two master fractures that run through every bed of this mass
        self.master = [self.cx + self.wx * rng.uniform(-0.55, 0.55) for _ in range(rng.choice((1, 1, 2)))]

    def joint_set(self, rng):
        joints = []
        x = self.cx - self.wx + rng.uniform(*self.joint_gap) * rng.uniform(0.45, 0.9)
        while x < self.cx + self.wx - 2.5:
            if all(abs(x - mx) > 3.2 for mx in self.master):
                th = math.radians(rng.uniform(-self.joint_angle, self.joint_angle))
                joints.append(((x, self.cy), (math.sin(th), math.cos(th)), (math.cos(th), -math.sin(th)), False,
                               rng.uniform(-0.24, 0.24)))      # joints dip up to ~13 deg off vertical
            x += rng.uniform(*self.joint_gap)
        for mx in self.master:
            th = math.radians(rng.uniform(-4.0, 4.0))
            joints.append(((mx + rng.uniform(-0.3, 0.3), self.cy), (math.sin(th), math.cos(th)),
                           (math.cos(th), -math.sin(th)), True, rng.uniform(-0.08, 0.08)))
        joints.sort(key=lambda j: j[0][0])
        return joints

    def footprint(self, h, grow=0.0, shift=(0.0, 0.0)):
        kx, kf, kb = self.shrink
        sx = self.wx * (1 - kx * h ** 1.3) + grow
        sf = self.wf * (1 - kf * h ** 1.2) + grow
        sb = self.wb * (1 - kb * h ** 1.1) + grow
        return hull2d([(self.cx + shift[0] + x * sx, self.cy + shift[1] + y * (sf if y > 0 else sb))
                       for x, y in self.unit])


def make_layers(rng, H, first, thick=(1.5, 4.8), soft=(0.7, 1.2), soft_chance=0.3, min_soft=1):
    """Strata beds bottom to top: (z_bottom, z_top, soft). Massive and thin beds alternate loosely."""
    layers = [(0.0, first, False)]
    z = first
    prev_soft = False
    massive = rng.random() < 0.5
    while H - z > 1.4:
        s = (not prev_soft) and 3.0 < z < H - 5.0 and rng.random() < soft_chance
        if s:
            t = rng.uniform(*soft)
        else:
            massive = not massive if rng.random() < 0.75 else massive
            t = rng.uniform(3.2, thick[1]) if massive else rng.uniform(thick[0], 2.6)
        top = z + t
        if H - top < 1.4:
            top = H
        layers.append((z, top, s))
        prev_soft = s
        z = top
    soft_n = sum(1 for L in layers if L[2])
    if soft_n < min_soft:
        # split a thick bed in the lower-middle part: a recessed soft bed under a hard one
        cands = [i for i, (zb, zt, s) in enumerate(layers) if not s and i > 0 and zt - zb > 3.0 and zb < 0.6 * H]
        if cands:
            i = rng.choice(cands)
            zb, zt, _ = layers[i]
            layers[i:i + 1] = [(zb, zb + 0.95, True), (zb + 0.95, zt, False)]
    return layers


def snow_slab(bm, pts, n, t, grow=0.18, inset=0.24, sink=0.08):
    """Soft-edged snow cap on a planar face (pts in order, normal n): grown foot, inset top."""
    c = sum(pts, Vector()) / len(pts)

    def ring(d_abs, h):
        out = []
        for p in pts:
            d = p - c
            L = d.length
            k = max(0.3, (L + d_abs) / L) if L > 1e-6 else 1.0
            out.append(bm.verts.new(c + d * k + n * h))
        return out
    b = ring(grow, -sink)
    tp = ring(-inset, t)
    N = len(pts)
    bm.faces.new(list(reversed(b)))
    for i in range(N):
        j = (i + 1) % N
        bm.faces.new((b[i], b[j], tp[j], tp[i]))
    bm.faces.new(tp)


def build_cliff(name, seed, H, masses, thick=(1.5, 4.8), detail=1.0, dip_deg=3.0,
                tones=((118, 116, 110), (129, 125, 117), (109, 107, 103)), dark=(82, 81, 83), snow=False,
                rubble=6, notes=""):
    """Layered cliff formation built from Mass footprints: strata beds (hard Stone tones, recessed soft
    DarkStone beds) cut into slabs by vertical joints; talus at the front foot; optional snow on ledges.
    detail scales the chamfer/corner-softening probability (lower = fewer triangles)."""
    rng = random.Random(seed)
    root = lib.begin(name, kind="Cliff", notes=notes)
    az = rng.uniform(0, 2 * math.pi)
    td = math.tan(math.radians(dip_deg))
    dip = (td * math.cos(az), td * math.sin(az))
    ms = [Mass(rng, **cfg) for cfg in masses]
    span = max(abs(dip[0]) * (abs(m.cx) + m.wx) + abs(dip[1]) * (abs(m.cy) + max(m.wf, m.wb)) for m in ms)
    layers = make_layers(rng, H, max(3.0, span + 1.6), thick=thick)
    layer_tone = [tones[0]]
    for _ in layers[1:]:
        layer_tone.append(rng.choice([t for t in tones if t != layer_tone[-1]]))
    # bed relief: soft beds are eroded back, a few hard beds stand out as ledges
    bed_off = []
    for zb, zt, soft in layers:
        if soft:
            bed_off.append(-rng.uniform(1.2, 1.9))
        else:
            bed_off.append(rng.uniform(-0.25, 0.3) + (0.7 if rng.random() < 0.22 else 0.0))
    pieces = []
    for mi, M in enumerate(ms):
        moff = (0.0, 0.24, -0.24, 0.48)[mi % 4]     # keeps overlapping masses' bed tops >= 0.1 apart
        used = [L for L in layers if L[0] < M.top - 1.0]
        col_seed = rand_off(rng)        # buttresses and gullies: a smooth offset along x, the same in every bed
        packet_left = 0
        joints = []
        for k, (zb, zt, soft) in enumerate(used):
            if packet_left <= 0:
                joints = M.joint_set(rng)
                packet_left = rng.randint(2, 3)
            if not soft:
                packet_left -= 1
            h = min(1.0, 0.5 * (zb + zt) / M.top)
            shift = (rng.uniform(-0.45, 0.45), rng.uniform(-0.35, 0.35))
            P = M.footprint(h, shift=shift)
            xs = [p[0] for p in P]
            keep_p = 0.12 if soft else (0.6 if zt - zb > 3.2 else 0.78)
            act = []
            for ji, J in enumerate(joints):
                if not (min(xs) + 2.4 < J[0][0] < max(xs) - 2.4):
                    continue
                if len(line_poly_hits(J[0], J[1], P)) < 2:
                    continue
                if act and J[0][0] - act[-1][1][0][0] < 3.0:
                    continue
                if (J[3] and not soft) or rng.random() < keep_p:
                    act.append((ji, J))
            top_layer = (k == len(used) - 1)
            n_pieces = len(act) + 1
            dropped = 0
            for i in range(n_pieces):
                if top_layer and n_pieces > 2 and dropped == 0 and rng.random() < 0.3:
                    dropped += 1
                    continue
                left = act[i - 1][1] if i > 0 else None
                right = act[i][1] if i < len(act) else None
                x_lo = left[0][0] if left else min(xs)
                x_hi = right[0][0] if right else max(xs)
                coff = M.buttress * noise.noise(Vector((0.5 * (x_lo + x_hi) * 0.17, 0.0, 0.0)) + col_seed)
                if soft:
                    kw = dict(delta=bed_off[k] + 0.4 * coff, lean=rng.uniform(0.0, 3.0), chamfer_p=0.0, chips=0,
                              corner_p=0.3, undercut_p=0.0)
                elif k == 0:
                    kw = dict(delta=coff + rng.uniform(0.1, 0.5), lean=rng.uniform(14.0, 20.0), chamfer_p=0.4,
                              chamfer=(0.4, 1.0), chips=1, corner_p=0.6, corner=(0.5, 1.3))
                elif top_layer:
                    kw = dict(delta=coff + rng.uniform(-0.5, 0.1), lean=rng.uniform(6.0, 12.0), chamfer_p=0.9,
                              chamfer=(0.7, 1.8), chips=2, corner_p=0.75, corner=(0.6, 1.6))
                else:
                    kw = dict(delta=bed_off[k] + coff + rng.uniform(-0.2, 0.2), lean=rng.uniform(2.0, 11.0),
                              chamfer_p=0.6, chamfer=(0.35, 1.4), chips=1, corner_p=0.6, corner=(0.4, 1.3))
                z1 = zt + moff + (0.07 if i % 2 == 0 else -0.07)
                z0 = 0.0 if k == 0 else zb - 0.12
                kw["chamfer_p"] = kw["chamfer_p"] * detail
                kw["corner_p"] = kw["corner_p"] * detail
                bm = make_piece(P, z0, z1, dip, rng, left=left, right=right, flat_bottom=(k == 0), **kw)
                if len(bm.verts) < 4:
                    bm.free()
                    continue
                pieces.append((bm, "DarkStone", dark, True) if soft else (bm, "Stone", layer_tone[k], True))
    # talus: fallen blocks along the foot of the front face
    for r in range(rubble):
        M = ms[r % min(2, len(ms))]
        P0 = M.footprint(0.0)
        front = [(a, b, m) for (a, b, m) in poly_edges(P0) if m[1] > 0.3] or poly_edges(P0)
        a, b, m = rng.choice(front)
        t = rng.uniform(0.1, 0.9)
        size = rng.uniform(1.8, 4.6)
        d = rng.uniform(0.0, 0.45) * size
        bm = boulder(rng, size, height=rng.uniform(0.5, 0.72), cuts=1, primary=9, secondary=3,
                     roundness=0.7, sink=0.15)
        move(bm, (a[0] + (b[0] - a[0]) * t + m[0] * d, a[1] + (b[1] - a[1]) * t + m[1] * d, 0.0))
        pieces.append((bm, "Stone", tones[r % 2], False))
    snow_bm = None
    if snow:
        allbm = merged([p[0] for p in pieces], free=False)
        bvh = BVHTree.FromBMesh(allbm)
        allbm.free()
        snow_bm = bmesh.new()
        for bm, role, _, slab in pieces:
            if not slab:
                continue
            bm.normal_update()
            for f in bm.faces:
                nf = f.normal
                if nf.z < 0.74 or f.calc_area() < 0.9:
                    continue
                c = f.calc_center_median()
                if c.z < 0.33 * H:
                    continue
                vs = [v.co.copy() for v in f.verts]
                samples = [c] + [c.lerp(p, 0.6) for p in vs]
                free = sum(1 for s in samples if bvh.ray_cast(s + nf * 0.05, UP, 80.0)[0] is None)
                if free < 0.45 * len(samples):
                    continue
                snow_slab(snow_bm, vs, nf, 0.32 + 0.38 * (c.z / H))
    groups = {}
    for bm, role, rgb, _ in pieces:
        groups.setdefault((role, rgb), []).append(bm)
    parts = []
    for (role, rgb), bms in sorted(groups.items(), key=lambda kv: (kv[0][0] != "Stone", kv[0][1] != tones[0])):
        parts.append((to_obj(name + "_g", merged(bms)), role, rgb, dict(collision="Default")))
    if snow_bm is not None and snow_bm.faces:
        parts.append((to_obj(name + "_snow", snow_bm), "Snow", None, dict(collide=False)))
    finalize(root, parts)


def build_cliffs():
    build_cliff("CliffChunkA", 512, H=17.0, rubble=5,
                notes="Highland outcrop: steep layered face toward +Y, stepped back slopes into the hill",
                masses=[
                    dict(cx=-1.5, cy=0.0, wx=12.5, wf=6.5, wb=8.5, top=17.0, shrink=(0.3, 0.2, 0.62)),
                    dict(cx=8.5, cy=1.0, wx=6.0, wf=6.0, wb=6.5, top=10.5, shrink=(0.25, 0.18, 0.5)),
                    dict(cx=-10.5, cy=3.5, wx=5.0, wf=3.5, wb=4.0, top=5.5, shrink=(0.2, 0.1, 0.3)),
                ])
    build_cliff("CliffChunkB", 622, H=27.0, rubble=6,
                notes="Cliff wall: steep layered face toward +Y, stepped back slopes into the hill",
                masses=[
                    dict(cx=-10.0, cy=0.0, wx=11.0, wf=8.0, wb=9.5, top=23.5, shrink=(0.3, 0.2, 0.6)),
                    dict(cx=9.0, cy=-1.0, wx=12.0, wf=8.5, wb=9.0, top=27.0, shrink=(0.32, 0.22, 0.6)),
                    dict(cx=1.5, cy=5.5, wx=5.5, wf=3.5, wb=4.0, top=13.0, shrink=(0.25, 0.15, 0.3)),
                ])
    build_cliff("CliffChunkC", 733, H=38.0, rubble=3, snow=True, thick=(2.2, 6.0), detail=0.8,
                notes="Mountain crag with snow on the upper ledges; front face toward +Y",
                masses=[
                    dict(cx=-3.0, cy=-1.0, wx=13.0, wf=10.5, wb=11.5, top=38.0, shrink=(0.68, 0.5, 0.7),
                         joint_gap=(9.0, 14.0)),
                    dict(cx=8.5, cy=1.5, wx=4.2, wf=3.6, wb=3.6, top=31.0, shrink=(0.45, 0.4, 0.45),
                         joint_gap=(9.0, 12.0), buttress=0.6),
                    dict(cx=15.0, cy=-1.5, wx=10.0, wf=8.5, wb=9.0, top=21.0, shrink=(0.45, 0.25, 0.55),
                         joint_gap=(9.0, 14.0)),
                    dict(cx=-13.0, cy=5.0, wx=8.5, wf=5.0, wb=5.0, top=9.5, shrink=(0.3, 0.15, 0.3)),
                ])


# =============================================================================================
# small rocks
# =============================================================================================
def drop_onto(bm, bvh, sink):
    """Lower bm straight down until it rests on bvh (or the ground), then sink it a little."""
    lo, hi = bounds(bm)
    zc = 0.5 * (lo.z + hi.z)
    best = lo.z
    if bvh is not None:
        for v in bm.verts:
            if v.co.z > zc:
                continue
            hit = bvh.ray_cast(v.co, DOWN, 200.0)
            if hit[0] is not None:
                best = min(best, hit[3])
    move(bm, (0, 0, -(best + sink)))
    if bounds(bm)[0].z < 0.0:
        cut(bm, (0, 0, 0), DOWN)


def build_rock_pile():
    rng = random.Random(1207)
    root = lib.begin("RockPile", kind="Rock", notes="Heap of 8 rocks, 6 studs across")
    tones = [("Stone", (122, 119, 112)), ("Stone", (104, 102, 98)), ("DarkStone", (84, 83, 85))]
    # size, x, y, tone - placed in order, each dropped onto what is already there
    specs = [(2.7, -0.5, -0.15, 0), (2.3, 1.45, 0.35, 1), (1.9, -2.05, 0.65, 0), (1.35, 2.55, -0.95, 2),
             (1.25, 0.3, 1.55, 1), (1.05, -1.45, -1.35, 0), (1.45, 0.45, 0.05, 0), (0.95, -0.95, 0.55, 2)]
    made = []
    for size, x, y, tone in specs:
        bm = boulder(rng, size, height=rng.uniform(0.48, 0.62), footprint=rng.uniform(0.62, 0.82), cuts=2,
                     roundness=0.6, primary=8, secondary=5, sink=0.0, wedge=(0.2, 0.4))
        move(bm, (x, y, 30.0))
        bvh = None
        if made:
            acc = merged([m[0] for m in made], free=False)
            bvh = BVHTree.FromBMesh(acc)
            acc.free()
        drop_onto(bm, bvh, 0.13 * size)
        made.append((bm, tone))
    groups = {}
    for bm, tone in made:
        groups.setdefault(tone, []).append(bm)
    parts = []
    for tone in sorted(groups):
        role, rgb = tones[tone]
        parts.append((to_obj("RockPile_g", merged(groups[tone])), role, rgb, dict(collision="Hull")))
    lo, hi = ls.world_bounds([p[0] for p in parts])
    s = 6.0 / max(hi.x - lo.x, hi.y - lo.y)
    for p in parts:
        p[0].data.transform(Matrix.Diagonal((s, s, s, 1.0)))
    finalize(root, parts)


def pebble(rng, length):
    w = length * rng.uniform(0.55, 0.85)
    h = length * rng.uniform(0.3, 0.42)
    bm = bmesh.new()
    for _ in range(11):
        d = rand_dir(rng, -70, 70)
        bm.verts.new((d.x * length / 2, d.y * w / 2, d.z * h / 2))
    bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    xform(bm, Matrix.Rotation(rng.uniform(0, 2 * math.pi), 4, "Z"))
    ground(bm, h * 0.22)
    return bm


def build_pebbles():
    rng = random.Random(1319)
    root = lib.begin("Pebbles", kind="Rock", notes="Decorative flat scatter, no collision")
    tones = [("Stone", (130, 127, 120)), ("Stone", (106, 104, 99)), ("DarkStone", (86, 85, 87))]
    placed = []
    tries = 0
    while len(placed) < 24 and tries < 5000:
        tries += 1
        x = rng.gauss(0.0, 1.5)
        y = rng.gauss(0.0, 1.05)
        if abs(x) > 3.3 or abs(y) > 2.3:
            continue
        r = 0.55 - 0.07 * math.hypot(x / 1.5, y / 1.05) + rng.uniform(-0.12, 0.14)
        r = max(0.17, r)
        if any(math.hypot(x - px, y - py) < (r + pr) * 0.66 for px, py, pr in placed):
            continue
        placed.append((x, y, r))
    groups = {}
    for i, (x, y, r) in enumerate(placed):
        bm = pebble(rng, 2 * r)
        move(bm, (x, y, 0))
        tone = 0 if i % 5 in (0, 2) else (1 if i % 5 in (1, 4) else 2)
        groups.setdefault(tone, []).append(bm)
    parts = []
    for tone in sorted(groups):
        role, rgb = tones[tone]
        parts.append((to_obj("Pebbles_g", merged(groups[tone])), role, rgb, dict(collide=False, cast_shadow=False)))
    finalize(root, parts)


# =============================================================================================
# standing stones
# =============================================================================================
def standing_stone(rng, w, t, h, lean_deg, lean_az, sides=12, rings=8):
    e = 2.0 / 3.6
    base = []
    for i in range(sides):
        a = 2 * math.pi * (i + rng.uniform(-0.15, 0.15)) / sides
        ca, sa = math.cos(a), math.sin(a)
        base.append((math.copysign(abs(ca) ** e, ca) * w / 2, math.copysign(abs(sa) ** e, sa) * t / 2))
    bm = bmesh.new()
    loops = []
    for r in range(rings):
        f = r / (rings - 1)
        z = -0.5 + f * (h + 0.5)
        s = 1.0 + 0.07 * math.sin(math.pi * min(1.0, f / 0.6)) - 0.3 * f ** 1.7 + 0.1 * (1 - f) ** 6
        sx = s * rng.uniform(0.96, 1.04)
        sy = (1.0 - 0.18 * f) * s * rng.uniform(0.95, 1.05)
        tw = math.radians(4.0) * f
        ct, st = math.cos(tw), math.sin(tw)
        loops.append([bm.verts.new((x * sx * ct - y * sy * st, x * sx * st + y * sy * ct, z)) for x, y in base])
    for r in range(rings - 1):
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((loops[r][j], loops[r][k], loops[r + 1][k], loops[r + 1][j]))
    apex = bm.verts.new((rng.uniform(-0.2, 0.2) * w, 0.0, h + 0.4 * t))
    for j in range(sides):
        bm.faces.new((loops[-1][j], loops[-1][(j + 1) % sides], apex))
    bm.faces.new(list(reversed(loops[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    off = rand_off(rng)
    for v in bm.verts:
        v.co += v.normal * (0.06 * w * fbm(v.co * (1.5 / w) + off, 2))
    for sy in (-1.0, 1.0):    # broad split faces
        chip(bm, (rng.uniform(-0.12, 0.12), sy, rng.uniform(-0.05, 0.1)), rng.uniform(0.04, 0.07))
    top_dir = rng.choice((-1.0, 1.0))   # slanted, broken top
    chip(bm, (top_dir * math.cos(math.radians(48)), rng.uniform(-0.2, 0.2), math.sin(math.radians(48))),
         rng.uniform(0.07, 0.11))
    chip(bm, (-top_dir * math.cos(math.radians(62)), rng.uniform(-0.3, 0.3), math.sin(math.radians(62))),
         rng.uniform(0.03, 0.05))
    for _ in range(6):
        chip(bm, rand_dir(rng, 0, 45), rng.uniform(0.025, 0.06))
    xform(bm, Matrix.Rotation(math.radians(lean_deg), 4, Vector((math.cos(lean_az), math.sin(lean_az), 0.0))))
    cut(bm, (0, 0, 0), DOWN)
    return bm


def build_standing_stones():
    rng = random.Random(7077)
    root = lib.begin("StandingStones", kind="Landmark",
                     notes="Fragment of a stone ring; the ring centre lies ~13 studs in front (+Y)")
    R = 13.0
    # angle on the ring (deg), width, thickness, height, lean (deg), rgb
    specs = [(-28.0, 3.7, 1.8, 6.6, 6.5, (138, 132, 124)),
             (0.0, 4.3, 2.1, 8.8, 2.0, (146, 140, 131)),
             (26.0, 3.9, 1.9, 7.6, 4.0, (133, 128, 121))]
    parts, patches = [], []
    for ang, w, t, h, lean, rgb in specs:
        a = math.radians(ang)
        lean_az = a - math.pi / 2 + rng.uniform(-0.6, 0.6)     # lean outward-ish
        bm = standing_stone(rng, w, t, h, lean, lean_az)
        xform(bm, Matrix.Rotation(a, 4, "Z"))
        move(bm, (R * math.sin(a), R - R * math.cos(a), 0.0))
        tp = top_point(bm, rng, 0.12)
        p = moss_patch(bm, DOWN, [(tp, 0.45 * w), (tp + Vector((0.25 * w, 0.0, 0.0)), 0.3 * w)], rng,
                       min_dot=0.3, lift=0.05)
        if p is not None:
            patches.append(p)
        outward = Vector((math.sin(a), -math.cos(a), 0.0))
        lo, hi = bounds(bm)
        foot = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0.75))
        side = Vector((math.cos(a), math.sin(a), 0.0))
        p = moss_patch(bm, -outward, [(foot + side * rng.uniform(-0.6, 0.6), 1.25),
                                      (foot + side * rng.uniform(-1.0, 1.0) + UP * 0.6, 0.8)], rng,
                       min_dot=0.25, lift=0.05)
        if p is not None:
            patches.append(p)
        parts.append((to_obj("StandingStones_s", bm), "Granite", rgb, dict(collision="Hull")))
    if patches:
        parts.append((shell("StandingStones_m", merged(patches), 0.13), "Moss", (84, 106, 54),
                      dict(collide=False, cast_shadow=False)))
    shift = finalize(root, parts)
    # centre of the stone ring this fragment belongs to (for placing more stones, a fire, loot...)
    lib.attach(root, "RingCenter", Vector((0.0, R, 0.0)) + shift)


# =============================================================================================
# flat stone
# =============================================================================================
def build_flat_stone():
    rng = random.Random(6067)
    root = lib.begin("FlatStone", kind="Rock", notes="10 x 8 x 1.5 slab; walkable top")
    P = hull2d([(5.95 * x, 4.15 * y) for x, y in unit_poly(rng, 11, boxy=2.3, jitter=0.25)])
    dip = (0.004, -0.003)
    th = math.radians(12.0)
    crack = ((1.2, 0.0), (math.sin(th), math.cos(th)), (math.cos(th), -math.sin(th)))
    top_a = make_piece(P, 0.4, 1.46, dip, rng, delta=-0.3, lean=9.0, right=crack, chamfer_p=0.95,
                       chamfer=(0.2, 0.45), chips=1, undercut_p=0.0, corner_p=0.7, corner=(0.3, 0.8))
    top_b = make_piece(P, 0.4, 1.36, dip, rng, delta=-0.4, lean=9.0, left=crack, chamfer_p=0.95,
                       chamfer=(0.2, 0.45), chips=1, undercut_p=0.0, corner_p=0.7, corner=(0.3, 0.8))
    foot = make_piece(P, 0.0, 0.62, (0.0, 0.0), rng, delta=0.05, lean=32.0, chamfer_p=0.0, chips=0,
                      flat_bottom=True, corner_p=0.8, corner=(0.3, 0.9), edge_jitter=0.3)
    top = merged([top_a, top_b])
    lo, hi = bounds(top)
    corner = Vector((lo.x + 2.0, hi.y - 1.9, 0.0))
    moss = moss_patch(top, DOWN, [(corner, 1.9), (corner + Vector((1.5, 0.5, 0.0)), 1.1),
                                  (corner + Vector((-0.4, -1.5, 0.0)), 0.9)], rng, min_dot=0.3, lift=0.04)
    parts = [(to_obj("FlatStone_s", top), "Stone", (126, 122, 115), dict(collision="Hull")),
             (to_obj("FlatStone_f", foot), "Stone", (108, 106, 101), dict(collision="Hull"))]
    if moss is not None:
        parts.append((shell("FlatStone_m", moss, 0.12), "Moss", (88, 110, 56), dict(collide=False, cast_shadow=False)))
    finalize(root, parts)


# =============================================================================================
# rock arch
# =============================================================================================
def arch_cutter(rng, a, b, rings, skew=0.0, n=18):
    """Lofted arch-shaped tunnel (closed solid) subtracted from the fin; flares at both ends."""
    prof = [(a, -4.0)] + [(a * math.cos(math.pi * i / n), b * math.sin(math.pi * i / n) ** 0.8)
                          for i in range(n + 1)] + [(-a, -4.0)]
    bm = bmesh.new()
    loops = []
    for (y, s, dx) in rings:
        ring = []
        for j, (x, z) in enumerate(prof):
            inner = 0 < j < len(prof) - 1
            jx = rng.uniform(-0.2, 0.2) if inner else 0.0
            jz = rng.uniform(-0.15, 0.15) if inner else 0.0
            zz = (z * s if z > 0 else z) + jz
            ring.append(bm.verts.new((x * s + dx + jx + skew * max(zz, 0.0), y, zz)))
        loops.append(ring)
    K = len(prof)
    for r in range(len(loops) - 1):
        for j in range(K):
            k = (j + 1) % K
            bm.faces.new((loops[r][j], loops[r][k], loops[r + 1][k], loops[r + 1][j]))
    bm.faces.new(loops[0])
    bm.faces.new(list(reversed(loops[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def boolean_difference(obj, cutter):
    mod = obj.modifiers.new("Opening", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    try:
        mod.solver = "EXACT"
    except Exception:
        pass
    ls.apply_modifiers(obj)


def build_arch():
    rng = random.Random(9011)
    root = lib.begin("RockArch", kind="Landmark", notes="Natural arch; walk through along Y")
    # an eroded fin: flat-topped, legs flaring into the ground, thicker at the base
    W0, D0, H0 = 22.0, 10.5, 16.0
    bm = grid_box(W0, D0, H0, 11, 4, 8)
    move(bm, (0, 0, H0 / 2 - 1.0))
    for v in bm.verts:
        x, y, z = v.co.x, v.co.y, v.co.z
        f = max(0.0, min(1.0, (z + 1.0) / H0))
        x = x * (1.0 + 0.2 * (1.0 - f) ** 1.6)
        y = y * (1.18 - 0.38 * f) + 0.008 * x * x - 0.5
        v.co = Vector((x, y, z))
    bm.normal_update()
    off = rand_off(rng)
    for v in bm.verts:
        v.co += v.normal * (0.6 * fbm(v.co * 0.1 + off, 2) + 0.2 * noise.noise(v.co * 0.33 + off))
    for sx in (-1, 1):   # big shoulder planes, different on each side
        chip(bm, (sx * math.cos(math.radians(rng.uniform(30, 40))), rng.uniform(-0.15, 0.15),
                  math.sin(math.radians(rng.uniform(30, 40)))), rng.uniform(0.1, 0.14))
        chip(bm, (sx * math.cos(math.radians(60)), rng.uniform(-0.25, 0.25), math.sin(math.radians(60))),
             rng.uniform(0.05, 0.08))
        chip(bm, (sx * math.cos(math.radians(14)), rng.uniform(-0.25, 0.25), math.sin(math.radians(14))),
             rng.uniform(0.03, 0.05))
    for sy in (-1, 1):
        for _ in range(3):
            chip(bm, (rng.uniform(-0.45, 0.45), sy, rng.uniform(-0.1, 0.45)), rng.uniform(0.04, 0.08))
    for _ in range(7):
        chip(bm, rand_dir(rng, 8, 70), rng.uniform(0.02, 0.05))
    chip(bm, (rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 1.0), 0.03)
    fin = to_obj("RockArch_fin", bm)
    rings = [(-8.0, 1.3, 0.3), (-4.0, 1.1, 0.15), (-1.4, 1.0, 0.0), (1.5, 1.0, -0.1), (4.2, 1.12, -0.2),
             (8.0, 1.34, -0.35)]
    rings = [(y - 0.5, s, dx + 0.8) for (y, s, dx) in rings]
    cutter = to_obj("RockArch_cutter", arch_cutter(rng, 5.3, 9.6, rings, skew=0.06))
    boolean_difference(fin, cutter)
    bpy.data.objects.remove(cutter, do_unlink=True)
    bm = bmesh.new()
    bm.from_mesh(fin.data)
    me = fin.data
    bpy.data.objects.remove(fin, do_unlink=True)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-4)
    cut(bm, (0, 0, 0), DOWN)
    lo, hi = bounds(bm)
    sxy = 20.0 / (hi.x - lo.x)
    sz = 14.0 / (hi.z - lo.z)
    c = (lo + hi) * 0.5
    xform(bm, Matrix.Diagonal((sxy, sxy, sz, 1.0)) @ Matrix.Translation(Vector((-c.x, -c.y, -lo.z))))
    n = strata_normal(rng, 2.0)
    levels = [lv + rng.uniform(-0.2, 0.2) for lv in (2.4, 4.6, 7.4, 10.5, 12.4)]
    for lv in levels[1:]:
        groove(bm, Vector((0, 0, 0)), n, lv, 0.11, 0.22, rng=rng, fade_freq=0.12)
    bvh = BVHTree.FromBMesh(bm)
    clear = [bvh.ray_cast(Vector((0, y, 0.05)), UP, 50.0)[3] for y in (-2.0, 0.0, 2.0)]
    widths, mids = [], []
    for z in (1.0, 5.5):
        hx1 = bvh.ray_cast(Vector((0, 0, z)), Vector((1, 0, 0)), 50.0)[3] or 0.0
        hx0 = bvh.ray_cast(Vector((0, 0, z)), Vector((-1, 0, 0)), 50.0)[3] or 0.0
        widths.append(hx0 + hx1)
        mids.append(0.5 * (hx1 - hx0))
    print("ARCH clearance under span:", ["%.2f" % (c or -1) for c in clear], "opening width at z=1, 5.5:",
          ["%.2f" % w for w in widths])
    lo, hi = bounds(bm)
    yc = (lo.y + hi.y) / 2
    moss = moss_patch(bm, DOWN, [(Vector((-1.2, yc + 0.3, 0)), 3.2), (Vector((2.6, yc - 0.6, 0)), 2.3),
                                 (Vector((-4.6, yc - 0.2, 0)), 1.9), (Vector((5.4, yc + 0.8, 0)), 1.3)],
                      rng, min_dot=0.5, lift=0.08)
    if moss is not None:   # keep only the patch on the crest (drop bits on lower ledges)
        lo_m = min(v.co.z for v in moss.verts)
        if lo_m < 9.0:
            low = [f for f in moss.faces if f.calc_center_median().z < 9.0]
            bmesh.ops.delete(moss, geom=low, context="FACES")
    # talus blocks at the feet of the legs (front and back)
    talus = []
    for (tx, ty, ts) in ((-7.6, 4.2, 2.6), (8.4, 3.6, 2.0), (-8.6, -4.0, 2.2), (6.8, -4.4, 3.0), (-4.6, 4.6, 1.4)):
        b = boulder(rng, ts, height=rng.uniform(0.55, 0.7), cuts=2, primary=10, secondary=4, sink=0.12)
        move(b, (tx, ty + yc, 0.0))
        talus.append(b)
    bands = []
    cuts_at = [None, levels[1], levels[3], None]
    for i in range(3):
        b = bm.copy()
        if cuts_at[i + 1] is not None:
            cut(b, n * cuts_at[i + 1], n)
        if cuts_at[i] is not None:
            cut(b, n * cuts_at[i], -n)
        bands.append(b)
    bm.free()
    bands[0] = merged([bands[0]] + talus)
    tones = [(120, 116, 108), (133, 127, 117), (114, 112, 107)]
    # PreciseConvexDecomposition (not Default): the bands wrap a walk-through passage, and the coarse Default
    # decomposition can bridge the 8-stud opening (same rule as the LobbyGate arch)
    parts = [(to_obj("RockArch_s", b), "Stone", tones[i], dict(collision="PreciseConvexDecomposition"))
             for i, b in enumerate(bands)]
    if moss is not None and moss.faces:
        parts.append((shell("RockArch_m", moss, 0.2), "Moss", (82, 106, 54), dict(collide=False, cast_shadow=False)))
    shift = finalize(root, parts)
    # ground point in the middle of the opening; LookVector runs along the passage
    lib.attach(root, "PassageCenter", Vector((mids[0], 0.0, 0.0)) + shift, look=(0, 1, 0), up=(0, 0, 1))


# =============================================================================================
bpy.context.scene.display.shadow_shift = 0.6     # softer self-shadow terminator on low-poly faces in previews
build_boulders()
build_cliffs()
build_rock_pile()
build_pebbles()
build_standing_stones()
build_flat_stone()
build_arch()
lib.export(out_dir, preview_dir)
