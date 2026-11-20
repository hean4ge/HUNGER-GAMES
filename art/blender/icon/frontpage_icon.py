"""
frontpage_icon.py - "front-page" style character icons for "#ARENA 48" (Roblox game icon), Blender 5.3 headless, seeded.

  blender --background --factory-startup --python art/blender/icon/frontpage_icon.py -- <out_dir> [a] [b] [c] [--res N] [--samples N]

Writes <out_dir>/concept<X>_raw.png (no title, straight from Cycles) and concept<X>_meta.json (head boxes in
pixel space, so the title can be placed off the faces) per concept:
  a  one contender close up, drawing a bow at the camera, intense eyes; the Horn and the glowing hex wall behind
  b  two rivals clashing near the Horn: one raises an axe and roars, the other ducks with a knife, shocked;
     a supply crate spills in the foreground
  c  a contender sprints off a launch plinth toward the camera, countdown beacon blazing behind, a rival with a
     spear close behind, dust kicked up

Characters are ORIGINAL Roblox-proportioned (R15) avatars: blocky bevelled parts, painted faces (drawn into a
texture by this script), survival outfits (hooded jackets, vests, cargo trousers, fingerless gloves, packs, a
plain numbered armband). No film characters, emblems, logos, District numbers or film costumes. No blood.
Title is added afterwards by finish_icons.py (PIL).
"""
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view

SEED = 2548


# ------------------------------------------------------------------------------------------- args
def argv():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.join(os.path.dirname(__file__), "out")
    opts, res, samples = [], 1024, 256
    i = 0
    pos = []
    while i < len(a):
        if a[i] == "--res":
            res = int(a[i + 1]); i += 2; continue
        if a[i] == "--samples":
            samples = int(a[i + 1]); i += 2; continue
        pos.append(a[i]); i += 1
    if pos:
        out = pos[0]
        opts = [x.lower() for x in pos[1:]]
    return out, (opts or ["a", "b", "c"]), res, samples


# ------------------------------------------------------------------------------------------- colour
def lin(c):
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


