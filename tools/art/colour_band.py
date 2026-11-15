"""colour_band.py: TwoArenas.md section 7's colour band, checked region by region on a render against its film frame.

Usage, from the repo root. It runs in Blender 5.3's Python with numpy (no Pillow) and reads PNG (8 and 16 bit) and JPEG:

  $blender = "$env:LOCALAPPDATA/Programs/Blender/blender-5.3.0-windows-x64/blender.exe"
  & $blender --background --factory-startup --python tools/art/colour_band.py -- tools/art/specs/pass1_map1.json `
      [more specs] [--refs <References>] [--out <report.json or folder>] [--sheet <folder>] [--size 800]
  python tools/art/colour_band.py <the same arguments>     # starts that Blender for you ($env:BLENDER overrides it)

Spec: {"pairs": [{"name": "map1_owner", "ours": "art/previews/Map1/x.png", "film": "refs:owner/y.png",
                  "regions": [{"class": "ground", "label": "meadow, front left",
                               "ours": [0.0, 0.8, 0.15, 0.98], "film": [0.0, 0.78, 0.15, 0.98]}]}]}
  Rectangles are [x0, y0, x1, y1] in fractions of each image, top left (0, 0). "ours" is our render and "film" the film
  frame, as two files, never a compare sheet. "refs:" paths resolve against --refs; other relative paths against the
  repo root. Optional: per pair "note", "sheet_label"; per region "label", "note", and three extra checks on ours:
  "b_minus_r": [lo, hi] (region mean, 0-255), "b_minus_r_dark": [lo, hi] (its darkest quarter, pass 1's shadow
  measure) and "sat_within": 0.05 (saturation within that of the film's, as the launch reds need).
Classes (our value against the film's): ground, foliage, stone, water and built: saturation 0.65-0.85x, brightness
  -10% to +20%; sky and haze: 0.45-0.65x, -10% to +25%; interior: 0.65-0.85x, -10% to +20%; signal: reported only.
Per region: mean saturation (HSV S over pixels with V > 0.08), mean luma (Rec. 709 on sRGB, 0-255), mean RGB, blue
  minus red and the ratios. Per pair: the vivid share of our render (S > 0.6 and V > 0.35) outside the signal
  rectangles, failed over 1%. Both images of a pair are first box-filtered to one width (the narrower, at most --size).
  --refs   the References folder (default $env:LS_REFS, else ~/OneDrive/Documents/LastStanding/References)
  --out    the JSON report, or a folder for it (default %TEMP%/colour_band/<spec name>.report.json)
  --sheet  also write compare_<pair>_regions.png (ours | film | our vivid pixels) to check the rectangles by eye. It
           shows a film frame, so the folder must be outside the repo or have a .gitignore that excludes compare_*.png.
  --size   the working-width cap in px (default 800; 0 measures both images at their own size)
It prints a PASS/FAIL table and always exits 0: it reports, it doesn't block.
"""
import argparse
import datetime
import hashlib
import json
import os
import struct
import subprocess
import sys
import tempfile
import zlib

VERSION = 1
_GROUND = (0.65, 0.85, -10.0, 20.0)
_AIR = (0.45, 0.65, -10.0, 25.0)
BANDS = {  # class: (saturation ratio low, high, brightness difference low %, high %); None = reported, not banded
    "ground": _GROUND, "foliage": _GROUND, "stone": _GROUND, "water": _GROUND, "built": _GROUND,
    "sky": _AIR, "haze": _AIR,
    "interior": (0.65, 0.85, -10.0, 20.0),
    "signal": None,
}
SAT_V_MIN = 0.08          # saturation is averaged over pixels brighter than this (V); below it, S is noise
VIVID_S, VIVID_V, VIVID_LIMIT_PCT = 0.6, 0.35, 1.0
FILM_SAT_MIN = 0.05       # a film region greyer than this gives no usable saturation ratio: it is judged on luma only
FILM_LUMA_MIN = 8.0       # likewise for brightness on a near-black film region
FLAT_BLACK_LUMA, FLAT_BLACK_SD = 24.0, 4.0   # a film rectangle this dark and even is a letterbox bar: an error
REC709 = (0.2126, 0.7152, 0.0722)
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REGION_KEYS = {"class", "label", "note", "ours", "film", "b_minus_r", "b_minus_r_dark", "sat_within"}
PAIR_KEYS = {"name", "ours", "film", "regions", "note", "sheet_label"}
CLASS_RGB = {"ground": (0.95, 0.78, 0.15), "foliage": (0.15, 0.95, 0.3), "stone": (0.8, 0.8, 0.8),
             "water": (0.2, 0.55, 1.0), "built": (1.0, 0.55, 0.1), "sky": (0.35, 0.9, 1.0), "haze": (0.75, 0.75, 1.0),
             "interior": (1.0, 0.3, 0.3), "signal": (1.0, 0.2, 1.0)}


