"""
ad_review.py - art-direction review renders across ALL realistic sets, built only from what Roblox will receive:
the exported GLBs + the manifests' SurfaceAppearance blocks + the PNGs in textures/<Set>/ (Blender 5.3, Cycles).

    blender --background --factory-startup --python art/blender/ad_review.py -- <BlenderExports> <previews_root>
            [scenes=forest,meadow,marsh,spire,camp,gorge,fp,lineup,assets] [light=ct14,ct18] [samples=96]
            [res=1600x900]

Materials are rebuilt per part exactly as an integrator builds the SurfaceAppearance: ColorMap (sRGB) x Color tint,
NormalMap (OpenGL, tangent space), RoughnessMap, MetalnessMap; AlphaMode Transparency with MeshPart.Transparency 0
renders as a 0.5 alpha cut-out, with Transparency > 0 as a blend; MeshParts are single-sided (back faces culled);
Neon parts glow in their rgb; invisible colliders are hidden. Images larger than 1024 px would be shrunk to 1024 the
way Roblox does (none are left). Lighting: Blender's built-in Sky Texture (multiple scattering) with its sun -
ct14 = high afternoon sun (Roblox ClockTime 14, elevation 42 deg), ct18 = warm low sun (ClockTime 18, elevation 5 deg).

Writes <previews_root>/_ArtDirection/<scene>_<light>.png, _lineup_all.png and (scene 'assets': every asset at eye
level next to the figure, both lights) _sheet_<Set>_<light>.png + tiles/.
"""
import json
import math
import os
import random
import sys
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.path.expanduser("~"), "OneDrive", "Documents",
                                                          "LastStanding", "BlenderExports")
PREV = os.path.join(os.path.abspath(ARGS[1]) if len(ARGS) > 1 else os.path.join(os.path.dirname(__file__), "..",
                                                                                 "previews"), "_ArtDirection")
OPTS = dict(a.split("=", 1) for a in ARGS[2:] if "=" in a)
SCENES = OPTS.get("scenes", "forest,meadow,marsh,spire,camp,gorge,fp,lineup").split(",")
LIGHTS = OPTS.get("light", "ct14,ct18").split(",")
SAMPLES = int(OPTS.get("samples", "96"))
RES = tuple(int(v) for v in OPTS.get("res", "1600x900").split("x"))
SETS = ["TreesReal", "GroundReal", "LandmarksReal", "BuildingsReal", "PropsReal", "ItemsReal"]
EYE = 5.0
os.makedirs(PREV, exist_ok=True)


def log(*a):
    print(*a, flush=True)


def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# =============================================================================================== scene + light
LIGHT = {"ct14": dict(elev=42.0, strength=0.075, exposure=0.0),
         "ct18": dict(elev=5.0, strength=0.075, exposure=1.35)}


def setup_render():
    scene = bpy.context.scene
    for o in list(bpy.data.objects):          # factory startup: default cube, camera and point light
        bpy.data.objects.remove(o, do_unlink=True)
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = d.type == kind
                    scene.cycles.device = "GPU"
                    break
            except Exception:
                continue
    except Exception:
        pass
    c = scene.cycles
    c.samples = SAMPLES
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = True
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.transmission_bounces = 4
    c.transparent_max_bounces = 24
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.filter_width = 1.2
    r = scene.render
    r.resolution_x, r.resolution_y = RES
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    world = bpy.data.worlds.new("AD_Sky")
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


