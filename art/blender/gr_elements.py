"""
gr_elements.py - modelled plant elements for the GroundReal card atlases (texture-from-geometry).

Every element is real geometry in studs: grass blades with a folded midrib, fern fronds with toothed pinnae,
bracken with pinnules, leaves with vein attributes, flowers, moss tufts. ElementMesh (a MeshBuilder with extra
attributes) carries per-vertex linear albedo, roughness and leaf-space coordinates (lu across -1..1, lv along
0..1, vein strength, vein count, vein mode) that the atlas shader turns into veins and bump.

Element space: the card plane is XY with +Y = growth direction (up on the card) and +Z toward the camera.
Side-view elements (grasses, reeds, flower sprigs, fronds) stand on y = 0; top-view elements (bracken blade,
leaf sprays, moss) lie in the plane and are seen from above.
"""
import math

import numpy as np

import tex_ground as tg

C = tg.rgb


# =============================================================================================== mesh builder
class ElementMesh(tg.MeshBuilder):
    def __init__(self):
        super().__init__()
        self.A = []          # (k, 5): lu, lv, vein, nvein, vmode

    def add(self, verts, faces, color, rough=0.6, leaf=None):
        verts = np.asarray(verts, np.float64).reshape(-1, 3)
        k = len(verts)
        if leaf is None:
            leaf = np.zeros((k, 5))
        else:
            leaf = np.asarray(leaf, np.float64)
            if leaf.ndim == 1:
                leaf = np.tile(leaf, (k, 1))
        self.A.append(leaf)
        return super().add(verts, faces, color, rough)

    def build(self, name, collection=None):
        obj = super().build(name, collection)
        if obj is None:
            return None
        A = np.concatenate(self.A, 0)
        for i, nm in enumerate(("lu", "lv", "vein", "nvein", "vmode")):
            tg.set_point_float(obj.data, nm, A[:, i])
        return obj


def _grid_faces(rows, cols):
    """Quad faces for a rows x cols vertex grid laid out row-major."""
    f = []
    for r in range(rows - 1):
        for c in range(cols - 1):
            a = r * cols + c
            f.append((a, a + 1, a + cols + 1, a + cols))
    return f


def _rot2(v, ang):
    c, s = math.cos(ang), math.sin(ang)
    return np.stack([v[..., 0] * c - v[..., 1] * s, v[..., 0] * s + v[..., 1] * c], -1)


def perp_basis(f):
    """Two unit vectors perpendicular to f (and to each other)."""
    f = np.asarray(f, float)
    f = f / np.linalg.norm(f)
    a = np.array([1.0, 0.0, 0.0]) if abs(f[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    s = np.cross(f, a)
    s /= np.linalg.norm(s)
    return s, np.cross(f, s)


def frame_from_dir(d, up_hint=(0, 0, 1)):
    d = np.asarray(d, float)
    d = d / np.linalg.norm(d)
    u = np.asarray(up_hint, float)
    side = np.cross(d, u)
    if np.linalg.norm(side) < 1e-6:
        side = np.cross(d, (1, 0, 0))
    side /= np.linalg.norm(side)
    nrm = np.cross(side, d)
    return d, side, nrm


# =============================================================================================== primitives
def spine_curve(base, ang0, length, curve, segs, tilt=0.0, curve_pow=1.6, wobble=0.0, rng=None):
    """Points of a blade spine in the card plane (XY), starting at base, initial angle ang0 from +Y toward +X,
    bending by 'curve' radians toward +X (negative = toward -X) with curvature growing toward the tip. tilt is a
    constant z slope per stud (depth). Returns pts (segs+1, 3) and unit dirs."""
    t = np.linspace(0, 1, segs + 1)
    ang = ang0 + curve * t ** curve_pow
    if wobble and rng is not None:
        ang = ang + wobble * np.sin(t * math.pi * rng.uniform(1, 3) + rng.uniform(0, 6))
    d = np.stack([np.sin(ang), np.cos(ang), np.full_like(t, tilt)], 1)
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    step = length / segs
    pts = np.zeros((segs + 1, 3))
    pts[0] = base
    for i in range(1, segs + 1):
        pts[i] = pts[i - 1] + 0.5 * (d[i - 1] + d[i]) * step
    return pts, d


def ribbon(mb, pts, dirs, widths, color_fn, rough, twist=None, fold=0.25, leafattr=None, side_up=(0, 0, 1)):
    """A folded strip (3 vertices across: edge, midrib, edge) along pts. widths = half widths per point.
    color_fn(t) -> (k, 3) colours per spine point. leafattr: (vein, nvein, vmode)."""
    k = len(pts)
    t = np.linspace(0, 1, k)
    V, L, Cs = [], [], []
    cols = color_fn(t)
    for i in range(k):
        d = dirs[i]
        side = np.cross(d, side_up)
        if np.linalg.norm(side) < 1e-6:
            side = np.array([1.0, 0, 0])
        side /= np.linalg.norm(side)
        nrm = np.cross(side, d)
        nrm /= np.linalg.norm(nrm)
        if twist is not None:
            a = twist[i]
            side, nrm = side * math.cos(a) + nrm * math.sin(a), -side * math.sin(a) + nrm * math.cos(a)
        w = widths[i]
        p = pts[i]
        V += [p - side * w, p + nrm * w * fold, p + side * w]
        Cs += [cols[i] * 0.94, cols[i] * 1.03, cols[i] * 0.94]
        if leafattr is None:
            L += [(-1, t[i], 0, 0, 0), (0, t[i], 0, 0, 0), (1, t[i], 0, 0, 0)]
        else:
            L += [(-1, t[i]) + tuple(leafattr), (0, t[i]) + tuple(leafattr), (1, t[i]) + tuple(leafattr)]
    F = _grid_faces(k, 3)
    mb.add(np.array(V), F, np.array(Cs), rough, np.array(L))


def tube(mb, pts, radius, color, rough, sides=5, color_fn=None):
    """A thin round stem along pts (radius scalar or per point)."""
    pts = np.asarray(pts, float)
    k = len(pts)
    rad = np.full(k, radius) if np.ndim(radius) == 0 else np.asarray(radius, float)
    V, Cs = [], []
    t = np.linspace(0, 1, k)
    for i in range(k):
        d = pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)]
        d /= max(np.linalg.norm(d), 1e-9)
        _, s, n = frame_from_dir(d, (0, 0, 1) if abs(d[2]) < 0.9 else (1, 0, 0))
        col = color if color_fn is None else color_fn(t[i])
        for j in range(sides):
            a = TAU_J(j, sides)
            V.append(pts[i] + (s * math.cos(a) + n * math.sin(a)) * rad[i])
            Cs.append(np.asarray(col) * (0.85 + 0.15 * math.sin(a)))
    F = []
    for i in range(k - 1):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            F.append((a, b, b + sides, a + sides))
    mb.add(np.array(V), F, np.array(Cs), rough)


def TAU_J(j, n):
    return 2.0 * math.pi * j / n


def ellipsoid(mb, center, axes, color, rough, seg=8, rings=5, axis_dir=None, color_fn=None):
    """Small ellipsoid (spikelets, buds, berries, flower discs). axes = (rx, ry, rz) in local frame; if axis_dir
    is given the local +Y axis is aligned to it."""
    V, Cs = [], []
    for r in range(rings + 1):
        th = math.pi * r / rings
        for s in range(seg):
            ph = 2 * math.pi * s / seg
            p = np.array([math.sin(th) * math.cos(ph) * axes[0], -math.cos(th) * axes[1],
                          math.sin(th) * math.sin(ph) * axes[2]])
            V.append(p)
            col = color if color_fn is None else color_fn(r / rings, ph)
            Cs.append(col)
    V = np.array(V)
    if axis_dir is not None:
        d, s, n = frame_from_dir(axis_dir)
        V = V[:, 0:1] * s + V[:, 1:2] * d + V[:, 2:3] * n
    V = V + np.asarray(center, float)
    F = []
    for r in range(rings):
        for s in range(seg):
            a, b = r * seg + s, r * seg + (s + 1) % seg
            F.append((a, b, b + seg, a + seg))
    mb.add(V, F, np.array(Cs), rough)


