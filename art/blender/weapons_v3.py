"""
weapons_v3.py - WeaponsV3: every starred weapon at five looks, 1 to 5 stars (docs/design/Combat_v3.md section 5),
plus the two new weapons from the owner's 19 Nov pictures, as our own designs:
  paired_blades / paired_blades_L  two short single-edged blades, round guard, diamond cord wrap, clipped tip
  wrapped_sabre                    the one-sword fallback (same blade family, 3.4 studs)
  leaf_dagger                      leaf-shaped throwing dagger, diamond section, spiral wrap, ring pommel

Run headless (seeded, no randomness; same input -> same GLBs):
  blender --background --factory-startup --python weapons_v3.py -- <export dir> [work dir]
Writes  WeaponsV3.glb      held weapons, one model per star: <id>_t1 .. <id>_t5 (+ unstarred throwing_knife, arrow,
                           wire_snare as in WeaponsV2)
        WeaponsV3_Far.glb  far versions <id>_t<s>_Far (same grips; small trims dropped, star colours kept)
        WeaponsV3.manifest.json

Rule (Combat_v3 5.1): the silhouette stays the same at every star; detail grows inside it:
  1 Worn        notched edge, loose trailing strap, dull steel with brown-grey patches, faded wood, edge = blade tone
  2 Sound       clean edge, tidy grip
  3 Fine        fuller / bevel line, diamond cross-wrap (raised lattice), steel ferrule ring, pale honed edge
  4 Superior    brass collar and pommel cap, two engraved bands, rivet row, stitched grip edge, dark hardwood
  5 Masterwork  spine / haft inlay, layered-steel band by the edge, cord knot and tassel, maker's mark,
                near-black steel against the pale honed edge (strongest value contrast)
All matte (roughness >= 0.6, no emissive). Steel greys lean warm-neutral, never blue (blued steel read navy in the
train's daylight, WeaponLooks note 18 Nov).
Held-item convention (art/README.md section 3, WeaponsV2): grip at the origin, item along Blender +Z (Roblox +Y),
edge / front toward Blender +Y (Roblox -Z). Roblox (x, y, z) = Blender (x, z, -y). Attachments as WeaponsV2.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wv3_geo as G  # noqa: E402
from wv3_geo import R, S, T, V  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding",
                                        "BlenderExports", "WeaponsV3")
WORK = ARGS[1] if len(ARGS) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")

STAR_NAMES = ["Worn", "Sound", "Fine", "Superior", "Masterwork"]
PI = math.pi

# ------------------------------------------------------------------------------------------------ palette
# role -> five (RobloxMaterial, rgb), 1..5 stars; or one fixed (RobloxMaterial, rgb).
PAL = {
    "Blade":   [("Metal", (122, 118, 110)), ("Metal", (150, 148, 142)), ("Metal", (106, 104, 100)),
                ("Metal", (80, 78, 76)), ("Metal", (54, 52, 50))],
    "Edge":    [("Metal", (128, 124, 116)), ("Metal", (178, 176, 170)), ("Metal", (188, 186, 178)),
                ("Metal", (196, 194, 186)), ("Metal", (208, 204, 194))],
    "Fitting": [("Metal", (84, 80, 76)), ("Metal", (98, 96, 92)), ("Metal", (120, 118, 114)),
                ("Metal", (112, 110, 106)), ("Metal", (104, 102, 98))],
    "Satin":   [("Metal", (120, 116, 110)), ("Metal", (150, 150, 146)), ("Metal", (158, 158, 152)),
                ("Metal", (150, 150, 146)), ("Metal", (150, 150, 146))],
    "Wood":    [("Wood", (160, 144, 120)), ("Wood", (168, 138, 100)), ("Wood", (144, 108, 74)),
                ("Wood", (104, 74, 50)), ("Wood", (88, 60, 40))],
    "Grip":    [("Leather", (126, 106, 84)), ("Leather", (100, 72, 50)), ("Leather", (106, 76, 52)),
                ("Leather", (94, 66, 46)), ("Leather", (86, 60, 42))],
    "Ray":     [("Fabric", (104, 102, 98)), ("Fabric", (92, 90, 88)), ("Fabric", (120, 118, 112)),
                ("Fabric", (128, 126, 120)), ("Fabric", (136, 134, 128))],
    "Cord":    [("Fabric", (142, 132, 114)), ("Fabric", (86, 80, 72)), ("Fabric", (60, 58, 56)),
                ("Fabric", (52, 50, 48)), ("Fabric", (46, 44, 42))],
    "Strap":   None,
    "Wrap":    [("Fabric", (60, 58, 56)), ("Fabric", (52, 50, 48)), ("Fabric", (48, 46, 44)),
                ("Fabric", (44, 42, 40)), ("Fabric", (40, 38, 36))],
}
PAL["Strap"] = PAL["Grip"]
PAL["StrapCord"] = PAL["Cord"]
FIXED = {
    "Brass": ("Metal", (152, 122, 70)),
    "Inlay": ("Metal", (164, 132, 74)),
    "Etch": ("Metal", (40, 38, 36)),
    "LayerDark": ("Metal", (36, 34, 33)),
    "LayerLight": ("Metal", (124, 120, 112)),
    "Patch": ("Metal", (114, 100, 84)),
    "Stitch": ("Fabric", (200, 190, 164)),
    "Tassel": ("Fabric", (116, 48, 42)),         # oxblood cord (a cosmetic colour, not a hit effect)
    "Tassel2": ("Fabric", (178, 152, 98)),       # ochre cord: the left blade of the pair
    "Horn": ("Wood", (56, 48, 44)),
    "Rawhide": ("Leather", (172, 148, 112)),
    "Rope": ("Fabric", (214, 206, 184)),
    "Shaft": ("Wood", (176, 150, 112)),
    "Fletch": ("Fabric", (200, 194, 180)),
    "FletchCock": ("Fabric", (176, 92, 52)),
    "Wire": ("Metal", (156, 156, 152)),
    "Stake": ("Wood", (128, 100, 72)),
}
# role -> the Stars.applyFinish role (Shared/Stars.lua: Steel, Wood, Leather, Rope, Brass, Cord)
FINISH_ROLE = {"Blade": "Steel", "Edge": "Steel", "Fitting": "Steel", "Satin": "Steel", "Etch": "Steel",
               "LayerDark": "Steel", "LayerLight": "Steel", "Patch": "Steel", "Wire": "Steel",
               "Wood": "Wood", "Horn": "Wood", "Shaft": "Wood", "Stake": "Wood",
               "Grip": "Leather", "Rawhide": "Leather", "Strap": "Leather", "StrapCord": "Cord",
               "Cord": "Cord", "Wrap": "Cord", "Ray": "Cord", "Stitch": "Cord", "Tassel": "Cord", "Tassel2": "Cord",
               "Fletch": "Cord", "FletchCock": "Cord",
               "Brass": "Brass", "Inlay": "Brass", "Rope": "Rope"}


HANG = {"Tassel", "Tassel2", "Strap", "StrapCord"}     # soft parts that hang: left out of the silhouette check


def finish_of(role, s):
    if role in PAL:
        return PAL[role][max(1, s) - 1]
    return FIXED[role]


def rb(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4) + 0.0]


# ------------------------------------------------------------------------------------------------ asset
class Asset:
    def __init__(self, wid, s, kind, tags=(), notes="", starred=True):
        self.id, self.s, self.kind, self.tags, self.notes, self.starred = wid, s, kind, list(tags), notes, starred
        self.name = ("%s_t%d" % (wid, s)) if starred else wid
        self.geo = {}
        self.att = {}
        self.extra = {}

    def add(self, role, g, M=None):
        if g is None:
            return
        vs, fs = g
        dst = self.geo.setdefault(role, [[], []])
        off = len(dst[0])
        dst[0].extend(tuple(M @ V(v)) if M is not None else tuple(v) for v in vs)
        dst[1].extend([i + off for i in f] for f in fs)

    def attach(self, name, pos, look=(0, 0, 1), up=(0, 1, 0)):
        self.att[name] = (tuple(pos), tuple(look), tuple(up))


MATS = {}


def material(role, s):
    rmat, rgb = finish_of(role, s)
    key = (role, rgb)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("WV3_%s_%d_%d_%d" % ((role,) + tuple(rgb)))
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    col = tuple(G.srgb_to_lin(c) for c in rgb) + (1.0,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.62 if rmat == "Metal" else 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = col
    MATS[key] = m
    return m


def build(asset, x_offset, coll):
    root = bpy.data.objects.new(asset.name, None)
    coll.objects.link(root)
    root.location = (x_offset, 0, 0)
    parts, tris_total = [], 0
    lo, hi = V((1e9, 1e9, 1e9)), V((-1e9, -1e9, -1e9))
    clo, chi = V((1e9, 1e9, 1e9)), V((-1e9, -1e9, -1e9))
    for role, (vs, fs) in asset.geo.items():
        pname = "%s_%s" % (asset.name, role)
        me = bpy.data.meshes.new(pname)
        me.from_pydata(vs, [], fs)
        me.validate(clean_customdata=False)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="EAR_CLIP")
        degen = [f for f in bm.faces if f.calc_area() < 1e-9]
        if degen:
            bmesh.ops.delete(bm, geom=degen, context="FACES_ONLY")
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = False
        me.materials.append(material(role, asset.s))
        ob = bpy.data.objects.new(pname, me)
        coll.objects.link(ob)
        ob.parent = root
        tris = len(me.polygons)
        tris_total += tris
        for v in me.vertices:
            for k in range(3):
                lo[k] = min(lo[k], v.co[k])
                hi[k] = max(hi[k], v.co[k])
                if role not in HANG:
                    clo[k] = min(clo[k], v.co[k])
                    chi[k] = max(chi[k], v.co[k])
        rmat, rgb = finish_of(role, asset.s)
        parts.append({"name": pname, "role": role, "finishRole": FINISH_ROLE.get(role, "Steel"), "tris": tris,
                      "robloxMaterial": rmat, "rgb": list(rgb), "collide": False, "collision": "Box",
                      "castShadow": False, "canQuery": False, "canTouch": False})
    bmin, bmax = rb(lo), rb(hi)
    bmin, bmax = [min(a, b) for a, b in zip(bmin, bmax)], [max(a, b) for a, b in zip(bmin, bmax)]
    man = {"name": asset.name, "id": asset.id, "stars": asset.s if asset.starred else None,
           "finish": STAR_NAMES[asset.s - 1] if asset.starred else None, "kind": asset.kind,
           "starred": asset.starred, "tags": asset.tags, "notes": asset.notes,
           "origin": [round(x_offset, 4), 0.0, 0.0],
           "size": [round(b - a, 3) for a, b in zip(bmin, bmax)], "boundsMin": bmin, "boundsMax": bmax,
           "coreSize": [round(abs(rb(chi)[k] - rb(clo)[k]), 3) for k in range(3)],
           "tris": tris_total, "parts": parts,
           "attachments": {k: {"position": rb(p), "look": rb(l), "up": rb(u)} for k, (p, l, u) in asset.att.items()}}
    man.update(asset.extra)
    return root, man


# ================================================================================================ detail kit
def N(q, near=8, far=5):
    return near if q else far


def C(q, c):
    return c if q else 0.0


def grip_att(a):
    a.attach("Grip", (0, 0, 0), look=(0, 0, 1), up=(0, 1, 0))


# ---- blades: stations (z, y_back, y_front, half_thickness), as wv3_geo.blade
def bl_at(st, z):
    if z <= st[0][0]:
        return st[0][1:]
    for a, b in zip(st, st[1:]):
        if a[0] <= z <= b[0]:
            f = (z - a[0]) / max(b[0] - a[0], 1e-9)
            return tuple(a[i] + (b[i] - a[i]) * f for i in (1, 2, 3))
    return st[-1][1:]


def body_span(yb, yf, band, double):
    w = max(yf - yb, 1e-4)
    b = min(band, w * (0.3 if double else 0.45))
    return (yb + b if double else yb), yf - b


def zs_between(st, z0, z1):
    return [z0] + [s[0] for s in st if z0 + 1e-4 < s[0] < z1 - 1e-4] + [z1]


class Bl:
    def __init__(self, st, band, double=False):
        self.st, self.band, self.double = st, band, double

    def face_strip(self, z0, z1, f0, f1, lift=0.004, sides=(1, -1)):
        out = []
        for sd in sides:
            secs = []
            for z in zs_between(self.st, z0, z1):
                yb, yf, t = bl_at(self.st, z)
                y0, y1 = body_span(yb, yf, self.band, self.double)
                ya, yb_ = y0 + (y1 - y0) * f0, y0 + (y1 - y0) * f1
                xo, xi = sd * (t + lift), sd * max(t - 0.003, 0.0005)
                secs.append([(xo, ya, z), (xo, yb_, z), (xi, yb_, z), (xi, ya, z)])
            out.append(G.loft(secs))
        return G.merge(*out)

    def spine_strip(self, z0, z1, wf=0.5, lift=0.004):
        secs = []
        for z in zs_between(self.st, z0, z1):
            yb, yf, t = bl_at(self.st, z)
            w = max(t * wf, 0.003)
            secs.append([(w, yb + 0.003, z), (-w, yb + 0.003, z), (-w, yb - lift, z), (w, yb - lift, z)])
        return G.loft(secs)

    def layered(self, a, z0, z1, n, f0=0.6, f1=0.97, skew=0.05, lift=0.005):
        """Alternating dark / light parallelogram facets by the edge (our own pattern-weld look)."""
        n = max(n, int((z1 - z0) * 16))
        dz = (z1 - z0) / n
        for i in range(n):
            za = z0 + i * dz
            pts = {1: [], -1: []}
            wz = dz * (0.32 if i % 2 == 0 else 0.22)
            for zz, f in ((za, f0), (za + wz, f0), (za + skew, f1), (za + wz + skew, f1)):
                yb, yf, t = bl_at(self.st, zz)
                y0, y1 = body_span(yb, yf, self.band, self.double)
                y = y0 + (y1 - y0) * f
                for sd in (1, -1):
                    pts[sd] += [(sd * (t + lift), y, zz), (sd * max(t - 0.003, 0.0005), y, zz)]
            for sd in (1, -1):
                a.add("LayerLight", G.hull(pts[sd]))

    def patches(self, a, spots):
        for (z, dz, f0, f1, sd) in spots:
            a.add("Patch", self.face_strip(z, z + dz, f0, f1, lift=0.003, sides=(sd,)))

    def mark(self, a, z, f=0.35):
        """Maker's mark: a small punched chevron on the ricasso, one face."""
        yb, yf, t = bl_at(self.st, z)
        y0, y1 = body_span(yb, yf, self.band, self.double)
        y = y0 + (y1 - y0) * f
        for sd in (1, -1):
            for dy in (-0.012, 0.012):
                a.add("Etch", G.hull([(sd * (t + 0.004), y + dy, z), (sd * (t - 0.002), y + dy, z),
                                      (sd * (t + 0.004), y + dy * 0.2, z + 0.035), (sd * (t - 0.002), y + dy * 0.2, z + 0.035),
                                      (sd * (t + 0.004), y + dy * 1.6, z + 0.012), (sd * (t - 0.002), y + dy * 1.6, z + 0.012)]))


