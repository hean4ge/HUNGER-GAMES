# Map 1 into the game: the build plan

*15 November 2026. The owner looked at the Blender renders and answered "Yes, build it". This page is the contract
for the agents building it. Where it and an older design page disagree, this page wins for the beta.*

*Updated 18 November 2026 (afternoon): Map 1 is installed. The plan below is kept as it was written; section 7
lists where the place now differs from it.*

Sources: the Blender exports (`%USERPROFILE%\OneDrive\Documents\LastStanding\BlenderExports\Map1`, pass 3, every
check passed), [TwoArenas.md](TwoArenas.md) section 3, and three reports written today in the session's scratch
area (`wave3\consumers\report.md`, `wave3\worldgen\report.md`, `wave3\mp\report.md`).

## 1. What the beta gets

| In the beta | Later |
|---|---|
| The Blender terrain as Roblox terrain out to radius 2,750, with the lake and the stream | The film's hazards and creatures |
| The heart: the horn (blue-grey), its platform, 48 plinths at radius 150, the flower beds | The cableway, the designed sites' buildings |
| Forest, heather, gorse, boulders and flowers from the Blender masks, within the phone budgets | Plate tubes in the ground (a trench and a collar mesh) |
| The far mountains, and a far-valley mesh so the valley shows beyond the streaming distance | Expanded Terrain (three grass tints) |
| Loot, drinking water, the border, the start and the round on this map, for 1 to 48 contenders | Climbing trees, hunting, gathering |
| The lobby unchanged, moved out of the way | |

## 2. Decisions

1. **The vault.** The classic forest arena leaves the game and stays restorable.
   - Layer A: saved place versions 258 (tested) and 302 (wave 2) hold all of it.
   - Layer B: `ServerStorage.Vault_ClassicForest` (in the repo: `src/ServerStorage/Vault_ClassicForest/`) keeps its
     scripts and data: ArenaLayout v2, TerrainGen, TerrainData, Populate and its children, WaterPointsBuilder,
     RealAssets, the WaterPoints data, the 177 loot markers, and a README with the restore steps.
   - Its scenery in `workspace.Arena` is deleted and its terrain is cleared by region. Never call
     `TerrainGen.generate()` or `Populate.generate()` with defaults: the first clears all terrain, the second rebuilds
     the lobby.
2. **Data goes in through studio_sync blob packs** ([tools/studio_sync](../../tools/studio_sync/README.md)). No HTTP,
   no model uploads for data. Scripts go in with `sync.py push`.
3. **The lobby moves** from (2600, 160, 0) to **(8800, 160, 0)**, a shift of +6,200 on X, before any Map 1 terrain is
   written: copy the island's terrain region, paste it shifted, `PivotTo` everything in `workspace.Lobby` by the same
   shift, clear the old region, set `LobbyPosition`. It stays east of the arena, so the lobby's facing is unchanged.
