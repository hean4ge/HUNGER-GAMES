"""
style_c_cabin.py - Variant C hunter's cabin (16.8 x 12.8 log footprint incl. the log ends, porch in front).

Rounded saddle-notched logs (1 stud thick, domed end grain), light lime chinking in the grooves, a 38 degree shake
roof whose front slope breaks to 22 degrees over the porch (catslide), vertical board gables, log purlins and ridge
with rounded ends, a fieldstone chimney on the east gable, stone piers, a plank porch with posts, rails and two
steps, a board door (4 x 7.5 opening, open inward) and three four-pane windows.

Texturing = one shared 1024 KIT page (the rule for every building in this style):
  rows 448-1016  tiling trims, full width, U repeats every 8 studs: log band A, log band B, plank band, shake band.
                 Contact occlusion (log-on-log grooves, plank bevels, shake gaps) is painted into the trims.
  x 768-1024, rows 0-440   end-grain discs (4) + swatches (chinking, iron, glass, dark wood)
  x 0-760,    rows 0-440   UNIQUE bake: chimney and pier stones (own UV islands, baked AO + painted stone colours)
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

import style_c_lib as L
import tex_ground as tg

TAU = 2.0 * math.pi
RES = 1024
SPT = 8.0                     # studs per U tile on every trim

# ------------------------------------------------------------------------------------------------ kit layout (px)
BANDS = {"logA": (448, 600), "logB": (608, 760), "plank": (768, 872), "shake": (880, 1016)}
STONE_RECT = (0, 0, 760, 440)
DISCS = [(830, 378), (954, 378), (830, 254), (954, 254)]
DISC_R = 58
SW = {"chink": (772, 140, 1020, 188), "metal": (772, 76, 894, 132), "glass": (900, 76, 1020, 132),
      "dark": (772, 8, 1020, 68)}

# ------------------------------------------------------------------------------------------------ dimensions
R = 0.5
S = 0.96
HX, HY = 7.0, 5.0
EXT = 0.95
Z0 = 1.15
FLOOR = 1.25
N_FB = 10                    # courses on the front / back walls
N_SIDE = 9                   # courses on the gable walls (half-course higher)
ALPHA = math.radians(38.0)
BETA = math.radians(22.0)
TA = math.tan(ALPHA)
TB = math.tan(BETA)
ZR = 14.65                   # roof deck underside at the ridge
TH_D = 0.3                   # deck board thickness
ROOF_X = 8.8                 # gable overhang
Y_KINK = 5.5
Y_PORCH = 9.9
Y_BACK = -6.8
EXP, OVL = 1.0, 0.45         # shake course exposure / overlap
DOOR = (-2.0, 2.0)
DOOR_TOP = 8.75


def zc_fb(i):
    return Z0 + i * S


def zc_side(i):
    return Z0 + S / 2 + i * S


def z_under(y):
    """Roof deck underside above y."""
    if y >= Y_KINK:
        return ZR - Y_KINK * TA - (y - Y_KINK) * TB
    return ZR - abs(y) * TA


def uv_px(x, y):
    return ((x + 0.5) / RES, (y + 0.5) / RES)


def band_v(name, f):
    """f in 0..1 across the band -> V."""
    y0, y1 = BANDS[name]
    return (y0 + 0.5 + f * (y1 - y0 - 1.0)) / RES


# =============================================================================================== mesh builder
class MB:
    """Faces with per-corner UVs and a per-face smooth flag (logs smooth, boards flat)."""

    def __init__(self, name):
        self.name = name
        self.V = []
        self.F = []
        self.UV = []
        self.SM = []
        self.smooth = True

    def v(self, p):
        self.V.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.V) - 1

    def f(self, idx, uvs):
        self.F.append(tuple(idx))
        self.UV.append([(float(u), float(v)) for (u, v) in uvs])
        self.SM.append(self.smooth)

    def build(self):
        import bmesh
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.V, [], self.F)
        uv = me.uv_layers.new(name="UVMap")
        flat = [c for face in self.UV for c in face]
        uv.data.foreach_set("uv", np.array(flat, np.float32).ravel())
        me.polygons.foreach_set("use_smooth", np.array(self.SM, bool))
        me.update()
        bm = bmesh.new()                    # consistent outward normals per closed piece (no welding)
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def cols(x, y, z):
    return np.stack([np.asarray(x, float), np.asarray(y, float), np.asarray(z, float)], axis=1)


AX_XZ = cols((1, 0, 0), (0, 0, 1), (0, -1, 0))        # length X, width Z (height), thickness Y
AX_YZ = cols((0, 1, 0), (0, 0, 1), (1, 0, 0))         # length Y, width Z (height), thickness X


def _frame(axis, ref):
    a = np.asarray(axis, float)
    a /= np.linalg.norm(a)
    down = np.array([0.0, 0.0, -1.0])
    if abs(a @ down) > 0.9:
        down = -np.asarray(ref, float)
    down = down - (down @ a) * a
    down /= np.linalg.norm(down)
    out = np.cross(a, down)
    if out @ np.asarray(ref, float) < 0:
        out = -out
    return a, down, out


def log(mb, p0, p1, r0, r1, ref, band, rng, seg=12, ends=(True, True)):
    """Round log from p0 to p1 with rounded (domed) end grain. theta = 0 points down, pi/2 toward 'ref' (wall
    outward). U = 8 studs per tile along the log, V = theta inside the band; ends map onto an end-grain disc."""
    mb.smooth = True
    p0 = np.asarray(p0, float)
    p1 = np.asarray(p1, float)
    Ln = float(np.linalg.norm(p1 - p0))
    a, down, out = _frame(p1 - p0, ref)
    uoff = rng.uniform(0, SPT)
    bev = min(0.13, Ln * 0.2)
    th = [TAU * k / seg for k in range(seg + 1)]

    def ring(s, r):
        c = p0 + a * s
        return [mb.v(c + r * (math.cos(t) * down + math.sin(t) * out)) for t in th[:-1]]

    rr = lambda s: r0 + (r1 - r0) * s / Ln
    s0 = bev if ends[0] else 0.0
    s1 = Ln - bev if ends[1] else Ln
    A = ring(s0, rr(s0))
    B = ring(s1, rr(s1))
    for k in range(seg):
        k2 = (k + 1) % seg
        u0 = (s0 + uoff) / SPT
        u1 = (s1 + uoff) / SPT
        mb.f((A[k], A[k2], B[k2], B[k]), [(u0, band_v(band, th[k] / TAU)), (u0, band_v(band, th[k + 1] / TAU)),
                                         (u1, band_v(band, th[k + 1] / TAU)), (u1, band_v(band, th[k] / TAU))])
    for side, on in ((0, ends[0]), (1, ends[1])):
        if not on:
            continue
        cx, cy = DISCS[rng.randint(len(DISCS))]
        rot = rng.uniform(0, TAU)
        sgn = -1.0 if side == 0 else 1.0
        s_edge = s0 if side == 0 else s1
        s_cap = 0.0 if side == 0 else Ln
        r_e = rr(s_edge)
        Cring = ring(s_cap - sgn * 0.012, rr(s_cap) * 0.8)
        cen = mb.v(p0 + a * (s_cap + sgn * 0.035))
        Edge = A if side == 0 else B

        def duv(k, rho):
            t = th[k] + rot
            return uv_px(cx + rho * DISC_R * math.cos(t), cy + rho * DISC_R * math.sin(t))
        for k in range(seg):
            k2 = (k + 1) % seg
            if side == 1:
                mb.f((Edge[k], Edge[k2], Cring[k2], Cring[k]), [duv(k, 1.0), duv(k + 1, 1.0), duv(k + 1, 0.8),
                                                                duv(k, 0.8)])
                mb.f((Cring[k], Cring[k2], cen), [duv(k, 0.8), duv(k + 1, 0.8), uv_px(cx, cy)])
            else:
                mb.f((Edge[k2], Edge[k], Cring[k], Cring[k2]), [duv(k + 1, 1.0), duv(k, 1.0), duv(k, 0.8),
                                                                duv(k + 1, 0.8)])
                mb.f((Cring[k2], Cring[k], cen), [duv(k + 1, 0.8), duv(k, 0.8), uv_px(cx, cy)])


def board(mb, c, size, axes, band="plank", rng=None, uoff=None, swatch=None):
    """Box with plank UVs: local x = length (U along), y = width (band across), z = thickness.
    axes = 3x3 (columns = local x, y, z in world). swatch = name of a flat swatch instead of a band."""
    mb.smooth = False
    c = np.asarray(c, float)
    hx, hy, hz = [s / 2.0 for s in size]
    Ax = np.asarray(axes, float)
    uoff = rng.uniform(0, SPT) if (uoff is None and rng is not None) else (uoff or 0.0)
    P = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                P[(sx, sy, sz)] = mb.v(c + Ax @ np.array([sx * hx, sy * hy, sz * hz]))

    def uvp(k, face):
        lx, ly, lz = k[0] * hx, k[1] * hy, k[2] * hz
        if swatch is not None or face == "x":
            x0, y0, x1, y1 = SW[swatch or "dark"]
            if face == "x":
                fx, fy = (ly + hy) / (2 * hy), (lz + hz) / (2 * hz)
            else:
                fx = (lx + hx) / (2 * hx)
                fy = (ly + hy) / (2 * hy) if face == "z" else (lz + hz) / (2 * hz)
            return uv_px(x0 + 3 + fx * (x1 - x0 - 6), y0 + 3 + fy * (y1 - y0 - 6))
        u = (lx + hx + uoff) / SPT
        if face == "z":
            return (u, band_v(band, (ly + hy) / (2 * hy)))
        return (u, band_v(band, 0.1 + 0.8 * (lz + hz) / (2 * hz)))      # long sides: grain across the height

    faces = [
        ("z", [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
        ("z", [(-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)]),
        ("y", [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
        ("y", [(1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)]),
        ("x", [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
        ("x", [(-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)]),
    ]
    for face, corners in faces:
        mb.f([P[k] for k in corners], [uvp(k, face) for k in corners])


def prism(mb, pts8, band="plank", uoff=0.0, length_axis=0, width=1.0):
    """Hexahedron from 8 corner points ordered like board() (-x-y-z, -x-y+z, -x+y-z, ... via index map).
    pts8: dict {(sx, sy, sz): point}; UVs as a plank along local x."""
    mb.smooth = False
    P = {k: mb.v(v) for k, v in pts8.items()}
    L0 = np.linalg.norm(np.asarray(pts8[(1, -1, -1)]) - np.asarray(pts8[(-1, -1, -1)]))

    def uvp(k, face):
        u = ((k[0] + 1) * 0.5 * L0 + uoff) / SPT
        if face == "y":
            return (u, band_v(band, 0.02 if k[1] < 0 else 0.98))
        return (u, band_v(band, (k[1] + 1) * 0.5))
    faces = [
        ("z", [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
        ("z", [(-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)]),
        ("y", [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
        ("y", [(1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)]),
        ("x", [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
        ("x", [(-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)]),
    ]
    for face, corners in faces:
        mb.f([P[k] for k in corners], [uvp(k, face) for k in corners])


AX_X = np.eye(3)
AX_Y = cols((0, 1, 0), (-1, 0, 0), (0, 0, 1))            # local x = world +Y, local y = world -X


def axes_vertical(width_dir):
    """Vertical board: local x = +Z (length), local y = width_dir, local z = cross."""
    x = np.array([0.0, 0.0, 1.0])
    y = np.asarray(width_dir, float)
    y /= np.linalg.norm(y)
    z = np.cross(x, y)
    return np.stack([x, y, z], 1)


def axes_along(length_dir, width_dir):
    x = np.asarray(length_dir, float)
    x /= np.linalg.norm(x)
    y = np.asarray(width_dir, float)
    y = y - (y @ x) * x
    y /= np.linalg.norm(y)
    return np.stack([x, y, np.cross(x, y)], 1)


# =============================================================================================== geometry
def cut(a0, a1, holes):
    out = [(a0, a1)]
    for (c0, c1) in holes:
        nxt = []
        for (lo, hi) in out:
            if c1 <= lo or c0 >= hi:
                nxt.append((lo, hi))
                continue
            if c0 > lo:
                nxt.append((lo, c0))
            if c1 < hi:
                nxt.append((c1, hi))
        out = nxt
    return [(lo, hi) for (lo, hi) in out if hi - lo > 0.3]


# wall openings: (wall, a0, a1, courses removed) - 'a' is x on front/back walls and y on side walls
OPENINGS = {
    "front": [(-2.3, 2.3, range(0, 9)), (3.05, 5.95, (4, 5))],
    "back": [(-5.95, -3.05, (4, 5))],
    "west": [(-1.45, 1.45, (3, 4))],
    "east": [],
}


def build_logs(rng):
    mb = MB("Cabin_Logs")
    walls = {"front": (+1, "x", HY), "back": (-1, "x", -HY), "west": (-1, "y", -HX), "east": (+1, "y", HX)}
    for wall, (sgn, ax, pos) in walls.items():
        n = N_FB if ax == "x" else N_SIDE
        for i in range(n):
            z = zc_fb(i) if ax == "x" else zc_side(i)
            span = (HX + EXT) if ax == "x" else (HY + EXT)
            holes = [(o[0], o[1]) for o in OPENINGS[wall] if i in o[2]]
            for (a0, a1) in cut(-span, span, holes):
                r0 = R * rng.uniform(0.95, 1.04)
                r1 = r0 * rng.uniform(0.96, 1.0)
                if ax == "x":
                    p0, p1, ref = (a0, pos, z), (a1, pos, z), (0, sgn, 0)
                else:
                    p0, p1, ref = (pos, a0, z), (pos, a1, z), (sgn, 0, 0)
                band = "logA" if rng.rand() < 0.55 else "logB"
                log(mb, p0, p1, r0, r1, ref, band, rng)
    # gable boards (vertical) on both side walls
    ztop_side = zc_side(N_SIDE - 1) + R
    for xs in (-1, 1):
        y = -5.45
        while y < 5.45 - 0.2:
            w = min(0.98, 5.45 - y)
            ya, yb = y, y + w - 0.03
            x_in, x_out = xs * 7.05, xs * 7.38
            zb = ztop_side - 0.25
            ztA = z_under(abs(ya)) - 0.03
            ztB = z_under(abs(yb)) - 0.03
            pts = {}
            for sy, yy, zt in ((-1, ya, ztA), (1, yb, ztB)):
                for sz, xx in ((-1, x_in), (1, x_out)):
                    pts[(-1, sy, sz)] = (xx, yy, zb)
                    pts[(1, sy, sz)] = (xx, yy, zt)
            prism(mb, pts, "plank", rng.uniform(0, SPT))
            y += w
    # ridge log and purlins (rounded ends out past the gables; short on the chimney side)
    for (yy, rr) in ((0.0, 0.42), (-3.0, 0.36), (3.0, 0.36)):
        zz = z_under(abs(yy)) - rr + 0.02
        log(mb, (-9.35, yy, zz), (8.9 if yy == 0.0 else 9.35, yy, zz), rr, rr * 0.97, (0, 1, 0), "logB", rng)
    return mb.build()


def build_chinking(rng):
    """Lime chinking: a slab in each wall plane, thick enough (0.72) to show as a light band in the V-groove
    between round logs (logs cover +-0.36 of their centre height at the slab face, courses are 0.96 apart)."""
    mb = MB("Cabin_Chinking")
    th = 0.72
    for wall in ("front", "back", "west", "east"):
        horiz = wall in ("front", "back")
        n = N_FB if horiz else N_SIDE
        z0 = (zc_fb(0) if horiz else zc_side(0)) - 0.1
        z1 = (zc_fb(n - 1) if horiz else zc_side(n - 1)) + 0.1
        a0, a1 = (-HX, HX) if horiz else (-HY, HY)
        pos = {"front": HY, "back": -HY, "west": -HX, "east": HX}[wall]
        pieces = []
        ops = OPENINGS[wall]
        xs = cut(a0, a1, [(o[0], o[1]) for o in ops])
        for (lo, hi) in xs:
            pieces.append((lo, hi, z0, z1))
        for (o0, o1, courses) in ops:
            cz = [(zc_fb(i) if horiz else zc_side(i)) for i in courses]
            zb, zt = min(cz) - R, max(cz) + R
            if zb - z0 > 0.2:
                pieces.append((o0, o1, z0, zb + 0.05))
            if z1 - zt > 0.2:
                pieces.append((o0, o1, zt - 0.05, z1))
        for (lo, hi, zb, zt) in pieces:
            if horiz:
                c, size, axes = ((lo + hi) / 2, pos, (zb + zt) / 2), (hi - lo, zt - zb, th), AX_XZ
            else:
                c, size, axes = (pos, (lo + hi) / 2, (zb + zt) / 2), (hi - lo, zt - zb, th), AX_YZ
            board(mb, c, size, axes, swatch="chink")
    return mb.build()


def slope_frames():
    """(origin(y, z) on the deck TOP line, downslope dir, outward normal, length, x-extent) per roof segment."""
    top_r = ZR + TH_D / math.cos(ALPHA)
    back = ((0.0, top_r), (-math.cos(ALPHA), -math.sin(ALPHA)), (-math.sin(ALPHA), math.cos(ALPHA)),
            -Y_BACK / math.cos(ALPHA))
    front = ((0.0, top_r), (math.cos(ALPHA), -math.sin(ALPHA)), (math.sin(ALPHA), math.cos(ALPHA)),
             Y_KINK / math.cos(ALPHA))
    k_top = (Y_KINK, z_under(Y_KINK) + TH_D / math.cos(BETA))
    porch = (k_top, (math.cos(BETA), -math.sin(BETA)), (math.sin(BETA), math.cos(BETA)),
             (Y_PORCH - Y_KINK) / math.cos(BETA))
    return {"back": back, "front": front, "porch": porch}


def build_roof(rng):
    mb = MB("Cabin_Roof")
    fr = slope_frames()

    def P(seg, t, h, x):
        (oy, oz), (dy, dz), (ny, nz), _ = fr[seg]
        return (x, oy + t * dy + h * ny, oz + t * dz + h * nz)
    for seg, (o, d, n, T) in fr.items():
        # deck boards (underside visible from inside and under the eaves)
        t = 0.0
        while t < T - 0.05:
            w = min(0.98, T - t)
            pts = {}
            for sx, xx in ((-1, -ROOF_X), (1, ROOF_X)):
                for sy, tt in ((-1, t), (1, t + w - 0.02)):
                    for sz, hh in ((-1, -TH_D), (1, 0.0)):
                        pts[(sx, sy, sz)] = P(seg, tt, hh, xx)
            prism(mb, pts, "plank", rng.uniform(0, SPT))
            t += w
        # shake courses (wedges: thin top 0.07 -> thick butt 0.24), laid from the eave up to the ridge
        mb.smooth = False
        b = T + 0.08
        while b > 0.15:
            top = max(0.0, b - EXP - OVL)
            y0, y1 = BANDS["shake"]
            vb = (y0 + 0.5) / RES
            vbt = (y0 + 0.5 + 0.08 * (y1 - y0 - 1)) / RES
            vt = (y0 + 0.5 + (y1 - y0 - 1) * min(1.0, 0.08 + 0.92 * (b - top) / (EXP + OVL))) / RES
            uo = rng.uniform(0, SPT)
            ids = {}
            for sx, xx in ((-1, -ROOF_X - 0.05), (1, ROOF_X + 0.05)):
                ids[(sx, "tb")] = mb.v(P(seg, top, 0.0, xx))
                ids[(sx, "bb")] = mb.v(P(seg, b, 0.0, xx))
                ids[(sx, "bt")] = mb.v(P(seg, b, 0.24, xx))
                ids[(sx, "tt")] = mb.v(P(seg, top, 0.07, xx))
            u0 = (-ROOF_X + uo) / SPT
            u1 = (ROOF_X + uo) / SPT
            # top (exposed shake face): butt edge -> v near the band bottom
            mb.f((ids[(-1, "bt")], ids[(1, "bt")], ids[(1, "tt")], ids[(-1, "tt")]),
                 [(u0, vbt), (u1, vbt), (u1, vt), (u0, vt)])
            # butt face
            mb.f((ids[(-1, "bb")], ids[(1, "bb")], ids[(1, "bt")], ids[(-1, "bt")]),
                 [(u0, vb), (u1, vb), (u1, vbt), (u0, vbt)])
            # bottom (on the deck, hidden)
            mb.f((ids[(-1, "tb")], ids[(1, "tb")], ids[(1, "bb")], ids[(-1, "bb")]),
                 [(u0, vt), (u1, vt), (u1, vt), (u0, vt)])
            # upslope end (hidden)
            mb.f((ids[(-1, "tt")], ids[(1, "tt")], ids[(1, "tb")], ids[(-1, "tb")]),
                 [(u0, vt), (u1, vt), (u1, vt), (u0, vt)])
            # gable ends
            for sx in (-1, 1):
                q = [ids[(sx, "tb")], ids[(sx, "bb")], ids[(sx, "bt")], ids[(sx, "tt")]]
                uvq = [(0.01, vt), (0.01, vb), (0.01, vbt), (0.01, vt)]
                if sx > 0:
                    q, uvq = q[::-1], uvq[::-1]
                mb.f(q, uvq)
            b -= EXP
        # verge (barge) boards along both gable edges
        for xs in (-1, 1):
            pts = {}
            for sx, tt in ((-1, 0.0), (1, T + 0.08)):
                for sy, hh in ((-1, -TH_D - 0.25), (1, 0.28)):
                    for sz, xx in ((-1, xs * (ROOF_X + 0.06)), (1, xs * (ROOF_X + 0.3))):
                        pts[(sx, sy, sz)] = P(seg, tt, hh, xx)
            if xs < 0:
                pts = {(k[0], k[1], -k[2]): v for k, v in pts.items()}
            prism(mb, pts, "plank", rng.uniform(0, SPT))
    # ridge cap log on top of the courses
    zr = ZR + TH_D / math.cos(ALPHA) + 0.2
    log(mb, (-ROOF_X - 0.15, 0.0, zr), (ROOF_X + 0.15, 0.0, zr), 0.3, 0.29, (0, 1, 0), "logB", rng)
    return mb.build()


def build_porch(rng):
    mb = MB("Cabin_Porch")
    x = -7.6
    while x < 7.6 - 0.2:
        w = min(0.95, 7.6 - x)
        c = (x + w / 2, (5.42 + Y_PORCH) / 2, FLOOR - 0.14)
        board(mb, c, (Y_PORCH - 5.42, w - 0.03, 0.28), AX_Y, "plank", rng)
        x += w
    for yy in (5.8, 7.8, 9.6):
        log(mb, (-7.9, yy, 0.72), (7.9, yy, 0.72), 0.36, 0.35, (0, 1, 0), "logA", rng)
    for (y0, y1, ztop) in ((Y_PORCH - 0.05, Y_PORCH + 0.95, 0.86), (Y_PORCH + 0.95, Y_PORCH + 1.95, 0.46)):
        c = (0.0, (y0 + y1) / 2, ztop / 2 - 0.1)
        board(mb, c, (4.6, y1 - y0, ztop + 0.2), AX_X, "plank", rng)
    return mb.build()


def build_posts(rng):
    mb = MB("Cabin_Posts")
    yb = 9.3
    for xx in (-7.25, -2.55, 2.55, 7.25):
        log(mb, (xx, yb, FLOOR - 0.05), (xx, yb, 8.12), 0.3, 0.28, (0, 1, 0), "logA", rng, seg=10)
    log(mb, (-8.3, yb, 8.43), (8.3, yb, 8.43), 0.38, 0.37, (0, 1, 0), "logA", rng)
    for (xa, xb) in ((-7.25, -2.55), (2.55, 7.25)):
        for zz, rr in ((FLOOR + 3.1, 0.16), (FLOOR + 0.55, 0.13)):
            log(mb, (xa, yb, zz), (xb, yb, zz), rr, rr, (0, 1, 0), "logB", rng, seg=8)
        for k in range(1, 5):
            xx = xa + (xb - xa) * k / 5.0
            log(mb, (xx, yb, FLOOR + 0.5), (xx, yb, FLOOR + 3.15), 0.09, 0.09, (0, 1, 0), "logB", rng, seg=8,
                ends=(False, False))
    return mb.build()


def build_floor(rng):
    mb = MB("Cabin_Floor")
    y = -4.55
    while y < 4.55 - 0.2:
        w = min(0.95, 4.55 - y)
        board(mb, (0.0, y + w / 2, FLOOR - 0.13), (13.1, w - 0.03, 0.26), AX_X, "plank", rng)
        y += w
    board(mb, (0.0, HY, FLOOR - 0.15), (4.0, 1.1, 0.3), AX_X, "plank", rng)      # threshold
    return mb.build()


def build_trim(rng):
    """Door jambs + header, door leaf (open 75 deg inward), window frames + mullions, west shutter, iron."""
    mb = MB("Cabin_Trim")
    vert_x = axes_vertical((1, 0, 0))
    vert_y = axes_vertical((0, 1, 0))
    for xx in (-2.15, 2.15):
        board(mb, (xx, HY, (FLOOR + 9.29) / 2), (9.29 - FLOOR, 0.3, 1.12), vert_x, "plank", rng)
    board(mb, (0.0, HY, (DOOR_TOP + 9.29) / 2), (4.0, 9.29 - DOOR_TOP, 1.12), AX_XZ, "plank", rng)
    # door leaf, built closed in the hinge frame then rotated about the hinge
    hinge = np.array([DOOR[0] + 0.05, HY - 0.42, 0.0])
    ang = math.radians(-75.0)
    Rz = np.array([[math.cos(ang), -math.sin(ang), 0], [math.sin(ang), math.cos(ang), 0], [0, 0, 1]])

    def door_board(c_local, size, axes, band="plank", swatch=None):
        c = hinge + Rz @ np.asarray(c_local, float)
        board(mb, c, size, Rz @ axes, band, rng, swatch=swatch)
    h0, h1 = FLOOR + 0.04, DOOR_TOP - 0.04
    for k in range(4):
        door_board((0.5 + k * 0.99, 0.0, (h0 + h1) / 2), (h1 - h0, 0.96, 0.18), vert_x)
    for zz in (h0 + 1.2, h1 - 1.2):
        door_board((2.0, -0.14, zz), (3.6, 0.5, 0.1), AX_XZ)
    dz = (h1 - 1.2) - (h0 + 1.2)
    ln = math.hypot(3.2, dz)
    dvec = np.array([3.2, 0.0, dz]) / ln
    door_board((2.0, -0.14, (h0 + h1) / 2), (ln - 0.3, 0.42, 0.09),
               axes_along(dvec, np.cross(np.array([0, 1.0, 0]), dvec)))
    for zz in (h0 + 1.1, h1 - 1.1):
        door_board((0.95, 0.105, zz), (1.7, 0.16, 0.03), AX_XZ, swatch="metal")
    door_board((3.55, 0.12, (h0 + h1) / 2 - 0.4), (0.1, 0.42, 0.08), vert_x, swatch="metal")
    # windows: frame boards in the log cut, sill, head, 4-pane mullions
    wins = [("x", HY, 3.05, 5.95, zc_fb(3) + R, zc_fb(6) - R, 1),
            ("x", -HY, -5.95, -3.05, zc_fb(3) + R, zc_fb(6) - R, -1),
            ("y", -HX, -1.45, 1.45, zc_side(2) + R, zc_side(5) - R, -1)]
    glass = []
    for (ax, pos, a0, a1, zb, zt, sgn) in wins:
        def B(cx, cz, la, lz, depth, sw=None, out_off=0.0):
            if ax == "x":
                board(mb, (cx, pos + sgn * out_off, cz), (la, lz, depth), AX_XZ, "plank", rng, swatch=sw)
            else:
                board(mb, (pos + sgn * out_off, cx, cz), (la, lz, depth), AX_YZ, "plank", rng, swatch=sw)
        B(a0 + 0.15, (zb + zt) / 2, 0.3, zt - zb, 1.12)
        B(a1 - 0.15, (zb + zt) / 2, 0.3, zt - zb, 1.12)
        B((a0 + a1) / 2, zt - 0.13, a1 - a0, 0.26, 1.12)
        B((a0 + a1) / 2, zb + 0.12, a1 - a0 + 0.35, 0.24, 1.36, out_off=0.12)
        B((a0 + a1) / 2, (zb + zt) / 2, 0.1, zt - zb - 0.5, 0.16, sw="dark")
        B((a0 + a1) / 2, (zb + zt) / 2, a1 - a0 - 0.6, 0.1, 0.16, sw="dark")
        glass.append((ax, pos, a0 + 0.3, a1 - 0.3, zb + 0.24, zt - 0.26))
    # west shutter, swung open flat against the wall
    for k in range(2):
        board(mb, (-HX - 0.62, 1.75 + k * 0.62, (zc_side(2) + zc_side(5)) / 2), (2.1, 0.6, 0.14), vert_y, "plank",
              rng)
    return mb.build(), glass


def build_glass(glass):
    mb = MB("Cabin_Glass")
    for (ax, pos, a0, a1, zb, zt) in glass:
        if ax == "x":
            board(mb, ((a0 + a1) / 2, pos, (zb + zt) / 2), (a1 - a0, zt - zb, 0.06), AX_XZ, swatch="glass")
        else:
            board(mb, (pos, (a0 + a1) / 2, (zb + zt) / 2), (a1 - a0, zt - zb, 0.06), AX_YZ, swatch="glass")
    return mb.build()


# ------------------------------------------------------------------------------------------------ stones (SDF)
def stone_layout(rng):
    """Rounded fieldstones: (centre, half extents, rotation, rounding) for the chimney shell and the piers."""
    stones = []

    def course_face(x0, x1, z0, z1, place, depth=0.42, hmin=0.5, hmax=0.78, lmin=0.5, lmax=1.4):
        """Fieldstone courses: every stone gets its own height, length, rounding and a little drift."""
        z = z0
        while z < z1 - 0.15:
            hgt = min(rng.uniform(hmin, hmax), z1 - z)
            x = x0 - rng.uniform(0, 0.5)
            while x < x1:
                ln = rng.uniform(lmin, lmax)
                a, b = max(x, x0), min(x + ln, x1)
                if b - a > 0.22:
                    hs = hgt * rng.uniform(0.7, 1.0)
                    ca = (a + b) / 2 + rng.uniform(-0.04, 0.04)
                    cz = z + hgt / 2 + rng.uniform(-0.5, 0.5) * (hgt - hs)
                    half = np.array([(b - a) / 2 - 0.05, depth / 2 + rng.uniform(-0.05, 0.07), hs / 2 - 0.035])
                    stones.append(place(ca, cz, half, rng.uniform(-0.09, 0.09)))
                x += ln
            z += hgt

    def rot(axis_deg_z, tilt):
        return (Matrix.Rotation(axis_deg_z + rng.uniform(-0.06, 0.06), 3, "Z") @ Matrix.Rotation(tilt, 3, "X")
                @ Matrix.Rotation(rng.uniform(-0.05, 0.05), 3, "Y"))
    # firebox block: x 7.45..10.25, y -2..2, z -0.3..6.0 ; stack: x 8.95..10.7, y -0.95..0.95, z 6..17.6
    FB = (7.45, 10.25, -2.05, 2.05, -0.35, 6.0)
    ST = (8.95, 10.7, -0.95, 0.95, 6.0, 17.6)
    for (xa, xb, ya, yb, za, zb), faces in ((FB, ("px", "py", "ny", "top")), (ST, ("px", "py", "ny", "nx"))):
        def mk(face):
            if face == "px":
                return lambda a, cz, half, tl: ((xb - half[1] + 0.06, a, cz), (half[0], half[1], half[2]),
                                                np.array(rot(math.pi / 2, tl)))
            if face == "nx":
                return lambda a, cz, half, tl: ((xa + half[1] - 0.06, a, cz), (half[0], half[1], half[2]),
                                                np.array(rot(math.pi / 2, tl)))
            if face == "py":
                return lambda a, cz, half, tl: ((a, yb - half[1] + 0.06, cz), (half[0], half[1], half[2]),
                                                np.array(rot(0.0, tl)))
            return lambda a, cz, half, tl: ((a, ya + half[1] - 0.06, cz), (half[0], half[1], half[2]),
                                            np.array(rot(0.0, tl)))
        for face in faces:
            if face == "top":
                continue
            z_from = za if (xa, xb) == FB[:2] else (za if face != "nx" else 12.6)
            if face in ("px", "nx"):
                course_face(ya, yb, z_from, zb, mk(face))
            else:
                course_face(xa, xb, z_from, zb, mk(face))
    # firebox shoulder (sloped cap stones) + chimney cap
    for k in range(5):
        y = -1.9 + k * 0.95
        stones.append(((9.75, y, 6.15), (0.62, 0.42, 0.22), np.array(Matrix.Rotation(-0.35, 3, "Y"))))
    stones.append(((9.82, 0.0, 17.7), (1.02, 1.1, 0.16), np.eye(3)))
    # piers under the walls, the gable-wall middles and the porch sills
    piers = [(-7, -5, 0.68), (7, -5, 0.68), (-7, 5, 0.68), (7, 5, 0.68), (0, -5, 0.68), (0, 5, 0.68),
             (-3.6, 5, 0.68), (3.6, 5, 0.68), (-3.6, -5, 0.68), (3.6, -5, 0.68), (-7, 0, 1.14),
             (-7, -2.6, 1.14), (-7, 2.6, 1.14), (-7.4, 7.8, 0.4), (7.4, 7.8, 0.4), (-7.4, 9.6, 0.4),
             (7.4, 9.6, 0.4), (0, 7.8, 0.4), (0, 9.6, 0.4)]
    for (x, y, top) in piers:
        hz = (top + 0.3) / 2
        stones.append(((x + rng.uniform(-0.1, 0.1), y + rng.uniform(-0.1, 0.1), top - hz),
                       (rng.uniform(0.55, 0.68), rng.uniform(0.5, 0.64), hz), np.array(rot(rng.uniform(0, 1), 0))))
    cores = [((8.85, 0.0, 2.8), (1.32, 1.95, 3.25)), ((9.82, 0.0, 11.8), (0.78, 0.86, 5.85))]
    stones = [(c, h, Rm, min(rng.uniform(0.08, 0.19), 0.7 * min(h))) for (c, h, Rm) in stones]
    return stones, cores


def build_stones(rng):
    stones, cores = stone_layout(rng)
    sdf = L.SDF(block=2.0)
    for (c, half) in cores:
        sdf.round_box(c, half, 0.1, k=0.0)
    for (c, half, Rm, rad) in stones:
        sdf.round_box(c, np.asarray(half), rad, rot=Rm, k=0.04)
    sdf.round_box((9.82, 0.0, 17.75), (0.42, 0.45, 0.6), 0.08, k=0.04, op="subtract")
    sdf.displace(0.022, 1.4, 2, seed=91)
    chim = L.sdf_mesh("Cabin_StoneChimney", sdf, (7.0, -2.6, -0.6), (11.3, 2.6, 18.2), 0.065, target_tris=3800)
    sdf2 = L.SDF(block=2.0)
    for (c, half, Rm, rad) in stones:
        if c[2] < 1.2 and (c[0] < 7.2 or abs(c[1]) > 2.3):
            sdf2.round_box(c, np.asarray(half), max(rad, 0.14), rot=Rm, k=0.0)
    sdf2.displace(0.02, 1.4, 2, seed=92)
    piers = L.sdf_mesh("Cabin_StonePiers", sdf2, (-8.4, -6.0, -0.5), (8.4, 10.6, 1.6), 0.07, target_tris=1600)
    import bmesh
    bm = bmesh.new()
    for o in (chim, piers):
        bm.from_mesh(o.data)
    me = bpy.data.meshes.new("Cabin_Stone")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Cabin_Stone", me)
    bpy.context.scene.collection.objects.link(obj)
    for o in (chim, piers):
        bpy.data.objects.remove(o, do_unlink=True)
    L.smooth_shade(obj)
    return obj, stones


def det_stone(nt, co):
    n = nt.noise(co, 2.4, 3.0, 0.5)
    v = nt.voronoi(co, 1.6, "F1", "EUCLIDEAN", 1.0, "Distance")
    pit = nt.maprange(v, 0.0, 0.45, 0.0, 1.0, interp="SMOOTHSTEP")
    h = nt.math("MULTIPLY_ADD", n, 0.6, nt.math("MULTIPLY", pit, 0.4))
    return h, nt.noise(co, 0.4, 2.0, 0.5), 0.28, 0.06


# =============================================================================================== kit painting
def aniso_noise(rng, h, w, fu_max, fv_lo, fv_hi, beta=1.0):
    """Periodic h x w field: low frequencies along U (<= fu_max cycles/tile), fv_lo..fv_hi cycles along V."""
    fy = (np.fft.fftfreq(h) * h)[:, None]
    fx = (np.fft.fftfreq(w) * w)[None, :]
    win = (np.abs(fx) <= fu_max) * tg.smoothstep(fv_lo * 0.6, fv_lo, np.abs(fy)) * \
        (1 - tg.smoothstep(fv_hi, fv_hi * 1.4, np.abs(fy)))
    k = np.sqrt(fx ** 2 + fy ** 2)
    k[0, 0] = 1
    amp = win * k ** (-beta)
    amp[0, 0] = 0
    f = np.fft.ifft2(amp * np.exp(1j * rng.uniform(0, TAU, (h, w)))).real
    return (f - f.mean()) / (f.std() + 1e-9)


def wrapdist(a, b, period):
    d = np.abs(a - b) % period
    return np.minimum(d, period - d)


def paint_log_band(rng, h, w, hue):
    """Log side: theta = 0 at the bottom of the log, pi/2 toward the wall's outside, pi on top."""
    V = (np.arange(h) + 0.5)[:, None] / h * TAU * np.ones((1, w))
    U = (np.arange(w) + 0.5)[None, :] / w * SPT * np.ones((h, 1))       # studs along the log
    up = -np.cos(V)
    g1 = aniso_noise(rng, h, w, 6, 10, 40)
    g2 = aniso_noise(rng, h, w, 2, 2, 6)
    low = L.periodic_noise(rng, h, w, 1, 4)
    weather = np.clip(0.55 + 0.32 * up + 0.18 * low + 0.06 * g2, 0, 1)
    warm = np.array(hue[0]) / 255.0
    silver = np.array(hue[1]) / 255.0
    col = warm[None, None] + (silver - warm)[None, None] * weather[..., None]
    col *= (1.0 + 0.05 * g1 + 0.04 * g2)[..., None]
    # contact occlusion where the log disappears behind the chinking / its neighbours
    occ = np.ones((h, w))
    for c in (46, 134, 226, 314):                 # where the log meets the chinking face (sin = 0.72)
        dd = np.degrees(np.abs(((V - math.radians(c)) + math.pi) % TAU - math.pi))
        occ -= 0.4 * np.exp(-(dd / 12.0) ** 2)
    hidden = (np.degrees(V) < 38) | ((np.degrees(V) > 142) & (np.degrees(V) < 218)) | (np.degrees(V) > 322)
    occ = np.where(hidden, np.minimum(occ, 0.55), occ)
    under = 0.86 + 0.14 * np.clip(up * 0.5 + 0.5, 0, 1)
    col *= (occ * under)[..., None]
    hgt = 0.012 * g1 + 0.006 * g2
    # knots: soft dark ovals with a lighter rim on the visible faces
    for _ in range(4):
        u0 = rng.uniform(0, SPT)
        v0 = math.radians(rng.choice([rng.uniform(55, 125), rng.uniform(235, 305)]))
        du = wrapdist(U, u0, SPT) / 0.16
        dv = np.abs(V - v0) / 0.13
        rr = np.sqrt(du ** 2 + dv ** 2)
        core = L.ss(1.0, 0.45, rr)
        rim = L.ss(1.7, 1.1, rr) * (1 - core)
        col = col * (1 - 0.45 * core)[..., None] + (0.06 * rim)[..., None]
        hgt += 0.012 * core - 0.004 * rim
    # drying checks: long thin cracks along the log
    for _ in range(2):
        v0 = math.radians(rng.choice([rng.uniform(70, 120), rng.uniform(245, 295)]))
        u0 = rng.uniform(0, SPT)
        ln = rng.uniform(1.6, 3.6)
        t = ((U - u0) % SPT) / ln
        along = np.where(t < 1.0, np.sin(np.clip(t, 0, 1) * math.pi) ** 0.5, 0.0)
        wv = np.abs(V - v0 - 0.02 * np.sin(U * 2.3)) / math.radians(1.6)
        crack = L.ss(1.0, 0.0, wv) * along
        col *= (1 - 0.55 * crack)[..., None]
        hgt -= 0.03 * crack
    return np.clip(col, 0, 1), hgt, 0.86 - 0.05 * up * 0.5 + 0.02 * g2


