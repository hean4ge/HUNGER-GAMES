"""
wv2_geo.py - small geometry kit for the WeaponsV2 set (flat colour per part, no textures).
Every helper returns (verts, faces) in Blender space (Z up, 1 BU = 1 stud). Asset collects them per role.
Shapes are convex hulls (chamfered boxes, prisms, wedges) and lofts (blades, limbs, hoops), so every part reads
as chunky flat facets in the Roblox style.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

V = Vector
D = math.radians


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def R(axis, deg):
    return Matrix.Rotation(D(deg), 4, axis)


def S(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    m = Matrix.Identity(4)
    m[0][0], m[1][1], m[2][2] = x, y, z
    return m


# ------------------------------------------------------------------------------------------------ hull
def hull(pts):
    bm = bmesh.new()
    vs = [bm.verts.new(V(p)) for p in pts]
    bm.verts.ensure_lookup_table()
    res = bmesh.ops.convex_hull(bm, input=vs)
    drop = [g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)]
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=D(0.5), verts=list(bm.verts), edges=list(bm.edges))
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return verts, faces


def cbox(sx, sy, sz, c=0.0, loc=(0, 0, 0)):
    """Box centred on loc, chamfered by c (convex hull of the 24 corner points)."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    c = min(c, hx * 0.45, hy * 0.45, hz * 0.45)
    pts = []
    for a in (-1, 1):
        for b in (-1, 1):
            for d in (-1, 1):
                if c <= 0:
                    pts.append((a * hx, b * hy, d * hz))
                else:
                    pts += [(a * (hx - c), b * hy, d * (hz - c)), (a * hx, b * (hy - c), d * (hz - c)),
                            (a * (hx - c), b * (hy - c), d * hz)]
    pts = [(p[0] + loc[0], p[1] + loc[1], p[2] + loc[2]) for p in pts]
    return hull(pts)


def ring(rx, ry, z, n, phase=0.5, cx=0.0, cy=0.0):
    return [(cx + rx * math.cos(2 * math.pi * (i + phase) / n), cy + ry * math.sin(2 * math.pi * (i + phase) / n), z)
            for i in range(n)]


def cyl(rx, z0, z1, n=8, ry=None, c=0.0, rx1=None, ry1=None, phase=0.5, cx=0.0, cy=0.0):
    """n-sided prism along Z from z0 to z1 (elliptic rx, ry; optional taper to rx1, ry1), chamfered ends."""
    ry = rx if ry is None else ry
    rx1 = rx if rx1 is None else rx1
    ry1 = ry if ry1 is None else ry1
    if c > 0:
        rings = [ring(rx - c, ry - c, z0, n, phase, cx, cy), ring(rx, ry, z0 + c, n, phase, cx, cy),
                 ring(rx1, ry1, z1 - c, n, phase, cx, cy), ring(rx1 - c, ry1 - c, z1, n, phase, cx, cy)]
    else:
        rings = [ring(rx, ry, z0, n, phase, cx, cy), ring(rx1, ry1, z1, n, phase, cx, cy)]
    return hull([p for r in rings for p in r])


def rod(p0, p1, r, n=4):
    p0, p1 = V(p0), V(p1)
    d = p1 - p0
    L = d.length
    vs, fs = cyl(r, 0, L, n)
    q = d.normalized().to_track_quat("Z", "Y")
    M = T(*p0) @ q.to_matrix().to_4x4()
    return [tuple(M @ V(v)) for v in vs], fs


# ------------------------------------------------------------------------------------------------ loft
def loft(sections, caps=True, closed=False):
    """sections: list of rings (each a list of 3D points, all the same length, each ring closed)."""
    verts, faces = [], []
    m = len(sections[0])
    for s in sections:
        verts += [tuple(p) for p in s]
    n = len(sections)
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        a, b = i * m, ((i + 1) % n) * m
        for j in range(m):
            j2 = (j + 1) % m
            faces.append([a + j, a + j2, b + j2, b + j])
    if caps and not closed:
        faces.append(list(reversed(range(m))))
        faces.append([(n - 1) * m + j for j in range(m)])
    return verts, faces


def merge(*geos):
    verts, faces = [], []
    for vs, fs in geos:
        off = len(verts)
        verts += list(vs)
        faces += [[i + off for i in f] for f in fs]
    return verts, faces


def xform(g, M):
    vs, fs = g
    return [tuple(M @ V(v)) for v in vs], fs


def blade(stations, band=0.03, double=False):
    """Blade along +Z, edge toward +Y. stations: (z, y_back, y_front, half_thickness).
    Returns (body, edge_front, edge_back_or_None). The edge strips are thin wedges (the honed bevel)."""
    body, ef, eb = [], [], []
    for z, yb, yf, t in stations:
        w = max(yf - yb, 1e-4)
        b = min(band, w * (0.3 if double else 0.45))
        yfm = yf - b
        ybm = yb + b if double else yb
        body.append([(t, ybm, z), (t, yfm, z), (-t, yfm, z), (-t, ybm, z)])
        ef.append([(t, yfm, z), (0.0, yf, z), (-t, yfm, z)])
        if double:
            eb.append([(-t, ybm, z), (0.0, yb, z), (t, ybm, z)])
    return loft(body), loft(ef), (loft(eb) if double else None)


def sweep(path, section, ref=(1, 0, 0), closed=False, caps=True):
    """Sweep along path (list of points). section(i, s) -> list of (u, v): u along the ref axis, v along the binormal."""
    P = [V(p) for p in path]
    n = len(P)
    rings = []
    refv = V(ref)
    for i in range(n):
        if closed:
            t = (P[(i + 1) % n] - P[(i - 1) % n])
        else:
            t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)])
        t.normalize()
        nrm = refv - t * refv.dot(t)
        if nrm.length < 1e-6:
            nrm = V((0, 0, 1)) - t * t.z
        nrm.normalize()
        bn = t.cross(nrm)
        s = i / (n - 1 if not closed else n)
        rings.append([tuple(P[i] + nrm * u + bn * v) for (u, v) in section(i, s)])
    return loft(rings, caps=caps, closed=closed)


def rect(u, v):
    return [(u, v), (u, -v), (-u, -v), (-u, v)]


def star_geo(R_out=0.5, R_in=0.21, depth=0.12, dome=0.08):
    """Five-point star in the XZ plane facing +Y, top point +Z, back face at y=0, apex at y=depth+dome."""
    out = []
    for i in range(10):
        a = math.pi / 2 - i * math.pi / 5
        r = R_out if i % 2 == 0 else R_in
        out.append((r * math.cos(a), r * math.sin(a)))
    verts = [(x, 0.0, z) for x, z in out] + [(x, depth, z) for x, z in out] + [(0, 0, 0), (0, depth + dome, 0)]
    cb, cf = 20, 21
    faces = []
    for i in range(10):
        j = (i + 1) % 10
        faces.append([cb, j, i])                     # back fan
        faces.append([i, j, 10 + j, 10 + i])         # side
        faces.append([cf, 10 + i, 10 + j])           # faceted front
    return verts, faces


# ------------------------------------------------------------------------------------------------ colour
def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
