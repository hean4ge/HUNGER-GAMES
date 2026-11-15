"""
launch_rooms.py - HUNGER GAMES (BETA) / LAST STANDING: the launch sequence, ONE set used before BOTH maps.
Faceted style A ("realistic blockish", docs/design/ArtStyle.md) with semi-realistic tones
(docs/design/UpcomingFilm_Brief.md section 2). Seeded and headless; every asset is modelled here, nothing is
downloaded, traced or generated. The owner's frames are study-only references: they are read for the compare
sheets and never copied into any exported file.

The three rooms, in the owner's order ("the red room with the metal on top is just the transition room ... it
loads up to the room like the images i sent you"):
  1. LaunchRedRoom      the transition room (client-local, loops while the map loads): oxblood walls, a roof of
                        red panels under a dark square net, a teal hexagonal frame of square tube over the lift,
                        a blue-grey steel deck with black grates over glowing red mesh, white stripes, red rails,
                        red lamp housings, an upper walkway with concrete stairs, a steel door and an intercom.
  2. the glass-case hall, the ground ring of the pole hall:
     LaunchCaseBay      one bay (x48 at r 110): a tall glass case on oxblood posts with a dark-red disc on its
                        pedestal, a front top-light and the maroon wall unit beside it.
     LaunchCaseGallery  45-degree segment (x8): the curved walkway, its pale kerb, the light gantry with rows of
                        white strip lights, columns and the navy back screen.
     LaunchRiserDisc    the moving disc (x48): dark-red top, rim, collar on the pole.
  3. the pole hall (the stage of the one-shot rise):
     LaunchPoleHallSegment  45-degree segment (x8): floor plates, the banked ring of oxblood and pale wedges,
                        wall with columns and ledges, the truss dome with purlins, rings of LED bars, the
                        apertures over the poles.
     LaunchPoleHallCrown    the spoked ceiling ring (48 spokes), the hub and its 12 spotlights.
     LaunchPole         1-stud 12-sided steel pole with copper bands and segmented edge-lit strips (x48).

Run (headless, from the repo root; art/README.md section 1):
  blender --background --factory-startup --python art/blender/launch_rooms.py -- <out_dir> <preview_dir> [stages]
  out_dir     default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Launch
  preview_dir default art/previews/Launch
  stages      comma list (default build,preview,export):
                build    geometry, paint, AO (always runs)
                preview  compare sheets (render beside the owner's frame), overviews, the rise path sheet,
                         colour checks -> <preview_dir>
                export   LaunchRedRoom.glb, LaunchCaseHall.glb, LaunchPoleHall.glb, textures,
                         Launch.manifest.json (+ copy in art/manifests)
                only=<view,...>  render just these preview views
  env LAUNCH_QUALITY = draft | final (samples; default final)
  env LAUNCH_REF     = folder of the owner's frames (default %USERPROFILE%/OneDrive/Documents/LastStanding/
                       References/owner). Only the compare sheets read it.

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
ART = os.path.normpath(os.path.join(HERE, ".."))
CATEGORY = "Launch"
TEX = os.path.join(OUT, "textures")
GLB_ONLY = os.path.join(TEX, "glb_only")

# =============================================================================================== palette
# key: tone (the semi-real base, sRGB 0-255, = the area mean after AO), sampled (frame value, evidence only),
#      roughness, metalness, kind (paint | neon | glass), note.  Brief section 2.8 unless marked "ours".
PAL = {
    # 1 red room
    "oxblood":     ((112, 46, 46), "#281616", 0.85, 0.0, "paint", "walls, roof panels (brief 2.8)"),
    "oxblood_dk":  ((100, 46, 48), "#241316", 0.85, 0.0, "paint", "wall backing, lift apron (ours, from the floor sample)"),
    "net":         ((62, 82, 86), "#1d4250", 0.6, 0.0, "paint", "net and grating, dark teal-grey steel"),
    "hex":         ((66, 114, 122), "#205766", 0.6, 0.0, "paint", "hexagonal frame of square tube"),
    "bolt":        ((84, 96, 100), None, 0.55, 0.0, "paint", "gusset plates and bolts (ours)"),
    "rose":        ((150, 96, 104), "#5c4d5a", 0.7, 0.0, "paint", "the lift disc, dusty rose"),
    "deck":        ((120, 130, 136), "#205169", 0.6, 0.0, "paint", "steel deck plate"),
    "grate":       ((44, 46, 48), "#031a2a", 0.7, 0.0, "paint", "floor grates (deliberate black, luma >= 40)"),
    "redmesh":     ((120, 40, 42), "#1c1015", 0.8, 0.0, "paint", "red mesh under the grates, lit from below"),
    "rail":        ((156, 48, 50), "#592a38", 0.55, 0.0, "paint", "red rails, painted steel tube"),
    "stripe":      ((206, 206, 200), "#697c87", 0.8, 0.0, "paint", "white floor stripes"),
    "lamp":        ((150, 46, 48), "#582d3b", 0.6, 0.0, "paint", "lamp housings"),
    "concrete":    ((126, 126, 122), "#2a3945", 0.9, 0.0, "paint", "concrete base course and steps"),
    "door":        ((88, 94, 100), None, 0.6, 0.0, "paint", "steel door and intercom (ours)"),
    # 2 glass-case hall
    "post":        ((110, 54, 60), "#4b353c", 0.7, 0.0, "paint", "case posts"),
    "case_disc":   ((126, 50, 54), "#452e30", 0.7, 0.0, "paint", "case and rider discs"),
    "disc_rim":    ((110, 44, 48), "#0d141b", 0.7, 0.0, "paint", "rider's disc rim"),
    "unit":        ((116, 52, 58), None, 0.75, 0.0, "paint", "maroon wall unit (ours, between posts and discs)"),
    "plinth":      ((76, 80, 86), None, 0.7, 0.0, "paint", "case plinth and pedestal, dark steel (ours)"),
    "walkway":     ((74, 80, 88), None, 0.7, 0.0, "paint", "gallery walkway deck (ours, dark blue-grey steel)"),
    "shell_case":  ((54, 64, 78), "#123a4f", 0.85, 0.0, "paint", "glass-hall shell: screens, gantry"),
    # 3 pole hall
    "shell":       ((58, 66, 78), "#143040", 0.85, 0.0, "paint", "pole-hall shell: wall, roof deck"),
    "truss":       ((96, 104, 114), "#0d2132", 0.6, 0.0, "paint", "spoked ring and truss"),
    "floor":       ((70, 76, 84), None, 0.7, 0.0, "paint", "hall floor plates (ours, darker than the walkway)"),
    "wedge_red":   ((124, 54, 54), "#5d403e", 0.85, 0.0, "paint", "floor wedges, oxblood"),
    "wedge_pale":  ((176, 178, 176), "#8c9498", 0.85, 0.0, "paint", "floor wedges, pale; also the kerb"),
    "steel":       ((164, 166, 168), None, 0.4, 1.0, "paint", "poles, bare steel (metal)"),
    "copper":      ((176, 112, 70), "#c8833c", 0.4, 1.0, "paint", "copper bands (metal)"),
    "housing":     ((64, 68, 74), None, 0.7, 0.0, "paint", "LED bar housings, spot cans (ours)"),
    # emitters and glass (flat, never jittered)
    "light":       ((236, 240, 244), "#dfe6ed", 0.5, 0.0, "neon", "light bars and panels (the only Neon parts)"),
    "lens":        ((245, 240, 232), None, 0.5, 0.0, "neon", "lamp lenses and spot lenses"),
    "strip":       ((236, 240, 244), "#e2e6e9", 0.5, 0.0, "neon", "the poles' segmented edge-lit strips (dimmer)"),
    "spot":        ((240, 242, 246), None, 0.5, 0.0, "neon", "hub spotlight lenses (the brightest emitters)"),
    "glass":       ((196, 210, 214), "#062a3d", 0.1, 0.0, "glass", "case glass, Transparency 0.65"),
}
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
NET_PITCH, NET_BAR = 1.45, 0.25                # cells 1.2 + bars 0.25
DISC_R = 3.6                                   # 7.2 across: the arena's plate tube
ROOF_Z = (20.4, 20.9)                          # red roof panels between the two nets
RED_PITS = []                                  # (width, depth) of each grate pit, in GrateGlow order


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


def build_red_room(rng):
    P = {k: MB(k) for k in ("Shell", "Roof", "NetA", "NetB", "HexFrame", "Deck", "Grates", "Rails", "Lamps",
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
    # panel seams: shallow dark battens on both faces (the roof reads as cassettes behind the net)
    for i in range(-3, 4):
        x = i * 3.75
        hy_ = hex_half_y(x, HX_OUT)
        spans = [(-hd, -hy_), (hy_, hd)] if hy_ else [(-hd, hd)]
        for zf in ((ROOF_Z[0] - 0.12, ROOF_Z[0]), (ROOF_Z[1], ROOF_Z[1] + 0.12)):
            for y0, y1 in spans:
                if y1 - y0 > 0.5:
                    roof.add(g_box(x - 0.12, y0, zf[0], x + 0.12, y1, zf[1]), "oxblood_dk")
    for j in range(-3, 4):
        y = j * 3.4
        hx_ = hex_half_x(y, HX_OUT)
        for zf in ((ROOF_Z[0] - 0.12, ROOF_Z[0]), (ROOF_Z[1], ROOF_Z[1] + 0.12)):
            for x0, x1 in (((-hw, -hx_), (hx_, hw)) if hx_ else ((-hw, hw),)):
                if x1 - x0 > 0.5:
                    roof.add(g_box(x0, y - 0.12, zf[0], x1, y + 0.12, zf[1]), "oxblood_dk")

    def net_layer(mb, z_x, z_y, cut):
        b = NET_BAR
        nx = int((RD - 0.8) / NET_PITCH) + 1
        for j in range(nx):
            y = -((nx - 1) * NET_PITCH) / 2 + j * NET_PITCH
            hx_ = hex_half_x(y, cut)
            spans = [(-hw, -hx_), (hx_, hw)] if hx_ else [(-hw, hw)]
            for x0, x1 in spans:
                mb.add(g_box(x0, y - b / 2, z_x, x1, y + b / 2, z_x + b), "net")
        ny = int((RW - 0.8) / NET_PITCH) + 1
        for i in range(ny):
            x = -((ny - 1) * NET_PITCH) / 2 + i * NET_PITCH
            hy_ = hex_half_y(x, cut)
            spans = [(-hd, -hy_), (hy_, hd)] if hy_ else [(-hd, hd)]
            for y0, y1 in spans:
                mb.add(g_box(x - b / 2, y0, z_y, x + b / 2, y1, z_y + b), "net")
    # under the roof: the room's net ceiling, cut clear of the opening (seen from above through the frame)
    net_layer(P["NetA"], 19.75, 19.5, HX_OUT + 0.05)
    # on top of the roof (frame A): it runs in under the frame
    net_layer(P["NetB"], ROOF_Z[1] + 0.12, ROOF_Z[1] + 0.37, HX_OUT - 0.2)

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
    # floor pits lined with red mesh (a red panel under a dark square net, lit from inside). The two lanes ahead of
    # and behind the lift carry black square-mesh grates flush with the deck (frame B, ahead of the player); the two
    # pits beside the lift are open red mesh under a dark rim (frame B, either side of the player). The Deck part's
    # Box collider spans the pits, so all of them are walkable.
    gi = 0
    pits = [(-7.6, -9.6, -0.25, -5.0, True), (0.25, -9.6, 7.6, -5.0, True), (-7.6, 5.0, -0.25, 9.6, True),
            (0.25, 5.0, 7.6, 9.6, True), (-10.0, -4.2, -7.5, 4.2, False), (7.5, -4.2, 10.0, 4.2, False)]
    RED_PITS[:] = [(x1 - x0, y1 - y0) for x0, y0, x1, y1, _ in pits]
    for x0, y0, x1, y1, black_top in pits:
        gi += 1
        v = grates.vol()
        grates.add(g_box(x0, y0, -1.3, x1, y1, -1.1), "redmesh", None, v)          # red mesh panel
        nxg = int((x1 - x0) / 1.2)
        for k in range(1, nxg + 1):                                                  # its dark net
            xx = x0 + k * (x1 - x0) / (nxg + 1)
            grates.add(g_box(xx - 0.13, y0, -1.1, xx + 0.13, y1, -0.98), "grate", None, v)
        nyg = int((y1 - y0) / 1.2)
        for k in range(1, nyg + 1):
            yy = y0 + k * (y1 - y0) / (nyg + 1)
            grates.add(g_box(x0, yy - 0.13, -1.1, x1, yy + 0.13, -0.98), "grate", None, v)
        for wx0, wy0, wx1, wy1 in ((x0, y0, x1, y0 + 0.12), (x0, y1 - 0.12, x1, y1),
                                   (x0, y0, x0 + 0.12, y1), (x1 - 0.12, y0, x1, y1)):
            grates.add(g_box(wx0, wy0, -1.3, wx1, wy1, -0.4), "grate", None, v)       # pit walls
        vb = grates.vol()
        rim = 0.35
        grates.add(g_box(x0, y0, -0.35, x1, y0 + rim, 0.0), "grate", None, vb)          # rim
        grates.add(g_box(x0, y1 - rim, -0.35, x1, y1, 0.0), "grate", None, vb)
        grates.add(g_box(x0, y0 + rim, -0.35, x0 + rim, y1 - rim, 0.0), "grate", None, vb)
        grates.add(g_box(x1 - rim, y0 + rim, -0.35, x1, y1 - rim, 0.0), "grate", None, vb)
        if black_top:                                                                 # square mesh 0.75
            nb = int(round((y1 - y0 - 2 * rim) / 0.75)) - 1
            for k in range(1, nb + 1):
                yy = y0 + rim + k * (y1 - y0 - 2 * rim) / (nb + 1)
                grates.add(g_box(x0 + rim, yy - 0.13, -0.3, x1 - rim, yy + 0.13, -0.02), "grate", None, vb)
            nc = int(round((x1 - x0 - 2 * rim) / 0.75)) - 1
            for k in range(1, nc + 1):
                xx = x0 + rim + k * (x1 - x0 - 2 * rim) / (nc + 1)
                grates.add(g_box(xx - 0.13, y0 + rim, -0.32, xx + 0.13, y1 - rim, -0.04), "grate", None, vb)
        # the glow: a red light inside the pit, aimed down at the mesh so the mesh reads lit from within
        atts["GrateGlow_%d" % gi] = (Vector(((x0 + x1) / 2, (y0 + y1) / 2, -0.55)), Vector((0, 0, -1)))

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
    atts["GuardFloor"] = (Vector((5.2, 7.3, 0.0)), Vector((0, -1, 0)))
    atts["WalkwaySpot"] = (Vector((0.0, 1.0, 19.2)), (Vector((0.0, 10.4, WZ + 3.5)) - Vector((0.0, 1.0, 19.2))).normalized())

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
    M = M_place((ux, uy, 0.0), -BAY_STEP / 2)
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
STRIP_FROM = 38.0                            # the strips light the upper two thirds of each pole (T1 @124.7 s)
# LED rings (r, count, bearing offset): radial bars, none on a 7.5-degree seam (where the trusses run) or a pole
LED_RINGS = ((104.0, 32, 5.625), (128.0, 48, 3.75), (152.0, 64, 2.8125), (174.0, 80, 2.25))


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
    # LED bars: radial, in rings outside the crown, each under a dark housing (the film shows none inside the wheel)
    for r, count, off in LED_RINGS:
        step = 360.0 / count
        for k in range(count):
            b = off + k * step
            if b >= seg:
                break
            L = min(4.0 if r < 110 else 3.4 + r / 60.0, 179.0 - r)
            ra, rb = r - L, r + L
            za, zb = dome_bot(ra) - 1.6, dome_bot(rb) - 1.6
            pa, pb = bearing(b, ra, za), bearing(b, rb, zb)
            tr.add(g_beam(pa + Vector((0, 0, 0.35)), pb + Vector((0, 0, 0.35)), sec_rect(0.9, 0.45)), "housing")
            led.add(g_beam(pa, pb, sec_rect(0.5, 0.3)), "light")
            # hanger to the roof
            tr.add(g_beam(bearing(b, r, dome_bot(r) - 1.2), bearing(b, r, dome_top(r) + 0.9), sec_rect(0.25, 0.25)), "housing")
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
    atts = {}
    for k in range(12):
        b = k * 30.0 + 15.0
        base = bearing(b, 12.5, zc - 7.2)
        tip = bearing(b, 13.5, zc - 10.4)
        v = hub.vol()
        hub.add(g_beam(base, base + Vector((0, 0, -1.4)), sec_rect(0.45, 0.45)), "housing", None, v)
        hub.add(g_beam(base + Vector((0, 0, -1.2)), tip, p_ngon(1.15, 10)), "housing", None, v)
        d = (tip - (base + Vector((0, 0, -1.2)))).normalized()
        spots.add(g_beam(tip, tip + d * 0.12, p_ngon(0.95, 10)), "spot")
        atts["HubSpot_%d" % (k + 1)] = (tip + d * 0.2, Vector((0.08 * math.sin(math.radians(b)),
                                                                0.08 * math.cos(math.radians(b)), -1)).normalized())
    return P, atts


def build_pole():
    P = {"Steel": MB("Steel"), "Copper": MB("Copper"), "Strip": MB("Strip", "neon")}
    st, cu, sp = P["Steel"], P["Copper"], P["Strip"]
    H = POLE_TOP - POLE_BASE
    st.add(g_prism(p_ngon(0.5, 12, rot=0), 0.0, H), "steel")
    for z in [1.6] + [16.0 + 15.0 * k for k in range(8)]:
        if z + 0.6 < H:
            cu.add(g_prism(p_ngon(0.62, 12, rot=0), z, z + 0.6), "copper")
    # two segmented edge-lit strips on the front-left / front-right facets (toward the hall centre); from far they
    # read as the dotted lines converging on the hub, from close as vertical light tubes (T1 @124.7 / @127.2 s)
    for ang in (60.0, 120.0):
        a = math.radians(ang)
        c, s = math.cos(a), math.sin(a)
        z = STRIP_FROM
        while z + 4.2 < H - 1.0:
            p0 = Vector((0.52 * c, 0.52 * s, z))
            p1 = Vector((0.52 * c, 0.52 * s, z + 4.2))
            sp.add(g_beam(p0, p1, sec_rect(0.26, 0.2), up=(c, s, 0)), "strip")
            z += 6.3
    atts = {"Base": (Vector((0, 0, 0)), Vector((0, 0, 1))), "Top": (Vector((0, 0, H)), Vector((0, 0, 1)))}
    return P, atts


# =============================================================================================== preview figures
def figure_parts(kind="tribute", district=None):
    """A blocky R15-proportioned figure (5.5 tall) for previews only. Front = +Y."""
    mb = MB("Figure")
    if kind == "tribute":
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.86, 0.86, 0.1), 0.0, 0.35), "shoe")
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.84, 0.84, 0.1), 0.35, 2.3), "trousers")
        mb.add(g_prism(p_crect(0, 0, 1.9, 0.95, 0.12), 2.3, 4.3), district or "trousers")
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 1.38, 0, 0.8, 0.8, 0.1), 2.35, 4.25), "cape")
        mb.add(g_prism(p_crect(0, 0, 1.15, 1.1, 0.18), 4.32, 5.42), "skin")
        mb.add(g_prism(p_crect(0, -0.05, 1.3, 1.25, 0.3), 5.1, 5.75), "hair")
        mb.add(g_prism(p_crect(0, -0.55, 1.3, 0.3, 0.1), 4.4, 5.6), "hair")
        # cape: faceted poncho, open front edges trimmed dark, hood behind the head
        cape = [(r, z) for r, z in ((1.12, 4.42), (1.7, 3.3), (2.05, 1.7))]
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
    elif kind == "escort":   # an escort in a dark patterned suit, looking up (frame A)
        for sx in (-1, 1):
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.86, 0.86, 0.1), 0.0, 0.35), "shoe")
            mb.add(g_prism(p_crect(sx * 0.47, 0, 0.84, 0.84, 0.1), 0.35, 2.3), "trim")
        mb.add(g_prism(p_crect(0, 0, 1.9, 0.95, 0.12), 2.3, 4.3), "trim")
        mb.add(g_prism(p_crect(0, 0.2, 1.2, 0.6, 0.1), 2.6, 4.1), "yellow")
        for sx in (-1, 1):
            mb.add(g_beam((sx * 1.3, 0.0, 4.15), (sx * 2.35, 0.55, 3.0), sec_rect(0.75, 0.75), up=(0, 1, 0)), "trim")
        mb.add(g_prism(p_crect(0, 0, 1.15, 1.1, 0.18), 4.32, 5.42), "skin")
        mb.add(g_prism(p_crect(0, -0.05, 1.45, 1.35, 0.35), 5.0, 5.95), "trousers")
    else:   # guard in white armour with a dark visor and a rifle
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
    ("LaunchRedRoom", "NetA"): ("Paint", "Metal", False, "Box", True, [], "the net seen from the room"),
    ("LaunchRedRoom", "NetB"): ("Paint", "Metal", False, "Box", True, [], "the net on top of the roof (establishing shot)"),
    ("LaunchRedRoom", "HexFrame"): ("Paint", "Metal", False, "Box", True, [], "teal hexagonal frame, gussets and bolts"),
    ("LaunchRedRoom", "Deck"): ("Paint", "DiamondPlate", True, "Box", True, ["Floor"], "deck plates, stripes, lift apron"),
    ("LaunchRedRoom", "Grates"): ("Paint", "Metal", False, "Box", True, [], "grates and the red mesh pits (walk on the Deck collider)"),
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
    ("LaunchPoleHallSegment", "Truss"): ("Paint", "Metal", False, "Box", True, [], "trusses, purlins, columns, LED housings"),
    ("LaunchPoleHallSegment", "LED"): ("Light", "Neon", False, "Box", False, [], "LED bars (Neon)"),
    ("LaunchPoleHallCrown", "Ring"): ("Paint", "Metal", False, "Box", True, [], "spoked ring"),
    ("LaunchPoleHallCrown", "Hub"): ("Paint", "Metal", False, "Box", True, [], "hub and spot cans"),
    ("LaunchPoleHallCrown", "Spots"): ("Light", "Neon", False, "Box", False, [], "spot lenses (Neon)"),
    ("LaunchPole", "Steel"): ("Paint", "Metal", False, "Box", True, [], "12-sided steel pole"),
    ("LaunchPole", "Copper"): ("Paint", "Metal", False, "Box", True, [], "copper bands"),
    ("LaunchPole", "Strip"): ("Light", "Neon", False, "Box", False, [], "segmented edge-lit strips"),
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
AMBIENT = {"red": (30, 18, 20), "case": (24, 34, 48), "hall": (12, 16, 24)}
_mats = {}


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
    amb = nt.nodes.new("ShaderNodeRGB")
    amb.name = "Ambient"
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(at.outputs["Color"], mul.inputs[6])
    nt.links.new(amb.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
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
    tr.inputs["Color"].default_value = (0.86, 0.9, 0.92, 1.0)
    gl = nt.nodes.new("ShaderNodeBsdfPrincipled")
    gl.inputs["Base Color"].default_value = lin(PAL["glass"][0]) + (1.0,)
    gl.inputs["Roughness"].default_value = 0.08
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = 0.08
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
    _mats[key] = m
    return m


NEON_STRENGTH = {"light": 9.0, "lens": 14.0, "strip": 3.5, "spot": 45.0}


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
    m = _mats.get("M_Paint")
    if m:
        m.node_tree.nodes["Ambient"].outputs[0].default_value = lin(AMBIENT[room]) + (1.0,)


def figure_object(kind, name, M, coll, district=None):
    mb = figure_parts(kind, district)
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


def compare_sheet(render_path, frame_path, out_path, title, ref_label):
    ren = load_rgb(render_path)
    fr = load_rgb(frame_path)
    H = ren.shape[0]
    fr = resize(fr, H, int(round(fr.shape[1] * H / fr.shape[0])))
    gap, strip = 12, 34
    W = ren.shape[1] + gap + fr.shape[1]
    sheet = np.full((H + strip, W, 3), 0.07)
    sheet[:H, :ren.shape[1]] = ren
    sheet[:H, ren.shape[1] + gap:] = fr
    draw_text(sheet, 10, H + 10, "OURS: " + title, 2)
    draw_text(sheet, ren.shape[1] + gap + 10, H + 10, "FILM, STUDY ONLY: " + ref_label, 2)
    save_rgb(out_path, sheet)
    return colour_stats(ren), colour_stats(fr)


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
        vs.view_transform = "AgX"
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
COOL = (0.86, 0.92, 1.0)
WARM_WHITE = (1.0, 0.95, 0.88)
LIGHT_GAIN = {"red_key": 24000.0, "grate": 520.0, "lamp": 70.0, "red_top": 1200.0, "walkway": 5000.0,
              "hub": 160000.0, "led": 450.0, "case": 200.0, "unit": 14.0, "gantry": 30.0, "rider": 9000.0}


def led_bars():
    """World endpoints of every LED bar in the hall (all 8 segments)."""
    out = []
    for seg in range(8):
        for r, count, off in LED_RINGS:
            step = 360.0 / count
            for k in range(count):
                b = off + k * step
                if b >= 45.0:
                    break
                bb = b + 45.0 * seg
                Lh = min(4.0 if r < 110 else 3.4 + r / 60.0, 179.0 - r)
                out.append((bearing(bb, r - Lh, dome_bot(r - Lh) - 1.85), bearing(bb, r + Lh, dome_bot(r + Lh) - 1.85)))
    return out


def build_lights(assets):
    red_atts = assets["LaunchRedRoom"].atts
    G = LIGHT_GAIN
    L = {}
    c = L["red"] = new_collection("L_Red")
    # the key falls through the hex opening only (cone 50: it clears the frame), the walkway spot lights the
    # escort or guard who looks up from the walkway (frame A)
    add_light(c, "Red_Key", "SPOT", red_atts["KeyLight"][0], (0, 0, -1), G["red_key"], COOL, spot_deg=50, blend=0.45,
              radius=2.0)
    add_light(c, "Red_Walkway", "SPOT", red_atts["WalkwaySpot"][0], red_atts["WalkwaySpot"][1], G["walkway"],
              (0.95, 0.96, 1.0), spot_deg=34, blend=0.5, radius=0.6)
    for k, (p, d) in red_atts.items():
        if k.startswith("GrateGlow"):
            w, dp = RED_PITS[int(k.split("_")[1]) - 1]
            add_light(c, "Red_" + k, "AREA", p, d, G["grate"] * (w * dp) / 30.0, (1.0, 0.42, 0.36),
                      size=(w - 0.5, dp - 0.5))
        elif k.startswith("Lamp_"):
            add_light(c, "Red_" + k, "POINT", p, None, G["lamp"], WARM_WHITE, radius=0.35)
    c = L["redtop"] = new_collection("L_RedTop")
    add_light(c, "RedTop_Fill", "AREA", (0, -4, 34), (0, 0.15, -1), G["red_top"], (1.0, 0.93, 0.9), size=(30, 24))
    # the hall: hub spots, a SurfaceLight on every LED bar, case lights, gantry rows, unit panels
    c = L["hall"] = new_collection("L_Hall")
    for k, (p, d) in assets["LaunchPoleHallCrown"].atts.items():
        add_light(c, "Hall_" + k, "SPOT", p, d, G["hub"], COOL, spot_deg=34, blend=0.5, radius=0.9)
    for n, (pa, pb) in enumerate(led_bars()):
        add_light(c, "LED_%03d" % n, "AREA", (pa + pb) / 2, (0, 0, -1), G["led"], COOL, size=((pb - pa).length, 0.5),
                  xaxis=pb - pa)
    c = L["case"] = new_collection("L_Case")
    for i in range(N_BAYS):
        Mb = M_facing_centre(bay_bearing(i), CASE_R)
        R3 = Mb.to_3x3()
        p, d = assets["LaunchCaseBay"].atts["CaseLight"]
        add_light(c, "Case_%02d" % i, "AREA", Mb @ p, R3 @ d, G["case"], (0.95, 0.97, 1.0), size=(2.3, 0.4),
                  xaxis=R3 @ Vector((1, 0, 0)))
        p, d = assets["LaunchCaseBay"].atts["UnitLight"]
        add_light(c, "Unit_%02d" % i, "AREA", Mb @ p, R3 @ d, G["unit"], (0.95, 0.97, 1.0), size=(2.0, 0.5),
                  xaxis=R3 @ Vector((1, 0, 0)))
        for r in GANTRY_ROWS:
            b0, b1 = i * BAY_STEP + 0.6, (i + 1) * BAY_STEP - 0.6
            pa, pb = bearing(b0, r, GANTRY_Z - 0.15), bearing(b1, r, GANTRY_Z - 0.15)
            add_light(c, "Gantry_%02d_%d" % (i, int(r * 10)), "AREA", (pa + pb) / 2, (0, 0, -1), G["gantry"], COOL,
                      size=((pb - pa).length, 0.45), xaxis=pb - pa)
    L["rider"] = new_collection("L_Rider")
    for coll in L.values():
        coll.hide_render = True
    return L


# =============================================================================================== the rise plan
RISE_T = 9.0
RISE_ACC, RISE_DEC = 2.0, 2.0
RISE_VMAX = RISE / (RISE_ACC / 2 + (RISE_T - RISE_ACC - RISE_DEC) + RISE_DEC / 2)


def rise_s(t):
    a = RISE_VMAX / RISE_ACC
    t2 = RISE_T - RISE_DEC
    if t <= 0:
        return 0.0
    if t < RISE_ACC:
        return 0.5 * a * t * t
    s1 = 0.5 * a * RISE_ACC ** 2
    if t < t2:
        return s1 + RISE_VMAX * (t - RISE_ACC)
    if t < RISE_T:
        dt = t - t2
        return s1 + RISE_VMAX * (t2 - RISE_ACC) + RISE_VMAX * dt - 0.5 * (RISE_VMAX / RISE_DEC) * dt * dt
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


ORBIT_DEG = 270.0
# radius from the rider's axis; the orbit ends on the side of the bay, so it tightens at the top to pass inside the
# roof truss on the bay seam (7.2 studs out)
CAM_RADIUS = [(0.0, 6.5), (4.0, 8.5), (6.5, 8.0), (8.0, 5.2), (9.0, 4.8)]
CAM_HEIGHT = [(0.0, 4.4), (3.0, -3.0), (6.0, -1.0), (7.5, -1.6), (9.0, -2.4)]    # relative to the disc top
CAM_FOV = [(0.0, 50.0), (7.0, 52.0), (9.0, 62.0)]                                # vertical, degrees


def rise_camera_local(t):
    """Camera in the BAY frame (origin = bay floor centre, +Y toward the hall centre, Blender axes)."""
    z_disc = DISC_TOP + rise_s(t)
    phi = math.radians(90.0 + ORBIT_DEG * smooth(t / RISE_T))
    rho = keyed(t, CAM_RADIUS)
    pos = Vector((rho * math.cos(phi), DISC_Y + rho * math.sin(phi), z_disc + keyed(t, CAM_HEIGHT)))
    chest = Vector((0.0, DISC_Y, z_disc + 3.4))
    aperture = Vector((0.0, POLE_Y, POLE_TOP + 6.0))
    w = smooth((t - 6.5) / 2.5)
    look = chest.lerp(aperture, w)
    return pos, look, keyed(t, CAM_FOV), z_disc


def to_rbx(v):
    return [float(v[0]), float(v[2]), float(-v[1])]


def rise_plan(assets, inst, bay=0):
    """Samples the one-shot rise at 10 Hz, checks camera clearance against the set, returns the plan."""
    excl = set(o.name for o in inst["discs"][bay])
    obs = [o for o in inst["hall"] if not o.hide_render and o.name not in excl]
    bpy.context.view_layer.update()
    bvh = bvh_from_objects(obs)
    own_pole = set(o.name for o in inst["poles"][bay])
    see = [o for o in obs if o["cls"] != "glass"]                  # sight passes through the case glass
    bvh_see = bvh_from_objects(see)
    bvh_np = bvh_from_objects([o for o in see if o.name not in own_pole])
    Mb = M_facing_centre(bay_bearing(bay), CASE_R)
    keys, worst = [], (1e9, 0.0)
    occluded = 0
    occluded_not_pole = []
    for i in range(int(RISE_T * 10) + 1):
        t = i / 10.0
        p, look, fov, zd = rise_camera_local(t)
        pw = Mb @ p
        near = bvh.find_nearest(pw)
        dist = near[3] if near[0] is not None else 1e9
        if dist < worst[0]:
            worst = (dist, t)
        chest_w = Mb @ Vector((0.0, DISC_Y, zd + 3.4))
        d = chest_w - pw
        hit = bvh_see.ray_cast(pw, d.normalized(), d.length - 0.5)
        if hit[0] is not None:
            occluded += 1
            if bvh_np.ray_cast(pw, d.normalized(), d.length - 0.5)[0] is not None:
                occluded_not_pole.append(round(t, 1))
        keys.append({"t": round(t, 2), "discTopY": round(zd, 3),
                     "cameraBay": [round(v, 3) for v in to_rbx(p)], "lookAtBay": [round(v, 3) for v in to_rbx(look)],
                     "fovV": round(fov, 2)})
    plan = {
        "bayFrame": "relative to the case bay's CFrame (origin = bay floor centre, LookVector = toward the hall "
                    "centre); multiply by the bay's CFrame for world positions",
        "poleBaseY": POLE_BASE, "poleTopY": round(POLE_TOP, 3), "poleLength": round(POLE_TOP - POLE_BASE, 3),
        "discStartY": DISC_TOP, "discEndY": DISC_TOP + RISE, "riseStuds": RISE, "duration": RISE_T,
        "profile": "accelerate %.1f s, cruise %.1f s at %.2f studs/s, brake %.1f s" % (
            RISE_ACC, RISE_T - RISE_ACC - RISE_DEC, RISE_VMAX, RISE_DEC),
        "peakSpeed": round(RISE_VMAX, 3), "accel": round(RISE_VMAX / RISE_ACC, 3),
        "orbitDeg": ORBIT_DEG, "orbitDirection": "counter-clockwise seen from above, starting in front of the "
                                                 "case (toward the hall centre)",
        "radiusKeys": CAM_RADIUS, "heightKeys": CAM_HEIGHT, "fovKeys": CAM_FOV,
        "minClearance": round(worst[0], 3), "minClearanceAt": worst[1],
        "lineOfSightBlockedSamples": occluded, "blockedByOtherThanOwnPoleAt": occluded_not_pole,
        "samples": len(keys),
        "keys": keys,
    }
    log("RISE plan: %.0f studs in %.1f s, peak %.1f studs/s, camera min clearance %.2f at t=%.1f s, sight blocked "
        "in %d/%d samples (by something other than the rider's own pole at t=%s)" % (
            RISE, RISE_T, RISE_VMAX, worst[0], worst[1], occluded, len(keys), occluded_not_pole))
    return plan


# =============================================================================================== previews
FRAMES = {
    "red_a": ("launch_1_red_room_net_a.png", "T1 @120.2 S"),
    "red_b": ("launch_1_red_room_net_b.png", "T1 @122.7 S"),
    "cases": ("launch_2_glass_cases.png", "T1 @125.9 S"),
    "wide": ("launch_3_pole_hall_wide.png", "T1 @124.7 S"),
    "rise": ("launch_3_pole_rise.png", "T1 @127.2 S"),
}
TITLES = {"red_a": "RED ROOM, LOOKING DOWN THROUGH THE HEX FRAME", "red_b": "RED ROOM, THE STEEL DECK",
          "cases": "THE GLASS-CASE HALL", "wide": "THE POLE HALL", "rise": "THE RISE, LOW ANGLE"}


class Previewer:
    def __init__(self, assets, inst, lights, rise):
        self.assets, self.inst, self.L, self.rise = assets, inst, lights, rise
        self.scene = bpy.context.scene
        self.samples = 40 if QUALITY == "draft" else 160
        self.width = 760 if QUALITY == "draft" else 1100
        self.stats = {}
        self.figs = new_collection("Figures")
        os.makedirs(PREV, exist_ok=True)

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

    def fig(self, kind, M, district=None):
        return figure_object(kind, "Fig_%d" % len(self.figs.objects), M, self.figs, district)

    def bay_M(self, i):
        return M_facing_centre(bay_bearing(i), CASE_R)

    def set_disc(self, i, z_top):
        Mb = self.bay_M(i)
        for o in self.inst["discs"][i]:
            o.matrix_world = Mb @ Matrix.Translation((0, DISC_Y, z_top))

    def reset_discs(self):
        for i in range(N_BAYS):
            self.set_disc(i, DISC_TOP)

    def rider(self, i, z_top, yaw_extra=0.0, district=None):
        Mb = self.bay_M(i)
        return self.fig("tribute", Mb @ Matrix.Translation((0, DISC_Y, z_top)) @ Matrix.Rotation(
            math.radians(yaw_extra), 4, "Z"), district)

    def rider_key(self, i, z_top):
        Mb = self.bay_M(i)
        D = Mb @ Vector((0, DISC_Y, z_top))
        n_in = (Mb.to_3x3() @ Vector((0, 1, 0))).normalized()
        src = D + n_in * 7.0 + Vector((0, 0, 10.0))
        add_light(self.L["rider"], "Rider_Key", "SPOT", src, (D + Vector((0, 0, 3.0))) - src, LIGHT_GAIN["rider"],
                  (1.0, 0.97, 0.94), spot_deg=36, blend=0.6, radius=0.8)
        return D, n_in

    def render(self, name, aspect, exposure, ambient):
        set_ambient(ambient)
        w = self.width
        h = int(round(w * aspect[1] / aspect[0]))
        render_settings(self.scene, (w, h), self.samples, exposure)
        path = os.path.join(PREV, "render_%s.png" % name)
        self.scene.render.filepath = path
        t = time.time()
        bpy.ops.render.render(write_still=True)
        log("PREVIEW %s (%.0fs)" % (path, time.time() - t))
        return path

    def compare(self, name, path):
        fname, label = FRAMES[name]
        fpath = os.path.join(REF, fname)
        out = os.path.join(PREV, "compare_%s.png" % name)
        if not os.path.exists(fpath):
            log("NOTE no reference frame for %s (%s); render only" % (name, fpath))
            self.stats[name] = {"ours": colour_stats(load_rgb(path)), "frame": None}
            return
        ours, frame = compare_sheet(path, fpath, out, TITLES[name], label)
        self.stats[name] = {"ours": ours, "frame": frame}
        log("PREVIEW %s" % out)

    # -- the five compare views (owner frames)
    def v_red_a(self):
        """Frame A: the view of the rising player, steeply down through the top half of the hex frame, to the
        escort on the walkway looking up (a long lens: the frame large, the room compressed behind it)."""
        self.show({"RedRoom", "L_Red", "L_RedTop", "Figures"})
        self.fig("escort", M_place(self.assets["LaunchRedRoom"].atts["EscortWalkway"][0], 180.0))
        d = Vector((0.0, 0.682, -0.731))
        cam_p = Vector((0.0, -13.7, 42.5))
        camera(self.scene, cam_p, cam_p + d * 30.0, lens=62.0)
        return self.render("red_a", (656, 277), 0.2, "red")

    def v_red_b(self):
        """Frame B: from just above and behind the player on the lift, over the near rail to the grates."""
        self.show({"RedRoom", "L_Red", "Figures"})
        self.fig("tribute", M_place((0, 0, 0.15), -14.0))
        self.fig("guard", M_place(self.assets["LaunchRedRoom"].atts["GuardFloor"][0], 200.0))
        self.fig("guard", M_place(self.assets["LaunchRedRoom"].atts["GuardWalkway"][0], 180.0))
        camera(self.scene, (0.45, -2.9, 10.6), (0.2, 6.0, 0.0), lens=18.0)
        return self.render("red_b", (635, 284), 0.2, "red")

    def scale_lights(self, coll_key, prefix, factor):
        for o in self.L[coll_key].objects:
            if o.name.startswith(prefix):
                o.data.energy *= factor

    def v_cases(self):
        """The case row from the walkway: the near cases on the left, the row curving away to the right, a
        contender on each disc, rows of strip lights overhead. The walkway stays dark; the cases glow."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        for i in range(0, 9):
            self.rider(i, DISC_TOP, 0.0, "yellow" if i == 1 else None)
        camera(self.scene, bearing(0.0, 102.6, 6.1), bearing(30.0, 112.0, 4.6), lens=22.0)
        self.scale_lights("hall", "LED_", 0.45)
        self.scale_lights("case", "Gantry_", 0.5)
        self.scale_lights("case", "Case_", 1.6)
        p = self.render("cases", (664, 314), 0.2, "case")
        self.scale_lights("hall", "LED_", 1 / 0.45)
        self.scale_lights("case", "Gantry_", 1 / 0.5)
        self.scale_lights("case", "Case_", 1 / 1.6)
        return p

    def v_wide(self):
        """From the walkway across the hall: the far ring of poles, riders part-way up, the spoked ring above."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        rng = random.Random(7)
        for i in sorted(IN_USE):
            z = 44.0 + rng.uniform(-5, 5)
            self.set_disc(i, z)
            self.rider(i, z)
        camera(self.scene, (0.0, -102.0, 6.0), (0.0, 0.0, 55.7), lens=13.0)
        p = self.render("wide", (662, 323), 0.3, "hall")
        self.reset_discs()
        return p

    def v_rise(self):
        """Low angle in front of a rider mid-rise, the pole above the head, neighbours' strips to the sides."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures", "L_Rider"})
        rng = random.Random(11)
        for i in sorted(IN_USE):
            z = 62.0 if i == 0 else 56.0 + rng.uniform(-5, 7)
            self.set_disc(i, z)
            self.rider(i, z)
        D, n_in = self.rider_key(0, 62.0)
        camera(self.scene, D + n_in * 7.8 + Vector((0, 0, -3.2)), D + Vector((0, 0, 6.2)) - n_in * 0.3, lens=17.0)
        p = self.render("rise", (657, 306), 0.3, "hall")
        self.reset_discs()
        return p

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
            self.rider(i, DISC_TOP)
        Mb = self.bay_M(0)
        camera(self.scene, Mb @ Vector((3.2, 9.5, 5.6)), Mb @ Vector((-0.6, 0.3, 4.6)), lens=24.0)
        return self.render("overview_case_bay", (16, 9), 0.3, "case")

    def v_hall(self):
        self.show({"Hall", "L_Hall", "L_Case", "Figures"})
        for i in sorted(IN_USE):
            self.rider(i, DISC_TOP)
        camera(self.scene, (0.0, -166.0, 64.0), (0.0, 40.0, 34.0), lens=13.5)
        return self.render("overview_pole_hall", (16, 9), 0.3, "hall")

    def rise_sheet(self):
        """Frames along the suggested one-shot camera path (fewer samples), tiled with their times."""
        self.show({"Hall", "L_Hall", "L_Case", "Figures", "L_Rider"})
        Mb = self.bay_M(0)
        times = (0.0, 1.5, 3.0, 4.5, 6.0, 7.5, 8.4, 9.0)
        tiles = []
        old_w, old_s = self.width, self.samples
        self.width, self.samples = 520, max(24, self.samples // 4)
        for i in sorted(IN_USE):
            if i:
                self.rider(i, DISC_TOP)
        cam = None
        for t in times:
            for o in list(self.L["rider"].objects):
                bpy.data.objects.remove(o, do_unlink=True)
            p, look, fov, zd = rise_camera_local(t)
            self.set_disc(0, zd)
            rid = self.rider(0, zd)
            self.rider_key(0, zd)
            if t >= 6.5:                            # the aperture starts to flood with light
                ap = Mb @ Vector((0.0, POLE_Y, POLE_TOP - 1.2))
                add_light(self.L["rider"], "Aperture_Flood", "SPOT", ap, (0, 0, -1),
                          60000.0 * smooth((t - 6.5) / 2.5), (1.0, 0.99, 0.97), spot_deg=70, blend=0.8, radius=1.6)
            cam = camera(self.scene, Mb @ p, Mb @ look, lens=24.0)
            cam.data.sensor_fit = "VERTICAL"
            cam.data.angle = math.radians(fov)
            path = self.render("risepath_t%04.1f" % t, (16, 9), 0.3, "hall")
            img = load_rgb(path)
            if t >= RISE_T - 0.6:                   # the whiteout: light floods the aperture
                wgt = min(1.0, (t - (RISE_T - 0.6)) / 0.6)
                img = img * (1 - wgt) + np.ones_like(img) * wgt * 0.97
            draw_text(img, 10, 10, "T = %.1f S   DISC Y %.0f" % (t, zd), 2,
                      (0.1, 0.1, 0.12) if t >= RISE_T - 0.1 else (0.93, 0.93, 0.9))
            tiles.append(img)
            bpy.data.objects.remove(rid, do_unlink=True)
            os.remove(path)
        if cam is not None:
            cam.data.sensor_fit = "HORIZONTAL"
        self.width, self.samples = old_w, old_s
        h, w = tiles[0].shape[:2]
        cols = 4
        rows = (len(tiles) + cols - 1) // cols
        sheet = np.full((rows * (h + 8) + 40, cols * (w + 8), 3), 0.07)
        for k, img in enumerate(tiles):
            r_, c_ = divmod(k, cols)
            sheet[r_ * (h + 8):r_ * (h + 8) + h, c_ * (w + 8):c_ * (w + 8) + w] = img
        draw_text(sheet, 10, rows * (h + 8) + 12, "THE RISE, ONE SHOT: %.0f STUDS IN %.0f S, THE CAMERA ORBITS %.0f "
                  "DEG ROUND THE RIDER, THEN THE WHITEOUT" % (RISE, RISE_T, ORBIT_DEG), 2)
        out = os.path.join(PREV, "rise_path_sheet.png")
        save_rgb(out, sheet)
        self.reset_discs()
        log("PREVIEW %s" % out)

    def palette_sheet(self):
        """Swatches: sampled frame colour -> semi-real tone, with luma (our numbers only)."""
        keys = [k for k in PAL if PAL[k][4] != "neon"]
        sw, sh_, pad = 64, 40, 8
        cols = 3
        rows = (len(keys) + cols - 1) // cols
        cw = sw * 2 + 300
        img = np.full((rows * (sh_ + pad) + 50, cols * cw, 3), 0.1)
        draw_text(img, 10, 10, "LAUNCH PALETTE: SAMPLED (LEFT) -> SEMI-REAL TONE (RIGHT), RGB AND LUMA", 2)
        for n, k in enumerate(keys):
            r_, c_ = divmod(n, cols)
            x0, y0 = c_ * cw + 10, 40 + r_ * (sh_ + pad)
            tone, sampled = PAL[k][0], PAL[k][1]
            if sampled:
                s = tuple(int(sampled[i:i + 2], 16) for i in (1, 3, 5))
                img[y0:y0 + sh_, x0:x0 + sw] = np.array(s) / 255.0
            img[y0:y0 + sh_, x0 + sw + 4:x0 + 2 * sw + 4] = np.array(tone) / 255.0
            draw_text(img, x0 + 2 * sw + 12, y0 + 6, k.replace("_", " "), 2)
            draw_text(img, x0 + 2 * sw + 12, y0 + 24, "%d %d %d  L%.0f" % (tone[0], tone[1], tone[2], luma(tone)), 2)
        out = os.path.join(PREV, "palette_swatches.png")
        save_rgb(out, img)
        log("PREVIEW %s" % out)

    def run(self):
        views = [("red_a", self.v_red_a, True), ("red_b", self.v_red_b, True), ("cases", self.v_cases, True),
                 ("wide", self.v_wide, True), ("rise", self.v_rise, True),
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
                self.stats[name] = {"ours": colour_stats(load_rgb(path)), "frame": None}
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
        with open(cc, "w", encoding="utf-8") as f:
            json.dump(old, f, indent=1)
        for k, v in self.stats.items():
            log("COLOUR %-14s ours %s" % (k, v["ours"]))
            if v.get("frame"):
                log("COLOUR %-14s film %s" % (k, v["frame"]))


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
        "schema": "LS-Launch-1 (faceted style A, palette atlas)",
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
        "budgets": budgets,
        "set": {
            "frame": "the pole hall: origin at its floor centre (y 0); bearings clockwise from north (Roblox -Z). "
                     "CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(yawDeg), 0).",
            "dimensions": {"hallDiameter": 2 * HALL_R, "wallTop": WALL_TOP, "crownDiameter": 2 * CROWN_R,
                           "crownY": 127.0, "caseRingRadius": CASE_R, "poleRingRadius": POLE_R,
                           "bankedRing": [120.4, HALL_R], "walkway": [98.6, CASE_R - CDp / 2 - 0.2],
                           "gantryY": GANTRY_Z, "ledRings": [r for r, _, _ in LED_RINGS]},
            "instances": set_inst,
            "redRoom": {"asset": "LaunchRedRoom", "placement": "client-local, one per player: under the player's "
                        "own bay, origin = bay origin + (0, -40, 0), same yaw (its roof top then sits 18 studs "
                        "under the hall floor). Nobody else ever sees it.",
                        "liftTravel": "the rose lift disc rises from y 0.15 up through the hex frame (y 21.6) into "
                                      "the dark above the roof; the cut to the case hides there"},
        },
        "rise": rise,
        "sequence": [
            {"stage": "1 Red room (transition, loops while the map loads)", "seconds": ">= 4, loops",
             "camera": "first person while waiting (the room is walkable). When the map is ready: a chime, the "
                       "player is set on the lift disc (Spawn) and the cinematic starts on CamTopDown: straight "
                       "down through the hex frame, pushing in from y 33 to 27 over 2.5 s (the film's framing)."},
            {"stage": "2 Up the lift", "seconds": 3.0,
             "camera": "the disc lifts; the camera rises ahead of the player through the hex frame into the dark "
                       "above the roof (hidden cut 1)."},
            {"stage": "3 The glass case", "seconds": 4.0,
             "camera": "open on the player in their case (CamCase); pull back out through the front glass to the "
                       "walkway and sweep 20 degrees along the curving row of cases (others stand in theirs)."},
            {"stage": "4 The rise (one shot)", "seconds": RISE_T,
             "camera": "rise.keys: the disc rides the pole %.0f studs while the camera orbits %.0f degrees round "
                       "the rider, low first (looking up the pole, T1 @127.2 s), then level, then up at the "
                       "aperture." % (RISE, ORBIT_DEG)},
            {"stage": "5 Whiteout", "seconds": 1.0,
             "camera": "overlaps the last 0.6 s of the rise: the aperture floods white (hidden cut 2 into the arena)."},
            {"stage": "6 Arrival", "seconds": 3.0,
             "camera": "Map 1: up the brass-rimmed tube in the turf; Map 2: the plate surfaces in the lagoon. The "
                       "camera finishes the circle (the last 90 degrees) and settles behind the head facing the "
                       "horn; then first person."},
        ],
        "lighting": {
            "LaunchRedRoom": {"ambient": list(AMBIENT["red"]), "exposure": 0.2,
                              "lights": "SpotLight at KeyLight (cool white, angle 78, aimed down); a red "
                                        "SurfaceLight (Face Top) in each grate pit at GrateGlow_n; PointLights "
                                        "(warm white, range 10) at Lamp_n"},
            "LaunchCaseHall": {"ambient": list(AMBIENT["case"]), "exposure": 0.3,
                               "lights": "SurfaceLight (Face Bottom) on each case top-light and each gantry strip; "
                                         "a small SurfaceLight on each unit panel"},
            "LaunchPoleHall": {"ambient": list(AMBIENT["hall"]), "exposure": 0.3, "bloomThreshold": 1.4,
                               "lights": "SpotLights (angle 34) at the 12 HubSpot_n; a SurfaceLight (Face Bottom) "
                                         "on every LED bar; the poles' strips are Neon only; a SpotLight that rides "
                                         "7 studs in front of and 10 above each rider (the rider key)"},
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
            "tone. Saturated colour only on the red rails and lamps and the light sources.",
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
