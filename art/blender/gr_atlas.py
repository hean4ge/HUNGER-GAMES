"""
gr_atlas.py - renders the GroundReal flora card atlases (texture from geometry), Blender 5.3 headless.

Two 1024 pages, each written as Color (RGBA, alpha cut-out, colour bled into transparent pixels), Normal (OpenGL,
+Y up, tangent space of a card whose U = +X and V = +Y) and Roughness (gray):
  GR_Plants_*  grasses, reeds, cattail leaves, sword fern fronds, bracken blade, wildflowers, flower heads, stems
  GR_Shrubs_*  evergreen / broadleaf / currant / beech sprays, leaf fills, moss, bark, mushroom, berry, litter
Each slot is rendered on its own (orthographic Cycles, 2x supersampled, emission-only data passes) and composed.
The slot layout with trimmed rects, densities (px per stud) and anchors is written to GR_Atlas_Layout.json; the
card generators map UVs from it.
"""
import json
import math
import os
import time

import bpy
import numpy as np

import gr_elements as el
import tex_ground as tg

PAGE = 1024
SS = 2


# =============================================================================================== node helpers
class NT:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nodes = self.nt.nodes
        self.links = self.nt.links

    def n(self, kind, **kw):
        node = self.nodes.new(kind)
        for k, v in kw.items():
            setattr(node, k, v)
        return node

    def _in(self, sock, val):
        if isinstance(val, bpy.types.NodeSocket):
            self.links.new(val, sock)
        else:
            dv = sock.default_value
            if hasattr(dv, "__len__") and not hasattr(val, "__len__"):
                val = [val] * len(dv)
            sock.default_value = val

    def math(self, op, a, b=0.0, c=0.0, clamp=False):
        node = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._in(node.inputs[0], a)
        self._in(node.inputs[1], b)
        self._in(node.inputs[2], c)
        return node.outputs[0]

    def vmath(self, op, a, b=None, c=None, scale=None):
        node = self.n("ShaderNodeVectorMath", operation=op)
        self._in(node.inputs[0], a)
        if b is not None:
            self._in(node.inputs[1], b)
        if c is not None:
            self._in(node.inputs[2], c)
        if scale is not None:
            self._in([s for s in node.inputs if s.identifier == "Scale"][0], scale)
        if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE"):
            return node.outputs["Value"]
        return node.outputs["Vector"]

    def mapr(self, v, a, b, c=0.0, d=1.0, smooth=True):
        node = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP" if smooth else "LINEAR", clamp=True)
        self._in(node.inputs["Value"], v)
        node.inputs["From Min"].default_value = a
        node.inputs["From Max"].default_value = b
        node.inputs["To Min"].default_value = c
        node.inputs["To Max"].default_value = d
        return node.outputs["Result"]

    def attr(self, name):
        return self.n("ShaderNodeAttribute", attribute_name=name, attribute_type="GEOMETRY")

    def noise(self, vec, scale, detail=4.0, rough=0.55, dist=0.0, dims="3D"):
        node = self.n("ShaderNodeTexNoise", noise_dimensions=dims)
        self._in(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        node.inputs["Distortion"].default_value = dist
        return node

    def voronoi(self, vec, scale, feature="F1", rand=1.0, dims="3D"):
        node = self.n("ShaderNodeTexVoronoi", voronoi_dimensions=dims, feature=feature)
        self._in(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = scale
        node.inputs["Randomness"].default_value = rand
        return node

    def mixc(self, a, b, fac):
        """lerp of colours/vectors: a + (b - a) * fac."""
        diff = self.vmath("SUBTRACT", b, a)
        return self.vmath("ADD", a, self.vmath("SCALE", diff, scale=fac))

    def color(self, rgb_lin):
        node = self.n("ShaderNodeRGB")
        node.outputs[0].default_value = (float(rgb_lin[0]), float(rgb_lin[1]), float(rgb_lin[2]), 1.0)
        return node.outputs[0]


def finish_pass_material(nt, alb, nrm, rough, alpha=None):
    """Common tail: facing normal encode, AO, rough+AO pack, emission pass switch (reroutes named PASS_*)."""
    geo = nt.n("ShaderNodeNewGeometry")
    dot = nt.vmath("DOT_PRODUCT", nrm, geo.outputs["Incoming"])
    sgn = nt.math("SIGN", dot)
    sgn = nt.math("ADD", nt.math("MULTIPLY", nt.math("COMPARE", sgn, 0.0, 0.0), 1.0), sgn)   # sign(0) -> 1
    nf = nt.vmath("SCALE", nrm, scale=sgn)
    enc = nt.vmath("MULTIPLY_ADD", nf, (0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
    ao = nt.n("ShaderNodeAmbientOcclusion", name="PASS_AO", samples=16, inside=False, only_local=False)
    ao.inputs["Distance"].default_value = 0.2
    comb = nt.n("ShaderNodeCombineColor")
    nt._in(comb.inputs[0], rough)
    nt.links.new(ao.outputs["AO"], comb.inputs[1])
    comb.inputs[2].default_value = 0.0
    r_alb = nt.n("NodeReroute", name="PASS_ALB")
    r_nrm = nt.n("NodeReroute", name="PASS_NRM")
    r_ra = nt.n("NodeReroute", name="PASS_RA")
    nt.links.new(alb, r_alb.inputs[0])
    nt.links.new(enc, r_nrm.inputs[0])
    nt.links.new(comb.outputs[0], r_ra.inputs[0])
    emit = nt.n("ShaderNodeEmission", name="PASS_EMIT")
    emit.inputs["Strength"].default_value = 1.0
    out = nt.n("ShaderNodeOutputMaterial")
    if alpha is not None:
        tr = nt.n("ShaderNodeBsdfTransparent")
        mixs = nt.n("ShaderNodeMixShader")
        nt._in(mixs.inputs[0], alpha)
        nt.links.new(tr.outputs[0], mixs.inputs[1])
        nt.links.new(emit.outputs[0], mixs.inputs[2])
        nt.links.new(mixs.outputs[0], out.inputs["Surface"])
    else:
        nt.links.new(emit.outputs[0], out.inputs["Surface"])
    nt.links.new(r_alb.outputs[0], emit.inputs["Color"])


def new_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        bpy.data.materials.remove(mat)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    return mat, NT(mat)


def make_elem_material():
    """Attribute-driven material for modelled elements: albedo/rough per vertex, leaf veins from lu/lv."""
    mat, nt = new_material("GR_Elem")
    alb = nt.attr("albedo").outputs["Color"]
    rough = nt.attr("rough").outputs["Fac"]
    lu = nt.attr("lu").outputs["Fac"]
    lv = nt.attr("lv").outputs["Fac"]
    vein = nt.attr("vein").outputs["Fac"]
    nvein = nt.attr("nvein").outputs["Fac"]
    vmode = nt.attr("vmode").outputs["Fac"]
    au = nt.math("ABSOLUTE", lu)
    mid = nt.mapr(au, 0.0, 0.08, 1.0, 0.0)
    ph = nt.math("SUBTRACT", nt.math("MULTIPLY", lv, nvein), nt.math("MULTIPLY", nt.math("MULTIPLY", au, nvein), 0.45))
    f = nt.math("FRACT", ph)
    d = nt.math("MINIMUM", f, nt.math("SUBTRACT", 1.0, f))
    lat = nt.math("MULTIPLY", nt.mapr(d, 0.0, 0.1, 1.0, 0.0), nt.mapr(au, 0.7, 1.0, 1.0, 0.0))
    pp = nt.math("FRACT", nt.math("MULTIPLY", nt.math("MULTIPLY_ADD", lu, 0.5, 0.5), nvein))
    pd = nt.math("MINIMUM", pp, nt.math("SUBTRACT", 1.0, pp))
    par = nt.mapr(pd, 0.0, 0.2, 1.0, 0.0)
    pin = nt.math("MULTIPLY_ADD", lat, 0.65, mid)
    parm = nt.math("MULTIPLY_ADD", par, 0.5, nt.math("MULTIPLY", mid, 0.4))
    vm = nt.math("MULTIPLY", vein, nt.math("ADD", pin, nt.math("MULTIPLY", nt.math("SUBTRACT", parm, pin), vmode)))
    alb_v = nt.vmath("SCALE", alb, scale=nt.math("MULTIPLY_ADD", vm, 0.26, 1.0))
    bump = nt.n("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.004
    nt._in(bump.inputs["Height"], nt.math("MULTIPLY", vm, -1.0))
    finish_pass_material(nt, alb_v, bump.outputs["Normal"], rough)
    return mat


def make_proc_material(kind):
    """Procedural flat regions: bark, mush_cap, mush_gills, mush_stem, berry, stem_green, stem_brown, cattail_head,
    reed_culm. Object coordinates are studs in element space."""
    mat, nt = new_material("GR_Proc_" + kind)
    tc = nt.n("ShaderNodeTexCoord")
    P = tc.outputs["Object"]
    C = tg.rgb
    rough = 0.7
    height = None
    if kind == "bark":
        streak = nt.noise(nt.vmath("MULTIPLY", P, (9.0, 0.5, 9.0)), 4.0, 6, 0.6).outputs["Fac"]
        big = nt.noise(P, 0.9, 3, 0.5).outputs["Fac"]
        vor = nt.voronoi(nt.vmath("MULTIPLY", P, (1.0, 3.2, 1.0)), 9.0, "F1", 0.95)
        lent = nt.mapr(vor.outputs["Distance"], 0.05, 0.16, 1.0, 0.0)
        lent = nt.math("MULTIPLY", lent, nt.mapr(nt.noise(P, 6.0, 2).outputs["Fac"], 0.42, 0.58, 0.0, 1.0))
        base = nt.mixc(nt.color(C(118, 106, 94)), nt.color(C(108, 112, 96)), nt.mapr(big, 0.35, 0.65))
        base = nt.vmath("SCALE", base, scale=nt.mapr(streak, 0.3, 0.7, 0.78, 1.08, False))
        alb = nt.mixc(base, nt.color(C(168, 148, 116)), nt.math("MULTIPLY", lent, 0.85))
        fine = nt.noise(P, 60.0, 4, 0.6).outputs["Fac"]
        height = nt.math("ADD", nt.math("MULTIPLY", lent, 0.6), nt.math("MULTIPLY", nt.math("SUBTRACT", streak, 0.5), 0.8))
        height = nt.math("ADD", height, nt.math("MULTIPLY", fine, 0.15))
        rough = nt.mapr(lent, 0.0, 1.0, 0.78, 0.9)
    elif kind in ("mush_cap", "mush_gills"):
        r = nt.math("DIVIDE", nt.vmath("LENGTH", nt.vmath("MULTIPLY", P, (1.0, 1.0, 0.0))), 0.24)
        sep = nt.n("ShaderNodeSeparateXYZ")
        nt.links.new(P, sep.inputs[0])
        ang = nt.math("ARCTAN2", sep.outputs[1], sep.outputs[0])
        if kind == "mush_cap":
            cx = nt.n("ShaderNodeCombineXYZ")
            nt._in(cx.inputs[0], nt.math("MULTIPLY", ang, 9.0))
            nt._in(cx.inputs[1], nt.math("MULTIPLY", r, 2.0))
            fib = nt.noise(cx.outputs[0], 3.0, 5, 0.6).outputs["Fac"]
            centre = nt.mixc(nt.color(C(84, 56, 34)), nt.color(C(156, 112, 66)), nt.mapr(r, 0.05, 0.7))
            rim = nt.mixc(centre, nt.color(C(196, 168, 124)), nt.mapr(r, 0.78, 1.0))
            alb = nt.vmath("SCALE", rim, scale=nt.mapr(fib, 0.3, 0.7, 0.86, 1.1, False))
            scale_v = nt.voronoi(P, 70.0, "F1", 1.0).outputs["Distance"]
            scales = nt.math("MULTIPLY", nt.mapr(scale_v, 0.0, 0.25, 1.0, 0.0), nt.mapr(r, 0.1, 0.6, 1.0, 0.0))
            alb = nt.mixc(alb, nt.color(C(70, 46, 30)), nt.math("MULTIPLY", scales, 0.6))
            height = nt.math("ADD", nt.math("MULTIPLY", fib, 0.4), nt.math("MULTIPLY", scales, 0.5))
            rough = 0.55
        else:
            gill = nt.math("ABSOLUTE", nt.math("SINE", nt.math("MULTIPLY", ang, 48.0)))
            gill = nt.mapr(gill, 0.0, 0.6, 1.0, 0.0)
            alb = nt.mixc(nt.color(C(208, 190, 156)), nt.color(C(118, 96, 72)), nt.math("MULTIPLY", gill, 0.8))
            alb = nt.mixc(alb, nt.color(C(196, 182, 152)), nt.mapr(r, 0.12, 0.05))
            height = nt.math("MULTIPLY", gill, -1.0)
            rough = 0.7
    elif kind == "mush_stem":
        streak = nt.noise(nt.vmath("MULTIPLY", P, (14.0, 1.0, 14.0)), 6.0, 5, 0.6).outputs["Fac"]
        sep = nt.n("ShaderNodeSeparateXYZ")
        nt.links.new(P, sep.inputs[0])
        alb = nt.mixc(nt.color(C(142, 112, 80)), nt.color(C(214, 200, 174)), nt.mapr(sep.outputs[1], 0.0, 0.45))
        alb = nt.vmath("SCALE", alb, scale=nt.mapr(streak, 0.3, 0.7, 0.88, 1.06, False))
        height = streak
        rough = 0.65
    elif kind == "berry":
        r = nt.math("DIVIDE", nt.vmath("LENGTH", nt.vmath("MULTIPLY", P, (1.0, 1.0, 0.0))), 0.09)
        spec = nt.noise(P, 120.0, 2).outputs["Fac"]
        alb = nt.mixc(nt.color(C(196, 42, 40)), nt.color(C(128, 16, 26)), nt.mapr(r, 0.0, 1.0))
        alb = nt.vmath("SCALE", alb, scale=nt.mapr(spec, 0.4, 0.6, 0.94, 1.04, False))
        calyx = nt.mapr(r, 0.12, 0.2, 1.0, 0.0)
        alb = nt.mixc(alb, nt.color(C(58, 40, 30)), calyx)
        height = nt.math("MULTIPLY", calyx, -1.0)
        rough = nt.mapr(calyx, 0.0, 1.0, 0.24, 0.7)
    elif kind in ("stem_green", "stem_brown", "reed_culm"):
        streak = nt.noise(nt.vmath("MULTIPLY", P, (30.0, 1.0, 30.0)), 4.0, 4, 0.6).outputs["Fac"]
        col = {"stem_green": C(84, 108, 48), "stem_brown": C(104, 84, 54), "reed_culm": C(160, 148, 96)}[kind]
        alb = nt.vmath("SCALE", nt.color(col), scale=nt.mapr(streak, 0.3, 0.7, 0.85, 1.1, False))
        height = streak
        rough = 0.55
    elif kind == "cattail_head":
        fine = nt.noise(P, 220.0, 3, 0.7).outputs["Fac"]
        big = nt.noise(P, 9.0, 3, 0.5).outputs["Fac"]
        alb = nt.mixc(nt.color(C(96, 64, 42)), nt.color(C(74, 50, 34)), nt.mapr(big, 0.35, 0.65))
        alb = nt.vmath("SCALE", alb, scale=nt.mapr(fine, 0.35, 0.65, 0.82, 1.15, False))
        height = fine
        rough = 0.95
    else:
        raise ValueError(kind)
    bump = nt.n("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    bump.inputs["Distance"].default_value = 0.003
    nt._in(bump.inputs["Height"], height)
    finish_pass_material(nt, alb, bump.outputs["Normal"], rough)
    return mat


def set_pass(kind, ao_dist=None):
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        nodes = mat.node_tree.nodes
        emit = nodes.get("PASS_EMIT")
        if emit is None:
            continue
        src = nodes.get({"alb": "PASS_ALB", "nrm": "PASS_NRM", "ra": "PASS_RA"}[kind])
        mat.node_tree.links.new(src.outputs[0], emit.inputs["Color"])
        if ao_dist is not None:
            nodes["PASS_AO"].inputs["Distance"].default_value = ao_dist


# =============================================================================================== element renders
def _clear_elements():
    for o in list(bpy.data.objects):
        if o.get("gr_elem"):
            bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


def _flat(kind, x0, y0, x1, y1, shape="rect", z=0.0):
    """A flat plane/disc element with a procedural material."""
    mat = bpy.data.materials.get("GR_Proc_" + kind) or make_proc_material(kind)
    if shape == "disc":
        n = 64
        cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2
        V = [(cx, cy, z)] + [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z)
                             for i in range(n)]
        F = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    else:
        V = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
        F = [(0, 1, 2, 3)]
    ob = tg.mesh_object("GR_flat_" + kind, np.array(V), F)
    ob.data.materials.append(mat)
    ob["gr_elem"] = True
    return ob


def render_slot(scene, spec, tmp_dir, log=print):
    """Render one slot -> dict with 'rgba' (linear albedo + alpha), 'nrm' (encoded), 'ra' (rough, ao) at slot px."""
    _clear_elements()
    W, H = spec["studs"]
    ax, ay = spec["anchor"]
    pw, ph = spec["px"][2], spec["px"][3]
    rng = np.random.RandomState(spec.get("seed", 1))
    t0 = time.time()
    objs = []
    if "flat" in spec:
        for f in spec["flat"]:
            objs.append(_flat(*f))
    else:
        mb = spec["build"](rng)
        ob = mb.build("GR_elem_" + spec["name"])
        ob["gr_elem"] = True
        ob.data.materials.append(bpy.data.materials["GR_Elem"])
        objs.append(ob)
    tg.data_render_settings(scene, pw * SS, ph * SS, samples=spec.get("samples", 24))
    tg.ortho_camera(scene, -ax, -ay, W - ax, H - ay, z=20.0)
    out = {}
    for kind in ("alb", "nrm", "ra"):
        set_pass(kind, spec.get("ao", 0.15))
        img = tg.render_exr(scene, os.path.join(tmp_dir, "slot_%s_%s.exr" % (spec["name"], kind)))
        out[kind] = img
    a = out["alb"][..., 3:4]
    un = lambda x: np.where(a > 1e-4, x[..., :3] / np.maximum(a, 1e-4), 0.0)
    alb = np.concatenate([un(out["alb"]), a], 2)
    nrm = np.concatenate([un(out["nrm"]), a], 2)
    ra = np.concatenate([un(out["ra"]), a], 2)
    res = {"rgba": tg.downsample2(alb), "nrm": tg.downsample2(nrm), "ra": tg.downsample2(ra)}
    log("SLOT %-16s %4dx%-4d %.1fs" % (spec["name"], pw, ph, time.time() - t0))
    return res


# =============================================================================================== layouts
E = el


def _heads(rng):
    raise RuntimeError("heads are rendered per cell")


PLANTS = [
    dict(name="grass_tall_a", px=(0, 512, 256, 512), studs=(2.0, 4.0), anchor=(1.0, 0.0), ao=0.12, seed=11,
         build=lambda r: E.build_grass_tall(r, "a")),
    dict(name="grass_tall_b", px=(256, 512, 256, 512), studs=(2.0, 4.0), anchor=(1.0, 0.0), ao=0.12, seed=12,
         build=lambda r: E.build_grass_tall(r, "b")),
    dict(name="reed", px=(512, 512, 128, 512), studs=(1.6, 6.4), anchor=(0.8, 0.0), ao=0.15, seed=13,
         build=E.build_reed),
    dict(name="cattail", px=(640, 512, 128, 512), studs=(1.4, 5.6), anchor=(0.7, 0.0), ao=0.12, seed=14,
         build=E.build_cattail_leaves),
    dict(name="swordfern_a", px=(768, 512, 128, 512), studs=(0.75, 3.0), anchor=(0.375, 0.0), ao=0.05, seed=15,
         build=lambda r: E.build_sword_fern(r, "a")),
    dict(name="swordfern_b", px=(896, 512, 128, 512), studs=(0.75, 3.0), anchor=(0.375, 0.0), ao=0.05, seed=16,
         build=lambda r: E.build_sword_fern(r, "b")),
    dict(name="bracken", px=(0, 128, 384, 384), studs=(2.4, 2.4), anchor=(1.2, 0.05), ao=0.06, seed=17,
         build=E.build_bracken),
    dict(name="grass_forest_a", px=(384, 256, 256, 256), studs=(1.6, 1.6), anchor=(0.8, 0.0), ao=0.08, seed=18,
         build=lambda r: E.build_grass_forest(r, "a")),
    dict(name="grass_forest_b", px=(384, 0, 256, 256), studs=(1.6, 1.6), anchor=(0.8, 0.0), ao=0.08, seed=19,
         build=lambda r: E.build_grass_forest(r, "b")),
    dict(name="flowers_a", px=(640, 256, 256, 256), studs=(1.8, 1.8), anchor=(0.9, 0.0), ao=0.08, seed=20,
         build=lambda r: E.build_flowers(r, "a")),
    dict(name="flowers_b", px=(640, 0, 256, 256), studs=(1.8, 1.8), anchor=(0.9, 0.0), ao=0.08, seed=21,
         build=lambda r: E.build_flowers(r, "b")),
    dict(name="stem_green", px=(896, 256, 32, 256), studs=(0.1, 0.8), anchor=(0.0, 0.0),
         flat=[("stem_green", 0.0, 0.0, 0.1, 0.8)]),
    dict(name="stem_brown", px=(928, 256, 32, 256), studs=(0.1, 0.8), anchor=(0.0, 0.0),
         flat=[("stem_brown", 0.0, 0.0, 0.1, 0.8)]),
    dict(name="cattail_head", px=(960, 256, 32, 256), studs=(0.1, 0.8), anchor=(0.0, 0.0),
         flat=[("cattail_head", 0.0, 0.0, 0.1, 0.8)]),
    dict(name="reed_culm", px=(992, 256, 32, 256), studs=(0.1, 0.8), anchor=(0.0, 0.0),
         flat=[("reed_culm", 0.0, 0.0, 0.1, 0.8)]),
]
HEAD_KINDS = ["daisy", "daisy", "buttercup", "buttercup", "knapweed", "yarrow",
              "clover", "harebell", "daisy", "buttercup", "knapweed", "clover"]
for _i, _k in enumerate(HEAD_KINDS):
    PLANTS.append(dict(name="head_%d_%s" % (_i, _k), px=(64 * (_i % 6), 64 * (1 - _i // 6), 64, 64),
                       studs=(0.24, 0.24), anchor=(0.12, 0.12), ao=0.02, seed=40 + _i,
                       build=(lambda k: (lambda r: E.build_flower_head_top(r, k)))(_k)))

SHRUBS = [
    dict(name="evergreen_a", px=(0, 768, 256, 256), studs=(1.2, 1.2), anchor=(0.6, 0.0), ao=0.06, seed=61,
         build=lambda r: E.leafy_sprig(r, "evergreen_a")),
    dict(name="evergreen_b", px=(256, 768, 256, 256), studs=(1.2, 1.2), anchor=(0.6, 0.0), ao=0.06, seed=62,
         build=lambda r: E.leafy_sprig(r, "evergreen_b")),
    dict(name="broadleaf_a", px=(512, 768, 256, 256), studs=(1.4, 1.4), anchor=(0.7, 0.0), ao=0.06, seed=63,
         build=lambda r: E.leafy_sprig(r, "broadleaf_a")),
    dict(name="broadleaf_b", px=(768, 768, 256, 256), studs=(1.4, 1.4), anchor=(0.7, 0.0), ao=0.06, seed=64,
         build=lambda r: E.leafy_sprig(r, "broadleaf_b")),
    dict(name="currant", px=(0, 512, 256, 256), studs=(1.4, 1.4), anchor=(0.7, 0.0), ao=0.06, seed=65,
         build=lambda r: E.leafy_sprig(r, "currant")),
    dict(name="beech_a", px=(256, 512, 256, 256), studs=(1.6, 1.6), anchor=(0.8, 0.0), ao=0.06, seed=66,
         build=lambda r: E.leafy_sprig(r, "beech_a")),
    dict(name="beech_b", px=(512, 512, 256, 256), studs=(1.6, 1.6), anchor=(0.8, 0.0), ao=0.06, seed=67,
         build=lambda r: E.leafy_sprig(r, "beech_b")),
    dict(name="fill_evergreen", px=(768, 512, 256, 256), studs=(1.2, 1.2), anchor=(0.6, 0.6), ao=0.05, seed=68,
         build=lambda r: E.leaf_fill(r, "evergreen", 1.2)),
    dict(name="moss_a", px=(0, 256, 256, 256), studs=(1.8, 1.8), anchor=(0.9, 0.9), ao=0.03, seed=69,
         build=lambda r: E.moss_patch(r, 0.82, 0.82, True, "green")),
    dict(name="moss_b", px=(256, 256, 256, 256), studs=(1.8, 1.8), anchor=(0.9, 0.9), ao=0.03, seed=70,
         build=lambda r: E.moss_patch(r, 0.82, 0.8, True, "dark")),
    dict(name="moss_mat", px=(0, 0, 512, 256), studs=(4.0, 2.0), anchor=(2.0, 1.0), ao=0.03, seed=71,
         build=lambda r: E.moss_patch(r, 1.9, 0.92, True, "green", 0.9)),
    dict(name="bark", px=(512, 0, 128, 512), studs=(1.0, 4.0), anchor=(0.0, 0.0),
         flat=[("bark", 0.0, 0.0, 1.0, 4.0)]),
    dict(name="mush_cap", px=(640, 384, 128, 128), studs=(0.5, 0.5), anchor=(0.25, 0.25),
         flat=[("mush_cap", -0.24, -0.24, 0.24, 0.24, "disc")]),
    dict(name="mush_gills", px=(640, 256, 128, 128), studs=(0.5, 0.5), anchor=(0.25, 0.25),
         flat=[("mush_gills", -0.24, -0.24, 0.24, 0.24, "disc")]),
    dict(name="mush_stem", px=(640, 0, 64, 256), studs=(0.25, 1.0), anchor=(0.0, 0.0),
         flat=[("mush_stem", 0.0, 0.0, 0.25, 1.0)]),
    dict(name="berry", px=(704, 192, 64, 64), studs=(0.2, 0.2), anchor=(0.1, 0.1),
         flat=[("berry", -0.095, -0.095, 0.095, 0.095, "disc")]),
    dict(name="fill_broadleaf", px=(768, 256, 256, 256), studs=(1.4, 1.4), anchor=(0.7, 0.7), ao=0.06, seed=72,
         build=lambda r: E.leaf_fill(r, "broadleaf", 1.4)),
    dict(name="litter", px=(768, 0, 256, 256), studs=(1.6, 1.6), anchor=(0.8, 0.8), ao=0.04, seed=73,
         build=lambda r: E.litter_patch(r, 0.72, 0.72)),
]

PAGES = {"Plants": PLANTS, "Shrubs": SHRUBS}


# =============================================================================================== page build
def build_page(page, specs, tex_dir, tmp_dir, log=print, only=None):
    scene = bpy.context.scene
    bpy.data.materials.get("GR_Elem") or make_elem_material()
    rgba = np.zeros((PAGE, PAGE, 4))
    nrm = np.zeros((PAGE, PAGE, 4))
    ra = np.zeros((PAGE, PAGE, 4))
    layout = {}
    cache_path = os.path.join(tmp_dir, "page_%s.npz" % page)
    cached = dict(np.load(cache_path, allow_pickle=True)) if (only and os.path.exists(cache_path)) else None
    if cached is not None:
        rgba, nrm, ra = cached["rgba"], cached["nrm"], cached["ra"]
        layout = json.loads(str(cached["layout"]))
    for spec in specs:
        if only and spec["name"] not in only and spec["name"] in layout:
            continue
        res = render_slot(scene, spec, tmp_dir, log)
        x, y, w, h = spec["px"]
        rgba[y:y + h, x:x + w] = res["rgba"]
        nrm[y:y + h, x:x + w] = res["nrm"]
        ra[y:y + h, x:x + w] = res["ra"]
        a = res["rgba"][..., 3]
        ys, xs = np.nonzero(a > 0.02)
        if len(xs):
            tx0, tx1 = max(int(xs.min()) - 2, 0), min(int(xs.max()) + 3, w)
            ty0, ty1 = max(int(ys.min()) - 2, 0), min(int(ys.max()) + 3, h)
        else:
            tx0, ty0, tx1, ty1 = 0, 0, w, h
        dens = w / spec["studs"][0]
        layout[spec["name"]] = {
            "slot": [x, y, w, h],
            "rect": [x + tx0, y + ty0, x + tx1, y + ty1],
            "density": dens,
            "anchor_px": [x + spec["anchor"][0] * dens, y + spec["anchor"][1] * dens],
            "studs": list(spec["studs"]),
            "coverage": float((a > 0.5).mean()),
        }
    np.savez_compressed(cache_path, rgba=rgba, nrm=nrm, ra=ra, layout=json.dumps(layout))
    return finish_page(page, rgba, nrm, ra, layout, tex_dir, log)


def finish_page(page, rgba, nrm, ra, layout, tex_dir, log=print):
    alpha = rgba[..., 3]
    # mild AO into albedo (AO pass is rendered per slot with a slot-appropriate distance)
    ao = np.clip(ra[..., 1], 0, 1)
    ao = np.where(alpha > 1e-3, ao, 1.0)
    alb = rgba[..., :3] * (0.55 + 0.45 * ao[..., None])
    w = np.clip((alpha - 0.05) * 3.0, 0, 1)
    alb_f = tg.pushpull(alb, w)
    n = tg.decode_normal(nrm[..., :3])
    n = np.where(alpha[..., None] > 1e-3, n, np.array([0, 0, 1.0]))
    n_f = tg.pushpull(n, w)
    n_f = n_f / np.maximum(np.linalg.norm(n_f, axis=-1, keepdims=True), 1e-6)
    n_f[..., 2] = np.maximum(n_f[..., 2], 0.05)
    r_f = tg.pushpull(ra[..., :1], w)[..., 0]
    # thin blades / pinnae erode in the lower mips (box-filtered alpha drops under the cut-off): give the Plants
    # page a one-pixel coverage rim (colour is already bled there), ~1.4x thicker blades at 2-3 px wide
    if page == "Plants":
        pad = np.pad(alpha, 1, mode="edge")
        nb = np.max(np.stack([pad[1 + dy:1 + dy + alpha.shape[0], 1 + dx:1 + dx + alpha.shape[1]]
                              for dy in (-1, 0, 1) for dx in (-1, 0, 1)]), axis=0)
        alpha = np.maximum(alpha, 0.72 * nb)
    # sharpen alpha slightly: cut-out friendly (Roblox Transparency mode with part Transparency 0 alpha-tests)
    a_out = np.clip((alpha - 0.5) * 1.6 + 0.5, 0, 1)
    color = np.concatenate([tg.lin_to_srgb(alb_f), a_out[..., None]], 2)
    files = {
        "color": tg.write_png(os.path.join(tex_dir, "GR_%s_Color.png" % page), color),
        "normal": tg.write_png(os.path.join(tex_dir, "GR_%s_Normal.png" % page), tg.encode_normal(n_f)),
        "rough": tg.write_png(os.path.join(tex_dir, "GR_%s_Rough.png" % page), np.clip(r_f, 0, 1)),
    }
    meta = {"page": page, "size": PAGE, "files": {k: os.path.basename(v) for k, v in files.items()},
            "slots": layout}
    # average colour per slot (manifest rgb fallback)
    for name, s in layout.items():
        x0, y0, x1, y1 = s["rect"]
        a = alpha[y0:y1, x0:x1]
        c = alb_f[y0:y1, x0:x1]
        m = a > 0.5
        avg = c[m].mean(axis=0) if m.any() else c.reshape(-1, 3).mean(axis=0)
        s["avg_srgb"] = [int(round(v * 255)) for v in tg.lin_to_srgb(avg)]
    log("PAGE %s -> %s" % (page, ", ".join(os.path.basename(v) for v in files.values())))
    return meta


def build_atlases(tex_dir, tmp_dir, log=print, pages=("Plants", "Shrubs"), only=None):
    os.makedirs(tex_dir, exist_ok=True)
    os.makedirs(tmp_dir, exist_ok=True)
    layout_path = os.path.join(tmp_dir, "GR_Atlas_Layout.json")
    allmeta = {}
    if os.path.exists(layout_path):
        with open(layout_path, encoding="utf-8") as f:
            allmeta = json.load(f)
    for page in pages:
        allmeta[page] = build_page(page, PAGES[page], tex_dir, tmp_dir, log, only)
    with open(layout_path, "w", encoding="utf-8") as f:
        json.dump(allmeta, f, indent=1)
    return allmeta