def paint_plank_band(rng, h, w):
    V = (np.arange(h) + 0.5)[:, None] / h * np.ones((1, w))              # 0..1 across one 0.95 board
    U = (np.arange(w) + 0.5)[None, :] / w * SPT * np.ones((h, 1))
    g1 = aniso_noise(rng, h, w, 8, 8, 30)
    low = L.periodic_noise(rng, h, w, 1, 5)
    base = np.array([142, 112, 82]) / 255.0
    silver = np.array([150, 140, 124]) / 255.0
    wt = np.clip(0.45 + 0.25 * low, 0, 1)
    col = base + (silver - base) * wt[..., None]
    col *= (1 + 0.06 * g1)[..., None]
    edge = np.minimum(V, 1 - V)
    bevel = L.ss(0.0, 0.08, edge)
    col *= (0.72 + 0.28 * bevel)[..., None]
    hgt = 0.02 * bevel + 0.008 * g1
    for uj in (0.0, 4.0):           # butt joints every 4 studs (with nails)
        dj = wrapdist(U, uj, SPT)
        gap = L.ss(0.025, 0.0, dj)
        col *= (1 - 0.6 * gap)[..., None]
        hgt -= 0.03 * gap
        for side in (-1, 1):
            for vv in (0.25, 0.75):
                dn = np.sqrt((wrapdist(U, (uj + side * 0.1) % SPT, SPT) / 0.035) ** 2 + ((V - vv) / 0.04) ** 2)
                nail = L.ss(1.0, 0.5, dn)
                col = col * (1 - 0.6 * nail)[..., None]
                hgt += 0.004 * nail
    return np.clip(col, 0, 1), hgt, 0.84 - 0.04 * bevel + 0.02 * g1


