"""
tex_landmarks.py - PBR texture builder for the LandmarksReal set (LAST STANDING), Blender 5.3 headless.

All maps are synthesised procedurally (seeded numpy inside Blender's Python): physical height fields in studs
(tool marks, grains, pits, joints, rings, rivets ...) -> OpenGL normal maps; albedo and roughness are built from
the same fields, with cavity/ambient occlusion baked in. Everything is periodic in U (and in V for the granite
tile), so the sheets tile without seams. Five materials, 3 images each = 15 PNGs (<= 16 per set), 1024x1024.

Sheets (1 stud = 0.33 m). "px/stud" is the texel density.
  LR_Granite    tile, 4 x 4 studs, 256 px/stud: weathered grey granite, boasted tool marks, pits, spalls,
                hairline cracks, crustose lichen, rain streaks.
  LR_StoneTrim  trim strips, tileable in U (4 studs), 256 px/stud:
                  rows    0-255  DAMP   granite rows 768-1023 of the tile + rising damp, splash dirt, moss foot
                  rows  256-639  RUST   granite rows 0-383 of the tile + rust streaks running down from iron above
                  rows  640-767  MOSS   joint fill: moss cushions, soil, grit (V = across the joint)
                  rows  768-1023 SETTS  three courses of granite setts with mossy joints (cobbled ring)
                DAMP and RUST continue the granite tile exactly, so a face split at the band line is seamless.
  LR_Wood       trim strips along the grain (U, 4 studs), 256 px/stud: 3 weathered plank faces (0.75 stud),
                1 hewn beam face (1 stud), end grain cells (5 x 0.75 stud).
  LR_Iron       trim strips (U, 4 studs), 256 px/stud, METAL: forged strap, forged bar, worn steel, diamond tread
                plate, soot/charcoal.
  LR_Misc       clay pantiles (2 courses, 192 px/stud), half-round ridge tiles, 3-strand hemp rope, and the banner
                cloth with the Cleft sigil.

Each material: <name>_Color.png (sRGB), <name>_Normal.png (OpenGL, +Y up), <name>_Rough.png (8-bit grayscale,
Roblox-ready: authored roughness + ROBLOX_ROUGH_OFFSET), LR_Iron_Metal.png (8-bit grayscale metalness, the only
metal sheet) and <name>_MR.png (glTF packing R = G = roughness, B = metalness; embedded in the GLB, never uploaded
on its own). Upload set: 5 colour + 5 normal + 5 roughness + 1 metalness = 16 images.
Row 0 of every array = V 0 (bottom of the image).

Run standalone:  blender --background --factory-startup --python tex_landmarks.py -- <texture_dir>
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
PPS = 256.0                     # stone / wood / iron density (px per stud)
GRANITE_STUDS = 4.0             # granite tile = 4 x 4 studs
TRIM_STUDS = 4.0                # U period of every trim strip except the roof

# ----------------------------------------------------------------------------------------------- UV layout (rows)
# (row0, row1) of each strip; V = row / 1024. Users map V inside [row0 + PAD, row1 - PAD].
PAD = 3
STONE_STRIPS = {"DAMP": (0, 256), "RUST": (256, 640), "MOSS": (640, 768), "SETTS": (768, 1024)}
STONE_STRIP_STUDS = {"DAMP": 1.0, "RUST": 1.5, "MOSS": 0.5, "SETTS": 1.0}
WOOD_STRIPS = {"PLANK0": (0, 192), "PLANK1": (192, 384), "PLANK2": (384, 576), "BEAM": (576, 832),
               "END": (832, 1024)}
WOOD_END_CELLS = 5              # end grain cells of 192 x 192 px (0.75 stud) in the END row, 64 px spare at the right
IRON_STRIPS = {"STRAP": (0, 256), "BAR": (256, 512), "STEEL": (512, 768), "TREAD": (768, 960), "SOOT": (960, 1024)}
MISC_STRIPS = {"ROOF": (0, 384), "RIDGE": (384, 512), "ROPE": (512, 576), "BANNER": (576, 1024)}
ROOF_PPS = 192.0                # roof strip: 1024 px = 5.333 studs (8 tiles), 2 courses of 1 stud
ROOF_PERIOD_STUDS = N / ROOF_PPS
BANNER_LEN, BANNER_WID = 6.7, 3.2   # banner region: U along the length (U 0 = top hem), V across the width

MATERIALS = ["LR_Granite", "LR_StoneTrim", "LR_Wood", "LR_Iron", "LR_Misc"]
METAL_MATERIALS = {"LR_Iron"}


ROBLOX_ROUGH_OFFSET = 0.08      # LookDevPlaybook s.11: Roblox renders ~0.1 glossier than Blender at equal roughness


def files_for(mat):
    """Colour + normal + grayscale roughness (+ grayscale metalness for metal) are the SurfaceAppearance maps to
    upload; _MR is the glTF metallicRoughness packing embedded in the GLB."""
    out = {"color": mat + "_Color.png", "normal": mat + "_Normal.png", "rough": mat + "_Rough.png"}
    if mat in METAL_MATERIALS:
        out["metal"] = mat + "_Metal.png"
    out["mr"] = "glb_only/" + mat + "_MR.png"      # embedded in the GLB only: kept out of the upload folder
    return out


# =============================================================================================== PNG writer
def _filter_rows(raw, ft, bpp):
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
        out = r - np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, c))
    return (out & 0xFF).astype(np.uint8)


def write_png(path, img, dither=True, seed=1):
    """img: float 0..1, H x W or H x W x C, row 0 = BOTTOM (V = 0). 8-bit gray / RGB / RGBA PNG."""
    a = np.asarray(img, dtype=np.float64) * 255.0
    if dither:
        rng = np.random.default_rng(seed)
        a = a + (rng.random(a.shape[:2]) - 0.5)[..., None] if a.ndim == 3 else a + (rng.random(a.shape) - 0.5)
    arr = np.flipud(np.clip(np.round(a), 0, 255).astype(np.uint8))
    h, w = arr.shape[:2]
    ch = 1 if arr.ndim == 2 else arr.shape[2]
    raw = arr.reshape(h, w * ch)
    best = None
    for ft in (1, 2, 4):
        data = np.concatenate([np.full((h, 1), ft, np.uint8), _filter_rows(raw, ft, ch)], axis=1).tobytes()
        comp = zlib.compress(data, 9)
        if best is None or len(comp) < len(best):
            best = comp

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, {1: 0, 3: 2, 4: 6}[ch], 0, 0, 0)))
        f.write(chunk(b"IDAT", best))
        f.write(chunk(b"IEND", b""))
    return path


# =============================================================================================== small helpers
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _is_rgb(x):
    x = np.asarray(x)
    return x.ndim == 3 or (x.ndim == 1 and x.shape[0] == 3)


def lerp(a, b, t):
    """a + (b - a) * t; a 2D weight is broadcast over RGB when a or b is a colour."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    t = np.asarray(t, dtype=np.float64)
    if t.ndim == 2 and (_is_rgb(a) or _is_rgb(b)):
        t = t[..., None]
    return a + (b - a) * t


