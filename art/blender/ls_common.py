"""
ls_common.py - shared helpers for LAST STANDING Blender asset generators (Blender 5.3, headless).

CONVENTIONS (every generator follows these so the Roblox import can be automated)
- 1 Blender unit = 1 Roblox stud. Blender is Z-up; we export Y-up glTF (GLB), which Roblox imports at
  1 unit = 1 stud. Roblox axes from Blender axes: (x, y, z)_roblox = (x, z, -y)_blender.
- The FRONT of an asset faces Blender +Y (that becomes the Roblox LookVector, -Z).
  Its base rests on z = 0, centred on the origin. (The Library lays assets out in a row when exporting
  and records each asset's origin in the manifest, so the importer can re-centre them.)
- Each asset = a root EMPTY named <Asset> with child meshes named <Asset>_<Role>[_<n>], ONE material per mesh.
  Roles come from ROLES below; the Roblox integration sets MeshPart.Material and MeshPart.Color from the manifest,
  so geometry comes from Blender and the surface comes from Roblox's PBR materials (no textures to upload).
- Roblox limit: 20,000 triangles per mesh. Stay well under the budgets in your brief.
- Watertight meshes, no zero-thickness faces. box_uv() gives every mesh a consistent texel density so
  Roblox materials tile at the same size on every asset.

USAGE
    import os, sys
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    import ls_common as ls

    out_dir, preview_dir = ls.args()
    ls.reset()
    lib = ls.Library("Foliage")
    root = lib.begin("PineA", kind="Tree")
    trunk = ls.cylinder("trunk", radius=0.9, radius_top=0.5, depth=18, segments=10)
    lib.add(root, trunk, "Bark", collide=True, collision="Hull", tags=["Climbable"], smooth_angle=50)
    ...
    lib.finish(root)
    lib.export(out_dir, preview_dir)   # writes <Category>.glb + <Category>.manifest.json + PNG previews

Run headless:
    blender --background --factory-startup --python <script.py> -- <out_dir> <preview_dir>
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------------------------
# Roles: Blender material role -> Roblox material + default sRGB colour (0-255) + preview roughness/metal.
# Add roles here (and tell the integrator) rather than inventing names inside generators.
# --------------------------------------------------------------------------------------------
ROLES = {
    # Trees and plants
    "Bark": {"roblox": "Wood", "rgb": (88, 66, 50)},
    "BirchBark": {"roblox": "Wood", "rgb": (214, 207, 192)},
    "DeadWood": {"roblox": "Wood", "rgb": (112, 100, 86)},
    "Leaves": {"roblox": "LeafyGrass", "rgb": (76, 110, 50)},
    "PineNeedles": {"roblox": "LeafyGrass", "rgb": (50, 82, 52)},
    "BirchLeaves": {"roblox": "LeafyGrass", "rgb": (118, 148, 68)},
    "Bush": {"roblox": "LeafyGrass", "rgb": (68, 102, 46)},
    "Fern": {"roblox": "LeafyGrass", "rgb": (84, 120, 56)},
    "Reed": {"roblox": "Grass", "rgb": (130, 134, 78)},
    "Berry": {"roblox": "SmoothPlastic", "rgb": (148, 32, 52)},
    "Mushroom": {"roblox": "SmoothPlastic", "rgb": (196, 168, 138)},
    "MushroomCap": {"roblox": "SmoothPlastic", "rgb": (160, 62, 44)},
    # Stone and ground
    "Stone": {"roblox": "Rock", "rgb": (118, 116, 110)},
    "DarkStone": {"roblox": "Slate", "rgb": (80, 80, 82)},
    "Basalt": {"roblox": "Basalt", "rgb": (66, 64, 64)},
    "Granite": {"roblox": "Granite", "rgb": (140, 134, 126)},
    "Cobble": {"roblox": "Cobblestone", "rgb": (128, 124, 116)},
    "Paving": {"roblox": "Pavement", "rgb": (124, 120, 112)},
    "Moss": {"roblox": "Grass", "rgb": (86, 108, 56)},
    "Snow": {"roblox": "Snow", "rgb": (236, 240, 244)},
    "Dirt": {"roblox": "Ground", "rgb": (98, 82, 62)},
    # Built materials
    "Wood": {"roblox": "Wood", "rgb": (118, 86, 58)},
    "Planks": {"roblox": "WoodPlanks", "rgb": (126, 94, 64)},
    "DarkPlanks": {"roblox": "WoodPlanks", "rgb": (84, 64, 46)},
    "Logs": {"roblox": "Wood", "rgb": (104, 78, 54)},
    "Thatch": {"roblox": "Grass", "rgb": (158, 138, 88)},
    "RoofTiles": {"roblox": "ClayRoofTiles", "rgb": (122, 70, 52)},
    "Shingles": {"roblox": "RoofShingles", "rgb": (70, 66, 64)},
    "Plaster": {"roblox": "Plaster", "rgb": (196, 186, 166)},
    "Concrete": {"roblox": "Concrete", "rgb": (132, 130, 126)},
    "Brick": {"roblox": "Brick", "rgb": (132, 84, 64)},
    # Metals
    "Metal": {"roblox": "Metal", "rgb": (122, 126, 132), "metal": 0.8, "rough": 0.45},
    "DarkMetal": {"roblox": "Metal", "rgb": (56, 58, 62), "metal": 0.8, "rough": 0.5},
    "Steel": {"roblox": "Metal", "rgb": (172, 176, 182), "metal": 0.9, "rough": 0.3},
    "Brass": {"roblox": "Metal", "rgb": (176, 140, 82), "metal": 0.9, "rough": 0.35},
    "Rust": {"roblox": "CorrodedMetal", "rgb": (118, 80, 58), "metal": 0.5, "rough": 0.8},
    # Soft materials
    "Cloth": {"roblox": "Fabric", "rgb": (150, 140, 120)},
    "Canvas": {"roblox": "Fabric", "rgb": (172, 160, 128)},
    "Banner": {"roblox": "Fabric", "rgb": (198, 94, 46)},
    "Leather": {"roblox": "Leather", "rgb": (100, 66, 44)},
    "DarkLeather": {"roblox": "Leather", "rgb": (58, 42, 32)},
    "Rope": {"roblox": "Fabric", "rgb": (160, 132, 92)},
    "Feather": {"roblox": "Fabric", "rgb": (212, 204, 186)},
    "Bandage": {"roblox": "Fabric", "rgb": (230, 226, 212)},
    "Paper": {"roblox": "Cardboard", "rgb": (204, 188, 150)},
    "Rubber": {"roblox": "Rubber", "rgb": (40, 40, 42)},
    # Special
    "Ember": {"roblox": "Neon", "rgb": (255, 128, 48)},
    "Glass": {"roblox": "Glass", "rgb": (172, 204, 208)},
    "WaterFill": {"roblox": "Glass", "rgb": (110, 160, 190)},
    "Food": {"roblox": "SmoothPlastic", "rgb": (150, 60, 40)},
    "Tin": {"roblox": "Metal", "rgb": (150, 152, 150), "metal": 0.8, "rough": 0.5},
    # Characters (first-person arms)
    "Skin": {"roblox": "SmoothPlastic", "rgb": (204, 160, 128)},
    "Sleeve": {"roblox": "Fabric", "rgb": (52, 56, 60)},
    "Glove": {"roblox": "Leather", "rgb": (70, 52, 40)},
}

TRIANGLE_LIMIT = 20000

_material_cache = {}


def args():
    """(out_dir, preview_dir) from the command line after '--'."""
    argv = sys.argv
    rest = argv[argv.index("--") + 1:] if "--" in argv else []
    out_dir = rest[0] if len(rest) > 0 else os.getcwd()
    preview_dir = rest[1] if len(rest) > 1 else os.path.join(out_dir, "previews")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(preview_dir, exist_ok=True)
    return out_dir, preview_dir


def reset():
    """Empty scene (factory settings)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _material_cache.clear()