class SpecError(Exception):
    pass


class _Parser(argparse.ArgumentParser):
    def error(self, message):          # never sys.exit: inside Blender that becomes the process exit code
        raise SpecError(message)


def parse_args(argv):
    p = _Parser(prog="colour_band.py", add_help=False)
    p.add_argument("specs", nargs="*")
    p.add_argument("--refs", default=None)
    p.add_argument("--out", default=None)
    p.add_argument("--sheet", default=None)
    p.add_argument("--size", type=int, default=800)
    p.add_argument("--repo", default=REPO)
    p.add_argument("-h", "--help", action="store_true")
    return p.parse_args(argv)


# ------------------------------------------------------------------------------------------------- paths and files
def default_refs():
    env = os.environ.get("LS_REFS")
    if env:
        return os.path.normpath(env)
    guess = os.path.normpath(os.path.expanduser("~/OneDrive/Documents/LastStanding/References"))
    return guess if os.path.isdir(guess) else None


def resolve(path, refs, repo):
    if path.startswith("refs:"):
        if not refs:
            raise SpecError("%s needs --refs (the References folder)" % path)
        return os.path.normpath(os.path.join(refs, path[5:].lstrip("/\\")))
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(repo, path))


def file_info(path):
    with open(path, "rb") as f:
        sha = hashlib.sha1(f.read()).hexdigest()[:12]
    mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path)).isoformat(timespec="seconds")
    return {"sha1": sha, "modified": mtime}


def inside(path, root):
    p, r = os.path.normcase(os.path.abspath(path)), os.path.normcase(os.path.abspath(root))
    return p == r or p.startswith(r.rstrip("\\/") + os.sep)


def sheet_folder_ok(folder, repo):
    """Film imagery never goes into the repo: inside it, only a folder whose .gitignore drops compare_*.png will do."""
    if not inside(folder, repo):
        return True

    def lines(p):
        try:
            with open(p, encoding="utf-8") as f:
                return {ln.strip() for ln in f}
        except OSError:
            return set()
    if lines(os.path.join(folder, ".gitignore")) & {"compare_*.png", "compare_*"}:
        return True
    rel = os.path.relpath(os.path.abspath(folder), os.path.abspath(repo)).replace(os.sep, "/")
    return bool(lines(os.path.join(repo, ".gitignore")) & {rel + "/compare_*.png", rel + "/compare_*"})


# ------------------------------------------------------------------------------------------------------ the spec
def check_rect(r, what):
    if not (isinstance(r, (list, tuple)) and len(r) == 4 and all(isinstance(v, (int, float)) for v in r)):
        raise SpecError("%s: a rectangle is [x0, y0, x1, y1] in fractions" % what)
    x0, y0, x1, y1 = r
    if not (0.0 <= x0 < x1 <= 1.0 and 0.0 <= y0 < y1 <= 1.0):
        raise SpecError("%s: %s is not inside 0..1 with x0 < x1 and y0 < y1" % (what, list(r)))
    return [float(v) for v in r]


