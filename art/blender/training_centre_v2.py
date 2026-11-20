"""
training_centre_v2.py - LAST STANDING: the Training Centre's look pass v2 (wave 27, Blender 5.3, headless)
                        -> TrainingCentreV2.glb + TrainingCentreV2.manifest.json + TrainingCentreV2.prims.json
                        -> src/ServerStorage/WorldGen/TrainingCentreDressData.lua (for TrainingCentreBuilder)

The owner, 20 Nov 2026: "recreate the training room to look more like the one in the movie". The redesign spec is
wave27/tc_design.md (tcresearch). Our own room: the film is mood and layout reference only; no film names, logos,
words, costumes or characters. Matte, one flat colour per part, no image textures (ArtStyle).

What it adds on top of the v1 set (art/blender/training_centre.py, uploaded once as LS_TrainingCentre_v1), as one new
asset TC_Dress placed at the hall origin (hall space: Roblox axes, x east, z north negative, floor y 0):
  Flute        each 8-stud padded wall panel carries 4 faceted vertical flutes (6 facets), leaning with the panel
  Strut        white V-pairs of portal struts (2.4 x 1.4) on white plinths, up to a white ring beam (y 29..31) that
               runs round the whole hall over the panels; a warm Neon cove strip hides on the beam's top
  Chequer      a 2.5-stud blue-slate chequer (replaces the v1 5-stud FloorTile in mesh mode; the Part build of the set
               scales the v1 tile mesh instead: no prims are written for it)
  Deck/DeckEdge honey-teak station decks (0.35 high: TrainingStations.DeckHeight) under survival, the blade circle,
               fitness and the spear range, with rubber nosing; a low teak strip behind the archery line
  Slat*        our own split-flap boards: two 7-slat stacks on the north wall (in front of the panels: the v1 colour bars
               hid behind them) and a 4-sided board on a drop column from the ceiling over the hall's middle
  Gallery*     an observers' pod cantilevered off the west wall over survival and the blade circle (y 17..29): white
               frame, raked tinted glass, walnut inside, teak lounge chairs, faceless dark silhouettes. Not reachable.
  props        a white hoop wheel (fitness), cream cushions round the blade ring, two wall clocks, a teak fountain
Markers (attachments): SlatText_* (SurfaceGui faces, attribute text; screen = the call's countdown), BaySign_* (tall
StationSigns at each deck's front corner), CoveLight_*, GalleryGlow_*.

Run: blender --background --factory-startup --python art/blender/training_centre_v2.py -- <export dir> [<lua out>]
Seeded (SEED = 1127). The geometry helpers (MB, box, beam, loft, realize...) come from training_centre.py.
"""
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
_ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

# the v1 generator's helpers, without running it (its last line is main())
_src = open(os.path.join(HERE, "training_centre.py"), encoding="utf-8").read()
_cut = _src.rfind("\nmain()")
G = {"__name__": "training_centre_lib", "__file__": os.path.join(HERE, "training_centre.py")}
exec(compile(_src[:_cut], "training_centre.py", "exec"), G)
for _k in ("MB", "box", "beam", "loft", "cyl", "cube", "hexa", "quad_up", "M", "V", "realize", "reset_scene",
           "glb_check", "att_json", "Asset", "ROLES", "NO_SHADOW", "TRANSPARENCY", "bounds_rbx", "R3", "log"):
    globals()[_k] = G[_k]

import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