def notch(st, zlist, depth=0.018, half=0.028):
    """1 star: chipped notches in the cutting edge (small facet cuts, silhouette within 5%)."""
    out = list(st)
    for zn in zlist:
        for dz, d in ((-half, 0.0), (0.0, depth), (half, 0.0)):
            yb, yf, t = bl_at(st, zn + dz)
            out.append((zn + dz, yb, yf - d, t))
    out.sort(key=lambda r: r[0])
    return out


# ---- round grips and hafts
def helix(r, z0, z1, turns, phase=0.0, hand=1, w=0.011, h=0.009, ppt=6, ry=None):
    ry = r if ry is None else ry
    n = max(2, int(round(turns * ppt)) + 1)
    rings = []
    for i in range(n):
        f = i / (n - 1)
        ang = phase + hand * 2 * PI * turns * f
        z = z0 + (z1 - z0) * f
        c, s_ = math.cos(ang), math.sin(ang)
        P = V((r * c, ry * s_, z))
        rad = V((c, s_, 0)).normalized()
        k = hand * 2 * PI * turns
        tng = V((-r * s_ * k, ry * c * k, z1 - z0)).normalized()
        b = tng.cross(rad).normalized()
        ring = [P - rad * 0.003 + b * w, P + rad * h + b * w * 0.55, P + rad * h - b * w * 0.55, P - rad * 0.003 - b * w]
        rings.append([tuple(p) for p in ring])
    return G.loft(rings)


def lattice(r, z0, z1, turns, strands=2, ry=None, **kw):
    gs = []
    for k in range(strands):
        ph = 2 * PI * k / strands
        gs.append(helix(r, z0, z1, turns, phase=ph, hand=1, ry=ry, **kw))
        gs.append(helix(r, z0, z1, turns, phase=ph + PI / strands, hand=-1, ry=ry, **kw))
    return G.merge(*gs)


def box_lattice(cx, cy, hx, hy, z0, z1, turns, r=0.008):
    """Cross-laid cord round a box grip: two opposite spirals over the four corners, so each face shows X crossings."""
    corners = [(hx, hy), (-hx, hy), (-hx, -hy), (hx, -hy)]
    n = int(round(turns * 4))
    gs = []
    for hand in (1, -1):
        pts = []
        for i in range(n + 1):
            k = (i * hand) % 4
            x, y = corners[k]
            pts.append((cx + x * 1.04, cy + y * 1.04, z0 + (z1 - z0) * i / n))
        for p0, p1 in zip(pts, pts[1:]):
            gs.append(G.rod(p0, p1, r, 4))
    return G.merge(*gs)


def stud(pos, normal, r=0.017, h=0.012, n=6):
    nrm = V(normal).normalized()
    M = T(*pos) @ nrm.to_track_quat("Z", "Y").to_matrix().to_4x4()
    return G.xform(G.cyl(r, -0.004, h, n, c=0.004), M)


def stitches(p0, p1, n, normal, l=0.03, w=0.008):
    p0, p1, nrm = V(p0), V(p1), V(normal).normalized()
    d = (p1 - p0)
    gs = []
    for i in range(n):
        c = p0 + d * ((i + 0.5) / n)
        a0, a1 = c - d.normalized() * l / 2 + nrm * 0.002, c + d.normalized() * l / 2 + nrm * 0.002
        gs.append(G.rod(tuple(a0), tuple(a1), w, 4))
    return G.merge(*gs)


def tassel(a, top, length=0.3, role="Tassel", lean=(0, -0.06)):
    """Cord knot and a short two-strand tassel hanging from top along -Z."""
    x, y, z = top
    a.add(role, G.cyl(0.03, z - 0.05, z, 6, rx1=0.02, c=0.006, cx=x, cy=y))
    bot = (x + lean[0], y + lean[1], z - length)
    for dx in (-0.016, 0.016):
        a.add(role, G.rod((x + dx, y, z - 0.04), (bot[0] + dx * 1.6, bot[1], bot[2] + 0.07), 0.011, 4))
    a.add(role, G.cyl(0.024, bot[2], bot[2] + 0.09, 6, rx1=0.032, cx=bot[0], cy=bot[1]))


