"""
buildings_real.py - LAST STANDING "BuildingsReal" set (realistic, textured), Blender 5.3 headless.

Writes, into <out_dir>:
  BuildingsReal.glb + BuildingsReal.manifest.json   HunterCabin, Watchtower, Footbridge
  PropsReal.glb     + PropsReal.manifest.json       Tent, Campfire, Woodpile, Barrel, Lantern, CratePile,
                                                    FenceSegment, Sign, Bedroll, LogBench
  textures/BuildingsReal/BR_*.png                   the 16-image texture set both GLBs embed
and review renders into <preview_dir>/BuildingsReal/.

    blender --background --factory-startup --python buildings_real.py -- <out_dir> <preview_dir> [only] [flags]

[only]  comma list of asset names (iteration; it overwrites the GLBs with that subset - finish with a full run)
flags   notex     reuse the existing PNG set instead of re-synthesising it (~40 s)
        norender  skip the review renders          fast   low-sample renders
        noexport  skip the GLB / manifest export
Asset code: br_cabin, br_tower, br_bridge, br_props. Helpers: br_kit (UV-mapped primitives, materials, export),
tex_buildings (texture sheets), br_preview (Cycles review renders).
"""
import importlib
import os
import sys
import time

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls  # noqa: E402
import ls_patch  # noqa: F401,E402
import tex_buildings as tb  # noqa: E402
import br_kit as K  # noqa: E402
import br_preview as P  # noqa: E402

out_dir, preview_dir = ls.args()
out_dir, preview_dir = os.path.abspath(out_dir), os.path.abspath(preview_dir)
_rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = None
FLAGS = set()
for a in _rest[2:]:
    if a in ("notex", "norender", "fast", "noexport", "nolineup"):
        FLAGS.add(a)
    elif a and a != "all":
        ONLY = set(x for x in a.split(",") if x)

TEX_DIR = os.path.join(out_dir, "textures", K.SET_NAME)
PREV_DIR = os.path.join(preview_dir, K.SET_NAME)

BUILDINGS = [
    ("HunterCabin", "br_cabin", "build"),
    ("Watchtower", "br_tower", "build"),
    ("Footbridge", "br_bridge", "build"),
]
PROPS = [
    ("Tent", "br_props", "build_tent"),
    ("Campfire", "br_props", "build_campfire"),
    ("Woodpile", "br_props", "build_woodpile"),
    ("Barrel", "br_props", "build_barrel"),
    ("Lantern", "br_props", "build_lantern"),
    ("CratePile", "br_props", "build_cratepile"),
    ("FenceSegment", "br_props", "build_fence"),
    ("Sign", "br_props", "build_sign"),
    ("Bedroll", "br_props", "build_bedroll"),
    ("LogBench", "br_props", "build_logbench"),
]


def run(category, entries, seed, kind):
    todo = [e for e in entries if ONLY is None or e[0] in ONLY]
    if not todo:
        return None
    ls.reset()
    K._MATS.clear()
    K._IMGS.clear()
    ls.seed(seed)
    lib = ls.Library(category)
    for (name, mod, fn) in todo:
        t0 = time.time()
        getattr(importlib.import_module(mod), fn)(lib)
        print("BUILT %s (%.1fs)" % (name, time.time() - t0))
    for e in lib.assets:
        print("TRIS %-14s %6d  parts %2d  size %s" % (e["name"], e["tris"], len(e["parts"]), e["size"]))
        for p in e["parts"]:
            print("   part %-30s %5d  %-5s %-27s %s" % (p["name"], p["tris"], p["collide"], p["collision"],
                                                     p.get("surface", {}).get("sheet", "-")))
        for k, a in e["attachments"].items():
            print("   att  %-14s pos %s look %s" % (k, a["position"], a["look"]))
    if "noexport" not in FLAGS:
        K.export(lib, out_dir)
    if "norender" not in FLAGS:
        samples = 24 if "fast" in FLAGS else 96
        dev = P.setup(samples=samples)
        print("RENDER device", dev)
        roots = [e["root"] for e in lib.assets]
        for e in lib.assets:
            mod = importlib.import_module([m for (n, m, f) in entries if n == e["name"]][0])
            extra = getattr(mod, "review_views", lambda name: [])(e["name"])
            t0 = time.time()
            if hasattr(mod, "preview_setup"):
                mod.preview_setup(P)
            for p in P.views_for(e["root"], kind, PREV_DIR, e["name"], extra, samples):
                print("PREVIEW " + p)
            if hasattr(mod, "preview_teardown"):
                mod.preview_teardown(P)
            print("RENDERED %s (%.1fs)" % (e["name"], time.time() - t0))
        if len(roots) > 1 and "nolineup" not in FLAGS:
            path = os.path.join(PREV_DIR, "_lineup_%s.png" % ("buildings" if kind == "building" else "props"))
            rows = None
            if kind == "prop":   # low props in front, tall ones behind
                by = {e["name"]: e["root"] for e in lib.assets}
                rows = [[by[n] for n in ("Barrel", "LogBench", "Campfire", "Bedroll", "Lantern") if n in by],
                        [by[n] for n in ("Tent", "Woodpile", "CratePile", "FenceSegment", "Sign") if n in by]]
            print("PREVIEW " + P.lineup(roots, path, samples=samples, gap=6.0 if kind == "building" else 2.5,
                                        rows=rows))
    return lib


t_start = time.time()
if "notex" not in FLAGS or not os.path.exists(os.path.join(TEX_DIR, tb.PREFIX + "layout.json")):
    tb.build_all(TEX_DIR)
K.load_stats(TEX_DIR)
run("BuildingsReal", BUILDINGS, 6150, "building")
run("PropsReal", PROPS, 6151, "prop")
if "noexport" not in FLAGS:
    import ad_finalize                      # art-direction schema + Roblox import checks (prints ADCHECK)
    ad_finalize.finalize("PropsReal", out_dir)
    ad_finalize.finalize("BuildingsReal", out_dir)
print("DONE in %.1fs" % (time.time() - t_start))
