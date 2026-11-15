"""Blender MCP server for LAST STANDING (stdio, no dependencies; runs on Blender's own Python).

Tools
- blender_info           Blender's path and version, and whether the live bridge is running.
- blender_run_script     Run a Python script in headless Blender, e.g. an art/blender generator, with its arguments.
- blender_run_python     Run a Python snippet in headless Blender, optionally on a .blend file.
- blender_inspect_model  Import a GLB/FBX/OBJ (or open a .blend) and report objects, triangles, sizes, materials, images.
- blender_render_preview Render a model to PNG (three-quarter, front, side, back or top; midday or dusk light) and
                         return the image.
- blender_live_exec      Run Python inside a running Blender that has the ls_blender_bridge add-on enabled.
- blender_live_screenshot Capture that Blender's 3D viewport.

Headless tools start one Blender process per call, from the repo root. The live tools talk to 127.0.0.1:9876.
Protocol: MCP over stdio, newline-delimited JSON-RPC 2.0. Logs go to stderr only.
"""
import base64
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import traceback

VERSION = "0.1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_BLENDER = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "Blender",
                               "blender-5.3.0-windows-x64", "blender.exe")
BLENDER = os.environ.get("BLENDER_EXE") or DEFAULT_BLENDER
BRIDGE = ("127.0.0.1", int(os.environ.get("LS_BLENDER_BRIDGE_PORT", "9876")))
WORK = os.path.join(tempfile.gettempdir(), "ls_blender_mcp")
os.makedirs(WORK, exist_ok=True)


def log(*a):
    print("[blender-mcp]", *a, file=sys.stderr, flush=True)


def resolve(p):
    """Absolute path; relative paths are taken from the repo root."""
    p = os.path.expandvars(os.path.expanduser(str(p)))
    return p if os.path.isabs(p) else os.path.join(REPO, p)


def tail(s, n=120):
    lines = (s or "").splitlines()
    return "\n".join(lines[-n:])


def run_blender(args, timeout):
    if not os.path.isfile(BLENDER):
        return -2, 0.0, "", "Blender not found at %s (set BLENDER_EXE)" % BLENDER
    cmd = [BLENDER, "--background", "--factory-startup"] + args
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=timeout, cwd=REPO)
        return p.returncode, time.time() - t0, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return -1, time.time() - t0, out, "TIMEOUT after %ss" % timeout