def set_light(scene, preset, bearing):
    """bearing: compass direction the sun shines FROM, degrees from +Y toward +X (Sky Texture convention)."""
    L = LIGHT[preset]
    sky = [n for n in scene.world.node_tree.nodes if n.type == "TEX_SKY"][0]
    bg = [n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND"][0]
    sky.sun_elevation = math.radians(L["elev"])
    sky.sun_rotation = math.radians(bearing)
    bg.inputs["Strength"].default_value = L["strength"]
    scene.view_settings.exposure = L["exposure"]


def camera(scene, loc, target, lens=24.0):
    cam = bpy.data.objects.get("AD_Cam")
    if cam is None:
        cam = bpy.data.objects.new("AD_Cam", bpy.data.cameras.new("AD_Cam"))
        scene.collection.objects.link(cam)
    cam.data.type = "PERSP"
    cam.data.lens = lens
    cam.data.sensor_width = 36
    cam.data.clip_start = 0.05
    cam.data.clip_end = 3000
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def render(scene, name):
    path = os.path.join(PREV, name + ".png")
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log("RENDER %s (%.0fs)" % (path, time.time() - t))
    return path


# =============================================================================================== materials
_MATS = {}
_IMGS = {}


def _img(rel, cs):
    path = os.path.join(OUT, *rel.split("/"))
    key = (path, cs)
    if key in _IMGS:
        return _IMGS[key]
    im = bpy.data.images.load(path, check_existing=False)
    im.colorspace_settings.name = cs
    if max(im.size) > 1024:                    # Roblox shrinks anything larger to 1024
        f = 1024.0 / max(im.size)
        im.scale(int(im.size[0] * f), int(im.size[1] * f))
    _IMGS[key] = im
    return im


def sa_material(p):
    """Principled material equivalent to the part's SurfaceAppearance (+ MeshPart.Transparency, single-sided)."""
    sa = p.get("surfaceAppearance")
    tr = float(p.get("transparency") or 0.0)
    if p.get("neon"):
        key = ("neon", tuple(p.get("rgb", (255, 128, 48))))
    else:
        key = (sa["colorMap"], sa["normalMap"], sa["roughnessMap"], sa.get("metalnessMap"), sa["alphaMode"],
               tuple(sa.get("color") or (255, 255, 255)), round(tr, 3))
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("AD_%d" % len(_MATS))
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if p.get("neon"):
        lin = [srgb_to_lin(c) for c in p.get("rgb", (255, 128, 48))]
        bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 4.0
        _MATS[key] = m
        return m

    def tex(rel, cs):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = _img(rel, cs)
        n.interpolation = "Linear"
        return n
    c = tex(sa["colorMap"], "sRGB")
    tint = [srgb_to_lin(v) for v in (sa.get("color") or (255, 255, 255))]
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(c.outputs["Color"], mul.inputs[6])
    mul.inputs[7].default_value = (*tint, 1.0)
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    n = tex(sa["normalMap"], "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    r = tex(sa["roughnessMap"], "Non-Color")
    nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    if sa.get("metalnessMap"):
        mt = tex(sa["metalnessMap"], "Non-Color")
        nt.links.new(mt.outputs["Color"], bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = 0.0
    # single-sided like a MeshPart (Cycles would otherwise shade back faces)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    front = nt.nodes.new("ShaderNodeMath")
    front.operation = "SUBTRACT"
    front.inputs[0].default_value = 1.0
    nt.links.new(geo.outputs["Backfacing"], front.inputs[1])
    alpha = front.outputs[0]
    if sa["alphaMode"] == "Transparency":
        if tr <= 0.0:
            gt = nt.nodes.new("ShaderNodeMath")
            gt.operation = "GREATER_THAN"
            gt.inputs[1].default_value = 0.5
            nt.links.new(c.outputs["Alpha"], gt.inputs[0])
            src = gt.outputs[0]
        else:
            sc = nt.nodes.new("ShaderNodeMath")
            sc.operation = "MULTIPLY"
            nt.links.new(c.outputs["Alpha"], sc.inputs[0])
            sc.inputs[1].default_value = 1.0 - tr
            src = sc.outputs[0]
        mm = nt.nodes.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        nt.links.new(src, mm.inputs[0])
        nt.links.new(alpha, mm.inputs[1])
        alpha = mm.outputs[0]
    nt.links.new(alpha, bsdf.inputs["Alpha"])
    _MATS[key] = m
    return m


# =============================================================================================== import
ROOTS = {}          # asset -> root empty (re-centred on its origin, hidden; scenes use instances)
MANIFEST = {}       # asset -> manifest asset entry
LIB = None


def import_all():
    global LIB
    LIB = bpy.data.collections.new("AD_Library")
    bpy.context.scene.collection.children.link(LIB)
    for s in SETS:
        mp = os.path.join(OUT, s + ".manifest.json")
        if not os.path.exists(mp):
            log("SKIP " + s)
            continue
        with open(mp, encoding="utf-8") as f:
            man = json.load(f)
        files = [g["file"] for g in man.get("glbs", [])] or [s + ".glb"]
        parts = {p["name"]: p for a in man["assets"] for p in a["parts"]}
        for fn in files:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, fn))
            new = [o for o in bpy.data.objects if o not in before]
            by = {o.name: o for o in new}
            for a in man["assets"]:
                if a.get("glb", fn) != fn or a["name"] not in by:
                    continue
                root = by[a["name"]]
                root.location.x -= a["origin"][0]
                ROOTS[a["name"]] = root
                MANIFEST[a["name"]] = a
            for o in new:
                for c in list(o.users_collection):
                    c.objects.unlink(o)
                LIB.objects.link(o)
                if o.type != "MESH":
                    continue
                p = parts.get(o.name)
                if p is None:
                    continue
                if p.get("role") == "Collider" or (not p.get("surfaceAppearance") and not p.get("neon")):
                    o.hide_render = True
                    continue
                o.data.materials.clear()
                o.data.materials.append(sa_material(p))
                o.visible_shadow = bool(p.get("castShadow", True))
        log("IMPORTED %s: %d assets" % (s, sum(1 for a in man["assets"] if a["name"] in ROOTS)))
    LIB.hide_render = True
    bpy.context.view_layer.update()


SCENE_COL = None


def clear_scene():
    global SCENE_COL
    if SCENE_COL is not None:
        for o in list(SCENE_COL.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(SCENE_COL)
    SCENE_COL = bpy.data.collections.new("AD_Scene")
    bpy.context.scene.collection.children.link(SCENE_COL)


def place(name, loc, rot=0.0, scale=1.0, tilt=(0.0, 0.0)):
    """Instance an asset (linked duplicates of its parts) with its pivot at loc, yaw rot (radians)."""
    root = ROOTS[name]
    inst = bpy.data.objects.new(name + "_i", None)
    SCENE_COL.objects.link(inst)
    for c in root.children_recursive:
        if c.type != "MESH" or c.hide_render:
            continue
        d = c.copy()
        SCENE_COL.objects.link(d)
        d.parent = inst
        d.matrix_parent_inverse = Matrix.Identity(4)
        d.matrix_basis = (root.matrix_world.inverted() @ c.matrix_world)
        d.hide_render = False
    inst.location = loc
    inst.rotation_euler = (tilt[0], tilt[1], rot)
    inst.scale = (scale, scale, scale)
    return inst


def attachment_world(asset, att, inst_loc=(0, 0, 0), rot=0.0):
    """Manifest attachment (Roblox space, relative to the pivot) -> Blender world position + look."""
    a = MANIFEST[asset]["attachments"][att]
    p = Vector((a["position"][0], -a["position"][2], a["position"][1]))
    lk = Vector((a["look"][0], -a["look"][2], a["look"][1]))
    R = Matrix.Rotation(rot, 3, "Z")
    return Vector(inst_loc) + R @ p, R @ lk


# =============================================================================================== ground
def ground_material(kind):
    m = bpy.data.materials.get("AD_Ground_" + kind)
    if m:
        return m
    m = bpy.data.materials.new("AD_Ground_" + kind)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")

    def noise(scale, detail, rough=0.6, w=0.0):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
        return n
    big = noise(0.045, 4.0, 0.55)
    mid = noise(0.6, 6.0, 0.6)
    fine = noise(9.0, 4.0, 0.7)
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "MULTIPLY_ADD"
    nt.links.new(mid.outputs["Fac"], add.inputs[0])
    add.inputs[1].default_value = 0.45
    nt.links.new(big.outputs["Fac"], add.inputs[2])
    add2 = nt.nodes.new("ShaderNodeMath")
    add2.operation = "MULTIPLY_ADD"
    nt.links.new(fine.outputs["Fac"], add2.inputs[0])
    add2.inputs[1].default_value = 0.2
    nt.links.new(add.outputs[0], add2.inputs[2])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    pal = {
        # Roblox terrain stand-ins (sRGB): forest floor = humus + needle litter + moss; meadow = grass sward with
        # dry patches; marsh = wet peat / mud; plaza surround = trampled grass
        "forest": [(0.30, (34, 28, 22)), (0.46, (52, 43, 33)), (0.58, (68, 56, 42)), (0.70, (50, 56, 32)),
                   (0.84, (60, 54, 40))],
        "meadow": [(0.30, (62, 72, 34)), (0.50, (84, 94, 44)), (0.66, (108, 108, 56)), (0.80, (92, 100, 48)),
                   (0.92, (120, 112, 70))],
        "marsh": [(0.30, (36, 32, 26)), (0.50, (52, 46, 34)), (0.64, (60, 60, 36)), (0.80, (46, 50, 30)),
                  (0.92, (70, 64, 46))],
    }[kind]
    cr = ramp.color_ramp
    cr.elements[0].position = pal[0][0]
    cr.elements[0].color = (*[srgb_to_lin(v) for v in pal[0][1]], 1.0)
    cr.elements[1].position = pal[-1][0]
    cr.elements[1].color = (*[srgb_to_lin(v) for v in pal[-1][1]], 1.0)
    for pos, col in pal[1:-1]:
        e = cr.elements.new(pos)
        e.color = (*[srgb_to_lin(v) for v in col], 1.0)
    nt.links.new(add2.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6 if kind == "marsh" else 0.9
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    bump.inputs["Distance"].default_value = 0.08
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def terrain(size, n, height_fn, kind, name="AD_Ground", center=(0, 0)):
    xs = np.linspace(-size / 2, size / 2, n) + center[0]
    ys = np.linspace(-size / 2, size / 2, n) + center[1]
    V = []
    for y in ys:
        for x in xs:
            V.append((x, y, height_fn(x, y)))
    F = []
    for j in range(n - 1):
        for i in range(n - 1):
            a = j * n + i
            F.append((a, a + 1, a + n + 1, a + n))
    me = bpy.data.meshes.new(name)
    me.from_pydata(V, [], F)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    SCENE_COL.objects.link(ob)
    me.materials.append(ground_material(kind))
    return ob


def water(z, size, center=(0, 0)):
    me = bpy.data.meshes.new("AD_Water")
    s = size / 2
    cx, cy = center
    me.from_pydata([(cx - s, cy - s, z), (cx + s, cy - s, z), (cx + s, cy + s, z), (cx - s, cy + s, z)], [],
                   [(0, 1, 2, 3)])
    ob = bpy.data.objects.new("AD_Water", me)
    SCENE_COL.objects.link(ob)
    m = bpy.data.materials.new("AD_WaterMat")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.012, 0.016, 0.01, 1)
    b.inputs["Roughness"].default_value = 0.04
    b.inputs["IOR"].default_value = 1.33
    me.materials.append(m)
    return ob


def figure(loc, yaw=0.0):
    """5.5-stud mannequin (feet at loc)."""
    import bmesh
    bm = bmesh.new()

    def capsule(p0, p1, r, seg=12):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        L = d.length
        mm = Matrix.Translation(p0) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        g = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=L)
        bmesh.ops.transform(bm, matrix=mm @ Matrix.Translation((0, 0, L / 2)), verts=g["verts"])
        for pp in (p0, p1):
            s = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=8, radius=r)
            bmesh.ops.translate(bm, vec=pp, verts=s["verts"])
    capsule((-0.38, 0, 0.25), (-0.33, 0, 2.55), 0.3)
    capsule((0.38, 0, 0.25), (0.33, 0, 2.55), 0.3)
    capsule((0, 0, 2.75), (0, 0, 4.15), 0.62)
    capsule((-0.95, 0, 4.25), (-1.1, 0.05, 2.45), 0.22)
    capsule((0.95, 0, 4.25), (1.1, 0.05, 2.45), 0.22)
    s = bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=12, radius=0.45)
    bmesh.ops.translate(bm, vec=Vector((0, 0, 5.05)), verts=s["verts"])
    me = bpy.data.meshes.new("AD_Figure")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    m = bpy.data.materials.get("AD_FigureMat") or bpy.data.materials.new("AD_FigureMat")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.05, 0.075, 0.13, 1)
    b.inputs["Roughness"].default_value = 0.7
    me.materials.append(m)
    ob = bpy.data.objects.new("AD_Figure", me)
    SCENE_COL.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (0, 0, yaw)
    return ob


