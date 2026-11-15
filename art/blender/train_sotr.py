"""
train_sotr.py - LAST STANDING ("HUNGER GAMES (BETA)"): the train and its station in the look of "The Hunger Games:
                Sunrise on the Reaping" (Blender 5.3, headless)
                -> Train_*.glb + Train.manifest.json + textures/ + review previews (art/previews/Train/)

The owner, 14 November 2026: "AND MAKE THE TRAINS LOOK LIKE THEM TOO", "FROM NOW TAKE INSPIRATION FROM THE UPCOMNG
MOVIE", "make sure blendr recreates the map assets and game design with semi realistic colour tones". The brief is
docs/design/UpcomingFilm_Brief.md section 4 (the station hall and the trains in the film's look), with the owner's
TRIBUTE spec section 9 (docs/design/owner/TributeSpec_BloodAndMovement_2026-11-14.md) for the seven cars and their
rooms. The primary reference is the owner's frame References/owner/train_station_owner_frame.png (Trailer 1 @35.7 s,
https://www.youtube.com/watch?v=fS35YSjopjE), plus the trailer frames the brief lists. References are for study only:
nothing here is traced, copied or embedded. Every sign, emblem, poster, board, upholstery motif and plate is our own;
there is no lettering anywhere (the departure boards carry abstract glyph blocks, not words).

Style A, "faceted realism" (docs/design/ArtStyle.md section 6; .claude/skills/blender-art):
  - true scale (1 stud = 0.28 m, player 5.5, doors 4 x 7.5), real members built as chamfered prisms, few volumes;
  - flat-shaded facets sized by class (1-2.5 studs on architecture and the car bodies, 0.3-1 on props);
  - colour painted per facet (+-5 % per volume, +-2.5 % per facet, lighter and warmer on top, cooler underneath),
    two-radius AO multiplied in (never below half the painted value), a 0.04-0.08-stud bevel normal only;
  - matte (roughness 0.75-0.95) except real metal (brass, gold, steel), glass, the polished platform stone (0.4)
    and the train's semi-gloss lacquer (roughness 0.3, metalness 0.2: brief 4.3, a matte black train reads as a hole);
  - semi-real tones from the brief's palette (4.6), inside the light band (built surfaces luma 55-215, deliberate
    blacks >= 40); darkness inside comes from the light rigs, never the paint; saturated colour only on signals
    (the red-orange nose lamp, the amber board rows, the propaganda screen's cool light).

What it builds (see build_all_assets(); every asset is a root EMPTY <Asset> with MeshParts <Asset>_<Role>[_n]):
  Station (Train_Station.glb, hall 170 x 420 studs after brief 4.2; the entrance hall is 156 deep so a camera can
  stand as far back as the film's, the shed 264, and 6 more shed bays recede beyond as backdrop):
    Station_Coffer           one 12 x 12 coffer of the concrete ceiling with its round downlight (placed 160 times)
    Station_EntranceCeiling  the soffit collar, radial ribs and deep fascia round the 100 x 50 oval; header wall
    Station_Lantern          the elliptical drum and coffered dome above the oval
    Station_Sunburst         10 tapered gold blades in two fans, two collars and a drop (our own sculpture)
    Station_EntranceWalls    side walls of the entrance hall (columns, tall glazing, base with doors) + end wall
    Station_EntranceFloor    polished stone floor of the entrance hall with our own brass sunrise inlay
    Station_Portal           the white cross-beam on four columns at the shed's mouth, with our own gold emblem
    Station_ShedBay          a 24-stud slice of the train shed: glazed walls with stepped white fins, roof beams
    Station_FloorBay         a 24-stud slice of floor: concourse, two platforms, the guideway pits and maglev beams
    Station_ShedEnd          the far end: portal frame, pits running out, a glowing backdrop
  Station props (Train_StationProps.glb):
    Station_Banner (5 x 18, pointed, our own gold motif), Station_Board (10 x 5 on posts, glyph rows),
    Station_Poster (14 x 24, our own faceted-guard poster), Station_Guard (our own white-armoured guard, statue pose)
  Trains (Train_Exterior.glb, brief 4.3):
    Train_NoseCar (90), Train_BodyCar (80), Train_ObservationCar (80): glossy black and maroon lacquer, gold
    pinstripes, round-cornered brass windows, maglev skirt (no wheels), a faceted capsule nose with a 3.5-stud
    gold-rimmed lamp round a glowing 2-stud core; Train_DoorLeaf (a separate moving mesh)
  Interiors (Train_InteriorsA/B/C.glb, spec section 9 in the film's materials, brief 4.4; a room texture set and a
  furniture texture set per car):
    Train_Car1_Vestibule (fits the nose car), Train_Car2_Dining, Train_Car3_Lounge, Train_Car4_Corridor,
    Train_Car5_Compartment, Train_Car6_Observation (fits the observation car), Train_Car7_Guard (fits the nose car,
    turned round as the tail), plus the moving pieces: Train_Chandelier, Train_PendantLamp, Train_CompartmentDoor,
    Train_VestibuleDoor, Train_GangwayDoor, Train_GlobeLid, Train_BudVase, Train_Crystal; Train_BridgeBackdrop (the
    night bridge seen from the observation car and in exterior_night_bridge)
  Every car stays under 10k triangles with its interior, every MeshPart under 5k. Collision is explicit: each asset
  lists collider boxes in the manifest; mesh parts are visual only.

Run (headless, from the repo root; art/README.md section 1):
  blender --background --factory-startup --python art/blender/train_sotr.py -- <out_dir> <preview_dir> [stages]
    out_dir      BlenderExports (or BlenderExports/Train); files go to <...>/Train/
    preview_dir  art/previews (or art/previews/Train); renders go to <...>/Train/
    stages       comma list, default build,preview
      quick[:station|exterior|interiors|carN]   look-dev renders straight from the painted meshes (no bake) -> WORK
      build                                     geometry, paint, UVs, bakes, GLBs, manifest (+ copy in art/manifests)
      preview[:station+exterior+interiors+compare+tones]   review renders from the EXPORTED GLBs into preview_dir
                                                (the parts after the colon, joined by +, pick what to render)
  env TRAIN_SOTR_WORK  work folder (default %TEMP%/TrainSotR_build)
  env TRAIN_SOTR_REFS  the LastStanding/References folder (owner frame for the compare sheets; never copied)
  env TRAIN_SOTR_FAST  1 = quarter samples and half resolution in preview renders (look-dev only)
Seeded (SEED = 50): the same script gives the same meshes and textures.

Compare sheets (compare_*.png) put the owner's frame beside our render for review. They hold film imagery, so
.gitignore keeps them out of the repo (the brief: no reference image goes into the repo or the game).
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

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, geometry

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)
import tex_ground as tg  # noqa: E402  shared helpers (PNG writer, push-pull bleed, colour maths, GPU setup); read only

T0 = time.time()


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CATEGORY = "Train"
EXPORTS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")


def _sub(path, name):
    path = os.path.abspath(path)
    return path if os.path.basename(path.rstrip("\\/")).lower() == name.lower() else os.path.join(path, name)


OUT = _sub(ARGV[0], CATEGORY) if len(ARGV) > 0 and ARGV[0] not in ("", "-") else os.path.join(EXPORTS, CATEGORY)
PREV = (_sub(ARGV[1], CATEGORY) if len(ARGV) > 1 and ARGV[1] not in ("", "-")
        else os.path.normpath(os.path.join(HERE, "..", "previews", CATEGORY)))
STAGES = [s for s in (ARGV[2] if len(ARGV) > 2 else "build,preview").split(",") if s]
EXPORT_ROOT = os.path.dirname(OUT)
TEX = os.path.join(OUT, "textures")
GLB_ONLY = os.path.join(TEX, "glb_only")
REL_TEX = os.path.relpath(TEX, EXPORT_ROOT).replace("\\", "/")
REL_OUT = os.path.relpath(OUT, EXPORT_ROOT).replace("\\", "/")
WORK = os.environ.get("TRAIN_SOTR_WORK") or os.path.join(tempfile.gettempdir(), "TrainSotR_build")
REFS = os.environ.get("TRAIN_SOTR_REFS") or os.path.join(os.path.expanduser("~"), "OneDrive", "Documents",
                                                         "LastStanding", "References")
FAST = os.environ.get("TRAIN_SOTR_FAST", "0") == "1"
ART = os.path.normpath(os.path.join(HERE, ".."))
REPO_MANIFESTS = os.path.join(ART, "manifests")
MANIFEST_PATH = os.path.join(OUT, CATEGORY + ".manifest.json")
SEED = 50

TAU = 2.0 * math.pi
V = Vector
UP = V((0.0, 0.0, 1.0))
PART_MAX_TRIS = 4900          # every MeshPart under 5k (brief 4.7)
ASSET_MAX_TRIS = 10000        # a car or a hall section at most 10k

# ================================================================================================ dimensions
# Station hall space (Blender, Z up): x across the hall (west -85 .. east +85), y along it (entrance end +210 .. far
# end -210), floor z = 0. Roblox (x, y, z) = Blender (x, z, -y), so the entrance end is Roblox -Z.
HALL_W, HALL_L = 170.0, 420.0
WALL_X = 85.0
CONC_X = 33.0                 # concourse 66 wide (x -33 .. 33)
PLAT_X = 63.0                 # platforms 30 wide (33 .. 63), the guideway bays 22 wide (63 .. 85)
PIT_Z = -5.0                  # guideway bay floor
ENT_Y0, ENT_Y1 = 54.0, 210.0   # entrance hall under the coffered ceiling (13 coffers deep)
OVAL_Y = 110.0                # the oval's centre = origin of the entrance-hall assets
OVAL_A, OVAL_B = 50.0, 25.0   # semi-axes of the 100 x 50 oval
CEIL_Z = 40.0                 # coffer rib soffit; coffers recess up to 44
COFFER = 12.0
LANTERN_Z = 72.0              # coffered dome above the oval
SHED_H = 60.0
BAY = 24.0
NBAYS = 11                    # 11 x 24 = 264: the shed from y 54 to -210
BACKDROP_BAYS = 6             # the shed recedes beyond the walkable 420 as a cheap backdrop
SHED_END_Y = ENT_Y0 - BAY * (NBAYS + BACKDROP_BAYS)

# Train (car space: origin at the car's footprint centre on platform level, front (+Y) = the nose / Roblox -Z)
CAR_W = 11.5
HWID = CAR_W / 2.0
CAR_L, NOSE_CAR_L = 80.0, 90.0
NOSE_LEN = 15.0
FLOOR_Z = 0.3                 # interior floor (0.3 above the platform)
SKIRT_Z = -2.2                # underside of the skirt; the guideway flange top is at -2.45
LIN_X = 5.25                  # interior lining (0.5 inside the skin)
WALL_TOP = 8.2                # lining wall top / cove line
VAULT_Z = 9.9                 # interior ceiling crown (9.6 clear)
WIN_W, WIN_Z0, WIN_Z1 = 5.0, 3.7, 7.3
DOOR_W, DOOR_H = 4.0, 7.5     # z 0.3 .. 7.8
DOOR_Z1 = FLOOR_Z + DOOR_H
TRACK_X = PLAT_X + 0.5 + HWID  # 69.25: 0.5 gap to the platform edge
GANGWAY_GAP = 1.5
NOSE_FRONT_Y = 52.0           # noses stop 2 studs inside the shed's mouth

# ================================================================================================ palette
# Semi-real tones (sRGB) from the brief's tables (4.6; sampled -> softened -> clamped into ArtStyle's light band).
# rough/metal are the SurfaceAppearance values; kv/kf the per-volume / per-facet value jitter; pat a pattern id
# applied at bake time (1 upholstery, 2 carpet lattice, 3 table runner).


def mk(rgb, rough=0.85, metal=0.0, kv=0.05, kf=0.025, pat=0, grade=1.0):
    return dict(rgb=tuple(rgb), rough=rough, metal=metal, kv=kv, kf=kf, pat=pat, grade=grade)


MK = {
    # station
    "concrete": mk((148, 142, 134), 0.88),                        # brief: coffered concrete #948e86
    "coffer": mk((138, 133, 126), 0.9, kv=0.03),                  # inside the coffers, a touch darker
    "concrete_dark": mk((112, 108, 102), 0.9),                    # pits, plinths
    "floor": mk((110, 104, 98), 0.4, kv=0.07, kf=0.0),            # polished platform stone (brief: roughness 0.4)
    "floor_light": mk((150, 142, 130), 0.4, kv=0.05, kf=0.0),     # inlay stone
    "edge_strip": mk((190, 176, 136), 0.8, kv=0.03),              # platform edge band (muted, not a signal)
    "white_steel": mk((212, 208, 200), 0.6, 0.1, kv=0.025),       # mullions, fins, cross-beam (#d4d0c8)
    "bronze": mk((96, 84, 72), 0.55, 0.6, kv=0.03),               # entrance-hall window frames
    "gold": mk((186, 142, 78), 0.3, 0.9, kv=0.03, kf=0.03),       # the sunburst blades (#ba8e4e)
    "brass": mk((180, 132, 74), 0.35, 0.9, kv=0.03, kf=0.02),     # brass frames and fittings (#b4844a)
    "steel": mk((150, 152, 154), 0.4, 0.8, kv=0.03),              # rails, rods
    "steel_dark": mk((84, 86, 88), 0.55, 0.6, kv=0.03),
    "guideway": mk((138, 133, 126), 0.9),
    "banner": mk((88, 48, 46), 0.92, kv=0.03),                    # brief: banners #58302e
    "banner_gold": mk((176, 138, 80), 0.45, 0.6, kv=0.02),        # our own motif (#b08a50)
    "board": mk((44, 44, 46), 0.5, 0.2, kv=0.02),                 # departure boards (#2c2c2e)
    "poster_maroon": mk((122, 54, 54), 0.85, kv=0.0, kf=0.0),
    "poster_gold": mk((182, 140, 82), 0.85, kv=0.0, kf=0.0),
    "poster_cream": mk((214, 202, 178), 0.85, kv=0.0, kf=0.0),
    "poster_slate": mk((88, 104, 116), 0.85, kv=0.0, kf=0.0),
    "poster_white": mk((212, 210, 204), 0.85, kv=0.0, kf=0.0),
    "poster_shade": mk((160, 158, 152), 0.85, kv=0.0, kf=0.0),
    "poster_dark": mk((52, 48, 50), 0.85, kv=0.0, kf=0.0),
    "poster_sky": mk((196, 140, 96), 0.85, kv=0.0, kf=0.0),
    "armour": mk((214, 212, 206), 0.55, kv=0.02, kf=0.02),        # brief: armour #d6d4ce
    "harness": mk((48, 48, 50), 0.7, kv=0.02),                    # harness #303032
    "suit": mk((74, 74, 78), 0.85, kv=0.03),
    "visor": mk((50, 52, 56), 0.15, 0.3, kv=0.0, kf=0.0),
    # train exterior (semi-gloss lacquer is the deliberate exception to the matte rule)
    "lacquer": mk((46, 40, 44), 0.3, 0.2, kv=0.015, kf=0.012),    # body #2e282c
    "maroon": mk((112, 46, 48), 0.3, 0.2, kv=0.015, kf=0.012),    # panels #702e30
    "pinstripe": mk((184, 146, 90), 0.35, 0.6, kv=0.01, kf=0.0),  # gold pinstripes #b8925a
    "bezel": mk((44, 42, 46), 0.35, 0.4, kv=0.01, kf=0.01),       # the lamp's dark surround
    "bellows": mk((52, 50, 50), 0.9, kv=0.02),
    "underframe": mk((58, 58, 60), 0.75, 0.3, kv=0.02),
    # train interior (film materials, brief 4.4)
    "upholstery": mk((100, 46, 38), 0.92, kv=0.03, kf=0.0, pat=1),  # #642e26 with our cream arcs (#ceb48e)
    "leather": mk((112, 66, 46), 0.6, kv=0.04),                   # pleated leather bench
    "velvet": mk((124, 54, 52), 0.95, kv=0.04),                   # oxblood velvet club chairs (lifted: baked 49)
    "wood": mk((132, 84, 60), 0.55, kv=0.05),                     # arches and panelling (#84543c)
    "wood_dark": mk((104, 64, 46), 0.6, kv=0.05),                 # mahogany skirting and frames
    "hammered": mk((198, 166, 126), 0.5, 0.35, kv=0.02, kf=0.045),  # hammered cream-gold ceiling (#c6a67e)
    "wall_cream": mk((186, 164, 132), 0.9, kv=0.025),             # upper wall panels
    "carpet": mk((94, 42, 40), 0.95, kv=0.02, kf=0.0, pat=2),     # burgundy carpet, gold lattice
    "parquet": mk((126, 82, 58), 0.55, kv=0.06, kf=0.0),
    "marble": mk((196, 186, 168), 0.35, kv=0.04, kf=0.0),
    "marble_dark": mk((112, 70, 58), 0.35, kv=0.04, kf=0.0),
    "linen": mk((214, 208, 196), 0.9, kv=0.015),
    "runner": mk((112, 50, 44), 0.9, kv=0.0, kf=0.0, pat=3),
    "porcelain": mk((212, 208, 200), 0.3, kv=0.01, kf=0.01),
    "silver": mk((178, 180, 182), 0.3, 0.9, kv=0.01),
    "silk": mk((198, 178, 146), 0.4, kv=0.02),
    "cotton": mk((186, 182, 172), 0.95, kv=0.02),
    "uniform": mk((92, 96, 104), 0.85, kv=0.03),
    "mirror": mk((196, 200, 202), 0.08, 1.0, kv=0.0, kf=0.0),
    "piano": mk((58, 52, 54), 0.25, 0.1, kv=0.01, kf=0.01),
    "keys_white": mk((212, 206, 194), 0.4, kv=0.0, kf=0.01),
    "globe_sea": mk((86, 112, 114), 0.5, kv=0.0, kf=0.03),
    "globe_land": mk((174, 152, 106), 0.5, kv=0.0, kf=0.03),
    "blind": mk((176, 158, 128), 0.9, kv=0.02),
    "screen_frame": mk((54, 52, 54), 0.4, 0.4, kv=0.01),
    "steel_grey": mk((124, 128, 130), 0.6, 0.4, kv=0.03),         # guard car (the District 12 grey steel)
    "steel_plate": mk((92, 96, 100), 0.65, 0.4, kv=0.05, kf=0.0),
    "grating": mk((60, 62, 64), 0.7, 0.4, kv=0.02),
    "slate_steel": mk((88, 104, 116), 0.6, 0.3, kv=0.03),         # #586874
    "flower": mk((150, 112, 120), 0.8, kv=0.02),                  # a wilting rose, muted
    "stem": mk((92, 104, 60), 0.85, kv=0.02),
    # backdrop (night bridge)
    "bridge": mk((132, 134, 136), 0.85, kv=0.03),
    "hill": mk((58, 66, 52), 0.95, kv=0.06),
    "water_dark": mk((40, 56, 66), 0.2, kv=0.0, kf=0.0),
}

# Emissive parts (Neon in Roblox, with the light objects the manifest lists). rgb, preview strength.
EMIT = {
    "lamp_core": ((232, 88, 52), 2.2),        # brief: nose lamp core #e85834
    "marker": ((236, 150, 70), 8.0),
    "downlight": ((255, 238, 214), 18.0),
    "glow": ((248, 232, 222), 3.2),            # glazing glow backdrop #f8e8de
    "glow_roof": ((240, 226, 214), 1.6),
    "glyph": ((232, 232, 226), 4.0),           # board rows #e8e8e2
    "glyph_amber": ((236, 172, 76), 5.0),      # board rows #ecac4c
    "cove": ((255, 196, 128), 9.0),            # amber cove strips
    "bulb": ((255, 214, 160), 16.0),
    "screen": ((132, 172, 214), 1.3),          # the propaganda screen: the lounge's only cool light
    "striplight": ((226, 232, 236), 10.0),     # guard car
    "deck_light": ((255, 200, 140), 20.0),     # the bridge's deck lights
    "window_glow": ((236, 176, 112), 2.0),
}
# Glass parts (Roblox Glass, Transparency from here). rgb, transparency.
GLASS = {
    "glass": ((178, 196, 198), 0.7),
    "glass_dark": ((96, 104, 108), 0.45),
    "crystal": ((220, 226, 228), 0.6),
}
PATTERNS = {1: "upholstery: cream C-arcs (openings alternating by row) and dots on burgundy, 1.4-stud cells",
            2: "carpet: gold diagonal lattice with cream lozenges, 2-stud cells",
            3: "table runner: gold chevrons on burgundy, 1.2-stud cells"}
KEYS = sorted(MK) + sorted(EMIT) + sorted(GLASS)
KEY_ID = {k: i for i, k in enumerate(KEYS)}


def key_kind(k):
    return "tex" if k in MK else ("neon" if k in EMIT else "glass")


def s2l(c):
    return tg.srgb_to_lin(np.asarray(c, np.float64) / 255.0)


def hash01(i, salt=0):
    x = (int(i) * 2654435761 + (salt * 7919 + 104729)) & 0xFFFFFFFF
    x ^= x >> 16
    x = (x * 2246822519) & 0xFFFFFFFF
    x ^= x >> 13
    x = (x * 3266489917) & 0xFFFFFFFF
    x ^= x >> 16
    return (x & 0xFFFFFF) / float(0xFFFFFF)


def jit(i, salt):
    return hash01(i, salt) * 2.0 - 1.0


def luma(rgb):
    r, g, b = rgb
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


# ================================================================================================ mesh accumulator
class MB:
    """Faces with a paint key (MK / EMIT / GLASS) and a volume id. Each modelled face gets one facet id, so all of
    its triangles are painted as one facet. Faces are counter-clockwise seen from their visible side; nothing is
    re-wound later (open shells such as linings and ceilings face one way on purpose)."""

    def __init__(self):
        self.V, self.F, self.K, self.VOL, self.FID = [], [], [], [], []
        self.vol = 0
        self.fid = 0

    def nv(self):
        self.vol += 1
        return self.vol

    def face(self, pts, key, vol=None, fid=None):
        if len(pts) < 3:
            return None
        if key not in KEY_ID:
            raise KeyError("unknown paint key %s" % key)
        base = len(self.V)
        for p in pts:
            self.V.append((float(p[0]), float(p[1]), float(p[2])))
        self.F.append(tuple(range(base, base + len(pts))))
        self.K.append(key)
        self.VOL.append(self.vol if vol is None else vol)
        if fid is None:
            self.fid += 1
            fid = self.fid
        self.FID.append(fid)
        return fid

    def new_fid(self):
        self.fid += 1
        return self.fid

    def extend(self, other, M=None):
        """Append another MB (optionally transformed by the 4x4 Matrix M), keeping its volumes and facets apart."""
        vo, fo = self.vol, self.fid
        for f, k, vv, ff in zip(other.F, other.K, other.VOL, other.FID):
            pts = [V(other.V[i]) for i in f]
            if M is not None:
                pts = [M @ p for p in pts]
            self.face(pts, k, vol=vv + vo, fid=ff + fo)
        self.vol = vo + other.vol + 1
        self.fid = fo + other.fid + 1

    def ntris(self):
        return sum(len(f) - 2 for f in self.F)

    def empty(self):
        return not self.F


# ================================================================================================ primitives
def box(mb, lo, hi, key, skip=(), vol=None):
    """Axis-aligned box, outward faces; skip any of '-x +x -y +y -z +z'."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    if vol is None:
        vol = mb.nv()

    def P(i, j, k):
        return (x1 if i else x0, y1 if j else y0, z1 if k else z0)
    faces = {
        "-x": [P(0, 0, 0), P(0, 0, 1), P(0, 1, 1), P(0, 1, 0)],
        "+x": [P(1, 0, 0), P(1, 1, 0), P(1, 1, 1), P(1, 0, 1)],
        "-y": [P(0, 0, 0), P(1, 0, 0), P(1, 0, 1), P(0, 0, 1)],
        "+y": [P(0, 1, 0), P(0, 1, 1), P(1, 1, 1), P(1, 1, 0)],
        "-z": [P(0, 0, 0), P(0, 1, 0), P(1, 1, 0), P(1, 0, 0)],
        "+z": [P(0, 0, 1), P(1, 0, 1), P(1, 1, 1), P(0, 1, 1)],
    }
    for k, pts in faces.items():
        if k not in skip:
            mb.face(pts, key, vol)
    return vol


def hull(mb, pts, key, vol=None):
    """Convex hull of the points as flat facets (coplanar triangles merged into one facet)."""
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(V(p))
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    drop = list({g for g in res.get("geom_interior", []) + res.get("geom_unused", [])
                 if isinstance(g, bmesh.types.BMVert) and g.is_valid})
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if vol is None:
        vol = mb.nv()
    for f in bm.faces:
        mb.face([v.co.copy() for v in f.verts], key, vol)
    bm.free()
    return vol


def cbox_pts(lo, hi, ch):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    c = min(ch, 0.45 * (x1 - x0), 0.45 * (y1 - y0), 0.45 * (z1 - z0))
    pts = []
    for x, ix in ((x0, 1), (x1, -1)):
        for y, iy in ((y0, 1), (y1, -1)):
            for z, iz in ((z0, 1), (z1, -1)):
                pts += [(x, y + iy * c, z + iz * c), (x + ix * c, y, z + iz * c), (x + ix * c, y + iy * c, z)]
    return pts


def cbox(mb, lo, hi, key, ch=0.12, vol=None):
    """Chamfered box (every edge chamfered by ch): the 'real member' of style A."""
    if ch <= 1e-4:
        return box(mb, lo, hi, key, vol=vol)
    return hull(mb, cbox_pts(lo, hi, ch), key, vol)


def frame_for(d, up=UP):
    d = V(d).normalized()
    u = V(up)
    if abs(d.dot(u)) > 0.97:
        u = V((1, 0, 0)) if abs(d.x) < 0.9 else V((0, 1, 0))
    x = u.cross(d).normalized()
    y = d.cross(x).normalized()
    return x, y, d


def obox(mb, c, ax, half, key, ch=0.0, vol=None):
    """Oriented (chamfered) box: c centre, ax = (X, Y, Z) unit axes, half = half sizes."""
    X, Y, Z = (V(a) for a in ax)
    hx, hy, hz = half
    pts = cbox_pts((-hx, -hy, -hz), (hx, hy, hz), ch) if ch > 1e-4 else \
        [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    return hull(mb, [V(c) + X * p[0] + Y * p[1] + Z * p[2] for p in pts], key, vol)


def beam(mb, p0, p1, w, h, key, up=UP, ch=0.0, vol=None):
    """A rectangular member from p0 to p1 (w across, h along the up hint)."""
    p0, p1 = V(p0), V(p1)
    d = p1 - p0
    L = d.length
    x, y, z = frame_for(d, up)
    return obox(mb, (p0 + p1) * 0.5, (x, y, z), (w * 0.5, h * 0.5, L * 0.5), key, ch, vol)


def loft(mb, rings, key, closed=True, cap0=False, cap1=False, vol=None, keys=None, fids=None):
    """Bands between consecutive rings (rings CCW about the loft direction -> outward faces)."""
    if vol is None:
        vol = mb.nv()
    n = len(rings[0])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            kk = keys(k, i) if callable(keys) else key
            mb.face([a[i], a[j], b[j], b[i]], kk, vol)
    if cap0:
        mb.face(list(reversed(rings[0])), key, vol)
    if cap1:
        mb.face(list(rings[-1]), key, vol)
    return vol


def ring_pts(c, X, Y, rx, ry, n, phase=0.0):
    return [V(c) + X * (rx * math.cos(phase + TAU * i / n)) + Y * (ry * math.sin(phase + TAU * i / n))
            for i in range(n)]


def cyl(mb, p0, p1, r0, r1, n, key, cap0=True, cap1=True, phase=0.0, vol=None, up=UP, sq=1.0):
    p0, p1 = V(p0), V(p1)
    x, y, d = frame_for(p1 - p0, up)
    rings = [ring_pts(p0, x, y, r0, r0 * sq, n, phase), ring_pts(p1, x, y, r1, r1 * sq, n, phase)]
    return loft(mb, rings, key, cap0=cap0 and r0 > 1e-5, cap1=cap1 and r1 > 1e-5, vol=vol)


def lathe(mb, prof, n, key, c=(0, 0, 0), phase=0.0, sx=1.0, sy=1.0, cap0=True, cap1=True, vol=None, keys=None):
    """prof: [(r, z)] from bottom to top; rings CCW about +Z -> outward."""
    c = V(c)
    rings = [[V((c.x + sx * r * math.cos(phase + TAU * i / n), c.y + sy * r * math.sin(phase + TAU * i / n),
                 c.z + z)) for i in range(n)] for r, z in prof]
    return loft(mb, rings, key, cap0=cap0 and prof[0][0] > 1e-5, cap1=cap1 and prof[-1][0] > 1e-5, vol=vol,
                keys=keys)


def sweep(mb, path, section, key, up=UP, cap0=True, cap1=True, vol=None, keys=None):
    """Sweep 2D sections along a polyline. section(k) -> [(u, v)] CCW (u along the frame's x, v along its y)."""
    path = [V(p) for p in path]
    rings = []
    for k, p in enumerate(path):
        if k == 0:
            t = path[1] - path[0]
        elif k == len(path) - 1:
            t = path[-1] - path[-2]
        else:
            t = (path[k + 1] - path[k]).normalized() + (path[k] - path[k - 1]).normalized()
        x, y, _ = frame_for(t, up)
        rings.append([p + x * u + y * v for u, v in section(k)])
    return loft(mb, rings, key, cap0=cap0, cap1=cap1, vol=vol, keys=keys)


def poly_holes(mb, outer, holes, key, normal, vol=None):
    """Planar polygon with holes, triangulated (one facet); triangles wound to face `normal`."""
    loops = [[V(p) for p in outer]] + [[V(p) for p in h] for h in holes]
    pts = [p for lp in loops for p in lp]
    tris = geometry.tessellate_polygon(loops)
    fid = mb.new_fid()
    n = V(normal)
    if vol is None:
        vol = mb.nv()
    for t in tris:
        a, b, c = (pts[i] for i in t)
        if (b - a).cross(c - a).dot(n) < 0:
            b, c = c, b
        mb.face([a, b, c], key, vol, fid=fid)
    return vol


def rrect(cx, cz, w, h, r, seg=3):
    """Rounded rectangle in (u, v) plane, CCW, starting at the lower-right corner arc."""
    r = min(r, 0.49 * w, 0.49 * h)
    pts = []
    for (ux, vz, a0) in ((cx + w / 2 - r, cz - h / 2 + r, -90.0), (cx + w / 2 - r, cz + h / 2 - r, 0.0),
                         (cx - w / 2 + r, cz + h / 2 - r, 90.0), (cx - w / 2 + r, cz - h / 2 + r, 180.0)):
        for s in range(seg + 1):
            a = math.radians(a0 + 90.0 * s / seg)
            pts.append((ux + r * math.cos(a), vz + r * math.sin(a)))
    return pts


def clip_poly(poly, x0, y0, x1, y1):
    """Sutherland-Hodgman clip of a 2D polygon to a rectangle."""
    def clip(pts, inside, inter):
        out = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]
            ia, ib = inside(a), inside(b)
            if ib:
                if not ia:
                    out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out

    def ix(a, b, x):
        t = (x - a[0]) / (b[0] - a[0])
        return (x, a[1] + t * (b[1] - a[1]))

    def iy(a, b, y):
        t = (y - a[1]) / (b[1] - a[1])
        return (a[0] + t * (b[0] - a[0]), y)
    p = list(poly)
    for inside, inter in ((lambda q: q[0] >= x0, lambda a, b: ix(a, b, x0)),
                          (lambda q: q[0] <= x1, lambda a, b: ix(a, b, x1)),
                          (lambda q: q[1] >= y0, lambda a, b: iy(a, b, y0)),
                          (lambda q: q[1] <= y1, lambda a, b: iy(a, b, y1))):
        if not p:
            break
        p = clip(p, inside, inter)
    return p


def ellipse_pts(a, b, n, z, cx=0.0, cy=0.0, phase=0.0):
    return [V((cx + a * math.cos(phase + TAU * i / n), cy + b * math.sin(phase + TAU * i / n), z)) for i in range(n)]


def disc(mb, c, r, n, normal, key, vol=None, phase=0.0):
    x, y, d = frame_for(normal)
    pts = ring_pts(c, x, y, r, r, n, phase)
    mb.face(pts, key, vol)


# ================================================================================================ assets
class Asset:
    """One root EMPTY with MeshParts by role. Part kinds: 'tex' (baked texture set), 'neon' (emissive, one EMIT
    key), 'glass' (one GLASS key). Attachments and collider boxes are kept in Blender asset space."""

    def __init__(self, name, kind, glb, tset=None, tags=(), notes="", pivot="base centre on the floor",
                 tex_size=1024):
        self.name, self.kind, self.glb = name, kind, glb
        self.tset = tset or name
        self.tags, self.notes, self.pivot = list(tags), notes, pivot
        self.tex_size = tex_size
        self.parts = {}
        self.attach = {}
        self.colliders = []
        self.objs = []          # built Blender objects (role, obj)

    def part(self, role, kind="tex", collide=False, collision="Box", shadow=True, tags=(), tset=None, size=None):
        if role not in self.parts:
            self.parts[role] = dict(mb=MB(), kind=kind, collide=collide, collision=collision, shadow=shadow,
                                    tags=list(tags), tset=tset or self.tset, size=size or self.tex_size)
        return self.parts[role]["mb"]

    def att(self, name, pos, look=(0, 1, 0), up=(0, 0, 1), **extra):
        self.attach[name] = dict(pos=V(pos), look=V(look).normalized(), up=V(up).normalized(), extra=extra)

    def collider(self, lo, hi, tag="Solid"):
        lo, hi = V(lo), V(hi)
        self.colliders.append((V((min(lo.x, hi.x), min(lo.y, hi.y), min(lo.z, hi.z))),
                               V((max(lo.x, hi.x), max(lo.y, hi.y), max(lo.z, hi.z))), tag))

    def ntris(self):
        return sum(p["mb"].ntris() for p in self.parts.values())


# ================================================================================================ mesh objects
def split_mb(mb, max_tris=PART_MAX_TRIS):
    """Bisect a part along its longest axis (by face centroids, at the triangle median) until every piece fits."""
    if mb.ntris() <= max_tris:
        return [mb]
    cents = np.array([np.mean([mb.V[i] for i in f], axis=0) for f in mb.F])
    span = cents.max(0) - cents.min(0)
    ax = int(np.argmax(span))
    order = np.argsort(cents[:, ax], kind="stable")
    tri = np.array([len(f) - 2 for f in mb.F])[order]
    cut = int(np.searchsorted(np.cumsum(tri), tri.sum() / 2.0))
    out = []
    for sel in (order[:cut + 1], order[cut + 1:]):
        sub = MB()
        for fi in sel:
            f = mb.F[fi]
            sub.face([mb.V[i] for i in f], mb.K[fi], vol=mb.VOL[fi], fid=mb.FID[fi])
        sub.vol, sub.fid = mb.vol, mb.fid
        out += split_mb(sub, max_tris)
    return out