def mul(c, k):
    return tuple(max(0, min(255, v * k)) for v in c)


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ------------------------------------------------------------------------------------------- scene
def reset(res, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 8
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "16"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        ok = False
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
            ok = ok or d.use
        if ok:
            sc.cycles.device = "GPU"
    except Exception:
        pass
    return sc


_MATS = {}


def mat(col, rough=0.82, metal=0.0, emit=0.0, emit_col=None, sheen=0.0):
    key = (tuple(round(v, 1) for v in col), rough, metal, emit, emit_col, sheen)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("M%d" % len(_MATS))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if sheen > 0:
        try:
            b.inputs["Sheen Weight"].default_value = sheen
        except Exception:
            pass
    if emit > 0:
        b.inputs["Emission Color"].default_value = lin(emit_col or col)
        b.inputs["Emission Strength"].default_value = emit
    _MATS[key] = m
    return m


def emis_mat(col, strength):
    m = bpy.data.materials.new("E")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = lin(col)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mesh_obj(name, verts, faces, material, smooth=False, bevel=0.0, seg=2):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    link(ob)
    ob.data.materials.append(material)
    if bevel > 0:
        md = ob.modifiers.new("Bevel", "BEVEL")
        md.width = bevel
        md.segments = seg
        md.limit_method = "NONE"
    return ob


BOX_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def box_verts(size, off=(0, 0, 0), taper=1.0):
    w, d, h = size[0] / 2, size[1] / 2, size[2] / 2
    ox, oy, oz = off
    lo = [(-w, -d, -h), (w, -d, -h), (w, d, -h), (-w, d, -h)]
    hi = [(-w * taper, -d * taper, h), (w * taper, -d * taper, h), (w * taper, d * taper, h), (-w * taper, d * taper, h)]
    return [Vector((x + ox, y + oy, z + oz)) for (x, y, z) in lo + hi]


def box(name, size, M, col, off=(0, 0, 0), bevel=0.07, rough=0.82, metal=0.0, taper=1.0, material=None, smooth=False,
        seg=2):
    vs = [M @ v for v in box_verts(size, off, taper)]
    return mesh_obj(name, vs, BOX_F, material or mat(col, rough, metal), smooth=smooth, bevel=bevel, seg=seg)


def frame(origin, R):
    """4x4 from a location and a 3x3 rotation."""
    M = R.to_4x4()
    M.translation = Vector(origin)
    return M


def basis_from(z_dir, y_hint):
    """Rotation whose local +Z is z_dir and local +Y is as close to y_hint as possible."""
    z = Vector(z_dir).normalized()
    y = Vector(y_hint) - z * Vector(y_hint).dot(z)
    if y.length < 1e-5:
        y = Vector((0, 0, 1)) if abs(z.z) < 0.9 else Vector((0, 1, 0))
        y = y - z * y.dot(z)
    y.normalize()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


def seg_box(name, p0, p1, w, d, col, y_hint=(0, 0, 1), bevel=0.03, ext=0.0, rough=0.8, metal=0.0, taper=1.0,
            material=None):
    p0, p1 = Vector(p0), Vector(p1)
    ax = p1 - p0
    L = ax.length
    R = basis_from(ax, y_hint)
    c = (p0 + p1) / 2
    return box(name, (w, d, L + ext), frame(c, R), col, bevel=bevel, rough=rough, metal=metal, taper=taper,
               material=material)


def cyl(name, base, r, h, sides, col, M=None, rough=0.8, metal=0.0, top_scale=1.0, material=None, bevel=0.0,
        smooth=False):
    M = M or Matrix.Identity(4)
    bx, by, bz = base
    vs, fs = [], []
    for i in range(sides):
        a = i * 2 * math.pi / sides
        vs.append(M @ Vector((bx + r * math.cos(a), by + r * math.sin(a), bz)))
    for i in range(sides):
        a = i * 2 * math.pi / sides
        vs.append(M @ Vector((bx + r * top_scale * math.cos(a), by + r * top_scale * math.sin(a), bz + h)))
    for i in range(sides):
        j = (i + 1) % sides
        fs.append((i, j, sides + j, sides + i))
    fs.append(tuple(reversed(range(sides))))
    fs.append(tuple(range(sides, 2 * sides)))
    return mesh_obj(name, vs, fs, material or mat(col, rough, metal), smooth=smooth, bevel=bevel)


# ------------------------------------------------------------------------------------------- faces
FACE_RES = 1024
FACE_W, FACE_H = 1.36, 1.28  # head size (x, z) the texture spans


def _grid(n):
    s = (np.arange(n) + 0.5) / n
    u = (s - 0.5) * FACE_W
    v = (s - 0.5) * FACE_H
    U, V = np.meshgrid(u, v)
    return U, V


def m_ellipse(U, V, cx, cy, rx, ry, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    x, y = U - cx, V - cy
    xr, yr = x * c + y * s, -x * s + y * c
    return (xr / rx) ** 2 + (yr / ry) ** 2 <= 1.0


def m_poly(U, V, pts):
    inside = np.zeros(U.shape, bool)
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        cond = ((yi > V) != (yj > V)) & (U < (xj - xi) * (V - yi) / (yj - yi + 1e-12) + xi)
        inside ^= cond
        j = i
    return inside


def brow(cx, cy, length, thick, angle, side):
    """A chunky brow bar; angle in degrees, positive = inner end down (angry). side -1 = left of face image."""
    a = math.radians(angle) * side
    dx, dy = math.cos(a) * length / 2, math.sin(a) * length / 2
    nx, ny = -math.sin(a) * thick / 2, math.cos(a) * thick / 2
    # slightly wedge shaped: thicker at the inner end
    inner_k, outer_k = 1.15, 0.8
    p0 = (cx - dx, cy - dy)
    p1 = (cx + dx, cy + dy)
    if side < 0:  # left brow (image left): inner end is p1
        ki, ko = inner_k, outer_k
        return [(p0[0] - nx * ko, p0[1] - ny * ko), (p1[0] - nx * ki, p1[1] - ny * ki),
                (p1[0] + nx * ki, p1[1] + ny * ki), (p0[0] + nx * ko, p0[1] + ny * ko)]
    ki, ko = inner_k, outer_k
    return [(p0[0] - nx * ki, p0[1] - ny * ki), (p1[0] - nx * ko, p1[1] - ny * ko),
            (p1[0] + nx * ko, p1[1] + ny * ko), (p0[0] + nx * ki, p0[1] + ny * ki)]


INK = (28, 22, 20)
WHITE = (250, 248, 242)
MOUTH = (70, 22, 26)
TONGUE = (196, 82, 82)


def face_layers(expr, U, V, skin):
    """List of (mask, rgb, alpha) layers, painted in order. Roblox-style: bold dark eyes with catchlights,
    chunky brows, simple graphic mouth; slightly stylised but readable at 150 px."""
    L = []
    ex, ey = 0.25, 0.07
    shade = mul(skin, 0.78)
    if expr == "intense":  # drawing a bow: narrowed eyes, hard brows, gritted teeth
        for s in (-1, 1):
            eye = m_ellipse(U, V, s * ex, ey, 0.105, 0.085)
            lid = m_poly(U, V, [(s * ex - 0.2, ey + 0.035 + (0.03 if s < 0 else 0.03)),
                                (s * ex + 0.2, ey + 0.035 + (0.03 if s > 0 else 0.03)),
                                (s * ex + 0.2, ey + 0.3), (s * ex - 0.2, ey + 0.3)])
            # lid slants down toward the nose
            lid = m_poly(U, V, [(s * ex - 0.18, ey + (0.06 if s > 0 else 0.0)),
                                (s * ex + 0.18, ey + (0.0 if s > 0 else 0.06)),
                                (s * ex + 0.18, ey + 0.3), (s * ex - 0.18, ey + 0.3)])
            L.append((eye & ~lid, INK, 1.0))
            L.append((m_ellipse(U, V, s * ex + 0.035, ey - 0.005, 0.03, 0.026), WHITE, 1.0))
            L.append((m_poly(U, V, brow(s * 0.24, 0.215, 0.36, 0.1, 24, s)), INK, 1.0))
        L.append((m_ellipse(U, V, 0, -0.04, 0.05, 0.03), shade, 0.55))  # nose hint
        teeth = m_poly(U, V, [(-0.2, -0.24), (0.2, -0.235), (0.17, -0.31), (-0.17, -0.315)])
        L.append((m_poly(U, V, [(-0.235, -0.22), (0.235, -0.215), (0.2, -0.335), (-0.2, -0.34)]), MOUTH, 1.0))
        L.append((teeth, WHITE, 1.0))
        L.append((m_poly(U, V, [(-0.2, -0.276), (0.2, -0.27), (0.2, -0.282), (-0.2, -0.288)]), (150, 140, 130), 1.0))
        L.append((m_ellipse(U, V, 0.36, -0.12, 0.09, 0.05, 0.4), (120, 90, 64), 0.35))  # mud smudge
    elif expr == "fury":  # axe raised: roaring
        for s in (-1, 1):
            eye = m_ellipse(U, V, s * ex, ey + 0.01, 0.1, 0.12)
            lid = m_poly(U, V, [(s * ex - 0.18, ey + (0.1 if s > 0 else 0.02)),
                                (s * ex + 0.18, ey + (0.02 if s > 0 else 0.1)),
                                (s * ex + 0.18, ey + 0.3), (s * ex - 0.18, ey + 0.3)])
            L.append((eye & ~lid, INK, 1.0))
            L.append((m_ellipse(U, V, s * ex + 0.03, ey + 0.0, 0.03, 0.03), WHITE, 1.0))
            L.append((m_poly(U, V, brow(s * 0.24, 0.215, 0.38, 0.11, 30, s)), INK, 1.0))
        L.append((m_ellipse(U, V, 0, -0.05, 0.05, 0.03), shade, 0.55))
        top = [(-0.25, -0.23), (-0.12, -0.17), (0.12, -0.17), (0.25, -0.23)]
        L.append((m_poly(U, V, top + [(0.2, -0.45), (-0.2, -0.45)]), MOUTH, 1.0))
        L.append((m_poly(U, V, top + [(0.235, -0.27), (0.11, -0.225), (-0.11, -0.225), (-0.235, -0.27)]), WHITE, 1.0))
        L.append((m_poly(U, V, [(-0.17, -0.44), (0.17, -0.44), (0.15, -0.405), (-0.15, -0.405)]), WHITE, 1.0))
        L.append((m_ellipse(U, V, 0.0, -0.39, 0.12, 0.045), TONGUE, 1.0))
        L.append((m_ellipse(U, V, -0.38, -0.14, 0.08, 0.045, -0.3), (120, 90, 64), 0.35))
    elif expr == "shock":  # ducking: wide eyes, raised brows, open "O"
        for s in (-1, 1):
            L.append((m_ellipse(U, V, s * ex, ey, 0.115, 0.15), WHITE, 1.0))
            L.append((m_ellipse(U, V, s * ex - s * 0.02, ey + 0.0, 0.065, 0.085), INK, 1.0))
            L.append((m_ellipse(U, V, s * ex - s * 0.02 + 0.025, ey + 0.03, 0.02, 0.02), WHITE, 1.0))
            ring = m_ellipse(U, V, s * ex, ey, 0.13, 0.165) & ~m_ellipse(U, V, s * ex, ey, 0.112, 0.147)
            L.append((ring, INK, 1.0))
            L.append((m_poly(U, V, brow(s * 0.25, 0.3, 0.34, 0.085, -16, s)), INK, 1.0))
        L.append((m_ellipse(U, V, 0, -0.29, 0.1, 0.12), MOUTH, 1.0))
        L.append((m_ellipse(U, V, 0, -0.36, 0.065, 0.04), TONGUE, 1.0))
        L.append((m_ellipse(U, V, 0.37, -0.15, 0.08, 0.045, 0.3), (120, 90, 64), 0.3))
    elif expr == "determined":  # sprinting: fierce grin-grimace
        for s in (-1, 1):
            eye = m_ellipse(U, V, s * ex, ey, 0.1, 0.115)
            lid = m_poly(U, V, [(s * ex - 0.18, ey + (0.07 if s > 0 else 0.03)),
                                (s * ex + 0.18, ey + (0.03 if s > 0 else 0.07)),
                                (s * ex + 0.18, ey + 0.3), (s * ex - 0.18, ey + 0.3)])
            L.append((eye & ~lid, INK, 1.0))
            L.append((m_ellipse(U, V, s * ex + 0.03, ey - 0.005, 0.03, 0.028), WHITE, 1.0))
            L.append((m_poly(U, V, brow(s * 0.24, 0.215, 0.36, 0.1, 20, s)), INK, 1.0))
        L.append((m_ellipse(U, V, 0, -0.05, 0.05, 0.03), shade, 0.55))
        L.append((m_poly(U, V, [(-0.27, -0.25), (-0.13, -0.19), (0.13, -0.19), (0.27, -0.25), (0.22, -0.38),
                                (-0.22, -0.38)]), MOUTH, 1.0))
        L.append((m_poly(U, V, [(-0.25, -0.25), (-0.12, -0.2), (0.12, -0.2), (0.25, -0.25), (0.24, -0.28),
                                (-0.24, -0.28)]), WHITE, 1.0))
        L.append((m_poly(U, V, [(-0.21, -0.33), (0.21, -0.33), (0.2, -0.37), (-0.2, -0.37)]), WHITE, 1.0))
        L.append((m_ellipse(U, V, -0.36, -0.12, 0.09, 0.05, -0.4), (120, 90, 64), 0.35))
    return L


def face_image(name, expr, skin):
    ss = 2
    n = FACE_RES * ss
    U, V = _grid(n)
    rgb = np.zeros((n, n, 3), np.float32)
    alpha = np.zeros((n, n), np.float32)
    for m, col, a in face_layers(expr, U, V, skin):
        c = np.array(lin(col)[:3], np.float32)
        k = m.astype(np.float32) * a
        rgb = rgb * (1 - k[..., None]) + c * k[..., None]
        alpha = alpha * (1 - k) + k
    # premultiplied -> straight; downsample
    rgb = rgb.reshape(FACE_RES, ss, FACE_RES, ss, 3).mean(axis=(1, 3))
    alpha = alpha.reshape(FACE_RES, ss, FACE_RES, ss).mean(axis=(1, 3))
    straight = np.where(alpha[..., None] > 1e-4, rgb / np.maximum(alpha[..., None], 1e-4), 0)
    px = np.concatenate([straight, alpha[..., None]], axis=2).astype(np.float32)
    img = bpy.data.images.new(name, FACE_RES, FACE_RES, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Linear Rec.709"
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def head_mat(name, skin, img):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, Lk = nt.nodes, nt.links
    b = N["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.6
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ")
    Lk.new(tc.outputs["Object"], sep.inputs[0])
    mu = N.new("ShaderNodeMath"); mu.operation = "MULTIPLY_ADD"
    mu.inputs[1].default_value = 1.0 / FACE_W; mu.inputs[2].default_value = 0.5
    Lk.new(sep.outputs["X"], mu.inputs[0])
    mv = N.new("ShaderNodeMath"); mv.operation = "MULTIPLY_ADD"
    mv.inputs[1].default_value = 1.0 / FACE_H; mv.inputs[2].default_value = 0.5
    Lk.new(sep.outputs["Z"], mv.inputs[0])
    cmb = N.new("ShaderNodeCombineXYZ")
    Lk.new(mu.outputs[0], cmb.inputs["X"]); Lk.new(mv.outputs[0], cmb.inputs["Y"])
    tex = N.new("ShaderNodeTexImage"); tex.image = img; tex.extension = "CLIP"; tex.interpolation = "Cubic"
    Lk.new(cmb.outputs[0], tex.inputs["Vector"])
    # front mask from object-space normal (-Y is the face)
    sn = N.new("ShaderNodeSeparateXYZ")
    Lk.new(tc.outputs["Normal"], sn.inputs[0])
    fm = N.new("ShaderNodeMapRange")
    fm.inputs["From Min"].default_value = -0.35; fm.inputs["From Max"].default_value = -0.6
    Lk.new(sn.outputs["Y"], fm.inputs["Value"])
    am = N.new("ShaderNodeMath"); am.operation = "MULTIPLY"
    Lk.new(tex.outputs["Alpha"], am.inputs[0]); Lk.new(fm.outputs["Result"], am.inputs[1])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"
    Lk.new(am.outputs[0], mx.inputs["Factor"])
    mx.inputs["A"].default_value = lin(skin)
    Lk.new(tex.outputs["Color"], mx.inputs["B"])
    Lk.new(mx.outputs["Result"], b.inputs["Base Color"])
    # a touch of subsurface-free warmth: slight sheen
    try:
        b.inputs["Sheen Weight"].default_value = 0.15
    except Exception:
        pass
    return m


# ------------------------------------------------------------------------------------------- avatar
def two_bone(S, T, L1, L2, pole):
    S, T, P = Vector(S), Vector(T), Vector(pole)
    d = T - S
    dist = min(d.length, (L1 + L2) * 0.995)
    dist = max(dist, abs(L1 - L2) + 1e-3)
    dr = d.normalized()
    a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    pv = (P - S) - dr * (P - S).dot(dr)
    if pv.length < 1e-5:
        pv = Vector((0, -1, 0))
    pv.normalize()
    E = S + dr * a + pv * h
    W = S + dr * dist
    return E, W


def rot_xyz(rx=0, ry=0, rz=0):
    from mathutils import Euler
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix()


class Outfit:
    def __init__(self, **kw):
        self.skin = (226, 170, 128)
        self.jacket = (58, 82, 52)
        self.jacket_dark = (40, 58, 38)
        self.vest = (112, 92, 62)
        self.pants = (104, 92, 70)
        self.boots = (60, 44, 34)
        self.glove = (44, 40, 38)
        self.hair = (70, 46, 30)
        self.hood = True
        self.band = (232, 222, 196)
        self.band_num = "27"
        self.pack = (92, 74, 50)
        self.strap = (66, 50, 36)
        self.hair_style = "short"
        self.__dict__.update(kw)


def segment_limb(name, S, E, W, up_hint, w, cols_upper, cols_lower, lens, hand_col, hand_tip, sleeve=None,
                 cuff=None, foot=False, boot=None):
    """Builds upper part (S->E) and lower part (E->W) plus hand/foot below W. Returns the hand frame."""
    objs = []
    d1 = (E - S).normalized()
    d2 = (W - E).normalized()
    # extend the upper so the shoulder/hip block reads solid
    objs.append(seg_box(name + "_u", S + d1 * -0.28, E + d1 * 0.06, w, w, cols_upper, y_hint=up_hint, bevel=0.08))
    objs.append(seg_box(name + "_l", E - d2 * 0.06, W, w * 0.97, w * 0.97, cols_lower, y_hint=up_hint, bevel=0.08))
    if cuff:
        objs.append(seg_box(name + "_cuff", W - d2 * 0.2, W - d2 * 0.02, w * 1.06, w * 1.06, cuff, y_hint=up_hint,
                            bevel=0.05))
    if not foot:
        H0, H1 = W, W + d2 * 0.42
        objs.append(seg_box(name + "_hand", H0, H1 - d2 * 0.08, w * 0.8, w * 0.8, hand_col, y_hint=up_hint,
                            bevel=0.1))
        objs.append(seg_box(name + "_fing", H1 - d2 * 0.1, H1, w * 0.62, w * 0.62, mul(hand_tip, 0.88), y_hint=up_hint,
                            bevel=0.05))
        R = basis_from(d2, up_hint)
        return objs, frame(W + d2 * 0.22, R)
    # foot: a boot block pointing forward (y_hint is the toe direction)
    R = basis_from(d2, up_hint)
    fz = d2
    toe = Vector(up_hint).normalized()
    c = W + fz * 0.17 + toe * 0.12
    objs.append(box(name + "_foot", (w * 0.98, w * 1.25, 0.36), frame(c, R), boot, bevel=0.08))
    return objs, frame(W, R)


class Avatar:
    """R15-proportioned avatar. Facing -Y by default; char's right side is -X."""

    def __init__(self, name, root, yaw=0.0, lean=0.0, roll=0.0, outfit=None, expr="determined", waist=(0, 0, 0),
                 neck=(0, 0, 0), head_scale=1.0):
        self.name = name
        self.o = outfit or Outfit()
        self.R0 = rot_xyz(0, 0, yaw) @ rot_xyz(lean, roll, 0)
        self.root = Vector(root)
        self.Rw = self.R0 @ rot_xyz(*waist)
        self.Rh = self.Rw @ rot_xyz(*neck)
        self.expr = expr
        self.hs = head_scale
        self.objs = []
        # key points
        self.waist_p = self.root + self.R0 @ Vector((0, 0, 0.8))
        self.neck_p = self.waist_p + self.Rw @ Vector((0, 0, 1.22))
        self.head_c = self.neck_p + self.Rh @ Vector((0, 0, 0.72 * head_scale))
        self.sh = {"R": self.waist_p + self.Rw @ Vector((-1.5, 0, 0.82)),
                   "L": self.waist_p + self.Rw @ Vector((1.5, 0, 0.82))}
        self.hip = {"R": self.root + self.R0 @ Vector((-0.5, 0, -0.02)),
                    "L": self.root + self.R0 @ Vector((0.5, 0, -0.02))}

    def fw(self, R=None):
        return (R or self.Rw) @ Vector((0, -1, 0))

    def build_body(self):
        o = self.o
        n = self.name
        M0 = frame(self.root, self.R0)
        Mw = frame(self.waist_p, self.Rw)
        # lower torso: belt + trousers top
        self.objs.append(box(n + "_hips", (2.0, 1.0, 0.82), M0, o.pants, off=(0, 0, 0.38)))
        self.objs.append(box(n + "_belt", (2.06, 1.06, 0.2), M0, o.strap, off=(0, 0, 0.72), bevel=0.04))
        self.objs.append(box(n + "_buckle", (0.32, 0.08, 0.2), M0, (150, 128, 82), off=(0.25, -0.54, 0.72), bevel=0.02,
                             rough=0.5, metal=0.6))
        # upper torso: jacket + vest + collar
        self.objs.append(box(n + "_torso", (2.0, 1.0, 1.25), Mw, o.jacket, off=(0, 0, 0.6)))
        self.objs.append(box(n + "_hem", (2.08, 1.08, 0.24), Mw, o.jacket_dark, off=(0, 0, 0.06), bevel=0.05))
        self.objs.append(box(n + "_zip", (0.08, 0.06, 1.1), Mw, o.jacket_dark, off=(-0.05, -0.52, 0.62), bevel=0.01))
        self.objs.append(box(n + "_vestL", (0.62, 1.1, 1.18), Mw, o.vest, off=(0.62, 0, 0.6), bevel=0.05))
        self.objs.append(box(n + "_vestR", (0.62, 1.1, 1.18), Mw, o.vest, off=(-0.62, 0, 0.6), bevel=0.05))
        for sx in (-1, 1):
            self.objs.append(box(n + "_pocket", (0.44, 0.1, 0.36), Mw, mul(o.vest, 0.82), off=(sx * 0.62, -0.58, 0.42),
                                 bevel=0.03))
            self.objs.append(box(n + "_flap", (0.48, 0.12, 0.1), Mw, mul(o.vest, 0.7), off=(sx * 0.62, -0.6, 0.6),
                                 bevel=0.02))
        # collar
        self.objs.append(box(n + "_collar", (1.3, 1.0, 0.24), Mw, o.jacket_dark, off=(0, 0.05, 1.28), bevel=0.08))
        # backpack + straps
        self.objs.append(box(n + "_pack", (1.6, 0.7, 1.4), Mw, o.pack, off=(0, 0.82, 0.55), bevel=0.14))
        self.objs.append(box(n + "_packflap", (1.5, 0.76, 0.42), Mw, mul(o.pack, 0.8), off=(0, 0.84, 1.1), bevel=0.1))
        self.objs.append(box(n + "_bedroll", (1.9, 0.5, 0.5), Mw, (70, 96, 74), off=(0, 0.88, 1.45), bevel=0.2,
                             seg=3))
        for sx in (-1, 1):
            self.objs.append(box(n + "_strap", (0.2, 1.14, 0.16), Mw, o.strap, off=(sx * 0.55, 0, 1.18), bevel=0.02))
            self.objs.append(box(n + "_strapF", (0.2, 0.06, 1.15), Mw, o.strap, off=(sx * 0.55, -0.57, 0.6),
                                 bevel=0.02))
        # rope coil on the hip
        self.rope(M0, (1.02, 0.1, 0.4))
        # mud patches
        self.objs.append(box(n + "_mud1", (0.5, 0.04, 0.22), M0, (92, 70, 50), off=(-0.55, -0.51, 0.25), bevel=0.02))
        self.objs.append(box(n + "_mud2", (0.32, 0.04, 0.26), Mw, mul(o.jacket, 0.72), off=(0.62, -0.62, 0.95),
                             bevel=0.02))

    def rope(self, M, off):
        n = 10
        r1, r2 = 0.28, 0.06
        vs, fs = [], []
        k = 6
        for i in range(n):
            a = i * 2 * math.pi / n
            for j in range(k):
                b = j * 2 * math.pi / k
                x = (r1 + r2 * math.cos(b))
                vs.append(M @ (Vector(off) + Vector((r2 * math.sin(b) * 1.6, x * math.cos(a), x * math.sin(a)))))
        for i in range(n):
            for j in range(k):
                fs.append((i * k + j, i * k + (j + 1) % k, ((i + 1) % n) * k + (j + 1) % k, ((i + 1) % n) * k + j))
        self.objs.append(mesh_obj(self.name + "_rope", vs, fs, mat((176, 150, 104), 0.9), smooth=True))

    def build_head(self):
        o = self.o
        n = self.name
        s = self.hs
        Mh = frame(self.head_c, self.Rh)
        # neck
        self.objs.append(seg_box(n + "_neck", self.neck_p - self.Rw @ Vector((0, 0, 0.1)),
                                 self.neck_p + self.Rh @ Vector((0, 0, 0.25)), 0.6, 0.6, mul(o.skin, 0.85),
                                 y_hint=self.Rh @ Vector((0, 1, 0))))
        img = face_image(n + "_face", self.expr, o.skin)
        hm = head_mat(n + "_headmat", o.skin, img)
        vs = box_verts((FACE_W * s, 1.22 * s, FACE_H * s))
        # head object at the head centre so its object coords map to the face texture
        me = bpy.data.meshes.new(n + "_head")
        me.from_pydata([tuple(v / s) for v in vs], [], BOX_F)
        for p in me.polygons:
            p.use_smooth = True
        ob = bpy.data.objects.new(n + "_head", me)
        link(ob)
        ob.data.materials.append(hm)
        md = ob.modifiers.new("Bevel", "BEVEL"); md.width = 0.3; md.segments = 6; md.limit_method = "NONE"
        ob.matrix_world = Mh @ Matrix.Scale(s, 4)
        self.head = ob
        self.objs.append(ob)
        hw, hd, hh = FACE_W * s, 1.22 * s, FACE_H * s
        if o.hood:
            t = 0.16 * s
            col = o.jacket
            inner = mul(o.jacket, 0.45)
            self.objs.append(box(n + "_hoodT", (hw + 2 * t + 0.06, hd + t + 0.1, t), Mh, col,
                                 off=(0, 0.06, hh / 2 + t / 2 - 0.02), bevel=0.07))
            self.objs.append(box(n + "_hoodB", (hw + 2 * t + 0.06, t, hh + t), Mh, col,
                                 off=(0, hd / 2 + t / 2 + 0.03, 0.02), bevel=0.07))
            for sx in (-1, 1):
                self.objs.append(box(n + "_hoodS", (t, hd + 0.12, hh * 1.0), Mh, col,
                                     off=(sx * (hw / 2 + t / 2 + 0.03), 0.04, 0.02), bevel=0.06))
                self.objs.append(box(n + "_hoodE", (t * 0.7, 0.06, hh * 0.98), Mh, inner,
                                     off=(sx * (hw / 2 + 0.01), -hd / 2 - 0.0, 0.04), bevel=0.02))
            # brim peak over the forehead
            self.objs.append(box(n + "_hoodP", (hw + 2 * t + 0.02, 0.3, t * 1.1), Mh, mul(col, 0.92),
                                 off=(0, -hd / 2 + 0.05, hh / 2 + 0.02), bevel=0.06))
            # fringe of hair peeking out
            self.objs.append(box(n + "_fringe", (hw * 0.82, 0.14, 0.2 * s), Mh, o.hair,
                                 off=(0.06, -hd / 2 - 0.0, hh / 2 - 0.08), bevel=0.05))
        else:
            hc = o.hair
            if o.hair_style == "short":
                self.objs.append(box(n + "_hairT", (hw + 0.12, hd + 0.12, 0.34 * s), Mh, hc,
                                     off=(0, 0.04, hh / 2 + 0.06), bevel=0.12, seg=3))
                self.objs.append(box(n + "_hairB", (hw + 0.12, 0.3, hh * 0.75), Mh, hc,
                                     off=(0, hd / 2 - 0.05, 0.16), bevel=0.1))
                for sx in (-1, 1):
                    self.objs.append(box(n + "_hairS", (0.18, hd * 0.75, hh * 0.45), Mh, hc,
                                         off=(sx * (hw / 2 + 0.03), 0.12, 0.3), bevel=0.06))
                # spiky front tufts
                for i, x in enumerate((-0.42, -0.14, 0.14, 0.42)):
                    self.objs.append(box(n + "_tuft%d" % i, (0.3, 0.32, 0.26), Mh @ frame((x * s, -hd / 2 + 0.1,
                                     hh / 2 + 0.02), rot_xyz(-25, (-1) ** i * 10, 0)), hc, bevel=0.06))
            elif o.hair_style == "band":  # tied-back hair under a cloth headband
                self.objs.append(box(n + "_hairT", (hw + 0.12, hd + 0.12, 0.34 * s), Mh, hc,
                                     off=(0, 0.04, hh / 2 + 0.06), bevel=0.12, seg=3))
                self.objs.append(box(n + "_hairB", (hw + 0.1, 0.34, hh * 0.9), Mh, hc,
                                     off=(0, hd / 2 - 0.02, 0.06), bevel=0.1))
                self.objs.append(box(n + "_hband", (hw + 0.2, hd + 0.2, 0.16), Mh, o.band_col,
                                     off=(0, 0.02, hh / 2 - 0.08), bevel=0.05))
                self.objs.append(box(n + "_tail", (0.36, 0.3, 0.9), Mh @ frame((0, hd / 2 + 0.25, -0.05),
                                     rot_xyz(25, 0, 0)), hc, bevel=0.1))

    def arm(self, side, target, pole):
        o = self.o
        S = self.sh[side]
        E, W = two_bone(S, target, 0.95, 0.85, pole)
        up = self.Rw @ Vector((0, -1, 0)) if side else Vector((0, 0, 1))
        objs, Mhand = segment_limb(self.name + "_arm" + side, S, E, W, (E - S).cross(W - E) if (E - S).cross(
            W - E).length > 1e-3 else up, 0.98, o.jacket, o.jacket, None, o.glove, o.skin, cuff=o.jacket_dark)
        self.objs += objs
        # armband on the upper arm with a plain number (left arm only)
        if side == "L" and o.band_num:
            d1 = (E - S).normalized()
            c = S + d1 * 0.32
            R = basis_from(d1, self.Rw @ Vector((1, 0, 0)))
            self.objs.append(box(self.name + "_band", (1.06, 1.06, 0.3), frame(c, R), o.band, bevel=0.03))
            self.number(c, d1, o.band_num)
        if side == "R":
            self.handR = Mhand
        else:
            self.handL = Mhand
        return Mhand

    def number(self, c, d1, txt):
        """A plain stencil number printed on the outward face of the armband."""
        out = (self.Rw @ Vector((1, 0, 0))) - d1 * (self.Rw @ Vector((1, 0, 0))).dot(d1)
        out.normalize()
        cu = bpy.data.curves.new(self.name + "_num", "FONT")
        cu.body = txt
        fp = font_path()
        if fp:
            try:
                cu.font = bpy.data.fonts.load(fp, check_existing=True)
            except Exception:
                pass
        cu.size = 0.27
        cu.align_x = "CENTER"; cu.align_y = "CENTER"
        cu.extrude = 0.005
        ob = bpy.data.objects.new(self.name + "_num", cu)
        link(ob)
        ob.data.materials.append(mat((30, 28, 26), 0.8))
        # text faces +Z of its local frame; reading upright along -d1 ("up the arm")
        zax = out
        yax = -d1
        xax = yax.cross(zax)
        R = Matrix((xax, yax, zax)).transposed()
        ob.matrix_world = frame(c + out * 0.54, R)
        self.objs.append(ob)

    def leg(self, side, target, pole, toe_dir=None):
        o = self.o
        S = self.hip[side]
        E, W = two_bone(S, target, 0.95, 0.85, pole)
        toe = Vector(toe_dir) if toe_dir else self.R0 @ Vector((0, -1, 0))
        objs, _ = segment_limb(self.name + "_leg" + side, S, E, W, toe, 0.98, o.pants, o.pants, None, None, None,
                               cuff=o.boots, foot=True, boot=o.boots)
        self.objs += objs
        # cargo pocket on the outer thigh
        d1 = (E - S).normalized()
        sx = -1 if side == "R" else 1
        outv = self.R0 @ Vector((sx, 0, 0))
        R = basis_from(d1, toe)
        self.objs.append(box(self.name + "_cargo" + side, (0.1, 0.46, 0.42),
                             frame(S + d1 * 0.5 + outv * 0.5, R), mul(o.pants, 0.84), bevel=0.03))
        return E, W


# ------------------------------------------------------------------------------------------- weapons & props
STEEL = (178, 184, 190)
WOOD = (122, 84, 52)
WRAP = (52, 40, 32)


def bow(grip, up, aim, nock, height=3.4, draw=True):
    up, aim = Vector(up).normalized(), Vector(aim).normalized()
    pts = []
    n = 12
    for i in range(n + 1):
        t = -1 + 2 * i / n
        p = Vector(grip) + up * t * height / 2 - aim * (0.55 * t * t) + aim * 0.05
        # recurve flick at the tips
        if abs(t) > 0.85:
            p += aim * (abs(t) - 0.85) * 1.8
        pts.append(p)
    for i in range(n):
        t = abs(-1 + 2 * (i + 0.5) / n)
        w = 0.2 - 0.1 * t
        col = WRAP if t < 0.18 else (WOOD if i % 2 else mul(WOOD, 0.9))
        seg_box("bow%d" % i, pts[i], pts[i + 1], w, w * 1.3, col, y_hint=aim, bevel=0.02, ext=0.05)
    sm = mat((236, 230, 214), 0.6)
    s0, s1 = pts[0] - aim * 0.02, pts[-1] - aim * 0.02
    nk = Vector(nock) if draw else (s0 + s1) / 2
    seg_box("str0", s0, nk, 0.035, 0.035, None, material=sm, bevel=0.0)
    seg_box("str1", nk, s1, 0.035, 0.035, None, material=sm, bevel=0.0)
    return pts


def arrow(tail, tip):
    tail, tip = Vector(tail), Vector(tip)
    d = (tip - tail).normalized()
    seg_box("shaft", tail, tip - d * 0.4, 0.07, 0.07, (196, 166, 120), y_hint=(0, 0, 1), bevel=0.0)
    R = basis_from(d, (0, 0, 1))
    hb = tip - d * 0.45
    # faceted broadhead
    vs = [hb + R @ Vector((0.17, 0, 0)), hb + R @ Vector((0, 0.04, 0)), hb + R @ Vector((-0.17, 0, 0)),
          hb + R @ Vector((0, -0.04, 0)), tip]
    fs = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (3, 2, 1, 0)]
    mesh_obj("head", vs, fs, mat(STEEL, 0.35, 0.85))
    seg_box("collar", tip - d * 0.52, tip - d * 0.42, 0.1, 0.1, WRAP, bevel=0.0)
    # three fletches
    for k in range(3):
        a = k * 2 * math.pi / 3 + 0.4
        nv = R @ Vector((math.cos(a), math.sin(a), 0))
        f0 = tail + d * 0.12
        vs = [f0, f0 + d * 0.6, f0 + d * 0.55 + nv * 0.16, f0 + d * 0.05 + nv * 0.2]
        mesh_obj("fl%d" % k, vs, [(0, 1, 2, 3)], mat((214, 92, 44) if k == 0 else (236, 226, 204), 0.8))


def axe(grip, up, edge_dir, length=3.0):
    up, ed = Vector(up).normalized(), Vector(edge_dir).normalized()
    p0 = Vector(grip) - up * 0.7
    p1 = Vector(grip) + up * (length - 0.7)
    seg_box("haft", p0, p1, 0.17, 0.2, WOOD, y_hint=ed, bevel=0.03)
    seg_box("haftwrap", Vector(grip) - up * 0.45, Vector(grip) + up * 0.45, 0.21, 0.24, WRAP, y_hint=ed, bevel=0.03)
    side = up.cross(ed).normalized()
    hc = p1 - up * 0.45
    # wedge head: thick at the haft, thin wide bit at the edge
    th, tw = 0.24, 0.05
    vs = [hc - up * 0.28 + side * th / 2, hc + up * 0.28 + side * th / 2, hc + up * 0.28 - side * th / 2,
          hc - up * 0.28 - side * th / 2,
          hc + ed * 1.05 - up * 0.62 + side * tw, hc + ed * 1.05 + up * 0.55 + side * tw,
          hc + ed * 1.05 + up * 0.55 - side * tw, hc + ed * 1.05 - up * 0.62 - side * tw]
    fs = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (0, 3, 2, 1), (4, 5, 6, 7)]
    mesh_obj("axehead", vs, fs, mat((150, 156, 162), 0.42, 0.8), bevel=0.02)
    # bright bevelled bit
    vs2 = [v + ed * 0.0 for v in vs[4:]] + [hc + ed * 1.18 - up * 0.66, hc + ed * 1.18 + up * 0.6]
    mesh_obj("axeedge", [vs[4], vs[5], vs2[5], vs2[4], vs[7], vs[6]],
             [(0, 1, 2, 3), (4, 3, 2, 5), (0, 3, 4), (1, 5, 2)], mat((222, 226, 230), 0.25, 0.9))
    box("axeback", (th * 1.1, 0.3, 0.36), frame(hc - ed * 0.18, basis_from(up, ed)), (90, 94, 98), bevel=0.03,
        rough=0.5, metal=0.7)


def knife(grip, blade_dir, flat_n, length=1.25):
    bd = Vector(blade_dir).normalized()
    fn = Vector(flat_n).normalized()
    g = Vector(grip)
    seg_box("khandle", g - bd * 0.3, g + bd * 0.28, 0.2, 0.24, WRAP, y_hint=fn, bevel=0.04)
    seg_box("kguard", g + bd * 0.27, g + bd * 0.35, 0.16, 0.48, (150, 128, 82), y_hint=fn.cross(bd), bevel=0.02)
    side = bd.cross(fn).normalized()
    b0 = g + bd * 0.35
    tip = b0 + bd * length
    vs = [b0 + side * 0.17 + fn * 0.035, b0 - side * 0.13 + fn * 0.035, b0 - side * 0.13 - fn * 0.035,
          b0 + side * 0.17 - fn * 0.035,
          tip - bd * 0.35 + side * 0.15 + fn * 0.02, tip - bd * 0.25 - side * 0.12 + fn * 0.02,
          tip - bd * 0.25 - side * 0.12 - fn * 0.02, tip - bd * 0.35 + side * 0.15 - fn * 0.02, tip - side * 0.05]
    fs = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (0, 3, 2, 1), (4, 5, 8), (5, 6, 8), (6, 7, 8),
          (7, 4, 8)]
    mesh_obj("kblade", vs, fs, mat((226, 230, 236), 0.32, 0.65))


def spear(grip, aim, back=2.4, front=3.2):
    a = Vector(aim).normalized()
    g = Vector(grip)
    p0, p1 = g - a * back, g + a * front
    seg_box("sshaft", p0, p1, 0.15, 0.15, WOOD, bevel=0.02)
    seg_box("swrap", p1 - a * 0.3, p1, 0.2, 0.2, WRAP, bevel=0.02)
    R = basis_from(a, (0, 0, 1))
    hb = p1
    vs = [hb, hb + a * 0.45 + R @ Vector((0.24, 0, 0)), hb + a * 0.45 + R @ Vector((0, 0.06, 0)),
          hb + a * 0.45 + R @ Vector((-0.24, 0, 0)), hb + a * 0.45 + R @ Vector((0, -0.06, 0)), hb + a * 1.35]
    fs = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 1), (1, 5, 2), (2, 5, 3), (3, 5, 4), (4, 5, 1)]
    mesh_obj("shead", vs, fs, mat(STEEL, 0.3, 0.85))


