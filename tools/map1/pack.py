"""pack.py - Map 1's data pack: the Blender exports turned into the data the game builds from.

See README.md beside this file and docs/design/Map1Build.md section 3.3 (the contract).

  python tools/map1/pack.py                read the exports, repair the water, write the blobs, build the Studio pack
                                           "map1_data", write Shared/Map1Regions.lua, the repair log, the manifest and
                                           the Studio proof script
  python tools/map1/pack.py --dry          read, repair and check only; writes nothing
  python tools/map1/pack.py --no-pack      write the files but do not build the Studio pack

The Studio pack is written only when it would differ from the one already in Studio's content folder, so running
the command again changes nothing. After a Studio update the pack is gone: the same command builds it again.

Options
  --exports DIR      the Blender export folder (default: $LS_MAP1_EXPORTS, else
                     %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Map1)
  --build DIR        where the blob files go (default: tools/map1/build, not committed; build/NAME for --pack-name)
  --force-pack       write the Studio pack even if the one in Studio's content folder is already this build
  --margin           give narrow pools (the stream) a wet margin one cell wide, so that the designed water shows
                     (README, "The margin"); --no-margin turns it off. The default is STREAM_MARGIN below.
  --pack-name NAME   another name for the Studio pack, for experiments: the log and the manifest then stay in the
                     build folder and the module is not written (the contract's name is map1_data)
  --height-cell N    spacing of Map1Regions' height nodes in studs: 32 (default) or 64
  --no-module        do not write src/ReplicatedStorage/Shared/Map1Regions.lua
  --ready FILE       also write the blob list (build number, sizes, fingerprints) to FILE

Python 3 with numpy. No Pillow: pngread.py beside this file reads the PNGs.
"""
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import pngread  # noqa: E402

BS = chr(92)

# ----------------------------------------------------------------------------------------------------------------------
# The contract (docs/design/Map1Build.md 3.3). A change here is a change to every reader of the pack.
# ----------------------------------------------------------------------------------------------------------------------
N = 1376  # cells a side; one cell is one 4-stud voxel column
CELL = 4
ORIGIN = -2752  # x and z of the grid's north-west corner; row 0 is the north row
MASK_N = 688
UNIT = 32  # heights and water levels are stored as studs * 32
VOX = CELL * UNIT  # one voxel layer in stored units
MASKS = ["Conifer", "Broadleaf", "Gorse", "Heather", "Boulders", "Crags", "TallGrass", "Wildflowers"]
MANIFESTS = ["Landmarks", "Plants", "Skyline", "FarValley"]
# The export file behind each Manifest_<Name> blob: the first that exists. The skyline as first exported has parts
# wider than Roblox's 2,048-stud limit, so the re-cut one stands in for it as soon as Blender has made it.
MANIFEST_FILES = {
    "Landmarks": ["Map1_Landmarks.manifest.json"],
    "Plants": ["Map1_Plants.manifest.json"],
    "Skyline": ["Map1_SkylineCut.manifest.json", "Map1_Skyline.manifest.json"],
    "FarValley": ["Map1_FarValley.manifest.json"],
}
REGIONS =["Heart", "Iris", "NorthWood", "EastRidge", "SouthMountain", "Lake", "WestRidge", "Edge", "Crest", "Outside"]
SLOT_BASES = ["Grass", "Grass", "Grass", "LeafyGrass", "Ground", "Salt", "Mud", "Limestone", "Rock", "Basalt"]
KNOLL_Y = 46.0  # ArenaLayout.BaseHeight
RING_Y = 44.3  # ArenaLayout.RingHeight
PLINTHS = 48
PLINTH_RADIUS = 150.0

# The water rules (Map1Build.md decision 5; worldgen report section 4.5).
LEVEL_MIN = 16  # a water level sits at least 0.5 studs into its voxel layer ...
LEVEL_MAX = 64  # ... and at most 2.0
SILL_RISE = 10  # a sill stands 0.3125 studs above the water it holds (TerrainGen's rule is 0.3)
SMALL_POOL = 4  # a pool this small with a bad level becomes dry ground; a bigger one stops the packer
STREAM_MARGIN = False  # give narrow pools a one-cell wet margin (see README, "The margin"); --margin turns it on
MARGIN_DEPTH = 8  # a margin cell's bed is 0.25 studs under the water: too shallow to be taken for a drinking spot
NARROW_POOL = 2000  # a pool with fewer cells than this is narrow water (the stream's pools; not the lake)
MARGIN_MAX_CUT = 96  # no margin where it would lower the ground by more than 3 studs: a steep bank stays as it is
HEART_CLEAR = 200  # no repair may come this close to the centre: the turf (r 180) must stay as Blender made it
NB8 = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))
NB4 = ((-1, 0), (0, -1), (0, 1), (1, 0))

# Map1Regions
REGION_CELL = 16
REGION_N = 240
REGION_ORIGIN = -1920
REGION_SAMPLE = 2  # the region raster is sampled at cell (2, 2) of every 4 x 4 block, as Map1_BiomeGrid16.json is
HEIGHT_FIRST = 35  # "#": the first of the 57 characters ("#" to "[") a height digit may be; none needs escaping
HEIGHT_BASE_N = 57
MODULE_LIMIT = 150000
MODULE_PATH = os.path.join(REPO, "src", "ReplicatedStorage", "Shared", "Map1Regions.lua")


class PackError(Exception):
    pass


def lp(p):
    """Windows long-path form of p (the repo sits deep in the profile folder)."""
    p = os.path.abspath(p)
    if os.name != "nt" or p.startswith(BS + BS):
        return p
    return BS + BS + "?" + BS + p.replace("/", BS)


def read_bytes(p):
    with open(lp(p), "rb") as fh:
        return fh.read()


def write_bytes(p, data):
    d = os.path.dirname(os.path.abspath(p))
    os.makedirs(lp(d), exist_ok=True)
    with open(lp(p), "wb") as fh:
        fh.write(data)


def fnv(data):
    """FNV-1a 32-bit, lowercase hex: the fingerprint tools/studio_sync and StudioSync.lua use."""
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return "%08x" % h


def sha(data):
    return hashlib.sha256(data).hexdigest()


def studs(v):
    return v / float(UNIT)


def cell_xz(row, col):
    return ORIGIN + CELL * (col + 0.5), ORIGIN + CELL * (row + 0.5)


def default_exports():
    env = os.environ.get("LS_MAP1_EXPORTS")
    if env:
        return env
    return os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports", "Map1")


# ----------------------------------------------------------------------------------------------------------------------
# Reading and refusing
# ----------------------------------------------------------------------------------------------------------------------
def read_png(folder, name, size, dtype):
    path = os.path.join(folder, name)
    if not os.path.isfile(lp(path)):
        raise PackError("missing export: " + path)
    arr, _info = pngread.read(lp(path))
    if arr.shape != (size, size) or arr.dtype != dtype:
        raise PackError("%s is %s %s; the contract says %d x %d %s" % (name, arr.shape, arr.dtype, size, size, np.dtype(dtype)))
    return np.ascontiguousarray(arr)


def read_json(folder, name):
    """(the file's text with LF line endings, as bytes; the parsed value). A text blob is then the same on every
    machine, whatever line endings the generator or a git checkout gave the file."""
    path = os.path.join(folder, name)
    if not os.path.isfile(lp(path)):
        raise PackError("missing export: " + path)
    raw = read_bytes(path)
    if raw.startswith(bytes((0xEF, 0xBB, 0xBF))):
        raise PackError(name + " starts with a BOM")
    raw = raw.replace(bytes((13, 10)), bytes((10,)))
    if bytes((13,)) in raw:
        raise PackError(name + " has bare CR characters")
    try:
        return raw, json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as err:
        raise PackError("%s is not UTF-8 JSON: %s" % (name, err))


