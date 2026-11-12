"""
style_c_review.py - review renders for the Variant C style test, built ONLY from what Roblox receives: the exported
StyleTest_C.glb, the manifest's SurfaceAppearance blocks and the upload PNGs (Cycles, Blender's Sky Texture).

Shots (all at eye level, 5 studs, next to a blocky 5.5-stud R15-style figure):
  lineup_<light>.png       the four assets in a row on forest-floor terrain with a pebble path
  vignette_<light>.png     a small clearing: path to the cabin porch, spruce, oak, boulder
  closeups_<light>.png     2 x 2 sheet: spruce base, oak limbs / perches, cabin porch + corner, boulder
  ground_textures.png      the two terrain tiles: 2 x 2 repeats top-down + an eye-level patch with the figure
Lights: midday (sun 62 deg) and late (late-afternoon sun 14 deg, warm).
"""
import json
import math
import os
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector

import tex_ground as tg

LIGHTS = {"midday": dict(elev=62.0, bearing=38.0, strength=0.075, exposure=-0.3),
          "late": dict(elev=11.0, bearing=72.0, strength=0.075, exposure=0.45)}
EXPORTS = None
SC = {}


def log(*a):
    print(*a, flush=True)


def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# =============================================================================================== render setup
def setup(samples, res):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    tg.enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = True
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.transparent_max_bounces = 16
    c.caustics_reflective = False
    c.caustics_refractive = False
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    world = bpy.data.worlds.new("SC_Sky")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = True
    sky.altitude = 300.0
    try:
        sky.aerosol_density = 1.6
        sky.air_density = 1.0
    except AttributeError:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    scene.world = world
    return scene