def paint_shake_band(rng, h, w):
    V = (np.arange(h) + 0.5)[:, None] / h * np.ones((1, w))              # 0 = butt end, 1 = hidden top
    U = (np.arange(w) + 0.5)[None, :] / w * SPT * np.ones((h, 1))
    edges = [0.0]
    while True:
        nxt = edges[-1] + rng.uniform(0.55, 1.25)
        if nxt > SPT - 0.4:
            break
        edges.append(nxt)
    edges = np.array(edges)
    idx = np.searchsorted(edges, U[0], side="right") - 1
    tone = rng.uniform(-1, 1, len(edges))
    mossy = rng.rand(len(edges)) < 0.18
    t = tone[idx][None, :] * np.ones((h, 1))
    ms = mossy[idx][None, :] * np.ones((h, 1))
    left = edges[idx]
    right = np.append(edges[1:], SPT)[idx]
    du = np.minimum(U[0] - left, right - U[0])[None, :] * np.ones((h, 1))
    g1 = L.periodic_noise(rng, h, w, 20, 80)
    streak = aniso_noise(rng, h, w, 40, 0.5, 3)
    base = np.array([116, 104, 92]) / 255.0
    col = base * (1 + 0.1 * t + 0.05 * streak + 0.02 * g1)[..., None]
    col = L.mixc(col, np.array([98, 106, 76]) / 255.0, ms * L.ss(0.5, 0.1, V) * 0.55)
    gap = L.ss(0.035, 0.0, du)
    col *= (1 - 0.65 * gap)[..., None]
    butt = V < 0.08
    col = np.where(butt[..., None], col * 0.72, col)
    lit = 1.0 - 0.16 * L.ss(0.55, 0.95, V)       # the next course shades the upper part
    col *= lit[..., None]
    col *= (0.88 + 0.12 * L.ss(0.08, 0.2, V))[..., None]
    hgt = 0.02 * L.ss(0.0, 0.06, du) - 0.03 * gap + 0.008 * streak + 0.015 * (1 - V)
    return np.clip(col, 0, 1), hgt, 0.88 + 0.03 * gap - 0.02 * t


