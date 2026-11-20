"""
arena48_icon.py - game icon options for "#ARENA 48" (Roblox icon, 512x512), Blender 5.3 headless, seeded.

  blender --background --factory-startup --python art/blender/icon/arena48_icon.py -- <out_dir> [a] [b] [c]

Writes <out_dir>/arena48_icon_<x>.png (512) and arena48_icon_<x>_150.png (150 downscale) per option:
  a  the Horn on its plinth ring in the valley at dusk, "48" above
  b  a blocky contender rising on a launch plinth into low sun glare, pine forest framing, "48" below
  c  a bold faceted "48" in rust-to-moss letters, blue hex border wall lit behind, night forest, amber glow

Style: chunky faceted low-poly forms, colour painted per face (FACE colour attribute), matte, Cycles + AgX.
No bird, ring emblem, arrow, pin or film branding. Text only "48". Font: Oswald Bold (ships with Roblox),
falls back to Bahnschrift / Impact.
"""
import glob
import math
import os
import random
import sys

import bpy
from mathutils import Vector, noise

SEED = 4848
INK = (244, 241, 234)
AMBER = (232, 182, 90)
RUST = (150, 72, 38)
MOSS = (96, 118, 52)


def argv():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = a[0] if a else os.path.join(os.path.dirname(__file__), "out")
    opts = [x.lower() for x in a[1:]] or ["a", "b", "c"]
    return out, opts


