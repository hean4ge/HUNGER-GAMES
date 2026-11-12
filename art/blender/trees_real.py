"""
trees_real.py - LAST STANDING "TreesReal" generator: realistic, textured temperate mountain-forest trees
(Blender 5.3, headless). Replaces the stylised Foliage trees for the classic forest arena.

Assets (1 unit = 1 stud, trunk base centre on z = 0, front = +Y = Roblox LookVector):
  conifers   SpruceA, SpruceB, FirA, PineA, ConiferYoung
  broadleaf  BirchA, BirchB, OakA (standable level limbs: Perch1..N, OakA_Bark tagged Climbable)
  dead       SnagA, SnagB, FallenLogA, FallenLogB, StumpA, StumpB

How the look is made (the standard real-time vegetation approach):
- Trunks, limbs, branches and roots are real geometry: swept, tapered tubes with root flares and lobes,
  UV-unwrapped U around / V along with a whole number of bark tiles (tex_trees.py) around each trunk: ~130-300 px
  per stud at the base (manifest barkPxPerStud; the four thickest trunks sit at 126-141 with one tile around).
- Foliage is alpha-tested cards cut from two atlases rendered from modelled sprigs (tex_trees.py). Cards are
  clustered and crossed along the branches, slightly bent, duplicated with flipped back faces, and their
  normals are bent toward "out of the crown" so a crown shades like a volume instead of flat planes.
- One SurfaceAppearance per MeshPart; species share images and differ by SurfaceAppearance.Color tints.

Run (from the repo root):
  blender --background --factory-startup --python art/blender/trees_real.py -- <out_dir> <preview_dir> [flags]
    flags: textures      rebuild every PNG first (otherwise existing ones in <out_dir>/textures/TreesReal are used)
           only=A,B      build a subset (for iteration; does NOT overwrite the full export unless 'export')
           nopreview     skip the EEVEE review renders (nosheets: skip only the lineup / forest sheets)
           split         export TreesReal_Conifers / _Broadleaf / _Deadwood.glb instead of one TreesReal.glb
                         (automatic above 18 MiB; each split GLB embeds its own copy of the shared images)
  Every export is checked: TANGENT / TEXCOORD_0 / NORMAL on every primitive, metallicFactor 0 on every material,
  embedded images byte-identical to the PNGs (GLBCHECK line; problems become manifest warnings).
Outputs: <out_dir>/TreesReal*.glb, <out_dir>/TreesReal.manifest.json, <out_dir>/textures/TreesReal/*.png,
         art/manifests/TreesReal.manifest.json, <preview_dir>/TreesReal/*.png
"""
import json
import math
import os
import random
import shutil
import sys
import time

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls
import ls_patch  # noqa: F401  (shared fixes: bounds, query flags, manifest copy)
import tex_trees as tx

import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_MANIFESTS = os.path.normpath(os.path.join(HERE, "..", "manifests"))
UP = Vector((0.0, 0.0, 1.0))
TAU = 2.0 * math.pi
CATEGORY = "TreesReal"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else os.getcwd()
    preview_dir = argv[1] if len(argv) > 1 else os.path.join(out_dir, "previews")
    flags = {}
    for a in argv[2:]:
        if "=" in a:
            k, v = a.split("=", 1)
            flags[k] = v
        else:
            flags[a] = True
    return out_dir, preview_dir, flags


def clamp(x, a, b):
    return a if x < a else (b if x > b else x)


def lerp(a, b, t):
    return a + (b - a) * t


def smooth01(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0) if e1 != e0 else (0.0 if x < e0 else 1.0)
    return t * t * (3 - 2 * t)


def hdir(a):
    return Vector((math.cos(a), math.sin(a), 0.0))


def rot_about(v, axis, ang):
    return Matrix.Rotation(ang, 3, axis.normalized()) @ v


# ================================================================================================
# Materials: one per (texture set, tint). Roblox: SurfaceAppearance with the same maps + Color = tint.
# ================================================================================================
TEXSETS = {
    "BarkConifer": {"rough": "bark", "alpha": False},
    "BarkOak": {"rough": "bark", "alpha": False},
    "BarkBirch": {"rough": "bark", "alpha": False},
    "Deadwood": {"rough": "bark", "alpha": False},
    "ConiferAtlas": {"rough": "foliage", "alpha": True},
    "BroadleafAtlas": {"rough": "foliage", "alpha": True},
}

# key: (texture set, tint sRGB 0-255, Roblox AlphaMode, glTF alpha cut-out)
MATS = {
    "TR_Bark_Spruce": ("BarkConifer", (176, 150, 132), "Overlay", False),
    "TR_Bark_Fir": ("BarkConifer", (196, 192, 186), "Overlay", False),
    "TR_Bark_PineUpper": ("BarkConifer", (240, 174, 134), "Overlay", False),
    "TR_Bark_Young": ("BarkConifer", (190, 164, 142), "Overlay", False),
    "TR_Bark_Snag": ("BarkConifer", (150, 138, 128), "Overlay", False),
    "TR_Bark_Log": ("BarkConifer", (150, 134, 122), "Overlay", False),
    "TR_Bark_Oak": ("BarkOak", (216, 208, 198), "Overlay", False),
    "TR_Bark_PineLower": ("BarkOak", (226, 196, 176), "Overlay", False),
    "TR_Bark_BirchBase": ("BarkOak", (120, 118, 118), "Overlay", False),
    "TR_Bark_Birch": ("BarkBirch", (252, 252, 250), "Overlay", False),
    "TR_Deadwood": ("Deadwood", (214, 206, 194), "Overlay", False),
    "TR_Deadwood_Rot": ("Deadwood", (150, 138, 124), "Overlay", False),
    "TR_Conifer_Spruce": ("ConiferAtlas", (255, 255, 255), "Transparency", True),
    "TR_Conifer_SpruceB": ("ConiferAtlas", (246, 255, 236), "Transparency", True),
    "TR_Conifer_Fir": ("ConiferAtlas", (238, 250, 244), "Transparency", True),
    "TR_Conifer_Pine": ("ConiferAtlas", (236, 246, 250), "Transparency", True),
    "TR_Conifer_Young": ("ConiferAtlas", (232, 236, 222), "Transparency", True),
    "TR_Conifer_Dead": ("ConiferAtlas", (255, 255, 255), "Transparency", True),
    "TR_Moss": ("ConiferAtlas", (244, 244, 236), "Transparency", True),
    "TR_EndGrain": ("ConiferAtlas", (226, 218, 206), "Overlay", False),
    "TR_EndGrain_Old": ("ConiferAtlas", (176, 168, 158), "Overlay", False),
    "TR_Broadleaf_Birch": ("BroadleafAtlas", (236, 236, 226), "Transparency", True),
    "TR_Broadleaf_Oak": ("BroadleafAtlas", (250, 250, 244), "Transparency", True),
    "TR_Moss_Broadleaf": ("BroadleafAtlas", (244, 244, 236), "Transparency", True),
}

# atlas regions each card material samples (fallback colour / albedo check use only these texels)
MAT_REGIONS = {
    "TR_Conifer_Spruce": ["spruce"], "TR_Conifer_SpruceB": ["spruce"], "TR_Conifer_Fir": ["fir"],
    "TR_Conifer_Pine": ["pine"], "TR_Conifer_Young": ["young"], "TR_Conifer_Dead": ["deadtwig"],
    "TR_Moss": ["moss"], "TR_EndGrain": ["endgrain"], "TR_EndGrain_Old": ["endgrain"],
    "TR_Broadleaf_Birch": ["birchA", "birchStrand", "birchB"], "TR_Broadleaf_Oak": ["oakA", "oakB"],
    "TR_Moss_Broadleaf": ["moss"],
}

# role -> Roblox physics material (the look comes from the SurfaceAppearance)
ROLE_MATERIAL = {"Bark": "Wood", "BarkUpper": "Wood", "BarkBase": "Wood", "BirchBark": "Wood", "DeadWood": "Wood",
                 "Branches": "Wood", "Roots": "Wood", "CutFace": "Wood", "Foliage": "LeafyGrass", "Moss": "Grass"}
for _role, _mat in ROLE_MATERIAL.items():          # register in the shared table at runtime (ls_common is frozen)
    ls.ROLES.setdefault(_role, {"roblox": _mat, "rgb": (128, 128, 128)})

_mat_cache = {}
_tex_avg = {}


def tex_path(tex_dir, name):
    return os.path.join(tex_dir, name)


def texset_files(key):
    c, n = tx.FILES[key]
    return c, n, tx.ROUGH_FILES[TEXSETS[key]["rough"]]


def load_image(path, colorspace):
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    return img


def texture_average(tex_dir, key, regions=None):
    """Linear mean colour of a colour map over its opaque texels (alpha > 0.5), optionally only inside the given
    atlas regions (manifest fallback colour and the albedo check)."""
    ck = (key, tuple(regions or ()))
    if ck in _tex_avg:
        return _tex_avg[ck]
    import numpy as np
    img = load_image(tex_path(tex_dir, tx.FILES[key][0]), "sRGB")
    w, h = img.size
    # Image.pixels of an 8-bit PNG are the stored (sRGB-encoded) values; convert to linear below
    a = np.array(img.pixels[:], dtype=np.float64).reshape(h, w, img.channels)
    if img.channels == 4:
        wgt = (a[..., 3] > 0.5).astype(np.float64)
    else:
        wgt = np.ones((h, w))
    if regions:
        rm = np.zeros((h, w))
        for r in regions:
            x0, y0, x1, y1 = tx.ATLAS[key][r]["rect"]
            rm[y0:y1, x0:x1] = 1.0
        wgt *= rm
    lin = tx.srgb_to_lin(a[..., :3])
    m = (lin * wgt[..., None]).sum(axis=(0, 1)) / max(wgt.sum(), 1.0)
    _tex_avg[ck] = m
    return m


def material(tex_dir, key):
    if key in _mat_cache:
        return _mat_cache[key]
    tset, tint, _amode, cut = MATS[key]
    cfile, nfile, rfile = texset_files(tset)
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    out = nt.nodes.get("Material Output")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = load_image(tex_path(tex_dir, cfile), "sRGB")
    tc.location = (-700, 300)
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    lin = [tx.srgb_to_lin(c / 255.0) for c in tint]
    nt.links.new(tc.outputs["Color"], mul.inputs[6])
    mul.inputs[7].default_value = (float(lin[0]), float(lin[1]), float(lin[2]), 1.0)
    mul.location = (-400, 300)
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    if cut:
        rnd = nt.nodes.new("ShaderNodeMath")
        rnd.operation = "ROUND"
        nt.links.new(tc.outputs["Alpha"], rnd.inputs[0])
        nt.links.new(rnd.outputs[0], bsdf.inputs["Alpha"])
        rnd.location = (-400, 0)
        m.surface_render_method = "DITHERED"
        if hasattr(m, "use_transparent_shadow"):
            m.use_transparent_shadow = True
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = load_image(tex_path(tex_dir, nfile), "Non-Color")
    tn.location = (-700, -300)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nm.uv_map = "UVMap"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    nm.location = (-400, -300)
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = load_image(tex_path(tex_dir, tx.ROUGH_GLB_FILES[TEXSETS[tset]["rough"]]), "Non-Color")
    tr.location = (-700, -50)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    # Metallic is read from the packed image's blue channel (0 everywhere). Linking both channels keeps the
    # glTF exporter on its pass-through path, so the GLB embeds glb_only/*_MR.png byte for byte; with Metallic
    # unlinked it re-composes the image with a WHITE blue channel (and metallicFactor 0), which an importer
    # that ignores the factor would read as full metal. export() then sets metallicFactor 0 in the GLB JSON,
    # so the factor and the texture both say "no metal".
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    m.use_backface_culling = True          # glTF doubleSided = false: cards carry their own back faces
    avg = texture_average(tex_dir, tset, MAT_REGIONS.get(key))
    m.diffuse_color = (float(avg[0] * lin[0]), float(avg[1] * lin[1]), float(avg[2] * lin[2]), 1.0)
    _mat_cache[key] = m
    return m


def fallback_rgb(tex_dir, key):
    """Effective mean albedo (sRGB 0-255) of a material: its texels' mean x its SurfaceAppearance tint."""
    tset, tint, _a, _c = MATS[key]
    avg = texture_average(tex_dir, tset, MAT_REGIONS.get(key))
    lin = [avg[i] * tx.srgb_to_lin(tint[i] / 255.0) for i in range(3)]
    return [int(round(float(tx.lin_to_srgb(c)) * 255)) for c in lin]


# ================================================================================================
# Mesh builder: polygons with per-corner UVs and (optional) per-corner normals; everything else gets
# area-weighted smooth vertex normals. All parts are written with custom split normals.
# ================================================================================================
class MB:
    def __init__(self):
        self.co, self.faces, self.uv, self.nrm, self.meta = [], [], [], [], []

    def v(self, p):
        self.co.append(Vector(p))
        return len(self.co) - 1

    def f(self, vids, uvs, normals=None, meta=None):
        self.faces.append(tuple(vids))
        self.uv.append(tuple(tuple(u) for u in uvs))
        self.nrm.append(None if normals is None else tuple(Vector(n) for n in normals))
        self.meta.append(meta)

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

    def vertex_normals(self):
        acc = [Vector((0.0, 0.0, 0.0)) for _ in self.co]
        for vids in self.faces:
            n = Vector((0.0, 0.0, 0.0))
            m = len(vids)
            for i in range(m):
                a = self.co[vids[i]]
                b = self.co[vids[(i + 1) % m]]
                n.x += (a.y - b.y) * (a.z + b.z)
                n.y += (a.z - b.z) * (a.x + b.x)
                n.z += (a.x - b.x) * (a.y + b.y)
            for vi in vids:
                acc[vi] += n
        return [a.normalized() if a.length > 1e-12 else Vector((0.0, 0.0, 1.0)) for a in acc]

    def take(self, src, face_ids, vnormals=None):
        """Copy faces of src (by index) into self, with normals frozen from src's smooth normals so shading
        stays continuous across part boundaries (bark / bare wood, dark base / white birch...)."""
        vn = vnormals or src.vertex_normals()
        remap = {}
        for fi in face_ids:
            vids = []
            for vi in src.faces[fi]:
                if vi not in remap:
                    remap[vi] = self.v(src.co[vi])
                vids.append(remap[vi])
            ns = src.nrm[fi] if src.nrm[fi] is not None else tuple(vn[vi] for vi in src.faces[fi])
            self.f(vids, src.uv[fi], ns, src.meta[fi])

    def to_object(self, name):
        vn = self.vertex_normals()
        # Faces with more than 4 corners (the contour splitter's cut pieces) are fanned into triangles: the
        # glTF exporter can only compute MikkTSpace tangents for tris and quads and silently drops TANGENT for
        # the whole mesh otherwise. Every such piece is convex (a quad clipped by straight cuts), so a fan is
        # exact; the triangle count is unchanged.
        faces, fuvs, fns = [], [], []
        for fi, vids in enumerate(self.faces):
            ns = self.nrm[fi]
            if ns is None:
                ns = [vn[vi] for vi in vids]
            uvs = self.uv[fi]
            if len(vids) <= 4:
                faces.append(list(vids))
                fuvs.append(uvs)
                fns.append(ns)
                continue
            for t in range(1, len(vids) - 1):
                idx = (0, t, t + 1)
                faces.append([vids[i] for i in idx])
                fuvs.append(tuple(uvs[i] for i in idx))
                fns.append([ns[i] for i in idx])
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(c) for c in self.co], [], faces)
        uvl = me.uv_layers.new(name="UVMap")
        uvl.data.foreach_set("uv", [c for fuv in fuvs for uv in fuv for c in uv])
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        loop_n = []
        for ns in fns:
            loop_n.extend(tuple(n) for n in ns)
        me.normals_split_custom_set(loop_n)
        me.update()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ================================================================================================
