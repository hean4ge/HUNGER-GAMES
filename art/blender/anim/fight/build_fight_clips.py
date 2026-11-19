"""
build_fight_clips.py - bakes one family of Combat v3 fight clips in Blender and writes its Luau module.

    blender --background --python build_fight_clips.py -- <Family> <module_dir> <preview_dir> [norender] [only=a,b]

Family: Common | Fists | ShortBlade | Sword | Axe | Spear | Throwing | Bow (clips_<family>.py beside this file).
Writes <module_dir>/<Family>.lua (src/ReplicatedStorage/Shared/FightClips), <preview_dir>/<family>_sheet.png (the
family's 8-frame contact sheet, three-quarter view) and <preview_dir>/<family>_report.txt (per clip: samples, hit
sample, sizes, check lines). Every clip is checked on every sample: feet planted (unless the clip steps), no blade
through the body, no blade in the ground, every hand and foot reachable.
"""
import importlib
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import fight_lib as fl  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FAMILY = argv[0]
MOD_DIR = argv[1]
PREV_DIR = argv[2]
RENDER = "norender" not in argv
ONLY = next((a[5:].split(",") for a in argv if a.startswith("only=")), None)
DEBUG = next((a[6:].split(",") for a in argv if a.startswith("debug=")), [])
GLB = os.path.expandvars(r"%USERPROFILE%\OneDrive\Documents\LastStanding\BlenderExports\WeaponsV3\WeaponsV3.glb")

t0 = time.time()
mod = importlib.import_module("clips_" + FAMILY.lower())
sc = fl.Scene(GLB, mod.ITEMS)
clips = mod.clips()
if ONLY:
    clips = [c for c in clips if c.name in ONLY]
by_name = {c.name: c for c in clips}
entries, report = [], []
for c in clips:
    keys = [k for k in (c.item, c.off_item) if k]
    sc.show_items(keys)
    warn = sc.key(c)
    lines = sc.check(c)
    rows = sc.transforms(c)
    tp, joints = fl.encode_tp(c, rows)
    e = {"name": c.name, "len": c.length, "dt": c.dt, "n": c.n + 1, "mask": c.mask, "hit": c.hit, "loop": c.loop,
         "additive": c.additive, "item": c.item and mod.ITEMS[c.item][0].rsplit("_t", 1)[0], "kind": c.kind,
         "markers": c.markers, "tp": tp, "fpLeft": c.fp_left}
    if c.fp:
        hold = fl.FP_HOLD.get(c.kind, fl.FP_HOLD["Blade"])
        e["fp"] = fl.encode_fp(sc.fp_frames(c, hold))
    entries.append(e)
    hit_s = (" hit sample %d" % round(c.hit / c.dt)) if c.hit else ""
    report.append("%-28s %-5s %5.2fs %3d samples dt %.4f%s  tp %d B  fp %d B  %s" % (
        c.name, c.mask, c.length, c.n + 1, c.dt, hit_s, len(tp), len(e.get("fp", "")), c.note))
    for w in warn[:6] + lines[:10]:
        report.append("    " + w)
    if len(warn) + len(lines) > 16:
        report.append("    ... %d more" % (len(warn) + len(lines) - 16))
    print("CLIP", report[-1] if not (warn or lines) else c.name + " %d warn %d check" % (len(warn), len(lines)))

os.makedirs(MOD_DIR, exist_ok=True)
os.makedirs(PREV_DIR, exist_ok=True)
header = ("Combat v3 fight clips, family %s: %d clips. Third person: joint Transforms (upper: Waist, Neck, arms; full: + Root and legs),\n"
          "per sample 8 characters a joint (a quaternion x, y, z, w at 12 bits), the Root's position in 6 more (+-8 studs).\n"
          "First person: per sample the right and left wrist frames in camera space (position +-4 studs, quaternion) and the\n"
          "two elbow poles. Samples are dt apart; the hit lands on a sample. Played by Client/Controllers/ClipPlayer." % (FAMILY, len(entries)))
if not ONLY:
    size = fl.write_module(os.path.join(MOD_DIR, FAMILY + ".lua"), FAMILY, entries, header)
    report.insert(0, "%s.lua %d bytes, %d clips, %.1f s" % (FAMILY, size, len(entries), time.time() - t0))
    print("MODULE %s.lua %d bytes" % (FAMILY, size))
else:
    fl.write_module(os.path.join(PREV_DIR, FAMILY + "_only.lua"), FAMILY, entries, header)

if DEBUG:
    fl.setup_preview(sc.scene)
    sc.scene.cycles.samples = 12
    for name in DEBUG:
        c = by_name.get(name)
        if c is None:
            continue

        def prep(c=c):
            sc.show_items([k for k in (c.item, c.off_item) if k])
            sc.key(c)
        fr = sorted(set(int(round(i * c.n / 7)) for i in range(8)))
        if c.hit:
            fr = sorted(set(fr) | {int(round(c.hit / c.dt))})[:8]
        shots = [(prep if i == 0 else None, f, "%s %.2fs" % (name, f * c.dt)) for i, f in enumerate(fr)]
        fl.render_tiles(sc.scene, shots, os.path.join(PREV_DIR, "debug", name + ".png"), tile=(300, 350),
                        **getattr(mod, "SHEET_VIEW", {}))
    RENDER = False
if RENDER and getattr(mod, "SHEET", None):
    dev = fl.setup_preview(sc.scene)
    shots = []
    for name, t, label in mod.SHEET:
        c = by_name.get(name)
        if c is None:
            continue

        def prep(c=c):
            sc.show_items([k for k in (c.item, c.off_item) if k])
            sc.key(c)
        f = int(round(t / c.dt))
        shots.append((prep, f, "%s  %.2fs  %s" % (name, f * c.dt, label)))
    kw = getattr(mod, "SHEET_VIEW", {})
    fl.render_tiles(sc.scene, shots, os.path.join(PREV_DIR, FAMILY.lower() + "_sheet.png"), **kw)
    print("PREVIEW %s_sheet.png (%s)" % (FAMILY.lower(), dev))

with open(os.path.join(PREV_DIR, FAMILY.lower() + "_report.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(report) + "\n")
print("DONE %.1f s" % (time.time() - t0))
