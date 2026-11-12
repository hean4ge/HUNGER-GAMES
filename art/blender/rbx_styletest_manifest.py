"""Writes art/manifests/StyleTest.Manifest.luau (the data child of ServerStorage.StyleTest.StyleTestBuilder) from the
three style-test manifests next to the GLBs and the id ledger art/manifests/StyleTest.assetIds.json.

    python -I art/blender/rbx_styletest_manifest.py            (run from the repo root)

Image ids per texture set:
  ColorMap / NormalMap  the importer's own images (ledger 'importerImages', pixel-checked against the PNGs)
  RoughnessMap          the grayscale PNG uploaded once (ledger 'images', use asset:<set>) where the importer's map
                        (the packed glTF metallicRoughness G channel at its embedded size) is half the PNG size:
                        A Spruce/Oak/Cabin/CabinRoof and all of B. Elsewhere (A Boulder, all of C) the importer's
                        map is full size and pixel-identical, so its id is used (ledger 'importerImages', used=true).
Ground tiles: the three PNGs of each tile, uploaded once (ledger 'images', use terrain:StyleTest_<V>_<Tile>).
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORTS = os.path.join(os.environ.get("USERPROFILE", ""), "OneDrive", "Documents", "LastStanding", "BlenderExports")
LEDGER = os.path.join(REPO, "art", "manifests", "StyleTest.assetIds.json")
OUT = os.path.join(REPO, "art", "manifests", "StyleTest.Manifest.luau")

VARIANTS = [
    ("A", "A_LowPolyRealism", "A  Low-poly realism", "StyleTest/A/StyleTest_A.manifest.json"),
    ("B", "B_BlockyVoxelRealism", "B  Blocky voxel realism", "StyleTest/B/StyleTest_B.manifest.json"),
    ("C", "C_SmoothStylizedRealism", "C  Smooth stylized realism", "StyleTest/C/StyleTest_C.manifest.json"),
]
GLB = {"A": "StyleTest/A/StyleTest_A.glb", "B": "StyleTest/B/StyleTest_B.glb", "C": "StyleTest/C/StyleTest_C.glb"}


def set_key(path):
    base = os.path.basename(path)
    for suffix in ("_Color.png",):
        if base.endswith(suffix):
            return base[: -len(suffix)]
    raise ValueError(path)


def main():
    with open(LEDGER, encoding="utf-8") as f:
        ledger = json.load(f)
    images = ledger.get("images", {})
    importer = ledger.get("importerImages", {})

    def uploaded(path):
        e = images.get(path)
        return e and e.get("assetId")

    out = {"CREATOR": ledger["creator"]["userId"], "ORDER": [v[0] for v in VARIANTS], "VARIANTS": {}}
    missing = []
    for key, style, label, rel in VARIANTS:
        with open(os.path.join(EXPORTS, rel), encoding="utf-8") as f:
            man = json.load(f)
        prefix = os.path.dirname(rel).replace("\\", "/") + "/"
        model = ledger["models"][GLB[key]]
        v = {"key": key, "style": style, "label": label,
             "source": {"name": model["displayName"], "assetId": model.get("assetId")},
             "roles": {}, "assets": {}, "textures": {}, "ground": {}}
        for a in man["assets"]:
            kind = a.get("kind")
            name = a["name"]
            if kind == "Tree":
                v["roles"]["oak" if "Oak" in name else "conifer"] = name
            elif kind == "Building":
                v["roles"]["cabin"] = name
            elif kind == "Rock":
                v["roles"]["boulder"] = name
            parts = []
            for p in a["parts"]:
                sa = p.get("surfaceAppearance")
                tex = None
                if sa:
                    tex = set_key(sa["colorMap"])
                    if tex not in v["textures"]:
                        rough_rel = sa["roughnessMap"] if sa["roughnessMap"].startswith("StyleTest/") else prefix + sa["roughnessMap"]
                        imp_rough = importer.get(tex + "_Rough") or {}
                        t = {"color": (importer.get(tex + "_Color") or {}).get("assetId"),
                             "normal": (importer.get(tex + "_Normal") or {}).get("assetId"),
                             # the uploaded grayscale PNG, or the importer's own map where it is full size and verified
                             "rough": uploaded(rough_rel) or (imp_rough.get("assetId") if imp_rough.get("used") else None)}
                        for k2, val in t.items():
                            if not val:
                                missing.append("%s %s %s" % (key, tex, k2))
                        v["textures"][tex] = t
                parts.append({
                    "name": p["name"], "role": p.get("role"), "mat": p.get("robloxMaterial"), "rgb": p.get("rgb"),
                    "collide": bool(p.get("collide")), "collision": p.get("collision"),
                    "shadow": bool(p.get("castShadow")), "query": bool(p.get("canQuery")),
                    "touch": bool(p.get("canTouch")), "transparency": float(p.get("transparency") or 0),
                    "tags": p.get("tags") or [], "tex": tex,
                    "alpha": (sa or {}).get("alphaMode", "Overlay"), "tint": (sa or {}).get("color", [255, 255, 255]),
                })
            att = {}
            for n, at in (a.get("attachments") or {}).items():
                att[n] = {"pos": at["position"], "look": at["look"], "up": at["up"]}
            v["assets"][name] = {"kind": kind, "origin": a["origin"], "bmin": a["boundsMin"], "bmax": a["boundsMax"],
                                 "tris": a.get("tris"), "parts": parts, "att": att}
        for t in man.get("terrainMaterials", []):
            tile = "Pebble" if "Pebble" in t["name"] else "ForestFloor"
            def rp(p):
                return p if p.startswith("StyleTest/") else prefix + p
            g = {"name": "StyleTest_%s_%s" % (key, tile), "artistName": t["name"],
                 "color": uploaded(rp(t["colorMap"])), "normal": uploaded(rp(t["normalMap"])),
                 "rough": uploaded(rp(t["roughnessMap"])),
                 "studsPerTile": float(t.get("studsPerTile") or 8), "pattern": t.get("materialPattern", "Organic"),
                 "artistBase": t.get("baseMaterial") or t.get("suggestedBaseMaterial"),
                 "artistTerrainColor": t.get("terrainColor")}
            for k2 in ("color", "normal", "rough"):
                if not g[k2]:
                    missing.append("%s %s %s" % (key, tile, k2))
            v["ground"][tile] = g
        for r in ("conifer", "oak", "cabin", "boulder"):
            if r not in v["roles"]:
                missing.append("%s role %s" % (key, r))
        out["VARIANTS"][key] = v

    # asset ids travel as strings (no float formatting on the Luau side)
    def ids_to_str(o):
        if isinstance(o, dict):
            return {k: (str(val) if k in ("assetId", "color", "normal", "rough") and isinstance(val, int) else ids_to_str(val))
                    for k, val in o.items()}
        if isinstance(o, list):
            return [ids_to_str(x) for x in o]
        return o

    out = ids_to_str(out)
    body = json.dumps(out, separators=(",", ":"))
    assert "]==]" not in body
    header = ("-- GENERATED by art/blender/rbx_styletest_manifest.py from BlenderExports/StyleTest/<V>/*.manifest.json and\n"
              "-- art/manifests/StyleTest.assetIds.json. Do not edit by hand; regenerate after a re-export or a new upload.\n"
              "-- Shape: CREATOR, ORDER {A,B,C}, VARIANTS[V] = { key, style, label, source{name,assetId}, roles{conifer,oak,\n"
              "-- cabin,boulder}, assets[name]{kind,origin,bmin,bmax,tris,parts[]{name,role,mat,rgb,collide,collision,shadow,\n"
              "-- query,touch,transparency,tags,tex,alpha,tint},att[name]{pos,look,up}}, textures[set]{color,normal,rough},\n"
              "-- ground[Pebble|ForestFloor]{name,artistName,color,normal,rough,studsPerTile,pattern,artistBase,\n"
              "-- artistTerrainColor} }. Image and model ids are strings.\n")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "return game:GetService(\"HttpService\"):JSONDecode([==[" + body + "]==])\n")
    print("wrote", OUT)
    if missing:
        print("MISSING ids (%d):" % len(missing))
        for m in missing:
            print("  ", m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