def finish_mesh(obj):
    """Weld, drop degenerate faces, triangulate (bake, tangents and GLB see the same triangles), flat-shade."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges[:])
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.polygons.foreach_set("use_smooth", np.zeros(len(obj.data.polygons), bool))
    obj.data.update()


def mb_object(mb, name, collection=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.V, [], mb.F)
    me.update(calc_edges=True)
    for nm, vals in (("mk", [KEY_ID[k] for k in mb.K]), ("vol", mb.VOL), ("fid", mb.FID)):
        a = me.attributes.new(nm, "INT", "FACE")
        a.data.foreach_set("value", np.asarray(vals, np.int32))
    obj = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(obj)
    finish_mesh(obj)
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def paint(obj, salt=0):
    """One flat painted colour per modelled facet -> corner colour attributes bk_col (linear) and bk_rmp
    (roughness, metalness, pattern id / 8)."""
    me = obj.data
    nP, nL = len(me.polygons), len(me.loops)
    if nP == 0:
        return obj
    kid, vol, fid = (np.empty(nP, np.int32) for _ in range(3))
    me.attributes["mk"].data.foreach_get("value", kid)
    me.attributes["vol"].data.foreach_get("value", vol)
    me.attributes["fid"].data.foreach_get("value", fid)
    nrm = np.empty(nP * 3, np.float32)
    me.polygons.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)
    lt = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_total", lt)
    lstart = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_start", lstart)
    area = np.empty(nP, np.float32)
    me.polygons.foreach_get("area", area)
    # facet normal = area-weighted mean over its triangles (a hammered facet stays one value)
    ufid, inv = np.unique(fid, return_inverse=True)
    fn = np.zeros((len(ufid), 3))
    np.add.at(fn, inv, nrm * area[:, None])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    fnz = fn[inv, 2]
    col = np.ones((nL, 4), np.float32)
    rmp = np.zeros((nL, 4), np.float32)
    rmp[:, 3] = 1.0
    for pi in range(nP):
        key = KEYS[kid[pi]]
        if key not in MK:
            c = np.asarray(s2l(EMIT[key][0] if key in EMIT else GLASS[key][0]))
            col[lstart[pi]:lstart[pi] + lt[pi], :3] = c
            rmp[lstart[pi]:lstart[pi] + lt[pi], :3] = (0.2, 0.0, 0.0)
            continue
        m = MK[key]
        base = np.asarray(m["rgb"], np.float64) / 255.0
        vv, ff = int(vol[pi]) + 7919 * salt, int(fid[pi]) + 104729 * salt
        val = 1.0 + m["kv"] * jit(vv, 3) + m["kf"] * jit(ff, 5)
        t = float(np.clip(fnz[pi], -1.0, 1.0)) * m["grade"]
        val *= 1.0 + 0.035 * t                                         # lighter on top, darker underneath
        c = base * val
        c = c * np.array([1.0 + 0.012 * t, 1.0 + 0.004 * t, 1.0 - 0.012 * t])   # warmer on top, cooler below
        c = c + 0.010 * jit(vv, 7) * np.array([0.8, 0.25, -0.9]) * base.mean()  # slight warm / cool drift
        col[lstart[pi]:lstart[pi] + lt[pi], :3] = tg.srgb_to_lin(np.clip(c, 0.0, 1.0))
        rmp[lstart[pi]:lstart[pi] + lt[pi], :3] = (m["rough"], m["metal"], m["pat"] / 8.0)
    kidc = np.ones((nL, 4), np.float32)
    kidc[:, 0] = (np.repeat(kid, lt) + 0.5) / 256.0
    for nm, arr in (("bk_col", col), ("bk_rmp", rmp), ("bk_kid", kidc)):
        a = me.color_attributes.get(nm) or me.color_attributes.new(nm, "FLOAT_COLOR", "CORNER")
        a.data.foreach_set("color", arr.ravel())
    return obj


def build_asset_objects(asset, collection=None, salt=0):
    """MB parts -> painted mesh objects (split under 5k triangles), parented to a root EMPTY at the origin."""
    root = bpy.data.objects.new(asset.name, None)
    (collection or bpy.context.scene.collection).objects.link(root)
    asset.root = root
    asset.objs = []
    for role, p in asset.parts.items():
        if p["mb"].empty():
            continue
        if p["kind"] != "tex":
            ks = set(p["mb"].K)
            assert len(ks) == 1, "%s_%s mixes keys %s" % (asset.name, role, ks)
        pieces = split_mb(p["mb"])
        for i, sub in enumerate(pieces):
            nm = "%s_%s" % (asset.name, role) + ("_%d" % (i + 1) if len(pieces) > 1 else "")
            o = mb_object(sub, nm, collection)
            paint(o, salt)
            o["tset"] = p["tset"]
            o["tsize"] = p["size"]
            o.parent = root
            o["role"] = role
            o["kind"] = p["kind"]
            o["key"] = sub.K[0]
            asset.objs.append((role, o))
    return root


# ================================================================================================ scene helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_material(name):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    return m


def link_only(nt, out_socket, in_socket):
    for l_ in list(in_socket.links):
        nt.links.remove(l_)
    nt.links.new(out_socket, in_socket)


_QMATS = {}


def neon_material(key, strength_scale=1.0):
    nm = "PV_neon_%s_%.2f" % (key, strength_scale)
    if nm in bpy.data.materials:
        return bpy.data.materials[nm]
    m = new_material(nm)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    rgb, s = EMIT[key]
    em.inputs["Color"].default_value = (*s2l(rgb), 1.0)
    em.inputs["Strength"].default_value = s * strength_scale
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def glass_material(key):
    nm = "PV_glass_%s" % key
    if nm in bpy.data.materials:
        return bpy.data.materials[nm]
    m = new_material(nm)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    rgb, transp = GLASS[key]
    # Roblox glass is a see-through tinted sheet, not a refractive solid: mix a transparent and a glossy BSDF
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    tr.inputs["Color"].default_value = (*(0.85 + 0.15 * np.asarray(s2l(rgb))), 1.0)
    gl = nt.nodes.new("ShaderNodeBsdfPrincipled")
    gl.inputs["Base Color"].default_value = (*s2l(rgb), 1.0)
    gl.inputs["Roughness"].default_value = 0.06
    gl.inputs["Metallic"].default_value = 0.0
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = 1.0 - transp
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(gl.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    return m


def quick_tex_material():
    if "Q_tex" in _QMATS:
        return _QMATS["Q_tex"]
    m = new_material("Q_tex")
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    ac = nt.nodes.new("ShaderNodeAttribute")
    ac.attribute_name = "bk_col"
    ar = nt.nodes.new("ShaderNodeAttribute")
    ar.attribute_name = "bk_rmp"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(ac.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(ar.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Red"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Metallic"])
    _QMATS["Q_tex"] = m
    return m


def assign_quick_materials(asset):
    for role, o in asset.objs:
        o.data.materials.clear()
        if o["kind"] == "tex":
            o.data.materials.append(quick_tex_material())
        elif o["kind"] == "neon":
            o.data.materials.append(neon_material(o["key"]))
        else:
            o.data.materials.append(glass_material(o["key"]))


def render_setup(scene, res, samples, denoise=True):
    tg.enable_gpu(scene)
    c = scene.cycles
    if FAST:
        samples = max(16, samples // 4)
        res = (res[0] // 2, res[1] // 2)
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.02
    c.use_denoising = denoise
    c.max_bounces = 8
    c.diffuse_bounces = 3
    c.glossy_bounces = 3
    c.transmission_bounces = 6
    c.transparent_max_bounces = 12
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.sample_clamp_indirect = 8.0
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.film_transparent = False
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    # Khronos PBR Neutral keeps the painted hue and value (closest of Blender's transforms to how Roblox shows paint)
    try:
        scene.view_settings.view_transform = "Khronos PBR Neutral"
        scene.view_settings.look = "None"
    except TypeError:
        scene.view_settings.view_transform = "AgX"


def set_world(scene, kind, strength=1.0, sun_elev=14.0, sun_azim=-90.0):
    """kind: 'sky' (late-day sky texture) or a flat colour (r, g, b) in sRGB."""
    world = bpy.data.worlds.get("TS_World") or bpy.data.worlds.new("TS_World")
    if world.node_tree is None:
        world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    if kind == "sky":
        sky = nt.nodes.new("ShaderNodeTexSky")
        try:
            sky.sky_type = "MULTIPLE_SCATTERING"
        except TypeError:
            sky.sky_type = "NISHITA"
        sky.sun_disc = False
        sky.altitude = 300.0
        try:
            sky.aerosol_density = 1.6
        except AttributeError:
            pass
        sky.sun_elevation = math.radians(sun_elev)
        sky.sun_rotation = math.radians(sun_azim)
        nt.links.new(sky.outputs[0], bg.inputs[0])
    else:
        bg.inputs[0].default_value = (*s2l(kind), 1.0)
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs[0])
    scene.world = world
    return world


def add_light(scene, name, kind, loc, energy, color=(1, 1, 1), size=1.0, rot=None, target=None, shape="RECTANGLE",
              size_y=None, spot=None):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.shape = shape
        ld.size = size
        if size_y is not None:
            ld.size_y = size_y
    elif kind in ("POINT", "SPOT"):
        ld.shadow_soft_size = size
        if kind == "SPOT" and spot:
            ld.spot_size = math.radians(spot[0])
            ld.spot_blend = spot[1]
    elif kind == "SUN":
        ld.angle = math.radians(size)
    o = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(o)
    o.location = loc
    if target is not None:
        o.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    elif rot is not None:
        o.rotation_euler = rot
    return o


def camera(scene, loc, target, hfov=70.0, res=None, shift_y=0.0, roll=0.0):
    cd = bpy.data.cameras.get("TS_Cam") or bpy.data.cameras.new("TS_Cam")
    cam = bpy.data.objects.get("TS_Cam")
    if cam is None:
        cam = bpy.data.objects.new("TS_Cam", cd)
        scene.collection.objects.link(cam)
    cd.sensor_fit = "HORIZONTAL"
    cd.angle = math.radians(hfov)
    cd.clip_start = 0.1
    cd.clip_end = 4000.0
    cd.shift_y = shift_y
    cam.location = loc
    q = (V(target) - V(loc)).to_track_quat("-Z", "Y")
    cam.rotation_euler = q.to_euler()
    if roll:
        cam.rotation_euler.rotate_axis("Z", math.radians(roll))
    scene.camera = cam
    if res:
        scene.render.resolution_x, scene.render.resolution_y = res
    return cam


def render_to(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    log("RENDER %s (%.0fs)" % (path, time.time() - t))
    return path


# ================================================================================================ more shapes
def face_toward(mb, pts, key, ref, vol=None, fid=None):
    """Add a face, wound so its normal points along ref (a direction)."""
    pts = [V(p) for p in pts]
    n = V((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += V(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    if n.dot(V(ref)) < 0:
        pts.reverse()
    return mb.face(pts, key, vol, fid)


def torus(mb, c, axis, R, r, nM, nm, key, vol=None, phase=0.0):
    c = V(c)
    X, Y, Z = frame_for(axis)
    if vol is None:
        vol = mb.nv()
    rings = []
    for i in range(nM):
        a = phase + TAU * i / nM
        radial = X * math.cos(a) + Y * math.sin(a)
        cc = c + radial * R
        rings.append([(cc + radial * (r * math.cos(TAU * j / nm)) + Z * (r * math.sin(TAU * j / nm)), cc)
                      for j in range(nm)])
    for i in range(nM):
        A_, B_ = rings[i], rings[(i + 1) % nM]
        for j in range(nm):
            k = (j + 1) % nm
            pts = [A_[j][0], A_[k][0], B_[k][0], B_[j][0]]
            mid = sum((p for p in pts), V((0, 0, 0))) / 4.0
            ctr = (A_[j][1] + B_[j][1]) * 0.5
            face_toward(mb, pts, key, mid - ctr, vol)
    return vol


def ellipse_normal(a, b, t):
    return V((math.cos(t) / a, math.sin(t) / b, 0.0)).normalized()


def grid_wall(mb, axis_pos, side, ys, zs, holes, key_fn, vol=None, inward=True):
    """A wall in the plane x = axis_pos built from cells between the sorted cut lines ys x zs; cells inside any hole
    (y0, y1, z0, z1) are skipped. side = +1 / -1 is the wall's side of the car or hall; inward faces point to -side.
    key_fn(z0, z1) -> paint key for the row."""
    if vol is None:
        vol = mb.nv()
    nx = -side if inward else side
    for i in range(len(ys) - 1):
        for j in range(len(zs) - 1):
            y0, y1, z0, z1 = ys[i], ys[i + 1], zs[j], zs[j + 1]
            if y1 - y0 < 1e-4 or z1 - z0 < 1e-4:
                continue
            cy, cz = 0.5 * (y0 + y1), 0.5 * (z0 + z1)
            if any(h[0] - 1e-4 <= cy <= h[1] + 1e-4 and h[2] - 1e-4 <= cz <= h[3] + 1e-4 for h in holes):
                continue
            k = key_fn(z0, z1)
            if k is None:
                continue
            pts = [V((axis_pos, y0, z0)), V((axis_pos, y1, z0)), V((axis_pos, y1, z1)), V((axis_pos, y0, z1))]
            face_toward(mb, pts, k, V((nx, 0, 0)), vol)
    return vol


def rect_loop(x0, y0, x1, y1, z):
    return [V((x0, y0, z)), V((x1, y0, z)), V((x1, y1, z)), V((x0, y1, z))]


def boundary_loop(cells):
    """Outer boundary (CCW, grid units) of a set of unit cells (i, j); assumes one simply connected blob."""
    edges = {}
    for (i, j) in cells:
        for a, b in (((i, j), (i + 1, j)), ((i + 1, j), (i + 1, j + 1)), ((i + 1, j + 1), (i, j + 1)),
                     ((i, j + 1), (i, j))):
            if (b, a) in edges:
                del edges[(b, a)]
            else:
                edges[(a, b)] = True
    nxt = {}
    for a, b in edges:
        nxt.setdefault(a, []).append(b)
    start = min(nxt)
    loop = [start]
    cur = start
    prev_dir = None
    for _ in range(len(edges) + 2):
        cands = nxt[cur]
        b = cands[0]
        if len(cands) > 1 and prev_dir is not None:     # pinch point: turn left first
            b = max(cands, key=lambda q: (prev_dir[0] * (q[1] - cur[1]) - prev_dir[1] * (q[0] - cur[0])))
        prev_dir = (b[0] - cur[0], b[1] - cur[1])
        if b == start:
            break
        loop.append(b)
        cur = b
    # drop collinear points
    out = []
    n = len(loop)
    for k in range(n):
        a, b, c = loop[k - 1], loop[k], loop[(k + 1) % n]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(b)
    return out


# ================================================================================================ station
def coffer_grid():
    """Kept coffer cells (centre x, y in entrance-asset space) and the skipped cells round the oval."""
    y0, y1 = ENT_Y0 - OVAL_Y, ENT_Y1 - OVAL_Y
    x0 = -(WALL_X - 1.0)
    nx = int(round(2 * (WALL_X - 1.0) / COFFER))
    ny = int(round((y1 - y0) / COFFER))
    ea, eb = OVAL_A + 1.5, OVAL_B + 1.5
    skip, kept = set(), []
    for i in range(nx):
        for j in range(ny):
            cx0, cy0 = x0 + i * COFFER, y0 + j * COFFER
            if any(((cx0 + u * COFFER) / (ea + 1.2)) ** 2 + ((cy0 + v * COFFER) / (eb + 1.2)) ** 2 < 1.0
                   for u in (0, 0.5, 1) for v in (0, 0.5, 1)):
                skip.add((i, j))
            else:
                kept.append((cx0 + COFFER / 2, cy0 + COFFER / 2))
    return kept, skip, (x0, y0, nx, ny)


def build_coffer():
    A = Asset("Station_Coffer", "StationArch", "Train_Station.glb", tex_size=256, tags=["Station", "Ceiling",
                                                                                         "Modular"],
              pivot="on the floor under the cell centre (the soffit is 40 up)",
              notes="One 12 x 12 coffer of the entrance hall's concrete ceiling (1-stud chamfered rib soffit, a "
                    "sloped recess 4 deep, a round downlight), tiled 160 times round the oval (layout). Out of reach: "
                    "no collision.")
    mb = A.part("Concrete")
    li = A.part("Downlight", kind="neon", shadow=False)
    h = COFFER / 2
    z0, z1, z2 = CEIL_Z, CEIL_Z + 3.3, CEIL_Z + 4.0
    o = rect_loop(-h, -h, h, h, z0)
    r1 = rect_loop(-h + 0.5, -h + 0.5, h - 0.5, h - 0.5, z0)
    r2 = rect_loop(-h + 2.0, -h + 2.0, h - 2.0, h - 2.0, z1)
    r3 = rect_loop(-h + 2.35, -h + 2.35, h - 2.35, h - 2.35, z2)
    vol = mb.nv()
    for k in range(4):
        kk = (k + 1) % 4
        mb.face([o[k], r1[k], r1[kk], o[kk]], "concrete", vol)
        mb.face([r1[k], r2[k], r2[kk], r1[kk]], "coffer", vol)
        mb.face([r2[k], r3[k], r3[kk], r2[kk]], "coffer", vol)
    mb.face([r3[0], r3[3], r3[2], r3[1]], "coffer", vol)
    disc(li, (0, 0, z2 - 0.03), 0.75, 8, (0, 0, -1), "downlight")
    A.att("Downlight", (0, 0, z2 - 0.1), (0, 0, -1), (0, 1, 0),
          note="warm SpotLight (255, 214, 170), Brightness 1, Range 40, Angle 70, or a SurfaceLight on the disc")
    return A


def build_entrance_ceiling():
    A = Asset("Station_EntranceCeiling", "StationArch", "Train_Station.glb", tags=["Station", "Ceiling"],
              notes="The unique part of the entrance hall's coffered ceiling: the soffit collar round the 100 x 50 "
                    "oval with 28 radial ribs, the deep fascia ring that rises to the lantern, the perimeter strips "
                    "and the header wall over the shed's mouth. The regular coffers are Station_Coffer modules "
                    "(layout). Origin = the oval's centre on the floor. Out of reach: no collision.")
    mb = A.part("Concrete", collide=False)
    kept, skip, (x0, y0, nx, ny) = coffer_grid()
    y1 = y0 + ny * COFFER
    z0, z2 = CEIL_Z, CEIL_Z + 4.0
    ea, eb = OVAL_A + 1.5, OVAL_B + 1.5
    for s_ in (-1, 1):
        xa, xb = sorted((s_ * (WALL_X - 1.0), s_ * WALL_X))
        mb.face(list(reversed(rect_loop(xa, y0, xb, y1, z0))), "concrete")
    loop = boundary_loop(skip)
    outer = [V((x0 + i * COFFER, y0 + j * COFFER, z0)) for i, j in loop]
    n = 72
    inner = ellipse_pts(ea, eb, n, z0)
    poly_holes(mb, outer, [inner], "concrete", (0, 0, -1))

    def in_collar(px, py):
        return (math.floor((px - x0) / COFFER), math.floor((py - y0) / COFFER)) in skip
    for k in range(28):
        t = TAU * (k + 0.5) / 28
        d = V((math.cos(t), math.sin(t), 0.0))
        r_in = 1.0 / math.sqrt((d.x / ea) ** 2 + (d.y / eb) ** 2)
        r = r_in
        while in_collar(d.x * (r + 0.6), d.y * (r + 0.6)) and r < 200:
            r += 0.25
        if r - r_in < 1.5:
            continue
        beam(mb, d * r_in + V((0, 0, z0 - 0.45)), d * (r - 0.1) + V((0, 0, z0 - 0.45)), 0.9, 0.9, "concrete")
    a, b = OVAL_A, OVAL_B
    zf = CEIL_Z - 3.5
    loft(mb, [list(reversed(ellipse_pts(a, b, n, zf))), list(reversed(ellipse_pts(a, b, n, z2)))], "concrete")
    loft(mb, [ellipse_pts(ea, eb, n, zf), ellipse_pts(ea, eb, n, z0)], "concrete")
    ia, oa = ellipse_pts(a, b, n, zf), ellipse_pts(ea, eb, n, zf)
    vol = mb.nv()
    for i in range(n):
        j = (i + 1) % n
        mb.face([ia[i], ia[j], oa[j], oa[i]][::-1], "concrete", vol)
    box(mb, (-WALL_X, y0 - 1.0, CEIL_Z), (WALL_X, y0, SHED_H + 2.0), "concrete", skip=("+y", "+z", "-x", "+x"))
    return A


def build_lantern():
    A = Asset("Station_Lantern", "StationArch", "Train_Station.glb", tags=["Station", "Ceiling"],
              notes="Elliptical drum (z 44-72) and coffered dome above the oval: 24 pilasters, 24 radial ribs, a "
                    "ring rib and a hub the sculpture hangs from. Origin = the oval's centre on the floor.")
    mb = A.part("Concrete")
    li = A.part("Downlights", kind="neon", shadow=False)
    a, b, n = OVAL_A, OVAL_B, 72
    z0, z1 = CEIL_Z + 4.0, LANTERN_Z
    loft(mb, [list(reversed(ellipse_pts(a, b, n, z0))), list(reversed(ellipse_pts(a, b, n, z1)))], "concrete")
    mb.face(list(reversed(ellipse_pts(a, b, n, z1))), "coffer")
    for k in range(24):
        t = TAU * (k + 0.5) / 24
        p = V((a * math.cos(t), b * math.sin(t), 0.5 * (z0 + z1)))
        nrm = -ellipse_normal(a, b, t)
        tan = V((-a * math.sin(t), b * math.cos(t), 0)).normalized()
        obox(mb, p + nrm * 0.45, (tan, nrm, UP), (0.6, 0.5, 0.5 * (z1 - z0)), "concrete", ch=0.1)
    for k in range(24):
        t = TAU * k / 24
        pin = V((0.17 * a * math.cos(t), 0.17 * b * math.sin(t), z1 - 0.7))
        pout = V((0.985 * a * math.cos(t), 0.985 * b * math.sin(t), z1 - 0.7))
        beam(mb, pin, pout, 1.0, 1.4, "concrete")
    for sc, w in ((0.58, 1.2),):
        ra, rb = sc * a, sc * b
        zt, zb = z1, z1 - 1.5
        loft(mb, [ellipse_pts(ra + w / 2, rb + w / 2, n, zb), ellipse_pts(ra + w / 2, rb + w / 2, n, zt)], "concrete")
        loft(mb, [list(reversed(ellipse_pts(ra - w / 2, rb - w / 2, n, zb))),
                  list(reversed(ellipse_pts(ra - w / 2, rb - w / 2, n, zt)))], "concrete")
        ia, oa = ellipse_pts(ra - w / 2, rb - w / 2, n, zb), ellipse_pts(ra + w / 2, rb + w / 2, n, zb)
        vol = mb.nv()
        for i in range(n):
            j = (i + 1) % n
            mb.face([oa[i], oa[j], ia[j], ia[i]], "concrete", vol)
    hub = ellipse_pts(0.17 * a, 0.17 * b, 24, z1 - 1.2)
    loft(mb, [hub, [p + V((0, 0, 1.2)) for p in hub]], "concrete", cap0=True)
    for k in range(24):
        t = TAU * (k + 0.5) / 24
        for sc in (0.38, 0.8):
            disc(li, (sc * a * math.cos(t), sc * b * math.sin(t), z1 - 0.05), 0.6, 8, (0, 0, -1), "downlight")
    return A


def blade(mb, p0, p1, s, rng, segs=14):
    p0, p1 = V(p0), V(p1)
    L = (p1 - p0).length
    path, secs = [], []
    tw0 = rng.uniform(-0.1, 0.1)
    for k in range(segs + 1):
        u = k / segs
        p = p0.lerp(p1, u) - UP * (0.045 * L * math.sin(math.pi * u))
        path.append(p)
        w = 1.2 + 5.4 * u ** 0.8
        th = 0.6 + 1.3 * u
        tw = tw0 + s * 0.22 * u
        base = [(-0.5 * w, -0.05 * th), (-0.22 * w, -0.5 * th), (0.24 * w, -0.45 * th), (0.5 * w, 0.0),
                (0.2 * w, 0.5 * th), (-0.25 * w, 0.42 * th)]
        c, sn = math.cos(tw), math.sin(tw)
        secs.append([(x * c - y * sn, x * sn + y * c) for x, y in base])
    # chisel tip
    d = (p1 - p0).normalized()
    path.append(p1 + d * 1.6 + UP * 0.4)
    secs.append([(0.55 * x, 0.3 * y) for x, y in secs[-1]])
    return sweep(mb, path, lambda k: secs[k], "gold", up=V((0.0, 0.55, 0.83)), cap0=True, cap1=True)


def build_sunburst():
    A = Asset("Station_Sunburst", "Sculpture", "Train_Station.glb", tags=["Station", "Sculpture"],
              notes="Our own sculpture in the film's spirit: 10 long tapered gold blades in two fans of five, "
                    "gathered by two collars at the centre and rising to the drum's rim (40-52 studs long, 6-sided "
                    "sections, a slight sag and twist), with a faceted gold drop between the collars. Hung from the "
                    "lantern by steel rods. Brushed gold: metalness 0.9, roughness 0.3. Origin = the oval's centre on "
                    "the floor.")
    g = A.part("Gold")
    rods = A.part("Rods", shadow=False)
    rng = random.Random(SEED + 11)
    hub_z = 32.0
    top = LANTERN_Z - 0.2
    for s in (-1, 1):
        for k, psi in enumerate((-58, -29, 0, 29, 58)):
            t = math.radians(psi)
            p0 = V((s * 3.3, 1.1 * math.sin(t), hub_z - 0.3 * math.cos(t)))
            ang = t if s > 0 else math.pi - t
            p1 = V(((OVAL_A - 3.5) * math.cos(ang), (OVAL_B - 3.0) * math.sin(ang), 45.5 + 2.5 * math.cos(t)))
            blade(g, p0, p1, s, rng)
            cyl(rods, p1 + V((0, 0, 0.6)), V((p1.x, p1.y, top)), 0.13, 0.13, 4, "steel")
        torus(g, (s * 4.4, 0, hub_z), (1, 0, 0), 1.9, 0.5, 10, 4, "gold")
        cyl(rods, (s * 4.4, 0, hub_z + 2.3), (s * 4.4, 0, top), 0.13, 0.13, 4, "steel")
    lathe(g, [(0.0, 19.5), (1.0, 20.8), (1.8, 22.9), (2.1, 25.3), (1.7, 27.8), (0.9, 29.8), (0.45, 31.2),
              (0.45, 32.6), (0.0, 32.8)], 8, "gold")
    cyl(rods, (0, 0, 32.7), (0, 0, top), 0.16, 0.16, 4, "steel")
    return A


def build_entrance_walls():
    A = Asset("Station_EntranceWalls", "StationArch", "Train_Station.glb", tags=["Station", "Wall"],
              notes="The entrance hall's side walls (columns, a stone base with service doors, tall bronze-framed "
                    "glazing glowing amber from behind) and the end wall (three glass doorways, clerestory). Origin = "
                    "the oval's centre on the floor. Collision: use the colliders (mesh parts are visual).")
    c = A.part("Walls")
    gl = A.part("Glass", kind="glass")
    glow = A.part("Glow", kind="neon", shadow=False)
    y0, y1 = ENT_Y0 - OVAL_Y, ENT_Y1 - OVAL_Y
    cols = [y0 + 1.5] + [y0 + (y1 - y0) * k / 5.0 for k in range(1, 5)] + [y1 - 1.5]
    for s in (-1, 1):
        xi, xo = s * (WALL_X - 3.0), s * (WALL_X + 0.5)
        for cy in cols:
            cbox(c, (min(xi, xo), cy - 1.5, 0), (max(xi, xo), cy + 1.5, CEIL_Z), "concrete", ch=0.3)
        for k in range(len(cols) - 1):
            ya, yb = cols[k] + 1.5, cols[k + 1] - 1.5
            ym = 0.5 * (ya + yb)
            xw, xb = s * (WALL_X - 0.5), s * (WALL_X + 0.5)
            # stone base with a recessed service door
            grid_wall(c, xw, s, [ya, ym - 2.0, ym + 2.0, yb], [0.0, DOOR_H, 10.0],
                      [(ym - 2.0, ym + 2.0, 0.0, DOOR_H)], lambda z0, z1: "concrete")
            face_toward(c, [V((s * (WALL_X + 0.2), ym - 2.0, 0)), V((s * (WALL_X + 0.2), ym + 2.0, 0)),
                            V((s * (WALL_X + 0.2), ym + 2.0, DOOR_H)), V((s * (WALL_X + 0.2), ym - 2.0, DOOR_H))],
                        "wood_dark", V((-s, 0, 0)))
            for (pa, pb) in (((ym - 2.0, 0), (ym - 2.0, DOOR_H)), ((ym + 2.0, 0), (ym + 2.0, DOOR_H))):
                face_toward(c, [V((xw, pa[0], pa[1])), V((s * (WALL_X + 0.2), pa[0], pa[1])),
                                V((s * (WALL_X + 0.2), pb[0], pb[1])), V((xw, pb[0], pb[1]))], "concrete",
                            V((0, -1 if pa[0] > ym else 1, 0)))
            face_toward(c, [V((xw, ym - 2.0, DOOR_H)), V((xw, ym + 2.0, DOOR_H)),
                            V((s * (WALL_X + 0.2), ym + 2.0, DOOR_H)), V((s * (WALL_X + 0.2), ym - 2.0, DOOR_H))],
                        "concrete", V((0, 0, -1)))
            cbox(c, (min(s * (WALL_X - 1.2), xb), ya, 9.6), (max(s * (WALL_X - 1.2), xb), yb, 10.6), "concrete",
                 ch=0.15)
            # bronze glazing frame: mullions every ~4, transoms
            nm = max(1, int(round((yb - ya) / 4.0)))
            for m in range(nm + 1):
                yy = ya + (yb - ya) * m / nm
                box(c, (min(s * (WALL_X - 0.6), s * (WALL_X + 0.3)), yy - 0.25, 10.6),
                    (max(s * (WALL_X - 0.6), s * (WALL_X + 0.3)), yy + 0.25, 38.0), "bronze",
                    skip=("+x" if s > 0 else "-x", "-z", "+z"))
            for zt in (17.0, 24.0, 31.0):
                box(c, (min(s * (WALL_X - 0.5), s * (WALL_X + 0.3)), ya, zt - 0.25),
                    (max(s * (WALL_X - 0.5), s * (WALL_X + 0.3)), yb, zt + 0.25), "bronze",
                    skip=("+x" if s > 0 else "-x", "-y", "+y"))
            box(c, (min(s * (WALL_X - 0.5), xb), ya, 38.0), (max(s * (WALL_X - 0.5), xb), yb, CEIL_Z), "concrete",
                skip=("+z",))
            box(gl, (min(s * WALL_X, s * (WALL_X + 0.1)), ya, 10.6), (max(s * WALL_X, s * (WALL_X + 0.1)), yb, 38.0),
                "glass", skip=("-y", "+y", "-z", "+z"))
        face_toward(glow, [V((s * 89.0, y0, 0)), V((s * 89.0, y1, 0)), V((s * 89.0, y1, CEIL_Z + 4)),
                           V((s * 89.0, y0, CEIL_Z + 4))], "glow", V((-s, 0, 0)))
        A.collider((s * (WALL_X - 0.5), y0, 0), (s * (WALL_X + 1.5), y1, CEIL_Z))
    # end wall (hall entrance) with three doorways and a clerestory
    ye = y1
    doors = [(-34.0, -26.0), (-4.0, 4.0), (26.0, 34.0)]
    xs = sorted({-WALL_X, WALL_X} | {d for p in doors for d in p})
    holes = [(d0, d1, 0.0, 10.0) for d0, d1 in doors]
    for i in range(len(xs) - 1):
        for (za, zb) in ((0.0, 10.0), (10.0, 14.0), (36.0, CEIL_Z)):
            xa, xb = xs[i], xs[i + 1]
            cx_, cz_ = 0.5 * (xa + xb), 0.5 * (za + zb)
            if any(h[0] <= cx_ <= h[1] and h[2] <= cz_ <= h[3] for h in holes):
                continue
            face_toward(c, [V((xa, ye, za)), V((xb, ye, za)), V((xb, ye, zb)), V((xa, ye, zb))], "concrete",
                        V((0, -1, 0)))
    for d0, d1 in doors:
        for xx in (d0, d1):
            face_toward(c, [V((xx, ye, 0)), V((xx, ye + 1.0, 0)), V((xx, ye + 1.0, 10)), V((xx, ye, 10))],
                        "concrete", V((1 if xx == d0 else -1, 0, 0)))
        face_toward(c, [V((d0, ye, 10)), V((d1, ye, 10)), V((d1, ye + 1.0, 10)), V((d0, ye + 1.0, 10))],
                    "concrete", V((0, 0, -1)))
        cbox(c, (d0, ye + 0.3, 0), (d0 + 0.3, ye + 0.6, 10), "bronze", ch=0.05)
        cbox(c, (d1 - 0.3, ye + 0.3, 0), (d1, ye + 0.6, 10), "bronze", ch=0.05)
        cbox(c, (0.5 * (d0 + d1) - 0.15, ye + 0.3, 0), (0.5 * (d0 + d1) + 0.15, ye + 0.6, 10), "bronze", ch=0.05)
        box(gl, (d0, ye + 0.42, 0), (d1, ye + 0.48, 10), "glass", skip=("-x", "+x", "-z", "+z"))
    for m in range(43):
        xx = -WALL_X + 4.0 * m
        if xx > WALL_X:
            break
        box(c, (xx - 0.25, ye - 0.3, 14.0), (xx + 0.25, ye + 0.4, 36.0), "bronze", skip=("+y", "-z", "+z"))
    for zt in (14.0, 25.0, 36.0):
        cbox(c, (-WALL_X, ye - 0.3, zt - 0.3), (WALL_X, ye + 0.4, zt + 0.3), "bronze", ch=0.06)
    box(gl, (-WALL_X, ye + 0.1, 14.0), (WALL_X, ye + 0.2, 36.0), "glass", skip=("-x", "+x", "-z", "+z"))
    face_toward(glow, [V((-WALL_X, ye + 5, 0)), V((WALL_X, ye + 5, 0)), V((WALL_X, ye + 5, CEIL_Z)),
                       V((-WALL_X, ye + 5, CEIL_Z))], "glow", V((0, -1, 0)))
    A.collider((-WALL_X, ye, 0), (WALL_X, ye + 1.5, CEIL_Z))
    return A


def build_entrance_floor():
    A = Asset("Station_EntranceFloor", "StationArch", "Train_Station.glb", tags=["Station", "Floor", "Walkable"],
              notes="Polished stone floor of the entrance hall (6-stud slabs, roughness 0.4) with our own brass "
                    "'sunrise' inlay at the shed's mouth; the guideway pits' end walls and buffer stops. Origin = the "
                    "oval's centre on the floor.")
    f = A.part("Floor")
    y0, y1 = ENT_Y0 - OVAL_Y, ENT_Y1 - OVAL_Y
    xs = [-WALL_X] + [-81.0 + 6.0 * i for i in range(28)] + [WALL_X]
    ys = [y0 + 6.0 * j for j in range(int(round((y1 - y0) / 6.0)) + 1)]
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            f.face(rect_loop(xs[i], ys[j], xs[i + 1], ys[j + 1], 0.0), "floor", f.nv())
    # inlay: a darker stone half-disc with brass rays and arcs (our own sunrise)
    cy = y0
    hd = [V((0, cy, 0.008))] + [V((20.0 * math.cos(math.radians(a)), cy + 20.0 * math.sin(math.radians(a)), 0.008))
                                for a in range(0, 181, 10)]
    f.face(hd, "floor_light")
    for a in range(10, 171, 20):
        t = math.radians(a)
        d, nx_ = V((math.cos(t), math.sin(t), 0)), V((-math.sin(t), math.cos(t), 0))
        p0, p1 = V((0, cy, 0.016)) + d * 3.0, V((0, cy, 0.016)) + d * 19.0
        f.face([p0 - nx_ * 0.3, p1 - nx_ * 0.15, p1 + nx_ * 0.15, p0 + nx_ * 0.3], "brass")
    for r in (8.0, 20.0):
        for k in range(18):
            ta, tb = math.radians(10 * k), math.radians(10 * (k + 1))
            pa = [V((rr * math.cos(t), cy + rr * math.sin(t), 0.016)) for rr, t in
                  ((r - 0.25, ta), (r + 0.25, ta), (r + 0.25, tb), (r - 0.25, tb))]
            f.face(pa, "brass")
    # the pits' end walls and buffer stops (the guideway bays start at the shed's mouth)
    for s in (-1, 1):
        xa, xb = sorted((s * PLAT_X, s * WALL_X))
        face_toward(f, [V((xa, y0, PIT_Z)), V((xb, y0, PIT_Z)), V((xb, y0, 0)), V((xa, y0, 0))], "concrete_dark",
                    V((0, -1, 0)))
        bx = s * TRACK_X
        cbox(f, (bx - 3.2, y0 - 2.2, PIT_Z), (bx + 3.2, y0, -0.6), "concrete_dark", ch=0.2)
        cbox(f, (bx - 2.6, y0 - 2.5, -3.4), (bx + 2.6, y0 - 2.1, -1.2), "steel_dark", ch=0.08)
    A.collider((-WALL_X, y0, -1.0), (WALL_X, y1, 0.0), "Floor")
    for s in (-1, 1):
        A.collider((s * TRACK_X - 3.2, y0 - 2.5, PIT_Z), (s * TRACK_X + 3.2, y0, -0.6))
    return A


def build_portal():
    A = Asset("Station_Portal", "StationArch", "Train_Station.glb", tags=["Station", "Portal"],
              notes="The white cross-beam (6 high) at the shed's mouth on four columns, carrying our own gold emblem "
                    "(a rayed disc and bars; no lettering). Origin = floor centre at the shed's mouth (hall y 126).")
    c = A.part("Steel")
    cbox(c, (-WALL_X, -1.0, 24.0), (WALL_X, 1.0, 30.0), "white_steel", ch=0.25)
    for x in (-61.5, -33.0, 33.0, 61.5):
        cbox(c, (x - 0.9, -0.9, 0.6), (x + 0.9, 0.9, 24.0), "white_steel", ch=0.15)
        cbox(c, (x - 1.3, -1.3, 0.0), (x + 1.3, 1.3, 0.6), "concrete", ch=0.1)
        A.collider((x - 1.3, -1.3, 0), (x + 1.3, 1.3, 24.0))
    # our emblem: a rayed gold disc on the beam, flanked by bars
    cyl(c, (0, -0.35, 33.6), (0, 0.35, 33.6), 2.6, 2.6, 16, "gold")
    cyl(c, (0, -0.55, 33.6), (0, 0.55, 33.6), 1.2, 1.2, 12, "gold")
    for k in range(9):
        a = math.radians(-80 + 20 * k)
        d = V((math.sin(a), 0, math.cos(a)))
        n_ = V((math.cos(a), 0, -math.sin(a)))
        p0, p1 = V((0, 0, 33.6)) + d * 2.9, V((0, 0, 33.6)) + d * 6.0
        hull(c, [p0 + n_ * 0.4 + V((0, -0.25, 0)), p0 - n_ * 0.4 + V((0, -0.25, 0)), p0 + n_ * 0.4 + V((0, 0.25, 0)),
                 p0 - n_ * 0.4 + V((0, 0.25, 0)), p1 + n_ * 0.08 + V((0, -0.2, 0)), p1 - n_ * 0.08 + V((0, -0.2, 0)),
                 p1 + n_ * 0.08 + V((0, 0.2, 0)), p1 - n_ * 0.08 + V((0, 0.2, 0))], "gold")
    cbox(c, (-14.0, -0.3, 30.0), (14.0, 0.3, 30.7), "gold", ch=0.08)
    for s in (-1, 1):
        cbox(c, (min(s * 17.0, s * 58.0), -0.25, 30.7), (max(s * 17.0, s * 58.0), 0.25, 31.2), "gold", ch=0.06)
    return A


def build_shed_bay():
    A = Asset("Station_ShedBay", "StationArch", "Train_Station.glb", tags=["Station", "Shed", "Modular"],
              notes="One 24-stud slice of the train shed, repeated 14 times (+4 as backdrop): glazed walls 60 high "
                    "with white mullions every 6 studs and stepped fins (deep low, shallow high), transoms, the "
                    "amber-pink glow behind the glass (emissive backdrop: add warm SurfaceLights facing in), the roof's "
                    "white beams every 6 studs and purlins under roof glazing. Origin = the slice's floor centre.")
    st = A.part("Steel")
    gl = A.part("Glass", kind="glass")
    glow = A.part("Glow", kind="neon", shadow=False)
    glr = A.part("GlowRoof", kind="neon", shadow=False)
    h = BAY / 2.0
    for s in (-1, 1):
        def X(a, b):
            return min(s * a, s * b), max(s * a, s * b)
        xa, xb = X(WALL_X - 1.0, WALL_X + 0.5)
        box(st, (xa, -h, PIT_Z), (xb, h, 4.0), "concrete_dark", skip=("-y", "+y", "-z"))
        for y in (-12.0, -6.0, 0.0, 6.0):
            ma, mb_ = X(WALL_X - 0.6, WALL_X + 0.4)
            cbox(st, (ma, y - 0.3, 4.0), (mb_, y + 0.3, SHED_H), "white_steel", ch=0.08)
            for (za, zb, dep) in ((4.0, 22.0, 3.2), (22.0, 40.0, 2.4), (40.0, SHED_H, 1.6)):
                fa, fb = X(WALL_X - 0.6 - dep, WALL_X - 0.6)
                cbox(st, (fa, y - 0.25, za), (fb, y + 0.25, zb - 0.02), "white_steel", ch=0.08)
        for zt in (22.0, 40.0):
            ta, tb = X(WALL_X - 0.5, WALL_X + 0.3)
            cbox(st, (ta, -h, zt - 0.25), (tb, h, zt + 0.25), "white_steel", ch=0.06)
        ga, gb = X(WALL_X + 0.45, WALL_X + 0.55)
        box(gl, (ga, -h, 4.0), (gb, h, SHED_H), "glass", skip=("-y", "+y", "-z", "+z"))
        face_toward(glow, [V((s * 90.0, -h, PIT_Z)), V((s * 90.0, h, PIT_Z)), V((s * 90.0, h, SHED_H + 6)),
                           V((s * 90.0, -h, SHED_H + 6))], "glow", V((-s, 0, 0)))
        A.collider((s * (WALL_X - 1.0), -h, PIT_Z), (s * (WALL_X + 1.0), h, SHED_H))
    for y in (-12.0, 0.0):
        cbox(st, (-WALL_X, y - 0.5, SHED_H - 2.6), (WALL_X, y + 0.5, SHED_H), "white_steel", ch=0.12)
    for y in (-6.0, 6.0):
        cbox(st, (-WALL_X, y - 0.3, SHED_H - 1.4), (WALL_X, y + 0.3, SHED_H), "white_steel", ch=0.08)
    for x in (-51.0, -17.0, 17.0, 51.0):
        cbox(st, (x - 0.4, -h, SHED_H - 1.2), (x + 0.4, h, SHED_H), "white_steel", ch=0.08)
    box(gl, (-WALL_X, -h, SHED_H), (WALL_X, h, SHED_H + 0.1), "glass", skip=("-x", "+x", "-y", "+y"))
    glr.face(list(reversed(rect_loop(-WALL_X, -h, WALL_X, h, SHED_H + 5.0))), "glow_roof")
    return A


def build_floor_bay():
    A = Asset("Station_FloorBay", "StationArch", "Train_Station.glb", tags=["Station", "Floor", "Walkable",
                                                                            "Modular"],
              notes="One 24-stud slice of floor: the concourse (66) and two platforms (30) in polished stone slabs, "
                    "a muted edge band and nosing, the guideway pits (22, floor at -5) with the maglev T-beam and its "
                    "guide rails under each track (no sleepers, no rails to ride on). Origin = the slice's floor "
                    "centre.")
    f = A.part("Floor")
    h = BAY / 2.0
    xs = [-CONC_X + 6.0 * i for i in range(12)]
    for i in range(len(xs) - 1):
        for y in (-h, -6.0, 0.0, 6.0):
            f.face(rect_loop(xs[i], y, xs[i + 1], y + 6.0, 0.0), "floor", f.nv())
    for s in (-1, 1):
        px = [CONC_X + (PLAT_X - 1.6 - CONC_X) * k / 5.0 for k in range(6)]
        for i in range(5):
            xa, xb = sorted((s * px[i], s * px[i + 1]))
            for y in (-h, -6.0, 0.0, 6.0):
                f.face(rect_loop(xa, y, xb, y + 6.0, 0.0), "floor", f.nv())
        xa, xb = sorted((s * (PLAT_X - 1.6), s * (PLAT_X - 0.45)))
        f.face(rect_loop(xa, -h, xb, h, 0.0), "edge_strip")
        e0, e1 = s * (PLAT_X - 0.45), s * PLAT_X
        face_toward(f, [V((e0, -h, 0)), V((e0, h, 0)), V((e1, h, -0.35)), V((e1, -h, -0.35))], "concrete",
                    V((s, 0, 1)))
        face_toward(f, [V((e1, -h, -0.35)), V((e1, h, -0.35)), V((e1, h, PIT_Z)), V((e1, -h, PIT_Z))],
                    "concrete_dark", V((s, 0, 0)))
        xa, xb = sorted((s * PLAT_X, s * WALL_X))
        f.face(rect_loop(xa, -h, xb, h, PIT_Z), "concrete_dark", f.nv())
        tx = s * TRACK_X
        box(f, (tx - 2.0, -h, PIT_Z), (tx + 2.0, h, -3.4), "guideway", skip=("-y", "+y", "-z"))
        cbox(f, (tx - 4.7, -h, -3.4), (tx + 4.7, h, -2.65), "guideway", ch=0.15)
        for gx in (-4.15, 4.15):
            cbox(f, (tx + gx - 0.3, -h, -2.65), (tx + gx + 0.3, h, -2.45), "steel", ch=0.05)
        A.collider((xa, -h, PIT_Z - 1.0), (xb, h, PIT_Z), "Floor")
        A.collider((tx - 4.7, -h, PIT_Z), (tx + 4.7, h, -2.45))
    A.collider((-PLAT_X, -h, -1.0), (PLAT_X, h, 0.0), "Floor")
    return A


def build_shed_end():
    A = Asset("Station_ShedEnd", "StationArch", "Train_Station.glb", tags=["Station", "Backdrop"],
              notes="The far end of the shed, open to the light: a white portal frame, a glazed upper band with fins, "
                    "a pale apron and the glow beyond; the pits and maglev beams run 180 studs out under the parked "
                    "trains. Origin = floor centre at the end (hall y -354).")
    st = A.part("Steel")
    gl = A.part("Glass", kind="glass", shadow=False)
    glow = A.part("Glow", kind="neon", shadow=False)
    for s_ in (-1, 1):
        xa, xb = sorted((s_ * (WALL_X - 1.0), s_ * (WALL_X + 2.0)))
        cbox(st, (xa, -1.5, PIT_Z), (xb, 1.5, SHED_H + 2.0), "white_steel", ch=0.2)
    cbox(st, (-WALL_X - 2.0, -1.5, SHED_H - 4.0), (WALL_X + 2.0, 1.5, SHED_H + 2.0), "white_steel", ch=0.2)
    cbox(st, (-WALL_X, -1.0, 24.0), (WALL_X, 1.0, 26.0), "white_steel", ch=0.15)
    for m in range(29):
        x = -WALL_X + 6.0 * m
        if abs(x) > WALL_X - 1:
            continue
        cbox(st, (x - 0.3, -0.4, 26.0), (x + 0.3, 1.6, SHED_H - 4.0), "white_steel", ch=0.06)
    box(gl, (-WALL_X, -0.05, 26.0), (WALL_X, 0.05, SHED_H - 4.0), "glass", skip=("-x", "+x", "-z", "+z"))
    st.face(rect_loop(-PLAT_X, -60.0, PLAT_X, 0.0, 0.0), "concrete")
    face_toward(glow, [V((-WALL_X - 60, -70.0, PIT_Z)), V((WALL_X + 60, -70.0, PIT_Z)),
                       V((WALL_X + 60, -70.0, SHED_H + 30)), V((-WALL_X - 60, -70.0, SHED_H + 30))], "glow",
                V((0, 1, 0)))
    for s_ in (-1, 1):
        tx = s_ * TRACK_X
        xa, xb = sorted((s_ * PLAT_X, s_ * WALL_X))
        st.face(rect_loop(xa, -180.0, xb, -1.0, PIT_Z), "concrete_dark")
        box(st, (tx - 2.0, -180.0, PIT_Z), (tx + 2.0, -1.0, -3.4), "guideway", skip=("-y", "+y", "-z"))
        cbox(st, (tx - 4.7, -180.0, -3.4), (tx + 4.7, -1.0, -2.65), "guideway", ch=0.15)
        A.collider((tx - 4.7, -180.0, PIT_Z), (tx + 4.7, -1.0, -2.45))
        e0 = s_ * PLAT_X
        face_toward(st, [V((e0, -60.0, 0.0)), V((e0, 0.0, 0.0)), V((e0, 0.0, PIT_Z)), V((e0, -60.0, PIT_Z))],
                    "concrete_dark", V((s_, 0, 0)))
    A.collider((-PLAT_X, -60.0, -1.0), (PLAT_X, 0.0, 0.0), "Floor")
    return A


# ------------------------------------------------------------------------------------------------ station props
def banner_wave(x, z):
    return 0.10 * math.sin(1.5 * x + 0.33 * z) + 0.05 * math.sin(0.7 * x - 0.5 * z)


def banner_outline():
    return [(-2.5, -0.3), (2.5, -0.3), (2.5, -15.5), (0.0, -18.5), (-2.5, -15.5)]


def inset_poly(poly, d):
    """Inset a convex CCW polygon (x, z) by d."""
    n = len(poly)
    lines = []
    for i in range(n):
        a, b = V((*poly[i], 0)), V((*poly[(i + 1) % n], 0))
        t = (b - a).normalized()
        nrm = V((-t.y, t.x, 0))          # left normal = inward for CCW
        lines.append((a + nrm * d, t))
    out = []
    for i in range(n):
        p1, t1 = lines[i - 1]
        p2, t2 = lines[i]
        den = t1.x * t2.y - t1.y * t2.x
        if abs(den) < 1e-9:
            out.append((p2.x, p2.y))
            continue
        u = ((p2.x - p1.x) * t2.y - (p2.y - p1.y) * t2.x) / den
        q = p1 + t1 * u
        out.append((q.x, q.y))
    return out


def build_banner():
    A = Asset("Station_Banner", "Prop", "Train_StationProps.glb", tset="Station_Kit", tex_size=512,
              tags=["Station", "Banner", "Sways"], pivot="the rod's centre (hang point); the cable runs 24 up",
              notes="Narrow maroon-brown banner (5 x 18) with a pointed bottom, hanging from a brass rod; our own gold "
                    "motif on both faces (a border, a rising half-sun with rays, a bar and a chevron), never the film's "
                    "arrow and roundel. Sways as one piece (separate mesh); the Cable part stretches to the beam above.")
    cl = A.part("Cloth", shadow=True)
    cab = A.part("Cable", shadow=False)
    ol = banner_outline()
    cols = [-2.5, -1.25, 0.0, 1.25, 2.5]
    rows = [-0.3, -3.3, -6.3, -9.3, -12.3, -15.5]

    def zb(x):
        return -15.5 - 1.2 * (2.5 - abs(x))
    th = 0.06
    vol = cl.nv()
    for side in (1, -1):
        for i in range(4):
            for r in range(5):
                xa, xb, za, zb_ = cols[i], cols[i + 1], rows[r], rows[r + 1]
                pts = [V((xa, side * th + banner_wave(xa, za), za)), V((xb, side * th + banner_wave(xb, za), za)),
                       V((xb, side * th + banner_wave(xb, zb_), zb_)), V((xa, side * th + banner_wave(xa, zb_), zb_))]
                face_toward(cl, pts, "banner", V((0, side, 0)), vol)
            xa, xb = cols[i], cols[i + 1]
            pts = [V((xa, side * th + banner_wave(xa, -15.5), -15.5)), V((xb, side * th + banner_wave(xb, -15.5), -15.5)),
                   V((xb, side * th + banner_wave(xb, zb(xb)), zb(xb))),
                   V((xa, side * th + banner_wave(xa, zb(xa)), zb(xa)))]
            face_toward(cl, pts, "banner", V((0, side, 0)), vol)
    edge = [(x, -0.3) for x in cols[::-1]]
    edge = [(2.5, -0.3)] + [(2.5, z) for z in rows[1:]] + [(x, zb(x)) for x in (1.25, 0.0, -1.25)] + \
           [(-2.5, z) for z in rows[::-1][:-1]] + [(-2.5, -0.3)] + [(x, -0.3) for x in (-1.25, 0.0, 1.25)]
    for k in range(len(edge)):
        (xa, za), (xb, zb_) = edge[k], edge[(k + 1) % len(edge)]
        pts = [V((xa, th + banner_wave(xa, za), za)), V((xb, th + banner_wave(xb, zb_), zb_)),
               V((xb, -th + banner_wave(xb, zb_), zb_)), V((xa, -th + banner_wave(xa, za), za))]
        mid = V((0.5 * (xa + xb), 0, 0.5 * (za + zb_)))
        face_toward(cl, pts, "banner", mid - V((0, 0, -8.0)), vol)

    def motif(side):
        off = side * (th + 0.045)

        def P(x, z):
            return V((x, off + banner_wave(x, z), z))
        o1, o2 = inset_poly(ol, 0.35), inset_poly(ol, 0.6)
        for k in range(len(o1)):
            k2 = (k + 1) % len(o1)
            face_toward(cl, [P(*o1[k]), P(*o1[k2]), P(*o2[k2]), P(*o2[k])], "banner_gold", V((0, side, 0)))
        cz = -6.2
        half = [P(0.0, cz)] + [P(1.25 * math.cos(math.radians(a)), cz + 1.25 * math.sin(math.radians(a)))
                               for a in range(0, 181, 20)]
        face_toward(cl, half, "banner_gold", V((0, side, 0)))
        for a in range(15, 166, 30):
            t = math.radians(a)
            d, nn = (math.cos(t), math.sin(t)), (-math.sin(t), math.cos(t))
            r0, r1 = 1.5, 2.35
            face_toward(cl, [P(d[0] * r0 + nn[0] * 0.17, cz + d[1] * r0 + nn[1] * 0.17),
                             P(d[0] * r0 - nn[0] * 0.17, cz + d[1] * r0 - nn[1] * 0.17),
                             P(d[0] * r1, cz + d[1] * r1)], "banner_gold", V((0, side, 0)))
        face_toward(cl, [P(-1.6, cz - 0.55), P(1.6, cz - 0.55), P(1.6, cz - 0.25), P(-1.6, cz - 0.25)],
                    "banner_gold", V((0, side, 0)))
        face_toward(cl, [P(-0.17, -8.0), P(0.17, -8.0), P(0.17, -13.0), P(-0.17, -13.0)], "banner_gold",
                    V((0, side, 0)))
        for sx in (-1, 1):
            face_toward(cl, [P(0.0, -14.5), P(0.0, -14.05), P(sx * 1.1, -13.25), P(sx * 1.1, -13.7)],
                        "banner_gold", V((0, side, 0)))
    motif(1)
    motif(-1)
    cyl(cl, (-3.0, 0, 0), (3.0, 0, 0), 0.18, 0.18, 6, "brass")
    for s in (-1, 1):
        hull(cl, [(s * 3.0, 0, 0.0), (s * 3.25, 0.22, 0), (s * 3.25, -0.22, 0), (s * 3.25, 0, 0.22),
                  (s * 3.25, 0, -0.22), (s * 3.55, 0, 0)], "brass")
    cyl(cab, (0, 0, 0.15), (0, 0, 24.0), 0.08, 0.08, 4, "steel")
    A.att("Hang", (0, 0, 24.0), (0, 0, 1), (0, 1, 0), note="top of the cable: weld to the roof beam above")
    return A


def build_board():
    A = Asset("Station_Board", "Prop", "Train_StationProps.glb", tset="Station_Kit", tex_size=512, tags=["Station", "Sign"],
              notes="Departure board 10 x 5 on two posts (board z 11-16), with rows of our own abstract glyph "
                    "blocks in white and amber on both faces (no words, no film text). Glyphs are Neon parts.")
    fr = A.part("Frame")
    gw = A.part("Glyphs", kind="neon", shadow=False)
    ga = A.part("GlyphsAmber", kind="neon", shadow=False)
    for x in (-3.8, 3.8):
        cbox(fr, (x - 0.22, -0.22, 0.0), (x + 0.22, 0.22, 11.1), "steel_dark", ch=0.05)
        cbox(fr, (x - 0.45, -0.45, 0.0), (x + 0.45, 0.45, 0.25), "steel_dark", ch=0.05)
    cbox(fr, (-5.0, -0.35, 11.0), (5.0, 0.35, 16.0), "board", ch=0.12)
    rng = random.Random(SEED + 23)
    for side in (1, -1):
        yy = side * 0.36
        face_toward(fr, [V((-4.7, yy, 15.0)), V((4.7, yy, 15.0)), V((4.7, yy, 15.08)), V((-4.7, yy, 15.08))],
                    "brass", V((0, side, 0)))
        rows = [(15.42, "head")] + [(14.6 - 0.66 * r, "row") for r in range(6)]
        for zc, kind in rows:
            x = -4.6
            groups = [7, 5, 4, 3] if kind == "row" else [4, 3, 3, 3]
            for gi, ng in enumerate(groups):
                amber = kind == "head" or (gi == 3 and rng.random() < 0.5)
                for _ in range(ng):
                    w = rng.uniform(0.22, 0.32)
                    if x + w > 4.6:
                        break
                    hgt = 0.34 if rng.random() > 0.15 else 0.24
                    pts = [V((x, yy * 1.002, zc - hgt / 2)), V((x + w, yy * 1.002, zc - hgt / 2)),
                           V((x + w, yy * 1.002, zc + hgt / 2)), V((x, yy * 1.002, zc + hgt / 2))]
                    face_toward(ga if amber else gw, pts, "glyph_amber" if amber else "glyph", V((0, side, 0)))
                    x += w + 0.08
                x += 0.55
    A.att("Light", (0, 0.8, 13.5), (0, 1, 0), (0, 0, 1), note="optional SurfaceLight on the Glyphs (white), "
                                                                  "Brightness 0.3, Range 6")
    A.collider((-5.0, -0.35, 11.0), (5.0, 0.35, 16.0))
    for x in (-3.8, 3.8):
        A.collider((x - 0.45, -0.45, 0), (x + 0.45, 0.45, 11.0))
    return A


def build_poster():
    A = Asset("Station_Poster", "Prop", "Train_StationProps.glb", tset="Station_Poster", tex_size=1024,
              tags=["Station", "Poster"],
              notes="Framed propaganda poster 14 x 24 with our own art: a heroic faceted guard (white armour, black "
                    "harness, our own gold chest emblem) against a maroon sunburst, a slate band with blank cream "
                    "bars (no slogan, no film character). Hangs on a wall: origin = bottom centre of the frame's "
                    "back, front +Y.")
    p = A.part("Poster")
    W2, H = 7.0, 24.0
    # frame: front annulus, reveals, outer edges
    poly_holes(p, [V((-W2, 0.4, 0)), V((W2, 0.4, 0)), V((W2, 0.4, H)), V((-W2, 0.4, H))],
               [[V((-W2 + 0.45, 0.4, 0.45)), V((W2 - 0.45, 0.4, 0.45)), V((W2 - 0.45, 0.4, H - 0.45)),
                 V((-W2 + 0.45, 0.4, H - 0.45))]], "bronze", (0, 1, 0))
    box(p, (-W2, 0.0, 0.0), (W2, 0.4, H), "bronze", skip=("+y", "-y"))
    ia, ib = -W2 + 0.45, W2 - 0.45
    for (a, b_, nrm) in ((V((ia, 0, 0.45)), V((ib, 0, 0.45)), (0, 0, 1)), (V((ib, 0, 0.45)), V((ib, 0, H - 0.45)), (-1, 0, 0)),
                         (V((ib, 0, H - 0.45)), V((ia, 0, H - 0.45)), (0, 0, -1)), (V((ia, 0, H - 0.45)), V((ia, 0, 0.45)), (1, 0, 0))):
        face_toward(p, [a + V((0, 0.4, 0)), b_ + V((0, 0.4, 0)), b_ + V((0, 0.28, 0)), a + V((0, 0.28, 0))], "bronze",
                    V(nrm))
    x0, x1, z0, z1 = ia, ib, 0.45, H - 0.45
    lay = [0.28]

    def L(pts2, key, dz=0.012):
        lay[0] += dz
        face_toward(p, [V((x, lay[0], z)) for x, z in pts2], key, V((0, 1, 0)))
    L([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], "poster_maroon")
    cx, cz = 0.4, 15.6
    for k in range(12):
        a0, a1 = math.radians(30 * k - 7), math.radians(30 * k + 7)
        tri = [(cx, cz), (cx + 40 * math.cos(a0), cz + 40 * math.sin(a0)), (cx + 40 * math.cos(a1), cz + 40 * math.sin(a1))]
        cp = clip_poly(tri, x0, z0, x1, z1)
        if len(cp) >= 3:
            face_toward(p, [V((x, lay[0] + 0.012, z)) for x, z in cp], "poster_sky", V((0, 1, 0)))
    lay[0] += 0.012
    L([(cx + 3.4 * math.cos(TAU * i / 16), 17.2 + 3.4 * math.sin(TAU * i / 16)) for i in range(16)], "poster_gold")
    L([(x0, z0), (x1, z0), (x1, 4.7), (x0, 4.7)], "poster_slate")
    for (za, zb, w) in ((1.3, 1.85, 10.0), (2.3, 2.85, 6.8), (3.3, 3.85, 3.6)):
        L([(-w / 2, za), (w / 2, za), (w / 2, zb), (-w / 2, zb)], "poster_cream", dz=0.0)
    lay[0] += 0.012
    L([(x0, 22.1), (x1, 22.1), (x1, 22.9), (x0, 22.9)], "poster_cream", dz=0.0)
    # the figure (light from the upper left)
    L([(-4.4, 4.7), (0.3, 4.7), (0.6, 13.3), (-0.1, 15.0), (-3.3, 14.5), (-4.7, 12.7)], "poster_white")
    L([(0.3, 4.7), (4.5, 4.7), (4.9, 12.5), (3.7, 14.3), (0.9, 14.9), (0.6, 13.3)], "poster_shade", dz=0.0)
    L([(-6.1, 12.0), (-5.0, 11.3), (-3.2, 11.9), (-2.7, 14.0), (-3.6, 15.3), (-5.4, 14.9), (-6.3, 13.4)],
      "poster_white")
    L([(2.6, 11.9), (4.4, 11.2), (5.6, 12.0), (5.9, 13.4), (5.1, 14.8), (3.4, 15.2), (2.5, 13.9)], "poster_shade",
      dz=0.0)
    L([(-3.4, 14.2), (-2.6, 14.6), (4.0, 5.6), (3.2, 5.2)], "poster_dark")
    L([(3.1, 14.0), (3.9, 13.6), (-2.9, 5.2), (-3.7, 5.6)], "poster_dark", dz=0.0)
    L([(-4.4, 4.7), (4.5, 4.7), (4.6, 5.7), (-4.5, 5.7)], "poster_dark", dz=0.0)
    L([(0.3 + 0.75 * math.cos(TAU * i / 8 + 0.39), 9.75 + 0.75 * math.sin(TAU * i / 8 + 0.39)) for i in range(8)],
      "poster_gold")
    L([(-0.7, 14.8), (1.3, 14.8), (1.2, 16.0), (-0.6, 16.0)], "poster_dark")
    L([(-1.9, 15.8), (2.5, 15.8), (2.7, 17.4), (2.2, 19.0), (0.6, 19.9), (-1.0, 19.6), (-2.0, 18.2)], "poster_white")
    L([(0.9, 15.8), (2.5, 15.8), (2.7, 17.4), (2.2, 19.0), (0.9, 19.8)], "poster_shade", dz=0.0)
    L([(-1.5, 16.3), (2.3, 16.5), (2.4, 17.5), (-1.4, 17.4)], "poster_dark")
    L([(-2.3, 17.9), (2.9, 17.9), (2.9, 18.3), (-2.3, 18.3)], "poster_shade")
    A.collider((-W2, 0, 0), (W2, 0.4, H))
    return A


def build_guard():
    A = Asset("Station_Guard", "Character", "Train_StationProps.glb", tset="Station_Guard", tex_size=512,
              tags=["Station", "NPC", "Guard"],
              notes="Our own guard in white armour (helmet, cuirass, pauldrons, greaves, bracers), black harness, "
                    "black visor and boots, with our own small gold chest emblem; 5.6 tall at attention. A static "
                    "statue mesh for the rows on the platforms and in the guard car (rig it later if guards must "
                    "move). Origin = between the feet, facing +Y.")
    b = A.part("Body")
    for s in (-1, 1):
        cx = s * 0.3
        hull(b, [(cx - 0.23, -0.34, 0), (cx + 0.23, -0.34, 0), (cx - 0.24, 0.5, 0), (cx + 0.24, 0.5, 0),
                 (cx - 0.21, 0.52, 0.26), (cx + 0.21, 0.52, 0.26), (cx - 0.2, 0.22, 0.45), (cx + 0.2, 0.22, 0.45),
                 (cx - 0.22, -0.32, 0.95), (cx + 0.22, -0.32, 0.95), (cx - 0.22, 0.18, 0.95), (cx + 0.22, 0.18, 0.95)],
             "harness")
        cyl(b, (cx, 0.0, 0.88), (cx * 1.02, 0.0, 2.38), 0.27, 0.31, 6, "armour", phase=math.radians(30))
        hull(b, [(cx - 0.2, 0.18, 2.3), (cx + 0.2, 0.18, 2.3), (cx - 0.22, 0.36, 2.45), (cx + 0.22, 0.36, 2.45),
                 (cx - 0.2, 0.2, 2.68), (cx + 0.2, 0.2, 2.68), (cx, 0.42, 2.5)], "armour")
        cyl(b, (cx, 0.0, 2.4), (cx * 1.05, 0.0, 3.15), 0.32, 0.36, 6, "suit", phase=math.radians(30))
        hull(b, [(cx - 0.26, 0.22, 2.68), (cx + 0.26, 0.22, 2.68), (cx - 0.3, 0.32, 3.12), (cx + 0.3, 0.32, 3.12),
                 (cx - 0.2, 0.42, 2.9), (cx + 0.2, 0.42, 2.9)], "armour")
        hull(b, [(s * 0.86, -0.18, 4.25), (s * 0.86, 0.2, 4.25), (s * 1.08, 0.0, 4.32), (s * 0.66, -0.2, 4.62),
                 (s * 0.66, 0.22, 4.62), (s * 0.95, 0.0, 4.66), (s * 0.78, 0.0, 4.76), (s * 1.02, -0.16, 4.4),
                 (s * 1.02, 0.18, 4.4)], "armour")
        cyl(b, (s * 0.86, 0.0, 4.38), (s * 0.93, 0.04, 3.55), 0.21, 0.19, 6, "suit")
        cyl(b, (s * 0.93, 0.04, 3.55), (s * 0.9, 0.14, 2.86), 0.2, 0.17, 6, "armour")
        hull(b, [(s * 0.78, 0.04, 2.88), (s * 1.02, 0.04, 2.88), (s * 0.8, 0.28, 2.86), (s * 1.0, 0.26, 2.86),
                 (s * 0.82, 0.1, 2.5), (s * 0.98, 0.1, 2.52), (s * 0.84, 0.24, 2.56), (s * 0.96, 0.22, 2.56)],
             "harness")
    lathe(b, [(0.62, 3.06), (0.64, 3.3)], 8, "harness", sx=1.0, sy=0.66)
    hull(b, [(-0.12, 0.42, 3.1), (0.12, 0.42, 3.1), (-0.12, 0.42, 3.27), (0.12, 0.42, 3.27), (0, 0.47, 3.18)], "brass")
    pts = []
    for z, rx, ry in ((3.25, 0.6, 0.38), (3.6, 0.66, 0.42), (3.95, 0.72, 0.45), (4.3, 0.76, 0.44), (4.55, 0.7, 0.36)):
        for k in range(10):
            t = TAU * k / 10
            pts.append((rx * math.cos(t), ry * math.sin(t) + (0.04 if math.sin(t) > 0.5 else 0.0), z))
    pts += [(0.0, 0.54, 3.95), (0.0, 0.5, 4.3)]
    hull(b, pts, "armour")
    for s in (-1, 1):
        beam(b, (s * 0.46, 0.44, 4.42), (-s * 0.5, 0.47, 3.32), 0.2, 0.07, "harness", up=V((0, 1, 0)))
        beam(b, (s * 0.46, -0.42, 4.42), (-s * 0.5, -0.45, 3.32), 0.2, 0.07, "harness", up=V((0, -1, 0)))
        beam(b, (s * 0.46, 0.43, 4.46), (s * 0.46, -0.41, 4.46), 0.2, 0.07, "harness", up=V((0, 0, 1)))
    cyl(b, (0, 0.555, 3.9), (0, 0.6, 3.9), 0.15, 0.15, 8, "brass", up=V((0, 0, 1)))
    cyl(b, (0, 0, 4.5), (0, 0, 4.82), 0.2, 0.19, 6, "suit")
    lathe(b, [(0.4, 4.74), (0.445, 4.95), (0.44, 5.2), (0.37, 5.42), (0.22, 5.57), (0.0, 5.63)], 8, "armour",
          phase=math.radians(22.5))
    lathe(b, [(0.47, 4.86), (0.48, 4.93)], 8, "armour", phase=math.radians(22.5))
    hull(b, [(-0.3, 0.28, 4.74), (0.3, 0.28, 4.74), (-0.31, 0.3, 5.12), (0.31, 0.3, 5.12), (-0.15, 0.43, 4.76),
             (0.15, 0.43, 4.76), (-0.15, 0.44, 5.12), (0.15, 0.44, 5.12), (0, 0.47, 4.95)], "visor")
    A.collider((-0.7, -0.5, 0), (0.7, 0.5, 5.6))
    return A


# ================================================================================================ layouts
def station_layout():
    """[(asset, location (Blender hall space), yaw degrees)] for the station hall."""
    L = [("Station_Coffer", (cx, OVAL_Y + cy, 0), 0) for cx, cy in coffer_grid()[0]]
    L += [("Station_EntranceCeiling", (0, OVAL_Y, 0), 0), ("Station_Lantern", (0, OVAL_Y, 0), 0),
         ("Station_Sunburst", (0, OVAL_Y, 0), 0), ("Station_EntranceWalls", (0, OVAL_Y, 0), 0),
         ("Station_EntranceFloor", (0, OVAL_Y, 0), 0), ("Station_Portal", (0, ENT_Y0, 0), 0)]
    for k in range(NBAYS + BACKDROP_BAYS):
        yc = ENT_Y0 - BAY * (k + 0.5)
        L += [("Station_ShedBay", (0, yc, 0), 0), ("Station_FloorBay", (0, yc, 0), 0)]
    L.append(("Station_ShedEnd", (0, SHED_END_Y, 0), 0))
    for k in range(NBAYS - 1):
        for x in (-11.0, 11.0):
            L.append(("Station_Banner", (x, ENT_Y0 - 12.0 - BAY * k, 34.0), 0))
    for k in range(3):
        for x in (-46.0, 46.0):
            L.append(("Station_Board", (x, ENT_Y0 - 8.0 - 96.0 * k, 0), 0))
    for y in (OVAL_Y - 9.2, OVAL_Y + 22.0):
        L.append(("Station_Poster", (-(WALL_X - 0.9), y, 13.0), -90))
        L.append(("Station_Poster", (WALL_X - 0.9, y, 13.0), 90))
    return L


def guard_layout():
    """Guard posts (preview dressing and GuardPost attachments for the integrator)."""
    G = []
    for s in (-1, 1):
        for k in range(12):
            G.append(((s * (PLAT_X - 3.5), NOSE_FRONT_Y - 6.0 - 7.0 * k, 0), 90 if s < 0 else -90))
        for k in range(3):
            G.append(((s * (PLAT_X - 9.0 - 3.0 * k), NOSE_FRONT_Y + 3.0, 0), 0))
    for x in (-3.0, 3.0):
        G.append(((x, ENT_Y0 - 2.0, 0), 0))
    G.append(((-11.0, 176.0, 0), 180))
    G.append(((11.0, 176.0, 0), 180))
    G.append(((-10.5, 189.0, 0), 180))
    G.append(((10.5, 189.0, 0), 180))
    for k in range(8):
        for x in (-4.0, 4.0):
            G.append(((x, ENT_Y0 - 30.0 - 14.0 * k, 0), 0))
    return G


# ================================================================================================ train: shells
# Half profile of the car body (x >= 0, z), bottom centre to roof centre. The flank (x = 5.75) carries vertices at
# every livery line and opening edge: door sill 0.3, pinstripes 0.55-0.8 and 7.55-7.8, the observation car's glass
# 1.2, windows 3.7-7.3, door head 7.8.
PROF = [(0.0, SKIRT_Z), (4.3, SKIRT_Z), (5.1, -1.75), (5.6, -1.0), (HWID, -0.2), (HWID, 0.3), (HWID, 0.55),
        (HWID, 0.8), (HWID, 1.2), (HWID, WIN_Z0), (HWID, WIN_Z1), (HWID, 7.55), (HWID, DOOR_Z1), (HWID, 8.4),
        (5.55, 9.35), (5.05, 10.1), (4.15, 10.6), (2.9, 10.88), (1.45, 10.97), (0.0, 11.0)]
NOSE_ZC, NOSE_R = 4.6, 4.9


def car_ring():
    """Closed ring (x, z), counter-clockwise about +Y (top -> right -> bottom -> left)."""
    right = PROF[1:-1]
    return [(0.0, PROF[-1][1])] + [p for p in reversed(right)] + [(0.0, PROF[0][1])] + [(-x, z) for x, z in right]


RING = car_ring()


def seg_key(i, flank_band=True):
    """Livery per ring segment: glossy black, a maroon flank between gold pinstripes."""
    (xa, za), (xb, zb) = RING[i], RING[(i + 1) % len(RING)]
    if not (abs(xa) > HWID - 0.01 and abs(xb) > HWID - 0.01) or not flank_band:
        return "lacquer"
    zc = 0.5 * (za + zb)
    if 0.55 <= zc <= 0.8 or 7.55 <= zc <= 7.8:
        return "pinstripe"
    if 0.8 < zc < 7.55:
        return "maroon"
    return "lacquer"


def seg_flank(i):
    (xa, za), (xb, zb) = RING[i], RING[(i + 1) % len(RING)]
    return abs(xa) > HWID - 0.01 and abs(xb) > HWID - 0.01, (1 if xa > 0 else -1), min(za, zb), max(za, zb)


def nose_point(x, z, t):
    """Blend a body-ring point toward the nose circle (t 0 = body, 1 = the round face)."""
    th = math.atan2(x, z - NOSE_ZC)
    cx, cz = NOSE_R * math.sin(th), NOSE_ZC + NOSE_R * math.cos(th)
    w = t ** 1.25
    return (x + (cx - x) * w, z + (cz - z) * w), th


def car_layout(kind):
    """Openings per car type: windows [(y0, y1)], side doors [(y0, y1)], gangway ends, nose."""
    if kind == "nose":
        L = NOSE_CAR_L
        doors = [(-L / 2 + 3.0, -L / 2 + 7.0), (21.0, 25.0)]
        wins = [(c - WIN_W / 2, c + WIN_W / 2) for c in (-32.5, -24.5, -16.5, -8.5, -0.5, 7.5, 15.5)]
        return dict(L=L, doors=doors, wins=wins, ends=("rear",), nose=True, glass_bays=None)
    if kind == "obs":
        L = CAR_L
        bays = [(-L / 2 + 4.0 + 6.0 * k, -L / 2 + 10.0 + 6.0 * k) for k in range(12)]
        return dict(L=L, doors=[], wins=[], ends=("rear", "front"), nose=False, glass_bays=bays)
    L = CAR_L
    doors = [(-L / 2 + 3.0, -L / 2 + 7.0), (L / 2 - 7.0, L / 2 - 3.0)]
    wins = [(c - WIN_W / 2, c + WIN_W / 2) for c in (-24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0)]
    return dict(L=L, doors=doors, wins=wins, ends=("rear", "front"), nose=False, glass_bays=None)


def window_frame(mb, gl, side, y0, y1, z0=WIN_Z0, z1=WIN_Z1, x_out=HWID, x_in=LIN_X - 0.05, r=0.85, seg=2,
                 inset=0.32):
    """Brass frame filling a rectangular opening with a round-cornered window, and its glass."""
    s = side
    yc, zc, w, h = 0.5 * (y0 + y1), 0.5 * (z0 + z1), y1 - y0, z1 - z0
    rr = rrect(yc, zc, w - 2 * inset, h - 2 * inset, r, seg)
    xo, xi = s * (x_out + 0.05), s * x_in
    outer = [V((xo, y0, z0)), V((xo, y1, z0)), V((xo, y1, z1)), V((xo, y0, z1))]
    poly_holes(mb, outer, [[V((xo, u, v)) for u, v in rr]], "brass", (s, 0, 0))
    inner = [V((xi, y0, z0)), V((xi, y1, z0)), V((xi, y1, z1)), V((xi, y0, z1))]
    poly_holes(mb, inner, [[V((xi, u, v)) for u, v in rr]], "brass", (-s, 0, 0))
    vol = mb.nv()
    n = len(rr)
    for k in range(n):
        (ua, va), (ub, vb) = rr[k], rr[(k + 1) % n]
        pts = [V((xo, ua, va)), V((xo, ub, vb)), V((xi, ub, vb)), V((xi, ua, va))]
        mid = V((0, 0.5 * (ua + ub), 0.5 * (va + vb)))
        face_toward(mb, pts, "brass", V((0, yc, zc)) - mid, vol)
    for (pa, pb) in (((y0, z0), (y1, z0)), ((y1, z0), (y1, z1)), ((y1, z1), (y0, z1)), ((y0, z1), (y0, z0))):
        pts = [V((s * x_out, pa[0], pa[1])), V((s * x_out, pb[0], pb[1])), V((xo, pb[0], pb[1])),
               V((xo, pa[0], pa[1]))]
        mid = V((0, 0.5 * (pa[0] + pb[0]), 0.5 * (pa[1] + pb[1])))
        face_toward(mb, pts, "brass", mid - V((0, yc, zc)), vol)
    if gl is not None:
        xg = s * (0.5 * (x_out + x_in))
        face_toward(gl, [V((xg + s * 0.03, u, v)) for u, v in rr], "glass", V((s, 0, 0)))
        face_toward(gl, [V((xg - s * 0.03, u, v)) for u, v in rr], "glass", V((-s, 0, 0)))


def door_jambs(mb, side, y0, y1, z0, z1, x_out=HWID, x_in=LIN_X, key="lacquer"):
    s = side
    yc, zc = 0.5 * (y0 + y1), 0.5 * (z0 + z1)
    vol = mb.nv()
    for (pa, pb) in (((y0, z0), (y1, z0)), ((y1, z0), (y1, z1)), ((y1, z1), (y0, z1)), ((y0, z1), (y0, z0))):
        pts = [V((s * x_out, pa[0], pa[1])), V((s * x_out, pb[0], pb[1])), V((s * x_in, pb[0], pb[1])),
               V((s * x_in, pa[0], pa[1]))]
        mid = V((0, 0.5 * (pa[0] + pb[0]), 0.5 * (pa[1] + pb[1])))
        face_toward(mb, pts, key, V((0, yc, zc)) - mid, vol)


def bellows(mb, y_end, out):
    """Rubber gangway diaphragm round the end doorway (accordion folds), reaching 0.75 beyond the end."""
    ox, oz0, oz1 = 3.0, -0.4, 9.0
    ix, iz0, iz1 = 2.2, FLOOR_Z, DOOR_Z1 + 0.35
    ys = [y_end + out * d for d in (0.0, 0.25, 0.5, 0.75)]
    outs = [ox, ox - 0.22, ox, ox - 0.22]
    vol = mb.nv()
    for k in range(3):
        r0, r1 = outs[k], outs[k + 1]
        a = [V((-r0, ys[k], oz0)), V((r0, ys[k], oz0)), V((r0, ys[k], oz1 - (ox - r0))),
             V((-r0, ys[k], oz1 - (ox - r0)))]
        b = [V((-r1, ys[k + 1], oz0)), V((r1, ys[k + 1], oz0)), V((r1, ys[k + 1], oz1 - (ox - r1))),
             V((-r1, ys[k + 1], oz1 - (ox - r1)))]
        for i in range(4):
            j = (i + 1) % 4
            pts = [a[i], a[j], b[j], b[i]]
            mid = sum(pts, V((0, 0, 0))) / 4.0
            face_toward(mb, pts, "bellows", mid - V((0, mid.y, 4.3)), vol)
        ai = [V((-ix, ys[k], iz0)), V((ix, ys[k], iz0)), V((ix, ys[k], iz1)), V((-ix, ys[k], iz1))]
        bi = [V((-ix, ys[k + 1], iz0)), V((ix, ys[k + 1], iz0)), V((ix, ys[k + 1], iz1)), V((-ix, ys[k + 1], iz1))]
        for i in range(1, 4):
            j = (i + 1) % 4
            pts = [ai[i], ai[j], bi[j], bi[i]]
            mid = sum(pts, V((0, 0, 0))) / 4.0
            face_toward(mb, pts, "bellows", V((0, mid.y, 4.3)) - mid, vol)
    ye = ys[-1]
    r = outs[-1]
    poly_holes(mb, [V((-r, ye, oz0)), V((r, ye, oz0)), V((r, ye, oz1 - (ox - r))), V((-r, ye, oz1 - (ox - r)))],
               [[V((-ix, ye, iz0)), V((ix, ye, iz0)), V((ix, ye, iz1)), V((-ix, ye, iz1))]], "bellows", (0, out, 0))
    face_toward(mb, [V((-ix, ys[0], iz0)), V((ix, ys[0], iz0)), V((ix, ye, iz0)), V((-ix, ye, iz0))], "underframe",
                V((0, 0, 1)))


def shell_stations(lay):
    L = lay["L"]
    y_back, y_front = -L / 2, L / 2
    y_nose0 = y_front - NOSE_LEN if lay["nose"] else y_front
    stations = {y_back, y_nose0}
    for a_, b_ in lay["doors"] + lay["wins"]:
        stations |= {a_, b_}
    if lay["glass_bays"]:
        for a_, b_ in lay["glass_bays"]:
            stations |= {a_ - 0.3, a_ + 0.3, b_ - 0.3, b_ + 0.3}
    st = sorted(stations)
    full = []
    for i in range(len(st) - 1):
        full.append(st[i])
        n_ = int((st[i + 1] - st[i]) // 7.0)
        for k in range(1, n_ + 1):
            full.append(st[i] + (st[i + 1] - st[i]) * k / (n_ + 1))
    full.append(st[-1])
    return full, y_back, y_front, y_nose0


def build_car_shell(kind):
    """kind: 'nose' (90, nose at +Y), 'body' (80), 'obs' (80, observation glass)."""
    lay = car_layout(kind)
    L = lay["L"]
    name = {"nose": "Train_NoseCar", "body": "Train_BodyCar", "obs": "Train_ObservationCar"}[kind]
    what = {"nose": "Nose car (car 1; car 7 is the same car turned round as the tail)",
            "body": "Body car (cars 2-5)",
            "obs": "Observation car (car 6): floor-to-ceiling glass on both flanks and a glazed roof"}[kind]
    A = Asset(name, "TrainCar", "Train_Exterior.glb", tags=["Train", "Car", "Moving"],
              notes=("%s, %g long, 11.5 wide, 13.2 tall over a maglev guideway (no wheels). Glossy black lacquer "
                     "with a maroon flank between gold pinstripes (semi-gloss: roughness 0.3, metalness 0.2, brief "
                     "4.3), round-cornered brass windows, plug doors 4 x 7.5 (Train_DoorLeaf, separate), gangway "
                     "diaphragms. Origin = footprint centre at platform level; the interior floor is 0.3 up; front "
                     "+Y (Roblox -Z). Interior kits fit inside (same origin)." % (what, L)))
    mb = A.part("Body")
    gl = A.part("Glass", kind="glass", shadow=False)
    stations, y_back, y_front, y_nose0 = shell_stations(lay)
    nR = len(RING)
    holes = []                      # (side, y0, y1, z0, z1)
    for a_, b_ in lay["wins"]:
        for s in (-1, 1):
            holes.append((s, a_, b_, WIN_Z0, WIN_Z1))
    for a_, b_ in lay["doors"]:
        for s in (-1, 1):
            holes.append((s, a_, b_, FLOOR_Z, DOOR_Z1))
    if lay["glass_bays"]:
        for a_, b_ in lay["glass_bays"]:
            for s in (-1, 1):
                holes.append((s, a_ + 0.3, b_ - 0.3, 1.2, 8.4))
    roof_glass = []
    for k in range(len(stations) - 1):
        ya, yb = stations[k], stations[k + 1]
        yc = 0.5 * (ya + yb)
        vol = mb.nv()
        for i in range(nR):
            j = (i + 1) % nR
            fl, s, z0, z1 = seg_flank(i)
            if fl and any(h[0] == s and h[1] - 1e-4 <= yc <= h[2] + 1e-4 and
                          h[3] - 1e-4 <= 0.5 * (z0 + z1) <= h[4] + 1e-4 for h in holes):
                continue
            key = seg_key(i)
            if lay["glass_bays"]:
                (xa, za), (xb, zb) = RING[i], RING[j]
                in_bay = any(a_ + 0.3 <= yc <= b_ - 0.3 for a_, b_ in lay["glass_bays"])
                if min(za, zb) >= 8.4 - 1e-4 and abs(0.5 * (xa + xb)) > 0.4:
                    if in_bay:
                        roof_glass.append((k, i))
                        continue
                    key = "brass"
            pa = [V((RING[i][0], ya, RING[i][1])), V((RING[j][0], ya, RING[j][1])),
                  V((RING[j][0], yb, RING[j][1])), V((RING[i][0], yb, RING[i][1]))]
            mb.face(pa, key, vol)
    # glazing of the observation car: flank panes and roof panes between brass ribs
    if lay["glass_bays"]:
        for (k, i) in roof_glass:
            ya, yb = stations[k], stations[k + 1]
            j = (i + 1) % nR
            sc = 0.985
            pa = [V((RING[i][0] * sc, ya, RING[i][1] * sc + 0.08)), V((RING[j][0] * sc, ya, RING[j][1] * sc + 0.08)),
                  V((RING[j][0] * sc, yb, RING[j][1] * sc + 0.08)), V((RING[i][0] * sc, yb, RING[i][1] * sc + 0.08))]
            gl.face(pa, "glass")
            q = [p - (p - V((0, p.y, 4.0))).normalized() * 0.05 for p in pa]
            gl.face(list(reversed(q)), "glass")
        for a_, b_ in lay["glass_bays"]:
            for s in (-1, 1):
                xo = s * (HWID - 0.25)
                face_toward(gl, [V((xo, a_ + 0.3, 1.2)), V((xo, b_ - 0.3, 1.2)), V((xo, b_ - 0.3, 8.4)),
                                 V((xo, a_ + 0.3, 8.4))], "glass", V((s, 0, 0)))
                face_toward(gl, [V((xo - s * 0.05, a_ + 0.3, 1.2)), V((xo - s * 0.05, b_ - 0.3, 1.2)),
                                 V((xo - s * 0.05, b_ - 0.3, 8.4)), V((xo - s * 0.05, a_ + 0.3, 8.4))], "glass",
                            V((-s, 0, 0)))
                door_jambs(mb, s, a_ + 0.3, b_ - 0.3, 1.2, 8.4, x_out=HWID, x_in=HWID - 0.3, key="brass")
    for a_, b_ in lay["wins"]:
        for s in (-1, 1):
            window_frame(mb, gl, s, a_, b_)
    for di, (a_, b_) in enumerate(lay["doors"]):
        for s in (-1, 1):
            door_jambs(mb, s, a_, b_, FLOOR_Z, DOOR_Z1)
            for (za, zb, ya_, yb_) in ((DOOR_Z1, DOOR_Z1 + 0.18, a_ - 0.18, b_ + 0.18),
                                       (FLOOR_Z, DOOR_Z1, a_ - 0.18, a_), (FLOOR_Z, DOOR_Z1, b_, b_ + 0.18)):
                face_toward(mb, [V((s * (HWID + 0.03), ya_, za)), V((s * (HWID + 0.03), yb_, za)),
                                 V((s * (HWID + 0.03), yb_, zb)), V((s * (HWID + 0.03), ya_, zb))], "pinstripe",
                            V((s, 0, 0)))
            A.att("Door%s_%d" % ("R" if s > 0 else "L", di + 1), (s * (HWID - 0.1), 0.5 * (a_ + b_), FLOOR_Z),
                  (0, 1, 0), (0, 0, 1),
                  note="Train_DoorLeaf closed here (yaw %d: its +X out of the car); open = 0.2 in, then slide 4.2 "
                       "along +look into the wall pocket" % (0 if s > 0 else 180))
    if lay["nose"]:
        build_nose(A, mb, y_nose0)
    for e in lay["ends"]:
        ye = y_front if e == "front" else y_back
        out = 1 if e == "front" else -1
        ring3 = [V((x, ye, z)) for x, z in RING]
        poly_holes(mb, ring3, [[V((-DOOR_W / 2, ye, FLOOR_Z)), V((DOOR_W / 2, ye, FLOOR_Z)),
                                V((DOOR_W / 2, ye, DOOR_Z1)), V((-DOOR_W / 2, ye, DOOR_Z1))]], "lacquer",
                   (0, out, 0))
        vol = mb.nv()
        yi = ye - out * 0.6
        for (pa, pb) in (((-DOOR_W / 2, FLOOR_Z), (DOOR_W / 2, FLOOR_Z)),
                         ((DOOR_W / 2, FLOOR_Z), (DOOR_W / 2, DOOR_Z1)),
                         ((DOOR_W / 2, DOOR_Z1), (-DOOR_W / 2, DOOR_Z1)),
                         ((-DOOR_W / 2, DOOR_Z1), (-DOOR_W / 2, FLOOR_Z))):
            pts = [V((pa[0], ye, pa[1])), V((pb[0], ye, pb[1])), V((pb[0], yi, pb[1])), V((pa[0], yi, pa[1]))]
            mid = V((0.5 * (pa[0] + pb[0]), ye, 0.5 * (pa[1] + pb[1])))
            face_toward(mb, pts, "underframe", V((0, ye, 4.0)) - mid, vol)
        bellows(mb, ye, out)
        A.att("Gangway%s" % ("Front" if out > 0 else "Rear"), (0, ye + out * 0.75, FLOOR_Z), (0, out, 0),
              (0, 0, 1), note="the next car's diaphragm meets here (1.5 between car ends)")
    # colliders: floor, roof, flanks round the doors, ends round the gangway
    A.collider((-HWID, y_back, SKIRT_Z), (HWID, y_nose0, FLOOR_Z), "Floor")
    A.collider((-HWID, y_back, 9.9), (HWID, y_nose0, 11.0))
    for s in (-1, 1):
        y = y_back
        for a_, b_ in sorted(lay["doors"]) + [(y_nose0, y_nose0)]:
            if a_ - y > 0.05:
                A.collider((s * LIN_X, y, FLOOR_Z), (s * HWID, a_, 9.9))
            if b_ > a_:
                A.collider((s * LIN_X, a_, DOOR_Z1), (s * HWID, b_, 9.9))
            y = b_
    for e in lay["ends"]:
        ye = y_front if e == "front" else y_back
        out = 1 if e == "front" else -1
        y0_, y1_ = sorted((ye, ye - out * 0.6))
        A.collider((-HWID, y0_, FLOOR_Z), (-DOOR_W / 2, y1_, 9.9))
        A.collider((DOOR_W / 2, y0_, FLOOR_Z), (HWID, y1_, 9.9))
        A.collider((-DOOR_W / 2, y0_, DOOR_Z1), (DOOR_W / 2, y1_, 9.9))
    if lay["nose"]:
        A.collider((-HWID, y_nose0, SKIRT_Z), (HWID, y_front, 10.0))
    return A


def build_nose(A, mb, y_nose0):
    """The faceted capsule nose: the body ring morphs into a round face (9.8 across) with a deep bezel and a
    3.5-stud gold-rimmed lamp round a glowing 2-stud red-orange core."""
    nR = len(RING)
    ts = [0.0, 0.2, 0.38, 0.54, 0.68, 0.8, 0.9, 1.0]
    rings, thetas = [], None
    for t in ts:
        y = y_nose0 + NOSE_LEN * 0.93 * (1.0 - (1.0 - t) ** 1.6)
        pts, th = [], []
        for x, z in RING:
            (px, pz), a = nose_point(x, z, t)
            pts.append(V((px, y, pz)))
            th.append(a)
        rings.append(pts)
        thetas = th
    for k in range(len(rings) - 1):
        vol = mb.nv()
        for i in range(nR):
            j = (i + 1) % nR
            mb.face([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]], seg_key(i), vol)
    yf = rings[-1][0].y

    def face_ring(scale, dy):
        return [V((NOSE_R * scale * math.sin(a), yf + dy, NOSE_ZC + NOSE_R * scale * math.cos(a))) for a in thetas]
    fr = [rings[-1], face_ring(0.93, 0.62), face_ring(0.8, 1.08), face_ring(0.76, 0.92), face_ring(0.68, 0.5)]
    keys = ["lacquer", "lacquer", "bezel", "bezel"]
    for k in range(len(fr) - 1):
        vol = mb.nv()
        for i in range(nR):
            j = (i + 1) % nR
            mb.face([fr[k][i], fr[k][j], fr[k + 1][j], fr[k + 1][i]], keys[k], vol)
    n = 20
    yb_ = yf + 0.5

    def lamp(r, dy):
        return [V((r * math.sin(TAU * i / n), yb_ + dy, NOSE_ZC + r * math.cos(TAU * i / n))) for i in range(n)]
    poly_holes(mb, face_ring(0.68, 0.5), [lamp(1.75, 0.0)], "bezel", (0, 1, 0))
    loft(mb, [lamp(1.75, 0.0), lamp(1.75, 0.55), lamp(1.45, 0.75), lamp(1.1, 0.6), lamp(1.0, 0.35)], "brass")
    core = A.part("LampCore", kind="neon", shadow=False)
    core.face(lamp(1.0, 0.36), "lamp_core")
    A.att("Lamp", (0, yb_ + 0.4, NOSE_ZC), (0, 1, 0), (0, 0, 1),
          note="SpotLight forward: Color (232, 88, 52), Brightness 2, Range 60, Angle 50; plus a PointLight Range 8 "
               "for the red glow on the platform")
    mk_ = A.part("Marker", kind="neon", shadow=False)
    for s in (-1, 1):
        cands = [i for i in range(nR) if RING[i][0] * s > 5.0 and abs(RING[i][1] - 3.7) < 0.01]
        if cands:
            p = rings[3][cands[0]]
            disc(mk_, p + V((s * 0.06, 0, -1.7)), 0.32, 8, (s, 0.35, 0), "marker")


def build_door_leaf():
    A = Asset("Train_DoorLeaf", "TrainDoor", "Train_Exterior.glb", tset="Train_DoorLeaf", tex_size=256,
              tags=["Train", "Door", "Moving"], pivot="bottom centre of the leaf's inner face",
              notes="Exterior plug door 4 x 7.5 in the car's livery with a round-cornered brass porthole. Closed: "
                    "outer face flush with the skin; opens 0.2 inward then slides 4.2 along its +Y into the wall "
                    "pocket (pneumatic thump, spec section 9). Local +X = out of the car.")
    lf = A.part("Leaf")
    gl = A.part("Glass", kind="glass", shadow=False)
    w, h, t = DOOR_W, DOOR_H, 0.2
    ys = [-w / 2, -0.75, 0.75, w / 2]
    zs = [0.0, 0.25, 0.5, 4.0, 6.3, 7.25, 7.5]

    def lk(z0, z1):
        zc = 0.5 * (z0 + z1)
        if 0.25 <= zc <= 0.5 or 7.25 <= zc <= 7.5:
            return "pinstripe"
        return "maroon" if 0.5 < zc < 7.25 else "lacquer"
    grid_wall(lf, t, -1, ys, zs, [(-0.75, 0.75, 4.0, 6.3)], lk, inward=True)
    grid_wall(lf, 0.0, 1, ys, [0.0, 4.0, 6.3, h], [(-0.75, 0.75, 4.0, 6.3)], lambda z0, z1: "wood_dark", inward=True)
    box(lf, (0.0, -w / 2, 0.0), (t, w / 2, h), "wood_dark", skip=("+x", "-x"))
    window_frame(lf, gl, 1, -0.75, 0.75, 4.0, 6.3, x_out=t - 0.05, x_in=0.0, r=0.55, inset=0.12)
    return A


# ================================================================================================ train: interiors
def place(mb, piece, loc, yaw=0.0):
    M = Matrix.Translation(V(loc)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    mb.extend(piece, M)


def vault_xz(n=8):
    """Interior ceiling arc from (-LIN_X, WALL_TOP) to (LIN_X, WALL_TOP) through (0, VAULT_Z)."""
    c = LIN_X
    sag = VAULT_Z - WALL_TOP
    R = (c * c + sag * sag) / (2 * sag)
    zc = VAULT_Z - R
    a0 = math.atan2(WALL_TOP - zc, -c)
    a1 = math.atan2(WALL_TOP - zc, c)
    return [(R * math.cos(a0 + (a1 - a0) * k / n), zc + R * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)], zc


def section_poly(y, inset=0.0):
    """The interior cross-section (floor, walls, vault) at y as a CCW loop seen from +y (x right, z up)."""
    arc, _ = vault_xz()
    pts = [V((-LIN_X + inset, y, FLOOR_Z)), V((LIN_X - inset, y, FLOOR_Z))]
    pts += [V((x * (1 - inset / LIN_X), y, z - inset * 0.5)) for x, z in reversed(arc)]
    return pts


def wall_with_door(mb, y, face, key, door=(-DOOR_W / 2, DOOR_W / 2), thick=0.0, frame_key="brass", inset=0.0):
    """A transverse wall at y facing `face` (+1 / -1 along y) with a doorway; optional thickness (two faces and
    a reveal) and a frame round the doorway."""
    hole = [V((door[0], y, FLOOR_Z)), V((door[1], y, FLOOR_Z)), V((door[1], y, DOOR_Z1)), V((door[0], y, DOOR_Z1))]
    poly_holes(mb, section_poly(y, inset), [hole], key, (0, face, 0))
    if thick > 0:
        y2 = y - face * thick
        hole2 = [V((p.x, y2, p.z)) for p in hole]
        poly_holes(mb, section_poly(y2, inset), [hole2], key, (0, -face, 0))
        vol = mb.nv()
        for (pa, pb) in (((door[0], FLOOR_Z), (door[1], FLOOR_Z)), ((door[1], FLOOR_Z), (door[1], DOOR_Z1)),
                         ((door[1], DOOR_Z1), (door[0], DOOR_Z1)), ((door[0], DOOR_Z1), (door[0], FLOOR_Z))):
            pts = [V((pa[0], y, pa[1])), V((pb[0], y, pb[1])), V((pb[0], y2, pb[1])), V((pa[0], y2, pa[1]))]
            mid = V((0.5 * (pa[0] + pb[0]), y, 0.5 * (pa[1] + pb[1])))
            face_toward(mb, pts, frame_key if frame_key else key, V((0.5 * (door[0] + door[1]), y, 4.0)) - mid, vol)
    if frame_key:
        for sgn in ((1,) if thick <= 0 else (1, -1)):
            yy = y + face * 0.04 if sgn > 0 else y - face * (thick + 0.04)
            ff = face * sgn
            for (a, b) in (((door[0] - 0.3, FLOOR_Z), (door[0], DOOR_Z1 + 0.3)),
                           ((door[1], FLOOR_Z), (door[1] + 0.3, DOOR_Z1 + 0.3)),
                           ((door[0], DOOR_Z1), (door[1], DOOR_Z1 + 0.3))):
                face_toward(mb, [V((a[0], yy, a[1])), V((b[0], yy, a[1])), V((b[0], yy, b[1])), V((a[0], yy, b[1]))],
                            frame_key, V((0, ff, 0)))


STYLE_SALOON = dict(skirt="wood_dark", wainscot="wood", dado="brass", upper="wall_cream", frieze="wood",
                    ceiling="hammered", cove="wood_dark", sill="wood")
STYLE_DINING = dict(skirt="wood_dark", wainscot="wood_dark", dado="silver", upper="wood", frieze="wood_dark",
                    ceiling="hammered", cove="wood_dark", sill="wood_dark")
STYLE_GUARD = dict(skirt="steel_dark", wainscot="steel_grey", dado="steel_dark", upper="steel_grey",
                   frieze="steel_dark", ceiling="steel", cove="steel_dark", sill="steel_dark")


def lining(A, mb, lay, y0, y1, style, rng, cove=True, skip_sides=(), arches=(), wall_glass_bays=None):
    """Interior walls (with the window and door openings of the shell), the vault, coves, sills, dado rails and
    arches between y0 and y1."""
    L = lay["L"]
    for s in (-1, 1):
        if s in skip_sides:
            continue
        cuts = {y0, y1}
        holes = []
        for a_, b_ in lay["wins"]:
            if y0 < a_ < y1:
                cuts |= {a_, b_}
                holes.append((a_, b_, WIN_Z0, WIN_Z1))
        for a_, b_ in lay["doors"]:
            if y0 <= a_ < y1:
                cuts |= {a_, b_}
                holes.append((a_, b_, FLOOR_Z, DOOR_Z1))
        if wall_glass_bays:
            for a_, b_ in wall_glass_bays:
                cuts |= {a_ + 0.3, b_ - 0.3}
                holes.append((a_ + 0.3, b_ - 0.3, 1.2, 8.4))
        ys = sorted(c for c in cuts if y0 <= c <= y1)
        zs = sorted({FLOOR_Z, 0.65, 1.2, 3.1, 3.3, WIN_Z0, WIN_Z1, DOOR_Z1, WALL_TOP})

        def rk(z0, z1):
            zc = 0.5 * (z0 + z1)
            if zc < 0.65:
                return style["skirt"]
            if zc < 3.1:
                return style["wainscot"]
            if zc < 3.3:
                return style["dado"]
            if zc > DOOR_Z1:
                return style["frieze"]
            return style["upper"]
        grid_wall(mb, s * LIN_X, s, ys, zs, holes, rk, inward=True)
        # sills, dado rails (broken at doors)
        for a_, b_ in lay["wins"]:
            if y0 < a_ < y1:
                cbox(mb, (min(s * LIN_X, s * (LIN_X - 0.4)), a_ - 0.15, WIN_Z0 - 0.16),
                     (max(s * LIN_X, s * (LIN_X - 0.4)), b_ + 0.15, WIN_Z0), style["sill"], ch=0.05)
        segs = [(y0, y1)]
        for a_, b_ in lay["doors"]:
            nxt = []
            for p, q in segs:
                if a_ < q and b_ > p:
                    if a_ - p > 0.3:
                        nxt.append((p, a_))
                    if q - b_ > 0.3:
                        nxt.append((b_, q))
                else:
                    nxt.append((p, q))
            segs = nxt
        if not wall_glass_bays:
            for p, q in segs:
                box(mb, (min(s * LIN_X, s * (LIN_X - 0.12)), p, 3.1), (max(s * LIN_X, s * (LIN_X - 0.12)), q, 3.3),
                    style["dado"], skip=("+x" if s > 0 else "-x", "-y", "+y"))
        for a_, b_ in lay["doors"]:
            if y0 <= a_ < y1:
                xx = s * (LIN_X - 0.06)
                for (ya_, yb_, za, zb) in ((a_ - 0.3, a_, FLOOR_Z, DOOR_Z1 + 0.3), (b_, b_ + 0.3, FLOOR_Z, DOOR_Z1 + 0.3),
                                           (a_, b_, DOOR_Z1, DOOR_Z1 + 0.3)):
                    face_toward(mb, [V((xx, ya_, za)), V((xx, yb_, za)), V((xx, yb_, zb)), V((xx, ya_, zb))],
                                "brass", V((-s, 0, 0)))
        if cove:
            xa, xb = s * LIN_X, s * (LIN_X - 0.6)
            face_toward(mb, [V((xa, y0, WALL_TOP)), V((xa, y1, WALL_TOP)), V((xb, y1, WALL_TOP)), V((xb, y0, WALL_TOP))],
                        style["cove"], V((0, 0, -1)))
            face_toward(mb, [V((xb, y0, WALL_TOP)), V((xb, y1, WALL_TOP)), V((xb, y1, WALL_TOP + 0.45)),
                             V((xb, y0, WALL_TOP + 0.45))], style["cove"], V((-s, 0, 0)))
            face_toward(mb, [V((xb, y0, WALL_TOP + 0.45)), V((xb, y1, WALL_TOP + 0.45)),
                             V((xb + s * 0.08, y1, WALL_TOP + 0.45)), V((xb + s * 0.08, y0, WALL_TOP + 0.45))],
                        "brass", V((0, 0, 1)))
            lt = A.part("Cove", kind="neon", shadow=False)
            face_toward(lt, [V((s * (LIN_X - 0.15), y0, WALL_TOP + 0.06)), V((s * (LIN_X - 0.15), y1, WALL_TOP + 0.06)),
                             V((s * (LIN_X - 0.45), y1, WALL_TOP + 0.06)), V((s * (LIN_X - 0.45), y0, WALL_TOP + 0.06))],
                        "cove", V((0, 0, 1)))
    # the vault
    arc, zc = vault_xz(8)
    if style["ceiling"] == "hammered":
        n_y = max(2, int(round((y1 - y0) / 1.7)))
        grid = []
        for k in range(n_y + 1):
            y = y0 + (y1 - y0) * k / n_y
            row = []
            for i, (x, z) in enumerate(arc):
                if 0 < i < len(arc) - 1 and 0 < k < n_y:
                    d = rng.uniform(-0.13, 0.13)
                    rx, rz = x, z - zc
                    ln = math.hypot(rx, rz)
                    x, z = x + rx / ln * d, z + rz / ln * d
                    y += rng.uniform(-0.18, 0.18) if 0 < k < n_y else 0.0
                row.append(V((x, y, z)))
            grid.append(row)
        vol = mb.nv()
        for k in range(n_y):
            for i in range(len(arc) - 1):
                a, b, c, d = grid[k][i], grid[k][i + 1], grid[k + 1][i + 1], grid[k + 1][i]
                ctr = V((0, 0.5 * (a.y + c.y), zc))
                if (k + i) % 2 == 0:
                    face_toward(mb, [a, b, c], "hammered", ctr - (a + b + c) / 3.0, vol)
                    face_toward(mb, [a, c, d], "hammered", ctr - (a + c + d) / 3.0, vol)
                else:
                    face_toward(mb, [a, b, d], "hammered", ctr - (a + b + d) / 3.0, vol)
                    face_toward(mb, [b, c, d], "hammered", ctr - (b + c + d) / 3.0, vol)
    else:
        n_y = max(1, int(round((y1 - y0) / 6.0)))
        for k in range(n_y):
            ya, yb = y0 + (y1 - y0) * k / n_y, y0 + (y1 - y0) * (k + 1) / n_y
            vol = mb.nv()
            for i in range(len(arc) - 1):
                (xa, za), (xb, zb) = arc[i], arc[i + 1]
                pts = [V((xa, ya, za)), V((xb, ya, zb)), V((xb, yb, zb)), V((xa, yb, za))]
                face_toward(mb, pts, "steel_grey", V((0, 0.5 * (ya + yb), zc)) - sum(pts, V((0, 0, 0))) / 4, vol)
            beam(mb, V((arc[1][0], yb, arc[1][1] - 0.15)), V((arc[-2][0], yb, arc[-2][1] - 0.15)), 0.5, 0.25,
                 "steel_dark")
    for ya in arches:
        path = [V((-LIN_X, ya, FLOOR_Z)), V((-LIN_X, ya, WALL_TOP))] + [V((x, ya, z)) for x, z in arc[1:-1]] + \
               [V((LIN_X, ya, WALL_TOP)), V((LIN_X, ya, FLOOR_Z))]

        def sec(k):
            return [(0.0, -0.45), (0.38, -0.45), (0.38, 0.45), (0.0, 0.45)]
        sweep(mb, path, sec, "wood", up=V((0, 1, 0)), cap0=False, cap1=False,
              keys=lambda k, i: "wood_dark" if i in (0, 2) else "wood")


def floor_planks(mb, y0, y1, x0=-LIN_X, x1=LIN_X, key="parquet", w=1.3, z=FLOOR_Z):
    n = max(1, int(round((x1 - x0) / w)))
    for i in range(n):
        xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
        mb.face(rect_loop(xa, y0, xb, y1, z), key, mb.nv())


def floor_carpet(mb, y0, y1, x0, x1, border=0.35, z=FLOOR_Z + 0.03):
    mb.face(rect_loop(x0 + border, y0 + border, x1 - border, y1 - border, z), "carpet")
    poly_holes(mb, rect_loop(x0, y0, x1, y1, z), [rect_loop(x0 + border, y0 + border, x1 - border, y1 - border, z)],
               "banner_gold", (0, 0, 1))
    for (a, b) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        pts = [V((a[0], a[1], z)), V((b[0], b[1], z)), V((b[0], b[1], FLOOR_Z)), V((a[0], a[1], FLOOR_Z))]
        mid = V((0.5 * (a[0] + b[0]), 0.5 * (a[1] + b[1]), z))
        face_toward(mb, pts, "banner_gold", mid - V((0.5 * (x0 + x1), 0.5 * (y0 + y1), z)))


def floor_tiles(mb, y0, y1, x0=-LIN_X, x1=LIN_X, t=2.625, keys=("marble", "marble_dark"), z=FLOOR_Z):
    nx = max(1, int(round((x1 - x0) / t)))
    ny = max(1, int(round((y1 - y0) / t)))
    for i in range(nx):
        for j in range(ny):
            xa, xb = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
            ya, yb = y0 + (y1 - y0) * j / ny, y0 + (y1 - y0) * (j + 1) / ny
            mb.face(rect_loop(xa, ya, xb, yb, z), keys[(i + j) % 2], mb.nv())


# ------------------------------------------------------------------------------------------------ furniture
def p_banquette(length, depth=2.3, seat_h=1.85, back_h=3.55, key="upholstery", seg=3.2):
    """Bench along local +Y, its back against x = +depth (a wall), the sitter facing -X. Origin = front-centre at
    floor level."""
    m = MB()
    cbox(m, (0.25, -length / 2, 0.0), (depth, length / 2, seat_h - 0.42), "wood_dark", ch=0.06)
    n = max(1, int(round(length / seg)))
    for k in range(n):
        ya, yb = -length / 2 + length * k / n + 0.03, -length / 2 + length * (k + 1) / n - 0.03
        cbox(m, (0.0, ya, seat_h - 0.45), (depth - 0.55, yb, seat_h), key, ch=0.14)
        hull(m, [(depth - 0.62, ya, seat_h), (depth - 0.62, yb, seat_h), (depth - 0.08, ya, seat_h),
                 (depth - 0.08, yb, seat_h), (depth - 0.32, ya, back_h), (depth - 0.32, yb, back_h),
                 (depth - 0.02, ya, back_h - 0.05), (depth - 0.02, yb, back_h - 0.05),
                 (depth - 0.55, ya, back_h - 0.3), (depth - 0.55, yb, back_h - 0.3)], key)
    return m


def p_pleated_bench(length, depth=2.0, seat_h=1.8, back_h=4.2):
    m = MB()
    cbox(m, (0.2, -length / 2, 0.0), (depth, length / 2, seat_h - 0.4), "wood_dark", ch=0.06)
    cbox(m, (0.0, -length / 2, seat_h - 0.42), (depth - 0.4, length / 2, seat_h), "leather", ch=0.14)
    n = int(round(length / 0.55))
    vol = m.nv()
    for k in range(n):
        ya, yb = -length / 2 + length * k / n, -length / 2 + length * (k + 1) / n
        ym = 0.5 * (ya + yb)
        for (za, zb) in ((seat_h, back_h),):
            pts = [V((depth - 0.42, ya, za)), V((depth - 0.62, ym, za)), V((depth - 0.62, ym, zb - 0.1)),
                   V((depth - 0.42, ya, zb))]
            face_toward(m, pts, "leather", V((-1, -0.4, 0)), vol)
            pts = [V((depth - 0.62, ym, za)), V((depth - 0.42, yb, za)), V((depth - 0.42, yb, zb)),
                   V((depth - 0.62, ym, zb - 0.1))]
            face_toward(m, pts, "leather", V((-1, 0.4, 0)), vol)
    cbox(m, (depth - 0.5, -length / 2, back_h), (depth, length / 2, back_h + 0.2), "brass", ch=0.05)
    return m


def p_table(w, l, h=2.7, top="wood", base="brass", cloth=False):
    """Table centred at the origin (w along X, l along Y)."""
    m = MB()
    cbox(m, (-w / 2, -l / 2, h - 0.18), (w / 2, l / 2, h), top, ch=0.06)
    if cloth:
        d = 0.9
        for (a, b, nrm) in (((-w / 2 - 0.05, -l / 2 - 0.05), (w / 2 + 0.05, -l / 2 - 0.05), (0, -1, 0)),
                            ((w / 2 + 0.05, -l / 2 - 0.05), (w / 2 + 0.05, l / 2 + 0.05), (1, 0, 0)),
                            ((w / 2 + 0.05, l / 2 + 0.05), (-w / 2 - 0.05, l / 2 + 0.05), (0, 1, 0)),
                            ((-w / 2 - 0.05, l / 2 + 0.05), (-w / 2 - 0.05, -l / 2 - 0.05), (-1, 0, 0))):
            face_toward(m, [V((a[0], a[1], h + 0.01)), V((b[0], b[1], h + 0.01)), V((b[0], b[1], h - d)),
                            V((a[0], a[1], h - d))], "linen", V(nrm))
        m.face(rect_loop(-w / 2 - 0.05, -l / 2 - 0.05, w / 2 + 0.05, l / 2 + 0.05, h + 0.012), "linen")
    n = max(1, int(round(l / 7.0)))
    for k in range(n):
        y = -l / 2 + l * (k + 0.5) / n
        cyl(m, (0, y, 0.0), (0, y, h - 0.18), 0.22, 0.18, 6, base)
        cbox(m, (-w / 2 + 0.4, y - 0.6, 0.0), (w / 2 - 0.4, y + 0.6, 0.18), base, ch=0.05)
    return m


def p_chair(seat="upholstery", frame="wood_dark"):
    """Dining chair facing +Y, seat centre at the origin's (0, 0)."""
    m = MB()
    for x in (-0.75, 0.75):
        for y in (-0.7, 0.7):
            box(m, (x - 0.1, y - 0.1, 0), (x + 0.1, y + 0.1, 1.45), frame, skip=("-z", "+z"))
    cbox(m, (-0.88, -0.85, 1.45), (0.88, 0.85, 1.75), seat, ch=0.1)
    hull(m, [(-0.85, -0.85, 1.75), (0.85, -0.85, 1.75), (-0.85, -0.6, 1.75), (0.85, -0.6, 1.75),
             (-0.8, -1.05, 4.1), (0.8, -1.05, 4.1), (-0.8, -0.85, 4.1), (0.8, -0.85, 4.1)], frame)
    hull(m, [(-0.68, -0.6, 2.1), (0.68, -0.6, 2.1), (-0.66, -0.78, 3.9), (0.66, -0.78, 3.9),
             (-0.68, -0.5, 2.1), (0.68, -0.5, 2.1), (-0.66, -0.66, 3.9), (0.66, -0.66, 3.9)], seat)
    return m


