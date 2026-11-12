"""
lr_plaza.py - SpirePlatform (the plaza round the Spire) and Plinth (the launch plate) for the LandmarksReal set.

SpirePlatform: a 120-stud granite plaza, walking surface at z = 0.6 (flush with the Spire's first tread), placed
unrotated at the arena centre with the same origin as the Spire.
  - octagonal hole, apothem 20 = exactly the Spire's bottom slab
  - six concentric courses of worn granite flagstones (r 20..47.6, slabs 4-6.5 studs long, staggered joints of
    0.09-0.3 filled with moss and soil), broken by eight cobbled spokes on the Spire's face axes
  - a band of granite setts (r 47.6..56.6) holding the 24 launch-plate openings: centres at radius 52, angles
    0, 15 ... 345 degrees clockwise from north (north = Blender +Y = Roblox -Z), opening radius 3.4, each with a
    worn forged-iron rim and a granite-lined launch tube 12 studs deep below it
  - a ring of granite kerb stones (r 56.6..60, top 0.95)
  Visual parts never collide; convex collider pieces (Transparency 1) carry collision with the 24 openings open.

Plinth: worn steel launch plate (diameter 5.6, 16 facets, raised rim, concentric diamond-tread grip rings), tread
surface at z = 1.5 (Stand), on a steel ram 12 studs long so nothing floats while it rises out of the tube. The
facet facing the Spire (Blender +Y = Roblox LookVector) carries the thin light strip (Plinth_Ember).
Origin = the plaza surface at the opening centre (plaza y = 0.6), i.e. attachment Plate_<n> of SpirePlatform.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import lr_core as C
import lr_masonry as M
import lr_parts as P
import tex_landmarks as T

TAU = 2.0 * math.pi
TOP = 0.6                       # plaza walking surface
HOLE_AP = 20.0                  # octagonal hole = the Spire's bottom slab
R_PLATE, OPEN_R, N_PLATES = 52.0, 3.4, 24
R_BAND0, R_BAND1 = 47.6, 56.6   # setts band holding the openings
R_CURB1, CURB_TOP = 60.0, 0.95
COURSES = [24.3, 28.6, 32.9, 37.2, 42.0, R_BAND0]
SPOKE_HW = 1.25
GAP = 0.09
TUBE_DEPTH = 12.0
RIM_OUT = 3.95


def plate_angle(i):
    """Standard (CCW from +X) angle of plate i, which sits 15*i degrees clockwise from north."""
    return math.radians(90.0 - 15.0 * i)


def plate_xy(i):
    a = math.radians(15.0 * i)
    return (R_PLATE * math.sin(a), R_PLATE * math.cos(a))


def circ_pt(r, a, off=0.0):
    """Where the ray at angle a, shifted sideways by off, meets the circle of radius r."""
    d = Vector((math.cos(a), math.sin(a)))
    n = Vector((-math.sin(a), math.cos(a)))
    t = math.sqrt(max(r * r - off * off, 0.0))
    p = n * off + d * t
    return (p.x, p.y)


OCT = P.ngon(8, HOLE_AP, 0.0)
OCT_OUT = P.offset_convex(P.ccw(OCT), 0.07)


# ------------------------------------------------------------------------------------------------- flagstones
def edge_line(r_in, r_out, a, off, span):
    """Inner and outer point of a slab edge on the ray (a, off). Outer chords end ON the circle r_out - GAP/2;
    inner chords are pushed out so their middle clears r_in + GAP/2 (no overlap with the course inside)."""
    if r_in is None:
        pi = M.ray_hit(OCT_OUT, (0, 0), a, off)
    else:
        pi = circ_pt((r_in + GAP / 2) / math.cos(min(span, 0.6) / 2), a, off)
    po = circ_pt(r_out - GAP / 2, a, off)
    return pi, po


def build_flags(stone, rnd):
    """Lays the flagstone courses; returns the centre lines of the radial joints [(p_in, p_out)]."""
    axes = [k * math.pi / 4 for k in range(8)]
    joints = []
    for j, r_out in enumerate(COURSES):
        r_in = None if j == 0 else COURSES[j - 1]
        rm = ((HOLE_AP + 1.2) if r_in is None else r_in) * 0.5 + r_out * 0.5
        for k in range(8):
            A0, A1 = axes[k], axes[k] + math.pi / 4
            arc = rm * (math.pi / 4) - 2 * SPOKE_HW
            n = max(1, int(round(arc / rnd.uniform(4.4, 5.6))))
            w = [rnd.uniform(0.75, 1.25) for _ in range(n)]
            # joint angles measured at the mid radius between the spoke edges
            s0 = A0 + (SPOKE_HW + GAP / 2) / rm
            s1 = A1 - (SPOKE_HW + GAP / 2) / rm
            cuts = [s0]
            for wi in w[:-1]:
                cuts.append(cuts[-1] + (s1 - s0) * wi / sum(w))
            cuts.append(s1)
            for i in range(1, n):
                ji, jo = edge_line(r_in, r_out, cuts[i], 0.0, cuts[i + 1] - cuts[i])
                joints.append((ji, (jo[0] * (r_out + 0.15) / max(r_out - GAP / 2, 1e-3),
                                    jo[1] * (r_out + 0.15) / max(r_out - GAP / 2, 1e-3))))
            for i in range(n):
                a_lo, a_hi = cuts[i], cuts[i + 1]
                span = a_hi - a_lo
                lo = (A0, SPOKE_HW + GAP / 2) if i == 0 else (a_lo, GAP / 2)
                hi = (A1, -(SPOKE_HW + GAP / 2)) if i == n - 1 else (a_hi, -GAP / 2)
                pi0, po0 = edge_line(r_in, r_out, lo[0], lo[1], span)
                pi1, po1 = edge_line(r_in, r_out, hi[0], hi[1], span)
                inner = [pi0]
                if r_in is None:
                    # follow the octagon round any corner inside this slab
                    for v in OCT_OUT:
                        av = math.atan2(v[1], v[0]) % TAU
                        if (av - a_lo) % TAU < (a_hi - a_lo) % TAU:
                            inner.append(v)
                inner.append(pi1)
                poly = [inner[0], po0, po1] + list(reversed(inner[1:]))
                poly = [p for idx, p in enumerate(poly) if idx == 0 or (Vector(p) - Vector(poly[idx - 1])).length > 1e-4]
                c = P.centroid(poly)
                ang = math.atan2(c[1], c[0])
                tf = (Vector((-math.sin(ang), math.cos(ang), 0)), Vector((math.cos(ang), math.sin(ang), 0)))
                P.flagstone(stone, rnd, poly, TOP, depth=0.12, bevel=0.085, tilt=0.03, sink=0.02, top_frame=tf,
                            damp=0.3, sides=False)
    return joints


def build_spokes(setts, rnd):
    """Cobbled spokes on the Spire's eight face axes: two 1.25-wide runs of setts per spoke (courses along it)."""
    rows = T.STONE_STRIPS["SETTS"]
    for k in range(8):
        a = k * math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        n = Vector((-math.sin(a), math.cos(a), 0))
        for side in (-1, 1):
            o0, o1 = (0.0, SPOKE_HW) if side > 0 else (-SPOKE_HW, 0.0)
            p_in = [Vector(M.ray_hit(OCT_OUT, (0, 0), a, o)) for o in (o0, o1)]
            p_out = [Vector(circ_pt(R_BAND0 - 0.02, a, o)) for o in (o0, o1)]
            z = TOP - 0.03
            bm = C.new_bm()
            vs = [bm.verts.new((p.x, p.y, z)) for p in (p_in[0], p_out[0], p_out[1], p_in[1])]
            f = bm.faces.new(vs)
            if f.normal.z < 0:
                f.normal_flip()
            uv = C.uvl(bm)
            ou = rnd.random()
            for l in f.loops:
                q = l.vert.co
                u = q.dot(d) / T.TRIM_STUDS + ou
                t = (q.dot(n) - o0) / (o1 - o0)
                l[uv].uv = (u, C.strip_v(rows, t))
            f.material_index = C.M_TRIM
            setts.add(bm)


