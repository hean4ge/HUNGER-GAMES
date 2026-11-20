# Season one "The First Ride" cosmetics in 3D (CardMenusAndShop.md sections 3.1 and 4.1).
#
#   blender --background --factory-startup --python art/blender/season_one.py -- <export dir> <preview dir> [<icons dir>]
#   (export dir: %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/SeasonOne; preview dir: art/previews)
#
# Writes to <export dir>:
#   SeasonOneSkinParts.glb + .manifest.json   extra parts of the higher skins, each asset in its weapon's Grip frame
#   SeasonOneProps.glb + .manifest.json       kill-effect, emote and launch-effect props, the banner pole, the pennant
#   SeasonOneCrates.glb + .manifest.json      the five Gold crates (body + separate lid for the reveal)
#   SeasonOneSkins.manifest.json              the 26 skins + 3 wraps as recipes on WeaponsV3 (colours/materials
#                                             by role, extra parts, tier rule) - no new mesh needed for a recipe
#   SeasonOne.index.json                      what is where
# and to <preview dir>/SeasonOne/: Workbench previews (Library) plus matte studio renders of every skin and prop.
# With <icons dir>: SkinTiles_N.png sprite sheets (640 x 256 cells, transparent) + SkinTiles.json, the icon
# fallbacks for skin tiles beyond the 24 live ViewportFrames.
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls  # noqa: E402
from season_one_skins import GROUP_OF, SKINS, WRAPS  # noqa: E402

out_dir, preview_dir = ls.args()
rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ICON_DIR = os.path.abspath(rest[2]) if len(rest) > 2 else None
WV3_DIR = os.path.join(os.path.dirname(os.path.abspath(out_dir)), "WeaponsV3")
WV3_GLB = os.path.join(WV3_DIR, "WeaponsV3.glb")
WV3_MAN = json.load(open(os.path.join(WV3_DIR, "WeaponsV3.manifest.json"), encoding="utf-8"))
PREV = os.path.join(os.path.abspath(preview_dir), "SeasonOne")
os.makedirs(PREV, exist_ok=True)
random.seed(48)

ls.reset()

# ------------------------------------------------------------------------------------------------------------
# WeaponsV3 (imported only to measure and to render the skins; never exported from here)
# ------------------------------------------------------------------------------------------------------------
bpy.ops.import_scene.gltf(filepath=WV3_GLB)
WEAPONS = {}   # asset name -> {"root": empty, "parts": {role: obj}}
for o in list(bpy.data.objects):
    if o.parent is None and o.type == "EMPTY" and not o.name.endswith("_Far"):
        WEAPONS[o.name] = {"root": o, "parts": {c.name[len(o.name) + 1:]: c for c in o.children if c.type == "MESH"}}
    elif o.parent is None and o.name.endswith("_Far"):
        for c in list(o.children_recursive):
            bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.objects.remove(o, do_unlink=True)
for w in WEAPONS.values():
    w["root"].hide_render = True
    for c in w["parts"].values():
        c.hide_render = True
WV3_ASSETS = {a["name"]: a for a in WV3_MAN["assets"]}


def bounds(asset, role):
    w = WEAPONS[asset]
    o = w["parts"][role]
    inv = w["root"].matrix_world.inverted()
    pts = [inv @ (o.matrix_world @ v.co) for v in o.data.vertices]
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