def p_club_chair(key="velvet"):
    """Velvet tub chair facing +Y."""
    m = MB()
    cbox(m, (-1.35, -1.3, 0.0), (1.35, 1.2, 0.35), "wood_dark", ch=0.08)
    cbox(m, (-1.05, -0.8, 0.35), (1.05, 1.15, 1.55), key, ch=0.22)
    for s in (-1, 1):
        hull(m, [(s * 1.05, -1.3, 0.35), (s * 1.4, -1.3, 0.35), (s * 1.05, 1.2, 0.35), (s * 1.4, 1.2, 0.35),
                 (s * 1.05, -1.2, 2.45), (s * 1.38, -1.2, 2.4), (s * 1.08, 1.05, 2.2), (s * 1.36, 1.0, 2.15)], key)
    hull(m, [(-1.35, -1.3, 0.35), (1.35, -1.3, 0.35), (-1.35, -0.8, 0.35), (1.35, -0.8, 0.35),
             (-1.3, -1.35, 3.4), (1.3, -1.35, 3.4), (-1.1, -0.95, 3.25), (1.1, -0.95, 3.25), (0, -1.4, 3.6)], key)
    return m


def p_side_table(h=2.0, r=0.8, top="wood", base="brass"):
    m = MB()
    lathe(m, [(r, h - 0.12), (r, h)], 8, top)
    m.face([V((r * math.cos(TAU * i / 8), r * math.sin(TAU * i / 8), h - 0.12)) for i in range(8)][::-1], top)
    cyl(m, (0, 0, 0.1), (0, 0, h - 0.12), 0.12, 0.12, 6, base)
    lathe(m, [(0.55, 0.0), (0.5, 0.1), (0.0, 0.12)], 8, base)
    return m


