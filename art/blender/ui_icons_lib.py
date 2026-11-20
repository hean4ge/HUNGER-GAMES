# Quiet cards icon kit: drawing primitives for flat, matte, faceted icons rendered in Blender.
# Used by ui_icons.py (CardMenusAndShop.md section 4.2). Nothing here touches the scene by itself.
#
# Look: every shape is a 2D curve extruded with a 45-degree chamfer; the material is pure emission whose
# colour steps down once (x SHADE) on facets that face away from an upper-left light. So each shape reads as
# one flat matte tone with one shade step on its lower-right rim: "chunky facets", no gradients, no gloss.
# Coordinates are design units, SVG style (x right, y down); (CX, CY) is the canvas centre.
import math

import bpy

# --- palette (Theme.lua / CardMenusAndShop 4.2) ------------------------------------------------------------
P = dict(
    ink="#F4F1EA", ink2="#BDB8AC", ink3="#8E897F", shade="#0D1012", dark="#2A2F33", dk="#3E4448",
    st="#A7AEB2", st2="#6C747A", st3="#4D555A", wd="#8E6B4C", wd2="#6A4E38", lt="#5A4535",
    br="#C9A24E", br2="#9C7A34", sun="#E8B65A", sage="#9DBFAE", sage2="#6F9282",
    cop="#B87A52", cop2="#8C5A3A", ver="#5E9E8E", mul="#9E5C78", moon="#C9D3E0", moon2="#9EABBC",
    parch="#E8D9B0", parch2="#CDBB8E", stone="#A39D90", stone2="#7E786C",
    slate="#6C7FA0", slate2="#4E5F7C", cream="#EFE6D2", ox="#7A2E2A", ox2="#5C2220",
    rust="#A8643E", leaf="#C08A3E", silver="#C3C8CB", silver2="#DADDDF", silver3="#8E979C",
    crown="#3F4A52", crown2="#56636B", flame="#E8A85A", flame2="#C9743F",
)

SHADE_STEP = 0.66          # linear multiplier on away-facing facets (about 0.83 in sRGB)
LIGHT = (-0.45, 0.55, 0.70)  # upper-left, towards the viewer
CHAMFER = 1.0              # design units (2.56 px at 256)

CX, CY = 50.0, 50.0
_layer = [0]
_mats = {}
_profiles = {}
_font = [None]


def set_canvas(cx, cy):
    global CX, CY
    CX, CY = cx, cy
    _layer[0] = 0


def set_font(path):
    try:
        _font[0] = bpy.data.fonts.load(path, check_existing=True)
    except Exception:
        _font[0] = None


def hex_lin(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


def col(c):
    return P.get(c, c)


def mat(c):
    c = col(c)
    if c in _mats:
        return _mats[c]
    m = bpy.data.materials.new("ic_" + c.lstrip("#"))
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    L = LIGHT
    n = math.sqrt(sum(v * v for v in L))
    dot.inputs[1].default_value = (L[0] / n, L[1] / n, L[2] / n)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e0, e1 = ramp.color_ramp.elements
    e0.position = 0.0
    e0.color = (SHADE_STEP, SHADE_STEP, SHADE_STEP, 1)
    e1.position = 0.45
    e1.color = (1, 1, 1, 1)
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    lin = hex_lin(c)
    mul.inputs[1].default_value = (lin[0], lin[1], lin[2])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    nt.links.new(dot.outputs["Value"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mul.inputs[0])
    nt.links.new(mul.outputs["Vector"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    _mats[c] = m
    return m


def _xy(p):
    return (p[0] - CX, CY - p[1])


def _next_z():
    _layer[0] += 1
    return _layer[0] * 3.0


def _link(cu, c, name):
    cu.materials.append(mat(c))
    ob = bpy.data.objects.new(name, cu)
    ob.location.z = _next_z()
    bpy.context.scene.collection.objects.link(ob)
    return ob


# --- geometry helpers (design units) -----------------------------------------------------------------------
def circle_pts(cx, cy, r, seg=40, a0=0.0, ry=None):
    ry = r if ry is None else ry
    return [(cx + r * math.cos(a0 + 2 * math.pi * i / seg), cy + ry * math.sin(a0 + 2 * math.pi * i / seg)) for i in range(seg)]


def arc_pts(cx, cy, r, a0, a1, seg=None, ry=None):
    """Angles in degrees, SVG sense (0 = right, 90 = down)."""
    ry = r if ry is None else ry
    seg = seg or max(4, int(abs(a1 - a0) / 7))
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / seg)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / seg))) for i in range(seg + 1)]


def quad(p0, c, p1, seg=12):
    out = []
    for i in range(seg + 1):
        t = i / seg
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]))
    return out


def cubic(p0, c0, c1, p1, seg=14):
    out = []
    for i in range(seg + 1):
        t = i / seg
        a, b, cc, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
        out.append((a * p0[0] + b * c0[0] + cc * c1[0] + d * p1[0], a * p0[1] + b * c0[1] + cc * c1[1] + d * p1[1]))
    return out


def rrect_pts(x0, y0, x1, y1, r=4, seg=4):
    r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    pts = []
    for (cx, cy, a0) in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        if r <= 0.01:
            pts.append((cx, cy))
            continue
        pts += arc_pts(cx, cy, r, a0, a0 + 90, seg)
    return pts


