"""
br_kit.py - construction kit for the BuildingsReal set (realistic, textured). Built on ls_common / ls_patch (both
unchanged) and tex_buildings (the five texture sheets).

Every primitive writes closed solids into an MB (mesh builder) together with explicit per-corner UVs that point
into one region of one sheet:
  - full-width strips tile along U by the texture repeat (boards along their grain, logs along their length,
    shake courses along the eave, masonry bands round their perimeter, ropes along their lay)
  - logs, poles and ropes wrap V round their circumference: each half of a log (seam at top and bottom) maps
    once onto the strip, so the strip's V edges are always the top and bottom contact lines (contact AO)
  - log ends / timber ends map polar / planar into the end-grain cells
UV winding always follows the geometric winding (no mirrored islands), so tangent-space normals are safe.

An MB becomes one MeshPart via part(): ls Library.add (bake, clean, shading, bounds, flags) with uv=False, then
the role's flat material is replaced by the sheet's textured PBR material and the manifest entry is extended with
the texture files, alpha mode and an average-colour fallback.
"""
import json
import math
import os
import random
import shutil

import bpy
from mathutils import Vector as V

import ls_common as ls
import ls_patch  # noqa: F401  (hard edges, ordered bounds, query flags, manifest copy)
import tex_buildings as tb

TAU = 2.0 * math.pi
DOOR_W, DOOR_H = 4.0, 7.5
SET_NAME = "BuildingsReal"
TEX_DIR = None          # set by buildings_real.py (folder holding the BR_*.png set)
_MATS = {}
_IMGS = {}
_LAYOUT = {s: {n: tb.region_info(s, n) for n in tb.LAYOUT[s]} for s in tb.SHEETS}
_AVG = {}               # sheet -> region -> avg sRGB (from BR_layout.json)
METAL_REGIONS = {"iron", "tin", "wire"}


def R(sheet, name):
    """Region info: {'uv': (u0, v0, u1, v1), 'tile': (tw, th) studs, 'ppx', 'fullWidth', 'sheet', 'name'}."""
    info = dict(_LAYOUT[sheet][name])
    info["sheet"] = sheet
    info["name"] = name
    return info


def load_stats(tex_dir):
    global TEX_DIR
    TEX_DIR = tex_dir
    p = os.path.join(tex_dir, tb.PREFIX + "layout.json")
    if os.path.exists(p):
        with open(p, "r", encoding="utf-8") as f:
            sheets = json.load(f).get("sheets", {})
        for s, d in sheets.items():
            _AVG[s] = {k: v["avgRgb"] for k, v in d.get("regions", {}).items()}


# ================================================================================================
# Mesh builder
# ================================================================================================
class MB:
    def __init__(self, sheet):
        self.sheet = sheet
        self.co = []
        self.faces = []
        self.fuv = []
        self.regions = set()

    def v(self, p):
        self.co.append(V(p))
        return len(self.co) - 1

    def f(self, idx, uvs, region=None):
        self.faces.append(tuple(idx))
        self.fuv.append([(float(u), float(w)) for (u, w) in uvs])
        if region is not None:
            self.regions.add(region["name"])

    def merge(self, other):
        off = len(self.co)
        self.co += other.co
        self.faces += [tuple(i + off for i in fc) for fc in other.faces]
        self.fuv += other.fuv
        self.regions |= other.regions

    def tris(self):
        return sum(len(fc) - 2 for fc in self.faces)

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(c) for c in self.co], [], self.faces)
        uvl = me.uv_layers.new(name="UVMap")
        for poly, uvs in zip(me.polygons, self.fuv):
            for k, li in enumerate(poly.loop_indices):
                uvl.data[li].uv = uvs[k]
        me.update()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def frame(axis, up=(0, 0, 1)):
    """Orthonormal right-handed frame (x along axis, z as close to 'up' as possible, y = z x x)."""
    x = V(axis).normalized()
    u = V(up).normalized()
    if abs(x.dot(u)) > 0.985:
        u = V((0, 1, 0)) if abs(x.y) < 0.9 else V((1, 0, 0))
    z = (u - x * u.dot(x)).normalized()
    return x, z.cross(x), z


def v_reps(reg, span_studs, nseg):
    """How many times a V-periodic strip should repeat across span_studs (whole number dividing nseg) so its
    texels stay roughly square."""
    th = reg["tile"][1]
    want = max(1, int(round(span_studs / max(th, 1e-6))))
    for r in range(min(want, nseg), 0, -1):
        if nseg % r == 0:
            return r
    return 1


def suv(reg, u_studs, v_norm):
    """UV in a strip region: u in studs along the strip (wraps for full-width strips), v 0..1 across."""
    u0, v0, u1, v1 = reg["uv"]
    tw = reg["tile"][0]
    if reg["fullWidth"]:
        u = u_studs / tw
    else:
        u = u0 + (u_studs / tw) * (u1 - u0)
    return (u, v0 + max(0.0, min(1.0, v_norm)) * (v1 - v0))


def buv(reg, nu, nv):
    """UV in a block region, nu / nv 0..1."""
    u0, v0, u1, v1 = reg["uv"]
    return (u0 + max(0.0, min(1.0, nu)) * (u1 - u0), v0 + max(0.0, min(1.0, nv)) * (v1 - v0))


def disc_uv(reg, ang, rho):
    """Polar UV into a disc cell (rho 0..1 = centre..rim of the drawn disc, radius 0.47 of the cell)."""
    u0, v0, u1, v1 = reg["uv"]
    cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
    rr = 0.47 * (u1 - u0) * rho
    return (cu + rr * math.cos(ang), cv + rr * math.sin(ang) * (v1 - v0) / (u1 - u0))


