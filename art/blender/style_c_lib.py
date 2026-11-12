"""
style_c_lib.py - shared helpers for the Variant C style test ("smooth stylized realism"), Blender 5.3 headless.

Used by style_c.py and its style_c_*.py modules. Read-only use of tex_ground (PNG writer, push-pull, noise).

Contents
- SDF sculpting: round cones, (half-)ellipsoids, spheres, round boxes, custom fields, combined with polynomial
  smooth-min / smooth-max, optional fBm displacement; block-culled grid sampling -> surface nets -> projection ->
  mesh -> decimation (closed, watertight, soft volumes: "sculpted clumps, not cards")
- mesh helpers (numpy -> bpy, triangulate, smooth shading, decimate, transforms)
- UVs: multi-object smart project + average scale + pack into one page (optionally into a sub-rectangle)
- bakes: per-part bake materials (object position, normal, pointiness, AO near/far, procedural detail height,
  tangent-space normal from the same detail through a Bump node) into float images -> numpy
- painting helpers: sRGB ramps, linear/sRGB, push-pull fill, PNG writers (colour / normal / roughness / packed MR)
"""
import math
import os
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import tex_ground as tg

FAR = 1.0e3
TAU = 2.0 * math.pi


def log(*a):
    print(*a, flush=True)


# =============================================================================================== SDF primitives
def smin(a, b, k):
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def sd_round_cone(P, a, b, r1, r2):
    """Exact SDF of a round cone (sphere r1 at a swept to sphere r2 at b) - Inigo Quilez's formulation."""
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = P - a
    y = pa @ ba
    z = y - l2
    q = pa * l2 - y[:, None] * ba
    x2 = np.einsum("ij,ij->i", q, q)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d1 = np.sqrt(x2 + z2) * il2 - r2
    d2 = np.sqrt(x2 + y2) * il2 - r1
    d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))