# Paths and swept tubes
# ================================================================================================
def catmull(ctrl, per=8):
    pts = [Vector(p) for p in ctrl]
    if len(pts) < 3:
        out = []
        for i in range(per + 1):
            out.append(pts[0].lerp(pts[-1], i / per))
        return out
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for j in range(per):
            t = j / per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1].copy())
    return out


class Path:
    def __init__(self, ctrl, per=8):
        self.pts = catmull(ctrl, per)
        self.L = [0.0]
        for a, b in zip(self.pts, self.pts[1:]):
            self.L.append(self.L[-1] + (b - a).length)
        self.length = self.L[-1]

    def at(self, s):
        """Point and unit tangent at arc-length fraction s."""
        target = clamp(s, 0.0, 1.0) * self.length
        lo, hi = 0, len(self.L) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.L[mid] < target:
                lo = mid
            else:
                hi = mid
        seg = self.L[hi] - self.L[lo]
        f = 0.0 if seg < 1e-9 else (target - self.L[lo]) / seg
        p = self.pts[lo].lerp(self.pts[hi], f)
        t = self.pts[hi] - self.pts[lo]
        return p, (t.normalized() if t.length > 1e-9 else UP.copy())


class Sweep:
    """Rings of a swept tube (positions kept) so caps, decals and branches can sit exactly on it."""

    def __init__(self, path, ss, frames, rings_pos, ring_ids, vs, sides, tiles):
        self.path, self.ss, self.frames = path, ss, frames
        self.rings_pos, self.ring_ids, self.vs = rings_pos, ring_ids, vs
        self.sides, self.tiles = sides, tiles

    def _locate(self, s):
        ss = self.ss
        s = clamp(s, ss[0], ss[-1])
        i = 0
        while i < len(ss) - 2 and ss[i + 1] < s:
            i += 1
        f = (s - ss[i]) / max(ss[i + 1] - ss[i], 1e-9)
        return i, clamp(f, 0.0, 1.0)

    def center(self, s):
        return self.path.at(s)[0]

    def surface(self, s, th):
        """Point on the faceted surface and its outward normal at arc fraction s, section angle th."""
        i, f = self._locate(s)
        a = (th % TAU) / TAU * self.sides
        k = int(math.floor(a)) % self.sides
        g = a - math.floor(a)
        k2 = (k + 1) % self.sides
        r0 = self.rings_pos[i]
        r1 = self.rings_pos[i + 1]
        p0 = r0[k].lerp(r0[k2], g)
        p1 = r1[k].lerp(r1[k2], g)
        p = p0.lerp(p1, f)
        c = self.path.at(s)[0]
        T = self.path.at(s)[1]
        d = p - c
        d -= T * d.dot(T)
        n = d.normalized() if d.length > 1e-9 else UP.copy()
        # tilt by the local slope of the surface along the tube
        along = p1 - p0
        if along.length > 1e-6:
            side = (r0[k2] - r0[k]).normalized() if (r0[k2] - r0[k]).length > 1e-9 else n.cross(T)
            n2 = side.cross(along.normalized())
            if n2.dot(n) < 0:
                n2 = -n2
            if n2.length > 1e-6:
                n = n2.normalized()
        return p, n

    def radius(self, s):
        i, f = self._locate(s)

        def rr(j):
            c = sum((p for p in self.rings_pos[j]), Vector((0, 0, 0))) / self.sides
            return sum((p - c).length for p in self.rings_pos[j]) / self.sides
        return lerp(rr(i), rr(i + 1), f)


def make_frames(path, ss, up_lock=False, ref=None):
    frames = []
    prevT = None
    N = None
    for s in ss:
        P, T = path.at(s)
        if up_lock:
            N = UP - T * UP.dot(T)
            if N.length < 1e-4:
                N = Vector((1.0, 0.0, 0.0)) - T * T.x
            N.normalize()
        elif N is None:
            r = ref if ref is not None else (Vector((1.0, 0.0, 0.0)) if abs(T.z) > 0.9 else UP)
            N = (r - T * r.dot(T)).normalized()
        else:
            N = prevT.rotation_difference(T) @ N
            N = (N - T * N.dot(T)).normalized()
        prevT = T
        B = T.cross(N)
        frames.append((P, T, N, B))
    return frames


