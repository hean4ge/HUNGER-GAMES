"""
tex_buildings.py - texture sheets for the BuildingsReal set (LAST STANDING), Blender 5.3 headless (numpy only).

Every surface of the man-made remnants and campsite props samples one of FIVE 1024 x 1024 sheets. Each sheet is a
stack of full-width strips (tileable along U, and along V where a strip wraps round a log or rope) plus a few
blocks. Everything is synthesised procedurally from height fields: the height field is the "high-poly detail"
(grain relief, checks, drawknife facets, stones, weave ...) and colour, ambient occlusion (horizon AO + cavity),
roughness, metalness and OpenGL normals are all baked from it, so the sheets need no downloads.

  BR_Wood   sawn boards (silver, grey-brown, brown, damp, crate pine), rough-sawn beam, end-grain squares
  BR_Log    peeled wall log (with contact AO + chinking smears), weathered pole, bark, rope, log-end discs
  BR_Stone  fieldstone masonry (chimney + mossy footing), rock, chinking, concrete, ash / soot
  BR_Shake  7 rows of hand-split cedar shake courses (clean -> mossy), shake butts, moss cushion
  BR_Kit    canvas, rusted iron, tin, wire rope, char, ember, globe glass, blanket, window glass, leather (RGBA)

Images (all PNG, power of two):
  BR_<Sheet>_Color.png  (1024, sRGB; BR_Kit_Color is RGBA - alpha is only used by the glass materials)
  BR_<Sheet>_Normal.png (1024, OpenGL +Y tangent space)
  BR_<Sheet>_MR.png     (512, R = G = roughness, B = metalness - the glTF metallicRoughness packing; B is never
                         a flat channel, so no image the importer derives from it is a single colour)
  BR_<Sheet>_Roughness.png (512, 8-bit grayscale roughness = the MR map's G channel, for a hand-built
                         SurfaceAppearance.RoughnessMap)
  BR_Kit_Metal.png      (512, grayscale metalness of BR_Kit for a hand-built SurfaceAppearance)
The GLB embeds Color + Normal + MR (15 images). A hand-built SurfaceAppearance set uses Color + Normal + Roughness
(+ Kit Metal) = 16 images. Either way a set stays within 16 uploads.

Layout: LAYOUT below (pixel boxes, y up from the bottom = V 0). br_kit.py maps UVs into these boxes.

Run on its own (writes the PNGs + BR_layout.json):
  blender --background --factory-startup --python tex_buildings.py -- <texture_out_dir> [sheet,sheet...]
"""
import json
import math
import os
import struct
import sys
import time
import zlib

import numpy as np

N = 1024
MR_N = 512
TAU = 2.0 * math.pi
PREFIX = "BR_"
SHEETS = ("Wood", "Log", "Stone", "Shake", "Kit")

# ================================================================================================
# Layout. region: (x, y, w, h, pad, px_per_stud). Full-width strips (w == N) wrap in U through the texture
# repeat; their pad is only applied in V. Blocks are padded on all sides. The pad is filled with the periodic
# continuation of the content so bilinear filtering and the first mips never pull in the neighbour.
# ================================================================================================
LAYOUT = {
    "Wood": {
        "board_silver": (0, 896, N, 128, 4, 160.0),
        "board_grey": (0, 768, N, 128, 4, 160.0),
        "board_brown": (0, 640, N, 128, 4, 160.0),
        "board_damp": (0, 512, N, 128, 4, 160.0),
        "beam": (0, 384, N, 128, 4, 160.0),
        "board_lichen": (0, 256, N, 128, 4, 160.0),
        "board_crate": (0, 128, N, 128, 4, 160.0),
        "end_sq_0": (0, 0, 128, 128, 4, 160.0),
        "end_sq_1": (128, 0, 128, 128, 4, 160.0),
        "end_sq_2": (256, 0, 128, 128, 4, 160.0),
        "end_sq_3": (384, 0, 128, 128, 4, 160.0),
        "end_sq_4": (512, 0, 128, 128, 4, 160.0),
        "end_sq_5": (640, 0, 128, 128, 4, 160.0),
        "end_sq_6": (768, 0, 128, 128, 4, 160.0),
        "end_sq_7": (896, 0, 128, 128, 4, 160.0),
    },
    "Log": {
        "log_wall": (0, 704, N, 320, 4, 164.0),
        "pole": (0, 448, N, 256, 4, 176.0),
        "bark": (0, 256, N, 192, 4, 196.0),
        "split": (0, 192, N, 64, 4, 150.0),
        "rope": (0, 128, N, 64, 4, 112.0),
        "end_0": (0, 0, 128, 128, 3, 100.0),
        "end_1": (128, 0, 128, 128, 3, 100.0),
        "end_2": (256, 0, 128, 128, 3, 100.0),
        "end_3": (384, 0, 128, 128, 3, 100.0),
        "end_4": (512, 0, 128, 128, 3, 100.0),
        "end_5": (640, 0, 128, 128, 3, 100.0),
        "end_fresh_0": (768, 0, 128, 128, 3, 100.0),
        "end_fresh_1": (896, 0, 128, 128, 3, 100.0),
    },
    "Stone": {
        "masonry": (0, 736, N, 288, 4, 200.0),
        "masonry_foot": (0, 576, N, 160, 4, 200.0),
        "rock": (0, 384, N, 192, 4, 200.0),
        "rock_burnt": (0, 288, N, 96, 4, 140.0),
        "chinking": (0, 192, N, 96, 4, 200.0),
        "concrete": (0, 96, N, 96, 4, 160.0),
        "ash": (0, 0, N, 96, 4, 120.0),
    },
    "Shake": {
        "course_0": (0, 896, N, 128, 3, 160.0),
        "course_1": (0, 768, N, 128, 3, 160.0),
        "course_2": (0, 640, N, 128, 3, 160.0),
        "course_3": (0, 512, N, 128, 3, 160.0),
        "course_4": (0, 384, N, 128, 3, 160.0),
        "course_5": (0, 256, N, 128, 3, 160.0),
        "course_6": (0, 128, N, 128, 3, 160.0),
        "butt": (0, 64, N, 64, 4, 160.0),
        "moss": (0, 0, N, 64, 4, 160.0),
    },
    "Kit": {
        "canvas": (0, 512, N, 512, 4, 128.0),
        "iron": (0, 432, N, 80, 4, 200.0),
        "tin": (0, 368, N, 64, 4, 200.0),
        "wire": (0, 336, N, 32, 3, 160.0),
        "char": (0, 272, N, 64, 4, 180.0),
        "ember": (0, 208, N, 64, 4, 180.0),
        "globe": (0, 160, N, 48, 3, 300.0),
        "blanket": (0, 0, 512, 160, 4, 110.0),
        "glass": (512, 0, 256, 160, 4, 160.0),
        "leather": (768, 80, 256, 80, 4, 300.0),
        "ticking": (768, 0, 256, 80, 4, 110.0),
    },
}


def region_info(sheet, name):
    """Inner (content) box of a region: dict with px box, UV box, px per stud and tile size in studs."""
    x, y, w, h, pad, ppx = LAYOUT[sheet][name]
    if w == N:
        ix, iw = 0, N
    else:
        ix, iw = x + pad, w - 2 * pad
    iy, ih = y + pad, h - 2 * pad
    return {"px": (ix, iy, iw, ih), "uv": (ix / N, iy / N, (ix + iw) / N, (iy + ih) / N), "ppx": ppx,
            "tile": (iw / ppx, ih / ppx), "fullWidth": w == N}


# ================================================================================================
# PNG writer (8-bit gray / RGB / RGBA). Arrays are row 0 = BOTTOM (V = 0); the file is written top-down.
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
    arr = np.clip(np.round(np.asarray(img, dtype=np.float64) * 255.0), 0, 255).astype(np.uint8)
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


# ================================================================================================
# Colour + maths helpers (all colour maths in linear space)
# ================================================================================================
def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def C(r, g, b):
    return srgb_to_lin(np.array([r, g, b], dtype=np.float64) / 255.0)


def mixc(a, b, t):
    t = np.asarray(t, dtype=np.float64)
    if t.ndim == 2:
        t = t[..., None]
    return a + (b - a) * t


