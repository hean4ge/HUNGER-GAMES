"""
ir_verify.py - checks the exported ItemsReal set against the v1 Items contract and the realism-pass rules.
Plain Python 3 (no Blender, no numpy):

    python ir_verify.py <BlenderExports folder> [<repo art/manifests folder>]

Checks: same asset names as v1; every v1 attachment present with the same position / look / up (tolerance 0.002);
the part names the game relies on (<Crate>_Lid, Lid-tagged fittings, SupplyCrate3_Ember, bow_Rope, bottle Glass /
WaterFill); triangle budgets (items/crates <= 2,500, parts <= 20,000); textures: <= 16 PNGs, power of two, <= 1024,
roughness / metalness 8-bit grayscale, colour RGB(A); every GLB primitive has NORMAL, TANGENT and TEXCOORD_0.
"""
import json
import os
import struct
import sys

TOL = 0.002


def png_info(path):
    with open(path, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: " + path)
    w, h, depth, ctype = struct.unpack(">IIBB", head[16:26])
    return w, h, depth, {0: "gray", 2: "rgb", 3: "palette", 4: "gray+alpha", 6: "rgba"}.get(ctype, str(ctype))


def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    assert ctype == b"JSON"
    return json.loads(data[20:20 + clen].decode("utf-8"))


def close(a, b):
    return all(abs(x - y) <= TOL for x, y in zip(a, b))


def main():
    out = sys.argv[1]
    v1_dir = sys.argv[2] if len(sys.argv) > 2 else out
    real = json.load(open(os.path.join(out, "ItemsReal.manifest.json"), encoding="utf-8"))
    v1p = os.path.join(v1_dir, "Items.manifest.json")
    if not os.path.exists(v1p):
        v1p = os.path.join(out, "Items.manifest.json")
    v1 = json.load(open(v1p, encoding="utf-8"))
    problems, lines = [], []
    rv = {a["name"]: a for a in real["assets"]}
    vv = {a["name"]: a for a in v1["assets"]}
    if set(rv) != set(vv):
        problems.append("asset names differ: missing %s, extra %s" % (sorted(set(vv) - set(rv)), sorted(set(rv) - set(vv))))
    for nm, a1 in vv.items():
        a2 = rv.get(nm)
        if a2 is None:
            continue
        for an, at1 in a1["attachments"].items():
            at2 = a2["attachments"].get(an)
            if at2 is None:
                problems.append("%s: attachment %s missing" % (nm, an))
                continue
            for k in ("position", "look", "up"):
                if not close(at1[k], at2[k]):
                    problems.append("%s.%s %s v1 %s -> %s" % (nm, an, k, at1[k], at2[k]))
        extra = set(a2["attachments"]) - set(a1["attachments"])
        if extra:
            lines.append("NOTE %s has extra attachments %s" % (nm, sorted(extra)))
        budget = 2500
        if a2["tris"] > budget:
            problems.append("%s: %d tris > %d" % (nm, a2["tris"], budget))
        for p in a2["parts"]:
            if p["tris"] > 20000:
                problems.append("%s: part %s %d tris > 20000" % (nm, p["name"], p["tris"]))
        names = {p["name"] for p in a2["parts"]}
        if a1["kind"] == "Crate":
            if nm + "_Lid" not in names:
                problems.append(nm + ": no <Crate>_Lid part")
            v1_lid = {p["name"] for p in a1["parts"] if "Lid" in p.get("tags", [])}
            r_lid = {p["name"] for p in a2["parts"] if "Lid" in p.get("tags", [])}
            if v1_lid != r_lid:
                problems.append("%s: Lid-tagged parts v1 %s vs %s" % (nm, sorted(v1_lid), sorted(r_lid)))
        lines.append("%-15s tris %5d (v1 %5d)  parts %d (v1 %d)  size %s (v1 %s)" % (
            nm, a2["tris"], a1["tris"], len(a2["parts"]), len(a1["parts"]), a2["size"], a1["size"]))
    for must in ("SupplyCrate3_Ember", "bow_Rope", "water_bottle_Glass", "water_bottle_WaterFill", "empty_bottle_Glass"):
        owner = must.rsplit("_", 1)[0] if not must.startswith("SupplyCrate3") else "SupplyCrate3"
        owner = {"water_bottle_WaterFill": "water_bottle"}.get(must, owner)
        if owner in rv and must not in {p["name"] for p in rv[owner]["parts"]}:
            problems.append("part %s missing" % must)
    # textures
    tex = real.get("textures", {})
    folder = os.path.join(out, real.get("textureFolder", "textures/ItemsReal"))
    if len(tex) > 16:
        problems.append("%d textures > 16" % len(tex))
    for fn, info in sorted(tex.items()):
        w, h, depth, ctype = png_info(os.path.join(folder, fn))
        ok_size = w == h and w <= 1024 and (w & (w - 1)) == 0
        want = {"roughness": ("gray",), "metalness": ("gray",), "normal": ("rgb",), "color": ("rgb", "rgba")}[info["kind"]]
        if not ok_size or depth != 8 or ctype not in want:
            problems.append("%s: %dx%d %d-bit %s (want %s, square power of two <= 1024)" % (fn, w, h, depth, ctype, want))
        lines.append("TEX %-26s %4dx%-4d %d-bit %-5s %7.0f KB" % (fn, w, h, depth, ctype,
                                                                os.path.getsize(os.path.join(folder, fn)) / 1024.0))
    # GLB
    js = glb_json(os.path.join(out, real["glb"]))
    prims = [(m.get("name"), p) for m in js.get("meshes", []) for p in m["primitives"]]
    for nm, p in prims:
        for attr in ("NORMAL", "TANGENT", "TEXCOORD_0"):
            if attr not in p["attributes"]:
                problems.append("GLB %s: no %s" % (nm, attr))
    lines.append("GLB %d primitives, %d embedded images, %.2f MB" % (
        len(prims), len(js.get("images", [])), os.path.getsize(os.path.join(out, real["glb"])) / 1048576.0))
    for l in lines:
        print(l)
    print("PROBLEMS: %d" % len(problems))
    for p in problems:
        print("  - " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
