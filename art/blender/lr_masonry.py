"""
lr_masonry.py - masonry builders for the LandmarksReal set: course blocks around a (tapering) outline, blocks
drawn in elevation (openings, gables, buttresses), dark joint backing and simple convex colliders.
"""
import math

import bmesh
from mathutils import Vector

import lr_core as C
import lr_parts as P

TAU = 2.0 * math.pi


def ray_hit(poly, c, a, origin_off=0.0):
    """Point where the ray from c (shifted sideways by origin_off) at angle a leaves the convex polygon."""
    dx, dy = math.cos(a), math.sin(a)
    ox, oy = c[0] - dy * origin_off, c[1] + dx * origin_off
    best = None
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        ex, ey = q[0] - p[0], q[1] - p[1]
        den = dx * ey - dy * ex
        if abs(den) < 1e-12:
            continue
        wx, wy = p[0] - ox, p[1] - oy
        t = (wx * ey - wy * ex) / den
        s = (wx * dy - wy * dx) / den
        if t > 1e-9 and -1e-9 <= s <= 1 + 1e-9 and (best is None or t < best[0]):
            best = (t, (ox + dx * t, oy + dy * t))
    return best[1]


def poly_between(poly, c, a0, a1, gap=0.0):
    """Boundary polyline of a convex polygon from angle a0 to a1 (CCW around c); the two cut lines are shifted
    by gap/2 into the range so neighbouring pieces leave a joint of 'gap'."""
    pts = [ray_hit(poly, c, a0, gap / 2)]
    span = (a1 - a0) % TAU or TAU
    inner = []
    for v in poly:
        rel = (math.atan2(v[1] - c[1], v[0] - c[0]) - a0) % TAU
        if 1e-6 < rel < span - 1e-6:
            inner.append((rel, v))
    inner.sort()
    pts += [v for _, v in inner]
    pts.append(ray_hit(poly, c, a1, -gap / 2))
    return pts


def vertex_angles(poly, c):
    return [math.atan2(v[1] - c[1], v[0] - c[0]) for v in poly]


def polys_between(polys, c, a0, a1, gap=0.0):
    """poly_between for several outlines at once (the levels of one block): every polyline gets a point at every
    vertex angle of ANY outline inside (a0, a1), so all levels have the same point count and can be lofted
    (corners stay exact; extra points just sit on straight edges)."""
    span = (a1 - a0) % TAU or TAU
    rels = []
    for poly in polys:
        for v in poly:
            rel = (math.atan2(v[1] - c[1], v[0] - c[0]) - a0) % TAU
            if 1e-6 < rel < span - 1e-6:
                rels.append(rel)
    rels.sort()
    uniq = []
    for r in rels:
        if not uniq or r - uniq[-1] > 1e-4:
            uniq.append(r)
    out = []
    for poly in polys:
        pts = [ray_hit(poly, c, a0, gap / 2)]
        pts += [ray_hit(poly, c, a0 + r, 0.0) for r in uniq]
        pts.append(ray_hit(poly, c, a1, -gap / 2))
        out.append(pts)
    return out


def safe_cuts(rnd, n, polys, c, start=None, jitter=0.3, clear_deg=5.0):
    """n cut angles around c, roughly even, kept clear of the outline vertices of every polygon in polys."""
    va = []
    for p in polys:
        va += vertex_angles(p, c)
    a0 = rnd.uniform(0, TAU) if start is None else start
    cuts = []
    for i in range(n):
        a = a0 + TAU * (i + rnd.uniform(-jitter, jitter) * 0.5) / n
        for _ in range(40):
            if all(abs(((a - v + math.pi) % TAU) - math.pi) > math.radians(clear_deg) for v in va):
                break
            a += math.radians(1.3)
        cuts.append(a)
    return cuts


def clip_x(pts, x0, side):
    """Clip a convex polygon to side * x >= x0 (Sutherland-Hodgman)."""
    out = []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        fa, fb = side * a[0] - x0, side * b[0] - x0
        if fa >= 0:
            out.append(a)
        if (fa >= 0) != (fb >= 0):
            t = fa / (fa - fb)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _orient(f, expect):
    f.normal_update()
    if f.normal.dot(expect) < 0:
        f.normal_flip()


