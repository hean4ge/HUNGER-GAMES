"""test_pack.py - checks that pack.py repairs what it should and refuses what it must.

  python tools/map1/test_pack.py [--exports DIR]

It copies the real export's data files into temporary folders, damages one thing in each copy, and runs the packer
dry on it. Nothing in the repo, the export folder or Studio is written. About a minute.
"""
import contextlib
import io
import json
import os
import shutil
import struct
import sys
import tempfile
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pack  # noqa: E402
import pngread  # noqa: E402

DATA_FILES = (["Map1_%s.png" % n for n in ("Height", "Material", "Region", "WaterMask", "WaterLevel")]
              + ["Map1_Mask_%s.png" % n for n in pack.MASKS]
              + ["Map1_Terrain.json", "Map1_Layout.json", "Map1_BiomeGrid16.json"]
              + ["Map1_%s.manifest.json" % n for n in ("Landmarks", "Plants", "Skyline")])


def write_png(path, arr):
    """8- or 16-bit greyscale PNG, filter 0 on every row."""
    h, w = arr.shape
    depth = 16 if arr.dtype == np.uint16 else 8
    raw = arr.astype(">u2" if depth == 16 else np.uint8).tobytes()
    stride = w * depth // 8
    rows = b"".join(b"\x00" + raw[i * stride:(i + 1) * stride] for i in range(h))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, depth, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def read_png(folder, name):
    arr, _info = pngread.read(os.path.join(folder, name))
    return np.array(arr)


def edit_json(folder, name, change):
    path = os.path.join(folder, name)
    with open(path, "rb") as fh:
        value = json.loads(fh.read().decode("utf-8"))
    change(value)
    with open(path, "wb") as fh:
        fh.write(json.dumps(value, indent=1).encode("utf-8"))


def run(folder):
    """Runs the packer dry on a folder. Returns (error text or None, everything it printed)."""
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            pack.main(["--dry", "--exports", folder])
    except pack.PackError as err:
        return str(err), out.getvalue()
    return None, out.getvalue()


# --- the damage -------------------------------------------------------------------------------------------------------
def wrong_size(folder):
    arr = read_png(folder, "Map1_Material.png")
    write_png(os.path.join(folder, "Map1_Material.png"), arr[:-1, :])


def height_8bit(folder):
    arr = read_png(folder, "Map1_Height.png")
    write_png(os.path.join(folder, "Map1_Height.png"), (arr >> 8).astype(np.uint8))


def region_renamed(folder):
    edit_json(folder, "Map1_Terrain.json", lambda t: t["regions"].__setitem__("3", "Northwood"))


def slot_base_changed(folder):
    edit_json(folder, "Map1_Terrain.json", lambda t: t["materialSlots"]["6"].__setitem__("base", "Sand"))


def slot_out_of_legend(folder):
    arr = read_png(folder, "Map1_Material.png")
    arr[10, 10] = 11
    write_png(os.path.join(folder, "Map1_Material.png"), arr)


def knoll_lowered(folder):
    arr = read_png(folder, "Map1_Height.png")
    arr[686:690, 686:690] -= 32
    write_png(os.path.join(folder, "Map1_Height.png"), arr)


def ring_raised(folder):
    arr = read_png(folder, "Map1_Height.png")
    arr[688, 688 + 37] += 16  # r = 150
    write_png(os.path.join(folder, "Map1_Height.png"), arr)


def hole(folder):
    arr = read_png(folder, "Map1_Height.png")
    arr[5, 5] = 0
    write_png(os.path.join(folder, "Map1_Height.png"), arr)


def mask_disagrees(folder):
    arr = read_png(folder, "Map1_WaterMask.png")
    arr[100, 100] = 255
    write_png(os.path.join(folder, "Map1_WaterMask.png"), arr)


def one_bad_level(folder):
    """One stream cell at a level 3 studs into its layer: an in-between cell, as the older export had."""
    arr = read_png(folder, "Map1_WaterLevel.png")
    assert arr[620, 560] == 1592  # a cell of the 49.75 pool
    arr[620, 560] = 51 * 32
    write_png(os.path.join(folder, "Map1_WaterLevel.png"), arr)


def pool_at_bad_level(folder):
    arr = read_png(folder, "Map1_WaterLevel.png")
    arr[arr == 1592] = 51 * 32  # the whole 49.75 pool at 51.0: 3 studs into its layer
    write_png(os.path.join(folder, "Map1_WaterLevel.png"), arr)