def lin(r, g, b):
    c = np.array([r, g, b], dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def lum(c):
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def fnoise(rng, h, w, pps, lo, hi, beta=2.0, aniso=1.0):
    """Periodic band-limited noise (zero mean, unit std). lo/hi in cycles per stud. aniso > 1 stretches features
    along V (streaks), aniso < 1 along U (grain)."""
    fy = np.fft.fftfreq(h, d=1.0 / pps)[:, None]
    fx = np.fft.rfftfreq(w, d=1.0 / pps)[None, :]
    f = np.sqrt(fx ** 2 + (fy * aniso) ** 2)
    amp = np.zeros_like(f)
    m = f > 0
    amp[m] = f[m] ** (-beta / 2.0)
    amp *= smoothstep(lo * 0.7, lo, f) * (1.0 - smoothstep(hi, hi * 1.4, f))
    out = np.fft.irfft2(np.fft.rfft2(rng.standard_normal((h, w))) * amp, s=(h, w))
    s = out.std()
    return (out - out.mean()) / (s if s > 0 else 1.0)


def blur(img, sigma):
    """Periodic Gaussian blur (sigma in px)."""
    if img.ndim == 3:
        return np.stack([blur(img[..., c], sigma) for c in range(img.shape[2])], axis=-1)
    h, w = img.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.fft.irfft2(np.fft.rfft2(img) * g, s=(h, w))


def worley(rng, h, w, ny, nx, jitter=0.9):
    """Periodic jittered-grid Worley noise. Returns F1, F2 (px), cell id, and (dx, dy) to the nearest point."""
    cy, cx = h / ny, w / nx
    px = (np.arange(nx)[None, :] + 0.5 + (rng.random((ny, nx)) - 0.5) * jitter) * cx
    py = (np.arange(ny)[:, None] + 0.5 + (rng.random((ny, nx)) - 0.5) * jitter) * cy
    yy = (np.arange(h) + 0.5)[:, None]
    xx = (np.arange(w) + 0.5)[None, :]
    ci = np.floor(yy / cy).astype(np.int64)
    cj = np.floor(xx / cx).astype(np.int64)
    F1 = np.full((h, w), np.inf)
    F2 = np.full((h, w), np.inf)
    ID = np.zeros((h, w), np.int64)
    DX = np.zeros((h, w))
    DY = np.zeros((h, w))
    for di in (-1, 0, 1):
        for dj in (-1, 0, 1):
            ii = ci + di
            jj = cj + dj
            iw = ii % ny
            jw = jj % nx
            pxx = px[iw, jw] + (jj - jw) * cx
            pyy = py[iw, jw] + (ii - iw) * cy
            dx = xx - pxx
            dy = yy - pyy
            d = np.sqrt(dx * dx + dy * dy)
            closer = d < F1
            F2 = np.where(closer, F1, np.minimum(F2, d))
            F1 = np.where(closer, d, F1)
            ID = np.where(closer, iw * nx + jw, ID)
            DX = np.where(closer, dx, DX)
            DY = np.where(closer, dy, DY)
    return F1, F2, ID, DX, DY


def grad(hgt, pps, wrap_v=True):
    gx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5 * pps
    if wrap_v:
        gy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5 * pps
    else:
        gy = np.gradient(hgt, axis=0) * pps
    return gx, gy


def normal_map(hgt, pps, strength=1.0, wrap_v=True):
    """Height (studs) -> encoded OpenGL tangent-space normal (H x W x 3, 0..1)."""
    gx, gy = grad(hgt, pps, wrap_v)
    nx, ny = -gx * strength, -gy * strength
    nz = np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5


def occlusion(hgt, pps, scales=((2.0, 70.0), (8.0, 30.0), (24.0, 12.0)), floor=0.45):
    """Cavity / ambient occlusion from height: how far a texel sits below its blurred surroundings."""
    ao = np.zeros_like(hgt)
    for sigma, k in scales:
        ao += np.clip(blur(hgt, sigma) - hgt, 0.0, None) * k
    return np.clip(1.0 - ao, floor, 1.0)


def wrapdist(a, b, period):
    d = np.abs(a - b) % period
    return np.minimum(d, period - d)


def sd_polygon(px, py, poly):
    """Signed distance (px) from points to a closed polygon (negative inside). px, py broadcastable arrays."""
    d = np.full(np.broadcast(px, py).shape, np.inf)
    inside = np.zeros(d.shape, bool)
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        ex, ey = x1 - x0, y1 - y0
        wx, wy = px - x0, py - y0
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey + 1e-12), 0.0, 1.0)
        dx, dy = wx - ex * t, wy - ey * t
        d = np.minimum(d, dx * dx + dy * dy)
        cond = ((y0 <= py) & (py < y1)) | ((y1 <= py) & (py < y0))
        xint = x0 + (py - y0) * ex / (ey + 1e-12)
        inside ^= cond & (px < xint)
    return np.where(inside, -1.0, 1.0) * np.sqrt(d)


# =============================================================================================== GRANITE
def granite_fields(seed=7101):
    """Weathered grey granite tile (4 x 4 studs). Returns dict(albedo linear HxWx3, height studs, rough)."""
    n, pps = N, PPS
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)

    # ---- minerals: feldspar (light, some pink), smoky quartz, black mica/hornblende (3-4 mm grains)
    G = 300
    F1, F2, gid, _, _ = worley(rng, n, n, G, G, 0.95)
    gv = rng.random(G * G)[gid]
    gb = rng.random(G * G)[gid]
    gp = rng.random(G * G)[gid]
    mica = gv < 0.09
    quartz = (gv >= 0.09) & (gv < 0.4)
    feld_col = lerp(lin(164, 160, 153), lin(168, 152, 142), (gp > 0.72).astype(float))
    col = np.where(mica[..., None], lin(66, 66, 68) * (0.85 + 0.3 * gb[..., None]),
                   np.where(quartz[..., None], lin(124, 124, 127) * (0.9 + 0.2 * gb[..., None]),
                            feld_col * (0.92 + 0.14 * gb[..., None])))
    edge = smoothstep(0.0, 1.3, F2 - F1)
    col *= (0.93 + 0.07 * edge)[..., None]
    fine = fnoise(rng, n, n, pps, 30, 128, 1.0)
    col *= (1.0 + 0.03 * fine)[..., None]
    fresh = col.copy()
    # weathering: grains blend into a grey-beige skin, more in some places than others
    wmix = np.clip(0.68 + 0.12 * fnoise(rng, n, n, pps, 0.3, 4, 2.4), 0.45, 0.88)
    col = lerp(col, lin(130, 125, 116) * (1.0 + 0.025 * fine)[..., None], wmix)

    mott = fnoise(rng, n, n, pps, 0.25, 6, 2.6)
    col *= (1.0 + 0.22 * mott)[..., None]
    col *= (1.0 + 0.07 * fnoise(rng, n, n, pps, 0.5, 2, 2.0))[..., None]      # block-scale tone (per UV offset)
    hue = fnoise(rng, n, n, pps, 0.25, 3, 2.6)
    col *= (1.0 + 0.03 * hue[..., None] * np.array([1.0, 0.35, -0.8]))

    # ---- height: undulation of the dressed face
    h = 0.010 * fnoise(rng, n, n, pps, 0.25, 3, 3.0)
    # ---- boasted tool marks: patches of parallel chisel grooves, each patch its own direction (periodic)
    Fp1, Fp2, pid, _, _ = worley(rng, n, n, 3, 3, 0.8)
    kx = np.zeros(9)
    ky = np.zeros(9)
    dep = np.zeros(9)
    for p in range(9):
        ang = math.radians(rng.uniform(60, 84)) * (1 if rng.random() < 0.5 else -1) + (math.pi if rng.random() < 0.5 else 0)
        kmag = n / rng.uniform(11.0, 15.0)
        kx[p] = round(kmag * math.cos(ang))
        ky[p] = round(kmag * math.sin(ang))
        dep[p] = rng.uniform(0.0011, 0.0024)
    phase = TAU * (kx[pid] * xx + ky[pid] * yy) / n + 1.3 * fnoise(rng, n, n, pps, 0.3, 3, 3.0)
    groove = (0.5 + 0.5 * np.cos(phase)) ** 5
    stroke = smoothstep(-0.5, 0.6, fnoise(rng, n, n, pps, 2, 14, 1.6))
    tool = dep[pid] * stroke * smoothstep(0, 12, Fp2 - Fp1)
    h -= tool * groove
    # ---- grain relief (quartz stands proud of weathered feldspar)
    h += np.where(quartz, 0.0005, 0.0) - np.where(mica, 0.0003, 0.0) - 0.0004 * (1.0 - edge)
    h += 0.00035 * fine
    # ---- pits
    Fq, _, qid, _, _ = worley(rng, n, n, 26, 26, 0.95)
    qr = rng.uniform(1.5, 7.0, 26 * 26)[qid]
    qon = (rng.random(26 * 26) < 0.5)[qid]
    pit = np.where(qon, np.clip(1.0 - Fq / qr, 0.0, 1.0) ** 0.6, 0.0)
    h -= rng.uniform(0.003, 0.008) * pit
    # ---- spalls (old flakes, sharp rim, fresher stone inside)
    sp = fnoise(rng, n, n, pps, 0.3, 4, 2.8) + 0.25 * fnoise(rng, n, n, pps, 4, 30, 1.4)
    spall = smoothstep(1.7, 1.85, sp)
    h -= 0.006 * spall
    # ---- hairline cracks
    cn = fnoise(rng, n, n, pps, 0.6, 8, 2.2)
    cmask = smoothstep(0.5, 1.0, fnoise(rng, n, n, pps, 0.3, 3, 2.5))
    crack = smoothstep(0.035, 0.0, np.abs(cn)) * cmask
    h -= 0.0028 * crack

    # ---- crustose "map" lichen: irregular lobed patches with a thin dark margin (prothallus), areolate crust
    lich = np.zeros((n, n))
    lich_col = np.zeros((n, n, 3))
    margin = np.zeros((n, n))
    Fa, Fa2, _, _, _ = worley(rng, n, n, 150, 150, 0.95)
    areole = smoothstep(0.0, 1.8, Fa2 - Fa)
    species = [(lin(136, 139, 127), 1.3), (lin(146, 145, 138), 1.95), (lin(144, 140, 110), 2.2)]
    for scol, thr in species:
        fld = fnoise(rng, n, n, pps, 0.5, 5, 2.3) + 0.32 * fnoise(rng, n, n, pps, 5, 45, 1.3)
        cov = smoothstep(thr, thr + 0.05, fld)
        mg = smoothstep(thr - 0.06, thr - 0.005, fld) * (1.0 - cov)
        tex_c = scol * (0.9 + 0.12 * areole)[..., None] * (1.0 + 0.05 * fnoise(rng, n, n, pps, 3, 30, 1.6))[..., None]
        lich_col = np.where((cov > lich)[..., None], tex_c, lich_col)
        lich = np.maximum(lich, cov)
        margin = np.maximum(margin, mg)
    dots_F, _, did, _, _ = worley(rng, n, n, 128, 128, 0.95)
    don = rng.random(128 * 128)[did]
    dmask = smoothstep(1.0, 1.6, fnoise(rng, n, n, pps, 0.5, 4, 2.4))
    orange = np.where(don < 0.25, smoothstep(2.2, 1.0, dots_F), 0.0) * smoothstep(2.2, 2.6, fnoise(rng, n, n, pps, 0.5, 4, 2.4))
    black = np.where(don < 0.35, smoothstep(1.9, 0.9, dots_F), 0.0) * dmask
    h += 0.0009 * lich * areole + 0.0005 * orange

    # ---- rain streaks: vertical darkening and a few dark drip lines
    st = fnoise(rng, n, n, pps, 0.4, 10, 1.6, aniso=7.0)
    streak = smoothstep(0.4, 2.0, st) * 0.28
    drip = smoothstep(1.9, 2.8, fnoise(rng, n, n, pps, 1.0, 30, 1.2, aniso=9.0)) * 0.22
    streak = np.clip(streak + drip, 0, 0.42)

    # ---- compose albedo
    col = lerp(col, fresh * 1.04, spall * 0.55)
    col *= (1.0 - 0.45 * crack)[..., None]
    col *= (1.0 - 0.3 * pit)[..., None]
    col *= (1.0 - streak)[..., None]
    col = lerp(col, lich_col, lich * 0.6)
    col *= (1.0 - 0.18 * margin)[..., None]
    col = lerp(col, lin(176, 116, 54), orange * 0.8)
    col = lerp(col, lin(44, 44, 42), black * 0.8)
    ao = occlusion(h, pps)
    col *= ao[..., None]

    rough = 0.83 + 0.035 * fine - 0.06 * quartz + 0.03 * mica
    rough = lerp(rough, 0.93, lich)
    rough = np.maximum(rough, 0.95 * np.maximum(crack, pit))
    rough = lerp(rough, 0.78, spall)
    return {"albedo": col, "height": h, "rough": np.clip(rough, 0.5, 0.98)}


