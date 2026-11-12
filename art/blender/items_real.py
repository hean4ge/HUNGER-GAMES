"""
items_real.py - LAST STANDING "ItemsReal" set: realistic, textured held items, supply crates and armour
(Blender 5.3 headless)  ->  ItemsReal.glb + ItemsReal.manifest.json + PNG textures + previews.

    blender --background --factory-startup --python items_real.py -- <out_dir> <preview_dir> [options]
    options:  sets=IR_Weapons,IR_Supplies   only (re)build these texture sets (the GLB then holds only them -
                                            always finish with a full run)
              reuse                          reuse the cached data bakes (geometry unchanged, materials tuned)
              assets=knife,sword             build only these builder functions (testing)
              renderonly [only=knife,bow]    re-render previews from the exported GLB + manifest
              renderonly lineuponly          only the _lineup.png + _contact.png sheets
              norender                       skip the preview renders

Replaces the v1 Items set (items.py) one-for-one: same asset names, Grip origins, attachments and gameplay
dimensions; crate lids keep <Crate>_Lid (+ the Lid-tagged <Crate>_LidMetal / _LidDarkMetal fittings);
bow_Rope is still the string; SupplyCrate3_Ember is still a separate Neon part.

Pipeline (tex_items.py): geometry tagged per piece -> one UV atlas per texture set -> Cycles data bake
(position, normal, grain frame, ids, AO, convexity, bevel normal) -> numpy materials (tex_items_mats.py) ->
Color / Normal / Roughness / Metalness PNGs (1024) -> GLB with embedded textures.

Texture sets (4 x 1024; 16 PNGs in textures/ItemsReal = Color, Normal, 8-bit grayscale Roughness and Metalness per
set - what the integrator uploads for hand-built SurfaceAppearances; the GLB embeds Color + Normal + a packed glTF
metallicRoughness per set). The GLB is exported WITH tangents (Roblox needs them for normal maps):
  IR_Weapons   knife, machete, hatchet, spear, mace, sword, bow, arrow, throwing_knife
  IR_Supplies  water_bottle, empty_bottle, berries, apple, dried_meat, ration, bandage, herbs, medkit
  IR_CratesA   SupplyCrate1, SupplyCrate2
  IR_CratesB   SupplyCrate3, leather_vest, padded_armor
"""
import json
import os
import shutil
import sys
import time

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import ls_common as ls  # noqa: E402
import tex_items as tx  # noqa: E402
import tex_items_mats as M  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(ARGV[0] if len(ARGV) > 0 else os.getcwd())
# absolute: Blender resolves relative render paths differently from Python's os functions
PREVIEW_DIR = os.path.abspath(ARGV[1] if len(ARGV) > 1 else os.path.join(OUT_DIR, "previews"))
OPTS = {}
for a in ARGV[2:]:
    k, _, v = a.partition("=")
    OPTS[k] = v or True
CATEGORY = "ItemsReal"
TEX_DIR = os.path.join(OUT_DIR, "textures", CATEGORY)
HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ART = os.path.normpath(os.path.join(HERE, ".."))
CACHE = os.environ.get("IR_CACHE") or os.path.join(os.environ.get("TEMP", OUT_DIR), "ls_items_real_cache")
RES = 1024

SETS = {
    "IR_Weapons": dict(ao=(0.05, 0.25, 0.03), alpha=False),
    "IR_Supplies": dict(ao=(0.05, 0.25, 0.03), alpha=True),
    "IR_CratesA": dict(ao=(0.12, 0.8, 0.06), alpha=False, ground=True),
    "IR_CratesB": dict(ao=(0.12, 0.8, 0.06), alpha=False, ground=True),
}
ONLY = set(OPTS["sets"].split(",")) if "sets" in OPTS else set(SETS)


class ItemsLib(tx.RealLibrary):
    """RealLibrary + piece joining, per-asset material parameters and bake poses (crate lids open)."""

    def __init__(self, category):
        super().__init__(category)
        self.mparams = {}
        self.bake_pose = {}
        self.extra = {}

    def part(self, root, pieces, role, texset, name=None, weight=1.0, smooth="keep", collide=False, collision="Box",
             cast_shadow=True, tags=None, alpha=None, transparency=0.0, rgb=None, weights_by_piece=False,
             sa_extra=None):
        obj = tx.join(pieces, (name or "%s_%s" % (root.name, role)) + "_tmp")
        return self.add(root, obj, role, texset, name=name, collide=collide, collision=collision,
                        cast_shadow=cast_shadow, tags=tags, smooth=smooth, alpha=alpha, weight=weight,
                        transparency=transparency, rgb=rgb, sa_extra=sa_extra)

    def params(self, root, mid, d):
        self.mparams.setdefault(root.name, {}).setdefault(mid, {}).update(d)

    def rename(self, root, obj, new_name):
        e = self._entry(root)
        for p in e["parts"]:
            if p["name"] == obj.name:
                p["name"] = new_name
        obj.name = new_name
        obj.data.name = new_name
        return obj