def skin_block(g, rnd, levels, inner0, inner1, bevel=0.08, segs=1, damp_z=None, rust_z=None, jitter=0.01,
               center=(0.0, 0.0)):
    """Course block that only exists where it can be seen: outer face lofted through levels [(polyline, z), ...]
    (same point count, CCW around center), top and bottom joint returns back to the inner polylines (inner0 at
    the first z, inner1 at the last) and the two end joints. Open at the back (a dark core sits behind)."""
    bm = C.new_bm()
    rings = [[bm.verts.new((x, y, z)) for (x, y) in pl] for pl, z in levels]
    z0, z1 = levels[0][1], levels[-1][1]
    i0 = [bm.verts.new((x, y, z0)) for (x, y) in inner0]
    i1 = [bm.verts.new((x, y, z1)) for (x, y) in inner1]
    cx, cy = center
    k = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(k - 1):
            f = bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
            mid = (a[j].co + a[j + 1].co) / 2
            _orient(f, Vector((mid.x - cx, mid.y - cy, 0.0)))
    fb = bm.faces.new(rings[0] + list(reversed(i0)))
    _orient(fb, Vector((0, 0, -1)))
    ft = bm.faces.new(rings[-1] + list(reversed(i1)))
    _orient(ft, Vector((0, 0, 1)))
    t0 = (rings[0][1].co - rings[0][0].co).normalized()
    t1 = (rings[0][-1].co - rings[0][-2].co).normalized()
    fs = bm.faces.new([r[0] for r in rings] + [i1[0], i0[0]])
    _orient(fs, -t0)
    fe = bm.faces.new([r[-1] for r in rings] + [i1[-1], i0[-1]])
    _orient(fe, t1)
    C.bevel_all(bm, bevel, segs, angle_deg=25.0)
    if jitter:
        C.jitter_verts(bm, jitter, rnd)
    rule = C.Granite(rnd, damp_z=damp_z, rust_z=rust_z)
    for zb in rule.band_lines():
        if z0 + 0.02 < zb < z1 - 0.02:
            C.bisect(bm, (0, 0, zb), (0, 0, 1))
    bm.normal_update()
    rule(bm, list(bm.faces))
    g.add(bm)


def course_blocks(g, rnd, poly0, poly1, z0, z1, n, depth=0.6, gap=0.07, bevel=0.08, damp_z=None, rust_z=None, segs=1,
                  center=None, cuts=None, mid=None):
    """A course of n skin blocks around a convex outline that tapers from poly0 (z0) to poly1 (z1).
    mid: optional (poly, z) intermediate level (cornice profiles). Returns the cut angles used."""
    c = center or P.centroid(poly0)
    polys = [poly0, poly1] + ([mid[0]] if mid else [])
    cuts = cuts or safe_cuts(rnd, n, polys, c)
    in0 = P.offset_convex(P.ccw(poly0), -depth)
    in1 = P.offset_convex(P.ccw(poly1), -depth)
    zg0, zg1 = z0 + gap / 2, z1 - gap / 2
    for i in range(n):
        a0, a1 = cuts[i], cuts[(i + 1) % n]
        if a1 <= a0:
            a1 += TAU
        if mid:
            o0, om, o1 = polys_between([poly0, mid[0], poly1], c, a0, a1, gap)
            lv = [(o0, zg0), (om, mid[1]), (o1, zg1)]
        else:
            o0, o1 = polys_between([poly0, poly1], c, a0, a1, gap)
            lv = [(o0, zg0), (o1, zg1)]
        skin_block(g, rnd, lv, poly_between(in0, c, a0, a1, gap), poly_between(in1, c, a0, a1, gap), bevel=bevel,
                   damp_z=damp_z, rust_z=rust_z, center=c, segs=segs)
    return cuts


