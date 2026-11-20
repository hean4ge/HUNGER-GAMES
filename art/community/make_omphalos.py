"""Omphalos Studio community emblem and banner (owner refs: a line-art square perfume mark, a teal wide-tracked banner)."""
import math
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
COPPER = F + "COPRGTL.TTF"
GREEK = F + "palai.ttf"
S = 4  # supersample

def tracked(d, xy, text, font, fill, track, anchor_center=True):
    widths = [d.textlength(c, font=font) for c in text]
    total = sum(widths) + track * (len(text) - 1)
    x, y = xy
    if anchor_center:
        x -= total / 2
    for c, w in zip(text, widths):
        d.text((x, y), c, font=font, fill=fill)
        x += w + track
    return total

def emblem(size=1024):
    W = size * S
    bg, ink = (24, 22, 20), (236, 226, 204)
    im = Image.new("RGB", (W, W), bg)
    d = ImageDraw.Draw(im)
    lw = int(W * 0.006)
    m = int(W * 0.12)
    d.rectangle([m, m, W - m, W - m], outline=ink, width=lw)
    # title
    f = ImageFont.truetype(COPPER, int(W * 0.075))
    tracked(d, (W / 2, m + W * 0.055), "OMPHALOS", f, ink, W * 0.012)
    # rays behind the stone
    cx, base_y = W / 2, W - m - W * 0.11
    top_y = base_y - W * 0.40
    for i in range(13):
        a = math.radians(200 + i * (140 / 12))
        r0, r1 = W * 0.20, W * 0.33
        cy = base_y - W * 0.12
        d.line([cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + r1 * math.cos(a), cy + r1 * math.sin(a)], fill=ink, width=lw // 2)
    # the stone: a beehive dome
    dome_w, dome_h = W * 0.30, W * 0.34
    pts = []
    for i in range(0, 181):
        t = math.radians(i)
        x = cx - (dome_w / 2) * math.cos(t)
        y = base_y - dome_h * (math.sin(t) ** 0.75)
        pts.append((x, y))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(pts + [(cx + dome_w / 2, base_y)], fill=255)
    stone = Image.new("RGB", (W, W), bg)
    sd = ImageDraw.Draw(stone)
    # the carved net: diagonal lattice
    step = W * 0.045
    for k in range(-30, 30):
        x0 = cx + k * step
        sd.line([x0 - W * 0.4, base_y, x0 + W * 0.4, base_y - W * 0.8], fill=ink, width=lw // 2)
        sd.line([x0 + W * 0.4, base_y, x0 - W * 0.4, base_y - W * 0.8], fill=ink, width=lw // 2)
    im.paste(stone, (0, 0), mask)
    d.line(pts, fill=ink, width=lw, joint="curve")
    # plinth
    d.rectangle([cx - dome_w * 0.62, base_y, cx + dome_w * 0.62, base_y + W * 0.035], outline=ink, width=lw)
    d.line([m + W * 0.06, base_y + W * 0.07, W - m - W * 0.06, base_y + W * 0.07], fill=ink, width=lw // 2)
    f2 = ImageFont.truetype(COPPER, int(W * 0.04))
    # STUDIO under the line
    return im.resize((size, size), Image.LANCZOS)

def banner(w=1920, h=480):
    W, H = w * S, h * S
    bg, ink = (58, 138, 142), (16, 52, 56)
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(COPPER, int(H * 0.17))
    tracked(d, (W / 2, H * 0.30), "OMPHALOS STUDIO", f, ink, H * 0.035)
    g = ImageFont.truetype(GREEK, int(H * 0.15))
    tracked(d, (W / 2, H * 0.53), "ὀμφαλός", g, ink, H * 0.03)
    return im.resize((w, h), Image.LANCZOS)

if __name__ == "__main__":
    e = emblem(1024); e.save("omphalos_emblem_1024.png"); e.resize((420, 420), Image.LANCZOS).save("omphalos_emblem_420.png")
    e.resize((150, 150), Image.LANCZOS).save("omphalos_emblem_150.png")
    banner().save("omphalos_banner_1920x480.png")
    banner(1920, 1080).save("omphalos_banner_1920x1080.png")
    print("ok")