def strap(a, x, y, z, role="Grip"):
    role = "Strap" if role == "Grip" else "StrapCord"
    """1 star: the wrap's loose end trailing from the grip."""
    a.add(role, G.hull([(x - 0.012, y - 0.022, z), (x + 0.012, y - 0.022, z), (x - 0.012, y + 0.022, z),
                        (x + 0.012, y + 0.022, z), (x + 0.04 - 0.01, y - 0.03, z - 0.2), (x + 0.04 + 0.01, y - 0.03, z - 0.2),
                        (x + 0.04 - 0.01, y + 0.005, z - 0.2), (x + 0.04 + 0.01, y + 0.005, z - 0.2)]))


def ring_bands(a, role, r, zs, h=0.012, ry=None, n=8):
    for z in zs:
        a.add(role, G.cyl(r, z - h / 2, z + h / 2, n, ry=ry))


def haft_inlay(a, r, z0, z1, w=0.014, role="Inlay"):
    for sd in (1, -1):
        a.add(role, G.cbox(0.006, w, z1 - z0, 0, loc=(sd * (r * math.cos(PI / 8) + 0.002), 0, (z0 + z1) / 2)))


def round_grip(a, s, q, r, z0, z1, ry=None, turns=2.0, n=8):
    """Grip wrap by stars: 1 loose strap, 2 plain, 3+ diamond cross-wrap lattice."""
    a.add("Grip", G.cyl(r, z0, z1, N(q, n, 5), ry=ry, c=C(q, 0.008)))
    if q and s >= 3:
        a.add("Wrap", lattice(r, z0 + 0.01, z1 - 0.01, turns, strands=2, ry=ry))
    if q and s == 1:
        strap(a, r * 0.9, 0.0, z0 + 0.03)


# ================================================================================================ weapons
def knife(s, q):
    a = Asset("knife", s, "Weapon", ["Melee", "Blade"],
              notes="Hunting Knife. Clip-point blade with a honed bevel strip, oval guard, leather handle, pommel.")
    st = [(0.285, -0.056, 0.11, 0.013), (0.45, -0.057, 0.124, 0.013), (0.66, -0.057, 0.128, 0.012),
          (0.80, -0.05, 0.11, 0.010), (0.91, -0.022, 0.074, 0.007), (0.975, 0.004, 0.046, 0.004),
          (1.02, 0.026, 0.032, 0.0015)]
    if not q:
        st = [st[0], st[2], st[3], st[4], st[6]]
    if q and s == 1:
        st = notch(st, [0.5, 0.72])
    B = Bl(st, 0.03)
    body, edge, _ = G.blade(st, band=0.03)
    a.add("Blade", body)
    a.add("Edge", edge)
    round_grip(a, s, q, 0.048, -0.29, 0.22, ry=0.062, turns=2.0)
    fit = "Brass" if s >= 4 else "Fitting"
    a.add(fit, G.cyl(0.051, 0.22, 0.25, N(q), ry=0.066, cy=0.005))           # bolster
    a.add("Fitting", G.cbox(0.07, 0.25, 0.04, C(q, 0.01), loc=(0, 0.03, 0.265)))
    a.add("Fitting", G.cyl(0.056, -0.345, -0.29, N(q), ry=0.07, c=C(q, 0.012), cy=0.005))
    if s >= 4:
        a.add("Brass", G.cyl(0.05, -0.372, -0.345, N(q, 10, 6), ry=0.062, c=C(q, 0.008), cy=0.005))
    if q:
        if s == 1:
            B.patches(a, [(0.36, 0.12, 0.15, 0.6, 1), (0.6, 0.1, 0.3, 0.8, -1)])
        if s >= 3:
            a.add("Fitting", G.cyl(0.054, 0.195, 0.222, 8, ry=0.068))                  # ferrule ring
            a.add("Etch", B.face_strip(0.33, 0.82, 0.18, 0.3))                          # fuller line
        if s >= 4:
            a.add("Etch", B.face_strip(0.3, 0.312, 0.05, 0.95))
            a.add("Etch", B.face_strip(0.326, 0.338, 0.05, 0.95))
            for z in (-0.2, -0.05, 0.1):
                a.add("Brass", stud((0.05, 0, z), (1, 0, 0)))
                a.add("Brass", stud((-0.05, 0, z), (-1, 0, 0)))
            a.add("Stitch", stitches((0, -0.064, -0.27), (0, -0.064, 0.2), 8, (0, -1, 0)))
        if s >= 5:
            a.add("Inlay", B.spine_strip(0.3, 0.8))
            B.layered(a, 0.36, 0.8, 8)
            B.mark(a, 0.29, 0.25)
            tassel(a, (0, 0.0, -0.375), 0.3)
    grip_att(a)
    a.attach("Tip", (0, 0.03, 1.02))
    return a


def machete(s, q):
    a = Asset("machete", s, "Weapon", ["Melee", "Blade"],
              notes="Machete. Long single-edged blade widening to a clipped tip, slab handle with three rivets.")
    st = [(0.23, -0.066, 0.07, 0.010), (0.6, -0.066, 0.12, 0.009), (1.2, -0.066, 0.18, 0.008),
          (1.7, -0.066, 0.235, 0.007), (1.95, -0.066, 0.25, 0.006), (2.04, -0.01, 0.23, 0.004),
          (2.08, 0.17, 0.205, 0.0015)]
    if not q:
        st = [st[0], st[2], st[4], st[5], st[6]]
    if q and s == 1:
        st = notch(st, [1.05, 1.55], depth=0.02)
    B = Bl(st, 0.036)
    body, edge, _ = G.blade(st, band=0.036)
    a.add("Blade", body)
    a.add("Edge", edge)
    a.add("Grip", G.cbox(0.1, 0.13, 0.6, C(q, 0.028), loc=(0, 0, -0.12)))
    a.add("Fitting", G.cbox(0.11, 0.15, 0.05, C(q, 0.012), loc=(0, 0, -0.445)))
    a.add("Brass" if s >= 4 else "Fitting", G.cbox(0.092, 0.14, 0.05, C(q, 0.01), loc=(0, 0.0, 0.205)))
    if q:
        for z in (-0.3, -0.12, 0.06):
            a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.02, -0.056, 0.056, 6), M=T(0, 0, z) @ R("Y", 90))
        if s == 1:
            strap(a, 0.045, 0.0, -0.4)
            B.patches(a, [(0.5, 0.25, 0.1, 0.6, 1), (1.3, 0.2, 0.3, 0.8, -1), (1.7, 0.12, 0.15, 0.5, 1)])
        if s >= 3:
            a.add("Etch", B.face_strip(0.3, 1.9, 0.56, 0.6))                            # bevel line
            for z in (-0.38, -0.21, 0.15):                                             # tidy wrap bands
                a.add("Wrap", G.cbox(0.108, 0.138, 0.045, 0.01, loc=(0, 0, z)))
        if s >= 4:
            a.add("Etch", B.face_strip(0.3, 0.312, 0.05, 0.95))
            a.add("Etch", B.face_strip(0.326, 0.338, 0.05, 0.95))
            lan = [(0.0, 0.035 * math.cos(2 * PI * i / 8), -0.395 + 0.035 * math.sin(2 * PI * i / 8)) for i in range(8)]
            for sd in (1, -1):
                a.add("Brass", G.xform(G.sweep(lan, lambda i, t: G.rect(0.006, 0.01), ref=(1, 0, 0), closed=True),
                                       T(sd * 0.052, 0, 0)))
            a.add("Stitch", stitches((0, 0.066, -0.4), (0, 0.066, 0.16), 9, (0, 1, 0)))
        if s >= 5:
            B.layered(a, 0.5, 1.9, 12)
            a.add("Inlay", B.spine_strip(0.3, 1.92))
            B.mark(a, 0.25, 0.3)
            tassel(a, (0, 0.0, -0.43), 0.3)
    grip_att(a)
    a.attach("Tip", (0, 0.19, 2.08))
    return a