def build_joints(bed, rnd, radial):
    """Moss, soil and grit filling the flagstone joints, just under the worn arrises: one trough per radial joint,
    ring troughs between the courses and at the band, troughs along the spoke edges and round the octagon. The
    MOSS strip runs along each joint (U) and across it (V), so every joint reads right whatever its direction."""
    z = TOP - 0.065
    for (p0, p1) in radial:
        P.trough(bed, p0, p1, 0.42, z, sag=0.02, ou=rnd.random())
    for r in COURSES:
        P.ring_trough(bed, r + 0.05, 0.56, z, 0.0, TAU, 72, sag=0.02)
    for k in range(8):
        a = k * math.pi / 4
        for off in (SPOKE_HW + GAP / 2, -(SPOKE_HW + GAP / 2)):
            p0 = M.ray_hit(OCT_OUT, (0, 0), a, off)
            p1 = circ_pt(R_BAND0 + 0.2, a, off)
            P.trough(bed, p0, p1, 0.36, z - 0.005, sag=0.02, ou=rnd.random())
    oct_mid = P.offset_convex(P.ccw(OCT), 0.04)
    for i in range(8):
        P.trough(bed, oct_mid[i], oct_mid[(i + 1) % 8], 0.3, z, sag=0.015, ou=rnd.random())


