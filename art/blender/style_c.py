"""
style_c.py - LAST STANDING style test, VARIANT C: "Smooth stylized realism" (Blender 5.3, headless).

    blender --background --factory-startup --python art/blender/style_c.py -- <out_dir> <preview_dir>
            [stages=ground,assets,preview] [only=Spruce,Oak,Cabin,Boulder] [samples=96] [res=1600x900]

    out_dir      default %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/StyleTest/C
    preview_dir  default art/previews/StyleTest/C

What it makes (everything modelled / sculpted / baked here - no downloaded models, textures or AI images):
  StyleTest_C.glb              StyleC_Spruce, StyleC_Oak, StyleC_Cabin, StyleC_Boulder (row along X, origins in the
                               manifest), textures embedded, tangents on every primitive, single-sided materials
  StyleTest_C.manifest.json    parts, collision, attachments, SurfaceAppearance blocks, terrain MaterialVariants,
                               style rules, GLB check
  textures/                    upload PNGs: <Asset>_Color / _Normal (1024, OpenGL) / _Rough (512, 8-bit gray);
                               StyleC_PebblePath_* and StyleC_ForestFloor_* (1024 Color + Normal + Roughness) for
                               terrain MaterialVariants. textures/glb_only/*_MR.png are the packed glTF copies
                               embedded in the GLB - never upload them.
  <preview_dir>                Cycles reviews of the exported GLB + PNGs: eye level beside a 5.5-stud figure at
                               midday and in late-afternoon sun, close-ups, ground-texture sheet.

Style C in one line: chunky rounded volumes with real-world proportions (sculpted SDF clumps, soft bevels, rounded
log ends), painted value gradients + baked AO in the colour map, soft large-scale normal detail, matte PBR.
"""
import json
import math
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy
import numpy as np
from mathutils import Vector

import style_c_lib as L
import tex_ground as tg

VARIANT = "C"
PREFIX = "StyleC"
STYLE_NAME = "Smooth stylized realism"
RES = 1024
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
POS_ARGS = [a for a in ARGS if "=" not in a]
OPTS = dict(a.split("=", 1) for a in ARGS if "=" in a)
EXPORTS = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")
OUT = os.path.abspath(POS_ARGS[0]) if POS_ARGS else os.path.join(EXPORTS, "StyleTest", VARIANT)
PREV = os.path.abspath(POS_ARGS[1]) if len(POS_ARGS) > 1 else os.path.normpath(
    os.path.join(HERE, "..", "previews", "StyleTest", VARIANT))
STAGES = OPTS.get("stages", "ground,assets,preview").split(",")
ONLY = OPTS.get("only", "Spruce,Oak,Cabin,Boulder").split(",")
TEX = os.path.join(OUT, "textures")
GLB_ONLY = os.path.join(TEX, "glb_only")
REL = "StyleTest/%s/textures/" % VARIANT          # manifest paths are relative to BlenderExports
REPO_MANIFESTS = os.path.normpath(os.path.join(HERE, "..", "manifests"))
GLB_NAME = "StyleTest_%s" % VARIANT
for d in (OUT, TEX, GLB_ONLY, PREV):
    os.makedirs(d, exist_ok=True)

ROBLOX_MATERIAL = {"Needles": "LeafyGrass", "Leaves": "LeafyGrass", "Bark": "Wood", "Rock": "Rock",
                   "Logs": "Wood", "Roof": "WoodPlanks", "Porch": "WoodPlanks", "Floor": "WoodPlanks",
                   "Trim": "WoodPlanks", "Stone": "Cobblestone", "Glass": "Glass", "Chinking": "Plaster",
                   "PorchRoof": "WoodPlanks", "Posts": "Wood", "Gable": "WoodPlanks"}

