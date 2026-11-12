"""
lr_core.py - geometry, UV mapping, PBR materials, manifest and GLB export for the LandmarksReal set.

Independent of ls_common.Library (that one assigns flat Roblox materials and box UVs); it follows the same
conventions (1 unit = 1 stud, Blender +Y = asset front = Roblox LookVector, base centre on z = 0, parts named
<Asset>_<Role>[_n], one material per part, manifest vectors in Roblox space) and extends the manifest with the
texture set of every part.

Geometry is built in bmesh "pieces" (one stone block, one plank, one band ...). Each piece is UV-mapped with a rule
from this module the moment it is created, and every face carries a material index into MATS. Pieces are collected
in "groups" (same role + collision behaviour); at export a group is split by material into MeshParts.
"""
import json
import math
import os
import random
import shutil

import bmesh
import bpy
from mathutils import Matrix, Vector

import tex_landmarks as T

TAU = 2.0 * math.pi
MATS = ["LR_Granite", "LR_StoneTrim", "LR_Wood", "LR_Iron", "LR_Misc", "LR_Ember", "LR_Collider"]
M_GRANITE, M_TRIM, M_WOOD, M_IRON, M_MISC, M_EMBER, M_COLL = range(7)
TEXTURED = set(T.MATERIALS)

# role -> (Roblox material, fallback rgb used when no SurfaceAppearance is applied, i.e. the texture average)
ROLES = {
    "Granite": ("Granite", (138, 134, 127)),
    "Stone": ("Rock", (132, 128, 120)),
    "Cobble": ("Cobblestone", (124, 120, 112)),
    "Paving": ("Pavement", (136, 132, 125)),
    "Moss": ("Grass", (82, 94, 50)),
    "Wood": ("Wood", (124, 116, 104)),
    "Planks": ("WoodPlanks", (124, 116, 104)),
    "DarkMetal": ("Metal", (70, 64, 60)),
    "Metal": ("Metal", (120, 120, 120)),
    "Steel": ("DiamondPlate", (122, 124, 126)),
    "Rust": ("CorrodedMetal", (110, 70, 48)),
    "RoofTiles": ("ClayRoofTiles", (146, 84, 60)),
    "Banner": ("Fabric", (140, 60, 40)),
    "Rope": ("Fabric", (150, 128, 94)),
    "Basalt": ("Basalt", (40, 38, 36)),
    "Ember": ("Neon", (255, 128, 48)),
    "Collider": ("Granite", (90, 88, 84)),
}


def rng_for(seed):
    return random.Random(seed)


# =============================================================================================== materials
_mat_cache = {}


def _img(path, colorspace):
    img = bpy.data.images.get(os.path.basename(path))
    if img is None or img.filepath != path:
        img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    return img