def leaf(mb, base, direction, length, width, shape="ovate", color=(0.1, 0.2, 0.05), rough=0.55, nlen=8,
         ncross=5, cup=0.15, curl=0.0, fold=0.12, roll=0.0, serr=0.0, serr_n=0, lobes=0, lobe_depth=0.0,
         vein=0.8, nvein=7.0, vmode=0.0, color_tip=None, color_edge=None, spots=None, rng=None,
         up=(0, 0, 1), petiole=0.0):
    """Generic leaf blade along 'direction' from 'base'. shape: ovate | elliptic | lanceolate | linear | obovate
    | round | spatulate. Width profile x serration x lobes. cup/curl/fold bend it in 3D; roll rotates it about
    its midrib. Returns nothing (adds to mb)."""
    d, side, nrm = frame_from_dir(direction, up)
    if roll:
        side, nrm = side * math.cos(roll) + nrm * math.sin(roll), -side * math.sin(roll) + nrm * math.cos(roll)
    ys = np.linspace(0, 1, nlen + 1)
    if shape == "ovate":
        prof = np.sin(np.clip(ys, 0, 1) ** 0.75 * math.pi) * (1.0 - 0.25 * ys)
    elif shape == "elliptic":
        prof = np.sin(ys * math.pi) ** 0.85
    elif shape == "obovate":
        prof = np.sin(np.clip(ys, 0, 1) ** 1.35 * math.pi) ** 0.9
    elif shape == "lanceolate":
        prof = np.sin(np.clip(ys, 0, 1) ** 0.6 * math.pi) ** 0.9
    elif shape == "linear":
        prof = np.clip(1.0 - smooth_tip(ys, 0.75), 0, 1) * np.clip(ys * 8 + 0.35, 0, 1)
    elif shape == "spatulate":
        prof = 0.25 + 0.75 * np.sin(np.clip(ys, 0, 1) ** 2.2 * math.pi) ** 0.8
        prof[-1] = 0
    else:  # round
        prof = np.sqrt(np.clip(1 - (2 * ys - 1) ** 2, 0, 1))
    if serr and serr_n:
        saw = (ys * serr_n) % 1.0
        prof = prof * (1.0 + serr * (saw - 0.5))
    if lobes:
        prof = prof * (1.0 - lobe_depth * (0.5 - 0.5 * np.cos(ys * lobes * 2 * math.pi)) ** 1.5)
    prof = np.clip(prof, 0, None)
    prof[-1] = 0.0
    xs = np.linspace(-1, 1, ncross)
    V, Cs, L = [], [], []
    rngv = rng if rng is not None else np.random
    base = np.asarray(base, float) + d * petiole
    col0 = np.asarray(color, float)
    for i, y in enumerate(ys):
        for x in xs:
            w = width * 0.5 * prof[i]
            along = y * length
            bend = curl * (y ** 2) * length          # curl toward nrm (positive = tip up)
            cupz = cup * (x ** 2) * w * 2.0
            foldz = -fold * abs(x) * w
            p = base + d * along + side * (x * w) + nrm * (bend + cupz + foldz)
            V.append(p)
            c = col0.copy()
            if color_tip is not None:
                c = c + (np.asarray(color_tip) - c) * (y ** 2)
            if color_edge is not None:
                c = c + (np.asarray(color_edge) - c) * (abs(x) ** 3) * 0.6
            if spots is not None and rngv.random_sample() < spots[0]:
                c = c + (np.asarray(spots[1]) - c) * rngv.uniform(0.3, 0.8)
            Cs.append(c)
            L.append((x, y, vein, nvein, vmode))
    F = _grid_faces(len(ys), ncross)
    mb.add(np.array(V), F, np.array(Cs), rough, np.array(L))


def smooth_tip(y, start):
    return tg.smoothstep(start, 1.0, y)


def disc(mb, center, radius, color, rough, n=10, normal=(0, 0, 1), dome=0.0, color_fn=None):
    """Flat or slightly domed disc (flower centres, mushroom tops in top views)."""
    nz = np.asarray(normal, float)
    nz /= np.linalg.norm(nz)
    s, n2 = perp_basis(nz)
    rings = 3
    V, Cs = [np.asarray(center, float) + nz * dome * radius], [color if color_fn is None else color_fn(0.0)]
    for r in range(1, rings + 1):
        rr = r / rings
        for j in range(n):
            a = 2 * math.pi * j / n
            V.append(np.asarray(center) + (s * math.cos(a) + n2 * math.sin(a)) * radius * rr
                     + nz * dome * radius * (1 - rr ** 2))
            Cs.append(color if color_fn is None else color_fn(rr))
    F = []
    for j in range(n):
        F.append((0, 1 + j, 1 + (j + 1) % n))
    for r in range(1, rings):
        o0, o1 = 1 + (r - 1) * n, 1 + r * n
        for j in range(n):
            F.append((o0 + j, o1 + j, o1 + (j + 1) % n, o0 + (j + 1) % n))
    mb.add(np.array(V), F, np.array(Cs), rough)


# =============================================================================================== grasses
def grass_blade(mb, rng, base, ang0, length, width, cols, curve=0.0, rough=0.65, tilt=0.0, segs=8, fold=0.3,
                twist_amt=0.6, vein=0.5, nvein=5.0):
    """cols = (base, mid, tip) linear colours."""
    pts, dirs = spine_curve(base, ang0, length, curve, segs, tilt=tilt, wobble=0.05, rng=rng)
    t = np.linspace(0, 1, segs + 1)
    widths = width * 0.5 * np.clip(1.0 - t ** 2.2, 0, 1) ** 0.7 * np.clip(0.55 + t * 6, 0, 1)
    widths[-1] = 0.0
    tw = twist_amt * rng.uniform(-1, 1) * t + rng.uniform(-0.3, 0.3)
    cb, cm, ct = (np.asarray(c, float) for c in cols)

    def cf(tt):
        tt = tt[:, None]
        lo = cb + (cm - cb) * np.clip(tt / 0.35, 0, 1)
        return np.where(tt < 0.35, lo, cm + (ct - cm) * np.clip((tt - 0.35) / 0.65, 0, 1) ** 1.3)
    ribbon(mb, pts, dirs, widths, cf, rough, twist=tw, fold=fold, leafattr=(vein, nvein, 1.0))
    return pts


def jitter_col(rng, c, amt=0.08, hue=0.04):
    c = np.asarray(c, float)
    v = 1.0 + rng.uniform(-amt, amt)
    h = rng.uniform(-hue, hue)
    return np.clip(c * v * np.array([1 + h, 1.0, 1 - h]), 0, 1)


def spikelet_head(mb, rng, top, axis, length, width, col, rough=0.8, n=24, spread=0.25, droop=0.0):
    """A narrow spike / plume of small spikelets around the top of a culm."""
    axis = np.asarray(axis, float)
    axis /= np.linalg.norm(axis)
    for i in range(n):
        f = i / max(n - 1, 1)
        p = top - axis * length * (1.0 - f)
        a = rng.uniform(0, 2 * math.pi)
        out = np.array([math.cos(a), 0.0, math.sin(a)])
        out = out - axis * out.dot(axis)
        out /= max(np.linalg.norm(out), 1e-9)
        dirv = axis * (1.0 - droop) + out * spread + np.array([0, -droop, 0])
        sz = length * 0.09 * (0.7 + 0.6 * math.sin(f * math.pi))
        c = jitter_col(rng, col, 0.1, 0.03)
        ellipsoid(mb, p + out * width * 0.4 * math.sin(f * math.pi + 0.3), (sz * 0.28, sz, sz * 0.28), c, rough,
                  seg=5, rings=3, axis_dir=dirv)