def load_spec(path):
    with open(path, encoding="utf-8") as f:
        spec = json.load(f)
    if not isinstance(spec, dict) or not isinstance(spec.get("pairs"), list):
        raise SpecError("the spec needs {\"pairs\": [...]}")
    warnings = []
    names = set()
    for i, pr in enumerate(spec["pairs"]):
        where = "pair %d" % (i + 1)
        if not isinstance(pr, dict):
            raise SpecError("%s is not an object" % where)
        for k in ("name", "ours", "film"):
            if not isinstance(pr.get(k), str) or not pr[k]:
                raise SpecError("%s needs \"%s\"" % (where, k))
        if pr["name"] in names:
            raise SpecError("pair name %s is used twice" % pr["name"])
        names.add(pr["name"])
        warnings += ["%s: unknown key \"%s\"" % (pr["name"], k) for k in sorted(set(pr) - PAIR_KEYS)]
        regs = pr.setdefault("regions", [])
        if not isinstance(regs, list):
            raise SpecError("%s: \"regions\" is a list" % pr["name"])
        for j, rg in enumerate(regs):
            rw = "%s region %d" % (pr["name"], j + 1)
            if not isinstance(rg, dict) or rg.get("class") not in BANDS:
                raise SpecError("%s: \"class\" must be one of %s" % (rw, ", ".join(BANDS)))
            rg["ours"] = check_rect(rg.get("ours"), rw + " ours")
            rg["film"] = check_rect(rg.get("film"), rw + " film")
            for key in ("b_minus_r", "b_minus_r_dark"):
                b = rg.get(key)
                if key in rg and not (isinstance(b, list) and len(b) == 2 and b[0] <= b[1]):
                    raise SpecError("%s: \"%s\" is [low, high]" % (rw, key))
            if "sat_within" in rg and not (isinstance(rg["sat_within"], (int, float)) and rg["sat_within"] >= 0):
                raise SpecError("%s: \"sat_within\" is a number >= 0" % rw)
            warnings += ["%s: unknown key \"%s\"" % (rw, k) for k in sorted(set(rg) - REGION_KEYS)]
    return spec, warnings


# ------------------------------------------------------------------------------------------------------ pixels
def load_image(path):
    """H x W x 4 float in 0..1, row 0 = top. Non-Color keeps the file's code values (16-bit PNGs are not linearised)."""
    import bpy
    import numpy as np
    img = bpy.data.images.load(path, check_existing=False)
    try:
        try:
            img.colorspace_settings.name = "Non-Color"
        except TypeError:
            pass
        w, h = img.size
        if not w or not h:
            raise SpecError("Blender could not read %s" % path)
        buf = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(buf)
    finally:
        bpy.data.images.remove(img)
    return np.clip(buf.reshape(h, w, 4)[::-1].astype(np.float64), 0.0, 1.0)


def _area_axis(a, n_out, axis):
    """Exact box (area) resampling along one axis, through the running sum."""
    import numpy as np
    n_in = a.shape[axis]
    if n_out >= n_in:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (1, 0)
    c = np.pad(np.cumsum(a, axis=axis), pad)
    edges = np.arange(n_out + 1) * (n_in / n_out)
    i0 = np.minimum(np.floor(edges).astype(int), n_in - 1)
    shape = [1] * a.ndim
    shape[axis] = n_out + 1
    lo = np.take(c, i0, axis=axis)
    run = lo + (np.take(c, i0 + 1, axis=axis) - lo) * (edges - i0).reshape(shape)
    return np.diff(run, axis=axis) * (n_out / n_in)


def to_width(a, width):
    import numpy as np
    h, w = a.shape[:2]
    if width <= 0 or width >= w:
        return a
    p = a.copy()
    p[..., :3] *= p[..., 3:4]                 # premultiplied, so transparent pixels don't bleed in
    p = _area_axis(_area_axis(p, width, 1), max(1, int(round(h * width / w))), 0)
    al = p[..., 3:4]
    p[..., :3] = np.where(al > 1e-6, p[..., :3] / np.maximum(al, 1e-6), 0.0)
    return p


def sat_val(rgb):
    import numpy as np
    mx, mn = rgb.max(-1), rgb.min(-1)
    return np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0), mx


def rect_px(rect, shape):
    h, w = shape[:2]
    c0 = min(w - 1, max(0, int(round(rect[0] * w))))
    r0 = min(h - 1, max(0, int(round(rect[1] * h))))
    return [c0, r0, min(w, max(c0 + 1, int(round(rect[2] * w)))), min(h, max(r0 + 1, int(round(rect[3] * h))))]