def p_piano():
    """Upright piano bolted to the floor, keyboard facing +Y."""
    m = MB()
    cbox(m, (-2.6, -1.0, 0.25), (2.6, 0.15, 4.6), "piano", ch=0.08)
    cbox(m, (-2.65, -1.05, 4.6), (2.65, 0.2, 4.8), "piano", ch=0.05)
    cbox(m, (-2.5, 0.15, 2.45), (2.5, 1.05, 2.75), "piano", ch=0.05)
    cbox(m, (-2.3, 0.4, 2.75), (2.3, 1.0, 2.85), "keys_white", ch=0.02)
    for k in range(15):
        x = -2.15 + 4.3 * (k + 0.5) / 15
        if k % 7 in (2, 6):
            continue
        cbox(m, (x - 0.06, 0.45, 2.85), (x + 0.06, 0.85, 2.95), "piano", ch=0.0)
    cbox(m, (-2.5, 0.85, 2.85), (2.5, 1.05, 3.3), "piano", ch=0.03)
    for x in (-2.3, 2.3):
        cbox(m, (x - 0.18, 0.15, 0.25), (x + 0.18, 1.0, 2.45), "piano", ch=0.04)
        cbox(m, (x - 0.25, -1.0, 0.0), (x + 0.25, 1.1, 0.25), "brass", ch=0.04)
    cbox(m, (-1.5, -0.98, 0.0), (1.5, 0.12, 0.25), "piano", ch=0.04)
    for x in (-0.35, 0.0, 0.35):
        cbox(m, (x - 0.05, 0.3, 0.5), (x + 0.05, 0.75, 0.6), "brass", ch=0.0)
    return m


