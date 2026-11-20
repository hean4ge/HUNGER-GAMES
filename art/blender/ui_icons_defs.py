# The icon list for Quiet cards (CardMenusAndShop.md section 4.2): 84 icons + banners.
# Each entry: id -> (group, display name, draw function). Draw functions use ui_icons_lib in a 100 x 100
# design box (silhouette inside about 8..92), SVG coordinates (y down). Rank emblems render at 512 px,
# banners in a 300 x 100 box at 768 x 256.
import math

from ui_icons_lib import (P, arc, arc_pts, arrowhead, circle, circle_pts, cubic, dashed, leaf_pts, quad, rect,
                          ring, rrect_pts, shape, star_pts, stroke, text, xform)

ICONS = {}   # id -> dict(group, name, kind, fn)


def icon(group, name, kind="icon"):
    def deco(fn):
        ICONS[fn.__name__] = dict(group=group, name=name, kind=kind, fn=fn)
        return fn
    return deco


# --- small reusable drawings -------------------------------------------------------------------------------
def figure(x, y, s, c, pose="stand"):
    """A simple person: head + body strokes. (x, y) = head centre; s = scale (1 = 10 unit head)."""
    circle(x, y, 7 * s, c)
    w = 8 * s
    stroke([(x, y + 11 * s), (x, y + 32 * s)], w, c)
    if pose == "stand":
        stroke([(x, y + 32 * s), (x - 7 * s, y + 52 * s)], w, c)
        stroke([(x, y + 32 * s), (x + 7 * s, y + 52 * s)], w, c)
        stroke([(x, y + 16 * s), (x - 10 * s, y + 30 * s)], w * 0.85, c)
        stroke([(x, y + 16 * s), (x + 10 * s, y + 30 * s)], w * 0.85, c)


def hatchet(x, y, rot, s, head="st", haft="wd", edge="ink2"):
    """Hatchet with the haft along +x from the butt at (x, y); the head at the far end, blade up."""
    pts_haft = xform([(0, 0), (56, 0)], x, y, rot, s, ox=0, oy=0)
    stroke(pts_haft, 7 * s, haft)
    head_pts = [(44, -4), (40, -24), (52, -20), (66, -26), (62, 4), (48, 5)]
    shape(xform(head_pts, x, y, rot, s), head)
    shape(xform([(40, -24), (52, -20), (66, -26), (65, -19), (52, -14), (42, -17)], x, y, rot, s), edge)


def sword_h(x0, y, x1, c_blade="ink", c_guard="ink2", c_grip="ink2", w=10):
    """A horizontal sword pointing right: grip from x0, guard, blade to x1."""
    g = x0 + 14
    rect(x0, y - 3.5, g, y + 3.5, c_grip, r=2)
    rect(g, y - 11, g + 5, y + 11, c_guard, r=1.5)
    shape([(g + 5, y - w / 2), (x1 - 9, y - w / 2), (x1, y), (x1 - 9, y + w / 2), (g + 5, y + w / 2)], c_blade)


def knife(x, y, rot, s, blade="ink", grip="ink2"):
    pts_b = [(22, -5), (54, -5), (64, 0), (54, 4), (22, 4)]
    shape(xform(pts_b, x, y, rot, s), blade)
    shape(xform(rrect_pts(0, -4, 20, 4, 3), x, y, rot, s), grip)
    shape(xform([(19, -8), (23, -8), (23, 8), (19, 8)], x, y, rot, s), grip)


def bow(cx, cy, h, c_limb="wd", c_string="ink2", flip=False, drawn=0.0):
    """Recurve-ish bow, belly to the left; drawn > 0 pulls the string right by that much."""
    sgn = -1 if flip else 1
    top, bot = (cx, cy - h / 2), (cx, cy + h / 2)
    limb = quad(top, (cx - sgn * h * 0.45, cy), bot, 18)
    tips = [(cx + sgn * 5, cy - h / 2 - 3), top]
    stroke(tips, 5, c_limb)
    stroke([bot, (cx + sgn * 5, cy + h / 2 + 3)], 5, c_limb)
    stroke(limb, 7, c_limb)
    if drawn:
        stroke([top, (cx + sgn * drawn, cy), bot], 2.2, c_string, cap="flat")
    else:
        stroke([top, bot], 2.2, c_string, cap="flat")
    rect(cx - sgn * h * 0.22 - 4, cy - 7, cx - sgn * h * 0.22 + 4, cy + 7, "lt", r=2)


def arrow_h(x0, x1, y, c="ink", fl="ink2", w=4.5):
    stroke([(x0 + 6, y), (x1 - 8, y)], w, c, cap="flat")
    arrowhead((x1, y), (x0, y), 12, c, 6.5)
    shape([(x0, y - 7), (x0 + 12, y - 1.5), (x0 + 12, y + 1.5), (x0, y + 7), (x0 + 4, y)], fl)


def flame(cx, by, s, c1="flame2", c2="flame", c3="sun"):
    outer = cubic((cx, by), (cx - 18 * s, by - 2 * s), (cx - 10 * s, by - 26 * s), (cx + 2 * s, by - 40 * s)) + \
        cubic((cx + 2 * s, by - 40 * s), (cx + 4 * s, by - 26 * s), (cx + 18 * s, by - 20 * s), (cx, by))[1:-1]
    shape(outer, c1)
    inner = cubic((cx, by), (cx - 10 * s, by - 2 * s), (cx - 6 * s, by - 16 * s), (cx + 1 * s, by - 26 * s)) + \
        cubic((cx + 1 * s, by - 26 * s), (cx + 3 * s, by - 16 * s), (cx + 10 * s, by - 12 * s), (cx, by))[1:-1]
    shape(inner, c2)
    shape(circle_pts(cx, by - 7 * s, 4 * s, 16), c3)


def feather(x, y, rot, s, c="ink", c2="ink2"):
    vane = quad((0, 0), (30, -16), (60, -2), 12) + quad((60, -2), (32, 10), (0, 0), 12)[1:-1]
    shape(xform(vane, x, y, rot, s), c)
    stroke(xform([(-8, 1), (58, -2)], x, y, rot, s), 2.4 * s, c2, cap="flat")
    # two notches
    shape(xform([(24, -10), (30, -11), (26, -4)], x, y, rot, s), c2)


def snowflake(cx, cy, r, c, w=6):
    for k in range(3):
        a = math.radians(90 + 60 * k)
        stroke([(cx - r * math.cos(a), cy - r * math.sin(a)), (cx + r * math.cos(a), cy + r * math.sin(a))], w, c)
    for k in range(6):
        a = math.radians(30 + 60 * k + 60)
        bx, by = cx + 0.62 * r * math.cos(a), cy + 0.62 * r * math.sin(a)
        for d in (-38, 38):
            b = a + math.radians(180 + d)
            stroke([(bx, by), (bx + 0.3 * r * math.cos(b) * -1, by + 0.3 * r * math.sin(b) * -1)], w * 0.7, c)