def sweep(mb, ctrl, ss, section, sides, tiles=1, up_lock=False, ref=None, v0=0.0, v_scale=1.0, tip=0.0,
          per=8, path=None):
    """Sweep a section along a Catmull-Rom path. section(s, th) -> radius, or (x, y) in the (N, B) frame.
    UV: u = tiles around the ring, v keeps texels square (v advances by tiles / circumference per stud).
    tip > 0 closes the end with a point that far ahead (branch tips). Faces carry meta (s, th)."""
    path = path or Path(ctrl, per)
    frames = make_frames(path, ss, up_lock, ref)
    rings_pos, ring_ids, vs = [], [], []
    v = v0
    prev_c, prev_r = None, None
    for i, s in enumerate(ss):
        P, T, N, B = frames[i]
        pos = []
        for k in range(sides):
            th = TAU * k / sides
            val = section(s, th)
            if isinstance(val, tuple):
                x, y = val
            else:
                x, y = val * math.cos(th), val * math.sin(th)
            pos.append(P + N * x + B * y)
        r = sum((p - P).length for p in pos) / sides
        if prev_c is not None:
            circ = TAU * max(0.02, 0.5 * (r + prev_r))
            v += (P - prev_c).length * tiles / circ * v_scale
        prev_c, prev_r = P, r
        rings_pos.append(pos)
        ring_ids.append([mb.v(p) for p in pos])
        vs.append(v)
    for i in range(len(ss) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            u0 = tiles * k / sides
            u1 = tiles * (k + 1) / sides
            a, b = ring_ids[i], ring_ids[i + 1]
            mb.f((a[k], a[k2], b[k2], b[k]), ((u0, vs[i]), (u1, vs[i]), (u1, vs[i + 1]), (u0, vs[i + 1])),
                 meta=(0.5 * (ss[i] + ss[i + 1]), TAU * (k + 0.5) / sides))
    if tip > 0.0:
        P, T, N, B = frames[-1]
        t = mb.v(P + T * tip)
        vt = vs[-1] + tip * tiles / (TAU * max(0.02, prev_r))
        last = ring_ids[-1]
        for k in range(sides):
            k2 = (k + 1) % sides
            mb.f((last[k], last[k2], t), ((tiles * k / sides, vs[-1]), (tiles * (k + 1) / sides, vs[-1]),
                                          (tiles * (k + 0.5) / sides, vt)), meta=(1.0, TAU * (k + 0.5) / sides))
    return Sweep(path, ss, frames, rings_pos, ring_ids, vs, sides, tiles)


def _ms_polys(pos, f):
    """Marching squares on one quad (corners 0..3 in winding order). Returns (positive, negative) polygons as
    lists of ('c', i) corners and ('e', i, j) edge crossings, all in the quad's winding order."""
    def walk(side):
        out = []
        for i in range(4):
            j = (i + 1) % 4
            if pos[i] == side:
                out.append(("c", i))
            if pos[i] != pos[j]:
                out.append(("e", i, j))
        return out
    n = sum(pos)
    if n == 4:
        return [[("c", 0), ("c", 1), ("c", 2), ("c", 3)]], []
    if n == 0:
        return [], [[("c", 0), ("c", 1), ("c", 2), ("c", 3)]]
    if n == 2 and pos[0] == pos[2]:                       # saddle: the centre value decides which side connects
        conn = sum(f) / 4.0 >= 0.0
        tris = [[("e", (c - 1) % 4, c), ("c", c), ("e", c, (c + 1) % 4)] for c in range(4) if pos[c] != conn]
        return ([walk(True)], tris) if conn else (tris, [walk(False)])
    return [walk(True)], [walk(False)]


def contour_split(src, sw, field, mb_pos, mb_neg):
    """Split a swept tube (built into src) between two parts along the zero line of field(s, th): positive
    -> mb_pos, negative -> mb_neg. Quads crossing the line are cut along it (marching squares), so bark
    patches, the birch's black base or the pine's two barks get organic, smooth outlines instead of whole
    faces. Normals come from the unsplit tube, so shading stays continuous across the cut."""
    vn = src.vertex_normals()
    sides, tiles = sw.sides, sw.tiles
    fval = [[field(s, TAU * k / sides) for k in range(sides)] for s in sw.ss]
    caches = {id(mb_pos): ({}, {}), id(mb_neg): ({}, {})}

    def vert(mb, ref, gid, P):
        corner_c, edge_c = caches[id(mb)]
        if ref[0] == "c":
            g = gid[ref[1]]
            if g not in corner_c:
                corner_c[g] = mb.v(src.co[g])
            return corner_c[g]
        a, b = gid[ref[1]], gid[ref[2]]
        key = (min(a, b), max(a, b))
        if key not in edge_c:
            fa, fb = P[ref[1]], P[ref[2]]
            t = fa / (fa - fb) if abs(fa - fb) > 1e-12 else 0.5
            edge_c[key] = mb.v(src.co[a].lerp(src.co[b], t))
        return edge_c[key]

    def attr(ref, uvs, ns, P):
        if ref[0] == "c":
            return uvs[ref[1]], ns[ref[1]]
        i, j = ref[1], ref[2]
        fa, fb = P[i], P[j]
        t = fa / (fa - fb) if abs(fa - fb) > 1e-12 else 0.5
        uv = (lerp(uvs[i][0], uvs[j][0], t), lerp(uvs[i][1], uvs[j][1], t))
        return uv, ns[i].lerp(ns[j], t).normalized()

    for i in range(len(sw.ss) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            gid = (sw.ring_ids[i][k], sw.ring_ids[i][k2], sw.ring_ids[i + 1][k2], sw.ring_ids[i + 1][k])
            u0, u1 = tiles * k / sides, tiles * (k + 1) / sides
            uvs = ((u0, sw.vs[i]), (u1, sw.vs[i]), (u1, sw.vs[i + 1]), (u0, sw.vs[i + 1]))
            P = (fval[i][k], fval[i][k2], fval[i + 1][k2], fval[i + 1][k])
            ns = tuple(vn[g] for g in gid)
            pos = [v >= 0.0 for v in P]
            pp, nn = _ms_polys(pos, P)
            for polys, mb in ((pp, mb_pos), (nn, mb_neg)):
                for poly in polys:
                    vids, puv, pn = [], [], []
                    for ref in poly:
                        vids.append(vert(mb, ref, gid, P))
                        uv, n = attr(ref, uvs, ns, P)
                        puv.append(uv)
                        pn.append(n)
                    if len(set(vids)) >= 3:
                        mb.f(vids, puv, pn)
    # faces that are not part of the ring grid (tip fans): whole-face assignment
    n_grid = (len(sw.ss) - 1) * sides
    for fi in range(n_grid, len(src.faces)):
        meta = src.meta[fi]
        s_, th = meta if meta is not None else (1.0, 0.0)
        target = mb_pos if field(s_, th) >= 0.0 else mb_neg
        target.take(src, [fi], vn)


def cap_disc(mb, sw, ring=-1, uvr=None, facing=1, center_offset=0.0, ring_lift=None, uv_scale=0.47):
    """Flat (or slightly domed/recessed) cap over a ring of a sweep. uvr = atlas rect for an end-grain disc;
    facing +1 = the cap faces along the tube (end), -1 = against it (start)."""
    pos = sw.rings_pos[ring]
    P, T, N, B = sw.frames[ring]
    c = sum(pos, Vector((0, 0, 0))) / len(pos)
    rmax = max((p - c).length for p in pos)
    n = T * facing
    rim = []
    for p in pos:
        q = p.copy()
        if ring_lift:
            q += n * ring_lift(p)
        rim.append(q)
    cen = c + n * center_offset
    ids = [mb.v(p) for p in rim]
    cid = mb.v(cen)
    u0, v0, u1, v1 = uvr
    uc, vc = (u0 + u1) * 0.5, (v0 + v1) * 0.5
    hw, hh = (u1 - u0) * uv_scale, (v1 - v0) * uv_scale

    def uv_of(p):
        d = p - c
        return (uc + d.dot(N) / rmax * hw, vc + d.dot(B) / rmax * hh)
    m = len(ids)
    for k in range(m):
        k2 = (k + 1) % m
        tri = (ids[k], ids[k2], cid) if facing > 0 else (ids[k2], ids[k], cid)
        pts = [mb.co[i] for i in tri]
        mb.f(tri, [uv_of(p) for p in pts], [n, n, n])


def jagged_end(mb, sw, rng, depth=1.2, inward=0.25, hollow=0.3, ring=-1, splinters=1.0, facing=1, shard=0.3):
    """Broken, splintered end: a few long shards and many short ones beyond the ring (facing +1 = past the
    end, -1 = before the start), a ragged inner wall and a recessed centre. Tiles the bare-wood texture."""
    pos = sw.rings_pos[ring]
    P, T, N, B = sw.frames[ring]
    T = T * facing
    m = len(pos)
    c = sum(pos, Vector((0, 0, 0))) / m
    r = sum((p - c).length for p in pos) / m
    base_ids = [mb.v(p) for p in pos]
    lens = []
    for k in range(m):
        if rng.random() < shard:
            lens.append(depth * rng.uniform(0.55, 1.0) * splinters)
        else:
            lens.append(depth * rng.uniform(0.0, 0.22) * splinters)
    # neighbours of a long shard get a shoulder so shards are wedges, not needles
    lens = [max(lens[k], 0.45 * max(lens[(k - 1) % m], lens[(k + 1) % m])) for k in range(m)]
    spikes = []
    for k, p in enumerate(pos):
        q = p + T * lens[k] + (c - p) * (inward * rng.uniform(0.2, 0.7) * (0.3 + lens[k] / max(depth, 1e-6)))
        spikes.append(q)
    sp_ids = [mb.v(q) for q in spikes]
    inner = [c + (p - c) * rng.uniform(0.45, 0.62) + T * (min(lens[k], depth * 0.3) * rng.uniform(0.2, 0.6))
             for k, p in enumerate(pos)]
    in_ids = [mb.v(q) for q in inner]
    cen = mb.v(c - T * hollow)
    tiles = sw.tiles
    v_end = sw.vs[ring]
    circ = TAU * max(r, 0.05)
    for k in range(m):
        k2 = (k + 1) % m
        u0, u1 = tiles * k / m, tiles * (k + 1) / m
        va = v_end + lens[k] * tiles / circ
        vb = v_end + lens[k2] * tiles / circ
        vi = v_end + 0.3
        quads = [((base_ids[k], base_ids[k2], sp_ids[k2], sp_ids[k]), ((u0, v_end), (u1, v_end), (u1, vb), (u0, va))),
                 ((sp_ids[k], sp_ids[k2], in_ids[k2], in_ids[k]), ((u0, va), (u1, vb), (u1, vi), (u0, vi))),
                 ((in_ids[k], in_ids[k2], cen), ((u0, vi), (u1, vi), ((u0 + u1) * 0.5, vi + 0.25)))]
        for vids, uvs in quads:
            if facing < 0:
                vids, uvs = vids[::-1], uvs[::-1]
            mb.f(vids, uvs)


# ================================================================================================
# Cards and decals
# ================================================================================================
def card(mb, base, along, right, length, width, atlas, region, bend=0.0, segs=2, cup=0.0, outward=None,
         k_out=0.62, double=True, twist=0.0):
    """Alpha card: its region's twig anchor sits at `base`, the sprig grows along `along` for `length` studs,
    `right` spans the width. bend (radians, + = curl toward the front face) is spread over segs; cup lifts
    the centre line; outward(p) bends shading normals out of the crown. Back faces are duplicated."""
    reg = tx.ATLAS[atlas][region]
    u0, v0, u1, v1 = tx.region_uv(atlas, region)
    top = reg["anchor"] == "top"
    a = along.normalized()
    r = (right - a * right.dot(a))
    if r.length < 1e-6:
        r = a.orthogonal()
    r.normalize()
    if twist:
        r = rot_about(r, a, twist)
    spine, dirs = [base.copy()], [a.copy()]
    d = a.copy()
    step = length / segs
    p = base.copy()
    for j in range(segs):
        d_mid = rot_about(d, r, bend / segs * 0.5)
        p = p + d_mid * step
        d = rot_about(d, r, bend / segs)
        spine.append(p.copy())
        dirs.append(d.copy())
    rows = []
    for j, (p, d) in enumerate(zip(spine, dirs)):
        n = r.cross(d).normalized()
        t = j / segs
        v = (v1 - (v1 - v0) * t) if top else (v0 + (v1 - v0) * t)
        if cup:
            pts = [(p - r * (width * 0.5), (u0, v)), (p + n * (cup * width), ((u0 + u1) * 0.5, v)),
                   (p + r * (width * 0.5), (u1, v))]
        else:
            pts = [(p - r * (width * 0.5), (u0, v)), (p + r * (width * 0.5), (u1, v))]
        rows.append((pts, n))

    def shade_n(pnt, n):
        if outward is None:
            return n
        o = outward(pnt)
        s = 1.0 if o.dot(n) >= 0 else -1.0
        return (o * k_out + n * s * (1.0 - k_out)).normalized()

    for side in ((1, -1) if double else (1,)):
        ids = []
        for pts, n in rows:
            ids.append([(mb.v(q), uv, shade_n(q, n)) for q, uv in pts])
        for j in range(segs):
            A, Bv = ids[j], ids[j + 1]
            for c in range(len(A) - 1):
                quad = [A[c], A[c + 1], Bv[c + 1], Bv[c]]
                if side < 0:
                    quad = quad[::-1]
                mb.f([q[0] for q in quad], [q[1] for q in quad], [q[2] for q in quad])


def decal(mb, sw, s_lo, s_hi, th_c, th_w, atlas, region, lift=0.035, gx=4, gy=4, flip=False):
    """A moss patch hugging a sweep's surface between arc fractions s_lo..s_hi around angle th_c."""
    u0, v0, u1, v1 = tx.region_uv(atlas, region)
    grid = []
    for i in range(gy):
        s = lerp(s_lo, s_hi, i / (gy - 1))
        row = []
        for j in range(gx):
            th = th_c + (j / (gx - 1) - 0.5) * th_w * (-1 if flip else 1)
            p, n = sw.surface(s, th)
            row.append((mb.v(p + n * lift), (lerp(u0, u1, j / (gx - 1)), lerp(v0, v1, i / (gy - 1))), n))
        grid.append(row)
    for i in range(gy - 1):
        for j in range(gx - 1):
            q = [grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]]
            if flip:
                q = q[::-1]
            mb.f([x[0] for x in q], [x[1] for x in q], [x[2] for x in q])


# ================================================================================================
# Library with textured parts (extends the ls_common manifest)
# ================================================================================================
class TexLibrary(ls.Library):
    def __init__(self, category, tex_dir):
        super().__init__(category)
        self.tex_dir = tex_dir

    def add_tex(self, root, obj, role, mat_key, collide=False, collision="Hull", cast_shadow=True, tags=None,
                cards=False, notes=None):
        entry = self._entry(root)
        count = sum(1 for p in entry["parts"] if p["role"] == role)
        part_name = "%s_%s" % (root.name, role) + ("" if count == 0 else "_%d" % (count + 1))
        obj.name = part_name
        obj.data.name = part_name
        obj.data.materials.clear()
        obj.data.materials.append(material(self.tex_dir, mat_key))
        obj.parent = root
        tris = ls.tri_count(obj)
        if tris > ls.TRIANGLE_LIMIT:
            raise ValueError("%s has %d triangles (> %d Roblox limit)" % (part_name, tris, ls.TRIANGLE_LIMIT))
        if tris == 0:
            self.warnings.append(part_name + " has no faces")
        tset, tint, amode, cut = MATS[mat_key]
        cfile, nfile, rfile = texset_files(tset)
        part = {
            "name": part_name, "role": role, "robloxMaterial": ROLE_MATERIAL[role],
            "rgb": fallback_rgb(self.tex_dir, mat_key),
            "collide": bool(collide), "collision": collision if collide else "Box",
            "castShadow": bool(cast_shadow), "canQuery": bool(collide), "canTouch": bool(collide),
            "tags": list(tags or []), "tris": tris, "material": mat_key,
            "surfaceAppearance": {
                "colorMap": cfile, "normalMap": nfile, "roughnessMap": rfile, "metalnessMap": None,
                "alphaMode": amode, "color": list(tint),
            },
            "doubleSided": False,
            "backFacesInMesh": bool(cards),
            "transparency": 0,
        }
        if amode == "Transparency":
            part["alphaSetup"] = (
                "SurfaceAppearance.AlphaMode = Transparency with MeshPart.Transparency = 0 (alpha-tested cut-out: "
                "depth-correct, no sorting) and MeshPart.DoubleSided = false - "
                + ("the back faces are real, flipped duplicate faces in the mesh" if cards else
                   "single-sided decal lying on the bark, seen from outside only"))
        if notes:
            part["notes"] = notes
        entry["parts"].append(part)
        return obj


class Asset:
    """Collects the parts (one MB each) of one asset, then hands them to the library."""

    def __init__(self, lib, name, kind, tags, notes):
        self.lib = lib
        self.name = name
        self.root = lib.begin(name, kind=kind, tags=tags, notes=notes)
        self.parts = []
        self.texel = None

    def part(self, role, mat_key, collide=False, collision="Hull", shadow=True, tags=None, cards=False):
        mb = MB()
        self.parts.append({"role": role, "mb": mb, "mat": mat_key, "collide": collide, "collision": collision,
                           "shadow": shadow, "tags": tags, "cards": cards})
        return mb

    def done(self):
        total = 0
        for p in self.parts:
            if not p["mb"].faces:
                continue
            obj = p["mb"].to_object(self.name + "_" + p["role"])
            self.lib.add_tex(self.root, obj, p["role"], p["mat"], p["collide"], p["collision"], p["shadow"],
                             p["tags"], p["cards"])
            total += p["mb"].tris()
        entry = self.lib.finish(self.root)
        if self.texel:
            entry["barkPxPerStud"] = int(round(self.texel))
        print("ASSET %-13s %6d tris  size %s  parts %d  bark %s px/stud" % (self.name, entry["tris"], entry["size"],
                                                                         len(entry["parts"]), entry.get("barkPxPerStud")))
        return entry


# ================================================================================================
# Shared tree pieces
# ================================================================================================
def trunk_path(rng, H, z0=-0.6, lean=(0.0, 0.0), wiggle=0.25, n=6):
    """Control points of a gently sinuous trunk from below ground to the top."""
    la, lamt = lean
    ld = hdir(la)
    ph1, ph2 = rng.uniform(0, TAU), rng.uniform(0, TAU)
    ctrl = [Vector((0.0, 0.0, z0)), Vector((0.0, 0.0, 0.0))]
    for i in range(1, n + 1):
        f = i / n
        z = H * f
        off = ld * (lamt * H * f * f)
        off += Vector((math.sin(ph1 + f * 5.0), math.cos(ph2 + f * 4.3), 0.0)) * (wiggle * min(1.0, f * 3.0))
        ctrl.append(Vector((off.x, off.y, z)))
    return ctrl


def z_samples(H, z0=-0.6, base_fine=(0.0, 0.25, 0.6, 1.0, 1.6, 2.4, 3.4), step=2.6, top_extra=()):
    zs = [z0] + [z for z in base_fine if z < H]
    z = zs[-1] + step
    while z < H - 0.5:
        zs.append(z)
        z += step
    zs += [z for z in top_extra if zs[-1] < z < H]
    zs.append(H)
    return zs


def trunk_section(rng, H, r0, r_top, flare=0.45, flare_h=1.1, lobes=5, lobe_amp=0.3, lobe_h=0.9, power=0.9,
                  noise_amp=0.04):
    ph = rng.uniform(0, TAU)
    seed = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))

    def r_at(z, th):
        zz = max(z, 0.0)
        f = clamp(zz / H, 0.0, 1.0)
        r = r_top + (r0 - r_top) * (1.0 - f) ** power
        r *= 1.0 + flare * math.exp(-zz / flare_h)
        lob = max(0.0, math.cos(lobes * th + ph)) ** 2
        r *= 1.0 + lobe_amp * math.exp(-zz / lobe_h) * lob
        r *= 1.0 + noise_amp * noise.noise(seed + Vector((math.cos(th) * 1.3, math.sin(th) * 1.3, zz * 0.35)))
        return r
    return r_at, ph


def build_trunk(mb, rng, H, r0, r_top, z0=-0.6, lean=(0.0, 0.0), wiggle=0.2, sides=12, tile_studs=5.0,
                step=2.6, tip=0.6, **kw):
    ctrl = trunk_path(rng, H, z0, lean, wiggle)
    path = Path(ctrl)
    r_at, ph = trunk_section(rng, H, r0, r_top, **kw)
    zs = z_samples(H, z0, step=step)
    ss = [clamp((z - z0) / (H - z0), 0.0, 1.0) for z in zs]
    tiles = max(1, int(round(TAU * r0 / tile_studs)))

    def section(s, th):
        z = z0 + s * (H - z0)
        return r_at(z, th)
    sw = sweep(mb, ctrl, ss, section, sides, tiles=tiles, tip=tip, path=path, ref=Vector((1.0, 0.0, 0.0)))
    sw.z0, sw.H, sw.r_at, sw.lobe_phase = z0, H, r_at, ph
    return sw


def z_to_s(sw, z):
    return clamp((z - sw.z0) / (sw.H - sw.z0), 0.0, 1.0)


def texel_at(sw, z=1.0):
    """Bark texel density (px per stud) around the trunk at height z."""
    r = sw.radius(z_to_s(sw, z))
    return sw.tiles * tx.N / (TAU * max(r, 1e-3))


def root_arms(mb, rng, sw, n, r0, lobe_phase, reach=(2.0, 2.7), h=(0.7, 1.2), thick=0.36, tile_studs=5.0,
              lobes=5):
    """Short root arms that leave the trunk flare and dive into the ground (walk-through part)."""
    for k in range(n):
        if lobes:
            a = (TAU * (k % lobes) - lobe_phase) / lobes + rng.uniform(-0.15, 0.15)
        else:
            a = TAU * k / n + rng.uniform(-0.3, 0.3)
        d = hdir(a)
        R = r0 * rng.uniform(*reach)
        h0 = r0 * rng.uniform(*h)
        rr = r0 * thick * rng.uniform(0.85, 1.15)
        ctrl = [d * (r0 * 0.3) + UP * h0, d * (r0 * 1.0) + UP * (h0 * 0.45), d * (R * 0.72) + UP * 0.08,
                d * R - UP * 0.55]

        def sec(s, th, rr=rr):
            r = rr * (1.0 - 0.72 * s)
            return (r * 1.25 * math.cos(th), r * 0.8 * math.sin(th))
        tiles = 1
        sweep(mb, ctrl, [0.0, 0.2, 0.45, 0.7, 1.0], sec, 6, tiles=tiles, up_lock=True)


