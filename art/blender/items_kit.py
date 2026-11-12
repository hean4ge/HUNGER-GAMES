"""
items_kit.py - private geometry helpers for the LAST STANDING "Items" category (driven by items.py).
Built on top of ls_common, which stays untouched. Every builder returns a plain mesh object that
items.py hands to Library.add() (via part()).
"""
import math

import bmesh
import bpy
from mathutils import Quaternion, Vector

import ls_common as ls

V = Vector
TAU = math.pi * 2.0


# ------------------------------------------------------------------ small maths
def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def curve(points, x):
    """Smooth monotone-ish cubic through sorted (x, y) control points, clamped at both ends."""
    n = len(points)
    if x <= points[0][0]:
        return points[0][1]
    if x >= points[-1][0]:
        return points[-1][1]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [d[0]]
    for i in range(1, n - 1):
        m.append(0.0 if d[i - 1] * d[i] <= 0 else (d[i - 1] + d[i]) / 2.0)
    m.append(d[-1])
    for i in range(n - 1):
        if x <= xs[i + 1]:
            h = xs[i + 1] - xs[i]
            t = (x - xs[i]) / h
            t2, t3 = t * t, t * t * t
            return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i]
                    + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1])
    return ys[-1]


# ------------------------------------------------------------------ mesh skinning
def _extent(row):
    p0 = V(row[0])
    return max((V(p) - p0).length for p in row)


def _face(bm, verts):
    try:
        return bm.faces.new(verts)
    except ValueError:
        return None


