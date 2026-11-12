"""
tex_items.py - shared texture / bake / export core for the realistic ItemsReal set (LAST STANDING),
Blender 5.3 headless. Used by items_real.py (the ArmsReal set was dropped: the game keeps its original hands); nothing here edits ls_common, ls_patch or any other
artist's files.

PIPELINE (per texture set = one 1024 atlas shared by many assets)
  1. Geometry. Every mesh piece is tagged with per-piece attributes before it is joined into a part:
       mid  (face)   material id (see tex_items_mats.MATS)
       gco  (point)  piece-local "grain" coordinates: x along the grain / weave / bone axis, + a random offset
       rnd  (point)  per-piece random 0..1 (colour variation between planks, strips, washers...)
       bevr (point)  edge-rounding radius in studs for the baked bevel normal
       a0..a3 (point) material-specific parameters (blade grind band, wrap phase, finger/nail coordinates...)
  2. UVs. Smart UV project per part, islands normalised to a common texel density (x a per-part weight),
     then all parts of the set are packed together into one 0..1 atlas (Blender's concave packer).
  3. Data bake (Cycles, GPU). The asset-local position, normal, gco, ids, attributes, ambient occlusion at
     several radii, convexity and a tangent-space "rounded edge" normal (Bevel shader) are baked into float
     images. Assets are spread 100 studs apart, so occlusion only comes from the asset's own parts (and a
     ground plane for crates).
  4. Material synthesis (numpy, tex_items_mats). Every texel knows where it is on the object, so materials are
     solid 3D textures: no visible UV seams, wear on real edges, grime in real crevices, rust streaks under real
     nails. Output: albedo, alpha, roughness, metalness and a height field (studs) per texel.
  5. Normal map = bevel normal (Cycles) reoriented-blended with the height detail; every map is push-pull
     dilated into the empty space so mip levels never pick up the background.
  6. Export. PNGs: <Set>_Color (RGB or RGBA), _Normal (OpenGL, +Y), _Roughness, _Metalness (textures/<Set>/);
     the GLB embeds Color + Normal + MetallicRoughness (glTF: G = roughness, B = metalness, R = baked AO).
"""
import json
import math
import os
import struct
import sys
import time
import zlib

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

V = Vector
TAU = 2.0 * math.pi
BLENDER = bpy.app.version


# =============================================================================================== PNG I/O
def _png_filter(raw, ft, bpp):
    r = raw.astype(np.int16)
    a = np.zeros_like(r)
    a[:, bpp:] = r[:, :-bpp]
    b = np.zeros_like(r)
    b[1:, :] = r[:-1, :]
    if ft == 1:
        out = r - a
    elif ft == 2:
        out = r - b
    elif ft == 3:
        out = r - ((a + b) >> 1)
    else:
        c = np.zeros_like(r)
        c[1:, bpp:] = r[:-1, :-bpp]
        p = a + b - c
        pa, pb, pc = np.abs(p - a), np.abs(p - b), np.abs(p - c)
        pred = np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, c))
        out = r - pred
    return (out & 0xFF).astype(np.uint8)


def write_png(path, img, dither=True):
    """img: float 0..1, H x W (gray) or H x W x 3/4; row 0 = BOTTOM (V = 0, Blender order). 8-bit PNG."""
    a = np.asarray(img, dtype=np.float64)
    h, w = a.shape[:2]
    if dither:
        bayer = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0 - 0.5
        d = np.tile(bayer, (h // 4 + 1, w // 4 + 1))[:h, :w]
        if a.ndim == 3:
            d = d[..., None]
        a = a * 255.0 + d * 0.8
    else:
        a = a * 255.0
    arr = np.clip(np.round(a), 0, 255).astype(np.uint8)
    arr = np.flipud(arr)
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    ctype = {1: 0, 3: 2, 4: 6}[ch]
    raw = arr.reshape(h, w * ch)
    best = None
    for ft in (1, 2, 4):
        filt = _png_filter(raw, ft, ch)
        data = np.concatenate([np.full((h, 1), ft, np.uint8), filt], axis=1).tobytes()
        comp = zlib.compress(data, 9)
        if best is None or len(comp) < len(best):
            best = comp

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)))
        f.write(chunk(b"IDAT", best))
        f.write(chunk(b"IEND", b""))
    return path


def image_to_np(img):
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4)


def load_png_np(path):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = "Non-Color"
    a = image_to_np(img).copy()
    bpy.data.images.remove(img)
    return a


# =============================================================================================== colour
def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def C(r, g, b):
    """sRGB 0-255 -> linear float triple."""
    return srgb_to_lin(np.array([r, g, b], dtype=np.float64) / 255.0)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t, dtype=np.float64)
    if np.ndim(a) == 2 or np.ndim(b) == 2:
        if t.ndim == 1:
            t = t[:, None]
    return a + (b - a) * t


# =============================================================================================== noise (numpy)
_GRAD = np.array([[1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0], [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
                  [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1], [1, 1, 0], [-1, 1, 0], [0, -1, 1], [0, -1, -1]],
                 dtype=np.float64)
_M32 = np.uint64(0xFFFFFFFF)


def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.uint64) * np.uint64(0x8DA6B343)) ^ (iy.astype(np.uint64) * np.uint64(0xD8163841)) \
        ^ (iz.astype(np.uint64) * np.uint64(0xCB1AB31F)) ^ np.uint64((seed * 0x165667B1 + 0x27D4EB2F) & 0xFFFFFFFF)
    h &= _M32
    h ^= h >> np.uint64(15)
    h = (h * np.uint64(0x2C1B3C6D)) & _M32
    h ^= h >> np.uint64(12)
    h = (h * np.uint64(0x297A2D39)) & _M32
    h ^= h >> np.uint64(15)
    return h