def crate(base, yaw, rng, open_lid=True):
    M = frame(base, rot_xyz(0, 0, yaw))
    W, D, H = 3.0, 2.0, 1.7
    pl = [(132, 98, 62), (118, 86, 54), (140, 104, 66)]
    for i in range(4):  # side planks
        z = 0.22 + i * 0.42
        box("cr_f%d" % i, (W, 0.14, 0.38), M, pl[i % 3], off=(0, -D / 2, z), bevel=0.03)
        box("cr_b%d" % i, (W, 0.14, 0.38), M, pl[(i + 1) % 3], off=(0, D / 2, z), bevel=0.03)
        for sx in (-1, 1):
            box("cr_s%d" % i, (0.14, D, 0.38), M, pl[(i + 2) % 3], off=(sx * W / 2, 0, z), bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("cr_post", (0.26, 0.26, H + 0.05), M, (96, 70, 44), off=(sx * W / 2, sy * D / 2, H / 2), bevel=0.04)
    box("cr_bottom", (W, D, 0.12), M, (90, 66, 42), off=(0, 0, 0.06), bevel=0.02)
    # stencil band (plain, no logo): a cream stripe
    box("cr_band", (W * 0.7, 0.04, 0.3), M, (226, 214, 180), off=(0, -D / 2 - 0.08, 1.05), bevel=0.01)
    if open_lid:
        Ml = M @ frame((0, D / 2 + 0.1, H + 0.05), rot_xyz(-118, 0, 0))
        for i in range(4):
            box("cr_lid%d" % i, (W + 0.1, 0.5, 0.12), Ml, pl[i % 3], off=(0, -0.26 - i * 0.52, 0.06), bevel=0.03)
    return M


def bottle(base, R, col=(70, 130, 170)):
    M = frame(base, R)
    cyl("btl", (0, 0, 0), 0.22, 0.75, 8, col, M=M, rough=0.3, smooth=False)
    cyl("btlneck", (0, 0, 0.75), 0.22, 0.18, 8, col, M=M, top_scale=0.5, rough=0.3)
    cyl("btlcap", (0, 0, 0.93), 0.12, 0.12, 8, (40, 44, 48), M=M)


def pouch(base, R, col):
    M = frame(base, R)
    box("pouch", (0.8, 0.5, 0.6), M, col, bevel=0.15, seg=3)
    box("pouchflap", (0.82, 0.54, 0.16), M, mul(col, 0.8), off=(0, 0, 0.28), bevel=0.06)


def bread(base, R):
    M = frame(base, R)
    box("loaf", (0.9, 0.45, 0.4), M, (196, 140, 76), bevel=0.16, seg=3)


def apple(base, col=(196, 52, 40)):
    me = bpy.data.meshes.new("apple")
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.22)
    bm.to_mesh(me)
    ob = bpy.data.objects.new("apple", me)
    link(ob)
    ob.location = base
    ob.data.materials.append(mat(col, 0.55))