def lin(c):
    def f(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


def mixc(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def jit(c, rng, amt=0.06):
    k = 1.0 + rng.uniform(-amt, amt)
    return tuple(max(0, min(255, v * k)) for v in c)


def font_path():
    pats = [os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\content\fonts\Oswald-Bold.ttf"),
            r"C:\Program Files (x86)\Roblox\Versions\*\content\fonts\Oswald-Bold.ttf"]
    for p in pats:
        g = sorted(glob.glob(p))
        if g:
            return g[-1]
    for p in [r"C:\Windows\Fonts\bahnschrift.ttf", r"C:\Windows\Fonts\impact.ttf"]:
        if os.path.exists(p):
            return p
    return None


# ------------------------------------------------------------------------------------------- scene basics
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 128
    sc.cycles.use_denoising = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for dt in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                prefs.compute_device_type = dt
                prefs.get_devices()
                if any(d.type == dt for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = True
                    sc.cycles.device = "GPU"
                    break
            except Exception:
                continue
    except Exception:
        pass
    return sc


_MATS = {}


def facecol_mat(name="FaceCol", rough=0.85, metal=0.0, emit=0.0):
    key = (name, rough, metal, emit)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "col"
    nt.links.new(at.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0:
        nt.links.new(at.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = emit
    _MATS[key] = m
    return m


def plain_mat(name, col, rough=0.85, metal=0.0, emit_col=None, emit=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit_col is not None:
        b.inputs["Emission Color"].default_value = lin(emit_col)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
    return m


class Batch:
    """Accumulates triangles/quads with a per-face sRGB colour, emits one flat-shaded object."""

    def __init__(self):
        self.v, self.f, self.c = [], [], []

    def face(self, pts, col):
        i = len(self.v)
        self.v.extend(pts)
        self.f.append(tuple(range(i, i + len(pts))))
        self.c.append(col)

    def emit(self, name, mat=None, parent=None):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p) for p in self.v], [], self.f)
        me.update()
        set_face_cols(me, self.c)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(mat or facecol_mat())
        if parent:
            ob.parent = parent
        return ob


def set_face_cols(me, cols):
    at = me.color_attributes.get("col") or me.color_attributes.new("col", "FLOAT_COLOR", "FACE")
    flat = []
    for c in cols:
        flat.extend(lin(c))
    at.data.foreach_set("color", flat)


def prism(b, base, r, h, sides, col_side, col_top, rot=0.0, taper=1.0, shade=True, top=True):
    """Vertical faceted prism / frustum. base = (x,y,z)."""
    x, y, z = base
    lo = [Vector((x + r * math.cos(rot + i * 2 * math.pi / sides), y + r * math.sin(rot + i * 2 * math.pi / sides), z))
          for i in range(sides)]
    hi = [Vector((x + r * taper * math.cos(rot + i * 2 * math.pi / sides),
                  y + r * taper * math.sin(rot + i * 2 * math.pi / sides), z + h)) for i in range(sides)]
    for i in range(sides):
        j = (i + 1) % sides
        a = rot + (i + 0.5) * 2 * math.pi / sides
        k = 0.82 + 0.18 * (0.5 + 0.5 * math.cos(a - 0.8)) if shade else 1.0
        b.face([lo[i], lo[j], hi[j], hi[i]], tuple(v * k for v in col_side))
    if top:
        if taper > 0.001:
            b.face(hi, col_top)


def cone(b, base, r, h, sides, col, rng, rot=0.0):
    x, y, z = base
    tip = Vector((x + rng.uniform(-0.05, 0.05) * r, y + rng.uniform(-0.05, 0.05) * r, z + h))
    ring = [Vector((x + r * rng.uniform(0.85, 1.1) * math.cos(rot + i * 2 * math.pi / sides),
                    y + r * rng.uniform(0.85, 1.1) * math.sin(rot + i * 2 * math.pi / sides),
                    z + rng.uniform(-0.06, 0.06) * h)) for i in range(sides)]
    for i in range(sides):
        j = (i + 1) % sides
        a = rot + (i + 0.5) * 2 * math.pi / sides
        k = 0.78 + 0.3 * (0.5 + 0.5 * math.cos(a - 0.7))
        b.face([ring[i], ring[j], tip], tuple(min(255, v * k) for v in jit(col, rng, 0.05)))
    b.face(list(reversed(ring)), tuple(v * 0.55 for v in col))


def pine(b, base, h, rng, needle=(54, 74, 46), bark=(92, 70, 52), fade=None):
    x, y, z = base
    nc = fade(needle, base) if fade else needle
    bc = fade(bark, base) if fade else bark
    prism(b, (x, y, z - 0.3), h * 0.05, h * 0.3, 5, bc, bc)
    tiers = 3 if h < 9 else 4
    for t in range(tiers):
        f = t / tiers
        r = h * (0.30 - 0.19 * f) * rng.uniform(0.9, 1.1)
        zz = z + h * (0.18 + 0.62 * f)
        cone(b, (x, y, zz), r, h * (0.42 - 0.1 * f), 7, jit(nc, rng, 0.07), rng, rot=rng.uniform(0, 6.3))


# ------------------------------------------------------------------------------------------- world sky
def sky(zenith, horizon, ground, sun_dir, sun_col, glow=0.0, glow_pow=24.0, disc=0.0, strength=1.0,
        haze_col=None, haze=0.0):
    w = bpy.data.worlds.new("Sky")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    N = nt.nodes
    L = nt.links
    bg = N["Background"]
    tc = N.new("ShaderNodeTexCoord")
    nrm = N.new("ShaderNodeVectorMath"); nrm.operation = "NORMALIZE"
    L.new(tc.outputs["Generated"], nrm.inputs[0])
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(nrm.outputs["Vector"], sep.inputs[0])
    mr = N.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -0.08
    mr.inputs["From Max"].default_value = 0.75
    L.new(sep.outputs["Z"], mr.inputs["Value"])
    ramp = N.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0; cr.elements[0].color = lin(ground)
    cr.elements[1].position = 1.0; cr.elements[1].color = lin(zenith)
    e = cr.elements.new(0.1); e.color = lin(horizon)
    if haze_col:
        e2 = cr.elements.new(0.3); e2.color = lin(mixc(horizon, zenith, 0.35))
    L.new(mr.outputs["Result"], ramp.inputs["Fac"])
    col_out = ramp.outputs["Color"]
    if glow > 0 or disc > 0:
        dot = N.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
        L.new(nrm.outputs["Vector"], dot.inputs[0])
        dot.inputs[1].default_value = Vector(sun_dir).normalized()
        clamp = N.new("ShaderNodeMath"); clamp.operation = "MAXIMUM"; clamp.inputs[1].default_value = 0.0
        L.new(dot.outputs["Value"], clamp.inputs[0])
        pw = N.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = glow_pow
        L.new(clamp.outputs["Value"], pw.inputs[0])
        pw2 = N.new("ShaderNodeMath"); pw2.operation = "POWER"; pw2.inputs[1].default_value = 2400.0
        L.new(clamp.outputs["Value"], pw2.inputs[0])
        m1 = N.new("ShaderNodeMath"); m1.operation = "MULTIPLY"; m1.inputs[1].default_value = glow
        L.new(pw.outputs["Value"], m1.inputs[0])
        m2 = N.new("ShaderNodeMath"); m2.operation = "MULTIPLY"; m2.inputs[1].default_value = disc
        L.new(pw2.outputs["Value"], m2.inputs[0])
        add = N.new("ShaderNodeMath"); add.operation = "ADD"
        L.new(m1.outputs["Value"], add.inputs[0]); L.new(m2.outputs["Value"], add.inputs[1])
        sc = N.new("ShaderNodeMix"); sc.data_type = "RGBA"; sc.blend_type = "ADD"
        L.new(add.outputs["Value"], sc.inputs["Factor"])
        L.new(col_out, sc.inputs["A"])
        sc.inputs["B"].default_value = lin(sun_col)
        col_out = sc.outputs["Result"]
    L.new(col_out, bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    return w


def sun(direction, col, strength, angle_deg=2.0):
    d = bpy.data.lights.new("Sun", "SUN")
    d.energy = strength
    d.color = lin(col)[:3]
    d.angle = math.radians(angle_deg)
    o = bpy.data.objects.new("Sun", d)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()
    return o


def sun_disc(cam_loc, direction, dist, radius, col, strength, halos=((12.0, 1.6), (4.0, 1.2))):
    """A faceted low-poly sun disc plus soft additive halo discs, all facing the camera (the glare)."""
    d = Vector(direction).normalized()
    c = Vector(cam_loc) + d * dist
    q = (-d).to_track_quat("Z", "Y")
    for k, (rs, a) in enumerate(((1.0, 1.0),) + tuple(halos)):
        r = radius * rs
        n = 12 if k == 0 else 24
        me = bpy.data.meshes.new("SunDisc%d" % k)
        me.from_pydata([(0, 0, 0)] + [(r * math.cos(i * 2 * math.pi / n), r * math.sin(i * 2 * math.pi / n), 0)
                                      for i in range(n)], [], [(0, i + 1, (i + 1) % n + 1) for i in range(n)])
        o = bpy.data.objects.new("SunDisc%d" % k, me)
        bpy.context.scene.collection.objects.link(o)
        o.location = c - d * k * 0.5
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = q
        m = bpy.data.materials.new("SunMat%d" % k)
        m.use_nodes = True
        nt = m.node_tree
        for nd in list(nt.nodes):
            if nd.type != "OUTPUT_MATERIAL":
                nt.nodes.remove(nd)
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = lin(col)
        em.inputs["Strength"].default_value = strength * a
        if k == 0:
            nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
        else:
            # soft radial falloff (no hard halo rings): strength * (1 - r/R)^3
            tc = nt.nodes.new("ShaderNodeTexCoord")
            mp = nt.nodes.new("ShaderNodeMapping")
            mp.inputs["Scale"].default_value = (1.0 / r, 1.0 / r, 1.0 / r)
            gr = nt.nodes.new("ShaderNodeTexGradient")
            gr.gradient_type = "SPHERICAL"
            pw = nt.nodes.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 2.2
            mu = nt.nodes.new("ShaderNodeMath"); mu.operation = "MULTIPLY"; mu.inputs[1].default_value = strength * a
            nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
            nt.links.new(mp.outputs["Vector"], gr.inputs["Vector"])
            nt.links.new(gr.outputs["Fac"], pw.inputs[0])
            nt.links.new(pw.outputs[0], mu.inputs[0])
            nt.links.new(mu.outputs[0], em.inputs["Strength"])
            tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            ad = nt.nodes.new("ShaderNodeAddShader")
            nt.links.new(em.outputs[0], ad.inputs[0])
            nt.links.new(tr.outputs[0], ad.inputs[1])
            nt.links.new(ad.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
        o.data.materials.append(m)
        o.visible_shadow = False
        o.visible_diffuse = False
        o.visible_glossy = False


def point(loc, col, watts, radius=1.0):
    d = bpy.data.lights.new("Pt", "POINT")
    d.energy = watts
    d.color = lin(col)[:3]
    d.shadow_soft_size = radius
    o = bpy.data.objects.new("Pt", d)
    o.location = loc
    bpy.context.scene.collection.objects.link(o)
    return o


def camera(loc, target, lens=35.0):
    c = bpy.data.cameras.new("Cam")
    c.lens = lens
    c.clip_end = 3000
    o = bpy.data.objects.new("Cam", c)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = o
    bpy.context.view_layer.update()
    return o


# ------------------------------------------------------------------------------------------- terrain
class Valley:
    def __init__(self, rng, ridge_r=120.0, ridge_h=70.0, lake=(-40.0, 70.0, 28.0), arena_r=30.0):
        self.off = Vector((rng.uniform(-500, 500), rng.uniform(-500, 500), rng.uniform(-500, 500)))
        self.ridge_r, self.ridge_h, self.lake, self.arena_r = ridge_r, ridge_h, lake, arena_r

    def h(self, x, y):
        r = math.hypot(x, y)
        t = max(0.0, min(1.0, (r - self.ridge_r * 0.45) / (self.ridge_r * 0.75)))
        t = t * t * (3 - 2 * t)
        n1 = noise.noise((Vector((x, y, 0)) * 0.012) + self.off)
        n2 = noise.noise((Vector((x, y, 0)) * 0.04) + self.off * 1.3)
        z = t * self.ridge_h * (0.75 + 0.6 * n1) + n2 * 1.6 * (0.3 + t * 4)
        lx, ly, lr = self.lake
        dl = math.hypot(x - lx, y - ly)
        if dl < lr * 1.6:
            z -= 4.0 * max(0.0, 1 - (dl / (lr * 1.6)) ** 2)
        if r < self.arena_r:
            z = z * (r / self.arena_r) ** 2
        return z

    def build(self, size, n, fade, cols, snow_line=60.0, name="Terrain", center=(0, 0)):
        b = Batch()
        cx, cy = center
        step = size / n
        P = [[Vector((cx - size / 2 + i * step, cy - size / 2 + j * step, 0)) for j in range(n + 1)] for i in range(n + 1)]
        for i in range(n + 1):
            for j in range(n + 1):
                p = P[i][j]
                p.x += noise.noise(p * 0.3 + self.off) * step * 0.3
                p.y += noise.noise(p * 0.3 - self.off) * step * 0.3
                p.z = self.h(p.x, p.y)
        rng = random.Random(SEED + 7)
        for i in range(n):
            for j in range(n):
                q = (P[i][j], P[i + 1][j], P[i + 1][j + 1], P[i][j + 1])
                tris = [(q[0], q[1], q[2]), (q[0], q[2], q[3])] if (i + j) % 2 else [(q[0], q[1], q[3]), (q[1], q[2], q[3])]
                for t in tris:
                    nn = (t[1] - t[0]).cross(t[2] - t[0]).normalized()
                    cz = (t[0].z + t[1].z + t[2].z) / 3
                    cen = (t[0] + t[1] + t[2]) / 3
                    slope = 1 - abs(nn.z)
                    if cz > snow_line + noise.noise(cen * 0.05) * 8 and slope < 0.55:
                        c = cols["snow"]
                    elif slope > 0.33 or cz > snow_line * 0.75:
                        c = mixc(cols["rock"], cols["rock2"], rng.random())
                    elif cz < -1.2:
                        c = cols["shore"]
                    else:
                        c = mixc(cols["grass"], cols["grass2"], 0.5 + 0.5 * noise.noise(cen * 0.06 + self.off))
                    light = 0.85 + 0.2 * max(0.0, nn.dot(cols["key"]))
                    c = tuple(v * light for v in jit(c, rng, 0.05))
                    b.face(list(t), fade(c, cen))
        return b.emit(name)


def make_fade(cam_loc, fog_col, start, end, power=1.0):
    cl = Vector(cam_loc)

    def f(c, p):
        d = (Vector(p) - cl).length
        t = max(0.0, min(1.0, (d - start) / (end - start))) ** power
        return mixc(c, fog_col, t * 0.85)
    return f


def water(z, size, col, center=(0, 0)):
    me = bpy.data.meshes.new("Water")
    s = size / 2
    cx, cy = center
    me.from_pydata([(cx - s, cy - s, z), (cx + s, cy - s, z), (cx + s, cy + s, z), (cx - s, cy + s, z)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new("Water", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(plain_mat("Water", col, rough=0.12))
    return o


# ------------------------------------------------------------------------------------------- text "48"
def text48(cam, dist, y_off, size, face_top, face_bot, side_col, emit=0.25, extrude=0.12, x_off=0.0, body="48",
           rim=None):
    fp = font_path()
    cu = bpy.data.curves.new("T48", "FONT")
    cu.body = body
    if fp:
        cu.font = bpy.data.fonts.load(fp)
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = size
    cu.extrude = extrude * size
    cu.bevel_depth = 0.035 * size
    cu.bevel_resolution = 0
    cu.resolution_u = 3
    cu.space_character = 1.04
    ob = bpy.data.objects.new("T48c", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    zs = [v.co.y for v in me.vertices]
    y0, y1 = min(zs), max(zs)
    cols = []
    for p in me.polygons:
        t = (p.center.y - y0) / max(1e-6, (y1 - y0))
        front = mixc(face_bot, face_top, t)
        if p.normal.z > 0.9:
            c = front
        elif p.normal.z > 0.2:  # front chamfer: lit edge
            c = mixc(front, rim or INK, 0.35) if p.normal.y > 0 else tuple(v * 0.8 for v in front)
        else:
            c = tuple(v * (0.6 + 0.25 * max(0, p.normal.y)) for v in side_col)
        cols.append(c)
    set_face_cols(me, cols)
    o = bpy.data.objects.new("T48", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(facecol_mat("TextCol", rough=0.7, emit=emit))
    o.parent = cam
    o.location = (x_off, y_off, -dist)
    return o


# ------------------------------------------------------------------------------------------- the Horn
def horn(b_metal, base, scale, rng, yaw=0.0):
    """Original faceted Horn: a curved, tapering octagonal shell lying on its side, open mouth toward +Y (then yaw)."""
    sub = Batch()
    _horn(sub, (0, 0, 0), scale, rng)
    cy, sy = math.cos(yaw), math.sin(yaw)
    bx, by, bz = base
    for f, c in zip(sub.f, sub.c):
        b_metal.face([Vector((sub.v[i].x * cy - sub.v[i].y * sy + bx, sub.v[i].x * sy + sub.v[i].y * cy + by,
                              sub.v[i].z + bz)) for i in f], c)


def _horn(b_metal, base, scale, rng):
    x0, y0, z0 = base
    rings = []
    segs, sides = 9, 8
    for k in range(segs + 1):
        t = k / segs
        # spine: rises and curls back from the mouth (t=0) to the tip (t=1)
        ang = t * 2.1
        R = 1.0 * scale
        sx = 0.0
        sy = -math.sin(ang) * R * 1.25
        sz = (1 - math.cos(ang)) * R * 0.75 + 0.55 * scale * (1 - t)
        rad = scale * (0.62 * (1 - t) ** 1.15 + 0.05)
        tang = Vector((0, -math.cos(ang) * 1.25, math.sin(ang) * 0.75)).normalized()
        side = Vector((1, 0, 0))
        up = side.cross(tang).normalized()
        ring = []
        for i in range(sides):
            a = i * 2 * math.pi / sides + math.pi / sides
            ring.append(Vector((x0 + sx, y0 + sy, z0 + sz)) + (side * math.cos(a) + up * math.sin(a)) * rad)
        rings.append(ring)
    bronze = (214, 162, 84)
    for k in range(segs):
        for i in range(sides):
            j = (i + 1) % sides
            q = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
            n = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
            k2 = 0.8 + 0.2 * rng.random()
            b_metal.face(q, tuple(v * k2 for v in bronze))
    # inner mouth (dark)
    inner = [rings[0][i] + (rings[1][i] - rings[0][i]) * 0.0 for i in range(sides)]
    cen = sum(inner, Vector()) / sides
    for i in range(sides):
        j = (i + 1) % sides
        b_metal.face([inner[j], inner[i], cen + Vector((0, -0.6 * scale, 0.05 * scale))], (40, 30, 22))


# ------------------------------------------------------------------------------------------- option A
def option_a(out):
    sc = reset()
    rng = random.Random(SEED + 1)
    cam_loc = Vector((24.0, 44.0, 19.0))
    tgt = Vector((-2.0, -6.0, 9.0))
    cam = camera(cam_loc, tgt, lens=34)
    sun_dir = Vector((-1.0, -0.55, 0.14)).normalized()
    sky((52, 78, 124), (246, 170, 98), (90, 80, 76), sun_dir, (255, 200, 130), glow=1.6, glow_pow=9, disc=6.0,
        strength=1.2)
    sun(sun_dir, (255, 196, 140), 4.0, 3.0)
    fade = make_fade(cam_loc, (196, 150, 128), 90, 520, 1.0)
    val = Valley(rng, ridge_r=240, ridge_h=95, lake=(-70.0, -50.0, 34.0), arena_r=34)
    cols = dict(grass=(78, 112, 52), grass2=(100, 122, 56), rock=(124, 114, 104), rock2=(104, 98, 92),
                snow=(232, 226, 222), shore=(124, 114, 88), key=-sun_dir)
    val.build(1100, 150, fade, cols, snow_line=78)
    water(-1.6, 900, (40, 66, 80))
    # trees: a forest belt between the plinth ring and the mountains
    tb = Batch()
    for _ in range(1500):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(42, 300)
        x, y = r * math.cos(a), r * math.sin(a)
        z = val.h(x, y)
        if z < -0.4 or z > 60:
            continue
        if (x - cam_loc.x * 0.6) ** 2 + (y - cam_loc.y * 0.6) ** 2 < 32 ** 2:  # keep the near view clear
            continue
        pine(tb, (x, y, z), rng.uniform(8, 14), rng, fade=fade)
    tb.emit("Pines")
    # dais + plinth ring + Horn
    db = Batch()
    prism(db, (0, 0, -0.6), 14.0, 1.4, 24, (150, 146, 138), (166, 160, 150), shade=True)
    prism(db, (0, 0, 0.8), 9.0, 0.6, 24, (140, 136, 128), (156, 150, 140))
    n_pl = 24
    for i in range(n_pl):
        a = i * 2 * math.pi / n_pl
        x, y = 22 * math.cos(a), 22 * math.sin(a)
        prism(db, (x, y, val.h(x, y) - 0.6), 1.15, 1.7, 8, (118, 122, 128), (150, 154, 160), rot=a)
    db.emit("Dais", mat=facecol_mat("Stone", rough=0.8))
    hb = Batch()
    horn(hb, (2.5, -0.5, 1.4), 8.0, rng, yaw=math.radians(-125))
    hb.emit("Horn", mat=facecol_mat("Bronze", rough=0.5, metal=0.55))
    point((6, 12, 5), AMBER, 1500, 2.0)
    # "48"
    text48(cam, 10.4, 3.43, 3.0, (16, 12, 10), (16, 12, 10), (10, 8, 6), emit=0.0, x_off=0.1)  # drop shadow
    text48(cam, 10, 3.55, 3.0, (196, 92, 42), (112, 136, 58), (40, 30, 24), emit=0.9, rim=INK)
    return render(sc, out, "a")


# ------------------------------------------------------------------------------------------- option B
def contender(b, base, s, col):
    """Blocky player-scale figure (Roblox-like proportions, faceted), arms slightly out, rising."""
    x, y, z = base
    def box(cx, cy, cz, w, d, h, c):
        x0, x1, y0, y1, z0, z1 = cx - w / 2, cx + w / 2, cy - d / 2, cy + d / 2, cz, cz + h
        V = [Vector(p) for p in [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]]
        for f, k in [((0, 1, 5, 4), 0.9), ((1, 2, 6, 5), 0.8), ((2, 3, 7, 6), 0.7), ((3, 0, 4, 7), 0.85),
                     ((4, 5, 6, 7), 1.0), ((3, 2, 1, 0), 0.5)]:
            b.face([V[i] for i in f], tuple(v * k for v in c))
    box(x - 0.5 * s, y, z, 0.9 * s, 0.9 * s, 2.0 * s, col)          # legs
    box(x + 0.5 * s, y, z, 0.9 * s, 0.9 * s, 2.0 * s, col)
    box(x, y, z + 2.0 * s, 2.0 * s, 1.0 * s, 2.0 * s, col)          # torso
    # arms angled slightly out
    for sgn in (-1, 1):
        cx = x + sgn * 1.45 * s
        V0 = Vector((cx, y, z + 4.0 * s))
        d = Vector((sgn * 0.35, 0, -1)).normalized() * 2.0 * s
        w = 0.45 * s
        side = Vector((1, 0, sgn * 0.35)).normalized() * w
        fw = Vector((0, w, 0))
        P = [V0 - side - fw, V0 + side - fw, V0 + side + fw, V0 - side + fw]
        Q = [p + d for p in P]
        for i in range(4):
            j = (i + 1) % 4
            b.face([P[i], P[j], Q[j], Q[i]], tuple(v * (0.7 + 0.08 * i) for v in col))
        b.face(list(reversed(Q)), col)
    # head: faceted octagonal block with chamfers
    prism(b, (x, y, z + 4.1 * s), 0.72 * s, 0.25 * s, 8, col, col, rot=math.pi / 8, taper=1.18, top=False)
    prism(b, (x, y, z + 4.35 * s), 0.85 * s, 0.75 * s, 8, col, col, rot=math.pi / 8, taper=1.0, top=False)
    prism(b, (x, y, z + 5.1 * s), 0.85 * s, 0.25 * s, 8, col, col, rot=math.pi / 8, taper=0.78, top=True)


def option_b(out):
    sc = reset()
    rng = random.Random(SEED + 2)
    cam_loc = Vector((0.0, 13.0, 0.6))
    tgt = Vector((0.0, 0.0, 6.2))
    cam = camera(cam_loc, tgt, lens=28)
    sun_dir = Vector((-1.3, -13.0, 7.2)).normalized()
    sky((62, 98, 150), (250, 192, 116), (80, 80, 70), sun_dir, (255, 220, 160), strength=1.0)
    sun_disc(cam_loc, sun_dir, 400, 4.6, (255, 238, 200), 30.0)
    sun(sun_dir, (255, 210, 150), 4.0, 2.0)
    fade = make_fade(cam_loc, (206, 172, 132), 30, 260, 0.75)
    val = Valley(rng, ridge_r=140, ridge_h=80, lake=(-200.0, 0.0, 10.0), arena_r=40)
    cols = dict(grass=(74, 108, 50), grass2=(96, 118, 54), rock=(120, 112, 102), rock2=(100, 96, 90),
                snow=(230, 224, 218), shore=(120, 110, 84), key=-sun_dir)
    val.build(600, 100, fade, cols, snow_line=66)
    # pine walls left and right, darker near camera
    tb = Batch()
    for _ in range(900):
        x = rng.uniform(-140, 140)
        y = rng.uniform(-200, -2)
        if abs(x) < 7 + max(0.0, -y) * 0.45:
            continue
        z = val.h(x, y)
        pine(tb, (x, y, z), rng.uniform(9, 16), rng, needle=(46, 66, 42), fade=fade)
    tb.emit("Pines")
    # launch plinth: octagonal metal column with ring lip, rising out of a pit
    pb = Batch()
    steel = (120, 126, 132)
    prism(pb, (0, 0, -2.0), 2.3, 4.0, 8, (96, 100, 104), (120, 124, 128), rot=math.pi / 8)
    prism(pb, (0, 0, 2.0), 2.7, 0.4, 8, steel, (150, 154, 160), rot=math.pi / 8)
    prism(pb, (0, 0, -0.4), 4.6, 0.5, 16, (128, 122, 112), (140, 134, 124))
    pb.emit("Plinth", mat=facecol_mat("Steel", rough=0.5, metal=0.6))
    cb = Batch()
    contender(cb, (0, 0, 2.4), 1.0, (66, 62, 64))
    cb.emit("Contender", mat=facecol_mat("Suit", rough=0.85))
    # light seam on the plinth lip (amber, restrained)
    ring = Batch()
    prism(ring, (0, 0, 2.32), 2.72, 0.08, 8, AMBER, AMBER, rot=math.pi / 8, top=False, shade=False)
    ring.emit("Seam", mat=facecol_mat("SeamGlow", rough=0.6, emit=3.0))
    point((0, 9.0, 2.0), (150, 170, 210), 700, 3.0)   # cool front fill so the figure is not a black hole
    point((0, 1.5, 2.6), AMBER, 120, 0.6)            # plinth bounce
    text48(cam, 10.4, 3.98, 3.4, (16, 12, 10), (16, 12, 10), (10, 8, 6), emit=0.0, x_off=-3.48)
    text48(cam, 10, 4.1, 3.4, (196, 92, 42), (112, 136, 58), (40, 30, 24), emit=0.9, rim=INK, x_off=-3.4)
    return render(sc, out, "b")


# ------------------------------------------------------------------------------------------- option C
def hex_wall(b, rng, center_y=-14.0, radius=60.0, rows=9, cell=2.6, col=(70, 150, 230)):
    """Curved wall of hexagon panels (the closing border), panels emissive blue with darker gaps."""
    h = cell * math.sqrt(3) / 2
    span = 34
    for r in range(rows):
        for q in range(-span, span + 1):
            cx = q * cell * 1.5
            cz = r * 2 * h + (h if q % 2 else 0) - 4
            ang = cx / radius
            if abs(ang) > 1.3:
                continue
            pts = []
            for i in range(6):
                a = i * math.pi / 3
                lx = cx + math.cos(a) * cell * 0.9
                lz = cz + math.sin(a) * cell * 0.9
                aa = lx / radius
                pts.append(Vector((math.sin(aa) * radius, center_y + radius - math.cos(aa) * radius - radius, lz)))
            k = rng.uniform(0.35, 1.0) * (1.0 - 0.06 * r)
            b.face(pts[::-1], tuple(v * k for v in col))


def option_c(out):
    sc = reset()
    rng = random.Random(SEED + 3)
    cam_loc = Vector((0.0, 14.0, 3.0))
    tgt = Vector((0.0, 0.0, 3.4))
    cam = camera(cam_loc, tgt, lens=32)
    sky((10, 16, 30), (24, 40, 62), (10, 12, 14), Vector((0, -1, 0.2)), (60, 110, 170), glow=0.6, glow_pow=4,
        strength=0.6)
    moon = sun(Vector((0.4, 0.6, 0.7)), (150, 170, 210), 0.35, 4.0)
    fade = make_fade(cam_loc, (18, 34, 54), 20, 120, 1.0)
    # ground
    val = Valley(rng, ridge_r=200, ridge_h=40, lake=(-400.0, 0.0, 5.0), arena_r=60)
    cols = dict(grass=(40, 58, 36), grass2=(50, 64, 38), rock=(70, 70, 72), rock2=(60, 62, 66),
                snow=(180, 186, 196), shore=(60, 56, 46), key=Vector((0.4, 0.6, 0.7)))
    val.build(300, 70, fade, cols, snow_line=90)
    # hex border wall behind
    hb = Batch()
    hex_wall(hb, rng, center_y=-16.0, radius=50.0)
    hb.emit("HexWall", mat=facecol_mat("HexGlow", rough=0.6, emit=1.3))
    # silhouetted pines between the wall and the letters
    tb = Batch()
    for _ in range(140):
        x = rng.uniform(-40, 40)
        y = rng.uniform(-13, -4)
        pine(tb, (x, y, val.h(x, y)), rng.uniform(4.5, 9.5), rng, needle=(20, 30, 26), bark=(26, 22, 20))
    tb.emit("Pines")
    # amber glow from below the letters (a fire-light read, not a neon one)
    point((0, 7.5, 2.2), AMBER, 700, 3.5)            # warm key from below-front
    point((-4.0, 4.0, 6.0), AMBER, 150, 1.0)
    # big "48" on a low faceted stone plinth
    sb = Batch()
    prism(sb, (0, -1.0, -0.5), 4.2, 0.9, 7, (88, 84, 78), (104, 98, 90), rot=0.13)
    sb.emit("Base", mat=facecol_mat("Stone2", rough=0.85))
    text48(cam, 7.2, 0.15, 4.3, (200, 96, 44), (104, 132, 56), (72, 48, 30), emit=0.75, extrude=0.22, rim=AMBER)
    return render(sc, out, "c")


# ------------------------------------------------------------------------------------------- render
def render(sc, out, tag):
    os.makedirs(out, exist_ok=True)
    p = os.path.join(out, "arena48_icon_%s.png" % tag)
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(p)
    img.scale(150, 150)
    p2 = os.path.join(out, "arena48_icon_%s_150.png" % tag)
    img.filepath_raw = p2
    img.file_format = "PNG"
    img.save()
    print("WROTE", p, p2, flush=True)
    return p


def main():
    out, opts = argv()
    print("font:", font_path(), flush=True)
    for o in opts:
        {"a": option_a, "b": option_b, "c": option_c}[o](out)


main()
