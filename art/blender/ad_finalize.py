"""
ad_finalize.py - art-direction finishing step for the realistic sets (TreesReal, GroundReal, LandmarksReal,
BuildingsReal, PropsReal, ItemsReal). Standard library only: it runs inside Blender (every *_real.py generator calls
finalize() right after it writes its manifest) and with a plain Python:

    python art/blender/ad_finalize.py [<BlenderExports>]        # re-check every set + write RealSets.index.json

What it does to a manifest (the generator's own fields are kept; these are added or normalised):
  schema                 "LS-Real-1"
  glbs[]                 {file, bytes, sizeMB, assets[]} for every GLB of the set; every asset gets 'glb'
  textureFolder          textures/<folder> relative to BlenderExports (BuildingsReal and PropsReal share one)
  uploadTextures[]       every PNG a SurfaceAppearance needs: {file, kind, size, channels, bytes, usedBy[]}
                         - upload each once and reuse the id; glb_only/ files are never uploaded
  parts[].surfaceAppearance   one shape for every set:
                         {colorMap, normalMap, roughnessMap, metalnessMap|null, alphaMode, color[r,g,b]}
                         paths relative to BlenderExports; null for Neon embers and invisible colliders
  parts[].transparency, doubleSided (always false), backFacesInMesh, canQuery, canTouch, castShadow, neon
  adCheck                the checks below, with every problem listed (a clean set has adCheck.problems == [])

Checks (Roblox import constraints):
  - every GLB <= 20,000,000 bytes (Roblox upload limit; noted above 19 MB), no mesh over 20,000 triangles
  - TANGENT, NORMAL and TEXCOORD_0 on every primitive; no doubleSided material
  - every image (embedded or uploaded) is a power-of-two PNG of at most 1024 x 1024
  - at most 16 upload images per texture folder; roughness / metalness maps are 8-bit grayscale PNGs
  - every map a part references exists
  - set contracts: SpirePlatform Plate_1..24 at r = 52 every 15 degrees clockwise from north (-Z), Plinth asset tag,
    Climbable oak wood, the ladder / bridge / item attachments the game uses
"""
import json
import math
import os
import shutil
import struct
import sys

SCHEMA = "LS-Real-1"
MAX_GLB_BYTES = 20_000_000          # Roblox upload limit (20 MB); > 19 MB is reported as a note
MAX_TRIS = 20000
MAX_PX = 1024
MAX_UPLOADS = 16
FOLDER = {"TreesReal": "TreesReal", "GroundReal": "GroundReal", "LandmarksReal": "LandmarksReal",
          "BuildingsReal": "BuildingsReal", "PropsReal": "BuildingsReal", "ItemsReal": "ItemsReal"}
SETS = ["TreesReal", "GroundReal", "LandmarksReal", "BuildingsReal", "PropsReal", "ItemsReal"]
REPO_MANIFESTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "manifests"))
DEFAULT_OUT = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents", "LastStanding", "BlenderExports")

# attachments / tags the game code relies on (checked when the asset is present)
REQUIRED_ATTACH = {
    "OakA": ["Perch1", "Perch2", "Perch3", "Perch4"],
    "SpirePlatform": ["Plate_%d" % i for i in range(1, 25)],
    "Spire": ["Beacon", "CrateSlot_1", "CrateSlot_2", "CrateSlot_3", "CrateSlot_4"],
    "Plinth": ["Stand"],
    "Brazier": ["Fire"],
    "Bench": ["Seat_1", "Seat_2"],
    "NoticeBoard": ["Board"],
    "HunterCabin": ["Door", "LadderBase", "LadderTop", "Hearth"],
    "Watchtower": ["LadderBase", "LadderTop"],
    "Footbridge": ["EndA", "EndB"],
    "Campfire": ["FireCenter"],
    "Lantern": ["Glow", "HangPoint"],
    "Sign": ["SignFace"],
    "LogBench": ["Seat_1", "Seat_2"],
    "CaveMouth": ["CaveEntrance"],
    "bow": ["Grip", "Nock", "StringTop", "StringBottom", "ArrowRest"],
    "arrow": ["Nock", "Tip"],
    "sword": ["Grip", "Tip"],
    "SupplyCrate1": ["LidHinge", "Prompt", "LootPoint"],
    "SupplyCrate2": ["LidHinge", "Prompt", "LootPoint"],
    "SupplyCrate3": ["LidHinge", "Prompt", "LootPoint"],
}