def p_globe_stand():
    """Globe drinks cabinet: a wooden stand, the lower hemisphere with a brass meridian (the lid is
    Train_GlobeLid). Globe centre at z 2.7."""
    m = MB()
    for k in range(4):
        a = TAU * (k + 0.5) / 4
        cyl(m, (1.15 * math.cos(a), 1.15 * math.sin(a), 0), (0.95 * math.cos(a), 0.95 * math.sin(a), 2.45), 0.12, 0.12,
            6, "wood_dark")
    torus(m, (0, 0, 2.45), (0, 0, 1), 1.25, 0.12, 16, 4, "wood")
    torus(m, (0, 0, 0.6), (0, 0, 1), 1.05, 0.08, 12, 4, "wood_dark")
    prof = [(0.0, 1.55), (0.45, 1.6)] + [(1.1 * math.sin(math.radians(a)), 2.7 - 1.1 * math.cos(math.radians(a)))
                                           for a in (35, 55, 72, 90)]
    lathe(m, prof, 12, "globe_sea", keys=lambda k, i: "globe_land" if (i * 7 + k * 3) % 5 == 0 else "globe_sea")
    m.face([V((1.1 * math.cos(TAU * i / 12), 1.1 * math.sin(TAU * i / 12), 2.7)) for i in range(12)], "wood")
    torus(m, (0, 0, 2.7), (1, 0, 0), 1.25, 0.06, 16, 4, "brass")
    for k in range(3):
        a = TAU * k / 3
        hull(m, [(0.9 * math.cos(a), 0.9 * math.sin(a), 2.71), (0.9 * math.cos(a) + 0.12, 0.9 * math.sin(a), 2.71),
                 (0.9 * math.cos(a), 0.9 * math.sin(a) + 0.12, 2.71), (0.9 * math.cos(a), 0.9 * math.sin(a), 3.15)],
             "crystal" if False else "brass")
    return m


def p_screen(w=7.2, h=4.2):
    """Wall screen frame (the panel is a separate emissive part), facing -Y, mounted on a wall at y = 0."""
    m = MB()
    poly_holes(m, [V((-w / 2 - 0.35, -0.3, -0.35)), V((w / 2 + 0.35, -0.3, -0.35)), V((w / 2 + 0.35, -0.3, h + 0.35)),
                   V((-w / 2 - 0.35, -0.3, h + 0.35))],
               [[V((-w / 2, -0.3, 0)), V((w / 2, -0.3, 0)), V((w / 2, -0.3, h)), V((-w / 2, -0.3, h))]], "screen_frame",
               (0, -1, 0))
    box(m, (-w / 2 - 0.35, -0.3, -0.35), (w / 2 + 0.35, 0.0, h + 0.35), "screen_frame", skip=("-y", "+y"))
    return m


def p_bunk(length=7.0, width=3.0, z=1.7, sheet="cotton", frame="wood_dark", rails=True):
    """Bunk along Y against x = +width (a wall), top of the mattress at z + 0.5."""
    m = MB()
    cbox(m, (0.0, -length / 2, z - 0.25), (width, length / 2, z), frame, ch=0.05)
    cbox(m, (0.08, -length / 2 + 0.1, z), (width - 0.05, length / 2 - 0.1, z + 0.45), sheet, ch=0.14)
    cbox(m, (0.5, length / 2 - 1.6, z + 0.45), (width - 0.4, length / 2 - 0.3, z + 0.75), sheet, ch=0.12)
    hull(m, [(0.06, -length / 2 + 0.15, z + 0.45), (width - 0.1, -length / 2 + 0.15, z + 0.45),
             (0.06, 0.6, z + 0.45), (width - 0.1, 0.6, z + 0.45), (0.0, -length / 2 + 0.1, z + 0.62),
             (0.0, 0.7, z + 0.6), (width - 0.15, 0.5, z + 0.64), (width - 0.15, -length / 2 + 0.15, z + 0.62)],
         "banner" if sheet == "silk" else "blind")
    if rails:
        cbox(m, (-0.05, -length / 2 + 0.3, z + 0.45), (0.12, length / 2 - 0.3, z + 0.65), "brass", ch=0.03)
    return m


def p_uniform():
    """A pressed tribute uniform on a brass hanger (our own: plain charcoal-blue jacket and trousers)."""
    m = MB()
    cyl(m, (0, 0, 7.1), (0, 0, 7.35), 0.05, 0.05, 4, "brass")
    hull(m, [(-0.95, 0, 6.85), (0.95, 0, 6.85), (0, 0, 7.12), (0, 0.06, 7.0), (0, -0.06, 7.0)], "brass")
    hull(m, [(-0.95, -0.22, 6.8), (0.95, -0.22, 6.8), (-0.95, 0.22, 6.8), (0.95, 0.22, 6.8),
             (-0.85, -0.2, 4.6), (0.85, -0.2, 4.6), (-0.85, 0.2, 4.6), (0.85, 0.2, 4.6), (0, 0.3, 6.95)], "uniform")
    for s in (-1, 1):
        hull(m, [(s * 0.95, -0.16, 6.8), (s * 1.12, -0.16, 6.7), (s * 0.95, 0.16, 6.8), (s * 1.12, 0.16, 6.7),
                 (s * 1.0, -0.14, 4.9), (s * 1.18, -0.14, 4.95), (s * 1.0, 0.14, 4.9), (s * 1.18, 0.14, 4.95)],
             "uniform")
        hull(m, [(s * 0.05, -0.16, 4.5), (s * 0.75, -0.16, 4.5), (s * 0.05, 0.16, 4.5), (s * 0.75, 0.16, 4.5),
                 (s * 0.1, -0.14, 2.0), (s * 0.6, -0.14, 2.0), (s * 0.1, 0.14, 2.0), (s * 0.6, 0.14, 2.0)], "uniform")
    cbox(m, (-0.85, -0.12, 4.5), (0.85, 0.12, 4.62), "harness", ch=0.02)
    return m


def p_handrail(h=7.2):
    m = MB()
    cyl(m, (0, 0, FLOOR_Z), (0, 0, FLOOR_Z + h), 0.13, 0.13, 8, "brass")
    for z in (FLOOR_Z, FLOOR_Z + h):
        lathe(m, [(0.28, z - 0.02), (0.28, z + 0.08), (0.14, z + 0.18)] if z < 1 else
              [(0.14, z - 0.18), (0.28, z - 0.08), (0.28, z + 0.02)], 8, "brass")
    return m


def p_jump_seat():
    m = MB()
    cbox(m, (0.0, -0.9, 2.2), (0.35, 0.9, 4.0), "steel_dark", ch=0.06)
    cbox(m, (0.35, -0.85, 2.3), (0.55, 0.85, 3.9), "steel_plate", ch=0.05)
    cbox(m, (0.0, -1.0, 4.4), (0.2, 1.0, 5.6), "steel_plate", ch=0.05)
    return m


def p_locker(w=2.4, d=1.6, h=7.0):
    m = MB()
    cbox(m, (0.0, -w / 2, 0.0), (d, w / 2, h), "slate_steel", ch=0.06)
    for y in (-w / 4, w / 4):
        cbox(m, (-0.04, y - w / 4 + 0.08, 0.3), (0.02, y + w / 4 - 0.08, h - 0.3), "steel_grey", ch=0.02)
        cbox(m, (-0.12, y + (0.3 if y < 0 else -0.3) - 0.05, 3.2), (-0.02, y + (0.3 if y < 0 else -0.3) + 0.05, 4.0),
             "steel", ch=0.0)
    return m


