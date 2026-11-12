"""br_cabin.py - HunterCabin (BuildingsReal): an old trapper's log cabin deep in the woods.

Saddle-notched round logs (weathered, bark remnants) with lime chinking in the gaps, half-log sills on a fieldstone
foundation, a 40 degree cedar-shake roof on log purlins (mossier on the back slope and at the eaves), the front
slope carried on over a small porch, a fieldstone chimney with a working fireplace on the east gable, one plank door
(4 x 7.5 opening, open inward), two small four-pane windows (dirty glass, one board shutter), a sleeping loft over
the west third (floor top 10.9) reached by a pole ladder, and a simple interior (table, bench, bunk, shelves).

Footprint ~25.6 x 21 including the eaves and the porch. Front = +Y, ridge along X, base centre on z = 0.
"""
import math
import random

from mathutils import Vector as V

import br_kit as K

TAU = 2.0 * math.pi
HX, HY = 10.5, 7.0              # wall-log centre lines
R = 0.5                         # mean wall-log radius
S = 1.12                        # course spacing (0.12 gaps are chinked)
Z_S0 = 0.9                      # first course of the gable (side) walls
Z_F0 = Z_S0 + S / 2             # first course of the front / back walls (half-course stagger)
N_COURSE = 10
FLOOR = 1.0
LOFT = 10.9
LOFT_EDGE = -3.0
PITCH = 40.0
TP = math.tan(math.radians(PITCH))
CP, SP = math.cos(math.radians(PITCH)), math.sin(math.radians(PITCH))
PLATE_TOP = Z_F0 + (N_COURSE - 1) * S + R
ZR = PLATE_TOP + HY * TP        # roof underside at the ridge
EAVE_F, EAVE_B = 12.0, -8.6     # roof edges (front slope runs on over the porch)
ROOF_X0, ROOF_X1 = -12.6, 11.35  # gable overhangs (short on the east so the chimney stands clear)
SLAB = 0.22
DOOR = (-2.0, 2.0)
WIN_F = (-7.6, -5.0)
WIN_B = (3.7, 6.3)
WIN_Z = (4.5, 7.38)             # opening between course 2 (top 4.2 + sill) and course 6 (bottom 7.68)
HEARTH_Y = (-1.5, 1.5)
HEARTH_Z = (FLOOR, 4.5)
JAMB = 0.42
CH_X0, CH_X1 = HX + R, HX + R + 2.8     # chimney base (firebox block)
CH_Y = 2.1
ST_X0, ST_X1, ST_Y = HX + R + 0.6, HX + R + 2.55, 1.0   # stack
MAS_Z0, MAS_T = 0.76, 1.4       # masonry course grid (strip height 1.4)


def z_roof(y):
    """Roof underside height above a point at distance |y| from the ridge."""
    return ZR - abs(y) * TP


def cut_intervals(a0, a1, cuts):
    out = [(a0, a1)]
    for (c0, c1) in cuts:
        nxt = []
        for (lo, hi) in out:
            if c1 <= lo or c0 >= hi:
                nxt.append((lo, hi))
                continue
            if c0 > lo:
                nxt.append((lo, c0))
            if c1 < hi:
                nxt.append((c1, hi))
        out = nxt
    return out


def oquad(mb, a, b, c, d, out, reg, rows=1, u0=0.0, v_span=(0.0, 1.0)):
    """quad_rows with automatic orientation: flips (a, b, c, d) -> (b, a, d, c) when it faces away from 'out'."""
    a, b, c, d = V(a), V(b), V(c), V(d)
    if (b - a).cross(d - a).dot(V(out)) < 0:
        a, b, c, d = b, a, d, c
    K.quad_rows(mb, a, b, c, d, reg, rows, u0, v_span)


def ends(rng):
    return K.R("Log", "end_%d" % rng.randrange(6))


# ------------------------------------------------------------------------------------------------ walls
def wall(mb, chk, axis, c, zs, half, openings, rng, limit=None, ext=(0.85, 1.25), sill=False):
    """One log wall. axis 'x': logs along X at y = c; 'y': along Y at x = c. openings: (lo, hi, zl, zh) in wall
    coordinates. Adds the chinking strips between consecutive courses to chk. Returns the course list."""
    lw = K.R("Log", "log_wall")
    pole = K.R("Log", "pole")
    chink = K.R("Stone", "chinking")
    placed = []
    for ci, z in enumerate(zs):
        a0, a1 = -half - rng.uniform(*ext), half + rng.uniform(*ext)
        crown = [True, True]
        if limit is not None:
            lim = limit(z)
            if lim < 0.7:
                continue
            if -lim > a0:
                a0, crown[0] = -lim, False
            if lim < a1:
                a1, crown[1] = lim, False
        cuts = []
        for (lo, hi, zl, zh) in openings:
            if z + 0.9 * R > zl and z - 0.9 * R < zh:
                cuts.append((lo - JAMB * 0.5, hi + JAMB * 0.5))
        pieces = cut_intervals(a0, a1, cuts)
        rr = R * rng.uniform(0.95, 1.06)
        flip = ci % 2 == 1                     # alternate butt and top ends course by course
        for (lo, hi) in pieces:
            if hi - lo < 0.6:
                continue
            dz = rng.uniform(-0.025, 0.025)
            pa = (lo, c, z + dz) if axis == "x" else (c, lo, z + dz)
            pb = (hi, c, z - dz) if axis == "x" else (c, hi, z - dz)
            r0, r1 = (rr, rr * 0.93) if not flip else (rr * 0.93, rr)
            ch0 = 0.1 if (lo == a0 and crown[0]) else 0.0
            ch1 = 0.1 if (hi == a1 and crown[1]) else 0.0
            reg = lw if rng.random() > 0.2 else pole   # a few paler, smoother logs break up the wall
            K.log(mb, pa, pb, r0, r1, reg=reg, end_reg=(ends(rng), ends(rng)), segs=10, rings=3, rng=rng,
                  chamfer=(ch0, ch1), bow=rng.uniform(0.0, 0.06), oval=0.06, wob=0.03)
        placed.append((z, a0, a1, cuts))
    # chinking between consecutive courses (only where both courses exist and outside openings / beyond corners)
    for (z0, a00, a01, cut0), (z1, a10, a11, cut1) in zip(placed[:-1], placed[1:]):
        zc = (z0 + z1) / 2
        lo, hi = max(a00, a10, -half + R * 0.6), min(a01, a11, half - R * 0.6)
        cuts = [c_ for c_ in cut0 + cut1]
        for (p, q) in cut_intervals(lo, hi, cuts):
            if q - p < 0.3:
                continue
            if axis == "x":
                K.timber(chk, (p, c, zc), (q, c, zc), 0.36, R * 1.1, chink, chink, up=(0, 1, 0), ch=0.0, rng=rng)
            else:
                K.timber(chk, (c, p, zc), (c, q, zc), 0.36, R * 1.1, chink, chink, up=(1, 0, 0), ch=0.0, rng=rng)
    return placed


