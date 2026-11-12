"""
gr_preview.py - review renders for GroundReal made from the EXPORTED GLB + PNGs (what Roblox will receive).

Cycles (GPU when present) under Blender's built-in Sky Texture (multiple scattering) with a matching sun. Materials
are rebuilt from the manifest: ColorMap (sRGB, alpha cut-out at 0.5 like Roblox AlphaMode Transparency with part
Transparency 0), NormalMap (OpenGL, tangent space), RoughnessMap; back faces are culled like Roblox's single-sided
MeshParts. A 5.5-stud reference figure stands next to every asset; the key light comes from the front-right
(set_sun bearing 40) for the shots. Outputs into <preview_dir>/GroundReal/:
  <Asset>_close.jpg   eye-level (5 studs) shot at 4-8 studs
  <Asset>_mid.jpg     eye-level shot at ~20 studs (big pieces: the whole asset)
  _lineup.png         every asset in rows next to the figure, labelled (gr_vignettes)
  _vignette_forest.png, _vignette_meadow.png, _vignette_cliffs.png   (gr_vignettes, with TreesReal when present)
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

import tex_ground as tg

FIG_H = 5.5
EYE = 5.0


# =============================================================================================== scene
def set_sun(scene, elev, rot):
    """Sky sun: rot is the compass bearing of the sun measured from +Y toward +X (Blender Sky Texture convention,
    checked with shadow probes: 0 = sun at +Y, 90 = sun at +X). Asset fronts face +Y."""
    sky = [n for n in scene.world.node_tree.nodes if n.type == "TEX_SKY"][0]
    sky.sun_elevation = math.radians(elev)
    sky.sun_rotation = math.radians(rot)


def setup_scene(res=(1280, 720), samples=96, sun_elev=36.0, sun_rot=40.0, strength=0.075):
    """sun_rot 40: front-right key light for the asset shots (camera sits front-left at -35 deg)."""
    scene = bpy.context.scene
    tg.enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = True
    try:
        c.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.transparent_max_bounces = 24
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.filter_width = 1.2
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.film_transparent = False
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    world = bpy.data.worlds.get("GR_Sky") or bpy.data.worlds.new("GR_Sky")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_elevation = math.radians(sun_elev)
    sky.sun_rotation = math.radians(sun_rot)
    sky.sun_disc = True
    sky.altitude = 300.0
    try:
        sky.aerosol_density = 1.6
        sky.air_density = 1.0
    except AttributeError:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    scene.world = world
    return scene


def camera(scene, loc, target, lens=28.0, name="GR_PrevCam"):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.sensor_width = 36
    cam.data.clip_start = 0.05
    cam.data.clip_end = 2000
    cam.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


def ground_material(kind="soil"):
    name = "GR_Ground_" + kind
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 0.35
    n1.inputs["Detail"].default_value = 8
    n1.inputs["Roughness"].default_value = 0.6
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 9.0
    n2.inputs["Detail"].default_value = 6
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 14.0
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    if kind == "soil":          # forest floor: dark humus, needle/leaf litter, a little moss
        cols = [(0.0, (40, 33, 26)), (0.42, (62, 51, 39)), (0.6, (84, 70, 52)), (0.78, (58, 62, 36)),
                (1.0, (72, 62, 46))]
    elif kind == "meadow":      # grass ground (as seen under the grass cards)
        cols = [(0.0, (70, 78, 40)), (0.5, (96, 102, 50)), (0.75, (120, 112, 64)), (1.0, (90, 96, 48))]
    else:                       # neutral review ground: forest soil with litter and sparse grass
        cols = [(0.0, (62, 52, 40)), (0.45, (88, 74, 56)), (0.7, (104, 90, 66)), (0.85, (78, 84, 50)),
                (1.0, (96, 86, 64))]
    cr.elements[0].position = cols[0][0]
    cr.elements[0].color = tuple(float(tg.srgb_to_lin(v / 255.0)) for v in cols[0][1]) + (1.0,)
    cr.elements[1].position = cols[-1][0]
    cr.elements[1].color = tuple(float(tg.srgb_to_lin(v / 255.0)) for v in cols[-1][1]) + (1.0,)
    for pos, col in cols[1:-1]:
        e = cr.elements.new(pos)
        e.color = tuple(float(tg.srgb_to_lin(v / 255.0)) for v in col) + (1.0,)
    mixn = nt.nodes.new("ShaderNodeMath")
    mixn.operation = "MULTIPLY_ADD"
    nt.links.new(n2.outputs["Fac"], mixn.inputs[0])
    mixn.inputs[1].default_value = 0.35
    nt.links.new(n1.outputs["Fac"], mixn.inputs[2])
    nt.links.new(mixn.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.05
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def ground(scene, size=400, kind="neutral", slope=None, name="GR_Ground"):
    ob = bpy.data.objects.get(name)
    if ob is None:
        n = 60
        xs = np.linspace(-size / 2, size / 2, n)
        V, F = [], []
        for j in range(n):
            for i in range(n):
                V.append((xs[i], xs[j], 0.0))
        for j in range(n - 1):
            for i in range(n - 1):
                a = j * n + i
                F.append((a, a + 1, a + n + 1, a + n))
        ob = tg.mesh_object(name, np.array(V), F)
        for p in ob.data.polygons:
            p.use_smooth = True
    ob.data.materials.clear()
    ob.data.materials.append(ground_material(kind))
    if slope is not None:
        co = tg.vertex_coords(ob.data)
        co[:, 2] = slope(co[:, 0], co[:, 1])
        ob.data.vertices.foreach_set("co", co.astype(np.float32).ravel())
        ob.data.update()
    return ob


def figure(scene, loc=(0, 0, 0), yaw=0.0, name="GR_Figure"):
    """Simple 5.5-stud mannequin (head top at 5.5)."""
    if bpy.data.objects.get(name):
        ob = bpy.data.objects[name]
        ob.location = loc
        ob.rotation_euler = (0, 0, yaw)
        return ob
    import bmesh
    bm = bmesh.new()

    def capsule(p0, p1, r, seg=12):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        L = d.length
        m = Matrix.Translation(p0) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=L)
        bmesh.ops.transform(bm, matrix=m @ Matrix.Translation((0, 0, L / 2)), verts=geom["verts"])
        for pp in (p0, p1):
            g = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=8, radius=r)
            bmesh.ops.translate(bm, vec=pp, verts=g["verts"])
    capsule((-0.38, 0, 0.25), (-0.33, 0, 2.55), 0.3)
    capsule((0.38, 0, 0.25), (0.33, 0, 2.55), 0.3)
    capsule((0, 0, 2.75), (0, 0, 4.15), 0.62)
    capsule((-0.95, 0, 4.25), (-1.1, 0.05, 2.45), 0.22)
    capsule((0.95, 0, 4.25), (1.1, 0.05, 2.45), 0.22)
    g = bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=12, radius=0.45)
    bmesh.ops.translate(bm, vec=Vector((0, 0, 5.05)), verts=g["verts"])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    m = bpy.data.materials.new("GR_FigureMat")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.06, 0.09, 0.16, 1)
    b.inputs["Roughness"].default_value = 0.7
    me.materials.append(m)
    ob.location = loc
    ob.rotation_euler = (0, 0, yaw)
    return ob


# =============================================================================================== import + materials
def texture_material(name, sa, tex_root):
    m = bpy.data.materials.get("PV_" + name)
    if m:
        return m
    m = bpy.data.materials.new("PV_" + name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    out = nt.nodes.get("Material Output")

    def img(rel, cs):
        path = os.path.join(tex_root, os.path.basename(rel))
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        n.interpolation = "Linear"
        return n
    c = img(sa["colorMap"], "sRGB")
    nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    nmap = img(sa["normalMap"], "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(nmap.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    r = img(sa["roughnessMap"], "Non-Color")
    nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.5
    # Roblox renders MeshParts single-sided: cull back faces (Cycles would flip their normals instead)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    front = nt.nodes.new("ShaderNodeMath")
    front.operation = "SUBTRACT"
    front.inputs[0].default_value = 1.0
    nt.links.new(geo.outputs["Backfacing"], front.inputs[1])
    if sa.get("alphaMode") == "Transparency":
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = "GREATER_THAN"
        gt.inputs[1].default_value = 0.5
        nt.links.new(c.outputs["Alpha"], gt.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(gt.outputs[0], mul.inputs[0])
        nt.links.new(front.outputs[0], mul.inputs[1])
        nt.links.new(mul.outputs[0], bsdf.inputs["Alpha"])
    else:
        nt.links.new(front.outputs[0], bsdf.inputs["Alpha"])
    m.use_backface_culling = True
    return m


def import_glb(glb_path, manifest, tex_root):
    """Import the GLB, re-centre every asset on its manifest origin, apply PV_ materials. Returns {asset: root}."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = {}
    by_name = {o.name: o for o in new}
    for a in manifest["assets"]:
        root = by_name.get(a["name"])
        if root is None:
            continue
        ox = a["origin"][0]
        root.location.x -= ox
        roots[a["name"]] = root
        for p in a["parts"]:
            ob = by_name.get(p["name"])
            if ob is None or ob.type != "MESH":
                continue
            mat = texture_material(p["textureSet"], p["surfaceAppearance"], tex_root)
            ob.data.materials.clear()
            ob.data.materials.append(mat)
            ob.visible_shadow = bool(p.get("castShadow", True))
    bpy.context.view_layer.update()
    return roots


