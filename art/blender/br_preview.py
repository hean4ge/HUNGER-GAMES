"""
br_preview.py - review renders for the BuildingsReal set: Cycles (GPU when present) under Blender's built-in Sky
Texture (multiple scattering) plus a matching sun lamp, on a procedural forest-floor ground, with a 5.5-stud
reference figure. Views per asset: eye-level hero, gameplay distance (70 deg FOV like Roblox), close-up detail;
plus a lineup sheet of every asset in a row.
"""
import math
import os

import bpy
from mathutils import Vector as V

import ls_common as ls

FIG_H = 5.5
ls = ls  # re-exported for review hooks in the asset modules
EXPOSURE = -0.6
_STATE = {}


def _gpu(scene):
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
                    return kind
            except Exception:
                continue
    except Exception:
        pass
    scene.cycles.device = "CPU"
    return "CPU"


def _ground_material():
    m = bpy.data.materials.get("BRP_ForestFloor")
    if m:
        return m
    m = bpy.data.materials.new("BRP_ForestFloor")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tco = nt.nodes.new("ShaderNodeTexCoord")
    def noise(scale, detail=4.0, rough=0.6):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        nt.links.new(tco.outputs["Object"], n.inputs["Vector"])
        return n
    def ramp(inp, stops):
        r = nt.nodes.new("ShaderNodeValToRGB")
        cr = r.color_ramp
        cr.elements[0].position, cr.elements[0].color = stops[0]
        cr.elements[1].position, cr.elements[1].color = stops[1]
        for pos, col in stops[2:]:
            e = cr.elements.new(pos)
            e.color = col
        nt.links.new(inp, r.inputs["Fac"])
        return r
    def lin(r, g, b):
        return (ls.srgb_to_linear(r / 255), ls.srgb_to_linear(g / 255), ls.srgb_to_linear(b / 255), 1.0)
    big = noise(0.035, 3.0)
    mid = noise(0.45, 6.0, 0.65)
    fine = noise(7.0, 8.0, 0.7)
    # forest floor: dark humus, rust-brown needle litter, patches of moss / short grass
    soil = ramp(mid.outputs["Fac"], [(0.32, lin(60, 45, 30)), (0.72, lin(108, 80, 52)), (0.52, lin(84, 63, 42))])
    green = ramp(big.outputs["Fac"], [(0.45, lin(66, 66, 36)), (0.64, lin(78, 92, 42))])
    mixg = nt.nodes.new("ShaderNodeMix")
    mixg.data_type = "RGBA"
    mixg.blend_type = "MIX"
    gmask = ramp(big.outputs["Fac"], [(0.5, (0, 0, 0, 1)), (0.62, (1, 1, 1, 1))])
    nt.links.new(gmask.outputs["Color"], mixg.inputs["Factor"])
    nt.links.new(soil.outputs["Color"], mixg.inputs["A"])
    nt.links.new(green.outputs["Color"], mixg.inputs["B"])
    needles = ramp(fine.outputs["Fac"], [(0.5, (1, 1, 1, 1)), (0.68, lin(170, 112, 70))])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 0.55
    nt.links.new(mixg.outputs["Result"], mul.inputs["A"])
    nt.links.new(needles.outputs["Color"], mul.inputs["B"])
    nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.93
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.05
    nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def _flat_mat(name, rgb, rough=0.7):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = tuple(ls.srgb_to_linear(c / 255) for c in rgb) + (1.0,)
    b.inputs["Roughness"].default_value = rough
    return m