def crate_front(x0, y0, x1, y1, body, lid, lid_top, depth=10):
    """A chest seen slightly from above: top face parallelogram, then the front."""
    shape([(x0 + depth, y0 - depth * 0.6), (x1 + depth * 0.0, y0 - depth * 0.6), (x1, y0), (x0, y0)], lid_top)
    rect(x0, y0, x1, y1, body, r=2)


def shield_pts(cx, cy, w, h):
    hw = w / 2
    top = cy - h / 2
    return [(cx, top), (cx + hw, top + h * 0.12)] + cubic((cx + hw, top + h * 0.12), (cx + hw, top + h * 0.55), (cx + hw * 0.6, top + h * 0.85), (cx, top + h))[1:] + \
        cubic((cx, top + h), (cx - hw * 0.6, top + h * 0.85), (cx - hw, top + h * 0.55), (cx - hw, top + h * 0.12))[1:]


def chevron(cx, y, w, h, t, c):
    """A solid chevron (point up) with thickness t, top point at (cx, y)."""
    shape([(cx, y), (cx + w / 2, y + h), (cx + w / 2, y + h + t), (cx, y + t), (cx - w / 2, y + h + t), (cx - w / 2, y + h)], c)


def padlock(cx, cy, s, body="ink", shackle="ink", hole="dark"):
    stroke(arc_pts(cx, cy - 6 * s, 13 * s, 180, 360), 7 * s, shackle, cap="flat")
    stroke([(cx - 13 * s, cy - 6 * s), (cx - 13 * s, cy + 2 * s)], 7 * s, shackle, cap="flat")
    stroke([(cx + 13 * s, cy - 6 * s), (cx + 13 * s, cy + 2 * s)], 7 * s, shackle, cap="flat")
    rect(cx - 22 * s, cy - 2 * s, cx + 22 * s, cy + 32 * s, body, r=6 * s)
    circle(cx, cy + 12 * s, 4.5 * s, hole)
    rect(cx - 2 * s, cy + 13 * s, cx + 2 * s, cy + 22 * s, hole)


# =============================================================================================================
# Weapon skills (7)
@icon("WeaponSkills", "Head Kick")
def sk_head_kick():
    circle(28, 22, 8, "ink")
    stroke([(31, 34), (38, 58)], 10, "ink")                 # body
    stroke([(38, 58), (30, 88)], 10, "ink")                 # standing leg
    stroke([(34, 40), (18, 54)], 8, "ink")                  # arm back
    stroke([(38, 58), (60, 42), (82, 26)], 10, "ink")       # kicking leg
    arc(66, 46, 30, -120, -40, 4.5, "ink2")                 # the arc of the kick
    arc(66, 46, 38, -110, -55, 3.5, "ink3")


@icon("WeaponSkills", "Chained Strikes")
def sk_chained_strikes():
    stroke([(16, 70), (30, 46)], 7, "ink2")
    stroke([(34, 76), (52, 42)], 9, "ink")
    stroke([(56, 80), (80, 34)], 11, "ink")
    arrowhead((88, 20), (80, 34), 14, "ink", 9)
    stroke([(12, 88), (86, 88)], 4, "ink3")


@icon("WeaponSkills", "Running Cut")
def sk_running_cut():
    stroke([(8, 36), (26, 36)], 4.5, "ink3")
    stroke([(4, 50), (30, 50)], 4.5, "ink2")
    stroke([(8, 64), (26, 64)], 4.5, "ink3")
    sword_h(36, 50, 96, "ink", "ink2", "ink2", 11)


@icon("WeaponSkills", "Whirl")
def sk_whirl():
    pts = arc_pts(50, 50, 32, 120, 400)
    stroke(pts[:-2], 9, "ink")
    arrowhead(pts[-1], pts[-4], 15, "ink", 10)
    circle(50, 50, 9, "ink2", 24)
    for k in range(3):
        a = math.radians(-60 + 120 * k)
        stroke([(50 + 14 * math.cos(a), 50 + 14 * math.sin(a)), (50 + 21 * math.cos(a), 50 + 21 * math.sin(a))], 4.5, "ink3")


@icon("WeaponSkills", "Vault Kick")
def sk_vault_kick():
    stroke([(20, 92), (52, 12)], 6, "wd")
    shape([(52, 12), (49, 2), (58, 8)], "st")
    pts = quad((28, 64), (54, 2), (88, 46), 16)
    stroke(pts[:-1], 8, "ink")
    arrowhead(pts[-1], pts[-3], 14, "ink", 9)
    circle(84, 66, 6, "ink2")
    stroke([(14, 92), (40, 92)], 4, "ink3")


@icon("WeaponSkills", "Ricochet")
def sk_ricochet():
    stroke([(12, 22), (46, 74)], 8, "ink2")
    stroke([(46, 74), (82, 28)], 8, "ink")
    arrowhead((90, 18), (82, 28), 15, "ink", 10)
    shape(star_pts(46, 76, 12, 5, 4, -45), "sun")
    stroke([(22, 90), (72, 90)], 4, "ink3")


@icon("WeaponSkills", "Piercing Shot")
def sk_piercing_shot():
    rect(42, 18, 54, 82, "ink2", r=3)
    rect(44, 44, 52, 56, "dark", r=1)
    arrow_h(6, 96, 50, "ink", "ink2", 5)


# General skills (6)
@icon("GeneralSkills", "Concentration")
def sk_concentration():
    ring(50, 50, 32, 24, "ink")
    circle(50, 50, 9, "ink")
    for (a, b) in (((50, 6), (50, 20)), ((50, 80), (50, 94)), ((6, 50), (20, 50)), ((80, 50), (94, 50))):
        stroke([a, b], 6, "ink2")


@icon("GeneralSkills", "Second Wind")
def sk_second_wind():
    p1 = [(10, 40), (60, 40)] + arc_pts(60, 30, 10, 90, -200)[1:]
    stroke(p1, 8, "ink")
    p2 = [(10, 58), (72, 58)] + arc_pts(72, 68, 10, -90, 200)[1:]
    stroke(p2, 8, "ink")
    stroke([(22, 76), (48, 76)], 6, "ink2")
    stroke([(24, 22), (42, 22)], 5, "ink3")


@icon("GeneralSkills", "Sprint Burst")
def sk_sprint_burst():
    shape([(44, 8), (70, 8), (56, 40), (76, 40), (36, 92), (48, 54), (28, 54)], "ink")
    stroke([(8, 34), (24, 34)], 5, "ink2")
    stroke([(4, 50), (22, 50)], 5, "ink3")
    stroke([(8, 66), (20, 66)], 5, "ink2")


def footprint(cx, cy, rot, s, c):
    shape(xform(circle_pts(0, 6, 10, 24, ry=15), cx, cy, rot, s), c)
    for (dx, dy, r) in ((-9, -16, 3.6), (-3, -19, 3.8), (3.5, -19, 3.8), (9.5, -16, 3.4)):
        shape(xform(circle_pts(dx, dy, r, 12), cx, cy, rot, s), c)


@icon("GeneralSkills", "Quiet Step")
def sk_quiet_step():
    footprint(34, 66, -10, 1.15, "ink")
    footprint(66, 34, 10, 1.15, "ink2")
    for r, c in ((10, "ink3"),):
        arc(78, 70, r, -60, 60, 3.5, c)
        arc(78, 70, r + 8, -50, 50, 3.0, "ink3")