def star_pts(cx, cy, r_out, r_in, n=5, a0=-90):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(a0 + 180.0 * i / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def xform(pts, dx=0.0, dy=0.0, rot=0.0, sx=1.0, sy=None, ox=0.0, oy=0.0):
    """Scale and rotate (degrees, clockwise on screen) about (ox, oy), then translate."""
    sy = sx if sy is None else sy
    ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    out = []
    for x, y in pts:
        x, y = (x - ox) * sx, (y - oy) * sy
        out.append((ox + x * ca - y * sa + dx, oy + x * sa + y * ca + dy))
    return out


def leaf_pts(cx, cy, length, width, rot=0.0, seg=8):
    """A pointed leaf/petal along +x from its base at (cx, cy)."""
    top = quad((0, 0), (length * 0.5, -width), (length, 0), seg)
    bot = quad((length, 0), (length * 0.5, width), (0, 0), seg)[1:-1]
    return xform(top + bot, cx, cy, rot)


# --- primitives --------------------------------------------------------------------------------------------
def shape(loops, c, chamfer=CHAMFER, name="shape"):
    """Filled polygon(s). loops: one list of points, or a list of lists (even-odd: inner loops are holes)."""
    if loops and isinstance(loops[0][0], (int, float)):
        loops = [loops]
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "FRONT"
    cu.extrude = 0.4
    cu.bevel_depth = chamfer
    cu.bevel_resolution = 0
    for loop in loops:
        sp = cu.splines.new("POLY")
        sp.points.add(len(loop) - 1)
        for p, q in zip(sp.points, loop):
            x, y = _xy(q)
            p.co = (x, y, 0, 1)
        sp.use_cyclic_u = True
    return _link(cu, c, name)


def circle(cx, cy, r, c, seg=40, ry=None):
    return shape(circle_pts(cx, cy, r, seg, ry=ry), c)


def ring(cx, cy, r_out, r_in, c, seg=44):
    return shape([circle_pts(cx, cy, r_out, seg), circle_pts(cx, cy, r_in, seg)], c)


def rect(x0, y0, x1, y1, c, r=0.0):
    return shape(rrect_pts(x0, y0, x1, y1, r) if r > 0 else [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], c)


def _profile(w, chamfer):
    key = (round(w, 3), round(chamfer, 3))
    if key in _profiles:
        return _profiles[key]
    c = min(chamfer, w * 0.3)
    pc = bpy.data.curves.new("prof", "CURVE")
    pc.dimensions = "2D"
    sp = pc.splines.new("POLY")
    h = w / 2.0
    # y is negated so the chamfer faces the camera (+Z) after the sweep
    pp = [(-h, 1.0), (h, 1.0), (h, 0.0), (h - c, -c), (-h + c, -c), (-h, 0.0)]
    sp.points.add(len(pp) - 1)
    for p, (x, y) in zip(sp.points, pp):
        p.co = (x, y, 0, 1)
    sp.use_cyclic_u = True
    ob = bpy.data.objects.new("prof", pc)
    bpy.context.scene.collection.objects.link(ob)
    ob.location.z = -1000
    ob.hide_render = True
    _profiles[key] = ob
    return ob


def stroke(pts, w, c, cap="round", closed=False, chamfer=CHAMFER, name="stroke"):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.bevel_mode = "OBJECT"
    cu.bevel_object = _profile(w, chamfer)
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for p, q in zip(sp.points, pts):
        x, y = _xy(q)
        p.co = (x, y, 0, 1)
    sp.use_cyclic_u = closed
    if cap == "round" and not closed:
        # end discs sit one layer below the stroke so the stroke's top covers them
        z_before = _layer[0]
        for q in (pts[0], pts[-1]):
            d = shape(circle_pts(q[0], q[1], w / 2.0 - chamfer * 0.5, 20), c, chamfer=chamfer * 0.9, name="cap")
            d.location.z = (z_before + 1) * 3.0 - 1.4
        _layer[0] = z_before
    return _link(cu, c, name)


def arc(cx, cy, r, a0, a1, w, c, cap="round"):
    return stroke(arc_pts(cx, cy, r, a0, a1), w, c, cap)


def dashed(pts, w, c, dash=6.0, gap=5.0, cap="round"):
    """Split a polyline into dashes of `dash` design units."""
    segs = []
    cur = [pts[0]]
    acc = 0.0
    on = True
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a, b)
        t = 0.0
        while L - t > 1e-6:
            need = (dash if on else gap) - acc
            step = min(need, L - t)
            t += step
            acc += step
            p = (a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L)
            if on:
                cur.append(p)
            if acc >= (dash if on else gap) - 1e-6:
                if on and len(cur) > 1:
                    segs.append(cur)
                on = not on
                acc = 0.0
                cur = [p]
    if on and len(cur) > 1:
        segs.append(cur)
    return [stroke(s, w, c, cap) for s in segs]


def arrowhead(tip, frm, size, c, width=None):
    """A solid triangle pointing from `frm` towards `tip`."""
    ang = math.atan2(tip[1] - frm[1], tip[0] - frm[0])
    width = size * 0.8 if width is None else width
    bx, by = tip[0] - size * math.cos(ang), tip[1] - size * math.sin(ang)
    px, py = -math.sin(ang), math.cos(ang)
    return shape([tip, (bx + px * width, by + py * width), (bx - px * width, by - py * width)], c)


def text(s, cx, cy, size, c, chamfer=0.6):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = s
    if _font[0] is not None:
        cu.font = _font[0]
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = 0.3
    cu.bevel_depth = chamfer
    cu.bevel_resolution = 0
    cu.materials.append(mat(c))
    ob = bpy.data.objects.new("txt", cu)
    x, y = _xy((cx, cy))
    ob.location = (x, y, _next_z())
    bpy.context.scene.collection.objects.link(ob)
    return ob
