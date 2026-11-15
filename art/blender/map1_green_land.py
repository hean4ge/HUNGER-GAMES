"""
map1_green_land.py - HUNGER GAMES (BETA) / LAST STANDING, Map 1 "the green land" (Blender 5.3, headless).

What it is
  A seeded generator that recreates Map 1 from docs/design/UpcomingFilm_Brief.md section 1 (the green land of
  *Sunrise on the Reaping*) at true game scale, in ArtStyle.md style A ("faceted realism"): chunky flat-shaded
  facets, painted per-facet colour in the semi-real light band, no textures, no cards. Every mesh is generated
  here; the reference frames are only ever read by the compare stage, which writes OUTSIDE the repo.

Size (brief 1.2): play radius r 1,800 studs (504 m, the arena is ~1 km across), ArenaV3's wall foot ~r 1,846,
  Boundary r 1,900, terrain to r 2,750 (heightmap +-2,752). The film's high aerial (FE @26.9 s) shows the ring as a
  small disc on a broad grass shoulder with 300-500 m of open grass before scrub, forest and crags, inside one
  glacial valley (Valle de Lago); ArenaV3's grids, scatter caps, phone memory and the 15-minute round are all built
  for this radius, so the book's "miles" of meadow do not override it.
Heart (brief 1.4, ring moved out): knoll y 46 (flat to r 50), star platform deck y 52, 48 plinths at r 150
  (y ~44.3, 7.5 deg apart, offset 3.75), turf to r 180, protected disc r 0-200 fading out by r 255.
  - Today's r 52 ring / r 62 plaza is NOT kept: 48 plinths at r 52 would stand 6.8 studs (1.9 m) apart, inside the
    100-stud platform's points (r 50), with no room for the flower spokes.
  - The brief's r 120 is NOT kept either (an open decision for the lead). In the owner's frame (T1 @1.7 s) the ring
    is roughly 6x as wide as the horn (rough pixel measure, ~495 px against ~78 px on the 800 px trailer frame). With
    the brief's own horn (12-15 m, our sails 50 studs, skirts ~57 across) that puts the ring near r 150-170; by the
    same ratio, at r 120 our horn would read about 50% too big for its ring. r 150 keeps the brief's horn and is close
    to the frame's proportions in compare_owner_t1_1.7s. The cost: the plinths stand 19.6 studs (5.5 m) apart, over the
    brief's 4-5 m estimate from the tributes. TerrainGen's fixed plaza inputs become: 48 plates at r 150, turf r 180,
    protected disc r 200-255 (the brief's build note had r 120 / 150 / 170-210).
  - Beds: the frame reads as more beds than the brief's 15 (roughly 5-7 per quarter, an estimate). 24 radial
    positions every 15 deg (offset 7.5, so they fall between plinths and the mouth bearings 60/180/300 fall between
    beds); the 6 positions beside the mouths hold the teardrops (periwinkle and marigold), the other 18 are pointed
    spokes 9 wide from the platform to r 140 (~90-104 long), in the brief's 5-colour cycle.

Landforms (brief 1.3): the almond ("eye") valley floor N-S; east and west limestone ridges (crests ~320-470 near
  r 1,550-1,750, a narrow crag band under the crest); the North Wood rising to the flat Edge (y ~240) and its
  107-stud cliff over the canyon (floor ~133); the South Mountain under the peak mesh (summit y 640); the lake (water
  34, 14 deep) and the stepped stony stream; ArenaV3's wall (18-stud step at r ~1,846 +-85) and a continuous massif
  (crests 700-1,000 at r ~2,150-2,450) falling to ~120 at r 2,750. Slope budget (ArenaV3 3): 86% of the play disc
  is under 30 deg; the steep ground is the ridge crag bands, the mountain, the Edge and the wall.

Colour: every tone is UpcomingFilm_Brief 1.10's semi-real palette (PAL). Renders use the Standard view transform
  (no film look, no AgX desaturation) and a sun calibrated so a lit flat facet shows about its painted value; saturated
  colour stays on the signals (beds, copper plates, berries). Render-only stand-ins, never exported: the gradient sky,
  the volumetric cloud layers (the game's Atmosphere, Clouds and particle sheets), the distance haze, the far ring of
  mountains past r 2,650, the horn's interior fill light, the white tribute figures and the tube shadows.

Coordinates: 1 Blender unit = 1 stud. Blender x = east, y = north, z = up. Roblox (X, Y, Z) = Blender (x, z, -y).
  Bearings are degrees clockwise from north (Roblox -Z), r is the distance from the horn's axis.

Run (from the repo root):
  blender --background --factory-startup --python art/blender/map1_green_land.py -- <export dir> <preview dir> [stages] [shots]
  export dir   default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Map1
  preview dir  default art/previews/Map1
  stages       comma list of data, assets, scene, render, compare (default: all). "render" alone reloads the saved
               scene from the work folder. "-" keeps a default.
  shots        comma list of shot names (default: all), see SHOTS below.
  env MAP1_WORK     work folder (default %TEMP%/Map1_build): field cache, scene .blend
  env MAP1_COMPARE  compare-sheet folder (default <MAP1_REF>/compare/Map1). Compare sheets contain film frames, so
                    by default they live beside the references, out of the repo and out of the game (study only).
  env MAP1_REF      reference folder (default %USERPROFILE%/OneDrive/Documents/LastStanding/References)
  env MAP1_SAMPLES  Cycles samples (default 96); env MAP1_RES = resolution scale (default 1.0)

Outputs
  <export dir>/Map1_Height.png         16-bit grey, 1,376 x 1,376, 4 studs/px, y = value / 32 studs
  <export dir>/Map1_Material.png       8-bit terrain-slot index (legend in Map1_Terrain.json), 4 studs/px
  <export dir>/Map1_Region.png         8-bit region index, 4 studs/px
  <export dir>/Map1_WaterMask.png, Map1_WaterLevel.png (16-bit, same encoding as the height)
  <export dir>/Map1_Mask_<Kind>.png    8-bit scatter densities (Conifer, Broadleaf, Gorse, Heather, Boulders,
                                       TallGrass, Wildflowers, Crags), 4 studs/px
  <export dir>/Map1_BiomeGrid16.json   240 x 240 region ids, 16-stud cells over +-1,920 (Shared.BiomeGrid layout)
  <export dir>/Map1_Terrain.json       grid metadata, legends, palette, stream polyline, lake, trails
  <export dir>/Map1_Layout.json        every landmark placement in Roblox space
  <export dir>/Map1_Landmarks.glb + .manifest.json   landmark meshes (pivots, sizes, triangle counts)
  <export dir>/Map1_Plants.glb + .manifest.json      faceted PLACEHOLDER plants (layout tests only)
  art/manifests/Map1_*.manifest.json   copies of the manifests
  <preview dir>/*.png                  our renders only (no film frames): overview_aerial, birdseye_34, match_<frame>,
                                       data_maps (hillshade + slots + layout dots)
  <MAP1_COMPARE>/compare_<frame>.png   the film frame (study only) beside our matching render; never in the repo
"""
import json
import math
import os
import random
import shutil
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
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def _arg(i, default):
    return ARGV[i] if len(ARGV) > i and ARGV[i] not in ("", "-") else default


DOCS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding")
OUT = os.path.abspath(_arg(0, os.path.join(DOCS, "BlenderExports", "Map1")))
PREV = os.path.abspath(_arg(1, os.path.join(REPO, "art", "previews", "Map1")))
STAGES = [s.strip() for s in _arg(2, "data,assets,scene,render,compare").split(",") if s.strip()]
SHOT_FILTER = [s.strip() for s in _arg(3, "").split(",") if s.strip()]
WORK = os.environ.get("MAP1_WORK") or os.path.join(tempfile.gettempdir(), "Map1_build")
REF = os.environ.get("MAP1_REF") or os.path.join(DOCS, "References")
COMPARE = os.environ.get("MAP1_COMPARE") or os.path.join(REF, "compare", "Map1")
SAMPLES = int(os.environ.get("MAP1_SAMPLES", "96"))
RES_SCALE = float(os.environ.get("MAP1_RES", "1.0"))
MANIFEST_COPY = os.path.join(REPO, "art", "manifests")
for _d in (OUT, PREV, WORK):
    os.makedirs(_d, exist_ok=True)

SEED = 50                      # the 50th Games
TAU = 2.0 * math.pi

# ------------------------------------------------------------------------------------------------ grid and scale
SPP = 4.0                      # studs per pixel of every exported raster
HALF = 2752.0                  # rasters cover x, z in [-2,752, 2,752]
NF = int(2 * HALF / SPP)       # 1,376
PLAY_R = 1800.0
WALL_R = 1846.0
BOUNDARY_R = 1900.0
PLAZA_Y = 46.0
DECK_Y = 52.0
RING_R = 150.0
N_PLINTH = 48
TURF_R = 180.0
LAKE_Y = 34.0
HEIGHT_SCALE = 32.0            # 16-bit height = y * 32 (0..2,047.97 studs, 1/32-stud steps)

# ------------------------------------------------------------------------------------------------ palette
# Semi-real tones from UpcomingFilm_Brief.md 1.10 (sampled from the frames, grade removed, softened, clamped into
# ArtStyle's light band). sRGB 0-255. Saturated values are kept only for signals (beds, copper plates, berries).
PAL = {
    "sky_zenith": (104, 146, 186), "sky_horizon": (180, 200, 214), "cloud": (246, 246, 248),
    "mist": (222, 226, 226), "haze": (204, 212, 218),
    "turf": (92, 120, 54), "meadow": (106, 124, 66), "dry": (128, 128, 80),
    "needles": (56, 76, 52), "needles_pine": (62, 80, 54), "broadleaf": (72, 90, 52),
    "pine_bark": (124, 96, 80), "fir_bark": (112, 98, 86), "beech_bark": (122, 112, 94),
    "forest_floor": (100, 86, 66), "path": (120, 106, 86),
    "gorse_body": (62, 78, 42), "gorse_flower": (204, 176, 66),
    "heather": (132, 84, 112), "heather_pink": (182, 128, 138),
    "yellow": (204, 180, 72), "red": (178, 70, 68), "pink": (198, 142, 156), "lavender": (136, 138, 184),
    "magenta": (158, 86, 126), "periwinkle": (124, 152, 198), "fleck": (218, 216, 204), "marigold": (212, 152, 60),
    "crimson": (150, 44, 56), "bed_foliage": (66, 88, 46), "holly": (52, 72, 46), "berry": (176, 40, 44),
    "limestone": (156, 152, 140), "white_boulder": (164, 162, 152), "scree": (140, 124, 104),
    "dark_rock": (108, 106, 100), "pebbles": (126, 120, 106), "mud": (92, 80, 64),
    "water": (40, 94, 100),
    "sail": (208, 210, 206), "inner": (74, 60, 92), "inner_navy": (64, 60, 88), "gold": (180, 142, 74),
    "cladding": (190, 178, 146), "joint": (160, 150, 124), "glass_band": (70, 120, 128), "bronze": (120, 96, 64),
    "horn_floor": (184, 174, 148), "steel": (150, 152, 150), "copper": (176, 112, 70), "brass": (150, 120, 78),
    "tube_dark": (44, 46, 48), "cape": (214, 212, 206), "skin": (196, 156, 128),
    "golden_grass": (164, 150, 92), "peach": (222, 170, 138), "coral": (210, 120, 104), "violet": (122, 92, 142),
}


def lin(c):
    """sRGB 0-255 -> linear 0-1."""
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


# Roblox roles for exported parts: role -> (Roblox material, palette key, metal, rough, shader kind)
ROLES = {
    "HornSail": ("Plaster", "sail", 0.0, 0.8, "paint"),
    "HornInner": ("Plaster", "inner", 0.0, 0.85, "paint"),
    "HornGold": ("Metal", "gold", 0.7, 0.45, "metal"),
    "HornFloor": ("Limestone", "horn_floor", 0.0, 0.85, "paint"),
    "Cladding": ("Limestone", "cladding", 0.0, 0.85, "paint"),
    "GlassBand": ("Glass", "glass_band", 0.0, 0.2, "glass"),
    "Bronze": ("Metal", "bronze", 0.6, 0.5, "metal"),
    "Steel": ("Metal", "steel", 0.8, 0.45, "metal"),
    "Copper": ("Metal", "copper", 0.8, 0.35, "metal"),
    "Brass": ("Metal", "brass", 0.8, 0.4, "metal"),
    "TubeDark": ("Metal", "tube_dark", 0.5, 0.6, "metal"),
    "BedFlowers": ("LeafyGrass", "yellow", 0.0, 0.9, "paint"),
    "BedFoliage": ("LeafyGrass", "bed_foliage", 0.0, 0.9, "paint"),
    "Petals": ("SmoothPlastic", "yellow", 0.0, 0.8, "paint"),
    "Bark": ("Wood", "beech_bark", 0.0, 0.9, "paint"),
    "Leaves": ("LeafyGrass", "broadleaf", 0.0, 0.9, "paint"),
    "Needles": ("LeafyGrass", "needles", 0.0, 0.9, "paint"),
    "Bush": ("LeafyGrass", "gorse_body", 0.0, 0.9, "paint"),
    "Heather": ("LeafyGrass", "heather", 0.0, 0.9, "paint"),
    "Limestone": ("Limestone", "limestone", 0.0, 0.85, "paint"),
    "DarkRock": ("Rock", "dark_rock", 0.0, 0.9, "paint"),
    "Hedge": ("LeafyGrass", "holly", 0.0, 0.9, "paint"),
    "Berries": ("SmoothPlastic", "berry", 0.0, 0.6, "paint"),
    "Grass": ("Grass", "golden_grass", 0.0, 0.95, "paint"),
    "Cape": ("Fabric", "cape", 0.0, 0.9, "paint"),
    "Skin": ("SmoothPlastic", "skin", 0.0, 0.8, "paint"),
}


# ================================================================================================ small maths
def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, np.float64) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def angd(th, c):
    return np.abs((np.asarray(th) - c + 180.0) % 360.0 - 180.0)


def window(th, c, half, fe):
    return 1.0 - sstep(half - fe, half + fe, angd(th, c))


def P2(bearing, r):
    a = math.radians(bearing)
    return Vector((r * math.sin(a), r * math.cos(a), 0.0))


def P3(bearing, r, z):
    v = P2(bearing, r)
    v.z = z
    return v


def to_roblox(v):
    return [round(float(v[0]), 3), round(float(v[2]), 3), round(float(-v[1]), 3)]


class Noise:
    """2-D gradient noise (numpy, vectorised), roughly in [-1, 1]."""

    def __init__(self, seed, period=256):
        rng = np.random.default_rng(seed)
        self.perm = np.concatenate([rng.permutation(256)] * 2).astype(np.int64)
        ang = rng.random(256) * TAU
        self.gx = np.cos(ang)
        self.gy = np.sin(ang)
        self.px = period - 1          # x period in lattice units (a power of two): seamless angular noise

    def __call__(self, x, y):
        x = np.asarray(x, np.float64)
        y = np.asarray(y, np.float64)
        xi = np.floor(x)
        yi = np.floor(y)
        xf = x - xi
        yf = y - yi
        xi = xi.astype(np.int64)
        yi = yi.astype(np.int64) & 255
        xa = xi & self.px
        xb = (xi + 1) & self.px
        p = self.perm

        def g(ix, iy, dx, dy):
            h = p[p[ix] + iy] & 255
            return self.gx[h] * dx + self.gy[h] * dy

        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        n00 = g(xa, yi, xf, yf)
        n10 = g(xb, yi, xf - 1, yf)
        n01 = g(xa, yi + 1, xf, yf - 1)
        n11 = g(xb, yi + 1, xf - 1, yf - 1)
        a = n00 + u * (n10 - n00)
        b = n01 + u * (n11 - n01)
        return (a + v * (b - a)) * 1.414

    def fbm(self, x, y, octaves=4, lac=2.0, gain=0.5):
        s = 0.0
        amp = 1.0
        norm = 0.0
        f = 1.0
        for o in range(octaves):
            s = s + amp * self(x * f + o * 16.0 * (self.px == 255) + o * 4, y * f - o * 9.73)
            norm += amp
            amp *= gain
            f *= lac
        return s / norm

    def ridged(self, x, y, octaves=4, lac=2.0, gain=0.5):
        s = 0.0
        amp = 1.0
        norm = 0.0
        f = 1.0
        for o in range(octaves):
            n = 1.0 - np.abs(self(x * f + o * 31.7, y * f + o * 7.1))
            s = s + amp * n * n
            norm += amp
            amp *= gain
            f *= lac
        return s / norm


def hash01(*ints, salt=0):
    """Deterministic 0..1 hash of integer arrays."""
    x = np.uint64(salt * 7919 + 104729)
    for a in ints:
        a = np.asarray(a).astype(np.uint64)
        x = (x ^ a) * np.uint64(0x9E3779B97F4A7C15)
        x ^= x >> np.uint64(29)
    x = x * np.uint64(0xBF58476D1CE4E5B9)
    x ^= x >> np.uint64(32)
    return (x & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


# ================================================================================================ PNG writer
def png_write(path, arr):
    """(h,w) uint8/uint16 grey, or (h,w,3|4) uint8."""
    a = np.ascontiguousarray(arr)
    h, w = a.shape[:2]
    if a.ndim == 2:
        ct = 0
    else:
        ct = {3: 2, 4: 6}[a.shape[2]]
    if a.dtype == np.uint16:
        bd = 16
        rows = a.astype(">u2").reshape(h, -1).view(np.uint8).reshape(h, -1)
    else:
        bd = 8
        rows = a.astype(np.uint8).reshape(h, -1)
    raw = np.zeros((h, rows.shape[1] + 1), np.uint8)
    raw[:, 1:] = rows

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, bd, ct, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw.tobytes(), 6)))
        f.write(chunk(b"IEND", b""))


# ================================================================================================ LAYOUT
# Brief 1.3-1.5. Everything not marked C in the brief is our invention ("I"); positions are bearings/radii.
MOUTHS = (60.0, 180.0, 300.0)
STAR_POINTS = (0.0, 120.0, 240.0)
SPOKE_COLOURS = ("yellow", "red", "pink", "lavender", "magenta")
ALT = {"yellow": (216, 198, 104), "red": (194, 98, 92), "pink": (214, 168, 178), "lavender": (160, 162, 204),
       "magenta": (178, 112, 150), "periwinkle": (218, 216, 204), "marigold": (222, 176, 84),
       "crimson": (170, 62, 92), "violet": (150, 120, 168)}
# the stony wildflower stream: NW spring at the wood's edge -> the lake (bearing, r)
STREAM = [(306, 790), (296, 650), (284, 530), (266, 440), (246, 400), (226, 425), (208, 520), (196, 650),
          (188, 760), (184, 840)]
LAKE = dict(bearing=180.0, r=925.0, ax=330.0, ay=128.0)   # ellipse semi-axes: east-west, north-south
KNOLLS = [(32, 440, 12, 70), (98, 520, 15, 85), (142, 400, 9, 60), (322, 430, 10, 65), (272, 600, 11, 70),
          (122, 640, 10, 70), (64, 330, 6, 55)]
RAVINES = [[(346, 1480), (342, 1180), (336, 960), (330, 780)], [(24, 1500), (28, 1240), (36, 1000), (44, 800)]]
TRAILS = [[(300, 200), (300, 330), (292, 520), (300, 700), (318, 820), (330, 860)],      # to the spiral
          [(60, 200), (60, 330), (58, 600), (60, 860), (60, 960)],                        # to the sun glade
          [(180, 200), (180, 330), (176, 560), (174, 760)]]                               # to the lake shore
# summits of the massif outside the Boundary (bearing, height, angular half-width): behind the volcano (180) the
# range stays low so the peak keeps its sky silhouette from the horn; 108 is the big mass behind the owner-frame view
MASSIF = [(108, 1060, 16), (132, 860, 7), (152, 760, 9), (206, 700, 8), (228, 960, 7), (248, 820, 8),
          (266, 900, 10), (300, 920, 10), (322, 840, 7), (340, 960, 9), (18, 990, 11), (42, 860, 7),
          (58, 920, 9), (82, 880, 8)]
SPIRAL = (330.0, 900.0)
# the heart: dome profile, beds, lone trees (ring r 150: see the docstring for why not the brief's r 120)
DOME_R = [0, 50, 150, 200, 260]
DOME_Y = [46, 46, 44.3, 43.6, 43.2]
BED_POSITIONS = [7.5 + 15.0 * k for k in range(24)]
SPOKE_BEARINGS = [b for b in BED_POSITIONS if min(angd(b, m) for m in (60.0, 180.0, 300.0)) > 10.0]
SPOKE_OUT = 140.0
TEAR_R = {"periwinkle": 60.0, "marigold": 56.0}
TEAR_DB = 11.0
LONE_TREE_R = 300.0
SUN_GLADE = (60.0, 1000.0)
HOLLOW = (0.0, 1600.0)
PEAK = (180.0, 1550.0)
PEAK_H = 345.0                 # the peak mesh's height above its (buried) base; summit ~y 640 (brief 1.3)
BERMS = [(20, 360, "violet"), (110, 320, "violet"), (156, 470, "violet"), (236, 300, "violet"),
         (342, 300, "violet"), (76, 610, "violet"), (204, 380, "violet"), (282, 360, "violet")]


def stream_xy():
    return np.array([[r * math.sin(math.radians(b)), r * math.cos(math.radians(b))] for b, r in STREAM])


def polyline_dist(X, Y, pts):
    """distance from (X,Y) to a polyline, and arc parameter (studs from the first point)."""
    best = np.full(X.shape, 1e18)
    tpar = np.zeros(X.shape)
    acc = 0.0
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        L = math.sqrt(L2)
        t = np.clip(((X - ax) * dx + (Y - ay) * dy) / L2, 0.0, 1.0)
        d = np.hypot(X - (ax + t * dx), Y - (ay + t * dy))
        m = d < best
        best = np.where(m, d, best)
        tpar = np.where(m, acc + t * L, tpar)
        acc += L
    return best, tpar, acc


def smooth_path(pts, step=6.0):
    """Catmull-Rom resample of a polyline (x,y) at ~step studs."""
    P = np.asarray(pts, np.float64)
    P = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return np.array(out)