@icon("GeneralSkills", "Steady Hands")
def sk_steady_hands():
    for x, top in ((36, 22), (48, 16), (60, 18), (72, 26)):
        stroke([(x, 54), (x, top)], 11, "ink")
    stroke([(26, 70), (16, 50)], 11, "ink")
    shape(rrect_pts(30, 46, 78, 88, 14), "ink")
    stroke([(8, 94), (92, 94)], 4, "ink2")
    circle(50, 94, 4, "ink2")


@icon("GeneralSkills", "Brace")
def sk_brace():
    shape(shield_pts(50, 50, 64, 80), "ink")
    shape([(50, 16), (50, 84), (56, 82), (56, 18)], "ink2")
    stroke([(6, 34), (14, 34)], 5, "ink3")
    stroke([(4, 50), (14, 50)], 5, "ink3")
    stroke([(6, 66), (14, 66)], 5, "ink3")


# Kits (5)
@icon("Kits", "Archer")
def kit_archer():
    bow(34, 50, 78, "wd", "ink2", drawn=16)
    arrow_h(30, 94, 50, "ink", "ink2", 4.5)


@icon("Kits", "Forager")
def kit_forager():
    stroke(quad((50, 14), (46, 30), (34, 42)), 4, "wd2", cap="flat")
    stroke(quad((50, 14), (56, 32), (66, 44)), 4, "wd2", cap="flat")
    stroke(quad((50, 14), (50, 34), (50, 58)), 4, "wd2", cap="flat")
    shape(leaf_pts(50, 16, 30, 9, -20), "sage")
    shape(leaf_pts(50, 18, 26, 8, 200), "sage2")
    for (x, y, r, c) in ((32, 56, 14, "cop"), (66, 58, 14, "rust"), (49, 72, 15, "cop2")):
        circle(x, y, r, c, 28)
        circle(x - r * 0.35, y - r * 0.35, r * 0.22, "parch", 12)


@icon("Kits", "Trapper")
def kit_trapper():
    stroke([(6, 88), (94, 88)], 5, "ink3")
    shape([(22, 10), (32, 10), (32, 78), (27, 90), (22, 78)], "wd")
    shape([(27, 10), (32, 10), (32, 78), (27, 90)], "wd2")
    rect(19, 22, 35, 30, "lt", r=1.5)
    # the wire noose: a cord from the stake to a wide loop on the ground
    stroke(quad((34, 26), (56, 26), (58, 52), 10), 4.5, "ink2")
    loop = circle_pts(62, 70, 28, 36, ry=13)
    stroke(loop + [loop[0]], 5, "ink", cap="flat")
    rect(55, 50, 63, 58, "ink2", r=2)


@icon("Kits", "Medic")
def kit_medic():
    rect(36, 18, 64, 30, "ink2", r=3)
    rect(16, 26, 84, 82, "ink", r=8)
    rect(43, 36, 57, 72, "dark", r=1.5)
    rect(32, 47, 68, 61, "dark", r=1.5)


@icon("Kits", "Climber")
def kit_climber():
    shape([(6, 88), (44, 18), (60, 46), (70, 34), (96, 88)], "st2")
    shape([(44, 18), (54, 36), (48, 32), (42, 40), (37, 31)], "ink")
    shape([(70, 34), (77, 47), (71, 44), (66, 41)], "ink2")
    # a climbing pick on top
    stroke([(22, 84), (54, 58)], 5, "wd")
    shape([(50, 50), (66, 58), (76, 54), (64, 64), (52, 62)], "ink")


# Traits (12)
@icon("Traits", "Unseen")
def tr_unseen():
    eye = quad((8, 50), (50, 10), (92, 50), 16) + quad((92, 50), (50, 90), (8, 50), 16)[1:-1]
    shape(eye, "ink2")
    circle(50, 50, 15, "dark")
    circle(50, 50, 6, "ink3")
    stroke([(16, 86), (84, 14)], 8, "ink")


@icon("Traits", "Quiet Swish")
def tr_quiet_swish():
    arc(22, 82, 58, -82, -8, 7, "ink2")
    arc(22, 82, 46, -80, -12, 4, "ink3")
    knife(66, 70, -60, 0.62, "ink", "ink2")
    for i, r in enumerate((4.5, 3.5, 2.5)):
        circle(18 + i * 12, 30 - i * 6, r, "ink3", 12)


@icon("Traits", "Second in the Arc")
def tr_second_in_arc():
    for (x, c, s) in ((28, "ink", 1.0), (72, "ink2", 0.85)):
        circle(x, 92 - 32 * s, 9 * s, c, 24)
        shape(rrect_pts(x - 15 * s, 92 - 20 * s, x + 15 * s, 96, 8 * s), c)
    pts = arc_pts(50, 70, 44, 200, 340)
    stroke(pts[:-1], 7, "ink")
    arrowhead(pts[-1], pts[-3], 13, "ink", 8)


@icon("Traits", "Heavy Throw")
def tr_heavy_throw():
    dashed(quad((10, 84), (30, 10), (64, 30), 18), 5, "ink3", 7, 6)
    hatchet(56, 60, -50, 0.75, "ink", "ink2", "st")
    for x in (64, 76, 88):
        stroke([(x, 82), (x - 4, 92)], 4.5, "ink2")


@icon("Traits", "Splits Firewood")
def tr_splits_firewood():
    shape(arc_pts(40, 64, 24, 90, 270, 16), "wd")
    shape(arc_pts(60, 64, 24, -90, 90, 16), "wd")
    shape(arc_pts(40, 64, 15, 90, 270, 12), "#A88462")
    shape(arc_pts(60, 64, 15, -90, 90, 12), "#A88462")
    shape(arc_pts(40, 64, 6, 90, 270, 8), "wd2")
    shape(arc_pts(60, 64, 6, -90, 90, 8), "wd2")
    shape([(38, 10), (62, 10), (58, 30), (50, 48), (42, 30)], "st")
    shape([(42, 30), (50, 48), (58, 30), (54, 34), (50, 40), (46, 34)], "ink")
    stroke([(50, 10), (50, 2)], 6, "wd")


@icon("Traits", "Long Reach")
def tr_long_reach():
    stroke([(6, 40), (76, 40)], 6, "wd", cap="flat")
    shape([(74, 33), (96, 40), (74, 47)], "ink")
    rect(68, 34, 76, 46, "br")
    stroke([(14, 68), (86, 68)], 4.5, "ink2", cap="flat")
    arrowhead((6, 68), (20, 68), 11, "ink2", 7)
    arrowhead((94, 68), (80, 68), 11, "ink2", 7)
    stroke([(6, 58), (6, 78)], 3.5, "ink3")
    stroke([(94, 58), (94, 78)], 3.5, "ink3")


@icon("Traits", "Big Throw")
def tr_big_throw():
    dashed(quad((6, 86), (40, 0), (72, 30), 18), 5, "ink3", 7, 6)
    pts = [(56, 22), (90, 62)]
    stroke(pts, 5.5, "wd", cap="flat")
    arrowhead((96, 70), (56, 22), 16, "ink", 7)
    for x in (24, 36):
        stroke([(x, 90), (x + 52, 90)], 3, "ink3")
        break