def grid_mesh(name, rows, close_u=True, close_v=False, cap_start=True, cap_end=True):
    """Skin rows[v][u] of points with quads. close_u wraps each row into a loop, close_v wraps the rows.
    Open ends of a looped grid get n-gon caps (skipped where a row collapses to a single point)."""
    bm = bmesh.new()
    grid = [[bm.verts.new(V(p)) for p in row] for row in rows]
    nv, nu = len(grid), len(grid[0])
    for j in range(nv if close_v else nv - 1):
        a, b = grid[j], grid[(j + 1) % nv]
        for i in range(nu if close_u else nu - 1):
            i2 = (i + 1) % nu
            _face(bm, (a[i], a[i2], b[i2], b[i]))
    if close_u and not close_v:
        if cap_start and _extent(rows[0]) > 1e-6:
            _face(bm, list(reversed(grid[0])))
        if cap_end and _extent(rows[-1]) > 1e-6:
            _face(bm, grid[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def place(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    ls.refresh()
    return obj


def baked(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Place and bake the transform into the mesh (so later joins/offsets stay simple)."""
    place(obj, loc, rot, scale)
    return ls.bake_transform(obj)


def shift(obj, offset):
    """Translate mesh data (object stays at identity)."""
    ls.bake_transform(obj)
    for v in obj.data.vertices:
        v.co += V(offset)
    obj.data.update()
    return obj


# ------------------------------------------------------------------ sections
def circle(n, r=1.0, phase=0.0):
    return [(r * math.cos(TAU * i / n + phase), r * math.sin(TAU * i / n + phase)) for i in range(n)]


def rrect(w, h, c):
    """Chamfered rectangle: 8 points, w along the first section axis, h along the second."""
    a, b = w / 2.0, h / 2.0
    c = min(c, a * 0.9, b * 0.9)
    return [(a, -b + c), (a, b - c), (a - c, b), (-a + c, b), (-a, b - c), (-a, -b + c), (-a + c, -b), (a - c, -b)]


def superellipse(n, a, b, p=2.5, phase=0.0):
    pts = []
    for i in range(n):
        t = TAU * i / n + phase
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2.0 / p), c), b * math.copysign(abs(s) ** (2.0 / p), s)))
    return pts


# ------------------------------------------------------------------ builders
def sweep(name, path, section, scale_fn=None, up=(1, 0, 0), cap_start=True, cap_end=True):
    """Sweep a closed 2D section [(a, b)] along a 3D polyline with parallel-transport frames.
    a runs along the frame normal (seeded from `up`), b along the binormal.
    scale_fn(t) -> (sa, sb) scales the section at normalised arc length t."""
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
    rows = []
    for i in range(n):
        if i > 0:
            axis = tangents[i - 1].cross(tangents[i])
            if axis.length > 1e-9:
                ang = tangents[i - 1].angle(tangents[i])
                nrm = Quaternion(axis.normalized(), ang) @ nrm
            nrm = (nrm - tangents[i] * nrm.dot(tangents[i])).normalized()
        binormal = tangents[i].cross(nrm)
        sa, sb = scale_fn(lengths[i] / total) if scale_fn else (1.0, 1.0)
        rows.append([pts[i] + nrm * (a * sa) + binormal * (b * sb) for (a, b) in section])
    return grid_mesh(name, rows, close_u=True, cap_start=cap_start, cap_end=cap_end)


def revolve(name, profile, segs=16, closed=False, r_fn=None, phase=0.0):
    """Revolve (r, z) points around Z. closed=True treats the profile as a loop (tubes, rings).
    r_fn(angle, z) -> radius multiplier (lobes, ridges)."""
    rows = []
    for (r, z) in profile:
        row = []
        for i in range(segs):
            a = TAU * i / segs + phase
            rr = r * (r_fn(a, z) if r_fn else 1.0)
            row.append((rr * math.cos(a), rr * math.sin(a), z))
        rows.append(row)
    return grid_mesh(name, rows, close_u=True, close_v=closed)


def hull(name, pts, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Convex hull of points with coplanar triangles merged back into clean n-gons."""
    bm = bmesh.new()
    verts = [bm.verts.new(V(p)) for p in pts]
    res = bmesh.ops.convex_hull(bm, input=verts, use_existing_faces=False)
    kill = [g for g in res.get("geom_interior", []) + res.get("geom_unused", []) if isinstance(g, bmesh.types.BMVert)]
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=list(bm.verts), edges=list(bm.edges))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return place(ls.from_bmesh(name, bm), loc, rot)


def chamfer_box(name, size, chamfer=0.03, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Box with every edge chamfered (catches light; 44 tris)."""
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    c = min(chamfer, hx * 0.49, hy * 0.49, hz * 0.49)
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts += [(sx * hx, sy * (hy - c), sz * (hz - c)), (sx * (hx - c), sy * hy, sz * (hz - c)),
                        (sx * (hx - c), sy * (hy - c), sz * hz)]
    return hull(name, pts, loc, rot)


def board(name, size, chamfer=0.03, axis=0, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Box whose 4 edges along `axis` are chamfered (8-sided prism, 28 tris): planks, rails, battens."""
    half = [s / 2.0 for s in size]
    o1, o2 = [i for i in range(3) if i != axis]
    c = min(chamfer, half[o1] * 0.45, half[o2] * 0.45)
    a, b = half[o1], half[o2]
    sec = [(a, b - c), (a - c, b), (-a + c, b), (-a, b - c), (-a, -b + c), (-a + c, -b), (a - c, -b), (a, -b + c)]
    pts = []
    for e in (-half[axis], half[axis]):
        for (p, q) in sec:
            v = [0.0, 0.0, 0.0]
            v[axis], v[o1], v[o2] = e, p, q
            pts.append(v)
    return hull(name, pts, loc, rot)


def rect_frame(name, outer, inner, z0, z1):
    """Flat rectangular ring (outer w, d) minus (inner w, d), from z0 to z1."""
    def loop(w, d, z):
        a, b = w / 2.0, d / 2.0
        return [(a, b, z), (-a, b, z), (-a, -b, z), (a, -b, z)]
    rows = [loop(outer[0], outer[1], z0), loop(outer[0], outer[1], z1),
            loop(inner[0], inner[1], z1), loop(inner[0], inner[1], z0)]
    return grid_mesh(name, rows, close_u=True, close_v=True)


def wrap_grip(name, z0, z1, rx, ry, bands=6, bulge=0.010, tilt_deg=14.0, segs=8, flare=None, offset=(0, 0)):
    """Leather/cord wrapped grip around Z: creased, slightly tilted bands that read as a spiral wrap.
    flare(t) scales the radius along the grip (t = 0 bottom, 1 top)."""
    rows = []
    rings = bands * 2 + 1
    tilt = math.tan(math.radians(tilt_deg)) * 0.7071
    for k in range(rings):
        t = k / (rings - 1)
        z = lerp(z0, z1, t)
        s = 1.0 if k % 2 == 0 else 1.0 + bulge / max(min(rx, ry), 1e-3)
        f = flare(t) if flare else 1.0
        end = k == 0 or k == rings - 1
        row = []
        for i in range(segs):
            a = TAU * i / segs
            x = rx * f * s * math.cos(a)
            y = ry * f * s * math.sin(a)
            dz = 0.0 if end else tilt * (x + y)
            row.append((x + offset[0], y + offset[1], z + dz))
        rows.append(row)
    return grid_mesh(name, rows, close_u=True)


def stations(z0, z1, n, back_fn, front_fn, power=1.0):
    """Blade stations (z, y_back, y_front, s) with s in 0..1; power > 1 packs stations toward the tip."""
    out = []
    for k in range(n + 1):
        t = k / n
        s = 1.0 - (1.0 - t) ** power
        out.append((lerp(z0, z1, s), back_fn(s), front_fn(s), s))
    return out


def slab_loft(sts, hx_fn, across=(0.0, 1.0), grind_front=0.0, grind_back=0.0,
              edge_half=0.006, overlap=0.004, band_inset=0.94, grind_frac=0.42):
    """Blade-like solid sliced horizontally. sts: [(z, y_back, y_front, s)] bottom -> top; thickness along X.
    hx_fn(s, u, y) = half thickness across the body (u 0 = back boundary, 1 = front boundary).
    The ground edge (grind) becomes separate thin wedge bands so it can take a darker material.
    Returns ring lists (body, front_band | None, back_band | None) for grid_mesh."""
    body, front, back = [], [], []
    nb = 2 * len(across)
    both = bool(grind_front and grind_back)
    for (z, yb, yf, s) in sts:
        w = yf - yb
        if w < 1e-4:
            p = (0.0, 0.5 * (yb + yf), z)
            body.append([p] * nb)
            front.append([p] * 4)
            back.append([p] * 4)
            continue
        frac = grind_frac * (0.72 if both else 1.0)
        gf = min(grind_front, frac * w) if grind_front else 0.0
        gb = min(grind_back, frac * w) if grind_back else 0.0
        y0, y1 = yb + gb, yf - gf
        top, bot = [], []
        for u in across:
            y = lerp(y0, y1, u)
            hx = max(hx_fn(s, u, y), 0.0015)
            top.append((hx, y, z))
            bot.append((-hx, y, z))
        body.append(top + bot[::-1])
        ov = min(overlap, 0.45 * (y1 - y0))
        if grind_front:
            hb = max(hx_fn(s, 1.0, y1) * band_inset, edge_half)
            front.append([(hb, y1 - ov, z), (edge_half, yf, z), (-edge_half, yf, z), (-hb, y1 - ov, z)])
        if grind_back:
            hb = max(hx_fn(s, 0.0, y0) * band_inset, edge_half)
            back.append([(-hb, y0 + ov, z), (-edge_half, yb, z), (edge_half, yb, z), (hb, y0 + ov, z)])
    return body, (front if grind_front else None), (back if grind_back else None)


def blade(name, sts, hx_fn, across=(0.0, 1.0), grind_front=0.0, grind_back=0.0, edge_half=0.006):
    """(body, edges) meshes: the Steel body and the Metal ground edge band(s) (joined when double-edged)."""
    b, f, k = slab_loft(sts, hx_fn, across, grind_front, grind_back, edge_half)
    body = grid_mesh(name + "_body", b)
    bands = []
    if f:
        bands.append(grid_mesh(name + "_edgeF", f))
    if k:
        bands.append(grid_mesh(name + "_edgeB", k))
    edges = None
    if len(bands) == 1:
        edges = bands[0]
    elif bands:
        edges = ls.join(bands, name + "_edges")
    return body, edges


def leaf(name, length, width, thick=0.016, tip_curl=0.0):
    """Leaf outline in the XZ plane pointing +Z (base at origin), thickness along Y."""
    pts = [(0.0, 0.0), (width * 0.30, length * 0.12), (width * 0.5, length * 0.42), (width * 0.30, length * 0.75),
           (0.0, length), (-width * 0.30, length * 0.75), (-width * 0.5, length * 0.42), (-width * 0.30, length * 0.12)]
    obj = ls.extrude_profile(name, pts, thick)
    if tip_curl:
        for v in obj.data.vertices:
            t = max(v.co.z, 0.0) / length
            v.co.y += tip_curl * t * t
        obj.data.update()
    return obj


def rod(name, r, length, segs=8, center=(0, 0, 0), axis="Z", r_top=None):
    """Cylinder centred on `center` along X, Y or Z."""
    obj = ls.cylinder(name, radius=r, depth=length, segments=segs, radius_top=r_top)
    for v in obj.data.vertices:
        v.co.z -= length / 2.0
    obj.data.update()
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    return place(obj, center, rot)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    return ls.join(objs, name)


# ------------------------------------------------------------------ library glue
class ItemLibrary(ls.Library):
    """Library aware of hand-held items: their grip sits at the origin by design, so extending below z = 0
    is expected for them and is reported as a NOTE (not a WARNING). Also renames lid parts."""

    def __init__(self, category):
        super().__init__(category)
        self.held = set()
        self.notes = []

    def begin_held(self, name, kind, tags=None, notes=""):
        root = self.begin(name, kind, tags, notes)
        self.held.add(name)
        return root

    def finish(self, root):
        before = len(self.warnings)
        entry = super().finish(root)
        if root.name in self.held:
            fresh = self.warnings[before:]
            del self.warnings[before:]
            for w in fresh:
                if "below z = 0" in w:
                    note = w + " [held item: grip at origin by convention]"
                    self.notes.append(note)
                    print("NOTE " + note)
                else:
                    self.warnings.append(w)
        print("ASSET %-14s tris=%5d size=%s parts=%d" % (entry["name"], entry["tris"], entry["size"], len(entry["parts"])))
        return entry

    def _setup_preview_scene(self):
        """Preview-only tweaks (the GLB is untouched): drop the preview ground 4 mm so bases resting on z = 0
        don't z-fight with it, and lower the Workbench viewport metallic of metal roles so Steel/Metal/Tin read
        as the light-grey metal Roblox renders instead of studio-black mirrors."""
        scene, cam, ground = super()._setup_preview_scene()
        if not ground.get("items_lowered"):
            for v in ground.data.vertices:
                v.co.z -= 0.004
            ground.data.update()
            ground["items_lowered"] = True
        for mat in bpy.data.materials:
            if mat.metallic > 0.5:
                mat.metallic = 0.3
                mat.roughness = max(mat.roughness, 0.4)
        return scene, cam, ground

    def render_preview(self, roots, path, elevation_deg=25, azimuth_deg=35, margin=1.15):
        """Tall single assets (spear, bow, swords, vests) get a wider margin: the base framing fits the bounding
        sphere to the horizontal FOV, which crops tall items in the 4:3 frame."""
        if len(roots) == 1:
            meshes = [c for c in roots[0].children_recursive if c.type == "MESH"]
            lo, hi = ls.world_bounds(meshes)
            d = hi - lo
            if d.z > max(d.x, d.y):
                margin *= 1.3
        return super().render_preview(roots, path, elevation_deg, azimuth_deg, margin)

    def rename(self, root, obj, new_name):
        entry = self._entry(root)
        for p in entry["parts"]:
            if p["name"] == obj.name:
                p["name"] = new_name
        obj.name = new_name
        obj.data.name = new_name
        if obj.name != new_name:
            raise ValueError("object name clash: " + new_name)
        return obj


def part(lib, root, obj, role, rgb=None, smooth=None, shadow=True, tags=None, collide=False, collision="Box"):
    """Items default: no collision (carried/displayed), Box fidelity for cheap queries."""
    return lib.add(root, obj, role, rgb=rgb, collide=collide, collision=collision, cast_shadow=shadow,
                   tags=tags, smooth_angle=smooth)


def grip(lib, root, extra=None):
    lib.attach(root, "Grip", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))