def sstep(e0, e1, x):
    t = np.clip((np.asarray(x) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grid(h, w):
    Y, X = np.mgrid[0:h, 0:w].astype(np.float64)
    return Y + 0.5, X + 0.5


def norm01(a, lo_p=0.5, hi_p=99.5):
    lo, hi = np.percentile(a, lo_p), np.percentile(a, hi_p)
    return np.clip((a - lo) / (hi - lo + 1e-12), 0.0, 1.0)


def pnoise(rng, h, w, lam_lo, lam_hi, beta=1.0, ax=1.0, ay=1.0):
    """Periodic band-limited noise (zero mean, unit std) with feature wavelengths lam_lo..lam_hi pixels.
    ax > 1 stretches features along X (U), ay > 1 along Y (V)."""
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.sqrt((fx * ax) ** 2 + (fy * ay) ** 2)
    k[0, 0] = 1e-9
    k_lo, k_hi = 1.0 / lam_hi, 1.0 / lam_lo
    win = sstep(k_lo * 0.6, k_lo, k) * (1.0 - sstep(k_hi, k_hi * 1.6, k))
    amp = win * k ** (-beta)
    amp[0, 0] = 0.0
    spec = amp * np.exp(1j * rng.uniform(0.0, TAU, (h, w)))
    f = np.fft.ifft2(spec).real
    f -= f.mean()
    s = f.std()
    return f / s if s > 1e-12 else f


def pblur(img, sx, sy=None):
    """Periodic gaussian blur, sigma in pixels (sx along X, sy along Y)."""
    sy = sx if sy is None else sy
    h, w = img.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * math.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    return np.fft.ifft2(np.fft.fft2(img) * g).real


def pvoronoi(rng, h, w, gx, gy, jitter=0.9, warp=None, reach=2, aspect=1.0):
    """Periodic Voronoi on a jittered gx x gy grid. aspect > 1 measures distance with X divided by aspect, so
    cells really come out elongated along X (bark plates, laid stones, drawknife facets).
    Returns F1, the distance to the nearest cell edge, cell id and the nearest site (sx, sy) - all in the
    (X / aspect, Y) metric except the site position, which is in pixels."""
    cw, ch = w / gx, h / gy
    px = (np.arange(gx)[None, :] + 0.5 + (rng.random((gy, gx)) - 0.5) * jitter) * cw
    py = (np.arange(gy)[:, None] + 0.5 + (rng.random((gy, gx)) - 0.5) * jitter) * ch
    Y, X = grid(h, w)
    if warp is not None:
        X = X + warp[0]
        Y = Y + warp[1]
    ci = np.floor(X / cw).astype(np.int64)
    cj = np.floor(Y / ch).astype(np.int64)
    a = float(aspect)
    d1 = np.full((h, w), 1e18)
    sid = np.zeros((h, w), np.int64)
    s1x = np.zeros((h, w))
    s1y = np.zeros((h, w))
    cands = []
    ry = max(reach, int(math.ceil(reach * cw / (ch * a)))) if a > 1.0 else reach
    for dj in range(-ry, ry + 1):
        for di in range(-reach, reach + 1):
            ii, jj = ci + di, cj + dj
            iw, jw = ii % gx, jj % gy
            qx = px[jw, iw] + (ii - iw) * cw
            qy = py[jw, iw] + (jj - jw) * ch
            d = ((X - qx) / a) ** 2 + (Y - qy) ** 2
            m = d < d1
            d1 = np.where(m, d, d1)
            sid = np.where(m, jw * gx + iw, sid)
            s1x = np.where(m, qx, s1x)
            s1y = np.where(m, qy, s1y)
            cands.append((qx, qy))
    edge = np.full((h, w), 1e9)
    for (qx, qy) in cands:
        dd = np.sqrt(((qx - s1x) / a) ** 2 + (qy - s1y) ** 2)
        valid = dd > 1e-6
        e = (((X - qx) / a) ** 2 + (Y - qy) ** 2 - d1) / (2.0 * np.maximum(dd, 1e-6))
        edge = np.where(valid & (e < edge), e, edge)
    return np.sqrt(d1), edge, sid, (s1x, s1y)


def cell_rand(rng, sid, n_cells, lo=0.0, hi=1.0):
    vals = rng.uniform(lo, hi, n_cells)
    return vals[sid]


def normal_from_height(hgt, ppx):
    """hgt in studs, ppx = pixels per stud -> OpenGL tangent normal (H x W x 3, -1..1), +Y = +V (row up)."""
    s = ppx * 0.5
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * s
    dy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * s
    ln = np.sqrt(dx * dx + dy * dy + 1.0)
    return np.stack([-dx / ln, -dy / ln, 1.0 / ln], axis=-1)


def horizon_ao(hgt, ppx, radius_studs, dirs=8, steps=6, strength=1.0):
    """Periodic height-field ambient occlusion: mean over directions of the sine of the highest horizon angle."""
    h, w = hgt.shape
    rad_px = max(radius_studs * ppx, 1.5)
    occ = np.zeros_like(hgt)
    for k in range(dirs):
        a = TAU * (k + 0.5) / dirs
        cx, cy = math.cos(a), math.sin(a)
        best = np.zeros_like(hgt)
        for s in range(1, steps + 1):
            dist = rad_px * (s / steps) ** 1.5
            ox, oy = int(round(cx * dist)), int(round(cy * dist))
            if ox == 0 and oy == 0:
                continue
            sh = np.roll(np.roll(hgt, -oy, axis=0), -ox, axis=1)
            dd = math.hypot(ox, oy) / ppx
            ang = np.arctan2(sh - hgt, dd)
            best = np.maximum(best, ang)
        occ += np.sin(best)
    occ /= dirs
    return np.clip(1.0 - strength * occ, 0.0, 1.0)


def cavity(hgt, sigmas=(1.5, 5.0, 14.0), weights=(0.5, 0.3, 0.2)):
    c = np.zeros_like(hgt)
    for s, wt in zip(sigmas, weights):
        c += wt * np.maximum(0.0, pblur(hgt, s) - hgt)
    return c


def _win(cx, cy, rx, ry, h, w):
    xs = np.arange(int(math.floor(cx - rx)) - 1, int(math.ceil(cx + rx)) + 2)
    ys = np.arange(int(math.floor(cy - ry)) - 1, int(math.ceil(cy + ry)) + 2)
    if len(xs) > w:
        xs = np.arange(int(math.floor(cx - w / 2)), int(math.floor(cx - w / 2)) + w)
    if len(ys) > h:
        ys = np.arange(int(math.floor(cy - h / 2)), int(math.floor(cy - h / 2)) + h)
    dx = (xs + 0.5 - cx)[None, :]
    dy = (ys + 0.5 - cy)[:, None]
    return np.ix_(ys % h, xs % w), dx, dy


def stamp_max(field, idx, val):
    field[idx] = np.maximum(field[idx], val)


def crack_along_u(field, rng, cx, cy, length, width, slope=0.0, wob=1.2):
    """Thin tapered crack running along X (U), periodic. field gets max-combined depth 0..1."""
    h, w = field.shape
    L2 = length / 2.0
    ry = abs(slope) * L2 + wob * 1.6 + width * 3.0 + 2.0
    idx, dx, dy = _win(cx, cy, L2, ry, h, w)
    t = np.clip(1.0 - np.abs(dx) / L2, 0.0, 1.0)
    ph, f = rng.uniform(0, TAU), rng.uniform(0.8, 2.2)
    path = slope * dx + wob * np.sin(dx / L2 * math.pi * f + ph) + 0.5 * wob * np.sin(dx / L2 * math.pi * f * 2.9 + 2 * ph)
    wid = width * np.power(t, 0.6) + 0.12
    val = np.exp(-((dy - path) / wid) ** 2) * np.minimum(1.0, t * 5.0)
    stamp_max(field, idx, val)


def crack_along_v(field, rng, cx, cy, length, width, slope=0.0, wob=1.0):
    h, w = field.shape
    L2 = length / 2.0
    rx = abs(slope) * L2 + wob * 1.6 + width * 3.0 + 2.0
    idx, dx, dy = _win(cx, cy, rx, L2, h, w)
    t = np.clip(1.0 - np.abs(dy) / L2, 0.0, 1.0)
    ph, f = rng.uniform(0, TAU), rng.uniform(0.8, 2.2)
    path = slope * dy + wob * np.sin(dy / L2 * math.pi * f + ph) + 0.5 * wob * np.sin(dy / L2 * math.pi * f * 2.9 + 2 * ph)
    wid = width * np.power(t, 0.6) + 0.12
    val = np.exp(-((dx - path) / wid) ** 2) * np.minimum(1.0, t * 5.0)
    stamp_max(field, idx, val)


def spots(field, rng, n, r_lo, r_hi, soft=0.35, mask=None, aspect=1.0):
    """n soft discs (radius px) max-combined into field; if mask is given, discs only land where mask > 0.5."""
    h, w = field.shape
    placed = 0
    tries = 0
    while placed < n and tries < n * 20:
        tries += 1
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        if mask is not None and mask[int(cy) % h, int(cx) % w] < rng.uniform(0.3, 0.7):
            continue
        r = rng.uniform(r_lo, r_hi)
        idx, dx, dy = _win(cx, cy, r * aspect + 2, r + 2, h, w)
        d = np.sqrt((dx / aspect) ** 2 + dy ** 2) / r
        val = 1.0 - sstep(1.0 - soft, 1.0, d)
        stamp_max(field, idx, val)
        placed += 1
    return field


def periodic_widths(rng, total, lo, hi):
    """Random segment widths summing exactly to total (pixels)."""
    ws = []
    s = 0.0
    while s < total:
        v = rng.uniform(lo, hi)
        ws.append(v)
        s += v
    excess = s - total
    if ws[-1] - excess >= lo * 0.6:
        ws[-1] -= excess
    else:
        ws.pop()
        k = total / sum(ws)
        ws = [v * k for v in ws]
    return ws


def finish(col, hgt, rough, ppx, ao_radius=0.06, ao_strength=1.0, cav_strength=0.0, metal=None, alpha=None,
           extra_ao=None, blur_h=0.6, ao_min=0.38):
    """Bake AO + cavity into colour, derive the normal. Returns the region dict the sheet assembler needs."""
    hs = pblur(hgt, blur_h) if blur_h > 0 else hgt
    ao = horizon_ao(hs, ppx, ao_radius, strength=ao_strength)
    if cav_strength > 0:
        cav = cavity(hs * ppx)
        ao = ao * np.clip(1.0 - cav_strength * cav, 0.35, 1.0)
    ao = ao_min + (1.0 - ao_min) * ao
    if extra_ao is not None:
        ao = ao * extra_ao
    col = col * ao[..., None]
    return {"albedo": col, "normal": normal_from_height(hs, ppx), "rough": np.clip(rough, 0.02, 1.0),
            "metal": metal, "alpha": alpha, "ao": ao}


# ================================================================================================
# WOOD: sawn boards, rough-sawn beam, end-grain squares
# ================================================================================================
def lichen_patches(rng, h, w, ppx, cover, mask=None, scale=1.0, yellow=0.12):
    """Crustose lichen: irregular lobed rosettes that gather in clusters. Returns (pale, yellow, dots) cover maps.
    cover = fraction of the (masked) area; scale ~ rosette size multiplier."""
    s = scale
    ros = pnoise(rng, h, w, 2.5 * s, 26 * s, 0.9)
    lobe = pnoise(rng, h, w, 0.8, 3.5, 0.3)
    clus = pnoise(rng, h, w, 40 * s, 420 * s, 1.4)
    field = ros + 0.4 * lobe + 1.1 * clus
    if mask is not None:
        field = field - 3.0 * (1.0 - np.clip(mask, 0, 1))
    if cover <= 0:
        z = np.zeros((h, w))
        return z, z, z
    thr = np.percentile(field, 100.0 * (1.0 - cover))
    pale = sstep(thr, thr + 0.22, field)
    f2 = pnoise(rng, h, w, 1.5 * s, 10 * s, 0.8) + 0.4 * lobe + 1.1 * clus
    thr2 = np.percentile(f2, 100.0 * (1.0 - cover * yellow))
    yel = sstep(thr2, thr2 + 0.2, f2) * (1.0 - pale)
    dots = sstep(2.1, 2.7, pnoise(rng, h, w, 0.7, 2.2, 0.2)) * pale
    return pale, yel, dots


def apply_lichen(col, hgt, pale, yel, dots, rng, strength=0.8):
    h, w = pale.shape
    v = norm01(pnoise(rng, h, w, 1.5, 12, 0.6))
    pcol = mixc(C(170, 176, 156), C(146, 158, 138), v)
    col = mixc(col, pcol, pale * strength)
    col = mixc(col, C(186, 160, 74), yel * strength * 0.85)
    col = mixc(col, C(54, 52, 48), dots * 0.6)
    hgt = hgt + 0.0015 * pale + 0.001 * yel
    return col, hgt


def moss_cushions(rng, h, w, ppx, size=0.09):
    """Lumpy cushion structure (0..1) of moss tufts."""
    gx, gy = max(3, int(w / (size * ppx))), max(2, int(h / (size * ppx)))
    F1, edge, sid, _ = pvoronoi(rng, h, w, gx, gy, 0.95)
    r = 0.62 * h / gy
    cush = np.clip(1.0 - (F1 / r) ** 2, 0.0, 1.0) * cell_rand(rng, sid, gx * gy, 0.6, 1.0)
    return np.clip(cush + 0.25 * pnoise(rng, h, w, 0.8, 3, 0.3), 0, 1.2)


BOARD_STYLES = {
    # weather: 0 = fresh brown, 1 = silver. tone: overall brightness. mildew / lichen / moss amounts.
    "board_silver": dict(weather=0.95, tone=1.0, mildew=0.5, lichen=0.05, moss=0.0, nails=2.0, checks=11, knots=1.3,
                         seed=101),
    "board_grey": dict(weather=0.62, tone=0.97, mildew=0.3, lichen=0.0, moss=0.0, nails=1.5, checks=8, knots=1.5,
                       seed=102),
    "board_brown": dict(weather=0.15, tone=0.92, mildew=0.12, lichen=0.0, moss=0.0, nails=1.5, checks=5, knots=1.8,
                        seed=103, dirt=0.35),
    "board_damp": dict(weather=0.8, tone=0.8, mildew=0.9, lichen=0.03, moss=0.45, nails=1.5, checks=9, knots=1.2,
                       seed=104, damp=0.6),
    "beam": dict(weather=0.82, tone=0.95, mildew=0.4, lichen=0.03, moss=0.0, nails=0.6, checks=14, knots=1.0,
                 seed=105, saw=1.0),
    "board_lichen": dict(weather=1.0, tone=1.03, mildew=0.6, lichen=0.16, moss=0.2, nails=1.0, checks=12, knots=1.0,
                         seed=106),
    "board_crate": dict(weather=0.42, tone=1.06, mildew=0.25, lichen=0.0, moss=0.0, nails=3.0, checks=6, knots=2.2,
                        seed=107, saw=0.6, pine=1.0),
}


def gen_board(h, w, ppx, weather=0.8, tone=1.0, mildew=0.3, lichen=0.0, moss=0.0, nails=1.5, checks=8, knots=1.2,
              seed=1, saw=0.0, damp=0.0, dirt=0.2, pine=0.0):
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    tile_studs = w / ppx
    # ---- growth rings on a flat-sawn face: rings are cylinders round a pith that wanders under the board
    D = rng.uniform(0.25, 1.0) * h
    vp = (h * rng.uniform(-0.9, 1.9) + h * 0.36 * np.sin(TAU * X / w + rng.uniform(0, TAU))
          + h * 0.12 * np.sin(2 * TAU * X / w + rng.uniform(0, TAU)))
    warp = pnoise(rng, h, w, 40, 800, 1.6, ax=12.0) * 2.4 + pnoise(rng, h, w, 6, 60, 1.0, ax=8.0) * 0.45
    R = np.sqrt((Y - vp) ** 2 + D ** 2) + warp
    # ---- knots: oval, ringed, dark rim; the grain flows round them
    knot = np.zeros((h, w))
    krim = np.zeros((h, w))
    crack = np.zeros((h, w))
    for _ in range(rng.poisson(knots * tile_studs / 6.4)):
        kx, ky = rng.uniform(0, w), rng.uniform(0.22 * h, 0.78 * h)
        kr = rng.uniform(0.035, 0.085) * ppx
        ka = rng.uniform(1.15, 1.7)
        idx, dx, dy = _win(kx, ky, kr * ka * 7, kr * 4.5, h, w)
        d2 = (dx / (ka * 1.5)) ** 2 + dy ** 2
        R[idx] += 2.4 * kr * np.exp(-d2 / (2 * (2.1 * kr) ** 2))
        dk = np.sqrt((dx / ka) ** 2 + dy ** 2) / kr
        stamp_max(knot, idx, 1.0 - sstep(0.88, 1.04, dk))
        stamp_max(krim, idx, np.exp(-((dk - 0.98) / 0.13) ** 2))
        if rng.random() < 0.55:
            crack_along_u(crack, rng, kx + rng.uniform(-0.5, 0.5) * kr, ky + rng.uniform(-0.3, 0.3) * kr,
                          kr * rng.uniform(3, 7), rng.uniform(0.6, 1.3), wob=0.5)
    ring = rng.uniform(4.6, 6.8)
    ph = (R / ring + 0.35 * pnoise(rng, h, w, 30, 400, 1.3, ax=6.0)) % 1.0
    late = sstep(0.66, 0.79, ph) * (1.0 - sstep(0.92, 1.0, ph))
    fib = pnoise(rng, h, w, 1.2, 14, 0.5, ax=16.0)
    streak = pnoise(rng, h, w, 20, 400, 1.2, ax=14.0)
    tone_n = pnoise(rng, h, w, 150, 1400, 1.6, ax=4.0)
    # ---- checks along the grain (a few long open ones, more fine ones)
    for _ in range(rng.poisson(checks * tile_studs / 6.4)):
        big = rng.random() < 0.3
        crack_along_u(crack, rng, rng.uniform(0, w), rng.uniform(0.15 * h, 0.85 * h),
                      rng.uniform(0.6, 2.6 if big else 1.2) * ppx, rng.uniform(1.4, 2.4) if big else rng.uniform(0.5, 1.1),
                      slope=rng.uniform(-0.008, 0.008), wob=1.1)
    # ---- nail holes in pairs (deck nails at a joist) + black iron-tannin streaks along the grain
    hole = np.zeros((h, w))
    stain = np.zeros((h, w))
    for _ in range(rng.poisson(nails * tile_studs / 6.4)):
        nx = rng.uniform(0, w)
        for ny in (h * rng.uniform(0.22, 0.32), h * rng.uniform(0.68, 0.78)):
            r = rng.uniform(1.3, 2.0)
            idx, dx, dy = _win(nx, ny, 0.4 * ppx, 7, h, w)
            stamp_max(hole, idx, 1.0 - sstep(0.7, 1.0, np.sqrt(dx ** 2 + dy ** 2) / r))
            sl = rng.uniform(0.06, 0.25) * ppx
            stamp_max(stain, idx, np.exp(-np.abs(dx) / sl) * np.exp(-(dy / rng.uniform(2.2, 4.5)) ** 2) * 0.85)
    # ---- edges (board arrises): worn round + dirt in the gap; slight cupping across the board
    de = np.minimum(Y, h - Y)
    edge_round = (1.0 - sstep(0.0, 0.12 * h, de)) ** 2
    cup = rng.uniform(-1.0, 1.0) * 0.004 * (((Y / h - 0.5) * 2.0) ** 2 - 0.33)
    # ---- height (studs)
    relief = 0.0008 + 0.0036 * weather
    hgt = relief * (late - 0.5) + 0.0007 * fib - 0.012 * edge_round + cup
    hgt += 0.002 * knot - 0.0015 * krim
    hgt -= 0.017 * crack + 0.008 * hole
    if saw > 0:
        period = rng.uniform(0.05, 0.075) * ppx
        sx = np.sin(TAU * (X + 0.16 * Y + 1.5 * pnoise(rng, h, w, 20, 200, 1.0, ay=3.0)) / period)
        hgt += saw * 0.0011 * (1.0 - 0.55 * weather) * sx
    # ---- colour (linear)
    if pine > 0:
        warm_e, warm_l = C(190, 158, 116), C(156, 118, 78)
    else:
        warm_e, warm_l = C(172, 134, 94), C(126, 90, 60)
    grey_e, grey_l = C(160, 156, 147), C(122, 117, 110)
    wm = np.clip(weather + 0.13 * tone_n + 0.05 * streak, 0.0, 1.0)
    e = mixc(warm_e, grey_e, wm)
    l = mixc(warm_l, grey_l, wm)
    col = mixc(e, l, late * (0.9 - 0.45 * wm))
    col = col * (1.0 + 0.07 * fib + 0.035 * tone_n)[..., None] * tone
    # brown-grey intermediate wash where the grey has not fully taken (desaturated, streaky)
    bw = sstep(0.4, 1.6, streak + 0.5 * tone_n) * wm * (1 - wm) * 2.5
    col = mixc(col, C(142, 126, 108), np.clip(bw, 0, 1) * 0.35)
    # dark run-off streaks + clustered mildew specks
    dk = sstep(0.9, 2.1, pnoise(rng, h, w, 3, 90, 0.9, ax=10.0) + 0.6 * streak) * (0.25 + 0.75 * wm)
    col = mixc(col, C(80, 78, 74), dk * 0.45)
    if mildew > 0:
        sp = sstep(1.7, 2.5, pnoise(rng, h, w, 0.8, 3.0, 0.3)) * sstep(0.3, 1.4, pnoise(rng, h, w, 20, 300, 1.2, ax=5.0) + 0.4 * streak)
        col = mixc(col, C(46, 44, 42), np.clip(sp * mildew * 1.4, 0, 1) * 0.75)
    # knots: dark resinous core (weathers to charcoal) with a resin halo
    kc = mixc(C(96, 64, 40), C(78, 72, 66), wm)
    col = mixc(col, kc, knot * 0.88)
    col = mixc(col, C(56, 44, 34), krim * 0.6)
    if damp > 0:
        dmask = sstep(-0.6, 1.2, pnoise(rng, h, w, 30, 400, 1.2, ax=3.0)) * damp
        col = col * (1.0 - 0.3 * dmask)[..., None]
        col = mixc(col, C(70, 80, 60), dmask * 0.16)
    stn = np.clip(stain, 0, 1)
    col = mixc(col, C(52, 44, 38), stn * 0.72)
    col = mixc(col, C(28, 25, 23), hole)
    # dirt in the gaps at the board edges + grime in the open grain
    col = col * (1.0 - (0.3 + 0.25 * dirt) * (1.0 - sstep(0.0, 0.075 * h, de)))[..., None]
    col = col * (1.0 - dirt * 0.25 * late * (1 - wm))[..., None]
    if lichen > 0:
        pale, yel, dots = lichen_patches(rng, h, w, ppx, lichen, scale=0.8, yellow=0.2)
        col, hgt = apply_lichen(col, hgt, pale, yel, dots, rng, 0.75)
    if moss > 0:
        mm = (1.0 - sstep(0.0, 0.18 * h, de)) * sstep(-0.2, 0.9, pnoise(rng, h, w, 10, 160, 1.1, ax=4.0) + 0.2)
        mm = np.clip(mm * moss * 1.7, 0, 1)
        mcol = mixc(C(60, 78, 32), C(104, 124, 48), norm01(pnoise(rng, h, w, 1.2, 6, 0.4)))
        col = mixc(col, mcol, mm)
        hgt += 0.006 * mm * (0.6 + 0.4 * pnoise(rng, h, w, 1.5, 6, 0.5))
    # checks: dark interior, slightly eroded (lighter) lips
    lips = np.clip(pblur(crack, 1.6) * 1.6 - crack, 0, 1)
    col = mixc(col, C(176, 170, 160), lips * 0.18 * wm)
    col = mixc(col, C(38, 33, 29), crack * 0.93)
    rough = 0.83 + 0.07 * wm + 0.025 * pnoise(rng, h, w, 10, 200, 1.0, ax=6.0)
    rough = rough + 0.1 * crack - 0.06 * stn - (0.1 * dmask if damp > 0 else 0.0)
    return finish(col, hgt, rough, ppx, ao_radius=0.05, ao_strength=1.15)


def gen_end_square(s, ppx, seed, weather=0.75):
    rng = np.random.default_rng(seed)
    Y, X = grid(s, s)
    a = rng.uniform(0, TAU)
    dist = rng.uniform(0.35, 1.0) * s
    pxp, pyp = s / 2 + math.cos(a) * dist, s / 2 + math.sin(a) * dist
    dx, dy = X - pxp, Y - pyp
    r = np.sqrt(dx * dx + dy * dy) + pnoise(rng, s, s, 6, 80, 1.3) * 1.4
    ring = rng.uniform(4.0, 6.0)
    ph = (r / ring) % 1.0
    late = sstep(0.62, 0.78, ph) * (1.0 - sstep(0.9, 1.0, ph))
    th = np.arctan2(dy, dx)
    crack = np.zeros((s, s))
    for _ in range(rng.integers(1, 3)):
        t0 = math.atan2(s / 2 - pyp, s / 2 - pxp) + rng.uniform(-0.45, 0.45)
        bend = rng.uniform(-0.03, 0.03)
        dth = np.angle(np.exp(1j * (th - t0 - bend * (r - dist))))
        across = np.abs(dth) * np.maximum(r, 1.0)
        r0 = dist - rng.uniform(0.25, 0.45) * s
        r1 = r0 + rng.uniform(0.3, 0.6) * s
        t = np.clip((r - r0) / (r1 - r0), 0, 1)
        wid = 0.5 + rng.uniform(0.8, 1.8) * (1 - t)
        crack = np.maximum(crack, np.exp(-(across / wid) ** 2) * (r > r0) * (r < r1) * sstep(0, 0.1, t))
    saw = np.sin(TAU * (X * math.cos(0.3) + Y * math.sin(0.3)) / rng.uniform(5, 8))
    hgt = 0.0022 * (late - 0.5) - 0.014 * crack + 0.0005 * saw
    de = np.minimum(np.minimum(X, s - X), np.minimum(Y, s - Y))
    hgt -= 0.006 * (1.0 - sstep(0, 0.08 * s, de)) ** 2
    early = mixc(C(150, 118, 84), C(122, 116, 106), weather)
    latec = mixc(C(112, 80, 52), C(92, 86, 78), weather)
    col = mixc(early, latec, late * 0.75)
    col = col * (0.93 + 0.08 * pnoise(rng, s, s, 10, 120, 1.2))[..., None]
    col = mixc(col, C(36, 32, 28), crack * 0.9)
    col = col * (1.0 - 0.3 * (1.0 - sstep(0, 0.06 * s, de)))[..., None]
    rough = 0.9 + 0.05 * crack
    return finish(col, hgt, rough, ppx, ao_radius=0.03)


# ================================================================================================
# LOG: peeled wall log, weathered pole, bark, rope, log-end discs
# ================================================================================================
def gen_log(h, w, ppx, seed, contact=True, weather=0.82, bark=0.11, checks=9, knots=2.2, chink=0.6):
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    tile = w / ppx
    gx = max(3, int(round(w / (rng.uniform(0.5, 0.75) * ppx))))
    gy = max(2, int(round(h / (0.15 * ppx))))
    wx = pnoise(rng, h, w, 20, 260, 1.3, ax=3.0) * 6.0
    F1, edge, sid, _ = pvoronoi(rng, h, w, gx, gy, 0.95, warp=(wx, wx * 0.4), aspect=3.5)
    cell_h = h / gy
    fac = 1.0 - np.clip(edge / (0.55 * cell_h), 0.0, 1.0)
    ftone = cell_rand(rng, sid, gx * gy, -1, 1)
    facet_h = 0.0055 * fac ** 2 + 0.0015 * ftone
    grain = pnoise(rng, h, w, 1.6, 16, 0.6, ax=18.0)
    grain2 = pnoise(rng, h, w, 18, 160, 1.0, ax=22.0)
    tone_n = pnoise(rng, h, w, 100, 1000, 1.5, ax=5.0)
    bm = pnoise(rng, h, w, 12, 300, 1.4, ax=9.0) + 0.22 * pnoise(rng, h, w, 2, 14, 0.7, ax=5.0)
    thr = np.percentile(bm, 100 * (1 - bark))
    bark_m = sstep(thr - 0.05, thr + 0.07, bm)
    crack = np.zeros((h, w))
    spiral = rng.uniform(-0.04, 0.04)
    for _ in range(rng.poisson(checks * tile / 5.2)):
        big = rng.random() < 0.35
        crack_along_u(crack, rng, rng.uniform(0, w), rng.uniform(0, h), rng.uniform(0.8, 3.6 if big else 1.4) * ppx,
                      rng.uniform(1.6, 3.0) if big else rng.uniform(0.6, 1.3), slope=spiral + rng.uniform(-0.01, 0.01),
                      wob=1.4)
    knot = np.zeros((h, w))
    kring = np.zeros((h, w))
    for _ in range(rng.poisson(knots * tile / 5.2)):
        kx, ky = rng.uniform(0, w), rng.uniform(0, h)
        kr = rng.uniform(0.04, 0.1) * ppx
        idx, dx, dy = _win(kx, ky, kr * 3.5, kr * 3, h, w)
        d = np.sqrt((dx / 1.25) ** 2 + dy ** 2) / kr
        stamp_max(knot, idx, 1.0 - sstep(0.85, 1.05, d))
        stamp_max(kring, idx, np.exp(-((d - 1.25) / 0.3) ** 2) * 0.8)
    hgt = facet_h + 0.0012 * grain + 0.0014 * grain2 + 0.004 * bark_m * (0.6 + 0.4 * pnoise(rng, h, w, 1.5, 8, 0.5))
    hgt += 0.0025 * knot - 0.019 * crack
    silver = C(158, 153, 144)
    silver_d = C(126, 121, 113)
    honey = C(164, 136, 102)
    wm = np.clip(weather + 0.2 * tone_n + 0.1 * grain2, 0, 1)
    base = mixc(honey, silver, wm)
    base = mixc(base, mixc(C(140, 112, 82), silver_d, wm), sstep(0.2, 1.6, grain2) * 0.55)
    col = base * (1.0 + 0.09 * grain + 0.04 * tone_n + 0.035 * ftone)[..., None]
    col = col * (1.0 - 0.07 * fac)[..., None]
    bfib = norm01(pnoise(rng, h, w, 1.2, 10, 0.6, ax=6.0))
    bcol = mixc(C(64, 46, 36), C(98, 70, 50), bfib)
    bedge = np.clip(bark_m * (1 - bark_m) * 4.0, 0, 1)
    col = mixc(col, bcol, bark_m * 0.94)
    col = mixc(col, C(128, 102, 76), bedge * 0.35)
    col = mixc(col, C(80, 64, 50), kring * 0.5)
    col = mixc(col, mixc(C(92, 62, 40), C(72, 66, 60), wm), knot * 0.9)
    dk = sstep(1.0, 2.2, pnoise(rng, h, w, 3, 60, 0.8, ax=7.0) + 0.5 * pnoise(rng, h, w, 40, 300, 1.2, ax=6.0))
    col = mixc(col, C(76, 74, 70), dk * 0.42)
    sp = sstep(1.8, 2.6, pnoise(rng, h, w, 0.8, 3.0, 0.3)) * sstep(0.2, 1.4, pnoise(rng, h, w, 20, 300, 1.2, ax=5.0))
    col = mixc(col, C(50, 48, 46), sp * 0.6)
    lips = np.clip(pblur(crack, 1.8) * 1.7 - crack, 0, 1)
    col = mixc(col, C(178, 172, 162), lips * 0.2 * wm)
    col = mixc(col, C(38, 33, 29), crack * 0.93)
    pale, yel, dots = lichen_patches(rng, h, w, ppx, 0.025, scale=0.8, yellow=0.25)
    col, hgt = apply_lichen(col, hgt, pale, yel, dots, rng, 0.7)
    extra = None
    if contact:
        dv = np.minimum(Y, h - Y) / h
        extra = 1.0 - 0.5 * (1.0 - sstep(0.0, 0.2, dv)) ** 1.5
        sm = (1.0 - sstep(0.02, 0.14, dv)) * sstep(0.1, 0.9, pnoise(rng, h, w, 4, 90, 1.0, ax=4.0) + 0.2)
        sm = np.clip(sm * chink, 0, 1)
        col = mixc(col, C(170, 164, 152), sm * 0.7)
        hgt += 0.002 * sm
        col = col * (1.0 - 0.16 * (1.0 - sstep(0.0, 0.1, dv)))[..., None]
    rough = 0.84 + 0.06 * wm + 0.05 * bark_m + 0.1 * crack
    return finish(col, hgt, rough, ppx, ao_radius=0.05, ao_strength=1.15, extra_ao=extra)


def gen_bark(h, w, ppx, seed):
    """Pine / spruce bark for firewood, bench logs and rough poles, toned to sit with the TreesReal conifer bark:
    grey-brown scaly plates elongated along U (= the trunk axis) whose lower lips stand proud, separated by
    brown fissures; shed patches expose the smoother red-brown inner bark; a little pale lichen."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    gx = max(3, int(round(w / (0.26 * ppx))))
    gy = max(2, int(round(h / (0.115 * ppx))))
    wx = pnoise(rng, h, w, 20, 300, 1.3, ax=3.0) * 9.0 + pnoise(rng, h, w, 4, 20, 0.9) * 1.5
    wy = pnoise(rng, h, w, 10, 200, 1.3, ax=4.0) * 4.0 + pnoise(rng, h, w, 4, 20, 0.9) * 1.2
    F1, edge, sid, (sx, sy) = pvoronoi(rng, h, w, gx, gy, 0.95, warp=(wx, wy), aspect=2.2)
    nc = gx * gy
    cellh = h / gy
    r1, r2, r3, r4 = (cell_rand(rng, sid, nc) for _ in range(4))
    # scales overlap like shingles along the trunk: each tilts so the edge facing -U stands proud
    along = np.clip((sx - (X + wx)) / (cellh * 2.2 * 0.6), -1.0, 1.0)
    plate = sstep(0.0, 0.22 * cellh, edge)
    lip = (0.3 + 0.35 * r1 + (0.3 + 0.25 * r2) * along) * plate
    curl = (r3 > 0.55) * sstep(0.4, 1.0, along) * (1.0 - sstep(0.0, 0.18 * cellh, edge)) * 0.35
    clus = sstep(0.2, 1.4, pnoise(rng, h, w, 30, 220, 1.2) + 0.4 * pnoise(rng, h, w, 8, 40, 0.9))
    shed = ((r4 < 0.06 + 0.5 * clus) * sstep(0.05 * cellh, 0.3 * cellh, edge)).astype(np.float64)
    fine = 0.05 * pnoise(rng, h, w, 1.0, 5, 0.5) + 0.05 * pnoise(rng, h, w, 3, 14, 0.8, ax=3.0)
    rel = (lip + curl) * (1.0 - 0.7 * shed) - 0.15 * shed + fine - 0.25 * (1.0 - plate)
    hgt = rel * 0.022
    grey = C(140, 128, 116)
    brown = C(118, 98, 82)
    fresh = C(146, 98, 72)
    pale = C(168, 160, 148)
    col = mixc(grey, brown, np.clip(0.6 * r1 + 0.25 * pnoise(rng, h, w, 6, 40, 1.0), 0, 1))
    col = mixc(col, pale, sstep(0.55, 0.95, lip) * 0.12)
    col = mixc(col, fresh, shed * 0.8)
    fiss = mixc(C(70, 56, 46), C(92, 74, 60), norm01(pnoise(rng, h, w, 2, 10, 0.5)))
    col = mixc(fiss, col, sstep(0.0, 0.6, plate))
    col = col * (0.93 + 0.07 * pnoise(rng, h, w, 20, 140, 1.0))[..., None]
    pale_l, yel, dots = lichen_patches(rng, h, w, ppx, 0.035, mask=plate, scale=0.6, yellow=0.08)
    col, hgt = apply_lichen(col, hgt, pale_l, yel, dots, rng, 0.45)
    rough = 0.86 + 0.06 * (1 - plate) - 0.05 * shed
    return finish(col, hgt, rough, ppx, ao_radius=0.035, ao_strength=1.0, cav_strength=0.15, ao_min=0.5)


def gen_rope(h, w, ppx, seed, strands=3, twists=14, wire=False):
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    n_lay = strands * twists
    ph = (n_lay * X / w + strands * Y / h)
    f = ph % 1.0
    xs = (f - 0.5) * 2.0
    prof = np.sqrt(np.clip(1.0 - xs ** 2, 0.0, 1.0))
    sid = np.floor(ph).astype(np.int64) % strands
    # yarns / wires twisted the other way inside each strand
    yarn = np.sin(TAU * (n_lay * 5 * X / w - strands * 3 * Y / h))
    fuzz = pnoise(rng, h, w, 1.0, 4, 0.3)
    hgt = 0.012 * prof + 0.0015 * yarn * prof + (0.0004 if wire else 0.0012) * fuzz
    if wire:
        col = mixc(C(92, 94, 96), C(158, 160, 160), prof)
        rust = sstep(0.8, 2.0, pnoise(rng, h, w, 4, 90, 1.2, ax=3.0))
        col = mixc(col, C(118, 72, 44), rust * 0.75)
        col = col * (0.92 + 0.08 * yarn)[..., None]
        rough = 0.42 + 0.35 * rust + 0.1 * (1 - prof)
        metal = np.clip(0.95 - 0.9 * rust - 0.25 * (1 - prof), 0, 1)
        return finish(col, hgt, rough, ppx, ao_radius=0.02, ao_strength=1.2, metal=metal)
    tone = np.array([0.0, 0.5, 1.0])[sid]
    col = mixc(C(150, 126, 92), C(132, 112, 84), tone)
    col = mixc(col, C(118, 108, 92), sstep(-0.5, 1.5, pnoise(rng, h, w, 30, 500, 1.2, ax=4.0)) * 0.5)
    col = col * (0.88 + 0.1 * yarn + 0.05 * fuzz)[..., None]
    dirt = sstep(0.4, 1.6, pnoise(rng, h, w, 20, 400, 1.2, ax=5.0))
    col = mixc(col, C(84, 72, 58), dirt * 0.45)
    rough = 0.92 + 0.04 * fuzz
    return finish(col, hgt, rough, ppx, ao_radius=0.02, ao_strength=1.4)


def gen_end_disc(s, ppx, seed, fresh=False):
    """Round log end: rings round an off-centre pith, radial checks, chainsaw arcs, bark rim (disc radius 0.47 s)."""
    rng = np.random.default_rng(seed)
    Y, X = grid(s, s)
    cx, cy = s / 2, s / 2
    pr = 0.47 * s
    px_, py_ = cx + rng.uniform(-0.08, 0.08) * s, cy + rng.uniform(-0.08, 0.08) * s
    dx, dy = X - px_, Y - py_
    r = np.sqrt(dx * dx + dy * dy)
    th = np.arctan2(dy, dx)
    rw = r + 1.4 * np.sin(3 * th + rng.uniform(0, TAU)) * r / pr + pnoise(rng, s, s, 4, 40, 1.2) * 0.8
    ring = rng.uniform(2.4, 3.6)
    ph = (rw / ring) % 1.0
    late = sstep(0.6, 0.8, ph) * (1.0 - sstep(0.9, 1.0, ph))
    rd = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / pr
    crack = np.zeros((s, s))
    for _ in range(rng.integers(2, 6)):
        t0 = rng.uniform(-math.pi, math.pi)
        dth = np.angle(np.exp(1j * (th - t0 + 0.08 * np.sin(r * 0.2))))
        wid = rng.uniform(1.0, 2.6) / np.maximum(r, 1.0) * (0.4 + rd)
        crack = np.maximum(crack, np.exp(-(dth / wid) ** 2) * sstep(rng.uniform(0.15, 0.6), 0.95, rd))
    if not fresh:  # one big V check from the rim
        t0 = rng.uniform(-math.pi, math.pi)
        dth = np.angle(np.exp(1j * (th - t0)))
        crack = np.maximum(crack, np.exp(-(dth / (3.0 / np.maximum(r, 1.0) * rd * 1.6)) ** 2) * sstep(0.3, 0.9, rd))
    arcs = np.sin(TAU * np.sqrt((X - cx + 2.2 * s) ** 2 + (Y - cy) ** 2) / rng.uniform(4.5, 7.0))
    bark = sstep(0.9, 0.95, rd)
    hgt = 0.0016 * (late - 0.5) - 0.014 * crack + 0.0007 * arcs * (1 - bark) + 0.006 * bark
    hgt -= 0.01 * sstep(0.995, 1.06, rd)
    if fresh:
        early, latec = C(212, 176, 128), C(176, 128, 82)
        heart = 1.0 - sstep(0.35, 0.6, rd)
        early = mixc(early, C(196, 146, 96), heart * 0.6)
        latec = mixc(latec, C(160, 110, 70), heart * 0.6)
    else:
        early, latec = C(140, 132, 120), C(102, 96, 88)
    col = mixc(early, latec, late * 0.8)
    col = col * (0.9 + 0.1 * pnoise(rng, s, s, 8, 90, 1.2))[..., None]
    if not fresh:
        col = mixc(col, C(70, 66, 60), sstep(0.6, 1.6, pnoise(rng, s, s, 3, 30, 0.8)) * 0.4)
        col = mixc(col, C(86, 96, 70), sstep(0.75, 0.92, rd) * sstep(0.5, 1.5, pnoise(rng, s, s, 4, 40, 1.0)) * 0.5)
    col = mixc(col, C(40, 34, 28), crack * 0.9)
    col = mixc(col, C(70, 50, 38), bark)
    col = mixc(col, C(40, 32, 26), sstep(0.96, 1.02, rd))
    rough = 0.88 + 0.06 * crack
    return finish(col, hgt, rough, ppx, ao_radius=0.025, ao_strength=1.2)


# ================================================================================================
# STONE: fieldstone masonry, rock, chinking, concrete, ash
# ================================================================================================
STONE_TONES = [(130, 127, 120), (146, 142, 134), (114, 111, 106), (128, 120, 108), (104, 103, 101), (152, 148, 140),
               (122, 114, 104), (138, 133, 124), (98, 96, 92), (156, 150, 140), (118, 118, 116), (134, 124, 110)]


def _stone_surface(rng, h, w, ppx, sid, ncell):
    """Per-pixel stone colour + micro height for a field of stones identified by sid."""
    tones = np.array([C(*t) for t in STONE_TONES])
    pick = rng.integers(0, len(STONE_TONES), ncell)
    base = tones[pick][sid]
    var = cell_rand(rng, sid, ncell, 0.9, 1.08)
    base = base * var[..., None]
    grain = pnoise(rng, h, w, 1.0, 4, 0.4)
    mott = pnoise(rng, h, w, 14, 180, 1.4)
    blot = pnoise(rng, h, w, 5, 50, 1.1)
    col = base * (1.0 + 0.02 * grain + 0.08 * mott + 0.035 * blot)[..., None]
    speck = sstep(2.3, 2.9, pnoise(rng, h, w, 1.0, 3.0, 0.2)) * (cell_rand(rng, sid, ncell) > 0.55)
    col = mixc(col, C(60, 60, 60), speck * 0.3)
    rust = sstep(1.3, 2.3, pnoise(rng, h, w, 10, 140, 1.2)) * (cell_rand(rng, sid, ncell) > 0.65)
    col = mixc(col, C(142, 104, 72), rust * 0.3)
    micro = 0.0008 * grain + 0.004 * pnoise(rng, h, w, 6, 60, 1.2) + 0.002 * blot
    return col, micro


def _lichen(rng, h, w, mask, amount):
    li = spots(np.zeros((h, w)), rng, int(amount * 700 * w / 1024), 1.5, 9.0, soft=0.45, mask=mask)
    li2 = spots(np.zeros((h, w)), rng, int(amount * 80 * w / 1024), 1.0, 4.5, soft=0.4, mask=mask)
    return li, li2


def gen_masonry(h, w, ppx, seed, foot=False):
    """Fieldstone chimney / footing masonry: rounded and split stones of varied tone laid in rough courses,
    set in deep raked lime mortar (dark joints), chipped arrises, sparse lichen; the 'foot' variant adds
    ground damp, splash dirt and moss creeping up out of the joints."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    gy = max(2, int(round(h / (rng.uniform(0.40, 0.48) * ppx))))
    gx = max(3, int(round(w / (rng.uniform(0.7, 0.9) * ppx))))
    wx = pnoise(rng, h, w, 14, 200, 1.4) * 7.0 + pnoise(rng, h, w, 3, 12, 0.8) * 0.35
    wy = pnoise(rng, h, w, 14, 200, 1.4) * 4.0 + pnoise(rng, h, w, 3, 12, 0.8) * 0.35
    F1, edge, sid, (sx, sy) = pvoronoi(rng, h, w, gx, gy, 0.85, warp=(wx, wy), aspect=1.7)
    ncell = gx * gy
    mortar_w = rng.uniform(0.065, 0.08) * ppx * (1.0 + 0.3 * pnoise(rng, h, w, 20, 220, 1.0))
    e = edge - mortar_w * 0.5
    stone = sstep(-0.5, 0.6, e)
    bev = cell_rand(rng, sid, ncell, 0.06, 0.2) * ppx
    dome = np.sqrt(np.clip(1.0 - (1.0 - np.clip(e / bev, 0.0, 1.0)) ** 2, 0.0, 1.0))
    proud = cell_rand(rng, sid, ncell, 0.025, 0.06)
    tx = cell_rand(rng, sid, ncell, -1, 1)
    ty = cell_rand(rng, sid, ncell, -1, 1)
    Yw, Xw = Y + wy, X + wx
    tilt = (tx * (Xw - sx) + ty * (Yw - sy)) / ppx * 0.035
    big = pnoise(rng, h, w, 10, 100, 1.3)
    facet = np.abs(pnoise(rng, h, w, 6, 50, 1.1))
    hs = proud * dome + (0.012 * big + tilt - 0.006 * facet) * dome
    chip = sstep(1.1, 1.7, pnoise(rng, h, w, 4, 30, 0.8)) * (1.0 - sstep(0.06 * ppx, 0.2 * ppx, e))
    hs -= 0.014 * chip
    scol, micro = _stone_surface(rng, h, w, ppx, sid, ncell)
    # stronger stone-to-stone contrast: some stones darker / browner, a few pale quartzite
    kind = cell_rand(rng, sid, ncell)
    scol = mixc(scol, scol * 0.72, (kind < 0.25))
    scol = mixc(scol, mixc(scol, C(132, 108, 84), 0.6), (kind > 0.82) * (kind < 0.92))
    scol = mixc(scol, C(176, 172, 162), (kind > 0.94) * 0.7)
    mort_h = -0.035 + 0.005 * pnoise(rng, h, w, 1.5, 12, 0.5) + 0.008 * sstep(-mortar_w * 0.5, 0, e)
    hgt = (hs + micro * dome) * stone + mort_h * (1 - stone)
    mcol = mixc(C(132, 126, 114), C(104, 98, 88), norm01(pnoise(rng, h, w, 3, 40, 0.8)))
    mcol = mcol * (0.9 + 0.1 * pnoise(rng, h, w, 1.0, 4, 0.4))[..., None]
    gap = (1.0 - sstep(-0.35 * mortar_w, 0.15 * mortar_w, e)) * sstep(-0.9 * mortar_w, -0.35 * mortar_w, e)
    col = mixc(mcol, scol, stone)
    col = mixc(col, C(40, 38, 35), gap * 0.55)          # shadow line where stone meets the raked mortar
    col = mixc(col, mixc(scol, C(176, 172, 162), 0.45), chip * 0.35 * stone)
    col = col * (1.0 - 0.14 * (1 - dome) * stone)[..., None]
    streak = sstep(0.7, 1.9, pnoise(rng, h, w, 4, 220, 1.3, ay=7.0))
    col = mixc(col, C(76, 74, 68), streak * 0.22)
    lm = stone * sstep(0.0, 0.6, e / ppx * 10.0)
    pale, yel, dots = lichen_patches(rng, h, w, ppx, 0.07 if foot else 0.04, mask=lm, scale=0.9, yellow=0.18)
    col, hgt = apply_lichen(col, hgt, pale, yel, dots, rng, 0.6)
    extra = None
    if foot:
        g = 1.0 - sstep(0.0, 0.85 * h, Y)
        mz = np.clip((1.0 - stone) * 0.9 + g * 0.55, 0, 1) * sstep(-0.4, 0.8, pnoise(rng, h, w, 8, 110, 1.0) + g)
        mz = np.clip(mz, 0, 1)
        cush = moss_cushions(rng, h, w, ppx, 0.07)
        mossc = mixc(C(52, 66, 28), C(92, 110, 42), norm01(pnoise(rng, h, w, 1.2, 6, 0.4)))
        mossc = mossc * (0.72 + 0.4 * np.clip(cush, 0, 1))[..., None]
        col = col * (1.0 - 0.28 * g)[..., None]
        col = mixc(col, C(84, 70, 54), g ** 2 * 0.45)
        col = mixc(col, mossc, mz * 0.85)
        hgt += mz * (0.008 + 0.01 * np.clip(cush, 0, 1))
        extra = 1.0 - 0.22 * g
    rough = np.where(stone > 0.5, 0.8 + 0.06 * pnoise(rng, h, w, 6, 80, 1.0), 0.95)
    if foot:
        rough = rough - 0.12 * (1.0 - sstep(0.0, 0.6 * h, Y))
    return finish(col, hgt, rough, ppx, ao_radius=0.12, ao_strength=1.15, extra_ao=extra, blur_h=0.7, ao_min=0.36,
                  cav_strength=0.02)


def gen_rock(h, w, ppx, seed):
    """Weathered granite-gneiss surface for loose stones (campfire ring, footings, abutments)."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    big = pnoise(rng, h, w, 40, 700, 1.7)
    mid = pnoise(rng, h, w, 6, 70, 1.1)
    band = pnoise(rng, h, w, 6, 120, 1.2, ax=6.0, ay=1.0)
    ridged = 1.0 - np.abs(pnoise(rng, h, w, 10, 120, 1.2))
    crack = np.zeros((h, w))
    for _ in range(int(4 * w / 1024)):
        crack_along_u(crack, rng, rng.uniform(0, w), rng.uniform(0, h), rng.uniform(0.2, 0.6) * ppx,
                      rng.uniform(0.5, 1.2), slope=rng.uniform(-0.5, 0.5), wob=3.0)
    hgt = 0.022 * big + 0.006 * mid + 0.004 * ridged + 0.002 * band - 0.01 * crack
    grain = pnoise(rng, h, w, 1.0, 3.5, 0.3)
    base = mixc(C(138, 134, 126), C(116, 112, 105), sstep(-1, 1, big))
    base = mixc(base, C(140, 128, 112), sstep(0.6, 1.6, pnoise(rng, h, w, 30, 400, 1.3)) * 0.35)
    col = base * (1.0 + 0.035 * grain + 0.06 * mid + 0.05 * band)[..., None]
    col = mixc(col, C(54, 54, 54), sstep(2.0, 2.6, pnoise(rng, h, w, 1.0, 2.5, 0.2)) * 0.35)
    col = mixc(col, C(196, 192, 184), sstep(2.1, 2.7, pnoise(rng, h, w, 1.0, 2.5, 0.2)) * 0.3)
    pale, yel, dots = lichen_patches(rng, h, w, ppx, 0.1, scale=1.0, yellow=0.2)
    col, hgt = apply_lichen(col, hgt, pale, yel, dots, rng, 0.72)
    col = mixc(col, C(62, 60, 56), crack * 0.6)
    rough = 0.8 + 0.05 * mid + 0.08 * pale
    return finish(col, hgt, rough, ppx, ao_radius=0.06, ao_strength=1.0)


def gen_split(h, w, ppx, seed):
    """Split firewood face: long torn fibres and splinter ridges along U, pale fresh wood weathering to grey."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    fib = pnoise(rng, h, w, 1.2, 10, 0.5, ax=22.0)
    ridge = pnoise(rng, h, w, 6, 60, 1.1, ax=26.0)
    tear = np.abs(pnoise(rng, h, w, 3, 30, 0.9, ax=12.0))
    crack = np.zeros((h, w))
    for _ in range(int(14 * w / 1024)):
        crack_along_u(crack, rng, rng.uniform(0, w), rng.uniform(0.1 * h, 0.9 * h), rng.uniform(0.3, 1.6) * ppx,
                      rng.uniform(0.5, 1.2), slope=rng.uniform(-0.02, 0.02), wob=0.8)
    hgt = 0.003 * fib + 0.008 * ridge - 0.004 * tear - 0.01 * crack
    tone = norm01(pnoise(rng, h, w, 40, 600, 1.4, ax=6.0))
    col = mixc(C(196, 166, 124), C(160, 150, 136), tone * 0.8)
    col = mixc(col, C(170, 118, 76), sstep(0.4, 1.6, pnoise(rng, h, w, 10, 200, 1.2, ax=10.0)) * 0.35)
    col = col * (0.9 + 0.08 * fib + 0.06 * ridge)[..., None]
    col = mixc(col, C(110, 96, 80), sstep(0.8, 1.8, tear) * 0.35)
    col = mixc(col, C(54, 44, 36), crack * 0.85)
    rough = 0.86 + 0.06 * tear
    return finish(col, hgt, rough, ppx, ao_radius=0.03, ao_strength=1.1)


def gen_rock_burnt(h, w, ppx, seed):
    """Fire-ring stone: the rock surface blackened with soot, cracked by heat, dusted with ash."""
    base = gen_rock(h, w, ppx, seed)
    rng = np.random.default_rng(seed + 1)
    Y, X = grid(h, w)
    soot = sstep(-0.6, 0.9, pnoise(rng, h, w, 8, 160, 1.2) + 0.9 * (Y / h) - 0.2)
    col = base["albedo"]
    col = mixc(col, C(34, 32, 30), soot * 0.8)
    ash = sstep(1.0, 2.0, pnoise(rng, h, w, 2, 30, 0.8)) * sstep(0.5, 1.0, Y / h)
    col = mixc(col, C(150, 146, 140), ash * 0.5)
    crack = np.zeros((h, w))
    for _ in range(int(8 * w / 1024)):
        crack_along_u(crack, rng, rng.uniform(0, w), rng.uniform(0, h), rng.uniform(0.15, 0.5) * ppx,
                      rng.uniform(0.5, 1.0), slope=rng.uniform(-0.6, 0.6), wob=2.0)
    col = mixc(col, C(20, 18, 17), crack * 0.8)
    base["albedo"] = col
    base["rough"] = np.clip(base["rough"] + 0.06 * soot, 0, 1)
    return base


def gen_chinking(h, w, ppx, seed):
    """Lime / clay chinking seen between two logs: trowelled, cracked, dirty, shadowed under both logs."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    trowel = pnoise(rng, h, w, 8, 120, 1.2, ax=3.0)
    crack = np.zeros((h, w))
    for _ in range(int(9 * w / 1024)):
        crack_along_v(crack, rng, rng.uniform(0, w), rng.uniform(0.25 * h, 0.75 * h), rng.uniform(0.25, 0.6) * h,
                      rng.uniform(0.4, 0.9), slope=rng.uniform(-0.4, 0.4), wob=1.6)
    for _ in range(int(6 * w / 1024)):
        crack_along_u(crack, rng, rng.uniform(0, w), rng.uniform(0.3 * h, 0.7 * h), rng.uniform(0.1, 0.4) * ppx,
                      rng.uniform(0.4, 0.9), wob=1.6)
    grit = sstep(1.6, 2.4, pnoise(rng, h, w, 0.8, 3, 0.3))
    holes = sstep(1.7, 2.3, pnoise(rng, h, w, 3, 14, 0.8))
    dv = np.minimum(Y, h - Y) / h
    hgt = 0.0025 * trowel - 0.008 * crack - 0.01 * holes + 0.001 * grit + 0.004 * sstep(0.0, 0.3, dv)
    col = mixc(C(182, 176, 162), C(158, 148, 132), norm01(pnoise(rng, h, w, 10, 220, 1.2)))
    col = col * (0.95 + 0.05 * trowel)[..., None]
    col = mixc(col, C(124, 112, 96), sstep(0.5, 1.8, pnoise(rng, h, w, 4, 80, 1.0, ax=2.5)) * 0.4)
    col = mixc(col, C(110, 104, 94), grit * 0.4)
    col = mixc(col, C(96, 88, 76), holes * 0.7)
    col = mixc(col, C(84, 78, 70), crack * 0.6)
    mz = sstep(1.0, 2.0, pnoise(rng, h, w, 6, 80, 1.0)) * (1.0 - sstep(0.1, 0.3, dv))
    col = mixc(col, C(80, 96, 44), mz * 0.55)
    extra = 1.0 - 0.6 * (1.0 - sstep(0.0, 0.38, dv)) ** 1.6
    rough = 0.92 - 0.02 * trowel
    return finish(col, hgt, rough, ppx, ao_radius=0.04, ao_strength=1.0, extra_ao=extra)


def gen_concrete(h, w, ppx, seed):
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    agg = sstep(1.2, 1.9, pnoise(rng, h, w, 1.5, 6, 0.5))
    pores = sstep(2.0, 2.6, pnoise(rng, h, w, 0.8, 3, 0.3))
    mid = pnoise(rng, h, w, 6, 80, 1.2)
    form = np.sin(TAU * Y / (0.33 * ppx)) * 0.5 + 0.5
    hgt = 0.0015 * agg - 0.004 * pores + 0.0015 * mid + 0.0008 * sstep(0.9, 1.0, form)
    col = mixc(C(152, 149, 142), C(128, 125, 118), norm01(pnoise(rng, h, w, 20, 300, 1.2)))
    col = mixc(col, C(170, 164, 152), agg * 0.3)
    col = mixc(col, C(76, 74, 72), pores * 0.6)
    rs = sstep(0.8, 2.0, pnoise(rng, h, w, 6, 300, 1.3, ay=8.0))
    col = mixc(col, C(132, 92, 62), rs * 0.3)
    g = 1.0 - sstep(0.0, 0.5 * h, Y)
    dirt = np.clip(g * sstep(-0.5, 0.8, pnoise(rng, h, w, 6, 100, 1.0) + g), 0, 1)
    col = mixc(col, C(84, 72, 56), dirt * 0.55)
    mz = np.clip(g * sstep(0.4, 1.4, pnoise(rng, h, w, 4, 60, 1.0) + g * 0.6), 0, 1)
    col = mixc(col, C(72, 90, 40), mz * 0.6)
    pale, yel, dots = lichen_patches(rng, h, w, ppx, 0.06, scale=0.9, yellow=0.25)
    col, hgt = apply_lichen(col, hgt, pale, yel, dots, rng, 0.6)
    rough = 0.88 + 0.04 * mid
    return finish(col, hgt, rough, ppx, ao_radius=0.03, ao_strength=1.0)


def gen_ash(h, w, ppx, seed):
    """Campfire bed for a polar mapping: V 0 = centre (pale ash, charcoal bits), V 1 = rim (scorched earth)."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    t = Y / h
    lumps = sstep(1.0, 1.8, pnoise(rng, h, w, 1.5, 7, 0.6, ax=2.0))
    fine = pnoise(rng, h, w, 1.0, 6, 0.5, ax=2.0)
    hgt = 0.004 * lumps + 0.0015 * fine + 0.004 * pnoise(rng, h, w, 6, 60, 1.0, ax=2.0)
    ash = mixc(C(160, 156, 150), C(122, 118, 112), norm01(pnoise(rng, h, w, 3, 50, 1.0, ax=2.0)))
    char = mixc(C(36, 34, 32), C(62, 58, 54), norm01(fine))
    earth = mixc(C(74, 60, 46), C(56, 46, 38), norm01(pnoise(rng, h, w, 4, 80, 1.0, ax=2.0)))
    k = sstep(0.3, 0.8, t + 0.12 * pnoise(rng, h, w, 20, 300, 1.2, ax=2.0))
    col = mixc(ash, char, k * 0.85)
    col = mixc(col, earth, sstep(0.78, 1.0, t))
    col = mixc(col, C(30, 28, 27), lumps * 0.7 * (1 - sstep(0.85, 1.0, t)))
    col = mixc(col, C(176, 174, 168), sstep(1.6, 2.6, fine) * (1 - k) * 0.5)
    rough = 0.95 - 0.05 * lumps
    return finish(col, hgt, rough, ppx, ao_radius=0.02, ao_strength=0.8)


# ================================================================================================
# SHAKE: hand-split cedar shake courses, butts, moss cushion
# ================================================================================================
SHAKE_ROWS = [  # moss amount, debris, weathering, seed
    dict(moss=0.02, debris=0.15, weather=0.9, seed=301),
    dict(moss=0.06, debris=0.25, weather=0.95, seed=302),
    dict(moss=0.12, debris=0.35, weather=0.85, seed=303),
    dict(moss=0.2, debris=0.4, weather=0.9, seed=304),
    dict(moss=0.32, debris=0.5, weather=0.9, seed=305),
    dict(moss=0.45, debris=0.6, weather=0.8, seed=306),
    dict(moss=0.6, debris=0.7, weather=0.75, seed=307),
]


def _moss_colour(rng, h, w):
    a = norm01(pnoise(rng, h, w, 1.0, 5, 0.4))
    b = norm01(pnoise(rng, h, w, 8, 90, 1.0))
    col = mixc(C(50, 64, 26), C(98, 118, 42), a)
    col = mixc(col, C(122, 118, 60), sstep(0.68, 0.95, b) * 0.45)
    col = mixc(col, C(86, 74, 50), sstep(0.0, 0.22, b) * 0.4)
    return col


def gen_shake_course(h, w, ppx, moss=0.1, debris=0.3, weather=0.9, seed=1):
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    widths = periodic_widths(rng, w, 0.32 * ppx, 1.05 * ppx)
    edges = np.concatenate([[0.0], np.cumsum(widths)])
    col_idx = np.searchsorted(edges, X[0], side="right") - 1
    col_idx = np.clip(col_idx, 0, len(widths) - 1)
    ns = len(widths)
    left = edges[col_idx]
    wid = np.array(widths)[col_idx]
    loc = (X[0] - left) / wid
    gap_w = rng.uniform(1.5, 4.0, ns)[col_idx]
    dgap = np.minimum(X[0] - left, left + wid - X[0])
    gap = (1.0 - sstep(gap_w * 0.5, gap_w * 0.5 + 1.2, dgap))[None, :] * np.ones((h, 1))
    butt_off = rng.uniform(0.0, 0.035 * ppx, ns)[col_idx][None, :]
    cup = rng.uniform(-1, 1, ns)[col_idx][None, :]
    twist = rng.uniform(-1, 1, ns)[col_idx][None, :]
    tone = rng.uniform(0, 1, ns)[col_idx][None, :]
    warm = (rng.uniform(0, 1, ns) < 0.2)[col_idx][None, :]
    lc = (loc - 0.5)[None, :]
    yb = Y - butt_off
    grooves = pnoise(rng, h, w, 1.5, 22, 0.7, ay=10.0)
    deep = np.zeros((h, w))
    for _ in range(int(40 * w / 1024)):
        crack_along_v(deep, rng, rng.uniform(0, w), rng.uniform(0.2 * h, 1.0 * h), rng.uniform(0.3, 1.2) * h,
                      rng.uniform(0.5, 1.4), slope=rng.uniform(-0.06, 0.06), wob=1.0)
    deep *= rng.uniform(0.5, 1.0)
    hgt = (0.0045 * grooves + 0.0025 * pnoise(rng, h, w, 25, 250, 1.3, ay=4.0) + 0.006 * cup * lc ** 2 * 4.0
           + 0.004 * twist * lc - 0.012 * deep)
    hgt += 0.018 * (1.0 - Y / h)
    butt = 1.0 - sstep(0.0, 0.05 * h, yb)
    hgt -= 0.014 * butt ** 2
    hgt = hgt * (1 - gap) - 0.03 * gap
    hgt = np.where(yb < 0, hgt - 0.03, hgt)
    silver = C(152, 148, 140)
    dark = C(98, 94, 88)
    brown = C(124, 108, 92)
    base = mixc(silver, dark, tone * 0.75)
    base = mixc(base, brown, np.clip((1 - weather) * 0.6 + 0.5 * warm, 0, 1))
    col = base * (1.0 + 0.08 * grooves)[..., None]
    wet = sstep(0.4, 1.8, pnoise(rng, h, w, 4, 180, 1.2, ay=8.0))
    col = mixc(col, C(76, 74, 70), wet * 0.4)
    blk = sstep(1.6, 2.4, pnoise(rng, h, w, 0.8, 3.0, 0.3)) * sstep(0.0, 1.0, pnoise(rng, h, w, 20, 200, 1.0) + 0.3)
    col = mixc(col, C(40, 40, 38), blk * 0.6)
    col = mixc(col, C(40, 36, 32), np.clip(deep * 0.85 + gap * 0.95, 0, 1))
    col = mixc(col, C(66, 58, 50), butt * 0.35)
    # moss cushions grow out of the keyways and along the butt line
    near = np.clip(np.maximum((1.0 - sstep(0, 0.14 * ppx, dgap))[None, :] * np.ones((h, 1)),
                              1.0 - sstep(0, 0.4 * h, yb)), 0, 1)
    mn = pnoise(rng, h, w, 14, 260, 1.4) * 0.85 + 1.25 * near - 1.75 + moss * 3.4
    cush = moss_cushions(rng, h, w, ppx, 0.085)
    mm = sstep(0.0, 0.6, mn + 0.45 * (cush - 0.5))
    if moss > 0.001:
        mcol = _moss_colour(rng, h, w)
        mcol = mcol * (0.7 + 0.45 * np.clip(cush, 0, 1))[..., None]
        col = mixc(col, mcol, mm)
        hgt += mm * (0.012 + 0.016 * np.clip(cush, 0, 1))
        col = mixc(col, C(70, 88, 50), sstep(-0.7, 0.0, mn) * 0.22 * (1 - mm))  # green algae film
    if debris > 0:
        nd = np.zeros((h, w))
        for _ in range(int(debris * 240 * w / 1024)):
            cx, cy = rng.uniform(0, w), rng.uniform(0, h)
            L = rng.uniform(0.06, 0.16) * ppx
            a = rng.uniform(0, math.pi)
            idx, dx, dy = _win(cx, cy, L, L, h, w)
            along = dx * math.cos(a) + dy * math.sin(a)
            across = -dx * math.sin(a) + dy * math.cos(a)
            val = np.exp(-(across / 0.55) ** 2) * (np.abs(along) < L / 2)
            stamp_max(nd, idx, val)
        keep = np.clip(near * 1.2 + mm, 0, 1)
        nd = nd * keep
        col = mixc(col, C(126, 88, 56), nd * 0.8)
        hgt += 0.004 * nd
    shade = 1.0 - 0.6 * sstep(0.62 * h, 1.0 * h, Y)
    rough = 0.86 + 0.015 * grooves - 0.12 * wet + 0.08 * mm
    return finish(col, hgt, rough, ppx, ao_radius=0.06, ao_strength=1.2, extra_ao=shade)


def gen_shake_butt(h, w, ppx, seed):
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    widths = periodic_widths(rng, w, 0.32 * ppx, 1.05 * ppx)
    edges = np.concatenate([[0.0], np.cumsum(widths)])
    ci = np.clip(np.searchsorted(edges, X[0], side="right") - 1, 0, len(widths) - 1)
    dgap = np.minimum(X[0] - edges[ci], edges[ci] + np.array(widths)[ci] - X[0])
    gap = (1.0 - sstep(1.0, 2.5, dgap))[None, :] * np.ones((h, 1))
    rings = np.sin(TAU * (X / 6.0 + 2.0 * pnoise(rng, h, w, 8, 80, 1.0)))
    hgt = 0.002 * rings - 0.02 * gap + 0.002 * pnoise(rng, h, w, 1.5, 10, 0.6, ay=3.0)
    col = mixc(C(92, 84, 76), C(70, 64, 58), norm01(rings))
    col = col * (0.9 + 0.12 * norm01(pnoise(rng, h, w, 10, 120, 1.0)))[..., None]
    col = mixc(col, C(34, 30, 28), gap)
    col = col * (0.72 + 0.28 * sstep(0, h, Y))[..., None]
    rough = 0.9
    return finish(col, hgt, np.full((h, w), rough), ppx, ao_radius=0.02, ao_strength=1.0)


def gen_moss(h, w, ppx, seed):
    rng = np.random.default_rng(seed)
    cush = moss_cushions(rng, h, w, ppx, 0.08)
    fuzz = pnoise(rng, h, w, 0.8, 4, 0.3)
    hgt = 0.02 * np.clip(cush, 0, 1) + 0.003 * fuzz
    col = _moss_colour(rng, h, w)
    col = col * (0.62 + 0.5 * np.clip(cush, 0, 1) + 0.06 * fuzz)[..., None]
    rough = 0.93 + 0.03 * fuzz
    return finish(col, hgt, rough, ppx, ao_radius=0.03, ao_strength=1.3)


# ================================================================================================
# KIT: canvas, iron, tin, wire rope, char, ember, globe glass, blanket, window glass, leather, ticking
# ================================================================================================
def gen_canvas(h, w, ppx, seed):
    """Weathered cotton duck for a tent side: U along the ridge, V from the hem (V 0) to the ridge (V 1)."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    t = Y / h
    weave = 0.5 * (np.sin(TAU * X / 2.6) * np.sin(TAU * Y / 2.6))
    slub = pnoise(rng, h, w, 2, 30, 0.8, ax=6.0) * 0.5 + pnoise(rng, h, w, 2, 30, 0.8, ay=6.0) * 0.5
    folds = pnoise(rng, h, w, 40, 400, 1.6, ax=0.7, ay=2.0)
    hgt = 0.0004 * weave + 0.0006 * slub + 0.012 * folds
    # sewn seam at 55 % height (two rows of stitching) + a patch
    seam_y = 0.55 * h
    seam = np.exp(-((Y - seam_y) / 2.2) ** 2)
    stitch = (np.sin(TAU * X / 6.0) > 0.2) * (np.exp(-((Y - seam_y - 4.5) / 0.8) ** 2) + np.exp(-((Y - seam_y + 4.5) / 0.8) ** 2))
    hgt += 0.002 * seam + 0.0006 * stitch
    base = mixc(C(176, 162, 128), C(196, 186, 158), sstep(0.3, 1.0, t))  # sun-bleached toward the ridge
    base = base * (1.0 + 0.04 * slub + 0.02 * weave)[..., None]
    col = mixc(base, C(160, 148, 116), sstep(0.5, 1.6, folds) * 0.4)
    # tide-line water stains
    st = pnoise(rng, h, w, 30, 300, 1.4)
    tide = np.exp(-((st - 1.0) / 0.06) ** 2) * sstep(0.0, 0.6, 1 - t)
    col = mixc(col, C(132, 116, 86), np.clip(sstep(1.0, 1.4, st) * 0.25 + tide * 0.5, 0, 1))
    # splash dirt + mud at the hem, green-grey mildew blooms low down
    g = (1.0 - sstep(0.0, 0.38, t + 0.06 * pnoise(rng, h, w, 6, 120, 1.0)))
    col = mixc(col, C(98, 82, 62), g ** 1.5 * 0.85)
    spl = spots(np.zeros((h, w)), rng, int(500 * w / 1024), 0.8, 3.0, soft=0.5, mask=1 - sstep(0.1, 0.5, t))
    col = mixc(col, C(84, 70, 54), spl * 0.6)
    mil = spots(np.zeros((h, w)), rng, int(140 * w / 1024), 1.0, 5.0, soft=0.6,
                mask=sstep(0.2, 1.2, pnoise(rng, h, w, 20, 200, 1.0)) * (1 - sstep(0.2, 0.7, t)))
    col = mixc(col, C(90, 96, 80), mil * 0.5)
    # patch (darker, newer canvas, stitched border)
    pxc, pyc, pw, ph = rng.uniform(0.15, 0.85) * w, rng.uniform(0.25, 0.42) * h, rng.uniform(0.35, 0.55) * ppx, rng.uniform(0.3, 0.45) * ppx
    dx, dy = np.abs(((X - pxc + w / 2) % w) - w / 2), np.abs(Y - pyc)
    patch = (1.0 - sstep(pw - 1.0, pw + 1.0, dx)) * (1.0 - sstep(ph - 1.0, ph + 1.0, dy))
    border = patch * (1.0 - (1.0 - sstep(pw - 4.0, pw - 2.5, dx)) * (1.0 - sstep(ph - 4.0, ph - 2.5, dy)))
    col = mixc(col, C(150, 138, 104), patch * 0.85)
    col = mixc(col, C(110, 100, 78), border * 0.6)
    hgt += 0.0015 * patch
    col = mixc(col, C(128, 118, 92), seam * 0.5)
    col = mixc(col, C(110, 100, 80), stitch * 0.5)
    rough = 0.93 - 0.05 * g
    return finish(col, hgt, rough, ppx, ao_radius=0.04, ao_strength=0.7)


def gen_iron(h, w, ppx, seed):
    """Hand-forged strap iron: hammer dimples, black scale, orange-brown rust, pitting."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    gx, gy = max(3, int(w / (0.07 * ppx))), max(2, int(h / (0.07 * ppx)))
    F1, edge, sid, _ = pvoronoi(rng, h, w, gx, gy, 0.9)
    dimple = (F1 / (0.05 * ppx)) ** 2
    rustn = pnoise(rng, h, w, 4, 200, 1.3) + 0.4 * pnoise(rng, h, w, 1.5, 8, 0.6)
    rust = sstep(-0.3, 0.6, rustn)
    pits = spots(np.zeros((h, w)), rng, int(600 * w / 1024), 0.5, 1.6, soft=0.4, mask=rust)
    hgt = 0.0015 * np.clip(dimple, 0, 1) + 0.003 * rust * pnoise(rng, h, w, 1.0, 5, 0.5) - 0.003 * pits
    scale = mixc(C(46, 44, 43), C(70, 68, 66), norm01(pnoise(rng, h, w, 2, 30, 0.8)))
    rcol = mixc(C(110, 58, 30), C(150, 92, 52), norm01(pnoise(rng, h, w, 1.2, 10, 0.5)))
    rcol = mixc(rcol, C(76, 46, 32), sstep(0.6, 1.4, rustn) * 0.5)
    col = mixc(scale, rcol, rust)
    col = mixc(col, C(30, 22, 18), pits * 0.8)
    de = np.minimum(Y, h - Y) / h
    polish = (1.0 - sstep(0.0, 0.12, de)) * (1 - rust)
    col = mixc(col, C(118, 116, 112), polish * 0.5)
    rough = 0.55 + 0.38 * rust - 0.15 * polish
    metal = np.clip(0.92 - 0.88 * rust, 0, 1)
    return finish(col, hgt, rough, ppx, ao_radius=0.02, ao_strength=0.8, metal=metal)


def gen_tin(h, w, ppx, seed):
    """Lantern tinplate: dull grey, soot, rust freckles, worn bright edges."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    n = pnoise(rng, h, w, 3, 100, 1.2)
    rust = sstep(0.8, 1.8, n + 0.4 * pnoise(rng, h, w, 1.5, 6, 0.5))
    soot = sstep(0.3, 1.0, Y / h + 0.3 * pnoise(rng, h, w, 20, 200, 1.0))
    hgt = 0.0006 * pnoise(rng, h, w, 1.0, 6, 0.5) + 0.0015 * rust
    col = mixc(C(128, 128, 122), C(150, 150, 144), norm01(pnoise(rng, h, w, 10, 200, 1.0)))
    col = mixc(col, C(40, 38, 36), soot * 0.55)
    col = mixc(col, C(120, 70, 40), rust * 0.85)
    rough = 0.48 + 0.4 * rust + 0.2 * soot
    metal = np.clip(0.9 - 0.85 * rust - 0.5 * soot, 0, 1)
    return finish(col, hgt, rough, ppx, ao_radius=0.02, ao_strength=0.6, metal=metal)


def gen_char(h, w, ppx, seed):
    """Charred log surface: alligator cracking in the char, grey ash film on the ridges."""
    rng = np.random.default_rng(seed)
    gx, gy = max(3, int(w / (0.09 * ppx))), max(2, int(h / (0.07 * ppx)))
    F1, edge, sid, _ = pvoronoi(rng, h, w, gx, gy, 0.95, warp=(pnoise(rng, h, w, 4, 40, 1) * 2, 0))
    blk = sstep(0.5, 2.5, edge)
    hgt = 0.006 * blk + 0.002 * pnoise(rng, h, w, 1.2, 6, 0.5)
    col = mixc(C(20, 19, 18), C(44, 42, 40), norm01(pnoise(rng, h, w, 1.5, 12, 0.5)))
    ash = sstep(0.4, 1.4, pnoise(rng, h, w, 6, 80, 1.0)) * blk
    col = mixc(col, C(128, 124, 120), ash * 0.6)
    col = mixc(col, C(10, 9, 9), (1 - blk))
    brown = sstep(0.8, 1.8, pnoise(rng, h, w, 20, 300, 1.2, ax=4))
    col = mixc(col, C(70, 50, 36), brown * 0.4)
    rough = 0.82 + 0.1 * ash
    return finish(col, hgt, rough, ppx, ao_radius=0.02, ao_strength=1.2)


def gen_ember(h, w, ppx, seed):
    """Glowing coals: ash-grey char plates, cracks that glow where the bed is hot, a few fully glowing spots."""
    rng = np.random.default_rng(seed)
    gx, gy = max(3, int(w / (0.06 * ppx))), max(2, int(h / (0.06 * ppx)))
    F1, edge, sid, _ = pvoronoi(rng, h, w, gx, gy, 0.95)
    crack = 1.0 - sstep(0.3, 2.2, edge)
    heat = norm01(pnoise(rng, h, w, 8, 160, 1.3))
    hot = sstep(0.35, 0.8, heat)
    hgt = -0.004 * crack + 0.002 * pnoise(rng, h, w, 1.2, 6, 0.5)
    plate = mixc(C(30, 27, 25), C(58, 40, 30), hot * 0.6)
    ash = sstep(0.2, 1.2, pnoise(rng, h, w, 3, 40, 0.8)) * (1 - hot * 0.7)
    plate = mixc(plate, C(142, 138, 132), ash * 0.75)
    glow = mixc(C(220, 52, 8), C(255, 150, 50), heat)
    col = mixc(plate, glow, np.clip(crack * hot * 1.2, 0, 1))
    col = mixc(col, C(255, 104, 26), sstep(0.82, 1.0, heat) * sstep(0.0, 0.8, pnoise(rng, h, w, 2, 20, 0.8)) * 0.8)
    col = mixc(col, C(30, 27, 25), crack * (1 - hot) * 0.8)
    rough = 0.82
    return finish(col, hgt, np.full((h, w), rough), ppx, ao_radius=0.01, ao_strength=0.3)


def gen_globe(h, w, ppx, seed):
    """Lantern globe for a cylindrical mapping: U round, V bottom -> top. Clear glass, soot toward the top."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    t = Y / h
    soot = sstep(0.45, 1.0, t + 0.12 * pnoise(rng, h, w, 6, 200, 1.2))
    smudge = sstep(0.6, 1.6, pnoise(rng, h, w, 8, 200, 1.2))
    col = mixc(C(214, 220, 212), C(54, 48, 42), soot * 0.9)
    col = mixc(col, C(150, 146, 134), smudge * 0.4)
    alpha = np.clip(0.16 + 0.75 * soot + 0.25 * smudge, 0, 1)
    rough = 0.06 + 0.6 * soot + 0.25 * smudge
    hgt = 0.0003 * pnoise(rng, h, w, 4, 60, 1.0)
    out = finish(col, hgt, rough, ppx, ao_radius=0.01, ao_strength=0.0, alpha=alpha)
    return out


def gen_window_glass(h, w, ppx, seed):
    """Old window pane: grime and spider-web dust at the edges, rain spots and smears; alpha = coverage."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    de = np.minimum(np.minimum(X, w - X), np.minimum(Y, h - Y)) / min(h, w)
    edge = 1.0 - sstep(0.0, 0.22, de + 0.05 * pnoise(rng, h, w, 6, 80, 1.0))
    bottom = 1.0 - sstep(0.0, 0.35, Y / h)
    smear = sstep(0.2, 1.4, pnoise(rng, h, w, 10, 160, 1.3, ax=1.5))
    drops = spots(np.zeros((h, w)), rng, int(260 * w / 256), 0.6, 2.4, soft=0.6)
    grime = np.clip(0.55 * edge + 0.35 * bottom + 0.3 * smear + 0.35 * drops, 0, 1)
    col = mixc(C(150, 160, 156), C(104, 96, 80), grime)
    alpha = np.clip(0.2 + 0.7 * grime, 0, 1)
    rough = 0.08 + 0.55 * grime
    hgt = 0.0004 * pnoise(rng, h, w, 6, 100, 1.2)
    return finish(col, hgt, rough, ppx, ao_radius=0.01, ao_strength=0.0, alpha=alpha)


def gen_blanket(h, w, ppx, seed):
    """Heavy wool blanket: brick-red with a charcoal border stripe near V 0.15, felted and pilled."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    twill = np.sin(TAU * (X + Y) / 3.0)
    fuzz = pnoise(rng, h, w, 1.0, 5, 0.3)
    pill = spots(np.zeros((h, w)), rng, int(900 * w / 512), 0.6, 1.4, soft=0.6)
    folds = pnoise(rng, h, w, 30, 300, 1.5)
    hgt = 0.0005 * twill + 0.001 * fuzz + 0.001 * pill + 0.01 * folds
    base = mixc(C(112, 44, 36), C(132, 58, 44), norm01(pnoise(rng, h, w, 8, 200, 1.2)))
    t = Y / h
    stripe = sstep(0.1, 0.12, t) * (1 - sstep(0.2, 0.22, t)) + sstep(0.26, 0.27, t) * (1 - sstep(0.3, 0.31, t))
    base = mixc(base, C(44, 40, 38), stripe)
    col = base * (0.9 + 0.08 * twill + 0.08 * fuzz)[..., None]
    col = mixc(col, C(150, 140, 124), pill * 0.18)
    col = mixc(col, C(90, 72, 56), sstep(0.8, 1.8, pnoise(rng, h, w, 10, 200, 1.2)) * 0.35)
    rough = 0.95
    return finish(col, hgt, np.full((h, w), rough), ppx, ao_radius=0.03, ao_strength=0.7)


def gen_ticking(h, w, ppx, seed):
    """Old mattress ticking: faded grey-blue stripes on oatmeal, stained."""
    rng = np.random.default_rng(seed)
    Y, X = grid(h, w)
    s = (X / ppx) % 0.18
    stripe = sstep(0.0, 0.01, s) * (1 - sstep(0.035, 0.045, s)) + sstep(0.06, 0.065, s) * (1 - sstep(0.07, 0.075, s))
    col = mixc(C(178, 168, 146), C(92, 100, 112), stripe * 0.8)
    col = col * (0.94 + 0.06 * pnoise(rng, h, w, 1.0, 6, 0.4))[..., None]
    st = sstep(0.6, 1.6, pnoise(rng, h, w, 20, 200, 1.3))
    col = mixc(col, C(130, 110, 80), st * 0.45)
    hgt = 0.0004 * np.sin(TAU * Y / 2.5) + 0.006 * pnoise(rng, h, w, 20, 200, 1.4)
    return finish(col, hgt, np.full((h, w), 0.92), ppx, ao_radius=0.02, ao_strength=0.6)


def gen_leather(h, w, ppx, seed):
    rng = np.random.default_rng(seed)
    gx, gy = max(3, int(w / (0.03 * ppx))), max(2, int(h / (0.03 * ppx)))
    F1, edge, sid, _ = pvoronoi(rng, h, w, gx, gy, 0.9)
    grain = sstep(0.3, 1.6, edge)
    crease = sstep(0.8, 1.8, pnoise(rng, h, w, 6, 80, 1.2, ax=0.4))
    hgt = 0.0012 * grain - 0.003 * crease
    col = mixc(C(70, 46, 32), C(98, 66, 44), norm01(pnoise(rng, h, w, 8, 160, 1.2)))
    col = col * (0.9 + 0.1 * grain)[..., None]
    col = mixc(col, C(46, 30, 22), crease * 0.6)
    Y, X = grid(h, w)
    de = np.minimum(Y, h - Y) / h
    col = mixc(col, C(128, 98, 70), (1 - sstep(0.0, 0.12, de)) * 0.5)  # worn edges
    rough = 0.62 + 0.15 * crease + 0.1 * (1 - grain)
    return finish(col, hgt, rough, ppx, ao_radius=0.01, ao_strength=0.8)


# ================================================================================================
# Sheet assembly
# ================================================================================================
# Albedo calibration per region (sRGB multipliers): keeps weathered wood in the 120-145 band, canvas khaki rather
# than white, so the set sits at the same value as the TreesReal bark and GroundReal rock under one exposure.
REGION_TONE = {
    ("Wood", "board_silver"): 0.9, ("Wood", "board_grey"): 0.9, ("Wood", "board_brown"): 0.93,
    ("Wood", "board_crate"): 0.85, ("Wood", "beam"): 0.9, ("Wood", "board_lichen"): 0.9,
    ("Log", "pole"): 0.9, ("Log", "log_wall"): 0.86, ("Log", "split"): 0.88, ("Log", "end_fresh_0"): 0.88,
    # art direction: the bark read as pale grey "giraffe" plates next to the red-brown TreesReal conifer bark
    # (effective sRGB ~ 92/68/52); warm and darken it to the same forest
    ("Log", "bark"): (0.74, 0.64, 0.56),
    ("Log", "end_fresh_1"): 0.88, ("Kit", "canvas"): (0.86, 0.85, 0.8), ("Kit", "tin"): 0.85,
    ("Stone", "chinking"): 0.84, ("Stone", "rock"): 0.92, ("Stone", "ash"): 0.7, ("Stone", "rock_burnt"): 0.9,
}


def build_region(sheet, name):
    r = _build_region(sheet, name)
    t = REGION_TONE.get((sheet, name))
    if t is not None:
        f = np.array(t if isinstance(t, tuple) else (t, t, t), dtype=np.float64) ** 2.2
        r["albedo"] = r["albedo"] * f
    return r


def _build_region(sheet, name):
    x, y, w, h, pad, ppx = LAYOUT[sheet][name]
    info = region_info(sheet, name)
    ix, iy, iw, ih = info["px"]
    if sheet == "Wood":
        if name.startswith("end_sq"):
            k = int(name.split("_")[-1])
            return gen_end_square(iw, ppx, 140 + k, weather=0.55 + 0.06 * k)
        return gen_board(ih, iw, ppx, **BOARD_STYLES[name])
    if sheet == "Log":
        if name == "log_wall":
            return gen_log(ih, iw, ppx, 201, contact=True)
        if name == "pole":
            return gen_log(ih, iw, ppx, 202, contact=False, weather=0.9, bark=0.08, checks=11, knots=1.6)
        if name == "bark":
            return gen_bark(ih, iw, ppx, 203)
        if name == "rope":
            return gen_rope(ih, iw, ppx, 204, strands=3, twists=13)
        if name == "split":
            return gen_split(ih, iw, ppx, 205)
        if name.startswith("end_fresh"):
            return gen_end_disc(iw, ppx, 230 + int(name[-1]), fresh=True)
        if name.startswith("end_"):
            return gen_end_disc(iw, ppx, 210 + int(name[-1]))
    if sheet == "Stone":
        if name == "masonry":
            return gen_masonry(ih, iw, ppx, 401)
        if name == "masonry_foot":
            return gen_masonry(ih, iw, ppx, 402, foot=True)
        if name == "rock":
            return gen_rock(ih, iw, ppx, 403)
        if name == "rock_burnt":
            return gen_rock_burnt(ih, iw, ppx, 407)
        if name == "chinking":
            return gen_chinking(ih, iw, ppx, 404)
        if name == "concrete":
            return gen_concrete(ih, iw, ppx, 405)
        if name == "ash":
            return gen_ash(ih, iw, ppx, 406)
    if sheet == "Shake":
        if name.startswith("course_"):
            return gen_shake_course(ih, iw, ppx, **SHAKE_ROWS[int(name[-1])])
        if name == "butt":
            return gen_shake_butt(ih, iw, ppx, 320)
        if name == "moss":
            return gen_moss(ih, iw, ppx, 321)
    if sheet == "Kit":
        fn = {"canvas": gen_canvas, "iron": gen_iron, "tin": gen_tin, "char": gen_char, "ember": gen_ember,
              "globe": gen_globe, "blanket": gen_blanket, "glass": gen_window_glass, "leather": gen_leather,
              "ticking": gen_ticking}.get(name)
        if fn is not None:
            return fn(ih, iw, ppx, 500 + sorted(LAYOUT["Kit"]).index(name))
        if name == "wire":
            return gen_rope(ih, iw, ppx, 520, strands=6, twists=9, wire=True)
    raise KeyError("no generator for %s/%s" % (sheet, name))


def _place(dst, src, x, y, w, h, pad, full_width):
    """Write src (content) into dst's outer box, filling the pad with the periodic continuation."""
    ch, cw = src.shape[:2]
    if full_width:
        rows = (np.arange(h) - pad) % ch
        dst[y:y + h, 0:N] = src[rows][:, np.arange(N) % cw]
    else:
        rows = (np.arange(h) - pad) % ch
        cols = (np.arange(w) - pad) % cw
        dst[y:y + h, x:x + w] = src[rows][:, cols]


def build_sheet(sheet, out_dir, log=print):
    t0 = time.time()
    alb = np.zeros((N, N, 3))
    alb[:] = C(128, 120, 110)
    nrm = np.zeros((N, N, 3))
    nrm[..., 2] = 1.0
    rough = np.full((N, N), 0.9)
    metal = np.zeros((N, N))
    alpha = np.ones((N, N))
    stats = {}
    for name, (x, y, w, h, pad, ppx) in LAYOUT[sheet].items():
        t1 = time.time()
        r = build_region(sheet, name)
        full = w == N
        _place(alb, r["albedo"], x, y, w, h, pad, full)
        _place(nrm, r["normal"], x, y, w, h, pad, full)
        _place(rough, r["rough"], x, y, w, h, pad, full)
        if r.get("metal") is not None:
            _place(metal, r["metal"], x, y, w, h, pad, full)
        if r.get("alpha") is not None:
            _place(alpha, r["alpha"], x, y, w, h, pad, full)
        avg = lin_to_srgb(r["albedo"].reshape(-1, 3).mean(axis=0))
        stats[name] = {"avgRgb": [int(round(v * 255)) for v in avg]}
        log("  region %-14s %5.1fs avg sRGB %s" % (name, time.time() - t1, stats[name]["avgRgb"]))
    srgb = lin_to_srgb(alb)
    base = os.path.join(out_dir, PREFIX + sheet)
    files = {}
    if sheet == "Kit":
        files["color"] = write_png(base + "_Color.png", np.concatenate([srgb, alpha[..., None]], axis=-1))
    else:
        files["color"] = write_png(base + "_Color.png", srgb)
    files["normal"] = write_png(base + "_Normal.png", np.clip(nrm * 0.5 + 0.5, 0, 1))
    # packed roughness / metalness at half resolution (box filter). B carries a tiny dither on non-metal sheets
    # so the derived metalness image is never one flat colour (it stays below 1 % metalness).
    rh = rough.reshape(MR_N, 2, MR_N, 2).mean(axis=(1, 3))
    mh = metal.reshape(MR_N, 2, MR_N, 2).mean(axis=(1, 3))
    if sheet != "Kit":
        rng = np.random.default_rng(7)
        mh = np.maximum(mh, rng.integers(0, 3, (MR_N, MR_N)) / 255.0)
    # glTF packing lives in glb_only/ (embedded in the GLBs, never uploaded) so the upload folder holds only the
    # 16 SurfaceAppearance images
    os.makedirs(os.path.join(out_dir, "glb_only"), exist_ok=True)
    files["mr"] = write_png(os.path.join(out_dir, "glb_only", PREFIX + sheet + "_MR.png"), np.stack([rh, rh, mh], axis=-1))
    # the same roughness as a plain 8-bit grayscale PNG (SurfaceAppearance.RoughnessMap), so the integrator never
    # depends on the importer splitting the packed glTF map
    files["roughness"] = write_png(base + "_Roughness.png", rh)
    if sheet == "Kit":
        files["metal"] = write_png(base + "_Metal.png", mh)
    sizes = {k: os.path.getsize(v) for k, v in files.items()}
    log("SHEET %s %.1fs  %s" % (sheet, time.time() - t0,
                                 ", ".join("%s %.2f MB" % (k, s / 1048576.0) for k, s in sizes.items())))
    return {"files": {k: os.path.basename(v) for k, v in files.items()}, "regions": stats}


def layout_json():
    out = {}
    for sheet in SHEETS:
        out[sheet] = {}
        for name in LAYOUT[sheet]:
            out[sheet][name] = region_info(sheet, name)
    return out


def build_all(out_dir, only=None, log=print):
    os.makedirs(out_dir, exist_ok=True)
    meta = {}
    path = os.path.join(out_dir, PREFIX + "layout.json")
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                meta = json.load(f).get("sheets", {})
        except Exception:
            meta = {}
    for sheet in SHEETS:
        if only and sheet not in only:
            continue
        meta[sheet] = build_sheet(sheet, out_dir, log)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"sheets": meta, "layout": layout_json()}, f, indent=1)
    return meta


def files_for(sheet):
    base = PREFIX + sheet
    out = {"color": base + "_Color.png", "normal": base + "_Normal.png", "mr": "glb_only/" + base + "_MR.png",
           "roughness": base + "_Roughness.png"}
    if sheet == "Kit":
        out["metal"] = base + "_Metal.png"
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else os.path.join(os.getcwd(), "textures")
    only = set(argv[1].split(",")) if len(argv) > 1 and argv[1] not in ("", "all") else None
    build_all(out, only)