def paint_disc(rng, size):
    yy, xx = np.mgrid[0:size, 0:size].astype(float) + 0.5
    cx, cy = size / 2 + rng.uniform(-4, 4), size / 2 + rng.uniform(-4, 4)
    rr = np.hypot(xx - cx, yy - cy) / DISC_R
    ph = np.arctan2(yy - cy, xx - cx)
    wob = 0.04 * np.sin(ph * 3 + rng.uniform(0, 6)) + 0.03 * np.sin(ph * 7 + rng.uniform(0, 6))
    rings = 0.5 + 0.5 * np.sin((rr + wob) * TAU * rng.uniform(6.5, 9.0))
    inner = np.array([176, 144, 106]) / 255.0
    outer = np.array([150, 120, 90]) / 255.0
    col = inner + (outer - inner) * np.clip(rr, 0, 1)[..., None]
    col *= (1 - 0.08 * rings)[..., None]
    rim = L.ss(0.8, 0.9, rr)
    col = L.mixc(col, np.array([104, 88, 72]) / 255.0, rim)
    hgt = 0.02 * (1 - np.clip(rr, 0, 1) ** 2) - 0.004 * rings - 0.03 * rim
    for _ in range(rng.randint(1, 4)):
        a0 = rng.uniform(-math.pi, math.pi)
        da = np.abs(((ph - a0) + math.pi) % TAU - math.pi) * np.maximum(rr, 0.05) * DISC_R
        crack = L.ss(1.6, 0.3, da) * L.ss(0.08, 0.2, rr) * L.ss(0.86, 0.6, rr)
        col *= (1 - 0.6 * crack)[..., None]
        hgt -= 0.03 * crack
    pith = L.ss(0.06, 0.0, np.hypot(xx - cx, yy - cy) / DISC_R)
    col *= (1 - 0.3 * pith)[..., None]
    return np.clip(col, 0, 1), hgt, 0.86 + 0.04 * rim


