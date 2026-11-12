"""
lr_lobby.py - the lobby kit for the LandmarksReal set: Pavilion, LobbyGate, Brazier, BannerPole, Bench, NoticeBoard,
Railing, StoneSteps. Realistic granite, weathered oak, clay pantiles, forged iron and wool cloth on the LR sheets.
Gameplay dimensions, attachments and collision intent are those of v1 (landmarks.py). Visual parts never collide;
simple convex Collider parts (Transparency 1) carry collision.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import lr_core as C
import lr_masonry as M
import lr_parts as P
import tex_landmarks as T

TAU = 2.0 * math.pi
ROOF_ROWS = T.MISC_STRIPS["ROOF"]
RIDGE_ROWS = T.MISC_STRIPS["RIDGE"]
ROPE_ROWS = T.MISC_STRIPS["ROPE"]
ROOF_BAND = 2.0                   # slope studs per ROOF strip (two courses of pantiles)
ROOF_U = T.ROOF_PERIOD_STUDS


def coll(a, key, collision="Box", rbx="Granite", notes=""):
    return a.group(key, "Collider", collide=True, collision=collision, cast_shadow=False, rbx_material=rbx,
                   transparency=1.0, smooth_angle=None, notes=notes)


def box_coll(g, x0, x1, y0, y1, z0, z1):
    M.collider_prism(g, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1)


# =============================================================================================== roofs
def _slope_bands(prof, band):
    """prof [(d, z)] -> list of (da, za, db, zb, sa, sb) sub-bands, split at multiples of 'band' slope studs and
    at the profile breaks (each sub-band is planar)."""
    segs = []
    s = 0.0
    for (d0, z0), (d1, z1) in zip(prof[:-1], prof[1:]):
        L = math.hypot(d1 - d0, z1 - z0)
        segs.append((d0, z0, d1, z1, s, s + L))
        s += L
    cuts = sorted({round(k * band, 6) for k in range(int(s / band) + 2) if k * band < s} |
                  {round(sg[4], 6) for sg in segs} | {round(s, 6)})
    out = []
    for a, b in zip(cuts[:-1], cuts[1:]):
        if b - a < 1e-4:
            continue
        for (d0, z0, d1, z1, s0, s1) in segs:
            if s0 - 1e-6 <= a and b <= s1 + 1e-6:
                fa, fb = (a - s0) / (s1 - s0), (b - s0) / (s1 - s0)
                out.append((d0 + (d1 - d0) * fa, z0 + (z1 - z0) * fa, d0 + (d1 - d0) * fb, z0 + (z1 - z0) * fb, a, b))
                break
    return out, s


def hip_roof(tiles, under, rnd, hx, hy, prof, thick, centre=(0.0, 0.0), board_strip=True):
    """Hipped roof with 45-degree hips (ridge half length hx - hy). prof = [(d, z)] tile-top height against the
    horizontal inset d from the eave, from d = 0 up to d = hy. Pantiles in 2-stud courses on the four slopes,
    sarking boards underneath (0.75-stud planks), a fascia round the eaves. Returns the hip/ridge polylines."""
    cx, cy = centre
    faces = [((0, -1), (1, 0), hx, hy), ((0, 1), (-1, 0), hx, hy), ((1, 0), (0, 1), hy, hx), ((-1, 0), (0, -1), hy, hx)]
    bands, s_total = _slope_bands(prof, ROOF_BAND)
    pbands, _ = _slope_bands(prof, 0.75)
    for (n2, t2, L0, D0) in faces:
        n = Vector((n2[0], n2[1], 0))
        t = Vector((t2[0], t2[1], 0))
        ou = rnd.random()

        def pt(d, z, side):
            return Vector((cx, cy, 0)) + n * (D0 - d) + t * (side * max(L0 - d, 0.0)) + Vector((0, 0, z))

        for (da, za, db, zb, sa, sb) in bands:
            bm = C.new_bm()
            uv = C.uvl(bm)
            q = [pt(da, za, -1), pt(da, za, 1), pt(db, zb, 1), pt(db, zb, -1)]
            if (q[2] - q[3]).length < 1e-5:
                q = q[:3]
            vs = [bm.verts.new(p) for p in q]
            f = bm.faces.new(vs)
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
            c0 = math.floor(sa / ROOF_BAND + 1e-6) * ROOF_BAND
            for l in f.loops:
                p = l.vert.co
                s = sa if abs(p.z - za) < 1e-6 and abs((p - Vector((cx, cy, 0))).dot(n) - (D0 - da)) < 1e-4 else sb
                l[uv].uv = (p.dot(t) / ROOF_U + ou, C.strip_v(ROOF_ROWS, (s - c0) / ROOF_BAND))
            f.material_index = C.M_MISC
            tiles.add(bm)
        if under is not None:
            for (da, za, db, zb, sa, sb) in pbands:
                bm = C.new_bm()
                q = [pt(da, za - thick, -1), pt(da, za - thick, 1), pt(db, zb - thick, 1), pt(db, zb - thick, -1)]
                if (q[2] - q[3]).length < 1e-5:
                    q = q[:3]
                vs = [bm.verts.new(p) for p in q]
                f = bm.faces.new(vs)
                f.normal_update()
                if f.normal.z > 0:
                    f.normal_flip()
                rows = T.WOOD_STRIPS[rnd.choice(["PLANK0", "PLANK1", "PLANK2"])]
                k = math.floor(sa / 0.75 + 1e-6) * 0.75
                uv = C.uvl(bm)
                for l in f.loops:
                    p = l.vert.co
                    s = sa if abs(p.z - (za - thick)) < 1e-6 else sb
                    l[uv].uv = (p.dot(t) / T.TRIM_STUDS + ou, C.strip_v(rows, (s - k) / 0.75))
                f.material_index = C.M_WOOD
                under.add(bm)
        # fascia (tile edge + board edge) along this eave
        bm = C.new_bm()
        z0 = prof[0][1]
        q = [pt(0, z0 - thick, -1), pt(0, z0 - thick, 1), pt(0, z0, 1), pt(0, z0, -1)]
        f = bm.faces.new([bm.verts.new(p) for p in q])
        f.normal_update()
        if f.normal.dot(n) < 0:
            f.normal_flip()
        C.Strip(C.M_WOOD, T.WOOD_STRIPS["BEAM"], t, (0, 0, 1), z0 - thick - 0.2, z0 + 0.2, ou=ou)(bm, [f])
        (under or tiles).add(bm)
    # hips and ridge
    ridge = [Vector((cx - (hx - hy), cy, prof[-1][1])), Vector((cx + (hx - hy), cy, prof[-1][1]))]
    hips = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pts = [Vector((cx + sx * (hx - d), cy + sy * (hy - d), z)) for (d, z) in prof]
            hips.append(pts)
    return ridge, hips


def gable_roof(tiles, under, rnd, half_len, half_w, z_eave, z_ridge, thick, centre=(0.0, 0.0)):
    """Two pantiled slopes meeting at a ridge along X, eaves at y = +-half_w. Returns the ridge line."""
    cx, cy = centre
    prof = [(0.0, z_eave), (half_w, z_ridge)]
    bands, _ = _slope_bands(prof, ROOF_BAND)
    for sy in (-1, 1):
        ou = rnd.random()
        t = Vector((1, 0, 0))
        for (da, za, db, zb, sa, sb) in bands:
            for layer, z_off in (("tile", 0.0), ("under", -thick)):
                bm = C.new_bm()
                uv = C.uvl(bm)
                q = [Vector((cx - half_len, cy + sy * (half_w - da), za + z_off)),
                     Vector((cx + half_len, cy + sy * (half_w - da), za + z_off)),
                     Vector((cx + half_len, cy + sy * (half_w - db), zb + z_off)),
                     Vector((cx - half_len, cy + sy * (half_w - db), zb + z_off))]
                f = bm.faces.new([bm.verts.new(p) for p in q])
                f.normal_update()
                if (f.normal.z < 0) == (layer == "tile"):
                    f.normal_flip()
                for l in f.loops:
                    p = l.vert.co
                    s = sa if abs(p.z - (za + z_off)) < 1e-6 else sb
                    if layer == "tile":
                        l[uv].uv = (p.x / ROOF_U + ou, C.strip_v(ROOF_ROWS, s / ROOF_BAND))
                    else:
                        l[uv].uv = (p.x / T.TRIM_STUDS + ou, C.strip_v(T.WOOD_STRIPS["PLANK1"], s / max(sb, 1e-3)))
                f.material_index = C.M_MISC if layer == "tile" else C.M_WOOD
                (tiles if layer == "tile" else under).add(bm)
        # eave fascia
        bm = C.new_bm()
        q = [Vector((cx - half_len, cy + sy * half_w, z_eave - thick)), Vector((cx + half_len, cy + sy * half_w, z_eave - thick)),
             Vector((cx + half_len, cy + sy * half_w, z_eave)), Vector((cx - half_len, cy + sy * half_w, z_eave))]
        f = bm.faces.new([bm.verts.new(p) for p in q])
        f.normal_update()
        if f.normal.y * sy < 0:
            f.normal_flip()
        C.Strip(C.M_WOOD, T.WOOD_STRIPS["BEAM"], (1, 0, 0), (0, 0, 1), z_eave - thick - 0.2, z_eave + 0.2, ou=ou)(bm, [f])
        under.add(bm)
    return [Vector((cx - half_len, cy, z_ridge)), Vector((cx + half_len, cy, z_ridge))]


def half_round(g, rnd, pts, r, segs=5, lift=0.0):
    """Half-round ridge/hip tiles along a 3D polyline (semicircle on top), RIDGE strip: U along, V around."""
    pts = [Vector(p) + Vector((0, 0, lift)) for p in pts]
    bm = C.new_bm()
    uv = C.uvl(bm)
    rings = []
    cum = [0.0]
    for i in range(1, len(pts)):
        cum.append(cum[-1] + (pts[i] - pts[i - 1]).length)
    for i, p in enumerate(pts):
        tng = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = tng.cross(Vector((0, 0, 1)))
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(tng).normalized()
        if up.z < 0:
            up = -up
        rings.append([p + side * (r * math.cos(math.pi * k / segs)) + up * (r * math.sin(math.pi * k / segs))
                      for k in range(segs + 1)])
    vr = [[bm.verts.new(q) for q in ring] for ring in rings]
    ou = rnd.random()
    for i in range(len(vr) - 1):
        for k in range(segs):
            f = bm.faces.new((vr[i][k], vr[i + 1][k], vr[i + 1][k + 1], vr[i][k + 1]))
            u0, u1 = ou + cum[i] / ROOF_U, ou + cum[i + 1] / ROOF_U
            v0, v1 = C.strip_v(RIDGE_ROWS, k / segs), C.strip_v(RIDGE_ROWS, (k + 1) / segs)
            C._uv_set(f, uv, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], C.M_MISC)
    for idx in (0, len(vr) - 1):
        ring = vr[idx]
        f = bm.faces.new(ring if idx else list(reversed(ring)))
        C._uv_set(f, uv, [(ou + 0.05 * k, C.strip_v(RIDGE_ROWS, k / segs)) for k in range(segs + 1)], C.M_MISC)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g.add(bm)


# =============================================================================================== iron details
def lantern(iron, ember, rnd, hook, drop, size=0.8, height=1.15):
    """Forged iron lantern hanging 'drop' below 'hook': square frame, pyramid cap with ring, base tray and a
    glowing core (Ember part). Returns the core centre (Lantern attachment)."""
    hx, hy, hz = hook
    top = hz - drop
    s = size / 2
    P.iron_bar(iron, rnd, [(hx, hy, hz + 0.05), (hx, hy, top + 0.35)], 0.07, 0.07)
    P.ring_bar(iron, rnd, (hx, hy), 0.14, top + 0.42, 0.05, 0.05, segs=8)
    # cap pyramid
    bm = C.new_bm()
    base = [bm.verts.new((hx + sx * (s + 0.08), hy + sy * (s + 0.08), top)) for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    apex = bm.verts.new((hx, hy, top + 0.36))
    for i in range(4):
        bm.faces.new((base[i], base[(i + 1) % 4], apex))
    bm.faces.new(list(reversed(base)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    C.Strip(C.M_IRON, T.IRON_STRIPS["STRAP"], (1, 1, 0), (0, 0, 1), top - 0.05, top + 0.4, ou=rnd.random())(bm, list(bm.faces))
    iron.add(bm)
    # corner posts and rails
    z0 = top - height
    for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        P.iron_bar(iron, rnd, [(hx + sx * s, hy + sy * s, z0 - 0.06), (hx + sx * s, hy + sy * s, top)], 0.07, 0.07)
    for z in (z0, top - 0.04):
        for i, ((ax, ay), (bx, by)) in enumerate((((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1)))):
            P.iron_bar(iron, rnd, [(hx + ax * s, hy + ay * s, z), (hx + bx * s, hy + by * s, z)], 0.06, 0.06)
    # base tray
    bm = C.box_bm(size + 0.12, size + 0.12, 0.08)
    C.transform(bm, Matrix.Translation((hx, hy, z0 - 0.04)))
    bm.normal_update()
    C.Strip(C.M_IRON, T.IRON_STRIPS["STRAP"], (1, 0, 0), (0, 1, 0), hy - s - 0.1, hy + s + 0.1, ou=rnd.random())(bm, list(bm.faces))
    iron.add(bm)
    # glowing core (a candle-like flame block seen through the open frame)
    core = C.box_bm(size * 0.42, size * 0.42, height * 0.55)
    zc = z0 + height * 0.42
    C.transform(core, Matrix.Translation((hx, hy, zc)))
    C.Flat(C.M_EMBER)(core, list(core.faces))
    ember.add(core)
    return (hx, hy, zc)


def coal_bed(soot, ember, rnd, center, rad, height, n, rr):
    import lr_spire as SP
    dome = C.new_bm()
    bmesh.ops.create_icosphere(dome, subdivisions=2, radius=1.0)
    C.transform(dome, Matrix.Diagonal((rad, rad, height, 1.0)))
    C.transform(dome, Matrix.Translation(center))
    C.jitter_verts(dome, 0.02, rnd)
    C.Flat(C.M_EMBER)(dome, list(dome.faces))
    ember.add(dome)
    SP.coal_heap(soot, rnd, center, rad * 0.98, height, n, rr)


# =============================================================================================== PAVILION
def build_pavilion(lib, rnd):
    a = lib.begin("Pavilion", kind="Building", tags=["Lobby"], notes=(
        "Open timber pavilion on a granite base: 24 x 16 under the eaves, ridge ~13.6. Oak deck top y = 0.95 with a "
        "granite front step (top 0.42). Eight hewn oak posts on granite pads, wall plates, tie beams and knee braces, "
        "a hipped roof of clay pantiles (bellcast eaves) on boarded rafters, half-round ridge and hip tiles. Forged "
        "iron lantern under the ridge: put a warm PointLight on attachment Lantern (Pavilion_Ember = its glowing "
        "core, Neon). Collision: Collider parts (deck/base and step boxes, eight post boxes, a Hull roof); the "
        "timber and tiles never collide."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="base course, pads, front step")
    deck = a.group("deck", "Planks", smooth_angle=50.0, notes="oak deck boards")
    wood = a.group("wood", "Wood", smooth_angle=50.0, notes="posts, plates, ties, braces, rafters, sarking, fascia")
    tiles = a.group("tiles", "RoofTiles", smooth_angle=50.0, notes="clay pantiles, ridge and hip tiles")
    iron = a.group("iron", "DarkMetal", smooth_angle=50.0, cast_shadow=True, notes="lantern")
    ember = a.group("ember", "Ember", smooth_angle=None, cast_shadow=False, notes="lantern core: Neon")
    c_floor = coll(a, "c_floor", "Box", "Granite", "base + deck, top 0.95")
    c_step = coll(a, "c_step", "Box", "Granite", "front step, top 0.42")
    c_posts = coll(a, "c_posts", "PreciseConvexDecomposition", "Wood", "eight posts (boxes)")
    c_roof = coll(a, "c_roof", "Hull", "Slate", "roof volume")
    TOPZ = 0.95
    # --- granite base course round a timber deck
    ox, oy, w = 10.5, 6.5, 0.85
    runs = [((-ox, -oy), (ox, -oy)), ((ox, -oy), (ox, oy)), ((ox, oy), (-ox, oy)), ((-ox, oy), (-ox, -oy))]
    for (p0, p1) in runs:
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        nrm = Vector((d.y, -d.x))                     # outward (runs are CCW)
        L = (p1 - p0).length
        n = max(2, int(round(L / 3.2)))
        cuts = [0.0]
        for i in range(n - 1):
            cuts.append(L * (i + 1) / n + rnd.uniform(-0.4, 0.4))
        cuts.append(L)
        for i in range(n):
            s0, s1 = cuts[i] + (0.02 if i else 0.0), cuts[i + 1] - (0.02 if i < n - 1 else 0.0)
            q0, q1 = p0 + d * s0, p0 + d * s1
            # mitre the corners: inner edge shortened by w at the run ends
            i0 = q0 - nrm * w + (d * w if i == 0 else Vector((0, 0)))
            i1 = q1 - nrm * w - (d * w if i == n - 1 else Vector((0, 0)))
            poly = [tuple(q0), tuple(q1), tuple(i1), tuple(i0)]
            P.stone(stone, rnd, poly, 0.0, TOPZ + rnd.uniform(-0.015, 0.005), bevel=0.07, damp_z=0.0,
                    chips=rnd.choice([0, 0, 1]), jitter=0.008)
    # front step
    P.stone(stone, rnd, P.rect(4.0, 0.78, cy=7.27), 0.0, 0.42, bevel=0.07, damp_z=0.0, chips=1)
    # deck boards along X, staggered butt joints over hidden joists
    iw = ox - w - 0.02
    rows = int((2 * (oy - w)) / 0.75)
    y = -(oy - w)
    for r in range(rows):
        x = -iw
        while x < iw - 0.3:
            L = min(rnd.uniform(5.5, 8.5), iw - x)
            if iw - (x + L) < 1.2:
                L = iw - x
            P.plank(deck, rnd, (x + 0.02, y + 0.375, TOPZ - 0.1), (x + L - 0.02, y + 0.375, TOPZ - 0.1), 0.72, 0.2)
            x += L
        y += 0.75
    box_coll(c_floor, -ox, ox, -oy, oy, 0.0, TOPZ)
    box_coll(c_step, -4.0, 4.0, oy - 0.02, 8.05, 0.0, 0.42)
    # --- posts on pads
    posts = [(x, y) for x in (-9.0, -3.0, 3.0, 9.0) for y in (-5.0, 5.0)]
    PZ0, PZ1 = 1.55, 9.3
    for (x, y) in posts:
        P.stone(stone, rnd, P.rect(0.85, 0.85, x, y), TOPZ - 0.05, PZ0, top_poly=P.rect(0.66, 0.66, x, y),
                bevel=0.06, chips=rnd.choice([0, 1]))
        P.member(wood, rnd, (x, y, PZ0), (x, y, PZ1 + 0.02), 0.98, 0.98, up=(0, 1, 0), segs=1, bevel=0.06,
                 twist=rnd.uniform(-0.02, 0.02))
        box_coll(c_posts, x - 0.5, x + 0.5, y - 0.5, y + 0.5, TOPZ, PZ1)
    # wall plates (X) and tie beams (Y)
    for y in (-5.0, 5.0):
        P.member(wood, rnd, (-10.6, y, 9.75), (10.6, y, 9.75), 1.15, 0.9, segs=1, bevel=0.06)
    for x in (-9.0, -3.0, 3.0, 9.0):
        P.member(wood, rnd, (x, -6.15, 9.72), (x, 6.15, 9.72), 0.95, 0.8, up=(0, 0, 1), segs=1, bevel=0.06)
    # knee braces
    for (x, y) in posts:
        for s in (-1, 1):
            if abs(x + s * 2.0) < 10.0:
                P.member(wood, rnd, (x + s * 0.45, y, 7.65), (x + s * 2.05, y, 9.32), 0.4, 0.4, up=(0, 1, 0), segs=1,
                         bevel=0.04, extend=0.22)
        sy = -1 if y > 0 else 1
        P.member(wood, rnd, (x, y + sy * 0.45, 7.65), (x, y + sy * 2.05, 9.32), 0.4, 0.4, up=(1, 0, 0), segs=1,
                 bevel=0.04, extend=0.22)
    # --- roof: bellcast hip, pantiles on sarking on rafters
    HX, HY, KIN = 12.0, 8.0, 2.0
    Z_E, KR, Z_R = 10.15, 0.42, 13.55
    THICK = 0.5
    prof = [(0.0, Z_E), (KIN, Z_E + KR), (HY, Z_R)]
    ridge, hips = hip_roof(tiles, wood, rnd, HX, HY, prof, THICK)
    half_round(tiles, rnd, [ridge[0] + Vector((-0.25, 0, 0)), ridge[1] + Vector((0.25, 0, 0))], 0.24, lift=0.04)
    for hp in hips:
        half_round(tiles, rnd, hp, 0.2, lift=0.03)

    def under(d):
        if d <= KIN:
            z = Z_E + KR * d / KIN
        else:
            z = Z_E + KR + (Z_R - Z_E - KR) * (d - KIN) / (HY - KIN)
        return z - THICK

    def rafter(pts, depth=0.5, width=0.34):
        for (x0, y0, d0), (x1, y1, d1) in zip(pts[:-1], pts[1:]):
            P.member(wood, rnd, (x0, y0, under(d0) - depth / 2), (x1, y1, under(d1) - depth / 2), width, depth,
                     segs=1, bevel=0.035, extend=0.02)

    for x0 in (-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0):
        y_end = max(0.25, abs(x0) - (HX - HY))
        for sy in (-1, 1):
            rafter([(x0, sy * (HY - 0.3), 0.3), (x0, sy * (HY - KIN), KIN), (x0, sy * y_end, HY - y_end)])
    for y0 in (-4.0, -2.0, 0.0, 2.0, 4.0):
        x_end = (HX - HY) + abs(y0)
        for sx in (-1, 1):
            rafter([(sx * (HX - 0.3), y0, 0.3), (sx * (HX - KIN), y0, KIN), (sx * x_end, y0, HX - x_end)])
    for sx in (-1, 1):
        for sy in (-1, 1):
            rafter([(sx * (HX - 0.3), sy * (HY - 0.3), 0.3), (sx * (HX - KIN), sy * (HY - KIN), KIN),
                    (sx * (HX - HY), 0.0, HY)], depth=0.58, width=0.42)
    rb = under(HY) - 0.75
    P.member(wood, rnd, (-(HX - HY) - 0.3, 0, rb + 0.35), ((HX - HY) + 0.3, 0, rb + 0.35), 0.5, 0.7, segs=1, bevel=0.05)
    # roof collider: the tile surface's hull
    pts = []
    for (d, z) in prof:
        for sx in (-1, 1):
            for sy in (-1, 1):
                pts.append((sx * (HX - d), sy * (HY - d) if d < HY else 0.0, z))
    pts += [(sx * HX, sy * HY, Z_E - THICK) for sx in (-1, 1) for sy in (-1, 1)]
    M.collider_hull(c_roof, pts)
    centre = lantern(iron, ember, rnd, (0.0, 0.0, rb + 0.02), 1.55, size=0.85, height=1.2)
    a.attach("Lantern", centre, look=(0, 0, -1), up=(0, 1, 0))
    return a


# =============================================================================================== LOBBY GATE
def build_gate(lib, rnd):
    a = lib.begin("LobbyGate", kind="Gate", tags=["Lobby"], notes=(
        "Granite archway 16 wide, 14 tall: two ashlar piers on a projecting plinth course, moulded imposts, a "
        "segmental arch of nine voussoirs with a keystone, coursed spandrels, a cornice and a small hipped roof of "
        "clay pantiles. Opening 8.9 wide, 8.9 clear at the imposts, 10.9 under the keystone (the lantern hangs to "
        "~8.4). Old iron gate pintles on the piers. Put a warm PointLight on attachment Lantern (LobbyGate_Ember = "
        "the lantern core, Neon). Collision: Collider parts (two pier boxes, convex pieces over the arch, Hull "
        "roof); the opening stays open."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="piers, arch, spandrels, cornice")
    tiles = a.group("tiles", "RoofTiles", smooth_angle=50.0, notes="pantiles, ridge and hip tiles")
    wood = a.group("wood", "Wood", smooth_angle=50.0, notes="roof boards and fascia")
    iron = a.group("iron", "DarkMetal", smooth_angle=50.0, notes="lantern, bracket, pintles")
    ember = a.group("ember", "Ember", smooth_angle=None, cast_shadow=False, notes="lantern core: Neon")
    c_piers = coll(a, "c_piers", "PreciseConvexDecomposition", "Granite", "two piers")
    c_attic = coll(a, "c_attic", "PreciseConvexDecomposition", "Granite", "masonry over the arch (convex pieces)")
    c_roof = coll(a, "c_roof", "Hull", "Slate", "roof")
    PX, PW, PD = 5.9, 1.45, 1.6
    Z_IMP0, Z_IMP1, Z_TOP = 8.3, 8.9, 12.0
    SPAN, RISE = PX - PW, 2.0
    R_ARCH = (SPAN ** 2 + RISE ** 2) / (2 * RISE)
    ZC = Z_IMP1 + RISE - R_ARCH
    th0 = math.asin(SPAN / R_ARCH)
    O = Vector((0, 0, 0))
    X = Vector((1, 0, 0))
    # --- piers: plinth course, then ashlar courses (one or two stones, alternating), damp foot
    courses = [1.0, 2.15, 3.3, 4.45, 5.6, 6.75, 7.9, Z_IMP0]
    for sx in (-1, 1):
        cxp = sx * PX
        P.stone(stone, rnd, P.rect(PW + 0.3, PD + 0.3, cxp), 0.0, 1.0, top_poly=P.rect(PW + 0.18, PD + 0.18, cxp),
                bevel=0.08, damp_z=0.0, chips=1)
        for ci in range(len(courses) - 1):
            z0, z1 = courses[ci] + 0.02, courses[ci + 1] - 0.02
            if ci % 2 == 0:
                pieces = [(-PD, PD)]
            else:
                m = rnd.uniform(-0.5, 0.5)
                pieces = [(-PD, m - 0.02), (m + 0.02, PD)]
            for (y0, y1) in pieces:
                P.stone(stone, rnd, [(cxp - PW, y0), (cxp + PW, y0), (cxp + PW, y1), (cxp - PW, y1)], z0, z1,
                        bevel=0.07, chips=rnd.choice([0, 1]), jitter=0.01)
        # impost moulding
        P.stone(stone, rnd, P.rect(PW + 0.04, PD + 0.04, cxp), Z_IMP0, Z_IMP1, top_poly=P.rect(PW + 0.22, PD + 0.22, cxp),
                bevel=0.06)
        box_coll(c_piers, cxp - PW - 0.3, cxp + PW + 0.3, -PD - 0.3, PD + 0.3, 0.0, Z_IMP1)
        # pintles on the inner faces (an old gate hung here)
        for z in (2.2, 6.4):
            xi = sx * (PX - PW)
            P.iron_bar(iron, rnd, [(xi, PD - 0.55, z), (xi - sx * 0.35, PD - 0.55, z)], 0.12, 0.12)
            P.iron_bar(iron, rnd, [(xi - sx * 0.35, PD - 0.55, z - 0.02), (xi - sx * 0.35, PD - 0.55, z + 0.32)], 0.08, 0.08)
    # --- segmental arch: nine voussoirs and a keystone
    n = 9
    dth = 2 * th0 / n
    for i in range(n):
        key = (i == n // 2)
        g = 0.006 / R_ARCH                       # tight joints: the bevels make the groove, nothing to see through
        ta, tb = -th0 + i * dth + g, -th0 + (i + 1) * dth - g
        ri, ro = R_ARCH, R_ARCH + (1.3 if key else 1.05)
        if key:
            ta, tb = ta - 0.02, tb + 0.02
        poly = [(ri * math.sin(ta), ZC + ri * math.cos(ta)), (ro * math.sin(ta), ZC + ro * math.cos(ta)),
                (ro * math.sin(tb), ZC + ro * math.cos(tb)), (ri * math.sin(tb), ZC + ri * math.cos(tb))]
        dep = 1.55 if key else 1.42
        M.elev_block(stone, rnd, Vector((0, dep, 0)), X, Vector((0, 1, 0)), poly, 0.0, 2 * dep, bevel=0.07, gap=0.0,
                     chips=rnd.choice([0, 1]))
    # --- springer beds: masonry under each springer's radial joint, on the impost
    xv, zv = (R_ARCH + 1.05) * math.sin(th0), ZC + (R_ARCH + 1.05) * math.cos(th0)
    for sx in (-1, 1):
        poly = [(sx * (SPAN + 0.03), Z_IMP1 + 0.01), (sx * (xv + 0.6), Z_IMP1 + 0.01), (sx * (xv + 0.6), zv - 0.1),
                (sx * xv, zv + 0.02)]
        M.elev_block(stone, rnd, Vector((0, 1.3, 0)), X, Vector((0, 1, 0)), poly, 0.0, 2.6, bevel=0.05, gap=0.04)
    # --- spandrels / attic: coursed blocks above the extrados, up to the cornice
    ext_r = R_ARCH + 1.05

    def ez(x):
        return ZC + math.sqrt(max(ext_r * ext_r - x * x, 0.0)) if abs(x) < ext_r else -1e9

    def x_at(z):
        """|x| where the extrados is at height z (0 when z is above the crown)."""
        dz = z - ZC
        return math.sqrt(max(ext_r * ext_r - dz * dz, 0.0)) if dz < ext_r else 0.0

    zs = [Z_IMP1, 9.95, 11.0, Z_TOP - 0.05]
    for ci in range(len(zs) - 1):
        z0, z1 = zs[ci], zs[ci + 1]
        xc = x_at(z1)                                # inside |x| < xc the arch rises above this course
        xz0 = x_at(z0)                               # outside |x| > xz0 the extrados is below the course bottom
        for side in (-1, 1):
            outer = PX + PW
            nb = 2 if ci % 2 == 0 else 3
            span = outer - xc
            if span < 0.4:
                continue
            cuts = [xc] + sorted(xc + span * (k + 1) / nb + rnd.uniform(-0.3, 0.3) * span / nb for k in range(nb - 1)) + [outer]
            for k in range(nb):
                u0, u1 = cuts[k] + (0.004 if k else 0.0), cuts[k + 1] - (0.004 if k < nb - 1 else 0.0)
                if u1 - u0 < 0.3:
                    continue
                # bottom polyline in |x| from u0 (near the arch) to u1 (outer): rises toward the arch
                bot = []
                for u in (u0, xz0, u1):
                    if u0 - 1e-6 <= u <= u1 + 1e-6:
                        bot.append((u, min(z1 - 0.02, max(z0, ez(u)))))
                bot = sorted(set(bot))                                  # arch side (high) -> outer (low)
                poly = bot + [(u1, z1), (u0, z1)]
                if poly[0][1] >= z1 - 0.03:
                    poly = poly[1:]                                     # triangle at the arch end
                poly = [(side * u, z) for (u, z) in poly]
                M.elev_block(stone, rnd, Vector((0, 1.3, 0)), X, Vector((0, 1, 0)), poly, 0.0, 2.6, bevel=0.06,
                             gap=0.0, chips=rnd.choice([0, 0, 1]))
    # cornice
    xs = [-(PX + PW + 0.4), -3.6, 0.3, 3.9, PX + PW + 0.4]
    for k in range(4):
        x0, x1 = xs[k] + (0.025 if k else 0.0), xs[k + 1] - (0.025 if k < 3 else 0.0)
        e0, e1 = (0.05 if k == 0 else 0.0), (0.05 if k == 3 else 0.0)
        P.stone(stone, rnd, [(x0, -PD - 0.32), (x1, -PD - 0.32), (x1, PD + 0.32), (x0, PD + 0.32)], Z_TOP - 0.05,
                Z_TOP + 0.4, top_poly=[(x0 - e0, -PD - 0.37), (x1 + e1, -PD - 0.37), (x1 + e1, PD + 0.37),
                                       (x0 - e0, PD + 0.37)], bevel=0.07, chips=rnd.choice([0, 1]))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (PX - PW), sx * (PX + PW + 0.3)))
        box_coll(c_attic, x0, x1, -PD, PD, Z_IMP1, Z_TOP + 0.4)
    # attic colliders: pieces between extrados chords and the top
    for k in range(6):
        x0 = -SPAN + 2 * SPAN * k / 6
        x1 = -SPAN + 2 * SPAN * (k + 1) / 6
        def ez2(x):
            return ZC + math.sqrt(max(R_ARCH * R_ARCH - x * x, 0.0))
        M.collider_elev(c_attic, Vector((0, PD, 0)), X, Vector((0, 1, 0)),
                        [(x0, ez2(x0) - 0.02), (x1, ez2(x1) - 0.02), (x1, Z_TOP + 0.4), (x0, Z_TOP + 0.4)], 0.0, 2 * PD)
    # --- roof
    HX, HY = 7.85, 2.5
    prof = [(0.0, Z_TOP + 0.4), (0.45, Z_TOP + 0.52), (HY, 13.75)]
    ridge, hips = hip_roof(tiles, wood, rnd, HX, HY, prof, 0.3)
    half_round(tiles, rnd, [ridge[0] + Vector((-0.2, 0, 0)), ridge[1] + Vector((0.2, 0, 0))], 0.2, lift=0.03)
    for hp in hips:
        half_round(tiles, rnd, hp, 0.17, lift=0.02)
    pts = [(sx * HX, sy * HY, Z_TOP + 0.1) for sx in (-1, 1) for sy in (-1, 1)]
    pts += [(sx * (HX - HY), 0.0, 13.75) for sx in (-1, 1)]
    M.collider_hull(c_roof, pts)
    # --- lantern on a forged bracket under the keystone
    kz = ZC + R_ARCH
    P.iron_bar(iron, rnd, [(0, -0.4, kz + 0.02), (0, 0.4, kz + 0.02)], 0.1, 0.1)
    centre = lantern(iron, ember, rnd, (0.0, 0.0, kz - 0.02), 0.62, size=0.7, height=1.0)
    a.attach("Lantern", centre, look=(0, 0, -1), up=(0, 1, 0))
    return a


# =============================================================================================== BRAZIER
def build_brazier(lib, rnd):
    a = lib.begin("Brazier", kind="Prop", tags=["Lobby", "Fire"], notes=(
        "Standing forged-iron brazier ~5.3 tall: three splayed legs with scroll feet, a twisted centre column, a "
        "riveted bowl and a crown of curved bars (a miniature of the Spire's fire basket). Brazier_Ember = the coal "
        "bed (Neon, no collision/shadow) under charcoal lumps: put the fire ParticleEmitter + warm PointLight on "
        "attachment Fire. Good AmbientEmitter for a fire-crackle loop. Collision: one Hull Collider."))
    iron = a.group("iron", "DarkMetal", smooth_angle=50.0, notes="forged iron")
    soot = a.group("coals", "Basalt", smooth_angle=None, cast_shadow=False, notes="charcoal lumps")
    ember = a.group("ember", "Ember", smooth_angle=None, cast_shadow=False, notes="coal bed: Neon")
    c = coll(a, "c_brazier", "Hull", "Metal", "brazier hull")
    for k in range(3):
        ang = math.pi / 2 + k * TAU / 3
        rad = Vector((math.cos(ang), math.sin(ang), 0))
        spine = [rad * r + Vector((0, 0, z)) for (r, z) in ((0.16, 1.75), (0.62, 1.12), (1.12, 0.42), (1.4, 0.1),
                                                               (1.6, 0.12), (1.62, 0.3))]
        P.iron_bar(iron, rnd, spine, 0.15, 0.13, up=rad, section=lambda t: (1.0 - 0.3 * t, 1.0 - 0.3 * t))
    # twisted column, knop and collar
    P.iron_bar(iron, rnd, [(0, 0, 1.3 + 0.25 * i) for i in range(8)], 0.24, 0.24, twist=math.pi * 1.5, chamfer=0.2)
    knop = C.lathe_bm([(0.0, 1.38), (0.28, 1.46), (0.36, 1.62), (0.26, 1.8), (0.0, 1.86)], 8)
    C.Polar(C.M_IRON, T.IRON_STRIPS["BAR"], (0, 0, 0), 0.0, 0.4, 1, z0=1.38, z1=1.86)(knop, list(knop.faces))
    iron.add(knop)
    collar = C.lathe_bm([(0.0, 3.05), (0.24, 3.05), (0.42, 3.22), (0.5, 3.4), (0.0, 3.4)], 10)
    C.Polar(C.M_IRON, T.IRON_STRIPS["BAR"], (0, 0, 0), 0.0, 0.5, 1, z0=3.05, z1=3.4)(collar, list(collar.faces))
    iron.add(collar)
    # bowl: outer skin, rolled rim, inner skin
    prof = [(0.35, 3.32), (0.95, 3.5), (1.42, 3.85), (1.7, 4.3), (1.82, 4.66), (1.86, 4.76), (1.78, 4.8),
            (1.7, 4.66), (1.58, 4.32), (1.3, 3.95), (0.85, 3.7), (0.3, 3.62)]
    bowl = C.lathe_bm(prof, 14)
    C.Polar(C.M_IRON, T.IRON_STRIPS["STRAP"], (0, 0, 0), 0.0, 1.9, 3, z0=3.3, z1=4.8)(bowl, list(bowl.faces))
    iron.add(bowl)
    for k in range(12):
        ang = TAU * (k + 0.5) / 12
        nrm = Vector((math.cos(ang) * 0.82, math.sin(ang) * 0.82, -0.57)).normalized()
        P.rivet(iron, (1.55 * math.cos(ang), 1.55 * math.sin(ang), 4.05), nrm, r=0.06, h=0.045, segs=5)
    # crown of curved bars + hoop
    for k in range(10):
        ang = TAU * k / 10
        rad = Vector((math.cos(ang), math.sin(ang), 0))
        spine = [rad * r + Vector((0, 0, z)) for (r, z) in ((1.74, 4.6), (1.92, 4.98), (2.18, 5.32))]
        P.iron_bar(iron, rnd, spine, 0.09, 0.07, up=rad)
    P.ring_bar(iron, rnd, (0, 0), 2.04, 5.08, 0.1, 0.07, segs=16)
    coal_bed(soot, ember, rnd, (0, 0, 4.36), 1.5, 0.3, 52, (0.17, 0.3))
    pts = [(1.62 * math.cos(TAU * k / 9), 1.62 * math.sin(TAU * k / 9), 0.0) for k in range(9)]
    pts += [(2.2 * math.cos(TAU * k / 12), 2.2 * math.sin(TAU * k / 12), 5.3) for k in range(12)]
    pts += [(1.9 * math.cos(TAU * k / 12), 1.9 * math.sin(TAU * k / 12), 4.7) for k in range(12)]
    M.collider_hull(c, pts)
    a.attach("Fire", (0, 0, 4.92), look=(0, 0, 1), up=(0, 1, 0))
    return a


# =============================================================================================== BANNER POLE
def build_bannerpole(lib, rnd):
    a = lib.begin("BannerPole", kind="Prop", tags=["Lobby"], notes=(
        "12-stud oak pole in a granite socket block, iron collar, spike finial, a crossbar on a forged bracket and a "
        "hanging wool banner with the arena's own sigil, the Cleft (a stepped base, a stone monolith split down its "
        "upper half, three iron bands, a fire basket and flame) and a swallowtail hem. BannerPole_Banner is cloth: "
        "non-colliding, real back faces (DoubleSided off). Collision: two Box Colliders (block, pole)."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="socket block")
    wood = a.group("wood", "Wood", smooth_angle=50.0, notes="pole and crossbar")
    iron = a.group("iron", "DarkMetal", smooth_angle=50.0, notes="collar, bracket, finial, knobs")
    rope = a.group("rope", "Rope", smooth_angle=60.0, cast_shadow=False, notes="lashings")
    cloth = a.group("cloth", "Banner", smooth_angle=70.0, notes="banner cloth: real back faces, DoubleSided off")
    cloth.back_faces = True
    c_block = coll(a, "c_block", "Box", "Granite", "socket block")
    c_pole = coll(a, "c_pole", "Box", "Wood", "pole")
    P.stone(stone, rnd, P.rect(0.82, 0.82), 0.0, 0.92, top_poly=P.rect(0.62, 0.62), bevel=0.07, damp_z=0.0, chips=1)
    box_coll(c_block, -0.82, 0.82, -0.82, 0.82, 0.0, 0.92)
    P.pole(wood, rnd, (0, 0, 0.85), (0, 0, 11.8), 0.24, 0.19, segs=10)
    box_coll(c_pole, -0.26, 0.26, -0.26, 0.26, 0.92, 11.8)
    collar = C.lathe_bm([(0.27, 0.86), (0.31, 0.9), (0.31, 1.3), (0.27, 1.34)], 10, caps=False)
    C.Polar(C.M_IRON, T.IRON_STRIPS["STRAP"], (0, 0, 0), 0.25, 0.32, 1, z0=0.86, z1=1.34)(collar, list(collar.faces))
    iron.add(collar)
    fin = C.lathe_bm([(0.2, 11.72), (0.23, 11.8), (0.2, 11.98), (0.07, 12.15), (0.0, 12.42)], 8)
    C.Polar(C.M_IRON, T.IRON_STRIPS["BAR"], (0, 0, 0), 0.0, 0.25, 1, z0=11.7, z1=12.42)(fin, list(fin.faces))
    iron.add(fin)
    BY, BZ = 0.5, 11.0
    P.pole(wood, rnd, (-1.95, BY, BZ), (1.95, BY, BZ), 0.12, segs=8)
    P.iron_bar(iron, rnd, [(0, 0.16, BZ), (0, BY, BZ)], 0.18, 0.3)
    P.iron_bar(iron, rnd, [(0, 0.2, BZ - 0.7), (0, BY, BZ - 0.1)], 0.08, 0.08)
    for sx in (-1, 1):
        kn = C.lathe_bm([(0.0, -0.17), (0.15, -0.1), (0.17, 0.0), (0.15, 0.1), (0.0, 0.17)], 8)
        C.transform(kn, Matrix.Rotation(math.pi / 2, 4, 'Y'))
        C.transform(kn, Matrix.Translation((sx * 2.05, BY, BZ)))
        kn.normal_update()
        C.Polar(C.M_IRON, T.IRON_STRIPS["BAR"], (sx * 2.05, BY, BZ), 0.0, 0.2, 1)(kn, list(kn.faces))
        iron.add(kn)
        # rope lashings of the banner's top hem
    for xr in (-1.35, -0.45, 0.45, 1.35):
        rb = C.lathe_bm([(0.15, -0.06), (0.17, 0.0), (0.15, 0.06)], 8, caps=False)
        C.transform(rb, Matrix.Rotation(math.pi / 2, 4, 'Y'))
        C.transform(rb, Matrix.Translation((xr, BY, BZ)))
        rb.normal_update()
        C.Polar(C.M_MISC, ROPE_ROWS, (xr, BY, BZ), 0.0, 0.2, 1)(rb, list(rb.faces))
        rope.add(rb)
    # --- cloth: two-sided grid, swallowtail hem, gentle folds
    top, bottom = BZ - 0.1, 4.25
    nx, nz = 10, 18
    span = top - bottom
    t_rows = T.MISC_STRIPS["BANNER"]

    def hem(x):
        return bottom + max(0.0, 0.85 * (1.0 - abs(x) / 1.15))

    for side in (1, -1):
        bm = C.new_bm()
        uv = C.uvl(bm)
        grid = []
        for i in range(nx + 1):
            x = -1.6 + 3.2 * i / nx
            col = []
            zb = hem(x)
            for j in range(nz + 1):
                z = top - (top - zb) * j / nz
                f = (top - z) / span
                y = BY + 0.11 * math.sin(TAU * (x + 1.6) / 2.6 + 0.5) * (0.25 + 0.75 * f) + 0.12 * f * f
                y += 0.015 * side
                col.append(bm.verts.new((x, y, z)))
            grid.append(col)
        for i in range(nx):
            for j in range(nz):
                q = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
                f = bm.faces.new(q if side > 0 else tuple(reversed(q)))
                coords = []
                for l in f.loops:
                    p = l.vert.co
                    u = (top - p.z) / T.BANNER_LEN
                    v = C.strip_v(t_rows, (1.6 - p.x) / 3.2)
                    coords.append((u, v))
                C._uv_set(f, uv, coords, C.M_MISC)
        bm.normal_update()
        for f in bm.faces:
            if f.normal.y * side < 0:
                f.normal_flip()
        cloth.add(bm)
    return a


# =============================================================================================== BENCH
def build_bench(lib, rnd):
    a = lib.begin("Bench", kind="Prop", tags=["Lobby", "Seat"], notes=(
        "Backless bench: two rough granite blocks carrying two thick weathered oak planks held by forged iron "
        "straps; seat top y = 1.8. Seat_1/Seat_2 attachments for sit spots. Collision: one Box Collider."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="granite legs")
    wood = a.group("wood", "Wood", smooth_angle=50.0, notes="oak seat planks")
    iron = a.group("iron", "DarkMetal", smooth_angle=50.0, notes="straps and bolts")
    c = coll(a, "c_bench", "Box", "Wood", "bench volume, top 1.8")
    for sx in (-1, 1):
        P.stone(stone, rnd, P.rect(0.48, 0.86, sx * 2.25), 0.0, 1.45, top_poly=P.rect(0.42, 0.8, sx * 2.25),
                bevel=0.07, damp_z=0.0, chips=2, chip_depth=(0.06, 0.16), jitter=0.02)
    for sy in (-1, 1):
        P.member(wood, rnd, (-3.15, sy * 0.43, 1.62), (3.15, sy * 0.43, 1.62), 0.8, 0.36, segs=1, bevel=0.06,
                 twist=rnd.uniform(-0.01, 0.01))
    for sx in (-1, 1):
        x = sx * 2.25
        spine = [(x, -0.92, 1.3), (x, -0.9, 1.81), (x, 0.9, 1.81), (x, 0.92, 1.3)]
        P.iron_bar(iron, rnd, spine, 0.32, 0.05, chamfer=0.15)
        for sy in (-1, 1):
            P.rivet(iron, (x, sy * 0.45, 1.835), (0, 0, 1), r=0.07, h=0.04, segs=6)
    box_coll(c, -3.15, 3.15, -0.86, 0.86, 0.0, 1.8)
    for i, x in enumerate((-1.5, 1.5)):
        a.attach("Seat_%d" % (i + 1), (x, 0, 1.8), look=(0, 1, 0), up=(0, 0, 1))
    return a


# =============================================================================================== NOTICE BOARD
def build_noticeboard(lib, rnd):
    a = lib.begin("NoticeBoard", kind="Prop", tags=["Lobby"], notes=(
        "Notice board: NoticeBoard_Planks is the board, 8 x 6 x 0.3 (x -4..4, y 2.2..8.2 up, 0.3 thick) of eight "
        "flush weathered boards; its +Y face (Roblox Front, -Z) is the SurfaceGui face (the GUI sits on the part's "
        "bounding-box face, which the board fronts exactly). Attachment Board = centre of that face. Oak frame, two "
        "hewn posts on granite pads, braces, and a small pantiled gable roof. Collision: Box Collider for the "
        "board and posts, Hull Collider for the roof."))
    planks = a.group("planks", "Planks", smooth_angle=50.0, notes="the SurfaceGui board (clean flat front)")
    frame = a.group("frame", "DarkPlanks", smooth_angle=50.0, notes="board frame")
    wood = a.group("wood", "Wood", smooth_angle=50.0, notes="posts, header, braces, roof boards")
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="post pads")
    tiles = a.group("tiles", "RoofTiles", smooth_angle=50.0, notes="pantiles and ridge")
    c_body = coll(a, "c_body", "Box", "Wood", "posts and board")
    c_roof = coll(a, "c_roof", "Hull", "Slate", "roof")
    # the board: eight boards whose fronts are flush at y = +0.15, joints barely open
    for k in range(8):
        z0 = 2.2 + 0.75 * k
        strip = ["PLANK0", "PLANK1", "PLANK2"][k % 3]
        bm = C.box_bm(8.0, 0.3, 0.75 - 0.012)
        C.transform(bm, Matrix.Translation((0.0, 0.0, z0 + 0.375)))
        bm.normal_update()
        rows = T.WOOD_STRIPS[strip]
        C.Member(C.M_WOOD, rows, (1, 0, 0), (-4.0, 0.0, z0), ou=rnd.random(), strip_studs=(rows[1] - rows[0]) / T.PPS,
                 end_cell=rnd.randrange(T.WOOD_END_CELLS), stretch=True)(bm, list(bm.faces))
        planks.add(bm)
    # frame boards
    for (p0, p1, w, h) in (((-4.38, 0.03, 8.38), (4.38, 0.03, 8.38), 0.46, 0.36),
                           ((-4.38, 0.03, 2.02), (4.38, 0.03, 2.02), 0.46, 0.36)):
        P.member(frame, rnd, p0, p1, w, h, segs=1, bevel=0.04)
    for sx in (-1, 1):
        P.member(frame, rnd, (sx * 4.19, 0.03, 1.84), (sx * 4.19, 0.03, 8.56), 0.38, 0.46, up=(0, 1, 0), segs=1, bevel=0.04)
    # posts on pads, header, braces
    for sx in (-1, 1):
        x = sx * 4.6
        P.stone(stone, rnd, P.rect(0.55, 0.55, x), 0.0, 0.72, top_poly=P.rect(0.44, 0.44, x), bevel=0.05, damp_z=0.0,
                chips=1)
        P.member(wood, rnd, (x, 0, 0.72), (x, 0, 9.9), 0.62, 0.62, up=(0, 1, 0), segs=1, bevel=0.05)
        P.member(wood, rnd, (x, 0, 7.6), (x - sx * 1.1, 0, 8.6), 0.3, 0.3, up=(0, 1, 0), segs=1, bevel=0.03, extend=0.15)
    P.member(wood, rnd, (-5.2, 0, 8.78), (5.2, 0, 8.78), 0.44, 0.52, segs=1, bevel=0.04)
    P.member(wood, rnd, (-5.3, 0, 10.0), (5.3, 0, 10.0), 0.3, 0.3, segs=1, bevel=0.03)
    for sx in (-1, 0, 1):
        for sy in (-1, 1):
            P.member(wood, rnd, (sx * 4.6, sy * 1.15, 9.0), (sx * 4.6, 0.0, 9.98), 0.2, 0.22, up=(0, 0, 1), segs=1,
                     bevel=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.member(wood, rnd, (sx * 5.5, sy * 1.32, 9.18), (sx * 5.5, 0.0, 10.38), 0.1, 0.32, up=(0, 0, 1), segs=1,
                     bevel=0.02, extend=0.04)
    box_coll(c_body, -4.95, 4.95, -0.35, 0.35, 0.0, 9.0)
    # gable roof (ridge along X), pantiles on boards
    ridge = gable_roof(tiles, wood, rnd, 5.45, 1.25, 9.3, 10.4, 0.22)
    half_round(tiles, rnd, [ridge[0] + Vector((-0.05, 0, 0)), ridge[1] + Vector((0.05, 0, 0))], 0.19, lift=0.02)
    pts = [(sx * 5.45, sy * 1.25, 9.08) for sx in (-1, 1) for sy in (-1, 1)] + [(sx * 5.45, 0.0, 10.42) for sx in (-1, 1)]
    M.collider_hull(c_roof, pts)
    a.attach("Board", (0, 0.15, 5.2), look=(0, 1, 0), up=(0, 0, 1))
    return a


# =============================================================================================== RAILING
def build_railing(lib, rnd):
    a = lib.begin("Railing", kind="Railing", tags=["Lobby"], notes=(
        "8-stud segment along X (x = -4..4), 3.6 tall: granite plinth kerb, two dressed granite posts with weathered "
        "caps, oak top and bottom rails with square balusters. Tile every 8 studs: the end posts pair up into a "
        "double pier. Collision: one Box Collider, so the run acts as a solid barrier."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="kerb, posts, caps")
    wood = a.group("wood", "Wood", smooth_angle=50.0, notes="rails and balusters")
    c = coll(a, "c_rail", "Box", "Granite", "solid barrier")
    P.stone(stone, rnd, P.rect(3.0, 0.42), 0.0, 0.55, top_poly=P.rect(2.98, 0.36), bevel=0.06, damp_z=0.0, chips=1)
    for sx in (-1, 1):
        x = sx * 3.5
        P.stone(stone, rnd, P.rect(0.5, 0.5, x), 0.0, 1.65, bevel=0.06, damp_z=0.0, chips=1)
        P.stone(stone, rnd, P.rect(0.48, 0.48, x), 1.67, 3.23, bevel=0.06, chips=rnd.choice([0, 1]))
        P.stone(stone, rnd, P.rect(0.6, 0.62, x - sx * 0.04), 3.25, 3.48, top_poly=P.rect(0.5, 0.52, x - sx * 0.04),
                bevel=0.06)
        P.stone(stone, rnd, P.rect(0.5, 0.52, x - sx * 0.04), 3.48, 3.6, top_poly=P.rect(0.3, 0.32, x - sx * 0.04),
                bevel=0.04)
    P.member(wood, rnd, (-3.05, 0, 2.95), (3.05, 0, 2.95), 0.56, 0.42, segs=1, bevel=0.06)
    P.member(wood, rnd, (-3.05, 0, 1.1), (3.05, 0, 1.1), 0.42, 0.32, segs=1, bevel=0.05)
    for x in (-2.1, -1.05, 0.0, 1.05, 2.1):
        P.member(wood, rnd, (x + rnd.uniform(-0.03, 0.03), 0, 1.24), (x, 0, 2.76), 0.27, 0.27, up=(0, 1, 0), segs=1,
                 bevel=0.035)
    box_coll(c, -4.0, 4.0, -0.5, 0.5, 0.0, 3.6)
    return a


# =============================================================================================== STONE STEPS
def build_steps(lib, rnd):
    a = lib.begin("StoneSteps", kind="Stairs", tags=["Lobby"], notes=(
        "Three granite steps, 8 wide overall (6.6 walkable between the cheek walls), 1-stud risers, 2-stud treads. "
        "Bottom step at the front (+Y); the top tread (y = 3) meets a terrace at z = -3 (Roblox) behind. Each step "
        "is two long stones with worn nosings; sloped cheek walls with coping. Collision: Collider pieces (three "
        "stacked step blocks + two cheek walls, PreciseConvexDecomposition)."))
    stone = a.group("stone", "Granite", smooth_angle=50.0, notes="steps and cheeks")
    c = coll(a, "c_steps", "PreciseConvexDecomposition", "Granite", "steps + cheeks")
    for i in range(3):
        y_front = 3.0 - 2.0 * i
        z0, z1 = float(i), float(i + 1)
        m = rnd.uniform(-0.6, 0.6)
        for (x0, x1) in ((-3.3, m - 0.02), (m + 0.02, 3.3)):
            P.stone(stone, rnd, [(x0, -3.0), (x1, -3.0), (x1, y_front), (x0, y_front)], z0 + 0.01, z1,
                    bevel=0.08, damp_z=0.0 if i == 0 else None, chips=rnd.choice([0, 1, 2]), jitter=0.012,
                    top_frame=(Vector((1, 0, 0)), Vector((0, 1, 0))))
        box_coll(c, -3.3, 3.3, -3.0, y_front, z0, z1)
    prof = [(3.0, 0.0), (3.0, 1.35), (-1.0, 3.35), (-3.0, 3.35), (-3.0, 0.0)]
    for sx in (-1, 1):
        xo = sx * 3.3
        # elevation drawn in (y, z) on the plane x = xo, extruded outward 0.75 -> use the cheek's outer face frame
        Oc = Vector((sx * 4.05, 0, 0))
        Xc = Vector((0, 1, 0)) if sx > 0 else Vector((0, -1, 0))
        poly = [(y * (1 if sx > 0 else -1), z) for (y, z) in prof]
        M.elev_block(stone, rnd, Oc, Xc, Vector((sx, 0, 0)), poly, 0.0, 0.75, bevel=0.08, gap=0.0, damp_z=0.0, chips=2)
        M.collider_elev(c, Oc, Xc, Vector((sx, 0, 0)), poly, 0.0, 0.75)
        del xo
    return a


BUILDERS = {"Pavilion": build_pavilion, "LobbyGate": build_gate, "Brazier": build_brazier,
            "BannerPole": build_bannerpole, "Bench": build_bench, "NoticeBoard": build_noticeboard,
            "Railing": build_railing, "StoneSteps": build_steps}