def hatchet(s, q):
    a = Asset("hatchet", s, "Weapon", ["Melee", "Axe", "Thrown", "Tool"],
              notes="Hatchet. Eight-sided haft with a flared butt, leather grip band, wedge head with a flared bit "
                    "and a honed edge, short poll, collar.")
    a.add("Wood", G.cyl(0.05, -0.32, 1.62, N(q), ry=0.07))
    a.add("Wood", G.cyl(0.062, -0.40, -0.30, N(q), ry=0.086, c=C(q, 0.012)))
    round_grip(a, s, q, 0.056, -0.24, 0.24, ry=0.077, turns=1.8)
    a.add("Brass" if s >= 4 else "Fitting", G.cbox(0.12, 0.2, 0.05, C(q, 0.01), loc=(0, 0, 1.31)))
    zc = 1.47
    a.add("Blade", G.cbox(0.13, 0.22, 0.3, C(q, 0.02), loc=(0, 0, zc)))
    rA = [(x, 0.1, z) for x in (-0.055, 0.055) for z in (zc - 0.11, zc + 0.11)]
    rB = [(x, 0.30, z) for x in (-0.032, 0.032) for z in (zc - 0.085, zc + 0.08)]
    rC = [(x, 0.44, z) for x in (-0.022, 0.022) for z in (zc - 0.23, zc + 0.23)]
    rD = [(x, 0.505, z) for x in (-0.004, 0.004) for z in (zc - 0.20, zc + 0.20)]
    a.add("Blade", G.hull(rA + rB))
    a.add("Blade", G.hull(rB + rC))
    a.add("Edge", G.hull(rC + rD))
    a.add("Blade", G.hull([(x, -0.1, z) for x in (-0.06, 0.06) for z in (zc - 0.08, zc + 0.08)] +
                          [(x, -0.17, z) for x in (-0.055, 0.055) for z in (zc - 0.07, zc + 0.07)]))
    if q:
        if s == 1:
            for sd in (1, -1):
                a.add("Patch", G.cbox(0.004, 0.09, 0.12, 0, loc=(sd * 0.066, -0.02 * sd, zc + 0.03 * sd)))
        if s >= 3:
            a.add("Fitting", G.cyl(0.058, 1.22, 1.285, 8, ry=0.078, c=0.008))           # haft ferrule
        if s >= 4:
            a.add("Brass", G.cbox(0.05, 0.1, 0.03, 0.006, loc=(0, 0.0, zc + 0.158)))    # wedge in the eye
            for z in (0.45, 0.7, 0.95):
                a.add("Brass", stud((0.05 * math.cos(PI / 8), 0, z), (1, 0, 0), r=0.015))
                a.add("Brass", stud((-0.05 * math.cos(PI / 8), 0, z), (-1, 0, 0), r=0.015))
            a.add("Stitch", stitches((0, -0.079, -0.22), (0, -0.079, 0.22), 7, (0, -1, 0)))
        if s >= 5:
            a.add("Etch", G.cbox(0.137, 0.028, 0.302, 0, loc=(0, 0.06, zc)))           # engraved cheek band
            a.add("Etch", G.cbox(0.137, 0.012, 0.302, 0, loc=(0, 0.0, zc)))
            for i in range(9):                                                           # layered edge
                z0 = zc - 0.21 + i * 0.047
                pts = []
                for sd in (1, -1):
                    pts = [(sd * 0.029, 0.37, z0), (sd * 0.022, 0.37, z0), (sd * 0.029, 0.37, z0 + 0.014),
                           (sd * 0.022, 0.37, z0 + 0.014), (sd * 0.0255, 0.435, z0 + 0.03),
                           (sd * 0.018, 0.435, z0 + 0.03), (sd * 0.0255, 0.435, z0 + 0.044),
                           (sd * 0.018, 0.435, z0 + 0.044)]
                    a.add("LayerLight", G.hull(pts))
            a.add("Grip", G.cyl(0.058, 1.12, 1.215, 8, ry=0.078, c=0.006))              # leather collar
            a.add("Stitch", stitches((0, -0.08, 1.125), (0, -0.08, 1.21), 3, (0, -1, 0), l=0.022))
            a.add("Stitch", stitches((0, 0.08, 1.125), (0, 0.08, 1.21), 3, (0, 1, 0), l=0.022))
            haft_inlay(a, 0.05, 0.3, 1.1, w=0.012)
    grip_att(a)
    a.attach("Tip", (0, 0.5, zc), look=(0, 1, 0), up=(0, 0, 1))
    return a


def spear(s, q):
    a = Asset("spear", s, "Weapon", ["Melee", "Polearm", "Thrown"],
              notes="Spear. Pale stave shaft, leather grip, cord binding, socket and butt cap, leaf-shaped head.")
    a.add("Wood", G.cyl(0.065, -2.52, 3.74, N(q)))
    a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.068, -2.62, -2.5, N(q), c=C(q, 0.015)))
    round_grip(a, s, q, 0.072, -0.36, 0.36, turns=2.4)
    if q and s >= 4:
        for i in range(4):
            a.add("Cord" if i % 2 == 0 else "Tassel2", G.cyl(0.075, 3.58 + i * 0.035, 3.58 + (i + 1) * 0.035, 8))
    else:
        a.add("Cord", G.cyl(0.074, 3.58, 3.72, N(q)))
    a.add("Fitting", G.cyl(0.075, 3.72, 3.95, N(q), rx1=0.045))
    st = [(3.92, -0.05, 0.05, 0.03), (4.05, -0.13, 0.13, 0.022), (4.15, -0.14, 0.14, 0.018),
          (4.28, -0.08, 0.08, 0.010), (4.40, -0.004, 0.004, 0.002)]
    if q and s == 1:
        st = notch(st, [4.2], depth=0.02, half=0.025)
    B = Bl(st, 0.035, double=True)
    body, ef, eb = G.blade(st, band=0.035, double=True)
    a.add("Blade", body)
    a.add("Edge", ef)
    a.add("Edge", eb)
    if q:
        if s == 1:
            B.patches(a, [(4.02, 0.1, 0.1, 0.5, 1)])
            a.add("Patch", G.cyl(0.07, -2.3, -2.12, 8))
        if s >= 3:
            a.add("Fitting", G.cyl(0.082, 3.70, 3.75, 8, c=0.008))                     # socket ferrule
            a.add("Edge", B.face_strip(3.98, 4.34, 0.46, 0.54))                         # head bevel line
        if s >= 4:
            a.add("Brass", G.cyl(0.07, 3.86, 3.9, 8, rx1=0.064))                        # socket ring
            a.add("Brass", G.cyl(0.06, -2.66, -2.62, 8, c=0.01))                        # butt cap
        if s >= 5:
            a.add("Etch", B.face_strip(3.995, 4.015, 0.04, 0.96))
            a.add("Etch", B.face_strip(4.03, 4.05, 0.04, 0.96))
            haft_inlay(a, 0.065, 0.45, 3.5)
            haft_inlay(a, 0.065, -2.45, -0.45)
            tassel(a, (0.0, 0.07, 3.6), 0.3, lean=(0, 0.04))
    grip_att(a)
    a.attach("Tip", (0, 0, 4.4))
    return a


def sword(s, q):
    a = Asset("sword", s, "Weapon", ["Melee", "Blade"],
              notes="Longsword: long straight single-edged blade with a raised back spine, square crossguard, "
                    "grip of stacked rings, disc pommel. 5 stars: clipped tip.")
    st = [(0.41, -0.07, 0.09, 0.016), (1.2, -0.07, 0.09, 0.015), (2.2, -0.066, 0.085, 0.013),
          (2.85, -0.06, 0.075, 0.010), (3.08, -0.035, 0.04, 0.006), (3.2, -0.002, 0.006, 0.002)]
    tip = (0, 0.003, 3.2)
    if s >= 5:
        st = st[:4] + [(3.0, -0.059, 0.072, 0.009), (3.2, -0.05, -0.04, 0.003)]
        tip = (0, -0.045, 3.2)
    if not q:
        st = [st[0], st[2], st[3], st[4], st[5]]
    if q and s == 1:
        st = notch(st, [1.45, 2.35], depth=0.02)
    B = Bl(st, 0.036)
    body, edge, _ = G.blade(st, band=0.036)
    a.add("Blade", body)
    a.add("Edge", edge)
    a.add("Blade", G.cbox(0.038, 0.02, 2.5, 0, loc=(0, -0.066, 1.66)))
    a.add("Fitting", G.cbox(0.13, 0.44, 0.08, C(q, 0.016), loc=(0, 0.01, 0.37)))
    if q:
        z, h = -0.33, 0.66 / 7
        for i in range(7):
            r = 0.062 if i % 2 == 0 else 0.055
            a.add("Grip" if (s < 3 or i % 2 == 1) else "Wrap", G.cyl(r, z + i * h, z + (i + 1) * h, 8, c=0.008))
    else:
        a.add("Grip", G.cyl(0.06, -0.33, 0.33, 5))
    a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.11, -0.035, 0.035, N(q), c=C(q, 0.012)),
          M=T(0, 0, -0.41) @ R("Y", 90))
    if q:
        if s == 1:
            strap(a, 0.055, 0.0, -0.3)
            B.patches(a, [(0.7, 0.3, 0.1, 0.6, 1), (1.8, 0.25, 0.2, 0.7, -1), (2.5, 0.15, 0.1, 0.5, 1)])
        if s >= 3:
            a.add("Etch", B.face_strip(0.5, 2.5, 0.22, 0.36))                           # fuller
            a.add("Fitting", G.cyl(0.066, 0.31, 0.335, 8, c=0.006))                     # ferrule
        if s >= 4:
            for sd in (1, -1):
                a.add("Brass", G.cbox(0.15, 0.05, 0.1, 0.012, loc=(0, 0.01 + sd * 0.2, 0.37)))
            a.add("Etch", B.face_strip(0.47, 0.485, 0.04, 0.96))
            a.add("Etch", B.face_strip(0.505, 0.52, 0.04, 0.96))
        if s >= 5:
            a.add("Inlay", G.cbox(0.02, 0.008, 2.3, 0, loc=(0, -0.0775, 1.6)))         # inlay on the raised spine
            B.layered(a, 0.6, 2.7, 14)
            B.mark(a, 0.43, 0.5)
            tassel(a, (0, 0.0, -0.45), 0.32)
    grip_att(a)
    a.attach("Tip", tip)
    return a