# =============================================================================================== STONE TRIM
def damp_strip(g, rng):
    """Rising damp, splash dirt and a moss foot over granite tile rows 768..1023 (contact edge = row 0)."""
    h0, h1 = STONE_STRIPS["DAMP"]
    H = h1 - h0
    A = g["albedo"][768:1024].copy()
    Ht = g["height"][768:1024].copy()
    R = g["rough"][768:1024].copy()
    z = ((np.arange(H) + 0.5) / PPS)[:, None] * np.ones((1, N))          # studs above the contact
    tide = 0.42 + 0.11 * fnoise(rng, H, N, PPS, 0.25, 3, 2.5) + 0.03 * fnoise(rng, H, N, PPS, 3, 20, 1.5)
    damp = smoothstep(tide + 0.07, tide - 0.06, z) * (0.78 + 0.22 * fnoise(rng, H, N, PPS, 1, 12, 1.8).clip(-1, 1))
    damp = np.clip(damp, 0, 1)
    Fs, _, sid, _, _ = worley(rng, H, N, 22, 88, 0.95)
    s_on = rng.random(22 * 88)[sid]
    splash = np.where(s_on < 0.35 * 1.0, smoothstep(2.4, 0.6, Fs), 0.0) * np.exp(-z / 0.22)
    mline = 0.02 + 0.05 * np.clip(fnoise(rng, H, N, PPS, 0.5, 6, 2.0) + 0.4, 0, 2.5) ** 1.5
    fuzz = fnoise(rng, H, N, PPS, 30, 110, 1.0)
    moss = smoothstep(mline + 0.012, mline - 0.025, z + 0.012 * fuzz)
    moss *= smoothstep(-0.9, 0.2, fnoise(rng, H, N, PPS, 0.7, 8, 2.0))       # gaps: bare damp stone
    # fade every effect to zero at the top edge, so the band meets the clean tile above invisibly
    top = smoothstep(1.0, 0.82, z)
    damp *= top
    splash *= top
    algae = lin(96, 104, 78)
    A = A * (1.0 - 0.42 * damp)[..., None]
    A = lerp(A, algae * (lum(A) / 0.18)[..., None] * 0.55, 0.22 * damp)
    A = lerp(A, lin(66, 54, 42), np.clip(splash * 0.75, 0, 1))
    mcol = lerp(lin(50, 60, 28), lin(92, 102, 46), smoothstep(-1.2, 1.4, fnoise(rng, H, N, PPS, 4, 60, 1.2)))
    mcol = lerp(mcol, lin(44, 40, 32), smoothstep(0.03, 0.0, z)[..., None] * 0.6)
    A = lerp(A, mcol * (0.85 + 0.25 * fuzz.clip(-1, 1))[..., None], moss)
    Ht = Ht + moss * (0.008 + 0.004 * fuzz) + 0.0
    R = lerp(R, 0.68, 0.55 * damp)
    R = lerp(R, 0.96, moss)
    return A, Ht, R


def rust_strip(g, rng):
    """Rust staining running down from iron above, over granite tile rows 0..383 (iron sits at the top edge)."""
    r0, r1 = STONE_STRIPS["RUST"]
    H = r1 - r0
    A = g["albedo"][0:H].copy()
    Ht = g["height"][0:H].copy()
    R = g["rough"][0:H].copy()
    zz = ((np.arange(H) + 0.5) / PPS)[:, None]
    d = (H / PPS - zz) * np.ones((1, N))                                 # studs below the iron
    x = np.arange(N)[None, :] * np.ones((H, 1))
    wob = 6.0 * fnoise(rng, H, N, PPS, 0.4, 6, 2.2, aniso=0.35)
    stain = np.zeros((H, N))
    ns = 26
    xs = np.sort(rng.uniform(0, N, ns))
    for i in range(ns):
        w = rng.uniform(6, 46)
        L = rng.uniform(0.25, 1.35)
        a = rng.uniform(0.35, 1.0)
        dx = wrapdist(x + wob * (0.5 + d), xs[i], N)
        width = w * (1.0 - 0.45 * np.clip(d / (L * 1.4), 0, 1))
        stain += a * np.exp(-(dx / width) ** 2) * np.exp(-d / L)
        if rng.random() < 0.55:                                           # a thin drip trail runs further
            xd = xs[i] + rng.uniform(-0.4, 0.4) * w
            stain += 0.6 * a * np.exp(-(wrapdist(x + wob * 1.5, xd, N) / rng.uniform(1.5, 3.2)) ** 2) * np.exp(-d / (L * 2.2))
    breakup = 0.75 + 0.25 * fnoise(rng, H, N, PPS, 2, 30, 1.4, aniso=4.0)
    wash = np.exp(-d / 0.07) * (0.55 + 0.45 * fnoise(rng, H, N, PPS, 1, 20, 1.6).clip(-1, 1))
    r = np.clip(stain * breakup + wash, 0.0, 1.0)
    r *= smoothstep(1.5, 1.2, d)                                          # nothing at the bottom edge
    tint = np.array([1.18, 0.72, 0.44])
    A = A * lerp(np.ones(3), tint, np.clip(r * 1.1, 0, 1))
    A = lerp(A, lin(98, 60, 38), np.clip(r - 0.55, 0, 1) * 0.8)
    R = R + 0.04 * r
    return A, Ht, R


