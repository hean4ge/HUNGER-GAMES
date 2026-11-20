# Quiet cards icons: render every icon of CardMenusAndShop.md section 4.2 in Blender and pack them into
# 1024 x 1024 sprite sheets with a JSON map of rectangles (ImageRectOffset / ImageRectSize, top-left origin).
#
#   blender --background --factory-startup --python art/blender/ui_icons.py -- <art/icons dir> [id,id,...]
#
# Output in <art/icons dir>:
#   png/<id>.png          one image per icon (256 x 256; rank emblems 512 x 512; banners and trims 768 x 256)
#   Icons_N.png           sprite sheets, 4 x 4 icons of 256
#   Ranks_N.png           2 x 2 rank emblems of 512
#   Banners_N.png         4 banners of 768 x 256 stacked (the right 256 px column is empty)
#   IconAtlas.json        id -> sheet + rectangle + group + name; sheets with an empty assetId to fill after upload
#   IconAtlas.luau        the same map as a Luau table (paste into Shared/Icons.lua)
# Shapes: ui_icons_defs.py; primitives and the look: ui_icons_lib.py.
import glob
import json
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_icons_lib as L  # noqa: E402
import ui_icons_defs as D  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else os.path.join(os.path.dirname(__file__), "..", "icons"))
ONLY = set(a for a in argv[1].split(",") if a) if len(argv) > 1 else None
PNG = os.path.join(OUT, "png")
os.makedirs(PNG, exist_ok=True)

SHADE = (13 / 255, 16 / 255, 18 / 255)
GROUP_ORDER = ["WeaponSkills", "GeneralSkills", "Kits", "Traits", "Currencies", "Cases", "KillIcons",
               "KillEffects", "Emotes", "LaunchEffects", "UI", "Ranks", "Banners", "Trims"]


def find_font():
    pats = [os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\content\fonts\Montserrat-Bold.ttf"),
            r"C:\Windows\Fonts\bahnschrift.ttf"]
    for p in pats:
        hits = sorted(glob.glob(p))
        if hits:
            return hits[-1]
    return None


def setup_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 0
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0
    sc.view_settings.gamma = 1
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.world = None
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.clip_start = 1
    cam_data.clip_end = 2000
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0, 0, 1000)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, cam


def clear_drawing():
    keep = {"cam"}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for cu in list(bpy.data.curves):
        if cu.users == 0:
            bpy.data.curves.remove(cu)
    L._profiles.clear()


def read_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)[::-1].copy()   # top-down


def write_png(path, arr):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("out", w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).ravel().astype(np.float32))
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def box_blur(a, r):
    if r <= 0:
        return a
    k = 2 * r + 1
    pad = np.pad(a, [(r, r), (r, r)] + [(0, 0)] * (a.ndim - 2), mode="edge")
    c = np.cumsum(np.cumsum(pad, 0), 1)
    c = np.pad(c, [(1, 0), (1, 0)] + [(0, 0)] * (a.ndim - 2))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def finish(arr, scale, shadow=True):
    """Add the soft Shade shadow (60%, down 2 px at 256) under the icon and bleed colour into clear pixels."""
    rgb, a = arr[..., :3], arr[..., 3]
    if shadow:
        dy = max(1, int(round(2 * scale)))
        sh = np.zeros_like(a)
        sh[dy:] = a[:-dy]
        sh = box_blur(box_blur(sh, max(1, int(round(scale)))), max(1, int(round(scale))))
        sa = sh * 0.6
        out_a = a + sa * (1 - a)
        safe = np.maximum(out_a, 1e-6)[..., None]
        out_rgb = (rgb * a[..., None] + np.array(SHADE) * (sa * (1 - a))[..., None]) / safe
        rgb, a = out_rgb, out_a
    # colour bleed so resampled edges never pick up black or white fringes
    prem = rgb * a[..., None]
    pb, ab = prem, a
    for r in (2, 4, 8):
        pb = box_blur(pb, r)
        ab = box_blur(ab, r)
    fill = pb / np.maximum(ab, 1e-6)[..., None]
    mean = (prem.sum((0, 1)) / max(a.sum(), 1e-6))
    fill = np.where((ab > 1e-5)[..., None], fill, mean)
    rgb = np.where((a < 0.004)[..., None], fill, rgb)
    return np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], axis=-1)


