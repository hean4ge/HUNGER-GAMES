"""
style_b.py - LAST STANDING style test, VARIANT B "Blocky voxel realism" (Blender 5.3, headless, numpy only).

Look: everything is built from axis-aligned blocks on a 0.5-stud voxel grid - trunks, branches, needle pads, leaf
clumps, square-section logs, plank roof courses, masonry and the boulder's stacked rounded blocks - at realistic
proportions, with a realistic slightly desaturated palette, subtle per-block colour variation and ambient occlusion
baked between the blocks. Every block face is ONE flat colour (no photo texture, no grain); the normal map only
carries block bevels, grooves between logs / planks / stones and soft domes on leaf blocks. Lighting does the realism.

    blender --background --factory-startup --python art/blender/style_b.py -- <out_dir> <preview_dir> [options]
        out_dir      default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/StyleTest/B
        preview_dir  default art/previews/StyleTest/B
        options      norender          export only
                     renderonly        re-render previews from the existing GLB + terrain PNGs
                     quick             low-sample previews
                     samples=N res=WxH shots=set,cabin,trees,ground lights=midday,late

Per asset: numpy voxel builder -> greedy-merged quads per MeshPart (faces between solid blocks dropped; colliding
parts that need a closed hull keep their inner faces, mapped to a dummy texel patch) -> one 1024 atlas per asset (P
texels per voxel face, the largest P that fits) -> per-texel bake: block colour x baked AO (corner AO + a cosine
hemisphere of rays marched through the voxel grid, the ground plane counts as an occluder) x groove darkening,
bevel / groove / dome normals (OpenGL, tangent space = the quad's UV axes), roughness -> Blender meshes -> one GLB
(normals, UVs, MikkTSpace tangents, single-sided, embedded Color + Normal + packed glTF roughness) + manifest in the
LS-Real-1 shape (paths relative to BlenderExports).
Terrain: two tileable MaterialVariant sets (pebble path, forest floor), heightfields of axis-aligned blocks rendered to
Color + Normal + Roughness (1024, 8 studs per tile).
"""
import json
import math
import os
import struct
import sys
import time
import zlib

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PATHS = [a for a in ARGV if "=" not in a and ("/" in a or "\\" in a)]
FLAGS = {a.lower() for a in ARGV if "=" not in a and not ("/" in a or "\\" in a)}
OPTS = dict(a.split("=", 1) for a in ARGV if "=" in a)
OUT = os.path.abspath(PATHS[0]) if PATHS else os.path.join(
    os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports", "StyleTest", "B")
PREV = os.path.abspath(PATHS[1]) if len(PATHS) > 1 else os.path.normpath(
    os.path.join(HERE, "..", "previews", "StyleTest", "B"))
EXP_ROOT = os.path.dirname(os.path.dirname(OUT))          # BlenderExports (manifest paths are relative to it)
TEX_DIR = os.path.join(OUT, "textures")
TERRAIN_DIR = os.path.join(OUT, "terrain")
CATEGORY = "StyleTest_B"
GLB_NAME = CATEGORY + ".glb"

V = 0.5                 # voxel size in studs
ATLAS = 1024            # atlas / terrain tile size (px)
TRI_LIMIT = 20000


def log(*a):
    print(*a, flush=True)


def rel(path):
    return os.path.relpath(path, EXP_ROOT).replace("\\", "/")


# =============================================================================================== colour, PNG, noise
def lin(c):
    """sRGB 0-255 triple -> linear float32 array."""
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)


def to_srgb(x):
    x = np.clip(np.asarray(x, np.float64), 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def _png_rows(raw, ft, bpp):
    if ft == 0:
        return raw
    prev = np.zeros_like(raw)
    prev[1:] = raw[:-1]
    left = np.zeros_like(raw)
    left[:, bpp:] = raw[:, :-bpp]
    if ft == 1:
        return (raw.astype(np.int16) - left).astype(np.uint8)
    if ft == 2:
        return (raw.astype(np.int16) - prev).astype(np.uint8)
    return (raw.astype(np.int16) - ((left.astype(np.int16) + prev) // 2)).astype(np.uint8)


def write_png(path, img):
    """img float 0..1 (H x W or H x W x C), row 0 = BOTTOM (V = 0, Blender convention). 8-bit gray / RGB / RGBA."""
    a = np.clip(np.round(np.asarray(img, np.float64) * 255.0), 0, 255).astype(np.uint8)
    a = np.flipud(a)
    h, w = a.shape[:2]
    ch = 1 if a.ndim == 2 else a.shape[2]
    raw = a.reshape(h, w * ch)
    best = None
    for ft in (1, 2, 3):
        data = np.concatenate([np.full((h, 1), ft, np.uint8), _png_rows(raw, ft, ch)], axis=1).tobytes()
        comp = zlib.compress(data, 9)
        if best is None or len(comp) < len(best):
            best = comp

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload))
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, {1: 0, 3: 2, 4: 6}[ch], 0, 0, 0)))
        f.write(chunk(b"IDAT", best))
        f.write(chunk(b"IEND", b""))
    return path


def _ihash(ix, iy, iz, seed):
    """Deterministic hash of integer lattice coordinates -> float64 in [0, 1)."""
    with np.errstate(over="ignore"):
        x = np.asarray(ix).astype(np.int64).astype(np.uint64) * np.uint64(0x9E3779B97F4A7C15)
        x = x ^ (np.asarray(iy).astype(np.int64).astype(np.uint64) * np.uint64(0xC2B2AE3D27D4EB4F))
        x = x ^ (np.asarray(iz).astype(np.int64).astype(np.uint64) * np.uint64(0x165667B19E3779F9))
        x = x ^ (np.uint64(seed & 0xFFFFFFFF) * np.uint64(0x27D4EB2F165667C5))
        x = x ^ (x >> np.uint64(31))
        x = x * np.uint64(0xBF58476D1CE4E5B9)
        x = x ^ (x >> np.uint64(29))
        x = x * np.uint64(0x94D049BB133111EB)
        x = x ^ (x >> np.uint64(32))
    return (x >> np.uint64(11)).astype(np.float64) * (1.0 / 9007199254740992.0)


def vnoise3(x, y, z, seed, period=None):
    """Smooth value noise in [0, 1]; period (int) wraps x and y (tileable 2D use)."""
    x, y, z = (np.asarray(v, np.float64) for v in (x, y, z))
    xi, yi, zi = np.floor(x), np.floor(y), np.floor(z)
    fx, fy, fz = x - xi, y - yi, z - zi
    xi, yi, zi = xi.astype(np.int64), yi.astype(np.int64), zi.astype(np.int64)
    ux, uy, uz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)

    def h(dx, dy, dz):
        a, b = xi + dx, yi + dy
        if period:
            a, b = a % period, b % period
        return _ihash(a, b, zi + dz, seed)
    c00 = h(0, 0, 0) * (1 - ux) + h(1, 0, 0) * ux
    c10 = h(0, 1, 0) * (1 - ux) + h(1, 1, 0) * ux
    c01 = h(0, 0, 1) * (1 - ux) + h(1, 0, 1) * ux
    c11 = h(0, 1, 1) * (1 - ux) + h(1, 1, 1) * ux
    return (c00 * (1 - uy) + c10 * uy) * (1 - uz) + (c01 * (1 - uy) + c11 * uy) * uz


def fbm3(x, y, z, seed, octaves=3, period=None):
    s, a, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        f = 2 ** o
        s = s + a * vnoise3(np.asarray(x) * f, np.asarray(y) * f, np.asarray(z) * f, seed + 101 * o,
                            period * f if period else None)
        tot += a
        a *= 0.5
    return s / tot


def box_blur3(a, r):
    """Mean over a (2r+1)^3 box (outside the grid counts as 0)."""
    out = a.astype(np.float32)
    w = 2 * r + 1
    for ax in range(3):
        pad = [(0, 0)] * 3
        pad[ax] = (r + 1, r)
        c = np.cumsum(np.pad(out, pad), axis=ax, dtype=np.float32)
        n = out.shape[ax]
        hi = np.take(c, np.arange(w, w + n), axis=ax)
        lo = np.take(c, np.arange(0, n), axis=ax)
        out = (hi - lo) / w
    return out


def shift_up(a, d):
    """a[i, j, k + d] (False above the grid)."""
    out = np.zeros_like(a)
    out[:, :, :-d] = a[:, :, d:]
    return out