def rope_coil(base, r=0.5, turns=3, col=(176, 150, 104)):
    vs, fs = [], []
    n = 16 * turns
    k = 6
    rr = 0.08
    for i in range(n + 1):
        a = i * 2 * math.pi / 16
        c = Vector(base) + Vector((r * math.cos(a), r * math.sin(a), rr + (i / n) * 0.3))
        rad = Vector((math.cos(a), math.sin(a), 0))
        for j in range(k):
            b = j * 2 * math.pi / k
            vs.append(c + rad * rr * math.cos(b) + Vector((0, 0, rr * math.sin(b))))
    for i in range(n):
        for j in range(k):
            fs.append((i * k + j, i * k + (j + 1) % k, (i + 1) * k + (j + 1) % k, (i + 1) * k + j))
    mesh_obj("coil", vs, fs, mat(col, 0.9), smooth=True)


def plinth(base, r=1.7, glow=0.0):
    x, y, z = base
    cyl("pl_base", (x, y, z - 1.0), r * 1.08, 0.9, 16, (96, 100, 106), rough=0.5, metal=0.6)
    cyl("pl_top", (x, y, z - 0.12), r, 0.12, 16, (150, 156, 162), rough=0.35, metal=0.8)
    if glow > 0:
        # thin glowing ring at the plate edge
        cyl("pl_ring", (x, y, z - 0.16), r * 1.1, 0.06, 32, None, material=emis_mat((255, 196, 110), glow))


