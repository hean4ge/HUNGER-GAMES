"""
lineup.py - art-direction review renders made from the EXPORTED GLBs (Blender 5.3, headless).

    blender --background --factory-startup --python lineup.py -- <out_dir> <preview_dir> [Category,...|none] [scale]

Writes
  <preview_dir>/<Category>/_lineup.png  every asset of the category in rows (tallest first), labelled, each row led
                                        by a 5.5-stud reference figure (or a 1-stud cube for hand-sized rows)
  <preview_dir>/_scale_lineup.png       representatives of every category next to the figure: world scale
                                        (Spire, trees, cliffs, buildings), human scale (doors, cover, props) and
                                        hand scale (weapons, food, armour) with a posed viewmodel arm
  <preview_dir>/_grip_check.png         R_HandGrip holding the sword, aligned purely from the two manifests'
                                        Grip attachments (look/up/position) - checks the Items <-> Arms contract
Reading the GLBs (not the generator scenes) also checks the export itself: axes, pivots, materials, shading.
Pass "none" as the category list to render only the scale lineup and grip check, and omit "scale" to skip them.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGS[0]
PREVIEW_DIR = ARGS[1]
ALL = ["Foliage", "Rocks", "Landmarks", "Buildings", "Props", "Items", "Arms"]
CATS = ALL if len(ARGS) < 3 or not ARGS[2] else ([] if ARGS[2] == "none" else ARGS[2].split(","))
DO_SCALE = len(ARGS) < 3 or (len(ARGS) > 3 and ARGS[3] == "scale") or not ARGS[2]

AZ, EL = 24.0, 11.0            # camera azimuth from the asset front (+Y) and elevation, degrees
FIG_H = 5.5                    # player height in studs
PX_W = 1800                    # width of every row image


# ----------------------------------------------------------------------------------------------- scene helpers
def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def flat_mat(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    v = [lin(x / 255.0) for x in rgb]
    m.diffuse_color = (v[0], v[1], v[2], 1.0)
    m.roughness, m.metallic = 0.8, 0.0
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light, sh.color_type = "STUDIO", "MATERIAL"
    sh.show_cavity, sh.cavity_type = True, "BOTH"
    sh.show_shadows, sh.shadow_intensity = True, 0.45
    scene.display.shadow_shift = 0.3
    try:
        sh.show_specular_highlight = True
    except AttributeError:
        pass
    world = bpy.data.worlds.new("LineupWorld")
    world.color = (0.62, 0.7, 0.76)
    scene.world = world
    scene.render.film_transparent = False


def import_glb(category):
    path = os.path.join(OUT_DIR, category + ".glb")
    with open(os.path.join(OUT_DIR, category + ".manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for m in bpy.data.materials:   # Workbench MATERIAL mode shows diffuse_color: copy the glTF base colour
        if m.use_nodes and m.node_tree and not m.get("lineup_done"):
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf:
                c = bsdf.inputs["Base Color"].default_value
                m.diffuse_color = (c[0], c[1], c[2], 1.0)
                m.metallic = min(bsdf.inputs["Metallic"].default_value, 0.3)   # studio metals read black otherwise
                m.roughness = max(bsdf.inputs["Roughness"].default_value, 0.4)
            m["lineup_done"] = True
    roots = {}
    for a in manifest["assets"]:
        obj = next((o for o in new if o.name == a["name"]), None)
        if obj is None:
            raise RuntimeError("asset %s not found in %s" % (a["name"], path))
        roots[a["name"]] = obj
    for o in new:   # detach the assets from any importer-added parent so matrix_world is ours to set
        if o.name in roots and o.parent is not None:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
    return manifest, roots


def meshes_of(root):
    return [o for o in [root] + list(root.children_recursive) if o.type == "MESH"]


def bounds(objs):
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for b in (o.matrix_world @ Vector(c) for c in o.bound_box):
            lo = Vector((min(lo.x, b.x), min(lo.y, b.y), min(lo.z, b.z)))
            hi = Vector((max(hi.x, b.x), max(hi.y, b.y), max(hi.z, b.z)))
    return lo, hi


def corners(lo, hi):
    return [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]


def box(name, lo, hi, mat):
    me = bpy.data.meshes.new(name)
    v = [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    me.from_pydata(v, [], f)
    me.update()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def figure(x=0.0, y=0.0, right_arm=True):
    """5.5-stud reference player (blocky R15-like proportions), facing +Y, feet on z = 0. Returns its objects."""
    m = flat_mat("_figure", (84, 112, 158))
    parts = [box("_fig_legL", (-0.95, -0.45, 0.0), (-0.05, 0.45, 2.55), m),
             box("_fig_legR", (0.05, -0.45, 0.0), (0.95, 0.45, 2.55), m),
             box("_fig_torso", (-1.0, -0.5, 2.55), (1.0, 0.5, 4.6), m),
             box("_fig_armL", (-1.85, -0.42, 2.45), (-1.05, 0.42, 4.55), m),
             box("_fig_head", (-0.55, -0.55, 4.65), (0.55, 0.55, FIG_H), m)]
    if right_arm:
        parts.append(box("_fig_armR", (1.05, -0.42, 2.45), (1.85, 0.42, 4.55), m))
    for p in parts:
        p.location = (x, y, 0.0)
    return parts


def unit_cube(x=0.0):
    c = box("_unit_cube", (-0.5, -0.5, 0.0), (0.5, 0.5, 1.0), flat_mat("_figure", (84, 112, 158)))
    c.location.x = x
    return [c]


def label(text, size):
    cu = bpy.data.curves.new("_lbl", type="FONT")
    cu.body = text
    cu.size = size
    cu.align_x, cu.align_y = "CENTER", "BOTTOM"
    cu.extrude = 0.0
    cu.materials.append(flat_mat("_label", (240, 240, 232)))
    o = bpy.data.objects.new("_lbl_" + text, cu)
    bpy.context.scene.collection.objects.link(o)
    return o


def ground(size=4000.0):
    me = bpy.data.meshes.new("_ground")
    s = size / 2
    me.from_pydata([(-s, -s, -0.01), (s, -s, -0.01), (s, s, -0.01), (-s, s, -0.01)], [], [(0, 1, 2, 3)])
    me.update()
    me.materials.append(flat_mat("_ground", (176, 178, 168)))
    o = bpy.data.objects.new("_ground", me)
    bpy.context.scene.collection.objects.link(o)
    return o


def camera_basis():
    a, e = math.radians(AZ), math.radians(EL)
    d = Vector((math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)))   # toward the camera
    f = -d
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f).normalized()
    return d, r, u


def move_to(root, delta):
    root.matrix_world = Matrix.Translation(delta) @ root.matrix_world


# ----------------------------------------------------------------------------------------------- one row
def render_row(items, path, ref="figure", label_names=True):
    """items: list of (name, [root objects]). Lays them out left to right with the reference first, frames an
    orthographic camera on the row and renders it. Returns the image path."""
    d, R, U = camera_basis()
    toward = Vector((d.x, d.y, 0.0)).normalized()          # horizontal direction toward the camera
    groups = []
    for name, roots in items:
        objs = []
        for r in roots:
            objs += meshes_of(r) if r.type != "MESH" or r.children else [r]
        lo, hi = bounds(objs)
        c = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, 0.0))
        for r in roots:
            move_to(r, -c)                                  # centre the footprint on the origin
        if lo.z < -0.05:                                    # hand-held items (grip at origin): rest on the ground
            for r in roots:
                move_to(r, Vector((0, 0, -lo.z)))
        lo, hi = bounds(objs)
        groups.append((name, roots, objs, lo, hi))
    heights = [g[4].z - g[3].z for g in groups]
    row_h = max(heights + [FIG_H if ref == "figure" else 1.0])
    gap = max(0.35, 0.09 * row_h)
    ref_objs = figure(right_arm=True) if ref == "figure" else unit_cube()
    rlo, rhi = bounds(ref_objs)
    start = min(c.dot(R) for c in corners(rlo, rhi))
    cursor = max(c.dot(R) for c in corners(rlo, rhi)) + gap * 1.4
    placed = list(ref_objs)
    helpers = list(ref_objs)          # objects this function created (removed again at the end)
    for name, roots, objs, lo, hi in groups:
        ps = [c.dot(R) for c in corners(lo, hi)]
        t = cursor - min(ps)
        for r in roots:
            move_to(r, R * t)
        cursor = t + max(ps) + gap
        placed += objs
    lsize = max(0.08, min(max(cursor - start, row_h * 2.5) / 110.0, 4.0))   # ~1% of the frame width
    for name, roots, objs, lo, hi in groups if label_names else ():
        lo2, hi2 = bounds(objs)
        front = max(c.dot(toward) for c in corners(lo2, hi2))
        lb = label(name, lsize)
        centre = (lo2 + hi2) / 2
        lb.location = Vector((centre.x, centre.y, 0.0)) + toward * (front - centre.dot(toward) + lsize * 7.5)
        lb.rotation_euler = Matrix((R, U, d)).transposed().to_euler()
        placed.append(lb)
        helpers.append(lb)
    g = ground()
    # frame: projected extents of everything but the ground
    bpy.context.view_layer.update()
    pts = []
    for o in placed:
        lo, hi = bounds([o])
        pts += corners(lo, hi)
    r0, r1 = min(p.dot(R) for p in pts), max(p.dot(R) for p in pts)
    u0, u1 = min(p.dot(U) for p in pts), max(p.dot(U) for p in pts)
    span_r, span_u = (r1 - r0) * 1.04, (u1 - u0) * 1.12
    res_y = int(round(PX_W * span_u / span_r))
    scale = span_r
    if res_y > 1100:
        res_y = 1100
        scale = span_u * PX_W / 1100.0
    res_y = max(res_y, 220)
    cam_data = bpy.data.cameras.new("_lineup_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = scale
    cam_data.clip_start, cam_data.clip_end = 0.1, 20000
    cam = bpy.data.objects.new("_lineup_cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    centre = R * ((r0 + r1) / 2) + U * ((u0 + u1) / 2)
    cam.matrix_world = Matrix.Translation(centre + d * 3000.0) @ Matrix((R, U, d)).transposed().to_4x4()
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = PX_W, res_y
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    # clean up this row's helpers (reference, labels, camera, ground); asset objects stay where they were put
    for o in [cam, g] + helpers:
        bpy.data.objects.remove(o, do_unlink=True)
    return path


def stack(paths, out, pad=6):
    """Stack row images vertically (white separators) into one PNG and delete the row files."""
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        imgs.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(im)
    W = max(a.shape[1] for a in imgs)
    H = sum(a.shape[0] for a in imgs) + pad * (len(imgs) - 1)
    sheet = np.ones((H, W, 4), dtype=np.float32)
    y = H
    for a in imgs:                      # Blender pixel rows run bottom-up: first row goes on top
        h, w = a.shape[:2]
        sheet[y - h:y, 0:w] = a
        y -= h + pad
    img = bpy.data.images.new("_sheet", W, H, alpha=True)
    img.pixels = sheet.ravel()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    for p in paths:
        os.remove(p)
    return out


def remove_tree(root):
    for o in list(root.children_recursive) + [root]:
        bpy.data.objects.remove(o, do_unlink=True)


# ----------------------------------------------------------------------------------------------- per category
def category_lineup(cat):
    reset()
    manifest, roots = import_glb(cat)
    sizes = {a["name"]: a["size"] for a in manifest["assets"]}
    order = sorted(roots, key=lambda n: -sizes[n][1])
    rows, cur = [], []
    for n in order:
        h, w = sizes[n][1], max(sizes[n][0], sizes[n][2])
        if cur:
            top = sizes[cur[0]][1]
            width = sum(max(sizes[m][0], sizes[m][2]) for m in cur) + w
            if h < top / 3.2 or width > max(top, 2.0) * 9.0:
                rows.append(cur)
                cur = []
        cur.append(n)
    if cur:
        if rows and len(cur) <= 2:      # a couple of leftovers join the previous row instead of a near-empty row
            rows[-1] += cur
        else:
            rows.append(cur)
    folder = os.path.join(PREVIEW_DIR, cat)
    os.makedirs(folder, exist_ok=True)
    paths = []
    for i, names in enumerate(rows):
        for n in roots:                           # only this row is visible
            for o in [roots[n]] + list(roots[n].children_recursive):
                o.hide_render = n not in names
        ref = "figure" if sizes[names[0]][1] >= FIG_H * 0.35 else "cube"
        paths.append(render_row([(n, [roots[n]]) for n in names], os.path.join(folder, "_lineup_row%d.png" % i), ref))
    out = stack(paths, os.path.join(folder, "_lineup.png"))
    print("LINEUP " + out)


# ----------------------------------------------------------------------------------------------- scale lineup
def att_matrix(att):
    """Attachment frame in Blender space (columns: look, up, look x up; translation = position)."""
    def b(v):
        return Vector((v[0], -v[2], v[1]))        # Roblox (x, y, z) -> Blender (x, -z, y)
    look, up = b(att["look"]).normalized(), b(att["up"]).normalized()
    m = Matrix((look, up, look.cross(up))).transposed().to_4x4()
    m.translation = b(att["position"])
    return m


def scale_lineup():
    reset()
    mans, roots = {}, {}
    for cat in ALL:
        m, r = import_glb(cat)
        mans[cat] = m
        roots.update(r)
    ents = {a["name"]: a for m in mans.values() for a in m["assets"]}
    for n in roots:
        for o in [roots[n]] + list(roots[n].children_recursive):
            o.hide_render = True

    def show(names, on=True):
        for n in names:
            for o in [roots[n]] + list(roots[n].children_recursive):
                o.hide_render = not on

    world = ["Spire", "PineB", "PineA", "OakB", "BirchA", "DeadTreeA", "Watchtower", "CliffChunkB", "RockArch",
             "RangerCabin", "RiverMill"]
    human = ["FishingShack", "LobbyGate", "Plinth", "Tent", "BushA", "BoulderC", "Barrel", "SupplyCrate1", "Bench",
             "FenceSegment", "Stump"]
    hand = ["spear", "bow", "sword", "machete", "mace", "hatchet", "knife", "arrow", "water_bottle", "medkit",
            "apple", "leather_vest"]
    paths = []
    show(world)
    paths.append(render_row([(n, [roots[n]]) for n in world], os.path.join(PREVIEW_DIR, "_scale_row0.png")))
    show(world, False)
    show(human)
    paths.append(render_row([(n, [roots[n]]) for n in human], os.path.join(PREVIEW_DIR, "_scale_row1.png")))
    show(human, False)

    # hand-scale row: the figure carries the exported viewmodel arm (world scale) hanging at its side, the hand
    # holding the sword through the two Grip attachments; the other items stand beside it
    arm = ["R_UpperArm", "R_Forearm", "R_HandGrip"]
    S = Vector((1.45, 0.0, 4.55))                                  # right shoulder of the figure
    hang = Matrix(((0, 1, 0), (1, 0, 0), (0, 0, -1))).to_4x4()     # bone +Z -> down, thumb +X -> forward
    up_arm = Matrix.Translation(S) @ hang
    elbow = up_arm @ att_matrix(ents["R_UpperArm"]["attachments"]["Elbow"]).translation
    fore = Matrix.Translation(elbow) @ hang
    wrist = fore @ att_matrix(ents["R_Forearm"]["attachments"]["Wrist"]).translation
    handm = Matrix.Translation(wrist) @ hang
    for n, mw in zip(arm, (up_arm, fore, handm)):
        roots[n].matrix_world = mw
    grip_world = handm @ att_matrix(ents["R_HandGrip"]["attachments"]["Grip"])
    sword_hold = bpy.data.objects.new("_sword_holder", None)
    bpy.context.scene.collection.objects.link(sword_hold)
    # a second sword instance for the held pose (the standing one stays in the row)
    held = []
    for ch in roots["sword"].children:
        o = bpy.data.objects.new("_held_" + ch.name, ch.data)
        bpy.context.scene.collection.objects.link(o)
        o.parent = sword_hold
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = roots["sword"].matrix_world.inverted() @ ch.matrix_world
        held.append(o)
    sword_hold.matrix_world = grip_world @ att_matrix(ents["sword"]["attachments"]["Grip"]).inverted()
    show(hand + arm)
    fig_parts = figure(right_arm=False)
    holder = bpy.data.objects.new("_fig_holder", None)
    bpy.context.scene.collection.objects.link(holder)
    for o in fig_parts + [roots[n] for n in arm] + [sword_hold]:
        mw = o.matrix_world.copy()
        o.parent = holder
        o.matrix_parent_inverse = holder.matrix_world.inverted()
        o.matrix_world = mw
    items = [("player + viewmodel arm (world scale)", [holder])] + [(n, [roots[n]]) for n in hand]
    paths.append(render_row(items, os.path.join(PREVIEW_DIR, "_scale_row2.png"), ref="cube"))
    out = stack(paths, os.path.join(PREVIEW_DIR, "_scale_lineup.png"))
    print("LINEUP " + out)

    # grip close-up: the held sword in the hand, from the thumb side and slightly above
    scene = bpy.context.scene
    for o in scene.objects:
        o.hide_render = True
    vis = meshes_of(roots["R_HandGrip"]) + held
    for o in vis:
        o.hide_render = False
    lo, hi = bounds(meshes_of(roots["R_HandGrip"]))
    c = (lo + hi) / 2
    cam_data = bpy.data.cameras.new("_grip_cam")
    cam_data.lens = 50
    cam_data.clip_start = 0.01
    cam = bpy.data.objects.new("_grip_cam", cam_data)
    scene.collection.objects.link(cam)
    view = Vector((0.9, 1.1, 0.55)).normalized()
    pos = c + view * 2.2
    f = (c - pos).normalized()
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f)
    cam.matrix_world = Matrix.Translation(pos) @ Matrix((r, u, -f)).transposed().to_4x4()
    scene.camera = cam
    scene.display.shading.show_shadows = False
    scene.render.resolution_x, scene.render.resolution_y = 900, 640
    scene.render.filepath = os.path.join(PREVIEW_DIR, "_grip_check.png")
    bpy.ops.render.render(write_still=True)
    print("LINEUP " + scene.render.filepath)


for cat in CATS:
    category_lineup(cat)
if DO_SCALE:
    scale_lineup()
