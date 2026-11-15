# Blender MCP connector (LAST STANDING)

A small, dependency-free MCP server that lets Claude drive Blender for this project. It is our own code: it
doesn't download assets or add-ons, in line with the owner's rule that every asset is made by us.

## Tools

| Tool | What it does |
|---|---|
| `blender_info` | Blender's path and version, and whether the live link is running |
| `blender_run_script` | Run a script in headless Blender from the repo root, e.g. `art/blender/arms_faceted.py -- <out> <previews>` |
| `blender_run_python` | Run a snippet in headless Blender, optionally on a `.blend` |
| `blender_inspect_model` | Objects, triangles, sizes, materials and images of a GLB, GLTF, FBX, OBJ or `.blend` |
| `blender_render_preview` | Render a model (three-quarter, front, back, side or top; midday or dusk) and return the image |
| `blender_live_exec` | Run Python in an open Blender window (needs the live link below) |
| `blender_live_screenshot` | Capture that window's 3D viewport |

## Setup

1. **Register it.** `.mcp.json` at the repo root, and at the session folder, already lists the server. It runs on
   Blender's own Python:

   ```json
   { "mcpServers": { "blender": { "type": "stdio",
       "command": "%LOCALAPPDATA%\\Programs\\Blender\\blender-5.3.0-windows-x64\\5.3\\python\\bin\\python.exe",
       "args": ["-I", "<repo>\\tools\\blender_mcp\\server.py"] } } }
   ```

   Claude Code asks you to approve the project's `blender` server the next time a session starts in that folder.
   If Blender lives somewhere else, set `BLENDER_EXE` in the server's `env`.
2. **Optional live link.** To let Claude work in an open Blender window:
   - Blender → Edit → Preferences → Add-ons → Install from Disk → `tools/blender_mcp/ls_blender_bridge.py`;
   - tick "LAST STANDING Bridge".

   It listens on 127.0.0.1:9876 only, and it runs any Python it's sent. Untick it when you're done.

## Self-test

Run `scratchpad/mcp_selftest.py <model.glb>`, or drive the server by hand. Each line on stdin is a JSON-RPC message:
`initialize`, then `tools/list`, then `tools/call`. The 14 November test inspected Rocks.glb (49 objects, 17,612
triangles) and rendered it in about 2 s.
