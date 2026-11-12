"""
items.py - LAST STANDING "Items" category generator (Blender 5.3, headless).
Weapons, ammo, consumables, armor and supply crates -> Items.glb + Items.manifest.json + previews.

    blender --background --factory-startup --python items.py -- <out_dir> <preview_dir>

Modules (same folder): items_kit (helpers), items_melee, items_ranged, items_consumables, items_armor, items_crates.
Held items: hand grip at the origin, item points up +Z, edge/front faces +Y (see each module's header).
"""
import os, sys
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import ls_common as ls
import ls_patch  # noqa: F401  (art-direction fixes on top of ls_common: hard edges, bounds, query flags)
out_dir, preview_dir = ls.args(); ls.reset(); ls.seed(4207)

import shutil

import items_kit as kit
import items_armor
import items_consumables
import items_crates
import items_melee
import items_ranged

ORDER = ["knife", "machete", "hatchet", "spear", "mace", "sword", "bow", "arrow", "throwing_knife",
         "water_bottle", "empty_bottle", "berries", "apple", "dried_meat", "ration", "bandage", "herbs", "medkit",
         "leather_vest", "padded_armor", "crate1", "crate2", "crate3"]

builders = {}
for module in (items_melee, items_ranged, items_consumables, items_armor, items_crates):
    for fn in module.BUILDERS:
        builders[fn.__name__] = fn

lib = kit.ItemLibrary("Items")
for name in ORDER:
    builders[name](lib)

# Mesh hygiene: every part should be closed and manifold (each edge shared by exactly two faces).
import bmesh
for e in lib.assets:
    for part_obj in e["root"].children:
        bm = bmesh.new()
        bm.from_mesh(part_obj.data)
        bad = sum(1 for ed in bm.edges if len(ed.link_faces) != 2)
        bm.free()
        if bad:
            print("NONMANIFOLD %s: %d edges" % (part_obj.name, bad))

# Extra review renders: side view (blade profiles face +/-X) for every asset.
side_dir = os.path.join(preview_dir, lib.category)
os.makedirs(side_dir, exist_ok=True)
for e in lib.assets:
    lib.render_preview([e["root"]], os.path.join(side_dir, e["name"] + "_side.png"), 12, 90)

manifest = lib.export(out_dir, preview_dir)

repo_manifests = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "manifests")
os.makedirs(repo_manifests, exist_ok=True)
shutil.copyfile(os.path.join(out_dir, lib.category + ".manifest.json"),
                os.path.join(repo_manifests, lib.category + ".manifest.json"))
print("MANIFEST COPIED to " + repo_manifests)
print("NOTES %d (held items extending below z = 0 by design)" % len(lib.notes))
print("TOTAL TRIS %d over %d assets" % (sum(e["tris"] for e in manifest["assets"]), len(manifest["assets"])))
