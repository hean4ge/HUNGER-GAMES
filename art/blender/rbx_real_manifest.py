"""rbx_real_manifest.py - generate the Luau data module ServerStorage.WorldGen.RealAssets.Manifest.

Plain Python (no Blender needed). It reads the LS-Real-1 manifests listed in BlenderExports/RealSets.index.json and
the upload ledger art/manifests/RealSets.assetIds.json, and writes art/manifests/RealAssets.Manifest.luau. Paste that
file into the ModuleScript ServerStorage.WorldGen.RealAssets.Manifest (Studio), then rebuild the templates:

    print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).build())

Run from the repo root:

    python art/blender/rbx_real_manifest.py [BlenderExports] [art/manifests/RealSets.assetIds.json] [out.luau]

Defaults: %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports, the ledger next to the manifests, and
art/manifests/RealAssets.Manifest.luau. Re-run it after any re-export or new upload (new GLB or image ids).

What goes in (all vectors in Roblox space, studs, relative to the asset origin as in the manifests):
  SOURCES  GLB key -> { assetId, name, file }               every uploaded GLB (ItemsReal too)
  IMAGES   image key (PNG basename) -> image asset id        all 77 upload images (52 importer + 25 uploaded)
  SURF     surface index -> { color, normal, roughness, metalness|false }   image keys
  SETS     world sets only (TreesReal, GroundReal, LandmarksReal, BuildingsReal, PropsReal; ItemsReal templates belong
           to ItemAssets). Per asset: src, kind, tags, origin, bmin, bmax, tris, parts, att.
           Per part P(name, role, material, rgb, collide, collision, castShadow, canQuery, canTouch, transparency,
           tags, surf, alphaMode, tint, neon).
           Per attachment A(position, look, up).
"""
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
WORLD_SETS = ["TreesReal", "GroundReal", "LandmarksReal", "BuildingsReal", "PropsReal"]
GLB_KEY = {  # GLB file -> SOURCES key (also the raw insert's name without the LS_ prefix and _v1 suffix)
    "TreesReal.glb": "TreesReal",
    "GroundReal_Flora.glb": "GroundReal_Flora",
    "GroundReal_Rocks.glb": "GroundReal_Rocks",
    "GroundReal_Cliffs.glb": "GroundReal_Cliffs",
    "LandmarksReal.glb": "LandmarksReal",
    "BuildingsReal.glb": "BuildingsReal",
    "PropsReal.glb": "PropsReal",
    "ItemsReal.glb": "ItemsReal",
}