def load_exports(folder):
    """Everything the pack needs, with every refusal the contract asks for."""
    if not os.path.isdir(lp(folder)):
        raise PackError("the export folder does not exist: " + folder)
    ex = {"folder": folder, "sources": {}, "notes": []}

    def note_source(name):
        raw = read_bytes(os.path.join(folder, name))
        ex["sources"][name] = {"bytes": len(raw), "sha256": sha(raw)}

    ex["height"] = read_png(folder, "Map1_Height.png", N, np.uint16)
    ex["material"] = read_png(folder, "Map1_Material.png", N, np.uint8)
    ex["region"] = read_png(folder, "Map1_Region.png", N, np.uint8)
    ex["waterMask"] = read_png(folder, "Map1_WaterMask.png", N, np.uint8)
    ex["waterLevel"] = read_png(folder, "Map1_WaterLevel.png", N, np.uint16)
    for nm in ("Height", "Material", "Region", "WaterMask", "WaterLevel"):
        note_source("Map1_%s.png" % nm)
    ex["masks"] = {}
    for nm in MASKS:
        ex["masks"][nm] = read_png(folder, "Map1_Mask_%s.png" % nm, MASK_N, np.uint8)
        note_source("Map1_Mask_%s.png" % nm)
    ex["terrainRaw"], ex["terrain"] = read_json(folder, "Map1_Terrain.json")
    ex["layoutRaw"], ex["layout"] = read_json(folder, "Map1_Layout.json")
    note_source("Map1_Terrain.json")
    note_source("Map1_Layout.json")
    ex["manifests"] = {}
    for nm in MANIFESTS:
        fname = next((f for f in MANIFEST_FILES[nm] if os.path.isfile(lp(os.path.join(folder, f)))), None)
        if fname is None:
            ex["notes"].append("%s is not in the export folder: the pack has no Manifest_%s blob" % (
                " / ".join(MANIFEST_FILES[nm]), nm))
            continue
        raw, parsed = read_json(folder, fname)
        if not isinstance(parsed, dict) or not isinstance(parsed.get("assets"), list) or not parsed["assets"]:
            raise PackError(fname + " has no 'assets'")
        note_source(fname)
        entry = {"data": raw, "file": fname, "content": "%s as text" % fname}
        # art/manifests holds a copy of every manifest, and the assets package adds the upload record ("assetIds") to
        # that copy. When the record is the only difference, the pack carries the copy with the record.
        repo_dir = os.path.join(REPO, "art", "manifests")
        if os.path.isfile(lp(os.path.join(repo_dir, fname))):
            repo_raw, repo_parsed = read_json(repo_dir, fname)
            is_dict = isinstance(repo_parsed, dict)
            same = is_dict and {k: v for k, v in repo_parsed.items() if k != "assetIds"} == parsed
            if same and "assetIds" in repo_parsed:
                entry = {"data": repo_raw, "file": "art/manifests/" + fname,
                         "content": "%s as text, from art/manifests: the export's manifest plus its upload record "
                                    "(assetIds)" % fname}
                on_disk = read_bytes(os.path.join(repo_dir, fname))
                ex["sources"]["art/manifests/" + fname] = {"bytes": len(on_disk), "sha256": sha(on_disk)}
            elif not same:
                ex["notes"].append("art/manifests/%s differs from the export's copy in more than assetIds; the pack "
                                   "holds the export's" % fname)
        if fname != MANIFEST_FILES[nm][0]:
            ex["notes"].append("Manifest_%s is %s for now: %s is not in the export folder" % (nm, fname, MANIFEST_FILES[nm][0]))
        ex["manifests"][nm] = entry
    biome = os.path.join(folder, "Map1_BiomeGrid16.json")
    ex["biomeGrid"] = None
    if os.path.isfile(lp(biome)):
        _raw, ex["biomeGrid"] = read_json(folder, "Map1_BiomeGrid16.json")
        note_source("Map1_BiomeGrid16.json")

    # the grid facts every reader hard-codes
    t = ex["terrain"]
    g = t.get("grid", {})
    facts = (g.get("width"), g.get("height"), g.get("studsPerPixel"), tuple(g.get("origin", ())))
    if facts != (N, N, float(CELL), (float(ORIGIN), float(ORIGIN))):
        raise PackError("Map1_Terrain.json grid is %r; the contract says %d x %d cells of %d from %d" % (facts, N, N, CELL, ORIGIN))
    mg = g.get("masks", {})
    if (mg.get("width"), mg.get("height"), mg.get("studsPerPixel")) != (MASK_N, MASK_N, 2.0 * CELL):
        raise PackError("Map1_Terrain.json mask grid changed: %r" % (mg,))
    if "value / 32" not in g.get("heightEncoding", "") or "value / 32" not in g.get("waterLevelEncoding", ""):
        raise PackError("Map1_Terrain.json no longer says heights and water levels are value / 32")

    # the legends: the terrain writer and the layout hard-code these ids
    regions = t.get("regions", {})
    got = [regions.get(str(i + 1)) for i in range(len(REGIONS))]
    if got != REGIONS or len(regions) != len(REGIONS):
        raise PackError("the region legend changed: %r (the contract's is %r)" % (regions, REGIONS))
    slots = t.get("materialSlots", {})
    got = [slots.get(str(i + 1), {}).get("base") for i in range(len(SLOT_BASES))]
    if got != SLOT_BASES or len(slots) != len(SLOT_BASES):
        raise PackError("the material legend changed: bases %r (the contract's are %r)" % (got, SLOT_BASES))
    for nm, arr, top in (("Material", ex["material"], len(SLOT_BASES)), ("Region", ex["region"], len(REGIONS))):
        lo, hi = int(arr.min()), int(arr.max())
        if lo < 1 or hi > top:
            raise PackError("Map1_%s.png holds ids %d..%d; the legend has 1..%d" % (nm, lo, hi, top))

    # heights: nothing at zero, and the two levels the game's start depends on
    h = ex["height"]
    if int(h.min()) == 0:
        raise PackError("Map1_Height.png has cells at 0: holes in the export")
    plaza = t.get("plaza", {})
    if abs(plaza.get("knollY", -1) - KNOLL_Y) > 1e-6 or abs(plaza.get("plinthRingY", -1) - RING_Y) > 1e-6:
        raise PackError("Map1_Terrain.json plaza says knoll %r and ring %r; the contract says %r and %r" % (
            plaza.get("knollY"), plaza.get("plinthRingY"), KNOLL_Y, RING_Y))
    c = ORIGIN + CELL * (np.arange(N) + 0.5)
    r = np.hypot(c[None, :], c[:, None])
    hs = h.astype(np.float64) / UNIT
    knoll = hs[r < 48.0]
    if np.abs(knoll - KNOLL_Y).max() > 0.25:
        raise PackError("the knoll (r < 48) is y %.2f..%.2f, not %.1f" % (knoll.min(), knoll.max(), KNOLL_Y))
    ring = hs[(r > 148.0) & (r < 152.0)]
    if np.abs(ring - RING_Y).max() > 0.3:
        raise PackError("the plinth ring (r 148..152) is y %.2f..%.2f, not %.1f" % (ring.min(), ring.max(), RING_Y))
    ex["heart"] = {"knoll": [float(knoll.min()), float(knoll.max())], "ring": [float(ring.min()), float(ring.max())]}

    # water: the mask and the levels describe the same cells
    wet_mask = ex["waterMask"] > 0
    wet_level = ex["waterLevel"] > 0
    if (wet_mask != wet_level).any():
        raise PackError("Map1_WaterMask.png and Map1_WaterLevel.png disagree on %d cells" % int((wet_mask != wet_level).sum()))
    if set(np.unique(ex["waterMask"]).tolist()) - {0, 255}:
        raise PackError("Map1_WaterMask.png holds values other than 0 and 255")

    # the 48 plinths stand on the ring, on the ground the Height grid says
    plinths = [it for it in ex["layout"].get("items", []) if it.get("asset") == "M1_Plinth"]
    if len(plinths) != PLINTHS:
        raise PackError("Map1_Layout.json places %d plinths, not %d" % (len(plinths), PLINTHS))
    worst = 0.0
    for it in plinths:
        x, y, z = it["position"]
        if abs(math.hypot(x, z) - PLINTH_RADIUS) > 0.05:
            raise PackError("plinth %r is not on radius %.0f" % (it.get("index"), PLINTH_RADIUS))
        worst = max(worst, abs(bilinear(hs, x, z) - y))
    if worst > 0.1:
        raise PackError("a plinth's y differs from the height grid by %.3f studs" % worst)
    ex["heart"]["plinthGroundError"] = worst
    return ex


def bilinear(grid, x, z):
    """Bilinear sample of a full-resolution grid (values at cell centres), clamped at the edge."""
    fx = min(max((x - ORIGIN) / CELL - 0.5, 0.0), N - 1.0)
    fz = min(max((z - ORIGIN) / CELL - 0.5, 0.0), N - 1.0)
    i = min(int(math.floor(fx)), N - 2)
    j = min(int(math.floor(fz)), N - 2)
    tx, tz = fx - i, fz - j
    return ((grid[j, i] * (1 - tx) + grid[j, i + 1] * tx) * (1 - tz)
            + (grid[j + 1, i] * (1 - tx) + grid[j + 1, i + 1] * tx) * tz)


# ----------------------------------------------------------------------------------------------------------------------
# The water
# ----------------------------------------------------------------------------------------------------------------------
def shifted(a, dr, dc, fill=0):
    """a's neighbour grid: out[r, c] = a[r + dr, c + dc], `fill` beyond the edge."""
    out = np.full_like(a, fill)
    r0, r1 = max(0, -dr), a.shape[0] - max(0, dr)
    c0, c1 = max(0, -dc), a.shape[1] - max(0, dc)
    out[r0:r1, c0:c1] = a[r0 + dr:r1 + dr, c0 + dc:c1 + dc]
    return out


def count_faults(H, W, nbs):
    """The three faults, counted the way the worldgen report counted them (pairs), for one neighbourhood."""
    wet = W > 0
    frac = W % VOX
    bad_level = int((wet & ((frac < LEVEL_MIN) | (frac > LEVEL_MAX))).sum())
    step_pairs = 0
    leak_pairs = 0
    leak_cells = np.zeros(W.shape, dtype=bool)
    worst_leak = 0
    for dr, dc in nbs:
        nw = shifted(W, dr, dc)
        nh = shifted(H, dr, dc, fill=1 << 30)
        step_pairs += int((wet & (nw > 0) & (nw != W)).sum())
        leak = wet & (nw == 0) & (nh < W)
        leak_pairs += int(leak.sum())
        if leak.any():
            worst_leak = max(worst_leak, int((W - nh)[leak].max()))
            leak_cells |= shifted(leak, -dr, -dc, fill=False)
    return {
        "badLevelCells": bad_level,
        "stepPairs": step_pairs // 2,  # every pair was seen from both sides
        "leakPairs": leak_pairs,
        "leakCells": int(leak_cells.sum()),
        "worstLeak": studs(worst_leak),
    }


def level_table(H, W):
    rows = []
    c = ORIGIN + CELL * (np.arange(N) + 0.5)
    r = np.hypot(c[None, :], c[:, None])
    for lv in np.unique(W[W > 0]).tolist():
        m = W == lv
        depth = (lv - H[m]) / float(UNIT)
        rows.append({"level": studs(lv), "raw": int(lv), "intoLayer": studs(lv % VOX), "cells": int(m.sum()),
                     "depthMin": float(depth.min()), "depthMean": float(depth.mean()), "depthMax": float(depth.max()),
                     "rMin": float(r[m].min()), "rMax": float(r[m].max())})
    return rows


def components(cells):
    """8-connected groups of a set of (row, col) cells, each group sorted, groups in row-major order."""
    todo = set(cells)
    out = []
    for start in sorted(cells):
        if start not in todo:
            continue
        todo.discard(start)
        group, stack = [], [start]
        while stack:
            cur = stack.pop()
            group.append(cur)
            for dr, dc in NB8:
                nb = (cur[0] + dr, cur[1] + dc)
                if nb in todo:
                    todo.discard(nb)
                    stack.append(nb)
        out.append(sorted(group))
    return out


def narrow_pools(W):
    """The wet cells of pools with fewer than NARROW_POOL cells (a pool is an 8-connected group at one level)."""
    out = np.zeros(W.shape, dtype=bool)
    for lv in np.unique(W[W > 0]).tolist():
        cells = [(int(r), int(c)) for r, c in zip(*np.nonzero(W == lv))]
        for group in components(cells):
            if len(group) < NARROW_POOL:
                for cell in group:
                    out[cell] = True
    return out


