"""
map1_far_exports.py - HUNGER GAMES (BETA) / LAST STANDING, Map 1 "the green land": the two far-view exports
(Blender 5.3, headless). A companion of map1_green_land.py (pass 3). It imports that generator as a module for its
palette, its far-range field and its export helpers, reads the generator's cached field, and NEVER writes any of the
generator's own 22 export files: it checks their SHA-256 before and after every run and stops if one changed.

Why a separate script: the generator's "assets" stage rewrites all three of its GLBs at once. These two files were
added on 15 Nov 2026 (docs/design/Map1Build.md, decision 7) while other agents were packing and uploading the pass-3
exports, so they are made here, from the cached field, without re-running anything.

What it writes
  <export dir>/Map1_SkylineCut.glb + .manifest.json
      The far range (r 2,600-7,600) of Map1_Skyline.glb, re-cut. The geometry is the generator's own build_skyline():
      the same 44,000 triangles and the same three painted classes. Roblox caps a part at 2,048 studs on any axis and
      the eight sector meshes are up to 6,027 across, so the triangles are regrouped into square tiles on the world's
      own axes: no part's bounding box is over 2,000 studs. Each tile belongs to one of the eight sector assets, which
      keep their names (M1_Skyline_N ... M1_Skyline_NW), so Map1_Layout.json's eight placements at the map centre
      still apply. Parts are M1_Skyline_<sector>_T<nn>_<role>; every part of a sector has the colour that sector's
      role had in Map1_Skyline.glb. Flat-shaded, single-sided, facing up (toward the arena), no collision, no shadow.
  <export dir>/Map1_FarValley.glb + .manifest.json
      A low-poly copy of the valley floor and sides for the view where voxel terrain is not streamed in: a decimated
      height field on a polar grid (2-degree steps: cells about 30 studs at r 850 growing to 64 x 96 at the rim; the
      vertices are nudged off the exact grid, FV_JITTER, so that a patch of one class is not a rectangle seen from
      the horn), fitted as a LOWER ENVELOPE of the true surface and dropped 6 studs, so real terrain covers every bit
      of it wherever terrain is present. Tiles M1_Far_A1 ... M1_Far_C3 (a 3 x 3 grid over r 850-2,750) and M1_Far_Core (r
      under 850: optional, see the manifest). Parts M1_Far_<tile>_<class>: Grass, DryGrass, Heather, Rock, Scree,
      Water (the lake's bed in the lake's colour) and Canopy (a dark green sheet 18-24 studs above the ground where the
      conifers are dense). Ground classes are smooth-shaded; the canopy is flat-shaded. Single-sided, faces up, no
      collision, no shadow.
  art/manifests/Map1_SkylineCut.manifest.json, Map1_FarValley.manifest.json   (a run into the default folder only)
  <preview dir>/far_classes.png        our data only: the far valley's classes from above
  <preview dir>/far_*.png              the render stage: views with terrain and scatter removed past r 1,024

Both manifests keep the pass-3 schema (assets in a row along +X, origin, boundsMin/Max, one flat colour per part) and
add, per part, "position" and "size": the part's bounding-box centre and extent in Roblox world space when its asset
stands at the map centre, which is where every asset of both files belongs (position 0, 0, 0; yaw 0).

Run (from the repo root)
  blender --background --factory-startup --python art/blender/map1_far_exports.py -- <export dir> <preview dir> [stages]
  export dir   default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Map1
  preview dir  default art/previews/Map1
  stages       comma list of skyline, farvalley, verify, render (default: skyline,farvalley,verify)
  env MAP1_WORK   the generator's work folder: field.npz (and Map1_scene.blend for the render stage)
  env MAP1_SRC    the folder holding the generator's 22 exports (default: the default export dir). Read only.
  env MAP1_SAMPLES, MAP1_RES   as the generator (render stage)
The verify stage needs no Blender data: it reads the two GLBs back with numpy and prints PASS/FAIL lines.
"""
import hashlib
import json
import math
import os
import shutil
import struct
import sys
import time
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402

import map1_green_land as G  # noqa: E402

log = G.log
OUT, PREV, WORK = G.OUT, G.PREV, G.WORK
STAGES = [s.strip() for s in G._arg(2, "skyline,farvalley,verify").split(",") if s.strip()]
SRC = os.path.abspath(os.environ.get("MAP1_SRC") or G.DEFAULT_OUT)
SPP, HALF, NF = G.SPP, G.HALF, G.NF

# the generator's 22 files: read, hashed, never written
PROTECTED = ["Map1_BiomeGrid16.json", "Map1_Height.png", "Map1_Landmarks.glb", "Map1_Landmarks.manifest.json",
             "Map1_Layout.json", "Map1_Material.png", "Map1_Plants.glb", "Map1_Plants.manifest.json",
             "Map1_Region.png", "Map1_Skyline.glb", "Map1_Skyline.manifest.json", "Map1_Terrain.json",
             "Map1_WaterLevel.png", "Map1_WaterMask.png"] + ["Map1_Mask_%s.png" % k for k in (
                 "Boulders", "Broadleaf", "Conifer", "Crags", "Gorse", "Heather", "TallGrass", "Wildflowers")]
OWN = ["Map1_SkylineCut.glb", "Map1_SkylineCut.manifest.json", "Map1_FarValley.glb", "Map1_FarValley.manifest.json"]

PART_LIMIT = 2000.0            # no part's bounding box may be longer than this on any axis (Roblox's cap is 2,048)
TILE_LIMIT = 1990.0            # what the tiler aims for, leaving ten studs to spare

# ------------------------------------------------------------------------------------------------ far valley numbers
FV_R0, FV_R1 = 850.0, 2750.0   # the valley ring
FV_NTH = 180                   # 2-degree steps: arcs 29.7 at r 850, 96 at r 2,750
FV_S0, FV_S1 = 30.0, 64.0      # radial step at r 850 and at the rim
FV_JITTER = 0.22               # each inner vertex is moved by up to this share of its cell, along and across the ring
FV_DROP = 6.0                  # the whole sheet lies at least this far under the true surface
FV_CANOPY_MIN = 18.0           # the canopy sheet clears the true ground by at least this much ...
FV_CANOPY_JITTER = 6.0         # ... plus 0 to this, per vertex (so 18 to 24 on even ground)
FV_CANOPY_DENSE = 0.40         # a triangle carries canopy when its mean conifer density is at least this
FV_SMOOTH_DEG = 45.0           # ground normals are shared between faces that meet at less than this (a crease past it)
FV_MAX_TRIS, FV_MAX_PART = 60000, 10000
# class -> (role, Roblox material, palette key, roughness, smooth shading)
FV_CLASSES = {
    "Grass": ("FarGrass", "Grass", "meadow", 0.95, True),
    "DryGrass": ("FarDryGrass", "Grass", "dry", 0.95, True),
    "Heather": ("FarHeather", "LeafyGrass", "heath", 0.95, True),
    "Rock": ("FarRock", "Limestone", "limestone", 0.9, True),
    "Scree": ("FarScree", "Basalt", "scree", 0.9, True),
    "Water": ("FarWater", "SmoothPlastic", "water", 0.3, True),
    "Canopy": ("FarCanopy", "LeafyGrass", "needles", 0.95, False),
}
FV_ORDER = ["Grass", "DryGrass", "Heather", "Rock", "Scree", "Water", "Canopy"]
for _c, (_role, _mat, _key, _rough, _s) in FV_CLASSES.items():
    G.ROLES[_role] = (_mat, _key, 0.0, _rough, "paint")
    G.COLLIDE[_role] = (False, "Box", False)


# ================================================================================================ small tools
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def protected_hashes():
    return {n: sha256(os.path.join(SRC, n)) for n in PROTECTED if os.path.exists(os.path.join(SRC, n))}


def own_path(name):
    """the only place an export path is made: one of this script's four files, never one of the generator's"""
    if name not in OWN or name in PROTECTED:
        raise RuntimeError("map1_far_exports writes only %s, not %r" % (OWN, name))
    return os.path.join(OUT, name)


def copy_manifest_to_repo(mpath, man):
    """the manifest's copy in art/manifests. The repo copy may carry top-level keys the export does not have (the
    assets builder records its upload under "assetIds" there): those are kept, after everything this export wrote."""
    dst = os.path.join(G.MANIFEST_COPY, os.path.basename(mpath))
    kept = {}
    if os.path.exists(dst):
        try:
            with open(dst) as f:
                old = json.load(f)
            kept = {k: v for k, v in old.items() if k not in man}
        except ValueError:
            kept = {}
    if not kept:
        shutil.copy2(mpath, dst)
    else:
        with open(dst, "w") as f:
            json.dump(dict(man, **kept), f, indent=1)
        log("the repo copy %s keeps the keys added in the repo: %s" % (os.path.basename(dst), sorted(kept)))


def same_manifest_in_repo(mpath):
    """True when the repo copy says everything the export's manifest says (keys added in the repo are allowed)"""
    dst = os.path.join(G.MANIFEST_COPY, os.path.basename(mpath))
    if not os.path.exists(dst):
        return False, "missing"
    with open(mpath) as f:
        a = json.load(f)
    with open(dst) as f:
        b = json.load(f)
    extra = sorted(k for k in b if k not in a)
    return all(k in b and b[k] == a[k] for k in a), ("identical" if not extra else "plus the repo's own %s" % extra)


def png_read_grey(path):
    """8- or 16-bit greyscale PNG, non-interlaced (the generator's own writer; any filter type)."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat, hdr = 8, [], None
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat.append(body)
        pos += 12 + ln
    w, h, depth, colour, _, _, interlace = hdr
    assert colour == 0 and interlace == 0 and depth in (8, 16), hdr
    bpp = depth // 8
    raw = np.frombuffer(zlib.decompress(b"".join(idat)), np.uint8).reshape(h, 1 + w * bpp)
    filt, rows = raw[:, 0], raw[:, 1:].astype(np.int32)
    if (filt == 0).all():
        out = rows
    else:
        out = np.zeros_like(rows)
        for y in range(h):
            ft, line = int(filt[y]), rows[y]
            prev = out[y - 1] if y else np.zeros(w * bpp, np.int32)
            if ft == 0:
                out[y] = line
            elif ft == 2:
                out[y] = (line + prev) & 255
            else:
                cur = np.zeros(w * bpp, np.int32)
                for i in range(w * bpp):
                    a = cur[i - bpp] if i >= bpp else 0
                    b = prev[i]
                    c = prev[i - bpp] if i >= bpp else 0
                    if ft == 1:
                        pr = a
                    elif ft == 3:
                        pr = (a + b) // 2
                    else:
                        p = a + b - c
                        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                        pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                    cur[i] = (line[i] + pr) & 255
                out[y] = cur
    out = out.astype(np.uint8)
    return out.reshape(h, w) if bpp == 1 else out.reshape(h, w, 2).astype(np.uint16)[..., 0] * 256 + out.reshape(h, w, 2)[..., 1]


def sample_bilinear(A, x, y):
    """a 4-stud raster (row 0 north) at Blender (x, y): bilinear, clamped at the raster's edge"""
    fi = np.clip((np.asarray(x, np.float64) + HALF) / SPP - 0.5, 0.0, NF - 1.0)
    fj = np.clip((HALF - np.asarray(y, np.float64)) / SPP - 0.5, 0.0, NF - 1.0)
    i0 = np.clip(np.floor(fi).astype(np.int64), 0, NF - 2)
    j0 = np.clip(np.floor(fj).astype(np.int64), 0, NF - 2)
    a, b = fi - i0, fj - j0
    return (A[j0, i0] * (1 - a) + A[j0, i0 + 1] * a) * (1 - b) + (A[j0 + 1, i0] * (1 - a) + A[j0 + 1, i0 + 1] * a) * b


