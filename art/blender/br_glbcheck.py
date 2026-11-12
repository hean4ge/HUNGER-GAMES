"""
br_glbcheck.py - inspect an exported GLB (plain Python, no bpy): every mesh primitive's vertex attributes
(TANGENT / NORMAL / TEXCOORD_0 must all be present for SurfaceAppearance normal maps), materials (textures,
alphaMode, double-sided) and embedded images with their byte sizes.

    python br_glbcheck.py <file.glb> [more.glb ...]

Exit code 1 if any primitive lacks TANGENT, NORMAL or TEXCOORD_0, or a GLB is 19 MB or larger.
"""
import json
import struct
import sys


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a GLB: " + path)
    off = 12
    doc, binary = None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binary = chunk
        off += 8 + clen
    return doc, binary, len(data)


def check(path):
    doc, binary, size = read_glb(path)
    ok = True
    print("GLB %s  %.2f MB  (binary chunk %.2f MB)" % (path, size / 1048576.0, len(binary) / 1048576.0))
    views = doc.get("bufferViews", [])
    img_bytes = 0
    for i, im in enumerate(doc.get("images", [])):
        n = views[im["bufferView"]]["byteLength"] if "bufferView" in im else 0
        img_bytes += n
        print("  image %2d %-28s %-10s %7.0f KB" % (i, im.get("name", "?"), im.get("mimeType", "?"), n / 1024.0))
    print("  images total %.2f MB, geometry + other %.2f MB" % (img_bytes / 1048576.0,
                                                               (len(binary) - img_bytes) / 1048576.0))
    texs = doc.get("textures", [])
    for i, m in enumerate(doc.get("materials", [])):
        pbr = m.get("pbrMetallicRoughness", {})

        def tex(t):
            if t is None:
                return "-"
            src = texs[t["index"]].get("source")
            return doc["images"][src].get("name", str(src)) if src is not None else "?"
        print("  material %-22s base=%s normal=%s mr=%s alpha=%s doubleSided=%s" % (
            m.get("name"), tex(pbr.get("baseColorTexture")), tex(m.get("normalTexture")),
            tex(pbr.get("metallicRoughnessTexture")), m.get("alphaMode", "OPAQUE"), m.get("doubleSided", False)))
    n_prim = n_tan = 0
    missing = []
    for me in doc.get("meshes", []):
        for p in me.get("primitives", []):
            n_prim += 1
            attrs = p.get("attributes", {})
            if "TANGENT" in attrs:
                n_tan += 1
            need = [a for a in ("TANGENT", "NORMAL", "TEXCOORD_0") if a not in attrs]
            if need:
                missing.append((me.get("name"), need))
    print("  meshes %d, primitives %d, with TANGENT %d" % (len(doc.get("meshes", [])), n_prim, n_tan))
    for (name, need) in missing:
        ok = False
        print("  MISSING %s on %s" % (",".join(need), name))
    if size >= 19 * 1048576:
        ok = False
        print("  TOO LARGE: %.2f MB (Roblox upload limit 20 MB per file)" % (size / 1048576.0))
    print("  RESULT " + ("OK" if ok else "FAIL"))
    return ok


if __name__ == "__main__":
    good = all([check(p) for p in sys.argv[1:]])
    sys.exit(0 if good else 1)
