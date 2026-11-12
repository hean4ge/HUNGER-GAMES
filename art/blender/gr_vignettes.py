"""
gr_vignettes.py - GroundReal review: per-asset close/mid shots, the lineup sheet and three vignettes, all rendered
from the exported GLB (see gr_preview.py for the scene, materials and figure).

The vignettes also import the tree artist's exported TreesReal.glb (read-only; used when it sits next to
GroundReal.glb) so ground flora, rocks and trees are judged together for palette and texel density. Without it a
bark-strip log from the Shrubs atlas stands in for the fallen log.
  _vignette_forest.png  sloped forest floor: ferns, grass, moss, mushrooms, rocks, a fallen log, trunks, dappled sun
  _vignette_meadow.png  meadow: tall grass, flowers, bushes, berry bush, sapling, boulders, forest edge
  _vignette_cliffs.png  cliff foot: cliff faces, cave mouth, scree, boulders, ferns
"""
import json
import math
import os

import bpy
import numpy as np

import gr_preview as pv
import tex_ground as tg

ROWS = [
    ("Cliffs and cave", ["CliffFaceC", "CliffFaceB", "CliffFaceA", "CaveMouth", "RockOutcrop"]),
    ("Rocks", ["BoulderD", "BoulderC", "RockFlat", "ScreeA", "BoulderB", "RiverStones", "BoulderA"]),
    ("Shrubs, sapling, reeds, ferns", ["SaplingBroadleaf", "BushA", "BerryBush", "BushB", "ReedsA", "FernA", "FernB"]),
    ("Grasses, flowers, floor", ["GrassTallA", "GrassTallB", "GrassForest", "FlowersA", "FlowersB", "MushroomsA",
                                 "MossPatch"]),
]
SHOT_SUN = (36.0, 40.0)          # elevation, bearing for the per-asset shots and the lineup


def _hide_all(roots):
    for r in roots.values():
        r.hide_render = True
        for c in r.children_recursive:
            c.hide_render = True


def clear_instances():
    for o in list(bpy.data.objects):
        if o.get("gr_inst"):
            bpy.data.objects.remove(o, do_unlink=True)


def place(roots, name, loc, rot=0.0, scale=1.0):
    if name not in roots:
        return None
    r = pv.instance(roots[name], loc, rot, scale, name + "_v")
    r["gr_inst"] = True
    for c in r.children:
        c["gr_inst"] = True
    return r


def text_label(text, loc, size=0.9, name=None):
    cu = bpy.data.curves.new(name or ("lbl_" + text), "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new(name or ("lbl_" + text), cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (math.radians(90), 0, math.radians(180))
    m = bpy.data.materials.get("GR_Label") or bpy.data.materials.new("GR_Label")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.9, 0.9, 0.88, 1)
    b.inputs["Emission Color"].default_value = (1, 1, 1, 1)
    b.inputs["Emission Strength"].default_value = 0.6
    cu.materials.append(m)
    ob["gr_inst"] = True
    return ob


# =============================================================================================== trees (read-only)
def cull_backfaces(m):
    """Roblox renders MeshParts single-sided; Cycles would shade the cards' flipped back faces instead."""
    if not m or not m.use_nodes or m.get("gr_culled"):
        return
    nt = m.node_tree
    bs = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"]
    if not bs:
        return
    b = bs[0]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sub = nt.nodes.new("ShaderNodeMath")
    sub.operation = "SUBTRACT"
    sub.inputs[0].default_value = 1.0
    nt.links.new(geo.outputs["Backfacing"], sub.inputs[1])
    a_in = b.inputs["Alpha"]
    if a_in.is_linked:
        src = a_in.links[0].from_socket
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(src, mul.inputs[0])
        nt.links.new(sub.outputs[0], mul.inputs[1])
        nt.links.new(mul.outputs[0], a_in)
    else:
        nt.links.new(sub.outputs[0], a_in)
    m["gr_culled"] = True