def filt3(A, fn):
    """3 x 3 minimum or maximum (a sample and its eight neighbours)"""
    P = np.pad(A, 1, mode="edge")
    out = A.copy()
    for dj in (0, 1, 2):
        for di in (0, 1, 2):
            out = fn(out, P[dj:dj + A.shape[0], di:di + A.shape[1]])
    return out


def rasterise(VX, VY, tris):
    """every 4-stud sample (pixel centre) under a triangle mesh seen from above -> (row, col, triangle, weights).
    A sample on a shared edge goes to the first triangle that holds it."""
    tri_map = -np.ones((NF, NF), np.int32)
    wmap = np.zeros((NF, NF, 3), np.float32)
    c = -HALF + SPP * (np.arange(NF) + 0.5)                 # x of a column; y of a row is -c[row]
    X0, Y0 = VX[tris[:, 0]], VY[tris[:, 0]]
    X1, Y1 = VX[tris[:, 1]], VY[tris[:, 1]]
    X2, Y2 = VX[tris[:, 2]], VY[tris[:, 2]]
    xmin, xmax = np.minimum(np.minimum(X0, X1), X2), np.maximum(np.maximum(X0, X1), X2)
    ymin, ymax = np.minimum(np.minimum(Y0, Y1), Y2), np.maximum(np.maximum(Y0, Y1), Y2)
    ia = np.clip(np.ceil((xmin + HALF) / SPP - 0.5 - 1e-9).astype(np.int64), 0, NF - 1)
    ib = np.clip(np.floor((xmax + HALF) / SPP - 0.5 + 1e-9).astype(np.int64), 0, NF - 1)
    ja = np.clip(np.ceil((HALF - ymax) / SPP - 0.5 - 1e-9).astype(np.int64), 0, NF - 1)
    jb = np.clip(np.floor((HALF - ymin) / SPP - 0.5 + 1e-9).astype(np.int64), 0, NF - 1)
    den = (Y1 - Y2) * (X0 - X2) + (X2 - X1) * (Y0 - Y2)
    for t in range(len(tris)):
        if ib[t] < ia[t] or jb[t] < ja[t] or abs(den[t]) < 1e-12:
            continue
        xs = c[ia[t]:ib[t] + 1][None, :]
        ys = -c[ja[t]:jb[t] + 1][:, None]
        w0 = ((Y1[t] - Y2[t]) * (xs - X2[t]) + (X2[t] - X1[t]) * (ys - Y2[t])) / den[t]
        w1 = ((Y2[t] - Y0[t]) * (xs - X2[t]) + (X0[t] - X2[t]) * (ys - Y2[t])) / den[t]
        w2 = 1.0 - w0 - w1
        sub = tri_map[ja[t]:jb[t] + 1, ia[t]:ib[t] + 1]
        ok = (w0 >= -1e-9) & (w1 >= -1e-9) & (w2 >= -1e-9) & (sub < 0)
        if ok.any():
            sub[ok] = t
            ws = wmap[ja[t]:jb[t] + 1, ia[t]:ib[t] + 1]
            ws[ok, 0] = w0[ok]
            ws[ok, 1] = w1[ok]
            ws[ok, 2] = w2[ok]
    pj, pi = np.nonzero(tri_map >= 0)
    return pj, pi, tri_map[pj, pi].astype(np.int64), np.clip(wmap[pj, pi].astype(np.float64), 0.0, 1.0)


class Envelope:
    """Fits the corner heights of a triangle mesh so that the mesh lies on or under a target at every 4-stud sample,
    and as high as that allows.
      project  Hildreth-style sweeps: each triangle's worst sample is put right by the smallest change of its corners
      seal     the guarantee: every corner drops by the worst excess left among the samples of its own triangles,
               after which no sample is above the target (each sample's three corners all dropped at least that far)
      lift     coordinate ascent: corners that share no triangle rise together, each as far as its samples allow
    For an UPPER envelope (the canopy over the ground) fit the negated heights under the negated target."""

    def __init__(self, nv, tris, ptri, w, target):
        self.nv, self.tris, self.nt = nv, tris, len(tris)
        self.ptri, self.w, self.T = ptri, w, target
        self.order = np.argsort(ptri, kind="stable")
        self.present, self.starts = np.unique(ptri[self.order], return_index=True)
        self.seg = np.repeat(np.arange(len(self.present)), np.diff(np.append(self.starts, len(ptri))))
        self.pv = tris[ptri]
        # colours: no two corners of one triangle share a colour (greedy)
        nb = [set() for _ in range(nv)]
        for a, b, c in tris.tolist():
            nb[a].update((b, c))
            nb[b].update((a, c))
            nb[c].update((a, b))
        col = -np.ones(nv, np.int64)
        for v in range(nv):
            used = {col[u] for u in nb[v]}
            k = 0
            while k in used:
                k += 1
            col[v] = k
        self.colour, self.ncol = col, int(col.max()) + 1

    def mesh(self, h):
        return (self.w * h[self.pv]).sum(1)

    def tri_reduce(self, vals, fn, fill):
        out = np.full(self.nt, fill)
        out[self.present] = fn.reduceat(vals[self.order], self.starts)
        return out

    def project(self, h, sweeps=80, tol=0.005):
        h = h.copy()
        for _ in range(sweeps):
            viol = self.mesh(h) - self.T
            tmax = self.tri_reduce(viol, np.maximum, -np.inf)
            if float(tmax.max()) <= tol:
                break
            vs = viol[self.order]
            is_max = vs >= tmax[self.present][self.seg] - 1e-12
            first = np.unique(self.seg[is_max], return_index=True)[1]
            pidx = self.order[np.nonzero(is_max)[0][first]]           # the worst sample of each triangle
            e = np.clip(viol[pidx], 0.0, None)
            w = self.w[pidx]
            corr = e[:, None] * w / (w * w).sum(1)[:, None]
            lower = np.zeros(self.nv)
            tv = self.tris[self.present]
            for k in range(3):
                np.maximum.at(lower, tv[:, k], corr[:, k])
            h -= lower
        return h

    def seal(self, h):
        viol = np.clip(self.mesh(h) - self.T, 0.0, None)
        tmax = self.tri_reduce(viol, np.maximum, 0.0)
        lower = np.zeros(self.nv)
        for k in range(3):
            np.maximum.at(lower, self.tris[:, k], tmax)
        return h - lower

    def lift(self, h, sweeps=8):
        h = h.copy()
        for _ in range(sweeps):
            total = 0.0
            for col in range(self.ncol):
                slack = self.T - self.mesh(h)
                rise = np.full(self.nv, np.inf)
                for k in range(3):
                    wk = self.w[:, k]
                    ratio = np.where(wk > 1e-3, slack / np.maximum(wk, 1e-3), np.inf)
                    np.minimum.at(rise, self.tris[:, k], self.tri_reduce(ratio, np.minimum, np.inf))
                rise = np.where(np.isfinite(rise) & (self.colour == col), np.clip(rise, 0.0, None), 0.0)
                h += rise
                total += float(rise.sum())
            if total < 1e-3:
                break
        return h

    def fit(self, h0):
        return self.seal(self.lift(self.seal(self.project(h0))))


def strip_tiles(cx, cz, lo, hi, limit, gap=500.0):
    """Group triangles into tiles whose bounding boxes are at most `limit` on X and Z: columns of equal width along
    X, each cut along Z into equal slabs over every stretch it actually covers (a hole splits a column in two). A
    triangle goes where its centroid lies; the boxes are measured on the triangles' own corners. Returns (tile index
    per triangle, [dict(col, row, n)]) for the column count that gives the fewest tiles."""
    x0, x1 = float(lo[:, 0].min()), float(hi[:, 0].max())
    best = None
    for ncol in range(max(1, int(math.ceil((x1 - x0) / limit))), int(math.ceil((x1 - x0) / limit)) + 4):
        edges = np.linspace(x0, x1, ncol + 1)
        col = np.clip(np.searchsorted(edges, cx, side="right") - 1, 0, ncol - 1)
        tile = -np.ones(len(cx), np.int64)
        tiles, ok = [], True
        for c in range(ncol):
            idx = np.nonzero(col == c)[0]
            if not len(idx):
                continue
            if hi[idx, 0].max() - lo[idx, 0].min() > limit:
                ok = False
                break
            order = idx[np.argsort(cz[idx], kind="stable")]
            row = 0
            for seg in np.split(order, np.nonzero(np.diff(cz[order]) > gap)[0] + 1):
                z0, z1 = float(lo[seg, 1].min()), float(hi[seg, 1].max())
                n = max(1, int(math.ceil((z1 - z0) / limit)))
                while True:
                    e = np.linspace(z0, z1, n + 1)
                    r = np.clip(np.searchsorted(e, cz[seg], side="right") - 1, 0, n - 1)
                    if all(hi[seg[r == k], 1].max() - lo[seg[r == k], 1].min() <= limit for k in range(n) if (r == k).any()):
                        break
                    n += 1
                for k in range(n):
                    s = seg[r == k]
                    if len(s):
                        tile[s] = len(tiles)
                        tiles.append(dict(col=c, row=row, n=int(len(s))))
                        row += 1
        if ok and (best is None or len(tiles) < len(best[1])):
            best = (tile, tiles, ncol)
    if best is None:
        raise RuntimeError("no tiling under %.0f studs" % limit)
    return best


def merge_small_parts(tile, role, lo, hi, limit, small=24):
    """A part is the triangles of one role in one tile. A part of fewer than `small` triangles is a draw call for
    almost nothing, so it joins the part of the same role in another tile when the joint bounding box still fits the
    limit (the nearest fit). Returns the tile each triangle's PART belongs to, and what moved."""
    tile = tile.copy()
    parts = {}
    for t, r in sorted(set(zip(tile.tolist(), role.tolist()))):
        m = (tile == t) & (role == r)
        parts[(t, r)] = [int(m.sum()), lo[m].min(0), hi[m].max(0)]
    moved = []
    for (t, r), (n, blo, bhi) in sorted(parts.items(), key=lambda kv: (kv[1][0], kv[0])):
        if n >= small:
            break
        best = None
        for (t2, r2), (n2, lo2, hi2) in sorted(parts.items()):
            if r2 != r or t2 == t or n2 < small:
                continue
            ext = float((np.maximum(bhi, hi2) - np.minimum(blo, lo2)).max())
            if ext <= limit and (best is None or ext < best[0]):
                best = (ext, t2)
        if best is not None:
            tile[(tile == t) & (role == r)] = best[1]
            host = parts[(best[1], r)]
            host[0] += n
            host[1], host[2] = np.minimum(host[1], blo), np.maximum(host[2], bhi)
            parts[(t, r)][0] = 0
            moved.append((t, r, best[1], n))
    return tile, moved


def tri_normals(V, T):
    P = V[T]
    n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    return n


def face_up(V, T):
    """turn every triangle so that it faces up (+z in Blender, +Y in Roblox)"""
    T = T.copy()
    flip = tri_normals(V, T)[:, 2] < 0
    T[flip] = T[flip][:, ::-1]
    return T


