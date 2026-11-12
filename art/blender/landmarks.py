"""
landmarks.py - LAST STANDING "Landmarks" category (Blender 5.3, headless).

Assets (exact names): Spire (hero landmark at the arena centre), SpirePlatform (paved plaza ring),
Plinth (start pad) and the lobby kit: Pavilion, Brazier, BannerPole, Bench, NoticeBoard, Railing,
LobbyGate, StoneSteps.

The Spire is "the Cleft": a faceted monolith of layered stone split along its upper half, the two halves
bound by dark-iron bands that bridge the slit (sky shows through it), braced at the base by iron wedge
buttresses, and crowned by a tulip-shaped iron basket of sixteen flared fins cradling the fire bowl.
(Original design - no franchise imagery.)

Run:
    blender --background --factory-startup --python landmarks.py -- <out_dir> <preview_dir>
Optional review renders (close-ups, composites with a 5.5-stud scale figure) are written when the
environment variable LS_DETAIL_DIR points at a folder. They are never exported.
"""
import math
import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls  # noqa: E402
import ls_patch  # noqa: F401,E402  (art-direction fixes on top of ls_common: hard edges, bounds, query flags)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

out_dir, preview_dir = ls.args()
ls.reset()
ls.seed(6031)
RNG = random.Random(6031)
lib = ls.Library("Landmarks")
TAU = 2.0 * math.pi


# ============================================================================================
# Small helpers (local to this generator - ls_common is shared and must not be edited)
# ============================================================================================
def rr(a, b):
    return RNG.uniform(a, b)


def add(root, obj, role, smooth_angle=None, **kw):
    """lib.add with a single material slot. (Hard edges for smooth_angle now come from ls_patch, which fixes
    ls.smooth() for every category; this generator used to carry its own copy of that fix.)"""
    for p in obj.data.polygons:
        p.material_index = 0
    return lib.add(root, obj, role, smooth_angle=smooth_angle, **kw)


# ---------------- 2D outlines (x, y) ----------------
def ngon(n, apothem, phase=0.0):
    """Regular n-gon with flat faces whose normals sit at phase + k*360/n (CCW)."""
    R = apothem / math.cos(math.pi / n)
    return [(R * math.cos(phase + (k + 0.5) * TAU / n), R * math.sin(phase + (k + 0.5) * TAU / n)) for k in range(n)]


def ngon_sampled(n, apothem, samples):
    """Points on a regular n-gon (face normals at k*360/n) sampled at equal angles; corners included
    when samples is a multiple of 2n."""
    sector = TAU / n
    pts = []
    for k in range(samples):
        a = TAU * k / samples
        rel = ((a + sector / 2) % sector) - sector / 2
        r = apothem / math.cos(rel)
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def circle(samples, r, phase=0.0):
    return [(r * math.cos(phase + TAU * k / samples), r * math.sin(phase + TAU * k / samples)) for k in range(samples)]