def build_grass_tall(rng, variant="a"):
    """Mid-summer meadow tall grass (green / olive blades, sun-cured tips, golden seed heads), side view, card
    ~2.0 x 4.0 studs, base at (0, 0)."""
    mb = ElementMesh()
    # art direction 2026-11-11: values brought into the LookDevPlaybook grass band (green channel 60-120 sRGB);
    # the old golden palette (straw 196/170/112) read as a dry savanna next to the TreesReal forest
    straw = C(168, 148, 98)
    gold = C(176, 152, 94)
    pale = C(188, 174, 128)
    olive = C(108, 108, 56)
    green = C(84, 102, 46)
    brown = C(128, 102, 66)
    if variant == "a":
        nblades, culms = 78, 15
    else:
        nblades, culms = 50, 9
    for i in range(nblades):
        bx = rng.normal(0, 0.11)
        base = np.array([bx, rng.uniform(0, 0.04), rng.uniform(-0.15, 0.15)])
        if variant == "a":
            ang0 = rng.normal(0, 0.16) + bx * 0.9
            curve = rng.choice([-1, 1]) * rng.uniform(0.05, 0.75)
            length = rng.uniform(1.4, 3.3)
            width = rng.uniform(0.032, 0.058)
        else:
            ang0 = rng.normal(0, 0.28) + bx * 1.2
            curve = np.sign(ang0 + 1e-3) * rng.uniform(0.4, 1.4)
            length = rng.uniform(1.3, 2.8)
            width = rng.uniform(0.045, 0.075)
        r = rng.random_sample()
        # art direction 2026-11-11: mid-summer sward to sit with the lush TreesReal greens - mostly green and
        # olive blades with sun-cured tips, a third gold / straw, a few dead brown ones (was 68 % straw: it read
        # as a dry savanna next to the forest)
        if r < 0.5:
            cols = (green * 0.7, jitter_col(rng, green), jitter_col(rng, C(94, 106, 50)))
        elif r < 0.72:
            cols = (green * 0.75, jitter_col(rng, C(98, 102, 52)), jitter_col(rng, C(124, 118, 70)))
        elif r < 0.8:
            cols = (brown * 0.7, brown, C(170, 140, 96))
        else:
            cols = (olive * 0.8, jitter_col(rng, gold if r < 0.92 else straw), jitter_col(rng, pale))
        grass_blade(mb, rng, base, ang0, length, width, cols, curve=curve, rough=rng.uniform(0.6, 0.78),
                    tilt=rng.uniform(-0.15, 0.15), segs=9, fold=0.35, twist_amt=1.0, vein=0.45, nvein=5)
    for i in range(culms):
        bx = rng.normal(0, 0.07)
        base = np.array([bx, 0.0, rng.uniform(-0.1, 0.1)])
        length = rng.uniform(3.0, 3.85) if variant == "a" else rng.uniform(2.9, 3.7)
        ang0 = rng.normal(0, 0.07) + bx * 0.6
        curve = rng.normal(0, 0.12) if variant == "a" else rng.choice([-1, 1]) * rng.uniform(0.15, 0.4)
        pts, dirs = spine_curve(base, ang0, length, curve, 10, tilt=rng.uniform(-0.05, 0.05))
        col_c = jitter_col(rng, C(150, 136, 90) if rng.random_sample() < 0.45 else C(100, 108, 56))
        tube(mb, pts, np.linspace(0.011, 0.007, len(pts)), col_c, 0.6, sides=4)
        top = pts[-1]
        axis = dirs[-1]
        hcol = jitter_col(rng, C(170, 150, 104), 0.1, 0.05)
        if variant == "a":
            spikelet_head(mb, rng, top, axis, rng.uniform(0.28, 0.46), 0.05, hcol, n=30, spread=0.18)
        else:
            # open nodding panicle with hanging oat-like spikelets
            for w in range(6):
                f = 0.15 + 0.85 * w / 5.0
                p0 = top - axis * 0.75 * (1.0 - f)
                for b in range(rng.randint(1, 3)):
                    side = rng.choice([-1, 1])
                    bl = rng.uniform(0.1, 0.24) * (1.1 - 0.5 * f)
                    bd = np.array([side * 0.8, -0.15 - rng.uniform(0, 0.4), rng.uniform(-0.4, 0.4)])
                    bd /= np.linalg.norm(bd)
                    p1 = p0 + bd * bl
                    tube(mb, [p0, (p0 + p1) / 2 + np.array([0, 0.02, 0]), p1], 0.0035, col_c, 0.6, sides=3)
                    ellipsoid(mb, p1 + np.array([0, -0.035, 0]), (0.012, 0.045, 0.012),
                              jitter_col(rng, C(206, 186, 132), 0.08), 0.75, seg=5, rings=3,
                              axis_dir=(side * 0.25, -1, 0))
    return mb


def build_grass_forest(rng, variant="a"):
    """Green forest/meadow grass tuft, side view, card ~1.6 x 1.6, base at (0, 0)."""
    mb = ElementMesh()
    greens = [C(84, 112, 44), C(98, 124, 50), C(72, 100, 42), C(110, 128, 58), C(90, 118, 66)]
    n = 90 if variant == "a" else 75
    for i in range(n):
        bx = rng.normal(0, 0.09)
        base = np.array([bx, rng.uniform(0, 0.03), rng.uniform(-0.12, 0.12)])
        ang0 = rng.normal(0, 0.3) + bx * 1.6
        curve = np.sign(ang0 + rng.normal(0, 0.1)) * rng.uniform(0.15, 1.1)
        length = rng.uniform(0.45, 1.35)
        width = rng.uniform(0.016, 0.032)
        g = jitter_col(rng, greens[rng.randint(len(greens))], 0.12, 0.05)
        tip = g * 1.15
        if rng.random_sample() < 0.18:
            tip = C(170, 150, 96)                      # dry tip
        cols = (g * 0.55, g, tip)
        grass_blade(mb, rng, base, ang0, length, width, cols, curve=curve, rough=rng.uniform(0.5, 0.65),
                    tilt=rng.uniform(-0.2, 0.2), segs=7, fold=0.35, twist_amt=0.8, vein=0.4, nvein=4)
    if variant == "b":
        for i in range(6):
            base = np.array([rng.normal(0, 0.05), 0, rng.uniform(-0.05, 0.05)])
            length = rng.uniform(1.1, 1.45)
            pts, dirs = spine_curve(base, rng.normal(0, 0.12), length, rng.normal(0, 0.25), 8)
            tube(mb, pts, 0.005, C(110, 120, 64), 0.6, sides=3)
            top = pts[-1]
            for b in range(10):
                f = b / 9.0
                p0 = top - dirs[-1] * 0.28 * (1 - f)
                side = 1 if b % 2 else -1
                bd = np.array([side * 0.9, 0.4, rng.uniform(-0.3, 0.3)])
                p1 = p0 + bd / np.linalg.norm(bd) * rng.uniform(0.04, 0.1)
                tube(mb, [p0, p1], 0.0025, C(120, 120, 70), 0.6, sides=3)
                ellipsoid(mb, p1, (0.008, 0.016, 0.008), jitter_col(rng, C(132, 120, 84), 0.1), 0.7, seg=4,
                          rings=2, axis_dir=bd)
    return mb