def perlin(P, seed=0):
    """3D gradient noise, P (N, 3) -> (N,) roughly in [-1, 1]."""
    P = np.asarray(P, dtype=np.float64)
    Pi = np.floor(P)
    f = P - Pi
    Pi = Pi.astype(np.int64)
    u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
    out = np.zeros(len(P))
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1.0 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1.0 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1.0 - u[:, 2]
                h = _hash(Pi[:, 0] + dx, Pi[:, 1] + dy, Pi[:, 2] + dz, seed) & np.uint64(15)
                g = _GRAD[h.astype(np.int64)]
                d = (f[:, 0] - dx) * g[:, 0] + (f[:, 1] - dy) * g[:, 1] + (f[:, 2] - dz) * g[:, 2]
                out += wx * wy * wz * d
    return out


_ROTS = []
_rng0 = np.random.default_rng(1234)
for _i in range(12):
    q, _ = np.linalg.qr(_rng0.normal(size=(3, 3)))
    _ROTS.append(q)


def fbm(P, freq=1.0, octaves=4, lac=2.03, gain=0.5, seed=0):
    P = np.asarray(P, dtype=np.float64)
    out = np.zeros(len(P))
    amp, norm, f = 1.0, 0.0, freq
    for o in range(octaves):
        out += amp * perlin((P @ _ROTS[o % 12]) * f, seed + o * 101)
        norm += amp
        amp *= gain
        f *= lac
    return out / norm


def ridged(P, freq=1.0, octaves=4, lac=2.03, gain=0.5, seed=0):
    P = np.asarray(P, dtype=np.float64)
    out = np.zeros(len(P))
    amp, norm, f = 1.0, 0.0, freq
    for o in range(octaves):
        out += amp * (1.0 - np.abs(perlin((P @ _ROTS[o % 12]) * f, seed + o * 131)))
        norm += amp
        amp *= gain
        f *= lac
    return out / norm


def voronoi(P, freq=1.0, seed=0, jitter=0.9):
    """F1, F2 distances (in cell units) and a 0..1 random id of the nearest feature point."""
    P = np.asarray(P, dtype=np.float64) * freq
    Pi = np.floor(P)
    f = P - Pi
    Pi = Pi.astype(np.int64)
    n = len(P)
    f1 = np.full(n, 9.0)
    f2 = np.full(n, 9.0)
    cid = np.zeros(n)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                h = _hash(Pi[:, 0] + dx, Pi[:, 1] + dy, Pi[:, 2] + dz, seed)
                jx = ((h & np.uint64(1023)).astype(np.float64) / 1023.0 - 0.5) * jitter + 0.5
                jy = (((h >> np.uint64(10)) & np.uint64(1023)).astype(np.float64) / 1023.0 - 0.5) * jitter + 0.5
                jz = (((h >> np.uint64(20)) & np.uint64(1023)).astype(np.float64) / 1023.0 - 0.5) * jitter + 0.5
                ddx = dx + jx - f[:, 0]
                ddy = dy + jy - f[:, 1]
                ddz = dz + jz - f[:, 2]
                d = np.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                cid = np.where(closer, ((h >> np.uint64(5)) & np.uint64(4095)).astype(np.float64) / 4095.0, cid)
                f1 = np.where(closer, d, f1)
    return f1, f2, cid


def cell_rand(P, freq=1.0, seed=0):
    """0..1 random value constant per integer cell of P * freq."""
    Pi = np.floor(np.asarray(P, dtype=np.float64) * freq).astype(np.int64)
    h = _hash(Pi[:, 0], Pi[:, 1], Pi[:, 2], seed)
    return (h & np.uint64(65535)).astype(np.float64) / 65535.0


def scratches(P, density=1.0, freq=60.0, width=0.08, seed=0, layers=4, length=0.25, dirs=None):
    """Clusters of fine straight scratches: for each layer a random direction; thin bands of a 1D sine pattern
    across that direction, broken into short dashes by low-frequency noise. Returns 0..1 mask."""
    P = np.asarray(P, dtype=np.float64)
    rng = np.random.default_rng(seed)
    out = np.zeros(len(P))
    for k in range(layers):
        if dirs is not None:
            d = np.asarray(dirs[k % len(dirs)], dtype=np.float64)
            d = d + rng.normal(scale=0.15, size=3)
        else:
            d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        across = P @ d
        ph = perlin(P * (freq * 0.05) + rng.uniform(0, 100, 3), seed + 7 * k) * 2.0
        line = np.abs(np.sin(across * freq * (0.7 + 0.6 * rng.random()) + ph))
        line = smoothstep(1.0 - width, 1.0, line)
        # dashes: keep only where a low-frequency noise (stretched across the line direction) is high
        e = rng.normal(size=3)
        e -= d * (e @ d)
        e /= np.linalg.norm(e)
        Q = np.stack([across * freq * 0.08, (P @ e) / max(length, 1e-3), P @ np.cross(d, e) * 3.0], axis=1)
        mask = smoothstep(0.55 - 0.25 * density, 0.75 - 0.2 * density, perlin(Q + rng.uniform(0, 50, 3), seed + 31 * k) * 0.5 + 0.5)
        out = np.maximum(out, line * mask * rng.uniform(0.5, 1.0))
    return out