def make_figure():
    """Simple 5.5-stud mannequin (contender in a dull jacket), feet on z = 0, facing -Y."""
    if "_BRP_Figure" in bpy.data.objects:
        return bpy.data.objects["_BRP_Figure"]
    parts = []
    def capsule(name, p0, p1, r, mat):
        o = ls.cylinder(name, radius=r, depth=(V(p1) - V(p0)).length, segments=14)
        d = V(p1) - V(p0)
        o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        o.location = p0
        ls.bake_transform(o)
        for end in (p0, p1):
            s = ls.uvsphere(name + "_e", radius=r, segments=14, rings=8, loc=end)
            ls.bake_transform(s)
            s.data.materials.append(mat)
            parts.append(s)
        o.data.materials.append(mat)
        parts.append(o)
    jacket = _flat_mat("BRP_Jacket", (70, 78, 62), 0.85)
    pants = _flat_mat("BRP_Pants", (64, 58, 50), 0.9)
    skin = _flat_mat("BRP_Skin", (176, 134, 106), 0.55)
    boots = _flat_mat("BRP_Boots", (46, 38, 32), 0.6)
    for sx in (-1, 1):
        capsule("leg", (0.32 * sx, 0, 0.35), (0.3 * sx, 0, 2.55), 0.27, pants)
        capsule("boot", (0.32 * sx, -0.12, 0.17), (0.32 * sx, 0.08, 0.2), 0.2, boots)
        capsule("arm", (0.82 * sx, 0, 4.25), (0.92 * sx, -0.05, 2.75), 0.19, jacket)
        hand = ls.uvsphere("hand", radius=0.17, segments=12, rings=8, loc=(0.94 * sx, -0.06, 2.6))
        ls.bake_transform(hand)
        hand.data.materials.append(skin)
        parts.append(hand)
    capsule("torso", (0, 0, 2.75), (0, 0, 4.15), 0.58, jacket)
    capsule("hips", (-0.25, 0, 2.6), (0.25, 0, 2.6), 0.38, pants)
    capsule("neck", (0, 0, 4.45), (0, 0, 4.7), 0.16, skin)
    head = ls.uvsphere("head", radius=0.38, segments=16, rings=10, loc=(0, 0, 5.08), scale=(0.9, 1.0, 1.1))
    ls.bake_transform(head)
    head.data.materials.append(skin)
    parts.append(head)
    fig = ls.join(parts, "_BRP_Figure")
    mats = [jacket, pants, skin, boots]
    fig.data.materials.clear()
    for m in mats:
        fig.data.materials.append(m)
    for p in fig.data.polygons:
        p.use_smooth = True
    zmax = max(v.co.z for v in fig.data.vertices)
    s = FIG_H / zmax
    for v in fig.data.vertices:
        v.co *= s
    return fig


def setup(samples=64, res=(1280, 720)):
    scene = bpy.context.scene
    dev = _gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = True
    try:
        c.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 3
    c.transparent_max_bounces = 8
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        try:
            scene.view_settings.look = "None"
        except Exception:
            pass
    # photographic exposure: a sunlit 18 % card lands near mid-grey, weathered silver wood (~140 sRGB) stays
    # below white
    scene.view_settings.exposure = EXPOSURE
    world = bpy.data.worlds.get("BRP_Sky") or bpy.data.worlds.new("BRP_Sky")
    world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "MULTIPLE_SCATTERING"
    except Exception:
        pass
    try:
        sky.sun_disc = False
    except Exception:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    scene.world = world
    sun = bpy.data.objects.get("_BRP_Sun")
    if sun is None:
        sd = bpy.data.lights.new("_BRP_Sun", "SUN")
        sun = bpy.data.objects.new("_BRP_Sun", sd)
        scene.collection.objects.link(sun)
    sun.data.angle = math.radians(1.2)
    ground = bpy.data.objects.get("_BRP_Ground")
    if ground is None:
        ground = ls.cube("_BRP_Ground", size=(900, 900, 0.2), loc=(0, 0, -0.1))
        ground.data.materials.append(_ground_material())
    cam = bpy.data.objects.get("_BRP_Cam")
    if cam is None:
        cd = bpy.data.cameras.new("_BRP_Cam")
        cd.clip_end = 3000
        cam = bpy.data.objects.new("_BRP_Cam", cd)
        scene.collection.objects.link(cam)
    scene.camera = cam
    fig = make_figure()
    _STATE.update(scene=scene, sky=sky, bg=bg, sun=sun, ground=ground, cam=cam, fig=fig, dev=dev)
    set_sun(32, 140)
    return dev


