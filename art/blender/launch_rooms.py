"""
launch_rooms.py - HUNGER GAMES (BETA) / LAST STANDING: the launch sequence, ONE set used before BOTH maps.
Faceted style A ("realistic blockish", docs/design/ArtStyle.md) with semi-realistic tones
(docs/design/UpcomingFilm_Brief.md section 2). Seeded and headless; every asset is modelled here, nothing is
downloaded, traced or generated. The owner's frames are study-only references: they are read for the compare
sheets and never copied into any exported file.

The three rooms, in the owner's order ("the red room with the metal on top is just the transition room ... it
loads up to the room like the images i sent you"):
  1. LaunchRedRoom      the transition room (client-local, loops while the map loads): oxblood walls, a roof of
                        red panels under a fine dark net set at 45 degrees to the hex frame and sagging slightly, a
                        teal hexagonal frame of square tube over the lift, a blue-grey steel deck with black grates,
                        red mesh in the two floor openings beside the lift, white stripes, red rails, red lamp
                        housings, an upper walkway with concrete stairs, a steel door and an intercom.
  2. the glass-case hall, the ground ring of the pole hall:
     LaunchCaseBay      one bay (x48 at r 110): a tall glass case on oxblood posts with a dark-red disc on its
                        pedestal, a front top-light and the maroon wall unit beside it.
     LaunchCaseGallery  45-degree segment (x8): the curved walkway, its pale kerb, the light gantry with rows of
                        white strip lights, columns and the navy back screen.
     LaunchRiserDisc    the moving disc (x48): dark-red top, rim, collar on the pole.
  3. the pole hall (the stage of the one-shot rise):
     LaunchPoleHallSegment  45-degree segment (x8): floor plates, the banked ring of oxblood and pale wedges,
                        wall with columns, ledges and two rows of vertical light bars, the truss dome with purlins,
                        the ceiling ring of LED bars in radial rows, the apertures over the poles.
     LaunchPoleHallCrown    the spoked ceiling ring (48 spokes), the hub and its 12 spotlights.
     LaunchPole         1-stud 12-sided dark steel rod with copper bands (x48). No light on the poles.

Pass 2 (TwoArenas.md sections 2.2, 2.4, 2.8, 7 and 8.2; critic #5 and #9):
  - the hue rides on the light: cool blue-white keys and a navy ambient in the case hall, the pole hall and over the
    deck, so the shadows go blue; the steel paint stays neutral. The reds are back at their sampled saturation
    (rails 0.53, case discs 0.33, each red within 0.05 of its frame sample; see palette_swatches.png).
  - the red room's net is the brief's spec: 1.2-stud cells, 0.25-stud bars, 45 degrees to the hex frame, a slight
    sag; the grates read black, and red shows only in the two floor openings beside the lift; the figure in the
    shot is the player's own stand-in in the white launch cape.
  - the poles are dark rods; the light bars are on the ceiling ring and the walls.
  - the rise ends on the film's low-angle, whole-body frame (T1 @127.2 s), then cuts to the whiteout; the manifest
    carries the camera keys for both cuts of TwoArenas 2.3 (the full launch and the short cut).

Pass 2, the review's must-fix items (14 Nov 2026):
  - frame A is the in-game shot: from just above the tube mouth, 75 degrees down, the far half of the hexagon frames
    the player's stand-in on the lift disc far below; an oxblood hood with thin red rails lines the drop under the
    frame (the film shows an oxblood shaft there, not the deck).
  - the light, not the paint, carries the band (TwoArenas 7): the deck keys cut by a quarter and leaning in over the
    grate lanes, a dim navy light under each grate lane, white lamp spots on the rail, no bounce in the red room; the
    case hall's own profile (deeper teal-navy bars, white gantry strips, a top-light cone on each disc); the pole
    hall's haze and bloom stand-ins. Neon parts light nothing in the previews, as in Roblox, which also ends the
    case hall's white speckle.
  - the wide frame is shot from the far side of the hall at the riders' height with an 18 mm lens (the spoked ring an
    ellipse across the top); the 12 hub spots hang in two tiers as one bright cluster; one wall bar per column, at the
    top of the wall, and every second row only in the ceiling ring's outer rings.
  - the case frame is a 35 mm view past the player along the tightly packed row; the neighbours stand in their suits
    so their discs show.
  - the red room's oxblood follows the band (OXBLOOD_RULING; the lead's ruling is pending) and the hex frame is back
    at the brief's tone; the walkway is darker (luma 58), as the film's floor is.

Run (headless, from the repo root; art/README.md section 1):
  blender --background --factory-startup --python art/blender/launch_rooms.py -- <out_dir> <preview_dir> [stages]
  out_dir     default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Launch
  preview_dir default art/previews/Launch
  stages      comma list (default build,preview,export):
                build    geometry, paint, AO (always runs)
                preview  compare sheets (render beside the owner's frame and the trailer frame), overviews, the
                         rise path sheet (both cuts), palette swatches, colour checks -> <preview_dir>
                export   LaunchRedRoom.glb, LaunchCaseHall.glb, LaunchPoleHall.glb, textures,
                         Launch.manifest.json (+ copy in art/manifests)
                only=<view+view...>  render just these preview views (red_a, red_b, cases, wide, rise, rise_end,
                         red_interior, case_bay, hall, risepath, palette)
  env LAUNCH_QUALITY = draft | final (samples; default final)
  env LAUNCH_REF     = folder of the owner's frames (default %USERPROFILE%/OneDrive/Documents/LastStanding/
                       References/owner). Only the compare sheets read it.
  env LAUNCH_TRAILER = folder of the trailer frames (default <LAUNCH_REF>/../trailer). Compare sheets only.
  The colour band (TwoArenas section 7) is checked with tools/art/colour_band.py on tools/art/specs/launch.json.

Conventions (art/README.md section 3): 1 unit = 1 stud; Blender Z up; Roblox (x, y, z) = Blender (x, z, -y);
an asset's front faces Blender +Y (Roblox LookVector); every asset root sits on z = 0 except LaunchRiserDisc
(origin = the standing surface, NOTE in the manifest). The set frame is the pole hall: origin at the floor centre,
bearings clockwise from Blender +Y (Roblox north, -Z).

Surfaces (ArtStyle rules 4-6): every facet carries ONE flat painted colour: the brief's semi-real tone with
+-6% per volume, +-3% per facet, a slight warm/cool drift, lighter and warmer on tops, cooler underneath, times a
baked ambient occlusion that never goes below half. Each surface's area-weighted mean after AO is normalised to the
brief's tone, so the tables in the brief are what the game shows. The export packs the facet colours into a small
palette texture per GLB (8 x 8 px cells, nearest-colour order so mips stay clean): a ColorMap, a RoughnessMap and
a MetalnessMap, no normal map (the facets are the shape). Light bars and lamp lenses are Neon parts; the case glass
is a Glass part. Darkness in these rooms comes from the lights (brief section 2.7), never from the paint.
"""
import json
import math
import os
import random
import shutil
import struct
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)
import tex_ground as tg  # noqa: E402  PNG writer, image reader, GPU setup (no side effects)

T0 = time.time()
TAU = 2.0 * math.pi
SEED = 50                                   # the 50th Games


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
EXPORTS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")
OUT = os.path.abspath(ARGV[0]) if len(ARGV) > 0 else os.path.join(EXPORTS, "Launch")
PREV = (os.path.abspath(ARGV[1]) if len(ARGV) > 1
        else os.path.normpath(os.path.join(HERE, "..", "previews", "Launch")))
_stage_arg = ARGV[2] if len(ARGV) > 2 else "build,preview,export"
STAGES = set(s for s in _stage_arg.split(",") if s and not s.startswith("only="))
ONLY = set()
for s in _stage_arg.split(","):
    if s.startswith("only="):
        ONLY.update(x for x in s[5:].split("+") if x)
QUALITY = os.environ.get("LAUNCH_QUALITY", "final")
REF = os.environ.get("LAUNCH_REF") or os.path.join(os.path.expanduser("~"), "OneDrive", "Documents",
                                                   "LastStanding", "References", "owner")
TRAILER = os.environ.get("LAUNCH_TRAILER") or os.path.normpath(os.path.join(REF, "..", "trailer"))
SHEET_LABEL = "BLENDER ITERATION - PLACEHOLDER FIGURES, NO PLANTS IN THIS SET"
ART = os.path.normpath(os.path.join(HERE, ".."))
CATEGORY = "Launch"
TEX = os.path.join(OUT, "textures")
GLB_ONLY = os.path.join(TEX, "glb_only")

# =============================================================================================== palette
# key: tone (the semi-real base, sRGB 0-255, = the area mean after AO), sampled (frame value, evidence only),
#      roughness, metalness, kind (paint | neon | glass), note.  Brief section 2.8 unless marked "ours".
# Pass 2: every red is back at the saturation of its frame sample (HSV S within 0.05, TwoArenas 8.2): pass 1 had
# pushed them to 0.55-0.69. The blue-greys stay as the brief set them: the navy is carried by the light.
# The red room's oxblood (review item 3b; THE LEAD'S RULING IS PENDING): TwoArenas 2.2 names only the rails and the
# case discs as the reds held at their sample, and 7's rules 3 and 5 keep strong colour for signals, so the oxblood
# walls, roof and hood are room surfaces under the band (0.65-0.85x the film's saturation): 15% under the sample, S 0.38
# (OXBLOOD_RULING "band", the default). Held at the sample (S 0.45) they render at 0.89-0.99x, over the band; the
# other ruling, "signal", holds them there and classes the room's oxblood regions as launch reds (sat_within 0.05).
OXBLOOD_RULING = os.environ.get("LAUNCH_OXBLOOD", "band")
_OXB = {"band": ((86, 53, 53), (80, 52, 53)), "signal": ((93, 51, 51), (86, 49, 51))}[OXBLOOD_RULING]
if os.environ.get("LAUNCH_OXBLOOD_DK") == "held":                              # look-dev
    _OXB = (_OXB[0], (86, 49, 51))
PAL = {
    # 1 red room
    "oxblood":     (_OXB[0], "#281616", 0.85, 0.0, "paint", "walls, roof panels, the hood (brief 2.8; S %.2f, sample 0.45: ruling '%s')" % ((max(_OXB[0]) - min(_OXB[0])) / max(_OXB[0]), OXBLOOD_RULING)),
    "oxblood_dk":  (_OXB[1], "#241515", 0.85, 0.0, "paint", "wall backing, lift apron (ours, from the floor sample, T1 @120.7 s; ruling '%s')" % OXBLOOD_RULING),
    "net":         ((62, 82, 86), "#1d4250", 0.6, 0.0, "paint", "net and grating, dark teal-grey steel"),
    "hex":         ((66, 114, 122), "#205766", 0.6, 0.0, "paint", "hexagonal frame of square tube, the brief's tone (S 0.46; review fix: measured on the limbs, the same surface in both frames, the frame renders under the band, not over it)"),
    "bolt":        ((84, 96, 100), None, 0.55, 0.0, "paint", "gusset plates and bolts (ours)"),
    "rose":        ((126, 101, 121), "#5c4d5a", 0.7, 0.0, "paint", "the lift disc, dusty rose (S 0.20; sampled 0.16)"),
    "deck":        ((120, 130, 136), "#205169", 0.6, 0.0, "paint", "steel deck plate (neutral; the cool keys make it blue)"),
    "grate":       ((44, 46, 48), "#031a2a", 0.7, 0.0, "paint", "floor grates and pit floors (deliberate black, luma >= 40)"),
    "redmesh":     ((87, 48, 61), "#1c1015", 0.8, 0.0, "paint", "the red mesh in the two floor openings (S 0.45 as sampled)"),
    "rail":        ((126, 63, 75), "#592a38", 0.55, 0.0, "paint", "red rails, painted steel tube (S 0.50; the sample is 0.53)"),
    "stripe":      ((206, 206, 200), "#697c87", 0.8, 0.0, "paint", "white floor stripes"),
    "lamp":        ((112, 57, 72), "#582d3b", 0.6, 0.0, "paint", "lamp housings (S 0.49 as sampled)"),
    "concrete":    ((126, 126, 122), "#2a3945", 0.9, 0.0, "paint", "concrete base course and steps"),
    "door":        ((88, 94, 100), None, 0.6, 0.0, "paint", "steel door and intercom (ours)"),
    # 2 glass-case hall
    "post":        ((90, 59, 63), "#4b353c", 0.7, 0.0, "paint", "case posts (S 0.34: the two samples are 0.29 and 0.37)"),
    "case_disc":   ((89, 60, 62), "#452e30", 0.7, 0.0, "paint", "case and rider discs (S 0.33 as sampled)"),
    "disc_rim":    ((82, 51, 54), "#0d141b", 0.7, 0.0, "paint", "rider's disc rim (sample graded blue; S 0.38, between the discs and the rails)"),
    "unit":        ((94, 58, 63), None, 0.75, 0.0, "paint", "maroon wall unit (ours; S 0.38, with the posts)"),
    "plinth":      ((76, 80, 86), None, 0.7, 0.0, "paint", "case plinth and pedestal, dark steel (ours)"),
    "walkway":     ((54, 59, 66), None, 0.7, 0.0, "paint", "gallery walkway deck (ours, dark blue-grey steel; review fix: luma 79 -> 58, the bottom of the built band, as the film's floor is dark: no light could dim the floor without also dimming the hall wall beyond)"),
    "shell_case":  ((54, 64, 78), "#123a4f", 0.85, 0.0, "paint", "glass-hall shell: screens, gantry"),
    # 3 pole hall
    "shell":       ((58, 66, 78), "#143040", 0.85, 0.0, "paint", "pole-hall shell: wall, roof deck"),
    "truss":       ((96, 104, 114), "#0d2132", 0.6, 0.0, "paint", "spoked ring and truss"),
    "floor":       ((70, 76, 84), None, 0.7, 0.0, "paint", "hall floor plates (ours, darker than the walkway)"),
    "wedge_red":   ((92, 63, 62), "#5d403e", 0.85, 0.0, "paint", "floor wedges, oxblood (S 0.33 as sampled)"),
    "wedge_pale":  ((176, 178, 176), "#8c9498", 0.85, 0.0, "paint", "floor wedges, pale; also the kerb"),
    "steel":       ((164, 166, 168), None, 0.4, 1.0, "paint", "the disc's collar, bare steel (metal)"),
    "pole":        ((112, 116, 122), None, 0.45, 0.7, "paint", "poles: plain steel rods (pass 2: no light on them; they read as thin dark lines against the lit hall)"),
    "copper":      ((176, 112, 70), "#c8833c", 0.4, 1.0, "paint", "copper bands (metal)"),
    "housing":     ((64, 68, 74), None, 0.7, 0.0, "paint", "LED bar housings, spot cans (ours)"),
    # emitters and glass (flat, never jittered)
    "light":       ((236, 240, 244), "#dfe6ed", 0.5, 0.0, "neon", "light bars and panels (the only Neon parts)"),
    "lens":        ((245, 240, 232), None, 0.5, 0.0, "neon", "lamp lenses and spot lenses"),
    "spot":        ((240, 242, 246), None, 0.5, 0.0, "neon", "hub spotlight lenses (the brightest emitters)"),
    "glass":       ((196, 210, 214), "#062a3d", 0.1, 0.0, "glass", "case glass, Transparency 0.65"),
}
# the reds of TwoArenas 8.2: tone saturation against the frame sample's (pass 1 in brackets)
REDS = ("oxblood", "oxblood_dk", "rail", "lamp", "redmesh", "post", "case_disc", "unit", "wedge_red", "rose")
RED_SAMPLE_SAT = {"post": 0.33}           # posts: mean of #4b353c (0.29) and #442b2e (T2 @133.3 s, 0.37)
# preview-only figures (never exported): white launch capes with dark trim (brief 2.8), white armour
FIG = {
    "cape": (216, 216, 212), "trim": (52, 62, 82), "skin": (198, 156, 124), "hair": (190, 160, 104),
    "hair_dk": (52, 40, 34), "trousers": (200, 200, 196), "shoe": (70, 70, 72), "armour": (214, 212, 206),
    "visor": (44, 46, 50), "rifle": (58, 60, 64), "black": (46, 46, 48), "yellow": (204, 172, 70),
}


def luma(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def s2l(v):
    v = v / 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lin(c):
    return tuple(s2l(x) for x in c)


# =============================================================================================== mesh builder
class MB:
    """Accumulates one part: vertices, faces, a palette key and a volume id per face."""

    def __init__(self, name, cls="paint"):
        self.name, self.cls = name, cls
        self.V, self.F, self.K, self.G = [], [], [], []
        self._vol = 0

    def vol(self):
        self._vol += 1
        return self._vol

    def add(self, geo, key, M=None, vol=None):
        verts, faces = geo
        if vol is None:
            vol = self.vol()
        b = len(self.V)
        for v in verts:
            w = (M @ Vector(v)) if M is not None else Vector(v)
            self.V.append((w.x, w.y, w.z))
        for f in faces:
            self.F.append(tuple(b + i for i in f))
            self.K.append(key)
            self.G.append(vol)
        return vol

    def tris(self):
        return sum(len(f) - 2 for f in self.F)


def g_prism(poly, z0, z1):
    n = len(poly)
    V = [(x, y, z0) for x, y in poly] + [(x, y, z1) for x, y in poly]
    F = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    F += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return V, F


def g_box(x0, y0, z0, x1, y1, z1):
    return g_prism([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1)


def p_ngon(r, n, rot=None, cx=0.0, cy=0.0, sx=1.0, sy=1.0):
    rot = math.pi / n if rot is None else rot
    return [(cx + sx * r * math.cos(rot + TAU * i / n), cy + sy * r * math.sin(rot + TAU * i / n)) for i in range(n)]


def p_crect(cx, cy, sx, sy, c):
    hx, hy = sx / 2.0, sy / 2.0
    return [(cx - hx + c, cy - hy), (cx + hx - c, cy - hy), (cx + hx, cy - hy + c), (cx + hx, cy + hy - c),
            (cx + hx - c, cy + hy), (cx - hx + c, cy + hy), (cx - hx, cy + hy - c), (cx - hx, cy - hy + c)]


def sec_rect(w, h):
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]


def g_beam(p0, p1, sec, up=(0, 0, 1)):
    """Prism of the CCW section (side, up) swept straight from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    X = d / d.length
    U = Vector(up).normalized()
    if abs(X.dot(U)) > 0.985:
        U = Vector((1, 0, 0)) if abs(X.x) < 0.9 else Vector((0, 1, 0))
    Y = U.cross(X).normalized()
    Z = X.cross(Y).normalized()
    n = len(sec)
    V = [p0 + Y * a + Z * b for a, b in sec] + [p1 + Y * a + Z * b for a, b in sec]
    F = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    F += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return [tuple(v) for v in V], F


def g_tube(p0, p1, r, n=8, up=(0, 0, 1)):
    return g_beam(p0, p1, p_ngon(r, n), up)


def g_annulus(outer, inner, z0, z1):
    """Ring prism between two CCW polygons with the same vertex count (mitred frames, collars)."""
    n = len(outer)
    V = ([(x, y, z0) for x, y in outer] + [(x, y, z1) for x, y in outer]
         + [(x, y, z0) for x, y in inner] + [(x, y, z1) for x, y in inner])
    F = []
    for i in range(n):
        j = (i + 1) % n
        F.append((i, j, n + j, n + i))
        F.append((2 * n + j, 2 * n + i, 3 * n + i, 3 * n + j))
        F.append((n + i, n + j, 3 * n + j, 3 * n + i))
        F.append((2 * n + i, 2 * n + j, j, i))
    return V, F


def g_sector(r0, r1, b0, b1, n, zb0, zb1, zt0, zt1):
    """Annular sector slab between bearings b0 < b1 (degrees clockwise from +Y). Bottom z at r0/r1 = zb0/zb1,
    top z at r0/r1 = zt0/zt1 (a banked top when they differ). n arc steps."""
    a0, a1 = math.radians(90.0 - b1), math.radians(90.0 - b0)    # CCW math angles
    full = abs((b1 - b0) - 360.0) < 1e-6
    cols = n if full else n + 1
    V, F = [], []
    for i in range(cols):
        a = a0 + (a1 - a0) * i / n
        c, s = math.cos(a), math.sin(a)
        V += [(r0 * c, r0 * s, zb0), (r1 * c, r1 * s, zb1), (r1 * c, r1 * s, zt1), (r0 * c, r0 * s, zt0)]
    for i in range(n):
        j = (i + 1) % cols
        ib, ob, ot, it = 4 * i, 4 * i + 1, 4 * i + 2, 4 * i + 3
        jb, jo, jt, ji = 4 * j, 4 * j + 1, 4 * j + 2, 4 * j + 3
        F += [(it, ot, jt, ji), (ib, jb, jo, ob), (ob, jo, jt, ot), (jb, ib, it, ji)]
    if not full:
        F.append((1, 2, 3, 0))
        k = 4 * n
        F.append((k, k + 3, k + 2, k + 1))
    return V, F


def bearing(b, r, z=0.0):
    a = math.radians(b)
    return Vector((r * math.sin(a), r * math.cos(a), z))


def M_place(origin, yaw_deg=0.0):
    """Matrix: rotate about Z by yaw (degrees, CCW from above, Blender convention), then translate."""
    return Matrix.Translation(Vector(origin)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")


def M_facing_centre(b, r, z=0.0):
    """Local +Y points at the hall centre; origin on bearing b at radius r."""
    return M_place(bearing(b, r, z), 180.0 - b)


def M_basis(u, w, origin):
    """Local (u, w, z) frame -> world: columns u, w, up."""
    u, w = Vector(u), Vector(w)
    return Matrix(((u.x, w.x, 0, origin[0]), (u.y, w.y, 0, origin[1]), (u.z, w.z, 1, origin[2]), (0, 0, 0, 1)))


# =============================================================================================== room 1: red room
RW, RD, RH = 30.0, 24.0, 20.0                  # interior 30 x 24, net at 20 (brief 2.3)
HX_IN, HX_OUT = 7.0, 7.9                       # hex frame apothems: 14 across the flats inside, 0.9 tube
NET_CELL, NET_BAR = 1.2, 0.25                  # the brief's net: 1.2-stud cells, 0.25-stud bars
NET_PITCH = NET_CELL + NET_BAR
NET_ANGLE = 45.0                               # degrees to the hex frame (critic #5b; the film's diamond read)
NET_RIDGE = 0.09                               # half height of the bars' diamond section (two faces built)
NET_SAG, NET_SAG_SPAN = 0.4, 4.0               # a slight sag: 0.4 stud at mid-span, full depth 4 studs from a fixing
NET_B_FIX = 21.45                              # the top net's fixings (walls and under the hex tube)
NET_A_FIX = 19.95                              # the room net's fixings (the walls' top channel)
DISC_R = 3.6                                   # 7.2 across: the arena's plate tube
ROOF_Z = (20.4, 20.9)                          # red roof panels between the two nets
RED_PITS = []                                  # (width, depth) of each red floor opening, in OpeningGlow order
RED_PITS_GRATE = []                            # (width, depth) of each grate lane, in GrateGlow order
DECK_KEY_POS = tuple(float(x) for x in os.environ.get("LAUNCH_DECK_POS", "11.0,-7.0,6.4").split(","))  # |x|, y, y
DECK_KEY_AIM = float(os.environ.get("LAUNCH_DECK_AIM", "8.0"))  # |x| each deck key aims at on the floor
DECK_KEY_DEG = float(os.environ.get("LAUNCH_DECK_DEG", "54"))   # the deck keys' cone angle (pass 2 review: 70 -> 54, so their blue stays off the apron)
HOOD_OUT = HX_IN + 0.3                         # the hood under the frame: 0.3 thick, flush with the frame's inner face
HOOD_Z0 = float(os.environ.get("LAUNCH_HOOD_Z0", "8.0"))    # its foot, 2.3 studs over the stand-in's head (the
#                                                frame's underside is at 21.6); frame B's deck camera never sees it


def hex_poly(apothem, n_extra=False):
    """Pointy-top hexagon (vertices on +-Y, flats on +-X). With n_extra, 12 points: vertices + edge midpoints."""
    R = apothem / math.cos(math.radians(30))
    pts = []
    for k in range(12 if n_extra else 6):
        if n_extra:
            ang = 30.0 * k
            rr = R if k % 2 == 1 else apothem
        else:
            ang = 30.0 + 60.0 * k
            rr = R
        pts.append((rr * math.cos(math.radians(ang)), rr * math.sin(math.radians(ang))))
    return pts


def rect_subtract(room, holes):
    """Rectangles covering room (x0, y0, x1, y1) minus the hole rectangles: cells on the breakpoint grid, merged
    along x within each row."""
    xs = sorted(set([room[0], room[2]] + [v for h in holes for v in (h[0], h[2]) if room[0] < v < room[2]]))
    ys = sorted(set([room[1], room[3]] + [v for h in holes for v in (h[1], h[3]) if room[1] < v < room[3]]))
    out = []
    for ya, yb in zip(ys[:-1], ys[1:]):
        run = None
        for xa, xb in zip(xs[:-1], xs[1:]):
            cx, cy = (xa + xb) / 2, (ya + yb) / 2
            inside = any(h[0] <= cx <= h[2] and h[1] <= cy <= h[3] for h in holes)
            if inside:
                if run:
                    out.append((run[0], ya, run[1], yb))
                    run = None
            else:
                run = (run[0], xb) if run else (xa, xb)
        if run:
            out.append((run[0], ya, run[1], yb))
    return out


def hex_half_x(y, apothem):
    R = apothem / math.cos(math.radians(30))
    ay = abs(y)
    if ay >= R:
        return None
    if ay <= R / 2:
        return apothem
    return apothem * (R - ay) / (R / 2)


def hex_half_y(x, apothem):
    R = apothem / math.cos(math.radians(30))
    ax = abs(x)
    if ax >= apothem:
        return None
    return R - ax * (R / 2) / apothem


_HEX_N = [(1.0, 0.0), (0.5, math.sqrt(3) / 2), (-0.5, math.sqrt(3) / 2)]   # the pointy-top hex's three edge normals


def hex_excess(x, y, apothem):
    """How far (x, y) lies outside the pointy-top hex of this apothem, measured to its edge lines (< 0 inside)."""
    return max(abs(nx * x + ny * y) for nx, ny in _HEX_N) - apothem


def net_sag(x, y, hw, hd):
    """0 at a fixing (the walls, the hex frame) rising to 1 a span NET_SAG_SPAN away: the net's sag shape."""
    d = min(hw - abs(x), hd - abs(y), hex_excess(x, y, HX_OUT))
    u = min(1.0, max(0.0, d / NET_SAG_SPAN))
    return 1.0 - (1.0 - u) * (1.0 - u)


def line_interval_in_rect(p0, d, hw, hd):
    """Parameter interval of the line p0 + s d inside |x| <= hw, |y| <= hd (None if it misses)."""
    lo, hi = -1e9, 1e9
    for k, h in ((0, hw), (1, hd)):
        if abs(d[k]) < 1e-12:
            if abs(p0[k]) > h:
                return None
            continue
        a, b = (-h - p0[k]) / d[k], (h - p0[k]) / d[k]
        lo, hi = max(lo, min(a, b)), min(hi, max(a, b))
    return (lo, hi) if hi > lo else None


def line_interval_in_hex(p0, d, apothem):
    lo, hi = -1e9, 1e9
    for nx, ny in _HEX_N:
        nd = nx * d[0] + ny * d[1]
        npp = nx * p0[0] + ny * p0[1]
        if abs(nd) < 1e-12:
            if abs(npp) > apothem:
                return None
            continue
        a, b = (-apothem - npp) / nd, (apothem - npp) / nd
        lo, hi = max(lo, min(a, b)), min(hi, max(a, b))
    return (lo, hi) if hi > lo else None


def build_net45(mb, key, z_fix, sag, cut, hw, hd, ridge_up, every=1):
    """The brief's net: two families of bars at +-NET_ANGLE to the hex frame (pitch NET_PITCH, width NET_BAR), clear
    of the hex opening (apothem `cut`), following a sagging surface z = z_fix - sag * net_sag(x, y). Each bar is the
    two faces of a diamond section facing the viewer (ridge up for the net seen from above, down for the net seen
    from the room), with a vertex at every `every`-th crossing so the bars bend with the sag."""
    a = math.radians(NET_ANGLE)
    fam = [((math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))),       # (along, across), along x across = +z
           ((-math.sin(a), math.cos(a)), (-math.cos(a), -math.sin(a)))]
    n = int(math.hypot(hw, hd) / NET_PITCH) + 2
    offs = [(k + 0.5) * NET_PITCH for k in range(-n, n)]
    hb = NET_BAR / 2.0
    ridge = NET_RIDGE if ridge_up else -NET_RIDGE

    def z_at(x, y):
        return z_fix - sag * net_sag(x, y, hw, hd)
    for (ux, uy), (vx, vy) in fam:
        v = mb.vol()
        for c in offs:
            p0 = (c * vx, c * vy)
            iv = line_interval_in_rect(p0, (ux, uy), hw, hd)
            if iv is None:
                continue
            spans = [iv]
            hx_iv = line_interval_in_hex(p0, (ux, uy), cut)
            if hx_iv is not None:
                spans = [(s0, min(s1, hx_iv[0])) for s0, s1 in spans if s0 < hx_iv[0]] + \
                        [(max(s0, hx_iv[1]), s1) for s0, s1 in spans if s1 > hx_iv[1]]
            for s0, s1 in spans:
                if s1 - s0 < 0.3:
                    continue
                cross = [s for s in offs if s0 + 0.05 < s < s1 - 0.05][::every]
                ss = [s0] + cross + [s1]
                V, F = [], []
                for s in ss:
                    x, y = p0[0] + s * ux, p0[1] + s * uy
                    z = z_at(x, y)
                    V += [(x - hb * vx, y - hb * vy, z), (x, y, z + ridge), (x + hb * vx, y + hb * vy, z)]
                for i in range(len(ss) - 1):
                    b0, b1 = 3 * i, 3 * (i + 1)
                    if ridge_up:      # faces point up
                        F += [(b0, b1, b1 + 1, b0 + 1), (b0 + 1, b1 + 1, b1 + 2, b0 + 2)]
                    else:             # faces point down
                        F += [(b0, b0 + 1, b1 + 1, b1), (b0 + 1, b0 + 2, b1 + 2, b1 + 1)]
                mb.add((V, F), key, None, v)