# ================================================================================================ STAGE: data
def compute_field():
    """Heights (Roblox y) and every mask, on the 4-stud grid; row 0 = north, column 0 = west."""
    log("field: start")
    nz = Noise(SEED)
    nz2 = Noise(SEED + 1)
    nz3 = Noise(SEED + 2)
    c = -HALF + SPP * (np.arange(NF) + 0.5)
    X = np.broadcast_to(c[None, :], (NF, NF)).astype(np.float64).copy()
    Y = np.broadcast_to(-c[:, None], (NF, NF)).astype(np.float64).copy()
    R = np.hypot(X, Y)
    TH = np.degrees(np.arctan2(X, Y)) % 360.0
    rad = np.radians(TH)
    nang = nz.fbm(np.cos(rad) * 2.3 + 5.0, np.sin(rad) * 2.3 - 3.0, 3)        # seamless angular noise
    nang2 = nz2.fbm(np.cos(rad) * 4.1 - 2.0, np.sin(rad) * 4.1 + 6.0, 3)

    # --- angular region weights (N wood 300-60, E ridge 60-120, S mountain 120-240, W ridge 240-300)
    wN = window(TH, 0, 60, 18)
    wE = window(TH, 90, 30, 18)
    wS = window(TH, 180, 60, 18)
    wW = window(TH, 270, 30, 18)
    ws = wN + wE + wS + wW + 1e-9
    wN, wE, wS, wW = wN / ws, wE / ws, wS / ws, wW / ws

    # --- valley floor: radial profiles per sector (brief 1.3), identical inside the protected disc
    PN = ([0, 50, 150, 200, 330, 600, 900, 1200, 1450, 1640, 1760, 2000],
          [46, 46, 44.3, 43.6, 48, 60, 104, 160, 214, 238, 240, 240])
    PE = ([0, 50, 150, 200, 420, 700, 1000, 1200, 1500, 2000], [46, 46, 44.3, 43.6, 47, 53, 66, 80, 95, 110])
    PS = ([0, 50, 150, 200, 420, 600, 760, 820, 1040, 1120, 1400, 2000],
          [46, 46, 44.3, 43.4, 40.5, 38.5, 36.4, 35.6, 35.6, 40, 60, 70])
    PW = ([0, 50, 150, 200, 420, 700, 1000, 1200, 1500, 2000], [46, 46, 44.3, 43.6, 48, 54, 68, 82, 96, 110])
    floor = (wN * np.interp(R, *PN) + wE * np.interp(R, *PE) + wS * np.interp(R, *PS) + wW * np.interp(R, *PW))

    prot = sstep(200.0, 255.0, R)              # protected disc (brief build note, moved out with the ring): r 200-255
    folds = (7.5 * nz.fbm(X / 330.0, Y / 330.0, 4) + 3.2 * nz2.fbm(X / 115.0 + 7.3, Y / 115.0 - 2.1, 3)) * prot
    hills = 22.0 * nz3.fbm(X / 430.0 + 3.0, Y / 430.0 + 9.0, 4) * sstep(520, 900, R)
    H = floor + folds + hills
    for b, r, hgt, rad_k in KNOLLS:
        p = P2(b, r)
        H += hgt * np.exp(-((X - p.x) ** 2 + (Y - p.y) ** 2) / (rad_k * rad_k))

    # --- the almond (the book's eye): lens N-S, tips r 1,750 (N) and 1,700 (S), widest r 1,150 (E, W)
    Ln, Wl = 1750.0, 1150.0
    rho = (Ln * Ln + Wl * Wl) / (2 * Wl)
    cc = rho - Wl
    Yl = np.where(Y < 0, Y * (Ln / 1700.0), Y)
    s = np.maximum(np.hypot(X - cc, Yl) - rho, np.hypot(X + cc, Yl) - rho)
    s = s + 55.0 * nz2.fbm(X / 620.0 + 11.0, Y / 620.0 - 5.0, 3)

    # --- spurs and gullies running downslope: seamless noise in (bearing, radius)
    npol = Noise(SEED + 5, period=16)
    npol8 = Noise(SEED + 6, period=8)
    ang_u = TH / 360.0 * 16.0
    ang_8 = TH / 360.0 * 8.0
    spur = 0.6 * npol8.fbm(ang_8, R / 520.0, 2) + 0.4 * npol.fbm(ang_u, R / 420.0, 3)
    spur2 = npol.fbm(ang_u * 2.0 + 3.0, R / 260.0 + 7.0, 2)
    s = s + 120.0 * npol8.fbm(ang_8 + 2.0, 0.37, 2) * sstep(-200.0, 100.0, s)

    def knee(x, k=0.62, lo=0.38):
        """gentle lower slope (lo of the rise over k of the width), then a steep crag band to the crest."""
        x = np.clip(x, 0.0, 1.0)
        return np.where(x < k, lo * (x / k) ** 1.15,
                        lo + (1.0 - lo) * (np.clip(x - k, 0.0, None) / (1.0 - k)) ** 1.25)

    # --- the lids: east and west limestone ridges (feet 70-90 at the almond's edge, crests 320-420 near r 1,700)
    t = s / 570.0
    kk = np.clip(0.76 + 0.08 * nang2, 0.66, 0.86)
    prof = np.where(t < 1.0, knee(t, kk, 0.56), 1.0 + 0.1 * sstep(1.0, 1.6, t))   # the crest runs on into the wall
    amp = (285.0 + 60.0 * nang + 45.0 * window(TH, 75, 8, 6) + 40.0 * window(TH, 285, 8, 6)) \
        * (1.0 - 0.45 * window(TH, 0, 14, 10))
    U = (amp * prof * (t > 0) + (50.0 * spur + 16.0 * spur2) * sstep(0.05, 0.6, t)
         + 32.0 * nz2.ridged(X / 180.0 + 5.0, Y / 180.0, 3) * sstep(0.85, 1.05, t))

    # --- the South Mountain: from ~60 at its foot to ~470 under the peak mesh (which tops out at y 640)
    de = np.hypot(X / 1050.0, (Y + 1640.0) / 760.0)
    msh = np.clip(1.0 - de, 0.0, 1.0)
    M = 410.0 * knee(msh, 0.5, 0.34) + (55.0 * spur + 30.0 * spur2) * sstep(0.05, 0.4, msh) \
        + 40.0 * nz2.ridged(X / 240.0, Y / 240.0, 3) * sstep(0.3, 0.8, msh)
    up = np.maximum(U, M) + 0.25 * np.minimum(U, M) * sstep(0.0, 1.0, np.minimum(U, M) / 120.0)
    H = H + up

    # --- crag bands: tilted strata (bedding planes dip ~8 deg to the south-east), patchy, only on steep high ground
    gy0, gx0 = np.gradient(H, SPP)
    sl0 = np.hypot(gx0, gy0)
    crag = 0.5 * sstep(0.45, 0.75, sl0) * sstep(110.0, 160.0, H) \
        * sstep(-0.1, 0.35, nz3.fbm(X / 260.0, Y / 260.0, 2))
    per = 58.0
    strat = H + 0.12 * X - 0.08 * Y
    tt = strat / per
    fl = np.floor(tt)
    terr = per * (fl + sstep(0.6, 1.0, tt - fl)) - 0.12 * X + 0.08 * Y
    H = H + crag * (terr - H)

    # --- North Wood: ravines 20-40 deep, clearings for the spiral and the flower-sun glade, the hedge hollow
    for rv in RAVINES:
        pts = np.array([[r * math.sin(math.radians(b)), r * math.cos(math.radians(b))] for b, r in rv])
        d, tp, L = polyline_dist(X, Y, smooth_path(pts, 10.0))
        depth = 21.0 * sstep(0.0, 0.25, tp / L) * (1.0 - sstep(0.8, 1.0, tp / L))
        H -= depth * (0.5 + 0.5 * np.cos(np.pi * np.clip(d / 66.0, 0.0, 1.0)))
    for (b, r), rr in ((SPIRAL, 62.0), (SUN_GLADE, 46.0)):
        p = P2(b, r)
        d = np.hypot(X - p.x, Y - p.y)
        i0 = int((p.x + HALF) / SPP)
        j0 = int((HALF - p.y) / SPP)
        hc = float(H[j0, i0])
        w = 1.0 - sstep(rr * 0.7, rr * 1.35, d)
        H = H + w * (hc - H)
    ph = P2(*HOLLOW)
    dh = np.hypot(X - ph.x, (Y - ph.y) * 1.25)

    # --- the wall (ArenaV3 2: 18-stud sheer step, +60 at ~75 deg, +120 at ~54 deg) and the massif to r 2,750
    edge_sec = window(TH, 0, 21, 7)
    rw = WALL_R + 45.0 * nang2 + 40.0 * npol.fbm(ang_u * 3.0 + 1.0, 5.0, 2)
    dw = R - rw
    wall = (18.0 * sstep(0.0, 3.0, dw) + 60.0 * sstep(3.0, 19.0, dw) + 120.0 * sstep(19.0, 106.0, dw))
    H += wall * (1.0 - edge_sec)
    # the massif beyond the Boundary: named summits and saddles (a range, not a crater rim), spurs downslope
    T = np.full(H.shape, 640.0)
    for b_, hgt, w_ in MASSIF:
        T = np.maximum(T, 640.0 + (hgt - 640.0) * np.exp(-(angd(TH, b_) / w_) ** 2))
    T = T + 60.0 * nang2 + 70.0 * npol8.fbm(ang_8 * 2.0 + 5.0, 1.3, 2)
    rc_ = 2290.0 + 110.0 * npol.fbm(ang_u * 1.2 + 9.0, 3.0, 2)            # the crest line wanders
    dr = R - rc_
    across = np.where(dr < 0, np.clip(1.0 + dr / 380.0, 0.0, 1.0) ** 1.35, np.clip(1.0 - dr / 470.0, 0.0, 1.0) ** 1.2)
    rid = nz.ridged(X / 260.0 + 3.0, Y / 260.0 - 8.0, 4)                  # spurs, cols and gullies
    mt = (T * across ** 0.9) * (0.62 + 0.5 * rid) + 40.0 * spur * across
    H = np.maximum(H, mt * sstep(1880.0, 1960.0, R))
    H = H + sstep(2560.0, 2760.0, R) * (120.0 + 30.0 * nz3(X / 200.0, Y / 200.0) - H)
    H = np.where(H > 900.0, 900.0 + 100.0 * np.tanh((H - 900.0) / 100.0), H)     # crests 700-1,000

    # --- the Edge: flat dry ground ~240 to r 1,750, a 107-stud cliff, the canyon (floor ~133) outside the Boundary
    re = 1752.0 + 6.0 * nang2
    canyon = 133.0 + 4.0 * nz2.fbm(X / 80.0, Y / 80.0, 2) + np.clip(R - 1950.0, 0.0, None) * 2.4
    cut = np.where(R > re, np.clip(H - canyon, 0.0, None), 0.0)
    H = H - window(TH, 0, 24, 8) * cut
    plateau = window(TH, 0, 20, 8) * sstep(1625.0, 1660.0, R) * (R <= re)
    H = H + plateau * (240.0 + 1.5 * nz(X / 60.0, Y / 60.0) - H)
    # the hedge hollow (r 1,600): a grassy bowl ringed by rocky slopes
    H -= 19.0 * np.exp(-(dh / 100.0) ** 2)
    H += 9.0 * np.exp(-((dh - 150.0) / 30.0) ** 2) * window(TH, 0, 25, 8) * (R <= re)

    # --- trails (bare earth, lightly eased) -- before the water so banks stay crisp
    trail_d = np.full(X.shape, 1e9)
    for tr in TRAILS:
        pts = np.array([[r * math.sin(math.radians(b)), r * math.cos(math.radians(b))] for b, r in tr])
        d, _, _ = polyline_dist(X, Y, smooth_path(pts, 8.0))
        trail_d = np.minimum(trail_d, d)

    # --- the lake: turquoise mountain lake, level 34, up to 14 deep, rocky grass shores
    pl = P2(LAKE["bearing"], LAKE["r"])
    lx, ly = (X - pl.x) / LAKE["ax"], (Y - pl.y) / LAKE["ay"]
    lphi = np.arctan2(ly, lx)
    q = np.hypot(lx, ly) / (1.0 + 0.10 * nz(np.cos(lphi) * 1.7 + 4.0, np.sin(lphi) * 1.7 - 1.0)
                            + 0.05 * nz2(np.cos(lphi) * 4.0, np.sin(lphi) * 4.0))
    bed = LAKE_Y - 14.0 * np.clip(1.0 - q * q, 0.0, 1.0) ** 0.7 - 0.6
    shore = LAKE_Y + 0.7 + 3.0 * sstep(1.0, 1.35, q)
    H = np.where(q < 1.0, np.minimum(H, bed), np.where(q < 1.35, np.minimum(H, shore + (H - shore)
                                                                            * sstep(1.0, 1.35, q)), H))

    # --- the stony wildflower stream in its dip (6-12 deep), from the wood's edge (y ~60) to the lake (34)
    sp = smooth_path(stream_xy(), 4.0)
    seg = np.diff(sp, axis=0)
    sL = np.concatenate([[0.0], np.cumsum(np.hypot(seg[:, 0], seg[:, 1]))])
    nrm = np.stack([-np.gradient(sp[:, 1]), np.gradient(sp[:, 0])], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)

    def sample(xy):
        i = np.clip(((xy[:, 0] + HALF) / SPP - 0.5).round().astype(int), 0, NF - 1)
        j = np.clip(((HALF - xy[:, 1]) / SPP - 0.5).round().astype(int), 0, NF - 1)
        return H[j, i]

    side = 0.5 * (sample(sp + nrm * 55.0) + sample(sp - nrm * 55.0))
    depth = 8.5 + 3.0 * np.sin(sL / 140.0)
    F = side - depth
    F[0:15] = np.minimum(F[0:15], 61.0)
    F = np.minimum.accumulate(F)                 # always downhill toward the lake
    F = np.maximum(F, LAKE_Y + 0.5 * (1 - sL / sL[-1]))
    # riffles: pools ~45 studs long, stepping down
    W = F - 0.35
    pool = (sL // 45.0).astype(int)
    Wst = np.array([W[pool == k].min() for k in pool])
    Wst = np.minimum.accumulate(Wst)
    Wst = np.maximum(Wst, LAKE_Y)
    d, tpar, Ltot = polyline_dist(X, Y, sp)
    Fg = np.interp(tpar, sL, F)
    Wg = np.interp(tpar, sL, Wst)
    hw = 44.0 + 12.0 * nz3(X / 160.0, Y / 160.0)
    cw = 4.6
    start = sstep(0.0, 70.0, tpar)
    chan = Wg - 1.25 + 0.9 * (d / cw) ** 2
    prof = Fg + (H - Fg) * (0.5 - 0.5 * np.cos(np.pi * np.clip((d - cw) / (hw - cw), 0.0, 1.0))) ** 0.6
    tgt = np.where(d < cw, chan, prof)
    H = np.where(d < hw, H - start * np.clip(H - tgt, 0.0, None), H)

    # --- the heart: exact dome inside the protected disc (flat 46 to r 50, the ring at r 150 ~1.7 lower)
    dome = np.interp(R, DOME_R, DOME_Y)
    H = np.where(R < 200.0, dome, H)

    # ============================================================================================ masks
    gy, gx = np.gradient(H, SPP)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    lake = q < 1.0
    water_lv = np.zeros_like(H)
    water_lv[lake] = LAKE_Y
    inchan = (d < cw + 0.5) & (Wg > H) & (start > 0.5)
    water_lv = np.where(inchan & ~lake, Wg, water_lv)
    water = (water_lv > H + 0.05)

    north_core = window(TH, 0, 55, 14)
    # forest densities
    fz = nz.fbm(X / 140.0 + 2.0, Y / 140.0 + 5.0, 3)
    clear = sstep(0.35, 0.55, nz2.fbm(X / 210.0 - 3.0, Y / 210.0 + 1.0, 3))     # natural clearings
    fe = 110.0 * nz3.fbm(X / 330.0 + 21.0, Y / 330.0 - 4.0, 3)                   # a ragged forest edge
    con = north_core * sstep(610.0 + fe, 720.0 + fe, R) * (1.0 - sstep(1560.0, 1640.0, R)) * (0.92 - 0.75 * clear)
    ridge_foot = sstep(0.0, 40.0, s) * (1.0 - sstep(180.0, 260.0, H - floor))
    con = np.maximum(con, 0.78 * ridge_foot * (1.0 - wS * 0.6) * sstep(-0.3, 0.2, fz) * (1.0 - clear * 0.5))
    con = np.maximum(con, 0.4 * sstep(1880.0, 1960.0, R) * (H < 520) * sstep(-0.1, 0.3, fz))
    con *= (slope < 40.0) * (1.0 - lake) * (1.0 - sstep(0.0, 1.0, (60.0 - d) / 20.0))
    for (b, r), rr in ((SPIRAL, 70.0), (SUN_GLADE, 52.0), (HOLLOW, 175.0)):
        p = P2(b, r)
        con *= sstep(rr * 0.85, rr * 1.15, np.hypot(X - p.x, Y - p.y))
    con *= sstep(4.0, 12.0, trail_d)
    hollow_w = np.exp(-((H - (floor + folds)) / 6.0) ** 2)
    concav = nz3.fbm(X / 90.0 + 13.0, Y / 90.0 - 7.0, 3)
    bro = north_core * sstep(540.0 + fe, 620.0 + fe, R) * (1.0 - sstep(740.0 + fe, 840.0 + fe, R)) * 0.7
    bro = np.maximum(bro, sstep(0.28, 0.42, concav) * sstep(230.0, 300.0, R) * (1.0 - sstep(1000.0, 1250.0, R))
                     * (1.0 - north_core * sstep(700, 760, R)) * 0.75)
    bro *= (slope < 30.0) * (1.0 - lake) * sstep(60.0, 90.0, d) * sstep(4.0, 12.0, trail_d)
    gor = (sstep(0.15, 0.4, nz2.fbm(X / 70.0 + 8.0, Y / 70.0, 3)) * 0.55
           * (sstep(420.0, 560.0, R) * (1.0 - sstep(1100.0, 1300.0, R)) + 0.6 * ridge_foot))
    gor *= (slope < 32.0) * (1.0 - lake) * (1.0 - con * 0.8) * sstep(40.0, 70.0, d) * sstep(5.0, 10.0, trail_d)
    gor *= sstep(200.0, 260.0, R)
    hea = (sstep(150.0, 230.0, H) * (1.0 - sstep(480.0, 600.0, H)) * sstep(14.0, 24.0, slope) * 0.9
           + 0.5 * np.exp(-((dh - 150.0) / 45.0) ** 2) * window(TH, 0, 30, 10))
    hea *= sstep(-0.25, 0.25, nz3.fbm(X / 85.0, Y / 85.0, 3)) * (1.0 - con)
    bou = (0.03 * sstep(250.0, 400.0, R) + 0.35 * sstep(26.0, 34.0, slope) * (1.0 - sstep(50.0, 58.0, slope))
           + 0.4 * np.exp(-((q - 1.15) / 0.12) ** 2))
    bou *= (1.0 - lake) * sstep(5.0, 9.0, d) * (R > 190) * (H < 650)
    tg = (np.maximum.reduce([1.0 - sstep(55.0, 75.0, np.hypot(X - P2(*SPIRAL).x, Y - P2(*SPIRAL).y)),
                             north_core * clear * sstep(700.0, 800.0, R) * (1.0 - sstep(1500, 1600, R)) * 0.8]))
    wf = (np.clip(1.0 - np.abs(d - 14.0) / 22.0, 0.0, 1.0) * start * (d < hw) * 0.9
          + 0.05 * sstep(220.0, 300.0, R) * (1.0 - sstep(650.0, 760.0, R)))
    wf *= (1.0 - lake)
    crg = sstep(42.0, 52.0, slope) * (H > 150.0) * (R < 2600.0)

    # terrain material slots (brief 1.11) -- soft weights for rendering, argmax for the export
    dry = np.clip(sstep(75.0, 150.0, H) * 0.85 + 0.25 * sstep(0.0, 0.5, nz3.fbm(X / 260.0, Y / 260.0, 3))
                  + 0.3 * sstep(14.0, 24.0, slope), 0.0, 1.0) * sstep(150.0, 260.0, R)
    wts = {
        "turf": 1.0 - sstep(TURF_R - 6.0, TURF_R + 6.0, R + 3.0 * nz(X / 20.0, Y / 20.0)),
        "meadow": np.ones_like(H),
        "dry": dry,
        "forest": sstep(0.3, 0.6, np.maximum(con, bro * 0.8)),
        "path": 1.0 - sstep(2.5, 4.5, trail_d),
        "limestone": sstep(36.0, 44.0, slope) * (H > 70.0) + 0.6 * np.exp(-((dh - 150.0) / 30.0) ** 2)
        * window(TH, 0, 25, 8),
        "rock": np.maximum(sstep(47.0, 55.0, slope), window(TH, 0, 24, 8) * (R > re + 2) * (R < 2050)),
        "scree": (sstep(-0.05, 0.25, nz2.fbm(X / 120.0 + 4.0, Y / 120.0, 3)) * sstep(150.0, 200.0, H)
                  * (1.0 - sstep(380.0, 430.0, H)) * sstep(18.0, 24.0, slope) * (1.0 - sstep(36.0, 42.0, slope))
                  * sstep(0.05, 0.25, msh)),
        "salt": (d < cw + 1.0) * start,
        "mud": np.maximum(np.clip(1.0 - np.abs(d - cw - 2.5) / 2.5, 0.0, 1.0) * start * (d < hw),
                          np.exp(-((q - 1.03) / 0.05) ** 2)),
    }
    order = ["meadow", "turf", "dry", "forest", "path", "scree", "limestone", "rock", "mud", "salt"]
    slot = np.zeros(H.shape, np.uint8)
    slot_id = {"turf": 1, "meadow": 2, "dry": 3, "forest": 4, "path": 5, "salt": 6, "mud": 7, "limestone": 8,
               "rock": 9, "scree": 10}
    slot[:] = slot_id["meadow"]
    thresh = {"turf": 0.5, "dry": 0.5, "forest": 0.5, "path": 0.5, "scree": 0.5, "limestone": 0.5, "rock": 0.5,
              "mud": 0.5, "salt": 0.5}
    for k in order[1:]:
        slot = np.where(wts[k] >= thresh[k], slot_id[k], slot)
    slot = np.where(lake, slot_id["mud"], slot)
    slot = np.where(lake & (q < 0.85), slot_id["salt"], slot)

    # regions
    iris_edge = 600.0 + 80.0 * nang2
    reg = np.full(H.shape, 2, np.uint8)
    reg = np.where((north_core > 0.5) & (R >= iris_edge), 3, reg)
    reg = np.where((wE > 0.5) & (s > -60.0), 4, reg)
    reg = np.where((wW > 0.5) & (s > -60.0), 7, reg)
    reg = np.where((wS > 0.5) & (R >= iris_edge + 150.0), 5, reg)
    reg = np.where((window(TH, 0, 24, 1) > 0.5) & (R >= 1640.0) & (R <= PLAY_R), 8, reg)
    reg = np.where(R < 190.0, 1, reg)
    reg = np.where(lake, 6, reg)
    reg = np.where((R > PLAY_R) & (R <= BOUNDARY_R), 9, reg)
    reg = np.where(R > BOUNDARY_R, 10, reg)

    masks = {"Conifer": con, "Broadleaf": bro, "Gorse": gor, "Heather": hea, "Boulders": bou, "TallGrass": tg,
             "Wildflowers": wf, "Crags": crg}
    stream = dict(path=sp, sL=sL, F=F, W=Wst, cw=cw)
    log("field: done (min %.1f, max %.1f)" % (H.min(), H.max()))
    return dict(H=H, X=X, Y=Y, R=R, TH=TH, slope=slope, water=water, water_lv=water_lv, slot=slot, reg=reg,
                masks=masks, wts=wts, stream=stream, q=q, trail_d=trail_d, dstream=d, floor=floor, msh=msh, s=s)


def ground_at(F, x, y):
    """bilinear ground height at Blender (x, y)."""
    H = F["H"]
    fi = (x + HALF) / SPP - 0.5
    fj = (HALF - y) / SPP - 0.5
    i0 = int(np.clip(math.floor(fi), 0, NF - 2))
    j0 = int(np.clip(math.floor(fj), 0, NF - 2))
    a = fi - i0
    b = fj - j0
    return float((H[j0, i0] * (1 - a) + H[j0, i0 + 1] * a) * (1 - b) + (H[j0 + 1, i0] * (1 - a)
                                                                         + H[j0 + 1, i0 + 1] * a) * b)


def layout(F):
    """Every placed landmark, in Blender space (pos, yaw degrees about z, asset)."""
    L = []
    L.append(dict(asset="M1_Platform", pos=(0.0, 0.0, PLAZA_Y), yaw=0.0, note="base embedded 1 stud; deck y 52"))
    L.append(dict(asset="M1_Horn", pos=(0.0, 0.0, DECK_Y), yaw=0.0, note="mouths at 60, 180, 300"))
    for k in range(N_PLINTH):
        b = 3.75 + 7.5 * k
        p = P2(b, RING_R)
        g = ground_at(F, p.x, p.y)
        L.append(dict(asset="M1_Plinth", pos=(p.x, p.y, g), yaw=-b, index=k, bearing=b))
        L.append(dict(asset="M1_PlateTubeRim", pos=(p.x, p.y, g), yaw=-b, index=k, bearing=b))
    for k, b in enumerate(SPOKE_BEARINGS):
        L.append(dict(asset="M1_Spoke_%02d" % k, pos=tuple(spoke_anchor(b)) + (0.0,), yaw=-b, bearing=b,
                      colour=SPOKE_COLOURS[k % 5]))
    for m in MOUTHS:
        for kind, db, r in (("M1_TeardropPeriwinkle", -TEAR_DB, TEAR_R["periwinkle"]),
                            ("M1_TeardropMarigold", TEAR_DB, TEAR_R["marigold"])):
            p = P2(m + db, r)
            L.append(dict(asset=kind, pos=(p.x, p.y, 0.0), yaw=-(m + db), bearing=m + db))
        p = P2(m, LONE_TREE_R)
        L.append(dict(asset="M1_LoneTree", pos=(p.x, p.y, 0.0), yaw=float(m * 1.7 % 360), bearing=m))
    p = P2(*SPIRAL)
    L.append(dict(asset="M1_CrimsonSpiral", pos=(p.x, p.y, 0.0), yaw=20.0))
    p = P2(*SUN_GLADE)
    L.append(dict(asset="M1_SunGlade", pos=(p.x, p.y, 0.0), yaw=0.0))
    # the V-shaped holly maze in the hedge hollow (brief 1.5): two arms of 12-stud modules from an apex at the
    # north side of the hollow, opening south toward the wood, plus a short inner baffle on each arm
    ph = P2(*HOLLOW)
    apex = Vector((ph.x, ph.y + 52.0, 0.0))
    for arm in (-1, 1):
        d = Vector((arm * math.sin(math.radians(32.0)), -math.cos(math.radians(32.0)), 0.0))
        yaw = math.degrees(math.atan2(d.y, d.x))
        for i in range(8):
            p = apex + d * (6.0 + 12.0 * i)
            L.append(dict(asset="M1_HollyHedge", pos=(p.x, p.y, 0.0), yaw=yaw))
        for i in range(3):
            p = apex + d * 40.0 - Vector((arm * 11.0, 0.0, 0.0)) + d * (12.0 * i)
            L.append(dict(asset="M1_HollyHedge", pos=(p.x, p.y, 0.0), yaw=yaw))
    for b, r, colour in BERMS:
        p = P2(b, r)
        L.append(dict(asset="M1_Berm", pos=(p.x, p.y, 0.0), yaw=float((b * 3) % 360), bearing=b))
    p = P2(*PEAK)
    L.append(dict(asset="M1_Peak", pos=(p.x, p.y, 0.0), yaw=0.0, note="summit y ~640"))
    for it in L:
        x, y, z = it["pos"]
        if it["asset"] not in ("M1_Platform", "M1_Horn", "M1_Plinth", "M1_PlateTubeRim"):
            z = ground_at(F, x, y)
            if it["asset"] == "M1_Peak":
                gmin = min(ground_at(F, x + dx, y + dy) for dx in (-120, -60, 0, 60, 120) for dy in (-100, 0, 100))
                z = min(640.0 - PEAK_H, gmin - 5.0)
                it["note"] = "summit y %.0f" % (z + PEAK_H)
                log("layout: peak base y %.1f, summit y %.1f" % (z, z + PEAK_H))
            it["pos"] = (x, y, z)
    return L


def spoke_anchor(b):
    """the spoke's centre point on the turf: inner end clear of the platform edge and steps, outer end r 110."""
    r_in = max(platform_edge_r(b) + 7.0, 36.0)
    for m in MOUTHS:
        if angd(b, m) < 20:
            r_in = max(r_in, 36.0)
    r_out = SPOKE_OUT
    rc = 0.5 * (r_in + r_out)
    p = P2(b, rc)
    return (p.x, p.y)


def spoke_len(b):
    r_in = max(platform_edge_r(b) + 7.0, 36.0)
    return SPOKE_OUT - r_in


def platform_edge_r(b):
    """distance from the centre to the triangle's edge (inradius 25) along bearing b."""
    m = min(MOUTHS, key=lambda mm: angd(b, mm))
    return min(50.0, 25.0 / max(math.cos(math.radians(angd(b, m))), 1e-3))


def data_stage():
    F = compute_field()
    H = F["H"]
    os.makedirs(OUT, exist_ok=True)
    png_write(os.path.join(OUT, "Map1_Height.png"), np.clip(np.round(H * HEIGHT_SCALE), 0, 65535).astype(np.uint16))
    png_write(os.path.join(OUT, "Map1_Material.png"), F["slot"])
    png_write(os.path.join(OUT, "Map1_Region.png"), F["reg"])
    png_write(os.path.join(OUT, "Map1_WaterMask.png"), (F["water"] * 255).astype(np.uint8))
    png_write(os.path.join(OUT, "Map1_WaterLevel.png"),
              np.where(F["water"], np.round(F["water_lv"] * HEIGHT_SCALE), 0).astype(np.uint16))
    for k, m in F["masks"].items():
        png_write(os.path.join(OUT, "Map1_Mask_%s.png" % k), np.clip(np.round(m * 255), 0, 255).astype(np.uint8))
    # Shared.BiomeGrid layout: 16-stud cells, 240 x 240 over +-1,920, row 0 = north
    idx = (np.arange(240) * 4 + int((HALF - 1920.0) / SPP) + 2).astype(int)
    grid = F["reg"][np.ix_(idx, idx)]
    with open(os.path.join(OUT, "Map1_BiomeGrid16.json"), "w") as f:
        json.dump(dict(cell=16, n=240, origin=[-1920, -1920], rowOrder="north (Roblox -Z) first",
                       regions=REGIONS, data=grid.astype(int).tolist()), f, separators=(",", ":"))
    L = layout(F)
    meta = terrain_meta(F)
    with open(os.path.join(OUT, "Map1_Terrain.json"), "w") as f:
        json.dump(meta, f, indent=1)
    with open(os.path.join(OUT, "Map1_Layout.json"), "w") as f:
        json.dump(layout_json(L), f, indent=1)
    np.savez_compressed(os.path.join(WORK, "field.npz"), H=H.astype(np.float32), slot=F["slot"], reg=F["reg"],
                        water=F["water"], water_lv=F["water_lv"].astype(np.float32),
                        slope=F["slope"].astype(np.float32), q=F["q"].astype(np.float32),
                        trail_d=F["trail_d"].astype(np.float32), dstream=F["dstream"].astype(np.float32),
                        msh=F["msh"].astype(np.float32),
                        **{"m_" + k: v.astype(np.float32) for k, v in F["masks"].items()},
                        **{"w_" + k: np.asarray(v, np.float32) for k, v in F["wts"].items()},
                        st_path=F["stream"]["path"], st_sL=F["stream"]["sL"], st_W=F["stream"]["W"])
    with open(os.path.join(WORK, "layout.json"), "w") as f:
        json.dump(L, f)
    data_preview(F, L)
    report_field(F)
    return F, L


REGIONS = {1: "Heart", 2: "Iris", 3: "NorthWood", 4: "EastRidge", 5: "SouthMountain", 6: "Lake", 7: "WestRidge",
           8: "Edge", 9: "Crest", 10: "Outside"}
SLOTS = {1: ("Grass", "turf", "Heart turf, r < 150"), 2: ("Grass", "meadow", "Iris meadow"),
         3: ("Grass", "dry", "dry slopes and ridge grass"), 4: ("LeafyGrass", "forest_floor", "forest floor"),
         5: ("Ground", "path", "paths and bare earth"), 6: ("Salt", "pebbles", "stream bed (river-pebble variant)"),
         7: ("Mud", "mud", "lake and stream margins"), 8: ("Limestone", "limestone", "crags, ridges, boulder fields"),
         9: ("Rock", "dark_rock", "cliff faces, canyon, the peak's core"),
         10: ("Basalt", "scree", "tan scree slot (Basalt stays reserved for scree)")}


def terrain_meta(F):
    sp = F["stream"]
    pts = [to_roblox((float(x), float(y), 0.0)) for x, y in sp["path"][::5]]
    lv = [round(float(v), 2) for v in sp["W"][::5]]
    return dict(
        map="Map 1, the green land", generator="art/blender/map1_green_land.py", seed=SEED,
        grid=dict(width=NF, height=NF, studsPerPixel=SPP, origin=[-HALF, -HALF],
                  pixelCentre="Roblox x = -2752 + 4*(col+0.5); Roblox z = -2752 + 4*(row+0.5); row 0 = north",
                  heightEncoding="16-bit: y_studs = value / 32", waterLevelEncoding="16-bit: y = value / 32, 0 = no water"),
        radii=dict(play=PLAY_R, wallFoot=WALL_R, boundary=BOUNDARY_R, terrainTo=2750, turf=TURF_R,
                   protectedDisc=[200, 255], plinthRing=RING_R),
        plaza=dict(knollY=PLAZA_Y, flatTo=50, deckY=DECK_Y, plinths=N_PLINTH, plinthStep=7.5, plinthOffset=3.75,
                   plinthRingY=round(dome_y(RING_R), 3), plateTubeRadius=3.6,
                   bedBearings=SPOKE_BEARINGS, mouths=list(MOUTHS)),
        regions=REGIONS, materialSlots={str(k): dict(base=v[0], tint=list(PAL[v[1]]), note=v[2])
                                        for k, v in SLOTS.items()},
        lake=dict(level=LAKE_Y, centre=to_roblox(P2(LAKE["bearing"], LAKE["r"])), semiAxesStuds=[LAKE["ax"],
                  LAKE["ay"]], maxDepth=14, waterColor=list(PAL["water"])),
        stream=dict(halfWidth=sp["cw"], pointsRoblox=pts, waterLevels=lv,
                    note="water steps down in ~45-stud pools from ~60 to 34; dip 6-12 deep, ~90 wide"),
        trails=[[to_roblox(P2(b, r)) for b, r in tr] for tr in TRAILS],
        edge=dict(lipR=1752, cliffDrop=107, canyonFloorY=133, sector=[-21, 21], note="force field at the lip"),
        palette={k: list(v) for k, v in PAL.items()},
        heights=dict(min=float(F["H"].min()), max=float(F["H"].max())),
    )


def layout_json(L):
    out = []
    for it in L:
        x, y, z = it["pos"]
        e = dict(asset=it["asset"], position=to_roblox((x, y, z)), yawDegrees=round(float(it["yaw"]), 3))
        for k in ("index", "bearing", "colour", "note"):
            if k in it:
                e[k] = it[k]
        out.append(e)
    return dict(space="Roblox (X east, Y up, Z south); yaw about +Y, degrees, applied to the manifest pivot",
                items=out)


def report_field(F):
    H, R, TH, slope = F["H"], F["R"], F["TH"], F["slope"]
    inside = R < PLAY_R
    log("field: slope < 30 deg inside the play disc: %.1f%%" % (100.0 * (slope[inside] < 30).mean()))
    for name, mask in (("ring r148-152", (R > 148) & (R < 152)), ("turf r<180", R < 180),
                       ("north r1600-1700", (R > 1600) & (R < 1700) & (angd(TH, 0) < 10)),
                       ("east crest r1550-1750", (R > 1550) & (R < 1750) & (angd(TH, 90) < 20)),
                       ("west crest r1550-1750", (R > 1550) & (R < 1750) & (angd(TH, 270) < 20)),
                       ("peak zone", (np.hypot(F["X"], F["Y"] + 1550) < 120))):
        v = H[mask]
        log("  %-22s y %.1f .. %.1f (mean %.1f)" % (name, v.min(), v.max(), v.mean()))
    for k, m in F["masks"].items():
        log("  mask %-12s mean %.3f" % (k, float(m[R < PLAY_R].mean())))


def data_preview(F, L):
    """hillshade + material colours, our own data only."""
    H, slot = F["H"], F["slot"]
    gy, gx = np.gradient(H, SPP)
    sun = np.array([-0.5, 0.6, 0.62])
    sun /= np.linalg.norm(sun)
    nrm = np.stack([-gx, gy, np.ones_like(H)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    shade = np.clip(nrm @ sun, 0.0, 1.0) * 0.75 + 0.35
    cols = np.zeros(slot.shape + (3,))
    for k, v in SLOTS.items():
        cols[slot == k] = PAL[v[1]]
    cols[F["water"]] = PAL["water"]
    img = np.clip(cols * shade[..., None], 0, 255)
    rr = F["R"]
    for rad_ in (PLAY_R, BOUNDARY_R, RING_R):
        img[np.abs(rr - rad_) < 2.5] = (250, 250, 250)
    for it in L:
        x, y, _ = it["pos"]
        i = int((x + HALF) / SPP)
        j = int((HALF - y) / SPP)
        img[max(0, j - 2):j + 3, max(0, i - 2):i + 3] = (255, 60, 40)
    png_write(os.path.join(PREV, "data_maps.png"), img.astype(np.uint8)[::2, ::2])
    log("PREVIEW", os.path.join(PREV, "data_maps.png"))


# ================================================================================================ mesh building
class MB:
    """Accumulates polygons with a per-face base colour (sRGB), volume id and paint settings."""

    def __init__(self):
        self.v = []
        self.f = []
        self.base = []
        self.vol = []
        self.paint = []
        self.cur_vol = 0

    def new_vol(self):
        self.cur_vol += 1
        return self.cur_vol

    def add_verts(self, pts):
        i0 = len(self.v)
        self.v.extend([tuple(map(float, p)) for p in pts])
        return list(range(i0, i0 + len(pts)))

    def face(self, idx, col, paint=None):
        self.f.append(tuple(idx))
        self.base.append(tuple(col))
        self.vol.append(self.cur_vol)
        self.paint.append(paint or DEFAULT_PAINT)

    def poly(self, pts, col, paint=None):
        self.face(self.add_verts(pts), col, paint)

    def mesh_part(self, verts, faces, col, paint=None, colfn=None):
        ids = self.add_verts(verts)
        for k, fc in enumerate(faces):
            c = colfn(k, [verts[i] for i in fc]) if colfn else col
            self.face([ids[i] for i in fc], c, paint)

    def tris(self):
        n = 0
        for fc in self.f:
            n += len(fc) - 2
        return n

    def transformed(self, mat):
        o = MB()
        o.v = [tuple(mat @ Vector(p)) for p in self.v]
        o.f, o.base, o.vol, o.paint, o.cur_vol = list(self.f), list(self.base), list(self.vol), list(self.paint), \
            self.cur_vol
        return o

    def extend(self, other):
        off = len(self.v)
        voff = self.cur_vol
        self.v.extend(other.v)
        self.f.extend([tuple(i + off for i in fc) for fc in other.f])
        self.base.extend(other.base)
        self.vol.extend([vv + voff for vv in other.vol])
        self.paint.extend(other.paint)
        self.cur_vol += other.cur_vol + 1


DEFAULT_PAINT = (0.05, 0.03, 0.06, 0.16)     # per-volume, per-facet jitter, lighter on top, darker underneath


def face_colours(mb, salt=0, normals=None):
    """linear per-face colours: base x volume/facet jitter x top/underside value, warm on top, cool under."""
    V = np.asarray(mb.v, np.float64)
    out = np.zeros((len(mb.f), 3))
    base = lin(np.asarray(mb.base, np.float64))
    vol = np.asarray(mb.vol)
    hv = hash01(vol, salt=salt + 3) * 2 - 1
    hf = hash01(np.arange(len(mb.f)), salt=salt + 11) * 2 - 1
    for k, fc in enumerate(mb.f):
        if normals is not None:
            nz_ = float(normals[k][2])
        else:
            p = V[list(fc)]
            n = np.cross(p[1] - p[0], p[2] - p[0])
            if len(fc) > 3:
                n = n + np.cross(p[2] - p[0], p[3] - p[0])
            ln = np.linalg.norm(n)
            nz_ = n[2] / ln if ln > 1e-12 else 0.0
        kv, kf, top, under = mb.paint[k]
        val = (1 + kv * hv[k]) * (1 + kf * hf[k]) * (1 + top * max(nz_, 0.0) - under * max(-nz_, 0.0))
        warm = np.array([1.0 + 0.02 * max(nz_, 0), 1.0, 1.0 - 0.025 * max(nz_, 0)]) * \
            np.array([1.0 - 0.02 * max(-nz_, 0), 1.0, 1.0 + 0.03 * max(-nz_, 0)])
        out[k] = base[k] * (val ** 2.2) * warm
    return np.clip(out, 0.0, 1.0)


def box_uv(me, studs_per_tile=8.0):
    """triangulate, then box-projected UVs, 1 UV unit = 8 studs (ls_common.box_uv's convention), so Roblox materials
    tile the same on every asset and the exporter can write tangents (it needs triangles and UVs)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            co = loop.vert.co
            u, v = ((co.y, co.z), (co.x, co.z), (co.x, co.y))[axis]
            loop[uv].uv = (u / studs_per_tile, v / studs_per_tile)
    bm.to_mesh(me)
    bm.free()
    me.update()


def fix_normals(me):
    """orient every island's faces consistently outward (face order is preserved)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.update()


def to_mesh(name, mb, salt=0, mat_index=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.v, [], mb.f)
    me.update()
    if len(me.polygons) != len(mb.f):
        raise RuntimeError("polygon count changed for %s" % name)
    fix_normals(me)
    nrm = np.empty(len(me.polygons) * 3, np.float32)
    me.polygons.foreach_get("normal", nrm)
    cols = face_colours(mb, salt, normals=nrm.reshape(-1, 3))
    at = me.attributes.new("Col", "FLOAT_COLOR", "FACE")
    rgba = np.ones((len(mb.f), 4), np.float32)
    rgba[:, :3] = cols
    at.data.foreach_set("color", rgba.ravel())
    if mat_index is not None:
        me.polygons.foreach_set("material_index", np.asarray(mat_index, np.int32))
    try:
        me.shade_flat()
    except AttributeError:
        for p in me.polygons:
            p.use_smooth = False
    return me


def hull(points, dissolve_deg=0.0):
    """convex hull -> (verts, faces) with outward faces."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    junk = []
    for g in res.get("geom_interior", []) + res.get("geom_unused", []):
        if isinstance(g, bmesh.types.BMVert) and g.is_valid and all(g is not x for x in junk):
            junk.append(g)
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    if dissolve_deg > 0:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve_deg), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.verts.index_update()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return verts, faces


def box(mb, lo, hi, col, paint=None, skip_bottom=False, mat=None):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    pts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1),
           (x0, y1, z1)]
    if mat is not None:
        pts = [tuple(mat @ Vector(p)) for p in pts]
    ids = mb.add_verts(pts)
    quads = [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    if not skip_bottom:
        quads.append((0, 3, 2, 1))
    for q in quads:
        mb.face([ids[i] for i in q], col, paint)


def prism(mb, z0, z1, r0, r1, sides, col, centre=(0.0, 0.0), rot=0.0, cap_top=True, cap_bottom=False,
          paint=None, rj=0.0, rng=None, tilt=(0.0, 0.0)):
    cx, cy = centre
    ring0, ring1 = [], []
    for i in range(sides):
        a = rot + TAU * i / sides
        j0 = 1 + (rng.uniform(-rj, rj) if rng else 0.0)
        j1 = 1 + (rng.uniform(-rj, rj) if rng else 0.0)
        ring0.append((cx + r0 * j0 * math.cos(a), cy + r0 * j0 * math.sin(a), z0))
        ring1.append((cx + tilt[0] + r1 * j1 * math.cos(a), cy + tilt[1] + r1 * j1 * math.sin(a), z1))
    a0 = mb.add_verts(ring0)
    a1 = mb.add_verts(ring1)
    for i in range(sides):
        j = (i + 1) % sides
        mb.face([a0[i], a0[j], a1[j], a1[i]], col, paint)
    if cap_top:
        mb.face(a1, col, paint)
    if cap_bottom:
        mb.face(a0[::-1], col, paint)


def bipyramid(mb, c, r, h, sides, col, rot=0.0, paint=None):
    ring = [(c[0] + r * math.cos(rot + TAU * i / sides), c[1] + r * math.sin(rot + TAU * i / sides), c[2])
            for i in range(sides)]
    ids = mb.add_verts(ring + [(c[0], c[1], c[2] + h), (c[0], c[1], c[2] - h * 0.5)])
    top, bot = ids[-2], ids[-1]
    for i in range(sides):
        j = (i + 1) % sides
        mb.face([ids[i], ids[j], top], col, paint)
        mb.face([ids[j], ids[i], bot], col, paint)


def blob_points(rng, centre, rx, ry, rz, n, flat_bottom=0.45, p=2.0):
    pts = []
    for _ in range(n):
        u = rng.uniform(-1, 1)
        a = rng.uniform(0, TAU)
        s_ = math.sqrt(max(0.0, 1 - u * u))
        d = Vector((s_ * math.cos(a), s_ * math.sin(a), u))
        k = (abs(d.x) ** p + abs(d.y) ** p + abs(d.z) ** p) ** (-1.0 / p)
        d = d * k * rng.uniform(0.86, 1.0)
        z = d.z * rz
        z = max(z, -rz * flat_bottom)
        pts.append((centre[0] + d.x * rx, centre[1] + d.y * ry, centre[2] + z))
    return pts


def lens_bed(mb, L, W, Hh, colour, alt, rng, shape="lens", heads=True, head_scale=1.0, fleck=None,
             foliage=PAL["bed_foliage"], head_density=2.6, row_len=1.7):
    """long mounded flower bed along +x, centred at the origin; pointed ends (lens) or teardrop (round at -x)."""
    nu = max(10, int(L / row_len))
    nv = 6

    def hw_of(t):           # t in [0,1] along the bed
        if shape == "lens":
            return 0.5 * W * max(0.0, 1.0 - abs(2 * t - 1) ** 1.8) ** 0.75
        if t < 0.32:
            return 0.5 * W * math.sqrt(max(0.0, 1.0 - ((0.32 - t) / 0.32) ** 2))
        return 0.5 * W * max(0.0, (1.0 - (t - 0.32) / 0.68)) ** 1.15

    rows = []
    paint = (0.04, 0.05, 0.05, 0.1)
    for i in range(1, nu):
        t = i / nu
        hw = max(hw_of(t), 0.25)
        ez = (1.0 - abs(2 * t - 1) ** 6) if shape == "lens" else (1.0 - max(0.0, t - 0.6) ** 2 * 2.0)
        row = []
        for j in range(nv + 1):
            v = -1 + 2 * j / nv
            z = Hh * max(0.0, 1 - v * v) ** 0.55 * ez + rng.uniform(-0.08, 0.08) - 0.25
            row.append((-L / 2 + t * L, v * hw, z))
        rows.append(mb.add_verts(row))
    tip0 = mb.add_verts([(-L / 2 - (0.0 if shape == "lens" else 0.3), 0.0, -0.25)])[0]
    tip1 = mb.add_verts([(L / 2, 0.0, -0.25)])[0]

    def colour_for(j0):
        edge = abs((j0 + 0.5) / nv * 2 - 1)
        if edge > 0.72:
            return foliage
        r = rng.random()
        if fleck is not None and r < 0.3:
            return fleck
        return alt if r < 0.22 else colour

    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        for j in range(nv):
            mb.face([a[j], b[j], b[j + 1], a[j + 1]], colour_for(j), paint)
    for j in range(nv):
        mb.face([tip0, rows[0][j], rows[0][j + 1]], colour_for(j), paint)
        mb.face([rows[-1][j], tip1, rows[-1][j + 1]], colour_for(j), paint)
    # skirt to embed the edges
    if heads:
        n = int(L * head_density * (W / 9.0))
        for _ in range(n):
            t = rng.uniform(0.04, 0.96)
            hw = hw_of(t)
            v = rng.uniform(-0.85, 0.85)
            ez = (1.0 - abs(2 * t - 1) ** 6) if shape == "lens" else (1.0 - max(0.0, t - 0.6) ** 2 * 2.0)
            z = Hh * max(0.0, 1 - v * v) ** 0.55 * ez - 0.15
            r = rng.uniform(0.3, 0.6) * head_scale
            c = fleck if (fleck is not None and rng.random() < 0.35) else (alt if rng.random() < 0.35 else colour)
            bipyramid(mb, (-L / 2 + t * L, v * hw, z + 0.1), r, r * 0.28, 5, c, rot=rng.uniform(0, TAU),
                      paint=(0.03, 0.06, 0.08, 0.2))


# ------------------------------------------------------------------------------------------------ the horn
def build_horn():
    rng = random.Random(SEED + 101)
    parts = {"HornSail": MB(), "HornInner": MB(), "HornGold": MB(), "HornFloor": MB()}
    RC, APEX = 21.0, 44.0
    apex = Vector((0.0, 0.0, APEX))
    sail_paint = (0.02, 0.025, 0.05, 0.12)
    # the hollow core: three plum faces (the A-frame mouths), corners at the star points
    for m in MOUTHS:
        a = P2(m - 60.0, RC)
        b = P2(m + 60.0, RC)
        mid = (a + b) * 0.5
        ab = (b - a)
        lab = ab.length
        h = 7.0 / lab
        o1 = a + ab * (0.5 - h)
        o2 = a + ab * (0.5 + h)
        ot = mid + (apex - mid) * (16.0 / APEX)
        nrm = (b - a).cross(apex - a).normalized()
        if nrm.dot(mid) < 0:
            nrm = -nrm
        th = 0.6
        outer = [a, o1, ot, o2, b, apex]
        inner = [p - nrm * th for p in outer]
        io = parts["HornInner"].add_verts(outer)
        ii = parts["HornInner"].add_verts(inner)
        P = parts["HornInner"]
        P.new_vol()
        for tri in ((0, 1, 2), (0, 2, 5), (2, 3, 4), (2, 4, 5)):
            P.face([io[k] for k in tri[::-1]], PAL["inner"], sail_paint)
            P.face([ii[k] for k in tri], PAL["inner_navy"], sail_paint)
        for k0, k1 in ((1, 2), (2, 3), (0, 1), (3, 4), (4, 5), (5, 0)):
            P.face([io[k0], ii[k0], ii[k1], io[k1]], PAL["inner"], sail_paint)
        # gold strips round the opening and up the A-frame edges (0.4 wide, proud 0.12)
        G = parts["HornGold"]
        for p0, p1 in ((o1, ot), (ot, o2), (a + (apex - a) * 0.02, apex), (b + (apex - b) * 0.02, apex)):
            strip(G, p0, p1, nrm, 0.4, 0.12)
        # gold battens fanning inside from quarter-circle plates at the base corners
        for corner, other in ((a, b), (b, a)):
            for f_ in (0.45, 0.7, 0.9):
                tgt = other + (apex - other) * f_
                strip(G, corner - nrm * th + (tgt - corner) * 0.06, corner - nrm * th + (tgt - corner) * 0.92, -nrm,
                      0.3, 0.12)
        # brass threshold at the mouth
        box(G, (-7.2, -0.75, 0.0), (7.2, 0.75, 0.3), PAL["gold"], mat=frame_at(mid - nrm * 0.2, m))
    # floor (a thin slab, so it is closed and faces up)
    fl = [P2(b_, RC - 0.4) for b_ in (0.0, 240.0, 120.0)]
    lo_ = parts["HornFloor"].add_verts([(p.x, p.y, -0.2) for p in fl])
    hi_ = parts["HornFloor"].add_verts([(p.x, p.y, 0.06) for p in fl])
    parts["HornFloor"].face(hi_, PAL["horn_floor"])
    parts["HornFloor"].face(lo_[::-1], PAL["horn_floor"])
    for i in range(3):
        j = (i + 1) % 3
        parts["HornFloor"].face([lo_[i], lo_[j], hi_[j], hi_[i]], PAL["horn_floor"])
    # sails: three tall inner sails and three flared outer sails, one pair at each star point
    for p in STAR_POINTS:
        tang = P2(p + 90.0, 1.0)
        rad = P2(p, 1.0)
        S = parts["HornSail"]
        # inner sail: pleated fan from a convex base (r ~22-25) to an apex at r 6, z 50
        base = []
        nseg = 8
        for i in range(nseg + 1):
            s_ = -1 + 2 * i / nseg
            rr = 21.0 + 3.6 * (1 - s_ * s_) + (1.1 if i % 2 else -0.3)
            base.append(rad * rr + tang * (16.0 * s_))
        top = rad * 6.0 + Vector((0, 0, 50.0))
        fan(S, base, [top], 0.5, PAL["sail"], sail_paint)
        # outer sail: tent skirt, base r ~27-29 flaring, a pulled-in mid row, apex r 14, z 36
        base = []
        mid = []
        nseg = 10
        apex_o = rad * 14.0 + Vector((0, 0, 36.0))
        for i in range(nseg + 1):
            s_ = -1 + 2 * i / nseg
            rr = 25.4 + 2.6 * (1 - s_ * s_) + (0.9 if i % 2 else -0.2) + 1.4 * s_ ** 4
            bp = rad * rr + tang * (13.0 * s_)
            base.append(bp)
            mp = bp + (apex_o - bp) * 0.36
            mp = mp - rad * (2.6 * (1 - 0.5 * abs(s_))) - tang * (1.6 * s_)
            mid.append(mp)
        fan(S, base, mid + [apex_o], 0.45, PAL["sail"], sail_paint, rows=True)
        G = parts["HornGold"]
        strip(G, base[0] + Vector((0, 0, 0.1)), mid[0], -tang, 0.35, 0.1)
        strip(G, mid[0], apex_o, -tang, 0.35, 0.1)
        strip(G, base[-1] + Vector((0, 0, 0.1)), mid[-1], tang, 0.35, 0.1)
        strip(G, mid[-1], apex_o, tang, 0.35, 0.1)
    return parts


def frame_at(pos, bearing):
    """matrix placing local +x along the tangent and +y outward at bearing."""
    rad = P2(bearing, 1.0)
    tang = P2(bearing + 90.0, 1.0)
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0] = tang[i]
        m[i][1] = rad[i]
    m[2][2] = 1.0
    m.translation = Vector(pos)
    return m


def strip(mb, p0, p1, out_n, w, t):
    """a flat bar from p0 to p1, width w, thickness t, standing proud along out_n."""
    p0, p1, out_n = Vector(p0), Vector(p1), Vector(out_n).normalized()
    d = (p1 - p0)
    if d.length < 1e-6:
        return
    side = d.cross(out_n).normalized() * (w / 2)
    o = out_n * t
    pts = [p0 - side, p0 + side, p1 + side, p1 - side]
    pts2 = [p + o for p in pts]
    ids = mb.add_verts(pts + pts2)
    col = PAL["gold"]
    mb.face([ids[4], ids[5], ids[6], ids[7]], col)
    mb.face([ids[0], ids[1], ids[5], ids[4]], col)
    mb.face([ids[2], ids[3], ids[7], ids[6]], col)
    mb.face([ids[1], ids[2], ids[6], ids[5]], col)
    mb.face([ids[3], ids[0], ids[4], ids[7]], col)


def fan(mb, base, upper, thick, col, paint, rows=False):
    """a folded panel: base polyline -> (one apex) or (mid row + apex), solid with thickness."""
    mb.new_vol()
    if not rows:
        apex = upper[0]
        nrm_c = Vector((base[0] + base[-1]) * 0.5 - apex).normalized()
        b_out = mb.add_verts(base)
        a_out = mb.add_verts([apex])[0]
        inward = [(apex - p).normalized() * 0.0 + Vector((-(p.x), -(p.y), 0)).normalized() * thick for p in base]
        b_in = mb.add_verts([p + inward[i] for i, p in enumerate(base)])
        a_in = mb.add_verts([apex - Vector((apex.x, apex.y, 0)).normalized() * thick * 0.2
                             - Vector((0, 0, thick * 1.5))])[0]
        for i in range(len(base) - 1):
            mb.face([b_out[i], b_out[i + 1], a_out], col, paint)
            mb.face([b_in[i + 1], b_in[i], a_in], col, paint)
            mb.face([b_out[i + 1], b_out[i], b_in[i], b_in[i + 1]], col, paint)
        mb.face([b_out[0], a_out, a_in, b_in[0]], col, paint)
        mb.face([b_out[-1], b_in[-1], a_in, a_out], col, paint)
        return
    mid, apex = upper[:-1], upper[-1]
    b_out = mb.add_verts(base)
    m_out = mb.add_verts(mid)
    a_out = mb.add_verts([apex])[0]

    def inw(p, k=1.0):
        return Vector((-p.x, -p.y, 0)).normalized() * thick * k

    b_in = mb.add_verts([p + inw(p) for p in base])
    m_in = mb.add_verts([p + inw(p) for p in mid])
    a_in = mb.add_verts([apex + inw(apex, 0.4) - Vector((0, 0, thick * 1.5))])[0]
    n = len(base)
    for i in range(n - 1):
        mb.face([b_out[i], b_out[i + 1], m_out[i + 1], m_out[i]], col, paint)
        mb.face([m_out[i], m_out[i + 1], a_out], col, paint)
        mb.face([b_in[i + 1], b_in[i], m_in[i], m_in[i + 1]], col, paint)
        mb.face([m_in[i + 1], m_in[i], a_in], col, paint)
        mb.face([b_out[i + 1], b_out[i], b_in[i], b_in[i + 1]], col, paint)
    for k, sgn in ((0, 1), (n - 1, -1)):
        if sgn > 0:
            mb.face([b_out[k], m_out[k], m_in[k], b_in[k]], col, paint)
            mb.face([m_out[k], a_out, a_in, m_in[k]], col, paint)
        else:
            mb.face([b_out[k], b_in[k], m_in[k], m_out[k]], col, paint)
            mb.face([m_out[k], m_in[k], a_in, a_out], col, paint)


# ------------------------------------------------------------------------------------------------ the platform
def build_platform():
    parts = {"Cladding": MB(), "GlassBand": MB(), "Bronze": MB()}
    Cl, Gl, Br = parts["Cladding"], parts["GlassBand"], parts["Bronze"]
    V = [P2(p, 50.0) for p in STAR_POINTS]
    out = []
    for k in range(3):
        vk = V[k]
        vprev = V[k - 1]
        vnext = V[(k + 1) % 3]
        out.append(vk + (vprev - vk).normalized() * 5.0)
        out.append(vk + (vnext - vk).normalized() * 5.0)
    # out: 6 points CCW? order them by angle
    out.sort(key=lambda v: math.atan2(v.y, v.x))
    Z0, Z1, ZB0, ZB1, ZC = -1.0, 6.0, 4.6, 5.8, 6.05
    pp = (0.03, 0.03, 0.05, 0.1)
    # backing prism (joints show as the darker backing)
    n = len(out)
    lo = Cl.add_verts([(p.x, p.y, Z0) for p in out])
    hi = Cl.add_verts([(p.x, p.y, ZB0) for p in out])
    for i in range(n):
        j = (i + 1) % n
        Cl.face([lo[i], lo[j], hi[j], hi[i]], PAL["joint"], pp)
    # panels 6 x 3 (two rows), proud 0.12, joints 0.15
    for i in range(n):
        a, b = out[i], out[(i + 1) % n]
        e = b - a
        L = e.length
        t = e.normalized()
        nrm = Vector((t.y, -t.x, 0.0))
        if nrm.dot((a + b) * 0.5) < 0:
            nrm = -nrm
        npan = max(1, round(L / 6.15))
        w = L / npan
        for k in range(npan):
            for z0, z1 in ((Z0, 2.3), (2.3, ZB0)):
                s0 = k * w + 0.075
                s1 = (k + 1) * w - 0.075
                q0 = a + t * s0
                q1 = a + t * s1
                pts = [q0, q1, q1 + nrm * 0.12, q0 + nrm * 0.12]
                zz0, zz1 = z0 + 0.075, z1 - 0.075
                ids = Cl.add_verts([(p.x, p.y, zz0) for p in pts] + [(p.x, p.y, zz1) for p in pts])
                Cl.new_vol()
                Cl.face([ids[3], ids[2], ids[6], ids[7]], PAL["cladding"], pp)
                Cl.face([ids[2], ids[1], ids[5], ids[6]], PAL["cladding"], pp)
                Cl.face([ids[0], ids[3], ids[7], ids[4]], PAL["cladding"], pp)
                Cl.face([ids[7], ids[6], ids[5], ids[4]], PAL["cladding"], pp)
        # glass band (slightly recessed) and the coping
    lo = Gl.add_verts([(p.x, p.y, ZB0) for p in out])
    hi = Gl.add_verts([(p.x, p.y, ZB1) for p in out])
    for i in range(n):
        j = (i + 1) % n
        Gl.face([lo[i], lo[j], hi[j], hi[i]], PAL["glass_band"], (0.0, 0.0, 0.0, 0.0))
    cop = [p + p.normalized() * 0.25 for p in out]
    lo = Cl.add_verts([(p.x, p.y, ZB1) for p in cop])
    hi = Cl.add_verts([(p.x, p.y, ZC) for p in cop])
    for i in range(n):
        j = (i + 1) % n
        Cl.face([lo[i], lo[j], hi[j], hi[i]], PAL["cladding"], pp)
        Cl.face([lo[j], lo[i], (Cl.add_verts([(out[i].x, out[i].y, ZB1)])[0]),
                 (Cl.add_verts([(out[j].x, out[j].y, ZB1)])[0])], PAL["joint"], pp)
    Cl.new_vol()
    Cl.face(hi, PAL["cladding"], (0.0, 0.02, 0.04, 0.1))
    # bronze steps at the mouths: 18 wide, four 1.5 risers, 2-stud treads, from r 25 out to r 33
    for m in MOUTHS:
        Br.new_vol()
        for i in range(4):
            r1 = 25.0 + 2.0 * (4 - i)
            box(Br, (-9.0, 24.6, Z0), (9.0, r1, 1.5 * (i + 1)), PAL["bronze"], mat=frame_at((0, 0, 0), m),
                paint=(0.02, 0.03, 0.06, 0.15), skip_bottom=True)
    return parts


# ------------------------------------------------------------------------------------------------ plinth and tube rim
def build_plinth():
    parts = {"Steel": MB(), "Copper": MB()}
    prism(parts["Steel"], -0.8, 1.35, 2.15, 2.15, 16, PAL["steel"], cap_top=False, paint=(0.0, 0.025, 0.04, 0.1))
    prism(parts["Copper"], 1.35, 1.6, 2.15, 2.05, 16, PAL["copper"], cap_top=True, paint=(0.0, 0.015, 0.05, 0.1))
    return parts


def build_rim():
    parts = {"Brass": MB(), "TubeDark": MB()}
    B = parts["Brass"]
    n = 24
    ri, ro = 3.6, 4.2
    pts = []
    for z in (-0.12, 0.06):
        for r in (ri, ro):
            pts.append([(r * math.cos(TAU * i / n), r * math.sin(TAU * i / n), z) for i in range(n)])
    ib, ob, it, ot = [B.add_verts(p) for p in pts]
    for i in range(n):
        j = (i + 1) % n
        B.face([it[i], it[j], ot[j], ot[i]][::-1], PAL["brass"], (0.0, 0.02, 0.04, 0.1))
        B.face([ot[i], ot[j], ob[j], ob[i]][::-1], PAL["brass"])
        B.face([ib[i], ib[j], it[j], it[i]][::-1], PAL["brass"])
    # the dark tube wall below the rim (the plate rides up this tube)
    D = parts["TubeDark"]
    a = D.add_verts([(ri * math.cos(TAU * i / n), ri * math.sin(TAU * i / n), -2.5) for i in range(n)])
    b = D.add_verts([(ri * math.cos(TAU * i / n), ri * math.sin(TAU * i / n), -0.12) for i in range(n)])
    for i in range(n):
        j = (i + 1) % n
        D.face([a[i], b[i], b[j], a[j]], PAL["tube_dark"], (0.0, 0.0, 0.0, 0.0))
    return parts


def build_tube_shadow():
    """render-only: the dark annulus of the open tube between the drum and the rim (terrain covers the hole)."""
    mb = MB()
    n = 24
    a = mb.add_verts([(2.1 * math.cos(TAU * i / n), 2.1 * math.sin(TAU * i / n), 0.03) for i in range(n)])
    b = mb.add_verts([(3.62 * math.cos(TAU * i / n), 3.62 * math.sin(TAU * i / n), 0.03) for i in range(n)])
    for i in range(n):
        j = (i + 1) % n
        mb.face([a[i], b[i], b[j], a[j]][::-1], PAL["tube_dark"], (0.0, 0.0, 0.0, 0.0))
    return {"TubeDark": mb}


# ------------------------------------------------------------------------------------------------ beds
def dome_y(r):
    return float(np.interp(r, DOME_R, DOME_Y))


def follow_dome(mb, r_centre):
    """beds are built flat along local +y (outward); drop each vertex with the knoll's 1-in-47 fall."""
    y0 = dome_y(r_centre)
    mb.v = [(x, y, z + dome_y(r_centre + y) - y0) for x, y, z in mb.v]
    return mb


def spoke_rc(b):
    return 0.5 * (max(platform_edge_r(b) + 7.0, 36.0) + SPOKE_OUT)


def build_spoke(k, heads=True):
    b = SPOKE_BEARINGS[k]
    L = spoke_len(b)
    col = SPOKE_COLOURS[k % 5]
    rng = random.Random(SEED + (200 if heads else 260) + k)
    mb = MB()
    lens_bed(mb, L, 9.0, 1.4, PAL[col], ALT[col], rng, heads=heads, row_len=1.7 if heads else 3.6)
    # the bed's long axis points outward: local +x -> +y (outward at yaw 0)
    rot = Matrix.Rotation(math.radians(90.0), 4, "Z")
    return {"BedFlowers": follow_dome(mb.transformed(rot), spoke_rc(b))}, L, col


def build_spoke_far(k):
    return build_spoke(k, heads=False)[0]


def build_teardrop(kind):
    rng = random.Random(SEED + (301 if kind == "periwinkle" else 302))
    mb = MB()
    if kind == "periwinkle":
        lens_bed(mb, 30.0, 12.0, 1.3, PAL["periwinkle"], ALT["periwinkle"], rng, shape="tear", fleck=PAL["fleck"])
        rc = TEAR_R['periwinkle']
    else:
        lens_bed(mb, 22.0, 10.0, 1.3, PAL["marigold"], ALT["marigold"], rng, shape="tear")
        rc = TEAR_R['marigold']
    rot = Matrix.Rotation(math.radians(90.0), 4, "Z")      # round end toward the platform (-y, inward)
    return {"BedFlowers": follow_dome(mb.transformed(rot), rc)}


def build_berm():
    rng = random.Random(SEED + 310)
    mb = MB()
    br = MB()
    n, rings = 14, 4
    R0, Hh = 4.2, 1.5
    prev = None
    for i in range(rings + 1):
        f = i / rings
        r = R0 * (1 - f) + 0.01
        z = Hh * math.sin(f * math.pi / 2) - 0.2
        ring = [(r * math.cos(TAU * j / n + i * 0.2), r * math.sin(TAU * j / n + i * 0.2), z + rng.uniform(-0.05, 0.05))
                for j in range(n)]
        ids = mb.add_verts(ring)
        if prev is not None:
            for j in range(n):
                jj = (j + 1) % n
                c = PAL["violet"] if i > 1 or rng.random() < 0.5 else PAL["bed_foliage"]
                mb.face([prev[j], prev[jj], ids[jj], ids[j]], c, (0.03, 0.05, 0.06, 0.12))
        prev = ids
    for _ in range(70):
        a = rng.uniform(0, TAU)
        rr = math.sqrt(rng.random()) * R0 * 0.85
        f = 1 - rr / R0
        z = Hh * math.sin(f * math.pi / 2) - 0.1
        bipyramid(mb, (rr * math.cos(a), rr * math.sin(a), z), rng.uniform(0.3, 0.5), 0.25, 5,
                  PAL["violet"] if rng.random() < 0.7 else ALT["violet"], rot=rng.uniform(0, TAU))
    # brass plaque on a short post, facing outward (+y)
    box(br, (-0.06, R0 + 0.3, -0.3), (0.06, R0 + 0.42, 0.7), PAL["brass"])
    box(br, (-0.4, R0 + 0.22, 0.5), (0.4, R0 + 0.3, 1.0), PAL["brass"])
    return {"BedFlowers": mb, "Brass": br}


def build_fuse_daisy():
    mb = MB()
    co = MB()
    prism(mb, 0.0, 0.9, 0.06, 0.05, 6, PAL["bed_foliage"])
    for i in range(10):
        a = TAU * i / 10
        c = Vector((math.cos(a), math.sin(a), 0.0))
        t = Vector((-math.sin(a), math.cos(a), 0.0))
        p0 = Vector((0, 0, 0.95)) + c * 0.15
        p1 = Vector((0, 0, 0.98)) + c * 0.6
        mb.poly([p0 - t * 0.06, p1 - t * 0.09, p1 + c * 0.05, p1 + t * 0.09, p0 + t * 0.06], PAL["yellow"])
    prism(co, 0.93, 1.05, 0.16, 0.12, 8, PAL["copper"])
    return {"Petals": mb, "Copper": co}


# ------------------------------------------------------------------------------------------------ plants
def star_tier(mb, c, R, rng, lobes, droop, thick, col, rot):
    zc = c[2]
    top = mb.add_verts([(c[0], c[1], zc + thick)])[0]
    bot = mb.add_verts([(c[0], c[1], zc - droop * 0.55)])[0]
    ring = []
    for i in range(lobes):
        a = rot + TAU * i / lobes
        rr = R * rng.uniform(0.86, 1.1)
        dz = droop * rng.uniform(0.85, 1.15)
        ring.append((c[0] + rr * math.cos(a), c[1] + rr * math.sin(a), zc - dz))
        a2 = a + math.pi / lobes
        ring.append((c[0] + 0.5 * R * math.cos(a2), c[1] + 0.5 * R * math.sin(a2), zc - 0.25 * droop))
    ids = mb.add_verts(ring)
    n = len(ids)
    mb.new_vol()
    pt = (0.05, 0.035, 0.1, 0.32)
    for i in range(n):
        j = (i + 1) % n
        mb.face([top, ids[i], ids[j]], col, pt)
        mb.face([bot, ids[j], ids[i]], col, pt)


def build_fir(seed, H):
    rng = random.Random(seed)
    bark, need = MB(), MB()
    prism(bark, -0.6, H * 0.9, 0.95 * H / 42, 0.15, 7, PAL["fir_bark"], rng=rng, rj=0.05, cap_bottom=False)
    z0 = H * rng.uniform(0.13, 0.2)
    tiers = rng.randint(8, 10)
    for i in range(tiers):
        f = i / (tiers - 1)
        zc = z0 + (H * 0.95 - z0) * f ** 0.92
        R = 0.235 * H * (1 - f) ** 0.92 + 0.55
        col = tuple(np.array(PAL["needles"]) * (0.92 + 0.14 * f))
        star_tier(need, (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), zc), R, rng, rng.choice((6, 7, 8)),
                  0.42 * R + 0.4, 0.22 * R + 0.3, col, rng.uniform(0, TAU))
    bipyramid(need, (0, 0, H * 0.94), 0.5, H * 0.06, 5, PAL["needles"])
    return {"Bark": bark, "Needles": need}


def build_pine(seed, H):
    rng = random.Random(seed)
    bark, need = MB(), MB()
    prism(bark, -0.6, H * 0.93, 1.0 * H / 45, 0.2, 7, PAL["pine_bark"], rng=rng, rj=0.05,
          tilt=(rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8)))
    for _ in range(rng.randint(2, 4)):                     # dead stubs on the clear trunk
        z = rng.uniform(0.3, 0.55) * H
        a = rng.uniform(0, TAU)
        prism(bark, z, z + 0.25, 0.12, 0.08, 4, PAL["fir_bark"], centre=(0.6 * math.cos(a), 0.6 * math.sin(a)))
    n = rng.randint(4, 6)
    for i in range(n):
        f = i / (n - 1)
        zc = H * (0.62 + 0.33 * f)
        R = H * (0.16 - 0.08 * f) * rng.uniform(0.85, 1.15)
        off = (rng.uniform(-1.6, 1.6) * (1 - f), rng.uniform(-1.6, 1.6) * (1 - f))
        col = tuple(np.array(PAL["needles_pine"]) * (0.92 + 0.12 * f))
        star_tier(need, (off[0], off[1], zc), R, rng, rng.choice((6, 7)), 0.3 * R, 0.35 * R + 0.3, col,
                  rng.uniform(0, TAU))
    return {"Bark": bark, "Needles": need}


def build_broadleaf(seed, H, lobes=(6, 8), pts=18, roundish=False):
    """beech/oak in style A: a stout 8-sided trunk forking into 3-4 limbs under one rounded crown of 6-9 big
    faceted lobes (flatter underneath, a dome on top, gaps that show the limbs) -- ArtStyle rule 3."""
    rng = random.Random(seed)
    bark, leaf = MB(), MB()
    tb = 0.7 * H / 30 + 0.5
    zf = H * rng.uniform(0.24, 0.3)
    prism(bark, -0.6, zf, tb, tb * 0.8, 8, PAL["beech_bark"], rng=rng, rj=0.04)
    crown_c = Vector((0.0, 0.0, H * 0.6))
    CR = H * (0.44 if roundish else 0.4)
    nl = rng.randint(*lobes)
    centres = [crown_c + Vector((0, 0, CR * 0.42))]
    for i in range(nl - 1):
        a = TAU * i / (nl - 1) + rng.uniform(-0.25, 0.25)
        rr = CR * rng.uniform(0.5, 0.68)
        centres.append(crown_c + Vector((rr * math.cos(a), rr * math.sin(a), rng.uniform(-0.18, 0.2) * CR)))
    for i, c in enumerate(centres[1:1 + rng.randint(3, 4)]):       # forked limbs, tapering, never one-point spokes
        p0 = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), zf - 0.4 + 0.6 * i))
        mid = p0.lerp(c, 0.55) + Vector((0, 0, 0.8))
        limb(bark, p0, mid, tb * 0.62, tb * 0.42, PAL["beech_bark"])
        limb(bark, mid, c - Vector((0, 0, CR * 0.2)), tb * 0.42, tb * 0.2, PAL["beech_bark"])
    for i, c in enumerate(centres):
        r = CR * rng.uniform(0.52, 0.64) * (1.18 if i == 0 else 1.0)
        v, f = hull(blob_points(rng, c, r, r * rng.uniform(0.9, 1.05), r * 0.86, pts, flat_bottom=0.55),
                    dissolve_deg=1.0)
        leaf.new_vol()
        tone = tuple(np.array(PAL["broadleaf"]) * rng.uniform(0.95, 1.06))
        leaf.mesh_part(v, f, tone, paint=(0.05, 0.04, 0.12, 0.32))
    return {"Bark": bark, "Leaves": leaf}


