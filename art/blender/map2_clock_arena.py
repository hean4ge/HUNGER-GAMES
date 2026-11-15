"""
map2_clock_arena.py - MAP 2, "the clock": the Catching Fire 12-sector clock arena at 3x, rebuilt in style A.
(Blender 5.3, headless. Brief: docs/design/UpcomingFilm_Brief.md section 3; style: docs/design/ArtStyle.md, style A.)

The owner: "the second map ... will be like the second map of the original hunger games movie where the map is a
clock", "recreated 3 x bigger and will have all the challenges in the movie and more". The reference is the owner's
fan-made sector guide (References/owner/map2_clock_arena_reference.png); the film set, film still and concept art are
in References/web. References are for study only: nothing from them is traced, sampled into a texture or exported.

What it builds (seeded: the same run makes the same files)
  * The whole map at game scale. Force field (play radius) R = 2,600 studs (1.46 km): the brief's recommendation,
    3x the real set's ~150 m lagoon, which is the guide at its own scale bar (lagoon 0.35 R, beach to 0.42 R).
    Everything is laid out in fractions of R, so R can change in one place.
      island r 0-120 (lava rock; flat plaza r 62 at y 46, the horn on it), lagoon r 0-910 (salt, water 34, 24 deep),
      12 basalt spokes on the hour bearings (790 x 10, deck 35.6), 24 plates in the water at r 210, beach ring
      r 910-1,090, jungle r 1,090-2,600 rising 40 -> 120 (0.6 R) -> 260 at the field, sector gullies on the 12 hour
      lines, the force field at R with a seared seam, visual-only jungle to R + 300 and fluted backdrop ridges.
  * Each of the 12 wedges has its own static read (landform + dressing + one landmark) so it is known at a glance.
  * Style A meshes: horn (faceted steel shards), island deck, island ring + 12 ramps, spoke modules, spoke spurs,
    plates + water collars, lightning tree, basalt pinnacles, clay mounds, and faceted placeholder plants (palms,
    broadleaf trees, giants, banyans, mangroves, emergents, fan palms, tree ferns, big-leaf clumps, shrubs,
    driftwood, snags, canopy shells). No cards, no textures: colour is painted per facet.

Run (from the repo root)
  blender --background --factory-startup --python art/blender/map2_clock_arena.py -- <export dir> <preview dir> [stages] [views]
    export dir   default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Map2
    preview dir  default art/previews/Map2
    stages       comma list of data, build, render, compare, glb (default all, in that order)
    views        comma list of render views (default all): overview, birdseye, topdown, lagoon, concept, girders,
                 plate, sectors (a 12-tile sheet: each wedge as a tribute sees it from the lagoon)
  env MAP2_WORK (scratch, default %TEMP%/Map2_build), MAP2_REFS (References folder), MAP2_SAMPLES (default 40),
      MAP2_SECTOR12 (centre bearing of sector "12": 15 = the owner's guide, the default; 0 = the brief's 3.3 reading)

Outputs
  <export>/terrain/*.png + Map2_terrain.json   heightmaps (16-bit) and biome masks (8-bit), layout and legend
  <export>/Map2_Landmarks.glb + .manifest.json landmark meshes (copy of the manifest in art/manifests/)
  <preview>/*.png                              overview, bird's-eye, data maps, sector sheet, view_*.png, tones.json
  <preview>/compare_*.png                      our render beside its reference frame: study only, git-ignored here
Render-only (never exported): the far island slopes and sea past the coarse grid, the faint dome cap, foam
patches, the 5.5-stud scale figure. Preview renders are for iterating; approve in Studio at 14:00 and 17:30.
"""
import json
import math
import os
import random
import struct
import sys
import tempfile
import time
import zlib

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

T0 = time.time()


def log(*a):
    print("[%7.1fs]" % (time.time() - T0), *a, flush=True)


HERE = os.path.dirname(os.path.abspath(__file__))
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def _arg(i, default):
    return ARGV[i] if len(ARGV) > i and ARGV[i] not in ("", "-", "default") else default


HOME = os.path.expanduser("~")
OUT = os.path.abspath(_arg(0, os.path.join(HOME, "OneDrive", "Documents", "LastStanding", "BlenderExports", "Map2")))
PREV = os.path.abspath(_arg(1, os.path.normpath(os.path.join(HERE, "..", "previews", "Map2"))))
STAGES = _arg(2, "data,build,render,compare,glb").split(",")
VIEW_ARG = _arg(3, "all")
WORK = os.environ.get("MAP2_WORK") or os.path.join(tempfile.gettempdir(), "Map2_build")
REFS = os.environ.get("MAP2_REFS") or os.path.join(HOME, "OneDrive", "Documents", "LastStanding", "References")
SAMPLES = int(os.environ.get("MAP2_SAMPLES", "40"))
MANIFEST_COPY = os.path.normpath(os.path.join(HERE, "..", "manifests"))
TERR = os.path.join(OUT, "terrain")
for _d in (OUT, TERR, PREV, WORK):
    os.makedirs(_d, exist_ok=True)

TAU = 2.0 * math.pi

# =============================================================================================== layout (fractions of R)
SEED = 75
R = 2600.0                      # force field = play radius (brief 3.2: recommended)
WATER = 34.0                    # lagoon level (salt)
PLAZA_Y, PLAZA_R = 46.0, 62.0   # kept from TerrainGen's fixed inputs: the island's flat top
ISLAND_R = 0.046 * R            # 120: waterline of the island
SHORE_R = 0.35 * R              # 910: lagoon water edge (mean)
BEACH_R = 0.42 * R              # 1,092: top of the beach (mean)
PLATE_R = 0.0808 * R            # 210: plates in the lagoon, 27 studs (4 s swim) from the nearest spoke
PLATE_TOP = 36.0                # plate top, 2 studs above the water
N_PLATES = 24                   # 2 per wedge, 7.5 deg either side of each spoke
SPOKE_W, SPOKE_TOP = 10.0, 35.6
FIELD_VISUAL = 300.0            # visual-only jungle past the field (brief 3.7)
WORLD_R = 3552.0                # terrain reaches this radius (coarse grid half extent)
SECTOR12_CENTRE = float(os.environ.get("MAP2_SECTOR12", "15"))
HOURS = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
FINE = (4.0, 2752.0)            # export grid: 4 studs per pixel, +-2,752 (1,376 px)
COARSE = (8.0, 3552.0)          # export grid + Blender terrain mesh: 8 studs per pixel, +-3,552 (888 px)
H_SCALE, H_OFFSET = 50.0, 64.0  # u16 = round((y + 64) * 50): 0.02-stud steps, y from -64 to 1,246.7

SECTORS = {
    12: ("LIGHTNING", "Lightning strikes the tallest tree at noon and midnight", "L",
         "the lightning tree (180 tall, bleached, scarred) on a knoll in a seared clearing; struck snags"),
    1: ("BLOOD RAIN", "Blood rain: thick dark red rain that stains surfaces (13+: no pools, no gore)", "L",
        "laterite: red-earth banks on the steep folds and three landslide scars; bronze-flush canopy"),
    2: ("POISON FOG", "Fog rolls from the rim to the beach; salt water purges it", "L",
        "a broad basin draining to the beach, silver-sage canopy, pale ghost trees, a still pool"),
    3: ("MONKEYS", "A troop of 20-40 monkey mutts waiting in the canopy", "L",
        "the canopy heights: a raised shelf of banyan giants with root pillars, the darkest green"),
    4: ("JABBERJAYS", "Jabberjays behind a transparent barrier that seals the wedge", "L",
        "basalt pinnacles (45-110 tall) standing out of the canopy, bird-perch snags on top"),
    5: ("SINKING SAND", "Ours: the beach and gullies turn to sucking mud", "I",
        "a wide mud fan and creek where the beach is widest; olive mangroves on stilt roots"),
    6: ("THE BEAST", "A beast never fully seen: flattened undergrowth, scored trunks, breathing in the fog", "L/I",
        "a deep winding ravine with a pool; the densest, darkest giants"),
    7: ("HEAT LAMP", "Ours: the sky goes white-hot with heat shimmer; shade and water matter", "I",
        "open dry savanna: straw grass, pale rock slabs, scattered fan palms"),
    8: ("FALLING TIMBER", "Ours: nuts and branches rain down, then trees topple across the paths", "I",
        "emergent timber trees (85-95 tall) and windthrown logs; a forest pond"),
    9: ("CRAB TIDE", "Ours: engineered land crabs pour up from the water across the beach", "I",
        "a dark lava-rock reef shelf awash with tide pools, and a coconut palm grove"),
    10: ("THE WAVE", "A 60-80-stud wall of water sweeps down the wedge; the lagoon surges", "L",
         "the scoured trough: a wide U-channel from the rim to the beach, flattened palms, driftwood lines"),
    11: ("INSECTS", "Clicking insects in the canopy that swarm whoever stays", "L/I",
         "a wet hollow with a spring pond, ochre clay insect mounds and lush big-leaf thickets"),
}


def sector_centre(h):
    return (SECTOR12_CENTRE + 30.0 * (h % 12)) % 360.0


def polar(bearing, r, z=0.0):
    """Blender XY(Z) from a bearing (deg clockwise from north = +Y) and a radius."""
    b = math.radians(bearing)
    return Vector((r * math.sin(b), r * math.cos(b), z))


def rbx(v):
    """Blender (x, y, z) -> Roblox (x, y, z) = (x, z, -y)."""
    return [round(float(v[0]), 3), round(float(v[2]), 3), round(float(-v[1]), 3)]


# =============================================================================================== palette (sRGB)
# Brief 3.8 (sampled -> semi-real) and ArtStyle's light band. Hazard/loot signals are the only saturated colours.
PAL = {
    "water": (40, 80, 80), "water_mid": (54, 96, 94), "water_shallow": (88, 122, 114), "surf": (226, 230, 228),
    "fresh": (52, 92, 86),
    "sand": (198, 188, 160), "sand_wet": (150, 140, 116), "lava": (96, 92, 88), "lava_top": (112, 108, 102),
    "rock": (122, 116, 106), "jungle": (96, 84, 62), "mud": (104, 90, 70), "salt": (126, 120, 106),
    "laterite": (128, 94, 76), "drygrass": (138, 132, 86), "seared": (110, 102, 90),
    "horn": (172, 174, 174), "palm_frond": (76, 92, 52), "canopy": (64, 86, 48), "canopy_dark": (54, 74, 42),
    "palm_trunk": (126, 110, 90), "bark": (116, 102, 84), "fern": (70, 94, 56), "bigleaf": (66, 92, 46),
    "shrub": (80, 96, 56), "deadwood": (176, 170, 156), "snag": (150, 144, 132), "ghost": (170, 168, 158),
    "driftwood": (168, 160, 146), "char": (74, 68, 64), "clay": (154, 122, 84), "pinnacle": (104, 100, 94),
    "slab": (140, 134, 122), "plate_steel": (150, 152, 150), "plate_copper": (176, 112, 70), "brass": (150, 120, 78),
    "collar": (88, 96, 98), "basalt_floor": (102, 98, 92), "rack_wood": (126, 104, 80), "crate": (120, 100, 78),
    "steel_band": (110, 112, 112), "mangrove": (78, 88, 52), "fanpalm": (96, 104, 66), "coconut": (120, 104, 62),
    "far": (62, 80, 52), "field": (200, 222, 230),
}
# per-sector canopy colour targets (foliage faces are tinted toward these); all inside leaves G 65-95
CANOPY_TINT = {12: (64, 86, 48), 1: (92, 76, 50), 2: (88, 95, 80), 3: (46, 70, 38), 4: (74, 84, 64),
               5: (80, 86, 48), 6: (44, 62, 36), 7: (96, 98, 58), 8: (84, 95, 44), 9: (64, 86, 48),
               10: (82, 95, 54), 11: (56, 92, 44)}

# terrain material slots (Expanded Terrain tinted slots; each slot's base material sets footsteps)
SLOTS = [  # index, key, Roblox base material, slot name, tint, note
    (1, "sand", "Sand", "beach", PAL["sand"], "beach and lagoon bed"),
    (2, "sand_wet", "Sand", "wet", PAL["sand_wet"], "wet margin at the waterline"),
    (3, "lava", "Rock", "lava", PAL["lava"], "island, spoke bases, spurs, the reef (dark identity rock; not Basalt)"),
    (4, "rock", "Rock", "outcrop", PAL["rock"], "steep jungle folds, ravine walls, pinnacle bases, slabs, crests"),
    (5, "jungle", "LeafyGrass", "jungle", PAL["jungle"], "jungle floor (luma 80-95)"),
    (6, "mud", "Mud", "wet", PAL["mud"], "wet gullies, the 5 o'clock fan, ravine floor, hollow, pool beds"),
    (7, "salt", "Salt", "gully", PAL["salt"], "the 12 sector-line gullies (pebble variant)"),
    (8, "laterite", "Ground", "laterite", PAL["laterite"], "sector 1 red-earth banks and scars (invented)"),
    (9, "drygrass", "Grass", "dry", PAL["drygrass"], "sector 7 savanna (invented)"),
    (10, "seared", "Ground", "seared", PAL["seared"], "the field seam and the lightning clearing (invented)"),
]
SLOT = {k: i for i, k, *_ in SLOTS}
REGIONS = {1: "island", 2: "lagoon", 3: "spoke", 4: "beach", 5: "jungle", 6: "field seam", 7: "visual-only jungle",
           8: "backdrop"}


# =============================================================================================== small maths
def smoothstep(e0, e1, x):
    """Hermite step from e0 to e1 (edges may be arrays; e0 > e1 gives the falling step)."""
    x = np.asarray(x, np.float64)
    den = np.asarray(e1, np.float64) - e0
    den = np.where(np.abs(den) < 1e-9, 1e-9, den)
    t = np.clip((x - e0) / den, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rwin(r, a, b, c, d):
    return smoothstep(a, b, r) * smoothstep(d, c, r)


def angdiff(a, b):
    return (np.asarray(a, np.float64) - b + 180.0) % 360.0 - 180.0


def wedge_w(th, hour, inner=10.0, outer=14.5):
    return smoothstep(outer, inner, np.abs(angdiff(th, sector_centre(hour))))


def boundary_deg(th):
    t = (np.asarray(th) - (SECTOR12_CENTRE - 15.0)) % 30.0
    return np.minimum(t, 30.0 - t)


def spoke_deg(th):
    t = np.asarray(th) % 30.0
    return np.minimum(t, 30.0 - t)


def hour_of(th):
    k = np.floor(((np.asarray(th) - (SECTOR12_CENTRE - 15.0)) % 360.0) / 30.0).astype(np.int64)
    return np.where(k == 0, 12, k)


def mspline(x, xs, ys):
    """Monotone cubic (Fritsch-Carlson) through (xs, ys); flat tangents at local extrema."""
    xs = np.asarray(xs, np.float64)
    ys = np.asarray(ys, np.float64)
    h = np.diff(xs)
    d = np.diff(ys) / h
    m = np.empty_like(ys)
    m[0], m[-1] = d[0], d[-1]
    m[1:-1] = (d[:-1] + d[1:]) / 2.0
    for k in range(1, len(ys) - 1):
        if d[k - 1] * d[k] <= 0:
            m[k] = 0.0
    for k in range(len(d)):
        if d[k] == 0:
            m[k] = m[k + 1] = 0.0
        else:
            a, b = m[k] / d[k], m[k + 1] / d[k]
            s = a * a + b * b
            if s > 9.0:
                t = 3.0 / math.sqrt(s)
                m[k], m[k + 1] = t * a * d[k], t * b * d[k]
    x = np.clip(np.asarray(x, np.float64), xs[0], xs[-1])
    i = np.clip(np.searchsorted(xs, x, side="right") - 1, 0, len(xs) - 2)
    t = (x - xs[i]) / h[i]
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1]
            + (t3 - t2) * h[i] * m[i + 1])


def _h32(ix, iz, seed):
    h = (ix * np.int64(73856093)) ^ (iz * np.int64(19349663)) ^ np.int64((seed * 83492791) & 0x7FFFFFFF)
    h = h & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * np.int64(1274126177)) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / 16777215.0


def vnoise(X, Y, scale, seed, rot=0.0):
    """Smooth value noise in [-1, 1] at continuous positions (resolution independent)."""
    if rot:
        c, s = math.cos(rot), math.sin(rot)
        X, Y = X * c - Y * s, X * s + Y * c
    x = X / scale + 1000.37
    y = Y / scale + 1000.71
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    ix, iy = ix.astype(np.int64), iy.astype(np.int64)
    ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    a = _h32(ix, iy, seed)
    b = _h32(ix + 1, iy, seed)
    c = _h32(ix, iy + 1, seed)
    d = _h32(ix + 1, iy + 1, seed)
    return (a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy) * 2.0 - 1.0


def fbm(X, Y, scale, octaves, seed, gain=0.5, lac=2.07):
    tot, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        tot = tot + amp * vnoise(X, Y, scale, seed + 1013 * o, rot=0.61 * o)
        norm += amp
        amp *= gain
        scale /= lac
    return tot / norm


def angn(th_deg, seed, terms):
    rng = random.Random(seed)
    t = np.radians(np.asarray(th_deg, np.float64))
    out = np.zeros_like(t)
    for k, a in terms:
        out = out + a * np.sin(k * t + rng.uniform(0, TAU))
    return out