def set_sun(elev_deg, azim_deg, strength=3.2, sky_strength=0.15):
    """azimuth: degrees from +Y toward +X (where the light comes FROM)."""
    sky, bg, sun = _STATE["sky"], _STATE["bg"], _STATE["sun"]
    e, a = math.radians(elev_deg), math.radians(azim_deg)
    try:
        sky.sun_elevation = e
        sky.sun_rotation = a
    except Exception:
        pass
    bg.inputs["Strength"].default_value = sky_strength
    d = V((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    sun.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sun.data.energy = strength
    sun.data.color = (1.0, 0.93, 0.84)


def _visible(roots, extra=()):
    scene = _STATE["scene"]
    keep = set(extra)
    for r in roots:
        keep.add(r)
        keep.update(r.children_recursive)
    for o in scene.objects:
        if o.name.startswith("_BRP_"):
            continue
        o.hide_render = o not in keep


def bounds(roots):
    meshes = []
    for r in roots:
        meshes += [c for c in r.children_recursive if c.type == "MESH"]
    return ls.world_bounds(meshes)


def shoot(path, target, cam_pos, lens_fov=70.0, fig_pos=None, fig_rot=0.0, samples=None):
    scene, cam, fig = _STATE["scene"], _STATE["cam"], _STATE["fig"]
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(lens_fov) if lens_fov < 90 else math.radians(60)
    cam.location = V(cam_pos)
    cam.rotation_euler = (V(target) - V(cam_pos)).to_track_quat("-Z", "Y").to_euler()
    if fig_pos is None:
        fig.hide_render = True
    else:
        fig.hide_render = False
        fig.location = V(fig_pos)
        fig.rotation_euler = (0, 0, fig_rot)
    if samples:
        scene.cycles.samples = samples
    # absolute path: Blender resolves a relative render path against the (unsaved) .blend's folder, i.e. the
    # drive root, not the working directory
    path = os.path.abspath(path)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def views_for(root, kind, out_dir, name, extra_views=None, samples=None):
    """Standard review views. kind: 'building' or 'prop'."""
    _visible([root])
    lo, hi = bounds([root])
    c = (lo + hi) / 2
    size = hi - lo
    span = max(size.x, size.y)
    paths = []
    os.makedirs(out_dir, exist_ok=True)
    if kind == "building":
        # hero: eye level 3/4 front-right, framed by a 50 deg lens
        d = max(span, size.z) * 1.25 + 6
        cam = V((c.x + d * 0.62, c.y + d * 0.78, 5.2))
        tgt = V((c.x, c.y, min(c.z, size.z * 0.42)))
        fig = V((c.x + size.x * 0.32, hi.y + 3.2, 0))
        set_sun(30, 75)
        paths.append(shoot(os.path.join(out_dir, name + "_hero.png"), tgt, cam, 50, fig, 0.4, samples))
        # gameplay distance: 70 deg FOV, standing 65 studs away
        cam = V((c.x - 38, c.y + 54, 5.2))
        set_sun(38, -25)
        paths.append(shoot(os.path.join(out_dir, name + "_far.png"), V((c.x, c.y, min(size.z * 0.35, 9))), cam, 70,
                           V((c.x - 6, hi.y + 4.0, 0)), 0.0, samples))
        # back three-quarter
        cam = V((c.x - d * 0.7, c.y - d * 0.72, 7.5))
        set_sun(26, 215)
        paths.append(shoot(os.path.join(out_dir, name + "_back.png"), V((c.x, c.y, size.z * 0.4)), cam, 50, None, 0,
                           samples))
    else:
        d = max(span * 1.25, 6.0) + 5.0
        cam = V((c.x + d * 0.55, c.y + d * 0.84, max(3.6, size.z * 0.9)))
        tgt = V((c.x + 0.6, c.y, max(size.z * 0.42, 1.8)))
        fig = V((hi.x + 1.8, c.y - 1.2, 0))
        set_sun(32, 70)
        paths.append(shoot(os.path.join(out_dir, name + "_hero.png"), tgt, cam, 45, fig, 0.6, samples))
        cam = V((c.x - 14, c.y + 22, 5.2))
        set_sun(38, -20)
        paths.append(shoot(os.path.join(out_dir, name + "_far.png"), V((c.x, c.y, size.z * 0.4)), cam, 70,
                           V((hi.x + 1.6, c.y + 0.6, 0)), 0.6, samples))
        # close-up: what a crouching / standing player sees at arm's length (texel density check)
        dc = max(span, size.z) * 0.9 + 1.2
        cam = V((c.x - dc * 0.5, c.y + dc * 0.85, max(size.z * 0.85, 1.4) + dc * 0.35))
        set_sun(30, 15)
        paths.append(shoot(os.path.join(out_dir, name + "_close.png"), V((c.x, c.y, size.z * 0.45)), cam, 40, None, 0,
                           samples))
    scene = _STATE["scene"]
    for view in (extra_views or []):
        vname, cam, tgt, fov, sun = view[:5]
        ev = view[5] if len(view) > 5 else 0.0
        lights = view[6] if len(view) > 6 else []
        if sun:
            set_sun(*sun)
        scene.view_settings.exposure = EXPOSURE + ev
        made = []
        for (pos, watts, col) in lights:
            ld = bpy.data.lights.new("_BRP_Fill", "POINT")
            ld.energy = watts
            ld.color = col
            ld.shadow_soft_size = 0.4
            lo_ = bpy.data.objects.new("_BRP_Fill", ld)
            lo_.location = V(pos)
            scene.collection.objects.link(lo_)
            made.append(lo_)
        fig = V(view[7]) if len(view) > 7 else None
        paths.append(shoot(os.path.join(out_dir, name + "_" + vname + ".png"), V(tgt), V(cam), fov, fig, 0.3, samples))
        for lo_ in made:
            bpy.data.objects.remove(lo_, do_unlink=True)
        scene.view_settings.exposure = EXPOSURE
    return paths


def lineup(roots, out_path, gap=6.0, samples=None, elev=9.0, res=(2400, 900), row_width=None, row_gap=10.0,
           rows=None):
    """All given assets side by side along X (temporarily moved), with the reference figure at the left end.
    row_width: wrap into rows (later rows further back) so small props stay readable; rows: explicit list of root
    lists (front row first) instead of wrapping."""
    scene = _STATE["scene"]
    old = [r.location.copy() for r in roots]
    if rows:
        rows = [[(r, *bounds([r])) for r in row] for row in rows if row]
    else:
        rows, cur, wsum = [], [], 0.0
        for r in roots:
            lo, hi = bounds([r])
            w = hi.x - lo.x
            if row_width and cur and wsum + w > row_width:
                rows.append(cur)
                cur, wsum = [], 0.0
            cur.append((r, lo, hi))
            wsum += w + gap
        rows.append(cur)
    y = 0.0
    left0 = None
    for row in rows:
        tot = sum(hi.x - lo.x for (_, lo, hi) in row) + gap * (len(row) - 1)
        x = -tot / 2
        if left0 is None:
            left0 = x
        depth = max(hi.y - lo.y for (_, lo, hi) in row)
        for (r, lo, hi) in row:
            r.location = (x - lo.x, y - (lo.y + hi.y) / 2, 0)
            x += hi.x - lo.x + gap
        y -= depth + row_gap
    bpy.context.view_layer.update()
    _visible(roots)
    lo, hi = bounds(roots)
    c = (lo + hi) / 2
    w = hi.x - lo.x
    rx, ry = scene.render.resolution_x, scene.render.resolution_y
    scene.render.resolution_x, scene.render.resolution_y = res
    cam = _STATE["cam"]
    cam.data.sensor_fit = "HORIZONTAL"
    fov = math.radians(34)
    cam.data.angle = fov
    dist = (w * 0.55) / math.tan(fov / 2) + (hi.y - lo.y) * 0.5
    e = math.radians(elev)
    tz = max(hi.z * 0.42, 2.0)
    cam.location = V((c.x, hi.y + dist * math.cos(e), tz + dist * math.sin(e)))
    cam.rotation_euler = (V((c.x, c.y, tz)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    fig = _STATE["fig"]
    fig.hide_render = False
    fig.location = (left0 - 3.0, hi.y - 1.5, 0)
    set_sun(34, 40)
    if samples:
        scene.cycles.samples = samples
    out_path = os.path.abspath(out_path)
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    for r, p in zip(roots, old):
        r.location = p
    bpy.context.view_layer.update()
    return out_path