# ------------------------------------------------------------------------------------------------- setts band
def boolean_cut(bm, cutter, mat_index):
    """EXACT boolean difference (bm - cutter); both are freed. Returns a new bmesh with UVs kept."""
    me_a = bpy.data.meshes.new("_lr_bool_a")
    bm.to_mesh(me_a)
    bm.free()
    me_b = bpy.data.meshes.new("_lr_bool_b")
    cutter.to_mesh(me_b)
    cutter.free()
    oa = bpy.data.objects.new("_lr_bool_a", me_a)
    ob = bpy.data.objects.new("_lr_bool_b", me_b)
    bpy.context.scene.collection.objects.link(oa)
    bpy.context.scene.collection.objects.link(ob)
    mod = oa.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = ob
    dg = bpy.context.evaluated_depsgraph_get()
    me_r = bpy.data.meshes.new_from_object(oa.evaluated_get(dg))
    out = bmesh.new()
    out.from_mesh(me_r)
    out.loops.layers.uv.verify()
    for f in out.faces:
        f.material_index = mat_index
    for o in (oa, ob):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in (me_a, me_b, me_r):
        bpy.data.meshes.remove(m)
    return out


def build_band(setts, rnd):
    """Granite setts r 47.6..56.6 in 1-stud courses (one SETTS strip each), with the 24 openings cut out."""
    rows = T.STONE_STRIPS["SETTS"]
    segs = 160
    z_top, z_bot = TOP - 0.025, TOP - 0.35
    radii = [R_BAND0 + k * (R_BAND1 - R_BAND0) / 9.0 for k in range(10)]
    bm = C.new_bm()
    uv = C.uvl(bm)
    top = [[bm.verts.new((r * math.cos(TAU * i / segs), r * math.sin(TAU * i / segs), z_top)) for i in range(segs)]
           for r in radii]
    bot0 = [bm.verts.new((radii[0] * math.cos(TAU * i / segs), radii[0] * math.sin(TAU * i / segs), z_bot)) for i in range(segs)]
    bot1 = [bm.verts.new((radii[-1] * math.cos(TAU * i / segs), radii[-1] * math.sin(TAU * i / segs), z_bot)) for i in range(segs)]
    ou = [rnd.random() for _ in radii]
    for k in range(9):
        rep = round(TAU * (radii[k] + radii[k + 1]) / 2 / T.TRIM_STUDS)
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((top[k][i], top[k][j], top[k + 1][j], top[k + 1][i]))
            if f.normal.z < 0:
                f.normal_flip()
            for l in f.loops:
                kk = k if l.vert in (top[k][i], top[k][j]) else k + 1
                ii = i if l.vert in (top[k][i], top[k + 1][i]) else i + 1
                l[uv].uv = (ou[k] + rep * ii / segs, C.strip_v(rows, (kk - k) * 1.0))
            f.material_index = C.M_TRIM
    # closed slab (sides + bottom) so the exact boolean has a solid to cut; the bottom is dropped afterwards
    for ring_t, ring_b in ((top[0], bot0), (top[-1], bot1)):
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((ring_t[i], ring_t[j], ring_b[j], ring_b[i]))
            for l in f.loops:
                l[uv].uv = (i / 8.0, C.strip_v(T.STONE_STRIPS["MOSS"], 0.05 + 0.1 * (l.vert.co.z < TOP - 0.2)))
            f.material_index = C.M_TRIM
    for i in range(segs):
        j = (i + 1) % segs
        f = bm.faces.new((bot0[i], bot0[j], bot1[j], bot1[i]))
        for l in f.loops:
            l[uv].uv = (i / 8.0, C.strip_v(T.STONE_STRIPS["MOSS"], 0.05))
        f.material_index = C.M_TRIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cut = C.new_bm()
    for i in range(N_PLATES):
        x, y = plate_xy(i)
        bmesh.ops.create_cone(cut, cap_ends=True, segments=32, radius1=OPEN_R + 0.03, radius2=OPEN_R + 0.03,
                              depth=2.0, matrix=Matrix.Translation((x, y, TOP - 0.2)))
    out = boolean_cut(bm, cut, C.M_TRIM)
    kill = []
    for f in out.faces:
        c = f.calc_center_median()
        if f.normal.z < -0.5:
            kill.append(f)
            continue
        if abs(f.normal.z) < 0.5:
            near = min(math.hypot(c.x - plate_xy(i)[0], c.y - plate_xy(i)[1]) for i in range(N_PLATES))
            if near < OPEN_R + 0.2:
                kill.append(f)                        # hole walls: hidden under the iron rims
    bmesh.ops.delete(out, geom=kill, context='FACES')
    setts.add(out)