def set_visible(roots, names):
    for n, r in roots.items():
        vis = n in names
        r.hide_render = not vis
        for c in r.children_recursive:
            c.hide_render = not vis


def bounds(root):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for c in root.children_recursive:
        if c.type != "MESH":
            continue
        for v in c.bound_box:
            w = c.matrix_world @ Vector(v)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def instance(root, loc, rot_z=0.0, scale=1.0, name=None):
    """Linked duplicate of an asset hierarchy (shares meshes)."""
    new_root = bpy.data.objects.new(name or (root.name + "_inst"), None)
    bpy.context.scene.collection.objects.link(new_root)
    for c in root.children:
        d = c.copy()
        bpy.context.scene.collection.objects.link(d)
        d.parent = new_root
        d.matrix_parent_inverse = Matrix.Identity(4)
        d.location = c.location
        d.rotation_euler = c.rotation_euler
        d.rotation_quaternion = c.rotation_quaternion
        d.scale = c.scale
        d.hide_render = False
    new_root.location = loc
    new_root.rotation_euler = (0, 0, rot_z)
    new_root.scale = (scale, scale, scale)
    return new_root


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# =============================================================================================== shots
def asset_shots(scene, roots, manifest, out_dir, names=None, log=print):
    fig = figure(scene)
    fmt = scene.render.image_settings
    fmt.file_format = "JPEG"          # per-asset shots as JPEG q88 keeps the repo light; lineup + vignettes stay PNG
    fmt.quality = 88
    paths = []
    for a in manifest["assets"]:
        n = a["name"]
        if names and n not in names:
            continue
        set_visible(roots, {n})
        root = roots[n]
        lo, hi = bounds(root)
        size = hi - lo
        h = size.z
        w = max(size.x, size.y)
        if w > 16:
            fig.location = (lo.x + w * 0.68, hi.y + 1.6, 0)     # in front of the right third of a cliff
        else:
            fig.location = (hi.x + 1.9, (lo.y + hi.y) / 2 + 0.3, 0)   # beside the asset, right of it
        fig.rotation_euler = (0, 0, math.radians(200))
        fig.hide_render = False
        # close: 4-8 studs from the asset's near face, eye level
        dist = min(8.0, max(4.0, w * 0.75 + 2.5))
        az = math.radians(-35)
        tgt = Vector(((lo.x + hi.x) / 2 - 0.6, (lo.y + hi.y) / 2, min(h * 0.45, 3.0)))
        cam_loc = tgt + Vector((math.sin(az) * (dist + w / 2), math.cos(az) * (dist + w / 2), 0))
        cam_loc.z = EYE
        lens = 26.0 if h > 8 or w > 10 else 32.0
        camera(scene, cam_loc, tgt, lens)
        paths.append(render(scene, os.path.join(out_dir, n + "_close.jpg")))
        # mid: ~20 studs (big pieces: far enough to show the whole asset)
        dist = 20.0 + w / 2 if max(h, w) < 16 else max(w, h) * 1.25 + 8.0
        tgt = Vector(((lo.x + hi.x) / 2 - 0.8, (lo.y + hi.y) / 2, min(h * 0.4, 6.0) if max(h, w) < 16 else h * 0.42))
        cam_loc = tgt + Vector((math.sin(az) * dist, math.cos(az) * dist, 0))
        cam_loc.z = EYE
        camera(scene, cam_loc, tgt, 40.0 if max(h, w) < 12 else 30.0)
        paths.append(render(scene, os.path.join(out_dir, n + "_mid.jpg")))
        log("PREVIEW %s" % n)
    fmt.file_format = "PNG"
    return paths