def set_light(scene, name):
    Lp = LIGHTS[name]
    sky = [n for n in scene.world.node_tree.nodes if n.type == "TEX_SKY"][0]
    bg = [n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND"][0]
    sky.sun_elevation = math.radians(Lp["elev"])
    sky.sun_rotation = math.radians(Lp["bearing"])
    bg.inputs["Strength"].default_value = Lp["strength"]
    scene.view_settings.exposure = Lp["exposure"]


def camera(scene, loc, target, lens=24.0, ortho=None):
    cam = bpy.data.objects.get("SC_Cam")
    if cam is None:
        cam = bpy.data.objects.new("SC_Cam", bpy.data.cameras.new("SC_Cam"))
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        cam.data.ortho_scale = ortho
    cam.data.lens = lens
    cam.data.sensor_width = 36
    cam.data.clip_start = 0.05
    cam.data.clip_end = 3000
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def render(scene, path, res=None):
    if res:
        scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log("RENDER %s (%.0fs)" % (path, time.time() - t))
    return path


# =============================================================================================== materials
_IM = {}
_MATS = {}


def img(rel, cs):
    path = os.path.join(EXPORTS, *rel.split("/")) if not os.path.isabs(rel) else rel
    key = (path, cs)
    if key not in _IM:
        im = bpy.data.images.load(path, check_existing=False)
        im.colorspace_settings.name = cs
        _IM[key] = im
    return _IM[key]


def sa_material(p):
    sa = p["surfaceAppearance"]
    tr = float(p.get("transparency") or 0.0)
    key = (sa["colorMap"], sa["normalMap"], sa["roughnessMap"], tuple(sa.get("color") or (255, 255, 255)), tr)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("SA_%d" % len(_MATS))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    c = nt.nodes.new("ShaderNodeTexImage")
    c.image = img(sa["colorMap"], "sRGB")
    tint = [lin(v) for v in (sa.get("color") or (255, 255, 255))]
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(c.outputs["Color"], mul.inputs[6])
    mul.inputs[7].default_value = (*tint, 1.0)
    nt.links.new(mul.outputs[2], b.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = img(sa["normalMap"], "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    r = nt.nodes.new("ShaderNodeTexImage")
    r.image = img(sa["roughnessMap"], "Non-Color")
    nt.links.new(r.outputs["Color"], b.inputs["Roughness"])
    b.inputs["Metallic"].default_value = 0.0
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    front = nt.nodes.new("ShaderNodeMath")
    front.operation = "SUBTRACT"
    front.inputs[0].default_value = 1.0
    nt.links.new(geo.outputs["Backfacing"], front.inputs[1])
    alpha = front.outputs[0]
    if tr > 0:
        mm = nt.nodes.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        nt.links.new(alpha, mm.inputs[0])
        mm.inputs[1].default_value = 1.0 - tr
        alpha = mm.outputs[0]
        b.inputs["Roughness"].default_value = 0.1
    nt.links.new(alpha, b.inputs["Alpha"])
    _MATS[key] = m
    return m


# =============================================================================================== library
ROOTS = {}
MAN = {}
LIBC = None
SCN = None


def import_glb(out_dir, glb_name):
    global LIBC
    with open(os.path.join(out_dir, glb_name + ".manifest.json"), encoding="utf-8") as f:
        man = json.load(f)
    LIBC = bpy.data.collections.new("SC_Library")
    bpy.context.scene.collection.children.link(LIBC)
    parts = {p["name"]: p for a in man["assets"] for p in a["parts"]}
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(out_dir, man["glb"]))
    new = [o for o in bpy.data.objects if o not in before]
    by = {o.name: o for o in new}
    for a in man["assets"]:
        root = by.get(a["name"])
        if root is None:
            log("REVIEW missing root " + a["name"])
            continue
        root.location.x -= a["origin"][0]
        ROOTS[a["name"]] = root
        MAN[a["name"]] = a
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        LIBC.objects.link(o)
        if o.type != "MESH":
            continue
        p = parts.get(o.name)
        if p is None:
            continue
        o.data.materials.clear()
        o.data.materials.append(sa_material(p))
        o.visible_shadow = bool(p.get("castShadow", True))
    LIBC.hide_render = True
    bpy.context.view_layer.update()
    return man


def new_scene_collection():
    global SCN
    if SCN is not None:
        for o in list(SCN.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(SCN)
    SCN = bpy.data.collections.new("SC_Scene")
    bpy.context.scene.collection.children.link(SCN)


def place(name, loc, rot=0.0):
    root = ROOTS[name]
    inst = bpy.data.objects.new(name + "_i", None)
    SCN.objects.link(inst)
    for c in root.children_recursive:
        if c.type != "MESH":
            continue
        d = c.copy()
        SCN.objects.link(d)
        d.parent = inst
        d.matrix_parent_inverse = Matrix.Identity(4)
        d.matrix_basis = root.matrix_world.inverted() @ c.matrix_world
        d.hide_render = False
    inst.location = loc
    inst.rotation_euler = (0, 0, rot)
    return inst


def figure(loc, yaw=0.0):
    """Blocky R15-style avatar, 5.5 studs: legs 2.0, torso 2.0, head 1.2 (rounded boxes)."""
    import bmesh
    mats = {"skin": (204, 160, 128), "shirt": (64, 86, 118), "pants": (58, 58, 64)}
    parts = [((-0.5, 0, 1.0), (0.94, 0.96, 2.0), "pants"), ((0.5, 0, 1.0), (0.94, 0.96, 2.0), "pants"),
             ((0, 0, 3.0), (2.0, 1.0, 2.0), "shirt"), ((-1.5, 0, 3.0), (0.94, 0.96, 2.0), "skin"),
             ((1.5, 0, 3.0), (0.94, 0.96, 2.0), "skin"), ((0, 0, 4.86), (1.15, 1.15, 1.25), "skin")]
    me = bpy.data.meshes.new("SC_Figure")
    order = ["skin", "shirt", "pants"]
    bm = bmesh.new()
    for (c, s, mname) in parts:
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=Vector(s), verts=tmp.verts)
        bmesh.ops.bevel(tmp, geom=tmp.edges[:], offset=0.12, segments=3, affect="EDGES", profile=0.5)
        bmesh.ops.translate(tmp, vec=Vector(c), verts=tmp.verts)
        for f in tmp.faces:
            f.material_index = order.index(mname)
        tme = bpy.data.meshes.new("tmp")
        tmp.to_mesh(tme)
        tmp.free()
        bm.from_mesh(tme)
        bpy.data.meshes.remove(tme)
    bm.to_mesh(me)
    bm.free()
    for k in order:
        m = bpy.data.materials.get("SC_Fig_" + k)
        if m is None:
            m = bpy.data.materials.new("SC_Fig_" + k)
            m.use_nodes = True
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = (*[lin(v) for v in mats[k]], 1)
            b.inputs["Roughness"].default_value = 0.6
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("SC_Figure", me)
    SCN.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (0, 0, yaw)
    return ob


# =============================================================================================== ground
def terrain_files(man):
    out = {}
    for t in man.get("terrainMaterials", []):
        out[t["key"]] = t
    return out


def ground_material(terr):
    m = bpy.data.materials.get("SC_Ground")
    if m:
        return m
    m = bpy.data.materials.new("SC_Ground")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")

    def layer(key, uvname):
        t = terr.get(key)
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.uv_map = uvname
        if t is None:
            return None
        ci = nt.nodes.new("ShaderNodeTexImage")
        ci.image = img(t["colorMap"], "sRGB")
        ni = nt.nodes.new("ShaderNodeTexImage")
        ni.image = img(t["normalMap"], "Non-Color")
        ri = nt.nodes.new("ShaderNodeTexImage")
        ri.image = img(t["roughnessMap"], "Non-Color")
        for n in (ci, ni, ri):
            nt.links.new(uv.outputs["UV"], n.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.space = "TANGENT"
        nm.uv_map = uvname
        nt.links.new(ni.outputs["Color"], nm.inputs["Color"])
        return ci.outputs["Color"], nm.outputs["Normal"], ri.outputs["Color"]
    floor = layer("ForestFloor", "UVfloor")
    path = layer("PebblePath", "UVpath")
    # grass stand-in (Roblox terrain grass is kept as is; this is only context)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    gn = nt.nodes.new("ShaderNodeTexNoise")
    gn.inputs["Scale"].default_value = 0.08
    gn.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], gn.inputs["Vector"])
    gr = nt.nodes.new("ShaderNodeValToRGB")
    gr.color_ramp.elements[0].color = (lin(70), lin(98), lin(40), 1)
    gr.color_ramp.elements[1].color = (lin(104), lin(128), lin(56), 1)
    nt.links.new(gn.outputs["Fac"], gr.inputs[0])
    gb = nt.nodes.new("ShaderNodeBump")
    gb.inputs["Strength"].default_value = 0.25
    gv = nt.nodes.new("ShaderNodeTexVoronoi")
    gv.inputs["Scale"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], gv.inputs["Vector"])
    nt.links.new(gv.outputs["Distance"], gb.inputs["Height"])
    # masks: vertex attributes 'path' and 'grass', broken up by noise
    def mask(attr, lo, hi, scale):
        a = nt.nodes.new("ShaderNodeAttribute")
        a.attribute_name = attr
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = 4.0
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        add = nt.nodes.new("ShaderNodeMath")
        add.operation = "MULTIPLY_ADD"
        nt.links.new(nz.outputs["Fac"], add.inputs[0])
        add.inputs[1].default_value = 0.35
        nt.links.new(a.outputs["Fac"], add.inputs[2])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        mr.inputs["From Min"].default_value = lo
        mr.inputs["From Max"].default_value = hi
        nt.links.new(add.outputs[0], mr.inputs["Value"])
        return mr.outputs["Result"]
    mp = mask("path", 0.55, 0.68, 0.6)
    mg = mask("grass", 0.6, 0.72, 0.35)

    def mixc(a, b2, f):
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        nt.links.new(f, mx.inputs["Factor"])
        nt.links.new(a, mx.inputs[6]) if not isinstance(a, tuple) else None
        if isinstance(a, tuple):
            mx.inputs[6].default_value = a
        nt.links.new(b2, mx.inputs[7])
        return mx.outputs[2]

    def mixv(a, b2, f):
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "VECTOR"
        nt.links.new(f, mx.inputs["Factor"])
        nt.links.new(a, mx.inputs[4])
        nt.links.new(b2, mx.inputs[5])
        return mx.outputs[1]

    def mixf(a, b2, f):
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "FLOAT"
        nt.links.new(f, mx.inputs["Factor"])
        if isinstance(a, float):
            mx.inputs[2].default_value = a
        else:
            nt.links.new(a, mx.inputs[2])
        nt.links.new(b2, mx.inputs[3])
        return mx.outputs[0]
    if floor is None:
        col, nrm, rough = gr.outputs[0], gb.outputs["Normal"], None
    else:
        col, nrm, rough = floor
        col = mixc(col, gr.outputs[0], mg)
        nrm = mixv(nrm, gb.outputs["Normal"], mg)
    if path is not None:
        col = mixc(col, path[0], mp)
        nrm = mixv(nrm, path[1], mp)
        rough = mixf(rough if rough is not None else 0.9, path[2], mp)
    nt.links.new(col, b.inputs["Base Color"])
    nt.links.new(nrm, b.inputs["Normal"])
    if rough is not None:
        nt.links.new(rough, b.inputs["Roughness"])
    else:
        b.inputs["Roughness"].default_value = 0.92
    return m


