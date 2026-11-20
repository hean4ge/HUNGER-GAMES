# tools/map1: Map 1's data pack

`pack.py` turns the Blender exports of Map 1 (the Green Land) into the data the game is built from. The contract is
[docs/design/Map1Build.md](../../docs/design/Map1Build.md), section 3.3.

```bash
python tools/map1/pack.py
```

That one command, run from the repo root with Studio open or closed:

1. reads the export folder (`%USERPROFILE%\OneDrive\Documents\LastStanding\BlenderExports\Map1`, or `--exports DIR`,
   or the environment variable `LS_MAP1_EXPORTS`) and refuses it if it breaks the contract;
2. repairs the water and asserts the three water rules (below);
3. writes the blob files to `tools/map1/build/` (not committed);
4. builds the Studio pack **`map1_data`** with `tools/studio_sync/sync.py blob`;
5. writes `src/ReplicatedStorage/Shared/Map1Regions.lua`;
6. writes `repair_log.md` and `pack_manifest.json` beside this file, and `build/proof.luau` and `build/READY.txt`.

It needs Python 3 with numpy. Pillow is not needed: `pngread.py` reads the PNGs. It takes a few seconds.

Running it again changes nothing: every output is byte-identical, and the Studio pack is written only when a blob
differs from the pack already there (`--force-pack` writes it anyway). When a blob does change, the build number
goes up, and `pack_manifest.json` and `build/READY.txt` say which blobs changed and by how much. `--dry` reads,
repairs and checks without writing anything.

## The pack lives in Studio's install folder

