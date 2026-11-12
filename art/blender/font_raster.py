# Rasterise an open font (Oswald Bold, SIL OFL 1.1) into small glyph bitmaps for the Roll Call point-cloud letters
# (Studio: StarterPlayerScripts.Client.Controllers.FallenRecapController.PointFont).
# Step 1, headless Blender (Oswald ships with Roblox Studio in <Roblox>/Versions/<ver>/content/fonts/Oswald-Bold.ttf):
#   blender --background --factory-startup --python font_raster.py -- <Oswald-Bold.ttf> <dir>/PointFont_glyphs.lua 22
# Step 2, plain Python: python make_pointfont.py <dir>   -> <dir>/PointFont.lua (fixes Q and 6, adds the layout code)
# Paste PointFont.lua into the PointFont ModuleScript.
import bpy, sys, math
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
FONT_PATH, OUT_PATH = argv[0], argv[1]
CAP_ROWS = int(argv[2]) if len(argv) > 2 else 22

CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.'!?&#@:()+/,*\"%=<>[]~"

font = bpy.data.fonts.load(FONT_PATH)
scene = bpy.context.scene


def glyph_tris(ch):
    curve = bpy.data.curves.new("glyph", type='FONT')
    curve.body = ch
    curve.font = font
    curve.size = 1.0
    curve.dimensions = '2D'
    curve.fill_mode = 'BOTH'
    curve.resolution_u = 24
    obj = bpy.data.objects.new("glyph", curve)
    scene.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    mesh = ev.to_mesh()
    mesh.calc_loop_triangles()
    verts = np.array([v.co[:2] for v in mesh.vertices], dtype=np.float64)
    tris = np.array([t.vertices[:] for t in mesh.loop_triangles], dtype=np.int64)
    ev.to_mesh_clear()
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    if len(tris) == 0:
        return None
    return verts[tris]  # (n, 3, 2)


def inside(points, tris):
    # points (m, 2); tris (n, 3, 2) -> bool (m,)
    res = np.zeros(len(points), dtype=bool)
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    for start in range(0, len(points), 4096):
        p = points[start:start + 4096][:, None, :]
        v0 = c - a
        v1 = b - a
        v2 = p - a
        d00 = (v0 * v0).sum(-1)
        d01 = (v0 * v1).sum(-1)
        d11 = (v1 * v1).sum(-1)
        d20 = (v2 * v0).sum(-1)
        d21 = (v2 * v1).sum(-1)
        den = d00 * d11 - d01 * d01
        den = np.where(np.abs(den) < 1e-12, 1e-12, den)
        u = (d11 * d20 - d01 * d21) / den
        v = (d00 * d21 - d01 * d20) / den
        hit = (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9)
        res[start:start + 4096] = hit.any(axis=1)
    return res


H = glyph_tris("H")
cap_h = H[:, :, 1].max() - H[:, :, 1].min()
cell = cap_h / CAP_ROWS
SS = 3  # supersampling per cell axis; a cell is filled when >= 45% of its samples are inside

out = []
for ch in CHARS:
    tris = glyph_tris(ch)
    if tris is None:
        continue
    xmin, xmax = tris[:, :, 0].min(), tris[:, :, 0].max()
    ymin, ymax = tris[:, :, 1].min(), tris[:, :, 1].max()
    c0 = math.floor(xmin / cell + 1e-6)
    c1 = math.ceil(xmax / cell - 1e-6)
    r0 = math.floor(ymin / cell + 1e-6)
    r1 = math.ceil(ymax / cell - 1e-6)
    cols, rows = c1 - c0, r1 - r0
    offs = (np.arange(SS) + 0.5) / SS
    rows_bits = []
    for r in range(rows - 1, -1, -1):  # top row first
        bits = 0
        for c in range(cols):
            xs = (c0 + c + offs) * cell
            ys = (r0 + r + offs) * cell
            gx, gy = np.meshgrid(xs, ys)
            pts = np.stack([gx.ravel(), gy.ravel()], axis=1)
            frac = inside(pts, tris).mean()
            if frac >= 0.45:
                bits |= 1 << (cols - 1 - c)
        rows_bits.append(bits)
    # trim empty columns/rows that the threshold produced
    out.append((ch, cols, rows, r0, rows_bits))
    print("GLYPH", repr(ch), cols, "x", rows, "base", r0)


def lua_char(ch):
    if ch in ('"', '\\'):
        return '"\\' + ch + '"'
    return '"' + ch + '"'


lines = []
lines.append("--[[")
lines.append("\tPointFont - glyph bitmaps for the Roll Call point-cloud letters (client).")
lines.append("\tRasterised from Oswald Bold (SIL Open Font License 1.1, (c) The Oswald Project Authors) by")
lines.append("\tart/blender/font_raster.py at %d rows of cap height. Each glyph: w/h in cells, y0 = row of the" % CAP_ROWS)
lines.append("\tbottom edge relative to the baseline (negative = descends), rows = top-to-bottom bitmasks (bit w-1 = left column).")
lines.append("\tPointFont.layout(text, capHeight) -> { Vector2 } cell centres in studs, origin at the text centre.")
lines.append("]]")
lines.append("local PointFont = {}")
lines.append("PointFont.CapRows = %d" % CAP_ROWS)
lines.append("PointFont.Tracking = 0.16 -- gap between glyphs, in cap heights")
lines.append("PointFont.SpaceWidth = 0.32 -- in cap heights")
lines.append("PointFont.Glyphs = {")
for ch, cols, rows, r0, rows_bits in out:
    lines.append("\t[%s] = { w = %d, h = %d, y0 = %d, rows = { %s } }," % (lua_char(ch), cols, rows, r0, ", ".join(str(b) for b in rows_bits)))
lines.append("}")
lines.append("")
with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("WROTE", OUT_PATH, len(out), "glyphs, cell", cell, "cap", cap_h)