# =============================================================================================== helpers
def hill(amp=6.0, fx=0.012, fy=0.017, slope=(0.0, 0.0), seed=0):
    rng = random.Random(seed)
    ph = [rng.uniform(0, 6.28) for _ in range(6)]

    def h(x, y):
        return (slope[0] * x + slope[1] * y + amp * (0.55 * math.sin(x * fx + ph[0]) * math.cos(y * fy + ph[1])
                + 0.3 * math.sin(x * fx * 2.3 + ph[2]) * math.sin(y * fy * 2.1 + ph[3])
                + 0.15 * math.sin(x * fx * 5.1 + ph[4] + y * fy * 4.3)))
    return h


def scatter(rng, n, xr, yr, avoid=(), min_d=0.0):
    pts = []
    tries = 0
    while len(pts) < n and tries < n * 60:
        tries += 1
        p = (rng.uniform(*xr), rng.uniform(*yr))
        if any(math.hypot(p[0] - a[0], p[1] - a[1]) < a[2] for a in avoid):
            continue
        if min_d and any(math.hypot(p[0] - q[0], p[1] - q[1]) < min_d for q in pts):
            continue
        pts.append(p)
    return pts


def P(h, name, x, y, rot=None, sink=0.0, rng=None, scale=1.0):
    r = rot if rot is not None else (rng.uniform(0, 6.283) if rng else 0.0)
    return place(name, (x, y, h(x, y) - sink), r, scale)