@icon("Traits", "Armour-breaker")
def tr_armour_breaker():
    shape(shield_pts(50, 52, 66, 80), "ink2")
    shape([(50, 12), (34, 40), (52, 50), (38, 78), (44, 80), (60, 52), (44, 42), (56, 12)], "dark")
    shape([(66, 18), (84, 22), (82, 36)], "ink3")


@icon("Traits", "Spinning Throw")
def tr_spinning_throw():
    shape([(50, 50), (34, 28), (40, 22), (50, 34), (60, 22), (66, 28)], "ink")
    shape([(50, 50), (34, 72), (40, 78), (50, 66), (60, 78), (66, 72)], "ink")
    rect(46, 30, 54, 70, "wd", r=2)
    for a0 in (200, 20):
        pts = arc_pts(50, 50, 38, a0, a0 + 110)
        stroke(pts[:-1], 6, "ink2")
        arrowhead(pts[-1], pts[-3], 12, "ink2", 8)


@icon("Traits", "Flat Throw")
def tr_flat_throw():
    shape([circle_pts(62, 50, 26, 40, ry=11), circle_pts(62, 50, 17, 40, ry=6.5)], "ink")
    rect(52, 47, 72, 53, "ink2", r=1.5)
    stroke([(6, 42), (30, 42)], 4.5, "ink3")
    stroke([(2, 50), (32, 50)], 4.5, "ink2")
    stroke([(6, 58), (30, 58)], 4.5, "ink3")


@icon("Traits", "Climb")
def tr_climb():
    shape([(58, 4), (96, 4), (96, 96), (52, 96), (60, 70), (50, 46), (62, 26)], "st2")
    shape([(62, 26), (50, 46), (56, 44), (66, 28)], "st3")
    stroke([(14, 86), (46, 40)], 6, "wd")
    shape([(38, 36), (62, 46), (66, 40), (46, 30)], "ink")
    chevron(24, 20, 22, 11, 6, "ink2")
    chevron(24, 34, 22, 11, 6, "ink3")


@icon("Traits", "Draw Range")
def tr_draw_range():
    bow(30, 50, 76, "wd", "ink2", drawn=-14)
    stroke([(18, 50), (62, 50)], 4, "ink", cap="flat")
    arrowhead((70, 50), (20, 50), 11, "ink", 6.5)
    ring(84, 50, 12, 7, "ink2", 28)
    circle(84, 50, 3.5, "sun", 12)


# Currencies and consumables (5)
@icon("Currencies", "Gold")
def cur_gold():
    circle(52, 55, 35, "br2", 44)
    circle(50, 50, 35, "br", 44)
    ring(50, 50, 27, 23, "br2", 44)
    shape(star_pts(50, 50, 15, 6, 4, -90), "br2")


@icon("Currencies", "Lucky Acorn")
def cur_acorn():
    nut = cubic((26, 46), (24, 70), (40, 86), (50, 92)) + cubic((50, 92), (60, 86), (76, 70), (74, 46))[1:]
    shape(nut, "leaf")
    shape([(50, 92), (44, 82), (50, 84), (56, 82)], "wd2")
    cap = quad((20, 48), (50, 6), (80, 48), 16) + quad((80, 48), (50, 58), (20, 48), 10)[1:-1]
    shape(cap, "wd2")
    for x in (34, 46, 58):
        stroke([(x, 26), (x + 10, 48)], 2.2, "lt", cap="flat")
    stroke([(50, 18), (54, 6), (62, 2)], 5, "wd2")
    shape(star_pts(80, 22, 10, 3.5, 4), "sun")


@icon("Currencies", "Wheel Spin")
def cur_spin_token():
    circle(50, 52, 38, "br", 48)
    for k in range(6):
        a0 = -90 + 60 * k
        pts = [(50, 52)] + arc_pts(50, 52, 31, a0, a0 + 60, 8)
        shape(pts, "ox" if k % 2 == 0 else "cream")
    circle(50, 52, 7, "br")
    circle(50, 52, 3, "br2", 12)
    shape([(42, 6), (58, 6), (50, 22)], "ink")


@icon("Currencies", "XP")
def cur_xp():
    shape(star_pts(50, 52, 42, 18, 5), "ink")
    shape(star_pts(50, 52, 18, 8, 5), "ink2")


@icon("Currencies", "Daily Stamp")
def cur_daily_stamp():
    ring(50, 50, 40, 33, "sun", 48)
    dashed(arc_pts(50, 50, 27, 0, 360, 48), 3, "sun", 5, 4, cap="flat")
    text("7", 50, 51, 34, "sun")


# Cases (9)
@icon("Cases", "Timber Crate")
def case_timber():
    crate_front(14, 34, 80, 84, "wd", "wd2", "wd2", 10)
    for y in (50, 67):
        stroke([(14, y), (80, y)], 2.5, "wd2", cap="flat")
    rect(14, 34, 20, 84, "wd2")
    rect(74, 34, 80, 84, "wd2")
    for x in (8, 86):
        stroke(arc_pts(x, 52, 7, 90, 270) if x < 50 else arc_pts(x, 52, 7, -90, 90), 3.5, "ink2", cap="flat")


@icon("Cases", "Ironbound Crate")
def case_ironbound():
    crate_front(14, 34, 80, 84, "wd", "wd2", "wd2", 10)
    for y in (50, 67):
        stroke([(14, y), (80, y)], 2.5, "wd2", cap="flat")
    for x in (24, 62):
        shape([(x, 34), (x + 8, 34), (x + 8 + 10, 28), (x + 10, 28)], "st3")
        rect(x, 34, x + 8, 84, "st2")
        for y in (40, 58, 76):
            circle(x + 4, y, 1.8, "st", 10)
    rect(43, 36, 51, 46, "st", r=1)


@icon("Cases", "Steel Crate")
def case_steel():
    shape([(24, 26), (90, 26), (80, 34), (14, 34)], "st")
    rect(14, 34, 80, 84, "st2", r=2)
    stroke([(14, 52), (80, 52)], 3, "st3", cap="flat")
    for x in (19, 75):
        for y in (40, 58, 78):
            circle(x, y, 2, "st", 10)
    rect(41, 38, 53, 52, "br", r=1.5)
    rect(45, 44, 49, 49, "br2")


@icon("Cases", "Silverleaf Crate")
def case_silverleaf():
    shape([(24, 26), (90, 26), (80, 34), (14, 34)], "silver2")
    rect(14, 34, 80, 84, "silver", r=2)
    stroke([(14, 50), (80, 50)], 2.5, "silver3", cap="flat")
    shape(leaf_pts(26, 74, 26, 9, -35), "silver3")
    shape(leaf_pts(50, 74, 22, 8, -60), "silver3")
    rect(41, 36, 53, 48, "st2", r=1.5)


