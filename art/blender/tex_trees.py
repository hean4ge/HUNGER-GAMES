"""
tex_trees.py - texture builder for the TreesReal set (LAST STANDING), Blender 5.3 headless.

Builds every image the realistic tree set uses (14 PNGs, all power of two, max 1024):

  bark (tileable in U and V; colour + OpenGL normal), synthesised in numpy from periodic height fields
    TR_BarkConifer_Color/_Normal   thin rounded scales (spruce / fir / young conifer / logs / stumps / snags;
                                   tinted orange it is the plated upper bark of the pine)
    TR_BarkOak_Color/_Normal       deep vertical furrows broken into plates (oak; tinted it is the lower pine
                                   bark and the black base of the birches)
    TR_BarkBirch_Color/_Normal     chalk-white birch bark with black lenticels, peeling strips, dark patches
    TR_Deadwood_Color/_Normal      silver weathered wood with fibres and checking cracks (snags, broken logs)
  card atlases (RGBA colour with alpha cut-outs + OpenGL normal), "texture from geometry": real needle sprigs,
  leaves and twigs are modelled in Blender and rendered top-down with Cycles (albedo, normal, AO passes), then
  un-premultiplied and colour-bled into the transparent pixels (push-pull fill) so mips never halo
    TR_ConiferAtlas_Color/_Normal  spruce frond, fir spray, pine tufts, young sprig, dead twigs, end grain, moss
    TR_BroadleafAtlas_Color/_Normal  oak sprays, birch sprays and a hanging birch strand, moss
  roughness (grayscale, shared, tileable noise around a mean - one for all bark, one for all foliage)
    TR_Rough_Bark, TR_Rough_Foliage

Import as a module (trees_real.py does) or run on its own:
  blender --background --factory-startup --python tex_trees.py -- <texture_out_dir> [bark|atlas|all]
"""
import math
import os
import struct
import sys
import time
import zlib

import numpy as np

N = 1024
TAU = 2.0 * math.pi

# Physical size of one bark tile (studs across the horizontal / U direction). trees_real.py picks the number of
# whole tiles around each trunk from this, which gives ~130-300 px per stud at trunk bases (see barkPxPerStud).
BARK_TILE_STUDS = {"conifer": 5.0, "oak": 6.0, "birch": 4.4, "deadwood": 5.0}

FILES = {
    "BarkConifer": ("TR_BarkConifer_Color.png", "TR_BarkConifer_Normal.png"),
    "BarkOak": ("TR_BarkOak_Color.png", "TR_BarkOak_Normal.png"),
    "BarkBirch": ("TR_BarkBirch_Color.png", "TR_BarkBirch_Normal.png"),
    "Deadwood": ("TR_Deadwood_Color.png", "TR_Deadwood_Normal.png"),
    "ConiferAtlas": ("TR_ConiferAtlas_Color.png", "TR_ConiferAtlas_Normal.png"),
    "BroadleafAtlas": ("TR_BroadleafAtlas_Color.png", "TR_BroadleafAtlas_Normal.png"),
}
ROUGH_FILES = {"bark": "TR_Rough_Bark.png", "foliage": "TR_Rough_Foliage.png"}
# GLB-only copies of the roughness maps packed the glTF way (R = G = roughness, B = metalness = 0). Embedded in the
# GLB instead of the grayscale files, so an importer that reads metalness from the blue channel still gets 0.
ROUGH_GLB_FILES = {"bark": "glb_only/TR_Rough_Bark_MR.png", "foliage": "glb_only/TR_Rough_Foliage_MR.png"}


# ================================================================================================
# PNG writer (8-bit gray / RGB / RGBA), best of the Sub, Up, Average and Paeth filters per image
# ================================================================================================
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


def write_png(path, img):
    """img: float array in 0..1 (H x W or H x W x C), row 0 = BOTTOM (V = 0, Blender/OpenGL order)."""
    arr = np.clip(np.round(np.asarray(img, dtype=np.float64) * 255.0), 0, 255).astype(np.uint8)
    arr = np.flipud(arr)
    h, w = arr.shape[:2]
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    ctype = {1: 0, 3: 2, 4: 6}[ch]
    raw = arr.reshape(h, w * ch)
    best = None
    for ft in (1, 2, 3, 4):
        filt = _png_filter(raw, ft, ch)
        data = np.concatenate([np.full((h, 1), ft, np.uint8), filt], axis=1).tobytes()
        comp = zlib.compress(data, 9)
        if best is None or len(comp) < len(best):
            best = comp

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)))
        f.write(chunk(b"IDAT", best))
        f.write(chunk(b"IEND", b""))
    return path


# ================================================================================================
# Colour helpers
# ================================================================================================
def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def rgb(r, g, b):
    """sRGB 0-255 -> linear float triple (all colour maths happens in linear space)."""
    return srgb_to_lin(np.array([r, g, b], dtype=np.float64) / 255.0)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ================================================================================================
# Periodic (tileable) field synthesis
# ================================================================================================
def _freqs(h, w):
    fy = np.fft.fftfreq(h) * h
    fx = np.fft.fftfreq(w) * w
    return fx[None, :], fy[:, None]


def band_noise(rng, f_lo, f_hi, beta=1.0, sx=1.0, sy=1.0, n=N, m=None):
    """Periodic fractal noise with energy between radial frequencies f_lo..f_hi (cycles per tile).
    sx / sy > 1 squeeze that axis' frequencies, i.e. stretch features along it. Zero mean, unit std."""
    m = m or n
    fx, fy = _freqs(n, m)
    k = np.sqrt((fx * sx) ** 2 + (fy * sy) ** 2)
    k[0, 0] = 1e-6
    win = smoothstep(f_lo * 0.6, f_lo, k) * (1.0 - smoothstep(f_hi, f_hi * 1.5, k))
    amp = win * k ** (-beta)
    amp[0, 0] = 0.0
    phase = rng.uniform(0.0, TAU, (n, m))
    f = np.fft.ifft2(amp * np.exp(1j * phase)).real
    f -= f.mean()
    return f / (f.std() + 1e-12)


def blur(img, sigma):
    """Periodic gaussian blur (sigma in pixels)."""
    h, w = img.shape
    fx, fy = _freqs(h, w)
    g = np.exp(-2.0 * (math.pi ** 2) * (sigma ** 2) * ((fx / w) ** 2 + (fy / h) ** 2))
    return np.fft.ifft2(np.fft.fft2(img) * g).real


def sample(img, x, y):
    """Bilinear periodic lookup, x / y in pixels."""
    h, w = img.shape
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = x - x0
    fy = y - y0
    x0 %= w
    y0 %= h
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy)
            + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


def voronoi(rng, gx, gy, jitter=0.85, warp=None, n=N, reach=(2, 2)):
    """Periodic Voronoi on a gx x gy jittered grid, measured in CELL units (dx / cell width, dy / cell
    height), so a grid of tall cells really gives tall cells. warp = (wx, wy) pixel offsets of the query.
    Returns F1, F2 (cell units), cell id, and the nearest point's offset (dx, dy) in pixels."""
    cw, ch = n / gx, n / gy
    ptx = (np.arange(gx)[None, :] + 0.5 + (rng.random((gy, gx)) - 0.5) * jitter) * cw
    pty = (np.arange(gy)[:, None] + 0.5 + (rng.random((gy, gx)) - 0.5) * jitter) * ch
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    xs += 0.5
    ys += 0.5
    if warp is not None:
        xs = xs + warp[0]
        ys = ys + warp[1]
    ci = np.floor(xs / cw).astype(np.int64)
    cj = np.floor(ys / ch).astype(np.int64)
    rx, ry = reach
    F1 = np.full((n, n), 1e9)
    F2 = np.full((n, n), 1e9)
    ID = np.zeros((n, n), np.int64)
    DX = np.zeros((n, n))
    DY = np.zeros((n, n))
    # distinct neighbour offsets only: on a small grid, offsets that wrap onto the same cell would count the
    # same point twice (F2 == F1) - distances below use the minimum image, so each point is needed once
    offs_x = sorted({d % gx for d in range(-rx, rx + 1)})
    offs_y = sorted({d % gy for d in range(-ry, ry + 1)})
    for dj in offs_y:
        for di in offs_x:
            cx = (ci + di) % gx
            cy = (cj + dj) % gy
            dx = ptx[cy, cx] - xs
            dy = pty[cy, cx] - ys
            dx -= np.round(dx / n) * n
            dy -= np.round(dy / n) * n
            d = np.sqrt((dx / cw) ** 2 + (dy / ch) ** 2)
            closer = d < F1
            F2 = np.where(closer, F1, np.minimum(F2, d))
            ID = np.where(closer, cy * gx + cx, ID)
            DX = np.where(closer, dx, DX)
            DY = np.where(closer, dy, DY)
            F1 = np.where(closer, d, F1)
    return F1, F2, ID, DX, DY


def grad(f):
    gx = (np.roll(f, -1, axis=1) - np.roll(f, 1, axis=1)) * 0.5
    gy = (np.roll(f, -1, axis=0) - np.roll(f, 1, axis=0)) * 0.5
    return gx, gy


def edge_distance(F1, F2, cap=64.0):
    """Approximate distance in pixels to the nearest cell boundary (first order: e / |grad e|), plus the
    boundary orientation: horiz = 1 where the boundary runs horizontally, 0 where it runs vertically."""
    e = F2 - F1
    gx, gy = grad(e)
    g = np.sqrt(gx * gx + gy * gy)
    d = np.minimum(e / np.maximum(g, 1e-6), cap)
    horiz = np.abs(gy) / (np.abs(gx) + np.abs(gy) + 1e-9)
    return d, horiz