def twin_axe(s, q):
    a = Asset("twin_axe", s, "Weapon", ["Melee", "Axe", "Thrown", "Heavy"],
              notes="Twin-Bit Axe: long pale haft, leather band, collar, two mirrored flared bits.")
    a.add("Wood", G.cyl(0.06, -0.6, 2.72, N(q), ry=0.075))
    a.add("Wood", G.cyl(0.07, -0.68, -0.56, N(q), ry=0.086, c=C(q, 0.014)))
    round_grip(a, s, q, 0.066, -0.38, 0.38, ry=0.081, turns=2.4)
    a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.076, 2.14, 2.27, N(q), ry=0.092, c=C(q, 0.01)))
    zc = 2.5
    a.add("Blade", G.cbox(0.18, 0.26, 0.5, C(q, 0.025), loc=(0, 0, zc)))
    a.add("Fitting", G.cbox(0.13, 0.15, 0.05, C(q, 0.01), loc=(0, 0, zc + 0.27)))
    arc = [(0.62, 0.42), (0.685, 0.22), (0.705, 0.0), (0.685, -0.22), (0.62, -0.42)]
    for sd in (1, -1):
        rA = [(x, sd * 0.12, zc + dz) for x in (-0.07, 0.07) for dz in (-0.2, 0.2)]
        rB = [(x, sd * 0.30, zc + dz) for x in (-0.045, 0.045) for dz in (-0.13, 0.13)]
        rC = [(x, sd * yy, zc + dz) for x in (-0.026, 0.026) for (yy, dz) in arc]
        a.add("Blade", G.hull(rA + rB))
        a.add("Blade", G.hull(rB + rC))
        cen = V((0, sd * 0.25, zc))
        for i in range(len(arc) - 1):
            pts = []
            for (yy, dz) in (arc[i], arc[i + 1]):
                p = V((0, sd * yy, zc + dz))
                d = (p - cen).normalized()
                pts += [(x, p.y, p.z) for x in (-0.026, 0.026)]
                o = p + d * 0.075
                pts += [(x, o.y, o.z) for x in (-0.004, 0.004)]
            a.add("Edge", G.hull(pts))
        if q and s == 1:
            for xs in (1, -1):
                poly = [(0.34, 0.02), (0.4, 0.09), (0.47, 0.07), (0.5, -0.02), (0.44, -0.07), (0.37, -0.05)]
                a.add("Patch", G.hull([(xs * xx, sd * yy, zc + dz) for (yy, dz) in poly
                                       for xx in (0.024 + 0.04 * (0.62 - yy) / 0.3 * 0.55 + 0.004, 0.012)]))
        if q and s >= 5:                                   # layered steel band along each bit's arc
            for i in range(len(arc) - 1):
                for xs in (1, -1):
                    (y0, d0), (y1, d1) = arc[i], arc[i + 1]
                    pts = []
                    for (yy, dz) in ((y0, d0), (y1, d1)):
                        p = V((0, sd * yy, zc + dz))
                        dd = (p - cen).normalized()
                        for k, xx in ((0.1, 0.032), (0.0, 0.03)):
                            pp = p - dd * (0.04 + k * 0.6)
                            pts += [(xs * xx, pp.y, pp.z), (xs * (xx - 0.008), pp.y, pp.z)]
                    a.add("LayerDark" if i % 2 == 0 else "LayerLight", G.hull(pts))
    if q:
        if s >= 3:
            a.add("Fitting", G.cyl(0.07, 2.08, 2.14, 8, ry=0.086, c=0.006))
        if s >= 4:
            for sd in (1, -1):
                a.add("Etch", G.cbox(0.184, 0.02, 0.5, 0, loc=(0, sd * 0.07, zc)))
                a.add("Etch", G.cbox(0.184, 0.012, 0.5, 0, loc=(0, sd * 0.1, zc)))
            for z in (0.6, 0.95, 1.3):
                a.add("Brass", stud((0.06 * math.cos(PI / 8), 0, z), (1, 0, 0), r=0.016))
                a.add("Brass", stud((-0.06 * math.cos(PI / 8), 0, z), (-1, 0, 0), r=0.016))
        if s >= 5:
            haft_inlay(a, 0.06, 0.45, 2.0)
            a.add("Grip", G.cyl(0.07, 1.86, 1.98, 8, ry=0.085, c=0.006))
            tassel(a, (0.0, -0.085, 1.94), 0.28, lean=(0, -0.03))
    grip_att(a)
    a.attach("Tip", (0, 0.78, zc), look=(0, 1, 0), up=(0, 0, 1))
    a.attach("Spin", (0, 0, 1.4), look=(1, 0, 0), up=(0, 0, 1))
    a.extra["throw"] = {"spinAxis": "Roblox +X through Spin (end over end)"}
    return a


def ring_blade(s, q):
    a = Asset("ring_blade", s, "Weapon", ["Melee", "Thrown", "Blade"],
              notes="Ring Blade: a flat steel hoop 1.78 across (WeaponsV2's 2.2 scaled 0.8 about the grip), honed "
                    "outer bevel over the front two thirds, leather-wrapped back arc, grip bar across the inside "
                    "wrapped in cord with ferrules. Held at the bar; flies flat.")
    n = 16
    cy, r_in, r_mid, r_out, t = 0.64, 0.75, 0.83, 0.89, 0.026

    def pt(r, th, x):
        return (x, cy + r * math.cos(th), r * math.sin(th))

    def ang(i):
        return 2 * PI * i / n

    a.add("Blade", G.loft([[pt(r_in, ang(i), t), pt(r_mid, ang(i), t), pt(r_mid, ang(i), -t), pt(r_in, ang(i), -t)]
                           for i in range(n)], closed=True))
    front = list(range(-5, 6))
    a.add("Edge", G.loft([[pt(r_mid, ang(i), t), pt(r_out, ang(i), 0.0), pt(r_mid, ang(i), -t)] for i in front]))
    back = list(range(5, 12))
    a.add("Blade", G.loft([[pt(r_mid - 0.004, ang(i), t), pt(r_out - 0.025, ang(i), 0.0), pt(r_mid - 0.004, ang(i), -t)]
                           for i in back]))
    if q:
        a.add("Grip", G.loft([[pt(r_in - 0.012, ang(i), t + 0.01), pt(r_out - 0.016, ang(i), t + 0.01),
                               pt(r_out - 0.016, ang(i), -t - 0.01), pt(r_in - 0.012, ang(i), -t - 0.01)]
                              for i in range(6, 11)]))
    half = math.sqrt(r_in ** 2 - cy ** 2) + 0.016
    a.add("Fitting", G.cyl(0.032, -half, half, N(q, 8, 5)))
    a.add("Tassel" if s >= 5 else "Cord", G.cyl(0.05, -0.24, 0.24, N(q, 8, 5), c=C(q, 0.008)))
    fer = "Brass" if s >= 4 else "Fitting"
    a.add(fer, G.cyl(0.044, -half, -half + 0.1, N(q, 8, 5)))
    a.add(fer, G.cyl(0.044, half - 0.1, half, N(q, 8, 5)))
    if q:
        if s == 1:
            strap(a, 0.045, 0.0, -0.22, role="Cord")
            for i, sd in ((1, 1), (-2, -1), (3, -1)):
                a.add("Patch", G.loft([[pt(r_in + 0.012, ang(i + k * 0.5), sd * (t + 0.003)),
                                        pt(r_mid - 0.01, ang(i + k * 0.5), sd * (t + 0.003)),
                                        pt(r_mid - 0.01, ang(i + k * 0.5), sd * (t - 0.002)),
                                        pt(r_in + 0.012, ang(i + k * 0.5), sd * (t - 0.002))] for k in (0, 1, 2)]))
        if s >= 3:
            for sd in (1, -1):                               # inner bevel ring, both faces
                a.add("Edge", G.loft([[pt(r_in, ang(i), sd * (t + 0.003)), pt(r_in + 0.022, ang(i), sd * (t + 0.003)),
                                       pt(r_in + 0.022, ang(i), sd * (t - 0.003)), pt(r_in, ang(i), sd * (t - 0.003))]
                                      for i in range(n)], closed=True))
            a.add("Wrap", lattice(0.05, -0.23, 0.23, 2.2, strands=2))
        if s >= 4:
            for z in (-half + 0.03, -half + 0.07, half - 0.07, half - 0.03):
                a.add("Etch", G.cyl(0.0455, z - 0.007, z + 0.007, 8))
        if s >= 5:
            for i in range(-5, 5):                            # layered band round the outer edge
                for sd in (1, -1):
                    a.add("LayerDark" if i % 2 == 0 else "LayerLight",
                          G.hull([pt(r_mid - 0.045, ang(i), sd * (t + 0.004)), pt(r_mid - 0.045, ang(i), sd * (t - 0.002)),
                                  pt(r_mid - 0.005, ang(i + 0.35), sd * (t + 0.004)),
                                  pt(r_mid - 0.005, ang(i + 0.35), sd * (t - 0.002)),
                                  pt(r_mid - 0.045, ang(i + 1), sd * (t + 0.004)),
                                  pt(r_mid - 0.045, ang(i + 1), sd * (t - 0.002)),
                                  pt(r_mid - 0.005, ang(i + 1.35), sd * (t + 0.004)),
                                  pt(r_mid - 0.005, ang(i + 1.35), sd * (t - 0.002))]))
    grip_att(a)
    a.attach("Tip", (0, cy + r_out, 0), look=(0, 1, 0), up=(0, 0, 1))
    a.attach("Spin", (0, cy, 0), look=(1, 0, 0), up=(0, 1, 0))
    a.extra["throw"] = {"spinAxis": "Roblox +X through Spin (flat spin, hoop stays level)"}
    return a