def limb(mb, p0, p1, r0, r1, col, sides=5):
    d = (p1 - p0)
    L = d.length
    if L < 1e-3:
        return
    q = d.normalized().to_track_quat("Z", "Y")
    m = q.to_matrix().to_4x4()
    m.translation = p0
    tmp = MB()
    prism(tmp, 0.0, L, r0, r1, sides, col)
    mb.extend(tmp.transformed(m))


def build_gorse(seed):
    rng = random.Random(seed)
    mb = MB()
    n = rng.randint(3, 4)
    for i in range(n):
        c = (rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0), rng.uniform(1.2, 2.2))
        r = rng.uniform(1.8, 3.0)
        v, f = hull(blob_points(rng, c, r, r * rng.uniform(0.8, 1.1), r * 0.8, 14, flat_bottom=0.9))
        mb.new_vol()

        def cf(k, fp, r_=rng):
            nrm = Vector(fp[1]) - Vector(fp[0])
            nrm = nrm.cross(Vector(fp[2]) - Vector(fp[0]))
            if nrm.length > 0 and nrm.normalized().z > 0.5 and r_.random() < 0.22:
                return PAL["gorse_flower"]
            return PAL["gorse_body"]

        mb.mesh_part(v, f, PAL["gorse_body"], paint=(0.05, 0.05, 0.1, 0.3), colfn=cf)
    return {"Bush": mb}