def render_one(sc, cam, iid, spec):
    kind = spec["kind"]
    if kind == "banner":
        w, h, units, cx, cy = 768, 256, 300.0, 150.0, 50.0
    elif kind == "rank":
        w, h, units, cx, cy = 512, 512, 128.0, 50.0, 50.0
    else:
        w, h, units, cx, cy = 256, 256, 128.0, 50.0, 50.0
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    cam.data.ortho_scale = units
    clear_drawing()
    L.set_canvas(cx, cy)
    spec["fn"]()
    tmp = os.path.join(PNG, "_tmp_" + iid + ".png")
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    arr = read_png(tmp)
    os.remove(tmp)
    arr = finish(arr, w / 256.0 if kind != "banner" else 1.0, shadow=(kind != "banner" or spec["group"] == "Trims"))
    write_png(os.path.join(PNG, iid + ".png"), arr)
    return arr


def pack(entries):
    """entries: [(id, spec, arr)] in order -> sheets dict and rect map."""
    sheets, rects = {}, {}

    def new_sheet(prefix):
        n = sum(1 for k in sheets if k.startswith(prefix + "_")) + 1
        name = "%s_%d" % (prefix, n)
        sheets[name] = np.zeros((1024, 1024, 4), dtype=np.float32)
        return name

    plans = [("Icons", 256, 256, lambda e: e[1]["kind"] == "icon"),
             ("Ranks", 512, 512, lambda e: e[1]["kind"] == "rank"),
             ("Banners", 768, 256, lambda e: e[1]["kind"] == "banner")]
    for prefix, cw, ch, pick in plans:
        items = [e for e in entries if pick(e)]
        cols = 1024 // cw
        per = cols * (1024 // ch)
        for i, (iid, spec, arr) in enumerate(items):
            if i % per == 0:
                cur = new_sheet(prefix)
            k = i % per
            x, y = (k % cols) * cw, (k // cols) * ch
            sheets[cur][y:y + ch, x:x + cw] = arr
            rects[iid] = dict(sheet=cur, x=x, y=y, w=cw, h=ch, group=spec["group"], name=spec["name"])
    return sheets, rects


def main():
    sc, cam = setup_scene()
    font = find_font()
    if font:
        L.set_font(font)
    allspecs = dict(D.ICONS)
    allspecs.update(D.BANNERS)
    order = sorted(allspecs.items(), key=lambda kv: GROUP_ORDER.index(kv[1]["group"]))
    entries = []
    for iid, spec in order:
        path = os.path.join(PNG, iid + ".png")
        if ONLY is not None and iid not in ONLY and os.path.exists(path):
            entries.append((iid, spec, read_png(path)))
            continue
        arr = render_one(sc, cam, iid, spec)
        print("rendered", iid, flush=True)
        entries.append((iid, spec, arr))
    sheets, rects = pack(entries)
    for name, arr in sheets.items():
        write_png(os.path.join(OUT, name + ".png"), finish(arr, 1.0, shadow=False))
    counts = {}
    for r in rects.values():
        counts[r["group"]] = counts.get(r["group"], 0) + 1
    atlas = dict(
        generator="art/blender/ui_icons.py (+ ui_icons_defs.py, ui_icons_lib.py)",
        design="docs/design/CardMenusAndShop.md section 4.2",
        style="matte flat facets, one shade step on lower-right facets, soft Shade shadow at 60%, transparent; "
              "icons 256 (silhouette in the centre 200), rank emblems 512, banners 768x256",
        font=os.path.basename(font) if font else None,
        upload="Not uploaded. Upload each sheet as an Image (Decal) after the owner's yes and fill assetId.",
        sheets={k: dict(file=k + ".png", size=[1024, 1024], assetId="") for k in sheets},
        counts=counts,
        icons=rects,
    )
    with open(os.path.join(OUT, "IconAtlas.json"), "w", encoding="utf-8") as f:
        json.dump(atlas, f, indent=1)
    lines = ["-- Generated by art/blender/ui_icons.py. Quiet cards icon atlas (CardMenusAndShop.md 4.2).",
             "-- Rect = ImageRectOffset (x, y) + ImageRectSize (w, h) on the sheet image. Fill the asset ids after upload.",
             "return {", "\tSheets = {"]
    for k in sheets:
        lines.append('\t\t%s = "", -- rbxassetid:// of %s.png' % (k, k))
    lines += ["\t},", "\tIcons = {"]
    for iid, r in rects.items():
        lines.append('\t\t%s = { sheet = "%s", x = %d, y = %d, w = %d, h = %d, group = "%s", name = "%s" },'
                     % (iid, r["sheet"], r["x"], r["y"], r["w"], r["h"], r["group"], r["name"].replace('"', "")))
    lines += ["\t},", "}", ""]
    with open(os.path.join(OUT, "IconAtlas.luau"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("ICONS", len(rects), "SHEETS", len(sheets), json.dumps(counts))


main()