def load_trees(glb_dir, log=print):
    glb = os.path.join(glb_dir, "TreesReal.glb")
    man = os.path.join(glb_dir, "TreesReal.manifest.json")
    if not (os.path.exists(glb) and os.path.exists(man)):
        log("TREES not found next to the GLB: vignettes use the stand-in log")
        return {}
    try:
        with open(man, encoding="utf-8") as f:
            manifest = json.load(f)
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=glb)
    except Exception as e:  # the tree artist may be re-exporting right now
        log("TREES not loaded (%s): vignettes use the stand-in log" % e)
        return {}
    new = [o for o in bpy.data.objects if o not in before]
    by_name = {o.name: o for o in new}
    roots = {}
    for a in manifest.get("assets", []):
        r = by_name.get(a["name"])
        if r is None:
            continue
        r.location.x -= a["origin"][0]
        roots[a["name"]] = r
    for o in new:
        o.hide_render = True
        if o.type == "MESH":
            for m in o.data.materials:
                cull_backfaces(m)
    log("TREES %d TreesReal assets loaded for the vignettes" % len(roots))
    return roots


# =============================================================================================== lineup
def lineup(scene, roots, out_dir, log=print):
    paths = []
    pv.set_sun(scene, *SHOT_SUN)
    for title, names in ROWS:
        names = [n for n in names if n in roots]
        if not names:
            continue
        clear_instances()
        _hide_all(roots)
        # the camera looks from +Y (asset fronts) toward -Y, so screen-right is -X: lay the row out toward -X
        x = 0.0
        fig = pv.figure(scene)
        fig.hide_render = False
        fig.location = (x - 1.2, 0, 0)
        fig.rotation_euler = (0, 0, math.radians(180))
        x -= 3.0
        hmax, dmax = 5.5, 2.0
        for n in names:
            lo, hi = pv.bounds(roots[n])
            w = hi.x - lo.x
            x -= 1.5
            place(roots, n, (x - hi.x, -(lo.y + hi.y) / 2, 0), 0.0)
            text_label(n, (x - w / 2, max(hi.y - lo.y, 2) / 2 + 1.5, 0.05), size=max(0.8, min(2.4, w * 0.12)))
            x -= w + 1.5
            hmax = max(hmax, hi.z)
            dmax = max(dmax, hi.y - lo.y)
        width = -x
        cx = x / 2
        el = math.radians(14.0)
        ortho = width * 1.04
        # screen-up is (0, -sin e, cos e): tallest top s_max, labels on the ground in front s_min
        s_max = (hmax + 1.0) * math.cos(el) + dmax / 2 * math.sin(el)
        s_min = -(dmax / 2 + 3.5) * math.sin(el) - 0.6
        vert = s_max - s_min
        res_y = int(min(1100, max(280, 2400 * vert / ortho)))
        ortho = max(ortho, vert * 2400 / res_y)
        tz = (s_max + s_min) / 2 / math.cos(el)
        tgt = (cx, 0.0, tz)
        cam = pv.camera(scene, (cx, 400.0 * math.cos(el), tz + 400.0 * math.sin(el)), tgt, 50.0)
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
        cam.data.clip_end = 1000.0
        scene.render.resolution_x, scene.render.resolution_y = 2400, res_y
        p = pv.render(scene, os.path.join(out_dir, "_lineup_row_%d.png" % len(paths)))
        cam.data.type = "PERSP"
        paths.append(p)
        log("LINEUP row %s" % title)
    imgs = [tg.load_image_np(p, "Non-Color")[..., :3] for p in paths]
    sep = np.ones((8, imgs[0].shape[1], 3)) * 0.95
    stack = []
    for im in reversed(imgs):           # row 0 = bottom in numpy order, so put the first row last
        stack += [im, sep]
    sheet = np.concatenate(stack[:-1], 0)
    out = tg.write_png(os.path.join(out_dir, "_lineup.png"), sheet, quantize=False)
    for p in paths:
        os.remove(p)
    clear_instances()
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    return out