def build_rims_and_tubes(iron, tube, dark, rnd):
    for i in range(N_PLATES):
        x, y = plate_xy(i)
        prof = [(RIM_OUT, TOP - 0.1), (RIM_OUT - 0.1, TOP + 0.04), (OPEN_R + 0.04, TOP + 0.04),
                (OPEN_R - 0.02, TOP - 0.55)]
        bm = C.lathe_bm(prof, 18, phase=rnd.uniform(0, TAU), caps=False)
        C.transform(bm, Matrix.Translation((x, y, 0)))
        bm.normal_update()
        C.Polar(C.M_IRON, T.IRON_STRIPS["STRAP"], (x, y, 0), OPEN_R - 0.05, RIM_OUT, 6, ou=rnd.random(),
                z0=TOP - 0.55, z1=TOP + 0.05)(bm, list(bm.faces))
        iron.add(bm)
        # granite-lined launch tube (faces point inward), damp foot, dark floor
        segs = 16
        z0, z1 = TOP - TUBE_DEPTH, TOP - 0.5
        bm = C.new_bm()
        r = OPEN_R - 0.01
        lo = [bm.verts.new((x + r * math.cos(TAU * k / segs), y + r * math.sin(TAU * k / segs), z0)) for k in range(segs)]
        hi = [bm.verts.new((x + r * math.cos(TAU * k / segs), y + r * math.sin(TAU * k / segs), z1)) for k in range(segs)]
        for k in range(segs):
            kk = (k + 1) % segs
            bm.faces.new((lo[k], hi[k], hi[kk], lo[kk]))            # wound so the normal points to the axis
        bm.normal_update()
        for f in bm.faces:
            c = f.calc_center_median()
            if f.normal.dot(Vector((x - c.x, y - c.y, 0))) < 0:
                f.normal_flip()
        rule = C.Granite(rnd, damp_z=z0)
        C.bisect(bm, (0, 0, z0 + T.STONE_STRIP_STUDS["DAMP"]), (0, 0, 1))
        bm.normal_update()
        rule(bm, list(bm.faces))
        tube.add(bm)
        fl = C.new_bm()
        fv = [fl.verts.new((x + r * math.cos(TAU * k / segs), y + r * math.sin(TAU * k / segs), z0)) for k in range(segs)]
        ff = fl.faces.new(fv)
        if ff.normal.z < 0:
            ff.normal_flip()
        C.Dark()(fl, list(fl.faces))
        dark.add(fl)


