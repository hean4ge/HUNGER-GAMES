"""Omphalos Studio v2. Emblem: the triple enclosure with the point at the centre
(Guenon, 'La triple enceinte druidique', Symboles de la Science sacree: the three
degrees around the one Centre). Banner: bolder Perpetua Titling, colours inverted."""
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
S = 4

def tracked(d, cx, y, text, font, fill, track):
    ws = [d.textlength(c, font=font) for c in text]
    x = cx - (sum(ws) + track * (len(text) - 1)) / 2
    for c, w in zip(text, ws):
        d.text((x, y), c, font=font, fill=fill)
        x += w + track

def emblem(size=1024, bg=(20, 19, 18), ink=(232, 221, 196), gold=(201, 162, 92)):
    W = size * S
    im = Image.new("RGB", (W, W), bg)
    d = ImageDraw.Draw(im)
    lw = int(W * 0.011)
    cx, cy = W / 2, W * 0.42
    halves = [W * 0.27, W * 0.18, W * 0.09]
    for h in halves:
        d.rectangle([cx - h, cy - h, cx + h, cy + h], outline=ink, width=lw)
    # the four paths joining the enclosures at their midpoints
    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        d.line([cx + dx * halves[0], cy + dy * halves[0], cx + dx * halves[2], cy + dy * halves[2]], fill=ink, width=lw)
    # the Centre
    r = W * 0.022
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=gold)
    f = ImageFont.truetype(F + "PERTILI.TTF", int(W * 0.085))
    tracked(d, cx, W * 0.765, "OMPHALOS", f, ink, W * 0.014)
    return im.resize((size, size), Image.LANCZOS)

def banner(w=1920, h=480, bg=(14, 56, 60), ink=(226, 238, 232), sub=(132, 196, 190)):
    W, H = w * S, h * S
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype(F + "PERTIBD.TTF", int(min(H * 0.22, W * 0.06)))
    tracked(d, W / 2, H * 0.28, "OMPHALOS STUDIO", big, ink, W * 0.006)
    g = ImageFont.truetype(F + "palabi.ttf", int(min(H * 0.15, W * 0.04)))
    tracked(d, W / 2, H * 0.56, "ὀμφαλός", g, sub, W * 0.004)
    return im.resize((w, h), Image.LANCZOS)

if __name__ == "__main__":
    e = emblem(); e.save("omphalos_emblem_v2_1024.png")
    e.resize((420, 420), Image.LANCZOS).save("omphalos_emblem_v2_420.png")
    e.resize((150, 150), Image.LANCZOS).save("omphalos_emblem_v2_150.png")
    banner().save("omphalos_banner_v2_1920x480.png")
    banner(1920, 1080).save("omphalos_banner_v2_1920x1080.png")
    banner(bg=(222, 232, 226), ink=(14, 56, 60), sub=(48, 120, 122)).save("omphalos_banner_v2_light_1920x480.png")
    print("ok")
