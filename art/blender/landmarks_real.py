"""
landmarks_real.py - LAST STANDING "LandmarksReal" set: realistic, textured rebuild of the arena landmarks and the
lobby kit (Blender 5.3, headless). Replaces the flat-coloured v1 look of landmarks.py; same names, gameplay
dimensions, attachments and collision intent.

Assets: Spire, SpirePlatform, Plinth, Pavilion, LobbyGate, Brazier, BannerPole, Bench, NoticeBoard, Railing,
StoneSteps.

Pipeline (all procedural, seeded):
  tex_landmarks.py  5 PBR materials -> 15 PNGs (1024^2): LR_Granite, LR_StoneTrim, LR_Wood, LR_Iron, LR_Misc
  lr_core.py        UV rules onto the tile/trim sheets, PBR materials, groups -> parts, manifest + GLB export
  lr_parts.py, lr_masonry.py   bevelled granite blocks, flagstones, timber, forged iron, rivets, colliders
  lr_spire.py, lr_plaza.py, lr_lobby.py   the assets
  lr_review.py      Cycles review renders under the built-in Sky Texture with a 5.5-stud figure

Run (from the repo root):
  blender --background --factory-startup --python art/blender/landmarks_real.py -- <out_dir> <preview_dir>
      [assets=Spire,Plinth,...] [tex=build|reuse] [review=all|none|<asset list>]
Writes <out_dir>/LandmarksReal.glb + .manifest.json, PNGs to <out_dir>/textures/LandmarksReal/, a copy of the
manifest to art/manifests/, review renders and a lineup sheet to <preview_dir>/LandmarksReal/.
"""
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import lr_core as C  # noqa: E402
import tex_landmarks as T  # noqa: E402

SET = "LandmarksReal"
ORDER = ["Spire", "SpirePlatform", "Plinth", "Pavilion", "LobbyGate", "Brazier", "BannerPole", "Bench",
         "NoticeBoard", "Railing", "StoneSteps"]


IMPORT_NOTES = [
    "Geometry: import LandmarksReal.glb (3D Importer or Open Cloud Model). Each asset root arrives as a Model of "
    "MeshParts named <Asset>_<Role>[_n]. Re-centre with the asset 'origin' (Model.WorldPivot = CFrame.new(origin), "
    "then PivotTo(CFrame.new())) as for every other category; boundsMin/boundsMax are relative to that pivot.",
    "Surfaces: every textured part has ONE SurfaceAppearance built from its 'surfaceAppearance' block: ColorMap, "
    "NormalMap (OpenGL +Y, MikkTSpace tangents are in the GLB), RoughnessMap (8-bit grayscale) and, for LR_Iron parts "
    "only, MetalnessMap (8-bit grayscale). Upload each PNG of textures/LandmarksReal ONCE and share the ids: 5 colour + "
    "5 normal + 5 roughness + 1 metalness = 16 images. The *_MR.png files are the glTF metallicRoughness packing "
    "embedded in the GLB (256 px); never upload them. Clear any importer-created TextureID. alphaMode null = leave "
    "the default: no LandmarksReal image has an alpha channel. 'rgb' is the texture average (fallback Color).",
    "Roughness maps are Roblox-ready: authored roughness + 0.08 (LookDevPlaybook s.11, Roblox renders glossier than "
    "Blender). Roughness/metalness are 512 px (half the colour size, as the playbook recommends).",
    "Tiling: the stone, wood and iron sheets are trim/tile sheets; UVs run outside 0..1 along U (and both ways on the "
    "granite tile), so the samplers must repeat (glTF default REPEAT). Check one wall in Studio before mass placement.",
    "Collision: visual parts never collide (CanCollide/CanQuery/CanTouch false). Parts with role 'Collider' carry all "
    "collision and raycasts: Transparency 1, CastShadow false, CanCollide/CanQuery/CanTouch true, CollisionFidelity as "
    "listed (CollisionFidelity can only be set at edit time). They are simple convex pieces, so walkable steps and "
    "decks stay walkable and every doorway, alcove and launch-plate opening stays open. If Studio's decomposition "
    "ever fills an opening, split that Collider by its islands into separate parts.",
    "Ember parts (role Ember: Spire_Ember, Plinth_Ember, Brazier_Ember, Pavilion_Ember, LobbyGate_Ember): Material "
    "Neon, Color (255,128,48), no SurfaceAppearance, CastShadow false. Pair each with a real light: Beacon (Spire), "
    "Fire (Brazier) and Lantern (Pavilion, LobbyGate) attachments.",
    "Launch plates: SpirePlatform attachments Plate_1..Plate_24 (plaza surface at the 24 openings, LookVector toward "
    "the Spire): pivot one Plinth on each. Plinth origin = plaza surface (tread y = 1.5 above it, Stand attachment); "
    "its ram reaches 12.3 below the plaza top so it fills the granite tube while the plate rises by LaunchDepth. "
    "Carve the terrain under the 24 tubes (radius 3.5, from plaza y = 0.6 down to y = -11.6), or the plate sinks into "
    "terrain when lowered.",
    "Spire + SpirePlatform: same origin, unrotated, at the arena centre; the plaza top (0.6) is flush with the Spire's "
    "first tread. Spire slit runs along Roblox Z (sky shows through it from north and south).",
]


