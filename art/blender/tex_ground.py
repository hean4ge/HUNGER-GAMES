"""
tex_ground.py - core helpers for the GroundReal set (realistic ground flora + rocks), Blender 5.3 headless.

Used by ground_real.py and its gr_*.py modules. Nothing here edits ls_common (frozen) or other artists' files.

Contents
- PNG writer (8-bit gray / RGB / RGBA, row 0 = BOTTOM = V 0) and EXR/PNG reader into numpy
- colour helpers (sRGB <-> linear), push-pull colour bleed, alpha-weighted 2x downsample
- numpy gradient noise (3D Perlin, fBm, ridged), periodic FFT noise for tiles
- surface nets (SDF grid -> watertight quad mesh), Newton projection onto the SDF
- fast mesh creation from numpy arrays, per-vertex colour/float attributes
- Cycles setup (OptiX GPU when present) for data renders and texture bakes
"""
import math
import os
import struct
import zlib

import bpy
import numpy as np
from mathutils import Matrix, Vector

TAU = 2.0 * math.pi


# =============================================================================================== PNG / images
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


def write_png(path, img, quantize=True):
    """img: float 0..1 (H x W or H x W x C), row 0 = BOTTOM (V = 0). Writes 8-bit PNG (gray/RGB/RGBA)."""
    a = np.asarray(img, dtype=np.float64)
    if quantize:
        # tiny ordered dither keeps smooth gradients from banding at 8 bits
        h, w = a.shape[:2]
        bayer = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0 - 0.5
        d = np.tile(bayer, (h // 4 + 1, w // 4 + 1))[:h, :w]
        if a.ndim == 3:
            d = d[..., None]
        a = a * 255.0 + d * 0.9
    else:
        a = a * 255.0
    arr = np.clip(np.round(a), 0, 255).astype(np.uint8)
    arr = np.flipud(arr)
    h, w = arr.shape[:2]
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
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)))
        f.write(chunk(b"IDAT", best))
        f.write(chunk(b"IEND", b""))
    return path


def load_image_np(path, colorspace="Non-Color"):
    """Read an image file through Blender: float32 H x W x 4, row 0 = bottom. EXR values stay linear."""
    img = bpy.data.images.load(path, check_existing=False)
    try:
        img.colorspace_settings.name = colorspace
    except TypeError:
        pass
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)


def np_to_image(name, arr, colorspace="Non-Color", float_buffer=True):
    """numpy H x W x (1|3|4) float (row 0 = bottom) -> bpy image (packed in memory)."""
    a = np.asarray(arr, dtype=np.float32)
    h, w = a.shape[:2]
    if a.ndim == 2:
        a = np.repeat(a[..., None], 3, axis=2)
    if a.shape[2] == 3:
        a = np.concatenate([a, np.ones((h, w, 1), np.float32)], axis=2)
    img = bpy.data.images.get(name)
    if img is not None and (img.size[0] != w or img.size[1] != h):
        bpy.data.images.remove(img)
        img = None
    if img is None:
        img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=float_buffer)
    img.colorspace_settings.name = colorspace
    img.pixels.foreach_set(a.ravel())
    img.update()
    return img


def image_to_np(img):
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4)


# =============================================================================================== colour maths
def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def rgb(r, g, b):
    """sRGB 0-255 -> linear float triple."""
    return srgb_to_lin(np.array([r, g, b], dtype=np.float64) / 255.0)


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t, dtype=np.float64)
    if t.ndim and np.ndim(a) > t.ndim:
        t = t[..., None]
    return a + (b - a) * t