# ================================================================================================
# Primitives
# ================================================================================================
def log(mb, p0, p1, r0, r1=None, reg=None, end_reg=None, segs=10, rings=2, up=(0, 0, 1), u_off=None,
        chamfer=(0.0, 0.0), cap=(True, True), bow=0.0, bow_dir=None, oval=0.05, wob=0.03, rng=None,
        theta0=0.0, end_rot=None, cap_inset=0.0):
    """Round log / pole / rope from p0 to p1 (closed). theta 0 = the 'up' side. reg = strip region (wraps V twice
    round the circumference, seam at the top and bottom), end_reg = disc cell(s) for the caps (a region or a pair).
    chamfer = (len0, len1): rounded cut edge at each end. Returns the vertex rings."""
    rng = rng or random
    p0, p1 = V(p0), V(p1)
    r1 = r0 if r1 is None else r1
    ax, ay, az = frame(p1 - p0, up)
    L = (p1 - p0).length
    if u_off is None and reg is not None and not reg["fullWidth"]:
        u_off = 0.02
    u_off = rng.uniform(0, 50) if u_off is None else u_off
    if bow_dir is None:
        a = rng.uniform(0, TAU)
        bow_dir = ay * math.cos(a) + az * math.sin(a)
    po = [rng.uniform(0, TAU) for _ in range(4)]
    stations = []
    c0, c1 = chamfer
    if c0 > 0:
        stations.append((0.0, 0.84))
    tA = min(c0 / L, 0.3) if c0 > 0 else 0.0
    tB = 1.0 - (min(c1 / L, 0.3) if c1 > 0 else 0.0)
    n_main = max(2, rings)
    for k in range(n_main):
        stations.append((tA + (tB - tA) * k / (n_main - 1), 1.0))
    if c1 > 0:
        stations.append((1.0, 0.84))
    ring_ids = []
    for (t, s) in stations:
        c = p0 + ax * (L * t) + V(bow_dir) * (bow * math.sin(math.pi * t))
        rr = (r0 + (r1 - r0) * t) * s
        ids = []
        for i in range(segs):
            th = theta0 + TAU * i / segs
            k = (1.0 + oval * math.cos(2 * th + po[0]) + wob * math.sin(3 * th + po[1] + 4.0 * t)
                 + 0.5 * wob * math.sin(5 * th + po[2] - 7.0 * t))
            d = az * math.cos(th) + ay * math.sin(th)
            ids.append(mb.v(c + d * (rr * k)))
        ring_ids.append((t, ids, rr))
    if reg is not None:
        hs = segs // 2
        reps = v_reps(reg, math.pi * 0.5 * (r0 + r1), hs)
        per = hs / reps
        for kk in range(len(ring_ids) - 1):
            ta, A, _ = ring_ids[kk]
            tb_, B, _ = ring_ids[kk + 1]
            ua, ub = u_off + ta * L, u_off + tb_ * L
            for i in range(segs):
                j = (i + 1) % segs
                k0 = i % per
                vi = k0 / per
                vj = (k0 + 1) / per
                mb.f((A[i], B[i], B[j], A[j]),
                     [suv(reg, ua, vi), suv(reg, ub, vi), suv(reg, ub, vj), suv(reg, ua, vj)], reg)
    ends = end_reg if isinstance(end_reg, (list, tuple)) else (end_reg, end_reg)
    rot = end_rot if end_rot is not None else (rng.uniform(0, TAU), rng.uniform(0, TAU))
    for side in (0, 1):
        if not cap[side]:
            continue
        t, ids, rr = ring_ids[0] if side == 0 else ring_ids[-1]
        er = ends[side]
        if er is None:
            er = reg
        # p0 cap faces -ax: ring order (clockwise round +ax) is CCW seen from -ax. p1 cap: reversed.
        order = list(range(segs)) if side == 0 else list(reversed(range(segs)))
        uvs = []
        for i in order:
            th = TAU * i / segs
            ang = (th if side == 0 else -th) + rot[side]
            if er is not None and not er["fullWidth"]:
                uvs.append(disc_uv(er, ang, 1.0))
            else:
                uvs.append(suv(er, (u_off + t * L) + 0.3 * math.cos(ang), 0.5 + 0.45 * math.sin(ang)))
        if cap_inset > 0:
            cen = mb.v(sum((mb.co[ids[i]] for i in range(segs)), V((0, 0, 0))) / segs
                       + (ax * (cap_inset if side == 0 else -cap_inset)))
            cu = disc_uv(er, 0, 0.0) if (er is not None and not er["fullWidth"]) else suv(er, u_off + t * L, 0.5)
            for k in range(segs):
                a_, b_ = order[k], order[(k + 1) % segs]
                mb.f((ids[a_], ids[b_], cen), [uvs[k], uvs[(k + 1) % segs], cu], er)
        else:
            mb.f([ids[i] for i in order], uvs, er)
    return ring_ids


def timber(mb, p0, p1, w, t, reg, end_reg=None, up=(0, 0, 1), ch=0.03, u_off=None, rng=None, ext=0.0,
           v_span=(0.0, 1.0), side_span=0.14, twist=0.0):
    """Chamfered sawn timber / board from p0 to p1: width w across (towards y of the frame), thickness t along
    'up'. The top and bottom faces carry the strip across their width; the narrow sides use the strip's edge
    rows (side_span); ends go to the end-grain cell."""
    rng = rng or random
    p0, p1 = V(p0), V(p1)
    ax, ay, az = frame(p1 - p0, up)
    if twist:
        ca, sa = math.cos(twist), math.sin(twist)
        ay, az = ay * ca + az * sa, az * ca - ay * sa
    d = (p1 - p0)
    L = d.length + 2 * ext
    p0 = p0 - ax * ext
    u_off = rng.uniform(0, 50) if u_off is None else u_off
    hw, ht = w / 2.0, t / 2.0
    c = min(ch, hw * 0.4, ht * 0.4)
    # octagon in (y, z), CCW seen from +x
    sec = [(hw - c, ht), (-hw + c, ht), (-hw, ht - c), (-hw, -ht + c), (-hw + c, -ht), (hw - c, -ht), (hw, -ht + c),
           (hw, ht - c)]
    if c <= 1e-4:
        sec = [(hw, ht), (-hw, ht), (-hw, -ht), (hw, -ht)]
    n = len(sec)
    A = [mb.v(p0 + ay * y + az * z) for (y, z) in sec]
    B = [mb.v(p0 + ax * L + ay * y + az * z) for (y, z) in sec]
    va, vb = v_span
    # per long face: (v range) - top face spans the full strip width, others use edge rows
    if n == 8:
        spans = [(va, vb), (vb - 0.04, vb), (vb - side_span, vb), (vb - 0.04, vb), (va, vb), (va, va + 0.04),
                 (va, va + side_span), (va, va + 0.04)]
        uoffs = [0.0, 0.0, 0.0, 0.0, 17.3, 0.0, 0.0, 0.0]
    else:
        spans = [(va, vb), (vb - side_span, vb), (va, vb), (va, va + side_span)]
        uoffs = [0.0, 0.0, 17.3, 0.0]
    for i in range(n):
        j = (i + 1) % n
        # face from sec[i] to sec[j]; quad (A_j, A_i, B_i, B_j) is CCW from outside for a CCW (from +x) section
        s0, s1 = spans[i]
        uo = u_off + uoffs[i]
        # v runs along the section direction i -> j; flip so u right / v up stays CCW
        mb.f((A[i], A[j], B[j], B[i]),
             [suv(reg, uo, s1), suv(reg, uo, s0), suv(reg, uo + L, s0), suv(reg, uo + L, s1)], reg)
    er = end_reg if end_reg is not None else reg
    for side, ring in ((0, A), (1, B)):
        order = list(range(n)) if side == 1 else list(reversed(range(n)))
        uvs = []
        for i in order:
            y, z = sec[i]
            ny = (y + hw) / (2 * hw)
            nz = (z + ht) / (2 * ht)
            if er["fullWidth"]:
                uvs.append(suv(er, u_off + 0.5 * y, nz * 0.2))
            else:
                uvs.append(buv(er, ny if side == 1 else 1 - ny, nz))
        mb.f([ring[i] for i in order], uvs, er)
    return A, B