def build_curb(stone, rnd):
    n = 60
    off = rnd.uniform(0, TAU / n)
    for k in range(n):
        a0 = off + TAU * k / n + 0.035 / R_BAND1
        a1 = off + TAU * (k + 1) / n - 0.035 / R_BAND1
        poly = [circ_pt(R_BAND1 + 0.02, a0), circ_pt(R_CURB1, a0), circ_pt(R_CURB1, a1), circ_pt(R_BAND1 + 0.02, a1)]
        P.stone(stone, rnd, poly, -0.35, CURB_TOP + rnd.uniform(-0.03, 0.01), bevel=0.08, damp_z=0.0,
                chips=rnd.choice([0, 0, 1]), jitter=0.01)


# ------------------------------------------------------------------------------------------------- colliders
def build_colliders(c_inner, c_band, c_curb):
    # inside the band: 16 convex pieces from the octagon to the band
    for k in range(16):
        a0, a1 = k * TAU / 16, (k + 1) * TAU / 16
        R = (R_BAND0 + 0.05) / math.cos(TAU / 32)
        poly = M.poly_between(P.ngon(8, HOLE_AP + 0.02, 0.0), (0, 0), a0, a1, 0.0)
        outer = [(R * math.cos(a0), R * math.sin(a0)), (R * math.cos(a1), R * math.sin(a1))]
        M.collider_prism(c_inner, [poly[0], outer[0], outer[1]] + list(reversed(poly[1:])), 0.0, TOP)
    # the band: one 15-degree cell per plate, minus an octagon round the opening, as 8 convex pieces
    for i in range(N_PLATES):
        a = plate_angle(i)
        h = math.radians(7.5)
        Ri, Ro = R_BAND0 - 0.05, (R_BAND1 + 0.05) / math.cos(h)
        cell = [(Ri * math.cos(a - h), Ri * math.sin(a - h)), (Ro * math.cos(a - h), Ro * math.sin(a - h)),
                (Ro * math.cos(a + h), Ro * math.sin(a + h)), (Ri * math.cos(a + h), Ri * math.sin(a + h))]
        cell = P.ccw(cell)
        cx, cy = plate_xy(i)
        hole = [(cx + v[0], cy + v[1]) for v in P.ngon(8, OPEN_R + 0.02, 0.0)]
        for k in range(8):
            v0, v1 = hole[k], hole[(k + 1) % 8]
            b0 = math.atan2(v0[1] - cy, v0[0] - cx)
            b1 = math.atan2(v1[1] - cy, v1[0] - cx)
            if b1 <= b0:
                b1 += TAU
            outer = M.poly_between(cell, (cx, cy), b0, b1, 0.0)
            M.collider_prism(c_band, [v0] + outer + [v1], 0.0, TOP)
    # kerb ring
    for k in range(24):
        a0, a1 = k * TAU / 24, (k + 1) * TAU / 24
        Ri = R_BAND1 - 0.05
        Ro = R_CURB1 / math.cos(TAU / 48)
        poly = [(Ri * math.cos(a0), Ri * math.sin(a0)), (Ro * math.cos(a0), Ro * math.sin(a0)),
                (Ro * math.cos(a1), Ro * math.sin(a1)), (Ri * math.cos(a1), Ri * math.sin(a1))]
        M.collider_prism(c_curb, poly, 0.0, CURB_TOP)