# =============================================================================================== scenes
def scene_forest(scene):
    """Sloped conifer forest: spruce, fir, pine, a birch, a young conifer, a snag; ferns, forest grass, moss,
    mushrooms, boulders, a fallen log and stumps; camera at eye level looking up the slope."""
    clear_scene()
    h = hill(amp=3.0, slope=(0.0, 0.16), seed=3)
    terrain(320, 140, h, "forest", center=(0, 60))
    rng = random.Random(11)
    trees = ["SpruceA", "SpruceB", "FirA", "SpruceA", "PineA", "FirA", "SpruceB", "SpruceA"]
    for i, (x, y) in enumerate(scatter(rng, 46, (-90, 90), (14, 170), avoid=[(0, 0, 10)], min_d=9.0)):
        P(h, trees[i % len(trees)] if (i % 11) != 5 else "BirchA", x, y, rng=rng)
    P(h, "SpruceA", -9, 24, rng=rng)
    P(h, "FirA", 10, 30, rng=rng)
    P(h, "BirchA", 22, 36, rng=rng)
    P(h, "ConiferYoung", -4, 15, rng=rng)
    P(h, "ConiferYoung", 13, 19, rng=rng)
    P(h, "SnagB", -20, 30, rng=rng)
    P(h, "FallenLogB", 9, 21, rot=0.5, sink=0.15)
    P(h, "StumpA", -8, 12, rng=rng)
    P(h, "StumpB", 12, 28, rng=rng)
    P(h, "BoulderC", -15, 19, rng=rng, sink=0.4)
    P(h, "BoulderB", 10, 11, rng=rng, sink=0.2)
    P(h, "BoulderA", -3.5, 9.5, rng=rng, sink=0.1)
    P(h, "MossPatch", 1.5, 12.5, rng=rng)
    P(h, "MossPatch", -11, 21, rng=rng)
    P(h, "MushroomsA", -6.5, 13.0, rng=rng)
    for (x, y) in scatter(rng, 30, (-28, 28), (6, 44), avoid=[(9, 21, 4), (-15, 19, 4)], min_d=2.8):
        P(h, rng.choice(["FernA", "FernB", "FernB"]), x, y, rng=rng)
    for (x, y) in scatter(rng, 50, (-26, 26), (5, 40), min_d=1.6):
        P(h, "GrassForest", x, y, rng=rng)
    figure((3.5, 19.0, h(3.5, 19.0)), yaw=0.3)
    cam = (-1.0, -4.0, h(-1.0, -4.0) + EYE)
    return cam, (1.0, 30.0, h(1.0, 30.0) + 6.5), 22.0, 200.0


def scene_meadow(scene):
    """Meadow edge: tall-grass field with flowers, bushes and boulders, forest edge (spruce, birch, oak) behind."""
    clear_scene()
    h = hill(amp=1.6, seed=5)
    terrain(320, 120, h, "meadow", center=(0, 60))
    rng = random.Random(21)
    for (x, y) in scatter(rng, 260, (-30, 30), (3, 46), min_d=1.7):
        P(h, rng.choice(["GrassTallA", "GrassTallB", "GrassTallA"]), x, y, rng=rng, sink=0.02)
    for (x, y) in scatter(rng, 40, (-26, 26), (3, 40), min_d=2.5):
        P(h, rng.choice(["FlowersA", "FlowersB"]), x, y, rng=rng)
    P(h, "BoulderC", 9, 16, rng=rng, sink=0.5)
    P(h, "BoulderB", -10, 22, rng=rng, sink=0.3)
    P(h, "BushA", -16, 34, rng=rng)
    P(h, "BerryBush", 15, 30, rng=rng)
    P(h, "BushB", 3, 40, rng=rng)
    P(h, "SaplingBroadleaf", -5, 44, rng=rng)
    edge = ["SpruceA", "BirchA", "SpruceB", "OakA", "FirA", "BirchB", "SpruceA", "PineA"]
    for i, (x, y) in enumerate(scatter(rng, 40, (-110, 110), (52, 150), min_d=10.0)):
        P(h, edge[i % len(edge)], x, y, rng=rng)
    P(h, "OakA", 28, 56, rng=rng)
    figure((-2.0, 14.0, h(-2.0, 14.0)), yaw=-0.2)
    return (0.0, -2.0, h(0.0, -2.0) + EYE), (2.0, 40.0, h(2.0, 40.0) + 5.0), 24.0, 215.0


