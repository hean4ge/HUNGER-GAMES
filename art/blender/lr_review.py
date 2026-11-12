"""
lr_review.py - review renders for the LandmarksReal set: Cycles (OptiX GPU when present) under Blender's built-in
Sky Texture plus a matching sun lamp, on a meadow-coloured ground, with a 5.5-stud scale figure. Never exported.
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector

TAU = 2.0 * math.pi


def enable_gpu(scene):
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                devs = [d for d in prefs.devices if d.type == kind]
                if devs:
                    for d in prefs.devices:
                        d.use = d.type == kind
                    scene.cycles.device = "GPU"
                    return kind
            except Exception:
                continue
    except Exception:
        pass
    scene.cycles.device = "CPU"
    return "CPU"


def setup(sun_elev=34.0, sun_az=150.0, samples=96, exposure=-0.9, ground=True, ground_size=1200.0, holes=None):
    """sun_az: compass direction the sun comes FROM, degrees clockwise from Blender +Y (north)."""
    scene = bpy.context.scene
    dev = enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.use_denoising = True
    try:
        c.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 3
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    for vt in ("AgX", "Filmic"):
        try:
            scene.view_settings.view_transform = vt
            break
        except TypeError:
            continue
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        try:
            scene.view_settings.look = "None"
        except TypeError:
            pass
    scene.view_settings.exposure = exposure
    # sky
    world = bpy.data.worlds.get("LR_Sky") or bpy.data.worlds.new("LR_Sky")
    world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    sky = nt.nodes.new("ShaderNodeTexSky")
    for st in ("MULTIPLE_SCATTERING", "SINGLE_SCATTERING", "HOSEK_WILKIE"):
        try:
            sky.sky_type = st
            break
        except TypeError:
            continue
    try:
        sky.sun_disc = False
    except AttributeError:
        pass
    el = math.radians(sun_elev)
    az = math.radians(sun_az)
    try:
        sky.sun_elevation = el
        sky.sun_rotation = (math.pi / 2 - az)          # sky rotation is measured from +X counter-clockwise
    except AttributeError:
        pass
    try:
        sky.altitude = 300.0
        sky.air_density = 1.0
        sky.aerosol_density = 1.4
    except AttributeError:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.21
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    scene.world = world
    # sun lamp matching the sky's sun
    sun = bpy.data.objects.get("LR_Sun")
    if sun is None:
        ld = bpy.data.lights.new("LR_Sun", "SUN")
        sun = bpy.data.objects.new("LR_Sun", ld)
        scene.collection.objects.link(sun)
    sun.data.energy = 5.4
    sun.data.color = (1.0, 0.92, 0.82)
    sun.data.angle = math.radians(0.8)
    d = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))   # toward the sun
    sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    if ground:
        make_ground(ground_size, holes)
    return dev


def make_ground(size=1200.0, holes=None):
    """Meadow-coloured ground plane; holes = [(x, y, r)] are cut through it (launch tubes)."""
    g = bpy.data.objects.get("LR_Ground")
    if g is not None:
        return g
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size / 2)
    if holes:
        ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z -= 2.0
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("LR_Ground")
    bm.to_mesh(me)
    bm.free()
    g = bpy.data.objects.new("LR_Ground", me)
    bpy.context.scene.collection.objects.link(g)
    if holes:
        from mathutils import Matrix
        cb = bmesh.new()
        for (x, y, r) in holes:
            bmesh.ops.create_cone(cb, cap_ends=True, segments=32, radius1=r, radius2=r, depth=6.0,
                                  matrix=Matrix.Translation((x, y, 0.0)))
        cm = bpy.data.meshes.new("LR_GroundCut")
        cb.to_mesh(cm)
        cb.free()
        co = bpy.data.objects.new("LR_GroundCut", cm)
        bpy.context.scene.collection.objects.link(co)
        mod = g.modifiers.new("holes", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = co
        co.hide_render = True
    g.location.z = -0.01
    mat = bpy.data.materials.new("LR_GroundMat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise")          # large patches: lush / dry grass / bare soil
    n1.inputs["Scale"].default_value = 0.05
    n1.inputs["Detail"].default_value = 6.0
    n2 = nt.nodes.new("ShaderNodeTexNoise")          # fine clumps
    n2.inputs["Scale"].default_value = 2.5
    n2.inputs["Detail"].default_value = 10.0
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    math_add = nt.nodes.new("ShaderNodeMath")
    math_add.operation = "MULTIPLY_ADD"
    math_add.inputs[1].default_value = 0.35
    nt.links.new(n2.outputs["Fac"], math_add.inputs[0])
    nt.links.new(n1.outputs["Fac"], math_add.inputs[2])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.45
    els[0].color = (0.028, 0.045, 0.012, 1)
    els[1].position = 0.85
    els[1].color = (0.085, 0.078, 0.035, 1)
    mid = els.new(0.66)
    mid.color = (0.05, 0.068, 0.02, 1)
    nt.links.new(math_add.outputs["Value"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    nt.links.new(n2.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    me.materials.append(mat)
    return g


def _capsule(bm, p0, p1, r, segs=10, rings=4):
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    L = axis.length
    q = axis.normalized().to_track_quat("Z", "Y")
    prof = []
    for i in range(rings + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / rings
        prof.append((r * math.cos(a), r * math.sin(a)))
    for i in range(rings + 1):
        a = (math.pi / 2) * i / rings
        prof.append((r * math.cos(a), L + r * math.sin(a)))
    ringsv = []
    for (rr, z) in prof:
        ringsv.append([bm.verts.new(p0 + q @ Vector((rr * math.cos(TAU * k / segs), rr * math.sin(TAU * k / segs), z)))
                       for k in range(segs)])
    for a, b in zip(ringsv[:-1], ringsv[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))


def figure(name="LR_Figure", loc=(0, 0, 0), rz=0.0, color=(0.09, 0.1, 0.12)):
    """5.5-stud scale figure (neutral clothing), facing +Y."""
    bm = bmesh.new()
    for sx in (-1, 1):
        _capsule(bm, (sx * 0.38, 0, 0.25), (sx * 0.36, 0, 2.55), 0.3)
        _capsule(bm, (sx * 1.0, 0, 2.75), (sx * 0.86, 0.05, 4.3), 0.22)
    _capsule(bm, (0, 0, 2.75), (0, 0, 4.15), 0.62)
    _capsule(bm, (0, 0, 4.45), (0, 0, 4.7), 0.18)
    _capsule(bm, (0, 0, 4.85), (0, 0.02, 5.08), 0.4)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (0, 0, rz)
    mat = bpy.data.materials.get("LR_FigureMat") or bpy.data.materials.new("LR_FigureMat")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.75
    me.materials.append(mat)
    return ob


def camera(name="LR_Cam"):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cd = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, cd)
        bpy.context.scene.collection.objects.link(cam)
    cam.data.clip_start = 0.05
    cam.data.clip_end = 5000
    bpy.context.scene.camera = cam
    return cam


def render(path, cam_loc, target, lens=35.0, res=(1600, 900), show=None, hide_names=("Collider",), samples=None):
    scene = bpy.context.scene
    cam = camera()
    cam.data.lens = lens
    cam.location = Vector(cam_loc)
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = res
    if samples:
        scene.cycles.samples = samples
    keep = {"LR_Ground", "LR_Sun", "LR_Cam"}
    hide_names = tuple(hide_names) + ("LR_GroundCut",)
    vis = None if show is None else set(show)
    for o in scene.objects:
        hidden = False
        if o.name in keep:
            hidden = False
        elif vis is not None and o not in vis:
            hidden = True
        if any(h in o.name for h in hide_names):
            hidden = True
        o.hide_render = hidden
    scene.render.filepath = path
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for o in scene.objects:
        o.hide_render = False
    print("RENDER " + path)
    return path


def load_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)[..., :3]


def sheet(paths, out, cols=2, labels=None, cell_w=800):
    """Contact sheet (rows of cells, each image scaled to cell_w by nearest/box filtering)."""
    import tex_landmarks as T
    imgs = []
    for p in paths:
        a = load_png(p)
        h, w = a.shape[:2]
        f = max(1, int(round(w / cell_w)))
        if f > 1:
            a = a[: h - h % f, : w - w % f].reshape(h // f, f, w // f, f, 3).mean(axis=(1, 3))
        imgs.append(a)
    ch = max(i.shape[0] for i in imgs)
    cw = max(i.shape[1] for i in imgs)
    rows = (len(imgs) + cols - 1) // cols
    canvas = np.full((rows * (ch + 8) + 8, cols * (cw + 8) + 8, 3), 0.12, np.float32)
    for k, a in enumerate(imgs):
        r, c = divmod(k, cols)
        y0 = canvas.shape[0] - (r + 1) * (ch + 8)          # row 0 = bottom in our PNG writer
        x0 = 8 + c * (cw + 8)
        canvas[y0 + (ch - a.shape[0]): y0 + ch, x0: x0 + a.shape[1]] = a
    T.write_png(out, np.clip(canvas, 0, 1), dither=False)
    print("SHEET " + out)
    return out