# =============================================================================================== voxel grid
class Grid:
    """Dense voxel grid. Voxel (i, j, k) spans lo + [i, i+1) * V on each axis. The asset pivot is the world origin
    (base centre on the ground, z = 0 is a lattice plane)."""

    def __init__(self, name, lo, hi):
        self.name = name
        self.lo = np.array(lo, np.float64)
        self.n = tuple(int(round((h - l) / V)) for l, h in zip(lo, hi))
        self.mat = np.zeros(self.n, np.uint8)
        self.grp = np.zeros(self.n, np.int32)
        self.col = np.zeros(self.n + (3,), np.float32)
        self.rgh = np.zeros(self.n, np.float32)
        self.axis = np.full(self.n, 255, np.uint8)
        self.var = np.ones(self.n, np.float32)
        self.mats = []
        self._g = 0
        self.attachments = {}

    def mat_add(self, name, part, rough=0.85, bevel=0.15, theta=0.55, groove=False, pillow=0.0, endcol=None,
                vary=0.03, gdark=0.3):
        self.mats.append(dict(name=name, part=part, rough=rough, bevel=bevel, theta=theta, groove=groove,
                              pillow=pillow, endcol=None if endcol is None else lin(endcol), vary=vary, gdark=gdark))
        return len(self.mats)

    def group(self):
        self._g += 1
        return self._g

    def _slices(self, lo, hi):
        i0 = [max(0, int(math.floor((l - g0) / V + 1e-6))) for l, g0 in zip(lo, self.lo)]
        i1 = [min(n, int(math.ceil((h - g0) / V - 1e-6))) for h, g0, n in zip(hi, self.lo, self.n)]
        if any(b <= a for a, b in zip(i0, i1)):
            return None
        return tuple(slice(a, b) for a, b in zip(i0, i1))

    def centres(self, sl):
        X = self.lo[0] + (np.arange(sl[0].start, sl[0].stop) + 0.5) * V
        Y = self.lo[1] + (np.arange(sl[1].start, sl[1].stop) + 0.5) * V
        Z = self.lo[2] + (np.arange(sl[2].start, sl[2].stop) + 0.5) * V
        return X[:, None, None], Y[None, :, None], Z[None, None, :]

    def all_centres(self):
        return self.centres(tuple(slice(0, n) for n in self.n))

    def paint(self, lo, hi, fn, mat, col, grp=0, axis=255, mode="over", rough=None):
        """Set every voxel whose centre lies in [lo, hi] and satisfies fn(X, Y, Z). col / grp may be callables
        of (X, Y, Z). mode: over (overwrite), empty (only empty voxels), solid (only filled voxels)."""
        sl = self._slices(lo, hi)
        if sl is None:
            return 0
        X, Y, Z = self.centres(sl)
        shape = tuple(s.stop - s.start for s in sl)
        m = np.ones(shape, bool) if fn is None else np.broadcast_to(np.asarray(fn(X, Y, Z), bool), shape).copy()
        cur = self.mat[sl]
        if mode == "empty":
            m &= cur == 0
        elif mode == "solid":
            m &= cur > 0
        cnt = int(m.sum())
        if cnt == 0:
            return 0
        c = np.broadcast_to(np.asarray(col(X, Y, Z), np.float32), shape + (3,))[m] if callable(col) \
            else np.asarray(col, np.float32)
        gv = np.broadcast_to(np.asarray(grp(X, Y, Z)), shape)[m] if callable(grp) else grp
        cur[m] = mat
        self.grp[sl][m] = gv
        self.axis[sl][m] = axis
        self.col[sl][m] = c
        self.rgh[sl][m] = self.mats[mat - 1]["rough"] if rough is None else rough
        return cnt

    def box(self, lo, hi, mat, col, grp=0, axis=255, mode="over"):
        return self.paint(lo, hi, None, mat, col, grp, axis, mode)

    def erase(self, lo, hi, fn=None):
        sl = self._slices(lo, hi)
        if sl is None:
            return
        if fn is None:
            self.mat[sl] = 0
        else:
            X, Y, Z = self.centres(sl)
            shape = tuple(s.stop - s.start for s in sl)
            m = np.broadcast_to(np.asarray(fn(X, Y, Z), bool), shape)
            self.mat[sl][m] = 0

    def capsule(self, a, b, r0, r1, mat, col, grp=0, mode="over", axis=255):
        a, b = np.asarray(a, float), np.asarray(b, float)
        rm = max(r0, r1)
        ab = b - a
        L2 = max(float(ab @ ab), 1e-9)

        def fn(X, Y, Z):
            px, py, pz = X - a[0], Y - a[1], Z - a[2]
            t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / L2, 0.0, 1.0)
            dx, dy, dz = px - t * ab[0], py - t * ab[1], pz - t * ab[2]
            r = r0 + (r1 - r0) * t
            return dx * dx + dy * dy + dz * dz < r * r
        return self.paint(np.minimum(a, b) - rm - V, np.maximum(a, b) + rm + V, fn, mat, col, grp, axis, mode)

    def limb(self, a, b, r0, r1, mat, col, p=2.8, grp=0, mode="over"):
        """Branch segment with a superellipse (squarish) cross-section: level limbs get flat, standable tops."""
        a, b = np.asarray(a, float), np.asarray(b, float)
        d = b - a
        L = float(np.linalg.norm(d))
        f = d / L
        l = np.cross(f, (0.0, 0.0, 1.0))
        l = l / np.linalg.norm(l) if np.linalg.norm(l) > 1e-3 else np.array([1.0, 0.0, 0.0])
        u = np.cross(l, f)
        rm = max(r0, r1)
        ext = 0.55 * rm

        def fn(X, Y, Z):
            px, py, pz = X - a[0], Y - a[1], Z - a[2]
            s = px * f[0] + py * f[1] + pz * f[2]
            t = np.clip(s / L, 0.0, 1.0)
            r = r0 + (r1 - r0) * t
            dl = np.abs(px * l[0] + py * l[1] + pz * l[2]) / r
            du = np.abs(px * u[0] + py * u[1] + pz * u[2]) / r
            return (dl ** p + du ** p < 1.0) & (s > -ext) & (s < L + ext)
        return self.paint(np.minimum(a, b) - rm - V, np.maximum(a, b) + rm + V, fn, mat, col, grp, 255, mode)

    def ellipsoid(self, c, radii, mat, col, yaw=0.0, noise=None, grp=0, mode="empty"):
        c = np.asarray(c, float)
        rx, ry, rz = radii
        cs, sn = math.cos(yaw), math.sin(yaw)
        R = np.array([max(rx, ry), max(rx, ry), rz]) * (1.0 + (noise[0] if noise else 0.0)) + V

        def fn(X, Y, Z):
            dx, dy, dz = X - c[0], Y - c[1], Z - c[2]
            u = (dx * cs + dy * sn) / rx
            v = (-dx * sn + dy * cs) / ry
            w = dz / rz
            q = u * u + v * v + w * w
            if noise:
                amp, fr, sd = noise
                q = q - amp * 2.0 * (vnoise3(X * fr, Y * fr, Z * fr, sd) - 0.5)
            return q < 1.0
        return self.paint(c - R, c + R, fn, mat, col, grp, 255, mode)

    def finalize_var(self, seed):
        """Per-voxel value variation (each material's 'vary'), hashed from the voxel index: flat per block."""
        I, J, K = np.meshgrid(*[np.arange(n) for n in self.n], indexing="ij")
        h = _ihash(I, J, K, seed).astype(np.float32)
        amp = np.zeros(256, np.float32)
        for i, m in enumerate(self.mats):
            amp[i + 1] = m["vary"]
        self.var = 1.0 + amp[self.mat] * (2.0 * h - 1.0)

    def top_of(self, x, y, z_lo, z_hi, mats):
        """Highest solid z (top face) of the given materials in the column at (x, y) between z_lo and z_hi."""
        i = int((x - self.lo[0]) // V)
        j = int((y - self.lo[1]) // V)
        k0 = int((z_lo - self.lo[2]) // V)
        k1 = int((z_hi - self.lo[2]) // V)
        col = self.mat[i, j, k0:k1]
        ks = [k for k in range(len(col)) if col[k] in mats]
        if not ks:
            return None
        return self.lo[2] + (k0 + max(ks) + 1) * V


def shade_foliage(g, mid, inner, outer, top, r=2, top_r=3):
    """Outer / upper leaves lighter and warmer, deep inner leaves darker and cooler (colour multipliers)."""
    m = g.mat == mid
    solid = g.mat > 0
    dens = box_blur3(solid, r)
    f = np.clip((0.97 - dens) / 0.5, 0.0, 1.0)[..., None]
    mult = np.asarray(inner, np.float32) * (1.0 - f) + np.asarray(outer, np.float32) * f
    blocked = np.zeros_like(solid)
    for d in range(1, top_r + 1):
        blocked |= shift_up(solid, d)
    mult = np.where((~blocked)[..., None], mult * np.asarray(top, np.float32), mult)
    g.col[m] *= mult[m]


def rbox_sdf(X, Y, Z, c, half, r):
    qx = np.abs(X - c[0]) - (half[0] - r)
    qy = np.abs(Y - c[1]) - (half[1] - r)
    qz = np.abs(Z - c[2]) - (half[2] - r)
    out = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2 + np.maximum(qz, 0) ** 2)
    return out + np.minimum(np.maximum(np.maximum(qx, qy), qz), 0.0) - r


# =============================================================================================== assets
def build_spruce(seed=1101):
    """Tall Norway-spruce-like conifer, ~44 studs: flared, ridged trunk with roots and dead stubs, ~22 whorls of
    drooping branches carrying layered needle pads (flattened ellipsoid sprays), a thin leader at the top."""
    rng = np.random.default_rng(seed)
    H = 44.0
    g = Grid("VoxSpruce", (-10.0, -10.0, -1.0), (10.0, 10.0, H + 1.5))
    BARK = g.mat_add("Bark", "Trunk", rough=0.9, bevel=0.16, theta=0.55, vary=0.035)
    WOOD = g.mat_add("Branch", "Branches", rough=0.88, bevel=0.16, theta=0.55, vary=0.035)
    DEAD = g.mat_add("DeadWood", "Branches", rough=0.9, bevel=0.16, theta=0.55, vary=0.05)
    NEED = g.mat_add("Needles", "Needles", rough=0.74, bevel=0.12, theta=0.42, pillow=0.2, vary=0.045)
    bark_dk, bark_lt, bark_hi = lin((60, 45, 36)), lin((104, 80, 62)), lin((112, 100, 88))

    def axis_xy(z):
        return 0.22 * np.sin(z * 0.11 + 0.8), 0.18 * np.cos(z * 0.083 + 0.2)

    def radius(z):
        z = np.maximum(z, 0.0)
        return np.maximum(1.08 * (1.0 - 0.8 * z / H) + 0.62 * np.exp(-z / 1.15), 0.26)

    def trunk_fn(X, Y, Z):
        ax, ay = axis_xy(Z)
        dx, dy = X - ax, Y - ay
        th = np.arctan2(dy, dx)
        n = fbm3(np.cos(th) * 2.4, np.sin(th) * 2.4, Z * 0.2, seed + 1, 3)
        return (np.hypot(dx, dy) < radius(Z) + 0.34 * (n - 0.5)) & (Z < H - 0.3)

    def bark_col(X, Y, Z):
        ax, ay = axis_xy(Z)
        th = np.arctan2(Y - ay, X - ax)
        n = fbm3(np.cos(th) * 2.4, np.sin(th) * 2.4, Z * 0.2, seed + 1, 3)        # ridges lighter, furrows darker
        t = np.clip((n - 0.3) / 0.4, 0, 1)[..., None]
        base = bark_dk * (1 - t) + bark_lt * t
        k = np.clip((Z - 6.0) / (H - 6.0), 0, 1)[..., None] * 0.55                 # thinner, greyer bark up high
        return base * (1 - k) + bark_hi * k
    g.paint((-3.5, -3.5, -1.0), (3.5, 3.5, H), trunk_fn, BARK, bark_col)
    for i in range(5):
        a = i * 2 * math.pi / 5 + rng.uniform(-0.35, 0.35)
        L = rng.uniform(1.5, 2.5)
        g.capsule((math.cos(a) * 0.9, math.sin(a) * 0.9, 0.75),
                  (math.cos(a) * (1.3 + L), math.sin(a) * (1.3 + L), -0.45), 0.62, 0.28, BARK,
                  lin((76, 58, 46)) * rng.uniform(0.92, 1.06))
    for i in range(9):                                                              # dead stubs on the bare stem
        z = rng.uniform(2.6, 7.0)
        a = rng.uniform(0, 2 * math.pi)
        L = rng.uniform(0.7, 1.8)
        ax, ay = (float(v) for v in axis_xy(z))
        r = float(radius(z))
        g.capsule((ax + math.cos(a) * (r - 0.3), ay + math.sin(a) * (r - 0.3), z),
                  (ax + math.cos(a) * (r + L), ay + math.sin(a) * (r + L), z - 0.3 * L), 0.3, 0.24, DEAD,
                  lin((106, 98, 88)) * rng.uniform(0.9, 1.06), mode="empty")
    # ---------------------------------------------------------------- whorls
    z0, ztop, R0 = 7.4, H - 1.4, 6.9
    needle = lin((40, 63, 45))
    whorl, z = 0, z0
    sprays = []
    while z < ztop - 0.5:
        f = (z - z0) / (ztop - z0)
        R = R0 * (1.0 - f) ** 0.92 + 0.55
        nb = 6 if f < 0.4 else (5 if f < 0.75 else 4)
        for b in range(nb):
            phi = whorl * 2.39996 + b * 2 * math.pi / nb + rng.uniform(-0.28, 0.28)
            L = R * rng.uniform(0.8, 1.04)
            droop = (0.3 - 0.25 * f) * rng.uniform(0.75, 1.2)
            rise = -0.04 + 0.34 * f
            ax, ay = (float(v) for v in axis_xy(z))
            r0 = float(radius(z)) * 0.6
            cs, sn = math.cos(phi), math.sin(phi)
            ts = np.linspace(0, 1, 9)
            pts = [(ax + cs * (r0 + t * L), ay + sn * (r0 + t * L),
                    z + L * (rise * t - droop * t * t + 0.35 * droop * t ** 3)) for t in ts]
            for i in range(len(pts) - 1):
                g.capsule(pts[i], pts[i + 1], 0.38 - 0.1 * i / 8, 0.38 - 0.1 * (i + 1) / 8, WOOD,
                          lin((74, 57, 45)), mode="empty")
            tint = np.array([rng.uniform(0.92, 1.08)] * 3, np.float32) * \
                np.array([1.0, rng.uniform(0.97, 1.03), rng.uniform(0.95, 1.05)], np.float32)
            tset = [0.36, 0.62, 0.88] if L > 2.6 else ([0.5, 0.88] if L > 1.2 else [0.7])
            for t in tset:
                fi = t * 8
                i0 = int(min(fi, 7))
                w = fi - i0
                p = np.array(pts[i0]) * (1 - w) + np.array(pts[i0 + 1]) * w
                along = 0.5 * L / len(tset) * 1.5 + 0.7
                width = (0.22 * L + 0.7) * (0.65 + 0.35 * math.sin(math.pi * min(t, 0.92)))
                thick = 0.5 + 0.14 * (1 - f)
                sprays.append((p + np.array([0, 0, 0.1]), (along, width, thick), phi, tint, t))
        whorl += 1
        z += (2.2 - 0.85 * f) + rng.uniform(-0.2, 0.2)
    for (p, rad3, phi, tint, t) in sprays:
        col = needle * tint * (np.array([1.1, 1.1, 1.0], np.float32) if t > 0.84 else 1.0)
        g.ellipsoid(p, rad3, NEED, col, yaw=phi, noise=(0.08, 0.6, seed + 7), grp=g.group(), mode="empty")
    for (c, rr) in (((0.1, 0.0, H - 0.9), (0.75, 0.75, 1.35)), ((0.0, 0.1, H - 2.6), (1.35, 1.35, 0.75)),
                    ((-0.1, 0.0, H - 4.1), (1.8, 1.8, 0.7))):
        g.ellipsoid(c, rr, NEED, needle * 1.08, noise=(0.25, 1.1, seed + 8), grp=g.group(), mode="empty")
    shade_foliage(g, NEED, inner=(0.62, 0.66, 0.74), outer=(1.1, 1.1, 1.0), top=(1.1, 1.1, 0.96))
    g.finalize_var(seed + 99)
    spec = dict(
        kind="Tree", tags=["Conifer", "Spruce", "Voxel"],
        notes="Voxel spruce ~44 tall: trunk + roots collide (Hull); branches and needle pads are visual only.",
        parts=[("Trunk", dict(role="Bark", roblox="Wood", collide=True, collision="Hull")),
               ("Branches", dict(role="Branches", roblox="Wood", collide=False)),
               ("Needles", dict(role="Needles", roblox="LeafyGrass", collide=False))],
        closed=["Trunk"], density={"Needles": 0.6},
        ao=dict(near=2.5, far=12.0, ns=0.42, fs=0.5, min=0.3))
    return g, spec


def build_oak(seed=2202):
    """Broad oak ~27 tall: furrowed trunk with buttress roots, four main limbs that each run level for ~3 studs
    (flat standable tops = Perch1-4), a central leader, secondary branches into ~20 leaf clumps."""
    rng = np.random.default_rng(seed)
    g = Grid("VoxOak", (-16.0, -16.0, -1.0), (16.0, 16.0, 30.0))
    BARK = g.mat_add("Bark", "Bark", rough=0.9, bevel=0.16, theta=0.55, vary=0.035)
    BR = g.mat_add("Branch", "Branches", rough=0.88, bevel=0.16, theta=0.55, vary=0.035)
    LEAF = g.mat_add("Leaves", "Leaves", rough=0.64, bevel=0.12, theta=0.4, pillow=0.24, vary=0.06)
    bark_dk, bark_lt = lin((68, 61, 53)), lin((116, 106, 93))

    def tax(z):
        return -0.16 * np.sin(z * 0.15), 0.12 * np.sin(z * 0.11 + 1.0)

    def trad(z):
        z = np.maximum(z, 0.0)
        return 1.3 - 0.018 * z + 0.95 * np.exp(-z / 0.85)

    def furrow(X, Y, Z):
        ax, ay = tax(Z)
        th = np.arctan2(Y - ay, X - ax)
        return fbm3(np.cos(th) * 3.4, np.sin(th) * 3.4, Z * 0.16, seed + 1, 3)

    def trunk_fn(X, Y, Z):
        ax, ay = tax(Z)
        return (np.hypot(X - ax, Y - ay) < trad(Z) + 0.45 * (furrow(X, Y, Z) - 0.5)) & (Z < 10.6)

    def bark_col(X, Y, Z):
        t = np.clip((furrow(X, Y, Z) - 0.3) / 0.4, 0, 1)[..., None]
        return bark_dk * (1 - t) + bark_lt * t
    g.paint((-4.0, -4.0, -1.0), (4.0, 4.0, 10.6), trunk_fn, BARK, bark_col)
    for i in range(6):
        a = i * 2 * math.pi / 6 + rng.uniform(-0.3, 0.3)
        L = rng.uniform(2.2, 3.4)
        g.capsule((math.cos(a) * 1.2, math.sin(a) * 1.2, 0.95),
                  (math.cos(a) * (1.6 + L), math.sin(a) * (1.6 + L), -0.4), 0.85, 0.32, BARK,
                  lin((84, 76, 66)) * rng.uniform(0.92, 1.06))
    limb_col = lin((92, 84, 74))
    perches, limb_ends = [], []
    az0 = rng.uniform(0, 2 * math.pi)
    for i in range(4):
        az = az0 + i * math.pi / 2 + rng.uniform(-0.25, 0.25)
        zs = 7.4 + 0.85 * i
        d = np.array([math.cos(az), math.sin(az), 0.0])
        ax, ay = (float(v) for v in tax(zs))
        p0 = np.array([ax, ay, zs])
        p1 = p0 + d * 2.0 + np.array([0, 0, 1.4])
        p2 = p1 + d * 3.0                                                          # level, standable stretch
        p3 = p2 + d * 2.0 + np.array([0, 0, 2.2])
        p4 = p3 + d * 1.6 + np.array([0, 0, 2.0])
        col = limb_col * rng.uniform(0.94, 1.06)
        for (a, b, r0, r1) in ((p0, p1, 1.08, 1.02), (p1, p2, 1.02, 0.98), (p2, p3, 0.98, 0.76),
                               (p3, p4, 0.76, 0.56)):
            g.limb(a, b, r0, r1, BARK, col, p=2.8)
        perches.append(((p1 + p2) / 2, d))
        limb_ends.append((p4, d))
    c0, c1, c2 = np.array([0.0, 0.0, 9.6]), np.array([0.6, -0.4, 14.6]), np.array([0.2, 0.3, 18.8])
    g.limb(c0, c1, 1.0, 0.78, BARK, limb_col)
    g.limb(c1, c2, 0.78, 0.5, BARK, limb_col)
    # ---------------------------------------------------------------- crown: big overlapping lobes (no broccoli)
    lobes = []
    for j in range(6):
        ang = az0 + math.pi / 4 + j * math.pi / 3 + rng.uniform(-0.25, 0.25)
        r = rng.uniform(6.3, 7.6)
        lobes.append((np.array([math.cos(ang) * r, math.sin(ang) * r, rng.uniform(17.2, 18.6)]),
                      (rng.uniform(4.8, 5.8), rng.uniform(4.4, 5.4), rng.uniform(3.4, 4.0)), ang))
    for j in range(3):
        ang = az0 + j * 2 * math.pi / 3 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(1.5, 3.5)
        lobes.append((np.array([math.cos(ang) * r, math.sin(ang) * r, rng.uniform(21.0, 22.2)]),
                      (rng.uniform(5.0, 5.8), rng.uniform(4.6, 5.4), rng.uniform(3.6, 4.2)), ang))
    for (p4, d) in limb_ends:                                  # each limb end feeds the nearest lobe
        c = min(lobes, key=lambda lb: float(np.linalg.norm(lb[0] - p4)))[0]
        g.capsule(p4, c, 0.5, 0.3, BR, lin((86, 78, 68)), mode="empty")
    for (c, _, _) in lobes[6:]:
        g.capsule(c2, c, 0.45, 0.3, BR, lin((86, 78, 68)), mode="empty")
    leaf = lin((64, 92, 42))
    tints = [np.array(t, np.float32) for t in ((1.0, 1.0, 1.0), (1.06, 1.05, 0.9), (0.95, 0.98, 1.04),
                                               (1.03, 0.99, 0.93), (0.97, 1.02, 0.97))]
    for (c, rad3, ang) in lobes:
        tint = tints[int(rng.integers(len(tints)))] * rng.uniform(0.93, 1.07)
        g.ellipsoid(c, rad3, LEAF, leaf * tint, yaw=ang, noise=(0.34, 0.42, seed + 9), grp=g.group(),
                    mode="empty")
    # leafy surface: carve the outer shell into clusters and gaps (interior stays solid - no hidden cavities)
    lf = g.mat == LEAF
    dens = box_blur3(g.mat > 0, 2)
    X, Y, Z = g.all_centres()
    n = vnoise3(X * 0.9, Y * 0.9, Z * 0.9, seed + 11)
    g.mat[lf & (dens < 0.8) & (n > 0.62)] = 0
    shade_foliage(g, LEAF, inner=(0.6, 0.66, 0.76), outer=(1.1, 1.08, 0.98), top=(1.1, 1.08, 0.92))
    for i, (p, d) in enumerate(perches):
        top = g.top_of(p[0], p[1], p[2] - 2.0, p[2] + 2.0, (BARK,))
        if top is not None:
            g.attachments["Perch%d" % (i + 1)] = dict(position=(float(p[0]), float(p[1]), float(top)),
                                                     look=(float(d[0]), float(d[1]), 0.0), up=(0.0, 0.0, 1.0))
    g.finalize_var(seed + 99)
    spec = dict(
        kind="Tree", tags=["Broadleaf", "Oak", "Voxel"],
        notes="Voxel oak ~27 tall: trunk + main limbs = one climbable part (PreciseConvexDecomposition, tag "
              "Climbable); the four level limb stretches have flat 2-stud tops (Perch1-4 on top, look = along the "
              "limb). Branches and leaves are visual only.",
        parts=[("Bark", dict(role="Bark", roblox="Wood", collide=True, collision="PreciseConvexDecomposition",
                             tags=["Climbable"])),
               ("Branches", dict(role="Branches", roblox="Wood", collide=False)),
               ("Leaves", dict(role="Leaves", roblox="LeafyGrass", collide=False))],
        closed=["Bark"], density={"Leaves": 0.6},
        ao=dict(near=2.5, far=12.0, ns=0.42, fs=0.5, min=0.3))
    return g, spec


def build_boulder(seed=3303):
    """~6-stud granite boulder: a broad rounded base block (top sloping), a smaller rounded block resting off-centre
    on it, a split-off chunk and a stone at its foot. Rounded edges meet in dark V-joints; each block has its own grey,
    broad mottling, pale lichen crusts, dark lichen dots and moss on upward faces, soil stain at the foot."""
    rng = np.random.default_rng(seed)
    g = Grid("VoxBoulder", (-4.5, -4.0, -1.0), (4.5, 4.0, 5.0))
    ROCK = g.mat_add("Granite", "Rock", rough=0.82, bevel=0.2, theta=0.6, groove=True, vary=0.08, gdark=0.5)
    # rounded blocks = superellipsoids (exponent ~2.5: between an egg and a box), only low-frequency noise
    # (centre, radii, exponent, sRGB, shear): shear tilts the block's top so the stack is not a pedestal
    blocks = [((0.0, 0.0, 0.5), (2.9, 2.3, 1.45), 3.4, (88, 86, 83), 0.16),     # base, top slopes to -X
              ((0.95, -0.55, 2.75), (1.75, 1.45, 0.95), 3.0, (98, 96, 92), -0.14),  # top block, off-centre
              ((-2.7, 1.5, 0.25), (1.15, 1.05, 0.9), 3.0, (80, 79, 77), 0.1),     # split-off chunk
              ((2.95, 1.85, -0.1), (0.6, 0.55, 0.45), 2.5, (92, 90, 87), 0.0)]    # stone at the foot
    for bi, (c, rad, p, rgb, sh) in enumerate(blocks):
        def fn(X, Y, Z, c=c, rad=rad, p=p, bi=bi, sh=sh):
            zz = Z - c[2] - sh * (X - c[0])
            q = (np.abs(X - c[0]) / rad[0]) ** p + (np.abs(Y - c[1]) / rad[1]) ** p + (np.abs(zz) / rad[2]) ** p
            return q - 0.3 * (vnoise3(X * 0.42, Y * 0.42, Z * 0.42, seed + 5 + bi) - 0.5) < 1.0
        g.paint(np.array(c) - np.array(rad) - 1, np.array(c) + np.array(rad) + 1, fn, ROCK,
                lin(rgb) * rng.uniform(0.97, 1.03), grp=g.group(), mode="empty")
    rock = g.mat == ROCK
    X, Y, Z = g.all_centres()
    open_up = rock & ~shift_up(g.mat > 0, 1)
    shape = rock.shape
    Xf, Yf, Zf = (np.broadcast_to(a, shape) for a in (X, Y, Z))
    blot = vnoise3(Xf * 0.7, Yf * 0.7, Zf * 0.7, seed + 20)                 # broad mottling between voxels
    g.col[rock] *= (0.84 + 0.32 * blot[rock])[:, None]
    lich = rock & (Zf > 0.6) & (vnoise3(Xf * 0.9, Yf * 0.9, Zf * 0.9, seed + 33) > 0.62)
    g.col[lich] = g.col[lich] * 0.35 + lin((126, 128, 118)) * 0.65
    dots = rock & (vnoise3(Xf * 1.7, Yf * 1.7, Zf * 1.7, seed + 24) > 0.8)
    g.col[dots] = g.col[dots] * 0.4 + lin((60, 60, 56)) * 0.6
    moss = open_up & (Zf > 1.2) & (vnoise3(Xf * 0.45, Yf * 0.45, Zf * 0.3, seed + 31) > 0.64)
    g.col[moss] = lin((50, 62, 40))
    foot = rock & (Zf < 0.6)
    g.col[foot] *= np.array([0.8, 0.77, 0.72], np.float32)
    g.finalize_var(seed + 99)
    spec = dict(kind="Rock", tags=["Boulder", "Granite", "Voxel"],
                notes="Voxel boulder ~6 x 4.6 body (7.5 with the foot stone), 4 above ground: stacked rounded granite "
                      "blocks; the base continues ~1 stud below y = 0 so it seats on slopes.",
                parts=[("Rock", dict(role="Rock", roblox="Rock", collide=True, collision="Hull"))],
                closed=[], ao=dict(near=2.0, far=8.0, ns=0.45, fs=0.35, min=0.35))
    return g, spec


def build_cabin(seed=4404):
    """Hunter's log cabin: 16 x 12 log body of 6 courses of 1.5 x 1.5 hewn square logs (outside edges chamfered
    into V-grooves, flat hewn interior, crossed square-cut corner ends), stone sill, stepped 45-degree shake roof
    whose front slope breaks into a 1:2 catslide over the 4-deep porch, ridge cap, log gables, stone chimney on the
    west gable, open plank door (4 x 7.5), framed cross windows (open plank shutters on the east one), porch posts
    with stepped knee braces, beam and rafters, one step."""
    rng = np.random.default_rng(seed)
    g = Grid("VoxCabin", (-12.0, -8.0, -1.0), (11.0, 12.0, 21.0))
    LOG = g.mat_add("Logs", "Logs", rough=0.82, bevel=0.12, theta=0.6, groove=True, endcol=(150, 126, 96),
                    vary=0.025, gdark=0.42)
    ROOFB = g.mat_add("RoofBack", "RoofBack", rough=0.86, bevel=0.14, theta=0.55, groove=True,
                      endcol=(70, 63, 56), vary=0.03, gdark=0.35)
    ROOFF = g.mat_add("RoofFront", "RoofFront", rough=0.86, bevel=0.14, theta=0.55, groove=True,
                      endcol=(70, 63, 56), vary=0.03, gdark=0.35)
    PROOF = g.mat_add("PorchRoof", "PorchRoof", rough=0.86, bevel=0.14, theta=0.55, groove=True,
                      endcol=(70, 63, 56), vary=0.03, gdark=0.35)
    FLOOR = g.mat_add("Floor", "Floor", rough=0.8, bevel=0.12, theta=0.5, groove=True, endcol=(150, 124, 96),
                      vary=0.025, gdark=0.4)
    STEP = g.mat_add("Steps", "Steps", rough=0.8, bevel=0.12, theta=0.5, groove=True, endcol=(150, 124, 96),
                     vary=0.025, gdark=0.4)
    POST = g.mat_add("Posts", "Posts", rough=0.82, bevel=0.14, theta=0.6, groove=True, endcol=(140, 118, 92),
                     vary=0.06, gdark=0.4)
    FOUND = g.mat_add("Foundation", "Foundation", rough=0.84, bevel=0.2, theta=0.6, groove=True, vary=0.035,
                      gdark=0.5)
    CHIM = g.mat_add("Chimney", "Chimney", rough=0.84, bevel=0.2, theta=0.6, groove=True, vary=0.035, gdark=0.5)
    DOOR = g.mat_add("Door", "Door", rough=0.8, bevel=0.12, theta=0.5, groove=True, endcol=(140, 112, 84),
                     vary=0.025, gdark=0.45)
    TRIM = g.mat_add("Trim", "Trim", rough=0.8, bevel=0.14, theta=0.55, groove=True, endcol=(150, 124, 96),
                     vary=0.025, gdark=0.4)

    def tint(base, v=0.07, h=0.03):
        return lin(base) * np.array([1 + rng.uniform(-h, h), 1.0, 1 + rng.uniform(-h, h)], np.float32) * \
            rng.uniform(1 - v, 1 + v)

    stones = [(124, 120, 112), (110, 108, 104), (134, 127, 116), (118, 112, 102), (102, 100, 97), (128, 124, 120)]

    def masonry(lo, hi, mat, course_h, lengths, hollow=None, seed_off=0):
        z = lo[2]
        ci = 0
        while z < hi[2] - 1e-6:
            ch = course_h[ci % len(course_h)]
            z1 = min(z + ch, hi[2])
            L = lengths[ci % len(lengths)]
            ox, oy = rng.uniform(0, L), rng.uniform(0, L)
            pal = np.array([lin(s) for s in stones])
            sd = seed + seed_off * 1000 + ci

            def cell(X, Y, Z, L=L, ox=ox, oy=oy):
                return np.floor((X + ox) / L).astype(np.int64), np.floor((Y + oy) / L).astype(np.int64)

            def col(X, Y, Z, cell=cell, sd=sd):
                ix, iy = cell(X, Y, Z)
                h1 = _ihash(ix, iy, 0, sd)
                h2 = _ihash(ix, iy, 1, sd)
                c = pal[np.minimum((h1 * len(pal)).astype(int), len(pal) - 1)]
                return c * (0.93 + 0.14 * h2)[..., None]

            def grp(X, Y, Z, cell=cell, ci=ci):
                ix, iy = cell(X, Y, Z)
                return 100000 + seed_off * 20000 + ci * 1000 + (ix + 40) * 30 + (iy + 15)

            def fn(X, Y, Z):
                if hollow is None:
                    return np.ones(np.broadcast(X, Y, Z).shape, bool)
                (hx0, hy0), (hx1, hy1) = hollow
                return ~((X > hx0) & (X < hx1) & (Y > hy0) & (Y < hy1))
            g.paint((lo[0], lo[1], z), (hi[0], hi[1], z1), fn, mat, col, grp=grp)
            z = z1
            ci += 1

    # ---------------------------------------------------------------- foundation sill + floor
    masonry((-8.5, -6.5, -0.5), (8.5, 6.5, 1.0), FOUND, [1.5], [2.0], hollow=((-6.5, -4.5), (6.5, 4.5)),
            seed_off=1)

    def planks(lo, hi, mat, along, base, lens=(3.0, 4.0, 5.0, 6.0), wid=0.5):
        """Boards along X (along=0) or Y (along=1), wid wide, staggered joints, one group + tint per board."""
        a0, a1 = (lo[0], hi[0]) if along == 0 else (lo[1], hi[1])
        b0, b1 = (lo[1], hi[1]) if along == 0 else (lo[0], hi[0])
        b = b0
        while b < b1 - 1e-6:
            a = a0 - float(rng.choice([0.0, 1.0, 1.5, 2.0]))
            while a < a1 - 1e-6:
                L = float(rng.choice(lens))
                s, e = max(a, a0), min(a + L, a1)
                if e > s:
                    if along == 0:
                        g.box((s, b, lo[2]), (e, b + wid, hi[2]), mat, tint(base), grp=g.group(), axis=0)
                    else:
                        g.box((b, s, lo[2]), (b + wid, e, hi[2]), mat, tint(base), grp=g.group(), axis=1)
                a += L
            b += wid
    planks((-6.5, -4.5, 0.5), (6.5, 4.5, 1.0), FLOOR, 0, (100, 88, 74))
    # ---------------------------------------------------------------- log walls: 1.5-stud chamfered square logs
    # (3 x 3 voxels minus the four edge voxels), so every course meets the next in a real V-groove and the
    # crossed, protruding corner ends show a rounded log profile. 6 courses from the floor (1.0) to 10.0.
    log_base = (96, 86, 76)

    def log(lo, hi, axis, col, outer, ext_lim):
        """Square log whose outside edges are chamfered by one voxel along the wall body (|coord| <= ext_lim), so
        the courses meet in V-grooves; the inside is hewn flat and the protruding corner ends are square-cut
        (hewn-log corners), which keeps the end grain reading as a log end, not as a '+' symbol."""
        gid = g.group()
        g.box(lo, hi, LOG, col, grp=gid, axis=axis)
        o = [d for d in range(3) if d != axis]
        for side0, c1 in ((-1, lo[o[0]]), (1, hi[o[0]] - V)):
            for c2 in (lo[o[1]], hi[o[1]] - V):
                spans = [(max(lo[axis], -ext_lim), min(hi[axis], ext_lim))] if side0 == outer else []
                for (s0, s1) in spans:
                    if s1 <= s0:
                        continue
                    elo, ehi = list(lo), list(hi)
                    elo[axis], ehi[axis] = s0, s1
                    elo[o[0]], ehi[o[0]], elo[o[1]], ehi[o[1]] = c1, c1 + V, c2, c2 + V
                    sl = g._slices(elo, ehi)
                    if sl is not None:
                        m = g.grp[sl] == gid
                        g.mat[sl][m] = 0
        return gid
    for c in range(6):
        z0, z1 = 1.0 + 1.5 * c, 2.5 + 1.5 * c
        ext = c % 2 == 0
        dark = 0.9 + 0.1 * min(c / 2.0, 1.0)                    # splash-darkened lower courses
        for (ya, yb, out) in ((4.5, 6.0, 1), (-6.0, -4.5, -1)):
            xa, xb = (-9.0, 9.0) if ext else (-6.5, 6.5)
            log((xa, ya, z0), (xb, yb, z1), 0, tint(log_base, 0.09) * dark, out, 8.0)
        for (xa, xb, out) in ((-8.0, -6.5, -1), (6.5, 8.0, 1)):
            ya, yb = (-4.5, 4.5) if ext else (-7.0, 7.0)
            log((xa, ya, z0), (xb, yb, z1), 1, tint(log_base, 0.09) * dark, out, 6.0)
    g.erase((-2.0, 4.5, 1.0), (2.0, 6.0, 8.5))                  # door 4 x 7.5
    g.erase((3.5, 4.5, 4.0), (6.0, 6.0, 7.0))                   # front window
    g.erase((6.5, -1.0, 4.0), (8.0, 1.5, 7.0))                  # east window

    def under(j):                                               # roof underside above voxel column j (|Y| index)
        if j <= 12:
            return 16.0 - 0.5 * j
        return 10.0 - 0.5 * ((j - 11) // 2)                     # porch run: 1:2 (catslide)
    for (xa, xb, xe) in ((-8.0, -6.5, -8.0), (6.5, 8.0, 7.5)):   # log gables, stepped under the roof
        for c in range(6, 10):
            z0 = 1.0 + 1.5 * c
            gid, col = g.group(), tint(log_base)
            for j in range(12):
                top = min(z0 + 1.5, under(j))
                if top <= z0:
                    continue
                for (ya, yb) in ((0.5 * j, 0.5 * j + 0.5), (-0.5 * j - 0.5, -0.5 * j)):
                    g.box((xa, ya, z0), (xb, yb, top), LOG, col, grp=gid, axis=1)
                    g.erase((xe, ya, z0), (xe + V, yb, z0 + V))  # outside chamfers, like the walls
                    if top - z0 >= 1.5:
                        g.erase((xe, ya, top - V), (xe + V, yb, top))
    for side in (1, -1):                                        # wall plates up to the roof
        gid, col = g.group(), tint(log_base)
        for j in (9, 10, 11):
            ya, yb = (0.5 * j, 0.5 * j + 0.5) if side > 0 else (-0.5 * j - 0.5, -0.5 * j)
            g.box((-8.0, ya, 10.0), (8.0, yb, under(j)), LOG, col, grp=gid, axis=0)
    # ---------------------------------------------------------------- stepped shake roof (45 degrees) + porch
    roof_base = (76, 72, 67)
    for side, mat, jmax in ((1, ROOFF, 13), (-1, ROOFB, 14), (1, PROOF, 21)):
        for j in range(13 if mat == PROOF else 0, jmax):
            ya, yb = (0.5 * j, 0.5 * j + 0.5) if side > 0 else (-0.5 * j - 0.5, -0.5 * j)
            zlo = under(j)
            x = -9.5 - float(rng.choice([0.0, 0.5, 1.0]))
            while x < 9.5 - 1e-6:
                L = float(rng.choice([1.0, 1.5, 1.5, 2.0, 2.5]))
                s, e = max(x, -9.5), min(x + L, 9.5)
                if e > s:
                    base = roof_base if rng.uniform() > 0.16 else (62, 58, 54)
                    col = tint(base, 0.08, 0.02)
                    if (j >= 10 if mat != PROOF else j >= 18) and rng.uniform() < 0.28:   # moss on the eaves
                        col = col * 0.62 + lin((66, 80, 46)) * 0.38
                    thick = 0.5 if (mat == PROOF and j == jmax - 1) else 1.0   # thin porch eave
                    g.box((s, ya, zlo), (e, yb, zlo + thick), mat, col, grp=g.group(), axis=1)
                x += L
    g.box((-9.5, -0.5, 17.0), (9.5, 0.5, 17.5), ROOFB, tint((66, 62, 58)), grp=g.group(), axis=0)
    # ---------------------------------------------------------------- chimney (west gable)
    masonry((-11.0, -2.0, -0.5), (-8.0, 2.0, 6.0), CHIM, [1.0, 0.5], [1.5, 2.0, 1.0], seed_off=2)
    masonry((-10.5, -1.5, 6.0), (-8.0, 1.5, 7.0), CHIM, [1.0], [1.5], seed_off=3)
    masonry((-10.0, -1.0, 7.0), (-8.0, 1.0, 19.0), CHIM, [1.0, 0.5], [1.0, 1.5], seed_off=4)
    g.box((-10.5, -1.5, 19.0), (-7.5, 1.5, 19.5), CHIM, lin((116, 112, 106)), grp=g.group())
    g.erase((-9.5, -0.5, 15.0), (-8.5, 0.5, 19.5))
    g.box((-9.5, -0.5, 14.5), (-8.5, 0.5, 15.0), CHIM, lin((34, 31, 29)), grp=g.group())
    # ---------------------------------------------------------------- porch
    planks((-8.0, 6.0, 0.5), (8.0, 10.0, 1.0), FLOOR, 0, (114, 102, 88))
    g.box((-8.0, 9.5, 0.0), (8.0, 10.0, 0.5), POST, tint((78, 68, 58)), grp=g.group(), axis=0)
    for xa in (-8.0, 7.5):
        g.box((xa, 6.0, 0.0), (xa + 0.5, 9.5, 0.5), POST, tint((78, 68, 58)), grp=g.group(), axis=1)
    planks((-2.5, 10.0, 0.0), (2.5, 11.0, 0.5), STEP, 0, (98, 86, 72), lens=(5.0,))
    for xa in (-8.0, -4.0, 3.0, 7.0):
        g.box((xa, 9.0, 1.0), (xa + 1.0, 10.0, 7.5), POST, tint((82, 72, 62)), grp=g.group(), axis=2)
    g.box((-8.5, 9.0, 7.5), (8.5, 10.0, 8.0), POST, tint((78, 69, 60)), grp=g.group(), axis=0)
    for (xa, sides) in ((-8.0, (1,)), (-4.0, (-1, 1)), (3.0, (-1, 1)), (7.0, (-1,))):   # stepped knee braces
        for sd in sides:
            gid, col = g.group(), tint((80, 70, 60))
            for st in range(3):
                x0 = xa + 1.0 + 0.5 * st if sd > 0 else xa - 0.5 - 0.5 * st
                g.box((x0, 9.5, 6.0 + 0.5 * st), (x0 + 0.5, 10.0, 7.5), POST, col, grp=gid, axis=2)
    for xa in np.arange(-8.0, 8.5, 2.0):                         # rafters following the porch roof underside
        gid, col = g.group(), tint((78, 68, 58))
        for j in range(12, 19):
            zt = under(j)
            g.box((xa, 0.5 * j, zt - 0.5), (xa + 0.5, 0.5 * j + 0.5, zt), POST, col, grp=gid, axis=1, mode="empty")
    # ---------------------------------------------------------------- door, frames, windows
    trim = (104, 92, 78)
    for (lo, hi) in (((-2.5, 6.0, 1.0), (-2.0, 6.5, 9.0)), ((2.0, 6.0, 1.0), (2.5, 6.5, 9.0)),
                     ((-2.5, 6.0, 8.5), (2.5, 6.5, 9.0))):
        g.box(lo, hi, TRIM, tint(trim), grp=g.group(), axis=2 if hi[2] - lo[2] > 1 else 0)
    for y in np.arange(0.5, 4.5, 0.5):                          # open door leaf: vertical boards
        g.box((-2.5, y, 1.0), (-2.0, y + 0.5, 8.5), DOOR, tint((94, 76, 58)), grp=g.group(), axis=2)
    for z in (2.0, 7.0):
        g.box((-3.0, 1.0, z), (-2.5, 4.0, z + 0.5), DOOR, tint((86, 68, 50)), grp=g.group(), axis=1)
    for (lo, hi, ax) in (((3.0, 6.0, 3.5), (6.5, 7.0, 4.0), 0), ((3.0, 6.0, 4.0), (3.5, 6.5, 7.5), 2),
                         ((6.0, 6.0, 4.0), (6.5, 6.5, 7.5), 2), ((3.0, 6.0, 7.0), (6.5, 6.5, 7.5), 0),
                         ((4.5, 5.5, 4.0), (5.0, 6.0, 7.0), 2), ((3.5, 5.5, 5.5), (6.0, 6.0, 6.0), 0),
                         ((8.0, -1.5, 3.5), (9.0, 2.0, 4.0), 1), ((8.0, -1.5, 4.0), (8.5, -1.0, 7.5), 2),
                         ((8.0, 1.5, 4.0), (8.5, 2.0, 7.5), 2), ((8.0, -1.5, 7.0), (8.5, 2.0, 7.5), 1),
                         ((7.5, 0.0, 4.0), (8.0, 0.5, 7.0), 2), ((7.5, -1.0, 5.5), (8.0, 1.5, 6.0), 1)):
        g.box(lo, hi, TRIM, tint(trim), grp=g.group(), axis=ax)
    for (y0, y1) in ((-3.0, -1.5), (2.0, 3.5)):                 # plank shutters folded open on the east window
        for yy in np.arange(y0, y1, 0.5):
            g.box((8.0, yy, 4.0), (8.5, yy + 0.5, 7.0), TRIM, tint((84, 92, 86), 0.05), grp=g.group(), axis=2)
    g.attachments["Door"] = dict(position=(0.0, 6.0, 1.0), look=(0.0, 1.0, 0.0), up=(0.0, 0.0, 1.0))
    g.finalize_var(seed + 99)
    spec = dict(
        kind="Building", tags=["Cabin", "LogCabin", "Voxel"],
        notes="Voxel hunter's cabin: log body 16 x 12 (walls 1.5 thick, floor top 1.0, wall top 10, ridge 17.5, "
              "chimney 19.5), porch 4 deep under a catslide roof (beam underside 7.5, 6.5 clear above the deck), one "
              "0.5 step. Door opening 4 x 7.5 at the front (front = LookVector, -Z Roblox); the door leaf stands open "
              "inside. 'Door' attachment at the threshold, facing out. Interior is open to the roof (no loft).",
        parts=[("Logs", dict(role="Logs", roblox="Wood", collide=True, collision="PreciseConvexDecomposition")),
               ("RoofBack", dict(role="Roof", roblox="WoodPlanks", collide=True, collision="Hull")),
               ("RoofFront", dict(role="Roof", roblox="WoodPlanks", collide=True, collision="Hull")),
               ("PorchRoof", dict(role="PorchRoof", roblox="WoodPlanks", collide=True, collision="Hull")),
               ("Floor", dict(role="Floor", roblox="WoodPlanks", collide=True, collision="Box", tags=["Floor"])),
               ("Steps", dict(role="Steps", roblox="WoodPlanks", collide=True, collision="Box")),
               ("Posts", dict(role="Posts", roblox="Wood", collide=True, collision="PreciseConvexDecomposition")),
               ("Foundation", dict(role="Foundation", roblox="Cobblestone", collide=True, collision="Box")),
               ("Chimney", dict(role="Chimney", roblox="Cobblestone", collide=True, collision="Hull")),
               ("Door", dict(role="Door", roblox="WoodPlanks", collide=True, collision="Box")),
               ("Trim", dict(role="Trim", roblox="WoodPlanks", collide=False))],
        closed=["Logs", "Posts", "RoofBack", "RoofFront", "PorchRoof", "Chimney", "Floor", "Foundation", "Door",
                "Steps"],
        ao=dict(near=2.0, far=7.0, ns=0.45, fs=0.32, min=0.4))
    return g, spec


BUILDERS = {"VoxSpruce": build_spruce, "VoxOak": build_oak, "VoxCabin": build_cabin, "VoxBoulder": build_boulder}


# =============================================================================================== mesher + baker
DIRS = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]
INPLANE = {0: (1, 2), 1: (0, 2), 2: (0, 1)}
NATURAL = {0: 1, 1: -1, 2: 1}            # sign of cross(e_A0, e_A1) along the face axis


def _nb(a, axis, s, fill):
    out = np.full_like(a, fill)
    src, dst = [slice(None)] * 3, [slice(None)] * 3
    if s > 0:
        dst[axis], src[axis] = slice(0, -1), slice(1, None)
    else:
        dst[axis], src[axis] = slice(1, None), slice(0, -1)
    out[tuple(dst)] = a[tuple(src)]
    return out


def _look(arr, I, J, K, default):
    nx, ny, nz = arr.shape[:3]
    ok = (I >= 0) & (I < nx) & (J >= 0) & (J < ny) & (K >= 0) & (K < nz)
    out = np.full(I.shape + arr.shape[3:], default, dtype=arr.dtype)
    out[ok] = arr[I[ok], J[ok], K[ok]]
    return out


def greedy2d(mask, maxa, maxb):
    m = mask.copy()
    NA, NB = m.shape
    rects = []
    for a in np.nonzero(m.any(axis=1))[0]:
        row = m[a]
        b = 0
        while b < NB:
            if not row[b]:
                nz = np.flatnonzero(row[b:])
                if nz.size == 0:
                    break
                b += int(nz[0])
                continue
            e = b + 1
            while e < NB and row[e] and e - b < maxb:
                e += 1
            h = 1
            while a + h < NA and h < maxa and m[a + h, b:e].all():
                h += 1
            m[a:a + h, b:e] = False
            rects.append((int(a), int(b), h, e - b))
            b = e
    return rects


def shelf_pack(items, groups, W, H):
    """Shelves of height-sorted items (parts grouped inside equal heights, so neighbouring islands share a
    material and mip bleeding stays invisible). Returns positions or None if the atlas overflows."""
    order = sorted(range(len(items)), key=lambda i: (-items[i][1], groups[i], -items[i][0]))
    pos = [None] * len(items)
    x = y = sh = 0
    for i in order:
        w, h = items[i]
        if w > W:
            return None
        if x + w > W:
            y, x, sh = y + sh, 0, 0
        if y + h > H:
            return None
        pos[i] = (x, y)
        x += w
        sh = max(sh, h)
    return pos


def compute_ao(occ, pts, nid, aop, K=40, chunk=900):
    """Cosine-weighted hemisphere AO from lattice points, rays marched through the occupancy grid. Fixed ray set
    (Fibonacci spiral): smooth, no sampling noise. Returns the AO factor per point."""
    dmax, dnear = aop["far"], aop["near"]
    ts = np.arange(0.07, dmax, 0.33, dtype=np.float32)
    i = np.arange(K) + 0.5
    r = np.sqrt(i / K)
    ph = i * 2.39996323
    loc = np.stack([r * np.cos(ph), r * np.sin(ph), np.sqrt(1 - r * r)], 1).astype(np.float32)
    near_o = np.zeros(len(pts), np.float32)
    far_o = np.zeros(len(pts), np.float32)
    shape = np.array(occ.shape)
    for ni, (axis, s) in enumerate(DIRS):
        sel = np.nonzero(nid == ni)[0]
        if not len(sel):
            continue
        A0, A1 = INPLANE[axis]
        D = np.zeros((K, 3), np.float32)
        D[:, A0], D[:, A1], D[:, axis] = loc[:, 0], loc[:, 1], s * loc[:, 2]
        for c0 in range(0, len(sel), chunk):
            ids = sel[c0:c0 + chunk]
            P0 = pts[ids].astype(np.float32)
            pos = P0[:, None, None, :] + D[None, :, None, :] * ts[None, None, :, None]
            ijk = np.floor(pos).astype(np.int32)
            inb = (ijk >= 0).all(-1) & (ijk < shape).all(-1)
            hit = ijk[..., 2] < 0
            q = ijk[inb]
            hit[inb] |= occ[q[:, 0], q[:, 1], q[:, 2]]
            first = np.argmax(hit, axis=2)
            th = np.where(hit.any(axis=2), ts[first], np.inf)
            near_o[ids] = (th < dnear).mean(1)
            far_o[ids] = np.where(th < dmax, 1.0 - th / dmax, 0.0).mean(1)
    return np.clip(1.0 - aop["ns"] * near_o - aop["fs"] * far_o, aop["min"], 1.0)


def _fill(atl, P, cx, cy, rot, ao4, col, rough, flags, bev, th, pil, gd):
    rr, cc = np.meshgrid(np.arange(P), np.arange(P), indexing="ij")
    uu, vv = (cc + 0.5) / P, (rr + 0.5) / P
    rb = rot[:, None, None]
    uA0 = np.where(rb, vv[None], uu[None]).astype(np.float32)
    uA1 = np.where(rb, uu[None], vv[None]).astype(np.float32)
    a00, a10, a01, a11 = (ao4[:, i][:, None, None] for i in range(4))
    ao = a00 * (1 - uA0) * (1 - uA1) + a10 * uA0 * (1 - uA1) + a01 * (1 - uA0) * uA1 + a11 * uA0 * uA1
    bw = np.maximum(bev * P, 1.15)[:, None, None]
    dists = (uA0 * P, (1 - uA0) * P, uA1 * P, (1 - uA1) * P)
    nA0 = np.zeros_like(uA0)
    nA1 = np.zeros_like(uA0)
    dark = np.ones_like(uA0)
    light = np.zeros_like(uA0)
    thb = th[:, None, None]
    for e in range(4):
        f = flags[:, e][:, None, None]
        t = np.clip(1.0 - dists[e] / bw, 0.0, 1.0) * (f > 0)
        ang = t * np.where(f == 2, 0.85, 1.0) * thb
        comp = (-1.0 if e % 2 == 0 else 1.0) * np.sin(ang)
        if e < 2:
            nA0 += comp
        else:
            nA1 += comp
        dark *= 1.0 - np.where(f == 2, gd[:, None, None] * t * t, 0.0)
        light = np.maximum(light, np.where(f == 1, t, 0.0))
    pl = pil[:, None, None]
    nA0 += np.sin(pl * (2 * uA0 - 1))
    nA1 += np.sin(pl * (2 * uA1 - 1))
    tx = np.where(rb, nA1, nA0)
    ty = np.where(rb, nA0, nA1)
    tz = np.sqrt(np.clip(1 - tx * tx - ty * ty, 0.04, 1.0))
    nn = np.stack([tx, ty, tz], -1)
    nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
    c = col[:, None, None, :] * (ao * dark * (1.0 + 0.05 * light))[..., None]
    R = cy[:, None, None] + rr[None]
    C = cx[:, None, None] + cc[None]
    atl["col"][R, C] = c
    atl["nrm"][R, C] = nn
    atl["rgh"][R, C] = rough[:, None, None] - 0.05 * light
    atl["fill"][R, C] = True


def _dilate(atl, iters):
    filled = atl["fill"]
    arrs = (atl["col"], atl["nrm"], atl["rgh"])
    for _ in range(iters):
        acc = [np.zeros_like(a) for a in arrs]
        cnt = np.zeros(filled.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            fm = np.roll(np.roll(filled, dy, 0), dx, 1)
            new = fm & ~filled
            if not new.any():
                continue
            for a, ac in zip(arrs, acc):
                ac[new] += np.roll(np.roll(a, dy, 0), dx, 1)[new]
            cnt[new] += 1
        nm = cnt > 0
        if not nm.any():
            break
        for a, ac in zip(arrs, acc):
            a[nm] = ac[nm] / (cnt[nm][:, None] if a.ndim == 3 else cnt[nm])
        filled = filled | nm
    atl["fill"] = filled


def bake_asset(g, spec, size=None, pmax=16, pmin=3):
    """size None: 512 when that still gives >= 24 px/stud, else 1024. Islands have no gutter: each quad's UVs are
    inset by half a texel, so bilinear sampling never leaves its island at full resolution; islands are packed in
    equal-height runs grouped by part, so neighbours (and mip bleeding) share a material. spec['density'] scales the
    texels per voxel face per part (foliage seen from further away gets fewer)."""
    if size is None:
        try:
            r = bake_asset(g, spec, 512, pmax, pmin)
            if r["P"] >= 12:
                return r
        except RuntimeError:
            pass
        size = ATLAS
    t0 = time.time()
    part_keys = [p[0] for p in spec["parts"]]
    solid = g.mat > 0
    mat_part = np.zeros(256, np.int16)
    for i, m in enumerate(g.mats):
        mat_part[i + 1] = part_keys.index(m["part"]) + 1
    partarr = mat_part[g.mat]
    closed = np.zeros(len(part_keys) + 1, bool)
    for p in spec.get("closed", []):
        closed[part_keys.index(p) + 1] = True
    zbot = g.lo[2] + np.arange(g.n[2]) * V
    rects = []
    for axis, s in DIRS:
        nbs = _nb(solid, axis, s, False)
        nbp = _nb(partarr, axis, s, 0)
        vis = solid & ~nbs
        hid = solid & nbs & (nbp != partarr) & closed[partarr]
        if axis == 2 and s < 0:                                 # bottoms at or below the ground are never seen
            below = (zbot <= 1e-6)[None, None, :]
            hid = hid | (vis & below)
            vis = vis & ~below
        for k in range(g.n[axis]):
            ix = [slice(None)] * 3
            ix[axis] = k
            ix = tuple(ix)
            v2, h2 = vis[ix], hid[ix]
            av, ah = bool(v2.any()), bool(h2.any())
            if not (av or ah):
                continue
            p2 = partarr[ix]
            for pi in np.unique(p2[v2 | h2]):
                if av:
                    mm = v2 & (p2 == pi)
                    if mm.any():
                        rects += [(axis, s, k, int(pi), False) + r for r in greedy2d(mm, 16, 16)]
                if ah:
                    mm = h2 & (p2 == pi)
                    if mm.any():
                        rects += [(axis, s, k, int(pi), True) + r for r in greedy2d(mm, 128, 128)]
    visr = [r for r in rects if not r[4]]
    nvis = len(visr)
    R = np.array(visr, dtype=np.int64)
    R_axis, R_s, R_k, R_p = R[:, 0], R[:, 1], R[:, 2], R[:, 3]
    R_a0, R_b0, R_na, R_nb = R[:, 5], R[:, 6], R[:, 7], R[:, 8]
    rot = R_na < R_nb
    nu = np.where(rot, R_nb, R_na)
    nv = np.where(rot, R_na, R_nb)
    dens = np.ones(len(part_keys) + 1)
    for pk, w in spec.get("density", {}).items():
        dens[part_keys.index(pk) + 1] = w
    pos, P = None, None
    for Pc in range(pmax, pmin - 1, -1):
        Pr = np.maximum(2, np.round(Pc * dens[R_p]).astype(np.int64))
        items = [(int(u * p), int(v * p)) for u, v, p in zip(nu, nv, Pr)] + [(4, 4)]
        pos = shelf_pack(items, list(R_p) + [999], size, size)
        if pos is not None:
            P = Pc
            break
    if P is None:
        raise RuntimeError("%s: faces do not fit a %d atlas even at P=%d" % (g.name, size, pmin))
    px = np.array([pos[i][0] for i in range(nvis)])
    py = np.array([pos[i][1] for i in range(nvis)])
    dummy = pos[nvis]
    # ---------------------------------------------------------------- cells (one per visible voxel face)
    ncell = R_na * R_nb
    rid = np.repeat(np.arange(nvis), ncell)
    off = np.concatenate([[0], np.cumsum(ncell)[:-1]])
    jj = np.arange(int(ncell.sum())) - np.repeat(off, ncell)
    ia, ib = jj // R_nb[rid], jj % R_nb[rid]
    a, b = R_a0[rid] + ia, R_b0[rid] + ib
    axis, s, k = R_axis[rid], R_s[rid], R_k[rid]
    I = np.where(axis == 0, k, a)
    J = np.where(axis == 0, a, np.where(axis == 1, k, b))
    Kk = np.where(axis == 2, k, b)
    crot = rot[rid]
    Pr = np.maximum(2, np.round(P * dens[R_p]).astype(np.int64))
    cP = Pr[rid]
    cx = px[rid] + np.where(crot, ib, ia) * cP
    cy = py[rid] + np.where(crot, ia, ib) * cP
    # ---------------------------------------------------------------- AO at the lattice corners
    plane = k + (s > 0)
    sbit = (s > 0).astype(np.int64)
    B = 4096

    def key(aa, bb):
        return (((axis * 2 + sbit) * B + plane) * B + aa) * B + bb
    ck = np.stack([key(a, b), key(a + 1, b), key(a, b + 1), key(a + 1, b + 1)], 1)
    ukeys, inv = np.unique(ck.ravel(), return_inverse=True)
    inv = inv.reshape(-1, 4)
    ub, ua = ukeys % B, (ukeys // B) % B
    upl, t4 = (ukeys // B ** 2) % B, ukeys // B ** 3
    usb, uax = t4 % 2, t4 // 2
    pts = np.zeros((len(ukeys), 3), np.float64)
    for ax_ in range(3):
        sel = uax == ax_
        A0, A1 = INPLANE[ax_]
        pts[sel, ax_] = upl[sel] + np.where(usb[sel] > 0, 0.02, -0.02)
        pts[sel, A0] = ua[sel]
        pts[sel, A1] = ub[sel]
    nid = uax * 2 + (1 - usb)
    zc = g.lo[2] + (np.arange(g.n[2]) + 0.5) * V
    occ = solid | (zc < 0)[None, None, :]
    t1 = time.time()
    ao_pts = compute_ao(occ, pts, nid, spec["ao"])
    ao4 = ao_pts[inv].astype(np.float32)
    t2 = time.time()
    # ---------------------------------------------------------------- per-cell attributes
    mv = g.mat[I, J, Kk]
    gv = g.grp[I, J, Kk]
    nmat = len(g.mats) + 1
    m_groove = np.zeros(256, bool)
    m_bev, m_th, m_pil, m_gd = (np.zeros(256, np.float32) for _ in range(4))
    m_hasend = np.zeros(256, bool)
    m_end = np.zeros((256, 3), np.float32)
    for i, m in enumerate(g.mats):
        m_groove[i + 1] = m["groove"]
        m_bev[i + 1], m_th[i + 1], m_pil[i + 1], m_gd[i + 1] = m["bevel"], m["theta"], m["pillow"], m["gdark"]
        if m["endcol"] is not None:
            m_hasend[i + 1] = True
            m_end[i + 1] = m["endcol"]
    var = g.var[I, J, Kk]
    col = g.col[I, J, Kk] * var[:, None]
    endf = m_hasend[mv] & (g.axis[I, J, Kk] == axis)
    col[endf] = m_end[mv[endf]] * var[endf][:, None]
    rough = g.rgh[I, J, Kk]
    A0ax = np.where(axis == 0, 1, 0)
    A1ax = np.where(axis == 2, 1, 2)
    dn = [np.where(axis == q, s, 0) for q in range(3)]
    flags = np.zeros((len(I), 4), np.int8)
    base_idx = (I, J, Kk)
    for e, (axsel, d) in enumerate(((A0ax, -1), (A0ax, 1), (A1ax, -1), (A1ax, 1))):
        w = [base_idx[q] + np.where(axsel == q, d, 0) for q in range(3)]
        sw = _look(solid, w[0], w[1], w[2], False)
        sa = _look(solid, w[0] + dn[0], w[1] + dn[1], w[2] + dn[2], False)
        gw = _look(g.grp, w[0], w[1], w[2], -1)
        mw = _look(g.mat, w[0], w[1], w[2], 0)
        groove = (mw != mv) | ((gw != gv) & (m_groove[mv] | m_groove[mw]))
        flags[:, e] = np.where(~sw, 1, np.where(sa, 0, np.where(groove, 2, 0)))
    # ---------------------------------------------------------------- texel fill
    atl = dict(col=np.zeros((size, size, 3), np.float32), nrm=np.zeros((size, size, 3), np.float32),
               rgh=np.zeros((size, size), np.float32), fill=np.zeros((size, size), bool))
    for pv in np.unique(cP):
        idx = np.nonzero(cP == pv)[0]
        CH = max(1, 600000 // int(pv * pv))
        for c0 in range(0, len(idx), CH):
            sl = idx[c0:c0 + CH]
            _fill(atl, int(pv), cx[sl], cy[sl], crot[sl], ao4[sl], col[sl], rough[sl], flags[sl], m_bev[mv[sl]],
                  m_th[mv[sl]], m_pil[mv[sl]], m_gd[mv[sl]])
    used = float(atl["fill"].mean())
    _dilate(atl, 3)
    bg = ~atl["fill"]
    atl["col"][bg] = atl["col"][~bg].mean(0)
    atl["nrm"][bg] = (0.0, 0.0, 1.0)
    atl["rgh"][bg] = float(atl["rgh"][~bg].mean())
    dx, dy = dummy[0], dummy[1]
    atl["col"][dy:dy + 4, dx:dx + 4] = lin((40, 36, 32))
    atl["nrm"][dy:dy + 4, dx:dx + 4] = (0.0, 0.0, 1.0)
    atl["rgh"][dy:dy + 4, dx:dx + 4] = 0.9
    # per-part fallback colour (mean visible face colour incl. AO, sRGB)
    face_rgb = {}
    cell_part = R_p[rid]
    for pi in np.unique(cell_part):
        mm = cell_part == pi
        face_rgb[int(pi)] = [int(round(v * 255)) for v in to_srgb((col[mm] * ao4[mm].mean(1)[:, None]).mean(0))]
    # ---------------------------------------------------------------- geometry
    # visible rect UVs (visible rects are 'rects' filtered in order)
    vis_iter = iter(range(nvis))
    vis_uv = {}
    for ri, r in enumerate(rects):
        if r[4]:
            continue
        vi = next(vis_iter)
        na, nb = r[7], r[8]
        p_ = int(Pr[vi])
        uvs = []
        for (da, db) in ((0, 0), (na, 0), (na, nb), (0, nb)):
            # half-texel inset: corners land on the centres of the island's border texels
            ia_ = 0.5 + da * (na * p_ - 1.0) / na
            ib_ = 0.5 + db * (nb * p_ - 1.0) / nb
            if rot[vi]:
                uvs.append(((px[vi] + ib_) / size, (py[vi] + ia_) / size))
            else:
                uvs.append(((px[vi] + ia_) / size, (py[vi] + ib_) / size))
        vis_uv[ri] = uvs
    out_parts = {}
    counters = {}
    for ri, r in enumerate(rects):
        pi = r[3]
        d = out_parts.setdefault(pi, dict(verts=[], faces=[], uvs=[]))
        n0 = len(d["verts"])
        ax_, s_, k_, _, hidden, a0, b0, na, nb = r
        A0, A1 = INPLANE[ax_]
        pl = k_ + (1 if s_ > 0 else 0)
        corners = ((0, 0), (na, 0), (na, nb), (0, nb))
        vs = []
        for (da, db) in corners:
            cvox = [0.0, 0.0, 0.0]
            cvox[ax_], cvox[A0], cvox[A1] = pl, a0 + da, b0 + db
            vs.append(tuple(g.lo + np.array(cvox) * V))
        if hidden:
            uvs = [((dx + 1 + 2 * (da > 0)) / size, (dy + 1 + 2 * (db > 0)) / size) for (da, db) in corners]
        else:
            uvs = vis_uv[ri]
        order = [0, 1, 2, 3] if s_ == NATURAL[ax_] else [0, 3, 2, 1]
        d["verts"] += [vs[o] for o in order]
        d["uvs"] += [uvs[o] for o in order]
        d["faces"].append((n0, n0 + 1, n0 + 2, n0 + 3))
        counters[pi] = counters.get(pi, 0) + 1
    t3 = time.time()
    pps = {k: round(float(max(2, round(P * dens[i + 1]))) / V, 1) for i, k in enumerate(part_keys)}
    log("BAKE %s: %d voxels, %d quads (%d hidden), %d face cells, %d AO points, atlas %d, P=%d (%s px/stud), "
        "%.0f%% used | mesh %.1fs AO %.1fs fill %.1fs" % (
            g.name, int(solid.sum()), len(rects), len(rects) - nvis, len(I), len(ukeys), size, P,
            ", ".join("%s %.0f" % kv for kv in pps.items()), used * 100, t1 - t0, t2 - t1, t3 - t2))
    return dict(P=P, pxPerStud=P / V, partPxPerStud=pps, size=size, parts=out_parts, part_keys=part_keys, atlas=atl,
                used=used, face_rgb=face_rgb, quads=len(rects), hidden=len(rects) - nvis)


def save_atlas(name, bake):
    atl = bake["atlas"]
    paths = dict(color=os.path.join(TEX_DIR, name + "_Color.png"), normal=os.path.join(TEX_DIR, name + "_Normal.png"),
                 rough=os.path.join(TEX_DIR, name + "_Roughness.png"),
                 mr=os.path.join(TEX_DIR, "glb_only", name + "_MR.png"))
    write_png(paths["color"], to_srgb(atl["col"]))
    write_png(paths["normal"], np.clip(atl["nrm"] * 0.5 + 0.5, 0, 1))
    r = np.clip(atl["rgh"], 0.0, 1.0)
    write_png(paths["rough"], r)
    r2 = 0.25 * (r[0::2, 0::2] + r[1::2, 0::2] + r[0::2, 1::2] + r[1::2, 1::2])
    write_png(paths["mr"], np.stack([r2, r2, np.zeros_like(r2)], 2))
    return paths


# =============================================================================================== terrain tiles
TILE_STUDS = 8.0


def _tnoise(xx, yy, freq, seed, octaves=3):
    """Tileable fbm over the 1024 tile (freq = lattice cells per tile)."""
    return fbm3(xx / ATLAS * freq, yy / ATLAS * freq, 0.0, seed, octaves, period=freq)


def _rr_mask(w, h, rc, bevel, profile="round"):
    """Rounded-rectangle block (w x h px): inside mask and bevel height 0..1 (quarter round or flat chamfer)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    px, py = xx + 0.5, yy + 0.5
    qx = np.abs(px - w / 2) - (w / 2 - rc)
    qy = np.abs(py - h / 2) - (h / 2 - rc)
    sd = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - rc
    d = -sd
    prof = np.clip(d / bevel, 0, 1)
    return d > 0, (prof if profile == "chamfer" else 1 - (1 - prof) ** 2)


class Tile:
    def __init__(self, seed):
        self.H = np.zeros((ATLAS, ATLAS), np.float32)
        self.C = np.zeros((ATLAS, ATLAS, 3), np.float32)
        self.R = np.zeros((ATLAS, ATLAS), np.float32)
        self.rng = np.random.default_rng(seed)

    def block(self, x0, y0, w, h, height, col, rough, rc=None, bevel=5.0, stack=False, over=False,
              profile="round", tilt=0.0):
        """tilt (studs): the flat top leans by up to this much corner to corner, so neighbouring blocks catch the
        light differently (reads as loose stones / leaves instead of printed tiles)."""
        rc = min(w, h) * 0.3 if rc is None else rc
        inside, prof = _rr_mask(w, h, rc, bevel, profile)
        ys = (y0 + np.arange(h)) % ATLAS
        xs = (x0 + np.arange(w)) % ATLAS
        ix = np.ix_(ys, xs)
        Hs = self.H[ix]
        base = float(Hs[inside].max()) if stack and inside.any() else 0.0
        hh = base + height * prof
        if tilt:
            sx, sy = self.rng.uniform(-1, 1, 2) * tilt
            gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
            hh = hh + prof * (sx * (gx / max(w - 1, 1) - 0.5) + sy * (gy / max(h - 1, 1) - 0.5))
        upd = inside & ((hh > Hs) | over)
        self.H[ix] = np.where(upd, hh, Hs)
        Cs = self.C[ix]
        Cs[upd] = col
        self.C[ix] = Cs
        Rs = self.R[ix]
        Rs[upd] = rough
        self.R[ix] = Rs


def _height_ao(H, pps, radius_px=44, dirs=16, steps=11):
    ao = np.zeros_like(H)
    for d in range(dirs):
        a = 2 * math.pi * (d + 0.5) / dirs
        hmax = np.zeros_like(H)
        for st in range(1, steps + 1):
            dist = radius_px * (st / steps) ** 1.5
            ox, oy = int(round(math.cos(a) * dist)), int(round(math.sin(a) * dist))
            if ox == 0 and oy == 0:
                continue
            Hs = np.roll(np.roll(H, -oy, 0), -ox, 1)
            hmax = np.maximum(hmax, (Hs - H) / (math.hypot(ox, oy) / pps))
        ao += 1.0 - np.sin(np.arctan(np.maximum(hmax, 0.0)))
    return ao / dirs


def _height_normal(H, pps, strength=1.0):
    gx = (np.roll(H, -1, 1) - np.roll(H, 1, 1)) * pps / 2
    gy = (np.roll(H, -1, 0) - np.roll(H, 1, 0)) * pps / 2
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(H)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def _finish_tile(t, name, ao_strength, pps, kind_notes):
    ao = _height_ao(t.H, pps)
    col = t.C * (1.0 - ao_strength + ao_strength * ao)[..., None]
    nrm = _height_normal(t.H, pps)
    paths = dict(color=os.path.join(TERRAIN_DIR, name + "_Color.png"),
                 normal=os.path.join(TERRAIN_DIR, name + "_Normal.png"),
                 rough=os.path.join(TERRAIN_DIR, name + "_Roughness.png"))
    srgb = to_srgb(col)
    write_png(paths["color"], srgb)
    write_png(paths["normal"], nrm * 0.5 + 0.5)
    write_png(paths["rough"], np.clip(t.R, 0, 1))
    avg = [int(round(v * 255)) for v in srgb.reshape(-1, 3).mean(0)]
    log("TERRAIN %s: mean sRGB %s, roughness %.2f" % (name, avg, float(t.R.mean())))
    return dict(paths=paths, avg=avg, notes=kind_notes)


def terrain_pebble_path(seed=5505):
    """Compacted earth path paved with blocky pebbles: axis-aligned blocks of 0.19-0.75 studs snapped to a
    1/16-stud grid, tight corners and chamfered edges, some split into two stepped halves (chipped), muted greys."""
    t = Tile(seed)
    rng = t.rng
    pps = ATLAS / TILE_STUDS
    yy, xx = np.mgrid[0:ATLAS, 0:ATLAS].astype(np.float32)
    n1 = _tnoise(xx, yy, 4, seed + 1)
    n2 = _tnoise(xx, yy, 16, seed + 2, 2)
    e0, e1 = lin((64, 56, 46)), lin((82, 72, 59))
    tt = np.clip(0.75 * n1 + 0.25 * n2, 0, 1)[..., None]
    cell = _ihash((xx // 32).astype(np.int64), (yy // 32).astype(np.int64), 0, seed + 3).astype(np.float32)
    t.C[:] = (e0 * (1 - tt) + e1 * tt) * (0.96 + 0.08 * cell)[..., None]
    t.R[:] = 0.93
    CELL = 8
    NC = ATLAS // CELL
    occ = np.zeros((NC, NC), bool)
    pal = [lin(c) for c in ((98, 94, 88), (86, 84, 80), (108, 100, 90), (78, 74, 70), (102, 96, 86),
                            (92, 90, 86), (112, 104, 94), (84, 80, 74), (110, 96, 80), (70, 68, 64))]
    placed = 0
    for (lo, hi, tries) in ((8, 12, 90), (6, 8, 520), (4, 6, 1500), (3, 4, 2600)):
        for _ in range(tries):
            w = int(rng.integers(lo, hi + 1))
            h = int(np.clip(round(w * rng.uniform(0.55, 1.5)), 3, 12))
            cx, cy = int(rng.integers(NC)), int(rng.integers(NC))
            ys = (cy - 1 + np.arange(h + 2)) % NC
            xs = (cx - 1 + np.arange(w + 2)) % NC
            if occ[np.ix_(ys, xs)].any():
                continue
            occ[np.ix_((cy + np.arange(h)) % NC, (cx + np.arange(w)) % NC)] = True
            ht = 0.035 + 0.1 * min(w, h) / 16.0
            col = pal[int(rng.integers(len(pal)))] * rng.uniform(0.93, 1.07)
            rough = 0.7 + 0.08 * rng.uniform()
            x0, y0 = cx * CELL + 1, cy * CELL + 1
            tl = 0.03 + 0.05 * min(w, h) / 16.0
            if min(w, h) >= 5 and rng.uniform() < 0.35:          # chipped: two stepped halves
                if w >= h:
                    k = int(rng.integers(2, w - 1))
                    parts = ((x0, y0, k * CELL - 1, h * CELL - 2), (x0 + k * CELL, y0, (w - k) * CELL - 2, h * CELL - 2))
                else:
                    k = int(rng.integers(2, h - 1))
                    parts = ((x0, y0, w * CELL - 2, k * CELL - 1), (x0, y0 + k * CELL, w * CELL - 2, (h - k) * CELL - 2))
                for pi_, (bx, by, bw, bh) in enumerate(parts):
                    f = 1.0 if pi_ == 0 else rng.uniform(0.6, 0.85)
                    t.block(bx, by, bw, bh, ht * f, col * (1.0 if pi_ == 0 else rng.uniform(0.92, 1.04)), rough,
                            rc=min(bw, bh) * 0.14, bevel=3.0, profile="chamfer", tilt=tl)
            else:
                t.block(x0, y0, w * CELL - 2, h * CELL - 2, ht, col, rough, rc=min(w, h) * CELL * 0.16,
                        bevel=3.0, profile="chamfer", tilt=tl)
            placed += 1
    for _ in range(260):
        cx, cy = int(rng.integers(NC)), int(rng.integers(NC))
        if occ[cy, cx]:
            continue
        occ[cy, cx] = True
        col = pal[int(rng.integers(len(pal)))] * rng.uniform(0.75, 0.9)
        t.block(cx * CELL + 1, cy * CELL + 1, CELL - 2, CELL - 2, 0.015, col, 0.8, rc=1.5, bevel=2.0,
                profile="chamfer")
    log("TERRAIN pebble path: %d pebbles, coverage %.0f%%" % (placed, occ.mean() * 100))
    return _finish_tile(t, "VoxPebblePath", 0.55, pps, "Compacted earth path paved with blocky pebbles.")


def terrain_forest_floor(seed=6606):
    """Dark humus in faint 1/8-stud soil cells, muted leaf-litter blocks stacked in layers, a few twigs and pebbles,
    and low cushions of moss blocks in small tileable beds. Low contrast so the 8-stud repeat does not read."""
    t = Tile(seed)
    rng = t.rng
    pps = ATLAS / TILE_STUDS
    yy, xx = np.mgrid[0:ATLAS, 0:ATLAS].astype(np.float32)
    n1 = _tnoise(xx, yy, 4, seed + 1)
    n2 = _tnoise(xx, yy, 12, seed + 2, 2)
    h0, h1 = lin((33, 28, 22)), lin((50, 41, 32))
    tt = np.clip(0.7 * n1 + 0.3 * n2, 0, 1)[..., None]
    cell = _ihash((xx // 16).astype(np.int64), (yy // 16).astype(np.int64), 0, seed + 4).astype(np.float32)
    t.C[:] = (h0 * (1 - tt) + h1 * tt) * (0.95 + 0.1 * cell)[..., None]
    t.R[:] = 0.95
    moss_field = _tnoise(xx, yy, 6, seed + 3)
    # dense, low-contrast litter: the humus only peeks through, so the tile reads as a material, not as objects
    leaves = [lin(c) for c in ((68, 58, 46), (76, 64, 50), (62, 54, 44), (82, 70, 56), (72, 64, 50),
                               (88, 74, 56))]
    for _ in range(360):
        w = int(rng.integers(26, 52))
        h = int(np.clip(round(w * rng.uniform(0.5, 0.9)), 16, 46))
        if rng.uniform() < 0.5:
            w, h = h, w
        x0, y0 = int(rng.integers(ATLAS)), int(rng.integers(ATLAS))
        if moss_field[y0, x0] > 0.59:
            continue
        t.block(x0, y0, w, h, 0.016, leaves[int(rng.integers(len(leaves)))] * rng.uniform(0.74, 0.98),
                0.78, rc=min(w, h) * 0.25, bevel=3.0, stack=True, profile="chamfer", tilt=0.03)
    needles = [lin(c) for c in ((72, 56, 42), (62, 49, 37), (80, 62, 46))]
    for _ in range(200):
        L = int(rng.integers(14, 24))
        w, h = (L, 6) if rng.uniform() < 0.5 else (6, L)
        x0, y0 = int(rng.integers(ATLAS)), int(rng.integers(ATLAS))
        if moss_field[y0, x0] > 0.59:
            continue
        t.block(x0, y0, w, h, 0.012, needles[int(rng.integers(3))] * rng.uniform(0.93, 1.07), 0.84, rc=1.5,
                bevel=2.0, stack=True, profile="chamfer")
    for _ in range(6):
        L = int(rng.integers(90, 200))
        w, h = (L, 6) if rng.uniform() < 0.5 else (6, L)
        t.block(int(rng.integers(ATLAS)), int(rng.integers(ATLAS)), w, h, 0.045,
                lin((66, 57, 48)) * rng.uniform(0.9, 1.1), 0.86, rc=2.0, bevel=2.5, stack=True, profile="chamfer")
    moss = [lin(c) for c in ((44, 52, 32), (50, 60, 36), (40, 48, 30), (47, 56, 34))]
    for _ in range(9000):
        x0, y0 = int(rng.integers(ATLAS)), int(rng.integers(ATLAS))
        f = moss_field[y0, x0]
        if f < 0.57 or rng.uniform() > (f - 0.57) * 7:
            continue
        s = int(rng.integers(16, 32))
        t.block(x0, y0, s, s, 0.03 + 0.035 * rng.uniform(), moss[int(rng.integers(4))] * rng.uniform(0.94, 1.06),
                0.9, rc=s * 0.15, bevel=4.0, profile="chamfer", tilt=0.02)
    for _ in range(14):
        s = int(rng.integers(14, 26))
        t.block(int(rng.integers(ATLAS)), int(rng.integers(ATLAS)), s, int(s * rng.uniform(0.7, 1.2)), 0.05,
                lin((84, 81, 76)) * rng.uniform(0.9, 1.06), 0.76, rc=3.0, bevel=3.5, over=True, profile="chamfer")
    return _finish_tile(t, "VoxForestFloor", 0.6, pps, "Humus, blocky leaf litter, needles, twigs and moss beds.")


TERRAIN = [
    dict(name="VoxPebblePath", fn=terrain_pebble_path, base="Ground", replaces="LS_EarthPath1 (the grainy pebbly "
         "earth path)", studsPerTile=8),
    dict(name="VoxForestFloor", fn=terrain_forest_floor, base="LeafyGrass", replaces="LS_ForestFloor",
         studsPerTile=8),
]


# =============================================================================================== Blender export
def atlas_material(name, paths):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    def img(path, cs):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    tc = img(paths["color"], "sRGB")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = img(paths["normal"], "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tr = img(paths["mr"], "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    m.use_backface_culling = True
    return m


def make_mesh_object(name, d, mat, parent):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in d["verts"]], [], d["faces"])
    uvl = me.uv_layers.new(name="UVMap")
    uvl.data.foreach_set("uv", np.asarray(d["uvs"], np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.zeros(len(me.polygons), bool))
    me.materials.append(mat)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    return ob


def to_roblox(v):
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def _glb_split(data):
    magic, ver, length = struct.unpack("<III", data[:12])
    clen, ctype = struct.unpack("<II", data[12:20])
    return ver, json.loads(data[20:20 + clen].decode("utf-8")), data[20 + clen:]


def glb_set_metallic_zero(path):
    with open(path, "rb") as f:
        data = f.read()
    ver, js, rest = _glb_split(data)
    for m in js.get("materials", []):
        m.setdefault("pbrMetallicRoughness", {})["metallicFactor"] = 0
        m["doubleSided"] = False
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, ver, 12 + len(body)) + body)


STYLE_RULES = [
    'Voxels only: every surface is axis-aligned blocks on a 0.5-stud grid; built pieces use whole-block sizes (logs 1.5 x 1.5, planks 0.5 thick, shake courses 0.5, stones 0.5-1.5 high); no rotated blocks, curves or alpha cards.',
    'Realistic scale and silhouette first, then voxelise: 1 stud = 0.28 m, player 5.5, door 4 x 7.5, conifers 35-50, oaks 25-30; forms come from the real species or building, never cartoon-exaggerated.',
    'One flat colour per block face from a realistic, slightly desaturated palette (bark 50-115, needles 30-75, leaf green 50-120, granite 80-110, weathered logs 85-105 sRGB); no photo texture, no noise, no grain.',
    'Variation lives per block: +/-7-9% per group (log, plank, shake, stone, leaf lobe, needle pad) and +/-3-8% per voxel; outer and upper foliage lighter and warmer, inner foliage darker and cooler.',
    'Bake AO between blocks into the ColorMap (corner AO + hemisphere rays out to 3.5-6 studs, the ground counts as an occluder); never bake sunlight or shadows - Roblox Realistic lighting does that.',
    'Normal maps only describe blocks: 1-2 px convex bevels on wood and stone, darkened grooves where logs, planks or stones meet, soft domes on leaf and needle blocks. Roughness by material (leaves 0.64, needles 0.74, wood 0.8-0.86, bark and granite 0.82-0.9); no metalness.',
    'Put light-catching detail in real geometry: V-grooves between log courses, stepped shake courses, stepped knee braces, bark ridges and furrows (+/-1 voxel), drooping needle pads, chipped stone edges.',
    'Budget: greedy-merged quads with hidden faces dropped, one MeshPart per collision role, one atlas per asset at the highest density that fits (wood/stone 14-32 px/stud, foliage at 0.6x); trees under 13k tris, small buildings under 6k, rocks under 0.5k.',
    'Terrain tiles speak the same language: axis-aligned bevelled pebbles, leaves and moss blocks with slightly tilted tops on a flat base, low contrast, 8 studs per tile, MaterialPattern Regular so blocks stay on the world grid.',
]

IMPORT_NOTES = [
    "Geometry: import StyleTest/B/StyleTest_B.glb (3D Importer / Open Cloud). Each asset root arrives as a Model of "
    "MeshParts named <Asset>_<Role>[_n]; re-centre with the asset 'origin' (WorldPivot = CFrame.new(origin), then "
    "PivotTo) like the other categories. The meshes carry normals, UVs and MikkTSpace tangents.",
    "Surfaces: every part gets ONE SurfaceAppearance from its 'surfaceAppearance' block: ColorMap / NormalMap / "
    "RoughnessMap = uploaded ids of those PNGs (one atlas set per asset, shared by all of that asset's parts), "
    "MetalnessMap empty, AlphaMode Overlay, Color white (the maps are final albedo with baked AO). Roughness PNGs are "
    "8-bit grayscale; normal maps are OpenGL (+Y). textures/glb_only/*_MR.png are the packed glTF copies embedded in "
    "the GLB - never upload them.",
    "Per part: CanCollide = collide, CollisionFidelity = collision (edit time), CastShadow, CanQuery, CanTouch, "
    "Anchored = true, Material = robloxMaterial (physics/footsteps), Color = rgb (fallback). VoxOak_Bark gets the "
    "Climbable tag; Perch1-4 sit on the level limb tops.",
    "Terrain: create one MaterialVariant per 'terrainMaterials' entry under MaterialService (BaseMaterial as given, "
    "StudsPerTile 8, MaterialPattern Regular), then SetBaseMaterialOverride. The ColorMaps are final colour, so set "
    "Terrain:SetMaterialColor for those bases to (255,255,255) or re-tune from there.",
]


def export_all(results, terrain_info, only=None):
    """results: list of (name, grid, spec, bake, tex_paths). Builds Blender objects, exports the GLB, writes the
    manifest. Returns the manifest dict."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    entries = []
    for (name, g, spec, bake, paths) in results:
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        scene.collection.objects.link(root)
        mat = atlas_material(name + "_Atlas", paths)
        parts = []
        role_count = {}
        lo = np.array([1e9] * 3)
        hi = np.array([-1e9] * 3)
        for pi, key in enumerate(bake["part_keys"], start=1):
            d = bake["parts"].get(pi)
            if not d:
                continue
            pdef = dict(spec["parts"])[key]
            role = pdef["role"]
            role_count[role] = role_count.get(role, 0) + 1
            pname = "%s_%s" % (name, role) + ("" if role_count[role] == 1 else "_%d" % role_count[role])
            make_mesh_object(pname, d, mat, root)
            vv = np.asarray(d["verts"])
            lo, hi = np.minimum(lo, vv.min(0)), np.maximum(hi, vv.max(0))
            tris = 2 * len(d["faces"])
            if tris > TRI_LIMIT:
                raise RuntimeError("%s has %d triangles" % (pname, tris))
            collide = bool(pdef.get("collide"))
            parts.append(dict(
                name=pname, role=role, robloxMaterial=pdef["roblox"], rgb=bake["face_rgb"].get(pi, [128, 128, 128]),
                collide=collide, collision=pdef.get("collision", "Hull") if collide else "Box",
                castShadow=True, canQuery=collide, canTouch=collide, tags=list(pdef.get("tags", [])), tris=tris,
                surfaceAppearance=dict(colorMap=rel(paths["color"]), normalMap=rel(paths["normal"]),
                                       roughnessMap=rel(paths["rough"]), metalnessMap=None, alphaMode="Overlay",
                                       color=[255, 255, 255]),
                transparency=0, doubleSided=False, backFacesInMesh=False, neon=False))
        a, b = to_roblox(lo), to_roblox(hi)
        atts = {}
        for an, at in g.attachments.items():
            atts[an] = dict(position=to_roblox(at["position"]), look=to_roblox(at["look"]), up=to_roblox(at["up"]))
        entries.append(dict(
            root=root, name=name, kind=spec["kind"], tags=spec["tags"], notes=spec["notes"],
            size=[round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3), round(float(hi[1] - lo[1]), 3)],
            boundsMin=[min(x, y) for x, y in zip(a, b)], boundsMax=[max(x, y) for x, y in zip(a, b)],
            tris=sum(p["tris"] for p in parts), pxPerStud=round(bake["pxPerStud"], 1),
            atlas=dict(size=bake["size"], texelsPerVoxelFace=bake["P"], pxPerStudByPart=bake["partPxPerStud"],
                       used=round(bake["used"], 3), quads=bake["quads"], hiddenQuads=bake["hidden"]),
            attachments=atts, parts=parts, _lox=float(lo[0])))
    x = 0.0
    for e in entries:
        offset = x - e["_lox"]
        e["root"].location = (offset, 0.0, 0.0)
        e["origin"] = [round(offset, 4), 0.0, 0.0]
        x += e["size"][0] + 8.0
    bpy.context.view_layer.update()
    for o in scene.objects:
        o.select_set(False)
    for e in entries:
        e["root"].select_set(True)
        for c in e["root"].children_recursive:
            c.select_set(True)
    glb_name = GLB_NAME if not only else CATEGORY + "_test.glb"
    glb = os.path.join(OUT, glb_name)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_image_format="AUTO", export_materials="EXPORT", export_normals=True,
                              export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
                              export_attributes=False)
    glb_set_metallic_zero(glb)
    import ad_finalize
    rep = ad_finalize.glb_report(glb)
    problems = list(rep["problems"])
    upload = []
    for e in entries:
        for p in e["parts"]:
            for key, kind in (("colorMap", "color"), ("normalMap", "normal"), ("roughnessMap", "roughness")):
                f = p["surfaceAppearance"][key]
                hit = next((u for u in upload if u["file"] == f), None)
                if hit is None:
                    info = ad_finalize.png_info(os.path.join(EXP_ROOT, *f.split("/")))
                    hit = dict(file=f, kind=kind, usedBy=[], size=[info[0], info[1]], bitDepth=info[2],
                               channels=info[3], bytes=os.path.getsize(os.path.join(EXP_ROOT, *f.split("/"))))
                    if kind == "roughness" and info[3] != "gray":
                        problems.append("%s is not grayscale" % f)
                    upload.append(hit)
                if e["name"] not in hit["usedBy"]:
                    hit["usedBy"].append(e["name"])
    glb_only = sorted(rel(os.path.join(TEX_DIR, "glb_only", fn)) for fn in os.listdir(os.path.join(TEX_DIR, "glb_only"))
                      if fn.endswith(".png"))
    terrain = []
    for tdef in TERRAIN:
        info = terrain_info.get(tdef["name"])
        if not info:
            continue
        terrain.append(dict(name=tdef["name"], baseMaterial=tdef["base"], replaces=tdef["replaces"],
                            studsPerTile=tdef["studsPerTile"], materialPattern="Regular",
                            colorMap=rel(info["paths"]["color"]), normalMap=rel(info["paths"]["normal"]),
                            roughnessMap=rel(info["paths"]["rough"]), metalnessMap=None, meanRGB=info["avg"],
                            terrainColor=[255, 255, 255], notes=info["notes"]))
    nbytes = os.path.getsize(glb)
    manifest = dict(
        schema="LS-Real-1", category=CATEGORY, variant="B", style="Blocky voxel realism",
        pathsRelativeTo="BlenderExports", units="1 Blender unit = 1 Roblox stud",
        axes="Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
        tangentSpace="MikkTSpace tangents in the GLB; normal maps OpenGL (+Y), tangent space",
        glbs=[dict(file=rel(glb), bytes=nbytes, sizeMB=round(nbytes / 1e6, 2), assets=[e["name"] for e in entries],
                   primitives=rep["primitives"], maxMeshTris=rep["maxMeshTris"],
                   embeddedImages=[i["name"] for i in rep["embeddedImages"]])],
        textureFolder=rel(TEX_DIR), uploadTextures=upload, glbOnlyTextures=glb_only, terrainMaterials=terrain,
        styleRules=STYLE_RULES, import_=None, assets=[], warnings=[], adCheck=None)
    manifest["import"] = IMPORT_NOTES
    del manifest["import_"]
    for e in entries:
        a = {k: v for k, v in e.items() if k not in ("root", "_lox")}
        a["glb"] = rel(glb)
        manifest["assets"].append(a)
        if e["tris"] > 12000:
            manifest["warnings"].append("%s has %d tris" % (e["name"], e["tris"]))
    if len(upload) > 16:
        problems.append("%d upload images in one folder (budget 16)" % len(upload))
    manifest["adCheck"] = dict(problems=problems, glbs=1, uploadImages=len(upload),
                               totalTris=sum(e["tris"] for e in entries), assets=len(entries))
    mpath = os.path.join(OUT, (CATEGORY if not only else CATEGORY + "_test") + ".manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    log("EXPORTED %s (%.2f MB), %d assets, %d tris, %d problems" % (glb, nbytes / 1e6, len(entries),
                                                                   manifest["adCheck"]["totalTris"], len(problems)))
    for p in problems:
        log("PROBLEM " + p)
    for e in entries:
        log("ASSET %-11s size %s tris %5d px/stud %.0f parts %s" % (
            e["name"], e["size"], e["tris"], e["pxPerStud"], ", ".join("%s %d" % (p["name"], p["tris"])
                                                                       for p in e["parts"])))
    log("MANIFEST " + mpath)
    return manifest, glb


# =============================================================================================== previews
LIGHTS = {"midday": dict(elev=58.0, bearing=32.0, strength=0.075, exposure=-0.5),
          "late": dict(elev=13.0, bearing=74.0, strength=0.075, exposure=0.25)}
PLACE = {"VoxCabin": ((0.0, -6.0), 0.0), "VoxSpruce": ((-21.0, -15.0), 0.5), "VoxOak": ((21.0, -8.0), 1.2),
         "VoxBoulder": ((-12.0, 13.0), 0.7)}
FIGURES = [((-5.6, 1.8, 1.0), 180.0),        # on the porch next to the door (deck top = 1.0, cabin at y -6)
           ((16.5, -2.5, 0.0), 140.0),       # under the oak
           ((-15.8, 10.2, 0.0), 200.0)]      # beside the boulder
SHOTS = {
    "set": dict(loc=(8.0, 50.0, 5.0), target=(-1.0, -4.0, 13.0), lens=19.0),
    "cabin": dict(loc=(9.5, 22.0, 5.0), target=(-1.0, -1.0, 6.0), lens=24.0),
    "spruce": dict(loc=(-33.0, 13.0, 5.0), target=(-21.0, -15.0, 18.0), lens=16.0),
    "oak": dict(loc=(17.0, 12.0, 5.0), target=(21.0, -8.0, 13.5), lens=16.0),
    "boulder": dict(loc=(-5.5, 20.5, 4.0), target=(-12.0, 13.0, 1.6), lens=30.0),
    "ground": dict(loc=(4.0, 24.0, 4.2), target=(1.5, 15.5, 0.0), lens=30.0),
}


def setup_render(samples, res):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception as ex:          # CPU fallback
        log("GPU unavailable: %s" % ex)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = True
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.caustics_reflective = False
    c.caustics_refractive = False
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    world = bpy.data.worlds.new("SB_Sky")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = True
    sky.altitude = 300.0
    try:
        sky.aerosol_density = 1.6
    except AttributeError:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    scene.world = world
    return scene


def set_light(scene, key):
    L = LIGHTS[key]
    nt = scene.world.node_tree
    sky = [n for n in nt.nodes if n.type == "TEX_SKY"][0]
    bg = [n for n in nt.nodes if n.type == "BACKGROUND"][0]
    sky.sun_elevation = math.radians(L["elev"])
    sky.sun_rotation = math.radians(L["bearing"])
    bg.inputs["Strength"].default_value = L["strength"]
    scene.view_settings.exposure = L["exposure"]


def tex_material(name, paths, tint=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    def img(path, cs):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    tc = img(paths["color"], "sRGB")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = img(paths["normal"], "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tr = img(paths["rough"], "Non-Color")
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    return m


def ground_mesh(name, verts2d, faces, z, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x, y, z) for (x, y) in verts2d], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    uv = []
    for f in faces:
        for vi in f:
            x, y = verts2d[vi]
            uv += [x / TILE_STUDS, y / TILE_STUDS]
    uvl.data.foreach_set("uv", np.asarray(uv, np.float32))
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def path_ribbon(points, width):
    pts = [np.array(p, float) for p in points]
    dense = []
    for i in range(len(pts) - 1):
        for t in np.linspace(0, 1, 12, endpoint=False):
            p0, p1 = pts[max(i - 1, 0)], pts[i]
            p2, p3 = pts[i + 1], pts[min(i + 2, len(pts) - 1)]
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                       (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
            dense.append(q)
    dense.append(pts[-1])
    verts, faces = [], []
    for i, p in enumerate(dense):
        d = dense[min(i + 1, len(dense) - 1)] - dense[max(i - 1, 0)]
        d = d / (np.linalg.norm(d) + 1e-9)
        nrm = np.array([-d[1], d[0]])
        w = width * (1.0 + 0.12 * math.sin(i * 0.7))
        verts += [tuple(p + nrm * w / 2), tuple(p - nrm * w / 2)]
        if i:
            b = 2 * i
            faces.append((b - 2, b, b + 1, b - 1))
    return verts, faces


def figure(loc, yaw):
    """Blocky 5.5-stud avatar (R15-ish proportions) for scale."""
    import bmesh
    mats = {}

    def mat(name, rgb):
        if name not in mats:
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = (*lin(rgb).tolist(), 1.0)
            b.inputs["Roughness"].default_value = 0.6
            mats[name] = m
        return mats[name]
    boxes = [((-0.5, 0, 1.15), (0.92, 0.92, 2.3), "legs", (52, 56, 66)),
             ((0.5, 0, 1.15), (0.92, 0.92, 2.3), "legs", (52, 56, 66)),
             ((0.0, 0, 3.3), (2.0, 1.0, 2.0), "shirt", (86, 100, 122)),
             ((-1.46, 0, 3.3), (0.9, 0.9, 2.0), "shirt", (86, 100, 122)),
             ((1.46, 0, 3.3), (0.9, 0.9, 2.0), "shirt", (86, 100, 122)),
             ((0.0, 0, 4.925), (1.15, 1.15, 1.15), "skin", (196, 160, 130))]
    obs = []
    for i, (c, s, mn, rgb) in enumerate(boxes):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=s, verts=bm.verts)
        bmesh.ops.translate(bm, vec=c, verts=bm.verts)
        me = bpy.data.meshes.new("SB_Fig%d" % i)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat("SB_Fig_" + mn, rgb))
        ob = bpy.data.objects.new("SB_Fig%d" % i, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (0, 0, yaw)
        obs.append(ob)
    return obs


def camera(scene, loc, target, lens):
    cam = bpy.data.objects.get("SB_Cam")
    if cam is None:
        cam = bpy.data.objects.new("SB_Cam", bpy.data.cameras.new("SB_Cam"))
        scene.collection.objects.link(cam)
    from mathutils import Vector
    cam.data.lens = lens
    cam.data.sensor_width = 36
    cam.data.clip_start = 0.05
    cam.data.clip_end = 3000
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def render_previews(glb, terrain_info, shots, lights, samples, res):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = setup_render(samples, res)
    bpy.ops.import_scene.gltf(filepath=glb)
    roots = {o.name: o for o in scene.objects if o.parent is None and o.name in PLACE}
    for name, ((x, y), yaw) in PLACE.items():
        if name in roots:
            roots[name].location = (x, y, 0.0)
            roots[name].rotation_euler = (0.0, 0.0, yaw)
    floor = tex_material("SB_ForestFloor", terrain_info["VoxForestFloor"]["paths"])
    path = tex_material("SB_PebblePath", terrain_info["VoxPebblePath"]["paths"])
    S = 300.0
    ground_mesh("SB_Ground", [(-S, -S), (S, -S), (S, S), (-S, S)], [(0, 1, 2, 3)], 0.0, floor)
    pv, pf = path_ribbon([(3.0, 90.0), (4.5, 55.0), (1.0, 30.0), (0.0, 12.0), (0.0, 4.5)], 4.6)
    ground_mesh("SB_Path", pv, pf, 0.004, path)
    pv2, pf2 = path_ribbon([(7.5, 4.6), (12.0, 7.5), (16.5, 12.0), (19.0, 18.0)], 2.6)
    ground_mesh("SB_Path2", pv2, pf2, 0.006, path)
    for (loc, yaw) in FIGURES:
        figure(loc, math.radians(yaw))
    out = []
    os.makedirs(PREV, exist_ok=True)
    for sk in shots:
        sd = SHOTS[sk]
        camera(scene, sd["loc"], sd["target"], sd["lens"])
        for lk in lights:
            set_light(scene, lk)
            p = os.path.join(PREV, "B_%s_%s.png" % (sk, lk))
            scene.render.filepath = p
            t = time.time()
            bpy.ops.render.render(write_still=True)
            log("PREVIEW %s (%.0fs)" % (p, time.time() - t))
            out.append(p)
    return out


def contact_sheet(paths, out_path, cols=2):
    ims = []
    for p in paths:
        im = bpy.data.images.load(p, check_existing=False)
        w, h = im.size
        a = np.empty(w * h * 4, np.float32)
        im.pixels.foreach_get(a)
        a = a.reshape(h, w, 4)[..., :3]
        a = 0.25 * (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2])
        ims.append(a)
        bpy.data.images.remove(im)
    h, w = ims[0].shape[:2]
    rows = (len(ims) + cols - 1) // cols
    sheet = np.ones((rows * h + (rows - 1) * 6, cols * w + (cols - 1) * 6, 3), np.float32)
    for i, a in enumerate(ims):
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * (h + 6)
        sheet[y0:y0 + h, c * (w + 6):c * (w + 6) + w] = a
    write_png(out_path, sheet)
    return out_path


# =============================================================================================== main
def main():
    t0 = time.time()
    only = [s for s in OPTS.get("only", "").split(",") if s]
    names = only or ["VoxSpruce", "VoxOak", "VoxCabin", "VoxBoulder"]
    os.makedirs(os.path.join(TEX_DIR, "glb_only"), exist_ok=True)
    os.makedirs(TERRAIN_DIR, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    glb = os.path.join(OUT, GLB_NAME if not only else CATEGORY + "_test.glb")
    terrain_info = {}
    if "renderonly" not in FLAGS:
        results = []
        for name in names:
            t = time.time()
            g, spec = BUILDERS[name]()
            log("BUILD %s: grid %s, %d voxels (%.1fs)" % (name, g.n, int((g.mat > 0).sum()), time.time() - t))
            bake = bake_asset(g, spec)
            paths = save_atlas(name, bake)
            results.append((name, g, spec, bake, paths))
        if "noterrain" not in FLAGS:
            for tdef in TERRAIN:
                terrain_info[tdef["name"]] = tdef["fn"]()
        else:
            for tdef in TERRAIN:
                terrain_info[tdef["name"]] = _terrain_from_disk(tdef["name"])
        manifest, glb = export_all(results, terrain_info, only=only)
    else:
        for tdef in TERRAIN:
            terrain_info[tdef["name"]] = _terrain_from_disk(tdef["name"])
    if "norender" not in FLAGS:
        quick = "quick" in FLAGS
        samples = int(OPTS.get("samples", "24" if quick else "128"))
        res = tuple(int(v) for v in OPTS.get("res", "960x540" if quick else "1600x900").split("x"))
        shots = OPTS.get("shots", "set,cabin,spruce,oak,boulder,ground").split(",")
        lights = OPTS.get("lights", "midday,late").split(",")
        prev = render_previews(glb, terrain_info, shots, lights, samples, res)
        want = ("B_set_midday.png", "B_set_late.png", "B_cabin_midday.png", "B_spruce_midday.png",
                "B_boulder_midday.png", "B_ground_late.png")
        main_shots = sorted((p for p in prev if os.path.basename(p) in want),
                            key=lambda p: want.index(os.path.basename(p)))
        if len(main_shots) == len(want):
            log("PREVIEW " + contact_sheet(main_shots, os.path.join(PREV, "_B_overview.png"), cols=3))
    log("DONE in %.0fs" % (time.time() - t0))


def _terrain_from_disk(name):
    paths = dict(color=os.path.join(TERRAIN_DIR, name + "_Color.png"),
                 normal=os.path.join(TERRAIN_DIR, name + "_Normal.png"),
                 rough=os.path.join(TERRAIN_DIR, name + "_Roughness.png"))
    return dict(paths=paths, avg=[0, 0, 0], notes="")


if __name__ == "__main__":
    main()