def compact(V, T, extra=None):
    used = np.unique(T)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return (V[used], remap[T]) if extra is None else (V[used], remap[T], extra[used])


def tri_neighbours(T):
    """for each triangle, the triangle across each of its three edges (or -1)"""
    nt = len(T)
    e = np.stack([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]], 1).reshape(-1, 2)
    key = np.sort(e, axis=1)
    k = key[:, 0].astype(np.int64) * (int(T.max()) + 1) + key[:, 1]
    order = np.argsort(k, kind="stable")
    ks = k[order]
    i = np.flatnonzero(ks[1:] == ks[:-1])
    nb = -np.ones(3 * nt, np.int64)
    a, b = order[i], order[i + 1]
    nb[a] = b // 3
    nb[b] = a // 3
    return nb.reshape(nt, 3)


def corner_normals(V, T, max_deg):
    """a normal for every corner of every triangle: the area-weighted mean of the faces round that vertex which lie
    within max_deg of the corner's own face. Gentle ground shades as one surface; cliffs and sharp ridges keep an edge.
    Computed on the whole sheet before it is cut into parts, so parts and tiles shade as one."""
    fn = tri_normals(V, T)
    unit = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    cv = T.ravel()
    cf = np.repeat(np.arange(len(T)), 3)
    order = np.argsort(cv, kind="stable")
    cvs, cfs = cv[order], cf[order]
    starts = np.flatnonzero(np.r_[True, cvs[1:] != cvs[:-1]])
    ends = np.r_[starts[1:], len(cvs)]
    out = np.zeros((len(T) * 3, 3))
    cos_t = math.cos(math.radians(max_deg))
    for s_, e_ in zip(starts.tolist(), ends.tolist()):
        f = cfs[s_:e_]
        out[order[s_:e_]] = ((unit[f] @ unit[f].T) >= cos_t).astype(np.float64) @ fn[f]
    out /= np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)
    return out.reshape(len(T), 3, 3)


def box_uv_np(V, T, studs_per_tile=8.0):
    """the generator's box_uv in numpy: per face, project along the normal's largest axis; 1 UV unit = 8 studs"""
    n = np.abs(tri_normals(V, T))
    axis = np.argmax(n, axis=1)[:, None]
    P = V[T]
    u = np.where(axis == 0, P[:, :, 1], P[:, :, 0])
    v = np.where(axis == 2, P[:, :, 1], P[:, :, 2])
    return np.stack([u, v], -1) / studs_per_tile


