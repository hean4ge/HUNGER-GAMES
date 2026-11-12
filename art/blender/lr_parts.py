"""
lr_parts.py - realistic building pieces for the LandmarksReal set: dressed granite blocks with chipped arrises,
flagstones, moss-filled joints, timber members, forged iron straps, rivets, rods, clay roof planes.
Every piece is bevelled (no razor CG edges), UV-mapped onto the LR trim sheets and appended to a Group.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import lr_core as C
import tex_landmarks as T

TAU = 2.0 * math.pi


# =============================================================================================== 2D helpers
def ngon(n, apothem, phase=0.0):
    R = apothem / math.cos(math.pi / n)
    return [(R * math.cos(phase + (k + 0.5) * TAU / n), R * math.sin(phase + (k + 0.5) * TAU / n)) for k in range(n)]


def rect(hx, hy, cx=0.0, cy=0.0):
    return [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]


def arc(r, a0, a1, n):
    return [(r * math.cos(a0 + (a1 - a0) * i / (n - 1)), r * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]


def offset_convex(pts, d):
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((e1.y, -e1.x))
        n2 = Vector((e2.y, -e2.x))
        m = (n1 + n2).normalized()
        k = d / max(m.dot(n1), 0.25)
        out.append((p1.x + m.x * k, p1.y + m.y * k))
    return out


def poly_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a / 2


def ccw(pts):
    return pts if poly_area(pts) > 0 else list(reversed(pts))


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def shrink(pts, d):
    """Inset a (roughly convex) polygon by d toward its centroid along edge normals."""
    return offset_convex(ccw(pts), -d)


# =============================================================================================== stone
def _chip(bm, corner, out_dir, depth, rnd):
    n = (Vector(out_dir).normalized() + Vector((rnd.uniform(-0.35, 0.35), rnd.uniform(-0.35, 0.35),
                                                 rnd.uniform(-0.35, 0.35)))).normalized()
    co = Vector(corner) - n * depth
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=n, clear_outer=True, dist=1e-5)
    cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if cut_edges:
        try:
            bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
        except Exception:
            pass


def stone(g, rnd, poly, z0, z1, bevel=0.08, segs=1, damp_z=None, rust_z=None, chips=0, chip_depth=(0.08, 0.22),
          jitter=0.008, top_poly=None, top_frame=None, rot_top=True, extra_bands=()):
    """Dressed granite block: prism(poly, z0..z1) with rounded arrises, optional chipped corners, granite mapping
    with seamless damp/rust trim bands. poly is a CCW list of (x, y) in world space."""
    poly = ccw(poly)
    bm = C.prism_bm(poly, z0, z1, top_poly=ccw(top_poly) if top_poly else None)
    C.bevel_all(bm, bevel, segs, angle_deg=25.0)
    if chips:
        corners = [(x, y, z) for (x, y) in poly for z in (z0, z1)]
        cx, cy = centroid(poly)
        zc = (z0 + z1) / 2
        for _ in range(chips):
            c = corners[rnd.randrange(len(corners))]
            out = Vector((c[0] - cx, c[1] - cy, (c[2] - zc) * 2.5))
            _chip(bm, c, out, rnd.uniform(*chip_depth), rnd)
    if jitter:
        C.jitter_verts(bm, jitter, rnd)
    rule = C.Granite(rnd, damp_z=damp_z, rust_z=rust_z, rot_top=rot_top, top_frame=top_frame)
    for zb in list(rule.band_lines()) + list(extra_bands):
        if z0 + 0.02 < zb < z1 - 0.02:
            C.bisect(bm, (0, 0, zb), (0, 0, 1))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    rule(bm, list(bm.faces))
    g.add(bm)
    return bm


def flagstone(g, rnd, poly, z_top, depth=0.45, bevel=0.07, tilt=0.025, sink=0.012, jitter=0.006, top_frame=None,
              damp=1.0, sides=True):
    """Worn paving slab: top at z_top (+ slight random tilt/sink), rounded top arris, sides use the DAMP trim
    (wet, mossy near the joint floor; damp = studs from the top down to the joint floor, so a small value darkens
    the worn arris like dirt in the joints). No bottom face; sides=False also drops the side faces (when a joint
    bedding sits just under the arris they are never seen)."""
    poly = ccw(poly)
    z0 = z_top - depth
    bm = C.prism_bm(poly, z0, z_top)
    # drop the bottom face
    bot = [f for f in bm.faces if f.normal.z < -0.9]
    bmesh.ops.delete(bm, geom=bot, context='FACES_ONLY')
    top_edges = [e for e in bm.edges if all(abs(v.co.z - z_top) < 1e-5 for v in e.verts)]
    C.bevel_edges(bm, top_edges, bevel, 1, 0.5)
    if not sides:
        kill = [f for f in bm.faces if abs(f.normal.z) < 0.2]
        bmesh.ops.delete(bm, geom=kill, context='FACES_ONLY')
    cx, cy = centroid(poly)
    ax, ay = rnd.uniform(-tilt, tilt), rnd.uniform(-tilt, tilt)
    dz = -rnd.uniform(0, sink)
    for v in bm.verts:
        if v.co.z > z_top - bevel * 1.5:
            v.co.z += dz + ax * (v.co.x - cx) * 0.05 + ay * (v.co.y - cy) * 0.05
    if jitter:
        C.jitter_verts(bm, jitter, rnd, axes=(1, 1, 0.3))
    rule = C.Granite(rnd, damp_z=z_top - damp, top_frame=top_frame)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    rule(bm, list(bm.faces))
    g.add(bm)


def trough(g, p0, p1, width, z, sag=0.04, ou=0.0):
    """Moss/soil joint fill under a gap: a shallow V strip from p0 to p1 (2D) at height z, MOSS strip (V across)."""
    p0, p1 = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = (p1 - p0)
    L = d.length
    if L < 1e-4:
        return
    t = d / L
    s = Vector((-t.y, t.x, 0))
    bm = C.new_bm()
    a = [bm.verts.new(p + s * width / 2 + Vector((0, 0, z))) for p in (p0, p1)]
    m = [bm.verts.new(p + Vector((0, 0, z - sag))) for p in (p0, p1)]
    b = [bm.verts.new(p - s * width / 2 + Vector((0, 0, z))) for p in (p0, p1)]
    bm.faces.new((b[0], b[1], m[1], m[0]))
    bm.faces.new((m[0], m[1], a[1], a[0]))
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    rows = T.STONE_STRIPS["MOSS"]
    uv = C.uvl(bm)
    for f in bm.faces:
        coords = []
        for l in f.loops:
            q = l.vert.co
            u = (q - Vector((p0.x, p0.y, q.z))).dot(t) / T.TRIM_STUDS + ou
            w = (q - Vector((p0.x, p0.y, q.z))).dot(s) / width + 0.5
            coords.append((u, C.strip_v(rows, w)))
        C._uv_set(f, uv, coords, C.M_TRIM)
    g.add(bm)


def ring_trough(g, r, width, z, a0, a1, segs, sag=0.04, center=(0, 0)):
    """Circular moss joint between two rings of slabs (arc from a0 to a1)."""
    bm = C.new_bm()
    rows = T.STONE_STRIPS["MOSS"]
    uv = C.uvl(bm)
    cx, cy = center
    cols = []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        c, s = math.cos(a), math.sin(a)
        cols.append([bm.verts.new((cx + (r - width / 2) * c, cy + (r - width / 2) * s, z)),
                     bm.verts.new((cx + r * c, cy + r * s, z - sag)),
                     bm.verts.new((cx + (r + width / 2) * c, cy + (r + width / 2) * s, z))])
    rep = max(1, round(r * abs(a1 - a0) / T.TRIM_STUDS))
    for i in range(segs):
        for k in range(2):
            f = bm.faces.new((cols[i][k], cols[i + 1][k], cols[i + 1][k + 1], cols[i][k + 1]))
            if f.normal.z < 0:
                f.normal_flip()
            coords = []
            for l in f.loops:
                ii = next(j for j in (i, i + 1) if l.vert in cols[j])
                kk = cols[ii].index(l.vert)
                coords.append((rep * ii / segs, C.strip_v(rows, kk / 2.0)))
            C._uv_set(f, uv, coords, C.M_TRIM)
    g.add(bm)


# =============================================================================================== timber
def member(g, rnd, p0, p1, w, h, up=(0, 0, 1), strip="BEAM", bevel=0.05, segs=2, end_cell=None, extend=0.0,
           jitter=0.006, twist=0.0, stretch=False):
    """Squared timber from p0 to p1 (w across, h along 'up'), rounded arrises, grain along the member."""
    p0, p1 = Vector(p0), Vector(p1)
    dn = (p1 - p0).normalized()
    p0, p1 = p0 - dn * extend, p1 + dn * extend
    L = (p1 - p0).length
    side = Vector(up).cross(dn)
    if side.length < 1e-6:
        side = Vector((0, 1, 0)).cross(dn)
    side.normalize()
    upn = dn.cross(side).normalized()
    bm = C.box_bm(L, w, h)
    C.bevel_all(bm, bevel, segs, angle_deg=25.0)
    if jitter:
        C.jitter_verts(bm, jitter, rnd)
    m = Matrix((dn, side, upn)).transposed().to_4x4()
    if twist:
        m = m @ Matrix.Rotation(twist, 4, 'X')
    m.translation = (p0 + p1) / 2
    C.transform(bm, m)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    rows = T.WOOD_STRIPS[strip]
    studs = (rows[1] - rows[0]) / T.PPS
    cell = end_cell if end_cell is not None else rnd.randrange(T.WOOD_END_CELLS)
    rule = C.Member(C.M_WOOD, rows, dn, p0, ou=rnd.random(), strip_studs=studs, end_cell=cell,
                    voff=rnd.uniform(0, max(0.0, 1.0 - max(w, h) / studs)) if not stretch else 0.0, stretch=stretch)
    rule(bm, list(bm.faces))
    g.add(bm)
    return bm


def plank(g, rnd, p0, p1, w, t, up=(0, 0, 1), bevel=0.035, extend=0.0):
    """Board: wide face up (w across, t thick) using one of the three plank strips (whole width of the strip)."""
    strip = rnd.choice(["PLANK0", "PLANK1", "PLANK2"])
    p0, p1 = Vector(p0), Vector(p1)
    dn = (p1 - p0).normalized()
    p0, p1 = p0 - dn * extend, p1 + dn * extend
    L = (p1 - p0).length
    side = Vector(up).cross(dn).normalized()
    upn = dn.cross(side).normalized()
    bm = C.box_bm(L, w, t)
    C.bevel_all(bm, bevel, 1, angle_deg=25.0)
    C.jitter_verts(bm, 0.004, rnd)
    m = Matrix((dn, side, upn)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    C.transform(bm, m)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    rows = T.WOOD_STRIPS[strip]
    rule = C.Member(C.M_WOOD, rows, dn, p0, ou=rnd.random(), strip_studs=(rows[1] - rows[0]) / T.PPS,
                    end_cell=rnd.randrange(T.WOOD_END_CELLS), stretch=True)
    rule(bm, list(bm.faces))
    g.add(bm)
    return bm


def pole(g, rnd, p0, p1, r0, r1=None, segs=10, strip="BEAM", mat=None, rows=None, period=T.TRIM_STUDS, caps=True):
    """Round pole/rod: U along the axis, V around (one wrap of the strip)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    r1 = r0 if r1 is None else r1
    bm = C.new_bm()
    uv = C.uvl(bm)
    q = d.normalized().to_track_quat('Z', 'Y')
    rings = []
    for z, r in ((0.0, r0), (L, r1)):
        rings.append([bm.verts.new(p0 + q @ Vector((r * math.cos(TAU * i / segs), r * math.sin(TAU * i / segs), z)))
                      for i in range(segs)])
    mat = C.M_WOOD if mat is None else mat
    rows = rows or T.WOOD_STRIPS[strip]
    ou = rnd.random()
    for i in range(segs):
        j = (i + 1) % segs
        f = bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
        coords = [(ou, C.strip_v(rows, i / segs)), (ou, C.strip_v(rows, (i + 1) / segs)),
                  (ou + L / period, C.strip_v(rows, (i + 1) / segs)), (ou + L / period, C.strip_v(rows, i / segs))]
        C._uv_set(f, uv, coords, mat)
    if caps:
        for k, ring in enumerate(rings):
            f = bm.faces.new(ring if k == 1 else list(reversed(ring)))
            if mat == C.M_WOOD:
                e0, e1 = T.WOOD_STRIPS["END"]
                S = e1 - e0
                cell = rnd.randrange(T.WOOD_END_CELLS)
                rr = r1 if k == 1 else r0
                coords = []
                for l in f.loops:
                    lp = q.inverted() @ (l.vert.co - p0)
                    su = 0.5 + lp.x / (2.2 * rr)
                    sv = 0.5 + lp.y / (2.2 * rr)
                    coords.append(((cell * S + su * S) / T.N, (e0 + sv * S) / T.N))
                C._uv_set(f, uv, coords, mat)
            else:
                C._uv_set(f, uv, [(ou + 0.02 * i, C.strip_v(rows, 0.5)) for i in range(len(f.loops))], mat)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g.add(bm)
    return bm