STYLE_RULES = [
    "Shape first: chunky, rounded volumes at real-world scale (1 stud = 0.28 m; door 4 x 7.5, spruce 35-50, oak "
    "25-30, logs 1 stud thick). Every edge carries a soft bevel or rounding (>= 0.1 stud); no razor edges, no thin "
    "slivers.",
    "Foliage is sculpted, closed clump volumes (SDF smooth-unions of boughs / leaf masses, meshed and decimated), "
    "never alpha cards: spruce = drooping fanned tiers, broadleaf = big lumpy masses with flatter undersides and "
    "gaps that show the limbs.",
    "Colour is painted, not photographed: every albedo is a soft value gradient (light tops / tips / outer crown -> "
    "dark undersides / interiors, warm-cool drift over 5-15 studs) multiplied by baked AO (near 0.6-1.8 + far 2.5-6 "
    "studs). No noise or grain finer than ~0.3 stud.",
    "Normal maps hold only soft, large detail (bark plates, leaf-mass lumps, wood grain, stone pitting) at "
    "moderate strength; silhouettes and big forms come from geometry.",
    "Palette: slightly desaturated naturals (sRGB) - needles 20-100, broadleaf green channel 38-145, bark 50-130, "
    "weathered logs 95-160, stone 90-160, soil 60-130; saturated accents only small and purposeful.",
    "Materials are matte PBR: roughness 0.74-0.95 for nature and wood, metalness 0 (no map); glass is the only "
    "smooth surface.",
    "Organic assets get one unique 1024 page each (Color+AO / Normal / Roughness 512, ~15-40 px/stud, shared by all "
    "parts of the asset). Buildings use a shared kit page: tiling trims (logs, planks, shakes, end grain) at "
    "50-128 px/stud with contact occlusion painted in, plus a uniquely baked region for stonework.",
    "Terrain MaterialVariants are 1024 px tiles over 10-12 studs (85-100 px/stud) built from modelled elements "
    "(rounded pebbles, leaves, twigs) rendered top-down in Blender: clean shapes, soft contact AO, broad colour "
    "drift only, MaterialPattern Organic.",
    "Budgets: trees <= 15k tris, buildings <= 16k, rocks <= 2k, every MeshPart < 20k; GLB with tangents, normals "
    "and UVs, single-sided, metallicFactor 0.",
    "Collision as gameplay reads: canopies and needles non-colliding (hide-able), trunks Hull, climbable oak wood "
    "PreciseConvexDecomposition + Climbable tag + Perch attachments, walls with openings PreciseConvexDecomposition.",
]


def log(*a):
    print(*a, flush=True)


# =============================================================================================== export material
_IMG_CACHE = {}