def summarize(px):
    """px: N x 3 in 0..1."""
    import numpy as np
    if len(px) == 0:
        return None
    s, v = sat_val(px)
    lit = v > SAT_V_MIN
    m = px.mean(0) * 255.0
    luma = px @ np.array(REC709)
    dark = px[luma <= np.quantile(luma, 0.25)]       # pass 1's "shadow" blue minus red, inside the region
    return {
        "px": int(len(px)),
        "sat_px_pct": round(float(lit.mean() * 100.0), 1),
        "sat": round(float(s[lit].mean()), 3) if lit.any() else None,
        "luma": round(float(luma.mean() * 255.0), 1),
        "luma_sd": round(float(luma.std() * 255.0), 1),
        "rgb": [round(float(c), 1) for c in m],
        "hex": "#%02x%02x%02x" % tuple(int(round(c)) for c in m),
        "b_minus_r": round(float(m[2] - m[0]), 1),
        "b_minus_r_dark": round(float((dark[:, 2] - dark[:, 0]).mean() * 255.0), 1),
        "sat_of_mean": round(float((m.max() - m.min()) / m.max()), 3) if m.max() > 0 else 0.0,
    }


def region_stats(img, rect):
    box = rect_px(rect, img.shape)
    c0, r0, c1, r1 = box
    px = img[r0:r1, c0:c1].reshape(-1, 4)
    return summarize(px[px[:, 3] >= 0.5][:, :3]), box


def vivid(img, boxes):
    """Share of opaque pixels outside the boxes that are vivid, and where they sit."""
    import numpy as np
    s, v = sat_val(img[..., :3])
    keep = img[..., 3] >= 0.5
    for c0, r0, c1, r1 in boxes:
        keep[r0:r1, c0:c1] = False
    viv = (s > VIVID_S) & (v > VIVID_V) & keep
    n, of = int(viv.sum()), int(keep.sum())
    out = {"pct": round(100.0 * n / of, 3) if of else 0.0, "px": n, "of_px": of, "mask": viv}
    if n:
        ys, xs = np.nonzero(viv)
        h, w = viv.shape
        fx, fy = xs / w, ys / h

        def q(a, p):
            return round(float(np.quantile(a, p)), 3)
        out["where"] = {"centre": [round(float(fx.mean()), 3), round(float(fy.mean()), 3)],
                        "box_p5_p95": [q(fx, 0.05), q(fy, 0.05), q(fx, 0.95), q(fy, 0.95)]}
        out["rgb"] = [round(float(c), 1) for c in img[..., :3][viv].mean(0) * 255.0]
    return out


# ------------------------------------------------------------------------------------------------------ judging
def judge(cls, o, f, rg):
    """Checks one region against its class band (and the optional extra checks). Ratios are judged as displayed."""
    out = {"sat_ratio": None, "luma_diff_pct": None, "checks": {}, "why": []}
    if o["sat"] is not None and f["sat"] is not None and f["sat"] >= FILM_SAT_MIN:
        out["sat_ratio"] = round(o["sat"] / f["sat"], 2)
    if f["luma"] >= FILM_LUMA_MIN:
        out["luma_diff_pct"] = int(round(100.0 * (o["luma"] / f["luma"] - 1.0)))
    band = BANDS[cls]
    ck, why = out["checks"], out["why"]
    if band:
        lo, hi, dlo, dhi = band
        out["band"] = {"sat_ratio": [lo, hi], "luma_diff_pct": [dlo, dhi]}
        r = out["sat_ratio"]
        if r is None:
            ck["sat"] = "n/a"
            why.append("film nearly grey, saturation not judged")
        elif r < lo or r > hi:
            ck["sat"] = "FAIL"
            why.append("sat %.2fx %s %.2f" % (r, "<" if r < lo else ">", lo if r < lo else hi))
        else:
            ck["sat"] = "PASS"
        d = out["luma_diff_pct"]
        if d is None:
            ck["luma"] = "n/a"
            why.append("film nearly black, brightness not judged")
        elif d < dlo or d > dhi:
            ck["luma"] = "FAIL"
            why.append("%s %+d%%" % ("too dark" if d < dlo else "too bright", d))
        else:
            ck["luma"] = "PASS"
    for key, name in (("b_minus_r", "B-R"), ("b_minus_r_dark", "dark B-R")):
        if key in rg:
            lo, hi = rg[key]
            b = int(round(o[key]))
            ck[key] = "PASS" if lo <= b <= hi else "FAIL"
            if ck[key] == "FAIL":
                why.append("%s %+d outside %+d..%+d" % (name, b, lo, hi))
    if "sat_within" in rg:
        if o["sat"] is None or f["sat"] is None:
            ck["sat_within"] = "n/a"
        else:
            d = round(abs(o["sat"] - f["sat"]), 3)
            ck["sat_within"] = "PASS" if d <= rg["sat_within"] else "FAIL"
            if ck["sat_within"] == "FAIL":
                why.append("sat %.3f vs film %.3f, off by %.3f > %.3f" % (o["sat"], f["sat"], d, rg["sat_within"]))
    vals = set(ck.values())
    out["status"] = "FAIL" if "FAIL" in vals else "PASS" if "PASS" in vals else "INFO" if band is None else "N/A"
    return out