def build_all(lib):
    import importlib
    import ir_geo
    ir_geo.reseed(4207)
    want = {
        "IR_Weapons": ("ir_weapons", "BUILDERS"),
        "IR_Supplies": ("ir_supplies", "BUILDERS"),
        "IR_CratesA": ("ir_crates", "BUILDERS_A"),
        "IR_CratesB": ("ir_crates", "BUILDERS_B"),
    }
    only_assets = set(OPTS["assets"].split(",")) if "assets" in OPTS else None
    for sname in SETS:
        if sname not in ONLY:
            continue
        mod, attr = want[sname]
        for fn in getattr(importlib.import_module(mod), attr):
            if only_assets and fn.__name__ not in only_assets:
                continue
            fn(lib)


def set_asset_codes(lib, sname):
    """Encode the asset index into the 'mid' face attribute (mid + 100 * index within the set)."""
    names = []
    for e in lib.assets:
        objs = [o for p, o in zip(e["parts"], e["objs"]) if p["textureSet"] == sname]
        if not objs:
            continue
        aid = len(names)
        names.append(e["name"])
        for o in objs:
            at = o.data.attributes["mid"]
            v = np.empty(len(o.data.polygons), dtype=np.float32)
            at.data.foreach_get("value", v)
            v = np.mod(v, 100.0) + 100.0 * aid
            at.data.foreach_set("value", v)
            o.data.update()
    return names


def bake_set(lib, sname, cfg):
    trip = lib.parts_of_set(sname)
    if not trip:
        return None
    objs = [o for (_, _, o) in trip]
    names = set_asset_codes(lib, sname)
    weights = [p["_weight"] for (_, p, _) in trip]
    t0 = time.time()
    dens = tx.unwrap_pack(objs, weights, res=RES, margin_px=4)
    print("UV %s: %d parts packed in %.1fs" % (sname, len(objs), time.time() - t0))
    for (e, p, o) in trip:
        p["pxPerStud"] = round(dens[o.name], 1)
    # spread the assets apart so occlusion only comes from each asset's own parts
    saved = {}
    occluders = []
    for i, nm in enumerate(names):
        e = next(x for x in lib.assets if x["name"] == nm)
        saved[nm] = e["root"].location.copy()
        e["root"].location = (i * 60.0, 300.0, 0.0)
        pose = lib.bake_pose.get(nm)
        if pose:
            pose(True)
        if cfg.get("ground"):
            gp = ls.cube("_bake_ground_%d" % i, size=(14, 14, 0.02), loc=(i * 60.0, 300.0, -0.011))
            occluders.append(gp)
    bpy.context.view_layer.update()
    baker = tx.Baker(res=RES, cache_dir=os.path.join(CACHE, CATEGORY))
    data = baker.bake(sname, objs, ao_dist=cfg["ao"], force=not OPTS.get("reuse"))
    for gp in occluders:
        bpy.data.objects.remove(gp, do_unlink=True)
    for nm in names:
        e = next(x for x in lib.assets if x["name"] == nm)
        e["root"].location = saved[nm]
        pose = lib.bake_pose.get(nm)
        if pose:
            pose(False)
    bpy.context.view_layer.update()
    # material parameters keyed by (asset index, material id)
    params = {}
    for aid, nm in enumerate(names):
        for mid, d in lib.mparams.get(nm, {}).items():
            q = dict(d)
            if "nails" in q:
                q["nails_now"] = q.pop("nails")
            params[(aid, mid)] = q
    t0 = time.time()
    ch = M.synthesize(data, params, asset_names=names)
    print("SYNTH %s in %.1fs" % (sname, time.time() - t0))
    files = tx.finish_set(sname, data, ch, TEX_DIR, has_alpha=cfg["alpha"], orm_dir=os.path.join(CACHE, CATEGORY))
    albedo = files.pop("_albedo_srgb")
    lib.sets[sname] = {
        "images": {k: os.path.relpath(v, OUT_DIR).replace("\\", "/") for k, v in files.items() if k != "metallicRoughness"},
        "resolution": RES,
        "assets": names,
        "colorAlpha": "opacity (AlphaMode Transparency parts only; 1 elsewhere)" if cfg["alpha"] else None,
        "pxPerStud": {nm: round(float(np.median([dens[o.name] for (e, p, o) in trip if e["name"] == nm])), 1)
                      for nm in names},
        "_mean_rgb": {o.name: tx.mean_rgb_by_uv(o, albedo) for (e, p, o) in trip},
    }
    lib.extra[sname] = files
    return files