def scene_marsh(scene):
    """Marsh: shallow water with reeds and sedge, a drowned snag and a mossy log, river stones on the bank."""
    clear_scene()
    base = hill(amp=0.9, seed=8)

    def h(x, y):
        bank = 0.9 * max(0.0, 1.0 - abs(y - 8.0) / 6.0)
        return base(x, y) - 0.6 + bank + (0.04 * y if y < 4 else 0.0)
    terrain(260, 140, h, "marsh", center=(0, 50))
    water(-0.15, 400, center=(0, 60))
    rng = random.Random(31)
    for (x, y) in scatter(rng, 70, (-30, 30), (10, 60), min_d=2.6):
        P(h, rng.choice(["ReedsA", "ReedsA", "GrassTallB"]), x, y, rng=rng, sink=0.1)
    for (x, y) in scatter(rng, 30, (-16, 16), (2, 12), min_d=2.0):
        P(h, rng.choice(["GrassTallB", "GrassForest", "ReedsA"]), x, y, rng=rng)
    P(h, "SnagA", 7, 28, rng=rng, sink=0.6)
    P(h, "FallenLogA", -4, 14, rot=0.25, sink=0.6)
    P(h, "RiverStones", 4, 5, rng=rng, sink=0.15)
    P(h, "MossPatch", -7, 6, rng=rng)
    for i, (x, y) in enumerate(scatter(rng, 30, (-110, 110), (70, 160), min_d=11.0)):
        P(h, ["SpruceA", "BirchA", "SpruceB", "FirA", "SnagB"][i % 5], x, y, rng=rng)
    figure((2.0, 9.0, h(2.0, 9.0)), yaw=0.4)
    return (0.0, -4.0, h(0.0, -4.0) + EYE), (2.0, 30.0, 2.5), 24.0, 230.0


def scene_spire(scene):
    """The arena centre seen by a contender standing on Plate_13 (due south): SpirePlatform, Spire, 24 Plinths,
    meadow and a forest ring beyond the plaza."""
    clear_scene()
    h = lambda x, y: 0.0 if math.hypot(x, y) < 64 else 0.012 * (math.hypot(x, y) - 64) ** 1.4  # noqa: E731
    terrain(700, 140, h, "meadow")
    place("SpirePlatform", (0, 0, 0))
    place("Spire", (0, 0, 0))
    for i in range(24):
        pos, look = attachment_world("SpirePlatform", "Plate_%d" % (i + 1))
        yaw = math.atan2(-look.x, look.y)
        place("Plinth", tuple(pos), yaw)
    rng = random.Random(41)
    for (x, y) in scatter(rng, 160, (-130, 130), (-130, 130), min_d=4.0):
        d = math.hypot(x, y)
        if 64 < d < 95:
            P(h, rng.choice(["GrassTallA", "GrassTallB", "FlowersA"]), x, y, rng=rng)
    for (x, y) in scatter(rng, 120, (-260, 260), (-260, 260), min_d=12.0):
        if 110 < math.hypot(x, y) < 260:
            P(h, rng.choice(["SpruceA", "SpruceB", "FirA", "PineA", "BirchA"]), x, y, rng=rng)
    pos, look = attachment_world("SpirePlatform", "Plate_13")
    stand = pos + Vector((0, 0, 1.5))
    figure(tuple(pos + Vector((-6.5, 3.0, 0.0))), yaw=0.0)
    cam = stand + Vector((0, 0, EYE)) - look * 1.0
    return tuple(cam), (0.0, 0.0, 20.0), 22.0, 160.0