def ground(terr, size, n, height_fn, path_fn, grass_fn, center=(0, 0), tiles=None):
    xs = np.linspace(-size / 2, size / 2, n) + center[0]
    ys = np.linspace(-size / 2, size / 2, n) + center[1]
    X, Y = np.meshgrid(xs, ys)
    Z = height_fn(X, Y)
    V = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    i = np.arange(n - 1)
    a = (i[None, :] + i[:, None] * n).ravel()
    F = np.stack([a, a + 1, a + n + 1, a + n], 1)
    me = bpy.data.meshes.new("SC_Ground")
    me.vertices.add(len(V))
    me.vertices.foreach_set("co", V.astype(np.float32).ravel())
    me.loops.add(F.size)
    me.loops.foreach_set("vertex_index", F.astype(np.int32).ravel())
    me.polygons.add(len(F))
    me.polygons.foreach_set("loop_start", (np.arange(len(F)) * 4).astype(np.int32))
    me.update(calc_edges=True)
    li = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", li)
    tf = (tiles or {}).get("ForestFloor", 12.0)
    tp = (tiles or {}).get("PebblePath", 10.0)
    for name, t in (("UVfloor", tf), ("UVpath", tp)):
        uv = me.uv_layers.new(name=name)
        uv.data.foreach_set("uv", (V[li, :2] / t).astype(np.float32).ravel())
    for name, fn in (("path", path_fn), ("grass", grass_fn)):
        at = me.attributes.new(name, "FLOAT", "POINT")
        at.data.foreach_set("value", np.clip(fn(V[:, 0], V[:, 1]), 0, 1).astype(np.float32))
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    ob = bpy.data.objects.new("SC_Ground", me)
    SCN.objects.link(ob)
    me.materials.append(ground_material(terr))
    return ob