def export(lib):
    mats = {}
    for sname, files in lib.extra.items():
        mats[(sname, None)] = tx.export_material(sname, files["color"], files["normal"], files["metallicRoughness"])
        if SETS[sname]["alpha"]:
            mats[(sname, "Transparency")] = tx.export_material(sname + "_Transparent", files["color"], files["normal"],
                                                               files["metallicRoughness"], alpha=True)
    mats[(None, None)] = tx.flat_material("IR_Ember", (236, 112, 44), emission=4.0)
    manifest = lib.export(OUT_DIR, mats)
    glb = os.path.join(OUT_DIR, CATEGORY + ".glb")
    rep = tx.verify_glb(glb)
    print("VERIFY GLB: %d meshes / %d primitives; missing TANGENT %d, NORMAL %d, TEXCOORD_0 %d; %d embedded images"
          % (rep["meshes"], rep["primitives"], len(rep["missingTangent"]), len(rep["missingNormal"]),
             len(rep["missingUV"]), len(rep["images"])))
    for mname, m in sorted(rep["materials"].items()):
        print("VERIFY MAT %-24s base %s normal %s MR %s alpha %s" % (mname, m["baseColorTexture"], m["normalTexture"],
                                                                   m["metallicRoughnessTexture"], m["alphaMode"]))
    if rep["missingTangent"] or rep["missingUV"]:
        lib.warnings.append("GLB primitives without TANGENT/UV: %s" % (rep["missingTangent"] + rep["missingUV"]))
    manifest["glbCheck"] = {"tangents": not rep["missingTangent"], "primitives": rep["primitives"],
                            "embeddedImages": rep["images"]}
    add_inventory(manifest)
    mpath = os.path.join(OUT_DIR, CATEGORY + ".manifest.json")
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    os.makedirs(os.path.join(REPO_ART, "manifests"), exist_ok=True)
    shutil.copyfile(mpath, os.path.join(REPO_ART, "manifests", CATEGORY + ".manifest.json"))
    print("MANIFEST COPIED to " + os.path.join(REPO_ART, "manifests"))
    import ad_finalize                      # art-direction schema + Roblox import checks (prints ADCHECK)
    manifest = ad_finalize.finalize(CATEGORY, OUT_DIR)
    return manifest


IMPORT_NOTES = [
    "Swap-in for the v1 Items set: every asset keeps its v1 name, origin (Grip at the hand grip, crates on the floor "
    "centre), gameplay size and attachments (Grip, Tip, Nock, StringTop, StringBottom, ArrowRest, Mouth, Torso, "
    "LidHinge, Prompt, LootPoint) at the v1 positions, so ItemAssets.build() can switch manifests without code "
    "changes. Part lists are leaner (one MeshPart per surface group); the names the game relies on are kept: "
    "<Crate>_Lid (+ Lid-tagged fittings), SupplyCrate3_Ember, bow_Rope (the string), water_bottle_Glass / "
    "water_bottle_WaterFill / empty_bottle_Glass.",
    "Geometry: import ItemsReal.glb (3D Importer / Open Cloud Model). Each asset root arrives as a Model of MeshParts "
    "named as in the manifest; re-centre with the asset 'origin' exactly like the v1 Items (WorldPivot = "
    "CFrame.new(origin), then PivotTo).",
    "Surfaces: give every textured part ONE SurfaceAppearance from its 'surfaceAppearance' block: ColorMap / "
    "NormalMap / RoughnessMap / MetalnessMap = the uploaded ids of those PNGs in textures/ItemsReal (16 images for "
    "the whole set, each uploaded once and shared), AlphaMode as given, Color = 'color'. Do not rely on the importer's "
    "auto SurfaceAppearance for roughness/metalness: the GLB packs them into one glTF metallicRoughness image "
    "(glbOnlyTextures) which Roblox does not split. Clear any importer-created TextureID.",
    "Glass and water (water_bottle_Glass, water_bottle_WaterFill, empty_bottle_Glass): AlphaMode = Transparency and "
    "MeshPart.Transparency = 0.02 (>= 0.02 makes the colour-map alpha blend smoothly; the alpha channel already "
    "carries the glass opacity: ~0.2 in thin walls, more at the base, shoulder and smudges). Every other part is "
    "opaque (AlphaMode Overlay with a fully opaque colour map; Transparency 0). No part relies on DoubleSided; "
    "keep MeshPart.DoubleSided = false.",
    "SupplyCrate3_Ember is untextured: Material Neon, Color = rgb (236,112,44), or a plain part with "
    "EmissiveStrength; optionally a small orange PointLight (Range ~6, Brightness ~0.5) at LootPoint.",
    "Per part: CanCollide = collide, CollisionFidelity = collision, CastShadow = castShadow, CanQuery = canQuery, "
    "CanTouch = canTouch; Material = robloxMaterial (physics/sounds only, the look comes from the "
    "SurfaceAppearance); 'rgb' = mean texture colour (fallback MeshPart.Color). Viewmodel / held copies: set "
    "CastShadow = false on every part (LookDevPlaybook 7.3); world loot copies use castShadow as listed.",
    "Texel density (median px per stud, per asset) is in textureSets.<set>.pxPerStud; held items 170-260, crates "
    "and armour lower (large surfaces seen at arm's length).",
]