def extrude(mb, p0, p1, sec, edge_map, cap_map=None, up=(0, 0, 1), rings=2, bow=0.0, bow_dir=None, rng=None,
            taper=1.0, wob=0.0):
    """Prism along p0 -> p1 with an arbitrary section [(y, z), ...] listed CCW seen from +x (frame of the axis).
    edge_map[i] = (region, u_off, v_at_i, v_at_next): the face from sec[i] to sec[i+1]; v must DEcrease along the
    CCW direction so the UVs stay unmirrored. cap_map = (region, (cy, cz), radius, rot): planar projection of the
    end sections into a disc cell centred on (cy, cz) (a log's pith) - half logs and firewood wedges get the
    matching part of the end-grain disc. taper scales the section at p1."""
    rng = rng or random
    p0, p1 = V(p0), V(p1)
    ax, ay, az = frame(p1 - p0, up)
    L = (p1 - p0).length
    if bow_dir is None:
        a = rng.uniform(0, TAU)
        bow_dir = ay * math.cos(a) + az * math.sin(a)
    n = len(sec)
    rows = []
    for k in range(rings):
        t = k / (rings - 1)
        sc = 1.0 + (taper - 1.0) * t
        c = p0 + ax * (L * t) + V(bow_dir) * (bow * math.sin(math.pi * t))
        ids = []
        for i, (y, z) in enumerate(sec):
            j = 1.0 + (wob * math.sin(7.3 * i + 5.1 * t * L) if wob else 0.0)
            ids.append(mb.v(c + (ay * y + az * z) * sc * j))
        rows.append((t, ids))
    for k in range(rings - 1):
        ta, A = rows[k]
        tb_, B = rows[k + 1]
        for i in range(n):
            j = (i + 1) % n
            reg, uo, vi, vj = edge_map[i]
            ua, ub = uo + ta * L, uo + tb_ * L
            mb.f((A[i], A[j], B[j], B[i]), [suv(reg, ua, vi), suv(reg, ua, vj), suv(reg, ub, vj), suv(reg, ub, vi)],
                 reg)
    if cap_map is not None:
        reg, (cy, cz), rad, rot = cap_map
        for side, (t, ids) in ((0, rows[0]), (1, rows[-1])):
            sc = 1.0 + (taper - 1.0) * t
            order = list(range(n)) if side == 1 else list(reversed(range(n)))
            uvs = []
            for i in order:
                y, z = sec[i]
                yy = (y - cy) / rad
                zz = (z - cz) / rad
                if side == 0:
                    yy = -yy
                ang = math.atan2(zz, yy) + rot
                rho = min(1.0, math.hypot(yy, zz))
                uvs.append(disc_uv(reg, ang, rho))
            mb.f([ids[i] for i in order], uvs, reg)
    return rows


def arc(cy, cz, r, a0, a1, n, jit=0.0, rng=None):
    """Points on a circular arc (angles in radians, measured from +y toward +z) - for log sections."""
    rng = rng or random
    out = []
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        rr = r * (1.0 + (rng.uniform(-jit, jit) if jit else 0.0))
        out.append((cy + rr * math.cos(a), cz + rr * math.sin(a)))
    return out


def box_uv_face(reg, n, p, origin, scale=1.0, vext=None, u_shift=0.0):
    """Box-projection UV of point p for a face with normal n, into a region (strip: u wraps, v normalised by
    vext = (lo, hi) of the projected v coordinate)."""
    q = (p - origin) * scale
    a = max(range(3), key=lambda i: abs(n[i]))
    if a == 0:
        u, w = (q.y if n.x > 0 else -q.y), q.z
    elif a == 1:
        u, w = (-q.x if n.y > 0 else q.x), q.z
    else:
        u, w = (q.x if n.z > 0 else -q.x), q.y
    u += u_shift
    if reg["fullWidth"]:
        lo, hi = vext if vext else (0.0, reg["tile"][1])
        return suv(reg, u, (w - lo) / max(hi - lo, 1e-6))
    tw, th = reg["tile"]
    lo, hi = vext if vext else (0.0, th)
    return buv(reg, (u / tw) % 1.0, (w - lo) / max(hi - lo, 1e-6))