# =============================================================================================== reeds, cattails
def build_reed(rng):
    """Common reed: culms with alternating drooping strap leaves and a nodding feathery plume. ~1.6 x 6.4."""
    mb = ElementMesh()
    for c in range(5):
        base = np.array([rng.normal(0, 0.14), 0, rng.uniform(-0.1, 0.1)])
        h = rng.uniform(5.0, 6.1)
        pts, dirs = spine_curve(base, rng.normal(0, 0.03), h, rng.normal(0, 0.1), 14)
        culm = jitter_col(rng, C(156, 146, 92), 0.08)
        tube(mb, pts, np.linspace(0.028, 0.014, len(pts)), culm, 0.55, sides=5)
        # leaves at nodes
        nodes = np.arange(0.5, h - 0.9, rng.uniform(0.45, 0.6))
        for j, z in enumerate(nodes):
            i = int(z / h * (len(pts) - 1))
            p = pts[i]
            side = 1 if j % 2 else -1
            lower = z < h * 0.35
            L = rng.uniform(0.8, 1.25) * (0.8 if lower else 1.0)
            ang0 = side * rng.uniform(0.35, 0.7)
            curve = side * rng.uniform(0.8, 1.6)
            if lower and rng.random_sample() < 0.6:
                cols = (C(150, 136, 92), C(168, 150, 100), C(176, 160, 116))
            else:
                g = jitter_col(rng, C(104, 122, 70), 0.08)
                cols = (g * 0.9, g, C(150, 144, 96))
            grass_blade(mb, rng, p, ang0, L, rng.uniform(0.07, 0.095), cols, curve=curve, rough=0.55, tilt=rng.uniform(-0.3, 0.3),
                        segs=9, fold=0.25, twist_amt=1.2, vein=0.6, nvein=7)
        # plume
        top = pts[-1]
        nod = np.array([rng.choice([-1, 1]) * 0.6, 1.0, 0])
        nod /= np.linalg.norm(nod)
        for b in range(38):
            f = b / 37.0
            p0 = top - dirs[-1] * 0.85 * (1 - f)
            bd = nod * 0.7 + np.array([rng.normal(0, 0.45), rng.uniform(-0.1, 0.4), rng.normal(0, 0.3)])
            bd /= np.linalg.norm(bd)
            bl = 0.24 * (1.0 - 0.6 * f) + rng.uniform(0, 0.09)
            seg = [p0 + bd * bl * s for s in np.linspace(0, 1, 4)]
            tube(mb, seg, 0.003, C(130, 104, 90), 0.8, sides=3)
            for s in range(5):
                q = p0 + bd * bl * (0.25 + 0.75 * s / 4.0)
                col = jitter_col(rng, C(132, 100, 92) if rng.random_sample() < 0.5 else C(172, 150, 126), 0.1)
                ellipsoid(mb, q, (0.007, 0.03, 0.007), col, 0.85, seg=4, rings=2, axis_dir=bd + nod * 0.4)
    return mb


def build_cattail_leaves(rng):
    """Strap leaves of a cattail stand (heads are geometry on the asset). ~1.4 x 5.2."""
    mb = ElementMesh()
    for i in range(17):
        bx = rng.normal(0, 0.14)
        base = np.array([bx, 0, rng.uniform(-0.1, 0.1)])
        L = rng.uniform(3.2, 5.0)
        ang0 = rng.normal(0, 0.06) + bx * 0.5
        curve = rng.choice([-1, 1]) * rng.uniform(0.05, 0.5)
        pts, dirs = spine_curve(base, ang0, L, curve, 14, tilt=rng.uniform(-0.04, 0.04))
        t = np.linspace(0, 1, len(pts))
        w = rng.uniform(0.035, 0.05) * np.clip(1.0 - tg.smoothstep(0.82, 1.0, t), 0, 1) ** 0.6
        w[-1] = 0
        tw = rng.uniform(-0.8, 0.8) * t + rng.uniform(-0.35, 0.35)
        g = jitter_col(rng, C(96, 116, 60), 0.08, 0.04)
        dry = rng.random_sample() < 0.4

        def cf(tt, g=g, dry=dry):
            tt = tt[:, None]
            c = C(150, 150, 98) + (g - C(150, 150, 98)) * np.clip(tt * 5, 0, 1)
            if dry:
                c = c + (C(158, 134, 90) - c) * tg.smoothstep(0.8, 1.0, tt)
            return c
        ribbon(mb, pts, dirs, w, cf, 0.5, twist=tw, fold=0.35, leafattr=(0.55, 9.0, 1.0))
    return mb


# =============================================================================================== ferns
def pinna(mb, rng, base, direction, length, width, col, rough, serr=0.25, nteeth=9, auricle=True, curl=0.08,
          up=(0, 0, 1)):
    leaf(mb, base, direction, length, width, shape="lanceolate", color=col, rough=rough, nlen=10, ncross=5,
         cup=0.05, curl=curl, fold=0.25, serr=serr, serr_n=nteeth, vein=0.7, nvein=nteeth * 0.9, vmode=0.0,
         color_tip=col * 1.12, up=up)
    if auricle:
        d = np.asarray(direction, float)
        d /= np.linalg.norm(d)
        ear = np.array([0.0, 1.0, 0.0]) - d * d[1]
        if np.linalg.norm(ear) > 1e-6:
            ear /= np.linalg.norm(ear)
            leaf(mb, np.asarray(base) + d * width * 0.2, ear * 0.6 + d * 0.4, width * 0.9, width * 0.6, shape="ovate",
                 color=col, rough=rough, nlen=4, ncross=3, cup=0.05, vein=0.4, nvein=3, up=up)


def build_sword_fern(rng, variant="a"):
    """Single-pinnate frond lying flat, rachis along +Y from y = 0. ~0.75 x 3.0."""
    mb = ElementMesh()
    L = 2.85 if variant == "a" else 2.6
    stipe = 0.55 if variant == "a" else 0.45
    base_col = C(56, 94, 42) if variant == "a" else C(74, 108, 48)
    pts, dirs = spine_curve(np.array([0, 0, 0.0]), 0.0, L, rng.normal(0, 0.08), 30)
    tube(mb, pts, np.linspace(0.022, 0.004, len(pts)), C(70, 76, 40), 0.5, sides=4,
         color_fn=lambda t: C(96, 74, 50) if t < stipe / L else C(70, 90, 44))
    # scales on the stipe
    for i in range(14):
        p = pts[int(rng.uniform(0, stipe / L) * 30)]
        leaf(mb, p, (rng.normal(0, 1), rng.uniform(0.2, 1), 0.3), 0.04, 0.012, shape="lanceolate",
             color=C(120, 88, 56), rough=0.7, nlen=3, ncross=3, vein=0)
    npairs = 25 if variant == "a" else 22
    for k in range(npairs):
        f = k / (npairs - 1)
        for side in (-1, 1):
            ff = f + (0.5 / npairs if side > 0 else 0.0)
            pos = stipe / L + (1 - stipe / L) * ff
            if pos > 0.995:
                continue
            idx = pos * 30
            i0 = int(idx)
            p = pts[i0] + (pts[min(i0 + 1, 30)] - pts[i0]) * (idx - i0)
            d = dirs[min(i0, 29)]
            rise = 0.5 + 0.5 * math.sin(min(ff / 0.22, 1.0) * math.pi / 2)
            fall = (1.0 - tg.smoothstep(0.56, 1.0, ff)) ** 0.8
            prof = rise * fall
            length = 0.30 * prof + 0.025
            width = 0.068 * (0.6 + 0.4 * prof)
            ang = math.radians(76 - 18 * ff)
            out = _rot2(d[None, :2], -side * ang)[0]
            direction = np.array([out[0], out[1], rng.uniform(-0.05, 0.12)])
            col = jitter_col(rng, base_col, 0.06, 0.03)
            pinna(mb, rng, p, direction, length, width, col, 0.42, serr=0.3, nteeth=10, auricle=True,
                  curl=rng.uniform(0.0, 0.12))
    return mb