def export_material(name, color_png, normal_png, mr_png):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    def img(path, cs):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = cs
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    tc = img(color_png, "sRGB")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tn = img(normal_png, "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.space = "TANGENT"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    tr = img(mr_png, "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    m.use_backface_culling = True
    return m


def write_page(page, col, nrm_enc, rough, cover):
    """Fill uncovered texels (push-pull) and write the upload PNGs + the packed glTF MR copy."""
    col = L.fill_uncovered(col, cover)
    nrm = L.fill_uncovered(nrm_enc, cover)
    rg = L.fill_uncovered(rough[..., None], cover)[..., 0]
    files = {"color": "%s_Color.png" % page, "normal": "%s_Normal.png" % page, "rough": "%s_Rough.png" % page,
             "mr": "%s_MR.png" % page}
    L.write_color(os.path.join(TEX, files["color"]), col)
    L.write_normal(os.path.join(TEX, files["normal"]), nrm)
    L.write_gray(os.path.join(TEX, files["rough"]), rg, size=512)
    L.write_mr(os.path.join(GLB_ONLY, files["mr"]), rg, size=512)
    return files


# =============================================================================================== assets
class Lib:
    def __init__(self):
        self.assets = []
        self.warnings = []
        self.pages = {}

    def add_asset(self, name, kind, parts, page_files, mat, attach=None, notes="", extra=None, tags=None,
                  part_rgb=None):
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        bpy.context.scene.collection.objects.link(root)
        counts = {}
        entry = {"name": name, "kind": kind, "tags": list(tags or []), "notes": notes, "root": root, "parts": [],
                 "attachments": {}, "page": page_files}
        for i, (obj, role, flags) in enumerate(parts):
            counts[role] = counts.get(role, 0) + 1
            pname = "%s_%s" % (name, role) + ("" if counts[role] == 1 else "_%d" % counts[role])
            obj.name = pname
            obj.data.name = pname
            obj.data.materials.clear()
            obj.data.materials.append(flags.get("material", mat))
            obj.parent = root
            if not obj.data.uv_layers:
                raise ValueError(pname + " has no UVs")
            L.triangulate(obj)
            obj.data.validate(clean_customdata=False)
            tris = L.tri_count(obj)
            if tris > 20000:
                raise ValueError("%s has %d triangles" % (pname, tris))
            collide = bool(flags.get("collide", False))
            sa = {"colorMap": REL + page_files["color"], "normalMap": REL + page_files["normal"],
                  "roughnessMap": REL + page_files["rough"], "metalnessMap": None,
                  "alphaMode": "Overlay", "color": [255, 255, 255]}
            entry["parts"].append({
                "name": pname, "role": role, "robloxMaterial": ROBLOX_MATERIAL.get(role, "SmoothPlastic"),
                "rgb": list(part_rgb[i]) if part_rgb else [128, 128, 128], "collide": collide,
                "collision": flags.get("collision", "Box") if collide else "Box",
                "castShadow": bool(flags.get("castShadow", True)), "canQuery": collide, "canTouch": collide,
                "tags": list(flags.get("tags", [])), "tris": tris, "surfaceAppearance": sa,
                "transparency": flags.get("transparency", 0), "doubleSided": False, "backFacesInMesh": False,
                "renderFidelity": "Automatic"})
        for an, (pos, look, up) in (attach or {}).items():
            entry["attachments"][an] = {"position": to_roblox(pos), "look": to_roblox(norm(look)),
                                        "up": to_roblox(norm(up))}
        if extra:
            entry.update(extra)
        self.assets.append(entry)
        return entry

    def finish(self, e):
        objs = [c for c in e["root"].children if c.type == "MESH"]
        bpy.context.view_layer.update()
        lo = np.array([1e9] * 3)
        hi = np.array([-1e9] * 3)
        for o in objs:
            co = L.numpy_verts(o)
            mw = np.array(o.matrix_world)
            w = co @ mw[:3, :3].T + mw[:3, 3]
            lo = np.minimum(lo, w.min(0))
            hi = np.maximum(hi, w.max(0))
        a, b = to_roblox(lo), to_roblox(hi)
        e["boundsMin"] = [min(x, y) for x, y in zip(a, b)]
        e["boundsMax"] = [max(x, y) for x, y in zip(a, b)]
        e["size"] = [round(hi[0] - lo[0], 3), round(hi[2] - lo[2], 3), round(hi[1] - lo[1], 3)]
        e["tris"] = sum(p["tris"] for p in e["parts"])
        if lo[2] < -1.5:
            self.warnings.append("%s reaches %.2f below the pivot" % (e["name"], lo[2]))
        if lo[2] < -0.05:
            e["buriedDepth"] = round(-float(lo[2]), 3)


def to_roblox(v):
    return [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)]


def norm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def bake_organic(lib, name, kind, build):
    """Unique page for an organic asset: UV page -> data bakes -> painter -> PNGs -> parts."""
    t0 = time.time()
    a = build()
    parts = a["parts"]
    objs = [p[0] for p in parts]
    for o in objs:
        o.data.validate(clean_customdata=False)
    L.unwrap_page(objs, angle=72.0, margin=0.003)
    dens = L.texel_density(objs, RES)
    lo, hi = L.bounds(objs)
    baker = L.Baker([(p[0], p[2]) for p in parts], RES, lo, hi)
    data = baker.run(*a["ao"])
    baker.cleanup()
    srgb, rough = a["paint"](data)
    cov = data["cover"]
    col = np.zeros((RES, RES, 3))
    col[cov] = srgb
    rg = np.full((RES, RES), 0.85)
    rg[cov] = rough
    page = "%s_%s" % (PREFIX, name)
    files = write_page(page, col, data["tnrm"], rg, cov)
    mat = export_material(page, os.path.join(TEX, files["color"]), os.path.join(TEX, files["normal"]),
                          os.path.join(GLB_ONLY, files["mr"]))
    pid = data["pid"][cov]
    part_rgb = []
    for i in range(len(parts)):
        m = pid == i
        part_rgb.append(L.stats_srgb(srgb[m]) if m.any() else (128, 128, 128))
    e = lib.add_asset("%s_%s" % (PREFIX, name), kind, [(p[0], p[1], p[3]) for p in parts], files, mat,
                      a.get("attach"), a.get("notes", ""), part_rgb=part_rgb,
                      extra={"pxPerStud": round(dens, 1), **({"perchWidths": a["perchWidths"]}
                                                             if "perchWidths" in a else {})})
    lib.finish(e)
    park(lib, e)
    log("ASSET %-16s %6d tris  %5.1f px/stud  page %s  (%.0fs)" % (e["name"], e["tris"], dens, page,
                                                                    time.time() - t0))
    return e