def base_moss(mb, rng, sw, atlas, n=4, z_max=2.4, region="moss"):
    for k in range(n):
        th = rng.uniform(0, TAU)
        z_lo = rng.uniform(-0.2, 0.3)
        z_hi = z_lo + rng.uniform(1.0, z_max)
        r = sw.radius(z_to_s(sw, 0.5 * (z_lo + z_hi)))
        w = clamp(rng.uniform(1.1, 2.0) / max(r, 0.3), 0.6, 2.2)
        decal(mb, sw, z_to_s(sw, z_lo), z_to_s(sw, z_hi), th, w, atlas, region, lift=0.05)


def outward_conifer(centre_z_fn=None, upk=0.45):
    def fn(p):
        h = Vector((p.x, p.y, 0.0))
        if h.length < 1e-4:
            return UP.copy()
        return (h.normalized() + UP * upk).normalized()
    return fn


def outward_ellipsoid(c, ax, ay, az, upk=0.25):
    def fn(p):
        d = Vector(((p.x - c.x) / ax, (p.y - c.y) / ay, (p.z - c.z) / az))
        if d.length < 1e-4:
            return UP.copy()
        return (d.normalized() + UP * upk).normalized()
    return fn


def branch_curve(start, dir_h, L, pitch, droop, upturn, rng, n=6, wobble=0.04):
    """Control points of a conifer branch: leaves the trunk at `pitch`, sags by `droop`, tips turn up."""
    pts = []
    side = Vector((-dir_h.y, dir_h.x, 0.0))
    ph = rng.uniform(0, TAU)
    for i in range(n + 1):
        u = i / n
        x = L * u
        z = math.tan(pitch) * x - droop * L * u * u + upturn * L * u ** 3
        lat = wobble * L * math.sin(ph + u * 3.0) * u
        pts.append(start + dir_h * x + UP * z + side * lat)
    return pts


def dead_stubs(mb, rng, sw, z_lo, z_hi, count, length=(0.3, 1.4), r=(0.05, 0.11), foliage=None, atlas=None,
               down=(-0.35, 0.15)):
    """Dead branch stubs (self-pruned lower branches), optionally with dead-twig cards on the longer ones."""
    for i in range(count):
        z = rng.uniform(z_lo, z_hi)
        a = rng.uniform(0, TAU)
        d = hdir(a)
        L = rng.uniform(*length)
        rad = rng.uniform(*r)
        s = z_to_s(sw, z)
        c = sw.center(s)
        pitch = rng.uniform(*down)
        dd = (d * math.cos(pitch) + UP * math.sin(pitch)).normalized()
        ctrl = [c + d * 0.0, c + dd * (L * 0.5) + d * 0.05, c + dd * L + UP * rng.uniform(-0.15, 0.1)]
        sweep(mb, ctrl, [0.0, 0.5, 1.0], lambda s_, th, rad=rad: rad * (1.0 - 0.55 * s_), 4, tip=0.08)
        if foliage is not None and L > 1.1 and rng.random() < 0.75:
            tipp = ctrl[-1]
            for j in range(rng.randint(1, 2)):
                ln = rng.uniform(1.4, 2.0)
                al = (dd + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(-0.2, 0.25)))).normalized()
                rt = UP.cross(al)
                card(foliage, c + dd * (L * 0.35), al, rt, ln, ln, atlas, "deadtwig", bend=rng.uniform(-0.3, 0.1),
                     twist=rng.uniform(-0.6, 0.6), outward=outward_conifer())


def grow_to_clusters(wood, rng, skeleton, clusters, rb_fn, sides=4, below=0.8):
    """Space-colonisation-lite: clusters are reached nearest-first by gently arching branches that start at
    the nearest existing wood (preferring wood below the cluster); every new branch joins the skeleton, so
    later clusters fork off it and the crown gets a natural hierarchy."""
    pending = list(clusters)
    while pending:
        best_i, best_s, best_d = 0, None, 1e9
        for i, P in enumerate(pending):
            for sp in skeleton:
                d = (P - sp).length + below * max(0.0, sp.z - P.z)
                if d < best_d:
                    best_i, best_s, best_d = i, sp, d
        P = pending.pop(best_i)
        S = best_s
        L = (P - S).length
        if L < 0.4:
            continue
        side = (P - S).cross(UP)
        side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        mid = S.lerp(P, 0.5) + UP * (0.1 * L) + side * rng.uniform(-0.12, 0.12) * L
        r = rb_fn(L)
        sweep(wood, [S, mid, P], [0.0, 0.5, 1.0], lambda s_, th, r=r: r * (1.0 - 0.6 * s_), sides, tip=0.05)
        skeleton.extend([S.lerp(mid, 0.5), mid, mid.lerp(P, 0.5), P])


def shell_points(rng, centre, ax, ay, az, n_try, min_d, z_min, k_rng=(0.82, 1.0), dz_min=-0.45, lumpy=0.0):
    pts = []
    lump_seed = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    for _ in range(n_try):
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if v.length < 1e-6:
            continue
        v.normalize()
        if v.z < dz_min:
            continue
        k = rng.uniform(*k_rng) * (1.0 + lumpy * noise.noise(lump_seed + v * 1.6))
        p = centre + Vector((v.x * ax, v.y * ay, v.z * az)) * k
        if p.z < z_min:
            continue
        if all((p - q).length >= min_d for q in pts):
            pts.append(p)
    return pts


def leaf_cluster(fol, rng, P, outw, atlas, regions, n, size, spread=(0.2, 0.55), segs=2):
    """Crossed sprays radiating from P, biased out of the crown: a leafy clump with volume from every angle."""
    o = outw(P)
    for j in range(n):
        spin = TAU * j / n + rng.uniform(-0.3, 0.3)
        perp = rot_about(o.orthogonal().normalized(), o, spin)
        al = (o * rng.uniform(*spread) + perp).normalized()
        reg = regions[rng.randrange(len(regions))]
        ln = size * rng.uniform(0.82, 1.05)
        jit = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * (size * 0.22)
        card(fol, P + jit - al * (ln * 0.3), al, o.cross(al), ln, ln, atlas, reg, bend=rng.uniform(-0.25, 0.25),
             twist=rng.uniform(-0.45, 0.45), outward=outw, segs=segs if j % 2 == 0 else 1)


# ================================================================================================
# Conifers
# ================================================================================================
def build_conifer(lib, name, seed, H, r0, crown_base, crown_r, whorl_step, per_whorl, style, mats, notes,
                  dead_below=True, tint_foliage=None, budget=9000):
    """Spruce / fir: tiers of branches from crown_base to the top; spruce branches sag and hang curtains of
    pendulous branchlets, fir branches stay flatter with upturned tips; dead stubs below the live crown."""
    rng = random.Random(seed)
    A = Asset(lib, name, "Tree", ["Conifer", "Realistic"], notes)
    bark = A.part("Bark", mats["bark"], collide=True, collision="Hull")
    wood = A.part("Branches", mats["bark"], shadow=True)
    roots = A.part("Roots", mats["bark"])
    fol = A.part("Foliage", mats["foliage"], cards=True)
    moss = A.part("Moss", "TR_Moss", shadow=False, cards=False)
    atlas = "ConiferAtlas"
    reg = "spruce" if style == "spruce" else "fir"
    sw = build_trunk(bark, rng, H, r0, r0 * 0.07, lean=(rng.uniform(0, TAU), 0.006), wiggle=0.18,
                     sides=12 if r0 > 0.7 else 10, tile_studs=tx.BARK_TILE_STUDS["conifer"], step=2.8,
                     flare=0.42, lobes=5, lobe_amp=0.32, lobe_h=0.8)
    A.texel = texel_at(sw)
    root_arms(roots, rng, sw, 5, r0, sw.lobe_phase)
    base_moss(moss, rng, sw, atlas, n=4)
    outw = outward_conifer()
    def one_branch(z, a, L, t, small=False):
        d = hdir(a)
        s = z_to_s(sw, z)
        c = sw.center(s)
        rr = sw.radius(s)
        if style == "spruce":
            pitch = math.radians(lerp(-16.0, 30.0, t ** 1.3) + rng.uniform(-5, 5))
            droop = lerp(0.26, 0.05, t) * rng.uniform(0.8, 1.2)
            upturn = lerp(0.12, 0.03, t)
        else:
            pitch = math.radians(lerp(-4.0, 34.0, t ** 1.4) + rng.uniform(-4, 4))
            droop = lerp(0.07, 0.02, t)
            upturn = lerp(0.1, 0.04, t)
        pts = branch_curve(c + d * (rr * 0.3), d, L, pitch, droop, upturn, rng)
        for q in pts:
            q.z = max(q.z, 1.2)
        path = Path(pts, 6)
        rb = 0.035 + 0.011 * L
        if L > 1.3:
            ss = [0.0, 0.26, 0.52] if L > 3.0 else [0.0, 0.5]
            sweep(wood, None, ss, lambda s_, th, rb=rb: rb * (1.0 - 0.75 * s_), 4 if L > 5 else 3, path=path,
                  tip=0.04)
        # foliage: overlapping sprays along the branch reaching past its tip, fanned side sprays that fill
        # the gaps between the branches of a tier, hanging branchlet curtains on spruce
        W0 = tx.region_size_studs(atlas, reg)[0]
        card_len = clamp(0.42 * L + 1.5, 1.6, W0 * 1.02)
        k_top = max(1, int(math.ceil((L * 0.82) / (card_len * 0.62))))
        u_first = 0.12 if t > 0.5 else 0.2
        u_last = max(u_first, (L + 0.5 - card_len) / L)
        bend = (-0.32 * (1 - t) + 0.22 * t) if style == "spruce" else (0.2 + 0.2 * t)
        for j in range(k_top):
            u_b = lerp(u_first, u_last, j / max(1, k_top - 1)) + rng.uniform(-0.03, 0.03)
            u_b = clamp(u_b, 0.05, 0.95)
            p, T = path.at(u_b)
            rt = T.cross(UP)                    # right-hand side: the card's front faces up
            if rt.length < 1e-4:
                rt = Vector((1.0, 0.0, 0.0))
            ln = card_len * rng.uniform(0.92, 1.04)
            card(fol, p + UP * 0.05, T, rt, ln, ln * 0.96, atlas, reg, bend=bend + rng.uniform(-0.1, 0.1),
                 twist=rng.uniform(-0.3, 0.3), outward=outw, cup=0.06 if style == "fir" else 0.0, segs=2)
            if j > 0 or k_top == 1:
                for sgn in (-1.0, 1.0):
                    if rng.random() < 0.15:
                        continue
                    yaw = sgn * math.radians(rng.uniform(32, 55))
                    Ts = rot_about(T, UP, yaw)
                    Ts = (Ts - UP * (0.12 if style == "spruce" else 0.0)).normalized()
                    ls_ = ln * rng.uniform(0.7, 0.85)
                    card(fol, p - UP * rng.uniform(0.05, 0.22), Ts, Ts.cross(UP), ls_, ls_ * 0.95, atlas, reg,
                         bend=bend * 0.8, twist=sgn * rng.uniform(0.1, 0.45), outward=outw, segs=1)
            if style == "fir" and L > 2.0 and rng.random() < 0.6:
                # second, lower layer rotated about the branch: thick flat fir tiers
                card(fol, p - UP * 0.3, T, rt, ln * 0.85, ln * 0.8, atlas, reg,
                     bend=0.25, twist=rng.choice((-1, 1)) * rng.uniform(0.35, 0.6), outward=outw, segs=1)
        if style == "spruce" and L > 1.6:
            k_h = max(1, int(round(L / 2.3)))
            for j in range(k_h):
                u = clamp(0.3 + 0.62 * (j + rng.uniform(0.2, 0.8)) / k_h, 0.25, 0.95)
                p, T = path.at(u)
                hl = clamp(0.4 * card_len + 1.0, 1.4, 2.9) * rng.uniform(0.85, 1.1)
                hl = min(hl, p.z - 0.5)
                if hl < 0.9:
                    continue
                hang = (-UP + T * rng.uniform(0.25, 0.5)).normalized()
                rt = T.copy()
                rt.z = 0
                rt = rt.normalized() if rt.length > 1e-4 else Vector((1, 0, 0))
                card(fol, p - UP * 0.04, hang, rt, hl, hl * 0.85, atlas, reg, bend=rng.uniform(-0.25, 0.1),
                     twist=rng.choice((-1, 1)) * rng.uniform(0.25, 0.6), outward=outw, segs=1)
        if t < 0.55 and rng.random() < 0.6:
            # dead twigs in the dark inner crown near the trunk
            p, T = path.at(0.08)
            al = (T + Vector((0, 0, rng.uniform(-0.3, 0.1)))).normalized()
            card(fol, p, al, al.cross(UP), 2.0, 2.0, atlas, "deadtwig", bend=-0.2, twist=rng.uniform(-0.8, 0.8),
                 outward=outw, segs=1)

    golden = math.radians(137.5)
    az = rng.uniform(0, TAU)
    z = crown_base
    tier = 0
    while z < H - 1.6:
        t = (z - crown_base) / max(H - crown_base, 1e-6)
        n = per_whorl if t < 0.85 else max(3, per_whorl - 1)
        az += golden + rng.uniform(-0.3, 0.3)
        env = (1.0 - t) ** (0.92 if style == "spruce" else 1.0)
        env *= 0.88 + 0.12 * math.sin(math.pi * min(1.0, t * 3.0))      # slightly fuller low in the crown
        for b in range(n):
            a = az + TAU * b / n + rng.uniform(-0.25, 0.25)
            one_branch(z, a, max(0.7, crown_r * env * rng.uniform(0.82, 1.08) + 0.6), t)
        # smaller inter-whorl branches fill the tiers (spruce and fir both carry them)
        if t < 0.8:
            zi = z + whorl_step * rng.uniform(0.35, 0.65)
            ti = (zi - crown_base) / max(H - crown_base, 1e-6)
            for b in range(2 if t < 0.45 else 1):
                a = az + rng.uniform(0, TAU)
                one_branch(zi, a, max(0.7, crown_r * env * rng.uniform(0.45, 0.65) + 0.4), ti, True)
        z += whorl_step * rng.uniform(0.85, 1.15)
        tier += 1
    # leader: a spire of crossed sprays
    top = sw.center(1.0)
    for k in range(3):
        a = k * math.pi / 3 + rng.uniform(-0.2, 0.2)
        ln = 2.6 if style == "spruce" else 2.4
        card(fol, top - UP * (ln * 0.92), UP, hdir(a), ln, ln * 0.62, atlas, reg, bend=0.0, segs=1,
             outward=outw)
    if dead_below and crown_base > 3.0:
        dead_stubs(wood, rng, sw, 2.2, crown_base - 0.3, int((crown_base - 2.2) * 2.4), foliage=fol, atlas=atlas)
    e = A.done()
    if e["tris"] > budget:
        lib.warnings.append("%s has %d tris (budget %d)" % (name, e["tris"], budget))
    return e