def build_bracken(rng):
    """Bracken blade seen from above: tripinnate triangle, rachis along +Y from y = 0. ~2.4 x 2.4."""
    mb = ElementMesh()
    L = 2.3
    pts, dirs = spine_curve(np.array([0, 0, 0.0]), 0.0, L, rng.normal(0, 0.06), 24)
    tube(mb, pts, np.linspace(0.026, 0.005, len(pts)), C(110, 112, 52), 0.5, sides=4)
    greens = [C(84, 114, 42), C(94, 121, 46), C(106, 129, 51), C(78, 105, 39)]
    npairs = 9
    for k in range(npairs):
        f = k / npairs
        for side in (-1, 1):
            pos = 0.04 + f * 0.92 + (0.02 if side > 0 else 0.0)
            idx = pos * 24
            i0 = min(int(idx), 23)
            p = pts[i0] + (pts[i0 + 1] - pts[i0]) * (idx - i0)
            d = dirs[i0]
            plen = 1.18 * (1.0 - f) ** 1.05 + 0.08
            ang = math.radians(62 - 18 * f)
            out = _rot2(d[None, :2], -side * ang)[0]
            cpts, cdirs = spine_curve(p, math.atan2(out[0], out[1]), plen, -side * rng.uniform(0.05, 0.25), 12,
                                      tilt=rng.uniform(0.0, 0.06))
            tube(mb, cpts, np.linspace(0.012, 0.003, len(cpts)), C(108, 120, 52), 0.5, sides=3)
            gcol = greens[rng.randint(len(greens))]
            brown = rng.random_sample() < 0.18
            nps = max(5, int(24 * plen / 1.2))
            for j in range(nps):
                g = j / nps
                for s2 in (-1, 1):
                    qpos = 0.05 + g * 0.93 + (0.5 / nps if s2 > 0 else 0)
                    if qpos > 0.99:
                        continue
                    qi = qpos * 12
                    q0 = min(int(qi), 11)
                    q = cpts[q0] + (cpts[q0 + 1] - cpts[q0]) * (qi - q0)
                    qd = cdirs[q0]
                    plen2 = (0.19 * (1.0 - g) ** 0.75 + 0.035) * (0.6 + 0.4 * (1 - f))
                    qa = math.radians(70 - 20 * g)
                    o2 = _rot2(qd[None, :2], -s2 * qa)[0]
                    col = jitter_col(rng, gcol, 0.07, 0.04)
                    if brown and g > 0.4:
                        col = col + (C(150, 112, 60) - col) * rng.uniform(0.3, 0.9)
                    nl = 6 if plen2 > 0.08 else 0
                    leaf(mb, q, (o2[0], o2[1], rng.uniform(0.02, 0.12)), plen2, min(0.05, plen2 * 0.42),
                         shape="linear", color=col, rough=0.55, nlen=8, ncross=3, cup=0.12, fold=0.2,
                         lobes=nl, lobe_depth=0.45, vein=0.55, nvein=max(nl, 3), vmode=0.0,
                         color_tip=col * 1.1)
    return mb


# =============================================================================================== flowers
def daisy_head(mb, rng, center, facing, radius, petal_col=None, disc_col=None, n=21):
    facing = np.asarray(facing, float)
    facing /= np.linalg.norm(facing)
    disc(mb, center, radius * 0.3, disc_col if disc_col is not None else C(214, 162, 34), 0.7, n=9,
         normal=facing, dome=0.35)
    s, n2 = perp_basis(facing)
    pc = petal_col if petal_col is not None else C(232, 232, 222)
    for j in range(n):
        a = 2 * math.pi * (j + rng.uniform(-0.2, 0.2)) / n
        d = s * math.cos(a) + n2 * math.sin(a) - facing * rng.uniform(0.0, 0.35)
        leaf(mb, np.asarray(center) + (s * math.cos(a) + n2 * math.sin(a)) * radius * 0.26, d,
             radius * rng.uniform(0.68, 0.8), radius * 0.2, shape="elliptic",
             color=jitter_col(rng, pc, 0.04, 0.01), rough=0.55, nlen=4, ncross=3, cup=0.2, fold=0.0,
             vein=0.25, nvein=3, vmode=1.0, up=facing)


def cup_flower(mb, rng, center, facing, radius, col, n=5):
    facing = np.asarray(facing, float)
    facing /= np.linalg.norm(facing)
    disc(mb, center, radius * 0.25, C(150, 140, 40), 0.6, n=6, normal=facing, dome=0.5)
    s, n2 = perp_basis(facing)
    for j in range(n):
        a = 2 * math.pi * j / n + rng.uniform(-0.15, 0.15)
        o = s * math.cos(a) + n2 * math.sin(a)
        leaf(mb, np.asarray(center) + o * radius * 0.12, o * 0.85 + facing * 0.45, radius * 0.95, radius * 0.95,
             shape="obovate", color=jitter_col(rng, col, 0.04, 0.01), rough=0.3, nlen=4, ncross=4, cup=0.45,
             vein=0.3, nvein=4, vmode=1.0, up=facing)


def tuft_head(mb, rng, center, radius, bract_col, floret_col, n=40, up=(0, 1, 0)):
    """Knapweed-like: scaly bract ball with a crown of thin florets."""
    ellipsoid(mb, center, (radius, radius * 1.1, radius), bract_col, 0.75, seg=8, rings=5, axis_dir=up)
    up = np.asarray(up, float)
    up /= np.linalg.norm(up)
    for j in range(n):
        a = rng.uniform(0, 2 * math.pi)
        el = rng.uniform(0.15, 1.0)
        _, s, n2 = frame_from_dir(up)
        d = up * el + (s * math.cos(a) + n2 * math.sin(a)) * (1 - el * 0.6)
        d /= np.linalg.norm(d)
        p0 = np.asarray(center) + up * radius * 0.6 + d * radius * 0.4
        tube(mb, [p0, p0 + d * radius * rng.uniform(0.9, 1.5)], radius * 0.07, jitter_col(rng, floret_col, 0.08),
             0.6, sides=3)


def umbel(mb, rng, center, radius, col, n=45, up=(0, 1, 0)):
    """Yarrow-like flat dome of tiny florets."""
    up = np.asarray(up, float)
    up /= np.linalg.norm(up)
    _, s, n2 = frame_from_dir(up)
    for j in range(n):
        r = radius * math.sqrt(rng.uniform(0, 1))
        a = rng.uniform(0, 2 * math.pi)
        p = np.asarray(center) + (s * math.cos(a) + n2 * math.sin(a)) * r + up * (radius * 0.25 * (1 - (r / radius) ** 2))
        disc(mb, p, radius * 0.07, jitter_col(rng, col, 0.05, 0.01), 0.7, n=5, normal=up * 0.7 + (p - center) * 2.0,
             dome=0.4)
        tube(mb, [np.asarray(center) - up * radius * 0.5, p], radius * 0.012, C(110, 118, 70), 0.6, sides=3)


def clover_head(mb, rng, center, radius, col):
    ellipsoid(mb, center, (radius, radius * 1.05, radius), col * 0.8, 0.7, seg=8, rings=6)
    for j in range(36):
        u = rng.uniform(-0.6, 1.0)
        a = rng.uniform(0, 2 * math.pi)
        d = np.array([math.sqrt(1 - u * u) * math.cos(a), u, math.sqrt(1 - u * u) * math.sin(a)])
        p = np.asarray(center) + d * radius * 0.85
        tube(mb, [p, p + d * radius * 0.45], radius * 0.12, jitter_col(rng, col, 0.1, 0.03), 0.6, sides=3)