def build_red_room(rng):
    P = {k: MB(k) for k in ("Shell", "Roof", "NetA", "NetB", "HexFrame", "Hood", "Deck", "Grates", "Rails", "Lamps",
                            "Stairs", "Lift")}
    P["LampLights"] = MB("LampLights", "neon")
    shell, roof, deck, grates, rails = P["Shell"], P["Roof"], P["Deck"], P["Grates"], P["Rails"]
    hw, hd = RW / 2, RD / 2
    atts = {}

    # ---- walls: local (u along the wall, w into the room, z up); interior face at w = 0
    walls = [  # (u axis, w axis, origin, length, name)
        ((1, 0, 0), (0, 1, 0), (0, -hd, 0), RW, "front"),
        ((-1, 0, 0), (0, -1, 0), (0, hd, 0), RW, "back"),
        ((0, 1, 0), (-1, 0, 0), (hw, 0, 0), RD, "right"),
        ((0, -1, 0), (1, 0, 0), (-hw, 0, 0), RD, "left"),
    ]
    door_u = (-10.5, -6.5)                       # front wall door opening (4 x 7.5)
    for u_ax, w_ax, org, L, name in walls:
        M = M_basis(u_ax, w_ax, org)
        v = shell.vol()
        shell.add(g_box(-L / 2 - 1.0, -1.0, -0.6, L / 2 + 1.0, -0.3, 22.2), "oxblood_dk", M, v)   # backing
        # concrete base course 1.6 high, 0.4 proud
        cuts = [door_u] if name == "front" else []
        segs = [(-L / 2, L / 2)]
        for c0, c1 in cuts:
            segs = [(a, c0) for a, b in segs if a < c0] + [(c1, b) for a, b in segs if b > c1]
        for a, b in segs:
            shell.add(g_box(a, -0.3, 0.0, b, 0.4, 1.6), "concrete", M)
        # oxblood panels, two tiers, about 3 wide with 0.2 joints
        n = max(1, int(round(L / 3.0)))
        pw = L / n
        for i in range(n):
            u0, u1 = -L / 2 + i * pw + 0.1, -L / 2 + (i + 1) * pw - 0.1
            for z0, z1 in ((1.6, 10.0), (10.2, 18.6)):
                if name == "front" and z0 < 8.5 and u1 > door_u[0] - 0.9 and u0 < door_u[1] + 0.9:
                    continue
                shell.add(g_box(u0, -0.3, z0 + 0.05, u1, 0.0, z1 - 0.05), "oxblood", M)
        # dark steel channel along the top, where the roof net is fixed
        shell.add(g_box(-L / 2, -0.3, 18.6, L / 2, 0.3, 20.0), "net", M)
        # parapet above the roof so the establishing camera never sees past the edges
        shell.add(g_box(-L / 2 - 0.3, -0.3, 21.3, L / 2 + 0.3, 0.45, 22.2), "net", M)
        # thin red vertical pipes on the walls (frame A)
        for pu in ((-L / 2 + 2.2, L / 2 - 2.2) if L > 25 else (-L / 2 + 2.2,)):
            if name == "front" and door_u[0] - 1 < pu < door_u[1] + 1:
                continue
            rails.add(g_tube((pu, 0.5, 1.6), (pu, 0.5, 18.6), 0.2, 8), "rail", M)
            for pz in (3.0, 10.0, 17.0):
                rails.add(g_box(pu - 0.15, 0.0, pz - 0.15, pu + 0.15, 0.4, pz + 0.15), "rail", M)
        if name == "front":
            u0, u1 = door_u
            shell.add(g_box(u0 - 0.8, -0.3, 0.0, u0, 0.35, 8.3), "concrete", M)          # jambs
            shell.add(g_box(u1, -0.3, 0.0, u1 + 0.8, 0.35, 8.3), "concrete", M)
            shell.add(g_box(u0 - 0.8, -0.3, 7.5, u1 + 0.8, 0.35, 8.5), "concrete", M)     # lintel
            shell.add(g_box(u0, -0.75, 0.0, u1, -0.45, 7.5), "door", M)                    # recessed leaf
            shell.add(g_box(u0 + 1.2, -0.45, 5.0, u1 - 1.2, -0.35, 6.4), "grate", M)       # vision slot
            shell.add(g_box(u0 + 0.3, -0.45, 3.4, u0 + 0.7, -0.2, 4.4), "concrete", M)     # handle
            # intercom: grey box, speaker slots, a red call lamp
            shell.add(g_box(3.3, 0.0, 4.2, 4.7, 0.35, 6.4), "door", M)
            for k in range(3):
                shell.add(g_box(3.6, 0.35, 5.2 + 0.3 * k, 4.4, 0.42, 5.35 + 0.3 * k), "grate", M)
            P["Lamps"].add(g_box(3.75, 0.35, 4.45, 4.25, 0.5, 4.8), "lamp", M)
            atts["Intercom"] = (M @ Vector((4.0, 0.5, 5.3)), M.to_3x3() @ Vector((0, 1, 0)))

    # ---- roof: red panels between a lower net (seen from the room) and an upper net (seen from above, frame A)
    hp = hex_poly(HX_OUT)
    corners = [(hw + 0.3, hd + 0.3), (-hw - 0.3, hd + 0.3), (-hw - 0.3, -hd - 0.3), (hw + 0.3, -hd - 0.3)]

    def ray_rect(a):
        c, s = math.cos(a), math.sin(a)
        t = min((hw + 0.3) / abs(c) if abs(c) > 1e-9 else 1e9, (hd + 0.3) / abs(s) if abs(s) > 1e-9 else 1e9)
        return (t * c, t * s)
    for k in range(6):
        a0 = math.atan2(hp[k][1], hp[k][0])
        a1 = math.atan2(hp[(k + 1) % 6][1], hp[(k + 1) % 6][0])
        if a1 <= a0:
            a1 += TAU
        poly = [hp[k], ray_rect(a0)]
        cs = []
        for cx, cy in corners:
            ca = math.atan2(cy, cx)
            while ca < a0:
                ca += TAU
            if a0 < ca < a1:
                cs.append((ca, (cx, cy)))
        poly += [p for _, p in sorted(cs)]
        poly += [ray_rect(a1), hp[(k + 1) % 6]]
        roof.add(g_prism(poly, ROOF_Z[0], ROOF_Z[1]), "oxblood")
    # (pass 1's batten grid is gone: under the fine 45-degree net it fought the net's lines)

    # the net, to the brief's spec (critic #5b): 1.2-stud cells, 0.25-stud bars, 45 degrees to the hex frame, with a
    # slight sag between its fixings. NetA hangs under the roof (seen from the room, ridges down); NetB is stretched
    # over the roof panels on supports at the walls and under the hex tube (frame A, ridges up) and runs in under
    # the tube.
    build_net45(P["NetA"], "net", NET_A_FIX, NET_SAG, HX_OUT + 0.05, hw, hd, ridge_up=False, every=2)
    build_net45(P["NetB"], "net", NET_B_FIX, NET_SAG, HX_OUT - 0.2, hw, hd, ridge_up=True, every=2)

    # ---- hexagonal frame of square teal tube (mouth of the lift), gussets and bolts on top
    hexf = P["HexFrame"]
    HZ0, HZ1 = 21.6, 22.5                                    # the 0.9 square tube sits on the roof
    hexf.add(g_annulus(hex_poly(HX_OUT), hex_poly(HX_IN), HZ0, HZ1), "hex")
    for k in range(6):
        ang = 30.0 + 60.0 * k
        mid = (HX_IN + HX_OUT) / 2 / math.cos(math.radians(30))
        c = Vector((mid * math.cos(math.radians(ang)), mid * math.sin(math.radians(ang)), HZ1))
        M = M_place(c, ang - 90.0)
        v = hexf.vol()
        hexf.add(g_prism(p_crect(0, 0, 1.6, 1.3, 0.35), 0.0, 0.14), "bolt", M, v)
        for bx in (-0.45, 0.45):
            hexf.add(g_prism(p_ngon(0.17, 6, cx=bx, cy=0.1), 0.14, 0.3), "bolt", M, v)
        # a bolted joint plate down the outer face of each corner
        Mo = M_place(Vector((HX_OUT / math.cos(math.radians(30)) * math.cos(math.radians(ang)),
                             HX_OUT / math.cos(math.radians(30)) * math.sin(math.radians(ang)), HZ0)), ang - 90.0)
        hexf.add(g_box(-0.7, -0.05, 0.05, 0.7, 0.12, 0.85), "bolt", Mo, v)
    # (no sleeve: the roof prisms close the opening's edge themselves, and a sleeve read as a teal band from above)
    # ---- the drop under the frame (pass 2 review fix, frame A): the film looks down through the hexagon into a
    # narrow oxblood shaft with thin red vertical rails (T1 @120.2 s), not onto the steel deck, so an oxblood hood lines
    # the drop from the frame down to HOOD_Z0, with a thin rail on each corner and down the middle of each panel. Its
    # foot stays above the deck camera of frame B (y 10.6) and the walkway's rail; the lift rises up through it.
    hood = P["Hood"]
    hood.add(g_annulus(hex_poly(HOOD_OUT), hex_poly(HX_IN), HOOD_Z0, HZ0), "oxblood")
    vr = hood.vol()
    for k in range(6):                     # one rail down the middle of each panel (the film's thin vertical rails)
        c, s = math.cos(math.radians(60.0 * k)), math.sin(math.radians(60.0 * k))
        rr = HX_IN - 0.14
        hood.add(g_beam((rr * c, rr * s, HOOD_Z0 + 0.3), (rr * c, rr * s, HZ0 - 0.1), sec_rect(0.25, 0.25),
                        up=(c, s, 0.0)), "rail", None, vr)
    atts["KeyLight"] = (Vector((0, 0, 34.0)), Vector((0, 0, -1)))
    atts["CamTopDown"] = (Vector((0, -2.5, 25.5)), Vector((0, 0.35, -1)).normalized())

    # ---- floor: lift apron (oxblood), steel deck plates, white stripes, grates over red mesh
    lift = P["Lift"]
    lift.add(g_prism(p_ngon(DISC_R, 24), -0.5, 0.15), "rose")
    lift.add(g_annulus(p_ngon(DISC_R - 0.45, 24), p_ngon(DISC_R - 0.7, 24), 0.15, 0.22), "oxblood_dk")
    atts["Spawn"] = (Vector((0, 0, 0.15)), Vector((0, 1, 0)))
    # apron round the lift (inside the rails): 4 quarter plates with a round hole r 3.8
    base_q = ([(3.8, 0.0), (7.25, 0.0), (7.25, 4.2), (0.0, 4.2), (0.0, 3.8)]
              + [(3.8 * math.cos(math.radians(a)), 3.8 * math.sin(math.radians(a))) for a in (75, 60, 45, 30, 15)])
    for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        poly = [(sx * x, sy * y) for x, y in base_q]
        if sx * sy < 0:
            poly.reverse()
        deck.add(g_prism(poly, -0.4, 0.0), "oxblood_dk")
    deck.add(g_prism(p_ngon(3.8, 24), -0.9, -0.5), "grate")                 # lift well floor
    # steel deck plates (explicit layout round the features), 0.12 seams
    xs = [-15.0, -10.5]
    plates = []
    for yy in range(6):                                                     # side walkways
        y0, y1 = -12.0 + 4 * yy, -12.0 + 4 * (yy + 1)
        plates += [(-15.0, y0, -10.5, y1), (10.5, y0, 15.0, y1)]
    band = [(-12.0, -9.6), (-9.6, -5.0), (-5.0, -4.2), (-4.2, 4.2), (4.2, 5.0), (5.0, 9.6), (9.6, 12.0)]
    for y0, y1 in band:
        if (y0, y1) in ((-9.6, -5.0), (5.0, 9.6)):
            plates += [(-10.0, y0, -7.6, y1), (-0.25, y0, 0.25, y1), (7.6, y0, 10.0, y1)]
        elif (y0, y1) == (-4.2, 4.2):            # thin plates under the rail posts; red-mesh pits beyond them
            plates += [(-7.5, -4.2, -7.25, 0.0), (-7.5, 0.0, -7.25, 4.2), (7.25, -4.2, 7.5, 0.0),
                       (7.25, 0.0, 7.5, 4.2)]
        else:
            for k in range(4):
                plates.append((-10.0 + 5 * k, y0, -10.0 + 5 * (k + 1), y1))
    for x0, y0, x1, y1 in plates:
        deck.add(g_box(x0 + 0.06, y0 + 0.06, -0.4, x1 - 0.06, y1 - 0.06, 0.0), "deck")
    # thin dark substrate that shows in the seams, with the pits and the lift well left open
    holes = [(-7.6, -9.6, -0.25, -5.0), (0.25, -9.6, 7.6, -5.0), (-7.6, 5.0, -0.25, 9.6), (0.25, 5.0, 7.6, 9.6),
             (-10.0, -4.2, -7.5, 4.2), (7.5, -4.2, 10.0, 4.2), (-3.8, -3.8, 3.8, 3.8)]
    for x0, y0, x1, y1 in rect_subtract((-hw, -hd, hw, hd), holes):
        deck.add(g_box(x0, y0, -0.62, x1, y1, -0.42), "grate")
    for x0, x1 in ((-10.5, -10.0), (10.0, 10.5)):                           # white stripes (frame B)
        deck.add(g_box(x0, -hd, -0.38, x1, hd, 0.02), "stripe")
    for y0, y1 in ((-9.6, -5.0), (5.0, 9.6)):                                # stripes round the grate lanes
        for yy in (y0 - 0.05, y1 + 0.05):
            deck.add(g_box(-7.6, yy - 0.18, -0.38, 7.6, yy + 0.18, 0.02), "stripe")
    # floor pits (critic #5b, frame B). The four lanes ahead of and behind the lift carry black square-mesh grates
    # flush with the deck over a dark pit: they read black, with no red under them. The two openings beside the lift
    # are the only red: a dark pit with a red mesh stretched across it at 45 degrees, lit from inside. The Deck
    # part's Box collider spans the pits, so all of them are walkable.
    gi = 0
    pits = [(-7.6, -9.6, -0.25, -5.0, "grate"), (0.25, -9.6, 7.6, -5.0, "grate"), (-7.6, 5.0, -0.25, 9.6, "grate"),
            (0.25, 5.0, 7.6, 9.6, "grate"), (-10.0, -4.2, -7.5, 4.2, "opening"), (7.5, -4.2, 10.0, 4.2, "opening")]
    RED_PITS[:] = [(x1 - x0, y1 - y0) for x0, y0, x1, y1, kind in pits if kind == "opening"]
    RED_PITS_GRATE.clear()
    for x0, y0, x1, y1, kind in pits:
        v = grates.vol()
        z_floor = -2.6 if kind == "grate" else -1.7          # the grate lanes are deep dark pits: they read black
        grates.add(g_prism([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z_floor - 0.1, z_floor), "grate", None, v)
        for wx0, wy0, wx1, wy1 in ((x0, y0, x1, y0 + 0.12), (x0, y1 - 0.12, x1, y1),
                                   (x0, y0, x0 + 0.12, y1), (x1 - 0.12, y0, x1, y1)):
            grates.add(g_box(wx0, wy0, z_floor, wx1, wy1, -0.35), "grate", None, v)       # pit walls
        vb = grates.vol()
        rim = 0.35
        grates.add(g_box(x0, y0, -0.35, x1, y0 + rim, 0.0), "grate", None, vb)          # rim
        grates.add(g_box(x0, y1 - rim, -0.35, x1, y1, 0.0), "grate", None, vb)
        grates.add(g_box(x0, y0 + rim, -0.35, x0 + rim, y1 - rim, 0.0), "grate", None, vb)
        grates.add(g_box(x1 - rim, y0 + rim, -0.35, x1, y1 - rim, 0.0), "grate", None, vb)
        if kind == "grate":                                     # black square mesh: 0.25 bars at 0.9, mostly open
            # (review fix) a dim navy light under each lane's mesh, facing the pit floor, so the void reads navy-black
            # through the bars as in the film's frame B, with no red under any grate
            gl_n = sum(1 for k_ in atts if k_.startswith("GrateGlow_")) + 1
            atts["GrateGlow_%d" % gl_n] = (Vector(((x0 + x1) / 2, (y0 + y1) / 2, -0.45)), Vector((0, 0, -1)))
            RED_PITS_GRATE.append((x1 - x0, y1 - y0))
            nb = int(round((y1 - y0 - 2 * rim) / 0.9)) - 1
            for k in range(1, nb + 1):
                yy = y0 + rim + k * (y1 - y0 - 2 * rim) / (nb + 1)
                grates.add(g_box(x0 + rim, yy - 0.125, -0.3, x1 - rim, yy + 0.125, -0.02), "grate", None, vb)
            nc = int(round((x1 - x0 - 2 * rim) / 0.9)) - 1
            for k in range(1, nc + 1):
                xx = x0 + rim + k * (x1 - x0 - 2 * rim) / (nc + 1)
                grates.add(g_box(xx - 0.125, y0 + rim, -0.32, xx + 0.125, y1 - rim, -0.04), "grate", None, vb)
            continue
        # the opening's red mesh: square bars at 45 degrees, pitch NET_PITCH, 0.6 under the deck, clipped to the pit
        gi += 1
        vm = grates.vol()
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hx_, hy_ = (x1 - x0) / 2 - 0.12, (y1 - y0) / 2 - 0.12
        a = math.radians(NET_ANGLE)
        n = int(math.hypot(hx_, hy_) / NET_PITCH) + 2
        for (ux, uy), (vx, vy) in (((math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))),
                                   ((-math.sin(a), math.cos(a)), (-math.cos(a), -math.sin(a)))):
            for k in range(-n, n):
                c = (k + 0.5) * NET_PITCH
                iv = line_interval_in_rect((c * vx, c * vy), (ux, uy), hx_, hy_)
                if iv is None or iv[1] - iv[0] < 0.3:
                    continue
                pa = Vector((cx + c * vx + iv[0] * ux, cy + c * vy + iv[0] * uy, -0.62))
                pb = Vector((cx + c * vx + iv[1] * ux, cy + c * vy + iv[1] * uy, -0.62))
                grates.add(g_beam(pa, pb, sec_rect(NET_BAR, 0.22)), "redmesh", None, vm)
        # the glow: a dim red light low in the opening, aimed up through the mesh (the only red light in the room)
        atts["OpeningGlow_%d" % gi] = (Vector((cx, cy, z_floor + 0.25)), Vector((0, 0, 1)))

    # ---- rails: a U round the lift (open at the back), the far rail with the lamp post, walkway and stairs
    def rail_run(pts, top=3.6, mid=1.8, posts=None, r=0.22):
        v = rails.vol()
        for a, b in zip(pts[:-1], pts[1:]):
            for hz in (top, mid):
                rails.add(g_tube((a[0], a[1], a[2] + hz), (b[0], b[1], b[2] + hz), r, 8), "rail", None, v)
        for p in (posts if posts is not None else pts):
            rails.add(g_tube((p[0], p[1], p[2]), (p[0], p[1], p[2] + top + r), r, 6), "rail", None, v)
            rails.add(g_prism(p_ngon(0.42, 6, cx=p[0], cy=p[1]), p[2], p[2] + 0.12), "rail", None, v)
    rail_run([(-7.25, -4.4, 0), (-7.25, 4.6, 0), (7.25, 4.6, 0), (7.25, -4.4, 0)],
             posts=[(-7.25, -4.4, 0), (-7.25, 0.1, 0), (-7.25, 4.6, 0), (7.25, 4.6, 0), (7.25, 0.1, 0),
                    (7.25, -4.4, 0)])
    rail_run([(-10.0, 9.95, 0), (10.0, 9.95, 0)], posts=[(-10.0, 9.95, 0), (-5.0, 9.95, 0), (0.0, 9.95, 0),
                                                        (5.0, 9.95, 0), (10.0, 9.95, 0)])
    rail_run([(-10.0, -9.95, 0), (10.0, -9.95, 0)], posts=[(-10.0, -9.95, 0), (0.0, -9.95, 0),
                                                          (10.0, -9.95, 0)])
    # upper walkway along the back wall at 10, concrete stairs up the right wall
    st = P["Stairs"]
    WZ = 10.0
    st.add(g_box(-hw, 8.4, WZ - 0.5, 11.9, hd, WZ), "deck")
    st.add(g_box(-hw, 8.4, WZ - 1.2, 11.9, 8.7, WZ - 0.5), "net")                      # fascia
    for bx in (-11.0, -3.0, 5.0):                                                       # gussets (y, z) x 0.5
        st.add(g_prism([(8.6, WZ - 1.2), (hd, WZ - 4.5), (hd, WZ - 1.2)], 0, 0.5), "net",
               Matrix(((0, 0, 1, bx), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    n_st = 13
    y_a, y_b = -7.0, 8.4
    for k in range(n_st):
        z1 = WZ * (k + 1) / n_st
        ya = y_a + (y_b - y_a) * k / n_st
        yb = y_a + (y_b - y_a) * (k + 1) / n_st
        st.add(g_box(12.0, ya, max(0.0, z1 - 1.6), hw, yb + 0.02, z1), "concrete")
    st.add(g_box(11.9, 8.4, 0.0, hw, hd, WZ - 0.5), "concrete")                          # landing block
    st.add(g_prism([(y_a, 0.0), (y_b, 0.0), (y_b, WZ - 0.4)], 0, 0.5), "concrete",
           Matrix(((0, 0, 1, 11.5), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))            # stringer
    rail_run([(-hw, 8.55, WZ), (11.9, 8.55, WZ)],
             posts=[(-hw + 0.3, 8.55, WZ), (-9.0, 8.55, WZ), (-3.0, 8.55, WZ), (3.0, 8.55, WZ),
                    (9.0, 8.55, WZ), (11.9, 8.55, WZ)])
    # stair rail (sloped), on the open side of the stair
    v = rails.vol()
    for hz in (3.6, 1.8):
        rails.add(g_tube((11.85, y_a, hz), (11.85, y_b, WZ + hz), 0.22, 8), "rail", None, v)
    for t in (0.0, 0.5, 1.0):
        y = y_a + (y_b - y_a) * t
        z = WZ * t if t < 1 else WZ
        rails.add(g_tube((11.85, y, z), (11.85, y, z + 3.8), 0.22, 8), "rail", None, v)
    atts["GuardWalkway"] = (Vector((-6.0, 10.5, WZ)), Vector((0, -1, 0)))
    atts["EscortWalkway"] = (Vector((0.0, 10.4, WZ)), Vector((0, -1, 0)))
    atts["GuardFloor"] = (Vector((5.0, 10.9, 0.0)), Vector((0, -1, 0)))     # beyond the far rail, as in frame B
    # the walkway's spot hangs over the walkway, outside the hood (pass 1 hung it in the tube mouth)
    atts["WalkwaySpot"] = (Vector((-4.0, 10.6, 19.4)), (Vector((-5.0, 11.2, WZ)) - Vector((-4.0, 10.6, 19.4))).normalized())
    # the cool blue-white keys over the deck (pass 2, TwoArenas 2.8): four spots under the net ceiling, one over each
    # grate lane's outer half, so the steel reads blue and its shadows go blue (frame B)
    # (review fix) each key leans in toward the middle of its grate lane, so the blue light reaches the grate bars
    dkx, dky0, dky1 = DECK_KEY_POS
    for k, (kx, ky) in enumerate(((-dkx, dky0), (dkx, dky0), (-dkx, dky1), (dkx, dky1))):
        aim = Vector((math.copysign(DECK_KEY_AIM, kx), ky, 0.0))
        atts["DeckKey_%d" % (k + 1)] = (Vector((kx, ky, 18.9)), (aim - Vector((kx, ky, 18.9))).normalized())

    # ---- lamp housings (red, round fronts) with white lenses: a pair on the far rail's centre post (frame B)
    lamps, lens = P["Lamps"], P["LampLights"]
    li = 0

    def lamp(pos, facing_deg):
        nonlocal li
        li += 1
        M = M_place(pos, facing_deg)
        v = lamps.vol()
        lamps.add(g_beam((0, -0.75, 0), (0, 0.55, 0), p_ngon(0.85, 8)), "lamp", M, v)
        lamps.add(g_beam((0, 0.55, 0), (0, 0.75, 0), p_ngon(0.95, 8)), "lamp", M, v)
        lens.add(g_beam((0, 0.75, 0), (0, 0.86, 0), p_ngon(0.62, 8)), "lens", M)
        w = M @ Vector((0, 1.1, 0))
        atts["Lamp_%d" % li] = (w, M.to_3x3() @ Vector((0, 1, 0)))
    for sx in (-1.05, 1.05):                         # pair facing the lift (front = -Y towards the player)
        lamp((sx, 10.15, 4.75), 180.0)
    rails.add(g_box(-1.9, 9.6, 3.85, 1.9, 10.4, 4.0), "rail")                              # lamp bracket
    for x_w, yaw in ((hw - 0.75, 90.0), (-hw + 0.75, -90.0)):
        for dz in (0.0, 1.9):
            lamp((x_w, 4.0, 13.0 + dz), yaw)
    for x_b in (-8.0, 8.0):                          # under the walkway, facing the room
        lamp((x_b, hd - 0.85, 7.0), 180.0)
    return P, atts


# =============================================================================================== room 2: case hall
CASE_R = 110.0                    # bay centres
N_BAYS = 48
BAY_STEP = 360.0 / N_BAYS         # 7.5 deg, 14.4 studs apart at r 110
BAY_OFF = BAY_STEP / 2            # bays sit between the 45-degree segment seams
CW, CDp, CH = 4.3, 4.8, 11.0      # case width (x), depth (y), height
DISC_Y = 0.3                      # disc centre in the bay frame (toward the hall centre)
DISC_TOP = 1.6
POLE_Y = -1.7                     # pole axis in the bay frame (behind the disc)
GANTRY_Z = 16.0
UNIT_SETBACK = 1.8                # the maroon wall unit stands this far behind the case line (pass 2)
GANTRY_ROWS = (97.4, 99.7, 117.8)  # strip-light rows: two over the inner walkway, one behind the cases; the case
                                   # fronts (r 100.8-115.6) stay clear for the rise and the orbiting camera


def bay_bearing(i):
    return BAY_OFF + BAY_STEP * i


def build_case_bay():
    P = {"Frame": MB("Frame"), "Glass": MB("Glass", "glass"), "Light": MB("Light", "neon"), "Unit": MB("Unit"),
         "Collider": MB("Collider", "collider")}
    fr, gl, lt, un = P["Frame"], P["Glass"], P["Light"], P["Unit"]
    hx, hy = CW / 2, CDp / 2
    fr.add(g_prism(p_crect(0, 0, CW + 0.4, CDp + 0.4, 0.25), 0.0, 0.4), "plinth")
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (hx - 0.4), sy * (hy - 0.4)
            fr.add(g_prism(p_crect(cx, cy, 0.8, 0.8, 0.12), 0.4, CH), "post")
            fr.add(g_prism(p_crect(cx, cy, 0.9, 0.9, 0.14), CH, CH + 0.18), "post")      # caps
    # kick plates and top rails of the glass (dark)
    fr.add(g_box(-hx + 0.8, hy - 0.2, 0.4, hx - 0.8, hy, 0.9), "plinth")
    for x0, x1 in ((-hx, -hx + 0.2), (hx - 0.2, hx)):
        fr.add(g_box(x0, -hy + 0.8, 0.4, x1, hy - 0.8, 0.9), "plinth")
    gl.add(g_box(-hx + 0.8, hy - 0.16, 0.9, hx - 0.8, hy - 0.04, 10.2), "glass")
    gl.add(g_box(-hx + 0.04, -hy + 0.8, 0.9, -hx + 0.16, hy - 0.8, 10.2), "glass")
    gl.add(g_box(hx - 0.16, -hy + 0.8, 0.9, hx - 0.04, hy - 0.8, 10.2), "glass")
    # front top-light bar (thin, outside the disc's path) and its dark carrier
    fr.add(g_box(-hx + 0.8, hy - 0.22, 10.2, hx - 0.8, hy, 10.95), "plinth")
    lt.add(g_box(-hx + 0.95, hy - 0.3, 10.25, hx - 0.95, hy - 0.2, 10.55), "light")
    # pedestal (the disc rests on it until the rise)
    fr.add(g_prism(p_ngon(0.55, 8, cx=0, cy=DISC_Y), 0.4, DISC_TOP - 0.4), "plinth")
    fr.add(g_prism(p_ngon(1.0, 12, cx=0, cy=DISC_Y), 0.4, 0.55), "plinth")
    # pole foot plate behind the disc
    fr.add(g_prism(p_ngon(0.95, 12, cx=0, cy=POLE_Y), 0.4, 0.62), "plinth")
    # maroon wall unit in the gap to the left (bearing -3.75 deg from the bay), facing the walkway
    a = math.radians(BAY_STEP / 2)
    ux, uy = -CASE_R * math.sin(a), CASE_R - CASE_R * math.cos(a)
    # pass 2: set back 1.8 studs behind the case line, so the row of cases reads as cases with posts between them
    # (T1 @125.9 s) and a view along the row from inside a case passes in front of the units
    M = M_place((ux, uy, 0.0), -BAY_STEP / 2) @ Matrix.Translation((0.0, -UNIT_SETBACK, 0.0))
    v = un.vol()
    un.add(g_prism(p_crect(0, -0.4, 3.4, 1.6, 0.3), 0.0, 0.5), "plinth", M, v)
    for sx in (-1, 1):
        un.add(g_prism(p_crect(sx * 1.3, -0.4, 0.8, 1.4, 0.12), 0.5, 7.4), "unit", M, v)
    un.add(g_beam((-1.7, -0.4, 7.4), (1.7, -0.4, 7.4), [(-0.7, 0), (0.7, 0), (0.7, 1.0), (0.4, 1.5), (-0.4, 1.5), (-0.7, 1.0)]),
           "unit", M, v)                                                                        # arched head
    un.add(g_box(-0.9, -1.0, 0.5, 0.9, -0.6, 7.4), "shell_case", M, v)                          # dark recess
    un.add(g_box(-0.9, -0.45, 0.5, 0.9, 0.2, 3.6), "unit", M, v)                                # cabinet
    lt.add(g_beam((-1.05, 0.33, 8.25), (1.05, 0.33, 8.25), p_ngon(0.3, 8, sx=1.0, sy=1.0)), "light", M)
    # back collider (invisible): keeps the player in the case while frozen; the game turns it off at the rise
    P["Collider"].add(g_box(-hx, -hy, 0.4, hx, -hy + 0.15, 9.0), "glass")
    atts = {
        "Stand": (Vector((0, DISC_Y, DISC_TOP)), Vector((0, 1, 0))),
        "CaseLight": (Vector((0, hy - 0.3, 10.2)), Vector((0, -0.3, -1)).normalized()),
        "PoleBase": (Vector((0, POLE_Y, 0.4)), Vector((0, 0, 1))),
        "UnitLight": (M @ Vector((0, 0.5, 8.25)), M.to_3x3() @ Vector((0, 1, 0))),
        "CamCase": (Vector((0, DISC_Y + 6.8, 6.0)), Vector((0, -1, 0))),
    }
    return P, atts


def build_riser_disc():
    P = {"Disc": MB("Disc"), "Collar": MB("Collar")}
    d, c = P["Disc"], P["Collar"]
    v = d.vol()
    d.add(g_prism(p_ngon(1.8, 24), -0.4, 0.0), "case_disc", None, v)
    d.add(g_annulus(p_ngon(1.86, 24), p_ngon(1.62, 24), -0.48, -0.04), "disc_rim")
    d.add(g_prism(p_ngon(1.25, 12), -0.85, -0.4), "disc_rim")
    py = POLE_Y - DISC_Y
    c.add(g_annulus(p_ngon(0.95, 12, cx=0, cy=py), p_ngon(0.72, 12, cx=0, cy=py), -1.3, 0.05), "steel")
    c.add(g_box(-0.45, -1.5, -0.95, 0.45, -0.6, -0.4), "steel")
    atts = {"Stand": (Vector((0, 0, 0)), Vector((0, 1, 0))), "PoleAxis": (Vector((0, py, 0)), Vector((0, 0, 1)))}
    return P, atts


def build_case_gallery():
    P = {"Walkway": MB("Walkway"), "Gantry": MB("Gantry"), "Lights": MB("Lights", "neon")}
    w, g, lt = P["Walkway"], P["Gantry"], P["Lights"]
    seg = 45.0
    front = CASE_R - CDp / 2 - 0.2          # 107.4: the case plinth front
    for k in range(6):
        b0, b1 = k * BAY_STEP, (k + 1) * BAY_STEP
        w.add(g_sector(98.6, front, b0 + 0.04, b1 - 0.04, 2, -0.3, -0.3, 0.4, 0.4), "walkway")
        w.add(g_sector(97.8, 98.6, b0 + 0.04, b1 - 0.04, 2, -0.3, -0.3, 0.42, 0.42), "wedge_pale")   # kerb
        w.add(g_sector(CASE_R + CDp / 2 + 0.2, 119.6, b0 + 0.04, b1 - 0.04, 2, -0.3, -0.3, 0.4, 0.4), "plinth")
    # the floor between the cases (pass 2: the wall units now stand set back in these gaps)
    half_case = math.degrees((CW / 2 + 0.2) / CASE_R)
    for k in range(7):
        g0, g1 = max(0.0, k * BAY_STEP - (BAY_STEP / 2 - half_case)), min(seg, k * BAY_STEP + (BAY_STEP / 2 - half_case))
        if g1 - g0 > 0.1:
            w.add(g_sector(front, CASE_R + CDp / 2 + 0.2, g0 + 0.02, g1 - 0.02, 1, -0.3, -0.3, 0.4, 0.4), "walkway")
    w.add(g_sector(119.6, 120.4, 0, seg, 6, -0.3, -0.3, 3.2, 3.2), "shell_case")                    # back screen
    # gantry: rows of strip lights over the inner walkway and behind the cases (the case fronts stay clear for
    # the rise and the orbiting camera), radial ties at the bay seams, columns every 15 degrees
    for k in range(6):
        b = k * BAY_STEP
        for r0, r1 in ((96.0, 100.8), (115.6, 120.0)):
            g.add(g_beam(bearing(b, r0, GANTRY_Z + 0.5), bearing(b, r1, GANTRY_Z + 0.5), sec_rect(0.6, 0.8)), "shell_case")
    for k in range(6):
        b0, b1 = k * BAY_STEP, (k + 1) * BAY_STEP
        for r in (96.6, 100.4, 116.2, 119.4):
            g.add(g_beam(bearing(b0, r, GANTRY_Z + 0.5), bearing(b1, r, GANTRY_Z + 0.5), sec_rect(0.5, 0.7)), "shell_case")
        for r in GANTRY_ROWS:                    # rows of short strip lights (three tubes per bay per row)
            span = (b1 - 0.6) - (b0 + 0.6)
            for j in range(3):
                ba = b0 + 0.6 + span * (j + 0.14) / 3.0
                bb = b0 + 0.6 + span * (j + 0.86) / 3.0
                pa, pb = bearing(ba, r, GANTRY_Z), bearing(bb, r, GANTRY_Z)
                g.add(g_beam(pa + Vector((0, 0, 0.14)), pb + Vector((0, 0, 0.14)), sec_rect(0.75, 0.3)), "housing")
                lt.add(g_beam(pa, pb, sec_rect(0.42, 0.2)), "light")
    for b in (0.0, 22.5):                         # slim hangers up to the main roof trusses (bay seams)
        for r in (98.5, 117.8):
            g.add(g_beam(bearing(b, r, GANTRY_Z + 0.85), bearing(b, r, dome_bot(r) - 0.6), sec_rect(0.3, 0.3)),
                  "shell_case")
    atts = {}
    for k in range(6):
        b = k * BAY_STEP + BAY_OFF + 3.0
        atts["GuardPost_%d" % (k + 1)] = (bearing(b, 101.0, 0.4), (bearing(b, 1.0) - bearing(b, 0.0)).normalized())
    return P, atts


# =============================================================================================== room 3: pole hall
HALL_R = 180.0
WALL_TOP = 100.0
CROWN_R = 97.0
POLE_R = CASE_R - POLE_Y          # 111.7
POLE_BASE = 0.4
RISE = 120.0


def dome_top(r):
    """Top-chord line of the truss dome: (180, 104) -> (97, 129.5)."""
    return 104.0 + (HALL_R - r) / (HALL_R - CROWN_R) * 25.5


def dome_bot(r):
    return 98.0 + (HALL_R - r) / (HALL_R - CROWN_R) * 27.0


POLE_TOP = dome_top(POLE_R) + 0.6            # the aperture collar
# The ceiling ring's LED bars (pass 2): a polar grid of radial bars, one radial row on every 7.5-degree seam (48 in
# all, hung under the trusses) and 6 rings, so that bars on one bearing line up. From the floor the far half of the
# ceiling then shows the film's dotted rows fanning out under the hub (T1 @124.7 s); from the rise, the rows either
# side of a rider (3.75 degrees off its bearing) read as the pair of tubes behind the rider (T1 @127.2 s). The rows
# keep 7 studs clear of every pole's aperture.
LED_ROW_BEARINGS = tuple(BAY_STEP * k for k in range(6))
LED_RING_R = (104.0, 117.0, 130.0, 143.0, 156.0, 169.0)
LED_HALF = 3.0                               # each bar is 6 studs long (radially)
LED_SPARSE_R = 140.0                         # review fix: the rings beyond this keep every second row only, so the
#                                              near ceiling reads as the film's sparse dashes, not a white grid
LED_RINGS = tuple((r, 24 if r > LED_SPARSE_R else 48, LED_ROW_BEARINGS[0]) for r in LED_RING_R)  # (r, bars, first)
# the wall bars (pass 2): two vertical light bars, one above the other, on the inner face of every wall column (the
# columns stand on the bay seams, so from the rise a pair flanks each rider, as the tubes do in T1 @127.2 s)
WALL_BAR_Z = ((82.0, 96.0),)                 # review fix: one bar per column, at the top of the wall, so the wall
#                                              below reads dark behind the riders as in T1 @124.7 s (pass 2 had two, a grid)
WALL_BAR_BEARINGS = tuple(BAY_STEP * k for k in range(6))
WALL_BAR_R = HALL_R - 2.25                   # just proud of the columns' inner faces (r 177.9)


def led_bar_ends(seg=0, dz=-1.6):
    """End points of the ceiling ring's LED bars in segment seg (0-7, world frame of the hall); dz below the truss
    bottom chords (-1.6: the bar's axis; -1.85: its emitting face)."""
    out = []
    for k, b in enumerate(LED_ROW_BEARINGS):
        for r in LED_RING_R:
            if r > LED_SPARSE_R and k % 2 == 1:
                continue
            ra, rb = r - LED_HALF, r + LED_HALF
            bb = b + 45.0 * seg
            out.append((bearing(bb, ra, dome_bot(ra) + dz), bearing(bb, rb, dome_bot(rb) + dz)))
    return out


def build_hall_segment():
    P = {"Floor": MB("Floor"), "Bank": MB("Bank"), "Shell": MB("Shell"), "Truss": MB("Truss"),
         "LED": MB("LED", "neon")}
    fl, bk, sh, tr, led = P["Floor"], P["Bank"], P["Shell"], P["Truss"], P["LED"]
    seg = 45.0
    # floor plates: rings of 15-degree plates with 0.25 seams over a dark substrate
    for r0, r1, key in ((4.0, 30.0, "floor"), (30.0, 56.0, "floor"), (56.0, 78.0, "floor"), (78.0, 97.8, "floor")):
        for k in range(3):
            b0, b1 = k * 15.0, (k + 1) * 15.0
            dr = 0.125
            db = math.degrees(0.125 / max(r0, 1.0))
            fl.add(g_sector(r0 + dr, r1 - dr, b0 + db, b1 - db, 3 if r1 > 40 else 2, -0.3, -0.3, 0.0, 0.0), key)
    fl.add(g_sector(4.0, 97.8, 0.0, seg, 6, -0.6, -0.6, -0.3, -0.3), "plinth")
    fl.add(g_prism([(0.0, 0.0)] + [tuple(bearing(b, 4.0))[:2] for b in (45.0, 22.5, 0.0)], -0.3, 0.0), "floor")
    # banked ring: alternating pale (behind each case) and oxblood (between cases) wedges, r 120 -> 180, z 0.3 -> 14
    for k in range(12):
        b0, b1 = k * 3.75, (k + 1) * 3.75
        key = "wedge_red" if k % 2 == 0 else "wedge_pale"
        e = math.degrees(0.12 / 120.0)
        bk.add(g_sector(120.4, HALL_R, b0 + e, b1 - e, 1, 0.0, 13.4, 0.42, 14.0), key)
    bk.add(g_sector(120.4, HALL_R, 0, seg, 6, -0.3, 13.0, 0.3, 13.8), "plinth")
    # wall: facets, columns at every 7.5 degrees, two ledges, a lighter clerestory band
    for k in range(6):
        b0, b1 = k * BAY_STEP, (k + 1) * BAY_STEP
        sh.add(g_sector(HALL_R, HALL_R + 2.0, b0, b1, 1, 13.0, 13.0, WALL_TOP + 6, WALL_TOP + 6), "shell")
        for zl in (40.0, 70.0):
            sh.add(g_sector(HALL_R - 1.2, HALL_R, b0, b1, 1, zl, zl, zl + 1.0, zl + 1.0), "truss")
    for k in range(6):
        b = k * BAY_STEP
        p = bearing(b, HALL_R - 1.0)
        sh.add(g_prism(p_crect(0, 0, 2.6, 2.2, 0.35), 13.0, WALL_TOP + 2.0), "truss",
               M_place(p, -b))
    # roof deck (dark), a shallow cone on the top chords, 4 radial rings x 6 facets
    rr = [HALL_R + 2.0, 160.0, 136.0, 112.0, CROWN_R + 2.5]
    for k in range(6):
        b0, b1 = k * BAY_STEP, (k + 1) * BAY_STEP
        for ra, rb in zip(rr[1:], rr[:-1]):
            sh.add(g_sector(ra, rb, b0, b1, 1, dome_top(ra) + 0.9, dome_top(rb) + 0.9,
                            dome_top(ra) + 1.5, dome_top(rb) + 1.5), "shell")
    # trusses: main at 0 and 22.5 (chords + web), light radial beams at the other bay seams
    for b in (0.0, 22.5):
        n = 8
        tops = [bearing(b, HALL_R - (HALL_R - CROWN_R) * t / n, dome_top(HALL_R - (HALL_R - CROWN_R) * t / n))
                for t in range(n + 1)]
        bots = [bearing(b, HALL_R - (HALL_R - CROWN_R) * t / n, dome_bot(HALL_R - (HALL_R - CROWN_R) * t / n))
                for t in range(n + 1)]
        v = tr.vol()
        side = bearing(b + 90.0, 1.0) - bearing(b + 90.0, 0.0)
        tr.add(g_beam(tops[0], tops[-1], sec_rect(1.5, 1.5), up=(0, 0, 1)), "truss", None, v)
        tr.add(g_beam(bots[0], bots[-1], sec_rect(1.5, 1.5), up=(0, 0, 1)), "truss", None, v)
        for t in range(n + 1):
            tr.add(g_beam(bots[t], tops[t], sec_rect(0.8, 0.8), up=tuple(side)), "truss", None, v)
            if t < n:
                tr.add(g_beam(bots[t], tops[t + 1], sec_rect(0.7, 0.7), up=tuple(side)), "truss", None, v)
    for b in (7.5, 15.0, 30.0, 37.5):
        tr.add(g_beam(bearing(b, HALL_R, dome_top(HALL_R) - 0.4), bearing(b, CROWN_R + 1.0, dome_top(CROWN_R + 1) - 0.4),
                      sec_rect(0.9, 1.2)), "truss")
    # purlins (tangential, at the top chords) between the radial members
    for r in (120.0, 140.0, 160.0, 176.0):
        for k in range(6):
            b0, b1 = k * BAY_STEP, (k + 1) * BAY_STEP
            z = dome_top(r) + 0.2
            tr.add(g_beam(bearing(b0, r, z), bearing(b1, r, z), sec_rect(0.9, 0.9)), "truss")
    # the ceiling ring's LED bars: radial bars in a polar grid outside the crown, each under a dark housing hung
    # just below the truss bottom chords (the film shows none inside the wheel)
    for pa, pb in led_bar_ends(0):
        tr.add(g_beam(pa + Vector((0, 0, 0.35)), pb + Vector((0, 0, 0.35)), sec_rect(0.9, 0.45)), "housing")
        led.add(g_beam(pa, pb, sec_rect(0.5, 0.3)), "light")
    # the wall bars: two vertical bars on the inner face of each column, each in a dark channel
    for b in WALL_BAR_BEARINGS:
        for z0, z1 in WALL_BAR_Z:
            tr.add(g_beam(bearing(b, WALL_BAR_R + 0.35, z0 - 0.4), bearing(b, WALL_BAR_R + 0.35, z1 + 0.4),
                          sec_rect(0.9, 0.5), up=tuple(bearing(b, 1.0) - bearing(b, 0.0))), "housing")
            led.add(g_beam(bearing(b, WALL_BAR_R, z0), bearing(b, WALL_BAR_R, z1), sec_rect(0.5, 0.3),
                           up=tuple(bearing(b, 1.0) - bearing(b, 0.0))), "light")
    # apertures over the poles: collar rings in the roof deck with a closed dark iris
    for k in range(6):
        b = bay_bearing(k)
        c = bearing(b, POLE_R)
        z = dome_top(POLE_R) + 0.6
        sh.add(g_annulus(p_ngon(2.6, 12, cx=c.x, cy=c.y), p_ngon(1.6, 12, cx=c.x, cy=c.y), z - 0.9, z + 0.4), "truss")
        sh.add(g_prism(p_ngon(1.65, 12, cx=c.x, cy=c.y), z + 0.15, z + 0.4), "housing")
    return P, {}


def build_crown():
    P = {"Ring": MB("Ring"), "Hub": MB("Hub"), "Spots": MB("Spots", "neon")}
    ring, hub, spots = P["Ring"], P["Hub"], P["Spots"]
    zc = 127.0
    ring.add(g_sector(CROWN_R - 6.0, CROWN_R, 0, 360, 48, zc - 2.5, zc - 2.5, zc + 2.5, zc + 2.5), "truss")
    ring.add(g_sector(CROWN_R - 5.4, CROWN_R - 0.6, 0, 360, 48, zc + 2.5, zc + 2.5, zc + 3.6, zc + 3.6), "shell")
    ring.add(g_sector(58.5, 61.5, 0, 360, 24, zc - 1.2, zc - 1.2, zc + 1.2, zc + 1.2), "truss")
    for k in range(48):
        b = k * 7.5 + 3.75
        ring.add(g_beam(bearing(b, 19.5, zc + 0.8), bearing(b, CROWN_R - 5.8, zc + 0.2), sec_rect(0.7, 1.1)), "truss")
    hub.add(g_prism(p_ngon(20.0, 24, rot=0), zc - 6.0, zc + 2.8), "truss")
    hub.add(g_prism(p_ngon(16.5, 24, rot=0), zc - 7.2, zc - 6.0), "housing")
    hub.add(g_prism(p_ngon(6.0, 12), zc + 2.8, zc + 4.5), "shell")
    # the roof deck over the wheel (pass 2): seen through the spokes, as in T1 @124.7 s (pass 1 left it open)
    ring.add(g_prism(p_ngon(CROWN_R + 3.5, 24, rot=0), zc + 5.6, zc + 6.2), "shell")
    atts = {}
    # the 12 hub spots hang below the hub in two tiers, as the film's bright hanging cluster (review fix; T1 @124.7 s,
    # T2 @133.9 s): 8 on drop rods round a ring of r 11, 4 lower on a ring of r 5, each a big can with a 5.2-stud lens
    # tilted a little outward (pass 2 had a flat ring of small dots against the hub's underside)
    for k, (b, r_, drop) in enumerate([(k * 45.0 + 22.5, 11.0, 6.5) for k in range(8)] +
                                      [(k * 90.0, 5.0, 13.0) for k in range(4)]):
        base = bearing(b, r_, zc - 7.2)
        top = base + Vector((0, 0, -drop))
        tip = bearing(b, r_ + 0.9, zc - 7.2 - drop - 2.4)
        v = hub.vol()
        hub.add(g_beam(base, top, sec_rect(0.35, 0.35)), "housing", None, v)                    # drop rod
        hub.add(g_beam(top + Vector((0, 0, 0.3)), tip, p_ngon(3.0, 10)), "housing", None, v)    # the can
        d = (tip - top).normalized()
        spots.add(g_beam(tip, tip + d * 0.14, p_ngon(2.6, 10)), "spot")
        atts["HubSpot_%d" % (k + 1)] = (tip + d * 0.25, Vector((0.12 * math.sin(math.radians(b)),
                                                                 0.12 * math.cos(math.radians(b)), -1)).normalized())
    return P, atts


def build_pole():
    """A dark steel rod with copper bands (pass 2: no light strips; the film's poles are dark rods, critic #5c)."""
    P = {"Steel": MB("Steel"), "Copper": MB("Copper")}
    st, cu = P["Steel"], P["Copper"]
    H = POLE_TOP - POLE_BASE
    st.add(g_prism(p_ngon(0.5, 12, rot=0), 0.0, H), "pole")
    for z in [1.6] + [16.0 + 15.0 * k for k in range(8)]:
        if z + 0.6 < H:
            cu.add(g_prism(p_ngon(0.62, 12, rot=0), z, z + 0.6), "copper")
    atts = {"Base": (Vector((0, 0, 0)), Vector((0, 0, 1))), "Top": (Vector((0, 0, H)), Vector((0, 0, 1)))}
    return P, atts


# =============================================================================================== preview figures
def figure_parts(kind="tribute", district=None, look_up=0.0):
    """A blocky R15-proportioned figure (5.5 tall) for previews only. Front = +Y. A "tribute" is the player's own
    stand-in (or a neighbour) in the white launch cape; look_up tilts the head back by that many degrees."""
    mb = MB("Figure")
    if kind == "suit":
        # a neighbour in the cases (review fix): the white launch suit with the district colour on the sleeves and no
        # flared cape, so the raised disc shows round the feet and catches the case's top light (T1 @125.9 s)
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.86, 0.86, 0.1), 0.0, 0.35), "shoe")
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.84, 0.84, 0.1), 0.35, 2.3), "trousers")
        mb.add(g_prism(p_crect(0, 0, 1.9, 0.95, 0.12), 2.3, 4.3), "cape")
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 1.38, 0, 0.8, 0.8, 0.1), 2.35, 4.25), district or "cape")
        mb.add(g_prism(p_crect(0, 0, 1.15, 1.1, 0.18), 4.32, 5.42), "skin")
        mb.add(g_box(-0.42, 0.5, 4.95, 0.42, 0.57, 5.08), "hair_dk")
        mb.add(g_prism(p_crect(0, -0.05, 1.3, 1.25, 0.3), 5.1, 5.75), "hair")
        mb.add(g_prism(p_crect(0, -0.55, 1.3, 0.3, 0.1), 4.4, 5.6), "hair")
        mb.add(g_prism(p_crect(0, -0.62, 1.6, 0.4, 0.15), 3.2, 4.4), "cape")              # the hood, down
        return mb
    if kind == "tribute":
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.86, 0.86, 0.1), 0.0, 0.35), "shoe")
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.84, 0.84, 0.1), 0.35, 2.3), "trousers")
        mb.add(g_prism(p_crect(0, 0, 1.9, 0.95, 0.12), 2.3, 4.3), district or "trousers")
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 1.38, 0, 0.8, 0.8, 0.1), 2.35, 4.25), "cape")
        Mh = (Matrix.Translation((0, 0, 4.32)) @ Matrix.Rotation(math.radians(look_up), 4, "X")
              @ Matrix.Translation((0, 0, -4.32)))
        mb.add(g_prism(p_crect(0, 0, 1.15, 1.1, 0.18), 4.32, 5.42), "skin", Mh)
        mb.add(g_box(-0.42, 0.5, 4.95, 0.42, 0.57, 5.08), "hair_dk", Mh)          # brows, so the face reads
        mb.add(g_prism(p_crect(0, -0.05, 1.3, 1.25, 0.3), 5.1, 5.75), "hair", Mh)
        mb.add(g_prism(p_crect(0, -0.55, 1.3, 0.3, 0.1), 4.4, 5.6), "hair", Mh)
        # cape: faceted poncho, open front edges trimmed dark, hood behind the head
        cape = [(r, z) for r, z in ((0.86, 4.3), (1.7, 3.3), (2.05, 1.7))]     # a narrow collar: the head shows from below
        n = 12
        ring_pts = []
        for r, z in cape:
            ring_pts.append([(r * math.cos(TAU * i / n + math.pi / 12), 0.72 * r * math.sin(TAU * i / n + math.pi / 12), z)
                             for i in range(n)])
        V = [p for ring_ in ring_pts for p in ring_]
        F = []
        for k in range(len(cape) - 1):
            for i in range(n):
                j = (i + 1) % n
                F.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
        F.append(tuple(range(n)))
        F.append(tuple(range(2 * n + n - 1, 2 * n - 1, -1)))
        mb.add((V, F), "cape")
        hem = [(2.07 * math.cos(TAU * i / n + math.pi / 12), 0.72 * 2.07 * math.sin(TAU * i / n + math.pi / 12)) for i in range(n)]
        hem_in = [(1.9 * math.cos(TAU * i / n + math.pi / 12), 0.72 * 1.9 * math.sin(TAU * i / n + math.pi / 12)) for i in range(n)]
        mb.add(g_annulus(hem, hem_in, 1.62, 1.98), "trim")
        for sx in (-1, 1):
            mb.add(g_beam((sx * 0.35, 0.78, 4.35), (sx * 0.62, 1.45, 1.7), sec_rect(0.22, 0.16), up=(0, 1, 0.3)), "trim")
        mb.add(g_beam((0, -0.55, 4.3), (0, -0.8, 5.5), p_ngon(0.62, 8)), "cape")
    else:   # guard in white armour with a dark visor and a rifle (our own design; pass 2 drops pass 1's escort)
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 0.48, 0, 0.9, 0.9, 0.12), 0.0, 0.4), "black")
            mb.add(g_prism(p_crect(sx * 0.48, 0, 0.88, 0.88, 0.12), 0.4, 2.3), "armour")
            mb.add(g_prism(p_crect(sx * 0.48, 0.12, 0.9, 0.7, 0.12), 1.0, 1.5), "black")
        mb.add(g_prism(p_crect(0, 0, 2.0, 1.05, 0.15), 2.3, 4.35), "armour")
        mb.add(g_prism(p_crect(0, 0.12, 1.4, 0.9, 0.12), 3.0, 4.1), "black")
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 1.42, 0, 0.84, 0.84, 0.12), 2.4, 4.3), "armour")
        mb.add(g_prism(p_crect(0, 0, 1.3, 1.3, 0.3), 4.35, 5.65), "armour")
        mb.add(g_box(-0.6, 0.45, 4.6, 0.6, 0.68, 5.2), "visor")
        mb.add(g_beam((-1.1, 0.9, 3.0), (1.2, 0.9, 3.9), sec_rect(0.3, 0.42), up=(0, 0, 1)), "rifle")
    return mb