def build_young(lib, notes):
    rng = random.Random(77)
    name = "ConiferYoung"
    H = 11.0
    A = Asset(lib, name, "Tree", ["Conifer", "Realistic", "Young"], notes)
    bark = A.part("Bark", "TR_Bark_Young", collide=True, collision="Hull")
    fol = A.part("Foliage", "TR_Conifer_Young", cards=True)
    atlas = "ConiferAtlas"
    sw = build_trunk(bark, rng, H, 0.26, 0.03, z0=-0.4, wiggle=0.06, sides=7, tile_studs=1.6, step=2.4,
                     flare=0.3, lobes=0, lobe_amp=0.0, tip=0.4)
    A.texel = texel_at(sw)
    outw = outward_conifer(upk=0.35)
    z = 0.35
    az = rng.uniform(0, TAU)
    while z < H - 0.9:
        t = z / H
        az += math.radians(137.5)
        n = 6 if t < 0.6 else 5
        for b in range(n):
            a = az + TAU * b / n + rng.uniform(-0.2, 0.2)
            d = hdir(a)
            L = max(0.6, 3.6 * (1.0 - t) ** 0.95 * rng.uniform(0.85, 1.05) + 0.4)
            c = sw.center(z_to_s(sw, z))
            pitch = math.radians(lerp(-4, 30, t) + rng.uniform(-5, 5))
            p0 = c + d * 0.05
            T = (d * math.cos(pitch) + UP * math.sin(pitch)).normalized()
            ln = clamp(L * 1.0, 0.9, 1.75)
            card(fol, p0, T, T.cross(UP), ln, ln * 0.95, atlas, "young", bend=-0.25 + 0.45 * t,
                 twist=rng.uniform(-0.3, 0.3), outward=outw, segs=2, cup=0.08)
            if L > 1.2:
                for sgn in (-1.0, 1.0):
                    if rng.random() < 0.3:
                        continue
                    Ts = (rot_about(T, UP, sgn * math.radians(rng.uniform(30, 50))) - UP * 0.1).normalized()
                    p1 = p0 + T * (L * rng.uniform(0.25, 0.45))
                    card(fol, p1 - UP * 0.08, Ts, Ts.cross(UP), ln * 0.8, ln * 0.75, atlas, "young", bend=-0.15,
                         twist=sgn * rng.uniform(0.2, 0.5), outward=outw, segs=1)
        z += 0.62 * rng.uniform(0.85, 1.15)
    top = sw.center(1.0)
    for k in range(3):
        card(fol, top - UP * 1.3, UP, hdir(k * math.pi / 3 + 0.3), 1.4, 0.95, atlas, "young", segs=1, outward=outw)
    e = A.done()
    if e["tris"] > 2500:
        lib.warnings.append("%s has %d tris (budget 2500)" % (name, e["tris"]))
    return e


def build_pine(lib, notes):
    """Scots pine: tall straight bole, grey furrowed lower bark, plated orange upper bark, a high irregular
    crown of sinuous limbs whose ends carry cloud-like clumps of needle brushes; dead stubs on the bole."""
    rng = random.Random(4242)
    name = "PineA"
    H = 52.0
    r0 = 1.05
    A = Asset(lib, name, "Tree", ["Conifer", "Realistic", "Pine"], notes)
    lower = A.part("Bark", "TR_Bark_PineLower", collide=True, collision="Hull")
    upper = A.part("BarkUpper", "TR_Bark_PineUpper", collide=True, collision="Hull")
    wood = A.part("Branches", "TR_Bark_PineUpper")
    roots = A.part("Roots", "TR_Bark_PineLower")
    fol = A.part("Foliage", "TR_Conifer_Pine", cards=True)
    moss = A.part("Moss", "TR_Moss", shadow=False)
    atlas = "ConiferAtlas"
    tmp = MB()
    sw = build_trunk(tmp, rng, H - 2.0, r0, 0.16, lean=(rng.uniform(0, TAU), 0.01), wiggle=0.45, sides=12,
                     tile_studs=tx.BARK_TILE_STUDS["oak"], step=2.8, flare=0.38, lobes=5, lobe_amp=0.28, tip=0.3)
    seed = Vector((rng.uniform(-40, 40), rng.uniform(-40, 40), 0))
    z_split = 0.48 * H

    def field(s, th):
        z = sw.z0 + s * (sw.H - sw.z0)
        jag = 3.2 * noise.noise(seed + Vector((math.cos(th) * 1.6, math.sin(th) * 1.6, z * 0.12)))
        jag += 1.0 * noise.noise(seed * 1.9 + Vector((math.cos(th) * 4.0, math.sin(th) * 4.0, z * 0.5)))
        return z_split + jag - z              # positive: grey furrowed lower bark
    contour_split(tmp, sw, field, lower, upper)
    A.texel = texel_at(sw)
    root_arms(roots, rng, sw, 5, r0, sw.lobe_phase)
    base_moss(moss, rng, sw, atlas, n=3)
    crown_lo = 28.5
    clusters = []
    pads = []
    nl = 14
    az = rng.uniform(0, TAU)
    for i in range(nl):
        f = i / (nl - 1)
        z = lerp(crown_lo, H - 5.0, f) + rng.uniform(-0.7, 0.7)
        az += math.radians(137.5) + rng.uniform(-0.4, 0.4)
        d = hdir(az)
        L = lerp(11.0, 4.5, f ** 1.1) * rng.uniform(0.85, 1.15)
        elev = math.radians(lerp(4, 40, f) + rng.uniform(-8, 8))
        c = sw.center(z_to_s(sw, z))
        rr = sw.radius(z_to_s(sw, z))
        side = Vector((-d.y, d.x, 0))
        pts = [c + d * (rr * 0.2)]
        dirv = (d * math.cos(elev) + UP * math.sin(elev)).normalized()
        seglen = L / 4
        p = pts[0].copy()
        for k in range(4):
            kink = side * rng.uniform(-0.5, 0.5) + UP * rng.uniform(-0.25, 0.2)
            dirv = (dirv + kink * 0.5).normalized()
            if k >= 2:   # pine limbs flatten out and turn up again at the ends
                dirv = (dirv + d * 0.25 + UP * 0.35).normalized()
            p = p + dirv * seglen
            pts.append(p.copy())
        rb = 0.12 + 0.03 * L
        path = Path(pts, 6)
        sweep(wood, None, [0.0, 0.25, 0.5, 0.75, 1.0], lambda s_, th, rb=rb: rb * (1.0 - 0.72 * s_), 6,
              path=path, tip=0.1, tiles=1)
        clusters.append((pts[-1], (pts[-1] - pts[-2]).normalized(), 1.0))
        pads.append((path, 0.32))
        for j in range(rng.randint(3, 5)):
            u = rng.uniform(0.3, 0.85)
            q, T = path.at(u)
            sd = rng.choice((-1, 1))
            sdir = (T * 0.6 + side * sd * rng.uniform(0.6, 1.1) + UP * rng.uniform(0.25, 0.7)).normalized()
            Ls = L * rng.uniform(0.3, 0.45)
            sp = [q, q + sdir * (Ls * 0.5) + UP * 0.1, q + sdir * Ls + UP * rng.uniform(0.2, 0.6)]
            sweep(wood, sp, [0.0, 0.5, 1.0], lambda s_, th, rb=rb: rb * 0.42 * (1.0 - 0.6 * s_), 4, tip=0.06)
            clusters.append((sp[-1], (sp[-1] - sp[-2]).normalized(), 0.85))
            pads.append((Path(sp, 4), 0.15))
    top = sw.center(1.0)
    clusters.append((top + UP * 0.3, UP.copy(), 0.95))
    outw = outward_conifer(upk=0.7)
    # pads: brushes stand up along the outer limb and its side shoots (flat-topped pine foliage masses)
    for pth, u0 in pads:
        n = max(1, int(pth.length * (1.0 - u0) / 0.62))      # dense brushes: limbs read as foliage masses
        for j in range(n):
            u = u0 + (1.0 - u0) * (j + rng.uniform(0.2, 0.8)) / n
            q, T = pth.at(u)
            hT = Vector((T.x, T.y, 0))
            hT = hT.normalized() if hT.length > 1e-4 else hdir(rng.uniform(0, TAU))
            for kind in (0, 1):
                if kind == 0:
                    al = (UP * 0.85 + hT * 0.45 + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))).normalized()
                else:
                    al = (hT + rot_about(hT, UP, math.pi / 2) * rng.uniform(-0.8, 0.8) + UP * rng.uniform(-0.1, 0.4)).normalized()
                ln = 3.3 * rng.uniform(0.85, 1.05)
                rt = al.cross(UP) if al.cross(UP).length > 1e-3 else hT
                card(fol, q - al * 0.45, al, rot_about(rt, al, rng.uniform(-0.9, 0.9)), ln, ln, atlas, "pine",
                     bend=rng.uniform(0.0, 0.3), outward=outw, segs=1)
    for (p, d, sc) in clusters:
        k = rng.randint(6, 8)
        ax = (d + UP * 0.8).normalized()
        for j in range(k):
            cone = rng.uniform(0.45, 1.35)                 # wide cone: flat-topped clumps, not round pom-poms
            spin = TAU * j / k + rng.uniform(-0.3, 0.3)
            perp = rot_about(ax.orthogonal().normalized(), ax, spin)
            al = (ax * math.cos(cone) + perp * math.sin(cone)).normalized()
            ln = 3.25 * sc * rng.uniform(0.85, 1.05)
            rt = al.cross(UP) if al.cross(UP).length > 1e-3 else perp
            card(fol, p - al * 0.65, al, rot_about(rt, al, rng.uniform(-0.8, 0.8)), ln, ln, atlas, "pine",
                 bend=rng.uniform(0.0, 0.3), outward=outw, segs=2 if j % 2 == 0 else 1)
    dead_stubs(wood, rng, sw, 7.0, crown_lo - 1.0, 14, length=(0.25, 1.6), r=(0.06, 0.14), foliage=fol, atlas=atlas,
               down=(-0.2, 0.25))
    e = A.done()
    if e["tris"] > 9000:
        lib.warnings.append("%s has %d tris (budget 9000)" % (name, e["tris"]))
    return e


# ================================================================================================
# Broadleaf
# ================================================================================================
def birch_stem(rng, A, parts, base, lean_dir, lean, H, r0, crown_from, atlas, outw, fol, wood, n_br=14, spacing=0.85,
               sides=14):
    """One birch stem: white trunk with a black fissured base, ascending branches that arch out and carry
    curtains of hanging leafy twigs (silver birch weeps)."""
    tmp = MB()
    ctrl = [base + Vector((0, 0, -0.5)), base]
    ph = rng.uniform(0, TAU)
    for i in range(1, 7):
        f = i / 6
        off = lean_dir * (math.tan(lean) * H * f)
        off += Vector((math.sin(ph + f * 6.0), math.cos(ph + f * 5.0), 0)) * 0.22 * f
        ctrl.append(base + off + UP * (H * f))
    path = Path(ctrl)
    z0 = -0.5
    r_at, lph = trunk_section(rng, H, r0, 0.05, flare=0.3, flare_h=0.8, lobes=4, lobe_amp=0.18, lobe_h=0.6,
                              power=1.0, noise_amp=0.03)
    zs = [z0, 0.0, 0.25, 0.6] + [0.95 + 0.42 * i for i in range(12)]
    z = zs[-1] + 2.4
    while z < H - 0.5:
        zs.append(z)
        z += 2.4
    zs.append(H)
    ss = [clamp((z - z0) / (H - z0), 0.0, 1.0) for z in zs]
    tiles = max(1, int(round(TAU * r0 / tx.BARK_TILE_STUDS["birch"])))
    sw = sweep(tmp, None, ss, lambda s, th: r_at(z0 + s * (H - z0), th), sides, tiles=tiles, tip=0.3, path=path,
               ref=Vector((1, 0, 0)))
    sw.z0, sw.H, sw.lobe_phase = z0, H, lph
    seed = Vector((rng.uniform(-40, 40), rng.uniform(-40, 40), 0))
    z_dark = rng.uniform(2.4, 3.6)

    def field(s, th):
        z = z0 + s * (H - z0)
        jag = 1.5 * noise.noise(seed + Vector((math.cos(th) * 3.0, math.sin(th) * 3.0, z * 0.7)))
        jag += 0.6 * noise.noise(seed * 2.1 + Vector((math.cos(th) * 7.0, math.sin(th) * 7.0, z * 1.6)))
        return z_dark + jag - z               # positive: the black fissured base
    contour_split(tmp, sw, field, parts["base"], parts["white"])
    tips = []
    az = rng.uniform(0, TAU)
    for i in range(n_br):
        f = i / max(1, n_br - 1)
        z = lerp(crown_from, H * 0.94, f) + rng.uniform(-0.5, 0.5)
        s = z_to_s(sw, z)
        c = sw.center(s)
        az += math.radians(137.5) + rng.uniform(-0.5, 0.5)
        d = (hdir(az) + lean_dir * 0.35).normalized()
        L = lerp(8.0, 3.0, f ** 0.9) * rng.uniform(0.85, 1.15)
        elev = math.radians(lerp(34, 60, f) + rng.uniform(-8, 8))
        dirv = (d * math.cos(elev) + UP * math.sin(elev)).normalized()
        pts = [c, c + dirv * (L * 0.35), c + dirv * (L * 0.6) + d * (L * 0.18),
               c + dirv * (L * 0.75) + d * (L * 0.42) - UP * (L * 0.08)]
        rb = 0.06 + 0.018 * L
        bp = Path(pts, 6)
        sweep(wood, None, [0.0, 0.33, 0.66, 1.0], lambda s_, th, rb=rb: rb * (1.0 - 0.72 * s_), 4, path=bp, tip=0.05)
        tips.append((bp, L, d, 0.25))
        for j in range(rng.randint(2, 3)):
            u = rng.uniform(0.35, 0.85)
            q, T = bp.at(u)
            sd = rng.choice((-1, 1))
            side = Vector((-d.y, d.x, 0)) * sd
            sdir = (T * 0.45 + side * 0.85 + UP * 0.05).normalized()
            Ls = L * rng.uniform(0.35, 0.55)
            sp = [q, q + sdir * (Ls * 0.5), q + sdir * Ls - UP * (Ls * 0.3)]
            spath = Path(sp, 4)
            sweep(wood, None, [0.0, 0.5, 1.0], lambda s_, th, rb=rb: rb * 0.45 * (1.0 - 0.6 * s_), 3, path=spath,
                  tip=0.04)
            tips.append((spath, Ls, side, 0.1))
    # curtains of hanging leafy twigs along every branch, densest toward the ends
    for bp, L, d, u0 in tips:
        nh = max(2, int(round(L / spacing)))
        for j in range(nh):
            u = clamp(u0 + (1.0 - u0) * (j + rng.uniform(0.1, 0.9)) / nh, u0, 1.0)
            p, T = bp.at(u)
            reg = rng.choice(("birchA", "birchA", "birchStrand", "birchStrand", "birchB"))
            W, Hh = tx.region_size_studs(atlas, reg)
            sc = rng.uniform(0.95, 1.25)
            if p.z - Hh * sc < 1.0:
                sc = max(0.5, (p.z - 1.0) / Hh)
            out = Vector((T.x, T.y, 0))
            out = out.normalized() if out.length > 1e-4 else d
            hang = (-UP + out * rng.uniform(0.15, 0.45)).normalized()
            rt = rot_about(Vector((-out.y, out.x, 0)), UP, rng.uniform(-1.2, 1.2))
            card(fol, p + UP * 0.05, hang, rt, Hh * sc, W * sc, atlas, reg, bend=rng.uniform(-0.15, 0.3),
                 outward=outw, segs=2)
        # a small leafy clump at the tip
        tip, T = bp.at(1.0)
        o = (T + UP * 0.3).normalized()
        for k in range(2):
            al = (o + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.0)))).normalized()
            card(fol, tip - al * 0.4, al, al.cross(UP) if al.cross(UP).length > 1e-3 else Vector((1, 0, 0)),
                 1.7, 1.7, atlas, "birchB", bend=0.2, outward=outw, segs=1)
    return sw