# ------------------------------------------------------------------------------------------- arena backdrop
def font_path():
    import glob
    for p in [os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\content\fonts\Oswald-Bold.ttf")]:
        g = sorted(glob.glob(p))
        if g:
            return g[-1]
    return None


def cone_mesh(name, base, r, h, sides, col, rng, tilt=(0, 0, 0), shade=True, emit=0.0):
    x, y, z = base
    R = rot_xyz(*tilt)
    ring = [Vector((r * rng.uniform(0.85, 1.1) * math.cos(i * 2 * math.pi / sides + 0.3),
                    r * rng.uniform(0.85, 1.1) * math.sin(i * 2 * math.pi / sides + 0.3), 0)) for i in range(sides)]
    tip = Vector((0, 0, h))
    vs = [Vector(base) + R @ v for v in ring] + [Vector(base) + R @ tip]
    fs = [(i, (i + 1) % sides, sides) for i in range(sides)] + [tuple(reversed(range(sides)))]
    return mesh_obj(name, vs, fs, mat(col, 0.88))


def pine(base, h, rng, col=(50, 84, 50)):
    x, y, z = base
    cyl("trunk", (x, y, z - 0.5), h * 0.045, h * 0.3, 5, (88, 64, 46), rough=0.9)
    tiers = 4
    for t in range(tiers):
        f = t / tiers
        r = h * (0.28 - 0.18 * f) * rng.uniform(0.9, 1.1)
        c = mul(col, rng.uniform(0.88, 1.12))
        cone_mesh("needles", (x, y, z + h * (0.16 + 0.6 * f)), r, h * (0.4 - 0.1 * f), 7, c, rng)


def mountain(base, r, h, rng, rock=(118, 124, 134), snow=(236, 240, 246), snow_frac=0.42):
    """Low-poly peak: faceted cone with a white snow cap, flat-shaded facets lit by the sun."""
    x, y, z = base
    sides = 9
    ring = []
    for i in range(sides):
        a = i * 2 * math.pi / sides
        rr = r * rng.uniform(0.75, 1.15)
        ring.append(Vector((x + rr * math.cos(a), y + rr * math.sin(a) * 0.7, z)))
    mid = []
    for i in range(sides):
        a = (i + 0.5) * 2 * math.pi / sides
        rr = r * snow_frac * rng.uniform(0.8, 1.2)
        mid.append(Vector((x + rr * math.cos(a), y + rr * math.sin(a) * 0.7, z + h * (1 - snow_frac) *
                           rng.uniform(0.9, 1.1))))
    tip = Vector((x + rng.uniform(-0.05, 0.05) * r, y, z + h))
    vs = ring + mid + [tip]
    fs, cols = [], []
    for i in range(sides):
        j = (i + 1) % sides
        fs.append((i, j, sides + i)); cols.append(rock)
        fs.append((j, sides + j, sides + i)); cols.append(mul(rock, 0.92))
        fs.append((sides + i, sides + j, 2 * sides)); cols.append(snow)
    ob = mesh_obj("mtn", vs, fs, mat(rock, 0.9))
    snow_m = mat(snow, 0.8)
    ob.data.materials.append(snow_m)
    for p, c in zip(ob.data.polygons, cols):
        p.material_index = 1 if c == snow else 0
    return ob


def horn(base, scale, yaw=0.0, glow=1.0):
    """The Horn as seen in game: three tall pale-blue spires around a dark-blue mouth, gold seams."""
    M = frame(base, rot_xyz(0, 0, yaw)) @ Matrix.Scale(scale, 4)
    pale = mat((196, 222, 240), 0.45, 0.1)
    pale2 = mat((170, 200, 228), 0.5, 0.1)
    navy = mat((34, 56, 112), 0.4, 0.2)
    gold = mat((232, 180, 70), 0.3, 0.9, emit=0.6 * glow, emit_col=(255, 196, 90))

    def spire(cx, cy, w, d, h, lean):
        Ms = M @ frame((cx, cy, 0), rot_xyz(lean[0], lean[1], 0))
        vs = [Ms @ Vector(v) for v in [(-w, -d, 0), (w, -d, 0), (w, d, 0), (-w, d, 0), (0, d * 0.2, h)]]
        fs = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
        ob = mesh_obj("spire", vs, fs, pale)
        ob.data.materials.append(pale2)
        ob.data.polygons[1].material_index = 1
        ob.data.polygons[3].material_index = 1
        # gold seam up the front edge
        seg_box("seam", vs[0].lerp(vs[1], 0.5), vs[4], 0.16 * scale, 0.16 * scale, None, material=gold, bevel=0.0)
        return vs

    spire(0, 0.5, 3.2, 2.6, 30, (0, 0))
    spire(-4.6, -0.4, 2.8, 2.4, 23, (0, -9))
    spire(4.6, -0.4, 2.8, 2.4, 22, (0, 10))
    spire(-2.0, 2.4, 2.2, 2.0, 25, (6, -4))
    spire(2.2, 2.4, 2.2, 2.0, 26, (6, 5))
    # dark mouth between the spires with a gold-trimmed pointed arch
    vs = [M @ Vector(v) for v in [(-2.4, -2.2, 0), (2.4, -2.2, 0), (0, -2.0, 14)]]
    mesh_obj("mouth", vs, [(0, 1, 2)], navy)
    for a, b in ((vs[0], vs[2]), (vs[1], vs[2])):
        seg_box("arch", a + Vector((0, -0.05, 0)), b + Vector((0, -0.05, 0)), 0.22 * scale, 0.22 * scale, None,
                material=gold, bevel=0.0)
    # platform
    Mp = M
    box("dais", (18, 14, 1.2), Mp, (214, 218, 222), off=(0, 0, -0.5), bevel=0.05)
    box("daisband", (18.2, 14.2, 0.3), Mp, (40, 70, 140), off=(0, 0, 0.0), bevel=0.02)


def hex_wall(center, radius, height, cell, col, strength, rng, arc=(-70, 70)):
    """Glowing hexagonal border-force-field lines on a big curved wall."""
    m = emis_mat(col, strength)
    vs, fs = [], []
    cx, cy, cz = center
    w = cell * math.sqrt(3)
    rows = int(height / (cell * 1.5)) + 1
    a0, a1 = math.radians(arc[0]), math.radians(arc[1])
    cols_n = int((a1 - a0) * radius / w) + 1
    t = 0.03 * cell

    def P(ang_x, z):
        a = a0 + ang_x / radius
        return Vector((cx + radius * math.sin(a), cy + radius * math.cos(a), cz + z))

    for r in range(rows):
        for c in range(cols_n):
            if rng.random() < 0.08:
                continue
            ox = c * w + (w / 2 if r % 2 else 0)
            oz = r * cell * 1.5
            corners = [(ox + cell * math.cos(math.radians(30 + 60 * k)), oz + cell * math.sin(math.radians(30 + 60 * k)))
                       for k in range(6)]
            for k in range(6):
                (x0, z0), (x1, z1) = corners[k], corners[(k + 1) % 6]
                dx, dz = x1 - x0, z1 - z0
                L = math.hypot(dx, dz)
                nx, nz = -dz / L * t, dx / L * t
                i = len(vs)
                vs += [P(x0 - nx, z0 - nz), P(x1 - nx, z1 - nz), P(x1 + nx, z1 + nz), P(x0 + nx, z0 + nz)]
                fs.append((i, i + 1, i + 2, i + 3))
    ob = mesh_obj("hexwall", vs, fs, m)
    ob.visible_shadow = False
    # faint fill so the cells read as a translucent wall
    return ob


def ground(size, z, rng, col=(76, 128, 52), center=(0, 0), n=60):
    cx, cy = center
    vs, fs, cols = [], [], []
    step = size / n
    hgt = {}
    for i in range(n + 1):
        for j in range(n + 1):
            x = cx - size / 2 + i * step
            y = cy - size / 2 + j * step
            hgt[(i, j)] = z + rng.uniform(-0.15, 0.15) * step * 0.2
            vs.append(Vector((x, y, hgt[(i, j)])))
    for i in range(n):
        for j in range(n):
            a = i * (n + 1) + j
            fs.append((a, a + n + 1, a + n + 2, a + 1))
    ob = mesh_obj("ground", vs, fs, mat(col, 0.95))
    # per-face colour variation via a colour attribute
    at = ob.data.color_attributes.new("col", "FLOAT_COLOR", "FACE")
    flat = []
    for _ in fs:
        flat.extend(lin(mul(col, rng.uniform(0.85, 1.12))))
    at.data.foreach_set("color", flat)
    m = bpy.data.materials.new("Ground")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    an = nt.nodes.new("ShaderNodeAttribute"); an.attribute_name = "col"
    nt.links.new(an.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    ob.data.materials.clear()
    ob.data.materials.append(m)
    return ob


def grass_tufts(center, radius, count, rng, col=(84, 150, 56), z=0.0, h=(0.5, 1.1)):
    vs, fs = [], []
    cx, cy = center
    for _ in range(count):
        a = rng.uniform(0, 2 * math.pi)
        r = radius * math.sqrt(rng.random())
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        for k in range(3):
            ang = rng.uniform(0, math.pi)
            ww = rng.uniform(0.06, 0.12)
            hh = rng.uniform(*h)
            lean = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))
            d = Vector((math.cos(ang), math.sin(ang), 0)) * ww
            i = len(vs)
            vs += [Vector((x, y, z)) - d, Vector((x, y, z)) + d, Vector((x, y, z + hh)) + lean]
            fs.append((i, i + 1, i + 2))
    ob = mesh_obj("grass", vs, fs, mat(col, 0.85))
    return ob