SEED = 1127
CATEGORY = "TrainingCentreV2"
OUT = _ARGV[0] if len(_ARGV) > 0 and _ARGV[0] not in ("", "-") else os.path.join(
    os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports", CATEGORY)
LUA_OUT = _ARGV[1] if len(_ARGV) > 1 else os.path.join(REPO, "src", "ServerStorage", "WorldGen",
                                                         "TrainingCentreDressData.lua")
HX, HZ, HH = 110.0, 75.0, 36.0
DECK_H = 0.35          # = TrainingStations.DeckHeight (the builder lifts those stations' v1 assets by it)
ARCH_H = 0.08          # the archery strip: an inlay (the shooting line and the lane pads stay on the floor)
RING_Y0, RING_Y1, RING_D = 29.0, 31.0, 4.2
STRUT_OFF = 3.4        # strut centre line from the wall face

# ------------------------------------------------------------------------------------------------ palette (tc_design 3)
NEW_ROLES = {
    "Flute":        ((58, 104, 110), "Fabric"),
    "Strut":        ((226, 224, 216), "SmoothPlastic"),
    "Cove":         ((255, 214, 170), "Neon"),
    "Chequer":      ((98, 116, 132), "Carpet"),   # (112,128,138) read near-white under the grid (Studio, 20 Nov)
    "Deck":         ((118, 90, 70), "Wood"),     # teak: (176,118,70) and (146,102,70) read "use" orange under the warm grid
    "DeckEdge":     ((60, 66, 72), "Rubber"),
    "SlatBody":     ((30, 33, 36), "SmoothPlastic"),
    "SlatFrame":    ((52, 56, 60), "SmoothPlastic"),
    "SlatTeal":     ((72, 126, 130), "SmoothPlastic"),
    "SlatOchre":    ((190, 150, 70), "SmoothPlastic"),
    "SlatBlue":     ((80, 104, 150), "SmoothPlastic"),
    "SlatRose":     ((168, 92, 96), "SmoothPlastic"),
    "SlatSage":     ((120, 150, 110), "SmoothPlastic"),
    "GalleryWall":  ((60, 44, 34), "Wood"),
    "GalleryFloor": ((44, 34, 28), "Wood"),
    "GalleryGlass": ((150, 180, 185), "Glass"),
    "Teak":         ((150, 100, 60), "Wood"),
    "Upholstery":   ((190, 150, 70), "Fabric"),
    "Silhouette":   ((26, 28, 32), "SmoothPlastic"),
    "Cushion":      ((226, 210, 160), "Fabric"),
    "ClockFace":    ((240, 236, 226), "SmoothPlastic"),
    "SteelD":       ((120, 126, 132), "SmoothPlastic"),
}
ROLES.update(NEW_ROLES)
NO_SHADOW.update({"Cove", "Chequer", "GalleryGlass", "DeckEdge", "Silhouette"})
TRANSPARENCY["GalleryGlass"] = 0.55
SLAT_ENDS = ["SlatTeal", "SlatOchre", "SlatBlue", "SlatRose", "SlatSage"]


def segs(lo, hi, opens):
    out, cur = [], lo
    for o0, o1 in sorted(opens):
        if o0 > cur:
            out.append((cur, o0))
        cur = max(cur, o1)
    if cur < hi:
        out.append((cur, hi))
    return out


def flute(mb, p0, p1, along, nrm, r, n=6):
    """A faceted round bolster from p0 to p1 (its axis), `along` the wall, `nrm` out of it; a flat facet faces out."""
    p0, p1, along, nrm = V(p0), V(p1), V(along).normalized(), V(nrm).normalized()
    vs, fs = [], []
    for c in (p0, p1):
        for k in range(n):
            a = 2 * math.pi * k / n     # vertices at 0, 60, ... from `along`: a flat facet faces out
            vs.append(c + along * (math.cos(a) * r) + nrm * (math.sin(a) * r))
    for k in range(n):
        k2 = (k + 1) % n
        fs.append((k, k2, n + k2, n + k))
    fs.append(tuple(reversed(range(n))))
    fs.append(tuple(n + k for k in range(n)))
    mb.add(vs, fs, loft_n=n)


def wedge_x(mb, x_hi, x_lo, z0, z1, h):
    """A sloped nosing falling from height h at x_hi to 0 at x_lo (either order), along z0..z1."""
    hexa(mb, [(x_hi, 0.0, z0), (x_lo, 0.0, z0), (x_lo, 0.0, z1), (x_hi, 0.0, z1),
              (x_hi, h, z0), (x_lo, 0.01, z0), (x_lo, 0.01, z1), (x_hi, h, z1)])


def wedge_z(mb, z_hi, z_lo, x0, x1, h):
    hexa(mb, [(x0, 0.0, z_hi), (x1, 0.0, z_hi), (x1, 0.0, z_lo), (x0, 0.0, z_lo),
              (x0, h, z_hi), (x1, h, z_hi), (x1, 0.01, z_lo), (x0, 0.01, z_lo)])


# ================================================================================================ the dress
def build_dress():
    rnd = random.Random(SEED)
    a = Asset("TC_Dress", "Hall",
              "Wave 27 look pass over the v1 hall: fluted wall panels, white V struts on a ring beam with a cove, a "
              "2.5-stud blue-slate chequer, teak station decks, split-flap slat boards (north wall + a 4-sided board "
              "over the middle), an observers' pod on the west wall, a hoop, cushions, clocks and a fountain.")

    # ---- flutes on every v1 wall panel (same modules as training_centre.build_shell)
    north_open = [(-16.0, 16.0)]
    south_open = [(-48.0, -32.0), (-8.0, 8.0), (32.0, 48.0)]
    nfl = 0
    for wn, sgn in (("N", -1), ("S", 1), ("W", -1), ("E", 1)):
        along_x = wn in ("N", "S")
        L = HX if along_x else HZ
        opens = north_open if wn == "N" else (south_open if wn == "S" else [])
        inward = -sgn
        for s0, s1 in segs(-L, L, opens):
            k = int(math.floor((s1 - s0) / 8.0 + 1e-6))
            if k <= 0:
                continue
            w = (s1 - s0) / k
            for i in range(k):
                c0, c1 = s0 + i * w + 0.25, s0 + (i + 1) * w - 0.25
                for f in range(4):
                    u = c0 + (f + 0.5) * (c1 - c0) / 4
                    if along_x:
                        def P(uu, y, d):
                            return (uu, y, sgn * HZ + inward * d)
                        al, nr = (1, 0, 0), (0, 0, inward)
                    else:
                        def P(uu, y, d):
                            return (sgn * HX + inward * d, y, uu)
                        al, nr = (0, 0, 1), (inward, 0, 0)
                    flute(a.mb("Flute"), P(u, 3.25, 0.55 - 0.45), P(u, 29.55, 1.35 - 0.45), al, nr, 0.95)
                    nfl += 1
    a.extra["flutes"] = nfl

    # ---- ring beam round the hall + cove strip on its top (hidden from the floor)
    st = a.mb("Strut")
    box(st, (-HX, RING_Y0, -HZ), (HX, RING_Y1, -HZ + RING_D))
    box(st, (-HX, RING_Y0, HZ - RING_D), (HX, RING_Y1, HZ))
    box(st, (-HX, RING_Y0, -HZ + RING_D), (-HX + RING_D, RING_Y1, HZ - RING_D))
    box(st, (HX - RING_D, RING_Y0, -HZ + RING_D), (HX, RING_Y1, HZ - RING_D))
    cv = a.mb("Cove")
    box(cv, (-HX + 1.2, RING_Y1, -HZ + 1.2), (HX - 1.2, RING_Y1 + 0.2, -HZ + 2.2))
    box(cv, (-HX + 1.2, RING_Y1, HZ - 2.2), (HX - 1.2, RING_Y1 + 0.2, HZ - 1.2))
    box(cv, (-HX + 1.2, RING_Y1, -HZ + 2.2), (-HX + 2.2, RING_Y1 + 0.2, HZ - 2.2))
    box(cv, (HX - 2.2, RING_Y1, -HZ + 2.2), (HX - 1.2, RING_Y1 + 0.2, HZ - 2.2))
    coves = [("N", x) for x in (-82.0, -27.0, 27.0, 82.0)] + [("S", x) for x in (-82.0, -27.0, 27.0, 82.0)] + \
            [("W", z) for z in (-37.0, 37.0)] + [("E", z) for z in (-37.0, 37.0)]
    for i, (wn, u) in enumerate(coves):
        if wn in ("N", "S"):
            p = (u, RING_Y1 + 1.0, (-HZ + 2.5) if wn == "N" else (HZ - 2.5))
        else:
            p = ((-HX + 2.5) if wn == "W" else (HX - 2.5), RING_Y1 + 1.0, u)
        a.mark("CoveLight_%02d" % (i + 1), p, (0, -1, 0), (0, 0, -1), {"wall": wn})

    # ---- white V struts: (wall, u of the V's foot). Placed clear of the doors, arches, slat stacks, archery lanes,
    #      the climbing wall, the hay bales, the archer mat and the gallery pod (tc_design 3.2 / checked against v1).
    vs_ = {"N": [-88.0, -56.0, 56.0, 88.0], "S": [-96.0, -64.0, -20.0, 20.0], "W": [27.0], "E": [-16.0, 16.0, 44.0]}
    for wn, us in vs_.items():
        for u in us:
            if wn in ("N", "S"):
                zc = (-HZ + STRUT_OFF) if wn == "N" else (HZ - STRUT_OFF)

                def Q(uu, y):
                    return (uu, y, zc)
                nrm = (0, 0, 1 if wn == "N" else -1)
                lo, hi = (u - 1.7, 0.0, zc - 1.0), (u + 1.7, 0.6, zc + 1.0)
                clo, chi = (u - 4.0, 0.0, zc - 0.7), (u + 4.0, 8.0, zc + 0.7)
            else:
                xc = (-HX + STRUT_OFF) if wn == "W" else (HX - STRUT_OFF)

                def Q(uu, y):
                    return (xc, y, uu)
                nrm = (1 if wn == "W" else -1, 0, 0)
                lo, hi = (xc - 1.0, 0.0, u - 1.7), (xc + 1.0, 0.6, u + 1.7)
                clo, chi = (xc - 0.7, 0.0, u - 4.0), (xc + 0.7, 8.0, u + 4.0)
            box(st, lo, hi)
            for s in (-1, 1):
                beam(st, Q(u + s * 0.6, 0.6), Q(u + s * 10.0, RING_Y0), 2.4, 1.4, up=nrm)
            a.col("Strut_%s_%d" % (wn, int(u)), clo, chi)

    # ---- the 2.5-stud chequer (mesh only; the Part build scales the v1 tile mesh)
    t = 2.5
    nx, nz = int(2 * HX / t), int(2 * HZ / t)
    for i in range(nx):
        for j in range(nz):
            if (i + j) % 2 == 0:
                quad_up(a.mb("Chequer"), -HX + i * t, -HZ + j * t, -HX + (i + 1) * t, -HZ + (j + 1) * t, 0.03)

    # ---- decks (tc_design 3.1; footprints cover every v1 prop of the station, which the builder lifts by DECK_H)
    dk, de = a.mb("Deck"), a.mb("DeckEdge")
    west = [("Survival", -75.0, -20.0), ("Blade", -20.0, 30.0), ("Fitness", 30.0, 73.0)]
    for name, z0, z1 in west:
        box(dk, (-HX, 0.0, z0), (-44.0, DECK_H, z1))
        a.col("Deck_" + name, (-HX, -0.5, z0), (-44.0, DECK_H, z1))
    for z in (-20.0, 30.0):     # rubber seams between the west decks (the partitions stand on them)
        box(de, (-58.0, DECK_H, z - 0.2), (-44.0, DECK_H + 0.02, z + 0.2))
    wedge_x(de, -44.0, -42.8, -75.0, 73.0, DECK_H)
    wedge_z(de, 73.0, 74.2, -HX, -44.0, DECK_H)
    box(dk, (42.0, 0.0, -HZ), (HX, DECK_H, -35.5))
    a.col("Deck_Spear", (42.0, -0.5, -HZ), (HX, DECK_H, -35.5))
    wedge_x(de, 42.0, 40.8, -HZ, -35.5, DECK_H)
    wedge_z(de, -35.5, -34.3, 40.8, 58.0, DECK_H)
    # the throw line again on the deck (the v1 line lifts with its asset; this keeps it bright at the deck's edge)
    # archery: a low teak strip behind the shooting line (the lane pads and the line stay on the floor)
    box(dk, (46.0, 0.0, 66.4), (98.0, ARCH_H, 74.6))
    box(de, (46.0, 0.0, 66.4), (98.0, ARCH_H + 0.02, 66.7))
    a.col("Deck_Archery", (46.0, -0.5, 66.4), (98.0, ARCH_H, 74.6))
    a.extra["decks"] = {"height": DECK_H, "archery": ARCH_H}

    # ---- slat boards
    def slat(cx, y, zf, face, text, role, name, screen=False, width=15.0):
        """One slat: body width x 1.8, its front at zf facing `face` (+1 = +z); a coloured end block on the left."""
        mb_b = a.mb("SlatBody")
        d = 0.5
        if face > 0:
            box(mb_b, (cx - width / 2, y, zf - d), (cx + width / 2, y + 1.8, zf))
            left = cx - width / 2
            box(a.mb(role), (left, y, zf - d), (left + 2.0, y + 1.8, zf + 0.04))
            p = (cx + 1.0, y + 0.9, zf + 0.02)
            look = (0, 0, 1)
        else:
            box(mb_b, (cx - width / 2, y, zf), (cx + width / 2, y + 1.8, zf + d))
            left = cx + width / 2   # the left as you read it from -z
            box(a.mb(role), (left - 2.0, y, zf - 0.04), (left, y + 1.8, zf + d))
            p = (cx - 1.0, y + 0.9, zf - 0.02)
            look = (0, 0, -1)
        at = {"text": text, "size": [width - 2.4, 1.5]}
        if screen:
            at["screen"] = True
        a.mark(name, p, look, (0, 1, 0), at)

    def slat_x(cz, y, xf, face, text, role, name, screen=False, width=15.0):
        """The same along z, its front at xf facing `face` (+1 = +x)."""
        d = 0.5
        mb_b = a.mb("SlatBody")
        if face > 0:
            box(mb_b, (xf - d, y, cz - width / 2), (xf, y + 1.8, cz + width / 2))
            left = cz + width / 2       # reading from +x, left is +z
            box(a.mb(role), (xf - d, y, left - 2.0), (xf + 0.04, y + 1.8, left))
            p = (xf + 0.02, y + 0.9, cz - 1.0)
            look = (1, 0, 0)
        else:
            box(mb_b, (xf, y, cz - width / 2), (xf + d, y + 1.8, cz + width / 2))
            left = cz - width / 2
            box(a.mb(role), (xf - 0.04, y, left), (xf + d, y + 1.8, left + 2.0))
            p = (xf - 0.02, y + 0.9, cz + 1.0)
            look = (-1, 0, 0)
        at = {"text": text, "size": [width - 2.4, 1.5]}
        if screen:
            at["screen"] = True
        a.mark(name, p, look, (0, 1, 0), at)

    # north stacks: in front of the fluted panels (fronts at z -72.3), 7 slats, hung from the ring beam
    stacks = {
        -30.0: ["ARCHERY  ·  EAST LANES", "THROWING  ·  NORTH-EAST", "BLADE CIRCLE  ·  WEST", "SURVIVAL  ·  NORTH-WEST",
                "FITNESS  ·  SOUTH-WEST", "TRACK  ·  THE MIDDLE", "KIT BOARD  ·  BY THE BENCHES"],
        30.0: [None, "PICK A KIT ON THE ORANGE MATS", "BORROW FROM THE STATION CHESTS", "PASS A DRILL  ·  EARN A TOKEN",
               "ALLIES  ·  ASK AT THE BENCHES", "STAY IN YOUR BAY WITH LENT GEAR", "THE LAUNCH  ·  NORTH DOORS"],
    }
    zf = -HZ + 2.7
    fr = a.mb("SlatFrame")
    for cx, lines in stacks.items():
        for k in range(7):
            y = 28.3 - 1.8 - k * 2.05      # top slat first
            txt = lines[k]
            slat(cx, y, zf, 1, txt or "THE TRAINING CENTRE", SLAT_ENDS[(k + (2 if cx > 0 else 0)) % 5],
                 "SlatText_N%s_%d" % ("W" if cx < 0 else "E", k + 1), screen=txt is None)
        for s in (-1, 1):
            box(fr, (cx + s * 7.8 - 0.3, 13.9, zf - 0.75), (cx + s * 7.8 + 0.3, 28.6, zf - 0.15))
            box(fr, (cx + s * 6.0 - 0.1, 28.6, zf - 0.55), (cx + s * 6.0 + 0.1, RING_Y0, zf - 0.35))
        box(fr, (cx - 8.1, 28.3, zf - 0.75), (cx + 8.1, 28.6, zf - 0.15))
        # a round wall clock on the ring beam's face over the stack (white face, dark rim and hands)
        cz = -HZ + RING_D
        cyl(a.mb("SlatFrame"), M((cx, 30.0, cz), 0, 90), 2.15, 0.2, n=12)
        cyl(a.mb("ClockFace"), M((cx, 30.0, cz), 0, 90), 1.85, 0.3, n=12)
        hr, mn = rnd.uniform(0, 360), rnd.uniform(0, 360)
        cube(a.mb("SlatBody"), M((cx, 30.0, cz + 0.36), 0, 0, hr), (0.22, 1.1, 0.06), (0, 0.45, 0))
        cube(a.mb("SlatBody"), M((cx, 30.0, cz + 0.4), 0, 0, mn), (0.14, 1.6, 0.06), (0, 0.7, 0))

    # the 4-sided board on a drop column over the hall's middle (nothing on the floor: the centre walk stays clear)
    box(st, (-1.5, 19.95, -1.5), (1.5, HH, 1.5))
    rows = {
        "N": [None, "ARCHERY  ·  4 HITS IN 30 s", "THROWING  ·  3 HITS AT 20+", "BLADES  ·  8 CLEAN HITS IN 25 s"],
        "S": [None, "LAP  ·  UNDER 19 s", "OBSTACLE RUN  ·  UNDER 12 s", "CLIMB  ·  THE TOP IN 8 s"],
        "E": [None, "SURVIVAL  ·  ALL FOUR IN 45 s", "BIKE  ·  20 s IN THE GREEN", "WEIGHTS  ·  10 ON THE BEAT"],
        "W": [None, "TRAIN  ·  THEN TAKE THE CALL", "ONE TOKEN PER DRILL PASSED", "THE GAMES ARE WATCHING"],
    }
    R = 8.25
    for side, lines in rows.items():
        for k in range(4):
            y = 26.15 - k * 2.05
            role = SLAT_ENDS[(k + "NESW".index(side)) % 5]
            nm = "SlatText_P%s_%d" % (side, k + 1)
            txt = lines[k] or "THE TRAINING CENTRE"
            if side == "N":
                slat(0.0, y, -R, -1, txt, role, nm, screen=lines[k] is None, width=15.6)
            elif side == "S":
                slat(0.0, y, R, 1, txt, role, nm, screen=lines[k] is None, width=15.6)
            elif side == "E":
                slat_x(0.0, y, R, 1, txt, role, nm, screen=lines[k] is None, width=15.6)
            else:
                slat_x(0.0, y, -R, -1, txt, role, nm, screen=lines[k] is None, width=15.6)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(fr, (sx * 8.15 - 0.35, 19.6, sz * 8.15 - 0.35), (sx * 8.15 + 0.35, 28.6, sz * 8.15 + 0.35))
    box(st, (-8.6, 28.2, -8.6), (8.6, 28.9, 8.6))
    box(fr, (-8.4, 19.5, -8.4), (8.4, 19.95, 8.4))     # a dark underside (white glared from below)

    # ---- the observers' pod (our own; tc_design 3.6, moved inside the hall: the v1 wall is one merged mesh)
    gx0, gx1, gz0, gz1 = -HX + 1.9, -97.0, -60.0, 16.0
    gf = a.mb("GalleryFloor")
    box(gf, (gx0, 17.2, gz0), (gx1, 18.0, gz1))
    box(st, (gx0, 16.6, gz0), (gx1 + 0.4, 17.2, gz1))               # white soffit
    box(st, (gx1, 16.6, gz0), (gx1 + 0.4, 18.6, gz1))               # white fascia
    box(st, (gx0, 28.0, gz0), (gx1 + 0.6, 29.0, gz1))               # roof under the ring beam
    for z in (gz0, gz1 - 0.6):
        box(a.mb("GalleryWall"), (gx0, 17.2, z), (gx1 + 0.4, 28.0, z + 0.6))
        box(st, (gx0, 17.2, z + (-0.05 if z == gz0 else 0.55)), (gx1 + 0.45, 28.0, z + (0.05 if z == gz0 else 0.65)))
    box(a.mb("GalleryWall"), (gx0, 18.0, gz0), (gx0 + 0.5, 28.0, gz1))
    # raked glass: foot at x -99.4, y 18.6; head leaning out to x -97.6, y 28
    gl = a.mb("GalleryGlass")
    fx0, fy0, fx1, fy1 = -99.4, 18.6, -97.6, 28.0
    hexa(gl, [(fx0, fy0, gz0 + 0.6), (fx0 + 0.15, fy0, gz0 + 0.6), (fx0 + 0.15, fy0, gz1 - 0.6), (fx0, fy0, gz1 - 0.6),
              (fx1, fy1, gz0 + 0.6), (fx1 + 0.15, fy1, gz0 + 0.6), (fx1 + 0.15, fy1, gz1 - 0.6), (fx1, fy1, gz1 - 0.6)])
    nm = 9
    for k in range(nm + 1):
        z = gz0 + 0.6 + (gz1 - gz0 - 1.2) * k / nm
        beam(st, (fx0 + 0.1, fy0 - 0.4, z), (fx1 + 0.1, fy1, z), 0.4, 0.45, up=(1, 0, 0))
    box(st, (fx0 - 0.3, 18.0, gz0), (gx1 + 0.4, 18.6, gz1))          # sill
    # inside: a counter on the back wall, ten teak lounge chairs facing the hall, low tables, five silhouettes
    box(a.mb("Teak"), (gx0 + 0.5, 18.0, -50.0), (gx0 + 2.3, 21.4, 6.0))
    seated = {1, 3, 4, 6, 8}
    for i in range(10):
        z = -55.0 + i * 7.4
        cxh = -102.6
        tk, up_ = a.mb("Teak"), a.mb("Upholstery")
        for sx in (-0.9, 0.9):
            for sz in (-0.9, 0.9):
                beam(tk, (cxh + sx * 1.05, 18.0, z + sz * 1.05), (cxh + sx * 0.8, 19.4, z + sz * 0.8), 0.2, 0.2)
        box(up_, (cxh - 1.1, 19.4, z - 1.1), (cxh + 1.1, 20.0, z + 1.1))
        hexa(up_, [(cxh - 1.2, 19.9, z - 1.1), (cxh - 0.7, 19.9, z - 1.1), (cxh - 0.7, 19.9, z + 1.1), (cxh - 1.2, 19.9, z + 1.1),
                   (cxh - 1.8, 22.6, z - 1.1), (cxh - 1.3, 22.6, z - 1.1), (cxh - 1.3, 22.6, z + 1.1), (cxh - 1.8, 22.6, z + 1.1)])
        if i < 9:
            cyl(tk, M((cxh + 0.2, 18.0, z + 3.7)), 0.7, 1.4, n=8)
        if i in seated:
            sl = a.mb("Silhouette")
            cube(sl, M((cxh - 0.5, 0, z), 0, 0, 8), (1.0, 2.2, 1.5), (0, 21.1, 0))
            loft(sl, M((cxh - 0.35, 22.4, z)), [(0.0, 0.3, 0.3), (0.35, 0.5, 0.45), (0.9, 0.42, 0.4), (1.25, 0.15, 0.15)],
                 n=6, phase=rnd.uniform(0, 1))
            cube(sl, M((cxh + 0.3, 0, z)), (1.4, 0.5, 1.3), (0, 19.95, 0))
    for i, z in enumerate((-46.0, -22.0, 2.0)):
        a.mark("GalleryGlow_%d" % (i + 1), (-101.0, 26.5, z), (1, 0, 0), (0, 1, 0))
    a.col("Gallery", (-HX, 16.6, gz0 - 0.1), (gx1 + 0.6, 29.0, gz1 + 0.1))

    # ---- props
    # a white hoop wheel (8 across) on the fitness deck, standing in the y-z plane on two feet
    hx, hz, hy = -84.0, 38.0, DECK_H + 4.6
    n = 14
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        beam(st, (hx, hy + math.sin(a0) * 4.0, hz + math.cos(a0) * 4.0), (hx, hy + math.sin(a1) * 4.0, hz + math.cos(a1) * 4.0),
             0.55, 0.55, up=(1, 0, 0))
    for s in (-1, 1):
        beam(a.mb("SlatFrame"), (hx, DECK_H, hz + s * 1.6), (hx, hy - 3.6, hz + s * 0.5), 0.3, 0.3, up=(1, 0, 0))
    box(a.mb("SlatFrame"), (hx - 0.8, DECK_H, hz - 2.2), (hx + 0.8, DECK_H + 0.2, hz + 2.2))
    a.col("Hoop", (hx - 0.4, DECK_H, hz - 4.3), (hx + 0.4, hy + 4.3, hz + 4.3))
    # cream cushions round the blade ring
    for dx, dz in ((11.7, -11.7), (-11.7, -11.7), (11.7, 11.7), (-11.7, 11.7)):
        cyl(a.mb("Cushion"), M((-75.0 + dx, DECK_H, 7.5 + dz), rnd.uniform(0, 60)), 1.3, 0.55, n=8, r2=1.15)
    # a teak drinking fountain on the south wall, west of the middle arch
    fx, fz = -14.0, 73.0
    box(a.mb("Teak"), (fx - 1.3, 0.0, fz - 0.9), (fx + 1.3, 3.0, fz + 1.5))
    box(a.mb("SteelD"), (fx - 1.4, 3.0, fz - 1.0), (fx + 1.4, 3.3, fz + 1.5))
    cyl(a.mb("SteelD"), M((fx, 3.3, fz + 0.6)), 0.12, 0.5, n=6)
    a.col("Fountain", (fx - 1.4, 0.0, fz - 1.0), (fx + 1.4, 3.3, fz + 1.5))

    # ---- tall bay signs (StationSign, Width 4.2, Height 4.4), at each deck's front corner, facing the track
    signs = [("Archery", "ARCHERY", "Six lanes · bows at the chest", (44.0, 0.0, 63.5), (-1, 0, 0)),
             ("Spear", "SPEAR & THROWING", "Spears and knives · throw from the line", (39.0, 0.0, -33.0), (-1, 0, 0)),
             ("Survival", "SURVIVAL", "Fire · water · plants · bandage", (-45.6, DECK_H, -23.5), (1, 0, 0)),
             ("Blade", "BLADE CIRCLE", "Pick a Specialty · spar the dummies", (-45.6, DECK_H, 26.0), (1, 0, 0)),
             ("Fitness", "FITNESS", "Wall · bikes · weights", (-45.6, DECK_H, 33.5), (1, 0, 0))]
    for sid, title, cap, p, look in signs:
        a.mark("BaySign_" + sid, p, look, (0, 1, 0), {"title": title, "caption": cap})
    return a


# ================================================================================================ export
def num(x):
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, int):
        return str(x)
    s = ("%.4f" % x).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, (bool, int, float)):
        return num(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join("%s=%s" % (k if k.isidentifier() else "[%s]" % json.dumps(k), lua(x)) for k, x in v.items()) + "}"
    raise TypeError(type(v))


def main():
    random.seed(SEED)
    os.makedirs(OUT, exist_ok=True)
    a = build_dress()
    scene = reset_scene()
    coll = scene.collection
    root, parts, tris, pts, cols = realize(a, coll, Matrix.Identity(4))
    att = {k: att_json(p, l, u, at) for k, (p, l, u, at) in sorted(a.att.items())}
    bpy.ops.object.select_all(action='DESELECT')
    for ob in coll.objects:
        ob.select_set(not ob.name.endswith("_Col"))
    path = os.path.join(OUT, CATEGORY + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_normals=True, export_tangents=False,
                              export_materials='EXPORT', export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, CATEGORY + ".blend"))
    check = glb_check(path)
    manifest = {"category": CATEGORY, "glb": CATEGORY + ".glb", "generator": "training_centre_v2.py", "seed": SEED,
                "units": "studs", "axes": "Roblox (x, y, z) = Blender (x, z, -y); hall space, origin = hall floor centre",
                "hallOrigin": [8800.0, 200.0, 3000.0], "deckHeight": DECK_H, "glbCheck": check,
                "import": "Upload once as LS_TrainingCentre_v2 (Model). Record its id in art/manifests/"
                          "TrainingCentreV2.assetIds.json as {\"model\": {\"assetId\": <id>}} and re-run this script "
                          "(or set TrainingCentreDressData.assetId): TrainingCentreBuilder then places these meshes "
                          "like the v1 set's (hall * centre * turned 180 about Y, coloured from the roles).",
                "assets": [{"name": a.name, "notes": a.notes, "tris": tris, "parts": parts, "colliders": cols,
                            "attachments": att, "extra": a.extra}]}
    with open(os.path.join(OUT, CATEGORY + ".manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    prims = {role: mb.prims for role, mb in a.parts.items() if mb.prims and role != "Chequer"}
    npr = sum(len(v) for v in prims.values())
    # the builder's data
    ids_path = os.path.join(REPO, "art", "manifests", CATEGORY + ".assetIds.json")
    asset_id = None
    if os.path.exists(ids_path):
        with open(ids_path, encoding="utf-8") as fh:
            asset_id = (json.load(fh).get("model") or {}).get("assetId")
    roles = {}
    for p in parts:
        r = {"n": p["name"], "m": p["robloxMaterial"], "c": p["rgb"], "p": p["center"]}
        if p["transparency"]:
            r["t"] = p["transparency"]
        if not p["castShadow"]:
            r["sh"] = False
        roles[p["role"]] = r
    lcols = []
    for c in cols:
        d = {"n": c["name"], "p": c["center"], "s": c["size"]}
        if c["yawDeg"]:
            d["yaw"] = c["yawDeg"]
        lcols.append(d)
    latt = {}
    for k, v in att.items():
        d = {"p": v["position"], "l": v["look"], "u": v["up"]}
        if v.get("attributes"):
            d["at"] = v["attributes"]
        latt[k] = d
    lines = []
    w = lines.append
    w("-- GENERATED by art/blender/training_centre_v2.py (wave 27 look pass). Do not edit; re-run the generator.")
    w("-- Hall space (Roblox axes, studs), placed at the hall origin. Read by TrainingCentreBuilder (buildDress).")
    w("local D = {}")
    w("D.assetId = %s -- the TrainingCentreV2.glb upload (nil: the Part build below)" % (num(asset_id) if asset_id else "nil"))
    w("D.deckHeight = %s -- = TrainingStations.DeckHeight" % num(DECK_H))
    w("D.glb = %s" % lua({k: check[k] for k in ("bytes", "meshes", "triangles")}))
    w("D.assets = {}")
    w("D.assets[\"TC_Dress\"] = {")
    w("  kind = \"Hall\", tris = %d," % tris)
    w("  placements = {{name=\"TC_Dress\",p={0,0,0},yaw=0}},")
    w("  roles = %s," % lua(roles))
    w("  colliders = %s," % lua(lcols))
    w("  attachments = %s," % lua(latt))
    w("  prims = {")
    for role, rows in prims.items():
        w("    [%s] = {%s}," % (json.dumps(role), ",".join(lua(r) for r in rows)))
    w("  },")
    w("}")
    w("D.order = {\"TC_Dress\"}")
    w("return D")
    with open(LUA_OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    log("TC_Dress tris %d parts %d cols %d att %d prims %d" % (tris, len(parts), len(cols), len(att), npr))
    log("EXPORTED", path, check)
    log("WROTE", LUA_OUT)


main()