def material(key, tex_dir):
    if key in _mat_cache and _mat_cache[key].name in bpy.data.materials:
        return _mat_cache[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if key in TEXTURED:
        files = T.files_for(key)
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = _img(os.path.join(tex_dir, files["color"]), "sRGB")
        tc.location = (-700, 300)
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
        tm = nt.nodes.new("ShaderNodeTexImage")
        tm.image = _img(os.path.join(tex_dir, files["mr"]), "Non-Color")
        tm.location = (-700, 0)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (-400, 0)
        nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = _img(os.path.join(tex_dir, files["normal"]), "Non-Color")
        tn.location = (-700, -300)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (-400, -300)
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        mat.diffuse_color = (0.3, 0.3, 0.3, 1.0)
    elif key == "LR_Ember":
        bsdf.inputs["Base Color"].default_value = (1.0, 0.216, 0.03, 1.0)
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.216, 0.03, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 6.0
        bsdf.inputs["Roughness"].default_value = 0.8
    else:  # collider: plain dark, never rendered in reviews
        bsdf.inputs["Base Color"].default_value = (0.1, 0.1, 0.1, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    mat.use_backface_culling = True          # glTF doubleSided = false (manifest doubleSided false; closed solids)
    _mat_cache[key] = mat
    return mat


def preview_materials():
    """Call AFTER the GLB export, before review renders: the maps carry Roblox-ready roughness (authored look +
    T.ROBLOX_ROUGH_OFFSET, LookDevPlaybook s.11), so the review materials take the offset back out and Blender
    shows the authored look. (A math node in the export material would stop the glTF exporter from writing the
    metallicRoughness texture, hence this separate step.)"""
    for key, mat in _mat_cache.items():
        if key not in TEXTURED or mat.name not in bpy.data.materials or mat.get("lr_preview"):
            continue
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        link = next((l for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Roughness"), None)
        if link is None:
            continue
        src = link.from_socket
        nt.links.remove(link)
        sub = nt.nodes.new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        sub.use_clamp = True
        sub.inputs[1].default_value = T.ROBLOX_ROUGH_OFFSET
        nt.links.new(src, sub.inputs[0])
        nt.links.new(sub.outputs["Value"], bsdf.inputs["Roughness"])
        mat["lr_preview"] = True


# =============================================================================================== bmesh helpers
def new_bm():
    bm = bmesh.new()
    bm.loops.layers.uv.verify()
    return bm


def uvl(bm):
    return bm.loops.layers.uv.verify()


def face_center(f):
    return f.calc_center_median()


def transform(bm, m, verts=None):
    bmesh.ops.transform(bm, matrix=m, verts=list(verts if verts is not None else bm.verts))


def bevel_edges(bm, edges, w, segs=1, profile=0.5):
    if w <= 0 or not edges:
        return
    bmesh.ops.bevel(bm, geom=list(edges), offset=w, offset_type='OFFSET', profile_type='SUPERELLIPSE',
                    segments=segs, profile=profile, affect='EDGES', clamp_overlap=True)


def bevel_all(bm, w, segs=1, angle_deg=30.0, profile=0.5):
    edges = [e for e in bm.edges if e.is_manifold and len(e.link_faces) == 2
             and e.calc_face_angle(0.0) > math.radians(angle_deg)]
    bevel_edges(bm, edges, w, segs, profile)


def box_bm(sx, sy, sz):
    """Box centred on the origin."""
    bm = new_bm()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((sx, sy, sz)), verts=bm.verts)
    return bm


def prism_bm(poly, z0, z1, top_poly=None):
    """Closed prism from a CCW 2D polygon (x, y) between z0 and z1 (optionally a different top polygon)."""
    bm = new_bm()
    top_poly = top_poly or poly
    bot = [bm.verts.new((x, y, z0)) for x, y in poly]
    top = [bm.verts.new((x, y, z1)) for x, y in top_poly]
    n = len(poly)
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def loft_bm(rings, cap0=True, cap1=True):
    bm = new_bm()
    vr = [[bm.verts.new(Vector(p)) for p in ring] for ring in rings]
    n = len(vr[0])
    for a, b in zip(vr[:-1], vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap0:
        bm.faces.new(list(reversed(vr[0])))
    if cap1:
        bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def cylinder_bm(r0, r1, z0, z1, segs=12, cap=True):
    ring0 = [(r0 * math.cos(TAU * i / segs), r0 * math.sin(TAU * i / segs), z0) for i in range(segs)]
    ring1 = [(r1 * math.cos(TAU * i / segs), r1 * math.sin(TAU * i / segs), z1) for i in range(segs)]
    return loft_bm([ring0, ring1], cap, cap)


def lathe_bm(profile, segs=16, phase=0.0, caps=True):
    """Revolve [(r, z), ...] bottom to top around Z; caps ends where r > 0 (unless caps=False)."""
    bm = new_bm()
    rings = []
    for (r, z) in profile:
        rings.append([bm.verts.new((r * math.cos(phase + TAU * i / segs), r * math.sin(phase + TAU * i / segs), z))
                      for i in range(segs)])
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if caps and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if caps and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def sweep_bm(spine, section, up=(0, 0, 1), cap0=True, cap1=True, twist=0.0):
    """Sweep a 2D section [(a, b)] (a along 'side', b along 'normal') along a 3D spine."""
    pts = [Vector(p) for p in spine]
    n = len(pts)
    U = Vector(up)
    rings = []
    for i, p in enumerate(pts):
        tng = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side = tng.cross(U)
        if side.length < 1e-6:
            side = tng.cross(Vector((1, 0, 0)))
        side.normalize()
        nrm = side.cross(tng).normalized()
        ang = twist * i / max(n - 1, 1)
        c, s = math.cos(ang), math.sin(ang)
        sec = section(i / max(n - 1, 1)) if callable(section) else section
        rings.append([p + side * (a * c - b * s) + nrm * (a * s + b * c) for (a, b) in sec])
    return loft_bm(rings, cap0, cap1)


def bisect(bm, co, no):
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no), dist=1e-5)


def jitter_verts(bm, amount, rnd, axes=(1, 1, 1)):
    moved = {}
    for v in bm.verts:
        key = (round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4))
        if key not in moved:
            moved[key] = Vector((rnd.uniform(-amount, amount) * axes[0], rnd.uniform(-amount, amount) * axes[1],
                                 rnd.uniform(-amount, amount) * axes[2]))
        v.co += moved[key]


def tri_count_bm(bm):
    return sum(len(f.verts) - 2 for f in bm.faces)


# =============================================================================================== UV rules
def _uv_set(f, uv, coords, mat):
    for loop, (u, v) in zip(f.loops, coords):
        loop[uv].uv = (u, v)
    f.material_index = mat


def horiz_tangent(n):
    t = Vector((-n.y, n.x, 0.0))
    if t.length < 1e-6:
        return Vector((1.0, 0.0, 0.0))
    return t.normalized()


class Granite:
    """World-space mapping onto the 4-stud granite tile with optional seamless trim bands:
    damp_z: the face meets the ground/a surface at this z -> the 1-stud band above it uses StoneTrim DAMP.
    rust_z: iron sits at this z -> the 1.5-stud band below it uses StoneTrim RUST.
    Faces must already be split at the band lines (see Piece.split_bands)."""

    def __init__(self, rnd, damp_z=None, rust_z=None, rot_top=True, top_frame=None, horiz=0.72):
        self.ou = rnd.random()
        self.ou_top, self.ov_top = rnd.random(), rnd.random()
        self.damp_z, self.rust_z = damp_z, rust_z
        self.rot = rnd.choice([0, 1, 2, 3]) if rot_top else 0
        self.top_frame = top_frame          # (xaxis Vector, yaxis Vector) for horizontal faces
        self.horiz = horiz
        if damp_z is not None:
            self.ov = 0.75 - damp_z / T.GRANITE_STUDS
        elif rust_z is not None:
            self.ov = -(rust_z - T.STONE_STRIP_STUDS["RUST"]) / T.GRANITE_STUDS
        else:
            self.ov = rnd.random()

    def band_lines(self):
        z = []
        if self.damp_z is not None:
            z.append(self.damp_z + T.STONE_STRIP_STUDS["DAMP"])
        if self.rust_z is not None:
            z.append(self.rust_z - T.STONE_STRIP_STUDS["RUST"])
            z.append(self.rust_z)
        return z

    def __call__(self, bm, faces):
        uv = uvl(bm)
        S = T.GRANITE_STUDS
        for f in faces:
            n = f.normal
            pts = [l.vert.co for l in f.loops]
            c = face_center(f)
            if abs(n.z) >= self.horiz:
                if self.top_frame:
                    ax, ay = self.top_frame
                else:
                    ax, ay = Vector((1, 0, 0)), Vector((0, 1, 0))
                coords = []
                for p in pts:
                    u, v = p.dot(ax) / S, p.dot(ay) / S
                    for _ in range(self.rot):
                        u, v = -v, u
                    coords.append((u + self.ou_top, v + self.ov_top))
                _uv_set(f, uv, coords, M_GRANITE)
                continue
            t = horiz_tangent(n)
            us = [p.dot(t) / S + self.ou for p in pts]
            zc = c.z
            if self.damp_z is not None and zc < self.damp_z + T.STONE_STRIP_STUDS["DAMP"] - 1e-4:
                r0, r1 = T.STONE_STRIPS["DAMP"]
                vs = [_band_v(p.z - self.damp_z, T.STONE_STRIP_STUDS["DAMP"], r0, r1) for p in pts]
                _uv_set(f, uv, list(zip(us, vs)), M_TRIM)
            elif self.rust_z is not None and zc > self.rust_z - T.STONE_STRIP_STUDS["RUST"] + 1e-4 and zc < self.rust_z + 0.05:
                r0, r1 = T.STONE_STRIPS["RUST"]
                base = self.rust_z - T.STONE_STRIP_STUDS["RUST"]
                vs = [_band_v(p.z - base, T.STONE_STRIP_STUDS["RUST"], r0, r1) for p in pts]
                _uv_set(f, uv, list(zip(us, vs)), M_TRIM)
            else:
                vs = [p.z / S + self.ov for p in pts]
                _uv_set(f, uv, list(zip(us, vs)), M_GRANITE)


def _band_v(dz, studs, r0, r1, pad=T.PAD):
    t = min(max(dz / studs, 0.0), 1.0)
    rows = r0 + pad + t * (r1 - r0 - 2 * pad)
    return rows / T.N


def strip_v(key_rows, t, pad=T.PAD):
    r0, r1 = key_rows
    t = min(max(t, 0.0), 1.0)
    return (r0 + pad + t * (r1 - r0 - 2 * pad)) / T.N


class Strip:
    """Trim-strip mapping: U = p.u_axis / period + offset (tiles), V = position across [a0, a1] (world studs along
    v_axis) mapped into the strip rows. Faces whose normal is close to u_axis (end faces) use end_rule if given."""

    def __init__(self, mat, rows, u_axis, v_axis, a0, a1, period=T.TRIM_STUDS, ou=0.0, end_rule=None, flip=False):
        self.mat, self.rows = mat, rows
        self.u_axis, self.v_axis = Vector(u_axis).normalized(), Vector(v_axis).normalized()
        self.a0, self.a1 = a0, a1
        self.period, self.ou = period, ou
        self.end_rule = end_rule
        self.flip = flip

    def __call__(self, bm, faces):
        uv = uvl(bm)
        for f in faces:
            if self.end_rule is not None and abs(f.normal.dot(self.u_axis)) > 0.7:
                self.end_rule(bm, [f])
                continue
            coords = []
            for l in f.loops:
                p = l.vert.co
                u = p.dot(self.u_axis) / self.period + self.ou
                t = (p.dot(self.v_axis) - self.a0) / max(self.a1 - self.a0, 1e-6)
                coords.append((u, strip_v(self.rows, 1 - t if self.flip else t)))
            _uv_set(f, uv, coords, self.mat)


class Member:
    """Timber/iron member with a long axis: long faces map onto a strip (U along the axis, V across the face,
    density kept unless the face is wider than the strip), end faces onto end-grain cells (wood) or the strip."""

    def __init__(self, mat, rows, axis, origin, ou=0.0, period=T.TRIM_STUDS, strip_studs=1.0, end_cell=None,
                 voff=0.0, stretch=False):
        self.mat, self.rows = mat, rows
        self.axis = Vector(axis).normalized()
        self.origin = Vector(origin)
        self.ou, self.period, self.strip_studs = ou, period, strip_studs
        self.end_cell = end_cell
        self.voff = voff
        self.stretch = stretch

    def __call__(self, bm, faces):
        uv = uvl(bm)
        r0, r1 = self.rows
        rows_h = r1 - r0 - 2 * T.PAD
        for f in faces:
            n = f.normal
            pts = [l.vert.co - self.origin for l in f.loops]
            if abs(n.dot(self.axis)) > 0.7:
                # end face
                a = horiz_tangent(self.axis) if abs(self.axis.z) > 0.7 else Vector((0, 0, 1)).cross(self.axis).normalized()
                if a.length < 1e-6:
                    a = Vector((1, 0, 0))
                b = self.axis.cross(a).normalized()
                if self.end_cell is not None:
                    e0, e1 = T.WOOD_STRIPS["END"]
                    S = e1 - e0
                    cell = self.end_cell % T.WOOD_END_CELLS
                    coords = []
                    for p in pts:
                        su = 0.5 + p.dot(a) / 0.95
                        sv = 0.5 + p.dot(b) / 0.95
                        su, sv = min(max(su, 0.02), 0.98), min(max(sv, 0.02), 0.98)
                        coords.append(((cell * S + su * S) / T.N, (e0 + sv * S) / T.N))
                    _uv_set(f, uv, coords, self.mat)
                else:
                    coords = [(p.dot(a) / self.period + self.ou, strip_v(self.rows, 0.5 + p.dot(b) / (2 * self.strip_studs)))
                              for p in pts]
                    _uv_set(f, uv, coords, self.mat)
                continue
            across = n.cross(self.axis).normalized()
            ws = [p.dot(across) for p in pts]
            w0, w1 = min(ws), max(ws)
            width = max(w1 - w0, 1e-4)
            coords = []
            for p, w in zip(pts, ws):
                u = p.dot(self.axis) / self.period + self.ou
                if self.stretch or width > self.strip_studs:
                    t = (w - w0) / width
                else:
                    t = self.voff + (w - w0) / self.strip_studs
                    t = min(t, 1.0)
                coords.append((u, (r0 + T.PAD + t * rows_h) / T.N))
            _uv_set(f, uv, coords, self.mat)


class Polar:
    """Annulus/disc mapping around a vertical axis: U = angle * repeats / TAU (integer repeats keep it seamless),
    V = radius mapped from [r0, r1] into the strip rows. Side (vertical) faces map U by angle, V by height."""

    def __init__(self, mat, rows, center, r0, r1, repeats, ou=0.0, z0=None, z1=None, side_rows=None):
        self.mat, self.rows, self.center = mat, rows, Vector(center)
        self.r0, self.r1, self.rep, self.ou = r0, r1, repeats, ou
        self.z0, self.z1, self.side_rows = z0, z1, side_rows or rows

    def __call__(self, bm, faces):
        uv = uvl(bm)
        for f in faces:
            pts = [l.vert.co - self.center for l in f.loops]
            angs = [math.atan2(p.y, p.x) for p in pts]
            a0 = angs[0]
            angs = [a0 + ((a - a0 + math.pi) % TAU) - math.pi for a in angs]
            us = [a * self.rep / TAU + self.ou for a in angs]
            if abs(f.normal.z) > 0.6 or self.z0 is None:
                vs = [strip_v(self.rows, (math.hypot(p.x, p.y) - self.r0) / max(self.r1 - self.r0, 1e-6)) for p in pts]
            else:
                vs = [strip_v(self.side_rows, (p.z - self.z0) / max(self.z1 - self.z0, 1e-6)) for p in pts]
            _uv_set(f, uv, list(zip(us, vs)), self.mat)


class Planar:
    """Planar projection (u_axis, v_axis world studs / scale) into a region [u0..u1] x [rows]."""

    def __init__(self, mat, u_axis, v_axis, scale_u, scale_v, ou=0.0, ov=0.0):
        self.mat = mat
        self.ua, self.va = Vector(u_axis), Vector(v_axis)
        self.su, self.sv, self.ou, self.ov = scale_u, scale_v, ou, ov

    def __call__(self, bm, faces):
        uv = uvl(bm)
        for f in faces:
            _uv_set(f, uv, [(l.vert.co.dot(self.ua) / self.su + self.ou, l.vert.co.dot(self.va) / self.sv + self.ov)
                            for l in f.loops], self.mat)


def _box_uv(f, scale):
    """Box projection (dominant normal axis), world studs / scale. Non-degenerate UVs keep MikkTSpace tangents
    well defined on every exported triangle."""
    n = f.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    a, b = [(1, 2), (0, 2), (0, 1)][ax]
    return [(l.vert.co[a] / scale, l.vert.co[b] / scale) for l in f.loops]


class Dark:
    """Joint backing seen only through gaps: the dark soil edge of the StoneTrim MOSS strip. V moves a little with
    the box projection so no UV triangle has zero area (tangent export)."""

    def __init__(self, v=0.06):
        self.v = v

    def __call__(self, bm, faces):
        uv = uvl(bm)
        for f in faces:
            coords = []
            for (u, w) in _box_uv(f, T.TRIM_STUDS):
                coords.append((u, strip_v(T.STONE_STRIPS["MOSS"], self.v + 0.05 * (w % 1.0))))
            _uv_set(f, uv, coords, M_TRIM)


class Flat:
    """Untextured materials (ember, collider): box-projected UVs (8 studs per tile), never sampled by a texture,
    present only so tangents can be generated for every mesh."""

    def __init__(self, mat):
        self.mat = mat

    def __call__(self, bm, faces):
        uv = uvl(bm)
        for f in faces:
            _uv_set(f, uv, _box_uv(f, 8.0), self.mat)


# =============================================================================================== assets / groups
class Group:
    def __init__(self, asset, key, role, collide, collision, cast_shadow, tags, query, rbx_material, transparency,
                 smooth_angle, notes):
        self.asset, self.key, self.role = asset, key, role
        self.collide, self.collision, self.cast_shadow = collide, collision, cast_shadow
        self.tags = list(tags or [])
        self.query = collide if query is None else query
        self.rbx_material = rbx_material
        self.transparency = transparency
        self.smooth_angle = smooth_angle
        self.notes = notes
        self.bm = new_bm()

    def add(self, piece_bm, rule=None, matrix=None):
        """Append a piece (already UV-mapped unless a rule is given) to this group, optionally transformed."""
        if matrix is not None:
            transform(piece_bm, matrix)
            # UVs that depend on world position must be assigned after the transform
        if rule is not None:
            bmesh.ops.recalc_face_normals(piece_bm, faces=piece_bm.faces)
            piece_bm.normal_update()
            rule(piece_bm, list(piece_bm.faces))
        me = bpy.data.meshes.new("_piece")
        piece_bm.to_mesh(me)
        piece_bm.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)


