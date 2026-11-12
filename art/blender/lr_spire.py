"""
lr_spire.py - THE SPIRE ("the Cleft"), realistic rebuild for the LandmarksReal set.

A monumental tower of dressed grey granite. A stepped octagonal base (40 across, 1-stud risers, worn treads)
carries a socle of big ashlar courses with four gabled alcoves for supply crates (two leaning gable stones form
each alcove's pitched ceiling) and four stone buttresses on the diagonals, then a moulded cornice. Above it a
tapering monolith of massive courses splits down its upper half; three forged, riveted iron straps clamp the two
halves (rust streaks run down the stone below each strap) and an iron collar carries a forged fire basket
(cresset) with a glowing coal bed. Gameplay dimensions are those of v1 (landmarks.py).

Visual parts never collide; simple convex colliders (role Collider, Transparency 1) carry the collision.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import lr_core as C
import lr_masonry as M
import lr_parts as P
import tex_landmarks as T

TAU = 2.0 * math.pi
TER = 3.6                                  # terrace
SOC_W, SOC_K = 8.5, 2.8                    # socle chamfered square: half width, corner cut
SOC_TOP = 12.2
CORNICE = (12.2, 13.0)
SZ0, SZ1, SW0 = 12.9, 51.0, 6.6            # monolith taper (v1 numbers)
SPLIT_Z, TIP_Z = 26.7, 46.3
BANDS = [(26.0, 27.4), (36.4, 37.6), (45.3, 46.8)]
COURSES = [13.0, 16.5, 20.0, 23.4, 26.7, 29.9, 33.3, 37.0, 40.0, 43.0, 46.05, 47.9]
COLLAR = (47.9, 49.4)
AW, AJ, AA, AB = 2.7, 8.4, 9.9, 5.2        # alcove half width, jamb top, apex, back wall distance
TIERS = [(20.0, 0.0, 0.6), (18.0, 0.6, 1.6), (16.0, 1.6, 2.6), (14.0, 2.6, TER)]
BEACON = (0.0, 0.0, 54.5)


def cham_sq(w, k):
    return [(w, -w + k), (w, w - k), (w - k, w), (-w + k, w), (-w, w - k), (-w, -w + k), (-w + k, -w), (w - k, -w)]


def shaft_w(z):
    t = min(max((z - SZ0) / (SZ1 - SZ0), 0.0), 1.0)
    return SW0 * (1.0 - 0.545 * t ** 1.1)


def outline(z, out=0.0):
    w = shaft_w(z)
    pts = cham_sq(w, 0.36 * w)
    return P.offset_convex(pts, out) if out else pts


def cleft(z):
    if z <= SPLIT_Z:
        return 0.0
    return 0.45 + 0.5 * min(1.0, (z - SPLIT_Z) / (TIP_Z - SPLIT_Z))


def half(z, side, out=0.0):
    return M.clip_x(outline(z, out), cleft(z) - (out if out < 0 else 0.0), side)


def socle_cs(out=0.0):
    pts = cham_sq(SOC_W, SOC_K)
    return P.offset_convex(pts, out) if out else pts


# ---------------------------------------------------------------------------------------------------------- base
def build_steps(stone, dark, rnd):
    tan = math.tan(math.pi / 8)
    for ti, (a, z0, z1) in enumerate(TIERS):
        nxt = TIERS[ti + 1][0] if ti + 1 < len(TIERS) else None
        depth = (a - nxt + 0.45) if nxt else 2.0
        h = a * tan
        n_blocks = [3, 3, 2, 2][ti]
        for k in range(8):
            th = k * math.pi / 4
            n = Vector((math.cos(th), math.sin(th)))
            t = Vector((-math.sin(th), math.cos(th)))
            hi = h - depth * tan
            wts = [rnd.uniform(0.75, 1.25) for _ in range(n_blocks)]
            us = [-h]
            for wv in wts:
                us.append(us[-1] + 2 * h * wv / sum(wts))
            us[-1] = h
            for i in range(len(us) - 1):
                u0, u1 = us[i], us[i + 1]
                ui0 = -hi if i == 0 else u0
                ui1 = hi if i == len(us) - 2 else u1
                g = 0.04
                loc = [(u0 + (g if i else 0.0), 0.0), (u1 - (g if i < len(us) - 2 else 0.0), 0.0),
                       (ui1 - (g if i < len(us) - 2 else 0.0), depth), (ui0 + (g if i else 0.0), depth)]
                poly = [tuple(n * (a - v) + t * u) for (u, v) in loc]
                P.stone(stone, rnd, poly, z0 + 0.012, z1, bevel=0.09 if ti else 0.07, segs=1, damp_z=z0,
                        chips=rnd.choice([0, 0, 1]), top_frame=(Vector((t.x, t.y, 0)), Vector((n.x, n.y, 0))),
                        jitter=0.012)
        # dark bedding behind the joints of this tier
        M.dark_prism(dark, P.ngon(8, a - 0.3, 0.0), z0, z1 - 0.06, caps=False)
    # terrace paving between the kerb (apothem 12) and the socle
    oct12 = P.ngon(8, 12.0, 0.0)
    cs = socle_cs()
    for k in range(8):
        a0 = k * math.pi / 4 - math.pi / 8
        for (b0, b1) in ((a0, a0 + math.pi / 8), (a0 + math.pi / 8, a0 + math.pi / 4)):
            outer = M.poly_between(oct12, (0, 0), b0, b1, 0.08)
            inner = M.poly_between(cs, (0, 0), b0, b1, 0.08)
            poly = outer + list(reversed(inner))
            P.flagstone(stone, rnd, poly, TER, depth=0.45, bevel=0.08, tilt=0.02)
    M.dark_prism(dark, oct12, TER - 0.5, TER - 0.12)


# ---------------------------------------------------------------------------------------------------------- socle
def face_frame(k):
    """Socle face k (0..7): broad faces on the axes (k even), diagonal faces (k odd). Returns origin (face centre
    at z 0), along-face unit x, outward normal, half width."""
    th = k * math.pi / 4
    n = Vector((math.cos(th), math.sin(th), 0.0))
    x = Vector((-math.sin(th), math.cos(th), 0.0))
    if k % 2 == 0:
        dist, hw = SOC_W, SOC_W - SOC_K
    else:
        dist = (2 * SOC_W - SOC_K) / math.sqrt(2.0)
        hw = SOC_K / math.sqrt(2.0)
    return n * dist, x, n, hw


SOCLE_COURSES = [TER, 4.9, 6.65, AJ, 10.3, SOC_TOP]


def gable_lines(T_=1.15):
    """Left gable stone polygon in (s, z) and its outer line z(s) helper."""
    P0, A = Vector((-AW, AJ)), Vector((0.0, AA))
    u = A - P0
    nl = Vector((-u.y, u.x)).normalized()

    def outer_s_at(z):
        # outer (upper) line: P0 + T nl + t u
        t = (z - (P0.y + T_ * nl.y)) / u.y
        return P0.x + T_ * nl.x + t * u.x

    tz = -(P0.x + T_ * nl.x) / u.x                # t where the outer line reaches s = 0
    z_top = P0.y + T_ * nl.y + tz * u.y
    s_foot = outer_s_at(AJ)
    left = [(s_foot, AJ), (-AW, AJ), (0.0, AA), (0.0, z_top)]
    return left, outer_s_at, z_top


def build_socle(stone, dark, coll, rnd):
    left_gable, outer_s_at, z_top = gable_lines()
    for k in range(8):
        O, X, Nn, hw = face_frame(k)
        broad = (k % 2 == 0)
        for ci in range(len(SOCLE_COURSES) - 1):
            z0, z1 = SOCLE_COURSES[ci], SOCLE_COURSES[ci + 1]
            damp = TER if ci == 0 else None
            if not broad:
                # diagonal face: one or two stones per course, alternating
                if ci % 2 == 0:
                    pieces = [(-hw, hw)]
                else:
                    m = rnd.uniform(-0.4, 0.4)
                    pieces = [(-hw, m), (m, hw)]
                for (s0, s1) in pieces:
                    M.elev_block(stone, rnd, O, X, Nn, [(s0, z0), (s1, z0), (s1, z1), (s0, z1)], 0.0, 1.3,
                                 damp_z=damp, chips=rnd.choice([0, 1]))
                continue
            if z1 <= AJ + 1e-6:
                # jambs either side of the alcove: long-and-short work, deep enough to form the side walls
                for sgn in (-1, 1):
                    if ci % 2 == 0:
                        segs_ = [(AW, hw)]
                    else:
                        segs_ = [(AW, AW + 1.9), (AW + 1.9, hw)]
                    for (s0, s1) in segs_:
                        a_, b_ = sorted((sgn * s0, sgn * s1))
                        deep = 3.75 if abs(s0 - AW) < 1e-6 else 1.3
                        M.elev_block(stone, rnd, O, X, Nn, [(a_, z0), (b_, z0), (b_, z1), (a_, z1)], 0.0, deep,
                                     damp_z=damp, chips=rnd.choice([0, 1]))
            elif ci == 3:
                # course beside the gable stones (sloped ends)
                s_hi = outer_s_at(z1)
                for sgn in (-1, 1):
                    poly = [(-hw, z0), (left_gable[0][0], z0), (s_hi, z1), (-hw, z1)]
                    if sgn > 0:
                        poly = [(-s, z) for (s, z) in poly]
                    M.elev_block(stone, rnd, O, X, Nn, poly, 0.0, 1.3)
            else:
                # course over the gable: two stones meeting above the apex
                s_lo = outer_s_at(z0)
                for sgn in (-1, 1):
                    poly = [(-hw, z0), (s_lo, z0), (0.0, z_top), (0.0, z1), (-hw, z1)]
                    if sgn > 0:
                        poly = [(-s, z) for (s, z) in poly]
                    M.elev_block(stone, rnd, O, X, Nn, poly, 0.0, 1.3)
        if broad:
            # gable stones: the alcove's pitched ceiling
            for sgn in (-1, 1):
                poly = left_gable if sgn < 0 else [(-s, z) for (s, z) in left_gable]
                M.elev_block(stone, rnd, O, X, Nn, poly, 0.0, 3.75, bevel=0.1)
            # back wall (two stones) and floor slab
            dback = SOC_W - AB
            M.elev_block(stone, rnd, O, X, Nn, [(-AW - 0.1, TER), (AW + 0.1, TER), (AW + 0.1, 6.4), (-AW - 0.1, 6.4)],
                         dback, dback + 0.8, damp_z=TER)
            M.elev_block(stone, rnd, O, X, Nn, [(-AW - 0.1, 6.4), (AW + 0.1, 6.4), (AW + 0.1, AJ), (0.0, AA + 0.2),
                                                (-AW - 0.1, AJ)], dback, dback + 0.8)
            fl = [tuple(O + X * s - Nn * d)[:2] for (s, d) in ((-AW, 0.04), (AW, 0.04), (AW, dback), (-AW, dback))]
            P.flagstone(stone, rnd, fl, TER, depth=0.4, bevel=0.07)
    # dark core behind the courses, leaving the four alcoves open
    D = SOC_W - 0.45
    M.dark_prism(dark, P.rect(AB - 0.9, AB - 0.9), TER, SOC_TOP, caps=False)
    for k in range(4):
        rot = Matrix.Rotation(k * math.pi / 2, 3, 'Z')

        def R(pts):
            return [tuple((rot @ Vector((x, y, 0)))[:2]) for (x, y) in pts]
        M.dark_prism(dark, R([(AB, AW + 0.35), (D, AW + 0.35), (D, SOC_W - SOC_K), (SOC_W - SOC_K + 0.1, D),
                              (AW + 0.35, D), (AW + 0.35, AB)]),
                     TER, SOC_TOP, caps=False)
        th = k * math.pi / 2
        O = Vector((math.cos(th), math.sin(th), 0)) * SOC_W
        X = Vector((-math.sin(th), math.cos(th), 0))
        Nn = Vector((math.cos(th), math.sin(th), 0))
        gl, _, ztop = gable_lines()
        sf = gl[0][0]
        for sgn in (-1, 1):
            poly = [(-AW - 0.3, AJ + 0.6), (sf, AJ + 0.6), (0.0, ztop + 0.3), (0.0, SOC_TOP), (-AW - 0.3, SOC_TOP)]
            if sgn > 0:
                poly = [(-q, z) for (q, z) in poly]
            M.dark_elev(dark, O, X, Nn, poly, 1.25, SOC_W - AB + 0.1)
    # cornice: projecting course with a chamfered bed; deep enough to roof the socle under the monolith
    z0, z1 = CORNICE
    M.course_blocks(stone, rnd, socle_cs(0.02), socle_cs(0.55), z0, z1, 12, depth=3.0, gap=0.06, bevel=0.07,
                    center=(0, 0), mid=(socle_cs(0.55), z0 + 0.38))
    # buttresses on the diagonals
    for k in (1, 3, 5, 7):
        O, X, Nn, hw = face_frame(k)
        prof = [[(0.0, TER), (2.3, TER), (2.3, 5.7), (0.0, 5.7)],
                [(0.0, 5.7), (2.3, 5.7), (2.3, 7.6), (0.0, 7.6)],
                [(0.0, 7.6), (2.3, 7.6), (1.15, 9.9), (0.0, 9.9)],
                [(0.0, 9.9), (1.15, 9.9), (1.15, 10.9), (0.0, SOC_TOP)]]
        for bi, pr in enumerate(prof):
            # profile drawn in (projection, z), extruded across the face
            M.elev_block(stone, rnd, O + Nn * 0.0 - X * 1.2, Nn, -X, pr, -0.0, 2.4, bevel=0.09,
                         damp_z=TER if bi == 0 else None, chips=rnd.choice([0, 1]))
        M.collider_elev(coll, O - X * 1.2, Nn, -X, [(0.0, TER), (2.3, TER), (2.3, 7.6), (1.15, 9.9), (1.15, 10.9),
                                                     (0.0, SOC_TOP)], 0.0, 2.4)


def socle_colliders(coll):
    """Convex pieces: central core, 12 jamb/corner pieces, lintels and gable wedges over the four alcoves."""
    M.collider_prism(coll, P.rect(AB, AB), TER, CORNICE[1])
    for k in range(4):
        rot = Matrix.Rotation(k * math.pi / 2, 3, 'Z')

        def R(pts):
            return [tuple((rot @ Vector((x, y, 0)))[:2]) for (x, y) in pts]
        M.collider_prism(coll, R([(AB, AW), (SOC_W, AW), (SOC_W, SOC_W - SOC_K), (AB, SOC_W - SOC_K)]), TER, SOC_TOP)
        M.collider_prism(coll, R([(AB, SOC_W - SOC_K), (SOC_W, SOC_W - SOC_K), (SOC_W - SOC_K, SOC_W), (AB, SOC_W)]),
                         TER, SOC_TOP)
        M.collider_prism(coll, R([(AW, AB), (AB, AB), (AB, SOC_W), (AW, SOC_W)]), TER, SOC_TOP)
        M.collider_prism(coll, R([(AB, -AW), (SOC_W, -AW), (SOC_W, AW), (AB, AW)]), AA + 1.25, SOC_TOP)
        th = k * math.pi / 2
        O = Vector((math.cos(th), math.sin(th), 0)) * SOC_W
        X = Vector((-math.sin(th), math.cos(th), 0))
        Nn = Vector((math.cos(th), math.sin(th), 0))
        for sgn in (-1, 1):
            poly = [(-AW, AJ), (0.0, AA), (0.0, AA + 1.25), (-AW, AA + 1.25)]
            if sgn > 0:
                poly = [(-s, z) for (s, z) in poly]
            M.collider_elev(coll, O, X, Nn, poly, 0.0, SOC_W - AB)
    M.collider_prism(coll, socle_cs(0.55), CORNICE[0] + 0.3, CORNICE[1])


# ---------------------------------------------------------------------------------------------------------- monolith
def band_for(z0, z1):
    for b0, b1 in BANDS:
        if z0 < b0 <= z1 + 1e-6 or (z0 < b0 and z1 > b0):
            return b0
    if z1 >= COLLAR[0] - 1e-6:
        return COLLAR[0]
    return None


def build_monolith(stone, dark, rnd):
    for ci in range(len(COURSES) - 1):
        z0, z1 = COURSES[ci], COURSES[ci + 1]
        rust = band_for(z0, z1)
        damp = z0 if ci == 0 else None
        if z1 <= SPLIT_Z + 1e-6:
            n = 6 if ci % 2 == 0 else 7
            M.course_blocks(stone, rnd, outline(z0), outline(z1), z0, z1, n, depth=0.7, gap=0.08, bevel=0.1,
                            damp_z=damp, rust_z=rust, center=(0, 0))
        else:
            for side in (1, -1):
                p0, p1 = half(z0, side), half(z1, side)
                c = P.centroid(p0)
                M.course_blocks(stone, rnd, p0, p1, z0, z1, 3, depth=0.7, gap=0.08, bevel=0.1, rust_z=rust, center=c)
    # dark cores
    M.dark_prism(dark, outline(COURSES[0], -0.45), COURSES[0], SPLIT_Z, top_poly=outline(SPLIT_Z, -0.45), caps=False)
    for side in (1, -1):
        M.dark_prism(dark, half(SPLIT_Z, side, -0.45), SPLIT_Z, COURSES[-1], top_poly=half(COURSES[-1], side, -0.45))


def taper_strap(g, rnd, z0, z1, out=0.28, rivets=True, rivet_r=0.12, rows=1):
    """Forged iron strap clamped round the monolith between z0 and z1 (follows the taper), riveted."""
    lo, hi = outline(z0, out), outline(z1, out)
    ilo, ihi = outline(z0, -0.04), outline(z1, -0.04)
    bm = C.new_bm()
    n = len(lo)
    ob = [bm.verts.new((x, y, z0)) for x, y in lo]
    ot = [bm.verts.new((x, y, z1)) for x, y in hi]
    ib = [bm.verts.new((x, y, z0)) for x, y in ilo]
    it = [bm.verts.new((x, y, z1)) for x, y in ihi]
    for i in range(n):
        j = (i + 1) % n
        for quad, exp in (((ob[i], ob[j], ot[j], ot[i]), None), ((it[i], it[j], ib[j], ib[i]), None),
                          ((ot[i], ot[j], it[j], it[i]), Vector((0, 0, 1))), ((ib[i], ib[j], ob[j], ob[i]), Vector((0, 0, -1)))):
            f = bm.faces.new(quad)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    C.bevel_all(bm, 0.05, 1, angle_deg=50.0)
    bm.normal_update()
    rowsr = T.IRON_STRIPS["STRAP"]
    uv = C.uvl(bm)
    per = sum((Vector(lo[(i + 1) % n]) - Vector(lo[i])).length for i in range(n))
    rep = max(1, round(per / T.TRIM_STUDS))
    ou = rnd.random()
    for f in bm.faces:
        coords = []
        for l in f.loops:
            p = l.vert.co
            coords.append((math.atan2(p.y, p.x) / TAU * rep + ou, C.strip_v(rowsr, (p.z - z0) / (z1 - z0))))
        a0 = coords[0][0]
        coords = [(a0 + ((u - a0 + rep / 2) % rep) - rep / 2, v) for (u, v) in coords]
        C._uv_set(f, uv, coords, C.M_IRON)
    g.add(bm)
    if rivets:
        zs = [(z0 + z1) / 2] if rows == 1 else [z0 + (z1 - z0) * 0.3, z0 + (z1 - z0) * 0.7]
        for zr in zs:
            ring = outline(zr, out)
            for i in range(n):
                p0, p1 = Vector(ring[i]), Vector(ring[(i + 1) % n])
                e = p1 - p0
                L = e.length
                nrm = Vector((e.y, -e.x, 0)).normalized()
                cnt = max(1, int(L / 2.1))
                for r in range(cnt):
                    f = (r + 0.5) / cnt
                    q = p0 + e * f
                    P.rivet(g, (q.x, q.y, zr), nrm, r=rivet_r, h=rivet_r * 0.7, segs=5)


# ---------------------------------------------------------------------------------------------------------- crown
def build_crown(iron, soot, ember, rnd):
    taper_strap(iron, rnd, COLLAR[0], COLLAR[1], out=0.36, rows=2, rivet_r=0.13)
    # forged bowl (pan) resting on the collar, spanning the cleft
    prof = [(0.0, 49.32), (2.9, 49.32), (3.75, 49.75), (4.35, 50.5), (4.72, 51.5), (4.82, 52.05), (4.6, 52.12),
            (4.42, 51.6), (4.08, 50.75), (3.45, 50.15), (2.6, 49.82), (0.0, 49.82)]
    bm = C.lathe_bm(prof, 16, phase=math.pi / 16)
    C.Polar(C.M_IRON, T.IRON_STRIPS["STRAP"], (0, 0, 0), 0.0, 4.9, 7, z0=49.3, z1=52.15)(bm, list(bm.faces))
    iron.add(bm)
    # cage: 16 forged square bars, twisted between the hoops, flaring outward
    rz = [(4.55, 50.55), (4.78, 51.9), (5.1, 53.4), (5.42, 54.9), (5.72, 56.3), (5.96, 57.7), (6.0, 58.15)]
    for k in range(16):
        a = k * TAU / 16 + TAU / 32
        rad = Vector((math.cos(a), math.sin(a), 0))
        spine = [rad * r + Vector((0, 0, z)) for (r, z) in rz]
        P.iron_bar(iron, rnd, spine, 0.27, 0.27, twist=math.pi * (1 if k % 2 else -1) * 0.5, up=rad)
    for (r, z, h) in ((5.12, 53.4, 0.42), (5.74, 56.3, 0.42)):
        ring_band(iron, rnd, r + 0.14, z, h, 0.13)
    P.ring_bar(iron, rnd, (0, 0), 5.98, 57.75, 0.3, 0.3, segs=32)
    # coal bed: a low glowing core, almost buried under a heap of charcoal lumps, so only the gaps glow
    dome = C.new_bm()
    bmesh.ops.create_icosphere(dome, subdivisions=2, radius=1.0)
    C.transform(dome, Matrix.Diagonal((4.05, 4.05, 0.75, 1.0)))
    C.transform(dome, Matrix.Translation((0, 0, 52.0)))
    C.jitter_verts(dome, 0.05, rnd)
    C.Flat(C.M_EMBER)(dome, list(dome.faces))
    ember.add(dome)
    coal_heap(soot, rnd, (0, 0, 52.0), 4.0, 0.75, 175, (0.36, 0.62))


def coal_lump(g, rnd, p, r):
    """Cheap charcoal lump: a jittered, tumbled box (12 tris) on the SOOT strip - blocky like split charcoal."""
    bm = C.box_bm(2.0, 2.0, 2.0)
    C.transform(bm, Matrix.Diagonal((r * rnd.uniform(0.7, 1.2), r * rnd.uniform(0.55, 0.9), r * rnd.uniform(0.45, 0.75), 1.0)))
    C.jitter_verts(bm, r * 0.22, rnd)
    C.transform(bm, Matrix.Rotation(rnd.uniform(0, TAU), 4, 'Z') @ Matrix.Rotation(rnd.uniform(-0.5, 0.5), 4, 'X')
                @ Matrix.Rotation(rnd.uniform(-0.5, 0.5), 4, 'Y'))
    C.transform(bm, Matrix.Translation(p))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    C.Strip(C.M_IRON, T.IRON_STRIPS["SOOT"], (1, 0, 0), (0, 0, 1), p[2] - r, p[2] + r, ou=rnd.random())(bm, list(bm.faces))
    g.add(bm)


def coal_heap(g, rnd, center, rad, height, n, rr):
    """Lumps scattered over the dome surface (z = height * sqrt(1 - (d/rad)^2)), denser in the middle."""
    cx, cy, cz = center
    for i in range(n):
        d = rad * math.sqrt(rnd.random()) * 0.97
        ph = rnd.uniform(0, TAU)
        z = cz + height * math.sqrt(max(0.0, 1.0 - (d / rad) ** 2)) - 0.08
        coal_lump(g, rnd, (cx + d * math.cos(ph), cy + d * math.sin(ph), z), rnd.uniform(*rr))


def ring_band(g, rnd, r, zc, h, t, segs=32):
    """Flat forged hoop (vertical band) of radius r centred at height zc."""
    bm = C.new_bm()
    uv = C.uvl(bm)
    rows = T.IRON_STRIPS["STRAP"]
    rings = []
    for (rr, z) in ((r, zc - h / 2), (r, zc + h / 2), (r - t, zc + h / 2), (r - t, zc - h / 2)):
        rings.append([bm.verts.new((rr * math.cos(TAU * i / segs), rr * math.sin(TAU * i / segs), z)) for i in range(segs)])
    ou = rnd.random()
    rep = max(1, round(TAU * r / T.TRIM_STUDS))
    for a in range(4):
        b = (a + 1) % 4
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((rings[a][i], rings[a][j], rings[b][j], rings[b][i]))
            va, vb = C.strip_v(rows, a / 4), C.strip_v(rows, (a + 1) / 4)
            C._uv_set(f, uv, [(ou + rep * i / segs, va), (ou + rep * (i + 1) / segs, va), (ou + rep * (i + 1) / segs, vb),
                              (ou + rep * i / segs, vb)], C.M_IRON)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g.add(bm)


# ---------------------------------------------------------------------------------------------------------- asset
def build(lib, rnd):
    a = lib.begin("Spire", kind="Landmark", tags=["Spire", "Landmark"], notes=(
        "Hero landmark at the arena centre (origin = arena centre, base on the plaza at y = 0). 'The Cleft': dressed "
        "granite tower on a walkable stepped octagon (40 across; 1-stud risers, 2-stud treads, terrace at 3.6), a "
        "socle with four gabled alcoves (CrateSlot_1..4 on the alcove floors, LookVector out of the alcove), four "
        "buttresses on the diagonals, then a tapering monolith split down its upper half (slit along Roblox Z, so the "
        "sky shows through from the front/back), clamped by three riveted iron straps, an iron collar and a forged "
        "fire basket. Visual parts are non-colliding; the Collider parts (Transparency 1) carry collision and queries. "
        "Spire_Ember = glowing coal bed (Neon, no collision, no shadow): parent the beacon PointLight and fire/smoke "
        "emitters to attachment Beacon."))
    stone = a.group("stone", "Granite", collide=False, query=False, smooth_angle=50.0, notes="dressed granite (tile + trim)")
    dark = a.group("dark", "Stone", collide=False, query=False, cast_shadow=False, smooth_angle=None,
                   notes="joint backing, only visible through the joints")
    iron = a.group("iron", "DarkMetal", collide=False, query=False, smooth_angle=50.0, notes="straps, collar, fire basket")
    soot = a.group("coals", "Basalt", collide=False, query=False, cast_shadow=False, smooth_angle=None,
                   notes="charcoal lumps on the coal bed")
    ember = a.group("ember", "Ember", collide=False, query=False, cast_shadow=False, smooth_angle=None,
                    notes="glowing coal bed: Neon (255,128,48), no collision, no shadow")
    c_base = a.group("c_base", "Collider", collide=True, collision="PreciseConvexDecomposition", cast_shadow=False,
                     rbx_material="Granite", transparency=1.0, smooth_angle=None,
                     notes="steps, terrace and buttresses: 4 octagonal tiers + 4 wedges (walkable)")
    c_socle = a.group("c_socle", "Collider", collide=True, collision="PreciseConvexDecomposition", cast_shadow=False,
                      rbx_material="Granite", transparency=1.0, smooth_angle=None,
                      notes="socle with the four open alcoves (convex pieces), cornice")
    c_shaft = a.group("c_shaft", "Collider", collide=True, collision="PreciseConvexDecomposition", cast_shadow=False,
                      rbx_material="Granite", transparency=1.0, smooth_angle=None,
                      notes="monolith: lower block + the two split halves (the slit stays open) + collar")
    c_top = a.group("c_top", "Collider", collide=True, collision="Hull", cast_shadow=False, rbx_material="Metal",
                    transparency=1.0, smooth_angle=None, notes="fire basket")

    build_steps(stone, dark, rnd)
    build_socle(stone, dark, c_base, rnd)
    build_monolith(stone, dark, rnd)
    for (b0, b1) in BANDS:
        taper_strap(iron, rnd, b0, b1, out=0.3, rows=1 if b1 - b0 < 1.45 else 2)
    build_crown(iron, soot, ember, rnd)

    # colliders
    for (ap, z0, z1) in TIERS:
        M.collider_prism(c_base, P.ngon(8, ap, 0.0), z0, z1)
    socle_colliders(c_socle)
    M.collider_prism(c_shaft, outline(COURSES[0]), COURSES[0], SPLIT_Z, top_poly=outline(SPLIT_Z))
    for side in (1, -1):
        M.collider_prism(c_shaft, half(SPLIT_Z, side), SPLIT_Z, COLLAR[0], top_poly=half(COLLAR[0], side))
    M.collider_prism(c_shaft, outline(COLLAR[0], 0.36), COLLAR[0], COLLAR[1], top_poly=outline(COLLAR[1], 0.36))
    hull_pts = []
    for (r, z) in ((4.9, 49.3), (4.9, 52.1), (6.1, 58.2)):
        hull_pts += [(r * math.cos(TAU * i / 12), r * math.sin(TAU * i / 12), z) for i in range(12)]
    M.collider_hull(c_top, hull_pts)

    # attachments
    for k in range(4):
        th = k * math.pi / 2
        d = (AB + SOC_W) / 2
        a.attach("CrateSlot_%d" % (k + 1), (d * math.cos(th), d * math.sin(th), TER), look=(math.cos(th), math.sin(th), 0),
                 up=(0, 0, 1))
    a.attach("Beacon", BEACON, look=(0, 0, 1), up=(0, 1, 0))
    return a
