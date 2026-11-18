# Map 1: what the packer changed in the water

Written by `tools/map1/pack.py`. Do not edit: run the packer again. Heights and levels are in studs; a cell is one
4-stud voxel column, `x = -2752 + 4 * (col + 0.5)`, `z = -2752 + 4 * (row + 0.5)`, row 0 in the north.

Read from: `Map1_Height.png` (sha256 bc9b751905d76447...) and `Map1_WaterLevel.png` (sha256 6b6ea1795bb88dad...).

## The rules (Map1Build.md, decision 5)

1. Every water level sits 0.5 to 2 studs into its 4-stud voxel layer.
2. Two neighbouring wet cells have the same level, or a dry sill cell stands between them.
3. No dry cell next to water is lower than that water's level.

"Neighbouring" means the 8 cells round a cell, diagonals included: the stricter reading. A workbench test on
15 November 2026 found no water face at a corner even when only the four side neighbours were sealed, so the
diagonals are a margin, not a need.

## Faults in the export

| Fault | Counted with 4 neighbours | Counted with 8 neighbours | The older export (worldgen report 4.5) |
|---|---|---|---|
| Wet cells whose level breaks rule 1 | 0 | 0 | 17 |
| Pairs of wet neighbours with different levels | 18 | 40 | 41 |
| Wet cell beside a lower dry cell: pairs (dry cells; worst drop) | 20 (16; 1.84) | 58 (30; 9.94) | 20 (worst 1.84) |

The 8-neighbour count of the third fault is large before the repairs because the cells beside a cascade touch
the upper pool at a corner. Most of them are settled by the sills and need no change of their own.

### Water levels in the export

| Level | Into its voxel layer | Cells | Depth (least, mean, most) | Radius |
|---|---|---|---|---|
| 34.0000 | 2.0000 | 8716 | 0.34, 8.50, 14.59 | 371 to 1053 |
| 37.4375 | 1.4375 | 24 | 0.44, 0.98, 1.25 | 355 to 376 |
| 38.0000 | 2.0000 | 51 | 0.34, 0.94, 1.25 | 339 to 357 |
| 40.9062 | 0.9062 | 131 | 0.38, 0.96, 1.25 | 345 to 471 |
| 41.0000 | 1.0000 | 26 | 0.34, 0.94, 1.25 | 472 to 501 |
| 42.0000 | 2.0000 | 26 | 0.41, 0.94, 1.25 | 500 to 531 |
| 45.0625 | 1.0625 | 25 | 0.53, 0.98, 1.25 | 528 to 559 |
| 49.7500 | 1.7500 | 26 | 0.38, 0.95, 1.25 | 554 to 583 |
| 60.6562 | 0.6562 | 99 | 0.09, 0.89, 1.25 | 581 to 678 |

## Repairs: 42 cells

20 cells were dried and 42 heights were raised (the largest rise is 1.84 studs). Nothing was lowered, no water was
added, and no material or region id was changed: a sill keeps the slot its cell had (the stream bed).

### Cells whose level broke rule 1, made dry ground: 0 cells

None.

### Sills: 20 cells