def repair_water(H0, W0, margin=False):
    """Returns the repaired (heights, levels) and the list of repairs, one entry per changed cell. Neighbours are the
    8 cells round a cell, except where the text says "side".

    1. A wet cell whose level is at or under its ground has no water: it becomes dry.
    2. A wet cell whose level breaks the voxel rule (0.5 to 2 studs into its 4-stud layer) becomes dry ground if its
       pool is SMALL_POOL cells or fewer (the in-between cells of a cascade); a bigger pool stops the packer.
    M. Only with margin=True: every dry cell at the side of a narrow pool's water becomes wet at that pool's level,
       MARGIN_DEPTH deep, unless that would lower its ground by more than MARGIN_MAX_CUT. Terrain water in a channel
       2 or 3 cells wide is hidden by its banks; the margin cells take that loss, so the designed cells show
       (measured in Studio, see README).
    3. Where two wet cells with different levels touch, the higher one becomes a dry sill.
    4. Every cell dried by 2 or 3 is raised to SILL_RISE above the highest water still beside it.
    5. Every other dry cell beside water and lower than it is raised to that water's level: the least that seals it.
    Without the margin, only heights rise and only water is removed.
    """
    H = H0.astype(np.int64)
    W = W0.astype(np.int64)
    tags = {}  # (row, col) -> why the cell changed

    # 1. water with no depth
    flat = (W > 0) & (W <= H)
    for row, col in zip(*np.nonzero(flat)):
        tags[(int(row), int(col))] = "noDepth"
    W[flat] = 0

    # 2. levels that break the voxel rule
    dried = {}
    frac = W % VOX
    bad = (W > 0) & ((frac < LEVEL_MIN) | (frac > LEVEL_MAX))
    if bad.any():
        by_level = {}
        for row, col in zip(*np.nonzero(bad)):
            by_level.setdefault(int(W[row, col]), []).append((int(row), int(col)))
        for lv in sorted(by_level):
            for group in components(by_level[lv]):
                if len(group) > SMALL_POOL:
                    x, z = cell_xz(*group[0])
                    raise PackError(
                        "a pool of %d cells near (%.0f, %.0f) stands at %.4f, which is %.4f studs into its voxel layer; "
                        "the rule is 0.5 to 2. Fix the level in the generator (art/blender/map1_green_land.py)."
                        % (len(group), x, z, studs(lv), studs(lv % VOX)))
                for cell in group:
                    dried[cell] = "badLevel"
    Wk = W.copy()
    for (row, col) in dried:
        Wk[row, col] = 0

    # M. the margin of narrow pools
    margins = {}
    if margin:
        narrow = narrow_pools(Wk)
        level_beside = np.zeros(W.shape, dtype=np.int64)
        for dr, dc in NB4:
            level_beside = np.maximum(level_beside, shifted(np.where(narrow, Wk, 0), dr, dc))
        for row, col in zip(*np.nonzero((Wk == 0) & (level_beside > 0))):
            cell = (int(row), int(col))
            lv = int(level_beside[row, col])
            if cell not in dried and int(H[row, col]) - (lv - MARGIN_DEPTH) <= MARGIN_MAX_CUT:
                margins[cell] = lv
        for (row, col), lv in margins.items():
            Wk[row, col] = lv

    # 3. the higher cell of every pair of wet neighbours with different levels
    wet = Wk > 0
    higher = np.zeros(W.shape, dtype=bool)
    for dr, dc in NB8:
        nw = shifted(Wk, dr, dc)
        higher |= wet & (nw > 0) & (Wk > nw)
    for row, col in zip(*np.nonzero(higher)):
        cell = (int(row), int(col))
        dried[cell] = "sill"
        margins.pop(cell, None)  # a margin cell that would touch lower water stays dry: it is part of the sill

    # 4. the final water; dried cells become ground SILL_RISE above the highest water that still touches them
    W2 = Wk.copy()
    for (row, col) in dried:
        W2[row, col] = 0
    H2 = H.copy()
    for (row, col), lv in margins.items():
        H2[row, col] = min(int(H[row, col]), lv - MARGIN_DEPTH)
        tags[(row, col)] = "margin"
    holds, lower_water = {}, {}
    for (row, col) in sorted(dried):
        own = int(Wk[row, col]) if Wk[row, col] > 0 else int(W[row, col])
        beside = 0
        lower = 0
        for dr, dc in NB8:
            rr, cc = row + dr, col + dc
            if 0 <= rr < N and 0 <= cc < N and W2[rr, cc] > 0:
                beside = max(beside, int(W2[rr, cc]))
                if W2[rr, cc] < own:
                    lower = max(lower, int(W2[rr, cc]))
        if beside > 0:
            H2[row, col] = max(int(H[row, col]), beside + SILL_RISE)
        tags[(row, col)] = dried[(row, col)]
        holds[(row, col)] = beside
        lower_water[(row, col)] = lower

    # 5. banks: dry ground beside water and under it
    wet2 = W2 > 0
    need = np.zeros(W.shape, dtype=np.int64)
    for dr, dc in NB8:
        need = np.maximum(need, shifted(W2, dr, dc))
    low = (~wet2) & (need > H2)
    for row, col in zip(*np.nonzero(low)):
        cell = (int(row), int(col))
        tags.setdefault(cell, "bank")
        holds[cell] = int(need[row, col])
    H2[low] = need[low]

    if int(H2.max()) > 65535:
        raise PackError("a repaired height no longer fits 16 bits")

    # one entry per changed cell, from what actually changed
    H0i, W0i = H0.astype(np.int64), W0.astype(np.int64)
    repairs = []
    for row, col in zip(*np.nonzero((H2 != H0i) | (W2 != W0i))):
        cell = (int(row), int(col))
        if cell not in tags:
            raise PackError("cell %r changed without a reason: a bug in the packer" % (cell,))
        was_wet, is_wet = W0i[cell] > 0, W2[cell] > 0
        kind = tags[cell]
        if not was_wet and not is_wet and kind not in ("sill", "bank"):
            kind = "bank"
        repairs.append({"kind": kind, "row": cell[0], "col": cell[1],
                        "levelWas": int(W0i[cell]), "levelNow": int(W2[cell]),
                        "groundWas": int(H0i[cell]), "groundNow": int(H2[cell]),
                        "holds": holds.get(cell, 0), "lowerWater": lower_water.get(cell, 0)})
    order = {"noDepth": 0, "badLevel": 1, "margin": 2, "sill": 3, "bank": 4}
    repairs.sort(key=lambda rp: (order[rp["kind"]], rp["row"], rp["col"]))
    return H2, W2, repairs


def find_hollows(H, W):
    """Dry ground that lies under the level of the water beside it, behind the cells that hold that water, with no
    lower water to drain to. Rule 3 asks only for the cells that touch the water, so the packer leaves a hollow as it
    is and reports it: the pool is held there by a bank one cell wide. Returns one entry per hollow."""
    wet = W > 0
    out = []
    for lv in np.unique(W[wet]).tolist():
        pool = W == lv
        bank = np.zeros(W.shape, dtype=bool)
        for dr, dc in NB8:
            bank |= shifted(pool, dr, dc, fill=False)
        bank &= ~wet
        low = (~wet) & (H < lv)
        seed = np.zeros(W.shape, dtype=bool)
        drains = np.zeros(W.shape, dtype=bool)
        lower_water = wet & (W < lv)
        for dr, dc in NB8:
            seed |= shifted(bank, dr, dc, fill=False)
            drains |= shifted(lower_water, dr, dc, fill=False)
        seed &= low
        seen = np.zeros(W.shape, dtype=bool)
        seen_open = np.zeros(W.shape, dtype=bool)
        for start in zip(*np.nonzero(seed)):
            start = (int(start[0]), int(start[1]))
            if seen[start]:
                continue
            group, stack, is_open = [], [start], False
            seen[start] = True
            while stack and not is_open:
                cur = stack.pop()
                group.append(cur)
                if drains[cur]:
                    is_open = True  # ground that runs down to lower water is a slope, not a hollow
                for dr, dc in NB8:
                    nb = (cur[0] + dr, cur[1] + dc)
                    if not (0 <= nb[0] < N and 0 <= nb[1] < N) or not low[nb]:
                        continue
                    if seen_open[nb]:
                        is_open = True
                    elif not seen[nb]:
                        seen[nb] = True
                        stack.append(nb)
            if is_open:
                for cell in group + stack:
                    seen_open[cell] = True
                continue
            rows = [c[0] for c in group]
            cols = [c[1] for c in group]
            floor = min(int(H[c]) for c in group)
            x0, z0 = cell_xz(min(rows), min(cols))
            x1, z1 = cell_xz(max(rows), max(cols))
            out.append({"level": studs(lv), "cells": len(group), "xFrom": x0, "xTo": x1, "zFrom": z0, "zTo": z1,
                        "lowestGround": studs(floor), "deepest": studs(lv - floor)})
    return out