def build_birch(lib, name, seed, stems, notes, budget=9000):
    rng = random.Random(seed)
    A = Asset(lib, name, "Tree", ["Broadleaf", "Realistic", "Birch"], notes)
    atlas = "BroadleafAtlas"
    base = A.part("BarkBase", "TR_Bark_BirchBase", collide=True, collision="Hull")
    whites = []
    for i in range(len(stems)):
        whites.append(A.part("BirchBark", "TR_Bark_Birch", collide=True, collision="Hull"))
    wood = A.part("Branches", "TR_Bark_Birch")
    roots = A.part("Roots", "TR_Bark_BirchBase")
    fol = A.part("Foliage", "TR_Broadleaf_Birch", cards=True)
    moss = A.part("Moss", "TR_Moss_Broadleaf", shadow=False)
    sws = []
    tops = []
    for i, (offset, lean_dir, lean, H, r0, crown_from, n_br) in enumerate(stems):
        c = Vector((offset[0], offset[1], 0.0))
        tops.append(c + lean_dir * (math.tan(lean) * H * 0.8) + UP * (H * 0.7))
    cx = sum((t.x for t in tops)) / len(tops)
    cy = sum((t.y for t in tops)) / len(tops)
    czs = [s[3] for s in stems]
    outw = outward_ellipsoid(Vector((cx, cy, sum(czs) / len(czs) * 0.68)), 6.0, 6.0, 9.0, upk=0.2)
    for i, (offset, lean_dir, lean, H, r0, crown_from, n_br) in enumerate(stems):
        parts = {"base": base, "white": whites[i]}
        sw = birch_stem(rng, A, parts, Vector((offset[0], offset[1], 0.0)), lean_dir, lean, H, r0, crown_from,
                        atlas, outw, fol, wood, n_br, 0.85 if len(stems) == 1 else 1.1,
                        14 if len(stems) == 1 else 11)
        sws.append((sw, r0))
    A.texel = texel_at(sws[0][0])
    for sw, r0 in sws:
        root_arms(roots, rng, sw, 4, r0, sw.lobe_phase, reach=(1.8, 2.4), thick=0.34, lobes=4)
        base_moss(moss, rng, sw, atlas, n=2, z_max=1.6)
    e = A.done()
    if e["tris"] > budget:
        lib.warnings.append("%s has %d tris (budget %d)" % (name, e["tris"], budget))
    return e


OAK_SECTION = [(1.0, 0.0), (0.96, 0.62), (0.82, 1.0), (-0.82, 1.0), (-0.96, 0.62),
               (-1.0, 0.0), (-0.86, -0.62), (-0.4, -0.98), (0.4, -0.98), (0.86, -0.62)]


def build_oak(lib, notes):
    """Broad old pedunculate oak: short massive bole, 4 thick limbs that run out LEVEL (flat, standable tops,
    Perch1..4) and then climb and fork; branches grow out to ~90 lobed-leaf clumps spread over a broad dome."""
    rng = random.Random(9090)
    name = "OakA"
    A = Asset(lib, name, "Tree", ["Broadleaf", "Realistic", "Oak"], notes)
    climb = A.part("Bark", "TR_Bark_Oak", collide=True, collision="PreciseConvexDecomposition", tags=["Climbable"])
    wood = A.part("Branches", "TR_Bark_Oak")
    roots = A.part("Roots", "TR_Bark_Oak")
    fol = A.part("Foliage", "TR_Broadleaf_Oak", cards=True)
    moss = A.part("Moss", "TR_Moss_Broadleaf", shadow=False)
    atlas = "BroadleafAtlas"
    H_bole = 11.0
    r0 = 1.85
    sw = build_trunk(climb, rng, H_bole + 2.5, r0, 0.9, lean=(rng.uniform(0, TAU), 0.01), wiggle=0.3, sides=14,
                     tile_studs=tx.BARK_TILE_STUDS["oak"], step=2.2, tip=0.0, flare=0.5, flare_h=1.4, lobes=6,
                     lobe_amp=0.3, lobe_h=1.1, power=0.7)
    A.texel = texel_at(sw)
    root_arms(roots, rng, sw, 6, r0, sw.lobe_phase, reach=(1.8, 2.4), thick=0.42, lobes=6)
    base_moss(moss, rng, sw, atlas, n=5, z_max=2.8)
    skeleton = []
    limbs = [(9.6, 20, 11.5, 2.05), (11.4, 112, 10.5, 2.0), (12.6, 205, 12.0, 1.98), (14.4, 292, 9.5, 1.95)]
    for i, (hb, azd, reach, w) in enumerate(limbs):
        a = math.radians(azd) + rng.uniform(-0.1, 0.1)
        d = hdir(a)
        sd = Vector((-d.y, d.x, 0))
        c = sw.center(z_to_s(sw, hb))
        level = reach * 0.42
        pts = [c - d * 0.4, c + d * (r0 * 0.7), c + d * (r0 * 0.9 + level * 0.5),
               c + d * (r0 * 0.9 + level) + UP * 0.05, c + d * (reach * 0.72) + UP * 2.2 + sd * rng.uniform(-0.6, 0.6),
               c + d * reach + UP * 5.2 + sd * rng.uniform(-0.9, 0.9)]
        path = Path(pts, 6)
        lvl_end = (r0 * 0.9 + level + 0.4) / path.length

        def sec(s, th, w=w, lvl_end=lvl_end):
            k = int(round(th / (TAU / 10))) % 10
            sx, sy = OAK_SECTION[k]
            taper = 1.0 - 0.55 * smooth01(lvl_end * 0.8, 1.0, s)
            blend = smooth01(lvl_end * 0.85, lvl_end * 1.25, s)
            ang = TAU * k / 10
            x = lerp(sx, math.cos(ang), blend) * w * 0.5 * taper * 1.08
            y = lerp(sy * 0.85, math.sin(ang), blend) * w * 0.5 * taper * 0.95
            return (y, -x)         # (N = up, B = side): flat top faces up, ring runs N -> B like sweep()
        ss = [0.0, 0.08, 0.16, 0.24, 0.32, 0.4, 0.5, 0.62, 0.75, 0.88, 1.0]
        limb_sw = sweep(climb, None, ss, sec, 10, tiles=1, up_lock=True, path=path, tip=0.3)
        u = (r0 * 0.9 + level * 0.45) / path.length
        P, T = path.at(u)
        top_y = max(limb_sw.rings_pos[2][k].z for k in range(10))
        lib.attach(A.root, "Perch%d" % (i + 1), (P.x, P.y, top_y), look=(d.x, d.y, 0.0), up=(0, 0, 1))
        widths = []
        for ri in (2, 3, 4):
            ring = limb_sw.rings_pos[ri]
            topv = [p for p in ring if p.z > top_y - 0.06]
            if len(topv) >= 2:
                widths.append(max((p - q).length for p in topv for q in topv))
        print("PERCH %s %d: top z %.2f, flat width %s" % (name, i + 1, top_y, ["%.2f" % x for x in widths]))
        for k in range(5, 21):
            skeleton.append(path.at(0.45 + 0.55 * (k - 5) / 15)[0])
        # two forks off the climbing end of each limb
        for j in range(2):
            q, T = path.at(rng.uniform(0.6, 0.85))
            fdir = (T + sd * rng.choice((-1, 1)) * rng.uniform(0.6, 1.0) + UP * 0.6).normalized()
            Lf = reach * rng.uniform(0.35, 0.5)
            fp = [q, q + fdir * (Lf * 0.5), q + fdir * Lf + UP * 0.8]
            sweep(wood, fp, [0.0, 0.5, 1.0], lambda s_, th, w=w: w * 0.22 * (1.0 - 0.6 * s_), 6, tip=0.1)
            skeleton.extend([fp[1], fp[2]])
    cen = sw.center(1.0)
    lead = [cen - UP * 1.0, cen + UP * 3.0 + hdir(rng.uniform(0, TAU)) * 0.6, cen + UP * 7.5 + hdir(rng.uniform(0, TAU)) * 1.2,
            cen + UP * 11.0]
    lp = Path(lead, 6)
    sweep(climb, None, [0.0, 0.3, 0.6, 1.0], lambda s_, th: 0.95 * (1.0 - 0.7 * s_), 10, path=lp, tip=0.3)
    for k in range(10):
        skeleton.append(lp.at(0.25 + 0.75 * k / 9)[0])
    crown_c = Vector((0.0, 0.0, 17.5))
    ax, az_ = 13.0, 9.2
    outw = outward_ellipsoid(crown_c, ax, ax, az_, upk=0.25)
    outer = shell_points(rng, crown_c, ax, ax, az_, 9000, 2.95, 9.2, (0.8, 1.0), -0.72, lumpy=0.13)
    inner = shell_points(rng, crown_c, ax * 0.7, ax * 0.7, az_ * 0.7, 800, 4.0, 12.0, (0.85, 1.0), -0.2)
    clusters = outer + inner[:18]
    grow_to_clusters(wood, rng, skeleton, clusters, lambda L: clamp(0.07 + 0.025 * L, 0.09, 0.3), sides=4)
    for P in outer:
        leaf_cluster(fol, rng, P, outw, atlas, ("oakA", "oakB"), rng.randint(5, 6), 3.3)
    for P in inner[:18]:
        leaf_cluster(fol, rng, P, outw, atlas, ("oakA", "oakB"), 3, 3.0, segs=1)
    print("OAK clusters: %d outer, %d inner" % (len(outer), min(18, len(inner))))
    e = A.done()
    if e["tris"] > 9000:
        lib.warnings.append("%s has %d tris (budget 9000)" % (name, e["tris"]))
    return e


# ================================================================================================
# Dead and fallen
# ================================================================================================
def bark_field(rng, keep_fn):
    """Positive where bark remains, negative where it has fallen off (bare wood)."""
    seed = Vector((rng.uniform(-40, 40), rng.uniform(-40, 40), rng.uniform(-40, 40)))

    def f(s, th):
        n = noise.noise(seed + Vector((math.cos(th) * 1.4, math.sin(th) * 1.4, s * 9.0)))
        n += 0.5 * noise.noise(seed * 1.7 + Vector((math.cos(th) * 3.2, math.sin(th) * 3.2, s * 21.0)))
        return keep_fn(s) - n
    return f


def dead_branch(mb, rng, start, d, L, r, fol=None, atlas=None, depth=0):
    """A bare dead branch with a couple of forks; the finest twigs are cards from the dead-twig region."""
    side = d.cross(UP)
    side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
    pts = [start]
    p = start.copy()
    dirv = d.copy()
    for k in range(3):
        dirv = (dirv + side * rng.uniform(-0.35, 0.35) + UP * rng.uniform(-0.25, 0.15)).normalized()
        p = p + dirv * (L / 3)
        pts.append(p.copy())
    sweep(mb, pts, [0.0, 0.33, 0.66, 1.0], lambda s_, th: r * (1.0 - 0.7 * s_), 4 if r > 0.08 else 3, tip=0.05)
    if depth < 1:
        for k in range(rng.randint(1, 3)):
            q = pts[rng.randint(1, 2)]
            fd = (dirv + side * rng.choice((-1, 1)) * rng.uniform(0.5, 1.0) + UP * rng.uniform(-0.2, 0.4)).normalized()
            dead_branch(mb, rng, q, fd, L * rng.uniform(0.35, 0.5), r * 0.55, fol, atlas, depth + 1)
    if fol is not None and rng.random() < 0.8:
        tipp = pts[-1]
        al = (dirv + Vector((0, 0, rng.uniform(-0.2, 0.3)))).normalized()
        rt = al.cross(UP) if al.cross(UP).length > 1e-3 else side
        ln = rng.uniform(1.6, 2.2)
        card(fol, tipp - al * (ln * 0.55), al, rot_about(rt, al, rng.uniform(-0.8, 0.8)), ln, ln, atlas,
             "deadtwig", bend=rng.uniform(-0.3, 0.2), outward=outward_conifer(), segs=1)


