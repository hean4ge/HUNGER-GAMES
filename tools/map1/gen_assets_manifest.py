"""gen_assets_manifest.py - writes src/ServerStorage/WorldGen/Map1/Assets/Manifest.lua, the generated child module of
ServerStorage.WorldGen.Map1.Assets (the builder that turns the uploaded Map 1 meshes into templates and places them).

It reads, and never changes:
  art/manifests/Map1_<Set>.manifest.json   the Blender manifests WITH their "assetIds" entry (the upload ledger)
  <exports>/Map1_<Set>.glb                 for each part's own centre and size (the manifest has them per asset only)
  <exports>/Map1_Layout.json               the placements and the heart's numbers

  python tools/map1/gen_assets_manifest.py [--exports <folder>] [--check]

--exports defaults to %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports/Map1. --check writes nothing and
exits 1 when the file on disk differs from what would be written.

A set is included only when its manifest carries an asset id (it has been uploaded) and its GLB is the uploaded file
(same SHA-256 as the ledger says). Run it again after an upload or a re-export, then push the module with
tools/studio_sync (see that README) and run Assets.build() and Assets.verify() in Studio.
numpy is the only dependency.
"""
import hashlib
import io
import json
import os
import struct
import sys

import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(REPO, "src", "ServerStorage", "WorldGen", "Map1", "Assets", "Manifest.lua")
MANIFESTS = os.path.join(REPO, "art", "manifests")
DEFAULT_EXPORTS = os.path.join(os.environ.get("USERPROFILE", ""), "OneDrive", "Documents", "LastStanding",
                               "BlenderExports", "Map1")
# set key -> (manifest file stem, name of the raw insert in ServerStorage.MeshImports). The order is the build order.
SETS = [
    ("Landmarks", "Map1_Landmarks", "Map1_Landmarks"),
    ("Plants", "Map1_Plants", "Map1_Plants"),
    ("Skyline", "Map1_SkylineCut", "Map1_Skyline"),
    ("FarValley", "Map1_FarValley", "Map1_FarValley"),
]
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def glb_part_bounds(path):
    """{mesh node name: (asset name, min xyz, max xyz)} in the asset's own space (Roblox axes = glTF axes)."""
    with open(path, "rb") as fh:
        _magic, _ver, _length = struct.unpack("<4sII", fh.read(12))
        clen, _ctype = struct.unpack("<I4s", fh.read(8))
        j = json.loads(fh.read(clen))
        blen, _btype = struct.unpack("<I4s", fh.read(8))
        blob = fh.read(blen)

    def positions(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        dt = np.dtype(CT[a["componentType"]]).newbyteorder("<")
        n = NC[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride")
        if stride and stride != dt.itemsize * n:
            raw = np.frombuffer(blob, dtype=np.uint8, count=stride * a["count"], offset=off).reshape(a["count"], stride)
            return raw[:, : dt.itemsize * n].copy().view(dt).reshape(a["count"], n)
        return np.frombuffer(blob, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)

    out = {}

    def walk(ni, offset, asset):
        n = j["nodes"][ni]
        if n.get("rotation") or n.get("scale") or n.get("matrix"):
            sys.exit("%s: node %s is rotated or scaled; the builder expects translations only" % (path, n.get("name")))
        t = np.array(n.get("translation", [0, 0, 0]), dtype=np.float64)
        here = offset + t if asset is not None else np.zeros(3)  # the root's own translation is its place in the row
        if asset is None:
            asset = n.get("name")
        if "mesh" in n:
            lo = np.full(3, np.inf)
            hi = np.full(3, -np.inf)
            for pr in j["meshes"][n["mesh"]]["primitives"]:
                v = positions(pr["attributes"]["POSITION"]).astype(np.float64) + here
                lo = np.minimum(lo, v.min(0))
                hi = np.maximum(hi, v.max(0))
            if n.get("name") in out:
                sys.exit("%s: two meshes are named %s" % (path, n.get("name")))
            out[n["name"]] = (asset, lo, hi)
        for c in n.get("children", []):
            walk(c, here, asset)

    for r in j["scenes"][0]["nodes"]:
        walk(r, np.zeros(3), None)
    return out


def num(x):
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, int):
        return str(x)
    s = "%.4f" % float(x)
    s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def lua(v, indent=0):
    """A Lua literal for JSON-like data (dict keys must be strings)."""
    if v is None:
        return "nil"
    if isinstance(v, (bool, int, float)):
        return num(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=True)
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float, str, bool)) or x is None for x in v):
            return "{" + ", ".join(lua(x) for x in v) + "}"
        pad = "\t" * (indent + 1)
        return "{\n" + "".join(pad + lua(x, indent + 1) + ",\n" for x in v) + "\t" * indent + "}"
    if isinstance(v, dict):
        pad = "\t" * (indent + 1)
        parts = []
        for k, x in v.items():
            key = k if (k.replace("_", "a").isalnum() and not k[0].isdigit()) else "[" + json.dumps(k) + "]"
            parts.append(pad + key + " = " + lua(x, indent + 1) + ",\n")
        return "{\n" + "".join(parts) + "\t" * indent + "}"
    raise TypeError(type(v))