def moss_strip(rng):
    """Joint fill seen between flagstones and blocks: moss cushions, soil, grit. V = across the joint."""
    r0, r1 = STONE_STRIPS["MOSS"]
    H = r1 - r0
    v = ((np.arange(H) + 0.5) / H)[:, None] * np.ones((1, N))
    across = np.abs(v - 0.5) * 2.0
    Fm, Fm2, mid, _, _ = worley(rng, H, N, 22, 176, 0.95)
    dome = np.clip(1.0 - (Fm / 4.2) ** 2, 0, 1)
    tone = rng.random(22 * 176)[mid]
    clump = fnoise(rng, H, N, PPS, 1.2, 10, 1.8)
    cover = smoothstep(-0.35, 0.45, clump + 0.55 - 1.2 * across)
    soil = lerp(lin(46, 38, 30), lin(74, 62, 48), smoothstep(-1, 1, fnoise(rng, H, N, PPS, 4, 60, 1.2)))
    mcol = lerp(lin(46, 56, 26), lin(96, 104, 48), np.clip(tone * 0.7 + 0.25 * clump + 0.15, 0, 1))
    mcol = mcol * (0.72 + 0.32 * dome)[..., None]
    # a few dry grass blades lying in the joint
    gr = smoothstep(2.1, 2.6, fnoise(rng, H, N, PPS, 6, 80, 1.0, aniso=0.08))
    mcol = lerp(mcol, lin(128, 120, 78), gr * 0.7)
    A = lerp(soil, mcol, cover)
    Fg, _, gid, _, _ = worley(rng, H, N, 10, 80, 0.9)
    gon = rng.random(10 * 80)[gid]
    grit = np.where(gon < 0.25, smoothstep(3.2, 1.6, Fg), 0.0)
    A = lerp(A, lin(120, 116, 108) * (0.8 + 0.4 * gon / 0.25)[..., None], grit * (1 - cover * 0.6))
    A *= (0.5 + 0.5 * smoothstep(1.0, 0.55, across))[..., None]          # shadow under the stone edges
    Ht = 0.016 * (1.0 - across ** 2) + cover * 0.006 * dome + 0.004 * grit
    R = np.clip(0.93 + 0.04 * clump - 0.05 * grit, 0.8, 1.0)
    return A, Ht, R


def setts_strip(g, rng):
    """Three courses of granite setts (cobbled ring), mossy joints. Tileable in U (4 studs)."""
    r0, r1 = STONE_STRIPS["SETTS"]
    H = r1 - r0
    A = np.zeros((H, N, 3))
    Ht = np.full((H, N), -0.035)
    R = np.full((H, N), 0.95)
    cover = np.zeros((H, N))
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    rows = [0, 86, 171, 256]
    gA, gH, gR = g["albedo"], g["height"], g["rough"]
    edge_n = 2.2 * fnoise(rng, H, N, PPS, 6, 40, 1.4)
    for c in range(3):
        y0, y1 = rows[c] + 4, rows[c + 1] - 4
        x = rng.uniform(0, N)
        start = x
        lengths = []
        total = 0.0
        while total < N - 150:
            L = rng.uniform(78, 138)
            lengths.append(L)
            total += L
        scale = N / total
        lengths = [L * scale for L in lengths]
        for L in lengths:
            x0, x1 = x + 4.5, x + L - 4.5
            cxm, hw = (x0 + x1) / 2, (x1 - x0) / 2
            cym, hh = (y0 + y1) / 2 + rng.uniform(-2, 2), (y1 - y0) / 2 + rng.uniform(-2, 1)
            dxp = np.abs(((xx - cxm + N / 2) % N) - N / 2)
            dyp = np.abs(yy - cym)
            rr = 9.0
            qx = np.maximum(dxp - (hw - rr), 0.0)
            qy = np.maximum(dyp - (hh - rr), 0.0)
            sd = np.sqrt(qx * qx + qy * qy) + np.minimum(np.maximum(dxp - (hw - rr), dyp - (hh - rr)), 0.0) - rr
            sd = sd + edge_n
            inside = sd < 0
            if not inside.any():
                x += L
                continue
            prof = 1.0 - np.exp(np.minimum(sd, 0.0) / 7.0)
            tilt = (rng.uniform(-1, 1) * ((xx - cxm + N / 2) % N - N / 2) / hw + rng.uniform(-1, 1) * (yy - cym) / hh)
            hs = rng.uniform(-0.006, 0.004) + 0.012 * prof + 0.002 * tilt - 0.006 * (dxp / hw) ** 2 * 0.5
            ox, oy = int(rng.integers(0, N)), int(rng.integers(0, N))
            src_rows = (np.arange(H) + oy) % N
            sA = gA[src_rows][:, (np.arange(N) + ox) % N]
            sH = gH[src_rows][:, (np.arange(N) + ox) % N]
            sR = gR[src_rows][:, (np.arange(N) + ox) % N]
            tint = np.array([1.0, 1.0, 1.0]) * rng.uniform(0.82, 1.12)
            k = rng.random()
            if k < 0.25:
                tint *= np.array([0.94, 0.98, 1.06])
            elif k < 0.4:
                tint *= np.array([1.06, 0.99, 0.94])
            col = sA * tint * (0.82 + 0.18 * prof)[..., None]
            wear = smoothstep(0.4, 1.0, prof)
            A = np.where(inside[..., None], col, A)
            Ht = np.where(inside, hs + 0.4 * sH, Ht)
            R = np.where(inside, lerp(sR, 0.62, wear * 0.55), R)
            cover = np.where(inside, 1.0, cover)
            x += L
    # joints: soil, grit, moss
    jm = fnoise(rng, H, N, PPS, 2, 25, 1.5)
    jcol = lerp(lin(50, 42, 34), lin(62, 72, 34), smoothstep(-0.3, 0.9, jm))
    Fj, _, jid, _, _ = worley(rng, H, N, 64, 256, 0.95)
    jdome = np.clip(1.0 - (Fj / 2.6) ** 2, 0, 1)
    jcol = jcol * (0.75 + 0.3 * jdome)[..., None]
    A = np.where(cover[..., None] > 0, A, jcol)
    Ht = np.where(cover > 0, Ht, -0.03 + 0.012 * smoothstep(-0.3, 1.0, jm) * jdome)
    ao = occlusion(Ht, PPS, scales=((2.0, 40.0), (6.0, 25.0), (16.0, 10.0)), floor=0.5)
    A *= ao[..., None]
    return A, Ht, R


def build_stone(tex_dir, g=None, seed=7202):
    rng = np.random.default_rng(seed)
    g = g or granite_fields()
    # --- LR_Granite
    gn = normal_map(g["height"], PPS, 1.15)
    save_material(tex_dir, "LR_Granite", g["albedo"], gn, g["rough"], None)
    # --- LR_StoneTrim
    A = np.zeros((N, N, 3))
    Hh = np.zeros((N, N))
    R = np.zeros((N, N))
    NM = np.zeros((N, N, 3))
    parts = {"DAMP": damp_strip(g, rng), "RUST": rust_strip(g, rng), "MOSS": moss_strip(rng),
             "SETTS": setts_strip(g, rng)}
    for key, (a, h, r) in parts.items():
        r0, r1 = STONE_STRIPS[key]
        A[r0:r1], Hh[r0:r1], R[r0:r1] = a, h, r
    # DAMP + RUST continue the granite tile (rows 768..1023 then 0..383), so their normals use one stack
    stack = np.concatenate([Hh[0:640], g["height"][384:768]], axis=0)  # wraps back to tile row 768 = DAMP row 0
    NM[0:640] = normal_map(stack, PPS, 1.15)[0:640]
    for key in ("MOSS", "SETTS"):
        r0, r1 = STONE_STRIPS[key]
        NM[r0:r1] = normal_map(Hh[r0:r1], PPS, 1.15, wrap_v=False)
    save_material(tex_dir, "LR_StoneTrim", A, NM, R, None, normal_ready=True)
    return g