def build_snag(lib, name, seed, H, r0, lean, mossy, notes):
    rng = random.Random(seed)
    A = Asset(lib, name, "Tree", ["Dead", "Realistic", "Snag"], notes)
    barkp = A.part("Bark", "TR_Bark_Snag", collide=True, collision="Hull")
    woodp = A.part("DeadWood", "TR_Deadwood", collide=True, collision="Hull")
    stubs = A.part("Branches", "TR_Deadwood")
    roots = A.part("Roots", "TR_Bark_Snag")
    fol = A.part("Foliage", "TR_Conifer_Dead", cards=True)
    moss = A.part("Moss", "TR_Moss", shadow=False)
    atlas = "ConiferAtlas"
    tmp = MB()
    la = rng.uniform(0, TAU)
    ctrl = [Vector((0.0, 0.0, -0.6)), Vector((0.0, 0.0, 0.0))]
    ld = hdir(la)
    ph = rng.uniform(0, TAU)
    for i in range(1, 7):
        f = i / 6
        off = ld * (math.tan(lean) * H * f) + Vector((math.sin(ph + f * 5), math.cos(ph + f * 4), 0)) * 0.18 * f
        ctrl.append(Vector((off.x, off.y, H * f * math.cos(lean))))
    path = Path(ctrl)
    z0 = -0.6
    r_at, lph = trunk_section(rng, H, r0, r0 * 0.62, flare=0.4, lobes=5, lobe_amp=0.3, power=0.8)
    zs = z_samples(H, z0, step=0.7)
    ss = [clamp((z - z0) / (H - z0), 0.0, 1.0) for z in zs]
    tiles = max(1, int(round(TAU * r0 / tx.BARK_TILE_STUDS["deadwood"])))
    sw = sweep(tmp, None, ss, lambda s, th: r_at(z0 + s * (H - z0), th), 16, tiles=tiles, path=path,
               ref=Vector((1, 0, 0)))
    sw.z0, sw.H, sw.lobe_phase = z0, H, lph
    A.texel = texel_at(sw)
    keep = (lambda s: lerp(0.55, -0.55, s)) if not mossy else (lambda s: lerp(0.35, -0.3, s))
    contour_split(tmp, sw, bark_field(rng, keep), barkp, woodp)
    jagged_end(woodp, sw, rng, depth=1.9 if not mossy else 1.3, inward=0.3, hollow=0.6, shard=0.3)
    root_arms(roots, rng, sw, 5, r0, sw.lobe_phase)
    dead_stubs(stubs, rng, sw, 2.5, H - 1.5, int(H * 0.8), length=(0.3, 1.1), r=(0.06, 0.13))
    nb = 12 if not mossy else 6
    for k in range(nb):
        z = rng.uniform(H * 0.3, H - 2.0)
        s = z_to_s(sw, z)
        a = rng.uniform(0, TAU)
        d = (hdir(a) * math.cos(math.radians(rng.uniform(-25, 15))) + UP * math.sin(math.radians(rng.uniform(-25, 15)))).normalized()
        dead_branch(stubs, rng, sw.center(s), d, rng.uniform(2.4, 4.6), rng.uniform(0.11, 0.17), fol, atlas)
    if mossy:
        for k in range(12):
            s0 = rng.uniform(0.0, 0.7)
            ln = rng.uniform(0.06, 0.16)
            th = rng.uniform(0, TAU)
            r = sw.radius(s0)
            decal(moss, sw, s0, min(0.95, s0 + ln), th, clamp(2.2 / max(r, 0.3), 0.8, 2.4), atlas, "moss", lift=0.05)
        base_moss(moss, rng, sw, atlas, n=5, z_max=3.0)
    else:
        base_moss(moss, rng, sw, atlas, n=3, z_max=1.8)
    return A.done()


def build_log(lib, name, seed, L, r0, sink, mossy, notes, cut_end=True):
    rng = random.Random(seed)
    A = Asset(lib, name, "Prop", ["Dead", "Realistic", "Log"], notes)
    barkp = A.part("Bark", "TR_Bark_Log", collide=True, collision="Hull")
    woodp = A.part("DeadWood", "TR_Deadwood_Rot", collide=True, collision="Hull")
    cut = A.part("CutFace", "TR_EndGrain_Old" if mossy else "TR_EndGrain", shadow=False)
    moss = A.part("Moss", "TR_Moss", shadow=False)
    atlas = "ConiferAtlas"
    tmp = MB()
    zc = r0 - sink
    sag = rng.uniform(0.1, 0.25)
    bendy = rng.uniform(-0.4, 0.4)
    ctrl = []
    for i in range(6):
        f = i / 5
        x = -L / 2 + L * f
        ctrl.append(Vector((x, bendy * math.sin(math.pi * f), zc - sag * math.sin(math.pi * f))))
    r_end = r0 * 0.82
    seedv = Vector((rng.uniform(-40, 40), rng.uniform(-40, 40), 0))

    def sec(s, th):
        r = lerp(r0, r_end, s)
        r *= 1.0 + 0.05 * noise.noise(seedv + Vector((math.cos(th) * 1.2, math.sin(th) * 1.2, s * 6.0)))
        if mossy:
            r *= 1.0 - 0.08 * max(0.0, -math.cos(th))     # settled, slightly flattened underside
        return r
    n_r = 34 if L > 16 else 26
    ss = [i / (n_r - 1) for i in range(n_r)]
    tiles = max(1, int(round(TAU * r0 / tx.BARK_TILE_STUDS["conifer"])))
    sw = sweep(tmp, ctrl, ss, sec, 14, tiles=tiles, ref=UP)
    A.texel = sw.tiles * tx.N / (TAU * sw.radius(0.5))
    keep = (lambda s: 0.35) if not mossy else (lambda s: -0.05 + 0.3 * abs(s - 0.5))
    contour_split(tmp, sw, bark_field(rng, keep), barkp, woodp)
    # ends: a sawn end (end grain) and a broken, splintered end
    if cut_end:
        cap_disc(cut, sw, ring=0, uvr=tx.region_uv(atlas, "endgrain"), facing=-1)
    else:
        jagged_end(woodp, sw, rng, depth=0.8, inward=0.35, hollow=0.45, ring=0, facing=-1)
    jagged_end(woodp, sw, rng, depth=1.4 if not mossy else 0.9, inward=0.35, hollow=0.5 if mossy else 0.3)
    # branch stubs
    for k in range(rng.randint(3, 6)):
        s = rng.uniform(0.1, 0.9)
        th = rng.uniform(0, TAU)
        if math.cos(th) < -0.4:
            continue
        p, n = sw.surface(s, th)
        ln = rng.uniform(0.3, 0.9)
        sweep(woodp, [p - n * 0.15, p + n * (ln * 0.6), p + n * ln + UP * 0.1], [0.0, 0.5, 1.0],
              lambda s_, th_: 0.11 * (1 - 0.5 * s_), 4, tip=0.05)
    # moss on top
    nm = 26 if mossy else 5
    for k in range(nm):
        s0 = rng.uniform(0.02, 0.85)
        ln = rng.uniform(0.1, 0.24) if mossy else rng.uniform(0.05, 0.1)
        th = rng.uniform(-1.1, 1.1)                      # theta 0 = top of the log
        decal(moss, sw, s0, min(0.99, s0 + ln), th, rng.uniform(1.2, 2.2), atlas, "moss", lift=0.05)
    e = A.done()
    if e["tris"] > 2500:
        lib.warnings.append("%s has %d tris (budget 2500)" % (name, e["tris"]))
    return e


def build_stump(lib, name, seed, r0, h_top, broken, notes):
    rng = random.Random(seed)
    A = Asset(lib, name, "Prop", ["Dead", "Realistic", "Stump"], notes)
    barkp = A.part("Bark", "TR_Bark_Log" if not broken else "TR_Bark_Snag", collide=True, collision="Hull")
    woodp = A.part("DeadWood", "TR_Deadwood_Rot", collide=True, collision="Hull")
    cut = A.part("CutFace", "TR_EndGrain", shadow=False)
    roots = A.part("Roots", "TR_Bark_Log" if not broken else "TR_Bark_Snag")
    moss = A.part("Moss", "TR_Moss", shadow=False)
    atlas = "ConiferAtlas"
    tmp = MB()
    z0 = -0.5
    r_at, ph = trunk_section(rng, 30.0, r0, r0 * 0.6, flare=0.5, flare_h=0.7, lobes=5, lobe_amp=0.35, lobe_h=0.6,
                             power=1.0)
    zs = [z0, 0.0, 0.25, 0.6, 1.0, 1.5, h_top]
    ss = [(z - z0) / (h_top - z0) for z in zs]
    ctrl = [Vector((0, 0, z0)), Vector((0, 0, h_top))]
    tiles = max(1, int(round(TAU * r0 / tx.BARK_TILE_STUDS["conifer"])))
    sw = sweep(tmp, ctrl, ss, lambda s, th: r_at(z0 + s * (h_top - z0), th), 14, tiles=tiles, per=1,
               ref=Vector((1, 0, 0)))
    sw.z0, sw.H, sw.lobe_phase = z0, h_top, ph
    A.texel = texel_at(sw)
    keep = (lambda s: 0.6) if not broken else (lambda s: lerp(0.4, -0.2, s))
    contour_split(tmp, sw, bark_field(rng, keep), barkp, woodp)
    if not broken:
        cap_disc(cut, sw, ring=-1, uvr=tx.region_uv(atlas, "endgrain"), facing=1)
    else:
        jagged_end(woodp, sw, rng, depth=1.6, inward=0.25, hollow=0.9)
    root_arms(roots, rng, sw, 5, r0, ph, reach=(1.9, 2.5), h=(0.5, 0.9), thick=0.42)
    base_moss(moss, rng, sw, atlas, n=4 if broken else 3, z_max=1.2)
    e = A.done()
    if e["tris"] > 2500:
        lib.warnings.append("%s has %d tris (budget 2500)" % (name, e["tris"]))
    return e


# ================================================================================================
# Build + export
# ================================================================================================
NOTES = {
    "SpruceA": "Tall mature Norway spruce, ~54 studs: conical crown from ~9 studs, sagging tiers with hanging "
               "branchlet curtains, dead self-pruned stubs below. Trunk Hull; branches, roots, cards walk-through.",
    "SpruceB": "Medium spruce, ~35 studs, fuller and lower crowned (live branches from ~3.5 studs).",
    "FirA": "Silver fir, ~41 studs: dense, narrow, regular tiers of flat sprays with upturned tips, smooth grey bark.",
    "PineA": "Scots pine, ~52 studs: bare straight bole (grey furrowed lower bark, orange plated upper bark), "
             "high irregular crown of sinuous limbs ending in needle brushes.",
    "ConiferYoung": "Young spruce, ~11 studs, branches to the ground. Trunk Hull.",
    "BirchA": "Single-stem silver birch, ~29 studs: white bark with black lenticels and a black fissured base, "
              "airy crown of hanging leafy strands.",
    "BirchB": "Three-stem birch clump, ~27 studs. Each stem collides on its own (Hull); the shared black base "
              "is one Hull.",
    "OakA": "Broad old oak, ~27 tall x ~28 wide. 4 thick limbs run out level with flat standable tops "
            "(Perch1-4 at their centres); trunk + limbs are one PreciseConvexDecomposition part tagged Climbable.",
    "SnagA": "Dead standing conifer with a splintered broken top, bark sloughing off to silver wood.",
    "SnagB": "Leaning, mossy dead conifer (leans away from the pivot), broken top.",
    "FallenLogA": "Fallen conifer log along X (~14.5 long): sawn end grain at -X, splintered break at +X.",
    "FallenLogB": "Mossy, rotting log along X (~21 long), top ~2.3 (hop-on); both ends broken.",
    "StumpA": "Sawn stump, top ~2.1 (hop-on) with growth rings, flaring roots.",
    "StumpB": "Broken, rotten stump, splintered hollow top, moss.",
}

SINGLE = {"TreesReal": ["SpruceA", "SpruceB", "FirA", "PineA", "ConiferYoung", "BirchA", "BirchB", "OakA",
                        "SnagA", "SnagB", "FallenLogA", "FallenLogB", "StumpA", "StumpB"]}
GROUPS = {
    "TreesReal_Conifers": ["SpruceA", "SpruceB", "FirA", "PineA", "ConiferYoung"],
    "TreesReal_Broadleaf": ["BirchA", "BirchB", "OakA"],
    "TreesReal_Deadwood": ["SnagA", "SnagB", "FallenLogA", "FallenLogB", "StumpA", "StumpB"],
}


def build_all(lib, only=None):
    def want(n):
        return only is None or n in only
    entries = []
    if want("SpruceA"):
        entries.append(build_conifer(lib, "SpruceA", 1101, 54.0, 1.05, 9.0, 8.6, 1.9, 5, "spruce",
                                     {"bark": "TR_Bark_Spruce", "foliage": "TR_Conifer_Spruce"}, NOTES["SpruceA"]))
    if want("SpruceB"):
        entries.append(build_conifer(lib, "SpruceB", 2202, 35.0, 0.78, 3.6, 7.4, 1.8, 5, "spruce",
                                     {"bark": "TR_Bark_Spruce", "foliage": "TR_Conifer_SpruceB"}, NOTES["SpruceB"]))
    if want("FirA"):
        entries.append(build_conifer(lib, "FirA", 3303, 41.0, 0.85, 4.5, 5.6, 1.72, 5, "fir",
                                     {"bark": "TR_Bark_Fir", "foliage": "TR_Conifer_Fir"}, NOTES["FirA"]))
    if want("PineA"):
        entries.append(build_pine(lib, NOTES["PineA"]))
    if want("ConiferYoung"):
        entries.append(build_young(lib, NOTES["ConiferYoung"]))
    if want("BirchA"):
        entries.append(build_birch(lib, "BirchA", 5505, [((0.0, 0.0), hdir(0.7), math.radians(3.0), 29.0, 0.72,
                                                         9.5, 22)], NOTES["BirchA"]))
    if want("BirchB"):
        stems = [((0.55, 0.1), hdir(0.2), math.radians(9.0), 27.0, 0.52, 9.0, 13),
                 ((-0.4, 0.45), hdir(2.3), math.radians(11.0), 25.0, 0.48, 8.5, 12),
                 ((-0.25, -0.5), hdir(4.3), math.radians(7.0), 26.0, 0.5, 9.0, 12)]
        entries.append(build_birch(lib, "BirchB", 6606, stems, NOTES["BirchB"]))
    if want("OakA"):
        entries.append(build_oak(lib, NOTES["OakA"]))
    if want("SnagA"):
        entries.append(build_snag(lib, "SnagA", 7707, 26.0, 0.95, 0.004, False, NOTES["SnagA"]))
    if want("SnagB"):
        entries.append(build_snag(lib, "SnagB", 8808, 19.0, 0.85, 0.24, True, NOTES["SnagB"]))
    if want("FallenLogA"):
        entries.append(build_log(lib, "FallenLogA", 9191, 14.5, 0.95, 0.12, False, NOTES["FallenLogA"]))
    if want("FallenLogB"):
        entries.append(build_log(lib, "FallenLogB", 9292, 21.0, 1.25, 0.18, True, NOTES["FallenLogB"],
                                 cut_end=False))
    if want("StumpA"):
        entries.append(build_stump(lib, "StumpA", 9393, 1.3, 2.1, False, NOTES["StumpA"]))
    if want("StumpB"):
        entries.append(build_stump(lib, "StumpB", 9494, 1.15, 2.7, True, NOTES["StumpB"]))
    return entries