def pushpull(rgb_arr, w, eps=1e-6):
    """Fill pixels with weight ~0 from their weighted neighbourhood at all scales (colour bleed for alpha cards
    and bake islands). rgb_arr: H x W x C, w: H x W in 0..1. Returns filled H x W x C (covered pixels keep their
    colour). Works for any size (pads to a power of two)."""
    h, wd = w.shape
    n = 1
    while n < max(h, wd):
        n *= 2
    C = rgb_arr.shape[2]
    col = np.zeros((n, n, C), np.float64)
    ww = np.zeros((n, n), np.float64)
    col[:h, :wd] = rgb_arr
    ww[:h, :wd] = np.clip(w, 0, 1)
    pyr = []
    c, a = col * ww[..., None], ww
    while c.shape[0] > 1:
        pyr.append((c, a))
        c = c.reshape(c.shape[0] // 2, 2, c.shape[1] // 2, 2, C).sum(axis=(1, 3))
        a = a.reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2).sum(axis=(1, 3))
        k = np.minimum(a, 1.0) / np.maximum(a, eps)       # renormalise to <= 1 total weight
        c, a = c * k[..., None], np.minimum(a, 1.0)
    # coarsest: colour = c / a
    up = c / np.maximum(a, eps)[..., None]
    for (cl, al) in reversed(pyr):
        up = np.repeat(np.repeat(up, 2, axis=0), 2, axis=1)
        est = cl / np.maximum(al, eps)[..., None]
        t = np.clip(al, 0, 1)[..., None]
        up = est * t + up * (1.0 - t)
    return up[:h, :wd]