# =============================================================================================== WOOD
def wood_face(rng, H, kind, plank_seed_tint=None):
    """Weathered, silvered timber face, grain along U. H rows (across the grain). Returns albedo, height, rough."""
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    ring_px = rng.uniform(7.0, 11.0) if kind == "plank" else rng.uniform(8.0, 13.0)
    warp = 2.2 * fnoise(rng, H, N, PPS, 0.25, 3, 3.0, aniso=0.12) + 0.5 * fnoise(rng, H, N, PPS, 1, 10, 2.0, aniso=0.2)
    q = yy / ring_px + warp + int(rng.integers(-2, 3)) * xx / N      # integer drift keeps U periodic
    # knots bend the grain around them
    knots = []
    nk = rng.integers(0, 3) if kind == "plank" else rng.integers(1, 3)
    for _ in range(nk):
        kx, ky = rng.uniform(0, N), rng.uniform(0.2, 0.8) * H
        sx, sy = rng.uniform(10, 22), rng.uniform(7, 14) * (H / 192.0)
        dxk = ((xx - kx + N / 2) % N) - N / 2
        g = np.exp(-(dxk / (sx * 3.2)) ** 2 - ((yy - ky) / (sy * 2.2)) ** 2)
        q += 2.4 * g * np.tanh((yy - ky) / (sy * 0.8))
        knots.append((kx, ky, sx, sy))
    fq = q - np.floor(q)
    late = np.exp(-((fq - 0.82) / 0.07) ** 2)
    fib = fnoise(rng, H, N, PPS, 4, 120, 1.2, aniso=0.06)
    hgt = -0.0042 * (1.0 - late) + 0.0006 * fib
    if kind == "beam":                                                # hewing scallops across the grain
        sc = 0.5 + 0.5 * np.cos(TAU * (xx / rng.uniform(70, 95) + 0.3 * fnoise(rng, H, N, PPS, 0.5, 4, 2.0)))
        hgt -= 0.006 * sc ** 2 * (0.6 + 0.4 * fnoise(rng, H, N, PPS, 0.5, 4, 2.0).clip(-1, 1))
    # checks: long cracks along the grain
    crack = np.zeros((H, N))
    nck = rng.integers(2, 5) if kind == "plank" else rng.integers(4, 7)
    for _ in range(nck):
        cyc = rng.uniform(0.15, 0.85) * H
        x0 = rng.uniform(0, N)
        L = rng.uniform(60, 300) if kind == "plank" else rng.uniform(150, 600)
        wmax = rng.uniform(0.6, 1.5) if kind == "plank" else rng.uniform(1.0, 2.8)
        t = (((xx - x0) % N) / L)
        on = t < 1.0
        w = wmax * np.clip(np.sin(np.pi * np.clip(t, 0, 1)), 0, 1) ** 0.7
        path = cyc + 1.0 * np.sin(TAU * t * rng.uniform(0.2, 0.7) + rng.uniform(0, TAU)) + ring_px * 0.25 * warp
        dd = np.abs(yy - path)
        crack = np.maximum(crack, np.where(on, smoothstep(w + 1.0, w * 0.2, dd), 0.0))
    hgt -= 0.012 * crack
    # knot cores
    knot = np.zeros((H, N))
    for kx, ky, sx, sy in knots:
        dxk = ((xx - kx + N / 2) % N) - N / 2
        r = np.sqrt((dxk / sx) ** 2 + ((yy - ky) / sy) ** 2)
        knot = np.maximum(knot, smoothstep(1.15, 0.7, r))
        hgt -= 0.003 * smoothstep(1.2, 0.2, r)
    # colour: silver-grey weathering over brown wood, darker in eroded earlywood, black fungal streaks
    base_brown = lin(116, 94, 72) * rng.uniform(0.92, 1.06)
    silver = lin(132, 127, 119) * rng.uniform(0.9, 1.05)
    weather = np.clip(0.72 + 0.18 * fnoise(rng, H, N, PPS, 0.3, 6, 2.2, aniso=0.3), 0.35, 1.0)
    col = lerp(base_brown, silver, weather)
    streaks = fnoise(rng, H, N, PPS, 1, 60, 1.3, aniso=0.05)
    col = col * (0.76 + 0.34 * late)[..., None] * (1.0 + 0.05 * fib + 0.07 * streaks)[..., None]
    fung = smoothstep(0.5, 2.0, fnoise(rng, H, N, PPS, 0.5, 10, 1.8, aniso=0.12))
    col = lerp(col, lin(70, 68, 64), fung * 0.6)
    col = lerp(col, lin(76, 58, 42), knot * 0.85)
    col = lerp(col, lin(46, 40, 34), crack * 0.85)
    rough = np.clip(0.8 + 0.05 * fib + 0.1 * crack - 0.04 * late, 0.6, 0.98)
    return col, hgt, rough


def nail_stains(rng, col, hgt, rough, H, every_px, rows):
    """Iron nail heads with black tannin stains and a short rust run along the grain."""
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    for x0 in np.arange(rng.uniform(40, 120), N, every_px):
        for fy in rows:
            cx, cy = (x0 + rng.uniform(-6, 6)) % N, fy * H + rng.uniform(-4, 4)
            dx = ((xx - cx + N / 2) % N) - N / 2
            r = np.sqrt(dx ** 2 + (yy - cy) ** 2)
            head = smoothstep(4.2, 3.0, r)
            halo = np.exp(-(r / rng.uniform(9, 16)) ** 2) * 0.75
            run = np.exp(-(np.abs(yy - cy) / 3.0) ** 2) * np.exp(-np.abs(dx) / rng.uniform(20, 45)) * 0.45
            st = np.clip(halo + run, 0, 1) * (1 - head)
            col[:] = lerp(col, col * np.array([0.42, 0.4, 0.4]), st)
            col[:] = lerp(col, lin(52, 46, 42), head)
            hgt[:] = hgt + 0.003 * head * (1.0 - (r / 4.2) ** 2).clip(0, 1)
            rough[:] = lerp(rough, 0.6, head)


