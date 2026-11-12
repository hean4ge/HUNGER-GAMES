"""
gr_export.py - GroundReal asset library: parts with texture sets, validation, GLB export, manifest.

Follows the ls_common / ls_patch conventions (art/README.md): 1 unit = 1 stud, Blender Z-up -> Y-up GLB, asset front
= Blender +Y = Roblox LookVector (-Z), root empty named <Asset> with MeshParts <Asset>_<Role>[_n], assets laid out in
a row along X with each 'origin' recorded, per-axis ordered boundsMin/boundsMax, canQuery/canTouch = collide and Box
fidelity for non-colliders, manifest copied into art/manifests/.

Extension for textured parts (one SurfaceAppearance per MeshPart):
  part.textureSet            name of the texture set (see manifest.textureSets)
  part.surfaceAppearance     {colorMap, normalMap, roughnessMap, metalnessMap (null), alphaMode}
                             paths relative to the BlenderExports folder (textures/GroundReal/<file>.png)
  part.transparency          MeshPart.Transparency (0: cut-out with depth, see Roblox docs for AlphaMode)
  part.doubleSided           MeshPart.DoubleSided (false everywhere: cards carry real flipped back faces)
  part.backFacesInMesh       true when the mesh already contains the flipped back faces
  part.renderFidelity        suggested MeshPart.RenderFidelity
The GLBs carry geometry, UVs, normals and MikkTSpace tangents (export_tangents=True: Roblox needs tangents on
imported meshes or normal maps show no effect) and, since the 2026-11-11 art-direction pass, the textures as well
(baseColorTexture with cut-out alpha on the card atlases = alphaMode MASK, normalTexture, and a packed glTF
metallicRoughnessTexture from textures/GroundReal/glb_only/*_MR.png: R = G = roughness, B = 0, metallicFactor patched
to 0), so Roblox's importer can build the SurfaceAppearances itself. The set is split into three GLBs
(GroundReal_Flora / _Rocks / _Cliffs, see GLB_GROUPS) so each stays well under the 20 MB upload limit with its images
embedded; one manifest covers all three (asset 'glb' says which file holds it). After export each GLB's JSON chunk
is parsed and every primitive is checked for POSITION, NORMAL, TANGENT and TEXCOORD_0 (manifest.glbCheck).
"""
import json
import math
import os
import shutil
import struct

import bpy
import numpy as np
from mathutils import Matrix, Vector

import tex_ground as tg

REPO_MANIFESTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "manifests"))
TEX_REL = "textures/GroundReal"
TRIANGLE_LIMIT = 20000

# role -> Roblox material (physics, footsteps, fallback look when a SurfaceAppearance is not loaded)
ROLE_MATERIAL = {
    "Fern": "LeafyGrass", "Grass": "Grass", "Reed": "Grass", "Flower": "Grass", "Leaves": "LeafyGrass",
    "Berries": "SmoothPlastic", "Mushroom": "Ground", "Moss": "Grass", "Trunk": "Wood", "Rock": "Rock",
    "Stone": "Rock", "Pebbles": "Rock",
}


