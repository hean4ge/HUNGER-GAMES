"""make_hex_tile - the border wall's honeycomb tile as a PNG (for upload; Config.Border.HexImage).

The same pixels ArenaController.Hex draws into an EditableImage at start: one tile of a pointy-top honeycomb,
111 x 192 (sqrt(3) x 3 hexagon edges of 64 px), seamless when repeated. Colours: Config.Border.WallLineColor
(the outline, lifted toward white) and Config.Border.WallColor (the glow and the cells).

  python tools/border/make_hex_tile.py [out.png]      (default: tools/border/hex_tile.png)
"""
import math
import os
import struct
import sys
import zlib

EDGE = 64
TILE_W = 111
TILE_H = 3 * EDGE
LINE_HALF = 2.4
LINE_SOFT = 1.2
GLOW_FALL = 6.5
GLOW_ALPHA = 0.5
FILL_ALPHA = 0.13
BEVEL_ALPHA = 0.3
CORE_WHITE = 0.4
LINE = (56, 124, 255)  # Config.Border.WallLineColor
GLOW = (44, 112, 255)  # Config.Border.WallColor

SQ3 = math.sqrt(3)
APOTHEM = SQ3 / 2 * EDGE


def edge_distance(x, y):
    best = 1e9
    w = SQ3 * EDGE
    for j in range(-1, 3):
        cy = j * 1.5 * EDGE
        shift = 0 if j % 2 == 0 else w / 2
        for i in range(-1, 2):
            dx = x - (i * w + shift)
            dy = y - cy
            d = max(abs(dx), abs(dx * 0.5 + dy * SQ3 / 2), abs(dx * 0.5 - dy * SQ3 / 2))
            best = min(best, d)
    return APOTHEM - best


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def pixels():
    core = tuple(lerp(c / 255, 1, CORE_WHITE) for c in LINE)
    glow = tuple(c / 255 for c in GLOW)
    sx = SQ3 * EDGE / TILE_W
    rows = []
    for py in range(TILE_H):
        row = bytearray([0])  # PNG filter: none
        for px in range(TILE_W):
            e = edge_distance((px + 0.5) * sx, py + 0.5)
            core_a = 1 - smooth(LINE_HALF - LINE_SOFT, LINE_HALF + LINE_SOFT, e)
            glow_a = GLOW_ALPHA * math.exp(-max(e - LINE_HALF, 0) / GLOW_FALL)
            inside = min(max(1 - e / APOTHEM, 0), 1)
            fill_a = FILL_ALPHA + BEVEL_ALPHA * inside ** 3
            soft_a = glow_a + fill_a * (1 - glow_a)
            a = core_a + soft_a * (1 - core_a)
            k = core_a / a if a > 0 else 0
            c = [lerp(glow[n], core[n], k) for n in range(3)]
            row += bytes([int(c[0] * 255 + 0.5), int(c[1] * 255 + 0.5), int(c[2] * 255 + 0.5), int(min(max(a, 0), 1) * 255 + 0.5)])
        rows.append(bytes(row))
    return b"".join(rows)


def png(path, raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    head = struct.pack(">IIBBBBB", TILE_W, TILE_H, 8, 6, 0, 0, 0)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "hex_tile.png")
    png(out, pixels())
    print(out, TILE_W, "x", TILE_H)
