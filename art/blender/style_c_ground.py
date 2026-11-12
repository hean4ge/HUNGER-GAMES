"""
style_c_ground.py - Variant C terrain MaterialVariant tiles (Blender 5.3, Cycles).

  StyleC_PebblePath   10 studs per tile: packed earth with softly rounded pebbles and cobbles (+ a little grit)
  StyleC_ForestFloor  12 studs per tile: painted leaf litter (oak / beech / birch leaves in three layers), spruce
                      needle clumps, twigs, cones, two moss cushions and a few stones on dark humus

How: every element is modelled as real geometry on a periodic soil mesh (elements crossing the tile edge are
copied at +-T, so the tile wraps exactly), rendered straight down with an orthographic camera as emission data
passes (albedo, world normal, AO, leaf coordinates, aux), then painted in numpy: soft top-light and contact AO,
midribs and veins on leaves, broad periodic colour drift only - no photo grain. Output 1024 px PNGs:
<Name>_Color (sRGB), <Name>_Normal (OpenGL, tangent space U = +X, V = +Y), <Name>_Rough (8-bit gray).
"""
import math
import os
import time

import bpy
import numpy as np

import style_c_lib as L
import tex_ground as tg

TAU = 2.0 * math.pi
RES = 1024


def log(*a):
    print(*a, flush=True)