def bell_flower(mb, rng, top, radius, col):
    """Harebell: nodding bell hanging from 'top'."""
    pts = [np.asarray(top) + np.array([radius * 0.2 * math.sin(i), -radius * 2.0 * i / 6.0, 0]) for i in range(7)]
    rr = [radius * (0.2 + 0.8 * (i / 6.0) ** 0.7) for i in range(7)]
    V, F, Cs = [], [], []
    sides = 8
    for i, (p, r) in enumerate(zip(pts, rr)):
        for j in range(sides):
            a = 2 * math.pi * j / sides
            flare = 1.0 + (0.25 if i == 6 and j % 2 == 0 else 0.0)
            V.append(p + np.array([math.cos(a), 0, math.sin(a)]) * r * flare)
            Cs.append(col * (0.8 + 0.25 * i / 6.0))
    for i in range(6):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            F.append((a, b, b + sides, a + sides))
    mb.add(np.array(V), F, np.array(Cs), 0.5)


def flower_stem(mb, rng, base, height, lean, col=None):
    pts, dirs = spine_curve(base, lean, height, rng.normal(0, 0.15), 8, tilt=rng.uniform(-0.15, 0.15))
    tube(mb, pts, np.linspace(0.009, 0.006, len(pts)), col if col is not None else jitter_col(rng, C(84, 108, 48)),
         0.55, sides=4)
    return pts, dirs


def basal_leaves(mb, rng, n, spread, col, shape="spatulate", length=(0.12, 0.22), width=(0.04, 0.07), serr=0.0):
    for i in range(n):
        a = rng.uniform(-1.2, 1.2)
        base = np.array([rng.normal(0, spread), 0.0, rng.uniform(-0.1, 0.1)])
        d = np.array([math.sin(a), math.cos(a) * 0.8 + 0.2, rng.uniform(-0.3, 0.6)])
        leaf(mb, base, d, rng.uniform(*length), rng.uniform(*width), shape=shape,
             color=jitter_col(rng, col, 0.08, 0.03), rough=0.5, nlen=6, ncross=5, cup=0.2, curl=-0.2,
             serr=serr, serr_n=7, vein=0.6, nvein=5)


def build_flowers(rng, variant="a"):
    """Meadow wildflower sprig, side view, ~1.8 x 1.8, base (0, 0)."""
    mb = ElementMesh()
    greens = [C(84, 112, 44), C(98, 124, 50), C(104, 120, 58)]
    for i in range(42):
        bx = rng.normal(0, 0.24)
        g = jitter_col(rng, greens[rng.randint(3)], 0.1)
        grass_blade(mb, rng, np.array([bx, 0, rng.uniform(-0.1, 0.1)]), rng.normal(0, 0.3) + bx, rng.uniform(0.35, 1.0),
                    rng.uniform(0.016, 0.028), (g * 0.6, g, g * 1.1), curve=rng.normal(0, 0.6), rough=0.55, tilt=rng.uniform(-0.2, 0.2),
                    segs=6, vein=0.4, nvein=4)
    if variant == "a":
        basal_leaves(mb, rng, 9, 0.16, C(76, 104, 44), "spatulate", serr=0.25)
        for i in range(12):       # ox-eye daisies
            base = np.array([rng.normal(0, 0.28), 0, rng.uniform(-0.1, 0.1)])
            pts, dirs = flower_stem(mb, rng, base, rng.uniform(0.95, 1.6), rng.normal(0, 0.12))
            for k in range(3):
                q = pts[1 + k * 2]
                leaf(mb, q, (rng.choice([-1, 1]) * 0.8, 0.6, 0.1), 0.11, 0.03, shape="lanceolate",
                     color=C(78, 104, 46), rough=0.5, nlen=5, ncross=3, serr=0.35, serr_n=6, vein=0.4, nvein=4)
            face = dirs[-1] * 0.6 + np.array([rng.normal(0, 0.4), 0, rng.uniform(0.3, 0.9)])
            daisy_head(mb, rng, pts[-1], face, rng.uniform(0.08, 0.1))
        for i in range(10):       # buttercups
            base = np.array([rng.normal(0, 0.3), 0, rng.uniform(-0.1, 0.1)])
            pts, dirs = flower_stem(mb, rng, base, rng.uniform(0.7, 1.25), rng.normal(0, 0.18))
            heads = [pts[-1]]
            if rng.random_sample() < 0.7:
                b0 = pts[5]
                bp, bd = spine_curve(b0, rng.choice([-1, 1]) * 0.5, 0.25, 0.1, 4)
                tube(mb, bp, 0.006, C(84, 108, 48), 0.55, sides=3)
                heads.append(bp[-1])
            for h in heads:
                face = np.array([rng.normal(0, 0.5), 0.7, rng.uniform(0.2, 0.9)])
                cup_flower(mb, rng, h, face, rng.uniform(0.032, 0.042), C(226, 184, 34))
        for i in range(5):        # palmate buttercup leaves
            base = np.array([rng.normal(0, 0.15), 0.02, rng.uniform(-0.05, 0.1)])
            for lb in range(3):
                a = (lb - 1) * 0.7 + rng.normal(0, 0.1)
                leaf(mb, base + np.array([0, 0.12, 0]), (math.sin(a), math.cos(a), 0.4), 0.09, 0.07,
                     shape="obovate", color=jitter_col(rng, C(70, 100, 40), 0.08), rough=0.45, nlen=5, ncross=5,
                     lobes=3, lobe_depth=0.4, vein=0.5, nvein=4)
    else:
        for i in range(7):        # knapweed
            base = np.array([rng.normal(0, 0.28), 0, rng.uniform(-0.1, 0.1)])
            pts, dirs = flower_stem(mb, rng, base, rng.uniform(1.0, 1.5), rng.normal(0, 0.12), C(78, 96, 50))
            tuft_head(mb, rng, pts[-1], 0.04, C(84, 74, 46), C(184, 86, 166), n=52, up=dirs[-1])
            if rng.random_sample() < 0.6:
                bp, bd = spine_curve(pts[5], rng.choice([-1, 1]) * 0.5, 0.3, 0.1, 4)
                tube(mb, bp, 0.006, C(78, 96, 50), 0.55, sides=3)
                tuft_head(mb, rng, bp[-1], 0.028, C(84, 74, 46), C(176, 82, 158), n=32, up=bd[-1])
            for k in range(3):
                leaf(mb, pts[1 + k], (rng.choice([-1, 1]), 0.5, 0.1), 0.14, 0.03, shape="lanceolate",
                     color=C(84, 100, 54), rough=0.6, nlen=5, ncross=3, vein=0.4, nvein=4)
        for i in range(4):        # yarrow
            base = np.array([rng.normal(0, 0.26), 0, rng.uniform(-0.1, 0.1)])
            pts, dirs = flower_stem(mb, rng, base, rng.uniform(1.0, 1.35), rng.normal(0, 0.1), C(96, 108, 64))
            umbel(mb, rng, pts[-1] + np.array([0, 0.03, 0]), rng.uniform(0.09, 0.12), C(226, 222, 206), n=60)
            for k in range(4):     # feathery leaves
                q = pts[k + 1]
                for s in range(8):
                    leaf(mb, q + np.array([0, s * 0.012, 0]), (rng.choice([-1, 1]) * 0.9, 0.4 + s * 0.05, 0.1),
                         0.05, 0.008, shape="linear", color=C(78, 100, 52), rough=0.6, nlen=3, ncross=3, vein=0)
        for i in range(7):        # red clover
            base = np.array([rng.normal(0, 0.28), 0, rng.uniform(-0.1, 0.1)])
            pts, dirs = flower_stem(mb, rng, base, rng.uniform(0.35, 0.75), rng.normal(0, 0.25), C(86, 110, 52))
            clover_head(mb, rng, pts[-1], 0.04, C(192, 112, 146))
            for lf in range(3):
                q = pts[2] + np.array([rng.normal(0, 0.05), 0, 0])
                for li in range(3):
                    a = (li - 1) * 1.1 + rng.normal(0, 0.1)
                    leaf(mb, q, (math.sin(a), math.cos(a), 0.6), 0.05, 0.032, shape="elliptic",
                         color=C(72, 104, 46), color_edge=C(140, 160, 110), rough=0.5, nlen=4, ncross=5,
                         vein=0.3, nvein=4)
        for i in range(5):        # harebells
            base = np.array([rng.normal(0, 0.24), 0, rng.uniform(-0.1, 0.1)])
            pts, dirs = spine_curve(base, rng.normal(0, 0.1), rng.uniform(0.85, 1.2), rng.choice([-1, 1]) * 0.6, 8)
            tube(mb, pts, 0.004, C(90, 110, 60), 0.55, sides=3)
            bell_flower(mb, rng, pts[-1], 0.022, C(118, 124, 196))
    return mb


