bl_info = {
    "name": "LAST STANDING Bridge (MCP live link)",
    "author": "LAST STANDING",
    "version": (0, 1, 0),
    "blender": (4, 0, 0),
    "location": "Runs in the background once enabled",
    "description": "Lets the LAST STANDING Blender MCP run Python in this Blender and capture the viewport "
                   "(127.0.0.1 only). Enable it only while you want Claude to work in this Blender window.",
    "category": "Development",
}

import base64
import contextlib
import io
import json
import os
import queue
import socket
import tempfile
import threading
import traceback

import bpy

HOST = "127.0.0.1"
PORT = int(os.environ.get("LS_BLENDER_BRIDGE_PORT", "9876"))
_jobs = queue.Queue()
_listener = None
_running = False


def _serve():
    global _running
    try:
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(4)
    except OSError as e:
        print("[LS Bridge] could not listen on %s:%d: %s" % (HOST, PORT, e))
        return
    print("[LS Bridge] listening on %s:%d" % (HOST, PORT))
    while _running:
        try:
            conn, _ = srv.accept()
        except OSError:
            break
        threading.Thread(target=_handle, args=(conn,), daemon=True).start()


def _handle(conn):
    try:
        data = b""
        while not data.endswith(b"\n"):
            chunk = conn.recv(1 << 16)
            if not chunk:
                break
            data += chunk
        req = json.loads(data.decode("utf-8"))
        if req.get("op") == "ping":
            resp = {"ok": True, "blender": bpy.app.version_string}
        else:
            box, done = {}, threading.Event()
            _jobs.put((req, box, done))  # run on Blender's main thread (see _tick)
            done.wait(timeout=float(req.get("timeout", 120)))
            resp = box.get("resp", {"ok": False, "error": "timed out waiting for Blender's main thread"})
        conn.sendall((json.dumps(resp) + "\n").encode("utf-8"))
    except Exception:
        try:
            conn.sendall((json.dumps({"ok": False, "error": traceback.format_exc()}) + "\n").encode("utf-8"))
        except OSError:
            pass
    finally:
        conn.close()


def _run(req):
    op = req.get("op")
    if op == "exec":
        buf, ns = io.StringIO(), {"bpy": bpy, "__name__": "__ls_bridge__"}
        try:
            with contextlib.redirect_stdout(buf):
                exec(compile(req["code"], "<mcp>", "exec"), ns)
            return {"ok": True, "stdout": buf.getvalue()[-20000:],
                    "result": repr(ns["result"])[:20000] if "result" in ns else None}
        except Exception:
            return {"ok": False, "stdout": buf.getvalue()[-20000:], "error": traceback.format_exc()}
    if op == "screenshot":
        path = os.path.join(tempfile.gettempdir(), "ls_bridge_viewport.png")
        for window in bpy.context.window_manager.windows:
            for area in window.screen.areas:
                if area.type == "VIEW_3D":
                    with bpy.context.temp_override(window=window, area=area):
                        bpy.ops.screen.screenshot_area(filepath=path)
                    with open(path, "rb") as f:
                        return {"ok": True, "png": base64.b64encode(f.read()).decode("ascii")}
        return {"ok": False, "error": "no 3D viewport is open"}
    return {"ok": False, "error": "unknown op " + str(op)}


def _tick():
    while not _jobs.empty():
        req, box, done = _jobs.get()
        box["resp"] = _run(req)
        done.set()
    return 0.1


def register():
    global _listener, _running
    _running = True
    if _listener is None or not _listener.is_alive():
        _listener = threading.Thread(target=_serve, daemon=True)
        _listener.start()
    if not bpy.app.timers.is_registered(_tick):
        bpy.app.timers.register(_tick, persistent=True)


def unregister():
    global _running
    _running = False
    if bpy.app.timers.is_registered(_tick):
        bpy.app.timers.unregister(_tick)