@icon("Cases", "Crown Crate")
def case_crown():
    shape([(24, 26), (90, 26), (80, 34), (14, 34)], "crown2")
    rect(14, 34, 80, 80, "crown", r=2)
    rect(12, 78, 82, 86, "br2", r=1)
    shape([(32, 68), (32, 52), (40, 60), (47, 46), (54, 60), (62, 52), (62, 68)], "br")
    for x in (32, 47, 62):
        circle(x, 50 if x != 47 else 44, 2.5, "br", 10)


@icon("Cases", "Strongbox")
def case_strongbox():
    shape([(22, 22), (88, 22), (80, 32), (14, 32)], "st")
    rect(14, 32, 80, 86, "st2", r=3)
    rect(14, 32, 80, 44, "st", r=2)
    stroke([(34, 22), (34, 14), (60, 14), (60, 22)], 4, "dk", cap="flat")
    for x in (26, 41, 56):
        rect(x, 54, x + 10, 70, "dk", r=2)
        stroke([(x + 5, 57), (x + 5, 67)], 2, "st", cap="flat")


@icon("Cases", "Masterwork Strongbox")
def case_masterwork():
    shape([(22, 22), (88, 22), (80, 32), (14, 32)], "crown2")
    rect(14, 32, 80, 86, "dk", r=3)
    rect(14, 32, 80, 44, "crown2", r=2)
    rect(14, 76, 80, 82, "br")
    stroke([(34, 22), (34, 14), (60, 14), (60, 22)], 4, "br2", cap="flat")
    for x in (26, 41, 56):
        rect(x, 52, x + 10, 68, "br", r=2)
        stroke([(x + 5, 55), (x + 5, 65)], 2, "br2", cap="flat")
    for (x, y) in ((14, 32), (80, 32), (14, 86), (80, 86)):
        shape(circle_pts(x, y, 5, 4, math.pi / 4), "br")


@icon("Cases", "Prize Wheel")
def case_wheel():
    rect(46, 84, 54, 96, "wd2")
    rect(30, 92, 70, 97, "wd")
    circle(50, 50, 40, "br", 52)
    for k in range(6):
        a0 = -90 + 60 * k
        shape([(50, 50)] + arc_pts(50, 50, 34, a0, a0 + 60, 9), "ox" if k % 2 == 0 else "cream")
    circle(50, 50, 8, "br")
    shape([(43, 2), (57, 2), (50, 16)], "ink")


@icon("Cases", "Armoury")
def case_armoury():
    rect(12, 14, 88, 90, "wd2", r=3)
    rect(12, 70, 88, 78, "wd")
    rect(12, 22, 88, 28, "wd")
    stroke([(28, 82), (34, 18)], 5, "st")
    rect(24, 64, 36, 68, "lt")
    stroke([(50, 84), (50, 26)], 4, "wd")
    shape([(44, 30), (50, 10), (56, 30)], "st")
    stroke([(72, 84), (66, 30)], 4, "wd")
    shape([(62, 34), (60, 18), (76, 18), (74, 34)], "st")


# Ranks (10 + Prestige), 512 px
RANKS = [
    ("rank_recruit", "Recruit", "stone", "stone2", 1, 0),
    ("rank_runner", "Runner", "stone", "stone2", 2, 0),
    ("rank_scout", "Scout", "cop", "cop2", 1, 1),
    ("rank_tracker", "Tracker", "cop", "cop2", 2, 1),
    ("rank_pathfinder", "Pathfinder", "st", "st2", 1, 2),
    ("rank_ranger", "Ranger", "st", "st2", 2, 2),
    ("rank_warden", "Warden", "br", "br2", 2, 3),
    ("rank_vanguard", "Vanguard", "br", "br2", 3, 3),
    ("rank_sentinel", "Sentinel", "moon", "moon2", 3, 4),
    ("rank_paragon", "Paragon", "parch", "parch2", 3, 5),
]


def _rank(c1, c2, chevrons, tier):
    if tier >= 2:   # wings
        for sgn in (-1, 1):
            for k in range(3):
                y = 30 + k * 12
                shape([(50 + sgn * 30, y), (50 + sgn * (46 - k * 3), y - 4 + k), (50 + sgn * (44 - k * 4), y + 6), (50 + sgn * 30, y + 9)], c2)
    if tier >= 3:   # laurel sprigs low on the sides
        for sgn in (-1, 1):
            stroke(arc_pts(50, 52, 40, 105, 165) if sgn < 0 else arc_pts(50, 52, 40, 75, 15), 2.6, "br2" if tier == 3 else c2)
            for k in range(4):
                a = math.radians(110 + k * 18) if sgn < 0 else math.radians(70 - k * 18)
                x, y = 50 + 42 * math.cos(a), 52 + 42 * math.sin(a)
                shape(leaf_pts(x, y, 13, 4.5, math.degrees(a) + (90 if sgn < 0 else -90) + sgn * 30), "br2" if tier == 3 else c2)
    if tier >= 1:
        shape(shield_pts(50, 50, 66, 82), c2)
        shape(shield_pts(50, 51, 56, 70), c1)
    else:
        shape(shield_pts(50, 50, 62, 78), c1)
    shape([(50, 16), (50, 84)] + list(reversed(shield_pts(50, 51, 56, 70)[6:])), c1)
    # inner half shade for the faceted read
    sp = shield_pts(50, 51, 52 if tier >= 1 else 58, 66 if tier >= 1 else 74)
    right = [p for p in sp if p[0] >= 50 - 1e-6]
    shape(right, c2 if tier < 4 else c2)
    y0 = 62 - (chevrons - 1) * 7
    for k in range(chevrons):
        chevron(50, y0 + k * 13 - 12, 34, 12, 7, "dark")
    if tier >= 4:
        shape(star_pts(50, 30, 9, 4, 5), "dark")
    if tier >= 5:
        shape([(30, 10), (38, 2), (44, 10), (50, 0), (56, 10), (62, 2), (70, 10), (66, 14), (34, 14)], c2)


def _make_rank(rid, name, c1, c2, n, tier):
    def fn():
        _rank(c1, c2, n, tier)
    fn.__name__ = rid
    ICONS[rid] = dict(group="Ranks", name=name, kind="rank", fn=fn)


for _r in RANKS:
    _make_rank(*_r)


@icon("Ranks", "Prestige", "rank")
def rank_prestige():
    ring(50, 50, 44, 36, "br2", 56)
    for k in range(12):
        a = math.radians(-90 + 30 * k)
        shape(xform([(0, -3), (8, 0), (0, 3)], 50 + 40 * math.cos(a), 50 + 40 * math.sin(a), math.degrees(a) + 90 - 90), "br")
    shape(star_pts(50, 52, 34, 15, 5), "br")
    shape([(50, 52)] + [p for p in star_pts(50, 52, 34, 15, 5)][0:6], "br2")
    shape(star_pts(50, 52, 12, 5.5, 5), "parch")