def downsample2(rgba, premult=True):
    """2x box downsample of H x W x 4 (straight alpha). Colour is alpha-weighted."""
    h, w = rgba.shape[:2]
    r = rgba.reshape(h // 2, 2, w // 2, 2, rgba.shape[2])
    if not premult:
        return r.mean(axis=(1, 3))
    a = r[..., 3]
    asum = a.sum(axis=(1, 3))
    col = (r[..., :3] * a[..., None]).sum(axis=(1, 3)) / np.maximum(asum, 1e-8)[..., None]
    plain = r[..., :3].mean(axis=(1, 3))
    col = np.where(asum[..., None] > 1e-6, col, plain)
    return np.concatenate([col, (asum / 4.0)[..., None]], axis=2)


def box_down(arr, f):
    """Integer factor box downsample of H x W (x C)."""
    h, w = arr.shape[:2]
    if arr.ndim == 2:
        return arr.reshape(h // f, f, w // f, f).mean(axis=(1, 3))
    return arr.reshape(h // f, f, w // f, f, arr.shape[2]).mean(axis=(1, 3))


def encode_normal(n):
    n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-8)
    return n * 0.5 + 0.5


def decode_normal(c):
    n = c[..., :3] * 2.0 - 1.0
    return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-8)


# =============================================================================================== noise (numpy)
class Perlin:
    """Improved Perlin gradient noise in 3D (vectorised). noise() is ~[-1, 1]."""

    def __init__(self, seed=0):
        rng = np.random.RandomState(seed)
        p = rng.permutation(256)
        self.p = np.concatenate([p, p, p]).astype(np.int64)

    @staticmethod
    def _fade(t):
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

    @staticmethod
    def _grad(h, x, y, z):
        h = h & 15
        u = np.where(h < 8, x, y)
        v = np.where(h < 4, y, np.where((h == 12) | (h == 14), x, z))
        return np.where(h & 1, -u, u) + np.where(h & 2, -v, v)

    def noise(self, x, y, z):
        xf, yf, zf = np.floor(x), np.floor(y), np.floor(z)
        X = xf.astype(np.int64) & 255
        Y = yf.astype(np.int64) & 255
        Z = zf.astype(np.int64) & 255
        x = x - xf
        y = y - yf
        z = z - zf
        u, v, w = self._fade(x), self._fade(y), self._fade(z)
        p = self.p
        A = p[X] + Y
        AA = p[A] + Z
        AB = p[A + 1] + Z
        B = p[X + 1] + Y
        BA = p[B] + Z
        BB = p[B + 1] + Z
        g = self._grad
        x1, y1, z1 = x - 1.0, y - 1.0, z - 1.0
        l1 = g(p[AA], x, y, z) + u * (g(p[BA], x1, y, z) - g(p[AA], x, y, z))
        l2 = g(p[AB], x, y1, z) + u * (g(p[BB], x1, y1, z) - g(p[AB], x, y1, z))
        l3 = g(p[AA + 1], x, y, z1) + u * (g(p[BA + 1], x1, y, z1) - g(p[AA + 1], x, y, z1))
        l4 = g(p[AB + 1], x, y1, z1) + u * (g(p[BB + 1], x1, y1, z1) - g(p[AB + 1], x, y1, z1))
        m1 = l1 + v * (l2 - l1)
        m2 = l3 + v * (l4 - l3)
        return m1 + w * (m2 - m1)

    def fbm(self, P, freq=1.0, octaves=4, lac=2.0, gain=0.5, offset=(0.0, 0.0, 0.0)):
        """P: (..., 3). Sum of octaves, normalised to ~[-1, 1]."""
        x = P[..., 0] * freq + offset[0]
        y = P[..., 1] * freq + offset[1]
        z = P[..., 2] * freq + offset[2]
        total = np.zeros(x.shape, np.float64)
        amp, norm = 1.0, 0.0
        for o in range(octaves):
            total += amp * self.noise(x, y, z)
            norm += amp
            amp *= gain
            x, y, z = x * lac + 17.3, y * lac + 5.1, z * lac + 11.7
        return total / norm

    def ridged(self, P, freq=1.0, octaves=4, lac=2.0, gain=0.5, offset=(0.0, 0.0, 0.0)):
        x = P[..., 0] * freq + offset[0]
        y = P[..., 1] * freq + offset[1]
        z = P[..., 2] * freq + offset[2]
        total = np.zeros(x.shape, np.float64)
        amp, norm = 1.0, 0.0
        for o in range(octaves):
            n = 1.0 - np.abs(self.noise(x, y, z))
            total += amp * n * n
            norm += amp
            amp *= gain
            x, y, z = x * lac + 31.1, y * lac + 7.7, z * lac + 2.9
        return total / norm


def worley(P, cell, seed=0, jitter=0.9):
    """3D cellular noise on a jittered grid: returns F1, F2 distances (in units of P) and the nearest cell id."""
    rng = np.random.RandomState(seed)
    table = rng.random_sample((4096, 3))
    Q = P / cell
    base = np.floor(Q).astype(np.int64)
    f = Q - base
    F1 = np.full(Q.shape[:-1], 1e9)
    F2 = np.full(Q.shape[:-1], 1e9)
    ID = np.zeros(Q.shape[:-1], np.int64)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = base[..., 0] + dx, base[..., 1] + dy, base[..., 2] + dz
                h = (cx * 73856093) ^ (cy * 19349663) ^ (cz * 83492791)
                h = (h ^ (h >> 13)) & 4095
                j = 0.5 + (table[h] - 0.5) * jitter
                d = np.sqrt((dx + j[..., 0] - f[..., 0]) ** 2 + (dy + j[..., 1] - f[..., 1]) ** 2
                            + (dz + j[..., 2] - f[..., 2]) ** 2)
                closer = d < F1
                F2 = np.where(closer, F1, np.minimum(F2, d))
                ID = np.where(closer, h, ID)
                F1 = np.where(closer, d, F1)
    return F1 * cell, F2 * cell, ID


# periodic (tileable) 2D fields --------------------------------------------------------------------------
def band_noise(rng, n, f_lo, f_hi, beta=1.0, sx=1.0, sy=1.0):
    """Periodic n x n noise with energy between f_lo..f_hi cycles per tile; zero mean, unit std."""
    fy = (np.fft.fftfreq(n) * n)[:, None]
    fx = (np.fft.fftfreq(n) * n)[None, :]
    k = np.sqrt((fx * sx) ** 2 + (fy * sy) ** 2)
    k[0, 0] = 1e-6
    win = smoothstep(f_lo * 0.6, f_lo, k) * (1.0 - smoothstep(f_hi, f_hi * 1.5, k))
    amp = win * k ** (-beta)
    amp[0, 0] = 0.0
    phase = rng.uniform(0.0, TAU, (n, n))
    f = np.fft.ifft2(amp * np.exp(1j * phase)).real
    f -= f.mean()
    return f / (f.std() + 1e-12)


def pblur(img, sigma):
    """Periodic gaussian blur (sigma in pixels) of a square H x W field."""
    h, w = img.shape
    fy = (np.fft.fftfreq(h))[:, None]
    fx = (np.fft.fftfreq(w))[None, :]
    g = np.exp(-2.0 * (math.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    return np.fft.ifft2(np.fft.fft2(img) * g).real


def pworley(rng, n, cells, jitter=0.9):
    """Periodic 2D Worley on an n x n tile with cells x cells jittered points: F1, F2 (pixels), id."""
    cw = n / cells
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="xy"), -1) + 0.5
           + (rng.random_sample((cells, cells, 2)) - 0.5) * jitter) * cw     # [j, i] -> (x, y)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64) + 0.5
    ci = np.floor(xs / cw).astype(np.int64)
    cj = np.floor(ys / cw).astype(np.int64)
    F1 = np.full((n, n), 1e9)
    F2 = np.full((n, n), 1e9)
    ID = np.zeros((n, n), np.int64)
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            ii = ci + di
            jj = cj + dj
            px = pts[jj % cells, ii % cells, 0] + np.floor_divide(ii, cells) * n
            py = pts[jj % cells, ii % cells, 1] + np.floor_divide(jj, cells) * n
            d = np.sqrt((px - xs) ** 2 + (py - ys) ** 2)
            closer = d < F1
            F2 = np.where(closer, F1, np.minimum(F2, d))
            ID = np.where(closer, (jj % cells) * cells + (ii % cells), ID)
            F1 = np.where(closer, d, F1)
    return F1, F2, ID