def build_heather(seed):
    rng = random.Random(seed)
    mb = MB()
    col = PAL["heather"] if rng.random() < 0.7 else PAL["heather_pink"]
    for i in range(rng.randint(1, 3)):
        c = (rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5), 0.25)
        r = rng.uniform(1.6, 3.2)
        v, f = hull(blob_points(rng, c, r, r * rng.uniform(0.7, 1.0), rng.uniform(0.8, 1.3), 12, flat_bottom=0.4))
        mb.new_vol()
        mb.mesh_part(v, f, col, paint=(0.06, 0.05, 0.08, 0.25))
    return {"Heather": mb}


def build_wildflowers(seed):
    rng = random.Random(seed)
    mb = MB()
    cols = [(204, 180, 72), (124, 152, 198), (218, 216, 204), (214, 168, 178)]
    v, f = hull(blob_points(rng, (0, 0, -0.15), 3.0, 2.4, 0.45, 12, flat_bottom=0.2))
    mb.mesh_part(v, f, PAL["bed_foliage"], paint=(0.03, 0.04, 0.0, 0.2))
    for _ in range(26):
        a = rng.uniform(0, TAU)
        rr = math.sqrt(rng.random()) * 2.6
        bipyramid(mb, (rr * math.cos(a), rr * math.sin(a), 0.3 + rng.uniform(0, 0.25)), rng.uniform(0.25, 0.4), 0.09,
                  5, rng.choice(cols), rot=rng.uniform(0, TAU))
    return {"BedFlowers": mb}