def lake_on_a_layer_boundary(folder):
    arr = read_png(folder, "Map1_WaterLevel.png")
    arr[arr == 1088] = 36 * 32  # 36.0 is 4 studs into the layer under it
    write_png(os.path.join(folder, "Map1_WaterLevel.png"), arr)


def water_without_depth(folder):
    """A wet cell whose ground is above its level."""
    h = read_png(folder, "Map1_Height.png")
    w = read_png(folder, "Map1_WaterLevel.png")
    assert w[921, 764] == 1088
    h[921, 764] = 1088 + 40
    write_png(os.path.join(folder, "Map1_Height.png"), h)


def missing_layout(folder):
    os.remove(os.path.join(folder, "Map1_Layout.json"))


def plinth_moved(folder):
    def change(layout):
        for item in layout["items"]:
            if item["asset"] == "M1_Plinth":
                item["position"][0] += 3.0
                break
    edit_json(folder, "Map1_Layout.json", change)


def plinth_missing(folder):
    def change(layout):
        for i, item in enumerate(layout["items"]):
            if item["asset"] == "M1_Plinth":
                del layout["items"][i]
                break
    edit_json(folder, "Map1_Layout.json", change)


def biome_grid_changed(folder):
    edit_json(folder, "Map1_BiomeGrid16.json", lambda b: b["data"][120].__setitem__(120, 9))


def bom(folder):
    path = os.path.join(folder, "Map1_Terrain.json")
    with open(path, "rb") as fh:
        raw = fh.read()
    with open(path, "wb") as fh:
        fh.write(b"\xef\xbb\xbf" + raw)


def cell_size_changed(folder):
    edit_json(folder, "Map1_Terrain.json", lambda t: t["grid"].__setitem__("studsPerPixel", 2.0))


def knoll_number_changed(folder):
    edit_json(folder, "Map1_Terrain.json", lambda t: t["plaza"].__setitem__("knollY", 48.0))


def manifest_empty(folder):
    edit_json(folder, "Map1_Plants.manifest.json", lambda m: m.__setitem__("assets", []))


# (name, damage, text the refusal must contain or None when the packer must pass, text its output must contain)
CASES = [
    ("clean copy", None, None, "PASS  no dry cell next to water"),
    ("Material.png one row short", wrong_size, "contract says", None),
    ("Height.png is 8-bit", height_8bit, "contract says", None),
    ("a region renamed in the legend", region_renamed, "region legend changed", None),
    ("a material slot on another base", slot_base_changed, "material legend changed", None),
    ("a material id outside the legend", slot_out_of_legend, "the legend has 1..10", None),
    ("the knoll one stud low", knoll_lowered, "the knoll", None),
    ("the plinth ring half a stud high", ring_raised, "the plinth ring", None),
    ("a hole in the heights", hole, "holes in the export", None),
    ("water mask and levels disagree", mask_disagrees, "disagree on 1 cells", None),
    ("one stream cell at an in-between level", one_bad_level, None, "1 bad levels"),
    ("a whole pool 3 studs into its layer", pool_at_bad_level, "the rule is 0.5 to 2", None),
    ("the lake on a layer boundary", lake_on_a_layer_boundary, "the rule is 0.5 to 2", None),
    ("a wet cell with its ground above the water", water_without_depth, None, "1 with no depth"),
    ("Layout.json missing", missing_layout, "missing export", None),
    ("a plinth 3 studs off the ring", plinth_moved, "not on radius", None),
    ("47 plinths", plinth_missing, "places 47 plinths", None),
    ("BiomeGrid16 differs from the region raster", biome_grid_changed, "is not Map1_Region.png sampled", None),
    ("Terrain.json starts with a BOM", bom, "starts with a BOM", None),
    ("the cell size changed", cell_size_changed, "the contract says", None),
    ("the knoll's height changed in Terrain.json", knoll_number_changed, "the contract says", None),
    ("a manifest with no assets", manifest_empty, "has no 'assets'", None),
]