def climb_pick(s, q):
    a = Asset("climb_pick", s, "Weapon", ["Melee", "Tool", "Climbing"],
              notes="Climbing Pick: six-sided hickory haft, leather grip, rawhide wrist loop, foot spike, socket "
                    "head with a curved pick and a square adze.")
    a.add("Wood", G.cyl(0.055, -0.52, 1.30, 6, ry=0.07, phase=0))
    a.add("Grip", G.cyl(0.061, -0.30, 0.26, 6, ry=0.077, phase=0))
    a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.064, -0.62, -0.50, 6, ry=0.08, phase=0, c=C(q, 0.01)))
    a.add("Fitting", G.hull(G.ring(0.05, 0.05, -0.62, 4) + [(0, 0, -0.80)]))
    zc = 1.38
    a.add("Fitting", G.cbox(0.13, 0.16, 0.24, C(q, 0.02), loc=(0, 0, zc)))
    path = [(0, 0.04, zc + 0.03), (0, 0.22, zc + 0.04), (0, 0.38, zc - 0.0), (0, 0.52, zc - 0.09), (0, 0.63, zc - 0.22)]
    wid = [0.042, 0.038, 0.03, 0.02, 0.006]
    hgt = [0.06, 0.055, 0.045, 0.03, 0.006]
    a.add("Blade", G.sweep(path, lambda i, t: G.rect(wid[i], hgt[i]), ref=(1, 0, 0)))
    a.add("Blade", G.hull([(x, -0.07, z) for x in (-0.05, 0.05) for z in (zc - 0.06, zc + 0.06)] +
                          [(x, -0.30, z) for x in (-0.09, 0.09) for z in (zc - 0.10, zc - 0.05)]))
    a.add("Edge", G.hull([(x, -0.30, z) for x in (-0.09, 0.09) for z in (zc - 0.10, zc - 0.05)] +
                         [(x, -0.345, z) for x in (-0.088, 0.088) for z in (zc - 0.125, zc - 0.11)]))
    loop = [(0.16 * math.cos(2 * PI * i / 10), -0.085, -0.66 + 0.2 * math.sin(2 * PI * i / 10)) for i in range(10)]
    if q:
        a.add("Rawhide", G.sweep(loop, lambda i, t: G.rect(0.012, 0.022), ref=(0, 1, 0), closed=True))
        if s == 1:
            strap(a, 0.05, 0.0, -0.27)
            a.add("Patch", G.cbox(0.134, 0.09, 0.1, 0, loc=(0, 0.02, zc + 0.04)))
        if s >= 3:
            a.add("Stitch", stitches((0, -0.079, -0.28), (0, -0.079, 0.24), 8, (0, -1, 0)))
            a.add("Stitch", stitches((0, 0.079, -0.28), (0, 0.079, 0.24), 8, (0, 1, 0)))
            a.add("Fitting", G.cyl(0.064, 0.26, 0.29, 6, ry=0.08, phase=0))
        if s >= 4:
            a.add("Brass", G.cyl(0.04, -0.7, -0.64, 4, phase=0.5))
            for z in (0.45, 0.75, 1.05):
                a.add("Brass", stud((0.055, 0, z), (1, 0, 0), r=0.014))
                a.add("Brass", stud((-0.055, 0, z), (-1, 0, 0), r=0.014))
        if s >= 5:
            a.add("Etch", G.cbox(0.136, 0.166, 0.03, 0, loc=(0, 0, zc + 0.06)))
            a.add("Etch", G.cbox(0.136, 0.166, 0.015, 0, loc=(0, 0, zc - 0.05)))
            haft_inlay(a, 0.055, 0.32, 1.22, w=0.012)
    grip_att(a)
    a.attach("Tip", (0, 0.63, zc - 0.22), look=(0, 0.55, -0.83), up=(0, 0.83, 0.55))
    return a


def _limb(path, w0, w1, t0, t1, off=0.0):
    return G.sweep(path, lambda i, s: [(u, v + off) for (u, v) in G.rect(w0 + (w1 - w0) * s, t0 + (t1 - t0) * s)],
                   ref=(1, 0, 0))


def bow(s, q):
    a = Asset("bow", s, "Weapon", ["Ranged", "Bow"],
              notes="Recurve Bow. Wooden riser with an arrow window on -X, leather grip, recurved limbs, tip "
                    "overlays, linen string. v1 attachments kept (Nock, StringTop, StringBottom, ArrowRest). "
                    "Hide <name>_Rope while drawing.")
    sy, zt, zm = -0.4168, 2.32, 0.2
    up_path = [(0, 0.0, 0.62), (0, -0.03, 1.0), (0, -0.11, 1.4), (0, -0.24, 1.8), (0, -0.355, 2.12),
               (0, -0.392, 2.32), (0, -0.37, 2.42), (0, -0.30, 2.47)]
    if not q:
        up_path = [up_path[i] for i in (0, 2, 3, 5, 7)]
    lo_path = [(x, y, 2 * zm - z) for (x, y, z) in up_path]
    a.add("Wood", _limb(up_path, 0.075, 0.032, 0.034, 0.018))
    a.add("Wood", _limb(lo_path, 0.075, 0.032, 0.034, 0.018))
    a.add("Wood", G.cbox(0.15, 0.17, 0.42, C(q, 0.02), loc=(0, 0.02, -0.19)))
    a.add("Wood", G.cbox(0.15, 0.17, 0.30, C(q, 0.02), loc=(0, 0.01, 0.62)))
    a.add("Wood", G.cbox(0.075, 0.15, 0.40, C(q, 0.01), loc=(0.0375, 0.01, 0.27)))
    a.add("Wood", G.cbox(0.15, 0.15, 0.18, C(q, 0.02), loc=(0, 0.0, -0.45)))
    a.add("Grip", G.cbox(0.17, 0.19, 0.36, C(q, 0.03), loc=(0, 0.02, -0.12)))
    a.add("Brass" if s >= 4 else "Fitting", G.cbox(0.08, 0.06, 0.02, 0, loc=(-0.035, 0.035, 0.07)))
    for zz, sgn in ((zt, 1), (2 * zm - zt, -1)):
        a.add("Brass" if s >= 4 else "Fitting", G.cbox(0.075, 0.08, 0.10, C(q, 0.01), loc=(0, sy + 0.035, zz + sgn * 0.02)))
    a.add("Rope", G.rod((0, sy, zt), (0, sy, 2 * zm - zt), 0.011 if q else 0.014, 4))
    if q:
        if s == 1:
            strap(a, 0.08, 0.02, -0.28)
        if s >= 3:
            a.add("Wrap", box_lattice(0.0, 0.02, 0.087, 0.097, -0.28, 0.04, 2.5))
        if s >= 4:
            for dz in (0.045, -0.045):
                a.add("Brass", G.cyl(0.02, zm + dz - 0.012, zm + dz + 0.012, 6, cy=sy))
        if s >= 5:
            a.add("Horn", _limb(up_path[:6], 0.03, 0.014, 0.004, 0.004, off=0.03))
            a.add("Horn", _limb(lo_path[:6], 0.03, 0.014, 0.004, 0.004, off=0.03))
            a.add("Etch", G.cbox(0.154, 0.174, 0.03, 0, loc=(0, 0.01, 0.66)))
            a.add("Etch", G.cbox(0.154, 0.174, 0.015, 0, loc=(0, 0.01, 0.71)))
    grip_att(a)
    a.attach("Nock", (0, sy, zm), look=(0, 1, 0), up=(0, 0, 1))
    a.attach("StringTop", (0, sy, zt))
    a.attach("StringBottom", (0, sy, 2 * zm - zt), look=(0, 0, -1), up=(0, 1, 0))
    a.attach("ArrowRest", (-0.04, 0.035, zm), look=(0, 1, 0), up=(0, 0, 1))
    return a


def short_bow(s, q):
    a = Asset("short_bow", s, "Weapon", ["Ranged", "Bow", "Kit"],
              notes="Short Bow: plain flat-limbed self bow, tan leather grip block. Same attachments as the bow.")
    sy, zt, zm = -0.36, 2.0, 0.2
    up_path = [(0, 0.0, 0.42), (0, -0.04, 0.85), (0, -0.13, 1.30), (0, -0.25, 1.70), (0, -0.335, 2.0)]
    if not q:
        up_path = [up_path[i] for i in (0, 2, 4)]
    lo_path = [(x, y, 2 * zm - z) for (x, y, z) in up_path]
    a.add("Wood", _limb(up_path, 0.07, 0.03, 0.036, 0.02))
    a.add("Wood", _limb(lo_path, 0.07, 0.03, 0.036, 0.02))
    a.add("Wood", G.cbox(0.13, 0.13, 0.62, C(q, 0.02), loc=(0, 0.0, 0.11)))
    a.add("Grip", G.cbox(0.15, 0.15, 0.34, C(q, 0.03), loc=(0, 0.0, -0.06)))
    for zz in (zt, 2 * zm - zt):
        a.add("Fitting", G.cbox(0.07, 0.07, 0.07, C(q, 0.01), loc=(0, sy + 0.025, zz)))
    a.add("Rope", G.rod((0, sy, zt), (0, sy, 2 * zm - zt), 0.011 if q else 0.014, 4))
    if q:
        if s == 1:
            strap(a, 0.07, 0.0, -0.2)
        if s >= 3:
            for z in (-0.2, -0.06, 0.08):
                a.add("Cord", G.cbox(0.158, 0.158, 0.035, 0.008, loc=(0, 0, z)))
        if s >= 4:
            a.add("Brass", G.cbox(0.075, 0.06, 0.018, 0.004, loc=(-0.035, 0.04, 0.13)))
        if s >= 5:
            a.add("Horn", _limb(up_path, 0.022, 0.01, 0.004, 0.004, off=0.034))
            a.add("Horn", _limb(lo_path, 0.022, 0.01, 0.004, 0.004, off=0.034))
    grip_att(a)
    a.attach("Nock", (0, sy, zm), look=(0, 1, 0), up=(0, 0, 1))
    a.attach("StringTop", (0, sy, zt))
    a.attach("StringBottom", (0, sy, 2 * zm - zt), look=(0, 0, -1), up=(0, 1, 0))
    a.attach("ArrowRest", (-0.035, 0.035, zm), look=(0, 1, 0), up=(0, 0, 1))
    return a


# ------------------------------------------------------------------------------------------------ new: the blades
def _curved_blade(z0, L, yb0=-0.055, yf0=0.1, curve=0.07, t0=0.017, t1=0.012, clip=0.24, n=6):
    """Single-edged blade along +Z from z0, length L, a gentle curve toward the spine (-Y), straight spine and a
    clipped, angled tip: the edge runs straight until clip before the end, then angles back to a point on the spine."""
    st = []
    zs = [z0 + L * i / (n - 1) for i in range(n - 1)]
    zs = [z for z in zs if z < z0 + L - clip - 0.05] + [z0 + L - clip]
    for z in zs:
        f = (z - z0) / L
        off = -curve * f * f
        st.append((z, yb0 + off, yf0 + off - 0.012 * f, t0 + (t1 - t0) * f))
    ze = z0 + L
    off = -curve
    st.append((ze, yb0 + off, yb0 + off + 0.008, 0.003))
    return st