def vec(v):
    return "{" + ", ".join(num(x) for x in v) + "}"


def main(argv):
    exports = DEFAULT_EXPORTS
    check = "--check" in argv
    if "--exports" in argv:
        exports = argv[argv.index("--exports") + 1]
    lines = []
    w = lines.append
    w("-- GENERATED by tools/map1/gen_assets_manifest.py from art/manifests/Map1_*.manifest.json (with their")
    w("-- \"assetIds\"), the uploaded GLBs (each part's own bounds) and Map1_Layout.json. Do not edit: run the script.")
    w("-- Vectors are Roblox space (X east, Y up, Z south), relative to the asset's pivot. Part fields: name, role,")
    w("-- mat (the manifest's Roblox material: Assets maps it to a matte one), rgb, collide, collision (fidelity),")
    w("-- shadow, query, touch, tris, c / s (the part's own centre and size, measured in the GLB), hidden (invisible).")
    w("local M = {}")
    w("")
    w("local function P(name, role, mat, r, g, b, collide, collision, shadow, query, touch, tris, cx, cy, cz, sx, sy, sz, hidden)")
    w("\treturn {")
    w("\t\tname = name, role = role, mat = mat, rgb = { r, g, b }, collide = collide, collision = collision,")
    w("\t\tshadow = shadow, query = query, touch = touch, tris = tris, c = { cx, cy, cz }, s = { sx, sy, sz },")
    w("\t\thidden = hidden == true,")
    w("\t}")
    w("end")
    w("")
    sources, order, set_blocks, seen, counts = [], [], [], {}, []
    for key, stem, import_name in SETS:
        mpath = os.path.join(MANIFESTS, stem + ".manifest.json")
        if not os.path.isfile(mpath):
            print("skip %-10s no %s" % (key, os.path.relpath(mpath, REPO)))
            continue
        man = json.load(io.open(mpath, encoding="utf-8"))
        ids = man.get("assetIds", {}).get("model")
        if not ids or not ids.get("assetId"):
            print("skip %-10s %s has no assetIds.model.assetId (not uploaded yet)" % (key, stem))
            continue
        glb = os.path.join(exports, man["glb"])
        if not os.path.isfile(glb):
            sys.exit("%s is missing" % glb)
        digest = sha256(glb)
        if ids.get("sha256") and ids["sha256"] != digest:
            sys.exit("%s changed since it was uploaded as %s (sha256 %s, the ledger says %s). Upload nothing twice: "
                     "ask the lead." % (glb, ids.get("displayName"), digest, ids["sha256"]))
        bounds = glb_part_bounds(glb)
        blocks, nparts = [], 0
        assets = sorted(man["assets"], key=lambda a: a["origin"][0])
        for a in assets:
            if a["name"] in seen:
                sys.exit("asset name %s is in both %s and %s" % (a["name"], seen[a["name"]], key))
            seen[a["name"]] = key
            hidden = set(a.get("invisibleParts", []))
            plines = []
            for p in a["parts"]:
                if p["name"] not in bounds:
                    sys.exit("%s: part %s is not in %s" % (key, p["name"], man["glb"]))
                owner, lo, hi = bounds[p["name"]]
                if owner != a["name"]:
                    sys.exit("%s: part %s sits under %s in the GLB" % (key, p["name"], owner))
                c, s = (lo + hi) / 2, hi - lo
                args = [json.dumps(p["name"]), json.dumps(p["role"]), json.dumps(p["robloxMaterial"])]
                args += [num(int(x)) for x in p["rgb"]]
                args += [num(bool(p["collide"])), json.dumps(p["collision"]), num(bool(p["castShadow"])),
                         num(bool(p.get("canQuery", p["collide"]))), num(bool(p.get("canTouch", p["collide"]))),
                         num(int(p["tris"]))]
                args += [num(x) for x in c] + [num(x) for x in s]
                if p["name"] in hidden:
                    args.append("true")
                plines.append("\t\t\t\tP(" + ", ".join(args) + "),")
                nparts += 1
            att = a.get("attachments") or {}
            attl = ["\t\t\t\t%s = { pos = %s, look = %s, up = %s }," % (
                k if k.replace("_", "a").isalnum() else "[" + json.dumps(k) + "]",
                vec(v["position"]), vec(v["look"]), vec(v["up"])) for k, v in att.items()]
            b = ["\t\t{"]
            b.append("\t\t\tname = %s, kind = %s, tags = %s, tris = %d," % (
                json.dumps(a["name"]), json.dumps(a.get("kind", "")), lua(a.get("tags", [])), int(a.get("tris", 0))))
            b.append("\t\t\torigin = %s, bmin = %s, bmax = %s," % (vec(a["origin"]), vec(a["boundsMin"]), vec(a["boundsMax"])))
            if a.get("optional"):
                b.append("\t\t\toptional = true,")
            place = a.get("placement")
            if place and (any(abs(x) > 1e-9 for x in place.get("position", [0, 0, 0])) or abs(place.get("yawDegrees", 0)) > 1e-9):
                b.append("\t\t\tplacement = { %s, %s }," % (", ".join(num(x) for x in place["position"]), num(place.get("yawDegrees", 0))))
            if a.get("notes"):
                b.append("\t\t\tnotes = %s," % json.dumps(a["notes"], ensure_ascii=True))
            b.append("\t\t\tparts = {")
            b += plines
            b.append("\t\t\t},")
            if attl:
                b.append("\t\t\tatt = {")
                b += attl
                b.append("\t\t\t},")
            else:
                b.append("\t\t\tatt = {},")
            b.append("\t\t},")
            blocks.append("\n".join(b))
        if len(bounds) != nparts:
            sys.exit("%s: the manifest lists %d parts, the GLB holds %d meshes" % (key, nparts, len(bounds)))
        order.append(key)
        sources.append("\t%s = { key = %s, name = %s, import = %s, assetId = %d, glb = %s, bytes = %d, sha256 = %s, placeholder = %s }," % (
            key, json.dumps(key), json.dumps(ids["displayName"]), json.dumps(import_name), int(ids["assetId"]),
            json.dumps(man["glb"]), os.path.getsize(glb), json.dumps(digest), num(bool(man.get("placeholder")))))
        set_blocks.append("\t%s = {\n%s\n\t}," % (key, "\n".join(blocks)))
        counts.append((key, len(assets), nparts))
        print("set  %-10s %-24s asset %d  %d assets, %d parts" % (key, ids["displayName"], ids["assetId"], len(assets), nparts))
    w("-- The uploads (one Model asset per GLB; the ledger is the \"assetIds\" entry of each art manifest).")
    w("M.ORDER = %s" % lua(order))
    w("M.SOURCES = {")
    lines.extend(sources)
    w("}")
    w("")
    w("-- Every asset of every uploaded set, in the order they stand in the GLB's row (along +X).")
    w("M.SETS = {")
    lines.extend(set_blocks)
    w("}")
    w("")
    lpath = os.path.join(exports, "Map1_Layout.json")
    layout = json.load(io.open(lpath, encoding="utf-8"))
    w("-- Map1_Layout.json (sha256 %s): %s" % (sha256(lpath), layout.get("space", "")))
    w("-- items: { asset, x, y, z, yawDegrees, index = (0-based ring index), bearing = , stand = {x, y, z} }")
    w("M.LAYOUT = {")
    w("\tsha256 = %s," % json.dumps(sha256(lpath)))
    w("\titems = {")
    missing = {}
    for it in layout["items"]:
        extra = ""
        if "index" in it:
            extra += ", index = %d" % int(it["index"])
        if "bearing" in it:
            extra += ", bearing = %s" % num(it["bearing"])
        if "stand" in it:
            extra += ", stand = %s" % vec(it["stand"])
        if "colour" in it:
            extra += ", colour = %s" % json.dumps(it["colour"])
        w("\t\t{ %s, %s, %s%s }," % (json.dumps(it["asset"]), ", ".join(num(x) for x in it["position"]),
                                    num(it["yawDegrees"]), extra))
        if it["asset"] not in seen:
            missing[it["asset"]] = missing.get(it["asset"], 0) + 1
    w("\t},")
    heart = dict(layout["heart"])
    w("\theart = %s," % lua(heart, 1))
    w("}")
    w("")
    w("return M")
    text = "\n".join(lines) + "\n"
    data = text.encode("utf-8")
    if len(data) > 199000:
        sys.exit("the module would be %d bytes; a script Source is capped at 200,000 characters" % len(data))
    if missing:
        print("note: the layout places assets that no uploaded set holds yet: " +
              ", ".join("%s x%d" % kv for kv in sorted(missing.items())))
    if check:
        cur = io.open(OUT, "rb").read() if os.path.isfile(OUT) else b""
        same = cur == data
        print("check: %s" % ("up to date" if same else "DIFFERS from " + os.path.relpath(OUT, REPO)))
        return 0 if same else 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, "wb") as fh:
        fh.write(data)
    print("wrote %s (%d bytes): %s; %d layout items" % (
        os.path.relpath(OUT, REPO), len(data), ", ".join("%s %d/%d" % c for c in counts), len(layout["items"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