# Kill icons (5) - these are the items themselves
@icon("KillIcons", "Crossed Axes")
def ki_crossed_axes():
    circle(50, 50, 42, "lt", 48)
    ring(50, 50, 42, 37, "wd2", 48)
    hatchet(22, 80, -45, 0.82, "st", "st2", "ink2")
    # mirrored hatchet
    stroke([(78, 80), (78 - 33, 80 - 33)], 5.8, "st2")
    head = [(44, -4), (40, -24), (52, -20), (66, -26), (62, 4), (48, 5)]
    head = [(-x, y) for x, y in head]
    shape(xform(head, 78, 80, 45, 0.82), "st")
    shape(xform([(-40, -24), (-52, -20), (-66, -26), (-65, -19), (-52, -14), (-42, -17)], 78, 80, 45, 0.82), "ink2")


@icon("KillIcons", "Compass Star")
def ki_compass_star():
    ring(50, 50, 30, 26, "br2", 44)
    shape(star_pts(50, 50, 30, 9, 4, -45), "br2")
    shape(star_pts(50, 50, 44, 10, 4, -90), "br")
    for k in range(4):
        a = -90 + 90 * k
        tip = (50 + 44 * math.cos(math.radians(a)), 50 + 44 * math.sin(math.radians(a)))
        side = (50 + 10 * math.cos(math.radians(a + 45)), 50 + 10 * math.sin(math.radians(a + 45)))
        shape([(50, 50), tip, side], "br2")
    circle(50, 50, 5, "parch", 16)


WOLF = [(22, 88), (20, 60), (24, 40), (28, 12), (42, 30), (50, 26), (60, 30), (84, 44), (93, 52), (88, 58),
        (72, 62), (60, 64), (54, 74), (52, 90)]


@icon("KillIcons", "Wolf Head")
def ki_wolf_head():
    cx, cy = 56, 52
    big = [(cx + (x - cx) * 1.12, cy + (y - cy) * 1.1) for x, y in WOLF]
    shape(big, "cream")
    shape(WOLF, "slate")
    shape([(28, 18), (40, 32), (32, 38)], "slate2")
    shape([(60, 30), (84, 44), (93, 52), (88, 58), (72, 58), (66, 46)], "slate2")
    shape(circle_pts(88, 52, 3, 8), "dark")
    shape([(52, 40), (62, 38), (58, 44)], "cream")
    shape([(30, 70), (40, 60), (48, 72), (40, 86)], "slate2")


@icon("KillIcons", "Laurel")
def ki_laurel():
    for sgn in (-1, 1):
        pts = arc_pts(50, 50, 38, 100, 250) if sgn < 0 else arc_pts(50, 50, 38, 80, -70)
        stroke(pts, 4, "br2")
        for k, (x, y) in enumerate(pts[1::2]):
            a = math.degrees(math.atan2(y - 50, x - 50))
            shape(leaf_pts(x, y, 15, 5.5, a + (90 if sgn < 0 else -90) + sgn * 35), "br")
    text("48", 50, 51, 30, "ink")


@icon("KillIcons", "Horned Helm")
def ki_horned_helm():
    ring(50, 52, 44, 39, "moon", 56)
    for k in range(10):
        a = math.radians(-90 + 36 * k + 18)
        shape(star_pts(50 + 41.5 * math.cos(a), 52 + 41.5 * math.sin(a), 6, 2, 3, math.degrees(a)), "moon2")
    for sgn in (-1, 1):
        horn = cubic((50 + sgn * 18, 38), (50 + sgn * 36, 36), (50 + sgn * 40, 22), (50 + sgn * 34, 8)) + \
            cubic((50 + sgn * 34, 8), (50 + sgn * 30, 20), (50 + sgn * 26, 26), (50 + sgn * 16, 28))[1:]
        shape(horn, "cream")
    dome = [(28, 74), (28, 48)] + arc_pts(50, 48, 22, 180, 360, 14)[1:] + [(72, 74), (60, 74), (60, 58), (40, 58), (40, 74)]
    shape(dome, "st")
    rect(26, 44, 74, 50, "br", r=1)
    rect(47, 50, 53, 70, "st2")
    shape([p for p in dome if p[0] >= 50], "st2")


# Kill effects (9)
@icon("KillEffects", "Ash Scatter")
def ke_ash_scatter():
    circle(26, 26, 9, "ink2")
    shape([(14, 92), (16, 48), (24, 38), (32, 38), (40, 50), (36, 92)], "ink2")
    import random
    rng = random.Random(4)
    for i in range(16):
        x = 40 + i * 3.4 + rng.uniform(-3, 3)
        y = 70 - i * 3.2 + rng.uniform(-10, 10)
        s = 5.5 - i * 0.25
        shape(xform([(-s, -s * 0.6), (s, -s * 0.8), (s * 0.7, s * 0.7), (-s * 0.8, s * 0.5)], x, y, rng.uniform(0, 90)),
              "ink2" if i < 6 else "ink3")


@icon("KillEffects", "Petal Fall")
def ke_petal_fall():
    dashed(arc_pts(50, 54, 36, -40, 200), 3, "ink3", 5, 6)
    for (x, y, r, s) in ((40, 10, 40, 1.0), (78, 30, 120, 0.9), (70, 72, 190, 1.1), (18, 66, 290, 0.85), (40, 42, 70, 1.25)):
        shape(leaf_pts(x, y, 26 * s, 12 * s, r), "cream")
        shape(leaf_pts(x, y, 13 * s, 4.5 * s, r), "parch2")


@icon("KillEffects", "Leaf Swirl")
def ke_leaf_swirl():
    pts = [(50 + (8 + t * 0.38) * math.cos(math.radians(t * 4.2)), 50 + (8 + t * 0.38) * math.sin(math.radians(t * 4.2))) for t in range(0, 100, 2)]
    stroke(pts, 3.5, "ink3")
    for (x, y, r, c) in ((80, 40, -30, "cop"), (40, 86, 140, "leaf"), (16, 46, 220, "rust"), (58, 20, -100, "br2"), (60, 58, 10, "cop2")):
        shape(leaf_pts(x, y, 22, 8, r), c)
        stroke(xform([(0, 0), (16, 0)], x, y, r), 1.6, "lt", cap="flat")


@icon("KillEffects", "Paper Confetti")
def ke_paper_confetti():
    import random
    rng = random.Random(7)
    cols = ["sun", "ink", "cop", "sage", "slate", "parch"]
    pos = [(26, 22), (56, 14), (80, 30), (18, 50), (46, 42), (74, 56), (30, 76), (58, 72), (86, 80), (44, 92), (12, 84), (68, 34)]
    for i, (x, y) in enumerate(pos):
        w, h = rng.uniform(9, 13), rng.uniform(5, 7)
        shape(xform([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)], x, y, rng.uniform(-60, 60)), cols[i % len(cols)])


@icon("KillEffects", "Feather Burst")
def ke_feather_burst():
    feather(14, 76, -40, 1.0, "ink", "ink2")
    feather(40, 88, -75, 0.75, "ink2", "ink3")
    feather(54, 70, -15, 0.65, "st", "st2")
    for (x, y) in ((80, 22), (70, 12), (88, 40)):
        circle(x, y, 2.6, "ink3", 10)