def blade_pair(wid, s, q, side="R", grip_len=0.6, blade_len=2.0, notes=""):
    a = Asset(wid, s, "Weapon", ["Melee", "Blade"] + (["OffHand"] if side == "L" else []), notes=notes)
    gz0, gz1 = -grip_len / 2, grip_len / 2
    z_guard0, z_guard1 = gz1, gz1 + 0.055
    z_col1 = z_guard1 + 0.07
    st = _curved_blade(z_col1 - 0.02, blade_len)
    if not q:
        st = [st[0], st[2], st[-2], st[-1]]
    if q and s == 1:
        st = notch(st, [z_col1 + blade_len * 0.38, z_col1 + blade_len * 0.66], depth=0.018)
    B = Bl(st, 0.032)
    body, edge, _ = G.blade(st, band=0.032)
    a.add("Blade", body)
    a.add("Edge", edge)
    # grip: dark grey under-layer (Ray) and black cord; diamond windows from 3 stars
    if q and s >= 3:
        a.add("Ray", G.cyl(0.052, gz0, gz1, 8, ry=0.064, c=0.006))
        a.add("Wrap", lattice(0.052, gz0 + 0.01, gz1 - 0.01, 2.5 * grip_len / 0.6, strands=2, ry=0.064, w=0.016,
                              h=0.012))
    else:
        a.add("Cord", G.cyl(0.054, gz0, gz1, N(q), ry=0.066, c=C(q, 0.006)))
        if q:
            ring_bands(a, "Wrap", 0.056, [gz0 + 0.05 + i * (grip_len - 0.1) / 5 for i in range(6)], h=0.018, ry=0.068)
        if q and s == 1:
            strap(a, 0.05, 0.0, gz0 + 0.03, role="Cord")
    # round guard (12 sides), satin; 4 stars: brass rim (a slightly larger, thinner disc)
    a.add("Satin", G.cyl(0.21, z_guard0, z_guard1, N(q, 12, 8), c=C(q, 0.01)))
    if q and s >= 4:
        a.add("Brass", G.cyl(0.218, z_guard0 + 0.012, z_guard1 - 0.012, 12))
    a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.06, z_guard1, z_col1, N(q), ry=0.085, cy=-0.0, c=C(q, 0.006)))
    a.add("Fitting", G.cyl(0.058, gz0 - 0.008, gz0 + 0.004, N(q), ry=0.07))
    a.add("Brass" if s >= 4 else "Satin", G.cyl(0.056, gz0 - 0.05, gz0 - 0.008, N(q, 10, 6), ry=0.066, c=C(q, 0.012)))
    if q:
        if s == 1:
            B.patches(a, [(z_col1 + 0.3, 0.25, 0.1, 0.55, 1), (z_col1 + 1.1, 0.2, 0.25, 0.7, -1)])
        if s >= 3:
            a.add("Fitting", G.cyl(0.058, gz1 - 0.025, gz1, 8, ry=0.07))
        if s >= 4:
            a.add("Etch", B.face_strip(z_col1 + 0.06, z_col1 + 0.075, 0.04, 0.96))
            a.add("Etch", B.face_strip(z_col1 + 0.095, z_col1 + 0.11, 0.04, 0.96))
        if s >= 5:
            a.add("Inlay", B.spine_strip(z_col1 + 0.05, z_col1 + blade_len - 0.3))
            B.layered(a, z_col1 + 0.25, z_col1 + blade_len - 0.32, max(8, int(blade_len * 6)))
            B.mark(a, z_col1 + 0.02, 0.3)
            tassel(a, (0, 0.0, gz0 - 0.05), 0.3, role="Tassel" if side == "R" else "Tassel2")
    grip_att(a)
    yb_tip = st[-1][1]
    a.attach("Tip", (0, yb_tip, st[-1][0]))
    return a


def paired_blades(s, q):
    return blade_pair("paired_blades", s, q, "R", notes=(
        "Paired Blades, right hand (Combat_v3 5.4; from the owner's crossed-blades picture, our own design): 2.7 studs, "
        "2.0 blade with a gentle curve, straight spine and a clipped angled tip, pale honed edge strip the full length, "
        "round 12-sided guard, 0.6 grip diamond-wrapped in black cord over dark grey, round pommel cap. 5 stars: oxblood "
        "tassel (the left blade's is ochre, so the pair reads as a pair)."))


def paired_blades_L(s, q):
    a = blade_pair("paired_blades_L", s, q, "L", notes=(
        "Paired Blades, left hand: the same blade, welded to LeftGripAttachment when offHand = true. Identical "
        "geometry (the blade is symmetric across its flat), ochre tassel at 5 stars."))
    return a


def wrapped_sabre(s, q):
    return blade_pair("wrapped_sabre", s, q, "R", grip_len=0.75, blade_len=2.55, notes=(
        "Wrapped Sabre (the Paired Blades fallback, Combat_v3 5.4): one 3.4-stud single-edged sword, the same blade "
        "family, round guard and diamond wrap."))


def leaf_dagger(s, q):
    a = Asset("leaf_dagger", s, "Weapon", ["Melee", "Thrown", "Blade"], notes=(
        "Leaf Dagger (Combat_v3 5.5; from the owner's throwing-dagger picture, our own design): 1.22 studs, a leaf blade "
        "0.65 long widest a third of the way up with a diamond section (4 faces to a central ridge) and pale honed "
        "edges, a 0.35 grip with a raised spiral wrap, a ring pommel 0.22 across. FingerRing = ring centre (the "
        "first-person flourish turns it about FingerRing's look axis)."))
    z0, L = 0.175, 0.65
    prof = [(0.0, 0.045, 0.026), (0.12, 0.085, 0.03), (0.217, 0.105, 0.031), (0.36, 0.092, 0.027),
            (0.5, 0.058, 0.019), (0.6, 0.026, 0.01), (0.65, 0.002, 0.002)]
    if not q:
        prof = [prof[0], prof[2], prof[4], prof[6]]
    if q and s == 1:
        prof = sorted(prof + [(0.29, 0.099, 0.029)])
    body, ef, eb, ridge = [], [], [], []
    for i, (dz, w, t) in enumerate(prof):
        z = z0 + dz
        k = 0.78
        wn = w - (0.012 if (q and s == 1 and abs(dz - 0.29) < 1e-6) else 0.0)
        body.append([(0.0 + t * (1 - k), wn * k, z), (t, 0.0, z), (t * (1 - k), -w * k, z),
                     (-t * (1 - k), -w * k, z), (-t, 0.0, z), (-t * (1 - k), wn * k, z)])
        ef.append([(t * (1 - k), wn * k, z), (0.0, wn, z), (-t * (1 - k), wn * k, z)])
        eb.append([(-t * (1 - k), -w * k, z), (0.0, -w, z), (t * (1 - k), -w * k, z)])
    a.add("Blade", G.loft(body))
    a.add("Edge", G.loft(ef))
    a.add("Edge", G.loft(eb))
    gz0, gz1 = -0.175, 0.175
    a.add("Cord" if s < 3 else "Grip", G.cyl(0.036, gz0, gz1, N(q), ry=0.04, c=C(q, 0.006)))
    a.add("Brass" if s >= 4 else "Fitting", G.cyl(0.042, gz1, z0 + 0.03, N(q), ry=0.05, c=C(q, 0.006)))
    a.add("Fitting", G.cyl(0.04, gz0 - 0.03, gz0 + 0.005, N(q), ry=0.044))
    rc, rr = gz0 - 0.03 - 0.088, 0.088
    nring = 16 if s >= 4 else 12
    if not q:
        nring = 8
    ringp = [(0.0, rr * math.sin(2 * PI * i / nring), rc + rr * math.cos(2 * PI * i / nring)) for i in range(nring)]
    a.add("Brass" if s >= 5 else "Fitting",
          G.sweep(ringp, lambda i, t: G.rect(0.022, 0.018), ref=(1, 0, 0), closed=True))
    if q:
        if s == 1:
            a.add("Patch", G.loft([[(t + 0.003, w * 0.15, z0 + dz), (t + 0.003, w * 0.55, z0 + dz),
                                     (t - 0.003, w * 0.55, z0 + dz), (t - 0.003, w * 0.15, z0 + dz)]
                                    for (dz, w, t) in [(0.1, 0.08, 0.03), (0.2, 0.1, 0.03)]]))
        if s == 2:
            a.add("Wrap", helix(0.036, gz0 + 0.01, gz1 - 0.01, 3.0, ry=0.04, w=0.01, h=0.006))
        if s >= 3:
            a.add("Wrap", helix(0.036, gz0 + 0.01, gz1 - 0.01, 5.0, ry=0.04, w=0.012, h=0.009, ppt=8))
            role = "Inlay" if s >= 5 else "Edge"
            wr = 0.012 if s >= 5 else 0.007
            for sd in (1, -1):                                    # ridge line on both faces
                a.add(role, G.loft([[(sd * (t + 0.004), wr, z0 + dz), (sd * (t + 0.004), -wr, z0 + dz),
                                     (sd * (t - 0.004), -wr, z0 + dz), (sd * (t - 0.004), wr, z0 + dz)]
                                    for (dz, w, t) in prof[1:-1]]))
        if s >= 4:
            a.add("Brass", G.cyl(0.046, gz1 - 0.02, gz1 + 0.006, 10, ry=0.052))
        if s >= 5:
            a.add("Tassel", G.cyl(0.03, rc - rr - 0.03, rc - rr + 0.01, 6, rx1=0.02, c=0.006))
            tassel(a, (0, 0.0, rc - rr - 0.03), 0.24)
    grip_att(a)
    a.attach("Tip", (0, 0, z0 + L))
    a.attach("FingerRing", (0, 0, rc), look=(1, 0, 0), up=(0, 0, 1))
    a.attach("Spin", (0, 0, 0.15), look=(1, 0, 0), up=(0, 0, 1))
    a.extra["throw"] = {"spinAxis": "Roblox +X through Spin (end over end), or flat (no spin) for the silent throw"}
    return a