def build_tallgrass(seed):
    rng = random.Random(seed)
    mb = MB()
    for i in range(7):
        a = rng.uniform(0, TAU)
        rr = rng.uniform(0, 1.6)
        c = (rr * math.cos(a), rr * math.sin(a))
        h = rng.uniform(2.5, 3.5)
        lean = Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0))
        base = [Vector((c[0] + 0.4 * math.cos(t), c[1] + 0.4 * math.sin(t), 0)) for t in (0, 2.1, 4.2)]
        tip = Vector((c[0], c[1], h)) + lean
        mb.new_vol()
        for k in range(3):
            mb.poly([base[k], base[(k + 1) % 3], tip], PAL["golden_grass"], (0.06, 0.05, 0.1, 0.2))
    return {"Grass": mb}


def jointed_block(rng, a, b, c, cuts=3, pts=26, dissolve=4.0):
    raw = []
    for _ in range(pts):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        m = max(abs(d.x), abs(d.y), abs(d.z))
        d = d / m
        raw.append(Vector((d.x * a, d.y * b, d.z * c)) * rng.uniform(0.9, 1.0))
    for _ in range(cuts):
        n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1))).normalized()
        off = rng.uniform(0.55, 0.85) * (abs(n.x) * a + abs(n.y) * b + abs(n.z) * c)
        raw = [p - n * (p.dot(n) - off) if p.dot(n) > off else p for p in raw]
    return hull(raw, dissolve_deg=dissolve)


def build_boulder(seed, size):
    """two overlapping jointed blocks and a spall (ArtStyle 3.1's boulder), 0.5-1.5-stud facets, 150-300 tris."""
    rng = random.Random(seed)
    mb = MB()
    blocks = [((0.0, 0.0), size * 0.5, size * rng.uniform(0.36, 0.46), size * rng.uniform(0.26, 0.36), 4, 64),
              ((size * 0.28, size * 0.12), size * 0.34, size * 0.3, size * 0.24, 3, 44),
              ((-size * 0.34, -size * 0.2), size * 0.16, size * 0.14, size * 0.1, 2, 24)]
    for (ox, oy), a, b, c, cuts, pts in blocks:
        v, f = jointed_block(rng, a, b, c, cuts=cuts, pts=pts, dissolve=1.5)
        v = [(p[0] + ox, p[1] + oy, p[2]) for p in v]
        zmin = min(p[2] for p in v)
        v = [(p[0], p[1], p[2] - zmin - c * 0.35) for p in v]
        mb.new_vol()

        def cf(k, fp):
            n = (Vector(fp[1]) - Vector(fp[0])).cross(Vector(fp[2]) - Vector(fp[0]))
            if n.length > 0 and n.normalized().z > 0.9 and rng.random() < 0.35:
                return tuple(np.array(PAL["dry"]) * 0.92)          # lichen and grass on the top facets
            return PAL["white_boulder"]

        mb.mesh_part(v, f, PAL["white_boulder"], paint=(0.04, 0.04, 0.06, 0.18), colfn=cf)
    return {"Limestone": mb}


def build_crag(seed, W, Hh, D):
    """jointed limestone strata: stacked blocks with bedding planes, grassy ledges on upward facets."""
    rng = random.Random(seed)
    mb = MB()
    strata = max(2, int(Hh / rng.uniform(9, 13)))
    z = -Hh * 0.08
    for s_ in range(strata):
        th = Hh / strata * rng.uniform(0.85, 1.15)
        width = W * (1.0 - 0.45 * s_ / strata) * rng.uniform(0.85, 1.0)
        nb = max(1, int(width / rng.uniform(9, 14)))
        x = -width / 2
        tone = np.array(PAL["limestone"]) * rng.uniform(0.94, 1.06)
        for b in range(nb):
            bw = width / nb * rng.uniform(0.9, 1.15)
            v, f = jointed_block(rng, bw / 2, D / 2 * rng.uniform(0.7, 1.0) * (1 - 0.3 * s_ / strata), th / 2,
                                 cuts=3, pts=40, dissolve=2.5)
            off = Vector((x + bw / 2, rng.uniform(-D * 0.12, D * 0.12), z + th / 2))
            v = [tuple(Vector(p) + off) for p in v]
            mb.new_vol()

            def cf(k, fp, tone_=tone):
                n = (Vector(fp[1]) - Vector(fp[0])).cross(Vector(fp[2]) - Vector(fp[0]))
                if n.length > 0 and n.normalized().z > 0.8:
                    return tuple(np.array(PAL["dry"]) * 0.95)
                return tuple(tone_)

            mb.mesh_part(v, f, tuple(tone), paint=(0.04, 0.035, 0.06, 0.16), colfn=cf)
            x += bw * rng.uniform(0.82, 0.95)
        z += th * 0.92
    return {"Limestone": mb}


