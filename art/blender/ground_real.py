"""
ground_real.py - GroundReal: realistic, textured ground flora + rocks for LAST STANDING (Blender 5.3 headless).

    blender --background --factory-startup --python art/blender/ground_real.py -- <out_dir> <preview_dir> [stages] [assets]

stages (comma list, default "all" = atlas,rocktex,assets,preview):
  atlas     render the flora card atlases (GR_Plants_*, GR_Shrubs_*) from modelled plant geometry
  rocktex   build the tileable granite set + shared rock roughness (GR_Granite_*, GR_Rock_Rough)
  assets    build all 26 assets, bake the unique boulder pages, export GroundReal.glb + manifest
  preview   import the exported GLB + PNGs and render close/mid shots, vignettes and the lineup
assets: optional comma list of asset names for the preview stage.

Writes
  <out_dir>/GroundReal_Flora.glb, GroundReal_Rocks.glb, GroundReal_Cliffs.glb (textures embedded, each < 19 MB)
  <out_dir>/GroundReal.manifest.json (one manifest for the three GLBs; + copy in art/manifests/)
  <out_dir>/textures/GroundReal/*.png       every image the set uses (upload each once; all 1024 px or less)
  <out_dir>/textures/GroundReal/glb_only/   packed glTF metallicRoughness copies embedded in the GLBs (never upload)
  <preview_dir>/GroundReal/*.png            review renders
Build cache (layout JSON, EXR passes, npz) goes to %TEMP%/GroundReal_build; it is rebuilt by the atlas stage.
"""
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402

import tex_ground as tg  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0]) if len(ARGS) > 0 else os.path.join(os.path.expanduser("~"), "OneDrive", "Documents",
                                                                  "LastStanding", "BlenderExports")
PREV = os.path.abspath(ARGS[1]) if len(ARGS) > 1 else os.path.join(HERE, "..", "previews")
STAGES = set((ARGS[2] if len(ARGS) > 2 and ARGS[2] else "all").split(","))
if "all" in STAGES:
    STAGES = {"atlas", "rocktex", "assets", "preview"}
ONLY = set(ARGS[3].split(",")) if len(ARGS) > 3 and ARGS[3] else None
TEX = os.path.join(OUT, "textures", "GroundReal")
# the tree artist's TreesReal.glb (read-only) dresses the vignettes; default: the BlenderExports folder
TREES_DIR = os.environ.get("GR_TREES_DIR") or os.path.join(os.path.expanduser("~"), "OneDrive", "Documents",
                                                             "LastStanding", "BlenderExports")
CACHE = os.path.join(tempfile.gettempdir(), "GroundReal_build")
PREV_DIR = os.path.join(PREV, "GroundReal")
GLB_NAME = "GroundReal"
for d in (OUT, TEX, CACHE, PREV_DIR):
    os.makedirs(d, exist_ok=True)


def log(msg):
    print(msg, flush=True)


def load_layout():
    with open(os.path.join(CACHE, "GR_Atlas_Layout.json"), encoding="utf-8") as f:
        return json.load(f)


def texture_sets(layout):
    sets = {}
    for page in ("Plants", "Shrubs"):
        meta = layout[page]
        cols = [s["avg_srgb"] for s in meta["slots"].values() if s.get("coverage", 0) > 0.05]
        avg = [int(sum(c[i] for c in cols) / max(len(cols), 1)) for i in range(3)]
        sets[page] = {"color": meta["files"]["color"], "normal": meta["files"]["normal"],
                      "rough": meta["files"]["rough"], "alphaMode": "Transparency", "avg": avg,
                      "notes": "1024 card atlas, colour bled into transparent pixels; cut-out alpha"}
    rock_meta = os.path.join(CACHE, "GR_Rock_Sets.json")
    if os.path.exists(rock_meta):
        with open(rock_meta, encoding="utf-8") as f:
            sets.update(json.load(f))
    return sets


def stage_atlas():
    import gr_atlas
    tg.reset_scene()
    t = time.time()
    only = set(os.environ["GR_ATLAS_ONLY"].split(",")) if os.environ.get("GR_ATLAS_ONLY") else None
    meta = gr_atlas.build_atlases(TEX, CACHE, log, only=only)
    with open(os.path.join(CACHE, "GR_Atlas_Layout.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    log("ATLAS done in %.0fs" % (time.time() - t))


def stage_rocktex():
    import gr_rocks
    tg.reset_scene()
    gr_rocks.build_rock_textures(TEX, CACHE, log)


def stage_assets():
    import gr_export
    import gr_flora
    tg.reset_scene()
    layout = load_layout()
    L = {p: layout[p]["slots"] for p in ("Plants", "Shrubs")}
    have_rocks = os.path.exists(os.path.join(HERE, "gr_rocks.py"))
    if have_rocks:
        import gr_rocks
        gr_rocks.prepare_sets(TEX, CACHE, log)
    lib = gr_export.GroundLib("GroundReal", texture_sets(layout))
    lib.tex_dir = TEX              # materials embed the PNGs (and glb_only/*_MR.png) into the GLBs
    lib.notes += [
        "Flora: alpha cards with real flipped back faces (DoubleSided off, Transparency 0, AlphaMode Transparency); "
        "card bottoms are clamped to at most %.2f studs below y = 0 so blades emerge from the soil on slopes."
        % gr_export.PLANT_SINK,
        "Plants atlas: one-pixel alpha rim so thin blades survive the lower mips; colour is bled into every "
        "transparent pixel (no halos).",
        "All roughness maps are separate 8-bit grayscale PNGs for the SurfaceAppearances; the GLBs embed a packed "
        "glTF metallicRoughness copy (glb_only/*_MR.png, R = G = roughness, B = 0, metallicFactor 0); no metal.",
    ]
    t = time.time()
    gr_flora.build_all_flora(lib, L, log)
    log("FLORA built in %.0fs" % (time.time() - t))
    if have_rocks:
        t = time.time()
        gr_rocks.build_all_rocks(lib, L, TEX, CACHE, log)
        lib.sets.update(texture_sets(layout))
        log("ROCKS built in %.0fs" % (time.time() - t))
    extra = {"atlasLayout": {p: {"files": layout[p]["files"], "slots": {k: {"rect": v["rect"],
                                                                             "density": round(v["density"], 2)}
                                                                         for k, v in layout[p]["slots"].items()}}
                             for p in ("Plants", "Shrubs")}}
    lib.export(OUT, GLB_NAME, extra, log=log)
    import ad_finalize                      # art-direction schema + Roblox import checks (prints ADCHECK)
    ad_finalize.finalize(GLB_NAME, OUT, log=log)


def stage_preview():
    import gr_preview
    import gr_vignettes
    tg.reset_scene()
    with open(os.path.join(OUT, GLB_NAME + ".manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    scene = gr_preview.setup_scene()
    roots = {}
    for g in (manifest.get("glbs") or [{"file": GLB_NAME + ".glb"}]):
        roots.update(gr_preview.import_glb(os.path.join(OUT, g["file"]), manifest, TEX))
    gr_vignettes.run_all(scene, roots, manifest, PREV_DIR, ONLY, log, glb_dir=TREES_DIR)


if __name__ == "__main__":
    t0 = time.time()
    if "atlas" in STAGES:
        stage_atlas()
    if "rocktex" in STAGES and os.path.exists(os.path.join(HERE, "gr_rocks.py")):
        stage_rocktex()
    if "assets" in STAGES:
        stage_assets()
    if "preview" in STAGES:
        stage_preview()
    log("DONE in %.0fs" % (time.time() - t0))