# =============================================================================================== objects, paint, AO
def mb_to_object(mb, name, collection):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.V, [], mb.F)
    me.validate(clean_customdata=False)
    me.update()
    try:
        me.shade_flat()
    except AttributeError:
        for p in me.polygons:
            p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    ob["cls"] = mb.cls
    META[me.name] = {"keys": list(mb.K), "vols": list(mb.G), "cls": mb.cls}
    return ob


META = {}          # mesh name -> {"keys": palette key per face, "vols": volume id per face, "cls", "srgb"}


def meta(ob):
    return META[ob.data.name]


def hashu(*xs):
    h = 2166136261
    for x in xs:
        h = ((h ^ (int(x) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return h / 4294967295.0


def paint_object(ob, ao, salt):
    """Per-face colour: tone, volume and facet jitter, warm-top / cool-bottom, times AO (>= 0.5)."""
    me = ob.data
    keys = meta(ob)["keys"]
    vols = meta(ob)["vols"]
    nrm = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)
    cols = np.zeros((len(me.polygons), 3))
    for i, p in enumerate(me.polygons):
        tone, _, _, _, kind, _ = PAL[keys[i]]
        c = np.array(tone, dtype=np.float64)
        if kind == "paint":
            jv = (hashu(salt, vols[i], 7) - 0.5) * 0.12
            jf = (hashu(salt, vols[i], i, 13) - 0.5) * 0.06
            drift = (hashu(salt, vols[i], 29) - 0.5) * 0.04
            nz = nrm[i][2]
            top = 0.045 * nz if nz > 0 else 0.07 * nz
            c = c * (1.0 + jv + jf + top)
            c[0] *= 1.0 + drift + (0.015 * nz)
            c[2] *= 1.0 - drift - (0.015 * nz)
            c = c * ao[i]
        cols[i] = c
    return cols


def normalise_to_tones(obs_cols):
    """Scale each palette key's faces (across all parts given) so the mean luma after AO of what can be SEEN equals
    the tone's luma (keeps hue and the relative facet variation). Faces are weighted by area x openness, so the
    buried faces (plate bottoms, seams, faces against walls) do not drag the mean. Returns {key: (target, before,
    after, factor)}."""
    acc = {}
    for ob, cols in obs_cols:
        keys = meta(ob)["keys"]
        openness = meta(ob).get("open")
        areas = np.empty(len(ob.data.polygons))
        ob.data.polygons.foreach_get("area", areas)
        for i, k in enumerate(keys):
            if PAL[k][4] != "paint":
                continue
            w = areas[i] * (0.05 + (openness[i] if openness is not None else 1.0))
            a = acc.setdefault(k, [0.0, 0.0])
            a[0] += w * luma(cols[i])
            a[1] += w
    report = {}
    for k, (s, w) in acc.items():
        mean = s / max(w, 1e-9)
        target = luma(PAL[k][0])
        f = min(1.7, max(0.8, target / max(mean, 1e-6)))
        report[k] = (target, mean, mean * f, f)
        for ob, cols in obs_cols:
            keys = meta(ob)["keys"]
            for i, kk in enumerate(keys):
                if kk == k:
                    cols[i] = cols[i] * f
    for ob, cols in obs_cols:
        np.clip(cols, 0, 255, out=cols)
    return report


AO_STRENGTH = 0.5          # AO never takes a facet below half its painted value (ArtStyle rule 5)


def face_ao(ob_world_faces, bvh, rng_seed, n_rays=20, near=2.5, far=9.0, strength=AO_STRENGTH):
    """ob_world_faces: list of (centroid, normal, corner points). AO per face in [1 - strength, 1]."""
    rng = np.random.default_rng(rng_seed)
    u1 = rng.random(n_rays)
    u2 = rng.random(n_rays)
    r = np.sqrt(u1)
    th = TAU * u2
    local = np.stack([r * np.cos(th), r * np.sin(th), np.sqrt(np.maximum(0, 1 - u1))], axis=1)
    out = np.ones(len(ob_world_faces))
    for fi, (cen, nrm, pts) in enumerate(ob_world_faces):
        n = Vector(nrm)
        if n.length < 1e-6:
            continue
        t = n.orthogonal().normalized()
        b = n.cross(t)
        samples = [cen] + [cen.lerp(p, 0.6) for p in pts[:4]]
        occ = 0.0
        cnt = 0
        for s in samples:
            o = s + n * 0.03
            for lx, ly, lz in local:
                d = t * lx + b * ly + n * lz
                hit = bvh.ray_cast(o, d, far)
                cnt += 1
                if hit[0] is not None:
                    dist = hit[3]
                    occ += 1.0 if dist < near else 0.55 * (1.0 - (dist - near) / (far - near))
        out[fi] = 1.0 - strength * (occ / max(cnt, 1))
    return out


def world_faces(ob, M=None):
    M = M if M is not None else ob.matrix_world
    R = M.to_3x3()
    res = []
    me = ob.data
    for p in me.polygons:
        pts = [M @ me.vertices[v].co for v in p.vertices]
        cen = sum(pts, Vector()) / len(pts)
        nrm = (R @ p.normal).normalized()
        res.append((cen, nrm, pts))
    return res


def bvh_from_objects(obs):
    verts, polys = [], []
    for ob in obs:
        M = ob.matrix_world
        base = len(verts)
        me = ob.data
        verts += [tuple(M @ v.co) for v in me.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in me.polygons]
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)


def set_face_colors(ob, cols):
    """Store painted face colours (sRGB 0-255) as a linear corner colour 'paint' + per-face rough/metal."""
    me = ob.data
    keys = meta(ob)["keys"]
    lin_cols = np.array([[s2l(min(255.0, v)) for v in c] for c in cols])
    loop_tot = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_total", loop_tot)
    per_loop = np.repeat(lin_cols, loop_tot, axis=0)
    rgba = np.concatenate([per_loop, np.ones((len(per_loop), 1))], axis=1).astype(np.float32)
    at = me.color_attributes.get("paint") or me.color_attributes.new("paint", "FLOAT_COLOR", "CORNER")
    at.data.foreach_set("color", rgba.ravel())
    rough = np.array([PAL[k][2] for k in keys], dtype=np.float32)
    metal = np.array([PAL[k][3] for k in keys], dtype=np.float32)
    for nm, arr in (("rough", rough), ("metal", metal)):
        a = me.attributes.get(nm) or me.attributes.new(nm, "FLOAT", "FACE")
        a.data.foreach_set("value", arr)
    meta(ob)["srgb"] = np.array(cols, dtype=np.float64)
    me.update()


# =============================================================================================== scene assembly
class Asset:
    def __init__(self, name, kind, room, parts, atts, notes="", tags=()):
        self.name, self.kind, self.room, self.parts, self.atts = name, kind, room, parts, atts
        self.notes, self.tags = notes, list(tags)
        self.masters = {}            # part -> object (at identity)


PART_META = {
    # (asset, part) -> (role, robloxMaterial, collide, collision, castShadow, tags, notes)
    ("LaunchRedRoom", "Shell"): ("Paint", "Concrete", True, "PreciseConvexDecomposition", True, ["Floor"], "walls, base course, door, intercom, parapet"),
    ("LaunchRedRoom", "Roof"): ("Paint", "Metal", False, "Box", True, [], "red roof panels between the nets"),
    ("LaunchRedRoom", "NetA"): ("Paint", "Metal", False, "Box", True, [], "the net seen from the room: 1.2 cells, 0.25 bars, 45 deg, sagging"),
    ("LaunchRedRoom", "NetB"): ("Paint", "Metal", False, "Box", True, [], "the net over the roof (establishing shot): 1.2 cells, 0.25 bars, 45 deg, sagging"),
    ("LaunchRedRoom", "HexFrame"): ("Paint", "Metal", False, "Box", True, [], "teal hexagonal frame, gussets and bolts"),
    ("LaunchRedRoom", "Hood"): ("Paint", "Metal", False, "Box", True, [], "the drop under the hex frame: an oxblood hood with thin red rails (frame A's shaft); the lift rises through it"),
    ("LaunchRedRoom", "Deck"): ("Paint", "DiamondPlate", True, "Box", True, ["Floor"], "deck plates, stripes, lift apron"),
    ("LaunchRedRoom", "Grates"): ("Paint", "Metal", False, "Box", True, [], "black grates over dark pits, and the red mesh in the two floor openings (walk on the Deck collider)"),
    ("LaunchRedRoom", "Rails"): ("Paint", "Metal", True, "PreciseConvexDecomposition", True, [], "red rails, posts, wall pipes"),
    ("LaunchRedRoom", "Lamps"): ("Paint", "Metal", False, "Box", True, [], "lamp housings"),
    ("LaunchRedRoom", "LampLights"): ("Light", "Neon", False, "Box", False, [], "lamp lenses (Neon)"),
    ("LaunchRedRoom", "Stairs"): ("Paint", "Concrete", True, "PreciseConvexDecomposition", True, ["Floor"], "walkway and stairs"),
    ("LaunchRedRoom", "Lift"): ("Paint", "Metal", True, "Hull", True, ["Floor", "Lift"], "the rose lift disc (moves)"),
    ("LaunchCaseBay", "Frame"): ("Paint", "Metal", True, "PreciseConvexDecomposition", True, [], "plinth, posts, pedestal"),
    ("LaunchCaseBay", "Glass"): ("Glass", "Glass", True, "PreciseConvexDecomposition", False, [], "front and side panes"),
    ("LaunchCaseBay", "Light"): ("Light", "Neon", False, "Box", False, [], "case top-light and the unit's panel"),
    ("LaunchCaseBay", "Unit"): ("Paint", "Metal", True, "PreciseConvexDecomposition", True, [], "maroon wall unit"),
    ("LaunchCaseBay", "Collider"): ("Collider", "SmoothPlastic", True, "Box", False, ["BackCollider"], "invisible; CanCollide off at the rise"),
    ("LaunchRiserDisc", "Disc"): ("Paint", "Metal", True, "Hull", True, ["Floor"], "the disc you ride"),
    ("LaunchRiserDisc", "Collar"): ("Paint", "Metal", False, "Box", True, [], "collar on the pole"),
    ("LaunchCaseGallery", "Walkway"): ("Paint", "DiamondPlate", True, "PreciseConvexDecomposition", True, ["Floor"], "walkway, kerb, back strip and screen"),
    ("LaunchCaseGallery", "Gantry"): ("Paint", "Metal", False, "Box", True, [], "light gantry and columns"),
    ("LaunchCaseGallery", "Lights"): ("Light", "Neon", False, "Box", False, [], "strip lights (Neon)"),
    ("LaunchPoleHallSegment", "Floor"): ("Paint", "DiamondPlate", True, "PreciseConvexDecomposition", True, ["Floor"], "floor plates"),
    ("LaunchPoleHallSegment", "Bank"): ("Paint", "Concrete", True, "PreciseConvexDecomposition", True, [], "banked wedge ring"),
    ("LaunchPoleHallSegment", "Shell"): ("Paint", "Concrete", False, "Box", True, [], "wall, roof deck, apertures"),
    ("LaunchPoleHallSegment", "Truss"): ("Paint", "Metal", False, "Box", True, [], "trusses, purlins, columns, LED housings, wall-bar channels"),
    ("LaunchPoleHallSegment", "LED"): ("Light", "Neon", False, "Box", False, [], "the ceiling ring's LED bars and the wall bars (Neon)"),
    ("LaunchPoleHallCrown", "Ring"): ("Paint", "Metal", False, "Box", True, [], "spoked ring"),
    ("LaunchPoleHallCrown", "Hub"): ("Paint", "Metal", False, "Box", True, [], "hub and spot cans"),
    ("LaunchPoleHallCrown", "Spots"): ("Light", "Neon", False, "Box", False, [], "spot lenses (Neon)"),
    ("LaunchPole", "Steel"): ("Paint", "Metal", False, "Box", True, [], "12-sided dark steel rod (no light on it)"),
    ("LaunchPole", "Copper"): ("Paint", "Metal", False, "Box", True, [], "copper bands"),
}

ROOM_OF = {"LaunchRedRoom": "LaunchRedRoom", "LaunchCaseBay": "LaunchCaseHall", "LaunchCaseGallery": "LaunchCaseHall",
           "LaunchRiserDisc": "LaunchCaseHall", "LaunchPoleHallSegment": "LaunchPoleHall",
           "LaunchPoleHallCrown": "LaunchPoleHall", "LaunchPole": "LaunchPoleHall"}

IN_USE = set(range(0, N_BAYS, 2))            # a 24-player round stands in every second case


def new_collection(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in (parent or bpy.context.scene.collection).children]:
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def link_instance(master, name, M, coll):
    ob = bpy.data.objects.new(name, master.data)
    ob.matrix_world = M
    coll.objects.link(ob)
    ob["cls"] = master["cls"]
    return ob


def build_all():
    rng = random.Random(SEED)
    lib = new_collection("Masters")
    assets = {}
    specs = [
        ("LaunchRedRoom", "Room", build_red_room(rng), "The transition room (client-local, one per player), "
         "loops while the map loads. Interior 30 x 24, net at 20."),
        ("LaunchCaseBay", "CaseBay", build_case_bay(), "One bay of the glass-case ring (x48 at r 110, every 7.5 deg, "
         "facing the hall centre). Open top and back so the disc and collar can leave up the pole."),
        ("LaunchRiserDisc", "Platform", build_riser_disc(), "The disc a contender rides (x48), moved by the game up "
         "its pole. Origin = the standing surface (Stand)."),
        ("LaunchCaseGallery", "Segment", build_case_gallery(), "45-degree segment of the case gallery (x8, yaw k*45)."),
        ("LaunchPoleHallSegment", "Segment", build_hall_segment(), "45-degree segment of the pole hall (x8, yaw k*45)."),
        ("LaunchPoleHallCrown", "Crown", build_crown(), "The spoked ceiling ring and hub (x1, at the hall origin)."),
        ("LaunchPole", "Pole", build_pole(), "One pole (x48), base on the case plinth at y 0.4."),
    ]
    for name, kind, (parts, atts), notes in specs:
        a = Asset(name, kind, ROOM_OF[name], parts, atts, notes)
        for pn, mb in parts.items():
            if not mb.F:
                continue
            ob = mb_to_object(mb, "%s_%s" % (name, pn), lib)
            a.masters[pn] = ob
        assets[name] = a
    lib.hide_render = True
    return assets


def assemble(assets):
    """Instances of the masters in the set frame (pole hall) + the red room in its own frame."""
    hall = new_collection("Hall")
    red = new_collection("RedRoom")
    inst = {"hall": [], "red": [], "bays": {}, "discs": {}, "poles": {}}
    for pn, m in assets["LaunchRedRoom"].masters.items():
        inst["red"].append(link_instance(m, "I_" + m.name, Matrix.Identity(4), red))
    for k in range(8):
        M = M_place((0, 0, 0), -45.0 * k)
        for an in ("LaunchPoleHallSegment", "LaunchCaseGallery"):
            for pn, m in assets[an].masters.items():
                inst["hall"].append(link_instance(m, "I_%s_%d" % (m.name, k), M, hall))
    for pn, m in assets["LaunchPoleHallCrown"].masters.items():
        inst["hall"].append(link_instance(m, "I_" + m.name, Matrix.Identity(4), hall))
    for i in range(N_BAYS):
        b = bay_bearing(i)
        Mb = M_facing_centre(b, CASE_R)
        inst["bays"][i] = []
        for pn, m in assets["LaunchCaseBay"].masters.items():
            ob = link_instance(m, "I_%s_%02d" % (m.name, i), Mb, hall)
            if pn == "Collider":
                ob.hide_render = True
            inst["bays"][i].append(ob)
            inst["hall"].append(ob)
        Mp = Mb @ Matrix.Translation((0, POLE_Y, POLE_BASE))
        inst["poles"][i] = [link_instance(m, "I_%s_%02d" % (m.name, i), Mp, hall)
                            for m in assets["LaunchPole"].masters.values()]
        inst["hall"] += inst["poles"][i]
        Md = Mb @ Matrix.Translation((0, DISC_Y, DISC_TOP))
        inst["discs"][i] = [link_instance(m, "I_%s_%02d" % (m.name, i), Md, hall)
                            for m in assets["LaunchRiserDisc"].masters.values()]
        inst["hall"] += inst["discs"][i]
    return inst


def paint_and_ao(assets, inst):
    log("AO: building BVHs")
    bpy.context.view_layer.update()
    bvh_red = bvh_from_objects([o for o in inst["red"]])
    hall_obs = [o for o in inst["hall"] if not o.hide_render]
    bvh_hall = bvh_from_objects(hall_obs)
    # the master's AO is computed on one representative instance in its set position
    rep = {}
    for o in inst["red"]:
        rep[o.data.name] = (o, bvh_red)
    for o in inst["hall"]:
        if o.data.name not in rep and not o.hide_render:
            rep[o.data.name] = (o, bvh_hall)
    painted = []
    salt = 1
    for an, a in assets.items():
        for pn, m in a.masters.items():
            salt += 1
            o, bvh = rep.get(m.data.name, (None, None))
            if o is None or m["cls"] in ("neon", "glass", "collider"):
                ao = np.ones(len(m.data.polygons))
            else:
                t = time.time()
                ao = face_ao(world_faces(o), bvh, SEED * 100 + salt)
                log("AO %-34s %5d faces  mean %.3f  min %.3f  (%.1fs)" % (m.name, len(ao), ao.mean(), ao.min(),
                                                                              time.time() - t))
            meta(m)["open"] = np.clip((ao - (1.0 - AO_STRENGTH)) / AO_STRENGTH, 0.0, 1.0)
            cols = paint_object(m, ao, salt)
            painted.append((m, cols))
    report = normalise_to_tones(painted)
    for m, cols in painted:
        set_face_colors(m, cols)
    return report


# =============================================================================================== preview materials
# Lighting.Ambient per space (sRGB 0-255; the preview adds paint x ambient, as Roblox does). Pass 2: navy in both
# halls and a dim cool ambient in the red room, so that unlit faces read blue, not charcoal (TwoArenas 2.8).
AMBIENT = {"red": (26, 21, 28), "case": (14, 30, 44), "hall": (56, 76, 94), "rise": (36, 40, 48)}
# "rise": the pole hall's profile once the camera settles into the low-angle end frame: a darker, greyer navy, so the
# lit rider stands out against a hall that falls away (T1 @127.2 s); it blends in with the exposure ramp
for _kv in filter(None, os.environ.get("LAUNCH_AMB", "").split(";")):          # look-dev: "hall:20,30,50;case:..."
    _k, _v = _kv.split(":")
    AMBIENT[_k] = tuple(int(x) for x in _v.split(","))
VIEW_TRANSFORM = os.environ.get("LAUNCH_VIEW", "AgX")
_mats = {}
_amb_nodes = []


def _ambient_emission(nt, bsdf, base_socket):
    """Emission = base colour x the space's ambient (the preview's stand-in for Roblox's Lighting.Ambient)."""
    amb = nt.nodes.new("ShaderNodeRGB")
    amb.name = "Ambient"
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    if base_socket is not None:
        nt.links.new(base_socket, mul.inputs[6])
    else:
        mul.inputs[6].default_value = bsdf.inputs["Base Color"].default_value[:]
    nt.links.new(amb.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    _amb_nodes.append(amb)


def mat_paint(name="M_Paint"):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "paint"
    ar = nt.nodes.new("ShaderNodeAttribute")
    ar.attribute_name = "rough"
    am = nt.nodes.new("ShaderNodeAttribute")
    am.attribute_name = "metal"
    nt.links.new(at.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(ar.outputs["Fac"], bsdf.inputs["Roughness"])
    nt.links.new(am.outputs["Fac"], bsdf.inputs["Metallic"])
    _ambient_emission(nt, bsdf, at.outputs["Color"])
    _mats[name] = m
    return m


def mat_neon(name, rgb, strength):
    key = (name, strength)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = lin(rgb) + (1.0,)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    _mats[key] = m
    return m


def mat_glass():
    if "glass" in _mats:
        return _mats["glass"]
    m = bpy.data.materials.new("M_Glass")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    tr.inputs["Color"].default_value = (0.94, 0.96, 0.97, 1.0)
    # (review fix) a pure glossy layer, no diffuse: pass 2's Principled layer gave the panes a faint grey diffuse that
    # caught the case lights as grainy grey patches beside each top light
    gl = nt.nodes.new("ShaderNodeBsdfGlossy")
    gl.inputs["Color"].default_value = lin(PAL["glass"][0]) + (1.0,)
    gl.inputs["Roughness"].default_value = 0.08
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = 0.04           # clear glass with light reflections (T1 @125.9 s), not a grey haze
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(gl.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    _mats["glass"] = m
    return m


def mat_flat(rgb):
    key = ("flat",) + tuple(rgb)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("M_Fig_%d_%d_%d" % tuple(rgb))
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = lin(rgb) + (1.0,)
    b.inputs["Roughness"].default_value = 0.85
    _ambient_emission(m.node_tree, b, None)
    _mats[key] = m
    return m


NEON_STRENGTH = {"light": 9.0, "lens": 14.0, "spot": 45.0}


def assign_preview_materials(assets):
    for a in assets.values():
        for pn, m in a.masters.items():
            m.data.materials.clear()
            cls = m["cls"]
            if cls == "neon":
                key = meta(m)["keys"][0]
                m.data.materials.append(mat_neon("M_Neon_" + key, PAL[key][0], NEON_STRENGTH.get(key, 9.0)))
            elif cls == "glass":
                m.data.materials.append(mat_glass())
            elif cls == "collider":
                m.data.materials.append(mat_glass())
            else:
                m.data.materials.append(mat_paint())


def set_ambient(room):
    rgb = room if isinstance(room, tuple) else AMBIENT[room]
    for node in _amb_nodes:
        node.outputs[0].default_value = lin(rgb) + (1.0,)


def figure_object(kind, name, M, coll, district=None, look_up=0.0):
    mb = figure_parts(kind, district, look_up)
    ob = mb_to_object(mb, name, coll)
    ob.matrix_world = M
    keys = meta(ob)["keys"]
    used = sorted(set(keys))
    for k in used:
        ob.data.materials.append(mat_flat(FIG[k]))
    idx = {k: i for i, k in enumerate(used)}
    ob.data.polygons.foreach_set("material_index", [idx[k] for k in keys])
    return ob


# =============================================================================================== 5 x 7 label font
_F = {
    "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
    "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
    "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "I": [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
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
    ",": ["     ", "     ", "     ", "     ", " ##  ", "  #  ", " #   "],
    ":": ["     ", " ##  ", " ##  ", "     ", " ##  ", " ##  ", "     "],
    "-": ["     ", "     ", "     ", "#####", "     ", "     ", "     "],
    "/": ["    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "],
    "(": ["   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # "],
    ")": [" #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   "],
    "@": [" ### ", "#   #", "# ###", "# # #", "# ###", "#    ", " ####"],
    "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    "=": ["     ", "     ", "#####", "     ", "#####", "     ", "     "],
    "#": [" # # ", " # # ", "#####", " # # ", "#####", " # # ", " # # "],
    "%": ["##   ", "##  #", "   # ", "  #  ", " #   ", "#  ##", "   ##"],
    "'": ["  #  ", "  #  ", "     ", "     ", "     ", "     ", "     "],
    ">": [" #   ", "  #  ", "   # ", "    #", "   # ", "  #  ", " #   "],
    "<": ["   # ", "  #  ", " #   ", "#    ", " #   ", "  #  ", "   # "],
    " ": ["     "] * 7,
}


def draw_text(img, x, y, text, scale=2, col=(0.93, 0.93, 0.9)):
    """img: H x W x 3, row 0 = TOP."""
    H, W = img.shape[:2]
    for ci, ch in enumerate(text.upper()):
        g = _F.get(ch)
        if g is None:
            continue
        for ry, row in enumerate(g):
            for rx, c in enumerate(row):
                if c != "#":
                    continue
                y0, x0 = y + ry * scale, x + (ci * 6 + rx) * scale
                if 0 <= y0 < H - scale and 0 <= x0 < W - scale:
                    img[y0:y0 + scale, x0:x0 + scale, :3] = col


def load_rgb(path):
    a = tg.load_image_np(path, "Non-Color")
    return np.flipud(a[..., :3]).astype(np.float64)


def save_rgb(path, img):
    tg.write_png(path, np.flipud(np.clip(img, 0.0, 1.0)), quantize=False)


def resize(img, h, w):
    H, W = img.shape[:2]
    ys = np.clip((np.arange(h) + 0.5) * H / h - 0.5, 0, H - 1)
    xs = np.clip((np.arange(w) + 0.5) * W / w - 0.5, 0, W - 1)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, H - 1)
    x1 = np.minimum(x0 + 1, W - 1)
    wy = (ys - y0)[:, None, None]
    wx = (xs - x0)[None, :, None]
    a = img[y0][:, x0] * (1 - wx) + img[y0][:, x1] * wx
    b = img[y1][:, x0] * (1 - wx) + img[y1][:, x1] * wx
    return a * (1 - wy) + b * wy


def colour_stats(img):
    """Numbers for the semi-real check: no cartoon saturation, no film grade in the shadows, no clipping."""
    x = img.reshape(-1, 3)
    L = x @ np.array([0.2126, 0.7152, 0.0722])
    mx, mn = x.max(1), x.min(1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    lit = L > 0.06
    dark = (L <= np.quantile(L, 0.25)) & (L > 0.01)
    return {
        "meanLuma": round(float(L.mean() * 255), 1),
        "p95Luma": round(float(np.quantile(L, 0.95) * 255), 1),
        "clippedPct": round(float((L > 0.985).mean() * 100), 2),
        "meanSaturationLit": round(float(sat[lit].mean()) if lit.any() else 0.0, 3),
        "vividPct": round(float(((sat > 0.72) & (mx > 0.5)).mean() * 100), 2),
        "shadowBlueMinusRed": round(float((x[dark, 2] - x[dark, 0]).mean() * 255) if dark.any() else 0.0, 1),
        "shadowGreenMinusRed": round(float((x[dark, 1] - x[dark, 0]).mean() * 255) if dark.any() else 0.0, 1),
    }


def compare_sheet(render_path, frames, out_path, title):
    """Our render beside the film frames [(path, caption)], all at one height, captioned, with the iteration label.
    The sheet shows film frames, so it is written only as compare_*.png into a folder whose .gitignore drops them."""
    ren = load_rgb(render_path)
    H = ren.shape[0]
    panels = [(ren, "OURS: " + title)]
    for path, caption in frames:
        fr = load_rgb(path)
        panels.append((resize(fr, H, int(round(fr.shape[1] * H / fr.shape[0]))), "FILM, STUDY ONLY: " + caption))
    gap, strip = 12, 58
    W = sum(p.shape[1] for p, _ in panels) + gap * (len(panels) - 1)
    sheet = np.full((H + strip, W, 3), 0.07)
    x = 0
    for img, caption in panels:
        sheet[:H, x:x + img.shape[1]] = img
        draw_text(sheet, x + 10, H + 10, caption[:max(8, img.shape[1] // 12 - 1)], 2)
        x += img.shape[1] + gap
    draw_text(sheet, 10, H + 34, SHEET_LABEL, 2, (0.95, 0.78, 0.35))
    save_rgb(out_path, sheet)
    return colour_stats(ren), [colour_stats(load_rgb(p)) for p, _ in frames]


# =============================================================================================== render setup
def render_settings(scene, res, samples, exposure):
    tg.enable_gpu(scene)
    c = scene.cycles
    c.samples = samples
    c.use_adaptive_sampling = True
    c.use_denoising = True
    for d in ("OPTIX", "OPENIMAGEDENOISE"):
        try:
            c.denoiser = d
            break
        except TypeError:
            continue
    c.max_bounces = 8
    c.diffuse_bounces = 1          # Roblox has no indirect bounce indoors: keep GI to one bounce
    c.glossy_bounces = 2
    c.transmission_bounces = 6
    c.transparent_max_bounces = 12
    c.sample_clamp_indirect = 4.0
    # (review fix) no caustics: Roblox has none, and the case glass's faint reflection of each case's top light
    # scattered a speckle of white dots over the dark surfaces behind it
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.blur_glossy = 1.0
    try:
        c.use_light_tree = True
    except AttributeError:
        pass
    r = scene.render
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    r.film_transparent = False
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    vs = scene.view_settings
    try:
        vs.view_transform = VIEW_TRANSFORM
    except TypeError:
        vs.view_transform = "Filmic"
    try:
        vs.look = "None"
    except TypeError:
        pass
    vs.exposure = exposure
    world = bpy.data.worlds.get("LaunchWorld") or bpy.data.worlds.new("LaunchWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs["Strength"].default_value = 0.0
    scene.world = world


_GLARE_TYPES = {"FOG_GLOW": "Fog Glow", "BLOOM": "Bloom", "STREAKS": "Streaks"}


def set_glare(scene, spec, exposure, fog=None):
    """Preview stand-ins for two Roblox post effects, in the compositor on the scene-linear render (before the view
    transform): the bloom, as a glare, and the Atmosphere's haze, as a distance fog.
    spec = (type, threshold after exposure, strength, size) or None (no glare). The threshold is in the units the
    exposure leaves (Roblox's bloom threshold), so it is divided by 2^exposure for the pre-exposure render.
    fog = (start, depth, amount, sRGB colour) or None: the picture blends toward the colour with distance (the mist
    pass, linear from start over depth), at most by amount."""
    if not spec and not fog:
        scene.render.use_compositing = False
        return
    for vl in scene.view_layers:               # the mist pass first: the Render Layers node shows it only once enabled
        vl.use_pass_mist = True
    ng = bpy.data.node_groups.get("LaunchPost")
    if ng is None:
        ng = bpy.data.node_groups.new("LaunchPost", "CompositorNodeTree")
        ng.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        rl.name = "RL"
        amt = ng.nodes.new("ShaderNodeMath")
        amt.name = "FogAmount"
        amt.operation = "MULTIPLY"
        mix = ng.nodes.new("ShaderNodeMix")
        mix.name = "Fog"
        mix.data_type = "RGBA"
        col = ng.nodes.new("CompositorNodeRGB")
        col.name = "FogColour"
        gl = ng.nodes.new("CompositorNodeGlare")
        gl.name = "Glare"
        out = ng.nodes.new("NodeGroupOutput")
        ng.links.new(rl.outputs["Mist"], amt.inputs[0])
        ng.links.new(amt.outputs[0], mix.inputs[0])
        ng.links.new(rl.outputs["Image"], mix.inputs[6])
        ng.links.new(col.outputs["Color"], mix.inputs[7])
        ng.links.new(mix.outputs[2], gl.inputs["Image"])
        ng.links.new(gl.outputs["Image"], out.inputs[0])
    for vl in scene.view_layers:
        vl.use_pass_mist = True
    fog_amount = 0.0
    if fog:
        start, depth, fog_amount, rgb = fog
        ms = scene.world.mist_settings
        ms.start, ms.depth, ms.falloff = start, depth, "LINEAR"
        ng.nodes["FogColour"].outputs[0].default_value = tuple(v / (2.0 ** exposure) for v in lin(rgb)) + (1.0,)
    ng.nodes["FogAmount"].inputs[1].default_value = fog_amount
    gl = ng.nodes["Glare"]
    if spec:
        kind, thr, strength, size = spec
        gl.mute = False
        gl.inputs["Type"].default_value = _GLARE_TYPES.get(kind, kind)
        gl.inputs["Quality"].default_value = "High"
        gl.inputs["Threshold"].default_value = thr / (2.0 ** exposure)
        gl.inputs["Strength"].default_value = strength
        gl.inputs["Size"].default_value = size
    else:
        gl.mute = True
    scene.compositing_node_group = ng
    scene.render.use_compositing = True


def orient(ob, direction, xaxis=None):
    d = Vector(direction).normalized()
    if xaxis is None:
        ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        return
    zax = -d
    xax = Vector(xaxis)
    xax = (xax - zax * xax.dot(zax)).normalized()
    yax = zax.cross(xax)
    ob.rotation_euler = Matrix((xax, yax, zax)).transposed().to_euler()


def add_light(coll, name, kind, loc, direction=None, energy=100.0, color=(1, 1, 1), size=(1, 1), spot_deg=45.0,
              blend=0.3, radius=0.25, xaxis=None):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "SPOT":
        ld.spot_size = math.radians(spot_deg)
        ld.spot_blend = blend
        ld.shadow_soft_size = radius
    elif kind == "POINT":
        ld.shadow_soft_size = radius
    elif kind == "AREA":
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = size
    ob = bpy.data.objects.new(name, ld)
    coll.objects.link(ob)
    ob.location = Vector(loc)
    if direction is not None:
        orient(ob, direction, xaxis)
    return ob


def camera(scene, loc, target, lens=24.0):
    cam = bpy.data.objects.get("LaunchCam")
    if cam is None:
        cam = bpy.data.objects.new("LaunchCam", bpy.data.cameras.new("LaunchCam"))
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.sensor_width = 36.0
    cam.data.sensor_fit = "HORIZONTAL"
    cam.data.clip_start = 0.05
    cam.data.clip_end = 2000.0
    cam.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


# =============================================================================================== lights per space
# Pass 2 (TwoArenas 2.8, critic #5a): the hue rides on the light. Cool blue-white keys and a navy ambient in the
# case hall, the pole hall and over the deck turn the shadows blue while the steel paint stays neutral; the red
# room keeps one cool white key down the tube and red light only in its two floor openings.
COOL = (0.86, 0.92, 1.0)                     # cool white: the key down the tube, the case top-lights
COOL_KEY = (0.55, 0.75, 1.0)                 # cool blue-white: the halls' and the deck's keys and light bars
DECK_KEY = (0.34, 0.57, 1.0)                 # the deck keys: the film's blue steel deck (frame B) from neutral paint
RED_KEY_DEG = 13.0                           # the key down the tube pools on the lift disc (pass 2 review: 20 -> 13, the apron stays dark)
# the cases stage (TwoArenas 2.3, 11-15 s): the pole hall's hub spots and wall bars are dimmed until the rise, so the
# ring of cases sits in the dim navy of its own profile (T1 @125.9 s); the ceiling ring's bars stay on at half
CASE_STAGE_DIM = {"Hall_HubSpot": 0.05, "Wall_": 2.0, "LED_": 2.6}
for _kv in filter(None, os.environ.get("LAUNCH_CASE_DIM", "").split(";")):      # look-dev: "LED_:0.6;Wall_:0.5"
    _k, _v = _kv.split(":")
    CASE_STAGE_DIM[_k] = float(_v)
CASE_STAGE_COL = (0.26, 0.65, 1.0)           # the case stage's deeper teal-navy on the hall's bars (review fix)
CASE_GANTRY_COL = (0.86, 0.92, 1.0)          # the gantry strips light the cases white in the case stage
if os.environ.get("LAUNCH_CASE_COL"):
    CASE_STAGE_COL = tuple(float(x) for x in os.environ["LAUNCH_CASE_COL"].split(","))
if os.environ.get("LAUNCH_GANTRY_COL"):
    CASE_GANTRY_COL = tuple(float(x) for x in os.environ["LAUNCH_GANTRY_COL"].split(","))
WARM_WHITE = (1.0, 0.95, 0.88)               # the lamp lenses
LAMP_LIGHT = (0.9, 0.94, 1.0)                # (review fix) the lamps' PointLights: white, so they light the rail pink, not the grates warm
if os.environ.get("LAUNCH_LAMP_COL"):
    LAMP_LIGHT = tuple(float(x) for x in os.environ["LAUNCH_LAMP_COL"].split(","))
RED_GLOW = (1.0, 0.36, 0.34)                 # the floor openings
GRATE_GLOW = (0.08, 0.26, 1.0)               # the dim navy light under each grate lane (review fix)
if os.environ.get("LAUNCH_GRATE_GLOW"):
    GRATE_GLOW = tuple(float(x) for x in os.environ["LAUNCH_GRATE_GLOW"].split(","))
LIGHT_GAIN = {"red_key": 24000.0, "opening": 60.0, "lamp": 220.0, "red_top": 3200.0, "walkway": 1200.0,
              "deck_key": 10000.0, "grate_glow": 280.0, "hub": 160000.0, "led": 450.0, "wall": 1200.0,
              "case": 1800.0, "unit": 60.0, "gantry": 3.0, "rider": 9000.0}
for _kv in filter(None, os.environ.get("LAUNCH_GAIN", "").split(";")):         # look-dev: "led:450;deck_key:9000"
    _k, _v = _kv.split(":")
    LIGHT_GAIN[_k] = float(_v)
if os.environ.get("LAUNCH_COOL_KEY"):
    COOL_KEY = tuple(float(x) for x in os.environ["LAUNCH_COOL_KEY"].split(","))
if os.environ.get("LAUNCH_DECK_KEY"):
    DECK_KEY = tuple(float(x) for x in os.environ["LAUNCH_DECK_KEY"].split(","))
if os.environ.get("LAUNCH_RED_KEY_DEG"):
    RED_KEY_DEG = float(os.environ["LAUNCH_RED_KEY_DEG"])
RED_KEY_BLEND = float(os.environ.get("LAUNCH_RED_KEY_BLEND", "0.45"))
RED_TOP_FILL = (-2.0, -3.0, 34.0, 0.0, 0.12, -1.0, 28.0, 24.0)   # position, direction, size of the light over the roof
RED_TOP_COL = (0.72, 0.84, 1.0)
if os.environ.get("LAUNCH_REDTOP_FILL"):
    RED_TOP_FILL = tuple(float(x) for x in os.environ["LAUNCH_REDTOP_FILL"].split(","))
if os.environ.get("LAUNCH_REDTOP_COL"):
    RED_TOP_COL = tuple(float(x) for x in os.environ["LAUNCH_REDTOP_COL"].split(","))
# exposure per shot (Lighting.ExposureCompensation, TwoArenas 2.8). The rise darkens the hall as the camera settles
# into the low-angle frame: the rider key keeps the rider readable while the hall falls away (T1 @127.2 s).
VIEW_EXPOSURE = {"red_a": 0.2, "red_b": 0.2, "red_interior": 0.2, "cases": 0.75, "case_bay": 0.75, "wide": 0.3,
                 "hall": 0.3, "rise": -0.2, "rise_end": 0.3}
# diffuse bounces per view (default 1). The red room renders with none (review fix): Roblox's local lights do not
# bounce, and the preview's one bounce carried the red rails' and apron's light into the grate pits (mauve, not navy)
VIEW_BOUNCES = {"red_a": 0, "red_b": 0, "red_interior": 0}
for _kv in filter(None, os.environ.get("LAUNCH_BOUNCES", "").split(";")):      # look-dev: "red_b:1"
    _k, _v = _kv.split(":")
    VIEW_BOUNCES[_k] = int(_v)
# the case hall's fireflies (review fix): the white speckle on the dark maroon posts and units came from indirect
# paths that find the small, bright light bars; the case views clamp indirect light harder and take more samples
VIEW_CLAMP = {"cases": 0.4, "case_bay": 0.4}
VIEW_SAMPLES = {"cases": 2.0, "case_bay": 1.5}
# a glare pass on the pole-hall views stands in for Roblox's bloom (TwoArenas 2.8: threshold 1.4): (type, threshold
# in Lighting units after exposure, strength, size). The film's hub spots read as one bright hanging cluster through it.
VIEW_GLARE = {"wide": ("FOG_GLOW", 1.4, 0.6, 0.8), "hall": ("FOG_GLOW", 1.4, 0.6, 0.8),
              "rise": ("FOG_GLOW", 1.4, 0.4, 0.6), "rise_end": ("FOG_GLOW", 1.4, 0.4, 0.6),
              "risepath": ("FOG_GLOW", 1.4, 0.4, 0.6)}
if os.environ.get("LAUNCH_GLARE_WIDE"):                                          # look-dev: "FOG_GLOW,1.4,0.5,0.7"
    _g = os.environ["LAUNCH_GLARE_WIDE"].split(",")
    VIEW_GLARE["wide"] = (_g[0], float(_g[1]), float(_g[2]), float(_g[3]))
# a thin navy haze in the pole hall (review fix, item 1d: the far wall and the ceiling ring were 14-22% too dark): the
# preview's stand-in for an Atmosphere in the pole hall's profile (start, depth, at most this much, sRGB colour)
VIEW_FOG = {"wide": (40.0, 300.0, 0.3, (30, 56, 84)), "hall": (40.0, 300.0, 0.3, (30, 56, 84))}
# the pole hall's own profile colours its hub spots and bars a little deeper than the shared cool key (review fix); the
# rise's profile a little greyer, as the film's rise frame is (T1 @127.2 s: dark quarter blue minus red only +6 to +9)
VIEW_HALL_COL = {"wide": (0.45, 0.7, 1.0), "hall": (0.45, 0.7, 1.0), "rise": (0.76, 0.84, 1.0),
                 "rise_end": (0.76, 0.84, 1.0), "risepath": (0.76, 0.84, 1.0)}
if os.environ.get("LAUNCH_RISE_COL"):
    for _k in ("rise", "rise_end", "risepath"):
        VIEW_HALL_COL[_k] = tuple(float(x) for x in os.environ["LAUNCH_RISE_COL"].split(","))
# per-view light dimming {view: {light prefix: factor}} (tried on the rise's end frame: dimming the ceiling ring's bars
# darkened the whole hall, not just the roof, so none is used)
VIEW_DIM = {}
if os.environ.get("LAUNCH_FOG_WIDE"):                                            # look-dev: "40,300,0.35,34,58,86"
    _g = [float(x) for x in os.environ["LAUNCH_FOG_WIDE"].split(",")]
    VIEW_FOG["wide"] = (_g[0], _g[1], _g[2], (_g[3], _g[4], _g[5]))
# (review fix) the rise's exposure ramps from the pole hall's to the end frame's: with the bars' Neon no longer lighting
# the hall in the preview, the hall needs less darkening than pass 2's -0.35
RISE_EXPOSURE = [(0.0, 0.45), (4.5, 0.45), (6.8, 0.3), (9.0, 0.3)]        # full cut, by t (s)
SHORT_EXPOSURE = [(0.0, 0.45), (2.0, 0.45), (3.4, 0.3), (5.0, 0.3)]       # short cut
for _kv in filter(None, os.environ.get("LAUNCH_EXPO", "").split(";")):         # look-dev: "rise:-0.5;wide:0.3"
    _k, _v = _kv.split(":")
    VIEW_EXPOSURE[_k] = float(_v)


def led_bars():
    """World endpoints of every light bar's emitting face in the hall: the ceiling ring (all 8 segments)."""
    return [e for seg in range(8) for e in led_bar_ends(seg, -1.85)]


def wall_bars():
    """(centre, inward normal, length) of every wall bar's emitting face (all 8 segments)."""
    out = []
    for seg in range(8):
        for b in WALL_BAR_BEARINGS:
            bb = b + 45.0 * seg
            n_in = (bearing(bb, 0.0) - bearing(bb, 1.0)).normalized()
            for z0, z1 in WALL_BAR_Z:
                out.append((bearing(bb, WALL_BAR_R - 0.2, (z0 + z1) / 2), n_in, z1 - z0))
    return out


def build_lights(assets):
    red_atts = assets["LaunchRedRoom"].atts
    G = LIGHT_GAIN
    L = {}
    c = L["red"] = new_collection("L_Red")
    # the key falls through the hex opening onto the lift and its apron only (a 20-degree cone); the walkway spot and
    # the four deck keys are cool and blue, so the steel deck reads blue under them (frame B)
    add_light(c, "Red_Key", "SPOT", red_atts["KeyLight"][0], (0, 0, -1), G["red_key"], COOL, spot_deg=RED_KEY_DEG,
              blend=RED_KEY_BLEND, radius=1.2)
    add_light(c, "Red_Walkway", "SPOT", red_atts["WalkwaySpot"][0], red_atts["WalkwaySpot"][1], G["walkway"],
              COOL_KEY, spot_deg=26, blend=0.5, radius=0.6)          # (review fix) narrower: it stays on the walkway
    for k, (p, d) in red_atts.items():
        if k.startswith("OpeningGlow"):
            w, dp = RED_PITS[int(k.split("_")[1]) - 1]
            add_light(c, "Red_" + k, "AREA", p, d, G["opening"] * (w * dp) / 20.0, RED_GLOW,
                      size=(w - 0.4, dp - 0.4))
        elif k.startswith("GrateGlow"):
            w, dp = RED_PITS_GRATE[int(k.split("_")[1]) - 1]
            add_light(c, "Red_" + k, "AREA", p, d, G["grate_glow"], GRATE_GLOW, size=(w - 0.5, dp - 0.5))
        elif k.startswith("DeckKey"):
            add_light(c, "Red_" + k, "SPOT", p, d, G["deck_key"], DECK_KEY, spot_deg=DECK_KEY_DEG, blend=0.7, radius=1.5)
        elif k.startswith("Lamp_") and G["lamp"] > 0:
            # (review fix) each lamp throws a white cone the way it faces, tipped 10 degrees down: the pair on the far
            # rail's post light the rail round the lift pink-red, as in frame B, and stay off the grates below them
            dd = (Vector(d).normalized() + Vector((0, 0, -0.18))).normalized()
            add_light(c, "Red_" + k, "SPOT", p, dd, G["lamp"], LAMP_LIGHT, spot_deg=50.0, blend=0.5, radius=0.3)
    c = L["redtop"] = new_collection("L_RedTop")
    # the dim cool light over the roof, seen only in frame A (pass 2 review: 4200 -> 3000, so the net, the frame and
    # the hood's oxblood sit in the band of T1 @120.2 s)
    fx, fy, fz, fdx, fdy, fdz, fsx, fsy = RED_TOP_FILL
    add_light(c, "RedTop_Fill", "AREA", (fx, fy, fz), (fdx, fdy, fdz), G["red_top"], RED_TOP_COL, size=(fsx, fsy))
    # the hall: hub spots, a SurfaceLight on every light bar (ceiling ring and walls); case lights, gantry rows, units
    c = L["hall"] = new_collection("L_Hall")
    for k, (p, d) in assets["LaunchPoleHallCrown"].atts.items():
        add_light(c, "Hall_" + k, "SPOT", p, d, G["hub"], COOL_KEY, spot_deg=34, blend=0.5, radius=0.9)
    for n, (pa, pb) in enumerate(led_bars()):
        add_light(c, "LED_%03d" % n, "AREA", (pa + pb) / 2, (0, 0, -1), G["led"], COOL_KEY,
                  size=((pb - pa).length, 0.5), xaxis=pb - pa)
    for n, (p, nrm, ln) in enumerate(wall_bars()):
        add_light(c, "Wall_%03d" % n, "AREA", p, nrm, G["wall"], COOL_KEY, size=(0.5, ln), xaxis=nrm.cross(Vector((0, 0, 1))))
    c = L["case"] = new_collection("L_Case")
    for i in range(N_BAYS):
        Mb = M_facing_centre(bay_bearing(i), CASE_R)
        R3 = Mb.to_3x3()
        p, d = assets["LaunchCaseBay"].atts["CaseLight"]
        # (review fix) the case's top light is a cone aimed down at the disc, so each raised dark-red disc catches it
        # as in T1 @125.9 s (a SurfaceLight, Face Bottom, Angle 50, in game); pass 2's flat panel left them near black.
        # The cone stays inside the case, off the walkway.
        add_light(c, "Case_%02d" % i, "SPOT", Mb @ (p + Vector((0, 0, -0.3))), R3 @ d, G["case"], COOL, spot_deg=50.0,
                  blend=0.5, radius=0.15)
        p, d = assets["LaunchCaseBay"].atts["UnitLight"]
        add_light(c, "Unit_%02d" % i, "AREA", Mb @ p, R3 @ d, G["unit"], COOL, size=(2.0, 0.5),
                  xaxis=R3 @ Vector((1, 0, 0)))
        for r in GANTRY_ROWS:
            b0, b1 = i * BAY_STEP + 0.6, (i + 1) * BAY_STEP - 0.6
            pa, pb = bearing(b0, r, GANTRY_Z - 0.15), bearing(b1, r, GANTRY_Z - 0.15)
            add_light(c, "Gantry_%02d_%d" % (i, int(r * 10)), "AREA", (pa + pb) / 2, (0, 0, -1), G["gantry"],
                      COOL_KEY, size=((pb - pa).length, 0.45), xaxis=pb - pa)
    L["rider"] = new_collection("L_Rider")
    for coll in L.values():
        coll.hide_render = True
    return L


# =============================================================================================== the rise plan
# Both cuts of TwoArenas 2.3 ride the same 120 studs of pole and end on the same frame: the film's low-angle,
# whole-body shot from in front of the rider (T1 @127.2 s: the disc's rim at the foot of the frame, the pole rising
# behind the head, a light bar either side), held while the opening above floods white. Pass 1 ended on the rider's
# side, in a close-up of the cloak and the pole under the roof (critic #5d); the film's frame is from the front, so the
# full cut now circles a whole turn (360 degrees, anticlockwise from above) and the short cut 155 degrees.
#   full   9 s (TwoArenas 2.3: 15.0-24.0 s from the call): starts in front of the case where the cases stage leaves
#          the camera, swings round at knee height once the disc is above the case gantry, and is back in front,
#          low, by t 6.8, while the rider is still in the open hall (disc y ~100); it holds that frame as the rider
#          climbs toward the opening, which floods white from t 7.4 (white by 9.0).
#   short  5 s (3.0-8.0 s from the call): a cut straight to the disc leaving the case, seen from behind and to the
#          right (clear of the case gantry behind the row), then 155 degrees round to the same end frame by t 3.4;
#          the opening floods from t 4.2.
END_FRAME = {"distance": 7.0, "below": 1.6, "pitchDeg": 35.0, "fovV": 42.0}   # camera from the rider's axis, below
#           the disc top; the look pitch and the vertical field of view of the end frame (T1 @127.2 s)
CUTS = {
    "full": {"T": 9.0, "acc": 2.0, "dec": 2.0, "phi0": 90.0, "orbit": 360.0, "orbitEnd": 6.8, "settle": (5.4, 6.8),
             "whiteout": (7.4, 9.0),
             "radius": [(0.0, 6.5), (3.0, 8.5), (5.0, 8.2), (6.8, END_FRAME["distance"]), (9.0, END_FRAME["distance"])],
             "height": [(0.0, 4.4), (2.5, -3.0), (5.0, -2.4), (6.8, -END_FRAME["below"]), (9.0, -END_FRAME["below"])],
             "fov": [(0.0, 50.0), (4.5, 54.0), (6.8, END_FRAME["fovV"]), (9.0, END_FRAME["fovV"])],
             "sheet": (0.0, 1.5, 3.0, 4.5, 6.0, 7.0, 8.2, 9.0)},
    "short": {"T": 5.0, "acc": 1.6, "dec": 1.4, "phi0": 295.0, "orbit": 155.0, "orbitEnd": 3.4, "settle": (2.4, 3.4),
              "whiteout": (4.2, 5.0),
              "radius": [(0.0, 6.8), (1.6, 7.8), (3.4, END_FRAME["distance"]), (5.0, END_FRAME["distance"])],
              "height": [(0.0, 3.0), (1.4, -2.4), (3.4, -END_FRAME["below"]), (5.0, -END_FRAME["below"])],
              "fov": [(0.0, 52.0), (2.0, 54.0), (3.4, END_FRAME["fovV"]), (5.0, END_FRAME["fovV"])],
              "sheet": (0.0, 1.2, 2.4, 3.6, 4.4, 5.0)},
}
RISE_T = CUTS["full"]["T"]


def rise_vmax(cut):
    c = CUTS[cut]
    return RISE / (c["acc"] / 2 + (c["T"] - c["acc"] - c["dec"]) + c["dec"] / 2)


def rise_s(t, cut="full"):
    """Studs climbed at t: accelerate, cruise, brake (one profile per cut)."""
    c = CUTS[cut]
    T, acc, dec = c["T"], c["acc"], c["dec"]
    vmax = rise_vmax(cut)
    a = vmax / acc
    t2 = T - dec
    if t <= 0:
        return 0.0
    if t < acc:
        return 0.5 * a * t * t
    s1 = 0.5 * a * acc ** 2
    if t < t2:
        return s1 + vmax * (t - acc)
    if t < T:
        dt = t - t2
        return s1 + vmax * (t2 - acc) + vmax * dt - 0.5 * (vmax / dec) * dt * dt
    return RISE


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * x * (x * (6 * x - 15) + 10)


def keyed(t, keys):
    """Piecewise smoothstep through (t, value) keys."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (ta, va), (tb, vb) in zip(keys[:-1], keys[1:]):
        if t <= tb:
            u = (t - ta) / (tb - ta)
            u = u * u * (3 - 2 * u)
            return va + (vb - va) * u
    return keys[-1][1]


def rise_camera_local(t, cut="full"):
    """Camera in the BAY frame (origin = bay floor centre, +Y toward the hall centre, Blender axes): position, look
    target, vertical field of view, disc top."""
    c = CUTS[cut]
    z_disc = DISC_TOP + rise_s(t, cut)
    phi = math.radians(c["phi0"] + c["orbit"] * smooth(t / c["orbitEnd"]))
    rho = keyed(t, c["radius"])
    pos = Vector((rho * math.cos(phi), DISC_Y + rho * math.sin(phi), z_disc + keyed(t, c["height"])))
    chest = Vector((0.0, DISC_Y, z_disc + 3.4))
    # the end frame's look: from the camera toward the rider's axis, pitched up END_FRAME pitchDeg
    hor = Vector((0.0, DISC_Y, pos.z)) - pos
    hor = hor.normalized() if hor.length > 1e-6 else Vector((0.0, -1.0, 0.0))
    pitch = math.radians(END_FRAME["pitchDeg"])
    end_look = pos + (hor * math.cos(pitch) + Vector((0.0, 0.0, math.sin(pitch)))) * 8.0
    to_chest = (chest - pos).normalized() * 8.0
    w = smooth((t - c["settle"][0]) / (c["settle"][1] - c["settle"][0]))
    look = pos + to_chest.lerp(end_look - pos, w)
    return pos, look, keyed(t, c["fov"]), z_disc


def rise_exposure(t, cut="full"):
    return keyed(t, RISE_EXPOSURE if cut == "full" else SHORT_EXPOSURE)


def rise_profile_weight(t, cut="full"):
    """0 = the pole hall's lighting profile, 1 = the rise profile: it follows the exposure ramp."""
    keys = RISE_EXPOSURE if cut == "full" else SHORT_EXPOSURE
    e0, e1 = keys[0][1], keys[-1][1]
    return min(1.0, max(0.0, (e0 - rise_exposure(t, cut)) / (e0 - e1))) if e0 != e1 else 0.0


def rise_ambient(t, cut="full"):
    w = rise_profile_weight(t, cut)
    return tuple(int(round(a + (b - a) * w)) for a, b in zip(AMBIENT["hall"], AMBIENT["rise"]))


def whiteout_weight(t, cut="full"):
    w0, w1 = CUTS[cut]["whiteout"]
    return smooth((t - w0) / (w1 - w0))


def to_rbx(v):
    return [float(v[0]), float(v[2]), float(-v[1])]


def rise_plan(assets, inst, bay=0):
    """Samples both cuts at 10 Hz, checks the camera's clearance against the set and its line of sight to the rider,
    returns the plan (the manifest's rise.keys for the full cut, rise.cuts for both)."""
    excl = set(o.name for o in inst["discs"][bay])
    obs = [o for o in inst["hall"] if not o.hide_render and o.name not in excl]
    bpy.context.view_layer.update()
    bvh = bvh_from_objects(obs)
    own_pole = set(o.name for o in inst["poles"][bay])
    see = [o for o in obs if o["cls"] != "glass"]                  # sight passes through the case glass
    bvh_see = bvh_from_objects(see)
    bvh_np = bvh_from_objects([o for o in see if o.name not in own_pole])
    Mb = M_facing_centre(bay_bearing(bay), CASE_R)
    cuts = {}
    for cut, c in CUTS.items():
        keys, worst = [], (1e9, 0.0)
        occluded, occluded_not_pole = [], []
        for i in range(int(round(c["T"] * 10)) + 1):
            t = i / 10.0
            p, look, fov, zd = rise_camera_local(t, cut)
            pw = Mb @ p
            near = bvh.find_nearest(pw)
            dist = near[3] if near[0] is not None else 1e9
            if dist < worst[0]:
                worst = (dist, t)
            chest_w = Mb @ Vector((0.0, DISC_Y, zd + 3.4))
            d = chest_w - pw
            if bvh_see.ray_cast(pw, d.normalized(), d.length - 0.5)[0] is not None:
                occluded.append(round(t, 1))
                if bvh_np.ray_cast(pw, d.normalized(), d.length - 0.5)[0] is not None:
                    occluded_not_pole.append(round(t, 1))
            keys.append({"t": round(t, 2), "discTopY": round(zd, 3),
                         "cameraBay": [round(v, 3) for v in to_rbx(p)],
                         "lookAtBay": [round(v, 3) for v in to_rbx(look)],
                         "fovV": round(fov, 2), "exposure": round(rise_exposure(t, cut), 3),
                         "riseProfile": round(rise_profile_weight(t, cut), 3),
                         "whiteout": round(whiteout_weight(t, cut), 3)})
        vmax = rise_vmax(cut)
        cuts[cut] = {
            "duration": c["T"], "riseStuds": RISE,
            "profile": "accelerate %.1f s, cruise %.1f s at %.2f studs/s, brake %.1f s" % (
                c["acc"], c["T"] - c["acc"] - c["dec"], vmax, c["dec"]),
            "peakSpeed": round(vmax, 3), "accel": round(vmax / c["acc"], 3),
            "orbitDeg": c["orbit"], "orbitStartDeg": c["phi0"],
            "orbitDirection": "anticlockwise seen from above; 90 = in front of the rider (toward the hall centre), "
                              "180 = the rider's left, 270 = behind",
            "orbitEndsAt": c["orbitEnd"], "settle": list(c["settle"]), "whiteout": list(c["whiteout"]),
            "radiusKeys": c["radius"], "heightKeys": c["height"], "fovKeys": c["fov"],
            "exposureKeys": RISE_EXPOSURE if cut == "full" else SHORT_EXPOSURE,
            "minClearance": round(worst[0], 3), "minClearanceAt": worst[1],
            "lineOfSightBlockedAt": occluded, "blockedByOtherThanOwnPoleAt": occluded_not_pole,
            "samples": len(keys), "keys": keys,
        }
        log("RISE %-5s %.0f studs in %.1f s, peak %.1f studs/s, orbit %.0f deg, camera min clearance %.2f at t=%.1f s, "
            "sight to the chest blocked at t=%s (by something other than the rider's own pole at t=%s)" % (
                cut, RISE, c["T"], vmax, c["orbit"], worst[0], worst[1], occluded, occluded_not_pole))
    full = cuts["full"]
    plan = {
        "bayFrame": "relative to the case bay's CFrame (origin = bay floor centre, LookVector = toward the hall "
                    "centre); multiply by the bay's CFrame for world positions",
        "poleBaseY": POLE_BASE, "poleTopY": round(POLE_TOP, 3), "poleLength": round(POLE_TOP - POLE_BASE, 3),
        "discStartY": DISC_TOP, "discEndY": DISC_TOP + RISE, "riseStuds": RISE,
        "endFrame": dict(END_FRAME, reference="the film's low-angle, whole-body frame (T1 @127.2 s): in front of "
                                              "the rider, just below the disc, looking up past the body to the pole"),
        "cuts": cuts,
        # pass 1's field names, kept for the full cut so a LaunchController reading rise.keys keeps working
        "duration": full["duration"], "profile": full["profile"], "peakSpeed": full["peakSpeed"],
        "accel": full["accel"], "orbitDeg": full["orbitDeg"], "orbitDirection": full["orbitDirection"],
        "radiusKeys": full["radiusKeys"], "heightKeys": full["heightKeys"], "fovKeys": full["fovKeys"],
        "minClearance": full["minClearance"], "minClearanceAt": full["minClearanceAt"],
        "samples": full["samples"], "keys": full["keys"],
    }
    return plan


# =============================================================================================== previews
# Each compare view is set beside the owner's frame and the clean trailer frame of the same shot (the owner's copies
# of the wide, case and rise shots carry video-player icons). Film frames are study-only: the sheets are written as
# compare_*.png into the preview folder, whose .gitignore keeps them out of the repo.
FRAMES = {
    "red_a": [("launch_1_red_room_net_a.png", "OWNER, T1 @120.2 S"), ("trailer1_120.7s.png", "T1 @120.7 S")],
    "red_b": [("launch_1_red_room_net_b.png", "OWNER, T1 @122.7 S"), ("trailer1_122.7s.png", "T1 @122.7 S")],
    "cases": [("launch_2_glass_cases.png", "OWNER, T1 @125.9 S"), ("trailer1_125.9s.png", "T1 @125.9 S")],
    "wide": [("launch_3_pole_hall_wide.png", "OWNER, T1 @124.7 S"), ("trailer1_124.7s.png", "T1 @124.7 S")],
    "rise": [("launch_3_pole_rise.png", "OWNER, T1 @127.2 S"), ("trailer1_127.2s.png", "T1 @127.2 S")],
    "rise_end": [("trailer1_127.2s.png", "T1 @127.2 S, THE END FRAME")],
}
TITLES = {"red_a": "RED ROOM, LOOKING DOWN THROUGH THE HEX FRAME", "red_b": "RED ROOM, THE STEEL DECK",
          "cases": "THE GLASS-CASE HALL", "wide": "THE POLE HALL", "rise": "THE RISE, LOW ANGLE (DISC Y 62)",
          "rise_end": "THE END FRAME OF THE RISE, FULL CUT T = 7.0 S"}


def frame_path(fname):
    """Owner frames live in REF; trailer frames (trailer*.png) in TRAILER."""
    return os.path.join(TRAILER if fname.startswith("trailer") else REF, fname)


def _cam_env(name, default):
    """(position, target, lens) for a compare view; env LAUNCH_CAM_<NAME> = "x,y,z,tx,ty,tz,lens" overrides it while
    a view is being framed."""
    v = os.environ.get("LAUNCH_CAM_" + name)
    if not v:
        return default
    f = [float(x) for x in v.split(",")]
    return (tuple(f[0:3]), tuple(f[3:6]), f[6])


# frame A (pass 2 review fix): the in-game shot of TwoArenas 2.4. The camera is just above the tube mouth (7.5 studs
# over the frame) and looks down 75 degrees with the design's opening field of view (50 vertical), so the far half of
# the hexagon frames the picture as in T1 @120.2 s: its apex at the top, its side corners half way down at the edges.
# The player's own stand-in stands on the lift disc (Spawn) far below, looking up; from this angle it sits low in the
# frame, where the film shows the rose disc. (Pass 2's first try put the stand-in on the escort's walkway behind a
# rail, seen at 47 degrees: not a shot the game can take.) The last value is the vertical field of view.
RED_A_CAM = _cam_env("RED_A", ((0.0, 2.0, 30.0), (0.0, 10.0, 0.15), 50.0))       # red room frame (world)
RED_A_YAW = 0.0                    # the stand-in faces +Y, toward the camera's side of the tube, and looks up
# the case frame (T1 @125.9 s; TwoArenas 2.4 "at face height just outside your glass, looking past you along the
# row"): just outside the player's front glass at face height (the disc top is at 1.6), looking past the player's head
# along the row toward bay 1: the next case's posts, the maroon unit with its light panel, the neighbours, the strip
# lights overhead and the navy hall beyond. Our cases stand 14.4 studs apart with the pole behind each disc, so the
# film's over-the-shoulder from inside the case is not possible here.
CASES_CAM = _cam_env("CASES", ((8.0, 4.4, 6.6), (-24.0, 0.0, 5.3), 35.0))        # in bay 0's frame
CASES_YAW = float(os.environ.get("LAUNCH_CASES_YAW", "60"))   # the player turns 60 degrees toward the row
# the wide frame (T1 @124.7 s; T2 @133.9 s), review fix: from the far side of the hall, on the banked ring by the
# wall at about the riders' height, with an 18 mm lens pitched up 20 degrees: the spoked ring reads as an ellipse across
# the top with the hub's hanging cluster under it, the poles stand nearly vertical and the far riders sit in a line in
# the lower third. (Pass 2's first try was an 8.8 mm lens tilted 39 degrees up from the case ring: a look up a dome.)
WIDE_CAM = _cam_env("WIDE", ((-6.0, -176.0, 45.0), (14.0, 0.0, 108.0), 18.0))     # the pole hall (world)
WIDE_RIDER_Z = float(os.environ.get("LAUNCH_WIDE_RIDER_Z", "45"))


class Previewer:
    def __init__(self, assets, inst, lights, rise):
        self.assets, self.inst, self.L, self.rise = assets, inst, lights, rise
        self.scene = bpy.context.scene
        self.samples = 40 if QUALITY == "draft" else 160
        self.width = 760 if QUALITY == "draft" else 1100
        self.stats = {}
        self.figs = new_collection("Figures")
        os.makedirs(PREV, exist_ok=True)
        # (review fix) a Neon part glows in Roblox but lights nothing and nothing reflects it: the SurfaceLights on the
        # bars do the lighting. So the preview's neon meshes are seen by the camera only. That ends the white speckle
        # the dark maroon posts caught from the small bright bars, and the lights' gains are now the ones the game
        # needs (pass 2 had the bars' white glow lighting the halls as well, which greyed the navy).
        neon_lights = os.environ.get("LAUNCH_NEON_LIGHT", "0") != "0"
        for o in bpy.data.objects:
            if o.get("cls") == "neon":
                o.visible_glossy = False
                o.visible_transmission = False
                o.visible_shadow = False
                o.visible_diffuse = neon_lights

    def show(self, colls):
        for c in self.scene.collection.children:
            c.hide_render = c.name not in colls
        for c in self.L.values():
            c.hide_render = c.name not in colls

    def clear_figs(self):
        for o in list(self.figs.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        for o in list(self.L["rider"].objects):
            bpy.data.objects.remove(o, do_unlink=True)

    def fig(self, kind, M, district=None, look_up=0.0):
        return figure_object(kind, "Fig_%d" % len(self.figs.objects), M, self.figs, district, look_up)

    def bay_M(self, i):
        return M_facing_centre(bay_bearing(i), CASE_R)

    def set_disc(self, i, z_top):
        Mb = self.bay_M(i)
        for o in self.inst["discs"][i]:
            o.matrix_world = Mb @ Matrix.Translation((0, DISC_Y, z_top))

    def reset_discs(self):
        for i in range(N_BAYS):
            self.set_disc(i, DISC_TOP)

    def rider(self, i, z_top, yaw_extra=0.0, district=None, look_up=0.0, kind="tribute"):
        Mb = self.bay_M(i)
        return self.fig(kind, Mb @ Matrix.Translation((0, DISC_Y, z_top)) @ Matrix.Rotation(
            math.radians(yaw_extra), 4, "Z"), district, look_up)

    def rider_key(self, i, z_top):
        """The key that rides up with the rider (TwoArenas 2.8): cool white, in front of and above the rider."""
        Mb = self.bay_M(i)
        D = Mb @ Vector((0, DISC_Y, z_top))
        n_in = (Mb.to_3x3() @ Vector((0, 1, 0))).normalized()
        src = D + n_in * 7.0 + Vector((0, 0, 10.0))
        add_light(self.L["rider"], "Rider_Key", "SPOT", src, (D + Vector((0, 0, 3.0))) - src, LIGHT_GAIN["rider"],
                  COOL, spot_deg=36, blend=0.6, radius=0.8)
        return D, n_in

    def render(self, name, aspect, exposure, ambient):
        exposure = VIEW_EXPOSURE.get(name, exposure)
        set_ambient(ambient)
        w = self.width
        h = int(round(w * aspect[1] / aspect[0]))
        render_settings(self.scene, (w, h), int(self.samples * VIEW_SAMPLES.get(name, 1.0)), exposure)
        b = VIEW_BOUNCES.get(name)
        if b is not None:
            self.scene.cycles.diffuse_bounces = b
        if name in VIEW_CLAMP:
            self.scene.cycles.sample_clamp_indirect = VIEW_CLAMP[name]
        key = "risepath" if name.startswith("risepath") else name
        set_glare(self.scene, VIEW_GLARE.get(key), exposure, VIEW_FOG.get(key))
        saved = []                       # the pole hall's own profile colours its bars and spots (VIEW_HALL_COL)
        if VIEW_HALL_COL.get(key):
            for o in self.L["hall"].objects:
                if o.name.startswith(("Hall_", "LED_", "Wall_")):
                    saved.append((o, tuple(o.data.color)))
                    o.data.color = VIEW_HALL_COL[key]
        saved_e = []                     # and dims some of them (VIEW_DIM: the rise's end frame keeps its roof dark)
        for o in self.L["hall"].objects:
            for prefix, f in VIEW_DIM.get(key, {}).items():
                if o.name.startswith(prefix):
                    saved_e.append((o, o.data.energy))
                    o.data.energy *= f
        path = os.path.join(PREV, "render_%s.png" % name)
        self.scene.render.filepath = path
        t = time.time()
        bpy.ops.render.render(write_still=True)
        for o, col in saved:
            o.data.color = col
        for o, e in saved_e:
            o.data.energy = e
        log("PREVIEW %s (%.0fs)" % (path, time.time() - t))
        return path

    def case_stage(self, on):
        """The case hall's lighting profile (TwoArenas 2.3, 11-15 s), on or off: the pole hall's hub spots off, its bars
        at CASE_STAGE_DIM in a deeper teal-navy (CASE_STAGE_COL), the gantry strips white (review fix)."""
        if on:
            self._case_saved = {}
            for prefix, f in CASE_STAGE_DIM.items():
                self.scale_lights("hall", prefix, f)
            for ck in ("hall", "case"):
                for o in self.L[ck].objects:
                    if o.name.startswith(("Hall_", "LED_", "Wall_", "Gantry_")):
                        self._case_saved[o.name] = tuple(o.data.color)
                        o.data.color = ((CASE_GANTRY_COL or CASE_STAGE_COL) if o.name.startswith("Gantry_")
                                        else CASE_STAGE_COL)
        else:
            for ck in ("hall", "case"):
                for o in self.L[ck].objects:
                    if o.name in self._case_saved:
                        o.data.color = self._case_saved[o.name]
            for prefix, f in CASE_STAGE_DIM.items():
                self.scale_lights("hall", prefix, 1.0 / f)

    def compare(self, name, path):
        frames = [(frame_path(f), cap) for f, cap in FRAMES[name] if os.path.exists(frame_path(f))]
        if not frames:
            log("NOTE no reference frame for %s; render only" % name)
            self.stats[name] = {"ours": colour_stats(load_rgb(path)), "frames": None}
            return
        out = os.path.join(PREV, "compare_%s.png" % name)
        ours, film = compare_sheet(path, frames, out, TITLES[name])
        self.stats[name] = {"ours": ours, "frames": {cap: s for (_, cap), s in zip(frames, film)}}
        log("PREVIEW %s" % out)

    def scale_lights(self, coll_key, prefix, factor):
        for o in self.L[coll_key].objects:
            if o.name.startswith(prefix):
                o.data.energy *= factor

    # -- the compare views
    def v_red_a(self):
        """Frame A, the in-game red-room shot (TwoArenas 2.4; the manifest's sequence stage 1): from just above the
        tube mouth, looking steeply down through the far half of the hexagon at the player's own stand-in in the white
        launch cape on the lift disc (Spawn), far below, looking up into the tube (T1 @120.2 s). See RED_A_CAM."""
        self.show({"RedRoom", "L_Red", "L_RedTop", "Figures"})
        self.fig("tribute", M_place(self.assets["LaunchRedRoom"].atts["Spawn"][0], RED_A_YAW), look_up=38.0)
        cam = camera(self.scene, Vector(RED_A_CAM[0]), Vector(RED_A_CAM[1]))
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle = math.radians(RED_A_CAM[2])
        path = self.render("red_a", (656, 277), 0.2, "red")
        cam.data.sensor_fit = "HORIZONTAL"
        return path

    def v_red_b(self):
        """Frame B: from just above and behind the player on the lift, over the near rail to the black grates; red
        only in the two floor openings beside the lift."""
        self.show({"RedRoom", "L_Red", "Figures"})
        self.fig("tribute", M_place((0, 0, 0.15), -14.0))
        self.fig("guard", M_place(self.assets["LaunchRedRoom"].atts["GuardFloor"][0], 200.0))
        self.fig("guard", M_place(self.assets["LaunchRedRoom"].atts["GuardWalkway"][0], 180.0))
        camera(self.scene, (0.45, -2.9, 10.6), (0.2, 6.0, 0.0), lens=18.0)
        return self.render("red_b", (635, 284), 0.2, "red")

    def v_cases(self):
        """The film's frame (T1 @125.9 s): past the player's head along the row at the neighbours in their cases, the
        navy hall beyond (see CASES_CAM)."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        for i in (47, 0, 1, 2, 3, 4, 5, 6, 7, 8):          # every case along the view is filled, as in the film
            # the player (in the launch cape) turns to look along the row at the neighbour, as the film's tribute does
            # (CASES_YAW); the neighbours stand in their suits, so their discs show (review fix)
            self.rider(i, DISC_TOP, CASES_YAW if i == 0 else 0.0, "yellow" if i == 1 else None,
                       kind="tribute" if i == 0 else "suit")
        Mb = self.bay_M(0)
        cam_p, look, lens = CASES_CAM
        camera(self.scene, Mb @ Vector(cam_p), Mb @ Vector(look), lens=lens)
        # the case-hall profile (case_stage): the pole hall's hub spots stay off until the rise, and (review fix) its
        # bars take a deeper teal-navy while the cases are on screen; the gantry strips light the cases white
        self.case_stage(True)
        p = self.render("cases", (664, 314), 0.2, "case")
        self.case_stage(False)
        return p

    def v_wide(self):
        """From the floor near the case ring across the hall: the far ring of poles with riders part-way up, the
        spoked ring above with the hub's spots, the ceiling ring's light bars fanning out beyond the hub."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        rng = random.Random(7)
        cam_b = (math.degrees(math.atan2(WIDE_CAM[0][0], WIDE_CAM[0][1])) + 360.0) % 360.0
        for i in sorted(IN_USE):
            z = WIDE_RIDER_Z + rng.uniform(-5, 5)        # staggered heights (TwoArenas 2.6)
            if abs((bay_bearing(i) - cam_b + 180.0) % 360.0 - 180.0) < 25.0:
                z = 20.0 + rng.uniform(-2, 2)            # the riders beside the camera have only just left their cases
            self.set_disc(i, z)
            self.rider(i, z)
        cam_p, look, lens = WIDE_CAM
        camera(self.scene, cam_p, look, lens=lens)
        p = self.render("wide", (662, 323), 0.3, "hall")
        self.reset_discs()
        return p

    def end_frame_camera(self, i, z_disc):
        """The end frame (END_FRAME) for rider i with its disc top at z_disc: in front, just below the disc."""
        Mb = self.bay_M(i)
        pos = Mb @ Vector((0.0, DISC_Y + END_FRAME["distance"], z_disc - END_FRAME["below"]))
        n_out = (Mb.to_3x3() @ Vector((0, -1, 0))).normalized()
        pitch = math.radians(END_FRAME["pitchDeg"])
        look = pos + (n_out * math.cos(pitch) + Vector((0, 0, math.sin(pitch)))) * 8.0
        cam = camera(self.scene, pos, look, lens=24.0)
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle = math.radians(END_FRAME["fovV"])
        return cam

    def v_rise(self):
        """The film's low-angle, whole-body frame (T1 @127.2 s) mid-hall: in front of and just below a rider at disc
        y 62, the pole rising behind the head, the dark rods of the neighbours, the light bars of the walls and the
        ceiling ring beyond."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures", "L_Rider"})
        rng = random.Random(11)
        for i in sorted(IN_USE):
            z = 62.0 if i == 0 else 56.0 + rng.uniform(-5, 7)
            self.set_disc(i, z)
            self.rider(i, z, look_up=30.0 if i == 0 else 0.0)
        self.rider_key(0, 62.0)
        cam = self.end_frame_camera(0, 62.0)
        p = self.render("rise", (657, 306), 0.3, "rise")
        cam.data.sensor_fit = "HORIZONTAL"
        self.reset_discs()
        return p

    def v_rise_end(self):
        """The rise's own camera keys at t 7.0 s of the full cut: the end frame, held until the opening floods."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures", "L_Rider"})
        t = 7.0
        rng = random.Random(11)
        p, look, fov, zd = rise_camera_local(t, "full")
        for i in sorted(IN_USE):
            z = zd if i == 0 else zd + rng.uniform(-14, 10)
            self.set_disc(i, z)
            self.rider(i, z, look_up=30.0 if i == 0 else 0.0)
        self.rider_key(0, zd)
        Mb = self.bay_M(0)
        cam = camera(self.scene, Mb @ p, Mb @ look, lens=24.0)
        cam.data.sensor_fit = "VERTICAL"
        cam.data.angle = math.radians(fov)
        path = self.render("rise_end", (657, 306), 0.3, "rise")
        cam.data.sensor_fit = "HORIZONTAL"
        self.reset_discs()
        return path

    # -- overviews (ours only)
    def v_red_interior(self):
        self.show({"RedRoom", "L_Red", "Figures"})
        self.fig("tribute", M_place((0, 0, 0.15), 8.0))
        self.fig("guard", M_place(self.assets["LaunchRedRoom"].atts["GuardFloor"][0], 200.0))
        self.fig("guard", M_place(self.assets["LaunchRedRoom"].atts["GuardWalkway"][0], 180.0))
        camera(self.scene, (-12.6, -11.2, 17.2), (3.0, 4.0, 2.5), lens=13.0)
        return self.render("overview_red_room", (16, 9), 0.2, "red")

    def v_case_bay(self):
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        for i in (47, 0, 1):
            self.rider(i, DISC_TOP, kind="tribute" if i == 0 else "suit")
        Mb = self.bay_M(0)
        camera(self.scene, Mb @ Vector((3.2, 9.5, 5.6)), Mb @ Vector((-0.6, 0.3, 4.6)), lens=24.0)
        self.case_stage(True)
        p = self.render("overview_case_bay", (16, 9), 0.3, "case")
        self.case_stage(False)
        return p

    def v_hall(self):
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        for i in sorted(IN_USE):
            self.rider(i, DISC_TOP)
        camera(self.scene, (0.0, -166.0, 64.0), (0.0, 40.0, 34.0), lens=13.5)
        return self.render("overview_pole_hall", (16, 9), 0.3, "hall")

    def rise_tiles(self, cut, width, samples, others):
        """Frames along one cut's camera keys, with the opening's flood and the whiteout. others: {bay: (figure,
        height offset)}: the neighbours ride at staggered heights, 6-16 studs above or below (TwoArenas 2.6)."""
        c = CUTS[cut]
        Mb = self.bay_M(0)
        tiles = []
        cam = None
        for t in c["sheet"]:
            for o in list(self.L["rider"].objects):
                bpy.data.objects.remove(o, do_unlink=True)
            p, look, fov, zd = rise_camera_local(t, cut)
            self.set_disc(0, zd)
            for i, (fig, dz) in others.items():
                z = min(DISC_TOP + RISE, max(DISC_TOP, zd + dz))
                self.set_disc(i, z)
                fig.matrix_world = self.bay_M(i) @ Matrix.Translation((0, DISC_Y, z))
            rid = self.rider(0, zd, look_up=30.0 * smooth(t / c["orbitEnd"]))
            self.rider_key(0, zd)
            w0 = c["whiteout"][0]
            if t >= w0 - 0.8:                        # the opening above starts to flood with light
                ap = Mb @ Vector((0.0, POLE_Y, POLE_TOP - 1.2))
                add_light(self.L["rider"], "Aperture_Flood", "SPOT", ap, (0, 0, -1),
                          60000.0 * smooth((t - (w0 - 0.8)) / 1.6), (1.0, 0.99, 0.97), spot_deg=70, blend=0.8,
                          radius=1.6)
            cam = camera(self.scene, Mb @ p, Mb @ look, lens=24.0)
            cam.data.sensor_fit = "VERTICAL"
            cam.data.angle = math.radians(fov)
            old_w, old_s = self.width, self.samples
            self.width, self.samples = width, samples
            path = self.render("risepath_%s_t%04.1f" % (cut, t), (16, 9), rise_exposure(t, cut), rise_ambient(t, cut))
            self.width, self.samples = old_w, old_s
            img = load_rgb(path)
            wgt = whiteout_weight(t, cut)
            if wgt > 0:
                img = img * (1 - wgt) + np.ones_like(img) * wgt * 0.97
            draw_text(img, 10, 10, "%s CUT  T = %.1f S   DISC Y %.0f" % (cut.upper(), t, zd), 2,
                      (0.1, 0.1, 0.12) if wgt > 0.6 else (0.93, 0.93, 0.9))
            tiles.append(img)
            bpy.data.objects.remove(rid, do_unlink=True)
            os.remove(path)
        if cam is not None:
            cam.data.sensor_fit = "HORIZONTAL"
        return tiles

    def rise_sheet(self):
        """Two rows for the full cut (9 s, a whole turn), one for the short cut (5 s, about half a turn)."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures", "L_Rider"})
        rng = random.Random(5)
        others = {}
        for i in sorted(IN_USE):
            if i:
                dz = rng.uniform(6.0, 16.0) * (1 if rng.random() < 0.5 else -1)
                others[i] = (self.rider(i, DISC_TOP), dz)
        width, samples = 520, max(24, self.samples // 4)
        lines = []
        for cut in ("full", "short"):
            tiles = self.rise_tiles(cut, width, samples, others)
            for k in range(0, len(tiles), 4):
                lines.append(tiles[k:k + 4])
        h, w = lines[0][0].shape[:2]
        cols = 4
        sheet = np.full((len(lines) * (h + 8) + 66, cols * (w + 8), 3), 0.07)
        for r_, line in enumerate(lines):
            for c_, img in enumerate(line):
                sheet[r_ * (h + 8):r_ * (h + 8) + h, c_ * (w + 8):c_ * (w + 8) + w] = img
        y = len(lines) * (h + 8) + 10
        f, s = CUTS["full"], CUTS["short"]
        draw_text(sheet, 10, y, "THE RISE, ONE SHOT, %.0f STUDS. FULL CUT %.0f S: A WHOLE TURN FROM THE FRONT. SHORT "
                  "CUT %.0f S: %.0f DEG FROM BEHIND RIGHT. BOTH END ON THE LOW-ANGLE FRAME, THEN WHITE OUT"
                  % (RISE, f["T"], s["T"], s["orbit"]), 2)
        draw_text(sheet, 10, y + 24, SHEET_LABEL, 2, (0.95, 0.78, 0.35))
        out = os.path.join(PREV, "rise_path_sheet.png")
        save_rgb(out, sheet)
        self.reset_discs()
        log("PREVIEW %s" % out)

    def palette_sheet(self):
        """Swatches: sampled frame colour -> semi-real tone, with RGB, luma and HSV saturation (the reds' check)."""
        keys = [k for k in PAL if PAL[k][4] != "neon"]
        sw, sh_, pad = 64, 40, 8
        cols = 3
        rows = (len(keys) + cols - 1) // cols
        cw = sw * 2 + 400
        img = np.full((rows * (sh_ + pad) + 74, cols * cw, 3), 0.1)
        draw_text(img, 10, 10, "LAUNCH PALETTE, PASS 2: SAMPLED -> TONE. RGB, LUMA, SATURATION (REDS: THE "
                               "SAMPLE'S, WITHIN 0.05)", 2)
        for n, k in enumerate(keys):
            r_, c_ = divmod(n, cols)
            x0, y0 = c_ * cw + 10, 40 + r_ * (sh_ + pad)
            tone, sampled = PAL[k][0], PAL[k][1]
            line2 = "%d %d %d  L%.0f  S%.2f" % (tone[0], tone[1], tone[2], luma(tone), hsv_sat(tone))
            if sampled:
                s = tuple(int(sampled[i:i + 2], 16) for i in (1, 3, 5))
                img[y0:y0 + sh_, x0:x0 + sw] = np.array(s) / 255.0
                if k in REDS:
                    line2 += " (%.2f)" % RED_SAMPLE_SAT.get(k, hsv_sat(s))
            img[y0:y0 + sh_, x0 + sw + 4:x0 + 2 * sw + 4] = np.array(tone) / 255.0
            draw_text(img, x0 + 2 * sw + 12, y0 + 6, k.replace("_", " "), 2)
            draw_text(img, x0 + 2 * sw + 12, y0 + 24, line2, 2)
        out = os.path.join(PREV, "palette_swatches.png")
        save_rgb(out, img)
        log("PREVIEW %s" % out)

    def run(self):
        views = [("red_a", self.v_red_a, True), ("red_b", self.v_red_b, True), ("cases", self.v_cases, True),
                 ("wide", self.v_wide, True), ("rise", self.v_rise, True), ("rise_end", self.v_rise_end, True),
                 ("red_interior", self.v_red_interior, False), ("case_bay", self.v_case_bay, False),
                 ("hall", self.v_hall, False)]
        for name, fn, cmp in views:
            if ONLY and name not in ONLY:
                continue
            self.clear_figs()
            path = fn()
            if cmp:
                self.compare(name, path)
            else:
                self.stats[name] = {"ours": colour_stats(load_rgb(path)), "frames": None}
        self.clear_figs()
        if not ONLY or "risepath" in ONLY:
            self.rise_sheet()
            self.clear_figs()
        if not ONLY or "palette" in ONLY:
            self.palette_sheet()
        cc = os.path.join(PREV, "colour_check.json")
        old = {}
        if ONLY and os.path.exists(cc):
            try:
                with open(cc, encoding="utf-8") as f:
                    old = json.load(f)
            except Exception:
                old = {}
        old.update(self.stats)
        old["reds"] = red_check()
        old["note"] = ("pass 2: whole-frame numbers (pass 1's measure, kept for comparison). The pass/fail band is "
                       "tools/art/colour_band.py on tools/art/specs/launch.json, region by region.")
        with open(cc, "w", encoding="utf-8") as f:
            json.dump(old, f, indent=1)
        for k, v in self.stats.items():
            log("COLOUR %-14s ours %s" % (k, v["ours"]))
            for cap, s in (v.get("frames") or {}).items():
                log("COLOUR %-14s film %s %s" % (k, cap, s))


def hsv_sat(c):
    mx, mn = max(c[:3]), min(c[:3])
    return (mx - mn) / mx if mx > 0 else 0.0


def red_check():
    """TwoArenas 8.2: each held red tone's saturation within 0.05 of its frame sample's. Under the 'band' oxblood
    ruling (OXBLOOD_RULING) the oxblood room surfaces are checked against the band instead: 0.65-0.85x the sample."""
    out = {}
    for k in REDS:
        tone, sampled = PAL[k][0], PAL[k][1]
        if not sampled and k not in RED_SAMPLE_SAT:
            continue
        s_samp = RED_SAMPLE_SAT.get(k) or hsv_sat(tuple(int(sampled[i:i + 2], 16) for i in (1, 3, 5)))
        s_tone = hsv_sat(tone)
        row = {"sampled": sampled, "sampledSat": round(s_samp, 3), "tone": list(tone), "toneSat": round(s_tone, 3),
               "diff": round(s_tone - s_samp, 3), "pass": abs(s_tone - s_samp) <= 0.05}
        if OXBLOOD_RULING == "band" and k in ("oxblood", "oxblood_dk"):
            ratio = s_tone / s_samp
            row.update({"rule": "room surface under the band: 0.65-0.85x the sample (ruling pending)",
                        "ratio": round(ratio, 3), "pass": 0.65 <= round(ratio, 2) <= 0.85})
        out[k] = row
    return out


# =============================================================================================== budgets
INSTANCES = {"LaunchRedRoom": 1, "LaunchCaseBay": N_BAYS, "LaunchCaseGallery": 8, "LaunchRiserDisc": N_BAYS,
             "LaunchPoleHallSegment": 8, "LaunchPoleHallCrown": 1, "LaunchPole": N_BAYS}
ASSET_ORDER = ["LaunchRedRoom", "LaunchCaseBay", "LaunchCaseGallery", "LaunchRiserDisc", "LaunchPoleHallSegment",
               "LaunchPoleHallCrown", "LaunchPole"]
ROOMS = ["LaunchRedRoom", "LaunchCaseHall", "LaunchPoleHall"]
PART_LIMIT = 5000
ROOM_LIMIT = 10000
ASSET_LIMIT = {"LaunchCaseBay": 1500, "LaunchPoleHallSegment": 5000, "LaunchRiserDisc": 600, "LaunchPole": 1500,
               "LaunchPoleHallCrown": 5000, "LaunchCaseGallery": 5000, "LaunchRedRoom": 10000}


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def check_budgets(assets):
    out = {"rooms": {}, "assets": {}, "warnings": []}
    for an in ASSET_ORDER:
        a = assets[an]
        parts = {pn: tri_count(m) for pn, m in a.masters.items()}
        total = sum(parts.values())
        out["assets"][an] = {"parts": parts, "tris": total, "instances": INSTANCES[an]}
        for pn, t in parts.items():
            lim = 4000 if (an == "LaunchRedRoom" and pn.startswith("Net")) else PART_LIMIT
            if t >= lim:
                out["warnings"].append("%s_%s has %d triangles (limit %d)" % (an, pn, t, lim))
        if total > ASSET_LIMIT.get(an, ROOM_LIMIT):
            out["warnings"].append("%s has %d triangles (limit %d)" % (an, total, ASSET_LIMIT[an]))
    for room in ROOMS:
        ans = [an for an in ASSET_ORDER if ROOM_OF[an] == room]
        uniq = sum(out["assets"][an]["tris"] for an in ans)
        drawn = sum(out["assets"][an]["tris"] * INSTANCES[an] for an in ans)
        out["rooms"][room] = {"assets": ans, "uniqueTris": uniq, "drawnTris": drawn}
        if uniq > ROOM_LIMIT:
            out["warnings"].append("%s holds %d unique triangles (limit %d)" % (room, uniq, ROOM_LIMIT))
    for room, v in out["rooms"].items():
        log("BUDGET %-16s unique %6d tris, drawn %7d tris (%s)" % (room, v["uniqueTris"], v["drawnTris"],
                                                                     ", ".join(v["assets"])))
    for an, v in out["assets"].items():
        log("BUDGET   %-22s %5d tris x%-2d  %s" % (an, v["tris"], v["instances"],
                                                   ", ".join("%s %d" % kv for kv in v["parts"].items())))
    for w in out["warnings"]:
        log("WARNING " + w)
    return out


# =============================================================================================== export
def hue_bucket(c):
    r, g, b = [x / 255.0 for x in c[:3]]
    mx, mn = max(r, g, b), min(r, g, b)
    if mx - mn < 0.08:
        return -1
    if mx == r:
        h = ((g - b) / (mx - mn)) % 6
    elif mx == g:
        h = (b - r) / (mx - mn) + 2
    else:
        h = (r - g) / (mx - mn) + 4
    return int(h * 2)


def build_atlas(room, paint_obs):
    cells, face_cells = {}, {}
    for ob in paint_obs:
        md = meta(ob)
        ids = []
        for i, c in enumerate(md["srgb"]):
            k = md["keys"][i]
            cell = (int(round(min(255, max(0, c[0])))), int(round(min(255, max(0, c[1])))),
                    int(round(min(255, max(0, c[2])))), int(round(PAL[k][2] * 255)), int(round(PAL[k][3] * 255)))
            ids.append(cells.setdefault(cell, len(cells)))
        face_cells[ob.name] = ids
    order = sorted(cells.keys(), key=lambda k: (k[4], k[3], hue_bucket(k), luma(k)))
    rank = {k: i for i, k in enumerate(order)}
    n = len(order)
    grid = 8
    while grid * grid < n:
        grid *= 2
    cell_px = 8 if grid * 8 <= 1024 else max(1, 1024 // grid)
    size = grid * cell_px
    color = np.zeros((size, size, 3))
    rough = np.zeros((size, size))
    metal = np.zeros((size, size))
    last = order[-1]
    for idx in range(grid * grid):
        k = order[idx] if idx < n else last
        cx, cy = idx % grid, idx // grid
        sl = (slice(cy * cell_px, (cy + 1) * cell_px), slice(cx * cell_px, (cx + 1) * cell_px))
        color[sl] = np.array(k[:3]) / 255.0
        rough[sl] = k[3] / 255.0
        metal[sl] = k[4] / 255.0
    uv_of = {}
    for k, idx in rank.items():
        cx, cy = idx % grid, idx // grid
        uv_of[cells[k]] = ((cx + 0.5) / grid, (cy + 0.5) / grid)
    face_uv = {name: [uv_of[i] for i in ids] for name, ids in face_cells.items()}
    folder = os.path.join(TEX, room)
    os.makedirs(os.path.join(folder, "glb_only"), exist_ok=True)
    files = {"color": os.path.join(folder, room + "_Color.png"), "rough": os.path.join(folder, room + "_Rough.png"),
             "metal": os.path.join(folder, room + "_Metal.png"),
             "mr": os.path.join(folder, "glb_only", room + "_MR.png")}
    tg.write_png(files["color"], color, quantize=False)
    tg.write_png(files["rough"], rough, quantize=False)
    tg.write_png(files["metal"], metal, quantize=False)
    tg.write_png(files["mr"], np.stack([np.ones_like(rough), rough, metal], axis=2), quantize=False)
    info = {"colours": n, "grid": grid, "cellPx": cell_px, "sizePx": size}
    log("ATLAS %s: %d colours in a %d px palette (%d px cells)" % (room, n, size, cell_px))
    return face_uv, files, info


def export_material(name, kind, files=None, rgb=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = True          # glTF doubleSided = false (single-sided, art/README.md)
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if kind == "paint":
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = bpy.data.images.load(files["color"], check_existing=True)
        tc.image.colorspace_settings.name = "sRGB"
        tc.interpolation = "Closest"
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
        tm = nt.nodes.new("ShaderNodeTexImage")
        tm.image = bpy.data.images.load(files["mr"], check_existing=True)
        tm.image.colorspace_settings.name = "Non-Color"
        tm.interpolation = "Closest"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    elif kind == "neon":
        c = lin(rgb) + (1.0,)
        bsdf.inputs["Base Color"].default_value = c
        bsdf.inputs["Emission Color"].default_value = c
        bsdf.inputs["Emission Strength"].default_value = 1.0
    else:
        bsdf.inputs["Base Color"].default_value = (lin(rgb) + (1.0,)) if kind == "glass" else (0.8, 0.8, 0.8, 1.0)
        bsdf.inputs["Alpha"].default_value = 0.35 if kind == "glass" else 0.0
        bsdf.inputs["Roughness"].default_value = 0.1
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    return m


def gltf_export(path):
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
              export_tangents=True, export_normals=True, export_texcoords=True, export_materials="EXPORT",
              export_cameras=False, export_lights=False, export_extras=False, export_image_format="AUTO",
              export_vertex_color="NONE")
    for _ in range(8):
        try:
            bpy.ops.export_scene.gltf(**kw)
            return
        except TypeError as e:
            msg = str(e)
            bad = [k for k in list(kw) if k != "filepath" and '"%s"' % k in msg]
            if not bad:
                raise
            for k in bad:
                log("NOTE glTF exporter has no option %s; dropped" % k)
                kw.pop(k)
    bpy.ops.export_scene.gltf(**kw)


def glb_check(path):
    with open(path, "rb") as f:
        data = f.read()
    clen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    need = ("POSITION", "NORMAL", "TEXCOORD_0", "TANGENT")
    problems, nprim = [], 0
    for me in js.get("meshes", []):
        for prim in me.get("primitives", []):
            nprim += 1
            miss = [k for k in need if k not in prim.get("attributes", {})]
            if miss:
                problems.append("%s lacks %s" % (me.get("name"), ",".join(miss)))
    for m in js.get("materials", []):
        if m.get("doubleSided"):
            problems.append("material %s is doubleSided" % m.get("name"))
    if len(data) >= 19_000_000:
        problems.append("GLB is %.2f MB" % (len(data) / 1e6))
    return {"primitives": nprim, "meshes": len(js.get("meshes", [])),
            "materials": [m.get("name") for m in js.get("materials", [])],
            "images": [i.get("name") for i in js.get("images", [])], "bytes": len(data)}, problems


def png_meta(path):
    with open(path, "rb") as f:
        head = f.read(33)
    w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
    return {"size": [w, h], "bitDepth": bd, "channels": {0: "gray", 2: "RGB", 4: "gray+alpha", 6: "RGBA"}.get(ct)}


def attachment_json(p, d):
    d = Vector(d).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((0, 1, 0))
    up = (up - d * up.dot(d)).normalized()
    return {"position": [round(v, 4) for v in to_rbx(p)], "look": [round(v, 4) for v in to_rbx(d)],
            "up": [round(v, 4) for v in to_rbx(up)]}


def export_all(assets, report, budgets, rise):
    os.makedirs(OUT, exist_ok=True)
    exp = new_collection("Export")
    manifest_assets, glbs, uploads, glb_only = [], [], [], []
    # free the clean names <Asset>_<Part> for the exported nodes and meshes (Blender would add .001 otherwise)
    for a in assets.values():
        for m in a.masters.values():
            md = META.pop(m.data.name)
            m.data.name = "_m_" + m.data.name
            META[m.data.name] = md
            m.name = "_m_" + m.name

    def rel(p):
        return os.path.relpath(p, OUT).replace("\\", "/")
    for room in ROOMS:
        ans = [an for an in ASSET_ORDER if ROOM_OF[an] == room]
        paint_obs = [m for an in ans for m in assets[an].masters.values() if m["cls"] == "paint"]
        face_uv, files, atlas = build_atlas(room, paint_obs)
        for kind, key in (("color", "color"), ("roughness", "rough"), ("metalness", "metal")):
            d = png_meta(files[key])
            uploads.append({"file": rel(files[key]), "kind": kind, "set": room, "size": d["size"],
                            "bitDepth": d["bitDepth"], "channels": d["channels"]})
        glb_only.append(rel(files["mr"]))
        mats = {"paint": export_material(room + "_Paint", "paint", files)}
        roots, x_cursor = [], 0.0
        for an in ans:
            a = assets[an]
            root = bpy.data.objects.new(an, None)
            exp.objects.link(root)
            parts_json = []
            lo = Vector((1e9, 1e9, 1e9))
            hi = Vector((-1e9, -1e9, -1e9))
            for pn, m in a.masters.items():
                me = m.data.copy()
                me.name = "%s_%s" % (an, pn)
                ob = bpy.data.objects.new(me.name, me)
                if ob.name != me.name or me.name != "%s_%s" % (an, pn):
                    raise RuntimeError("export name clash: %s / %s" % (ob.name, me.name))
                exp.objects.link(ob)
                ob.parent = root
                cls = m["cls"]
                keys = meta(m)["keys"]
                if cls == "paint":
                    lt = np.empty(len(me.polygons), dtype=np.int64)
                    me.polygons.foreach_get("loop_total", lt)
                    tg.set_uvs(me, np.repeat(np.array(face_uv[m.name]), lt, axis=0))
                    mat = mats["paint"]
                else:
                    tg.set_uvs(me, np.full((len(me.loops), 2), 0.5))
                    key = keys[0]
                    mk = room + {"neon": "_Neon_", "glass": "_Glass_", "collider": "_Collider_"}[cls] + key
                    if mk not in mats:
                        mats[mk] = export_material(mk, "collider" if cls == "collider" else cls, rgb=PAL[key][0])
                    mat = mats[mk]
                ca = me.color_attributes.get("paint")
                if ca:
                    me.color_attributes.remove(ca)
                for nm in ("rough", "metal"):
                    at = me.attributes.get(nm)
                    if at:
                        me.attributes.remove(at)
                bm = bmesh.new()
                bm.from_mesh(me)
                bmesh.ops.triangulate(bm, faces=bm.faces[:])
                bm.to_mesh(me)
                bm.free()
                me.materials.clear()
                me.materials.append(mat)
                try:
                    me.shade_flat()
                except AttributeError:
                    pass
                co = np.empty(len(me.vertices) * 3)
                me.vertices.foreach_get("co", co)
                co = co.reshape(-1, 3)
                lo = Vector(np.minimum(np.array(lo), co.min(0)))
                hi = Vector(np.maximum(np.array(hi), co.max(0)))
                role, rmat, collide, coll, cast, tags, notes = PART_META[(an, pn)]
                srgb = meta(m).get("srgb")
                if cls == "paint" and srgb is not None:
                    areas = np.empty(len(m.data.polygons))
                    m.data.polygons.foreach_get("area", areas)
                    mean = (srgb * areas[:, None]).sum(0) / max(areas.sum(), 1e-9)
                    rgb_mean = [int(round(v)) for v in mean]
                else:
                    rgb_mean = list(PAL[keys[0]][0])
                pj = {"name": me.name, "role": role, "robloxMaterial": rmat, "rgb": rgb_mean,
                      "collide": collide, "collision": coll, "castShadow": cast, "canQuery": collide,
                      "canTouch": collide, "tags": tags, "tris": len(me.polygons), "notes": notes,
                      "transparency": 0.0, "neon": cls == "neon", "doubleSided": False, "renderFidelity": "Automatic"}
                if cls == "paint":
                    pj["textureSet"] = room
                    pj["surfaceAppearance"] = {"colorMap": rel(files["color"]), "normalMap": None,
                                               "roughnessMap": rel(files["rough"]), "metalnessMap": rel(files["metal"]),
                                               "alphaMode": "Overlay", "color": [255, 255, 255]}
                    pj["paletteKeys"] = sorted(set(keys))
                elif cls == "glass":
                    pj.update({"transparency": 0.65, "reflectance": 0.2, "surfaceAppearance": None})
                elif cls == "collider":
                    pj.update({"transparency": 1.0, "surfaceAppearance": None})
                else:
                    pj["surfaceAppearance"] = None
                parts_json.append(pj)
            root.location = (x_cursor - lo.x, 0.0, 0.0)
            origin = [round(x_cursor - lo.x, 4), 0.0, 0.0]
            x_cursor += (hi.x - lo.x) + 8.0
            roots.append(root)
            extra = " NOTE: dips %.2f studs below its origin by design." % -lo.z if lo.z < -0.05 else ""
            rl, rh = to_rbx(lo), to_rbx(hi)
            manifest_assets.append({
                "name": an, "kind": a.kind, "room": room, "glb": room + ".glb", "instances": INSTANCES[an],
                "notes": a.notes + extra, "origin": origin,
                "boundsMin": [round(min(u, v), 3) for u, v in zip(rl, rh)],
                "boundsMax": [round(max(u, v), 3) for u, v in zip(rl, rh)],
                "size": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)],
                "tris": sum(p["tris"] for p in parts_json), "parts": parts_json,
                "attachments": {k: attachment_json(p, d) for k, (p, d) in a.atts.items()}})
        bpy.context.view_layer.update()
        for o in bpy.context.scene.objects:
            o.select_set(False)
        for r_ in roots:
            r_.select_set(True)
            for c in r_.children_recursive:
                c.select_set(True)
        glb = os.path.join(OUT, room + ".glb")
        gltf_export(glb)
        chk, problems = glb_check(glb)
        glbs.append({"file": room + ".glb", "assets": ans, "bytes": chk["bytes"],
                     "sizeMB": round(chk["bytes"] / 1048576.0, 3), "embeddedImages": chk["images"],
                     "materials": chk["materials"], "primitives": chk["primitives"], "problems": problems,
                     "palette": atlas})
        log("EXPORTED %s (%.2f MB), %d assets, %d primitives, problems: %s" % (
            glb, chk["bytes"] / 1048576.0, len(ans), chk["primitives"], problems or "none"))
    manifest = build_manifest(manifest_assets, glbs, uploads, glb_only, report, budgets, rise)
    mpath = os.path.join(OUT, CATEGORY + ".manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    repo_copy = os.path.join(ART, "manifests", CATEGORY + ".manifest.json")
    os.makedirs(os.path.dirname(repo_copy), exist_ok=True)
    shutil.copyfile(mpath, repo_copy)
    log("MANIFEST %s (+ copy %s)" % (mpath, repo_copy))
    return manifest


def build_manifest(assets_json, glbs, uploads, glb_only, report, budgets, rise):
    set_inst = []
    for k in range(8):
        for an in ("LaunchPoleHallSegment", "LaunchCaseGallery"):
            set_inst.append({"asset": an, "position": [0, 0, 0], "yawDeg": (-45.0 * k) % 360.0})
    set_inst.append({"asset": "LaunchPoleHallCrown", "position": [0, 0, 0], "yawDeg": 0.0})
    for i in range(N_BAYS):
        b = bay_bearing(i)
        Mb = M_facing_centre(b, CASE_R)
        yaw = (180.0 - b) % 360.0
        for an, local in (("LaunchCaseBay", Vector((0, 0, 0))), ("LaunchPole", Vector((0, POLE_Y, POLE_BASE))),
                          ("LaunchRiserDisc", Vector((0, DISC_Y, DISC_TOP)))):
            row = {"asset": an, "bay": i + 1, "position": [round(v, 4) for v in to_rbx(Mb @ local)], "yawDeg": yaw}
            if an == "LaunchCaseBay":
                row.update({"bearingDeg": b, "inUse24": i in IN_USE})
            set_inst.append(row)
    palette = []
    for k, (tone, sampled, rough, metal, kind, note) in PAL.items():
        row = {"key": k, "tone": list(tone), "hex": "#%02x%02x%02x" % tone, "luma": round(luma(tone), 1),
               "sampled": sampled, "roughness": rough, "metalness": metal, "kind": kind, "note": note}
        if k in report:
            tgt, before, after, f = report[k]
            row["meanLumaAfterAO"] = round(after, 1)
            row["normaliseFactor"] = round(f, 3)
        palette.append(row)
    return {
        "schema": "LS-Launch-2 (faceted style A, palette atlas; pass 2)",
        "category": CATEGORY,
        "generator": "art/blender/launch_rooms.py (seed %d)" % SEED,
        "glbs": glbs,
        "units": "1 Blender unit = 1 Roblox stud",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y); an asset's front = Roblox LookVector (-Z); bases on y = 0 "
                "(LaunchRiserDisc: origin = the standing surface)",
        "textureFolder": "textures/<room>",
        "uploadTextures": uploads,
        "glbOnlyTextures": glb_only,
        "palette": palette,
        "redCheck": red_check(),
        "budgets": budgets,
        "set": {
            "frame": "the pole hall: origin at its floor centre (y 0); bearings clockwise from north (Roblox -Z). "
                     "CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(yawDeg), 0).",
            "dimensions": {"hallDiameter": 2 * HALL_R, "wallTop": WALL_TOP, "crownDiameter": 2 * CROWN_R,
                           "crownY": 127.0, "caseRingRadius": CASE_R, "poleRingRadius": POLE_R,
                           "bankedRing": [120.4, HALL_R], "walkway": [98.6, CASE_R - CDp / 2 - 0.2],
                           "gantryY": GANTRY_Z, "ledRings": list(LED_RING_R),
                           "ledRowBearingsPerSegment": list(LED_ROW_BEARINGS), "ledBarLength": 2 * LED_HALF,
                           "wallBars": {"bearingsPerSegment": list(WALL_BAR_BEARINGS), "radius": WALL_BAR_R,
                                        "heights": [list(z) for z in WALL_BAR_Z]},
                           "redRoomNet": {"cell": NET_CELL, "bar": NET_BAR, "angleToHexDeg": NET_ANGLE,
                                          "sag": NET_SAG, "fixingsY": {"NetA": NET_A_FIX, "NetB": NET_B_FIX}}},
            "instances": set_inst,
            "redRoom": {"asset": "LaunchRedRoom", "placement": "client-local, one per player: under the player's "
                        "own bay, origin = bay origin + (0, -40, 0), same yaw (its roof top then sits 18 studs "
                        "under the hall floor). Nobody else ever sees it.",
                        "liftTravel": "the rose lift disc rises from y 0.15 up through the hex frame (y 21.6) into "
                                      "the dark above the roof; the cut to the case hides there"},
        },
        "rise": rise,
        "sequence": {
            "rule": "TwoArenas 2.3: the full cut if any contender in the round has not launched yet this session, "
                    "else the short cut; everyone in a round sees the same cut on the same clock",
            "full": [
                {"stage": "Fade to black on the training floor", "from": 0.0, "to": 0.4},
                {"stage": "1 The red room (loops while the arena streams in)", "from": 0.4, "to": 8.0,
                 "camera": "just above the hex frame's mouth (Blender (0, 2, 30), 7.5 studs over the frame), looking "
                           "75 deg down past the far half of the hexagon at the player's own stand-in on the lift disc "
                           "(Spawn) far below, in the oxblood hood; a slow zoom, fov 50 -> 42 over 6 s, then a 4 deg/s "
                           "drift if the wait runs on. At 6 s the player looks up into the tube.",
                 "cameraStart": {"position": to_rbx(Vector(RED_A_CAM[0])), "lookAt": to_rbx(Vector(RED_A_CAM[1])),
                                 "fovV": RED_A_CAM[2]}},
                {"stage": "2 Up the teal tube", "from": 8.0, "to": 11.0,
                 "camera": "rises ahead of the player through the hex frame into the dark above the roof (hidden "
                           "cut 1)"},
                {"stage": "3 The cases", "from": 11.0, "to": 15.0,
                 "camera": "at face height just outside the glass, beside the player, looking past the player (who "
                           "turns toward the row) along the tightly packed row of cases with a long lens (35 mm on "
                           "36 mm film, about 54 deg across; cameraStart, in the bay frame); then pulls back and arcs "
                           "40 deg round the hall, ending in front of the case at rise.cuts.full.keys[0]",
                 "cameraStart": {"positionBay": to_rbx(Vector(CASES_CAM[0])), "lookAtBay": to_rbx(Vector(CASES_CAM[1])),
                                 "fovV": round(math.degrees(2 * math.atan(18.0 / CASES_CAM[2] * 314.0 / 664.0)), 1)}},
                {"stage": "4 The rise", "from": 15.0, "to": 24.0, "keys": "rise.cuts.full",
                 "camera": "a whole turn anticlockwise from the front while climbing with the rider; from t 5.4 it "
                           "settles into the film's low-angle, whole-body frame (rise.endFrame, T1 @127.2 s), held "
                           "from t 6.8 while the rider is still in the open hall; the opening floods white from t 7.4"},
                {"stage": "5 White-out (the cut into the arena hides here)", "from": 24.0, "to": 25.0},
                {"stage": "6 The arrival", "from": 25.0, "to": 28.0,
                 "camera": "out of the white 14 studs above the plinth, looking down (T1 @129.2 s); drops behind the "
                           "head facing the horn, then into first person at 28.0. The rise now ends in front of the "
                           "rider, so reaching 'behind the head' is a further half turn, not pass 1's quarter."},
                {"stage": "On the plinth: 10 to 1", "from": 28.0, "to": 38.0},
            ],
            "short": [
                {"stage": "Fade", "from": 0.0, "to": 0.4},
                {"stage": "1 The red room, only as long as loading needs", "from": 0.4, "to": 3.0},
                {"stage": "4 The rise", "from": 3.0, "to": 8.0, "keys": "rise.cuts.short",
                 "camera": "a cut straight to the disc leaving the case, seen from behind and to the right (clear "
                           "of the gantry behind the cases); 155 deg anticlockwise to the same low-angle end frame by "
                           "t 3.4, held; floods white from t 4.2"},
                {"stage": "5 White-out", "from": 8.0, "to": 9.0},
                {"stage": "6 The arrival", "from": 9.0, "to": 12.0},
                {"stage": "On the plinth: 6 to 1", "from": 12.0, "to": 18.0},
            ],
        },
        "lighting": {
            "note": "pass 2 (TwoArenas 2.8) with the review's fixes: the hue rides on the light, not the paint. Cool "
                    "keys and a navy ambient in both halls and blue keys over the deck turn the shadows blue; the red "
                    "room keeps one cool white key down the tube and red light only in its two floor openings. Neon "
                    "parts light nothing (as in Roblox): every light below is a real Light. Light colours are 0-1 RGB "
                    "(Light.Color), gains are the Blender watts of the previews (relative only), ambients and exposures "
                    "as Lighting.Ambient and ExposureCompensation. The values were set on the Blender previews (paint x "
                    "ambient, AgX, the bloom and atmosphere stand-ins below) and measured with tools/art/colour_band.py "
                    "(tools/art/specs/launch.json); confirm them in Studio (ArtStyle rule 10) before shipping.",
            "colours": {"coolWhite": list(COOL), "coolKey": list(COOL_KEY), "deckKey": list(DECK_KEY),
                        "lampLight": list(LAMP_LIGHT), "openingGlow": list(RED_GLOW), "grateGlow": list(GRATE_GLOW),
                        "caseStageBars": list(CASE_STAGE_COL), "caseStageGantry": list(CASE_GANTRY_COL),
                        "poleHallBars": list(VIEW_HALL_COL["wide"]), "riseBars": list(VIEW_HALL_COL["rise_end"])},
            "previewGains": dict(LIGHT_GAIN),
            "LaunchRedRoom": {"ambient": list(AMBIENT["red"]), "exposure": VIEW_EXPOSURE["red_a"],
                              "lights": "SpotLight at KeyLight (coolWhite, angle %d, aimed down the tube onto the "
                                        "lift disc only); SpotLights at DeckKey_1-4 (deckKey, angle %d, leaning in "
                                        "toward the grate lanes: they make the neutral steel deck read blue); a "
                                        "coolKey SpotLight (angle 26) at WalkwaySpot, over the walkway; a dim navy "
                                        "SurfaceLight (Face Bottom, grateGlow) under each grate lane's mesh at "
                                        "GrateGlow_1-4, so the voids read navy-black; a red SurfaceLight (Face Top) "
                                        "low in each floor opening at OpeningGlow_1-2, the only red light; white "
                                        "SpotLights (lampLight, angle 50, tipped 10 deg down) at Lamp_n, the way "
                                        "each lamp faces" % (int(RED_KEY_DEG), int(DECK_KEY_DEG))},
            "LaunchCaseHall": {"ambient": list(AMBIENT["case"]), "exposure": VIEW_EXPOSURE["cases"],
                               "lights": "a SurfaceLight (Face Bottom, Angle 50, coolWhite) on each case top-light, "
                                         "aimed at the disc; SurfaceLights (Face Bottom, caseStageGantry) on the "
                                         "gantry strips; a small SurfaceLight on each unit panel. While the cases "
                                         "stage runs, the pole hall's hub spots are off and its bars take "
                                         "caseStageBars at caseStageDim of their gains",
                               "caseStageDim": {"HubSpot": CASE_STAGE_DIM["Hall_HubSpot"],
                                                "wallBars": CASE_STAGE_DIM["Wall_"],
                                                "ceilingRingBars": CASE_STAGE_DIM["LED_"]}},
            "LaunchPoleHall": {"ambient": list(AMBIENT["hall"]), "exposure": VIEW_EXPOSURE["wide"],
                               "bloom": {"threshold": 1.4, "previewStandIn": list(VIEW_GLARE["wide"])},
                               "atmosphere": {"note": "a thin navy haze (Lighting.Atmosphere in this profile): the "
                                                      "preview blends toward the colour with distance",
                                              "start": VIEW_FOG["wide"][0], "depth": VIEW_FOG["wide"][1],
                                              "amount": VIEW_FOG["wide"][2], "color": list(VIEW_FOG["wide"][3])},
                               "lights": "SpotLights (angle 34, poleHallBars) at the 12 HubSpot_n, which hang in two "
                                         "tiers under the hub; a SurfaceLight (Face Bottom) on every ceiling-ring LED "
                                         "bar and one (Face Front, toward the hall centre) on every wall bar; no light "
                                         "on the poles; a SpotLight that rides 7 studs in front of and 10 above each "
                                         "rider (the rider key, coolWhite). Phones: only the own rider's key and the 4 "
                                         "nearest; Low graphics drops the wall bars' lights"},
            "LaunchPoleHallRise": {"ambient": list(AMBIENT["rise"]), "exposure": VIEW_EXPOSURE["rise_end"],
                                   "note": "the rise's own profile: as the camera settles into the low-angle end "
                                           "frame the pole hall's ambient blends to this greyer navy, the bars take "
                                           "riseBars and the exposure eases (rise.cuts.*.keys[].riseProfile and "
                                           ".exposure), so the lit rider stands out against a hall that falls away "
                                           "(T1 @127.2 s)"},
        },
        "import": [
            "Import each GLB (3D Importer). Each asset root arrives as a Model of MeshParts named <Asset>_<Part>.",
            "Re-centre each asset: Model.WorldPivot = CFrame.new(origin), then PivotTo(CFrame.new()).",
            "Per part from the manifest: Material = robloxMaterial, Color = rgb, CanCollide = collide, "
            "CollisionFidelity = collision, CastShadow, CanQuery, CanTouch, Transparency; Anchored = true.",
            "Paint parts: one SurfaceAppearance per part (ColorMap, RoughnessMap, MetalnessMap from the upload "
            "files of its textureSet; no NormalMap). Neon parts: Material Neon, no SurfaceAppearance. Glass: "
            "Material Glass, Transparency 0.65, Reflectance 0.2. Collider: Transparency 1.",
            "Build the set from set.instances in a folder far from the arena; it is client-side (clone it on the "
            "client for the launch). The red room is cloned per player under their own bay.",
            "Attachments: create under the asset's main part with WorldCFrame = pivot * CFrame.lookAt(position, "
            "position + look, up).",
            "The palette textures are nearest-colour cells (8 px); the cells are sorted by colour so mips stay clean.",
        ],
        "styleRules": [
            "Style A: chunky volumes at true scale, flat facets, built members as chamfered prisms; nothing under "
            "0.25 stud except bolts and trim.",
            "Colour: the brief's semi-real tones (UpcomingFilm_Brief section 2.8), +-6% per volume, +-3% per "
            "facet, warm tops and cool undersides, AO >= 0.5; each surface's mean after AO is normalised to the "
            "tone. The reds sit at their frame sample's saturation (within 0.05; palette.redCheck); "
            "saturated colour only on the light sources.",
            "Darkness comes from the lighting, never the paint: no painted value below luma 40 (grates); built "
            "surfaces 55-215.",
        ],
        "assets": assets_json,
        "warnings": budgets["warnings"],
    }


# =============================================================================================== main
def main():
    log("launch_rooms.py stages=%s quality=%s only=%s" % (sorted(STAGES), QUALITY, sorted(ONLY)))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(SEED)
    np.random.seed(SEED)
    assets = build_all()
    inst = assemble(assets)
    budgets = check_budgets(assets)
    report = paint_and_ao(assets, inst)
    for k, (tgt, before, after, f) in sorted(report.items()):
        log("TONE %-11s target luma %5.1f  painted*AO %5.1f -> %5.1f (x%.2f)" % (k, tgt, before, after, f))
    for k, v in red_check().items():
        log("RED  %-11s sampled S %.2f, tone S %.2f (%+.2f) %s" % (k, v["sampledSat"], v["toneSat"], v["diff"],
                                                                  "PASS" if v["pass"] else "FAIL"))
    assign_preview_materials(assets)
    rise = rise_plan(assets, inst)
    if "preview" in STAGES:
        lights = build_lights(assets)
        Previewer(assets, inst, lights, rise).run()
    if "export" in STAGES:
        export_all(assets, report, budgets, rise)
    log("DONE")


if __name__ == "__main__":
    main()