def add_inventory(manifest):
    """Top-level texture inventory + import notes (same shape as the TreesReal manifest)."""
    textures = {}
    used = {}
    for sname, s in manifest["textureSets"].items():
        for kind, rel in s["images"].items():
            used.setdefault(rel, set()).update(s["assets"])
            path = os.path.join(OUT_DIR, rel)
            textures[os.path.basename(rel)] = {
                "kind": kind, "set": sname, "bytes": os.path.getsize(path) if os.path.exists(path) else None,
                "alpha": bool(kind == "color" and s.get("colorAlpha")), "grayscale": kind in ("roughness", "metalness"),
                "resolution": [RES, RES], "usedBy": sorted(s["assets"])}
    manifest["textureFolder"] = "textures/" + CATEGORY
    manifest["textures"] = textures
    manifest["imageCount"] = len(textures)
    manifest["glbOnlyTextures"] = {
        "%s_ORM.png" % sname: {"kind": "glTF metallicRoughness (R = baked AO, G = roughness, B = metalness)",
                               "note": "embedded in the GLB only - never upload it separately"}
        for sname in manifest["textureSets"]}
    manifest["import"] = IMPORT_NOTES


def render_only():
    import ir_render
    with open(os.path.join(OUT_DIR, CATEGORY + ".manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    if not OPTS.get("lineuponly"):
        ir_render.render_items(os.path.join(OUT_DIR, CATEGORY + ".glb"), manifest, os.path.join(PREVIEW_DIR, CATEGORY),
                               only=OPTS.get("only"))
    render_sheets(manifest)


def render_sheets(manifest):
    """Lineup (all assets at eye level with the 5.5-stud figure) + contact sheet of the per-asset previews."""
    import ir_render
    folder = os.path.join(PREVIEW_DIR, CATEGORY)
    if OPTS.get("only") or ("sets" in OPTS and len(ONLY) < len(SETS)):
        return
    ir_render.render_lineup(os.path.join(OUT_DIR, CATEGORY + ".glb"), manifest, folder)
    ir_render.contact_sheet(folder, [a["name"] for a in manifest["assets"]])


def main():
    if OPTS.get("renderonly"):
        render_only()
        return
    t_all = time.time()
    ls.reset()
    lib = ItemsLib(CATEGORY)
    build_all(lib)
    for e in lib.assets:
        for p, o in zip(e["parts"], e["objs"]):
            bad = tx.nonmanifold_edges(o)
            if bad:
                print("NOTE nonmanifold %s: %d edges" % (o.name, bad))
    for sname, cfg in SETS.items():
        if sname in ONLY:
            bake_set(lib, sname, cfg)
    manifest = export(lib)
    total = sum(a["tris"] for a in manifest["assets"])
    print("TOTAL TRIS %d over %d assets; %.0fs" % (total, len(manifest["assets"]), time.time() - t_all))
    for n in lib.notes:
        print("NOTE " + n)
    if not OPTS.get("norender"):
        import ir_render
        ir_render.render_items(os.path.join(OUT_DIR, CATEGORY + ".glb"), manifest, os.path.join(PREVIEW_DIR, CATEGORY),
                               only=OPTS.get("only"))
        render_sheets(manifest)


main()