def _glb_split(data):
    import struct
    magic, ver, _len = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("not a GLB")
    clen, ctype = struct.unpack_from("<II", data, 12)
    if ctype != 0x4E4F534A:
        raise ValueError("first GLB chunk is not JSON")
    return ver, json.loads(data[20:20 + clen].decode("utf-8")), data[20 + clen:]


def glb_set_metallic_zero(path):
    """Set metallicFactor = 0 on every material in the GLB's JSON chunk (the binary chunk is untouched)."""
    import struct
    with open(path, "rb") as f:
        data = f.read()
    ver, js, rest = _glb_split(data)
    n = 0
    for m in js.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if pbr.get("metallicFactor", 1.0) != 0:
            pbr["metallicFactor"] = 0
            n += 1
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)                     # JSON chunk is padded with spaces to 4 bytes
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, ver, 12 + len(body)) + body)
    return n


def glb_check(path, tex_dir=None):
    """Read the exported GLB's JSON chunk and report what Roblox will get: every primitive must carry TANGENT
    (MikkTSpace; without tangents Roblox ignores the normal maps), TEXCOORD_0 and NORMAL; no material may be
    metallic; cut-out cards must be alphaMode MASK and none double-sided; every embedded image must be the
    PNG file of the same name byte for byte (so the GLB and the textures folder can never disagree)."""
    with open(path, "rb") as f:
        _ver, js, _rest = _glb_split(f.read())
    prims = [(m["name"], p) for m in js.get("meshes", []) for p in m["primitives"]]
    miss = {a: sorted({n for n, p in prims if a not in p["attributes"]}) for a in ("TANGENT", "TEXCOORD_0", "NORMAL")}
    mats = js.get("materials", [])
    metal = sorted(m["name"] for m in mats if m.get("pbrMetallicRoughness", {}).get("metallicFactor", 1.0) != 0)
    double = sorted(m["name"] for m in mats if m.get("doubleSided"))
    img_mismatch = []
    if tex_dir:
        for im in js.get("images", []):
            nm = im.get("name", "")
            cands = [os.path.join(tex_dir, nm + ".png"), os.path.join(tex_dir, "glb_only", nm + ".png")]
            src = next((c for c in cands if os.path.exists(c)), None)
            blen = js["bufferViews"][im["bufferView"]]["byteLength"]
            if src is None or os.path.getsize(src) != blen:
                img_mismatch.append(nm)
    return {"primitives": len(prims), "images": len(js.get("images", [])), "materials": len(mats),
            "missing": miss, "metallic": metal, "doubleSided": double, "imageMismatch": img_mismatch,
            "alphaMask": sorted(m["name"] for m in mats if m.get("alphaMode") == "MASK")}


def export(lib, out_dir, tex_dir, groups, gap=8.0):
    """One GLB per group (assets in a row along X, 'origin' recorded per asset), one manifest for all."""
    for e in lib.assets:
        if "size" not in e:
            lib.finish(e["root"])
    by_name = {e["name"]: e for e in lib.assets}
    glbs = []
    for gname, names in groups.items():
        members = [by_name[n] for n in names if n in by_name]
        if not members:
            continue
        x = 0.0
        for e in members:
            offset = x - e["boundsMin"][0]
            e["root"].location = (offset, 0.0, 0.0)
            e["origin"] = [round(offset, 4), 0.0, 0.0]
            e["glb"] = gname + ".glb"
            x += e["size"][0] + gap
        bpy.context.view_layer.update()
        for obj in bpy.context.scene.objects:
            obj.select_set(False)
        for e in members:
            e["root"].select_set(True)
            for c in e["root"].children_recursive:
                c.select_set(True)
        path = os.path.join(out_dir, gname + ".glb")
        # tangents ON: Roblox needs them on imported meshes or the normal maps have no effect (MikkTSpace, the
        # same basis the bakes assume). Every part has a UV map (MB.to_object), which tangent export requires.
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                                  export_normals=True, export_tangents=True, export_texcoords=True,
                                  export_materials="EXPORT", export_image_format="AUTO")
        n_metal = glb_set_metallic_zero(path)
        mb = os.path.getsize(path) / (1024 * 1024)
        chk = glb_check(path, tex_dir)
        ok_t = not chk["missing"]["TANGENT"]
        glbs.append({"file": gname + ".glb", "assets": [e["name"] for e in members], "sizeMB": round(mb, 2),
                     "bytes": os.path.getsize(path), "primitives": chk["primitives"], "embeddedImages": chk["images"],
                     "tangents": ok_t})
        print("EXPORTED %s (%.2f MB), %d assets" % (path, mb, len(members)))
        print("GLBCHECK %s: %d primitives, TANGENT missing on %d, TEXCOORD_0 missing on %d, NORMAL missing on %d; "
              "%d images (not identical to their PNG: %s), %d materials (%d MASK; metallicFactor set to 0 on %d), "
              "metallic %s, doubleSided %s"
              % (gname, chk["primitives"], len(chk["missing"]["TANGENT"]), len(chk["missing"]["TEXCOORD_0"]),
                 len(chk["missing"]["NORMAL"]), chk["images"], chk["imageMismatch"] or "none", chk["materials"],
                 len(chk["alphaMask"]), n_metal, chk["metallic"] or "none", chk["doubleSided"] or "none"))
        if chk["imageMismatch"]:
            lib.warnings.append("%s: embedded images differ from the PNG files: %s" % (gname, chk["imageMismatch"]))
        for attr, names in chk["missing"].items():
            if names:
                lib.warnings.append("%s: %d primitives without %s (%s)" % (gname, len(names), attr,
                                                                          ", ".join(names[:6])))
        if chk["metallic"]:
            lib.warnings.append("%s: metallic materials %s" % (gname, chk["metallic"]))
        if chk["doubleSided"]:
            lib.warnings.append("%s: doubleSided materials %s" % (gname, chk["doubleSided"]))
        if mb > 18.0:
            lib.warnings.append("%s is %.1f MB (> 18 MB: split further)" % (gname, mb))
        for e in members:
            e["root"].location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
    return glbs


def write_manifest(lib, out_dir, tex_dir, glbs, notes=()):
    textures = {}
    for key in TEXSETS:
        c, n, r = texset_files(key)
        for f, kind in ((c, "color"), (n, "normal"), (r, "roughness")):
            p = tex_path(tex_dir, f)
            if f not in textures:
                textures[f] = {"kind": kind, "set": key if kind != "roughness" else None,
                               "bytes": os.path.getsize(p), "alpha": bool(TEXSETS[key]["alpha"]) and kind == "color",
                               "usedBy": []}
    for e in lib.assets:
        for p in e["parts"]:
            sa = p["surfaceAppearance"]
            for f in (sa["colorMap"], sa["normalMap"], sa["roughnessMap"]):
                if e["name"] not in textures[f]["usedBy"]:
                    textures[f]["usedBy"].append(e["name"])
    glb_only = {}
    for kind, f in tx.ROUGH_GLB_FILES.items():
        glb_only[f] = {"kind": "metallicRoughness (glTF packing: R = G = roughness, B = metalness 0)",
                       "bytes": os.path.getsize(tex_path(tex_dir, f)),
                       "note": "embedded in the GLB instead of %s - never upload it separately" % tx.ROUGH_FILES[kind]}
    import numpy as np
    rough_mean = {}
    for kind, f in tx.ROUGH_FILES.items():
        img = load_image(tex_path(tex_dir, f), "Non-Color")
        px = np.array(img.pixels[:], dtype=np.float64).reshape(-1, img.channels)[:, 0]
        rough_mean[kind] = round(float(px.mean()), 3)
    materials = {}
    for key, (tset, tint, amode, cut) in MATS.items():
        materials[key] = {"textureSet": tset, "tint": list(tint), "alphaMode": amode,
                          "regions": MAT_REGIONS.get(key), "albedoMeanSrgb": fallback_rgb(tex_dir, key),
                          "roughnessMean": rough_mean[TEXSETS[tset]["rough"]], "metalness": 0}
    manifest = {
        "category": CATEGORY,
        "glbs": glbs,
        "units": "1 Blender unit = 1 Roblox stud",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
        "tangentSpace": "MikkTSpace tangents exported (glTF TANGENT on every primitive, checked after export); "
                        "normal maps are OpenGL (+Y), tangent space",
        "textureFolder": "textures/TreesReal",
        "textures": textures,
        "glbOnlyTextures": glb_only,
        "materials": materials,
        "import": [
            "Geometry: import each GLB (3D Importer / Open Cloud Model). Every asset root arrives as a Model of "
            "MeshParts named <Asset>_<Role>[_n]; re-centre with the asset 'origin' (WorldPivot = CFrame.new(origin), "
            "then PivotTo) exactly like the other categories. The meshes carry tangents, so normal maps work.",
            "Surfaces: give every part ONE SurfaceAppearance built from its 'surfaceAppearance' block: ColorMap / "
            "NormalMap / RoughnessMap = the uploaded image ids of those PNG files (each file once - 14 images in "
            "total, shared by every asset; RoughnessMap uses the separate 8-bit grayscale TR_Rough_*.png), "
            "MetalnessMap empty (nothing is metal), AlphaMode as given, Color = 'color' (sRGB tint; it multiplies "
            "the ColorMap - the species differ only by these tints, so never skip it). Do not rely on the "
            "importer's auto SurfaceAppearance for roughness: the GLB packs roughness into a glTF metallicRoughness "
            "image (glb_only/*_MR.png, metallicFactor 0). Clear any importer-created TextureID.",
            "Cards (backFacesInMesh = true) already contain flipped back faces: keep MeshPart.DoubleSided = false "
            "(otherwise the back sides z-fight) and MeshPart.Transparency = 0 so AlphaMode Transparency is an "
            "alpha cut-out (no sorting). Each alpha part says so in its 'alphaSetup'.",
            "Per part: CanCollide = collide, CollisionFidelity = collision, CastShadow = castShadow, "
            "CanQuery = canQuery, CanTouch = canTouch, Anchored = true; Material = robloxMaterial (physics/sounds only, "
            "the look comes from the SurfaceAppearance); 'rgb' is a fallback MeshPart.Color matching the texture.",
            "OakA: OakA_Bark gets the CollectionService tag Climbable; attachments Perch1..N as in the v1 oaks.",
            "Check in Studio: card shadows should be cut out (dappled); if a crown casts solid card-shaped shadows, "
            "set CastShadow = false on that Foliage part. RenderFidelity Automatic is fine; if far crowns break up, "
            "use Precise on Foliage parts.",
        ],
        "assets": [],
        "notes": ["Trunks, roots and logs continue below y = 0 on purpose (they dive into the soil so a tree on a "
                  "slope never shows a floating edge); the pivot is the ground point at the trunk centre: "
                  + "; ".join(notes)] if notes else [],
        "warnings": lib.warnings,
    }
    for e in lib.assets:
        manifest["assets"].append({k: v for k, v in e.items() if k != "root"})
    path = os.path.join(out_dir, CATEGORY + ".manifest.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    os.makedirs(REPO_MANIFESTS, exist_ok=True)
    shutil.copyfile(path, os.path.join(REPO_MANIFESTS, CATEGORY + ".manifest.json"))
    print("MANIFEST %s (+ copy in art/manifests)" % path)
    import ad_finalize                      # art-direction schema + Roblox import checks (prints ADCHECK)
    manifest = ad_finalize.finalize(CATEGORY, out_dir)
    return manifest


def main():
    out_dir, preview_dir, flags = parse_args()
    t0 = time.time()
    tex_dir = os.path.join(out_dir, "textures", "TreesReal")
    os.makedirs(tex_dir, exist_ok=True)
    need = [f for k in TEXSETS for f in texset_files(k)] + list(tx.ROUGH_GLB_FILES.values())
    if flags.get("textures") or any(not os.path.exists(tex_path(tex_dir, f)) for f in need):
        tx.build_all(tex_dir, debug_dir=None)
    ls.reset()
    lib = TexLibrary(CATEGORY, tex_dir)
    only = set(flags["only"].split(",")) if "only" in flags else None
    build_all(lib, only)
    # bases deliberately continue below the pivot (trunks and roots dive into the soil so trees never float
    # on slopes): report as notes, not warnings
    notes = []
    for w in list(lib.warnings):
        if "below z = 0" in w:
            lib.warnings.remove(w)
            notes.append(w.split(" (")[0])
    test = only is not None and "export" not in flags
    if test:
        glbs = export(lib, out_dir, tex_dir, {"_TreesReal_Test": [e["name"] for e in lib.assets]})
    else:
        for old in list(SINGLE) + list(GROUPS):
            path = os.path.join(out_dir, old + ".glb")
            if os.path.exists(path):
                os.remove(path)
        glbs = export(lib, out_dir, tex_dir, SINGLE)
        # one GLB keeps every shared image embedded once; split (Conifers / Broadleaf / Deadwood) only when it
        # passes 18 MiB or when asked with the 'split' flag
        if glbs[0]["sizeMB"] > 18.0 or flags.get("split"):
            os.remove(os.path.join(out_dir, glbs[0]["file"]))
            lib.warnings = [w for w in lib.warnings if not w.startswith("TreesReal is")]
            glbs = export(lib, out_dir, tex_dir, GROUPS)
        write_manifest(lib, out_dir, tex_dir, glbs, notes)
    for w in lib.warnings:
        print("WARNING " + w)
    print("DONE %d assets, %d warnings, %.0fs" % (len(lib.assets), len(lib.warnings), time.time() - t0))
    if not flags.get("nopreview"):
        import trees_review
        trees_review.render_all(out_dir, preview_dir, [g["file"] for g in glbs], flags)


if __name__ == "__main__":
    main()