def hashf(x, salt=0):
    x = np.asarray(x).astype(np.uint64)
    x = (x * np.uint64(2654435761) + np.uint64((salt * 7919 + 104729) & 0xFFFFFFFF)) & np.uint64(0xFFFFFFFF)
    x ^= x >> np.uint64(16)
    x = (x * np.uint64(0x45D9F3B)) & np.uint64(0xFFFFFFFF)
    x ^= x >> np.uint64(16)
    return (x & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


def s2l(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def l2s(c):
    c = np.clip(np.asarray(c, np.float64), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def luma255(c):
    c = np.asarray(c, np.float64)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


# =============================================================================================== PNG / images
def write_png(path, arr, bits=8):
    """arr: uint8/uint16, H x W (gray) or H x W x 3/4; row 0 = top of the image."""
    a = np.ascontiguousarray(arr)
    h, w = a.shape[:2]
    ch = 1 if a.ndim == 2 else a.shape[2]
    ctype = {1: 0, 2: 4, 3: 2, 4: 6}[ch]
    if bits == 16:
        raw = np.ascontiguousarray(a.astype(">u2")).view(np.uint8).reshape(h, w * ch * 2)
    else:
        raw = a.astype(np.uint8).reshape(h, w * ch)
    up = raw.copy()
    up[1:] = ((raw[1:].astype(np.int16) - raw[:-1].astype(np.int16)) & 0xFF).astype(np.uint8)
    data = np.concatenate([np.full((h, 1), 2, np.uint8), up], axis=1).tobytes()

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, bits, ctype, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(data, 9)))
        f.write(chunk(b"IEND", b""))
    return path


def write_rgb(path, img01):
    return write_png(path, (np.clip(img01, 0, 1) * 255.0 + 0.5).astype(np.uint8))


def load_rgb(path):
    """Any image Blender reads -> H x W x 3 float (stored values, sRGB for 8-bit files), row 0 = top."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1, :, :3].astype(np.float64)


def load_linear(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].astype(np.float64)


def _box_blur(img, kx, ky):
    out = img
    if kx > 1:
        c = np.cumsum(np.pad(out, ((0, 0), (kx, kx), (0, 0)), mode="edge"), axis=1)
        out = (c[:, kx * 2:] - c[:, :-kx * 2])[:, :img.shape[1]] / (2 * kx)
    if ky > 1:
        c = np.cumsum(np.pad(out, ((ky, ky), (0, 0), (0, 0)), mode="edge"), axis=0)
        out = (c[ky * 2:] - c[:-ky * 2])[:img.shape[0]] / (2 * ky)
    return out


def resize(img, w, h):
    H, W = img.shape[:2]
    src = img
    fx, fy = W / float(w), H / float(h)
    if fx > 1.6 or fy > 1.6:
        src = _box_blur(img, int(fx / 2), int(fy / 2))
    xs = np.clip((np.arange(w) + 0.5) * W / w - 0.5, 0, W - 1)
    ys = np.clip((np.arange(h) + 0.5) * H / h - 0.5, 0, H - 1)
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    x1 = np.minimum(x0 + 1, W - 1)
    y1 = np.minimum(y0 + 1, H - 1)
    wx = (xs - x0)[None, :, None]
    wy = (ys - y0)[:, None, None]
    a = src[y0][:, x0]
    b = src[y0][:, x1]
    c = src[y1][:, x0]
    d = src[y1][:, x1]
    return (a * (1 - wx) + b * wx) * (1 - wy) + (c * (1 - wx) + d * wx) * wy


_G7 = {
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
    "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
    "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
    ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
    ",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
    ":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
    "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
    "(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
    ")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
    "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
    "'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
    "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
    "=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
    "%": ["##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"],
    "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
    "&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
    "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
    "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
}
GLYPHS = {k: "".join(v) for k, v in _G7.items()}
assert all(len(v) == 35 for v in GLYPHS.values())


def draw_text(img, x, y, text, scale=3, color=(0.95, 0.95, 0.93), bg=(0.08, 0.08, 0.08), pad=6):
    """5x7 bitmap text into an H x W x 3 float image (row 0 = top). Returns the width used."""
    text = text.upper()
    w = len(text) * 6 * scale - scale + 2 * pad
    hgt = 7 * scale + 2 * pad
    H, W = img.shape[:2]
    if bg is not None:
        img[max(0, y):min(H, y + hgt), max(0, x):min(W, x + w)] = bg
    cx = x + pad
    for ch in text:
        g = GLYPHS.get(ch, GLYPHS["?"])
        g = (g + "." * 35)[:35]
        for row in range(7):
            for col in range(5):
                if g[row * 5 + col] == "#":
                    y0, x0 = y + pad + row * scale, cx + col * scale
                    if 0 <= y0 < H and 0 <= x0 < W:
                        img[y0:y0 + scale, x0:x0 + scale] = color
        cx += 6 * scale
    return w


# =============================================================================================== layout objects
def _rand_points_in_wedge(rng, hour, n, r0, r1, half_deg, min_d, avoid=()):
    out = []
    tries = 0
    c = sector_centre(hour)
    while len(out) < n and tries < n * 400:
        tries += 1
        b = c + rng.uniform(-half_deg, half_deg)
        r = math.sqrt(rng.uniform(r0 * r0, r1 * r1))
        p = polar(b, r)
        if all((p - q[0]).length > min_d for q in out) and all((p - a).length > d for a, d in avoid):
            out.append((p, b, r))
    return out


def make_layout():
    rng = random.Random(SEED + 1)
    L = {}
    c = {h: sector_centre(h) for h in HOURS}
    L["lightning"] = polar(c[12], 0.47 * R)
    L["pinnacles"] = [(p, rng.uniform(130, 190), rng.uniform(0, 360))
                      for p, b, r in _rand_points_in_wedge(rng, 4, 7, 0.44 * R, 0.68 * R, 9.5, 140)]
    L["scars"] = [(c[1] - 6.0, 0.57 * R), (c[1] + 4.5, 0.72 * R), (c[1] - 1.0, 0.865 * R)]
    L["slabs"] = [(p, rng.uniform(0, 360), rng.uniform(0.8, 1.7))
                  for p, b, r in _rand_points_in_wedge(rng, 7, 22, 0.47 * R, 0.93 * R, 11, 70)]
    pools = []
    cr6 = c[6] + 4.5 * math.sin(1830.0 / 170.0 + 1.3)
    for name, hour, b, r, rad in (("FogPool", 2, c[2] + 1.0, 0.675 * R, 26.0), ("RavinePool", 6, cr6, 1830.0, 19.0),
                                  ("TimberPond", 8, c[8] + 5.0, 0.77 * R, 20.0),
                                  ("SpringPond", 11, c[11], 0.60 * R, 28.0)):
        pools.append(dict(name=name, hour=hour, centre=polar(b, r), radius=rad, level=None))
    L["pools"] = pools
    L["mounds"] = [(p, rng.uniform(0, 360), rng.uniform(0.75, 1.35))
                   for p, b, r in _rand_points_in_wedge(rng, 11, 70, 0.46 * R, 0.76 * R, 11.5, 26,
                                                        avoid=[(pools[3]["centre"], 50.0)])]
    L["mounds"] += [(p, rng.uniform(0, 360), rng.uniform(2.0, 3.0))
                    for p, b, r in _rand_points_in_wedge(rng, 11, 30, 0.408 * R, 0.445 * R, 12.0, 30)]
    L["logs"] = [(p, rng.uniform(0, 360), rng.uniform(0.85, 1.25))
                 for p, b, r in _rand_points_in_wedge(rng, 8, 150, 0.48 * R, 0.97 * R, 12.5, 22)]
    L["logs6"] = [(p, rng.uniform(0, 360), rng.uniform(0.8, 1.15))
                  for p, b, r in _rand_points_in_wedge(rng, 6, 40, 0.48 * R, 0.95 * R, 12.0, 30)]
    plates = []
    for i in range(N_PLATES):
        b = (7.5 + 15.0 * i) % 360.0
        plates.append(dict(index=i + 1, bearing=b, pos=polar(b, PLATE_R, PLATE_TOP)))
    L["plates"] = plates
    return L


LAYOUT = make_layout()
JK_R = [1000, 1092, 1200, 1350, 1560, 1800, 2050, 2300, 2600, 2750, 2900, 3050, 3200, 3330, 3450, 3560]
JK_Y = [38, 40, 50, 78, 120, 160, 198, 232, 260, 282, 318, 410, 540, 610, 580, 470]
SHORE_TERMS = [(2, 18), (3, 20), (4, 9), (5, 11), (7, 7), (9, 5), (13, 4), (17, 3.5), (23, 2.5), (29, 2.0)]
BEACH_TERMS = [(3, 8), (5, 7), (8, 5), (12, 3)]


# =============================================================================================== the terrain field
def field_core(X, Y):
    """Heights and the inputs the materials need, at arbitrary Blender XY positions (north = +Y)."""
    r = np.hypot(X, Y)
    th = np.degrees(np.arctan2(X, Y)) % 360.0
    W = {h: wedge_w(th, h) for h in HOURS}
    Rs = SHORE_R + angn(th, SEED + 11, SHORE_TERMS)
    Rb = (Rs + (BEACH_R - SHORE_R) + angn(th, SEED + 12, BEACH_TERMS) + 70.0 * W[5] + 45.0 * W[10]
          - 20.0 * W[9])
    # island + lagoon floor
    y_isl = np.interp(r, [0, 62, 70, 105, 122, 140, 160, 182], [46, 46, 45.2, 40, 34, 22, 13.5, 10])
    u = np.clip((r - 182.0) / np.maximum(Rs - 182.0, 1.0), 0.0, 1.0)
    rip = fbm(X, Y, 90.0, 3, SEED + 21) * 1.3 * smoothstep(0.05, 0.3, u) * (1.0 - smoothstep(0.8, 0.97, u))
    y_lag = 10.0 + 22.0 * smoothstep(0.52, 0.93, u) + 2.0 * smoothstep(0.93, 1.0, u) + rip
    y_lag = np.where(r < 182.0, y_isl, y_lag)
    # beach
    v = np.clip((r - Rs) / np.maximum(Rb - Rs, 1.0), 0.0, 1.0)
    y_bch = 34.0 + 4.4 * v ** 1.6 + 1.6 * smoothstep(0.8, 1.0, v) + 0.35 * fbm(X, Y, 40.0, 2, SEED + 23) * v
    # jungle: radial profile, folds radiating to the lagoon (sharp crests, round valleys on every 5 deg), noise
    Yr = mspline(r, JK_R, JK_Y)
    Yb = mspline(Rb, JK_R, JK_Y)
    y_jg = Yr + (40.0 - Yb) * (1.0 - smoothstep(Rb, Rb + 300.0, r))
    ramp = smoothstep(Rb, Rb + 160.0, r)
    bdeg = boundary_deg(th)
    c10 = sector_centre(10)
    a10 = angdiff(th, c10)
    d10 = r * np.abs(np.sin(np.radians(a10)))
    hw10 = mspline(r, [900, 1100, 1600, 2200, 2620], [90, 88, 105, 120, 132])
    utr = (1.0 - smoothstep(0.55 * hw10, hw10, d10)) * (np.abs(a10) < 60.0)
    warp = (2.3 * fbm(X, Y, 640.0, 3, SEED + 31) + 1.4 * fbm(X, Y, 230.0, 2, SEED + 32)) * smoothstep(0.8, 3.0, bdeg)
    p5 = 1.0 - np.abs(np.cos(np.radians(th + warp) * 36.0))
    p7 = 1.0 - np.abs(np.cos(np.radians(th + warp * 1.3) * 25.714))
    pm = smoothstep(-0.25, 0.25, fbm(X, Y, 900.0, 2, SEED + 33)) * smoothstep(0.8, 3.0, bdeg)
    p = p5 + (p7 - p5) * pm
    p = p * (0.55 + 0.45 * smoothstep(-0.5, 0.5, fbm(X, Y, 520.0, 3, SEED + 34)))
    Af = mspline(r, [1000, 1600, 2600, 2900, 3150, 3330, 3560], [6, 20, 34, 52, 110, 150, 120]) * ramp
    Af = Af * (1.0 + 0.45 * W[1] - 0.5 * W[2] - 0.65 * W[7]) * (1.0 - utr)
    An = mspline(r, [1000, 1600, 2600, 3000, 3560], [3, 9, 16, 30, 40]) * smoothstep(Rb - 20.0, Rb + 120.0, r)
    An = An * (1.0 - 0.5 * W[7]) * (1.0 - 0.7 * utr)
    y_jg = y_jg + Af * (p - 0.4) + An * fbm(X, Y, 420.0, 5, SEED + 41)
    # sector landforms
    y_jg = y_jg - 24.0 * wedge_w(th, 2, 6.0, 12.0) * rwin(r, 1250, 1500, 2100, 2450)          # 2: fog basin
    y_jg = y_jg + 18.0 * W[3] * rwin(r, 1350, 1550, 2050, 2300)                                 # 3: heights
    hol = wedge_w(th, 11, 5.0, 11.0) * rwin(r, 1250, 1420, 1720, 1900)
    y_jg = y_jg - 16.0 * hol                                                                    # 11: hollow
    lx, ly = LAYOUT["lightning"].x, LAYOUT["lightning"].y
    dlt = np.hypot(X - lx, Y - ly)
    y_jg = y_jg + 12.0 * np.exp(-dlt ** 2 / (2 * 65.0 ** 2))                                   # 12: knoll
    pin = np.zeros_like(r)
    for pp, ph, _ in LAYOUT["pinnacles"]:
        dd = np.hypot(X - pp.x, Y - pp.y)
        y_jg = y_jg + 8.0 * np.exp(-dd ** 2 / (2 * 28.0 ** 2))                                # 4: pinnacle bases
        pin = np.maximum(pin, 1.0 - smoothstep(22.0, 40.0, dd))
    y = np.where(r < Rs, y_lag, np.where(r < Rb, y_bch, y_jg))
    # 10: the wave's scoured trough (rim to beach)
    D10 = mspline(r, [1000, 1180, 1500, 2100, 2560, 2660], [0, 8, 26, 32, 30, 0])
    y = y - D10 * utr * smoothstep(Rs + 20.0, Rs + 120.0, r)
    # 6: the beast's ravine
    c6 = sector_centre(6) + 4.5 * np.sin(r / 170.0 + 1.3)
    a6 = angdiff(th, c6)
    d6 = r * np.abs(np.sin(np.radians(a6)))
    D6 = mspline(r, [1030, 1090, 1160, 1350, 1700, 2050, 2350, 2520], [0, 10, 22, 36, 48, 52, 30, 0]) * (
        np.abs(a6) < 60.0)
    prof6 = 1.0 - smoothstep(9.0, 9.0 + 0.55 * D6 + 6.0, d6)
    y = y - D6 * prof6
    # 5: the mud fan and its creek
    fan = W[5] * smoothstep(Rb + 280.0, Rb + 120.0, r) * (r > Rs)
    y_fan = 34.6 + 0.02 * (r - Rs) + 0.5 * fbm(X, Y, 60.0, 2, SEED + 51)
    y = y + (y_fan - y) * 0.85 * fan
    c5 = sector_centre(5) + 3.0 * np.sin(r / 120.0)
    d5 = r * np.abs(np.sin(np.radians(angdiff(th, c5))))
    creek = W[5] * rwin(r, Rs + 15.0, Rs + 40.0, 1750.0, 1850.0) * (1.0 - smoothstep(4.0, 9.0, d5))
    y = y - 2.2 * creek
    # 9: the reef shelf, awash
    shelf = W[9] * smoothstep(Rs - 95.0 - 25.0 * fbm(X, Y, 70.0, 2, SEED + 61), Rs - 60.0, r) * (r < Rs + 5.0)
    y_shelf = 33.3 + 1.2 * fbm(X, Y, 18.0, 3, SEED + 62)
    y = np.where(shelf > 0.02, np.maximum(y, y + (y_shelf - y) * shelf), y)
    # spokes: underwater rock ridge under every deck, the landing spur on the beach
    sdeg = spoke_deg(th)
    ds = r * np.sin(np.radians(sdeg))
    in_sp = (r > 105.0) & (r < Rs + 2.0)
    y = np.where(in_sp, np.maximum(y, 33.0 - 1.1 * np.maximum(ds - 6.0, 0.0)), y)
    in_spur = (r > Rs - 8.0) & (r < Rs + 80.0) & (ds < 14.0)
    spur_y = 35.7 + 0.03 * np.clip(r - Rs, 0, None) - 0.7 * np.maximum(ds - 5.5, 0.0)
    y = np.where(in_spur, np.maximum(y, spur_y), y)
    # island ramps: the 12 spoke corridors climb from the spoke deck to the plaza
    ramp_z = np.clip(35.3 + (124.0 - r) / 60.0 * 10.4, 35.3, 46.0)
    in_ramp = (r > 58.0) & (r < 132.0) & (ds < 8.0)
    y = np.where(in_ramp, np.minimum(y, ramp_z), y)
    # sector-line gullies (the 12 hour lines from the field to the beach), washes across the beach
    db = r * np.sin(np.radians(bdeg))
    g_on = smoothstep(Rb - 40.0, Rb + 20.0, r) * smoothstep(R + 40.0, R + 10.0, r)
    y = y - 4.5 * g_on * (1.0 - smoothstep(7.0, 18.0, db))
    wash = smoothstep(Rs + 70.0, Rs + 95.0, r) * smoothstep(Rb + 10.0, Rb - 30.0, r)
    y = y - 0.7 * wash * (1.0 - smoothstep(5.0, 11.0, db))
    # keep land outside the lagoon dry
    y = np.where((r > Rs + 3.0) & (y < 34.4), 34.4, y)
    # pools (levels are solved once, from the field without pools)
    pool_w = np.zeros_like(r)
    pool_level = np.full_like(r, -1e9)
    for pl in LAYOUT["pools"]:
        if pl["level"] is None:
            continue
        cx, cy = pl["centre"].x, pl["centre"].y
        dd = np.hypot(X - cx, Y - cy)
        rad = pl["radius"]
        bowl = pl["level"] - 3.8 * (1.0 - np.clip(dd / rad, 0, 1) ** 2)
        bank = 1.0 - smoothstep(rad, rad + 7.0, dd)
        y = np.where(dd < rad + 7.0, np.minimum(y, bowl + (y - bowl) * (1.0 - bank) + 0.0), y)
        inside = dd < rad + 1.5
        pool_level = np.where(inside, pl["level"], pool_level)
        pool_w = np.maximum(pool_w, inside.astype(np.float64))
    return dict(y=y, r=r, th=th, Rs=Rs, Rb=Rb, W=W, utr=utr, D6=D6, prof6=prof6, fan=fan, creek=creek, shelf=shelf,
                ds=ds, db=db, g_on=g_on, wash=wash, hol=hol, pin=pin, dlt=dlt, pool_w=pool_w, pool_level=pool_level,
                X=X, Y=Y)


def solve_pools():
    for pl in LAYOUT["pools"]:
        c = pl["centre"]
        a = np.linspace(0, TAU, 72, endpoint=False)
        ring = pl["radius"] + 6.0
        f = field_core(c.x + ring * np.sin(a), c.y + ring * np.cos(a))
        fc = field_core(np.array([c.x]), np.array([c.y]))
        pl["level"] = float(min(f["y"].min() - 0.8, fc["y"][0] + 1.5))
        pl["ground"] = float(fc["y"][0])
    log("POOLS", ", ".join("%s level %.1f" % (p["name"], p["level"]) for p in LAYOUT["pools"]))


def savanna_w(f):
    X, Y, r, Rb = f["X"], f["Y"], f["r"], f["Rb"]
    thj = f["th"] + 5.0 * fbm(X, Y, 300.0, 3, SEED + 80)
    w7 = wedge_w(thj, 7, 3.0, 12.5)
    core = rwin(r + 120.0 * fbm(X, Y, 400.0, 2, SEED + 82), Rb + 80.0, Rb + 260.0, R - 260.0, R - 60.0)
    return w7 * core * (0.75 + 0.5 * fbm(X, Y, 260.0, 3, SEED + 74)) + 0.25 * fbm(X, Y, 70.0, 3, SEED + 79)


def field_materials(f, slope):
    """Material slot index, tree density, region, sector and water depth for a field chunk."""
    X, Y, r, th, y = f["X"], f["Y"], f["r"], f["th"], f["y"]
    Rs, Rb, W = f["Rs"], f["Rb"], f["W"]
    mat = np.full(r.shape, SLOT["jungle"], np.uint8)
    mat[r < Rb] = SLOT["sand"]
    n1 = fbm(X, Y, 30.0, 2, SEED + 71)
    mat[(r >= Rs - 3.0) & (r < Rs + 22.0 + 6.0 * n1)] = SLOT["sand_wet"]
    mat[(r < Rs - 60.0) & (r > 200.0) & (fbm(X, Y, 160.0, 3, SEED + 72) > 0.32)] = SLOT["mud"]
    mat[(f["fan"] > 0.3) & (fbm(X, Y, 70.0, 3, SEED + 73) > -0.12)] = SLOT["mud"]
    mat[f["creek"] > 0.3] = SLOT["mud"]
    jungle = r >= Rb
    lat = (W[1] > 0.5) & (slope > 21.0) & (r > Rb + 60.0) & jungle
    for b, rr in LAYOUT["scars"]:
        pc = polar(b, rr)
        along = np.abs(r - rr)
        perp = np.hypot(X - pc.x, Y - pc.y)
        lat |= (along < 70.0 + 10.0 * n1) & (perp < 75.0) & (r * np.abs(np.sin(np.radians(angdiff(th, b)))) < 17.0)
    mat[lat] = SLOT["laterite"]
    sav_w = savanna_w(f)
    savanna = sav_w > 0.5
    mat[savanna & jungle] = SLOT["drygrass"]
    scour = (f["utr"] - 0.35 * smoothstep(Rb + 60.0, Rb + 260.0, r) + 0.25 * fbm(X, Y, 45.0, 3, SEED + 76)) > 0.72
    mat[scour & (r > Rs) & (r < Rb + 300.0)] = SLOT["sand"]
    rock = jungle & (slope > 36.0)
    rock |= (f["D6"] > 6.0) & (f["prof6"] > 0.12) & (f["prof6"] < 0.88) & (slope > 30.0)
    rock |= f["pin"] > 0.2
    rock |= (r > 3000.0) & (slope > 28.0)
    for pp, rot, sc in LAYOUT["slabs"]:
        rock |= np.hypot(X - pp.x, Y - pp.y) < 9.0 * sc
    mat[rock] = SLOT["rock"]
    mat[(f["D6"] > 6.0) & (f["prof6"] >= 0.88)] = SLOT["mud"]
    c6 = sector_centre(6) + 4.5 * np.sin(r / 170.0 + 1.3)
    d6 = r * np.abs(np.sin(np.radians(angdiff(th, c6))))
    mat[(r > Rs - 4.0) & (r < Rb + 30.0) & (d6 < 10.0 + (Rb + 30.0 - r) * 0.22) & (np.abs(angdiff(th, c6)) < 20)
        & (fbm(X, Y, 25.0, 2, SEED + 83) > -0.35)] = SLOT["mud"]
    mat[(f["hol"] > 0.6) & (fbm(X, Y, 50.0, 2, SEED + 75) > 0.05)] = SLOT["mud"]
    mat[(f["db"] < 9.0) & (f["g_on"] > 0.5)] = SLOT["salt"]
    mat[(f["db"] < 6.0) & (f["wash"] > 0.5)] = SLOT["salt"]
    lava = r < 128.0
    lava |= (r > 105.0) & (r < Rs + 2.0) & (f["ds"] < 9.5)
    lava |= (r > Rs - 8.0) & (r < Rs + 78.0) & (f["ds"] < 8.0)
    lava |= f["shelf"] > 0.5
    mat[lava] = SLOT["lava"]
    mat[np.abs(r - R) < 6.0] = SLOT["seared"]
    mat[f["dlt"] < 48.0] = SLOT["seared"]
    mat[f["pool_w"] > 0.5] = SLOT["mud"]
    # tree density (0..1) for the canopy scatter
    dens = np.where(r >= Rb + 20.0, 1.0, 0.0)
    dens *= smoothstep(10.0, 16.0, f["db"]) * (f["g_on"] > 0.0) + (f["g_on"] <= 0.0)
    dens *= smoothstep(8.0, 30.0, np.abs(r - R))
    dens *= 1.0 - 0.9 * smoothstep(0.35, 0.65, sav_w)
    dens *= 1.0 - 0.8 * f["utr"] * (r < R + 50.0) * smoothstep(-0.4, 0.2, fbm(X, Y, 70.0, 3, SEED + 78))
    dens *= 1.0 - 0.9 * smoothstep(0.45, 0.75, f["utr"]) * smoothstep(Rb + 700.0, Rb + 400.0, r)
    dens *= 1.0 - 0.45 * wedge_w(th, 2, 6.0, 12.0) * rwin(r, 1250, 1500, 2100, 2450) * smoothstep(
        -0.3, 0.3, fbm(X, Y, 90.0, 3, SEED + 77))
    dens *= 1.0 - 0.85 * f["fan"]
    dens *= np.where(lat, np.where(slope > 21.0, 0.3, 0.05), 1.0)
    dens *= np.where(f["dlt"] < 60.0, 0.0, 1.0)
    dens *= 1.0 - smoothstep(0.0, 0.2, f["pin"])
    dens *= np.where((f["D6"] > 4.0) & (f["prof6"] > 0.2), 0.0, 1.0)
    dens *= np.where(rock, 0.25, 1.0)
    dens *= np.where(f["pool_w"] > 0.0, 0.0, 1.0)
    dens *= np.where(r > R + FIELD_VISUAL, 0.75, 1.0)
    # region
    reg = np.full(r.shape, 5, np.uint8)
    reg[r < Rb] = 4
    reg[r < Rs] = 2
    reg[(r > 115.0) & (r < Rs) & (f["ds"] < SPOKE_W / 2.0)] = 3
    reg[r < 125.0] = 1
    reg[np.abs(r - R) <= 6.0] = 6
    reg[(r > R + 6.0) & (r <= R + FIELD_VISUAL)] = 7
    reg[r > R + FIELD_VISUAL] = 8
    # sector (hour 1..12; 13 = the island; 0 = outside the field)
    sec = hour_of(th).astype(np.uint8)
    sec[r < 125.0] = 13
    sec[r > R + 6.0] = 0
    # water depth (lagoon + pools)
    depth = np.where(r < Rs + 5.0, np.clip(WATER - y, 0, None), 0.0)
    depth = np.maximum(depth, np.where(f["pool_w"] > 0.5, np.clip(f["pool_level"] - y, 0, None), 0.0))
    return dict(mat=mat, dens=np.clip(dens, 0, 1), reg=reg, sec=sec, depth=depth)


def field_grid(cell, half, want_aux=False):
    """Evaluate the field on a square grid of cell centres; row 0 = north edge, col 0 = west edge."""
    n = int(round(2 * half / cell))
    xs = -half + cell * (np.arange(n) + 0.5)
    ys = half - cell * (np.arange(n) + 0.5)
    Ygrid = np.empty((n, n))
    step = max(64, int(250000 // n))
    for i0 in range(0, n, step):
        Xc, Yc = np.meshgrid(xs, ys[i0:i0 + step])
        Ygrid[i0:i0 + step] = field_core(Xc, Yc)["y"]
    gy, gx = np.gradient(Ygrid, cell)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    out = dict(y=Ygrid, slope=slope, mat=np.empty((n, n), np.uint8), dens=np.empty((n, n)), reg=np.empty((n, n), np.uint8),
               sec=np.empty((n, n), np.uint8), depth=np.empty((n, n)), cell=cell, half=half, n=n, xs=xs, ys=ys)
    for i0 in range(0, n, step):
        Xc, Yc = np.meshgrid(xs, ys[i0:i0 + step])
        f = field_core(Xc, Yc)
        m = field_materials(f, slope[i0:i0 + step])
        for k in ("mat", "dens", "reg", "sec", "depth"):
            out[k][i0:i0 + step] = m[k]
    return out


def grid_sample(G, key, X, Y, nearest=False):
    cell, half, n = G["cell"], G["half"], G["n"]
    fx = (np.asarray(X) + half) / cell - 0.5
    fy = (half - np.asarray(Y)) / cell - 0.5
    A = G[key]
    if nearest:
        return A[np.clip(np.round(fy).astype(int), 0, n - 1), np.clip(np.round(fx).astype(int), 0, n - 1)]
    x0 = np.clip(np.floor(fx).astype(int), 0, n - 2)
    y0 = np.clip(np.floor(fy).astype(int), 0, n - 2)
    tx = np.clip(fx - x0, 0, 1)
    ty = np.clip(fy - y0, 0, 1)
    a = A[y0, x0]
    b = A[y0, x0 + 1]
    c = A[y0 + 1, x0]
    d = A[y0 + 1, x0 + 1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


# =============================================================================================== mesh builder
class MB:
    """Faces with a base sRGB colour, a foliage flag and a volume id (painted at build time)."""

    def __init__(self):
        self.V, self.F, self.FC, self.FL, self.FVOL = [], [], [], [], []
        self.vol = 0

    def nv(self):
        self.vol += 1
        return self.vol

    def v(self, p):
        self.V.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.V) - 1

    def f(self, idx, col, leaf=0.0):
        idx = [int(i) for i in idx]
        if len(set(idx)) < 3:
            return
        self.F.append(idx)
        self.FC.append(col)
        self.FL.append(leaf)
        self.FVOL.append(self.vol)

    def fo(self, idx, col, outward, leaf=0.0):
        p = [Vector(self.V[i]) for i in idx]
        n = Vector((0, 0, 0))
        for i in range(1, len(p) - 1):
            n += (p[i] - p[0]).cross(p[i + 1] - p[0])
        if n.dot(Vector(outward)) < 0:
            idx = list(reversed(idx))
        self.f(idx, col, leaf)

    def mesh(self, verts, faces, col, leaf=0.0, new_vol=True):
        if new_vol:
            self.nv()
        base = len(self.V)
        for q in verts:
            self.v(q)
        for fc in faces:
            self.f([base + i for i in fc], col, leaf)

    def extend(self, other, mat=None):
        base = len(self.V)
        vb = self.vol
        for q in other.V:
            self.V.append(tuple(mat @ Vector(q)) if mat is not None else q)
        for fc, c, l, vo in zip(other.F, other.FC, other.FL, other.FVOL):
            self.F.append([base + i for i in fc])
            self.FC.append(c)
            self.FL.append(l)
            self.FVOL.append(vb + vo)
        self.vol = vb + other.vol

    def tris(self):
        return sum(len(fc) - 2 for fc in self.F)


PAINT_DEFAULT = dict(top=0.10, under=0.20, kv=0.06, kf=0.035, zg=0.10, warm=0.02)


def mb_object(mb, name, mat, coll, smooth=False, paint=None, seed=0):
    """Build a Blender mesh object; per-face painted colour in the corner attribute 'col' (linear), foliage 'lm'."""
    pr = dict(PAINT_DEFAULT)
    pr.update(paint or {})
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.V, [], mb.F)
    me.update(calc_edges=True)
    nP = len(me.polygons)
    if nP != len(mb.F):
        log("WARNING %s: %d faces built of %d" % (name, nP, len(mb.F)))
    me.polygons.foreach_set("use_smooth", np.full(nP, bool(smooth)))
    pn = np.empty(nP * 3, np.float32)
    me.polygons.foreach_get("normal", pn)
    pn = pn.reshape(-1, 3).astype(np.float64)
    pc = np.empty(nP * 3, np.float32)
    me.polygons.foreach_get("center", pc)
    pc = pc.reshape(-1, 3).astype(np.float64)
    base = np.array(mb.FC[:nP], np.float64)
    leaf = np.array(mb.FL[:nP], np.float64)
    vol = np.array(mb.FVOL[:nP], np.int64) + seed * 7919
    fid = np.arange(nP) + seed * 104729
    nz = pn[:, 2]
    shade = 1.0 + pr["top"] * np.clip(nz, 0, 1) - pr["under"] * np.clip(-nz, 0, 1)
    jit = 1.0 + pr["kv"] * (hashf(vol, 3) * 2 - 1) + pr["kf"] * (hashf(fid, 5) * 2 - 1)
    c = base * (shade * jit)[:, None]
    c = c + (pr["warm"] * 255.0 * (hashf(vol, 9) * 2 - 1))[:, None] * np.array([0.6, 0.2, -0.7])
    if pr["zg"] and nP:
        z = pc[:, 2]
        t = (z - z.min()) / max(z.max() - z.min(), 1e-6)
        c = c * (1.0 + pr["zg"] * leaf * (t - 0.5) * 2.0)[:, None]
    c = np.clip(c, 0, 255)
    lt = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_total", lt)
    rep = np.repeat(np.arange(nP), lt)
    lin = np.concatenate([s2l(c), np.ones((nP, 1))], axis=1)[rep]
    a = me.color_attributes.new("col", "FLOAT_COLOR", "CORNER")
    a.data.foreach_set("color", lin.astype(np.float32).ravel())
    me.color_attributes.active_color = a
    try:
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
    except Exception:
        pass
    a = me.attributes.new("lm", "FLOAT", "CORNER")
    a.data.foreach_set("value", leaf[rep].astype(np.float32))
    if mat is not None:
        me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    if coll is not None:
        coll.objects.link(obj)
    obj["rgb"] = [int(round(v)) for v in (l2s(s2l(c).mean(0)) * 255.0)] if nP else [128, 128, 128]
    obj["tris"] = int(sum(len(fc) - 2 for fc in mb.F))
    return obj


# =============================================================================================== primitives
def frames(path):
    P = [Vector(p) for p in path]
    n = len(P)
    T = []
    for i in range(n):
        t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)])
        T.append(t.normalized() if t.length > 1e-9 else Vector((0, 0, 1)))
    ref = Vector((1, 0, 0)) if abs(T[0].x) < 0.9 else Vector((0, 1, 0))
    N = (ref - T[0] * ref.dot(T[0])).normalized()
    out = []
    for i in range(n):
        if i > 0:
            N = (N - T[i] * N.dot(T[i]))
            N = N.normalized() if N.length > 1e-9 else out[-1][1]
        out.append((T[i], N, T[i].cross(N)))
    return P, out


def tube(mb, path, radii, sides, col, cap0=True, cap1=True, apex=None, rot0=0.0, rjit=0.0, rng=None, leaf=0.0,
         squash=None, new_vol=True):
    if new_vol:
        mb.nv()
    P, fr = frames(path)
    rings = []
    for i, p in enumerate(P):
        T, N, B = fr[i]
        sx, sy = squash[i] if squash else (1.0, 1.0)
        ring = []
        for j in range(sides):
            a = rot0 + TAU * j / sides
            rr = radii[i] * (1.0 + (rng.uniform(-rjit, rjit) if rjit else 0.0))
            ring.append(mb.v(p + (N * math.cos(a) * sx + B * math.sin(a) * sy) * rr))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            mb.f((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]), col, leaf)
    if cap0:
        mb.f(list(reversed(rings[0])), col, leaf)
    if apex is not None:
        c = mb.v(apex)
        for j in range(sides):
            mb.f((rings[-1][j], rings[-1][(j + 1) % sides], c), col, leaf)
    elif cap1:
        mb.f(rings[-1], col, leaf)
    return rings


def hull(points, dissolve_deg=1.5):
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in points]
    bmesh.ops.convex_hull(bm, input=vs)
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.01)
    if dissolve_deg:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve_deg), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.verts.index_update()
    verts = [v.co.copy() for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return verts, faces


def blob_points(rng, a, b, c, n=22, p=2.4, rj=0.08):
    pts = []
    for _ in range(n):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if d.length < 1e-6:
            continue
        d.normalize()
        rr = 1.0 / ((abs(d.x / a) ** p + abs(d.y / b) ** p + abs(d.z / c) ** p) ** (1.0 / p))
        pts.append(d * rr * rng.uniform(1.0 - rj, 1.0 + rj * 0.4))
    return pts


def cut(pts, nrm, frac):
    nrm = Vector(nrm).normalized()
    ext = max(q.dot(nrm) for q in pts)
    off = ext * frac
    return [q - nrm * (q.dot(nrm) - off) if q.dot(nrm) > off else q.copy() for q in pts]


def lobe(mb, rng, centre, rx, ry, rz, col, n=22, flat=0.55, leaf=1.0, yaw=None):
    pts = blob_points(rng, rx, ry, rz, n=n, p=2.2, rj=0.12)
    pts = cut(pts, (0, 0, -1), flat)
    if yaw is None:
        yaw = rng.uniform(0, TAU)
    rot = Matrix.Rotation(yaw, 3, "Z")
    v, f = hull([rot @ q for q in pts])
    mb.mesh([Vector(centre) + q for q in v], f, col, leaf)


def rock(mb, rng, centre, a, b, c, col, n=16, cuts=3, flat_bottom=0.5, flat_top=None, yaw=None, tilt=0.0):
    pts = blob_points(rng, a, b, c, n=n, p=2.2, rj=0.1)
    for _ in range(cuts):
        nv = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1))).normalized()
        pts = cut(pts, nv, rng.uniform(0.72, 0.88))
    pts = cut(pts, (0, 0, -1), flat_bottom)
    if flat_top:
        pts = cut(pts, (0, 0, 1), flat_top)
    rot = Matrix.Rotation(rng.uniform(0, TAU) if yaw is None else yaw, 3, "Z")
    if tilt:
        rot = rot @ Matrix.Rotation(rng.uniform(-tilt, tilt), 3, "X")
    v, f = hull([rot @ q for q in pts])
    mb.mesh([Vector(centre) + q for q in v], f, col)


def cbox(mb, centre, size, col, ch=0.12, yaw=0.0, leaf=0.0, rot=None):
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    ch = min(ch, sx * 0.45, sy * 0.45, sz * 0.45)
    pts = []
    for ix in (-1, 1):
        for iy in (-1, 1):
            for iz in (-1, 1):
                pts += [Vector((ix * (sx - ch), iy * sy, iz * sz)), Vector((ix * sx, iy * (sy - ch), iz * sz)),
                        Vector((ix * sx, iy * sy, iz * (sz - ch)))] if ch > 0.001 else [Vector((ix * sx, iy * sy, iz * sz))]
    R3 = rot if rot is not None else Matrix.Rotation(yaw, 3, "Z")
    v, f = hull([R3 @ q for q in pts], dissolve_deg=0.5)
    mb.mesh([Vector(centre) + q for q in v], f, col, leaf)


def hexcol(mb, cx, cy, z0, z1, rad, col, rot=0.0, tilt=(0.0, 0.0)):
    mb.nv()
    b = [mb.v((cx + rad * math.cos(rot + TAU * k / 6), cy + rad * math.sin(rot + TAU * k / 6), z0)) for k in range(6)]
    t = []
    for k in range(6):
        x = cx + rad * math.cos(rot + TAU * k / 6)
        y = cy + rad * math.sin(rot + TAU * k / 6)
        t.append(mb.v((x, y, z1 + tilt[0] * (x - cx) + tilt[1] * (y - cy))))
    for k in range(6):
        mb.f((b[k], b[(k + 1) % 6], t[(k + 1) % 6], t[k]), col)
    mb.f(t, col)


def frond(mb, base, az, elev_deg, tip_deg, L, Wd, col, segs=9, serr=0.55, thick=0.22, fold=0.42, leaf=1.0):
    """Arching folded strip (palm/fern frond, big leaf): a closed thin wedge with a zig-zag outline. No cards."""
    mb.nv()
    h = Vector((math.cos(az), math.sin(az), 0.0))
    side = Vector((-math.sin(az), math.cos(az), 0.0))
    up = Vector((0, 0, 1))
    p = Vector(base)
    a0, a1 = math.radians(elev_deg), math.radians(tip_deg)
    spine, left, right, under = [], [], [], []
    for i in range(segs + 1):
        t = i / segs
        phi = a0 + (a1 - a0) * t ** 1.4
        if i > 0:
            p = p + (h * math.cos(phi) + up * math.sin(phi)) * (L / segs)
        nrm = -h * math.sin(phi) + up * math.cos(phi)
        w = Wd * math.sin(math.pi * min(t * 1.12, 1.0)) ** 0.7
        if serr and 0 < i < segs and i % 2 == 1:
            w *= (1.0 - serr * 0.5)
        si = mb.v(p)
        spine.append(si)
        if w < 1e-3:
            left.append(si)
            right.append(si)
            under.append(si)
        else:
            left.append(mb.v(p + side * w - nrm * w * fold))
            right.append(mb.v(p - side * w - nrm * w * fold))
            under.append(mb.v(p - nrm * thick))
        spine_n = nrm
    for i in range(segs):
        ph = a0 + (a1 - a0) * ((i + 0.5) / segs) ** 1.4
        nrm = -h * math.sin(ph) + up * math.cos(ph)
        mb.fo((spine[i], spine[i + 1], left[i + 1], left[i]), col, nrm + side * 0.2, leaf)
        mb.fo((spine[i], right[i], right[i + 1], spine[i + 1]), col, nrm - side * 0.2, leaf)
        mb.fo((under[i], left[i], left[i + 1], under[i + 1]), col, -nrm + side * 0.2, leaf)
        mb.fo((under[i], under[i + 1], right[i + 1], right[i]), col, -nrm - side * 0.2, leaf)
    return p


# =============================================================================================== landmark builders
def shard(mb, pts, ups, ws, ths, col, tip0=0.0, tip1=0.0, rot=0.0):
    """A faceted crystal shard along pts: flattened 6-sided section oriented by ups (radial), optional pointed ends."""
    mb.nv()
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        T = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        U = (ups[i] - T * ups[i].dot(T)).normalized()
        V = T.cross(U)
        c, s_ = math.cos(rot), math.sin(rot)
        U, V = U * c + V * s_, V * c - U * s_
        w, th = ws[i] / 2.0, ths[i] / 2.0
        sec = [(w, 0.0), (w * 0.45, th), (-w * 0.5, th * 0.92), (-w, 0.0), (-w * 0.45, -th), (w * 0.5, -th * 0.9)]
        rings.append([mb.v(p + V * a + U * b) for a, b in sec])
    for i in range(n - 1):
        for j in range(6):
            mb.f((rings[i][j], rings[i][(j + 1) % 6], rings[i + 1][(j + 1) % 6], rings[i + 1][j]), col)
    for end, ring, sgn, tip in ((0, rings[0], -1, tip0), (n - 1, rings[-1], 1, tip1)):
        T = (pts[min(end + 1, n - 1)] - pts[max(end - 1, 0)]).normalized() * sgn
        if tip > 0:
            a = mb.v(pts[end] + T * tip + ups[end] * (tip * 0.15))
            for j in range(6):
                mb.f((ring[j], ring[(j + 1) % 6], a) if sgn > 0 else (ring[(j + 1) % 6], ring[j], a), col)
        else:
            mb.f(ring if sgn > 0 else list(reversed(ring)), col)


def build_horn(seed=SEED + 300):
    """The horn as a broken steel crystal: 10 staves of 2-3 faceted shards each form a curved horn (mouth south / -Y,
    tail north / +Y, curling up); 5 chunky shards bloom at the mouth; 3 girders lie splayed on the deck (the film's
    read). Stepped basalt floor, racks and crates inside."""
    rng = random.Random(seed)
    steel, floor, props = MB(), MB(), MB()
    col = PAL["horn"]

    def axis(t):
        y = -44.0 + 90.0 * t
        tt = max(t, 0.0)
        zc = 19.0 - 12.0 * tt + 9.0 * tt ** 3
        rad = 21.5 * (1.0 - tt) ** 0.85 + 1.6 + max(-t, 0.0) * 14.0
        return y, zc, rad
    for k, phi0 in enumerate([-128, -100, -72, -44, -16, 12, 40, 68, 96, 124]):
        phi = math.radians(phi0 + rng.uniform(-5, 5))
        t0, t1 = rng.uniform(-0.1, 0.02), rng.uniform(0.80, 0.96)
        nb = rng.choice((2, 3, 3))
        cuts = sorted(rng.uniform(0.2, 0.8) for _ in range(nb - 1))
        bounds = [t0] + [t0 + (t1 - t0) * c for c in cuts] + [t1]
        for sgi in range(nb):
            a, b = bounds[sgi] + (0.006 if sgi else 0.0), bounds[sgi + 1] - (0.006 if sgi < nb - 1 else 0.0)
            m = 4
            pts, ups, ws, ths = [], [], [], []
            dr = rng.uniform(-0.8, 0.9)
            dphi = math.radians(rng.uniform(-2.5, 2.5))
            for i in range(m + 1):
                t = a + (b - a) * i / m
                y, zc, rad = axis(t)
                rr = rad + dr + max(0.0, 0.1 - t) * 10.0
                ph = phi + dphi
                pts.append(Vector((rr * math.sin(ph), y, zc + rr * math.cos(ph))))
                ups.append(Vector((math.sin(ph), 0.0, math.cos(ph))))
                tt = max(t, 0.0)
                ws.append(9.0 * (1.0 - 0.58 * tt) * rng.uniform(0.93, 1.07))
                ths.append(4.6 * (1.0 - 0.5 * tt))
            tip0 = rng.uniform(4.0, 8.0) if sgi == 0 else rng.uniform(0.0, 1.6)
            shard(steel, pts, ups, ws, ths, col, tip0=tip0, tip1=0.0 if sgi < nb - 1 else rng.uniform(0, 3),
                  rot=rng.uniform(-0.12, 0.12))
    for k in range(5):
        phi = math.radians(-100 + 200 * k / 4 + rng.uniform(-10, 10))
        t = rng.uniform(0.02, 0.14)
        y, zc, rad = axis(t)
        p0 = Vector((rad * math.sin(phi), y, zc + rad * math.cos(phi)))
        out = Vector((math.sin(phi), 0.0, math.cos(phi)))
        d = (out * rng.uniform(0.8, 1.1) + Vector((0, -rng.uniform(0.35, 0.7), 0.35))).normalized()
        Ls = rng.uniform(18, 28)
        pts = [p0 - d * 4.0, p0 + d * (Ls * 0.4), p0 + d * (Ls * 0.75)]
        ups = [out.cross(d).normalized()] * 3
        w0 = rng.uniform(6.0, 8.5)
        shard(steel, pts, ups, [w0, w0 * 0.85, w0 * 0.6], [w0 * 0.5, w0 * 0.45, w0 * 0.35], col, tip0=0.0,
              tip1=Ls * 0.3, rot=rng.uniform(0, 1.0))
    # tail spike curling up
    tail = []
    for i in range(6):
        t = 0.84 + 0.2 * i / 5
        y, zc, rad = axis(min(t, 1.0))
        tail.append(Vector((0.0, y + (t - 1.0) * 30.0 * (t > 1.0), zc + max(t - 0.95, 0) * 60.0)))
    tube(steel, tail[:-1], [3.2, 2.8, 2.3, 1.8, 1.2], 5, col, cap0=True, apex=tail[-1] + Vector((0, 4.0, 7.0)))
    # girders lying splayed on the deck either side of the mouth
    for sgn in (-1, 1):
        for k in range(2 if sgn < 0 else 1):
            a = math.radians(sgn * rng.uniform(50, 75))
            d = Vector((math.sin(a) * sgn * sgn, -math.cos(a), 0.0))
            d = Vector((sgn * abs(math.sin(a)), -abs(math.cos(a)), 0.0))
            p0 = Vector((sgn * rng.uniform(16, 22), rng.uniform(-38, -22), 1.6))
            Lg = rng.uniform(26, 40)
            lift = rng.uniform(2.0, 6.0)
            tube(steel, [p0, p0 + d * Lg * 0.5 + Vector((0, 0, lift * 0.5)), p0 + d * Lg + Vector((0, 0, lift))],
                 [1.8, 1.7, 1.5], 4, col, rot0=math.pi / 4)
    # stepped basalt floor (jointed slabs)
    fl = PAL["basalt_floor"]
    for (x0, x1, y0, y1, z0, z1, nx, ny) in ((-27, 27, -54, 50, -0.4, 0.8, 3, 5), (-19, 19, -42, 36, 0.8, 1.6, 2, 4)):
        for i in range(nx):
            for j in range(ny):
                ax0 = x0 + (x1 - x0) * i / nx
                ax1 = x0 + (x1 - x0) * (i + 1) / nx
                ay0 = y0 + (y1 - y0) * j / ny
                ay1 = y0 + (y1 - y0) * (j + 1) / ny
                cbox(floor, ((ax0 + ax1) / 2, (ay0 + ay1) / 2, (z0 + z1) / 2 + rng.uniform(-0.04, 0.04)),
                     (ax1 - ax0 - 0.3, ay1 - ay0 - 0.3, z1 - z0), fl, ch=0.15)
    # racks (A-frames with long weapons) and crates
    for sgn in (-1, 1):
        for k in range(2):
            y0 = -30 + k * 16
            x = sgn * 12.5
            for dy in (0.0, 7.0):
                cbox(props, (x, y0 + dy, 4.0), (0.35, 0.35, 4.8), PAL["rack_wood"], ch=0.06,
                     rot=Matrix.Rotation(math.radians(12 * sgn), 3, "Y"))
            cbox(props, (x, y0 + 3.5, 5.6), (0.3, 7.6, 0.3), PAL["rack_wood"], ch=0.05)
            cbox(props, (x, y0 + 3.5, 3.0), (0.3, 7.6, 0.3), PAL["rack_wood"], ch=0.05)
            for w in range(4):
                cbox(props, (x - sgn * 0.6, y0 + 1.0 + w * 1.7, 4.2), (0.18, 0.18, 5.6), PAL["steel_band"], ch=0.03,
                     rot=Matrix.Rotation(math.radians(-14 * sgn), 3, "Y"))
    for k in range(8):
        cx = rng.uniform(-9, 9)
        cy = rng.uniform(-36, 8)
        cbox(props, (cx, cy, 1.6 + 1.1), (4.0, 2.6, 2.2), PAL["crate"], ch=0.12, yaw=rng.uniform(0, TAU))
    return [("Steel", steel, "metal"), ("Floor", floor, "paint"), ("Racks", props, "paint")]


def build_island_deck(seed=SEED + 301):
    """Hexagonal basalt pavers round the horn floor (deck level = 0 = y 46)."""
    rng = random.Random(seed)
    mb = MB()
    a = 4.6
    dx, dy = 1.5 * a, math.sqrt(3) * a
    for i in range(-12, 13):
        for j in range(-12, 13):
            cx = i * dx
            cy = j * dy + (dy / 2 if i % 2 else 0.0)
            rr = math.hypot(cx, cy)
            if rr > PLAZA_R - 1.5 or (abs(cx) < 27.5 and -54.5 < cy < 50.5):
                continue
            col = tuple(np.array(PAL["lava_top"]) * rng.uniform(0.94, 1.06))
            hexcol(mb, cx, cy, -1.2, 0.25 + rng.uniform(-0.06, 0.06), a - 0.16, col, rot=0.0)
    return [("Paving", mb, "paint")]


def build_island_ring(seed=SEED + 302):
    """Tumbled basalt round the island (origin: island centre at the waterline, y 34), 12 stepped ramps."""
    rng = random.Random(seed)
    segs = [MB() for _ in range(6)]
    stepsets = [MB() for _ in range(3)]
    z_top = lambda r: float(np.interp(r, [62, 80, 100, 115, 128, 136], [12.6, 10.6, 7.0, 3.2, 0.6, -1.2]))
    placed = []
    tries = 0
    while len(placed) < 560 and tries < 40000:
        tries += 1
        r = math.sqrt(rng.uniform(64 ** 2, 136 ** 2))
        b = rng.uniform(0, 360)
        sd = min(b % 30.0, 30.0 - b % 30.0)
        if r * math.sin(math.radians(sd)) < 7.0 + 2.0 * (r < 120):
            continue
        a = rng.uniform(3.2, 7.5)
        p = polar(b, r)
        if any((p - q).length < (a + qa) * 0.48 for q, qa in placed):
            continue
        placed.append((p, a))
        top = z_top(r) + rng.uniform(-1.2, 1.8)
        c = rng.uniform(2.6, 4.6)
        k = int((b % 360.0) // 60.0)
        col = PAL["lava"]
        rock(segs[k], rng, (p.x, p.y, top - c * 0.8), a, a * rng.uniform(0.6, 0.95), c, col, n=15, cuts=3,
             flat_bottom=0.6, flat_top=rng.uniform(0.82, 0.95) if rng.random() < 0.45 else None, tilt=0.25)
    for h in range(12):
        steps = stepsets[h // 4]
        bb = 30.0 * h
        u = polar(bb, 1.0)
        side = Vector((u.y, -u.x, 0.0))
        nst = 16
        for s in range(nst):
            r0 = 124.0 - 60.0 * s / nst
            r1 = 124.0 - 60.0 * (s + 1) / nst
            ztop = 1.6 + 10.4 * (s + 1) / nst
            c = u * ((r0 + r1) / 2)
            cbox(steps, (c.x, c.y, ztop - 1.0), (SPOKE_W, (r0 - r1) + 0.25, 2.0), PAL["lava"], ch=0.12,
                 yaw=-math.radians(bb))
        for sgn in (-1, 1):
            for s in range(5):
                rr = 70.0 + 12.0 * s
                q = u * rr + side * sgn * (SPOKE_W / 2 + 1.6)
                zt = 1.6 + 10.4 * (124.0 - rr) / 60.0 + 0.6
                rock(steps, rng, (q.x, q.y, zt - 1.6), 1.7, 3.6, 1.7, PAL["lava"], n=12, cuts=2, flat_top=0.8)
    parts = [("Rock_%d" % (k + 1), m, "paint") for k, m in enumerate(segs)]
    parts += [("Steps_%d" % (k + 1), m, "paint") for k, m in enumerate(stepsets)]
    return parts


def build_spoke_module(seed, length=40.0):
    """A 40-stud causeway module: hex basalt column tops (the walkable deck, top at 0 = y 35.6) and tumbled
    blocks down both sides into the water. Local +Y = outward along the spoke."""
    rng = random.Random(seed)
    deck, rocks = MB(), MB()
    n_y = 18
    a = length / (math.sqrt(3) * n_y)
    for i in range(-2, 3):
        cx = i * 1.5 * a
        for j in range(n_y):
            cy = -length / 2 + (j + 0.5) * math.sqrt(3) * a + (math.sqrt(3) * a / 2 if i % 2 else 0.0)
            if cy > length / 2:
                cy -= length
            top = rng.uniform(-0.16, 0.10)
            col = tuple(np.array(PAL["lava_top"]) * rng.uniform(0.92, 1.05))
            hexcol(deck, cx, cy, -4.0, top, a - 0.07, col, rot=0.0,
                   tilt=(rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02)))
    for sgn in (-1, 1):
        y = -length / 2 + rng.uniform(0, 2)
        while y < length / 2:
            sz = rng.uniform(2.6, 4.4)
            x = sgn * (SPOKE_W / 2 + rng.uniform(0.8, 2.6))
            top = rng.uniform(-1.6, -0.35)
            rock(rocks, rng, (x, y, top - sz * 0.6), sz * rng.uniform(0.7, 1.0), sz, sz * 0.75,
                 PAL["lava"] if rng.random() < 0.8 else PAL["lava_top"], n=14, cuts=3, flat_bottom=0.6,
                 flat_top=0.85)
            y += sz * rng.uniform(1.1, 1.5)
    return [("Deck", deck, "paint"), ("Rock", rocks, "paint")]


def build_spur(seed=SEED + 320):
    """The spoke's landing: a low basalt spur rising from the shoreline into the beach (local +Y inland)."""
    rng = random.Random(seed)
    mb = MB()
    a = 1.25
    for j in range(16):
        y = j * math.sqrt(3) * a
        for i in range(-2, 3):
            x = i * 1.5 * a
            yy = y + (math.sqrt(3) * a / 2 if i % 2 else 0.0)
            if rng.random() < 0.08 + 0.04 * j:
                continue
            top = 0.03 * yy + rng.uniform(-0.2, 0.15)
            hexcol(mb, x, yy, -3.5, top, a - 0.07, tuple(np.array(PAL["lava_top"]) * rng.uniform(0.92, 1.05)))
    for k in range(26):
        y = rng.uniform(0, 75)
        wdt = 6.0 + y * 0.08
        x = rng.choice((-1, 1)) * rng.uniform(4.5, wdt)
        s = rng.uniform(1.8, 3.8) * (1.3 if y > 35 else 1.0)
        rock(mb, rng, (x, y, 0.03 * y - s * 0.55), s, s * rng.uniform(0.7, 1.0), s * 0.7, PAL["lava"], n=14,
             cuts=3, flat_top=0.85)
    return [("Rock", mb, "paint")]


def build_plate(seed=SEED + 330):
    """Launch plate in the lagoon: steel drum with a copper top on a fluted column, a float collar with a brass rim.
    Origin at the waterline (y 34); the top is at +2 (y 36)."""
    steel, copper, collar = MB(), MB(), MB()
    S = PAL["plate_steel"]
    n = 16
    steel.nv()
    b = [steel.v((2.15 * math.cos(TAU * k / n), 2.15 * math.sin(TAU * k / n), 0.35)) for k in range(n)]
    m = [steel.v((2.15 * math.cos(TAU * k / n), 2.15 * math.sin(TAU * k / n), 1.86)) for k in range(n)]
    t = [steel.v((1.98 * math.cos(TAU * k / n), 1.98 * math.sin(TAU * k / n), 2.0)) for k in range(n)]
    for k in range(n):
        k1 = (k + 1) % n
        steel.f((b[k], b[k1], m[k1], m[k]), S)
        steel.f((m[k], m[k1], t[k1], t[k]), S)
    steel.f(list(reversed(b)), S)
    copper.nv()
    ct = [copper.v((1.98 * math.cos(TAU * k / n), 1.98 * math.sin(TAU * k / n), 2.0)) for k in range(n)]
    copper.f(ct, PAL["plate_copper"])
    pts = []
    for k in range(24):
        rr = 1.2 if k % 2 == 0 else 1.04
        pts.append((rr * math.cos(TAU * k / 24), rr * math.sin(TAU * k / 24)))
    steel.nv()
    lo = [steel.v((x, y, -28.0)) for x, y in pts]
    hi = [steel.v((x, y, 0.4)) for x, y in pts]
    for k in range(24):
        steel.f((lo[k], lo[(k + 1) % 24], hi[(k + 1) % 24], hi[k]), S)
    collar.nv()
    n2 = 24
    rings = []
    for (rr, z) in ((2.6, -0.35), (4.2, -0.35), (4.2, 0.30), (3.9, 0.45), (2.6, 0.45)):
        rings.append([collar.v((rr * math.cos(TAU * k / n2), rr * math.sin(TAU * k / n2), z)) for k in range(n2)])
    for i in range(len(rings)):
        j = (i + 1) % len(rings)
        c = PAL["brass"] if i in (2, 3) else PAL["collar"]
        for k in range(n2):
            collar.f((rings[i][k], rings[i][(k + 1) % n2], rings[j][(k + 1) % n2], rings[j][k]), c)
    return [("Steel", steel, "metal"), ("Copper", copper, "metal"), ("Collar", collar, "paint")]


def build_lightning_tree(seed=SEED + 340):
    """180-stud dead giant: bleached, buttressed, three massive limbs, a dark lightning scar down one side."""
    rng = random.Random(seed)
    bark, scar = MB(), MB()
    col = PAL["deadwood"]
    path = [(0, 0, 0), (0.4, 0.2, 30), (0.9, -0.3, 70), (1.3, -0.6, 104), (1.6, -0.4, 118)]
    radii = [8.6, 6.4, 5.2, 4.4, 4.0]
    tube(bark, path, radii, 9, col, cap0=False, cap1=True, rjit=0.05, rng=rng)
    for k in range(5):
        a = TAU * k / 5 + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        s = Vector((-d.y, d.x, 0))
        pts = [d * 6.0 + s * 1.0, d * 6.0 - s * 1.0, d * 6.6 + s * 0.9 + Vector((0, 0, 18)),
               d * 6.6 - s * 0.9 + Vector((0, 0, 18)), d * 16.0 + s * 0.8, d * 16.0 - s * 0.8,
               d * 15.0 + Vector((0, 0, 2.5)), d * 5.0]
        v, f = hull(pts)
        bark.mesh(v, f, col)
    top = Vector(path[-1])
    limb_tips = []
    for k in range(3):
        a = TAU * k / 3 + rng.uniform(-0.3, 0.3)
        el = math.radians(rng.uniform(48, 64))
        Lb = rng.uniform(42, 56)
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        mid = top + d * Lb * 0.5 + Vector((0, 0, 3))
        end = top + d * Lb
        tube(bark, [top - d * 3, mid, end], [3.4, 2.4, 1.5], 7, col, rjit=0.04, rng=rng)
        limb_tips.append((end, d))
    for end, d in limb_tips:
        for j in range(3):
            a = math.atan2(d.y, d.x) + rng.uniform(-1.0, 1.0)
            el = math.radians(rng.uniform(25, 72))
            e = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
            Lc = rng.uniform(12, 24)
            q = end + e * Lc
            tube(bark, [end - e * 1.5, end + e * Lc * 0.6, q], [1.5, 1.0, 0.6], 6, col)
            for k2 in range(2):
                a2 = a + rng.uniform(-0.8, 0.8)
                el2 = math.radians(rng.uniform(15, 65))
                e2 = Vector((math.cos(a2) * math.cos(el2), math.sin(a2) * math.cos(el2), math.sin(el2)))
                L2 = rng.uniform(5, 11)
                tube(bark, [q - e2 * 0.6, q + e2 * L2], [0.6, 0.3], 5, col)
    for k in range(6):
        z = rng.uniform(40, 100)
        a = rng.uniform(0, TAU)
        e = Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, 0.35)).normalized()
        rr = float(np.interp(z, [0, 30, 70, 104, 118], [8.6, 6.4, 5.2, 4.4, 4.0]))
        p0 = Vector((math.cos(a) * rr * 0.6, math.sin(a) * rr * 0.6, z))
        tube(bark, [p0, p0 + e * rng.uniform(5, 9)], [1.2, 0.8], 6, col)
    # lightning scar: a strip of dark split bark spiralling down the trunk
    for i in range(14):
        z = 150 - i * 9.5
        tt = min(z / 118.0, 1.0)
        rr = float(np.interp(z, [0, 30, 70, 104, 118, 180], [8.6, 6.4, 5.2, 4.4, 4.0, 2.2])) + 0.35
        a = 0.9 + i * 0.16
        cx = float(np.interp(z, [0, 30, 70, 104, 118], [0, 0.4, 0.9, 1.3, 1.6]))
        cy = float(np.interp(z, [0, 30, 70, 104, 118], [0, 0.2, -0.3, -0.6, -0.4]))
        if z > 118:
            continue
        p = Vector((cx + rr * math.cos(a), cy + rr * math.sin(a), z))
        cbox(scar, p, (1.4, 1.7, 10.5), PAL["char"], ch=0.2, yaw=a)
    return [("Bark", bark, "paint"), ("Scar", scar, "paint")]