def half_sill(mb, y, rng):
    """Half-log sill under a front / back wall: flat face down on the foundation, bark-edged round top."""
    lw, bark = K.R("Log", "log_wall"), K.R("Log", "bark")
    n = 7
    r = 0.52
    sec = K.arc(0.0, 0.0, r, 0.0, math.pi, n, jit=0.02, rng=rng)
    sec[0] = (r, 0.02)
    sec[-1] = (-r, 0.02)
    em = [(lw, rng.uniform(0, 30), 1.0 - i / n, 1.0 - (i + 1) / n) for i in range(n)]
    em.append((bark, rng.uniform(0, 30), 1.0, 0.0))
    ext = rng.uniform(0.7, 1.0)
    K.extrude(mb, (-HX - ext, y, 0.42), (HX + ext, y, 0.42), sec, em,
              cap_map=(ends(rng), (0.0, 0.0), r * 1.02, rng.uniform(0, TAU)), rings=2, rng=rng, bow=0.0)


# ------------------------------------------------------------------------------------------------ masonry
def outline_rect(x0, x1, y0, y1, rng, step=0.9, jit=0.05):
    """CCW rectangle outline with intermediate points jittered across the side (rubble masonry silhouette)."""
    pts = []
    for (p, q, n) in (((x0, y0), (x1, y0), (0, -1)), ((x1, y0), (x1, y1), (1, 0)), ((x1, y1), (x0, y1), (0, 1)),
                      ((x0, y1), (x0, y0), (-1, 0))):
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        k = max(1, int(round(L / step)))
        for i in range(k):
            t = i / k
            j = rng.uniform(-jit, jit) if i > 0 else rng.uniform(-jit, jit) * 0.5
            pts.append((p[0] + (q[0] - p[0]) * t + n[0] * j, p[1] + (q[1] - p[1]) * t + n[1] * j))
    return pts


def outline_notch(x0, x1, y0, y1, nx, ny0, ny1, rng, step=0.9, jit=0.05):
    """CCW outline of the chimney base with the firebox notch opening to -X (x0 side)."""
    pts = []
    segs = [((x0, y0), (x1, y0), (0, -1)), ((x1, y0), (x1, y1), (1, 0)), ((x1, y1), (x0, y1), (0, 1)),
            ((x0, y1), (x0, ny1), (-1, 0)), ((x0, ny1), (nx, ny1), (0, -1)), ((nx, ny1), (nx, ny0), (-1, 0)),
            ((nx, ny0), (x0, ny0), (0, 1)), ((x0, ny0), (x0, y0), (-1, 0))]
    for (p, q, n) in segs:
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        k = max(1, int(round(L / step)))
        for i in range(k):
            t = i / k
            j = rng.uniform(-jit, jit) if 0 < i else 0.0
            pts.append((p[0] + (q[0] - p[0]) * t + n[0] * j, p[1] + (q[1] - p[1]) * t + n[1] * j))
    return pts


def mband(mb, lo_pts, hi_pts, z0, z1, reg, u_off, bottom=False, top=False, cap_reg=None, grid=(MAS_Z0, MAS_T)):
    """Masonry course between z0 and z1 (lo_pts / hi_pts: CCW outlines with equal point counts; hi may differ
    for a battered shoulder). V follows the global course grid so stacked bands continue the stone pattern."""
    g0, gt = grid
    base = math.floor((z0 - g0) / gt + 1e-6)

    def vz(z):
        return max(0.0, min(1.0, (z - g0) / gt - base))
    n = len(lo_pts)
    lo = [mb.v((x, y, z0)) for (x, y) in lo_pts]
    hi = [mb.v((x, y, z1)) for (x, y) in hi_pts]
    s = u_off
    for i in range(n):
        j = (i + 1) % n
        L = math.hypot(lo_pts[j][0] - lo_pts[i][0], lo_pts[j][1] - lo_pts[i][1])
        mb.f((lo[i], lo[j], hi[j], hi[i]), [K.suv(reg, s, vz(z0)), K.suv(reg, s + L, vz(z0)),
                                            K.suv(reg, s + L, vz(z1)), K.suv(reg, s, vz(z1))], reg)
        s += L
    cr = cap_reg or reg
    if top:
        mb.f(hi, [K.box_uv_face(cr, V((0, 0, 1)), mb.co[k], V((0, 0, 0)), 1.0, (-3, 3)) for k in hi], cr)
    if bottom:
        mb.f(list(reversed(lo)), [K.box_uv_face(cr, V((0, 0, -1)), mb.co[k], V((0, 0, 0)), 1.0, (-3, 3))
                                  for k in reversed(lo)], cr)


def grid_cuts(z0, z1, extra=()):
    zs = set([z0, z1] + [z for z in extra if z0 < z < z1])
    k = math.ceil((z0 - MAS_Z0) / MAS_T)
    while True:
        z = MAS_Z0 + k * MAS_T
        if z >= z1 - 1e-6:
            break
        if z > z0 + 1e-6:
            zs.add(z)
        k += 1
    zs = sorted(zs)
    return list(zip(zs[:-1], zs[1:]))