# =============================================================================================== image ops
def pushpull(arr, mask, levels=11):
    """Fill pixels where mask == 0 with smooth extrapolation of the covered pixels (mip push-pull).
    arr: H x W or H x W x C float; mask: H x W bool/float. Returns a new array."""
    a = np.asarray(arr, dtype=np.float64)
    squeeze = a.ndim == 2
    if squeeze:
        a = a[..., None]
    w = np.asarray(mask, dtype=np.float64)[..., None]
    pyr = [(a * w, w)]
    cur_a, cur_w = a * w, w
    for _ in range(levels):
        h, wd = cur_w.shape[:2]
        if h < 2 or wd < 2:
            break
        ca = cur_a[: h // 2 * 2, : wd // 2 * 2]
        cw = cur_w[: h // 2 * 2, : wd // 2 * 2]
        ca = ca.reshape(h // 2, 2, wd // 2, 2, -1).sum(axis=(1, 3))
        cw = cw.reshape(h // 2, 2, wd // 2, 2, -1).sum(axis=(1, 3))
        pyr.append((ca, cw))
        cur_a, cur_w = ca, cw
    # pull back down
    fa, fw = pyr[-1]
    filled = np.where(fw > 0, fa / np.maximum(fw, 1e-12), 0.0)
    for (la, lw) in reversed(pyr[:-1]):
        up = np.repeat(np.repeat(filled, 2, axis=0), 2, axis=1)
        h, wd = la.shape[:2]
        if up.shape[0] < h or up.shape[1] < wd:
            up = np.pad(up, ((0, h - up.shape[0]), (0, wd - up.shape[1]), (0, 0)), mode="edge")
        up = up[:h, :wd]
        own = la / np.maximum(lw, 1e-12)
        filled = np.where(lw > 0, own, up)
        # smooth only the filled region a little (box 3x3) to avoid blocky fills
        sm = (filled + np.roll(filled, 1, 0) + np.roll(filled, -1, 0) + np.roll(filled, 1, 1) + np.roll(filled, -1, 1)) / 5.0
        filled = np.where(lw > 0, own, sm)
    out = np.where(w > 0, a, filled)
    return out[..., 0] if squeeze else out


def blur(arr, sigma):
    """Separable gaussian blur (wrap-around edges), arr H x W or H x W x C."""
    a = np.asarray(arr, dtype=np.float64)
    r = max(1, int(math.ceil(sigma * 3)))
    x = np.arange(-r, r + 1)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    k /= k.sum()
    out = np.zeros_like(a)
    for i, kv in zip(x, k):
        out += kv * np.roll(a, i, axis=0)
    a2 = out
    out = np.zeros_like(a2)
    for i, kv in zip(x, k):
        out += kv * np.roll(a2, i, axis=1)
    return out


def blur_masked(arr, mask, sigma):
    """Blur only using covered pixels (normalised), result valid on covered pixels."""
    a = np.asarray(arr, dtype=np.float64)
    m = np.asarray(mask, dtype=np.float64)
    if a.ndim == 3:
        num = blur(a * m[..., None], sigma)
        den = blur(m, sigma)[..., None]
    else:
        num = blur(a * m, sigma)
        den = blur(m, sigma)
    return np.where(den > 1e-6, num / np.maximum(den, 1e-6), a)


def _diff(a, cov, axis):
    """Central difference along axis, one-sided where a neighbour is not covered."""
    fwd = np.roll(a, -1, axis=axis)
    bwd = np.roll(a, 1, axis=axis)
    cf = np.roll(cov, -1, axis=axis)
    cb = np.roll(cov, 1, axis=axis)
    if a.ndim == 3:
        cf3, cb3 = cf[..., None], cb[..., None]
    else:
        cf3, cb3 = cf, cb
    both = (fwd - bwd) * 0.5
    d = np.where(cf3 & cb3, both, np.where(cf3, fwd - a, np.where(cb3, a - bwd, 0.0)))
    return d


def normal_from_height(h, P, cov, strength=1.0, max_slope=6.0):
    """Tangent-space (OpenGL) normal from a height field h (studs) using the baked position P (H x W x 3) for the
    world length of a texel. Assumes MikkTSpace tangent ~ dP/du and bitangent ~ dP/dv."""
    dhx = _diff(h, cov, 1)
    dhy = _diff(h, cov, 0)
    dPx = _diff(P, cov, 1)
    dPy = _diff(P, cov, 0)
    lx = np.linalg.norm(dPx, axis=2)
    ly = np.linalg.norm(dPy, axis=2)
    sx = np.where(lx > 1e-7, dhx / np.maximum(lx, 1e-7), 0.0) * strength
    sy = np.where(ly > 1e-7, dhy / np.maximum(ly, 1e-7), 0.0) * strength
    sx = np.clip(sx, -max_slope, max_slope)
    sy = np.clip(sy, -max_slope, max_slope)
    n = np.stack([-sx, -sy, np.ones_like(sx)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n


def rnm(base, detail):
    """Reoriented normal mapping: base and detail are tangent-space unit normals (H x W x 3)."""
    t = base + np.array([0.0, 0.0, 1.0])
    u = detail * np.array([-1.0, -1.0, 1.0])
    r = t * (np.sum(t * u, axis=2, keepdims=True) / np.maximum(t[..., 2:3], 1e-6)) - u
    return r / np.maximum(np.linalg.norm(r, axis=2, keepdims=True), 1e-9)


# =============================================================================================== piece attributes
ATTR_FLOATS = ("rnd", "bevr", "a0", "a1", "a2", "a3")


def frame_axes(axis, up_hint=(0, 0, 1)):
    x = V(axis).normalized()
    up = V(up_hint)
    if abs(x.dot(up.normalized())) > 0.95:
        up = V((1, 0, 0)) if abs(x.x) < 0.9 else V((0, 1, 0))
    y = (up - x * up.dot(x)).normalized()
    z = x.cross(y)
    return x, y, z


def tag(obj, mid, axis=(0, 0, 1), origin=(0, 0, 0), rnd=None, bevr=0.01, up=(0, 0, 1), seed_offset=True,
        a=None, rng=None, uvw=1.0):
    """Give a mesh piece its bake attributes (see module doc). Works on the mesh data in its current space
    (bake the object transform first). a = dict {a0: value or callable(co)->float, ...}."""
    me = obj.data
    if rnd is None:
        rnd = (rng.random() if rng is not None else 0.5)
    x, y, z = frame_axes(axis, up)
    o = V(origin)
    off = V((rnd * 37.13, rnd * 11.71, rnd * 23.37)) if seed_offset else V((0, 0, 0))
    for nm in ("gco",):
        if nm in me.attributes:
            me.attributes.remove(me.attributes[nm])
    g = me.attributes.new("gco", "FLOAT_VECTOR", "POINT")
    vals = []
    for v in me.vertices:
        d = v.co - o
        vals.append((d.dot(x) + off.x, d.dot(y) + off.y, d.dot(z) + off.z))
    g.data.foreach_set("vector", np.array(vals, dtype=np.float32).ravel())
    if "mid" in me.attributes:
        me.attributes.remove(me.attributes["mid"])
    m = me.attributes.new("mid", "FLOAT", "FACE")
    m.data.foreach_set("value", np.full(len(me.polygons), float(mid), dtype=np.float32))
    if "uvw" in me.attributes:
        me.attributes.remove(me.attributes["uvw"])
    w = me.attributes.new("uvw", "FLOAT", "FACE")
    w.data.foreach_set("value", np.full(len(me.polygons), float(uvw), dtype=np.float32))
    for nm in ATTR_FLOATS:
        if nm in me.attributes:
            me.attributes.remove(me.attributes[nm])
        at = me.attributes.new(nm, "FLOAT", "POINT")
        if nm == "rnd":
            vv = np.full(len(me.vertices), rnd, dtype=np.float32)
        elif nm == "bevr":
            vv = np.full(len(me.vertices), bevr, dtype=np.float32)
        else:
            spec = (a or {}).get(nm, 0.0)
            if callable(spec):
                vv = np.array([spec(v.co) for v in me.vertices], dtype=np.float32)
            else:
                vv = np.full(len(me.vertices), float(spec), dtype=np.float32)
        at.data.foreach_set("value", vv)
    me.update()
    return obj


def set_attr(obj, name, fn):
    """Overwrite a point float attribute from fn(co) -> float."""
    me = obj.data
    at = me.attributes[name]
    at.data.foreach_set("value", np.array([fn(v.co) for v in me.vertices], dtype=np.float32))
    me.update()


def bake_xform(obj):
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    return obj


def join(objs, name):
    """Concatenate meshes (with transforms) into one object; custom attributes survive (bmesh layers)."""
    objs = [o for o in objs if o is not None]
    bpy.context.view_layer.update()
    bm = bmesh.new()
    for o in objs:
        me = o.data.copy()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mesh_from(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate(clean_customdata=False)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def shade(obj, angle_deg=None):
    """None = flat, a number = smooth below that angle, 'keep' = keep the per-piece flags set before the join."""
    me = obj.data
    if angle_deg == "keep":
        return obj
    if angle_deg is None:
        for p in me.polygons:
            p.use_smooth = False
    else:
        for p in me.polygons:
            p.use_smooth = True
        me.set_sharp_from_angle(angle=math.radians(angle_deg))
    return obj


def recalc_normals(obj):
    """Orient every connected shell outward by its signed volume (bmesh.ops.recalc_face_normals guesses wrong on
    thin wedges such as blades). Open shells keep the recalc result."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    seen = set()
    flipped = 0
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        comp = []
        stack = [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            comp.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        vol = 0.0
        for f in comp:
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1]))
        if vol < 0:
            bmesh.ops.reverse_faces(bm, faces=comp)
            flipped += 1
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def triangulate_ngons(obj):
    """Split faces with more than 4 corners (caps of lathes/sweeps, extruded profiles): the glTF exporter's
    MikkTSpace tangents fail on n-gons ('Could not calculate tangents'), leaving the part without TANGENT.
    Face attributes, loop UVs and smooth flags carry over to the new triangles."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="BEAUTY")
        bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def shell_volumes(obj):
    """Signed volume of every connected shell (diagnostics)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen, out = set(), []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        comp, stack = [], [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            comp.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        vol = 0.0
        for f in comp:
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1]))
        out.append(vol / 6.0)
    bm.free()
    return out


def mirror_x(obj):
    obj.data.transform(Matrix.Scale(-1.0, 4, (1.0, 0.0, 0.0)))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def nonmanifold_edges(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    bm.free()
    return bad


# =============================================================================================== UV atlas
def deselect_all():
    for o in bpy.context.scene.objects:
        if o is not None:
            o.select_set(False)


def _set_mode(objs, mode):
    deselect_all()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode=mode)


def uv_area_and_3d(obj):
    me = obj.data
    uv = me.uv_layers.active.data
    a2 = 0.0
    a3 = 0.0
    for p in me.polygons:
        a3 += p.area
        pts = [uv[li].uv for li in p.loop_indices]
        s = 0.0
        for i in range(len(pts)):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % len(pts)]
            s += x0 * y1 - x1 * y0
        a2 += abs(s) * 0.5
    return a2, a3


def unwrap_pack(objs, weights, res=1024, margin_px=5, angle=58.0, methods=None, pack_shape="AABB"):
    """Unwrap every object (smart project, or 'keep' to keep UVs already set by the builder), normalise texel
    density across objects (x weight), pack all islands into one 0..1 atlas. Returns {obj.name: px_per_stud}."""
    methods = methods or {}
    smart = [o for o in objs if not o.data.uv_layers or methods.get(o.name) == "smart"]
    for o in objs:
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
    if smart:
        _set_mode(smart, "EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle), margin_method="FRACTION", island_margin=0.002,
                                 area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    # normalise density: scale each object's UVs so sqrt(uv_area / area3d) = weight * k
    for o, w in zip(objs, weights):
        a2, a3 = uv_area_and_3d(o)
        if a2 <= 0 or a3 <= 0:
            continue
        s = w / math.sqrt(a2 / a3)
        uv = o.data.uv_layers.active.data
        arr = np.empty(len(uv) * 2, dtype=np.float32)
        uv.foreach_get("uv", arr)
        arr *= s
        uv.foreach_set("uv", arr)
        o.data.update()
    # per-island weights (face attribute uvw: hidden faces get few texels)
    from bpy_extras import bmesh_utils
    for o in objs:
        if "uvw" not in o.data.attributes:
            continue
        wv = np.empty(len(o.data.polygons), dtype=np.float32)
        o.data.attributes["uvw"].data.foreach_get("value", wv)
        if np.allclose(wv, 1.0):
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        uvl = bm.loops.layers.uv.active
        for isl in bmesh_utils.bmesh_linked_uv_islands(bm, uvl):
            k = float(np.mean([wv[f.index] for f in isl]))
            if abs(k - 1.0) < 1e-4:
                continue
            pts = [l[uvl].uv.copy() for f in isl for l in f.loops]
            cx = sum(p.x for p in pts) / len(pts)
            cy = sum(p.y for p in pts) / len(pts)
            for f in isl:
                for l in f.loops:
                    u = l[uvl].uv
                    l[uvl].uv = (cx + (u.x - cx) * k, cy + (u.y - cy) * k)
        bm.to_mesh(o.data)
        bm.free()
        o.data.update()
    _set_mode(objs, "EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, rotate_method="ANY", scale=True,
                            merge_overlap=False, margin_method="FRACTION", margin=margin_px / float(res),
                            shape_method=pack_shape)
    bpy.ops.object.mode_set(mode="OBJECT")
    dens = {}
    for o in objs:
        a2, a3 = uv_area_and_3d(o)
        dens[o.name] = math.sqrt(a2 / a3) * res if a3 > 0 else 0.0
    return dens


# =============================================================================================== Cycles setup
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


def _nt_clear(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    return nt


def _attr(nt, name):
    n = nt.nodes.new("ShaderNodeAttribute")
    n.attribute_type = "GEOMETRY"
    n.attribute_name = name
    return n


def _combine(nt, a, b, c):
    n = nt.nodes.new("ShaderNodeCombineXYZ")
    for s, v in zip(n.inputs, (a, b, c)):
        if isinstance(v, (int, float)):
            s.default_value = v
        else:
            nt.links.new(v, s)
    return n.outputs[0]


def _math(nt, op, a, b=0.0):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for s, v in zip(n.inputs, (a, b)):
        if isinstance(v, (int, float)):
            s.default_value = v
        else:
            nt.links.new(v, s)
    return n.outputs[0]


def data_material(kind, img, ao_dist=(0.06, 0.3, 0.05), bevel_scale=1.0):
    """Bake shaders. kind: P (object position), N (object normal), G (gco), M (mid, rnd, a0), A (a1, a2, a3),
    O (ao small, ao large, ao inside), E (convexity small, large, bevr), B (tangent bevel normal: NORMAL bake)."""
    mat = bpy.data.materials.new("_bake_" + kind)
    nt = _nt_clear(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    if kind == "B":
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 16
        r = _math(nt, "MULTIPLY", _attr(nt, "bevr").outputs["Fac"], bevel_scale)
        nt.links.new(r, bev.inputs["Radius"])
        bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
        nt.links.new(bev.outputs["Normal"], bsdf.inputs["Normal"])
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
        return mat
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    if kind in ("P", "N"):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(tc.outputs["Object" if kind == "P" else "Normal"], em.inputs["Color"])
    elif kind == "G":
        nt.links.new(_attr(nt, "gco").outputs["Vector"], em.inputs["Color"])
    elif kind == "M":
        nt.links.new(_combine(nt, _attr(nt, "mid").outputs["Fac"], _attr(nt, "rnd").outputs["Fac"],
                              _attr(nt, "a0").outputs["Fac"]), em.inputs["Color"])
    elif kind == "A":
        nt.links.new(_combine(nt, _attr(nt, "a1").outputs["Fac"], _attr(nt, "a2").outputs["Fac"],
                              _attr(nt, "a3").outputs["Fac"]), em.inputs["Color"])
    elif kind == "O":
        aos = []
        for d, inside in ((ao_dist[0], False), (ao_dist[1], False), (ao_dist[2], True)):
            ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
            ao.samples = 16
            ao.inside = inside
            ao.only_local = False
            ao.inputs["Distance"].default_value = d
            aos.append(ao.outputs["AO"])
        nt.links.new(_combine(nt, *aos), em.inputs["Color"])
    elif kind == "E":
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        vals = []
        for sc in (1.0, 3.0):
            bev = nt.nodes.new("ShaderNodeBevel")
            bev.samples = 16
            r = _math(nt, "MULTIPLY", _attr(nt, "bevr").outputs["Fac"], sc * bevel_scale)
            nt.links.new(r, bev.inputs["Radius"])
            dp = nt.nodes.new("ShaderNodeVectorMath")
            dp.operation = "DOT_PRODUCT"
            nt.links.new(bev.outputs["Normal"], dp.inputs[0])
            nt.links.new(geo.outputs["Normal"], dp.inputs[1])
            vals.append(_math(nt, "SUBTRACT", 1.0, dp.outputs["Value"]))
        nt.links.new(_combine(nt, vals[0], vals[1], _attr(nt, "bevr").outputs["Fac"]), em.inputs["Color"])
    return mat


class Baker:
    """Bakes the data passes of one texture set into numpy arrays (cached as .npz)."""

    PASSES = ("P", "N", "G", "M", "A", "O", "E", "B")

    def __init__(self, res=1024, cache_dir=None, samples_data=1, samples_ao=96):
        self.res = res
        self.cache_dir = cache_dir
        self.samples_data = samples_data
        self.samples_ao = samples_ao

    def bake(self, name, objs, ao_dist=(0.06, 0.3, 0.05), extra_occluders=(), bevel_scale=1.0, force=False):
        cache = os.path.join(self.cache_dir, name + "_data.npz") if self.cache_dir else None
        if cache and os.path.exists(cache) and not force:
            d = np.load(cache)
            return {k: d[k] for k in d.files}
        scene = bpy.context.scene
        dev = enable_gpu(scene)
        scene.cycles.use_denoising = False
        scene.cycles.use_adaptive_sampling = False
        scene.cycles.max_bounces = 0
        scene.render.bake.margin = 0
        scene.render.bake.use_clear = False
        scene.render.bake.use_selected_to_active = False
        world = bpy.data.worlds.get("_bake_world") or bpy.data.worlds.new("_bake_world")
        scene.world = world
        saved = {o.name: list(o.data.materials) for o in objs}
        out = {}
        t0 = time.time()
        for kind in self.PASSES:
            img = bpy.data.images.new("_bake_%s_%s" % (name, kind), self.res, self.res, alpha=True, float_buffer=True)
            img.colorspace_settings.name = "Non-Color"
            sentinel = np.zeros((self.res, self.res, 4), dtype=np.float32)
            sentinel[..., 3] = -1.0
            img.pixels.foreach_set(sentinel.ravel())
            mat = data_material(kind, img, ao_dist=ao_dist, bevel_scale=bevel_scale)
            for o in objs:
                o.data.materials.clear()
                o.data.materials.append(mat)
            deselect_all()
            for o in objs:
                o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            scene.cycles.samples = self.samples_ao if kind in ("O", "E", "B") else self.samples_data
            if kind == "B":
                bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y",
                                    normal_b="POS_Z", margin=0, use_clear=False, target="IMAGE_TEXTURES")
            else:
                bpy.ops.object.bake(type="EMIT", margin=0, use_clear=False, target="IMAGE_TEXTURES")
            arr = image_to_np(img).copy()
            out[kind] = arr
            bpy.data.images.remove(img)
            bpy.data.materials.remove(mat)
        for o in objs:
            o.data.materials.clear()
            for m in saved[o.name]:
                o.data.materials.append(m)
        cov = out["P"][..., 3] > -0.5
        cov &= np.round(out["M"][..., 0]) % 100 > 0.5
        res = {"cov": cov}
        for k in self.PASSES:
            res[k] = out[k][..., :3]
        print("BAKE %s: %d passes on %s in %.1fs, coverage %.1f%%" % (name, len(self.PASSES), dev, time.time() - t0,
                                                                      100.0 * cov.mean()))
        if cache:
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            np.savez_compressed(cache, **res)
        return res


# =============================================================================================== library + export
ROBLOX_MAT = {
    "Steel": "Metal", "Metal": "Metal", "DarkMetal": "Metal", "Brass": "Metal", "Rust": "CorrodedMetal", "Tin": "Metal",
    "Wood": "Wood", "Planks": "WoodPlanks", "DarkPlanks": "WoodPlanks", "Leather": "Leather", "DarkLeather": "Leather",
    "Rope": "Fabric", "Cloth": "Fabric", "Canvas": "Fabric", "Bandage": "Fabric", "Feather": "Fabric", "Paper": "Cardboard",
    "Glass": "Glass", "WaterFill": "Glass", "Food": "SmoothPlastic", "Berry": "SmoothPlastic", "Leaves": "LeafyGrass",
    "Fern": "LeafyGrass", "Skin": "SmoothPlastic", "Sleeve": "Fabric", "Glove": "Leather", "Ember": "Neon",
    "Plaster": "Plaster",
}


class RealLibrary:
    """Asset bookkeeping for textured sets: parts, attachments, bounds, texture sets, GLB + manifest export.
    Manifest schema = the ls_common/ls_patch one, plus per-part 'surfaceAppearance' and a top-level 'textureSets'."""

    def __init__(self, category):
        self.category = category
        self.assets = []
        self.warnings = []
        self.notes = []
        self.sets = {}           # set name -> dict(images, alpha, ...)
        self.held = set()

    # ------------------------------------------------------------------ assets
    def _entry(self, root):
        for e in self.assets:
            if e["root"] == root:
                return e
        raise ValueError("unregistered root " + root.name)

    def begin(self, name, kind, tags=None, notes="", held=False):
        if any(e["name"] == name for e in self.assets):
            raise ValueError("duplicate asset " + name)
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        bpy.context.scene.collection.objects.link(root)
        self.assets.append({"name": name, "kind": kind, "tags": list(tags or []), "notes": notes, "root": root,
                            "parts": [], "attachments": {}, "objs": []})
        if held:
            self.held.add(name)
        return root

    def add(self, root, obj, role, texset, name=None, collide=False, collision="Box", cast_shadow=True, tags=None,
            smooth=None, alpha=None, weight=1.0, uv="smart", transparency=0.0, rgb=None, sa_extra=None):
        """Finalise a part. texset = texture set name (or None for an untextured part, e.g. Ember).
        alpha: None (opaque), 'Transparency' (glass/water), 'TintMask' (skin)."""
        e = self._entry(root)
        bake_xform(obj)
        triangulate_ngons(obj)
        recalc_normals(obj)
        shade(obj, smooth)
        if name is None:
            count = sum(1 for p in e["parts"] if p["role"] == role)
            name = "%s_%s" % (root.name, role) + ("" if count == 0 else "_%d" % (count + 1))
        obj.name = name
        obj.data.name = name
        obj.parent = root
        t = tris(obj)
        if t > 20000:
            raise ValueError("%s has %d tris" % (name, t))
        if not collide:
            collision = "Box"
        part = {"name": name, "role": role, "robloxMaterial": ROBLOX_MAT.get(role, "SmoothPlastic"),
                "rgb": list(rgb) if rgb else [128, 128, 128], "collide": bool(collide), "collision": collision,
                "castShadow": bool(cast_shadow), "canQuery": bool(collide), "canTouch": bool(collide),
                "tags": list(tags or []), "tris": t, "textureSet": texset, "alpha": alpha,
                "transparency": transparency, "_weight": weight, "_uv": uv, "_sa_extra": sa_extra or {},
                "_rgb_auto": rgb is None}
        e["parts"].append(part)
        e["objs"].append(obj)
        return obj

    def attach(self, root, name, position, look=(0, 0, 1), up=(0, 1, 0)):
        e = self._entry(root)
        e["attachments"][name] = {"position": to_roblox(V(position)), "look": to_roblox(V(look).normalized()),
                                  "up": to_roblox(V(up).normalized())}

    def finish(self, root):
        e = self._entry(root)
        lo, hi = bounds(e["objs"])
        a, b = to_roblox(lo), to_roblox(hi)
        e["boundsMin"] = [min(x, y) for x, y in zip(a, b)]
        e["boundsMax"] = [max(x, y) for x, y in zip(a, b)]
        size = hi - lo
        e["size"] = [round(size.x, 3), round(size.z, 3), round(size.y, 3)]
        e["tris"] = sum(p["tris"] for p in e["parts"])
        if lo.z < -0.05:
            msg = "%s dips %.2f studs below z = 0" % (root.name, -lo.z)
            if root.name in self.held:
                self.notes.append(msg + " [held item: grip at origin by convention]")
            else:
                self.warnings.append(msg + " (base should rest on 0)")
        print("ASSET %-16s tris=%5d size=%s parts=%s" % (e["name"], e["tris"], e["size"],
                                                        ",".join("%s(%d)" % (p["name"], p["tris"]) for p in e["parts"])))
        return e

    def parts_of_set(self, texset):
        out = []
        for e in self.assets:
            for p, o in zip(e["parts"], e["objs"]):
                if p["textureSet"] == texset:
                    out.append((e, p, o))
        return out

    # ------------------------------------------------------------------ export
    def export(self, out_dir, materials, gap=4.0, row=True):
        """materials: {(texset, alpha): bpy material}. Lays assets out in a row along X (origins recorded),
        exports <Category>.glb, writes <Category>.manifest.json. Returns the manifest dict."""
        for e in self.assets:
            if "size" not in e:
                self.finish(e["root"])
            for p, o in zip(e["parts"], e["objs"]):
                o.data.materials.clear()
                key = (p["textureSet"], p["alpha"])
                if key not in materials:
                    key = (p["textureSet"], None)
                o.data.materials.append(materials[key])
        x = 0.0
        for e in self.assets:
            off = x - e["boundsMin"][0]
            e["root"].location = (off, 0, 0)
            e["origin"] = [round(off, 4), 0.0, 0.0]
            x += e["size"][0] + gap
        bpy.context.view_layer.update()
        deselect_all()
        for e in self.assets:
            e["root"].select_set(True)
            for o in e["objs"]:
                ensure_uv(o)
                o.select_set(True)
        glb = os.path.join(out_dir, self.category + ".glb")
        # tangents ON: Roblox needs MikkTSpace tangents on imported meshes or the normal maps show no effect
        # (docs/research/LookDevPlaybook.md section 11); every mesh carries a UV map so tangents can be generated.
        bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                                  export_image_format="AUTO", export_materials="EXPORT", export_tangents=True,
                                  export_attributes=False, export_vertex_color="NONE")
        manifest = {
            "category": self.category,
            "glb": os.path.basename(glb),
            "units": "1 Blender unit = 1 Roblox stud",
            "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
            "textureSets": {k: {kk: vv for kk, vv in v.items() if not kk.startswith("_")} for k, v in self.sets.items()},
            "assets": [],
            "warnings": self.warnings,
            "notes": self.notes,
        }
        for e in self.assets:
            parts = []
            for p, o in zip(e["parts"], e["objs"]):
                q = {k: v for k, v in p.items() if not k.startswith("_") and k not in ("textureSet", "alpha", "transparency")}
                ts = p["textureSet"]
                if ts:
                    s = self.sets[ts]
                    sa = {"textureSet": ts, "colorMap": s["images"]["color"], "normalMap": s["images"]["normal"],
                          "roughnessMap": s["images"]["roughness"], "metalnessMap": s["images"].get("metalness"),
                          "alphaMode": p["alpha"] or "Overlay", "color": [255, 255, 255]}
                    sa.update(p["_sa_extra"])
                    q["surfaceAppearance"] = sa
                    mean = s.get("_mean_rgb", {}).get(o.name)
                    if mean is not None and p["_rgb_auto"]:
                        q["rgb"] = mean
                else:
                    q["surfaceAppearance"] = None
                q["transparency"] = p["transparency"]
                q["doubleSided"] = False
                q["backFacesInMesh"] = False
                parts.append(q)
            manifest["assets"].append({"name": e["name"], "kind": e["kind"], "tags": e["tags"], "notes": e["notes"],
                                       "origin": e["origin"], "size": e["size"], "boundsMin": e["boundsMin"],
                                       "boundsMax": e["boundsMax"], "tris": e["tris"], "parts": parts,
                                       "attachments": e["attachments"]})
        mpath = os.path.join(out_dir, self.category + ".manifest.json")
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1)
        size_mb = os.path.getsize(glb) / (1024 * 1024)
        print("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (glb, size_mb, len(self.assets), len(self.warnings)))
        for w in self.warnings:
            print("WARNING " + w)
        return manifest


def to_roblox(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def ensure_uv(obj):
    """Every exported mesh needs a UV map, otherwise the glTF exporter cannot generate MikkTSpace tangents for it
    (untextured parts such as SupplyCrate3_Ember): add a simple box projection normalised into 0..1."""
    if obj.type != "MESH" or obj.data.uv_layers:
        return obj
    me = obj.data
    uvl = me.uv_layers.new(name="UVMap")
    co = np.array([tuple(v.co) for v in me.vertices]) if len(me.vertices) else np.zeros((1, 3))
    lo, span = co.min(axis=0), np.maximum(np.ptp(co, axis=0), 1e-6)
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [i for i in range(3) if i != ax]
        for li in p.loop_indices:
            v = co[me.loops[li].vertex_index]
            uvl.data[li].uv = (0.01 + 0.98 * (v[a] - lo[a]) / span[a], 0.01 + 0.98 * (v[b] - lo[b]) / span[b])
    me.update()
    return obj


def mean_rgb_by_uv(obj, img):
    """Area-weighted mean sRGB colour (0-255 ints) of a texture (H x W x 3+, row 0 = V 0, values 0..1 sRGB) under a
    part's UV faces: the fallback MeshPart.Color written to the manifest 'rgb'."""
    me = obj.data
    if not me.uv_layers:
        return None
    uv = me.uv_layers.active.data
    H, W = img.shape[:2]
    acc = np.zeros(3)
    wsum = 0.0
    for p in me.polygons:
        pts = [uv[li].uv for li in p.loop_indices]
        cu = sum(q.x for q in pts) / len(pts)
        cv = sum(q.y for q in pts) / len(pts)
        samples = [(cu, cv)] + [(0.7 * q.x + 0.3 * cu, 0.7 * q.y + 0.3 * cv) for q in pts]
        w = p.area / len(samples)
        for (u, v) in samples:
            x = min(W - 1, max(0, int(u * W)))
            y = min(H - 1, max(0, int(v * H)))
            acc += img[y, x, :3] * w
            wsum += w
    if wsum <= 0:
        return None
    return [int(round(c)) for c in np.clip(acc / wsum, 0, 1) * 255.0]


def verify_glb(path):
    """Read the GLB's JSON chunk: every primitive must carry NORMAL, TANGENT and TEXCOORD_0; report the materials'
    texture slots and the embedded images."""
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, _length = struct.unpack_from("<4sII", data, 0)
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    if magic != b"glTF" or ctype != b"JSON":
        raise ValueError("not a GLB: " + path)
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    meshes = js.get("meshes", [])
    prims = [(m.get("name", "?"), p) for m in meshes for p in m["primitives"]]
    report = {
        "meshes": len(meshes),
        "primitives": len(prims),
        "missingTangent": [n for n, p in prims if "TANGENT" not in p["attributes"]],
        "missingNormal": [n for n, p in prims if "NORMAL" not in p["attributes"]],
        "missingUV": [n for n, p in prims if "TEXCOORD_0" not in p["attributes"]],
        "images": [im.get("name") for im in js.get("images", [])],
        "materials": {},
    }
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        report["materials"][m.get("name")] = {
            "baseColorTexture": "baseColorTexture" in pbr, "metallicRoughnessTexture": "metallicRoughnessTexture" in pbr,
            "normalTexture": "normalTexture" in m, "alphaMode": m.get("alphaMode", "OPAQUE"),
            "emissive": m.get("emissiveFactor")}
    return report


def bounds(objs):
    bpy.context.view_layer.update()
    lo = V((1e9, 1e9, 1e9))
    hi = V((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        n = len(o.data.vertices)
        co = np.empty(n * 3, dtype=np.float64)
        o.data.vertices.foreach_get("co", co)
        co = co.reshape(n, 3)
        M = np.array(o.matrix_world)
        w = co @ M[:3, :3].T + M[:3, 3]
        lo = V(np.minimum(np.array(lo), w.min(axis=0)))
        hi = V(np.maximum(np.array(hi), w.max(axis=0)))
    return lo, hi


def export_material(name, color_png, normal_png, mr_png, alpha=False):
    """Principled material wired the way the glTF exporter maps to baseColor / normal / metallicRoughness."""
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True     # glTF doubleSided = false, matching the manifest (MeshPart.DoubleSided off)
    nt = _nt_clear(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])

    def img_node(path, colorspace):
        img = bpy.data.images.get(os.path.basename(path))
        if img is None:
            img = bpy.data.images.load(path, check_existing=True)
        img.colorspace_settings.name = colorspace
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        return n

    c = img_node(color_png, "sRGB")
    nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(c.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    mr = img_node(mr_png, "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(mr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = img_node(normal_png, "Non-Color")
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def flat_material(name, rgb, emission=0.0, metallic=0.0, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True     # glTF doubleSided = false
    nt = _nt_clear(mat)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    lin = [float(x) for x in srgb_to_lin(np.array(rgb) / 255.0)]
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


# =============================================================================================== texture set finishing
def finish_set(set_name, data, ch, tex_dir, has_alpha=False, orm_dir=None, res=1024):
    """ch: dict of full-res arrays from the material pass: albedo (H,W,3 linear), alpha (H,W), rough (H,W),
    metal (H,W), height (H,W studs), ao (H,W). Writes the PNGs, returns the texture set record."""
    cov = data["cov"]
    P = pushpull(data["P"], cov)
    h = pushpull(ch["height"], cov)
    nd = normal_from_height(h, P, cov)
    nb = data["B"] * 2.0 - 1.0
    nb = np.where(cov[..., None], nb, np.array([0.0, 0.0, 1.0]))
    nb /= np.maximum(np.linalg.norm(nb, axis=2, keepdims=True), 1e-9)
    n = rnm(nb, nd)
    n = pushpull(n, cov)
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-9)
    albedo = pushpull(lin_to_srgb(ch["albedo"]), cov)
    rough = pushpull(ch["rough"], cov)
    metal = pushpull(ch["metal"], cov)
    ao = pushpull(ch.get("ao", np.ones(cov.shape)), cov)
    os.makedirs(tex_dir, exist_ok=True)
    files = {}
    if has_alpha:
        alpha = pushpull(ch["alpha"], cov)
        col = np.concatenate([albedo, alpha[..., None]], axis=2)
    else:
        col = albedo
    files["color"] = write_png(os.path.join(tex_dir, set_name + "_Color.png"), np.clip(col, 0, 1))
    files["normal"] = write_png(os.path.join(tex_dir, set_name + "_Normal.png"), np.clip(n * 0.5 + 0.5, 0, 1), dither=False)
    # separate 8-bit grayscale maps for hand-built SurfaceAppearances (Roblox does not split glTF metallicRoughness)
    files["roughness"] = write_png(os.path.join(tex_dir, set_name + "_Roughness.png"), np.clip(rough, 0, 1))
    stale = os.path.join(tex_dir, set_name + "_Metalness.png")
    if float(np.max(metal[cov])) > 0.05:
        files["metalness"] = write_png(stale, np.clip(metal, 0, 1))
    elif os.path.exists(stale):
        os.remove(stale)
    mr = np.stack([np.clip(ao, 0, 1), np.clip(rough, 0, 1), np.clip(metal, 0, 1)], axis=2)
    files["metallicRoughness"] = write_png(os.path.join(orm_dir or os.path.join(tex_dir, "_glb"), set_name + "_ORM.png"), mr)
    files["_albedo_srgb"] = albedo
    # moderation guard: no flat single-colour images
    for k, arr in (("color", col), ("normal", n), ("roughness", rough), ("metalness", metal)):
        if k == "metalness" and "metalness" not in files:
            continue
        if float(np.std(arr)) < 1e-3:
            print("WARNING %s %s is (nearly) a single flat colour" % (set_name, k))
    return files