# =============================================================================================== iron
def strap_loop(g, rnd, loop2d, z0, z1, thick=0.14, bevel=0.03, strip="STRAP", z_out=None):
    """Forged iron strap around a closed outline (CCW 2D): outer face at loop2d offset by 'thick'."""
    outer = offset_convex(ccw(loop2d), thick)
    inner = offset_convex(ccw(loop2d), -0.02)
    bm = C.new_bm()
    n = len(outer)
    ob = [bm.verts.new((x, y, z0)) for x, y in outer]
    ot = [bm.verts.new((x, y, z1)) for x, y in outer]
    ib = [bm.verts.new((x, y, z0)) for x, y in inner]
    it = [bm.verts.new((x, y, z1)) for x, y in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((it[i], it[j], ib[j], ib[i]))
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((ib[i], ib[j], ob[j], ob[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    C.bevel_all(bm, bevel, 1, angle_deg=60.0)
    bm.normal_update()
    rows = T.IRON_STRIPS[strip]
    ou = rnd.random()
    uv = C.uvl(bm)
    # U: running length around the loop, V: height across the strap
    per = [0.0]
    for i in range(n):
        per.append(per[-1] + (Vector(outer[(i + 1) % n]) - Vector(outer[i])).length)
    total = per[-1]
    rep = max(1, round(total / T.TRIM_STUDS))
    for f in bm.faces:
        coords = []
        for l in f.loops:
            p = l.vert.co
            a = math.atan2(p.y, p.x)
            coords.append((a / TAU * rep + ou, C.strip_v(rows, (p.z - z0) / max(z1 - z0, 1e-6))))
        a0 = coords[0][0]
        coords = [(a0 + ((u - a0 + rep / 2) % rep) - rep / 2, v) for (u, v) in coords]
        C._uv_set(f, uv, coords, C.M_IRON)
    g.add(bm)
    return outer


def rivet(g, pos, normal, r=0.09, h=0.06, segs=8):
    """Domed rivet head on a surface (pos on the surface, normal outward)."""
    n = Vector(normal).normalized()
    q = n.to_track_quat('Z', 'Y')
    prof = [(r, -0.03), (r * 0.82, h * 0.62), (0.0, h)]
    bm = C.lathe_bm(prof, segs)
    m = q.to_matrix().to_4x4()
    m.translation = Vector(pos)
    C.transform(bm, m)
    bm.normal_update()
    rows = T.IRON_STRIPS["BAR"]
    uv = C.uvl(bm)
    ou = (pos[0] * 0.37 + pos[1] * 0.11 + pos[2] * 0.23) % 1.0
    for f in bm.faces:
        coords = []
        for l in f.loops:
            lp = q.inverted() @ (l.vert.co - Vector(pos))
            coords.append((ou + lp.x / T.TRIM_STUDS * 2.0, C.strip_v(rows, 0.5 + lp.y / 0.8)))
        C._uv_set(f, uv, coords, C.M_IRON)
    g.add(bm)


def _frames(spine, up=(0, 0, 1)):
    pts = [Vector(p) for p in spine]
    n = len(pts)
    U = Vector(up)
    out = []
    closed = (pts[0] - pts[-1]).length < 1e-6
    for i, p in enumerate(pts):
        if closed and i in (0, n - 1):
            tng = (pts[1] - pts[n - 2]).normalized()
        else:
            tng = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side = tng.cross(U)
        if side.length < 1e-6:
            side = tng.cross(Vector((1, 0, 0)))
        side.normalize()
        nrm = side.cross(tng).normalized()
        out.append((p, tng, side, nrm))
    return out


def iron_bar(g, rnd, spine, w, d, strip="BAR", twist=0.0, cap=True, chamfer=0.28, up=(0, 0, 1), mat=None,
             section=None):
    """Forged bar along a 3D spine: chamfered-square section (w x d), smooth-shaded so it reads hand-forged.
    U = length along the bar, V = once around the section. section(t) may scale (w, d) along the bar."""
    c = chamfer * min(w, d)
    base = [(0.5, 0.5 - 2 * c / d), (0.5 - 2 * c / w, 0.5), (-0.5 + 2 * c / w, 0.5), (-0.5, 0.5 - 2 * c / d),
            (-0.5, -0.5 + 2 * c / d), (-0.5 + 2 * c / w, -0.5), (0.5 - 2 * c / w, -0.5), (0.5, -0.5 + 2 * c / d)]
    fr = _frames(spine, up)
    n = len(fr)
    bm = C.new_bm()
    uv = C.uvl(bm)
    rows = T.IRON_STRIPS[strip]
    mat = C.M_IRON if mat is None else mat
    ou = rnd.random()
    rings = []
    cum = [0.0]
    for i in range(1, n):
        cum.append(cum[-1] + (fr[i][0] - fr[i - 1][0]).length)
    for i, (p, tng, side, nrm) in enumerate(fr):
        t = i / max(n - 1, 1)
        sw, sd = (section(t) if section else (1.0, 1.0))
        ang = twist * t
        ca, sa = math.cos(ang), math.sin(ang)
        ring = []
        for (a, b) in base:
            aa, bb = a * w * sw, b * d * sd
            ring.append(bm.verts.new(p + side * (aa * ca - bb * sa) + nrm * (aa * sa + bb * ca)))
        rings.append(ring)
    k = len(base)
    for i in range(n - 1):
        for j in range(k):
            jj = (j + 1) % k
            f = bm.faces.new((rings[i][j], rings[i][jj], rings[i + 1][jj], rings[i + 1][j]))
            u0, u1 = ou + cum[i] / T.TRIM_STUDS, ou + cum[i + 1] / T.TRIM_STUDS
            v0, v1 = C.strip_v(rows, j / k), C.strip_v(rows, (j + 1) / k)
            C._uv_set(f, uv, [(u0, v0), (u0, v1), (u1, v1), (u1, v0)], mat)
    if cap:
        for idx, ring in ((0, rings[0]), (n - 1, rings[-1])):
            f = bm.faces.new(list(reversed(ring)) if idx == 0 else ring)
            C._uv_set(f, uv, [(ou + 0.03 * math.cos(TAU * j / k), C.strip_v(rows, 0.5 + 0.2 * math.sin(TAU * j / k)))
                              for j in range(k)], mat)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g.add(bm)
    return bm


def ring_bar(g, rnd, center, radius, z, w, d, segs=24, strip="BAR", mat=None):
    """Closed forged hoop (horizontal) of radius at height z."""
    cx, cy = center
    spine = [(cx + radius * math.cos(TAU * i / segs), cy + radius * math.sin(TAU * i / segs), z) for i in range(segs + 1)]
    return iron_bar(g, rnd, spine, w, d, strip=strip, cap=False, mat=mat)
