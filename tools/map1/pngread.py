"""Minimal PNG reader (struct + zlib + numpy). Greyscale 8/16-bit and RGB/RGBA 8-bit, non-interlaced.
Pillow is not installed on this machine, so the IHDR is parsed directly."""
import struct
import zlib

import numpy as np


def read_header(path):
    with open(path, "rb") as f:
        sig = f.read(8)
        assert sig == b"\x89PNG\r\n\x1a\n", "not a PNG: %s" % path
        length, ctype = struct.unpack(">I4s", f.read(8))
        assert ctype == b"IHDR"
        w, h, depth, colour, comp, filt, interlace = struct.unpack(">IIBBBBB", f.read(13))
    return dict(width=w, height=h, bitDepth=depth, colourType=colour, interlace=interlace)


def read(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = []
    hdr = None
    chunks = []
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        chunks.append(ctype.decode("latin1"))
        if ctype == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif ctype == b"IDAT":
            idat.append(body)
        pos += 12 + length
    w, h, depth, colour, comp, filt, interlace = hdr
    assert interlace == 0
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    bpp = channels * depth // 8
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    rows = np.frombuffer(raw, dtype=np.uint8).reshape(h, stride + 1)
    filters = rows[:, 0]
    px = rows[:, 1:].astype(np.int32)
    out = np.zeros((h, stride), dtype=np.int32)
    used = sorted(set(int(v) for v in np.unique(filters)))
    for y in range(h):
        ft = int(filters[y])
        line = px[y]
        prev = out[y - 1] if y > 0 else np.zeros(stride, dtype=np.int32)
        if ft == 0:
            out[y] = line
        elif ft == 2:
            out[y] = (line + prev) & 255
        elif ft == 1:
            cur = line.copy()
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
            out[y] = cur
        elif ft == 3:
            cur = line.copy()
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 255
            out[y] = cur
        elif ft == 4:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
            out[y] = cur
        else:
            raise ValueError("filter %d" % ft)
    arr = out.astype(np.uint8)
    if depth == 16:
        arr = arr.reshape(h, w, channels, 2)
        arr = (arr[..., 0].astype(np.uint16) << 8) | arr[..., 1].astype(np.uint16)
    else:
        arr = arr.reshape(h, w, channels)
    if channels == 1:
        arr = arr[..., 0]
    info = dict(width=w, height=h, bitDepth=depth, colourType=colour, channels=channels, filters=used, chunks=chunks)
    return arr, info
