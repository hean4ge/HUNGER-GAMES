"""
trees_review.py - EEVEE review renders for TreesReal, made from the EXPORTED GLBs (so they also check the export:
textures, alpha cut-outs, normals, pivots). Daylight is Blender's built-in physical Sky Texture (Blender 5.3 calls
the old Nishita model "Single Scattering"; the newer "Multiple Scattering" model is used) plus a matching sun lamp.

Per asset (art/previews/TreesReal/):
  <Asset>_eye08.png   first-person eye height (5 studs), 8 studs from the trunk, Roblox-like 70 deg vertical FOV
  <Asset>_eye25.png   the same from 25 studs
  <Asset>_full.png    whole silhouette, 5.5-stud reference figure beside it
Sheets: _lineup.png (every asset in a row with the figure), _forest.png / _forest_b.png (eye-level forest groups)

Run on its own (re-renders from the GLBs already exported):
  blender --background --factory-startup --python art/blender/trees_review.py -- <out_dir> <preview_dir> [only=A,B]
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

UP = Vector((0.0, 0.0, 1.0))
EYE = 5.0
FIGURE_H = 5.5


# ---------------------------------------------------------------- scene
def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def setup_scene(res=(1280, 720), samples=48, sun_elev=38.0, sun_az=205.0, haze=0.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    ee = scene.eevee
    ee.taa_render_samples = samples
    for attr, val in (("use_raytracing", True), ("use_shadows", True), ("shadow_ray_count", 2),
                      ("shadow_step_count", 8), ("use_volumetric_shadows", True)):
        if hasattr(ee, attr):
            try:
                setattr(ee, attr, val)
            except Exception:
                pass
    if hasattr(ee, "volumetric_end"):
        ee.volumetric_end = 400.0
    vs = scene.view_settings
    vs.view_transform = "AgX"
    for look in ("AgX - Medium High Contrast", "Medium High Contrast", "None"):
        try:
            vs.look = look
            break
        except TypeError:
            continue
    vs.exposure = 0.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    # sky
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    nt = world.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING" if "MULTIPLE_SCATTERING" in [e.identifier for e in
                                                                     sky.bl_rna.properties["sky_type"].enum_items] else "NISHITA"
    sky.sun_disc = False
    sky.sun_elevation = math.radians(sun_elev)
    sky.sun_rotation = math.radians(sun_az)
    try:
        sky.altitude = 800.0
        sky.air_density = 1.0
        sky.aerosol_density = 1.6
    except Exception:
        pass
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.22
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    if haze > 0:
        vol = nt.nodes.new("ShaderNodeVolumeScatter")
        vol.inputs["Density"].default_value = haze
        vol.inputs["Color"].default_value = (0.78, 0.84, 0.92, 1.0)
        if "Anisotropy" in vol.inputs:
            vol.inputs["Anisotropy"].default_value = 0.55
        nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    scene.world = world
    # sun matching the sky's sun direction
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 4.2
    sd.angle = math.radians(1.2)
    sd.color = (1.0, 0.96, 0.9)
    sun = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(sun)
    el, az = math.radians(sun_elev), math.radians(sun_az)
    # Blender sky: sun_rotation 0 = sun toward +Y? Direction of light travel is from the sun to the scene.
    dir_to_sun = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    sun.rotation_euler = (-dir_to_sun).to_track_quat("-Z", "Y").to_euler()
    ground(scene)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle = math.radians(70.0)
    cam_data.clip_start = 0.1
    cam_data.clip_end = 3000.0
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene, cam, sun


def ground(scene):
    me = bpy.data.meshes.new("Ground")
    s = 600.0
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    me.uv_layers.new(name="UVMap")
    obj = bpy.data.objects.new("Ground", me)
    scene.collection.objects.link(obj)
    m = bpy.data.materials.new("ForestFloor")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 0.09
    n1.inputs["Detail"].default_value = 8.0
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 1.6
    n2.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (_lin(74), _lin(60), _lin(44), 1.0)      # needle litter / soil
    ramp.color_ramp.elements[1].position = 0.65
    ramp.color_ramp.elements[1].color = (_lin(78), _lin(88), _lin(46), 1.0)      # moss / grass
    mixf = nt.nodes.new("ShaderNodeMath")
    mixf.operation = "MULTIPLY_ADD"
    nt.links.new(n1.outputs["Fac"], mixf.inputs[0])
    mixf.inputs[1].default_value = 0.75
    nt.links.new(n2.outputs["Fac"], mixf.inputs[2])
    sc = nt.nodes.new("ShaderNodeMath")
    sc.operation = "MULTIPLY"
    nt.links.new(mixf.outputs[0], sc.inputs[0])
    sc.inputs[1].default_value = 0.62
    nt.links.new(sc.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(n2.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.append(m)
    return obj


def figure(scene, name="Figure"):
    """Blocky 5.5-stud reference figure (R15 proportions), feet at the origin, facing +Y."""
    m = bpy.data.materials.new("FigureCloth")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (_lin(58), _lin(74), _lin(104), 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    root = bpy.data.objects.new(name, None)
    scene.collection.objects.link(root)
    boxes = [((-0.5, 0, 1.0), (0.9, 0.9, 2.0)), ((0.5, 0, 1.0), (0.9, 0.9, 2.0)),   # legs
             ((0, 0, 3.0), (2.0, 1.0, 2.0)),                                       # torso
             ((-1.5, 0, 3.0), (0.9, 0.9, 2.0)), ((1.5, 0, 3.0), (0.9, 0.9, 2.0)),   # arms
             ((0, 0, 4.6), (1.2, 1.1, 1.2))]                                       # head (top 5.2) + hair
    for i, (c, s) in enumerate(boxes):
        me = bpy.data.meshes.new("%s_%d" % (name, i))
        x, y, z = s[0] / 2, s[1] / 2, s[2] / 2
        v = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z), (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        me.from_pydata(v, [], f)
        me.materials.append(m)
        o = bpy.data.objects.new("%s_%d" % (name, i), me)
        o.location = c
        o.parent = root
        scene.collection.objects.link(o)
    # scale so the top of the head is exactly FIGURE_H
    root.scale = (FIGURE_H / 5.2,) * 3
    return root


def import_glbs(out_dir, files):
    roots = {}
    for f in files:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(out_dir, f))
        new = [o for o in bpy.data.objects if o not in before]
        for o in new:
            if o.parent is None and o.type == "EMPTY":
                roots[o.name] = o
    for m in bpy.data.materials:
        if m.node_tree is None:
            continue
        if hasattr(m, "use_transparent_shadow"):
            m.use_transparent_shadow = True
    return roots


def look_at(cam, eye, target):
    cam.location = eye
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()


def show_only(roots, keep):
    keep_set = set()
    for r in keep:
        keep_set.add(r)
        keep_set.update(r.children_recursive)
    for r in roots.values():
        for o in [r] + list(r.children_recursive):
            o.hide_render = o not in keep_set


def bounds(root):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    bpy.context.view_layer.update()
    for o in root.children_recursive:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PREVIEW " + path)


def asset_shots(scene, cam, roots, fig, man_assets, folder, only=None):
    for a in man_assets:
        name = a["name"]
        if only and name not in only:
            continue
        r = roots.get(name)
        if r is None:
            print("NOTE %s not found in the GLBs" % name)
            continue
        r.location = Vector((0.0, 0.0, 0.0))      # the root node carries the GLB row offset: pivot -> world origin
        bpy.context.view_layer.update()
        show_only(roots, [r])
        lo, hi = bounds(r)
        h = hi.z
        w = max(hi.x - lo.x, hi.y - lo.y)
        is_log = a["kind"] == "Prop"
        # figure just left of the trunk as seen from the cameras (which sit at -Y, 20 deg to the right)
        if is_log:
            fig.location = Vector((lo.x - 1.8, 1.2, 0.0))
        else:
            fig.location = Vector((-3.4, -0.8, 0.0))
        fig.rotation_euler = (0, 0, math.radians(15))
        # eye level at 8 and 25 studs (camera on -Y looking at the trunk, slightly off-axis)
        for dist, tag in ((8.0, "eye08"), (25.0, "eye25")):
            eye = Vector((dist * math.sin(math.radians(20)), -dist * math.cos(math.radians(20)), EYE))
            if is_log:
                pitch = math.radians(-14 if dist < 10 else -6)
            else:
                pitch = math.radians(6 if dist < 10 else min(26.0, math.degrees(math.atan2(h * 0.5 - EYE, dist))))
            fwd = Vector((-eye.x, -eye.y, 0)).normalized()
            target = eye + fwd * 10.0 + UP * (10.0 * math.tan(pitch))
            look_at(cam, eye, target)
            render(scene, os.path.join(folder, "%s_%s.png" % (name, tag)))
        # full silhouette
        cam.data.angle = math.radians(38.0)
        span = max(h, w * 0.75, 6.0)
        dist = span * 0.5 / math.tan(math.radians(19.0)) * 1.18 + w * 0.3
        c = Vector((0, 0, max(h * 0.5, 1.5)))
        eye = c + Vector((dist * math.sin(math.radians(25)), -dist * math.cos(math.radians(25)), 0.0))
        eye.z = max(EYE, c.z * 0.6)
        look_at(cam, eye, c)
        render(scene, os.path.join(folder, "%s_full.png" % name))
        cam.data.angle = math.radians(70.0)
        r.location = Vector((0.0, 0.0, 1000.0))
        bpy.context.view_layer.update()


def instance(root, name, loc, rot_z, scale=1.0):
    new_root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(new_root)
    for c in root.children:
        o = c.copy()
        o.parent = new_root
        o.matrix_parent_inverse = c.matrix_parent_inverse.copy()
        bpy.context.scene.collection.objects.link(o)
        o.hide_render = False
    new_root.location = loc
    new_root.rotation_euler = (0, 0, rot_z)
    new_root.scale = (scale, scale, scale)
    return new_root


def forest(scene, cam, roots, man_assets, folder, variant=0):
    """An eye-level look into a mixed mountain forest made of the exported assets."""
    rng = random.Random(31 + variant)
    origin = {a["name"]: a["origin"][0] for a in man_assets}
    for r in roots.values():
        r.hide_render = True
        for o in r.children_recursive:
            o.hide_render = True
    made = []
    plan = []
    if variant == 0:
        mix = (["SpruceA"] * 7 + ["SpruceB"] * 6 + ["FirA"] * 5 + ["PineA"] * 3 + ["BirchA"] * 2 + ["BirchB"] * 1
               + ["ConiferYoung"] * 6 + ["SnagA"] * 1 + ["SnagB"] * 1)
        area = (-45, 45, 8, 110)
    else:
        mix = (["OakA"] * 1 + ["BirchA"] * 4 + ["BirchB"] * 3 + ["SpruceB"] * 4 + ["PineA"] * 3 + ["FirA"] * 2
               + ["ConiferYoung"] * 4 + ["SnagB"] * 1)
        area = (-50, 50, 10, 105)
    pts = []
    for name in mix:
        for _ in range(200):
            x, y = rng.uniform(area[0], area[1]), rng.uniform(area[2], area[3])
            mind = 7.0 if name != "ConiferYoung" else 4.0
            if name == "OakA":
                x, y, mind = 6.0, 38.0, 18.0
            if all((x - px) ** 2 + (y - py) ** 2 > (mind + pm) ** 2 * 0.5 for px, py, pm in pts) and abs(x) + y > 9:
                pts.append((x, y, mind))
                plan.append((name, x, y))
                break
    for name, x, y in plan:
        src = roots.get(name)
        if src is None:
            continue
        made.append(instance(src, name + "_inst", Vector((x, y, 0)), rng.uniform(0, math.tau),
                             rng.uniform(0.9, 1.1)))
    # dead wood near the camera
    for name, x, y, rz in (("FallenLogB", -7.0, 15.0, 0.3), ("StumpA", 6.5, 11.0, 1.0), ("FallenLogA", 12.0, 26.0, 2.2),
                           ("StumpB", -12.0, 30.0, 0.5)):
        src = roots.get(name)
        if src is None:
            continue
        made.append(instance(src, name + "_inst", Vector((x, y, 0)), rz))
    # aerial perspective: a box of thin haze around the grove (a world volume would also swallow the sky)
    me = bpy.data.meshes.new("Haze")
    hx = 260.0
    v = [(-hx, -20, -1), (hx, -20, -1), (hx, 400, -1), (-hx, 400, -1),
         (-hx, -20, 120), (hx, -20, 120), (hx, 400, 120), (-hx, 400, 120)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me.from_pydata(v, [], f)
    haze = bpy.data.objects.new("Haze", me)
    scene.collection.objects.link(haze)
    hm = bpy.data.materials.new("HazeMat")
    hm.use_nodes = True
    nt = hm.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumeScatter")
    vol.inputs["Density"].default_value = 0.0016
    vol.inputs["Color"].default_value = (0.8, 0.86, 0.95, 1.0)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    me.materials.append(hm)
    eye = Vector((0.0, -2.0, EYE))
    look_at(cam, eye, eye + Vector((0.08, 1.0, 0.16)))
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    render(scene, os.path.join(folder, "_forest%s.png" % ("" if variant == 0 else "_b")))
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    bpy.data.objects.remove(haze, do_unlink=True)
    for o in made:
        for c in list(o.children):
            bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.objects.remove(o, do_unlink=True)


def lineup(scene, cam, roots, man_assets, fig, folder):
    order = ["SpruceA", "PineA", "FirA", "SpruceB", "OakA", "BirchA", "BirchB", "SnagA", "SnagB", "ConiferYoung",
             "StumpA", "StumpB", "FallenLogA", "FallenLogB"]
    by = {a["name"]: a for a in man_assets}
    x = 0.0
    keep = []
    fig.location = Vector((-6.0, 0, 0))
    fig.rotation_euler = (0, 0, 0)
    for n in order:
        a = by.get(n)
        r = roots.get(n)
        if a is None or r is None:
            continue
        w = a["size"][0]
        r.location = Vector((x - a["boundsMin"][0], 0.0, 0.0))
        keep.append(r)
        x += w + 3.0
    show_only(roots, keep)
    bpy.context.view_layer.update()
    total = x
    scene.render.resolution_x, scene.render.resolution_y = 2400, 675
    cam.data.sensor_fit = "HORIZONTAL"
    cam.data.angle = math.radians(14.0)
    dist = (total + 12.0) * 0.5 / math.tan(math.radians(7.0))
    c = Vector((total * 0.5 - 6.0, 0.0, 22.0))
    look_at(cam, c + Vector((0, -dist, 6.0)), c)
    render(scene, os.path.join(folder, "_lineup.png"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(70.0)
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    for r in keep:
        r.location = Vector((0, 0, 1000))


def compose_sheets(shots_dir, folder, names):
    """<Asset>.png = [eye level 8 studs | eye level 25 studs | full view], each 640 x 360, written compactly."""
    import numpy as np
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    import tex_trees as tx
    for name in names:
        panels = []
        for tag in ("eye08", "eye25", "full"):
            path = os.path.join(shots_dir, "%s_%s.png" % (name, tag))
            if not os.path.exists(path):
                break
            img = bpy.data.images.load(path, check_existing=False)
            img.colorspace_settings.name = "Non-Color"
            w, h = img.size
            a = np.array(img.pixels[:], dtype=np.float64).reshape(h, w, img.channels)[..., :3]
            bpy.data.images.remove(img)
            a = a.reshape(h // 2, 2, w // 2, 2, 3).mean(axis=(1, 3))
            panels.append(a)
        if len(panels) == 3:
            sheet = np.concatenate(panels, axis=1)
            tx.write_png(os.path.join(folder, name + ".png"), sheet)
            print("PREVIEW " + os.path.join(folder, name + ".png"))


def render_all(out_dir, preview_dir, files, flags=None):
    flags = flags or {}
    # absolute paths: Blender resolves a relative render filepath against the drive root (it wrote the lineup
    # and forest sheets to C:/art/previews/... instead of the repo), while Python resolves it against the cwd
    folder = os.path.abspath(os.path.join(preview_dir, "TreesReal"))
    os.makedirs(folder, exist_ok=True)
    import tempfile
    shots_dir = flags.get("shots") if isinstance(flags.get("shots"), str) else os.path.join(tempfile.gettempdir(),
                                                                                             "LS_TreesReal_shots")
    shots_dir = os.path.abspath(shots_dir)
    os.makedirs(shots_dir, exist_ok=True)
    man_path = os.path.join(out_dir, "TreesReal.manifest.json")
    scene, cam, sun = setup_scene()
    roots = import_glbs(out_dir, files)
    man_assets = None
    if os.path.exists(man_path) and not any(f.startswith("_") for f in files):
        with open(man_path, encoding="utf-8") as f:
            man_assets = json.load(f)["assets"]
    else:
        # test export: rebuild origins from the GLB layout (assets in a row along X)
        man_assets = []
        for name, r in roots.items():
            lo, hi = bounds(r)
            man_assets.append({"name": name, "origin": [r.location.x, 0, 0], "kind": "Prop" if name.startswith(("Fallen", "Stump")) else "Tree",
                               "size": [hi.x - lo.x, hi.z - lo.z, hi.y - lo.y], "boundsMin": [lo.x - r.location.x, lo.z, -hi.y]})
    for r in roots.values():
        r.location = Vector((0, 0, 1000))
    fig = figure(scene)
    only = set(flags["only"].split(",")) if isinstance(flags.get("only"), str) else None
    if not flags.get("noshots"):
        asset_shots(scene, cam, roots, fig, man_assets, shots_dir, only)
        compose_sheets(shots_dir, folder, [a["name"] for a in man_assets if not only or a["name"] in only])
    if not flags.get("nosheets"):
        fig.location = Vector((0, 0, -100))
        lineup(scene, cam, roots, man_assets, fig, folder)
        fig.location = Vector((0, 0, -100))
        forest(scene, cam, roots, man_assets, folder, 0)
        forest(scene, cam, roots, man_assets, folder, 1)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0]
    preview_dir = argv[1]
    flags = {}
    for a in argv[2:]:
        if "=" in a:
            k, v = a.split("=", 1)
            flags[k] = v
        else:
            flags[a] = True
    files = flags.get("files", "TreesReal_Conifers.glb,TreesReal_Broadleaf.glb,TreesReal_Deadwood.glb").split(",")
    render_all(out_dir, preview_dir, files, flags)