def build_peak():
    """the volcano: a sharp limestone horn-peak (too thin for terrain, ArenaV3 7.1), like the Pico of T2 @49.9 s.
    A ring-and-segment shell (not a convex hull, so gullies and ledges stay concave): a four-arete section that
    narrows and leans south-east to a hooked summit, stepped strata every ~20 studs, cliff facets of 8-20 studs,
    painted in tilted bedding bands with grassy ledges and a dark gully down the north face (the throat).
    Two lower shoulder towers sit either side. The base is buried in the terrain shoulder."""
    rng = random.Random(SEED + 500)
    nzp = Noise(SEED + 501)
    lime, core = MB(), MB()
    TOP = 640.0

    def tower(cx, cy, base_r, height, lean, rot, rings, segs, aretes=4, gully=None, salt=0):
        ring_ids = []
        for i in range(rings + 1):
            f = i / rings
            z = height * f
            step = 1.0 + (0.07 if i % 2 else -0.04) * (0.3 < f < 0.92)       # strata ledges
            env = base_r * (1.0 - f) ** 1.05 * step + 2.5
            ox, oy = cx + lean[0] * f ** 1.4, cy + lean[1] * f ** 1.4
            ids = []
            for j in range(segs):
                th = TAU * j / segs + rot
                ar = 1.0 + 0.22 * abs(math.cos(aretes / 2.0 * (th - rot))) ** 3       # aretes
                n = float(nzp(math.cos(th) * 2.0 + salt, z / 60.0 + math.sin(th) * 2.0))
                r = env * ar * (1.0 + 0.1 * n)
                if gully is not None:
                    d = abs(((th - gully + math.pi) % TAU) - math.pi)
                    r *= 1.0 - 0.16 * max(0.0, 1.0 - d / 0.45) * (0.15 < f < 0.85)
                ids.append(len(lime.v))
                lime.v.append((ox + r * math.cos(th), oy + r * math.sin(th), z))
            ring_ids.append(ids)
        lime.new_vol()
        for i in range(rings):
            a, b = ring_ids[i], ring_ids[i + 1]
            for j in range(segs):
                k = (j + 1) % segs
                pa, pb, pc, pd = (Vector(lime.v[a[j]]), Vector(lime.v[a[k]]), Vector(lime.v[b[k]]),
                                  Vector(lime.v[b[j]]))
                for tri in ((a[j], a[k], b[k]), (a[j], b[k], b[j])):
                    p0, p1, p2 = (Vector(lime.v[t]) for t in tri)
                    nrm = (p1 - p0).cross(p2 - p0)
                    c = (p0 + p1 + p2) / 3.0
                    band = int((c.z + 0.18 * c.x - 0.1 * c.y) // 21.0)
                    tone = np.array(PAL["limestone"]) * (1.02 if (band + salt) % 2 else 0.88)
                    if nrm.length > 0 and nrm.normalized().z > 0.55:
                        tone = np.array(PAL["dry"]) * 0.9                     # grassy ledges
                    if gully is not None:
                        th_c = math.atan2(c.y - cy, c.x - cx)
                        if abs(((th_c - gully + math.pi) % TAU) - math.pi) < 0.3 and c.z > height * 0.12:
                            tone = np.array(PAL["dark_rock"]) * 0.95       # the throat
                    lime.face(list(tri), tuple(tone), (0.03, 0.035, 0.05, 0.12))
        top = ring_ids[-1]
        apex = len(lime.v)
        lime.v.append((cx + lean[0] + 2.0, cy + lean[1] - 3.0, height + 9.0))
        for j in range(segs):
            lime.face([top[j], top[(j + 1) % segs], apex], PAL["limestone"], (0.03, 0.035, 0.05, 0.12))

    # main horn (PEAK_H tall above its buried base), leaning south-east; the throat gully faces north (+y)
    tower(0.0, 0.0, 150.0, PEAK_H - 9.0, (36.0, -34.0), 0.35, 18, 22, gully=math.pi / 2 + 0.25, salt=0)
    tower(-128.0, 22.0, 88.0, 190.0, (-10.0, -8.0), 0.9, 10, 14, salt=1)           # west shoulder tower
    tower(132.0, -4.0, 80.0, 160.0, (12.0, -6.0), 0.2, 9, 14, salt=2)              # east shoulder
    tower(-24.0, 86.0, 72.0, 205.0, (10.0, -22.0), 1.3, 11, 14, salt=3)            # fore-summit on the north face
    return {"Limestone": lime, "DarkRock": core}, TOP


def build_spiral():
    """the crimson spiral: a mounded 3-turn spiral of red and magenta flower hedge, 50 across, 4 tall, 2.5 thick."""
    rng = random.Random(SEED + 600)
    hedge = MB()
    pitch = 6.5
    r0 = 4.0
    turns = 3.0
    steps = int(turns * 64)
    prof = [(-1.25, 0.0), (-1.2, 1.6), (-0.8, 3.3), (0.0, 4.0), (0.8, 3.3), (1.2, 1.6), (1.25, 0.0)]
    rings = []
    for i in range(steps + 1):
        ph = turns * TAU * i / steps
        r = r0 + pitch * ph / TAU
        c = Vector((r * math.cos(ph), r * math.sin(ph), 0.0))
        rad = Vector((math.cos(ph), math.sin(ph), 0.0))
        hmul = 0.75 + 0.25 * min(1.0, i / 40.0)
        pts = [c + rad * (u * rng.uniform(0.92, 1.08)) + Vector((0, 0, max(0.0, z * hmul + rng.uniform(-0.15, 0.15))))
               for u, z in prof]
        rings.append(hedge.add_verts(pts))
    for i in range(steps):
        a, b = rings[i], rings[i + 1]
        for j in range(len(prof) - 1):
            low = j in (0, len(prof) - 2)
            col = PAL["bed_foliage"] if (low and rng.random() < 0.6) else (
                PAL["crimson"] if rng.random() < 0.7 else ALT["crimson"])
            hedge.face([a[j], a[j + 1], b[j + 1], b[j]], col, (0.04, 0.07, 0.06, 0.2))
    hedge.face(rings[0], PAL["crimson"])
    hedge.face(rings[-1][::-1], PAL["crimson"])
    return {"BedFlowers": hedge}


def build_holly():
    rng = random.Random(SEED + 700)
    mb, be = MB(), MB()
    nx, ny, nz_ = 4, 2, 6
    L, T, Hh = 12.0, 5.0, 16.0
    # lumpy faceted wall: a subdivided box with displaced outer vertices
    for side in (-1, 1):
        grid = []
        for k in range(nz_ + 1):
            row = []
            for i in range(nx + 1):
                x = -L / 2 + L * i / nx
                z = Hh * k / nz_
                bulge = rng.uniform(-0.45, 0.45) + (0.0 if k in (0,) else 0.25)
                yy = side * (T / 2 + bulge - 0.4 * (z / Hh) ** 2)
                row.append((x + rng.uniform(-0.3, 0.3) * (0 < i < nx), yy, z + rng.uniform(-0.3, 0.3) * (0 < k < nz_)))
            grid.append(mb.add_verts(row))
        for k in range(nz_):
            for i in range(nx):
                q = [grid[k][i], grid[k][i + 1], grid[k + 1][i + 1], grid[k + 1][i]]
                mb.face(q if side < 0 else q[::-1], PAL["holly"], (0.05, 0.05, 0.08, 0.2))
        if side < 0:
            g0 = grid
        else:
            g1 = grid
    for i in range(nx):     # top
        mb.face([g0[nz_][i], g0[nz_][i + 1], g1[nz_][i + 1], g1[nz_][i]], PAL["holly"], (0.05, 0.05, 0.1, 0.2))
    for k in range(nz_):    # ends
        mb.face([g0[k][0], g0[k + 1][0], g1[k + 1][0], g1[k][0]], PAL["holly"])
        mb.face([g0[k][nx], g1[k][nx], g1[k + 1][nx], g0[k + 1][nx]], PAL["holly"])
    for _ in range(18):     # the "berries" (ladybug mutts): sparse 0.3-stud lumps, a hazard tell
        side = rng.choice((-1, 1))
        bipyramid(be, (rng.uniform(-L / 2 + 1, L / 2 - 1), side * (T / 2 + 0.55), rng.uniform(2, Hh - 2)), 0.32, 0.25, 5,
                  PAL["berry"])
    return {"Hedge": mb, "Berries": be}


def build_sunglade():
    rng = random.Random(SEED + 800)
    grass, beds = MB(), MB()
    n = 24
    ring = grass.add_verts([(12.0 * math.cos(TAU * i / n), 12.0 * math.sin(TAU * i / n), 0.15) for i in range(n)])
    cen = grass.add_verts([(0.0, 0.0, 0.3)])[0]
    for i in range(n):
        grass.face([cen, ring[i], ring[(i + 1) % n]], PAL["golden_grass"], (0.0, 0.04, 0.06, 0.1))
    for i in range(16):
        a = TAU * i / 16
        L = 12.0 + 8.0 * ((i * 7) % 5) / 4.0
        col = ("pink", "magenta", "lavender", "coral")[i % 4]
        c = PAL[col] if col in PAL else PAL["pink"]
        tmp = MB()
        lens_bed(tmp, L, 3.6, 0.9, c, ALT.get(col, c), rng, head_density=2.2)
        m = Matrix.Rotation(a, 4, "Z") @ Matrix.Translation((14.0 + L / 2, 0.0, 0.0))
        beds.extend(tmp.transformed(m))
    for i in range(16):     # peach pompoms ringing the grass circle
        a = TAU * (i + 0.5) / 16
        bipyramid(beds, (13.0 * math.cos(a), 13.0 * math.sin(a), 0.6), 0.9, 0.7, 6, PAL["peach"], rot=a)
    return {"Grass": grass, "BedFlowers": beds}


def build_tribute(seed):
    """render-only scale figure: a 5.5-stud tribute in a white hooded cape."""
    rng = random.Random(seed)
    cape, skin = MB(), MB()
    v, f = hull([(0.95 * math.cos(a), 0.75 * math.sin(a), 0.0) for a in np.linspace(0, TAU, 9)[:-1]]
                + [(0.8 * math.cos(a), 0.55 * math.sin(a), 3.4) for a in np.linspace(0, TAU, 7)[:-1]]
                + [(0.0, 0.0, 4.6), (0.42, 0.0, 4.4), (-0.42, 0.0, 4.4), (0.0, -0.4, 5.3), (0.0, 0.3, 5.5)])
    cape.mesh_part(v, f, PAL["cape"], paint=(0.03, 0.03, 0.06, 0.2))
    bipyramid(skin, (0.0, 0.33, 4.75), 0.3, 0.32, 5, PAL["skin"])
    return {"Cape": cape, "Skin": skin}


# ================================================================================================ assets registry
class Asset:
    def __init__(self, name, kind, parts, tags=(), notes="", collide=None, export=True, glb="Map1_Landmarks",
                 attachments=None):
        self.name, self.kind, self.parts = name, kind, parts
        self.tags, self.notes, self.export, self.glb = list(tags), notes, export, glb
        self.collide = collide or {}
        self.attachments = attachments or {}
        self.render_obj = None


COLLIDE = {   # role -> (collide, CollisionFidelity, castShadow)
    "HornSail": (True, "PreciseConvexDecomposition", True), "HornInner": (True, "PreciseConvexDecomposition", True),
    "HornGold": (False, "Box", False), "HornFloor": (True, "Box", True), "Cladding": (True, "Hull", True),
    "GlassBand": (False, "Box", False), "Bronze": (True, "PreciseConvexDecomposition", True),
    "Steel": (True, "Hull", True), "Copper": (True, "Box", True), "Brass": (False, "Box", False),
    "TubeDark": (False, "Box", False), "BedFlowers": (False, "Box", False), "BedFoliage": (False, "Box", False),
    "Petals": (False, "Box", False), "Bark": (True, "Hull", True), "Leaves": (False, "Box", True),
    "Needles": (False, "Box", True), "Bush": (False, "Box", True), "Heather": (False, "Box", False),
    "Limestone": (True, "Default", True), "DarkRock": (True, "Default", True), "Hedge": (True, "Box", True),
    "Berries": (False, "Box", False), "Grass": (False, "Box", False), "Cape": (False, "Box", True),
    "Skin": (False, "Box", True),
}


def build_assets():
    A = {}

    def add(a):
        A[a.name] = a

    log("assets: heart")
    add(Asset("M1_Horn", "Landmark", build_horn(), tags=["Horn", "Cornucopia"],
              notes="6 sails in 3 pairs round a hollow walk-in core; mouths (A-frames 16 x 14) at 60/180/300; inner "
                    "sails 50 above the deck, outer 36. Pivot: deck centre (world y 52).",
              attachments={"Mouth_%d" % m: dict(position=to_roblox(P3(m, 11.0, 0.0)),
                                                 look=to_roblox(P2(m, 1.0)), up=[0, 1, 0]) for m in MOUTHS}))
    add(Asset("M1_Platform", "Landmark", build_platform(), tags=["HornPlatform"],
              notes="three-pointed star (triangle, points r 50 at 0/120/240, clipped), 6 high above the knoll (y 46 "
                    "-> deck 52), embedded 1 stud; bronze steps (18 wide, 4 x 1.5) at the mouths. Pivot: knoll level.",
              attachments={"Deck": dict(position=[0, 6.05, 0], look=[0, 0, -1], up=[0, 1, 0])}))
    add(Asset("M1_Plinth", "Landmark", build_plinth(), tags=["Plinth"],
              notes="brushed steel drum 4.3 x 1.6 with a 0.25 copper top plate; hidden 0.8 below the turf. Pivot: turf.",
              attachments={"Stand": dict(position=[0, 1.6, 0], look=[0, 0, -1], up=[0, 1, 0])}))
    add(Asset("M1_PlateTubeRim", "Landmark", build_rim(), tags=["PlateCollar"],
              notes="brass rim 8.4 across (PlateTube r 3.6), flush with the turf, plus the dark tube wall to -2.5."))
    add(Asset("M1_TubeShadow", "RenderOnly", build_tube_shadow(), export=False))
    log("assets: beds")
    for k in range(len(SPOKE_BEARINGS)):
        parts, L, col = build_spoke(k)
        add(Asset("M1_Spoke_%02d" % k, "FlowerBed", parts, tags=["FlowerBed", "Hazard", col],
                  notes="pointed flower spoke %.1f x 9 x 1.4 (%s), long axis along Roblox -Z (north, i.e. outward when yawed to its bearing)" % (L, col)))
        add(Asset("M1_Spoke_%02d_Far" % k, "FlowerBedFar", build_spoke_far(k), tags=["FarMesh"],
                  notes="far mesh of M1_Spoke_%02d (no flower heads)" % k))
    add(Asset("M1_TeardropPeriwinkle", "FlowerBed", build_teardrop("periwinkle"), tags=["FlowerBed", "Hazard"],
              notes="periwinkle and white teardrop 30 x 12 (the owner's 'pale radial pattern'); round end toward Roblox +Z (inward when yawed to its bearing)"))
    add(Asset("M1_TeardropMarigold", "FlowerBed", build_teardrop("marigold"), tags=["FlowerBed", "Hazard"],
              notes="marigold teardrop 22 x 10"))
    add(Asset("M1_Berm", "FlowerBed", build_berm(), tags=["Berm", "Hatch"],
              notes="round berm 8.4 x 1.5 of one poisonous flower with a brass plaque (may hide a Sub-A hatch)"))
    add(Asset("M1_FuseDaisy", "Hazard", build_fuse_daisy(), tags=["Hazard", "FuseDaisy"],
              notes="the exploding-bed tell: a 1.2-stud metal daisy with a copper fuse centre"))
    log("assets: set pieces")
    add(Asset("M1_LoneTree", "Tree", build_broadleaf(SEED + 900, 30.0, lobes=(8, 9), pts=26, roundish=True),
              tags=["LoneTree", "Placeholder"],
              notes="PLACEHOLDER: one of the three lone round trees on the mouth bearings at r 300"))
    add(Asset("M1_CrimsonSpiral", "Landmark", build_spiral(), tags=["Spiral", "Hazard"],
              notes="3-turn mounded spiral of red and magenta flower hedge, ~50 across, hedges 4 x 2.5, paths ~4"))
    add(Asset("M1_HollyHedge", "Landmark", build_holly(), tags=["HollyHedge", "Maze"],
              notes="holly hedge module 12 long, 16 tall, 5 thick; red berries are the ladybug-mutt tell"))
    add(Asset("M1_SunGlade", "Landmark", build_sunglade(), tags=["SunGlade", "Lure"],
              notes="24-stud golden grass circle ringed by peach pompoms with 16 flower spokes 12-20 long"))
    peak, top = build_peak()
    add(Asset("M1_Peak", "Landmark", peak, tags=["Peak", "Volcano"],
              notes="the sharp limestone horn-peak (the volcano), ~290 tall over the terrain shoulder; summit ~y 640"))
    for i, (w, h, d) in enumerate(((46.0, 34.0, 26.0), (74.0, 52.0, 34.0), (30.0, 62.0, 26.0))):
        add(Asset("M1_Crag_%s" % "ABC"[i], "Rock", build_crag(SEED + 520 + i, w, h, d), tags=["Crag", "Limestone"],
                  notes="jointed limestone crag module, %d wide x %d tall" % (w, h)))
    for i, s_ in enumerate((3.0, 5.0, 8.0)):
        add(Asset("M1_Boulder_%s" % "ABC"[i], "Rock", build_boulder(SEED + 540 + i, s_), tags=["Boulder"],
                  notes="white limestone boulder ~%d across" % s_))
    log("assets: plants (placeholders)")
    for i, h in enumerate((38.0, 44.0, 48.0)):
        add(Asset("M1_Fir_%s" % "ABC"[i], "Tree", build_fir(SEED + 1000 + i, h), tags=["Conifer", "Placeholder"],
                  glb="Map1_Plants", notes="PLACEHOLDER fir %d tall (style A star-lobed tiers)" % h))
    for i, h in enumerate((42.0, 48.0)):
        add(Asset("M1_Pine_%s" % "AB"[i], "Tree", build_pine(SEED + 1100 + i, h), tags=["Conifer", "Placeholder"],
                  glb="Map1_Plants", notes="PLACEHOLDER pine %d tall, tall clear pinkish trunk" % h))
    for i, h in enumerate((26.0, 32.0)):
        add(Asset("M1_Beech_%s" % "AB"[i], "Tree", build_broadleaf(SEED + 1200 + i, h), tags=["Broadleaf", "Placeholder"],
                  glb="Map1_Plants", notes="PLACEHOLDER beech %d tall, 6-8 crown lobes" % h))
    for i in range(2):
        add(Asset("M1_Gorse_%s" % "AB"[i], "Plant", build_gorse(SEED + 1300 + i), tags=["Bush", "Placeholder"],
                  glb="Map1_Plants", notes="PLACEHOLDER gorse clump with yellow flower facets"))
        add(Asset("M1_Heather_%s" % "AB"[i], "Plant", build_heather(SEED + 1400 + i), tags=["Heather", "Placeholder"],
                  glb="Map1_Plants", notes="PLACEHOLDER heather mat"))
    add(Asset("M1_Wildflowers_A", "Plant", build_wildflowers(SEED + 1500), tags=["Wildflowers", "Placeholder"],
              glb="Map1_Plants", notes="PLACEHOLDER wildflower clump (yellow, blue, white)"))
    add(Asset("M1_TallGrass_A", "Plant", build_tallgrass(SEED + 1600), tags=["TallGrass", "Placeholder"],
              glb="Map1_Plants", notes="PLACEHOLDER tall pale grass clump 2.5-3.5"))
    for i in range(3):
        add(Asset("M1_Tribute_%d" % i, "RenderOnly", build_tribute(SEED + 1700 + i), export=False))
    for a in A.values():
        log("  %-26s %6d tris  %s" % (a.name, sum(p.tris() for p in a.parts.values()), ",".join(a.parts)))
    return A


# ================================================================================================ materials
def fog_group():
    ng = bpy.data.node_groups.get("M1_Fog")
    if ng:
        return ng
    ng = bpy.data.node_groups.new("M1_Fog", "ShaderNodeTree")
    ng.interface.new_socket(name="Shader", in_out="INPUT", socket_type="NodeSocketShader")
    ng.interface.new_socket(name="Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    N, Lk = ng.nodes, ng.links
    gi = N.new("NodeGroupInput")
    go = N.new("NodeGroupOutput")
    cam = N.new("ShaderNodeCameraData")
    geo = N.new("ShaderNodeNewGeometry")
    sep = N.new("ShaderNodeSeparateXYZ")
    Lk.new(geo.outputs["Position"], sep.inputs[0])
    dist_v = N.new("ShaderNodeValue")
    dist_v.name = "FogDist"
    dist_v.outputs[0].default_value = 2800.0
    hgt_v = N.new("ShaderNodeValue")
    hgt_v.name = "FogHeight"
    hgt_v.outputs[0].default_value = 700.0
    max_v = N.new("ShaderNodeValue")
    max_v.name = "FogMax"
    max_v.outputs[0].default_value = 0.92

    def math_(op, a, b=None):
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

    camz = N.new("ShaderNodeValue")
    camz.name = "CamZ"
    camz.outputs[0].default_value = 100.0
    zavg = math_("MULTIPLY", math_("ADD", sep.outputs[2], camz.outputs[0]), 0.5)   # mean height along the ray
    zrel = math_("MAXIMUM", math_("SUBTRACT", zavg, 40.0), 0.0)
    hf = math_("EXPONENT", math_("DIVIDE", math_("MULTIPLY", zrel, -1.0), hgt_v.outputs[0]))
    dens = math_("ADD", 0.12, math_("MULTIPLY", hf, 0.88))
    od = math_("MULTIPLY", math_("DIVIDE", cam.outputs["View Distance"], dist_v.outputs[0]), dens)
    fog = math_("SUBTRACT", 1.0, math_("EXPONENT", math_("MULTIPLY", od, -1.0)))
    fog = math_("MULTIPLY", fog, max_v.outputs[0])
    em = N.new("ShaderNodeEmission")
    em.name = "FogEmission"
    em.inputs["Color"].default_value = (*lin(PAL["haze"]), 1.0)
    em.inputs["Strength"].default_value = 1.0
    mix = N.new("ShaderNodeMixShader")
    Lk.new(fog, mix.inputs[0])
    Lk.new(gi.outputs[0], mix.inputs[1])
    Lk.new(em.outputs[0], mix.inputs[2])
    Lk.new(mix.outputs[0], go.inputs[0])
    return ng


def make_material(name, kind):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    if kind == "cloud":
        vol = nt.nodes.new("ShaderNodeVolumePrincipled")
        vol.name = "Vol"
        vol.inputs["Color"].default_value = (*lin(PAL["mist"]), 1.0)
        vol.inputs["Density"].default_value = 0.006
        vol.inputs["Anisotropy"].default_value = 0.3
        # a little in-volume emission stands in for multiple scattering, so thick banks read bright, not grey
        vol.inputs["Emission Color"].default_value = (*lin(PAL["mist"]), 1.0)
        vol.inputs["Emission Strength"].default_value = 0.0035
        nt.links.new(vol.outputs[0], out.inputs["Volume"])
        return m
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    if kind != "water":
        attr = nt.nodes.new("ShaderNodeAttribute")
        attr.attribute_name = "Col"
        attr.attribute_type = "GEOMETRY"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    rough = {"paint": 0.88, "terrain": 1.0, "metal": 0.42, "glass": 0.18, "water": 0.06}[kind]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.72 if kind == "metal" else 0.0
    bsdf.inputs["Specular IOR Level"].default_value = {"paint": 0.18, "terrain": 0.06}.get(kind, 0.5)
    if kind == "water":
        bsdf.inputs["Base Color"].default_value = (*lin(PAL["water"]), 1.0)
        bsdf.inputs["Specular IOR Level"].default_value = 0.6
        bump = nt.nodes.new("ShaderNodeBump")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.08
        noise.inputs["Detail"].default_value = 3.0
        bump.inputs["Strength"].default_value = 0.06
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = fog_group()
    nt.links.new(bsdf.outputs[0], grp.inputs[0])
    nt.links.new(grp.outputs[0], out.inputs["Surface"])
    return m


KIND_INDEX = {"paint": 0, "metal": 1, "glass": 2}


def render_object(asset, coll):
    """one joined object per asset with paint/metal/glass slots, hidden itself (instanced by the scene)."""
    mb = MB()
    mats = []
    for role, part in asset.parts.items():
        kind = ROLES[role][4]
        if not part.f:
            continue
        mb.extend(part)
        mats.extend([KIND_INDEX[kind]] * len(part.f))
    me = to_mesh(asset.name + "_R", mb, salt=zlib.crc32(asset.name.encode()) % 997, mat_index=mats)
    for k in ("paint", "metal", "glass"):
        me.materials.append(make_material("M1_" + k.capitalize(), k))
    ob = bpy.data.objects.new(asset.name + "_R", me)
    coll.objects.link(ob)
    ob.hide_render = True
    ob.hide_viewport = True
    asset.render_obj = ob
    return ob


# ================================================================================================ GLB export
def export_glbs(A):
    for glb in ("Map1_Landmarks", "Map1_Plants"):
        names = [a for a in A.values() if a.export and a.glb == glb]
        if not names:
            continue
        sc = bpy.context.scene
        root_col = bpy.data.collections.new("EXPORT_" + glb)
        sc.collection.children.link(root_col)
        for o in sc.objects:
            o.select_set(False)
        x = 0.0
        manifest_assets = []
        objs = []
        for a in names:
            # bounds in local Blender space
            allv = np.array([p for part in a.parts.values() for p in part.v])
            lo, hi = allv.min(0), allv.max(0)
            width = hi[0] - lo[0]
            x += -lo[0] + 2.0
            emp = bpy.data.objects.new(a.name, None)
            root_col.objects.link(emp)
            emp.location = (x, 0.0, 0.0)
            parts = []
            tris_total = 0
            for i, (role, part) in enumerate(a.parts.items()):
                if not part.f:
                    continue
                me = bpy.data.meshes.new("%s_%s" % (a.name, role))
                me.from_pydata(part.v, [], part.f)
                me.update()
                fix_normals(me)
                box_uv(me)
                try:
                    me.shade_flat()
                except AttributeError:
                    pass
                mat = flat_material(role)
                me.materials.append(mat)
                ob = bpy.data.objects.new("%s_%s" % (a.name, role), me)
                root_col.objects.link(ob)
                ob.parent = emp
                objs.append(ob)
                tri = part.tris()
                tris_total += tri
                rmat, pkey, metal, rough, _ = ROLES[role]
                col, colfid, shadow = COLLIDE.get(role, (False, "Box", True))
                parts.append(dict(name="%s_%s" % (a.name, role), role=role, robloxMaterial=rmat,
                                  rgb=list(part_rgb(part)), collide=col, collision=colfid, castShadow=shadow,
                                  canQuery=col, canTouch=col, tags=[], tris=tri,
                                  metalness=metal, roughness=rough))
            objs.append(emp)
            manifest_assets.append(dict(
                name=a.name, kind=a.kind, tags=a.tags, notes=a.notes, origin=to_roblox((x, 0.0, 0.0)),
                size=[round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3), round(float(hi[1] - lo[1]), 3)],
                boundsMin=[round(float(lo[0]), 3), round(float(lo[2]), 3), round(float(-hi[1]), 3)],
                boundsMax=[round(float(hi[0]), 3), round(float(hi[2]), 3), round(float(-lo[1]), 3)],
                tris=tris_total, parts=parts, attachments=a.attachments,
                pivot="base centre on the ground (see notes)"))
            x += hi[0] + 2.0
        path = os.path.join(OUT, glb + ".glb")
        bpy.context.view_layer.update()
        for o in objs:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_apply=True, export_materials="EXPORT", export_vertex_color="NONE",
                                  export_tangents=True, export_cameras=False, export_lights=False)
        man = dict(category=glb, glb=os.path.basename(path), units="studs (1 Blender unit = 1 stud)",
                   axes="Roblox: X east, Y up, Z south (glTF +Y up; Blender (x,y,z) -> Roblox (x,z,-y))",
                   generator="art/blender/map1_green_land.py", seed=SEED, warnings=[],
                   placeholder=(glb == "Map1_Plants"), assets=manifest_assets,
                   notes=("Flat per-part colours (rgb, sRGB) are the semi-real tones of UpcomingFilm_Brief 1.10; "
                          "the Blender previews add +-3-6% facet value jitter and top/underside shading that a later "
                          "baked colour map (ArtStyle rule 4-5) carries. Every part is single-sided."))
        for a in manifest_assets:
            if a["tris"] > 20000:
                man["warnings"].append("%s over 20k triangles" % a["name"])
            for p in a["parts"]:
                if p["tris"] > 5000:
                    man["warnings"].append("%s over 5k triangles" % p["name"])
        mpath = os.path.join(OUT, glb + ".manifest.json")
        with open(mpath, "w") as f:
            json.dump(man, f, indent=1)
        if os.path.isdir(MANIFEST_COPY):
            shutil.copy2(mpath, os.path.join(MANIFEST_COPY, os.path.basename(mpath)))
        log("EXPORTED %s (%.2f MB), %d assets, %d warnings" % (path, os.path.getsize(path) / 1e6,
                                                                 len(manifest_assets), len(man["warnings"])))
        for w in man["warnings"]:
            log("WARNING", w)
        for o in list(root_col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(root_col)


_flat_cache = {}


def flat_material(role):
    if role in _flat_cache:
        return _flat_cache[role]
    rmat, pkey, metal, rough, _ = ROLES[role]
    m = bpy.data.materials.new("Map1_" + role)
    try:
        m.use_nodes = True
    except Exception:
        pass
    m.use_backface_culling = True          # glTF doubleSided false: single-sided, as the pipeline requires
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin(PAL[pkey]), 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    _flat_cache[role] = m
    return m


def part_rgb(part):
    """the dominant base colour of a part (sRGB)."""
    if not part.base:
        return (128, 128, 128)
    cols, counts = np.unique(np.round(np.asarray(part.base)).astype(int), axis=0, return_counts=True)
    return tuple(int(c) for c in cols[np.argmax(counts)])


# ================================================================================================ STAGE: scene
def terrain_mesh(H, colours, name="M1_Terrain"):
    """4-stud cells inside +-1,950 (ArenaV3's fine grid), 8-stud cells outside, crack-free (T-junction snap)."""
    n = NF
    c = -HALF + SPP * (np.arange(n) + 0.5)
    I0, I1 = 200, 1174
    use = np.zeros((n, n), bool)
    ev = np.zeros(n, bool)
    ev[0:n - 1:2] = True
    use[np.ix_(ev, ev)] = True
    use[I0:I1 + 1, I0:I1 + 1] = True
    vid = -np.ones((n, n), np.int64)
    jj, ii = np.nonzero(use)
    vid[jj, ii] = np.arange(len(jj))
    Z = H.astype(np.float64).copy()
    # snap odd boundary vertices of the fine block onto the coarse edges
    for k in range(I0 + 1, I1, 2):
        for (ja, ia, jb, ib, jc, ic) in ((I0, k, I0, k - 1, I0, k + 1), (I1, k, I1, k - 1, I1, k + 1),
                                         (k, I0, k - 1, I0, k + 1, I0), (k, I1, k - 1, I1, k + 1, I1)):
            Z[ja, ia] = 0.5 * (Z[jb, ib] + Z[jc, ic])
    verts = np.stack([c[ii], -c[jj], Z[jj, ii]], 1).astype(np.float32)
    tris = []

    def cells(j0s, i0s, step):
        J, I = np.meshgrid(j0s, i0s, indexing="ij")
        J = J.ravel()
        I = I.ravel()
        a = vid[J, I]
        b = vid[J, I + step]
        cc = vid[J + step, I + step]
        d = vid[J + step, I]
        ok = (a >= 0) & (b >= 0) & (cc >= 0) & (d >= 0)
        a, b, cc, d = a[ok], b[ok], cc[ok], d[ok]
        za, zb, zc, zd = verts[a, 2], verts[b, 2], verts[cc, 2], verts[d, 2]
        diag = np.abs(za - zc) <= np.abs(zb - zd)
        t1 = np.where(diag[:, None], np.stack([a, d, cc], 1), np.stack([a, d, b], 1))
        t2 = np.where(diag[:, None], np.stack([a, cc, b], 1), np.stack([b, d, cc], 1))
        return np.concatenate([t1, t2])

    fine = cells(np.arange(I0, I1), np.arange(I0, I1), 1)
    cj = np.arange(0, n - 2, 2)
    J, I = np.meshgrid(cj, cj, indexing="ij")
    inside = (J >= I0) & (J + 2 <= I1) & (I >= I0) & (I + 2 <= I1)
    coarse_j = J[~inside]
    coarse_i = I[~inside]
    a = vid[coarse_j, coarse_i]
    b = vid[coarse_j, coarse_i + 2]
    cc = vid[coarse_j + 2, coarse_i + 2]
    d = vid[coarse_j + 2, coarse_i]
    ok = (a >= 0) & (b >= 0) & (cc >= 0) & (d >= 0)
    a, b, cc, d = a[ok], b[ok], cc[ok], d[ok]
    za, zb, zc, zd = verts[a, 2], verts[b, 2], verts[cc, 2], verts[d, 2]
    diag = np.abs(za - zc) <= np.abs(zb - zd)
    t1 = np.where(diag[:, None], np.stack([a, d, cc], 1), np.stack([a, d, b], 1))
    t2 = np.where(diag[:, None], np.stack([a, cc, b], 1), np.stack([b, d, cc], 1))
    coarse = np.concatenate([t1, t2])
    tris = np.concatenate([fine, coarse]).astype(np.int32)
    # winding: make every face point up
    p0, p1, p2 = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
    nzv = np.cross(p1 - p0, p2 - p0)[:, 2]
    flip = nzv < 0
    tris[flip] = tris[flip][:, ::-1]
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.ravel())
    me.loops.add(len(tris) * 3)
    me.loops.foreach_set("vertex_index", tris.ravel())
    me.polygons.add(len(tris))
    me.polygons.foreach_set("loop_start", np.arange(0, len(tris) * 3, 3, dtype=np.int32))
    try:
        me.polygons.foreach_set("loop_total", np.full(len(tris), 3, np.int32))
    except Exception:
        pass
    me.update(calc_edges=True)
    # per-face colour: mean of the corner colours + facet jitter
    vc = colours[jj, ii]
    fc = (vc[tris[:, 0]] + vc[tris[:, 1]] + vc[tris[:, 2]]) / 3.0
    hf = hash01(np.arange(len(tris)), salt=77) * 2 - 1
    fc = fc * (1.0 + 0.015 * hf)[:, None] ** 2.2
    at = me.attributes.new("Col", "FLOAT_COLOR", "FACE")
    rgba = np.ones((len(tris), 4), np.float32)
    rgba[:, :3] = np.clip(fc, 0, 1)
    at.data.foreach_set("color", rgba.ravel())
    try:
        me.shade_flat()
    except AttributeError:
        pass
    me.materials.append(make_material("M1_Terrain", "terrain"))
    log("terrain mesh: %d verts, %d tris" % (len(verts), len(tris)))
    return me


def terrain_colours(D):
    """linear colour per grid sample from the soft material weights."""
    H = D["H"]
    w = {k[2:]: D[k] for k in D.files if k.startswith("w_")}
    nz = Noise(SEED + 9)
    c = -HALF + SPP * (np.arange(NF) + 0.5)
    X = np.broadcast_to(c[None, :], (NF, NF))
    Y = np.broadcast_to(-c[:, None], (NF, NF))
    L = lambda k: lin(PAL[k])[None, None, :]
    col = np.broadcast_to(L("meadow"), H.shape + (3,)).copy()
    col = col + (L("dry") - col) * w["dry"][..., None]
    col = col + (L("turf") - col) * w["turf"][..., None]
    col = col + (L("forest_floor") - col) * w["forest"][..., None]
    col = col + (L("path") - col) * (w["path"][..., None] * 0.85)
    col = col + (L("scree") - col) * w["scree"][..., None]
    heath = lin((118, 92, 96))[None, None, :]
    rr = np.hypot(X, Y)
    col = col + (heath - col) * (0.55 * np.clip(D["m_Heather"] * 1.4, 0, 1) * (rr < 2500.0))[..., None]
    col = col + (L("limestone") - col) * np.clip(w["limestone"], 0, 1)[..., None]
    col = col + (L("dark_rock") - col) * np.clip(w["rock"], 0, 1)[..., None]
    col = col + (L("mud") - col) * np.clip(w["mud"], 0, 1)[..., None]
    col = col + (L("pebbles") - col) * np.clip(w["salt"], 0, 1)[..., None]
    under = D["q"] < 1.0
    col[under] = lin((88, 92, 78))
    patch = 1.0 + 0.045 * nz.fbm(X / 75.0, Y / 75.0, 3) + 0.025 * nz.fbm(X / 22.0 + 5, Y / 22.0, 2)
    col = col * (patch[..., None] ** 2.2)
    return np.clip(col, 0, 1)