def park(lib, e):
    """Every asset is built at the origin: move a finished one far away so the next asset's AO bakes never see
    it (the export lays the row out again)."""
    e["root"].location = (2000.0 + 400.0 * len(lib.assets), 0.0, 0.0)
    bpy.context.view_layer.update()


def build_assets():
    import style_c_nature as SN
    lib = Lib()
    if "Spruce" in ONLY:
        bake_organic(lib, "Spruce", "Tree", SN.build_spruce)
    if "Oak" in ONLY:
        bake_organic(lib, "Oak", "Tree", SN.build_oak)
    if "Cabin" in ONLY:
        import style_c_cabin as SC
        SC.build_cabin(lib, sys.modules[__name__])
    if "Boulder" in ONLY:
        bake_organic(lib, "Boulder", "Rock", SN.build_boulder)
    return lib


# =============================================================================================== GLB + manifest
def export_glb(lib, terrain, gap=10.0):
    import gr_export as GX            # read-only reuse: GLB JSON check + metallicFactor patch
    x = 0.0
    for e in lib.assets:
        offset = x - e["boundsMin"][0]
        e["root"].location = (offset, 0, 0)
        e["origin"] = [round(offset, 4), 0.0, 0.0]
        x += e["size"][0] + gap
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for e in lib.assets:
        e["root"].select_set(True)
        for c in e["root"].children_recursive:
            c.select_set(True)
    glb = os.path.join(OUT, GLB_NAME + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                              export_image_format="AUTO", export_materials="EXPORT", export_normals=True,
                              export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
                              export_attributes=False)
    GX.glb_set_metallic_zero(glb)
    check, problems = GX.glb_check(glb)
    mats, imgs = GX.glb_materials(glb)
    double = [m.get("name") for m in mats if m.get("doubleSided")]
    if double:
        problems.append("doubleSided materials %s" % double)
    nbytes = os.path.getsize(glb)
    if nbytes > 19_000_000:
        problems.append("GLB is %.2f MB" % (nbytes / 1e6))
    lib.warnings += problems
    uploads = {}
    for e in lib.assets:
        for p in e["parts"]:
            for key, kind in (("colorMap", "color"), ("normalMap", "normal"), ("roughnessMap", "roughness")):
                rel = p["surfaceAppearance"][key]
                d = uploads.setdefault(rel, {"file": rel, "kind": kind, "usedBy": []})
                if e["name"] not in d["usedBy"]:
                    d["usedBy"].append(e["name"])
    for t in terrain:
        for key, kind in (("colorMap", "color"), ("normalMap", "normal"), ("roughnessMap", "roughness")):
            uploads.setdefault(t[key], {"file": t[key], "kind": kind, "usedBy": [t["name"]]})
    for rel, d in uploads.items():
        path = os.path.join(EXPORTS, *rel.split("/"))
        if os.path.exists(path):
            with open(path, "rb") as f:
                head = f.read(33)
            import struct
            w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
            d.update({"size": [w, h], "bitDepth": bd, "channels": {0: "gray", 2: "RGB", 6: "RGBA"}.get(ct, ct),
                      "bytes": os.path.getsize(path)})
        else:
            d["missing"] = True
            lib.warnings.append("missing texture " + rel)
    manifest = {
        "schema": "LS-StyleTest-1",
        "variant": VARIANT,
        "style": STYLE_NAME,
        "category": GLB_NAME,
        "glb": GLB_NAME + ".glb",
        "glbs": [{"file": GLB_NAME + ".glb", "bytes": nbytes, "sizeMB": round(nbytes / 1e6, 2),
                  "assets": [e["name"] for e in lib.assets], "embeddedImages": sorted(i.get("name", "") for i in imgs),
                  "doubleSided": double}],
        "units": "1 Blender unit = 1 Roblox stud",
        "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
        "folder": "StyleTest/%s" % VARIANT,
        "pathsRelativeTo": "BlenderExports",
        "textureFolder": REL.rstrip("/"),
        "uploadTextures": sorted(uploads.values(), key=lambda d: d["file"]),
        "glbOnlyTextures": sorted(REL + "glb_only/" + f for f in os.listdir(GLB_ONLY) if f.endswith(".png")),
        "terrainMaterials": terrain,
        "styleRules": STYLE_RULES,
        "import": [
            "Import StyleTest_C.glb (3D Importer / Open Cloud). Each asset root arrives as a Model of MeshParts named "
            "<Asset>_<Role>[_n]; re-centre with the asset 'origin' (WorldPivot = CFrame.new(origin), then PivotTo). "
            "The importer turns every import 180 degrees about Y (measured on all earlier sets) - undo it.",
            "Give every part ONE SurfaceAppearance from its surfaceAppearance block (ColorMap / NormalMap / "
            "RoughnessMap = uploaded ids of those PNGs, MetalnessMap empty, AlphaMode Overlay, Color white). All parts "
            "of one asset share the same three images, so copies instance. Normal maps are OpenGL (+Y) tangent space. "
            "Clear any importer TextureID; replace importer-made SurfaceAppearances (their roughness is half size).",
            "Per part: CanCollide = collide, CollisionFidelity = collision (edit time, via CreateMeshPartAsync), "
            "CastShadow, CanQuery, CanTouch, Anchored = true, Material = robloxMaterial (physics / footsteps), "
            "Color = rgb (fallback), Transparency = transparency (cabin glass 0.35).",
            "Attachments: StyleC_Oak Perch1-4 (level tops of standable limbs); StyleC_Cabin Door (threshold, facing "
            "out) and Hearth. Tag StyleC_Oak_Bark with CollectionService 'Climbable'.",
            "Terrain: make one MaterialVariant per terrainMaterials entry under MaterialService (ColorMap / NormalMap "
            "/ RoughnessMap, StudsPerTile, MaterialPattern Organic, BaseMaterial as suggested) and apply it with "
            "MaterialService:SetBaseMaterialOverride or paint it into an Expanded Terrain slot.",
        ],
        "assets": [],
        "warnings": lib.warnings,
        "glbCheck": dict(check, problems=problems,
                         tangentsOnEveryPrimitive=not any("TANGENT" in p for p in problems)),
    }
    for e in lib.assets:
        manifest["assets"].append({k: v for k, v in e.items() if k not in ("root", "page")})
    mpath = os.path.join(OUT, GLB_NAME + ".manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    if os.path.isdir(REPO_MANIFESTS):
        shutil.copyfile(mpath, os.path.join(REPO_MANIFESTS, os.path.basename(mpath)))
    log("EXPORTED %s (%.2f MB), %d assets, %d images, %d warnings" % (glb, nbytes / 1e6, len(lib.assets),
                                                                    len(imgs), len(lib.warnings)))
    log("GLBCHECK %d meshes, tangents on every primitive: %s" % (check.get("meshes", 0),
                                                                manifest["glbCheck"]["tangentsOnEveryPrimitive"]))
    for w in lib.warnings:
        log("WARNING " + w)
    log("MANIFEST " + mpath)
    return manifest


TERRAIN_JSON = os.path.join(OUT, GLB_NAME + ".terrain.json")     # kept out of the upload folder


def terrain_entries():
    path = TERRAIN_JSON
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return []


# =============================================================================================== main
def main():
    t0 = time.time()
    log("STYLE %s (%s) -> %s" % (VARIANT, STYLE_NAME, OUT))
    if "ground" in STAGES:
        import style_c_ground as SG
        bpy.ops.wm.read_factory_settings(use_empty=True)
        terr = SG.build_all(TEX, REL)
        with open(TERRAIN_JSON, "w", encoding="utf-8") as f:
            json.dump(terr, f, indent=1)
    if "assets" in STAGES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        lib = build_assets()
        export_glb(lib, terrain_entries())
    if "preview" in STAGES:
        import style_c_review as SR
        SR.run(OUT, PREV, GLB_NAME, OPTS)
    log("DONE in %.0fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
