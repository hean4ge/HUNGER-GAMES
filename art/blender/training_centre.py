"""
training_centre.py - LAST STANDING: the Training Centre (Blender 5.3, headless)
                     -> TrainingCentre.glb, TrainingCentre.manifest.json, TrainingCentre.blend, owner sheets.

The owner, 15 Nov 2026: "add skills when in game train goes to training room like in the movies and people get to test
diff kits and abilities"; 18 Nov: "the train that taakes them to the prep room before the arena where they get to choose
their allies and enter the room"; 19 Nov: "Training room first". Design page: docs/design/TrainingAndLoadup.md
(sections 3, 5 and 6). Our own design: teal padded walls with white diagonal ribs, a blue-grey chequered carpet, coffered
ceiling with round downlights, stacked colour-bar boards, orange ONLY on what you can use. No film names, crests or
frames. Matte, one flat colour per part, no image textures.

Hall space (all numbers below, and every manifest vector): Roblox axes, studs, origin = the hall floor centre, which the
game puts at place (8800, 200, 3000). x -110..110 (east +), z -75..75 (north -), floor y 0, ceiling 36.

Assets (each its own root; one MeshPart per role; colliders are <Asset>_<What>_Col boxes):
  TC_Platform     platform B (arrival), the track pit and guideway, the station roof, lamp banks, tunnel portals
  TC_HallShell    floor + chequer, padded walls, ribs, coffered ceiling + downlights, arches, big screen, colour bars
  TC_Archery      6 lanes, shooting line, 18 targets on orange stands (20/40/60), backstop, the Archer mat
  TC_BladeRing    padded ring r 14, spinning post, orange weapon cart, partitions
  TC_SpearRange   throw line, 5 boards (10..50), 2 orange spear racks, hay bales, the Hunter mat
  TC_Survival     fire pit, 3 snares, plant table (3 sound, 3 spoiled), trough, the Forager and Medic mats
  TC_Fitness      climbing wall 30 x 24 (orange holds, Climbable), 4 bikes, weights + bench, rope, the Climber mat
  TC_PrepFloor    the running track (lap 300), obstacle run (vault box, mantle wall, slide bar), 8 benches, kit board
  TC_LaunchDoors  steel surround, two sliding oxblood leaves (pocket doors), red lamp, the 12-stud corridor, end cap
  TC_Chest        the station chest (placed 5 times), lid separate, LidHinge / Prompt / LootPoint
  TC_Dummy        a burlap training dummy, one part per R15 limb (R15 names kept), on a steel plate (placed 5 times)

Run: blender --background --factory-startup --python training_centre.py -- <export dir> <preview dir> [build,preview]
env TC_SAMPLES (default 40). Seeded (SEED = 1119).
"""
import json
import math
import os
import random
import struct
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

T0 = time.time()
V = Vector
TAU = 2 * math.pi


def log(*a):
    print("[training_centre %5.1fs]" % (time.time() - T0), *a, flush=True)


ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CATEGORY = "TrainingCentre"
EXPORTS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")
OUT = os.path.join(ARGV[0], CATEGORY) if len(ARGV) > 0 and ARGV[0] not in ("", "-") else os.path.join(EXPORTS, CATEGORY)
PREV = os.path.abspath(ARGV[1]) if len(ARGV) > 1 else os.path.join(OUT, "previews")
STAGES = (ARGV[2] if len(ARGV) > 2 else "build,preview").split(",")
SAMPLES = int(os.environ.get("TC_SAMPLES", "40"))
ONLY = os.environ.get("TC_ONLY", "")
SEED = 1119
TRAIN_GLB = os.path.join(EXPORTS, "TrainLobby", "TrainLobby.glb")
TRAIN_MAN = os.path.join(EXPORTS, "TrainLobby", "TrainLobby.manifest.json")

HALL_AT = [8800.0, 200.0, 3000.0]
HX, HZ, HH = 110.0, 75.0, 36.0       # half width, half depth, height
WALL = 2.0

# ------------------------------------------------------------------------------------------------ palette
# role -> (rgb, Roblox material, extra). One flat colour per part. Orange ("Use") only on what you can use.
ROLES = {
    "Floor":      ((104, 116, 122), "Carpet"),
    "FloorTile":  ((150, 158, 162), "Carpet"),
    "Panel":      ((78, 112, 118), "Fabric"),
    "PanelBack":  ((44, 62, 66), "SmoothPlastic"),
    "Skirting":   ((50, 56, 60), "SmoothPlastic"),
    "Rib":        ((212, 214, 208), "SmoothPlastic"),
    "Trim":       ((196, 200, 196), "SmoothPlastic"),
    "Ceiling":    ((54, 58, 62), "SmoothPlastic"),
    "CeilBeam":   ((86, 92, 96), "SmoothPlastic"),
    "Downlight":  ((236, 240, 236), "Neon"),
    "Frame":      ((40, 44, 48), "Metal"),
    "Screen":     ((24, 26, 30), "SmoothPlastic"),
    "BarTeal":    ((72, 126, 130), "SmoothPlastic"),
    "BarOchre":   ((172, 144, 88), "SmoothPlastic"),
    "BarSlate":   ((92, 110, 140), "SmoothPlastic"),
    "BarRose":    ((158, 104, 108), "SmoothPlastic"),
    "BarSage":    ((126, 148, 118), "SmoothPlastic"),
    "Steel":      ((120, 126, 132), "Metal"),
    "DarkSteel":  ((52, 56, 60), "Metal"),
    "Use":        ((210, 106, 44), "SmoothPlastic"),
    "UseMat":     ((204, 102, 46), "Rubber"),
    "Line":       ((222, 222, 214), "SmoothPlastic"),
    "Track":      ((148, 84, 66), "Rubber"),
    "Wood":       ((128, 92, 60), "Wood"),
    "WoodDark":   ((92, 64, 44), "Wood"),
    "Canvas":     ((222, 214, 196), "Fabric"),
    "TargetRing": ((46, 48, 52), "Fabric"),
    "TargetBull": ((166, 58, 48), "Fabric"),
    "Backstop":   ((50, 56, 58), "Fabric"),
    "Hay":        ((182, 154, 92), "Fabric"),
    "RingMat":    ((66, 82, 92), "Rubber"),
    "Leather":    ((94, 64, 46), "Leather"),
    "Stone":      ((122, 120, 114), "Slate"),
    "Ash":        ((58, 54, 52), "Slate"),
    "Ember":      ((255, 128, 48), "Neon"),
    "Leaf":       ((84, 116, 66), "SmoothPlastic"),
    "LeafDry":    ((138, 116, 70), "SmoothPlastic"),
    "Clay":       ((150, 92, 66), "SmoothPlastic"),
    "Water":      ((64, 98, 110), "Glass"),
    "Rope":       ((168, 140, 96), "Fabric"),
    "ClimbPanel": ((132, 138, 140), "Concrete"),
    "Rubber":     ((34, 36, 38), "Rubber"),
    "Pad":        ((58, 64, 70), "Leather"),
    "Concrete":   ((94, 96, 98), "Concrete"),
    "ConcreteDark": ((60, 62, 64), "Concrete"),
    "PlatEdge":   ((190, 184, 164), "Concrete"),
    "TunnelWall": ((52, 56, 60), "Concrete"),
    "Band":       ((62, 92, 96), "SmoothPlastic"),
    "TunnelEnd":  ((8, 8, 10), "SmoothPlastic"),
    "Oxblood":    ((96, 30, 32), "SmoothPlastic"),
    "RedLamp":    ((255, 60, 48), "Neon"),
    "RedStrip":   ((210, 44, 40), "Neon"),
    "CorrFloor":  ((92, 104, 112), "Metal"),
    "EndCap":     ((10, 10, 12), "SmoothPlastic"),
    "DoorLeafL":  ((88, 28, 30), "SmoothPlastic"),
    "DoorLeafR":  ((88, 28, 30), "SmoothPlastic"),
    "DoorTrimL":  ((120, 126, 132), "Metal"),
    "DoorTrimR":  ((120, 126, 132), "Metal"),
    "ChestBody":  ((70, 80, 86), "Metal"),
    "Lid":        ((70, 80, 86), "Metal"),
    "LidUse":     ((210, 106, 44), "SmoothPlastic"),
    "Stand":      ((52, 56, 60), "Metal"),
    "Col":        ((163, 162, 165), "Plastic"),
}
for _k in range(1, 7):
    ROLES["PlatLamp%d" % _k] = ((255, 228, 196), "Neon")
BURLAP, BURLAP_D, VEST = (156, 128, 90), (126, 102, 74), (92, 100, 90)
R15 = ["Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
       "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg",
       "RightFoot"]
for _n in R15:
    ROLES[_n] = (VEST if _n == "UpperTorso" else (BURLAP_D if _n.endswith(("Hand", "Foot")) else BURLAP), "Fabric")
TRANSPARENCY = {"Water": 0.3}
NO_SHADOW = {"Downlight", "Ember", "RedLamp", "RedStrip", "Water", "Line", "Track", "FloorTile", "UseMat",
             "Screen"} | {"PlatLamp%d" % k for k in range(1, 7)}
PART_TAGS = {}   # (asset, role) -> [tags]


def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin_rgb(rgb):
    return tuple(srgb_to_lin(float(c)) for c in rgb)


def B(p):
    """Roblox (x, y, z) -> Blender (x, -z, y)."""
    return V((p[0], -p[2], p[1]))


def R3(v):
    return [round(v[0], 3), round(v[1], 3), round(v[2], 3)]


def rbx_from_b(v):
    return [round(v[0], 3), round(v[2], 3), round(-v[1], 3)]


# ------------------------------------------------------------------------------------------------ geometry (Roblox space)
class MB:
    def __init__(self):
        self.shells = []    # (verts Blender, faces, closed)
        self.prims = []     # the same shapes as Roblox Part primitives (the Part build of the set, see prim_of)

    def add(self, verts_r, faces, closed=True, loft_n=None):
        self.shells.append(([B(v) for v in verts_r], [tuple(f) for f in faces], closed))
        p = prim_of([V(v) for v in verts_r], faces, closed, loft_n)
        if p:
            self.prims.append(p)


def _r2(x):
    return round(x, 2)


def _obb(vs, e1, e3, min_t=0.0):
    a = e1.normalized()
    b = (e3 - a * e3.dot(a))
    if b.length < 1e-6:
        return None
    b.normalize()
    c = a.cross(b)
    ex = []
    for ax in (a, b, c):
        d = [v.dot(ax) for v in vs]
        ex.append((min(d), max(d)))
    ctr = a * ((ex[0][0] + ex[0][1]) / 2) + b * ((ex[1][0] + ex[1][1]) / 2) + c * ((ex[2][0] + ex[2][1]) / 2)
    size = [max(ex[i][1] - ex[i][0], min_t) for i in range(3)]
    if abs(a.x) > 0.9999 and abs(b.y) > 0.9999:
        return ["A", _r2(ctr.x), _r2(ctr.y), _r2(ctr.z), _r2(size[0]), _r2(size[1]), _r2(size[2])]
    if abs(a.z) > 0.9999 and abs(b.y) > 0.9999:
        return ["A", _r2(ctr.x), _r2(ctr.y), _r2(ctr.z), _r2(size[2]), _r2(size[1]), _r2(size[0])]
    return ["B", _r2(ctr.x), _r2(ctr.y), _r2(ctr.z), _r2(size[0]), _r2(size[1]), _r2(size[2]),
            round(a.x, 4), round(a.y, 4), round(a.z, 4), round(b.x, 4), round(b.y, 4), round(b.z, 4)]