def margin_checks(exports):
    """The margin option on the real exports: its own rules, and that it leaves the three water rules standing."""
    ex = pack.load_exports(exports)
    H0 = ex["height"].astype(np.int64)
    W0 = ex["waterLevel"].astype(np.int64)
    results = []

    def check(ok, text):
        results.append(bool(ok))
        print("%s  %s" % ("ok  " if ok else "FAIL", text))

    plain = pack.repair_water(H0, W0, False)
    H2, W2, repairs = pack.repair_water(H0, W0, True)
    try:
        pack.assert_water(H2, W2, H0, W0, repairs, True)
        check(True, "margin: the three water rules and the packer's own checks hold")
    except pack.PackError as err:
        check(False, "margin: %s" % err)
    margins = [rp for rp in repairs if rp["kind"] == "margin"]
    check(len(margins) > 0, "margin: %d cells were made wet" % len(margins))
    cuts = [rp["groundWas"] - rp["groundNow"] for rp in margins]
    check(max(cuts) <= pack.MARGIN_MAX_CUT, "margin: no cut is deeper than %.0f studs (deepest %.2f)" % (
        pack.studs(pack.MARGIN_MAX_CUT), pack.studs(max(cuts))))
    check(all(rp["levelNow"] - rp["groundNow"] >= pack.MARGIN_DEPTH for rp in margins),
          "margin: every margin cell is at least %.2f deep" % pack.studs(pack.MARGIN_DEPTH))
    narrow = pack.narrow_pools(W0)
    lake_level = int(np.bincount(W0[W0 > 0]).argmax())
    beside = 0
    for rp in margins:
        if any(narrow[rp["row"] + dr, rp["col"] + dc] and W0[rp["row"] + dr, rp["col"] + dc] == rp["levelNow"]
               for dr, dc in pack.NB4):
            beside += 1
    check(beside == len(margins), "margin: every margin cell is at the side of the narrow pool whose level it takes")
    check(not narrow[W0 == lake_level].any() and all(rp["levelNow"] != lake_level for rp in margins),
          "margin: the lake (%d cells at %.1f) is not narrow water and gets no margin" % (
              int((W0 == lake_level).sum()), pack.studs(lake_level)))
    kept = (W0 > 0) & (W2 > 0)
    check(bool((W2[kept] == W0[kept]).all()) and bool((H2[kept] == H0[kept]).all()),
          "margin: no designed wet cell changed its level or its bed")
    plain_dried = {(rp["row"], rp["col"]) for rp in plain[2] if rp["levelWas"] > 0 and rp["levelNow"] == 0}
    margin_dried = {(rp["row"], rp["col"]) for rp in repairs if rp["levelWas"] > 0 and rp["levelNow"] == 0}
    check(plain_dried == margin_dried, "margin: the same %d designed cells become sills with and without it" % len(plain_dried))

    def four_sided(W):
        wet = W > 0
        n4 = np.zeros(W.shape, dtype=int)
        for dr, dc in pack.NB4:
            n4 += pack.shifted(wet, dr, dc, fill=False)
        stream = narrow & wet
        return int((stream & (n4 == 4)).sum()), int(stream.sum())

    a, total_a = four_sided(plain[1])
    b, total_b = four_sided(W2)
    check(b > 2 * a and total_a == total_b, "margin: designed stream cells with water on all 4 sides: %d of %d without it, "
                                           "%d of %d with it" % (a, total_a, b, total_b))
    again = pack.repair_water(H2, W2, False)
    check(len(again[2]) == 0, "margin: the packed grids need no further repair")
    check(len(pack.repair_water(plain[0], plain[1], False)[2]) == 0, "no margin: the packed grids need no further repair")
    return results.count(False), len(results)


def main(argv):
    exports = pack.default_exports()
    if len(argv) == 2 and argv[0] == "--exports":
        exports = argv[1]
    elif argv:
        sys.exit(__doc__)
    base = tempfile.mkdtemp(prefix="map1_packtest_")
    failed = 0
    try:
        for index, (name, damage, must_refuse, must_print) in enumerate(CASES):
            folder = os.path.join(base, "case%02d" % index)
            os.mkdir(folder)
            for fname in DATA_FILES:
                shutil.copyfile(os.path.join(exports, fname), os.path.join(folder, fname))
            if damage:
                damage(folder)
            error, printed = run(folder)
            if must_refuse is not None:
                ok = error is not None and must_refuse in error
                detail = error if error is not None else "the packer did not refuse it"
            else:
                ok = error is None and (must_print is None or must_print in printed)
                detail = error if error is not None else "passes" + ("; reports '%s'" % must_print if must_print and ok else "")
            failed += 0 if ok else 1
            print("%s  %-45s %s" % ("ok  " if ok else "FAIL", name, detail[:150]))
            shutil.rmtree(folder, ignore_errors=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)
    margin_failed, margin_total = margin_checks(exports)
    print("%d cases and %d margin checks, %d failed" % (len(CASES), margin_total, failed + margin_failed))
    return 1 if failed + margin_failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