IMPORT_NOTES = [
    "Geometry: import GroundReal_Flora.glb, GroundReal_Rocks.glb and GroundReal_Cliffs.glb (3D Importer / Open "
    "Cloud); each asset's 'glb' names its file. Each asset root arrives as a Model of MeshParts named "
    "<Asset>_<Role>[_n]; re-centre with the asset 'origin' (WorldPivot = CFrame.new(origin), then PivotTo) like the "
    "other categories. The GLBs carry tangents (MikkTSpace) and embedded textures (glb_only/*_MR.png is the packed "
    "glTF roughness; never upload it separately).",
    "Surfaces: give every part ONE SurfaceAppearance from its 'surfaceAppearance' block: ColorMap / NormalMap / "
    "RoughnessMap = the uploaded image ids of those PNGs (upload each file in 'textures' once and share the ids so "
    "copies instance), MetalnessMap empty, AlphaMode as given, Color = 'color' (white: the maps are final albedo). "
    "Roughness PNGs are 8-bit grayscale; normal maps are OpenGL (+Y), tangent space. Clear any importer TextureID.",
    "Cards (backFacesInMesh = true) already contain flipped back faces: keep MeshPart.DoubleSided = false and "
    "MeshPart.Transparency = 0 so AlphaMode Transparency is a depth-correct alpha cut-out.",
    "Per part: CanCollide = collide, CollisionFidelity = collision (edit time only), CastShadow = castShadow, "
    "CanQuery = canQuery, CanTouch = canTouch, Anchored = true, Material = robloxMaterial (physics and footstep "
    "sounds only), Color = rgb (fallback when the SurfaceAppearance is not loaded).",
    "BerryBush_Berries is a separate part: hide it when the bush is picked (Transparency 1 or parent it away).",
    "Rocks and cliffs continue below y = 0 (buriedDepth) so they sit into terrain on slopes; plant cards sink at most "
    "0.07. Place each asset's pivot on the terrain surface.",
    "CliffFace* / CaveMouth use the tiling GR_Granite set: their UVs run outside 0..1 on purpose (the texture repeats "
    "every tileStuds studs). Check in Studio that the SurfaceAppearance repeats on these MeshParts.",
]
PLANT_ROLES = {"Fern", "Grass", "Reed", "Flower", "Leaves", "Berries", "Mushroom"}
# one manifest, three GLBs (each embeds only the images its assets use; every one stays well under 20 MB)
GLB_GROUPS = {
    "GroundReal_Flora": ["FernA", "FernB", "BushA", "BushB", "BerryBush", "GrassTallA", "GrassTallB", "GrassForest",
                         "ReedsA", "FlowersA", "FlowersB", "MushroomsA", "SaplingBroadleaf", "MossPatch"],
    "GroundReal_Rocks": ["BoulderA", "BoulderB", "BoulderC", "BoulderD", "RockFlat", "RiverStones"],
    "GroundReal_Cliffs": ["CliffFaceA", "CliffFaceB", "CliffFaceC", "RockOutcrop", "CaveMouth", "ScreeA"],
}
MR_SIZE = 512             # packed glTF metallicRoughness (glb_only) resolution
PLANT_SINK = 0.07          # plant cards may reach this far below z = 0 (blades emerge from the soil on slopes)


def to_roblox(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def clamp_below(obj, zmin):
    """Flatten any vertex below zmin onto zmin (card bottoms that bent into the ground)."""
    co = tg.vertex_coords(obj.data)
    low = co[:, 2] < zmin
    if low.any():
        co[low, 2] = zmin
        obj.data.vertices.foreach_set("co", co.astype(np.float32).ravel())
        obj.data.update()
    return int(low.sum())


def glb_check(path):
    """Parse a GLB's JSON chunk: per mesh, the attribute sets of its primitives. Returns (report, problems)."""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        return {}, ["not a GLB"]
    clen, ctype = struct.unpack("<I4s", data[12:20])
    js = json.loads(data[20:20 + clen].decode("utf-8"))
    report, problems = {}, []
    need = ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0")
    for m in js.get("meshes", []):
        attrs = set()
        for prim in m.get("primitives", []):
            a = set(prim.get("attributes", {}).keys())
            attrs |= a
            miss = [k for k in need if k not in a]
            if miss:
                problems.append("%s primitive lacks %s" % (m.get("name"), ",".join(miss)))
        report[m.get("name")] = sorted(attrs)
    return {"meshes": len(js.get("meshes", [])), "images": len(js.get("images", [])),
            "attributesPerMesh": report}, problems


def _glb_split(data):
    magic, ver, length = struct.unpack("<III", data[:12])
    clen, ctype = struct.unpack("<II", data[12:20])
    return ver, json.loads(data[20:20 + clen].decode("utf-8")), data[20 + clen:]


def glb_set_metallic_zero(path):
    """metallicFactor = 0 on every material (nothing in this set is metal; the packed MR image's B channel is 0)."""
    with open(path, "rb") as f:
        data = f.read()
    ver, js, rest = _glb_split(data)
    n = 0
    for m in js.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if pbr.get("metallicFactor", 1.0) != 0:
            pbr["metallicFactor"] = 0
            n += 1
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, ver, 12 + len(body)) + body)
    return n