def sd_ellipsoid(L, r):
    """Approximate ellipsoid SDF (local coordinates L, radii r: (3,) or (N, 3))."""
    k0 = np.linalg.norm(L / r, axis=1)
    k1 = np.linalg.norm(L / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_round_box(L, half, rad):
    q = np.abs(L) - (np.asarray(half) - rad)
    return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - rad


def rot_from_z(direction, roll=0.0):
    """3x3 rotation whose local Z axis points along direction (columns = local axes in world)."""
    d = Vector(direction).normalized()
    q = d.to_track_quat("Z", "Y")
    m = q.to_matrix()
    if roll:
        m = m @ Matrix.Rotation(roll, 3, "Z")
    return np.array(m)


def rot_from_x(direction, up=(0, 0, 1)):
    """Rotation whose local X axis points along direction and local Z is as close to 'up' as possible."""
    x = np.asarray(direction, float)
    x = x / np.linalg.norm(x)
    u = np.asarray(up, float)
    y = np.cross(u, x)
    if np.linalg.norm(y) < 1e-6:
        y = np.cross(np.array([0.0, 1.0, 0.0]), x)
    y /= np.linalg.norm(y)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


class SDF:
    """A list of primitives folded left to right with smooth union / subtraction / intersection, plus optional
    fBm displacement near the surface. Evaluation is culled per spatial block, so fields with hundreds of
    primitives stay fast."""

    def __init__(self, block=3.0):
        self.prims = []
        self.noise = []          # (amp, freq, octaves, seed, offset)
        self.block = block
        self._lo = None
        self._hi = None
        self._k = None

    # ---------------------------------------------------------------- building
    def add(self, kind, params, lo, hi, k=0.3, op="union"):
        self.prims.append({"kind": kind, "params": params, "lo": np.asarray(lo, float),
                           "hi": np.asarray(hi, float), "k": float(k), "op": op})
        self._lo = None

    def round_cone(self, a, b, r1, r2, k=0.3, squash=1.0, op="union"):
        a = np.asarray(a, float)
        b = np.asarray(b, float)
        L = float(np.linalg.norm(b - a))
        if L < 1e-3:
            b = a + np.array([0.0, 0.0, 1e-3])
            L = 1e-3
        if abs(r1 - r2) > 0.96 * L:
            m = 0.5 * (r1 + r2)
            dd = 0.48 * L * np.sign(r1 - r2)
            r1, r2 = m + dd, m - dd
        r = max(r1, r2)
        lo = np.minimum(a, b) - r
        hi = np.maximum(a, b) + r
        cz = 0.5 * (a[2] + b[2])
        if squash != 1.0:
            lo[2] = cz + (lo[2] - cz) * squash
            hi[2] = cz + (hi[2] - cz) * squash
        self.add("rcone", (a, b, float(r1), float(r2), float(squash), cz), lo, hi, k, op)

    def chain(self, pts, radii, k=0.3, squash=1.0, op="union"):
        """Round-cone polyline (a branch or a bough)."""
        for i in range(len(pts) - 1):
            self.round_cone(pts[i], pts[i + 1], radii[i], radii[i + 1], k, squash, op)

    def ellipsoid(self, c, radii, rot=None, k=0.3, rz_bottom=None, op="union"):
        c = np.asarray(c, float)
        radii = np.asarray(radii, float)
        R = np.eye(3) if rot is None else np.asarray(rot, float)
        rzb = float(radii[2] if rz_bottom is None else rz_bottom)
        ext = np.abs(R) @ np.array([radii[0], radii[1], max(radii[2], rzb)])
        self.add("ellip", (c, R, radii, rzb), c - ext, c + ext, k, op)

    def sphere(self, c, r, k=0.3, op="union"):
        c = np.asarray(c, float)
        self.add("sphere", (c, float(r)), c - r, c + r, k, op)

    def round_box(self, c, half, rad, rot=None, k=0.1, op="union"):
        c = np.asarray(c, float)
        half = np.asarray(half, float)
        R = np.eye(3) if rot is None else np.asarray(rot, float)
        ext = np.abs(R) @ half
        self.add("rbox", (c, R, half, float(rad)), c - ext, c + ext, k, op)

    def func(self, f, lo, hi, k=0.0, op="union"):
        self.add("func", f, lo, hi, k, op)

    def displace(self, amp, freq, octaves=3, seed=0, offset=(0.0, 0.0, 0.0)):
        self.noise.append((float(amp), float(freq), int(octaves), tg.Perlin(seed), offset))

    # ---------------------------------------------------------------- evaluation
    def _tables(self):
        if self._lo is None:
            self._lo = np.array([p["lo"] for p in self.prims])
            self._hi = np.array([p["hi"] for p in self.prims])
            self._k = np.array([p["k"] for p in self.prims])
        return self._lo, self._hi, self._k

    def noise_amp(self):
        return sum(n[0] for n in self.noise)

    def select(self, blo, bhi, pad=0.0):
        lo, hi, k = self._tables()
        m = (k + pad)[:, None]
        ok = np.all(lo - m <= bhi, axis=1) & np.all(hi + m >= blo, axis=1)
        return np.nonzero(ok)[0]

    def _prim(self, p, Q):
        kind = p["kind"]
        prm = p["params"]
        if kind == "rcone":
            a, b, r1, r2, sq, cz = prm
            if sq != 1.0:
                Q = Q.copy()
                Q[:, 2] = cz + (Q[:, 2] - cz) / sq
                return sd_round_cone(Q, a, b, r1, r2) * min(sq, 1.0)
            return sd_round_cone(Q, a, b, r1, r2)
        if kind == "ellip":
            c, R, radii, rzb = prm
            L = (Q - c) @ R
            if rzb != radii[2]:
                rr = np.empty_like(L)
                rr[:, 0] = radii[0]
                rr[:, 1] = radii[1]
                rr[:, 2] = np.where(L[:, 2] < 0.0, rzb, radii[2])
                return sd_ellipsoid(L, rr)
            return sd_ellipsoid(L, radii)
        if kind == "sphere":
            c, r = prm
            return np.linalg.norm(Q - c, axis=1) - r
        if kind == "rbox":
            c, R, half, rad = prm
            return sd_round_box((Q - c) @ R, half, rad)
        if kind == "func":
            return prm(Q)
        raise ValueError(kind)

    def eval_sel(self, Q, sel):
        d = np.full(len(Q), FAR)
        for j in sel:
            p = self.prims[j]
            dj = self._prim(p, Q)
            op = p["op"]
            if op == "union":
                d = smin(d, dj, p["k"])
            elif op == "subtract":
                d = smax(d, -dj, p["k"])
            else:
                d = smax(d, dj, p["k"])
        if self.noise:
            near = np.abs(d) < 3.0 * self.noise_amp() + 0.5
            if near.any():
                P = Q[near]
                add = np.zeros(len(P))
                for (amp, freq, octv, per, off) in self.noise:
                    add += amp * per.fbm(P, freq, octv, offset=off)
                d[near] += add
        return d

    def eval(self, P):
        """Arbitrary points (N, 3): grouped by block, each block evaluated with its culled primitive list."""
        P = np.asarray(P, float)
        out = np.full(len(P), FAR)
        if not self.prims or not len(P):
            return out
        B = self.block
        keys = np.floor(P / B).astype(np.int64)
        uniq, inv = np.unique(keys, axis=0, return_inverse=True)
        inv = inv.ravel()
        order = np.argsort(inv, kind="stable")
        bounds = np.searchsorted(inv[order], np.arange(len(uniq) + 1))
        pad = self.noise_amp() + 0.25
        for bi in range(len(uniq)):
            idx = order[bounds[bi]:bounds[bi + 1]]
            if not len(idx):
                continue
            blo = uniq[bi] * B
            sel = self.select(blo, blo + B, pad)
            if len(sel):
                out[idx] = self.eval_sel(P[idx], sel)
        return out

    def sample_grid(self, lo, hi, h, bc=28):
        lo = np.asarray(lo, float)
        hi = np.asarray(hi, float)
        shape = (np.ceil((hi - lo) / h).astype(int) + 1)
        F = np.full(tuple(shape), FAR, np.float32)
        pad = self.noise_amp() + 2.5 * h + 0.1
        axes = [lo[i] + np.arange(shape[i]) * h for i in range(3)]
        for i0 in range(0, shape[0], bc):
            i1 = min(i0 + bc, shape[0])
            for j0 in range(0, shape[1], bc):
                j1 = min(j0 + bc, shape[1])
                for k0 in range(0, shape[2], bc):
                    k1 = min(k0 + bc, shape[2])
                    blo = np.array([axes[0][i0], axes[1][j0], axes[2][k0]])
                    bhi = np.array([axes[0][i1 - 1], axes[1][j1 - 1], axes[2][k1 - 1]])
                    sel = self.select(blo, bhi, pad)
                    if not len(sel):
                        continue
                    X, Y, Z = np.meshgrid(axes[0][i0:i1], axes[1][j0:j1], axes[2][k0:k1], indexing="ij")
                    Q = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
                    F[i0:i1, j0:j1, k0:k1] = self.eval_sel(Q, sel).reshape(X.shape)
        return F, lo


# =============================================================================================== mesh helpers
def apply_modifiers(obj):
    if not obj.modifiers:
        return obj
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def clean_mesh(obj, dist=1e-5, recalc=True):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=dist)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def keep_largest_parts(obj, min_tris=60):
    """Drop tiny disconnected islands (surface-nets specks)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    drop = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        comp = []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for g2 in e.link_faces:
                    if g2.index not in seen:
                        seen.add(g2.index)
                        stack.append(g2)
        if len(comp) < min_tris:
            drop += comp
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(drop)


def decimate_to(obj, target):
    t = tri_count(obj)
    if t <= target:
        return obj
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.001, target / float(t))
    mod.use_collapse_triangulate = True
    apply_modifiers(obj)
    return obj


def smooth_shade(obj, flat=False):
    me = obj.data
    vals = np.full(len(me.polygons), not flat, dtype=bool)
    me.polygons.foreach_set("use_smooth", vals)
    me.update()
    return obj


def laplacian(obj, factor=0.5, iters=1):
    mod = obj.modifiers.new("sm", "SMOOTH")
    mod.factor = factor
    mod.iterations = iters
    apply_modifiers(obj)
    return obj


def link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def sdf_mesh(name, sdf, lo, hi, h, target_tris=None, project=True, smooth_iters=0, min_island=80):
    t0 = time.time()
    F, origin = sdf.sample_grid(lo, hi, h)
    t1 = time.time()
    verts, quads = tg.surface_nets(F, origin, h)
    if project and len(verts):
        verts = tg.project_to_sdf(verts, sdf.eval, iters=2, eps=h * 0.1, max_move=h * 0.7)
    obj = tg.mesh_object(name, verts, quads)
    clean_mesh(obj)
    keep_largest_parts(obj, min_island)
    if smooth_iters:
        laplacian(obj, 0.5, smooth_iters)
    triangulate(obj)
    raw = tri_count(obj)
    if target_tris:
        decimate_to(obj, target_tris)
    clean_mesh(obj)
    smooth_shade(obj)
    log("SDFMESH %-22s grid %s h=%.3f  sample %.1fs  mesh %.1fs  %d -> %d tris" % (
        name, "x".join(str(s) for s in F.shape), h, t1 - t0, time.time() - t1, raw, tri_count(obj)))
    return obj


def numpy_verts(obj):
    co = np.empty(len(obj.data.vertices) * 3, np.float32)
    obj.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3).astype(np.float64)


def set_verts(obj, co):
    obj.data.vertices.foreach_set("co", np.asarray(co, np.float32).ravel())
    obj.data.update()


def bounds(objs):
    lo = np.array([1e9] * 3)
    hi = np.array([-1e9] * 3)
    for o in objs:
        co = numpy_verts(o)
        if len(co):
            lo = np.minimum(lo, co.min(0))
            hi = np.maximum(hi, co.max(0))
    return lo, hi


def mesh_area(obj):
    return sum(p.area for p in obj.data.polygons)


# =============================================================================================== UVs
def select_only(objs, active=None):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def smart_uv(objs, angle=60.0, margin=0.004):
    select_only(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def pack(objs, margin=0.004, rotate=True):
    select_only(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    try:
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=rotate, margin_method="FRACTION", margin=margin,
                                shape_method="CONCAVE", scale=True)
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=rotate, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_transform(obj, su=1.0, sv=1.0, ou=0.0, ov=0.0):
    uv = obj.data.uv_layers.active.data
    a = np.empty(len(uv) * 2, np.float32)
    uv.foreach_get("uv", a)
    a = a.reshape(-1, 2)
    a[:, 0] = a[:, 0] * su + ou
    a[:, 1] = a[:, 1] * sv + ov
    uv.foreach_set("uv", a.ravel())


def unwrap_page(objs, angle=60.0, margin=0.004, rect=None):
    """Smart-project every object, equalise island scale across them and pack into one page. rect = (u0, v0, u1,
    v1) packs into a sub-rectangle (islands are pre-squashed so the packer fills the rectangle's aspect, rotation
    off so the squash can be undone exactly)."""
    smart_uv(objs, angle, margin)
    if rect is None:
        pack(objs, margin)
        return
    u0, v0, u1, v1 = rect
    aspect = (u1 - u0) / (v1 - v0)
    select_only(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        uv_transform(o, 1.0 / aspect, 1.0)
    select_only(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    try:
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=False, margin_method="FRACTION",
                                margin=margin, shape_method="CONCAVE", scale=True)
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=False, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        uv_transform(o, u1 - u0, v1 - v0, u0, v0)


def texel_density(objs, res):
    a3 = 0.0
    auv = 0.0
    for o in objs:
        me = o.data
        uv = me.uv_layers.active.data
        for p in me.polygons:
            a3 += p.area
            pts = [uv[li].uv for li in p.loop_indices]
            s = 0.0
            for i in range(1, len(pts) - 1):
                s += abs((pts[i].x - pts[0].x) * (pts[i + 1].y - pts[0].y)
                         - (pts[i + 1].x - pts[0].x) * (pts[i].y - pts[0].y)) * 0.5
            auv += s
    return math.sqrt(auv * res * res / max(a3, 1e-9))


# =============================================================================================== node helper
class NT:
    def __init__(self, mat):
        self.mat = mat
        self.nt = mat.node_tree
        self.nodes = self.nt.nodes
        self.links = self.nt.links

    def n(self, kind, **props):
        node = self.nodes.new(kind)
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def link(self, a, b):
        self.links.new(a, b)

    def _in(self, sock, v):
        if hasattr(v, "is_output") or (hasattr(v, "node") and hasattr(v, "links")):
            self.links.new(v, sock)
        else:
            sock.default_value = v

    def math(self, op, a, b=None, c=None, clamp=False):
        m = self.n("ShaderNodeMath")
        m.operation = op
        m.use_clamp = clamp
        self._in(m.inputs[0], a)
        if b is not None:
            self._in(m.inputs[1], b)
        if c is not None:
            self._in(m.inputs[2], c)
        return m.outputs[0]

    def vmath(self, op, a, b=None, c=None):
        m = self.n("ShaderNodeVectorMath")
        m.operation = op
        self._in(m.inputs[0], a)
        if b is not None:
            self._in(m.inputs[1], b)
        if c is not None:
            self._in(m.inputs[2], c)
        return m.outputs[0] if op not in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else m.outputs["Value"]

    def maprange(self, v, a0, a1, b0=0.0, b1=1.0, clamp=True, interp="LINEAR"):
        m = self.n("ShaderNodeMapRange")
        m.interpolation_type = interp
        m.clamp = clamp
        self._in(m.inputs["Value"], v)
        m.inputs["From Min"].default_value = a0
        m.inputs["From Max"].default_value = a1
        m.inputs["To Min"].default_value = b0
        m.inputs["To Max"].default_value = b1
        return m.outputs["Result"]

    def combine(self, x, y, z):
        c = self.n("ShaderNodeCombineXYZ")
        self._in(c.inputs[0], x)
        self._in(c.inputs[1], y)
        self._in(c.inputs[2], z)
        return c.outputs[0]

    def mapping(self, vec, scale=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0)):
        m = self.n("ShaderNodeMapping")
        self._in(m.inputs["Vector"], vec)
        m.inputs["Scale"].default_value = scale
        m.inputs["Location"].default_value = loc
        m.inputs["Rotation"].default_value = rot
        return m.outputs[0]

    def voronoi(self, vec, scale, feature="F1", metric="EUCLIDEAN", rand=1.0, out="Distance"):
        v = self.n("ShaderNodeTexVoronoi")
        v.feature = feature
        v.distance = metric
        self._in(v.inputs["Vector"], vec)
        v.inputs["Scale"].default_value = scale
        v.inputs["Randomness"].default_value = rand
        return v.outputs[out]

    def noise(self, vec, scale, detail=2.0, rough=0.5, distortion=0.0, out="Fac"):
        v = self.n("ShaderNodeTexNoise")
        self._in(v.inputs["Vector"], vec)
        v.inputs["Scale"].default_value = scale
        v.inputs["Detail"].default_value = detail
        v.inputs["Roughness"].default_value = rough
        v.inputs["Distortion"].default_value = distortion
        return v.outputs[out]


# =============================================================================================== bakes
def enable_gpu(scene):
    return tg.enable_gpu(scene)


def new_float_image(name, res, color=(0, 0, 0, 0)):
    im = bpy.data.images.get(name)
    if im is not None:
        bpy.data.images.remove(im)
    im = bpy.data.images.new(name, res, res, alpha=True, float_buffer=True)
    im.colorspace_settings.name = "Non-Color"
    im.generated_color = color
    return im


def image_np(im):
    w, h = im.size
    buf = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4).astype(np.float64)


class Baker:
    """Bakes data passes for a set of part objects that share ONE UV page.

    parts: list of (obj, detail) where detail = function(nt, obj_coord_socket) -> (height_socket, aux_socket,
    bump_strength, bump_distance). Passes return H x W x 4 float arrays (row 0 = V 0)."""

    def __init__(self, parts, res, lo, hi, occluders=(), ground_z=0.0, ground=True):
        self.parts = parts
        self.res = res
        self.lo = np.asarray(lo, float) - 0.01
        self.hi = np.asarray(hi, float) + 0.01
        self.scene = bpy.context.scene
        self.scene.render.engine = "CYCLES"
        self.device = enable_gpu(self.scene)
        if self.scene.world is None:
            self.scene.world = bpy.data.worlds.new("SC_BakeWorld")
        self.objs = [p[0] for p in parts]
        self.image = new_float_image("SC_bake", res)
        self.mats = []
        self.temp = []
        self._sock = {}
        if ground:
            me = bpy.data.meshes.new("SC_bake_ground")
            s = 200.0
            me.from_pydata([(-s, -s, ground_z), (s, -s, ground_z), (s, s, ground_z), (-s, s, ground_z)], [],
                           [(0, 1, 2, 3)])
            g = bpy.data.objects.new("SC_bake_ground", me)
            link(g)
            self.temp.append(g)
        for pi, (obj, detail) in enumerate(parts):
            self.mats.append(self._material(obj, detail, pi))

    def _material(self, obj, detail, pid):
        mat = bpy.data.materials.new("SC_bake_%s" % obj.name)
        mat.use_nodes = True
        nt = NT(mat)
        nt.nodes.clear()
        tc = nt.n("ShaderNodeTexCoord")
        geo = nt.n("ShaderNodeNewGeometry")
        span = self.hi - self.lo
        pos = nt.vmath("MULTIPLY_ADD", geo.outputs["Position"], tuple(1.0 / span), tuple(-self.lo / span))
        nrm = nt.vmath("MULTIPLY_ADD", geo.outputs["Normal"], (0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
        h, aux, bs, bd = detail(nt, tc.outputs["Object"])
        det = nt.combine(h, aux, (pid + 0.5) / 16.0)
        pnt = nt.combine(geo.outputs["Pointiness"], 0.0, 0.0)
        emit = nt.n("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 1.0
        bsdf = nt.n("ShaderNodeBsdfPrincipled")
        bump = nt.n("ShaderNodeBump")
        bump.inputs["Strength"].default_value = bs
        bump.inputs["Distance"].default_value = bd
        nt._in(bump.inputs["Height"], h)
        nt.link(bump.outputs["Normal"], bsdf.inputs["Normal"])
        out = nt.n("ShaderNodeOutputMaterial")
        img = nt.n("ShaderNodeTexImage")
        img.image = self.image
        nt.nodes.active = img
        self._sock[mat.name] = {"POS": pos, "NRM": nrm, "DET": det, "PNT": pnt, "emit": emit, "bsdf": bsdf,
                                "out": out, "img": img}
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        return mat

    def _route(self, which):
        for m in self.mats:
            s = self._sock[m.name]
            nt = m.node_tree
            for l in list(s["out"].inputs["Surface"].links):
                nt.links.remove(l)
            for l in list(s["emit"].inputs["Color"].links):
                nt.links.remove(l)
            if which == "NORMAL":
                nt.links.new(s["bsdf"].outputs[0], s["out"].inputs["Surface"])
            else:
                if which in s:
                    nt.links.new(s[which], s["emit"].inputs["Color"])
                else:
                    s["emit"].inputs["Color"].default_value = (1, 1, 1, 1)
                nt.links.new(s["emit"].outputs[0], s["out"].inputs["Surface"])
            s["img"].image = self.image
            nt.nodes.active = s["img"]

    def bake(self, which, samples=4, ao_distance=None):
        t = time.time()
        self.image = new_float_image("SC_bake_%s" % which, self.res)
        self._route(which)
        sc = self.scene
        sc.cycles.samples = samples
        sc.cycles.use_denoising = False
        b = sc.render.bake
        b.use_selected_to_active = False
        b.margin = 0
        b.use_clear = False
        b.target = "IMAGE_TEXTURES"
        select_only(self.objs)
        if which == "NORMAL":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y",
                                normal_b="POS_Z", margin=0, use_clear=False, target="IMAGE_TEXTURES")
        elif which == "AO":
            sc.world.light_settings.distance = ao_distance
            bpy.ops.object.bake(type="AO", margin=0, use_clear=False, target="IMAGE_TEXTURES")
        else:
            bpy.ops.object.bake(type="EMIT", margin=0, use_clear=False, target="IMAGE_TEXTURES")
        a = image_np(self.image)
        log("BAKE %-6s %s %4d spp %5.1fs" % (which, "" if ao_distance is None else "d=%.2f" % ao_distance,
                                              samples, time.time() - t))
        return a

    def run(self, ao_near, ao_far, ao_samples=48):
        cov = self.bake("COVER", 1)
        out = {
            "cover": cov[..., 0] > 0.5,
            "pos": self.bake("POS", 1)[..., :3] * (self.hi - self.lo) + self.lo,
            "nrm": self.bake("NRM", 1)[..., :3] * 2.0 - 1.0,
            "det": self.bake("DET", 1)[..., :3],
            "pnt": self.bake("PNT", 4)[..., 0],
            "ao1": self.bake("AO", ao_samples, ao_near)[..., 0],
            "ao2": self.bake("AO", ao_samples, ao_far)[..., 0],
            "tnrm": self.bake("NORMAL", 4)[..., :3],
        }
        n = out["nrm"]
        out["nrm"] = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
        out["pid"] = np.floor(out["det"][..., 2] * 16.0).astype(int)
        return out

    def cleanup(self):
        for o in self.temp:
            bpy.data.objects.remove(o, do_unlink=True)
        for o in self.objs:
            o.data.materials.clear()
        for m in self.mats:
            bpy.data.materials.remove(m)


# =============================================================================================== painting
def srgb2lin(c):
    return tg.srgb_to_lin(c)


def lin2srgb(c):
    return tg.lin_to_srgb(c)


def C(r, g, b):
    return np.array([r, g, b], float) / 255.0


def ramp(t, stops):
    """t (N,) -> (N, 3) sRGB 0..1 from [(pos, (r, g, b) 0-255), ...]."""
    t = np.asarray(t, float)
    xs = [s[0] for s in stops]
    out = np.empty(t.shape + (3,))
    for ch in range(3):
        out[..., ch] = np.interp(t, xs, [s[1][ch] / 255.0 for s in stops])
    return out


def mixc(a, b, t):
    t = np.asarray(t, float)
    if t.ndim < np.ndim(a):
        t = t[..., None]
    return a + (b - a) * t


def ss(e0, e1, x):
    return tg.smoothstep(e0, e1, x)


def fill_uncovered(arr, cover):
    """Push-pull fill of every texel outside the islands (seamless mips)."""
    return tg.pushpull(arr, cover.astype(np.float64))


def write_color(path, srgb):
    tg.write_png(path, np.clip(srgb, 0.0, 1.0))


def write_normal(path, enc):
    """enc: H x W x 3 in 0..1 (OpenGL tangent space, already encoded)."""
    n = enc * 2.0 - 1.0
    n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    tg.write_png(path, n * 0.5 + 0.5)


def write_gray(path, g, size=None):
    g = np.asarray(g, float)
    while size is not None and g.shape[0] > size:
        g = 0.25 * (g[0::2, 0::2] + g[1::2, 0::2] + g[0::2, 1::2] + g[1::2, 1::2])
    tg.write_png(path, np.clip(g, 0.0, 1.0))
    return g


def write_mr(path, rough, size=512):
    r = np.asarray(rough, float)
    while r.shape[0] > size:
        r = 0.25 * (r[0::2, 0::2] + r[1::2, 0::2] + r[0::2, 1::2] + r[1::2, 1::2])
    tg.write_png(path, np.stack([r, r, np.zeros_like(r)], axis=2))


def periodic_noise(rng, h, w, f_lo, f_hi, beta=1.0):
    """Periodic h x w noise (energy between f_lo..f_hi cycles per tile, measured on the longer side's scale)."""
    fy = (np.fft.fftfreq(h) * h)[:, None]
    fx = (np.fft.fftfreq(w) * w)[None, :]
    k = np.sqrt(fx ** 2 + fy ** 2)
    k[0, 0] = 1e-6
    win = tg.smoothstep(f_lo * 0.6, f_lo, k) * (1.0 - tg.smoothstep(f_hi, f_hi * 1.5, k))
    amp = win * k ** (-beta)
    amp[0, 0] = 0.0
    phase = rng.uniform(0.0, TAU, (h, w))
    f = np.fft.ifft2(amp * np.exp(1j * phase)).real
    f -= f.mean()
    return f / (f.std() + 1e-12)


def stats_srgb(srgb, mask=None):
    a = srgb if mask is None else srgb[mask]
    return tuple(int(round(v * 255)) for v in a.reshape(-1, 3).mean(0))
