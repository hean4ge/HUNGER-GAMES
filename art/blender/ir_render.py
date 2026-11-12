"""
ir_render.py - review renders for ItemsReal, made from the EXPORTED GLB (so the previews show exactly
what Roblox imports: geometry, UVs, embedded textures). Cycles (GPU, denoised), Blender's built-in physical Sky
Texture + a matching sun, a procedural forest-floor ground and a 5.5-stud mannequin for scale.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

import tex_items as tx

V = Vector


# =============================================================================================== scene
def init_scene(res=(1280, 720), samples=96):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    tx.enable_gpu(sc)
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.cycles.max_bounces = 6
    sc.cycles.transparent_max_bounces = 16
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.view_settings.exposure = 0.0
    return sc


def sky(sun_elev=38.0, sun_azim=135.0, strength=0.22, sun_strength=4.2):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("IR_Sky")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    sk = nt.nodes.new("ShaderNodeTexSky")
    sk.sky_type = "MULTIPLE_SCATTERING"
    sk.sun_disc = False
    sk.sun_elevation = math.radians(sun_elev)
    sk.sun_rotation = math.radians(sun_azim)
    sk.altitude = 300.0
    bg.inputs["Strength"].default_value = strength
    nt.links.new(sk.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    sc.world = w
    sun = bpy.data.objects.get("IR_Sun")
    if sun is None:
        ld = bpy.data.lights.new("IR_Sun", "SUN")
        sun = bpy.data.objects.new("IR_Sun", ld)
        sc.collection.objects.link(sun)
    sun.data.energy = sun_strength
    sun.data.angle = math.radians(0.8)
    sun.data.color = (1.0, 0.96, 0.9)
    # sky texture: rotation 0 = sun toward +Y? point the lamp the same way as the sky's sun
    e, a = math.radians(sun_elev), math.radians(sun_azim)
    d = V((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return sun


def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return m, nt


def forest_ground(size=60.0, name="IR_Ground"):
    """Forest floor: dark loam, dry needle and leaf litter, moss patches, small stones (backdrop only)."""
    me = bpy.data.meshes.new(name)
    h = size / 2
    me.from_pydata([(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m, nt = _mat("IR_ForestFloor")
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    L.new(bsdf.outputs[0], out.inputs["Surface"])
    tc = N.new("ShaderNodeTexCoord")

    def noise(scale, detail=6.0, rough=0.6, vec=None):
        n = N.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        L.new(vec or tc.outputs["Object"], n.inputs["Vector"])
        return n

    def ramp(fac, stops):
        r = N.new("ShaderNodeValToRGB")
        L.new(fac, r.inputs["Fac"])
        el = r.color_ramp.elements
        el[0].position, el[0].color = stops[0][0], stops[0][1]
        el[1].position, el[1].color = stops[-1][0], stops[-1][1]
        for pos, col in stops[1:-1]:
            e = el.new(pos)
            e.color = col
        return r

    def lin(r, g, b):
        c = tx.srgb_to_lin(np.array([r, g, b]) / 255.0)
        return (float(c[0]), float(c[1]), float(c[2]), 1.0)

    soil = ramp(noise(0.9).outputs["Fac"], [(0.35, lin(46, 36, 27)), (0.55, lin(70, 56, 42)), (0.7, lin(88, 72, 54))])
    # needle litter: stretched voronoi edges in a few rotated layers
    mixc = soil.outputs["Color"]
    for k, (rot, sc) in enumerate(((0.3, 9.0), (1.4, 11.0), (2.4, 8.0))):
        mp = N.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, rot)
        mp.inputs["Scale"].default_value = (1.0, 7.0, 1.0)
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        vo = N.new("ShaderNodeTexVoronoi")
        vo.feature = "DISTANCE_TO_EDGE"
        vo.inputs["Scale"].default_value = sc
        L.new(mp.outputs[0], vo.inputs["Vector"])
        r = ramp(vo.outputs["Distance"], [(0.0, (1, 1, 1, 1)), (0.03, (0, 0, 0, 1))])
        gate = ramp(noise(2.0 + k).outputs["Fac"], [(0.45, (0, 0, 0, 1)), (0.6, (1, 1, 1, 1))])
        mm = N.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        L.new(r.outputs["Color"], mm.inputs[0])
        L.new(gate.outputs["Color"], mm.inputs[1])
        mx = N.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        L.new(mm.outputs[0], mx.inputs["Factor"])
        L.new(mixc, mx.inputs["A"])
        mx.inputs["B"].default_value = lin(*((126, 92, 58), (110, 80, 50), (140, 108, 70))[k])
        mixc = mx.outputs["Result"]
    moss = ramp(noise(0.5, 4).outputs["Fac"], [(0.58, (0, 0, 0, 1)), (0.66, (1, 1, 1, 1))])
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    L.new(moss.outputs["Color"], mx.inputs["Factor"])
    L.new(mixc, mx.inputs["A"])
    mn = ramp(noise(14.0).outputs["Fac"], [(0.3, lin(44, 58, 26)), (0.7, lin(76, 92, 40))])
    L.new(mn.outputs["Color"], mx.inputs["B"])
    mixc = mx.outputs["Result"]
    st = N.new("ShaderNodeTexVoronoi")
    st.inputs["Scale"].default_value = 6.0
    L.new(tc.outputs["Object"], st.inputs["Vector"])
    stones = ramp(st.outputs["Distance"], [(0.0, (1, 1, 1, 1)), (0.12, (0, 0, 0, 1))])
    gate = ramp(noise(1.3).outputs["Fac"], [(0.55, (0, 0, 0, 1)), (0.62, (1, 1, 1, 1))])
    sm = N.new("ShaderNodeMath")
    sm.operation = "MULTIPLY"
    L.new(stones.outputs["Color"], sm.inputs[0])
    L.new(gate.outputs["Color"], sm.inputs[1])
    mx = N.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    L.new(sm.outputs[0], mx.inputs["Factor"])
    L.new(mixc, mx.inputs["A"])
    mx.inputs["B"].default_value = lin(120, 116, 106)
    L.new(mx.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.02
    hsum = N.new("ShaderNodeMath")
    hsum.operation = "ADD"
    L.new(noise(6.0, 8).outputs["Fac"], hsum.inputs[0])
    L.new(sm.outputs[0], hsum.inputs[1])
    L.new(hsum.outputs[0], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    ob.data.materials.append(m)
    return ob


def mannequin(loc=(0, 0, 0), yaw=0.0, name="IR_Figure"):
    """5.5-stud neutral mannequin (R15-like torso 2 x 1 so the vests fit)."""
    import bmesh
    parts = []

    def ell(c, r):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
        bmesh.ops.scale(bm, vec=V(r), verts=bm.verts)
        bmesh.ops.translate(bm, vec=V(c), verts=bm.verts)
        return bm

    def caps(a, b, r):
        a, b = V(a), V(b)
        d = b - a
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=r, radius2=r * 0.92, depth=d.length)
        q = V((0, 0, 1)).rotation_difference(d.normalized())
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=q.to_matrix(), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
        return bm
    bms = [ell((0, 0, 3.55), (0.95, 0.5, 0.98)), ell((0, 0, 4.95), (0.36, 0.4, 0.45)), caps((0, 0, 4.4), (0, 0, 4.7), 0.2),
           caps((-0.45, 0, 2.55), (-0.45, 0, 0.12), 0.34), caps((0.45, 0, 2.55), (0.45, 0, 0.12), 0.34),
           caps((-1.15, 0, 4.3), (-1.25, 0.05, 2.45), 0.26), caps((1.15, 0, 4.3), (1.25, 0.05, 2.45), 0.26),
           ell((-0.45, 0.1, 0.08), (0.24, 0.42, 0.1)), ell((0.45, 0.1, 0.08), (0.24, 0.42, 0.1)),
           ell((0, 0, 2.65), (0.9, 0.48, 0.42))]
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for b in bms:
        tmp = bpy.data.meshes.new("_t")
        b.to_mesh(tmp)
        b.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m, nt = _mat("IR_Clay")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = (0.16, 0.16, 0.155, 1)
    b.inputs["Roughness"].default_value = 0.65
    nt.links.new(b.outputs[0], out.inputs["Surface"])
    me.materials.append(m)
    ob.location = loc
    ob.rotation_euler = (0, 0, yaw)
    return ob


def camera(pos, target, lens=50.0, name="IR_Cam"):
    sc = bpy.context.scene
    cam = bpy.data.objects.get(name)
    if cam is None:
        cd = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, cd)
        sc.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.clip_start = 0.01
    cam.data.clip_end = 2000
    cam.data.sensor_width = 36
    cam.location = pos
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


def render(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW " + path)
    return path


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = {}
    for o in new:
        if o.parent is None:
            roots[o.name] = o
    return roots


def hierarchy_meshes(root):
    return [c for c in root.children_recursive if c.type == "MESH"]


def world_bounds(objs):
    bpy.context.view_layer.update()
    lo = V((1e9, 1e9, 1e9))
    hi = V((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ V(c)
            lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def sheet(paths, out, cols=2, scale=1.0):
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        a = tx.image_to_np(im)[..., :3].copy()
        bpy.data.images.remove(im)
        imgs.append(a)
    H = max(a.shape[0] for a in imgs)
    W = max(a.shape[1] for a in imgs)
    rows = (len(imgs) + cols - 1) // cols
    canvas = np.ones((rows * H, cols * W, 3)) * 0.12
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        rr = rows - 1 - r
        canvas[rr * H: rr * H + a.shape[0], c * W: c * W + a.shape[1]] = a
    if scale != 1.0:
        step = int(round(1 / scale))
        canvas = canvas[::step, ::step]
    # Blender image pixels from a PNG are already display (sRGB) values
    tx.write_png(out, np.clip(canvas, 0, 1), dither=False)
    print("PREVIEW " + out)
    return out


# =============================================================================================== item shots
LAY_FLAT = {"knife", "machete", "hatchet", "spear", "mace", "sword", "bow", "arrow", "throwing_knife", "dried_meat",
            "herbs", "berries", "bandage"}
UPRIGHT = {"water_bottle", "empty_bottle", "apple", "ration", "medkit"}


def pose_on_ground(root, name, at=(0, 0), yaw=0.0):
    """Lay held items down on their side (as loot on the ground), stand bottles/tins/bags up; rest on z = 0."""
    if name in LAY_FLAT:
        R = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(-90), 4, "Y")
    else:
        R = Matrix.Rotation(math.radians(yaw), 4, "Z")
    root.matrix_world = R
    bpy.context.view_layer.update()
    lo, hi = world_bounds(hierarchy_meshes(root))
    c = (lo + hi) / 2
    root.matrix_world = Matrix.Translation(V((at[0] - c.x, at[1] - c.y, -lo.z + 0.002))) @ R
    bpy.context.view_layer.update()
    return world_bounds(hierarchy_meshes(root))


def render_items(glb, manifest, folder, only=None):
    os.makedirs(folder, exist_ok=True)
    init_scene((1280, 720), 96)
    roots = import_glb(glb)
    forest_ground(80.0)
    fig = mannequin((0, 0, 0))
    assets = [a for a in manifest["assets"]]
    names = [a["name"] for a in assets]
    if only:
        names = [n for n in names if n in only.split(",")]
    for nm in roots:
        roots[nm].hide_render = True
        for c in roots[nm].children_recursive:
            c.hide_render = True
    fig.hide_render = True
    for nm in names:
        root = roots.get(nm)
        if root is None:
            print("WARNING asset %s missing from GLB import" % nm)
            continue
        for c in [root] + list(root.children_recursive):
            c.hide_render = False
        a = next(x for x in assets if x["name"] == nm)
        if a["kind"] == "Crate":
            shots_crate(root, nm, folder, fig)
        elif a["kind"] == "Armor":
            shots_armor(root, nm, a, folder, fig)
        else:
            shots_item(root, nm, folder, fig)
        for c in [root] + list(root.children_recursive):
            c.hide_render = True
        root.matrix_world = Matrix.Identity(4)
    fig.hide_render = True


LINEUP = {
    # name: (x, y, yaw) on the ground; crates in the back row, weapons laid along X, small loot in front
    "SupplyCrate1": (-6.2, -1.0, 0.0), "SupplyCrate2": (-1.6, -1.0, 0.0), "SupplyCrate3": (3.0, -1.0, 0.0),
    "spear": (-3.2, 3.0, 0.0), "bow": (4.2, 3.0, 0.0),
    "sword": (-6.0, 4.4, 0.0), "machete": (-2.6, 4.4, 0.0), "hatchet": (-0.1, 4.4, 0.0), "mace": (2.4, 4.4, 0.0),
    "arrow": (5.4, 4.4, 0.0),
    "knife": (-6.3, 5.6, 0.0), "throwing_knife": (-5.0, 5.6, 0.0), "water_bottle": (-3.7, 5.6, 0.0),
    "empty_bottle": (-2.85, 5.6, 0.0), "berries": (-1.9, 5.6, 0.0), "apple": (-1.15, 5.6, 0.0),
    "dried_meat": (-0.3, 5.6, 0.0), "ration": (0.6, 5.6, 0.0), "bandage": (1.4, 5.6, 0.0), "herbs": (2.3, 5.6, 0.0),
    "medkit": (3.6, 5.6, 0.0),
}


def render_lineup(glb, manifest, folder, name="_lineup.png"):
    """Every ItemsReal asset in one eye-level shot: crates in the back, two 5.5-stud mannequins wearing the vests,
    weapons and supplies on the forest floor in front."""
    init_scene((2560, 1080), 160)
    roots = import_glb(glb)
    forest_ground(140.0)
    assets = {a["name"]: a for a in manifest["assets"]}
    for nm, (x, y, yaw) in LINEUP.items():
        root = roots.get(nm)
        if root is None:
            continue
        if assets[nm]["kind"] == "Crate":
            root.matrix_world = Matrix.Translation((x, y, 0.0))
        else:
            pose_on_ground(root, nm, (x, y), yaw=yaw)
    for i, (nm, mx) in enumerate((("leather_vest", 7.6), ("padded_armor", 10.2))):
        fig = mannequin((mx, -0.6, 0), name="IR_Figure%d" % i)
        root = roots.get(nm)
        if root is not None:
            t = assets[nm]["attachments"]["Torso"]["position"]
            tb = V((t[0], -t[2], t[1]))
            root.matrix_world = Matrix.Translation(V((mx, -0.6, 3.55)) - tb)
    fig = mannequin((-9.4, 1.0, 0), name="IR_FigureScale")
    sky(30.0, 160.0)
    camera(V((1.0, 17.5, 5.2)), V((1.0, 1.6, 1.3)), lens=30)
    path = render(os.path.join(folder, name))
    return path


def contact_sheet(folder, names, out_name="_contact.png", cols=3, scale=0.5):
    """All per-asset review sheets (close + gameplay distance) tiled into one image."""
    paths = [os.path.join(folder, n + ".png") for n in names if os.path.exists(os.path.join(folder, n + ".png"))]
    if paths:
        return sheet(paths, os.path.join(folder, out_name), cols=cols, scale=scale)
    return None


def shots_item(root, nm, folder, fig):
    lo, hi = pose_on_ground(root, nm, (0, 0), yaw=198.0)       # front (+Y) toward the camera
    size = (hi - lo).length
    c = (lo + hi) / 2
    sky(36.0, 150.0)
    d = max(0.9, size * (1.9 if nm in UPRIGHT else 1.15))
    camera(c + V((d * 0.55, -d * 0.75, d * 0.62)), c, lens=50)
    p1 = render(os.path.join(folder, "_tmp_%s_close.png" % nm))
    fig.hide_render = False
    fig.location = (c.x + 2.2, c.y + 2.2, 0)
    fig.rotation_euler = (0, 0, math.radians(200))
    camera(V((c.x - 1.6, c.y - 6.0, 4.9)), V((c.x + 0.8, c.y + 1.2, 1.6)), lens=28)
    p2 = render(os.path.join(folder, "_tmp_%s_game.png" % nm))
    fig.hide_render = True
    sheet([p1, p2], os.path.join(folder, nm + ".png"), cols=2)
    for p in (p1, p2):
        os.remove(p)


def shots_crate(root, nm, folder, fig):
    root.matrix_world = Matrix.Rotation(math.radians(156), 4, "Z")    # front (+Y) toward the camera
    bpy.context.view_layer.update()
    sky(34.0, 140.0)
    camera(V((3.2, -6.0, 3.3)), V((0, 0, 0.95)), lens=40)
    p1 = render(os.path.join(folder, "_tmp_%s_close.png" % nm))
    fig.hide_render = False
    fig.location = (3.2, 0.8, 0)
    fig.rotation_euler = (0, 0, math.radians(205))
    camera(V((-3.0, -13.5, 4.9)), V((0.8, 0, 1.4)), lens=35)
    p2 = render(os.path.join(folder, "_tmp_%s_game.png" % nm))
    fig.hide_render = True
    # lid open ~100 degrees about LidHinge (back top edge, axis +X)
    lids = [c for c in root.children_recursive if c.type == "MESH" and "_Lid" in c.name]
    hinge = None
    for c in root.children_recursive:
        pass
    saved = {o.name: o.matrix_world.copy() for o in lids}
    if lids:
        lo, hi = world_bounds(lids)
        Mroot = root.matrix_world
        # hinge line in root space: back top edge y = -HD, z = lid bottom
        lz = min((Mroot.inverted() @ (o.matrix_world @ V(v.co))).z for o in lids for v in o.data.vertices)
        piv = Mroot @ V((0, -1.3, lz))
        axis = (Mroot.to_3x3() @ V((1, 0, 0))).normalized()
        Rm = Matrix.Translation(piv) @ Matrix.Rotation(math.radians(100), 4, axis) @ Matrix.Translation(-piv)
        for o in lids:
            o.matrix_world = Rm @ o.matrix_world
    camera(V((2.4, -4.6, 4.3)), V((0, 0, 0.8)), lens=35)
    p3 = render(os.path.join(folder, "_tmp_%s_open.png" % nm))
    for o in lids:
        o.matrix_world = saved[o.name]
    sheet([p1, p2, p3], os.path.join(folder, nm + ".png"), cols=3)
    for p in (p1, p2, p3):
        os.remove(p)


def shots_armor(root, nm, a, folder, fig):
    # worn on the mannequin via the Torso attachment (Roblox position -> Blender)
    t = a["attachments"]["Torso"]["position"]
    tb = V((t[0], -t[2], t[1]))
    fig.hide_render = False
    fig.location = (0, 0, 0)
    fig.rotation_euler = (0, 0, 0)
    root.matrix_world = Matrix.Translation(V((0, 0, 3.55)) - tb)
    bpy.context.view_layer.update()
    sky(36.0, 150.0)
    camera(V((2.6, 5.2, 4.6)), V((0, 0, 3.4)), lens=45)
    p1 = render(os.path.join(folder, "_tmp_%s_close.png" % nm))
    camera(V((-2.4, 11.0, 4.9)), V((0, 0, 2.9)), lens=35)
    p2 = render(os.path.join(folder, "_tmp_%s_game.png" % nm))
    fig.hide_render = True
    sheet([p1, p2], os.path.join(folder, nm + ".png"), cols=2)
    for p in (p1, p2):
        os.remove(p)