# ------------------------------------------------------------------------------------------------ build
def build(lib):
    rng = random.Random(5101)
    root = lib.begin("HunterCabin", kind="Building", tags=["Enterable", "Woodland", "Loft"],
                     notes="Trapper's log cabin. Door (4 x 7.5 opening) centre front (+Y) under a porch; windows "
                           "front-left and back-right; fireplace in the east gable (Hearth attachment); loft over "
                           "the west third, floor top 10.9, reached by a pole ladder: place a 2x10x2 TrussPart "
                           "(Transparency 1) from LadderBase up to LadderTop (the ladder mesh is visual only). "
                           "Roof slabs are Hull; shakes, trim, glass, ropes and furniture details do not collide.")
    lw = K.R("Log", "log_wall")
    pole, bark = K.R("Log", "pole"), K.R("Log", "bark")
    zs_fb = [Z_F0 + k * S for k in range(N_COURSE)]
    zs_side = [Z_S0 + k * S for k in range(N_COURSE + 6)]

    def gable_limit(z):
        return (ZR - (z + R) + 0.02) / TP

    # ------------------------------------------------ log walls + chinking
    chk = K.MB("Stone")
    door_open = (DOOR[0], DOOR[1], FLOOR, zs_fb[6] + R)
    winf = (WIN_F[0], WIN_F[1], WIN_Z[0] - 0.3, WIN_Z[1] + 0.3)
    winb = (WIN_B[0], WIN_B[1], WIN_Z[0] - 0.3, WIN_Z[1] + 0.3)
    hearth = (HEARTH_Y[0], HEARTH_Y[1], HEARTH_Z[0] - 0.6, HEARTH_Z[1] + 0.1)
    front = K.MB("Log")
    half_sill(front, HY, rng)
    wall(front, chk, "x", HY, zs_fb, HX, [door_open, winf], rng)
    back = K.MB("Log")
    half_sill(back, -HY, rng)
    wall(back, chk, "x", -HY, zs_fb, HX, [winb], rng)
    west = K.MB("Log")
    wall(west, chk, "y", -HX, zs_side, HY, [], rng, limit=gable_limit)
    east = K.MB("Log")
    wall(east, chk, "y", HX, zs_side, HY, [hearth], rng, limit=gable_limit)
    K.part(lib, root, front, "Logs", collision="PreciseConvexDecomposition", smooth_angle=60,
           notes="Front wall (door + window openings).")
    K.part(lib, root, back, "Logs", collision="PreciseConvexDecomposition", smooth_angle=60,
           notes="Back wall (window opening).")
    K.part(lib, root, west, "Logs", collision="Hull", smooth_angle=60, notes="West gable wall.")
    K.part(lib, root, east, "Logs", collision="Hull", smooth_angle=60,
           notes="East gable wall (fireplace opening; Hull closes the shallow firebox).")

    # ------------------------------------------------ roof frame: ridge log, purlins, loft beam + joists, porch beam
    beams = K.MB("Log")
    for (y, r) in ((0.0, 0.42), (-3.6, 0.36), (3.6, 0.36)):
        zc = z_roof(y) - r / CP + 0.03
        K.log(beams, (ROOF_X0 + 0.15, y, zc), (ROOF_X1 + (0.12 if y == 0.0 else 0.25), y, zc), r, r * 0.9, reg=lw,
              end_reg=(ends(rng), ends(rng)), segs=10, rings=3, rng=rng, chamfer=(0.08, 0.08), bow=0.03)
    K.log(beams, (LOFT_EDGE - 0.3, -HY - 0.3, LOFT - 0.3 - 0.42), (LOFT_EDGE - 0.3, HY + 0.3, LOFT - 0.3 - 0.42), 0.42,
          0.4, reg=lw, end_reg=(ends(rng), ends(rng)), segs=10, rings=3, rng=rng, bow=0.03)
    for y in (-4.6, -1.6, 1.6, 4.6):
        K.log(beams, (-HX - 0.1, y, LOFT - 0.3 - 0.22), (LOFT_EDGE - 0.1, y, LOFT - 0.3 - 0.22), 0.22, 0.2, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=8, rings=2, rng=rng)
    y_pb = 11.1
    zpb = z_roof(y_pb) - 0.4 / CP
    K.log(beams, (-8.3, y_pb, zpb), (8.3, y_pb, zpb), 0.4, 0.37, reg=lw, end_reg=(ends(rng), ends(rng)), segs=10,
          rings=3, rng=rng, chamfer=(0.08, 0.08), bow=0.04)
    K.part(lib, root, beams, "Logs", collide=False, smooth_angle=60,
           notes="Ridge log, purlins, loft beam and joists, porch beam (visual; the roof slabs carry the collision).")

    # ------------------------------------------------ porch: deck, rim log on stone piers, posts, braces, step
    deck = K.MB("Wood")
    bd = K.R("Wood", "board_grey")
    y_d0, y_d1 = HY + R + 0.03, 11.45
    cx, cy = 0.0, (y_d0 + y_d1) / 2
    hl = (y_d1 - y_d0) / 2
    K.board_box(deck, (cx - hl, cy - 7.6, 0.76), (cx + hl, cy + 7.6, FLOOR), bd, board=0.74, rz=math.pi / 2,
                c=(cx, cy, 0.0), rng=rng, z_rows=1)
    K.part(lib, root, deck, "Planks", collision="Box", tags=["Floor"], smooth_angle=30, notes="Porch deck.")
    porch = K.MB("Log")
    K.log(porch, (-7.9, y_d1 - 0.3, 0.5), (7.9, y_d1 - 0.3, 0.5), 0.3, 0.28, reg=lw, end_reg=(ends(rng), ends(rng)),
          segs=8, rings=2, rng=rng)
    post_x = (-7.0, -2.6, 2.6, 7.0)
    for x in post_x:
        K.log(porch, (x, y_pb, FLOOR - 0.05), (x + rng.uniform(-0.04, 0.04), y_pb + rng.uniform(-0.04, 0.04), zpb - 0.3),
              0.3, 0.27, reg=pole, end_reg=(ends(rng), ends(rng)), segs=9, rings=3, rng=rng, up=(1, 0, 0), bow=0.03)
    K.part(lib, root, porch, "Logs", collision="PreciseConvexDecomposition", smooth_angle=60,
           notes="Porch posts and rim log.")
    step = K.MB("Log")
    n = 6
    rs = 0.5
    sec = K.arc(0.0, 0.0, rs, math.pi, TAU, n, jit=0.02, rng=rng)
    sec[0], sec[-1] = (-rs, 0.0), (rs, 0.0)
    em = [(bark, rng.uniform(0, 30), 1.0 - i / n, 1.0 - (i + 1) / n) for i in range(n)]
    em.append((K.R("Log", "pole"), rng.uniform(0, 30), 1.0, 0.0))
    K.extrude(step, (-2.4, y_d1 + 0.55, 0.5), (2.4, y_d1 + 0.55, 0.5), sec, em,
              cap_map=(ends(rng), (0.0, 0.0), rs * 1.02, rng.uniform(0, TAU)), rings=2, rng=rng)
    K.part(lib, root, step, "Logs", collision="Hull", smooth_angle=55, notes="Half-log porch step (top 0.5).")

    # ------------------------------------------------ floors
    fl = K.MB("Wood")
    K.board_box(fl, (-HX + R - 0.05, -HY + R - 0.05, 0.6), (HX - R + 0.05, HY - R + 0.05, FLOOR),
                K.R("Wood", "board_brown"), board=0.74, rng=rng, z_rows=1)
    K.part(lib, root, fl, "Planks", collision="Box", tags=["Floor"], smooth_angle=30, notes="Cabin floor (top 1.0).")
    loft = K.MB("Wood")
    K.board_box(loft, (-HX + R - 0.05, -HY + R - 0.05, LOFT - 0.3), (LOFT_EDGE, HY - R + 0.05, LOFT),
                K.R("Wood", "board_grey"), board=0.74, rng=rng, z_rows=1)
    K.part(lib, root, loft, "Planks", collision="Box", tags=["Floor"], smooth_angle=30,
           notes="Loft floor (top 10.9).")

    # ------------------------------------------------ roof: board slabs (collision), shakes, ridge + barge boards
    shake = K.MB("Shake")
    trim = K.MB("Wood")
    rb = K.R("Wood", "board_grey")
    for side, y_e in ((1, EAVE_F), (-1, EAVE_B)):
        slab = K.MB("Wood")
        ye = abs(y_e)
        nrm = V((0, side * SP, CP))
        down = V((0, side * CP, -SP))
        A = V((ROOF_X0, 0.0, ZR))
        B = V((ROOF_X1, 0.0, ZR))
        C = V((ROOF_X1, side * ye, z_roof(ye)))
        D = V((ROOF_X0, side * ye, z_roof(ye)))
        T = nrm * SLAB
        L_s = ye / CP
        # underside: boards running down the slope (rows along X), seen from below
        oquad(slab, A, D, C, B, -nrm, K.R("Wood", "board_grey"), rows=max(1, int(round((ROOF_X1 - ROOF_X0) / 0.74))),
              u0=rng.uniform(0, 30))
        oquad(slab, A + T, B + T, C + T, D + T, nrm, K.R("Wood", "board_damp"), rows=1)
        oquad(slab, D, C, C + T, D + T, down, rb, rows=1, v_span=(0.0, 0.3))
        oquad(slab, A, B, B + T, A + T, -down, rb, rows=1, v_span=(0.0, 0.3))
        oquad(slab, A, D, D + T, A + T, V((-1, 0, 0)), rb, rows=1, v_span=(0.0, 0.3))
        oquad(slab, B, C, C + T, B + T, V((1, 0, 0)), rb, rows=1, v_span=(0.0, 0.3))
        K.part(lib, root, slab, "Planks", collision="Hull", smooth_angle=20,
               notes="%s roof boards (Hull: walk-on roof, arrows stop on it)." % ("Front" if side > 0 else "Back"))
        # cedar shake courses from the eave up to the ridge
        O = V((0.0, 0.0, ZR)) + T
        expo = 0.75
        k = 0
        d = L_s + 0.12
        while d > 0.05:
            frac = d / L_s
            if side > 0:
                idx = int(round(0.6 + 2.6 * frac ** 2 + rng.uniform(-0.8, 0.8)))
            else:
                idx = int(round(2.4 + 3.6 * frac + rng.uniform(-0.8, 0.8)))
            idx = max(0, min(6, idx))
            reg = K.R("Shake", "course_%d" % idx)
            ph = rng.uniform(0, TAU)

            def warp(a, dd, ph=ph):
                sag = 0.07 * math.sin(math.pi * min(1.0, max(0.0, dd / L_s)))
                return (0.025 * math.sin(a * 0.9 + ph) + 0.015 * math.sin(a * 2.7 + 2 * ph) - sag
                        + 0.02 * math.sin(dd * 1.7 + a * 0.3))
            K.course(shake, O, (1, 0, 0), down, nrm, ROOF_X0 - 0.06, ROOF_X1 + 0.06, d, min(expo, d), 0.11, reg,
                     K.R("Shake", "butt"), rng.uniform(0, 40), nu=6, warp=warp)
            d -= expo
            k += 1
        # barge boards along the gable edges
        for x in (ROOF_X0 - 0.07, ROOF_X1 + 0.07):
            p0 = V((x, 0.0, ZR)) + nrm * 0.1
            p1 = V((x, side * ye, z_roof(ye))) + nrm * 0.1
            K.timber(trim, p0, p1, 0.62, 0.12, rb, K.R("Wood", "end_sq_4"), up=(1, 0, 0), ch=0.025, rng=rng, ext=0.12)
        # ridge board on this slope
        K.timber(trim, V((ROOF_X0 - 0.15, 0, ZR)) + T + nrm * 0.16 + down * 0.3,
                 V((ROOF_X1 + 0.15, 0, ZR)) + T + nrm * 0.16 + down * 0.3, 0.68, 0.1, rb, K.R("Wood", "end_sq_1"),
                 up=nrm, ch=0.02, rng=rng)
    K.part(lib, root, shake, "Shingles", collide=False, smooth_angle=25,
           notes="Hand-split cedar shakes (moss heavier on the back slope and at the eaves).")

    # ------------------------------------------------ door: frame, threshold, plank leaf open inward, iron
    yb, yt = HY - R - 0.06, HY + R + 0.06
    wt = yt - yb
    beam = K.R("Wood", "beam")
    z_head = zs_fb[7] - R
    for x in (DOOR[0] - JAMB / 2, DOOR[1] + JAMB / 2):
        K.timber(trim, (x, HY, FLOOR - 0.02), (x, HY, z_head + 0.02), wt, JAMB, beam, K.R("Wood", "end_sq_0"),
                 up=(1, 0, 0), ch=0.03, rng=rng)
    K.timber(trim, (DOOR[0] - JAMB, HY, FLOOR + 7.5 + (z_head - FLOOR - 7.5) / 2),
             (DOOR[1] + JAMB, HY, FLOOR + 7.5 + (z_head - FLOOR - 7.5) / 2), wt, z_head - FLOOR - 7.5, beam,
             K.R("Wood", "end_sq_2"), up=(0, 0, 1), ch=0.03, rng=rng)
    K.timber(trim, (DOOR[0] - 0.1, HY, FLOOR - 0.05), (DOOR[1] + 0.1, HY, FLOOR - 0.05), wt + 0.2, 0.14,
             K.R("Wood", "board_damp"), K.R("Wood", "end_sq_3"), up=(0, 0, 1), ch=0.02, rng=rng)
    # window frames
    for (x0, x1, y_w, nrm_y) in ((WIN_F[0], WIN_F[1], HY, 1), (WIN_B[0], WIN_B[1], -HY, -1)):
        zl, zh = WIN_Z
        for x in (x0 - JAMB / 2, x1 + JAMB / 2):
            K.timber(trim, (x, y_w, zl - 0.3), (x, y_w, zh + 0.3), 2 * R + 0.1, JAMB, beam, K.R("Wood", "end_sq_5"),
                     up=(1, 0, 0), ch=0.03, rng=rng)
        K.timber(trim, (x0 - JAMB, y_w, zl - 0.15), (x1 + JAMB, y_w, zl - 0.15), 2 * R + 0.3, 0.3, beam,
                 K.R("Wood", "end_sq_6"), up=(0, 0, 1), ch=0.03, rng=rng)
        K.timber(trim, (x0 - JAMB, y_w, zh + 0.15), (x1 + JAMB, y_w, zh + 0.15), 2 * R + 0.1, 0.3, beam,
                 K.R("Wood", "end_sq_7"), up=(0, 0, 1), ch=0.03, rng=rng)
        # four-pane sash (muntins) in the wall's mid plane
        sash = K.R("Wood", "board_damp")
        ym = y_w
        for x in (x0 + 0.06, (x0 + x1) / 2, x1 - 0.06):
            K.timber(trim, (x, ym, zl), (x, ym, zh), 0.16, 0.12 if x != (x0 + x1) / 2 else 0.09, sash, sash,
                     up=(1, 0, 0), ch=0.01, rng=rng)
        for z in (zl + 0.06, (zl + zh) / 2, zh - 0.06):
            K.timber(trim, (x0, ym, z), (x1, ym, z), 0.16, 0.12 if z != (zl + zh) / 2 else 0.09, sash, sash,
                     up=(0, 0, 1), ch=0.01, rng=rng)
    # front window shutter: three boards on two battens, hinged on the left jamb, swung open against the wall
    hx, hy = WIN_F[0] - JAMB, HY + R + 0.12
    ang = math.radians(rng.uniform(150, 165))
    dvec = V((math.cos(ang), math.sin(ang) * 0.0 + 0.0, 0.0))
    dvec = V((-math.cos(math.pi - ang), math.sin(math.pi - ang), 0.0))
    for i in range(3):
        o = 0.12 + 0.9 * i
        p = V((hx, hy, 0)) + dvec * (o + 0.42)
        K.timber(trim, (p.x, p.y, WIN_Z[0] - 0.25), (p.x, p.y, WIN_Z[1] + 0.25), 0.86, 0.12,
                 K.R("Wood", "board_silver"), K.R("Wood", "end_sq_3"), up=(-dvec.y, dvec.x, 0), ch=0.02, rng=rng)
    for z in (WIN_Z[0] + 0.3, WIN_Z[1] - 0.3):
        p0 = V((hx, hy, z)) + dvec * 0.12 + V((-dvec.y, dvec.x, 0)) * 0.12
        p1 = V((hx, hy, z)) + dvec * 2.7 + V((-dvec.y, dvec.x, 0)) * 0.12
        K.timber(trim, p0, p1, 0.32, 0.1, K.R("Wood", "board_grey"), K.R("Wood", "end_sq_1"), up=(-dvec.y, dvec.x, 0),
                 ch=0.02, rng=rng)
    # fireplace mantel (lintel timber + shelf) on the inside of the east wall
    K.timber(trim, (HX - 0.2, HEARTH_Y[0] - 0.7, HEARTH_Z[1] + 0.2), (HX - 0.2, HEARTH_Y[1] + 0.7, HEARTH_Z[1] + 0.2),
             2 * R + 0.4, 0.4, beam, K.R("Wood", "end_sq_2"), up=(0, 0, 1), ch=0.04, rng=rng)
    K.timber(trim, (HX - R - 0.35, HEARTH_Y[0] - 0.9, HEARTH_Z[1] + 0.47), (HX - R - 0.35, HEARTH_Y[1] + 0.9,
             HEARTH_Z[1] + 0.47), 0.75, 0.14, K.R("Wood", "board_brown"), K.R("Wood", "end_sq_6"), up=(0, 0, 1),
             ch=0.02, rng=rng)
    K.part(lib, root, trim, "Wood", collide=False, smooth_angle=30,
           notes="Door / window frames, sashes, shutter, mantel, barge and ridge boards (visual).")

    door = K.MB("Wood")
    hinge = V((DOOR[1] - 0.05, HY - R - 0.2, 0))
    phi = math.radians(172)          # swung right round against the inside of the front wall
    dd = V((-math.cos(phi), -math.sin(phi), 0))
    nd = V((-dd.y, dd.x, 0))          # inside-face normal (closed: -Y)
    for i in range(5):
        p = hinge + dd * (0.05 + 0.39 + 0.79 * i)
        K.timber(door, (p.x, p.y, FLOOR + 0.06), (p.x, p.y, FLOOR + 7.42), 0.77, 0.16,
                 K.R("Wood", "board_damp" if i % 2 else "board_grey"), K.R("Wood", "end_sq_%d" % i), up=nd, ch=0.02,
                 rng=rng)
    # ledges + Z braces on the door's inside face (nd = its normal; now turned toward the wall)
    for z in (FLOOR + 1.0, FLOOR + 3.8, FLOOR + 6.5):
        p0 = hinge + dd * 0.3 + nd * 0.16
        p1 = hinge + dd * 3.7 + nd * 0.16
        K.timber(door, (p0.x, p0.y, z), (p1.x, p1.y, z), 0.5, 0.14, K.R("Wood", "board_grey"), K.R("Wood", "end_sq_7"),
                 up=nd, ch=0.02, rng=rng)
    pa = hinge + dd * 0.5 + nd * 0.16
    pb = hinge + dd * 3.5 + nd * 0.16
    K.timber(door, (pa.x, pa.y, FLOOR + 1.3), (pb.x, pb.y, FLOOR + 3.5), 0.45, 0.12, K.R("Wood", "board_grey"),
             K.R("Wood", "end_sq_7"), up=nd, ch=0.02, rng=rng)
    K.timber(door, (pa.x, pa.y, FLOOR + 4.1), (pb.x, pb.y, FLOOR + 6.2), 0.45, 0.12, K.R("Wood", "board_grey"),
             K.R("Wood", "end_sq_7"), up=nd, ch=0.02, rng=rng)
    K.part(lib, root, door, "Planks", collide=False, smooth_angle=30,
           notes="Plank door swung open inward flat against the front wall (visual; never blocks the doorway).")

    # ------------------------------------------------ glass
    gl = K.MB("Kit")
    greg = K.R("Kit", "glass")
    for (x0, x1, y_w) in ((WIN_F[0], WIN_F[1], HY), (WIN_B[0], WIN_B[1], -HY)):
        zl, zh = WIN_Z
        xm, zm = (x0 + x1) / 2, (zl + zh) / 2
        for (a0, a1) in ((x0 + 0.1, xm - 0.04), (xm + 0.04, x1 - 0.1)):
            for (b0, b1) in ((zl + 0.1, zm - 0.04), (zm + 0.04, zh - 0.1)):
                K.box_solid(gl, (a0, y_w - 0.02, b0), (a1, y_w + 0.02, b1), greg, origin=(a0, y_w - 0.02, b0),
                            vext=(0.0, b1 - b0), u_shift=0.0)
    K.part(lib, root, gl, "Glass", collide=False, cast_shadow=False, variant="Glass", smooth_angle=10,
           notes="Dirty window glass: AlphaMode Transparency, MeshPart.Transparency 0.1-0.3 (blended).")

    # ------------------------------------------------ stone: foundation (Box), chimney (Hull), hearth + piers
    found = K.MB("Stone")
    foot = K.R("Stone", "masonry_foot")
    for (x0, x1, y0, y1) in ((-HX - 0.75, HX + 0.75, HY - 0.6, HY + 0.6), (-HX - 0.75, HX + 0.75, -HY - 0.6, -HY + 0.6),
                             (-HX - 0.6, -HX + 0.6, -HY + 0.6, HY - 0.6), (HX - 0.6, HX + 0.6, -HY + 0.6, HY - 0.6)):
        o = outline_rect(x0, x1, y0, y1, rng, step=1.1, jit=0.05)
        mband(found, o, o, -0.04, 0.42, foot, rng.uniform(0, 30), bottom=False, top=True, grid=(-0.04, 0.76))
    K.part(lib, root, found, "Stone", collision="Box", smooth_angle=20, notes="Fieldstone foundation under the walls.")

    chim = K.MB("Stone")
    mas = K.R("Stone", "masonry")
    rk = K.R("Stone", "rock")
    nx = CH_X0 + 1.5
    base_rect = outline_rect(CH_X0, CH_X1, -CH_Y, CH_Y, rng, step=0.9, jit=0.06)
    o_notch = outline_notch(CH_X0, CH_X1, -CH_Y, CH_Y, nx, HEARTH_Y[0], HEARTH_Y[1], rng, step=0.9, jit=0.05)
    z_sh = 7.0
    first = True
    for (z0, z1) in [(-0.04, MAS_Z0)] + grid_cuts(MAS_Z0, z_sh, extra=(HEARTH_Z[0], HEARTH_Z[1])):
        notch = HEARTH_Z[0] - 1e-6 <= z0 and z1 <= HEARTH_Z[1] + 1e-6
        o = o_notch if notch else outline_rect(CH_X0, CH_X1, -CH_Y, CH_Y, rng, step=0.9, jit=0.06)
        reg = foot if z0 < MAS_Z0 - 1e-6 else mas
        grid = (-0.04, 0.76) if reg is foot else (MAS_Z0, MAS_T)
        cap_b = abs(z0 - HEARTH_Z[1]) < 1e-6
        mband(chim, o, o, z0, z1, reg, rng.uniform(0, 30), bottom=cap_b, top=True,
              cap_reg=K.R("Stone", "rock_burnt") if cap_b else K.R("Stone", "masonry"), grid=grid)
        first = False
    # battered shoulder up to the stack, then the stack to above the ridge
    z_s1 = z_sh + 1.2
    sh_lo = outline_rect(CH_X0, CH_X1, -CH_Y, CH_Y, rng, step=0.9, jit=0.0)
    n_lo = len(sh_lo)
    stack0 = outline_rect(ST_X0, ST_X1, -ST_Y, ST_Y, rng, step=0.9, jit=0.0)
    # resample the stack outline to the base outline's point count (same side split)
    sh_hi = []
    for (x, y) in sh_lo:
        tx = (x - CH_X0) / (CH_X1 - CH_X0)
        ty = (y + CH_Y) / (2 * CH_Y)
        sh_hi.append((ST_X0 + tx * (ST_X1 - ST_X0), -ST_Y + ty * 2 * ST_Y))
    mband(chim, sh_lo, sh_hi, z_sh, z_s1, mas, rng.uniform(0, 30), top=True, grid=(MAS_Z0, MAS_T))
    z_top = ZR + SLAB + 2.6
    for (z0, z1) in grid_cuts(z_s1, z_top):
        o = outline_rect(ST_X0, ST_X1, -ST_Y, ST_Y, rng, step=0.8, jit=0.05)
        mband(chim, o, o, z0, z1, mas, rng.uniform(0, 30), top=True, grid=(MAS_Z0, MAS_T))
    # cap stone + flue liner
    cap = V(((ST_X0 + ST_X1) / 2, 0.0, z_top))
    K.box_solid(chim, (ST_X0 - 0.22, -ST_Y - 0.2, z_top), (ST_X1 + 0.22, ST_Y + 0.2, z_top + 0.28), rk, jit=0.03,
                rng=rng)
    flue = outline_rect(cap.x - 0.42, cap.x + 0.42, -0.36, 0.36, rng, step=0.9, jit=0.0)
    flue_in = [(x, y) for (x, y) in reversed(flue)]
    mband(chim, flue, flue, z_top + 0.28, z_top + 0.62, K.R("Stone", "rock_burnt"), 0.0, top=True,
          cap_reg=K.R("Stone", "ash"), grid=(z_top, 0.63))
    K.part(lib, root, chim, "Stone", collision="Hull", smooth_angle=25,
           notes="Fieldstone chimney with the firebox opening into the cabin.")

    misc = K.MB("Stone")
    burnt = K.R("Stone", "rock_burnt")
    # soot liner inside the firebox (faces into the opening)
    y0f, y1f = HEARTH_Y[0] + 0.02, HEARTH_Y[1] - 0.02
    zf0, zf1 = HEARTH_Z[0] + 0.12, HEARTH_Z[1] - 0.02
    xb = nx - 0.02
    oquad(misc, (xb, y0f, zf0), (xb, y1f, zf0), (xb, y1f, zf1), (xb, y0f, zf1), V((-1, 0, 0)), burnt, rows=3)
    oquad(misc, (HX - R + 0.3, y0f, zf0), (xb, y0f, zf0), (xb, y0f, zf1), (HX - R + 0.3, y0f, zf1), V((0, 1, 0)), burnt,
          rows=3)
    oquad(misc, (HX - R + 0.3, y1f, zf0), (xb, y1f, zf0), (xb, y1f, zf1), (HX - R + 0.3, y1f, zf1), V((0, -1, 0)), burnt,
          rows=3)
    oquad(misc, (HX - R + 0.3, y0f, zf1), (xb, y0f, zf1), (xb, y1f, zf1), (HX - R + 0.3, y1f, zf1), V((0, 0, -1)), burnt,
          rows=2)
    # stone jambs either side of the fireplace opening (hide the cut log ends)
    for (ya, yb2) in ((HEARTH_Y[0] - 0.6, HEARTH_Y[0] + 0.02), (HEARTH_Y[1] - 0.02, HEARTH_Y[1] + 0.6)):
        K.box_solid(misc, (HX - R - 0.42, ya, FLOOR + 0.1), (HX - R + 0.3, yb2, HEARTH_Z[1] + 0.02), rk, jit=0.02,
                    rng=rng)
    # hearth slab in front of the fire, filling the cut sill course below it
    K.box_solid(misc, (HX - R - 1.5, HEARTH_Y[0] - 0.55, 0.42), (nx, HEARTH_Y[1] + 0.55, FLOOR + 0.1), rk, jit=0.02,
                rng=rng)
    # porch piers under the rim log
    for x in (-7.3, -2.6, 2.6, 7.3):
        K.rock(misc, (x, y_d1 - 0.3, -0.03), (0.95, 0.85, 0.42), rk, rng, subdiv=1, rough=0.3, facets=4)
    K.part(lib, root, [misc], "Stone", collide=False, smooth_angle=30,
           notes="Firebox soot liner, hearth slab, porch piers (visual).")
    K.part(lib, root, chk, "Stone", collide=False, cast_shadow=False, smooth_angle=20,
           notes="Lime chinking between the wall logs (visual).")

    # ------------------------------------------------ loft railing (two Box parts round the ladder gap) + ladder
    lad_x, lad_y = LOFT_EDGE + 1.0, -3.0
    for (ya, yb_) in ((-HY + R + 0.2, lad_y - 1.45), (lad_y + 1.45, HY - R - 0.2)):
        rail = K.MB("Log")
        npost = max(2, int(round((yb_ - ya) / 2.1)) + 1)
        # art direction: posts and rails stop 0.3 under the roof boards (near the eaves the full-height railing
        # poked up through the front roof slope as a visible triangle)
        for i in range(npost):
            y = ya + (yb_ - ya) * i / (npost - 1)
            top = min(LOFT + 2.85, z_roof(y) - 0.3)
            K.log(rail, (LOFT_EDGE - 0.17, y, LOFT - 0.05), (LOFT_EDGE - 0.17, y, top), 0.15, 0.13, reg=pole,
                  end_reg=ends(rng), segs=7, rings=2, rng=rng, up=(1, 0, 0), cap=(False, True))
        for z in (LOFT + 1.5, LOFT + 2.75):
            lim = (ZR - 0.3 - (z + 0.13)) / TP
            y0, y1 = max(ya - 0.1, -lim), min(yb_ + 0.1, lim)
            if y1 - y0 < 0.5:
                continue
            K.log(rail, (LOFT_EDGE - 0.17, y0, z), (LOFT_EDGE - 0.17, y1, z), 0.13, 0.12, reg=pole,
                  end_reg=(ends(rng), ends(rng)), segs=7, rings=2, rng=rng)
        K.part(lib, root, rail, "Logs", collision="Box", smooth_angle=60, notes="Loft railing.")
    lad = K.MB("Log")
    xb_, xt_ = lad_x + 0.35, lad_x - 0.3
    for dy in (-0.78, 0.78):
        K.log(lad, (xb_, lad_y + dy, FLOOR - 0.02), (xt_, lad_y + dy, LOFT + 1.15), 0.13, 0.11, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=7, rings=2, rng=rng, up=(1, 0, 0))
    k = 0
    z = FLOOR + 0.9
    while z < LOFT + 0.9:
        t = (z - FLOOR) / (LOFT + 1.15 - FLOOR)
        x = xb_ + (xt_ - xb_) * t
        K.log(lad, (x, lad_y - 0.92, z), (x, lad_y + 0.92, z + rng.uniform(-0.03, 0.03)), 0.075, 0.07, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=6, rings=2, rng=rng)
        z += 1.0
    K.part(lib, root, lad, "Logs", collide=False, tags=["LadderVisual"], smooth_angle=60,
           notes="Pole ladder (visual): the TrussPart between LadderBase and LadderTop does the climbing.")
    lib.attach(root, "LadderBase", (lad_x, lad_y, FLOOR), look=(-1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "LadderTop", (lad_x, lad_y, LOFT), look=(-1, 0, 0), up=(0, 0, 1))
    lib.attach(root, "Door", (0.0, HY, FLOOR), look=(0, 1, 0), up=(0, 0, 1))
    lib.attach(root, "Hearth", (HX + 0.3, 0.0, FLOOR + 0.15), look=(-1, 0, 0), up=(0, 0, 1))

    # ------------------------------------------------ furniture: table + bench (Box), bunk (Box), shelves, cloth, iron
    tab = K.MB("Wood")
    tx0, tx1, ty0, ty1, tz = -8.5, -4.3, 4.3, 6.35, FLOOR + 2.6
    K.board_box(tab, (tx0, ty0, tz - 0.16), (tx1, ty1, tz), K.R("Wood", "board_brown"), board=0.7, rng=rng, z_rows=1)
    for x in (tx0 + 0.45, tx1 - 0.45):
        for y in (ty0 + 0.3, ty1 - 0.3):
            K.timber(tab, (x, y, FLOOR - 0.02), (x, y, tz - 0.16), 0.28, 0.28, beam, K.R("Wood", "end_sq_3"),
                     up=(0, 1, 0), ch=0.03, rng=rng)
        K.timber(tab, (x, ty0 + 0.3, FLOOR + 0.6), (x, ty1 - 0.3, FLOOR + 0.6), 0.2, 0.16, beam, K.R("Wood", "end_sq_1"),
                 up=(0, 0, 1), ch=0.02, rng=rng)
    K.timber(tab, (tx0 + 0.45, (ty0 + ty1) / 2, FLOOR + 0.6), (tx1 - 0.45, (ty0 + ty1) / 2, FLOOR + 0.6), 0.2, 0.16, beam,
             K.R("Wood", "end_sq_2"), up=(0, 0, 1), ch=0.02, rng=rng)
    bz = FLOOR + 1.55
    K.board_box(tab, (tx0 + 0.4, 3.0, bz - 0.14), (tx1 - 0.4, 3.85, bz), K.R("Wood", "board_grey"), board=0.85, rng=rng,
                z_rows=1)
    for x in (tx0 + 0.8, tx1 - 0.8):
        K.timber(tab, (x, 3.42, FLOOR - 0.02), (x, 3.42, bz - 0.14), 0.7, 0.16, K.R("Wood", "board_grey"),
                 K.R("Wood", "end_sq_5"), up=(1, 0, 0), ch=0.02, rng=rng)
    K.part(lib, root, tab, "Planks", collision="Box", smooth_angle=30, notes="Table and bench.")

    bunk = K.MB("Log")
    bx0, bx1, by0, by1 = 3.4, 9.6, -HY + R + 0.05, -HY + R + 2.7
    for (x, y, h) in ((bx0, by0, 3.6), (bx0, by1, 3.6), (bx1, by0, 3.0), (bx1, by1, 3.0)):
        K.log(bunk, (x, y, FLOOR - 0.02), (x, y, FLOOR + h), 0.2, 0.18, reg=pole, end_reg=ends(rng), segs=8, rings=2,
              rng=rng, up=(1, 0, 0), cap=(False, True))
    for y in (by0, by1):
        K.log(bunk, (bx0 - 0.1, y, FLOOR + 1.15), (bx1 + 0.1, y, FLOOR + 1.15), 0.18, 0.17, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=8, rings=2, rng=rng)
    for x in (bx0, bx1):
        K.log(bunk, (x, by0 - 0.1, FLOOR + 1.15), (x, by1 + 0.1, FLOOR + 1.15), 0.17, 0.16, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=8, rings=2, rng=rng)
        K.log(bunk, (x, by0 - 0.1, FLOOR + 2.7), (x, by1 + 0.1, FLOOR + 2.7), 0.14, 0.13, reg=pole,
              end_reg=(ends(rng), ends(rng)), segs=7, rings=2, rng=rng)
    K.part(lib, root, bunk, "Logs", collision="Box", smooth_angle=60, notes="Pole bunk frame (Box).")

    cloth = K.MB("Kit")
    tk, bl = K.R("Kit", "ticking"), K.R("Kit", "blanket")
    mz = FLOOR + 1.35

    def mattress(a, b):
        x = bx0 + 0.15 + (bx1 - bx0 - 0.3) * b
        y = by0 + 0.15 + (by1 - by0 - 0.3) * (1 - a)
        z = mz + 0.22 + 0.06 * math.sin(math.pi * a) + 0.03 * math.sin(b * 11.0)
        return (x, y, z)
    K.sheet(cloth, mattress, 4, 8, 0.4, tk, lambda a, b: 0.05 + b * (tk["tile"][0] - 0.1),
            lambda a, b: 0.95 - 0.9 * a)

    def blanket(a, b):
        x = bx0 + 1.6 + (bx1 - bx0 - 1.75) * b
        y = by0 + 0.05 + (by1 - by0 - 0.1) * (1 - a)
        z = mz + 0.47 + 0.13 * math.sin(math.pi * a) ** 0.6 + 0.06 * math.sin(b * 7.0 + a * 4.0)
        if a < 0.08 or a > 0.92:
            z -= 0.3 * (min(a, 1 - a) < 0.08)
        return (x, y, z)
    K.sheet(cloth, blanket, 6, 8, 0.05, bl, lambda a, b: 0.05 + b * min(bl["tile"][0] - 0.1, 4.4),
            lambda a, b: 0.97 - 0.94 * a)
    K.part(lib, root, cloth, "Cloth", collide=False, smooth_angle=70, notes="Mattress and wool blanket on the bunk.")

    shelf = K.MB("Wood")
    for z in (FLOOR + 3.5, FLOOR + 4.7):
        K.board_box(shelf, (-HX + R - 0.02, -2.4, z - 0.12), (-HX + R + 0.75, 1.2, z), K.R("Wood", "board_grey"),
                    board=0.75, rng=rng, z_rows=1)
        for y in (-2.0, 0.8):
            K.timber(shelf, (-HX + R + 0.05, y, z - 0.6), (-HX + R + 0.6, y, z - 0.13), 0.14, 0.14, beam,
                     K.R("Wood", "end_sq_4"), up=(0, 1, 0), ch=0.01, rng=rng)
    K.board_box(shelf, (-HX + R + 0.08, 0.1, FLOOR + 4.7), (-HX + R + 0.7, 1.0, FLOOR + 5.25),
                K.R("Wood", "board_crate"), board=0.55, rng=rng)
    K.part(lib, root, shelf, "Wood", collide=False, smooth_angle=30, notes="Wall shelves and a small box.")

    iron = K.MB("Kit")
    treg, ireg, char = K.R("Kit", "tin"), K.R("Kit", "iron"), K.R("Kit", "char")
    for (y, h) in ((-1.9, 0.42), (-1.4, 0.36), (-0.85, 0.5)):
        K.lathe(iron, [(0.17, 0.0), (0.18, 0.02), (0.18, h - 0.02), (0.165, h)], 10, treg,
                c=(-HX + R + 0.4, y, FLOOR + 3.5))
    for z in (FLOOR + 2.0, FLOOR + 6.4):  # strap hinges on the door's outside face
        p0 = hinge + dd * 0.05 - nd * 0.09
        p1 = hinge + dd * 2.2 - nd * 0.09
        K.timber(iron, (p0.x, p0.y, z), (p1.x, p1.y, z), 0.24, 0.04, ireg, ireg, up=-nd, ch=0.0, rng=rng)
    K.log(iron, (nx - 0.6, -0.9, FLOOR + 0.35), (HX - R + 0.1, 0.7, FLOOR + 0.3), 0.2, 0.17, reg=char, segs=7, rings=2,
          rng=rng)
    K.log(iron, (nx - 0.5, 0.9, FLOOR + 0.3), (HX - R + 0.2, -0.6, FLOOR + 0.55), 0.18, 0.16, reg=char, segs=7,
          rings=2, rng=rng)
    K.part(lib, root, iron, "Rust", collide=False, cast_shadow=False, smooth_angle=45,
           notes="Tins on the shelf, door strap hinges, charred logs in the firebox.")
    lib.finish(root)
    return root


def review_views(name):
    """Extra review renders: (name, camera, target, fov, sun (elev, azim) or None, exposure offset,
    [(point light position, watts, colour)], figure position)."""
    lamp = (1.0, 0.72, 0.45)
    return [
        ("interior", (-6.4, 3.4, 6.0), (8.0, -3.0, 3.2), 72, (30, 60), 1.0,
         [((2.0, 0.0, 8.5), 900, lamp), ((-6.0, 2.0, 7.0), 250, lamp)], (5.0, 0.8, FLOOR)),
        ("loft", (6.0, 3.5, 6.4), (-4.5, -2.6, 9.8), 72, (30, 60), 1.0,
         [((0.5, 1.0, 8.5), 900, lamp), ((-7.0, 0.0, 13.0), 400, lamp)], (-1.0, -0.2, FLOOR)),
        ("hearth", (4.5, -1.8, 5.2), (11.0, 0.3, 2.6), 60, (30, 60), 1.0, [((6.0, 0.0, 7.0), 700, lamp)]),
        ("corner", (-15.5, 12.5, 4.0), (-10.5, 7.0, 3.6), 40, (34, -40)),
        ("chimney", (21.0, 11.5, 7.0), (12.4, 0.0, 9.5), 50, (38, 70)),
        ("porch", (4.5, 19.0, 4.6), (0.0, 7.0, 4.6), 55, (34, 30)),
    ]