def build_pinnacle(seed, H):
    """Basalt sea-stack: jointed column cluster with a skirt of fallen blocks."""
    rng = random.Random(seed)
    mb = MB()
    cols = [(0.0, 0.0, H, rng.uniform(9.0, 11.0))]
    for k in range(rng.randint(3, 4)):
        a = rng.uniform(0, TAU)
        d = rng.uniform(9, 15)
        cols.append((d * math.cos(a), d * math.sin(a), H * rng.uniform(0.3, 0.7), rng.uniform(5.0, 7.5)))
    for cx, cy, h, rad in cols:
        z = -4.0
        nseg = max(2, int(h / rng.uniform(9, 15)))
        rot = rng.uniform(0, TAU)
        for s in range(nseg):
            z1 = -4.0 + (h + 4.0) * (s + 1) / nseg
            rr = rad * (1.0 - 0.18 * s / nseg) * rng.uniform(0.95, 1.03)
            ox, oy = rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4)
            top_tilt = (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12)) if s == nseg - 1 else (0.0, 0.0)
            col = tuple(np.array(PAL["pinnacle"]) * (1.0 + 0.06 * s / nseg) * rng.uniform(0.95, 1.05))
            hexcol(mb, cx + ox, cy + oy, z, z1 - 0.25, rr, col, rot=rot + rng.uniform(-0.1, 0.1), tilt=top_tilt)
            z = z1
    for k in range(9):
        a = rng.uniform(0, TAU)
        d = rng.uniform(9, 17)
        s = rng.uniform(2.5, 5.0)
        rock(mb, rng, (d * math.cos(a), d * math.sin(a), s * 0.2), s, s * 0.8, s * 0.6, PAL["pinnacle"], n=14)
    return [("Rock", mb, "paint")]