def glb_materials(path):
    with open(path, "rb") as f:
        _v, js, _r = _glb_split(f.read())
    return js.get("materials", []), js.get("images", [])


class GroundLib:
    def __init__(self, category, texture_sets):
        """texture_sets: {set_name: {"color": file, "normal": file, "rough": file, "alpha": bool, "avg": rgb}}"""
        self.category = category
        self.sets = texture_sets
        self.assets = []
        self.warnings = []
        self.notes = []
        self._mats = {}
        self._mr_written = set()
        self.tex_dir = None           # textures/GroundReal (set by the driver before any part is added)

    # ------------------------------------------------------------------ assets
    def begin(self, name, kind, tags=None, notes="", budget=None):
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        bpy.context.scene.collection.objects.link(root)
        e = {"name": name, "kind": kind, "tags": list(tags or []), "notes": notes, "root": root, "parts": [],
             "attachments": {}, "budget": budget}
        self.assets.append(e)
        return root

    def _entry(self, root):
        for e in self.assets:
            if e["root"] is root:
                return e
        raise ValueError("unknown root")

    def _mr_file(self, set_name):
        """glb_only/<rough>_MR.png: R = G = roughness, B = 0 (glTF metallicRoughness packing, embedded only)."""
        rough = self.sets[set_name]["rough"]
        mr = rough.replace("_Rough.png", "_MR.png").replace("_Roughness.png", "_MR.png")
        out = os.path.join(self.tex_dir, "glb_only", mr)
        if out not in self._mr_written:
            src = bpy.data.images.load(os.path.join(self.tex_dir, rough), check_existing=False)
            src.colorspace_settings.name = "Non-Color"
            r = tg.image_to_np(src)[..., 0].astype(np.float64)
            bpy.data.images.remove(src)
            while r.shape[0] > MR_SIZE:
                r = 0.25 * (r[0::2, 0::2] + r[1::2, 0::2] + r[0::2, 1::2] + r[1::2, 1::2])
            tg.write_png(out, np.stack([r, r, np.zeros_like(r)], axis=2))
            self._mr_written.add(out)
        return out

    def material(self, set_name):
        """Textured glTF material (embedded on export): base colour (+ cut-out alpha on the card atlases -> alphaMode
        MASK), OpenGL normal map, packed metallicRoughness from glb_only/*_MR.png (B = 0, metallicFactor patched to
        0). Single-sided (glTF doubleSided = false; cards carry real flipped back faces)."""
        m = self._mats.get(set_name)
        if m is None:
            s = self.sets[set_name]
            m = bpy.data.materials.new("GR_" + set_name)
            m.use_nodes = True
            nt = m.node_tree
            bsdf = nt.nodes.get("Principled BSDF")
            avg = s.get("avg", (128, 128, 128))
            lin = [float(tg.srgb_to_lin(c / 255.0)) for c in avg]

            def img(path, cs):
                im = bpy.data.images.load(path, check_existing=True)
                im.colorspace_settings.name = cs
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = im
                return n
            tc = img(os.path.join(self.tex_dir, s["color"]), "sRGB")
            nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
            if s.get("alphaMode") == "Transparency":
                rnd = nt.nodes.new("ShaderNodeMath")
                rnd.operation = "ROUND"
                nt.links.new(tc.outputs["Alpha"], rnd.inputs[0])
                nt.links.new(rnd.outputs[0], bsdf.inputs["Alpha"])
                m.surface_render_method = "DITHERED"
            tn = img(os.path.join(self.tex_dir, s["normal"]), "Non-Color")
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.space = "TANGENT"
            nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
            tr = img(self._mr_file(set_name), "Non-Color")
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(tr.outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])     # 0: keeps the exporter's pass-through
            m.diffuse_color = (lin[0], lin[1], lin[2], 1.0)
            m.use_backface_culling = True          # glTF doubleSided = false (back faces are real geometry)
            self._mats[set_name] = m
        return m

    def add(self, root, obj, role, set_name, collide=False, collision="Box", cast_shadow=False, alpha="Overlay",
            backfaces=False, tags=None, name=None, rgb=None, fidelity="Automatic"):
        e = self._entry(root)
        tg_count = sum(1 for p in e["parts"] if p["role"] == role)
        part_name = name or ("%s_%s" % (e["name"], role) + ("" if tg_count == 0 else "_%d" % (tg_count + 1)))
        obj.name = part_name
        obj.data.name = part_name
        obj.data.materials.clear()
        obj.data.materials.append(self.material(set_name))
        obj.parent = root
        if role in PLANT_ROLES:
            clamp_below(obj, -PLANT_SINK)
        if not obj.data.uv_layers:
            raise ValueError("%s has no UVs (tangents cannot be exported)" % part_name)
        tris = tg.tri_count(obj)
        if tris > TRIANGLE_LIMIT:
            raise ValueError("%s has %d triangles (> %d)" % (part_name, tris, TRIANGLE_LIMIT))
        if tris == 0:
            self.warnings.append(part_name + " has no faces")
        s = self.sets[set_name]
        if not collide:
            collision = "Box"
        part = {
            "name": part_name, "role": role, "robloxMaterial": ROLE_MATERIAL.get(role, "Grass"),
            "rgb": list(rgb or s.get("avg", (128, 128, 128))), "collide": bool(collide), "collision": collision,
            "castShadow": bool(cast_shadow), "canQuery": bool(collide), "canTouch": bool(collide),
            "tags": list(tags or []), "tris": tris, "textureSet": set_name,
            "surfaceAppearance": {
                "colorMap": TEX_REL + "/" + s["color"],
                "normalMap": TEX_REL + "/" + s["normal"],
                "roughnessMap": TEX_REL + "/" + s["rough"],
                "metalnessMap": None,
                "alphaMode": alpha,
                "color": [255, 255, 255],
            },
            "transparency": 0,
            "doubleSided": False,
            "backFacesInMesh": bool(backfaces),
            "renderFidelity": fidelity,
        }
        e["parts"].append(part)
        return obj

    def attach(self, root, name, position, look=(0, 0, 1), up=(0, 1, 0)):
        e = self._entry(root)
        e["attachments"][name] = {"position": to_roblox(Vector(position)),
                                  "look": to_roblox(Vector(look).normalized()),
                                  "up": to_roblox(Vector(up).normalized())}

    def finish(self, root, ground_tol=0.05, buried_ok=0.0):
        e = self._entry(root)
        lo = np.array([1e9] * 3)
        hi = np.array([-1e9] * 3)
        bpy.context.view_layer.update()
        for c in root.children_recursive:
            if c.type != "MESH":
                continue
            co = tg.vertex_coords(c.data)
            mw = np.array(c.matrix_world)
            w = co @ mw[:3, :3].T + mw[:3, 3]
            lo = np.minimum(lo, w.min(0))
            hi = np.maximum(hi, w.max(0))
        a, b = to_roblox(lo), to_roblox(hi)
        e["boundsMin"] = [min(x, y) for x, y in zip(a, b)]
        e["boundsMax"] = [max(x, y) for x, y in zip(a, b)]
        e["size"] = [round(hi[0] - lo[0], 3), round(hi[2] - lo[2], 3), round(hi[1] - lo[1], 3)]
        e["tris"] = sum(p["tris"] for p in e["parts"])
        if lo[2] < -ground_tol - buried_ok:
            self.warnings.append("%s dips %.2f studs below z = 0" % (e["name"], -lo[2]))
        if buried_ok and lo[2] < -ground_tol:
            e["buriedDepth"] = round(-lo[2], 3)
        if e["budget"] and e["tris"] > e["budget"]:
            self.warnings.append("%s has %d tris (budget %d)" % (e["name"], e["tris"], e["budget"]))
        return e

    # ------------------------------------------------------------------ export
    def export(self, out_dir, glb_name, extra=None, gap=6.0, log=print, groups=None):
        """One manifest (<glb_name>.manifest.json) for the whole set; one GLB per group (GLB_GROUPS), assets in a
        row along X inside each GLB with their 'origin' recorded; textures embedded."""
        for e in self.assets:
            if "size" not in e:
                self.finish(e["root"])
        groups = groups or GLB_GROUPS
        by_name = {e["name"]: e for e in self.assets}
        missing = [e["name"] for e in self.assets if not any(e["name"] in v for v in groups.values())]
        if missing:
            raise ValueError("assets not in any GLB group: %s" % missing)
        tex_dir = os.path.join(out_dir, *TEX_REL.split("/"))
        glbs = []
        check_all = {"meshes": 0, "images": 0, "attributesPerMesh": {}}
        problems_all = []
        for gname, names in groups.items():
            members = [by_name[n] for n in names if n in by_name]
            if not members:
                continue
            x = 0.0
            for e in members:
                offset = x - e["boundsMin"][0]
                e["root"].location = (offset, 0, 0)
                e["origin"] = [round(offset, 4), 0.0, 0.0]
                e["glb"] = gname + ".glb"
                x += e["size"][0] + gap
            bpy.context.view_layer.update()
            for o in bpy.context.scene.objects:
                o.select_set(False)
            for e in members:
                e["root"].select_set(True)
                for c in e["root"].children_recursive:
                    c.select_set(True)
            glb = os.path.join(out_dir, gname + ".glb")
            bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
                                      export_yup=True, export_cameras=False, export_lights=False, export_extras=False,
                                      export_image_format="AUTO", export_materials="EXPORT", export_normals=True,
                                      export_texcoords=True, export_tangents=True, export_vertex_color="NONE",
                                      export_attributes=False)
            glb_set_metallic_zero(glb)
            check, problems = glb_check(glb)
            mats, imgs = glb_materials(glb)
            double = [m.get("name") for m in mats if m.get("doubleSided")]
            if double:
                problems.append("%s: doubleSided materials %s" % (gname, double))
            untextured = [m.get("name") for m in mats
                          if "baseColorTexture" not in m.get("pbrMetallicRoughness", {}) or "normalTexture" not in m]
            if untextured:
                problems.append("%s: materials without textures %s" % (gname, untextured))
            nbytes = os.path.getsize(glb)
            if nbytes > 19_000_000:
                problems.append("%s is %.2f MB (keep every GLB under 19 MB; the upload limit is 20 MB)"
                                % (gname, nbytes / 1e6))
            problems_all += problems
            check_all["meshes"] += check.get("meshes", 0)
            check_all["images"] += check.get("images", 0)
            check_all["attributesPerMesh"].update(check.get("attributesPerMesh", {}))
            glbs.append({"file": gname + ".glb", "assets": [e["name"] for e in members], "bytes": nbytes,
                         "sizeMB": round(nbytes / 1e6, 2), "embeddedImages": sorted(i.get("name", "") for i in imgs),
                         "alphaMask": sorted(m.get("name") for m in mats if m.get("alphaMode") == "MASK"),
                         "doubleSided": double, "tangentsOnEveryPrimitive": not any("TANGENT" in p for p in problems)})
            log("EXPORTED %s (%.2f MB), %d assets, %d images, MASK materials %s" % (
                glb, nbytes / 1e6, len(members), len(imgs), glbs[-1]["alphaMask"]))
        self.warnings += problems_all
        check_all["tangentsOnEveryPrimitive"] = not any("TANGENT" in p for p in problems_all)
        manifest = {
            "category": self.category,
            "glb": None,
            "glbs": glbs,
            "units": "1 Blender unit = 1 Roblox stud",
            "axes": "Roblox (x, y, z) = Blender (x, z, -y); asset front = Roblox LookVector (-Z); base on y = 0",
            "textureFolder": TEX_REL,
            "textureSets": {k: {"colorMap": TEX_REL + "/" + v["color"], "normalMap": TEX_REL + "/" + v["normal"],
                                "roughnessMap": TEX_REL + "/" + v["rough"], "metalnessMap": None,
                                "alphaMode": v.get("alphaMode", "Overlay"),
                                **({"tileStuds": v["tileStuds"]} if "tileStuds" in v else {}),
                                **({"pxPerStud": v["pxPerStud"]} if "pxPerStud" in v else {}),
                                "notes": v.get("notes", "")} for k, v in self.sets.items()},
            "textures": self._texture_inventory(tex_dir),
            "glbOnlyTextures": sorted(TEX_REL + "/glb_only/" + os.path.basename(f) for f in self._mr_written),
            "import": IMPORT_NOTES,
            "glbCheck": check_all,
            "assets": [],
            "warnings": self.warnings,
            "notes": self.notes,
        }
        if extra:
            manifest.update(extra)
        for e in self.assets:
            manifest["assets"].append({k: v for k, v in e.items() if k not in ("root", "budget")})
        mpath = os.path.join(out_dir, glb_name + ".manifest.json")
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=1)
        os.makedirs(REPO_MANIFESTS, exist_ok=True)
        shutil.copyfile(mpath, os.path.join(REPO_MANIFESTS, os.path.basename(mpath)))
        log("GLBCHECK %d meshes, %d images, tangents on every primitive: %s" % (
            check_all.get("meshes", 0), check_all.get("images", 0), check_all["tangentsOnEveryPrimitive"]))
        log("EXPORTED %d GLBs, %d assets, %d warnings" % (len(glbs), len(self.assets), len(self.warnings)))
        for w in self.warnings:
            log("WARNING " + w)
        log("MANIFEST %s (+ copy in art/manifests)" % mpath)
        return manifest

    def _texture_inventory(self, tex_dir):
        """Every PNG the parts reference: kind, pixel size, channels, bytes and which assets use it."""
        used = {}
        for e in self.assets:
            for p in e["parts"]:
                sa = p["surfaceAppearance"]
                for key, kind in (("colorMap", "color"), ("normalMap", "normal"), ("roughnessMap", "roughness")):
                    rel = sa.get(key)
                    if not rel:
                        continue
                    fn = rel.split("/")[-1]
                    d = used.setdefault(fn, {"kind": kind, "usedBy": []})
                    if e["name"] not in d["usedBy"]:
                        d["usedBy"].append(e["name"])
        for fn, d in used.items():
            path = os.path.join(tex_dir, fn)
            if os.path.exists(path):
                with open(path, "rb") as f:
                    head = f.read(33)
                w, h, bd, ct = struct.unpack(">IIBB", head[16:26])
                d.update({"size": [w, h], "bitDepth": bd,
                          "channels": {0: "gray", 2: "RGB", 4: "gray+alpha", 6: "RGBA"}.get(ct, str(ct)),
                          "bytes": os.path.getsize(path)})
            else:
                d["missing"] = True
                self.warnings.append("texture %s not found in %s" % (fn, tex_dir))
        return dict(sorted(used.items()))