def srgb_of(lin_rgb):
    c = np.clip(np.asarray(lin_rgb, np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0


# ================================================================================================ GLB + manifest
def np_mesh(name, V, T):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(V))
    me.vertices.foreach_set("co", np.asarray(V, np.float32).ravel())
    me.loops.add(len(T) * 3)
    me.loops.foreach_set("vertex_index", np.asarray(T, np.int32).ravel())
    me.polygons.add(len(T))
    me.polygons.foreach_set("loop_start", np.arange(0, len(T) * 3, 3, dtype=np.int32))
    try:
        me.polygons.foreach_set("loop_total", np.full(len(T), 3, np.int32))
    except Exception:
        pass
    me.update(calc_edges=True)
    if len(me.polygons) != len(T):
        raise RuntimeError("polygon count changed for %s" % name)
    return me


def export_set(glb, assets, top):
    """assets: [dict(name, kind, tags, notes, extra, parts=[dict(name, role, V, T, rgb, normals|None, extra)])], all in
    Blender space with the asset's pivot at the origin (these assets are in world space: the pivot is the map centre).
    Writes <glb>.glb and <glb>.manifest.json in the pass-3 layout (assets in a row along +X) and returns the manifest."""
    sc = bpy.context.scene
    root_col = bpy.data.collections.new("EXPORT_" + glb)
    sc.collection.children.link(root_col)
    for o in sc.objects:
        o.select_set(False)
    x = 0.0
    objs, man_assets, warnings = [], [], []
    for a in assets:
        allv = np.concatenate([p["V"] for p in a["parts"]])
        lo, hi = allv.min(0), allv.max(0)
        x += -lo[0] + 2.0
        emp = bpy.data.objects.new(a["name"], None)
        root_col.objects.link(emp)
        emp.location = (x, 0.0, 0.0)
        parts, tris_total = [], 0
        for p in a["parts"]:
            V, T = p["V"], p["T"]
            me = np_mesh(p["name"], V, T)
            uvl = me.uv_layers.new(name="UVMap")
            uvl.data.foreach_set("uv", box_uv_np(V, T).astype(np.float32).ravel())
            if p.get("normals") is not None:                       # (triangles, 3, 3): a normal for every corner
                me.shade_smooth()
                want = np.asarray(p["normals"], np.float64).reshape(-1, 3)
                me.normals_split_custom_set([tuple(n) for n in want.tolist()])
                me.update()
                got = np.zeros(len(want) * 3, np.float32)
                me.corner_normals.foreach_get("vector", got)
                worst = float(np.degrees(np.arccos(np.clip((got.reshape(-1, 3) * want).sum(1), -1.0, 1.0))).max())
                if worst > 1.0:
                    raise RuntimeError("%s: the stored normals are %.2f degrees off the ones asked for" % (p["name"], worst))
            else:
                me.shade_flat()
            me.materials.append(G.flat_material(p["role"], p["rgb"]))
            ob = bpy.data.objects.new(p["name"], me)
            root_col.objects.link(ob)
            ob.parent = emp
            objs.append(ob)
            plo, phi = V.min(0), V.max(0)
            size = [round(float(phi[0] - plo[0]), 3), round(float(phi[2] - plo[2]), 3), round(float(phi[1] - plo[1]), 3)]
            rmat, pkey, metal, rough, _ = G.ROLES[p["role"]]
            col, colfid, shadow = G.COLLIDE.get(p["role"], (False, "Box", False))
            tri = int(len(T))
            tris_total += tri
            entry = dict(name=p["name"], role=p["role"], robloxMaterial=rmat, rgb=[int(c) for c in p["rgb"]],
                         collide=col, collision=colfid, castShadow=shadow, canQuery=col, canTouch=col, tags=[],
                         tris=tri, metalness=metal, roughness=rough, colourGroup=1, colourGroups=1, faces="up",
                         position=G.to_roblox(0.5 * (plo + phi)), size=size,
                         boundsMin=[round(float(plo[0]), 3), round(float(plo[2]), 3), round(float(-phi[1]), 3)],
                         boundsMax=[round(float(phi[0]), 3), round(float(phi[2]), 3), round(float(-plo[1]), 3)],
                         shading="smooth" if p.get("normals") is not None else "flat", renderFidelity="Precise")
            entry.update(p.get("extra") or {})
            parts.append(entry)
            if max(size) > PART_LIMIT:
                warnings.append("%s is %.0f studs long (limit %.0f)" % (p["name"], max(size), PART_LIMIT))
            if tri > top.get("maxPartTris", 20000):
                warnings.append("%s has %d triangles (limit %d)" % (p["name"], tri, top["maxPartTris"]))
        objs.append(emp)
        entry = dict(
            name=a["name"], kind=a["kind"], tags=a["tags"], notes=a["notes"], origin=G.to_roblox((x, 0.0, 0.0)),
            size=[round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3), round(float(hi[1] - lo[1]), 3)],
            boundsMin=[round(float(lo[0]), 3), round(float(lo[2]), 3), round(float(-hi[1]), 3)],
            boundsMax=[round(float(hi[0]), 3), round(float(hi[2]), 3), round(float(-lo[1]), 3)],
            tris=tris_total, parts=parts, attachments={},
            pivot="the map centre at y 0 (world space): place the asset at position (0, 0, 0), yaw 0",
            placement=dict(position=[0.0, 0.0, 0.0], yawDegrees=0.0))
        entry.update(a.get("extra") or {})
        man_assets.append(entry)
        x += hi[0] + 2.0
    path = own_path(glb + ".glb")
    bpy.context.view_layer.update()
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="EXPORT", export_vertex_color="NONE",
                              export_tangents=True, export_cameras=False, export_lights=False)
    total = sum(a["tris"] for a in man_assets)
    if total > top.get("maxTris", 10 ** 9):
        warnings.append("%s has %d triangles (limit %d)" % (glb, total, top["maxTris"]))
    man = dict(category=glb, glb=os.path.basename(path), units="studs (1 Blender unit = 1 stud)",
               axes="Roblox: X east, Y up, Z south (glTF +Y up; Blender (x,y,z) -> Roblox (x,z,-y))",
               generator="art/blender/map1_far_exports.py", seed=G.SEED, warnings=warnings, placeholder=False,
               assets=man_assets, hornColouring=G.HORN)
    man.update({k: v for k, v in top.items() if k not in ("maxTris", "maxPartTris")})
    man["totals"] = dict(assets=len(man_assets), parts=sum(len(a["parts"]) for a in man_assets), tris=total,
                         longestPart=max(max(p["size"]) for a in man_assets for p in a["parts"]),
                         mostTrisInAPart=max(p["tris"] for a in man_assets for p in a["parts"]))
    mpath = own_path(glb + ".manifest.json")
    with open(mpath, "w") as f:
        json.dump(man, f, indent=1)
    if os.path.isdir(G.MANIFEST_COPY) and os.path.normcase(OUT) == os.path.normcase(G.DEFAULT_OUT):
        copy_manifest_to_repo(mpath, man)
    log("EXPORTED %s (%.2f MB), %d assets, %d parts, %d triangles, longest part %.0f, %d warnings" % (
        path, os.path.getsize(path) / 1e6, len(man_assets), man["totals"]["parts"], total,
        man["totals"]["longestPart"], len(warnings)))
    for w in warnings:
        log("WARNING", w)
    for o in list(root_col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(root_col)
    return man


PLACING = ("Every asset of this file is modelled in world space with its pivot at the map centre (0, 0, 0): place "
           "each at position (0, 0, 0) with yaw 0. In the file the assets stand in a row along +X, as in every other "
           "GLB of this project; 'origin' is each asset's pivot in the file. Each part also carries 'position' and "
           "'size': the centre and the extent of its bounding box in Roblox world space once its asset stands at the "
           "map centre. A MeshPart's Position is its bounding box's centre, so a part is in place when its Position "
           "equals 'position' and its Size equals 'size' (after the importer's own turn about Y has been undone, as "
           "for every other asset). Set RenderFidelity to Precise: neighbouring parts share an edge exactly, and a "
           "part simplified on its own could open a crack along it. CanCollide, CanQuery, CanTouch and CastShadow are "
           "false; the model is Persistent.")


# ================================================================================================ STAGE: skyline
def skyline_stage():
    log("skyline: building the far range (the generator's build_skyline)")
    sectors = G.build_skyline()
    roles = ["SkylineGrass", "SkylineForest", "SkylineRock"]
    old = None
    old_path = os.path.join(SRC, "Map1_Skyline.manifest.json")
    if os.path.exists(old_path):
        with open(old_path) as f:
            old = {p["name"]: p for a in json.load(f)["assets"] for p in a["parts"]}
    Vs, Ts, role_of, sector_of, off = [], [], [], [], 0
    sector_rgb = {}
    for si, name in enumerate(G.SKYLINE_SECTORS):
        for ri, role in enumerate(roles):
            mb = sectors[name][role]
            rgb = tuple(int(c) for c in G.part_rgb(mb))
            sector_rgb[(si, ri)] = rgb
            if old is not None:
                o = old["M1_Skyline_%s_%s" % (name, role)]
                if tuple(o["rgb"]) != rgb or o["tris"] != len(mb.f):
                    raise RuntimeError("build_skyline no longer matches Map1_Skyline.manifest.json at %s %s: %s %d vs "
                                       "%s %d" % (name, role, rgb, len(mb.f), o["rgb"], o["tris"]))
            V = np.asarray(mb.v, np.float64)
            T = np.asarray(mb.f, np.int64)
            Vs.append(V)
            Ts.append(T + off)
            off += len(V)
            role_of.append(np.full(len(T), ri))
            sector_of.append(np.full(len(T), si))
    V = np.concatenate(Vs)
    T = face_up(V, np.concatenate(Ts))
    role_of, sector_of = np.concatenate(role_of), np.concatenate(sector_of)
    log("skyline: %d triangles%s" % (len(T), "" if old is None else
                                     "; colours and triangle counts match Map1_Skyline.manifest.json"))
    P = V[T]
    # Roblox X = Blender x, Roblox Z = -Blender y: tile on (x, -y)
    RX, RZ = P[:, :, 0], -P[:, :, 1]
    cx, cz = RX.mean(1), RZ.mean(1)
    lo = np.stack([RX.min(1), RZ.min(1)], 1)
    hi = np.stack([RX.max(1), RZ.max(1)], 1)
    best = None
    for swap in (False, True):                  # columns along X, or along Z: keep whichever needs fewer tiles
        if swap:
            t_, tiles_, ncol_ = strip_tiles(cz, cx, lo[:, ::-1], hi[:, ::-1], TILE_LIMIT)
        else:
            t_, tiles_, ncol_ = strip_tiles(cx, cz, lo, hi, TILE_LIMIT)
        if best is None or len(tiles_) < len(best[1]):
            best = (t_, tiles_, ncol_, swap)
    tile, tiles, ncol, swapped = best
    area = 0.5 * np.linalg.norm(tri_normals(V, T), axis=1)
    cen3 = P.mean(1)
    # each tile joins the sector its centre lies in
    for k, tinfo in enumerate(tiles):
        m = tile == k
        c = (cen3[m] * area[m, None]).sum(0) / area[m].sum()
        bearing = math.degrees(math.atan2(c[0], c[1])) % 360.0
        tinfo["sector"] = int(((bearing + 22.5) % 360.0) // 45.0)
        tinfo["bearing"], tinfo["r"] = bearing, float(math.hypot(c[0], c[1]))
    # number the tiles sector by sector, nearest first
    order = sorted(range(len(tiles)), key=lambda k: (tiles[k]["sector"], round(tiles[k]["r"]), tiles[k]["bearing"]))
    for n, k in enumerate(order):
        tiles[k]["id"] = "T%02d" % (n + 1)
    ptile, moved = merge_small_parts(tile, role_of, lo, hi, TILE_LIMIT)
    log("skyline: %d tiles (%d columns along %s); %d parts of under 24 triangles joined a neighbouring tile's part "
        "of the same role (%d triangles)" % (len(tiles), ncol, "Z" if swapped else "X", len(moved),
                                             sum(m[3] for m in moved)))
    assets = []
    for si, name in enumerate(G.SKYLINE_SECTORS):
        parts = []
        mine = [k for k in order if tiles[k]["sector"] == si]
        for k in mine:
            for ri, role in enumerate(roles):
                m = (ptile == k) & (role_of == ri)
                if not m.any():
                    continue
                pv, pt = compact(V, T[m])
                own = float(area[m & (sector_of == si)].sum() / area[m].sum())
                parts.append(dict(name="M1_Skyline_%s_%s_%s" % (name, tiles[k]["id"], role), role=role, V=pv, T=pt,
                                  rgb=sector_rgb[(si, ri)], normals=None,
                                  extra=dict(tile=tiles[k]["id"], shareFromThisSector=round(own, 3))))
        assets.append(dict(
            name="M1_Skyline_" + name, kind="Skyline", tags=["Skyline", "Persistent", "NoCollision", "NoShadow"],
            notes="far range, the tiles whose centres lie in sector %s (bearing %d +-22.5), r 2,600-7,600, in world "
                  "space: place at the map centre, ModelStreamingMode Persistent, CanCollide/CanQuery/CanTouch/"
                  "CastShadow false. Re-cut of Map1_Skyline.glb's M1_Skyline_%s: the same triangles regrouped into "
                  "tiles of at most 2,000 studs, so a tile on the sector's edge holds some triangles of the "
                  "neighbouring sector (shareFromThisSector)." % (name, 45 * si, name),
            parts=parts, extra=dict(tiles=[tiles[k]["id"] for k in mine])))
    top = dict(
        maxPartTris=5000, replaces="Map1_Skyline.glb",
        notes=("The far range of Map1_Skyline.glb re-cut for Roblox, whose parts may be at most 2,048 studs long: "
               "the same 44,000 triangles (the generator's build_skyline), regrouped into tiles on the world's own "
               "axes so that no part's bounding box is over 2,000 studs on any axis. The eight assets keep the "
               "names Map1_Layout.json places at the map centre. Parts: M1_Skyline_<sector>_<tile>_<role>; one "
               "flat colour per part (rgb, also the part's material colour in the GLB): the colour that sector's "
               "role has in Map1_Skyline.glb. No vertex colours, no textures, flat-shaded, single-sided, every "
               "triangle faces up, which is toward the arena. " + PLACING),
        tiling=dict(limit=PART_LIMIT, method="columns of equal width along %s, each cut into equal slabs along %s; "
                                             "a triangle goes where its centroid lies; a part of under 24 triangles joins the "
                                             "same role's part in a neighbouring tile when the joint box still "
                                             "fits" % (("Z", "X") if swapped else ("X", "Z")),
                    tiles=[dict(id=tiles[k]["id"], sector=G.SKYLINE_SECTORS[tiles[k]["sector"]],
                                centreBearing=round(tiles[k]["bearing"], 1), centreR=round(tiles[k]["r"], 1),
                                tris=tiles[k]["n"]) for k in order]))
    return export_set("Map1_SkylineCut", assets, top)


# ================================================================================================ STAGE: far valley
def fv_grid():
    """The far valley's vertices and triangles from above (Blender x, y), centre to rim.
    Ring, r 850-2,750: 2-degree steps, the radial step growing with r from 30 to 64 (cells 30 x 30 -> 64 x 96).
    Core, r under 850: the same 2-degree steps down to r 455, then 4-degree steps to r 243, 8-degree steps to
    r 106 and a fan to the centre, so its cells stay 15 to 30 studs wide.
    Returns VX, VY, tris, quad (for each triangle the quad it belongs to, or -1), rings (radius, vertex count)."""
    b = (FV_S1 - FV_S0) / (FV_R1 - FV_R0)
    umax = math.log(FV_S1 / FV_S0) / b
    n_out = int(round(umax))
    u = np.arange(n_out + 1) * umax / n_out
    outer = FV_R0 + FV_S0 * (np.exp(b * u) - 1.0) / b
    outer[0], outer[-1] = FV_R0, FV_R1
    rings = [(0.0, 1)]
    rings += [(float(r), FV_NTH // 4) for r in np.linspace(106.25, 212.5, 5)]
    rings += [(float(r), FV_NTH // 2) for r in np.linspace(243.0, 425.0, 7)]
    rings += [(float(r), FV_NTH) for r in np.linspace(455.0, FV_R0, 14)[:-1]]
    rings += [(float(r), FV_NTH) for r in outer]
    VX, VY, start = [], [], []
    for k, (r, n) in enumerate(rings):
        start.append(len(VX))
        a = 2.0 * math.pi * np.arange(n) / n
        # The grid is centred on the horn, so seen from the horn every cell edge would be level or upright and every
        # patch of a class a rectangle. Each vertex is therefore moved a little along and across its ring (a fixed
        # hash, the same on every run). Not moved: the centre, the rings where the step count changes, the core's
        # rim (r 850, shared by the core and the ring) and the outer rim.
        inner = 0 < k < len(rings) - 1 and rings[k - 1][1] == n == rings[k + 1][1] and abs(r - FV_R0) > 1e-6
        if inner:
            step_r = min(r - rings[k - 1][0], rings[k + 1][0] - r)
            ids = np.arange(n) + 100000 * k
            r_ = r + FV_JITTER * step_r * (2.0 * G.hash01(ids, salt=4201) - 1.0)
            a = a + FV_JITTER * (2.0 * math.pi / n) * (2.0 * G.hash01(ids, salt=4202) - 1.0)
        else:
            r_ = np.full(n, r)
        VX.extend((r_ * np.sin(a)).tolist())
        VY.extend((r_ * np.cos(a)).tolist())
    VX, VY = np.asarray(VX), np.asarray(VY)
    tris, quad = [], []
    nq = 0
    for k in range(len(rings) - 1):
        (r0, n0), (r1, n1) = rings[k], rings[k + 1]
        s0, s1 = start[k], start[k + 1]
        if n0 == 1:                                         # the fan round the centre
            for j in range(n1):
                tris.append((s0, s1 + (j + 1) % n1, s1 + j))
                quad.append(-1)
        elif n1 == n0:                                      # a ring of quads: the diagonal is chosen later
            for j in range(n0):
                a, bq, c, d = s0 + j, s0 + (j + 1) % n0, s1 + (j + 1) % n0, s1 + j
                tris.append((a, bq, c))
                tris.append((a, c, d))
                quad.extend((nq, nq))
                nq += 1
        elif n1 == 2 * n0:                                  # twice as many steps outside: three triangles a step
            for j in range(n0):
                c0, c1 = s0 + j, s0 + (j + 1) % n0
                f0, f1, f2 = s1 + 2 * j, s1 + 2 * j + 1, s1 + (2 * j + 2) % n1
                tris.extend(((c0, f1, f0), (c0, c1, f1), (c1, f2, f1)))
                quad.extend((-1, -1, -1))
        else:
            raise RuntimeError("ring step %d -> %d" % (n0, n1))
    return VX, VY, np.asarray(tris, np.int64), np.asarray(quad, np.int64), rings


def paint_components(D):
    """how much of each palette tone the generator's own terrain paint (terrain_colours) puts on every sample: the
    paint is linear in the palette's colours, so painting with three tones set to red, green and blue and the rest to
    black reads their shares off directly. The palette is put back afterwards."""
    keys = ["meadow", "turf", "dry", "forest_floor", "scree", "heath", "limestone", "needles", "path", "dark_rock",
            "mud", "pebbles"]
    saved = dict(G.PAL)
    comp = {}
    try:
        for g in range(0, len(keys), 3):
            grp = keys[g:g + 3]
            for k in saved:
                G.PAL[k] = (0, 0, 0)
            for c, k in enumerate(grp):
                G.PAL[k] = tuple(255 if i == c else 0 for i in range(3))
            col = G.terrain_colours(D)
            for c, k in enumerate(grp):
                comp[k] = col[..., c].astype(np.float32)
    finally:
        G.PAL.clear()
        G.PAL.update(saved)
    return comp


def far_valley_stage():
    D = np.load(os.path.join(WORK, "field.npz"))
    Hf = D["H"].astype(np.float64)
    png = os.path.join(SRC, "Map1_Height.png")
    Hp = png_read_grey(png).astype(np.float64) / G.HEIGHT_SCALE          # what the game builds its terrain from
    if Hp.shape != Hf.shape or float(np.abs(Hp - Hf).max()) > 0.02:
        raise RuntimeError("field.npz is not the field Map1_Height.png was written from (max difference %.3f)"
                           % float(np.abs(Hp - Hf).max()))
    log("far valley: the cached field matches Map1_Height.png (max difference %.4f)" % float(np.abs(Hp - Hf).max()))
    c = -HALF + SPP * (np.arange(NF) + 0.5)
    PXg, PYg = np.meshgrid(c, -c)
    Rg = np.hypot(PXg, PYg)

    # ---- the grid and its triangles
    VX, VY, tris, quad, rings = fv_grid()
    nv = len(VX)
    hv = sample_bilinear(Hp, VX, VY)
    q_ids = np.nonzero(quad >= 0)[0].reshape(-1, 2)                      # the two triangles of each quad
    a, bq, cq, d = tris[q_ids[:, 0], 0], tris[q_ids[:, 0], 1], tris[q_ids[:, 0], 2], tris[q_ids[:, 1], 2]
    other = np.abs(hv[a] - hv[cq]) > np.abs(hv[bq] - hv[d])              # the other diagonal fits the ground better
    tris[q_ids[other, 0]] = np.stack([a, bq, d], 1)[other]
    tris[q_ids[other, 1]] = np.stack([bq, cq, d], 1)[other]
    if (tri_normals(np.stack([VX, VY, np.zeros(nv)], 1), tris)[:, 2] <= 0).any():
        raise RuntimeError("the far valley's grid folds over itself (FV_JITTER too large)")
    tcx, tcy = VX[tris].mean(1), VY[tris].mean(1)
    tr = np.hypot(tcx, tcy)
    core = tr < FV_R0
    log("far valley: grid %d vertices, %d triangles (%d in the ring r %.0f-%.0f, %d in the core)" % (
        nv, len(tris), int((~core).sum()), FV_R0, FV_R1, int(core.sum())))

    # ---- the ground: a lower envelope of the true surface, 6 studs down
    pj, pi, ptri, pw = rasterise(VX, VY, tris)
    pr = Rg[pj, pi]
    inside = (Rg <= FV_R1 * math.cos(math.pi / FV_NTH) - 0.5)
    missed = inside.copy()
    missed[pj, pi] = False
    if missed.any():
        raise RuntimeError("%d samples inside r %.0f lie under no triangle" % (int(missed.sum()), FV_R1))
    target = filt3(Hp, np.minimum) - FV_DROP          # the lowest of a sample and its 8 neighbours (4 studs each way)
    env = Envelope(nv, tris, ptri, pw, target[pj, pi])
    h_ground = env.fit(sample_bilinear(target, VX, VY))
    gap = Hp[pj, pi] - env.mesh(h_ground)
    if float(gap.min()) < FV_DROP - 1e-6:
        raise RuntimeError("the far ground comes within %.3f of the true surface" % float(gap.min()))
    fit_stats = dict(drop=FV_DROP, samples=int(len(gap)), minBelow=round(float(gap.min()), 3),
                     meanBelow=round(float(gap.mean()), 2), medianBelow=round(float(np.median(gap)), 2),
                     p90Below=round(float(np.percentile(gap, 90)), 2), p99Below=round(float(np.percentile(gap, 99)), 2),
                     maxBelow=round(float(gap.max()), 1), byRadius=[])
    for r_lo, r_hi in ((0, 850), (850, 1100), (1100, 1500), (1500, 1900), (1900, 2400), (2400, 2750)):
        m = (pr >= r_lo) & (pr < r_hi)
        fit_stats["byRadius"].append(dict(r=[r_lo, r_hi], meanBelow=round(float(gap[m].mean()), 2),
                                          p90Below=round(float(np.percentile(gap[m], 90)), 2),
                                          p99Below=round(float(np.percentile(gap[m], 99)), 2)))
    log("far valley: ground fitted; below the true surface: min %.2f, mean %.2f, median %.2f, p99 %.1f, max %.1f" % (
        gap.min(), gap.mean(), np.median(gap), np.percentile(gap, 99), gap.max()))
    for row in fit_stats["byRadius"]:
        log("    r %4d-%4d: mean %.2f, p90 %.2f, p99 %.2f" % (row["r"][0], row["r"][1], row["meanBelow"],
                                                               row["p90Below"], row["p99Below"]))

    # ---- classes, from the generator's own paint
    comp = paint_components(D)
    grass = comp["meadow"] + comp["turf"]
    dry, heath, scree = comp["dry"], comp["heath"], comp["scree"]
    rock = comp["limestone"] + comp["dark_rock"]
    tot = grass + dry + heath + scree + rock
    lake = D["q"] < 1.0
    # a sample's class is the tone that covers most of it (FV_ORDER: Grass, DryGrass, Heather, Rock, Scree); a
    # triangle's class is the one most of its samples have. Flat colours cannot show the paint's blends, so this is
    # the nearest flat picture of it.
    cls = np.stack([grass, dry, heath, rock, scree], 0).argmax(0).astype(np.int8)
    cls = np.where(tot < 0.05, np.where(D["w_dry"] >= 0.5, 1, 0), cls)  # forest floor, paths, mud: what lies under
    cls = np.where(lake, 5, cls)
    votes = np.zeros((len(tris), 6))
    np.add.at(votes, (ptri, cls[pj, pi].astype(np.int64)), 1.0)
    tri_class = votes.argmax(1)
    nb = tri_neighbours(tris)
    for _ in range(2):              # a lone triangle between two neighbours of one other class joins them
        nbc = np.where(nb >= 0, tri_class[nb], -1)
        a_, b_, c_ = nbc[:, 0], nbc[:, 1], nbc[:, 2]
        maj = np.where(a_ == b_, a_, np.where(a_ == c_, a_, np.where(b_ == c_, b_, -1)))
        lone = ((nbc == tri_class[:, None]).sum(1) == 0) & (maj >= 0) & (tri_class != 5) & (maj != 5)
        tri_class = np.where(lone, maj, tri_class)
    # canopy: the conifer mask, with the far forests carried on past r 2,250 where the mask itself fades out (the
    # generator paints that forest onto the ground, and the skyline's forest patches carry on from r 2,600)
    slope = D["slope"]
    dens = np.maximum(D["m_Conifer"], 0.8 * G.sstep(1800.0, 1950.0, Rg) * D["ffar"] * (slope < 38.0) * (~lake))
    dsum = np.zeros(len(tris))
    cnt = np.zeros(len(tris))
    np.add.at(dsum, ptri, dens[pj, pi])
    np.add.at(cnt, ptri, 1.0)
    canopy = (dsum / np.maximum(cnt, 1.0) >= FV_CANOPY_DENSE) & (tri_class != 5) & (tr > 215.0)
    for _ in range(2):              # no one-triangle holes in a forest and no one-triangle forests
        n_can = np.where(nb >= 0, canopy[nb], False).sum(1)
        canopy = (canopy | ((n_can == 3) & (tri_class != 5))) & ~(canopy & (n_can == 0))
    log("far valley: classes by triangle: %s; canopy %d" % (
        ", ".join("%s %d" % (FV_ORDER[k], int((tri_class == k).sum())) for k in range(6)), int(canopy.sum())))

    # ---- the canopy: an upper envelope 18 studs over the true surface, plus 0-6 per vertex
    ctris = tris[canopy]
    cm = canopy[ptri]
    renum = -np.ones(len(tris), np.int64)
    renum[canopy] = np.arange(int(canopy.sum()))
    top = filt3(Hp, np.maximum) + FV_CANOPY_MIN
    cenv = Envelope(nv, ctris, renum[ptri[cm]], pw[cm], -top[pj[cm], pi[cm]])
    h_can = -cenv.fit(-sample_bilinear(top, VX, VY))
    clear = cenv.mesh(-h_can) * -1.0 - Hp[pj[cm], pi[cm]]
    if float(clear.min()) < FV_CANOPY_MIN - 1e-6:
        raise RuntimeError("the canopy comes within %.3f of the ground" % float(clear.min()))
    h_can = h_can + FV_CANOPY_JITTER * G.hash01(np.arange(nv), salt=4107)
    can_stats = dict(minAboveGround=FV_CANOPY_MIN, jitter=FV_CANOPY_JITTER, triangles=int(len(ctris)),
                     meanAboveGround=round(float(clear.mean() + 0.5 * FV_CANOPY_JITTER), 2),
                     p99AboveGround=round(float(np.percentile(clear, 99) + FV_CANOPY_JITTER), 1),
                     denseAt=FV_CANOPY_DENSE)
    log("far valley: canopy fitted over %d triangles; above the true ground: min %.2f, mean %.2f, p99 %.1f (before "
        "the 0-%.0f jitter)" % (len(ctris), clear.min(), clear.mean(), np.percentile(clear, 99), FV_CANOPY_JITTER))

    # ---- geometry in Blender space, smooth normals for the ground
    VG = np.stack([VX, VY, h_ground], 1)
    VC = np.stack([VX, VY, h_can], 1)
    fn = tri_normals(VG, tris)
    cn = corner_normals(VG, tris, FV_SMOOTH_DEG)
    if (tri_normals(VG, tris)[:, 2] <= 0).any() or (tri_normals(VC, ctris)[:, 2] <= 0).any():
        raise RuntimeError("a far valley triangle does not face up")

    # ---- tiles: the ring on a grid of squares, the core as one tile
    P = VG[tris]
    RX, RZ = P[:, :, 0], -P[:, :, 1]
    lo = np.stack([RX.min(1), RZ.min(1)], 1)
    hi = np.stack([RX.max(1), RZ.max(1)], 1)
    ring_idx = np.nonzero(~core)[0]
    t_ring, tiles, ncol = strip_tiles(tcx[ring_idx], -tcy[ring_idx], lo[ring_idx], hi[ring_idx], TILE_LIMIT)
    tile = -np.ones(len(tris), np.int64)
    tile[ring_idx] = t_ring
    ids = []
    for tinfo in tiles:
        tinfo["id"] = "%s%d" % ("ABCDEFGH"[tinfo["col"]], tinfo["row"] + 1)
        ids.append(tinfo["id"])
    tile[core] = len(tiles)
    tiles.append(dict(col=-1, row=-1, n=int(core.sum()), id="Core"))
    # a ground class with under 24 triangles in a tile is not worth a part: those triangles take the tile's commonest
    # other ground class (the lake's bed keeps its own; so does the scree, which is one small patch on the peak's
    # shoulder, down to 8 triangles)
    recl = 0
    for k in range(len(tiles)):
        for ci in range(5):
            m = (tile == k) & (tri_class == ci)
            if 0 < int(m.sum()) < (8 if ci == 4 else 24):
                others = np.bincount(tri_class[(tile == k) & (tri_class != ci) & (tri_class != 5)], minlength=6)
                tri_class[m] = int(others.argmax())
                recl += int(m.sum())
    log("far valley: %d triangles of classes too small for a part took their tile's commonest class; now %s" % (
        recl, ", ".join("%s %d" % (FV_ORDER[k], int((tri_class == k).sum())) for k in range(6))))
    # parts of a few triangles join the same class in a neighbouring tile; never across the core's rim, so that the
    # nine ring tiles stay exactly the ring
    tile_g, tile_c = tile.copy(), tile.copy()
    tg, moved_g = merge_small_parts(tile[ring_idx], tri_class[ring_idx], lo[ring_idx], hi[ring_idx], TILE_LIMIT)
    tile_g[ring_idx] = tg
    c_idx = np.nonzero(canopy & ~core)[0]
    tc, moved_c = merge_small_parts(tile[c_idx], np.zeros(len(c_idx), np.int64), lo[c_idx], hi[c_idx], TILE_LIMIT)
    tile_c[c_idx] = tc
    log("far valley: %d tiles: %s; %d small parts joined a neighbouring tile's part of the same class" % (
        len(tiles), ", ".join(t["id"] for t in tiles), len(moved_g) + len(moved_c)))

    assets = []
    for k, tinfo in enumerate(tiles):
        parts = []
        for ci, cname in enumerate(FV_ORDER):
            role, _, key, _, smooth = FV_CLASSES[cname]
            if cname == "Canopy":
                m = (tile_c == k) & canopy
                if not m.any():
                    continue
                pv, pt = compact(VC, tris[m])
                nrm = None
            else:
                m = (tile_g == k) & (tri_class == ci)
                if not m.any():
                    continue
                pv, pt = compact(VG, tris[m])
                nrm = cn[m]
            parts.append(dict(name="M1_Far_%s_%s" % (tinfo["id"], cname), role=role, V=pv, T=pt,
                              rgb=tuple(int(v) for v in G.PAL[key]), normals=nrm,
                              extra={"class": cname, "tile": tinfo["id"], "paletteKey": key}))
        is_core = tinfo["id"] == "Core"
        assets.append(dict(
            name="M1_Far_" + tinfo["id"], kind="FarValley",
            tags=["FarValley", "Persistent", "NoCollision", "NoShadow"] + (["Optional"] if is_core else []),
            notes=("far valley, the core (r under %d): the heart and the Iris meadow, for views from the valley "
                   "sides when the heart is not streamed in. OPTIONAL: leave it out and the file is exactly the "
                   "ring r %d-%d. Its rim is the ring's inner rim (the same vertices), so the two join without a "
                   "gap." % (FV_R0, FV_R0, FV_R1)) if is_core else
                  ("far valley tile %s of the ring r %d-%d (column %s from the west, row %d from the north), in "
                   "world space: place at the map centre, ModelStreamingMode Persistent, CanCollide/CanQuery/"
                   "CanTouch/CastShadow false" % (tinfo["id"], FV_R0, FV_R1, tinfo["id"][0], tinfo["row"] + 1)),
            parts=parts, extra=dict(tile=tinfo["id"], optional=is_core)))
    pal = {c: dict(role=FV_CLASSES[c][0], robloxMaterial=FV_CLASSES[c][1], paletteKey=FV_CLASSES[c][2],
                   rgb=list(G.PAL[FV_CLASSES[c][2]]), shading="smooth" if FV_CLASSES[c][4] else "flat")
           for c in FV_ORDER}
    top = dict(
        maxTris=FV_MAX_TRIS, maxPartTris=FV_MAX_PART,
        notes=("A low-poly copy of Map 1's valley for the view where voxel terrain is not streamed in: a decimated "
               "height field on a polar grid (2-degree steps; cells about 30 studs at r 850 growing to 64 x 96 at "
               "the rim, r 2,750; the vertices are nudged off the exact grid so that patches of a class do not show "
               "as rectangles from the horn). The ground is a LOWER ENVELOPE of Map1_Height.png: at every 4-stud sample it "
               "lies at least 6 studs under the lowest of that sample and its eight neighbours, so real terrain "
               "covers it wherever terrain is present ('fit' gives the measured depths). Tiles: M1_Far_A1 ... "
               "M1_Far_C3 are a 3 x 3 grid over the ring (column A west to C east, row 1 north to 3 south); "
               "M1_Far_Core is the disc inside r 850 and is optional. Parts: M1_Far_<tile>_<class>, one flat colour "
               "per part, the palette's own (Map1_Terrain.json 'palette'), the same in every tile. Ground classes "
               "(Grass, DryGrass, Heather, Rock, Scree, Water) are smooth-shaded with normals worked out on the "
               "whole sheet before it was cut (faces that meet at over 45 degrees keep an edge), so parts and "
               "tiles shade as one surface; Water is the lake's bed in the lake's colour (the bed, "
               "not the surface, so that it stays under the real lake). Canopy is a separate flat-shaded sheet at "
               "least 18 studs above the true ground (18-24 on even ground) wherever the conifers are dense; it "
               "has no sides and faces up only, so from under it, among the real trees, it is not drawn. No vertex "
               "colours, no textures, single-sided, every triangle faces up. " + PLACING),
        classes=pal, fit=fit_stats, canopy=can_stats,
        grid=dict(ringInnerR=FV_R0, rimR=FV_R1, angularSteps=FV_NTH, radialStepAtInner=FV_S0, radialStepAtRim=FV_S1,
                  vertexJitter=FV_JITTER,
                  rings=[[round(r, 2), n] for r, n in rings], tiles=[t["id"] for t in tiles],
                  partRule="a triangle belongs to the tile its centroid lies in; a ground class with under 24 "
                           "triangles in a tile (Scree: under 8) takes that tile's commonest other ground class"),
        colourNote=("To match the real terrain exactly at the streaming edge, give the Grass and DryGrass parts the "
                    "colour the terrain's Grass material ends up with; the palette values here are the Blender "
                    "paint's (meadow and dry)."))
    man = export_set("Map1_FarValley", assets, top)
    # ---- a picture of the classes from above (our own data only)
    img = np.zeros((NF, NF, 3), np.uint8)
    img[:] = (30, 30, 34)
    pc = tri_class[ptri]
    for k in range(6):
        img[pj[pc == k], pi[pc == k]] = G.PAL[FV_CLASSES[FV_ORDER[k]][2]]
    cmask = canopy[ptri]
    img[pj[cmask], pi[cmask]] = G.PAL["needles"]
    un = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    shade = np.clip(0.78 + 0.22 * un[:, 2] + 0.3 * (un[:, 1] - un[:, 0]) * 0.7071, 0.55, 1.2)   # lit from the NW
    img[pj, pi] = np.clip(img[pj, pi] * shade[ptri][:, None], 0, 255).astype(np.uint8)
    G.png_write(os.path.join(PREV, "far_classes.png"), img[::2, ::2])
    log("PREVIEW", os.path.join(PREV, "far_classes.png"))
    return man


# ================================================================================================ STAGE: verify
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def glb_parts(path):
    """Reads a GLB with numpy only: per mesh node its name, its parent's name and translation, triangles (positions
    in the mesh's own space, glTF axes = Roblox axes), stored normals, material colour and flags."""
    with open(path, "rb") as f:
        data = f.read()
    magic, _, length = struct.unpack("<4sII", data[:12])
    assert magic == b"glTF", path
    pos, js, bn = 12, None, None
    while pos < length:
        ln, typ = struct.unpack("<I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        pos += 8 + ln
        if typ == b"JSON":
            js = json.loads(body.decode("utf-8"))
        elif typ.startswith(b"BIN"):
            bn = body

    def acc(idx):
        a = js["accessors"][idx]
        bv = js["bufferViews"][a["bufferView"]]
        dt = np.dtype(CT[a["componentType"]])
        n = NC[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0)
        if stride and stride != dt.itemsize * n:
            raw = np.frombuffer(bn, np.uint8, stride * a["count"], off).reshape(a["count"], stride)[:, :dt.itemsize * n]
            return np.frombuffer(raw.tobytes(), dt).reshape(a["count"], n)
        return np.frombuffer(bn, dt, a["count"] * n, off).reshape(a["count"], n)

    nodes = js.get("nodes", [])
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    rows = []
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        prims = js["meshes"][n["mesh"]]["primitives"]
        assert len(prims) == 1, n.get("name")
        prim = prims[0]
        at = prim["attributes"]
        Pv = acc(at["POSITION"]).astype(np.float64)
        Nv = acc(at["NORMAL"]).astype(np.float64) if "NORMAL" in at else None
        I = acc(prim["indices"]).reshape(-1, 3).astype(np.int64)
        mat = js["materials"][prim["material"]] if "material" in prim else {}
        pbr = mat.get("pbrMetallicRoughness", {})
        par = nodes[parent[i]] if i in parent else {}
        rows.append(dict(name=n.get("name"), parent=par.get("name"), translation=par.get("translation", [0, 0, 0]),
                         own=n.get("translation", [0, 0, 0]), rot=n.get("rotation"), scale=n.get("scale"),
                         P=Pv, N=Nv, I=I, rgb=[int(round(float(v))) for v in srgb_of(pbr.get("baseColorFactor", [1, 1, 1, 1])[:3])],
                         doubleSided=bool(mat.get("doubleSided", False)), color0="COLOR_0" in at,
                         uv="TEXCOORD_0" in at, tangent="TANGENT" in at))
    return rows, js


class Checker:
    def __init__(self):
        self.fails = 0
        self.lines = []

    def __call__(self, ok, label, detail=""):
        if not ok:
            self.fails += 1
        line = "%s  %s%s" % ("PASS" if ok else "FAIL", label, (": " + detail) if detail else "")
        self.lines.append(line)
        print(line, flush=True)
        return ok


def check_glb(check, man, rows, max_part_tris):
    glb = man["glb"]
    by = {r["name"]: r for r in rows}
    parts = [(a, p) for a in man["assets"] for p in a["parts"]]
    names = [p["name"] for _, p in parts]
    check(sorted(names) == sorted(by) and len(set(names)) == len(names), "%s: part names = GLB mesh nodes (%d)" % (
        glb, len(names)), "only in manifest %s, only in GLB %s" % (sorted(set(names) - set(by))[:4],
                                                                   sorted(set(by) - set(names))[:4]))
    bad = [p["name"] for _, p in parts if p["name"] in by and len(by[p["name"]]["I"]) != p["tris"]]
    check(not bad, "%s: triangle counts agree" % glb, str(bad[:4]))
    bad = [a["name"] for a in man["assets"] if a["tris"] != sum(p["tris"] for p in a["parts"])]
    check(not bad, "%s: each asset's triangle count is the sum of its parts'" % glb, str(bad[:4]))
    bad = [(p["name"], p["rgb"], by[p["name"]]["rgb"]) for _, p in parts if p["name"] in by
           and max(abs(x - y) for x, y in zip(p["rgb"], by[p["name"]]["rgb"])) > 1]
    check(not bad, "%s: each part's rgb = its GLB material's colour" % glb, str(bad[:3]))
    check(not any(r["color0"] or r["doubleSided"] for r in rows) and all(r["uv"] and r["tangent"] for r in rows),
          "%s: single-sided, UVs and tangents, no vertex colours" % glb)
    worst_agree, down, degenerate = 1.0, 0, 0
    for r in rows:
        tri = r["P"][r["I"]]
        fnr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        area = 0.5 * np.linalg.norm(fnr, axis=1)
        ok = area > 1e-9
        degenerate += int((~ok).sum())
        vn = r["N"][r["I"][ok]].mean(1)
        worst_agree = min(worst_agree, float(((fnr[ok] * vn).sum(1) > 0).mean()))
        down += int((fnr[ok][:, 1] <= 0).sum())                       # glTF +Y is up
        r["up"] = float((area[ok] * (fnr[ok][:, 1] > 0)).sum() / max(area[ok].sum(), 1e-9))
        r["area"] = float(area.sum())
    check(worst_agree > 0.999, "%s: stored normals agree with the winding" % glb, "worst part %.4f" % worst_agree)
    check(down == 0 and degenerate == 0, "%s: every triangle faces up (single-sided, toward the arena); none is "
          "degenerate" % glb, "%d face down or sideways, %d degenerate" % (down, degenerate))
    wrong = [p["name"] for _, p in parts if p["name"] in by and p.get("faces") == "up" and by[p["name"]]["up"] < 0.5]
    check(not wrong, "%s: every hinted sheet faces the way its manifest says" % glb, str(wrong[:4]))
    # sizes and positions: the GLB's own numbers against the manifest and the limit
    longest, bad_size, bad_pos, bad_origin, bad_xform = 0.0, [], [], [], []
    for a, p in parts:
        r = by.get(p["name"])
        if r is None:
            continue
        lo, hi = r["P"].min(0), r["P"].max(0)
        size = hi - lo
        longest = max(longest, float(size.max()))
        if float(size.max()) > PART_LIMIT:
            bad_size.append((p["name"], [round(float(v), 1) for v in size]))
        if np.abs(size - np.array(p["size"])).max() > 0.01 or np.abs(0.5 * (lo + hi) - np.array(p["position"])).max() > 0.01:
            bad_pos.append(p["name"])
        if r["parent"] != a["name"] or np.abs(np.array(r["translation"]) - np.array(a["origin"])).max() > 0.01:
            bad_origin.append(p["name"])
        if np.abs(np.array(r["own"])).max() > 1e-6 or r["rot"] not in (None, [0, 0, 0, 1]) or r["scale"] not in (None, [1, 1, 1]):
            bad_xform.append(p["name"])
    check(not bad_size, "%s: no part's bounding box is over %.0f studs on any axis" % (glb, PART_LIMIT),
          "longest %.1f; over: %s" % (longest, bad_size[:3]))
    check(not bad_pos, "%s: each part's position and size in the manifest are its bounding box in the GLB" % glb,
          str(bad_pos[:4]))
    check(not bad_origin, "%s: each part hangs under its asset's node, which stands at the manifest's origin" % glb,
          str(bad_origin[:4]))
    check(not bad_xform, "%s: no part node carries a transform of its own" % glb, str(bad_xform[:4]))
    bad = [(p["name"], p["tris"]) for _, p in parts if p["tris"] > max_part_tris]
    check(not bad, "%s: no part has more than %d triangles" % (glb, max_part_tris),
          "most %d; over: %s" % (max(p["tris"] for _, p in parts), bad[:3]))
    bad = [p["name"] for _, p in parts if p["collide"] or p["canQuery"] or p["canTouch"] or p["castShadow"]]
    check(not bad, "%s: no part collides, answers queries, touches or casts a shadow" % glb, str(bad[:4]))
    check(not man["warnings"], "%s: no warnings" % glb, str(man["warnings"][:3]))
    mp = os.path.join(OUT, glb.replace(".glb", ".manifest.json"))
    if os.path.normcase(OUT) == os.path.normcase(G.DEFAULT_OUT):
        ok, how = same_manifest_in_repo(mp)
        check(ok, "art/manifests/%s says what the export's manifest says" % os.path.basename(mp), how)
    return by


def verify_stage(before):
    check = Checker()
    J = lambda n: json.load(open(os.path.join(SRC, n)))
    now = protected_hashes()
    changed = sorted(n for n in before if now.get(n) != before[n])
    check(len(before) == len(PROTECTED) and not changed,
          "the generator's 22 export files are byte-identical to what they were when this run began", str(changed))
    present = sorted(os.listdir(SRC))
    extra = sorted(set(present) - set(PROTECTED) - set(OWN))
    check(not extra and all(n in present for n in PROTECTED), "the source folder holds the 22 files and nothing "
          "unknown", "extra %s" % extra)
    T = J("Map1_Terrain.json")
    L = J("Map1_Layout.json")

    # ---------------------------------------------------------------- the skyline
    sp = os.path.join(OUT, "Map1_SkylineCut.glb")
    if os.path.exists(sp):
        man = json.load(open(os.path.join(OUT, "Map1_SkylineCut.manifest.json")))
        rows, _ = glb_parts(sp)
        by = check_glb(check, man, rows, 5000)
        want = sorted(it["asset"] for it in L["items"] if it["asset"].startswith("M1_Skyline_"))
        check(sorted(a["name"] for a in man["assets"]) == want, "Map1_SkylineCut: its assets are the eight Map1_Layout"
              ".json places", str(want))
        check(all(it["position"] == [0.0, 0.0, 0.0] or it["position"] == [0.0, 0.0, -0.0] for it in L["items"]
                  if it["asset"].startswith("M1_Skyline_")), "Map1_Layout.json places each of them at the map centre")
        old_man = J("Map1_Skyline.manifest.json")
        old_rows, _ = glb_parts(os.path.join(SRC, "Map1_Skyline.glb"))
        old_by = {r["name"]: r for r in old_rows}
        # the same triangles: every triangle of the old file, by role, is in the new one (centroid and area)
        same = True
        detail = []
        for role in ("SkylineGrass", "SkylineForest", "SkylineRock"):
            def tri_table(rws):
                out = []
                for r in rws:
                    tri = r["P"][r["I"]]
                    ar = 0.5 * np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
                    out.append(np.concatenate([tri.mean(1), ar[:, None]], 1))
                t = np.concatenate(out)
                return t[np.lexsort((t[:, 2], t[:, 1], t[:, 0]))]
            a_ = tri_table([r for r in old_rows if r["name"].endswith("_" + role)])
            b_ = tri_table([r for r in rows if r["name"].endswith("_" + role)])
            ok = a_.shape == b_.shape and float(np.abs(a_ - b_).max()) < 0.02
            same = same and ok
            detail.append("%s %d/%d" % (role, len(a_), len(b_)))
        check(same, "Map1_SkylineCut: the same triangles as Map1_Skyline.glb, role by role (centroid and area of "
              "every one)", ", ".join(detail))
        check(man["totals"]["tris"] == sum(a["tris"] for a in old_man["assets"]) == 44000,
              "Map1_SkylineCut: the same triangle budget", "%d (was %d)" % (
                  man["totals"]["tris"], sum(a["tris"] for a in old_man["assets"])))
        old_rgb = {(a["name"], p["role"]): p["rgb"] for a in old_man["assets"] for p in a["parts"]}
        bad = [p["name"] for a in man["assets"] for p in a["parts"] if p["rgb"] != old_rgb[(a["name"], p["role"])]]
        check(not bad, "Map1_SkylineCut: every part has the colour its sector's role had in Map1_Skyline.glb", str(bad[:4]))
        # seen from the arena: how much of the range's area shows its front to an eye over the horn
        for eye_y in (60.0, 640.0):
            front = tot = 0.0
            for r in rows:
                tri = r["P"][r["I"]]
                fnr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
                c_ = tri.mean(1)
                ar = 0.5 * np.linalg.norm(fnr, axis=1)
                front += float(ar[(fnr * (np.array([0.0, eye_y, 0.0]) - c_)).sum(1) > 0].sum())
                tot += float(ar.sum())
            print("      skyline area facing an eye at the map centre, y %.0f: %.1f%% (the rest is the far side of "
                  "ridges, hidden by them)" % (eye_y, 100.0 * front / tot))
        print("      skyline: %d parts in %d tiles, longest part %.1f studs; Map1_Skyline.glb had %d parts up to "
              "%.0f studs" % (man["totals"]["parts"], len(man["tiling"]["tiles"]), man["totals"]["longestPart"],
                              len(old_rows), max(float((r["P"].max(0) - r["P"].min(0)).max()) for r in old_rows)))
    else:
        check(False, "Map1_SkylineCut.glb exists")

    # ---------------------------------------------------------------- the far valley
    fp = os.path.join(OUT, "Map1_FarValley.glb")
    if os.path.exists(fp):
        man = json.load(open(os.path.join(OUT, "Map1_FarValley.manifest.json")))
        rows, _ = glb_parts(fp)
        by = check_glb(check, man, rows, FV_MAX_PART)
        check(man["totals"]["tris"] <= FV_MAX_TRIS, "Map1_FarValley: at most %d triangles in all" % FV_MAX_TRIS,
              str(man["totals"]["tris"]))
        ok = all(p["name"] == "M1_Far_%s_%s" % (a["tile"], p["class"]) and a["name"] == "M1_Far_" + a["tile"]
                 and p["class"] in FV_CLASSES for a in man["assets"] for p in a["parts"])
        check(ok, "Map1_FarValley: parts are named M1_Far_<tile>_<class>")
        pal = T["palette"]
        bad = [p["name"] for a in man["assets"] for p in a["parts"] if p["rgb"] != pal[p["paletteKey"]]]
        check(not bad, "Map1_FarValley: every part's colour is its class's tone in Map1_Terrain.json's palette",
              str(bad[:4]))
        Hp = png_read_grey(os.path.join(SRC, "Map1_Height.png")).astype(np.float64) / 32.0
        c = -HALF + SPP * (np.arange(NF) + 0.5)
        Rg = np.hypot(*np.meshgrid(c, c))
        ground = np.full((NF, NF), np.nan)              # the highest ground sheet over each sample
        ground_lo = np.full((NF, NF), np.nan)           # the lowest (they differ only where two parts overlap)
        cover = np.zeros((NF, NF), np.int32)
        canopy_h = np.full((NF, NF), np.nan)
        ring_cover = np.zeros((NF, NF), bool)
        for a in man["assets"]:
            for p in a["parts"]:
                r = by[p["name"]]
                # glTF (x, y, z) = Roblox (X, Y, Z) = Blender (x, z, -y); rasterise() wants Blender x, y
                vx, vy, vh = r["P"][:, 0], -r["P"][:, 2], r["P"][:, 1]
                pj, pi, ptri, pw = rasterise(vx, vy, r["I"])
                hgt = (pw * vh[r["I"][ptri]]).sum(1)
                if p["class"] == "Canopy":
                    canopy_h[pj, pi] = hgt
                else:
                    ground_lo[pj, pi] = np.where(np.isnan(ground[pj, pi]), hgt, np.minimum(ground_lo[pj, pi], hgt))
                    ground[pj, pi] = np.where(np.isnan(ground[pj, pi]), hgt, np.maximum(ground[pj, pi], hgt))
                    cover[pj, pi] += 1
                    if not a.get("optional"):
                        ring_cover[pj, pi] = True
        g = ~np.isnan(ground)
        below = Hp[g] - ground[g]
        check(float(below.min()) >= FV_DROP - 0.002, "Map1_FarValley: at every 4-stud sample the ground sheet is at "
              "least %.0f studs under Map1_Height.png" % FV_DROP, "min %.3f, mean %.2f, p99 %.1f, max %.1f over %d "
              "samples" % (below.min(), below.mean(), np.percentile(below, 99), below.max(), int(g.sum())))
        low3 = filt3(Hp, np.minimum)
        check(float((low3[g] - ground[g]).min()) >= FV_DROP - 0.002, "Map1_FarValley: ... and under the lowest of "
              "that sample's eight neighbours too (4 studs each way)", "min %.3f" % float((low3[g] - ground[g]).min()))
        rim = FV_R1 * math.cos(math.pi / FV_NTH) - 0.5
        ring = (Rg >= FV_R0 + 0.5) & (Rg <= rim)
        check(bool(ring_cover[ring].all()), "Map1_FarValley: the ring r %.0f-%.0f has no hole (every sample under a "
              "ground triangle of the nine ring tiles)" % (FV_R0, FV_R1), "%d of %d samples uncovered" % (
                  int((~ring_cover[ring]).sum()), int(ring.sum())))
        check(not bool(ring_cover[Rg < FV_R0 - 4.5].any()) and float(Rg[g].max()) <= FV_R1 + 0.01,
              "Map1_FarValley: the nine ring tiles hold nothing inside r %.0f, and nothing lies past r %.0f" % (
                  FV_R0, FV_R1), "outermost sample r %.1f" % float(Rg[g].max()))
        disc = Rg <= rim
        twice = disc & (cover > 1)                      # a sample exactly on an edge two parts share counts twice
        spread = float((ground[twice] - ground_lo[twice]).max()) if twice.any() else 0.0
        check(bool(g[disc].all()) and spread < 0.01 and int(twice.sum()) < 0.001 * int(disc.sum()),
              "Map1_FarValley: with the core, the whole disc is covered once (no hole, no overlap)",
              "uncovered %d; %d samples lie on an edge shared by two parts (heights there agree within %.4f)" % (
                  int((~g[disc]).sum()), int(twice.sum()), spread))
        cg = ~np.isnan(canopy_h)
        if cg.any():
            above = canopy_h[cg] - Hp[cg]
            check(float(above.min()) >= FV_CANOPY_MIN - 0.002, "Map1_FarValley: the canopy sheet is at least %.0f "
                  "studs above Map1_Height.png everywhere" % FV_CANOPY_MIN, "min %.2f, median %.1f, p99 %.1f over %d "
                  "samples" % (above.min(), np.median(above), np.percentile(above, 99), int(cg.sum())))
            mask = png_read_grey(os.path.join(SRC, "Map1_Mask_Conifer.png")).astype(np.float64) / 255.0
            m4 = np.repeat(np.repeat(mask, 2, 0), 2, 1)
            inner = cg & (Rg < 2200.0)
            print("      canopy: %.1f%% of the disc; mean Map1_Mask_Conifer under it inside r 2,200: %.2f (outside "
                  "it: %.2f)" % (100.0 * cg[disc].mean(), float(m4[inner].mean()),
                                 float(m4[disc & ~cg & (Rg < 2200.0) & (Rg > FV_R0)].mean())))
        share = {}
        for a in man["assets"]:
            for p in a["parts"]:
                share[p["class"]] = share.get(p["class"], 0) + p["tris"]
        print("      far valley triangles by class: %s; ring %d, core %d" % (
            ", ".join("%s %d" % (k, share[k]) for k in FV_ORDER if k in share),
            sum(a["tris"] for a in man["assets"] if not a.get("optional")),
            sum(a["tris"] for a in man["assets"] if a.get("optional"))))
    else:
        check(False, "Map1_FarValley.glb exists")
    print("\n%s (%d failed)" % ("ALL PASS" if not check.fails else "FAILURES", check.fails), flush=True)
    return check.fails


# ================================================================================================ STAGE: render
# Views of the two files AS EXPORTED (flat part colours, no per-facet paint) in the generator's saved scene, with
# everything a client would not have past its streaming radius taken away: the terrain, the water and the scatter
# beyond r 1,024, and the hedges at r 1,600. The peak stays (a Persistent landmark). "full" renders are the same
# cameras in the untouched pass-3 scene, for comparison.
STREAM_R = 1024.0
EYE = 4.8
FAR_SHOTS = {
    # the trailer's view out of the south mouth: the generator's own match_t2_49.9s camera, light and exposure
    "far_horn_south_mouth": dict(G.SHOTS["match_t2_49.9s"], ref=None),
    # a player's eye (the game's 72-degree lens) on the deck at the top of the south stair, and on the deck's north point
    "far_deck_south": dict(cam=tuple(G.P3(180.0, 22.0, 52.05 + EYE)), yaw=180.0, pitch=3.0, vfov=72.0,
                           res=(1920, 1080), sun=(135.0, 48.0), exposure=0.0, ref=None),
    "far_deck_north": dict(cam=tuple(G.P3(0.0, 43.0, 52.05 + EYE)), yaw=0.0, pitch=4.0, vfov=72.0,
                           res=(1920, 1080), sun=(135.0, 48.0), exposure=0.0, ref=None),
    "far_aerial": dict(G.SHOTS["birdseye_34"]),
}
FAR_FULL = ("far_deck_south", "far_deck_north")       # also rendered in the untouched scene ("_full")


def _clip_mesh(ob, rmax):
    """keep only the faces whose centre lies within rmax of the map's axis (a new mesh; face colours carried over)"""
    me = ob.data
    n = len(me.polygons)
    ctr = np.zeros(n * 3, np.float32)
    me.polygons.foreach_get("center", ctr)
    ctr = ctr.reshape(-1, 3)
    keep = np.hypot(ctr[:, 0], ctr[:, 1]) <= rmax
    ls = np.zeros(n, np.int32)
    me.polygons.foreach_get("loop_start", ls)
    vi = np.zeros(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", vi)
    co = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    T = vi[ls[keep][:, None] + np.arange(3)[None, :]]
    new = np_mesh(me.name + "_near", co.reshape(-1, 3), T)
    old_col = me.attributes.get("Col")
    if old_col is not None:
        buf = np.zeros(n * 4, np.float32)
        old_col.data.foreach_get("color", buf)
        at = new.attributes.new("Col", "FLOAT_COLOR", "FACE")
        at.data.foreach_set("color", buf.reshape(-1, 4)[keep].ravel())
    for m in me.materials:
        new.materials.append(m)
    new.shade_flat()
    ob.data = new
    return int(keep.sum()), n


def _clip_points(ob, rmax):
    me = ob.data
    n = len(me.vertices)
    co = np.zeros(n * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    keep = np.hypot(co[:, 0], co[:, 1]) <= rmax
    new = bpy.data.meshes.new(me.name + "_near")
    new.vertices.add(int(keep.sum()))
    new.vertices.foreach_set("co", co[keep].ravel())
    for an in ("rot", "scl"):
        a = me.attributes.get(an)
        if a is None:
            continue
        buf = np.zeros(n * 3, np.float32)
        a.data.foreach_get("vector", buf)
        na = new.attributes.new(an, "FLOAT_VECTOR", "POINT")
        na.data.foreach_set("vector", buf.reshape(-1, 3)[keep].ravel())
    new.update()
    ob.data = new
    return int(keep.sum()), n


def _import_far(path, man, coll):
    """the exported GLB back into the scene: assets to the map centre, each part in its manifest colour"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    rgb = {p["name"]: p["rgb"] for a in man["assets"] for p in a["parts"]}
    mat = bpy.data.materials.get("M1_FarFlat")
    if mat is None:                 # the terrain's matte, hazed material, drawn from the front only (as Roblox does)
        mat = bpy.data.materials["M1_Terrain"].copy()
        mat.name = "M1_FarFlat"
        nt = mat.node_tree
        out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
        src = out.inputs["Surface"].links[0].from_socket
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
        nt.links.new(src, mix.inputs[1])
        nt.links.new(clear.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    made = [o for o in bpy.data.objects if o not in before]
    for o in made:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        if o.type == "EMPTY":
            o.location = (0.0, 0.0, 0.0)
        elif o.type == "MESH":
            me = o.data
            col = rgb[o.name.split(".")[0]]
            at = me.attributes.new("Col", "FLOAT_COLOR", "FACE")
            at.data.foreach_set("color", np.tile(np.append(G.lin(col), 1.0).astype(np.float32), len(me.polygons)))
            me.materials.clear()
            me.materials.append(mat)
            o.visible_shadow = False                   # CastShadow is false on every part of both files
    return made


def render_stage():
    scene_path = os.path.join(WORK, "Map1_scene.blend")
    log("render: loading", scene_path)
    bpy.ops.wm.open_mainfile(filepath=scene_path)
    sc = bpy.context.scene
    G.setup_gpu_only(sc)
    D = np.load(os.path.join(WORK, "field.npz"))
    G.mist_layer(sc)
    only = [s for s in G.SHOT_FILTER if s]              # a 4th argument: only the pictures named (file names, no .png)

    def shoot(shot, name):
        if only and name not in only:
            return
        G.apply_shot(sc, shot, FAR_SHOTS[shot], D)
        sc.render.filepath = os.path.join(PREV, name + ".png")
        t = time.time()
        bpy.ops.render.render(write_still=True)
        log("RENDER %s (%.0fs)" % (sc.render.filepath, time.time() - t))

    for shot in FAR_FULL:
        shoot(shot, shot + "_full")
    # what a client at the horn holds: nothing of the terrain, the water or the scatter past the streaming radius
    for nm in ("M1_Terrain", "M1_Lake", "M1_Stream"):
        k, n = _clip_mesh(bpy.data.objects[nm], STREAM_R)
        log("render: %s keeps %d of %d faces inside r %.0f" % (nm, k, n, STREAM_R))
    pts = [0, 0]
    for ob in bpy.data.collections["M1_Scatter"].objects:
        k, n = _clip_points(ob, STREAM_R)
        pts[0] += k
        pts[1] += n
    log("render: the scatter keeps %d of %d plants and rocks" % tuple(pts))
    for ob in bpy.data.collections["M1_Sites"].objects:
        if ob.name.startswith("M1_Skyline_"):
            ob.hide_render = True                                         # the pass-3 sectors: replaced by the re-cut
        elif math.hypot(ob.location.x, ob.location.y) > STREAM_R and not ob.name.startswith("M1_Peak"):
            ob.hide_render = True
    coll = bpy.data.collections.new("M1_Far")
    sc.collection.children.link(coll)
    sky = _import_far(os.path.join(OUT, "Map1_SkylineCut.glb"),
                      json.load(open(os.path.join(OUT, "Map1_SkylineCut.manifest.json"))), coll)
    far = _import_far(os.path.join(OUT, "Map1_FarValley.glb"),
                      json.load(open(os.path.join(OUT, "Map1_FarValley.manifest.json"))), coll)
    log("render: imported %d skyline and %d far valley objects from the exported GLBs" % (len(sky), len(far)))
    for shot in FAR_SHOTS:
        shoot(shot, shot)
    # the same without the far valley: what the horn would look out on with the skyline alone
    for o in far:
        o.hide_render = True
    for shot in FAR_FULL:
        shoot(shot, shot + "_no_far_valley")


# ================================================================================================ main
def main():
    log("Map 1 far exports: stages", STAGES, "out", OUT, "preview", PREV, "work", WORK, "source", SRC)
    before = protected_hashes()
    if len(before) != len(PROTECTED):
        raise RuntimeError("the source folder %s lacks %s" % (SRC, sorted(set(PROTECTED) - set(before))))
    fails = 0
    if "skyline" in STAGES:
        skyline_stage()
    if "farvalley" in STAGES:
        far_valley_stage()
    if "verify" in STAGES:
        fails = verify_stage(before)
    if "render" in STAGES:
        render_stage()
    after = protected_hashes()
    changed = sorted(n for n in before if after.get(n) != before[n])
    if changed:
        raise RuntimeError("PROTECTED FILES CHANGED: %s" % changed)
    log("the generator's %d export files are unchanged (SHA-256 before = after)" % len(before))
    log("done")
    if fails:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