# =============================================================================================== vignettes
def _stand_in_log(roots):
    """Fallen log stand-in (bark strip of the Shrubs atlas) when TreesReal is not available."""
    mat = bpy.data.materials.get("PV_Shrubs")
    if mat is None:
        return None
    import gr_flora
    import tempfile
    path = os.path.join(tempfile.gettempdir(), "GroundReal_build", "GR_Atlas_Layout.json")
    with open(path, encoding="utf-8") as f:
        layout = json.load(f)
    p = gr_flora.Part(layout["Shrubs"]["slots"])
    pts = [np.array([0.0, 0.0, z]) for z in np.linspace(-7, 7, 9)]
    p.tube(pts, 0.75, 12, "bark", mode="repeat", seg_studs=3.9)
    ob = p.build("GR_VignetteLog")
    ob.data.materials.append(mat)
    ob["gr_inst"] = True
    return ob


def _flatten_ground(g):
    co = tg.vertex_coords(g.data)
    co[:, 2] = 0.0
    g.data.vertices.foreach_set("co", co.astype(np.float32).ravel())
    g.data.update()
    g.data.materials.clear()
    g.data.materials.append(pv.ground_material("neutral"))


def forest_vignette(scene, roots, trees, out_dir, log=print):
    clear_instances()
    _hide_all(roots)
    pn = tg.Perlin(7)

    def height(x, y):
        return 0.16 * y + 0.9 * pn.fbm(np.stack([x * 0.06, y * 0.06, np.zeros_like(x)], -1), 1.0, 3)
    g = pv.ground(scene, 160, "soil", slope=lambda x, y: height(x, y))
    rng = np.random.RandomState(5)

    def Z(x, y):
        return float(height(np.array([x]), np.array([y]))[0])

    def P(x, y, name, rot=None, s=1.0, src=None):
        return place(src or roots, name, (x, y, Z(x, y)), rng.uniform(0, 6.28) if rot is None else rot, s)
    # foreground (y 0-6): low cover
    P(-3.2, 2.2, "FernB", 0.4, 0.95)
    P(2.6, 1.6, "MushroomsA", 0.9)
    P(-0.6, 4.0, "MossPatch", 0.8)
    P(4.6, 4.4, "FernA", None, 0.9)
    # mid ground (y 6-16): log, boulders, ferns, outcrop
    P(9.0, 11.0, "BoulderC", 2.3)
    P(-9.5, 8.5, "BoulderB", 0.3)
    P(-11.0, 17.0, "RockOutcrop", math.pi + 0.35)
    P(-8.6, 15.2, "MossPatch", 2.0, 0.9)
    for (x, y) in [(-5.5, 11.5), (2.5, 13.5), (11.5, 16.0), (-14.0, 11.0), (6.0, 7.5), (-2.0, 17.5)]:
        P(x, y, "FernA", None, rng.uniform(0.85, 1.1))
    for (x, y) in [(-6.5, 6.0), (0.5, 9.5), (7.0, 14.5), (13.0, 9.0), (-3.0, 14.0)]:
        P(x, y, "FernB", None, rng.uniform(0.9, 1.1))
    # background (y 16-40): shrubs, saplings, trees
    P(13.5, 22.0, "BushA", 0.0)
    P(-16.0, 24.0, "SaplingBroadleaf", 0.0)
    P(4.5, 25.0, "SaplingBroadleaf", 2.0, 1.1)
    P(-5.5, 28.0, "BushB", 1.0)
    for i in range(110):
        P(rng.uniform(-18, 18), rng.uniform(0.5, 30), "GrassForest", None, rng.uniform(0.75, 1.1))
    log_ob = None
    if "FallenLogA" in trees:
        P(-1.5, 10.0, "FallenLogA", math.radians(22), 1.0, trees)
        P(8.0, 19.0, "StumpA", 0.4, 1.0, trees)
        P(-15.0, 30.0, "SpruceA", 0.3, 1.0, trees)
        P(11.0, 33.0, "FirA", 1.1, 1.0, trees)
        P(-3.0, 40.0, "BirchA", 2.2, 1.0, trees)
        P(22.0, 26.0, "SpruceB", 2.9, 1.0, trees)
        P(-18.0, -22.0, "SpruceB", 0.0, 1.0, trees)       # behind the camera: dappled shade on the floor
    else:
        log_ob = _stand_in_log(roots)
        if log_ob is not None:
            log_ob.location = (-1.5, 10.0, Z(-1.5, 10.0) + 0.55)
            log_ob.rotation_euler = (0, math.radians(86), math.radians(22))
    fig = pv.figure(scene)
    fig.hide_render = False
    fig.location = (4.5, 12.0, Z(4.5, 12.0))
    fig.rotation_euler = (0, 0, math.radians(195))
    pv.set_sun(scene, 34.0, 205.0)
    cz = Z(0.0, -9.0)
    pv.camera(scene, (0.5, -9.0, cz + pv.EYE), (0.0, 14.0, cz + 3.4), 24.0)
    p = pv.render(scene, os.path.join(out_dir, "_vignette_forest.png"))
    log("VIGNETTE forest")
    clear_instances()                    # also removes the stand-in log (tagged gr_inst)
    _flatten_ground(g)
    return p