def elev_block(g, rnd, origin, xdir, nout, poly_sz, d0, d1, bevel=0.08, segs=1, damp_z=None, rust_z=None,
               jitter=0.01, gap=0.035, chips=0):
    """Block drawn in elevation: poly_sz [(s, z)] in the face plane (s along xdir), extruded from depth d0 to d1
    behind the face (along -nout)."""
    O, X, Nn = Vector(origin), Vector(xdir).normalized(), Vector(nout).normalized()
    pts = P.offset_convex(P.ccw(poly_sz), -gap / 2) if gap else P.ccw(poly_sz)

    def w(s, z, d):
        return O + X * s - Nn * d + Vector((0, 0, z))

    bm = C.new_bm()
    front = [bm.verts.new(w(s, z, d0)) for (s, z) in pts]
    back = [bm.verts.new(w(s, z, d1)) for (s, z) in pts]
    n = len(pts)
    ff = bm.faces.new(front)
    _orient(ff, Nn)
    fb = bm.faces.new(list(reversed(back)))
    _orient(fb, -Nn)
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((front[i], front[j], back[j], back[i]))
        e = Vector(pts[j]) - Vector(pts[i])
        out2 = Vector((e.y, -e.x)).normalized()
        _orient(f, X * out2.x + Vector((0, 0, out2.y)))
    C.bevel_all(bm, bevel, segs, angle_deg=25.0)
    if chips:
        cs, cz = P.centroid(pts)
        for _ in range(chips):
            s, z = pts[rnd.randrange(n)]
            outv = X * (s - cs) + Vector((0, 0, (z - cz))) + Nn * 1.2
            P._chip(bm, w(s, z, d0), outv, rnd.uniform(0.06, 0.16), rnd)
    if jitter:
        C.jitter_verts(bm, jitter, rnd)
    rule = C.Granite(rnd, damp_z=damp_z, rust_z=rust_z)
    zs = [z for _, z in pts]
    for zb in rule.band_lines():
        if min(zs) + 0.02 < zb < max(zs) - 0.02:
            C.bisect(bm, (0, 0, zb), (0, 0, 1))
    bm.normal_update()
    rule(bm, list(bm.faces))
    g.add(bm)


def collider_prism(g, poly, z0, z1, top_poly=None):
    bm = C.prism_bm(P.ccw(poly), z0, z1, top_poly=P.ccw(top_poly) if top_poly else None)
    C.Flat(C.M_COLL)(bm, list(bm.faces))
    g.add(bm)


def collider_elev(g, origin, xdir, nout, poly_sz, d0, d1):
    O, X, Nn = Vector(origin), Vector(xdir).normalized(), Vector(nout).normalized()
    pts = P.ccw(poly_sz)
    bm = C.new_bm()
    front = [bm.verts.new(O + X * s - Nn * d0 + Vector((0, 0, z))) for (s, z) in pts]
    back = [bm.verts.new(O + X * s - Nn * d1 + Vector((0, 0, z))) for (s, z) in pts]
    n = len(pts)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    C.Flat(C.M_COLL)(bm, list(bm.faces))
    g.add(bm)


def collider_hull(g, pts3d):
    bm = C.new_bm()
    vs = [bm.verts.new(p) for p in pts3d]
    bmesh.ops.convex_hull(bm, input=vs)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    C.Flat(C.M_COLL)(bm, list(bm.faces))
    g.add(bm)


def dark_prism(g, poly, z0, z1, top_poly=None, caps=True):
    bm = C.prism_bm(P.ccw(poly), z0, z1, top_poly=P.ccw(top_poly) if top_poly else None)
    if not caps:
        kill = [f for f in bm.faces if abs(f.normal.z) > 0.9]
        bmesh.ops.delete(bm, geom=kill, context='FACES_ONLY')
    C.Dark()(bm, list(bm.faces))
    g.add(bm)


def dark_elev(g, origin, xdir, nout, poly_sz, d0, d1):
    """Dark joint backing drawn in elevation (behind openings and gables)."""
    O, X, Nn = Vector(origin), Vector(xdir).normalized(), Vector(nout).normalized()
    pts = P.ccw(poly_sz)
    bm = C.new_bm()
    front = [bm.verts.new(O + X * s - Nn * d0 + Vector((0, 0, z))) for (s, z) in pts]
    back = [bm.verts.new(O + X * s - Nn * d1 + Vector((0, 0, z))) for (s, z) in pts]
    n = len(pts)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    C.Dark()(bm, list(bm.faces))
    g.add(bm)