@icon("KillEffects", "Bell Toll")
def ke_bell_toll():
    shape([circle_pts(50, 84, 42, 40, ry=10), circle_pts(50, 84, 34, 40, ry=7)], "ink3")
    bell = [(26, 70)] + cubic((26, 70), (30, 60), (28, 28), (50, 22))[1:] + cubic((50, 22), (72, 28), (70, 60), (74, 70))[1:]
    shape(bell, "br")
    shape([p for p in bell if p[0] >= 54] + [(70, 70)], "br2")
    rect(20, 68, 80, 75, "br2", r=3)
    circle(50, 80, 6, "br2", 16)
    stroke(arc_pts(50, 20, 6, 180, 360), 4, "br2", cap="flat")
    arc(50, 44, 40, -150, -120, 4, "ink2")
    arc(50, 44, 40, -60, -30, 4, "ink2")


@icon("KillEffects", "Flag Drop")
def ke_flag_drop():
    stroke([(8, 92), (92, 92)], 4, "ink3")
    shape([(32, 92), (30, 14), (36, 14), (38, 92)], "wd")
    circle(33, 12, 4, "br", 12)
    flag = [(37, 18)] + quad((37, 18), (60, 12), (86, 22))[1:] + [(76, 34), (86, 46)] + quad((86, 46), (60, 38), (37, 46))[1:]
    shape(flag, "cream")
    shape([(37, 26), (82, 28), (80, 34), (37, 34)], "slate")


@icon("KillEffects", "Frost Over")
def ke_frost_over():
    snowflake(50, 46, 36, "moon", 6)
    shape([circle_pts(50, 90, 30, 30, ry=6)], "moon2")


@icon("KillEffects", "Recall Beam")
def ke_recall_beam():
    shape([circle_pts(50, 86, 34, 36, ry=8), circle_pts(50, 86, 26, 36, ry=5.5)], "ink2")
    rect(36, 4, 64, 88, "parch", r=8)
    rect(42, 4, 58, 88, "ink", r=6)
    circle(50, 36, 5, "ink3", 16)
    stroke([(50, 44), (50, 60)], 6, "ink3")
    for (x, y) in ((26, 30), (74, 50), (24, 60), (78, 20)):
        shape(star_pts(x, y, 5, 1.6, 4), "ink2")


# Emotes (5)
@icon("Emotes", "Whetstone")
def em_whetstone():
    shape([(8, 64), (66, 30), (82, 26), (70, 40), (12, 72)], "st")
    shape([(12, 72), (70, 40), (82, 26), (72, 44), (16, 76)], "st2")
    shape(xform(rrect_pts(-14, -8, 14, 8, 3), 52, 56, -30), "stone2")
    shape(xform(rrect_pts(-14, -8, 14, -1, 2), 52, 56, -30), "stone")
    rect(6, 70, 26, 80, "lt", r=3)
    for d in (0, 10):
        stroke([(62 + d, 70), (70 + d, 64)], 3, "ink3")


@icon("Emotes", "Blade Twirl")
def em_blade_twirl():
    pts = arc_pts(50, 50, 36, -60, 230)
    stroke(pts[:-1], 5.5, "ink2")
    arrowhead(pts[-1], pts[-3], 12, "ink2", 8)
    knife(32, 66, -45, 0.85, "ink", "wd")


@icon("Emotes", "Map Check")
def em_map_check():
    xs = [10, 37, 63, 90]
    for i in range(3):
        y0 = 20 if i % 2 == 0 else 26
        y1 = 80 if i % 2 == 0 else 86
        shape([(xs[i], y0), (xs[i + 1], 26 if i % 2 == 0 else 20), (xs[i + 1], 86 if i % 2 == 0 else 80), (xs[i], y1)], "parch" if i % 2 == 0 else "parch2")
    dashed([(18, 70), (32, 52), (50, 60), (66, 40), (78, 44)], 3, "wd2", 5, 4)
    stroke([(76, 36), (86, 46)], 3.5, "ox")
    stroke([(86, 36), (76, 46)], 3.5, "ox")


@icon("Emotes", "Campfire Hands")
def em_campfire_hands():
    stroke([(22, 90), (78, 76)], 8, "wd")
    stroke([(22, 76), (78, 90)], 8, "wd2")
    flame(50, 82, 1.1)
    for sgn in (-1, 1):
        palm = [(50 + sgn * 22, 46), (50 + sgn * 42, 40), (50 + sgn * 46, 48), (50 + sgn * 44, 58), (50 + sgn * 24, 58)]
        shape(palm, "ink2")
        for k in range(3):
            stroke([(50 + sgn * 24, 46 + k * 5), (50 + sgn * 14, 44 + k * 5.5)], 4, "ink2")


@icon("Emotes", "Last One Standing")
def em_last_one_standing():
    shape([(4, 70), (24, 56), (40, 64), (62, 50), (96, 66), (96, 70)], "ink3")
    shape(circle_pts(50, 92, 40, 30, ry=8), "stone2")
    shape([(46, 30), (54, 30), (54, 80), (50, 90), (46, 80)], "st")
    shape([(50, 30), (54, 30), (54, 80), (50, 90)], "st2")
    rect(34, 24, 66, 30, "ink2", r=2)
    rect(46, 8, 54, 24, "lt", r=2)
    circle(50, 6, 5, "br", 14)


# Launch effects (4)
@icon("LaunchEffects", "Steam Vent")
def le_steam_vent():
    shape([(14, 92), (22, 74), (78, 74), (86, 92)], "st2")
    rect(22, 70, 78, 76, "st", r=1)
    for x in (26, 42, 58, 74):
        rect(x - 2, 80, x + 2, 88, "dark")
    for (x, y, r) in ((30, 58, 10), (44, 48, 13), (60, 52, 11), (72, 40, 9), (52, 30, 12), (34, 32, 8), (62, 18, 8)):
        circle(x, y, r, "ink", 24)


@icon("LaunchEffects", "Dust Ring")
def le_dust_ring():
    shape([circle_pts(50, 76, 46, 40, ry=16), circle_pts(50, 76, 30, 40, ry=9)], "stone")
    for k in range(9):
        a = math.radians(180 + k * 22.5 - 90 + 90)
        x, y = 50 + 42 * math.cos(math.radians(-180 + k * 22.5)), 76 + 14 * math.sin(math.radians(-180 + k * 22.5))
        circle(x, y - 6, 6 + (k % 3), "ink2", 16)
    rect(30, 52, 70, 74, "st2", r=2)
    shape(circle_pts(50, 52, 20, 30, ry=5), "st")