def parse():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else os.getcwd()
    prev_dir = argv[1] if len(argv) > 1 else os.path.join(out_dir, "previews")
    opts = {"assets": ",".join(ORDER), "tex": "reuse", "review": "all"}
    for a in argv[2:]:
        if "=" in a:
            k, v = a.split("=", 1)
            opts[k] = v
    return out_dir, prev_dir, opts


def builders():
    import lr_spire
    table = {"Spire": lr_spire.build}
    try:
        import lr_plaza
        table.update({"SpirePlatform": lr_plaza.build_platform, "Plinth": lr_plaza.build_plinth})
    except ImportError:
        pass
    try:
        import lr_lobby
        table.update(lr_lobby.BUILDERS)
    except ImportError:
        pass
    return table


def main():
    t0 = time.time()
    out_dir, prev_dir, opts = parse()
    tex_dir = os.path.join(out_dir, "textures", SET)
    os.makedirs(tex_dir, exist_ok=True)
    need = [m for m in T.MATERIALS for f in T.files_for(m).values() if not os.path.exists(os.path.join(tex_dir, f))]
    if opts["tex"] == "build" or need:
        T.build_all(tex_dir)
        print("TEXTURES built in %.1fs" % (time.time() - t0))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lib = C.Library(SET, tex_dir)
    table = builders()
    wanted = [n for n in ORDER if n in opts["assets"].split(",") and n in table]
    for i, name in enumerate(wanted):
        rnd = random.Random(9100 + ORDER.index(name) * 17)
        a = table[name](lib, rnd)
        lib.finish(a)
        vis = [p for p in a.parts if p["role"] != "Collider"]
        print("TRIS %s total=%d colliders=%d size=%s :: %s" % (
            a.name, a.info["tris"], a.info["colliderTris"], a.info["size"],
            ", ".join("%s=%d" % (p["name"], p["tris"]) for p in a.parts)))
        print("  visual parts %d, collider parts %d" % (len(vis), len(a.parts) - len(vis)))
    lib.notes = IMPORT_NOTES
    repo_manifests = os.path.normpath(os.path.join(HERE, "..", "manifests"))
    full = len(wanted) == len(ORDER)
    manifest, glb = lib.export(out_dir, repo_manifests if full else None)
    if full:
        import ad_finalize                  # art-direction schema + Roblox import checks (prints ADCHECK)
        manifest = ad_finalize.finalize(SET, out_dir)
    print("BUILD done in %.1fs" % (time.time() - t0))
    if opts["review"] != "none":
        import lr_shots
        which = wanted if opts["review"] == "all" else [n for n in opts["review"].split(",") if n in wanted]
        only = opts.get("shots")
        lr_shots.review(lib, which, os.path.join(prev_dir, SET), glb, only_shots=only.split(",") if only else None)
    print("ALL done in %.1fs" % (time.time() - t0))


main()