def scene_camp(scene):
    """Forest clearing: the hunter's cabin with a campsite in front (tent, fire ring, log bench, woodpile, barrel,
    crates, lantern, bedroll), conifers around."""
    clear_scene()
    h = hill(amp=1.2, seed=12)
    terrain(320, 140, h, "forest", center=(0, 10))
    place("HunterCabin", (0, 0, h(0, 0)), 0.0)
    place("Tent", (-15, 15, h(-15, 15)), 0.5)
    place("Bedroll", (-12.5, 19.5, h(-12.5, 19.5)), 0.2)
    fire = (-4.0, 19.0)
    place("Campfire", (*fire, h(*fire)), 0.0)
    place("LogBench", (-4.0, 24.0, h(-4.0, 24.0)), 0.0)
    place("LogBench", (1.2, 19.5, h(1.2, 19.5)), 1.5708)
    place("Woodpile", (14.5, 2.0, h(14.5, 2.0)), 1.5708)
    place("Barrel", (8.5, 12.0, h(8.5, 12.0)), 0.3)
    place("CratePile", (-14.0, 4.0, h(-14.0, 4.0)), 0.4)
    place("Lantern", (-3.0, 24.0, h(-3.0, 24.0) + 1.66), 0.0)
    place("FenceSegment", (18.0, 12.0, h(18.0, 12.0)), 1.2)
    place("Sign", (12.0, 26.0, h(12.0, 26.0)), -0.4)
    rng = random.Random(51)
    for i, (x, y) in enumerate(scatter(rng, 70, (-120, 120), (-90, 120), avoid=[(0, 8, 42)], min_d=9.5)):
        P(h, ["SpruceA", "SpruceB", "FirA", "SpruceA", "PineA", "BirchA"][i % 6], x, y, rng=rng)
    for (x, y) in scatter(rng, 30, (-34, 34), (-6, 40), avoid=[(0, 2, 17), (-4, 19, 7), (-15, 15, 5)], min_d=3.0):
        P(h, rng.choice(["FernB", "FernA", "GrassForest", "GrassForest", "BushB"]), x, y, rng=rng)
    P(h, "StumpA", 9.0, 30.0, rng=rng)
    P(h, "BoulderB", -22.0, 26.0, rng=rng, sink=0.2)
    figure((-1.0, 22.0, h(-1.0, 22.0)), yaw=2.6)
    return (10.0, 48.0, h(10.0, 48.0) + EYE), (-1.0, 8.0, 6.0), 24.0, 25.0


def scene_gorge(scene):
    """River gorge: the rope footbridge across the river, granite cliffs with scree on the far bank, river stones
    in the water, the watchtower on the far rim and conifers above."""
    clear_scene()
    base = hill(amp=1.0, seed=19)

    def ss(e0, e1, x):
        t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)

    def h(x, y):
        d = abs(y - 0.0)
        z = -7.5 + 7.5 * ss(9.0, 18.0, d) + 0.3 * base(x, y)
        if y > 30:
            z += 34.0 * ss(30.0, 52.0, y)
        return z
    terrain(320, 180, h, "forest", center=(0, 20))
    water(-5.6, 400, center=(0, 0))
    place("Footbridge", (0, 0, 0.0), math.radians(90))
    place("CliffFaceC", (-30, 33, h(-30, 24) - 2.5), math.radians(180))
    place("CliffFaceB", (16, 34, h(16, 26) - 2.5), math.radians(185))
    place("CaveMouth", (58, 36, h(58, 28) - 2.0), math.radians(170))
    place("ScreeA", (-6, 27, h(-6, 27)), 0.3)
    place("ScreeA", (30, 26, h(30, 26)), 2.0)
    place("RiverStones", (-6, 6, -5.75), 0.4)
    place("RiverStones", (9, -4, -5.75), 2.2)
    place("BoulderC", (-14, 22, h(-14, 22) - 0.4), 0.8)
    place("BoulderB", (12, -21, h(12, -21) - 0.2), 0.2)
    place("Watchtower", (40, 22, h(40, 22)), math.radians(200))
    rng = random.Random(71)
    for (x, y) in scatter(rng, 30, (-40, 40), (-40, -20), avoid=[(0, -30, 6)], min_d=2.6):
        P(h, rng.choice(["FernB", "GrassForest", "GrassForest", "FernA", "BushB"]), x, y, rng=rng)
    for i, (x, y) in enumerate(scatter(rng, 40, (-120, 120), (-120, -26), avoid=[(4, -40, 12)], min_d=10.0)):
        P(h, ["SpruceA", "FirA", "SpruceB", "BirchA", "PineA"][i % 5], x, y, rng=rng)
    for i, (x, y) in enumerate(scatter(rng, 40, (-120, 120), (54, 140), min_d=10.0)):
        P(h, ["SpruceA", "FirA", "SpruceB", "PineA"][i % 4], x, y, rng=rng)
    figure((2.0, -24.0, h(2.0, -24.0)), yaw=0.2)
    return (-34.0, -30.0, h(-34.0, -30.0) + EYE), (2.0, 6.0, 0.0), 24.0, 230.0