@icon("LaunchEffects", "Leaf Ring")
def le_leaf_ring():
    shape(circle_pts(50, 86, 26, 30, ry=6), "st2")
    pts = [(50 + 30 * math.cos(math.radians(t * 9)), 84 - t * 0.8 + 5 * math.sin(math.radians(t * 9))) for t in range(0, 90, 2)]
    stroke(pts, 3.5, "ink3")
    for i, t in enumerate((6, 26, 46, 66, 84)):
        x, y = pts[t // 2]
        shape(leaf_pts(x, y, 18, 6.5, -40 + i * 50), ["cop", "leaf", "sage", "rust", "br2"][i])


@icon("LaunchEffects", "Banner Unfurl")
def le_banner_unfurl():
    stroke([(30, 94), (30, 8)], 5, "wd")
    circle(30, 7, 4, "br", 12)
    rect(28, 14, 80, 18, "wd2", r=1)
    shape([(32, 18), (78, 18), (78, 70), (55, 82), (32, 70)], "slate")
    shape([(55, 18), (78, 18), (78, 70), (55, 82)], "slate2")
    shape(circle_pts(55, 44, 9, 4, 0), "br")


# Pass and UI marks (6)
@icon("UI", "Season Title")
def ui_title_tag():
    shape([(8, 34), (80, 34), (94, 50), (80, 66), (8, 66), (18, 50)], "ink2")
    circle(78, 50, 4.5, "dark", 14)
    stroke([(26, 50), (60, 50)], 5, "ink3", cap="flat")


@icon("UI", "Banner Trim")
def ui_banner_trim():
    rect(6, 26, 94, 72, "slate2", r=3)
    rect(6, 66, 94, 76, "br", r=2)
    for x in (14, 50, 86):
        circle(x, 71, 2, "br2", 10)


@icon("UI", "Numbered")
def ui_numbered_seal():
    shape(star_pts(50, 50, 42, 36, 16, -90), "moon2")
    circle(50, 50, 33, "moon", 40)
    text("#", 50, 52, 38, "dark")


@icon("UI", "Locked")
def ui_padlock():
    padlock(50, 40, 1.35, "ink", "ink", "dark")


@icon("UI", "Owned")
def ui_tick():
    stroke([(18, 54), (40, 76), (84, 26)], 13, "ink")


@icon("UI", "None")
def ui_none():
    ring(50, 50, 36, 27, "ink3", 48)
    stroke([(26, 74), (74, 26)], 9, "ink3", cap="flat")


# =============================================================================================================
# Banners (768 x 256; 300 x 100 design units, the whole canvas)
BANNERS = {}


def banner(name, overlay=False):
    def deco(fn):
        BANNERS[fn.__name__] = dict(group="Banners" if not overlay else "Trims", name=name, kind="banner", fn=fn)
        return fn
    return deco


@banner("Linen")
def bn_linen():
    rect(0, 0, 300, 100, "cream")
    for y in range(10, 100, 12):
        stroke([(4, y), (296, y)], 1.0, "#E6DCC6", cap="flat")
    dashed([(8, 8), (292, 8), (292, 92), (8, 92), (8, 8)], 2.0, "ink3", 6, 4, cap="flat")


@banner("Oak and Iron")
def bn_oak_iron():
    tones = ["wd", "#7C5D42", "#97734F", "wd2", "#86664A"]
    for i in range(5):
        rect(0, i * 20, 300, i * 20 + 20, tones[i])
        stroke([(0, i * 20 + 19.5), (300, i * 20 + 19.5)], 1.2, "lt", cap="flat")
    for x in (52, 248):
        rect(x - 9, 0, x + 9, 100, "st2")
        rect(x - 9, 0, x + 1, 100, "st3")
        for y in (10, 30, 50, 70, 90):
            circle(x, y, 2.6, "st", 10)


@banner("Mountain Dawn")
def bn_mountain_dawn():
    rect(0, 0, 300, 100, "#E8B48A")
    rect(0, 0, 300, 34, "#E9C49E")
    circle(210, 58, 14, "#F2D7AE", 32)
    shape([(0, 100), (0, 62), (40, 40), (70, 56), (110, 30), (160, 60), (200, 44), (250, 64), (300, 46), (300, 100)], "#8C9DB8")
    shape([(0, 100), (0, 76), (50, 58), (90, 74), (140, 52), (190, 76), (240, 60), (300, 78), (300, 100)], "#6C7FA0")
    shape([(0, 100), (0, 88), (70, 78), (130, 90), (200, 80), (260, 92), (300, 86), (300, 100)], "#4E5F7C")
    shape([(110, 30), (122, 38), (114, 37), (106, 40), (101, 36)], "cream")


@banner("The First Ride")
def bn_first_ride():
    rect(0, 0, 300, 100, "cream")
    shape([(0, 100), (0, 84), (300, 84), (300, 100)], "parch2")
    # trestle
    rect(30, 60, 270, 64, "wd2")
    for x in range(40, 270, 26):
        stroke([(x, 64), (x + 13, 84)], 2.6, "wd2", cap="flat")
        stroke([(x + 26, 64), (x + 13, 84)], 2.6, "wd2", cap="flat")
    # the train, in silhouette
    rect(70, 36, 120, 58, "ox")
    rect(76, 26, 98, 36, "ox")
    rect(102, 22, 108, 36, "ox2")
    rect(124, 38, 170, 58, "ox")
    rect(174, 38, 220, 58, "ox")
    for x in (80, 96, 112, 134, 160, 184, 210):
        circle(x, 59, 3.4, "ox2", 12)
    for x in (128, 142, 156, 178, 192, 206):
        rect(x, 42, x + 8, 48, "cream")
    for (x, y, r) in ((112, 16, 4), (122, 10, 5), (136, 6, 4)):
        circle(x, y, r, "ink2", 14)
    ring(262, 26, 16, 13, "ox", 36)
    text("S1", 262, 27, 15, "ox")


@banner("Top 48")
def bn_top48():
    rect(0, 0, 300, 100, "#3A4248")
    stroke([(4, 4), (296, 4), (296, 96), (4, 96), (4, 4)], 1.6, "#566068", cap="flat")
    shape(star_pts(150, 50, 36, 32, 18, -90), "br2")
    circle(150, 50, 29, "br", 40)
    text("48", 150, 51, 26, "dark")
    for x in (60, 240):
        stroke([(x - 30, 50), (x + 30, 50)], 2, "#566068", cap="flat")


@banner("Regular (trim)", overlay=True)
def trim_regular():
    rect(0, 88, 300, 98, "br")
    rect(0, 96, 300, 100, "br2")
    for x in range(12, 300, 46):
        circle(x, 93, 2, "br2", 10)


@banner("Warden (trim)", overlay=True)
def trim_warden():
    shape([[(0, 0), (300, 0), (300, 100), (0, 100)], [(5, 5), (295, 5), (295, 95), (5, 95)]], "st")


@banner("Sentinel (trim)", overlay=True)
def trim_sentinel():
    shape([[(0, 0), (300, 0), (300, 100), (0, 100)], [(5, 5), (295, 5), (295, 95), (5, 95)]], "silver2")
    shape([[(9, 9), (291, 9), (291, 91), (9, 91)], [(11, 11), (289, 11), (289, 89), (11, 89)]], "silver3")


@banner("Paragon (frame)", overlay=True)
def trim_paragon():
    shape([[(0, 0), (300, 0), (300, 100), (0, 100)], [(7, 7), (293, 7), (293, 93), (7, 93)]], "moon")
    shape([[(11, 11), (289, 11), (289, 89), (11, 89)], [(13, 13), (287, 13), (287, 87), (13, 87)]], "moon2")
    for (x, y) in ((7, 7), (293, 7), (7, 93), (293, 93)):
        shape(circle_pts(x, y, 9, 4, math.pi / 4), "moon")
        shape(circle_pts(x, y, 4, 4, math.pi / 4), "moon2")