def prim_of(vs, faces, closed, loft_n):
    """One Roblox Part per shape: boxes and hexahedra -> a fitted box (axes from the first edge and the bottom-to-top
    direction), lofts -> a Cylinder part along the loft axis, flat quads -> a thin box, anything else -> its AABB."""
    n = len(vs)
    if loft_n and n >= 2 * loft_n:
        k = loft_n
        c0 = sum(vs[:k], V((0, 0, 0))) / k
        c1 = sum(vs[-k:], V((0, 0, 0))) / k
        ax = c1 - c0
        L = ax.length
        if L < 1e-4:
            return None
        ax.normalize()
        r = max(((v - c0) - ax * (v - c0).dot(ax)).length for v in vs)
        ctr = (c0 + c1) / 2
        return ["C", _r2(ctr.x), _r2(ctr.y), _r2(ctr.z), _r2(L), _r2(2 * r), round(ax.x, 4), round(ax.y, 4),
                round(ax.z, 4)]
    if n == 8 and closed:
        e1 = vs[1] - vs[0]
        e3 = (sum(vs[4:], V((0, 0, 0))) - sum(vs[:4], V((0, 0, 0)))) / 4
        return _obb(vs, e1, e3)
    if n == 4 and not closed:
        e1 = vs[1] - vs[0]
        e2 = vs[3] - vs[0]
        nrm = e1.cross(e2)
        return _obb(vs, e1, nrm, 0.05)
    lo = V((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = V((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (lo + hi) / 2
    s = hi - lo
    return ["A", _r2(c.x), _r2(c.y), _r2(c.z), _r2(s.x), _r2(s.y), _r2(s.z)]


HEX_F = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def M(pos=(0, 0, 0), yaw=0.0, pitch=0.0, roll=0.0):
    """Roblox-space matrix: translate, then yaw about Y, pitch about X, roll about Z (degrees)."""
    return (Matrix.Translation(V(pos)) @ Matrix.Rotation(math.radians(yaw), 4, 'Y') @
            Matrix.Rotation(math.radians(pitch), 4, 'X') @ Matrix.Rotation(math.radians(roll), 4, 'Z'))


def hexa(mb, pts):
    mb.add([V(p) for p in pts], HEX_F)


def box(mb, lo, hi):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    hexa(mb, [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
              (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)])


def cube(mb, m, size, c=(0, 0, 0)):
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    pts = []
    for dy in (-sy, sy):
        for dx, dz in ((-sx, -sz), (sx, -sz), (sx, sz), (-sx, sz)):
            pts.append(m @ V((c[0] + dx, c[1] + dy, c[2] + dz)))
    hexa(mb, pts)


def loft(mb, m, rings, n=8, phase=0.0, cap=True):
    """Rings along local Y: (y, rx, rz). Faceted (flat shaded)."""
    vs, fs = [], []
    for (y, rx, rz) in rings:
        for k in range(n):
            a = phase + TAU * k / n
            vs.append(m @ V((math.cos(a) * rx, y, math.sin(a) * rz)))
    for i in range(len(rings) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            fs.append((i * n + k, i * n + k2, (i + 1) * n + k2, (i + 1) * n + k))
    if cap:
        fs.append(tuple(reversed(range(n))))
        last = (len(rings) - 1) * n
        fs.append(tuple(last + k for k in range(n)))
    mb.add(vs, fs, loft_n=n)


def cyl(mb, m, r, h, n=8, r2=None, phase=None):
    loft(mb, m, [(0.0, r, r), (h, r2 if r2 is not None else r, r2 if r2 is not None else r)], n,
         phase=(math.pi / n if phase is None else phase))


def beam(mb, p0, p1, w, d, up=(0, 1, 0)):
    p0, p1 = V(p0), V(p1)
    ax = (p1 - p0)
    L = ax.length
    ax.normalize()
    u = V(up)
    if abs(ax.dot(u)) > 0.95:
        u = V((1, 0, 0))
    side = ax.cross(u).normalized()
    up2 = side.cross(ax).normalized()
    pts = []
    for t in (0.0, L):
        base = p0 + ax * t
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            pts.append(base + side * (sx * w / 2) + up2 * (sy * d / 2))
    # reorder into the hexa layout (bottom ring at t=0, top ring at t=L)
    hexa(mb, pts)


def quad_up(mb, x0, z0, x1, z1, y):
    """One upward-facing quad (open), x0<x1, z0<z1."""
    mb.add([(x0, y, z0), (x0, y, z1), (x1, y, z1), (x1, y, z0)], [(0, 1, 2, 3)], closed=False)


def strip_up(mb, pts, w, y):
    """A flat painted strip along a 2D polyline (x, z), open quads, upward."""
    n = len(pts)
    for i in range(n - 1):
        a, b = V((pts[i][0], 0, pts[i][1])), V((pts[i + 1][0], 0, pts[i + 1][1]))
        d = (b - a).normalized()
        nrm = V((-d.z, 0, d.x)) * (w / 2)
        q = [a - nrm, a + nrm, b + nrm, b - nrm]
        q = [(p.x, y, p.z) for p in q]
        # make it face +Y
        e1 = V(q[1]) - V(q[0])
        e2 = V(q[2]) - V(q[0])
        if e1.cross(e2).y < 0:
            q = list(reversed(q))
        mb.add(q, [(0, 1, 2, 3)], closed=False)


def prism_xy(mb, m, poly, depth):
    """Polygon in local XY extruded along local +Z from 0 to depth."""
    n = len(poly)
    vs = [m @ V((x, y, 0)) for x, y in poly] + [m @ V((x, y, depth)) for x, y in poly]
    fs = [tuple(range(n)), tuple(n + i for i in reversed(range(n)))]
    for i in range(n):
        j = (i + 1) % n
        fs.append((i, j, n + j, n + i))
    mb.add(vs, fs)


# ------------------------------------------------------------------------------------------------ asset
class Asset:
    def __init__(self, name, kind, notes, pivot="hall floor centre (placed at the hall origin)"):
        self.name, self.kind, self.notes, self.pivot = name, kind, notes, pivot
        self.parts = {}
        self.cols = []
        self.att = {}
        self.placements = [{"position": [0.0, 0.0, 0.0], "yawDeg": 0.0, "name": name}]
        self.extra = {}

    def mb(self, role):
        return self.parts.setdefault(role, MB())

    def col(self, what, lo, hi, tags=None, attrs=None):
        c = [(lo[i] + hi[i]) / 2 for i in range(3)]
        s = [abs(hi[i] - lo[i]) for i in range(3)]
        self.cols.append((what, c, s, 0.0, tags or [], attrs or {}))

    def colm(self, what, c, size, yaw, tags=None, attrs=None):
        self.cols.append((what, list(c), list(size), yaw, tags or [], attrs or {}))

    def mark(self, name, pos, look=(0, 0, -1), up=(0, 1, 0), attrs=None):
        lk = V(look).normalized()
        self.att[name] = (V(pos), lk, V(up).normalized(), attrs or {})


def yaw_for(look):
    """Yaw (deg) that turns the asset's front (-Z) to face `look` (x, z)."""
    return math.degrees(math.atan2(-look[0], -look[1]))


# ================================================================================================ the hall shell
def build_shell():
    a = Asset("TC_HallShell", "Hall",
              "The hall: 220 x 150 x 36 inside. Blue-grey chequered carpet (5-stud squares), teal padded wall panels "
              "leaning in toward the top, white diagonal ribs, a coffered ceiling with 77 round downlights, three arches "
              "in the south wall onto platform B, the north wall's steel door surround with the big screen over it and "
              "two stacks of colour-bar boards. Floor centre = place (8800, 200, 3000).")
    # floor
    box(a.mb("Floor"), (-HX - WALL, -1.0, -HZ - WALL), (HX + WALL, 0.0, HZ + WALL))
    t = 5.0
    nx, nz = int(2 * HX / t), int(2 * HZ / t)
    for i in range(nx):
        for j in range(nz):
            if (i + j) % 2 == 0:
                quad_up(a.mb("FloorTile"), -HX + i * t, -HZ + j * t, -HX + (i + 1) * t, -HZ + (j + 1) * t, 0.015)
    a.col("Floor", (-HX - WALL, -2.0, -HZ - WALL), (HX + WALL, 0.0, HZ + WALL))
    # ceiling, coffers and downlights
    box(a.mb("Ceiling"), (-HX - WALL, HH, -HZ - WALL), (HX + WALL, HH + 2.0, HZ + WALL))
    a.col("Ceiling", (-HX - WALL, HH, -HZ - WALL), (HX + WALL, HH + 2.0, HZ + WALL))
    for k in range(12):
        x = -HX + 20.0 * k
        box(a.mb("CeilBeam"), (x - 0.7, HH - 2.6, -HZ), (x + 0.7, HH, HZ))
    for z in [-HZ + 20.0 * k for k in range(8)] + [HZ]:
        box(a.mb("CeilBeam"), (-HX, HH - 2.6, z - 0.7), (HX, HH, z + 0.7))
    n = 0
    for i, x in enumerate([-100.0 + 20.0 * k for k in range(11)]):
        for j, z in enumerate([-65.0 + 20.0 * k for k in range(7)]):
            cyl(a.mb("Downlight"), M((x, HH - 0.25, z)), 1.0, 0.2, n=10)
            cyl(a.mb("DarkSteel"), M((x, HH - 0.12, z)), 1.4, 0.12, n=10)
            n += 1
            a.mark("Lamp_%02d_%02d" % (i + 1, j + 1), (x, HH - 0.6, z), (0, -1, 0), (0, 0, -1),
                   {"light": (i % 2 == 0 and j % 2 == 0) or (i in (3, 7) and j == 3)})
    a.extra["downlights"] = n

    # walls: slab + skirting + padded panels (lean in at the top) + upper band. openings: north door, south arches.
    north_open = [(-16.0, 16.0)]                     # the steel surround (TC_LaunchDoors) covers x -16..16
    south_open = [(-48.0, -32.0), (-8.0, 8.0), (32.0, 48.0)]

    def segs(lo, hi, opens):
        out, cur = [], lo
        for o0, o1 in sorted(opens):
            if o0 > cur:
                out.append((cur, o0))
            cur = max(cur, o1)
        if cur < hi:
            out.append((cur, hi))
        return out

    # north (z = -HZ, face +z), south (z = +HZ, face -z), west (x = -HX, face +x), east (x = +HX, face -x)
    walls = [("N", -1), ("S", 1), ("W", -1), ("E", 1)]
    for wn, sgn in walls:
        along_x = wn in ("N", "S")
        L = HX if along_x else HZ
        opens = north_open if wn == "N" else (south_open if wn == "S" else [])
        if along_x:
            zf = sgn * HZ          # inner face
            # slab: with real openings for the door (8 x 14) and the arches (16 x 18)
            if wn == "N":
                holes = [(-4.0, 4.0, 14.0)]
            else:
                holes = [(o0, o1, 18.0) for o0, o1 in south_open]
            z0, z1 = (zf - WALL, zf) if sgn < 0 else (zf, zf + WALL)
            for s0, s1 in segs(-HX - WALL, HX + WALL, [(h0, h1) for h0, h1, _ in holes]):
                box(a.mb("PanelBack"), (s0, 0.0, z0), (s1, HH, z1))
                a.col("Wall%s_%d" % (wn, int(s0)), (s0, 0.0, z0 - (0.5 if sgn > 0 else 0)), (s1, HH, z1 + (0.5 if sgn < 0 else 0)))
            for h0, h1, hh in holes:
                box(a.mb("PanelBack"), (h0, hh, z0), (h1, HH, z1))
                a.col("Wall%sTop_%d" % (wn, int(h0)), (h0, hh, z0), (h1, HH, z1))
        else:
            xf = sgn * HX
            x0, x1 = (xf - WALL, xf) if sgn < 0 else (xf, xf + WALL)
            box(a.mb("PanelBack"), (x0, 0.0, -HZ - WALL), (x1, HH, HZ + WALL))
            a.col("Wall%s" % wn, (x0 - (0.5 if sgn > 0 else 0), 0.0, -HZ - WALL), (x1 + (0.5 if sgn < 0 else 0), HH, HZ + WALL))
        # panels along the inner face, 8-stud modules
        for s0, s1 in segs(-L, L, opens):
            k = int(math.floor((s1 - s0) / 8.0 + 1e-6))
            if k <= 0:
                continue
            w = (s1 - s0) / k
            for i in range(k):
                c0, c1 = s0 + i * w + 0.25, s0 + (i + 1) * w - 0.25
                inward = -sgn          # direction into the hall along the wall normal
                if along_x:
                    zf = sgn * HZ
                    def P(u, y, d):
                        return (u, y, zf + inward * d)
                else:
                    xf = sgn * HX
                    def P(u, y, d):
                        return (xf + inward * d, y, u)
                y0, y1 = 3.2, 29.6
                pts = [P(c0, y0, 0.0), P(c1, y0, 0.0), P(c1, y0, 0.55), P(c0, y0, 0.55),
                       P(c0, y1, 0.0), P(c1, y1, 0.0), P(c1, y1, 1.35), P(c0, y1, 1.35)]
                hexa(a.mb("Panel"), pts)
            # skirting and upper band
            if along_x:
                zf = sgn * HZ
                zz = (zf, zf - sgn * 0.35)
                box(a.mb("Skirting"), (s0, 0.0, min(zz)), (s1, 3.0, max(zz)))
                zz = (zf, zf - sgn * 0.6)
                box(a.mb("Skirting"), (s0, 30.0, min(zz)), (s1, 31.0, max(zz)))
            else:
                xf = sgn * HX
                xx = (xf, xf - sgn * 0.35)
                box(a.mb("Skirting"), (min(xx), 0.0, s0), (max(xx), 3.0, s1))
                xx = (xf, xf - sgn * 0.6)
                box(a.mb("Skirting"), (min(xx), 30.0, s0), (max(xx), 31.0, s1))
    # ribs: white diagonal beams standing off the panels
    ribs = {"N": [-100, -76, -52, 52, 76], "S": [-100, -76, 64, 88], "W": [-66, -42, -18, 6],
            "E": [-66, -42, -18, 6, 30, 54]}
    for wn, us in ribs.items():
        for u in us:
            if wn in ("N", "S"):
                zf = (-HZ + 1.8) if wn == "N" else (HZ - 1.8)
                beam(a.mb("Rib"), (u, 1.0, zf), (u + 13.0, 31.0, zf), 1.1, 0.9, up=(0, 0, 1))
            else:
                xf = (-HX + 1.8) if wn == "W" else (HX - 1.8)
                beam(a.mb("Rib"), (xf, 1.0, u), (xf, 31.0, u + 13.0), 1.1, 0.9, up=(1, 0, 0))
    # arches: white trim around each opening + spandrels that make the arch head (spring 12, crown 18)
    for o0, o1 in south_open:
        cx = (o0 + o1) / 2
        hw = (o1 - o0) / 2
        poly_l = [(-hw, 12.0)]
        for k in range(1, 6):
            a_ = math.pi - (math.pi / 2) * k / 6
            poly_l.append((math.cos(a_) * hw, 12.0 + math.sin(a_) * 6.0))
        poly_l += [(0.0, 18.0), (-hw, 18.0)]
        poly_r = [(-x, y) for x, y in reversed(poly_l)]
        for poly in (poly_l, poly_r):
            prism_xy(a.mb("PanelBack"), M((cx, 0, HZ)), poly, WALL)
        # trim: jambs + the arch ring (inside face)
        for s in (-1, 1):
            box(a.mb("Trim"), (cx + s * hw - (0.7 if s > 0 else 0), 0.0, HZ - 0.5), (cx + s * hw + (0.7 if s < 0 else 0), 12.0, HZ + WALL + 0.3))
        pts = [(math.cos(math.pi - math.pi * k / 10) * hw, 12.0 + math.sin(math.pi - math.pi * k / 10) * 6.0) for k in range(11)]
        for k in range(10):
            p0 = (cx + pts[k][0], pts[k][1], HZ - 0.2)
            p1 = (cx + pts[k + 1][0], pts[k + 1][1], HZ - 0.2)
            beam(a.mb("Trim"), p0, p1, 0.7, 0.8, up=(0, 0, 1))
        a.mark("Arch_%d" % (south_open.index((o0, o1)) + 1), (cx, 0.0, HZ), (0, 0, -1))
    # big screen over the launch doors (its face: TC_LaunchDoors covers x -16..16 up to 17; screen sits above)
    box(a.mb("Frame"), (-15.5, 17.5, -HZ), (15.5, 28.5, -HZ + 0.6))
    box(a.mb("Screen"), (-14.8, 18.2, -HZ + 0.6), (14.8, 27.8, -HZ + 0.7))
    a.mark("BigScreen", (0.0, 23.0, -HZ + 0.72), (0, 0, 1), (0, 1, 0), {"size": [29.6, 9.6]})
    # two stacks of colour-bar boards
    cols = ["BarTeal", "BarOchre", "BarSlate", "BarRose", "BarSage", "BarSlate"]
    for s in (-1, 1):
        cx = s * 30.0
        for k in range(6):
            y = 15.5 + k * 2.3
            box(a.mb("Frame"), (cx - 7.5, y, -HZ), (cx + 7.5, y + 2.0, -HZ + 0.7))
            box(a.mb(cols[(k + (s > 0)) % 6]), (cx - 7.0, y + 0.3, -HZ + 0.7), (cx - 7.0 + (9.5 + (k * 7 % 4)), y + 1.7, -HZ + 0.8))
            box(a.mb("Line"), (cx + 3.4, y + 0.6, -HZ + 0.7), (cx + 6.8, y + 1.4, -HZ + 0.78))
    # low padded partitions between the bays (3 high)
    for (x0, z0, x1, z1) in [(-110, -20.5, -58, -19.5), (-110, 29.5, -58, 30.5), (58, -35.5, 110, -34.5)]:
        box(a.mb("Panel"), (x0, 0.0, z0), (x1, 3.0, z1))
        box(a.mb("Skirting"), (x0, 3.0, z0 - 0.1), (x1, 3.25, z1 + 0.1))
        a.col("Partition_%d_%d" % (x0, z0), (x0, 0.0, z0), (x1, 3.25, z1))
    return a


# ================================================================================================ platform B
def build_platform():
    a = Asset("TC_Platform", "Station",
              "Platform B, where train copy B stands: a dark covered platform 300 long beside the hall's south wall, "
              "level with the train floor (y 0). The three arches lead up into the hall. Lamp banks PlatLamp1..6 "
              "(Neon) switch on bank by bank as the train stops. The track pit, the guideway (top y -3.4, the train's "
              "skirt bottom) and a tunnel portal at both ends (the tunnel stubs end in black).")
    z0, ze, zb = HZ, 86.6, 112.0       # platform from the hall's south wall to its edge; back wall at zb
    xL = 150.0
    box(a.mb("Concrete"), (-xL, -6.0, z0), (xL, 0.0, ze))
    a.col("Platform", (-xL, -6.0, z0), (xL, 0.0, ze))
    quad_up(a.mb("PlatEdge"), -xL, ze - 1.4, xL, ze - 0.4, 0.02)
    box(a.mb("ConcreteDark"), (-xL, -0.7, ze - 0.4), (xL, 0.0, ze))
    # pit + guideway
    box(a.mb("ConcreteDark"), (-xL, -7.0, ze), (xL, -6.0, zb))
    a.col("PitFloor", (-xL, -8.0, ze), (xL, -6.0, zb))
    box(a.mb("DarkSteel"), (-xL - 26, -6.0, 95.5), (xL + 26, -3.4, 99.5))
    for x in range(-144, 150, 12):
        box(a.mb("Steel"), (x - 0.6, -6.0, 93.8), (x + 0.6, -5.2, 101.2))
    a.col("Guideway", (-xL, -6.0, 95.5), (xL, -3.4, 99.5))
    # back wall with pilasters and a teal band
    box(a.mb("TunnelWall"), (-xL - 2, -7.0, zb), (xL + 2, 24.0, zb + 2))
    a.col("BackWall", (-xL - 2, -8.0, zb), (xL + 2, 24.0, zb + 2))
    box(a.mb("Band"), (-xL, 9.0, zb - 0.3), (xL, 10.6, zb))
    for x in range(-144, 150, 24):
        box(a.mb("ConcreteDark"), (x - 0.9, -6.0, zb - 0.6), (x + 0.9, 24.0, zb))
    # the platform's north wall beyond the hall + roof
    for s in (-1, 1):
        xa, xb_ = sorted((s * (HX + WALL), s * (xL + 2)))
        box(a.mb("TunnelWall"), (xa, 0.0, z0 - WALL), (xb_, 24.0, z0))
        a.col("NorthWall%s" % ("E" if s > 0 else "W"), (xa, 0.0, z0 - WALL), (xb_, 24.0, z0))
    # the platform face of the north wall: teal band, pilasters every 24, colour-bar boards beside the arches,
    # a wall bench between pilasters
    zw = z0 + 0.4
    box(a.mb("Band"), (-xL, 9.0, z0), (xL, 10.6, zw))
    box(a.mb("Skirting"), (-xL, 0.0, z0), (xL, 1.2, z0 + 0.3))
    arch_x = (-48.0, -32.0, -8.0, 8.0, 32.0, 48.0)
    for x in range(-144, 150, 24):
        if any(arch_x[i] - 1 <= x <= arch_x[i + 1] + 1 for i in (0, 2, 4)):
            continue
        box(a.mb("ConcreteDark"), (x - 0.9, 0.0, z0), (x + 0.9, 24.0, z0 + 0.7))
    for x in (-128.0, -104.0, -80.0, 80.0, 104.0, 128.0):
        box(a.mb("Wood"), (x - 4.0, 1.6, z0 + 0.3), (x + 4.0, 1.9, z0 + 1.9))
        box(a.mb("DarkSteel"), (x - 3.4, 0.0, z0 + 0.3), (x + 3.4, 1.6, z0 + 1.4))
        a.col("WallBench_%d" % int(x), (x - 4.0, 0.0, z0), (x + 4.0, 1.9, z0 + 1.9))
    bars = ["BarTeal", "BarOchre", "BarSlate", "BarSage"]
    for i, x in enumerate((-64.0, 64.0, -116.0, 116.0)):
        for k in range(3):
            y = 12.5 + k * 2.2
            box(a.mb("Frame"), (x - 6.0, y, z0), (x + 6.0, y + 1.9, z0 + 0.6))
            box(a.mb(bars[(i + k) % 4]), (x - 5.6, y + 0.3, z0 + 0.6), (x - 5.6 + 7.0 + (k * 3 % 4), y + 1.6, z0 + 0.7))
    box(a.mb("Ceiling"), (-xL - 2, 24.0, z0 - WALL), (xL + 2, 26.0, zb + 2))
    a.col("Roof", (-xL - 2, 24.0, z0 - WALL), (xL + 2, 26.0, zb + 2))
    for x in range(-144, 150, 24):
        box(a.mb("DarkSteel"), (x - 0.5, 22.6, z0), (x + 0.5, 24.0, zb))
    # end walls with portals (opening z 87..108, y -6..18) and tunnel stubs
    for s in (-1, 1):
        xa, xb_ = sorted((s * xL, s * (xL + 2)))
        for (za, zz, ya, yb) in [(z0 - WALL, 87.0, -7.0, 24.0), (108.0, zb + 2, -7.0, 24.0), (87.0, 108.0, 18.0, 24.0)]:
            box(a.mb("TunnelWall"), (xa, ya, za), (xb_, yb, zz))
            a.col("End%s_%d" % ("E" if s > 0 else "W", int(za)), (xa, ya, za), (xb_, yb, zz))
        # portal frame (lighter concrete), on the platform side
        xi = s * xL
        xa2, xb2 = sorted((xi, xi - s * 0.6))
        box(a.mb("Concrete"), (xa2, -6.0, 85.8), (xb2, 19.0, 87.0))
        box(a.mb("Concrete"), (xa2, -6.0, 108.0), (xb2, 19.0, 109.2))
        box(a.mb("Concrete"), (xa2, 18.0, 85.8), (xb2, 19.4, 109.2))
        # tunnel stub
        xt0, xt1 = sorted((s * (xL + 2), s * (xL + 28)))
        box(a.mb("TunnelWall"), (xt0, -7.0, 85.0), (xt1, 19.0, 87.0))
        box(a.mb("TunnelWall"), (xt0, -7.0, 108.0), (xt1, 19.0, 110.0))
        box(a.mb("TunnelWall"), (xt0, 18.0, 85.0), (xt1, 20.0, 110.0))
        box(a.mb("ConcreteDark"), (xt0, -8.0, 85.0), (xt1, -6.0, 110.0))
        xe0, xe1 = sorted((s * (xL + 28), s * (xL + 29)))
        box(a.mb("TunnelEnd"), (xe0, -8.0, 85.0), (xe1, 20.0, 110.0))
        a.col("Tunnel%s" % ("E" if s > 0 else "W"), (xe0, -8.0, 85.0), (xe1, 20.0, 110.0))
        a.mark("TunnelMouth%s" % ("E" if s > 0 else "W"), (s * xL, 0.0, 97.5), (s, 0, 0))
    # lamp banks over the platform
    for k, xc in enumerate([-125, -75, -25, 25, 75, 125]):
        box(a.mb("DarkSteel"), (xc - 20.5, 23.2, 79.6), (xc + 20.5, 24.0, 83.4))
        box(a.mb("PlatLamp%d" % (k + 1)), (xc - 20.0, 22.8, 80.4), (xc + 20.0, 23.2, 82.6))
        for j, dx in enumerate((-12.0, 0.0, 12.0)):
            a.mark("PlatLamp_%d_%d" % (k + 1, j + 1), (xc + dx, 22.4, 81.5), (0, -1, 0), (0, 0, -1), {"bank": k + 1})
    # spawns on the platform (join during Training): 2 rows x 24, facing the hall (north)
    n = 0
    for z in (79.5, 83.0):
        for i in range(24):
            n += 1
            a.mark("Spawn_%02d" % n, (-92.0 + i * 8.0, 0.0, z), (0, 0, -1))
    # train copy B: the lounge car's floor centre; the nose points east (+X); the platform is on the train's left
    a.mark("TrainB", (36.5, 0.0, 97.5), (1, 0, 0), (0, 1, 0),
           {"yawDeg": -90.0, "note": "BlenderTemplates.TRAIN_AT equivalent for copy B: CFrame.new(hall * (36.5, 0, 97.5)) "
                                     "* CFrame.Angles(0, rad(-90), 0); the side doors open on the north side"})
    return a


# ================================================================================================ stations
def target_stand(a, c, face=(0, 0, 1), board_h=4.6, r=2.2):
    """Orange stand + round canvas board; the board faces `face` (toward the shooters)."""
    yaw = yaw_for((-face[0], -face[2]))   # the board's back (-Z local) points away from the shooter
    m = M(c, yaw)
    use = a.mb("Use")
    for s in (-1, 1):
        beam(use, m @ V((s * 1.3, 0.0, 0.6)), m @ V((s * 0.5, board_h, 0.25)), 0.3, 0.3)
        beam(use, m @ V((s * 1.3, 0.0, -0.9)), m @ V((s * 0.5, board_h - 0.5, 0.15)), 0.25, 0.25)
    cube(use, m, (3.2, 0.25, 0.4), (0, 0.6, 0.0))
    mf = m @ M((0, board_h, 0.35), 0, 90)          # local Y -> +Z (toward the shooter)
    cyl(a.mb("Canvas"), mf, r, 0.35, n=12)
    cyl(a.mb("TargetRing"), mf @ M((0, 0.35, 0)), r * 0.68, 0.04, n=12)
    cyl(a.mb("Canvas"), mf @ M((0, 0.39, 0)), r * 0.5, 0.04, n=12)
    cyl(a.mb("TargetBull"), mf @ M((0, 0.43, 0)), r * 0.24, 0.04, n=10)


def mat_(a, role, name, c, size, kit=None, station=None):
    x, z = c
    box(a.mb(role), (x - size[0] / 2, 0.0, z - size[1] / 2), (x + size[0] / 2, 0.12, z + size[1] / 2))
    attrs = {"size": [size[0], 0.12, size[1]]}
    if kit:
        attrs["kit"] = kit
    if station:
        attrs["station"] = station
    a.mark(name, (x, 0.12, z), (0, 0, -1), (0, 1, 0), attrs)


def build_archery():
    a = Asset("TC_Archery", "Station",
              "Archery lanes: 6 lanes 8 wide (x 48..96), the shooting line at z 66, pop-up targets on orange stands at "
              "20, 40 and 60 studs (z 46, 26, 6), a padded backstop at z -8. Each target board has a TrainingTarget "
              "collider (attributes Lane, Distance). The Archer mat and the station chest stand east of the line.")
    lanes = [52.0 + 8.0 * k for k in range(6)]
    for k in range(7):
        x = 48.0 + 8.0 * k
        strip_up(a.mb("Line"), [(x, 70.0), (x, -8.0)], 0.25, 0.03)
    strip_up(a.mb("Use"), [(47.0, 66.0), (97.0, 66.0)], 0.6, 0.035)
    # waist rail at the line with dividers
    box(a.mb("Steel"), (47.5, 3.0, 67.6), (96.5, 3.3, 67.9))
    for k in range(7):
        x = 48.0 + 8.0 * k
        box(a.mb("Steel"), (x - 0.15, 0.0, 67.55), (x + 0.15, 3.3, 67.95))
        box(a.mb("Pad"), (x - 0.2, 0.0, 67.8), (x + 0.2, 2.2, 71.5))
    a.col("Rail", (47.5, 0.0, 67.5), (96.5, 3.3, 68.0))
    for i, x in enumerate(lanes):
        for d, z in ((20, 46.0), (40, 26.0), (60, 6.0)):
            target_stand(a, (x, 0.0, z), (0, 0, 1))
            a.colm("Target_L%d_%d" % (i + 1, d), (x, 4.6, z + 0.5), (4.6, 4.6, 0.8), 0.0, ["TrainingTarget"],
                   {"Station": "Archery", "Lane": i + 1, "Distance": d})
            a.mark("Target_L%d_%d" % (i + 1, d), (x, 4.6, z + 0.8), (0, 0, 1), (0, 1, 0), {"lane": i + 1, "distance": d})
    # backstop: padded bays between dark posts (10 high), a canvas strip at eye height per lane
    for k in range(6):
        x0 = 48.0 + 8.0 * k
        hexa(a.mb("Backstop"), [(x0 + 0.3, 0.0, -9.0), (x0 + 7.7, 0.0, -9.0), (x0 + 7.7, 0.0, -8.0), (x0 + 0.3, 0.0, -8.0),
                                (x0 + 0.3, 10.0, -9.0), (x0 + 7.7, 10.0, -9.0), (x0 + 7.7, 10.0, -8.6), (x0 + 0.3, 10.0, -8.6)])
        box(a.mb("Panel"), (x0 + 0.6, 3.0, -8.2), (x0 + 7.4, 6.0, -7.9))
    for x in range(48, 100, 8):
        box(a.mb("DarkSteel"), (x - 0.35, 0.0, -9.4), (x + 0.35, 10.6, -8.4))
    box(a.mb("DarkSteel"), (47.6, 10.0, -9.4), (96.4, 10.6, -8.2))
    a.col("Backstop", (47.6, 0.0, -9.4), (96.4, 10.6, -7.9))
    mat_(a, "UseMat", "Mat_Archer", (103.0, 70.0), (8.0, 6.0), kit="Archer", station="Archery")
    a.mark("Chest_Archery", (104.0, 0.0, 58.0), (-1, 0, 0), (0, 1, 0), {"station": "Archery"})
    a.mark("Station_Archery", (72.0, 0.0, 70.0), (0, 0, -1), (0, 1, 0), {"drill": "4 hits from 6 targets in 30 s"})
    return a


def build_spear():
    a = Asset("TC_SpearRange", "Station",
              "Spear and throwing range: the throw line at x 52 (orange), throwing boards at 10..50 studs (x 62..102) "
              "facing the thrower, two orange spear racks, hay bales as a backstop on the east wall. The Hunter mat.")
    strip_up(a.mb("Use"), [(52.0, -72.0), (52.0, -38.0)], 0.6, 0.035)
    for d, z in ((10, -62.0), (20, -46.0), (30, -58.0), (40, -44.0), (50, -54.0)):
        x = 52.0 + d
        m = M((x, 0, z), 90.0)         # front (-Z local) faces -X (the thrower)
        cube(a.mb("Wood"), m, (3.4, 5.0, 0.6), (0, 4.4, 0))
        for s in (-1, 1):
            cube(a.mb("WoodDark"), m, (0.4, 6.9, 0.4), (s * 1.2, 3.45, 0.5))
            beam(a.mb("WoodDark"), m @ V((s * 1.2, 0.0, 2.2)), m @ V((s * 1.2, 4.0, 0.7)), 0.3, 0.3)
        mf = m @ M((0, 4.6, -0.3), 0, -90)
        cyl(a.mb("TargetRing"), mf, 1.25, 0.04, n=10)
        cyl(a.mb("Canvas"), mf @ M((0, 0.04, 0)), 0.85, 0.04, n=10)
        cyl(a.mb("TargetBull"), mf @ M((0, 0.08, 0)), 0.4, 0.04, n=8)
        a.colm("Board_%d" % d, (x, 4.4, z), (0.8, 5.0, 3.4), 0.0, ["TrainingTarget"],
               {"Station": "Spear", "Distance": d})
        a.mark("Board_%d" % d, (x - 0.4, 4.6, z), (-1, 0, 0), (0, 1, 0), {"distance": d})
    rnd = random.Random(SEED + 3)
    for i, z in enumerate((-71.0, -64.0, -57.0, -50.0, -43.0)):
        for lvl in range(2):
            yaw = rnd.uniform(-3, 3)
            cube(a.mb("Hay"), M((107.0, 1.25 + lvl * 2.5, z), yaw), (3.6, 2.5, 6.6))
            for s in (-1.6, 1.6):
                cube(a.mb("Rope"), M((107.0, 1.25 + lvl * 2.5, z + s), yaw), (3.7, 2.56, 0.18))
    a.col("Bales", (105.2, 0.0, -74.5), (108.8, 5.0, -39.5))
    for k, z in enumerate((-72.0, -38.5)):
        m = M((45.5, 0, z), 90.0)
        use = a.mb("Use")
        for s in (-1, 1):
            beam(use, m @ V((s * 2.2, 0.0, -0.9)), m @ V((s * 2.2, 4.6, 0.0)), 0.3, 0.3)
            beam(use, m @ V((s * 2.2, 0.0, 0.9)), m @ V((s * 2.2, 4.6, 0.0)), 0.3, 0.3)
        beam(use, m @ V((-2.4, 4.4, 0.0)), m @ V((2.4, 4.4, 0.0)), 0.3, 0.3)
        beam(use, m @ V((-2.4, 1.0, -0.5)), m @ V((2.4, 1.0, -0.5)), 0.25, 0.25)
        for j in range(4):
            xx = -1.5 + j
            base = m @ V((xx, 0.0, -0.9))
            top = m @ V((xx + 0.1, 7.0, 0.35))
            beam(a.mb("Wood"), base, top, 0.16, 0.16)
            d = (top - base).normalized()
            beam(a.mb("Steel"), top, top + d * 0.9, 0.22, 0.08)
        a.colm("Rack%d" % (k + 1), (45.5, 2.4, z), (2.0, 4.8, 5.0), 0.0)
    mat_(a, "UseMat", "Mat_Hunter", (46.0, -56.0), (6.0, 8.0), kit="Hunter", station="Spear")
    a.mark("Chest_Spear", (46.0, 0.0, -46.0), (1, 0, 0), (0, 1, 0), {"station": "Spear"})
    a.mark("Station_Spear", (50.0, 0.0, -55.0), (1, 0, 0), (0, 1, 0), {"drill": "3 hits from 5 throws at 20 or more"})
    return a


def build_blade():
    a = Asset("TC_BladeRing", "Station",
              "Blade and axe circle: a padded ring r 14 centred (-75, 7.5) with a cream rim, four dummy stands at r 8 "
              "(Dummy_Target N, Dummy_Blocker E, Dummy_Parrier S, Dummy_Striker W, each facing the centre), a spinning "
              "post with two padded arms, and an orange weapon cart with the five blades on show.")
    cx, cz = -75.0, 7.5
    cyl(a.mb("Line"), M((cx, 0.0, cz)), 14.6, 0.22, n=24)
    cyl(a.mb("RingMat"), M((cx, 0.0, cz)), 14.0, 0.3, n=24)
    a.col("Ring", (cx - 14, -0.5, cz - 14), (cx + 14, 0.3, cz + 14))
    for name, (dx, dz) in (("Target", (0, -8)), ("Blocker", (8, 0)), ("Parrier", (0, 8)), ("Striker", (-8, 0))):
        p = (cx + dx, 0.3, cz + dz)
        a.mark("Dummy_" + name, p, (-dx, 0, -dz), (0, 1, 0), {"role": name})
    # spinning post
    m = M((-100.0, 0.0, 22.0))
    cyl(a.mb("DarkSteel"), m, 1.6, 0.4, n=8)
    cyl(a.mb("Steel"), m, 0.35, 6.2, n=8)
    for h, yaw in ((3.0, 0.0), (4.6, 60.0)):
        cyl(a.mb("DarkSteel"), M((-100.0, h - 0.3, 22.0)), 0.6, 0.6, n=8)
        cube(a.mb("Leather"), M((-100.0, h, 22.0), yaw), (7.0, 0.6, 0.6))
        for s in (-1, 1):
            cube(a.mb("Leather"), M((-100.0, h, 22.0), yaw), (1.4, 0.9, 0.9), (s * 3.2, 0, 0))
    a.colm("SpinPost", (-100.0, 3.1, 22.0), (1.2, 6.2, 1.2), 0.0)
    a.mark("SpinPost", (-100.0, 3.8, 22.0), (0, 0, -1), (0, 1, 0), {"spinAxis": "Y", "arms": ["Leather"]})
    # weapon cart (orange frame, two dark shelves, four wheels), its blades on show
    m = M((-50.0, 0.0, 22.0), -90.0)
    use = a.mb("Use")
    for sx in (-2.6, 2.6):
        for sz in (-1.1, 1.1):
            cube(use, m, (0.25, 4.6, 0.25), (sx, 3.0, sz))
            cyl(a.mb("Rubber"), m @ M((sx, 0.35, sz), 0, 0, 90), 0.35, 0.3, n=8)
    for y in (1.2, 3.0, 5.2):
        cube(use, m, (5.5, 0.2, 2.5), (0, y, 0))
    for y in (1.35, 3.15):
        cube(a.mb("WoodDark"), m, (5.2, 0.12, 2.2), (0, y, 0))
    blades = [(-1.8, 0.9, 0.12, 1.4), (-0.7, 1.6, 0.14, 2.3), (0.5, 1.2, 0.2, 2.0), (1.8, 2.2, 0.16, 3.4)]
    for bx, bl, bw, tl in blades:
        cube(a.mb("Wood"), m, (0.18, 0.14, 0.9), (bx, 3.32, 0.6))
        cube(a.mb("Steel"), m, (bw * 2.2, 0.06, bl), (bx, 3.3, 0.6 - 0.45 - bl / 2))
    cube(a.mb("Wood"), m, (0.18, 0.18, 2.4), (0.0, 1.52, 0.0))
    cube(a.mb("Steel"), m, (0.12, 0.9, 0.9), (0.0, 1.9, -1.0))
    cube(a.mb("Steel"), m, (0.12, 0.9, 0.9), (0.0, 1.9, -0.2))
    a.colm("Cart", (-50.0, 2.6, 22.0), (2.6, 5.3, 5.6), 0.0)
    a.mark("Chest_Blade", (-50.0, 0.0, -10.0), (1, 0, 0), (0, 1, 0), {"station": "Blade"})
    a.mark("Station_Blade", (-58.0, 0.0, 7.5), (-1, 0, 0), (0, 1, 0),
           {"drill": "8 clean hits on the blocker and parrier, block or parry 2 of the striker's blows, in 25 s"})
    return a


def stone(mb, rnd, c, r):
    rings = []
    for y, f in ((0.0, 1.0), (r * 0.55, 1.05), (r * 0.95, 0.65)):
        rings.append((y, r * f * rnd.uniform(0.85, 1.1), r * f * rnd.uniform(0.7, 1.0)))
    loft(mb, M(c, rnd.uniform(0, 360)), rings, n=6, phase=rnd.uniform(0, 1))


def build_survival():
    a = Asset("TC_Survival", "Station",
              "Survival corner: a stone fire pit with logs (hold E at FirePit), three snare stakes with cord loops, a "
              "plant table with six pots (three sound, three spoiled: never poisonous), a wooden trough with water, "
              "the bandage dummy's stand. Forager and Medic mats.")
    rnd = random.Random(SEED + 7)
    fx, fz = -88.0, -52.0
    for k in range(9):
        ang = TAU * k / 9
        stone(a.mb("Stone"), rnd, (fx + math.cos(ang) * 2.7, 0.0, fz + math.sin(ang) * 2.7), rnd.uniform(0.7, 0.95))
    cyl(a.mb("Ash"), M((fx, 0.0, fz)), 2.2, 0.12, n=9)
    for k in range(3):
        ang = 60 * k + 15
        m = M((fx, 0.45, fz), ang, 0, 90)
        cyl(a.mb("WoodDark"), m @ M((0, -1.6, 0)), 0.32, 3.2, n=6)
    cube(a.mb("Ember"), M((fx, 0.15, fz), 20), (1.4, 0.25, 1.2))
    a.col("FirePit", (fx - 3.6, 0.0, fz - 3.6), (fx + 3.6, 1.2, fz + 3.6))
    a.mark("FirePit", (fx, 0.6, fz), (0, 1, 0), (0, 0, -1), {"prompt": "Light the fire", "holdSeconds": 2})
    # snares
    for i, (x, z) in enumerate(((-100.0, -30.0), (-94.0, -27.0), (-104.0, -25.0))):
        cyl(a.mb("WoodDark"), M((x, 0.0, z)), 0.18, 1.8, n=5, r2=0.05)
        for k in range(6):
            a0, a1 = TAU * k / 6, TAU * (k + 1) / 6
            beam(a.mb("Rope"), (x + 0.6 + math.cos(a0) * 0.55, 0.08, z + math.sin(a0) * 0.55),
                 (x + 0.6 + math.cos(a1) * 0.55, 0.08, z + math.sin(a1) * 0.55), 0.08, 0.08)
        beam(a.mb("Rope"), (x, 1.3, z), (x + 0.6, 0.1, z), 0.07, 0.07)
        a.mark("Snare_%d" % (i + 1), (x, 0.0, z), (0, 0, -1))
    # plant table with six pots
    tx, tz = -64.0, -66.0
    cube(a.mb("Wood"), M((tx, 0, tz)), (11.0, 0.3, 3.2), (0, 2.6, 0))
    for sx in (-5.0, 5.0):
        for sz in (-1.3, 1.3):
            cube(a.mb("WoodDark"), M((tx, 0, tz)), (0.3, 2.6, 0.3), (sx, 1.3, sz))
    a.col("PlantTable", (tx - 5.5, 0.0, tz - 1.6), (tx + 5.5, 2.75, tz + 1.6))
    for k in range(6):
        px = tx - 4.5 + k * 1.8
        cyl(a.mb("Clay"), M((px, 2.75, tz)), 0.55, 0.9, n=8, r2=0.7)
        good = k % 2 == 0
        role = "Leaf" if good else "LeafDry"
        for j in range(4):
            yaw = j * 90 + rnd.uniform(-20, 20)
            tilt = rnd.uniform(18, 34) if good else rnd.uniform(55, 75)
            cube(a.mb(role), M((px, 3.55, tz), yaw, tilt), (0.5, 1.5 if good else 1.1, 0.12), (0, 0.65, 0))
        a.mark("Plant_%d" % (k + 1), (px, 3.6, tz), (0, 0, 1), (0, 1, 0), {"sound": good})
    # trough
    gx, gz = -64.0, -44.0
    w, d, h = 10.0, 2.8, 2.2
    cube(a.mb("Wood"), M((gx, 0, gz)), (w, 0.3, d), (0, 0.45, 0))
    for s in (-1, 1):
        cube(a.mb("Wood"), M((gx, 0, gz)), (w, h - 0.3, 0.3), (0, 0.3 + (h - 0.3) / 2, s * (d / 2 - 0.15)))
        cube(a.mb("Wood"), M((gx, 0, gz)), (0.3, h - 0.3, d), (s * (w / 2 - 0.15), 0.3 + (h - 0.3) / 2, 0))
        cube(a.mb("WoodDark"), M((gx, 0, gz)), (0.5, 0.3, d + 0.4), (s * (w / 2 - 1.0), 0.15, 0))
    cube(a.mb("Water"), M((gx, 0, gz)), (w - 0.6, 0.08, d - 0.6), (0, h - 0.5, 0))
    a.col("Trough", (gx - w / 2, 0.0, gz - d / 2), (gx + w / 2, h, gz + d / 2))
    a.mark("Trough", (gx, h - 0.4, gz), (0, 1, 0), (0, 0, -1), {"prompt": "Fill the bottle"})
    a.mark("BandageDummy", (-82.0, 0.0, -34.0), (1, 0, 0), (0, 1, 0), {"role": "Bandage"})
    mat_(a, "UseMat", "Mat_Forager", (-64.0, -57.0), (8.0, 4.0), kit="Forager", station="Survival")
    mat_(a, "UseMat", "Mat_Medic", (-74.0, -34.0), (4.0, 6.0), kit="Medic", station="Survival")
    a.mark("Chest_Survival", (-46.0, 0.0, -64.0), (1, 0, 0), (0, 1, 0), {"station": "Survival"})
    a.mark("Station_Survival", (-56.0, 0.0, -50.0), (-1, 0, 0), (0, 1, 0), {"drill": "fire, bottle, plants, bandage in 45 s"})
    return a


def build_fitness():
    a = Asset("TC_Fitness", "Station",
              "Fitness corner: a climbing wall 30 wide x 24 high against the west wall (orange holds; its collider is "
              "tagged Climbable), four exercise bikes with orange frames, a weight rack with a padded bench, a "
              "climbing rope from the ceiling. The Climber mat in front of the wall.")
    rnd = random.Random(SEED + 11)
    x0, x1, za, zb, H = -107.6, -106.0, 38.0, 68.0, 24.0
    box(a.mb("ClimbPanel"), (x0, 0.0, za), (x1, H, zb))
    for z in (za - 0.4, zb):
        box(a.mb("DarkSteel"), (x0 - 0.2, 0.0, z), (x1 + 0.3, H + 0.4, z + 0.4))
    box(a.mb("DarkSteel"), (x0 - 0.2, H, za - 0.4), (x1 + 0.3, H + 0.4, zb + 0.4))
    for y in range(4, int(H), 4):
        box(a.mb("DarkSteel"), (x1, y - 0.05, za), (x1 + 0.05, y + 0.05, zb))
    a.col("ClimbWall", (x0, 0.0, za), (x1, H + 0.4, zb), ["Climbable"])
    holds = 0
    for route, zc in enumerate((43.0, 53.0, 63.0)):
        y = 1.0
        while y < H - 0.8:
            z = zc + rnd.uniform(-3.2, 3.2)
            r = rnd.uniform(0.35, 0.6)
            m = M((x1, y, z), 0, 0, -90)       # local +Y -> +X (out of the wall)
            loft(a.mb("Use"), m, [(0.0, r, r * rnd.uniform(0.7, 1.0)), (r * 0.6, r * 0.75, r * 0.6), (r * 0.9, r * 0.3, r * 0.3)],
                 n=5, phase=rnd.uniform(0, 1))
            holds += 1
            y += rnd.uniform(1.1, 1.7)
    a.extra["holds"] = holds
    a.mark("ClimbTop", (-106.8, H + 0.4, 53.0), (1, 0, 0), (0, 1, 0), {"drill": "top in under 8 s"})
    a.mark("ClimbBase", (-104.0, 0.0, 53.0), (-1, 0, 0))
    # bikes
    for i in range(4):
        bx, bz = -90.0 + i * 6.0, 64.0
        m = M((bx, 0, bz))          # rider faces -Z
        use = a.mb("Use")
        cube(a.mb("DarkSteel"), m, (2.2, 0.25, 4.6), (0, 0.12, 0))
        beam(use, m @ V((0, 0.25, 1.4)), m @ V((0, 3.2, 0.9)), 0.3, 0.3)        # seat post
        beam(use, m @ V((0, 0.25, -1.6)), m @ V((0, 4.0, -1.3)), 0.3, 0.3)      # bar post
        beam(use, m @ V((0, 1.4, 1.2)), m @ V((0, 1.4, -1.5)), 0.28, 0.28)
        cube(a.mb("Pad"), m, (1.1, 0.35, 1.4), (0, 3.35, 0.9))
        cube(a.mb("DarkSteel"), m, (2.0, 0.2, 0.25), (0, 4.0, -1.3))
        cyl(a.mb("Rubber"), m @ M((-0.25, 1.4, -1.0), 0, 0, -90), 1.1, 0.5, n=10)
        cube(a.mb("Screen"), m, (0.9, 0.6, 0.12), (0, 4.4, -1.35))
        a.colm("Bike%d" % (i + 1), (bx, 1.8, bz), (2.2, 3.6, 4.6), 0.0)
        a.mark("Bike_%d" % (i + 1), (bx, 3.6, bz + 0.9), (0, 0, -1), (0, 1, 0), {"seat": True})
    # weights: rack + bench + bar with plates
    wx, wz = -58.0, 66.0
    for s in (-1, 1):
        cube(a.mb("DarkSteel"), M((wx, 0, wz)), (0.35, 5.0, 0.35), (s * 3.2, 2.5, 2.4))
        cube(a.mb("DarkSteel"), M((wx, 0, wz)), (0.35, 0.35, 3.2), (s * 3.2, 0.2, 1.0))
    cube(a.mb("DarkSteel"), M((wx, 0, wz)), (6.8, 0.3, 0.35), (0, 5.0, 2.4))
    cube(a.mb("Pad"), M((wx, 0, wz)), (1.4, 0.5, 5.0), (0, 1.7, 0.4))
    cube(a.mb("Steel"), M((wx, 0, wz)), (0.6, 1.5, 0.6), (0, 0.75, -1.4))
    cube(a.mb("Steel"), M((wx, 0, wz)), (0.6, 1.5, 0.6), (0, 0.75, 2.2))
    barm = M((wx, 3.6, wz + 2.4), 0, 0, -90)
    cyl(a.mb("Steel"), barm @ M((0, -3.8, 0)), 0.12, 7.6, n=6)
    for s in (-1, 1):
        for k in range(2):
            cyl(a.mb("Rubber"), barm @ M((0, s * (2.4 + k * 0.45) - (0.4 if s < 0 else 0), 0)), 1.2 - k * 0.25, 0.4, n=10)
    a.colm("WeightRack", (wx, 2.6, wz + 1.0), (7.0, 5.2, 3.4), 0.0)
    a.mark("Weights", (wx, 1.95, wz + 0.4), (0, 0, -1), (0, 1, 0), {"drill": "10 lifts on the beat"})
    # rope
    cyl(a.mb("Rope"), M((-60.0, 1.5, 42.0)), 0.28, HH - 3.0, n=6)
    cyl(a.mb("DarkSteel"), M((-60.0, HH - 1.5, 42.0)), 0.6, 1.5, n=6)
    a.colm("Rope", (-60.0, (HH + 1.5) / 2, 42.0), (0.6, HH - 1.5, 0.6), 0.0, ["Climbable"])
    mat_(a, "UseMat", "Mat_Climber", (-101.0, 53.0), (5.0, 10.0), kit="Climber", station="Fitness")
    a.mark("Chest_Fitness", (-46.0, 0.0, 50.0), (1, 0, 0), (0, 1, 0), {"station": "Fitness"})
    a.mark("Station_Fitness", (-70.0, 0.0, 50.0), (-1, 0, 0), (0, 1, 0),
           {"drill": "wall top under 8 s; bikes 20 s in the green; 10 clean lifts"})
    return a


def build_floor():
    a = Asset("TC_PrepFloor", "Prep",
              "The floor (prep area): the running track (lane 4 wide, one lap = 300 studs on its centre line), the "
              "obstacle run inside it (vault box, mantle wall, slide bar, start and finish lines), eight benches facing "
              "the kit board (KitBoard marker: a SurfaceGui face 16 x 9).")
    r, half = 20.0, 43.5   # 2*87 + 2*pi*20 = 299.7
    pts_c = []
    for k in range(17):
        ang = math.pi * k / 16
        pts_c.append((math.cos(ang) * r, half + math.sin(ang) * r))
    north = [(-x, -z) for x, z in pts_c]
    loop = [(r, -half)] + [(r, half)] + pts_c[1:-1] + [(-r, half), (-r, -half)] + north[1:-1] + [(r, -half)]
    strip_up(a.mb("Track"), loop, 4.0, 0.03)
    for off in (-2.1, 2.1):
        rr = r + off
        pc = [(math.cos(math.pi * k / 16) * rr, half + math.sin(math.pi * k / 16) * rr) for k in range(17)]
        nn = [(-x, -z) for x, z in pc]
        lp = [(rr, -half), (rr, half)] + pc[1:-1] + [(-rr, half), (-rr, -half)] + nn[1:-1] + [(rr, -half)]
        strip_up(a.mb("Line"), lp, 0.22, 0.04)
    strip_up(a.mb("Line"), [(r - 2.0, 0.0), (r + 2.0, 0.0)], 0.5, 0.045)
    a.mark("TrackStart", (r, 0.0, 0.0), (0, 0, -1), (0, 1, 0), {"lapStuds": round(2 * 2 * half + TAU * r, 1),
                                                                 "drill": "lap in under 19 s"})
    # obstacle run along x = 0, running south (+Z)
    strip_up(a.mb("Line"), [(-3.0, -44.0), (3.0, -44.0)], 0.5, 0.045)
    strip_up(a.mb("Line"), [(-3.0, -8.0), (3.0, -8.0)], 0.5, 0.045)
    cube(a.mb("Pad"), M((0, 0, -36.0)), (6.0, 2.7, 3.0), (0, 1.35, 0))
    cube(a.mb("Use"), M((0, 0, -36.0)), (6.1, 0.3, 3.1), (0, 2.85, 0))
    a.col("VaultBox", (-3.0, 0.0, -37.5), (3.0, 3.0, -34.5))
    cube(a.mb("Pad"), M((0, 0, -26.0)), (8.0, 5.2, 2.0), (0, 2.6, 0))
    cube(a.mb("Use"), M((0, 0, -26.0)), (8.1, 0.3, 2.1), (0, 5.35, 0))
    a.col("MantleWall", (-4.0, 0.0, -27.0), (4.0, 5.5, -25.0))
    for s in (-1, 1):
        cube(a.mb("DarkSteel"), M((0, 0, -16.0)), (0.4, 4.6, 0.4), (s * 3.5, 2.3, 0))
    cyl(a.mb("Use"), M((-3.5, 3.2, -16.0), 0, 0, -90), 0.2, 7.0, n=6)
    a.col("SlideBar", (-3.7, 3.0, -16.3), (3.7, 3.4, -15.7))
    a.mark("Obstacle_Start", (0.0, 0.0, -44.0), (0, 0, 1), (0, 1, 0), {"drill": "run in under 12 s"})
    a.mark("Obstacle_End", (0.0, 0.0, -8.0), (0, 0, 1))
    # benches face the kit board (south)
    n = 0
    for x in (-9.0, 9.0):
        for z in (12.0, 20.0, 28.0, 36.0):
            n += 1
            cube(a.mb("Wood"), M((x, 0, z)), (8.0, 0.35, 1.6), (0, 1.7, 0))
            for sx in (-3.2, 3.2):
                cube(a.mb("Steel"), M((x, 0, z)), (0.3, 1.55, 1.2), (sx, 0.78, 0))
            a.col("Bench%d" % n, (x - 4.0, 0.0, z - 0.8), (x + 4.0, 1.88, z + 0.8))
            for sx in (-2.5, 0.0, 2.5):
                a.mark("Seat_%d_%d" % (n, int(sx + 3)), (x + sx, 1.9, z), (0, 0, 1), (0, 1, 0))
    # kit board on two legs, facing north
    kx, kz = 0.0, 50.0
    for s in (-1, 1):
        cube(a.mb("DarkSteel"), M((kx, 0, kz)), (0.5, 12.0, 0.5), (s * 8.6, 6.0, 0.3))
        cube(a.mb("DarkSteel"), M((kx, 0, kz)), (1.6, 0.3, 2.4), (s * 8.6, 0.15, 0.3))
    cube(a.mb("Frame"), M((kx, 0, kz)), (17.0, 9.8, 0.5), (0, 7.4, 0.3))
    cube(a.mb("Screen"), M((kx, 0, kz)), (16.0, 9.0, 0.1), (0, 7.4, 0.0))
    cube(a.mb("Panel"), M((kx, 0, kz)), (16.2, 9.0, 0.2), (0, 7.4, 0.62))
    for s in (-1, 1):
        beam(a.mb("Rib"), (kx + s * 7.6, 3.2, kz + 0.75), (kx - s * 2.0, 11.6, kz + 0.75), 0.5, 0.15, up=(0, 0, 1))
    a.col("KitBoard", (kx - 8.9, 0.0, kz - 0.1), (kx + 8.9, 12.3, kz + 0.7))
    a.mark("KitBoard", (kx, 7.4, kz - 0.06), (0, 0, -1), (0, 1, 0), {"size": [16.0, 9.0]})
    a.mark("Station_Floor", (0.0, 0.0, 0.0), (0, 0, -1), (0, 1, 0), {"note": "allies are offered here; the kit board"})
    return a


def build_doors():
    a = Asset("TC_LaunchDoors", "Door",
              "The launch doors and corridor. A steel surround on the north wall (x -16..16) under the big screen, a "
              "red lamp over the opening, two oxblood pocket-door leaves (8 x 14 together) that slide 4.2 into the wall "
              "(DoorLeafL/R + DoorTrimL/R move together; colliders DoorL_Col/DoorR_Col), then a corridor 6 wide, 9 high "
              "and 10 long through to z -87 (place z 2913), oxblood walls, red light strips at floor level, a blue-grey "
              "steel floor with white stripes. TC_LaunchDoors_EndCap (black) closes the corridor until the red room "
              "stands behind it; remove it then.")
    zf = -HZ
    for (x0, y0, x1, y1) in [(-16.0, 0.0, -4.0, 17.0), (4.0, 0.0, 16.0, 17.0), (-4.0, 14.0, 4.0, 17.0)]:
        box(a.mb("DarkSteel"), (x0, y0, zf), (x1, y1, zf + 0.4))
    for x in (-12.0, -8.0, 8.0, 12.0):
        box(a.mb("Steel"), (x - 0.12, 0.0, zf + 0.4), (x + 0.12, 17.0, zf + 0.5))
    box(a.mb("Steel"), (-16.0, 16.6, zf + 0.4), (16.0, 17.0, zf + 0.6))
    for s in (-1, 1):
        xa, xb = sorted((s * 4.0, s * 5.0))
        box(a.mb("Steel"), (xa, 0.0, zf - 0.2), (xb, 15.0, zf + 1.0))
    box(a.mb("Steel"), (-5.0, 14.0, zf - 0.2), (5.0, 15.0, zf + 1.0))
    box(a.mb("DarkSteel"), (-2.4, 15.4, zf + 0.4), (2.4, 16.6, zf + 1.1))
    box(a.mb("RedLamp"), (-2.0, 15.6, zf + 1.1), (2.0, 16.4, zf + 1.25))
    a.mark("RedLamp", (0.0, 16.0, zf + 1.6), (0, 0, 1), (0, 1, 0), {"colourOff": [80, 24, 22], "colourOn": [255, 60, 48]})
    # leaves inside the wall thickness (z -76.3..-75.7)
    for side, s in (("L", -1), ("R", 1)):
        xa, xb = sorted((0.0, s * 4.0))
        box(a.mb("DoorLeaf" + side), (xa, 0.0, -76.3), (xb, 14.0, -75.7))
        for y in (3.0, 7.0, 11.0):
            box(a.mb("DoorTrim" + side), (xa + 0.2, y - 0.15, -75.75), (xb - 0.2, y + 0.15, -75.6))
        ex0, ex1 = sorted((s * 3.85, s * 4.0))
        box(a.mb("DoorTrim" + side), (ex0, 0.0, -76.35), (ex1, 14.0, -75.65))
        a.col("Door" + side, (xa, 0.0, -76.3), (xb, 14.0, -75.7), ["LaunchDoorLeaf"], {"Side": side, "OpenX": s * 4.2})
        a.mark("DoorLeaf" + side, ((xa + xb) / 2, 7.0, -76.0), (0, 0, 1), (0, 1, 0),
               {"openOffset": [s * 4.2, 0.0, 0.0], "seconds": 1.2})
    a.mark("LaunchDoors", (0.0, 0.0, -75.0), (0, 0, 1), (0, 1, 0), {"width": 8, "height": 14})
    # corridor z -77..-87
    c0, c1 = -87.0, -77.0
    for s in (-1, 1):
        xa, xb = sorted((s * 3.0, s * 4.0))
        box(a.mb("Oxblood"), (xa, 0.0, c0), (xb, 10.0, c1))
        a.col("CorrWall%s" % ("E" if s > 0 else "W"), (xa, 0.0, c0), (xb, 10.0, c1))
        sa, sb = sorted((s * 3.0, s * 2.85))
        box(a.mb("RedStrip"), (sa, 0.3, c0), (sb, 0.6, c1))
    box(a.mb("Ceiling"), (-4.0, 9.0, c0), (4.0, 10.0, c1))
    a.col("CorrRoof", (-4.0, 9.0, c0), (4.0, 10.0, c1))
    box(a.mb("CorrFloor"), (-4.0, -1.0, c0), (4.0, 0.0, c1))
    a.col("CorrFloor", (-4.0, -2.0, c0), (4.0, 0.0, c1))
    for x in (-1.9, 1.9):
        strip_up(a.mb("Line"), [(x, c1), (x, c0)], 0.3, 0.02)
    for k, z in enumerate((-80.0, -84.0)):
        box(a.mb("DarkSteel"), (-1.0, 8.8, z - 0.5), (1.0, 9.0, z + 0.5))
        box(a.mb("RedStrip"), (-0.8, 8.7, z - 0.3), (0.8, 8.8, z + 0.3))
        a.mark("Lamp_Corr_%d" % (k + 1), (0.0, 8.4, z), (0, -1, 0), (0, 0, -1), {"light": True, "red": True})
    box(a.mb("EndCap"), (-3.0, 0.0, c0 - 0.2), (3.0, 9.0, c0))
    a.col("EndCap", (-3.0, 0.0, c0 - 0.4), (3.0, 9.0, c0), ["RedRoomSeam"])
    a.mark("Corridor_Entry", (0.0, 0.0, -77.0), (0, 0, -1))
    a.mark("Corridor_End", (0.0, 0.0, c0), (0, 0, -1), (0, 1, 0), {"redRoomDisc": [0.0, 0.0, -99.0]})
    a.mark("RedRoomDisc", (0.0, 0.0, -99.0), (0, 0, 1), (0, 1, 0), {"place": [8800, 200, 2901]})
    return a


# ================================================================================================ chest and dummy
CHEST_SPOTS = []   # filled from the station assets' Chest_* markers


def build_chest():
    a = Asset("TC_Chest", "Chest",
              "The station chest (lends that station's items; hold E 0.6 s). Steel-blue body with orange straps, lid "
              "separate: TC_Chest_Lid + TC_Chest_LidUse rotate about LidHinge (+X axis, back top edge), ~100 degrees "
              "opens it. Front = -Z (LookVector).", pivot="floor centre of the chest; front = -Z")
    w, h, d = 4.2, 1.9, 2.6
    box(a.mb("ChestBody"), (-w / 2, 0.25, -d / 2), (w / 2, h, d / 2))
    for sx in (-1.7, 1.7):
        for sz in (-1.0, 1.0):
            box(a.mb("DarkSteel"), (sx - 0.3, 0.0, sz - 0.25), (sx + 0.3, 0.3, sz + 0.25))
    for sx in (-1.2, 1.2):
        box(a.mb("Use"), (sx - 0.22, 0.25, -d / 2 - 0.05), (sx + 0.22, h, d / 2 + 0.05))
    box(a.mb("DarkSteel"), (-w / 2 - 0.04, 0.25, -d / 2 - 0.04), (w / 2 + 0.04, 0.5, d / 2 + 0.04))
    # lid: a shallow faceted top
    lid = a.mb("Lid")
    hw = w / 2 + 0.05
    lid.add([(-hw, h, -d / 2 - 0.05), (hw, h, -d / 2 - 0.05), (hw, h, d / 2 + 0.05), (-hw, h, d / 2 + 0.05),
             (-hw, h + 0.55, -d / 2 + 0.25), (hw, h + 0.55, -d / 2 + 0.25), (hw, h + 0.55, d / 2 - 0.25),
             (-hw, h + 0.55, d / 2 - 0.25)], HEX_F)
    for sx in (-1.2, 1.2):
        lid_use = a.mb("LidUse")
        lid_use.add([(sx - 0.22, h, -d / 2 - 0.1), (sx + 0.22, h, -d / 2 - 0.1), (sx + 0.22, h, d / 2 + 0.1),
                     (sx - 0.22, h, d / 2 + 0.1), (sx - 0.22, h + 0.6, -d / 2 + 0.2), (sx + 0.22, h + 0.6, -d / 2 + 0.2),
                     (sx + 0.22, h + 0.6, d / 2 - 0.2), (sx - 0.22, h + 0.6, d / 2 - 0.2)], HEX_F)
    box(a.mb("LidUse"), (-0.4, h - 0.5, -d / 2 - 0.12), (0.4, h + 0.1, -d / 2 - 0.02))
    PART_TAGS[("TC_Chest", "Lid")] = ["Lid"]
    PART_TAGS[("TC_Chest", "LidUse")] = ["Lid"]
    a.col("Base", (-w / 2, 0.0, -d / 2), (w / 2, h + 0.55, d / 2))
    a.mark("LidHinge", (0.0, h, d / 2), (1, 0, 0), (0, 1, 0))
    a.mark("Prompt", (0.0, 1.3, -d / 2 - 0.6), (0, 0, -1))
    a.mark("LootPoint", (0.0, 0.5, 0.0), (0, 0, -1))
    return a


def build_dummy():
    a = Asset("TC_Dummy", "Dummy",
              "A burlap training dummy at blocky-R15 proportions, one MeshPart per R15 limb (TC_Dummy_<R15 name>), "
              "a canvas vest on the UpperTorso, standing on a steel plate (TC_Dummy_Stand, 0.3 high). To swap "
              "DummyBuilder's look, put each mesh at its R15 part's CFrame (the manifest gives each part's centre).",
              pivot="ground centre under the feet; front = -Z")
    F = 0.3     # plate
    def P(role):
        return a.mb(role)
    # legs
    for side, s in (("Left", -1), ("Right", 1)):
        x = s * 0.5
        loft(P(side + "Foot"), M((x, F, -0.12)), [(0.0, 0.48, 0.62), (0.32, 0.46, 0.58), (0.42, 0.36, 0.44)], n=8)
        loft(P(side + "LowerLeg"), M((x, F + 0.42, 0)), [(0.0, 0.36, 0.36), (0.45, 0.42, 0.42), (0.95, 0.44, 0.44)], n=8)
        loft(P(side + "UpperLeg"), M((x, F + 1.37, 0)), [(0.0, 0.44, 0.44), (0.5, 0.5, 0.5), (0.85, 0.5, 0.48)], n=8)
        # arms hang at the sides
        ax = s * 1.5
        loft(P(side + "Hand"), M((ax, F + 1.86, 0)), [(0.0, 0.3, 0.32), (0.22, 0.42, 0.44), (0.42, 0.4, 0.4)], n=8)
        loft(P(side + "LowerArm"), M((ax, F + 2.28, 0)), [(0.0, 0.38, 0.38), (0.5, 0.44, 0.44), (0.95, 0.46, 0.46)], n=8)
        loft(P(side + "UpperArm"), M((ax, F + 3.23, 0)), [(0.0, 0.46, 0.46), (0.6, 0.5, 0.5), (0.95, 0.5, 0.48),
                                                          (1.15, 0.36, 0.38)], n=8)
    loft(P("LowerTorso"), M((0, F + 2.22, 0)), [(0.0, 0.96, 0.5), (0.45, 1.0, 0.52)], n=8, phase=math.pi / 8)
    loft(P("UpperTorso"), M((0, F + 2.67, 0)), [(0.0, 0.98, 0.52), (0.5, 1.02, 0.56), (1.3, 1.08, 0.58),
                                                (1.62, 0.8, 0.46)], n=8, phase=math.pi / 8)
    loft(P("Head"), M((0, F + 4.32, 0)), [(0.0, 0.3, 0.3), (0.18, 0.56, 0.56), (0.62, 0.62, 0.6), (1.02, 0.5, 0.48),
                                          (1.18, 0.22, 0.22)], n=8, phase=math.pi / 8)
    cyl(a.mb("Stand"), M((0, 0, 0)), 1.6, F, n=8)
    a.col("Body", (-1.0, F, -0.6), (1.0, F + 5.5, 0.6))
    a.col("Stand", (-1.5, 0.0, -1.5), (1.5, F, 1.5))
    a.mark("Root", (0.0, F + 2.0, 0.0), (0, 0, -1), (0, 1, 0), {"note": "HumanoidRootPart centre for the R15 swap"})
    a.extra["r15"] = R15
    return a


# ------------------------------------------------------------------------------------------------ realise / export
_MATS = {}


def mat(role, preview=False):
    key = role + ("pv" if preview else "")
    if key in _MATS:
        return _MATS[key]
    rgb, rmat = ROLES[role]
    m = bpy.data.materials.new("TC_" + role)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin_rgb(rgb), 1.0)
    b.inputs["Roughness"].default_value = 0.5 if rmat == "Metal" else 0.88
    b.inputs["Metallic"].default_value = 0.0
    if preview:
        if rmat == "Neon":
            b.inputs["Emission Color"].default_value = (*lin_rgb(rgb), 1.0)
            b.inputs["Emission Strength"].default_value = 5.0
        if role in TRANSPARENCY or rmat == "Glass":
            nt = m.node_tree
            out = nt.nodes.get("Material Output")
            tr = nt.nodes.new("ShaderNodeBsdfTransparent")
            mix = nt.nodes.new("ShaderNodeMixShader")
            mix.inputs[0].default_value = TRANSPARENCY.get(role, 0.55)
            nt.links.new(b.outputs[0], mix.inputs[1])
            nt.links.new(tr.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs[0])
    _MATS[key] = m
    return m


def mesh_from(name, mb):
    bm = bmesh.new()
    for verts, faces, closed in mb.shells:
        vs = [bm.verts.new(v) for v in verts]
        made = []
        for f in faces:
            try:
                made.append(bm.faces.new([vs[i] for i in f]))
            except ValueError:
                pass
        if made and closed:
            bmesh.ops.recalc_face_normals(bm, faces=made)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    tris = len(bm.faces)
    pts = [v.co.copy() for v in bm.verts]
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.update()
    return me, tris, pts


def bounds_rbx(pts):
    lo = V((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = V((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    a, b = rbx_from_b(lo), rbx_from_b(hi)
    return [min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)]


def realize(a, coll, mtx, with_cols=True, preview=False):
    """mtx: Blender world matrix of the asset root."""
    root = bpy.data.objects.new(a.name, None)
    root.matrix_world = mtx
    coll.objects.link(root)
    parts, total, allpts = [], 0, []
    for role, mb in a.parts.items():
        if not mb.shells:
            continue
        name = a.name + "_" + role
        me, tris, pts = mesh_from(name, mb)
        me.materials.append(mat(role, preview))
        ob = bpy.data.objects.new(name, me)
        ob.parent = root
        coll.objects.link(ob)
        total += tris
        allpts += pts
        mn, mx = bounds_rbx(pts)
        rgb, rmat = ROLES[role]
        tags = PART_TAGS.get((a.name, role), [])
        if a.name == "TC_Dummy" and role in R15:
            tags = tags + ["R15:" + role]
        parts.append({"name": name, "role": role, "robloxMaterial": rmat, "rgb": list(rgb), "collide": False,
                      "collision": "Box", "castShadow": role not in NO_SHADOW, "canQuery": False, "canTouch": False,
                      "transparency": TRANSPARENCY.get(role, 0.0), "tris": tris, "tags": tags,
                      "center": [round((mn[i] + mx[i]) / 2, 3) for i in range(3)],
                      "size": [round(mx[i] - mn[i], 3) for i in range(3)]})
    cols = []
    for what, c, s, yaw, tags, attrs in a.cols:
        name = "%s_%s_Col" % (a.name, what)
        if with_cols:
            mb = MB()
            cube(mb, M(c, yaw), s)
            me, tris, _ = mesh_from(name, mb)
            me.materials.append(mat("Col"))
            ob = bpy.data.objects.new(name, me)
            ob.parent = root
            ob.hide_render = True
            coll.objects.link(ob)
        cols.append({"name": name, "center": R3(c), "size": R3(s), "yawDeg": round(yaw, 2), "collision": "Box",
                     "transparency": 1.0, "canCollide": True, "canQuery": True, "canTouch": "TrainingTarget" in tags,
                     "castShadow": False, "tags": tags, "attributes": attrs})
    return root, parts, total, allpts, cols


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()
    return bpy.context.scene


def build_all():
    zones = [build_platform(), build_shell(), build_archery(), build_blade(), build_spear(), build_survival(),
             build_fitness(), build_floor(), build_doors()]
    chest, dummy = build_chest(), build_dummy()
    chest.placements, dummy.placements = [], []
    for z in zones:
        for k, (p, l, u, at) in z.att.items():
            if k.startswith("Chest_"):
                chest.placements.append({"name": k, "position": R3(p), "yawDeg": round(yaw_for((l.x, l.z)), 2),
                                         "station": at.get("station")})
            if k.startswith("Dummy_") or k == "BandageDummy":
                dummy.placements.append({"name": k, "position": [round(p.x, 3), 0.0, round(p.z, 3)],
                                         "yawDeg": round(yaw_for((l.x, l.z)), 2), "role": at.get("role")})
    return zones + [chest, dummy]


def glb_check(path):
    with open(path, "rb") as fh:
        data = fh.read()
    clen, _ = struct.unpack_from("<I4s", data, 12)
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    prims = [p for m in js.get("meshes", []) for p in m["primitives"]]
    tris = sum(js["accessors"][p["indices"]]["count"] // 3 for p in prims)
    return {"file": os.path.basename(path), "bytes": len(data), "meshes": len(js.get("meshes", [])),
            "triangles": tris, "images": len(js.get("images", [])), "maxMeshTriangles":
                max(js["accessors"][p["indices"]]["count"] // 3 for p in prims)}


def att_json(p, l, u, at):
    d = {"position": R3(p), "look": R3(l), "up": R3(u)}
    if at:
        d["attributes"] = at
    return d


def stage_build(assets):
    os.makedirs(OUT, exist_ok=True)
    scene = reset_scene()
    coll = scene.collection
    mk = bpy.data.collections.new("Markers")
    scene.collection.children.link(mk)
    out = []
    x = 0.0
    hall_markers = {}
    unique, drawn = 0, 0
    for a in assets:
        origin = V((x, 0, 0))
        root, parts, tris, pts, cols = realize(a, coll, Matrix.Translation(origin))
        x += 600.0
        mn, mx = bounds_rbx(pts)      # mesh coordinates are root-local (= hall / asset space)
        att ={k: att_json(p, l, u, at) for k, (p, l, u, at) in sorted(a.att.items())}
        # empties for every marker (kept in the .blend, not exported)
        for k, (p, l, u, at) in a.att.items():
            e = bpy.data.objects.new("%s.%s" % (a.name, k), None)
            e.empty_display_type = 'SINGLE_ARROW'
            e.empty_display_size = 1.5
            e.matrix_world = Matrix.Translation(origin + B(p)) @ V((0, 0, 1)).rotation_difference(B(l)).to_matrix().to_4x4()
            mk.objects.link(e)
        d = {"name": a.name, "kind": a.kind, "notes": a.notes, "pivot": a.pivot, "origin": [x - 600.0, 0.0, 0.0],
             "size": [round(mx[i] - mn[i], 2) for i in range(3)], "boundsMin": mn, "boundsMax": mx, "tris": tris,
             "parts": parts, "colliders": cols, "attachments": att, "placements": a.placements}
        d.update(a.extra)
        out.append(d)
        unique += tris
        drawn += tris * len(a.placements)
        if a.name not in ("TC_Chest", "TC_Dummy"):
            for k, v in att.items():
                hall_markers[k] = dict(v, asset=a.name)
        log("  %-16s tris %6d parts %2d cols %3d att %3d placed %d" % (a.name, tris, len(parts), len(cols), len(att),
                                                                      len(a.placements)))
    # export meshes + roots only
    bpy.ops.object.select_all(action='DESELECT')
    for ob in coll.objects:
        ob.select_set(not ob.name.endswith("_Col"))     # colliders live in the .blend and the manifest, not the GLB
    path = os.path.join(OUT, CATEGORY + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_normals=True, export_tangents=False,
                              export_materials='EXPORT', export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, CATEGORY + ".blend"))
    check = glb_check(path)
    manifest = {
        "category": CATEGORY, "glb": CATEGORY + ".glb", "generator": "training_centre.py", "seed": SEED,
        "units": "studs (1 Blender unit = 1 stud)",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y). Hall space: x east, z south (north = -z), y up.",
        "hallOrigin": HALL_AT,
        "hallOriginNote": "Every zone asset is placed at the hall origin (its placement is [0,0,0], yaw 0): its part "
                          "centres, colliders and attachments are hall coordinates. TC_Chest and TC_Dummy carry one "
                          "placement per copy (position + yawDeg about Y in hall space).",
        "dimensions": {"hallInside": [2 * HX, HH, 2 * HZ], "wall": WALL, "platformTop": 0.0,
                       "platformZ": [HZ, 86.6], "trainBCentreLineZ": 97.5, "doors": [8.0, 14.0],
                       "corridor": {"width": 6.0, "height": 9.0, "z": [-87.0, -77.0]},
                       "track": {"radius": 20.0, "straight": 87.0, "lap": 299.7, "lane": 4.0}},
        "triangles": {"unique": unique, "drawnAllCopies": drawn,
                      "note": "drawn = every placed copy; a view of the hall sees most of it but not the platform's far "
                              "ends or the corridor"},
        "markers": hall_markers,
        "lampNote": "Hall: a PointLight at each Lamp_ii_jj marker whose attribute light is true (Range 40, Brightness 1.4, "
                    "Colour (236, 240, 236), Shadows on only for Lamp_05_03 and Lamp_07_05); the Downlight discs are "
                    "Neon. Platform: PlatLamp_b_k PointLights (Range 22, Brightness 1.2, warm) switched with the "
                    "PlatLamp<b> Neon bar. Corridor: Lamp_Corr_n red (Range 12).",
        "import": [
            "Insert the upload; each asset root arrives as a Model with one MeshPart per role named <Asset>_<Role>.",
            "Place each MeshPart at hall * placement * CFrame.new(part.center) * CFrame.Angles(0, pi, 0) (the importer "
            "turns meshes 180 degrees about Y), Anchored, CanCollide/CanQuery/CanTouch off; Color and Material from "
            "rgb and robloxMaterial; Transparency from transparency; CastShadow from castShadow.",
            "Colliders: build plain invisible Parts from 'colliders' (centre, size, yawDeg about Y), CanCollide on, "
            "CanQuery on, CollisionFidelity irrelevant (Parts). Tags: Climbable, TrainingTarget (+ attributes Station, "
            "Lane, Distance), LaunchDoorLeaf (Side, OpenX), RedRoomSeam (remove once the red room stands behind it).",
            "Markers are manifest-only (empties in TrainingCentre.blend): attachments per asset, 'markers' in hall "
            "space. Spawn_01..48 are on platform B and must NOT become enabled SpawnLocations.",
        ],
        "glbCheck": check, "assets": out,
    }
    mpath = os.path.join(OUT, CATEGORY + ".manifest.json")
    old_ids = None
    if os.path.exists(mpath):
        try:
            with open(mpath, encoding="utf-8") as fh:
                old_ids = json.load(fh).get("assetIds")
        except Exception:
            old_ids = None
    if old_ids and old_ids.get("model", {}).get("sha256"):
        import hashlib
        with open(path, "rb") as fh:
            sha = hashlib.sha256(fh.read()).hexdigest()
        if sha == old_ids["model"]["sha256"]:
            manifest["assetIds"] = old_ids
        else:
            log("NOTE the GLB changed since the recorded upload (sha differs): assetIds dropped, a new upload is needed")
    with open(mpath, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    # the Part build of the same set: one primitive per modelled shape (A = axis-aligned box: centre, size;
    # B = box: centre, size, right vector, up vector; C = Cylinder part: centre, length, diameter, axis)
    prims = {a.name: {role: mb.prims for role, mb in a.parts.items() if mb.prims} for a in assets}
    npr = sum(len(v) for d in prims.values() for v in d.values())
    with open(os.path.join(OUT, CATEGORY + ".prims.json"), "w", encoding="utf-8") as fh:
        json.dump({"note": "Part primitives per asset and role, asset space (Roblox axes). Same colours/materials as "
                           "the manifest roles.", "count": npr, "assets": prims}, fh, separators=(",", ":"))
    log("PRIMS", npr)
    log("EXPORTED", path, check, "unique", unique, "drawn", drawn)
    return manifest


# ------------------------------------------------------------------------------------------------ previews
def pv_mat(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin_rgb(rgb), 1.0)
    b.inputs["Roughness"].default_value = rough
    return m


def pv_box(coll, size, loc, m, rot=(0, 0, 0), parent=None, bevel=0.04):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect='EDGES')
    me = bpy.data.meshes.new("b")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("b", me)
    ob.location = loc
    ob.rotation_euler = rot
    me.materials.append(m)
    coll.objects.link(ob)
    if parent is not None:
        ob.parent = parent
    return ob


SHIRTS = [(230, 230, 226), (92, 112, 132), (132, 92, 72), (84, 120, 96), (150, 140, 110), (70, 80, 120)]


def pv_figure(coll, loc_r, look_r, shirt):
    """A blocky 5.5-stud avatar at a Roblox hall position, facing look_r."""
    skin = pv_mat("skin", (214, 190, 160))
    pants = pv_mat("pants", (70, 72, 80))
    sh = pv_mat("shirt", shirt)
    root = bpy.data.objects.new("Fig", None)
    root.location = B(loc_r)
    lk = B(look_r)
    root.rotation_euler = (0, 0, math.atan2(-lk.x, lk.y))
    coll.objects.link(root)
    pv_box(coll, (0.96, 0.96, 2.0), (-0.5, 0, 1.0), pants, parent=root)
    pv_box(coll, (0.96, 0.96, 2.0), (0.5, 0, 1.0), pants, parent=root)
    pv_box(coll, (2.0, 1.0, 2.0), (0, 0, 3.0), sh, parent=root)
    pv_box(coll, (0.96, 0.96, 2.0), (-1.5, 0, 3.0), skin, parent=root)
    pv_box(coll, (0.96, 0.96, 2.0), (1.5, 0, 3.0), skin, parent=root)
    pv_box(coll, (1.2, 1.1, 1.0), (0, 0, 4.5), skin, parent=root, bevel=0.14)


def use_gpu(scene):
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
                    scene.cycles.device = 'GPU'
                    log("cycles on", kind, [d.name for d in devs])
                    return
            except Exception:
                continue
    except Exception as e:
        log("GPU setup failed", e)


def pv_setup(scene):
    scene.render.engine = 'CYCLES'
    use_gpu(scene)
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 5
    scene.cycles.transparent_max_bounces = 8
    scene.render.image_settings.file_format = 'PNG'
    try:
        scene.view_settings.view_transform = 'AgX'
        scene.view_settings.exposure = 0.3
    except Exception:
        pass
    w = bpy.data.worlds.new("PV")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.42, 0.48, 0.52, 1.0)
    bg.inputs[1].default_value = 0.25
    scene.world = w


def add_light(scene, name, p_r, energy, color, size=1.0, kind='POINT', down=False):
    li = bpy.data.lights.new(name, kind)
    li.energy = energy
    li.color = color
    if kind == 'AREA':
        li.size = size
    else:
        li.shadow_soft_size = size
    o = bpy.data.objects.new(name, li)
    o.location = B(p_r)
    scene.collection.objects.link(o)
    return o


def import_train(scene):
    """Train copy B from the uploaded TrainLobby.glb, placed per its manifest at the TrainB marker."""
    if not (os.path.exists(TRAIN_GLB) and os.path.exists(TRAIN_MAN)):
        log("NOTE no TrainLobby.glb: the previews show the platform without the train")
        return
    with open(TRAIN_MAN, encoding="utf-8") as fh:
        tm = json.load(fh)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=TRAIN_GLB)
    new = [o for o in bpy.data.objects if o not in before]
    roots = {o.name: o for o in new if o.parent is None}
    lounge = Matrix.Translation(B((36.5, 0.0, 97.5))) @ Matrix.Rotation(math.radians(-90), 4, 'Z')
    keep = set()
    for asset in tm["assets"]:
        nm = asset["name"]
        root = roots.get(nm)
        if root is None:
            continue
        pls = [asset["placement"]] if "placement" in asset else asset.get("placements", [])
        if not pls:
            continue
        keep.add(nm)
        for i, pl in enumerate(pls):
            r = root if i == 0 else None
            if r is None:
                r = root.copy()
                scene.collection.objects.link(r)
                for ch in root.children:
                    c2 = ch.copy()
                    scene.collection.objects.link(c2)
                    c2.parent = r
            p = pl.get("position") or pl.get("p")
            r.matrix_world = lounge @ Matrix.Translation(B(p))
    for nm, r in roots.items():
        if nm not in keep:
            for ch in list(r.children_recursive):
                bpy.data.objects.remove(ch)
            bpy.data.objects.remove(r)
    # hide imported colliders
    for o in bpy.data.objects:
        if o.name.endswith("_Col") or "_Col." in o.name:
            o.hide_render = True
    log("train B placed:", sorted(keep))


def pv_render(scene, path, res, cam_r, target_r, lens=24.0):
    cam = bpy.data.cameras.new("Cam")
    cam.lens = lens
    cam.clip_start = 0.1
    cam.clip_end = 3000
    co = bpy.data.objects.new("Cam", cam)
    scene.collection.objects.link(co)
    co.location = B(cam_r)
    co.rotation_euler = (B(target_r) - B(cam_r)).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = co
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(co)
    log("  rendered", os.path.basename(path))


def load_px(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def save_px(path, arr):
    h, w, _ = arr.shape
    img = bpy.data.images.new("sheet", w, h, alpha=True)
    img.pixels.foreach_set(arr[::-1].astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def label_layer(path, size, labels):
    scene = reset_scene()
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    try:
        scene.view_settings.view_transform = 'Standard'
    except Exception:
        pass
    w, h = size
    k = 0.01
    m = bpy.data.materials.new("Txt")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (1, 1, 1, 1)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    for x, y, hp, text in labels:
        cu = bpy.data.curves.new("t", 'FONT')
        cu.body = text
        cu.size = hp * k * 1.35
        ob = bpy.data.objects.new("t", cu)
        ob.location = (x * k, -(y + hp) * k, 0)
        cu.materials.append(m)
        scene.collection.objects.link(ob)
    cam = bpy.data.cameras.new("C")
    cam.type = 'ORTHO'
    cam.ortho_scale = max(w, h) * k
    co = bpy.data.objects.new("C", cam)
    co.location = (w * k / 2, -h * k / 2, 10)
    scene.collection.objects.link(co)
    scene.camera = co
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def compose(path, size, panels, labels, tmp):
    w, h = size
    sheet = np.zeros((h, w, 4), dtype=np.float32)
    sheet[..., :3] = 0.09
    sheet[..., 3] = 1.0
    for f, x, y in panels:
        px = load_px(f)
        ph, pw, _ = px.shape
        sheet[y:y + ph, x:x + pw, :3] = px[..., :3]
    lp = os.path.join(tmp, "_labels_%s.png" % os.path.basename(path)[:-4])
    label_layer(lp, size, labels)
    lab = load_px(lp)
    for x, y, hp, text in labels:
        x0, x1 = max(0, x - 10), min(w, x + int(len(text) * hp * 0.58) + 14)
        y0, y1 = max(0, y - 7), min(h, y + hp + 12)
        sheet[y0:y1, x0:x1, :3] *= 0.38
    a = lab[..., 3:4]
    sheet[..., :3] = sheet[..., :3] * (1 - a) + lab[..., :3] * a
    save_px(path, sheet)
    log("PREVIEW", path)


def build_preview_scene(assets):
    scene = reset_scene()
    pv_setup(scene)
    for a in assets:
        for pl in a.placements:
            mtx = Matrix.Translation(B(pl["position"])) @ Matrix.Rotation(math.radians(pl["yawDeg"]), 4, 'Z')
            realize(a, scene.collection, mtx, with_cols=False, preview=True)
    import_train(scene)
    shell = [a for a in assets if a.name == "TC_HallShell"][0]
    for k, (p, l, u, at) in shell.att.items():
        if k.startswith("Lamp_"):
            add_light(scene, k, (p.x, p.y - 0.4, p.z), 2200.0, (0.96, 0.98, 1.0), size=2.0)
    plat = [a for a in assets if a.name == "TC_Platform"][0]
    for k, (p, l, u, at) in plat.att.items():
        if k.startswith("PlatLamp_"):
            add_light(scene, k, (p.x, p.y, p.z), 1700.0, (1.0, 0.86, 0.68), size=1.5)
    doors = [a for a in assets if a.name == "TC_LaunchDoors"][0]
    for k, (p, l, u, at) in doors.att.items():
        if k.startswith("Lamp_Corr") or k == "RedLamp":
            add_light(scene, k, (p.x, p.y, p.z), 260.0, (1.0, 0.3, 0.24), size=0.5)
    surv = [a for a in assets if a.name == "TC_Survival"][0]
    fp = surv.att["FirePit"][0]
    add_light(scene, "Fire", (fp.x, 1.6, fp.z), 300.0, (1.0, 0.55, 0.25), size=0.6)
    # people for scale
    rnd = random.Random(SEED + 99)
    figs = [((60, 0, 68.5), (0, 0, -1)), ((76, 0, 68.5), (0, 0, -1)), ((-75, 0.3, 4.0), (0, 0, -1)),
            ((-70, 0.3, 9.0), (1, 0, 0)), ((60, 0, -64), (1, 0, 0)), ((-84, 0, -48), (-1, 0, 0)),
            ((-62, 0, -60), (0, 0, -1)), ((-100, 0, 50), (-1, 0, 0)), ((-84, 0.6, 64.9), (0, 0, -1)),
            ((-9, 1.0, 20.6), (0, 0, 1)), ((9, 1.0, 28.6), (0, 0, 1)), ((20, 0, -10), (0, 0, -1)),
            ((0, 0, -50), (0, 0, 1)), ((-30, 0, 80), (0, 0, -1)), ((44, 0, 82), (0, 0, -1)),
            ((-60, 0, 81), (1, 0, 0)), ((-1.5, 0, -80), (0, 0, -1))]
    for i, (p, l) in enumerate(figs):
        pv_figure(scene.collection, p, l, SHIRTS[i % len(SHIRTS)])
    return scene


def stage_preview(assets):
    os.makedirs(PREV, exist_ok=True)
    tmp = os.path.join(PREV, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    scene = build_preview_scene(assets)
    E = 4.6
    shots = {
        # station with the train
        "plat_a":   ((-133, E + 1.5, 82.5), (40, 3.5, 92.0), 22),
        "plat_b":   ((12, E, 52), (-2, 5.0, 100), 24),
        # hall wide
        "hall_a":   ((100, 24, 70), (-30, 2, -30), 18),
        "hall_b":   ((-30, E + 1, 70), (-6, 8, -40), 20),
        # stations at eye height
        "st_arch":  ((80, E + 1.5, 72), (64, 3.5, 10), 24),
        "st_blade": ((-56, E, 12), (-80, 3.0, 6), 24),
        "st_spear": ((47, E, -55), (90, 4.0, -54), 24),
        "st_surv":  ((-46, E, -38), (-80, 1.5, -58), 22),
        "st_fit":   ((-50, E + 1, 54), (-96, 7.0, 52), 22),
        "st_track": ((24, E, 54), (0, 2.0, -30), 22),
        # prep area
        "prep_a":   ((0, 9, -2), (0, 5.0, 48), 22),
        "prep_b":   ((-26, E, 30), (6, 3.0, 22), 24),
        # the door
        "door_a":   ((9, E, -47), (0, 9.0, -75), 24),
        "door_b":   ((0, E, -71), (0, 4.0, -87), 22),
    }
    only = [s for s in ONLY.split(",") if s]
    paths = {}
    for k, (cam, tgt, lens) in shots.items():
        if only and k not in only:
            continue
        if k == "door_b":      # show the corridor with the leaves slid open
            for o in bpy.data.objects:
                for side, dx in (("L", -4.2), ("R", 4.2)):
                    if o.name.startswith("TC_LaunchDoors_DoorLeaf" + side) or o.name.startswith("TC_LaunchDoors_DoorTrim" + side):
                        o.location.x += dx
                if o.name.startswith("TC_LaunchDoors_EndCap"):
                    o.hide_render = False
        p = os.path.join(tmp, k + ".png")
        pv_render(scene, p, (960, 540), cam, tgt, lens)
        paths[k] = p
    if only:
        return
    W1 = (1940, 1180)
    sheets = [
        ("TC_owner_1_station_with_train.png", ["plat_a", "plat_b"],
         ["Platform B: the red train (copy B) stands beside the arches", "From the hall: the train through the middle arch"],
         "THE ARRIVAL PLATFORM  -  train B, three arches up into the hall"),
        ("TC_owner_2_hall_wide.png", ["hall_a", "hall_b"],
         ["The whole hall from the archery corner (220 x 150 x 36)", "From the middle arch: the floor, the track, the doors"],
         "THE TRAINING CENTRE  -  teal padded walls, white ribs, chequered carpet, orange = usable"),
        ("TC_owner_4_prep_area.png", ["prep_a", "prep_b"],
         ["The floor: 8 benches facing the kit board", "Benches, obstacle run and track from the side"],
         "THE PREP AREA  -  pick a kit, agree a truce, then the doors"),
        ("TC_owner_5_the_door.png", ["door_a", "door_b"],
         ["The launch doors under the big screen, red lamp over them", "The corridor: oxblood walls, red strips (end cap until the red room)"],
         "THE DOOR INTO THE RED ROOM"),
    ]
    for fn, ks, caps, title in sheets:
        panels = [(paths[ks[0]], 10, 70), (paths[ks[1]], 970, 70)]
        labels = [(20, 18, 30, title), (20, 620, 22, caps[0]), (980, 620, 22, caps[1])]
        compose(os.path.join(PREV, fn), (1940, 660), panels, labels, tmp)
    # stations sheet 3 x 2
    ks = [("st_arch", "Archery lanes: targets at 20, 40, 60"), ("st_blade", "Blade and axe circle: 4 dummies"),
          ("st_spear", "Spear and throwing range: boards 10..50"), ("st_surv", "Survival corner: fire, plants, trough"),
          ("st_fit", "Fitness corner: climbing wall, bikes, weights"), ("st_track", "Track lap 300 + obstacle run")]
    labels = [(20, 18, 30, "EACH STATION AT EYE HEIGHT (4.6 studs)  -  orange mats pick a kit, orange chests lend items")]
    panels = []
    for i, (k, cap) in enumerate(ks):
        col, row = i % 2, i // 2
        x, y = 10 + col * 970, 70 + row * 590
        panels.append((paths[k], x, y))
        labels.append((x + 10, y + 550, 22, cap))
    compose(os.path.join(PREV, "TC_owner_3_stations.png"), (1940, 1850), panels, labels, tmp)


def main():
    random.seed(SEED)
    assets = build_all()
    if "build" in STAGES:
        stage_build(assets)
    if "preview" in STAGES:
        stage_preview(assets)
    log("DONE")


main()