def seg_dist(X, Y, pts):
    d = np.full(np.shape(X), 1e9)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((X - x0) * dx + (Y - y0) * dy) / (dx * dx + dy * dy), 0, 1)
        d = np.minimum(d, np.hypot(X - (x0 + t * dx), Y - (y0 + t * dy)))
    return d


# =============================================================================================== scenes
def build_lineup(terr, tiles):
    new_scene_collection()
    path_pts = [(-80, 12.0), (80, 12.0)]

    def h(X, Y):
        return 0.15 * np.sin(X * 0.05) * np.cos(Y * 0.07)

    def pth(X, Y):
        return np.clip(1.0 - (seg_dist(X, Y, path_pts) - 2.6) / 2.0, 0, 1)

    def grs(X, Y):
        return np.clip((Y - 36.0) / 6.0, 0, 1)
    ground(terr, 220, 441, h, pth, grs, center=(-2, 10), tiles=tiles)
    # the camera looks along -Y, so screen-left is +X: spruce, oak, cabin, boulder read left to right
    spots = {}
    if "StyleC_Spruce" in ROOTS:
        place("StyleC_Spruce", (40, 0, 0), 0.4)
        figure((30.5, 5.0, 0), 0.5)
        spots["spruce"] = (40, 0)
    if "StyleC_Oak" in ROOTS:
        place("StyleC_Oak", (10, -1, 0), 0.0)
        figure((5.5, 2.5, 0), -0.3)
        spots["oak"] = (10, -1)
    if "StyleC_Cabin" in ROOTS:
        place("StyleC_Cabin", (-21, -4, 0), 0.0)
        figure((-26.0, 8.5, 0), 0.2)
        spots["cabin"] = (-21, -4)
    if "StyleC_Boulder" in ROOTS:
        place("StyleC_Boulder", (-44, 5, -0.2), 0.6)
        figure((-48.8, 7.0, 0), -0.6)
        spots["boulder"] = (-44, 5)
    return spots