def scene_fp(scene, which):
    """First person: items held in front of the camera (no arms - ArmsReal is not part of this pass)."""
    clear_scene()
    h = hill(amp=1.0, seed=17)
    terrain(240, 120, h, "forest", center=(0, 40))
    rng = random.Random(61)
    cam = Vector((0.0, 0.0, h(0, 0) + EYE))
    fwd = Vector((0, 1, -0.18)).normalized()
    right = Vector((1, 0, 0))
    up = right.cross(fwd).normalized() * -1 if right.cross(fwd).z < 0 else right.cross(fwd).normalized()
    up = fwd.cross(right).normalized() * -1
    up = Vector((0, 0.18, 1)).normalized()
    if which == "fp_sword":
        g = cam + fwd * 1.55 + right * 0.62 - up * 0.72
        o = place("sword", tuple(g), 0.0)
        o.rotation_euler = (math.radians(-55), math.radians(18), math.radians(-12))
        crate = Vector((1.2, 8.5, h(1.2, 8.5)))
        place("SupplyCrate2", tuple(crate), math.radians(200))
        place("apple", (crate.x - 2.6, crate.y - 1.2, h(crate.x - 2.6, crate.y - 1.2) + 0.16), 0.4)
        place("water_bottle", (crate.x - 3.4, crate.y - 0.4, h(crate.x - 3.4, crate.y - 0.4) + 0.5), 0.0)
        place("bandage", (crate.x - 2.0, crate.y - 2.4, h(crate.x - 2.0, crate.y - 2.4) + 0.16), 1.0)
        place("knife", (crate.x + 2.3, crate.y - 1.6, h(crate.x + 2.3, crate.y - 1.6) + 0.06), 0.0,
              ).rotation_euler = (math.radians(90), 0, math.radians(70))
    else:
        g = cam + fwd * 1.6 - right * 0.55 - up * 0.45
        o = place("bow", tuple(g), 0.0)
        o.rotation_euler = (math.radians(-8), math.radians(-12), math.radians(8))
        a = cam + fwd * 1.35 + right * 0.15 - up * 0.55
        ar = place("arrow", tuple(a), 0.0)
        ar.rotation_euler = (math.radians(-80), 0, math.radians(-14))
        place("SupplyCrate3", (-2.0, 11.0, h(-2.0, 11.0)), math.radians(170))
        place("leather_vest", (2.6, 7.0, h(2.6, 7.0) + 0.05), 0.0).rotation_euler = (math.radians(-80), 0, 0.6)
    for i, (x, y) in enumerate(scatter(rng, 40, (-80, 80), (16, 150), min_d=9.5)):
        P(h, ["SpruceA", "FirA", "SpruceB", "BirchA"][i % 4], x, y, rng=rng)
    for (x, y) in scatter(rng, 30, (-16, 16), (3, 26), avoid=[(1.2, 8.5, 4), (-2, 11, 4)], min_d=2.2):
        P(h, rng.choice(["FernB", "GrassForest", "GrassForest", "FernA"]), x, y, rng=rng)
    P(h, "BoulderB", -8, 13, rng=rng, sink=0.3)
    return tuple(cam), tuple(cam + fwd * 10), 20.0, 160.0


def detail_shots(scene):
    """Close checks of the pieces the scene renders flagged: cabin roof, bench + woodpile bark, boulders, a cliff
    face, a launch plate and the Spire base. Yields (name, camera, target, lens, bearing) after building each."""
    flat = lambda x, y: 0.0  # noqa: E731
    clear_scene()
    terrain(200, 8, flat, "forest")
    place("HunterCabin", (0, 0, 0), 0.0)
    figure((6.0, 9.0, 0.0))
    yield "cabin", (22.0, 30.0, 8.0), (0.0, 0.0, 9.0), 30.0, 20.0
    clear_scene()
    terrain(200, 8, flat, "forest")
    place("LogBench", (0, 0, 0), 0.0)
    place("Woodpile", (7.5, -2.0, 0), 0.0)
    place("Campfire", (-4.5, 3.5, 0), 0.0)
    figure((3.0, -3.0, 0.0))
    yield "camp_props", (2.0, 11.0, 4.0), (2.0, 0.0, 1.4), 30.0, 20.0
    clear_scene()
    terrain(200, 8, flat, "forest")
    place("BoulderB", (-9.0, 0, 0), 0.4)
    place("BoulderC", (0.0, 2.0, 0), 1.0)
    place("BoulderD", (13.0, 6.0, 0), 2.0)
    place("BoulderA", (-3.5, -4.0, 0), 0.0)
    place("RockFlat", (-14.0, -8.0, 0), 0.6)
    figure((5.0, -4.0, 0.0))
    yield "boulders", (-2.0, -22.0, 5.0), (0.0, 2.0, 2.5), 26.0, 200.0
    clear_scene()
    terrain(300, 8, flat, "forest")
    place("CliffFaceB", (0, 0, 0), 0.0)
    place("ScreeA", (-6.0, 12.0, 0), 0.0)
    figure((4.0, 13.0, 0.0))
    yield "cliff", (8.0, 44.0, 5.0), (0.0, 0.0, 12.0), 24.0, 20.0
    clear_scene()
    terrain(300, 8, flat, "meadow")
    place("SpirePlatform", (0, 0, 0))
    place("Spire", (0, 0, 0))
    for i in range(24):
        pos, look = attachment_world("SpirePlatform", "Plate_%d" % (i + 1))
        place("Plinth", tuple(pos), math.atan2(-look.x, look.y))
    figure((5.0, -46.0, 0.6))
    yield "plinth", (6.0, -60.0, 4.0), (0.0, -50.0, 1.2), 30.0, 160.0
    yield "spire_base", (14.0, -34.0, 5.6), (0.0, 0.0, 9.0), 24.0, 160.0


LINEUP_ORTHO = [0.0]


def scene_lineup(scene):
    """One representative per set and scale class, in a row with the 5.5-stud figure."""
    clear_scene()
    h = lambda x, y: 0.0  # noqa: E731
    terrain(600, 30, h, "forest", center=(150, 0))
    row = ["Plinth", "SupplyCrate2", "Barrel", "Campfire", "Tent", "BoulderA", "BoulderC", "FernA", "GrassTallA",
           "BushA", "StumpA", "FallenLogA", "ConiferYoung", "SaplingBroadleaf", "BirchA", "SpruceB", "OakA",
           "Watchtower", "HunterCabin"]
    x = 0.0
    figure((x, 0, 0))
    x += 4.0
    for n in row:
        if n not in MANIFEST:
            continue
        a = MANIFEST[n]
        w = a["size"][0]
        lo = a["boundsMin"][0]
        place(n, (x - lo, 0, 0), 0.0)
        x += w + 3.0
        if n in ("BushA", "OakA"):
            figure((x - 1.0, 0, 0))
            x += 3.0
    mid = x / 2
    LINEUP_ORTHO[0] = x * 1.02
    return (mid, -400.0, 26.0), (mid, 0.0, 26.0), 35.0, 205.0