def meadow_vignette(scene, roots, trees, out_dir, log=print):
    clear_instances()
    _hide_all(roots)
    pn = tg.Perlin(9)

    def height(x, y):
        return 0.6 * pn.fbm(np.stack([x * 0.04, y * 0.04, np.zeros_like(x)], -1), 1.0, 3)
    g = pv.ground(scene, 200, "meadow", slope=lambda x, y: height(x, y))
    rng = np.random.RandomState(11)

    def Z(x, y):
        return float(height(np.array([x]), np.array([y]))[0])

    def P(x, y, name, rot=None, s=1.0, src=None):
        return place(src or roots, name, (x, y, Z(x, y)), rng.uniform(0, 6.28) if rot is None else rot, s)
    for i in range(90):
        x, y = rng.uniform(-22, 22), rng.uniform(1, 44)
        P(x, y, "GrassTallA" if rng.random_sample() < 0.55 else "GrassTallB", None, rng.uniform(0.85, 1.1))
    for i in range(110):
        P(rng.uniform(-20, 20), rng.uniform(0.5, 32), "GrassForest", None, rng.uniform(0.8, 1.2))
    for i in range(18):
        P(rng.uniform(-13, 13), rng.uniform(1, 20), "FlowersA" if i % 2 else "FlowersB")
    P(-9.0, 16.0, "BushB", 0.5)
    P(10.0, 22.0, "BerryBush", 1.0)
    P(-15.0, 30.0, "SaplingBroadleaf", 0.0)
    P(14.0, 34.0, "SaplingBroadleaf", 1.3, 1.15)
    P(4.0, 9.0, "BoulderB", 0.2)
    P(6.5, 11.0, "BoulderA", 1.0)
    P(-5.0, 26.0, "BoulderD", 0.7)
    P(-3.5, 7.0, "RockFlat", 0.3)
    P(18.0, 12.0, "BushA", 0.3)
    if trees:
        P(-26.0, 52.0, "OakA", 0.6, 1.0, trees)
        P(6.0, 60.0, "SpruceB", 0.2, 1.0, trees)
        P(22.0, 54.0, "BirchB", 1.7, 1.0, trees)
        P(-6.0, 66.0, "SpruceA", 2.4, 1.0, trees)
    fig = pv.figure(scene)
    fig.hide_render = False
    fig.location = (1.5, 6.0, Z(1.5, 6.0))
    fig.rotation_euler = (0, 0, math.radians(160))
    pv.set_sun(scene, 30.0, 120.0)
    cz = Z(0.0, -5.0)
    pv.camera(scene, (0.0, -5.0, cz + pv.EYE), (0.0, 14.0, cz + 2.4), 24.0)
    p = pv.render(scene, os.path.join(out_dir, "_vignette_meadow.png"))
    log("VIGNETTE meadow")
    clear_instances()
    _flatten_ground(g)
    return p