def build_vignette(terr, tiles):
    new_scene_collection()
    path_pts = [(-9, 60), (-7, 38), (-3, 24), (0.5, 14), (1.0, 9.0)]

    def h(X, Y):
        return 0.25 * np.sin(X * 0.06 + 1.0) * np.cos(Y * 0.05) + 0.12 * np.sin(X * 0.17) * np.sin(Y * 0.13)

    def pth(X, Y):
        return np.clip(1.0 - (seg_dist(X, Y, path_pts) - 2.2) / 1.8, 0, 1)

    def grs(X, Y):
        return np.clip((np.hypot(X - 30, Y - 30) < 18).astype(float) * 1.0, 0, 1) * np.clip((Y - 12) / 6, 0, 1)
    ground(terr, 200, 401, h, pth, grs, center=(0, 15), tiles=tiles)
    if "StyleC_Cabin" in ROOTS:
        place("StyleC_Cabin", (0, -4, 0), 0.0)
    if "StyleC_Spruce" in ROOTS:
        place("StyleC_Spruce", (-19, -9, 0), 1.1)
        place("StyleC_Spruce", (-34, 6, 0), 2.3)
        place("StyleC_Spruce", (16, -24, 0), 0.2)
    if "StyleC_Oak" in ROOTS:
        place("StyleC_Oak", (22, 8, 0), 2.0)
    if "StyleC_Boulder" in ROOTS:
        place("StyleC_Boulder", (-8.5, 21, -0.3), 0.9)
    figure((-1.6, 23.0, h(-1.6, 23.0)), 2.9)


def compose(paths, out, cols=2, scale=1.0):
    ims = [tg.load_image_np(p, "Non-Color")[..., :3] for p in paths]
    h, w = ims[0].shape[:2]
    rows = (len(ims) + cols - 1) // cols
    pad = 6
    sheet = np.ones((rows * h + (rows + 1) * pad, cols * w + (cols + 1) * pad, 3)) * 0.12
    for i, im in enumerate(ims):
        r, c = i // cols, i % cols
        y0 = sheet.shape[0] - (pad + (r + 1) * h + r * pad)     # row 0 = bottom in our arrays
        x0 = pad + c * (w + pad)
        sheet[y0:y0 + h, x0:x0 + w] = im[:h, :w]
    tg.write_png(out, np.clip(sheet, 0, 1), quantize=False)
    for p in paths:
        try:
            os.remove(p)
        except OSError:
            pass
    log("SHEET " + out)
    return out


