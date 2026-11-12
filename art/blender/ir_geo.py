"""
ir_geo.py - geometry toolkit for items_real.py (realistic ItemsReal set).

Every builder here returns a mesh with UVs in STUD units, so all pieces of a texture set share one texel density
before packing:
  - ring-based meshes (lofts, lathes, sweeps, grips, blades, tori) get analytic "unrolled" UVs: one island per
    tube (u = arc length around the ring, v = distance along the rings), caps projected flat;
  - anything else (boxes, extruded plates) is smart-projected per piece and rescaled to studs (uv_smart).
Pieces are then tagged for the texture bake (piece() -> tex_items.tag). Reuses the v1 helpers in items_kit
(curve, rrect...) without modifying them.
"""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

import items_kit as kit
import ls_common as ls
import tex_items as tx
from items_kit import curve, lerp, smoothstep  # noqa: F401  (re-exported for the builders)

V = Vector
TAU = 2.0 * math.pi
RNG = random.Random(5150)


def reseed(s):
    RNG.seed(s)


# =============================================================================================== ring meshes
def _plane_uv(pts, center=None):
    """Project points onto their best-fit plane -> list of (u, v) in studs."""
    P = [V(p) for p in pts]
    c = V(center) if center is not None else sum(P, V()) / len(P)
    n = V()
    for i in range(len(P)):
        a, b = P[i], P[(i + 1) % len(P)]
        n += V(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    if n.length < 1e-12:
        n = V((0, 0, 1))
    n.normalize()
    e1 = (P[0] - c)
    e1 = e1 - n * e1.dot(n)
    if e1.length < 1e-9:
        e1 = n.orthogonal()
    e1.normalize()
    e2 = n.cross(e1)
    return [((p - c).dot(e1), (p - c).dot(e2)) for p in P], c, e1, e2


def rings_mesh(name, rings, close_u=True, cap_start="flat", cap_end="flat", close_v=False, gco_rings=None):
    """Skin rings (equal-length lists of 3D points) with quads and analytic UVs (studs).
    cap: None | 'flat' (n-gon) | 'fan' (centre point) | a 3D point (pole). close_v joins the last ring to the first.
    gco_rings (same shape as rings): per-point grain coordinates (x along the path, y/z across the section);
    stored on the object and used by piece() instead of the straight-axis frame (grain follows bent pieces)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    nr = len(rings)
    n = len(rings[0])
    pts = [[V(p) for p in r] for r in rings]
    vr = [[bm.verts.new(p) for p in r] for r in pts]
    # u: arc length around each ring (centred), v: mean distance between consecutive rings
    U = []
    for r in pts:
        acc = [0.0]
        for i in range(1, n + (1 if close_u else 0)):
            acc.append(acc[-1] + (r[i % n] - r[i - 1]).length)
        half = acc[-1] / 2.0
        U.append([a - half for a in acc])
    Vv = [0.0]
    for k in range(1, nr + (1 if close_v else 0)):
        a, b = pts[k - 1], pts[k % nr]
        Vv.append(Vv[-1] + sum((b[i] - a[i]).length for i in range(n)) / n)
    rows = nr if close_v else nr - 1
    for k in range(rows):
        k2 = (k + 1) % nr
        for i in range(n if close_u else n - 1):
            j = (i + 1) % n
            try:
                f = bm.faces.new((vr[k][i], vr[k][j], vr[k2][j], vr[k2][i]))
            except ValueError:
                continue
            Uk = U[k]
            Uk2 = U[k2] if not (close_v and k == nr - 1) else U[0]
            uv = [(Uk[i], Vv[k]), (Uk[i + 1], Vv[k]), (Uk2[i + 1], Vv[k + 1]), (Uk2[i], Vv[k + 1])]
            for l, (u, v) in zip(f.loops, uv):
                l[uvl].uv = (u, v)
    span_u = max(max(abs(x) for x in u) for u in U) + 0.02
    vmax = Vv[-1]

    def cap(ring_i, where, rev, offset):
        if where is None or not close_u:
            return
        rv = vr[ring_i]
        uvs, c, e1, e2 = _plane_uv(pts[ring_i])
        if where == "flat":
            try:
                f = bm.faces.new(list(reversed(rv)) if rev else rv)
            except ValueError:
                return
            lookup = {v: uv for v, uv in zip(rv, uvs)}
            for l in f.loops:
                u, v = lookup[l.vert]
                l[uvl].uv = (u + offset[0], v + offset[1])
            return
        pole = sum(pts[ring_i], V()) / n if where == "fan" else V(where)
        pv = bm.verts.new(pole)
        puv = ((pole - c).dot(e1), (pole - c).dot(e2))
        for i in range(n):
            j = (i + 1) % n
            tri = (rv[j], rv[i], pv) if rev else (rv[i], rv[j], pv)
            try:
                f = bm.faces.new(tri)
            except ValueError:
                continue
            for l in f.loops:
                if l.vert is pv:
                    u, v = puv
                else:
                    u, v = uvs[rv.index(l.vert)]
                l[uvl].uv = (u + offset[0], v + offset[1])

    if not close_v:
        r0 = max((p - sum(pts[0], V()) / n).length for p in pts[0])
        r1 = max((p - sum(pts[-1], V()) / n).length for p in pts[-1])
        cap(0, cap_start, True, (span_u + r0 + 0.03, r0))
        cap(nr - 1, cap_end, False, (span_u + r1 + 0.03, vmax - r1))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = ls.from_bmesh(name, bm)
    ob["_uv_studs"] = 1
    if gco_rings is not None:
        _store_gco(ob, [p for r in rings for p in r], [g for r in gco_rings for g in r])
    return ob


def _store_gco(ob, pts, gcos):
    """Map per-point grain coordinates onto the final vertices (nearest source point; caps get the coordinates of
    their rim) and keep them on the object for piece()."""
    from mathutils import kdtree
    kd = kdtree.KDTree(len(pts))
    for i, p in enumerate(pts):
        kd.insert(V(p), i)
    kd.balance()
    out = []
    for v in ob.data.vertices:
        _co, i, _d = kd.find(v.co)
        out.append(tuple(gcos[i]))
    ob["_gco"] = [c for t in out for c in t]


def ring(center, r_x, r_y, n, phase=0.0, fn=None, axes=((1, 0, 0), (0, 1, 0)), p=2.0):
    """Ring around center in the plane of axes (x, y); superellipse exponent p; fn(angle) -> radius scale."""
    cx = V(center)
    ax, ay = V(axes[0]), V(axes[1])
    pts = []
    for i in range(n):
        a = TAU * i / n + phase
        c, s = math.cos(a), math.sin(a)
        e = 2.0 / p
        x = math.copysign(abs(c) ** e, c) * r_x
        y = math.copysign(abs(s) ** e, s) * r_y
        k = fn(a) if fn else 1.0
        pts.append(cx + ax * (x * k) + ay * (y * k))
    return pts


def lathe(name, profile, segs=16, r_fn=None, phase=0.0, sx=1.0, sy=1.0, cap_start="fan", cap_end="fan"):
    """Revolve (r, z) bottom -> top around Z. End points with r ~ 0 become poles. r_fn(angle, z) -> scale."""
    rings = []
    for (r, z) in profile:
        row = []
        for i in range(segs):
            a = TAU * i / segs + phase
            rr = r * (r_fn(a, z) if r_fn else 1.0)
            row.append((rr * math.cos(a) * sx, rr * math.sin(a) * sy, z))
        rings.append(row)
    start, end = cap_start, cap_end
    if profile[0][0] < 1e-5:
        start = (0, 0, profile[0][1])
        rings = rings[1:]
    if profile[-1][0] < 1e-5:
        end = (0, 0, profile[-1][1])
        rings = rings[:-1]
    return rings_mesh(name, rings, cap_start=start, cap_end=end)


def sweep_rings(path, section, scale_fn=None, up=(1, 0, 0), with_gco=False):
    """Rings of a closed 2D section [(a, b)] swept along a 3D polyline (parallel-transport frames, as
    items_kit.sweep). scale_fn(t) -> (sa, sb). with_gco also returns per-point (arc length, a, b)."""
    pts = [V(p) for p in path]
    n = len(pts)
    lengths = [0.0]
    for i in range(1, n):
        lengths.append(lengths[-1] + (pts[i] - pts[i - 1]).length)
    total = lengths[-1] or 1.0
    tangents = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        tangents.append(t.normalized())
    u = V(up)
    nrm = u - tangents[0] * u.dot(tangents[0])
    if nrm.length < 1e-6:
        nrm = tangents[0].orthogonal()
    nrm.normalize()
    rings = []
    gco = []
    for i in range(n):
        if i > 0:
            axis = tangents[i - 1].cross(tangents[i])
            if axis.length > 1e-9:
                nrm = Quaternion(axis.normalized(), tangents[i - 1].angle(tangents[i])) @ nrm
            nrm = (nrm - tangents[i] * nrm.dot(tangents[i])).normalized()
        b = tangents[i].cross(nrm)
        sa, sb = scale_fn(lengths[i] / total) if scale_fn else (1.0, 1.0)
        rings.append([pts[i] + nrm * (a * sa) + b * (bb * sb) for (a, bb) in section])
        gco.append([(lengths[i], a * sa, bb * sb) for (a, bb) in section])
    if with_gco:
        return rings, gco
    return rings


def sweep(name, path, section, scale_fn=None, up=(1, 0, 0), caps=True):
    rings, gco = sweep_rings(path, section, scale_fn, up, with_gco=True)
    return rings_mesh(name, rings, cap_start="flat" if caps else None, cap_end="flat" if caps else None,
                      gco_rings=gco)


def tube(name, path, radius, segs=8, scale_fn=None, up=(1, 0, 0), caps=True):
    return sweep(name, path, kit.circle(segs, radius), scale_fn, up, caps)


def strap(name, path, w, t, up=(0, 1, 0), chamfer=0.004, scale_fn=None):
    return sweep(name, path, kit.rrect(w, t, chamfer), scale_fn, up)


def torus(name, major, minor, segs=16, minor_segs=6, center=(0, 0, 0), axis=(0, 0, 1), sx=1.0, sy=1.0):
    """Closed ring tube (UV'd), circle of radius `major` around `axis` through center."""
    ax = V(axis).normalized()
    e1 = ax.orthogonal().normalized()
    e2 = ax.cross(e1)
    rings = []
    for k in range(segs):
        a = TAU * k / segs
        c = V(center) + e1 * (math.cos(a) * major * sx) + e2 * (math.sin(a) * major * sy)
        radial = (e1 * math.cos(a) * sy + e2 * math.sin(a) * sx).normalized()
        rings.append([c + radial * (minor * math.cos(b)) + ax * (minor * math.sin(b))
                      for b in (TAU * j / minor_segs for j in range(minor_segs))])
    return rings_mesh(name, rings, cap_start=None, cap_end=None, close_v=True)


def smooth_path(pts, n=24):
    """Catmull-Rom resample of a 3D polyline."""
    P = [V(p) for p in pts]
    out = []
    for i in range(len(P) - 1):
        p0 = P[max(i - 1, 0)]
        p1, p2 = P[i], P[i + 1]
        p3 = P[min(i + 2, len(P) - 1)]
        steps = max(2, n // (len(P) - 1))
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    return [tuple(p) for p in out]


# =============================================================================================== other meshes
def uv_smart(obj, angle=60.0):
    """Smart-project one piece and rescale its UVs to studs (1 UV unit = 1 stud)."""
    tx._set_mode([obj], "EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), margin_method="FRACTION", island_margin=0.01,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    a2, a3 = tx.uv_area_and_3d(obj)
    if a2 > 0:
        k = math.sqrt(a3 / a2)
        uv = obj.data.uv_layers.active.data
        arr = np.empty(len(uv) * 2, dtype=np.float32)
        uv.foreach_get("uv", arr)
        uv.foreach_set("uv", arr * k)
        obj.data.update()
    obj["_uv_studs"] = 1
    return obj


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0)):
    o = ls.cube(name, size=size, loc=loc, rot=rot)
    return tx.bake_xform(o)


def cbox(name, size, chamfer=0.01, loc=(0, 0, 0), rot=(0, 0, 0)):
    o = kit.chamfer_box(name, size, chamfer, loc=loc, rot=rot)
    return tx.bake_xform(o)


def cyl(name, r, z0, z1, segs=12, r_top=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    o = lathe(name, [(0.0, z0), (r, z0), (r if r_top is None else r_top, z1), (0.0, z1)], segs=segs)
    o.location = loc
    o.rotation_euler = rot
    return tx.bake_xform(o)


def place(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    return tx.bake_xform(obj)


def xform(obj, M):
    obj.data.transform(M)
    obj.data.update()
    return obj


def orient_to(obj, origin, z_axis, y_hint):
    """Rotate a +Z-pointing local shape so +Z follows z_axis, local Y faces y_hint, then translate."""
    zv = V(z_axis).normalized()
    yv = V(y_hint)
    yv = (yv - zv * yv.dot(zv)).normalized()
    xv = yv.cross(zv)
    M = Matrix((xv, yv, zv)).transposed().to_4x4()
    M.translation = V(origin)
    return xform(obj, M)


def jitter(obj, amount, rng=None, fn=None):
    rng = rng or RNG
    for v in obj.data.vertices:
        k = fn(v.co) if fn else 1.0
        v.co += V((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amount * k
    obj.data.update()
    return obj


def noise_displace(obj, amount, scale, seed=0, fn=None):
    """Smooth 3D-noise displacement (tex_items.fbm) along vertex normals."""
    me = obj.data
    me.update()
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    nr = np.empty(n * 3)
    me.vertices.foreach_get("normal", nr)
    nr = nr.reshape(n, 3)
    d = tx.fbm(co, 1.0 / scale, 3, seed=seed)
    if fn is not None:
        d = d * np.array([fn(V(c)) for c in co])
    co = co + nr * (d * amount)[:, None]
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    return obj


# =============================================================================================== blades
def blade(name, sts, section, edges=("front",), band=0.022, tip_cap=True):
    """Blade solid lofted through horizontal stations. sts: [(z, y_back, y_front)] bottom -> tip.
    section(s, z, yb, yf) -> list of (y, hx) across the TOP surface from back to front (hx = half thickness,
    tiny at a sharpened edge, > 0 at a flat spine); the bottom surface mirrors x. The honed band (a0: 1 at the
    cutting edge, 0 beyond `band` studs) is stored for piece()."""
    rings = []
    honed = []
    n = len(sts)
    for k, (z, yb, yf) in enumerate(sts):
        s = k / (n - 1)
        top = section(s, z, yb, yf)
        loop = [(hx, y, z) for (y, hx) in top] + [(-hx, y, z) for (y, hx) in reversed(top)]
        rings.append(loop)
        hb = []
        for (x, y, zz) in loop:
            d = 9.0
            if "front" in edges:
                d = min(d, abs(yf - y))
            if "back" in edges:
                d = min(d, abs(y - yb))
            hb.append(max(0.0, 1.0 - d / band))
        honed.append(hb)
    obj = rings_mesh(name, rings, cap_start="flat", cap_end="flat" if tip_cap else None)
    flat_pts = np.array([p for r in rings for p in r])
    flat_h = np.array([h for r in honed for h in r])
    co = np.array([tuple(v.co) for v in obj.data.vertices])
    d = ((co[:, None, :] - flat_pts[None, :, :]) ** 2).sum(axis=2)
    obj["_a0"] = list(flat_h[np.argmin(d, axis=1)])
    return obj


def apply_a0_from_prop(obj):
    if "_a0" in obj.keys():
        vals = list(obj["_a0"])
        at = obj.data.attributes["a0"]
        at.data.foreach_set("value", np.array(vals, dtype=np.float32))
        obj.data.update()
        del obj["_a0"]


def stations(z0, z1, n, back_fn, front_fn, power=1.0):
    out = []
    for k in range(n + 1):
        t = k / n
        s = 1.0 - (1.0 - t) ** power
        out.append((lerp(z0, z1, s), back_fn(s), front_fn(s)))
    return out


# =============================================================================================== grips and wraps
def ribbed_grip(name, z0, z1, rx, ry, segs=14, ribs=8, depth=0.006, flare=None, rows_per_rib=4, offset=(0, 0),
                p=2.2, tilt=0.0):
    """Oval grip around Z with rounded ribs (stacked washers, cord turns, risers). flare(t) scales the section.
    tilt skews the ribs into a helix (wrapped cord / strip)."""
    rows = ribs * rows_per_rib + 1
    rings = []
    for k in range(rows):
        t = k / (rows - 1)
        z = lerp(z0, z1, t)
        ph = (t * ribs) % 1.0
        rib = 0.5 - 0.5 * math.cos(TAU * ph)
        f = flare(t) if flare else 1.0
        endfade = smoothstep(0.0, 0.5 / ribs, t) * smoothstep(1.0, 1.0 - 0.5 / ribs, t)
        k_r = f * (1.0 + depth / max(min(rx, ry), 1e-4) * (rib - 0.5) * 2.0 * endfade)
        pts = []
        for i in range(segs):
            a = TAU * i / segs
            c, s = math.cos(a), math.sin(a)
            e = 2.0 / p
            x = math.copysign(abs(c) ** e, c) * rx * k_r + offset[0]
            y = math.copysign(abs(s) ** e, s) * ry * k_r + offset[1]
            dz = tilt * (a / TAU) * (z1 - z0) / ribs if tilt else 0.0
            pts.append((x, y, z + dz * endfade))
        rings.append(pts)
    return rings_mesh(name, rings, cap_start="flat", cap_end="flat")


def angle_attr(obj, center=(0, 0), axis="Z"):
    """Callable for tag(a=...): angular phase 0..1 around the axis through center."""
    def f(co):
        if axis == "Z":
            return (math.atan2(co.y - center[1], co.x - center[0]) / TAU) % 1.0
        if axis == "X":
            return (math.atan2(co.z - center[1], co.y - center[0]) / TAU) % 1.0
        return (math.atan2(co.x - center[1], co.z - center[0]) / TAU) % 1.0
    return f


def piece(obj, mid, axis=(0, 0, 1), origin=(0, 0, 0), bevr=0.008, rnd=None, a=None, up=(0, 0, 1), uvw=1.0,
          shade=None, path_grain=True, seed_offset=True):
    """Bake transform, make sure the piece has stud-unit UVs, tag it for the texture bake.
    uvw = texel-density weight of this piece (hidden faces < 1, hero surfaces > 1); a callable uvw(center, normal)
    sets it per face. shade = None (flat facets, e.g. blades) or a smooth angle in degrees, kept through the join
    when the part is added with smooth='keep'. Swept pieces use their path coordinates as grain (path_grain)."""
    tx.bake_xform(obj)
    if "_uv_studs" not in obj.keys() or not obj.data.uv_layers:
        uv_smart(obj)
    rnd = RNG.random() if rnd is None else rnd
    tx.tag(obj, mid, axis=axis, origin=origin, rnd=rnd, bevr=bevr, up=up, a=a, uvw=1.0 if callable(uvw) else uvw,
           seed_offset=seed_offset)
    if callable(uvw):
        me = obj.data
        vals = np.array([float(uvw(p.center, p.normal)) for p in me.polygons], dtype=np.float32)
        me.attributes["uvw"].data.foreach_set("value", vals)
    if path_grain and "_gco" in obj.keys():
        g = np.array(list(obj["_gco"]), dtype=np.float64).reshape(-1, 3)
        if len(g) == len(obj.data.vertices):
            if seed_offset:
                g = g + np.array([rnd * 37.13, rnd * 11.71, rnd * 23.37])
            obj.data.attributes["gco"].data.foreach_set("vector", g.astype(np.float32).ravel())
        del obj["_gco"]
    elif "_gco" in obj.keys():
        del obj["_gco"]
    apply_a0_from_prop(obj)
    shade_piece(obj, shade)
    obj.data.update()
    return obj


def shade_piece(obj, angle):
    """Per-piece shading flags (face smooth + sharp edges by angle); bmesh joins keep them."""
    me = obj.data
    if angle is None:
        for p in me.polygons:
            p.use_smooth = False
    else:
        for p in me.polygons:
            p.use_smooth = True
        me.set_sharp_from_angle(angle=math.radians(angle))
    return obj