def build_dome(subdiv=5, width=5.0):
    """Force-field cap: the dual (hex/pent) edges of an icosphere cap as thin strips (a shallow dome: 1,400 at the
    apex, meeting the ground at R). Shown faint in the high aerial only; in game the field is invisible until touched."""
    zg = mspline(R, JK_R, JK_Y)
    apex = 1400.0
    cz = (R * R + zg * zg - apex * apex) / (2.0 * (zg - apex))
    rho = apex - cz
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=rho)
    bm.faces.ensure_lookup_table()
    cen = {f.index: f.calc_center_median() for f in bm.faces}
    mb = MB()
    for e in bm.edges:
        fs = e.link_faces
        if len(fs) != 2:
            continue
        a = cen[fs[0].index] + Vector((0, 0, cz))
        b = cen[fs[1].index] + Vector((0, 0, cz))
        if a.z < zg - 2 or b.z < zg - 2:
            continue
        d = (b - a)
        n = ((a + b) / 2 - Vector((0, 0, cz))).normalized()
        s = d.cross(n).normalized() * (width / 2)
        mb.nv()
        i0 = mb.v(a + s)
        i1 = mb.v(b + s)
        i2 = mb.v(b - s)
        i3 = mb.v(a - s)
        mb.f((i0, i1, i2, i3), PAL["field"])
    bm.free()
    return mb, zg


def build_field_band():
    """The field's foot: a low faint curtain where the force field meets the ground (always shown)."""
    n = 1440
    b = np.arange(n) * 360.0 / n
    gx, gy = R * np.sin(np.radians(b)), R * np.cos(np.radians(b))
    gz = field_core(gx, gy)["y"]
    mb = MB()
    mb.nv()
    lo, hi = [], []
    for k in range(n):
        lo.append(mb.v((gx[k], gy[k], gz[k] - 4.0)))
        hi.append(mb.v((gx[k], gy[k], gz[k] + 34.0)))
    for k in range(n):
        mb.f((lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k]), PAL["field"])
    return mb, gz


# =============================================================================================== plant builders
def build_palm(seed, H=45.0, lean=8.0, nfr=11, curve=0.3, frond_col=None):
    rng = random.Random(seed)
    mb = MB()
    n = 14
    path, rad = [], []
    p = Vector((0.0, 0.0, 0.0))
    lam = math.radians(lean)
    for i in range(n + 1):
        t = i / n
        if i > 0:
            a = lam * (0.35 + 0.65 * t ** (1.0 + curve))
            p = p + Vector((0.0, math.sin(a), math.cos(a))) * (H / n)
        path.append(tuple(p))
        rad.append((1.15 - 0.45 * t) * (1.06 if i % 2 else 1.0))
    tube(mb, path, rad, 7, PAL["palm_trunk"], cap0=False, cap1=True)
    top = Vector(path[-1])
    lobe(mb, rng, top + Vector((0, 0, 0.4)), 1.4, 1.4, 1.7, (92, 98, 62), n=12, leaf=0.5)
    fc = frond_col or PAL["palm_frond"]
    for k in range(nfr):
        az = TAU * k / nfr + rng.uniform(-0.25, 0.25)
        frond(mb, top + Vector((0, 0, 0.9)), az, rng.uniform(22, 55), -rng.uniform(55, 95), rng.uniform(14, 19),
              rng.uniform(2.6, 3.3), fc, segs=9, serr=0.55)
    for k in range(rng.randint(3, 6)):
        a = rng.uniform(0, TAU)
        lobe(mb, rng, top + Vector((math.cos(a) * 1.1, math.sin(a) * 1.1, -1.1)), 0.6, 0.6, 0.65, PAL["coconut"],
             n=10, flat=0.9, leaf=0.0)
    return mb


def build_broadleaf(seed, H, crown_r, buttress=False, nlobe=7, flat=0.45, col=None, bark=None):
    rng = random.Random(seed)
    mb = MB()
    bc = bark or PAL["bark"]
    lc = col or PAL["canopy"]
    r0 = max(0.9, 0.035 * H)
    fork = H * rng.uniform(0.48, 0.58)
    lean = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * 0.03 * H
    path = [(0, 0, -0.5), (0, 0, fork * 0.3), tuple(lean * 0.5 + Vector((0, 0, fork * 0.7))),
            tuple(lean + Vector((0, 0, fork)))]
    tube(mb, path, [r0 * 1.5, r0 * 1.05, r0 * 0.92, r0 * 0.8], 8, bc, cap0=False, rjit=0.04, rng=rng)
    top = Vector(path[-1])
    if buttress:
        for k in range(rng.randint(4, 5)):
            a = TAU * k / 5 + rng.uniform(-0.25, 0.25)
            d = Vector((math.cos(a), math.sin(a), 0))
            s = Vector((-d.y, d.x, 0))
            hb = H * 0.13
            pts = [d * r0 + s * 0.4, d * r0 - s * 0.4, d * r0 * 1.05 + s * 0.35 + Vector((0, 0, hb)),
                   d * r0 * 1.05 - s * 0.35 + Vector((0, 0, hb)), d * (r0 + hb * 0.6) + s * 0.3,
                   d * (r0 + hb * 0.6) - s * 0.3, d * (r0 + hb * 0.45) + Vector((0, 0, hb * 0.18))]
            v, f = hull([q + Vector((0, 0, -0.4)) for q in pts])
            mb.mesh(v, f, bc)
    cz = H - crown_r * 0.42
    lobes = []
    for k in range(nlobe):
        a = TAU * k / nlobe + rng.uniform(-0.3, 0.3)
        rr = crown_r * rng.uniform(0.35, 0.62)
        lobes.append(Vector((top.x + rr * math.cos(a), top.y + rr * math.sin(a), cz + rng.uniform(-0.15, 0.2) * crown_r)))
    lobes.append(Vector((top.x, top.y, cz + crown_r * 0.22)))
    for c in lobes:
        d = c - top
        mid = top + d * 0.55 + Vector((0, 0, d.length * 0.08))
        tube(mb, [top, mid, c - Vector((0, 0, crown_r * 0.15))], [r0 * 0.55, r0 * 0.38, r0 * 0.22], 6, bc,
             cap0=False)
    for c in lobes:
        rr = crown_r * rng.uniform(0.42, 0.6)
        lobe(mb, rng, c, rr, rr * rng.uniform(0.8, 1.0), rr * rng.uniform(0.5, 0.65), lc, n=22, flat=flat)
    return mb


def build_fern(seed, H=15.0):
    rng = random.Random(seed)
    mb = MB()
    path = [(0, 0, -0.3), (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), H * 0.5), (rng.uniform(-0.8, 0.8),
                                                                                       rng.uniform(-0.8, 0.8), H)]
    tube(mb, path, [0.6, 0.48, 0.42], 6, PAL["palm_trunk"], cap0=False)
    top = Vector(path[-1])
    for k in range(9):
        az = TAU * k / 9 + rng.uniform(-0.2, 0.2)
        frond(mb, top, az, rng.uniform(30, 55), -rng.uniform(40, 75), rng.uniform(7, 9.5), rng.uniform(1.4, 1.8),
              PAL["fern"], segs=8, serr=0.7)
    return mb


def build_bigleaf(seed, H=5.0):
    rng = random.Random(seed)
    mb = MB()
    for k in range(rng.randint(6, 8)):
        az = TAU * k / 7 + rng.uniform(-0.3, 0.3)
        hgt = rng.uniform(0.4, 0.75) * H
        base = Vector((math.cos(az) * 0.6, math.sin(az) * 0.6, hgt))
        tube(mb, [(0, 0, -0.2), (math.cos(az) * 0.3, math.sin(az) * 0.3, hgt * 0.6), tuple(base)], [0.14, 0.12, 0.1],
             4, PAL["bigleaf"], cap0=False, leaf=1.0)
        frond(mb, base, az, rng.uniform(20, 40), -rng.uniform(25, 55), rng.uniform(3.4, 5.0), rng.uniform(1.5, 2.3),
              PAL["bigleaf"], segs=5, serr=0.0, fold=0.3)
    return mb


def build_shrub(seed, s=1.0):
    rng = random.Random(seed)
    mb = MB()
    for k in range(rng.randint(3, 4)):
        a = rng.uniform(0, TAU)
        d = rng.uniform(0.5, 1.4) * s
        rr = rng.uniform(1.4, 2.2) * s
        lobe(mb, rng, (d * math.cos(a), d * math.sin(a), rr * 0.45), rr, rr * 0.85, rr * 0.7, PAL["shrub"], n=16,
             flat=0.6)
    return mb


def build_driftwood(seed, L=12.0):
    rng = random.Random(seed)
    mb = MB()
    r0 = rng.uniform(0.45, 0.7)
    path = [(-L / 2, 0, r0 * 0.7), (0, rng.uniform(-0.6, 0.6), r0 * 0.75), (L / 2, rng.uniform(-1, 1), r0 * 0.6)]
    tube(mb, path, [r0, r0 * 0.9, r0 * 0.6], 6, PAL["driftwood"], rjit=0.05, rng=rng)
    tube(mb, [(L * 0.1, 0, r0), (L * 0.3, 2.2, r0 * 1.2)], [r0 * 0.5, r0 * 0.3], 5, PAL["driftwood"])
    return mb


def build_snag(seed, H=30.0, col=None):
    rng = random.Random(seed)
    mb = MB()
    c = col or PAL["snag"]
    path = [(0, 0, -0.5), (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), H * 0.5), (rng.uniform(-1, 1),
                                                                                       rng.uniform(-1, 1), H)]
    r0 = 0.045 * H
    tube(mb, path, [r0 * 1.3, r0 * 0.9, r0 * 0.4], 7, c, cap0=False, rjit=0.06, rng=rng)
    for k in range(rng.randint(2, 4)):
        z = H * rng.uniform(0.45, 0.85)
        a = rng.uniform(0, TAU)
        el = math.radians(rng.uniform(10, 50))
        d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
        Lb = H * rng.uniform(0.15, 0.3)
        p0 = Vector((0, 0, z))
        tube(mb, [p0, p0 + d * Lb], [r0 * 0.45, r0 * 0.25], 5, c)
    return mb


def build_banyan(seed, H=56.0, W=84.0):
    rng = random.Random(seed)
    mb = MB()
    bc = (120, 108, 92)
    for k in range(4):
        a = TAU * k / 4 + rng.uniform(-0.3, 0.3)
        o = Vector((math.cos(a), math.sin(a), 0)) * 2.4
        tube(mb, [(o.x, o.y, -0.5), (o.x * 0.6, o.y * 0.6, H * 0.35), (o.x * 0.3, o.y * 0.3, H * 0.62)], [2.6, 2.0, 1.6],
             7, bc, cap0=False)
    hub = Vector((0, 0, H * 0.6))
    tips = []
    for k in range(7):
        a = TAU * k / 7 + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        Lr = W * rng.uniform(0.36, 0.46)
        end = hub + d * Lr + Vector((0, 0, rng.uniform(-3, 4)))
        tube(mb, [hub, hub + d * Lr * 0.5 + Vector((0, 0, 4)), end], [1.8, 1.3, 0.8], 6, bc, cap0=False)
        tips.append(end)
        for j in range(2):
            q = hub + d * Lr * rng.uniform(0.35, 0.9)
            tube(mb, [(q.x, q.y, -0.4), (q.x, q.y, q.z)], [rng.uniform(0.55, 0.85)] * 2, 6, bc, cap0=False, cap1=False)
    for c in tips + [hub + Vector((0, 0, 8))]:
        rr = rng.uniform(13, 18)
        lobe(mb, rng, c + Vector((0, 0, 6)), rr, rr * 0.9, rr * 0.5, PAL["canopy"], n=22, flat=0.4)
    for k in range(5):
        a = rng.uniform(0, TAU)
        d = rng.uniform(10, 22)
        rr = rng.uniform(12, 16)
        lobe(mb, rng, hub + Vector((math.cos(a) * d, math.sin(a) * d, 12)), rr, rr, rr * 0.5, PAL["canopy"], n=20,
             flat=0.4)
    return mb