def mesh_from_arrays(name, verts, tris, col_lin, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(t) for t in tris])
    me.update()
    at = me.attributes.new("Col", "FLOAT_COLOR", "FACE")
    rgba = np.ones((len(tris), 4), np.float32)
    rgba[:, :3] = col_lin
    at.data.foreach_set("color", rgba.ravel())
    me.materials.append(mat)
    try:
        me.shade_flat()
    except AttributeError:
        pass
    return me


def water_meshes(D, coll):
    wm = make_material("M1_Water", "water")
    # the lake: polar disc over the ellipse, z 34
    pl = P2(LAKE["bearing"], LAKE["r"])
    nr, na = 14, 96
    verts = [(pl.x, pl.y, LAKE_Y)]
    for i in range(1, nr + 1):
        f = 1.12 * i / nr
        for j in range(na):
            a = TAU * j / na
            verts.append((pl.x + LAKE["ax"] * f * math.cos(a), pl.y + LAKE["ay"] * f * math.sin(a), LAKE_Y))
    tris = []
    for j in range(na):
        tris.append((0, 1 + j, 1 + (j + 1) % na))
    for i in range(1, nr):
        for j in range(na):
            a = 1 + (i - 1) * na + j
            b = 1 + (i - 1) * na + (j + 1) % na
            c = 1 + i * na + (j + 1) % na
            d = 1 + i * na + j
            tris += [(a, d, c), (a, c, b)]
    me = mesh_from_arrays("M1_Lake", verts, tris, np.tile(lin(PAL["water"]), (len(tris), 1)), wm)
    ob = bpy.data.objects.new("M1_Lake", me)
    coll.objects.link(ob)
    # the stream ribbon at its stepped levels
    sp, W = D["st_path"], D["st_W"]
    nrm = np.stack([-np.gradient(sp[:, 1]), np.gradient(sp[:, 0])], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    hw = 2.6
    verts = []
    for k in range(len(sp)):
        z = W[k] + 0.02
        verts.append((sp[k, 0] + nrm[k, 0] * hw, sp[k, 1] + nrm[k, 1] * hw, z))
        verts.append((sp[k, 0] - nrm[k, 0] * hw, sp[k, 1] - nrm[k, 1] * hw, z))
    tris = []
    for k in range(len(sp) - 1):
        a, b, c, d = 2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2
        tris += [(a, b, c), (a, c, d)]
    me = mesh_from_arrays("M1_Stream", verts, tris, np.tile(lin(PAL["water"]), (len(tris), 1)), wm)
    ob = bpy.data.objects.new("M1_Stream", me)
    coll.objects.link(ob)


def far_ring(coll):
    """render-only skybox stand-in: distant faceted ranges r 2,700-9,000 (never exported, never terrain)."""
    nz = Noise(SEED + 33)
    na, nr = 1440, 130
    rs = np.linspace(2650.0, 9000.0, nr)
    an = np.linspace(0, TAU, na, endpoint=False)
    A_, R_ = np.meshgrid(an, rs)
    X = R_ * np.sin(A_)
    Y = R_ * np.cos(A_)
    env = sstep(2650.0, 3600.0, R_) * (1.0 - 0.35 * sstep(6000.0, 9000.0, R_))
    Hh = 160.0 + env * (520.0 + 760.0 * nz.ridged(X / 1500.0, Y / 1500.0, 5)) \
        + 160.0 * nz.fbm(X / 700.0, Y / 700.0, 3)
    Hh = np.where(R_ < 2760, 100.0, Hh)
    verts = np.stack([X.ravel(), Y.ravel(), Hh.ravel()], 1)
    tris = []
    for i in range(nr - 1):
        for j in range(na):
            a = i * na + j
            b = i * na + (j + 1) % na
            c = (i + 1) * na + (j + 1) % na
            d = (i + 1) * na + j
            tris += [(a, b, c), (a, c, d)]
    tris = np.array(tris)
    cols = np.zeros((len(tris), 3))
    zc = verts[tris].mean(1)[:, 2]
    p0, p1, p2 = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
    n = np.cross(p1 - p0, p2 - p0)
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    steep = sstep(0.75, 0.55, np.abs(n[:, 2]))
    g = lin(PAL["dry"]) * 0.8 + lin(PAL["needles"]) * 0.2
    rck = lin(PAL["limestone"])
    cols[:] = g + (rck - g) * np.clip(steep + sstep(900, 1300, zc)[:, None].ravel() * 0.6, 0, 1)[:, None]
    me = mesh_from_arrays("M1_FarRing", verts, tris, cols, make_material("M1_Terrain", "terrain"))
    ob = bpy.data.objects.new("M1_FarRing", me)
    coll.objects.link(ob)


def cloud_material(name, density, colour, emission, noise_scale, lo, hi, top_fade=0.4):
    """procedural cloud volume: world-space noise x an ellipsoidal falloff of the object's own box, wispier on top.
    Soft edges with no hull silhouette (the game's version is particle sheets; this predicts their read)."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.name = "Vol"
    vol.inputs["Color"].default_value = (*lin(colour), 1.0)
    vol.inputs["Anisotropy"].default_value = 0.3
    vol.inputs["Emission Color"].default_value = (*lin(colour), 1.0)
    vol.inputs["Emission Strength"].default_value = emission
    tc = nt.nodes.new("ShaderNodeTexCoord")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = noise_scale
    nz.inputs["Detail"].default_value = 5.0
    nz.inputs["Roughness"].default_value = 0.6
    strat = nt.nodes.new("ShaderNodeVectorMath")
    strat.operation = "MULTIPLY"
    strat.inputs[1].default_value = (1.0, 1.0, 2.6)
    nt.links.new(geo.outputs["Position"], strat.inputs[0])
    nt.links.new(strat.outputs[0], nz.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = lo
    mr.inputs["From Max"].default_value = hi
    nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
    # ellipsoidal falloff from the generated (0..1 box) coordinates
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = (0.5, 0.5, 0.5)
    nt.links.new(tc.outputs["Generated"], sub.inputs[0])
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(sub.outputs[0], ln.inputs[0])
    fall = nt.nodes.new("ShaderNodeMapRange")
    fall.inputs["From Min"].default_value = 0.12
    fall.inputs["From Max"].default_value = 0.5
    fall.inputs["To Min"].default_value = 1.0
    fall.inputs["To Max"].default_value = 0.0
    fall.interpolation_type = "SMOOTHSTEP"
    nt.links.new(ln.outputs["Value"], fall.inputs["Value"])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    topf = nt.nodes.new("ShaderNodeMapRange")
    topf.inputs["From Min"].default_value = top_fade
    topf.inputs["From Max"].default_value = 1.0
    topf.inputs["To Min"].default_value = 1.0
    topf.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs[2], topf.inputs["Value"])
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    nt.links.new(mr.outputs["Result"], m1.inputs[0])
    nt.links.new(fall.outputs["Result"], m1.inputs[1])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "MULTIPLY"
    nt.links.new(m1.outputs[0], m2.inputs[0])
    nt.links.new(topf.outputs["Result"], m2.inputs[1])
    m3 = nt.nodes.new("ShaderNodeMath")
    m3.operation = "MULTIPLY"
    m3.name = "DensityScale"
    m3.inputs[1].default_value = density
    nt.links.new(m2.outputs[0], m3.inputs[0])
    nt.links.new(m3.outputs[0], vol.inputs["Density"])
    m4 = nt.nodes.new("ShaderNodeMath")          # emission follows the density (it is not scaled by it otherwise)
    m4.operation = "MULTIPLY"
    m4.name = "EmissionScale"
    m4.inputs[1].default_value = emission
    nt.links.new(m2.outputs[0], m4.inputs[0])
    nt.links.new(m4.outputs[0], vol.inputs["Emission Strength"])
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    return m


def ellipsoid(name, coll, centre, size, yaw_deg, mat, seg=24, rings=12):
    me = bpy.data.meshes.new(name)
    verts, faces = [], []
    for i in range(rings + 1):
        th = math.pi * i / rings
        for j in range(seg):
            ph = TAU * j / seg
            verts.append((math.sin(th) * math.cos(ph) * 0.5, math.sin(th) * math.sin(ph) * 0.5, math.cos(th) * 0.5))
    for i in range(rings):
        for j in range(seg):
            a = i * seg + j
            b = i * seg + (j + 1) % seg
            faces.append((a, a + seg, b + seg, b))          # outward normals: Cycles needs them to enter a volume
    me.from_pydata(verts, [], faces)
    me.update()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    ob.location = centre
    ob.scale = size
    ob.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    coll.objects.link(ob)
    return ob


def layer_material(name, density, colour, emission, noise_scale, lo, hi, zb, rb, stretch=2.6, centre=(0.0, 0.0),
                   ang=None, flip=False):
    """a cloud layer defined in world space: stratified noise x a height band x a radial band (x an optional
    bearing window). No container shape shows: the mountainsides cut the layer where they rise through it."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    N, Lk = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    vol = N.new("ShaderNodeVolumePrincipled")
    vol.name = "Vol"
    vol.inputs["Color"].default_value = (*lin(colour), 1.0)
    vol.inputs["Anisotropy"].default_value = 0.3
    vol.inputs["Emission Color"].default_value = (*lin(colour), 1.0)
    geo = N.new("ShaderNodeNewGeometry")
    strat = N.new("ShaderNodeVectorMath")
    strat.operation = "MULTIPLY"
    strat.inputs[1].default_value = (1.0, 1.0, stretch)
    Lk.new(geo.outputs["Position"], strat.inputs[0])
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = noise_scale
    nz.inputs["Detail"].default_value = 5.0
    nz.inputs["Roughness"].default_value = 0.6
    Lk.new(strat.outputs[0], nz.inputs["Vector"])

    def mrange(src, a, b, c, d, smooth=True):
        n = N.new("ShaderNodeMapRange")
        n.inputs["From Min"].default_value = a
        n.inputs["From Max"].default_value = b
        n.inputs["To Min"].default_value = c
        n.inputs["To Max"].default_value = d
        if smooth:
            n.interpolation_type = "SMOOTHSTEP"
        Lk.new(src, n.inputs["Value"])
        return n.outputs["Result"]

    def mul(a, b):
        n = N.new("ShaderNodeMath")
        n.operation = "MULTIPLY"
        Lk.new(a, n.inputs[0])
        if isinstance(b, float):
            n.inputs[1].default_value = b
        else:
            Lk.new(b, n.inputs[1])
        return n.outputs[0]

    sep = N.new("ShaderNodeSeparateXYZ")
    Lk.new(geo.outputs["Position"], sep.inputs[0])
    flat = N.new("ShaderNodeVectorMath")
    flat.operation = "SUBTRACT"
    flat.inputs[1].default_value = (centre[0], centre[1], 0.0)
    Lk.new(geo.outputs["Position"], flat.inputs[0])
    flat2 = N.new("ShaderNodeVectorMath")
    flat2.operation = "MULTIPLY"
    flat2.inputs[1].default_value = (1.0, 1.0, 0.0)
    Lk.new(flat.outputs[0], flat2.inputs[0])
    ln = N.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    Lk.new(flat2.outputs[0], ln.inputs[0])
    z0, z1, z2, z3 = zb
    r0, r1, r2, r3 = rb
    zt = mul(mrange(sep.outputs[2], z0, z1, 0.0, 1.0), mrange(sep.outputs[2], z2, z3, 1.0, 0.0))
    rt = mul(mrange(ln.outputs["Value"], r0, r1, 0.0, 1.0), mrange(ln.outputs["Value"], r2, r3, 1.0, 0.0))
    dens = mul(mul(mrange(nz.outputs["Fac"], lo, hi, 0.0, 1.0, smooth=False), zt), rt)
    if ang is not None:      # a bearing window (deg, -180..180; flip=True measures from the south instead)
        a0, a1, a2, a3 = ang
        at = N.new("ShaderNodeMath")
        at.operation = "ARCTAN2"
        src = sep
        if flip:
            fl = N.new("ShaderNodeVectorMath")
            fl.operation = "MULTIPLY"
            fl.inputs[1].default_value = (-1.0, -1.0, 1.0)
            Lk.new(geo.outputs["Position"], fl.inputs[0])
            src = N.new("ShaderNodeSeparateXYZ")
            Lk.new(fl.outputs[0], src.inputs[0])
        Lk.new(src.outputs[0], at.inputs[0])
        Lk.new(src.outputs[1], at.inputs[1])
        deg = mul(at.outputs[0], 57.2958)
        dens = mul(dens, mul(mrange(deg, a0, a1, 0.0, 1.0), mrange(deg, a2, a3, 1.0, 0.0)))
    d1 = N.new("ShaderNodeMath")
    d1.operation = "MULTIPLY"
    d1.name = "DensityScale"
    d1.inputs[1].default_value = density
    Lk.new(dens, d1.inputs[0])
    Lk.new(d1.outputs[0], vol.inputs["Density"])
    e1 = N.new("ShaderNodeMath")
    e1.operation = "MULTIPLY"
    e1.name = "EmissionScale"
    e1.inputs[1].default_value = emission
    Lk.new(dens, e1.inputs[0])
    Lk.new(e1.outputs[0], vol.inputs["Emission Strength"])
    Lk.new(vol.outputs[0], out.inputs["Volume"])
    return m


def slab(name, coll, x0, x1, y0, y1, z0, z1, mat):
    """a closed box container (outward normals) for a world-space cloud layer."""
    mb = MB()
    box(mb, (x0, y0, z0), (x1, y1, z1), (255, 255, 255))
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.v, [], mb.f)
    me.update()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def clouds(coll, H):
    """the low cloud bank on the flanks (brief 1.7: y 250-400, colour 222,226,226), a higher veil on the massif,
    wisps across the peak's middle, and fair-weather cumulus far off."""
    rng = random.Random(SEED + 77)
    obs = []
    # all round except the south, where the view from the horn's mouth must keep the peak (T2 @49.9 s)
    bank = layer_material("M1_CloudBank", 0.024, PAL["mist"], 0.02, 0.0017, 0.46, 0.62,
                          zb=(200.0, 255.0, 330.0, 420.0), rb=(1150.0, 1450.0, 2350.0, 2600.0),
                          ang=(-158.0, -140.0, 140.0, 158.0))
    obs.append(slab("M1_CloudBank_layer", coll, -2700, 2700, -2700, 2700, 190.0, 430.0, bank))
    south = layer_material("M1_CloudBankSouth", 0.016, PAL["mist"], 0.014, 0.0017, 0.5, 0.64,
                           zb=(210.0, 240.0, 275.0, 310.0), rb=(1150.0, 1450.0, 2350.0, 2600.0),
                           ang=(-40.0, -22.0, 22.0, 40.0), flip=True)
    obs.append(slab("M1_CloudBank_south", coll, -2700, 2700, -2700, 0, 200.0, 320.0, south))
    veil = layer_material("M1_CloudVeil", 0.025, PAL["mist"], 0.02, 0.0014, 0.5, 0.64,
                          zb=(620.0, 690.0, 760.0, 860.0), rb=(1900.0, 2150.0, 2550.0, 2750.0))
    obs.append(slab("M1_CloudBank_veil", coll, -2800, 2800, -2800, 2800, 610.0, 870.0, veil))
    pk = P2(*PEAK)
    wisp = layer_material("M1_CloudWisp", 0.02, PAL["mist"], 0.018, 0.0035, 0.48, 0.62, stretch=4.0,
                          zb=(400.0, 430.0, 480.0, 520.0), rb=(0.0, 1.0, 230.0, 330.0), centre=(pk.x, pk.y))
    obs.append(slab("M1_CloudBank_peak", coll, pk.x - 340, pk.x + 340, pk.y - 340, pk.y + 340, 395.0, 525.0, wisp))
    high = cloud_material("M1_CloudHigh", 0.05, PAL["cloud"], 0.02, 0.0034, 0.46, 0.62, top_fade=0.8)
    for i in range(14):
        b = rng.uniform(0, 360)
        p = P3(b, rng.uniform(4800, 8500), rng.uniform(2300, 3100))
        s_ = rng.uniform(900, 1700)
        obs.append(ellipsoid("M1_Cumulus_%d" % i, coll, p, (s_, s_ * rng.uniform(0.6, 0.9), s_ * 0.45),
                             rng.uniform(0, 360), high))
    log("  clouds: %d volumes" % len(obs))
    return obs


def scatter_points(D, mask_key, spacing, k, rng_seed, ymax=1e9, rmax=2700.0, rmin=0.0):
    """jittered-grid candidates accepted by the mask density; returns (x, y, z) in Blender space."""
    m = D[mask_key]
    H = D["H"]
    rng = np.random.default_rng(rng_seed)
    g = np.arange(-rmax, rmax, spacing)
    GX, GY = np.meshgrid(g, g)
    GX = GX.ravel() + rng.uniform(-0.45, 0.45, GX.size) * spacing
    GY = GY.ravel() + rng.uniform(-0.45, 0.45, GY.size) * spacing
    rr = np.hypot(GX, GY)
    ok = (rr < rmax) & (rr > rmin)
    GX, GY = GX[ok], GY[ok]
    i = np.clip(((GX + HALF) / SPP - 0.5).astype(int), 0, NF - 1)
    j = np.clip(((HALF - GY) / SPP - 0.5).astype(int), 0, NF - 1)
    dens = m[j, i] * k
    keep = rng.random(dens.size) < dens
    GX, GY, i, j = GX[keep], GY[keep], i[keep], j[keep]
    Z = H[j, i]
    ok = Z < ymax
    return np.stack([GX[ok], GY[ok], Z[ok]], 1)


GN_CACHE = {}