def asset_tiles(scene, lights):
    """Every asset of every set at eye level next to the 5.5-stud figure (front three-quarter view), one tile per
    asset and light, composed into one contact sheet per set: _sheet_<Set>_<light>.png."""
    tile_dir = os.path.join(PREV, "tiles")
    os.makedirs(tile_dir, exist_ok=True)
    old = scene.render.resolution_x, scene.render.resolution_y
    scene.render.resolution_x, scene.render.resolution_y = 640, 400
    by_set = {}
    for s in SETS:
        mp = os.path.join(OUT, s + ".manifest.json")
        if os.path.exists(mp):
            with open(mp, encoding="utf-8") as f:
                by_set[s] = [a["name"] for a in json.load(f)["assets"] if a["name"] in ROOTS]
    for s, names in by_set.items():
        tiles = {lt: [] for lt in lights}
        for n in names:
            clear_scene()
            terrain(2400, 8, lambda x, y: 0.0, "forest")
            a = MANIFEST[n]
            bmin, bmax = a["boundsMin"], a["boundsMax"]
            held = s == "ItemsReal" and a.get("kind") not in ("Crate", "Armor")
            z0 = -bmin[1] if (held or bmin[1] < -0.3 and s == "ItemsReal") else 0.0
            place(n, (0, 0, z0), 0.0)
            W = bmax[0] - bmin[0]
            H = bmax[1] - bmin[1] if held else bmax[1]
            fx = bmax[0] + 1.6
            figure((fx, 0.0, 0.0), yaw=0.0)
            x0, x1 = bmin[0], fx + 1.3
            Wt = x1 - x0
            Ht = max(H, 5.5)
            cx = (x0 + x1) / 2
            d = max(0.97 * Wt, 1.73 * Ht) * 1.12 + max(0.0, -bmin[2])
            small = H < 3.0
            zc = min(EYE, max(1.4, Ht * 0.55)) if small else EYE
            if Wt > 60.0:                       # the plaza: a flat 120-stud disc reads only from above eye level
                zc = Wt * 0.3
            tgt = (cx, 0.0, Ht * 0.45)
            cam = (cx - 0.32 * d, bmax[2] * 0 + (-bmin[2]) + d, zc)
            camera(scene, cam, tgt, 35.0)
            for lt in lights:
                set_light(scene, lt, 25.0 if lt == "ct14" else 60.0)      # sun behind the camera (front-lit)
                path = os.path.join(tile_dir, "%s_%s_%s.png" % (s, n, lt))
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                tiles[lt].append((n, path))
        for lt in lights:
            compose_sheet(tiles[lt], os.path.join(PREV, "_sheet_%s_%s.png" % (s, lt)))
    scene.render.resolution_x, scene.render.resolution_y = old


def compose_sheet(tiles, path, cols=4):
    """Grid of 640x400 tiles (row 0 at the top) -> one PNG."""
    if not tiles:
        return
    tw, th = 640, 400
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.ones((rows * th, cols * tw, 4), np.float32) * 0.12
    sheet[..., 3] = 1.0
    for k, (n, p) in enumerate(tiles):
        im = bpy.data.images.load(p, check_existing=False)
        px = np.empty(tw * th * 4, np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(th, tw, 4)
        r, c = k // cols, k % cols
        y0 = (rows - 1 - r) * th
        sheet[y0:y0 + th, c * tw:(c + 1) * tw] = px
        bpy.data.images.remove(im)
    out = bpy.data.images.new("AD_sheet", cols * tw, rows * th, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    log("SHEET " + path)


# =============================================================================================== main
def main():
    t0 = time.time()
    scene = setup_render()
    import_all()
    log("IMPORT done in %.0fs" % (time.time() - t0))
    builders = {"forest": scene_forest, "meadow": scene_meadow, "marsh": scene_marsh, "spire": scene_spire,
                "camp": scene_camp, "gorge": scene_gorge}
    for sname in SCENES:
        if sname in builders:
            cam, tgt, lens, bearing = builders[sname](scene)
            camera(scene, cam, tgt, lens)
            for lt in LIGHTS:
                b = bearing if lt == "ct14" else bearing + 35.0
                set_light(scene, lt, b)
                render(scene, "%s_%s" % (sname, lt))
        elif sname == "fp":
            for which in ("fp_sword", "fp_bow"):
                cam, tgt, lens, bearing = scene_fp(scene, which)
                camera(scene, cam, tgt, lens)
                set_light(scene, "ct14", bearing)
                render(scene, which + "_ct14")
        elif sname == "details":
            for (dn, cam, tgt, lens, bearing) in detail_shots(scene):
                camera(scene, cam, tgt, lens)
                set_light(scene, "ct14", bearing)
                render(scene, "detail_" + dn + "_ct14")
        elif sname == "assets":
            asset_tiles(scene, LIGHTS)
        elif sname == "lineup":
            cam, tgt, lens, bearing = scene_lineup(scene)
            c = camera(scene, cam, tgt, lens)
            c.data.type = "ORTHO"
            c.data.ortho_scale = LINEUP_ORTHO[0]
            set_light(scene, "ct14", bearing)
            old = scene.render.resolution_x, scene.render.resolution_y
            scene.render.resolution_x, scene.render.resolution_y = 2400, 900
            render(scene, "_lineup_all")
            scene.render.resolution_x, scene.render.resolution_y = old
    log("AD REVIEW done in %.0fs" % (time.time() - t0))


main()