def build_mangrove(seed, H=18.0):
    rng = random.Random(seed)
    mb = MB()
    bc = (112, 100, 86)
    tube(mb, [(0, 0, 3.5), (0.3, 0.2, H * 0.55)], [0.8, 0.6], 6, bc, cap0=True)
    for k in range(9):
        a = TAU * k / 9 + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        z0 = rng.uniform(3.0, 6.0)
        rr = rng.uniform(4.0, 7.0)
        tube(mb, [(0, 0, z0), tuple(d * rr * 0.5 + Vector((0, 0, z0 + 1.2))), tuple(d * rr + Vector((0, 0, -0.5)))],
             [0.35, 0.3, 0.28], 5, bc, cap0=False)
    for k in range(5):
        a = TAU * k / 5 + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(4.5, 6.5)
        lobe(mb, rng, (math.cos(a) * 3.5, math.sin(a) * 3.5, H * 0.62 + rng.uniform(0, 3)), rr, rr * 0.9, rr * 0.6,
             PAL["mangrove"], n=18, flat=0.5)
    lobe(mb, rng, (0, 0, H * 0.82), 5.5, 5.0, 3.5, PAL["mangrove"], n=18, flat=0.5)
    return mb


def build_emergent(seed, H=90.0):
    rng = random.Random(seed)
    return build_broadleaf(seed, H, rng.uniform(16, 20), buttress=True, nlobe=5, flat=0.35,
                           col=(72, 92, 46), bark=(124, 112, 96))


def build_fanpalm(seed, H=22.0):
    rng = random.Random(seed)
    mb = MB()
    n = 10
    path = [(0, 0, H * i / n) for i in range(n + 1)]
    tube(mb, path, [0.95 * (1.07 if i % 2 else 1.0) for i in range(n + 1)], 7, (118, 106, 90), cap0=False)
    top = Vector(path[-1])
    for k in range(14):
        az = TAU * k / 14 + rng.uniform(-0.15, 0.15)
        el = math.radians(rng.uniform(-20, 50))
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        base = top + d * 2.4
        tube(mb, [top, base], [0.12, 0.1], 4, PAL["fanpalm"], cap0=False, leaf=1.0)
        side = Vector((-math.sin(az), math.cos(az), 0))
        up = d.cross(side).normalized()
        mb.nv()
        c = mb.v(base)
        cb = mb.v(base - up * 0.12)
        fan, fanb = [], []
        for j in range(9):
            a = math.radians(-70 + 140 * j / 8)
            q = base + (d * math.cos(a) + side * math.sin(a)) * 3.6 + up * (0.35 if j % 2 else -0.35)
            fan.append(mb.v(q))
            fanb.append(mb.v(q - up * 0.12))
        for j in range(8):
            mb.fo((c, fan[j], fan[j + 1]), PAL["fanpalm"], up, leaf=1.0)
            mb.fo((cb, fanb[j + 1], fanb[j]), PAL["fanpalm"], -up, leaf=1.0)
    return mb