def instancer(name, src_obj, pts, coll, rot_z=None, scale=None, tilt=0.0, seed=0):
    """a point mesh + Geometry Nodes 'Instance on Points' of src_obj, per-point rotation and scale."""
    if len(pts) == 0:
        return None
    rng = np.random.default_rng(seed)
    me = bpy.data.meshes.new(name + "_pts")
    me.vertices.add(len(pts))
    me.vertices.foreach_set("co", np.asarray(pts, np.float32).ravel())
    if rot_z is None:
        rot_z = rng.uniform(0, TAU, len(pts))
    rot = np.zeros((len(pts), 3), np.float32)
    rot[:, 2] = rot_z
    if tilt:
        rot[:, 0] = rng.uniform(-tilt, tilt, len(pts))
        rot[:, 1] = rng.uniform(-tilt, tilt, len(pts))
    if scale is None:
        scale = np.ones(len(pts))
    scl = np.repeat(np.asarray(scale, np.float32)[:, None], 3, 1)
    a = me.attributes.new("rot", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", rot.ravel())
    a = me.attributes.new("scl", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", scl.ravel())
    me.update()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ng = bpy.data.node_groups.new("GN_" + name, "GeometryNodeTree")
    ng.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N, Lk = ng.nodes, ng.links
    gi, go = N.new("NodeGroupInput"), N.new("NodeGroupOutput")
    m2p = N.new("GeometryNodeMeshToPoints")
    inst = N.new("GeometryNodeInstanceOnPoints")
    oi = N.new("GeometryNodeObjectInfo")
    oi.inputs["Object"].default_value = src_obj
    oi.inputs["As Instance"].default_value = True
    ra = N.new("GeometryNodeInputNamedAttribute")
    ra.data_type = "FLOAT_VECTOR"
    ra.inputs["Name"].default_value = "rot"
    sa = N.new("GeometryNodeInputNamedAttribute")
    sa.data_type = "FLOAT_VECTOR"
    sa.inputs["Name"].default_value = "scl"
    e2r = N.new("FunctionNodeEulerToRotation")
    Lk.new(gi.outputs[0], m2p.inputs["Mesh"])
    Lk.new(m2p.outputs[0], inst.inputs["Points"])
    Lk.new(oi.outputs["Geometry"], inst.inputs["Instance"])
    Lk.new(ra.outputs["Attribute"], e2r.inputs[0])
    Lk.new(e2r.outputs[0], inst.inputs["Rotation"])
    Lk.new(sa.outputs["Attribute"], inst.inputs["Scale"])
    Lk.new(inst.outputs[0], go.inputs[0])
    mod = ob.modifiers.new("Scatter", "NODES")
    mod.node_group = ng
    return ob


def place(asset, pos, yaw_deg, coll, name=None):
    ob = bpy.data.objects.new(name or asset.name, asset.render_obj.data)
    ob.location = pos
    ob.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    coll.objects.link(ob)
    return ob


def scene_stage(A):
    D = np.load(os.path.join(WORK, "field.npz"))
    with open(os.path.join(WORK, "layout.json")) as f:
        L = json.load(f)
    sc = bpy.context.scene
    for ob in list(sc.collection.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    cols = {}
    for nm in ("M1_Sources", "M1_Terrain", "M1_Heart", "M1_Sites", "M1_Scatter", "M1_Sky", "M1_Figures"):
        c = bpy.data.collections.new(nm)
        sc.collection.children.link(c)
        cols[nm] = c
    for a in A.values():
        render_object(a, cols["M1_Sources"])
    log("scene: terrain")
    me = terrain_mesh(D["H"], terrain_colours(D))
    cols["M1_Terrain"].objects.link(bpy.data.objects.new("M1_Terrain", me))
    water_meshes(D, cols["M1_Terrain"])
    far_ring(cols["M1_Sky"])
    log("scene: landmarks")
    for it in L:
        a = A.get(it["asset"])
        if a is None:
            continue
        coll = cols["M1_Heart"] if it["asset"] in ("M1_Horn", "M1_Platform", "M1_Plinth", "M1_PlateTubeRim") or \
            it["asset"].startswith(("M1_Spoke", "M1_Teardrop")) else cols["M1_Sites"]
        place(a, it["pos"], it["yaw"], coll)
        if it["asset"] == "M1_Plinth":
            place(A["M1_TubeShadow"], it["pos"], it["yaw"], coll)
            fig = A["M1_Tribute_%d" % (it["index"] % 3)]
            x, y, z = it["pos"]
            place(fig, (x, y, z + 1.6), it["yaw"] + 180.0 + random.Random(it["index"]).uniform(-25, 25),
                  cols["M1_Figures"])
    # the horn's interior is lit on set (T2 @49.9 s shows navy walls and gold battens, not a black hole): a soft
    # warm fill under the apex, render-only (the game needs its own light inside the horn)
    li = bpy.data.lights.new("M1_HornFill", "POINT")
    li.energy = 12000.0
    li.shadow_soft_size = 6.0
    li.color = (1.0, 0.93, 0.84)
    lo = bpy.data.objects.new("M1_HornFill", li)
    lo.location = (0.0, 0.0, DECK_Y + 24.0)
    cols["M1_Heart"].objects.link(lo)
    log("scene: scatter")
    scatter(D, A, cols["M1_Scatter"])
    log("scene: sky")
    clouds(cols["M1_Sky"], D["H"])
    setup_render(sc)
    path = os.path.join(WORK, "Map1_scene.blend")
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=False)
    log("scene saved", path, "%.0f MB" % (os.path.getsize(path) / 1e6))


def scatter(D, A, coll):
    S = 0
    # North Wood and ridge-foot conifers (firs and pines), forest model density as ArenaV3 7.5
    con = scatter_points(D, "m_Conifer", 15.0, 1.0, SEED + 1, ymax=560.0)
    rng = np.random.default_rng(SEED + 2)
    kind = rng.random(len(con))
    groups = [("M1_Fir_A", kind < 0.25), ("M1_Fir_B", (kind >= 0.25) & (kind < 0.5)),
              ("M1_Fir_C", (kind >= 0.5) & (kind < 0.68)), ("M1_Pine_A", (kind >= 0.68) & (kind < 0.85)),
              ("M1_Pine_B", kind >= 0.85)]
    for nm, msk in groups:
        p = con[msk]
        p[:, 2] -= 0.4
        instancer("SC_" + nm, A[nm].render_obj, p, coll, scale=rng.uniform(0.82, 1.15, len(p)), seed=S)
        S += 1
    log("  conifers %d" % len(con))
    bro = scatter_points(D, "m_Broadleaf", 10.0, 1.15, SEED + 3, ymax=400.0)
    kind = rng.random(len(bro))
    for nm, msk in (("M1_Beech_A", kind < 0.55), ("M1_Beech_B", kind >= 0.55)):
        p = bro[msk]
        p[:, 2] -= 0.4
        instancer("SC_" + nm, A[nm].render_obj, p, coll, scale=rng.uniform(0.8, 1.2, len(p)), seed=S)
        S += 1
    log("  broadleaf %d" % len(bro))
    gor = scatter_points(D, "m_Gorse", 7.0, 0.7, SEED + 4, ymax=450.0)
    kind = rng.random(len(gor))
    for nm, msk in (("M1_Gorse_A", kind < 0.5), ("M1_Gorse_B", kind >= 0.5)):
        p = gor[msk]
        p[:, 2] -= 0.3
        instancer("SC_" + nm, A[nm].render_obj, p, coll, scale=rng.uniform(0.8, 1.4, len(p)), seed=S)
        S += 1
    log("  gorse %d" % len(gor))
    hea = scatter_points(D, "m_Heather", 6.0, 0.8, SEED + 5, ymax=700.0)
    kind = rng.random(len(hea))
    for nm, msk in (("M1_Heather_A", kind < 0.5), ("M1_Heather_B", kind >= 0.5)):
        p = hea[msk]
        p[:, 2] -= 0.3
        instancer("SC_" + nm, A[nm].render_obj, p, coll, scale=rng.uniform(0.8, 1.6, len(p)), tilt=0.12, seed=S)
        S += 1
    log("  heather %d" % len(hea))
    bou = scatter_points(D, "m_Boulders", 9.0, 0.5, SEED + 6, ymax=700.0)
    kind = rng.random(len(bou))
    for nm, msk in (("M1_Boulder_A", kind < 0.5), ("M1_Boulder_B", (kind >= 0.5) & (kind < 0.85)),
                    ("M1_Boulder_C", kind >= 0.85)):
        p = bou[msk]
        instancer("SC_" + nm, A[nm].render_obj, p, coll, scale=rng.uniform(0.7, 1.4, len(p)), tilt=0.2, seed=S)
        S += 1
    log("  boulders %d" % len(bou))
    crg = scatter_points(D, "m_Crags", 64.0, 0.4, SEED + 7, ymax=900.0)
    kind = rng.random(len(crg))
    for nm, msk in (("M1_Crag_A", kind < 0.45), ("M1_Crag_B", (kind >= 0.45) & (kind < 0.8)),
                    ("M1_Crag_C", kind >= 0.8)):
        p = crg[msk]
        p[:, 2] -= 12.0
        instancer("SC_" + nm, A[nm].render_obj, p, coll, scale=rng.uniform(0.6, 1.1, len(p)), tilt=0.12, seed=S)
        S += 1
    log("  crags %d" % len(crg))
    wf = scatter_points(D, "m_Wildflowers", 3.6, 1.0, SEED + 8, ymax=200.0, rmax=1300.0)
    instancer("SC_Wildflowers", A["M1_Wildflowers_A"].render_obj, wf, coll, scale=rng.uniform(0.7, 1.3, len(wf)),
              seed=S)
    tg = scatter_points(D, "m_TallGrass", 4.5, 0.8, SEED + 9, ymax=400.0)
    instancer("SC_TallGrass", A["M1_TallGrass_A"].render_obj, tg, coll, scale=rng.uniform(0.8, 1.2, len(tg)), seed=S + 1)
    log("  wildflowers %d, tall grass %d" % (len(wf), len(tg)))
    # daisies and dandelions in the turf round the tubes: tiny wildflower clumps
    dz = []
    r2 = np.random.default_rng(SEED + 10)
    for k in range(260):
        b = r2.uniform(0, 360)
        r = r2.uniform(55, 148)
        p = P2(b, r)
        dz.append((p.x, p.y, ground_from(D, p.x, p.y) - 0.35))
    instancer("SC_TurfFlowers", A["M1_Wildflowers_A"].render_obj, dz, coll, scale=r2.uniform(0.35, 0.6, len(dz)),
              seed=S + 2)


def ground_from(D, x, y):
    H = D["H"]
    i = int(np.clip((x + HALF) / SPP - 0.5, 0, NF - 1))
    j = int(np.clip((HALF - y) / SPP - 0.5, 0, NF - 1))
    return float(H[j, i])


# ================================================================================================ render setup
def setup_render(sc):
    sc.render.engine = "CYCLES"
    try:
        cp = bpy.context.preferences.addons["cycles"].preferences
        cp.compute_device_type = "OPTIX"
        cp.get_devices()
        for d in cp.devices:
            d.use = d.type == "OPTIX"
        sc.cycles.device = "GPU"
    except Exception as e:
        log("GPU setup failed, CPU render:", e)
    c = sc.cycles
    c.samples = SAMPLES
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = True
    try:
        c.denoiser = "OPTIX"
    except TypeError:
        pass
    c.max_bounces = 5
    c.diffuse_bounces = 2
    c.glossy_bounces = 2
    c.transmission_bounces = 2
    c.volume_bounces = 1
    c.transparent_max_bounces = 8
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.volume_step_rate = 4.0
    c.volume_max_steps = 256
    r = sc.render
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    set_view(sc)
    # world: gradient sky (zenith #6892ba -> horizon #b4c8d6) plus a soft sun glow seen by the camera only;
    # lighting rays see the plain gradient at SkyLight strength, camera rays at SkyCam strength
    w = bpy.data.worlds.new("M1_Sky")
    try:
        w.use_nodes = True
    except Exception:
        pass
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.name = "SkyRamp"
    cr = ramp.color_ramp
    cr.elements[0].position = 0.5
    cr.elements[0].color = (*lin((150, 160, 160)), 1.0)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (*lin(PAL["sky_zenith"]), 1.0)
    e = cr.elements.new(0.505)
    e.color = (*lin(PAL["sky_horizon"]), 1.0)
    e = cr.elements.new(0.66)
    e.color = (*lin((146, 176, 204)), 1.0)
    mapz = nt.nodes.new("ShaderNodeMapRange")
    mapz.inputs["From Min"].default_value = -1.0
    mapz.inputs["From Max"].default_value = 1.0
    mapz.inputs["To Min"].default_value = 0.0
    mapz.inputs["To Max"].default_value = 1.0
    nt.links.new(sep.outputs[2], mapz.inputs["Value"])
    nt.links.new(mapz.outputs["Result"], ramp.inputs["Fac"])
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.name = "SunDot"
    nt.links.new(tc.outputs["Generated"], dot.inputs[0])
    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = "MAXIMUM"
    mx.inputs[1].default_value = 0.0
    nt.links.new(dot.outputs["Value"], mx.inputs[0])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    nt.links.new(mx.outputs[0], pw.inputs[0])
    pw.inputs[1].default_value = 260.0
    pw2 = nt.nodes.new("ShaderNodeMath")
    pw2.operation = "POWER"
    nt.links.new(mx.outputs[0], pw2.inputs[0])
    pw2.inputs[1].default_value = 9000.0
    gl = nt.nodes.new("ShaderNodeMath")
    gl.operation = "MULTIPLY_ADD"
    gl.name = "SunGlow"
    nt.links.new(pw.outputs[0], gl.inputs[0])
    gl.inputs[1].default_value = 0.3
    pw2m = nt.nodes.new("ShaderNodeMath")
    pw2m.operation = "MULTIPLY"
    pw2m.inputs[1].default_value = 6.0
    nt.links.new(pw2.outputs[0], pw2m.inputs[0])
    nt.links.new(pw2m.outputs[0], gl.inputs[2])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(gl.outputs[0], comb.inputs[0])
    gl2 = nt.nodes.new("ShaderNodeMath")
    gl2.operation = "MULTIPLY"
    gl2.inputs[1].default_value = 0.96
    nt.links.new(gl.outputs[0], gl2.inputs[0])
    nt.links.new(gl2.outputs[0], comb.inputs[1])
    gl3 = nt.nodes.new("ShaderNodeMath")
    gl3.operation = "MULTIPLY"
    gl3.inputs[1].default_value = 0.86
    nt.links.new(gl.outputs[0], gl3.inputs[0])
    nt.links.new(gl3.outputs[0], comb.inputs[2])
    add = nt.nodes.new("ShaderNodeVectorMath")
    add.operation = "ADD"
    nt.links.new(ramp.outputs["Color"], add.inputs[0])
    nt.links.new(comb.outputs[0], add.inputs[1])
    lp = nt.nodes.new("ShaderNodeLightPath")
    cam_v = nt.nodes.new("ShaderNodeValue")
    cam_v.name = "SkyCam"
    cam_v.outputs[0].default_value = 1.0
    light_v = nt.nodes.new("ShaderNodeValue")
    light_v.name = "SkyLight"
    light_v.outputs[0].default_value = 1.0
    st = nt.nodes.new("ShaderNodeMix")
    st.data_type = "FLOAT"
    sock = lambda node, io, name, typ: [s for s in getattr(node, io) if s.name == name and s.type == typ][0]
    nt.links.new(lp.outputs["Is Camera Ray"], sock(st, "inputs", "Factor", "VALUE"))
    nt.links.new(light_v.outputs[0], sock(st, "inputs", "A", "VALUE"))
    nt.links.new(cam_v.outputs[0], sock(st, "inputs", "B", "VALUE"))
    sel = nt.nodes.new("ShaderNodeMix")
    sel.data_type = "RGBA"
    nt.links.new(lp.outputs["Is Camera Ray"], sock(sel, "inputs", "Factor", "VALUE"))
    nt.links.new(ramp.outputs["Color"], sock(sel, "inputs", "A", "RGBA"))
    nt.links.new(add.outputs[0], sock(sel, "inputs", "B", "RGBA"))
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.name = "SkyBG"
    nt.links.new(sock(sel, "outputs", "Result", "RGBA"), bg.inputs["Color"])
    nt.links.new(sock(st, "outputs", "Result", "VALUE"), bg.inputs["Strength"])
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs[0], out.inputs[0])
    sc.world = w
    sun = bpy.data.lights.new("M1_Sun", "SUN")
    sun.energy = 5.0
    sun.angle = math.radians(0.6)
    sun.color = (1.0, 0.97, 0.92)
    so = bpy.data.objects.new("M1_Sun", sun)
    sc.collection.objects.link(so)
    cam = bpy.data.objects.new("M1_Cam", bpy.data.cameras.new("M1_Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam


# ================================================================================================ shots
# Each shot: camera (Blender xyz), yaw/pitch (deg; yaw is a bearing), vertical FOV, sun bearing/elevation, exposure,
# fog distance, reference frame (compare stage only), and the reference size (our render keeps its aspect).
SHOTS = {
    "overview_aerial": dict(cam=(0.0, -160.0, 9800.0), yaw=0.0, pitch=-89.0, vfov=33.0, res=(1800, 1800),
                            sun=(135.0, 52.0), exposure=0.0, fog=60000.0, fogmax=0.0, no_clouds=True, ref=None),
    "birdseye_34": dict(cam=tuple(P3(160.0, 3900.0, 2500.0)), yaw=340.0, pitch=-30.0, vfov=38.0, res=(1920, 1080),
                        sun=(120.0, 40.0), exposure=0.0, fog=7000.0, ref=None),
    "match_owner_t1_1.7s": dict(cam=tuple(P3(300.0, 330.0, 118.0)), yaw=120.0, pitch=-4.0, vfov=38.0,
                              res=(1600, 708), sun=(96.0, 42.0), exposure=0.0, fog=7500.0,
                              ref="owner/map1_green_land_owner_frame.png",
                              label="OWNER FRAME (OFFICIAL TRAILER 1 @1.7 S)"),
    "match_t1_40.2s": dict(cam=tuple(P3(60.0, 150.0, 47.8)), yaw=240.0, pitch=13.0, vfov=48.0, res=(1600, 686),
                         sun=(228.0, 19.0), exposure=0.0, fog=7500.0, ref="trailer/trailer1_40.2s.png",
                         label="OFFICIAL TRAILER 1 @40.2 S"),
    "match_t2_49.9s": dict(cam=tuple(P3(0.0, 3.0, 57.0)), yaw=180.0, pitch=4.0, vfov=38.0, res=(1600, 684),
                         sun=(150.0, 55.0), exposure=0.0, fog=7500.0, horn_fill=22000.0, ref="trailer/trailer2_49.9s.png",
                         label="OFFICIAL TRAILER 2 @49.9 S"),
    "match_t1_77.7s": dict(cam=tuple(P3(352.0, 128.0, 54.0)), yaw=172.0, pitch=-2.0, vfov=46.0, res=(1600, 686),
                         sun=(178.0, 23.0), exposure=0.0, fog=6500.0, ref="trailer/trailer1_77.7s.png",
                         label="OFFICIAL TRAILER 1 @77.7 S"),
    "match_fe_26.9s": dict(cam=tuple(P3(200.0, 1250.0, 700.0)), yaw=18.0, pitch=-26.0, vfov=34.0, res=(1600, 900),
                         sun=(150.0, 40.0), exposure=0.0, fog=3600.0, ref="trailer/fanedit_26.9s.png",
                         label="OFFICIAL FAN EDIT TRAILER @26.9 S", mist=True),
    "match_t2_128.7s": dict(cam=None, along_stream=0.36, height=2.6, side=9.0, pitch=1.0, vfov=44.0, res=(1600, 684),
                          sun=(150.0, 50.0), exposure=0.0, fog=7500.0, ref="trailer/trailer2_128.7s.png",
                          label="OFFICIAL TRAILER 2 @128.7 S"),
}


def apply_shot(sc, name, S, D=None):
    cam = sc.camera
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(S["vfov"])
    cam.data.clip_start = 0.3
    cam.data.clip_end = 40000.0
    if S.get("cam") is None:
        sp, sL = D["st_path"], D["st_sL"]
        t = S["along_stream"] * sL[-1]
        k = int(np.searchsorted(sL, t))
        p = sp[k]
        q = sp[min(k + 12, len(sp) - 1)]
        dxy = (q - p) / max(1e-6, float(np.hypot(*(q - p))))
        side = S.get("side", 0.0)
        p = p + np.array([dxy[1], -dxy[0]]) * side                   # step sideways onto the bank
        z = (ground_from(D, p[0], p[1]) if side else float(D["st_W"][k])) + S["height"]
        loc = Vector((p[0], p[1], z))
        yaw = math.degrees(math.atan2(q[0] - p[0], q[1] - p[1]))
    else:
        loc = Vector(S["cam"])
        yaw = S["yaw"]
    pitch = S["pitch"]
    d = Vector((math.sin(math.radians(yaw)) * math.cos(math.radians(pitch)),
                math.cos(math.radians(yaw)) * math.cos(math.radians(pitch)), math.sin(math.radians(pitch))))
    cam.location = loc
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    w, h = S["res"]
    sc.render.resolution_x = int(w * RES_SCALE)
    sc.render.resolution_y = int(h * RES_SCALE)
    sb, se = S["sun"]
    sd = Vector((math.sin(math.radians(sb)) * math.cos(math.radians(se)),
                 math.cos(math.radians(sb)) * math.cos(math.radians(se)), math.sin(math.radians(se))))
    sun = bpy.data.objects["M1_Sun"]
    sun.rotation_euler = sd.to_track_quat("Z", "Y").to_euler()
    nt = sc.world.node_tree
    nt.nodes["SunDot"].inputs[1].default_value = sd
    sc.view_settings.exposure = S["exposure"]
    fg = bpy.data.node_groups["M1_Fog"]
    fg.nodes["FogDist"].outputs[0].default_value = S["fog"]
    fg.nodes["FogMax"].outputs[0].default_value = S.get("fogmax", 0.92)
    fg.nodes["CamZ"].outputs[0].default_value = loc.z
    sun_obj = bpy.data.objects["M1_Sun"]
    sun_obj.data.energy = S.get("sun_strength", 5.0)      # Cycles: albedo x S x cos / pi -> ~1.1 x albedo at 42 deg
    fill = bpy.data.objects.get("M1_HornFill")
    if fill is not None:
        fill.data.energy = S.get("horn_fill", 12000.0)
    nt.nodes["SkyLight"].outputs[0].default_value = S.get("sky_light", 1.0)
    nt.nodes["SkyCam"].outputs[0].default_value = S.get("sky_cam", 1.0)
    for ob in bpy.data.objects:
        if ob.name.startswith("M1_CloudMist"):
            ob.hide_render = not S.get("mist", False)
        if ob.name == "M1_FarRing":
            ob.hide_render = S.get("no_far", False)
        if ob.name.startswith(("M1_CloudBank", "M1_Cumulus")):
            ob.hide_render = S.get("no_clouds", False) or os.environ.get("MAP1_NOCLOUDS") == "1"
    return loc


def mist_layer(sc):
    """the FE @26.9 s look: a fog deck just above the drone over the north half (render-only)."""
    if bpy.data.objects.get("M1_CloudMist_0"):
        return
    coll = bpy.data.collections.get("M1_Sky")
    mat = layer_material("M1_CloudMist", 0.02, PAL["mist"], 0.03, 0.0016, 0.3, 0.5,
                         zb=(700.0, 760.0, 900.0, 980.0), rb=(-1.0, 0.0, 2300.0, 2700.0), centre=(0.0, -400.0))
    slab("M1_CloudMist_0", coll, -2700, 2700, -800, 2700, 690.0, 990.0, mat)


def render_stage():
    sc = bpy.context.scene
    if bpy.data.objects.get("M1_Terrain") is None:
        path = os.path.join(WORK, "Map1_scene.blend")
        log("render: loading", path)
        bpy.ops.wm.open_mainfile(filepath=path)
        sc = bpy.context.scene
        setup_gpu_only(sc)
    D = np.load(os.path.join(WORK, "field.npz"))
    mist_layer(sc)
    done = []
    for name, S in SHOTS.items():
        if SHOT_FILTER and name not in SHOT_FILTER:
            continue
        apply_shot(sc, name, S, D)
        path = os.path.join(PREV, name + ".png")
        sc.render.filepath = path
        t = time.time()
        bpy.ops.render.render(write_still=True)
        log("RENDER %s (%.0fs)" % (path, time.time() - t))
        done.append(path)
    return done


def set_view(sc):
    """Standard view transform: a painted tone under unit light shows as itself, so the palette can be checked
    directly in the renders (AgX would desaturate and shift it)."""
    try:
        sc.display_settings.display_device = "sRGB"
    except TypeError:
        pass
    try:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
    except TypeError as e:
        log("WARNING view transform", e)
    log("view transform:", sc.view_settings.view_transform, sc.view_settings.look)


def setup_gpu_only(sc):
    try:
        cp = bpy.context.preferences.addons["cycles"].preferences
        cp.compute_device_type = "OPTIX"
        cp.get_devices()
        for d in cp.devices:
            d.use = d.type == "OPTIX"
        sc.cycles.device = "GPU"
    except Exception as e:
        log("GPU setup failed:", e)
    sc.cycles.samples = SAMPLES
    set_view(sc)


# ================================================================================================ STAGE: compare
FONT = {
    "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    "C": [" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"],
    "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    "G": [" ####", "#    ", "#    ", "#  ##", "#   #", "#   #", " ####"],
    "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "I": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
    "J": ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "],
    "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
    "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
    "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "],
    "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
    "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
    "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
    "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
    "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
    ".": ["     ", "     ", "     ", "     ", "     ", " ##  ", " ##  "],
    ",": ["     ", "     ", "     ", "     ", "     ", "  #  ", " #   "],
    ":": ["     ", " ##  ", " ##  ", "     ", " ##  ", " ##  ", "     "],
    "-": ["     ", "     ", "     ", "#####", "     ", "     ", "     "],
    "(": ["   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # "],
    ")": [" #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   "],
    "@": [" ### ", "#   #", "# ###", "# # #", "# ###", "#    ", " ####"],
    "/": ["    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "],
    "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    "=": ["     ", "     ", "#####", "     ", "#####", "     ", "     "],
    "'": ["  #  ", "  #  ", " #   ", "     ", "     ", "     ", "     "],
    " ": ["     "] * 7,
}


def draw_text(img, x, y, text, scale=3, col=(255, 255, 255)):
    for ch in text.upper():
        g = FONT.get(ch, FONT[" "])
        for r, row in enumerate(g):
            for cidx, px in enumerate(row):
                if px == "#":
                    y0 = y + r * scale
                    x0 = x + cidx * scale
                    if 0 <= y0 < img.shape[0] - scale and 0 <= x0 < img.shape[1] - scale:
                        img[y0:y0 + scale, x0:x0 + scale] = col
        x += 6 * scale
    return x


def load_rgb(path):
    """any image Blender reads -> (h, w, 3) uint8, top row first, values as stored (sRGB)."""
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    px = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(px)
    a = px.reshape(h, w, 4)[::-1, :, :3]
    bpy.data.images.remove(im)
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def resize(a, h_new):
    h, w = a.shape[:2]
    w_new = int(round(w * h_new / h))
    ys = np.clip((np.arange(h_new) + 0.5) * h / h_new - 0.5, 0, h - 1)
    xs = np.clip((np.arange(w_new) + 0.5) * w / w_new - 0.5, 0, w - 1)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, h - 1)
    x1 = np.minimum(x0 + 1, w - 1)
    fy = (ys - y0)[:, None, None]
    fx = (xs - x0)[None, :, None]
    a = a.astype(np.float64)
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
    bot = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
    return np.clip(top * (1 - fy) + bot * fy, 0, 255).astype(np.uint8)


def compare_stage():
    os.makedirs(COMPARE, exist_ok=True)
    made = []
    for name, S in SHOTS.items():
        if not S.get("ref") or (SHOT_FILTER and name not in SHOT_FILTER):
            continue
        ours_p = os.path.join(PREV, name + ".png")
        ref_p = os.path.join(REF, S["ref"])
        if not (os.path.exists(ours_p) and os.path.exists(ref_p)):
            log("compare: missing", ours_p if not os.path.exists(ours_p) else ref_p)
            continue
        ours = load_rgb(ours_p)
        ref = load_rgb(ref_p)
        Hh = 600
        ours = resize(ours, Hh)
        ref = resize(ref, Hh)
        gap, top = 16, 46
        W = ref.shape[1] + ours.shape[1] + gap * 3
        img = np.full((Hh + top + gap, W, 3), 24, np.uint8)
        img[top:top + Hh, gap:gap + ref.shape[1]] = ref
        x2 = gap * 2 + ref.shape[1]
        img[top:top + Hh, x2:x2 + ours.shape[1]] = ours
        draw_text(img, gap, 14, "REFERENCE - " + S["label"] + " - STUDY ONLY", 3, (236, 210, 150))
        draw_text(img, x2, 14, "OURS - MAP1_GREEN_LAND.PY - STYLE A", 3, (190, 230, 190))
        out = os.path.join(COMPARE, "compare_" + name.replace("match_", "") + ".png")
        png_write(out, img)
        made.append(out)
        log("COMPARE", out)
    return made


# ================================================================================================ main
def main():
    log("Map 1 generator: stages", STAGES, "out", OUT, "preview", PREV, "work", WORK)
    A = None
    if "data" in STAGES:
        data_stage()
    if "assets" in STAGES or "scene" in STAGES:
        A = build_assets()
    if "assets" in STAGES:
        export_glbs(A)
    if "scene" in STAGES:
        scene_stage(A)
    if "render" in STAGES:
        render_stage()
    if "compare" in STAGES:
        compare_stage()
    log("done")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