def normal_from_height(h, px_studs, depth_scale=1.0):
    """h in studs, px_studs = size of a pixel in studs. Returns tangent-space normal (OpenGL, +Y = +V)
    as an H x W x 3 float array in -1..1."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 / px_studs
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 / px_studs
    nx = -dx * depth_scale
    ny = -dy * depth_scale
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1)


def encode_normal(nrm):
    return np.clip(nrm * 0.5 + 0.5, 0.0, 1.0)


def cavity(h, sigmas=(2.0, 6.0, 18.0), weights=(0.5, 0.3, 0.2)):
    """How far each pixel sits below its neighbourhood (>= 0, in height units), multi-scale."""
    c = np.zeros_like(h)
    for s, wgt in zip(sigmas, weights):
        c += wgt * np.maximum(0.0, blur(h, s) - h)
    return c


def norm01(a):
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo + 1e-12), 0.0, 1.0)


# ================================================================================================
# Bark generators. Each returns (colour linear RGB HxWx3, height in studs HxW, tile size studs)
# ================================================================================================
def bark_conifer(seed=11, n=N):
    """Thin, rounded, overlapping scales that flake at their lower lips (Norway spruce). Light warm grey on
    purpose: every species multiplies its own tint over it (spruce red-brown, fir grey, pine-upper orange)."""
    rng = np.random.default_rng(seed)
    tile = BARK_TILE_STUDS["conifer"]
    wx = band_noise(rng, 2, 6) * 12.0 + band_noise(rng, 8, 24) * 4.0
    wy = band_noise(rng, 2, 6) * 12.0 + band_noise(rng, 8, 24) * 4.0
    gx, gy = 26, 22
    ch = n / gy
    F1, F2, ID, DX, DY = voronoi(rng, gx, gy, 0.95, (wx, wy), n)
    ed, _ = edge_distance(F1, F2)
    nc = gx * gy
    r1, r2, r3, r4 = (rng.random(nc)[ID] for _ in range(4))
    below = np.clip(DY / (ch * 0.55), -1.0, 1.0)          # +1 at the lower lip of the scale
    # scales overlap like shingles: each is tilted so its lower lip stands proud of the scale below
    plate = 0.3 + 0.35 * r1 + (0.38 + 0.3 * r2) * below
    plate += 0.3 * (r3 > 0.5) * smoothstep(0.35, 1.0, below) * smoothstep(7.0, 1.5, ed)   # curling lips
    plate -= 0.1 * (1.0 - smoothstep(0.0, 2.0, ed))
    # clusters of shed scales expose the smoother, redder inner bark
    clus = smoothstep(0.1, 1.3, band_noise(rng, 3, 10, 1.1) + 0.4 * band_noise(rng, 10, 30))
    shed = (r4 < 0.08 + 0.55 * clus).astype(np.float64) * smoothstep(0.0, 3.0, ed)
    fine = band_noise(rng, 60, 260, 0.5) * 0.05 + band_noise(rng, 18, 60, 0.8) * 0.06
    fib = band_noise(rng, 40, 200, 0.6, sx=4.0) * 0.04         # faint horizontal flake fibres
    hgt = plate * (1.0 - 0.75 * shed) - 0.2 * shed + fine + fib + 0.15 * band_noise(rng, 2, 6, 1.0, sy=3.0)
    hgt = blur(hgt, 0.6)
    h_studs = hgt * 0.045

    grey = rgb(148, 136, 124)
    brown = rgb(134, 112, 94)
    fresh = rgb(150, 112, 92)                               # exposed inner bark where scales have shed
    pale = rgb(176, 170, 160)                               # weathered, sun-bleached lips
    lichen = rgb(158, 164, 146)
    col = mix(grey, brown, np.clip(0.55 * r1 + 0.2 * band_noise(rng, 4, 14), 0, 1))
    col = mix(col, pale, smoothstep(0.6, 1.05, plate) * 0.45)
    col = mix(col, fresh, shed * 0.8)
    lich = smoothstep(1.2, 1.9, band_noise(rng, 4, 14, 1.2) + 0.5 * band_noise(rng, 20, 50))
    col = mix(col, lichen, lich * 0.4 * (1.0 - shed))
    cav = cavity(hgt, (1.2, 4.0, 12.0), (0.55, 0.3, 0.15))
    col *= np.clip(1.0 - 2.6 * cav, 0.35, 1.0)[..., None]
    col *= (0.93 + 0.07 * band_noise(rng, 30, 140))[..., None]
    return col, h_studs, tile


def bark_oak(seed=23, n=N):
    """Mature oak: deep V furrows between long, flat-topped, rough ridges that cross cracks cut into blocks."""
    rng = np.random.default_rng(seed)
    tile = BARK_TILE_STUDS["oak"]
    gx, gy = 20, 4
    meander = band_noise(rng, 1.0, 4, 1.2, sx=5.0) * 22.0 + band_noise(rng, 4, 12, 1.0, sx=2.5) * 4.0
    wy = band_noise(rng, 2, 6) * 12.0
    F1, F2, ID, DX, DY = voronoi(rng, gx, gy, 0.95, (meander, wy), n)
    ed, horiz = edge_distance(F1, F2)
    nc = gx * gy
    r1, r2, r3 = (rng.random(nc)[ID] for _ in range(3))
    w = 10.0 + 7.0 * r3
    ridge = smoothstep(0.5, w, ed) ** 0.8                    # V furrow rising to a plateau
    # cross cracks: horizontal-running boundaries of a shorter-celled Voronoi, cut deep into the ridges
    F1b, F2b, IDb, _, _ = voronoi(rng, gx, 15, 0.95, (meander, wy), n)
    edb, horb = edge_distance(F1b, F2b)
    cross = (1.0 - smoothstep(0.5, 4.0, edb)) * smoothstep(0.5, 0.8, horb)
    cross *= (rng.random(gx * 15)[IDb] > 0.3)
    # thin secondary splits running up the ridges
    F1c, F2c, IDc, _, _ = voronoi(rng, 46, 6, 0.95, (meander * 1.3, wy), n)
    edc, horc = edge_distance(F1c, F2c)
    split = (1.0 - smoothstep(0.3, 2.5, edc)) * (1.0 - smoothstep(0.3, 0.6, horc))
    split *= (rng.random(46 * 6)[IDc] > 0.45)
    block = (band_noise(rng, 14, 50, 0.8) * 0.08 + band_noise(rng, 50, 220, 0.5) * 0.05
             + band_noise(rng, 30, 160, 0.6, sy=5.0) * 0.06)
    hgt = (ridge * (0.82 + 0.18 * r1) + block * smoothstep(0.2, 0.7, ridge)
           - 0.6 * cross * ridge - 0.35 * split * ridge)
    hgt = blur(hgt, 0.7)
    h_studs = hgt * 0.11                                     # ~3.5 cm deep furrows

    top = rgb(150, 146, 138)
    side = rgb(108, 98, 88)
    furrow = rgb(54, 44, 37)
    rust = rgb(112, 84, 64)
    lichen_g = rgb(134, 142, 114)
    lichen_w = rgb(184, 184, 172)
    col = mix(furrow, side, smoothstep(0.0, 0.5, hgt))
    col = mix(col, top, smoothstep(0.5, 0.95, hgt))
    col = mix(col, rust, (1.0 - smoothstep(0.1, 0.6, hgt)) * smoothstep(0.3, 0.9, r2) * 0.5)
    t = smoothstep(0.55, 0.9, hgt)
    l1 = smoothstep(1.0, 1.7, band_noise(rng, 5, 16, 1.2) + 0.4 * band_noise(rng, 30, 80))
    l2 = smoothstep(1.4, 2.1, band_noise(rng, 6, 20, 1.2) + 0.5 * band_noise(rng, 30, 90))
    col = mix(col, lichen_g, l1 * t * 0.45)
    col = mix(col, lichen_w, l2 * t * 0.5)
    cav = cavity(hgt, (2.0, 6.0, 16.0))
    col *= np.clip(1.0 - 1.2 * cav, 0.35, 1.0)[..., None]
    col *= (0.92 + 0.08 * band_noise(rng, 25, 120))[..., None]
    return col, h_studs, tile


def _stamp_lenticels(n, rng, count, len_rng, hgt_rng, rows=None, row_share=0.7):
    """Rasterise horizontal, pointed lenticels (periodic). Returns (mask 0..1, raised rim mask)."""
    mask = np.zeros((n, n))
    rim = np.zeros((n, n))
    for _ in range(count):
        cx = rng.uniform(0, n)
        if rows is not None and rng.random() < row_share:
            cy = rows[rng.integers(len(rows))] + rng.normal(0, 4.0)
        else:
            cy = rng.uniform(0, n)
        a = rng.uniform(*len_rng) * 0.5
        b = rng.uniform(*hgt_rng) * 0.5
        tilt = rng.normal(0, 0.025)
        x0, x1 = int(math.floor(cx - a - 2)), int(math.ceil(cx + a + 2))
        y0, y1 = int(math.floor(cy - b - 3)), int(math.ceil(cy + b + 3))
        xs = np.arange(x0, x1)
        ys = np.arange(y0, y1)
        X, Y = np.meshgrid(xs + 0.5, ys + 0.5)
        dx = X - cx
        dy = (Y - cy) - tilt * dx
        prof = np.clip(1.0 - (np.abs(dx) / a) ** 1.8, 0.0, 1.0) ** 0.6 * b
        inside = np.clip((prof - np.abs(dy)) / 0.7 + 0.5, 0.0, 1.0)
        ring = np.clip((prof + 1.4 - np.abs(dy)) / 0.7 + 0.5, 0.0, 1.0) - inside
        dark = rng.uniform(0.7, 1.0)
        yy = (ys % n)[:, None]
        xx = (xs % n)[None, :]
        mask[yy, xx] = np.maximum(mask[yy, xx], inside * dark)
        rim[yy, xx] = np.maximum(rim[yy, xx], ring)
    return mask, rim


def bark_birch(seed=37, n=N):
    """Silver birch: chalk-white papery bark, dark horizontal lenticels in loose rows, a few thin peeling
    strips with a cream-tan underside, grey mottling and a few rough, fissured black patches."""
    rng = np.random.default_rng(seed)
    tile = BARK_TILE_STUDS["birch"]
    rows = list(rng.uniform(0, n, 40))
    lent, rim = _stamp_lenticels(n, rng, 1150, (14, 92), (2.6, 5.4), rows)
    lent2, _ = _stamp_lenticels(n, rng, 1100, (3, 12), (1.2, 2.4))
    # peeling strips: thin horizontal flakes
    pe = band_noise(rng, 4, 16, 1.0, sx=3.5) + 0.3 * band_noise(rng, 16, 44, 1.0, sx=3.5)
    peel = smoothstep(1.75, 1.9, pe)
    lip = smoothstep(1.5, 1.75, pe) - peel
    # rough black patches, cut by short horizontal fissures, with ragged edges
    bp = (band_noise(rng, 2, 7, 1.2) + 0.45 * band_noise(rng, 7, 22, 1.0)
          + 0.25 * band_noise(rng, 22, 80, 0.8))
    black = smoothstep(2.0, 2.25, bp)
    F1, F2, ID, _, _ = voronoi(rng, 30, 34, 0.9, (band_noise(rng, 4, 14) * 6.0, band_noise(rng, 4, 14) * 3.0), n)
    fe, fh = edge_distance(F1, F2)
    fiss = (1.0 - smoothstep(0.4, 2.6, fe)) * smoothstep(0.35, 0.7, fh)
    fibres = band_noise(rng, 20, 160, 0.7, sx=6.0)
    hgt = (0.05 * fibres - 0.4 * lent - 0.15 * lent2 + 0.12 * rim + 0.55 * lip + 0.2 * peel
           + black * (0.35 - 0.8 * fiss + 0.15 * band_noise(rng, 40, 200, 0.5)))
    hgt = blur(hgt, 0.5)
    h_studs = hgt * 0.014

    white = rgb(226, 224, 216)
    cream = rgb(216, 210, 196)
    grey = rgb(172, 172, 164)
    green = rgb(156, 162, 142)
    black_c = rgb(40, 38, 36)
    under = rgb(200, 182, 160)
    mott = band_noise(rng, 3, 12, 1.0) + 0.5 * band_noise(rng, 12, 40, 1.0)
    col = mix(white, cream, smoothstep(-0.5, 1.4, band_noise(rng, 2, 8)) * 0.8)
    col = mix(col, grey, smoothstep(0.6, 1.8, mott) * 0.4)
    col = mix(col, green, smoothstep(1.4, 2.4, mott + 0.6 * band_noise(rng, 20, 60)) * 0.4)
    col = mix(col, under, peel * 0.6)
    col = mix(col, rgb(130, 116, 104), lip * 0.45)
    col = mix(col, black_c, np.clip(lent * 0.95 + lent2 * 0.5, 0, 1))
    rough_dark = mix(rgb(78, 74, 70), black_c, np.clip(fiss + 0.4 * norm01(band_noise(rng, 30, 120)), 0, 1))
    col = mix(col, rough_dark, black * 0.95)
    col *= (0.96 + 0.04 * band_noise(rng, 40, 200))[..., None]
    return col, h_studs, tile


def bark_deadwood(seed=53, n=N):
    """Silver-grey weathered conifer wood without bark: long fibres, long vertical checking cracks,
    water stains and a little pale lichen."""
    rng = np.random.default_rng(seed)
    tile = BARK_TILE_STUDS["deadwood"]
    grain = (band_noise(rng, 24, 140, 0.8, sy=16.0) * 0.55
             + band_noise(rng, 80, 360, 0.6, sy=24.0) * 0.3
             + band_noise(rng, 5, 20, 1.0, sy=8.0) * 0.45)
    wx = band_noise(rng, 2, 6, 1.0, sy=4.0) * 8.0
    F1, F2, ID, _, _ = voronoi(rng, 11, 2, 0.95, (wx, wx * 0.0), n)
    ed, horiz = edge_distance(F1, F2)
    on = smoothstep(-0.3, 0.5, band_noise(rng, 2, 8, 1.0, sy=3.0))
    crack = (1.0 - smoothstep(0.3, 2.4, ed)) * (1.0 - smoothstep(0.35, 0.6, horiz)) * on
    hair = (1.0 - smoothstep(0.0, 0.045, np.abs(band_noise(rng, 6, 30, 1.0, sy=12.0))))
    hair *= smoothstep(0.0, 0.8, band_noise(rng, 3, 10, 1.0, sy=4.0))
    hgt = 0.2 * grain - 1.0 * crack - 0.3 * hair
    hgt = blur(hgt, 0.5)
    h_studs = hgt * 0.03

    silver = rgb(162, 158, 150)
    warm = rgb(142, 128, 110)
    dark = rgb(56, 49, 43)
    stain = rgb(104, 98, 90)
    lichen = rgb(170, 174, 150)
    col = mix(silver, warm, smoothstep(-1.0, 1.4, band_noise(rng, 2, 10, 1.0, sy=3.0)) * 0.55)
    col *= (0.84 + 0.16 * norm01(grain))[..., None]
    col = mix(col, stain, smoothstep(0.6, 1.8, band_noise(rng, 1, 6, 1.0, sy=6.0)) * 0.5)
    col = mix(col, dark, np.clip(crack * 0.95 + hair * 0.45, 0, 1))
    li = smoothstep(2.1, 2.6, band_noise(rng, 5, 16, 1.2) + 0.5 * band_noise(rng, 16, 50))
    col = mix(col, lichen, li * 0.35)
    cav = cavity(hgt, (1.5, 5.0, 12.0))
    col *= np.clip(1.0 - 1.4 * cav, 0.4, 1.0)[..., None]
    return col, h_studs, tile


# (generator, normal depth scale). Oak furrows are deep enough that full depth gave a 45 degree mean normal
# tilt - over-strong for Roblox's Realistic shading (LookDevPlaybook s11: moderate normals) - so it is eased.
BARKS = {
    "BarkConifer": (bark_conifer, 1.0),
    "BarkOak": (bark_oak, 0.72),
    "BarkBirch": (bark_birch, 1.0),
    "Deadwood": (bark_deadwood, 1.0),
}


def roughness_map(kind, seed, n=512):
    rng = np.random.default_rng(seed)
    f = 0.6 * band_noise(rng, 2, 10, 1.0, n=n) + 0.4 * band_noise(rng, 10, 60, 0.8, n=n)
    if kind == "bark":
        return np.clip(0.9 + 0.045 * f, 0.0, 1.0)
    return np.clip(0.72 + 0.06 * f, 0.0, 1.0)


def build_barks(out_dir, only=None, log=print):
    info = {}
    for key, (fn, depth) in BARKS.items():
        if only and key not in only:
            continue
        t0 = time.time()
        col, h, tile = fn()
        nrm = normal_from_height(h, tile / N, depth)
        cpath = write_png(os.path.join(out_dir, FILES[key][0]), lin_to_srgb(col))
        npath = write_png(os.path.join(out_dir, FILES[key][1]), encode_normal(nrm))
        avg = lin_to_srgb(col.reshape(-1, 3).mean(axis=0))
        info[key] = {"tileStuds": tile, "avgRgb": [int(round(v * 255)) for v in avg]}
        log("TEX %s %.1fs avg sRGB %s -> %s, %s" % (key, time.time() - t0, info[key]["avgRgb"],
                                                   os.path.basename(cpath), os.path.basename(npath)))
    return info


def build_roughness(out_dir, log=print):
    for kind, seed in (("bark", 71), ("foliage", 73)):
        r = roughness_map(kind, seed)
        p = write_png(os.path.join(out_dir, ROUGH_FILES[kind]), r)
        mr = np.stack([r, r, np.zeros_like(r)], axis=-1)
        write_png(os.path.join(out_dir, ROUGH_GLB_FILES[kind]), mr)
        log("TEX rough %s -> %s (+ glTF packed copy)" % (kind, os.path.basename(p)))


# ================================================================================================
# Card atlases ("texture from geometry")
# ================================================================================================
# Regions in pixels (x0, y0, x1, y1) with y measured up from the bottom (V = 0). "studs" = how many studs the
# region is wide when used on a card at 1:1 (its height follows the region's aspect). "anchor" = where the twig
# attaches: bottom-centre (sprays grow up the region), top-centre (hanging birch strands grow down it) or the
# centre (painted end grain and moss). trees_real.py maps cards onto these rects.
ATLAS = {
    "ConiferAtlas": {
        "spruce": {"rect": (0, 0, 512, 512), "studs": 3.6, "anchor": "bottom"},
        "fir": {"rect": (512, 0, 1024, 512), "studs": 3.2, "anchor": "bottom"},
        "pine": {"rect": (0, 512, 512, 1024), "studs": 3.0, "anchor": "bottom"},
        "young": {"rect": (512, 512, 768, 768), "studs": 1.5, "anchor": "bottom"},
        "deadtwig": {"rect": (768, 512, 1024, 768), "studs": 2.2, "anchor": "bottom"},
        "endgrain": {"rect": (512, 768, 768, 1024), "studs": 1.0, "anchor": "center"},
        "moss": {"rect": (768, 768, 1024, 1024), "studs": 2.0, "anchor": "center"},
    },
    "BroadleafAtlas": {
        "oakA": {"rect": (0, 0, 512, 512), "studs": 3.4, "anchor": "bottom"},
        "birchA": {"rect": (512, 0, 1024, 512), "studs": 3.0, "anchor": "top"},
        "oakB": {"rect": (0, 512, 512, 1024), "studs": 3.4, "anchor": "bottom"},
        "birchStrand": {"rect": (512, 512, 768, 1024), "studs": 1.6, "anchor": "top"},
        "moss": {"rect": (768, 512, 1024, 768), "studs": 2.0, "anchor": "center"},
        "birchB": {"rect": (768, 768, 1024, 1024), "studs": 1.6, "anchor": "top"},
    },
}
ATLAS_UNITS_PER_PX = 1.0 / 128.0      # render-scene units (the atlas is 8 x 8 units under an ortho camera)


def region_uv(atlas, key):
    x0, y0, x1, y1 = ATLAS[atlas][key]["rect"]
    return (x0 / N, y0 / N, x1 / N, y1 / N)


def region_size_studs(atlas, key):
    r = ATLAS[atlas][key]
    x0, y0, x1, y1 = r["rect"]
    return r["studs"], r["studs"] * (y1 - y0) / (x1 - x0)


class Geo:
    """Tiny mesh accumulator: positions + per-point colour (linear), vein strength, vein count/slope, UV."""

    def __init__(self):
        self.co, self.col, self.uv, self.vein, self.vn, self.vk, self.faces = [], [], [], [], [], [], []

    def v(self, co, col, uv=(0.0, 0.0), vein=0.0, vn=8.0, vk=0.6):
        self.co.append((co[0], co[1], co[2]))
        self.col.append((float(col[0]), float(col[1]), float(col[2])))
        self.uv.append((uv[0], uv[1]))
        self.vein.append(vein)
        self.vn.append(vn)
        self.vk.append(vk)
        return len(self.co) - 1

    def f(self, *idx):
        self.faces.append(tuple(idx))

    def bounds(self):
        a = np.array(self.co)
        return a.min(axis=0), a.max(axis=0)

    def to_object(self, name, scale, offset):
        import bpy
        co = [((x * scale) + offset[0], (y * scale) + offset[1], z * scale) for (x, y, z) in self.co]
        me = bpy.data.meshes.new(name)
        me.from_pydata(co, [], self.faces)
        me.update()
        ca = me.attributes.new("col", "FLOAT_COLOR", "POINT")
        ca.data.foreach_set("color", [c for rgb3 in self.col for c in (rgb3[0], rgb3[1], rgb3[2], 1.0)])
        for nm, vals in (("vein", self.vein), ("vn", self.vn), ("vk", self.vk)):
            a = me.attributes.new(nm, "FLOAT", "POINT")
            a.data.foreach_set("value", vals)
        uvl = me.uv_layers.new(name="UVMap")
        lv = [0] * len(me.loops)
        me.loops.foreach_get("vertex_index", lv)
        uvl.data.foreach_set("uv", [c for i in lv for c in self.uv[i]])
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def _vec():
    from mathutils import Vector
    return Vector


def _frame(T, up=None):
    Vector = _vec()
    up = up or Vector((0.0, 0.0, 1.0))
    S = T.cross(up)
    if S.length < 1e-6:
        S = T.cross(Vector((1.0, 0.0, 0.0)))
    S.normalize()
    U = S.cross(T)
    U.normalize()
    return S, U


def tube(g, pts, radii, col_fn, sides=6):
    n = len(pts)
    rings = []
    T = None
    for i in range(n):
        T = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        S, U = _frame(T)
        c = col_fn(i / max(1, n - 1))
        ring = []
        for k in range(sides):
            a = TAU * k / sides
            ring.append(g.v(pts[i] + (S * math.cos(a) + U * math.sin(a)) * radii[i], c))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            g.f(rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k])
    tip = g.v(pts[-1] + T * radii[-1] * 1.5, col_fn(1.0))
    for k in range(sides):
        g.f(rings[-1][k], rings[-1][(k + 1) % sides], tip)


def needle(g, base, d, length, width, c0, c1):
    S, U = _frame(d)
    tip = base + d * length
    m = base + d * (length * 0.45)
    cm = tuple((a + b) * 0.5 for a, b in zip(c0, c1))
    i0 = g.v(base, c0)
    i1 = g.v(tip, c1)
    il = g.v(m + S * (width * 0.5) - U * (width * 0.3), cm)
    ir = g.v(m - S * (width * 0.5) - U * (width * 0.3), cm)
    g.f(i0, ir, i1)
    g.f(i0, i1, il)


def polyline(start, direction, length, bend_to, bend, steps, rng, wobble=0.0, droop=0.0):
    """Points along a gently curving shoot: the heading turns toward bend_to by 'bend' (radians) overall."""
    Vector = _vec()
    pts = [start.copy()]
    d = direction.normalized()
    target = bend_to.normalized()
    step = length / steps
    p = start.copy()
    for i in range(steps):
        ang = d.angle(target) if d.dot(target) < 0.99999 else 0.0
        if ang > 1e-4:
            axis = d.cross(target)
            if axis.length > 1e-6:
                from mathutils import Matrix
                rot = Matrix.Rotation(min(ang, bend / steps), 3, axis.normalized())
                d = rot @ d
        if wobble:
            d = (d + Vector((rng.normal(0, wobble), rng.normal(0, wobble), 0.0))).normalized()
        p = p + d * step + Vector((0.0, 0.0, -droop * step))
        pts.append(p.copy())
    return pts


def _arc_samples(pts, spacing, rng):
    """Positions/tangents/fractions every ~spacing along a polyline."""
    seg = [(pts[i + 1] - pts[i]) for i in range(len(pts) - 1)]
    lens = [s.length for s in seg]
    total = sum(lens)
    out = []
    s = spacing * rng.uniform(0.2, 1.0)
    while s < total:
        acc = 0.0
        for i, ln in enumerate(lens):
            if acc + ln >= s:
                f = (s - acc) / max(ln, 1e-9)
                out.append((pts[i] + seg[i] * f, seg[i].normalized(), s / total))
                break
            acc += ln
        s += spacing * rng.uniform(0.7, 1.3)
    return out, total


def needles_on(g, pts, rng, spacing, nlen, nwid, theta, az, old, new, fresh=0.25, shorten_tip=0.35, side=0.75):
    """Needles spiralling round a shoot. theta = (min, max) degrees from the shoot axis (forward), az = max
    azimuth (deg) away from straight up (needles pointing down are hidden from the top view anyway).
    side = share of needles that point sideways (the ones that give a top-view bottlebrush its width;
    needles pointing at the camera foreshorten to dots)."""
    Vector = _vec()
    for p, T, frac in _arc_samples(pts, spacing, rng)[0]:
        S, U = _frame(T)
        th = math.radians(rng.uniform(*theta))
        if rng.random() < side:
            ph = math.radians(rng.uniform(55.0, min(az, 112.0))) * (1.0 if rng.random() < 0.5 else -1.0)
        else:
            ph = math.radians(rng.uniform(-50.0, 50.0))
        d = (T * math.cos(th) + (U * math.cos(ph) + S * math.sin(ph)) * math.sin(th)).normalized()
        ln = nlen * rng.uniform(0.8, 1.15) * (1.0 - shorten_tip * smoothstep(0.85, 1.0, frac))
        young = frac > 1.0 - fresh
        c = new if young else old
        jit = rng.uniform(0.85, 1.15)
        c0 = tuple(v * jit * 0.8 for v in c)
        c1 = tuple(min(1.0, v * jit * 1.15) for v in c)
        needle(g, p, d, ln, nwid, c0, c1)


# ---------------------------------------------------------------- conifer sprigs
def spruce_frond(g, rng, W, H, old, new, twig, fresh=0.22, dens=1.0, nlen=0.14, n_sec=22):
    """Norway spruce branch end seen from above: a dense bottlebrush of short needles all round every shoot,
    alternate side shoots with tertiaries, lighter new growth at the tips; the shoots barely show."""
    Vector = _vec()
    L = H * 0.93
    ph = rng.uniform(0, TAU)
    axis = [Vector((0.07 * math.sin(2.2 * t + ph) * t * W / 3.6, t * L, 0.03 * math.sin(3.0 * t)))
            for t in np.linspace(0.0, 1.0, 14)]
    tw = lambda t: twig
    nw = 0.019 * (W / 3.6) ** 0.5
    tube(g, axis, [0.03 * (1 - t) + 0.01 for t in np.linspace(0, 1, 14)], tw, 5)
    needles_on(g, axis, rng, 0.0075 / dens, nlen, nw, (48, 70), 115, old, new, fresh)
    for k in range(n_sec):
        t = 0.04 + 0.9 * (k + rng.uniform(-0.25, 0.25)) / n_sec
        side = 1.0 if k % 2 == 0 else -1.0
        env = math.sin(math.pi * min(1.0, t * 1.2 + 0.05)) ** 0.7 * (1.08 - 0.55 * t)
        Ls = min(W * 0.4, W * 0.45 * env * rng.uniform(0.85, 1.08))
        if Ls < 0.12:
            continue
        ang = math.radians(62 - 24 * t + rng.uniform(-6, 6))
        i = min(12, int(t * 13))
        start = axis[i].lerp(axis[i + 1], min(1.0, t * 13 - i))
        d0 = Vector((side * math.sin(ang), math.cos(ang), 0.0))
        pts = polyline(start, d0, Ls, Vector((0, 1, 0)), math.radians(rng.uniform(12, 26)), 6, rng, 0.04)
        tube(g, pts, [0.016 * (1 - s) + 0.006 for s in np.linspace(0, 1, len(pts))], tw, 4)
        needles_on(g, pts, rng, 0.008 / dens, nlen * 0.95, nw, (46, 68), 115, old, new, fresh)
        if Ls > 0.45:
            nt = int(Ls / 0.24)
            for j in range(nt):
                s = 0.18 + 0.68 * (j + rng.uniform(-0.2, 0.2)) / max(1, nt)
                idx = min(len(pts) - 2, int(s * (len(pts) - 1)))
                p = pts[idx]
                T = (pts[idx + 1] - pts[idx]).normalized()
                side2 = 1.0 if j % 2 == 0 else -1.0
                a2 = math.radians(rng.uniform(38, 55)) * side2
                d2 = Vector((T.x * math.cos(a2) - T.y * math.sin(a2), T.x * math.sin(a2) + T.y * math.cos(a2), 0))
                L2 = Ls * rng.uniform(0.25, 0.4) * (1.0 - 0.45 * s)
                p2 = polyline(p, d2, L2, T, math.radians(15), 3, rng, 0.03)
                tube(g, p2, [0.008, 0.007, 0.006, 0.005], tw, 3)
                needles_on(g, p2, rng, 0.009 / dens, nlen * 0.85, nw * 0.95, (46, 68), 115, old, new, fresh * 1.5)


def spruce_branch(g, rng, W, H, old, new, twig, fresh=0.12, nlen=0.15):
    """Mature Norway spruce branch end seen from above (the card every SpruceA/B tier uses). Unlike the even,
    oval frond (which read as one big pinnate leaf), the side shoots are longest at the base and shorten toward
    the tip, vary in length and angle, sometimes fork or are missing, and carry short tertiaries, so the
    outline is a ragged, tapering triangle of fuzzy bottlebrushes. The thin, dark main axis hides under its
    needles, and only the outer few percent of each shoot is lighter new growth."""
    Vector = _vec()
    L = H * 0.94
    ph = rng.uniform(0, TAU)
    axis = [Vector((0.05 * math.sin(2.6 * t + ph) * t * W / 3.6, t * L, 0.0)) for t in np.linspace(0.0, 1.0, 16)]
    tw = lambda t: twig
    nw = 0.02 * (W / 3.6) ** 0.5
    tube(g, axis, [0.022 * (1 - t) + 0.008 for t in np.linspace(0, 1, 16)], tw, 5)
    needles_on(g, axis, rng, 0.0068, nlen, nw, (40, 72), 130, old, new, fresh * 0.8)
    n_sec = 26
    for k in range(n_sec):
        t = 0.03 + 0.92 * (k + rng.uniform(-0.3, 0.3)) / n_sec
        if rng.uniform() < 0.12 and 0.15 < t < 0.85:
            continue                                   # a missing / broken side shoot leaves a gap
        side = 1.0 if (k + (1 if rng.uniform() < 0.15 else 0)) % 2 == 0 else -1.0
        env = smoothstep(0.0, 0.1, t) * (1.04 - 0.86 * t) ** 0.9
        Ls = W * 0.47 * env * rng.uniform(0.6, 1.12)
        if Ls < 0.1:
            continue
        ang = math.radians(rng.uniform(46, 76) - 22 * t)
        i = min(14, int(t * 15))
        start = axis[i].lerp(axis[i + 1], min(1.0, t * 15 - i))
        d0 = Vector((side * math.sin(ang), math.cos(ang), 0.0))
        pts = polyline(start, d0, Ls, Vector((side * rng.uniform(-0.2, 0.3), 1.0, 0.0)),
                       math.radians(rng.uniform(5, 32)), 7, rng, 0.06)
        tube(g, pts, [0.012 * (1 - s) + 0.005 for s in np.linspace(0, 1, len(pts))], tw, 4)
        needles_on(g, pts, rng, 0.0072, nlen * rng.uniform(0.88, 1.02), nw, (40, 72), 130, old, new, fresh)
        if Ls > 0.32:
            nt = int(Ls / 0.17)
            for j in range(nt):
                if rng.uniform() < 0.22:
                    continue
                s = 0.15 + 0.75 * (j + rng.uniform(-0.25, 0.25)) / max(1, nt)
                idx = min(len(pts) - 2, int(s * (len(pts) - 1)))
                p = pts[idx]
                T = (pts[idx + 1] - pts[idx]).normalized()
                side2 = 1.0 if (j + k) % 2 == 0 else -1.0
                a2 = math.radians(rng.uniform(32, 64)) * side2
                d2 = Vector((T.x * math.cos(a2) - T.y * math.sin(a2), T.x * math.sin(a2) + T.y * math.cos(a2), 0))
                L2 = Ls * rng.uniform(0.18, 0.42) * (1.0 - 0.4 * s)
                p2 = polyline(p, d2, L2, T, math.radians(rng.uniform(5, 20)), 3, rng, 0.05)
                tube(g, p2, [0.006, 0.005, 0.0045, 0.004], tw, 3)
                needles_on(g, p2, rng, 0.008, nlen * 0.85, nw * 0.95, (40, 72), 130, old, new, fresh * 1.4)


def fir_spray(g, rng, W, H, old, new, twig, under):
    """Silver fir: flat, two-ranked needles on opposite laterals (a flat, fern-like spray)."""
    Vector = _vec()
    L = H * 0.92
    axis = [Vector((0.05 * math.sin(2.0 * t) * t, t * L, 0.0)) for t in np.linspace(0, 1, 12)]
    tw = lambda t: twig

    def flat_needles(pts, spacing, ln0, scale=1.0):
        for p, T, frac in _arc_samples(pts, spacing, rng)[0]:
            S, U = _frame(T)
            for side in (-1.0, 1.0):
                # lower rank: sideways, flat; a few upper needles lie over the shoot in a shallow V
                for rank in (0, 1):
                    if rank == 1 and rng.random() < 0.45:
                        continue
                    th = math.radians(rng.uniform(70, 88) if rank == 0 else rng.uniform(35, 55))
                    ph = math.radians(side * (rng.uniform(78, 98) if rank == 0 else rng.uniform(25, 45)))
                    d = (T * math.cos(th) + (U * math.cos(ph) + S * math.sin(ph)) * math.sin(th)).normalized()
                    ln = ln0 * scale * rng.uniform(0.85, 1.12) * (0.75 if rank else 1.0)
                    ln *= 1.0 - 0.35 * smoothstep(0.85, 1.0, frac)
                    c = new if frac > 0.8 else old
                    if rank == 0 and rng.random() < 0.25:
                        c = tuple(a * 0.55 + b * 0.45 for a, b in zip(c, under))   # silver underside shows
                    j = rng.uniform(0.85, 1.12)
                    needle(g, p, d, ln, 0.022, tuple(v * j * 0.85 for v in c), tuple(min(1, v * j * 1.1) for v in c))

    tube(g, axis, [0.04 * (1 - t) + 0.012 for t in np.linspace(0, 1, 12)], tw, 5)
    flat_needles(axis, 0.016, 0.11)
    n_pairs = 8
    for k in range(n_pairs):
        t = 0.06 + 0.84 * (k + rng.uniform(-0.15, 0.15)) / n_pairs
        env = (1.0 - t) ** 0.8 * 1.05
        i = min(10, int(t * 11))
        start = axis[i].lerp(axis[i + 1], t * 11 - i)
        for side in (-1.0, 1.0):
            Ls = min(W * 0.42, W * 0.5 * env * rng.uniform(0.85, 1.05))
            if Ls < 0.15:
                continue
            ang = math.radians(rng.uniform(55, 66))
            d0 = Vector((side * math.sin(ang), math.cos(ang), 0.0))
            pts = polyline(start, d0, Ls, Vector((0, 1, 0)), math.radians(rng.uniform(8, 16)), 5, rng, 0.02)
            tube(g, pts, [0.02 * (1 - s) + 0.008 for s in np.linspace(0, 1, len(pts))], tw, 4)
            flat_needles(pts, 0.018, 0.1)
            if Ls > 0.55:
                for j in range(int(Ls / 0.32)):
                    s = 0.25 + 0.6 * j / max(1, int(Ls / 0.32))
                    idx = min(len(pts) - 2, int(s * (len(pts) - 1)))
                    p = pts[idx]
                    T = (pts[idx + 1] - pts[idx]).normalized()
                    for sd in (-1.0, 1.0):
                        a2 = math.radians(rng.uniform(50, 62)) * sd
                        d2 = Vector((T.x * math.cos(a2) - T.y * math.sin(a2),
                                     T.x * math.sin(a2) + T.y * math.cos(a2), 0))
                        L2 = Ls * rng.uniform(0.2, 0.3) * (1.0 - 0.4 * s)
                        p2 = polyline(p, d2, L2, T, math.radians(10), 3, rng)
                        tube(g, p2, [0.01, 0.008, 0.006, 0.005], tw, 3)
                        flat_needles(p2, 0.02, 0.085)


def pine_tuft(g, rng, W, H, old, new, twig, bud):
    """Scots pine branch end: a whorl of shoots, needles in pairs on their outer two thirds (brushes)."""
    Vector = _vec()
    base = [Vector((0.0, 0.0, 0.0)), Vector((0.02, 0.25, 0.0)), Vector((0.0, 0.48, 0.0))]
    tw = lambda t: twig
    tube(g, base, [0.05, 0.047, 0.044], tw, 6)
    whorl = base[-1]
    shoots = [(-70, 0.9), (-44, 1.08), (-18, 1.3), (6, 1.45), (30, 1.22), (55, 1.02), (76, 0.85)]
    for ang_d, lf in shoots:
        ang = math.radians(ang_d + rng.uniform(-5, 5))
        Ls = 1.0 * lf * rng.uniform(0.92, 1.05)
        d0 = Vector((math.sin(ang), math.cos(ang), 0.0))
        pts = polyline(whorl, d0, Ls, Vector((0, 1, 0)), math.radians(rng.uniform(6, 16)), 6, rng, 0.03)
        tube(g, pts, [0.03 * (1 - s) + 0.016 for s in np.linspace(0, 1, len(pts))], tw, 5)
        for p, T, frac in _arc_samples(pts, 0.011, rng)[0]:
            if frac < 0.16:
                continue
            S, U = _frame(T)
            ph0 = rng.uniform(-math.pi, math.pi)
            for k in range(2):                     # a fascicle of two needles
                th = math.radians(rng.uniform(26, 52))
                if rng.random() < 0.7:
                    ph = math.radians(rng.uniform(45, 150)) * (1.0 if rng.random() < 0.5 else -1.0)
                else:
                    ph = ph0 + k * math.pi * rng.uniform(0.7, 1.0)
                    ph = (ph + math.pi) % TAU - math.pi
                    if abs(ph) > math.radians(160):
                        ph = math.radians(160) * (1 if ph > 0 else -1)
                d = (T * math.cos(th) + (U * math.cos(ph) + S * math.sin(ph)) * math.sin(th)).normalized()
                ln = rng.uniform(0.3, 0.4) * (1.0 - 0.45 * smoothstep(0.86, 1.0, frac))
                c = new if frac > 0.84 else old
                j = rng.uniform(0.85, 1.12)
                needle(g, p, d, ln, 0.021, tuple(v * j * 0.8 for v in c), tuple(min(1, v * j * 1.12) for v in c))
        tip = pts[-1]
        T = (pts[-1] - pts[-2]).normalized()
        tube(g, [tip, tip + T * 0.05, tip + T * 0.09], [0.032, 0.027, 0.011], lambda t: bud, 5)


def dead_twigs(g, rng, W, H, wood, wood2, needle_c, lichen):
    Vector = _vec()

    def branch(p, d, L, r, depth):
        pts = polyline(p, d, L, d + Vector((rng.normal(0, 0.4), 0.3, 0)), math.radians(rng.uniform(5, 25)),
                       5, rng, 0.06)
        c = wood if rng.random() < 0.6 else wood2
        tube(g, pts, [r * (1 - 0.6 * s) for s in np.linspace(0, 1, len(pts))], lambda t: c, 4 if r > 0.012 else 3)
        if depth >= 4 or L < 0.14:
            for p2, T, frac in _arc_samples(pts, 0.04, rng)[0]:
                if rng.random() < 0.3:
                    S, U = _frame(T)
                    th = math.radians(rng.uniform(40, 80))
                    ph = math.radians(rng.uniform(-120, 120))
                    dd = (T * math.cos(th) + (U * math.cos(ph) + S * math.sin(ph)) * math.sin(th)).normalized()
                    needle(g, p2, dd, rng.uniform(0.06, 0.09), 0.012, needle_c, tuple(v * 1.15 for v in needle_c))
            return
        nk = rng.integers(3, 6) if depth < 3 else rng.integers(2, 4)
        for k in range(nk):
            s = 0.18 + 0.72 * (k + rng.uniform(0, 0.6)) / nk
            idx = min(len(pts) - 2, int(s * (len(pts) - 1)))
            T = (pts[idx + 1] - pts[idx]).normalized()
            side = 1.0 if (k + depth) % 2 == 0 else -1.0
            a = math.radians(rng.uniform(32, 62)) * side
            d2 = Vector((T.x * math.cos(a) - T.y * math.sin(a), T.x * math.sin(a) + T.y * math.cos(a), 0))
            branch(pts[idx], d2, L * rng.uniform(0.4, 0.58) * (1.0 - 0.35 * s), r * 0.6, depth + 1)
        # beard lichen hanging in short wavy strands
        if depth == 1 and rng.random() < 0.8:
            for _ in range(rng.integers(2, 5)):
                p0 = pts[rng.integers(1, len(pts) - 1)]
                q = [p0]
                dd = Vector((rng.normal(0, 0.5), rng.uniform(-1.0, -0.4), 0)).normalized()
                for _s in range(6):
                    dd = (dd + Vector((rng.normal(0, 0.5), rng.normal(0, 0.3), 0))).normalized()
                    q.append(q[-1] + dd * 0.05)
                tube(g, q, [0.006] * len(q), lambda t: lichen, 3)

    branch(Vector((0, 0, 0)), Vector((0.05, 1, 0)), H * 0.86, 0.03, 1)


# ---------------------------------------------------------------- leaves
def leaf(g, base, d, up, length, halfw, M, fold, curl, twist, col, vn, vk, vein=1.0, side_bias=0.0):
    """A leaf blade: midrib from base along d, half-width halfw(t, side) * length, V-fold, curl and twist."""
    from mathutils import Matrix
    S, Nn = _frame(d, up)
    if twist:
        R = Matrix.Rotation(twist, 3, d)
        S = R @ S
        Nn = R @ Nn
    mid, left, right = [], [], []
    for i in range(M + 1):
        t = i / M
        p = base + d * (t * length) + Nn * (-curl * t * t * length)
        wl = halfw(t, 1.0) * length
        wr = halfw(t, -1.0) * length
        cm = tuple(c * (0.95 + 0.08 * t) for c in col)
        ce = tuple(c * 1.06 for c in col)
        mid.append(g.v(p + Nn * 0.004, cm, (0.0, t), vein, vn, vk))
        left.append(g.v(p + S * wl - Nn * (fold * wl), ce, (1.0, t), vein, vn, vk))
        right.append(g.v(p - S * wr - Nn * (fold * wr), ce, (-1.0, t), vein, vn, vk))
    # wound so the upper surface (+Nn) is the front face: the albedo pass paints back faces as leaf undersides
    for i in range(M):
        g.f(mid[i], left[i], left[i + 1], mid[i + 1])
        g.f(mid[i], mid[i + 1], right[i + 1], right[i])


def oak_halfw(lobes, depth, ph_l, ph_r):
    def fn(t, side):
        env = 0.34 * math.sin(math.pi * min(1.0, t) ** 0.9) ** 0.75 * (0.55 + 0.6 * t)
        ph = ph_l if side > 0 else ph_r
        s = (t * lobes + ph) % 1.0
        lobe = (1.0 - depth) + depth * math.sin(math.pi * s) ** 0.55
        aur = 0.07 * math.exp(-((t - 0.05) / 0.035) ** 2)
        tipround = 1.0 - smoothstep(0.93, 1.0, t)
        return max(0.0, (env * lobe + aur) * tipround)
    return fn


def birch_halfw(teeth, ph):
    def fn(t, side):
        env = 0.95 * (t ** 0.42) * ((1.0 - t) ** 1.25)
        s = (t * teeth + ph + (0.33 if side < 0 else 0.0)) % 1.0
        s2 = (t * teeth * 3.0 + ph) % 1.0
        tooth = 0.07 * (1.0 - s) + 0.025 * (1.0 - s2)
        fade = smoothstep(0.08, 0.25, t) * (1.0 - smoothstep(0.86, 0.97, t))
        return max(0.0, env * (1.0 + tooth * fade))
    return fn


def _vary(col, rng, amt=0.12):
    j = rng.uniform(1 - amt, 1 + amt)
    h = rng.uniform(-amt * 0.5, amt * 0.5)
    return (col[0] * j * (1 + h), col[1] * j, col[2] * j * (1 - h))


def _poisson_in_ellipse(rng, cx, cy, ax, ay, k, min_d, tries=4000):
    pts = []
    for _ in range(tries):
        if len(pts) >= k:
            break
        a = rng.uniform(0, TAU)
        r = math.sqrt(rng.uniform(0, 1))
        p = (cx + math.cos(a) * r * ax, cy + math.sin(a) * r * ay)
        if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 >= min_d * min_d for q in pts):
            pts.append(p)
    return pts


def _nearest_on(pts, target, max_y=None, min_frac=0.0):
    """Closest polyline vertex to target (optionally only below max_y), with its index."""
    best, bi = None, 1
    n = len(pts)
    for i in range(max(1, int(min_frac * (n - 1))), n - 1):
        if max_y is not None and pts[i].y > max_y:
            continue
        d = (pts[i] - target).length
        if best is None or d < best:
            best, bi = d, i
    return bi


def oak_spray(g, rng, W, H, leaf_cols, twig, variant=0):
    """Pedunculate oak shoot from above: a zig-zag stem feeding side shoots that end in rosettes of lobed
    leaves (oak leaves crowd at the shoot tips), with single leaves along the shoots. Fills the region."""
    Vector = _vec()
    up = Vector((0, 0, 1))
    tw = lambda t: twig
    n = 7
    stem = [Vector((0, 0, 0))]
    for i in range(n):
        stem.append(stem[-1] + Vector(((0.09 if i % 2 else -0.09) + rng.normal(0, 0.03), H * 0.66 / n, 0)))
    tube(g, stem, [0.042 - 0.0035 * i for i in range(len(stem))], tw, 5)
    centres = _poisson_in_ellipse(rng, 0.0, H * 0.56, W * 0.31, H * 0.3, 9 if variant == 0 else 11,
                                  0.62 if variant == 0 else 0.55)
    tips = [(stem[-1], (stem[-1] - stem[-2]).normalized())]
    for (cx, cy) in centres:
        c = Vector((cx, cy, 0.0))
        if (c - stem[-1]).length < 0.35:
            continue
        i = _nearest_on(stem, c, max_y=cy - 0.15, min_frac=0.15)
        start = stem[i]
        d0 = (c - start)
        L2 = d0.length
        d0.normalize()
        bend_to = (d0 + Vector((0, 0.6, 0))).normalized()
        p2 = polyline(start, (d0 + Vector((rng.normal(0, 0.2), -0.1, 0))).normalized(), L2, bend_to,
                      math.radians(18), 4, rng, 0.04)
        tube(g, p2, [0.022, 0.019, 0.017, 0.015, 0.013], tw, 4)
        tips.append((p2[-1], (p2[-1] - p2[-2]).normalized()))
        for p, T2, frac in _arc_samples(p2, 0.17, rng)[0]:
            if frac > 0.7 or frac < 0.15:
                continue
            sd = 1.0 if rng.random() < 0.5 else -1.0
            a3 = math.radians(rng.uniform(40, 80)) * sd
            dl = Vector((T2.x * math.cos(a3) - T2.y * math.sin(a3), T2.x * math.sin(a3) + T2.y * math.cos(a3),
                         rng.uniform(-0.1, 0.25))).normalized()
            _oak_leaf(g, rng, p, dl, up, leaf_cols, rng.uniform(0.3, 0.4))
    for p, s, frac in _arc_samples(stem, 0.2, rng)[0]:
        if frac < 0.2 or frac > 0.9:
            continue
        sd = 1.0 if rng.random() < 0.5 else -1.0
        a3 = math.radians(rng.uniform(45, 85)) * sd
        dl = Vector((s.x * math.cos(a3) - s.y * math.sin(a3), s.x * math.sin(a3) + s.y * math.cos(a3), 0.1))
        _oak_leaf(g, rng, p, dl.normalized(), up, leaf_cols, rng.uniform(0.32, 0.42))
    for p, d in tips:                        # rosettes of leaves at the shoot tips
        nl = rng.integers(6, 9)
        a0 = math.atan2(d.y, d.x)
        for j in range(nl):
            a = a0 + math.radians(-160 + 320 * (j + rng.uniform(0.1, 0.9)) / nl)
            dl = Vector((math.cos(a), math.sin(a), rng.uniform(-0.05, 0.35))).normalized()
            _oak_leaf(g, rng, p + dl * 0.02, dl, up, leaf_cols, rng.uniform(0.36, 0.48))


def _oak_leaf(g, rng, p, d, up, cols, length):
    col = _vary(cols[rng.integers(len(cols))], rng, 0.1)
    q = p + d * 0.035                        # short petiole
    tube(g, [p, q], [0.008, 0.007], lambda t: (0.09, 0.08, 0.03), 3)
    hw = oak_halfw(rng.uniform(4.2, 5.4), rng.uniform(0.42, 0.58), rng.uniform(0, 1), rng.uniform(0, 1))
    leaf(g, q, d, up, length, hw, 44, rng.uniform(0.08, 0.2), rng.uniform(-0.1, 0.14),
         math.radians(rng.uniform(-28, 28) + (180.0 if rng.random() < 0.08 else 0.0)), col, rng.uniform(5.0, 6.5), rng.uniform(0.45, 0.7))


def birch_spray(g, rng, W, H, leaf_cols, twig, strand=False):
    """Hanging birch twigs (grow DOWN from the origin): a pendulous main twig with side shoots fanning out
    and down, alternate serrated leaves every ~0.1 stud on all of them."""
    Vector = _vec()
    up = Vector((0, 0, 1))
    tw = lambda t: twig
    L = H * (0.8 if strand else 0.9)
    main = polyline(Vector((0, 0, 0)), Vector((rng.normal(0, 0.12), -1, 0)), L, Vector((0, -1, 0)),
                    math.radians(10), 12, rng, 0.04)
    tube(g, main, [0.016 * (1 - s) + 0.006 for s in np.linspace(0, 1, len(main))], tw, 4)
    shoots = [(main, 1.0)]
    nside = 5 if strand else 10
    reach = W * (0.3 if strand else 0.36)
    for k in range(nside):
        s = 0.06 + 0.8 * (k + rng.uniform(-0.2, 0.2)) / nside
        idx = min(len(main) - 2, int(s * (len(main) - 1)))
        side = 1.0 if k % 2 == 0 else -1.0
        a = math.radians(rng.uniform(32, 62)) * side
        T = (main[idx + 1] - main[idx]).normalized()
        d2 = Vector((T.x * math.cos(a) - T.y * math.sin(a), T.x * math.sin(a) + T.y * math.cos(a), 0))
        L2 = reach * rng.uniform(0.75, 1.15) * (1.0 - 0.35 * s) / max(0.4, abs(math.sin(a)))
        L2 = min(L2, (H * 0.92 - abs(main[idx].y)) * 0.95)
        if L2 < 0.2:
            continue
        p2 = polyline(main[idx], d2, L2, Vector((0, -1, 0)), math.radians(rng.uniform(25, 45)), 6, rng, 0.05)
        tube(g, p2, [0.009, 0.008, 0.007, 0.006, 0.005, 0.0045, 0.004], tw, 3)
        shoots.append((p2, 0.9))
        if not strand and L2 > 0.7 and rng.random() < 0.7:
            j = len(p2) // 2
            T3 = (p2[j + 1] - p2[j]).normalized()
            a3 = math.radians(rng.uniform(30, 50)) * -side
            d3 = Vector((T3.x * math.cos(a3) - T3.y * math.sin(a3), T3.x * math.sin(a3) + T3.y * math.cos(a3), 0))
            p3 = polyline(p2[j], d3, L2 * 0.45, Vector((0, -1, 0)), math.radians(30), 4, rng, 0.05)
            tube(g, p3, [0.006, 0.005, 0.0045, 0.004, 0.0035], tw, 3)
            shoots.append((p3, 0.85))
    for pts, lscale in shoots:
        k = 0
        for p, T, frac in _arc_samples(pts, 0.1, rng)[0]:
            k += 1
            sd = 1.0 if k % 2 == 0 else -1.0
            a = math.radians(rng.uniform(35, 80)) * sd
            dl = Vector((T.x * math.cos(a) - T.y * math.sin(a), T.x * math.sin(a) + T.y * math.cos(a),
                         rng.uniform(-0.3, 0.3)))
            dl = (dl + Vector((0, -0.4, 0))).normalized()          # leaves hang
            col = _vary(leaf_cols[rng.integers(len(leaf_cols))], rng, 0.1)
            q = p + dl * 0.05
            tube(g, [p, q], [0.005, 0.004], lambda t: (0.12, 0.09, 0.04), 3)
            hw = birch_halfw(rng.uniform(10, 14), rng.uniform(0, 1))
            leaf(g, q, dl, up, rng.uniform(0.2, 0.27) * lscale * (0.8 + 0.2 * (1 - frac)), hw, 48,
                 rng.uniform(0.04, 0.12), rng.uniform(-0.12, 0.12), math.radians(rng.uniform(-50, 50) + (180.0 if rng.random() < 0.14 else 0.0)),
                 col, rng.uniform(6.0, 8.0), rng.uniform(0.35, 0.55))


# ---------------------------------------------------------------- painted regions
def paint_endgrain(size, rng):
    """Sawn end grain: pith, heartwood/sapwood, latewood rings, radial checks, saw marks, bark rim.
    Returns (rgb linear, alpha, height studs)."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    x = (x + 0.5) / size * 2 - 1
    y = (y + 0.5) / size * 2 - 1
    r = np.sqrt(x * x + y * y) / 0.94
    th = np.arctan2(y, x)
    n1 = band_noise(rng, 2, 6, 1.0, n=size)
    n2 = band_noise(rng, 6, 20, 1.0, n=size)
    rr = r * (1.0 + 0.035 * n1) + 0.008 * n2
    rings = rr * 24.0 + 0.6 * rr ** 2
    fr = rings % 1.0
    late = smoothstep(0.62, 0.86, fr) * (1.0 - smoothstep(0.9, 1.0, fr))
    heart = 1.0 - smoothstep(0.52, 0.66, rr)
    col = mix(rgb(204, 168, 120), rgb(170, 122, 80), heart)
    col = mix(col, col * 0.62, late * 0.85)
    checks = np.zeros_like(r)
    for a in rng.uniform(-math.pi, math.pi, 4):
        dth = np.angle(np.exp(1j * (th - a)))
        w = 0.004 + 0.03 * np.clip(0.9 - r, 0, 1)
        on = smoothstep(0.08, 0.2, r) * (1.0 - smoothstep(rng.uniform(0.55, 0.85), 0.92, r))
        checks = np.maximum(checks, (1.0 - smoothstep(0.0, w, np.abs(dth) * np.maximum(r, 0.05))) * on)
    pith = 1.0 - smoothstep(0.015, 0.04, r)
    saw = np.sin((x * 0.94 + y * 0.34 + 0.15 * (x * x)) * 95.0) * 0.5 + 0.5
    bark = smoothstep(0.92, 0.95, r)
    cambium = smoothstep(0.89, 0.915, r) * (1.0 - bark)
    col = mix(col, rgb(52, 36, 26), np.clip(checks + pith, 0, 1))
    col = mix(col, rgb(120, 82, 52), cambium * 0.8)
    barkc = mix(rgb(70, 54, 42), rgb(110, 92, 76), smoothstep(-1, 1.5, band_noise(rng, 20, 80, n=size)))
    col = mix(col, barkc, bark)
    col = mix(col, rgb(150, 142, 130), 0.18 * (1.0 - bark))     # light weathering
    col *= (0.94 + 0.06 * saw)[..., None]
    hgt = (0.004 * late - 0.03 * checks - 0.02 * pith + 0.002 * saw
           + bark * (0.03 + 0.012 * band_noise(rng, 20, 90, n=size)))
    alpha = 1.0 - smoothstep(0.985, 1.0, r * 0.94 / 0.97)
    return col, alpha, hgt