def build_flower_head_top(rng, kind):
    """A single flower head seen from above, centred at (0, 0), ~0.24 x 0.24 studs."""
    mb = ElementMesh()
    up = np.array([0.0, 0.0, 1.0])
    if kind == "daisy":
        daisy_head(mb, rng, np.zeros(3), up, 0.1, n=22)
    elif kind == "buttercup":
        for k in range(rng.randint(1, 3)):
            cup_flower(mb, rng, np.array([rng.normal(0, 0.03), rng.normal(0, 0.03), 0]), up + rng.normal(0, 0.2, 3),
                       0.045, C(226, 184, 34))
    elif kind == "knapweed":
        tuft_head(mb, rng, np.zeros(3), 0.042, C(84, 74, 46), C(184, 86, 166), n=70, up=up)
    elif kind == "yarrow":
        umbel(mb, rng, np.zeros(3), 0.1, C(226, 222, 206), n=70, up=up)
    elif kind == "clover":
        clover_head(mb, rng, np.zeros(3), 0.05, C(192, 112, 146))
    elif kind == "harebell":
        bell_flower(mb, rng, np.array([0, 0.07, 0]), 0.035, C(118, 124, 196))
    return mb


# =============================================================================================== sprigs / leaves
def twig(mb, pts, r0, r1, col):
    tube(mb, pts, np.linspace(r0, r1, len(pts)), col, 0.7, sides=4)


def leafy_sprig(rng, kind):
    """Top-view leaf spray, base at (0, 0), growing toward +Y. kinds: evergreen_a/b, broadleaf_a/b, currant,
    beech_a/b."""
    mb = ElementMesh()
    if kind.startswith("evergreen"):
        L, nside = 1.08, 7
        twig_col = C(92, 78, 54)
    elif kind.startswith("beech"):
        L, nside = 1.45, 4
        twig_col = C(104, 86, 66)
    elif kind == "currant":
        L, nside = 1.25, 4
        twig_col = C(110, 92, 70)
    else:
        L, nside = 1.25, 5
        twig_col = C(98, 82, 60)
    main, mdirs = spine_curve(np.array([0, 0.02, 0]), rng.normal(0, 0.08), L, rng.normal(0, 0.25), 12,
                              wobble=0.06 if kind.startswith("beech") else 0.02, rng=rng)
    twig(mb, main, 0.022, 0.006, twig_col)
    branches = [(main, mdirs, 1.0)]
    for b in range(nside):
        f = 0.2 + 0.6 * b / max(nside - 1, 1)
        i = int(f * 12)
        side = 1 if b % 2 else -1
        bl = L * rng.uniform(0.4, 0.6) * (1.1 - 0.5 * f)
        bp, bd = spine_curve(main[i], math.atan2(mdirs[i][0], mdirs[i][1]) + side * rng.uniform(0.7, 1.1), bl,
                             -side * rng.uniform(0.1, 0.4), 6)
        twig(mb, bp, 0.012, 0.004, twig_col)
        branches.append((bp, bd, bl / L))
    for (bp, bd, scale) in branches:
        n = len(bp)
        if kind.startswith("evergreen"):
            nleaf = int(26 * scale) + 6
            for j in range(nleaf):
                f = 0.08 + 0.92 * j / nleaf
                i = min(int(f * (n - 1)), n - 2)
                p = bp[i] + (bp[i + 1] - bp[i]) * (f * (n - 1) - i)
                d = bd[i]
                a = j * 2.4                                 # spiral phyllotaxis, flattened into the plane
                side = math.cos(a)
                ang = math.radians(rng.uniform(35, 60)) * (1 if side >= 0 else -1)
                o = _rot2(d[None, :2], -ang)[0]
                young = f > 0.78
                col = jitter_col(rng, C(84, 112, 52) if young else (C(44, 68, 36) if rng.random_sample() < 0.6
                                                                     else C(54, 80, 40)), 0.08, 0.03)
                leaf(mb, p, (o[0], o[1], rng.uniform(-0.15, 0.35) + 0.35 * math.sin(a)),
                     rng.uniform(0.085, 0.115) * (0.8 if young else 1.0), rng.uniform(0.038, 0.05),
                     shape="elliptic", color=col, color_edge=col * 0.8, rough=rng.uniform(0.32, 0.42), nlen=5,
                     ncross=5, cup=0.25, curl=-0.1, fold=0.15, roll=rng.uniform(-0.4, 0.4), vein=0.35, nvein=4,
                     petiole=0.008)
        elif kind.startswith("broadleaf"):
            nleaf = int(10 * scale) + 3
            for j in range(nleaf):
                f = 0.15 + 0.85 * j / nleaf
                i = min(int(f * (n - 1)), n - 2)
                p = bp[i]
                side = 1 if j % 2 else -1
                ang = math.radians(rng.uniform(40, 65)) * side
                o = _rot2(bd[i][None, :2], -ang)[0]
                base_c = C(80, 110, 44) if kind == "broadleaf_a" else C(92, 118, 48)
                col = jitter_col(rng, base_c, 0.08, 0.04)
                if rng.random_sample() < 0.12:
                    col = col + (C(160, 150, 64) - col) * 0.6
                leaf(mb, p, (o[0], o[1], rng.uniform(0.0, 0.3)), rng.uniform(0.17, 0.23), rng.uniform(0.1, 0.13),
                     shape="elliptic", color=col, color_tip=col * 1.05, rough=0.55, nlen=8, ncross=5, cup=0.15,
                     curl=rng.uniform(-0.15, 0.1), serr=0.08, serr_n=14, vein=0.8, nvein=7, petiole=0.03,
                     roll=rng.uniform(-0.25, 0.25), spots=(0.03, C(120, 100, 50)), rng=rng)
        elif kind == "currant":
            nleaf = int(6 * scale) + 3
            for j in range(nleaf):
                f = 0.2 + 0.8 * j / nleaf
                i = min(int(f * (n - 1)), n - 2)
                p = bp[i]
                side = 1 if j % 2 else -1
                o = _rot2(bd[i][None, :2], -side * math.radians(rng.uniform(40, 70)))[0]
                col = jitter_col(rng, C(82, 112, 46), 0.08, 0.04)
                center = p + np.array([o[0], o[1], 0.05]) * 0.06
                for lb in range(5):                  # palmate: five lobes from the petiole tip
                    a = (lb - 2) * 0.62 + rng.normal(0, 0.06)
                    ld = _rot2(np.array([o]), a)[0]
                    leaf(mb, center, (ld[0], ld[1], 0.12 - abs(lb - 2) * 0.05), 0.16 * (1.0 - abs(lb - 2) * 0.17),
                         0.11 * (1.0 - abs(lb - 2) * 0.12), shape="ovate", color=col, rough=0.6, nlen=6, ncross=5,
                         cup=0.18, serr=0.35, serr_n=6, vein=0.7, nvein=5)
        else:  # beech
            nleaf = int(11 * scale) + 3
            for j in range(nleaf):
                f = 0.1 + 0.9 * j / nleaf
                i = min(int(f * (n - 1)), n - 2)
                p = bp[i]
                side = 1 if j % 2 else -1
                o = _rot2(bd[i][None, :2], -side * math.radians(rng.uniform(35, 55)))[0]
                base_c = C(94, 122, 47) if kind == "beech_a" else C(98, 124, 48)
                col = jitter_col(rng, base_c, 0.07, 0.04)
                leaf(mb, p, (o[0], o[1], rng.uniform(-0.05, 0.2)), rng.uniform(0.22, 0.31), rng.uniform(0.13, 0.17),
                     shape="ovate", color=col, color_edge=col * 0.9, rough=0.5, nlen=9, ncross=5, cup=0.08,
                     curl=rng.uniform(-0.1, 0.1), serr=0.12, serr_n=8, vein=0.85, nvein=8, petiole=0.025,
                     roll=rng.uniform(-0.2, 0.2))
    return mb