def solid_box_proj(mb, verts, faces, reg, origin=None, scale=1.0, vext=None, u_shift=0.0):
    """Add a closed solid given as vertex positions + faces (CCW from outside), UVs by box projection.
    Default origin = the solid's bounding-box minimum and vext = (0, largest extent), so every projected V
    stays inside the region."""
    if origin is None:
        origin = V((min(p[0] for p in verts), min(p[1] for p in verts), min(p[2] for p in verts)))
        if vext is None:
            ext = max(max(p[i] for p in verts) - origin[i] for i in range(3))
            vext = (0.0, max(ext, 1e-3))
    origin = V(origin)
    ids = [mb.v(p) for p in verts]
    for fc in faces:
        pts = [V(verts[i]) for i in fc]
        nrm = V((0, 0, 0))
        for k in range(len(pts)):
            a, b = pts[k], pts[(k + 1) % len(pts)]
            nrm += V(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        if nrm.length < 1e-12:
            nrm = V((0, 0, 1))
        nrm.normalize()
        mb.f([ids[i] for i in fc], [box_uv_face(reg, nrm, p, origin, scale, vext, u_shift) for p in pts], reg)
    return ids


def box_solid(mb, lo, hi, reg, rz=0.0, origin=None, vext=None, jit=0.0, rng=None, u_shift=None):
    """Axis-aligned (optionally turned about Z) box, box-projected UVs."""
    rng = rng or random
    lo, hi = V(lo), V(hi)
    c = (lo + hi) / 2
    h = (hi - lo) / 2
    ca, sa = math.cos(rz), math.sin(rz)
    verts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                x, y = sx * h.x, sy * h.y
                p = V((c.x + x * ca - y * sa, c.y + x * sa + y * ca, c.z + sz * h.z))
                if jit:
                    p += V((rng.uniform(-jit, jit), rng.uniform(-jit, jit), rng.uniform(-jit, jit)))
                verts.append(p)
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return solid_box_proj(mb, verts, faces, reg, origin, 1.0, vext, rng.uniform(0, 40) if u_shift is None else u_shift)


def band(mb, outline, z0, z1, reg, u_off=0.0, top_reg=None, bottom=True, top=True, z_top_fn=None):
    """Masonry band: prism of a CCW outline (x, y) from z0 to z1. Sides: U = perimeter distance, V = height.
    z_top_fn(x, y) optionally lifts the top edge (sloped caps)."""
    n = len(outline)
    lo = [mb.v((x, y, z0)) for (x, y) in outline]
    hi = [mb.v((x, y, z_top_fn(x, y) if z_top_fn else z1)) for (x, y) in outline]
    s = u_off
    for i in range(n):
        j = (i + 1) % n
        a, b = V(outline[i] + (0,)), V(outline[j] + (0,))
        L = (b - a).length
        za1 = mb.co[hi[i]].z
        zb1 = mb.co[hi[j]].z
        mb.f((lo[i], lo[j], hi[j], hi[i]),
             [suv(reg, s, 0.0), suv(reg, s + L, 0.0), suv(reg, s + L, (zb1 - z0) / (z1 - z0)),
              suv(reg, s, (za1 - z0) / (z1 - z0))], reg)
        s += L
    treg = top_reg or reg
    if top:
        mb.f(hi, [box_uv_face(treg, V((0, 0, 1)), mb.co[k], V((0, 0, 0)), 1.0, (-3, 3)) for k in hi], treg)
    if bottom:
        mb.f(list(reversed(lo)), [box_uv_face(treg, V((0, 0, -1)), mb.co[k], V((0, 0, 0)), 1.0, (-3, 3))
                                  for k in reversed(lo)], treg)
    return lo, hi


def rock(mb, center, size, reg, rng, subdiv=1, rough=0.18, flat_bottom=True, rz=None, squash_top=0.0, facets=0,
         cut=(0.62, 0.86)):
    """Irregular stone: subdivided cube pushed toward an ellipsoid, noise-dented, flat-ish base. facets = number of
    random fracture planes that shave the shape flat (angular split stone with crisp arrises instead of a pillow)."""
    cx, cy, cz = center
    sx, sy, sz = size
    rz = rng.uniform(0, TAU) if rz is None else rz
    n = 2 + subdiv
    pts = {}
    ids = {}
    faces = []
    # cube surface grid
    def key(i, j, k):
        return (i, j, k)
    grid_pts = []
    for i in range(n + 1):
        for j in range(n + 1):
            for k in range(n + 1):
                if 0 < i < n and 0 < j < n and 0 < k < n:
                    continue
                grid_pts.append((i, j, k))
    phase = [rng.uniform(0, TAU) for _ in range(9)]
    planes = []
    for _ in range(facets):
        a, e = rng.uniform(0, TAU), rng.uniform(-0.25, 1.2)
        pn = V((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        planes.append((pn, rng.uniform(*cut)))
    ca, sa = math.cos(rz), math.sin(rz)
    verts = []
    index = {}
    for (i, j, k) in grid_pts:
        p = V((i / n * 2 - 1, j / n * 2 - 1, k / n * 2 - 1))
        q = p.normalized()
        bl = 0.62
        q = V((q.x * bl + p.x * (1 - bl) * 0.75, q.y * bl + p.y * (1 - bl) * 0.75, q.z * bl + p.z * (1 - bl) * 0.75))
        nz = (math.sin(3.1 * q.x + phase[0]) * math.sin(2.7 * q.y + phase[1]) + math.sin(2.3 * q.z + phase[2])
              + 0.5 * math.sin(5.3 * q.x + 4.1 * q.z + phase[3]) + 0.5 * math.sin(4.7 * q.y - 3.9 * q.z + phase[4]))
        q = q * (1.0 + rough * 0.22 * nz)
        for (pn, pd) in planes:
            dd = q.dot(pn) - pd
            if dd > 0:
                q = q - pn * dd
        x, y, z = q.x * sx / 2, q.y * sy / 2, q.z * sz / 2
        if flat_bottom and z < -sz * 0.32:
            z = -sz * 0.32 + (z + sz * 0.32) * 0.25
        if squash_top and z > sz * 0.25:
            z = sz * 0.25 + (z - sz * 0.25) * (1 - squash_top)
        index[(i, j, k)] = len(verts)
        verts.append(V((cx + x * ca - y * sa, cy + x * sa + y * ca, cz + z + sz * 0.32 * (1 if flat_bottom else 0))))
    def g(i, j, k):
        return index[(i, j, k)]
    for a in range(n):
        for b in range(n):
            # 6 faces of the cube, CCW from outside
            faces.append((g(n, a, b), g(n, a + 1, b), g(n, a + 1, b + 1), g(n, a, b + 1)))      # +x
            faces.append((g(0, a, b), g(0, a, b + 1), g(0, a + 1, b + 1), g(0, a + 1, b)))      # -x
            faces.append((g(a, n, b), g(a, n, b + 1), g(a + 1, n, b + 1), g(a + 1, n, b)))      # +y
            faces.append((g(a, 0, b), g(a + 1, 0, b), g(a + 1, 0, b + 1), g(a, 0, b + 1)))      # -y
            faces.append((g(a, b, n), g(a + 1, b, n), g(a + 1, b + 1, n), g(a, b + 1, n)))      # +z
            faces.append((g(a, b, 0), g(a, b + 1, 0), g(a + 1, b + 1, 0), g(a + 1, b, 0)))      # -z
    return solid_box_proj(mb, verts, faces, reg, None, 1.0, None, rng.uniform(0, 40))


def rope(mb, pts, r, reg, segs=6, u_off=None, rng=None, cap=True, u_scale=1.0):
    """Rope / cable along a polyline (list of points). V wraps once round the rope. u_scale compresses U (studs
    along the rope) so a long strap fits a small block region."""
    rng = rng or random
    pts = [V(p) for p in pts]
    if not reg["fullWidth"] and u_off is None:
        u_off = 0.02
    u_off = rng.uniform(0, 50) if u_off is None else u_off
    rings = []
    s = 0.0
    prev_y = None
    for k, p in enumerate(pts):
        if k == 0:
            d = pts[1] - pts[0]
        elif k == len(pts) - 1:
            d = pts[-1] - pts[-2]
        else:
            d = (pts[k + 1] - pts[k - 1])
        x, y, z = frame(d, (0, 0, 1))
        if prev_y is not None and y.dot(prev_y) < 0:
            y, z = -y, -z
        prev_y = y
        if k > 0:
            s += (pts[k] - pts[k - 1]).length * u_scale
        ids = [mb.v(p + (z * math.cos(TAU * i / segs) + y * math.sin(TAU * i / segs)) * r) for i in range(segs)]
        rings.append((s, ids))
    for k in range(len(rings) - 1):
        sa, A = rings[k]
        sb, B = rings[k + 1]
        for i in range(segs):
            j = (i + 1) % segs
            mb.f((A[i], B[i], B[j], A[j]), [suv(reg, u_off + sa, i / segs), suv(reg, u_off + sb, i / segs),
                                            suv(reg, u_off + sb, (i + 1) / segs), suv(reg, u_off + sa, (i + 1) / segs)],
                 reg)
    if cap:
        sa, A = rings[0]
        mb.f(A, [suv(reg, u_off + sa + 0.1 * math.cos(TAU * i / segs), 0.5 + 0.4 * math.sin(TAU * i / segs))
                 for i in range(segs)], reg)
        sb, B = rings[-1]
        mb.f(list(reversed(B)), [suv(reg, u_off + sb + 0.1 * math.cos(-TAU * i / segs), 0.5 + 0.4 * math.sin(-TAU * i / segs))
                                 for i in reversed(range(segs))], reg)
    return rings


def catenary(p0, p1, sag, n):
    """Points of a hanging curve from p0 to p1 dipping 'sag' at mid-span (parabolic approximation)."""
    p0, p1 = V(p0), V(p1)
    out = []
    for i in range(n + 1):
        t = i / n
        p = p0 + (p1 - p0) * t
        p.z -= sag * 4 * t * (1 - t)
        out.append(p)
    return out


def course(mb, O, a_dir, s_dir, n_dir, a0, a1, d_butt, expo, butt_th, reg, butt_reg, u_off, nu=4,
           top_th=0.03, warp=None):
    """One course of shakes on a roof plane P(a, d) = O + a*a_dir + d*s_dir (d = distance down the slope,
    n_dir = outward normal). The closed wedge spans d_butt - expo .. d_butt: thin at the top, butt_th thick at
    the butt. warp(a, d) -> offset along n_dir (sag / waviness). U runs along -a so the UVs are not mirrored."""
    O, a_dir, s_dir, n_dir = V(O), V(a_dir), V(s_dir), V(n_dir)
    if a_dir.cross(s_dir).dot(n_dir) < 0:
        a_dir = -a_dir
        a0, a1 = -a1, -a0
        if warp is not None:
            w0 = warp
            warp = lambda a, d: w0(-a, d)  # noqa: E731
    d_top = d_butt - expo
    rows = []
    for i in range(nu + 1):
        a = a0 + (a1 - a0) * i / nu
        w_t = warp(a, d_top) if warp else 0.0
        w_b = warp(a, d_butt) if warp else 0.0
        base_t = O + a_dir * a + s_dir * d_top
        base_b = O + a_dir * a + s_dir * d_butt
        ids = (mb.v(base_t + n_dir * (top_th + w_t)), mb.v(base_b + n_dir * (butt_th + w_b)),
               mb.v(base_b + n_dir * (w_b + 0.004)), mb.v(base_t + n_dir * (w_t + 0.004)))
        rows.append((a, ids))
    for i in range(nu):
        aa, A = rows[i]
        ab, B = rows[i + 1]
        ua, ub = u_off + (a1 - aa), u_off + (a1 - ab)
        mb.f((A[0], B[0], B[1], A[1]), [suv(reg, ua, 1.0), suv(reg, ub, 1.0), suv(reg, ub, 0.0), suv(reg, ua, 0.0)],
             reg)
        mb.f((A[1], B[1], B[2], A[2]), [suv(butt_reg, ua, 1.0), suv(butt_reg, ub, 1.0), suv(butt_reg, ub, 0.0),
                                       suv(butt_reg, ua, 0.0)], butt_reg)
        mb.f((A[2], B[2], B[3], A[3]), [suv(butt_reg, ua, 0.0), suv(butt_reg, ub, 0.0), suv(butt_reg, ub, 0.3),
                                       suv(butt_reg, ua, 0.3)], butt_reg)
        mb.f((A[3], B[3], B[0], A[0]), [suv(butt_reg, ua, 0.0), suv(butt_reg, ub, 0.0), suv(butt_reg, ub, 0.25),
                                       suv(butt_reg, ua, 0.25)], butt_reg)
    for side in (0, nu):
        a, ids = rows[side]
        order = (ids[0], ids[1], ids[2], ids[3]) if side == 0 else (ids[3], ids[2], ids[1], ids[0])
        uvo = [suv(butt_reg, u_off, 1.0), suv(butt_reg, u_off + expo, 1.0), suv(butt_reg, u_off + expo, 0.0),
               suv(butt_reg, u_off, 0.0)]
        if side != 0:
            uvo = [uvo[3], uvo[2], uvo[1], uvo[0]]
        mb.f(order, uvo, butt_reg)
    return rows


def sheet(mb, P, nu, nv, thick, reg, u_fn, v_fn, reg_in=None, edges=True, v_edge=0.06):
    """Cloth / canvas / blanket with real thickness. P(a, b) -> point for a, b in 0..1; the side that a x b
    points to is the OUTER face. u_fn(a, b) -> U in studs, v_fn(a, b) -> V 0..1 of the region. The inner face
    mirrors U so neither island is flipped (tangent space stays consistent). Returns the outer vertex grid."""
    g = [[V(P(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        ia, ib = max(i - 1, 0), min(i + 1, nu)
        ja, jb = max(j - 1, 0), min(j + 1, nv)
        n = (g[ib][j] - g[ia][j]).cross(g[i][jb] - g[i][ja])
        return n.normalized() if n.length > 1e-9 else V((0, 0, 1))
    nn = [[nrm(i, j) for j in range(nv + 1)] for i in range(nu + 1)]
    top = [[mb.v(g[i][j] + nn[i][j] * (thick * 0.5)) for j in range(nv + 1)] for i in range(nu + 1)]
    bot = [[mb.v(g[i][j] - nn[i][j] * (thick * 0.5)) for j in range(nv + 1)] for i in range(nu + 1)]
    ri = reg_in or reg
    if ri["fullWidth"]:
        def iu(a, b):
            return -u_fn(a, b)
    else:
        def iu(a, b):
            return ri["tile"][0] - u_fn(a, b)
    for i in range(nu):
        for j in range(nv):
            a0, a1, b0, b1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
            mb.f((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]),
                 [suv(reg, u_fn(a0, b0), v_fn(a0, b0)), suv(reg, u_fn(a1, b0), v_fn(a1, b0)),
                  suv(reg, u_fn(a1, b1), v_fn(a1, b1)), suv(reg, u_fn(a0, b1), v_fn(a0, b1))], reg)
            mb.f((bot[i][j], bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j]),
                 [suv(ri, iu(a0, b0), v_fn(a0, b0)), suv(ri, iu(a0, b1), v_fn(a0, b1)),
                  suv(ri, iu(a1, b1), v_fn(a1, b1)), suv(ri, iu(a1, b0), v_fn(a1, b0))], ri)
    if edges:
        def strip(seq):
            for k in range(len(seq) - 1):
                (i0, j0), (i1, j1) = seq[k], seq[k + 1]
                ua, ub = u_fn(i0 / nu, j0 / nv), u_fn(i1 / nu, j1 / nv)
                va = v_fn(i0 / nu, j0 / nv)
                vb = min(1.0, va + v_edge) if va < 0.5 else max(0.0, va - v_edge)
                mb.f((top[i1][j1], top[i0][j0], bot[i0][j0], bot[i1][j1]),
                     [suv(reg, ub, va), suv(reg, ua, va), suv(reg, ua, vb), suv(reg, ub, vb)], reg)
        strip([(i, 0) for i in range(nu + 1)][::-1])
        strip([(nu, j) for j in range(nv + 1)][::-1])
        strip([(i, nv) for i in range(nu + 1)])
        strip([(0, j) for j in range(nv + 1)])
    return top


def lathe(mb, prof, segs, reg, c=(0, 0, 0), rot=0.0, u_scale=None, v_range=(0.0, 1.0), cap_bottom=True,
          cap_top=True, cap_reg=None):
    """Surface of revolution about +Z through c. prof = [(r, z), ...] bottom -> top. U runs round (studs at the
    mean radius), V along the profile (v_range of the region). Flat caps close the ends (skipped when r ~ 0)."""
    c = V(c)
    rings = []
    for (r, z) in prof:
        ids = []
        for i in range(segs):
            a = rot + TAU * i / segs
            ids.append(mb.v(c + V((r * math.cos(a), r * math.sin(a), z))))
        rings.append(ids)
    lens = [0.0]
    for k in range(1, len(prof)):
        lens.append(lens[-1] + math.hypot(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]))
    tot = max(lens[-1], 1e-6)
    rm = max(0.02, sum(p[0] for p in prof) / len(prof))
    circ = TAU * rm if u_scale is None else u_scale
    va, vb = v_range
    for k in range(len(prof) - 1):
        v0 = va + (vb - va) * lens[k] / tot
        v1 = va + (vb - va) * lens[k + 1] / tot
        for i in range(segs):
            j = (i + 1) % segs
            ua, ub = circ * i / segs, circ * (i + 1) / segs
            mb.f((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]),
                 [suv(reg, ua, v0), suv(reg, ub, v0), suv(reg, ub, v1), suv(reg, ua, v1)], reg)
    cr = cap_reg or reg
    for (k, on, sgn) in ((0, cap_bottom, -1), (len(prof) - 1, cap_top, 1)):
        if not on or prof[k][0] < 1e-4:
            continue
        order = list(range(segs)) if sgn > 0 else list(reversed(range(segs)))
        uvs = []
        for i in order:
            a = TAU * i / segs * (1 if sgn > 0 else -1)
            if cr["fullWidth"]:
                uvs.append(suv(cr, 0.3 * prof[k][0] * math.cos(a), 0.5 + 0.45 * math.sin(a)))
            else:
                uvs.append(buv(cr, 0.5 + 0.47 * math.cos(a), 0.5 + 0.47 * math.sin(a)))
        mb.f([rings[k][i] for i in order], uvs, cr)
    return rings


def quad_rows(mb, a, b, c, d, reg, rows, u0=0.0, v_span=(0.0, 1.0)):
    """Planar quad a-b-c-d (CCW seen from outside; a->b = U direction, a->d = rows direction) split into
    'rows' bands; every band maps the full V span of the strip (boards, shake rows), U in studs along a->b."""
    a, b, c, d = V(a), V(b), V(c), V(d)
    L = (b - a).length
    va, vb = v_span
    for k in range(rows):
        t0, t1 = k / rows, (k + 1) / rows
        p0 = a + (d - a) * t0
        p1 = b + (c - b) * t0
        p2 = b + (c - b) * t1
        p3 = a + (d - a) * t1
        i0, i1, i2, i3 = mb.v(p0), mb.v(p1), mb.v(p2), mb.v(p3)
        uo = u0 + 13.7 * k
        mb.f((i0, i1, i2, i3), [suv(reg, uo, va), suv(reg, uo + L, va), suv(reg, uo + L, vb), suv(reg, uo, vb)],
             reg)


def board_box(mb, lo, hi, reg, board=0.75, rz=0.0, c=None, u0=None, rng=None, top_reg=None, z_rows=None):
    """Box (optionally turned about Z round c) whose faces are split into board-wide rows: sides run
    horizontally, top / bottom along X. Each row maps the full width of the board strip (its edge AO reads as
    the joint between boards)."""
    rng = rng or random
    lo, hi = V(lo), V(hi)
    cc = (lo + hi) / 2 if c is None else V(c)
    ca, sa = math.cos(rz), math.sin(rz)

    def P(x, y, z):
        dx, dy = x - cc.x, y - cc.y
        return V((cc.x + dx * ca - dy * sa, cc.y + dx * sa + dy * ca, z))
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    nz = z_rows or max(1, int(round((z1 - z0) / board)))
    ny = max(1, int(round((y1 - y0) / board)))
    u0 = rng.uniform(0, 40) if u0 is None else u0
    tr = top_reg or reg
    # sides, CCW seen from outside (a -> b runs to the viewer's right, a -> d up)
    quad_rows(mb, P(x1, y1, z0), P(x0, y1, z0), P(x0, y1, z1), P(x1, y1, z1), reg, nz, u0)
    quad_rows(mb, P(x0, y0, z0), P(x1, y0, z0), P(x1, y0, z1), P(x0, y0, z1), reg, nz, u0 + 7.1)
    quad_rows(mb, P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1), reg, nz, u0 + 3.3)
    quad_rows(mb, P(x0, y1, z0), P(x0, y0, z0), P(x0, y0, z1), P(x0, y1, z1), reg, nz, u0 + 11.9)
    quad_rows(mb, P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1), tr, ny, u0 + 21.0)
    quad_rows(mb, P(x0, y1, z0), P(x1, y1, z0), P(x1, y0, z0), P(x0, y0, z0), tr, ny, u0 + 27.0)


def bolt(mb, p, n, reg, r=0.07, h=0.05, washer=0.0, rot=None, rng=None):
    """Square-headed carriage bolt / lag screw head on a surface at p with outward normal n (closed, 12 tris;
    a washer adds a thin square plate under it)."""
    rng = rng or random
    n = V(n).normalized()
    ax, ay, az = frame(n, (0, 0, 1) if abs(n.z) < 0.9 else (1, 0, 0))
    rot = rng.uniform(0, math.pi / 2) if rot is None else rot
    cr, sr = math.cos(rot), math.sin(rot)
    ey, ez = ay * cr + az * sr, az * cr - ay * sr
    layers = ([(r * 1.7, washer, 0.0)] if washer > 0 else []) + [(r, h, washer)]
    for (rr, hh, base) in layers:
        b0 = V(p) + n * base
        corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        A = [mb.v(b0 + (ey * cy + ez * cz) * rr) for (cy, cz) in corners]
        B = [mb.v(b0 + n * hh + (ey * cy + ez * cz) * rr * 0.92) for (cy, cz) in corners]
        for i in range(4):
            j = (i + 1) % 4
            mb.f((A[i], A[j], B[j], B[i]), [suv(reg, 0.0, 0.0), suv(reg, rr * 2, 0.0), suv(reg, rr * 2, 0.4),
                                            suv(reg, 0.0, 0.4)], reg)
        mb.f(B, [suv(reg, 0.0, 0.1), suv(reg, rr * 2, 0.1), suv(reg, rr * 2, 0.9), suv(reg, 0.0, 0.9)], reg)
        mb.f(list(reversed(A)), [suv(reg, 0.0, 0.1), suv(reg, 0.0, 0.9), suv(reg, rr * 2, 0.9),
                                 suv(reg, rr * 2, 0.1)], reg)


# ================================================================================================
# Materials
# ================================================================================================
def _image(fname, colorspace):
    key = (fname, colorspace)
    if key in _IMGS and _IMGS[key].name in bpy.data.images:
        return _IMGS[key]
    path = os.path.join(TEX_DIR, fname)
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    _IMGS[key] = img
    return img


def sheet_material(sheet, variant=None):
    """Textured PBR material for a sheet. variant: None | 'Glass' (alpha blend) | 'Ember' (emissive)."""
    key = sheet + ("_" + variant if variant else "")
    m = _MATS.get(key)
    if m is not None and m.name in bpy.data.materials:
        return m
    mat = bpy.data.materials.new(tb.PREFIX + key)
    mat.use_nodes = True
    try:
        mat.use_backface_culling = True     # glTF doubleSided = false: every mesh is a closed solid
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    files = tb.files_for(sheet)
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = _image(files["color"], "sRGB")
    tc.location = (-700, 300)
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = _image(files["normal"], "Non-Color")
    tn.location = (-700, -300)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.location = (-350, -300)
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tm = nt.nodes.new("ShaderNodeTexImage")
    tm.image = _image(files["mr"], "Non-Color")
    tm.location = (-700, 0)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-400, 0)
    nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    if variant == "Glass":
        nt.links.new(tc.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    if variant == "Ember":
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0
    _MATS[key] = mat
    return mat


# ================================================================================================
# Parts
# ================================================================================================
def part(lib, root, mbs, role, collide=True, collision="Hull", cast_shadow=True, tags=None, smooth_angle=None,
         variant=None, rename=None, rgb=None, notes=None):
    """Register one or more MBs (same sheet) as a single MeshPart with the sheet's textured material."""
    if not isinstance(mbs, (list, tuple)):
        mbs = [mbs]
    mbs = [m for m in mbs if m is not None and m.faces]
    if not mbs:
        return None
    m = MB(mbs[0].sheet)
    for x in mbs:
        assert x.sheet == m.sheet, "mixing sheets in one part"
        m.merge(x)
    obj = m.build("%s_%s_tmp" % (root.name, role))
    if rgb is None and variant == "Ember":
        rgb = (255, 128, 48)            # Neon fallback colour (v1 ember convention)
    if rgb is None:
        avgs = [_AVG.get(m.sheet, {}).get(r) for r in sorted(m.regions)]
        avgs = [a for a in avgs if a]
        rgb = tuple(int(round(sum(a[i] for a in avgs) / len(avgs))) for i in range(3)) if avgs else None
    lib.add(root, obj, role, rgb=rgb, collide=collide, collision=collision, cast_shadow=cast_shadow, tags=tags,
            uv=False, smooth_angle=smooth_angle)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    mat = sheet_material(m.sheet, variant)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    entry = lib._entry(root)
    p = entry["parts"][-1]
    files = tb.files_for(m.sheet)
    surf = {"sheet": tb.PREFIX + m.sheet, "colorMap": files["color"], "normalMap": files["normal"],
            "roughnessMap": files["roughness"], "metalRoughnessMap": files["mr"], "regions": sorted(m.regions),
            "doubleSided": False}
    if m.sheet == "Kit" and m.regions & METAL_REGIONS:
        surf["metalnessMap"] = files["metal"]
    if variant == "Glass":
        surf["alphaMode"] = "Transparency"
        surf["meshTransparency"] = 0.15
    if variant == "Ember":
        surf["emissive"] = {"glTF": "emissiveTexture = colorMap, strength 3",
                            "roblox": "Material Neon with Color (255,128,48) + a warm PointLight at the asset's "
                                      "light attachment (v1 convention), or keep the SurfaceAppearance and add "
                                      "EmissiveStrength 1-3 / EmissiveTint (255,150,80) if the importer kept the "
                                      "emissive map"}
    p["surface"] = surf
    if notes:
        p["notes"] = notes
    if rename:
        new = "%s_%s" % (root.name, rename)
        obj.name = new
        obj.data.name = new
        p["name"] = new
    return obj


# ================================================================================================
# Export (ls Library.export layout + glTF options for PBR, extended manifest)
# ================================================================================================
REPO_MANIFESTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "manifests"))