def dust(center, size, count, rng, col=(255, 226, 170), strength=2.0, rmin=0.02, rmax=0.07):
    import bmesh
    me = bpy.data.meshes.new("dust")
    bm = bmesh.new()
    cx, cy, cz = center
    sx, sy, sz = size
    for _ in range(count):
        r = rng.uniform(rmin, rmax)
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
        off = Vector((cx + rng.uniform(-sx, sx) / 2, cy + rng.uniform(-sy, sy) / 2, cz + rng.uniform(-sz, sz) / 2))
        bmesh.ops.translate(bm, vec=off, verts=res["verts"])
    bm.to_mesh(me)
    ob = bpy.data.objects.new("dust", me)
    link(ob)
    m = mat(col, 0.9, emit=strength, emit_col=col)
    ob.data.materials.append(m)
    ob.visible_shadow = False
    return ob


def dust_cloud(center, size, density, col=(214, 186, 140), aniso=0.5):
    """A box of thin volume haze (sun shafts / kicked-up dust)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    ob = bpy.context.active_object
    ob.scale = size
    m = bpy.data.materials.new("Haze")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    v = nt.nodes.new("ShaderNodeVolumePrincipled")
    v.inputs["Color"].default_value = lin(col)
    v.inputs["Density"].default_value = density
    v.inputs["Anisotropy"].default_value = aniso
    nt.links.new(v.outputs[0], nt.nodes["Material Output"].inputs["Volume"])
    ob.data.materials.append(m)
    return ob


def puff(center, radius, density, rng, col=(200, 172, 130), n=5):
    """Kicked-up dust puffs: a cluster of noisy volume spheres."""
    m = bpy.data.materials.new("Puff")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    v = nt.nodes.new("ShaderNodeVolumePrincipled")
    v.inputs["Color"].default_value = lin(col)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.5
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    # radial falloff * noise
    ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"
    nt.links.new(tc.outputs["Object"], ln.inputs[0])
    fall = nt.nodes.new("ShaderNodeMapRange")
    fall.inputs["From Min"].default_value = 1.0; fall.inputs["From Max"].default_value = 0.2
    nt.links.new(ln.outputs["Value"], fall.inputs["Value"])
    mm = nt.nodes.new("ShaderNodeMath"); mm.operation = "MULTIPLY"
    nt.links.new(fall.outputs["Result"], mm.inputs[0])
    nt.links.new(nz.outputs["Fac"], mm.inputs[1])
    md = nt.nodes.new("ShaderNodeMath"); md.operation = "MULTIPLY"; md.inputs[1].default_value = density
    nt.links.new(mm.outputs[0], md.inputs[0])
    nt.links.new(md.outputs[0], v.inputs["Density"])
    nt.links.new(v.outputs[0], nt.nodes["Material Output"].inputs["Volume"])
    for _ in range(n):
        c = Vector(center) + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.5))) * radius * 0.6
        r = radius * rng.uniform(0.5, 1.0)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=c)
        ob = bpy.context.active_object
        ob.scale = (r, r, r * 0.8)
        ob.data.materials.append(m)


def sky(zenith, horizon, sun_dir, sun_col, glow=1.0, strength=1.0):
    w = bpy.data.worlds.new("Sky")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    N, L = nt.nodes, nt.links
    bg = N["Background"]
    tc = N.new("ShaderNodeTexCoord")
    nrm = N.new("ShaderNodeVectorMath"); nrm.operation = "NORMALIZE"
    L.new(tc.outputs["Generated"], nrm.inputs[0])
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(nrm.outputs["Vector"], sep.inputs[0])
    mr = N.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -0.05; mr.inputs["From Max"].default_value = 0.6
    L.new(sep.outputs["Z"], mr.inputs["Value"])
    ramp = N.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0; cr.elements[0].color = lin(horizon)
    cr.elements[1].position = 1.0; cr.elements[1].color = lin(zenith)
    e = cr.elements.new(0.22); e.color = lin((120, 182, 240))
    e3 = cr.elements.new(0.07); e3.color = lin(mixc(horizon, (150, 200, 240), 0.45))
    L.new(mr.outputs["Result"], ramp.inputs["Fac"])
    dot = N.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
    L.new(nrm.outputs["Vector"], dot.inputs[0])
    dot.inputs[1].default_value = Vector(sun_dir).normalized()
    cl = N.new("ShaderNodeMath"); cl.operation = "MAXIMUM"; cl.inputs[1].default_value = 0.0
    L.new(dot.outputs["Value"], cl.inputs[0])
    pw = N.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 10.0
    L.new(cl.outputs[0], pw.inputs[0])
    m1 = N.new("ShaderNodeMath"); m1.operation = "MULTIPLY"; m1.inputs[1].default_value = glow
    L.new(pw.outputs[0], m1.inputs[0])
    mx = N.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "ADD"
    L.new(m1.outputs[0], mx.inputs["Factor"])
    L.new(ramp.outputs["Color"], mx.inputs["A"])
    mx.inputs["B"].default_value = lin(sun_col)
    L.new(mx.outputs["Result"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength


def sun(direction, col, strength, angle=3.0):
    d = bpy.data.lights.new("Sun", "SUN")
    d.energy = strength
    d.color = lin(col)[:3]
    d.angle = math.radians(angle)
    o = bpy.data.objects.new("Sun", d)
    link(o)
    o.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()
    return o


def area(loc, target, col, power, size=3.0, shadow=True):
    d = bpy.data.lights.new("Area", "AREA")
    d.energy = power
    d.color = lin(col)[:3]
    d.size = size
    o = bpy.data.objects.new("Area", d)
    link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    try:
        o.visible_camera = False
    except Exception:
        pass
    if not shadow:
        try:
            d.use_shadow = False
        except Exception:
            pass
    return o


def camera(loc, target, lens=50.0, focus=None, fstop=2.8, roll=0.0):
    c = bpy.data.cameras.new("Cam")
    c.lens = lens
    c.clip_end = 5000
    c.clip_start = 0.05
    o = bpy.data.objects.new("Cam", c)
    link(o)
    o.location = loc
    q = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y")
    o.rotation_euler = q.to_euler()
    if roll:
        o.rotation_euler.rotate_axis("Z", math.radians(roll))
    bpy.context.scene.camera = o
    if focus is not None:
        c.dof.use_dof = True
        c.dof.focus_distance = (Vector(focus) - Vector(loc)).length
        c.dof.aperture_fstop = fstop
    bpy.context.view_layer.update()
    return o


def backdrop(rng, horn_pos=(0, 70, 0), horn_scale=1.3, horn_yaw=0.0, hex_center=(0, -20, -5), hex_r=230.0,
             hex_strength=6.0, pines=True, mtn=True, ground_col=(76, 128, 52)):
    ground(600, 0.0, rng, col=ground_col, center=(0, 150), n=70)
    horn(horn_pos, horn_scale, yaw=horn_yaw)
    # plinth ring around the Horn (small, far)
    for k in range(16):
        a = k * 2 * math.pi / 16
        p = Vector(horn_pos) + Vector((math.sin(a) * 26, -math.cos(a) * 20, 0))
        if p.y < 10:
            continue
        cyl("rp", (p.x, p.y, -0.2), 1.6, 0.7, 12, (150, 156, 162), rough=0.4, metal=0.7)
    if pines:
        for _ in range(140):
            x = rng.uniform(-260, 260)
            y = rng.uniform(110, 260)
            if abs(x) < 40 and y < 150:
                continue
            pine((x, y, 0), rng.uniform(14, 26), rng)
    if mtn:
        mountain((-150, 420, -5), 150, 180, rng)
        mountain((90, 470, -5), 170, 230, rng)
        mountain((260, 400, -5), 130, 150, rng)
        mountain((-330, 450, -5), 140, 160, rng)
    hex_wall(hex_center, hex_r, 150, 7.0, (90, 190, 255), hex_strength, rng)


# ------------------------------------------------------------------------------------------- concepts
def head_box_px(av, cam, res):
    sc = bpy.context.scene
    s = av.hs
    pts = []
    Mh = frame(av.head_c, av.Rh)
    for dx in (-1, 1):
        for dy in (-1, 1):
            for dz in (-1, 1):
                p = Mh @ Vector((dx * FACE_W * s * 0.6, dy * 0.7 * s, dz * FACE_H * s * 0.65))
                v = world_to_camera_view(sc, cam, p)
                pts.append((v.x * res, (1 - v.y) * res))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [min(xs), min(ys), max(xs), max(ys)]


def far_crowd(rng, spots):
    """Other contenders waiting on far plinths (small, soft in the background)."""
    cols = [(120, 60, 40), (60, 70, 110), (90, 100, 50), (110, 90, 60), (70, 90, 90)]
    for k, (x, y) in enumerate(spots):
        far = Avatar("far%d" % k, (x, y, 2.15 + 0.35), yaw=rng.uniform(-40, 40),
                     outfit=Outfit(jacket=cols[k % len(cols)], hood=bool(k % 2), band_num=""), expr="determined")
        far.build_body(); far.build_head()
        far.arm("L", far.sh["L"] + Vector((0.3, -0.3, -1.7)), far.sh["L"] + Vector((0, -2, 0)))
        far.arm("R", far.sh["R"] + Vector((-0.3, -0.3, -1.7)), far.sh["R"] + Vector((0, -2, 0)))
        far.leg("L", far.hip["L"] + Vector((0, 0, -1.75)), far.hip["L"] + Vector((0, -2, 0)))
        far.leg("R", far.hip["R"] + Vector((0, 0, -1.75)), far.hip["R"] + Vector((0, -2, 0)))
        plinth((x, y, 0.35), glow=4.0)


def front_light(key_dir, glow_dir, sky_glow=1.4, sun_strength=5.0):
    """Bright front-page lighting: the sun from the camera side for clean saturated colour, a warm sunset glow
    in the sky behind the subject, rim lights added per concept."""
    sky((30, 88, 206), (255, 214, 160), glow_dir, (255, 196, 120), glow=sky_glow * 0.6, strength=1.0)
    sun(key_dir, (255, 236, 206), sun_strength, 2.5)


def concept_a(res):
    rng = random.Random(SEED + 1)
    o = Outfit(skin=(214, 156, 112), jacket=(54, 90, 56), jacket_dark=(34, 58, 38), vest=(122, 96, 60),
               hair=(56, 36, 24), band_num="27", hood=True)
    # left-handed draw: the bow is in the right hand (viewer's left), the string hand anchors at the left jaw
    av = Avatar("hero", (0, 0, 2.15), yaw=-28, outfit=o, expr="intense", waist=(4, 0, -4), neck=(-4, 6, 40),
                head_scale=1.12)
    aim = Vector((-0.5, -0.86, -0.03)).normalized()
    anchor = av.head_c + Vector((0.5, -0.62, -0.5))
    grip = anchor + aim * 2.7
    av.build_body()
    av.build_head()
    av.arm("R", grip - aim * 0.22, av.sh["R"] + Vector((-1.0, 0.5, -2.0)))
    av.arm("L", anchor + Vector((0.05, 0.2, -0.15)), av.sh["L"] + Vector((1.2, 3.0, 0.6)))
    av.leg("R", av.hip["R"] + Vector((-0.4, -0.3, -1.75)), av.hip["R"] + Vector((0, -2, 0)))
    av.leg("L", av.hip["L"] + Vector((0.3, 0.4, -1.75)), av.hip["L"] + Vector((0, -2, 0)))
    up = (Vector((0, 0, 1)) - aim * aim.z).normalized()
    up = (up + aim.cross(Vector((0, 0, 1))).normalized() * -0.12).normalized()
    bow(grip, up, aim, anchor + aim * 0.05, height=3.7)
    arrow(anchor - aim * 0.12, grip + aim * 1.25)
    # quiver on the back
    Mq = frame(av.waist_p + av.Rw @ Vector((0.6, 0.95, 1.0)), av.Rw @ rot_xyz(-14, -25, 0))
    box("quiver", (0.5, 0.5, 2.0), Mq, (86, 62, 42), bevel=0.1)
    for k in range(4):
        x = -0.12 + k * 0.08
        seg_box("qarrow", Mq @ Vector((x, 0, 0.9)), Mq @ Vector((x, 0, 1.6)), 0.06, 0.06, (196, 166, 120), bevel=0.0)
        seg_box("qfl", Mq @ Vector((x, 0, 1.3)), Mq @ Vector((x, 0, 1.62)), 0.03, 0.18,
                (214, 92, 44) if k % 2 else (236, 226, 204), bevel=0.0)
    backdrop(rng, horn_pos=(-58, 74, 0), horn_scale=1.9, horn_yaw=0.45, hex_center=(0, -30, -10), hex_r=260,
             hex_strength=1.2)
    grass_tufts((0, 3), 14, 500, rng)
    far_crowd(rng, ((-14, 46), (-26, 52), (40, 58), (6, 70)))
    front_light(Vector((-0.45, -0.75, 0.5)), Vector((0.35, 0.9, 0.12)))
    area((-5, -7, 7.5), av.head_c, (255, 236, 214), 500, 4.0)
    area((5, -5, 3.0), av.head_c, (170, 205, 255), 200, 4.0)
    area((3.5, 4.5, 7.0), av.head_c, (150, 210, 255), 1600, 2.0)   # cyan rim (hex-wall side)
    area((-4.0, 4.0, 6.0), av.head_c, (255, 180, 110), 1600, 2.0)  # warm rim (sunset side)
    dust((0, 6, 5), (16, 8, 6), 140, rng, strength=1.4, rmin=0.012, rmax=0.035)
    dust_cloud((0, 40, 10), (200, 60, 30), 0.0015)
    cam_loc = Vector((2.0, -5.7, 5.0))
    target = av.head_c + Vector((-0.75, -0.6, -0.55))
    cam = camera(cam_loc, target, lens=36, focus=av.head_c + Vector((0, -0.6, 0)), fstop=2.4)
    return cam, [av]


def concept_b(res):
    rng = random.Random(SEED + 2)
    # attacker (left): axe raised overhead, roaring
    o1 = Outfit(skin=(150, 98, 64), jacket=(140, 70, 38), jacket_dark=(96, 46, 26), vest=(70, 80, 52),
                pants=(78, 74, 62), hair=(28, 22, 18), hood=False, hair_style="short", band_num="09",
                pack=(80, 86, 60))
    a = Avatar("axe", (-2.1, 0.4, 2.15), yaw=42, lean=-10, outfit=o1, expr="fury", waist=(-8, 0, 6),
               neck=(8, 0, -16), head_scale=1.14)
    a.build_body(); a.build_head()
    top = a.head_c + Vector((0.5, 0.45, 1.8))
    a.arm("R", top + Vector((-0.2, 0.05, -0.15)), a.sh["R"] + Vector((-2, -0.5, 0.5)))
    a.arm("L", top + Vector((0.2, -0.05, -0.45)), a.sh["L"] + Vector((2, -0.5, 0.5)))
    a.leg("R", a.hip["R"] + Vector((-0.5, 0.8, -1.65)), a.hip["R"] + Vector((0, -2, 0)))
    a.leg("L", a.hip["L"] + Vector((0.7, -0.9, -1.55)), a.hip["L"] + Vector((0, -2, 0)))
    axe(top, Vector((0.75, -0.1, 0.9)).normalized(), Vector((0.75, -0.45, -0.3)).normalized(), length=3.2)
    # defender (right): ducking low under the swing, knife up, shocked
    o2 = Outfit(skin=(236, 196, 160), jacket=(46, 96, 92), jacket_dark=(30, 64, 62), vest=(124, 100, 66),
                pants=(98, 88, 66), hair=(200, 132, 56), hood=False, hair_style="band", band_col=(176, 60, 44),
                band_num="33")
    d = Avatar("knife", (1.9, -0.9, 1.65), yaw=-36, lean=26, roll=-6, outfit=o2, expr="shock", waist=(10, 0, -6),
               neck=(-44, 0, 10), head_scale=1.14)
    d.build_body(); d.build_head()
    kh = d.sh["L"] + Vector((-0.2, -1.1, 0.6))
    d.arm("L", kh, d.sh["L"] + Vector((2, 0.5, -1)))
    d.arm("R", d.sh["R"] + Vector((-0.6, -1.0, 0.95)), d.sh["R"] + Vector((-2, 0, -1)))
    d.leg("R", d.hip["R"] + Vector((-0.6, -1.0, -1.05)), d.hip["R"] + Vector((0, -3, 1)))
    d.leg("L", d.hip["L"] + Vector((0.3, 1.0, -1.2)), d.hip["L"] + Vector((0, -3, 1)))
    knife(d.handL.translation, Vector((-0.55, -0.15, 1.0)), Vector((0.5, -0.85, 0.1)), length=1.2)
    # supply crate spilling between them, behind-right; loot scattered toward the camera
    crate((4.3, -1.6, 0.0), math.radians(-32), rng)
    bottle((3.0, -0.4, 0.22), rot_xyz(90, 0, 60))
    bottle((4.6, 0.6, 0.0), rot_xyz(0, 0, 0), col=(60, 120, 90))
    pouch((2.6, -2.6, 0.3), rot_xyz(0, 0, 30), (150, 92, 50))
    bread((0.6, -2.8, 0.2), rot_xyz(0, 0, -20))
    apple((-0.2, -3.4, 0.22)); apple((1.4, -3.9, 0.22), col=(214, 160, 50))
    rope_coil((-3.8, -2.0, 0.0), 0.55)
    backdrop(rng, horn_pos=(-2, 40, 0), horn_scale=1.35, horn_yaw=0.1, hex_center=(0, -40, -10), hex_r=260,
             hex_strength=1.2)
    grass_tufts((0, 0), 14, 600, rng)
    far_crowd(rng, ((-22, 30), (18, 28), (30, 36)))
    front_light(Vector((0.35, -0.8, 0.55)), Vector((-0.3, 0.9, 0.12)))
    area((-1, -9, 7), (0, 0, 4), (255, 236, 214), 900, 6.0)
    area((-5, 5, 9), a.head_c, (255, 180, 110), 2200, 2.5)
    area((5, 4, 6), d.head_c, (150, 210, 255), 1800, 2.5)
    dust((0, 4, 4), (16, 8, 6), 140, rng, strength=1.4, rmin=0.012, rmax=0.035)
    dust_cloud((0, 30, 8), (200, 40, 20), 0.0015)
    puff((0.6, -0.6, 0.3), 1.3, 0.8, rng, n=4)
    cam = camera((0.0, -8.4, 2.5), (0.0, 0, 4.1), lens=30, focus=(0.0, -0.4, 4.0), fstop=4.0, roll=3)
    return cam, [a, d]


def concept_c(res):
    rng = random.Random(SEED + 3)
    # sprinter: leaning hard into the run, right knee driving up, left arm pumping forward with a knife
    o = Outfit(skin=(198, 140, 98), jacket=(56, 92, 58), jacket_dark=(36, 60, 40), vest=(126, 98, 62),
               hair=(40, 28, 20), hood=True, band_num="41")
    s = Avatar("run", (0, 0, 2.5), yaw=10, lean=26, outfit=o, expr="determined", waist=(6, 0, -12),
               neck=(-30, 0, 4), head_scale=1.16)
    s.build_body(); s.build_head()
    s.arm("L", s.sh["L"] + Vector((-0.5, -1.4, 0.35)), s.sh["L"] + Vector((1.2, 0.0, -2)))
    s.arm("R", s.sh["R"] + Vector((-0.4, 1.3, -0.9)), s.sh["R"] + Vector((-1.5, -2, 0)))
    s.leg("R", s.hip["R"] + Vector((0.0, -1.35, -0.9)), s.hip["R"] + Vector((0, -3, 0.5)),
          toe_dir=Vector((0, -1, -0.3)))
    s.leg("L", s.hip["L"] + Vector((0.1, 1.2, -1.3)), s.hip["L"] + Vector((0, -2, 0)),
          toe_dir=Vector((0, -0.4, -1)))
    knife(s.handL.translation, Vector((0.35, -0.55, 1.0)), Vector((0.9, 0.3, 0)), length=1.35)
    # the plinth being left behind, and the countdown beacon blazing behind it
    plinth((0.2, 2.6, 0.35), r=1.8, glow=14.0)
    beacon = Vector((7.5, 14.0, 0))
    cyl("bpole", (beacon.x, beacon.y, 0), 0.3, 7.0, 8, (80, 84, 90), rough=0.5, metal=0.6)
    cyl("blamp", (beacon.x, beacon.y, 7.0), 1.3, 0.9, 16, None, material=emis_mat((255, 150, 60), 40.0))
    cyl("bcap", (beacon.x, beacon.y, 7.9), 1.4, 0.25, 16, (70, 74, 80), rough=0.5, metal=0.6)
    pt = bpy.data.lights.new("beacon", "POINT"); pt.energy = 5000; pt.color = lin((255, 150, 70))[:3]
    pt.shadow_soft_size = 1.2
    po = bpy.data.objects.new("beacon", pt); link(po); po.location = beacon + Vector((0, -1.8, 7.4))
    # rival sprinting close behind with a spear
    o2 = Outfit(skin=(120, 80, 54), jacket=(140, 74, 40), jacket_dark=(94, 48, 28), vest=(70, 72, 56),
                pants=(84, 78, 64), hair=(24, 20, 16), hood=False, hair_style="short", band_num="16")
    r = Avatar("rival", (-3.6, 5.4, 2.5), yaw=-18, lean=16, outfit=o2, expr="fury", waist=(4, 0, 6),
               neck=(-16, 0, 0), head_scale=1.12)
    r.build_body(); r.build_head()
    sg = r.sh["R"] + Vector((-0.3, -0.9, 0.75))
    r.arm("R", sg, r.sh["R"] + Vector((-2, 1, -1)))
    r.arm("L", r.sh["L"] + Vector((0.3, -1.5, -0.4)), r.sh["L"] + Vector((2, 0, -1)))
    r.leg("L", r.hip["L"] + Vector((0, -1.3, -1.0)), r.hip["L"] + Vector((0, -3, 0.5)))
    r.leg("R", r.hip["R"] + Vector((0, 1.1, -1.4)), r.hip["R"] + Vector((0, -2, 0)))
    spear(sg, Vector((0.45, -1.0, 0.12)), back=2.6, front=2.2)
    plinth((-3.8, 8.6, 0.35), r=1.8, glow=8.0)
    backdrop(rng, horn_pos=(12, 46, 0), horn_scale=1.35, horn_yaw=0.2, hex_center=(0, -40, -10), hex_r=260,
             hex_strength=1.2)
    grass_tufts((0, 0), 16, 700, rng)
    far_crowd(rng, ((-16, 26), (24, 24), (-28, 34)))
    front_light(Vector((-0.4, -0.75, 0.5)), Vector((0.2, 0.9, 0.12)), sky_glow=1.8)
    area((-3, -9, 7), s.head_c, (255, 236, 214), 700, 5.0)
    area((-3, 4, 7), s.head_c, (255, 170, 100), 2000, 2.5)
    area((4, 3, 6), s.head_c, (150, 210, 255), 1400, 2.5)
    puff((0.3, 1.9, 0.5), 1.7, 1.0, rng, n=6)
    puff((-3.4, 6.8, 0.4), 1.5, 0.8, rng, n=4)
    dust((0, 3, 2.5), (12, 8, 5), 160, rng, strength=1.4, rmin=0.012, rmax=0.035)
    dust_cloud((0, 30, 8), (200, 40, 20), 0.0015)
    cam = camera((-0.7, -6.4, 2.3), (0.0, 0.2, 3.5), lens=26, focus=s.head_c + Vector((0, -0.4, 0)), fstop=3.2,
                 roll=-6)
    return cam, [s, r]


def main():
    out, opts, res, samples = argv()
    os.makedirs(out, exist_ok=True)
    fn = {"a": concept_a, "b": concept_b, "c": concept_c}
    for k in opts:
        sc = reset(res, samples)
        cam, avs = fn[k](res)
        sc.render.filepath = os.path.join(out, "concept%s_raw.png" % k.upper())
        bpy.ops.render.render(write_still=True)
        meta = {"heads": [head_box_px(av, cam, res) for av in avs], "res": res}
        with open(os.path.join(out, "concept%s_meta.json" % k.upper()), "w") as f:
            json.dump(meta, f)
        print("WROTE", sc.render.filepath, meta)


main()