def end_grain(rng, S):
    """Weathered end grain, S x S px: rings around an off-centre pith, radial checks, saw marks."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    pcx, pcy = S * rng.uniform(0.25, 0.75), S * rng.uniform(0.25, 0.75)
    if rng.random() < 0.4:
        pcx = S * rng.choice([-0.3, 1.3])
    dx, dy = xx - pcx, yy - pcy
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    wob = 1.5 * np.sin(ang * 3 + rng.uniform(0, TAU)) + 1.0 * np.sin(ang * 7 + rng.uniform(0, TAU))
    q = (r + wob) / rng.uniform(5.0, 7.5)
    fq = q - np.floor(q)
    late = np.exp(-((fq - 0.85) / 0.08) ** 2)
    hgt = -0.002 * (1 - late)
    crack = np.zeros((S, S))
    for _ in range(rng.integers(2, 5)):
        a0 = rng.uniform(-np.pi, np.pi)
        da = np.abs(((ang - a0 + np.pi) % TAU) - np.pi) * r
        L = rng.uniform(0.35, 0.9) * S
        w = 0.6 + 2.6 * np.clip(1 - r / L, 0, 1)
        crack = np.maximum(crack, smoothstep(w + 0.6, w * 0.4, da) * (r < L))
    saw = 0.5 + 0.5 * np.sin(TAU * (xx * 0.9 + yy * 0.3) / rng.uniform(9, 14))
    hgt += -0.0012 * saw - 0.02 * crack
    col = lerp(lin(118, 108, 96), lin(146, 138, 126), late) * (0.9 + 0.1 * saw)[..., None]
    col *= (0.92 + 0.12 * np.clip(r / S, 0, 1))[..., None]
    col = lerp(col, lin(52, 44, 38), crack * 0.8)
    rough = np.clip(0.88 + 0.08 * crack, 0, 1)
    return col, hgt, rough


def build_wood(tex_dir, seed=7303):
    rng = np.random.default_rng(seed)
    A = np.zeros((N, N, 3))
    Hh = np.zeros((N, N))
    R = np.zeros((N, N))
    NM = np.zeros((N, N, 3))
    for key in ("PLANK0", "PLANK1", "PLANK2", "BEAM"):
        r0, r1 = WOOD_STRIPS[key]
        H = r1 - r0
        kind = "beam" if key == "BEAM" else "plank"
        col, hgt, rough = wood_face(rng, H, kind)
        if kind == "plank":
            nail_stains(rng, col, hgt, rough, H, 512, (0.3, 0.7))
        # weathering is strongest near the arrises: lighter edges, dirt in the centre line
        v = ((np.arange(H) + 0.5) / H)[:, None]
        edge = smoothstep(0.12, 0.0, np.minimum(v, 1 - v))
        col = col * (1.0 + 0.08 * edge)[..., None]
        ao = occlusion(hgt, PPS, scales=((1.5, 40.0), (5.0, 25.0), (14.0, 10.0)), floor=0.45)
        col *= ao[..., None]
        A[r0:r1], Hh[r0:r1], R[r0:r1] = col, hgt, rough
        NM[r0:r1] = normal_map(hgt, PPS, 1.0, wrap_v=False)
    r0, r1 = WOOD_STRIPS["END"]
    S = r1 - r0
    for i in range(WOOD_END_CELLS):
        col, hgt, rough = end_grain(rng, S)
        ao = occlusion(hgt, PPS, scales=((1.5, 40.0), (5.0, 20.0)), floor=0.5)
        x0 = i * S
        A[r0:r1, x0:x0 + S] = col * ao[..., None]
        Hh[r0:r1, x0:x0 + S] = hgt
        R[r0:r1, x0:x0 + S] = rough
    # spare 64 px column: weathered grey (filler, never mapped)
    A[r0:r1, WOOD_END_CELLS * S:] = A[r0:r1, 0:N - WOOD_END_CELLS * S]
    Hh[r0:r1, WOOD_END_CELLS * S:] = Hh[r0:r1, 0:N - WOOD_END_CELLS * S]
    R[r0:r1, WOOD_END_CELLS * S:] = R[r0:r1, 0:N - WOOD_END_CELLS * S]
    NM[r0:r1] = normal_map(Hh[r0:r1], PPS, 1.0, wrap_v=False)
    save_material(tex_dir, "LR_Wood", A, NM, R, None, normal_ready=True)


# =============================================================================================== IRON
def forged(rng, H, kind):
    """Old forged iron outdoors: hammer facets under an almost continuous skin of brown rust over dark scale,
    crusty orange-brown blooms, pitting, and bare metal only where the arrises are worn. Scale and rust are
    dielectric (metal 0); only the worn edges are metal. Returns albedo, height, rough, metal."""
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    cells = (max(2, H // 22), N // 22) if kind == "strap" else (max(2, H // 14), N // 34)
    F1, F2, fid, DX, DY = worley(rng, H, N, cells[0], cells[1], 0.9)
    cs = N / cells[1]
    facet = -0.0032 * (1.0 - np.clip((F1 / (cs * 0.75)) ** 2, 0, 1))
    hgt = facet + 0.0007 * fnoise(rng, H, N, PPS, 8, 60, 1.4)
    big = fnoise(rng, H, N, PPS, 0.3, 6, 2.2)
    mid = fnoise(rng, H, N, PPS, 3, 30, 1.5)
    fine = fnoise(rng, H, N, PPS, 20, 120, 1.0)
    rust = smoothstep(-1.9, 0.2, big + 0.35 * mid)                  # brown rust skin: nearly all the surface
    heavy = smoothstep(1.45, 2.2, big + 0.45 * mid)                  # crusty blooms, a few per metre
    Fp, _, pid, _, _ = worley(rng, H, N, max(2, H // 8), N // 8, 0.95)
    pon = rng.random(max(2, H // 8) * (N // 8))[pid]
    pit = np.where(pon < 0.22, smoothstep(2.2, 0.8, Fp), 0.0) * (0.25 + 0.75 * rust)
    hgt += 0.0013 * heavy * (0.6 + 0.4 * fine.clip(-1, 1)) + 0.0004 * rust * mid.clip(-1, 1) - 0.0024 * pit
    v = ((np.arange(H) + 0.5) / H)[:, None] * np.ones((1, N))
    ew = smoothstep(-0.6, 1.0, fnoise(rng, H, N, PPS, 0.8, 10, 1.8))
    edge = smoothstep(0.06, 0.0, np.minimum(v, 1 - v)) * ew * (1.0 - heavy)
    scale_col = lerp(lin(54, 50, 47), lin(68, 62, 57), smoothstep(-1, 1, mid))
    rust_col = lerp(lin(72, 50, 40), lin(98, 64, 46), smoothstep(-1.4, 1.4, mid + 0.5 * big))
    rust_col = rust_col * (1.0 + 0.08 * fine.clip(-1, 1))[..., None]
    col = lerp(scale_col, rust_col, rust * 0.9)
    col = lerp(col, lin(118, 72, 44) * (0.92 + 0.12 * fine.clip(-1, 1))[..., None], heavy * 0.6)
    col = lerp(col, lin(40, 30, 24), pit * 0.7)
    bare = lin(150, 148, 144)
    col = lerp(col, bare, edge * 0.8)
    metal = np.clip(edge * 0.95, 0, 1)
    rough = 0.74 + 0.04 * mid
    rough = lerp(rough, 0.86 + 0.04 * fine, rust * 0.8)
    rough = lerp(rough, 0.93, heavy)
    rough = lerp(rough, 0.42, edge)
    return col, hgt, np.clip(rough, 0.3, 1.0), metal


def steel(rng, H):
    """Worn mild-steel plate (launch plate): mill finish dulled by weather, soft oxidised and greasy zones, fine
    scratches, polished arrises. Low contrast; metal except where grime sits."""
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    base = lin(138, 137, 134) * (1.0 + 0.05 * fnoise(rng, H, N, PPS, 0.5, 20, 1.6))[..., None]
    brush = fnoise(rng, H, N, PPS, 10, 120, 1.0, aniso=0.05)
    scr = np.zeros((H, N))
    wear_zone = fnoise(rng, H, N, PPS, 0.5, 4, 2.2)
    for _ in range(220):
        x0, y0 = rng.uniform(0, N), rng.uniform(0, H)
        if wear_zone[int(y0) % H, int(x0) % N] < -0.2 and rng.random() < 0.7:
            continue
        ang = rng.normal(0, 0.5) + (0 if rng.random() < 0.6 else rng.uniform(0, np.pi))
        L = rng.uniform(8, 70)
        ex, ey = math.cos(ang), math.sin(ang)
        dx = ((xx - x0 + N / 2) % N) - N / 2
        dy = yy - y0
        t = dx * ex + dy * ey
        dperp = np.abs(-dx * ey + dy * ex)
        m = (t > 0) & (t < L) & (dperp < 1.6)
        if m.any():
            scr = np.maximum(scr, np.where(m, smoothstep(1.2, 0.2, dperp) * rng.uniform(0.25, 0.8), 0))
    ox = smoothstep(-1.0, 1.4, fnoise(rng, H, N, PPS, 0.3, 5, 2.4))              # oxidised/dull zones (most)
    grime = smoothstep(0.0, 2.4, fnoise(rng, H, N, PPS, 0.4, 6, 2.0)) * 0.5
    rust = smoothstep(1.0, 2.2, fnoise(rng, H, N, PPS, 0.6, 9, 1.8)) * (0.4 + 0.6 * grime / 0.5)
    v = ((np.arange(H) + 0.5) / H)[:, None] * np.ones((1, N))
    edge = smoothstep(0.12, 0.0, np.minimum(v, 1 - v))
    col = base * (1.0 + 0.025 * brush)[..., None]
    col = lerp(col, lin(96, 92, 86), ox * 0.6)
    col = lerp(col, lin(168, 168, 166), scr * 0.35)
    col = lerp(col, lin(62, 57, 51), grime)
    col = lerp(col, lin(104, 64, 42), rust * 0.85)
    col = lerp(col, lin(160, 160, 158), edge * 0.4)
    hgt = 0.0003 * brush - 0.0006 * scr + 0.0004 * rust
    rough = np.clip(0.56 + 0.05 * brush + 0.18 * ox - 0.08 * scr + 0.28 * grime + 0.25 * rust - 0.12 * edge, 0.3, 0.95)
    metal = np.clip(1.0 - 0.55 * ox - 0.9 * grime - rust, 0, 1)
    return col, hgt, rough, metal


def tread(rng, H):
    """Diamond tread plate: raised lugs in alternating orientation, polished tops, dirty recesses."""
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    P = N / 40.0                                   # 25.6 px pitch (0.1 stud): 40 cells along U, periodic
    rows = H / P
    ci = np.floor(xx / P)
    cj = np.floor(yy / P)
    lx = xx - (ci + 0.5) * P
    ly = yy - (cj + 0.5) * P
    sgn = np.where((ci + cj) % 2 == 0, 1.0, -1.0)
    a = np.pi / 4
    u = (lx * math.cos(a) + ly * math.sin(a) * sgn)
    w = (-lx * math.sin(a) * sgn + ly * math.cos(a))
    L, Wd = 0.27 * P, 0.12 * P
    d = np.sqrt((np.maximum(np.abs(u) - L, 0)) ** 2 + w ** 2) - Wd * np.clip(1 - (np.abs(u) / (L + Wd)) ** 2, 0.25, 1)
    lug = smoothstep(0.8, -1.2, d)
    hgt = 0.006 * lug ** 0.7
    base = steel(rng, H)
    col, _, rough, metal = base
    dirt = (1 - lug) * smoothstep(-0.6, 1.2, fnoise(rng, H, N, PPS, 0.5, 10, 1.8))
    col = lerp(col, lin(176, 176, 174), lug * 0.55)
    col = lerp(col, lin(56, 50, 44), dirt * 0.65)
    rough = lerp(rough, 0.42, lug * 0.8)
    rough = lerp(rough, 0.85, dirt * 0.7)
    metal = np.clip(lerp(metal, 1.0, lug) - dirt * 0.5, 0, 1)
    del rows
    return col, hgt, rough, metal


def soot(rng, H):
    n1 = fnoise(rng, H, N, PPS, 2, 80, 1.3)
    col = lin(30, 28, 27) * (1.0 + 0.25 * n1)[..., None]
    col = lerp(col, lin(70, 64, 58), smoothstep(1.4, 2.4, fnoise(rng, H, N, PPS, 4, 60, 1.2)))
    hgt = 0.004 * fnoise(rng, H, N, PPS, 4, 60, 1.6)
    return col, hgt, np.clip(0.9 + 0.05 * n1, 0, 1), np.zeros((H, N))


def build_iron(tex_dir, seed=7404):
    rng = np.random.default_rng(seed)
    A = np.zeros((N, N, 3))
    Hh = np.zeros((N, N))
    R = np.zeros((N, N))
    M = np.zeros((N, N))
    NM = np.zeros((N, N, 3))
    for key, fn in (("STRAP", lambda H: forged(rng, H, "strap")), ("BAR", lambda H: forged(rng, H, "bar")),
                    ("STEEL", lambda H: steel(rng, H)), ("TREAD", lambda H: tread(rng, H)),
                    ("SOOT", lambda H: soot(rng, H))):
        r0, r1 = IRON_STRIPS[key]
        col, hgt, rough, metal = fn(r1 - r0)
        ao = occlusion(hgt, PPS, scales=((1.5, 50.0), (5.0, 25.0)), floor=0.55)
        A[r0:r1] = col * ao[..., None]
        Hh[r0:r1], R[r0:r1], M[r0:r1] = hgt, rough, metal
        NM[r0:r1] = normal_map(hgt, PPS, 1.0, wrap_v=False)
    save_material(tex_dir, "LR_Iron", A, NM, R, M, normal_ready=True)


# =============================================================================================== MISC: roof, ridge, rope, banner
def roof_strip(rng):
    """Two courses of weathered clay pantiles (192 px/stud): 8 tiles of 0.667 stud per 5.333-stud period."""
    r0, r1 = MISC_STRIPS["ROOF"]
    H = r1 - r0
    pps = ROOF_PPS
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    tw = N / 8.0
    course = 192.0
    A = np.zeros((H, N, 3))
    Ht = np.zeros((H, N))
    R = np.zeros((H, N))
    pal = [lin(148, 80, 56), lin(158, 88, 60), lin(138, 74, 52), lin(128, 70, 50), lin(160, 98, 68),
           lin(144, 86, 62), lin(134, 78, 58)]
    for c in range(2):
        cy0 = c * course
        yl = (yy - cy0) / course                                        # 0 at the nose (bottom), 1 at the head
        inc = (yl >= 0) & (yl < 1)
        for t in range(8):
            off = rng.uniform(-3, 3)
            x0 = t * tw + off
            xl = (((xx - x0) % N) / tw)                                 # 0..1 across this tile (+ overlap)
            mine = inc & (xl < 1.06)
            if not mine.any():
                continue
            # pantile cross-profile: concave pan, then the roll that overlaps the next tile
            pan = -0.035 * np.sin(np.pi * np.clip(xl / 0.62, 0, 1)) ** 1.2
            roll = 0.05 * np.sin(np.pi * np.clip((xl - 0.58) / 0.42, 0, 1)) ** 0.8
            prof = np.where(xl < 0.62, pan, roll)
            ramp = 0.045 * (1.0 - yl)                                     # each course sits on the one below
            nose = smoothstep(0.0, 0.035, yl)
            hs = prof + ramp - 0.02 * (1 - nose) + rng.uniform(-0.004, 0.004)
            k = rng.integers(0, len(pal))
            tint = pal[k] * rng.uniform(0.94, 1.05)
            spot = fnoise(rng, H, N, pps, 3, 40, 1.4)
            colt = tint * (1.0 + 0.06 * spot)[..., None]
            # dirt washes down the pans, lighter crowns on the rolls
            colt = colt * np.where(xl < 0.62, 0.88 - 0.08 * (1 - yl), 1.04)[..., None]
            A = np.where(mine[..., None], colt, A)
            Ht = np.where(mine, hs, Ht)
            R = np.where(mine, 0.74 + 0.05 * spot, R)
    # weathering over all tiles: black streaks, lichen, moss in the shadowed overlaps under the noses
    yl_all = (yy % course) / course
    streak = smoothstep(0.8, 2.0, fnoise(rng, H, N, pps, 0.4, 10, 1.8, aniso=5.0))
    A = A * (1 - 0.35 * streak)[..., None]
    Fl, _, lid, _, _ = worley(rng, H, N, 12, 32, 0.9)
    lon = rng.random(12 * 32)[lid]
    lr = rng.uniform(3, 9, 12 * 32)[lid]
    lich = np.where(lon < 0.16, smoothstep(lr, lr - 2.5, Fl + 2.5 * fnoise(rng, H, N, pps, 10, 60, 1.3)), 0.0)
    lcol = np.where((lon < 0.06)[..., None], lin(160, 154, 108), lin(168, 164, 150))
    A = lerp(A, lcol, lich * 0.6)
    grime = smoothstep(-0.5, 1.5, fnoise(rng, H, N, pps, 0.3, 4, 2.2))
    A = A * (1.0 - 0.18 * grime)[..., None]
    mossy = smoothstep(0.12, 0.0, yl_all) * smoothstep(-0.2, 1.0, fnoise(rng, H, N, pps, 1, 16, 1.6))
    A = lerp(A, lin(70, 86, 40), mossy * 0.75)
    Ht = Ht + 0.003 * mossy + 0.0008 * lich
    R = lerp(R, 0.95, np.maximum(lich, mossy))
    ao = occlusion(Ht, pps, scales=((2.0, 30.0), (8.0, 18.0), (20.0, 8.0)), floor=0.45)
    A *= ao[..., None]
    return A, Ht, R


def ridge_strip(rng):
    """Half-round ridge tiles laid along U (1 stud each) bedded in lime mortar at both edges (V 0 and 1)."""
    r0, r1 = MISC_STRIPS["RIDGE"]
    H = r1 - r0
    pps = ROOF_PPS
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    v = (yy + 0.5) / H
    L = N / 5.0
    A = np.zeros((H, N, 3))
    Ht = np.zeros((H, N))
    pal = [lin(150, 80, 54), lin(134, 70, 48), lin(166, 96, 62), lin(124, 66, 48), lin(158, 92, 64)]
    for i in range(5):
        x0 = i * L + rng.uniform(-3, 3)
        xl = ((xx - x0) % N) / L
        mine = xl < 1.04
        collar = smoothstep(0.9, 0.97, xl)
        tint = pal[i % len(pal)] * rng.uniform(0.92, 1.06)
        A = np.where(mine[..., None], tint * (0.95 - 0.12 * collar)[..., None], A)
        Ht = np.where(mine, 0.01 * collar - 0.006 * (1 - smoothstep(0.0, 0.05, xl)), Ht)
    mort = smoothstep(0.16, 0.06, np.minimum(v, 1 - v) + 0.03 * fnoise(rng, H, N, pps, 3, 40, 1.4))
    mcol = lin(150, 146, 134) * (0.85 + 0.2 * fnoise(rng, H, N, pps, 10, 80, 1.2).clip(-1, 1))[..., None]
    A = lerp(A, mcol, mort)
    A = A * (1.0 + 0.05 * fnoise(rng, H, N, pps, 3, 40, 1.4))[..., None]
    lich = smoothstep(1.6, 2.2, fnoise(rng, H, N, pps, 2, 30, 1.5))
    A = lerp(A, lin(168, 164, 146), lich * 0.6)
    Ht = Ht + 0.004 * mort * fnoise(rng, H, N, pps, 20, 90, 1.2)
    R = np.clip(0.76 + 0.18 * mort + 0.1 * lich, 0, 1)
    A *= occlusion(Ht, pps, scales=((2.0, 30.0), (6.0, 15.0)), floor=0.55)[..., None]
    return A, Ht, R


def rope_strip(rng):
    """3-strand hemp rope; U along the rope (4 studs), V around it."""
    r0, r1 = MISC_STRIPS["ROPE"]
    H = r1 - r0
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    pitch = N / 64.0                                   # one strand repeat every 16 px (0.0625 stud)
    q = (yy / H) * 3.0 + xx / pitch
    fq = q - np.floor(q)
    strand = np.sin(np.pi * fq) ** 0.6
    fib = fnoise(rng, H, N, PPS, 30, 128, 1.0, aniso=0.6)
    hgt = 0.006 * strand + 0.0008 * fib
    dirt = smoothstep(-0.5, 1.5, fnoise(rng, H, N, PPS, 0.5, 10, 1.8))
    col = lin(156, 132, 94) * (0.7 + 0.32 * strand)[..., None] * (1 + 0.08 * fib)[..., None]
    col = lerp(col, lin(84, 70, 54), dirt * 0.55)
    rough = np.clip(0.9 + 0.05 * fib, 0, 1)
    return col, hgt, rough


def sigil_polys():
    """The Cleft sigil in banner space (studs): x across the width (-1.6..1.6), y down from the top hem (0..6.7).
    A stepped base, a tapering monolith split from the top down to mid-height (the halves lean slightly apart),
    three dark iron bands across it, a fire basket on top and a flame. Returns (polygons, flame, bands, courses)."""
    base = [(-1.08, 5.2), (1.08, 5.2), (1.08, 4.99), (0.86, 4.99), (0.86, 4.8), (-0.86, 4.8), (-0.86, 4.99),
            (-1.08, 4.99)]
    mono = [(-0.64, 4.8), (0.64, 4.8), (0.44, 2.1), (0.1, 2.06), (0.0, 3.45), (-0.1, 2.06), (-0.44, 2.1)]
    basket = [(-0.56, 1.58), (0.56, 1.58), (0.36, 1.98), (-0.36, 1.98)]
    flame = [(0.04, 0.42), (0.1, 0.66), (0.2, 0.88), (0.3, 1.1), (0.34, 1.3), (0.3, 1.46), (0.18, 1.56),
             (0.0, 1.6), (-0.18, 1.56), (-0.3, 1.46), (-0.34, 1.28), (-0.26, 1.04), (-0.12, 0.84), (-0.02, 0.62)]
    bands = [(2.36, 2.5), (3.1, 3.24), (3.98, 4.12)]
    courses = [2.8, 3.62, 4.42]
    return [base, mono, basket], flame, bands, courses


def banner_region(rng):
    """Banner cloth laid sideways: U = along the banner from the top hem (U 0) to the swallowtail (U 1),
    V = across the width (V 0 = the banner's left edge seen from the front). 153 x 140 px per stud."""
    r0, r1 = MISC_STRIPS["BANNER"]
    H = r1 - r0
    ppu = N / BANNER_LEN
    ppv = H / BANNER_WID
    yy, xx = np.mgrid[0:H, 0:N].astype(np.float64)
    s_len = xx / ppu                                   # studs from the top hem
    s_wid = (yy + 0.5) / ppv - BANNER_WID / 2           # studs across (-1.6..1.6)
    # wool cloth: weave + dye variation, sun-faded towards the top, dirt towards the tails
    weave = (np.sin(TAU * xx / 4.0) * np.sin(TAU * yy / 4.0))
    slub = fnoise(rng, H, N, ppu, 2, 40, 1.4, aniso=0.3)
    dye = lin(128, 50, 32) * (1.0 + 0.06 * fnoise(rng, H, N, ppu, 0.3, 6, 2.2))[..., None]
    dye = dye * (1.0 + 0.05 * slub)[..., None]
    fade = smoothstep(2.5, 0.0, s_len) * 0.18
    dye = lerp(dye, lin(176, 110, 82), fade)
    dirt = smoothstep(4.0, 6.7, s_len) * (0.4 + 0.3 * fnoise(rng, H, N, ppu, 0.5, 8, 2.0).clip(-1, 1))
    hem = smoothstep(0.42, 0.34, s_len)                                 # sleeve hem around the crossbar
    border = (smoothstep(0.2, 0.14, BANNER_WID / 2 - np.abs(s_wid)) * smoothstep(0.06, 0.12, BANNER_WID / 2 - np.abs(s_wid)))
    col = dye.copy()
    col = lerp(col, lin(48, 44, 42), border * 0.9)
    col = lerp(col, dye * 0.8, hem)
    # sigil: bone-coloured appliqué with a dark stitched outline, slightly raised
    polys, flame_poly, bands, courses = sigil_polys()
    px_x, px_y = s_wid * ppv, s_len * ppu
    sd_u = np.full((H, N), np.inf)
    for poly in polys:
        sd_u = np.minimum(sd_u, sd_polygon(px_x, px_y, [(x * ppv, y * ppu) for (x, y) in poly]))
    sd_f = sd_polygon(px_x, px_y, [(x * ppv, y * ppu) for (x, y) in flame_poly])
    sig = smoothstep(0.8, -0.8, sd_u)
    flame = smoothstep(0.8, -0.8, sd_f)
    outline = np.maximum(smoothstep(1.6, 0.6, np.abs(sd_u + 2.4)), smoothstep(1.6, 0.6, np.abs(sd_f + 2.4)))
    band_m = np.zeros((H, N))
    for (y0, y1) in bands:
        band_m = np.maximum(band_m, smoothstep(0.012, 0.0, np.maximum(y0 - s_len, s_len - y1)) * sig)
    course_m = np.zeros((H, N))
    for yc in courses:
        course_m = np.maximum(course_m, smoothstep(1.4, 0.4, np.abs(s_len - yc) * ppu) * sig)
    bone = lin(206, 196, 174) * (0.94 + 0.08 * slub.clip(-1, 1))[..., None]
    col = lerp(col, bone, sig)
    col = lerp(col, lin(52, 46, 42), band_m * 0.92)
    col = lerp(col, lin(120, 104, 86), course_m * 0.7)
    col = lerp(col, lin(214, 150, 62) * (0.95 + 0.1 * slub.clip(-1, 1))[..., None], flame)
    col = lerp(col, lin(40, 34, 30), outline * 0.7)
    sig = np.maximum(sig, flame)
    stitch = (0.5 + 0.5 * np.sin(TAU * (xx + yy) / 6.0)) * outline
    col = col * (1.0 - 0.06 * weave[..., None]) * (1.0 - dirt * 0.45)[..., None]
    col = lerp(col, lin(70, 58, 46), np.clip(dirt * 0.5, 0, 1))
    # fray near the swallowtail
    fray = smoothstep(6.45, 6.7, s_len) * fnoise(rng, H, N, ppu, 20, 80, 1.0, aniso=0.15).clip(0, 2)
    col *= (1 - 0.2 * fray)[..., None]
    hgt = 0.0012 * weave + 0.0012 * slub + 0.0025 * sig - 0.0015 * stitch + 0.003 * hem
    rough = np.clip(0.93 + 0.03 * slub - 0.04 * sig, 0.8, 1.0)
    return col, hgt, rough


def build_misc(tex_dir, seed=7505):
    rng = np.random.default_rng(seed)
    A = np.zeros((N, N, 3))
    Hh = np.zeros((N, N))
    R = np.zeros((N, N))
    NM = np.zeros((N, N, 3))
    for key, fn, pps in (("ROOF", roof_strip, ROOF_PPS), ("RIDGE", ridge_strip, ROOF_PPS), ("ROPE", rope_strip, PPS),
                         ("BANNER", banner_region, N / BANNER_LEN)):
        r0, r1 = MISC_STRIPS[key]
        col, hgt, rough = fn(rng)
        A[r0:r1], Hh[r0:r1], R[r0:r1] = col, hgt, rough
        NM[r0:r1] = normal_map(hgt, pps, 1.1, wrap_v=False)
    save_material(tex_dir, "LR_Misc", A, NM, R, None, normal_ready=True)


# =============================================================================================== save
ROUGH_SIZE = N // 2
MR_SIZE = N // 4
NORMAL_SOFTEN = 0.9             # px, gaussian on the normal maps' XY before writing


def half_res(a):
    """2 x 2 box downsample (row 0 = V 0 is kept, so UVs line up)."""
    return 0.25 * (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2])


