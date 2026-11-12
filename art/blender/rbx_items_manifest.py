"""rbx_items_manifest.py - generate the Luau data module ServerStorage.WorldGen.ItemAssets.Manifest.

Plain Python (no Blender needed). It reads the ItemsReal manifest (schema LS-Real-1) and the upload ledger
art/manifests/RealSets.assetIds.json, and writes art/manifests/ItemAssets.Manifest.luau. Paste that file into the
ModuleScript ServerStorage.WorldGen.ItemAssets.Manifest (Studio), then rebuild and check the templates:

    print(require(game.ServerStorage.WorldGen.ItemAssets:Clone()).build())
    print(require(game.ServerStorage.WorldGen.ItemAssets:Clone()).verify())

Run from the repo root:

    python art/blender/rbx_items_manifest.py [BlenderExports] [art/manifests/RealSets.assetIds.json] [out.luau]

Defaults: %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports, the ledger next to the manifests, and
art/manifests/ItemAssets.Manifest.luau. Re-run it after a re-export of ItemsReal.glb or a new upload.

What goes in (all vectors in Roblox space, studs, relative to the asset origin as in the manifest):
  SOURCES  Items -> ItemsReal.glb (the Model asset from the ledger)
  IMAGES   image key (PNG basename) -> image asset id, the 16 ItemsReal images (8 importer + 8 uploaded)
  SURF     surface index -> { color, normal, roughness, metalness|false } as IMAGES keys
  Items    per asset: kind, origin, bmin, bmax, parts, att
           P(name, role, material, rgb, surf, flags, extra?) with flags = letters c collide, s castShadow,
           q canQuery, t canTouch, n neon; extra = { transparency, alpha, tags, collision, tint } only where they differ
           from 0 / Overlay / none / Box / white. surf 0 = no SurfaceAppearance (the Neon ember strip).
           A(position, look, up) per attachment.
The v1 Blender arms (Assets.Viewmodel, unused) are not in here; ServerStorage.Archive_v1.ItemAssets_v1 rebuilds them.
"""
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def num(v):
    """Compact, stable number formatting (4 decimals, no trailing zeros)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def vec(t):
    return "{" + ",".join(num(float(x)) for x in t) + "}"


def ivec(t):
    return "{" + ",".join(str(int(x)) for x in t) + "}"


def lstr(s):
    return json.dumps(s)  # a JSON string literal is a valid Luau string literal for these names


def key_of(path):
    return os.path.splitext(os.path.basename(path))[0]


def main():
    exports = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.environ.get("USERPROFILE", ""), "OneDrive", "Documents", "LastStanding", "BlenderExports")
    ledger_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "art", "manifests", "RealSets.assetIds.json")
    out_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(REPO, "art", "manifests", "ItemAssets.Manifest.luau")

    items = json.load(open(os.path.join(exports, "ItemsReal.manifest.json"), encoding="utf-8"))
    ledger = json.load(open(ledger_path, encoding="utf-8"))
    problems = []
    if items.get("schema") != "LS-Real-1":
        problems.append("ItemsReal schema %s" % items.get("schema"))
    if items.get("adCheck", {}).get("problems"):
        problems.append("ItemsReal adCheck problems: %s" % items["adCheck"]["problems"])

    model = ledger["models"].get("ItemsReal.glb") or {}
    if model.get("assetId") is None:
        problems.append("ItemsReal.glb has no asset id in the ledger")
    if model.get("moderationState") not in (None, "Approved"):
        problems.append("ItemsReal.glb moderation %s" % model.get("moderationState"))
    images = {}
    for f, e in ledger["images"].items():
        if f.startswith("textures/ItemsReal/"):
            if e.get("assetId") is None:
                problems.append("no asset id for " + f)
                continue
            images[key_of(f)] = int(e["assetId"])
    for t in items.get("uploadTextures", []):
        if key_of(t["file"]) not in images:
            problems.append("upload image %s has no asset id" % t["file"])

    surfs = []
    surf_index = {}

    def surf_of(sa):
        keys = (key_of(sa["colorMap"]), key_of(sa["normalMap"]), key_of(sa["roughnessMap"]),
                key_of(sa["metalnessMap"]) if sa.get("metalnessMap") else None)
        for k in keys:
            if k is not None and k not in images:
                problems.append("image %s has no asset id" % k)
        if keys not in surf_index:
            surfs.append(keys)
            surf_index[keys] = len(surfs)
        return surf_index[keys]

    item_lines = ["\tItems = {"]
    nparts = 0
    for a in sorted(items["assets"], key=lambda a: a["name"]):
        item_lines.append("\t\t%s = { kind = %s, origin = %s, bmin = %s, bmax = %s, parts = {" % (
            a["name"], lstr(a["kind"]), vec(a["origin"]), vec(a["boundsMin"]), vec(a["boundsMax"])))
        for p in a["parts"]:
            sa = p.get("surfaceAppearance")
            neon = bool(p.get("neon"))
            if sa and neon:
                problems.append("%s: neon part with a surfaceAppearance" % p["name"])
            if not sa and not neon:
                problems.append("%s: no surfaceAppearance" % p["name"])
            surf = surf_of(sa) if sa else 0
            flags = "".join(ch for ch, on in (("c", p["collide"]), ("s", p["castShadow"]), ("q", p["canQuery"]),
                                               ("t", p["canTouch"]), ("n", neon)) if on)
            extra = []
            if float(p.get("transparency") or 0) != 0:
                extra.append("transparency = %s" % num(float(p["transparency"])))
            if sa and (sa.get("alphaMode") or "Overlay") != "Overlay":
                extra.append("alpha = %s" % lstr(sa["alphaMode"]))
            if p.get("tags"):
                extra.append("tags = {%s}" % ",".join(lstr(t) for t in p["tags"]))
            if p.get("collision", "Box") != "Box":
                extra.append("collision = %s" % lstr(p["collision"]))
            if sa and list(sa.get("color") or [255, 255, 255]) != [255, 255, 255]:
                extra.append("tint = %s" % ivec(sa["color"]))
            item_lines.append("\t\t\tP(%s, %s, %s, %s, %d, %s%s)," % (
                lstr(p["name"]), lstr(p["role"]), lstr(p["robloxMaterial"]), ivec(p["rgb"]), surf, lstr(flags),
                (", { " + ", ".join(extra) + " }") if extra else ""))
            nparts += 1
        att = a.get("attachments") or {}
        item_lines.append("\t\t}, att = {")
        for name in sorted(att):
            v = att[name]
            item_lines.append("\t\t\t%s = A(%s, %s, %s)," % (name, vec(v["position"]), vec(v["look"]), vec(v["up"])))
        item_lines.append("\t\t} },")
    item_lines.append("\t},")

    if problems:
        print("PROBLEMS:")
        for p in problems:
            print("  " + p)
        sys.exit(1)

    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = []
    out.append("--[[")
    out.append("\tItemAssets.Manifest - GENERATED by art/blender/rbx_items_manifest.py on %s. Do not edit by hand:" % stamp)
    out.append("\tre-run the generator after a re-export or a new upload and paste art/manifests/ItemAssets.Manifest.luau here.")
    out.append("\tSources: BlenderExports/ItemsReal.manifest.json (schema LS-Real-1) and art/manifests/RealSets.assetIds.json.")
    out.append("\tRoblox space, studs, relative to each asset's origin (held items: the hand grip; crates: the floor centre,")
    out.append("\tfront = -Z). P(name, role, material, rgb, surf, flags, extra?): flags c collide, s castShadow, q canQuery,")
    out.append("\tt canTouch, n neon; extra overrides transparency 0, alpha Overlay, tags none, collision Box, tint white.")
    out.append("\tsurf indexes SURF (0 = no SurfaceAppearance: the Neon ember strip). A(position, look, up).")
    out.append("]]")
    out.append("local function P(name, role, mat, rgb, surf, flags, x)")
    out.append("\tx = x or {}")
    out.append("\tlocal function has(c)")
    out.append("\t\treturn string.find(flags, c, 1, true) ~= nil")
    out.append("\tend")
    out.append("\treturn { name = name, role = role, mat = mat, rgb = rgb, surf = surf, collide = has(\"c\"), shadow = has(\"s\"),")
    out.append("\t\tquery = has(\"q\"), touch = has(\"t\"), neon = has(\"n\"), transparency = x.transparency or 0,")
    out.append("\t\talpha = x.alpha or \"Overlay\", tags = x.tags or {}, collision = x.collision or \"Box\", tint = x.tint or { 255, 255, 255 } }")
    out.append("end")
    out.append("local function A(pos, look, up)")
    out.append("\treturn { pos = pos, look = look, up = up }")
    out.append("end")
    out.append("return {")
    out.append("\tSCHEMA = \"LS-Real-1\",")
    out.append("\tGENERATED = %s," % lstr(stamp))
    out.append("\t-- the uploaded Model asset (raw insert: ServerStorage.MeshImports.<name>)")
    out.append("\tSOURCES = {")
    out.append("\t\tItems = { assetId = %d, name = %s, file = \"ItemsReal.glb\" }," % (
        int(model["assetId"]), lstr(model.get("displayName", "LS_ItemsReal_v1"))))
    out.append("\t},")
    out.append("\t-- image key (PNG basename) -> image asset id; one id per file, shared by every SurfaceAppearance")
    out.append("\tIMAGES = {")
    for k in sorted(images):
        out.append("\t\t%s = %d," % (k, images[k]))
    out.append("\t},")
    out.append("\t-- surface -> { ColorMap, NormalMap, RoughnessMap, MetalnessMap (false = leave empty) } as IMAGES keys")
    out.append("\tSURF = {")
    for i, (c, n, r, mm) in enumerate(surfs, 1):
        out.append("\t\t{ %s, %s, %s, %s }, -- %d" % (lstr(c), lstr(n), lstr(r), lstr(mm) if mm else "false", i))
    out.append("\t},")
    out.extend(item_lines)
    out.append("}")
    text = "\n".join(out) + "\n"
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote %s (%d bytes)" % (out_path, len(text.encode("utf-8"))))
    print("items %d (%d parts), images %d, surfaces %d" % (len(items["assets"]), nparts, len(images), len(surfs)))


if __name__ == "__main__":
    main()