def build_mound(seed, H=10.0):
    rng = random.Random(seed)
    mb = MB()
    spires = [(0.0, 0.0, H, 3.0)]
    for k in range(rng.randint(1, 2)):
        a = rng.uniform(0, TAU)
        spires.append((math.cos(a) * 2.2, math.sin(a) * 2.2, H * rng.uniform(0.45, 0.7), 1.8))
    for cx, cy, h, r0 in spires:
        mb.nv()
        rings = []
        nl = 14
        rot = rng.uniform(0, TAU)
        for i, (zt, rs) in enumerate(((-0.5, 1.0), (0.25, 0.86), (0.5, 0.62), (0.75, 0.38), (0.94, 0.16))):
            ring = []
            for k in range(nl):
                a = rot + TAU * k / nl + i * 0.08
                rr = r0 * rs * (1.0 if k % 2 == 0 else 0.74)
                ring.append(mb.v((cx + rr * math.cos(a), cy + rr * math.sin(a), zt * h if zt > 0 else zt)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for k in range(nl):
                mb.f((rings[i][k], rings[i][(k + 1) % nl], rings[i + 1][(k + 1) % nl], rings[i + 1][k]), PAL["clay"])
        apex = mb.v((cx, cy, h))
        for k in range(nl):
            mb.f((rings[-1][k], rings[-1][(k + 1) % nl], apex), PAL["clay"])
    return mb


def build_boulder(seed, s=4.0, col=None):
    rng = random.Random(seed)
    mb = MB()
    rock(mb, rng, (0, 0, s * 0.25), s, s * rng.uniform(0.6, 0.9), s * 0.65, col or PAL["rock"], n=16, cuts=3,
         flat_bottom=0.55)
    return mb


def build_slab(seed):
    rng = random.Random(seed)
    mb = MB()
    for k in range(rng.randint(2, 4)):
        a = rng.uniform(0, TAU)
        d = rng.uniform(0, 5)
        rock(mb, rng, (d * math.cos(a), d * math.sin(a), -0.6), rng.uniform(5, 9), rng.uniform(4, 7),
             rng.uniform(1.2, 2.2), PAL["slab"], n=16, cuts=2, flat_top=0.8, flat_bottom=0.5)
    return mb


def build_shell(seed, W=60.0):
    rng = random.Random(seed)
    mb = MB()
    for k in range(rng.randint(5, 7)):
        a = rng.uniform(0, TAU)
        d = rng.uniform(0, W * 0.3)
        rr = rng.uniform(0.25, 0.4) * W
        lobe(mb, rng, (d * math.cos(a), d * math.sin(a), rr * 0.6 + rng.uniform(4, 12)), rr, rr * 0.9, rr * 0.7,
             PAL["canopy_dark"], n=18, flat=0.3)
    return mb


def build_log(seed, L=32.0):
    rng = random.Random(seed)
    mb = MB()
    r0 = rng.uniform(1.4, 1.9)
    tube(mb, [(0, -L / 2, r0 * 0.8), (0.4, 0, r0 * 0.85), (0, L / 2, r0 * 0.7)], [r0, r0 * 0.9, r0 * 0.7], 7,
         PAL["bark"], rjit=0.05, rng=rng)
    v, f = hull([Vector((rng.uniform(-1, 1) * r0 * 2.2, -L / 2 - rng.uniform(0, 0.8), rng.uniform(-0.4, 2.2) * r0))
                 for _ in range(12)] + [Vector((0, -L / 2 + 1.0, r0))])
    mb.mesh(v, f, (104, 92, 76))
    return mb


def build_figure():
    """Blocky 5.5-stud avatar standing on a plate (scale reference; generic colours)."""
    mb = MB()
    for c, s, col in (((-0.5, 0, 1.15), (0.95, 0.95, 2.3), (52, 56, 64)), ((0.5, 0, 1.15), (0.95, 0.95, 2.3), (52, 56, 64)),
                      ((0, 0, 3.3), (2.0, 1.0, 2.0), (58, 66, 78)), ((-1.5, 0, 3.3), (0.95, 0.95, 2.0), (58, 66, 78)),
                      ((1.5, 0, 3.3), (0.95, 0.95, 2.0), (58, 66, 78)), ((0, 0, 4.9), (1.15, 1.15, 1.2), (98, 72, 56))):
        cbox(mb, c, s, col, ch=0.08)
    return mb


# variant table for the scattered (instanced) set: (name, builder) -> index order = name order (V000_...)
def variant_table():
    T = []

    def add(name, fn):
        T.append(("V%03d_%s" % (len(T), name), fn))
    add("PalmA", lambda: build_palm(11, 46, 7))
    add("PalmB", lambda: build_palm(12, 56, 13, curve=0.6))
    add("PalmC", lambda: build_palm(13, 37, 4))
    add("BroadS_A", lambda: build_broadleaf(21, 32, 10.5))
    add("BroadS_B", lambda: build_broadleaf(22, 38, 12.0))
    add("BroadM_A", lambda: build_broadleaf(23, 52, 16.0))
    add("BroadM_B", lambda: build_broadleaf(24, 58, 17.5))
    add("Giant_A", lambda: build_broadleaf(25, 78, 24.0, buttress=True, nlobe=9))
    add("Giant_B", lambda: build_broadleaf(26, 88, 26.0, buttress=True, nlobe=9))
    add("FernA", lambda: build_fern(31, 14))
    add("FernB", lambda: build_fern(32, 18))
    add("BigLeafA", lambda: build_bigleaf(33, 5))
    add("BigLeafB", lambda: build_bigleaf(34, 7))
    add("ShrubA", lambda: build_shrub(35, 1.0))
    add("ShrubB", lambda: build_shrub(36, 0.8))
    add("DriftA", lambda: build_driftwood(37, 12))
    add("DriftB", lambda: build_driftwood(38, 8))
    add("SnagA", lambda: build_snag(41, 26))
    add("SnagB", lambda: build_snag(42, 36))
    add("Banyan", lambda: build_banyan(43))
    add("Mangrove", lambda: build_mangrove(44))
    add("EmergentA", lambda: build_emergent(45, 122))
    add("EmergentB", lambda: build_emergent(46, 110))
    add("FanPalmA", lambda: build_fanpalm(47, 20))
    add("FanPalmB", lambda: build_fanpalm(48, 26))
    add("MoundA", lambda: build_mound(49, 9))
    add("MoundB", lambda: build_mound(50, 13))
    add("BoulderA", lambda: build_boulder(51, 4.0))
    add("BoulderB", lambda: build_boulder(52, 7.0))
    add("Slab", lambda: build_slab(53))
    add("ShellA", lambda: build_shell(54, 60))
    add("ShellB", lambda: build_shell(55, 44))
    add("Log", lambda: build_log(56))
    add("PalmFallen", lambda: build_palm(57, 40, 86, curve=0.1))
    add("Ghost", lambda: build_snag(58, 54, PAL["ghost"]))
    add("LavaBoulder", lambda: build_boulder(59, 5.0, PAL["lava"]))
    add("PalmFlat", lambda: build_palm(60, 34, 62, curve=0.5))
    add("StruckSnag", lambda: build_snag(61, 30, (108, 100, 92)))
    return T


VT = variant_table()
VI = {name.split("_", 1)[1]: i for i, (name, fn) in enumerate(VT)}


# =============================================================================================== materials
def new_mat(name):
    m = bpy.data.materials.new(name)
    if getattr(m, "node_tree", None) is None:
        m.use_nodes = True
    return m


def haze_group():
    ng = bpy.data.node_groups.get("Haze")
    if ng:
        return ng
    ng = bpy.data.node_groups.new("Haze", "ShaderNodeTree")
    ng.interface.new_socket("Shader", in_out="INPUT", socket_type="NodeSocketShader")
    ng.interface.new_socket("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    N, Lk = ng.nodes, ng.links
    gi = N.new("NodeGroupInput")
    go = N.new("NodeGroupOutput")
    cam = N.new("ShaderNodeCameraData")
    geo = N.new("ShaderNodeNewGeometry")
    sep = N.new("ShaderNodeSeparateXYZ")
    Lk.new(geo.outputs["Position"], sep.inputs[0])

    def val(name, v):
        n = N.new("ShaderNodeValue")
        n.name = name
        n.outputs[0].default_value = v
        return n.outputs[0]

    def m(op, a, b=None):
        n = N.new("ShaderNodeMath")
        n.operation = op
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                Lk.new(x, n.inputs[i])
        return n.outputs[0]
    L_ = val("HazeL", 6500.0)
    H_ = val("HazeH", 900.0)
    C_ = val("CamZ", 50.0)
    MX = val("HazeMax", 0.9)
    A = m("EXPONENT", m("MULTIPLY", m("DIVIDE", sep.outputs["Z"], H_), -1.0))
    B = m("EXPONENT", m("MULTIPLY", m("DIVIDE", C_, H_), -1.0))
    avg = m("MULTIPLY", m("ADD", A, B), 0.5)
    tau = m("MULTIPLY", m("DIVIDE", cam.outputs["View Distance"], L_), avg)
    T = m("EXPONENT", m("MULTIPLY", tau, -1.0))
    fac = m("MINIMUM", m("SUBTRACT", 1.0, T), MX)
    col = N.new("ShaderNodeRGB")
    col.name = "HazeCol"
    col.outputs[0].default_value = (0.6, 0.65, 0.7, 1.0)
    em = N.new("ShaderNodeEmission")
    Lk.new(col.outputs[0], em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    mix = N.new("ShaderNodeMixShader")
    Lk.new(fac, mix.inputs[0])
    Lk.new(gi.outputs[0], mix.inputs[1])
    Lk.new(em.outputs[0], mix.inputs[2])
    Lk.new(mix.outputs[0], go.inputs[0])
    return ng


def finish_mat(m, bsdf_out):
    nt = m.node_tree
    out = nt.nodes.get("Material Output") or nt.nodes.new("ShaderNodeOutputMaterial")
    g = nt.nodes.new("ShaderNodeGroup")
    g.node_tree = haze_group()
    nt.links.new(bsdf_out, g.inputs[0])
    nt.links.new(g.outputs[0], out.inputs["Surface"])


def attr_node(nt, name, kind="GEOMETRY"):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_type = kind
    a.attribute_name = name
    return a


def make_materials():
    M = {}
    m = new_mat("M_Paint")
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    nt.links.new(attr_node(nt, "col").outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.86
    finish_mat(m, b.outputs[0])
    M["paint"] = m
    m = new_mat("M_Metal")
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    nt.links.new(attr_node(nt, "col").outputs["Color"], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 0.55
    b.inputs["Roughness"].default_value = 0.5
    finish_mat(m, b.outputs[0])
    M["metal"] = m
    # plants: painted colour x per-instance sector tint (foliage faces only) x small per-instance variation
    m = new_mat("M_Plant")
    nt = m.node_tree
    N, Lk = nt.nodes, nt.links
    b = N.get("Principled BSDF")
    col = attr_node(nt, "col")
    tint = attr_node(nt, "tint", "INSTANCER")
    lm = attr_node(nt, "lm")
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    Lk.new(lm.outputs["Fac"], mix.inputs[0])
    mix.inputs[6].default_value = (1, 1, 1, 1)
    Lk.new(tint.outputs["Color"], mix.inputs[7])
    mul = N.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    Lk.new(col.outputs["Color"], mul.inputs[6])
    Lk.new(mix.outputs[2], mul.inputs[7])
    oi = N.new("ShaderNodeObjectInfo")
    rv = N.new("ShaderNodeMath")
    rv.operation = "MULTIPLY_ADD"
    Lk.new(oi.outputs["Random"], rv.inputs[0])
    rv.inputs[1].default_value = 0.14
    rv.inputs[2].default_value = 0.93
    hsv = N.new("ShaderNodeHueSaturation")
    Lk.new(rv.outputs[0], hsv.inputs["Value"])
    Lk.new(mul.outputs[2], hsv.inputs["Color"])
    Lk.new(hsv.outputs[0], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    finish_mat(m, b.outputs[0])
    M["plant"] = m
    m = new_mat("M_Terrain")
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    nt.links.new(attr_node(nt, "tcol").outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.93
    finish_mat(m, b.outputs[0])
    M["terrain"] = m
    m = new_mat("M_Water")
    nt = m.node_tree
    N, Lk = nt.nodes, nt.links
    b = N.get("Principled BSDF")
    Lk.new(attr_node(nt, "wcol").outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.07
    b.inputs["IOR"].default_value = 1.333
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / 26.0, 1 / 18.0, 1.0)
    Lk.new(tc.outputs["Object"], mp.inputs["Vector"])
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Detail"].default_value = 4.0
    Lk.new(mp.outputs[0], nz.inputs["Vector"])
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.6
    Lk.new(nz.outputs["Fac"], bump.inputs["Height"])
    Lk.new(bump.outputs["Normal"], b.inputs["Normal"])
    finish_mat(m, b.outputs[0])
    M["water"] = m
    m = new_mat("M_Field")
    nt = m.node_tree
    N, Lk = nt.nodes, nt.links
    for n in list(N):
        if n.type == "BSDF_PRINCIPLED":
            N.remove(n)
    out = N.get("Material Output")
    fade = attr_node(nt, "fade")
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*s2l(PAL["field"]), 1.0)
    em.inputs["Strength"].default_value = 2.2
    tr = N.new("ShaderNodeBsdfTransparent")
    add = N.new("ShaderNodeAddShader")
    mm = N.new("ShaderNodeMath")
    mm.operation = "MULTIPLY"
    mm.name = "FieldGain"
    Lk.new(fade.outputs["Fac"], mm.inputs[0])
    mm.inputs[1].default_value = 1.0
    Lk.new(mm.outputs[0], em.inputs["Strength"])
    Lk.new(tr.outputs[0], add.inputs[0])
    Lk.new(em.outputs[0], add.inputs[1])
    Lk.new(add.outputs[0], out.inputs["Surface"])
    M["field"] = m
    m = new_mat("M_Foam")
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    nt.links.new(attr_node(nt, "col").outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6
    b.inputs["Alpha"].default_value = 0.55
    finish_mat(m, b.outputs[0])
    M["foam"] = m
    return M


# =============================================================================================== scene build
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c


def mesh_from_arrays(name, verts, faces, coll_):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", np.asarray(verts, np.float32).ravel())
    k = faces.shape[1]
    me.loops.add(faces.size)
    me.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
    me.polygons.add(len(faces))
    me.polygons.foreach_set("loop_start", (np.arange(len(faces)) * k).astype(np.int32))
    me.update(calc_edges=True)
    obj = bpy.data.objects.new(name, me)
    coll_.objects.link(obj)
    return obj


def set_point_color(me, name, lin):
    lin = np.asarray(lin, np.float32)
    if lin.shape[1] == 3:
        lin = np.concatenate([lin, np.ones((len(lin), 1), np.float32)], 1)
    a = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    a.data.foreach_set("color", lin.ravel())
    return a


def terrain_colours(G):
    """Per-vertex colour of the coarse grid: the slot tint, softly blended, with broad low-contrast variation."""
    n = G["n"]
    tab = np.zeros((16, 3))
    for i, k, base, slot, tint, note in SLOTS:
        tab[i] = tint
    c = tab[G["mat"]]
    k = np.ones((3, 3)) / 9.0
    p = np.pad(c, ((1, 1), (1, 1), (0, 0)), mode="edge")
    c = sum(p[i:i + n, j:j + n] * k[i, j] for i in range(3) for j in range(3))
    X, Y = np.meshgrid(G["xs"], G["ys"])
    var = 1.0 + 0.05 * fbm(X, Y, 160.0, 3, SEED + 91) + 0.025 * fbm(X, Y, 28.0, 2, SEED + 92)
    c = c * var[..., None]
    rr = np.hypot(X, Y)
    far = smoothstep(R + FIELD_VISUAL - 40.0, R + FIELD_VISUAL + 60.0, rr) * (G["mat"] == SLOT["jungle"])
    c = c + (np.array(PAL["far"], np.float64) - c) * far[..., None]
    return np.clip(c, 0, 255)


def build_terrain(G, M, C):
    n = G["n"]
    X, Y = np.meshgrid(G["xs"], G["ys"])
    V = np.stack([X, Y, G["y"]], -1).reshape(-1, 3)
    idx = np.arange(n * n).reshape(n, n)
    q = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]], -1).reshape(-1, 4)
    rc = np.hypot(X[:-1, :-1] + G["cell"] / 2, Y[:-1, :-1] - G["cell"] / 2).ravel()
    q = q[rc < WORLD_R + 20.0]
    obj = mesh_from_arrays("Terrain", V, q, C["terrain"])
    me = obj.data
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    col = terrain_colours(G).reshape(-1, 3)
    set_point_color(me, "tcol", s2l(col))
    me.materials.append(M["terrain"])
    log("TERRAIN mesh %d verts %d quads" % (len(V), len(q)))
    return obj


def water_colour(depth, foam_w=0.0):
    d = np.asarray(depth, np.float64)
    sh = np.array(PAL["water_shallow"], np.float64)
    md = np.array(PAL["water_mid"], np.float64)
    dp = np.array(PAL["water"], np.float64)
    c = sh + (md - sh) * smoothstep(0.6, 5.0, d)[..., None]
    c = c + (dp - c) * smoothstep(4.0, 14.0, d)[..., None]
    foam = (1.0 - smoothstep(0.15, 0.9, d)) * 0.55
    c = c + (np.array(PAL["surf"]) - c) * foam[..., None]
    return c


def build_water(M, C):
    cell, half = 10.0, 1300.0
    n = int(2 * half / cell) + 1
    xs = np.linspace(-half, half, n)
    X, Y = np.meshgrid(xs, xs[::-1])
    f = field_core(X, Y)
    depth = WATER - f["y"]
    V = np.stack([X, Y, np.full_like(X, WATER)], -1).reshape(-1, 3)
    idx = np.arange(n * n).reshape(n, n)
    q = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]], -1).reshape(-1, 4)
    dmax = np.maximum.reduce([depth[:-1, :-1], depth[1:, :-1], depth[1:, 1:], depth[:-1, 1:]]).ravel()
    rr = np.hypot(X, Y)[:-1, :-1].ravel()
    q = q[(dmax > -1.5) & (rr < f["Rs"].max() + 40.0)]
    obj = mesh_from_arrays("Lagoon", V, q, C["water"])
    me = obj.data
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    wc = water_colour(np.clip(depth, 0, None))
    weed = smoothstep(0.18, 0.5, fbm(X, Y, 160.0, 3, SEED + 72)) * smoothstep(3.0, 9.0, depth)
    wc = wc * (1.0 - 0.2 * weed)[..., None] + np.array([0.0, -2.0, 4.0]) * weed[..., None]
    set_point_color(me, "wcol", s2l(np.clip(wc, 0, 255).reshape(-1, 3)))
    me.materials.append(M["water"])
    # freshwater pools
    for pl in LAYOUT["pools"]:
        c = pl["centre"]
        k = 40
        ring = [(c.x + (pl["radius"] + 3.0) * math.sin(TAU * i / k), c.y + (pl["radius"] + 3.0) * math.cos(TAU * i / k),
                 pl["level"]) for i in range(k)]
        verts = np.array([(c.x, c.y, pl["level"])] + ring)
        faces = np.array([(0, 1 + i, 1 + (i + 1) % k) for i in range(k)])
        po = mesh_from_arrays("Pool_" + pl["name"], verts, faces, C["water"])
        set_point_color(po.data, "wcol", s2l(np.tile(PAL["fresh"], (k + 1, 1))))
        po.data.materials.append(M["water"])
    return obj


def link_dup(src, name, coll_, loc, yaw=0.0, scale=1.0):
    o = bpy.data.objects.new(name, src.data)
    o.location = Vector(loc)
    o.rotation_euler = (0.0, 0.0, yaw)
    o.scale = (scale, scale, scale)
    coll_.objects.link(o)
    return o


def parts_objects(parts, name, M, coll_, seed=0):
    objs = []
    for role, mb, kind in parts:
        objs.append((role, mb_object(mb, "%s_%s" % (name, role), M["metal" if kind == "metal" else "paint"], coll_,
                                     seed=seed), kind))
    return objs


def ground_z(G, x, y):
    return float(grid_sample(G, "y", np.array([x]), np.array([y]))[0])


def build_landmarks(G, M, C):
    L = C["landmarks"]
    for role, o, k in parts_objects(build_horn(), "Horn", M, L):
        o.location = (0, 0, PLAZA_Y)
    for role, o, k in parts_objects(build_island_deck(), "IslandDeck", M, L):
        o.location = (0, 0, PLAZA_Y)
    for role, o, k in parts_objects(build_island_ring(), "IslandRing", M, L):
        o.location = (0, 0, WATER)
    plate = parts_objects(build_plate(), "Plate", M, C["src"])
    for pl in LAYOUT["plates"]:
        p = polar(pl["bearing"], PLATE_R, WATER)
        for role, o, k in plate:
            link_dup(o, "Plate%02d_%s" % (pl["index"], role), L, p, yaw=math.pi - math.radians(pl["bearing"]))
    mods = [parts_objects(build_spoke_module(SEED + 310 + i), "SpokeModule_%s" % "ABC"[i], M, C["src"], seed=i)
            for i in range(3)]
    spur = parts_objects(build_spur(), "SpokeSpur", M, C["src"])
    k = 0
    for h in range(12):
        b = 30.0 * h
        rs = float(field_core(np.array([polar(b, 1.0).x * 900]), np.array([polar(b, 1.0).y * 900]))["Rs"][0])
        r = 124.0
        while r < rs - 4.0:
            ln = min(40.0, rs - 4.0 - r)
            c = polar(b, r + 20.0, SPOKE_TOP)
            for role, o, kk in mods[k % 3]:
                link_dup(o, "Spoke%02d_%03d_%s" % (h, k, role), L, c,
                         yaw=-math.radians(b) + (math.pi if (k // 3) % 2 else 0.0))
            k += 1
            r += 40.0
        p = polar(b, rs - 6.0, SPOKE_TOP)
        for role, o, kk in spur:
            link_dup(o, "Spur%02d_%s" % (h, role), L, p, yaw=-math.radians(b))
    lt = LAYOUT["lightning"]
    for role, o, kk in parts_objects(build_lightning_tree(), "LightningTree", M, L):
        o.location = (lt.x, lt.y, ground_z(G, lt.x, lt.y) - 0.8)
    pins = [parts_objects(build_pinnacle(SEED + 350 + i, H), "Pinnacle_%s" % "AB"[i], M, C["src"])
            for i, H in enumerate((175.0, 140.0))]
    for i, (p, H, yaw) in enumerate(LAYOUT["pinnacles"]):
        src = pins[0] if H > 158 else pins[1]
        s = H / (175.0 if H > 158 else 140.0)
        for role, o, kk in src:
            link_dup(o, "Pin%02d_%s" % (i, role), L, (p.x, p.y, ground_z(G, p.x, p.y) - 1.5), yaw=math.radians(yaw),
                     scale=s)
    log("LANDMARKS: horn, deck, ring, 24 plates, %d spoke modules, 12 spurs, lightning tree, %d pinnacles" % (
        k, len(LAYOUT["pinnacles"])))


def build_foam(M, C):
    rng = random.Random(SEED + 400)
    mb = MB()
    col = PAL["surf"]

    def patch(x, y, s):
        mb.nv()
        k = 7
        c = mb.v((x, y, WATER + 0.06))
        ring = [mb.v((x + s * rng.uniform(0.55, 1.0) * math.cos(TAU * i / k + 0.3),
                      y + s * rng.uniform(0.55, 1.0) * math.sin(TAU * i / k + 0.3), WATER + 0.06)) for i in range(k)]
        for i in range(k):
            mb.f((c, ring[i], ring[(i + 1) % k]), col)
    for i in range(300):
        b = rng.uniform(0, 360)
        sd = min(b % 30.0, 30.0 - b % 30.0)
        r = rng.uniform(116, 132)
        if r * math.sin(math.radians(sd)) < 6.0:
            continue
        p = polar(b, r)
        patch(p.x, p.y, rng.uniform(1.2, 3.4))
    for h in range(12):
        b = 30.0 * h
        u = polar(b, 1.0)
        side = Vector((u.y, -u.x, 0))
        r = 130.0
        while r < SHORE_R - 30:
            for sgn in (-1, 1):
                if rng.random() < 0.22:
                    q = u * r + side * sgn * rng.uniform(9.5, 12.0)
                    patch(q.x, q.y, rng.uniform(0.8, 2.0))
            r += rng.uniform(4.0, 8.0)
    o = mb_object(mb, "Surf", M["foam"], C["fx"], paint=dict(kv=0.02, kf=0.0, top=0.0, under=0.0, warm=0.0))
    o.visible_shadow = False
    return o


def build_dome_obj(M, C):
    mb, zg = build_dome(5, 5.0)
    o = mb_object(mb, "ForceField", M["field"], C["dome"], paint=dict(kv=0, kf=0, top=0, under=0, warm=0))
    me = o.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    z = co.reshape(-1, 3)[:, 2]
    fade = 0.012 + 0.9 * np.exp(-np.clip(z - zg, 0, None) / 110.0)
    a = me.attributes.new("fade", "FLOAT", "POINT")
    a.data.foreach_set("value", fade.astype(np.float32))
    o.visible_shadow = False
    o.visible_diffuse = False
    o.visible_glossy = False
    mb2, zg2 = build_field_band()
    o2 = mb_object(mb2, "FieldBand", M["field"], C["fx"], paint=dict(kv=0, kf=0, top=0, under=0, warm=0))
    me = o2.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    z = co.reshape(-1, 3)[:, 2]
    a = me.attributes.new("fade", "FLOAT", "POINT")
    rel = np.clip(z - (zg2[np.arange(len(z)) // 2] - 4.0), 0, None)
    a.data.foreach_set("value", (0.6 * np.exp(-rel / 14.0)).astype(np.float32))
    o2.visible_shadow = False
    o2.visible_diffuse = False
    o2.visible_glossy = False
    return o


def instancer(name, pts, rot, scl, var, tint, src_coll, coll_):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(pts))
    me.vertices.foreach_set("co", np.asarray(pts, np.float32).ravel())
    a = me.attributes.new("variant", "INT", "POINT")
    a.data.foreach_set("value", np.asarray(var, np.int32))
    a = me.attributes.new("rot", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", np.asarray(rot, np.float32).ravel())
    a = me.attributes.new("scl", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", np.asarray(scl, np.float32).ravel())
    t = np.concatenate([np.asarray(tint, np.float32), np.ones((len(pts), 1), np.float32)], 1)
    a = me.color_attributes.new("tint", "FLOAT_COLOR", "POINT")
    a.data.foreach_set("color", t.ravel())
    o = bpy.data.objects.new(name, me)
    coll_.objects.link(o)
    mod = o.modifiers.new("Scatter", "NODES")
    ng = bpy.data.node_groups.new(name + "_GN", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N, Lk = ng.nodes, ng.links
    gi, go = N.new("NodeGroupInput"), N.new("NodeGroupOutput")
    iop = N.new("GeometryNodeInstanceOnPoints")
    ci = N.new("GeometryNodeCollectionInfo")
    ci.inputs["Collection"].default_value = src_coll
    ci.inputs["Separate Children"].default_value = True
    ci.inputs["Reset Children"].default_value = True
    na = {}
    for key, dt in (("variant", "INT"), ("rot", "FLOAT_VECTOR"), ("scl", "FLOAT_VECTOR")):
        n = N.new("GeometryNodeInputNamedAttribute")
        n.data_type = dt
        n.inputs["Name"].default_value = key
        na[key] = n
    Lk.new(gi.outputs[0], iop.inputs["Points"])
    Lk.new(ci.outputs[0], iop.inputs["Instance"])
    iop.inputs["Pick Instance"].default_value = True
    Lk.new(na["variant"].outputs["Attribute"], iop.inputs["Instance Index"])
    Lk.new(na["rot"].outputs["Attribute"], iop.inputs["Rotation"])
    Lk.new(na["scl"].outputs["Attribute"], iop.inputs["Scale"])
    Lk.new(iop.outputs[0], go.inputs[0])
    mod.node_group = ng
    return o


def tint_mul(hour):
    return np.array(CANOPY_TINT.get(int(hour), PAL["canopy"]), np.float64) / np.array(PAL["canopy"], np.float64)


def scatter(G):
    """All plants and loose pieces as instance points: (positions, rotations, scales, variants, tints)."""
    rng = np.random.RandomState(SEED + 500)
    P, ROT, SC, VAR, TN = [], [], [], [], []

    def add(x, y, z, yaw, s, v, tint, tilt=None):
        n = len(x)
        if n == 0:
            return
        P.append(np.stack([x, y, z], 1))
        tx = tilt[0] if tilt is not None else rng.uniform(-0.04, 0.04, n)
        ty = tilt[1] if tilt is not None else rng.uniform(-0.04, 0.04, n)
        ROT.append(np.stack([tx, ty, yaw], 1))
        s = np.asarray(s, np.float64) * np.ones(n)
        SC.append(np.stack([s, s, s], 1))
        VAR.append(np.asarray(v, np.int64) * np.ones(n, np.int64))
        TN.append(np.asarray(tint, np.float64).reshape(-1, 3) * np.ones((n, 1)))

    def jit_grid(cell, half):
        g = np.arange(-half, half, cell) + cell / 2
        X, Y = np.meshgrid(g, g)
        X = X.ravel() + rng.uniform(-0.45, 0.45, X.size) * cell
        Y = Y.ravel() + rng.uniform(-0.45, 0.45, Y.size) * cell
        return X, Y

    def info(X, Y):
        r = np.hypot(X, Y)
        th = np.degrees(np.arctan2(X, Y)) % 360.0
        return r, th, hour_of(th)

    def tints(hours, prob=1.0):
        t = np.array([tint_mul(h) for h in hours]) if len(hours) else np.zeros((0, 3))
        keep = rng.uniform(0, 1, len(hours)) < prob
        t[~keep] = 1.0
        return t

    # ---------------------------------------------------------------- canopy trees (inside, visual ring)
    X, Y = jit_grid(21.0, R + FIELD_VISUAL)
    r, th, hr = info(X, Y)
    f = field_core(X, Y)
    Rb = f["Rb"]
    ok = (r > Rb + 25.0) & (r < R + FIELD_VISUAL)
    dens = grid_sample(G, "dens", X, Y)
    ok &= rng.uniform(0, 1, X.size) < dens * 0.95
    X, Y, r, th, hr, Rb = X[ok], Y[ok], r[ok], th[ok], hr[ok], Rb[ok]
    mp = np.array([(q.x, q.y, 9.0 * s_) for q, _, s_ in LAYOUT["mounds"]])
    near = np.zeros(X.size, bool)
    for i0 in range(0, X.size, 8000):
        d = np.hypot(X[i0:i0 + 8000, None] - mp[None, :, 0], Y[i0:i0 + 8000, None] - mp[None, :, 1])
        near[i0:i0 + 8000] = (d < mp[None, :, 2] * 0.9 + 6.0).any(1)
    X, Y, r, th, hr, Rb = X[~near], Y[~near], r[~near], th[~near], hr[~near], Rb[~near]
    z = grid_sample(G, "y", X, Y) - 0.6
    u = rng.uniform(0, 1, X.size)
    var = np.where(u < 0.30, rng.choice([VI["BroadS_A"], VI["BroadS_B"]], X.size),
                   np.where(u < 0.72, rng.choice([VI["BroadM_A"], VI["BroadM_B"]], X.size),
                            rng.choice([VI["Giant_A"], VI["Giant_B"]], X.size)))
    palm_p = 0.45 * smoothstep(Rb + 420.0, Rb + 40.0, r) + 0.08
    u2 = rng.uniform(0, 1, X.size)
    var = np.where(u2 < palm_p, rng.choice([VI["PalmA"], VI["PalmB"], VI["PalmC"]], X.size), var)
    u3 = rng.uniform(0, 1, X.size)
    thj = (th + 6.0 * fbm(X, Y, 220.0, 3, SEED + 81) + rng.uniform(-1.5, 1.5, X.size)) % 360.0
    hrj = hour_of(thj)
    edge = r < Rb + 240.0
    var = np.where((hrj == 3) & (u3 < np.where(edge, 0.4, 0.16)) & (r < R), VI["Banyan"], var)
    var = np.where((hrj == 3) & (u3 > 0.75), rng.choice([VI["Giant_A"], VI["Giant_B"]], X.size), var)
    var = np.where((hrj == 8) & (u3 < 0.2), rng.choice([VI["EmergentA"], VI["EmergentB"]], X.size), var)
    var = np.where((hrj == 5) & (r < Rb + 380.0) & (u3 < 0.6), VI["Mangrove"], var)
    var = np.where((hrj == 2) & (u3 < np.where((r > 1250) & (r < 2450), 0.24, np.where(edge, 0.34, 0.1))),
                   VI["Ghost"], var)
    var = np.where((hrj == 6) & (u3 < 0.3), rng.choice([VI["Giant_A"], VI["Giant_B"]], X.size), var)
    var = np.where((hrj == 7) & (r < R - 40), np.where(u3 < 0.45, rng.choice([VI["FanPalmA"], VI["FanPalmB"]], X.size),
                                                        VI["BroadS_A"]), var)
    var = np.where((hrj == 9) & (r < Rb + 300.0) & (u3 < 0.5), rng.choice([VI["PalmA"], VI["PalmC"]], X.size), var)
    lt = LAYOUT["lightning"]
    dl = np.hypot(X - lt.x, Y - lt.y)
    var = np.where((dl < 170) & (u3 < 0.25), VI["StruckSnag"], var)
    near_field = np.abs(r - R) < 45.0
    var = np.where(near_field & (u3 < 0.55), rng.choice([VI["SnagA"], VI["SnagB"]], X.size), var)
    tn = tints(hrj)
    bronze = (hrj == 1) & (rng.uniform(0, 1, X.size) > 0.3)
    tn[(hrj == 1) & ~bronze] = 1.0
    yaw = rng.uniform(0, TAU, X.size)
    add(X, Y, z, yaw, rng.uniform(0.86, 1.14, X.size), var, tn)
    n_canopy = X.size
    # ---------------------------------------------------------------- understory (inside the field)
    X, Y = jit_grid(13.0, R)
    r, th, hr = info(X, Y)
    f = field_core(X, Y)
    ok = (r > f["Rb"] + 12.0) & (r < R - 10.0)
    dens = grid_sample(G, "dens", X, Y)
    ok &= rng.uniform(0, 1, X.size) < dens * 0.36
    X, Y, r, hr = X[ok], Y[ok], r[ok], hr[ok]
    z = grid_sample(G, "y", X, Y) - 0.3
    u = rng.uniform(0, 1, X.size)
    fern_p = np.where(hr == 11, 0.3, np.where(hr == 10, 0.7, 0.55))
    var = np.where(u < fern_p, rng.choice([VI["FernA"], VI["FernB"]], X.size),
                   rng.choice([VI["BigLeafA"], VI["BigLeafB"]], X.size))
    add(X, Y, z, rng.uniform(0, TAU, X.size), rng.uniform(0.85, 1.2, X.size), var, tints(hr))
    n_under = X.size
    # ---------------------------------------------------------------- the palm belt along the beach top
    pts = []
    for row, (dr, prob) in enumerate(((-30.0, 0.55), (-12.0, 0.8), (8.0, 0.8), (30.0, 0.6))):
        nn = int(TAU * 1100 / 10.5)
        b = (np.arange(nn) + rng.uniform(-0.35, 0.35, nn)) * 360.0 / nn
        pts.append((b, dr, prob))
    bx, by, bz, byaw, bv, bt, btilt = [], [], [], [], [], [], []
    for b, dr, prob in pts:
        hr = hour_of(b)
        xb, yb = np.sin(np.radians(b)), np.cos(np.radians(b))
        f = field_core(xb * 1000.0, yb * 1000.0)
        rr = f["Rb"] + dr + rng.uniform(-6, 6, b.size)
        mult = np.select([hr == 9, hr == 7, hr == 5, hr == 10], [1.35, 0.25, 0.2, 0.7], 0.75)
        keep = rng.uniform(0, 1, b.size) < prob * mult
        keep &= boundary_deg(b) * np.pi / 180.0 * rr > 12.0
        b, rr, hr = b[keep], rr[keep], hr[keep]
        x, y = rr * np.sin(np.radians(b)), rr * np.cos(np.radians(b))
        fz = field_core(x, y)
        gap = ((fz["D6"] > 2.0) & (fz["prof6"] > 0.15)) | ((fz["utr"] > 0.55) & (rng.uniform(0, 1, b.size) < 0.7))
        b, rr, hr, x, y = b[~gap], rr[~gap], hr[~gap], x[~gap], y[~gap]
        z = grid_sample(G, "y", x, y) - 0.5
        v = rng.choice([VI["PalmA"], VI["PalmB"], VI["PalmC"]], b.size)
        v = np.where(hr == 10, np.where(rng.uniform(0, 1, b.size) < 0.5, VI["PalmFlat"], VI["PalmFallen"]), v)
        yaw = np.pi - np.radians(b) + rng.uniform(-0.45, 0.45, b.size)
        bx.append(x), by.append(y), bz.append(z), byaw.append(yaw), bv.append(v), bt.append(tints(hr))
    add(np.concatenate(bx), np.concatenate(by), np.concatenate(bz), np.concatenate(byaw),
        rng.uniform(0.88, 1.12, sum(len(a) for a in bx)), np.concatenate(bv), np.concatenate(bt))
    # 9: the coconut grove on the beach
    nn = 260
    b = sector_centre(9) + rng.uniform(-12, 12, nn)
    f = field_core(np.sin(np.radians(b)) * 1000, np.cos(np.radians(b)) * 1000)
    rr = f["Rs"] + rng.uniform(70, 160, nn)
    rr = np.minimum(rr, f["Rb"] - 8)
    x, y = rr * np.sin(np.radians(b)), rr * np.cos(np.radians(b))
    add(x, y, grid_sample(G, "y", x, y) - 0.5, np.pi - np.radians(b) + rng.uniform(-0.5, 0.5, nn),
        rng.uniform(0.85, 1.1, nn), rng.choice([VI["PalmA"], VI["PalmC"]], nn), np.ones((nn, 3)))
    # beach shrubs and driftwood
    nn = int(TAU * 1080 / 6.0)
    b = (np.arange(nn) + rng.uniform(-0.4, 0.4, nn)) * 360.0 / nn
    f = field_core(np.sin(np.radians(b)) * 1000, np.cos(np.radians(b)) * 1000)
    rr = f["Rb"] - rng.uniform(4, 34, nn)
    hr = hour_of(b)
    keep = (rng.uniform(0, 1, nn) < np.where(hr == 5, 0.12, 0.42)) & (boundary_deg(b) * np.pi / 180 * rr > 10)
    b, rr, hr = b[keep], rr[keep], hr[keep]
    x, y = rr * np.sin(np.radians(b)), rr * np.cos(np.radians(b))
    add(x, y, grid_sample(G, "y", x, y) - 0.4, rng.uniform(0, TAU, b.size), rng.uniform(0.8, 1.3, b.size),
        rng.choice([VI["ShrubA"], VI["ShrubB"]], b.size), tints(hr))
    nn = 300
    b = rng.uniform(0, 360, nn)
    f = field_core(np.sin(np.radians(b)) * 1000, np.cos(np.radians(b)) * 1000)
    hr = hour_of(b)
    rr = f["Rs"] + 28 + rng.uniform(0, 1, nn) * np.maximum(f["Rb"] - f["Rs"] - 75, 5)
    rr = np.where(hr == 10, f["Rs"] + rng.uniform(45, 75, nn), rr)
    x, y = rr * np.sin(np.radians(b)), rr * np.cos(np.radians(b))
    add(x, y, grid_sample(G, "y", x, y) - 0.2, rng.uniform(0, TAU, nn), rng.uniform(0.8, 1.3, nn),
        rng.choice([VI["DriftA"], VI["DriftB"]], nn), np.ones((nn, 3)), tilt=(np.zeros(nn), np.zeros(nn)))
    nn = 140
    b = sector_centre(10) + rng.uniform(-11, 11, nn)
    f = field_core(np.sin(np.radians(b)) * 1000, np.cos(np.radians(b)) * 1000)
    rr = f["Rs"] + rng.uniform(40, 80, nn)
    x, y = rr * np.sin(np.radians(b)), rr * np.cos(np.radians(b))
    add(x, y, grid_sample(G, "y", x, y) - 0.2, rng.uniform(0, TAU, nn), rng.uniform(0.9, 1.4, nn),
        rng.choice([VI["DriftA"], VI["DriftB"]], nn), np.ones((nn, 3)), tilt=(np.zeros(nn), np.zeros(nn)))
    # boulders on steep jungle ground
    sel = np.argwhere((G["mat"] == SLOT["rock"]))
    pick = sel[rng.uniform(0, 1, len(sel)) < 0.22]
    x = G["xs"][pick[:, 1]] + rng.uniform(-4, 4, len(pick))
    y = G["ys"][pick[:, 0]] + rng.uniform(-4, 4, len(pick))
    keep = np.hypot(x, y) < R + FIELD_VISUAL
    x, y = x[keep], y[keep]
    add(x, y, grid_sample(G, "y", x, y) - 0.8, rng.uniform(0, TAU, x.size), rng.uniform(0.7, 1.8, x.size),
        rng.choice([VI["BoulderA"], VI["BoulderB"]], x.size), np.ones((x.size, 3)))
    # 9: reef boulders on the shelf
    nn = 220
    b = sector_centre(9) + rng.uniform(-12, 12, nn)
    f = field_core(np.sin(np.radians(b)) * 1000, np.cos(np.radians(b)) * 1000)
    rr = f["Rs"] - rng.uniform(5, 85, nn)
    x, y = rr * np.sin(np.radians(b)), rr * np.cos(np.radians(b))
    fz = field_core(x, y)
    keep = fz["shelf"] > 0.4
    x, y = x[keep], y[keep]
    add(x, y, fz["y"][keep] - 0.6, rng.uniform(0, TAU, x.size), rng.uniform(0.5, 1.4, x.size), VI["LavaBoulder"],
        np.ones((x.size, 3)))
    # sector pieces
    for p, yaw, s in LAYOUT["slabs"]:
        add(np.array([p.x]), np.array([p.y]), np.array([ground_z(G, p.x, p.y)]), np.array([math.radians(yaw)]), s,
            VI["Slab"], np.ones((1, 3)))
    for p, yaw, s in LAYOUT["mounds"]:
        add(np.array([p.x]), np.array([p.y]), np.array([ground_z(G, p.x, p.y) - 0.3]), np.array([math.radians(yaw)]), s,
            rng.choice([VI["MoundA"], VI["MoundB"]], 1), np.ones((1, 3)))
    for key in ("logs", "logs6"):
        for p, yaw, s in LAYOUT[key]:
            add(np.array([p.x]), np.array([p.y]), np.array([ground_z(G, p.x, p.y) - 0.5]),
                np.array([math.radians(yaw)]), s, VI["Log"], np.ones((1, 3)), tilt=(np.zeros(1), np.zeros(1)))
    # backdrop canopy shells and crest giants
    X, Y = jit_grid(26.0, WORLD_R)
    r = np.hypot(X, Y)
    ok = (r > R + FIELD_VISUAL - 10) & (r < WORLD_R - 15) & (rng.uniform(0, 1, X.size) < 0.9)
    X, Y = X[ok], Y[ok]
    z = grid_sample(G, "y", X, Y) - 3.0
    u = rng.uniform(0, 1, X.size)
    var = np.where(u < 0.12, rng.choice([VI["Giant_A"], VI["Giant_B"]], X.size),
                   rng.choice([VI["ShellA"], VI["ShellB"]], X.size))
    add(X, Y, z, rng.uniform(0, TAU, X.size), rng.uniform(1.0, 1.6, X.size), var, np.ones((X.size, 3)))
    # far slopes (render only): sparse big canopy shells so the outer island reads as forest
    nn = 26000
    rr = np.sqrt(rng.uniform((WORLD_R + 20.0) ** 2, 8500.0 ** 2, nn))
    b = rng.uniform(0, TAU, nn)
    X, Y = rr * np.sin(b), rr * np.cos(b)
    z = far_height(X, Y)
    keep = z > 12.0
    X, Y, z = X[keep], Y[keep], z[keep]
    add(X, Y, z - 4.0, rng.uniform(0, TAU, X.size), rng.uniform(1.8, 3.0, X.size),
        rng.choice([VI["ShellA"], VI["ShellB"]], X.size), np.ones((X.size, 3)))
    out = [np.concatenate(a) for a in (P, ROT, SC, VAR, TN)]
    log("SCATTER %d instances (canopy %d, understory %d)" % (len(out[0]), n_canopy, n_under))
    return out


def far_height(X, Y):
    """Render-only outer slopes of the island past the coarse grid, falling to the sea."""
    Rr = np.hypot(X, Y)
    th = np.degrees(np.arctan2(X, Y))
    base = np.interp(Rr, [WORLD_R - 40.0, 4300.0, 5600.0, 7000.0, 8200.0, 8800.0, 9300.0, 16000.0],
                     [455.0, 330.0, 200.0, 90.0, 18.0, 4.0, -6.0, -6.0])
    p = 1.0 - np.abs(np.cos(np.radians(th + 2.0 * fbm(X, Y, 900.0, 2, SEED + 95)) * 36.0))
    p = p * (0.6 + 0.4 * smoothstep(-0.5, 0.5, fbm(X, Y, 1500.0, 2, SEED + 98)))
    amp = np.interp(Rr, [WORLD_R, 5000.0, 7500.0, 8800.0], [110.0, 120.0, 50.0, 0.0])
    Z = base + amp * (p - 0.45) + 25.0 * fbm(X, Y, 700.0, 3, SEED + 96) * (Rr < 8800)
    return np.where(Rr > 8900.0, -6.0, Z)


def build_far(M, C):
    """Render-only surroundings: the island's outer slopes (fluted, forested) falling to a calm sea."""
    na, rs = 720, np.concatenate([np.linspace(WORLD_R - 40.0, 9000.0, 70), np.linspace(9300.0, 16000.0, 12)])
    A, Rr = np.meshgrid(np.radians(np.arange(na) * 360.0 / na), rs)
    X, Y = Rr * np.sin(A), Rr * np.cos(A)
    Z = far_height(X, Y)
    n0, n1 = Rr.shape
    V = np.stack([X, Y, Z], -1).reshape(-1, 3)
    idx = np.arange(n0 * n1).reshape(n0, n1)
    q = np.stack([idx[:-1, :], idx[1:, :], np.roll(idx[1:, :], -1, 1), np.roll(idx[:-1, :], -1, 1)], -1).reshape(-1, 4)
    o = mesh_from_arrays("FarLand", V, q, C["fx"])
    o.data.polygons.foreach_set("use_smooth", np.ones(len(o.data.polygons), bool))
    sea = Z < 1.0
    beach = (Z >= 1.0) & (Z < 14.0)
    col = np.tile(np.array(PAL["far"], np.float64), (n0, n1, 1))
    col = col * (1.0 + 0.08 * fbm(X, Y, 400.0, 2, SEED + 97))[..., None]
    col[beach] = PAL["sand"]
    col[sea] = (34, 84, 92)
    set_point_color(o.data, "tcol", s2l(col.reshape(-1, 3)))
    o.data.materials.append(M["terrain"])
    return o


def build_scene(G):
    reset_scene()
    sc = bpy.context.scene
    C = {k: coll(k) for k in ("terrain", "water", "landmarks", "plants", "fx", "src", "figure", "dome")}
    bpy.context.view_layer.layer_collection.children["src"].exclude = True
    M = make_materials()
    build_terrain(G, M, C)
    build_water(M, C)
    build_landmarks(G, M, C)
    build_foam(M, C)
    build_dome_obj(M, C)
    build_far(M, C)
    vsrc = coll("variants", C["src"])
    for name, fn in VT:
        mb = fn()
        o = mb_object(mb, name, M["plant"], vsrc, paint=dict(zg=0.14))
    pts, rot, scl, var, tint = scatter(G)
    instancer("Plants", pts, rot, scl, var, tint, vsrc, C["plants"])
    fig = mb_object(build_figure(), "Figure", M["paint"], C["figure"], paint=dict(kv=0, kf=0, warm=0, zg=0))
    fig.hide_render = True
    return sc, C, M


# =============================================================================================== data export
def u16_height(y):
    return np.clip(np.round((y + H_OFFSET) * H_SCALE), 0, 65535).astype(np.uint16)


def hillshade(y, cell):
    gy, gx = np.gradient(y, cell)
    n = np.stack([-gx, gy, np.ones_like(y)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    L = np.array([-0.45, 0.55, 0.7])
    L /= np.linalg.norm(L)
    return np.clip((n * L).sum(-1), 0, 1)


def data_stage():
    solve_pools()
    t = time.time()
    Gf = field_grid(*FINE)
    log("FINE grid %d x %d in %.0fs" % (Gf["n"], Gf["n"], time.time() - t))
    t = time.time()
    Gc = field_grid(*COARSE)
    log("COARSE grid %d x %d in %.0fs" % (Gc["n"], Gc["n"], time.time() - t))
    np.savez_compressed(os.path.join(WORK, "coarse.npz"), **{k: Gc[k] for k in ("y", "slope", "mat", "dens", "reg",
                                                                                   "sec", "depth", "xs", "ys")},
                        cell=Gc["cell"], half=Gc["half"], n=Gc["n"],
                        pools=np.array([p["level"] for p in LAYOUT["pools"]]))
    files = {}
    for tag, G in (("fine", Gf), ("coarse", Gc)):
        p = os.path.join(TERR, "Map2_height_%s_u16.png" % tag)
        write_png(p, u16_height(G["y"]), bits=16)
        files["height_" + tag] = p
    write_png(os.path.join(TERR, "Map2_material_u8.png"), Gf["mat"])
    write_png(os.path.join(TERR, "Map2_sector_u8.png"), Gf["sec"])
    write_png(os.path.join(TERR, "Map2_region_u8.png"), Gf["reg"])
    write_png(os.path.join(TERR, "Map2_waterdepth_u8.png"), np.clip(np.round(Gf["depth"] * 8.0), 0, 255).astype(np.uint8))
    write_png(os.path.join(TERR, "Map2_trees_u8.png"), np.clip(np.round(Gf["dens"] * 255), 0, 255).astype(np.uint8))
    for i, k, base, slot, tint, note in SLOTS:
        write_png(os.path.join(TERR, "Map2_mask_%s_u8.png" % k), np.where(Gf["mat"] == i, 255, 0).astype(np.uint8))
    write_png(os.path.join(TERR, "Map2_material_coarse_u8.png"), Gc["mat"])
    # stats
    yin = Gf["y"][np.hypot(*np.meshgrid(Gf["xs"], Gf["ys"])) <= R]
    counts = {k: float((Gf["mat"] == i).mean()) for i, k, *_ in SLOTS}
    log("HEIGHT inside the field: min %.1f max %.1f; materials %s" % (yin.min(), yin.max(),
                                                                      {k: round(v, 3) for k, v in counts.items()}))
    write_layout_json(Gf, Gc, counts)
    data_maps_preview(Gf)
    return Gc


def biome16(G):
    """16-stud biome grid as rows of single characters (from the 4-stud fine grid, majority per 4x4 block)."""
    mat = G["mat"]
    n = mat.shape[0] // 4
    blk = mat[:n * 4, :n * 4].reshape(n, 4, n, 4).transpose(0, 2, 1, 3).reshape(n, n, 16)
    counts = np.stack([(blk == i).sum(-1) for i in range(11)], -1)
    maj = counts.argmax(-1)
    dep = G["depth"][:n * 4, :n * 4].reshape(n, 4, n, 4).mean((1, 3))
    code = np.array(list(".SsLRJMGlDX"))
    ch = code[maj]
    ch[dep > 0.5] = "W"
    return ["".join(row) for row in ch]


def write_layout_json(Gf, Gc, counts):
    sp = []
    for h in range(12):
        b = 30.0 * h
        u = polar(b, 1.0)
        rs = float(field_core(np.array([u.x * 900]), np.array([u.y * 900]))["Rs"][0])
        sp.append(dict(hour=12 if h == 0 else h, bearing=b, start=rbx(polar(b, 124.0, SPOKE_TOP)),
                       end=rbx(polar(b, rs - 2.0, SPOKE_TOP)), length=round(rs - 126.0, 1), width=SPOKE_W,
                       deckY=SPOKE_TOP, landingSpur=rbx(polar(b, rs - 6.0, SPOKE_TOP)), rampFrom=rbx(polar(b, 124, 35.6)),
                       rampTo=rbx(polar(b, 64, PLAZA_Y))))
    sectors = []
    for h in HOURS:
        c = sector_centre(h)
        name, hazard, tag, dressing = SECTORS[h]
        sectors.append(dict(hour=h, name=name, centreBearing=c, fromBearing=(c - 15) % 360, toBearing=(c + 15) % 360,
                            hazard=hazard, tag=tag, staticRead=dressing,
                            canopyTint=list(CANOPY_TINT[h])))
    lt = LAYOUT["lightning"]
    lay = {
        "map": "Map2", "title": "The clock: the Catching Fire 12-sector arena at 3x (style A)",
        "generator": "art/blender/map2_clock_arena.py", "seed": SEED,
        "units": "1 stud = 0.28 m", "axes": "Roblox x east, z south (north = -Z), y up; bearings clockwise from north",
        "size": {"R": R, "acrossKm": round(2 * R * 0.28 / 1000, 2), "boundary": R,
                 "visualJungleTo": R + FIELD_VISUAL, "terrainTo": WORLD_R,
                 "why": ("Brief 3.2's recommendation: 3x the real set's ~120-170 m lagoon = the owner's guide at its own "
                         "scale bar (1 km = 345 px -> ~1.45 km across, lagoon 0.35 R, beach 0.42 R). The literal 3x "
                         "readings (R 5,360 or 7,770) break ArenaV3's budgets. Open decision for the owner; every "
                         "layout figure is a fraction of R.")},
        "sectorReading": {"sector12CentreBearing": SECTOR12_CENTRE,
                          "note": ("15 = the owner's guide: the faint sector lines run on the hour bearings, continuing "
                                   "the spokes, and sector 12 is the wedge from 12 to 1 o'clock. Brief 3.3's text puts "
                                   "the lines at 15, 45, ... (sector 12 centred on 0). Set MAP2_SECTOR12=0 to build that "
                                   "reading.")},
        "water": {"lagoonLevel": WATER, "salt": True, "waterColor": [38, 98, 96], "transparency": 0.55,
                  "reflectance": 0.6, "lagoonDepthMid": 24.0,
                  "pools": [dict(name=p["name"], hour=p["hour"], centre=rbx(p["centre"]), radius=p["radius"],
                                 level=round(p["level"], 2), fresh=True) for p in LAYOUT["pools"]]},
        "island": {"radius": ISLAND_R, "plazaY": PLAZA_Y, "plazaRadius": PLAZA_R,
                   "note": "PlazaY 46 and radius 62 kept (TerrainGen fixed inputs); the outer rock ring steps down to "
                           "the water (6-10 above it, brief 3.3); 12 ramps climb from the spoke decks (35.6) to 46."},
        "horn": {"position": [0.0, PLAZA_Y, 0.0], "mouthBearing": 180.0, "tailBearing": 0.0, "length": 90.0,
                 "mouthHeight": 40.0},
        "plates": {"radius": PLATE_R, "count": N_PLATES, "topY": PLATE_TOP,
                   "why": ("Moved from r 52 on the plaza to r 210 in the lagoon: the clock's opening is a swim from the "
                           "plate to a spoke (27 studs, ~4 s), then a run to the horn (brief 2.6, 3.3)."),
                   "list": [dict(index=p["index"], bearing=p["bearing"], position=rbx(p["pos"]),
                                 lookAt=[0.0, PLAZA_Y, 0.0]) for p in LAYOUT["plates"]]},
        "spokes": sp, "sectors": sectors,
        "landmarks": [dict(name="Horn", position=[0.0, PLAZA_Y, 0.0], yaw=0.0),
                      dict(name="IslandDeck", position=[0.0, PLAZA_Y, 0.0]),
                      dict(name="IslandRing", position=[0.0, WATER, 0.0]),
                      dict(name="LightningTree", hour=12, position=rbx(Vector((lt.x, lt.y, float(
                          grid_sample(Gc, "y", np.array([lt.x]), np.array([lt.y]))[0]))))),
                      ] + [dict(name="Pinnacle", hour=4, position=rbx(Vector((p.x, p.y, 0.0))), height=round(H, 1),
                                yaw=round(yaw, 1)) for p, H, yaw in LAYOUT["pinnacles"]]
        + [dict(name="ClayMound", hour=11, position=rbx(p), yaw=round(yaw, 1), scale=round(s, 2))
           for p, yaw, s in LAYOUT["mounds"]]
        + [dict(name="SavannaSlab", hour=7, position=rbx(p), yaw=round(yaw, 1), scale=round(s, 2))
           for p, yaw, s in LAYOUT["slabs"]],
        "grids": {
            "fine": {"file": "terrain/Map2_height_fine_u16.png", "studsPerPixel": FINE[0], "size": [Gf["n"], Gf["n"]],
                     "originXZ": [-FINE[1], -FINE[1]], "sample": "pixel centre",
                     "rows": "row 0 = the north edge (z = -2,752); rows run south (+z)",
                     "cols": "col 0 = the west edge (x = -2,752); cols run east (+x)",
                     "encoding": "y = value / 50 - 64 (16-bit, 0.02-stud steps)"},
            "coarse": {"file": "terrain/Map2_height_coarse_u16.png", "studsPerPixel": COARSE[0],
                       "size": [Gc["n"], Gc["n"]], "originXZ": [-COARSE[1], -COARSE[1]],
                       "encoding": "y = value / 50 - 64"},
            "masks": {"material": "terrain/Map2_material_u8.png (slot index, legend below; fine grid)",
                      "materialCoarse": "terrain/Map2_material_coarse_u8.png",
                      "perSlot": "terrain/Map2_mask_<key>_u8.png (255 where the slot wins; fine grid)",
                      "sector": "terrain/Map2_sector_u8.png (1-12 = hour wedge, 13 = the island, 0 = past the field)",
                      "region": "terrain/Map2_region_u8.png (%s)" % ", ".join("%d %s" % kv for kv in REGIONS.items()),
                      "waterDepth": "terrain/Map2_waterdepth_u8.png (depth = value / 8 studs; lagoon and pools)",
                      "trees": "terrain/Map2_trees_u8.png (canopy density 0-255 for the scatter)"},
        },
        "materials": [dict(index=i, key=k, base=base, slot=slot, tint="#%02x%02x%02x" % tint, rgb=list(tint),
                           share=round(counts[k], 4), use=note) for i, k, base, slot, tint, note in SLOTS],
        "biomeGrid16": {"cell": 16, "originXZ": [-FINE[1], -FINE[1]], "rows": "row 0 = north",
                        "legend": {"W": "water", "S": "sand", "s": "wet sand", "L": "lava rock", "R": "rock",
                                   "J": "jungle floor", "M": "mud", "G": "salt gully", "l": "laterite",
                                   "D": "dry grass", "X": "seared"},
                        "grid": biome16(Gf)},
    }
    p = os.path.join(OUT, "Map2_terrain.json")
    with open(p, "w") as f:
        json.dump(lay, f, indent=1)
    log("JSON", p)


def data_maps_preview(G):
    n = G["n"]
    hs = hillshade(G["y"], G["cell"])
    tab = np.zeros((16, 3))
    for i, k, base, slot, tint, note in SLOTS:
        tab[i] = tint
    mat = tab[G["mat"]] / 255.0
    water = G["depth"] > 0.3
    wc = water_colour(G["depth"]) / 255.0
    a = mat * (0.55 + 0.6 * hs[..., None])
    a[water] = wc[water]
    b = np.repeat((0.25 + 0.75 * hs)[..., None], 3, -1)
    hy = np.clip((G["y"] - 0) / 420.0, 0, 1)
    b = b * np.stack([0.55 + 0.45 * hy, 0.6 + 0.3 * hy, 0.65 + 0.1 * hy], -1)
    b[water] = (0.25, 0.45, 0.5)
    sec_cols = np.array([[0, 0, 0]] + [[0.55 + 0.35 * math.sin(k * 2.4), 0.55 + 0.35 * math.sin(k * 2.4 + 2.1),
                                        0.55 + 0.35 * math.sin(k * 2.4 + 4.2)] for k in range(1, 14)])
    c = sec_cols[np.clip(G["sec"], 0, 13)] * (0.6 + 0.4 * hs[..., None])
    c[water] = c[water] * 0.55 + 0.25
    d = np.repeat(G["dens"][..., None], 3, -1) * np.array([0.35, 0.6, 0.3]) + 0.12
    s = 688
    tiles = [resize(t, s, s) for t in (a, b, c, d)]
    sheet = np.full((2 * s + 3 * 40, 2 * s + 30, 3), 0.1)
    for k, (t, lbl) in enumerate(zip(tiles, ("MATERIAL SLOTS + WATER (4 STUDS/PX)", "HEIGHT (HILLSHADE)",
                                             "SECTORS (1-12) + ISLAND (13)", "CANOPY DENSITY"))):
        x0 = 10 + (k % 2) * (s + 10)
        y0 = 40 + (k // 2) * (s + 40)
        sheet[y0:y0 + s, x0:x0 + s] = t
        draw_text(sheet, x0, y0 - 34, lbl, scale=3, bg=None)
    write_rgb(os.path.join(PREV, "data_maps.png"), sheet)
    log("PREVIEW data_maps.png")


# =============================================================================================== GLB export
def to_roblox_bounds(objs):
    lo = np.array([1e9] * 3)
    hi = -lo
    for o in objs:
        co = np.empty(len(o.data.vertices) * 3, np.float32)
        o.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3).astype(np.float64)
        M4 = np.array(o.matrix_world)
        w = co @ M4[:3, :3].T + M4[:3, 3]
        rb = np.stack([w[:, 0], w[:, 2], -w[:, 1]], 1)
        lo = np.minimum(lo, rb.min(0))
        hi = np.maximum(hi, rb.max(0))
    return lo, hi


GLB_ASSETS = [
    # name, builder, kind, tags, pivot note, notes, collision rules per role
    ("Horn", lambda: build_horn(), "Landmark", ["Map2", "Horn"], "deck centre (place at y 46, tail north)",
     "10 staves of 2-3 faceted steel shards curve into a horn 90 long and ~40 tall at the mouth; 5 chunky shards "
     "bloom at the mouth; 3 girders lie splayed on the deck. Tail = Roblox -Z (north, the file's LookVector), mouth = "
     "Roblox +Z (south, toward 6). Stepped basalt floor and the racks/crates are separate parts. Brief metal: "
     "metalness 0.85, roughness 0.4 (the Blender previews use 0.55/0.5 to read under Blender's darker sky).",
     {"Steel": ("Metal", "PreciseConvexDecomposition", True), "Floor": ("Basalt", "Default", True),
      "Racks": ("WoodPlanks", "Box", False)}),
    ("IslandDeck", lambda: build_island_deck(), "Landmark", ["Map2", "Island"], "plaza centre at y 46",
     "Hex basalt pavers round the horn floor, tops at +0.25.", {"Paving": ("Basalt", "Default", True)}),
    ("IslandRing", lambda: build_island_ring(), "Landmark", ["Map2", "Island"], "island centre on the water (y 34)",
     "Tumbled basalt ring (6 arcs) and the 12 stepped ramps from the spoke decks (35.6) to the plaza (46).",
     {"*": ("Basalt", "Default", True)}),
    ("Plate", lambda: build_plate(), "Plinth", ["Map2", "Plinth", "Plate"], "waterline (y 34); top at +2",
     "Lagoon launch plate: steel drum, copper top, fluted column to -28, float collar with a brass rim.",
     {"Steel": ("Metal", "Hull", True), "Copper": ("Metal", "Box", True), "Collar": ("Metal", "Box", False)}),
    ("SpokeModule_A", lambda: build_spoke_module(SEED + 310), "Causeway", ["Map2", "Spoke"],
     "deck top centre (y 35.6); length along Roblox Z", "40-stud spoke module: hex column deck, tumbled sides.",
     {"Deck": ("Basalt", "Default", True), "Rock": ("Basalt", "Hull", True)}),
    ("SpokeModule_B", lambda: build_spoke_module(SEED + 311), "Causeway", ["Map2", "Spoke"],
     "deck top centre (y 35.6)", "Variant B.", {"Deck": ("Basalt", "Default", True), "Rock": ("Basalt", "Hull", True)}),
    ("SpokeModule_C", lambda: build_spoke_module(SEED + 312), "Causeway", ["Map2", "Spoke"],
     "deck top centre (y 35.6)", "Variant C.", {"Deck": ("Basalt", "Default", True), "Rock": ("Basalt", "Hull", True)}),
    ("SpokeSpur", lambda: build_spur(), "Causeway", ["Map2", "Spoke"], "shore end at deck level (y 35.6), runs inland",
     "Landing spur: the spoke deck rising 2.2 over 75 studs into the beach.", {"Rock": ("Basalt", "Default", True)}),
    ("LightningTree", lambda: build_lightning_tree(), "Landmark", ["Map2", "Sector12", "Tree"], "trunk base",
     "180-stud bleached dead giant with a lightning scar (Sector 12).",
     {"Bark": ("Wood", "Hull", True), "Scar": ("Wood", "Box", False)}),
    ("Pinnacle_A", lambda: build_pinnacle(SEED + 350, 175.0), "Landmark", ["Map2", "Sector4", "Rock"], "base centre",
     "Basalt sea-stack, 175 tall (placed scaled 0.9-1.09).", {"Rock": ("Basalt", "Default", True)}),
    ("Pinnacle_B", lambda: build_pinnacle(SEED + 351, 140.0), "Landmark", ["Map2", "Sector4", "Rock"], "base centre",
     "Basalt sea-stack, 140 tall (placed scaled 0.93-1.13).", {"Rock": ("Basalt", "Default", True)}),
    ("ClayMound_A", lambda: build_mound(49, 9), "Prop", ["Map2", "Sector11"], "base centre",
     "Ochre clay insect mound, 9 tall.", {"Clay": ("Ground", "Hull", True)}),
    ("ClayMound_B", lambda: build_mound(50, 13), "Prop", ["Map2", "Sector11"], "base centre",
     "Ochre clay insect mound, 13 tall.", {"Clay": ("Ground", "Hull", True)}),
]


def glb_stage():
    reset_scene()
    sc = bpy.context.scene
    col = coll("export")
    entries = []
    x_cursor = 0.0
    all_objs = []
    warnings = []
    for name, fn, kind, tags, pivot, notes, rules in GLB_ASSETS:
        parts = fn()
        if name.startswith("Clay"):
            parts = [("Clay", parts, "paint")]
        built = []
        for role, mb, mk in parts:
            if not mb.F:
                continue
            o = mb_object(mb, "%s_%s" % (name, role), None, col)
            built.append((role, o, mk))
        lo, hi = to_roblox_bounds([o for _, o, _ in built])
        width = hi[0] - lo[0]
        x_cursor += -lo[0] + 4.0
        for _, o, _ in built:
            o.location.x = x_cursor
        part_entries = []
        tris_total = 0
        for role, o, mk in built:
            m = new_mat("MX_%s_%s" % (name, role))
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = (1, 1, 1, 1)
            b.inputs["Metallic"].default_value = 0.85 if mk == "metal" else 0.0
            b.inputs["Roughness"].default_value = 0.4 if mk == "metal" else 0.88
            vc = m.node_tree.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "col"
            m.node_tree.links.new(vc.outputs["Color"], b.inputs["Base Color"])
            o.data.materials.append(m)
            rm, colli, collide = rules.get(role, rules.get("*", ("Rock", "Default", True)))
            t = int(o["tris"])
            tris_total += t
            if t > 5000:
                warnings.append("%s_%s has %d triangles (part budget 5,000)" % (name, role, t))
            part_entries.append(dict(name=o.name, role=role, robloxMaterial=rm, rgb=list(o["rgb"]), collide=collide,
                                     collision=colli if collide else "Box", castShadow=True, canQuery=collide,
                                     canTouch=collide, tags=[], tris=t))
        lo_rel = lo.copy()
        entries.append(dict(name=name, kind=kind, tags=tags, notes=notes, pivot=pivot,
                            origin=[round(x_cursor, 3), 0.0, 0.0], size=[round(float(v), 3) for v in hi - lo],
                            boundsMin=[round(float(v), 3) for v in lo_rel], boundsMax=[round(float(v), 3) for v in hi],
                            tris=tris_total, parts=part_entries, attachments=attachments_for(name)))
        x_cursor += hi[0] + 4.0
        all_objs += [o for _, o, _ in built]
    for o in all_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = all_objs[0]
    glb = os.path.join(OUT, "Map2_Landmarks.glb")
    kw = dict(filepath=glb, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
              export_cameras=False, export_lights=False, export_extras=False, export_materials="EXPORT",
              export_normals=True, export_texcoords=False, export_tangents=False)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    mb_ = os.path.getsize(glb) / 1e6
    man = dict(schema="LS-Map2-1 (landmarks)", category="Map2Landmarks", glb="Map2_Landmarks.glb", glbs=1,
               units="1 Blender unit = 1 Roblox stud (world scale)",
               axes="Roblox (x, y, z) = Blender (x, z, -y); assets laid out in a row along X; origin = pivot in the file",
               colour=("Per-facet painted colour is in COLOR_0 (vertex colour, flat per facet); every material's base "
                       "colour is white so COLOR_0 shows as painted. Each part's rgb is the mean painted colour (use "
                       "it as MeshPart.Color). Texture sets are NOT baked yet: run the style A bake (style_a.bake_set) "
                       "before any upload."),
               placement="See Map2_terrain.json: landmarks, plates, spokes (one module every 40 studs from r 124).",
               assets=entries, warnings=warnings)
    mp = os.path.join(OUT, "Map2_Landmarks.manifest.json")
    with open(mp, "w") as f:
        json.dump(man, f, indent=1)
    os.makedirs(MANIFEST_COPY, exist_ok=True)
    with open(os.path.join(MANIFEST_COPY, "Map2_Landmarks.manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    log("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (glb, mb_, len(entries), len(warnings)))
    for w in warnings:
        log("WARNING", w)
    for e in entries:
        log("  %-14s tris %6d size %s" % (e["name"], e["tris"], e["size"]))


def attachments_for(name):
    if name == "Plate":
        return {"Stand": dict(position=[0.0, 2.0, 0.0], look=[0.0, 0.0, -1.0], up=[0.0, 1.0, 0.0])}
    if name == "Horn":
        return {"Mouth": dict(position=[0.0, 1.6, 44.0], look=[0.0, 0.0, 1.0], up=[0.0, 1.0, 0.0]),
                "Tail": dict(position=[0.0, 16.0, -46.0], look=[0.0, 0.0, -1.0], up=[0.0, 1.0, 0.0])}
    if name.startswith("SpokeModule"):
        return {"EndIn": dict(position=[0.0, 0.0, 20.0], look=[0.0, 0.0, 1.0], up=[0.0, 1.0, 0.0]),
                "EndOut": dict(position=[0.0, 0.0, -20.0], look=[0.0, 0.0, -1.0], up=[0.0, 1.0, 0.0])}
    if name == "LightningTree":
        return {"StrikePoint": dict(position=[1.6, 176.0, 0.4], look=[0.0, 1.0, 0.0], up=[0.0, 0.0, -1.0])}
    return {}


# =============================================================================================== render
RIGS = {
    "day": dict(elev=52.0, bearing=205.0, strength=0.075, exposure=-0.7, haze_L=16000.0, aerosol=2.2, air=1.0,
                tint=(1.0, 1.0, 1.0)),
    "noon": dict(elev=64.0, bearing=195.0, strength=0.075, exposure=-0.75, haze_L=1e9, aerosol=2.0, air=1.0,
                 tint=(1.0, 1.0, 1.0)),
    "dusk": dict(elev=9.5, bearing=232.0, strength=0.075, exposure=0.55, haze_L=9000.0, aerosol=3.2, air=1.3,
                 tint=(1.5, 0.86, 0.95)),
}


def enable_gpu(scene):
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if [d for d in prefs.devices if d.type == kind]:
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


def render_setup(sc):
    dev = enable_gpu(sc)
    c = sc.cycles
    c.samples = SAMPLES
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.03
    c.use_denoising = True
    try:
        c.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    c.max_bounces = 5
    c.diffuse_bounces = 2
    c.glossy_bounces = 2
    c.transmission_bounces = 2
    c.transparent_max_bounces = 12
    c.volume_bounces = 0
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.sample_clamp_indirect = 8.0
    sc.render.use_persistent_data = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "8"
    sc.render.resolution_percentage = 100
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        log("WARNING AgX look not found")
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    if getattr(w, "node_tree", None) is None:
        w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_disc = True
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.name = "SkyTint"
    mix.inputs[0].default_value = 1.0
    nt.links.new(sky.outputs[0], mix.inputs[6])
    nt.links.new(mix.outputs[2], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    log("RENDER device", dev)


def set_rig(sc, key):
    rg = RIGS[key]
    nt = sc.world.node_tree
    sky = [n for n in nt.nodes if n.type == "TEX_SKY"][0]
    bg = [n for n in nt.nodes if n.type == "BACKGROUND"][0]
    sky.sun_elevation = math.radians(rg["elev"])
    sky.sun_rotation = math.radians(rg["bearing"])
    for attr, v in (("aerosol_density", rg["aerosol"]), ("dust_density", rg["aerosol"]), ("air_density", rg["air"]),
                    ("altitude", 120.0)):
        try:
            setattr(sky, attr, v)
        except Exception:
            pass
    bg.inputs["Strength"].default_value = rg["strength"]
    sc.view_settings.exposure = rg["exposure"]
    tn = nt.nodes.get("SkyTint")
    if tn is not None:
        tn.inputs[7].default_value = (*rg.get("tint", (1.0, 1.0, 1.0)), 1.0)


def camera(sc, loc, target, vfov=None, ortho=None, res=(1600, 900), clip=(0.5, 90000.0), roll=0.0):
    cam = bpy.data.objects.get("PrevCam")
    if cam is None:
        cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        cam.data.sensor_fit = "HORIZONTAL"
        cam.data.ortho_scale = ortho
    else:
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle = math.radians(vfov)
    cam.data.clip_start, cam.data.clip_end = clip
    cam.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    q = d.to_track_quat("-Z", "Y")
    cam.rotation_euler = q.to_euler()
    if roll:
        cam.rotation_euler.rotate_axis("Z", math.radians(roll))
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    return cam


def haze_set(colour_lin, L, camz):
    ng = haze_group()
    ng.nodes["HazeCol"].outputs[0].default_value = (*[float(v) for v in colour_lin], 1.0)
    ng.nodes["HazeL"].outputs[0].default_value = float(L)
    ng.nodes["CamZ"].outputs[0].default_value = float(camz)


def calibrate_haze(sc, bearing):
    """Sky radiance just above the horizon toward the view bearing (render of the sky alone)."""
    hidden = []
    for o in sc.objects:
        if not o.hide_render and o.type != "CAMERA":
            o.hide_render = True
            hidden.append(o)
    cam = camera(sc, (0, 0, 60), polar(bearing, 1000.0, 60.0), vfov=6.0, res=(48, 24))
    st = sc.cycles.samples
    sc.cycles.samples = 8
    fmt = sc.render.image_settings.file_format
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_depth = "32"
    p = os.path.join(WORK, "haze_cal.exr")
    sc.render.filepath = p
    vt = sc.view_settings.view_transform
    bpy.ops.render.render(write_still=True)
    sc.render.image_settings.file_format = fmt
    sc.render.image_settings.color_depth = "8"
    sc.cycles.samples = st
    for o in hidden:
        o.hide_render = False
    a = load_linear(p)
    h = a.shape[0]
    band = a[int(h * 0.2):int(h * 0.42), :, :3].reshape(-1, 3)
    col = band.mean(0)
    return col


def tone_check(path, name, stats):
    img = load_rgb(path)
    mx = img.max(-1)
    mn = img.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    lum = luma255(img * 255.0)
    hi = float(((sat > 0.55) & (mx > 0.25)).mean())
    vivid = float(((sat > 0.7) & (mx > 0.35)).mean())
    st = dict(lumaMean=round(float(lum.mean()), 1), lumaP1=round(float(np.percentile(lum, 1)), 1),
              lumaP99=round(float(np.percentile(lum, 99)), 1), satMean=round(float(sat.mean()), 3),
              satP95=round(float(np.percentile(sat, 95)), 3), highSatShare=round(hi, 4), vividShare=round(vivid, 4))
    stats[name] = st
    log("TONES %-10s luma %.0f (p1 %.0f, p99 %.0f) sat mean %.2f p95 %.2f, sat>0.55 %.2f%%, vivid %.2f%%" % (
        name, st["lumaMean"], st["lumaP1"], st["lumaP99"], st["satMean"], st["satP95"], hi * 100, vivid * 100))
    return img


def sample_topdown(img, ortho, res, stats):
    """Mean rendered colour of known regions in the straight-down view."""
    W, H = res
    sc_ = ortho / W

    def px(x, y):
        return int(round(W / 2 + x / sc_)), int(round(H / 2 - y / sc_))
    out = {}
    for label, r0, r1 in (("lagoon deep (r 300-600)", 300, 600), ("beach (r 960-1040)", 960, 1040),
                          ("jungle (r 1500-2400)", 1500, 2400)):
        cols = []
        for b in np.arange(4, 360, 7.0):
            if boundary_deg(b) < 3.0:
                continue
            for rr in np.linspace(r0, r1, 6):
                p = polar(float(b), float(rr))
                x, y = px(p.x, p.y)
                if 0 <= x < W and 0 <= y < H:
                    cols.append(img[y, x])
        c = np.array(cols).mean(0) * 255.0
        out[label] = [int(v) for v in c]
    for h in HOURS:
        cols = []
        for b in sector_centre(h) + np.linspace(-9, 9, 7):
            for rr in np.linspace(1350, 2350, 9):
                p = polar(float(b), float(rr))
                x, y = px(p.x, p.y)
                cols.append(img[y, x])
        out["sector %d" % h] = [int(v) for v in np.array(cols).mean(0) * 255.0]
    stats["topdownSamples"] = out
    log("TOPDOWN samples", json.dumps(out))


def views():
    pl = LAYOUT["plates"][1]          # the plate at 22.5 deg, between the 12 and 1 spokes
    pp = polar(pl["bearing"], PLATE_R, PLATE_TOP)
    look_b = 64.0
    look = polar(look_b, 1.0)
    fig_yaw = -math.radians(look_b)
    cam_p = pp - look * 15.0 + Vector((0, 0, 7.4))
    V = {
        "overview": dict(rig="day", loc=(0.0, -5600.0, 7100.0), target=(0.0, 150.0, 60.0), vfov=30.0,
                         res=(1920, 1080), file="overview_high_aerial.png", haze_L=26000.0, dome=True),
        "birdseye": dict(rig="day", loc=tuple(polar(205.0, 2350.0, 1380.0)), target=(0.0, 120.0, 40.0), vfov=44.0,
                         res=(1920, 1080), file="birdseye_34.png", haze_L=20000.0),
        "topdown": dict(rig="noon", loc=(0.0, 0.0, 9000.0), target=(0.0, 0.0, 0.0), ortho=2 * R * 554.0 / 500.0,
                        res=(1108, 1188), file="topdown_ortho.png", ref="owner/map2_clock_arena_reference.png",
                        compare="compare_guide_topdown.png", label="OWNER GUIDE - SECTOR TRAP OVERVIEW (FAN-MADE)"),
        "lagoon": dict(rig="noon", loc=(0.0, 0.0, 9000.0), target=(0.0, 0.0, 0.0), ortho=2 * SHORE_R * 1.105 * 668 / 520,
                       res=(1336, 1040), file="lagoon_ortho.png", ref="web/map2_film_set_satellite_lagoon_jonesboro.png",
                       compare="compare_satellite_lagoon.png", label="FILM SET FROM ABOVE (JONESBORO, 3 SPOKES BUILT)"),
        "concept": dict(rig="dusk", loc=tuple(polar(211.2, 292.0, 40.4)), target=(-4.0, -12.0, 60.0), vfov=29.0,
                        res=(1600, 904), file="view_concept_island.png",
                        ref="web/map2_concept_art_cornucopia_faceted.png", compare="compare_concept_island.png",
                        label="CATCHING FIRE CONCEPT ART - THE HORN ON ITS ISLAND"),
        "girders": dict(rig="day", loc=tuple(polar(262.0, 520.0, 38.6)), target=(0.0, 4.0, 52.0), vfov=9.2,
                        res=(1600, 664), file="view_horn_jungle.png",
                        ref="web/map2_film_still_cornucopia_girders_jungle.png", compare="compare_film_horn_jungle.png",
                        label="CATCHING FIRE FILM STILL - THE HORN AGAINST THE JUNGLE"),
        "plate": dict(rig="day", loc=tuple(cam_p), target=tuple(pp + look * 140.0 + Vector((0, 0, 0.5))),
                      vfov=30.0, res=(1128, 600), file="view_plate_rise.png",
                      ref="web/map2_film_still_rise_in_lagoon_spoke.jpg", compare="compare_plate_rise.png",
                      label="CATCHING FIRE STILL - RISING IN THE LAGOON BY A SPOKE", crop=True,
                      figure=(pp, fig_yaw)),
    }
    return V


def render_stage(sc=None):
    if sc is None:
        p = os.path.join(WORK, "map2_scene.blend")
        bpy.ops.wm.open_mainfile(filepath=p)
        sc = bpy.context.scene
        solve_pools()
    render_setup(sc)
    Vs = views()
    want = list(Vs.keys()) + ["sectors"] if VIEW_ARG == "all" else VIEW_ARG.split(",")
    stats = {}
    sp = os.path.join(PREV, "tones.json")
    if os.path.exists(sp):
        try:
            stats = json.load(open(sp))
        except Exception:
            stats = {}
    fig = bpy.data.objects.get("Figure")
    dome = bpy.data.collections.get("dome")
    for name in want:
        if name == "sectors":
            sector_sheet(sc, stats)
            continue
        v = Vs[name]
        set_rig(sc, v["rig"])
        if dome is not None:
            dome.hide_render = not v.get("dome", False)
        if fig is not None:
            fig.hide_render = "figure" not in v
            if "figure" in v:
                p, yaw = v["figure"]
                fig.location = p
                fig.rotation_euler = (0, 0, yaw)
        if v.get("ortho"):
            haze_set((0.5, 0.5, 0.5), 1e9, 9000.0)
            camera(sc, v["loc"], v["target"], ortho=v["ortho"], res=v["res"], clip=(10.0, 20000.0), roll=0.0)
            cam = sc.camera
            cam.rotation_euler = (0.0, 0.0, 0.0)
        else:
            d = Vector(v["target"]) - Vector(v["loc"])
            bearing = math.degrees(math.atan2(d.x, d.y)) % 360.0
            hc = calibrate_haze(sc, bearing)
            haze_set(hc * 0.97, v.get("haze_L", RIGS[v["rig"]]["haze_L"]), v["loc"][2])
            camera(sc, v["loc"], v["target"], vfov=v["vfov"], res=v["res"],
                   clip=(0.3 if name == "plate" else 2.0, 90000.0))
        out = os.path.join(PREV, v["file"])
        sc.render.filepath = out
        t = time.time()
        bpy.ops.render.render(write_still=True)
        log("RENDER %s (%.0fs)" % (out, time.time() - t))
        img = tone_check(out, name, stats)
        if name == "topdown":
            sample_topdown(img, v["ortho"], v["res"], stats)
    if fig is not None:
        fig.hide_render = True
    with open(sp, "w") as f:
        json.dump(stats, f, indent=1)


def sector_sheet(sc, stats):
    set_rig(sc, "day")
    if bpy.data.collections.get("dome") is not None:
        bpy.data.collections["dome"].hide_render = True
    tiles = []
    res = (640, 360)
    for h in HOURS:
        c = sector_centre(h)
        loc = polar(c, 560.0, 150.0)
        tgt = polar(c, 1650.0, 128.0)
        hc = calibrate_haze(sc, c)
        haze_set(hc * 0.97, RIGS["day"]["haze_L"], 150.0)
        camera(sc, loc, tgt, vfov=31.0, res=res, clip=(2.0, 90000.0))
        p = os.path.join(WORK, "sector_%02d.png" % h)
        sc.render.filepath = p
        st = sc.cycles.samples
        sc.cycles.samples = max(16, SAMPLES // 2)
        bpy.ops.render.render(write_still=True)
        sc.cycles.samples = st
        tiles.append((h, load_rgb(p)))
        log("SECTOR %d rendered" % h)
    cols, rows = 4, 3
    W, H = res
    gap = 8
    sheet = np.full((rows * (H + gap) + gap, cols * (W + gap) + gap, 3), 0.08)
    for k, (h, img) in enumerate(tiles):
        x0 = gap + (k % cols) * (W + gap)
        y0 = gap + (k // cols) * (H + gap)
        sheet[y0:y0 + H, x0:x0 + W] = img
        draw_text(sheet, x0 + 6, y0 + 6, "%d  %s" % (h, SECTORS[h][0]), scale=3)
    out = os.path.join(PREV, "sector_reads.png")
    write_rgb(out, sheet)
    tone_check(out, "sectors", stats)
    log("SHEET", out)


# =============================================================================================== compare sheets
def draw_label(img, x, y, width, text, bg, scale=2):
    """Word-wrapped 5x7 label that stays inside its panel (at most two lines)."""
    per = max(8, (width - 12) // (6 * scale))
    lines, cur = [], ""
    for w in text.split(" "):
        if len(cur) + len(w) + (1 if cur else 0) > per:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w) if cur else w
    lines.append(cur)
    for i, ln in enumerate(lines[:2]):
        draw_text(img, x, y + i * (7 * scale + 10), ln, scale=scale, bg=bg, pad=4)


def crop_black(img, thr=0.06):
    m = img.max(-1) > thr
    rows = np.where(m.mean(1) > 0.3)[0]
    cols = np.where(m.mean(0) > 0.3)[0]
    if len(rows) < 10 or len(cols) < 10:
        return img
    return img[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]


def compare_stage():
    Vs = views()
    for name, v in Vs.items():
        if "ref" not in v:
            continue
        ref_p = os.path.join(REFS, *v["ref"].split("/"))
        ours_p = os.path.join(PREV, v["file"])
        if not (os.path.exists(ref_p) and os.path.exists(ours_p)):
            log("WARNING compare %s: missing %s" % (name, ref_p if not os.path.exists(ref_p) else ours_p))
            continue
        ref = load_rgb(ref_p)
        if v.get("crop"):
            ref = crop_black(ref)
        ours = load_rgb(ours_p)
        Hh = 640
        wr = int(round(ref.shape[1] * Hh / ref.shape[0]))
        wo = int(round(ours.shape[1] * Hh / ours.shape[0]))
        gap, band = 12, 64
        canvas = np.full((Hh + band + 2 * gap, wr + wo + 3 * gap, 3), 0.1)
        canvas[band + gap:band + gap + Hh, gap:gap + wr] = resize(ref, wr, Hh)
        canvas[band + gap:band + gap + Hh, 2 * gap + wr:2 * gap + wr + wo] = resize(ours, wo, Hh)
        draw_label(canvas, gap, 6, wr, "REF (STUDY ONLY): " + v["label"], (0.18, 0.08, 0.06))
        draw_label(canvas, 2 * gap + wr, 6, wo, "OURS: MAP 2 IN STYLE A, R 2600 STUDS - " + name.upper(),
                   (0.06, 0.12, 0.08))
        out = os.path.join(PREV, v["compare"])
        write_rgb(out, canvas)
        log("COMPARE", out)
    gi = os.path.join(PREV, ".gitignore")
    with open(gi, "w") as f:
        f.write("# compare_*.png carry film/fan reference frames beside our renders: study only, never commit them\n"
                "# (owner rule: reference images never go into the game or the repo). Regenerate with\n"
                "# art/blender/map2_clock_arena.py (stage compare).\ncompare_*.png\n")


# =============================================================================================== main
def main():
    log("MAP2 R %.0f, sector 12 centre %.0f deg, stages %s, views %s, out %s, previews %s" % (
        R, SECTOR12_CENTRE, STAGES, VIEW_ARG, OUT, PREV))
    G = None
    sc = None
    if "data" in STAGES:
        G = data_stage()
    if "build" in STAGES:
        if G is None:
            solve_pools()
            p = os.path.join(WORK, "coarse.npz")
            if os.path.exists(p):
                z = np.load(p)
                G = {k: z[k] for k in z.files}
                G["cell"], G["half"], G["n"] = float(G["cell"]), float(G["half"]), int(G["n"])
            else:
                G = field_grid(*COARSE)
        sc, C, M = build_scene(G)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "map2_scene.blend"), compress=False)
        log("SAVED scene", os.path.join(WORK, "map2_scene.blend"))
    if "render" in STAGES:
        render_stage(sc)
    if "compare" in STAGES:
        compare_stage()
    if "glb" in STAGES:
        glb_stage()
    log("DONE")


if __name__ == "__main__":
    main()