def assert_water(H, W, H0, W0, repairs, margin=False):
    """The three rules of Map1Build.md decision 5, on the repaired grids. Raises PackError on any breach."""
    wet = W > 0
    checks = []
    frac = W[wet] % VOX
    ok = bool(((frac >= LEVEL_MIN) & (frac <= LEVEL_MAX)).all())
    checks.append((ok, "every water level sits 0.5 to 2 studs into its 4-stud voxel layer (%d levels, %d wet cells)" % (
        len(np.unique(W[wet])), int(wet.sum()))))
    steps = 0
    leaks = 0
    for dr, dc in NB8:
        nw = shifted(W, dr, dc)
        nh = shifted(H, dr, dc, fill=1 << 30)
        steps += int((wet & (nw > 0) & (nw != W)).sum())
        leaks += int((wet & (nw == 0) & (nh < W)).sum())
    checks.append((steps == 0, "two neighbouring wet cells always have the same level, so a dry cell stands between any "
                               "two pools (8 neighbours; %d breaches)" % (steps // 2)))
    checks.append((leaks == 0, "no dry cell next to water is lower than that water's level (8 neighbours; %d breaches)" % leaks))
    checks.append((bool((W[wet] > H[wet]).all()), "every wet cell's level is above its ground"))
    # the repairs are the only differences; without the margin heights only rose and water was only removed
    changed_h = np.nonzero(H != H0)
    changed_w = np.nonzero(W != W0)
    listed_h = {(r["row"], r["col"]) for r in repairs if r["groundNow"] != r["groundWas"]}
    listed_w = {(r["row"], r["col"]) for r in repairs if r["levelNow"] != r["levelWas"]}
    ok = set(zip(changed_h[0].tolist(), changed_h[1].tolist())) == listed_h
    ok = ok and set(zip(changed_w[0].tolist(), changed_w[1].tolist())) == listed_w
    ok = ok and len({(r["row"], r["col"]) for r in repairs}) == len(repairs)
    margin_cells = {(r["row"], r["col"]) for r in repairs if r["kind"] == "margin"}
    lowered = set(zip(*[a.tolist() for a in np.nonzero(H < H0)]))
    added = set(zip(*[a.tolist() for a in np.nonzero((W0 == 0) & (W > 0))]))
    raised = int((H > H0).sum())
    dried = int(((W0 > 0) & (W == 0)).sum())
    ok = ok and lowered <= margin_cells and added <= margin_cells and bool((W[W0 > 0] == W0[W0 > 0])[W[W0 > 0] > 0].all())
    if margin:
        deepest = max([r["groundWas"] - r["groundNow"] for r in repairs if r["kind"] == "margin"] or [0])
        checks.append((ok, "the log lists every changed cell: %d margin cells made wet beside narrow water (the only water "
                           "added; %d of them lowered, by %.2f studs at most, and nothing else was lowered), %d heights "
                           "raised, %d cells dried" % (len(margin_cells), len(lowered), studs(deepest), raised, dried)))
    else:
        ok = ok and not margin_cells
        checks.append((ok, "the log lists every changed cell: %d heights raised, %d cells dried; nothing was lowered and "
                           "no water was added" % (raised, dried)))
    nearest = min([math.hypot(*cell_xz(r["row"], r["col"])) for r in repairs] or [float("inf")])
    checks.append((nearest >= HEART_CLEAR, "no repair is within %d studs of the centre, so the knoll, the plinth ring and "
                                           "the turf are as exported%s" % (
                                               HEART_CLEAR, "" if not repairs else " (the nearest is at r %.0f)" % nearest)))
    for ok, text in checks:
        if not ok:
            raise PackError("water check failed: " + text)
    return [text for _ok, text in checks]


# ----------------------------------------------------------------------------------------------------------------------
# Map1Regions.lua
# ----------------------------------------------------------------------------------------------------------------------
def region_grid(region, biome_json, notes):
    """240 x 240 region ids from the full raster, checked against Map1_BiomeGrid16.json."""
    margin = (N - REGION_N * (REGION_CELL // CELL)) // 2
    k = REGION_CELL // CELL
    inner = region[margin:margin + REGION_N * k, margin:margin + REGION_N * k]
    grid = np.ascontiguousarray(inner[REGION_SAMPLE::k, REGION_SAMPLE::k])
    outer = region.copy()
    outer[margin:margin + REGION_N * k, margin:margin + REGION_N * k] = len(REGIONS)
    if int(outer.min()) != len(REGIONS):
        raise PackError("the region raster has a region other than Outside beyond the 240 x 240 grid")
    if biome_json is not None:
        facts = (biome_json.get("cell"), biome_json.get("n"), tuple(biome_json.get("origin", ())))
        if facts != (REGION_CELL, REGION_N, (REGION_ORIGIN, REGION_ORIGIN)):
            raise PackError("Map1_BiomeGrid16.json's grid changed: %r" % (facts,))
        theirs = np.array(biome_json["data"], dtype=np.uint8)
        if theirs.shape != grid.shape or (theirs != grid).any():
            raise PackError("Map1_BiomeGrid16.json is not Map1_Region.png sampled every 16 studs (%d cells differ)" % int(
                (theirs != grid).sum() if theirs.shape == grid.shape else -1))
    else:
        notes.append("Map1_BiomeGrid16.json is not in the export folder; the region grid was not cross-checked")
    return grid


def height_nodes(H, step):
    """Ground height at nodes `step` studs apart from ORIGIN: the mean of the four cells that meet at each node."""
    if (N * CELL) % step or step % (2 * CELL):
        raise PackError("--height-cell must divide %d and be a multiple of %d" % (N * CELL, 2 * CELL))
    n = N * CELL // step + 1
    k = step // CELL
    hs = np.pad(H.astype(np.float64) / UNIT, 1, mode="edge")  # hs[r + 1, c + 1] = H[r, c]
    idx = np.arange(n) * k  # node i sits between cells i*k - 1 and i*k
    a = hs[np.ix_(idx, idx)]
    b = hs[np.ix_(idx, idx + 1)]
    c = hs[np.ix_(idx + 1, idx)]
    d = hs[np.ix_(idx + 1, idx + 1)]
    return (a + b + c + d) / 4.0


def encode_heights(nodes):
    base = math.floor(float(nodes.min()))
    top = HEIGHT_BASE_N * HEIGHT_BASE_N - 1
    step = math.ceil((float(nodes.max()) - base) / top / 0.05 - 1e-9) * 0.05
    step = round(max(step, 0.05), 2)
    q = np.rint((nodes - base) / step).astype(np.int64)
    if int(q.min()) < 0 or int(q.max()) > top:
        raise PackError("height nodes do not fit two base-%d digits" % HEIGHT_BASE_N)
    rows = []
    for j in range(q.shape[0]):
        hi = q[j] // HEIGHT_BASE_N + HEIGHT_FIRST
        lo = q[j] % HEIGHT_BASE_N + HEIGHT_FIRST
        pair = np.empty(q.shape[1] * 2, dtype=np.uint8)
        pair[0::2] = hi
        pair[1::2] = lo
        rows.append(pair.tobytes().decode("ascii"))
    return base, step, rows, base + step * q


def coarse_height_at(nodes, step, x, z):
    """What Map1Regions.heightAt computes (vectorised), for the packer's own accuracy figures."""
    last = nodes.shape[0] - 1
    fx = np.clip((x - ORIGIN) / step, 0, last)
    fz = np.clip((z - ORIGIN) / step, 0, last)
    i = np.minimum(np.floor(fx).astype(int), last - 1)
    j = np.minimum(np.floor(fz).astype(int), last - 1)
    tx, tz = fx - i, fz - j
    return ((nodes[j, i] * (1 - tx) + nodes[j, i + 1] * tx) * (1 - tz)
            + (nodes[j + 1, i] * (1 - tx) + nodes[j + 1, i + 1] * tx) * tz)


def full_height_at(H, x, z):
    hs = H.astype(np.float64) / UNIT
    fx = np.clip((x - ORIGIN) / CELL - 0.5, 0, N - 1)
    fz = np.clip((z - ORIGIN) / CELL - 0.5, 0, N - 1)
    i = np.minimum(np.floor(fx).astype(int), N - 2)
    j = np.minimum(np.floor(fz).astype(int), N - 2)
    tx, tz = fx - i, fz - j
    return ((hs[j, i] * (1 - tx) + hs[j, i + 1] * tx) * (1 - tz)
            + (hs[j + 1, i] * (1 - tx) + hs[j + 1, i + 1] * tx) * tz)


def height_accuracy(H, decoded, step):
    """Error of the coarse grid against the full one at 200,000 seeded points inside the play radius."""
    rng = np.random.default_rng(20261115)
    m = 200000
    r = 1800.0 * np.sqrt(rng.random(m))
    th = rng.random(m) * 2 * math.pi
    x, z = r * np.cos(th), r * np.sin(th)
    err = np.abs(coarse_height_at(decoded, step, x, z) - full_height_at(H, x, z))
    p50, p95, p99 = np.percentile(err, [50, 95, 99])
    return {"points": m, "mean": float(err.mean()), "p50": float(p50), "p95": float(p95), "p99": float(p99),
            "max": float(err.max()), "within6": float((err <= 6.0).mean())}


MODULE_TEMPLATE = '''--[[
	Map1Regions - Map 1 (the Green Land): which region a point is in, and a coarse ground height. Server and clients.
	GENERATED by tools/map1/pack.py from the Blender exports: do not edit by hand, run the packer again.
	It asks for no service and never yields, so ArenaLayout can require it anywhere.

	  Map1Regions.regionAt(x, z) -> number    region id 1..@REGIONS@; @REGIONS@ (Outside) beyond the grid
	  Map1Regions.nameAt(x, z) -> string      the region's name
	  Map1Regions.Names[id] -> string         @NAMES@
	  Map1Regions.Ids[name] -> number
	  Map1Regions.heightAt(x, z) -> number    ground height in studs (under water: the bed), bilinear between nodes
	                                          @HCELL@ studs apart, clamped to the grid's edge beyond +-@HEDGE@

	heightAt is the fallback for places where the terrain is not loaded. Against the full 4-stud grid inside radius
	1,800 it is @P50@ studs out at the median, @P95@ at the 95th percentile and within 6 studs on @WITHIN6@% of points;
	on cliffs (the Edge, the peak, the crags) it can be tens of studs out, as any coarse grid is.

	Region grid: @RN@ x @RN@ cells of @RCELL@ studs from (@RORIGIN@, @RORIGIN@). Row 1 is the north row (lowest z). One
	character per cell: the id + 48. It is Map1_Region.png sampled every @RCELL@ studs (Map1_BiomeGrid16.json).
	Height grid: @HN@ x @HN@ nodes @HCELL@ studs apart from (@HORIGIN@, @HORIGIN@). Row 1 is the north row. Two characters
	per node, base @HBASEN@ from "#": height = @HBASE@ + @HSTEP@ * ((c1 - 35) * @HBASEN@ + (c2 - 35)). It is the data pack's
	Height blob (the Blender heights after the water repairs) averaged over the four cells that meet at each node.
]]
local Map1Regions = {}

Map1Regions.Version = 1
Map1Regions.Map = "GreenLand"
-- fingerprints (FNV-1a) of the map1_data blobs this module was made from
Map1Regions.Pack = { Height = "@FNVH@", Region = "@FNVR@" }

Map1Regions.Names = { @NAMELIST@ }
Map1Regions.Ids = {}
for id, name in ipairs(Map1Regions.Names) do
	Map1Regions.Ids[name] = id
end
Map1Regions.Outside = @REGIONS@

Map1Regions.RegionCell = @RCELL@
Map1Regions.RegionSize = @RN@ -- cells a side
Map1Regions.RegionOrigin = @RORIGIN@ -- x and z of the north-west corner
Map1Regions.HeightCell = @HCELL@
Map1Regions.HeightSize = @HN@ -- nodes a side
Map1Regions.HeightOrigin = @HORIGIN@ -- x and z of the north-west node
Map1Regions.HeightBase = @HBASE@
Map1Regions.HeightStep = @HSTEP@

local REGION = {
@REGIONROWS@
}

local HEIGHT = {
@HEIGHTROWS@
}

local R_CELL, R_SIZE, R_ORIGIN = @RCELL@, @RN@, @RORIGIN@
local H_CELL, H_LAST, H_ORIGIN = @HCELL@, @HLAST@, @HORIGIN@
local H_BASE, H_STEP, H_DIGIT = @HBASE@, @HSTEP@, @HBASEN@
local H_ZERO = 35 * (H_DIGIT + 1) -- what two "#" characters add
local OUTSIDE = @REGIONS@

local floor = math.floor
local byte = string.byte

function Map1Regions.regionAt(x: number, z: number): number
	local col = floor((x - R_ORIGIN) / R_CELL)
	local row = floor((z - R_ORIGIN) / R_CELL)
	-- written so that a NaN falls through to Outside
	if col >= 0 and col < R_SIZE and row >= 0 and row < R_SIZE then
		return byte(REGION[row + 1], col + 1) - 48
	end
	return OUTSIDE
end

function Map1Regions.nameAt(x: number, z: number): string
	return Map1Regions.Names[Map1Regions.regionAt(x, z)]
end

function Map1Regions.heightAt(x: number, z: number): number
	local fx = (x - H_ORIGIN) / H_CELL
	local fz = (z - H_ORIGIN) / H_CELL
	-- clamp to the grid; "not (f > 0)" also catches a NaN
	if not (fx > 0) then
		fx = 0
	elseif fx > H_LAST then
		fx = H_LAST
	end
	if not (fz > 0) then
		fz = 0
	elseif fz > H_LAST then
		fz = H_LAST
	end
	local i = floor(fx)
	if i > H_LAST - 1 then
		i = H_LAST - 1
	end
	local j = floor(fz)
	if j > H_LAST - 1 then
		j = H_LAST - 1
	end
	local tx, tz = fx - i, fz - j
	local p = i * 2 + 1
	local a1, a2, b1, b2 = byte(HEIGHT[j + 1], p, p + 3)
	local c1, c2, d1, d2 = byte(HEIGHT[j + 2], p, p + 3)
	local north = (a1 * H_DIGIT + a2) * (1 - tx) + (b1 * H_DIGIT + b2) * tx
	local south = (c1 * H_DIGIT + c2) * (1 - tx) + (d1 * H_DIGIT + d2) * tx
	return H_BASE + H_STEP * (north * (1 - tz) + south * tz - H_ZERO)
end

return Map1Regions
'''


def num(v):
    """A number as Lua source: no trailing zeros, no exponent."""
    if float(v) == int(v):
        return "%d" % int(v)
    return ("%.6f" % v).rstrip("0").rstrip(".")


def build_module(H, region, biome_json, step, fnv_height, fnv_region, notes):
    grid = region_grid(region, biome_json, notes)
    region_rows = [bytes((grid[j] + 48).tolist()).decode("ascii") for j in range(REGION_N)]
    nodes = height_nodes(H, step)
    base, hstep, height_rows, decoded = encode_heights(nodes)
    acc = height_accuracy(H, decoded, step)
    for rows in (region_rows, height_rows):
        for row in rows:
            if '"' in row or BS in row or any(ord(ch) < 35 or ord(ch) > 126 for ch in row):
                raise PackError("a grid row holds a character that is not safe in a Lua string")
    subs = {
        "REGIONS": str(len(REGIONS)),
        "NAMES": ", ".join(REGIONS),
        "NAMELIST": ", ".join('"%s"' % nm for nm in REGIONS),
        "RN": str(REGION_N), "RCELL": str(REGION_CELL), "RORIGIN": str(REGION_ORIGIN),
        "HN": str(nodes.shape[0]), "HLAST": str(nodes.shape[0] - 1), "HCELL": str(step), "HORIGIN": str(ORIGIN),
        "HEDGE": str(-ORIGIN),
        "HBASE": num(base), "HSTEP": num(hstep), "HBASEN": str(HEIGHT_BASE_N),
        "P50": "%.1f" % acc["p50"], "P95": "%.1f" % acc["p95"], "WITHIN6": "%.1f" % (100 * acc["within6"]),
        "FNVH": fnv_height, "FNVR": fnv_region,
        "REGIONROWS": "\n".join('\t"%s",' % row for row in region_rows),
        "HEIGHTROWS": "\n".join('\t"%s",' % row for row in height_rows),
    }
    # one pass over the template, so that an "@" inside a height row is never taken for a field
    text = re.sub(r"@([A-Z0-9]+)@", lambda m: subs[m.group(1)], MODULE_TEMPLATE)
    data = text.encode("utf-8")
    if b"\r" in data:
        raise PackError("the module has CR line endings")
    if len(data) >= MODULE_LIMIT:
        raise PackError("Map1Regions.lua would be %d bytes; the limit is %d" % (len(data), MODULE_LIMIT))

    # read the rows back the way the Lua does, and compare with the arrays they came from
    back = np.array([[ord(ch) - 48 for ch in row] for row in region_rows], dtype=np.uint8)
    if (back != grid).any():
        raise PackError("the region rows do not read back")
    q = np.array([[(ord(row[2 * i]) - 35) * HEIGHT_BASE_N + (ord(row[2 * i + 1]) - 35) for i in range(nodes.shape[1])]
                  for row in height_rows], dtype=np.float64)
    if np.abs(base + hstep * q - nodes).max() > hstep / 2 + 1e-6:
        raise PackError("the height rows do not read back")
    info = {"bytes": len(data), "fnv": fnv(data), "regionGrid": [REGION_N, REGION_N], "regionCell": REGION_CELL,
            "heightNodes": [int(nodes.shape[0]), int(nodes.shape[1])], "heightCell": step, "heightBase": base,
            "heightStep": hstep, "accuracyInsideR1800": acc}
    return data, info, grid, decoded


# ----------------------------------------------------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------------------------------------------------
def make_blobs(ex, H2, W2):
    """[(name, file name, bytes, description)] in the contract's order."""
    blobs = [
        ("Height", "Height.bin", H2.astype("<u2").tobytes(), "%d x %d uint16 LE, y = value / 32 (water repairs applied)" % (N, N)),
        ("Material", "Material.bin", ex["material"].astype(np.uint8).tobytes(), "%d x %d uint8, slot ids 1..10 of Terrain.materialSlots" % (N, N)),
        ("Region", "Region.bin", ex["region"].astype(np.uint8).tobytes(), "%d x %d uint8, region ids 1..10 of Terrain.regions" % (N, N)),
        ("WaterLevel", "WaterLevel.bin", W2.astype("<u2").tobytes(), "%d x %d uint16 LE, y = value / 32, 0 = dry (repaired)" % (N, N)),
    ]
    for nm in MASKS:
        blobs.append(("Mask_" + nm, "Mask_%s.bin" % nm, ex["masks"][nm].astype(np.uint8).tobytes(),
                      "%d x %d uint8, density 0..255, 8-stud cells" % (MASK_N, MASK_N)))
    blobs.append(("Terrain", "Terrain.json", ex["terrainRaw"], "Map1_Terrain.json as text (LF line endings, like every text blob)"))
    blobs.append(("Layout", "Layout.json", ex["layoutRaw"], "Map1_Layout.json as text"))
    for nm in MANIFESTS:
        if nm in ex["manifests"]:
            blobs.append(("Manifest_" + nm, "Manifest_%s.json" % nm, ex["manifests"][nm]["data"], ex["manifests"][nm]["content"]))
    expect = {"Height": N * N * 2, "Material": N * N, "Region": N * N, "WaterLevel": N * N * 2}
    for nm in MASKS:
        expect["Mask_" + nm] = MASK_N * MASK_N
    for name, _f, data, _d in blobs:
        if name in expect and len(data) != expect[name]:
            raise PackError("blob %s is %d bytes, not %d" % (name, len(data), expect[name]))
    return blobs


def write_log(path, ex, before, after, levels_before, levels_after, repairs, checks, hollows, margin=False):
    out = []
    w = out.append
    w("# Map 1: what the packer changed in the water")
    w("")
    w("Written by `tools/map1/pack.py`. Do not edit: run the packer again. Heights and levels are in studs; a cell is one")
    w("4-stud voxel column, `x = -2752 + 4 * (col + 0.5)`, `z = -2752 + 4 * (row + 0.5)`, row 0 in the north.")
    w("")
    w("Read from: `Map1_Height.png` (sha256 %s...) and `Map1_WaterLevel.png` (sha256 %s...)." % (
        ex["sources"]["Map1_Height.png"]["sha256"][:16], ex["sources"]["Map1_WaterLevel.png"]["sha256"][:16]))
    w("")
    w("## The rules (Map1Build.md, decision 5)")
    w("")
    w("1. Every water level sits 0.5 to 2 studs into its 4-stud voxel layer.")
    w("2. Two neighbouring wet cells have the same level, or a dry sill cell stands between them.")
    w("3. No dry cell next to water is lower than that water's level.")
    w("")
    w("\"Neighbouring\" means the 8 cells round a cell, diagonals included: the stricter reading. A workbench test on")
    w("15 November 2026 found no water face at a corner even when only the four side neighbours were sealed, so the")
    w("diagonals are a margin, not a need.")
    w("")
    w("## Faults in the export")
    w("")
    w("| Fault | Counted with 4 neighbours | Counted with 8 neighbours | The older export (worldgen report 4.5) |")
    w("|---|---|---|---|")
    w("| Wet cells whose level breaks rule 1 | %d | %d | 17 |" % (before[4]["badLevelCells"], before[8]["badLevelCells"]))
    w("| Pairs of wet neighbours with different levels | %d | %d | 41 |" % (before[4]["stepPairs"], before[8]["stepPairs"]))
    w("| Wet cell beside a lower dry cell: pairs (dry cells; worst drop) | %d (%d; %.2f) | %d (%d; %.2f) | 20 (worst 1.84) |" % (
        before[4]["leakPairs"], before[4]["leakCells"], before[4]["worstLeak"],
        before[8]["leakPairs"], before[8]["leakCells"], before[8]["worstLeak"]))
    w("")
    w("The 8-neighbour count of the third fault is large before the repairs because the cells beside a cascade touch")
    w("the upper pool at a corner. Most of them are settled by the sills and need no change of their own.")
    w("")
    w("### Water levels in the export")
    w("")
    w("| Level | Into its voxel layer | Cells | Depth (least, mean, most) | Radius |")
    w("|---|---|---|---|---|")
    for lv in levels_before:
        w("| %.4f | %.4f | %d | %.2f, %.2f, %.2f | %.0f to %.0f |" % (
            lv["level"], lv["intoLayer"], lv["cells"], lv["depthMin"], lv["depthMean"], lv["depthMax"], lv["rMin"], lv["rMax"]))
    w("")
    kinds = {}
    for rp in repairs:
        kinds.setdefault(rp["kind"], []).append(rp)
    raised = [rp for rp in repairs if rp["groundNow"] > rp["groundWas"]]
    lowered = [rp for rp in repairs if rp["groundNow"] < rp["groundWas"]]
    dried = [rp for rp in repairs if rp["levelWas"] > 0 and rp["levelNow"] == 0]
    margins = kinds.get("margin", [])
    w("## Repairs: %d cells" % len(repairs))
    w("")
    if margins:
        w("%d cells beside narrow water were made wet (the margin: see below), %d of them lowered, by at most %.2f studs." % (
            len(margins), len(lowered), max([studs(rp["groundWas"] - rp["groundNow"]) for rp in lowered] or [0.0])))
        w("%d cells were dried and %d heights were raised (the largest rise is %.2f studs). Nothing else was lowered, no" % (
            len(dried), len(raised), max([studs(rp["groundNow"] - rp["groundWas"]) for rp in raised] or [0.0])))
        w("other water was added, and no material or region id was changed: a sill keeps the slot its cell had.")
    else:
        w("%d cells were dried and %d heights were raised (the largest rise is %.2f studs). Nothing was lowered, no water was" % (
            len(dried), len(raised), max([studs(rp["groundNow"] - rp["groundWas"]) for rp in raised] or [0.0])))
        w("added, and no material or region id was changed: a sill keeps the slot its cell had (the stream bed).")
    w("")
    if kinds.get("noDepth"):
        w("### Water with no depth, made dry: %d cells" % len(kinds["noDepth"]))
        w("")
        w("| Row | Col | x | z | Level was | Ground |")
        w("|---|---|---|---|---|---|")
        for rp in kinds["noDepth"]:
            x, z = cell_xz(rp["row"], rp["col"])
            w("| %d | %d | %.0f | %.0f | %.4f | %.4f |" % (rp["row"], rp["col"], x, z, studs(rp["levelWas"]), studs(rp["groundWas"])))
        w("")
    if margin:
        w("### The margin: %d cells" % len(margins))
        w("")
        w("Terrain water in a channel 2 or 3 cells wide is partly hidden by its own banks: the bank's surface leans over")
        w("the first wet cell on each side. Measured in Studio with the game's voxel rules, a channel 2 cells wide on a")
        w("diagonal shows no water at all when its level sits 1 stud or less into its voxel layer, and one 3 cells wide")
        w("shows about half. With one more wet cell on each side, 86 to 100% of the designed water shows. So every dry")
        w("cell at the side of a narrow pool (fewer than {:,} cells: the stream's pools, not the lake) becomes wet at that".format(NARROW_POOL))
        w("pool's level, %.2f studs deep: too shallow to be taken for a drinking spot, deep enough to be a wet column." % studs(MARGIN_DEPTH))
        w("A bank more than %.2f studs above the water is left alone (no cut deeper than %d studs), and a margin cell that" % (
            studs(MARGIN_MAX_CUT - MARGIN_DEPTH), MARGIN_MAX_CUT // UNIT))
        w("would touch lower water stays dry and becomes part of the sill instead.")
        w("")
        w("| Row | Col | x | z | Level now | Ground was | Ground now | Lowered by |")
        w("|---|---|---|---|---|---|---|---|")
        for rp in margins:
            x, z = cell_xz(rp["row"], rp["col"])
            w("| %d | %d | %.0f | %.0f | %.4f | %.4f | %.4f | %.4f |" % (
                rp["row"], rp["col"], x, z, studs(rp["levelNow"]), studs(rp["groundWas"]), studs(rp["groundNow"]),
                studs(rp["groundWas"] - rp["groundNow"])))
        w("")
    for kind, title, why in (
        ("badLevel", "Cells whose level broke rule 1, made dry ground",
         ["A pool of %d cells or fewer at a level outside the rule is an in-between cell of a cascade. It becomes dry" % SMALL_POOL,
          "ground, %.4f studs above the highest water still beside it." % studs(SILL_RISE)]),
        ("sill", "Sills",
         ["Where two pools touched, the higher pool's edge cell becomes a dry sill %.4f studs above that pool's level" % studs(SILL_RISE),
          "(TerrainGen's sill rule), so that ground holds the upper pool. The lower pool is untouched."]
         + (["A row with \"dry\" under \"Level was\" is a bank cell at the end of a sill: with the margin it would have joined two",
             "pools, so it is raised with the sill."] if margin else [])),
    ):
        rows = kinds.get(kind, [])
        w("### %s: %d cells" % (title, len(rows)))
        w("")
        if not rows:
            w("None.")
            w("")
            continue
        for line in why:
            w(line)
        w("")
        w("| Row | Col | x | z | Level was | Ground was | Ground now | Raised by | Holds water at | Lower water beside |")
        w("|---|---|---|---|---|---|---|---|---|---|")
        for rp in rows:
            x, z = cell_xz(rp["row"], rp["col"])
            w("| %d | %d | %.0f | %.0f | %s | %.4f | %.4f | %.4f | %s | %s |" % (
                rp["row"], rp["col"], x, z, "%.4f" % studs(rp["levelWas"]) if rp["levelWas"] else "dry",
                studs(rp["groundWas"]), studs(rp["groundNow"]), studs(rp["groundNow"] - rp["groundWas"]),
                "%.4f" % studs(rp["holds"]) if rp["holds"] else "none",
                "%.4f" % studs(rp["lowerWater"]) if rp["lowerWater"] else "none"))
        w("")
    rows = kinds.get("bank", [])
    w("### Banks: %d cells" % len(rows))
    w("")
    if rows:
        w("Dry ground beside water and lower than it, raised to exactly that water's level: the least that satisfies rule 3.")
        w("")
        w("| Row | Col | x | z | Ground was | Ground now | Raised by |")
        w("|---|---|---|---|---|---|---|")
        for rp in rows:
            x, z = cell_xz(rp["row"], rp["col"])
            w("| %d | %d | %.0f | %.0f | %.4f | %.4f | %.4f |" % (
                rp["row"], rp["col"], x, z, studs(rp["groundWas"]), studs(rp["groundNow"]), studs(rp["groundNow"] - rp["groundWas"])))
        w("")
    else:
        w("None.")
        w("")
    w("## After the repairs")
    w("")
    w("| Level | Into its voxel layer | Cells | Depth (least, mean, most) |")
    w("|---|---|---|---|")
    for lv in levels_after:
        w("| %.4f | %.4f | %d | %.2f, %.2f, %.2f |" % (
            lv["level"], lv["intoLayer"], lv["cells"], lv["depthMin"], lv["depthMean"], lv["depthMax"]))
    w("")
    w("Faults left, counted with 8 neighbours: %d bad levels, %d pairs with different levels, %d leaks." % (
        after[8]["badLevelCells"], after[8]["stepPairs"], after[8]["leakPairs"]))
    w("")
    w("The packer asserted, and stops without writing a pack if any of these fails:")
    w("")
    for text in checks:
        w("- " + text)
    w("")
    w("## Hollows the packer left alone: %d" % len(hollows))
    w("")
    w("A hollow is dry ground lower than the water beside it, behind the cells that hold that water, with no lower water")
    w("to run to. Rule 3 is met (the cells that touch the water were raised), so the packer changes nothing more: the")
    w("water is held by a bank one cell wide, and the ground behind it stays under the water's level. To be rid of one,")
    w("change the generator: flood the hollow or lift its floor.")
    w("")
    if hollows:
        w("| Water level | Cells | x | z | Lowest ground | Deepest under the water |")
        w("|---|---|---|---|---|---|")
        for hw in hollows:
            w("| %.4f | %d | %.0f to %.0f | %.0f to %.0f | %.4f | %.4f |" % (
                hw["level"], hw["cells"], hw["xFrom"], hw["xTo"], hw["zFrom"], hw["zTo"], hw["lowestGround"], hw["deepest"]))
    else:
        w("None.")
    w("")
    write_bytes(path, "\n".join(out).encode("utf-8"))


def ready_text(pack_name, blob_rows, manifest, pack_path):
    out = []
    w = out.append
    w("map1_data: Map 1's data pack (docs/design/Map1Build.md 3.3)")
    w("")
    history = manifest.get("history", [])
    if history:
        newest = history[-1]
        w("BUILD %d, made %s." % (newest["build"], newest["date"]))
        if newest["build"] > 1:
            w("Changed since build %d:" % (newest["build"] - 1))
            for line in newest["changes"]:
                w("  - " + line)
            for entry in reversed(history[:-1]):
                w("Build %d (%s): %s" % (entry["build"], entry["date"], "; ".join(entry["changes"])))
        w("")
    w("Pack name: %s" % pack_name)
    if pack_path:
        w("Pack file: %s" % pack_path)
    w("Open it in Studio (Edit):")
    w('  local pack = require(game.ServerStorage.Dev.StudioSync:Clone()).open("%s")' % pack_name)
    w('  local height = pack:blob("Height")   -- a buffer; pack:info("Height") gives { bytes, fnv }')
    w("  pack:close()")
    w("")
    w("Grids are row-major, row 0 in the north (z = -2752), little-endian. Cell (row, col) of a 1376 grid is the voxel")
    w("column at x = -2752 + 4 * (col + 0.5), z = -2752 + 4 * (row + 0.5); a mask cell is 8 studs.")
    w("")
    w("%-20s %10s  %-8s  %s" % ("Blob", "Bytes", "FNV-1a", "Content"))
    for row in blob_rows:
        w("%-20s %10d  %-8s  %s" % (row["name"], row["bytes"], row["fnv"], row["content"]))
    w("")
    missing = [nm for nm in MANIFESTS if "Manifest_" + nm not in {r["name"] for r in blob_rows}]
    if missing:
        w("NOT in the pack yet: %s (the export folder has no such manifest; pack:info(name) returns nil)." % ", ".join(
            "Manifest_" + nm for nm in missing))
        w("")
    wr = manifest["water"]
    w("Water repairs: %d cells dried into sills, %d heights raised; every changed cell is in repair_log.md." % (
        wr["cellsDried"], wr["heightsRaised"]))
    if wr["margin"]:
        w("THE MARGIN IS ON: %d cells beside the stream's water are wet, %.2f deep (pack.py --margin; see the README)." % (
            wr["marginCells"], wr["marginDepth"]))
    else:
        w("The margin is off: the stream is as wide as Blender made it (pack.py --margin widens it by a cell a side).")
    w("Map1Regions.lua: %d bytes, fnv %s (made from Height %s and Region %s)." % (
        manifest["module"]["bytes"], manifest["module"]["fnv"], manifest["module"]["packHeight"], manifest["module"]["packRegion"]))
    w("")
    return "\n".join(out)


PROOF_TEMPLATE = '''-- Proof that Studio reads the pack "@PACK@" exactly. Generated by tools/map1/pack.py; run in Edit mode (execute_luau).
-- It checks every blob's size and FNV-1a against the packer's own figures and compares cells with the export files.
local Sync = require(game.ServerStorage.Dev.StudioSync:Clone())
local EXPECT = {
@EXPECT@
}
local HEIGHTS = { @HEIGHTS@ } -- row, col, value from Map1_Height.png (or the repair log), ...
local WATER = { @WATER@ } -- row, col, value from Map1_WaterLevel.png (or 0 where the log dried the cell), ...
local t0 = os.clock()
local pack = Sync.open("@PACK@")
local lines, bad = {}, 0
local names = pack:names()
if #names ~= #EXPECT then
	bad += 1
	table.insert(lines, string.format("BAD  the pack has %d blobs, the packer wrote %d", #names, #EXPECT))
end
local held = {}
for i, e in ipairs(EXPECT) do
	local info = pack:info(e[1])
	if not info then
		bad += 1
		table.insert(lines, "BAD  missing blob " .. e[1])
	else
		local b = pack:blob(e[1], false)
		local got = Sync.fnvBuffer(b)
		local ok = buffer.len(b) == e[2] and got == e[3] and info.bytes == e[2] and info.fnv == e[3] and names[i] == e[1]
		if not ok then
			bad += 1
		end
		table.insert(lines, string.format("%s  %-20s %9d bytes  fnv %s", if ok then "ok " else "BAD", e[1], buffer.len(b), got))
		if e[1] == "Height" or e[1] == "WaterLevel" then
			held[e[1]] = b
		end
	end
	task.wait()
end
local function cells(label, b, list)
	local wrong = 0
	for k = 1, #list, 3 do
		local got = buffer.readu16(b, 2 * (list[k] * @N@ + list[k + 1]))
		if got ~= list[k + 2] then
			wrong += 1
			table.insert(lines, string.format("BAD  %s cell (%d, %d): Studio %d, file %d", label, list[k], list[k + 1], got, list[k + 2]))
		end
	end
	bad += wrong
	table.insert(lines, string.format("%s  %d %s cells compared with the files, %d differ", if wrong == 0 then "ok " else "BAD", #list / 3, label, wrong))
end
if held.Height then
	cells("height", held.Height, HEIGHTS)
end
if held.WaterLevel then
	cells("water", held.WaterLevel, WATER)
end
local terrain = game:GetService("HttpService"):JSONDecode(buffer.tostring(pack:blob("Terrain")))
local layout = game:GetService("HttpService"):JSONDecode(buffer.tostring(pack:blob("Layout")))
table.insert(lines, string.format("ok   Terrain and Layout decode as JSON: map %q, %d layout items", tostring(terrain.map), #layout.items))
pack:close()
table.insert(lines, 1, string.format("%s: pack @PACK@, %d blobs, %.1f s", if bad == 0 then "PROOF PASSED" else "PROOF FAILED (" .. bad .. ")", #EXPECT, os.clock() - t0))
return table.concat(lines, "\\n")
'''


def proof_script(pack_name, blob_rows, H0, W0, H2, W2, repairs):
    """Luau that proves the pack in Studio. Cell values come from the export files; repaired cells from the log."""
    rng = np.random.default_rng(1376)
    untouched = (H2 == H0) & (W2 == W0)

    def pick(mask, count):
        """`count` cells of a mask, chosen with the seeded generator."""
        cells = np.argwhere(mask)
        if count <= 0 or len(cells) == 0:
            return []
        chosen = rng.choice(len(cells), size=min(count, len(cells)), replace=False)
        return [(int(cells[k][0]), int(cells[k][1])) for k in sorted(chosen.tolist())]

    heights = [(r, c, int(H0[r, c])) for r, c in pick(untouched, 16)]  # untouched cells: the PNG's own values
    moved = [rp for rp in repairs if rp["groundNow"] != rp["groundWas"]]
    for rp in moved[:: max(1, len(moved) // 4)][:4]:  # repaired cells: the log's values
        heights.append((rp["row"], rp["col"], rp["groundNow"]))
    heights += [(r, c, int(H0[r, c])) for r, c in pick(untouched, 20 - len(heights))]
    water = []
    for lv in np.unique(W2[W2 > 0]).tolist():  # one untouched cell of every level
        water += [(r, c, int(lv)) for r, c in pick(untouched & (W0 == lv), 1)]
    rewet = [rp for rp in repairs if rp["levelNow"] != rp["levelWas"]]
    for rp in rewet[:: max(1, len(rewet) // 4)][:4]:  # dried cells must read 0, margin cells their new level
        water.append((rp["row"], rp["col"], rp["levelNow"]))
    water += [(r, c, int(W0[r, c])) for r, c in pick(untouched & (W0 > 0), 17 - len(water))]
    water += [(r, c, 0) for r, c in pick(untouched & (W0 == 0), 20 - len(water))]
    for row, col, v in heights:
        assert int(H2[row, col]) == v
    for row, col, v in water:
        assert int(W2[row, col]) == v
    text = PROOF_TEMPLATE
    text = text.replace("@PACK@", pack_name).replace("@N@", str(N))
    text = text.replace("@EXPECT@", "\n".join('\t{ "%s", %d, "%s" },' % (r["name"], r["bytes"], r["fnv"]) for r in blob_rows))
    text = text.replace("@HEIGHTS@", ", ".join("%d, %d, %d" % t for t in heights))
    text = text.replace("@WATER@", ", ".join("%d, %d, %d" % t for t in water))
    return text


def load_history(manifest_path):
    """The builds so far, oldest first: [{build, date, changes, blobs?}]. Only the newest entry keeps its blobs."""
    if not os.path.isfile(lp(manifest_path)):
        return []
    try:
        old = json.loads(read_bytes(manifest_path).decode("utf-8"))
    except ValueError:
        return []
    if old.get("history"):
        return old["history"]
    if old.get("blobs"):  # a manifest from before builds were numbered: it is build 1
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(lp(manifest_path))))
        return [{"build": 1, "date": when, "changes": ["first build"],
                 "blobs": {b["name"]: [b["bytes"], b["fnv"]] for b in old["blobs"]}}]
    return []


def describe_changes(last, blobs, blob_rows, build):
    """What differs from the build before, one line per blob. For a grid it counts the cells that changed, read from
    the blob file the last run left in the build folder."""
    lines = []
    rows = {r["name"]: r for r in blob_rows}
    for name, fname, data, _desc in blobs:
        row = rows[name]
        if name not in last:
            lines.append("added %s (%d bytes, %s)" % (name, row["bytes"], row["fnv"]))
        elif last[name] != [row["bytes"], row["fnv"]]:
            detail = ""
            old_path = os.path.join(build, fname)
            if os.path.isfile(lp(old_path)):
                old = read_bytes(old_path)
                if fnv(old) == last[name][1] and len(old) == len(data) and fname.endswith(".bin"):
                    dtype = "<u2" if name in ("Height", "WaterLevel") else np.uint8
                    a = np.frombuffer(old, dtype=dtype).astype(np.int64)
                    b = np.frombuffer(data, dtype=dtype).astype(np.int64)
                    diff = a != b
                    scale = float(UNIT) if name in ("Height", "WaterLevel") else 1.0
                    detail = ": %d cells differ, by up to %s" % (int(diff.sum()), num(float(np.abs(a - b).max()) / scale))
            if not fname.endswith(".bin"):
                detail = ": now " + row["content"]
            lines.append("changed %s (%s -> %s)%s" % (name, last[name][1], row["fnv"], detail))
    for name in last:
        if name not in rows:
            lines.append("removed %s" % name)
    return lines or ["no blob changed"]


def pack_is_current(state_path, want):
    """The path of the Studio pack if the file in Studio's content folder is exactly the pack this run would build
    (same name, same blobs, the file untouched since it was built); None otherwise."""
    if not os.path.isfile(lp(state_path)):
        return None
    try:
        state = json.loads(read_bytes(state_path).decode("utf-8"))
        if state.get("pack") != want["pack"] or state.get("blobs") != want["blobs"]:
            return None
        # Studio's content folder moves with every Studio update: ask studio_sync where it is now
        import importlib.util
        spec = importlib.util.spec_from_file_location("ls_studio_sync", os.path.join(REPO, "tools", "studio_sync", "sync.py"))
        sync = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sync)
        here = os.path.join(sync.studio_dir(), want["pack"] + ".rbxmx")
        if os.path.normcase(os.path.abspath(here)) != os.path.normcase(os.path.abspath(state.get("path", ""))):
            return None
        if not os.path.isfile(lp(here)) or sha(read_bytes(here)) != state.get("sha256"):
            return None
        return here
    except (ValueError, OSError, AttributeError, SystemExit):
        return None


def run_sync_blob(pack_name, blob_files):
    """Build the Studio pack with tools/studio_sync/sync.py blob; returns (its path, {name: (bytes, fnv)})."""
    cmd = [sys.executable, os.path.join(REPO, "tools", "studio_sync", "sync.py"), "blob", pack_name]
    cmd += ["%s=%s" % (name, path) for name, path in blob_files]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO)
    if res.returncode != 0:
        raise PackError("sync.py blob failed:\n" + res.stdout + res.stderr)
    seen, pack_path = {}, None
    for line in res.stdout.splitlines():
        if line.startswith("data pack ") and " -> " in line:
            pack_path = line.split(" -> ", 1)[1].strip()
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "bytes":
            seen[parts[0]] = (int(parts[1]), parts[3])
    return pack_path, seen


def main(argv):
    opts = {"exports": default_exports(), "build": None, "pack": "map1_data", "cell": 32, "margin": STREAM_MARGIN,
            "dry": False, "no_pack": False, "no_module": False, "ready": None, "force_pack": False}
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--force-pack":
            opts["force_pack"] = True
        elif a == "--margin":
            opts["margin"] = True
        elif a == "--no-margin":
            opts["margin"] = False
        elif a == "--exports":
            opts["exports"] = args.pop(0)
        elif a == "--build":
            opts["build"] = args.pop(0)
        elif a == "--pack-name":
            opts["pack"] = args.pop(0)
        elif a == "--height-cell":
            opts["cell"] = int(args.pop(0))
        elif a == "--ready":
            opts["ready"] = args.pop(0)
        elif a == "--dry":
            opts["dry"] = True
        elif a == "--no-pack":
            opts["no_pack"] = True
        elif a == "--no-module":
            opts["no_module"] = True
        else:
            sys.exit(__doc__)
    official = opts["pack"] == "map1_data"
    if opts["build"] is None:  # an experiment pack gets a build folder of its own
        opts["build"] = os.path.join(HERE, "build") if official else os.path.join(HERE, "build", opts["pack"])

    print("Map 1 packer: exports in %s" % opts["exports"])
    ex = load_exports(opts["exports"])
    H0 = ex["height"].astype(np.int64)
    W0 = ex["waterLevel"].astype(np.int64)
    print("  read %d export files; knoll y %.2f..%.2f, ring y %.2f..%.2f, plinths on the ground within %.3f" % (
        len(ex["sources"]), ex["heart"]["knoll"][0], ex["heart"]["knoll"][1], ex["heart"]["ring"][0],
        ex["heart"]["ring"][1], ex["heart"]["plinthGroundError"]))

    before = {4: count_faults(H0, W0, NB4), 8: count_faults(H0, W0, NB8)}
    levels_before = level_table(H0, W0)
    print("  water in the export: %d wet cells at %d levels" % (int((W0 > 0).sum()), len(levels_before)))
    print("    levels breaking the voxel rule: %d cells" % before[8]["badLevelCells"])
    print("    wet neighbours with different levels: %d pairs (4 neighbours), %d (8 neighbours)" % (
        before[4]["stepPairs"], before[8]["stepPairs"]))
    print("    wet cell beside a lower dry cell: %d pairs, worst %.2f (4 neighbours); %d pairs, worst %.2f (8 neighbours)" % (
        before[4]["leakPairs"], before[4]["worstLeak"], before[8]["leakPairs"], before[8]["worstLeak"]))

    H2, W2, repairs = repair_water(H0, W0, opts["margin"])
    checks = assert_water(H2, W2, H0, W0, repairs, opts["margin"])
    after = {4: count_faults(H2, W2, NB4), 8: count_faults(H2, W2, NB8)}
    levels_after = level_table(H2, W2)
    dried = [rp for rp in repairs if rp["levelWas"] > 0 and rp["levelNow"] == 0]
    banks = [rp for rp in repairs if rp["kind"] == "bank"]
    margins = [rp for rp in repairs if rp["kind"] == "margin"]
    raised = [rp for rp in repairs if rp["groundNow"] > rp["groundWas"]]
    print("  repairs: %d cells dried (%d sills, %d bad levels, %d with no depth), %d banks raised; largest rise %.2f studs" % (
        len(dried), len([r for r in dried if r["kind"] == "sill"]), len([r for r in repairs if r["kind"] == "badLevel"]),
        len([r for r in repairs if r["kind"] == "noDepth"]), len(banks),
        max([studs(rp["groundNow"] - rp["groundWas"]) for rp in raised] or [0.0])))
    if opts["margin"]:
        print("  the margin: %d cells beside narrow water made wet, %.2f studs deep; largest lowering %.2f studs" % (
            len(margins), studs(MARGIN_DEPTH), max([studs(rp["groundWas"] - rp["groundNow"]) for rp in margins] or [0.0])))
    for text in checks:
        print("  PASS  " + text)
    hollows = find_hollows(H2, W2)
    for hw in hollows:
        print("  NOTE  a hollow of %d dry cells, up to %.2f studs under the water at %.2f beside it, at x %.0f..%.0f, "
              "z %.0f..%.0f: left as it is (see the repair log)" % (
                  hw["cells"], hw["deepest"], hw["level"], hw["xFrom"], hw["xTo"], hw["zFrom"], hw["zTo"]))

    blobs = make_blobs(ex, H2, W2)
    print("  fingerprinting %d blobs (%.1f MB) ..." % (len(blobs), sum(len(b[2]) for b in blobs) / 1e6))
    blob_rows = [{"name": name, "file": fname, "bytes": len(data), "fnv": fnv(data), "content": desc}
                 for name, fname, data, desc in blobs]
    by_name = {r["name"]: r for r in blob_rows}

    module_data, module_info, _grid, _decoded = build_module(
        H2, ex["region"], ex["biomeGrid"], opts["cell"], by_name["Height"]["fnv"], by_name["Region"]["fnv"], ex["notes"])
    acc = module_info["accuracyInsideR1800"]
    print("  Map1Regions.lua: %d bytes (limit %d); height nodes %d studs apart: median error %.2f, 95%% %.2f, 99%% %.2f, "
          "within 6 studs on %.2f%% of points inside r 1,800" % (
              module_info["bytes"], MODULE_LIMIT, opts["cell"], acc["p50"], acc["p95"], acc["p99"], 100 * acc["within6"]))
    for note in ex["notes"]:
        print("  NOTE  " + note)

    manifest = {
        "pack": opts["pack"],
        "contract": "docs/design/Map1Build.md 3.3",
        "grid": {"cells": N, "cellStuds": CELL, "origin": ORIGIN, "rowOrder": "row 0 = north (z = %d)" % ORIGIN,
                 "maskCells": MASK_N, "heightUnit": "value / %d" % UNIT},
        "blobs": [{k: r[k] for k in ("name", "bytes", "fnv", "content")} for r in blob_rows],
        "missing": ["Manifest_" + nm for nm in MANIFESTS if nm not in ex["manifests"]],
        "sources": ex["sources"],
        "water": {
            "neighbourhood": 8, "sillRise": studs(SILL_RISE),
            "exportFaults": {"4": before[4], "8": before[8]},
            "afterRepairs": {"4": after[4], "8": after[8]},
            "cellsDried": len(dried), "banksRaised": len(banks), "heightsRaised": len(raised),
            "margin": bool(opts["margin"]), "marginCells": len(margins), "marginDepth": studs(MARGIN_DEPTH),
            "wetCells": int((W2 > 0).sum()), "levels": [lv["level"] for lv in levels_after],
            "hollowsLeft": hollows,
        },
        "module": dict(module_info, file="src/ReplicatedStorage/Shared/Map1Regions.lua",
                       packHeight=by_name["Height"]["fnv"], packRegion=by_name["Region"]["fnv"]),
        "notes": ex["notes"],
    }

    if opts["dry"]:
        print("")
        print("%-20s %10s  %s" % ("Blob", "Bytes", "FNV-1a"))
        for r in blob_rows:
            print("%-20s %10d  %s" % (r["name"], r["bytes"], r["fnv"]))
        print("dry run: nothing written")
        return 0

    build = opts["build"]
    # The log, the manifest and the module are the real pack's record. A pack under another name is an experiment:
    # its log and manifest stay in its build folder and the module is not written.
    record_dir = HERE if official else build
    manifest_path = os.path.join(record_dir, "pack_manifest.json")

    # the build number and what changed since the build before (decided before the old blob files are overwritten)
    history = load_history(manifest_path)
    new_blobs = {r["name"]: [r["bytes"], r["fnv"]] for r in blob_rows}
    if not history or history[-1].get("blobs") != new_blobs:
        last = history[-1].get("blobs") if history else None
        changes = describe_changes(last, blobs, blob_rows, build) if last else ["first build"]
        for entry in history:
            entry.pop("blobs", None)  # only the newest entry needs its fingerprints
        history.append({"build": len(history) + 1, "date": time.strftime("%Y-%m-%d %H:%M"), "changes": changes,
                        "blobs": new_blobs})
        print("  build %d: %s" % (history[-1]["build"], "; ".join(changes)))
    else:
        print("  build %d: no blob changed since it was made (%s)" % (history[-1]["build"], history[-1]["date"]))
    manifest["build"] = history[-1]["build"]
    manifest["history"] = history[-20:]

    blob_files = []
    for name, fname, data, _desc in blobs:
        path = os.path.join(build, fname)
        if not os.path.isfile(lp(path)) or read_bytes(path) != data:
            write_bytes(path, data)
        blob_files.append((name, path))
    stale = [f for f in os.listdir(lp(build)) if f.startswith("Manifest_") and f not in {b[1] for b in blobs}]
    for f in stale:
        os.remove(lp(os.path.join(build, f)))
    print("  %d blob files are in %s" % (len(blobs), build))

    # the Studio pack: built unless the one in Studio's content folder is already this very build
    pack_path = None
    if not opts["no_pack"]:
        state_path = os.path.join(build, "pack_built.json")
        want = {"pack": opts["pack"], "blobs": [[r["name"], r["bytes"], r["fnv"]] for r in blob_rows]}
        pack_path = pack_is_current(state_path, want)
        if pack_path and not opts["force_pack"]:
            print("  the Studio pack %s is already this build: %s (use --force-pack to write it again)" % (opts["pack"], pack_path))
        else:
            pack_path, seen = run_sync_blob(opts["pack"], blob_files)
            for r in blob_rows:
                if seen.get(r["name"]) != (r["bytes"], r["fnv"]):
                    raise PackError("sync.py packed %s as %r; the packer made %r" % (
                        r["name"], seen.get(r["name"]), (r["bytes"], r["fnv"])))
            want["path"] = pack_path
            want["sha256"] = sha(read_bytes(pack_path))
            write_bytes(state_path, (json.dumps(want, indent=1) + "\n").encode("utf-8"))
            print("  built the Studio pack %s -> %s" % (opts["pack"], pack_path))

    write_log(os.path.join(record_dir, "repair_log.md"), ex, before, after, levels_before, levels_after, repairs, checks,
              hollows, opts["margin"])
    write_bytes(manifest_path, (json.dumps(manifest, indent=1) + "\n").encode("utf-8"))
    write_bytes(os.path.join(build, "proof.luau"),
                proof_script(opts["pack"], blob_rows, H0, W0, H2, W2, repairs).encode("utf-8"))
    print("  wrote repair_log.md and pack_manifest.json in %s, and %s" % (record_dir, os.path.join(build, "proof.luau")))
    if official and not opts["no_module"]:
        old = read_bytes(MODULE_PATH) if os.path.isfile(lp(MODULE_PATH)) else None
        if old != module_data:
            write_bytes(MODULE_PATH, module_data)
            print("  wrote src/ReplicatedStorage/Shared/Map1Regions.lua (%d bytes, fnv %s): PUSH IT with "
                  "tools/studio_sync (sync.py push, the apply line, confirm)" % (len(module_data), module_info["fnv"]))
        else:
            print("  src/ReplicatedStorage/Shared/Map1Regions.lua is unchanged (%d bytes, fnv %s)" % (
                len(module_data), module_info["fnv"]))
    text = ready_text(opts["pack"], blob_rows, manifest, pack_path)
    write_bytes(os.path.join(build, "READY.txt"), text.encode("utf-8"))
    if opts["ready"]:
        write_bytes(opts["ready"], text.encode("utf-8"))
    print("")
    print("%-20s %10s  %s" % ("Blob", "Bytes", "FNV-1a"))
    for r in blob_rows:
        print("%-20s %10d  %s" % (r["name"], r["bytes"], r["fnv"]))
    if not opts["no_pack"]:
        print("\nNow prove it in Studio (Edit mode): run the text of %s with execute_luau." % os.path.join(build, "proof.luau"))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except PackError as err:
        sys.exit("pack.py STOPPED: %s" % err)