def seed(value):
    random.seed(value)


# --------------------------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------------------------
def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(role, rgb=None):
    info = ROLES.get(role)
    if info is None:
        raise ValueError("Unknown role '%s' - add it to ls_common.ROLES" % role)
    rgb = tuple(int(round(v)) for v in (rgb or info["rgb"]))
    default = tuple(info["rgb"])
    name = role if rgb == default else "%s__%d_%d_%d" % (role, rgb[0], rgb[1], rgb[2])
    cached = _material_cache.get(name)
    if cached is not None and cached.name in bpy.data.materials:
        return cached
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    lin = [srgb_to_linear(v / 255.0) for v in rgb]
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        bsdf.inputs["Roughness"].default_value = info.get("rough", 0.85)
        bsdf.inputs["Metallic"].default_value = info.get("metal", 0.0)
        if role == "Ember":
            try:
                bsdf.inputs["Emission Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
                bsdf.inputs["Emission Strength"].default_value = 3.0
            except KeyError:
                pass
    mat.diffuse_color = (lin[0], lin[1], lin[2], 1.0)  # the Workbench preview uses this
    mat.roughness = info.get("rough", 0.85)
    mat.metallic = info.get("metal", 0.0)
    _material_cache[name] = mat
    return mat


# --------------------------------------------------------------------------------------------
# Mesh construction (bmesh based - no operator context needed)
# --------------------------------------------------------------------------------------------
def from_bmesh(name, bm):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _place(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    return obj


def cube(name, size=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return _place(from_bmesh(name, bm), loc, rot)


def cylinder(name, radius=1.0, depth=2.0, segments=12, radius_top=None, loc=(0, 0, 0), rot=(0, 0, 0), cap=True):
    """Cone/cylinder standing on z = 0 (base at the object origin) unless moved."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius_top is None else radius_top, depth=depth)
    bmesh.ops.translate(bm, vec=Vector((0, 0, depth / 2)), verts=bm.verts)
    return _place(from_bmesh(name, bm), loc, rot)


def icosphere(name, radius=1.0, subdivisions=2, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    return _place(from_bmesh(name, bm), loc, rot, scale)


def uvsphere(name, radius=1.0, segments=12, rings=8, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    return _place(from_bmesh(name, bm), loc, rot, scale)


def torus(name, major=1.0, minor=0.2, major_segments=16, minor_segments=8, loc=(0, 0, 0), rot=(0, 0, 0)):
    bm = bmesh.new()
    verts = []
    for i in range(major_segments):
        a = 2 * math.pi * i / major_segments
        ring = []
        for j in range(minor_segments):
            b = 2 * math.pi * j / minor_segments
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        verts.append(ring)
    for i in range(major_segments):
        for j in range(minor_segments):
            a = verts[i][j]
            b = verts[(i + 1) % major_segments][j]
            c = verts[(i + 1) % major_segments][(j + 1) % minor_segments]
            d = verts[i][(j + 1) % minor_segments]
            bm.faces.new((a, b, c, d))
    return _place(from_bmesh(name, bm), loc, rot)


def lathe(name, profile, segments=16, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Revolve a (radius, z) profile list (bottom to top) around Z. Caps the ends when radius > 0."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _place(from_bmesh(name, bm), loc, rot)


def extrude_profile(name, points2d, depth, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Extrude a closed 2D polygon (x, z points, counter-clockwise) along Y by depth (centred). Good for blades."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for (x, z) in points2d]
    back = [bm.verts.new((x, depth / 2, z)) for (x, z) in points2d]
    n = len(points2d)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _place(from_bmesh(name, bm), loc, rot)


def refresh():
    """Make matrix_world reflect location/rotation/scale changes made since the last update."""
    bpy.context.view_layer.update()


def join(objs, name):
    """Merge several mesh objects (with their transforms) into one new object."""
    refresh()
    bm = bmesh.new()
    for o in objs:
        me = o.data.copy()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    return from_bmesh(name, bm)


def duplicate(obj, name=None):
    new = obj.copy()
    new.data = obj.data.copy()
    new.name = name or (obj.name + "_dup")
    bpy.context.scene.collection.objects.link(new)
    return new


# --------------------------------------------------------------------------------------------
# Modifiers and shaping (applied immediately)
# --------------------------------------------------------------------------------------------
def apply_modifiers(obj):
    if not obj.modifiers:
        return obj
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    me = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def bake_transform(obj):
    """Bake location/rotation/scale into the mesh so the object sits at identity."""
    refresh()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    return obj


def subdivide(obj, levels=1, simple=False):
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    if simple:
        mod.subdivision_type = "SIMPLE"
    return apply_modifiers(obj)


def bevel(obj, width=0.05, segments=1, angle_deg=40):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_deg)
    return apply_modifiers(obj)


def decimate(obj, ratio=0.5):
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = ratio
    return apply_modifiers(obj)


def displace(obj, strength=0.3, noise_size=1.0, kind="CLOUDS", seed_offset=None):
    """Noise displacement along normals. seed_offset shifts the noise so variants differ."""
    tex = bpy.data.textures.new(obj.name + "_noise", type=kind)
    if hasattr(tex, "noise_scale"):
        tex.noise_scale = noise_size
    mod = obj.modifiers.new("Displace", "DISPLACE")
    mod.texture = tex
    mod.strength = strength
    helper = None
    if seed_offset is not None:
        helper = bpy.data.objects.new(obj.name + "_noiseorigin", None)
        bpy.context.scene.collection.objects.link(helper)
        helper.location = Vector(seed_offset)
        mod.texture_coords = "OBJECT"
        mod.texture_coords_object = helper
    apply_modifiers(obj)
    if helper is not None:
        bpy.data.objects.remove(helper, do_unlink=True)
    bpy.data.textures.remove(tex)
    return obj


def jitter(obj, amount=0.1, rng=None):
    """Randomly nudge vertices (shared vertices move together, so the mesh stays watertight)."""
    rng = rng or random
    for v in obj.data.vertices:
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount), rng.uniform(-amount, amount)))
    obj.data.update()
    return obj


def taper(obj, factor_top=0.5, axis="Z"):
    """Scale vertices toward the axis based on their height (simple deform without modifiers)."""
    zs = [v.co.z for v in obj.data.vertices]
    lo, hi = min(zs), max(zs)
    span = max(hi - lo, 1e-6)
    for v in obj.data.vertices:
        t = (v.co.z - lo) / span
        s = 1 + (factor_top - 1) * t
        v.co.x *= s
        v.co.y *= s
    obj.data.update()
    return obj


def bend_x(obj, amount=0.2):
    """Gentle bend: offset x by amount * (z/height)^2 (for curved trunks, reeds...)."""
    zs = [v.co.z for v in obj.data.vertices]
    hi = max(max(zs), 1e-6)
    for v in obj.data.vertices:
        t = max(v.co.z, 0) / hi
        v.co.x += amount * t * t * hi
    obj.data.update()
    return obj


def flat(obj):
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def smooth(obj, angle_deg=40):
    for p in obj.data.polygons:
        p.use_smooth = True
    try:
        obj.data.set_sharpness_by_angle(angle=math.radians(angle_deg))
    except Exception:
        pass
    return obj


def box_uv(obj, studs_per_tile=8.0):
    """Box-project UVs in object space so 1 UV unit = studs_per_tile studs (consistent material tiling)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            co = loop.vert.co
            if axis == 0:
                u, v = co.y, co.z
            elif axis == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            loop[uv_layer].uv = (u / studs_per_tile, v / studs_per_tile)
    bm.to_mesh(me)
    bm.free()
    return obj


def clean(obj, merge_dist=1e-4):
    """Merge duplicate vertices, drop loose/degenerate geometry, fix normals."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge_dist)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=merge_dist)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def tri_count(obj):
    if obj.type != "MESH":
        return 0
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def to_roblox(v):
    """Blender (x, y, z) -> Roblox (x, y, z): (x, z, -y)."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def world_bounds(objs):
    refresh()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


# --------------------------------------------------------------------------------------------
# Library: collect assets, validate, preview, export GLB + manifest
# --------------------------------------------------------------------------------------------
class Library:
    def __init__(self, category):
        self.category = category
        self.assets = []
        self.warnings = []

    def _entry(self, root):
        for e in self.assets:
            if e["root"] == root:
                return e
        raise ValueError("root not registered: " + root.name)

    def begin(self, name, kind="Prop", tags=None, notes=""):
        """Start an asset. Returns its root empty (kept at the origin while you build)."""
        if any(e["name"] == name for e in self.assets):
            raise ValueError("duplicate asset name " + name)
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        bpy.context.scene.collection.objects.link(root)
        self.assets.append({"name": name, "kind": kind, "tags": list(tags or []), "notes": notes,
                            "root": root, "parts": [], "attachments": {}})
        return root

    def add(self, root, obj, role, rgb=None, collide=True, collision="Hull", cast_shadow=True,
            tags=None, uv=True, studs_per_tile=8.0, smooth_angle=None):
        """Finalise a mesh as a part of the asset: bake transforms, UVs, shading, material, parent.
        collision: "Box" | "Hull" | "Default" | "PreciseConvexDecomposition" (Roblox CollisionFidelity).
        smooth_angle: None = flat shading; a number = smooth with sharp edges above that angle."""
        entry = self._entry(root)
        apply_modifiers(obj)
        bake_transform(obj)
        clean(obj)
        count = sum(1 for p in entry["parts"] if p["role"] == role)
        part_name = "%s_%s" % (root.name, role) + ("" if count == 0 else "_%d" % (count + 1))
        obj.name = part_name
        obj.data.name = part_name
        if uv:
            box_uv(obj, studs_per_tile)
        if smooth_angle is None:
            flat(obj)
        else:
            smooth(obj, smooth_angle)
        mat = material(role, rgb)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        obj.parent = root
        tris = tri_count(obj)
        if tris > TRIANGLE_LIMIT:
            raise ValueError("%s has %d triangles (> %d Roblox limit)" % (part_name, tris, TRIANGLE_LIMIT))
        if tris == 0:
            self.warnings.append(part_name + " has no faces")
        lo, hi = world_bounds([obj])
        dims = hi - lo
        if min(dims.x, dims.y, dims.z) < 0.02:
            self.warnings.append("%s is nearly flat (%.3f) - give it some thickness" % (part_name, min(dims)))
        info = ROLES[role]
        entry["parts"].append({
            "name": part_name, "role": role, "robloxMaterial": info["roblox"],
            "rgb": list(rgb or info["rgb"]), "collide": bool(collide), "collision": collision,
            "castShadow": bool(cast_shadow), "tags": list(tags or []), "tris": tris,
        })
        return obj

    def attach(self, root, name, position, look=(0, 0, 1), up=(0, 1, 0)):
        """Record an attachment point (Blender coordinates relative to the asset origin).
        look/up are Blender direction vectors; stored converted to Roblox space."""
        entry = self._entry(root)
        entry["attachments"][name] = {
            "position": to_roblox(Vector(position)),
            "look": to_roblox(Vector(look).normalized()),
            "up": to_roblox(Vector(up).normalized()),
        }

    def finish(self, root):
        entry = self._entry(root)
        meshes = [c for c in root.children_recursive if c.type == "MESH"]
        if not meshes:
            raise ValueError(root.name + " has no meshes")
        lo, hi = world_bounds(meshes)
        entry["boundsMin"] = to_roblox(lo)
        entry["boundsMax"] = to_roblox(hi)
        size = hi - lo
        entry["size"] = [round(size.x, 3), round(size.z, 3), round(size.y, 3)]
        entry["tris"] = sum(p["tris"] for p in entry["parts"])
        if lo.z < -0.05:
            self.warnings.append("%s dips %.2f studs below z = 0 (base should rest on 0)" % (root.name, -lo.z))
        return entry

    # ---------------- previews ----------------
    def _setup_preview_scene(self):
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_WORKBENCH"
        shading = scene.display.shading
        shading.light = "STUDIO"
        shading.color_type = "MATERIAL"
        shading.show_cavity = True
        shading.cavity_type = "BOTH"
        shading.show_shadows = True
        shading.shadow_intensity = 0.45
        try:
            shading.show_specular_highlight = True
        except AttributeError:
            pass
        world = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
        world.color = (0.62, 0.7, 0.76)
        scene.world = world
        scene.render.resolution_x = 640
        scene.render.resolution_y = 480
        scene.render.film_transparent = False
        ground = bpy.data.objects.get("_PreviewGround")
        if ground is None:
            ground = cube("_PreviewGround", size=(400, 400, 0.1), loc=(0, 0, -0.05))
            ground.data.materials.append(material("Dirt", (176, 178, 168)))
        cam = bpy.data.objects.get("_PreviewCam")
        if cam is None:
            cam_data = bpy.data.cameras.new("_PreviewCam")
            cam_data.lens = 50
            cam_data.clip_end = 5000
            cam = bpy.data.objects.new("_PreviewCam", cam_data)
            scene.collection.objects.link(cam)
        scene.camera = cam
        return scene, cam, ground

    def render_preview(self, roots, path, elevation_deg=25, azimuth_deg=35, margin=1.15):
        """Render the given asset roots (others hidden) from a camera orbiting their bounds.
        azimuth 0 = looking at the front (camera on +Y)."""
        scene, cam, ground = self._setup_preview_scene()
        visible = set()
        for r in roots:
            visible.add(r)
            visible.update(r.children_recursive)
        for obj in scene.objects:
            if obj in (cam, ground):
                continue
            obj.hide_render = obj not in visible
        meshes = [o for o in visible if o.type == "MESH"]
        lo, hi = world_bounds(meshes)
        center = (lo + hi) / 2
        radius = max((hi - lo).length / 2, 0.5)
        fov = cam.data.angle
        dist = radius / math.sin(fov / 2) * margin
        e = math.radians(elevation_deg)
        a = math.radians(azimuth_deg)
        direction = Vector((math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)))
        cam.location = center + direction * dist
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        ground.location = (center.x, center.y, -0.05 + min(lo.z, 0))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        for obj in scene.objects:
            obj.hide_render = False
        return path

    def previews(self, preview_dir):
        folder = os.path.join(preview_dir, self.category)
        os.makedirs(folder, exist_ok=True)
        paths = []
        for e in self.assets:
            root = e["root"]
            paths.append(self.render_preview([root], os.path.join(folder, e["name"] + "_front.png"), 20, 30))
            paths.append(self.render_preview([root], os.path.join(folder, e["name"] + "_back.png"), 35, 210))
        return paths

    # ---------------- export ----------------
    def export(self, out_dir, preview_dir=None, gap=6.0):
        """Render previews (each asset at the origin), then lay assets out in a row along X,
        export <Category>.glb and <Category>.manifest.json. Returns the manifest dict."""
        for e in self.assets:
            if "size" not in e:
                self.finish(e["root"])
        preview_paths = self.previews(preview_dir) if preview_dir else []
        # Row layout (Blender X), recorded as Roblox origins
        x = 0.0
        for e in self.assets:
            width = e["size"][0]
            min_x = e["boundsMin"][0]
            offset = x - min_x
            e["root"].location = (offset, 0, 0)
            e["origin"] = [round(offset, 4), 0.0, 0.0]
            x += width + gap
        bpy.context.view_layer.update()
        if preview_dir:
            overview = os.path.join(preview_dir, self.category, "_overview.png")
            self.render_preview([e["root"] for e in self.assets], overview, 30, 25, 1.05)
            preview_paths.append(overview)
        # Select only asset hierarchies and export
        for obj in bpy.context.scene.objects:
            obj.select_set(False)
        for e in self.assets:
            e["root"].select_set(True)
            for c in e["root"].children_recursive:
                c.select_set(True)
        glb = os.path.join(out_dir, self.category + ".glb")
        bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False, export_extras=False)
        manifest = {
            "category": self.category,
            "glb": os.path.basename(glb),
            "units": "1 Blender unit = 1 Roblox stud",
            "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
            "assets": [],
            "warnings": self.warnings,
        }
        for e in self.assets:
            manifest["assets"].append({k: v for k, v in e.items() if k != "root"})
        with open(os.path.join(out_dir, self.category + ".manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1)
        size_mb = os.path.getsize(glb) / (1024 * 1024)
        print("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (glb, size_mb, len(self.assets), len(self.warnings)))
        for w in self.warnings:
            print("WARNING " + w)
        for p in preview_paths:
            print("PREVIEW " + p)
        if size_mb > 19:
            print("WARNING GLB is over 19 MB - split the category (upload limit is 20 MB per file)")
        return manifest