Where two pools touched, the higher pool's edge cell becomes a dry sill 0.3125 studs above that pool's level
(TerrainGen's sill rule), so that ground holds the upper pool. The lower pool is untouched.

| Row | Col | x | z | Level was | Ground was | Ground now | Raised by | Holds water at | Lower water beside |
|---|---|---|---|---|---|---|---|---|---|
| 616 | 560 | -510 | -286 | 60.6562 | 59.4688 | 60.9688 | 1.5000 | 60.6562 | 49.7500 |
| 616 | 561 | -506 | -286 | 60.6562 | 59.6875 | 60.9688 | 1.2812 | 60.6562 | 49.7500 |
| 627 | 561 | -506 | -242 | 49.7500 | 48.9375 | 50.0625 | 1.1250 | 49.7500 | 45.0625 |
| 627 | 562 | -502 | -242 | 49.7500 | 48.5000 | 50.0625 | 1.5625 | 49.7500 | 45.0625 |
| 627 | 563 | -498 | -242 | 49.7500 | 49.3750 | 50.0625 | 0.6875 | 49.7500 | 45.0625 |
| 638 | 564 | -494 | -198 | 45.0625 | 44.0625 | 45.3750 | 1.3125 | 45.0625 | 42.0000 |
| 638 | 565 | -490 | -198 | 45.0625 | 43.9062 | 45.3750 | 1.4688 | 45.0625 | 42.0000 |
| 648 | 568 | -478 | -158 | 42.0000 | 40.7812 | 42.3125 | 1.5312 | 42.0000 | 41.0000 |
| 648 | 569 | -474 | -158 | 42.0000 | 41.1250 | 42.3125 | 1.1875 | 42.0000 | 41.0000 |
| 649 | 568 | -478 | -154 | 42.0000 | 40.9688 | 42.3125 | 1.3438 | 42.0000 | 41.0000 |
| 658 | 573 | -458 | -118 | 41.0000 | 39.8750 | 41.3125 | 1.4375 | 41.0000 | 40.9062 |
| 659 | 572 | -462 | -114 | 41.0000 | 40.3750 | 41.3125 | 0.9375 | 41.0000 | 40.9062 |
| 659 | 573 | -458 | -114 | 41.0000 | 39.7500 | 41.3125 | 1.5625 | 41.0000 | 40.9062 |
| 706 | 603 | -338 | 74 | 40.9062 | 39.6875 | 41.2188 | 1.5312 | 40.9062 | 38.0000 |
| 707 | 602 | -342 | 78 | 40.9062 | 40.4062 | 41.2188 | 0.8125 | 40.9062 | 38.0000 |
| 707 | 603 | -338 | 78 | 40.9062 | 39.6562 | 41.2188 | 1.5625 | 40.9062 | 38.0000 |
| 728 | 608 | -318 | 162 | 38.0000 | 36.8438 | 38.3125 | 1.4688 | 38.0000 | 37.4375 |
| 728 | 609 | -314 | 162 | 38.0000 | 37.0312 | 38.3125 | 1.2812 | 38.0000 | 37.4375 |
| 739 | 609 | -314 | 206 | 37.4375 | 36.6562 | 37.7500 | 1.0938 | 37.4375 | 34.0000 |
| 739 | 610 | -310 | 206 | 37.4375 | 36.2188 | 37.7500 | 1.5312 | 37.4375 | 34.0000 |

### Banks: 22 cells

Dry ground beside water and lower than it, raised to exactly that water's level: the least that satisfies rule 3.

| Row | Col | x | z | Ground was | Ground now | Raised by |
|---|---|---|---|---|---|---|
| 616 | 562 | -502 | -286 | 58.8125 | 60.6562 | 1.8438 |
| 638 | 566 | -486 | -198 | 43.4375 | 45.0625 | 1.6250 |
| 893 | 737 | 198 | 822 | 33.9688 | 34.0000 | 0.0312 |
| 895 | 740 | 210 | 830 | 33.9375 | 34.0000 | 0.0625 |
| 896 | 741 | 214 | 834 | 33.9375 | 34.0000 | 0.0625 |
| 896 | 742 | 218 | 834 | 33.7500 | 34.0000 | 0.2500 |
| 896 | 743 | 222 | 834 | 33.5625 | 34.0000 | 0.4375 |
| 897 | 743 | 222 | 838 | 33.6250 | 34.0000 | 0.3750 |
| 897 | 744 | 226 | 838 | 33.3750 | 34.0000 | 0.6250 |
| 897 | 745 | 230 | 838 | 33.1250 | 34.0000 | 0.8750 |
| 898 | 745 | 230 | 842 | 32.9688 | 34.0000 | 1.0312 |
| 898 | 746 | 234 | 842 | 32.6875 | 34.0000 | 1.3125 |
| 898 | 747 | 238 | 842 | 32.4688 | 34.0000 | 1.5312 |
| 898 | 748 | 242 | 842 | 32.3750 | 34.0000 | 1.6250 |
| 899 | 748 | 242 | 846 | 32.3750 | 34.0000 | 1.6250 |
| 899 | 749 | 246 | 846 | 32.4375 | 34.0000 | 1.5625 |
| 899 | 750 | 250 | 846 | 32.5938 | 34.0000 | 1.4062 |
| 899 | 751 | 254 | 846 | 32.7812 | 34.0000 | 1.2188 |
| 900 | 751 | 254 | 850 | 33.1250 | 34.0000 | 0.8750 |
| 900 | 752 | 258 | 850 | 33.3750 | 34.0000 | 0.6250 |
| 900 | 753 | 262 | 850 | 33.5938 | 34.0000 | 0.4062 |
| 900 | 754 | 266 | 850 | 33.8438 | 34.0000 | 0.1562 |

## After the repairs

| Level | Into its voxel layer | Cells | Depth (least, mean, most) |
|---|---|---|---|
| 34.0000 | 2.0000 | 8716 | 0.34, 8.50, 14.59 |
| 37.4375 | 1.4375 | 22 | 0.44, 0.98, 1.25 |
| 38.0000 | 2.0000 | 49 | 0.34, 0.94, 1.25 |
| 40.9062 | 0.9062 | 128 | 0.38, 0.96, 1.25 |
| 41.0000 | 1.0000 | 23 | 0.34, 0.93, 1.25 |
| 42.0000 | 2.0000 | 23 | 0.41, 0.93, 1.25 |
| 45.0625 | 1.0625 | 23 | 0.53, 0.97, 1.25 |
| 49.7500 | 1.7500 | 23 | 0.38, 0.97, 1.25 |
| 60.6562 | 0.6562 | 97 | 0.09, 0.89, 1.25 |

Faults left, counted with 8 neighbours: 0 bad levels, 0 pairs with different levels, 0 leaks.

The packer asserted, and stops without writing a pack if any of these fails:

- every water level sits 0.5 to 2 studs into its 4-stud voxel layer (9 levels, 9104 wet cells)
- two neighbouring wet cells always have the same level, so a dry cell stands between any two pools (8 neighbours; 0 breaches)
- no dry cell next to water is lower than that water's level (8 neighbours; 0 breaches)
- every wet cell's level is above its ground
- the log lists every changed cell: 42 heights raised, 20 cells dried; nothing was lowered and no water was added
- no repair is within 200 studs of the centre, so the knoll, the plinth ring and the turf are as exported (the nearest is at r 346)

## Hollows the packer left alone: 1

A hollow is dry ground lower than the water beside it, behind the cells that hold that water, with no lower water
to run to. Rule 3 is met (the cells that touch the water were raised), so the packer changes nothing more: the
water is held by a bank one cell wide, and the ground behind it stays under the water's level. To be rid of one,
change the generator: flood the hollow or lift its floor.

| Water level | Cells | x | z | Lowest ground | Deepest under the water |
|---|---|---|---|---|---|
| 34.0000 | 249 | 186 to 274 | 766 to 846 | 32.0625 | 1.9375 |
