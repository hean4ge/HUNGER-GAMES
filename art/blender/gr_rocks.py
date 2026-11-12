"""
gr_rocks.py - GroundReal rocks: weathered granite / gneiss boulders, slabs, scree, river stones, cliff faces, cave
mouth and outcrop (Blender 5.3 headless).

Shapes are signed-distance fields (rounded joint planes, strata with per-bed joint sets, tilted block faces, recessed
soft beds, an inclined joint set, spalls, cracks, angular talus) meshed with surface nets. Low-polys keep the
surface-nets winding (no flood-fill recalculation), the Newton projection onto the field is step-clamped, and
decimation debris islands are removed.

Texturing, two systems sharing one procedural granite shader (warm-grey tone, feldspar / quartz / biotite grain,
spalls, hairline fractures, five lichen species, moss from a top-facing mask, damp base, rain streaks, iron):
  unique bakes  BoulderA-D, RockFlat, RiverStones: smart-UV low-polys (decimated from a smoothed field) packed into
                three 1024 pages (GR_RockPage1/2/3 Color + Normal, ~55-65 px/stud: Roblox caps images at 1024 px,
                so the art-direction pass moved the set from two 2048 pages to three 1024 pages); Cycles bakes the
                full-detail high-poly
                (geometry + shader bump) to tangent-space OpenGL normals and albedo x short-distance AO (ground plane
                included); albedo / normal / coverage are baked single-sample at 4096 and box-filtered.
  tiling        CliffFaceA-C, CaveMouth, RockOutcrop, ScreeA: pieces a unique bake cannot serve (too large, or a
                fragment pile no low-poly hull can follow). Seamless granite tile, 1024 px over 13 studs (GR_Granite
                Color + Normal, baked from the same shader on a 4D torus so it wraps), box-projected UVs that run
                outside 0..1, crisp per-corner normals, real geometry for strata / ledges / joints, and separate
                <Asset>_Moss shell parts on cliff ledges textured from the Shrubs atlas moss cushions.
  GR_Rock_Rough is one tileable roughness noise shared by every rock texture set (UV-agnostic, 512, 8-bit gray).
"""
import json
import math
import os
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import tex_ground as tg
from gr_atlas import NT, new_material

C = tg.rgb
TILE_STUDS = 13.0         # granite tile period (1024 px -> 79 px/stud; Roblox's image limit is 1024 px)
TILE_RES = 1024
PAGE_RES = 1024           # unique boulder pages (Roblox's image limit); three pages -> ~55-65 px/stud
SS = 2                    # bake supersampling
SETS_FILE = "GR_Rock_Sets.json"
FILES = {
    "Granite": ("GR_Granite_Color.png", "GR_Granite_Normal.png"),
    "RockPage1": ("GR_RockPage1_Color.png", "GR_RockPage1_Normal.png"),
    "RockPage2": ("GR_RockPage2_Color.png", "GR_RockPage2_Normal.png"),
    "RockPage3": ("GR_RockPage3_Color.png", "GR_RockPage3_Normal.png"),
}
# which unique bake goes on which 1024 page (balanced by visible surface area)
PAGE_OF = {"BoulderD": "RockPage1", "BoulderC": "RockPage2", "BoulderA": "RockPage2", "RiverStones": "RockPage2",
           "RockFlat": "RockPage3", "BoulderB": "RockPage3"}
ROUGH = "GR_Rock_Rough.png"


# =============================================================================================== granite shader
def _col(nt, rgb):
    return nt.color(C(*rgb))