def paint_moss(size, rng):
    """Moss carpet for the decals on trunk bases, snags, logs and stumps (feather and cushion mosses): a fine,
    velvety mat of tiny fronds over low cushions - olive green, yellow-green tips, a few brown dead patches -
    with a hair-fine ragged edge. Kept fine-grained and low-contrast so it never reads as leaves up close
    (the earlier version had leaf-sized, dark-outlined lumps and read as clover / ivy)."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    x = (x + 0.5) / size * 2 - 1
    y = (y + 0.5) / size * 2 - 1
    r = np.sqrt(x * x + y * y)
    shape = r + 0.16 * band_noise(rng, 2, 5, 1.0, n=size) + 0.05 * band_noise(rng, 5, 16, 1.0, n=size)
    fringe = 0.035 * band_noise(rng, 40, 128, 0.3, n=size)          # frond tips break the edge up
    alpha = 1.0 - smoothstep(0.74, 0.79, shape + fringe)
    cush = band_noise(rng, 3, 9, 1.0, n=size)                        # low cushions, 0.2-0.7 stud
    mid = band_noise(rng, 16, 40, 0.8, n=size)                       # clumps of fronds
    fine = band_noise(rng, 60, 128, 0.4, n=size)                     # single frond tips
    hgt = 0.035 * np.clip(1 - r * r, 0, 1) + 0.012 * cush + 0.006 * mid + 0.002 * fine
    col = mix(rgb(52, 62, 30), rgb(84, 96, 42), smoothstep(-1.6, 1.6, cush + 0.6 * mid))
    col = mix(col, rgb(116, 122, 54), smoothstep(0.6, 2.4, fine + 0.6 * mid) * 0.55)
    col = mix(col, rgb(92, 80, 50), smoothstep(1.2, 2.2, band_noise(rng, 3, 10, n=size)) * 0.45)
    col *= (0.8 + 0.2 * smoothstep(-2.0, 1.5, fine))[..., None]
    cav = cavity(hgt / 0.035, (1.5, 4.0), (0.6, 0.4))
    col *= np.clip(1.0 - 1.2 * cav, 0.6, 1.0)[..., None]
    col *= (1.0 - 0.18 * smoothstep(0.45, 0.78, shape))[..., None]   # thinner, darker toward the edge
    return col, alpha, hgt


# ---------------------------------------------------------------- atlas rendering
def _pass_materials():
    """One override material per render pass. Every value they need lives on the geometry (attributes)."""
    import bpy

    def base(name):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        for nd in list(nt.nodes):
            nt.nodes.remove(nd)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.0
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        return m, nt, em

    def attr(nt, name):
        a = nt.nodes.new("ShaderNodeAttribute")
        a.attribute_type = "GEOMETRY"
        a.attribute_name = name
        return a

    def math_node(nt, op, a=None, b=None, va=None, vb=None):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = op
        if a is not None:
            nt.links.new(a, m.inputs[0])
        elif va is not None:
            m.inputs[0].default_value = va
        if b is not None:
            nt.links.new(b, m.inputs[1])
        elif vb is not None:
            m.inputs[1].default_value = vb
        return m.outputs[0]

    def maprange(nt, x, a, b, invert=False):
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        nt.links.new(x, mr.inputs["Value"])
        mr.inputs["From Min"].default_value = a
        mr.inputs["From Max"].default_value = b
        mr.inputs["To Min"].default_value = 1.0 if invert else 0.0
        mr.inputs["To Max"].default_value = 0.0 if invert else 1.0
        return mr.outputs["Result"]

    def vein_mask(nt):
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.uv_map = "UVMap"
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(uv.outputs["UV"], sep.inputs[0])
        au = math_node(nt, "ABSOLUTE", sep.outputs["X"])
        v = sep.outputs["Y"]
        midrib = maprange(nt, au, 0.015, 0.06, invert=True)
        vk = attr(nt, "vk").outputs["Fac"]
        vn = attr(nt, "vn").outputs["Fac"]
        s = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", v, math_node(nt, "MULTIPLY", au, vk)), vn)
        d = math_node(nt, "ABSOLUTE", math_node(nt, "SUBTRACT", math_node(nt, "FRACT", math_node(nt, "ADD", s, vb=0.5)), vb=0.5))
        lat = maprange(nt, d, 0.03, 0.09, invert=True)
        lat = math_node(nt, "MULTIPLY", lat, maprange(nt, au, 0.98, 0.6))
        lat = math_node(nt, "MULTIPLY", lat, maprange(nt, v, 0.02, 0.08))
        m = math_node(nt, "MAXIMUM", midrib, math_node(nt, "MULTIPLY", lat, vb=0.6))
        return math_node(nt, "MULTIPLY", m, attr(nt, "vein").outputs["Fac"])

    mats = {}
    # albedo (lighter veins; leaf undersides paler)
    m, nt, em = base("_pass_albedo")
    col = attr(nt, "col").outputs["Color"]
    vm = vein_mask(nt)
    mixv = nt.nodes.new("ShaderNodeMix")
    mixv.data_type = "RGBA"
    mixv.blend_type = "SCREEN"
    nt.links.new(vm, mixv.inputs["Factor"])
    nt.links.new(col, mixv.inputs[6])
    mixv.inputs[7].default_value = (0.17, 0.2, 0.08, 1.0)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mixb = nt.nodes.new("ShaderNodeMix")
    mixb.data_type = "RGBA"
    mixb.blend_type = "MIX"
    fac = math_node(nt, "MULTIPLY", geo.outputs["Backfacing"], math_node(nt, "MINIMUM", math_node(nt, "MULTIPLY", attr(nt, "vein").outputs["Fac"], vb=10.0), vb=1.0))
    nt.links.new(math_node(nt, "MULTIPLY", fac, vb=0.55), mixb.inputs["Factor"])
    nt.links.new(mixv.outputs[2], mixb.inputs[6])
    mixb.inputs[7].default_value = (0.2, 0.26, 0.12, 1.0)
    nt.links.new(mixb.outputs[2], em.inputs["Color"])
    mats["albedo"] = m
    # normal (world normal of the visible side, with sunken veins), encoded 0..1
    m, nt, em = base("_pass_normal")
    vm = vein_mask(nt)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.002
    nt.links.new(math_node(nt, "MULTIPLY", vm, vb=-1.0), bump.inputs["Height"])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(bump.outputs["Normal"], sep.inputs[0])
    sgn = math_node(nt, "SUBTRACT", math_node(nt, "MULTIPLY", math_node(nt, "GREATER_THAN", sep.outputs["Z"], vb=0.0), vb=2.0), vb=1.0)
    vm2 = nt.nodes.new("ShaderNodeVectorMath")
    vm2.operation = "MULTIPLY_ADD"
    nt.links.new(bump.outputs["Normal"], vm2.inputs[0])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    half = math_node(nt, "MULTIPLY", sgn, vb=0.5)
    for k in ("X", "Y", "Z"):
        nt.links.new(half, comb.inputs[k])
    nt.links.new(comb.outputs[0], vm2.inputs[1])
    vm2.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(vm2.outputs[0], em.inputs["Color"])
    mats["normal"] = m
    # ambient occlusion inside the sprig
    m, nt, em = base("_pass_ao")
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.only_local = True
    ao.samples = 16
    ao.inputs["Distance"].default_value = 0.35
    nt.links.new(ao.outputs["AO"], em.inputs["Color"])
    mats["ao"] = m
    return mats


def _setup_cycles(samples):
    import bpy
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type in ("OPTIX",)
        scene.cycles.device = "GPU"
    except Exception as exc:  # CPU fallback
        print("NOTE Cycles GPU unavailable (%s), using CPU" % exc)
        scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
    scene.cycles.filter_width = 1.15
    scene.render.film_transparent = True
    scene.render.resolution_x = N
    scene.render.resolution_y = N
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("_atlas_world")
    world.color = (0, 0, 0)
    scene.world = world
    cam_data = bpy.data.cameras.new("_atlas_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = N * ATLAS_UNITS_PER_PX
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("_atlas_cam", cam_data)
    scene.collection.objects.link(cam)
    half = N * ATLAS_UNITS_PER_PX * 0.5
    cam.location = (half, half, 20.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    scene.camera = cam
    return scene


def _render_to_array(scene, path):
    import bpy
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    arr = np.array(img.pixels[:], dtype=np.float64).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return arr


def _morph(a, r, op):
    """Grey-scale dilation (op=np.maximum) or erosion (np.minimum) with a disc of radius r pixels."""
    out = a.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > r * r + 0.5 or (dx == 0 and dy == 0):
                continue
            out = op(out, np.roll(np.roll(a, dy, axis=0), dx, axis=1))
    return out


# needle regions get a morphological closing of their alpha: gaps of a few pixels between needles fill in, so a
# frond stays a dense mass under alpha-test and at the lower mips instead of turning lacy with distance
CLOSE_REGIONS = {"spruce": 2, "fir": 2, "pine": 2, "young": 2}


def push_pull(img, w):
    """Fill every pixel from its weighted (w) neighbourhood: colour bleeding into transparent texels."""
    h, wd, c = img.shape
    levels = []
    cur = img * w[..., None]
    cw = w.copy()
    while cur.shape[0] > 1:
        levels.append((cur, cw))
        hh, ww = cur.shape[0] // 2, cur.shape[1] // 2
        cur = cur.reshape(hh, 2, ww, 2, c).sum(axis=(1, 3))
        cw = cw.reshape(hh, 2, ww, 2).sum(axis=(1, 3))
    res = cur / np.maximum(cw, 1e-8)[..., None]
    for lc, lw in reversed(levels):
        up = np.repeat(np.repeat(res, 2, axis=0), 2, axis=1)
        val = lc / np.maximum(lw, 1e-8)[..., None]
        a = np.clip(lw, 0.0, 1.0)[..., None]
        res = val * a + up * (1.0 - a)
    return res


SPRIG_COLS = {
    "spruce_old": rgb(44, 66, 32), "spruce_new": rgb(96, 128, 46), "spruce_twig": rgb(98, 72, 52),
    "spruce_new2": rgb(78, 108, 44), "spruce_twig2": rgb(70, 54, 42),
    "fir_old": rgb(42, 66, 38), "fir_new": rgb(92, 124, 58), "fir_twig": rgb(96, 82, 52), "fir_under": rgb(150, 166, 150),
    "pine_old": rgb(62, 86, 64), "pine_new": rgb(92, 116, 80), "pine_twig": rgb(150, 98, 62), "pine_bud": rgb(122, 84, 52),
    "young_old": rgb(62, 90, 44), "young_new": rgb(118, 146, 60),
    "dead_wood": rgb(104, 92, 80), "dead_wood2": rgb(132, 124, 114), "dead_needle": rgb(128, 86, 46),
    "lichen": rgb(166, 174, 146),
    "oak_leaves": [rgb(56, 84, 34), rgb(64, 92, 36), rgb(46, 72, 30), rgb(80, 104, 40)],
    "oak_twig": rgb(92, 78, 62),
    "birch_leaves": [rgb(88, 126, 44), rgb(102, 136, 48), rgb(76, 112, 38), rgb(120, 142, 50)],
    "birch_twig": rgb(70, 46, 38),
}


def _build_sprigs(kind, rng):
    """Returns {region: Geo} for the geometry regions of one atlas (local studs, anchor at the origin)."""
    C = SPRIG_COLS
    out = {}
    if kind == "ConiferAtlas":
        W, H = region_size_studs(kind, "spruce")
        # the original oval frond is still generated (and thrown away) so the shared random stream - and with
        # it the fir, pine, young and dead-twig regions - stays exactly as before
        spruce_frond(Geo(), rng, W, H, C["spruce_old"], C["spruce_new"], C["spruce_twig"])
        g = Geo()
        spruce_branch(g, np.random.default_rng(1103), W, H, C["spruce_old"], C["spruce_new2"], C["spruce_twig2"])
        out["spruce"] = g
        W, H = region_size_studs(kind, "fir")
        g = Geo()
        fir_spray(g, rng, W, H, C["fir_old"], C["fir_new"], C["fir_twig"], C["fir_under"])
        out["fir"] = g
        W, H = region_size_studs(kind, "pine")
        g = Geo()
        pine_tuft(g, rng, W, H, C["pine_old"], C["pine_new"], C["pine_twig"], C["pine_bud"])
        out["pine"] = g
        W, H = region_size_studs(kind, "young")
        g = Geo()
        spruce_frond(g, rng, W, H, C["young_old"], C["young_new"], C["spruce_twig"], fresh=0.35, dens=1.15,
                     nlen=0.085, n_sec=12)
        out["young"] = g
        W, H = region_size_studs(kind, "deadtwig")
        g = Geo()
        dead_twigs(g, rng, W, H, C["dead_wood"], C["dead_wood2"], C["dead_needle"], C["lichen"])
        out["deadtwig"] = g
    else:
        W, H = region_size_studs(kind, "oakA")
        g = Geo()
        oak_spray(g, rng, W, H, C["oak_leaves"], C["oak_twig"], 0)
        out["oakA"] = g
        W, H = region_size_studs(kind, "oakB")
        g = Geo()
        oak_spray(g, rng, W, H, C["oak_leaves"], C["oak_twig"], 1)
        out["oakB"] = g
        W, H = region_size_studs(kind, "birchA")
        g = Geo()
        birch_spray(g, rng, W, H, C["birch_leaves"], C["birch_twig"])
        out["birchA"] = g
        W, H = region_size_studs(kind, "birchStrand")
        g = Geo()
        birch_spray(g, rng, W, H, C["birch_leaves"], C["birch_twig"], strand=True)
        out["birchStrand"] = g
        W, H = region_size_studs(kind, "birchB")
        g = Geo()
        birch_spray(g, rng, W, H, C["birch_leaves"], C["birch_twig"], strand=True)
        out["birchB"] = g
    return out


def build_atlas(kind, out_dir, debug_dir=None, samples=48, ao_samples=192, log=print):
    """Model the sprigs, render albedo / normal / AO top-down with Cycles, paint the numpy regions, bleed
    colours into the empty texels and write <kind>_Color.png (RGBA) + <kind>_Normal.png."""
    import bpy
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = _setup_cycles(samples)
    rng = np.random.default_rng({"ConiferAtlas": 101, "BroadleafAtlas": 202}[kind])
    sprigs = _build_sprigs(kind, rng)
    margin = 5
    for key, g in sprigs.items():
        reg = ATLAS[kind][key]
        x0, y0, x1, y1 = reg["rect"]
        px_per_stud = (x1 - x0) / reg["studs"]
        scale = px_per_stud * ATLAS_UNITS_PER_PX
        lo, hi = g.bounds()
        if reg["anchor"] == "bottom":
            ox, oy = (x0 + x1) * 0.5, y0 + margin
        else:
            ox, oy = (x0 + x1) * 0.5, y1 - margin
        bx0, bx1 = ox + lo[0] * px_per_stud, ox + hi[0] * px_per_stud
        by0, by1 = oy + lo[1] * px_per_stud, oy + hi[1] * px_per_stud
        if bx0 < x0 + 2 or bx1 > x1 - 2 or by0 < y0 + 2 or by1 > y1 - 2:
            log("WARNING atlas %s/%s geometry spills out of its rect: x %.0f..%.0f (%d..%d) y %.0f..%.0f (%d..%d)"
                % (kind, key, bx0, bx1, x0, x1, by0, by1, y0, y1))
        g.to_object("_sprig_" + key, scale, (ox * ATLAS_UNITS_PER_PX, oy * ATLAS_UNITS_PER_PX))
        log("ATLAS %s/%s: %d tris" % (kind, key, sum(len(f) - 2 for f in g.faces)))
    mats = _pass_materials()
    # the EXR render passes are intermediates: keep them out of the upload folder (only a debug run keeps them)
    import shutil
    import tempfile
    tmp = debug_dir or tempfile.mkdtemp(prefix="ls_trees_atlas_")
    os.makedirs(tmp, exist_ok=True)
    passes = {}
    for name, spp in (("albedo", samples), ("normal", samples), ("ao", ao_samples)):
        scene.view_layers[0].material_override = mats[name]
        scene.cycles.samples = spp
        passes[name] = _render_to_array(scene, os.path.join(tmp, "_atlas_%s_%s.exr" % (kind, name)))
    scene.view_layers[0].material_override = None
    if not debug_dir:
        shutil.rmtree(tmp, ignore_errors=True)
    alpha = passes["albedo"][..., 3]
    inv = 1.0 / np.maximum(alpha, 1e-4)
    alb = np.clip(passes["albedo"][..., :3] * inv[..., None], 0.0, 1.0)
    nrm = passes["normal"][..., :3] * inv[..., None] * 2.0 - 1.0
    ao = np.clip(passes["ao"][..., 0] * inv, 0.0, 1.0)
    ao = blur(ao, 0.8)
    alb *= (0.5 + 0.5 * ao)[..., None]
    ln = np.linalg.norm(nrm, axis=-1, keepdims=True)
    nrm = np.where(ln > 1e-6, nrm / np.maximum(ln, 1e-6), np.array([0.0, 0.0, 1.0]))
    # slightly fatter cut-out so thin needles survive a 0.5 alpha test and the first mips
    a_cut = np.clip((alpha - 0.18) / 0.5, 0.0, 1.0)
    for key, rad in CLOSE_REGIONS.items():
        if key not in ATLAS[kind]:
            continue
        x0, y0, x1, y1 = ATLAS[kind][key]["rect"]
        sub = a_cut[y0:y1, x0:x1]
        closed = _morph(_morph(sub, rad, np.maximum), rad, np.minimum)
        a_cut[y0:y1, x0:x1] = np.maximum(sub, closed)
        alpha[y0:y1, x0:x1] = np.maximum(alpha[y0:y1, x0:x1], closed)
    # painted regions
    prng = np.random.default_rng(7 if kind == "ConiferAtlas" else 8)
    for key, reg in ATLAS[kind].items():
        if key in sprigs:
            continue
        x0, y0, x1, y1 = reg["rect"]
        size = x1 - x0
        if key == "endgrain":
            c, a, hgt = paint_endgrain(size, prng)
        else:
            c, a, hgt = paint_moss(size, prng)
        n_ = normal_from_height(hgt, reg["studs"] / size)
        alb[y0:y1, x0:x1] = c
        nrm[y0:y1, x0:x1] = n_
        a_cut[y0:y1, x0:x1] = a
        alpha[y0:y1, x0:x1] = a
    wgt = (a_cut > 0.5).astype(np.float64)
    fill_c = push_pull(alb, wgt)
    fill_n = push_pull(nrm, wgt)
    t = smoothstep(0.02, 0.35, alpha)[..., None]
    alb = alb * t + fill_c * (1.0 - t)
    nrm = nrm * t + fill_n * (1.0 - t)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
    rgba = np.concatenate([lin_to_srgb(alb), a_cut[..., None]], axis=-1)
    cpath = write_png(os.path.join(out_dir, FILES[kind][0]), rgba)
    npath = write_png(os.path.join(out_dir, FILES[kind][1]), encode_normal(nrm))
    cover = float((a_cut > 0.5).mean())
    log("TEX %s %.1fs coverage %.0f%% -> %s, %s" % (kind, time.time() - t0, cover * 100, os.path.basename(cpath),
                                                    os.path.basename(npath)))
    if debug_dir:
        write_png(os.path.join(debug_dir, "_dbg_%s_ao.png" % kind), ao)
        write_png(os.path.join(debug_dir, "_dbg_%s_alpha.png" % kind), alpha)
    return {"coverage": cover}


def build_all(out_dir, debug_dir=None, log=print, what="all"):
    info = {}
    if what in ("all", "bark"):
        info.update(build_barks(out_dir, log=log))
        build_roughness(out_dir, log=log)
    if what in ("all", "atlas", "ConiferAtlas"):
        info["ConiferAtlas"] = build_atlas("ConiferAtlas", out_dir, debug_dir, log=log)
    if what in ("all", "atlas", "BroadleafAtlas"):
        info["BroadleafAtlas"] = build_atlas("BroadleafAtlas", out_dir, debug_dir, log=log)
    return info


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else os.getcwd()
    what = argv[1] if len(argv) > 1 else "all"
    dbg = argv[2] if len(argv) > 2 else None
    build_all(out, dbg, what=what)