# ------------------------------------------------------------------------------------------------ file helpers
def png_info(path):
    """(width, height, bit depth, channels name) from the IHDR chunk, or None."""
    with open(path, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
    return w, h, bd, {0: "gray", 2: "RGB", 3: "palette", 4: "gray+alpha", 6: "RGBA"}.get(ct, str(ct))


def pow2(n):
    return n > 0 and (n & (n - 1)) == 0


def glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    clen, ctype = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    binc = data[20 + clen + 8:] if len(data) > 20 + clen else b""
    return js, binc, len(data)


def glb_report(path):
    """Everything the importer cares about, read from the GLB itself."""
    js, binc, nbytes = glb_json(path)
    acc = js.get("accessors", [])
    out = {"file": os.path.basename(path), "bytes": nbytes, "sizeMB": round(nbytes / 1e6, 2), "problems": []}
    prims = 0
    worst = 0
    for m in js.get("meshes", []):
        tris = 0
        for p in m.get("primitives", []):
            prims += 1
            a = p.get("attributes", {})
            for need in ("TANGENT", "NORMAL", "TEXCOORD_0"):
                if need not in a:
                    out["problems"].append("%s: primitive of %s lacks %s" % (out["file"], m.get("name"), need))
            cnt = acc[p["indices"]]["count"] if "indices" in p else acc[a["POSITION"]]["count"]
            tris += cnt // 3
        worst = max(worst, tris)
        if tris > MAX_TRIS:
            out["problems"].append("%s: mesh %s has %d triangles (> %d)" % (out["file"], m.get("name"), tris, MAX_TRIS))
    for mat in js.get("materials", []):
        if mat.get("doubleSided"):
            out["problems"].append("%s: material %s is doubleSided" % (out["file"], mat.get("name")))
    imgs = []
    for im in js.get("images", []):
        if "bufferView" not in im:
            continue
        bv = js["bufferViews"][im["bufferView"]]
        off = bv.get("byteOffset", 0)
        head = binc[off:off + 33]
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", head[16:24])
            imgs.append({"name": im.get("name"), "size": [w, h], "bytes": bv["byteLength"]})
            if w > MAX_PX or h > MAX_PX or not (pow2(w) and pow2(h)):
                out["problems"].append("%s: embedded image %s is %dx%d" % (out["file"], im.get("name"), w, h))
    if nbytes > MAX_GLB_BYTES:
        out["problems"].append("%s is %.2f MB (Roblox upload limit 20 MB: split it)" % (out["file"], nbytes / 1e6))
    elif nbytes > 19_000_000:
        out["note"] = "%s is %.2f MB: under the 20 MB limit but close to it" % (out["file"], nbytes / 1e6)
    out.update({"primitives": prims, "maxMeshTris": worst, "embeddedImages": imgs,
                "materials": len(js.get("materials", [])),
                "alphaMask": sorted(m.get("name") for m in js.get("materials", []) if m.get("alphaMode") == "MASK"),
                "alphaBlend": sorted(m.get("name") for m in js.get("materials", []) if m.get("alphaMode") == "BLEND")})
    return out


# ------------------------------------------------------------------------------------------------ normalising
def _rel(folder, v):
    if not v:
        return None
    v = v.replace("\\", "/")
    if v.startswith("textures/"):
        return v
    return "textures/%s/%s" % (folder, v)


def _surface_from_buildings(p, folder):
    s = p.get("surface") or {}
    if not s.get("colorMap"):
        return None
    return {"colorMap": _rel(folder, s.get("colorMap")), "normalMap": _rel(folder, s.get("normalMap")),
            "roughnessMap": _rel(folder, s.get("roughnessMap")), "metalnessMap": _rel(folder, s.get("metalnessMap")),
            "alphaMode": s.get("alphaMode") or "Overlay", "color": [255, 255, 255]}


def normalise_part(p, set_name, folder):
    role = p.get("role", "")
    neon = role == "Ember" or p.get("robloxMaterial") == "Neon"
    collider = role == "Collider"
    if set_name in ("BuildingsReal", "PropsReal"):
        sa = _surface_from_buildings(p, folder)
        s = p.get("surface") or {}
        p.setdefault("transparency", s.get("meshTransparency", 0))
        p.setdefault("doubleSided", bool(s.get("doubleSided", False)))
    else:
        sa = p.get("surfaceAppearance")
        if sa:
            sa = dict(sa)
            for k in ("colorMap", "normalMap", "roughnessMap", "metalnessMap"):
                sa[k] = _rel(folder, sa.get(k))
            sa["alphaMode"] = sa.get("alphaMode") or "Overlay"
            sa["color"] = sa.get("color") or [255, 255, 255]
    if neon or collider:
        sa = None
    if sa:
        sa = {k: sa.get(k) for k in ("colorMap", "normalMap", "roughnessMap", "metalnessMap", "alphaMode", "color")}
    p["surfaceAppearance"] = sa
    p["neon"] = bool(neon)
    p.setdefault("transparency", 1.0 if collider else 0)
    p["doubleSided"] = False
    p.setdefault("backFacesInMesh", False)
    p.setdefault("canQuery", bool(p.get("collide")))
    p.setdefault("canTouch", bool(p.get("collide")))
    p.setdefault("castShadow", True)
    p.setdefault("tags", [])
    return p


def _glb_list(m, set_name):
    if isinstance(m.get("glbs"), list) and m["glbs"]:
        files = [g["file"] if isinstance(g, dict) else g for g in m["glbs"]]
    elif m.get("glb"):
        files = [m["glb"]]
    else:
        files = [set_name + ".glb"]
    return files


def finalize(set_name, out_dir=None, log=print, repo_dir=REPO_MANIFESTS, dry=False):
    out_dir = out_dir or DEFAULT_OUT
    mpath = os.path.join(out_dir, set_name + ".manifest.json")
    with open(mpath, encoding="utf-8") as f:
        m = json.load(f)
    folder = FOLDER[set_name]
    tex_folder = "textures/" + folder
    problems = []
    # --- GLBs
    files = _glb_list(m, set_name)
    glbs = []
    for fn in files:
        gp = os.path.join(out_dir, fn)
        if not os.path.exists(gp):
            problems.append("missing GLB " + fn)
            continue
        rep = glb_report(gp)
        problems += rep["problems"]
        members = [a["name"] for a in m["assets"] if a.get("glb", files[0] if len(files) == 1 else None) == fn]
        glbs.append({"file": fn, "bytes": rep["bytes"], "sizeMB": rep["sizeMB"], "assets": members,
                     "primitives": rep["primitives"], "maxMeshTris": rep["maxMeshTris"],
                     "embeddedImages": [i["name"] for i in rep["embeddedImages"]],
                     "alphaMask": rep["alphaMask"], "alphaBlend": rep["alphaBlend"]})
    if len(files) == 1:
        for a in m["assets"]:
            a["glb"] = files[0]
    # --- parts
    used = {}
    for a in m["assets"]:
        for p in a["parts"]:
            normalise_part(p, set_name, folder)
            sa = p["surfaceAppearance"]
            if not sa:
                continue
            for key, kind in (("colorMap", "color"), ("normalMap", "normal"), ("roughnessMap", "roughness"),
                              ("metalnessMap", "metalness")):
                rel = sa.get(key)
                if not rel:
                    continue
                d = used.setdefault(rel, {"file": rel, "kind": kind, "usedBy": []})
                if a["name"] not in d["usedBy"]:
                    d["usedBy"].append(a["name"])
            if sa["alphaMode"] not in ("Overlay", "Transparency"):
                problems.append("%s: alphaMode %s" % (p["name"], sa["alphaMode"]))
    uploads = []
    for rel, d in sorted(used.items()):
        path = os.path.join(out_dir, *rel.split("/"))
        if not os.path.exists(path):
            problems.append("missing texture " + rel)
            continue
        info = png_info(path)
        if info is None:
            problems.append("not a PNG: " + rel)
            continue
        w, h, bd, ch = info
        d.update({"size": [w, h], "bitDepth": bd, "channels": ch, "bytes": os.path.getsize(path)})
        if w > MAX_PX or h > MAX_PX or not (pow2(w) and pow2(h)):
            problems.append("%s is %dx%d (Roblox: power of two, at most %d)" % (rel, w, h, MAX_PX))
        if d["kind"] in ("roughness", "metalness") and ch != "gray":
            problems.append("%s should be an 8-bit grayscale PNG (is %s)" % (rel, ch))
        if d["kind"] == "normal" and ch not in ("RGB", "RGBA"):
            problems.append("%s: normal map is %s" % (rel, ch))
        uploads.append(d)
    if len(uploads) > MAX_UPLOADS:
        problems.append("%d upload images (budget %d)" % (len(uploads), MAX_UPLOADS))
    # stray files in the upload folder (anything that is not referenced and not in glb_only/)
    tdir = os.path.join(out_dir, "textures", folder)
    if os.path.isdir(tdir) and set_name != "PropsReal":
        stray = sorted(fn for fn in os.listdir(tdir) if fn.lower().endswith(".png")
                       and (tex_folder + "/" + fn) not in used)
        if set_name == "BuildingsReal":          # PropsReal shares the folder
            pm = os.path.join(out_dir, "PropsReal.manifest.json")
            if os.path.exists(pm):
                with open(pm, encoding="utf-8") as f:
                    pj = json.load(f)
                pu = {x["file"] for x in pj.get("uploadTextures", [])}
                stray = [fn for fn in stray if (tex_folder + "/" + fn) not in pu]
        if stray:
            problems.append("unreferenced PNGs in the upload folder %s: %s" % (tex_folder, stray))
    glb_only = []
    gdir = os.path.join(tdir, "glb_only")
    if os.path.isdir(gdir):
        glb_only = sorted(tex_folder + "/glb_only/" + fn for fn in os.listdir(gdir) if fn.lower().endswith(".png"))
    # --- contracts
    by = {a["name"]: a for a in m["assets"]}
    for an, names in REQUIRED_ATTACH.items():
        if an in by:
            miss = [n for n in names if n not in (by[an].get("attachments") or {})]
            if miss:
                problems.append("%s lacks attachments %s" % (an, miss))
    if "SpirePlatform" in by:
        att = by["SpirePlatform"].get("attachments") or {}
        for i in range(24):
            a = att.get("Plate_%d" % (i + 1))
            if not a:
                continue
            ang = math.radians(15 * i)
            want = (52 * math.sin(ang), -52 * math.cos(ang))          # Roblox: north = -Z, clockwise from above
            got = (a["position"][0], a["position"][2])
            if math.hypot(want[0] - got[0], want[1] - got[1]) > 0.05:
                problems.append("SpirePlatform Plate_%d at %s, expected %s" % (i + 1, got, want))
    if "Plinth" in by and "Plinth" not in by["Plinth"].get("tags", []):
        problems.append("Plinth asset lacks the Plinth tag")
    if "OakA" in by:
        if not any("Climbable" in p.get("tags", []) for p in by["OakA"]["parts"]):
            problems.append("OakA has no Climbable part")
    # --- write
    m["schema"] = SCHEMA
    m["glbs"] = glbs
    m["textureFolder"] = tex_folder
    m["uploadTextures"] = uploads
    m["glbOnlyTextures"] = glb_only
    if set_name == "PropsReal":
        m["sharesTexturesWith"] = "BuildingsReal"
    m["adCheck"] = {"problems": problems, "glbs": len(glbs), "uploadImages": len(uploads),
                    "totalTris": sum(a.get("tris", 0) for a in m["assets"]), "assets": len(m["assets"])}
    if dry:
        repo_dir = None
    else:
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump(m, f, indent=1)
    if repo_dir and os.path.isdir(repo_dir):
        shutil.copyfile(mpath, os.path.join(repo_dir, os.path.basename(mpath)))
    log("ADCHECK %s: %d GLB(s) %s, %d upload images, %d assets, %d problems" % (
        set_name, len(glbs), ", ".join("%s %.2f MB" % (g["file"], g["sizeMB"]) for g in glbs), len(uploads),
        len(m["assets"]), len(problems)))
    for pr in problems:
        log("ADCHECK PROBLEM " + pr)
    return m


def write_index(out_dir, manifests):
    idx = {"schema": SCHEMA, "sets": [], "notes": [
        "Upload each PNG listed in a set's uploadTextures once (BuildingsReal and PropsReal share "
        "textures/BuildingsReal) and reuse the asset id in every SurfaceAppearance that names it.",
        "Never upload textures/*/glb_only/*: those are the glTF metallicRoughness copies embedded in the GLBs.",
        "Import every GLB in sets[].glbs; re-centre each asset on its manifest 'origin'."]}
    for name, m in manifests.items():
        idx["sets"].append({"set": name, "manifest": name + ".manifest.json", "glbs": m["glbs"],
                            "textureFolder": m["textureFolder"], "uploadImages": len(m["uploadTextures"]),
                            "assets": [a["name"] for a in m["assets"]], "totalTris": m["adCheck"]["totalTris"],
                            "problems": m["adCheck"]["problems"]})
    path = os.path.join(out_dir, "RealSets.index.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(idx, f, indent=1)
    return path


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    done = {}
    for s in SETS:
        if os.path.exists(os.path.join(out, s + ".manifest.json")):
            done[s] = finalize(s, out)
    print("INDEX " + write_index(out, done))