# ------------------------------------------------------------------------------------------------ unstarred (as V2)
def throwing_knife(q):
    a = Asset("throwing_knife", 2, "Weapon", ["Thrown", "Blade"], starred=False,
              notes="Throwing Knife (stack 6, no stars): double-edged spear point, cord-wrapped tang, ring pommel.")
    st = [(0.08, -0.04, 0.04, 0.008), (0.22, -0.076, 0.076, 0.008), (0.46, -0.05, 0.05, 0.006),
          (0.66, -0.002, 0.002, 0.001)]
    body, ef, eb = G.blade(st, band=0.026, double=True)
    a.add("Blade", body)
    a.add("Edge", ef)
    a.add("Edge", eb)
    a.add("Blade", G.cbox(0.016, 0.07, 0.4, 0, loc=(0, 0, -0.12)))
    a.add("Cord", G.cyl(0.022, -0.27, 0.07, N(q, 6, 4), ry=0.05))
    zc = -0.375
    ringp = [(0, 0.055 * math.cos(2 * PI * i / 8), zc + 0.055 * math.sin(2 * PI * i / 8)) for i in range(8)]
    a.add("Fitting", G.sweep(ringp, lambda i, s: G.rect(0.012, 0.012), ref=(1, 0, 0), closed=True))
    grip_att(a)
    a.attach("Tip", (0, 0, 0.66))
    return a


def arrow(q):
    a = Asset("arrow", 2, "Ammo", ["Ammo"], starred=False,
              notes="Arrow (no stars): pale shaft, nock, leaf head, three vanes. Origin = Nock.")
    a.add("Shaft", G.cyl(0.022, 0.06, 2.80, N(q, 6, 4)))
    a.add("Fitting", G.cyl(0.026, 0.0, 0.08, N(q, 6, 4)))
    st = [(2.77, -0.028, 0.028, 0.012), (2.88, -0.058, 0.058, 0.009), (3.0, -0.002, 0.002, 0.001)]
    body, ef, eb = G.blade(st, band=0.022, double=True)
    a.add("Blade", body)
    a.add("Edge", ef)
    a.add("Edge", eb)
    vane = G.hull([(0.0, -0.004, 0.12), (0.0, 0.004, 0.12), (0.0, -0.004, 0.55), (0.0, 0.004, 0.55),
                   (0.075, -0.003, 0.17), (0.075, 0.003, 0.17), (0.075, -0.003, 0.40), (0.075, 0.003, 0.40)])
    for i, deg in enumerate((90, 210, 330)):
        a.add("FletchCock" if i == 0 else "Fletch", vane, M=R("Z", deg))
    grip_att(a)
    a.attach("Nock", (0, 0, 0))
    a.attach("Tip", (0, 0, 3.0))
    return a


def wire_snare(q):
    a = Asset("wire_snare", 2, "Trap", ["Trap", "Kit"], starred=False,
              notes="Wire Snare (no stars): sharpened stake, coil of wire, running noose, cord tie.")
    a.add("Stake", G.hull(G.ring(0.035, 0.035, 0.30, 6) + G.ring(0.035, 0.035, -0.18, 6) + [(0, 0, -0.34)]))
    for zz, rr in ((0.2, 0.2), (0.235, 0.19)):
        pts = [(rr * math.cos(2 * PI * i / 12) + 0.04, rr * math.sin(2 * PI * i / 12), zz) for i in range(12)]
        a.add("Wire", G.sweep(pts, lambda i, s: G.rect(0.008, 0.008), ref=(0, 0, 1), closed=True))
    noose = [(0.24 + 0.12 * math.cos(2 * PI * i / 8), 0.12 * math.sin(2 * PI * i / 8), 0.06) for i in range(8)]
    a.add("Wire", G.sweep(noose, lambda i, s: G.rect(0.007, 0.007), ref=(0, 0, 1), closed=True))
    a.add("Wire", G.rod((0.12, 0.0, 0.06), (0.06, 0.0, 0.2), 0.008, 4))
    a.add("Cord", G.cyl(0.045, 0.24, 0.29, 6))
    grip_att(a)
    return a


STARRED = [knife, leaf_dagger, ring_blade, sword, machete, paired_blades, paired_blades_L, wrapped_sabre,
           hatchet, twin_axe, climb_pick, spear, bow, short_bow]
PLAIN = [throwing_knife, arrow, wire_snare]


# ================================================================================================ export
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def export(glb, roots):
    bpy.ops.object.select_all(action="DESELECT")
    for r in roots:
        r.select_set(True)
        for c in r.children_recursive:
            c.select_set(True)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_animations=False, export_materials="EXPORT")


def run_set(name, makers, gap=0.6):
    reset()
    coll = bpy.context.scene.collection
    roots, mans = [], []
    x = 0.0
    for mk in makers:
        a = mk()
        xs = [v[0] for vs, _ in a.geo.values() for v in vs]
        w0, w1 = min(xs), max(xs)
        x += -w0
        root, man = build(a, x, coll)
        x += w1 + gap
        roots.append(root)
        mans.append(man)
    glb = os.path.join(OUT, name + ".glb")
    export(glb, roots)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, name + ".blend"))
    print("EXPORTED", glb, round(os.path.getsize(glb) / 1e6, 3), "MB", len(mans), "assets")
    return mans


def makers(q):
    out = []
    for f in STARRED:
        for s in range(1, 6):
            out.append(lambda f=f, s=s: f(s, q))
    for f in PLAIN:
        out.append(lambda f=f: f(q))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    near = run_set("WeaponsV3", makers(1))

    def farify(mk):
        def m():
            a = mk()
            a.name += "_Far"
            return a
        return m
    far = run_set("WeaponsV3_Far", [farify(m) for m in makers(0)])
    warnings = []
    for m in near:
        m["far"] = m["name"] + "_Far"
        cap = 1400 if m["stars"] in (1, 2) else 2500
        if m["tris"] > cap:
            warnings.append("%s %d tris over %d" % (m["name"], m["tris"], cap))
    for m in far:
        m["nearOf"] = m["name"][:-4]
    # silhouette check: length and width of every star within 5% of 2 stars
    by = {}
    for m in near:
        if m["starred"]:
            by.setdefault(m["id"], {})[m["stars"]] = m
    sil = {}
    for wid, d in by.items():
        ref = d[2]["coreSize"]
        row = {}
        for s_, m in d.items():
            dev = [round((m["coreSize"][k] - ref[k]) / max(ref[k], 1e-3), 3) for k in (1, 2)]
            row[str(s_)] = {"coreSize": m["coreSize"], "lengthDev": dev[0], "widthDev": dev[1]}
            if abs(dev[0]) > 0.05 or abs(dev[1]) > 0.05:
                warnings.append("%s length %+.1f%% vs 2 stars" % (m["name"], dev[0] * 100))
        sil[wid] = row
    variants = {wid: ["%s_t%d" % (wid, s_) for s_ in range(1, 6)] for wid in by}
    man = {
        "category": "WeaponsV3", "glbs": {"near": "WeaponsV3.glb", "far": "WeaponsV3_Far.glb"},
        "generator": "weapons_v3.py (+ wv3_geo.py)", "units": "studs (1 Blender unit = 1 stud)",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y). Held items: Grip at the origin, look = item axis (Roblox +Y), "
                "up = edge / front (Roblox -Z), as WeaponsV2 / ItemsReal. Same grips and attachments as WeaponsV2.",
        "stars": {"names": STAR_NAMES,
                  "rule": "Five meshes per weapon, <id>_t1 .. <id>_t5 (Combat_v3 5.1): same silhouette, detail grows "
                          "inside it. Each part carries its own star finish in rgb / robloxMaterial: set them from "
                          "this manifest (the importer drops colours). finishRole is the Stars.applyFinish role if a "
                          "tint is still wanted; the variant colours already are the finish, so applyFinish should "
                          "skip parts whose model has attribute Variant."},
        "variants": variants,
        "silhouette": sil,
        "palette": {r: [{"stars": i + 1, "robloxMaterial": PAL[r][i][0], "rgb": list(PAL[r][i][1])} for i in range(5)]
                    for r in PAL},
        "fixedRoles": {r: {"robloxMaterial": m_, "rgb": list(c)} for r, (m_, c) in FIXED.items()},
        "import": [
            "Held and far models: CanCollide/CanQuery/CanTouch off, CollisionFidelity Box, Massless, CastShadow off "
            "on viewmodel copies.",
            "Metal parts: matte (Metal material with no reflectance, or SmoothPlastic as WeaponLooks does for plain "
            "parts so they never mirror the sky). Nothing Neon, nothing emissive.",
            "paired_blades welds to RightGripAttachment, paired_blades_L to LeftGripAttachment (offHand = true).",
            "leaf_dagger: FingerRing is the ring centre for the first-person flourish.",
            "ring_blade is now 1.78 across (was 2.2): Tip and Spin moved with it.",
            "Bows: hide <name>_Rope while drawing and draw Beams between StringTop, the Nock and StringBottom.",
        ],
        "assets": near + far, "warnings": warnings,
    }
    mp = os.path.join(OUT, "WeaponsV3.manifest.json")
    with open(mp, "w") as fh:
        json.dump(man, fh, indent=1)
    print("MANIFEST", mp, "warnings", len(warnings))
    for w in warnings:
        print("WARNING", w)
    for m in near:
        print("ASSET %-22s tris %5d size %s" % (m["name"], m["tris"], m["size"]))


main()