def arc(r, a0, a1, n):
    return [(r * math.cos(a0 + (a1 - a0) * i / (n - 1)), r * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]


def rect(hx, hy, cx=0.0, cy=0.0):
    return [(cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy), (cx - hx, cy - hy)]


def chamfer_square(w, k):
    """Square of half-width w with its corners cut back by k (8 faces: 4 broad, 4 narrow diagonals)."""
    return [(w, -w + k), (w, w - k), (w - k, w), (-w + k, w), (-w, w - k), (-w, -w + k), (-w + k, -w), (w - k, -w)]


def offset_convex(pts, d):
    """Mitred outward offset of a convex CCW polygon (negative d = inset)."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e1 = (p1 - p0).normalized()
        e2 = (p2 - p1).normalized()
        n1 = Vector((e1.y, -e1.x))
        n2 = Vector((e2.y, -e2.x))
        m = (n1 + n2).normalized()
        k = d / max(m.dot(n1), 0.25)
        out.append((p1.x + m.x * k, p1.y + m.y * k))
    return out


def offset_polyline(path, d):
    """Mitred offset of an open 2D polyline to its left (negative d = right)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    out = []
    for i in range(n):
        if i == 0 or i == n - 1:
            e = (pts[1] - pts[0]) if i == 0 else (pts[-1] - pts[-2])
            e.normalize()
            out.append(pts[i] + Vector((-e.y, e.x)) * d)
            continue
        e1 = (pts[i] - pts[i - 1]).normalized()
        e2 = (pts[i + 1] - pts[i]).normalized()
        n1 = Vector((-e1.y, e1.x))
        n2 = Vector((-e2.y, e2.x))
        m = (n1 + n2).normalized()
        out.append(pts[i] + m * (d / max(m.dot(n1), 0.25)))
    return [(p.x, p.y) for p in out]


def clip_x(pts, x0, side):
    """Clip a convex polygon to the half plane side*x >= x0 (Sutherland-Hodgman, keeps CCW order)."""
    out = []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        fa, fb = side * a[0] - x0, side * b[0] - x0
        if fa >= 0:
            out.append(a)
        if (fa >= 0) != (fb >= 0):
            t = fa / (fa - fb)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def xform2(pts, s=1.0, rot=0.0, dx=0.0, dy=0.0):
    c, sn = math.cos(rot), math.sin(rot)
    return [(dx + s * (x * c - y * sn), dy + s * (x * sn + y * c)) for x, y in pts]


def ring3(pts, z):
    return [(x, y, z) for x, y in pts]


# ---------------- solids ----------------
def loft(name, rings, cap0=True, cap1=True):
    """Skin consecutive rings (same vertex count) into a closed solid."""
    bm = bmesh.new()
    vr = [[bm.verts.new(Vector(p)) for p in ring] for ring in rings]
    n = len(vr[0])
    for a, b in zip(vr[:-1], vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap0:
        bm.faces.new(list(reversed(vr[0])))
    if cap1:
        bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def prism(name, pts, z0, z1, top=None):
    return loft(name, [ring3(pts, z0), ring3(pts if top is None else top, z1)])


def cprism(name, pts, z0, z1, bevel=0.1, bottom=0.0):
    """Vertical prism with a chamfer on the top edge (and optionally the bottom edge) only."""
    rings = []
    if bottom > 0:
        rings.append(ring3(offset_convex(pts, -bottom), z0))
        rings.append(ring3(pts, z0 + bottom))
    else:
        rings.append(ring3(pts, z0))
    if bevel > 0:
        rings.append(ring3(pts, z1 - bevel))
        rings.append(ring3(offset_convex(pts, -bevel), z1))
    else:
        rings.append(ring3(pts, z1))
    return loft(name, rings)


def band_solid(name, outer, inner, z0, z1, closed=True):
    """Solid between two 2D loops/polylines with the same point count (rings, arcs, sectors)."""
    bm = bmesh.new()
    ob = [bm.verts.new((x, y, z0)) for x, y in outer]
    ot = [bm.verts.new((x, y, z1)) for x, y in outer]
    ib = [bm.verts.new((x, y, z0)) for x, y in inner]
    it = [bm.verts.new((x, y, z1)) for x, y in inner]
    n = len(outer)
    for i in (range(n) if closed else range(n - 1)):
        j = (i + 1) % n
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((it[i], it[j], ib[j], ib[i]))
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((ib[i], ib[j], ob[j], ob[i]))
    if not closed:
        bm.faces.new((ob[0], ot[0], it[0], ib[0]))
        bm.faces.new((ib[-1], it[-1], ot[-1], ob[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def band_chamfer(name, outer, inner, z0, z1, b=0.05, closed=True):
    """Like band_solid but with a small chamfer on the two top edges only (no wasted bottom bevels)."""
    oi, io = [], []
    for (ox, oy), (ix, iy) in zip(outer, inner):
        d = Vector((ix - ox, iy - oy)).normalized()
        oi.append((ox + d.x * b, oy + d.y * b))
        io.append((ix - d.x * b, iy - d.y * b))
    prof = [ring3(outer, z0), ring3(outer, z1 - b), ring3(oi, z1), ring3(io, z1), ring3(inner, z1 - b), ring3(inner, z0)]
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in prof]
    n, m = len(outer), len(prof)
    for a in range(m):
        A, B = vr[a], vr[(a + 1) % m]
        for i in (range(n) if closed else range(n - 1)):
            j = (i + 1) % n
            bm.faces.new((A[i], A[j], B[j], B[i]))
    if not closed:
        bm.faces.new([r[0] for r in vr])
        bm.faces.new([r[-1] for r in reversed(vr)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def sweep(name, spine, section_fn, side_vec, cap0=True, cap1=True):
    """Sweep a 2D section along a spine. section_fn(t) -> [(u, v)], u along side_vec, v along
    tangent x side (for an upward spine with a tangential side vector, +v points toward the axis)."""
    pts = [Vector(p) for p in spine]
    n = len(pts)
    S = Vector(side_vec).normalized()
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            tng = pts[1] - pts[0]
        elif i == n - 1:
            tng = pts[-1] - pts[-2]
        else:
            tng = pts[i + 1] - pts[i - 1]
        tng.normalize()
        side = (S - tng * S.dot(tng)).normalized()
        nrm = tng.cross(side).normalized()
        rings.append([p + side * u + nrm * v for (u, v) in section_fn(i / (n - 1))])
    return loft(name, rings, cap0, cap1)


def beam(name, p0, p1, w, h, up=(0, 0, 1), extend=0.0):
    """Box from p0 to p1 (w across, h along the 'up' side)."""
    p0, p1 = Vector(p0), Vector(p1)
    dn = (p1 - p0).normalized()
    p0, p1 = p0 - dn * extend, p1 + dn * extend
    side = Vector(up).cross(dn)
    if side.length < 1e-6:
        side = Vector((0, 1, 0)).cross(dn)
    side.normalize()
    upn = dn.cross(side).normalized()
    obj = ls.cube(name, size=((p1 - p0).length, w, h))
    m = Matrix((dn, side, upn)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    obj.matrix_world = m
    return obj


def rod(name, p0, p1, r0, r1=None, segs=8):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    obj = ls.cylinder(name, radius=r0, radius_top=(r0 if r1 is None else r1), depth=d.length, segments=segs)
    m = d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    m.translation = p0
    obj.matrix_world = m
    return obj


def at(obj, x=0.0, y=0.0, z=0.0, rz=0.0):
    """Bake the object's transform, then rotate its mesh about world Z by rz and translate it."""
    ls.bake_transform(obj)
    obj.data.transform(Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, 'Z'))
    obj.data.update()
    return obj


def place(obj, matrix):
    ls.bake_transform(obj)
    obj.data.transform(matrix)
    obj.data.update()
    return obj


def frame_matrix(origin, xaxis, zaxis):
    zz = Vector(zaxis).normalized()
    xx = Vector(xaxis)
    xx = (xx - zz * xx.dot(zz)).normalized()
    yy = zz.cross(xx)
    m = Matrix((xx, yy, zz)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def bolt(name, origin, along, normal, s=0.18, h=0.2):
    b = loft(name, [ring3(rect(s, s), -0.05), ring3(rect(s, s), h * 0.45), ring3(rect(s * 0.6, s * 0.6), h)])
    return place(b, frame_matrix(origin, along, normal))


def boolean(obj, cutter, op="DIFFERENCE"):
    ls.refresh()
    mod = obj.modifiers.new("Bool", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    mod.solver = "EXACT"
    ls.apply_modifiers(obj)
    me = cutter.data
    bpy.data.objects.remove(cutter, do_unlink=True)
    if me.users == 0:
        bpy.data.meshes.remove(me)
    return obj


def solidify(obj, thickness, offset=0.0):
    mod = obj.modifiers.new("Solid", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = offset
    mod.use_even_offset = True
    mod.use_quality_normals = True
    return ls.apply_modifiers(obj)


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def grid_xz(name, x0, x1, z0, z1, nx, nz):
    bm = bmesh.new()
    rows = [[bm.verts.new((x0 + (x1 - x0) * i / nx, 0.0, z0 + (z1 - z0) * j / nz)) for i in range(nx + 1)]
            for j in range(nz + 1)]
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    return ls.from_bmesh(name, bm)


def lump(name, loc, r, squash=0.75, subdiv=1, jit=0.14):
    o = ls.icosphere(name, radius=r, subdivisions=subdiv, loc=loc,
                     rot=(rr(0, TAU), rr(0, TAU), rr(0, TAU)), scale=(rr(0.85, 1.15), rr(0.85, 1.15), squash))
    ls.jitter(o, r * jit, RNG)
    return o


def coal_bed(prefix, center, rx, ry, rz, n_lumps, lump_r, max_polar_deg=62, subdiv=2):
    """Glowing faceted mound (Ember) + dark charcoal lumps (Basalt) resting on it."""
    dome = ls.icosphere(prefix + "_dome", radius=1.0, subdivisions=subdiv, loc=center, scale=(rx, ry, rz))
    ls.jitter(dome, 0.05, RNG)
    lumps = []
    for i in range(n_lumps):
        th = math.radians(rr(0, max_polar_deg))
        ph = rr(0, TAU) if i else 0.3
        p = Vector(center) + Vector((rx * math.sin(th) * math.cos(ph), ry * math.sin(th) * math.sin(ph),
                                     rz * math.cos(th) * 0.96))
        lumps.append(lump(prefix + "_lump%d" % i, tuple(p), lump_r * rr(0.7, 1.25), squash=rr(0.55, 0.8)))
    return dome, ls.join(lumps, prefix + "_lumps")


def fin_basket(prefix, n, main_rz, minor_rz, main_wd, minor_wd):
    """Tulip-shaped iron basket: n tapered bars curving outward (even = main/tall, odd = minor/short).
    *_rz are spine points (r, z); *_wd are (half width, half depth) at the base."""
    bars = []
    for k in range(n):
        a = k * TAU / n
        main = (k % 2 == 0)
        radial = Vector((math.cos(a), math.sin(a), 0.0))
        tang = Vector((-math.sin(a), math.cos(a), 0.0))
        spine = [radial * r + Vector((0, 0, z)) for r, z in (main_rz if main else minor_rz)]
        w0, d0 = main_wd if main else minor_wd

        def section(t, w0=w0, d0=d0):
            w = w0 * (1 - 0.35 * t)
            d = d0 * (1 - 0.45 * t)
            return [(w, d), (-w, d), (-w, -d), (w, -d)]
        bars.append(sweep("%s%d" % (prefix, k), spine, section, tang))
    return bars


def lantern(prefix, hook, drop=0.7, size=0.95, height=1.2):
    """Hanging iron lantern. Returns (metal parts, ember core, core centre)."""
    x, y, zt = hook
    cap_top = zt - drop
    body_top = cap_top - 0.42
    body_bot = body_top - height
    metal = [rod(prefix + "_chain", (x, y, zt + 0.05), (x, y, cap_top - 0.1), 0.06, segs=6),
             ls.torus(prefix + "_ring", major=0.16, minor=0.05, major_segments=8, minor_segments=4,
                      loc=(x, y, cap_top + 0.1), rot=(math.pi / 2, 0, 0)),
             loft(prefix + "_cap", [ring3(rect(size * 0.64, size * 0.64, x, y), body_top - 0.05),
                                    ring3(rect(size * 0.64, size * 0.64, x, y), body_top + 0.04),
                                    ring3(rect(size * 0.12, size * 0.12, x, y), cap_top)]),
             cprism(prefix + "_frame_t", rect(size / 2, size / 2, x, y), body_top - 0.16, body_top, bevel=0.03),
             cprism(prefix + "_frame_b", rect(size / 2, size / 2, x, y), body_bot, body_bot + 0.18, bevel=0.03, bottom=0.04),
             loft(prefix + "_finial", [ring3(rect(0.16, 0.16, x, y), body_bot + 0.02),
                                       ring3(rect(0.02, 0.02, x, y), body_bot - 0.32)])]
    for sx in (-1, 1):
        for sy in (-1, 1):
            metal.append(ls.cube(prefix + "_bar", size=(0.13, 0.13, height),
                                 loc=(x + sx * (size / 2 - 0.07), y + sy * (size / 2 - 0.07), body_bot + height / 2)))
    core = prism(prefix + "_core", ngon(8, size * 0.22), body_bot + 0.17, body_top - 0.15)
    at(core, x, y, 0.0)
    return metal, core, (x, y, (body_top + body_bot) / 2)


# ============================================================================================
# THE SPIRE ("the Cleft")
# ============================================================================================
TER = 3.6                           # terrace (top of the stepped base)
SOC_W, SOC_K = 8.5, 2.8             # socle chamfered-square half width / corner cut
SZ0, SZ1, SW0 = 12.9, 51.0, 6.6     # monolith: bottom z, taper end z, half width at the bottom
SPLIT_Z, TIP_Z = 26.7, 46.3         # cleft starts (hidden under band A) / stops widening (under band C)
BANDS = [(26.0, 27.4), (36.4, 37.6), (45.3, 46.8)]


def shaft_w(z):
    t = min(max((z - SZ0) / (SZ1 - SZ0), 0.0), 1.0)
    return SW0 * (1.0 - 0.545 * t ** 1.1)


def shaft_poly(z, out=0.0):
    w = shaft_w(z)
    pts = chamfer_square(w, 0.36 * w)
    return offset_convex(pts, out) if out else pts


def cleft(z):
    """Half width of the slit that splits the upper monolith along X (widens slightly with height)."""
    if z <= SPLIT_Z:
        return 0.0
    return 0.45 + 0.5 * min(1.0, (z - SPLIT_Z) / (TIP_Z - SPLIT_Z))


def build_spire():
    root = lib.begin(
        "Spire", kind="Landmark", tags=["Spire", "Landmark"],
        notes=("Hero landmark at the arena centre (origin = Arena Center). 'The Cleft': layered stone monolith split "
               "along X above z=27, bound by iron bands; a tulip-shaped iron crown of 16 flared fins holds the fire bowl. "
               "Spire_Ember = coal bed (Neon, no collision/shadow): parent the beacon PointLight + fire/smoke emitters to attachment "
               "Beacon. CrateSlot_1..4 = floor centres of the four alcoves (crate pivot on the floor, LookVector out). "
               "First tread top z=0.6 is flush with SpirePlatform; 1-stud risers, 2-stud treads up to the terrace "
               "at z=3.6. The slit faces Roblox +/-Z (Blender +/-Y), so the silhouette tells players which side "
               "they are on."))

    # --- stepped octagonal base: 40 studs across flats, walkable --------------------------------------
    tiers = [(20.0, 0.0, 0.6), (18.0, 0.5, 1.6), (16.0, 1.5, 2.6), (14.0, 2.5, TER)]
    steps = ls.join([cprism("sp_tier%d" % i, ngon(8, ap), z0, z1, bevel=0.14)
                     for i, (ap, z0, z1) in enumerate(tiers)], "sp_steps")
    add(root, steps, "Granite", collision="Default")

    # --- socle with four gabled alcoves (crates sit inside) --------------------------------------------
    socle = prism("sp_socle", chamfer_square(SOC_W, SOC_K), TER - 0.1, 12.25)
    ls.bevel(socle, 0.16, 1, 40)
    AW, AJ, AA, AB = 2.7, 8.4, 9.9, 5.2      # alcove half width, jamb top, apex, back wall distance
    profile = [(-AW, TER - 0.3), (AW, TER - 0.3), (AW, AJ), (0.0, AA), (-AW, AJ)]
    cutters = []
    for k in range(4):
        c = ls.extrude_profile("sp_cut%d" % k, profile, depth=SOC_W + 1.2 - AB)
        at(c, 0, (AB + SOC_W + 1.2) / 2, 0)
        at(c, rz=k * math.pi / 2 - math.pi / 2)
        cutters.append(c)
    boolean(socle, ls.join(cutters, "sp_cuts"))
    add(root, socle, "Stone", collision="PreciseConvexDecomposition")

    metal = []
    # alcove frames: an inverted-U of dark iron around each opening
    path = [(-AW, TER - 0.05), (-AW, AJ), (0.0, AA), (AW, AJ), (AW, TER - 0.05)]
    strip = offset_polyline(path, 0.55) + list(reversed(offset_polyline(path, -0.06)))
    for k in range(4):
        f = ls.extrude_profile("sp_frame%d" % k, strip, depth=0.5)
        ls.bevel(f, 0.05, 1, 40)
        at(f, 0, SOC_W + 0.07, 0)
        at(f, rz=k * math.pi / 2 - math.pi / 2)
        metal.append(f)
        a = k * math.pi / 2
        d = (AB + SOC_W) / 2
        lib.attach(root, "CrateSlot_%d" % (k + 1), (d * math.cos(a), d * math.sin(a), TER),
                   look=(math.cos(a), math.sin(a), 0), up=(0, 0, 1))

    # buttresses: chunky iron wedges on the diagonals, climbing the socle and tapering into band A
    wedge = [(9.5, TER - 0.1), (12.05, TER - 0.1), (12.05, 4.9), (11.75, 5.3), (11.45, 11.6), (10.95, 12.4),
             (6.6, 26.6), (6.1, 26.6), (6.9, 14.0), (8.6, 12.8), (9.5, 12.0)]
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        bt = ls.extrude_profile("sp_buttress%d" % k, wedge, depth=1.9)
        ls.bevel(bt, 0.08, 1, 40)
        metal.append(at(bt, rz=a))
        foot = cprism("sp_bfoot%d" % k, rect(1.6, 1.5, cx=11.0), TER - 0.1, TER + 0.6, bevel=0.12)
        metal.append(at(foot, rz=a))
        for z in (7.2, 9.8):
            n = Vector((math.cos(a), math.sin(a), 0.0))
            t = Vector((-math.sin(a), math.cos(a), 0.0))
            r = 11.75 - (z - 5.3) * 0.3 / 6.3
            metal.append(bolt("sp_bbolt", tuple(n * r + Vector((0, 0, z))), t, n, s=0.22, h=0.22))

    # binding bands (they bridge the slit) with bolts
    for bi, (z0, z1) in enumerate(BANDS):
        e = 0.13
        metal.append(loft("sp_band%d" % bi, [ring3(shaft_poly(z0, 0.24), z0), ring3(shaft_poly(z0 + e, 0.42), z0 + e),
                                             ring3(shaft_poly(z1 - e, 0.42), z1 - e), ring3(shaft_poly(z1, 0.24), z1)]))
        zc = (z0 + z1) / 2
        poly = shaft_poly(zc, 0.42)
        for i in range(8):
            p0, p1 = Vector(poly[i]), Vector(poly[(i + 1) % 8])
            e2 = (p1 - p0).normalized()
            nrm = Vector((e2.y, -e2.x, 0.0))
            for f in ((0.5,) if i % 2 else (0.3, 0.7)):
                mid = p0 + (p1 - p0) * f
                metal.append(bolt("sp_bolt", (mid.x, mid.y, zc), (e2.x, e2.y, 0.0), nrm, s=0.2 if bi < 2 else 0.24))
    add(root, ls.join(metal, "sp_metal"), "DarkMetal", collision="Default")

    # --- the monolith: layered strata; the upper half split in two along X ---------------------------
    seq = [("Stone", 4.6), ("DarkStone", 0.65), ("Stone", 3.3), ("Granite", 1.4), ("Stone", 3.85),
           ("Stone", 4.2), ("DarkStone", 0.6), ("Stone", 3.6), ("Granite", 1.25), ("Stone", 4.1),
           ("DarkStone", 0.55), ("Stone", 5.3), ("Granite", 2.6)]
    strata = {"Stone": [], "DarkStone": [], "Granite": [cprism("sp_cornice", chamfer_square(SOC_W + 0.5, SOC_K + 0.2),
                                                              12.0, 13.0, bevel=0.2, bottom=0.25)]}
    z = SZ0
    for i, (role, h) in enumerate(seq):
        z1 = z + h
        za = z - 0.04
        out = {"Stone": rr(-0.04, 0.06), "DarkStone": -0.2, "Granite": rr(0.1, 0.16)}[role]
        sc, tw = rr(0.99, 1.01), rr(-0.012, 0.012)
        dx, dy = rr(-0.09, 0.09), rr(-0.09, 0.09)       # hand-set courses: never perfectly stacked
        jit = [rr(-0.015, 0.015) for _ in range(8)]

        def poly_at(zz, out=out, sc=sc, tw=tw, jit=jit, dx=dx, dy=dy):
            pts = xform2(shaft_poly(zz, out), sc, tw)
            return [(x * (1 + j) + dx, y * (1 + j) + dy) for (x, y), j in zip(pts, jit)]
        lo, hi = poly_at(za), poly_at(z1)
        if z < SPLIT_Z - 1e-6:
            pieces = [prism("sp_st%d" % i, lo, za, z1, top=hi)]
        else:
            g0, g1 = cleft(max(za, SPLIT_Z + 1e-3)), cleft(z1)
            pieces = [loft("sp_st%d_%d" % (i, s), [ring3(clip_x(lo, g0, s), za), ring3(clip_x(hi, g1, s), z1)])
                      for s in (1, -1)]
        for p in pieces:
            ls.bevel(p, 0.06 if role == "DarkStone" else 0.11, 1, 40)
        strata[role] += pieces
        z = z1
    add(root, ls.join(strata["Stone"], "sp_stone"), "Stone", rgb=(130, 124, 115), collision="Default")
    add(root, ls.join(strata["DarkStone"], "sp_dark"), "DarkStone", rgb=(70, 69, 71), collision="Default")
    add(root, ls.join(strata["Granite"], "sp_granite"), "Granite", rgb=(152, 145, 133), collision="Default")

    # --- crown: an iron ring clamps both halves; eight broad radial fins flare into a cup around the fire bowl,
    #     tied by a hoop (taller fins on the diagonals, echoing the buttresses) ------------------------------
    crown = [loft("sp_crownring", [ring3(shaft_poly(47.9, 0.2), 47.9), ring3(shaft_poly(48.3, 0.55), 48.3),
                                   ring3(shaft_poly(49.0, 0.75), 49.0), ring3(shaft_poly(49.4, 0.62), 49.4)])]
    poly = shaft_poly(48.65, 0.65)
    for i in range(8):
        p0, p1 = Vector(poly[i]), Vector(poly[(i + 1) % 8])
        e2 = (p1 - p0).normalized()
        nrm = Vector((e2.y, -e2.x, 0.0))
        for f in ((0.5,) if i % 2 else (0.3, 0.7)):
            mid = p0 + (p1 - p0) * f
            crown.append(bolt("sp_cbolt", (mid.x, mid.y, 48.65), (e2.x, e2.y, 0.0), nrm, s=0.2))
    # fire bowl raised on a flared pedestal so the coals sit at the basket's mid height (visible between the bars)
    crown.append(ls.lathe("sp_pedestal", [(0.0, 49.2), (1.6, 49.2), (1.1, 49.7), (0.75, 50.4), (0.75, 50.95), (1.25, 51.25),
                                          (0.0, 51.25)], segments=8, rot=(0, 0, math.pi / 8)))
    crown.append(ls.lathe("sp_bowl", [(0.0, 50.9), (1.3, 50.9), (2.55, 51.7), (3.5, 52.85), (3.95, 53.55), (4.0, 53.8),
                                      (3.72, 53.86), (3.25, 53.05), (1.7, 52.2), (0.0, 52.1)], segments=8,
                          rot=(0, 0, math.pi / 8)))
    crown += fin_basket("sp_fin", 16, [(3.75, 48.4), (4.1, 49.6), (4.45, 51.0), (4.85, 52.5), (5.35, 54.0), (5.95, 55.5),
                                       (6.6, 57.0), (7.25, 58.3)],
                        [(3.75, 48.4), (4.1, 49.6), (4.45, 51.0), (4.85, 52.5), (5.35, 54.0), (5.95, 55.5), (6.45, 56.75)],
                        (0.26, 0.62), (0.2, 0.45))
    crown.append(band_solid("sp_hoop_lo", circle(16, 5.1), circle(16, 4.6), 52.25, 52.75))
    crown.append(band_solid("sp_hoop_hi", circle(16, 6.42), circle(16, 5.92), 55.75, 56.3))
    add(root, ls.join(crown, "sp_crown"), "DarkMetal", collision="Default")

    dome, lumps = coal_bed("sp_coal", (0, 0, 53.3), 3.35, 3.35, 1.2, 14, 0.52)
    add(root, dome, "Ember", collide=False, cast_shadow=False)
    add(root, lumps, "Basalt", collide=False, cast_shadow=False)
    lib.attach(root, "Beacon", (0, 0, 54.5), look=(0, 0, 1), up=(0, 1, 0))
    return lib.finish(root)


# ============================================================================================
# SPIRE PLATFORM (plaza ring, 120 across, 0.6 thick)
# ============================================================================================
def build_platform():
    root = lib.begin(
        "SpirePlatform", kind="Plaza", tags=["Spire"],
        notes=("Place at the same origin as the Spire, on flat ground. The octagonal hole (apothem 20) is exactly the "
               "Spire's bottom slab, so the plaza top (z=0.6) is flush with the Spire's first tread. Cobble ring "
               "r=37.5-40.5 makes a natural plinth circle (r~39); cobble spokes run on the Spire's 8 face axes."))
    N, T = 80, 0.6
    R_HOLE, R_APRON, R_RING0, R_RING1, R_CURB0, R_CURB1 = 20.0, 25.0, 37.5, 40.5, 56.6, 60.0
    HW = 1.2      # spoke half width
    EPS = 0.012   # hairline so separate pieces of one mesh never share vertices
    cobble = [band_chamfer("pf_apron", circle(N, R_APRON), ngon_sampled(8, R_HOLE, N), 0.0, T),
              band_chamfer("pf_ring", circle(N, R_RING1), circle(N, R_RING0), 0.0, T)]
    pav_a, pav_b = [], []
    for k in range(8):
        a0 = k * math.pi / 4
        a1 = a0 + math.pi / 4
        for (ri, ro, n, parity) in ((R_APRON, R_RING0, 9, 0), (R_RING1, R_CURB0, 12, 1)):
            outer = arc(ro, a0 + math.asin(HW / ro), a1 - math.asin(HW / ro), n)
            inner = arc(ri, a0 + math.asin(HW / ri), a1 - math.asin(HW / ri), n)
            sector = band_chamfer("pf_sector", outer, inner, 0.0, T, closed=False)
            (pav_a if (k + parity) % 2 == 0 else pav_b).append(sector)
            so = arc(ro - EPS, a0 - math.asin(HW / ro), a0 + math.asin(HW / ro), 3)
            si = arc(ri + EPS, a0 - math.asin(HW / ri), a0 + math.asin(HW / ri), 3)
            cobble.append(band_chamfer("pf_spoke", so, si, 0.0, T, closed=False))
    add(root, ls.join(pav_a, "pf_pav_a"), "Paving", collision="Default")
    add(root, ls.join(pav_b, "pf_pav_b"), "Paving", rgb=(110, 106, 99), collision="Default")
    add(root, ls.join(cobble, "pf_cobble"), "Cobble", rgb=(102, 96, 88), collision="Default")
    curbs = []
    gap = EPS / R_CURB1
    for k in range(16):
        b0 = (k + 0.5) * TAU / 16 + gap
        b1 = (k + 1.5) * TAU / 16 - gap
        cb = band_solid("pf_curb%d" % k, arc(R_CURB1, b0, b1, 6), arc(R_CURB0, b0, b1, 6), 0.0, 0.95, closed=False)
        ls.bevel(cb, 0.1, 1, 40)
        curbs.append(cb)
    add(root, ls.join(curbs, "pf_curbs"), "Granite", collision="Default")
    return lib.finish(root)


# ============================================================================================
# PLINTH (start pad)
# ============================================================================================
def build_plinth():
    root = lib.begin(
        "Plinth", kind="StartPad", tags=["Plinth"],
        notes=("5.5 across flats, 1.5 tall. Front (+Y Blender / Roblox LookVector) should face the Spire: the ember "
               "strip sits on the front facet. Attachment Stand = where the contender's feet go."))
    add(root, prism("pl_base", ngon(8, 2.9), 0.0, 0.98, top=ngon(8, 2.74)), "Stone", collision="Hull")
    collar = [cprism("pl_collar", ngon(8, 2.86), 0.9, 1.18, bevel=0.04, bottom=0.04)]
    for k in range(8):
        if k == 2:
            continue      # front facet carries the ember strip
        a = k * math.pi / 4
        n = Vector((math.cos(a), math.sin(a), 0.0))
        t = Vector((-math.sin(a), math.cos(a), 0.0))
        collar.append(bolt("pl_bolt", tuple(n * 2.86 + Vector((0, 0, 1.04))), t, n, s=0.08, h=0.07))
    add(root, ls.join(collar, "pl_collar"), "DarkMetal", collision="Hull")
    cap = band_solid("pl_cap", ngon_sampled(8, 2.72, 16), circle(16, 1.95), 1.12, 1.5)
    ls.bevel(cap, 0.06, 1, 40)
    add(root, cap, "Granite", collision="Hull")
    disc = ls.cylinder("pl_disc", radius=2.0, depth=0.31, segments=16, loc=(0, 0, 1.13))
    add(root, disc, "Metal", collision="Box", smooth_angle=35)
    strip = ls.cube("pl_strip", size=(1.7, 0.07, 0.12), loc=(0, 2.86, 1.04))
    add(root, strip, "Ember", collide=False, cast_shadow=False)
    lib.attach(root, "Stand", (0, 0, 1.5), look=(0, 1, 0), up=(0, 0, 1))
    return lib.finish(root)


# ============================================================================================
# LOBBY KIT
# ============================================================================================
def hip_roof(name, hx, hy, rhx, z_e, z_k, kin, z_r, thick):
    """Closed hipped-roof slab: eave rectangle -> kick ring (inset kin) -> ridge (+-rhx, 0); 45-degree hips
    when hx - rhx == hy."""
    bm = bmesh.new()
    E = [(hx, -hy), (hx, hy), (-hx, hy), (-hx, -hy)]
    K = [(hx - kin, -(hy - kin)), (hx - kin, hy - kin), (-(hx - kin), hy - kin), (-(hx - kin), -(hy - kin))]

    def layer(dz):
        e = [bm.verts.new((x, y, z_e + dz)) for x, y in E]
        k = [bm.verts.new((x, y, z_k + dz)) for x, y in K]
        return e, k, bm.verts.new((rhx, 0.0, z_r + dz)), bm.verts.new((-rhx, 0.0, z_r + dz))

    def skin(e, k, rp, rm, flip):
        faces = [[e[i], e[(i + 1) % 4], k[(i + 1) % 4], k[i]] for i in range(4)]
        faces += [[k[0], k[1], rp], [k[1], k[2], rm, rp], [k[2], k[3], rm], [k[3], k[0], rp, rm]]
        for f in faces:
            bm.faces.new(list(reversed(f)) if flip else f)

    top = layer(0.0)
    bot = layer(-thick)
    skin(*top, False)
    skin(*bot, True)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([bot[0][i], bot[0][j], top[0][j], top[0][i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def hip_caps(prefix, hx, hy, rhx, z_e, z_k, kin, z_r, r_ridge, r_hip):
    caps = [rod(prefix + "_ridge", (-rhx - 0.2, 0, z_r + 0.02), (rhx + 0.2, 0, z_r + 0.02), r_ridge, segs=6)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            e = (sx * hx, sy * hy, z_e + 0.02)
            k = (sx * (hx - kin), sy * (hy - kin), z_k + 0.02)
            r = (sx * rhx, 0.0, z_r + 0.02)
            caps += [rod(prefix + "_hip", e, k, r_hip, segs=6), rod(prefix + "_hip", k, r, r_hip, segs=6)]
    return caps


def build_pavilion():
    root = lib.begin(
        "Pavilion", kind="Building", tags=["Lobby"],
        notes=("Open timber pavilion, 24 x 16 under the eaves, ridge ~14. Deck top z=0.95 with a front step. "
               "Roof collision Hull (sloped roofs are Hull in every category); posts/floor Default; rafters, boards, "
               "caps and the lantern are non-colliding. "
               "Put a warm PointLight on attachment Lantern."))
    base = cprism("pv_base", rect(10.5, 6.5), 0.0, 0.7, bevel=0.12)
    step = cprism("pv_step", rect(4.0, 0.8, cy=7.25), 0.0, 0.42, bevel=0.08)
    add(root, ls.join([base, step], "pv_g"), "Granite", collision="Default")
    add(root, cprism("pv_deck", rect(10.1, 6.1), 0.55, 0.95, bevel=0.05), "Planks", collision="Default")

    posts = [(x, y) for x in (-9.0, -3.0, 3.0, 9.0) for y in (-5.0, 5.0)]
    feet = []
    for i, (x, y) in enumerate(posts):
        f = loft("pv_foot%d" % i, [ring3(rect(0.85, 0.85, x, y), 0.85), ring3(rect(0.85, 0.85, x, y), 1.6),
                                   ring3(rect(0.66, 0.66, x, y), 2.0)])
        ls.bevel(f, 0.06, 1, 30)
        feet.append(f)
    add(root, ls.join(feet, "pv_feet"), "Stone", collision="Default")

    wood = [ls.cube("pv_post%d" % i, size=(1.0, 1.0, 7.5), loc=(x, y, 1.95 + 3.75)) for i, (x, y) in enumerate(posts)]
    for y in (-5.0, 5.0):
        wood.append(ls.cube("pv_plate", size=(21.2, 1.15, 0.9), loc=(0, y, 9.75)))
    for x in (-9.0, -3.0, 3.0, 9.0):
        wood.append(ls.cube("pv_tie", size=(0.95, 12.3, 0.8), loc=(x, 0, 9.72)))
    for (x, y) in posts:
        for s in (-1, 1):
            if abs(x + s * 2.0) < 10.0:
                wood.append(beam("pv_brace", (x + s * 0.45, y, 7.7), (x + s * 2.05, y, 9.32), 0.42, 0.42, extend=0.25))
        sy = -1 if y > 0 else 1
        wood.append(beam("pv_brace", (x, y + sy * 0.45, 7.7), (x, y + sy * 2.05, 9.32), 0.42, 0.42, extend=0.25))
    for w in wood:
        ls.bevel(w, 0.06, 1, 40)
    add(root, ls.join(wood, "pv_wood"), "Wood", collision="Default")

    # hipped roof with a gentle kick at the eaves
    HX, HY, RHX, KIN = 12.0, 8.0, 4.0, 2.0
    Z_E, KR, Z_R = 10.15, 0.42, 13.55
    T_TILE, T_BOARD = 0.42, 0.22

    def roof_z(d):
        if d <= KIN:
            return Z_E + KR * d / KIN
        return Z_E + KR + (Z_R - Z_E - KR) * (d - KIN) / (HY - KIN)

    add(root, hip_roof("pv_tiles", HX, HY, RHX, Z_E, Z_E + KR, KIN, Z_R, T_TILE), "RoofTiles", collision="Hull")
    add(root, hip_roof("pv_boards", HX - 0.15, HY - 0.15, RHX, roof_z(0.15) - T_TILE + 0.02, Z_E + KR - T_TILE + 0.02,
                       KIN - 0.15, Z_R - T_TILE + 0.02, T_BOARD), "DarkPlanks", collide=False)

    under_t = T_TILE + T_BOARD - 0.04

    def under(d):
        return roof_z(d) - under_t

    rafters = []

    def rafter(pts, depth=0.55, width=0.38, drop=0.0):
        for (x0, y0, d0), (x1, y1, d1) in zip(pts[:-1], pts[1:]):
            rafters.append(beam("pv_rafter", (x0, y0, under(d0) - depth / 2 - drop), (x1, y1, under(d1) - depth / 2 - drop),
                                width, depth, extend=0.02))

    for x0 in (-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0):
        y_end = max(0.25, abs(x0) - RHX)
        for sy in (-1, 1):
            rafter([(x0, sy * (HY - 0.05), 0.05), (x0, sy * (HY - KIN), KIN), (x0, sy * y_end, HY - y_end)])
    for y0 in (-4.0, -2.0, 0.0, 2.0, 4.0):
        x_end = RHX + abs(y0)
        for sx in (-1, 1):
            rafter([(sx * (HX - 0.05), y0, 0.05), (sx * (HX - KIN), y0, KIN), (sx * x_end, y0, HX - x_end)])
    for sx in (-1, 1):
        for sy in (-1, 1):
            rafter([(sx * (HX - 0.05), sy * (HY - 0.05), 0.05), (sx * (HX - KIN), sy * (HY - KIN), KIN), (sx * RHX, 0.0, HY)],
                   depth=0.6, width=0.45, drop=0.12)
    ridge_bottom = under(HY) - 0.75
    rafters.append(beam("pv_ridgebeam", (-RHX - 0.3, 0, ridge_bottom + 0.35), (RHX + 0.3, 0, ridge_bottom + 0.35), 0.5, 0.7))
    add(root, ls.join(rafters, "pv_rafters"), "Wood", collide=False)

    caps = hip_caps("pv", HX, HY, RHX, Z_E, Z_E + KR, KIN, Z_R, 0.34, 0.26)
    add(root, ls.join(caps, "pv_caps"), "RoofTiles", rgb=(98, 57, 43), collide=False, smooth_angle=50)

    lm, core, centre = lantern("pv_lantern", (0.0, 0.0, ridge_bottom + 0.02), drop=1.5)
    add(root, ls.join(lm, "pv_lantern"), "DarkMetal", collide=False, smooth_angle=40)
    add(root, core, "Ember", collide=False, cast_shadow=False)
    lib.attach(root, "Lantern", centre, look=(0, 0, -1), up=(0, 1, 0))
    return lib.finish(root)


def build_brazier():
    root = lib.begin(
        "Brazier", kind="Prop", tags=["Lobby", "Fire"],
        notes=("Standing iron brazier, ~5 tall: tripod + column + octagonal bowl with a small crown of curved bars "
               "(a miniature of the Spire's crown). Brazier_Ember = coal bed (Neon, no collision/shadow): put the fire ParticleEmitter + warm "
               "PointLight on attachment Fire. Good AmbientEmitter for a fire-crackle loop."))
    metal = []
    for k in range(3):
        a = math.pi / 2 + k * TAU / 3
        radial = Vector((math.cos(a), math.sin(a), 0.0))
        tang = Vector((-math.sin(a), math.cos(a), 0.0))
        spine = [radial * r + Vector((0, 0, z)) for r, z in ((0.2, 1.62), (0.62, 1.2), (1.02, 0.62), (1.26, 0.2), (1.34, 0.08))]

        def leg_section(t):
            w = 0.15 - 0.03 * t
            return [(w, w), (-w, w), (-w, -w), (w, -w)]
        metal.append(sweep("bz_leg%d" % k, spine, leg_section, tang))
        foot = ls.cube("bz_foot%d" % k, size=(0.56, 0.42, 0.16), loc=(1.4, 0, 0.08))
        ls.bevel(foot, 0.04, 1, 40)
        metal.append(at(foot, rz=a))
    metal.append(ls.lathe("bz_knop", [(0.0, 1.3), (0.3, 1.42), (0.4, 1.6), (0.3, 1.78), (0.0, 1.9)], segments=8))
    metal.append(ls.cylinder("bz_column", radius=0.17, radius_top=0.14, depth=1.55, segments=8, loc=(0, 0, 1.8)))
    metal.append(ls.lathe("bz_collar", [(0.0, 3.0), (0.26, 3.0), (0.42, 3.2), (0.5, 3.4), (0.0, 3.4)], segments=8))
    bowl = ls.lathe("bz_bowl", [(0.0, 3.3), (0.45, 3.3), (1.15, 3.72), (1.62, 4.28), (1.78, 4.62), (1.8, 4.78),
                                (1.58, 4.8), (1.46, 4.45), (0.95, 4.06), (0.0, 4.0)], segments=8)
    metal.append(bowl)
    # a miniature of the Spire's crown: curved bars + hoop around the rim
    metal += fin_basket("bz_bar", 16, [(1.62, 4.5), (1.82, 4.82), (2.02, 5.08), (2.24, 5.32)],
                        [(1.62, 4.5), (1.82, 4.82), (1.98, 5.06), (2.1, 5.18)], (0.075, 0.12), (0.06, 0.09))
    metal.append(band_solid("bz_hoop", circle(16, 2.08), circle(16, 1.94), 4.93, 5.03))
    add(root, ls.join(metal, "bz_metal"), "DarkMetal", collision="Hull", smooth_angle=35)
    dome, lumps = coal_bed("bz_coal", (0, 0, 4.47), 1.5, 1.5, 0.42, 8, 0.25, max_polar_deg=58)
    add(root, dome, "Ember", collide=False, cast_shadow=False)
    add(root, lumps, "Basalt", collide=False, cast_shadow=False)
    lib.attach(root, "Fire", (0, 0, 4.92), look=(0, 0, 1), up=(0, 1, 0))
    return lib.finish(root)


def build_bannerpole():
    root = lib.begin(
        "BannerPole", kind="Prop", tags=["Lobby"],
        notes=("12-stud pole with a hanging cloth banner (BannerPole_Banner, non-colliding). The cut-out emblem is an "
               "original abstract mark of the cleft Spire: two leaning stone halves, the fire above, a base bar."))
    foot = loft("bp_foot", [ring3(rect(0.8, 0.8), 0.0), ring3(rect(0.8, 0.8), 0.55), ring3(rect(0.62, 0.62), 0.9)])
    ls.bevel(foot, 0.06, 1, 30)
    add(root, foot, "Stone", collision="Box")
    pole = ls.cylinder("bp_pole", radius=0.24, radius_top=0.19, depth=11.0, segments=8, loc=(0, 0, 0.8))
    add(root, pole, "Wood", collision="Box", smooth_angle=50)
    BY, BZ = 0.5, 11.0
    add(root, rod("bp_bar", (-1.95, BY, BZ), (1.95, BY, BZ), 0.13, segs=8), "Wood", collide=False, smooth_angle=50)
    bits = [ls.cylinder("bp_collar", radius=0.33, radius_top=0.31, depth=0.45, segments=8, loc=(0, 0, 0.82)),
            ls.cube("bp_bracket", size=(0.3, BY + 0.05, 0.32), loc=(0, BY / 2, BZ))]
    for sx in (-1, 1):
        bits.append(ls.uvsphere("bp_knob", radius=0.17, segments=8, rings=6, loc=(sx * 2.0, BY, BZ)))
    bits.append(loft("bp_finial", [ring3(circle(4, 0.16), 11.7), ring3(circle(4, 0.3), 11.98),
                                   ring3(circle(4, 0.00002), 12.4)], cap1=False))
    add(root, ls.join(bits, "bp_metal"), "DarkMetal", collide=False, smooth_angle=40)

    top, bottom = BZ - 0.08, 4.25
    cloth = grid_xz("bp_cloth", -1.6, 1.6, bottom, top, 8, 16)
    solidify(cloth, 0.08, 0.0)
    cuts = [
        [(-1.15, bottom - 0.4), (1.15, bottom - 0.4), (0.0, bottom + 0.85)],          # swallowtail notch
        [(-0.66, 5.95), (-0.18, 5.95), (-0.18, 8.55), (-0.5, 9.15)],                   # left stone half
        [(0.18, 5.95), (0.66, 5.95), (0.5, 8.95), (0.18, 8.45)],                       # right stone half
        [(0.0, 9.22), (0.22, 9.55), (0.0, 9.88), (-0.22, 9.55)],                       # the fire
        [(-0.95, 5.45), (0.95, 5.45), (0.95, 5.72), (-0.95, 5.72)],                    # base bar
    ]
    boolean(cloth, ls.join([ls.extrude_profile("bp_cut%d" % i, p, depth=1.0) for i, p in enumerate(cuts)], "bp_cuts"))
    triangulate(cloth)
    span = top - bottom
    for v in cloth.data.vertices:
        f = (top - v.co.z) / span
        v.co.y += BY + 0.11 * math.sin(TAU * (v.co.x + 1.6) / 2.6 + 0.5) * (0.25 + 0.75 * f) + 0.12 * f * f
    cloth.data.update()
    add(root, cloth, "Banner", collide=False, smooth_angle=60)
    return lib.finish(root)


def build_bench():
    root = lib.begin("Bench", kind="Prop", tags=["Lobby", "Seat"],
                     notes="Backless stone-and-wood bench, seat top z=1.8. Seat_1/Seat_2 attachments for sit spots.")
    legs = []
    for sx in (-1, 1):
        leg = loft("bn_leg", [ring3(rect(0.5, 0.88, sx * 2.25), 0.0), ring3(rect(0.42, 0.78, sx * 2.25), 1.47)])
        ls.bevel(leg, 0.07, 1, 30)
        legs.append(leg)
    add(root, ls.join(legs, "bn_legs"), "Stone", collision="Box")
    boards = []
    for sy in (-1, 1):
        b = ls.cube("bn_board", size=(6.3, 0.8, 0.36), loc=(rr(-0.05, 0.05), sy * 0.43, 1.62))
        ls.bevel(b, 0.06, 1, 40)
        boards.append(b)
    add(root, ls.join(boards, "bn_boards"), "Wood", collision="Box")
    for i, x in enumerate((-1.5, 1.5)):
        lib.attach(root, "Seat_%d" % (i + 1), (x, 0, 1.8), look=(0, 1, 0), up=(0, 0, 1))
    return lib.finish(root)


def build_noticeboard():
    root = lib.begin(
        "NoticeBoard", kind="Prop", tags=["Lobby"],
        notes=("NoticeBoard_Planks is a clean 8 x 6 x 0.3 box (no bevel); its +Y face (Roblox Front, -Z) is the "
               "SurfaceGui face. Attachment Board = centre of that face."))
    add(root, ls.cube("nb_board", size=(8.0, 0.3, 6.0), loc=(0, 0, 5.2)), "Planks", collision="Box")
    frame = [ls.cube("nb_ftop", size=(8.76, 0.46, 0.36), loc=(0, 0.03, 8.38)),
             ls.cube("nb_fbot", size=(8.76, 0.46, 0.36), loc=(0, 0.03, 2.02))]
    for sx in (-1, 1):
        frame.append(ls.cube("nb_fside", size=(0.38, 0.46, 6.0), loc=(sx * 4.19, 0.03, 5.2)))
    for f in frame:
        ls.bevel(f, 0.04, 1, 40)
    add(root, ls.join(frame, "nb_frame"), "DarkPlanks", collision="Box")
    wood = [ls.cube("nb_post", size=(0.62, 0.62, 9.35), loc=(sx * 4.6, 0, 0.55 + 9.35 / 2)) for sx in (-1, 1)]
    wood.append(ls.cube("nb_header", size=(9.2, 0.44, 0.52), loc=(0, 0, 8.78)))
    for w in wood:
        ls.bevel(w, 0.05, 1, 40)
    add(root, ls.join(wood, "nb_wood"), "Wood", collision="Box")
    feet = []
    for sx in (-1, 1):
        f = loft("nb_foot", [ring3(rect(0.55, 0.55, sx * 4.6), 0.0), ring3(rect(0.55, 0.55, sx * 4.6), 0.45),
                             ring3(rect(0.42, 0.42, sx * 4.6), 0.72)])
        ls.bevel(f, 0.04, 1, 30)
        feet.append(f)
    add(root, ls.join(feet, "nb_feet"), "Stone", collision="Box")
    roof = ls.extrude_profile("nb_roof", [(1.18, 9.02), (1.18, 9.36), (0.0, 10.44), (-1.18, 9.36), (-1.18, 9.02),
                                          (0.0, 10.1)], depth=10.9)
    ls.bevel(roof, 0.04, 1, 40)
    at(roof, rz=math.pi / 2)
    add(root, roof, "RoofTiles", collision="Hull")
    add(root, rod("nb_ridge", (-5.5, 0, 10.42), (5.5, 0, 10.42), 0.19, segs=6), "RoofTiles", rgb=(98, 57, 43),
        collide=False, smooth_angle=50)
    lib.attach(root, "Board", (0, 0.15, 5.2), look=(0, 1, 0), up=(0, 0, 1))
    return lib.finish(root)


def build_railing():
    root = lib.begin("Railing", kind="Railing", tags=["Lobby"],
                     notes=("8-stud segment along X (x = -4..4), 3.6 tall. Tile every 8 studs: the end posts pair up into "
                            "a double pier. All parts Box collision so the run acts as a solid barrier."))
    stone = []
    for sx in (-1, 1):
        p = ls.cube("rl_post", size=(1.0, 1.0, 3.3), loc=(sx * 3.5, 0, 1.65))
        ls.bevel(p, 0.05, 1, 40)
        stone.append(p)
    stone.append(cprism("rl_curb", rect(3.08, 0.42), 0.0, 0.55, bevel=0.07))
    add(root, ls.join(stone, "rl_stone"), "Stone", collision="Box")
    caps = [cprism("rl_cap", rect(0.56, 0.62, cx=sx * 3.44), 3.25, 3.6, bevel=0.09, bottom=0.05) for sx in (-1, 1)]
    add(root, ls.join(caps, "rl_caps"), "Granite", collision="Box")
    wood = [ls.cube("rl_top", size=(6.2, 0.56, 0.42), loc=(0, 0, 2.95)),
            ls.cube("rl_low", size=(6.2, 0.42, 0.32), loc=(0, 0, 1.1))]
    for x in (-2.1, -0.7, 0.7, 2.1):
        wood.append(ls.cube("rl_bal", size=(0.28, 0.28, 1.65), loc=(x + rr(-0.03, 0.03), 0, 2.02)))
    for w in wood:
        ls.bevel(w, 0.04, 1, 40)
    add(root, ls.join(wood, "rl_wood"), "Wood", collision="Box")
    return lib.finish(root)


def build_gate():
    root = lib.begin(
        "LobbyGate", kind="Gate", tags=["Lobby"],
        notes=("Stone archway 16 wide, 14 tall with a tiled cap roof; opening 8.9 wide, 8.9 clear at the piers, 10.9 "
               "under the keystone (lantern hangs to ~8.4). Piers + attic use PreciseConvexDecomposition so the "
               "opening stays open. Put a warm PointLight on attachment Lantern."))
    PX, PW, PD = 5.9, 1.45, 1.6
    Z_IMP0, Z_IMP1, Z_TOP = 8.3, 8.9, 12.0
    SPAN, RISE = PX - PW, 2.0
    R_ARCH = (SPAN ** 2 + RISE ** 2) / (2 * RISE)
    ZC = Z_IMP1 + RISE - R_ARCH
    th0 = math.asin(SPAN / R_ARCH)

    stone = []
    for sx in (-1, 1):
        p = ls.cube("gt_pier", size=(2 * PW, 2 * PD, Z_TOP - 0.95), loc=(sx * PX, 0, 0.95 + (Z_TOP - 0.95) / 2))
        ls.bevel(p, 0.1, 1, 40)
        stone.append(p)
    z_att = Z_IMP1 - 0.1
    attic = ls.cube("gt_attic", size=(2 * (SPAN + 0.3), 2.6, Z_TOP - z_att), loc=(0, 0, (Z_TOP + z_att) / 2))
    arc_pts = [(R_ARCH * math.sin(-th0 + 2 * th0 * i / 18), ZC + R_ARCH * math.cos(-th0 + 2 * th0 * i / 18)) for i in range(19)]
    boolean(attic, ls.extrude_profile("gt_cut", [(-SPAN, z_att - 1.0)] + arc_pts + [(SPAN, z_att - 1.0)], depth=4.0))
    stone.append(attic)
    add(root, ls.join(stone, "gt_stone"), "Stone", collision="PreciseConvexDecomposition")

    gran = []
    for sx in (-1, 1):
        gran.append(cprism("gt_plinth", rect(PW + 0.3, PD + 0.3, sx * PX), 0.0, 1.0, bevel=0.12))
        gran.append(cprism("gt_impost", rect(PW + 0.18, PD + 0.18, sx * PX), Z_IMP0, Z_IMP1, bevel=0.08, bottom=0.08))
    gran.append(cprism("gt_cornice", rect(PX + PW + 0.45, PD + 0.35), Z_TOP - 0.05, Z_TOP + 0.45, bevel=0.1, bottom=0.12))
    add(root, ls.join(gran, "gt_gran"), "Granite", collision="Default")

    vous = []
    n = 9
    dth = 2 * th0 / n
    for i in range(n):
        key = (i == n // 2)
        g = 0.004
        ta, tb = -th0 + i * dth + g, -th0 + (i + 1) * dth - g
        ri, ro = R_ARCH - 0.06, R_ARCH + (1.25 if key else 1.0)
        if key:
            ta, tb = ta - 0.012, tb + 0.012
        pts = [(ri * math.sin(ta), ZC + ri * math.cos(ta)), (ro * math.sin(ta), ZC + ro * math.cos(ta)),
               (ro * math.sin(tb), ZC + ro * math.cos(tb)), (ri * math.sin(tb), ZC + ri * math.cos(tb))]
        v = ls.extrude_profile("gt_vous%d" % i, pts, depth=3.1 if key else 2.84)
        ls.bevel(v, 0.06, 1, 40)
        vous.append(v)
    add(root, ls.join(vous, "gt_vous"), "Granite", rgb=(150, 144, 135), collide=False)

    HX, HY, KIN = 7.85, 2.5, 0.45
    RHX = HX - HY
    Z_E, Z_K, Z_R = Z_TOP + 0.4, Z_TOP + 0.5, 13.75
    add(root, hip_roof("gt_roof", HX, HY, RHX, Z_E, Z_K, KIN, Z_R, 0.36), "RoofTiles", collision="Hull")
    add(root, ls.join(hip_caps("gt", HX, HY, RHX, Z_E, Z_K, KIN, Z_R, 0.22, 0.17), "gt_caps"), "RoofTiles",
        rgb=(98, 57, 43), collide=False, smooth_angle=50)

    dark = []
    for sx in (-1, 1):
        for z in (2.8, 6.0):
            dark.append(cprism("gt_band", rect(PW + 0.07, PD + 0.07, sx * PX), z, z + 0.42, bevel=0.03, bottom=0.03))
    lm, core, centre = lantern("gt_lantern", (0.0, 0.0, ZC + R_ARCH - 0.08), drop=0.5)
    dark += lm
    add(root, ls.join(dark, "gt_dark"), "DarkMetal", collide=False)
    add(root, core, "Ember", collide=False, cast_shadow=False)
    lib.attach(root, "Lantern", centre, look=(0, 0, -1), up=(0, 1, 0))
    return lib.finish(root)


def build_steps():
    root = lib.begin("StoneSteps", kind="Stairs", tags=["Lobby"],
                     notes=("3 steps, 8 wide overall (6.6 walkable between cheeks), 1-stud risers, 2-stud treads. "
                            "Bottom step at the front (+Y); top tread z=3 meets a terrace at y=-3."))
    treads = []
    for i in range(3):
        y_front = 3.0 - 2.0 * i
        y_back = -3.0 if i == 2 else y_front - 2.0 - 0.02
        t = ls.cube("st_tread%d" % i, size=(6.6, y_front - y_back, i + 1.0),
                    loc=(rr(-0.02, 0.02), (y_front + y_back) / 2, (i + 1.0) / 2))
        ls.bevel(t, 0.07, 1, 40)
        treads.append(t)
    add(root, ls.join(treads, "st_treads"), "Granite", collision="PreciseConvexDecomposition")
    cheeks = []
    for sx in (-1, 1):
        c = ls.extrude_profile("st_cheek", [(3.0, 0.0), (3.0, 1.35), (-1.0, 3.35), (-3.0, 3.35), (-3.0, 0.0)], depth=0.75)
        ls.bevel(c, 0.06, 1, 40)
        at(c, rz=math.pi / 2)
        at(c, x=sx * 3.625)
        cheeks.append(c)
    add(root, ls.join(cheeks, "st_cheeks"), "Stone", collision="PreciseConvexDecomposition")
    return lib.finish(root)


# ============================================================================================
# Review renders (optional; never exported)
# ============================================================================================
def asset_objs(root):
    return [root] + list(root.children_recursive)


def instance(root, loc=(0, 0, 0), rz=0.0):
    holder = bpy.data.objects.new(root.name + "_inst", None)
    bpy.context.scene.collection.objects.link(holder)
    objs = [holder]
    for c in root.children:
        d = c.copy()
        bpy.context.scene.collection.objects.link(d)
        d.parent = holder
        objs.append(d)
    holder.location = loc
    holder.rotation_euler = (0, 0, rz)
    return objs


def mannequin(name, loc):
    body = ls.cylinder(name + "_b", radius=0.85, radius_top=0.75, depth=4.2, segments=12, loc=loc)
    head = ls.uvsphere(name + "_h", radius=0.62, segments=12, rings=8, loc=(loc[0], loc[1], loc[2] + 4.85))
    m = ls.join([body, head], name)
    m.data.materials.append(ls.material("Sleeve", (196, 64, 52)))
    return m


def detail_shot(path, target, cam, lens=35, show=None, res=(960, 720), ground_scale=1.0):
    scene, camobj, ground = lib._setup_preview_scene()
    scene.render.resolution_x, scene.render.resolution_y = res
    camobj.data.lens = lens
    camobj.location = Vector(cam)
    camobj.rotation_euler = (Vector(target) - Vector(cam)).to_track_quat('-Z', 'Y').to_euler()
    ground.location = (target[0], target[1], -0.05)
    ground.scale = (ground_scale, ground_scale, 1.0)
    vis = set(show) if show is not None else None
    for o in scene.objects:
        if o not in (camobj, ground):
            o.hide_render = vis is not None and o not in vis
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in scene.objects:
        o.hide_render = False
    camobj.data.lens = 50
    ground.scale = (1.0, 1.0, 1.0)
    print("DETAIL " + path)


def beauty_shot(path, target, cam, lens, show, sun_rot=(math.radians(62), 0, math.radians(-135)), res=(1280, 720)):
    """Eevee render with a warm low sun, sky light and the emissive ember - a closer stand-in for Roblox Future
    lighting than Workbench. Review only; failures are reported and ignored."""
    scene = bpy.context.scene
    old_world = scene.world
    temp = []
    try:
        engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
        scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
        scene.render.resolution_x, scene.render.resolution_y = res
        world = bpy.data.worlds.get("BeautyWorld") or bpy.data.worlds.new("BeautyWorld")
        if world.node_tree is None:
            world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.42, 0.55, 0.75, 1.0)
        bg.inputs["Strength"].default_value = 0.9
        scene.world = world
        sun = bpy.data.lights.new("BeautySun", 'SUN')
        sun.energy = 4.0
        sun.color = (1.0, 0.86, 0.7)
        sun.angle = math.radians(3.0)
        sun_obj = bpy.data.objects.new("BeautySun", sun)
        scene.collection.objects.link(sun_obj)
        sun_obj.rotation_euler = sun_rot
        temp.append(sun_obj)
        camobj = bpy.data.objects.get("_PreviewCam")
        ground = bpy.data.objects.get("_PreviewGround")
        camobj.data.lens = lens
        camobj.location = Vector(cam)
        camobj.rotation_euler = (Vector(target) - Vector(cam)).to_track_quat('-Z', 'Y').to_euler()
        ground.location = (target[0], target[1], -0.05)
        ground.scale = (3.0, 3.0, 1.0)
        vis = set(show) | {sun_obj}
        for o in scene.objects:
            if o not in (camobj, ground):
                o.hide_render = o not in vis
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("BEAUTY " + path)
    except Exception as exc:
        print("NOTE beauty render skipped: %s" % exc)
    finally:
        for o in scene.objects:
            o.hide_render = False
        for o in temp:
            bpy.data.objects.remove(o, do_unlink=True)
        scene.world = old_world
        ground = bpy.data.objects.get("_PreviewGround")
        if ground:
            ground.scale = (1.0, 1.0, 1.0)
        cam = bpy.data.objects.get("_PreviewCam")
        if cam:
            cam.data.lens = 50
        scene.render.engine = "BLENDER_WORKBENCH"


def review_renders(folder, roots):
    os.makedirs(folder, exist_ok=True)
    temp = []
    sp, pf, pl = roots["Spire"], roots["SpirePlatform"], roots["Plinth"]
    figs = [mannequin("fig_terrace", (0.0, 10.6, TER)), mannequin("fig_plaza", (6.0, 27.0, 0.6)),
            mannequin("fig_alcove", (-6.9, 0.8, TER))]
    temp += figs
    plinths = []
    for k in range(24):
        a = k * TAU / 24 + TAU / 48
        plinths += instance(pl, (39.0 * math.cos(a), 39.0 * math.sin(a), 0.6), a + math.pi / 2)
    temp += plinths
    base = asset_objs(sp) + asset_objs(pf)
    detail_shot(os.path.join(folder, "spire_base.png"), (0, 4, 7.5), (16, 50, 8.5), 30, base + figs + plinths)
    detail_shot(os.path.join(folder, "spire_crown.png"), (0, 0, 51.5), (19, 23, 60), 40, asset_objs(sp))
    detail_shot(os.path.join(folder, "spire_crown_side.png"), (0, 0, 50.5), (30, 4, 54), 40, asset_objs(sp))
    detail_shot(os.path.join(folder, "spire_far.png"), (0, 0, 28), (60, 300, 7), 50, base + plinths, ground_scale=3.0)
    detail_shot(os.path.join(folder, "spire_far_side.png"), (0, 0, 28), (300, 40, 7), 50, base + plinths, ground_scale=3.0)
    detail_shot(os.path.join(folder, "arena_centre.png"), (0, 0, 14), (0, 112, 58), 30, base + plinths + figs)
    detail_shot(os.path.join(folder, "spire_low.png"), (0, 0, 30), (12, 34, 2.2), 24, base + plinths + figs)
    beauty_shot(os.path.join(folder, "beauty_arena.png"), (0, 0, 22), (38, 105, 14), 32, base + plinths + figs)
    beauty_shot(os.path.join(folder, "beauty_crown.png"), (0, 0, 53), (16, 22, 57), 40, asset_objs(sp))
    pfig = mannequin("fig_plinth", (0.0, 0.0, 1.5))
    temp.append(pfig)
    detail_shot(os.path.join(folder, "plinth_close.png"), (0, 0, 1.6), (5.5, 9.0, 4.5), 40, asset_objs(pl) + [pfig])

    lobby = []
    layout = [("Pavilion", (0, -12, 0), 0.0), ("LobbyGate", (0, 26, 0), 0.0), ("StoneSteps", (0, 33.2, 0), 0.0),
              ("Bench", (-7.5, 5, 0), 0.0), ("Bench", (7.5, 5, 0), 0.0), ("Brazier", (-6, 14, 0), 0.0),
              ("Brazier", (6, 14, 0), 0.0), ("BannerPole", (-11, 22, 0), 0.0), ("BannerPole", (11, 22, 0), 0.0),
              ("NoticeBoard", (-15, -2, 0), -math.pi / 2)]
    for x in range(-2, 2):
        layout.append(("Railing", (8 * x + 4, -26.0, 0), math.pi))
    for y in range(-3, 3):
        layout.append(("Railing", (19.0, 8 * y + 4, 0), -math.pi / 2))
    for name, loc, rz in layout:
        lobby += instance(roots[name], loc, rz)
    lfigs = [mannequin("fig_l1", (2.0, 4.0, 0.0)), mannequin("fig_l2", (-3.0, -9.0, 0.95)), mannequin("fig_l3", (1.0, 24.5, 0.0))]
    temp += lobby + lfigs
    detail_shot(os.path.join(folder, "lobby_overview.png"), (0, 4, 4), (34, 56, 26), 30, lobby + lfigs)
    detail_shot(os.path.join(folder, "lobby_eye.png"), (0, -12, 6.5), (5, 9, 4.2), 30, lobby + lfigs)
    detail_shot(os.path.join(folder, "lobby_gate.png"), (0, 26, 6), (9, 46, 5), 35, lobby + lfigs)
    detail_shot(os.path.join(folder, "brazier_close.png"), (6, 14, 3.4), (10, 22, 6.5), 40, lobby + lfigs)
    beauty_shot(os.path.join(folder, "beauty_lobby.png"), (0, 2, 4), (30, 50, 18), 30, lobby + lfigs)
    for o in temp:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)


# ============================================================================================
# Build + export
# ============================================================================================
builders = [build_spire, build_platform, build_plinth, build_pavilion, build_brazier, build_bannerpole,
            build_bench, build_noticeboard, build_railing, build_gate, build_steps]
for b in builders:
    b()

for e in lib.assets:
    parts = ", ".join("%s=%d" % (p["name"], p["tris"]) for p in e["parts"])
    print("TRIS %s total=%d size=%s :: %s" % (e["name"], e["tris"], e["size"], parts))

detail_dir = os.environ.get("LS_DETAIL_DIR")
if detail_dir:
    review_renders(detail_dir, {e["name"]: e["root"] for e in lib.assets})

lib.export(out_dir, preview_dir)