def normal_from_height_aniso(hgt, px_u, px_v, wrap_u=True):
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5 * px_u
    dy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5 * px_v
    n = np.stack([-dx, -dy, np.ones_like(hgt)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def paint_kit(rng, col, nrm, rough):
    """Fill the trim bands, discs and swatches of the kit page (arrays are row 0 = V 0)."""
    flat = np.array([0.5, 0.5, 1.0])
    for name, (y0, y1) in BANDS.items():
        h = y1 - y0
        if name == "logA":
            c, hg, r = paint_log_band(rng, h, RES, ((136, 104, 76), (160, 148, 130)))
            pv = h / (TAU * R)
        elif name == "logB":
            c, hg, r = paint_log_band(rng, h, RES, ((126, 96, 72), (150, 136, 118)))
            pv = h / (TAU * R)
        elif name == "plank":
            c, hg, r = paint_plank_band(rng, h, RES)
            pv = h / 0.95
        else:
            c, hg, r = paint_shake_band(rng, h, RES)
            pv = h / (EXP + OVL)
        n = normal_from_height_aniso(hg, RES / SPT, pv)
        col[y0:y1] = c
        nrm[y0:y1] = n * 0.5 + 0.5
        rough[y0:y1] = r
        for k in range(1, 9):               # edge extension into the padding rows (mip bleed)
            if y0 - k >= 0:
                col[y0 - k], nrm[y0 - k], rough[y0 - k] = col[y0], nrm[y0], rough[y0]
            if y1 - 1 + k < RES:
                col[y1 - 1 + k], nrm[y1 - 1 + k], rough[y1 - 1 + k] = col[y1 - 1], nrm[y1 - 1], rough[y1 - 1]
    size = 124
    for (cx, cy) in DISCS:
        c, hg, r = paint_disc(rng, size)
        n = normal_from_height_aniso(hg, DISC_R * 2.0, DISC_R * 2.0)
        x0, y0 = cx - size // 2, cy - size // 2
        col[y0:y0 + size, x0:x0 + size] = c
        nrm[y0:y0 + size, x0:x0 + size] = n * 0.5 + 0.5
        rough[y0:y0 + size, x0:x0 + size] = r
    sw_col = {"chink": (192, 184, 166), "metal": (64, 60, 56), "glass": (84, 102, 112), "dark": (92, 70, 52)}
    sw_r = {"chink": 0.93, "metal": 0.6, "glass": 0.1, "dark": 0.84}
    for name, (x0, y0, x1, y1) in SW.items():
        hh, ww = y1 - y0, x1 - x0
        nz = L.periodic_noise(rng, max(hh, ww), max(hh, ww), 2, 8)[:hh, :ww]
        c = np.array(sw_col[name]) / 255.0 * (1 + 0.04 * nz)[..., None]
        if name == "glass":
            c = c * (0.8 + 0.4 * np.linspace(0, 1, hh)[:, None, None])
        col[y0:y1, x0:x1] = c
        nrm[y0:y1, x0:x1] = flat
        rough[y0:y1, x0:x1] = sw_r[name] + 0.02 * nz


def paint_stones(d, stones, rng):
    cov = d["cover"]
    P = d["pos"][cov]
    N = d["nrm"][cov]
    det = d["det"][cov]
    ao1 = np.clip(d["ao1"][cov], 0, 1)
    ao2 = np.clip(d["ao2"][cov], 0, 1)
    best = np.full(len(P), 1e9)
    sid = np.full(len(P), -1)
    for i, (c, half, Rm, rad) in enumerate(stones):
        c = np.asarray(c)
        ext = np.abs(Rm) @ np.asarray(half) + 0.2
        m = np.all(np.abs(P - c) <= ext, axis=1)
        if not m.any():
            continue
        dd = L.sd_round_box((P[m] - c) @ Rm, np.asarray(half), rad)
        idx = np.nonzero(m)[0]
        better = dd < best[idx]
        best[idx[better]] = dd[better]
        sid[idx[better]] = i
    pal = np.array([(128, 124, 116), (146, 136, 118), (112, 102, 92), (92, 90, 88), (156, 148, 134),
                    (124, 110, 94), (136, 132, 126), (104, 96, 84)], float) / 255.0
    pick = rng.randint(len(pal), size=len(stones) + 1)
    jit = rng.uniform(0.88, 1.08, len(stones) + 1)
    col = pal[pick[sid]] * jit[sid][:, None]
    mortar = best > 0.045
    col = np.where(mortar[:, None], np.array([116, 108, 96]) / 255.0, col)
    g = det[:, 0]
    col *= (0.92 + 0.1 * g + 0.08 * np.clip(N[:, 2], -1, 1))[:, None]
    soot = L.ss(16.2, 17.8, P[:, 2]) * L.ss(7.5, 9.5, P[:, 0])
    col = L.mixc(col, np.array([52, 48, 46]) / 255.0, soot * 0.7)
    moss = L.ss(0.6, 0.0, P[:, 2]) * L.ss(0.2, 0.8, N[:, 2] + 0.3)
    col = L.mixc(col, np.array([84, 96, 52]) / 255.0, moss * 0.5)
    lin = L.srgb2lin(col) * ((0.42 + 0.58 * ao1 ** 1.2) * (0.7 + 0.3 * ao2))[:, None]
    rough = np.where(mortar, 0.93, 0.85) + 0.03 * (1 - g)
    return L.lin2srgb(lin), rough


# =============================================================================================== driver hook
def build_cabin(lib, D):
    """D = the style_c driver module (write_page, export_material, PREFIX, TEX, GLB_ONLY, Lib.add_asset)."""
    import time
    t0 = time.time()
    rng = np.random.RandomState(31)
    logs = build_logs(rng)
    chink = build_chinking(rng)
    roof = build_roof(rng)
    porch = build_porch(rng)
    posts = build_posts(rng)
    floor = build_floor(rng)
    trim, glass_spec = build_trim(rng)
    glass = build_glass(glass_spec)
    stone, stones = build_stones(rng)
    # logs are smooth-shaded, boards / courses flat (per-face flags set by MB); stones smooth.
    # unique stone islands inside the stone rectangle of the kit page
    x0, y0, x1, y1 = STONE_RECT
    L.unwrap_page([stone], angle=80.0, margin=0.003, rect=(x0 / RES + 0.004, y0 / RES + 0.004, x1 / RES - 0.004,
                                                           y1 / RES - 0.004))
    L.triangulate(stone)
    lo, hi = L.bounds([stone])
    bk = L.Baker([(stone, det_stone)], RES, lo, hi)
    data = bk.run(0.35, 1.6, ao_samples=64)
    bk.cleanup()
    s_col, s_rough = paint_stones(data, stones, rng)
    col = np.zeros((RES, RES, 3))
    nrm = np.zeros((RES, RES, 3))
    nrm[...] = (0.5, 0.5, 1.0)
    rough = np.full((RES, RES), 0.86)
    paint_kit(rng, col, nrm, rough)
    cov = data["cover"]
    region = np.zeros((RES, RES), bool)
    region[y0:y1, x0:x1] = True
    sc = np.zeros((RES, RES, 3))
    sc[cov] = s_col
    sr = np.zeros((RES, RES))
    sr[cov] = s_rough
    sub = (slice(y0, y1), slice(x0, x1))
    col[sub] = L.fill_uncovered(sc[sub], cov[sub])
    nrm[sub] = L.fill_uncovered(data["tnrm"][sub], cov[sub])
    rough[sub] = L.fill_uncovered(sr[sub][..., None], cov[sub])[..., 0]
    full = np.ones((RES, RES), bool)
    page = "%s_CabinKit" % D.PREFIX
    files = D.write_page(page, col, nrm, rough, full)
    import os
    mat = D.export_material(page, os.path.join(D.TEX, files["color"]), os.path.join(D.TEX, files["normal"]),
                            os.path.join(D.GLB_ONLY, files["mr"]))
    parts = [
        (logs, "Logs", dict(collide=True, collision="PreciseConvexDecomposition")),
        (chink, "Chinking", dict(collide=False, castShadow=False)),
        (roof, "Roof", dict(collide=True, collision="PreciseConvexDecomposition")),
        (porch, "Porch", dict(collide=True, collision="PreciseConvexDecomposition", tags=["Floor"])),
        (posts, "Posts", dict(collide=True, collision="PreciseConvexDecomposition")),
        (floor, "Floor", dict(collide=True, collision="Box", tags=["Floor"])),
        (trim, "Trim", dict(collide=False)),
        (glass, "Glass", dict(collide=True, collision="Box", transparency=0.35, castShadow=False)),
        (stone, "Stone", dict(collide=True, collision="PreciseConvexDecomposition")),
    ]
    rgb = {"Logs": (138, 116, 92), "Chinking": (192, 184, 166), "Roof": (112, 100, 88), "Porch": (140, 112, 84),
           "Posts": (136, 112, 88), "Floor": (140, 112, 84), "Trim": (130, 104, 80), "Glass": (84, 102, 112),
           "Stone": L.stats_srgb(s_col)}
    dens = L.texel_density([stone], RES)
    attach = {"Door": ((0.0, HY + 0.55, FLOOR), (0, 1, 0), (0, 0, 1)),
              "Hearth": ((HX - 0.75, 0.0, FLOOR), (-1, 0, 0), (0, 0, 1)),
              "PorchCenter": ((0.0, 7.7, FLOOR), (0, 1, 0), (0, 0, 1))}
    e = lib.add_asset("%s_Cabin" % D.PREFIX, "Building", parts, files, mat, attach,
                      "Hunter's log cabin. Door opening 4 x 7.5 (floor 1.25), porch deck 1.25 with two steps, "
                      "ridge %.1f, chimney top 17.9. Kit page: tiling trims (logs, planks, shakes; U = 8 studs) + "
                      "end-grain discs + swatches + a uniquely baked stone region (%.0f px/stud)." % (
                          ZR + 0.9, dens),
                      part_rgb=[rgb[p[1]] for p in parts],
                      extra={"pxPerStud": {"trims": [128, 48], "stones": round(dens, 1)},
                             "kitLayout": {"bands": BANDS, "stoneRect": STONE_RECT, "discs": DISCS,
                                           "swatches": SW, "studsPerTileU": SPT}})
    lib.finish(e)
    D.park(lib, e)
    print("ASSET %-16s %6d tris  kit page %s  stones %.1f px/stud  (%.0fs)" % (e["name"], e["tris"], page, dens,
                                                                             time.time() - t0), flush=True)
    return e