def save_material(tex_dir, name, albedo, normal_or_height, rough, metal, normal_ready=False):
    files = files_for(name)
    os.makedirs(os.path.join(tex_dir, "glb_only"), exist_ok=True)
    srgb = to_srgb(albedo)
    write_png(os.path.join(tex_dir, files["color"]), srgb, dither=False)    # natural noise, no banding: no dither
    nm = normal_or_height if normal_ready or normal_or_height.ndim == 3 else normal_map(normal_or_height, PPS)
    # take the sub-pixel grain out of the normals (it only shimmers under Roblox's specular and makes the PNG
    # incompressible), then renormalise
    xy = np.stack([blur(nm[..., 0] * 2.0 - 1.0, NORMAL_SOFTEN), blur(nm[..., 1] * 2.0 - 1.0, NORMAL_SOFTEN)], axis=-1)
    z = np.sqrt(np.clip(1.0 - (xy ** 2).sum(-1), 0.05, 1.0))
    nm = np.concatenate([xy, z[..., None]], axis=-1) * 0.5 + 0.5
    write_png(os.path.join(tex_dir, files["normal"]), nm, dither=False)
    r = np.clip(rough + ROBLOX_ROUGH_OFFSET, 0.0, 1.0)
    m = np.zeros_like(r) if metal is None else np.clip(metal, 0.0, 1.0)
    # roughness / metalness at half resolution (LookDevPlaybook s.11: half the colour map's size is enough); keeps
    # the GLB with its 15 embedded images under Roblox's ~20 MB upload size
    r2, m2 = half_res(r), half_res(m)
    r4, m4 = half_res(r2), half_res(m2)          # the GLB-embedded packing at 256 (MR_SIZE) keeps the GLB < 20 MB
    write_png(os.path.join(tex_dir, files["mr"]), np.stack([r4, r4, m4], axis=-1), dither=False)
    write_png(os.path.join(tex_dir, files["rough"]), r2, dither=False)
    if "metal" in files:
        write_png(os.path.join(tex_dir, files["metal"]), m2, dither=False)
    print("TEXTURE %s  mean albedo sRGB %s  rough %.2f%s" % (
        name, tuple(int(v) for v in (srgb.reshape(-1, 3).mean(0) * 255)), float(r.mean()),
        "" if metal is None else "  metal %.2f" % float(m.mean())))


def build_all(tex_dir, only=None):
    t0 = time.time()
    g = None
    if only is None or "stone" in only:
        g = build_stone(tex_dir)
        print("  stone %.1fs" % (time.time() - t0))
    if only is None or "wood" in only:
        build_wood(tex_dir)
        print("  wood %.1fs" % (time.time() - t0))
    if only is None or "iron" in only:
        build_iron(tex_dir)
        print("  iron %.1fs" % (time.time() - t0))
    if only is None or "misc" in only:
        build_misc(tex_dir)
        print("  misc %.1fs" % (time.time() - t0))
    return g


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else os.path.join(os.getcwd(), "textures")
    only = argv[1].split(",") if len(argv) > 1 else None
    build_all(out, only)