def normal_from_height(h, px_per_stud, strength=1.0):
    """Periodic finite-difference OpenGL normal (+Y = up in the image, row 0 = bottom) from a height field in
    studs. Returns H x W x 3 unit normals."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * px_per_stud * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * px_per_stud * strength
    n = np.stack([-dx, -dy, np.ones_like(h)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


# =============================================================================================== surface nets
_CORNERS = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)]
_EDGES = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]


def surface_nets(F, origin, h):
    """F: (nx, ny, nz) SDF samples (negative inside) at origin + (i, j, k) * h.
    Returns verts (N, 3) float64 and quads (M, 4) int64 with outward winding."""
    nx, ny, nz = F.shape
    ins = F < 0
    cells = [ins[c[0]:nx - 1 + c[0], c[1]:ny - 1 + c[1], c[2]:nz - 1 + c[2]] for c in _CORNERS]
    anyin = np.zeros(cells[0].shape, bool)
    allin = np.ones(cells[0].shape, bool)
    for c in cells:
        anyin |= c
        allin &= c
    active = anyin & ~allin
    ai, aj, ak = np.nonzero(active)
    nverts = len(ai)
    index = -np.ones(active.shape, np.int64)
    index[ai, aj, ak] = np.arange(nverts)
    acc = np.zeros((nverts, 3))
    cnt = np.zeros(nverts)
    for (c0, c1) in _EDGES:
        p0 = np.array(_CORNERS[c0], float)
        p1 = np.array(_CORNERS[c1], float)
        f0 = F[ai + _CORNERS[c0][0], aj + _CORNERS[c0][1], ak + _CORNERS[c0][2]]
        f1 = F[ai + _CORNERS[c1][0], aj + _CORNERS[c1][1], ak + _CORNERS[c1][2]]
        cr = (f0 < 0) != (f1 < 0)
        t = np.where(cr, f0 / np.where(cr, f0 - f1, 1.0), 0.0)
        acc[cr] += p0 + t[cr, None] * (p1 - p0)
        cnt[cr] += 1
    local = acc / np.maximum(cnt, 1)[:, None]
    verts = np.asarray(origin, float) + h * (np.stack([ai, aj, ak], 1) + local)
    quads = []
    # x edges: sample (i,j,k)->(i+1,j,k); cells around: (i,j-1,k-1),(i,j,k-1),(i,j,k),(i,j-1,k)
    e = ins[:-1, 1:-1, 1:-1] != ins[1:, 1:-1, 1:-1]
    i, j, k = np.nonzero(e)
    j += 1
    k += 1
    q = np.stack([index[i, j - 1, k - 1], index[i, j, k - 1], index[i, j, k], index[i, j - 1, k]], 1)
    flip = ~ins[i, j, k]           # outside at the low end -> normal points -x
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    # y edges: cells (i-1,j,k-1),(i-1,j,k),(i,j,k),(i,j,k-1)
    e = ins[1:-1, :-1, 1:-1] != ins[1:-1, 1:, 1:-1]
    i, j, k = np.nonzero(e)
    i += 1
    k += 1
    q = np.stack([index[i - 1, j, k - 1], index[i - 1, j, k], index[i, j, k], index[i, j, k - 1]], 1)
    flip = ~ins[i, j, k]
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    # z edges: cells (i-1,j-1,k),(i,j-1,k),(i,j,k),(i-1,j,k)
    e = ins[1:-1, 1:-1, :-1] != ins[1:-1, 1:-1, 1:]
    i, j, k = np.nonzero(e)
    i += 1
    j += 1
    q = np.stack([index[i - 1, j - 1, k], index[i, j - 1, k], index[i, j, k], index[i - 1, j, k]], 1)
    flip = ~ins[i, j, k]
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    quads = np.concatenate(quads, 0)
    quads = quads[(quads >= 0).all(axis=1)]
    return verts, quads


def sdf_grid(fn, lo, hi, h, band=None, coarse_fn=None):
    """Sample fn(P (N,3)) -> (N,) on a grid covering lo..hi with spacing h. If coarse_fn and band are given,
    the expensive fn is only evaluated where |coarse_fn| < band (narrow band); elsewhere coarse_fn is used."""
    lo = np.asarray(lo, float)
    hi = np.asarray(hi, float)
    shape = np.ceil((hi - lo) / h).astype(int) + 1
    xs = lo[0] + np.arange(shape[0]) * h
    ys = lo[1] + np.arange(shape[1]) * h
    zs = lo[2] + np.arange(shape[2]) * h
    out = np.empty(tuple(shape), np.float32)
    for a in range(0, shape[0], 32):          # chunk along x to bound memory
        X, Y, Z = np.meshgrid(xs[a:a + 32], ys, zs, indexing="ij")
        P = np.stack([X, Y, Z], -1).reshape(-1, 3)
        if coarse_fn is not None and band is not None:
            v = coarse_fn(P)
            near = np.abs(v) < band
            if near.any():
                v[near] = fn(P[near])
        else:
            v = fn(P)
        out[a:a + 32] = v.reshape(X.shape)
    return out, lo


def project_to_sdf(verts, fn, iters=2, eps=1e-3, step=1.0, max_move=None):
    """Newton steps that move vertices onto the zero set of fn (sharpens surface-nets output). max_move clamps each
    step (and the total displacement): where the field's gradient is weak or discontinuous (blended cuts, joint
    intersections) an unclamped Newton step throws a vertex far off the surface and leaves a needle."""
    v = verts.copy()
    lim = eps * 50.0 if max_move is None else max_move
    for _ in range(iters):
        f = fn(v)
        g = np.stack([(fn(v + np.array([eps, 0, 0])) - f) / eps,
                      (fn(v + np.array([0, eps, 0])) - f) / eps,
                      (fn(v + np.array([0, 0, eps])) - f) / eps], 1)
        gg = np.maximum((g * g).sum(1), 1e-8)
        d = step * (f / gg)[:, None] * g
        n = np.linalg.norm(d, axis=1, keepdims=True)
        v -= d * np.minimum(1.0, lim / np.maximum(n, 1e-12))
    off = v - verts
    n = np.linalg.norm(off, axis=1, keepdims=True)
    return verts + off * np.minimum(1.0, lim / np.maximum(n, 1e-12))


# =============================================================================================== meshes
def mesh_object(name, verts, faces, collection=None):
    """Create a mesh object from numpy verts (N,3) and faces (M,3|4) or a list of index tuples."""
    me = bpy.data.meshes.new(name)
    verts = np.asarray(verts, dtype=np.float64)
    if isinstance(faces, np.ndarray) and faces.ndim == 2:
        k = faces.shape[1]
        me.vertices.add(len(verts))
        me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
        me.loops.add(faces.size)
        me.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
        me.polygons.add(len(faces))
        me.polygons.foreach_set("loop_start", (np.arange(len(faces)) * k).astype(np.int32))
        me.update(calc_edges=True)
    else:
        me.from_pydata(verts.tolist(), [], [tuple(int(i) for i in f) for f in faces])
        me.update(calc_edges=True)
    obj = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def set_point_color(me, name, cols):
    """cols: (N, 3|4) linear float per vertex."""
    cols = np.asarray(cols, np.float32)
    if cols.shape[1] == 3:
        cols = np.concatenate([cols, np.ones((len(cols), 1), np.float32)], 1)
    attr = me.color_attributes.get(name) or me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    attr.data.foreach_set("color", cols.ravel())


def set_point_float(me, name, vals):
    attr = me.attributes.get(name) or me.attributes.new(name, "FLOAT", "POINT")
    attr.data.foreach_set("value", np.asarray(vals, np.float32).ravel())


def set_uvs(me, uv_per_loop, name="UVMap"):
    layer = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    layer.data.foreach_set("uv", np.asarray(uv_per_loop, np.float32).ravel())
    return layer


def loop_vertex_indices(me):
    li = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", li)
    return li


def vertex_coords(me):
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3).astype(np.float64)


def set_custom_normals(me, loop_normals):
    """Per-loop custom split normals (unit vectors)."""
    n = np.asarray(loop_normals, np.float64)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    for p in me.polygons:
        p.use_smooth = True
    me.normals_split_custom_set([tuple(v) for v in n])


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


class MeshBuilder:
    """Accumulates verts/faces with per-vertex albedo (linear RGB), roughness and an 'ao_scale' float."""

    def __init__(self):
        self.V, self.F, self.C, self.R = [], [], [], []
        self.n = 0

    def add(self, verts, faces, color, rough=0.6):
        verts = np.asarray(verts, np.float64).reshape(-1, 3)
        k = len(verts)
        col = np.asarray(color, np.float64)
        if col.ndim == 1:
            col = np.tile(col, (k, 1))
        r = np.asarray(rough, np.float64)
        if r.ndim == 0:
            r = np.full(k, float(r))
        self.V.append(verts)
        self.C.append(col[:, :3])
        self.R.append(r)
        for f in faces:
            self.F.append(tuple(int(i) + self.n for i in f))
        self.n += k
        return self.n - k

    def build(self, name, collection=None):
        if not self.V:
            return None
        V = np.concatenate(self.V, 0)
        obj = mesh_object(name, V, self.F, collection)
        set_point_color(obj.data, "albedo", np.concatenate(self.C, 0))
        set_point_float(obj.data, "rough", np.concatenate(self.R, 0))
        for p in obj.data.polygons:
            p.use_smooth = True
        return obj


# =============================================================================================== scene / cycles
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def enable_gpu(scene):
    """Use OptiX (or CUDA) when present; returns the device string used."""
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


def data_render_settings(scene, res_x, res_y, samples=16):
    """Cycles settings for exact data renders (emission-only shaders, linear EXR output)."""
    enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = False
    c.use_denoising = False
    c.max_bounces = 0
    c.diffuse_bounces = 0
    c.glossy_bounces = 0
    c.transmission_bounces = 0
    c.transparent_max_bounces = 8
    c.filter_width = 1.0
    try:
        c.seed = 1
    except AttributeError:
        pass
    r = scene.render
    r.resolution_x = res_x
    r.resolution_y = res_y
    r.resolution_percentage = 100
    r.film_transparent = True
    r.use_compositing = False
    r.use_sequencer = False
    r.dither_intensity = 0.0
    r.image_settings.file_format = "OPEN_EXR"
    r.image_settings.color_depth = "32"
    r.image_settings.exr_codec = "ZIP"
    r.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    world = bpy.data.worlds.get("GR_DataWorld") or bpy.data.worlds.new("GR_DataWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0, 0, 0, 1)
        bg.inputs["Strength"].default_value = 0.0
    scene.world = world


def ortho_camera(scene, x0, y0, x1, y1, z=50.0, name="GR_DataCam"):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    w, h = x1 - x0, y1 - y0
    cam.data.ortho_scale = max(w, h)
    cam.data.sensor_fit = "AUTO"
    cam.data.clip_start = 0.01
    cam.data.clip_end = z * 2 + 100
    cam.location = ((x0 + x1) / 2, (y0 + y1) / 2, z)
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam
    return cam


def render_exr(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return load_image_np(path, "Non-Color")