def ground_sheet(scene, terr, tiles, prev):
    """Each terrain tile: 2 x 2 repeats seen straight down + an eye-level patch with the figure (midday)."""
    paths = []
    for key in ("PebblePath", "ForestFloor"):
        if key not in terr:
            continue
        new_scene_collection()
        t = tiles.get(key, 10.0)
        one = {key: terr[key]}
        bpy.data.materials.remove(bpy.data.materials["SC_Ground"]) if "SC_Ground" in bpy.data.materials else None
        flag = (lambda X, Y: np.ones_like(X)) if key == "PebblePath" else (lambda X, Y: np.zeros_like(X))
        ground(terr, 140, 281, lambda X, Y: np.zeros_like(X), flag, lambda X, Y: np.zeros_like(X),
               center=(0, 0), tiles=tiles)
        set_light(scene, "midday")
        camera(scene, (t, t, 40), (t, t, 0), ortho=2 * t)
        paths.append(render(scene, os.path.join(prev, "_tmp_%s_top.png" % key), (900, 900)))
        figure((0.0, 6.0, 0.0), 0.4)
        camera(scene, (2.0, 17.0, 5.0), (0.0, 0.0, 0.6), lens=24)
        paths.append(render(scene, os.path.join(prev, "_tmp_%s_eye.png" % key), (900, 900)))
        bpy.data.materials.remove(bpy.data.materials["SC_Ground"])
    if paths:
        compose(paths, os.path.join(prev, "ground_textures.png"), cols=2)


def run(out_dir, prev, glb_name, opts):
    global EXPORTS
    EXPORTS = os.path.normpath(os.path.join(out_dir, "..", ".."))
    samples = int(opts.get("samples", "96"))
    res = tuple(int(v) for v in opts.get("res", "1600x900").split("x"))
    shots = opts.get("shots", "lineup,closeups,vignette,ground").split(",")
    lights = opts.get("light", "midday,late").split(",")
    scene = setup(samples, res)
    man = import_glb(out_dir, glb_name)
    terr = terrain_files(man)
    tiles = {k: v.get("studsPerTile", 10.0) for k, v in terr.items()}
    os.makedirs(prev, exist_ok=True)
    if "lineup" in shots or "closeups" in shots:
        spots = build_lineup(terr, tiles)
        for lt in lights:
            set_light(scene, lt)
            if "lineup" in shots:
                camera(scene, (-2, 80, 5.0), (-2, 0, 15.5), lens=24)
                render(scene, os.path.join(prev, "lineup_%s.png" % lt), res)
            if "closeups" in shots:
                tiles_p = []
                cams = []
                if "spruce" in spots:
                    x, y = spots["spruce"]
                    cams.append(((x + 6.0, y + 19.0, 4.6), (x - 3.0, y, 10.5), 22))
                if "oak" in spots:
                    x, y = spots["oak"]
                    cams.append(((x + 9.0, y + 17.0, 4.0), (x - 1.5, y, 11.5), 18))
                if "cabin" in spots:
                    x, y = spots["cabin"]
                    cams.append(((x + 12.0, y + 24.0, 5.0), (x - 1.0, y + 5.0, 5.5), 22))
                if "boulder" in spots:
                    x, y = spots["boulder"]
                    cams.append(((x + 4.5, y + 10.0, 4.2), (x - 1.2, y, 2.0), 24))
                for i, (loc, tgt, lens) in enumerate(cams):
                    camera(scene, loc, tgt, lens=lens)
                    tiles_p.append(render(scene, os.path.join(prev, "_tmp_close_%d.png" % i), (960, 540)))
                compose(tiles_p, os.path.join(prev, "closeups_%s.png" % lt), cols=2)
    if "vignette" in shots:
        build_vignette(terr, tiles)
        for lt in lights:
            set_light(scene, lt)
            camera(scene, (-9.0, 46.0, 5.2), (1.0, 0.0, 9.5), lens=22)
            render(scene, os.path.join(prev, "vignette_%s.png" % lt), res)
    if "ground" in shots and terr:
        ground_sheet(scene, terr, tiles, prev)