# ---------------------------------------------------------------------------------------------- the check sheet
_FONT = {  # 3 x 5 glyphs, rows top to bottom
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
    "Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
    ".": "000000000000010", ",": "000000000010100", "-": "000000111000000", ":": "000010000010000",
    "/": "001001010100100", "(": "010100100100010", ")": "010001001001010", "%": "101001010100101",
    "+": "000010111010000", "_": "000000000000111", "=": "000111000111000", "<": "001010100010001",
    ">": "100010001010100", "'": "010010000000000", "!": "010010010000010", " ": "000000000000000",
}


def draw_text(img, x, y, text, scale=2, col=(0.95, 0.95, 0.92)):
    h, w = img.shape[:2]
    for i, ch in enumerate(text.upper()):
        g = _FONT.get(ch, _FONT[" "])
        for k, bit in enumerate(g):
            if bit == "1":
                yy, xx = y + (k // 3) * scale, x + (i * 4 + k % 3) * scale
                if 0 <= yy < h - scale and 0 <= xx < w - scale:
                    img[yy:yy + scale, xx:xx + scale] = col


def draw_box(img, box, col, t=2):
    c0, r0, c1, r1 = box
    img[r0:r0 + t, c0:c1] = col
    img[max(r0, r1 - t):r1, c0:c1] = col
    img[r0:r1, c0:c0 + t] = col
    img[r0:r1, max(c0, c1 - t):c1] = col


def resize_bilinear(img, h, w):
    import numpy as np
    H, W = img.shape[:2]
    ys = np.clip((np.arange(h) + 0.5) * H / h - 0.5, 0, H - 1)
    xs = np.clip((np.arange(w) + 0.5) * W / w - 0.5, 0, W - 1)
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    y1, x1 = np.minimum(y0 + 1, H - 1), np.minimum(x0 + 1, W - 1)
    wy, wx = (ys - y0)[:, None, None], (xs - x0)[None, :, None]
    top = img[y0][:, x0] * (1 - wx) + img[y0][:, x1] * wx
    bot = img[y1][:, x0] * (1 - wx) + img[y1][:, x1] * wx
    return top * (1 - wy) + bot * wy


def write_png(path, rgb):
    import numpy as np
    a = (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    h, w = a.shape[:2]
    raw = np.concatenate([np.zeros((h, 1), np.uint8), a.reshape(h, w * 3)], axis=1).tobytes()

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def write_sheet(path, pr, ours, film, regions, viv):
    """Ours | film | our vivid pixels, each with the numbered rectangles, at one panel height."""
    import numpy as np
    H = 400
    panels = []
    for img, side in ((ours, "ours"), (film, "film")):
        h, w = img.shape[:2]
        pw = int(round(w * H / h))
        p = resize_bilinear(img[..., :3], H, pw)
        for i, rg in enumerate(regions, 1):
            b = rect_px(rg[side], (H, pw))
            col = CLASS_RGB[rg["class"]]
            draw_box(p, b, col)
            p[b[1]:b[1] + 14, b[0]:b[0] + 10 + 8 * len(str(i))] = col
            draw_text(p, b[0] + 3, b[1] + 2, str(i), 2, (0.0, 0.0, 0.0))
        panels.append(p)
    h, w = ours.shape[:2]
    pw = int(round(w * H / h))
    lum = ours[..., :3] @ np.array(REC709)
    base = np.repeat((0.15 + 0.55 * lum)[..., None], 3, axis=2)
    base[viv] = (1.0, 0.0, 1.0)
    yi = np.minimum((np.arange(H) * h / H).astype(int), h - 1)
    xi = np.minimum((np.arange(pw) * w / pw).astype(int), w - 1)
    p = base[yi][:, xi]
    for rg in regions:
        if rg["class"] == "signal":
            draw_box(p, rect_px(rg["ours"], (H, pw)), (1.0, 1.0, 1.0), 1)
    panels.append(p)
    gap, top, bottom = 10, 26, 26
    W = sum(q.shape[1] for q in panels) + gap * (len(panels) - 1)
    sheet = np.full((top + H + bottom, W, 3), 0.07)
    x = 0
    heads = ["OURS: " + pr["ours"], "FILM, STUDY ONLY: " + pr["film"],
             "OUR VIVID PIXELS OUTSIDE THE SIGNAL BOXES: %s (LIMIT %g%%)"
             % (fmt_pct(pr["vivid"]["pct"]), VIVID_LIMIT_PCT)]
    for q, head in zip(panels, heads):
        sheet[top:top + H, x:x + q.shape[1]] = q
        draw_text(sheet, x + 4, 8, head[:max(8, q.shape[1] // 8 - 1)])
        x += q.shape[1] + gap
    foot = "COLOUR_BAND REGION CHECK: %s" % pr["name"]
    if pr.get("sheet_label"):
        foot += " - " + pr["sheet_label"]
    draw_text(sheet, 4, top + H + 8, foot[:W // 8 - 1])
    write_png(path, sheet)


# ------------------------------------------------------------------------------------------------------ running
def run_pair(pr, refs, repo, size, sheet_dir):
    out = {"name": pr["name"], "status": "ERROR", "ours": {"path": pr["ours"]}, "film": {"path": pr["film"]}}
    for k in ("note", "sheet_label"):
        if k in pr:
            out[k] = pr[k]
    imgs = {}
    for side in ("ours", "film"):
        p = resolve(pr[side], refs, repo)
        out[side]["file"] = p
        if not os.path.isfile(p):
            out["error"] = "missing %s image: %s" % (side, p)
            return out
        if os.path.splitext(p)[1].lower() in (".exr", ".hdr", ".tif", ".tiff"):
            out.setdefault("warnings", []).append("%s is a float image: measure the 8-bit display PNG instead" % p)
        if os.path.basename(p).lower().startswith("compare_"):
            out.setdefault("warnings", []).append("%s looks like a compare sheet: measure the render and the film "
                                                  "frame as two files" % p)
        out[side].update(file_info(p))
        imgs[side] = load_image(p)
        out[side]["size"] = [imgs[side].shape[1], imgs[side].shape[0]]
    width = min(imgs["ours"].shape[1], imgs["film"].shape[1], size) if size > 0 else 0   # 0: each at its own size
    for side in ("ours", "film"):
        imgs[side] = to_width(imgs[side], width)
        out[side]["work_size"] = [imgs[side].shape[1], imgs[side].shape[0]]
    regions, signal_boxes, statuses = [], [], []
    for i, rg in enumerate(pr["regions"], 1):
        o, obox = region_stats(imgs["ours"], rg["ours"])
        f, fbox = region_stats(imgs["film"], rg["film"])
        r = {"n": i, "class": rg["class"], "label": rg.get("label", ""), "ours": None, "film": None}
        if "note" in rg:
            r["note"] = rg["note"]
        if rg["class"] == "signal":
            signal_boxes.append(obox)
        if o is None or f is None:
            r.update(status="ERROR", why=["no opaque pixels in the rectangle"])
        else:
            o.update(rect=rg["ours"], box_px=obox)
            f.update(rect=rg["film"], box_px=fbox)
            r.update(ours=o, film=f)
            r.update(judge(rg["class"], o, f, rg))
            for side, s in (("film", f), ("ours", o)):
                if s["luma"] <= FLAT_BLACK_LUMA and s["luma_sd"] <= FLAT_BLACK_SD:
                    msg = "the %s rectangle is flat black (luma %.0f): a letterbox bar or border?" % (side, s["luma"])
                    if side == "film":
                        r.update(status="ERROR", why=[msg])
                    else:
                        r["why"].append(msg)
        regions.append(r)
        statuses.append(r["status"])
    v = vivid(imgs["ours"], signal_boxes)
    mask = v.pop("mask")
    v["limit_pct"] = VIVID_LIMIT_PCT
    v["status"] = "PASS" if v["pct"] <= VIVID_LIMIT_PCT else "FAIL"
    film_signals = [rect_px(rg["film"], imgs["film"].shape) for rg in pr["regions"] if rg["class"] == "signal"]
    v["film_pct"] = vivid(imgs["film"], film_signals)["pct"]
    out["vivid"] = v
    whole = {}
    for side in ("ours", "film"):
        a = imgs[side].reshape(-1, 4)
        whole[side] = summarize(a[a[:, 3] >= 0.5][:, :3])
    whole.update({k: val for k, val in judge("signal", whole["ours"], whole["film"], {}).items()
                  if k in ("sat_ratio", "luma_diff_pct")})
    out["frame"] = whole
    out["regions"] = regions
    out["status"] = ("ERROR" if "ERROR" in statuses else
                     "FAIL" if "FAIL" in statuses or v["status"] == "FAIL" else "PASS")
    if sheet_dir:
        name = "".join(c if c.isalnum() or c in "._-" else "_" for c in pr["name"])
        sp = os.path.join(sheet_dir, "compare_%s_regions.png" % name)
        write_sheet(sp, dict(pr, vivid=v), imgs["ours"], imgs["film"], pr["regions"], mask)
        out["sheet"] = sp
    return out


def fmt_num(v, f):
    return "-" if v is None else f % v


def fmt_pct(v):
    return "<0.01%" if 0 < v < 0.005 else "%.2f%%" % v


def print_pair(p):
    print("")
    print("PAIR %s: %s" % (p["name"], p["status"]))
    if p.get("error"):
        print("  " + p["error"])
        return
    o, f = p["ours"], p["film"]
    print("  ours %s %dx%d | film %s %dx%d | measured at %d px wide" % (
        o["path"], o["size"][0], o["size"][1], f["path"], f["size"][0], f["size"][1], o["work_size"][0]))
    for w in p.get("warnings", []):
        print("  WARNING " + w)
    print("  %2s %-27s %-8s %-23s %-11s %-19s %-10s %-11s %s" % (
        "#", "region", "class", "saturation ours/film", "band", "luma ours/film", "band", "B-R o/f", "result"))
    for r in p["regions"]:
        if r["ours"] is None:
            print("  %2d %-27s %-8s %s" % (r["n"], r["label"][:27], r["class"], "ERROR " + "; ".join(r["why"])))
            continue
        ro, rf = r["ours"], r["film"]
        band = BANDS[r["class"]]
        sb = "%.2f-%.2fx" % band[:2] if band else "-"
        lb = "%+d..%+d%%" % band[2:] if band else "-"
        sat = "%s/%s %s" % (fmt_num(ro["sat"], "%.3f"), fmt_num(rf["sat"], "%.3f"),
                            fmt_num(r["sat_ratio"], "%.2fx"))
        lum = "%5.1f/%5.1f %s" % (ro["luma"], rf["luma"], fmt_num(r["luma_diff_pct"], "%+d%%"))
        bmr = "%+.0f/%+.0f" % (ro["b_minus_r"], rf["b_minus_r"])
        res = r["status"] + (": " + "; ".join(r["why"]) if r["why"] else "")
        if min(ro["sat_px_pct"], rf["sat_px_pct"]) < 25.0:
            res += " (few pixels above V 0.08)"
        if min(ro["px"], rf["px"]) < 200:
            res += " (small: %d px)" % min(ro["px"], rf["px"])
        print("  %2d %-27s %-8s %-23s %-11s %-19s %-10s %-11s %s" % (
            r["n"], r["label"][:27], r["class"], sat, sb, lum, lb, bmr, res))
    v = p["vivid"]
    where = ""
    if v.get("where"):
        where = ", centred at x %.2f y %.2f, mean rgb (%d,%d,%d)" % tuple(v["where"]["centre"] + v["rgb"])
    print("     vivid pixels outside the signals: ours %s (film %s), limit %g%%%s: %s" % (
        fmt_pct(v["pct"]), fmt_pct(v["film_pct"]), v["limit_pct"], where, v["status"]))
    fr = p["frame"]
    print("     whole frame, for information: sat %s/%s %s, luma %.1f/%.1f %s" % (
        fmt_num(fr["ours"]["sat"], "%.3f"), fmt_num(fr["film"]["sat"], "%.3f"), fmt_num(fr["sat_ratio"], "%.2fx"),
        fr["ours"]["luma"], fr["film"]["luma"], fmt_num(fr["luma_diff_pct"], "%+d%%")))
    if p.get("sheet"):
        print("     sheet: " + p["sheet"])


def run(args):
    refs = args.refs or default_refs()
    repo = os.path.abspath(args.repo)
    sheet_dir = None
    if args.sheet:
        sheet_dir = os.path.abspath(args.sheet)
        if not sheet_folder_ok(sheet_dir, repo):
            print("colour_band: no sheets: %s is in the repo and its .gitignore does not exclude compare_*.png "
                  "(film frames never go into the repo). Use a folder outside the repo." % sheet_dir)
            sheet_dir = None
        else:
            os.makedirs(sheet_dir, exist_ok=True)
    report = {"tool": "tools/art/colour_band.py", "version": VERSION,
              "ran": datetime.datetime.now().isoformat(timespec="seconds"), "refs": refs,
              "settings": {"size": args.size, "sat_v_min": SAT_V_MIN, "vivid_s": VIVID_S, "vivid_v": VIVID_V,
                           "vivid_limit_pct": VIVID_LIMIT_PCT, "film_sat_min": FILM_SAT_MIN,
                           "film_luma_min": FILM_LUMA_MIN,
                           "bands": {k: None if b is None else {"sat_ratio": list(b[:2]),
                                                                 "luma_diff_pct": list(b[2:])}
                                     for k, b in BANDS.items()}},
              "specs": []}
    print("colour_band v%d: refs %s" % (VERSION, refs))
    for sp in args.specs:
        path = sp if os.path.isfile(sp) else os.path.join(repo, sp)
        entry = {"spec": sp, "pairs": []}
        report["specs"].append(entry)
        print("")
        print("SPEC " + sp)
        try:
            spec, warnings = load_spec(path)
        except (OSError, ValueError, SpecError) as e:
            entry["error"] = str(e)
            print("  ERROR in the spec: %s" % e)
            continue
        entry["warnings"] = warnings
        for w in warnings:
            print("  WARNING " + w)
        for pr in spec["pairs"]:
            try:
                res = run_pair(pr, refs, repo, args.size, sheet_dir)
            except Exception as e:  # report and carry on: one bad pair never hides the others
                res = {"name": pr.get("name"), "status": "ERROR", "error": "%s: %s" % (type(e).__name__, e)}
            entry["pairs"].append(res)
            print_pair(res)
    pairs = [p for e in report["specs"] for p in e["pairs"]]
    report["summary"] = {k: sum(1 for p in pairs if p["status"] == k) for k in ("PASS", "FAIL", "ERROR")}
    out = args.out
    if not out:
        out = os.path.join(tempfile.gettempdir(), "colour_band")
    if not out.lower().endswith(".json"):
        stem = os.path.splitext(os.path.basename(args.specs[0]))[0] if len(args.specs) == 1 else "colour_band"
        out = os.path.join(out, stem + ".report.json")
    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)
    s = report["summary"]
    print("")
    print("SUMMARY %d pass, %d fail, %d error | report %s" % (s["PASS"], s["FAIL"], s["ERROR"], out))


def relaunch(argv):
    """Plain Python: hand the same arguments to Blender's Python, which has the image loader and numpy."""
    exe = os.environ.get("BLENDER") or os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "Blender",
                                                    "blender-5.3.0-windows-x64", "blender.exe")
    if not os.path.isfile(exe):
        print("colour_band: this runs in Blender's Python; Blender is not at %s (set $env:BLENDER)" % exe)
        return
    cmd = [exe, "--background", "--factory-startup", "--python", os.path.abspath(__file__), "--"] + list(argv)
    subprocess.call(cmd)


def main():
    try:
        sys.stdout.reconfigure(errors="replace")    # a label in any language never stops the table
    except (AttributeError, ValueError):
        pass
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    try:
        import bpy  # noqa: F401
    except ImportError:
        if "-h" in argv or "--help" in argv or not argv:
            print(__doc__)
        else:
            relaunch(argv)
        return
    if "--" not in sys.argv:
        print("colour_band: put the arguments after -- (blender ... --python tools/art/colour_band.py -- <spec>)")
        return
    try:
        args = parse_args(argv)
        if args.help or not args.specs:
            print(__doc__)
            return
        run(args)
    except Exception as e:  # always exit 0: it reports, it doesn't block
        print("colour_band: ERROR %s: %s" % (type(e).__name__, e))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