# ------------------------------------------------------------------------------------------------- assets
def build_platform(lib, rnd):
    a = lib.begin("SpirePlatform", kind="Plaza", tags=["Spire"], notes=(
        "Place unrotated at the arena centre with the same origin as the Spire, on flat ground. Walking surface "
        "y = 0.6, flush with the Spire's first tread; the octagonal hole (apothem 20) is exactly the Spire's bottom "
        "slab. Worn granite flagstones (moss and soil in the joints), eight cobbled spokes on the Spire's face axes, "
        "a band of setts (r 47.6-56.6) with the 24 launch-plate openings (radius 3.4, centres at r = 52, every 15 "
        "degrees clockwise from north = Roblox -Z) and their forged-iron rims, and a granite kerb (r 56.6-60, top "
        "0.95). Under every opening a granite-lined launch tube 12 deep (to y = -11.4): carve the terrain there "
        "(e.g. Terrain:FillCylinder with Air, radius 3.5, from y = -11.6 to 0.6). Attachments Plate_1..Plate_24 = "
        "opening centres on the plaza surface, LookVector toward the Spire: put each Plinth's pivot there. Visual "
        "parts never collide; the Collider parts (Transparency 1) keep the 24 openings open."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="flagstones and kerb (granite tile + damp trim)")
    setts = a.group("setts", "Cobble", smooth_angle=50.0, cast_shadow=False, notes="cobbled spokes and the setts band")
    bed = a.group("bed", "Moss", smooth_angle=None, cast_shadow=False, notes="moss and soil in the joints")
    iron = a.group("iron", "DarkMetal", smooth_angle=50.0, notes="forged iron rims of the 24 openings")
    tube = a.group("tube", "Stone", smooth_angle=50.0, cast_shadow=False, notes="granite-lined launch tubes")
    c_inner = a.group("c_inner", "Collider", collide=True, collision="PreciseConvexDecomposition",
                      cast_shadow=False, rbx_material="Slate", transparency=1.0, smooth_angle=None,
                      notes="plaza inside the plate band: 16 convex slabs (walkable)")
    c_band = a.group("c_band", "Collider", collide=True, collision="PreciseConvexDecomposition",
                     cast_shadow=False, rbx_material="Cobblestone", transparency=1.0, smooth_angle=None,
                     notes="plate band: 24 cells x 8 convex pieces, the 24 openings stay open")
    c_curb = a.group("c_curb", "Collider", collide=True, collision="PreciseConvexDecomposition",
                     cast_shadow=False, rbx_material="Granite", transparency=1.0, smooth_angle=None,
                     notes="kerb ring, top 0.95 (a 0.35 step)")
    radial = build_flags(stone, rnd)
    build_spokes(setts, rnd)
    build_joints(bed, rnd, radial)
    build_band(setts, rnd)
    build_rims_and_tubes(iron, tube, bed, rnd)
    build_curb(stone, rnd)
    build_colliders(c_inner, c_band, c_curb)
    for i in range(N_PLATES):
        x, y = plate_xy(i)
        L = math.hypot(x, y)
        a.attach("Plate_%d" % (i + 1), (x, y, TOP), look=(-x / L, -y / L, 0.0), up=(0, 0, 1))
    return a


PL_R = 2.8          # plate radius (diameter 5.6)
PL_TREAD = 1.5      # walking surface (Stand)
PL_RIM = 1.6        # raised rim top
PL_BOT = 1.18
RAM_R = 1.85
RAM_BOT = PL_BOT - 12.0


def _ram(g, rnd, z0, z1, r, segs, ph, rows):
    bm = C.new_bm()
    uv = C.uvl(bm)
    nb = max(1, int(round(z1 - z0)))
    zs = [z0 + (z1 - z0) * k / nb for k in range(nb + 1)]
    rings = [[bm.verts.new((r * math.cos(ph + TAU * i / segs), r * math.sin(ph + TAU * i / segs), z))
              for i in range(segs)] for z in zs]
    circ = TAU * r
    for k in range(nb):
        ou = rnd.random()
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            u0 = ou + circ * i / segs / T.TRIM_STUDS
            u1 = ou + circ * (i + 1) / segs / T.TRIM_STUDS
            C._uv_set(f, uv, [(u0, C.strip_v(rows, 0.02)), (u1, C.strip_v(rows, 0.02)), (u1, C.strip_v(rows, 0.98)),
                              (u0, C.strip_v(rows, 0.98))], C.M_IRON)
    for f in bm.faces:
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, c.y, 0.0))) < 0:
            f.normal_flip()
    g.add(bm)
    return bm