def granite_nodes(nt, vec, w, up, height, moss_amt, lichen_amt, damp_amt, streak_amt, river=0.0, tint=None):
    """Weathered granite / gneiss node graph. vec/w: 4D coordinates in studs, up = normal.z, height = z above the
    ground. Returns (color, roughness, height) sockets; height is in studs (Bump Distance 1 = physical relief).

    Layers, bottom to top: macro tone + warm weathering rind, mineral grain (biotite / white and buff feldspar /
    grey quartz) with isolated biotite flecks, spall scars (stepped flake facets), sparse hairline fractures with a
    dirt halo, rain streaks on steep faces, iron staining, five lichen species (pale crust, grey-green foliose,
    yellow-green map lichen with black prothallus lines, dark crust on tops, rare orange), moss from the up-facing
    mask, damp and soil-splashed base."""
    dry = 1.0 - river

    def W(o):
        return (w + o) if isinstance(w, (int, float)) else nt.math("ADD", w, o)

    def nz(scale, detail=4.0, rough=0.55, dist=0.0, v=None, wo=0.0):
        node = nt.n("ShaderNodeTexNoise", noise_dimensions="4D")
        nt._in(node.inputs["Vector"], vec if v is None else v)
        nt._in(node.inputs["W"], W(wo))
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        node.inputs["Distortion"].default_value = dist
        return node.outputs["Fac"]

    def vor(scale, feature="F1", rand=1.0, v=None, wo=0.0):
        node = nt.n("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature=feature)
        nt._in(node.inputs["Vector"], vec if v is None else v)
        nt._in(node.inputs["W"], W(wo))
        node.inputs["Scale"].default_value = scale
        node.inputs["Randomness"].default_value = rand
        return node

    def chan(col_socket, i):
        s = nt.n("ShaderNodeSeparateColor")
        nt.links.new(col_socket, s.inputs[0])
        return s.outputs[i]

    def ramp(fac, stops, constant=True):
        node = nt.n("ShaderNodeValToRGB")
        cr = node.color_ramp
        cr.interpolation = "CONSTANT" if constant else "LINEAR"
        cr.elements[0].position, cr.elements[0].color = stops[0][0], tuple(C(*stops[0][1])) + (1.0,)
        cr.elements[1].position, cr.elements[1].color = stops[-1][0], tuple(C(*stops[-1][1])) + (1.0,)
        for pos, c in stops[1:-1]:
            e = cr.elements.new(pos)
            e.color = tuple(C(*c)) + (1.0,)
        nt._in(node.inputs[0], fac)
        return node.outputs["Color"]

    def mul(a, b):
        return nt.math("MULTIPLY", a, b)

    def add(a, b):
        return nt.math("ADD", a, b)

    def lin(v, a, b, c=0.0, d=1.0):
        return nt.mapr(v, a, b, c, d, False)

    # ------------------------------------------------------------------ tone
    macro = nz(0.11, 3, 0.5)
    zone = nz(0.42, 4, 0.55, wo=3.1)
    col = nt.mixc(_col(nt, (74, 73, 70)), _col(nt, (132, 129, 122)), nt.mapr(macro, 0.32, 0.68))
    col = nt.vmath("SCALE", col, scale=nt.mapr(zone, 0.3, 0.7, 0.84, 1.06))
    warm = mul(nt.mapr(nz(0.27, 3, 0.5, wo=7.7), 0.5, 0.68), 0.35 * dry)
    col = nt.mixc(col, nt.vmath("MULTIPLY", col, (1.0, 0.93, 0.84)), warm)
    # ------------------------------------------------------------------ mineral grain
    g = vor(34.0, "F1", 1.0)
    grain = ramp(chan(g.outputs["Color"], 0), [(0.0, (184, 181, 172)), (0.45, (124, 125, 125)), (0.74, (176, 166, 154)),
                                               (0.88, (190, 186, 176)), (1.0, (190, 186, 176))])
    col = nt.mixc(col, grain, 0.2 * dry + 0.14 * river)
    gp = vor(7.0, "F1", 1.0, wo=0.9)
    pheno = mul(nt.mapr(chan(gp.outputs["Color"], 0), 0.24, 0.2), nt.mapr(gp.outputs["Distance"], 0.42, 0.3))
    col = nt.mixc(col, _col(nt, (192, 188, 178)), mul(pheno, 0.3 * dry))
    g2 = vor(70.0, "F1", 1.0, wo=1.7)
    fleck = mul(nt.mapr(chan(g2.outputs["Color"], 0), 0.17, 0.15), nt.mapr(g2.outputs["Distance"], 0.36, 0.26))
    col = nt.mixc(col, _col(nt, (36, 34, 32)), mul(fleck, 0.85 - 0.5 * river))
    fine = nz(14.0, 5, 0.6, wo=2.2)
    col = nt.vmath("SCALE", col, scale=lin(fine, 0.3, 0.7, 0.93, 1.05))
    if tint is not None:
        col = nt.vmath("MULTIPLY", col, tint)
    # ------------------------------------------------------------------ spall scars (stepped flake facets)
    fv = vor(1.3, "F1", 1.0, wo=4.4)
    frand = chan(fv.outputs["Color"], 1)
    spall = mul(nt.mapr(nz(0.45, 3, 0.5, wo=5.5), 0.5, 0.58), dry)
    step_h = mul(mul(frand, 0.022), spall)
    col = nt.vmath("SCALE", col, scale=add(1.0, mul(mul(nt.mapr(frand, 0.72, 0.8), spall), 0.07)))
    # ------------------------------------------------------------------ hairline fractures
    wn = nt.n("ShaderNodeTexNoise", noise_dimensions="4D")
    nt._in(wn.inputs["Vector"], vec)
    nt._in(wn.inputs["W"], W(10.0))
    wn.inputs["Scale"].default_value = 0.9
    wn.inputs["Detail"].default_value = 3.0
    vwarp = nt.vmath("ADD", vec, nt.vmath("SCALE", nt.vmath("SUBTRACT", wn.outputs["Color"], (0.5, 0.5, 0.5)),
                                          scale=0.6))
    fr = vor(0.3, "DISTANCE_TO_EDGE", 1.0, v=vwarp, wo=11.0)
    seg = nt.mapr(nz(0.45, 2, 0.5, wo=12.5), 0.56, 0.62)
    crack = mul(mul(nt.mapr(fr.outputs["Distance"], 0.008, 0.0015), seg), 0.35 + 0.65 * dry)
    halo = mul(mul(nt.mapr(fr.outputs["Distance"], 0.035, 0.004), seg), 0.08 * dry)
    col = nt.vmath("SCALE", col, scale=nt.math("SUBTRACT", 1.0, add(mul(crack, 0.5), halo)))
    # ------------------------------------------------------------------ rain streaks, iron staining
    sv = nt.vmath("MULTIPLY", vec, (2.0, 2.0, 0.17))
    streak = mul(mul(nt.mapr(nz(1.0, 3, 0.5, v=sv, wo=6.0), 0.52, 0.7),
                     nt.math("SUBTRACT", 1.0, nt.math("ABSOLUTE", up))), streak_amt)
    col = nt.mixc(col, nt.vmath("MULTIPLY", col, (0.62, 0.6, 0.58)), mul(streak, 0.55))
    iron = mul(nt.mapr(nz(0.5, 3, 0.5, wo=8.8), 0.62, 0.72), 0.18 * dry)
    col = nt.mixc(col, nt.vmath("MULTIPLY", col, (1.0, 0.78, 0.55)), iron)
    # ------------------------------------------------------------------ lichens
    expo = mul(nt.mapr(up, -0.25, 0.65, 0.45, 1.0), nt.mapr(height, 0.12, 0.9))
    lam = mul(expo, lichen_amt * dry)
    lam = mul(lam, nt.mapr(nz(0.16, 2, 0.5, wo=90.0), 0.38, 0.62, 0.2, 1.15))
    # L1 pale crust (Lecanora / Pertusaria): fractal lobed edge, paler growing rim, mottled
    n1 = nz(1.5, 8, 0.64, 0.25, wo=21.0)
    m1 = mul(nt.mapr(n1, 0.565, 0.578), lam)
    c1 = nt.mixc(_col(nt, (206, 206, 196)), _col(nt, (178, 180, 170)), nt.mapr(n1, 0.582, 0.62))
    c1 = nt.mixc(c1, _col(nt, (156, 160, 148)), nt.mapr(n1, 0.64, 0.7))
    c1 = nt.vmath("SCALE", c1, scale=lin(nz(16.0, 4, 0.6, wo=22.0), 0.3, 0.7, 0.9, 1.06))
    c1 = nt.mixc(c1, _col(nt, (150, 164, 136)), mul(nt.mapr(nz(0.7, 2, 0.5, wo=23.0), 0.42, 0.62), 0.6))
    c1 = nt.mixc(c1, _col(nt, (166, 166, 160)), mul(nt.mapr(nz(0.7, 2, 0.5, wo=24.0), 0.45, 0.65), 0.5))
    col = nt.mixc(col, c1, mul(m1, 0.9))
    # L2 grey-green foliose (Parmelia) with dark apothecia dots
    n2 = nz(2.2, 8, 0.62, 0.3, wo=31.0)
    m2 = mul(nt.mapr(n2, 0.598, 0.61), lam)
    c2 = nt.mixc(_col(nt, (170, 180, 150)), _col(nt, (128, 142, 110)), nt.mapr(n2, 0.615, 0.65))
    dots = mul(nt.mapr(vor(30.0, "F1", 1.0, wo=33.0).outputs["Distance"], 0.15, 0.1), nt.mapr(n2, 0.632, 0.66))
    c2 = nt.mixc(c2, _col(nt, (74, 62, 46)), mul(dots, 0.8))
    col = nt.mixc(col, c2, mul(m2, 0.92))
    # L4 dark crust on tops (Umbilicaria-like)
    n4 = nz(1.9, 6, 0.6, 0.2, wo=51.0)
    m4 = mul(mul(nt.mapr(n4, 0.635, 0.646), nt.mapr(up, 0.2, 0.85, 0.35, 1.0)), lam)
    c4 = nt.vmath("SCALE", _col(nt, (70, 66, 58)), scale=lin(nz(12.0, 3, wo=52.0), 0.3, 0.7, 0.85, 1.15))
    col = nt.mixc(col, c4, mul(m4, 0.85))
    # L3 yellow-green map lichen: areolae separated by black prothallus lines
    n3 = nz(3.2, 6, 0.6, 0.2, wo=41.0)
    m3 = mul(nt.mapr(n3, 0.626, 0.634), lam)
    are = nt.mapr(vor(34.0, "DISTANCE_TO_EDGE", 1.0, wo=42.0).outputs["Distance"], 0.07, 0.025)
    c3 = nt.mixc(_col(nt, (168, 176, 80)), _col(nt, (42, 42, 36)), mul(are, 0.85))
    rim3 = nt.math("SUBTRACT", nt.mapr(n3, 0.626, 0.629), nt.mapr(n3, 0.631, 0.638))
    c3 = nt.mixc(c3, _col(nt, (36, 36, 32)), nt.math("MAXIMUM", rim3, 0.0))
    col = nt.mixc(col, c3, mul(m3, 0.95))
    # L5 orange (Xanthoria), rare small spots
    n5 = nz(4.5, 5, 0.6, 0.1, wo=61.0)
    m5 = mul(nt.mapr(n5, 0.675, 0.684), lam)
    col = nt.mixc(col, _col(nt, (188, 132, 58)), mul(m5, 0.75))
    lich = nt.math("MAXIMUM", nt.math("MAXIMUM", m1, m2), nt.math("MAXIMUM", nt.math("MAXIMUM", m3, m4), m5))
    # ------------------------------------------------------------------ moss on up-facing surfaces
    mb = nz(0.7, 4, 0.6, wo=71.0)
    mm = mul(nt.mapr(up, 0.45, 0.8), nt.mapr(mb, 0.36, 0.5))
    mm = mul(mul(mm, nt.mapr(height, 0.05, 0.4)), moss_amt)
    mm = mul(mm, nt.mapr(nz(6.0, 5, 0.6, wo=72.0), 0.3, 0.46))
    mt = vor(30.0, "F1", 1.0, wo=73.0)
    mcol = nt.mixc(_col(nt, (70, 92, 36)), _col(nt, (118, 132, 52)), lin(chan(mt.outputs["Color"], 0), 0.2, 0.9))
    mcol = nt.mixc(mcol, _col(nt, (52, 68, 30)), mul(nt.mapr(mt.outputs["Distance"], 0.3, 0.55), 0.45))
    mcol = nt.mixc(mcol, _col(nt, (128, 114, 66)), mul(nt.mapr(nz(0.9, 4, 0.55, wo=74.0), 0.6, 0.7), 0.5))
    col = nt.mixc(col, mcol, mm)
    # ------------------------------------------------------------------ damp, soil-splashed base
    damp = mul(nt.mapr(height, 0.6, 0.0), damp_amt)
    col = nt.mixc(col, nt.vmath("MULTIPLY", col, (0.66, 0.63, 0.58)), damp)
    col = nt.mixc(col, _col(nt, (72, 60, 48)), nt.mapr(height, 0.04, -0.12))
    # ------------------------------------------------------------------ roughness (Roblox reads ~0.1 smoother)
    rough = add(0.88, mul(nt.math("SUBTRACT", fine, 0.5), 0.1))
    rough = add(rough, mul(lich, 0.03))
    rough = add(rough, mul(mm, 0.05))
    rough = nt.math("SUBTRACT", rough, mul(damp, 0.2))
    rough = nt.math("SUBTRACT", rough, 0.24 * river)
    # ------------------------------------------------------------------ relief in studs
    def N(fac):
        return mul(nt.math("SUBTRACT", fac, 0.5), 6.0)
    hgt = mul(nt.mapr(g.outputs["Distance"], 0.0, 0.5, 1.0, 0.0), 0.004 * (1.0 - 0.7 * river))
    hgt = add(hgt, mul(pheno, 0.006 * dry))
    hgt = nt.math("SUBTRACT", hgt, mul(fleck, 0.004))
    hgt = add(hgt, mul(N(nz(40.0, 3, 0.6, wo=80.0)), 0.0012 * (1.0 - 0.6 * river)))
    hgt = add(hgt, mul(N(nz(3.0, 5, 0.6, wo=81.0)), 0.01 * (1.0 - 0.5 * river)))
    hgt = add(hgt, mul(N(nz(0.9, 4, 0.55, wo=82.0)), 0.035))
    hgt = add(hgt, mul(step_h, 1.4))
    hgt = nt.math("SUBTRACT", hgt, add(mul(crack, 0.03), mul(halo, 0.06)))
    hgt = add(hgt, mul(lich, add(0.004, mul(N(nz(24.0, 3, 0.6, wo=83.0)), 0.001))))
    hgt = add(hgt, mul(mm, add(0.02, mul(nt.mapr(mt.outputs["Distance"], 0.0, 0.6, 1.0, 0.0), 0.025))))
    return col, rough, hgt



def rock_material(name, moss=1.0, lichen=1.0, damp=1.0, streak=0.6, river=0.0, bump=1.0, seed_w=0.0):
    """Principled material on the high-poly / bake plane, plus an Emission 'white' coverage output switch."""
    mat, nt = new_material(name)
    tc = nt.n("ShaderNodeTexCoord")
    geo = nt.n("ShaderNodeNewGeometry")
    vec = tc.outputs["Object"]
    sep_n = nt.n("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep_n.inputs[0])
    sep_p = nt.n("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep_p.inputs[0])
    tint = None
    if river > 0:
        oi = nt.n("ShaderNodeObjectInfo")
        ramp = nt.n("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.interpolation = "CONSTANT"
        stones = [(0.0, (236, 236, 236)), (0.22, (176, 176, 180)), (0.42, (246, 222, 196)), (0.6, (255, 252, 244)),
                  (0.78, (214, 226, 210))]
        cr.elements[0].position, cr.elements[0].color = 0.0, tuple(C(*stones[0][1])) + (1.0,)
        cr.elements[1].position, cr.elements[1].color = stones[-1][0], tuple(C(*stones[-1][1])) + (1.0,)
        for pos, col in stones[1:-1]:
            e = cr.elements.new(pos)
            e.color = tuple(C(*col)) + (1.0,)
        nt.links.new(oi.outputs["Random"], ramp.inputs[0])
        tint = ramp.outputs["Color"]
        w = nt.math("MULTIPLY", oi.outputs["Random"], 37.0)
    else:
        w = seed_w
    col, rough, hgt = granite_nodes(nt, vec, w, sep_n.outputs[2], sep_p.outputs[2], moss, lichen, damp, streak,
                                    river, tint)
    bsdf = nt.n("ShaderNodeBsdfPrincipled")
    nt._in(bsdf.inputs["Base Color"], col)
    nt._in(bsdf.inputs["Roughness"], rough)
    bmp = nt.n("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = 1.0
    bmp.inputs["Distance"].default_value = bump          # relief is in studs: 1 = physical
    nt._in(bmp.inputs["Height"], hgt)
    nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    emit = nt.n("ShaderNodeEmission", name="COVER_EMIT")
    emit.inputs["Color"].default_value = (1, 1, 1, 1)
    out = nt.n("ShaderNodeOutputMaterial", name="OUT")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    mat["bsdf"] = bsdf.name
    return mat


def set_cover(mat, on):
    nt = mat.node_tree
    out = nt.nodes["OUT"]
    if on:
        nt.links.new(nt.nodes["COVER_EMIT"].outputs[0], out.inputs["Surface"])
    else:
        b = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
        nt.links.new(b.outputs[0], out.inputs["Surface"])


# =============================================================================================== bake helpers
def bake_settings(scene, samples=16, margin=2, extrusion=0.05, max_ray=0.3):
    tg.enable_gpu(scene)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    b = scene.render.bake
    b.use_selected_to_active = True
    b.use_cage = False
    b.cage_extrusion = extrusion
    b.max_ray_distance = max_ray
    b.margin = margin
    b.margin_type = "EXTEND"
    b.use_clear = False
    b.normal_space = "TANGENT"
    b.normal_r, b.normal_g, b.normal_b = "POS_X", "POS_Y", "POS_Z"
    b.target = "IMAGE_TEXTURES"


def _select_only(objs, active):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def bake_target_material(low, image):
    mat = bpy.data.materials.new("BAKE_" + low.name)
    mat.use_nodes = True
    n = mat.node_tree.nodes.new("ShaderNodeTexImage")
    n.image = image
    mat.node_tree.nodes.active = n
    low.data.materials.clear()
    low.data.materials.append(mat)
    return mat, n


def set_bake_image(low, image):
    mat = low.data.materials[0]
    n = [x for x in mat.node_tree.nodes if x.type == "TEX_IMAGE"][0]
    n.image = image
    mat.node_tree.nodes.active = n


def new_image(name, res, color=(0, 0, 0, 0), non_color=True):
    im = bpy.data.images.get(name)
    if im is not None:
        bpy.data.images.remove(im)
    im = bpy.data.images.new(name, res, res, alpha=True, float_buffer=True)
    im.colorspace_settings.name = "Non-Color" if non_color else "Linear Rec.709"
    im.generated_color = color
    return im


# =============================================================================================== tile textures
def build_rock_textures(tex_dir, cache, log=print):
    """Seamless granite tile (Color + OpenGL Normal) and the shared tileable rock roughness."""
    t0 = time.time()
    scene = bpy.context.scene
    tg.reset_scene()
    scene = bpy.context.scene
    tg.enable_gpu(scene)
    # bake plane: UV 0..1 over TILE_STUDS; shader reads 4D torus coordinates built from the UVs
    me = bpy.data.meshes.new("TilePlane")
    V = [(0, 0, 0), (TILE_STUDS, 0, 0), (TILE_STUDS, TILE_STUDS, 0), (0, TILE_STUDS, 0)]
    me.from_pydata(V, [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for li, (u, v) in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[li].uv = (u, v)
    plane = bpy.data.objects.new("TilePlane", me)
    scene.collection.objects.link(plane)
    mat, nt = new_material("GR_TileBake")
    tc = nt.n("ShaderNodeTexCoord")
    sep = nt.n("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["UV"], sep.inputs[0])
    Rr = TILE_STUDS / (2 * math.pi)

    def circ(s, fn):
        return nt.math("MULTIPLY", nt.math(fn, nt.math("MULTIPLY", s, 2 * math.pi)), Rr)
    comb = nt.n("ShaderNodeCombineXYZ")
    nt._in(comb.inputs[0], circ(sep.outputs[0], "COSINE"))
    nt._in(comb.inputs[1], circ(sep.outputs[0], "SINE"))
    nt._in(comb.inputs[2], circ(sep.outputs[1], "COSINE"))
    w = circ(sep.outputs[1], "SINE")
    # lichen 0.55 on the tile (art direction): at full strength the pale crusts read as white paint flecks across
    # the big cliff faces
    col, rough, hgt = granite_nodes(nt, comb.outputs[0], w, 0.0, 5.0, 0.0, 0.55, 0.0, 0.0)
    bsdf = nt.n("ShaderNodeBsdfPrincipled")
    nt._in(bsdf.inputs["Base Color"], col)
    nt._in(bsdf.inputs["Roughness"], rough)
    bmp = nt.n("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = 1.0
    bmp.inputs["Distance"].default_value = 1.0
    nt._in(bmp.inputs["Height"], hgt)
    nt.links.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    out = nt.n("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    img_node = nt.n("ShaderNodeTexImage")
    plane.data.materials.append(mat)
    res = TILE_RES * SS
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 0
    scene.render.bake.use_clear = True
    scene.render.bake.normal_space = "TANGENT"
    scene.cycles.samples = 1          # albedo / normal passes are deterministic; SS x SS gives the anti-aliasing
    _select_only([plane], plane)
    out_imgs = {}
    for kind, btype in (("color", "DIFFUSE"), ("normal", "NORMAL")):
        im = new_image("tile_" + kind, res)
        img_node.image = im
        nt.nodes.active = img_node
        if btype == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=0, use_clear=True)
        else:
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=0, use_clear=True)
        out_imgs[kind] = tg.image_to_np(im)
    col = tg.box_down(out_imgs["color"][..., :3], SS)
    nrm = tg.decode_normal(tg.box_down(out_imgs["normal"][..., :3], SS))
    files = FILES["Granite"]
    tg.write_png(os.path.join(tex_dir, files[0]), tg.lin_to_srgb(col))
    tg.write_png(os.path.join(tex_dir, files[1]), tg.encode_normal(nrm))
    # shared rock roughness: periodic noise around 0.84 (fine grain + mid blotches)
    rng = np.random.RandomState(77)
    n = 512
    r = 0.84 + 0.05 * tg.band_noise(rng, n, 24, 160, 0.6) + 0.04 * tg.band_noise(rng, n, 3, 12, 1.0)
    tg.write_png(os.path.join(tex_dir, ROUGH), np.clip(r, 0.6, 0.98))
    log("ROCKTEX granite tile + rough in %.0fs (avg albedo sRGB %s)" % (
        time.time() - t0, [int(v * 255) for v in tg.lin_to_srgb(col.reshape(-1, 3).mean(0))]))
    return files


def prepare_sets(tex_dir, cache, log=print):
    sets = {}
    for key in ("Granite", "RockPage1", "RockPage2", "RockPage3"):
        sets[key] = {"color": FILES[key][0], "normal": FILES[key][1], "rough": ROUGH, "alphaMode": "Overlay",
                     "avg": [128, 124, 116],
                     "notes": ("seamless granite tile, %d px over %d studs (%d px/stud); box-projected UVs run "
                               "outside 0..1 and must repeat" % (TILE_RES, TILE_STUDS, TILE_RES / TILE_STUDS)
                               if key == "Granite" else
                               "unique bake page %d px (smart UVs, ~55-65 px/stud): albedo with short-distance AO, "
                               "OpenGL tangent-space normal of the full-detail high-poly" % PAGE_RES)}
        if key == "Granite":
            sets[key]["tileStuds"] = TILE_STUDS
    with open(os.path.join(cache, SETS_FILE), "w", encoding="utf-8") as f:
        json.dump(sets, f, indent=1)
    return sets


# =============================================================================================== SDF primitives
def smax(a, b, k):
    h = np.clip(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
    return a * h + b * (1 - h) + k * h * (1 - h)


def smin(a, b, k):
    return -smax(-a, -b, k)


def sd_ellipsoid(P, c, r):
    q = (P - c) / r
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / r, axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])


def rand_rot(rng, tilt=0.4):
    a = rng.uniform(0, 2 * math.pi)
    b = rng.uniform(-tilt, tilt)
    c = rng.uniform(-tilt, tilt)
    Rz = rot_z(a)
    Rx = np.array([[1, 0, 0], [0, math.cos(b), -math.sin(b)], [0, math.sin(b), math.cos(b)]])
    Ry = np.array([[math.cos(c), 0, math.sin(c)], [0, 1, 0], [-math.sin(c), 0, math.cos(c)]])
    return Rz @ Rx @ Ry


def sd_rbox(P, c, half, R, r=0.0):
    """Rounded box with rotation R (local -> world)."""
    q = np.abs((P - c) @ R) - (np.asarray(half) - r)
    out = np.linalg.norm(np.maximum(q, 0.0), axis=1)
    ins = np.minimum(np.max(q, axis=1), 0.0)
    return out + ins - r


def sd_polyhedron(P, c, planes, k):
    """Smooth intersection of half-spaces n.(P-c) <= d."""
    f = None
    for (n, d) in planes:
        v = (P - c) @ n - d
        f = v if f is None else smax(f, v, k)
    return f


# =============================================================================================== shapes
def boulder_fn(rng, size, height, bury, planes=6, k=0.14, lump=0.05, chip=0.012, crack=None, exfoliate=0.0,
               flat_top=0.0):
    """Weathered granite corestone: ellipsoid cut by rounded joint planes, lumpy, chipped, optional crack and
    exfoliation sheets. size = (sx, sy) footprint, height = visible height above z = 0."""
    pn = tg.Perlin(rng.randint(1 << 30))
    sx, sy = size
    rz = (height + bury) * 0.62
    c = np.array([0.0, 0.0, height - rz * 1.0])
    rad = np.array([sx / 2, sy / 2, rz])
    pl = []
    for i in range(planes):
        a = 2 * math.pi * i / planes + rng.uniform(-0.4, 0.4)
        el = rng.uniform(-0.15, 0.45)
        n = np.array([math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)])
        n /= np.linalg.norm(n)
        d = np.linalg.norm(rad * n) * rng.uniform(0.66, 0.86)
        pl.append((n, d))
    if flat_top:
        pl.append((np.array([rng.normal(0, 0.12), rng.normal(0, 0.12), 1.0]) / 1.015, rz * (1 - flat_top)))
    scale = max(sx, sy)
    kk = k * scale
    off = rng.uniform(0, 100, 3)

    def coarse(P):
        f = sd_ellipsoid(P, c, rad)
        f = smax(f, sd_polyhedron(P, c, pl, kk), kk)
        return np.maximum(f, -(P[:, 2] + bury))

    def fn(P):
        f = coarse(P)
        Q = P / scale
        f = f + lump * scale * pn.fbm(Q * 2.0 + off, 1.0, 4)
        f = f + 0.35 * lump * scale * pn.fbm(Q * 6.0 + off, 1.0, 3)
        f = f + chip * scale * (pn.ridged(Q * 9.0 + off, 1.0, 3) - 0.5)
        if exfoliate:
            # weathered sheets: where a patch mask is on, the outer sheet has spalled off (surface steps in)
            t = exfoliate * 0.011 * scale
            m = tg.smoothstep(0.02, 0.09, pn.fbm(Q * 1.7 + off + 7.0, 1.0, 3))
            m2 = tg.smoothstep(0.05, 0.12, pn.fbm(Q * 2.6 + off + 19.0, 1.0, 3))
            upper = tg.smoothstep(c[2] + rz * 0.05, c[2] + rz * 0.55, P[:, 2])
            f = f + (m + 0.7 * m * m2) * upper * t
        if crack is not None:
            n, d, w = crack
            ww = w * 1.7 * tg.smoothstep(height * 0.12, height * 0.95, P[:, 2])
            v = np.abs(P @ n - d + 0.07 * scale * pn.noise(Q[:, 0] * 4, Q[:, 1] * 4, Q[:, 2] * 4)
                       + 0.02 * scale * pn.noise(Q[:, 0] * 13, Q[:, 1] * 13, Q[:, 2] * 13)) - ww
            f = np.maximum(f, -v)
        return np.maximum(f, -(P[:, 2] + bury))

    def fn_low(P):
        f = coarse(P)
        Q = P / scale
        f = f + lump * scale * pn.fbm(Q * 2.0 + off, 1.0, 4)
        f = f + 0.35 * lump * scale * pn.fbm(Q * 6.0 + off, 1.0, 2)
        return np.maximum(f, -(P[:, 2] + bury))
    fn.low = fn_low
    lo = np.array([-sx * 0.75, -sy * 0.75, -bury - 0.1])
    hi = np.array([sx * 0.75, sy * 0.75, height * 1.15 + 0.2])
    return fn, coarse, lo, hi


def strata_fn(rng, W, H, D, bury, layers, ledge=1.2, overhang=0.6, joints=5, notch=0.9, lean=0.12, taper=0.25,
              noise_amp=0.35, chip=0.08, top_rough=0.6, tunnel=None, talus=0, front_wave=1.0, layer_tilt=0.04,
              back_slope=0.5, round_k=0.35, block_tilt=0.13, soft_frac=0.3, joint_carry=0.45):
    """Stratified granite / gneiss rock mass, front face toward +Y. W x H x D (depth along -Y), buried 'bury'
    below z = 0. layers: bed thicknesses from the bottom.

    Each bed has its own vertical joint set (a joint continues from the bed below with probability joint_carry),
    so blocks are staggered like real jointed rock. Every block's front is a plane with its own yaw / pitch tilt
    (block_tilt) and its own set-back (-ledge .. +overhang), giving faceted faces, ledges and overhang lips.
    'Soft' beds (soft_frac) are recessed under the harder beds above. Open joints are V-notches near the face,
    bedding planes are grooves. tunnel: (width, height, depth, flare) arch cut along Y. talus: angular fallen
    blocks at the foot."""
    pn = tg.Perlin(rng.randint(1 << 30))
    zs = [-bury]
    for t in layers:
        zs.append(zs[-1] + t)
    zs = np.array(zs)
    nl = len(layers)
    zmid = (zs[:-1] + zs[1:]) * 0.5
    # per-bed joint sets (staggered)
    jl = []
    prev = np.sort(rng.uniform(-W / 2 * 0.92, W / 2 * 0.92, joints))
    for li in range(nl):
        jn = max(1, int(round(joints * rng.uniform(0.35, 1.45))))
        keep = prev[rng.uniform(0, 1, len(prev)) < joint_carry][:jn]
        k = max(jn - len(keep), 0)
        new = rng.uniform(-W / 2 * 0.92, W / 2 * 0.92, k)
        cur = np.sort(np.concatenate([keep, new])) if k or len(keep) else rng.uniform(-W / 3, W / 3, 1)
        # no slivers: drop joints closer than 2.2 studs
        out = []
        for x in cur:
            if not out or x - out[-1] > 2.2:
                out.append(x)
        jl.append(np.array(out))
        prev = jl[-1]
    J = max(len(j) for j in jl)
    jx = np.full((nl, J), np.inf)
    for li, j in enumerate(jl):
        jx[li, :len(j)] = j
    jtilt = rng.uniform(-0.22, 0.22, (nl, J))
    # block centres (x) per bed
    xc = np.zeros((nl, J + 1))
    for li in range(nl):
        e = np.unique(np.concatenate([[-W / 2], jl[li], [W / 2]]))
        for bi in range(J + 1):
            if bi < len(e) - 1:
                xc[li, bi] = 0.5 * (e[bi] + e[bi + 1])
            else:
                xc[li, bi] = W / 2
    soft = rng.uniform(0, 1, nl) < soft_frac
    soft[0] = False
    soft[-1] = False
    offs = rng.uniform(-ledge, overhang, (nl, J + 1))
    offs[0] += 0.4
    offs[soft] -= rng.uniform(0.9, 1.8, (int(soft.sum()), 1))
    tx = rng.uniform(-block_tilt, block_tilt, (nl, J + 1))
    tz = rng.uniform(-block_tilt * 0.8, block_tilt * 0.6, (nl, J + 1))
    jopen = rng.uniform(0.3, 1.0, (nl, J)) * notch
    yfront = D * 0.35
    tilt = rng.uniform(-layer_tilt, layer_tilt)
    off3 = rng.uniform(0, 100, 3)
    diag = []
    for i in range(max(2, int(round(W / 14.0)))):
        th = math.radians(rng.uniform(32, 62)) * rng.choice([-1.0, 1.0])
        n2 = np.array([math.cos(th), math.sin(th)])            # plane normal in (x, z)
        x0 = rng.uniform(-W / 2 * 0.8, W / 2 * 0.8)
        z0 = rng.uniform(H * 0.15, H * 0.85)
        diag.append((n2, n2[0] * x0 + n2[1] * z0, rng.uniform(0.35, 0.8) * notch, rng.uniform(H * 0.3, H * 0.7),
                     np.array([x0, z0])))
    tal = []
    for i in range(talus):
        p = np.array([rng.uniform(-W / 2 * 0.8, W / 2 * 0.8), yfront + rng.uniform(0.6, 3.2), 0.0])
        if tunnel is not None and abs(p[0]) < tunnel[0] * 0.75:
            p[0] = math.copysign(tunnel[0] * 0.75 + rng.uniform(0.5, 3.0), p[0] if p[0] else 1.0)
        s = rng.uniform(1.1, 2.6)
        p[2] = s * rng.uniform(0.1, 0.3)
        tal.append((p, rand_rot(rng, 0.9), poly_fragment(rng, s), s))

    def bed_index(x, z):
        zl = z - tilt * x
        return np.clip(np.searchsorted(zs, zl) - 1, 0, nl - 1)

    def block_index(li, x, z):
        xj = jx[li] + jtilt[li] * (z[:, None] - zmid[li][:, None])
        return (x[:, None] > xj).sum(axis=1)

    def base_sdf(P):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        li = bed_index(x, z)
        bi = block_index(li, x, z)
        e = np.clip((np.abs(x) - W / 2 * (1 - taper)) / (W / 2 * taper), 0, 1)
        wave = front_wave * (pn.noise(x * 0.07 + off3[0], li * 0.9, 0.3)
                             + 0.9 * pn.noise(x * 0.033 + off3[2], 0.5, 1.7))
        ob = offs[li, bi]
        ob = np.where(ob > 0, ob * (1.0 - e), ob)
        yf = (yfront + ob + wave + tx[li, bi] * (x - xc[li, bi]) + tz[li, bi] * (z - zmid[li])
              - lean * np.maximum(z, 0) - e * e * D * 0.38)
        f_front = (y - yf) / np.sqrt(1.0 + tx[li, bi] ** 2 + tz[li, bi] ** 2)
        f_back = (-D * 0.65 - back_slope * np.maximum(z, 0)) - y
        htop = H * (1.0 - 0.55 * e * e) + top_rough * pn.noise(x * 0.08 + off3[1], y * 0.08, 0.7)
        f_top = z - htop
        f_sides = np.abs(x) - W / 2
        f = np.maximum(np.maximum(f_front, f_back), f_top)
        f = smax(f, f_sides, 1.2)
        return np.maximum(f, -(z + bury))

    def joints_cut(P, f):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        li = bed_index(x, z)
        depth = np.maximum(0.0, (yfront + overhang + 1.0) - y)
        fade = np.clip(1.0 - depth / 3.2, 0, 1)
        xj = jx[li] + jtilt[li] * (z[:, None] - zmid[li][:, None])
        dist = np.abs(x[:, None] - xj)
        k = np.argmin(dist, axis=1)
        dmin = dist[np.arange(len(x)), k]
        gap = jopen[li, k] * fade * 0.5
        f = np.maximum(f, -(dmin - gap))
        # inclined joint set: V-notches near the face, limited in length along the fracture
        for (n2, d2, op, half_len, c2) in diag:
            dd = np.abs(n2[0] * x + n2[1] * z - d2)
            along = np.abs((x - c2[0]) * n2[1] - (z - c2[1]) * n2[0])
            lim = np.clip(1.0 - (along - half_len) / 2.0, 0, 1)
            f = np.maximum(f, -(dd - op * 0.5 * fade * lim))
        # bedding-plane grooves between beds
        zl = z - tilt * x
        dz = np.min(np.abs(zl[:, None] - zs[None, 1:-1]), axis=1) if nl > 1 else np.full(len(z), 9.0)
        bed = 0.32 * np.clip(1.0 - depth / 1.8, 0, 1) - dz
        return np.maximum(f, bed * 0.8)

    def tunnel_cut(P, f):
        if tunnel is None:
            return f
        tw, th, td, flare = tunnel
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        fr = np.clip((y - (yfront - td)) / td, 0, 1)
        ww = tw * 0.5 * (1.0 + flare * fr ** 2)
        hh = th * (1.0 + 0.35 * flare * fr ** 2)
        wob = 0.9 * pn.noise(x * 0.25 + 5, y * 0.25, z * 0.25)
        q = np.sqrt((x / ww) ** 2 + (np.maximum(z, 0) / hh) ** 2)
        inside = (q - 1.0) * np.minimum(ww, hh) + wob
        inside = np.where(z < 0, np.maximum(np.abs(x) - ww, -z - 3.0) + wob, inside)
        return np.maximum(f, -inside)

    def talus_sdf(P, band):
        f = np.full(len(P), 1e9)
        for (pos, R, pl, s) in tal:
            d0 = np.linalg.norm(P - pos, axis=1)
            near = d0 < s * 0.8 + band
            if not near.any():
                continue
            Q = (P[near] - pos) @ R
            v = None
            for (nn, dd) in pl:
                wv = Q @ nn - dd
                v = wv if v is None else smax(v, wv, 0.05 * s)
            f[near] = np.minimum(f[near], v)
        return f

    def coarse(P):
        f = base_sdf(P)
        f = tunnel_cut(P, f)
        if tal:
            f = np.minimum(f, talus_sdf(P, 1.0))
        return f

    def fn(P):
        f = base_sdf(P)
        f = joints_cut(P, f)
        f = f + noise_amp * pn.fbm(P * 0.1 + off3, 1.0, 3)
        f = f + 0.35 * noise_amp * pn.fbm(P * 0.33 + off3 + 11.0, 1.0, 2)
        f = f + chip * (pn.ridged(P * 0.9 + off3, 1.0, 2) - 0.5)
        f = tunnel_cut(P, f)
        if tal:
            f = np.minimum(f, talus_sdf(P, 0.3) + 0.05 * pn.fbm(P * 1.1, 1.0, 2))
        return np.maximum(f, -(P[:, 2] + bury))
    lo = np.array([-W / 2 - 1.0, -D - back_slope * H - 1.0, -bury - 0.3])
    hi = np.array([W / 2 + 1.0, yfront + overhang + 4.5, H + top_rough + 1.5])
    return fn, coarse, lo, hi


def strata_kwargs(name, sp):
    """strata_fn keyword arguments for a TILED spec (shared by the pipeline and the review lab)."""
    small = name == "RockOutcrop"
    return dict(ledge=sp["ledge"], overhang=sp["overhang"], joints=sp["joints"], notch=sp.get("notch", 1.0),
                lean=sp.get("lean", 0.1), taper=sp.get("taper", 0.25), noise_amp=0.2 if small else 0.5,
                chip=0.06 if small else 0.11, top_rough=0.9, tunnel=sp.get("tunnel"), talus=sp["talus"],
                back_slope=sp.get("back", 0.5), block_tilt=sp.get("block_tilt", 0.2),
                soft_frac=sp.get("soft", 0.35), front_wave=sp.get("wave", 2.0),
                layer_tilt=sp.get("dip", 0.09))



def poly_fragment(rng, s):
    """Random convex fragment: 7-9 planes around the origin at distances ~s/2."""
    pl = []
    for k in range(rng.randint(7, 10)):
        n = rng.normal(0, 1, 3)
        n[2] *= 1.3
        n /= np.linalg.norm(n)
        pl.append((n, s * 0.5 * rng.uniform(0.62, 1.0) * (0.75 if n[2] > 0.6 else 1.0)))
    return pl


def heap_fn(rng, n, extent, height, bury, size_rng):
    """Scree heap: a low noisy core mound covered with angular fragments (bigger ones at the foot)."""
    pn = tg.Perlin(rng.randint(1 << 30))
    ex, ey = extent
    core_c = np.array([0.0, 0.0, -height * 0.35])
    core_r = np.array([ex / 2 * 0.78, ey / 2 * 0.78, height * 1.15])
    frags = []
    for i in range(n):
        u = rng.uniform(0, 1)
        r = math.sqrt(u) * 0.98
        a = rng.uniform(0, 2 * math.pi)
        x, y = math.cos(a) * r * core_r[0], math.sin(a) * r * core_r[1]
        zs = core_c[2] + core_r[2] * math.sqrt(max(0.0, 1 - r * r))
        s = rng.uniform(*size_rng) * (0.65 + 0.7 * r)
        pos = np.array([x, y, zs + s * rng.uniform(-0.15, 0.12)])
        R = rand_rot(rng, 1.2)
        frags.append((pos, R, poly_fragment(rng, s), s))
    for i in range(int(n * 0.25)):          # loose fragments rolled out at the foot
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(1.0, 1.25)
        s = rng.uniform(*size_rng) * rng.uniform(0.5, 1.0)
        pos = np.array([math.cos(a) * r * core_r[0], math.sin(a) * r * core_r[1], s * 0.2])
        frags.append((pos, rand_rot(rng, 1.2), poly_fragment(rng, s), s))

    def stones(P, band):
        f = np.full(len(P), 1e9)
        for (pos, R, pl, s) in frags:
            d0 = np.linalg.norm(P - pos, axis=1)
            near = d0 < s * 0.75 + band
            if not near.any():
                continue
            Q = (P[near] - pos) @ R
            v = None
            for (nn, dd) in pl:
                w = Q @ nn - dd
                v = w if v is None else smax(v, w, 0.06 * s)
            f[near] = np.minimum(f[near], v)
        return f

    def coarse(P):
        core = sd_ellipsoid(P, core_c, core_r)
        return np.maximum(np.minimum(core + 0.12, stones(P, 0.5)), -(P[:, 2] + bury))

    def fn(P):
        core = sd_ellipsoid(P, core_c, core_r) + 0.18 + 0.12 * pn.fbm(P * 0.9, 1.0, 3)
        f = np.minimum(core, stones(P, 0.2))
        f = f + 0.025 * pn.fbm(P * 2.2, 1.0, 3) + 0.016 * (pn.ridged(P * 6.0, 1.0, 2) - 0.5)
        return np.maximum(f, -(P[:, 2] + bury))
    lo = np.array([-ex / 2 * 1.4 - 1.0, -ey / 2 * 1.4 - 1.0, -bury - 0.1])
    hi = np.array([ex / 2 * 1.4 + 1.0, ey / 2 * 1.4 + 1.0, height + 1.4])
    return fn, coarse, lo, hi


def slab_fn(rng, size, thick, bury, crack=True):
    """Tabular slab with an irregular weathered outline, rounded edges, a broken upper layer and a crack."""
    pn = tg.Perlin(rng.randint(1 << 30))
    a, b = size[0] / 2, size[1] / 2
    off = rng.uniform(0, 50, 3)
    tx, ty = rng.uniform(-0.03, 0.03), rng.uniform(-0.025, 0.025)
    cn = np.array([rng.uniform(-1, 1), 1.0, 0.0])
    cn /= np.linalg.norm(cn)

    def outline(P):
        x, y = P[:, 0], P[:, 1]
        ang = np.arctan2(y / b, x / a)
        rad = 1.0 + 0.14 * pn.noise(np.cos(ang) * 1.6 + off[0], np.sin(ang) * 1.6 + off[1], 0.5) \
            + 0.06 * pn.noise(np.cos(ang) * 5 + off[2], np.sin(ang) * 5, 1.5)
        p = 2.4
        d = (np.abs(x / a) ** p + np.abs(y / b) ** p) ** (1.0 / p) - rad
        return d * min(a, b)

    def coarse(P):
        o = outline(P)
        ztop = thick + tx * P[:, 0] + ty * P[:, 1] + 0.22 * pn.noise(P[:, 0] * 0.16 + off[1], P[:, 1] * 0.16, 4.5)
        ztop = ztop - 0.75 * thick * tg.smoothstep(-1.6, 0.0, o)          # rim bevels down into the soil
        vert = np.maximum(P[:, 2] - ztop, -(P[:, 2] + bury))
        return smax(o, vert, 0.35)

    def fn(P):
        f = coarse(P)
        # upper layer partly broken away: a 0.25 step on part of the top
        brk = tg.smoothstep(-0.02, 0.06, pn.fbm(P * 0.22 + off, 1.0, 3))
        f = f + 0.24 * brk * tg.smoothstep(thick - 0.4, thick - 0.05, P[:, 2])
        f = f + 0.06 * pn.fbm(P * 0.6 + off, 1.0, 4) + 0.02 * (pn.ridged(P * 2.4 + off, 1.0, 3) - 0.5)
        if crack:
            v = np.abs(P @ cn - 0.6 + 0.12 * pn.noise(P[:, 0] * 0.8, P[:, 1] * 0.8, 3.0)) - 0.035
            v = np.maximum(v, -(P[:, 2] - (thick - 0.55)))         # crack only through the upper part
            f = np.maximum(f, -v)
        return np.maximum(f, -(P[:, 2] + bury))
    lo = np.array([-a * 1.25 - 0.5, -b * 1.25 - 0.5, -bury - 0.1])
    hi = np.array([a * 1.25 + 0.5, b * 1.25 + 0.5, thick + 0.6])
    return fn, coarse, lo, hi


def pile_fn(rng, n, extent, height, bury, size_rng):
    """Scree pile: angular granite fragments heaped into a mound (union of rounded boxes)."""
    pn = tg.Perlin(rng.randint(1 << 30))
    stones = []
    ex, ey = extent
    for i in range(n):
        r = math.sqrt(rng.uniform(0, 1))
        a = rng.uniform(0, 2 * math.pi)
        x, y = math.cos(a) * r * ex / 2, math.sin(a) * r * ey / 2
        mound = height * (1 - r ** 1.6)
        s = rng.uniform(*size_rng) * (1.15 - 0.5 * r)
        half = np.array([s, s * rng.uniform(0.55, 0.95), s * rng.uniform(0.35, 0.7)]) * 0.5
        z = mound - half[2] * rng.uniform(0.2, 0.9)
        stones.append((np.array([x, y, z]), half, rand_rot(rng, 0.6), rng.uniform(0.06, 0.16)))

    def coarse(P):
        f = np.full(len(P), 1e9)
        for (c, half, R, rr) in stones:
            f = np.minimum(f, sd_rbox(P, c, half, R, rr * half.min() * 2))
        return np.maximum(f, -(P[:, 2] + bury))

    def fn(P):
        f = coarse(P)
        f = f + 0.035 * pn.fbm(P * 1.8, 1.0, 3) + 0.018 * (pn.ridged(P * 5.0, 1.0, 2) - 0.5)
        return np.maximum(f, -(P[:, 2] + bury))
    lo = np.array([-ex / 2 - 1.0, -ey / 2 - 1.0, -bury - 0.1])
    hi = np.array([ex / 2 + 1.0, ey / 2 + 1.0, height + 1.2])
    return fn, coarse, lo, hi


def pebble_fn(rng, size, height, bury, flat=0.6):
    """River-worn stone: smooth flattened ellipsoid with very low noise."""
    pn = tg.Perlin(rng.randint(1 << 30))
    sx, sy = size
    rz = (height + bury) * 0.55
    c = np.array([0, 0, height - rz])
    rad = np.array([sx / 2, sy / 2, rz])
    off = rng.uniform(0, 50, 3)

    def coarse(P):
        return np.maximum(sd_ellipsoid(P, c, rad), -(P[:, 2] + bury))

    def fn(P):
        f = coarse(P) + 0.02 * max(sx, sy) * pn.fbm(P / max(sx, sy) * 2.5 + off, 1.0, 3)
        return np.maximum(f, -(P[:, 2] + bury))
    lo = np.array([-sx * 0.7, -sy * 0.7, -bury - 0.05])
    hi = np.array([sx * 0.7, sy * 0.7, height + 0.1])
    return fn, coarse, lo, hi


# =============================================================================================== meshing
def sdf_object(name, fn, coarse, lo, hi, h, band, project=True):
    t = time.time()
    F, origin = tg.sdf_grid(fn, lo, hi, h, band=band, coarse_fn=coarse)
    V, Q = tg.surface_nets(F, origin, h)
    if project:
        V = tg.project_to_sdf(V, fn, iters=2, eps=h * 0.25, step=0.8, max_move=h * 0.75)
    ob = tg.mesh_object(name, V, Q)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob, time.time() - t


def apply_mods(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def decimated_copy(high, name, target_tris, sharp_deg=55.0):
    low = high.copy()
    low.data = high.data.copy()
    low.name = name
    low.data.name = name
    bpy.context.scene.collection.objects.link(low)
    cur = sum(len(p.vertices) - 2 for p in low.data.polygons)
    mod = low.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, target_tris / max(cur, 1))
    mod.use_collapse_triangulate = True
    apply_mods(low)
    # tidy: merge near verts, drop loose, triangulate
    bm = bmesh.new()
    bm.from_mesh(low.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-4)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(low.data)
    bm.free()
    for p in low.data.polygons:
        p.use_smooth = True
    low.data.set_sharp_from_angle(angle=math.radians(sharp_deg))
    return low


def sdf_gradient(fn, P, eps):
    e = eps
    g = np.stack([fn(P + np.array([e, 0, 0])) - fn(P - np.array([e, 0, 0])),
                  fn(P + np.array([0, e, 0])) - fn(P - np.array([0, e, 0])),
                  fn(P + np.array([0, 0, e])) - fn(P - np.array([0, 0, e]))], 1)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def orient_by_sdf(obj, fn, eps):
    """Make every face's winding agree with the SDF (outward = +gradient). Flood-fill normal recalculation flips
    whole regions of non-manifold decimated meshes (the black triangles); the field is never wrong."""
    me = obj.data
    n = len(me.polygons)
    if n == 0:
        return 0
    cen = np.empty(n * 3, np.float32)
    me.polygons.foreach_get("center", cen)
    nor = np.empty(n * 3, np.float32)
    me.polygons.foreach_get("normal", nor)
    g = sdf_gradient(fn, cen.reshape(-1, 3).astype(np.float64), eps)
    flip = np.nonzero((nor.reshape(-1, 3) * g).sum(1) < 0.0)[0]
    if len(flip):
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        bmesh.ops.reverse_faces(bm, faces=[bm.faces[int(i)] for i in flip])
        bm.to_mesh(me)
        bm.free()
    return len(flip)


def _edge_dir(f, a, b):
    vs = list(f.verts)
    i = vs.index(a)
    return 1 if vs[(i + 1) % len(vs)] is b else -1


def remove_small_islands(bm, min_faces=16):
    """Delete disconnected debris (decimation leaves single triangles of collapsed noise blobs)."""
    seen = set()
    junk = []
    for f in bm.faces:
        if f in seen:
            continue
        comp, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        if len(comp) < min_faces:
            junk += comp
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
    return len(junk)


def fill_small_holes(bm, max_sides=12):
    """Close the small holes collapse decimation opens next to non-manifold vertices (mostly single missing
    triangles, which bmesh holes_fill refuses). Each boundary edge is walked opposite to its one face's direction,
    so the patch is wound consistently with its neighbours; loops through a non-manifold vertex are fanned from the
    walk as long as the walk closes."""
    nxt = {}
    for e in bm.edges:
        if len(e.link_faces) != 1:
            continue
        a, b = e.verts
        f = e.link_faces[0]
        if _edge_dir(f, a, b) == 1:      # face runs a -> b, so the hole runs b -> a
            nxt.setdefault(b, []).append(a)
        else:
            nxt.setdefault(a, []).append(b)
    used = set()
    made = 0
    for start in list(nxt.keys()):
        if start in used or len(nxt[start]) != 1:
            continue
        loop = [start]
        v = nxt[start][0]
        ok = False
        while len(loop) <= max_sides:
            if v is start:
                ok = True
                break
            if v in used or v not in nxt or len(nxt[v]) != 1 or v in loop:
                break
            loop.append(v)
            v = nxt[v][0]
        if not ok or len(loop) < 3:
            continue
        used.update(loop)
        try:
            f = bm.faces.new(loop)
        except ValueError:
            continue
        if len(loop) > 3:
            bmesh.ops.triangulate(bm, faces=[f])
        made += 1
    return made


def clean_mesh(obj, fn=None, eps=0.05, fill_holes=False):
    """Remove duplicate / degenerate faces and loose geometry, fill the small holes decimation opens at non-manifold
    spots, then let Blender validate the mesh. Winding is PRESERVED when an SDF is given: surface nets orient every
    quad from the inside / outside samples and collapse decimation keeps it. (Flood-fill recalculation flips whole
    regions of these non-manifold meshes, and SDF-gradient flips mis-orient faces at the field's steps - both showed
    up as black or missing triangles.) Without an SDF, Blender's flood fill orients the mesh."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    seen = {}
    dup = []
    for f in bm.faces:
        key = tuple(sorted(v.index for v in f.verts))
        if key in seen:
            dup.append(f)
        else:
            seen[key] = f
    if dup:
        bmesh.ops.delete(bm, geom=dup, context="FACES")
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-4)
    loose = [e for e in bm.edges if not e.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="EDGES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces)
    remove_small_islands(bm, 16)
    if fill_holes:
        fill_small_holes(bm)
    if fn is None:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.validate(clean_customdata=False)
    return obj


def sdf_loop_normals(obj, fn, eps=0.12, shift=0.3, crease_deg=70.0):
    """Per-corner normals for un-baked (tiled) rock: the SDF gradient is sampled a little inside each triangle
    (shift toward its centre) with a small eps, so block arrises and ledge lips stay crisp while flat and curved
    areas shade smoothly. Corners whose sample disagrees with the face by more than crease_deg use the face normal."""
    me = obj.data
    co = tg.vertex_coords(me)
    li = tg.loop_vertex_indices(me)
    n = len(me.polygons)
    cen = np.empty(n * 3, np.float32)
    me.polygons.foreach_get("center", cen)
    pnr = np.empty(n * 3, np.float32)
    me.polygons.foreach_get("normal", pnr)
    ls = np.empty(n, np.int32)
    lt = np.empty(n, np.int32)
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    lpoly = np.repeat(np.arange(n), lt)
    cen = cen.reshape(-1, 3).astype(np.float64)
    pnr = pnr.reshape(-1, 3).astype(np.float64)
    P = co[li] + shift * (cen[lpoly] - co[li])
    g = sdf_gradient(fn, P, eps)
    fnl = pnr[lpoly]
    dot = (g * fnl).sum(1)
    out = np.where((dot < math.cos(math.radians(crease_deg)))[:, None], fnl, g)
    tg.set_custom_normals(me, out)


def low_from_sdf(name, fn, coarse, lo, hi, target, band, prefactor=2.6, sharp_deg=60.0, crease_deg=58.0,
                 normals="vertex"):
    """Low-poly with even triangles: mid-resolution surface nets (about prefactor x target tris) projected onto the
    SDF, decimated (iterated) to the budget, cleaned, with custom normals from the SDF gradient: 'vertex' = low-pass
    per vertex (baked rocks: the normal map carries the detail), 'loop' = per corner, crisp edges (tiled rocks)."""
    t = time.time()
    # area estimate from a coarse pass
    h0 = max(hi - lo) / 60.0
    F0, o0 = tg.sdf_grid(coarse, lo, hi, h0)
    V0, Q0 = tg.surface_nets(F0, o0, h0)
    a0 = 0.0
    for q in Q0:
        p = V0[q]
        a0 += 0.5 * np.linalg.norm(np.cross(p[2] - p[0], p[3] - p[1]))
    hm = math.sqrt(a0 / (target * prefactor / 2.0))
    F, origin = tg.sdf_grid(fn, lo, hi, hm, band=band + 3 * hm, coarse_fn=coarse)
    V, Q = tg.surface_nets(F, origin, hm)
    V = tg.project_to_sdf(V, fn, iters=3, eps=hm * 0.2, step=0.85, max_move=hm * 0.75)
    low = tg.mesh_object(name, V, Q)
    oe = max(hm * 0.5, 0.02)
    clean_mesh(low, fn, oe)
    for attempt in range(4):
        cur = tg.tri_count(low)
        if cur <= target:
            break
        mod = low.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.05, target / cur * (0.98 if attempt == 0 else 0.93))
        mod.use_collapse_triangulate = True
        apply_mods(low)
        clean_mesh(low, fn, oe)
    if normals == "loop":
        sdf_loop_normals(low, fn, eps=max(hm * 0.28, 0.05), shift=0.25, crease_deg=70.0)
    else:
        sdf_normals(low, fn, eps=max(hm * 0.9, 0.04), crease_deg=crease_deg)
    return low, hm, time.time() - t


def sdf_normals(obj, fn, eps, crease_deg=58.0):
    """Custom split normals from the SDF gradient (central differences over eps act as a low-pass filter), so the
    shading follows the true surface instead of the triangle layout. Corners where the gradient disagrees with the
    face by more than crease_deg keep the face normal (crisp ledge lips)."""
    me = obj.data
    co = tg.vertex_coords(me)
    e = eps
    g = np.stack([fn(co + np.array([e, 0, 0])) - fn(co - np.array([e, 0, 0])),
                  fn(co + np.array([0, e, 0])) - fn(co - np.array([0, e, 0])),
                  fn(co + np.array([0, 0, e])) - fn(co - np.array([0, 0, e]))], 1)
    g /= np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
    cosc = math.cos(math.radians(crease_deg))
    loops = []
    li = tg.loop_vertex_indices(me)
    pn = np.empty(len(me.polygons) * 3, np.float32)
    me.polygons.foreach_get("normal", pn)
    pn = pn.reshape(-1, 3)
    lpoly = np.empty(len(me.loops), np.int64)
    for p in me.polygons:
        lpoly[p.loop_start:p.loop_start + p.loop_total] = p.index
    vn = g[li]
    fnrm = pn[lpoly]
    dot = (vn * fnrm).sum(1)
    out = np.where((dot < cosc)[:, None], fnrm, vn)
    tg.set_custom_normals(me, out)


def mesh_area(obj, zmin=None):
    a = 0.0
    for p in obj.data.polygons:
        if zmin is not None and p.center.z < zmin:
            continue
        a += p.area
    return a


# =============================================================================================== UVs
def smart_uv(obj, angle=62.0, margin=0.002):
    _select_only([obj], obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def shrink_hidden_islands(obj, z_hidden=-0.08, factor=0.3):
    """Scale UV islands lying entirely below ground so buried faces cost little texture space."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uvl = bm.loops.layers.uv.active
    bm.faces.ensure_lookup_table()
    seen = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        # flood fill over faces sharing UV-connected edges
        island = []
        stack = [f]
        seen.add(f.index)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for g2 in e.link_faces:
                    if g2.index in seen:
                        continue
                    # connected in UV if both edge verts share uv coords in both faces
                    ok = True
                    for v in e.verts:
                        uv1 = [l[uvl].uv for l in g.loops if l.vert == v][0]
                        uv2 = [l[uvl].uv for l in g2.loops if l.vert == v][0]
                        if (uv1 - uv2).length > 1e-6:
                            ok = False
                            break
                    if ok:
                        seen.add(g2.index)
                        stack.append(g2)
        if all(max(v.co.z for v in g.verts) < z_hidden for g in island):
            uvs = [l[uvl] for g in island for l in g.loops]
            c = sum((l.uv for l in uvs), Vector((0, 0))) / len(uvs)
            for l in uvs:
                l.uv = c + (l.uv - c) * factor
    bm.to_mesh(obj.data)
    bm.free()


def pack_page(objs, margin=0.0035):
    """Average island scale across all objects (uniform texel density) and pack them into one 0..1 page."""
    _select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        shrink_hidden_islands(o)
    _select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    try:
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, margin_method="FRACTION", margin=margin,
                                shape_method="CONCAVE", scale=True)
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_density(objs, res=PAGE_RES):
    """Texel density (px per stud) of a packed page: sqrt(uv area * res^2 / 3D area) over visible faces."""
    a3 = 0.0
    auv = 0.0
    for o in objs:
        me = o.data
        uv = me.uv_layers.active.data
        for p in me.polygons:
            if p.center.z < -0.05:
                continue
            a3 += p.area
            pts = [uv[li].uv for li in p.loop_indices]
            s = 0.0
            for i in range(1, len(pts) - 1):
                s += abs((pts[i].x - pts[0].x) * (pts[i + 1].y - pts[0].y) - (pts[i + 1].x - pts[0].x) * (pts[i].y - pts[0].y)) * 0.5
            auv += s
    return math.sqrt(auv * res * res / max(a3, 1e-6))


def box_tile_uvs(obj, studs=TILE_STUDS, rng=None, offset=None):
    """Box-projected UVs that wrap: vertical faces map (horizontal, z) so bands stay horizontal; tops map (x, y).
    Each projection axis gets its own random offset so seams are not aligned with each other."""
    rng = rng or np.random.RandomState(0)
    off = offset if offset is not None else rng.uniform(0, 1, (6, 2))
    me = obj.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    co = tg.vertex_coords(me)
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            v = co[me.loops[li].vertex_index]
            if ax == 2:
                u_, v_ = v[0], v[1]
                k = 4 if n[2] > 0 else 5
            elif ax == 1:
                u_, v_ = (v[0] if n[1] > 0 else -v[0]), v[2]
                k = 2 if n[1] > 0 else 3
            else:
                u_, v_ = (-v[1] if n[0] > 0 else v[1]), v[2]
                k = 0 if n[0] > 0 else 1
            uv.data[li].uv = (u_ / studs + off[k, 0], v_ / studs + off[k, 1])


# =============================================================================================== bake a page
def bake_page(page, pairs, tex_dir, cache, log=print, ground=True, ao_dist=0.6):
    """pairs: [(high, low, extrusion, max_ray)]. Low-polys already carry packed UVs. Writes Color + Normal PNGs at
    PAGE_RES. Albedo, normal and coverage are baked single-sample at SS x PAGE_RES and box-filtered (coverage
    weighted); AO is baked at PAGE_RES with a short distance (micro-occlusion and ground contact only)."""
    scene = bpy.context.scene
    t0 = time.time()
    hi_res = PAGE_RES * SS
    imgs = {"color": new_image(page + "_color", hi_res), "normal": new_image(page + "_normal", hi_res),
            "cover": new_image(page + "_cover", hi_res), "ao": new_image(page + "_ao", PAGE_RES)}
    if scene.world is None:
        scene.world = bpy.data.worlds.new("GR_BakeWorld")
    scene.world.light_settings.distance = ao_dist
    # spread pairs apart so AO / rays never see a neighbour; a ground plane under each for contact AO
    grounds = []
    for i, (hi, lo, ex, mr) in enumerate(pairs):
        off = Vector((i * 120.0, 0, 0))
        hi.location += off
        lo.location += off
        if ground:
            gme = bpy.data.meshes.new("bk_ground")
            s = 60
            gme.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
            g = bpy.data.objects.new("bk_ground", gme)
            scene.collection.objects.link(g)
            g.location = off
            gm = bpy.data.materials.get("bk_ground_mat") or bpy.data.materials.new("bk_ground_mat")
            gme.materials.append(gm)
            grounds.append(g)
        bake_target_material(lo, imgs["color"])
    bpy.context.view_layer.update()
    times = []
    for kind, btype, spp in (("color", "DIFFUSE", 1), ("normal", "NORMAL", 1), ("cover", "EMIT", 1),
                             ("ao", "AO", 32)):
        tp = time.time()
        margin = 4 if kind == "ao" else 4 * SS
        for (hi, lo, ex, mr) in pairs:
            bake_settings(scene, samples=spp, margin=margin, extrusion=ex, max_ray=mr)
            set_bake_image(lo, imgs[kind])
            for m in hi.data.materials:
                set_cover(m, btype == "EMIT")
            _select_only([hi, lo], lo)
            kw = dict(type=btype, use_selected_to_active=True, cage_extrusion=ex, max_ray_distance=mr,
                      margin=margin, use_clear=False)
            if btype == "DIFFUSE":
                kw["pass_filter"] = {"COLOR"}
            if btype == "NORMAL":
                kw["normal_space"] = "TANGENT"
            bpy.ops.object.bake(**kw)
        for (hi, lo, ex, mr) in pairs:
            for m in hi.data.materials:
                set_cover(m, False)
        times.append("%s %.0fs" % (kind, time.time() - tp))
    arr = {k: tg.image_to_np(im) for k, im in imgs.items()}
    w_hi = (np.clip(arr["cover"][..., 0], 0, 1) > 0.5).astype(np.float64)
    den = tg.box_down(w_hi, SS)

    def down(x):
        return tg.box_down(x * w_hi[..., None], SS) / np.maximum(den, 1e-6)[..., None]
    albedo = down(arr["color"][..., :3].astype(np.float64))
    nrm = down(tg.decode_normal(arr["normal"][..., :3].astype(np.float64)))
    ao = np.clip(arr["ao"][..., 0], 0, 1)
    col = albedo * (0.62 + 0.38 * ao[..., None])
    w = (den > 0.24).astype(np.float64)
    col = tg.pushpull(col, w)
    nrm = tg.pushpull(nrm, w)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
    files = FILES[page]
    tg.write_png(os.path.join(tex_dir, files[0]), tg.lin_to_srgb(col))
    tg.write_png(os.path.join(tex_dir, files[1]), tg.encode_normal(nrm))
    for i, (hi, lo, ex, mr) in enumerate(pairs):
        off = Vector((i * 120.0, 0, 0))
        hi.location -= off
        lo.location -= off
    for g in grounds:
        bpy.data.objects.remove(g, do_unlink=True)
    for im in imgs.values():
        bpy.data.images.remove(im)
    avg = tg.lin_to_srgb(col[w > 0.5].mean(0)) if (w > 0.5).any() else np.array([0.5, 0.5, 0.5])
    log("BAKE %s %d objects in %.0fs (%s)" % (page, len(pairs), time.time() - t0, ", ".join(times)))
    return [int(v * 255) for v in avg]


# =============================================================================================== moss shells
def moss_shells(part, obj, rng, layout, count, r_rng=(0.7, 1.5), up_min=0.62, zmin=0.6, offset=0.035,
                slots=("moss_a", "moss_b"), grid=7):
    """Moss cushions draped on up-facing ledge tops of obj: a small grid per cushion is dropped vertically onto the
    rock (BVH ray casts), lifted along the hit normal and mapped onto a moss cushion slot (ragged alpha edge at
    ~r). Grid cells that fall over a lip or onto steep rock are dropped, so cushions stop at ledge edges."""
    from mathutils.bvhtree import BVHTree
    me = obj.data
    co = tg.vertex_coords(me)
    polys = [tuple(p.vertices) for p in me.polygons]
    bvh = BVHTree.FromPolygons([Vector(v) for v in co], polys)
    cand = [p for p in me.polygons if p.normal.z > up_min and p.center.z > zmin]
    if not cand:
        return 0
    areas = np.array([p.area for p in cand])
    centers = np.array([tuple(p.center) for p in cand])
    seeds = []
    tries = 0
    while len(seeds) < count and tries < count * 60:
        tries += 1
        i = rng.choice(len(cand), p=areas / areas.sum())
        c = centers[i] + np.array([rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0])
        r = rng.uniform(*r_rng)
        if any(np.linalg.norm(c[:2] - s[0][:2]) < (r + s[1]) * 0.95 for s in seeds):
            continue
        seeds.append((c, r))
    made = 0
    for k, (c, r) in enumerate(seeds):
        sl = layout[slots[k % len(slots)]]
        x0, y0, x1, y1 = sl["rect"]
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        half_px = min(x1 - x0, y1 - y0) / 2.0 * 0.96
        ang = rng.uniform(0, 2 * math.pi)
        ax, ay = rng.uniform(1.0, 1.9), rng.uniform(0.55, 0.9)        # elongated, irregular cushions
        ca, sa = math.cos(ang), math.sin(ang)
        lift = offset + 0.003 * k
        n = grid
        P = np.full((n + 1, n + 1, 3), np.nan)
        Nn = np.zeros((n + 1, n + 1, 3))
        UV = np.zeros((n + 1, n + 1, 2))
        ok = np.zeros((n + 1, n + 1), bool)
        for j in range(n + 1):
            for i in range(n + 1):
                gx, gy = (i / n * 2 - 1) * r * ax, (j / n * 2 - 1) * r * ay
                wx, wy = c[0] + gx * ca - gy * sa, c[1] + gx * sa + gy * ca
                hit = bvh.ray_cast(Vector((wx, wy, c[2] + 2.5)), Vector((0, 0, -1)), 6.0)
                if hit[0] is None:
                    continue
                pos, nrm_ = np.array(hit[0]), np.array(hit[1])
                if nrm_[2] < 0.35 or abs(pos[2] - c[2]) > 0.9:
                    continue
                P[j, i] = pos + nrm_ * lift
                Nn[j, i] = tg_up_blend(nrm_)
                UV[j, i] = ((cx + (i / n * 2 - 1) * half_px) / 1024.0, (cy + (j / n * 2 - 1) * half_px) / 1024.0)
                ok[j, i] = True
        V, N, U2, F = [], [], [], []
        idx = -np.ones((n + 1, n + 1), int)
        for j in range(n + 1):
            for i in range(n + 1):
                if ok[j, i]:
                    idx[j, i] = len(V)
                    V.append(P[j, i])
                    N.append(Nn[j, i])
                    U2.append(UV[j, i])
        for j in range(n):
            for i in range(n):
                q = [idx[j, i], idx[j, i + 1], idx[j + 1, i + 1], idx[j + 1, i]]
                if min(q) < 0:
                    continue
                zs = [P[j, i][2], P[j, i + 1][2], P[j + 1, i + 1][2], P[j + 1, i][2]]
                if max(zs) - min(zs) > 0.45 * (2 * r * ax / n) + 0.25:
                    continue
                F.append(tuple(q))
        if F:
            part._add(np.array(V), np.array(N), np.array(U2), F, False)
            made += 1
    return made


def tg_up_blend(n):
    v = np.asarray(n, float) * 0.6 + np.array([0, 0, 0.4])
    return v / max(np.linalg.norm(v), 1e-9)


# =============================================================================================== assets
SPECS = {
    # name: (builder kwargs, target tris, grid h, texture mode)
}


def _boulder(rng, name):
    if name == "BoulderA":
        return boulder_fn(rng, (2.6, 2.2), 1.7, 0.35, planes=9, k=0.045, lump=0.045, chip=0.02), 520, 0.022
    if name == "BoulderB":
        n = np.array([0.94, 0.25, 0.22])
        n /= np.linalg.norm(n)
        return boulder_fn(rng, (5.0, 4.1), 3.1, 0.5, planes=8, k=0.06, lump=0.045, chip=0.018,
                          crack=(n, 0.35, 0.07)), 950, 0.035
    if name == "BoulderC":
        return boulder_fn(rng, (8.6, 7.0), 4.9, 0.8, planes=9, k=0.09, lump=0.05, chip=0.015, exfoliate=1.0,
                          flat_top=0.12), 1450, 0.05
    if name == "BoulderD":
        return boulder_fn(rng, (13.5, 11.0), 6.8, 1.2, planes=10, k=0.1, lump=0.055, chip=0.014, exfoliate=1.0,
                          flat_top=0.2), 2000, 0.07
    raise ValueError(name)


def build_all_rocks(lib, L, tex_dir, cache, log=print):
    scene = bpy.context.scene
    S = L["Shrubs"]
    t_all = time.time()
    unique = []          # (name, high, low, kind, extrusion, maxray)
    tiled = []
    # ---------------------------------------------------------------- boulders
    for i, name in enumerate(["BoulderA", "BoulderB", "BoulderC", "BoulderD"]):
        rng = np.random.RandomState(300 + i)
        (fn, coarse, lo, hi), target, h = _boulder(rng, name)
        high, dt = sdf_object(name + "_high", fn, coarse, lo, hi, h, band=h * 6 + 0.25 * max(hi - lo))
        mat = rock_material("RM_" + name, moss=1.0 if name in ("BoulderC", "BoulderD") else 0.7, lichen=1.0,
                            damp=1.0, streak=0.5, seed_w=11.0 * (i + 1))
        high.data.materials.append(mat)
        low, hm, dtl = low_from_sdf(name + "_Rock", getattr(fn, "low", fn), coarse, lo, hi, target,
                                    band=h * 6 + 0.25 * max(hi - lo))
        recentre(high, low)
        size = max(hi - lo)
        unique.append((name, high, low, "rock", 0.02 * size + 0.02, 0.08 * size + 0.1))
        log("ROCK %s high %d faces (%.1fs) -> low %d tris" % (name, len(high.data.polygons), dt, tg.tri_count(low)))
    # ---------------------------------------------------------------- RockFlat: tabular slab
    rng = np.random.RandomState(320)
    fn, coarse, lo, hi = slab_fn(rng, (10.0, 7.4), 1.3, 0.5)
    high, dt = sdf_object("RockFlat_high", fn, coarse, lo, hi, 0.04, band=0.5)
    high.data.materials.append(rock_material("RM_RockFlat", moss=0.8, lichen=1.0, damp=1.0, streak=0.2, seed_w=71.0))
    low, hm, dtl = low_from_sdf("RockFlat_Rock", fn, coarse, lo, hi, 950, band=0.5)
    recentre(high, low)
    unique.append(("RockFlat", high, low, "rock", 0.08, 0.5))
    log("ROCK RockFlat high %d faces (%.1fs) -> low %d" % (len(high.data.polygons), dt, tg.tri_count(low)))
    # ---------------------------------------------------------------- ScreeA
    rng = np.random.RandomState(330)
    fn, coarse, lo, hi = heap_fn(rng, 70, (8.0, 6.6), 2.5, 0.3, (0.45, 1.25))
    scree, hm, dtl = low_from_sdf("ScreeA_Rock", fn, coarse, lo, hi, 1950, band=0.3, crease_deg=50.0,
                                  normals="loop")           # flat fragment faces: crisp corners
    co = tg.vertex_coords(scree.data)
    vis = co[co[:, 2] > 0.1]
    scree.data.transform(Matrix.Translation((-(vis[:, 0].min() + vis[:, 0].max()) / 2,
                                             -(vis[:, 1].min() + vis[:, 1].max()) / 2, 0)))
    box_tile_uvs(scree, TILE_STUDS, rng)
    log("ROCK ScreeA tiled granite, low %d tris (%.1fs)" % (tg.tri_count(scree), dtl))
    # ---------------------------------------------------------------- RiverStones: big stones (Hull each) + pebbles
    rng = np.random.RandomState(340)
    river = []
    big = [((2.4, 1.8), 0.95), ((1.9, 1.5), 0.8), ((1.6, 1.25), 0.62), ((1.35, 1.1), 0.55)]
    placed = []
    for j, (sz, ht) in enumerate(big):
        for _ in range(50):
            p = np.array([rng.uniform(-2.6, 2.6), rng.uniform(-1.8, 1.8)])
            if all(np.linalg.norm(p - q) > (max(sz) + s2) * 0.55 for q, s2 in placed):
                break
        placed.append((p, max(sz)))
        f_, c_, lo_, hi_ = pebble_fn(rng, sz, ht, 0.25)
        hs, dt = sdf_object("RS_big%d_high" % j, f_, c_, lo_, hi_, 0.03, band=0.2)
        lw, hm, dtl = low_from_sdf("RS_big%d" % j, f_, c_, lo_, hi_, 300, band=0.2)
        yaw = rng.uniform(0, 6.28)          # one yaw for the pair: the bake needs high and low aligned
        for o in (hs, lw):
            o.location = (p[0], p[1], 0)
            o.rotation_euler = (0, 0, yaw)
        river.append(("big", hs, lw))
    pebbles = []
    for j in range(22):
        for _ in range(60):
            p = np.array([rng.uniform(-3.6, 3.6), rng.uniform(-2.6, 2.6)])
            s = rng.uniform(0.25, 0.75)
            if all(np.linalg.norm(p - q) > (s + s2) * 0.5 for q, s2 in placed):
                break
        placed.append((p, s))
        f_, c_, lo_, hi_ = pebble_fn(rng, (s, s * rng.uniform(0.6, 0.9)), s * rng.uniform(0.3, 0.5), 0.08)
        hs, dt = sdf_object("RS_peb%d_high" % j, f_, c_, lo_, hi_, 0.02, band=0.08)
        lw, hm, dtl = low_from_sdf("RS_peb%d" % j, f_, c_, lo_, hi_, 44 if s < 0.45 else 64, band=0.08)
        yaw = rng.uniform(0, 6.28)          # one yaw for the pair: the bake needs high and low aligned
        for o in (hs, lw):
            o.location = (p[0], p[1], 0)
            o.rotation_euler = (0, 0, yaw)
        pebbles.append((hs, lw))
    rmat = rock_material("RM_River", moss=0.25, lichen=0.0, damp=1.0, streak=0.0, river=1.0, bump=0.7)
    for _, hs, lw in river:
        hs.data.materials.append(rmat)
    for hs, lw in pebbles:
        hs.data.materials.append(rmat)
    for _, hs, lw in river:
        apply_transform(hs)
        apply_transform(lw)
    for hs, lw in pebbles:
        apply_transform(hs)
        apply_transform(lw)
    # one pebble object (low) and one high: a single bake pair instead of 22, and Blender's join keeps the
    # custom normals the bake's tangent space is built on
    pebbles = [(join_ops([hs for hs, lw in pebbles], "RS_pebbles_high"),
                join_ops([lw for hs, lw in pebbles], "RiverStones_Pebbles"))]
    log("ROCK RiverStones %d stones + %d pebble tris" % (len(river), tg.tri_count(pebbles[0][1])))
    # ---------------------------------------------------------------- unwrap + pack pages
    lows_unique = [u[2] for u in unique] + [r[2] for r in river] + [p[1] for p in pebbles]
    for lw in lows_unique:
        smart_uv(lw, 62.0)
    pages = {}
    for u in unique:
        pg = pages.setdefault(PAGE_OF[u[0]], {"objs": [], "pairs": []})
        pg["objs"].append(u[2])
        pg["pairs"].append((u[1], u[2], u[4], u[5]))
    rp = pages.setdefault(PAGE_OF["RiverStones"], {"objs": [], "pairs": []})
    rp["objs"] += [r[2] for r in river] + [p[1] for p in pebbles]
    rp["pairs"] += [(hs, lw, 0.03, 0.15) for _, hs, lw in river] + [(hs, lw, 0.02, 0.08) for hs, lw in pebbles]
    dens = {}
    for page in sorted(pages):
        pack_page(pages[page]["objs"])
        dens[page] = uv_density(pages[page]["objs"])
    log("PAGES texel density: " + ", ".join("%s %.1f px/stud" % (k, v) for k, v in sorted(dens.items())))
    for page in sorted(pages):
        lib.sets[page]["avg"] = bake_page(page, pages[page]["pairs"], tex_dir, cache, log)
        lib.sets[page]["pxPerStud"] = round(dens[page], 1)
    with open(os.path.join(cache, SETS_FILE), "w", encoding="utf-8") as f:
        json.dump({k: v for k, v in lib.sets.items() if k in FILES}, f, indent=1)
    lib.notes.append("Rock texel density: " + ", ".join("%s %.0f px/stud" % (k, v) for k, v in sorted(dens.items()))
                     + ", Granite tile %.0f px/stud (%d px over %g studs)" % (TILE_RES / TILE_STUDS, TILE_RES,
                                                                               TILE_STUDS))
    # ---------------------------------------------------------------- register unique assets
    info = {
        "BoulderA": ("Rock", ["Boulder", "Cover"], "Small granite boulder; sink 0.1-0.3."),
        "BoulderB": ("Rock", ["Boulder", "Cover"], "Split granite boulder (crack through the body)."),
        "BoulderC": ("Rock", ["Boulder", "Cover"], "Large weathered granite boulder with exfoliated, mossy top."),
        "BoulderD": ("Rock", ["Boulder", "Cover", "Climbable?"], "Big glacial erratic, mossy top; hip-high ledges."),
        "RockFlat": ("Rock", ["Slab", "Walkable"], "Low tabular slab, walkable top at ~1.3."),
    }
    page_of = {u[0]: PAGE_OF[u[0]] for u in unique}
    order = ["BoulderA", "BoulderB", "BoulderC", "BoulderD", "RockFlat"]
    for name in order:
        u = [x for x in unique if x[0] == name][0]
        kind, tags, notes = info[name]
        root = lib.begin(name, kind, tags, notes, budget=2000)
        low = u[2]
        bpy.data.objects.remove(u[1], do_unlink=True)
        lib.add(root, low, "Rock", page_of[name], collide=True, collision="Hull", cast_shadow=True, alpha="Overlay")
        lib.finish(root, buried_ok=1.4)
    root = lib.begin("ScreeA", "Rock", ["Scree", "Pile"],
                     "Pile of angular granite fragments for cliff feet and slopes. Tiling GR_Granite set (the same "
                     "surface as the cliffs above it), crisp per-corner normals.", budget=2000)
    lib.add(root, scree, "Rock", "Granite", collide=True, collision="Hull", cast_shadow=True, alpha="Overlay")
    lib.finish(root, buried_ok=1.4)
    root = lib.begin("RiverStones", "Rock", ["RiverStones", "Shore", "Ford"],
                     "Smooth river-worn stones for banks and fords: the 4 big stones are separate Hull parts (no "
                     "bridging between them); pebbles are one non-colliding part.", budget=2400)
    for _, hs, lw in river:
        bpy.data.objects.remove(hs, do_unlink=True)
        lib.add(root, lw, "Stone", PAGE_OF["RiverStones"], collide=True, collision="Hull", cast_shadow=True, alpha="Overlay")
    peb_high, peb = pebbles[0]
    bpy.data.objects.remove(peb_high, do_unlink=True)
    lib.add(root, peb, "Pebbles", PAGE_OF["RiverStones"], alpha="Overlay", name="RiverStones_Pebbles")
    lib.finish(root, buried_ok=0.4)
    # ---------------------------------------------------------------- tiled pieces
    build_tiled(lib, S, log)
    log("ROCKS all in %.0fs" % (time.time() - t_all))


def recentre(high, low):
    co = tg.vertex_coords(low.data)
    vis = co[co[:, 2] > 0.1]
    cx = (vis[:, 0].min() + vis[:, 0].max()) / 2
    cy = (vis[:, 1].min() + vis[:, 1].max()) / 2
    for o in (high, low):
        o.data.transform(Matrix.Translation((-cx, -cy, 0)))


def apply_transform(obj):
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)


def join_ops(objs, name):
    """Join with Blender's operator (keeps UVs, materials and custom split normals)."""
    _select_only(objs, objs[0])
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def join_objects(objs, name):
    bm = bmesh.new()
    uvname = None
    for o in objs:
        me = o.data.copy()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


TILED = {
    "CliffFaceA": dict(W=27.0, H=19.0, D=12.0, bury=2.5, layers=[1.8, 4.8, 2.2, 5.6, 1.6, 6.0], joints=6,
                       talus=3, target=4200, h=0.22, seed=401, overhang=0.9, ledge=1.6),
    "CliffFaceB": dict(W=38.0, H=28.0, D=15.0, bury=3.0, layers=[2.0, 5.6, 1.6, 4.4, 6.4, 2.2, 5.0, 3.8],
                       joints=8, talus=4, target=6200, h=0.26, seed=402, overhang=1.1, ledge=2.0),
    "CliffFaceC": dict(W=48.0, H=40.0, D=18.0, bury=3.0, layers=[2.2, 6.4, 1.6, 3.8, 7.2, 2.4, 4.6, 1.8, 6.6,
                                                                 3.4, 3.0], joints=10, talus=5, target=6900, h=0.3,
                       seed=403, overhang=1.3, ledge=2.3),
    "RockOutcrop": dict(W=14.0, H=4.8, D=9.0, bury=1.2, layers=[2.4, 2.0, 1.6], joints=3, talus=2,
                        target=2450, h=0.12, seed=404, overhang=0.4, ledge=1.2, lean=0.45, taper=0.5, back=0.9,
                        soft=0.0, block_tilt=0.22, wave=0.7),
    "CaveMouth": dict(W=36.0, H=22.0, D=16.0, bury=2.0, layers=[2.4, 5.2, 1.8, 4.6, 6.4, 3.6], joints=6,
                      talus=2, target=7000, h=0.24, seed=405, overhang=1.0, ledge=1.6,
                      tunnel=(18.0, 10.4, 14.0, 0.3)),
}


def build_tiled(lib, S, log=print):
    import gr_flora
    for name, sp in TILED.items():
        rng = np.random.RandomState(sp["seed"])
        t = time.time()
        fn, coarse, lo, hi = strata_fn(rng, sp["W"], sp["H"], sp["D"], sp["bury"], sp["layers"],
                                       **strata_kwargs(name, sp))
        low, hm, dtl = low_from_sdf(name + "_Rock", fn, coarse, lo, hi, sp["target"], band=1.6, prefactor=2.2,
                                    crease_deg=55.0, normals="loop")
        # centre the footprint of the visible part on the origin (front stays +Y)
        co = tg.vertex_coords(low.data)
        vis = co[co[:, 2] > 0.2]
        cx = (vis[:, 0].min() + vis[:, 0].max()) / 2
        cy = (vis[:, 1].min() + vis[:, 1].max()) / 2
        low.data.transform(Matrix.Translation((-cx, -cy, 0)))
        box_tile_uvs(low, TILE_STUDS, rng)
        moss = gr_flora.Part(S)
        nm = moss_shells(moss, low, rng, S, count={"CliffFaceA": 10, "CliffFaceB": 14, "CliffFaceC": 15,
                                                     "RockOutcrop": 7, "CaveMouth": 12}[name], grid=6,
                         r_rng=(0.8, 1.7) if name != "RockOutcrop" else (0.7, 1.4))
        kind = "Cliff" if name.startswith("Cliff") else ("CaveMouth" if name == "CaveMouth" else "Rock")
        notes = {
            "CliffFaceA": "Stratified granite/gneiss cliff chunk 27 x 19; steep layered face (front, Roblox -Z) with "
                          "walkable ledges, back slopes down to bury 4-8 studs into the hillside.",
            "CliffFaceB": "Stratified cliff chunk 38 x 28 with ledges, overhangs and V-notched joints.",
            "CliffFaceC": "Big stratified crag 48 x 40 for the gorge and highland walls.",
            "RockOutcrop": "Low forest-floor bedrock outcrop (stepped strata, mossy top); climbable steps.",
            "CaveMouth": "Rock arch/overhang shell framing a terrain cave: opening ~18 wide x ~10.5 high at the "
                         "front narrowing inward over 14 studs; floor is terrain; back buries into the hillside.",
        }[name]
        tags = {"Cliff": ["Cliff", "Ledges"], "CaveMouth": ["Cave", "Arch"], "Rock": ["Outcrop", "Cover"]}[kind]
        root = lib.begin(name, kind, tags, notes, budget=8000 if kind != "Rock" else 3000)
        coll = "PreciseConvexDecomposition" if name != "RockOutcrop" else "Hull"
        lib.add(root, low, "Rock", "Granite", collide=True, collision=coll, cast_shadow=True, alpha="Overlay",
                fidelity="Automatic")
        if nm:
            mo = moss.build(name + "_Moss")
            lib.add(root, mo, "Moss", "Shrubs", alpha="Transparency", tags=["Decal"],
                    rgb=gr_flora.slot_rgb(S, ["moss_a", "moss_b"]))
        if name == "CaveMouth":
            lib.attach(root, "CaveEntrance", (-cx, sp["D"] * 0.35 - cy - 1.0, 0.0), look=(0, -1, 0), up=(0, 0, 1))
        lib.finish(root, buried_ok=sp["bury"] + 0.5)
        log("TILED %s low %d tris, %d moss cushions (%.0fs)" % (name, tg.tri_count(low), nm, time.time() - t))