def cliff_vignette(scene, roots, trees, out_dir, log=print):
    clear_instances()
    _hide_all(roots)
    pn = tg.Perlin(13)

    def height(x, y):
        return 0.05 * y + 0.6 * pn.fbm(np.stack([x * 0.05, y * 0.05, np.zeros_like(x)], -1), 1.0, 3)
    g = pv.ground(scene, 220, "soil", slope=lambda x, y: height(x, y))
    rng = np.random.RandomState(17)

    def Z(x, y):
        return float(height(np.array([x]), np.array([y]))[0])

    def P(x, y, name, rot=None, s=1.0, src=None):
        return place(src or roots, name, (x, y, Z(x, y)), rng.uniform(0, 6.28) if rot is None else rot, s)
    # cliff fronts face the camera (asset front = +Y, so turn them 180 degrees)
    P(-4.0, 30.0, "CliffFaceB", math.pi)
    P(26.0, 27.0, "CliffFaceA", math.pi - 0.35)
    P(-34.0, 31.0, "CaveMouth", math.pi + 0.3)
    P(0.0, 15.5, "ScreeA", 0.4, 1.2)
    P(12.0, 13.0, "BoulderC", 2.0)
    P(-13.0, 12.0, "RockOutcrop", math.pi + 0.2)
    P(6.0, 7.0, "BoulderA", 0.5)
    P(-6.0, 6.0, "RockFlat", 1.2)
    for (x, y) in [(-2.0, 9.0), (8.0, 9.5), (-9.0, 8.0), (15.0, 8.0), (3.0, 12.0)]:
        P(x, y, "FernB" if rng.random_sample() < 0.5 else "FernA", None, rng.uniform(0.85, 1.1))
    for i in range(60):
        P(rng.uniform(-20, 22), rng.uniform(1, 16), "GrassForest", None, rng.uniform(0.8, 1.1))
    if trees:
        P(14.0, 20.0, "SpruceB", 0.4, 1.0, trees)
        P(-22.0, 18.0, "FirA", 1.3, 1.0, trees)
    fig = pv.figure(scene)
    fig.hide_render = False
    fig.location = (2.5, 10.0, Z(2.5, 10.0))
    fig.rotation_euler = (0, 0, math.radians(170))
    pv.set_sun(scene, 38.0, 230.0)
    cz = Z(0.0, -14.0)
    pv.camera(scene, (2.0, -14.0, cz + pv.EYE), (-2.0, 20.0, cz + 9.0), 22.0)
    p = pv.render(scene, os.path.join(out_dir, "_vignette_cliffs.png"))
    log("VIGNETTE cliffs")
    clear_instances()
    _flatten_ground(g)
    return p


def run_all(scene, roots, manifest, out_dir, only=None, log=print, glb_dir=None):
    pv.ground(scene, 400, "neutral")
    pv.set_sun(scene, *SHOT_SUN)
    if only is None or "shots" in only or any(n in roots for n in (only or [])):
        names = None if (only is None or "shots" in only) else [n for n in only if n in roots]
        if only is None or names or "shots" in only:
            pv.asset_shots(scene, roots, manifest, out_dir, names, log)
    if only is None or "lineup" in only:
        lineup(scene, roots, out_dir, log)
    want = [v for v in ("forest", "meadow", "cliffs") if only is None or v in only]
    if want:
        trees = load_trees(glb_dir, log) if glb_dir else {}
        if "forest" in want:
            forest_vignette(scene, roots, trees, out_dir, log)
        if "meadow" in want:
            meadow_vignette(scene, roots, trees, out_dir, log)
        if "cliffs" in want:
            cliff_vignette(scene, roots, trees, out_dir, log)
    pv.set_sun(scene, *SHOT_SUN)