def build_plinth(lib, rnd):
    a = lib.begin("Plinth", kind="StartPad", tags=["Plinth"], notes=(
        "Launch plate. Origin = the plaza surface at the opening centre (SpirePlatform attachment Plate_<n>, plaza "
        "y = 0.6): pivot the Plinth there with its LookVector toward the Spire. Worn steel plate 5.6 across (16 "
        "facets) with a raised rim and concentric diamond-tread grip rings; tread surface y = 1.5 (attachment Stand, "
        "where the contender's feet go); the facet facing the Spire carries Plinth_Ember, a thin light strip (Neon). "
        "Below it a steel ram 12 studs long (down to y = -10.8) fills the launch tube while the plate rises, so "
        "nothing floats. Lower/raise the whole model by LaunchDepth. Collider = one Hull cylinder (radius 2.8, "
        "y -10.8..1.5); the visual parts never collide."))
    steel = a.group("steel", "Steel", smooth_angle=50.0, notes="plate, rim, ram (worn steel)")
    ember = a.group("ember", "Ember", smooth_angle=None, cast_shadow=False, notes="light strip on the front facet: Neon")
    coll = a.group("c_plinth", "Collider", collide=True, collision="Hull", cast_shadow=False, rbx_material="Metal",
                   transparency=1.0, smooth_angle=None, notes="plate + ram cylinder, top 1.5")
    segs = 16
    ph = math.pi / 2 - math.pi / segs        # a facet centred on +Y (the front)
    steel_rows = T.IRON_STRIPS["STEEL"]
    tread_rows = T.IRON_STRIPS["TREAD"]

    def ring(r, z):
        return [(r * math.cos(ph + TAU * k / segs), r * math.sin(ph + TAU * k / segs), z) for k in range(segs)]

    # --- body: faceted side, chamfered top edge up to the rim, rim inner wall down to the tread
    prof = [(PL_R - 0.12, PL_BOT), (PL_R, PL_BOT + 0.12), (PL_R, PL_RIM - 0.06), (PL_R - 0.06, PL_RIM),
            (PL_R - 0.32, PL_RIM), (PL_R - 0.36, PL_TREAD)]
    bm = C.new_bm()
    rings = [[bm.verts.new(p) for p in ring(r, z)] for (r, z) in prof]
    uv = C.uvl(bm)
    ou = rnd.random()
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            coords = []
            for l in f.loops:
                kk = k if l.vert in (rings[k][i], rings[k][j]) else k + 1
                ii = i if l.vert in (rings[k][i], rings[k + 1][i]) else i + 1
                coords.append((ou + ii / segs * 4.0, C.strip_v(steel_rows, kk / (len(prof) - 1))))
            C._uv_set(f, uv, coords, C.M_IRON)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    steel.add(bm)
    # --- tread: concentric grip rings (diamond tread strip bent round), centre boss
    bands = [(0.0, 0.62), (0.62, 1.5), (1.5, PL_R - 0.36)]
    for bi, (r0, r1) in enumerate(bands):
        n = segs if bi else 8
        bm = C.new_bm()
        uv = C.uvl(bm)
        rep = max(1, round(TAU * (r0 + r1) / 2 / 2.0))
        z = PL_TREAD
        if r0 == 0.0:
            cv = bm.verts.new((0, 0, z + 0.03))
            outer = [bm.verts.new(((r1) * math.cos(ph + TAU * k / n), (r1) * math.sin(ph + TAU * k / n), z)) for k in range(n)]
            for k in range(n):
                kk = (k + 1) % n
                f = bm.faces.new((cv, outer[k], outer[kk]))
                C._uv_set(f, uv, [(ou + (k + 0.5) / n * rep, C.strip_v(tread_rows, 0.0)),
                                  (ou + k / n * rep, C.strip_v(tread_rows, 1.0)),
                                  (ou + (k + 1) / n * rep, C.strip_v(tread_rows, 1.0))], C.M_IRON)
        else:
            inner = [bm.verts.new((r0 * math.cos(ph + TAU * k / n), r0 * math.sin(ph + TAU * k / n), z)) for k in range(n)]
            outer = [bm.verts.new((r1 * math.cos(ph + TAU * k / n), r1 * math.sin(ph + TAU * k / n), z)) for k in range(n)]
            for k in range(n):
                kk = (k + 1) % n
                f = bm.faces.new((inner[k], outer[k], outer[kk], inner[kk]))
                C._uv_set(f, uv, [(ou + k / n * rep, C.strip_v(tread_rows, 0.0)),
                                  (ou + k / n * rep, C.strip_v(tread_rows, 1.0)),
                                  (ou + (k + 1) / n * rep, C.strip_v(tread_rows, 1.0)),
                                  (ou + (k + 1) / n * rep, C.strip_v(tread_rows, 0.0))], C.M_IRON)
        for f in bm.faces:
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
        steel.add(bm)
    # thin raised seam rings between the tread bands
    for r in (0.62, 1.5):
        bm = C.lathe_bm([(r + 0.05, PL_TREAD - 0.005), (r + 0.03, PL_TREAD + 0.035), (r - 0.03, PL_TREAD + 0.035),
                         (r - 0.05, PL_TREAD - 0.005)], segs, phase=ph, caps=False)
        C.Polar(C.M_IRON, steel_rows, (0, 0, 0), r - 0.06, r + 0.06, max(1, round(TAU * r / 4)), ou=rnd.random(),
                z0=PL_TREAD - 0.01, z1=PL_TREAD + 0.04)(bm, list(bm.faces))
        steel.add(bm)
    # --- underside: skirt cone and eight gussets onto the ram
    bm = C.lathe_bm([(RAM_R + 0.05, PL_BOT - 0.55), (PL_R - 0.2, PL_BOT - 0.02), (PL_R - 0.12, PL_BOT)], segs, phase=ph)
    C.Polar(C.M_IRON, steel_rows, (0, 0, 0), RAM_R, PL_R, 4, ou=rnd.random(), z0=PL_BOT - 0.6, z1=PL_BOT)(bm, list(bm.faces))
    steel.add(bm)
    for k in range(8):
        ang = ph + TAU * (k + 0.5) / 8
        d = Vector((math.cos(ang), math.sin(ang), 0))
        n = Vector((-math.sin(ang), math.cos(ang), 0))
        pts = [d * (RAM_R - 0.02) + Vector((0, 0, PL_BOT - 1.1)), d * (RAM_R - 0.02) + Vector((0, 0, PL_BOT - 0.05)),
               d * (PL_R - 0.25) + Vector((0, 0, PL_BOT - 0.05))]
        bm = C.new_bm()
        th = 0.07
        fr = [bm.verts.new(p + n * th) for p in pts]
        bk = [bm.verts.new(p - n * th) for p in pts]
        bm.faces.new(fr)
        bm.faces.new(list(reversed(bk)))
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((fr[i], fr[j], bk[j], bk[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        C.Strip(C.M_IRON, steel_rows, d, (0, 0, 1), PL_BOT - 1.15, PL_BOT, ou=rnd.random())(bm, list(bm.faces))
        steel.add(bm)
    # --- the ram: turned steel, guide collars. Built from 1-stud bands, U round the circumference at the trim
    # period and V up one band, so the steel strip keeps its real size (P.pole wraps one 1-stud strip round the
    # whole 11.6-stud circumference, which stretched the steel into a crumpled-plastic look - art direction fix)
    _ram(steel, rnd, RAM_BOT, PL_BOT - 0.5, RAM_R, segs, ph, steel_rows)
    for zc in (PL_BOT - 0.75, -4.2, -8.6):
        bm = C.lathe_bm([(RAM_R + 0.01, zc - 0.16), (RAM_R + 0.11, zc - 0.12), (RAM_R + 0.11, zc + 0.12),
                         (RAM_R + 0.01, zc + 0.16)], segs, phase=ph, caps=False)
        C.Polar(C.M_IRON, T.IRON_STRIPS["BAR"], (0, 0, 0), RAM_R, RAM_R + 0.12, 3, ou=rnd.random(), z0=zc - 0.16,
                z1=zc + 0.16)(bm, list(bm.faces))
        steel.add(bm)
    # --- light strip on the front facet (+Y): set into the side, just under the rim chamfer
    fx = PL_R * math.cos(math.pi / segs)          # facet apothem
    w = 2 * PL_R * math.sin(math.pi / segs) * 0.78
    bm = C.box_bm(w, 0.06, 0.1)
    C.transform(bm, Matrix.Translation((0, fx + 0.005, (PL_BOT + PL_RIM) / 2 - 0.02)))
    C.Flat(C.M_EMBER)(bm, list(bm.faces))
    ember.add(bm)
    # --- collider
    pts = []
    for (r, z) in ((PL_R, RAM_BOT), (PL_R, PL_TREAD)):
        pts += [(r * math.cos(ph + TAU * k / segs), r * math.sin(ph + TAU * k / segs), z) for k in range(segs)]
    M.collider_hull(coll, pts)
    a.attach("Stand", (0, 0, PL_TREAD), look=(0, 1, 0), up=(0, 0, 1))
    return a