def num(v):
    """Compact, stable number formatting (4 decimals, no trailing zeros)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def vec(t):
    return "{" + ",".join(num(x) for x in t) + "}"


def lstr(s):
    return json.dumps(s)  # a JSON string literal is a valid Luau string literal for these names


def key_of(path):
    return os.path.splitext(os.path.basename(path))[0]


def main():
    exports = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.environ.get("USERPROFILE", ""), "OneDrive", "Documents", "LastStanding", "BlenderExports")
    ledger_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "art", "manifests", "RealSets.assetIds.json")
    out_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(REPO, "art", "manifests", "RealAssets.Manifest.luau")

    index = json.load(open(os.path.join(exports, "RealSets.index.json"), encoding="utf-8"))
    ledger = json.load(open(ledger_path, encoding="utf-8"))
    problems = []

    # sources and images from the ledger
    sources = {}
    for f, e in ledger["models"].items():
        if e.get("assetId") is None:
            problems.append("no asset id for " + f)
            continue
        sources[GLB_KEY[f]] = (int(e["assetId"]), e["displayName"], f)
    images = {}
    for f, e in ledger["images"].items():
        if e.get("assetId") is None:
            problems.append("no asset id for " + f)
            continue
        images[key_of(f)] = int(e["assetId"])

    surfs = []  # list of (c, n, r, m)
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

    set_blocks = []
    counts = {}
    for s in index["sets"]:
        if s["set"] not in WORLD_SETS:
            continue
        m = json.load(open(os.path.join(exports, s["manifest"]), encoding="utf-8"))
        if m.get("schema") != "LS-Real-1":
            problems.append("%s schema %s" % (s["set"], m.get("schema")))
        lines = ["\t%s = {" % s["set"]]
        nparts = 0
        for a in sorted(m["assets"], key=lambda a: a["name"]):
            src = GLB_KEY[a["glb"]]
            if src not in sources:
                problems.append("%s: GLB %s not uploaded" % (a["name"], a["glb"]))
            lines.append("\t\t%s = { src = %s, kind = %s, tags = {%s}, origin = %s, bmin = %s, bmax = %s, tris = %d," % (
                a["name"], lstr(src), lstr(a["kind"]), ",".join(lstr(t) for t in a.get("tags", [])),
                vec(a["origin"]), vec(a["boundsMin"]), vec(a["boundsMax"]), a.get("tris", 0)))
            lines.append("\t\t\tparts = {")
            for p in a["parts"]:
                sa = p.get("surfaceAppearance")
                neon = bool(p.get("neon"))
                if sa and neon:
                    problems.append("%s: neon part with a surfaceAppearance" % p["name"])
                surf = surf_of(sa) if sa else 0
                alpha = sa.get("alphaMode") or "Overlay" if sa else "Overlay"
                tint = sa.get("color") or [255, 255, 255] if sa else [255, 255, 255]
                tags = p.get("tags") or []
                lines.append("\t\t\t\tP(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, {%s}, %d, %s, %s, %s)," % (
                    lstr(p["name"]), lstr(p["role"]), lstr(p["robloxMaterial"]), vec(p["rgb"]), num(bool(p["collide"])),
                    lstr(p["collision"]), num(bool(p["castShadow"])), num(bool(p["canQuery"])), num(bool(p["canTouch"])),
                    num(float(p.get("transparency") or 0)), ",".join(lstr(t) for t in tags), surf, lstr(alpha),
                    vec(tint), num(neon)))
                nparts += 1
            lines.append("\t\t\t},")
            att = a.get("attachments") or {}
            if att:
                lines.append("\t\t\tatt = {")
                for name in sorted(att, key=lambda n: (n.rstrip("0123456789"), int("0" + "".join(ch for ch in n if ch.isdigit())), n)):
                    v = att[name]
                    lines.append("\t\t\t\t%s = A(%s, %s, %s)," % (name, vec(v["position"]), vec(v["look"]), vec(v["up"])))
                lines.append("\t\t\t},")
            else:
                lines.append("\t\t\tatt = {},")
            lines.append("\t\t},")
        lines.append("\t},")
        set_blocks.append("\n".join(lines))
        counts[s["set"]] = (len(m["assets"]), nparts)

    if problems:
        print("PROBLEMS:")
        for p in problems:
            print("  " + p)
        sys.exit(1)

    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = []
    out.append("--[[")
    out.append("\tRealAssets.Manifest - GENERATED by art/blender/rbx_real_manifest.py on %s. Do not edit by hand:" % stamp)
    out.append("\tre-run the generator after a re-export or a new upload and paste art/manifests/RealAssets.Manifest.luau here.")
    out.append("\tSources: BlenderExports/*.manifest.json (schema LS-Real-1) and art/manifests/RealSets.assetIds.json.")
    out.append("\tRoblox space, studs, relative to each asset's origin (base centre on the ground, front = -Z).")
    out.append("\tP(name, role, material, rgb, collide, collision, castShadow, canQuery, canTouch, transparency, tags, surf,")
    out.append("\t  alphaMode, tint, neon); surf indexes SURF (0 = no SurfaceAppearance: Neon embers and invisible colliders).")
    out.append("\tA(position, look, up) relative to the asset origin.")
    out.append("]]")
    out.append("local function P(name, role, mat, rgb, collide, collision, shadow, query, touch, transparency, tags, surf, alpha, tint, neon)")
    out.append("\treturn { name = name, role = role, mat = mat, rgb = rgb, collide = collide, collision = collision, shadow = shadow,")
    out.append("\t\tquery = query, touch = touch, transparency = transparency, tags = tags, surf = surf, alpha = alpha, tint = tint, neon = neon }")
    out.append("end")
    out.append("local function A(pos, look, up)")
    out.append("\treturn { pos = pos, look = look, up = up }")
    out.append("end")
    out.append("return {")
    out.append("\tSCHEMA = \"LS-Real-1\",")
    out.append("\tGENERATED = %s," % lstr(stamp))
    out.append("\t-- GLB key -> uploaded Model asset (raw inserts: ServerStorage.MeshImports.<name>)")
    out.append("\tSOURCES = {")
    for k in sorted(sources):
        aid, name, f = sources[k]
        out.append("\t\t%s = { assetId = %d, name = %s, file = %s }," % (k, aid, lstr(name), lstr(f)))
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
    out.append("\tSETS = {")
    out.extend(set_blocks)
    out.append("\t},")
    out.append("}")
    text = "\n".join(out) + "\n"
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote %s (%d bytes)" % (out_path, len(text.encode("utf-8"))))
    print("sources %d, images %d, surfaces %d" % (len(sources), len(images), len(surfs)))
    for k, (na, npart) in counts.items():
        print("  %-14s %3d assets %4d parts" % (k, na, npart))


if __name__ == "__main__":
    main()