class Asset:
    def __init__(self, lib, name, kind, tags, notes):
        self.lib, self.name, self.kind = lib, name, kind
        self.tags, self.notes = list(tags or []), notes
        self.groups = []
        self.attachments = {}
        self.parts = []
        self.root = None
        self.info = {}

    def group(self, key, role, collide=False, collision="Box", cast_shadow=True, tags=None, query=None,
              rbx_material=None, transparency=0.0, smooth_angle=40.0, notes=""):
        for g in self.groups:
            if g.key == key:
                return g
        g = Group(self, key, role, collide, collision, cast_shadow, tags, query, rbx_material, transparency,
                  smooth_angle, notes)
        self.groups.append(g)
        return g

    def attach(self, name, position, look=(0, 0, 1), up=(0, 1, 0)):
        self.attachments[name] = {"position": to_roblox(Vector(position)),
                                  "look": to_roblox(Vector(look).normalized()),
                                  "up": to_roblox(Vector(up).normalized())}


def to_roblox(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def _split_by_material(bm):
    out = {}
    used = sorted({f.material_index for f in bm.faces})
    for mi in used:
        b = bm.copy()
        kill = [f for f in b.faces if f.material_index != mi]
        bmesh.ops.delete(b, geom=kill, context='FACES')
        loose = [v for v in b.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(b, geom=loose, context='VERTS')
        out[mi] = b
    return out


PART_TRI_LIMIT = 19000          # Roblox's hard limit is 20,000 triangles per MeshPart


def _islands(bm):
    bm.faces.index_update()
    seen = [False] * len(bm.faces)
    out = []
    for f in bm.faces:
        if seen[f.index]:
            continue
        seen[f.index] = True
        stack, comp = [f], []
        while stack:
            x = stack.pop()
            comp.append(x.index)
            for e in x.edges:
                for y in e.link_faces:
                    if not seen[y.index]:
                        seen[y.index] = True
                        stack.append(y)
        out.append(comp)
    return out


def _chunk(bm, limit=PART_TRI_LIMIT):
    """Split a mesh that is over the per-part triangle limit into spatially coherent chunks of whole islands
    (islands sorted bottom to top, then by angle), each under the limit."""
    total = tri_count_bm(bm)
    if total <= limit:
        return [bm]
    bm.faces.ensure_lookup_table()
    isl = []
    for comp in _islands(bm):
        tris = sum(len(bm.faces[i].verts) - 2 for i in comp)
        c = Vector()
        for i in comp:
            c += bm.faces[i].calc_center_median()
        c /= len(comp)
        isl.append((round(c.z / 6.0), math.atan2(c.y, c.x), tris, comp))
    isl.sort(key=lambda t: (t[0], t[1]))
    n_chunks = int(math.ceil(total / float(limit)))
    target = total / n_chunks
    groups, cur, cur_t = [], [], 0
    for (_, _, tris, comp) in isl:
        if cur and (cur_t + tris > limit or (cur_t >= target and len(groups) < n_chunks - 1)):
            groups.append(cur)
            cur, cur_t = [], 0
        cur += comp
        cur_t += tris
    if cur:
        groups.append(cur)
    out = []
    for gidx in groups:
        keep = set(gidx)
        b = bm.copy()
        b.faces.index_update()                  # the copy keeps the face order
        kill = [f for f in b.faces if f.index not in keep]
        bmesh.ops.delete(b, geom=kill, context='FACES')
        loose = [v for v in b.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(b, geom=loose, context='VERTS')
        out.append(b)
    bm.free()
    return out


class Library:
    def __init__(self, category, tex_dir):
        self.category = category
        self.tex_dir = tex_dir
        self.assets = []
        self.warnings = []
        self.notes = []

    def begin(self, name, kind="Prop", tags=None, notes=""):
        a = Asset(self, name, kind, tags, notes)
        self.assets.append(a)
        return a

    def finish(self, a):
        root = bpy.data.objects.new(a.name, None)
        root.empty_display_type = "PLAIN_AXES"
        bpy.context.scene.collection.objects.link(root)
        a.root = root
        role_count = {}
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        vis_lo = Vector((1e9, 1e9, 1e9))
        vis_hi = Vector((-1e9, -1e9, -1e9))
        for g in a.groups:
            if not g.bm.faces:
                continue
            bmesh.ops.remove_doubles(g.bm, verts=g.bm.verts, dist=1e-5)
            # MikkTSpace (glTF tangents) only works on tris and quads: triangulate every n-gon, keep the quads
            ngons = [f for f in g.bm.faces if len(f.verts) > 4]
            if ngons:
                bmesh.ops.triangulate(g.bm, faces=ngons, quad_method='BEAUTY', ngon_method='BEAUTY')
            pieces = []
            for mi, b0 in _split_by_material(g.bm).items():
                for b in _chunk(b0):
                    pieces.append((mi, b))
            for mi, b in pieces:
                key = MATS[mi]
                role = g.role
                cnt = role_count.get(role, 0)
                role_count[role] = cnt + 1
                pname = "%s_%s" % (a.name, role) + ("" if cnt == 0 else "_%d" % (cnt + 1))
                me = bpy.data.meshes.new(pname)
                b.normal_update()
                b.to_mesh(me)
                b.free()
                obj = bpy.data.objects.new(pname, me)
                bpy.context.scene.collection.objects.link(obj)
                obj.parent = root
                for p in me.polygons:
                    p.use_smooth = g.smooth_angle is not None
                if g.smooth_angle is not None:
                    me.set_sharp_from_angle(angle=math.radians(g.smooth_angle))
                    # face-area weighted normals: big faces stay flat, the narrow chamfers carry the turn, so a
                    # one-segment bevel reads as a softly rounded arris (applied at export, export_apply=True)
                    wn = obj.modifiers.new("LR_WeightedNormal", "WEIGHTED_NORMAL")
                    wn.mode = 'FACE_AREA'
                    wn.weight = 50
                    wn.keep_sharp = True
                me.materials.append(material(key, self.tex_dir))
                tris = sum(len(p.vertices) - 2 for p in me.polygons)
                if tris > 20000:
                    self.warnings.append("%s has %d triangles (> 20000, Roblox will reject it)" % (pname, tris))
                plo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
                phi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
                lo = Vector([min(lo[i], plo[i]) for i in range(3)])
                hi = Vector([max(hi[i], phi[i]) for i in range(3)])
                if g.role != "Collider":
                    vis_lo = Vector([min(vis_lo[i], plo[i]) for i in range(3)])
                    vis_hi = Vector([max(vis_hi[i], phi[i]) for i in range(3)])
                rbx, rgb = ROLES.get(role, ("SmoothPlastic", (128, 128, 128)))
                if g.rbx_material:
                    rbx = g.rbx_material
                part = {
                    "name": pname, "role": role, "robloxMaterial": rbx, "rgb": list(rgb),
                    "collide": bool(g.collide), "collision": g.collision if g.collide else "Box",
                    "castShadow": bool(g.cast_shadow), "canQuery": bool(g.query), "canTouch": bool(g.collide),
                    "transparency": g.transparency, "tags": list(g.tags), "tris": tris,
                    "material": key,
                }
                if key in TEXTURED:
                    files = T.files_for(key)
                    part["surfaceAppearance"] = {
                        "colorMap": files["color"], "normalMap": files["normal"],
                        "roughnessMap": files["rough"],
                        "metalnessMap": files.get("metal"),
                        "alphaMode": None,
                        "glbMetallicRoughness": files["mr"]}
                else:
                    part["surfaceAppearance"] = None
                part["doubleSided"] = False
                part["backFacesInMesh"] = bool(getattr(g, "back_faces", False))
                if g.notes:
                    part["notes"] = g.notes
                a.parts.append(part)
                obj["lr_role"] = role
        a.info = {"boundsMin": to_roblox_min_max(vis_lo, vis_hi)[0], "boundsMax": to_roblox_min_max(vis_lo, vis_hi)[1],
                  "size": [round(vis_hi.x - vis_lo.x, 3), round(vis_hi.z - vis_lo.z, 3), round(vis_hi.y - vis_lo.y, 3)],
                  "tris": sum(p["tris"] for p in a.parts if p["role"] != "Collider"),
                  "colliderTris": sum(p["tris"] for p in a.parts if p["role"] == "Collider")}
        a.vis_lo, a.vis_hi = vis_lo, vis_hi
        return a

    def export(self, out_dir, repo_manifest_dir=None, gap=8.0):
        x = 0.0
        for a in self.assets:
            off = x - a.vis_lo.x
            a.root.location = (off, 0, 0)
            a.origin = [round(off, 4), 0.0, 0.0]
            x += (a.vis_hi.x - a.vis_lo.x) + gap
        bpy.context.view_layer.update()
        for o in bpy.context.scene.objects:
            o.select_set(False)
        for a in self.assets:
            a.root.select_set(True)
            for c in a.root.children_recursive:
                c.select_set(True)
        glb = os.path.join(out_dir, self.category + ".glb")
        bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                                  export_image_format="AUTO", export_tangents=True, export_materials="EXPORT")
        check = inspect_glb(glb)
        if check["primitivesMissingTangent"]:
            self.warnings.append("primitives without TANGENT: %s" % ", ".join(check["primitivesMissingTangent"]))
        for m in check["materials"]:
            if m["name"] in TEXTURED and not (m["baseColorTexture"] and m["metallicRoughnessTexture"] and m["normalTexture"]):
                self.warnings.append("material %s lost a texture in the glTF export: %s" % (m["name"], m))
        print("GLBCHECK primitives %d, with TANGENT %d, images %s" % (
            check["primitives"], check["primitivesWithTangent"], check["images"]))
        manifest = {
            "category": self.category, "glb": os.path.basename(glb),
            "units": "1 Blender unit = 1 Roblox stud (1 stud ~ 0.33 m)",
            "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
            "textureFolder": "textures/" + self.category,
            "textures": texture_table(self.tex_dir),
            "glbCheck": check,
            "notes": self.notes,
            "assets": [],
            "warnings": self.warnings,
        }
        for a in self.assets:
            entry = {"name": a.name, "kind": a.kind, "tags": a.tags, "notes": a.notes, "origin": a.origin}
            entry.update(a.info)
            entry["parts"] = a.parts
            entry["attachments"] = a.attachments
            manifest["assets"].append(entry)
        mpath = os.path.join(out_dir, self.category + ".manifest.json")
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1)
        if repo_manifest_dir:
            os.makedirs(repo_manifest_dir, exist_ok=True)
            shutil.copyfile(mpath, os.path.join(repo_manifest_dir, os.path.basename(mpath)))
        # put assets back at the origin for review renders
        for a in self.assets:
            a.root.location = (0, 0, 0)
        bpy.context.view_layer.update()
        mb = os.path.getsize(glb) / (1024 * 1024)
        print("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (glb, mb, len(self.assets), len(self.warnings)))
        for w in self.warnings:
            print("WARNING " + w)
        return manifest, glb


def to_roblox_min_max(lo, hi):
    a, b = to_roblox(lo), to_roblox(hi)
    return [min(x, y) for x, y in zip(a, b)], [max(x, y) for x, y in zip(a, b)]


def texture_table(tex_dir):
    out = []
    for m in T.MATERIALS:
        files = T.files_for(m)
        for kind, fn in files.items():
            path = os.path.join(tex_dir, fn)
            out.append({"file": fn, "material": m, "map": kind,
                        "colorSpace": "sRGB" if kind == "color" else "Linear",
                        "size": [T.N, T.N] if kind in ("color", "normal") else ([T.MR_SIZE, T.MR_SIZE] if kind == "mr" else [T.ROUGH_SIZE, T.ROUGH_SIZE]),
                        "channels": {"color": "RGB base colour (no alpha)",
                                     "normal": "RGB tangent-space normal, OpenGL (+Y up), MikkTSpace",
                                     "rough": "8-bit grayscale roughness (Roblox-ready: authored + %.2f)" % T.ROBLOX_ROUGH_OFFSET,
                                     "metal": "8-bit grayscale metalness",
                                     "mr": "glTF metallicRoughness packing (R = G = roughness, B = metalness); embedded "
                                           "in the GLB - do not upload separately"}[kind],
                        "upload": kind != "mr",
                        "bytes": os.path.getsize(path) if os.path.exists(path) else None})
    return out


def inspect_glb(path):
    """Read the GLB's JSON chunk: per mesh primitive attributes (TANGENT present?), materials and images."""
    import struct
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    prims = []
    for m in js.get("meshes", []):
        for p in m.get("primitives", []):
            prims.append((m.get("name"), sorted(p.get("attributes", {}).keys())))
    missing = [n for n, att in prims if "TANGENT" not in att]
    mats = []
    for mt in js.get("materials", []):
        pbr = mt.get("pbrMetallicRoughness", {})
        mats.append({"name": mt.get("name"), "baseColorTexture": "baseColorTexture" in pbr,
                     "metallicRoughnessTexture": "metallicRoughnessTexture" in pbr,
                     "normalTexture": "normalTexture" in mt})
    return {"primitives": len(prims), "primitivesWithTangent": len(prims) - len(missing),
            "primitivesMissingTangent": missing, "attributeSets": sorted({",".join(a) for _, a in prims}),
            "materials": mats, "images": [im.get("name") for im in js.get("images", [])],
            "bytes": len(data)}
