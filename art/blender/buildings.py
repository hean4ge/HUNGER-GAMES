"""
buildings.py - LAST STANDING "Buildings" category generator (Blender 5.3, headless).
Writes Buildings.glb + Buildings.manifest.json (structures) and Props.glb + Props.manifest.json (small props).

    blender --background --factory-startup --python buildings.py -- <out_dir> <preview_dir> [only]

[only] (optional, for iteration) = comma list of asset names to build; omit it for the real export.
Asset code lives in bld_cabin / bld_tower / bld_mill / bld_water / bld_props, helpers in bld_kit.
"""
import importlib
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls  # noqa: E402
import ls_patch  # noqa: F401,E402  (art-direction fixes on top of ls_common: hard edges, bounds, query flags)

out_dir, preview_dir = ls.args()
ls.reset()
ls.seed(5150)

_rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(a for a in _rest[2].split(",") if a) if len(_rest) > 2 else None

BUILDINGS = [
    ("RangerCabin", "bld_cabin", "build"),
    ("Watchtower", "bld_tower", "build"),
    ("RiverMill", "bld_mill", "build_mill"),
    ("WaterWheel", "bld_mill", "build_wheel"),
    ("Bridge", "bld_water", "build_bridge"),
    ("FishingShack", "bld_water", "build_shack"),
    ("Jetty", "bld_water", "build_jetty"),
    ("StiltHut", "bld_swamp", "build_stilthut"),
    ("WalkwaySegment", "bld_swamp", "build_walkway"),
]
PROPS = [
    ("Tent", "bld_props", "build_tent"),
    ("Campfire", "bld_props", "build_campfire"),
    ("FenceSegment", "bld_props", "build_fence"),
    ("CratePile", "bld_props", "build_cratepile"),
    ("Barrel", "bld_props", "build_barrel"),
    ("Lantern", "bld_props", "build_lantern"),
    ("Well", "bld_props", "build_well"),
    ("Woodpile", "bld_props", "build_woodpile"),
    ("Sign", "bld_props", "build_sign"),
]


def run(category, entries, seed):
    ls.reset()
    ls.seed(seed)
    lib = ls.Library(category)
    for (name, mod, fn) in entries:
        if ONLY is not None and name not in ONLY:
            continue
        getattr(importlib.import_module(mod), fn)(lib)
        print("BUILT %s" % name)
    if not lib.assets:
        return None
    for e in lib.assets:
        print("TRIS %-16s %6d  parts %2d  size %s" % (e["name"], e["tris"], len(e["parts"]), e["size"]))
        if ONLY is not None:
            for p in e["parts"]:
                print("   part %-28s %5d  %s/%s" % (p["name"], p["tris"], p["collide"], p["collision"]))
    if ONLY is not None:
        review(lib)
    return lib.export(out_dir, preview_dir)


def review(lib):
    """Iteration-only extra renders: low front, side, high three-quarter and a roof-off top view."""
    folder = os.path.join(preview_dir, lib.category, "review")
    os.makedirs(folder, exist_ok=True)
    roof_roles = ("Shingles", "RoofTiles", "Thatch", "Rust")
    for e in lib.assets:
        root = e["root"]
        n = e["name"]
        lib.render_preview([root], os.path.join(folder, n + "_low.png"), 6, 0, 1.05)
        lib.render_preview([root], os.path.join(folder, n + "_side.png"), 12, 90, 1.05)
        lib.render_preview([root], os.path.join(folder, n + "_high.png"), 50, 140, 1.05)
        hidden = [c for c in root.children if any(c.name.startswith(n + "_" + r) for r in roof_roles)]
        if hidden:
            for c in hidden:
                c.parent = None
            lib.render_preview([root], os.path.join(folder, n + "_open.png"), 62, 20, 1.0)
            for c in hidden:
                c.parent = root


run("Buildings", BUILDINGS, 5150)
run("Props", PROPS, 5151)