`map1_data.rbxmx` is written to Studio's own content folder
(`%LOCALAPPDATA%\Roblox\Versions\<version>\content\ls_import\`). **A Studio update replaces that folder and the pack
is gone.** After a Studio update or reinstall, build it again with the one command above (it notices that the pack
is missing), then run the proof (next section). If `ServerStorage.Dev.StudioSync` is gone too, see
[tools/studio_sync](../studio_sync/README.md), "bootstrap". `sync.py clean` does not remove the pack. Nothing in the
pack is in the place file: the game's builders read it in Studio, in Edit mode, and write terrain and instances
from it.

Studio reads a rebuilt pack of the same name at once: no restart is needed (checked on 15 November 2026). The proof
script holds the new fingerprints, so it shows which build Studio has.

## Proving the pack in Studio

`pack.py` writes `tools/map1/build/proof.luau`. Run its text in Studio (Edit mode) with `execute_luau`. It opens the
pack, checks every blob's size and FNV-1a fingerprint against the packer's own figures, compares 20 height cells and
20 water cells with the export files (16 untouched heights and 4 repaired ones; one cell of every water level, 4
dried cells and 3 dry ones), and decodes the two JSON blobs. It prints `PROOF PASSED` or the lines that differ.

## What is in the pack

All grids are row-major, row 0 in the north (z = -2752), little-endian. Cell (row, col) of a 1376 grid is the voxel
column at `x = -2752 + 4 * (col + 0.5)`, `z = -2752 + 4 * (row + 0.5)`. A mask cell is 8 studs on the same origin.

| Blob | Content |
|---|---|
| `Height` | 1376 x 1376 uint16, y = value / 32. The Blender heights with the water repairs applied |
| `Material` | 1376 x 1376 uint8, the slot ids of `Map1_Terrain.json`. The PNG unchanged |
| `Region` | 1376 x 1376 uint8, the region ids. The PNG unchanged |
| `WaterLevel` | 1376 x 1376 uint16 after the repairs, y = value / 32, 0 = dry |
| `Mask_<Name>` | 688 x 688 uint8 for Conifer, Broadleaf, Gorse, Heather, Boulders, Crags, TallGrass, Wildflowers |
| `Terrain`, `Layout` | `Map1_Terrain.json` and `Map1_Layout.json` as text |
| `Manifest_Landmarks`, `Manifest_Plants`, `Manifest_Skyline`, `Manifest_FarValley` | The asset manifests as text |

- Text blobs have LF line endings (the exports have CRLF), so a blob's fingerprint is the same on every machine.
- A manifest blob is the export's manifest. If `art/manifests/` holds the same manifest with an added `assetIds`
  entry (the upload record), the pack carries that copy. If the two differ in anything else, the pack carries the
  export's and the packer says so.
- `Manifest_Skyline` is `Map1_SkylineCut.manifest.json` when the export folder has it, otherwise
  `Map1_Skyline.manifest.json`. The first skyline has parts wider than Roblox's 2,048-stud limit; the cut one is
  what the game imports.
- A manifest that is not in the export folder is left out of the pack. `pack:info("Manifest_FarValley")` is then nil.

`pack_manifest.json` lists every blob with its size and fingerprint, the export files it was made from (SHA-256),
the water figures and the module's accuracy. `build/READY.txt` is the same list as text.

## The water repairs

Roblox terrain water cannot stand against air and cannot slope. The packer makes the export obey three rules
(Map1Build.md, decision 5), and stops without writing anything if one still fails afterwards:

1. Every water level sits 0.5 to 2 studs into its 4-stud voxel layer.
2. Two neighbouring wet cells have the same level, or a dry sill cell stands between them.
3. No dry cell next to water is lower than that water's level.

"Neighbouring" means the 8 cells round a cell, diagonals included: the stricter reading. A workbench test found no
water face at a corner even when only the four side neighbours were sealed (TerrainGen's containment rule), so the
diagonals are a margin, not a need.

| Fault | What the packer does |
|---|---|
| A wet cell whose level is at or under its ground | It becomes dry |
| A pool of 4 cells or fewer at a level that breaks rule 1 (an in-between cell of a cascade) | It becomes dry ground, 0.3125 studs above the highest water still beside it |
| A bigger pool at a level that breaks rule 1 | **The packer stops.** The level must be fixed in the generator |
| Two pools that touch | The higher pool's edge cells become a dry sill, 0.3125 studs above that pool's level. The lower pool is untouched |
| Dry ground beside water and lower than it | It is raised to exactly the water's level |

Only heights rise and only water is removed (unless the margin is on, below). Materials and regions are never
changed: a sill keeps its cell's slot. Every changed cell is listed in [repair_log.md](repair_log.md), with the
count of each fault in the export.
The log also lists **hollows**: dry ground under the level of the water beside it, held back by a bank one cell
wide. The packer leaves those alone; they are for the generator to flood or lift.

## The margin (an option, off by default)

The three rules seal the water. They do not make a narrow stream show. Terrain water in a channel 2 or 3 cells wide
is partly hidden by its own banks: the bank's surface leans over the first wet cell on each side. Measured in Studio
on 15 November 2026, with the old arena's voxel rules (no solid in the voxel that holds the surface, containment over
4 neighbours):

| Test channel | Designed water that shows |
|---|---|
| Any cell with 4 wet side neighbours | 100% |
| 3 cells wide, straight | 67% with the level 0.66 into its voxel layer, 83% at 2.0 |
| 2 cells wide, straight | 38% at 0.66, 75% at 2.0 |
| 2 cells wide on a diagonal | 0% at 0.66 and at 1.0, 70% at 2.0 |
| The same, banks 1 stud higher | No change |
| The same, bed 1.25 deep | 23% at 0.66 |
| The same, **one more wet cell on each side** | 86% at 0.66, 100% at 2.0 |

`pack.py --margin` applies that last line to the data. Every dry cell at the side of a narrow pool (fewer than 2,000
cells: the stream's pools, not the lake) becomes wet at the pool's level, 0.25 studs deep, unless that would lower
its ground by more than 3 studs (a steep bank stays). The sills and banks are then made as usual, so the three rules
still hold. 0.25 is too shallow to be taken for a drinking spot and deep enough to be a wet column.

On the real stream (388 cells, written twice at the workbench from the two packs):

| | `map1_data` (no margin) | `map1_data_margin` |
|---|---|---|
| Designed stream area where water shows | 71% | 92% |
| Designed cells whose centre shows water | 281 of 388 | 359 of 388 |
| Worst pools: 60.66 and 40.91 | 63% and 70% | 81% and 96% |
| Mean depth where water shows | 0.57 | 0.74 |
| Water faces against air | 0 of 1,666 edges | 0 of 1,760 edges |
| Cells changed by the packer | 42 | 327: 281 margin cells lowered by 2.94 at most, 46 raised |

The margin cells themselves show water on 43% of their area, so the stream looks about 1.7 studs wider on each side
than Blender drew it.

```bash
python tools/map1/pack.py --margin --pack-name map1_data_margin   # an experiment pack beside the real one
python tools/map1/pack.py --margin                                # the real pack with the margin
```

To make the margin the default, set `STREAM_MARGIN = True` at the top of `pack.py`. The Height blob changes, so
`Map1Regions.lua` changes a little too and must be pushed again. A pack under another name keeps its files in
`build/<name>/` and does not touch the log, the manifest or the module of the real pack.

## The hills (on by default; `--no-hills` leaves them out)

The owner asked for a slightly hilly map (20 November 2026). `hills.py` lays gentle rolling ground over the valley
floor after the water repairs, so the Height blob, `Map1Regions.lua` and every builder read the same ground: a
seeded cubic B-spline value noise (wavelengths 320, 160 and 80 studs, seed 4820), about 10 studs up or down on the
open meadow and up to 17 near the valley sides, times a mask that keeps everything else as Blender made it: the
heart inside r 205 (the knoll, deck, plinth ring and turf), every cell within 28 studs of water (the lake, the stream,
their banks and levels), the trails and paths, every landmark's footprint, the Edge, Crest and Outside regions and
everything past r 1,560, and steep ground. The packer then checks the water's faults are unchanged, that no repaired
cell moved and that the heart is untouched, and stops otherwise. Build 5: 459,878 cells moved, +15.6 / -16.4 studs at
most. A B-spline, not a quintic blend: the quintic is flat round every lattice node, and the plateaus it left drew as
pale bare grass. After a new pack, write the changed chunks only (`Map1.Terrain` opts `only` and `trim`), then
`fillUnder`, Scatter, Loot, Water and the Audit.

## What else makes the packer stop

A missing file; a PNG of the wrong size or bit depth; a grid, cell size or origin that is not the contract's; a
region or material legend that changed (ids, names, base materials); an id outside the legend; a height of 0; a
knoll that is not y 46 or a plinth ring that is not y 44.3; a water mask that disagrees with the water levels; a
layout without exactly 48 plinths on radius 150, standing on the height grid; a `Map1_BiomeGrid16.json` that is not
the region raster sampled every 16 studs; a JSON file with a BOM; a module of 150,000 bytes or more.

`test_pack.py` damages a copy of the exports in 21 ways and checks each outcome, and checks the margin's own rules:

```bash
python tools/map1/test_pack.py
```

## Map1Regions.lua

`src/ReplicatedStorage/Shared/Map1Regions.lua` is generated. Do not edit it: run the packer, then push it with
`python tools/studio_sync/sync.py push src/ReplicatedStorage/Shared/Map1Regions.lua`. It asks for no service and
never yields, so it loads on the server and on clients.

| Name | Meaning |
|---|---|
| `regionAt(x, z)` | Region id 1 to 10; 10 (Outside) beyond the grid |
| `nameAt(x, z)`, `Names[id]`, `Ids[name]` | Heart, Iris, NorthWood, EastRidge, SouthMountain, Lake, WestRidge, Edge, Crest, Outside |
| `heightAt(x, z)` | Ground height in studs (under water: the bed), bilinear between nodes, clamped at the grid's edge |
| `RegionCell`, `RegionSize`, `RegionOrigin` | 16, 240, -1920 |
| `HeightCell`, `HeightSize`, `HeightOrigin`, `HeightBase`, `HeightStep` | 32, 173 nodes a side, -2752, and the decoding numbers |
| `Pack` | The fingerprints of the `Height` and `Region` blobs it was made from |

- The region grid is `Map1_Region.png` sampled every 16 studs: the same grid as `Map1_BiomeGrid16.json`. One
  character per cell.
- The height grid has nodes 32 studs apart, two characters per node (base 57, steps of 0.35 studs).
- `heightAt` is a fallback for places where the terrain is not loaded. Inside radius 1,800 it is 0.3 studs from the
  full grid at the median and within 6 studs on 99.6% of points. On cliffs (the Edge, the peak) it can be tens of
  studs out. No coarse grid avoids that: with nodes 64 studs apart 97.8% of points are within 6 studs, with 16 studs
  99.9%. `--height-cell 64` writes the 64-stud grid (a module of 79,000 bytes instead of 124,000).

## Files here

| File | What |
|---|---|
| `pack.py` | The packer |
| `pngread.py` | PNG reader (struct, zlib, numpy) |
| `test_pack.py` | The packer's tests |
| `repair_log.md` | Written by the packer: every cell it changed |
| `pack_manifest.json` | Written by the packer: the blob list, sizes, fingerprints, sources |
| `build/` | Written by the packer, not committed: the blob files, `proof.luau`, `READY.txt`; `build/<name>/` for a pack under another name |
| `gen_layout.py`, `gen_assets_manifest.py` | Other packages' generators (the layout module, the assets builder's manifest): not part of the packer |