def export(lib, out_dir, gap=8.0, extra=None):
    for e in lib.assets:
        if "size" not in e:
            lib.finish(e["root"])
    x = 0.0
    for e in lib.assets:
        width = e["size"][0]
        min_x = e["boundsMin"][0]
        offset = x - min_x
        e["root"].location = (offset, 0, 0)
        e["origin"] = [round(offset, 4), 0.0, 0.0]
        x += width + gap
    bpy.context.view_layer.update()
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for e in lib.assets:
        e["root"].select_set(True)
        for c in e["root"].children_recursive:
            c.select_set(True)
    glb = os.path.join(out_dir, lib.category + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_tangents=True, export_image_format="AUTO", export_materials="EXPORT")
    used_sheets = set()
    for e in lib.assets:
        for p in e["parts"]:
            if "surface" in p:
                used_sheets.add(p["surface"]["sheet"][len(tb.PREFIX):])
    textures = {}
    for s in sorted(used_sheets):
        textures[tb.PREFIX + s] = tb.files_for(s)
    manifest = {
        "category": lib.category,
        "set": SET_NAME,
        "glb": os.path.basename(glb),
        "units": "1 Blender unit = 1 Roblox stud",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
        "surfaces": ("Every part has a 'surface': textured PBR from the BR_ sheets, embedded in the GLB as "
                     "baseColorTexture / normalTexture (OpenGL +Y, tangent space) / metallicRoughnessTexture, with "
                     "TANGENT, NORMAL and TEXCOORD_0 on every primitive. The 3D importer turns them into a "
                     "SurfaceAppearance. If its packed-map conversion is poor, build the SurfaceAppearance by hand "
                     "from textures/" + SET_NAME + "/: ColorMap = colorMap, NormalMap = normalMap, RoughnessMap = "
                     "roughnessMap (8-bit grayscale), MetalnessMap = metalnessMap (only parts that list one; "
                     "leave it empty elsewhere), AlphaMode = alphaMode (glass only, with MeshPart.Transparency = "
                     "meshTransparency; every other part ignores alpha). All parts are closed solids: "
                     "DoubleSided false. 'rgb' is the average texture colour (MeshPart.Color fallback), "
                     "'robloxMaterial' the fallback material if no SurfaceAppearance is applied."),
        "uploads": {"importer": "the GLB embeds 15 images: BR_<Sheet>_Color / _Normal / _MR for Wood, Log, Stone, "
                                "Shake, Kit (both BuildingsReal.glb and PropsReal.glb embed the same files - upload "
                                "each PNG once and share the ids)",
                    "manual": "16 images: BR_<Sheet>_Color, BR_<Sheet>_Normal, BR_<Sheet>_Roughness (5 sheets) + "
                              "BR_Kit_Metal"},
        "texelDensity": {s_: {r_: tb.LAYOUT[s_][r_][5] for r_ in tb.LAYOUT[s_]} for s_ in tb.SHEETS},
        "texelDensityUnits": "pixels per stud on the 1024 sheets (logs 164, boards / shakes 160, masonry 200, "
                             "bark 196, canvas 128; end-grain discs 100)",
        "textureSheets": textures,
        "assets": [],
        "warnings": lib.warnings,
    }
    if extra:
        manifest.update(extra)
    for e in lib.assets:
        manifest["assets"].append({k: v for k, v in e.items() if k != "root"})
    mpath = os.path.join(out_dir, lib.category + ".manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    os.makedirs(REPO_MANIFESTS, exist_ok=True)
    shutil.copyfile(mpath, os.path.join(REPO_MANIFESTS, lib.category + ".manifest.json"))
    size_mb = os.path.getsize(glb) / (1024 * 1024)
    print("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (glb, size_mb, len(lib.assets), len(lib.warnings)))
    for w in lib.warnings:
        print("WARNING " + w)
    if size_mb > 19:
        print("WARNING GLB is over 19 MB - split it (upload limit is 20 MB per file)")
    # back to the build position (every asset at the origin) for the review renders
    for e in lib.assets:
        e["root"].location = (0, 0, 0)
    bpy.context.view_layer.update()
    return manifest