def write_temp(name, text):
    path = os.path.join(WORK, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


def text_block(s):
    return {"type": "text", "text": s}


# ---------------------------------------------------------------- scripts run inside Blender

IMPORT_SNIPPET = r'''
import bpy, os, sys
def ls_import(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        return  # opened on the command line
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise SystemExit("unsupported file type: " + ext)
'''

INSPECT_SCRIPT = IMPORT_SNIPPET + r'''
import json, mathutils
argv = sys.argv[sys.argv.index("--") + 1:]
path = argv[0]
ls_import(path)
dg = bpy.context.evaluated_depsgraph_get()
objs, total = [], 0
for o in bpy.context.scene.objects:
    item = {"name": o.name, "type": o.type, "parent": o.parent.name if o.parent else None}
    if o.type == "MESH":
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        corners = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
        mn = [min(v[i] for v in corners) for i in range(3)]
        mx = [max(v[i] for v in corners) for i in range(3)]
        item.update(tris=tris, verts=len(me.vertices), size=[round(mx[i] - mn[i], 4) for i in range(3)],
                    materials=[m.name for m in o.data.materials if m], uvLayers=len(o.data.uv_layers))
        ev.to_mesh_clear()
        total += tris
    elif o.type == "EMPTY":
        item["location"] = [round(x, 4) for x in o.matrix_world.translation]
    objs.append(item)
images = [{"name": i.name, "size": list(i.size)} for i in bpy.data.images if i.size[0] > 0]
print("@@JSON@@" + json.dumps({"file": path, "objects": objs, "totalTris": total, "images": images,
                               "materials": [m.name for m in bpy.data.materials]}) + "@@END@@")
'''

RENDER_SCRIPT = IMPORT_SNIPPET + r'''
import math, mathutils
argv = sys.argv[sys.argv.index("--") + 1:]
path, out, view, light, res, bg, samples = argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], int(argv[6])
ls_import(path)
scene = bpy.context.scene
for o in list(scene.objects):
    if o.type in ("CAMERA", "LIGHT"):
        bpy.data.objects.remove(o, do_unlink=True)
pts = []
for o in scene.objects:
    if o.type == "MESH" and not o.hide_render:
        pts += [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
if not pts:
    raise SystemExit("nothing to render")
mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
ctr, radius = (mn + mx) / 2, max((mx - mn).length / 2, 1e-3)
rx, ry = [int(x) for x in res.lower().split("x")]
scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = rx, ry, 100
cam_data = bpy.data.cameras.new("LS_PreviewCam")
cam_data.lens = 50
cam = bpy.data.objects.new("LS_PreviewCam", cam_data)
scene.collection.objects.link(cam)
dirs = {"three_quarter": (1.0, -1.25, 0.5), "front": (0, -1, 0.12), "back": (0, 1, 0.12), "side": (1, 0, 0.12),
        "top": (0.001, -0.02, 1)}
d = mathutils.Vector(dirs.get(view, dirs["three_quarter"])).normalized()
hfov = cam_data.angle
vfov = 2 * math.atan(math.tan(hfov / 2) * ry / rx)
cam.location = ctr + d
cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
rot = cam.rotation_euler.to_matrix()
right, up = rot @ mathutils.Vector((1, 0, 0)), rot @ mathutils.Vector((0, 1, 0))
corners = [mathutils.Vector((x, y, z)) for x in (mn.x, mx.x) for y in (mn.y, mx.y) for z in (mn.z, mx.z)]
# tightest distance at which every corner of the box is inside the frame (closed form), plus a margin
dist = max(max((p - ctr).dot(d) + abs((p - ctr).dot(right)) / math.tan(hfov / 2),
               (p - ctr).dot(d) + abs((p - ctr).dot(up)) / math.tan(vfov / 2)) for p in corners) * 1.1
dist = max(dist, radius * 0.5)
cam.location = ctr + d * dist
cam_data.clip_start, cam_data.clip_end = max(dist / 1000, 0.001), dist * 20
scene.camera = cam
sun = bpy.data.objects.new("LS_Sun", bpy.data.lights.new("LS_Sun", "SUN"))
scene.collection.objects.link(sun)
if light == "dusk":
    elev, az, energy, col = 9, 250, 2.6, (1.0, 0.6, 0.36)
    sky, sky_strength = (0.36, 0.3, 0.48), 0.55
else:
    elev, az, energy, col = 55, 140, 4.2, (1.0, 0.96, 0.9)
    sky, sky_strength = (0.45, 0.62, 0.92), 0.85
sun.data.energy, sun.data.color = energy, col
sun.rotation_euler = (math.radians(90 - elev), 0, math.radians(az))
world = scene.world or bpy.data.worlds.new("LS_World")
scene.world = world
world.use_nodes = True
bgnode = world.node_tree.nodes.get("Background")
if bg == "grey":
    sky = (0.5, 0.5, 0.52)
bgnode.inputs[0].default_value = (sky[0], sky[1], sky[2], 1)
bgnode.inputs[1].default_value = sky_strength
if bg != "none":
    bpy.ops.mesh.primitive_plane_add(size=radius * 40, location=(ctr.x, ctr.y, mn.z - radius * 0.002))
    ground = bpy.context.active_object
    mat = bpy.data.materials.new("LS_Ground")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    g = (0.16, 0.27, 0.09) if bg == "sky" else (0.32, 0.32, 0.33)
    bsdf.inputs["Base Color"].default_value = (g[0], g[1], g[2], 1)
    bsdf.inputs["Roughness"].default_value = 0.95
    ground.data.materials.append(mat)
scene.render.engine = "CYCLES"
scene.cycles.samples = samples
try:
    scene.cycles.use_denoising = True
except Exception:
    pass
try:
    scene.view_settings.view_transform = "AgX"
except Exception:
    pass
scene.render.film_transparent = False
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("@@JSON@@" + json.dumps({"out": out}) + "@@END@@") if False else print("@@OUT@@" + out + "@@END@@")
'''


def parse_marked(stdout, mark):
    a = stdout.find(mark)
    if a < 0:
        return None
    b = stdout.find("@@END@@", a)
    return stdout[a + len(mark):b if b >= 0 else None]


# ---------------------------------------------------------------- tools

def t_info(a):
    code, dt, out, err = run_blender(["--version"], 60) if os.path.isfile(BLENDER) else (-2, 0, "", "missing")
    live = bridge_call({"op": "ping"}, 2)
    return [text_block(json.dumps({
        "blender": BLENDER, "found": os.path.isfile(BLENDER),
        "version": (out or "").splitlines()[0] if out else None,
        "repo": REPO, "workDir": WORK,
        "liveBridge": "running" if live.get("ok") else "not running (enable the ls_blender_bridge add-on in Blender)",
    }, indent=1))], False


def t_run_script(a):
    script = resolve(a["script_path"])
    if not os.path.isfile(script):
        return [text_block("script not found: " + script)], True
    args = []
    if a.get("blend_file"):
        args.append(resolve(a["blend_file"]))
    args += ["--python", script]
    if a.get("script_args"):
        args += ["--"] + [str(x) for x in a["script_args"]]
    code, dt, out, err = run_blender(args, int(a.get("timeout_s", 900)))
    return [text_block("exit %s in %.1f s\n--- stdout (last lines) ---\n%s\n--- stderr (last lines) ---\n%s"
                       % (code, dt, tail(out), tail(err, 40)))], code != 0


def t_run_python(a):
    path = write_temp("snippet_%d.py" % int(time.time() * 1000), a["code"])
    args = []
    if a.get("blend_file"):
        args.append(resolve(a["blend_file"]))
    args += ["--python", path]
    code, dt, out, err = run_blender(args, int(a.get("timeout_s", 300)))
    return [text_block("exit %s in %.1f s\n--- stdout (last lines) ---\n%s\n--- stderr (last lines) ---\n%s"
                       % (code, dt, tail(out), tail(err, 40)))], code != 0


def t_inspect(a):
    path = resolve(a["path"])
    if not os.path.isfile(path):
        return [text_block("file not found: " + path)], True
    script = write_temp("inspect.py", INSPECT_SCRIPT)
    args = ([path] if path.lower().endswith(".blend") else []) + ["--python", script, "--", path]
    code, dt, out, err = run_blender(args, int(a.get("timeout_s", 300)))
    data = parse_marked(out, "@@JSON@@")
    if data is None:
        return [text_block("inspect failed (exit %s)\n%s\n%s" % (code, tail(out, 40), tail(err, 40)))], True
    return [text_block(json.dumps(json.loads(data), indent=1))], False


def t_render(a):
    path = resolve(a["path"])
    if not os.path.isfile(path):
        return [text_block("file not found: " + path)], True
    out = resolve(a["output_png"]) if a.get("output_png") else os.path.join(
        WORK, "preview_%s_%d.png" % (os.path.splitext(os.path.basename(path))[0], int(time.time())))
    script = write_temp("render.py", RENDER_SCRIPT)
    args = ([path] if path.lower().endswith(".blend") else []) + [
        "--python", script, "--", path, out, a.get("view", "three_quarter"), a.get("light", "midday"),
        a.get("resolution", "960x540"), a.get("background", "sky"), str(int(a.get("samples", 32)))]
    code, dt, sout, err = run_blender(args, int(a.get("timeout_s", 600)))
    if code != 0 or not os.path.isfile(out):
        return [text_block("render failed (exit %s)\n%s\n%s" % (code, tail(sout, 40), tail(err, 40)))], True
    blocks = [text_block("rendered %s in %.1f s" % (out, dt))]
    if a.get("return_image", True):
        with open(out, "rb") as f:
            blocks.append({"type": "image", "data": base64.b64encode(f.read()).decode("ascii"), "mimeType": "image/png"})
    return blocks, False


def bridge_call(req, timeout=120):
    try:
        with socket.create_connection(BRIDGE, timeout=min(timeout, 5)) as s:
            s.settimeout(timeout)
            s.sendall((json.dumps(req) + "\n").encode("utf-8"))
            buf = b""
            while not buf.endswith(b"\n"):
                chunk = s.recv(1 << 16)
                if not chunk:
                    break
                buf += chunk
        return json.loads(buf.decode("utf-8")) if buf else {"ok": False, "error": "empty reply"}
    except OSError as e:
        return {"ok": False, "error": "bridge not reachable at %s:%d (%s)" % (BRIDGE[0], BRIDGE[1], e)}


def t_live_exec(a):
    r = bridge_call({"op": "exec", "code": a["code"], "timeout": int(a.get("timeout_s", 120))},
                    int(a.get("timeout_s", 120)) + 5)
    return [text_block(json.dumps(r, indent=1))], not r.get("ok")


def t_live_shot(a):
    r = bridge_call({"op": "screenshot"}, 30)
    if not r.get("ok"):
        return [text_block(json.dumps(r))], True
    return [text_block("viewport screenshot"), {"type": "image", "data": r["png"], "mimeType": "image/png"}], False


TOOLS = [
    ("blender_info", "Blender's path and version, the repo root, and whether the live bridge add-on is running.",
     {"type": "object", "properties": {}}, t_info),
    ("blender_run_script", "Run a Python script in headless Blender (from the repo root), e.g. an art/blender generator "
     "with its export and preview folders. Returns the exit code and the last lines of output.",
     {"type": "object", "properties": {
         "script_path": {"type": "string", "description": "Script path, absolute or relative to the repo root"},
         "script_args": {"type": "array", "items": {"type": "string"}, "description": "Arguments after --"},
         "blend_file": {"type": "string", "description": "Optional .blend to open first"},
         "timeout_s": {"type": "integer", "default": 900}},
      "required": ["script_path"]}, t_run_script),
    ("blender_run_python", "Run a Python snippet in headless Blender (bpy available), optionally on a .blend. Print "
     "what you need back; the last lines of output are returned.",
     {"type": "object", "properties": {
         "code": {"type": "string"}, "blend_file": {"type": "string"},
         "timeout_s": {"type": "integer", "default": 300}}, "required": ["code"]}, t_run_python),
    ("blender_inspect_model", "Import a GLB, GLTF, FBX or OBJ (or open a .blend) and report every object with its "
     "triangle count, size in studs, materials and UV layers, plus totals and image sizes.",
     {"type": "object", "properties": {"path": {"type": "string"}, "timeout_s": {"type": "integer", "default": 300}},
      "required": ["path"]}, t_inspect),
    ("blender_render_preview", "Render a GLB, GLTF, FBX, OBJ or .blend to a PNG with a framed camera, sun and sky "
     "(Cycles, AgX) and return the image, so a look can be checked straight away.",
     {"type": "object", "properties": {
         "path": {"type": "string"},
         "view": {"type": "string", "enum": ["three_quarter", "front", "back", "side", "top"], "default": "three_quarter"},
         "light": {"type": "string", "enum": ["midday", "dusk"], "default": "midday"},
         "background": {"type": "string", "enum": ["sky", "grey", "none"], "default": "sky"},
         "resolution": {"type": "string", "default": "960x540"},
         "samples": {"type": "integer", "default": 32},
         "output_png": {"type": "string", "description": "Where to save it (default: a temp folder)"},
         "return_image": {"type": "boolean", "default": True},
         "timeout_s": {"type": "integer", "default": 600}}, "required": ["path"]}, t_render),
    ("blender_live_exec", "Run Python inside a running Blender that has the ls_blender_bridge add-on enabled "
     "(localhost only). Set a variable named result to return a value.",
     {"type": "object", "properties": {"code": {"type": "string"}, "timeout_s": {"type": "integer", "default": 120}},
      "required": ["code"]}, t_live_exec),
    ("blender_live_screenshot", "Capture the 3D viewport of the running Blender (ls_blender_bridge add-on).",
     {"type": "object", "properties": {}}, t_live_shot),
]
BY_NAME = {t[0]: t for t in TOOLS}

INSTRUCTIONS = ("Blender for LAST STANDING. Assets are generated by seeded scripts in art/blender (see art/README.md) "
                "in the faceted 'realistic blockish' style of docs/design/ArtStyle.md. Prefer editing a generator and "
                "re-running it over one-off edits; check every result with blender_render_preview and "
                "blender_inspect_model, and approve looks in game, not only in Blender.")


def handle(msg):
    mid, method = msg.get("id"), msg.get("method")
    if method == "initialize":
        pv = (msg.get("params") or {}).get("protocolVersion") or "2025-06-18"
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": pv, "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "blender", "version": VERSION}, "instructions": INSTRUCTIONS}}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": [
            {"name": n, "description": d, "inputSchema": s} for (n, d, s, _) in TOOLS]}}
    if method == "tools/call":
        p = msg.get("params") or {}
        tool = BY_NAME.get(p.get("name"))
        if not tool:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": "unknown tool " + str(p.get("name"))}}
        try:
            content, is_err = tool[3](p.get("arguments") or {})
        except Exception:
            content, is_err = [text_block(traceback.format_exc())], True
        return {"jsonrpc": "2.0", "id": mid, "result": {"content": content, "isError": bool(is_err)}}
    if mid is None:
        return None  # a notification (e.g. notifications/initialized)
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found: " + str(method)}}


def main():
    log("started; blender =", BLENDER, "; repo =", REPO)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        reply = handle(msg)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