4. **Terrain.** Voxels out to radius 2,750 from `Map1_Height.png`. A 64-stud solid shell inside radius 1,952 and a
   thinner one beyond (the writer's author may adjust with measurements). Expanded Terrain stays off. Roblox's own
   terrain materials and textures: the old LS_ material overrides are removed from the arena's materials. One colour
   per base material, taken from the Blender palette.
5. **Water** is repaired by the packer before it becomes voxels: every level sits 0.5 to 2 studs into its voxel
   layer, neighbouring levels get sills, and no dry ground beside water is lower than the water.
6. **Plinths.** 48 at radius 150, standing on the ring turf (y 44.30). No bores in the ground for the beta: a plate
   that finds no bore stays up, and the launch intro's white-out hands off to a player standing on the plinth.
7. **Far view.** Blender adds far-valley meshes (radius about 900 to 2,750, with a dark canopy layer where the forest
   is) and re-cuts the skyline so that no part is over 2,048 studs. Both are Persistent models.
8. **Uploads.** Four model files to the owner's account, by the method in [art/README.md](../../art/README.md):
   Landmarks, Plants, Skyline, FarValley. No images.
9. **Names.** Player-facing text calls the centre "the Horn". If the start signal is also called a horn in text, the
   signal's text changes; its sound does not.
10. **Contenders.** 48 a round, one per plinth (`MaxContenders` and `FullContenders` 48).
11. **The border.** Start radius 1,800 at 48 contenders, scaled by head count with the existing square-root rule from
    a lone-player radius of 520 (700 since 18 November, section 7). The wall never moves faster than 3.5 studs a second: the shrink ends when it ends
    today and starts as early as it must. Final radius 60, closing on turf 90 to 100 studs from the centre, not on
    the platform. The wall is tall enough for ground up to y 640.
12. **The Edge** (the cliff in the north, inside the border) is a real drop. The invisible Boundary at radius 1,900
    stops anyone leaving the map.
13. **Sound.** `getBiome` keeps today's biome names (Meadow, Forest, Lake, Cliffs, Field, Mountains, Lobby), mapped
    from Map 1's regions, so the ambience code does not change.
14. **One switch.** `Config.Map` names the arena ("ClassicForest" or "GreenLand") and `Config.Maps[name]` holds each
    map's numbers (border, contenders, timings). Game code reads sizes from the layout and from Config, never from
    constants, so the classic arena still works if the vault is restored.

## 3. The contract

### 3.1 `ReplicatedStorage.Shared.ArenaLayout` for Map 1

It must load on the server and on every client without yielding and without touching ServerStorage.

| Name | Value or meaning |
|---|---|
| `Version` | 3 |
| `Map` | "GreenLand" |
| `Center` | Vector3 (0, 0, 0) |
| `BaseHeight` | 46 (the knoll under the platform) |
| `RingHeight` | 44.3 (the plinth ring's turf) |
| `PlayRadius`, `BoundaryRadius`, `TerrainRadius` | 1800, 1900, 2750 |
| `PlinthRingRadius`, `PlinthCount`, `PlinthOffsetDeg` | 150, 48, 3.75 |
| `Plates[i]` | 48 entries in ring order: position on the turf, stand point, bearing |
| `PlazaRadius`, `AssetInfo.Spire.r` | Chosen so the last stand lands on turf 90 to 100 studs out (the old names stay; they are what the game reads) |
| `LastStandPoints` | Optional: Vector3 points on open turf that the Last Stand closes on. Without it `ArenaService` takes a point 90 to 100 studs out on a mouth lane (`Heart.mouths[i].bearing` and `.lane`), and without those the two names above |
| `LobbyPosition` | Vector3 (8800, 160, 0) |
| `WaterLevel`, `Lake` | 34; the lake's level, centre and semi-axes |
| `Sectors` | No marsh |
| `Heart`, `Sites`, `Trails`, `Stream`, `Edge` | From `Map1_Layout.json` and `Map1_Terrain.json` |
| `polar(angle, r, y)`, `flatDistance(a, b)` | As today |
| `getBiome(position)` | From the replicated region grid (`Shared.Map1Regions`), today's biome names |
| `heightAt(x, z)` | A terrain raycast first; the coarse grid in `Shared.Map1Regions` as the fallback |

Since the install (18 November) `src/ReplicatedStorage/Shared/ArenaLayout.lua` is this Map 1 layout, and the old
layout is in the vault. `ArenaLayout_GreenLand.lua` no longer exists.

### 3.2 Instances

| Where | What |
|---|---|
| `workspace.Arena.Plinths` | Exactly 48 models, `Plinth01` to `Plinth48` in ring order, each with a `Stand` attachment. Nothing else in the folder |
| `workspace.Arena.Landmarks` | The horn, the platform, the beds and spokes, the peak, lone trees, hedges, berms |
| `workspace.Arena.Skyline`, `workspace.Arena.FarValley` | Persistent models |
| `workspace.Arena.Scatter` | Trees, heather, gorse, boulders, flowers, grouped in cells for streaming |
| `workspace.Arena.Boundary` | The invisible backstop at radius 1,900 |
| `ServerStorage.ArenaData.LootSpawns` | Markers with `Kind`, `Tier`, `Runner`, `DropIn`. A tier-3 marker within 90 studs of the centre. `DropIn = false` under the sails |
| `ReplicatedStorage.Shared.WaterPoints` | Regenerated for Map 1 |
| `ServerStorage.WorldGen.Map1` | The new builders: `Data`, `Terrain`, `Assets`, `Scatter`, `Loot`, `Water`, `Audit`. As built it is a folder: no `init` runs the steps, each builder is called by hand (section 7) |

### 3.3 The data pack

`tools/map1/pack.py` reads the Blender exports and writes one blob pack named `map1_data` with these blobs. All grids
are row-major, row 0 at the north (z = -2752), little-endian.

| Blob | Content |
|---|---|
| `Height` | 1376 x 1376 uint16, y = value / 32 |
| `Material` | 1376 x 1376 uint8, the slot ids of `Map1_Terrain.json` |
| `Region` | 1376 x 1376 uint8 |
| `WaterLevel` | 1376 x 1376 uint16 after the repairs, y = value / 32, 0 = dry |
| `Mask_<Name>` | 688 x 688 uint8 for Conifer, Broadleaf, Gorse, Heather, Boulders, Crags, TallGrass, Wildflowers |
| `Terrain`, `Layout` | The two JSON files as text |
| `Manifest_Landmarks`, `Manifest_Plants`, `Manifest_Skyline`, `Manifest_FarValley` | The asset manifests as text |

The packer also writes `src/ReplicatedStorage/Shared/Map1Regions.lua`: the 240 x 240 region grid (16-stud cells)
and a coarse height grid for clients.

## 4. Packages

Each agent keeps a `notes.md` in its scratch folder, updated as it goes, and writes its files early, so that another
agent can pick the work up if it is cut off.

| Package | Owns | Needs Studio |
|---|---|---|
| blender-3b | `art/blender/map1_green_land.py`, the exports, `art/manifests/Map1_*`, `art/previews/Map1` | No |
| data-pack | `tools/map1/`, `Shared/Map1Regions.lua` | Only to prove the pack loads |
| layout | `Shared/ArenaLayout_GreenLand.lua` | No |
| terrain | `ServerStorage/WorldGen/Map1/Data.lua`, `Terrain.lua` | For the install |
| assets | `ServerStorage/WorldGen/Map1/Assets.lua` and its ids, the uploads | Yes |
| scatter | `ServerStorage/WorldGen/Map1/Scatter.lua`, DetailController's plant table | For the install |
| systems | The Config map switch, loot markers, water points, border, launch, lobby, texts | For the install |
| install | The vault, the lobby move, running every builder, the checks, the pictures | Yes, alone |

## 5. The install order

1. Check that Studio matches the repo and that the place is saved (a restore point).
2. Vault: move the old scripts and data, delete the old scenery, keep `workspace.Arena`, `workspace.Lobby` and the loot folder.
3. Move the lobby. Check a player spawns on it.
4. Clear the old arena's terrain by region. Push the new modules. Swap the layout. Set `Config.Map`.
5. Write the terrain from the data pack. Run its checks (heights against the grid, sealed water, no holes).
6. Insert the uploaded assets, place the landmarks, the skyline and the far valley, then the scatter.
7. Loot markers, water points, the Boundary, ambience.
8. A full practice round, start to finish. Then pictures for the owner from a plinth, the horn's mouth, the forest
   edge and the lake.

## 6. Checks before it counts as done

- Ground under every plinth; all 48 stand points 1.6 above the turf; names in ring order.
- No holes in the terrain; every water cell sealed; the lake and stream can be drunk from.
- Every loot marker is on reachable ground and inside the start ring for its round size.
- The Boundary holds all round at radius 1,900.
- A lone player's round: launch, loot, drink, fight the dummies, the border closes, the round ends, the next begins.
- Frame time and memory on the mid quality level are within ArenaV3 section 7's budgets.
- SyntaxCheck and InputCheck pass. Nothing is left in the Edit data model by a test.

## 7. What the install and the 18 November fixes changed

*Added 18 November 2026 (afternoon). Place version 404, commit `e2226af`. Lines marked **†** are from the afternoon
round: in `src/` and the open Studio session, not yet committed or in a saved version.*

### 7.1 As installed (18 November, morning)

- **The switch.** `Config.Map` is "GreenLand", `Shared.ArenaLayout` is the Map 1 layout (version 3), and the lobby
  stands at (8800, 160, 0). The vault holds the classic arena as decided.
- **Counts.** 42,583 plants in 1,753 cells (the dry plan said 42,634). 446 loot markers were planned and 443 are
  placed: the three under the Peak are left out. 87 water points (40 on the stream, 47 on the lake) and 26 ambience
  emitters.
- **The stream** shows 92 % of the designed water: the packer gives it a wet margin (commit `310f2bb`).
- **The far valley was out of place** on the first played round: 1,580 studs off the centre and tilted 3.46 degrees,
  showing as shards across the sky. It was put back at the map centre. The far meshes are now `Locked`, so a click in
  Studio's 3D view can't drag them, and the audit fails if `Skyline` or `FarValley` is off the centre or turned. If it
  happens again: `workspace.Arena.FarValley:PivotTo(CFrame.identity)`.
- **The old style-test diorama** moved from `Workspace.StyleTest` to `ServerStorage.StyleTest.Diorama`.

### 7.2 Changed against the contract

| Contract | Now | Why |
|---|---|---|
| Decision 11: a lone player's border starts at radius 520 | `MinStartRadius` 700. Two players get 860, 24 get 1,469, 48 keep 1,800. The 3.5 studs a second cap and the 13:50 close are unchanged; a lone ring starts moving at 10:00, two players' at 9:32. Loot is placed out to the start radius less 10 | At 520 a lone tester could not reach the forest (radius 570 to 630). The lake (about 800) is still outside a lone ring |
| Decision 11: the border wall | Neon panels instead of ForceField, which showed only as thin seams by day. Each panel thins with its distance from the camera, because a full sheet dyed the whole valley at full graphics quality. **†** A ground line and a low skirt mark the ring from afar ([GameDesign.md](../GameDesign.md) section 4) | Seen in play at full quality |
| Decision 7: the far view | The far-valley parts are repainted by role in duskier tones (`Map1.Assets.applyLookColors()`), and far blur is off on this map. On each client the far-valley canopy shells fade out when the camera is within 450 to 650 studs of their footprint (`DetailController`), so they don't lie over real trees. A whole tile (1,900 studs wide) loses its canopy at once | The canopy layer showed as dark slabs over streamed-in trees |
| Not in the contract: the Peak | It is a hollow shell, and players could walk in under it. `Map1.Terrain.fillUnder()` raised the ground under it (about 72,000 voxels), and `surveyUnder()` and the audit's new `peak` check watch it. **Run `fillUnder()` again after any terrain write and after the landmarks are placed.** `Map1.Terrain.verify()` was not changed and reports the raised columns as off the grid | Found in play |
| Section 3.2: loot markers | `Map1.Loot.build` leaves out blocked scattered markers and never seats one on a plant or a stone. One marker (`Site:C6:Crate3`) sat on a boulder and was moved by hand onto turf at (-3.4, 37.1, 775.6). A dry run of the builder reproduces the place's 443 | Review and play findings |
| Streaming: the classic arena's numbers | `StreamOutBehavior` is Opportunistic, in the place and in `Map1.Terrain.applyStreaming`. It works only partly: 8,600 to 9,000 plants beyond 1,100 studs stayed loaded for the 40 s watched | Nothing streamed out at all before |
| Decision 4: the look | `Shared.DayCycle` holds one lighting look per arena, picked by `Config.Map`. For Map 1: clear air, grass length 0.1, and the water colour, which `Map1.Terrain.applyLook` now takes from the lighting look. To re-apply in Edit: `Map1.Assets.applyLookColors()`, then `WorldGen.LightingRig.apply()` | The lighting pass |
| Decisions 6 and 10: 48 plinths, one launch | The launch intro's hall holds at most 24 glass cases, so two neighbouring plinths share one. The full cut with two contenders was played by two clients; no picture was taken | 48 cases put the neighbours inside the camera's path |
| Decision 9: names | Player-facing text says "the Horn" for the centre and "the signal" for the start. The lobby's two notice boards were re-worded for Map 1, in the place and in `WorldGen/AssetBuilder/Props.lua` | The final check found the old arena's words on the boards |
| Decision 10: 48 contenders | `FallenSnapshots` keeps 48, the Roll Call is capped at 45 s, and the pick takes whoever played least recently when more than 48 wait. **The place's server size still read 60 on 18 November; it should be 48** | Review findings |

Left as they are, on purpose or for later:
- **Heather on limestone.** 175 of the 11,808 heather mats lie on bare limestone (seen at the Edge); `Scatter` keeps
  Limestone as allowed ground for the hedge hollow's rim.
- **No minimum distance between trunks.** Two firs 2.75 studs apart held a tester for 24 s at (64, -796).
- **Ragged far ridge below about engine quality level 13 of 21.** It is what the engine makes of the far meshes at
  reduced quality; no property change cures it. The cure is one mesh per far-valley tile from Blender.

### 7.3 Where the section 6 checks stand

| Check | State on 18 November |
|---|---|
| Plinths | Pass (audit) |
| Terrain and water | Pass (audit); drinking at the stream and swimming in the lake seen in play |
| Loot markers reachable and inside the start ring | Pass (audit); in a lone round the loot service skipped 286 markers outside radius 690 and placed none beyond the ring |
| The Boundary | Pass (audit); in play it stopped a sprinting, jumping player at radius 1,899.4 |
| A lone player's round | Pass, many times, the last five runs focused at full quality |
| Frame time and memory within ArenaV3 section 7 | **Not measured.** Instances, streamed plants, terrain and texture memory are inside the budgets. Real frame rate and client memory need a focused window or a device; one focused reading at the heart gave 3.76 ms render CPU and 2.43 ms GPU |
| SyntaxCheck, InputCheck, nothing left behind | Pass: 136 scripts compile, 17 actions each in Plate and Arena, no leftovers |

`Map1.Audit.run()` ended the day at 13 pass, 0 fail, 1 manual (checks: switch, layout, plinths, terrain, water, loot,
boundary, peak, instances, lobby, ambience, scripts, leftovers, manual).