# ------------------------------------------------------------------------------------------------ kits
def corridor_lamps(A, fu, x, y0, y1, step=10.5):
    """Small brass ceiling lamps down a corridor (neon bulbs + attachments for PointLights)."""
    arc, zc = vault_xz()
    R = math.hypot(arc[0][0], arc[0][1] - zc)
    z = zc + math.sqrt(max(0.0, R * R - x * x))
    lp = A.part("CeilingLamps", kind="neon", shadow=False)
    n = int((y1 - y0) // step)
    for k in range(n):
        y = y0 + step * (k + 0.5)
        lathe(fu, [(0.0, z - 0.45), (0.4, z - 0.4), (0.5, z - 0.12), (0.52, z + 0.05)], 8, "brass", c=(x, y, 0.0),
              cap1=False)
        disc(lp, (x, y, z - 0.46), 0.32, 8, (0, 0, -1), "bulb")
        A.att("CeilingLamp_%d" % (k + 1), (x, y, z - 0.5), (0, 0, -1), (0, 1, 0),
              note="PointLight Range 9, Brightness 0.7, warm (255, 200, 140)")


def kit_asset(name, car_kind, notes, tags=()):
    A = Asset(name, "TrainInterior", "Train_Interiors.glb", tags=["Train", "Interior", "Walkable"] + list(tags),
              notes=notes + " Fits inside %s (same origin: car footprint centre at platform level; floor 0.3 up). "
              "Two texture sets: the room and the furniture (1024 each)."
              % {"nose": "Train_NoseCar", "body": "Train_BodyCar", "obs": "Train_ObservationCar"}[car_kind])
    A.part("Furniture", tset=name + "_Furniture", size=1024)
    return A


def kit_ends(A, lay, ends, style_key="wood", door_frame="brass", inset=0.0):
    """Interior end walls (gangway doorways) at the car ends."""
    mb = A.part("Room")
    L = lay["L"]
    for e in ends:
        ye = (L / 2 - 0.6) if e == "front" else -(L / 2 - 0.6)
        face = -1 if e == "front" else 1
        wall_with_door(mb, ye, face, style_key, frame_key=door_frame, inset=inset)
        A.att("GangwayDoor%s" % ("Front" if e == "front" else "Rear"), (0, ye, FLOOR_Z), (0, -face, 0), (0, 0, 1),
              note="Train_GangwayDoor closed here (its +Y along look); slides 4.2 along +X")


def interior_lights_att(A, y0, y1):
    A.att("CoveLights", (0, 0.5 * (y0 + y1), WALL_TOP + 0.1), (0, 0, 1), (0, 1, 0),
          note="SurfaceLights on the Cove parts, Face Top, Color (255, 196, 128), Brightness 1.2, Range 10, Angle 120 "
               "(amber cove light washing the vault); darkness comes from this rig, not the paint")


def build_car1_vestibule():
    lay = car_layout("nose")
    A = kit_asset("Train_Car1_Vestibule", "nose",
                  "Car 1 (spec section 9): the vestibule where tributes board (the front plug doors, brass handrails, "
                  "a pleated leather bench, a console with the bud vase; Train_VestibuleDoor seals it with a pneumatic "
                  "thump), then a saloon of geometric-upholstery banquettes under the brass windows (the film's "
                  "train interior), a rear vestibule and the cab bulkhead (locked door).", tags=["Car1"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    rng = random.Random(SEED + 101)
    yb, yf = -(NOSE_CAR_L / 2 - 0.6), 27.5
    lining(A, mb, lay, yb, yf, STYLE_SALOON, rng, arches=(-36.5, -12.0, 17.5))
    floor_tiles(mb, 17.5, yf)
    floor_tiles(mb, yb, -36.5)
    floor_planks(mb, -36.5, 17.5, -LIN_X, -1.6)
    floor_planks(mb, -36.5, 17.5, 1.6, LIN_X)
    floor_carpet(mb, -36.5, 17.5, -1.6, 1.6, border=0.25)
    face_toward(mb, section_poly(yf), "wood_dark", V((0, -1, 0)))
    wall_with_door(mb, -36.5, 1, "wood", thick=0.4, frame_key="brass")
    kit_ends(A, lay, ("rear",))
    # the pneumatic partition: brass frame and glass either side of the sliding door
    gl = A.part("Glass", kind="glass", shadow=False)
    yp = 17.5
    for xa, xb in ((-LIN_X, -DOOR_W / 2 - 0.3), (DOOR_W / 2 + 0.3, LIN_X)):
        cbox(fu, (xa, yp - 0.15, FLOOR_Z), (xb, yp + 0.15, 1.3), "wood_dark", ch=0.05)
        for x in (xa, xb):
            cbox(fu, (x - 0.15, yp - 0.18, FLOOR_Z), (x + 0.15, yp + 0.18, WALL_TOP), "brass", ch=0.04)
        cbox(fu, (xa, yp - 0.18, 1.3), (xb, yp + 0.18, 1.5), "brass", ch=0.04)
        box(gl, (xa + 0.15, yp - 0.04, 1.5), (xb - 0.15, yp + 0.04, WALL_TOP), "glass", skip=("-x", "+x", "-z", "+z"))
    cbox(fu, (-DOOR_W / 2 - 0.3, yp - 0.18, DOOR_Z1), (DOOR_W / 2 + 0.3, yp + 0.18, WALL_TOP), "brass", ch=0.04)
    A.att("VestibuleDoor", (0, yp, FLOOR_Z), (1, 0, 0), (0, 0, 1),
          note="Train_VestibuleDoor closed here; slides 4.3 along +X (the pneumatic thump; the outside sound dies)")
    # brass handrails at the front doors, the pleated leather bench on the bulkhead, the console with the vase
    for s in (-1, 1):
        for y in (20.6, 25.4):
            place(fu, p_handrail(), (s * (LIN_X - 0.45), y, 0.0))
    place(fu, p_pleated_bench(6.0), (-1.6, yf - 2.0, FLOOR_Z), 90)
    con = MB()
    cbox(con, (-1.2, -0.5, 2.6), (1.2, 0.5, 2.85), "wood", ch=0.05)
    for x in (-1.0, 1.0):
        cyl(con, (x, 0, 0), (x, 0, 2.6), 0.1, 0.08, 6, "brass")
    cbox(con, (-1.1, -0.4, 0.0), (1.1, 0.4, 0.12), "brass", ch=0.03)
    place(fu, con, (3.7, yf - 0.9, FLOOR_Z), 0)
    A.att("BudVase", (3.7, yf - 0.9, FLOOR_Z + 2.85), (0, 1, 0), (0, 0, 1),
          note="Train_BudVase stands here (a loose object: it slides with the sway)")
    # saloon: banquettes under the windows, small tables between facing pairs
    for s in (-1, 1):
        for c in (-32.5, -24.5, -16.5, -8.5, -0.5, 7.5):
            place(fu, p_banquette(6.4), (s * (LIN_X - 2.3), c, FLOOR_Z), 0 if s > 0 else 180)
        for c in (-20.5, 3.5):
            place(fu, p_side_table(2.1, 0.75), (s * (LIN_X - 3.2), c, FLOOR_Z))
    interior_lights_att(A, yb, yf)
    A.att("Beat_Window", (3.0, -0.5, FLOOR_Z), (1, 0, 0), (0, 0, 1),
          note="proximity beat: sit at the saloon window as the country passes")
    A.collider((-LIN_X, yf, FLOOR_Z), (LIN_X, yf + 0.4, 9.9))
    return A


def build_car2_dining():
    lay = car_layout("body")
    A = kit_asset("Train_Car2_Dining", "body",
                  "Car 2 (spec section 9): mahogany panelling with a silver rail (for the spec's filigree), the "
                  "hammered cream-gold vault and wood-and-brass arches, one long table in white linen with our own "
                  "runner motif, plates with a plain gold rim (no seal, no crests), silver, twelve chairs in the "
                  "geometric upholstery, sconces; two Train_Chandelier on gimbals and Train_Crystal glasses are "
                  "separate (moving).", tags=["Car2"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    rng = random.Random(SEED + 102)
    yb, yf = -(CAR_L / 2 - 0.6), CAR_L / 2 - 0.6
    lining(A, mb, lay, yb, yf, STYLE_DINING, rng, arches=(-31.5, -12.0, 12.0, 31.5))
    floor_tiles(mb, yb, -31.5)
    floor_tiles(mb, 31.5, yf)
    floor_carpet(mb, -31.5, 31.5, -LIN_X, LIN_X, border=0.45)
    for y, f in ((-31.5, 1), (31.5, -1)):
        wall_with_door(mb, y, f, "wood_dark", thick=0.4, frame_key="brass")
    kit_ends(A, lay, ("rear", "front"), style_key="wood_dark")
    TX = -0.9           # the table sits off-centre so the +X aisle stays walkable (2.6 wide)
    place(fu, p_table(2.8, 34.0, cloth=True, top="wood_dark"), (TX, 0, FLOOR_Z))
    th = FLOOR_Z + 2.7 + 0.015
    fu.face(rect_loop(TX - 0.3, -16.5, TX + 0.3, 16.5, th + 0.004), "runner")
    k = 0
    for side in (-1, 1):
        for i in range(6):
            y = -13.75 + 5.5 * i
            place(fu, p_chair(), (TX + side * 2.45, y, FLOOR_Z), 90 if side > 0 else -90)
            px = TX + side * 0.85
            lathe(fu, [(0.0, th), (0.6, th + 0.005), (0.62, th + 0.07), (0.5, th + 0.075), (0.0, th + 0.06)], 8,
                  "porcelain", c=(px, y, 0.0), keys=lambda kk, ii: "brass" if kk == 2 else "porcelain")
            for dy, key in ((-0.75, "silver"), (0.75, "silver"), (0.93, "silver")):
                cbox(fu, (px - 0.35, y + dy - 0.05, th), (px + 0.35, y + dy + 0.05, th + 0.04), key, ch=0.0)
            A.att("Glass_%d" % (k + 1), (TX + side * 0.4, y + 0.85, th), (0, 1, 0), (0, 0, 1),
                  note="Train_Crystal stands here (rings and slides with the sway)")
            A.att("Seat_%d" % (k + 1), (TX + side * 2.45, y, FLOOR_Z + 1.75), (-side, 0, 0), (0, 0, 1))
            k += 1
    for s in (-1, 1):
        for c in (-28.0, -20.0, -12.0, -4.0, 4.0, 12.0, 20.0, 28.0):
            if abs(c) > 30:
                continue
            sc = MB()
            cbox(sc, (-0.18, -0.35, 5.6), (0.0, 0.35, 6.4), "silver", ch=0.04)
            hull(sc, [(-0.05, -0.3, 6.2), (-0.05, 0.3, 6.2), (-0.65, -0.35, 6.4), (-0.65, 0.35, 6.4),
                      (-0.35, 0.0, 6.9), (-0.1, -0.2, 6.7), (-0.1, 0.2, 6.7)], "wall_cream")
            place(fu, sc, (s * (LIN_X - 0.05), c, 0.0), 0 if s > 0 else 180)
            lt = A.part("Sconces", kind="neon", shadow=False)
            disc(lt, (s * (LIN_X - 0.42), c, 6.55), 0.18, 6, (0, 0, 1), "bulb")
    for i, y in enumerate((-9.0, 9.0)):
        A.att("Chandelier_%d" % (i + 1), (TX, y, VAULT_Z - 0.1), (0, 0, -1), (0, 1, 0),
              note="Train_Chandelier hangs here (its origin at the hang point); swings on its gimbal with the sway; "
                   "PointLight Range 14, Brightness 1.5, Color (255, 214, 160) at its centre")
    interior_lights_att(A, yb, yf)
    A.att("Beat_Table", (TX, 0, FLOOR_Z), (0, 1, 0), (0, 0, 1),
          note="proximity beat: sit at the table (the awkward-silence timer)")
    return A


def build_car3_lounge():
    lay = car_layout("body")
    A = kit_asset("Train_Car3_Lounge", "body",
                  "Car 3 (spec section 9): oxblood velvet club chairs with brass side tables, a globe drinks cabinet "
                  "(its lid Train_GlobeLid opens), a piano bolted to the floor, the propaganda screen (the only cool "
                  "light in the car; our own looping content), amber coves, Train_PendantLamp x3 (separate, swing).",
                  tags=["Car3"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    rng = random.Random(SEED + 103)
    yb, yf = -(CAR_L / 2 - 0.6), CAR_L / 2 - 0.6
    lining(A, mb, lay, yb, yf, STYLE_SALOON, rng, arches=(-31.5, 0.0, 31.5))
    floor_tiles(mb, yb, -31.5)
    floor_tiles(mb, 31.5, yf)
    floor_planks(mb, -31.5, 31.5)
    floor_carpet(mb, -22.0, 22.0, -3.6, 3.6, border=0.4)
    wall_with_door(mb, -31.5, 1, "wood", door=(1.0, 1.0 + DOOR_W), thick=0.4, frame_key="brass")
    wall_with_door(mb, 31.5, -1, "wood", door=(-1.05 - DOOR_W, -1.05), thick=0.4, frame_key="brass")
    kit_ends(A, lay, ("rear", "front"))
    for s in (-1, 1):
        for c in (-20.0, -4.0, 12.0):
            place(fu, p_club_chair(), (s * 2.9, c - 2.4, FLOOR_Z), 0)
            place(fu, p_club_chair(), (s * 2.9, c + 2.4, FLOOR_Z), 180)
            place(fu, p_side_table(2.0, 0.7), (s * (LIN_X - 0.9), c, FLOOR_Z))
    place(fu, p_globe_stand(), (0.0, -27.0, FLOOR_Z))
    A.att("GlobeLid", (0.0, -27.0, FLOOR_Z + 2.7), (0, 1, 0), (0, 0, 1),
          note="Train_GlobeLid sits here (hinge at its -Y edge); the 'pour from the cabinet' beat opens it")
    A.att("Beat_Cabinet", (0.0, -24.5, FLOOR_Z), (0, -1, 0), (0, 0, 1), note="proximity beat: pour from the cabinet")
    place(fu, p_piano(), (2.45, 28.6, FLOOR_Z), 180)
    place(fu, p_screen(4.8, 2.9), (-2.4, -31.5, 3.9), 180)
    sc = A.part("Screen", kind="neon", shadow=False)
    face_toward(sc, [V((-4.8, -31.17, 3.9)), V((0.0, -31.17, 3.9)), V((0.0, -31.17, 6.8)), V((-4.8, -31.17, 6.8))],
                "screen", V((0, 1, 0)))
    A.att("Screen", (-2.4, -31.0, 5.35), (0, 1, 0), (0, 0, 1),
          note="SurfaceLight on the Screen part, Face Front, cool Color (132, 172, 214), Brightness 0.8, Range 16; a "
               "SurfaceGui or Decal with our own looping content (fashion, recaps, a smiling host), never film footage")
    A.att("Beat_Screen", (-2.4, -25.0, FLOOR_Z), (0, -1, 0), (0, 0, 1), note="proximity beat: watch the screen")
    for i, y in enumerate((-12.0, 4.0, 20.0)):
        A.att("Pendant_%d" % (i + 1), (0, y, VAULT_Z - 0.05), (0, 0, -1), (0, 1, 0),
              note="Train_PendantLamp hangs here; swings with the sway; PointLight Range 10 warm")
    interior_lights_att(A, yb, yf)
    return A


def compartment_room(A, mb, fu, gl, ya, yb, door_y, dressed, rng, x_part=0.9):
    """A compartment between the partition (x = x_part) and the outer wall (-LIN_X), from ya to yb."""
    poly = lambda y: [V((-LIN_X, y, FLOOR_Z)), V((x_part, y, FLOOR_Z)), V((x_part, y, WALL_TOP + 0.6)),
                      V((-LIN_X, y, WALL_TOP + 0.6))]
    face_toward(mb, poly(ya + 0.05), "wall_cream", V((0, 1, 0)))
    face_toward(mb, poly(yb - 0.05), "wall_cream", V((0, -1, 0)))
    mb.face(list(reversed(rect_loop(-LIN_X, ya, x_part, yb, WALL_TOP + 0.6))), "hammered")
    cx_, cy_ = 0.5 * (-LIN_X + x_part), 0.5 * (ya + yb)
    lathe(fu, [(0.0, WALL_TOP + 0.25), (0.45, WALL_TOP + 0.3), (0.55, WALL_TOP + 0.55), (0.6, WALL_TOP + 0.6)], 8,
          "brass", c=(cx_, cy_, 0.0), cap1=False)
    lp = A.part("CeilingLamps", kind="neon", shadow=False)
    disc(lp, (cx_, cy_, WALL_TOP + 0.24), 0.4, 8, (0, 0, -1), "bulb")
    A.att("CeilingLamp_c%d" % int(round(cy_)), (cx_, cy_, WALL_TOP + 0.2), (0, 0, -1), (0, 1, 0),
          note="PointLight Range 10, Brightness 0.8, warm (255, 200, 140)")
    floor_carpet(mb, ya + 0.05, yb - 0.05, -LIN_X, x_part, border=0.3)
    zt = WALL_TOP + 0.6
    grid_wall(mb, x_part - 0.2, 1, [ya, door_y - DOOR_W / 2, door_y + DOOR_W / 2, yb], [FLOOR_Z, DOOR_Z1, zt],
              [(door_y - DOOR_W / 2, door_y + DOOR_W / 2, FLOOR_Z, DOOR_Z1)], lambda z0, z1: "wall_cream",
              inward=True)
    if dressed:
        # District 12: two bunks (silk above? no: one made up in silk, one in plain cotton), a fold-down basin with a
        # chipped mirror, the window seat, the pressed uniform, the brass plaque under the window
        place(fu, p_bunk(7.0, 2.9, 1.6, "silk"), (x_part - 3.1, ya + 3.8, 0.0), 0)
        place(fu, p_bunk(7.0, 2.9, 5.3, "cotton"), (x_part - 3.1, ya + 3.8, 0.0), 0)
        for y in (ya + 0.35, ya + 7.25):
            cbox(fu, (x_part - 0.45, y - 0.12, FLOOR_Z), (x_part - 0.2, y + 0.12, 7.6), "wood_dark", ch=0.03)
        for z in (2.6, 3.4, 4.2, 5.0):
            cbox(fu, (x_part - 0.42, ya + 7.0, z - 0.06), (x_part - 0.24, ya + 7.5, z + 0.06), "brass", ch=0.0)
        place(fu, p_banquette(6.0, depth=1.9, seat_h=1.8, back_h=3.5), (-LIN_X + 1.9, 0.5 * (ya + yb) + 0.5, FLOOR_Z),
              180)
        bas = MB()
        cbox(bas, (-1.0, -0.05, 2.9), (1.0, 0.0, 3.0), "brass", ch=0.0)
        hull(bas, [(-0.9, 0.0, 3.0), (0.9, 0.0, 3.0), (-0.9, -1.2, 3.0), (0.9, -1.2, 3.0), (-0.7, -0.15, 2.6),
                   (0.7, -0.15, 2.6), (-0.7, -1.0, 2.6), (0.7, -1.0, 2.6)], "porcelain")
        cyl(bas, (0, -0.15, 3.0), (0, -0.15, 3.5), 0.07, 0.07, 6, "brass")
        cyl(bas, (0, -0.15, 3.5), (0, -0.55, 3.45), 0.06, 0.05, 6, "brass")
        cbox(bas, (-1.0, -0.12, 4.0), (1.0, 0.0, 6.4), "brass", ch=0.03)
        place(fu, bas, (-2.6, yb - 0.05, FLOOR_Z), 0)
        mir = A.part("Mirror")
        face_toward(mir, [V((-3.5, yb - 0.2, FLOOR_Z + 4.12)), V((-1.7, yb - 0.2, FLOOR_Z + 4.12)),
                          V((-1.7, yb - 0.2, FLOOR_Z + 5.85)), V((-2.15, yb - 0.2, FLOOR_Z + 6.28)),
                          V((-3.5, yb - 0.2, FLOOR_Z + 6.28))], "mirror", V((0, -1, 0)))
        place(fu, p_uniform(), (x_part - 0.5, door_y + 3.5, FLOOR_Z), 90)
        cbox(fu, (-LIN_X, 0.5 * (ya + yb) - 0.45, 3.0), (-LIN_X + 0.06, 0.5 * (ya + yb) + 0.45, 3.35), "brass",
             ch=0.02)
        A.att("Plaque", (-LIN_X + 0.07, 0.5 * (ya + yb), 3.17), (1, 0, 0), (0, 0, 1),
              note="small brass plaque under the window: the district number goes here as a texture/text once names "
                   "are decided (blank now)")
        A.att("Beat_Bunk", (x_part - 1.5, ya + 3.8, FLOOR_Z), (-1, 0, 0), (0, 0, 1), note="the compartment")
    else:
        place(fu, p_bunk(7.0, 2.9, 1.6, "cotton"), (x_part - 3.1, ya + 3.8, 0.0), 0)
        place(fu, p_bunk(7.0, 2.9, 5.3, "cotton"), (x_part - 3.1, ya + 3.8, 0.0), 0)
        place(fu, p_banquette(5.0, depth=1.9, seat_h=1.8, back_h=3.5), (-LIN_X + 1.9, 0.5 * (ya + yb) + 1.0, FLOOR_Z),
              180)


def corridor_partition(A, mb, x_part, y0, y1, doors, open_doors, door_key="wood_dark"):
    """The corridor wall (faces +X into the corridor) with compartment doors; locked doors are fixed panels."""
    zs = [FLOOR_Z, 0.65, 3.1, 3.3, DOOR_Z1, WALL_TOP]
    ys = sorted({y0, y1} | {d - DOOR_W / 2 for d in doors} | {d + DOOR_W / 2 for d in doors})
    holes = [(d - DOOR_W / 2, d + DOOR_W / 2, FLOOR_Z, DOOR_Z1) for d in doors]

    def rk(z0, z1):
        zc = 0.5 * (z0 + z1)
        return "wood_dark" if zc < 0.65 else ("wood" if zc < 3.1 else ("brass" if zc < 3.3 else "wall_cream"))
    grid_wall(mb, x_part, -1, ys, zs, holes, rk, inward=True)
    zt = VAULT_Z
    face_toward(mb, [V((x_part, y0, WALL_TOP)), V((x_part, y1, WALL_TOP)), V((x_part, y1, zt)), V((x_part, y0, zt))],
                "wood", V((1, 0, 0)))
    for d in doors:
        door_jambs(mb, -1, d - DOOR_W / 2, d + DOOR_W / 2, FLOOR_Z, DOOR_Z1, x_out=-x_part, x_in=-(x_part - 0.2),
                   key="brass")
        if d not in open_doors:
            face_toward(mb, [V((x_part - 0.08, d - DOOR_W / 2, FLOOR_Z)), V((x_part - 0.08, d + DOOR_W / 2, FLOOR_Z)),
                             V((x_part - 0.08, d + DOOR_W / 2, DOOR_Z1)), V((x_part - 0.08, d - DOOR_W / 2, DOOR_Z1))],
                        door_key, V((1, 0, 0)))
            cbox(mb, (x_part - 0.06, d - 0.5, 5.6), (x_part + 0.0, d + 0.5, 6.0), "brass", ch=0.0)
            cbox(mb, (x_part - 0.06, d + 1.4, 3.3), (x_part + 0.04, d + 1.55, 4.0), "brass", ch=0.0)
        A.att("CompartmentDoor_%d" % (doors.index(d) + 1), (x_part - 0.1, d, FLOOR_Z), (0, 1, 0), (0, 0, 1),
              note=("Train_CompartmentDoor here; slides 4.2 along +Y" if d in open_doors else
                    "locked: a fixed panel in the wall"))


def build_car4_corridor():
    lay = car_layout("body")
    A = kit_asset("Train_Car4_Corridor", "body",
                  "Car 4 (spec section 9): the narrow corridor (4.3 wide) along the windows, brass handrail and "
                  "fittings, a strip of patterned carpet, six compartment doors: two open (Train_CompartmentDoor) "
                  "into small tribute compartments, four locked with blinds drawn behind them.", tags=["Car4"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    gl = A.part("Glass", kind="glass", shadow=False)
    rng = random.Random(SEED + 104)
    yb, yf = -(CAR_L / 2 - 0.6), CAR_L / 2 - 0.6
    x_part = 0.9
    lining(A, mb, lay, yb, yf, STYLE_SALOON, rng, arches=(-31.5, 31.5), skip_sides=())
    floor_tiles(mb, yb, -31.5)
    floor_tiles(mb, 31.5, yf)
    floor_planks(mb, -31.5, 31.5, x_part, LIN_X)
    floor_carpet(mb, -31.5, 31.5, x_part + 0.9, LIN_X - 0.9, border=0.25)
    wall_with_door(mb, -31.5, 1, "wood", door=(1.05, 1.05 + DOOR_W), thick=0.4, frame_key="brass")
    wall_with_door(mb, 31.5, -1, "wood", door=(1.05, 1.05 + DOOR_W), thick=0.4, frame_key="brass")
    kit_ends(A, lay, ("rear", "front"))
    corridor_lamps(A, fu, 3.1, -31.5, 31.5)
    doors = [-26.25, -15.75, -5.25, 5.25, 15.75, 26.25]
    open_doors = [-5.25, 5.25]
    corridor_partition(A, mb, x_part, -31.5, 31.5, doors, open_doors)
    cuts = [-31.5, -21.0, -10.5, 0.0, 10.5, 21.0, 31.5]
    for k in range(6):
        ya, yb_ = cuts[k], cuts[k + 1]
        if doors[k] in open_doors:
            compartment_room(A, mb, fu, gl, ya, yb_, doors[k], False, rng, x_part)
        else:
            face_toward(mb, [V((-LIN_X, ya + 0.05, FLOOR_Z)), V((x_part, ya + 0.05, FLOOR_Z)),
                             V((x_part, ya + 0.05, WALL_TOP + 0.6)), V((-LIN_X, ya + 0.05, WALL_TOP + 0.6))],
                        "wall_cream", V((0, 1, 0)))
    for a_, b_ in lay["wins"]:
        mid = 0.5 * (a_ + b_)
        k = max(0, min(5, int((mid + 31.5) // 10.5)))
        if doors[k] not in open_doors:
            face_toward(fu, [V((-LIN_X + 0.3, a_, WIN_Z0)), V((-LIN_X + 0.3, b_, WIN_Z0)), V((-LIN_X + 0.3, b_, WIN_Z1)),
                             V((-LIN_X + 0.3, a_, WIN_Z1))], "blind", V((1, 0, 0)))
            face_toward(fu, [V((-LIN_X + 0.32, a_, WIN_Z0)), V((-LIN_X + 0.32, b_, WIN_Z0)),
                             V((-LIN_X + 0.32, b_, WIN_Z1)), V((-LIN_X + 0.32, a_, WIN_Z1))], "blind", V((-1, 0, 0)))
    cyl(mb, (LIN_X - 0.35, -31.0, 3.9), (LIN_X - 0.35, 31.0, 3.9), 0.1, 0.1, 6, "brass")
    for y in range(-30, 31, 6):
        cbox(mb, (LIN_X - 0.4, y - 0.08, 3.75), (LIN_X, y + 0.08, 3.85), "brass", ch=0.0)
    interior_lights_att(A, yb, yf)
    return A


def build_car5_compartment():
    lay = car_layout("body")
    A = kit_asset("Train_Car5_Compartment", "body",
                  "Car 5 (spec section 9): the corridor and three compartments; the middle one is District 12's: one "
                  "bunk made up in silk, one in plain cotton, a fold-down basin with a chipped mirror, the "
                  "upholstered window seat, a pressed uniform waiting, a blank brass plaque under the window. Every "
                  "surface is bolted.", tags=["Car5"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    gl = A.part("Glass", kind="glass", shadow=False)
    rng = random.Random(SEED + 105)
    yb, yf = -(CAR_L / 2 - 0.6), CAR_L / 2 - 0.6
    x_part = 0.9
    lining(A, mb, lay, yb, yf, STYLE_SALOON, rng, arches=(-31.5, 31.5))
    floor_tiles(mb, yb, -31.5)
    floor_tiles(mb, 31.5, yf)
    floor_planks(mb, -31.5, 31.5, x_part, LIN_X)
    floor_carpet(mb, -31.5, 31.5, x_part + 0.9, LIN_X - 0.9, border=0.25)
    wall_with_door(mb, -31.5, 1, "wood", door=(1.05, 1.05 + DOOR_W), thick=0.4, frame_key="brass")
    wall_with_door(mb, 31.5, -1, "wood", door=(1.05, 1.05 + DOOR_W), thick=0.4, frame_key="brass")
    kit_ends(A, lay, ("rear", "front"))
    corridor_lamps(A, fu, 3.1, -31.5, 31.5)
    doors = [-21.0, 0.0, 21.0]
    corridor_partition(A, mb, x_part, -31.5, 31.5, doors, doors)
    cuts = [-31.5, -10.5, 10.5, 31.5]
    for k in range(3):
        compartment_room(A, mb, fu, gl, cuts[k], cuts[k + 1], doors[k], k == 1, rng, x_part)
    cyl(mb, (LIN_X - 0.35, -31.0, 3.9), (LIN_X - 0.35, 31.0, 3.9), 0.1, 0.1, 6, "brass")
    interior_lights_att(A, yb, yf)
    A.att("Beat_Window", (-2.5, 0.0, FLOOR_Z), (-1, 0, 0), (0, 0, 1), note="the window seat")
    return A


def build_car6_observation():
    lay = car_layout("obs")
    A = kit_asset("Train_Car6_Observation", "obs",
                  "Car 6 (spec section 9): glass on three sides (both flanks floor to ceiling and the roof), a long "
                  "curved bench in the geometric upholstery facing each flank, low tables, a floor-level amber cove so "
                  "the night outside stays readable. The districts (and the night bridge, Train_BridgeBackdrop) pass "
                  "outside.", tags=["Car6"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    yb, yf = -(CAR_L / 2 - 0.6), CAR_L / 2 - 0.6
    floor_planks(mb, yb, yf)
    floor_carpet(mb, -33.0, 33.0, -3.2, 3.2, border=0.35)
    for s in (-1, 1):
        face_toward(mb, [V((s * (HWID - 0.3), yb, FLOOR_Z)), V((s * (HWID - 0.3), yf, FLOOR_Z)),
                         V((s * (HWID - 0.3), yf, 1.2)), V((s * (HWID - 0.3), yb, 1.2))], "wood_dark", V((-s, 0, 0)))
        cbox(mb, (min(s * (HWID - 0.3), s * (HWID - 0.75)), yb, 1.05), (max(s * (HWID - 0.3), s * (HWID - 0.75)), yf, 1.2),
             "brass", ch=0.03)
        lt = A.part("Cove", kind="neon", shadow=False)
        face_toward(lt, [V((s * (HWID - 0.5), yb, 1.22)), V((s * (HWID - 0.5), yf, 1.22)), V((s * (HWID - 0.7), yf, 1.22)),
                         V((s * (HWID - 0.7), yb, 1.22))], "cove", V((0, 0, 1)))
    kit_ends(A, lay, ("rear", "front"), inset=-0.22)
    # curved benches: one bulging toward each flank (the sitter faces the glass)
    for s, (ya, yb_) in ((1, (2.0, 30.0)), (-1, (-30.0, -2.0))):
        yc, half = 0.5 * (ya + yb_), 0.5 * (yb_ - ya)
        n = 9
        F = []
        for k in range(n + 1):
            y = ya + (yb_ - ya) * k / n
            u = (y - yc) / half
            F.append(V((s * (2.4 + 0.9 * (1.0 - u * u)), y, 0.0)))
        back = V((-s * 2.1, 0.0, 0.0))
        for k in range(n):
            p0, p1 = F[k], F[k + 1]
            seat = [p0, p1, p1 + back, p0 + back]
            hull(fu, [q + V((0, 0, z)) for q in seat for z in (FLOOR_Z, 1.4)], "wood_dark")
            hull(fu, [q + V((0, 0, z)) for q in seat for z in (1.4, 1.85)], "upholstery")
            bk = [p0 + back * 0.76, p1 + back * 0.76, p1 + back, p0 + back]
            hull(fu, [q + V((0, 0, 1.85)) for q in bk] +
                 [bk[0] + V((-s * 0.25, 0, 3.6)), bk[1] + V((-s * 0.25, 0, 3.6)), bk[2] + V((-s * 0.05, 0, 3.6)),
                  bk[3] + V((-s * 0.05, 0, 3.6))], "upholstery")
    for (x, y) in ((3.6, -12.0), (-3.6, 10.0), (3.6, 30.0), (-3.6, -34.0)):
        place(fu, p_side_table(1.9, 0.75), (x, y, FLOOR_Z))
    A.att("CoveLights", (0, 0, 1.3), (0, 0, 1), (0, 1, 0),
          note="SurfaceLights on the Cove parts (floor-level amber, Brightness 0.6): keep the glass dark so the "
               "night view reads")
    A.att("Beat_Window", (4.0, 10.0, FLOOR_Z), (1, 0, 0), (0, 0, 1),
          note="proximity beat: stand at the observation window as District 12 passes")
    for s in (-1, 1):
        A.collider((s * (HWID - 0.75), yb, FLOOR_Z), (s * HWID, yf, 9.9))
    return A


def build_car7_guard():
    lay = car_layout("nose")
    A = kit_asset("Train_Car7_Guard", "nose",
                  "Car 7 (spec section 9): grey steel, no decoration: steel plate floor, flat steel vault on ribs, cool "
                  "strip lights, folded jump seats nobody uses, grab rails, slate-steel lockers. Four guards "
                  "(Station_Guard) stand at the GuardPost attachments the whole trip. The nose car turned round "
                  "as the tail.", tags=["Car7"])
    mb = A.part("Room")
    fu = A.part("Furniture")
    rng = random.Random(SEED + 107)
    yb, yf = -(NOSE_CAR_L / 2 - 0.6), 27.5
    lining(A, mb, lay, yb, yf, STYLE_GUARD, rng, cove=False)
    n_pl = int(math.ceil((yf - yb) / 4.5))
    for k in range(n_pl):
        floor_planks(mb, yb + (yf - yb) * k / n_pl, yb + (yf - yb) * (k + 1) / n_pl, key="steel_plate", w=2.1)
    face_toward(mb, section_poly(yf), "steel_grey", V((0, -1, 0)))
    kit_ends(A, lay, ("rear",), style_key="steel_grey", door_frame="steel_dark")
    lt = A.part("StripLights", kind="neon", shadow=False)
    for y in range(-38, 26, 8):
        face_toward(lt, [V((-0.35, y, VAULT_Z - 0.12)), V((0.35, y, VAULT_Z - 0.12)), V((0.35, y + 5.0, VAULT_Z - 0.12)),
                         V((-0.35, y + 5.0, VAULT_Z - 0.12))], "striplight", V((0, 0, -1)))
    for s in (-1, 1):
        for c in (-28.5, -12.5, 3.5):
            place(fu, p_jump_seat(), (s * LIN_X, c, FLOOR_Z), 180 if s > 0 else 0)
        for c in (-20.5, 11.5):
            place(fu, p_locker(), (s * (LIN_X - 1.6), c, FLOOR_Z), 0 if s > 0 else 180)
        cyl(mb, (s * (LIN_X - 0.3), yb + 1.0, 7.0), (s * (LIN_X - 0.3), yf - 1.0, 7.0), 0.1, 0.1, 6, "steel")
    for i, (x, y) in enumerate(((-2.2, -6.0), (2.2, -6.0), (-2.2, 8.0), (2.2, 8.0))):
        A.att("GuardPost_%d" % (i + 1), (x, y, FLOOR_Z), (0, 1 if i < 2 else -1, 0), (0, 0, 1),
              note="a Station_Guard stands here the whole trip; they don't sit")
    A.att("StripLights", (0, 0, VAULT_Z - 0.2), (0, 0, -1), (0, 1, 0),
          note="SurfaceLights on StripLights, Face Bottom, cool white (226, 232, 236), Brightness 1, Range 12")
    A.collider((-LIN_X, yf, FLOOR_Z), (LIN_X, yf + 0.4, 9.9))
    return A


# ------------------------------------------------------------------------------------------------ moving pieces
def build_chandelier():
    A = Asset("Train_Chandelier", "TrainProp", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Light", "Moving"], pivot="the hang point (ceiling rose)",
              notes="Brass chandelier on a gimbal for the dining car: a rose, a stem and a gimbal ring, eight curved "
                    "arms with warm bulbs and faceted crystal drops. Swings on its own inertia (spec: never quite "
                    "stops). Origin = hang point; it hangs 2.4 down.")
    b = A.part("Brass")
    g = A.part("Crystal", kind="glass", shadow=False)
    lt = A.part("Bulbs", kind="neon", shadow=False)
    lathe(b, [(0.0, -0.25), (0.55, -0.2), (0.6, -0.05), (0.0, 0.0)], 8, "brass")
    cyl(b, (0, 0, -0.2), (0, 0, -0.9), 0.07, 0.07, 6, "brass")
    torus(b, (0, 0, -1.0), (1, 0, 0), 0.22, 0.04, 10, 3, "brass")
    lathe(b, [(0.0, -2.4), (0.18, -2.3), (0.3, -2.0), (0.22, -1.6), (0.1, -1.3), (0.08, -1.1), (0.0, -1.05)], 8, "brass")
    for k in range(8):
        a = TAU * k / 8
        d = V((math.cos(a), math.sin(a), 0))
        path = [V((0, 0, -1.85)) + d * 0.2, V((0, 0, -2.0)) + d * 0.6, V((0, 0, -1.95)) + d * 0.95,
                V((0, 0, -1.7)) + d * 1.15]
        sweep(b, path, lambda k_: [(0.04 * math.cos(TAU * i / 4 + 0.78), 0.04 * math.sin(TAU * i / 4 + 0.78))
                                   for i in range(4)], "brass")
        tip = path[-1]
        lathe(b, [(0.06, -0.12), (0.12, 0.0), (0.12, 0.05)], 6, "brass", c=tip)
        lathe(lt, [(0.0, 0.05), (0.07, 0.1), (0.05, 0.28), (0.0, 0.32)], 6, "bulb", c=tip)
        dp = V((0, 0, -2.15)) + d * 0.75
        hull(g, [dp + V((0.08, 0, 0)), dp - V((0.08, 0, 0)), dp + V((0, 0.08, 0)), dp - V((0, 0.08, 0)),
                 dp + V((0, 0, 0.12)), dp - V((0, 0, 0.3))], "crystal")
    torus(b, (0, 0, -1.95), (0, 0, 1), 0.7, 0.035, 12, 3, "brass")
    A.att("Light", (0, 0, -1.8), (0, 0, -1), (0, 1, 0), note="PointLight Range 14, Brightness 1.5, (255, 214, 160)")
    return A


def build_pendant():
    A = Asset("Train_PendantLamp", "TrainProp", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Light", "Moving"], pivot="the hang point",
              notes="Brass pendant lamp for the lounge (a bell shade on a rod); swings with the sway.")
    b = A.part("Brass")
    lt = A.part("Bulb", kind="neon", shadow=False)
    lathe(b, [(0.0, -0.2), (0.35, -0.15), (0.35, 0.0), (0.0, 0.0)], 8, "brass")
    cyl(b, (0, 0, -0.15), (0, 0, -1.3), 0.05, 0.05, 6, "brass")
    lathe(b, [(0.75, -2.05), (0.7, -1.85), (0.45, -1.5), (0.18, -1.3), (0.0, -1.28)], 10, "brass")
    lathe(b, [(0.0, -1.33), (0.15, -1.36), (0.42, -1.55), (0.66, -1.86), (0.71, -2.03)], 10, "wall_cream")
    lathe(lt, [(0.0, -1.95), (0.16, -1.85), (0.12, -1.6), (0.0, -1.55)], 6, "bulb")
    A.att("Light", (0, 0, -1.8), (0, 0, -1), (0, 1, 0), note="PointLight Range 10, Brightness 1, warm")
    return A


def build_compartment_door():
    A = Asset("Train_CompartmentDoor", "TrainDoor", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Door", "Moving"], pivot="bottom centre, corridor face at +X",
              notes="Sliding compartment door 4 x 7.5: mahogany with a brass number plate (blank) and handle, a "
                    "louvred vent. Slides 4.2 along +Y.")
    d = A.part("Leaf")
    cbox(d, (-0.15, -DOOR_W / 2, 0.0), (0.0, DOOR_W / 2, DOOR_H), "wood_dark", ch=0.03)
    for (za, zb) in ((0.6, 3.0), (3.6, 6.9)):
        cbox(d, (0.0, -1.5, za), (0.06, 1.5, zb), "wood", ch=0.03)
    for k in range(5):
        z = 1.0 + 0.35 * k
        cbox(d, (0.06, -1.1, z), (0.1, 1.1, z + 0.18), "wood_dark", ch=0.0)
    cbox(d, (0.06, -0.5, 6.0), (0.11, 0.5, 6.45), "brass", ch=0.0)
    cbox(d, (0.06, 1.55, 3.3), (0.16, 1.7, 4.1), "brass", ch=0.0)
    return A


def build_vestibule_door():
    A = Asset("Train_VestibuleDoor", "TrainDoor", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Door", "Moving"], pivot="bottom centre",
              notes="Car 1's pneumatic door: brass frame and glass, 4 x 7.5; slides 4.3 along +X and seals with a "
                    "thump.")
    d = A.part("Frame")
    g = A.part("Glass", kind="glass", shadow=False)
    for (lo, hi) in (((-2.0, -0.12, 0.0), (-1.72, 0.12, 7.5)), ((1.72, -0.12, 0.0), (2.0, 0.12, 7.5)),
                     ((-2.0, -0.12, 0.0), (2.0, 0.12, 0.6)), ((-2.0, -0.12, 7.22), (2.0, 0.12, 7.5)),
                     ((-2.0, -0.12, 3.4), (2.0, 0.12, 3.6))):
        cbox(d, lo, hi, "brass", ch=0.04)
    box(g, (-1.72, -0.03, 0.6), (1.72, 0.03, 7.22), "glass", skip=("-x", "+x", "-z", "+z"))
    return A


def build_gangway_door():
    A = Asset("Train_GangwayDoor", "TrainDoor", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Door", "Moving"], pivot="bottom centre",
              notes="End door between cars, 4 x 7.5: mahogany with a round-cornered brass window and a brass kick "
                    "plate; slides 4.2 along +X into the end wall.")
    d = A.part("Leaf")
    g = A.part("Glass", kind="glass", shadow=False)
    tmp, tmpg = MB(), MB()
    t = 0.16
    ys = [-DOOR_W / 2, -0.9, 0.9, DOOR_W / 2]
    zs = [0.0, 0.6, 3.9, 6.6, DOOR_H]
    hole = [(-0.9, 0.9, 3.9, 6.6)]

    def kk(z0, z1):
        return "brass" if z1 <= 0.61 else "wood_dark"
    grid_wall(tmp, t / 2, -1, ys, zs, hole, kk, inward=True)
    grid_wall(tmp, -t / 2, 1, ys, zs, hole, kk, inward=True)
    box(tmp, (-t / 2, -DOOR_W / 2, 0.0), (t / 2, DOOR_W / 2, DOOR_H), "wood_dark", skip=("+x", "-x"))
    window_frame(tmp, tmpg, 1, -0.9, 0.9, 3.9, 6.6, x_out=t / 2 - 0.05, x_in=-t / 2, r=0.5, inset=0.12)
    R = Matrix.Rotation(math.radians(90), 4, "Z")
    d.extend(tmp, R)
    g.extend(tmpg, R)
    return A


def build_globe_lid():
    A = Asset("Train_GlobeLid", "TrainProp", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Prop", "Moving"], pivot="globe centre (hinge on the -Y edge)",
              notes="Upper half of the globe drinks cabinet (muted sea and land facets: an abstract globe, not a "
                    "real map); hinges open for the pour beat.")
    b = A.part("Shell")
    prof = [(1.1 * math.sin(math.radians(a)), 1.1 * math.cos(math.radians(a))) for a in (90, 72, 55, 35, 15)] + \
           [(0.0, 1.1)]
    lathe(b, prof, 12, "globe_sea", keys=lambda k, i: "globe_land" if (i * 5 + k * 2) % 4 == 0 else "globe_sea",
          cap0=False)
    b.face(list(reversed([V((1.1 * math.cos(TAU * i / 12), 1.1 * math.sin(TAU * i / 12), 0.0)) for i in range(12)])),
           "wood")
    return A


def build_bud_vase():
    A = Asset("Train_BudVase", "TrainProp", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Prop", "Loose"], pivot="base centre",
              notes="A slim brass bud vase with a single wilting rose (car 1); a loose object that slides with the "
                    "sway.")
    b = A.part("Vase")
    lathe(b, [(0.0, 0.0), (0.2, 0.0), (0.22, 0.12), (0.12, 0.5), (0.07, 0.95), (0.1, 1.05), (0.0, 1.05)], 8, "brass")
    path = [V((0, 0, 1.0)), V((0.02, 0.0, 1.6)), V((0.12, 0.0, 2.0)), V((0.35, 0.0, 2.15)), V((0.55, 0.0, 2.0))]
    sweep(b, path, lambda k: [(0.035 * math.cos(TAU * i / 4), 0.035 * math.sin(TAU * i / 4)) for i in range(4)], "stem")
    hp = path[-1]
    hull(b, [hp + V((0.1, 0.1, 0.05)), hp + V((0.1, -0.1, 0.05)), hp + V((-0.08, 0.12, 0.0)),
             hp + V((-0.08, -0.12, 0.0)), hp + V((0.05, 0.0, -0.25)), hp + V((0.18, 0.0, -0.1)),
             hp + V((-0.05, 0.0, 0.12))], "flower")
    hull(b, [V((0.06, 0.0, 1.55)), V((0.3, 0.12, 1.45)), V((0.28, -0.05, 1.42)), V((0.08, 0.02, 1.5))], "stem")
    return A


def build_crystal():
    A = Asset("Train_Crystal", "TrainProp", "Train_Interiors.glb", tset="Train_Props",
              tags=["Train", "Prop", "Loose"], pivot="base centre",
              notes="A crystal goblet for the dining table (rings when the train sways; slides).")
    g = A.part("Glass", kind="glass", shadow=False)
    lathe(g, [(0.0, 0.0), (0.2, 0.0), (0.2, 0.03), (0.04, 0.06), (0.035, 0.35), (0.16, 0.42), (0.19, 0.62),
              (0.17, 0.78), (0.0, 0.5)], 8, "crystal")
    return A


def build_bridge_backdrop():
    A = Asset("Train_BridgeBackdrop", "Backdrop", "Train_Interiors.glb", tset="Train_Bridge", tex_size=512,
              tags=["Train", "Backdrop", "Night"],
              notes="Low-detail night backdrop for the observation car (Trailer 2's journey, in our own build): a "
                    "twin-pylon cable-stayed bridge over a dark reservoir between hill ridges, with warm deck lights. "
                    "Origin = deck centre at water level; the deck runs along Y at z 30.")
    b = A.part("Bridge")
    h = A.part("Hills")
    lt = A.part("DeckLights", kind="neon", shadow=False)
    deck_z = 30.0
    cbox(b, (-8.0, -420.0, deck_z - 3.0), (8.0, 420.0, deck_z), "bridge", ch=0.4)
    for y in (-150.0, 150.0):
        for s in (-1, 1):
            cbox(b, (s * 10.0 - 2.0, y - 2.5, -10.0), (s * 10.0 + 2.0, y + 2.5, deck_z + 70.0), "bridge", ch=0.4)
        cbox(b, (-12.0, y - 2.0, deck_z + 40.0), (12.0, y + 2.0, deck_z + 44.0), "bridge", ch=0.3)
        cbox(b, (-12.0, y - 2.0, deck_z - 6.0), (12.0, y + 2.0, deck_z - 2.0), "bridge", ch=0.3)
        for s in (-1, 1):
            for k in range(1, 9):
                for d in (-1, 1):
                    top = V((s * 10.0, y, deck_z + 68.0 - 3.0 * k))
                    bot = V((s * 8.0, y + d * 16.0 * k, deck_z))
                    cyl(b, top, bot, 0.35, 0.35, 4, "steel")
    for y in range(-400, 401, 20):
        for s in (-1, 1):
            disc(lt, (s * 7.6, y, deck_z + 0.6), 0.6, 6, (0, 0, 1), "deck_light")
    rng = random.Random(SEED + 300)
    for side in (-1, 1):
        for k in range(7):
            cx = side * rng.uniform(260.0, 520.0)
            cy = -600.0 + 200.0 * k + rng.uniform(-60, 60)
            hgt = rng.uniform(90.0, 220.0)
            pts = [(cx + rng.uniform(-180, 180), cy + rng.uniform(-160, 160), -5.0) for _ in range(9)]
            pts += [(cx + rng.uniform(-60, 60), cy + rng.uniform(-60, 60), hgt * rng.uniform(0.6, 1.0)) for _ in range(4)]
            hull(h, pts, "hill")
    h.face(rect_loop(-700.0, -800.0, 700.0, 800.0, -0.5), "water_dark")
    return A


# ================================================================================================ baking
BAKE = {   # by asset kind: AO radii (studs), exponents, strength (AO term floor = 1 - strength), bevel normal radius
    "StationArch": dict(near=0.9, far=5.0, pn=1.0, pf=0.8, strength=0.42, bevel=0.07),
    "Sculpture": dict(near=0.5, far=3.0, pn=1.0, pf=0.8, strength=0.38, bevel=0.06),
    "Prop": dict(near=0.15, far=0.8, pn=1.0, pf=0.8, strength=0.38, bevel=0.03),
    "Character": dict(near=0.05, far=0.35, pn=1.0, pf=0.8, strength=0.36, bevel=0.015),
    "TrainCar": dict(near=0.3, far=1.6, pn=1.0, pf=0.8, strength=0.36, bevel=0.04),
    "TrainDoor": dict(near=0.08, far=0.5, pn=1.0, pf=0.8, strength=0.36, bevel=0.02),
    "TrainInterior": dict(near=0.35, far=2.2, pn=1.0, pf=0.8, strength=0.42, bevel=0.035),
    "TrainProp": dict(near=0.06, far=0.4, pn=1.0, pf=0.8, strength=0.36, bevel=0.015),
    "Backdrop": dict(near=1.5, far=10.0, pn=1.0, pf=0.8, strength=0.3, bevel=0.1),
}
AO_TINT = np.array([1.03, 1.0, 0.97])     # shadows a touch cooler (ArtStyle rule 4)
POS_SCALE = 0.0005                         # position pass encoding: p * scale + 0.5
GLB_GROUPS = [
    ("Train_Station.glb", ["Station_Coffer", "Station_EntranceCeiling", "Station_Lantern", "Station_Sunburst",
                           "Station_EntranceWalls", "Station_EntranceFloor", "Station_Portal", "Station_ShedBay",
                           "Station_FloorBay", "Station_ShedEnd"]),
    ("Train_StationProps.glb", ["Station_Banner", "Station_Board", "Station_Poster", "Station_Guard"]),
    ("Train_Exterior.glb", ["Train_NoseCar", "Train_BodyCar", "Train_ObservationCar", "Train_DoorLeaf"]),
    ("Train_InteriorsA.glb", ["Train_Car1_Vestibule", "Train_Car2_Dining", "Train_Car3_Lounge"]),
    ("Train_InteriorsB.glb", ["Train_Car4_Corridor", "Train_Car5_Compartment", "Train_Car6_Observation"]),
    ("Train_InteriorsC.glb", ["Train_Car7_Guard", "Train_Chandelier", "Train_PendantLamp", "Train_CompartmentDoor",
                              "Train_VestibuleDoor", "Train_GangwayDoor", "Train_GlobeLid", "Train_BudVase",
                              "Train_Crystal", "Train_BridgeBackdrop"]),
]
ROBLOX_MAT = {   # paint key -> Roblox material (physics and sound; the look comes from the SurfaceAppearance)
    "concrete": "Concrete", "coffer": "Concrete", "concrete_dark": "Concrete", "guideway": "Concrete",
    "floor": "Marble", "floor_light": "Marble", "edge_strip": "Concrete", "white_steel": "Metal", "bronze": "Metal",
    "gold": "Metal", "brass": "Metal", "steel": "Metal", "steel_dark": "Metal", "banner": "Fabric",
    "board": "Metal", "armour": "SmoothPlastic", "lacquer": "Metal", "maroon": "Metal", "upholstery": "Fabric",
    "leather": "Leather", "velvet": "Fabric", "wood": "Wood", "wood_dark": "Wood", "hammered": "Metal",
    "wall_cream": "Fabric", "carpet": "Fabric", "parquet": "WoodPlanks", "marble": "Marble", "linen": "Fabric",
    "porcelain": "SmoothPlastic", "steel_grey": "Metal", "steel_plate": "DiamondPlate", "slate_steel": "Metal",
    "bridge": "Concrete", "hill": "Grass", "mirror": "Glass", "piano": "SmoothPlastic", "globe_sea": "Wood",
    "poster_maroon": "Cardboard", "bellows": "Rubber",
}


def uv_unwrap(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(50.0), island_margin=0.002, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    # CONCAVE + an additive margin: the best fill here, and fast (CONVEX + FRACTION took up to 47 s on a 107-triangle
    # poster in Blender 5.3)
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="CARDINAL", scale=True, margin_method="ADD", margin=0.003,
                            shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_material(name, p):
    m = new_material(name)
    nt = m.node_tree
    N = nt.nodes
    for n in list(N):
        N.remove(n)
    h = dict(nt=nt)
    h["out"] = N.new("ShaderNodeOutputMaterial")
    h["em"] = N.new("ShaderNodeEmission")
    h["em"].inputs["Strength"].default_value = 1.0
    for nm, attr in (("ac", "bk_col"), ("ar", "bk_rmp"), ("ak", "bk_kid")):
        a = N.new("ShaderNodeAttribute")
        a.attribute_name = attr
        h[nm] = a
    geo = N.new("ShaderNodeNewGeometry")
    for nm, sock in (("pos", "Position"), ("gnrm", "True Normal")):
        vm = N.new("ShaderNodeVectorMath")
        vm.operation = "MULTIPLY_ADD"
        sc = POS_SCALE if nm == "pos" else 0.5
        vm.inputs[1].default_value = (sc, sc, sc)
        vm.inputs[2].default_value = (0.5, 0.5, 0.5)
        nt.links.new(geo.outputs[sock], vm.inputs[0])
        h[nm] = vm
    for nm, dist in (("aon", p["near"]), ("aof", p["far"])):
        ao = N.new("ShaderNodeAmbientOcclusion")
        ao.samples = 16
        ao.inputs["Distance"].default_value = dist
        h[nm] = ao
    bev = N.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = p["bevel"]
    h["bsdf"] = N.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bev.outputs["Normal"], h["bsdf"].inputs["Normal"])
    h["img"] = N.new("ShaderNodeTexImage")
    N.active = h["img"]
    return m, h


def set_bake_pass(h, which):
    nt, em, out = h["nt"], h["em"], h["out"]
    for l_ in list(em.inputs["Color"].links):
        nt.links.remove(l_)
    if which == "normal":
        link_only(nt, h["bsdf"].outputs["BSDF"], out.inputs["Surface"])
        return
    link_only(nt, em.outputs["Emission"], out.inputs["Surface"])
    src = {"color": h["ac"].outputs["Color"], "rmp": h["ar"].outputs["Color"], "kid": h["ak"].outputs["Color"],
           "pos": h["pos"].outputs["Vector"], "gnrm": h["gnrm"].outputs["Vector"], "aon": h["aon"].outputs["AO"],
           "aof": h["aof"].outputs["AO"]}.get(which)
    if src is None:
        em.inputs["Color"].default_value = (1, 1, 1, 1)
    else:
        nt.links.new(src, em.inputs["Color"])


def blur_masked(a, m, sigma):
    w = m.astype(np.float64)
    num = tg.pblur(a * w, sigma)
    den = tg.pblur(w, sigma)
    out = np.where(den > 1e-4, num / np.maximum(den, 1e-4), a)
    return np.where(m, out, a)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def pattern_mask(pid, u, v):
    """Motif coverage (0..1) and colour index (0 = first motif colour, 1 = second) for pattern pid at (u, v) studs."""
    if pid == 1:          # upholstery: cream C-arcs (opening alternates by row) and dots on the cell corners
        cell = 1.4
        cu, cv = u / cell, v / cell
        row = np.floor(cv)
        cu = cu + 0.5 * np.mod(row, 2)          # brick offset: the rows interlock like a woven chain
        fu, fv = cu - np.floor(cu) - 0.5, cv - row - 0.5
        r = np.hypot(fu, fv)
        ring = sstep(0.18, 0.2, r) * (1.0 - sstep(0.345, 0.365, r))
        th = np.arctan2(fv, fu)
        opening = np.where(np.mod(row, 2) == 0, 0.0, math.pi)
        dth = np.abs(np.angle(np.exp(1j * (th - opening))))
        ring *= sstep(0.75, 0.9, dth)
        du, dv = 0.5 - np.abs(fu), 0.5 - np.abs(fv)
        dot = 1.0 - sstep(0.1, 0.12, np.hypot(du, dv))
        return np.clip(ring + dot, 0, 1) * 0.72, np.zeros_like(u, dtype=int)   # woven, not printed: 72 % cover
    if pid == 2:          # carpet: gold diagonal lattice, cream lozenges at the crossings
        cell = 2.0
        a, b = (u + v) / cell, (u - v) / cell
        da, db = np.abs(a - np.round(a)), np.abs(b - np.round(b))
        line = np.clip((1.0 - sstep(0.045, 0.065, da)) + (1.0 - sstep(0.045, 0.065, db)), 0, 1)
        loz = (1.0 - sstep(0.13, 0.15, da + db))
        m = np.clip(line + loz, 0, 1)
        return m, np.where(loz > 0.5, 1, 0)
    if pid == 3:          # runner: gold diamond chain and edge lines
        fu = u / 0.6 - np.floor(u / 0.6) - 0.5
        fv = v / 1.2 - np.floor(v / 1.2) - 0.5
        dia = 1.0 - sstep(0.3, 0.33, np.abs(fu) + np.abs(fv) * 0.5)
        edge = sstep(0.4, 0.43, np.abs(fu))
        return np.clip(dia + edge, 0, 1), np.zeros_like(u, dtype=int)
    return np.zeros_like(u), np.zeros_like(u, dtype=int)


PATTERN_COLS = {1: [(206, 180, 142)], 2: [(168, 132, 80), (200, 182, 150)], 3: [(176, 138, 80)]}


def apply_patterns(col, rmp, pos, gn, cov, kid):
    pat = np.rint(rmp[..., 2] * 8.0).astype(int)
    for pid in (1, 2, 3):
        m = cov & (pat == pid)
        if not m.any():
            continue
        P, Nn = pos[m], gn[m]
        ax = np.argmax(np.abs(Nn), axis=1)
        u = np.where(ax == 0, P[:, 1], P[:, 0])
        v = np.where(ax == 2, P[:, 1], P[:, 2])
        mask, ci = pattern_mask(pid, u, v)
        base_key = {1: "upholstery", 2: "carpet", 3: "runner"}[pid]
        base_lin = np.asarray(s2l(MK[base_key]["rgb"]))
        c = col[m]
        ratio = (c.mean(axis=1) / max(1e-6, float(base_lin.mean())))[:, None]
        mot = np.stack([np.asarray(s2l(PATTERN_COLS[pid][min(i, len(PATTERN_COLS[pid]) - 1)])) for i in (0, 1)])
        mc = mot[ci] * np.clip(ratio, 0.85, 1.15)
        col[m] = c * (1.0 - mask[:, None]) + mc * mask[:, None]
    return col


def bake_set(tset, members):
    """UV-unwrap the set's textured parts together; bake painted colour (+ patterns) x two-radius AO, roughness,
    metalness and a bevel normal into one texture set. Returns file names and stats."""
    scene = bpy.context.scene
    objs = [o for a in members for r, o in a.objs if o["kind"] == "tex" and o.get("tset") == tset]
    size = max(int(o.get("tsize", 1024)) for o in objs)
    p = BAKE.get(members[0].kind, BAKE["Prop"])
    occluders = [o for a in members for r, o in a.objs if o["kind"] == "tex"]
    homes = []
    x = 0.0
    for a in members:
        homes.append((a.root, a.root.location.copy()))
        bpy.context.view_layer.update()
        lo = min(min((o.matrix_world @ V(c)).x for c in o.bound_box) for _, o in a.objs)
        hi = max(max((o.matrix_world @ V(c)).x for c in o.bound_box) for _, o in a.objs)
        a.root.location = (a.root.location.x + x - lo, 0.0, 0.0)
        x += (hi - lo) + 30.0
    bpy.context.view_layer.update()
    for o in scene.objects:
        if o.type == "MESH":
            o.hide_render = o not in occluders
    t0 = time.time()
    uv_unwrap(objs)
    area = sum(sum(pg.area for pg in o.data.polygons) for o in objs)
    uv_area = 0.0
    for o in objs:
        uvl = o.data.uv_layers.active.data
        for pg in o.data.polygons:
            pts = [uvl[li].uv for li in pg.loop_indices]
            uv_area += 0.5 * abs(sum(pts[i].x * pts[(i + 1) % len(pts)].y - pts[(i + 1) % len(pts)].x * pts[i].y
                                     for i in range(len(pts))))
    pxs = size * math.sqrt(uv_area / max(area, 1e-6))
    log("  %s: %d parts, %.0f sq studs, UV fill %.2f, %.1f px/stud at %d (unwrap %.0fs)" % (
        tset, len(objs), area, uv_area, pxs, size, time.time() - t0))
    mat, h = bake_material("BK_" + tset, p)
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    maps = {}
    for which, spp in (("cover", 1), ("color", 1), ("rmp", 1), ("kid", 1), ("pos", 1), ("gnrm", 1), ("aon", 32),
                       ("aof", 48), ("normal", 8)):
        img = bpy.data.images.new("bk_%s_%s" % (tset, which), size, size, alpha=True, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        h["img"].image = img
        h["nt"].nodes.active = h["img"]
        set_bake_pass(h, which)
        scene.cycles.samples = spp
        if which == "normal":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y",
                                normal_b="POS_Z", margin=0, use_clear=True, target="IMAGE_TEXTURES")
        else:
            bpy.ops.object.bake(type="EMIT", margin=0, use_clear=True, target="IMAGE_TEXTURES")
        maps[which] = tg.image_to_np(img).astype(np.float64)
        bpy.data.images.remove(img)
    for root, loc in homes:
        root.location = loc
    for o in scene.objects:
        o.hide_render = False
    bpy.context.view_layer.update()
    cov = maps["cover"][..., 0] > 0.5
    col = maps["color"][..., :3].copy()
    rmp = maps["rmp"][..., :3]
    kid = np.rint(maps["kid"][..., 0] * 256.0 - 0.5).astype(int)
    pos = (maps["pos"][..., :3] - 0.5) / POS_SCALE
    gn = maps["gnrm"][..., :3] * 2.0 - 1.0
    col = apply_patterns(col, rmp, pos, gn, cov, kid)
    aon = blur_masked(np.clip(maps["aon"][..., 0], 0, 1), cov, 1.0)
    aof = blur_masked(np.clip(maps["aof"][..., 0], 0, 1), cov, 1.6)
    ao = np.clip(aon, 0, 1) ** p["pn"] * np.clip(aof, 0, 1) ** p["pf"]
    term = 1.0 - p["strength"] * (1.0 - ao)[..., None] * AO_TINT[None, None, :]
    term = np.clip(term, 0.5, 1.0)                       # rule 5: never below half the painted value
    out = col * term
    rough = np.clip(rmp[..., 0] + 0.05 * (1.0 - aon), 0.04, 0.98)
    metal = np.clip(rmp[..., 1], 0.0, 1.0)
    nrm = maps["normal"][..., :3]
    w = cov.astype(np.float64)
    out = tg.pushpull(out, w)
    rough = tg.pushpull(rough[..., None], w)[..., 0]
    metal = tg.pushpull(metal[..., None], w)[..., 0]
    nrm = tg.encode_normal(tg.pushpull(nrm, w) * 2.0 - 1.0)
    base = set_name(tset)
    files = {"color": base + "_Color.png", "normal": base + "_Normal.png", "rough": base + "_Rough.png",
             "mr": base + "_MR.png"}
    has_metal = float(metal[cov].max()) > 0.05 if cov.any() else False
    if has_metal:
        files["metal"] = base + "_Metal.png"
    os.makedirs(GLB_ONLY, exist_ok=True)
    tg.write_png(os.path.join(TEX, files["color"]), tg.lin_to_srgb(out))
    tg.write_png(os.path.join(TEX, files["normal"]), nrm, quantize=False)
    tg.write_png(os.path.join(TEX, files["rough"]), rough)
    if has_metal:
        tg.write_png(os.path.join(TEX, files["metal"]), metal, quantize=False)
    r2, m2 = rough, metal
    while r2.shape[0] > 512:
        r2 = 0.25 * (r2[0::2, 0::2] + r2[1::2, 0::2] + r2[0::2, 1::2] + r2[1::2, 1::2])
        m2 = 0.25 * (m2[0::2, 0::2] + m2[1::2, 0::2] + m2[0::2, 1::2] + m2[1::2, 1::2])
    tg.write_png(os.path.join(GLB_ONLY, files["mr"]), np.stack([np.zeros_like(r2), r2, m2], axis=2), quantize=False)
    # per paint key: mean ColorMap after AO (the tone check, ArtStyle rule 6 "mean sRGB per surface after AO")
    keys = {}
    if cov.any():
        srgb = tg.lin_to_srgb(out)
        for k in np.unique(kid[cov]):
            if 0 <= k < len(KEYS) and KEYS[k] in MK:
                sel = cov & (kid == k)
                c = srgb[sel].mean(axis=0) * 255.0
                keys[KEYS[k]] = dict(texels=int(sel.sum()), meanSRGB=[int(round(v)) for v in c],
                                     luma=round(luma(c), 1), target=list(MK[KEYS[k]]["rgb"]))
    srgb_mean = [int(round(v)) for v in tg.lin_to_srgb(out[cov].mean(0)) * 255] if cov.any() else [0, 0, 0]
    stats = dict(size=size, coverage=round(float(cov.mean()), 3), pxPerStud=round(pxs, 1), meanColorSRGB=srgb_mean,
                 aoTermMin=round(float(term[cov].min()), 3) if cov.any() else 1.0, metalness=has_metal, keys=keys)
    log("  baked %s: coverage %.1f%%, mean sRGB %s, AO term min %.2f, metal %s (%.0fs)" % (
        tset, 100 * stats["coverage"], srgb_mean, stats["aoTermMin"], has_metal, time.time() - t0))
    return files, stats


def set_name(tset):
    """Texture-set (and material) name: the category prefix once (Train_Station_Coffer, Train_NoseCar)."""
    return tset if tset.startswith(CATEGORY + "_") else "%s_%s" % (CATEGORY, tset)


def export_material(tset, files):
    m = new_material(set_name(tset))
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def img(path, cs):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    tc = img(os.path.join(TEX, files["color"]), "sRGB")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = img(os.path.join(TEX, files["normal"]), "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tr = img(os.path.join(GLB_ONLY, files["mr"]), "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    m.use_backface_culling = True
    return m


def export_flat_material(key):
    nm = "%s_%s_%s" % (CATEGORY, "Neon" if key in EMIT else "Glass", key)
    if nm in bpy.data.materials:
        return bpy.data.materials[nm]
    m = new_material(nm)
    b = m.node_tree.nodes.get("Principled BSDF")
    if key in EMIT:
        rgb = EMIT[key][0]
        b.inputs["Base Color"].default_value = (*s2l(rgb), 1.0)
        b.inputs["Emission Color"].default_value = (*s2l(rgb), 1.0)
        b.inputs["Emission Strength"].default_value = 1.0
        b.inputs["Roughness"].default_value = 0.5
    else:
        rgb, tr = GLASS[key]
        b.inputs["Base Color"].default_value = (*s2l(rgb), 1.0)
        b.inputs["Alpha"].default_value = 1.0 - tr
        b.inputs["Roughness"].default_value = 0.05
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.use_backface_culling = True
    return m


# ================================================================================================ GLB checks
def _glb_split(data):
    magic, ver, length = struct.unpack("<III", data[:12])
    clen, ctype = struct.unpack("<II", data[12:20])
    return ver, json.loads(data[20:20 + clen].decode("utf-8")), data[20 + clen:]


def glb_patch_and_check(path, metal_sets):
    """metallicFactor 1 on textured sets that carry metal (0 elsewhere), then: POSITION/NORMAL/TANGENT/TEXCOORD_0
    on textured primitives, no vertex colours, no doubleSided material, textures present, size."""
    with open(path, "rb") as f:
        data = f.read()
    ver, js, rest = _glb_split(data)
    for m in js.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        nm = m.get("name", "")
        pbr["metallicFactor"] = 1 if any(nm == set_name(t) for t in metal_sets) else 0
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, ver, 12 + len(body)) + body)
    problems = []
    flat = {i for i, m in enumerate(js.get("materials", [])) if "_Neon_" in m.get("name", "") or
            "_Glass_" in m.get("name", "")}
    nprim = 0
    for me in js.get("meshes", []):
        for prim in me.get("primitives", []):
            nprim += 1
            need = ("POSITION", "NORMAL") if prim.get("material") in flat else ("POSITION", "NORMAL", "TANGENT",
                                                                                 "TEXCOORD_0")
            miss = [k for k in need if k not in prim.get("attributes", {})]
            if miss:
                problems.append("%s lacks %s" % (me.get("name"), ",".join(miss)))
            if "COLOR_0" in prim.get("attributes", {}):
                problems.append("%s carries vertex colours" % me.get("name"))
    for i, m in enumerate(js.get("materials", [])):
        if m.get("doubleSided"):
            problems.append("material %s is doubleSided" % m.get("name"))
        if i not in flat and ("normalTexture" not in m or "baseColorTexture" not in m.get("pbrMetallicRoughness", {})):
            problems.append("material %s lacks textures" % m.get("name"))
    size = os.path.getsize(path)
    if size >= 19_000_000:
        problems.append("%s is %.2f MB (limit 20)" % (os.path.basename(path), size / 1e6))
    return {"primitives": nprim, "meshes": len(js.get("meshes", [])), "bytes": size,
            "images": [i.get("name") for i in js.get("images", [])],
            "materials": [m.get("name") for m in js.get("materials", [])]}, problems


def png_info(path):
    with open(path, "rb") as f:
        head = f.read(33)
    w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
    return {"size": [w, h], "bitDepth": bd, "channels": {0: "gray", 2: "RGB", 4: "gray+alpha", 6: "RGBA"}.get(ct)}


def to_roblox(v):
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def to_blender(r):
    return V((r[0], -r[2], r[1]))


# ================================================================================================ BUILD
STYLE_NOTES = [
    "Style A, faceted realism (docs/design/ArtStyle.md): true scale (1 stud = 0.28 m, player 5.5, doors 4 x 7.5), "
    "real members as chamfered prisms, flat-shaded facets (1-2.5 studs on architecture and car bodies, 0.3-1 on "
    "props), nothing modelled under ~0.25 stud except trim.",
    "Painted, not textured: one flat value per facet (+-5% per volume, +-2.5% per facet, lighter and warmer on top, "
    "cooler underneath), two-radius AO multiplied in (never below half the painted value), a 0.015-0.1-stud bevel "
    "normal; our own patterns (upholstery arcs, carpet lattice, runner) baked at 1.2-2-stud cells.",
    "Semi-real tones from UpcomingFilm_Brief.md 4.6 (sampled from the film, softened, clamped into the light band); "
    "matte except real metal, glass, the polished platform stone (0.4) and the train's semi-gloss lacquer (0.3).",
    "Darkness inside comes from the light rigs listed in 'lighting', never from the paint; saturated colour only on "
    "signals (the red-orange nose lamp, amber board rows, the cool propaganda screen).",
    "No film lettering, emblems, posters, slogans, seals or crests anywhere: every sign, emblem, poster, board row "
    "and plate motif is our own; the boards carry abstract glyph blocks, not words.",
]

LIGHTING = {
    "station": "Lighting.Ambient (70, 56, 44), ColorShift_Top (200, 140, 90), a warm low sun through the west glazing; "
               "SurfaceLights facing in on every ShedBay/EntranceWalls/ShedEnd Glow part (Color (248, 232, 222), "
               "Brightness 1.5, Range 40); warm downlights in the coffers; the nose lamps' red PointLights.",
    "train": "Amber cove SurfaceLights on the Cove parts (255, 196, 128), the chandeliers' and pendants' PointLights "
             "(swing with them), the lounge screen's cool SurfaceLight (the only cool light), guard-car strip lights; "
             "the windows glow amber from outside at night (Roblox does this from the interior lights).",
    "night journey": "Moonlit blue outside (Ambient ~ (40, 48, 70)), amber windows inside; Train_BridgeBackdrop with "
                     "its DeckLights.",
}
MOTION = {
    "sway": "constant 1.5 degree roll and a 0.4-stud vertical float on a slow sine (period ~6 s), out of phase front "
            "to back (spec section 9); move each car model as a whole (shell + interior + pieces welded to its root).",
    "pieces": "Train_Chandelier / Train_PendantLamp swing on their hang points; Train_BudVase and Train_Crystal slide "
              "a little with the sway; Station_Banner sways in the station.",
    "doors": "Train_DoorLeaf: plug door (0.2 in, then 4.2 along); Train_VestibuleDoor 4.3 along +X (pneumatic "
             "thump); Train_CompartmentDoor 4.2 along +Y; Train_GangwayDoor 4.2 along +X.",
    "sound": "52 Hz hum, glass chime, cutlery shift, door thump, piano pedal squeak, boots on steel (spec).",
}


def part_entry(a, role, o, files_by_set, stats_by_set):
    kind = o["kind"]
    me = o.data
    kid = np.empty(len(me.polygons), np.int32)
    me.attributes["mk"].data.foreach_get("value", kid)
    area = np.empty(len(me.polygons), np.float32)
    me.polygons.foreach_get("area", area)
    w = {}
    for k, ar in zip(kid, area):
        w[KEYS[k]] = w.get(KEYS[k], 0.0) + float(ar)
    dom = max(w, key=w.get)
    tot = sum(w.values())
    if kind == "tex":
        lin = sum(np.asarray(s2l(MK[k]["rgb"])) * v for k, v in w.items() if k in MK) / max(tot, 1e-6)
        rgb = [int(round(v)) for v in tg.lin_to_srgb(lin) * 255]
        f = files_by_set[o["tset"]]
        sa = {"colorMap": REL_TEX + "/" + f["color"], "normalMap": REL_TEX + "/" + f["normal"],
              "roughnessMap": REL_TEX + "/" + f["rough"],
              "metalnessMap": (REL_TEX + "/" + f["metal"]) if "metal" in f else None, "alphaMode": "Overlay",
              "color": [255, 255, 255]}
        mat = ROBLOX_MAT.get(dom, "SmoothPlastic")
    elif kind == "neon":
        rgb, sa, mat = list(EMIT[dom][0]), None, "Neon"
    else:
        rgb, sa, mat = list(GLASS[dom][0]), None, "Glass"
    shadow = kind == "tex" and a.parts[role]["shadow"]
    return {"name": o.name, "role": role, "kind": kind, "robloxMaterial": mat, "rgb": rgb,
            "collide": False, "collision": "Box", "castShadow": bool(shadow), "canQuery": False, "canTouch": False,
            "tags": list(a.parts[role]["tags"]), "tris": tri_count(o),
            "textureSet": set_name(o["tset"]) if kind == "tex" else None,
            "surfaceAppearance": sa, "transparency": GLASS[dom][1] if kind == "glass" else 0,
            "neon": kind == "neon", "emitKey": dom if kind == "neon" else None,
            "doubleSided": False, "backFacesInMesh": kind == "glass", "renderFidelity": "Automatic",
            "keys": {k: round(v / max(tot, 1e-6), 3) for k, v in sorted(w.items(), key=lambda kv: -kv[1])[:6]}}


def planar_uv(o, scale=0.1):
    """Box-projected UVs for untextured (Neon / Glass) parts, so the GLB carries clean TEXCOORD_0 and tangents."""
    me = o.data
    uvl = me.uv_layers.new(name="UVMap")
    nP, nL = len(me.polygons), len(me.loops)
    nrm = np.empty(nP * 3, np.float32)
    me.polygons.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)
    lt = np.empty(nP, np.int32)
    me.polygons.foreach_get("loop_total", lt)
    lv = np.empty(nL, np.int32)
    me.loops.foreach_get("vertex_index", lv)
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)[lv]
    ax = np.repeat(np.argmax(np.abs(nrm), axis=1), lt)
    u = np.where(ax == 0, co[:, 1], co[:, 0]) * scale
    v = np.where(ax == 2, co[:, 1], co[:, 2]) * scale
    uvl.data.foreach_set("uv", np.stack([u, v], axis=1).ravel().astype(np.float32))


def layout_entries(layout):
    return [{"asset": n, "position": to_roblox(V(loc)), "yawDeg": round(float(yaw), 2)} for n, loc, yaw in layout]


def build_stage():
    reset()
    scene = bpy.context.scene
    tg.enable_gpu(scene)
    scene.cycles.use_denoising = False
    os.makedirs(TEX, exist_ok=True)
    for d in (TEX, GLB_ONLY):          # this run's textures replace the last run's (stale names never linger)
        if os.path.isdir(d):
            for fn in os.listdir(d):
                if fn.startswith(CATEGORY + "_") and fn.endswith(".png"):
                    os.remove(os.path.join(d, fn))
    assets = build_all_assets()
    coll = make_objects(assets)
    by = {a.name: a for a in assets}
    budget_report(assets)
    sets = {}
    for a in assets:
        for _, o in a.objs:
            if o["kind"] == "tex" and a not in sets.setdefault(o["tset"], []):
                sets[o["tset"]].append(a)
    files, stats = {}, {}
    for tset, members in sets.items():
        t = time.time()
        files[tset], stats[tset] = bake_set(tset, members)
        log("BAKE %s (%d assets) %.0fs" % (tset, len(members), time.time() - t))
    mats = {t: export_material(t, f) for t, f in files.items()}
    for a in assets:
        for role, o in a.objs:
            o.data.materials.clear()
            o.data.materials.append(mats[o["tset"]] if o["kind"] == "tex" else export_flat_material(o["key"]))
    # manifest entries (before the attributes are dropped)
    entries = {}
    for a in assets:
        parts = [part_entry(a, r, o, files, stats) for r, o in a.objs]
        lo = np.array([1e9] * 3)
        hi = np.array([-1e9] * 3)
        for _, o in a.objs:
            co = np.empty(len(o.data.vertices) * 3, np.float32)
            o.data.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            lo, hi = np.minimum(lo, co.min(0)), np.maximum(hi, co.max(0))
        ra, rb = to_roblox(lo), to_roblox(hi)
        att = {k: {"position": to_roblox(v["pos"]), "look": to_roblox(v["look"]), "up": to_roblox(v["up"]),
                   **({"note": v["extra"]["note"]} if "note" in v["extra"] else {})} for k, v in a.attach.items()}
        cols = []
        for clo, chi, tag in a.colliders:
            c = (clo + chi) * 0.5
            sz = chi - clo
            cols.append({"centre": to_roblox(c), "size": [round(sz.x, 3), round(sz.z, 3), round(sz.y, 3)],
                         "tag": tag})
        entries[a.name] = {
            "name": a.name, "kind": a.kind, "tags": a.tags, "notes": a.notes, "pivot": a.pivot,
            "boundsMin": [min(p_, q) for p_, q in zip(ra, rb)], "boundsMax": [max(p_, q) for p_, q in zip(ra, rb)],
            "size": [round(float(hi[0] - lo[0]), 3), round(float(hi[2] - lo[2]), 3), round(float(hi[1] - lo[1]), 3)],
            "tris": sum(p_["tris"] for p_ in parts), "parts": parts, "attachments": att, "colliders": cols}
    for a in assets:
        for role, o in a.objs:
            for an in ("mk", "vol", "fid"):
                at = o.data.attributes.get(an)
                if at is not None:
                    o.data.attributes.remove(at)
            for an in ("bk_col", "bk_rmp", "bk_kid"):
                at = o.data.color_attributes.get(an)
                if at is not None:
                    o.data.color_attributes.remove(at)
            if o.data.uv_layers:
                o.data.uv_layers[0].name = "UVMap"
            elif o["kind"] != "tex":
                planar_uv(o)
    # export: each GLB lays its assets out in a row along X
    glbs, problems_all = [], []
    metal_sets = [t for t, s_ in stats.items() if s_["metalness"]]
    for glb, names in GLB_GROUPS:
        x = 0.0
        for nm in names:
            a = by[nm]
            e = entries[nm]
            w = e["size"][0]
            offset = x - e["boundsMin"][0]
            a.root.location = (offset, 0.0, 0.0)
            e["origin"] = [round(offset, 4), 0.0, 0.0]
            e["glb"] = REL_OUT + "/" + glb
            x += w + 10.0
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        for nm in names:
            by[nm].root.select_set(True)
            for _, o in by[nm].objs:
                o.select_set(True)
        path = os.path.join(OUT, glb)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                                  export_image_format="AUTO", export_materials="EXPORT", export_normals=True,
                                  export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
                                  export_attributes=False)
        check, problems = glb_patch_and_check(path, metal_sets)
        problems_all += problems
        glbs.append({"file": REL_OUT + "/" + glb, "assets": names, "bytes": check["bytes"],
                     "sizeMB": round(check["bytes"] / 1e6, 2), "meshes": check["meshes"],
                     "embeddedImages": check["images"], "problems": problems})
        log("GLB %s: %d meshes, %.2f MB, problems %s" % (glb, check["meshes"], check["bytes"] / 1e6, problems))
        for nm in names:
            by[nm].root.location = (0.0, 0.0, 0.0)
    warnings = list(problems_all)
    for a in assets:
        e = entries[a.name]
        big = max(p_["tris"] for p_ in e["parts"])
        if big > 5000:
            warnings.append("%s: a part has %d triangles (limit 5k)" % (a.name, big))
        if e["tris"] > ASSET_MAX_TRIS:
            warnings.append("%s: %d triangles (limit 10k)" % (a.name, e["tris"]))
    cars = {}
    for shell, kit, length, turned in TRAIN_CARS:
        t = entries[shell]["tris"] + entries[kit]["tris"]
        cars[kit] = {"shell": shell, "shellTris": entries[shell]["tris"], "interiorTris": entries[kit]["tris"],
                     "total": t, "turned": turned}
        if t > ASSET_MAX_TRIS:
            warnings.append("%s + %s: %d triangles (a car should stay under 10k)" % (shell, kit, t))
    upload = []
    for tset, f in files.items():
        for k in ("color", "normal", "rough", "metal"):
            if k in f:
                upload.append(dict(file=REL_TEX + "/" + f[k], kind={"rough": "roughness", "metal": "metalness"}.get(
                    k, k), set=set_name(tset), **png_info(os.path.join(TEX, f[k]))))
    att = attach_table(assets)
    layout = {
        "hall": "Blender hall space: x across (west -85 .. east +85), y along (entrance +210 .. far end -210), floor "
                "0 -> Roblox (x, y, z) = (x, z, -y): the entrance end is Roblox -Z. Positions below are Roblox, "
                "relative to the hall origin (the hall's floor centre); yawDeg about +Y.",
        "station": layout_entries(station_layout()),
        "guards": layout_entries([("Station_Guard", loc, yaw) for loc, yaw in guard_layout()]),
        "trainWest": layout_entries(train_layout(-TRACK_X, NOSE_FRONT_Y, att)),
        "trainEast": layout_entries(train_layout(TRACK_X, NOSE_FRONT_Y, att)),
        "cars": [{"car": i + 1, "shell": s_, "interior": k_, "length": l_, "turnedRound": t_}
                 for i, (s_, k_, l_, t_) in enumerate(TRAIN_CARS)],
    }
    manifest = {
        "schema": "LS-Real-1 (train and station)", "category": CATEGORY,
        "source": "art/blender/train_sotr.py (seed %d); brief docs/design/UpcomingFilm_Brief.md section 4; owner "
                  "spec section 9 (docs/design/owner/TributeSpec_BloodAndMovement_2026-11-14.md)" % SEED,
        "glbs": glbs, "units": "1 Blender unit = 1 Roblox stud (world scale)",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y); an asset's front (+Y in Blender) is its Roblox LookVector "
                "(-Z). Each GLB lays its assets in a row along X: set Model.WorldPivot = CFrame.new(origin), then "
                "PivotTo the layout CFrame (and undo the importer's 180-degree turn about Y as ItemAssets does).",
        "textureFolder": REL_TEX, "uploadTextures": upload,
        "glbOnlyTextures": [REL_TEX + "/glb_only/" + f["mr"] for f in files.values()],
        "textureSets": {set_name(t): dict(members=[a.name for a in sets[t]], **{
            k: (REL_TEX + "/" + v) for k, v in files[t].items() if k != "mr"}, **{
            k: v for k, v in stats[t].items() if k != "keys"}) for t in files},
        "tones": {t: stats[t]["keys"] for t in files},
        "palette": {k: {"rgb": list(v["rgb"]), "luma": round(luma(v["rgb"]), 1), "roughness": v["rough"],
                        "metalness": v["metal"]} for k, v in MK.items()},
        "emissive": {k: list(v[0]) for k, v in EMIT.items()},
        "glass": {k: {"rgb": list(v[0]), "transparency": v[1]} for k, v in GLASS.items()},
        "patterns": PATTERNS, "layout": layout, "lighting": LIGHTING, "motion": MOTION,
        "collision": "Every mesh part is visual (CanCollide/CanQuery/CanTouch off, CollisionFidelity Box). Build the "
                     "collision from each asset's 'colliders' (invisible anchored Parts: centre and size in Roblox "
                     "space relative to the asset pivot; tag 'Floor' marks walkable tops). Doors leave 4 x 7.5 gaps.",
        "import": [
            "Import each GLB (3D Importer or bulk import); each asset root arrives as a Model of MeshParts "
            "<Asset>_<Role>[_n]. Re-centre with 'origin' (art/README.md section 4).",
            "Per part: textured parts get ONE SurfaceAppearance from 'surfaceAppearance' (ColorMap, NormalMap, "
            "RoughnessMap, MetalnessMap where given; Color white); Neon parts: Material Neon, Color = rgb, no "
            "SurfaceAppearance; Glass parts: Material Glass, Color = rgb, Transparency from the part.",
            "Every mesh part: Anchored (cars are anchored and moved as a whole by script), CanCollide/CanQuery/"
            "CanTouch off, CastShadow per part; then add the colliders.",
            "Attachments: create under the asset's first part with WorldCFrame = pivot * CFrame.lookAt(position, "
            "position + look, up). Door, chandelier, lamp, lid, vase, glass and guard attachments say which "
            "separate model goes there.",
            "Assemble the station and both trains from 'layout' (Roblox positions relative to the hall origin).",
            "No upload has been made; uploads need the owner's go-ahead.",
        ],
        "styleRules": STYLE_NOTES, "cars": cars,
        "ip": "Film-faithful places by the owner's choice; no film imagery, lettering, logos, emblems, posters, "
              "seals or crests. In-game names stay an open decision (the plaques and boards are blank or abstract).",
        "assets": [dict(entries[n], glb=entries[n].get("glb")) for g in GLB_GROUPS for n in g[1]],
        "warnings": warnings,
    }
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    os.makedirs(REPO_MANIFESTS, exist_ok=True)
    shutil.copyfile(MANIFEST_PATH, os.path.join(REPO_MANIFESTS, CATEGORY + ".manifest.json"))
    log("EXPORTED %d GLBs (%.2f MB), %d assets, %d texture sets, %d warnings" % (
        len(glbs), sum(g["sizeMB"] for g in glbs), len(entries), len(files), len(warnings)))
    for w in warnings:
        log("WARNING " + w)
    return manifest


# ================================================================================================ PREVIEW
def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def preview_load():
    """Fresh scene with every exported GLB; -> (inst, attach table in Blender space, manifest)."""
    reset()
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        man = json.load(f)
    coll = bpy.data.collections.new("TS_Imported")
    bpy.context.scene.collection.children.link(coll)
    for g in man["glbs"]:
        objs = import_glb(os.path.join(EXPORT_ROOT, g["file"]))
        for o in objs:
            for c in o.users_collection:
                c.objects.unlink(o)
            coll.objects.link(o)
    bpy.context.view_layer.update()
    inst, att = {}, {}
    for e in man["assets"]:
        root = bpy.data.objects.get(e["name"])
        if root is None:
            log("WARNING preview: %s not found in the GLBs" % e["name"])
            continue
        Rinv = root.matrix_world.inverted()
        lst = []
        pinfo = {p["name"]: p for p in e["parts"]}
        for ch in root.children:
            if ch.type != "MESH":
                continue
            pi = pinfo.get(ch.name)
            if pi is None:
                base = ch.name.split(".")[0]
                pi = pinfo.get(base)
            if pi is not None and pi["kind"] != "tex":
                ch.data.materials.clear()
                ch.data.materials.append(neon_material(pi["emitKey"]) if pi["kind"] == "neon" else
                                         glass_material(max(pi["keys"], key=pi["keys"].get)))
            ch["kind"] = pi["kind"] if pi else "tex"
            lst.append((pi["role"] if pi else "", ch, Rinv @ ch.matrix_world))
        inst[e["name"]] = lst
        att[e["name"]] = {k: dict(pos=tuple(to_blender(v["position"])), look=tuple(to_blender(v["look"])),
                                  note=v.get("note", "")) for k, v in e["attachments"].items()}
    exclude_collection(coll)
    return inst, att, man


def render_night_bridge(inst, att, path, samples=128):
    """The whole seven-car train crossing Train_BridgeBackdrop at night (after Trailer 2's journey shot, our own
    build): moonlit blue outside, amber windows, the red-orange lamp."""
    scene = bpy.context.scene
    for o in list(scene.objects):
        if o.name.startswith("TS_") and o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o, do_unlink=True)
    coll = bpy.data.collections.new("TS_Night")
    scene.collection.children.link(coll)
    place_asset(inst["Train_BridgeBackdrop"], (0, 0, 0), 0, coll)
    z = 30.0 + 2.45
    y = 300.0
    for name, loc, yaw in train_layout(0.0, y, att):
        if name in inst:
            place_asset(inst[name], (loc[0], loc[1], loc[2] + z), yaw, coll)
    for shell, kit, length, turned in TRAIN_CARS:
        yc = y - length / 2
        for dy in (-length / 4, length / 4):
            add_light(scene, "TS_CarLight_%d" % int(yc + dy), "POINT", (0, yc + dy, z + 6.0), 1500.0,
                      color=(1.0, 0.7, 0.42), size=1.0)
        y -= length + GANGWAY_GAP
    add_light(scene, "TS_NoseLamp", "SPOT", (0, 300.0 + 1.5, z + NOSE_ZC), 4000.0, color=(1.0, 0.36, 0.2), size=0.8,
              target=(0, 420.0, z + 2.0), spot=(50.0, 0.4))
    add_light(scene, "TS_NoseGlow", "POINT", (0, 301.0, z + NOSE_ZC), 200.0, color=(1.0, 0.36, 0.2), size=0.6)
    set_world(scene, (26, 34, 54), 0.5)
    moon = add_light(scene, "TS_Moon", "SUN", (0, 0, 300), 0.35, color=(0.62, 0.72, 1.0), size=1.0)
    moon.rotation_euler = V((0.4, -0.5, -0.75)).normalized().to_track_quat("-Z", "Y").to_euler()
    render_setup(scene, (1600, 900), samples)
    scene.view_settings.exposure = 0.9
    camera(scene, (-235.0, 470.0, 120.0), (10.0, 150.0, 30.0), hfov=46.0)
    render_to(scene, path)
    bpy.data.collections.remove(coll)
    for o in list(scene.objects):
        if o.name.startswith("TS_") and o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o, do_unlink=True)


def render_stats(path):
    a = tg.load_image_np(path, "sRGB")[..., :3].astype(np.float64)
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    lum = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    hot = (sat > 0.75) & (mx > 0.3)
    return {"meanLuma": round(float(lum.mean() * 255), 1), "meanSaturation": round(float(sat.mean()), 3),
            "saturatedPixels%": round(100.0 * float(hot.mean()), 2),
            "p95Saturation": round(float(np.percentile(sat, 95)), 3)}


def preview_stage(only=None):
    want = set(only or ["station", "exterior", "interiors", "compare", "tones"])
    os.makedirs(PREV, exist_ok=True)
    inst, att, man = preview_load()
    scene = bpy.context.scene
    shots = {}
    if want & {"station", "exterior"}:
        sc = bpy.data.collections.new("TS_Scene")
        scene.collection.children.link(sc)
        assemble_station(inst, att, sc, trains=True, interiors=True)
        light_station(scene)
        if "station" in want:
            render_setup(scene, (1600, 667), 160)
            station_frame_camera(scene)
            shots["station_frame"] = render_to(scene, os.path.join(PREV, "station_frame.png"))
            c = OWNER_CAM
            camera(scene, c["loc"], V(c["loc"]) + V((0.0, -1.0, math.tan(math.radians(c["pitch"])))), hfov=c["hfov"])
            shots["station_owner_match"] = render_to(scene, os.path.join(PREV, "station_owner_match.png"))
        render_setup(scene, (1600, 900), 160)
        for nm, (cam, tgt, hfov) in EXTERIOR_SHOTS.items():
            if (nm.startswith("station") and "station" in want) or (nm.startswith("exterior") and "exterior" in want):
                camera(scene, cam, tgt, hfov=hfov)
                shots[nm] = render_to(scene, os.path.join(PREV, nm + ".png"))
        bpy.data.collections.remove(sc)
        for o in list(scene.objects):
            if o.name.startswith("TS_") and o.type in ("LIGHT", "CAMERA"):
                bpy.data.objects.remove(o, do_unlink=True)
    if "exterior" in want and "Train_BridgeBackdrop" in inst:
        render_night_bridge(inst, att, os.path.join(PREV, "exterior_night_bridge.png"))
    if "interiors" in want:
        render_interiors(inst, att, PREV, samples=128)
        for k, nm in SHOT_NAMES.items():
            shots[nm] = os.path.join(PREV, nm + ".png")
    if "compare" in want:
        compare_sheets()
    if "tones" in want:
        tone_report(man)


# ------------------------------------------------------------------------------------------------ sheets
_TEXT_CACHE = {}


def text_tris(text):
    if text in _TEXT_CACHE:
        return _TEXT_CACHE[text]
    curve = bpy.data.curves.new("_lbl", type="FONT")
    curve.body = text
    curve.size = 1.0
    obj = bpy.data.objects.new("_lbl", curve)
    bpy.context.scene.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    verts = np.array([v.co[:2] for v in me.vertices], np.float64)
    tris = np.array([t.vertices[:] for t in me.loop_triangles], np.int64)
    ev.to_mesh_clear()
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    res = verts[tris] if len(tris) else np.zeros((0, 3, 2))
    _TEXT_CACHE[text] = res
    return res


def draw_text(img, text, x, y, size, rgb=(1, 1, 1), ss=3):
    """Rasterise text (Blender's built-in font) onto img (H x W x 3, row 0 = top) with its baseline at y."""
    tris = text_tris(text)
    if len(tris) == 0:
        return
    H, W = img.shape[:2]
    pts = tris * size
    pts[..., 0] += x
    pts[..., 1] = y - pts[..., 1]
    x0 = int(max(0, math.floor(pts[..., 0].min())))
    x1 = int(min(W, math.ceil(pts[..., 0].max()) + 1))
    y0 = int(max(0, math.floor(pts[..., 1].min())))
    y1 = int(min(H, math.ceil(pts[..., 1].max()) + 1))
    if x1 <= x0 or y1 <= y0:
        return
    hs, ws = (y1 - y0) * ss, (x1 - x0) * ss
    cov = np.zeros((hs, ws), bool)
    P = (pts - np.array([x0, y0])) * ss
    for t in P:
        bx0, by0 = int(max(0, math.floor(t[:, 0].min()))), int(max(0, math.floor(t[:, 1].min())))
        bx1, by1 = int(min(ws, math.ceil(t[:, 0].max()) + 1)), int(min(hs, math.ceil(t[:, 1].max()) + 1))
        if bx1 <= bx0 or by1 <= by0:
            continue
        yy, xx = np.mgrid[by0:by1, bx0:bx1]
        px, py = xx + 0.5, yy + 0.5
        a, b, c = t
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / d
        l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / d
        l3 = 1 - l1 - l2
        cov[by0:by1, bx0:bx1] |= (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
    alpha = cov.reshape(y1 - y0, ss, x1 - x0, ss).mean(axis=(1, 3))[..., None]
    img[y0:y1, x0:x1] = img[y0:y1, x0:x1] * (1 - alpha) + np.asarray(rgb)[None, None, :] * alpha


def load_rgb(path):
    a = tg.load_image_np(path, "sRGB")[..., :3]
    return np.flipud(a).astype(np.float64)


def resize(img, w, h):
    H, W = img.shape[:2]
    f = max(1, int(min(H / h, W / w)))
    if f > 1:
        img = img[:H - H % f, :W - W % f].reshape(H // f, f, W // f, f, -1).mean(axis=(1, 3))
        H, W = img.shape[:2]
    ys = (np.arange(h) + 0.5) * H / h - 0.5
    xs = (np.arange(w) + 0.5) * W / w - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, H - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, W - 1)
    y1 = np.clip(y0 + 1, 0, H - 1)
    x1 = np.clip(x0 + 1, 0, W - 1)
    fy = np.clip(ys - y0, 0, 1)[:, None, None]
    fx = np.clip(xs - x0, 0, 1)[None, :, None]
    a = img[y0][:, x0]
    b = img[y0][:, x1]
    c = img[y1][:, x0]
    d = img[y1][:, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fit(img, w, h):
    """Crop to the w:h aspect (centre) and resize."""
    H, W = img.shape[:2]
    if W / H > w / h:
        nw = int(round(H * w / h))
        img = img[:, (W - nw) // 2:(W - nw) // 2 + nw]
    else:
        nh = int(round(W * h / w))
        img = img[(H - nh) // 2:(H - nh) // 2 + nh]
    return resize(img, w, h)


def compose(panels, cols, out_path, title=None, subtitle=None, label_h=40, pad=10, bg=(0.086, 0.094, 0.11),
            label_rgb=(0.93, 0.84, 0.67), size=20):
    h, w = panels[0][0].shape[:2]
    rows = (len(panels) + cols - 1) // cols
    top = (68 if subtitle else 48) if title else 0
    W = cols * w + (cols + 1) * pad
    H = top + rows * (h + label_h) + (rows + 1) * pad
    sheet = np.ones((H, W, 3)) * np.asarray(bg)
    if title:
        draw_text(sheet, title, pad + 4, 32, 26, (0.97, 0.97, 0.97))
        if subtitle:
            draw_text(sheet, subtitle, pad + 4, 58, 16, (0.72, 0.74, 0.78))
    for i, (im, lab) in enumerate(panels):
        r, c = divmod(i, cols)
        x = pad + c * (w + pad)
        y = top + pad + r * (h + label_h + pad)
        if lab:
            draw_text(sheet, lab, x + 4, y + label_h - 12, size, label_rgb)
        sheet[y + label_h:y + label_h + h, x:x + w] = im[:h, :w]
    tg.write_png(out_path, np.flipud(np.clip(sheet, 0, 1)), quantize=False)
    log("SHEET", out_path, "%dx%d" % (W, H))
    return out_path


def compare_sheets():
    """Owner/trailer frames beside our renders (study only: these sheets are kept out of git by .gitignore)."""
    own = os.path.join(REFS, "owner", "train_station_owner_frame.png")
    tr = os.path.join(REFS, "trailer")
    pairs = [
        ("compare_station.png", [(own, None, "Owner frame (T1 @35.7 s, study only)"),
                                 (os.path.join(PREV, "station_owner_match.png"), None, "Ours, from higher up (the brief's tracks sit wider apart)"),
                                 (os.path.join(tr, "trailer1_35.7s.png"), None, "Trailer 1 @35.7 s, the wide view"),
                                 (os.path.join(PREV, "station_frame.png"), None, "Ours, wide: the coffers, oval and sunburst")],
         (1100, 458), "The station hall: owner frame vs our build",
         "Coffered ceiling and oval, gold sunburst, white cross-beam, banners, boards, posters, guards, two trains"),
        ("compare_train.png", [(os.path.join(tr, "trailer1_35.7s_detail_trains.png"), None, "Trailer 1 @35.7 s (detail)"),
                               (os.path.join(PREV, "exterior_nose.png"), None, "Ours: Train_NoseCar on the platform")],
         (1000, 563), "The train: film detail vs our nose car",
         "Bullet nose, round gold-rimmed lamp with a red-orange core, black lacquer, maroon flank, gold pinstripes"),
        ("compare_interiors.png", [(os.path.join(tr, "fanedit_1.4s.png"), None, "Fan Edit @1.4 s: upholstery, brass window"),
                                   (os.path.join(PREV, "interior_car1_vestibule.png"), None, "Ours: car 1 saloon"),
                                   (os.path.join(tr, "fanedit_3.8s.png"), None, "Fan Edit @3.8 s: hammered ceiling, arch"),
                                   (os.path.join(PREV, "interior_car2_dining.png"), None, "Ours: car 2 dining")],
         (800, 450), "The train inside: film frames vs our cars",
         "Geometric burgundy-cream upholstery, round-cornered brass windows, hammered cream-gold vault, wood arches"),
    ]
    for fname, items, (w, h), title, sub in pairs:
        panels = []
        ok = True
        for path, crop, lab in items:
            if not os.path.exists(path):
                log("WARNING compare: missing %s" % path)
                ok = False
                break
            panels.append((fit(load_rgb(path), w, h), lab))
        if ok:
            compose(panels, 2, os.path.join(PREV, fname), title, sub)


DELIBERATE_BLACKS = {"lacquer", "bezel", "board", "harness", "piano", "screen_frame", "bellows", "visor", "underframe",
                     "poster_dark", "water_dark", "suit", "steel_dark", "hill"}


def tone_report(man):
    """Swatch sheet: each paint key's brief tone beside its baked mean (after AO), plus render statistics."""
    rows = []
    seen = set()
    for tset, keys in man.get("tones", {}).items():
        for k, v in sorted(keys.items(), key=lambda kv: -kv[1]["texels"]):
            if k in seen or v["texels"] < 400:
                continue
            seen.add(k)
            rows.append((k, tset, v["target"], v["meanSRGB"], v["luma"]))
    rows.sort(key=lambda r: r[0])
    cw, ch, cols = 300, 64, 4
    nrow = (len(rows) + cols - 1) // cols
    H, W = 90 + nrow * (ch + 30), cols * (cw + 16) + 16
    sheet = np.ones((H, W, 3)) * np.array([0.086, 0.094, 0.11])
    draw_text(sheet, "Train set tones: brief tone (left) vs baked mean after AO (right)", 16, 34, 24,
              (0.97, 0.97, 0.97))
    draw_text(sheet, "luma of the baked mean; built surfaces 55-215, deliberate blacks >= 40 (ArtStyle rule 6)", 16, 62,
              15, (0.72, 0.74, 0.78))
    for i, (k, tset, tgt, got, lu) in enumerate(rows):
        r, c = divmod(i, cols)
        x, y = 16 + c * (cw + 16), 80 + r * (ch + 30)
        sheet[y:y + ch, x:x + cw // 2] = np.asarray(tgt) / 255.0
        sheet[y:y + ch, x + cw // 2:x + cw] = np.asarray(got) / 255.0
        flag = "" if (40 if k in DELIBERATE_BLACKS else 55) <= lu <= 215 else "  OUT"
        draw_text(sheet, "%s  %d%s" % (k, int(round(lu)), flag), x + 2, y + ch + 20, 15,
                  (1.0, 0.55, 0.45) if flag else (0.85, 0.85, 0.82))
    tg.write_png(os.path.join(PREV, "tones_palette.png"), np.flipud(np.clip(sheet, 0, 1)), quantize=False)
    stats = {}
    for fn in sorted(os.listdir(PREV)):
        if fn.endswith(".png") and (fn.startswith("station") or fn.startswith("exterior") or fn.startswith("interior")):
            stats[fn] = render_stats(os.path.join(PREV, fn))
    refs = {"owner_frame": os.path.join(REFS, "owner", "train_station_owner_frame.png")}
    for k, pth in refs.items():
        if os.path.exists(pth):
            stats[k + " (reference)"] = render_stats(pth)
    out = os.path.join(WORK, "render_tones.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"renders": stats, "keys": {r[0]: {"target": r[2], "baked": r[3], "luma": r[4]} for r in rows}},
                  f, indent=1)
    for k, v in stats.items():
        log("TONES %-34s %s" % (k, v))
    out_of_band = [r for r in rows if not (40 if r[0] in DELIBERATE_BLACKS else 55) <= r[4] <= 215]
    log("TONES %d keys measured, %d outside the band (55-215; deliberate blacks >= 40): %s" % (len(rows), len(out_of_band),
                                                               [(r[0], r[4]) for r in out_of_band]))


# ================================================================================================ asset sets
def build_station_assets():
    return [build_coffer(), build_entrance_ceiling(), build_lantern(), build_sunburst(), build_entrance_walls(),
            build_entrance_floor(), build_portal(), build_shed_bay(), build_floor_bay(), build_shed_end(),
            build_banner(), build_board(), build_poster(), build_guard()]


def build_train_assets():
    return [build_car_shell("nose"), build_car_shell("body"), build_car_shell("obs"), build_door_leaf(),
            build_car1_vestibule(), build_car2_dining(), build_car3_lounge(), build_car4_corridor(),
            build_car5_compartment(), build_car6_observation(), build_car7_guard(),
            build_chandelier(), build_pendant(), build_compartment_door(), build_vestibule_door(),
            build_gangway_door(), build_globe_lid(), build_bud_vase(), build_crystal(), build_bridge_backdrop()]


def build_all_assets():
    return build_station_assets() + build_train_assets()


def make_objects(assets, coll_name="TS_Assets"):
    coll = bpy.data.collections.new(coll_name)
    bpy.context.scene.collection.children.link(coll)
    for i, a in enumerate(assets):
        build_asset_objects(a, coll, salt=i + 1)
        a.inst = [(r, o, o.matrix_world.copy()) for r, o in a.objs]
        log("ASSET %-26s tris %6d  parts %s" % (a.name, sum(tri_count(o) for _, o in a.objs),
                                                  ", ".join("%s:%d" % (o.name[len(a.name) + 1:], tri_count(o))
                                                            for _, o in a.objs)))
    return coll


def exclude_collection(coll):
    def find(lc):
        if lc.collection == coll:
            return lc
        for ch in lc.children:
            r = find(ch)
            if r:
                return r
        return None
    lc = find(bpy.context.view_layer.layer_collection)
    if lc:
        lc.exclude = True


def place_asset(inst, loc, yaw=0.0, coll=None):
    """Linked copies of an asset's parts (inst: [(role, obj, asset-local matrix)]) at loc, turned yaw degrees."""
    M = Matrix.Translation(V(loc)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    out = []
    for role, o, Ml in inst:
        c = bpy.data.objects.new(o.name + "_i", o.data)
        (coll or bpy.context.scene.collection).objects.link(c)
        c.matrix_world = M @ Ml
        for k in ("role", "kind", "key"):
            if k in o:
                c[k] = o[k]
        out.append(c)
    return out


TRAIN_CARS = [  # shell, interior kit, length, turned round
    ("Train_NoseCar", "Train_Car1_Vestibule", NOSE_CAR_L, False),
    ("Train_BodyCar", "Train_Car2_Dining", CAR_L, False),
    ("Train_BodyCar", "Train_Car3_Lounge", CAR_L, False),
    ("Train_BodyCar", "Train_Car4_Corridor", CAR_L, False),
    ("Train_BodyCar", "Train_Car5_Compartment", CAR_L, False),
    ("Train_ObservationCar", "Train_Car6_Observation", CAR_L, False),
    ("Train_NoseCar", "Train_Car7_Guard", NOSE_CAR_L, True),
]
ATTACH_PIECES = [("DoorR_", "Train_DoorLeaf", 0.0), ("DoorL_", "Train_DoorLeaf", 180.0),
                 ("Chandelier_", "Train_Chandelier", 0.0), ("Pendant_", "Train_PendantLamp", 0.0),
                 ("VestibuleDoor", "Train_VestibuleDoor", 0.0), ("GangwayDoor", "Train_GangwayDoor", 0.0),
                 ("GlobeLid", "Train_GlobeLid", 0.0), ("BudVase", "Train_BudVase", 0.0),
                 ("Glass_", "Train_Crystal", 0.0), ("GuardPost_", "Station_Guard", None),
                 ("CompartmentDoor_", "Train_CompartmentDoor", 0.0)]


def car_pieces(attach_by_asset, shell, kit):
    """[(piece asset, local pos, yaw)] from a car's shell and kit attachments."""
    out = []
    for an in (shell, kit):
        for nm, a in attach_by_asset.get(an, {}).items():
            for pre, piece, yaw in ATTACH_PIECES:
                if not nm.startswith(pre):
                    continue
                if pre == "CompartmentDoor_" and "Train_CompartmentDoor here" not in a.get("note", ""):
                    continue
                if yaw is None:
                    yaw = 0.0 if a["look"][1] >= 0 else 180.0
                out.append((piece, V(a["pos"]), yaw))
    return out


def train_layout(x, y_front, attach_by_asset, cars=None):
    """[(asset, loc, yaw)] for one train with its nose at y_front heading +Y."""
    L = []
    y = y_front
    for shell, kit, length, turned in (cars or TRAIN_CARS):
        yc = y - length / 2
        yaw = 180.0 if turned else 0.0
        M = Matrix.Translation(V((x, yc, 0))) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        L += [(shell, (x, yc, 0.0), yaw), (kit, (x, yc, 0.0), yaw)]
        for piece, pos, pyaw in car_pieces(attach_by_asset, shell, kit):
            L.append((piece, tuple(M @ pos), yaw + pyaw))
        y -= length + GANGWAY_GAP
    return L


def attach_table(assets):
    return {a.name: {k: dict(pos=tuple(v["pos"]), look=tuple(v["look"]), note=v["extra"].get("note", ""))
                     for k, v in a.attach.items()} for a in assets}


def station_frame_camera(scene, res=(1600, 667)):
    c = STATION_CAM
    loc = V(c["loc"])
    tgt = loc + V((0.0, -1.0, math.tan(math.radians(c["pitch"]))))
    return camera(scene, loc, tgt, hfov=c["hfov"], res=res)


STATION_CAM = dict(loc=(0.0, 205.0, 6.8), pitch=12.5, hfov=98.0)
OWNER_CAM = dict(loc=(-4.0, 192.0, 19.0), pitch=5.7, hfov=88.0)     # the owner's tighter, elevated frame


def assemble_station(inst, attach_by_asset, coll, trains=True, interiors=True):
    for name, loc, yaw in station_layout():
        if name in inst:
            place_asset(inst[name], loc, yaw, coll)
    for loc, yaw in guard_layout():
        place_asset(inst["Station_Guard"], loc, yaw, coll)
    if trains:
        for x in (-TRACK_X, TRACK_X):
            for name, loc, yaw in train_layout(x, NOSE_FRONT_Y, attach_by_asset):
                if name in inst and (interiors or not name.startswith("Train_Car")):
                    place_asset(inst[name], loc, yaw, coll)


# ================================================================================================ light rigs
def light_station(scene, exposure=0.0):
    set_world(scene, "sky", strength=0.32, sun_elev=13.0, sun_azim=-100.0)
    d = V((0.93, -0.22, -0.30)).normalized()
    sun = add_light(scene, "TS_Sun", "SUN", (0, 0, 200), 3.6, color=(1.0, 0.72, 0.46), size=1.2)
    sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    for x in (-60.0, -20.0, 20.0, 60.0):
        for y in (70.0, 115.0, 160.0, 198.0):
            add_light(scene, "TS_Down_%d_%d" % (x, y), "AREA", (x, y, CEIL_Z - 1.5), 7000.0, color=(1.0, 0.78, 0.56),
                      size=34.0, size_y=40.0, rot=(0, 0, 0))
    for k in range(9):
        add_light(scene, "TS_Shed_%d" % k, "AREA", (0, ENT_Y0 - 20.0 - 40.0 * k, SHED_H - 4.0), 12000.0,
                  color=(1.0, 0.8, 0.62), size=150.0, size_y=30.0, rot=(0, 0, 0))
    add_light(scene, "TS_Oval", "AREA", (0, OVAL_Y, LANTERN_Z - 1.5), 14000.0, color=(1.0, 0.84, 0.64), size=70.0,
              size_y=34.0, rot=(0, 0, 0))
    for x in (-TRACK_X, TRACK_X):
        add_light(scene, "TS_Lamp_%d" % x, "POINT", (x, NOSE_FRONT_Y + 1.5, 4.6), 90.0, color=(1.0, 0.36, 0.2),
                  size=0.6)
    scene.view_settings.exposure = exposure


def light_interior(scene, car_kind, kit_name, attach, outside="dusk"):
    """Amber coves (area lights along both coves), chandeliers / pendants / sconces, the screen, dim sky outside."""
    if outside == "night":
        set_world(scene, (40, 52, 82), 0.6)
    else:
        set_world(scene, (92, 98, 124), 0.55)
    L = NOSE_CAR_L if car_kind == "nose" else CAR_L
    if kit_name == "Train_Car7_Guard":
        for y in range(-38, 26, 8):
            add_light(scene, "TS_Strip_%d" % y, "AREA", (0, y + 2.5, VAULT_Z - 0.3), 260.0, color=(0.88, 0.93, 1.0),
                      size=0.7, size_y=5.0, rot=(0, 0, 0))
    elif kit_name == "Train_Car6_Observation":
        for s in (-1, 1):
            add_light(scene, "TS_Cove_%d" % s, "AREA", (s * (HWID - 0.6), 0, 1.35), 1600.0, color=(1.0, 0.7, 0.42),
                      size=0.3, size_y=L - 2, rot=(0, 0, 0))
        add_light(scene, "TS_ObsFill", "AREA", (0, 0, 9.0), 500.0, color=(1.0, 0.72, 0.45), size=3.0,
                  size_y=L - 10, rot=(0, 0, 0))
        add_light(scene, "TS_Moon", "SUN", (0, 0, 100), 0.25, color=(0.62, 0.72, 1.0), size=1.0,
                  rot=(math.radians(55), 0, math.radians(30)))
    else:
        for s in (-1, 1):
            add_light(scene, "TS_Cove_%d" % s, "AREA", (s * (LIN_X - 0.3), 0, WALL_TOP + 0.12), 5200.0,
                      color=(1.0, 0.68, 0.40), size=0.35, size_y=L - 2, rot=(0, 0, 0))
        add_light(scene, "TS_Fill", "AREA", (0, 0, VAULT_Z - 0.4), 1400.0, color=(1.0, 0.75, 0.5), size=4.0,
                  size_y=L - 10, rot=(0, 0, 0))
    for nm, a in attach.items():
        p = V(a["pos"])
        if nm.startswith("Chandelier_"):
            add_light(scene, "TS_" + nm, "POINT", p + V((0, 0, -1.8)), 260.0, color=(1.0, 0.8, 0.55), size=0.6)
        elif nm.startswith("CeilingLamp_"):
            add_light(scene, "TS_" + nm, "POINT", p + V((0, 0, -0.4)), 90.0 if nm[12:13].isdigit() else 240.0,
                      color=(1.0, 0.78, 0.52), size=0.3)
        elif nm.startswith("Pendant_"):
            add_light(scene, "TS_" + nm, "POINT", p + V((0, 0, -1.85)), 140.0, color=(1.0, 0.78, 0.52), size=0.3)
        elif nm == "Screen":
            add_light(scene, "TS_Screen", "AREA", p + V((0, 0.4, 0)), 90.0, color=(0.62, 0.78, 1.0), size=4.6,
                      size_y=2.8, target=p + V((0, 6, 0)))
    if kit_name == "Train_Car2_Dining":
        for s in (-1, 1):
            for c in (-28.0, -20.0, -12.0, -4.0, 4.0, 12.0, 20.0, 28.0):
                add_light(scene, "TS_Sconce_%d_%d" % (s, c), "POINT", (s * (LIN_X - 0.45), c, 6.6), 18.0,
                          color=(1.0, 0.8, 0.55), size=0.2)
    scene.view_settings.exposure = 0.55


def outside_dressing(scene, coll, night=False):
    """A ground plane and a ring of low hills outside the car windows (preview only)."""
    mb = MB()
    mb.face(rect_loop(-900.0, -900.0, 900.0, 900.0, -2.6), "hill")
    rng = random.Random(SEED + 400)
    for k in range(18):
        a = TAU * k / 18
        r = rng.uniform(140.0, 260.0)
        cx, cy = r * math.cos(a), r * math.sin(a)
        pts = [(cx + rng.uniform(-90, 90), cy + rng.uniform(-90, 90), -3.0) for _ in range(8)]
        pts += [(cx + rng.uniform(-30, 30), cy + rng.uniform(-30, 30), rng.uniform(30, 80)) for _ in range(3)]
        hull(mb, pts, "hill")
    o = mb_object(mb, "TS_Outside", coll)
    paint(o, 99)
    o.data.materials.append(quick_tex_material())
    return o


INTERIOR_SHOTS = {   # kit -> (camera, target, hfov) in car space
    "Train_Car1_Vestibule": ((0.3, -35.9, 5.3), (-0.4, 10.0, 3.7), 76.0),
    "Train_Car2_Dining": ((0.4, 31.0, 5.4), (-0.9, -6.0, 3.5), 78.0),
    "Train_Car3_Lounge": ((-3.05, 31.0, 5.4), (-0.6, -8.0, 3.8), 78.0),
    "Train_Car4_Corridor": ((3.2, 31.0, 5.3), (2.6, -6.0, 4.2), 74.0),
    "Train_Car5_Compartment": ((0.4, 1.6, 5.5), (-4.8, -6.5, 3.4), 96.0),
    "Train_Car6_Observation": ((0.0, 38.6, 5.4), (0.4, 0.0, 3.8), 80.0),
    "Train_Car7_Guard": ((0.0, -43.6, 5.3), (0.0, 0.0, 4.2), 76.0),
}
INTERIOR_EXTRA = {   # a second look where one doorway view cannot hold the room
    "Train_Car5_Compartment": [("interior_car5_compartment_b", (-0.8, -1.5, 5.5), (-3.0, 10.3, 4.4), 92.0)],
}
SHOT_NAMES = {"Train_Car1_Vestibule": "interior_car1_vestibule", "Train_Car2_Dining": "interior_car2_dining",
              "Train_Car3_Lounge": "interior_car3_lounge", "Train_Car4_Corridor": "interior_car4_corridor",
              "Train_Car5_Compartment": "interior_car5_compartment",
              "Train_Car6_Observation": "interior_car6_observation", "Train_Car7_Guard": "interior_car7_guard"}


def render_interiors(inst, attach_by_asset, out_dir, which=None, prefix="", samples=96):
    scene = bpy.context.scene
    for shell, kit, length, turned in TRAIN_CARS:
        if which and kit not in which:
            continue
        for o in list(scene.objects):
            if o.name.startswith("TS_") or o.get("_shot"):
                bpy.data.objects.remove(o, do_unlink=True)
        coll = bpy.data.collections.get("TS_Shot") or bpy.data.collections.new("TS_Shot")
        if coll.name not in scene.collection.children:
            scene.collection.children.link(coll)
        for o in list(coll.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        objs = place_asset(inst[shell], (0, 0, 0), 0, coll) + place_asset(inst[kit], (0, 0, 0), 0, coll)
        for piece, pos, pyaw in car_pieces(attach_by_asset, shell, kit):
            if piece in inst:
                if piece == "Train_CompartmentDoor":
                    if kit == "Train_Car5_Compartment":
                        continue                      # open: slid into the wall pocket, out of the doorway view
                    pos = pos + V((0, 4.2, 0))
                elif piece == "Train_VestibuleDoor":
                    pos = pos + V((4.3, 0, 0))
                objs += place_asset(inst[piece], pos, pyaw, coll)
        night = kit == "Train_Car6_Observation"
        if night and "Train_BridgeBackdrop" in inst:
            objs += place_asset(inst["Train_BridgeBackdrop"], (150.0, -160.0, -38.0), 28.0, coll)
        else:
            o = outside_dressing(scene, coll)
            o["_shot"] = True
        car_kind = {"Train_NoseCar": "nose", "Train_BodyCar": "body", "Train_ObservationCar": "obs"}[shell]
        light_interior(scene, car_kind, kit, attach_by_asset.get(kit, {}), "night" if night else "dusk")
        cam, tgt, hfov = INTERIOR_SHOTS[kit]
        render_setup(scene, (1600, 900), samples)
        camera(scene, cam, tgt, hfov=hfov, res=None)
        render_to(scene, os.path.join(out_dir, prefix + SHOT_NAMES[kit] + ".png"))
        for nm, cam2, tgt2, hfov2 in INTERIOR_EXTRA.get(kit, []):
            camera(scene, cam2, tgt2, hfov=hfov2, res=None)
            render_to(scene, os.path.join(out_dir, prefix + nm + ".png"))


EXTERIOR_SHOTS = {
    "exterior_nose": ((TRACK_X + 6.0, NOSE_FRONT_Y + 23.0, 5.2), (TRACK_X - 1.5, NOSE_FRONT_Y - 6.0, 4.4), 58.0),
    "exterior_side": ((PLAT_X - 4.5, NOSE_FRONT_Y - 12.0, 5.8), (TRACK_X - 4.0, NOSE_FRONT_Y - 120.0, 5.4), 62.0),
    "station_platform": ((PLAT_X - 10.5, NOSE_FRONT_Y - 12.0, 5.6), (PLAT_X - 7.0, -120.0, 9.0), 82.0),
}


# ================================================================================================ quick stage
def quick_stage(what):
    reset()
    scene = bpy.context.scene
    want_station = what in ("station", "exterior", "all")
    want_interiors = what.startswith("car") or what in ("interiors", "all")
    assets = (build_station_assets() if want_station else [build_guard()]) + build_train_assets()
    coll = make_objects(assets)
    for a in assets:
        assign_quick_materials(a)
    exclude_collection(coll)
    inst = {a.name: a.inst for a in assets}
    att = attach_table(assets)
    budget_report(assets)
    if want_station:
        sc = bpy.data.collections.new("TS_Scene")
        scene.collection.children.link(sc)
        assemble_station(inst, att, sc, trains=True, interiors=(what != "station"))
        light_station(scene)
        render_setup(scene, (1600, 667), 48)
        station_frame_camera(scene)
        render_to(scene, os.path.join(WORK, "quick_station_frame.png"))
        render_setup(scene, (1600, 900), 48)
        for nm, (cam, tgt, hfov) in EXTERIOR_SHOTS.items():
            camera(scene, cam, tgt, hfov=hfov)
            render_to(scene, os.path.join(WORK, "quick_%s.png" % nm))
        bpy.data.collections.remove(sc)
    if want_interiors:
        which = None
        if what.startswith("car") and len(what) > 3:
            which = [k for k in SHOT_NAMES if k.startswith("Train_Car%s_" % what[3:])]
        render_interiors(inst, att, WORK, which, prefix="quick_", samples=48)


def budget_report(assets):
    by = {a.name: a for a in assets}
    for a in assets:
        t = sum(tri_count(o) for _, o in a.objs)
        big = max((tri_count(o) for _, o in a.objs), default=0)
        if big > 5000 or t > ASSET_MAX_TRIS:
            log("WARNING budget %s: %d tris, largest part %d" % (a.name, t, big))
    for shell, kit, length, turned in TRAIN_CARS:
        if shell in by and kit in by:
            t = sum(tri_count(o) for _, o in by[shell].objs) + sum(tri_count(o) for _, o in by[kit].objs)
            log("CAR %-24s shell+interior %6d tris%s" % (kit, t, "  (over 10k)" if t > ASSET_MAX_TRIS else ""))


def main():
    log("train_sotr.py OUT=%s PREV=%s WORK=%s stages=%s" % (OUT, PREV, WORK, STAGES))
    os.makedirs(WORK, exist_ok=True)
    for st in STAGES:
        if st.startswith("quick"):
            quick_stage(st.split(":", 1)[1] if ":" in st else "all")
        elif st == "build":
            build_stage()
        elif st.startswith("preview"):
            preview_stage(st.split(":", 1)[1].split("+") if ":" in st else None)
    log("DONE")


if __name__ == "__main__":
    main()