def leaf_fill(rng, kind, size):
    """Dense opaque mass of leaves filling a size x size square centred at (0, 0) (bush interiors)."""
    mb = ElementMesh()
    half = size / 2 + 0.08
    n = 1100 if kind == "evergreen" else 420
    # dark backing so gaps read as deep shade, not holes
    mb.add(np.array([[-half, -half, -0.08], [half, -half, -0.08], [half, half, -0.08], [-half, half, -0.08]]),
           [(0, 1, 2, 3)], C(22, 30, 16), 0.8)
    for i in range(n):
        p = np.array([rng.uniform(-half, half), rng.uniform(-half, half), rng.uniform(-0.06, 0.04)])
        a = rng.uniform(0, 2 * math.pi)
        d = (math.cos(a), math.sin(a), rng.uniform(-0.3, 0.4))
        depth = (p[2] + 0.06) / 0.1
        if kind == "evergreen":
            col = jitter_col(rng, C(44, 68, 36) if rng.random_sample() < 0.7 else C(60, 88, 42), 0.1, 0.03)
            col = col * (0.45 + 0.55 * depth)
            leaf(mb, p, d, rng.uniform(0.08, 0.11), rng.uniform(0.038, 0.05), shape="elliptic", color=col,
                 rough=0.4, nlen=4, ncross=3, cup=0.25, vein=0.3, nvein=4)
        else:
            col = jitter_col(rng, C(80, 110, 44), 0.1, 0.04) * (0.45 + 0.55 * depth)
            leaf(mb, p, d, rng.uniform(0.15, 0.21), rng.uniform(0.09, 0.12), shape="elliptic", color=col,
                 rough=0.55, nlen=5, ncross=5, cup=0.15, vein=0.7, nvein=6)
    return mb


# =============================================================================================== moss, litter
def moss_patch(rng, rx, ry, ragged=True, palette="green", density=1.0):
    """Top view moss cushion inside an ellipse rx x ry (studs) centred at (0, 0) with a ragged edge."""
    mb = ElementMesh()
    pn = tg.Perlin(rng.randint(1 << 30))
    if palette == "green":
        cols = [C(92, 116, 40), C(124, 140, 50), C(70, 96, 34), C(54, 76, 30), C(104, 124, 46)]
    else:
        cols = [C(76, 98, 36), C(58, 82, 32), C(98, 112, 44), C(46, 66, 28), C(84, 102, 40)]
    # backing: soil/old moss under the tufts (only inside the main body so the rim stays ragged)
    ang = np.linspace(0, 2 * math.pi, 64, endpoint=False)
    edge_n = pn.fbm(np.stack([np.cos(ang) * 1.3, np.sin(ang) * 1.3, np.zeros_like(ang)], 1), 1.0, 3)
    rr = 0.84 + 0.22 * edge_n * (1 if ragged else 0.3)
    V = [np.array([0, 0, -0.02])] + [np.array([math.cos(a) * rx * r * 0.92, math.sin(a) * ry * r * 0.92, -0.02])
                                     for a, r in zip(ang, rr)]
    F = [(0, 1 + j, 1 + (j + 1) % 64) for j in range(64)]
    mb.add(np.array(V), F, C(40, 44, 22), 0.95)
    ntufts = int(5200 * density * (rx * ry) / 0.81)
    pts = rng.uniform(-1, 1, (ntufts * 2, 2))
    pts = pts[(pts ** 2).sum(1) < 1.0][:ntufts]
    th = np.arctan2(pts[:, 1], pts[:, 0])
    edge = np.interp(th % (2 * math.pi), np.append(ang, 2 * math.pi), np.append(rr, rr[0]))
    r = np.sqrt((pts ** 2).sum(1))
    P3 = np.stack([pts[:, 0] * rx * 2.2, pts[:, 1] * ry * 2.2, np.zeros(len(pts))], 1)
    clump = pn.fbm(P3, 1.0, 4)
    keep = r < edge * (1.0 + 0.12 * clump) + (rng.uniform(0, 1, len(r)) < 0.04) * 0.15
    for (x, y), cl, rv in zip(pts[keep], clump[keep], r[keep]):
        px, py = x * rx, y * ry
        h = 0.035 * (1.0 - (rv / 1.1) ** 2) + 0.01 * cl
        ci = int((cl * 0.5 + 0.5) * (len(cols) - 0.01)) % len(cols)
        col = jitter_col(rng, cols[ci], 0.12, 0.04)
        if rng.random_sample() < 0.04:
            col = C(112, 96, 56)
        base = np.array([px, py, h])
        nlv = 5
        a0 = rng.uniform(0, 2 * math.pi)
        for k in range(nlv):
            a = a0 + 2 * math.pi * k / nlv
            leaf(mb, base, (math.cos(a), math.sin(a), rng.uniform(0.2, 0.9)), rng.uniform(0.016, 0.026), 0.007,
                 shape="lanceolate", color=col * rng.uniform(0.85, 1.12), rough=0.9, nlen=2, ncross=3, cup=0.0,
                 fold=0.0, vein=0.0)
    return mb


def litter_patch(rng, rx, ry):
    """Fallen leaves and twigs (top view) for bush bases."""
    mb = ElementMesh()
    cols = [C(122, 86, 50), C(148, 110, 62), C(102, 74, 46), C(160, 128, 74), C(92, 70, 48), C(126, 104, 66)]
    for i in range(240):
        while True:
            x, y = rng.uniform(-1, 1, 2)
            if x * x + y * y < 1:
                break
        p = np.array([x * rx, y * ry, rng.uniform(0, 0.04)])
        a = rng.uniform(0, 2 * math.pi)
        col = jitter_col(rng, cols[rng.randint(len(cols))], 0.12, 0.05)
        if rng.random_sample() < 0.5:
            leaf(mb, p, (math.cos(a), math.sin(a), rng.uniform(-0.2, 0.2)), rng.uniform(0.12, 0.24),
                 rng.uniform(0.06, 0.12), shape="ovate", color=col, rough=0.75, nlen=6, ncross=5,
                 cup=rng.uniform(-0.3, 0.4), curl=rng.uniform(-0.3, 0.3), roll=rng.uniform(-0.5, 0.5), vein=0.7,
                 nvein=6, spots=(0.15, C(70, 50, 36)), rng=rng)
        else:
            leaf(mb, p, (math.cos(a), math.sin(a), 0.0), rng.uniform(0.06, 0.12), rng.uniform(0.015, 0.03),
                 shape="linear", color=C(120, 100, 64), rough=0.8, nlen=3, ncross=3, vein=0.2, nvein=2, vmode=1.0)
    for i in range(10):
        p0 = np.array([rng.uniform(-rx, rx) * 0.7, rng.uniform(-ry, ry) * 0.7, 0.03])
        a = rng.uniform(0, 2 * math.pi)
        p1 = p0 + np.array([math.cos(a), math.sin(a), 0]) * rng.uniform(0.2, 0.5)
        twig(mb, [p0, (p0 + p1) / 2 + np.array([0, 0, 0.01]), p1], 0.01, 0.005, C(96, 78, 58))
    return mb
