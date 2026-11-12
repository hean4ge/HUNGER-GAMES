"""
bld_kit.py - construction helpers for the LAST STANDING "Buildings" and "Props" generators.
Built on top of ls_common (which must not be edited). Geometry is built directly in asset space
(origin = asset centre on the ground, front = +Y), so lib.add() only has to bake identity transforms.
Rule of thumb used everywhere: overlapping pieces interpenetrate instead of sharing coplanar faces
(no z-fighting), and every piece is a closed solid.
"""
import math
import random

import bmesh
from mathutils import Vector as V

import ls_common as ls

TAU = 2.0 * math.pi
# Project-wide door opening (player = 5.5 studs): 4 wide x 7.5 tall clear opening, used by every enterable building
DOOR_W, DOOR_H = 4.0, 7.5


def door_opening(cx, floor_z, w=DOOR_W, h=DOOR_H):
    """(lo, hi, z_lo, z_hi) of a standard door opening centred on cx, standing on floor_z."""
    return (cx - w / 2, cx + w / 2, floor_z, floor_z + h)


BOX_FACES =[(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]


def rnd(a, b):
    return random.uniform(a, b)


def tint(role, amt=6, base=None):
    """A small random rgb override around a role colour (so repeated parts don't look cloned)."""
    r, g, b = base or ls.ROLES[role]["rgb"]
    d = rnd(-amt, amt)
    return tuple(max(0, min(255, int(round(c + d + rnd(-2, 2))))) for c in (r, g, b))


def mesh_obj(name, verts, faces):
    bm = bmesh.new()
    vs = [bm.verts.new(V(v)) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def frame(axis, up=(0, 0, 1)):
    """Orthonormal frame (x along axis, z as close to 'up' as possible)."""
    x = V(axis).normalized()
    u = V(up).normalized()
    if abs(x.dot(u)) > 0.98:
        u = V((0, 1, 0)) if abs(x.y) < 0.9 else V((1, 0, 0))
    z = (u - x * u.dot(x)).normalized()
    return x, z.cross(x), z


def _box_verts(c, ax, ay, az, hx, hy, hz):
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                out.append(c + ax * (sx * hx) + ay * (sy * hy) + az * (sz * hz))
    return out


def beam(name, p0, p1, w, h, up=(0, 0, 1), bev=0.0, ext=0.0):
    """Square timber from p0 to p1: w across, h towards 'up'. ext lengthens both ends."""
    p0, p1 = V(p0), V(p1)
    ax, ay, az = frame(p1 - p0, up)
    obj = mesh_obj(name, _box_verts((p0 + p1) / 2, ax, ay, az, (p1 - p0).length / 2 + ext, w / 2, h / 2),
                   BOX_FACES)
    if bev > 0:
        ls.bevel(obj, bev, 1, 40)
    return obj


def abox(name, lo, hi, bev=0.0, rz=0.0):
    """Axis-aligned box between corners lo and hi, optionally turned rz radians about its centre."""
    lo, hi = V(lo), V(hi)
    c, h = (lo + hi) / 2, (hi - lo) / 2
    ax = V((math.cos(rz), math.sin(rz), 0))
    ay = V((-math.sin(rz), math.cos(rz), 0))
    obj = mesh_obj(name, _box_verts(c, ax, ay, V((0, 0, 1)), abs(h.x), abs(h.y), abs(h.z)), BOX_FACES)
    if bev > 0:
        ls.bevel(obj, bev, 1, 40)
    return obj


def rock(name, lo, hi, bev=0.12, jit=0.06, rz=0.0):
    """Chunky masonry stone: bevelled box with jittered vertices (flat shaded later)."""
    obj = abox(name, lo, hi, bev, rz)
    if jit > 0:
        ls.jitter(obj, jit)
    return obj


def tube(name, p0, p1, r0, r1=None, segs=8, rings=2, bend=0.0, bulge=0.0, ch0=0.0, ch1=0.0,
         rj=0.0, phase=None, up=(0, 0, 1), cap_scale=0.82):
    """Log / pole / rope from p0 to p1. ch0/ch1 = chamfer length at the ends (adds a smaller cap ring)."""
    p0, p1 = V(p0), V(p1)
    r1 = r0 if r1 is None else r1
    ax, u, w = frame(p1 - p0, up)
    L = max((p1 - p0).length, 1e-4)
    phase = rnd(0, TAU) if phase is None else phase
    bdir = u * rnd(-1, 1) + w * rnd(-1, 1)
    bdir = bdir.normalized() * bend if bdir.length > 1e-6 else V((0, 0, 0))
    st = []
    t0 = min(ch0 / L, 0.3) if ch0 > 0 else 0.0
    t1 = 1.0 - (min(ch1 / L, 0.3) if ch1 > 0 else 0.0)
    if ch0 > 0:
        st.append((0.0, cap_scale))
    for i in range(rings):
        st.append((t0 + (t1 - t0) * i / (rings - 1), 1.0))
    if ch1 > 0:
        st.append((1.0, cap_scale))
    verts, faces = [], []
    for (t, s) in st:
        r = (r0 + (r1 - r0) * t) * s * (1 + bulge * math.sin(math.pi * t)) * (1 + rnd(-rj, rj))
        c = p0 + ax * (L * t) + bdir * math.sin(math.pi * t)
        for i in range(segs):
            a = phase + TAU * i / segs
            verts.append(c + u * (r * math.cos(a)) + w * (r * math.sin(a)))
    n = len(st)
    for k in range(n - 1):
        for i in range(segs):
            j = (i + 1) % segs
            faces.append((k * segs + i, k * segs + j, (k + 1) * segs + j, (k + 1) * segs + i))
    faces.append(tuple(reversed(range(segs))))
    faces.append(tuple(range((n - 1) * segs, n * segs)))
    return mesh_obj(name, verts, faces)


def ring(name, r_in, r_out, h0, h1, segs=16, axis="z", c=(0, 0, 0), phase=0.0, jit=0.0):
    """Annulus with a rectangular cross-section around Z (or X): hoops, rims, well walls."""
    c = V(c)
    verts, faces = [], []
    for i in range(segs):
        a = phase + TAU * i / segs
        ca, sa = math.cos(a), math.sin(a)
        for (r, h) in ((r_in, h0), (r_out, h0), (r_out, h1), (r_in, h1)):
            rr = r + (rnd(-jit, jit) if jit else 0.0)
            p = (rr * ca, rr * sa, h) if axis == "z" else (h, rr * ca, rr * sa)
            verts.append(c + V(p))
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(4):
            m = (k + 1) % 4
            faces.append((i * 4 + k, j * 4 + k, j * 4 + m, i * 4 + m))
    return mesh_obj(name, verts, faces)


def prism(name, pts, a0, a1, axis="y"):
    """Extrude a 2D polygon between a0 and a1 along an axis. axis 'y': pts are (x, z); 'x': (y, z); 'z': (x, y)."""
    def P(p, a):
        if axis == "y":
            return (p[0], a, p[1])
        if axis == "x":
            return (a, p[0], p[1])
        return (p[0], p[1], a)
    n = len(pts)
    verts = [P(p, a0) for p in pts] + [P(p, a1) for p in pts]
    faces = [tuple(range(n)), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return mesh_obj(name, verts, faces)


def grid_solid(name, nu, nv, fn, thick, side=(0, 0, 1)):
    """Thin solid from a parametric surface fn(u, v) -> point (u, v in 0..1), offset 'thick' against
    its normal (the normal is flipped to agree with 'side'). Cloth, canvas, nets, curved boards."""
    top = [[V(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
    sd = V(side)
    verts, faces, it, ib = [], [], {}, {}
    for i in range(nu + 1):
        for j in range(nv + 1):
            du = top[min(i + 1, nu)][j] - top[max(i - 1, 0)][j]
            dv = top[i][min(j + 1, nv)] - top[i][max(j - 1, 0)]
            n = du.cross(dv)
            n = n.normalized() if n.length > 1e-9 else V(sd)
            if n.dot(sd) < 0:
                n = -n
            it[i, j] = len(verts)
            verts.append(top[i][j])
            ib[i, j] = len(verts)
            verts.append(top[i][j] - n * thick)
    for i in range(nu):
        for j in range(nv):
            faces.append((it[i, j], it[i + 1, j], it[i + 1, j + 1], it[i, j + 1]))
            faces.append((ib[i, j], ib[i, j + 1], ib[i + 1, j + 1], ib[i + 1, j]))
    for i in range(nu):
        for j in (0, nv):
            faces.append((it[i, j], ib[i, j], ib[i + 1, j], it[i + 1, j]))
    for j in range(nv):
        for i in (0, nu):
            faces.append((it[i, j], it[i, j + 1], ib[i, j + 1], ib[i, j]))
    return mesh_obj(name, verts, faces)


def roof_slab(name, a0, a1, run, pitch_deg, z_ridge, thick, side=1, axis="x", c=(0.0, 0.0),
              nu=6, nv=3, sag=0.0, jit=0.0, droop=0.0):
    """One slope of a gable (or shed) roof. The UNDERSIDE passes through the ridge line (height z_ridge at
    across-offset 0) and falls at the pitch for the horizontal distance 'run'. a0..a1 = extent along the ridge.
    side = +1 / -1 picks the slope direction; axis = ridge direction ('x' or 'y'). The top surface meets the
    opposite slab in a clean mitre at the ridge. sag dips the middle, jit roughens the free edges (thatch)."""
    th = math.radians(pitch_deg)
    t, ct, st_ = math.tan(th), math.cos(th), math.sin(th)
    cx, cy = c

    def P(a, b, z):
        return V((cx + a, cy + b, z)) if axis == "x" else V((cx + b, cy + a, z))

    verts, faces, idx = [], [], {}
    for i in range(nu + 1):
        a = a0 + (a1 - a0) * i / nu
        for j in range(nv + 1):
            d = run * j / nv
            sg = sag * math.sin(math.pi * i / nu) * math.sin(math.pi * j / nv)
            zu = z_ridge - d * t - sg - droop * (j / nv) ** 2
            edge = j > 0 and (j == nv or i in (0, nu))
            ja = rnd(-jit, jit) if (edge and jit and i in (0, nu)) else 0.0
            jz = rnd(-jit, jit) if (edge and jit) else 0.0
            jb = rnd(0, jit) if (edge and jit and j == nv) else 0.0
            idx[i, j, 0] = len(verts)
            verts.append(P(a + ja, side * (d + jb), zu + jz))
            idx[i, j, 1] = len(verts)
            if j == 0:
                verts.append(P(a, 0.0, z_ridge + thick / ct))
            else:
                verts.append(P(a + ja, side * (d + jb + thick * st_), zu + thick * ct + jz))
    for i in range(nu):
        for j in range(nv):
            for k in (0, 1):
                faces.append((idx[i, j, k], idx[i + 1, j, k], idx[i + 1, j + 1, k], idx[i, j + 1, k]))
    for i in range(nu):
        for j in (0, nv):
            faces.append((idx[i, j, 0], idx[i + 1, j, 0], idx[i + 1, j, 1], idx[i, j, 1]))
    for j in range(nv):
        for i in (0, nu):
            faces.append((idx[i, j, 0], idx[i, j + 1, 0], idx[i, j + 1, 1], idx[i, j, 1]))
    return mesh_obj(name, verts, faces)


def cut_intervals(a0, a1, cuts):
    """[a0, a1] minus the union of the cut intervals -> list of (lo, hi)."""
    segs = [(a0, a1)]
    for (cl, ch) in cuts:
        nxt = []
        for (lo, hi) in segs:
            if ch <= lo or cl >= hi:
                nxt.append((lo, hi))
                continue
            if cl > lo:
                nxt.append((lo, cl))
            if ch < hi:
                nxt.append((ch, hi))
        segs = nxt
    return segs


def wall_boxes(name, axis, c, t, a0, a1, z0, z1, openings, bev=0.0):
    """Solid wall along 'x' (at y = c) or 'y' (at x = c), thickness t, a0..a1 x z0..z1, with rectangular
    openings (lo, hi, zlo, zhi) left open. Returns a list of boxes (piers, spandrels, sills)."""
    out = []

    def B(al, ah, zl, zh):
        if ah - al < 1e-3 or zh - zl < 1e-3:
            return
        if axis == "x":
            out.append(abox(name, (al, c - t / 2, zl), (ah, c + t / 2, zh), bev))
        else:
            out.append(abox(name, (c - t / 2, al, zl), (c + t / 2, ah, zh), bev))
    cur = a0
    for (lo, hi, zl, zh) in sorted(openings):
        B(cur, lo, z0, z1)
        B(lo, hi, z0, zl)
        B(lo, hi, zh, z1)
        cur = hi
    B(cur, a1, z0, z1)
    return out


def frame_boards(name, axis, c, t, lo, hi, zl, zh, b=0.35, proud=0.12, sill=True, bev=0.04,
                 head_top=None, sill_bot=None):
    """Timber frame (jambs, header, optional projecting sill) lining an opening in a wall of thickness t."""
    d = t / 2 + proud
    out = []

    def B(al, ah, zlo, zhi, dd):
        if axis == "x":
            out.append(abox(name, (al, c - dd, zlo), (ah, c + dd, zhi), bev))
        else:
            out.append(abox(name, (c - dd, al, zlo), (c + dd, ah, zhi), bev))
    htop = zh + b if head_top is None else max(head_top, zh + 0.25)
    sbot = zl - b if sill_bot is None else min(sill_bot, zl - 0.25)
    B(lo - b, lo, zl - 0.05, htop - 0.08, d)
    B(hi, hi + b, zl - 0.05, htop - 0.08, d)
    B(lo - b - 0.12, hi + b + 0.12, zh, htop, d + 0.04)
    if sill:
        B(lo - b - 0.22, hi + b + 0.22, sbot, zl, d + 0.1)
    return out


def ladder(name, base, height, width=1.5, axis="x", step=1.0, top_ext=1.0, rail=(0.22, 0.3), rung_r=0.09):
    """Vertical wooden ladder (rails spread along 'axis') standing at base. Visual only."""
    base = V(base)
    off = V((width / 2, 0, 0)) if axis == "x" else V((0, width / 2, 0))
    up = (0, 1, 0) if axis == "x" else (1, 0, 0)
    out = [beam(name, base + s * off, base + s * off + V((0, 0, height + top_ext)), rail[0], rail[1], up=up)
           for s in (-1, 1)]
    z = step * 0.75
    while z < height + 0.3:
        out.append(tube(name, base - off + V((0, 0, z)), base + off + V((0, 0, z)), rung_r, segs=6, phase=0.0))
        z += step
    return out


def shake_roof(name, a0, a1, run, pitch_deg, z_ridge, thick, side=1, axis="x", courses=4, lap=0.25,
               strip=0.16, lift_deg=4.0, nu=4, jit=0.0):
    """Stepped shingle/shake courses lying on top of a roof_slab with the same parameters: each course is a
    strip tilted lift_deg flatter so its lower edge stands proud -> horizontal shadow lines across the roof."""
    th = math.radians(pitch_deg)
    z_top0 = z_ridge + thick / math.cos(th)
    out = []
    step = run / courses
    for i in range(courses):
        da = max(0.0, i * step - lap)
        db = run + 0.12 if i == courses - 1 else (i + 1) * step
        zt = z_top0 - da * math.tan(th) + 0.01
        c = (0.0, side * da) if axis == "x" else (side * da, 0.0)
        out.append(roof_slab(name, a0, a1, db - da, pitch_deg - lift_deg, zt, strip, side=side, axis=axis, c=c,
                             nu=nu, nv=1, jit=jit))
    return out


def railing(name, pts, z_of, height=3.2, post_every=2.4, post=0.32, rail=(0.22, 0.28), mid=True, low=False,
            bev=0.03, skip_first=False, skip_last=False, rail_bev=0.0):
    """Posts + rails along a polyline of (x, y) points. z_of(x, y) = floor height under that point."""
    out = []
    posts = []
    for k in range(len(pts) - 1):
        a, b = V((pts[k][0], pts[k][1], 0)), V((pts[k + 1][0], pts[k + 1][1], 0))
        n = max(1, int(math.ceil((b - a).length / post_every)))
        for i in range(n + (1 if k == len(pts) - 2 else 0)):
            posts.append(a + (b - a) * (i / n))
    tops = []
    for i, p in enumerate(posts):
        z = z_of(p.x, p.y)
        tops.append(V((p.x, p.y, z)))
        if (i == 0 and skip_first) or (i == len(posts) - 1 and skip_last):
            continue
        out.append(abox(name, (p.x - post / 2, p.y - post / 2, z - 0.05),
                        (p.x + post / 2, p.y + post / 2, z + height + 0.12), bev, rz=0.0))
    levels = [height - rail[1] / 2]
    if mid:
        levels.append(height * 0.55)
    if low:
        levels.append(height * 0.18)
    for i in range(len(tops) - 1):
        a, b = tops[i], tops[i + 1]
        for lv in levels:
            out.append(beam(name, a + V((0, 0, lv)), b + V((0, 0, lv)), rail[0], rail[1], bev=rail_bev,
                            ext=post * 0.45))
    return out


def add(lib, root, objs, role, **kw):
    """Join a list of objects (or take one) and register it as a single part."""
    if isinstance(objs, (list, tuple)):
        objs = [o for o in objs if o is not None]
        if not objs:
            return None
        obj = objs[0] if len(objs) == 1 else ls.join(objs, "%s_%s_tmp" % (root.name, role))
    else:
        obj = objs
    return lib.add(root, obj, role, **kw)