# =============================================================================================== geometry accumulator
class Acc:
    def __init__(self):
        self.V, self.F, self.col, self.aux, self.luv = [], [], [], [], []
        self.n = 0

    def add(self, verts, faces, col, aux, luv=None):
        verts = np.asarray(verts, float)
        k = len(verts)
        self.V.append(verts)
        self.F += [tuple(int(i) + self.n for i in f) for f in faces]
        c = np.asarray(col, float)
        self.col.append(np.tile(c, (k, 1)) if c.ndim == 1 else c)
        a = np.asarray(aux, float)
        self.aux.append(np.tile(a, (k, 1)) if a.ndim == 1 else a)
        if luv is None:
            luv = np.zeros((k, 3))
        self.luv.append(np.asarray(luv, float))
        self.n += k

    def build(self, name):
        V = np.concatenate(self.V)
        me = bpy.data.meshes.new(name)
        me.from_pydata(V.tolist(), [], self.F)
        me.update()
        for an, arr in (("col", self.col), ("aux", self.aux), ("luv", self.luv)):
            a = np.concatenate(arr)
            a4 = np.concatenate([a, np.ones((len(a), 1))], 1).astype(np.float32)
            at = me.color_attributes.new(an, "FLOAT_COLOR", "POINT")
            at.data.foreach_set("color", a4.ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def wrap_offsets(x, y, r, T, margin=0.05):
    offs = []
    for dx in (-T, 0.0, T):
        for dy in (-T, 0.0, T):
            if (x + dx + r > -margin and x + dx - r < T + margin and y + dy + r > -margin
                    and y + dy - r < T + margin):
                offs.append((dx, dy))
    return offs


def periodic_height(T, terms, rng):
    waves = []
    for (k, amp) in terms:
        for _ in range(3):
            kx, ky = rng.randint(-k, k + 1), rng.randint(-k, k + 1)
            if kx == 0 and ky == 0:
                continue
            waves.append((kx, ky, amp * rng.uniform(0.5, 1.0), rng.uniform(0, TAU)))

    def h(x, y):
        z = np.zeros_like(np.asarray(x, float))
        for kx, ky, a, ph in waves:
            z = z + a * np.cos(TAU * (kx * x + ky * y) / T + ph)
        return z
    return h


def soil_mesh(acc, T, hfun, col, rough, n=200):
    xs = np.linspace(-0.06 * T, 1.06 * T, n)
    X, Y = np.meshgrid(xs, xs)
    Z = hfun(X, Y)
    V = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    i = np.arange(n - 1)
    a = (i[None, :] + i[:, None] * n).ravel()
    F = np.stack([a, a + 1, a + n + 1, a + n], 1)
    acc.add(V, F.tolist(), col, (rough, 0.0, 0.5))


def ellipsoid_mesh(a, b, c, seg=20, rings=10, bumps=None, rng=None):
    th = np.linspace(0, math.pi, rings + 1)[1:-1]
    ph = np.linspace(0, TAU, seg, endpoint=False)
    TH, PH = np.meshgrid(th, ph, indexing="ij")
    d = np.ones_like(TH)
    if bumps:
        for (amp, m, n_, p1, p2) in bumps:
            d += amp * np.sin(m * TH + p1) * np.cos(n_ * PH + p2)
    x = a * np.sin(TH) * np.cos(PH) * d
    y = b * np.sin(TH) * np.sin(PH) * d
    z = c * np.cos(TH) * d
    V = np.concatenate([[[0, 0, c]], np.stack([x.ravel(), y.ravel(), z.ravel()], 1), [[0, 0, -c]]])
    F = []
    nr = len(th)
    for j in range(seg):
        j2 = (j + 1) % seg
        F.append((0, 1 + j, 1 + j2))
    for r in range(nr - 1):
        for j in range(seg):
            j2 = (j + 1) % seg
            a0 = 1 + r * seg + j
            a1 = 1 + r * seg + j2
            F.append((a0, a0 + seg, a1 + seg, a1))
    last = 1 + nr * seg
    for j in range(seg):
        j2 = (j + 1) % seg
        F.append((1 + (nr - 1) * seg + j2, 1 + (nr - 1) * seg + j, last))
    return V, F


def rotz(V, ang):
    c, s = math.cos(ang), math.sin(ang)
    R = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    return V @ R.T


def rotx(V, ang):
    c, s = math.cos(ang), math.sin(ang)
    R = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    return V @ R.T


def roty(V, ang):
    c, s = math.cos(ang), math.sin(ang)
    R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return V @ R.T


def poisson(rng, T, radii, gap, tries=60):
    pts = []
    for r in radii:
        for _ in range(tries):
            x, y = rng.uniform(0, T, 2)
            ok = True
            for (px, py, pr) in pts:
                dx = abs(x - px)
                dy = abs(y - py)
                dx = min(dx, T - dx)
                dy = min(dy, T - dy)
                if dx * dx + dy * dy < (r + pr + gap) ** 2:
                    ok = False
                    break
            if ok:
                pts.append((x, y, r))
                break
    return pts


# =============================================================================================== render passes
def data_material():
    m = bpy.data.materials.new("GD_Data")
    m.use_nodes = True
    nt = L.NT(m)
    nt.nodes.clear()
    geo = nt.n("ShaderNodeNewGeometry")
    out = nt.n("ShaderNodeOutputMaterial")
    emit = nt.n("ShaderNodeEmission")
    nt.link(emit.outputs[0], out.inputs["Surface"])
    attrs = {}
    for an in ("col", "aux", "luv"):
        a = nt.n("ShaderNodeAttribute")
        a.attribute_name = an
        attrs[an] = a.outputs["Color"]
    nrm = nt.vmath("MULTIPLY_ADD", geo.outputs["Normal"], (0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
    ao_nodes = {}
    for key, dist in (("ao1", 0.12), ("ao2", 0.45)):
        ao = nt.n("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = dist
        ao_nodes[key] = ao
    sep = nt.n("ShaderNodeSeparateXYZ")
    nt.link(geo.outputs["Position"], sep.inputs[0])
    socks = {"col": attrs["col"], "aux": attrs["aux"], "luv": attrs["luv"], "nrm": nrm,
             "ao": nt.combine(ao_nodes["ao1"].outputs["AO"], ao_nodes["ao2"].outputs["AO"], sep.outputs[2])}
    return m, emit, socks, ao_nodes


def render_passes(T, tmp, name, ao_dist=(0.12, 0.45), samples=24):
    scene = bpy.context.scene
    tg.data_render_settings(scene, RES, RES, samples=samples)
    scene.cycles.filter_width = 1.2
    tg.ortho_camera(scene, 0.0, 0.0, T, T, z=40.0)
    m, emit, socks, ao_nodes = data_material()
    ao_nodes["ao1"].inputs["Distance"].default_value = ao_dist[0]
    ao_nodes["ao2"].inputs["Distance"].default_value = ao_dist[1]
    for o in scene.objects:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(m)
    nt = m.node_tree
    out = {}
    for key in ("col", "aux", "luv", "nrm", "ao"):
        for l in list(emit.inputs["Color"].links):
            nt.links.remove(l)
        nt.links.new(socks[key], emit.inputs["Color"])
        scene.cycles.samples = 96 if key == "ao" else samples
        t = time.time()
        out[key] = tg.render_exr(scene, os.path.join(tmp, "%s_%s.exr" % (name, key)))[..., :3].astype(np.float64)
        log("GROUND %s pass %-3s %4.1fs" % (name, key, time.time() - t))
    return out


def finish(name, T, col_srgb, nrm_world, rough, tex_dir, rel, notes, base, rgb):
    n = nrm_world.copy()
    n[..., :2] *= 0.9
    n[..., 2] = np.maximum(n[..., 2], 0.15)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    files = {"colorMap": "%s_Color.png" % name, "normalMap": "%s_Normal.png" % name,
             "roughnessMap": "%s_Rough.png" % name}
    tg.write_png(os.path.join(tex_dir, files["colorMap"]), np.clip(col_srgb, 0, 1))
    tg.write_png(os.path.join(tex_dir, files["normalMap"]), n * 0.5 + 0.5)
    tg.write_png(os.path.join(tex_dir, files["roughnessMap"]), np.clip(rough, 0, 1))
    mean = tuple(int(round(v * 255)) for v in col_srgb.reshape(-1, 3).mean(0))
    log("GROUND %s written: mean sRGB %s, roughness %.2f" % (name, mean, rough.mean()))
    return {"name": name, "key": name.replace("StyleC_", ""), "colorMap": rel + files["colorMap"],
            "normalMap": rel + files["normalMap"], "roughnessMap": rel + files["roughnessMap"],
            "studsPerTile": T, "pxPerStud": round(RES / T, 1), "materialPattern": "Organic",
            "baseMaterial": base, "terrainColor": list(rgb), "meanAlbedo": list(mean),
            "normalConvention": "OpenGL (+Y up), tangent space, U = world +X, V = world +Y (top-down tile)",
            "notes": notes}


# =============================================================================================== pebble path
PEBBLE_PAL = [((140, 134, 124), 0.3), ((150, 140, 120), 0.2), ((120, 122, 120), 0.2), ((100, 98, 96), 0.12),
              ((138, 116, 94), 0.08), ((160, 154, 144), 0.05), ((128, 114, 100), 0.05)]
PEBBLE_PAL_BIG = [((136, 130, 122), 0.4), ((146, 136, 118), 0.3), ((120, 120, 116), 0.3)]


def pick(rng, pal):
    w = np.array([p[1] for p in pal])
    i = rng.choice(len(pal), p=w / w.sum())
    return np.array(pal[i][0], float)


def build_pebble_path(tex_dir, rel, tmp):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    T = 10.0
    rng = np.random.RandomState(404)
    acc = Acc()
    hfun = periodic_height(T, [(1, 0.05), (2, 0.03), (4, 0.012)], rng)
    soil_mesh(acc, T, hfun, np.array([104, 92, 76]) / 255.0, 0.93)
    radii = sorted(list(rng.uniform(0.42, 0.6, 10)) + list(rng.uniform(0.25, 0.4, 95)) +
                   list(rng.uniform(0.13, 0.23, 170)), reverse=True)
    pts = poisson(rng, T, radii, 0.03)
    grit = poisson(rng, T, list(rng.uniform(0.05, 0.085, 260)), 0.02, tries=20)
    count = 0
    for (x, y, r) in pts + grit:
        small = r < 0.1
        a, b = r * rng.uniform(1.0, 1.3), r * rng.uniform(0.78, 1.0)
        c = r * rng.uniform(0.5, 0.68)
        bumps = [(0.06, 2, 1, rng.uniform(0, 6), rng.uniform(0, 6)), (0.04, 3, 2, rng.uniform(0, 6),
                                                                      rng.uniform(0, 6))]
        V, F = ellipsoid_mesh(a, b, c, 10 if small else 22, 6 if small else 11, bumps)
        V = rotx(V, rng.uniform(-0.12, 0.12))
        V = rotz(V, rng.uniform(0, TAU))
        zc = float(hfun(np.array(x), np.array(y))) + c * rng.uniform(-0.25, 0.1)
        colr = pick(rng, PEBBLE_PAL_BIG if r > 0.36 else PEBBLE_PAL) / 255.0 * rng.uniform(0.86, 0.97)
        rough = rng.uniform(0.7, 0.82)
        for (dx, dy) in wrap_offsets(x, y, max(a, b), T):
            acc.add(V + np.array([x + dx, y + dy, zc]), F, colr, (rough, 0.25, rng.rand()))
            count += 1
    acc.build("GD_PebblePath")
    log("GROUND PebblePath: %d pebbles (+ wrapped copies = %d)" % (len(pts) + len(grit), count))
    P = render_passes(T, tmp, "PebblePath", ao_dist=(0.18, 0.6))
    col = P["col"]
    nrm = P["nrm"] * 2.0 - 1.0
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
    aux = P["aux"]
    ao1 = np.clip(P["ao"][..., 0], 0, 1)
    ao2 = np.clip(P["ao"][..., 1], 0, 1)
    peb = np.clip((aux[..., 1] - 0.0) / 0.25, 0, 1)
    nprng = np.random.RandomState(7)
    low = L.periodic_noise(nprng, RES, RES, 1, 4)
    mid = L.periodic_noise(nprng, RES, RES, 6, 16)
    srgb = col.copy()
    soilv = 1.0 + 0.07 * low + 0.03 * mid
    srgb = srgb * (1 - peb[..., None]) * soilv[..., None] + srgb * peb[..., None]
    damp = L.ss(0.4, 1.2, low)
    srgb = L.mixc(srgb, srgb * np.array([0.86, 0.84, 0.82]), damp * (1 - peb) * 0.6)
    top = L.ss(0.35, 1.0, nrm[..., 2])
    srgb *= (1.0 + peb * (0.14 * top - 0.06))[..., None]
    lin = L.srgb2lin(np.clip(srgb, 0, 1))
    lin *= ((0.56 + 0.44 * ao1 ** 1.1) * (0.76 + 0.24 * ao2))[..., None]
    out = L.lin2srgb(lin)
    rough = np.clip(aux[..., 0] + 0.04 * (1 - ao1), 0, 1)
    return finish("StyleC_PebblePath", T, out, nrm, rough, tex_dir, rel,
                  "Packed earth path with softly rounded pebbles and cobbles (modelled ellipsoids, 0.13-0.6 stud "
                  "radius) and a little grit; no photo grain. %.0fs" % (time.time() - t0), "Ground", (180, 172, 160))


# =============================================================================================== forest floor
LEAF_TOP = [((160, 124, 70), 0.25), ((140, 88, 52), 0.15), ((146, 134, 80), 0.12), ((134, 102, 64), 0.25),
            ((112, 112, 66), 0.08), ((122, 76, 48), 0.15)]
LEAF_MID = [((126, 96, 64), 0.3), ((112, 82, 56), 0.25), ((136, 104, 66), 0.2), ((102, 76, 52), 0.15),
            ((120, 74, 48), 0.1)]
LEAF_LOW = [((80, 62, 46), 0.4), ((70, 56, 44), 0.3), ((90, 70, 50), 0.3)]


def leaf_outline(kind, t, rng):
    s = np.sin(np.pi * np.clip(t, 0, 1))
    if kind == "oak":
        env = s ** 0.7 * (0.55 + 0.45 * t)
        lobes = 1.0 + 0.34 * np.sin(TAU * 4.5 * t + 0.4)
        return 0.34 * env * np.maximum(lobes, 0.45)
    if kind == "beech":
        return 0.3 * s ** 0.62 * (1.0 - 0.18 * t)
    serr = 1.0 + 0.07 * np.abs(np.sin(TAU * 9.0 * t))
    return 0.34 * s ** 0.68 * (1.12 - 0.35 * t) * serr


def leaf_mesh(kind, Lng, rng, n=16):
    t = np.linspace(0.0, 1.0, n)
    w = leaf_outline(kind, t, rng) * Lng
    w[0] = 0.012 * Lng
    w[-1] = 0.004 * Lng
    cup = rng.uniform(0.0, 0.35)
    arch = rng.uniform(-0.04, 0.06)
    V, luv = [], []
    for i, ti in enumerate(t):
        x = (ti - 0.5) * Lng
        for side in (-1.0, 0.0, 1.0):
            y = side * w[i]
            z = cup * (side ** 2) * w[i] * 0.6 + arch * Lng * math.sin(math.pi * ti)
            V.append((x, y, z))
            luv.append((ti, abs(side), 1.0))
    F = []
    for i in range(n - 1):
        for j in range(2):
            a = i * 3 + j
            F.append((a, a + 3, a + 4, a + 1))
    # petiole
    base = len(V)
    for (x, wy) in ((-0.5 * Lng - 0.13 * Lng, 0.012 * Lng), (-0.5 * Lng, 0.012 * Lng)):
        V.append((x, -wy, 0.0))
        V.append((x, wy, 0.0))
        luv.append((0.0, 0.0, 0.0))
        luv.append((0.0, 0.0, 0.0))
    F.append((base, base + 2, base + 3, base + 1))
    return np.array(V), F, np.array(luv)


def tube(points, radius, seg=6):
    pts = np.asarray(points, float)
    V, F = [], []
    for i, p in enumerate(pts):
        d = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        d /= np.linalg.norm(d)
        up = np.array([0, 0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0, 0])
        e1 = np.cross(d, up)
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(d, e1)
        r = radius * (1.0 - 0.35 * i / max(len(pts) - 1, 1))
        for k in range(seg):
            a = TAU * k / seg
            V.append(p + r * (math.cos(a) * e1 + math.sin(a) * e2))
    for i in range(len(pts) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            F.append((i * seg + k, i * seg + k2, (i + 1) * seg + k2, (i + 1) * seg + k))
    return np.array(V), F


def build_forest_floor(tex_dir, rel, tmp):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    T = 12.0
    rng = np.random.RandomState(512)
    acc = Acc()
    hfun = periodic_height(T, [(1, 0.06), (2, 0.03), (3, 0.015)], rng)
    soil_mesh(acc, T, hfun, np.array([60, 48, 38]) / 255.0, 0.95)
    # no moss cushions in the tile: any distinctive feature repeats every 12 studs (moss belongs in its own
    # terrain material or as scattered props)
    mosses = []
    for (mx, my, mr) in mosses:
        for _ in range(9):
            ang, rad = rng.uniform(0, TAU), mr * 0.6 * math.sqrt(rng.rand())
            x, y = mx + rad * math.cos(ang), my + rad * math.sin(ang)
            r = rng.uniform(0.28, 0.48) * mr
            bumps = [(0.08, 3, 3, rng.uniform(0, 6), rng.uniform(0, 6)), (0.05, 5, 4, rng.uniform(0, 6),
                                                                          rng.uniform(0, 6))]
            V, F = ellipsoid_mesh(r, r * rng.uniform(0.8, 1.0), r * 0.38, 20, 10, bumps)
            V = rotz(V, rng.uniform(0, TAU))
            z = float(hfun(np.array(x), np.array(y))) + 0.02
            tv = np.clip(V[:, 2:3] / (r * 0.38), -1, 1) * 0.5 + 0.5
            col = (np.array([62, 80, 40]) + (np.array([104, 120, 58]) - np.array([62, 80, 40])) * tv) / 255.0
            for (dx, dy) in wrap_offsets(x, y, r, T):
                acc.add(V + np.array([x + dx, y + dy, z]), F, col * rng.uniform(0.95, 1.05),
                        (0.93, 0.5, rng.rand()))

    def in_moss(x, y):
        for (mx, my, mr) in mosses:
            dx = min(abs(x - mx), T - abs(x - mx))
            dy = min(abs(y - my), T - abs(y - my))
            if dx * dx + dy * dy < (mr * 0.85) ** 2:
                return True
        return False
    # small stones
    for (x, y, r) in poisson(rng, T, list(rng.uniform(0.12, 0.22, 4)), 0.5):
        V, F = ellipsoid_mesh(r * 1.15, r, r * 0.6, 18, 9, [(0.05, 2, 1, rng.uniform(0, 6), rng.uniform(0, 6))])
        V = rotz(V, rng.uniform(0, TAU))
        z = float(hfun(np.array(x), np.array(y))) - r * 0.15
        for (dx, dy) in wrap_offsets(x, y, r * 1.2, T):
            acc.add(V + np.array([x + dx, y + dy, z]), F, pick(rng, PEBBLE_PAL) / 255.0 * 0.78, (0.8, 0.25, 0.5))
    # leaves in three layers (low = decayed and dark, mid, top = fresher and warmer)
    nleaf = 0
    layer_z = {"low": 0.012, "mid": 0.03, "top": 0.05}
    for layer, count, pal in (("low", 900, LEAF_LOW), ("mid", 720, LEAF_MID), ("top", 250, LEAF_TOP)):
        for i in range(count):
            x, y = rng.uniform(0, T, 2)
            if in_moss(x, y) and rng.rand() < 0.85:
                continue
            kind = rng.choice(["oak", "beech", "birch"], p=[0.45, 0.35, 0.2])
            Lng = {"oak": rng.uniform(0.42, 0.62), "beech": rng.uniform(0.34, 0.5),
                   "birch": rng.uniform(0.24, 0.34)}[kind]
            V, F, luv = leaf_mesh(kind, Lng, rng)
            V = roty(V, rng.uniform(-0.08, 0.08))
            V = rotx(V, rng.uniform(-0.08, 0.08))
            V = rotz(V, rng.uniform(0, TAU))
            base = pick(rng, pal) / 255.0 * rng.uniform(0.92, 1.06)
            tip = base * rng.uniform(0.95, 1.12)
            tv = luv[:, 0:1]
            colv = base * (0.86 + 0.14 * tv) + (tip - base) * tv
            colv *= (1.0 - 0.1 * luv[:, 1:2] ** 2)
            z = float(hfun(np.array(x), np.array(y))) + layer_z[layer] + i * 0.000012
            r = Lng * 0.65
            for (dx, dy) in wrap_offsets(x, y, r, T):
                acc.add(V + np.array([x + dx, y + dy, z]), F, colv, (0.74 + 0.06 * rng.rand(), 0.75, rng.rand()),
                        luv)
            nleaf += 1
    # spruce needle clumps
    for _ in range(8):
        cx, cy = rng.uniform(0, T, 2)
        for _ in range(20):
            ang, rad = rng.uniform(0, TAU), 0.45 * math.sqrt(rng.rand())
            x, y = cx + rad * math.cos(ang), cy + rad * math.sin(ang)
            ln, wd = rng.uniform(0.2, 0.28), 0.038
            V = np.array([(-ln / 2, -wd / 2, 0), (ln / 2, -wd / 2, 0), (ln / 2, wd / 2, 0), (-ln / 2, wd / 2, 0),
                          (-ln / 2, 0, wd * 0.6), (ln / 2, 0, wd * 0.6)])
            F = [(0, 1, 5, 4), (4, 5, 2, 3), (0, 4, 3)[::-1], (1, 2, 5)]
            V = rotz(V, rng.uniform(0, TAU))
            z = float(hfun(np.array(x), np.array(y))) + 0.035 + rng.uniform(0, 0.02)
            col = np.array([(112, 76, 50), (98, 70, 50), (122, 88, 60)][rng.randint(3)]) / 255.0
            for (dx, dy) in wrap_offsets(x, y, ln, T):
                acc.add(V + np.array([x + dx, y + dy, z]), F, col, (0.8, 0.875, rng.rand()))
    # twigs
    for _ in range(9):
        x, y = rng.uniform(0, T, 2)
        ln = rng.uniform(0.8, 1.8)
        ang = rng.uniform(0, TAU)
        pts = []
        for k in range(5):
            s = (k / 4.0 - 0.5) * ln
            bend = 0.08 * math.sin(k * 1.3 + rng.rand())
            pts.append((x + s * math.cos(ang) - bend * math.sin(ang), y + s * math.sin(ang) + bend * math.cos(ang),
                        float(hfun(np.array(x), np.array(y))) + 0.085))
        V, F = tube(pts, rng.uniform(0.035, 0.06))
        col = np.array([(104, 90, 76), (88, 74, 62), (116, 100, 82)][rng.randint(3)]) / 255.0
        for (dx, dy) in wrap_offsets(x, y, ln / 2 + 0.1, T):
            acc.add(V + np.array([dx, dy, 0]), F, col, (0.85, 1.0, rng.rand()))
    # cones (lying on their side, with scale ridges)
    for _ in range(3):
        x, y = rng.uniform(0, T, 2)
        V, F = ellipsoid_mesh(0.34, 0.19, 0.19, 18, 16)
        ax = (V[:, 0] / 0.34 + 1) / 2
        ridge = np.maximum(0, np.sin(TAU * 7 * ax + np.arctan2(V[:, 2], V[:, 1]) * 1.0)) ** 2
        V[:, 1:] *= (1 + 0.16 * ridge)[:, None]
        V = rotz(V, rng.uniform(0, TAU))
        z = float(hfun(np.array(x), np.array(y))) + 0.17
        col = (np.array([120, 84, 54]) / 255.0)[None, :] * (0.85 + 0.3 * ridge[:, None])
        for (dx, dy) in wrap_offsets(x, y, 0.4, T):
            acc.add(V + np.array([x + dx, y + dy, z]), F, col, (0.8, 0.625, rng.rand()))
    acc.build("GD_ForestFloor")
    log("GROUND ForestFloor: %d leaves, 8 needle clumps, 9 twigs, 3 cones" % nleaf)
    P = render_passes(T, tmp, "ForestFloor", ao_dist=(0.1, 0.4))
    col = P["col"]
    nrm = P["nrm"] * 2.0 - 1.0
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
    aux = P["aux"]
    luv = P["luv"]
    ao1 = np.clip(P["ao"][..., 0], 0, 1)
    ao2 = np.clip(P["ao"][..., 1], 0, 1)
    leaf = np.clip(luv[..., 2], 0, 1)
    along, across = luv[..., 0], luv[..., 1]
    midrib = L.ss(0.09, 0.03, across) * L.ss(0.02, 0.08, along) * L.ss(0.97, 0.85, along) * L.ss(0.9, 1.0, leaf)
    vein_f = np.abs(((along * 7.0 - across * 1.4) % 1.0) - 0.5) * 2.0
    vein = L.ss(0.16, 0.04, vein_f) * L.ss(0.08, 0.2, across) * L.ss(0.85, 0.6, across) * L.ss(0.9, 1.0, leaf)
    srgb = col * (1.0 + 0.13 * midrib + 0.05 * vein)[..., None]
    srgb = L.mixc(srgb, srgb * np.array([1.06, 1.05, 0.9]), midrib * 0.5)
    nprng = np.random.RandomState(9)
    low = L.periodic_noise(nprng, RES, RES, 1, 4)
    mid = L.periodic_noise(nprng, RES, RES, 5, 12)
    srgb *= (1.0 + 0.06 * low + 0.025 * mid)[..., None]
    srgb = L.mixc(srgb, srgb * np.array([1.05, 1.0, 0.9]), np.clip(low, 0, 1) * 0.5)
    srgb = L.mixc(srgb, srgb * np.array([0.92, 0.97, 1.04]), np.clip(-low, 0, 1) * 0.5)
    top = L.ss(0.5, 1.0, nrm[..., 2])
    srgb *= (0.93 + 0.1 * top)[..., None]
    lin = L.srgb2lin(np.clip(srgb, 0, 1))
    lin *= ((0.42 + 0.58 * ao1 ** 1.2) * (0.66 + 0.34 * ao2))[..., None]
    out = L.lin2srgb(lin)
    rough = np.clip(aux[..., 0] + 0.03 * (1 - ao1), 0, 1)
    return finish("StyleC_ForestFloor", T, out, nrm, rough, tex_dir, rel,
                  "Painted leaf litter: %d modelled oak / beech / birch leaves in three layers (dark decayed -> "
                  "warm fresh), spruce needle clumps, twigs and cones on dark humus. %.0fs" % (
                      nleaf, time.time() - t0), "LeafyGrass", (176, 170, 160))


def build_all(tex_dir, rel):
    tmp = os.path.join(os.environ.get("TEMP", tex_dir), "StyleC_ground")
    os.makedirs(tmp, exist_ok=True)
    return [build_pebble_path(tex_dir, rel, tmp), build_forest_floor(tex_dir, rel, tmp)]