# ------------------------------------------------------------------------------------------------------------
# Small mesh builders (Grip frame: X = thickness, Y = edge direction, Z = along the item)
# ------------------------------------------------------------------------------------------------------------
def _obj(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return ls.from_bmesh(name, bm)


def plate(name, pts_yz, x0, thick):
    """A flat plate: the polygon (y, z) in the plane x = x0, extruded by thick (sign = side)."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for (y, z) in pts_yz]
    b = [bm.verts.new((x0 + thick, y, z)) for (y, z) in pts_yz]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    return _obj(name, bm)


def strip(name, line_yz, width, x0, thick):
    """A raised line along a (y, z) polyline on the face x = x0: one quad plate per segment, merged."""
    bm = bmesh.new()
    for (p, q) in zip(line_yz, line_yz[1:]):
        d = Vector((q[0] - p[0], q[1] - p[1]))
        if d.length < 1e-6:
            continue
        nrm = Vector((-d.y, d.x)).normalized() * width / 2
        ext = d.normalized() * width * 0.45
        quad = [(p[0] - ext.x + nrm.x, p[1] - ext.y + nrm.y), (q[0] + ext.x + nrm.x, q[1] + ext.y + nrm.y),
                (q[0] + ext.x - nrm.x, q[1] + ext.y - nrm.y), (p[0] - ext.x - nrm.x, p[1] - ext.y - nrm.y)]
        a = [bm.verts.new((x0, y, z)) for (y, z) in quad]
        b = [bm.verts.new((x0 + thick, y, z)) for (y, z) in quad]
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return _obj(name, bm)


def both_faces(fn, name, x_face, thick, *args):
    """Build the same plate on +X and -X faces and join them."""
    p = fn(name + "_p", *args, x_face, thick)
    m = fn(name + "_m", *args, -x_face, -thick)
    return ls.join([p, m], name)


def leaf2d(length, width, seg=4, serrate=0.0):
    """A pointed leaf outline along +u from (0, 0); returns [(u, v)]."""
    top, bot = [], []
    for i in range(seg + 1):
        t = i / seg
        w = width * math.sin(math.pi * t) * (1 - 0.35 * t)
        if serrate and 0 < i < seg:
            w *= 1 + serrate * (1 if i % 2 else -1)
        top.append((length * t, w / 2))
        bot.append((length * t, -w / 2))
    return top + list(reversed(bot[1:-1]))


def poly_circle(cy, cz, r, seg=12, a0=0.0):
    return [(cy + r * math.cos(a0 + 2 * math.pi * i / seg), cz + r * math.sin(a0 + 2 * math.pi * i / seg)) for i in range(seg)]


def lumps(name, centres, radius, squash=(1, 1, 1), jitter=0.0):
    objs = []
    for i, c in enumerate(centres):
        o = ls.icosphere("%s_%d" % (name, i), radius=radius * random.uniform(0.85, 1.1), subdivisions=1,
                         loc=c, scale=squash)
        if jitter:
            ls.jitter(o, jitter)
        objs.append(o)
    return ls.join(objs, name)


# ------------------------------------------------------------------------------------------------------------
# Extra parts of the higher skins (all inside the WeaponsV3 silhouette)
# ------------------------------------------------------------------------------------------------------------
def x_wave():
    lo, hi = bounds("sword_t3", "Blade")
    parts = []
    for k, ph in enumerate((0.0, 2.2)):
        line = [(-0.012 + 0.022 * math.sin(z * 7.0 + ph), z) for z in [0.62 + 0.08 * i for i in range(27)]]
        parts.append((both_faces(strip, "wave%d" % k, hi.x + 0.0005, 0.005, line, 0.011), "Metal", (140, 142, 144)))
    return parts, "sword", "Blade"


def x_temper_bands():
    lo, hi = bounds("sword_t3", "Blade")
    cols = [(178, 152, 98), (150, 104, 64), (84, 100, 132)]
    parts = []
    for i, c in enumerate(cols):
        z0, z1 = 0.47 + 0.15 * i, 0.47 + 0.15 * (i + 1)
        pts = [(lo.y + 0.004, z0), (hi.y - 0.002, z0), (hi.y - 0.002, z1), (lo.y + 0.004, z1)]
        parts.append((both_faces(plate, "band%d" % i, hi.x + 0.0005, 0.004, pts), "Metal", c))
    return parts, "sword", "Blade"


def x_ricasso_collar():
    lo, hi = bounds("sword_t3", "Blade")
    o = ls.cube("collar", size=(0.054, (hi.y - lo.y) + 0.02, 0.06), loc=(0, (lo.y + hi.y) / 2, 0.44))
    ls.bevel(o, 0.008, 1)
    return [(o, "Brass", (164, 132, 74))], "sword", "Blade"


def x_oak_leaves():
    flo, fhi = bounds("sword_t3", "Fitting")
    parts = []
    objs = []
    for side in (-1, 1):
        y_end = fhi.y if side > 0 else flo.y
        base_y = y_end - side * 0.105
        for k, (ang, ln, wd) in enumerate(((0, 0.11, 0.07), (38, 0.085, 0.055), (-38, 0.085, 0.055))):
            out = leaf2d(ln, wd, 6, 0.25)
            a = math.radians(ang)
            pts = []
            for (u, v) in out:
                uy = u * math.cos(a) - v * math.sin(a)
                vz = u * math.sin(a) + v * math.cos(a)
                pts.append((base_y + side * uy, 0.36 + vz))
            o = plate("leaf%d_%d" % (side, k), pts, -(fhi.x + 0.01), 2 * (fhi.x + 0.01))
            objs.append(o)
    parts.append((ls.join(objs, "oak"), "Brass", (164, 132, 74)))
    return parts, "sword", "Fitting"


def x_fuller_inlay():
    lo, hi = bounds("sword_t3", "Etch")
    pts = [(lo.y + 0.004, 0.52), (lo.y + 0.012, 0.52), (lo.y + 0.012, 2.45), (lo.y + 0.004, 2.45)]
    return [(both_faces(plate, "inlay", hi.x + 0.0005, 0.003, pts), "Brass", (176, 142, 80))], "sword", "Etch"


def x_crosshatch():
    lo, hi = bounds("sword_t3", "Blade")
    lines = []
    y0, y1 = lo.y + 0.012, hi.y - 0.014
    for k in range(12):
        z = 0.7 + k * 0.16
        lines.append([(y0, z), (y1, z + 0.09)])
        lines.append([(y1, z + 0.02), (y0, z + 0.11)])
    objs = []
    for i, ln in enumerate(lines):
        objs.append(both_faces(strip, "hatch%d" % i, hi.x + 0.0005, 0.004, ln, 0.008))
    return [(ls.join(objs, "hatch"), "Metal", (112, 116, 124))], "sword", "Blade"


def x_pommel_stone():
    lo, _ = bounds("sword_t3", "Fitting")
    o = ls.icosphere("stone", radius=0.06, subdivisions=1, loc=(0, 0.01, lo.z + 0.05), scale=(1.3, 1.0, 0.9))
    ls.jitter(o, 0.006)
    return [(o, "Stone", (104, 120, 140))], "sword", "Fitting"


def x_haft_bands():
    lo, hi = bounds("hatchet_t3", "Wood")
    objs = []
    for z in (0.5, 0.78, 1.06):
        o = ls.cube("band", size=(hi.x - lo.x + 0.016, hi.y - lo.y + 0.016, 0.05), loc=(0, (lo.y + hi.y) / 2, z))
        ls.bevel(o, 0.01, 1)
        objs.append(o)
    return [(ls.join(objs, "bands"), "Wood", (112, 86, 60))], "hatchet", "Wood"


def x_verdigris_patches():
    lo, hi = bounds("hatchet_t3", "Blade")
    objs = []
    for i, (y, z, r) in enumerate(((0.06, 1.46, 0.045), (0.24, 1.36, 0.035), (0.2, 1.58, 0.03), (-0.08, 1.33, 0.03))):
        pts = [(y + r * random.uniform(0.7, 1.1) * math.cos(a), z + r * random.uniform(0.7, 1.1) * math.sin(a))
               for a in [2 * math.pi * k / 7 for k in range(7)]]
        objs.append(both_faces(plate, "patch%d" % i, hi.x + 0.0005, 0.004, pts))
    return [(ls.join(objs, "patches"), "Metal", (94, 158, 142))], "hatchet", "Blade"


def x_butt_cap():
    lo, hi = bounds("hatchet_t3", "Wood")
    o = ls.cube("cap", size=(hi.x - lo.x + 0.014, hi.y - lo.y + 0.014, 0.07), loc=(0, (lo.y + hi.y) / 2, lo.z + 0.02))
    ls.bevel(o, 0.012, 1)
    return [(o, "Metal", (176, 108, 70))], "hatchet", "Wood"


def x_sunburst():
    lo, hi = bounds("twin_axe_t3", "Blade")
    objs = []
    for side in (-1, 1):
        cy, cz = side * 0.42, 2.5
        objs.append(both_faces(plate, "disc%d" % side, hi.x + 0.0005, 0.008, poly_circle(cy, cz, 0.085, 12)))
        for k in range(8):
            a = 2 * math.pi * k / 8 + math.pi / 8
            r0, r1, w = 0.1, 0.18, 0.026
            tip = (cy + r1 * math.cos(a), cz + r1 * math.sin(a))
            p1 = (cy + r0 * math.cos(a) - w * math.sin(a), cz + r0 * math.sin(a) + w * math.cos(a))
            p2 = (cy + r0 * math.cos(a) + w * math.sin(a), cz + r0 * math.sin(a) - w * math.cos(a))
            objs.append(both_faces(plate, "ray%d_%d" % (side, k), hi.x + 0.0005, 0.006, [p1, tip, p2]))
    return [(ls.join(objs, "sunburst"), "Brass", (196, 156, 94))], "twin_axe", "Blade"


def x_fur_collar():
    lo, hi = bounds("twin_axe_t3", "Wood")
    blo, _ = bounds("twin_axe_t3", "Blade")
    z = blo.z - 0.07
    centres = []
    for k in range(10):
        a = 2 * math.pi * k / 10
        centres.append((0.07 * math.cos(a), 0.088 * math.sin(a), z + random.uniform(-0.02, 0.02)))
    o = lumps("fur", centres, 0.052, (1, 1, 1.25), 0.008)
    return [(o, "Cloth", (150, 146, 140))], "twin_axe", "Wood"


def _moon(asset):
    lo, hi = bounds(asset + "_t3", "Fitting")
    z = hi.z - 0.055
    disc = both_faces(plate, "moon", hi.x + 0.0005, 0.006, poly_circle(0.0, z, 0.036, 14))
    cres = []
    for a in range(-100, 101, 25):
        cres.append((0.036 * math.cos(math.radians(a)) * 0.98, z + 0.036 * math.sin(math.radians(a)) * 0.98))
    for a in range(100, -101, -25):
        cres.append((-0.014 + 0.03 * math.cos(math.radians(a)), z + 0.03 * math.sin(math.radians(a))))
    shade = both_faces(plate, "phase", hi.x + 0.0065, 0.003, cres)
    return [(disc, "Metal", (214, 214, 216)), (shade, "Metal", (96, 98, 104))]


def x_moon_discs():
    return _moon("paired_blades"), "paired_blades", "Fitting"


def x_moon_discs_L():
    return _moon("paired_blades_L"), "paired_blades_L", "Fitting"


def x_rope_lashing():
    lo, hi = bounds("spear_t3", "Wood")
    objs = []
    for i, z in enumerate((hi.z - 0.12, hi.z - 0.08, hi.z - 0.04, hi.z - 0.30, hi.z - 0.34)):
        objs.append(ls.torus("turn%d" % i, major=hi.x + 0.012, minor=0.016, major_segments=10, minor_segments=4, loc=(0, 0, z)))
    return [(ls.join(objs, "lashing"), "Rope", (200, 190, 164))], "spear", "Wood"


def x_lightning_inlay():
    lo, hi = bounds("spear_t3", "Blade")
    z0, z1 = lo.z + 0.05, hi.z - 0.13
    line = [(0.0, z0), (0.024, z0 + 0.09), (-0.018, z0 + 0.15), (0.02, z0 + 0.22), (-0.004, z1)]
    return [(both_faces(strip, "bolt", hi.x - 0.008, 0.011, line, 0.014), "Metal", (206, 210, 216))], "spear", "Blade"


def x_storm_ferrule():
    lo, hi = bounds("spear_t3", "Fitting")
    c = [(0.0, 0.0, lo.z + 0.06)] + [(0.045 * math.cos(a), 0.045 * math.sin(a), lo.z + 0.13 + 0.02 * math.sin(3 * a))
                                      for a in [2 * math.pi * k / 5 for k in range(5)]]
    o = lumps("cloud", c, 0.075, (1, 1, 0.8), 0.004)
    return [(o, "Brass", (170, 136, 80))], "spear", "Fitting"


def x_leaf_rest():
    lo, hi = bounds("bow_t3", "Grip")
    out = leaf2d(0.15, 0.08, 6, 0.2)
    bm = bmesh.new()
    z0 = hi.z + 0.004
    a = [bm.verts.new((0.02 + v * 0.9, -0.02 + u, z0)) for (u, v) in out]
    b = [bm.verts.new((0.02 + v * 0.9, -0.02 + u, z0 + 0.022)) for (u, v) in out]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    o = _obj("rest", bm)
    o.location.x = hi.x - 0.07
    return [(o, "Wood", (190, 122, 62))], "bow", "Grip"


def x_brass_spine():
    lo, hi = bounds("machete_t3", "Blade")
    o = ls.cube("spine", size=(hi.x - lo.x + 0.01, 0.018, 1.6), loc=(0, lo.y - 0.002, lo.z + 0.05 + 0.8))
    ls.bevel(o, 0.004, 1)
    return [(o, "Brass", (176, 142, 80))], "machete", "Blade"


EXTRAS = {
    "wave": x_wave, "temper_bands": x_temper_bands, "ricasso_collar": x_ricasso_collar, "oak_leaves": x_oak_leaves,
    "fuller_inlay": x_fuller_inlay, "crosshatch": x_crosshatch, "pommel_stone": x_pommel_stone,
    "haft_bands": x_haft_bands, "verdigris_patches": x_verdigris_patches, "butt_cap": x_butt_cap,
    "sunburst": x_sunburst, "fur_collar": x_fur_collar, "moon_discs": x_moon_discs, "rope_lashing": x_rope_lashing,
    "lightning_inlay": x_lightning_inlay, "storm_ferrule": x_storm_ferrule, "leaf_rest": x_leaf_rest,
    "brass_spine": x_brass_spine,
}


def tier_check(weapon, role):
    """Return the tiers whose anchor bounds differ from t3 by more than 5 thousandths of a stud."""
    names = [weapon] if weapon in WEAPONS else ["%s_t%d" % (weapon, t) for t in range(1, 6)]
    if len(names) == 1:
        return []
    ref = bounds(weapon + "_t3", role)
    off = []
    for t in range(1, 6):
        nm = "%s_t%d" % (weapon, t)
        if role not in WEAPONS[nm]["parts"]:
            off.append(t)
            continue
        b = bounds(nm, role)
        if max((b[0] - ref[0]).length, (b[1] - ref[1]).length) > 0.005:
            off.append(t)
    return off


skin_lib = ls.Library("SeasonOneSkinParts")
SKIN_PART_ROOTS = {}   # skin id -> [roots]
for s in SKINS:
    for key in s.get("extras", []):
        fns = [(key, EXTRAS[key])] + ([("moon_discs_L", x_moon_discs_L)] if key == "moon_discs" else [])
        for k2, fn in fns:
            parts, weapon, anchor = fn()
            name = "%s__%s" % (s["id"], k2)
            root = skin_lib.begin(name, kind="SkinPart", tags=["Cosmetic", "SkinPart"],
                                  notes="%s extra for %s (%s). Weld in the Grip frame of %s_t1..t5." % (k2, s["name"], s["weapon"], weapon))
            for (o, role, rgb) in parts:
                skin_lib.add(root, o, role, rgb=rgb, collide=False, collision="Box", cast_shadow=False)
            e = skin_lib.finish(root)
            e["skin"] = s["id"]
            e["weapon"] = weapon
            e["anchorRole"] = anchor
            e["frame"] = "Grip: the root sits at the weapon's Grip (origin of %s_tN). Parts keep their offsets." % weapon
            e["tiersDiffer"] = tier_check(weapon, anchor)
            SKIN_PART_ROOTS.setdefault(s["id"], []).append((root, weapon))

# ------------------------------------------------------------------------------------------------------------
# Props: kill effects, emotes, launch effects, the banner pole and the pennant
# ------------------------------------------------------------------------------------------------------------
props = ls.Library("SeasonOneProps")


def flat_shape(name, outline_xy, thick, z0=0.0):
    bm = bmesh.new()
    a = [bm.verts.new((x, y, z0)) for (x, y) in outline_xy]
    b = [bm.verts.new((x, y, z0 + thick)) for (x, y) in outline_xy]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    return _obj(name, bm)


def bend_up(o, amount):
    """Curl a flat piece: z += amount * x^2 (a petal or a leaf that is not dead flat)."""
    for v in o.data.vertices:
        v.co.z += amount * (v.co.x ** 2 + 0.4 * v.co.y ** 2)
    o.data.update()
    return o


# Bell Toll: a small brass bell with a yoke and a clapper
r = props.begin("KE_Bell", kind="KillEffectProp", notes="Bell Toll (#35): rings once above the figure; animate a swing about the Yoke attachment.")
bell = ls.lathe("bell", [(0.0, 0.0), (0.62, 0.0), (0.6, 0.06), (0.5, 0.2), (0.4, 0.55), (0.36, 0.85), (0.3, 1.0), (0.16, 1.08), (0.0, 1.1)], segments=14)
props.add(r, bell, "Brass", rgb=(176, 142, 80), collide=False)
lip = ls.torus("lip", major=0.6, minor=0.05, major_segments=14, minor_segments=4, loc=(0, 0, 0.04))
props.add(r, lip, "Brass", rgb=(150, 118, 64), collide=False)
clap = ls.icosphere("clapper", radius=0.13, subdivisions=1, loc=(0, 0, 0.12))
props.add(r, clap, "Metal", rgb=(96, 92, 86), collide=False)
yoke = ls.cube("yoke", size=(0.9, 0.18, 0.16), loc=(0, 0, 1.2))
ls.bevel(yoke, 0.03, 1)
props.add(r, yoke, "Wood", rgb=(110, 82, 58), collide=False)
props.attach(r, "Yoke", (0, 0, 1.2))
props.finish(r)

# Dust ring (Bell Toll, Dust Ring launch effect): a low lumpy ring to scale outwards
r = props.begin("FX_DustRing", kind="EffectProp", notes="A ring of dust: tween Size outwards and Transparency to 1 over 0.8 s.")
cs = [(2.0 * math.cos(a), 2.0 * math.sin(a), 0.18) for a in [2 * math.pi * k / 16 for k in range(16)]]
props.add(r, lumps("dust", cs, 0.42, (1.3, 1.3, 0.5), 0.05), "Dirt", rgb=(184, 172, 150), collide=False, cast_shadow=False)
props.finish(r)

# Recall Beam: an open column (the one effect allowed a brief light; Studio sets its transparency)
r = props.begin("KE_RecallColumn", kind="KillEffectProp", notes="Recall Beam (#38): 14-stud open column, scale Y 0 -> 1 then fade; SmoothPlastic at 0.6 transparency, never Neon in the arena.")
col = ls.cylinder("column", radius=1.6, radius_top=1.4, depth=14, segments=16, cap=False)
props.add(r, col, "Cloth", rgb=(244, 238, 222), collide=False, cast_shadow=False)
base = ls.torus("base", major=1.7, minor=0.12, major_segments=16, minor_segments=4, loc=(0, 0, 0.1))
props.add(r, base, "Cloth", rgb=(232, 224, 204), collide=False, cast_shadow=False)
props.finish(r)

# Flag Drop: a small cloth arena pennant on a stake (+ the folded state)
r = props.begin("KE_Pennant", kind="KillEffectProp", notes="Flag Drop (#36): plants beside the figure; flutter by swapping to _Folded at the end.")
stake = ls.cylinder("stake", radius=0.06, depth=3.0, segments=6, radius_top=0.05)
props.add(r, stake, "Wood", rgb=(132, 100, 70), collide=False)
tipc = ls.cylinder("tip", radius=0.06, depth=0.25, segments=6, radius_top=0.0, loc=(0, 0, -0.25))
props.add(r, tipc, "Metal", rgb=(120, 120, 118), collide=False)
knob = ls.icosphere("knob", radius=0.09, subdivisions=1, loc=(0, 0, 3.04))
props.add(r, knob, "Brass", rgb=(176, 142, 80), collide=False)
cloth_pts = [(0.0, 2.9), (1.3, 2.78), (1.0, 2.5), (1.3, 2.22), (0.0, 2.1)]
cl = plate("cloth", [(-x, z) for (x, z) in cloth_pts], -0.015, 0.03)
cl.rotation_euler = (0, 0, math.radians(90))
ls.refresh()
for v in cl.data.vertices:
    v.co.x += 0.06 * math.sin(v.co.y * 4.0)
props.add(r, cl, "Cloth", rgb=(232, 224, 204), collide=False)
stripe = plate("stripe", [(-0.0, 2.58), (-1.12, 2.55), (-1.12, 2.43), (-0.0, 2.42)], -0.02, 0.04)
stripe.rotation_euler = (0, 0, math.radians(90))
props.add(r, stripe, "Cloth", rgb=(108, 127, 160), collide=False)
props.finish(r)

r = props.begin("KE_Pennant_Folded", kind="KillEffectProp", notes="The pennant folded around its stake (end state of Flag Drop).")
props.add(r, ls.cylinder("stake", radius=0.06, depth=3.0, segments=6, radius_top=0.05), "Wood", rgb=(132, 100, 70), collide=False)
props.add(r, ls.cylinder("roll", radius=0.13, depth=0.8, segments=8, radius_top=0.1, loc=(0, 0, 2.1)), "Cloth", rgb=(232, 224, 204), collide=False)
props.add(r, ls.torus("tie", major=0.13, minor=0.025, major_segments=8, minor_segments=4, loc=(0, 0, 2.5)), "Cloth", rgb=(108, 127, 160), collide=False)
props.finish(r)

# Banner Unfurl + every banner: a pole with a crossbar and a 3:1 cloth that takes the banner image (UV 0..1)
r = props.begin("LE_BannerPole", kind="LaunchEffectProp", tags=["BannerCloth"],
                notes="Banner Unfurl (#59) and the banner on boards: the Cloth part has UVs 0..1 for the player's 768x256 banner "
                      "image (SurfaceAppearance ColorMap or a Decal on Front). _Furled is the rolled state under the crossbar.")
pole = ls.cylinder("pole", radius=0.09, depth=8.0, segments=8, radius_top=0.075)
props.add(r, pole, "Wood", rgb=(118, 88, 60), collide=False)
bar = ls.cylinder("bar", radius=0.06, depth=4.0, segments=8, loc=(-2.0, 0, 7.4), rot=(0, math.radians(90), 0))
props.add(r, bar, "Wood", rgb=(118, 88, 60), collide=False)
for x in (-2.05, 2.05):
    props.add(r, ls.icosphere("fin", radius=0.11, subdivisions=1, loc=(x, 0, 7.4)), "Brass", rgb=(176, 142, 80), collide=False)
props.add(r, ls.icosphere("top", radius=0.14, subdivisions=1, loc=(0, 0, 8.05)), "Brass", rgb=(176, 142, 80), collide=False)
# cloth: 12 x 4 faceted grid, 3.6 x 1.2 studs, hanging from the bar, a gentle wave in Y, UVs 0..1
bm = bmesh.new()
nx, nz, W, H = 12, 4, 3.6, 1.2
vs = [[bm.verts.new((-W / 2 + W * i / nx, 0.07 * math.sin(i * 1.3) + 0.03 * j, 7.3 - H * j / nz)) for i in range(nx + 1)] for j in range(nz + 1)]
uv = bm.loops.layers.uv.new("UVMap")
for j in range(nz):
    for i in range(nx):
        f = bm.faces.new((vs[j][i], vs[j + 1][i], vs[j + 1][i + 1], vs[j][i + 1]))
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = ((co.x + W / 2) / W, (co.z - (7.3 - H)) / H)
# give the cloth a little thickness on the back (copy with an offset, flipped) so it is not zero-thickness
back = bmesh.ops.duplicate(bm, geom=list(bm.faces))["geom"]
bverts = [g for g in back if isinstance(g, bmesh.types.BMVert)]
bmesh.ops.translate(bm, vec=Vector((0, 0.03, 0)), verts=bverts)
bfaces = [g for g in back if isinstance(g, bmesh.types.BMFace)]
bmesh.ops.reverse_faces(bm, faces=bfaces)
cloth = ls.from_bmesh("cloth", bm)
props.add(r, cloth, "Cloth", rgb=(232, 224, 204), collide=False, uv=False)
props.attach(r, "BannerTop", (0, 0, 7.3))
props.finish(r)

r = props.begin("LE_BannerPole_Furled", kind="LaunchEffectProp", notes="The banner rolled under the crossbar (start and end of Banner Unfurl).")
props.add(r, ls.cylinder("pole", radius=0.09, depth=8.0, segments=8, radius_top=0.075), "Wood", rgb=(118, 88, 60), collide=False)
props.add(r, ls.cylinder("bar", radius=0.06, depth=4.0, segments=8, loc=(-2.0, 0, 7.4), rot=(0, math.radians(90), 0)), "Wood", rgb=(118, 88, 60), collide=False)
props.add(r, ls.cylinder("roll", radius=0.16, depth=3.6, segments=8, loc=(-1.8, 0, 7.15), rot=(0, math.radians(90), 0)), "Cloth", rgb=(232, 224, 204), collide=False)
for x in (-1.2, 1.2):
    props.add(r, ls.torus("tie", major=0.17, minor=0.025, major_segments=8, minor_segments=4, loc=(x, 0, 7.15), rot=(0, math.radians(90), 0)), "Rope", rgb=(176, 150, 108), collide=False)
props.finish(r)

# Falling pieces for kill effects (MeshPart debris; the same shapes exist as particle sprites in art/icons)
PIECES = [
    ("FX_Petal", "Cloth", (240, 230, 210), lambda: bend_up(flat_shape("p", [(u - 0.25, v) for (u, v) in leaf2d(0.5, 0.32, 8)], 0.03), 0.5), "Petal Fall (#31)"),
    ("FX_LeafMaple", "Cloth", (184, 110, 64), None, "Leaf Swirl (#32), Leaf Ring (#58)"),
    ("FX_LeafOak", "Cloth", (168, 128, 62), lambda: bend_up(flat_shape("p", [(u - 0.35, v) for (u, v) in leaf2d(0.7, 0.36, 8, 0.16)], 0.03), 0.3), "Leaf Swirl (#32)"),
    ("FX_Feather", "Feather", (214, 210, 200), None, "Feather Burst (#34)"),
    ("FX_Confetti", "Paper", (232, 182, 90), lambda: bend_up(flat_shape("p", [(-0.14, -0.08), (0.14, -0.08), (0.14, 0.08), (-0.14, 0.08)], 0.03), 1.2), "Paper Confetti (#33): recolour per piece"),
    ("FX_Snowflake", "Snow", (226, 234, 242), None, "Frost Over (#37)"),
    ("FX_AshFlake", "Cloth", (176, 172, 164), lambda: flat_shape("p", [(-0.12, -0.08), (0.1, -0.1), (0.14, 0.04), (0.02, 0.12), (-0.12, 0.06)], 0.03), "Ash Scatter (#30)"),
]


def maple():
    """Five pointed lobes around a centre, with a short stem: one outline, no self-crossing."""
    pts = []
    lobes = [(90, 0.48), (90 - 52, 0.4), (90 - 110, 0.3), (90 + 110, 0.3), (90 + 52, 0.4)]
    lobes = sorted(lobes, key=lambda t: t[0])
    for i, (a, r) in enumerate(lobes):
        a2 = lobes[(i + 1) % len(lobes)][0] + (360 if i == len(lobes) - 1 else 0)
        pts.append((r * math.cos(math.radians(a)), r * math.sin(math.radians(a))))
        mid = math.radians((a + a2) / 2)
        pts.append((0.13 * math.cos(mid), 0.13 * math.sin(mid)))
    o = flat_shape("p", pts, 0.03)
    stem = ls.cube("stem", size=(0.03, 0.22, 0.03), loc=(0, -0.2, 0.015))
    return bend_up(ls.join([o, stem], "maple"), 0.3)


def feather_mesh():
    out = [(u - 0.4, v) for (u, v) in leaf2d(0.8, 0.22, 10)]
    o = flat_shape("p", out, 0.02)
    shaft = ls.cube("shaft", size=(1.0, 0.03, 0.04), loc=(-0.05, 0, 0.02))
    return bend_up(ls.join([o, shaft], "feather"), 0.25)


def snowflake_mesh():
    objs = []
    for k in range(3):
        objs.append(ls.cube("arm", size=(0.6, 0.06, 0.03), loc=(0, 0, 0.015 + 0.004 * k), rot=(0, 0, math.radians(60 * k))))
        for s in (-1, 1):
            for d in (-1, 1):
                a = math.radians(60 * k)
                cx, cy = s * 0.18 * math.cos(a), s * 0.18 * math.sin(a)
                objs.append(ls.cube("tw", size=(0.14, 0.04, 0.03), loc=(cx, cy, 0.006 + 0.003 * (d + 1)), rot=(0, 0, a + d * math.radians(50))))
    return ls.join(objs, "flake")


for (nm, role, rgb, fn, note) in PIECES:
    r = props.begin(nm, kind="EffectPiece", tags=["Debris"], notes=note + ". Non-colliding debris piece; spawn many, anchored tweens or Massless.")
    o = maple() if nm == "FX_LeafMaple" else feather_mesh() if nm == "FX_Feather" else snowflake_mesh() if nm == "FX_Snowflake" else fn()
    props.add(r, o, role, rgb=rgb, collide=False, collision="Box", cast_shadow=False)
    props.finish(r)

# Emote props
r = props.begin("EM_Whetstone", kind="EmoteProp", notes="Whetstone (#51): held in the left hand (Grip attachment).")
w = ls.cube("stone", size=(0.22, 0.85, 0.16), loc=(0, 0, 0.08))
ls.bevel(w, 0.04, 1)
props.add(r, w, "Stone", rgb=(128, 124, 116), collide=False)
props.attach(r, "Grip", (0, 0, 0.08))
props.finish(r)

r = props.begin("EM_MapOpen", kind="EmoteProp", notes="Map Check (#53): the unfolded paper map, three panels with soft folds; both hands hold the outer edges.")
panels = []
for i, ang in enumerate((-14, 0, 14)):
    p = ls.cube("panel%d" % i, size=(0.62, 0.02, 0.9), loc=((i - 1) * 0.6, abs(i - 1) * 0.07, 0.45), rot=(0, 0, math.radians(ang)))
    panels.append(p)
props.add(r, ls.join(panels, "map"), "Paper", rgb=(222, 206, 166), collide=False)
props.add(r, ls.cube("route", size=(1.2, 0.03, 0.03), loc=(0.0, -0.005, 0.5), rot=(0, math.radians(18), 0)), "Paper", rgb=(140, 86, 60), collide=False)
props.finish(r)

r = props.begin("EM_MapFolded", kind="EmoteProp", notes="Map Check (#53): the folded map, taken from and put back in the belt.")
props.add(r, ls.cube("map", size=(0.62, 0.08, 0.9), loc=(0, 0, 0.45)), "Paper", rgb=(222, 206, 166), collide=False)
props.finish(r)

r = props.begin("EM_Campfire", kind="EmoteProp", notes="Campfire Hands (#54): logs and a stone ring; the flame is a Fire/ParticleEmitter at the Flame attachment. Fades in and out.")
logs = []
for k in range(5):
    a = 2 * math.pi * k / 5
    lg = ls.cylinder("log%d" % k, radius=0.09, depth=0.72, segments=6, loc=(0.62 * math.cos(a), 0.62 * math.sin(a), 0.06))
    lg.rotation_euler = (0, math.radians(-72), a)
    logs.append(lg)
props.add(r, ls.join(logs, "logs"), "Logs", rgb=(110, 82, 58), collide=False)
stones = [(0.82 * math.cos(a), 0.82 * math.sin(a), 0.08) for a in [2 * math.pi * k / 11 for k in range(11)]]
props.add(r, lumps("stones", stones, 0.13, (1.2, 1.0, 0.7), 0.02), "Stone", rgb=(122, 118, 110), collide=False)
props.attach(r, "Flame", (0, 0, 0.3))
props.finish(r)

# ------------------------------------------------------------------------------------------------------------
# The five Gold crates (one base; separate lid with a hinge attachment for the reveal)
# ------------------------------------------------------------------------------------------------------------
crates = ls.Library("SeasonOneCrates")
CW, CD, CH, LH = 2.4, 1.6, 1.15, 0.45     # width (x), depth (y), body height, lid height


def box(name, sx, sy, sz, loc, bev=0.04):
    o = ls.cube(name, size=(sx, sy, sz), loc=loc)
    if bev:
        ls.bevel(o, bev, 1)
    return o


def planks_body(name):
    objs = [box("floor", CW - 0.1, CD - 0.1, 0.1, (0, 0, 0.05), 0.02)]
    n = 3
    h = CH / n
    for i in range(n):
        z = h * (i + 0.5)
        for (sx, sy, x, y) in ((CW, 0.1, 0, CD / 2 - 0.05), (CW, 0.1, 0, -CD / 2 + 0.05), (0.1, CD - 0.2, CW / 2 - 0.05, 0), (0.1, CD - 0.2, -CW / 2 + 0.05, 0)):
            objs.append(box("pl", sx - (0.0 if sx > 1 else 0), sy, h - 0.035, (x, y, z), 0.025))
    return ls.join(objs, name)


def planks_lid(name):
    objs = []
    n = 4
    for i in range(n):
        y = -CD / 2 + CD * (i + 0.5) / n
        objs.append(box("lp", CW + 0.04, CD / n - 0.03, 0.12, (0, y, CH + LH - 0.06), 0.025))
    objs.append(box("rim", CW + 0.04, CD + 0.04, LH - 0.12, (0, 0, CH + (LH - 0.12) / 2), 0.03))
    return ls.join(objs, name)


def steel_body(name):
    o = box(name, CW, CD, CH, (0, 0, CH / 2), 0.06)
    return o


def steel_lid(name):
    base_ = box("lid", CW + 0.06, CD + 0.06, LH * 0.6, (0, 0, CH + LH * 0.3), 0.05)
    top = box("lidtop", CW - 0.12, CD - 0.12, LH * 0.4, (0, 0, CH + LH * 0.8), 0.08)
    return ls.join([base_, top], name)


def rivets(name, pts, r=0.045):
    return ls.join([ls.icosphere("rv", radius=r, subdivisions=1, loc=p, scale=(1, 0.6, 1)) for p in pts], name)


def latch(name, z, col_role, rgb, lib, root, w=0.26, h=0.3):
    o = box(name, w, 0.08, h, (0, -CD / 2 - 0.04, z), 0.02)
    lib.add(root, o, col_role, rgb=rgb, collide=False)


CRATES = [
    ("Crate_Timber", 300, "Planks and rope handles"),
    ("Crate_Ironbound", 750, "Planks with two iron bands"),
    ("Crate_Steel", 1500, "Riveted grey steel with a brass latch"),
    ("Crate_Silverleaf", 3000, "Pale silver-grey steel with a pressed leaf on the lid"),
    ("Crate_Crown", 6000, "Dark slate-blue steel with a brass crown boss and a brass foot rail"),
]
for (nm, price, look) in CRATES:
    root = crates.begin(nm, kind="Crate", tags=["Crate"], notes="%s Gold. %s. The Lid parts open about the LidHinge attachment (back top edge)." % (price, look))
    if nm in ("Crate_Timber", "Crate_Ironbound"):
        crates.add(root, planks_body("body"), "Planks", rgb=(142, 108, 74), collide=True, collision="Box")
        lid = planks_lid("lid")
        crates.add(root, lid, "Planks", rgb=(126, 94, 64), collide=True, collision="Box")
        crates._entry(root)["parts"][-1]["lid"] = True
        if nm == "Crate_Timber":
            for x in (-CW / 2 - 0.06, CW / 2 + 0.06):
                h_ = ls.torus("handle", major=0.2, minor=0.04, major_segments=10, minor_segments=4, loc=(x, 0, CH * 0.62), rot=(0, math.radians(90), 0))
                crates.add(root, h_, "Rope", rgb=(176, 150, 108), collide=False)
            latch("latch", CH - 0.08, "Wood", (96, 72, 50), crates, root)
        else:
            for x in (-0.65, 0.65):
                band = box("band", 0.16, CD + 0.06, CH + 0.02, (x, 0, CH / 2), 0.02)
                crates.add(root, band, "DarkMetal", rgb=(86, 88, 90), collide=False)
                lb = box("lidband", 0.16, CD + 0.1, LH + 0.04, (x, 0, CH + LH / 2), 0.02)
                crates.add(root, lb, "DarkMetal", rgb=(86, 88, 90), collide=False)
                crates._entry(root)["parts"][-1]["lid"] = True
            crates.add(root, rivets("rv", [(x, -CD / 2 - 0.03, z) for x in (-0.65, 0.65) for z in (0.25, 0.6, 0.95)]), "Metal", rgb=(140, 142, 144), collide=False)
            latch("latch", CH - 0.08, "Metal", (130, 132, 134), crates, root)
    else:
        body_rgb, lid_rgb, trim_role, trim_rgb = {
            "Crate_Steel": ((112, 118, 122), (132, 138, 142), "Brass", (176, 142, 80)),
            "Crate_Silverleaf": ((184, 190, 194), (204, 208, 212), "Metal", (122, 128, 134)),
            "Crate_Crown": ((66, 78, 92), (84, 98, 112), "Brass", (176, 142, 80)),
        }[nm]
        crates.add(root, steel_body("body"), "Metal", rgb=body_rgb, collide=True, collision="Box")
        crates.add(root, steel_lid("lid"), "Metal", rgb=lid_rgb, collide=True, collision="Box")
        crates._entry(root)["parts"][-1]["lid"] = True
        rim = box("rim", CW + 0.04, CD + 0.04, 0.1, (0, 0, CH - 0.05), 0.02)
        crates.add(root, rim, "Metal", rgb=tuple(max(40, c - 24) for c in body_rgb), collide=False)
        pts = [(x, -CD / 2 - 0.01, z) for x in (-1.08, -0.54, 0.54, 1.08) for z in (0.18, 0.95)]
        pts += [(x, CD / 2 + 0.01, z) for x in (-1.08, 1.08) for z in (0.18, 0.95)]
        crates.add(root, rivets("rv", pts), "Metal", rgb=tuple(min(230, c + 30) for c in body_rgb), collide=False)
        latch("latch", CH - 0.06, trim_role, trim_rgb, crates, root, 0.34, 0.36)
        if nm == "Crate_Silverleaf":
            out = [(u - 0.45, v) for (u, v) in leaf2d(0.9, 0.42, 10, 0.18)]
            lf = flat_shape("leaf", out, 0.03, CH + LH)
            lf.rotation_euler = (0, 0, math.radians(25))
            crates.add(root, lf, "Metal", rgb=(150, 158, 164), collide=False)
            crates._entry(root)["parts"][-1]["lid"] = True
            vein = box("vein", 0.8, 0.03, 0.03, (0, 0, CH + LH + 0.03), 0)
            vein.rotation_euler = (0, 0, math.radians(25))
            crates.add(root, vein, "Metal", rgb=(132, 140, 146), collide=False)
            crates._entry(root)["parts"][-1]["lid"] = True
        if nm == "Crate_Crown":
            crown_pts = [(-0.34, 0.0), (0.34, 0.0), (0.34, 0.22), (0.22, 0.12), (0.12, 0.34), (0.0, 0.16), (-0.12, 0.34), (-0.22, 0.12), (-0.34, 0.22)]
            boss = plate("boss", [(x, CH * 0.38 + z) for (x, z) in crown_pts], 0, 0.06)
            boss.rotation_euler = (0, 0, math.radians(90))
            boss.location.y = -CD / 2 - 0.03
            # plate() builds in the (y, z) plane at x = 0; rotate so it faces -Y (the front)
            crates.add(root, boss, "Brass", rgb=(186, 150, 86), collide=False)
            lb = flat_shape("lidboss", [(x * 0.8, z * 0.8 - 0.12) for (x, z) in crown_pts], 0.04, CH + LH - 0.005)
            crates.add(root, lb, "Brass", rgb=(186, 150, 86), collide=False)
            crates._entry(root)["parts"][-1]["lid"] = True
            rail = box("rail", CW + 0.16, CD + 0.16, 0.12, (0, 0, 0.06), 0.03)
            crates.add(root, rail, "Brass", rgb=(166, 134, 76), collide=False)
    crates.attach(root, "LidHinge", (0, CD / 2, CH))
    crates.attach(root, "Reveal", (0, 0, CH + 0.4))
    crates.finish(root)

# ------------------------------------------------------------------------------------------------------------
# Matte studio renders (skins, props, crates) for the owner sheets and the skin tile fallbacks
# ------------------------------------------------------------------------------------------------------------
def lin(rgb):
    return [ls.srgb_to_linear(c / 255.0) for c in rgb]


_studio = {}


def studio():
    sc = bpy.context.scene
    if "cam" in _studio:
        return sc, _studio["cam"]
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("studio")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.32, 0.33, 0.35, 1)
    bg.inputs["Strength"].default_value = 0.9
    sc.world = world
    sun = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN"))
    sun.data.energy = 4.6
    sun.data.angle = math.radians(12)
    sun.rotation_euler = (math.radians(40), math.radians(-25), math.radians(35))
    sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 1.4
    fill.rotation_euler = (math.radians(70), math.radians(40), math.radians(-150))
    sc.collection.objects.link(fill)
    cam = bpy.data.objects.new("scam", bpy.data.cameras.new("scam"))
    cam.data.type = "ORTHO"
    cam.data.clip_end = 500
    sc.collection.objects.link(cam)
    sc.camera = cam
    _studio["cam"] = cam
    return sc, cam


def preview_mat(rgb, rmat):
    key = ("mat", tuple(rgb), rmat)
    m = _studio.get(key)
    if m:
        return m
    m = bpy.data.materials.new("pv_%d_%d_%d_%s" % (rgb[0], rgb[1], rgb[2], rmat))
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    c = lin(rgb)
    b.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1)
    metal = rmat in ("Metal", "DiamondPlate")
    b.inputs["Metallic"].default_value = 0.45 if metal else 0.0
    b.inputs["Roughness"].default_value = 0.55 if metal else 0.85
    _studio[key] = m
    return m


def frame_and_render(objs, path, res=(640, 256), view=(0.0, -90.0, 0.0), roll=0.0, margin=1.12):
    """Ortho camera looking along `view` (Euler deg of the camera); fits the objects; renders a transparent PNG."""
    sc, cam = studio()
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    keep = set(objs)
    for o in sc.objects:
        if o.type == "MESH":
            o.hide_render = o not in keep
    cam.rotation_euler = [math.radians(v) for v in view]
    cam.rotation_euler.rotate_axis("Z", math.radians(roll))
    ls.refresh()
    R = cam.matrix_world.to_3x3()
    inv = R.transposed()
    pts = []
    for o in objs:
        for v in o.data.vertices:
            pts.append(inv @ (o.matrix_world @ v.co))
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    c = (lo + hi) / 2
    cam.location = R @ Vector((c.x, c.y, hi.z + 20))
    w, h = hi.x - lo.x, hi.y - lo.y
    aspect = res[0] / res[1]
    cam.data.ortho_scale = max(w, h * aspect) * margin
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in sc.objects:
        if o.type == "MESH":
            o.hide_render = True


def recipe_colour(recipe, part_role, finish_role, default_rgb, default_mat):
    roles = recipe
    rgb, mat = default_rgb, default_mat
    grp = GROUP_OF.get(finish_role)
    if part_role in ("Inlay",) and "Brass" in roles:
        grp = "Brass"
    if grp and grp in roles and not (grp == "Steel" and part_role == "Edge"):
        v = roles[grp]
        rgb, mat = (v[0], v[1]) if isinstance(v[0], tuple) else (v, mat)
        if grp == "Steel" and part_role in ("LayerLight", "LayerDark", "Etch"):
            d = {"LayerLight": 18, "LayerDark": -22, "Etch": -30}[part_role]
            rgb = tuple(max(40, min(235, c + d)) for c in rgb)
    if part_role in roles:
        v = roles[part_role]
        rgb, mat = (v[0], v[1]) if isinstance(v[0], tuple) else (v, mat)
    return tuple(rgb), mat


def skinned_parts(asset, roles):
    """[(obj, rgb, material)] for one WeaponsV3 asset under a recipe."""
    out = []
    for p in WV3_ASSETS[asset]["parts"]:
        role = p["name"][len(asset) + 1:]
        o = WEAPONS[asset]["parts"].get(role)
        if o is None:
            continue
        rgb, mat = recipe_colour(roles, role, p["finishRole"], tuple(p["rgb"]), p["robloxMaterial"])
        out.append((o, rgb, mat, p))
    return out


SKIN_TILES = []   # (id, png)
skin_records = []
render_dir = os.path.join(PREV, "skins")
os.makedirs(render_dir, exist_ok=True)


def render_skin(s, roles, rolesL, weapon, tier=3, suffix=""):
    assets = [weapon]
    if weapon in ("paired_blades",):
        assets = ["paired_blades", "paired_blades_L"]
    objs = []
    moved = []
    for i, a in enumerate(assets):
        nm = a if a in WEAPONS else "%s_t%d" % (a, tier)
        root = WEAPONS[nm]["root"]
        moved.append((root, root.location.copy(), root.rotation_euler.copy()))
        root.location = (0.0, 0.0 + (0.55 if i == 1 else 0.0), 0.0)
        rr = roles if (i == 0 or rolesL is None) else rolesL
        for (o, rgb, mat, p) in skinned_parts(nm, rr):
            o.data.materials.clear()
            o.data.materials.append(preview_mat(rgb, mat))
            objs.append(o)
    for (root, wpn) in SKIN_PART_ROOTS.get(s["id"], []):
        for c in root.children:
            if c.type == "MESH":
                p = next(pp for pp in skin_lib._entry(root)["parts"] if pp["name"] == c.name)
                c.data.materials.clear()
                c.data.materials.append(preview_mat(p["rgb"], p["robloxMaterial"]))
                if wpn == "paired_blades_L":
                    root.location = (0, 0.55, 0)
                objs.append(c)
    ls.refresh()
    path = os.path.join(render_dir, s["id"] + suffix + ".png")
    # lay the weapon diagonally: look from +X at the flat of the blade, slightly from the front, rolled
    frame_and_render(objs, path, (512, 205), view=(90.0, 0.0, 90.0 - 18.0), roll=-70.0, margin=1.06)
    for (root, loc, rot) in moved:
        root.location, root.rotation_euler = loc, rot
    for (root, wpn) in SKIN_PART_ROOTS.get(s["id"], []):
        root.location = (0, 0, 0)
    return path


for s in SKINS:
    rolesL = s.get("rolesL")
    if rolesL == "same":
        rolesL = s["roles"]
    p = render_skin(s, s["roles"], rolesL, s["weapon"])
    SKIN_TILES.append((s["id"], p))
# tier check: every skin with extra parts, also on its 1-star and 5-star meshes (looked at before export)
check_dir = os.path.join(render_dir, "_tiercheck")
for s in SKINS:
    if s.get("extras") and s["weapon"] in [w.rsplit("_t", 1)[0] for w in WEAPONS]:
        rolesL = s["roles"] if s.get("rolesL") == "same" else s.get("rolesL")
        for t in (1, 5):
            render_skin(s, s["roles"], rolesL, s["weapon"], tier=t, suffix="__t%d" % t)
for wr in WRAPS:
    s2 = dict(wr)
    p = render_skin(s2, wr["roles"], None, "sword")
    SKIN_TILES.append((wr["id"], p))

# props and crates: one studio render each (three-quarter view)
prop_dir = os.path.join(PREV, "props")
os.makedirs(prop_dir, exist_ok=True)
PROP_TILES = []
for lib in (props, crates):
    for e in lib.assets:
        meshes = [c for c in e["root"].children_recursive if c.type == "MESH"]
        for c in meshes:
            p = next(pp for pp in e["parts"] if pp["name"] == c.name)
            c.data.materials.clear()
            c.data.materials.append(preview_mat(p["rgb"], p["robloxMaterial"]))
        path = os.path.join(prop_dir, e["name"] + ".png")
        frame_and_render(meshes, path, (384, 384), view=(68.0, 0.0, 35.0), roll=0.0, margin=1.15)
        PROP_TILES.append((e["name"], path))
        # restore Library materials for export
        for c in meshes:
            p = next(pp for pp in e["parts"] if pp["name"] == c.name)
            c.data.materials.clear()
            c.data.materials.append(ls.material(p["role"], tuple(p["rgb"])))
for e in skin_lib.assets:
    for c in [c for c in e["root"].children_recursive if c.type == "MESH"]:
        p = next(pp for pp in e["parts"] if pp["name"] == c.name)
        c.data.materials.clear()
        c.data.materials.append(ls.material(p["role"], tuple(p["rgb"])))

# hide the imported weapons from everything below (Library previews render with Workbench)
for w in WEAPONS.values():
    for c in w["parts"].values():
        c.hide_render = True
        c.hide_set(True)

# ------------------------------------------------------------------------------------------------------------
# Export
# ------------------------------------------------------------------------------------------------------------
man_parts = skin_lib.export(out_dir, preview_dir)
man_props = props.export(out_dir, preview_dir)
man_crates = crates.export(out_dir, preview_dir)


def recipe_json(roles):
    out = {}
    for k, v in roles.items():
        if isinstance(v[0], tuple):
            out[k] = {"rgb": list(v[0]), "robloxMaterial": v[1]}
        else:
            out[k] = {"rgb": list(v)}
    return out


skins_manifest = {
    "category": "SeasonOneSkins",
    "design": "docs/design/CardMenusAndShop.md 3.1 (items 1-29)",
    "generator": "art/blender/season_one.py + season_one_skins.py",
    "rule": ("A skin re-colours the parts of every star tier (WeaponsV3 <weapon>_t1..t5) by role. Order: group keys by "
             "the part's finishRole (Steel = every Steel role except Edge; Leather; Cord; Wood; Brass = Brass + Inlay; Rope), "
             "then role keys. With a Steel key, LayerLight/LayerDark/Etch follow it (+18/-22/-30) unless named. Roles not named "
             "keep their star finish. robloxMaterial when given replaces the part's Material (matte: no Reflectance). "
             "extraParts are SeasonOneSkinParts assets whose root is the weapon's Grip: weld each part at its offset from that "
             "root (the WeaponsV3 core geometry is identical in t1..t5, checked per anchor; tiersDiffer lists any exception). "
             "Wraps (weapon '*') apply to every weapon. Stars still show on the tile; skins never change stats or silhouette."),
    "skins": [],
}
for s in SKINS + WRAPS:
    rec = {k: s[k] for k in ("n", "id", "weapon", "name", "grade", "source", "look")}
    rec["roles"] = recipe_json(s["roles"])
    rl = s.get("rolesL")
    if rl:
        rec["rolesLeft"] = recipe_json(s["roles"] if rl == "same" else rl)
    rec["extraParts"] = ["%s__%s" % (s["id"], k) for k in s.get("extras", [])] + \
        (["%s__moon_discs_L" % s["id"]] if "moon_discs" in s.get("extras", []) else [])
    rec["preview"] = os.path.relpath(os.path.join(render_dir, s["id"] + ".png"), os.path.dirname(os.path.dirname(preview_dir))).replace("\\", "/")
    skins_manifest["skins"].append(rec)
with open(os.path.join(out_dir, "SeasonOneSkins.manifest.json"), "w", encoding="utf-8") as f:
    json.dump(skins_manifest, f, indent=1)

# ------------------------------------------------------------------------------------------------------------
# Skin tile fallbacks: 640 x 256 cells, 1 x 4 per 1024 sheet (transparent)
# ------------------------------------------------------------------------------------------------------------
if ICON_DIR:
    import numpy as np
    os.makedirs(ICON_DIR, exist_ok=True)

    def read(path):
        img = bpy.data.images.load(path, check_existing=False)
        w, h = img.size
        a = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(a)
        bpy.data.images.remove(img)
        return a.reshape(h, w, 4)[::-1].copy()

    def write(path, arr):
        h, w = arr.shape[:2]
        img = bpy.data.images.new("o", w, h, alpha=True)
        img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).ravel())
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)

    rects = {}
    sheets = []
    for i, (sid, path) in enumerate(SKIN_TILES):
        if i % 8 == 0:
            sheets.append(np.zeros((1024, 1024, 4), dtype=np.float32))
        k = i % 8
        arr = read(path)
        x, y = (k % 2) * 512, (k // 2) * 256 + 25
        sheets[-1][y:y + arr.shape[0], x:x + arr.shape[1]] = arr
        rects[sid] = dict(sheet="SkinTiles_%d" % len(sheets), x=x, y=y, w=arr.shape[1], h=arr.shape[0])
    for n, arr in enumerate(sheets, 1):
        write(os.path.join(ICON_DIR, "SkinTiles_%d.png" % n), arr)
    with open(os.path.join(ICON_DIR, "SkinTiles.json"), "w", encoding="utf-8") as f:
        json.dump(dict(note="Fallback pictures (512 x 205, 2.5:1) for skin tiles past the 24 live ViewportFrames. Not uploaded.",
                       sheets={"SkinTiles_%d" % n: dict(file="SkinTiles_%d.png" % n, size=[1024, 1024], assetId="") for n in range(1, len(sheets) + 1)},
                       tiles=rects), f, indent=1)

index = dict(
    folder="BlenderExports/SeasonOne",
    design="docs/design/CardMenusAndShop.md (season one)",
    files=dict(
        skins="SeasonOneSkins.manifest.json (26 skins + 3 wraps as recipes on WeaponsV3; no upload needed for a recipe)",
        skinParts="SeasonOneSkinParts.glb + .manifest.json (%d assets)" % len(man_parts["assets"]),
        props="SeasonOneProps.glb + .manifest.json (%d assets)" % len(man_props["assets"]),
        crates="SeasonOneCrates.glb + .manifest.json (%d assets)" % len(man_crates["assets"]),
    ),
    upload="Nothing uploaded. Each GLB uploads once as a Model after the owner's yes (art/README.md).",
)
with open(os.path.join(out_dir, "SeasonOne.index.json"), "w", encoding="utf-8") as f:
    json.dump(index, f, indent=1)
print("SEASON ONE DONE", len(SKIN_TILES), "skin renders,", len(PROP_TILES), "prop renders")
