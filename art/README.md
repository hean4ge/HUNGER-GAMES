# LAST STANDING - art pipeline (Blender -> GLB -> Roblox)

Every mesh in the game is built **procedurally** by headless Blender 5.3 scripts in `art/blender/`. Nothing is
hand-modelled, so every asset can be regenerated, tweaked by editing parameters, and reviewed from preview images.
Surfaces come from Roblox PBR materials (Rock, WoodPlanks, LeafyGrass, ...) chosen per part by the manifest, so no
textures are uploaded. Art direction follows `docs/GameDesign.md` section 3: stylized-realistic, chunky readable
shapes, natural slightly desaturated palette, ember-orange accent, no big Neon/SmoothPlastic surfaces.

```
art/
  blender/      generators (one per category) + shared helpers
  manifests/    <Category>.manifest.json - copy of the manifest written next to each GLB (importer input)
  previews/     <Category>/<Asset>_front.png, _back.png (+ Items _side.png), _overview.png, _lineup.png
                _scale_lineup.png (all categories vs a 5.5-stud player), _grip_check.png (Items <-> Arms grip)
BlenderExports (outside the repo, %USERPROFILE%/OneDrive/Documents/LastStanding/BlenderExports)
                <Category>.glb + <Category>.manifest.json  - what Roblox imports
```

## 1. Regenerating

Run each generator headless. Arguments after `--` are the export folder and the preview folder. Runs are seeded,
so the same script produces a byte-identical GLB.

```powershell
$blender = "$env:LOCALAPPDATA/Programs/Blender/blender-5.3.0-windows-x64/blender.exe"
$out     = "$env:USERPROFILE/OneDrive/Documents/LastStanding/BlenderExports"
$prev    = "art/previews"          # run from the repo root

& $blender --background --factory-startup --python art/blender/foliage.py   -- $out $prev   # Foliage.glb
& $blender --background --factory-startup --python art/blender/rocks.py     -- $out $prev   # Rocks.glb
& $blender --background --factory-startup --python art/blender/landmarks.py -- $out $prev   # Landmarks.glb
& $blender --background --factory-startup --python art/blender/buildings.py -- $out $prev   # Buildings.glb + Props.glb
& $blender --background --factory-startup --python art/blender/items.py     -- $out $prev   # Items.glb
& $blender --background --factory-startup --python art/blender/arms.py      -- $out $prev   # Arms.glb
# review sheets made from the exported GLBs (optional; ~1 min per category)
& $blender --background --factory-startup --python art/blender/lineup.py    -- $out $prev
```

| Category | Script (+ modules) | Output | Typical run |
|---|---|---|---|
| Foliage | `foliage.py` | Foliage.glb | ~2 min |
| Rocks | `rocks.py` | Rocks.glb | ~1 min |
| Landmarks | `landmarks.py` | Landmarks.glb | ~1 min |
| Buildings, Props | `buildings.py` (`bld_kit`, `bld_cabin`, `bld_tower`, `bld_mill`, `bld_water`, `bld_swamp`, `bld_props`) | Buildings.glb, Props.glb | ~2 min |
| Items | `items.py` (`items_kit`, `items_melee`, `items_ranged`, `items_consumables`, `items_armor`, `items_crates`) | Items.glb | ~2 min |
| Arms | `arms.py` | Arms.glb | ~2 min |

Each run prints `EXPORTED <glb> (<MB>), <n> assets, <n> warnings`, then one `WARNING` line per problem and one
`PREVIEW` line per image. It also copies the manifest into `art/manifests/`. A clean run has **0 warnings**.
Expected deviations are printed as `NOTE`: held items extend below z = 0 (the grip is the origin) and the WaterWheel
is pivoted on its axle. After any change, open the asset's `_front`/`_back` previews and the category `_lineup.png`.

Optional switches:
- `buildings.py ... -- $out $prev RangerCabin,Watchtower` builds only those assets and adds extra review angles
  under `previews/Buildings/review/`. **It overwrites Buildings.glb and its manifest with that subset**, so always
  finish with a full run.
- `lineup.py ... -- $out $prev Rocks,Items` renders only those lineups. `-- $out $prev none scale` renders only the
  cross-category `_scale_lineup.png` and `_grip_check.png`.
- `LS_DETAIL_DIR=<folder>` (landmarks.py) and `ARMS_DEBUG_DIR=<folder>` (arms.py) write extra close-up review renders.

Upload limit: 20 MB per file. Every GLB is under 2.5 MB, and the library warns above 19 MB (split the category if
that ever happens).

## 2. Shared code

- `ls_common.py` - frozen shared library: roles, mesh helpers, `Library` (validate, preview, GLB export,
  manifest). **Do not edit it.** Fix things in `ls_patch.py` or in the generators instead.
- `ls_patch.py` - art-direction fixes layered on top of `ls_common`. Every generator imports it right after
  `ls_common`:
  1. **Hard edges.** `ls_common.smooth()` called `Mesh.set_sharpness_by_angle`, which does not exist in
     Blender 5.x, and the error was swallowed. Every `smooth_angle` part was therefore fully smooth-shaded (blobby
     log ends, pommels, hoops). The patch uses `set_sharp_from_angle`, so `smooth_angle=N` means smooth below
     N degrees and a hard edge above.
  2. **Ordered bounds.** `boundsMin` and `boundsMax` are now true per-axis min/max in Roblox space. The library
     used to swap the Z component.
  3. **Query flags.** Each part gets `canQuery` and `canTouch` (equal to `collide`). Non-colliding parts get
     CollisionFidelity `Box`, so no physics data is generated for them.
  4. **Repo copy.** The manifest is copied into `art/manifests/` after every export.

  The owner of `ls_common` should fold fixes 1 and 2 into the library and then delete the patch.
- `lineup.py` - review renders built from the **exported GLBs**, so they also check the export itself: axes,
  pivots, materials and shading. It writes the per-category lineups (reference figure or 1-stud cube on each row),
  the cross-category scale lineup, and a grip check that puts the sword in R_HandGrip using only the two manifests'
  Grip attachments.

## 3. Conventions (all categories)

**Units and axes.** 1 Blender unit = 1 stud. Blender is Z-up. The export is Y-up glTF, so Roblox
`(x, y, z) = Blender (x, z, -y)`. An asset's front faces Blender +Y, which is the Roblox **LookVector (-Z)**.

**Pivots.** Each asset's origin is its base centre on the ground: footprint centre, trunk centre, or wall centre.
Exceptions:
- Held items: origin is the hand grip (see Items).
- Arm pieces: origin is the proximal joint.
- WaterWheel: origin is the axle centre.

Bases rest on z = 0. Measured values are within -0.035/+0.02 stud everywhere except held items and the WaterWheel.

**Names.** Each asset is a root named `<Asset>` with one MeshPart per material: `<Asset>_<Role>[_n]`, numbered in
build order. Item crate lids are renamed `<Crate>_Lid` (plus fittings such as `<Crate>_LidMetal`).

**Materials.** Roles live in `ls_common.ROLES` (role -> Roblox material + default colour). The importer must use
each part's manifest `rgb`, not the role default. Multi-tone assets (pine tiers, two-tone canopies, cliff strata)
rely on per-part overrides. Add new roles to ROLES rather than inventing names. This pass needed no new roles.

**Palette.** Stone 105-152 grey-beige; wood and bark 80-150 warm brown; foliage greens 34-134 (darker low down);
clay roofs (98-128, 57-74, 43-54); shingles 86-100 warm grey. Ember Neon (255,128,48) is used only for small coal
beds, lantern cores, the plinth strip and the tier-3 crate seam. The Banner orange (198,94,46) matches the UI
accent. Saturated accents are kept small and purposeful: berries, toadstool caps, apple, medkit, spear rag and the
cock feather.

**Edge treatment.** Rocks, cliffs, foliage canopies, needles and blades are flat-shaded facets. Built pieces are
bevelled or chamfered boxes. Round wood and metal (logs, poles, hoops, pommels) and organic shapes (hands,
sleeves) are smooth-shaded with hard edges above their `smooth_angle`. UVs are box-projected at 8 studs per tile
(`ls_common.box_uv`), so Roblox materials tile the same on every asset.

**Scale references** (checked in `previews/_scale_lineup.png`):

| Reference | Value |
|---|---|
| Player | 5.5 studs |
| Door opening | **4 wide x 7.5 tall** (`bld_kit.DOOR_W/DOOR_H`, used by every enterable building) |
| Interior ceiling | 9.2-9.6 |
| Spire | 58.5 (target ~60) |
| Pines | 28-40 (brief 26-42) |
| Oaks | 23-25 |
| Birches | 25-27 |
| Bushes | 3.6-4.8 (hide a crouching player) |
| Plinth top | 1.5 |
| Crate | 4 x 2.6 x 2.2 (fits the Spire's 5.4 x 3.3 x 4.8 alcoves with room for the lid to open) |
| Weapon handles | 0.10-0.19 across |
| Viewmodel arm | upper arm 0.95 + forearm 0.85 + hand ~0.5 |
| Armour cavity | 2.05 x 1.15 (blocky R15 torso) |

**Collision rules.**

| What | Collision |
|---|---|
| Flat floors, decks, porches, steps, plain walls | `Box` |
| Sloped roofs and convex solids | `Hull` (a Box of a tilted slab fills the room under it). Applies to every roof in every category. |
| Walls with openings, arches and walk-through passages (LobbyGate, RockArch, Spire socle, cabin and mill walls) | `PreciseConvexDecomposition` |
| Tree trunks, boulders, stumps, logs | `Hull` |
| Big cliffs, Spire masonry, plaza | `Default` |
| Climbable oak wood (trunk + standable branches) | `PreciseConvexDecomposition` + part tag `Climbable` |
| Foliage canopies, needles, bushes, roots, twigs, moss, snow, pebbles, trim, frames, shutters, ropes, ladders (visual), banners, glass, water, embers, all held items, all arm pieces | `collide=false`, CanQuery/CanTouch off, so arrows and raycasts pass through and players can hide in bushes |

**Budgets** (all met):

| Category | Budget |
|---|---|
| Roblox limit | 20,000 triangles per mesh. The largest part in the set is 2,432 (SpirePlatform_Cobble). |
| Trees | 900-3,500 |
| Bushes | 570. BerryBush is 1,320: its 42 berries are the forage read, so place it sparsely. |
| Boulders | 320-704 |
| Cliffs | up to 4,000 |
| Spire | 6,028 |
| Buildings | 816-8,538 (RangerCabin is the heaviest) |
| Props | 208-1,000 |
| Items | 270-1,468 |
| Hands | under 2,000 |

## 4. Importing into Roblox

**Manifest schema** (`<Category>.manifest.json`; all vectors are in Roblox space):
```
category, glb, units, axes, warnings[]
assets[]: name, kind, tags[], notes, origin[x,0,0], size[x,y,z], boundsMin[], boundsMax[], tris,
          parts[]:  name, role, robloxMaterial, rgb[r,g,b], collide, collision, castShadow, canQuery, canTouch,
                    tags[], tris
          attachments{ name: {position[], look[], up[]} }     (position relative to the asset origin)
```

**Per-asset import steps** (edit-time builder in `ServerStorage.WorldGen`, run from the command bar or
`execute_luau`):
1. Import the GLB with the 3D Importer or Asset Manager bulk import. Each asset root arrives as a Model with
   MeshParts named as in the manifest.
2. Re-centre. The GLB lays the assets out in a row along X, and `origin` is the asset's pivot inside the file. Set
   `Model.WorldPivot = CFrame.new(origin)`, then `PivotTo(CFrame.new())` to bring the asset to the template origin.
   `boundsMin` and `boundsMax` are relative to that pivot.
3. For every part, set these properties from the manifest:

   | Property | Value |
   |---|---|
   | `Material` | `Enum.Material[robloxMaterial]` |
   | `Color` | `Color3.fromRGB(rgb)` |
   | `CanCollide` | `collide` |
   | `CollisionFidelity` | `collision` |
   | `CastShadow` | `castShadow` |
   | `CanQuery` | `canQuery` |
   | `CanTouch` | `canTouch` |
   | `Anchored` | `true` for everything static |

   CollisionFidelity can only be changed at edit time, never by game scripts.
4. Attachments: create each one under the asset's main part with
   `WorldCFrame = pivot * CFrame.lookAt(position, position + look, up)`. Then `LookVector` = `look` and
   `UpVector` = `up`.
5. Tags. Asset `tags` are descriptive; store them as an attribute or use them to sort into `WorldAssets/<kind>`.
   Only these map to the game's CollectionService tags:
   - asset tag `Plinth`
   - part tag `Climbable` (OakA_Bark, OakB_Bark)

   Add `AmbientEmitter` (attribute `SoundKey`) yourself at fire, water and wheel attachments (Brazier.Fire,
   Campfire.FireCenter, RiverMill.WheelAxle). Helper part tags: `Floor` (walkable deck), `Lid`, `LadderVisual`.
6. Glass: water_bottle/empty_bottle `_Glass` Transparency ~0.45, item `WaterFill` ~0.2, mill and well `WaterFill`
   ~0.35. Ember parts are Neon: add warm PointLights at the attachments listed below.

### Imported: Items.glb and Arms.glb (2026-11-11)

- Uploaded once through Open Cloud as Model assets **LS_Items_v1 = 89569069083663** and **LS_Arms_v1 =
  130319005401961** (creator user 5458010221, both Approved). The raw inserts live in `ServerStorage.MeshImports`
  (packages; never edit them). Re-uploading is only needed after a re-export of the GLB.
- `ServerStorage.WorldGen.ItemAssets.build()` turns them into `ReplicatedStorage.Assets.Items/Crates/Viewmodel`; its
  `Manifest` child is generated from these manifests (regenerate it after a re-export). The importer bakes a 180 degree
  turn about Y into every mesh and insert_asset adds a random yaw; the builder measures and undoes both.
- Item templates carry an invisible `Handle` at the Grip in the game's ItemModels convention (LookVector = business
  end, UpVector = blade spine), not the manifest's Grip frame (whose up is the edge). Crates get an invisible `Base`
  collision box; the body meshes are visual only. The Studio importer drops every colour (all parts arrive grey
  Plastic), so material and rgb always come from the manifest.

### Category notes

**Foliage.**
- Leaning trees lean away from the pivot. FallenLog lies along X with its fungi on the front (+Z Roblox is the back).
- Oaks have `Perch1..N` on the level tops of the standable branches: 1.6-2.0 wide, 9.4-15.2 up, look = along the
  branch.
- Use per-part rgb for the 2-3 needle and leaf tones.
- `BerryBush_Berry` can be hidden when picked.
- Stump and FallenLog are hop-on (top ~2.3, Hull). Roots are walk-through on purpose, so feet never snag.

**Rocks.** Centred on the footprint.
- Sink boulders and the pile 0.1-0.3 into the terrain.
- Bury a cliff's stepped back 2-6 studs into the hillside with the steep layered face (-Z) out.
- RockArch: passage along Z, 8 wide at the ground, 6.7 at head height, 8.65-9.5 clear. Its bands now use
  PreciseConvexDecomposition so the opening can't be bridged. `PassageCenter` sits on the ground in the opening.
- StandingStones: `RingCenter` is ~12 studs in front for a fire or loot.

**Landmarks.**
- Spire + SpirePlatform: both at the arena centre with the same rotation. The plaza top (0.6) is flush with the
  first tread, and the treads (1-stud risers) climb to the terrace at 3.6. The slit runs along Roblox Z.
- Spire attachments: `Beacon` (0, 54.5, 0) for the fire, light and smoke. `CrateSlot_1..4` are the alcove floors
  (look = out of the alcove); use them as LootSpawn markers with Kind Crate.
- Plinth: LookVector toward the Spire (the ember strip faces it); `Stand` at 1.5. Place 24 pads on the r ~ 39
  cobble ring, 15 degrees apart.
- Pavilion and LobbyGate roofs are now Hull. Lanterns take PointLights at `Lantern`; Brazier uses `Fire`.
- NoticeBoard: SurfaceGui on `NoticeBoard_Planks`, Face Front (`Board`).
- Bench: `Seat_1/2` for Seat parts.
- Railing tiles every 8 studs along X as a solid Box barrier.
- LobbyGate opening is 8.9 wide x 8.9 clear (10.9 under the keystone).

**Buildings.**
- Doors are 4 x 7.5. `Door` attachments sit at the threshold, facing out.
- Ladders need invisible TrussParts. TrussPart sizes snap to 2 studs.
  - RangerCabin: 2x10x2 from `LadderBase` (-2.75, 1, 3) up to the loft at `LadderTop` y = 10.9. The climber faces
    -X.
  - Watchtower: 2x22x2 from `LadderBase` (1.75, 0, 1.75) to the deck at 22, through the 2.5 x 2.5 well. The deck
    is 4 Box parts so the well stays open; the roof is now Hull.
- WaterWheel: put its origin on `RiverMill.WheelAxle` (13.6, 7.4, 0) with the mill's rotation, and spin it on the
  client about its own X axis (`* CFrame.Angles(dt*speed, 0, 0)`). Only the rims and spokes collide (Hull).
- Bridge spans X: `EndWest`/`EndEast` at deck height 0.95, 3.35 mid-span.
- Jetty runs along Z: `ShoreEnd` at +Z, `WaterEnd` at -Z, deck top 3. Sink the piles into the lake bed.
- StiltHut: floor at 7; the ramp lands at `RampFoot` (20.6, 0, -8.3).
- WalkwaySegment chains `EndA`/`EndB` every 12 studs along Z, deck top 2.
- Some PreciseConvexDecomposition parts are joined from separate pieces (porch posts, stilts, tower legs). Check
  in Studio that every doorway and under-hut space stays open.

**Props.**
- Campfire: PointLight + fire at `FireCenter`.
- Lantern: hang from `HangPoint`, light at `Glow`.
- Sign: SurfaceGui at `SignFace`.
- Well: the Hull shaft means nobody can fall in.
- FenceSegment tiles every 8 along X.
- CratePile and Woodpile are cover (Box).

**Items** (held items).
- Origin = the hand grip.
- `Grip` attachment: look = item axis (Roblox +Y), up = edge or front (Roblox -Z).
- To hold an item, align the item's Grip frame with the hand's Grip frame:
  `item:PivotTo(handGrip.WorldCFrame * itemGripLocal:Inverse())`, or use a RigidConstraint between the two
  attachments. The two Grip conventions match: look = toward the blade, up = edge toward the knuckles.
  `_grip_check.png` shows the sword placed this way.
- `Tip` sits on blades, spear, arrow, mace and hatchet bit.
- Bow:
  - `Nock` = string centre, look = shot direction.
  - `StringTop`/`StringBottom` anchor two Beams for the draw; hide `bow_Rope` while drawing.
  - `ArrowRest` is on the -X side of the riser window.
  - The arrow's `Nock` is its origin: align it to the bow's Nock, arrow +Y along the string.
- Crates:
  - `<Crate>_Lid` plus the `Lid`-tagged fittings rotate about `LidHinge` (+X axis, back top edge); ~100 degrees
    opens it.
  - `Prompt` (ProximityPrompt) is in front; `LootPoint` is inside on the floor.
  - Optional small orange PointLight at LootPoint for tier 3.
- Vests: weld `Torso` to UpperTorso.
- Ground loot: offset by `-boundsMin.y` so the item rests on the ground. Pickup is by ProximityPrompt, since item
  parts are CanQuery off. Enable CanQuery on dropped copies only if a raycast pickup is ever added.

**Arms** (first-person viewmodel, **world scale**).
- Bone axis = Roblox +Y (the part's UpVector), pivot = proximal joint, LookVector = back of the arm or hand. The
  thumb is +X on R_ pieces; L_ pieces are exact X-mirrors (negate X to mirror an animation).
- Chain: `UpperArm.Elbow` (0, 0.95, 0) -> Forearm origin; `Forearm.Wrist` (0, 0.85, 0) -> hand origin.
- Bend the elbow toward Roblox +Z (the inner-elbow folds).
- Hand attachments:

  | Attachment | Position | Look | Up |
  |---|---|---|---|
  | `R_HandGrip.Grip` | (0.013, 0.257, 0.118) | (0.985, 0.174, 0) | (-0.174, 0.985, 0) |
  | `L_HandGrip.Grip` | X mirrored | X mirrored | X mirrored |
  | `Palm` | (0, 0.18, 0.066) | out of the palm | toward the fingers |
  | `Knuckles` | (+/-0.052, 0.339, 0.033) | punch direction | back of the hand |

- The hand closes around a 0.15 handle, which matches the Items handles (0.10-0.19). Fingers press slightly into
  thicker grips, which hides any gap.
- Camera placement at world scale: eye at the camera, shoulders ~0.5 below and ~0.4 to each side, hands ~1 stud
  ahead, 70 degree FOV. The `_assembled_*.png` previews show these poses; they were rendered at modelling scale,
  so the framing is the same.
- Skin parts can be recoloured to the avatar's skin tone. Every piece is non-colliding, CastShadow off and
  CanQuery/CanTouch off.
- For a chunkier viewmodel, scale the assembled arms **and** the held item together (`Model:ScaleTo`) so the
  grip stays 1:1.

## 5. Asset inventory (final export)

Sizes are Roblox X x Y x Z in studs (Y = height). "Parts (colliding)" = MeshParts in the asset (how many collide).

### Foliage.glb - 1.87 MB, 18 assets, 26,614 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| PineA | Tree | 13.33 x 34.08 x 14.93 | 1,874 | 5 (1) | - |
| PineB | Tree | 11.97 x 40.01 x 11.83 | 1,818 | 5 (1) | - |
| PineC | Tree | 15.82 x 27.95 x 15.04 | 1,672 | 5 (1) | - |
| OakA | Tree | 25.73 x 23.33 x 24.38 | 3,137 | 4 (1) | Perch1-4 |
| OakB | Tree | 28.90 x 25.40 x 25.23 | 3,461 | 4 (1) | Perch1-5 |
| BirchA | Tree | 10.20 x 25.17 x 9.30 | 1,718 | 5 (1) | - |
| BirchB | Tree | 12.47 x 27.35 x 11.72 | 1,864 | 6 (2) | - |
| DeadTreeA | Tree | 11.24 x 19.73 x 9.82 | 910 | 2 (1) | - |
| DeadTreeB | Tree | 8.82 x 16.45 x 8.85 | 1,468 | 3 (1) | - |
| BushA | Bush | 7.18 x 4.22 x 6.71 | 570 | 1 (0) | - |
| BushB | Bush | 7.68 x 3.62 x 7.46 | 570 | 1 (0) | - |
| BushC | Bush | 5.72 x 4.77 x 5.52 | 570 | 1 (0) | - |
| BerryBush | Bush | 6.94 x 4.06 x 6.59 | 1,320 | 2 (0) | - |
| FernClump | Plant | 5.00 x 2.10 x 5.96 | 940 | 1 (0) | - |
| ReedsClump | Plant | 4.99 x 5.72 x 6.17 | 1,156 | 2 (0) | - |
| MushroomCluster | Plant | 3.01 x 2.31 x 2.66 | 1,184 | 2 (0) | - |
| Stump | Prop | 6.36 x 2.94 x 5.86 | 952 | 3 (1) | - |
| FallenLog | Prop | 15.43 x 2.94 x 3.89 | 1,430 | 5 (1) | - |

### Rocks.glb - 1.06 MB, 12 assets, 17,612 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| BoulderA | Rock | 2.84 x 1.82 x 3.00 | 320 | 1 (1) | - |
| BoulderB | Rock | 4.73 x 2.89 x 5.00 | 394 | 2 (2) | - |
| BoulderC | Rock | 8.00 x 4.39 x 6.08 | 468 | 2 (1) | - |
| BoulderD | Rock | 11.56 x 6.10 x 13.00 | 704 | 2 (1) | - |
| CliffChunkA | Cliff | 29.32 x 17.32 x 19.52 | 2,190 | 4 (4) | - |
| CliffChunkB | Cliff | 42.60 x 27.39 x 21.05 | 3,642 | 4 (4) | - |
| CliffChunkC | Cliff | 46.62 x 39.04 x 24.34 | 3,982 | 5 (4) | - |
| RockPile | Rock | 6.00 x 2.36 x 3.86 | 956 | 3 (3) | - |
| Pebbles | Rock | 6.51 x 0.29 x 4.78 | 694 | 3 (0) | - |
| StandingStones | Landmark | 15.87 x 9.18 x 4.35 | 1,384 | 4 (3) | RingCenter |
| FlatStone | Rock | 10.22 x 1.49 x 7.99 | 288 | 3 (2) | - |
| RockArch | Landmark | 20.00 x 14.05 x 11.20 | 2,590 | 4 (3) | PassageCenter |

### Landmarks.glb - 1.38 MB, 11 assets, 21,130 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| Spire | Landmark | 40.00 x 58.45 x 40.00 | 6,028 | 9 (7) | CrateSlot_1-4, Beacon |
| SpirePlatform | Plaza | 119.91 x 0.95 x 119.91 | 6,112 | 4 (4) | - |
| Plinth | StartPad | 5.86 x 1.50 x 5.83 | 588 | 5 (4) | Stand |
| Pavilion | Building | 24.34 x 13.91 x 16.34 | 3,308 | 10 (5) | Lantern |
| Brazier | Prop | 4.58 x 5.37 x 4.58 | 1,308 | 3 (1) | Fire |
| BannerPole | Prop | 4.34 x 12.40 x 1.60 | 1,146 | 5 (2) | - |
| Bench | Prop | 6.30 x 1.80 x 1.75 | 176 | 2 (2) | Seat_1, Seat_2 |
| NoticeBoard | Prop | 11.00 x 10.61 x 2.36 | 528 | 6 (5) | Board |
| Railing | Railing | 8.00 x 3.60 x 1.24 | 428 | 3 (3) | - |
| LobbyGate | Gate | 15.93 x 13.99 x 5.23 | 1,272 | 7 (3) | Lantern |
| StoneSteps | Stairs | 8.00 x 3.35 x 6.00 | 236 | 2 (2) | - |

### Buildings.glb - 2.44 MB, 9 assets, 36,382 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| RangerCabin | Building | 30.24 x 24.18 x 24.01 | 8,538 | 25 (18) | LadderBase, LadderTop, Door |
| Watchtower | Building | 14.23 x 35.41 x 14.23 | 4,668 | 18 (13) | LadderBase, LadderTop |
| RiverMill | Building | 30.40 x 22.75 x 21.68 | 5,812 | 24 (13) | WheelAxle, Door |
| WaterWheel | Mechanism | 6.30 x 13.77 x 13.77 | 2,000 | 3 (1) | Axle |
| Bridge | Building | 39.12 x 6.58 x 11.14 | 4,384 | 7 (6) | EndWest, EndEast |
| FishingShack | Building | 15.49 x 13.70 x 15.44 | 2,792 | 17 (9) | Door |
| Jetty | Building | 6.72 x 5.03 x 24.50 | 2,924 | 8 (5) | ShoreEnd, WaterEnd |
| StiltHut | Building | 30.20 x 25.57 x 20.00 | 4,448 | 18 (15) | Door, RampFoot |
| WalkwaySegment | Building | 4.52 x 2.00 x 12.00 | 816 | 3 (3) | EndA, EndB |

### Props.glb - 0.36 MB, 9 assets, 5,410 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| Tent | Prop | 7.02 x 5.15 x 12.92 | 550 | 5 (1) | - |
| Campfire | Prop | 3.75 x 1.39 x 3.84 | 648 | 4 (1) | FireCenter |
| FenceSegment | Prop | 8.11 x 4.65 x 0.51 | 208 | 2 (2) | - |
| CratePile | Prop | 6.46 x 5.43 x 5.81 | 848 | 2 (1) | - |
| Barrel | Prop | 2.35 x 3.20 x 2.30 | 696 | 2 (1) | - |
| Lantern | Prop | 0.90 x 2.19 x 0.90 | 280 | 2 (0) | HangPoint, Glow |
| Well | Prop | 7.55 x 7.30 x 6.53 | 1,000 | 10 (4) | - |
| Woodpile | Prop | 6.38 x 3.09 x 3.01 | 888 | 3 (1) | - |
| Sign | Prop | 5.61 x 6.61 x 1.81 | 292 | 3 (2) | SignFace |

### Items.glb - 0.97 MB, 23 assets, 18,634 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| knife | Weapon | 0.15 x 1.34 x 0.31 | 642 | 4 (0) | Grip, Tip |
| machete | Weapon | 0.14 x 2.52 x 0.35 | 868 | 5 (0) | Grip, Tip |
| hatchet | Weapon | 0.20 x 2.13 x 0.65 | 828 | 4 (0) | Grip, Tip |
| spear | Weapon | 0.26 x 7.02 x 0.36 | 1,252 | 7 (0) | Grip, Tip |
| mace | Weapon | 0.44 x 2.80 x 0.48 | 1,178 | 5 (0) | Grip, Tip |
| sword | Weapon | 0.17 x 3.63 x 0.82 | 1,216 | 5 (0) | Grip, Tip |
| bow | Weapon | 0.20 x 4.53 x 0.58 | 996 | 5 (0) | Grip, Nock, StringTop, StringBottom, ArrowRest |
| arrow | Ammo | 0.19 x 3.05 x 0.22 | 562 | 7 (0) | Grip, Nock, Tip |
| throwing_knife | Weapon | 0.08 x 1.02 x 0.16 | 888 | 4 (0) | Grip, Tip |
| water_bottle | Drink | 0.45 x 1.00 x 0.45 | 490 | 4 (0) | Grip, Mouth |
| empty_bottle | Drink | 0.65 x 0.90 x 0.42 | 498 | 3 (0) | Grip, Mouth |
| berries | Food | 0.42 x 0.63 x 0.40 | 484 | 4 (0) | Grip |
| apple | Food | 0.43 x 0.50 x 0.43 | 270 | 3 (0) | Grip |
| dried_meat | Food | 0.40 x 0.84 x 0.33 | 490 | 3 (0) | Grip |
| ration | Food | 0.49 x 0.66 x 0.48 | 488 | 2 (0) | Grip |
| bandage | Medical | 0.36 x 0.46 x 0.39 | 344 | 2 (0) | Grip |
| herbs | Medical | 0.45 x 0.78 x 0.38 | 476 | 3 (0) | Grip |
| medkit | Medical | 1.04 x 0.79 x 0.48 | 464 | 4 (0) | Grip |
| leather_vest | Armor | 2.30 x 2.38 x 1.41 | 1,432 | 4 (0) | Grip, Torso |
| padded_armor | Armor | 2.44 x 2.49 x 1.60 | 1,468 | 3 (0) | Grip, Torso |
| SupplyCrate1 | Crate | 4.00 x 2.20 x 2.61 | 960 | 3 (3) | LidHinge, Prompt, LootPoint |
| SupplyCrate2 | Crate | 4.36 x 2.25 x 2.64 | 1,188 | 6 (3) | LidHinge, Prompt, LootPoint |
| SupplyCrate3 | Crate | 4.00 x 2.23 x 2.78 | 1,152 | 5 (3) | LidHinge, Prompt, LootPoint |

### Arms.glb - 0.51 MB, 10 assets, 14,764 tris

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| R_UpperArm | ViewmodelArm | 0.32 x 1.10 x 0.33 | 736 | 1 (0) | Shoulder, Elbow |
| R_Forearm | ViewmodelArm | 0.27 x 0.95 x 0.26 | 794 | 3 (0) | Elbow, Wrist |
| R_HandGrip | ViewmodelHand | 0.27 x 0.45 x 0.36 | 1,926 | 3 (0) | Wrist, Grip |
| R_HandOpen | ViewmodelHand | 0.29 x 0.58 x 0.25 | 1,936 | 3 (0) | Wrist, Palm |
| R_HandFist | ViewmodelHand | 0.26 x 0.36 x 0.31 | 1,990 | 3 (0) | Wrist, Knuckles |
| L_UpperArm | ViewmodelArm | 0.32 x 1.10 x 0.33 | 736 | 1 (0) | Shoulder, Elbow |
| L_Forearm | ViewmodelArm | 0.27 x 0.95 x 0.26 | 794 | 3 (0) | Elbow, Wrist |
| L_HandGrip | ViewmodelHand | 0.27 x 0.45 x 0.36 | 1,926 | 3 (0) | Wrist, Grip |
| L_HandOpen | ViewmodelHand | 0.29 x 0.58 x 0.25 | 1,936 | 3 (0) | Wrist, Palm |
| L_HandFist | ViewmodelHand | 0.26 x 0.36 x 0.31 | 1,990 | 3 (0) | Wrist, Knuckles |

**Total: 92 assets in 7 GLBs, 140,546 tris, 8.6 MB.**

## 6. Art-direction pass (2026-11-10): what changed and why

1. **`ls_patch.py` (new), imported by all six generators.** It fixes hard edges, so smooth-angle parts in
   Foliage, Buildings, Props, Items and Arms get the crisp rims, caps and creases their authors specified.
   Landmarks' private copy of that fix was removed. The patch also orders the manifest bounds, adds explicit
   CanQuery/CanTouch flags with Box fidelity on non-colliders, and copies every manifest into `art/manifests/`.
2. **Arms exported at world scale** (`arms.py` `KIT_SCALE = 0.5`). The kit had been modelled at 2x: a 4.8-stud
   arm against a 5.5-stud player, with a fist built around a 0.3 handle while every weapon handle is 0.10-0.19.
   Held weapons would have floated in a giant hand. Attachments and notes were scaled to match.
3. **Doors standardised to 4 x 7.5** in all enterable buildings: RangerCabin, RiverMill, FishingShack and StiltHut
   were 4.6-5.0 x 8.2-8.4.
4. **Every sloped roof uses Hull.** The Pavilion, NoticeBoard, LobbyGate and Watchtower roofs were Box, which gave
   them flat invisible tops and blocked arrows above the slopes.
5. **RockArch collision is PreciseConvexDecomposition**, the same rule as the LobbyGate arch, so the walk-through
   passage can't be bridged by the coarse Default decomposition.
6. **WaterWheel below-ground extent is reported as a NOTE.** The axle pivot is by design. Manifest warnings are now
   0 in all categories.
7. **FernClump crown sunk 0.02.** It floated 0.03 above the ground.
8. **`lineup.py` (new)** renders review sheets from the exported GLBs: per-category lineups, the cross-category
   scale lineup and the grip check.

## 7. Known limitations / to verify in Studio

- Previews are Workbench renders with flat colours. Roblox's LeafyGrass, WoodPlanks, Slate and ClayRoofTiles
  textures and Future lighting will change the look. Check one asset of each material in Studio, especially the
  darkest pine tier (36,62,40).
- Canopies, bushes and needles are closed, single-sided shells. From inside a bush you see out, and its inside
  shows no leaves.
- RangerCabin's full extent is 30 x 24 because of the porch and eaves (log walls 25.2 x 17.2). It is the heaviest
  building at 8.5k tris.
- CliffChunkC sits at 3,982 of 4,000 tris. Re-check after any parameter change, because its random stream
  reshuffles.
- Spire steps use Default collision. If players snag on the step edges, switch `Spire_Granite` to
  PreciseConvexDecomposition.
- Long thin items (spear, bow, arrow) look slender straight-on. Render their hotbar icons diagonally.
- Workbench stencil shadows show faint triangle streaks on low-poly faces. This affects previews only.

## 8. TreesReal - realistic, textured forest trees (2026-11-11)

Replaces the stylised Foliage trees for the classic forest arena. Unlike sections 1-7, this set is **textured**:
every part gets a SurfaceAppearance built from shared PNGs, and species differ only by the SurfaceAppearance tint.

```powershell
& $blender --background --factory-startup --python art/blender/trees_real.py -- $out $prev textures   # ~5 min
```

- Scripts: `trees_real.py` (geometry, materials, export, manifest), `tex_trees.py` (all textures: numpy bark synthesis
  and Cycles-rendered card atlases), `trees_review.py` (EEVEE review renders made from the exported GLB under
  Blender's physical sky).
- Flags: `textures` rebuilds the PNGs (otherwise the existing ones are reused), `only=A,B` builds a test subset into
  `_TreesReal_Test.glb`, `nopreview` / `nosheets` skip renders, and `split` writes `TreesReal_Conifers/_Broadleaf/
  _Deadwood.glb` (this also happens automatically above 18 MiB; each split GLB embeds its own copy of the shared images).
- Output: `TreesReal.glb` (14 assets, 17.5 MiB, 14 embedded images), `TreesReal.manifest.json`, and
  `textures/TreesReal/` with 14 PNGs: 6 colour (the two card atlases are RGBA), 6 OpenGL normal maps, and 2 **8-bit
  grayscale roughness maps**. The `glb_only/*_MR.png` files are the glTF-packed copies (R = G = roughness, B = 0) that
  are embedded in the GLB. **Never upload them.**
- Every export prints a `GLBCHECK` line:
  - TANGENT, TEXCOORD_0 and NORMAL are on every primitive. Faces with more than 4 corners are fanned into triangles,
    because the exporter drops tangents on n-gons.
  - `metallicFactor` is 0 on every material, set by patching the GLB JSON after export.
  - Every embedded image is byte-identical to its PNG.
  - A clean run has 0 warnings.
- Previews in `previews/TreesReal/`: `<Asset>.png` shows eye level at 8 studs, eye level at 25 studs and the full tree,
  each next to a 5.5-stud figure. `_lineup.png` lines up all 14 assets, and `_forest.png` / `_forest_b.png` are
  eye-level forest groups.

**Manifest additions** (on top of section 4):
- Per part:
  - `surfaceAppearance`: `colorMap`, `normalMap`, `roughnessMap`, `metalnessMap` (null), `alphaMode`, and `color`
    (the tint; it is mandatory).
  - `doubleSided` (always false), `backFacesInMesh`, `transparency` (0), and `alphaSetup` on alpha parts.
- Per asset: `barkPxPerStud`.
- Top level: `materials` (tint, effective albedo and roughness per material), `textures`, `glbOnlyTextures`,
  `tangentSpace` and `import` (the step list).
- Import rules:
  - Cards: AlphaMode `Transparency`, `MeshPart.Transparency = 0` (alpha-tested, no sorting) and
    `DoubleSided = false`. The back faces are real flipped geometry.
  - `OakA_Bark` (PreciseConvexDecomposition) gets the `Climbable` tag. Use the Perch1-4 attachments.

| Asset | Kind | Size X x Y x Z (studs) | Tris | Parts (colliding) | Attachments |
|---|---|---|---|---|---|
| SpruceA | Tree | 18.19 x 55.26 x 17.10 | 8,503 | 5 (1) | - |
| SpruceB | Tree | 15.15 x 36.22 x 14.98 | 6,060 | 5 (1) | - |
| FirA | Tree | 12.59 x 42.23 x 12.76 | 8,532 | 5 (1) | - |
| PineA | Tree | 21.29 x 54.55 x 25.45 | 8,534 | 6 (2) | - |
| ConiferYoung | Tree | 5.57 x 11.80 x 5.94 | 2,039 | 2 (1) | - |
| BirchA | Tree | 18.54 x 30.34 x 19.75 | 5,427 | 6 (2) | - |
| BirchB | Tree | 21.75 x 28.55 x 19.84 | 8,892 | 8 (4) | - |
| OakA | Tree | 29.24 x 28.91 x 29.16 | 8,628 | 5 (1) | Perch1-4 (10.4-14.3 up) |
| SnagA | Tree | 8.98 x 28.10 x 9.21 | 3,687 | 6 (2) | - |
| SnagB | Tree | 8.91 x 20.36 x 9.95 | 2,867 | 6 (2) | - |
| FallenLogA | Prop | 15.77 x 1.99 x 2.35 | 1,166 | 4 (2) | - |
| FallenLogB | Prop | 22.36 x 3.22 x 3.27 | 2,262 | 3 (2) | - (top 2.3, hop-on) |
| StumpA | Prop | 5.68 x 2.82 x 5.57 | 508 | 5 (2) | - (top 2.1) |
| StumpB | Prop | 4.51 x 4.62 x 4.98 | 660 | 4 (2) | - |

The Y sizes include the roots, which dive 0.17-0.82 studs below the pivot so that trees on slopes never float.
Total: 67,765 tris.

**Known limitations / to verify in Studio**
- Bark texel density at 1 stud above the ground is 126-141 px/stud on the four thickest trunks (SpruceA, PineA,
  OakA, StumpB). One 1024 px tile wraps each trunk, and two tiles would mean about 270 px/stud and half-size bark
  features. The other trunks are 146-297; ConiferYoung's thin stem is 602.
- From 8-15 studs, spruce cards seen face-on against a bright sky can still read as broad flat fronds. From 25 studs
  on, the crowns read as dense, drooping spruce.
- One roughness map per family. Moss and end grain share the foliage map (0.72), which is a bit glossy for moss.
- Unverified in Roblox:
  - whether card shadows come out dappled (if they are solid, set `CastShadow = false` on that Foliage part);
  - how the importer treats the embedded packed roughness (the separate grayscale maps cover this);
  - whether bark that tiles outside the 0..1 UV range repeats.

## 9. ItemsReal - realistic, textured items and supply crates (2026-11-11)

Drop-in replacement for the v1 Items set (20 held items + SupplyCrate1/2/3). The first-person arms are **not**
rebuilt: the original simple hands stay (no ArmsReal).

```powershell
& $blender --background --factory-startup --python art/blender/items_real.py -- $out $prev   # ~15 min with renders
#  switches: norender | sets=IR_Weapons,IR_Supplies (partial GLB - finish with a full run) | assets=knife,sword |
#            renderonly [only=knife,bow] | renderonly lineuponly
python art/blender/ir_verify.py $out art/manifests      # contract check against the v1 Items manifest
```

- **Modules** (all private to this set): `items_real.py` (driver), `tex_items.py` (UV atlas, Cycles data bake,
  PNG writer, GLB export + verification), `tex_items_mats.py` (procedural numpy materials: forged and carbon steel,
  wrought iron with rivets, brass, tinplate, oiled hardwood, weathered planks with nail heads and a burnt brand,
  leather with seams, cord and laid rope, canvas, gauze, quilted linen, glass, water, apple, berries, smoked meat,
  bone, printed paper, leaves), `ir_geo.py` (UV'd lofts, sweeps, lathes, blades, leaves), `ir_weapons.py`,
  `ir_supplies.py`, `ir_crates.py`, `ir_armor.py`, `ir_render.py` (Cycles reviews of the exported GLB under
  Blender's built-in sky), `ir_verify.py`.
- **Pipeline**: each mesh piece is tagged (material id, grain frame that follows swept/bent pieces, per-piece
  random, edge radius, material attributes) -> one 1024 UV atlas per texture set -> Cycles bakes object position,
  normal, grain frame, ids, AO (3 radii), convexity and a rounded-edge normal -> materials evaluated per texel in
  3D (no UV seams; wear on real edges, grime in real crevices, rust under real nails) -> PNGs.
- **Textures**: 4 sets x {Color, Normal (OpenGL +Y), Roughness, Metalness} = **16 PNGs**, 1024, 8-bit, roughness and
  metalness as separate grayscale images, in `textures/ItemsReal/`. The GLB embeds Color + Normal + a packed glTF
  metallicRoughness (`<Set>_ORM`, R = baked AO) per set; never upload the ORM separately.
  `IR_Weapons` (9 weapons), `IR_Supplies` (9 drinks/food/medical; Color has alpha for the glass and water only),
  `IR_CratesA` (SupplyCrate1, 2), `IR_CratesB` (SupplyCrate3, leather_vest, padded_armor).
- **Tangents**: exported with `export_tangents=True`. n-gons (lathe/sweep caps, extruded profiles) are triangulated
  when each part is finalised, because the exporter's MikkTSpace silently skips meshes with n-gons; every part has
  a UV map (also the untextured Ember strip). `glbCheck` in the manifest records the result (64/64 primitives with
  TANGENT).
- **Swap-in contract** (checked by `ir_verify.py`, 0 problems): same 23 asset names and kinds, same origins
  (held items: hand grip; crates: floor centre), every v1 attachment at the same position / look / up (Grip, Tip,
  Nock, StringTop, StringBottom, ArrowRest, Mouth, Torso, LidHinge, Prompt, LootPoint). Part lists are leaner (one
  MeshPart per surface group, e.g. `knife_Steel` + `knife_Leather`); the names the game relies on are kept:
  `<Crate>_Lid` plus the Lid-tagged `SupplyCrate2_LidMetal` / `SupplyCrate3_LidDarkMetal`, `SupplyCrate3_Ember`
  (separate Neon part), `bow_Rope` (string, serving, nock bead), `water_bottle_Glass`, `water_bottle_WaterFill`,
  `empty_bottle_Glass`.
- **Import**: follow the manifest's `import` notes. One SurfaceAppearance per part from its `surfaceAppearance`
  block; glass and water parts use AlphaMode Transparency with `MeshPart.Transparency = 0.02` (the colour-map alpha
  holds the opacity); everything else is opaque. `rgb` is the mean texture colour (fallback MeshPart.Color).
  Viewmodel copies of held items: CastShadow off.
- **Texel density** (median px/stud): held items 170-295; crates and armour 53-63 (large surfaces; the 16-image
  budget caps them).
- **Review**: `previews/ItemsReal/<asset>.png` (close-up + gameplay distance with a 5.5-stud figure; crates add a
  lid-open shot; armour is worn by the figure), `_lineup.png` (all 23 assets at eye level), `_contact.png`.

| Asset | Kind | Size X x Y x Z | Tris | Parts | Texture set | px/stud |
|---|---|---|---|---|---|---|
| knife | Weapon | 0.11 x 1.35 x 0.27 | 1,788 | 2 | IR_Weapons | 275 |
| machete | Weapon | 0.12 x 2.53 x 0.34 | 1,008 | 2 | IR_Weapons | 258 |
| hatchet | Weapon | 0.11 x 2.14 x 0.65 | 1,008 | 2 | IR_Weapons | 230 |
| spear | Weapon | 0.21 x 7.02 x 0.30 | 2,432 | 2 | IR_Weapons | 199 |
| mace | Weapon | 0.41 x 2.81 x 0.46 | 1,844 | 2 | IR_Weapons | 225 |
| sword | Weapon | 0.10 x 3.68 x 0.75 | 2,440 | 2 | IR_Weapons | 230 |
| bow | Weapon | 0.17 x 4.52 x 0.56 | 1,996 | 2 | IR_Weapons | 169 |
| arrow | Ammo | 0.16 x 3.06 x 0.18 | 1,128 | 2 | IR_Weapons | 214 |
| throwing_knife | Weapon | 0.06 x 1.02 x 0.15 | 1,488 | 2 | IR_Weapons | 270 |
| water_bottle | Drink | 0.45 x 1.00 x 0.45 | 1,440 | 4 | IR_Supplies | 245 |
| empty_bottle | Drink | 0.64 x 0.90 x 0.42 | 1,528 | 3 | IR_Supplies | 294 |
| berries | Food | 0.34 x 0.70 x 0.23 | 2,332 | 3 | IR_Supplies | 270 |
| apple | Food | 0.32 x 0.31 x 0.32 | 756 | 3 | IR_Supplies | 245 |
| dried_meat | Food | 0.37 x 0.84 x 0.32 | 1,016 | 3 | IR_Supplies | 294 |
| ration | Food | 0.49 x 0.67 x 0.48 | 1,556 | 2 | IR_Supplies | 263 |
| bandage | Medical | 0.32 x 0.42 x 0.27 | 796 | 2 | IR_Supplies | 263 |
| herbs | Medical | 0.30 x 0.65 x 0.28 | 2,180 | 3 | IR_Supplies | 245 |
| medkit | Medical | 1.02 x 0.78 x 0.47 | 1,088 | 3 | IR_Supplies | 245 |
| SupplyCrate1 | Crate | 4.01 x 2.21 x 2.65 | 1,104 | 3 | IR_CratesA | 53 |
| SupplyCrate2 | Crate | 4.34 x 2.21 x 2.62 | 2,044 | 6 | IR_CratesA | 63 |
| SupplyCrate3 | Crate | 4.03 x 2.23 x 2.73 | 2,140 | 5 | IR_CratesB | 59 |
| leather_vest | Armor | 2.29 x 2.37 x 1.40 | 2,124 | 3 | IR_CratesB | 55 |
| padded_armor | Armor | 2.38 x 2.49 x 1.53 | 1,984 | 3 | IR_CratesB | 55 |

**ItemsReal.glb - 13.06 MB, 23 assets, 37,220 tris, 64 MeshParts.**

Differences from v1 to know about:
- Real-world sizes for natural food: the apple is 10 cm (0.32 studs, v1 0.43) and the berries are a 2.3-3.3 cm
  sprig; the bandage is a 10.5 cm x 5.7 cm gauze roll (v1 0.36 x 0.46 x 0.39 overall). Grips and attachments did
  not move; ground-loot offsets come from the new `boundsMin`.
- The leather vest shell is thinner (outer surface and attachments unchanged, the cavity is slightly roomier).
- SupplyCrate3 carries the arena's Spire "Cleft" sigil burnt into its lid (our own iconography).
- Unverified in Roblox (not opened in Studio by this pass): the look under Realistic lighting, the glass alpha
  blend, and how the importer treats the packed metallicRoughness (the separate grayscale maps cover it).

## 10. GroundReal - realistic, textured ground flora and rocks (2026-11-11)

Replaces the stylized v1 `foliage.py` / `rocks.py` ground sets for the realistic forest arena. Same conventions as
above (1 unit = 1 stud, front = Blender +Y = Roblox -Z, base centre on the ground), but every part is **textured**:
one SurfaceAppearance per MeshPart, built from PNGs that are uploaded once and shared (15 images for the whole set,
all 1024 px or smaller since the 2026-11-11 art-direction pass - section 11).

```powershell
& $blender --background --factory-startup --python art/blender/ground_real.py -- $out art/previews   # ~10 min
#   3rd argument: stages (atlas,rocktex,assets,preview; default all)
#   4th argument: preview subset (asset names, or shots / lineup / forest / meadow / cliffs)
#   env GR_ATLAS_ONLY=slot,slot  re-render only those atlas slots (the rest comes from %TEMP%/GroundReal_build;
#                                a fresh machine needs one full atlas run first)
#   env GR_TREES_DIR             folder holding TreesReal.glb for the vignettes (default: BlenderExports)
```

| Module | Role |
|---|---|
| `ground_real.py` | driver (stages, paths, manifest notes) |
| `tex_ground.py` | PNG writer, colour maths, push-pull bleed, numpy noise, surface nets, mesh and Cycles helpers |
| `gr_elements.py`, `gr_atlas.py` | modelled plant elements (blades, fronds, leaves, flower heads, moss, litter, bark) rendered into the two card atlases |
| `gr_flora.py` | the 14 flora assets: bent alpha cards with real flipped back faces, tubes for stems and trunks |
| `gr_rocks.py` | granite shader, SDF rock shapes, low-poly pipeline, bakes, tiling cliff pieces, moss shells |
| `gr_export.py` | parts, validation, GLB export (tangents on), GLB check, texture inventory, manifest |
| `gr_preview.py`, `gr_vignettes.py` | review renders from the exported GLB + PNGs under Blender's Sky Texture |

**How the look is made**
- Flora: every plant element is modelled (veined blades and seed heads, pinnate fronds with serrated pinnae and
  auricles, leaf sprays, flower heads) and rendered orthographically into two 1024 atlases with alpha: colour bled
  into every transparent pixel, baked normals and roughness, and a one-pixel alpha rim on the Plants page so thin
  blades survive the lower mips. Cards bend along their length; grasses use up-bent normals, bushes and the
  sapling crown use normals from the crown centre (soft volumetric shading - Roblox has no leaf translucency).
- Rocks: shapes are signed-distance fields (rounded joint planes, strata with per-bed joint sets, tilted block
  faces, recessed soft beds, an inclined joint set, spalls, cracks, angular talus) meshed with surface nets; the
  surface-nets winding is kept through decimation (no normal recalculation) and the Newton projection onto the
  field is step-clamped (unclamped steps threw needles out of weak-gradient spots). Boulders, the slab and the
  river stones are decimated from a smoothed field and get unique 1024 bakes on three pages (53-70 px/stud) of the full-detail
  high-poly (OpenGL tangent-space normal, albedo with short-distance AO). Cliffs, the cave mouth, the outcrop and
  the scree tile one seamless granite set instead (1024 px over 13 studs = 79 px/stud; box-projected UVs run
  outside 0..1) with crisp per-corner normals, plus separate `<Asset>_Moss` cushion parts on cliff ledges. (The
  scree was baked first, but a 1.9k-triangle hull cannot follow 70 angular fragments: the bake recorded
  grazing-ray normals, so it shares the cliffs' surface now - which also matches the cliffs it lies under.)
- One procedural granite shader feeds both: warm-grey tone and weathering rind, mineral grain (white and buff
  feldspar, grey quartz, salt-and-pepper biotite, feldspar phenocrysts), spall scars, sparse hairline fractures,
  rain streaks, iron staining, five lichen species in clustered colonies (pale crust, grey-green foliose with
  apothecia, yellow-green map lichen with black prothallus lines, dark crust on tops, rare orange), moss on
  up-facing surfaces and a damp, soil-splashed base. Relief is modelled in studs (bump distance 1 = physical).
  Mean granite albedo is about sRGB 128-135 (playbook range 110-160); moss and foliage sit next to the TreesReal
  values (moss 60-69/74-79/29-32 vs the trees' 64/73/31).

**Import** follows the `import` notes in the manifest: upload each PNG listed in `textures` once, give each part
one SurfaceAppearance from its `surfaceAppearance` block (`color` white), AlphaMode as given; cards keep
`DoubleSided = false` and `Transparency = 0` (their back faces are in the mesh); roughness PNGs are 8-bit gray, no
metalness map. `glbCheck` in the manifest confirms POSITION / NORMAL / TANGENT / TEXCOORD_0 on every primitive.

**Review renders** (`art/previews/GroundReal/`): `<Asset>_close.jpg` (eye level, 4-8 studs) and `<Asset>_mid.jpg`
(~20 studs, or the whole piece for cliffs) next to the 5.5-stud figure, `_lineup.png`, and three vignettes:
`_vignette_forest.png` (sloped forest floor with ferns, grass, moss, mushrooms, boulders, outcrop and the TreesReal
fallen log, stump and trunks, dappled sun), `_vignette_meadow.png` (tall grass, wildflowers, bushes, boulders,
forest edge), `_vignette_cliffs.png` (cliff faces, cave mouth, scree and boulders at a cliff foot). The vignettes
import `TreesReal.glb` read-only so the ground set is judged next to the trees.

**Known limitations / to verify in Studio**
- Cliff and cave UVs tile outside 0..1: confirm that the SurfaceAppearance repeats on these MeshParts.
- Rock low-polys keep a few non-manifold edges where blocks touch (they render correctly; collision is Hull or
  PreciseConvexDecomposition).
- Card shadows: `castShadow` is off for small plants; bushes, the sapling and reeds cast shadows - check that they
  come out dappled, not as solid card shapes.
- Rock pages carry gentle baked AO (contact and crevices only); if Roblox's own occlusion makes bases too dark,
  lift the SurfaceAppearance `Color` slightly.
- The flat underside of each baked rock keeps its UV island (buried, never seen); a later pass could shrink it to
  free page space.

### GroundReal - three GLBs, 26 assets, 48,253 tris, 15 upload images

| GLB | Size | Assets | Embedded images |
|---|---|---|---|
| GroundReal_Flora.glb | 4.82 MB | FernA, FernB, BushA, BushB, BerryBush, GrassTallA, GrassTallB, GrassForest, ReedsA, FlowersA, FlowersB, MushroomsA, SaplingBroadleaf, MossPatch | GR_Plants_Color, GR_Plants_MR, GR_Plants_Normal, GR_Shrubs_Color, GR_Shrubs_MR, GR_Shrubs_Normal |
| GroundReal_Rocks.glb | 9.86 MB | BoulderA, BoulderB, BoulderC, BoulderD, RockFlat, RiverStones | GR_RockPage1_Color, GR_RockPage1_Normal, GR_RockPage2_Color, GR_RockPage2_Normal, GR_RockPage3_Color, GR_RockPage3_Normal, GR_Rock_MR |
| GroundReal_Cliffs.glb | 10.61 MB | ScreeA, CliffFaceA, CliffFaceB, CliffFaceC, RockOutcrop, CaveMouth | GR_Granite_Color, GR_Granite_Normal, GR_Rock_MR, GR_Shrubs_Color, GR_Shrubs_MR, GR_Shrubs_Normal |

| Asset | GLB | Size W x H x D (studs) | Tris | Parts: tris (collision) |
|---|---|---|---|---|
| FernA | Flora | 5.9 x 2.6 x 4.8 | 864 | Fern 864 (no collision, no shadow) |
| FernB | Flora | 4.6 x 2.1 x 4.2 | 728 | Fern 728 (no collision, no shadow) |
| BushA | Flora | 7.1 x 5.0 x 6.6 | 1236 | Leaves 1236 (no collision) |
| BushB | Flora | 7.3 x 3.2 x 6.8 | 996 | Leaves 996 (no collision) |
| BerryBush | Flora | 6.2 x 4.4 x 5.1 | 1836 | Leaves 916 (no collision), Berries 920 (no collision, no shadow) |
| GrassTallA | Flora | 3.5 x 3.7 x 3.2 | 384 | Grass 384 (no collision, no shadow) |
| GrassTallB | Flora | 4.0 x 3.3 x 3.4 | 360 | Grass 360 (no collision, no shadow) |
| GrassForest | Flora | 1.8 x 1.1 x 1.6 | 160 | Grass 160 (no collision, no shadow) |
| ReedsA | Flora | 3.3 x 6.2 x 3.4 | 534 | Reed 534 (no collision, no shadow) |
| FlowersA | Flora | 2.0 x 1.6 x 1.8 | 196 | Flower 196 (no collision, no shadow) |
| FlowersB | Flora | 1.8 x 1.5 x 1.7 | 192 | Flower 192 (no collision, no shadow) |
| MushroomsA | Flora | 1.7 x 0.6 x 1.5 | 830 | Mushroom 830 (no collision, no shadow) |
| SaplingBroadleaf | Flora | 6.4 x 9.2 x 6.5 | 1196 | Trunk 140 (Hull), Leaves 1056 (no collision) |
| MossPatch | Flora | 4.8 x 0.3 x 3.3 | 252 | Moss 252 (no collision, no shadow) |
| BoulderA | Rocks | 2.3 x 2.1 x 2.1 | 508 | Rock 508 (Hull) |
| BoulderB | Rocks | 4.1 x 3.6 x 3.8 | 930 | Rock 930 (Hull) |
| BoulderC | Rocks | 6.7 x 5.3 x 5.7 | 1420 | Rock 1420 (Hull) |
| BoulderD | Rocks | 11.0 x 7.1 x 8.4 | 1960 | Rock 1960 (Hull) |
| RockFlat | Rocks | 9.9 x 1.9 x 7.5 | 930 | Rock 930 (Hull) |
| ScreeA | Cliffs | 8.2 x 3.1 x 6.5 | 1896 | Rock 1896 (Hull) |
| RiverStones | Rocks | 7.2 x 1.2 x 5.6 | 2280 | Stone 294 (Hull), Stone_2 294 (Hull), Stone_3 294 (Hull), Stone_4 294 (Hull), Pebbles 1104 (no collision, no shadow) |
| CliffFaceA | Cliffs | 27.3 x 22.3 x 25.3 | 4496 | Rock 4062 (PreciseConvexDecomposition), Moss 434 (no collision, no shadow) |
| CliffFaceB | Cliffs | 38.3 x 31.9 x 32.8 | 6691 | Rock 6005 (PreciseConvexDecomposition), Moss 686 (no collision, no shadow) |
| CliffFaceC | Cliffs | 48.4 x 44.1 x 41.1 | 7218 | Rock 6628 (PreciseConvexDecomposition), Moss 590 (no collision, no shadow) |
| RockOutcrop | Cliffs | 14.1 x 6.4 x 16.9 | 2691 | Rock 2385 (Hull), Moss 306 (no collision, no shadow) |
| CaveMouth | Cliffs | 36.3 x 24.6 x 31.6 | 7469 | Rock 6821 (PreciseConvexDecomposition), Moss 648 (no collision, no shadow) |

| Image | Size | Channels | Used by |
|---|---|---|---|
| GR_Granite_Color.png | 1024x1024 | RGB | 6 assets |
| GR_Granite_Normal.png | 1024x1024 | RGB | 6 assets |
| GR_Plants_Color.png | 1024x1024 | RGBA | 8 assets |
| GR_Plants_Normal.png | 1024x1024 | RGB | 8 assets |
| GR_Plants_Rough.png | 1024x1024 | gray | 8 assets |
| GR_RockPage1_Color.png | 1024x1024 | RGB | 1 assets |
| GR_RockPage1_Normal.png | 1024x1024 | RGB | 1 assets |
| GR_RockPage2_Color.png | 1024x1024 | RGB | 3 assets |
| GR_RockPage2_Normal.png | 1024x1024 | RGB | 3 assets |
| GR_RockPage3_Color.png | 1024x1024 | RGB | 2 assets |
| GR_RockPage3_Normal.png | 1024x1024 | RGB | 2 assets |
| GR_Rock_Rough.png | 512x512 | gray | 12 assets |
| GR_Shrubs_Color.png | 1024x1024 | RGBA | 11 assets |
| GR_Shrubs_Normal.png | 1024x1024 | RGB | 11 assets |
| GR_Shrubs_Rough.png | 1024x1024 | gray | 11 assets |

GLB-only (embedded, never uploaded): GR_Plants_MR.png, GR_Rock_MR.png, GR_Shrubs_MR.png.

## 11. Realistic sets: art direction, shared conventions and import (2026-11-11)

This section covers all six realistic sets together: TreesReal (section 8), ItemsReal (section 9), GroundReal
(section 10), LandmarksReal, BuildingsReal and PropsReal. It records the conventions every set now follows, the
import flags, and what the art-direction pass changed before anything was uploaded. Nothing here has been uploaded or
opened in Studio yet.

### 11.1 What ships

| Set | GLB | Size | Assets | Tris | Upload images (folder) | Generator |
|---|---|---|---|---|---|---|
| TreesReal | `TreesReal.glb` | 18.37 MB | 14 | 67,765 | 14 (`textures/TreesReal`) | `trees_real.py` |
| GroundReal | `GroundReal_Flora.glb` | 4.82 MB | 14 | 9,764 | 15 (`textures/GroundReal`) | `ground_real.py` |
| GroundReal | `GroundReal_Rocks.glb` | 9.86 MB | 6 | 8,028 | 15 (`textures/GroundReal`) | `ground_real.py` |
| GroundReal | `GroundReal_Cliffs.glb` | 10.61 MB | 6 | 30,461 | 15 (`textures/GroundReal`) | `ground_real.py` |
| LandmarksReal | `LandmarksReal.glb` | 19.62 MB | 11 | 58,751 | 16 (`textures/LandmarksReal`) | `landmarks_real.py` |
| BuildingsReal | `BuildingsReal.glb` | 18.38 MB | 3 | 26,837 | 16 (`textures/BuildingsReal`) | `buildings_real.py` |
| PropsReal | `PropsReal.glb` | 13.02 MB | 10 | 10,328 | 13 (shares `textures/BuildingsReal`) | `buildings_real.py` |
| ItemsReal | `ItemsReal.glb` | 13.52 MB | 23 | 37,220 | 16 (`textures/ItemsReal`) | `items_real.py` |

**Total: 87 assets in 8 GLBs, 249,154 tris, 108.2 MB.** Every set passes `ad_finalize` with 0 problems. The unique upload images are 14 + 15 + 16 + 16 + 16 = 77 PNGs (PropsReal reuses 13 of BuildingsReal's 16).

`BlenderExports/RealSets.index.json` lists every set, its GLBs, its manifest, its texture folder and its upload
images. `ad_finalize.py` writes it, and the integrator can drive the whole import from it.

### 11.2 Regenerating

Run from the repo root. `$out` and `$prev` are set as in section 1. Each generator ends by calling
`ad_finalize.finalize()`, which normalises its manifest and prints an `ADCHECK` line. A clean run reports
`0 problems`.

```powershell
& $blender --background --factory-startup --python art/blender/trees_real.py     -- $out $prev [textures] [nopreview nosheets]   # ~5 min
& $blender --background --factory-startup --python art/blender/ground_real.py    -- $out $prev                 # ~10 min (3 GLBs)
& $blender --background --factory-startup --python art/blender/landmarks_real.py -- $out $prev tex=build review=all   # ~6 min
& $blender --background --factory-startup --python art/blender/buildings_real.py -- $out $prev [norender]     # ~3 min (Buildings + Props)
& $blender --background --factory-startup --python art/blender/items_real.py     -- $out $prev [norender]     # ~5 min + 7 min renders
python art/blender/ir_verify.py $out art/manifests                       # ItemsReal keeps the v1 Items contract
python art/blender/ad_finalize.py $out                                   # re-check every set, write RealSets.index.json
& $blender --background --factory-startup --python art/blender/ad_review.py -- $out $prev [scenes=...] [light=ct14,ct18]
```

`ad_review.py` scenes: `forest`, `meadow`, `marsh`, `spire`, `camp`, `gorge`, `fp` (first person), `lineup`,
`details` and `assets` (every asset at eye level next to the figure, one contact sheet per set). It renders in
Cycles under Blender's built-in Sky Texture with its sun: `ct14` is the high afternoon sun (Roblox ClockTime 14,
elevation 42 degrees) and `ct18` the warm low sun (ClockTime 18, elevation 5 degrees). The renders are built only
from what Roblox will receive: the exported GLBs, the manifests' `surfaceAppearance` blocks and the upload PNGs, with
cut-out alpha, single-sided parts and Neon embers. Output goes to `art/previews/_ArtDirection/`.

### 11.3 Conventions shared by every realistic set

- **Space.** These are the same as section 3: 1 unit = 1 stud, Roblox (x, y, z) = Blender (x, z, -y), and the front
  faces Blender +Y = Roblox LookVector (-Z).
  - World assets have their pivot at the base centre on the ground. Held items have it at the grip.
  - Rocks, cliffs, trunks and roots continue below y = 0 on purpose, so they seat into slopes. Plant cards sink at
    most 0.07.
- **Images.**
  - PNG, power of two, at most 1024 x 1024 (Roblox shrinks bigger uploads, so GroundReal's former 2048 maps would
    have lost half their detail without notice).
  - No single-flat-colour image, and at most 16 upload images per texture folder.
  - ColorMap is sRGB, RGB. It is RGBA only where alpha is used: the card atlases and glass.
  - NormalMap is OpenGL (+Y), tangent space, MikkTSpace.
  - RoughnessMap and MetalnessMap are 8-bit grayscale. A MetalnessMap exists only for sheets that contain metal.
- **`glb_only/`.** Each `textures/<Set>/glb_only/` folder holds the packed glTF metallicRoughness copies that are
  embedded in the GLBs. **Never upload them.** All six sets now keep them out of the upload folder.
- **GLBs.**
  - Every GLB embeds its textures (baseColor, normal, metallicRoughness).
  - Every primitive carries TANGENT, NORMAL and TEXCOORD_0. No material is doubleSided.
  - metallicFactor is 0 wherever nothing is metal.
  - Every GLB is at most 20 MB. LandmarksReal, at 19.6 MB, is the closest.
- **Manifest schema `LS-Real-1`.** `ad_finalize.py` adds these fields on top of each generator's own, so one importer
  serves all six sets.
  - Per part:
    - `surfaceAppearance {colorMap, normalMap, roughnessMap, metalnessMap|null, alphaMode, color}`. Paths are
      relative to BlenderExports. It is `null` for Neon embers and invisible colliders.
    - `transparency`, `doubleSided` (always false), `backFacesInMesh` and `neon`.
    - `collide`, `collision`, `canQuery`, `canTouch`, `castShadow`, `tags`, `robloxMaterial` and `rgb` (fallback
      colour).
  - Per asset: `glb`, `origin`, `boundsMin`/`boundsMax`, `tris` and `attachments` (Roblox space, relative to the
    pivot).
  - Top level: `glbs[]`, `textureFolder`, `uploadTextures[]` (file, kind, size, channels, users),
    `glbOnlyTextures[]`, and `adCheck` (problems, which must be empty).
- **Palette.** These are the measured values that make the sets sit together:
  - Granite: 110-160 sRGB. The rocks, cliffs, Spire and plaza are now 115-130.
  - Bark: 50-110. The trees, BR bark and the bench and woodpile logs are 83-92 / 62-68 / 46-52.
  - Grass green channel: 60-120.
  - Silvered wood: 110-145.
  - These follow `docs/research/LookDevPlaybook.md` section 11.

### 11.4 Import flags (integrator checklist)

1. **Upload images.** Upload every PNG in each manifest's `uploadTextures` once and keep a file → asset-id map.
   BuildingsReal and PropsReal share `textures/BuildingsReal`. Skip `glb_only/`.
2. **Import GLBs.** Import every GLB in each manifest's `glbs`. Then re-centre each asset:
   `WorldPivot = CFrame.new(origin)`, then `PivotTo`.
3. **SurfaceAppearance.** If a part's `surfaceAppearance` is not null, give the part one SurfaceAppearance:
   - ColorMap, NormalMap, RoughnessMap and MetalnessMap come from the id map. Leave MetalnessMap empty when it is null.
   - AlphaMode as given (`Overlay` or `Transparency`).
   - `Color = surfaceAppearance.color`. This is mandatory for TreesReal, whose species share images.
   - Clear any TextureID the importer created.
   - If the importer already built SurfaceAppearances from the embedded images, replace them with these. That keeps
     one shared image per file and the separate grayscale roughness maps.
4. **MeshPart flags.** For every part:

   | Property | Value |
   |---|---|
   | `DoubleSided` | `false` (cards carry real back faces) |
   | `Transparency` | the part's `transparency` |
   | `CastShadow` | `castShadow` |
   | `CanCollide` | `collide` |
   | `CollisionFidelity` | `collision` (edit time only) |
   | `CanQuery` | `canQuery` |
   | `CanTouch` | `canTouch` |
   | `Anchored` | `true` |
   | `Material` | `robloxMaterial` |
   | `Color` | `rgb` (fallback) |
   | `RenderFidelity` | Automatic |

   `transparency` is 0 for card cut-outs, 0.02 for item glass and water, 0.15 for cabin and lantern glass, and 1 for
   colliders. `neon = true` parts get `Material = Neon` with `Color = rgb` (255,128,48), no SurfaceAppearance, and a
   warm PointLight at the asset's light attachment.
5. **Tags and attachments.**
   - CollectionService tags: the asset tag `Plinth` and the part tag `Climbable` (`OakA_Bark`). Helper part tags are
     `Floor`, `Lid`, `LadderVisual` and `HideSpot`.
   - Create every manifest attachment (`Perch1-4`, `Plate_1..24`, `CrateSlot_1..4`, `Beacon`, `Stand`,
     `LadderBase`/`LadderTop`, `Door`, `Hearth`, `EndA`/`EndB`, `FireCenter`, `Glow`/`HangPoint`, `SignFace`,
     `Seat_n`, `CaveEntrance`, `Grip`/`Tip`/`Nock`/`StringTop`/`StringBottom`/`ArrowRest`, `LidHinge`/`Prompt`/
     `LootPoint`) as in section 4.
   - SpirePlatform `Plate_n` sits at r = 52, every 15 degrees clockwise from north (-Z). `ad_finalize` checks this.
6. **Studio checks.** These are unverified, because Studio was out of scope:
   - Normal-map handedness on one bark trunk.
   - Card shadows (dappled or solid).
   - Tiling outside 0..1 on cliffs, plaza and walls.
   - The glass blend.
   - The SpirePlatform and cave colliders leave the openings open.
   - Under Realistic lighting, granite and the steel plates are not too glossy.

### 11.5 Art-direction pass (2026-11-11): what changed and why

**Roblox import constraints (hard fixes)**
1. **GroundReal images were 2048 px.** Roblox caps images at 1024, so 6 of its maps would have been downscaled on
   upload, and the previews showed detail the game would never get.
   - The unique boulder bakes now use three 1024 pages instead of two 2048 pages: `PAGE_OF` in `gr_rocks.py`, new
     `GR_RockPage3_*`. They reach 53-70 px/stud.
   - The granite tile is 1024 px over 13 studs (79 px/stud).
   - The set now has 15 upload images.
2. **GroundReal shipped a GLB with no textures,** so the importer would have produced untextured MeshParts.
   - The GLBs now embed Color, Normal and a packed metallicRoughness (`glb_only/GR_*_MR.png`, B = 0,
     metallicFactor 0). The card atlases are alphaMode MASK.
   - The set is split into `GroundReal_Flora` / `_Rocks` / `_Cliffs` so each stays far under 20 MB: 4.8 / 9.9 /
     10.6 MB.
   - One manifest still covers the set, and each asset records its `glb`.
   - The old single `GroundReal.glb` was moved out of the export folder.
3. **Every LandmarksReal and ItemsReal material was `doubleSided` in the GLB,** although the manifests say
   DoubleSided false. Both sets' materials are now single-sided (`lr_core.material`, `tex_items.export_material`
   and `flat_material`).
4. **LandmarksReal and BuildingsReal kept their packed `_MR.png` copies in the upload folders.** That would have been
   5 extra uploads per set. They now go to `glb_only/`, as TreesReal already did. The stale copies were moved out.
5. **Manifest schema.** There is now one schema, `LS-Real-1`, plus `RealSets.index.json` and an automatic `ADCHECK`
   on every generator run (`ad_finalize.py`). Before this, each set described its surfaces differently: `surface`
   vs `surfaceAppearance`, bare file names vs `textures/<Set>/...`, missing alpha/colour fields.

**Look (judged in `ad_review.py` renders, both lights)**
6. **GroundReal tall grass.** It was a golden straw sward (68 % straw blades, green channel ~140) that read as a dry
   savanna beside the lush TreesReal forest. It is now a mid-summer meadow: mostly green and olive blades with
   sun-cured tips and golden seed heads, with values in the playbook grass band.
7. **Granite (boulders, cliffs, scree, outcrop, cave).**
   - The tone is darker and more varied: mean ~134 → ~123 sRGB, broader macro variation, fewer bright mineral
     specks.
   - The cliff tile's lichen is at 0.55, because the pale crusts read as white paint flecks on 40-stud faces.
8. **Boulders.** They read as pillows and eggs. They now have flatter joint facets with tighter rounding: k 0.1-0.18
   → 0.045-0.1 x size, deeper and more numerous cuts. BoulderB's crack is wider and wanders, where before it read as
   a drawn black line.
9. **Cliffs.** They read as stacked masonry courses. They now have uneven beds (thin partings between massive beds),
   broader undulation of the block faces (noise 0.2 → 0.5 at a lower frequency, plus a second octave), livelier
   block tilts (0.13 → 0.2) and face waves (1.3 → 2.0).
10. **LandmarksReal dressed granite (Spire, plaza, steps).** It read as clean poured concrete. It now has a darker
    weathered skin and stronger mottling and rain streaks: mean 137 → 129 sRGB.
11. **Plinth.**
    - The steel read as chrome. It is now duller, oxidised mild steel with grime and rust blooms (base roughness
      0.4 → 0.56), and the tread lugs are 0.28 → 0.42.
    - The ram UVs wrapped one 1-stud steel strip round an 11.6-stud circumference, which gave it a crumpled-plastic
      look. It is now built from 1-stud bands (`lr_plaza._ram`; Plinth 912 → 1,264 tris).
12. **BuildingsReal bark (log bench, woodpile, poles).** Pale grey "giraffe" plates sat next to the red-brown TreesReal
    conifer bark. It is now warmed and darkened to match: sRGB 83/62/46 vs the trees' 92/68/52, with a subtler pale
    lip.
13. **HunterCabin.** The loft railing poked up through the front roof slope as a visible triangle. Its posts and rails
    now stop 0.3 under the roof boards.
14. **ItemsReal crate planks.** They had evenly wavy cartoon grain. They now have straighter rings (distortion 0.3 →
    0.1), softer late-wood contrast (0.38 → 0.22) and fine fibre streaks.

### 11.6 Review renders

All of these are in `art/previews/_ArtDirection/` and are made by `ad_review.py`:
- `forest_*.png`, `meadow_*.png`, `marsh_*.png`, `spire_*.png`, `camp_*.png` and `gorge_*.png`, each in `ct14` and
  `ct18`.
- `fp_sword_ct14.png` and `fp_bow_ct14.png`.
- `_lineup_all.png`.
- `detail_*.png`.
- `_sheet_<Set>_<light>.png`: every asset at eye level next to the 5.5-stud figure.

The per-set artists' previews (`art/previews/<Set>/`) were re-rendered from the final exports for GroundReal,
LandmarksReal, BuildingsReal and ItemsReal.

### 11.7 Known limitations (punch list)

- **TreesReal foliage is card-based.** Spruce and fir sprays read as flat shelves or edge-on cards within 8-15 studs.
  PineA's crown reads as bonsai-like clumps and OakA's as broccoli clumps. From 25 studs the forest reads well (see
  `forest_*`). A real fix needs more, smaller cards and an atlas pass, and the conifers are at 8.5k of their 9k
  budget. This was not attempted in this pass.
- **Cliffs** still read as blocky jointed granite at arm's length (flat block faces), though no longer as masonry. A
  sculpted erosion pass or baked unique cliff pages would be the next step.
- **Texel density is capped by the 1024 limit and the 16-image budget:**
  - Unique rock bakes: 53 px/stud (BoulderD, alone on RockPage1) to 70 px/stud.
  - ItemsReal crates and armour: 53-63 px/stud.
  - The four thickest tree trunks: 126-141 px/stud.
  - All of these are soft when a player hugs them.
- **LandmarksReal.glb is 19.62 MB.** It is under the 20 MB limit but has only 0.38 MB of headroom (18.72 MiB).
  Any growth means splitting it, for example into an arena GLB and a lobby GLB, the way GroundReal is split.
- **Stray folder.** `C:/art/previews/` (outside the repo) still holds 5 stale images from earlier artist runs that hit
  the relative-path bug. Deleting files that other agents created was out of scope, so it is safe for the user to
  delete `C:/art` by hand.
- **Not verified in Roblox** (Studio and uploads were out of scope):
  - How the importer handles the embedded packed metallicRoughness. The separate grayscale maps cover this.
  - Whether UVs outside 0..1 repeat (bark, cliffs, plaza, walls).
  - Whether card shadows come out dappled.
  - The glass blend (Transparency 0.02 / 0.15).
  - Normal-map handedness on a lit trunk.
  - Collider openings (SpirePlatform plates, cave, gate).
  - Whether this importer adds the 180-degree Y turn measured for v1 Items (section 4).
- **Review renders use a procedural terrain stand-in,** not Roblox terrain, and Cycles, not Roblox Future lighting.
  Re-check values under the LookDev playbook's lighting once the assets are in Studio.

### 11.8 Studio integration (2026-11-12)

**One-asset test.** `GroundReal_Flora.glb` was uploaded once as `LS_GroundReal_Flora_v1` = **95045390089356**
(Approved) and inserted into `ServerStorage.MeshImports`. What the Open Cloud importer makes from these GLBs:
- **Hierarchy.** One Model per asset, then one `<Part>_Node` Model per mesh, then one MeshPart per manifest part.
  All 16 of 16 arrived with exact names.
- **Scale.** Sizes match the GLB extents to 1e-4 studs (1 unit = 1 stud).
- **The 180-degree turn about Y measured for v1 Items is present.** Positions mirror through the GLB origin in both
  X and Z (dX 49.358 -> -49.358, dZ -0.353 -> +0.353) while every part rotation reads 0, so the turn is baked into
  the mesh data. insert_asset added no extra yaw this time; the builder measures and undoes both anyway.
- **Part state.** Parts arrive unanchored, Plastic, default grey (163, 162, 165), with an empty TextureID.
- **SurfaceAppearance.** Each MeshPart gets one, built from the embedded textures. The importer **uploads those
  images implicitly** as Image assets on the creator's account (displayName `image`, Approved). Per material it
  makes Color, Normal, Roughness (from the packed MR's G channel) and Metalness (from the B channel; one flat-black
  image shared by both materials).
- **AlphaMode.** It stays **Overlay** although the glTF material is MASK, so cards render as grey boxes until
  AlphaMode = Transparency (checked in a capture).
- **Pixel readback** (EditableImage) of the importer's images against the PNGs:
  - Color: 1024 x 1024, the same 5 sample pixels including the colour bled into transparent texels; alpha < 128 on
    63.2 % vs 63.3 %.
  - Normal: 1024 x 1024, the same sample pixels (G not flipped).
  - Roughness: 512 x 512, where the PNG is 1024 x 1024.
  - Metalness: 512 x 512, flat 0.
- **Cut-out cards** (AlphaMode Transparency, Transparency 0, DoubleSided off) render clean. Small plant cards cast
  soft blob shadows; tree crowns cast cut-out (dappled) shadows (see 11.9).

**Decision: image path (made before the other uploads).**
- **ColorMap and NormalMap** reuse the importer's images (52 files), after a pixel-readback check of each one.
  Evidence: every embedded Color and Normal image in the 8 GLBs is byte-identical (sha256) to its upload PNG.
- **RoughnessMap and MetalnessMap** come from the 25 grayscale PNGs (19 roughness + 6 metalness), uploaded once each.
  The importer can only derive these maps from the packed MR/ORM, which falls short in three ways:
  - Half resolution for GR_Plants/GR_Shrubs (512 vs 1024) and for every LandmarksReal sheet (256 vs 512).
  - Non-zero metalness (B mean 1/255) on BuildingsReal sheets the manifest calls non-metal.
  - An extra flat-black metalness image on non-metal sets, where the manifests want MetalnessMap empty.
- **Shared files.** A file embedded in two GLBs (GR_Shrubs_*, BR_Wood/Kit/Stone/Log_*) keeps the id from its first
  import (GroundReal_Flora, BuildingsReal).
- **Fallback.** If an importer image fails the check, that PNG is uploaded instead, once.
- **Total.** 8 GLBs + 25 PNGs. Every id is recorded in `art/manifests/RealSets.assetIds.json`.

**Result of the uploads.**
- All 8 GLBs and the 25 grayscale PNGs are Approved.
- All 52 importer Color/Normal images passed the readback check: same size, the grid mean of every channel equal,
  and 9 sample pixels identical. The 25 uploads pass the same check and stay pure gray.
- The importer **de-duplicates identical images across uploads**: Cliffs reused Flora's GR_Shrubs ids, and Props
  reused BuildingsReal's BR_* ids. No shared file was uploaded twice.
- The importer's own images that no template uses (29, listed under `importerUnused` in the ledger) exist on the
  account: 19 roughness and 9 metalness maps derived from the packed MR/ORM, plus one ColorMap, **130802519081423**,
  that PropsReal's `BR_Kit_Ember` material produced. That material has BR_Kit_Color as both base colour and emissive
  texture, and the importer baked the two together: 1024 x 1024, a 32 x 32 grid mean RGB of 191/169/137 against
  BR_Kit_Color's 128/114/93, with the same alpha. It is the ColorMap of `Lantern_Ember` and `Campfire_Ember` in
  the raw `LS_PropsReal_v1` insert only. Templates make embers Neon with no SurfaceAppearance. The ledger now holds
  114 unique ids: 8 models, 77 image files and 29 unused importer images.

**Duplicate-upload audit (2026-11-12, fix round).** Open Cloud cannot list a creator's Image assets: `IMAGE` is not an
inventory asset type, and an `assetIds` filter with image ids returns 500. So the check combines five sources. Each
result is in the ledger under `duplicateUploadAudit`.
- **Model inventory** (`inventoryItemAssetTypes=MODEL`): exactly the 8 realistic models once each, plus the two v1
  models (LS_Items_v1, LS_Arms_v1). So each GLB was imported once.
- **Image inventory** (Studio MCP `search_asset`, scope `user`, type `Image`; at most 20 results per query, no
  paging):
  - With no query it lists newest first. The top 20 are the last 20 PNG uploads in reverse upload order, so
    nothing newer exists on the account.
  - The name searches `Rough`, `Roughness` and `Metal` return each of the 25 PNG names exactly once, with the
    ledger id.
  - `image` (the importer's display name) returns the 20 highest-id importer images, all in the ledger.
  - Type `Decal` returns none.
- **Transcript audit** of all 102 agent transcripts of this project: 35 Open Cloud creates, which are the 2 v1
  models plus the 33 realistic uploads, one per file. Each returned 200 with the ledger's operation id. There were no
  re-uploads, no new versions, and no `upload_image` or Luau `CreateAssetAsync` calls.
- **Place sweep:** the 8 raw inserts reference 81 distinct image ids, all in the ledger. Across the whole place
  (Workspace, ServerStorage, ReplicatedStorage and the Starter* services), 1,127 SurfaceAppearances reference 106
  distinct ids. All 106 are in the ledger, every one of the 77 image files appears, and no file appears under two
  ids.
- **Limit:** the lower-id importer images (61 of 81) cannot be listed account-wide. A stray copy there is ruled out
  only indirectly, by the one import per GLB and by the importer reusing ids for identical content (Cliffs reused
  Flora's GR_Shrubs ids; Props reused BuildingsReal's).
- **Other images on the account** that are not ours: the "Generated ColorMap/NormalMap/RoughnessMap/MetalnessMap"
  images. They most likely come from another agent's 10 `generate_material` calls for terrain materials
  (LS_MeadowGrass and others) on 2026-11-11.

### 11.9 Templates: `ServerStorage.MeshAssets` (2026-11-12)

**What is in Studio**
- **Raw inserts** (packages; never edit them): `ServerStorage.MeshImports.LS_<Glb>_v1` for all 8 GLBs.
- **Templates:** `ServerStorage.MeshAssets.<Set>.<Asset>` for TreesReal (14), GroundReal (26), LandmarksReal (11),
  BuildingsReal (3) and PropsReal (10). That is 64 templates and 259 manifest parts. ItemsReal is left to
  ItemAssets.
- **Builder:** `ServerStorage.WorldGen.RealAssets`, with its generated child `Manifest`. The repo copies are
  byte-identical to Studio: `art/manifests/RealAssets.luau` (builder) and `art/manifests/RealAssets.Manifest.luau`
  (data, written by `art/blender/rbx_real_manifest.py`).
- **Look-check lineup:** `ServerStorage.MeshAssets_Preview.RealAssets_Lineup`, kept as a copy. Next to it,
  `HunterCabin_Closeup_CT14` holds the cabin close-up set with its camera points (see the look check below).
- **Previous builds:** `ServerStorage.Archive_v1.MeshAssets_prev.<Set>`. These are generated output and safe to
  delete.

**Rebuilding**
```powershell
python art/blender/rbx_real_manifest.py   # after a re-export or a new upload; paste the .luau into RealAssets.Manifest
```
```lua
print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).build())   -- all five sets (~25 s)
print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).verify())  -- read-back check against the manifest
print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).lineup())  -- temporary look-check lineup at (4200,200,0)
print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).clearLineup())
```
The last `verify()` reported "verified 64 templates, 259 parts, 229 SurfaceAppearances, 57 attachments, 6 lights,
19 tags" with no problems. It covers:
- the pivot;
- the AssetId attribute;
- every part flag, including CollisionFidelity, RenderFidelity and DoubleSided;
- the maps, AlphaMode and tint of each SurfaceAppearance;
- the attachment frames;
- the tags and lights;
- the bounds.

**Template contract** (the full list is in the module header)
- **Pivot.** `WorldPivot` = the manifest origin: the base centre on the ground, with front = LookVector (-Z).
- **PrimaryPart** = the first visual part. It carries every manifest attachment.
- **Attributes:** `AssetId` (the GLB's Model asset), `Source`, `Set`, `Kind`, `Tags`, `Size`, `BoundsMin`,
  `BoundsMax`, `Tris`. Parts carry `Role`, plus `Tags` for descriptive part tags.
- **CollectionService tags:** `Plinth` (model) and `Climbable`, `Floor`, `LadderVisual`, `HideSpot` (parts).
  RoundService only reads Workspace plinths, so the tagged template in ServerStorage is not picked up.
- **Embers** are Neon with no SurfaceAppearance. A warm `EmberLight` PointLight (shadows on) sits on Spire `Beacon`,
  Brazier `Fire`, Pavilion/LobbyGate `Lantern`, Campfire `FireCenter` and Lantern `Glow`. The Plinth has no light,
  on purpose: 24 shadowed lights would be too many.
- **Ladders.** HunterCabin and Watchtower carry an invisible native-climb `LadderTruss` (2x10x2 and 2x22x2).

**Placing them** (set dressing, after terrain v2)
- Clone, then `PivotTo` a ground CFrame. Raycast the terrain for y and put the pivot on the surface. Trunks, roots and
  rock bases already continue 0.2-3.3 studs below y = 0. Rotate freely about Y.
- **Spire and SpirePlatform** share the same origin, unrotated, at the arena centre. Put one Plinth on each plate:
  `plinth:PivotTo(platform.PrimaryPart["Plate_" .. n].WorldCFrame)`. This keeps the ember strip facing the Spire; it
  was checked with all 24 in the lineup. Carve terrain under the 24 tubes (radius 3.5, plaza y 0.6 down to -11.6).
- **Spire `CrateSlot_1..4`** are LootSpawn spots (Kind Crate). Footbridge `EndA`/`EndB` sit at deck level 1.5.
- **Ambient sound.** Add `AmbientEmitter` (attribute `SoundKey`) at fire attachments when placing; templates don't
  carry it.
- **Instancing.** Keep the SurfaceAppearances as built (shared ids) so copies batch. Tint only through
  `SurfaceAppearance.Color`.

**Problems found and fixed while building**
1. **CollisionFidelity ignores direct writes.** It stays Default with no error; v1 ItemAssets' `pcall` hid this. The
   builder now makes the physics with `AssetService:CreateMeshPartAsync({CollisionFidelity = ...})` and copies it
   with `ApplyMesh`, 8 at a time (about 1.4 s per mesh).
2. **`Model.WorldPivot` on an unparented model with a PrimaryPart did not reach `PivotOffset`.** The builder sets
   `PrimaryPart.PivotOffset` directly.
3. **Manifest `boundsMin`/`boundsMax` are visual only.** Four LandmarksReal colliders reach past them: Spire top 58.2
   vs 58.162, SpirePlatform +-60.52 vs +-59.99, Brazier y 0 / z +-2.2, BannerPole z +-0.82. Pivots are measured on
   non-collider parts; before this fix Brazier sat 0.027 studs high.
4. **Every import is turned 180 degrees about Y** (all 8). The builder reads the turn off the row of assets and undoes
   it. HunterCabin's door faces -Z and its chimney +X, matching `Hearth` (+10.8, 1.15, 0).

**Studio look check** (Realistic, PrioritizeLightingQuality on). Captures at ClockTime 14, at 17.65 (sun 4.9 degrees,
the art director's "ct18"), at 18 and 18.3 (dusk), plus close-ups: SpruceA, PineA, BoulderD, CliffFaceA/B/C,
HunterCabin and the Spire base with all 24 plinths. The captures are in `art/previews/_StudioLookCheck/`.

**HunterCabin at ClockTime 14, Edit mode (fix round, 2026-11-12T06:41-06:43Z): captures 18 to 21.**
- **Conditions.** `get_studio_state` read Edit with only the Edit DataModel available. ClockTime was read back as
  14.00 before the captures, then restored to the 14.50 its owner had set. The copy was checked against the
  template: 29 of 29 parts, 28 SurfaceAppearances, and 0 differences in geometry, flags, maps, AlphaMode or tint.
- **18 and 19 match the art director's light.** The copy is turned -188.2 degrees about Y so that the CT14 sun
  (elevation 54.2 degrees) comes from the front-left, as in `_ArtDirection/detail_cabin_ct14.png`. With that light:
  - The chimney stones read beige-grey with dark mortar and a moss foot.
  - The logs read weathered grey-beige, with end grain and rings on the corner notches.
  - The shingles read grey with moss patches, and the porch planks show their nail holes.
  - As in the render, the chimney (+X) is on the left and the porch and door (-Z) face the camera. A 5.5-stud R15
    figure stands in front of the porch.
  - There are no black, shiny, flipped or untextured faces.
- **20 and 21 keep the lineup yaw,** which puts the chimney gable in shade. Lit only by the sky, those faces turn
  blue-grey. That is the blue sky-fill lighting note below, not a texture fault.
- **Overall look.** The cabin reads cooler and less saturated than the Cycles render. The Edit viewport also
  rendered softly at the time: about 16 fps, with another agent working.
- **Re-shooting.** The capture set is kept in `ServerStorage.MeshAssets_Preview.HunterCabin_Closeup_CT14`. Its
  attributes hold the camera and look-at points: `CamD`/`LookD` gives 18, `CamE`/`LookE` gives 19, and
  `CamB_lineupYaw`/`LookB_lineupYaw` gives 20. The cabin is stored at `AdPivot`, the turned pivot used for 18 and 19.
  1. Parent the set to Workspace. For 20, first `PivotTo` the cabin to the `LineupPivot` attribute.
  2. Set ClockTime to 14.
  3. Call `screen_capture` with those points.
  4. Restore ClockTime and move the set back.

No import fault was left:
- **No mesh, texture or alpha faults.** There are no flipped or black faces and no missing textures. Scale matches
  the 5.5-stud R15 figure. Cut-outs are clean on every card, and Overlay grey boxes appear only with the importer's
  own SurfaceAppearances.
- **Normal maps shade.** In an A/B of BoulderD with and without its NormalMap, the mapped copy shows facet relief and
  the other shades flat. This answers the tangent check.
- **UVs outside 0..1 repeat** on the cliffs, plaza and walls (granite tile over the 38-stud CliffFaceB).
- **Card shadows.** Tree crowns cast cut-out shadows: dappled under the birches, near-solid under the dense oak and
  spruce. Small plant cards cast soft blobs. The manifest's CastShadow settings are kept.
- **Glossy surfaces.** Nothing reads glossy or black at ClockTime 14. Back-lit pine clumps get a white sky sheen on
  their upper edges, while the same crown front-lit is dark green.
- **Lighting, for the day/night owner.** Shadows and up-facing cliff ledges take a strong blue sky fill
  (EnvironmentDiffuseScale 1), against the warm neutral shadows of the Cycles reviews. Edit-mode ClockTime 17.65-18
  is a dim blue dusk, not a golden hour.
- **Embers at dusk.** The Spire basket and plinth strips glow. The Campfire EmberLight lights the ground with
  shadowed rays.

**Open items**
- **TexturePack errors.** Studio logs "Failed to upload TexturePack (Referenced Asset 24 is NOT found)" about once
  per playtest.
  - It began at 01:43Z, when the BuildingsReal/PropsReal/ItemsReal packages were inserted.
  - It did not grow when the 229 template SurfaceAppearances were added.
  - It is not caused by the restored test parts.
  - The importer glass SurfaceAppearances reference valid ids, so the source is not identified.
  - Whether the templates' SurfaceAppearances render in a live client was not checked: back-to-back playtests by
    another agent left no window for one.
- **Template SurfaceAppearances are built by script.** Studio bakes their texture packs on first use or publish.
  Check one placed copy in a playtest before mass placement.

### 11.10 ItemsReal in the game: item templates and the first-person viewmodel (2026-11-12)

**What is in Studio**
- **Templates** (what the game clones; game code unchanged): `ReplicatedStorage.Assets.Items.<itemId>` (20) and
  `Assets.Crates.SupplyCrate1..3`, built from the one `LS_ItemsReal_v1` upload (**97973095265937**). Every template
  carries `Source = LS_ItemsReal_v1` and `AssetId`. `ItemModels.build` / `buildCrate` clone them for the hand, the
  ground, other players and crates. `Assets.Viewmodel` (the unused v1 Blender arms) is untouched.
- **Builder:** `ServerStorage.WorldGen.ItemAssets` with its generated child `Manifest`. Repo copies, byte-identical to
  Studio: `art/manifests/ItemAssets.luau` and `art/manifests/ItemAssets.Manifest.luau` (written by
  `art/blender/rbx_items_manifest.py` from `BlenderExports/ItemsReal.manifest.json` and the upload ledger).
- **Images:** nothing new was uploaded. ColorMap / NormalMap are the importer's own images and RoughnessMap /
  MetalnessMap the separate grayscale PNGs (16 images, 4 surfaces; ids in `RealSets.assetIds.json`).
- **Archive** (`ServerStorage.Archive_v1`): `ItemTemplates_v1.Items` (20) and `.Crates` (3) are the v1 templates;
  `ItemAssets_v1` is the v1 builder (it also rebuilds `Assets.Viewmodel`); `ViewmodelController_preItemsReal` (with
  its Rig and Poses) and `ItemModels_preItemsReal` are the scripts before this pass (ItemModels itself did not
  change). `ViewmodelController_preFixRound` (with its Rig and Poses) is the viewmodel before the fix round below.
  A rebuild moves the previous ItemsReal build to `ItemAssets_prev` (generated output, safe to delete;
  there is none yet).

**Rebuilding**
```powershell
python art/blender/rbx_items_manifest.py   # after a re-export or a new upload; paste the .luau into ItemAssets.Manifest
```
```lua
print(require(game.ServerStorage.WorldGen.ItemAssets:Clone()).build())   -- ~15 s; archives what it replaces
print(require(game.ServerStorage.WorldGen.ItemAssets:Clone()).verify())  -- read-back check against the manifest
```
The last `verify()` reported "verified 23 templates, 64 parts, 63 SurfaceAppearances, 46 attachments: 0 problems"
(the 64th part is the Neon `SupplyCrate3_Ember`, which has no SurfaceAppearance on purpose). It checks Source /
AssetId, the part list, SurfaceAppearance maps / AlphaMode / tint, Transparency, Material, DoubleSided, CastShadow,
CollisionFidelity, welds and flags, the bounds (+-0.06 studs), every attachment (+-0.001), crate Base / Lid / Hinge /
Tier, and the bow's Nock / String.

**Template contract** (the full list is in the module header)
- Same names, origins and attachments as v1 (`Grip`, `Tip`, `Nock`, `StringTop`, `StringBottom`, `ArrowRest`,
  `Mouth`, `Torso`, `LidHinge`, `PromptAttachment`, `LootPoint`). `Handle` is an invisible 0.05-stud part at the
  grip in the ItemModels frame: LookVector = business end; vests and the med kit hang along LookVector.
- One SurfaceAppearance per MeshPart. Glass and water: AlphaMode Transparency with `Transparency = 0.02`.
  CollisionFidelity Box, made with `CreateMeshPartAsync` + `ApplyMesh` (direct writes are ignored).
- The bow's `Nock` has `RestPosition` and `MaxDraw` (1.12 studs); `bow_Rope` has the `String` attribute, so the view
  copy swaps it for two Beams. Crates: invisible WoodPlanks `Base` collider, `Lid` with its fittings, `Hinge`
  attribute, tier 3 `EmberGlow` light at `LootPoint`.

**Viewmodel changes** (`StarterPlayer.StarterPlayerScripts.Client.Controllers.ViewmodelController`; the hands' parts,
sizes, colours and IK are unchanged)
- `Poses`: the item-use block is new. `Poses.DRINK` (lips, yaw, tilt0/tilt1, roll, low), `Poses.EAT` (hand, chew),
  `Poses.ARMOR` (lift, over, downRight/Left, tugRight/Left, pull, liftedAt/overAt/downAt/tug0At/tug1At),
  `Poses.useHidesItem(style, t, duration)`, `Poses.use(style, t, restRight, restLeft, duration?)` and
  `Poses.applyUse(style, t, u, right, left, rig, duration)`. Removed: `BOTTLE_REACH`, `BOTTLE_LIFT`, `DRINK_LIPS`,
  `ARMOR_SWING`, `ARMOR_OUT/OVER/DOWN`, `armorHidesItem`, `armorTug`. `HOLD.Armor.right` now carries the vest by its
  collar, in view at the lower right.
- `ViewmodelController`: the use block calls `Poses.applyUse` and `Poses.useHidesItem`.
- `Rig.ITEM_HOLD`: per-item offsets in the fist (apple, bandage, berries, ration, water_bottle, empty_bottle) so
  food and bottles sit in the closed hand on the palm side. The bandage and berries entries were redone in the fix
  round below.
- The bow poses did not change.

**How the uses look now**
- **Drink:** the bottle comes up from the lower right; its neck goes down past the bottom edge to the lips and its
  body runs up to the right, tipping further as it empties. The fist holds it from behind and below at the edge, so
  what shows is mostly the (translucent) bottle.
- **Eat:** the food is brought to the mouth just above the bottom edge in the middle, held in the fist; a sprig, a
  strip or a bone end points at the mouth; a small chewing bob. The berry sprig is held by its stalk with the red
  cluster out of the top of the fist; the cluster goes to the mouth, a little higher than other food so it shows
  above the hotbar (fix round).
- **Armour:** the vest hangs from the right fist by its collar (in view, lower right). Using it lifts it up the right
  side and swings it back over the right shoulder; it leaves past the top right corner and is hidden from then on.
  Both fists then come up at the bottom edge, clear of the hotbar, and tug the hem down twice.
- **Bandage** (style `Wrap`, fix round): the roll is wound round the left forearm at the lower left, then pulled
  tight. Details below.
- **Med kit:** the unchanged two-handed `Bandage` style at the bottom centre.

**Bow clear-zone re-check after the swap** (one full shot cycle per line: idle, draw 0.9 s, hold, release, next
nock; 74 frames; viewport 1570 x 753; rays against precise mirrors; TrainingDummy centred on the crosshair)

| View | 6 % circle | 12 % circle (max) | Nearest viewmodel pixel | String | Dummy hidden 15 / 30 / 60 studs |
|---|---|---|---|---|---|
| FOV 72, hip | 0 px (v1 0) | 0.000 % (v1 0.000 %) | 19.7 %H (v1 19.7) | 40.6 %H | 0.98 / 0 / 0 % (v1 same) |
| FOV 100, hip | 0 px (v1 0) | 0.016 % at release (v1 0.016 %) | 12.0 %H (v1 12.0) | 24.7 %H | 1.00 / 0 / 0 % (v1 same) |
| FOV 72, aimed (54.7) | 0 px (v1 0) | 0.000 % | 27.6 %H (v1 27.6) | 57.1 %H | 0.93 / 0 / 0 % (v1 same) |
| FOV 100, aimed (76) | 0 px (v1 0) | 0.000 % | 18.3 %H (v1 18.1) | 37.8 %H | 0.95 / 0 / 0 % (v1 1.72 / 0 / 0) |

No pose re-solve was needed. Real-input shots in a playtest (left mouse, aim with right mouse) were accepted by the
server and landed on the crosshair point: 30 studs aimed 0.031 / 0.019 studs off, hip 0.39; 60 studs aimed 0.051 /
0.023; every hit on UpperTorso for 50 damage, and the arrow count went down.

**Use poses, clear zone** (the hold, the whole use and 0.3 s after it at 60 fps, every 3rd frame; same rays and
viewport; "nearest" is the nearest viewmodel pixel to the crosshair in % of the viewport height). No use puts a
single pixel in the 6 % circle at FOV 72 or 100.

| Item (style, use time) | 12 % circle max, FOV 72 / 100 | Nearest, FOV 72 / 100 |
|---|---|---|
| water_bottle (Drink, 1.6 s) | 0 / 0 % | 23.9 / 14.6 %H |
| apple (Eat, 1.2 s) | 0 / 0 % | 27.6 / 16.7 %H |
| berries (Eat, 1.0 s; fix round) | 0 / 0 % | 20.7 / 12.7 %H |
| herbs (Eat, 1.5 s) | 0 / 0 % | 27.9 / 17.0 %H |
| dried_meat (Eat, 2.0 s) | 0 / 0.44 % (while it comes up) | 18.6 / 11.4 %H |
| ration (Eat, 2.5 s) | 0 / 1.40 % (while it comes up) | 17.5 / 10.9 %H |
| bandage (Wrap, 2.5 s; fix round) | 0 / 0 % | 19.9 / 12.2 %H |
| medkit (Bandage, 5.0 s) | 0 / 3.11 % (the kit circling) | 15.4 / 9.6 %H |
| leather_vest (Armor, 1.5 s) | 0 / 0 % | 21.2 / 13.0 %H (the hold itself) |
| padded_armor (Armor, 2.5 s) | 0 / 0 % | 22.0 / 13.5 %H |

The armour rows include one more fix: the vest stays hidden after the use while the hands come back
(`hideForUse = (using or alpha.use > 0.05) and Poses.useHidesItem(...)`). Before it, the worn vest popped back
into the right fist at the tug pose for a moment, pointing up into the 12 % circle (3.62 % at FOV 100).

**Live check** (playtests with real keyboard and mouse input, captures at ClockTime 14)
- Looked at in captures, held and in use: bow (draw, full draw aimed at FOV 100, release), water bottle, apple,
  berries, dried meat, ration, bandage, med kit, leather vest and padded armour. They render textured in the hand
  and in the hotbar icons, and nothing covers the crosshair.
- Ground and crates (LootService's own spawns in a playtest): all 88 ground items and all 40 crates come from
  `LS_ItemsReal_v1`, and all 245 ground-item MeshParts have their SurfaceAppearance.
  - Ground items rest on the ground: gap median -0.01 studs, at most +0.05. Two arrows read about 0.4 studs below
    the ground under their centre, probably lying across uneven ground (not checked).
  - Crate bases sit 0.02-0.10 studs into the ground, as LootService intends. One crate read -4.1 because something
    just above it (a roof or ledge) caught the downward ray; it was not checked further.
- Opening a crate with real input (hold E): `Opened` = true, the lid turned 110 degrees, and three items spilled
  (leather vest, arrow, mace). All three are `LS_ItemsReal_v1` and came to rest 0.02 studs above the ground.
- Held weapons (knife, machete, hatchet, spear, mace, sword, throwing knife), the empty bottle and herbs are built
  from the new templates with every SurfaceAppearance. At rest nothing is in the 12 % circle at FOV 72 or 100; the
  nearest pixel is 25.5-35.6 %H away at FOV 72 and 15.7-21.8 %H at FOV 100.
- **Not looked at in a capture:** the weapons in the hand, the ground items and the crates. Studio's window was
  minimised during the last two playtests, so the 3D view captured black; the checks above are numeric.

**Open items**
- Studio still logs "Failed to upload TexturePack (Referenced Asset 24 is NOT found)" about three times per
  playtest (seen before this pass; see 11.8).
- The berries eat pose showed leaves instead of berries; fixed in the fix round below.

#### Fix round (2026-11-12): bandage, berries, and the ContentId failures

An independent verifier failed three checks: the bandage did not read, the berries did not show, and two ContentId
failures in a playtest were not explained. Script edits were small and targeted; the archived copy is
`Archive_v1.ViewmodelController_preFixRound`. The hands' parts, sizes, colours and IK did not change.

**What changed**
- `Rig.ITEM_HOLD.bandage = CFrame.fromMatrix(V(-0.25, 0, 0), V(0, 0, -1), V(1, 0, 0))`: the roll lies along the palm
  side of the fist, its axis along the thumb and its loose end toward the knuckles. It was `CFrame.new(-0.2, 0,
  0.05)`, which left only the end of the roll poking out of the palm.
- `Rig.ITEM_HOLD.berries = CFrame.new(-0.1, 0, -0.22) * CFrame.Angles(math.pi, 0, 0)`: the sprig is held by its
  stalk, upside down, so the berry cluster stands out of the top of the fist and the leaves hang below it. Before,
  the fist closed on the cluster and only the stalk and leaves showed.
- `Poses.HOLD_ITEM` (new): per-item idle holds over the kind's hold. `bandage.right = H(V(0.8, -0.62, -1.42),
  V(-0.15, 0.95, -0.25), V(-0.35, -0.25, -0.9))` and `berries.right = H(V(0.74, -0.86, -1.34), V(-0.12, 0.92,
  -0.38), V(-0.2, -0.42, -0.88))` hold them up above the hotbar at the lower right. `Poses.hold(kind, aim, itemId?)`
  takes the item id; the bow returns before the override.
- `Poses.WRAP` (new) with the local `wrapHands`: the bandage's use style is now `Wrap`. The left forearm comes up
  across the lower left, its elbow out to the left (`Poses.usePole("Wrap")` = `WRAP.pole`, blended in by the
  controller), and the fist is bent down at the wrist. The right hand winds the roll twice round the forearm, 0.3
  studs behind the wrist, with the roll's centre 0.28 from the forearm's axis (the axis comes from `Rig.solveArm`,
  so it is the forearm as drawn). The roll moves slowest on the near side and hurries round the far side
  (`slowAt` 45 degrees, `ease` 0.6), then a short pull (`tug`) tightens it. Parameters: `wrist`, `pole`, `bend`,
  `palm`, `at`, `radius`, `fist`, `turns`, `slowAt`, `ease`, `start` 0.12, `stop` 0.84, `tug`.
- `Poses.EAT.lift = { berries = V(-0.06, 0.09, 0) }`: `Poses.applyUse("Eat")` raises the hand by this for the
  berries.
- `ViewmodelController`: `USE_STYLE.bandage = "Wrap"` (the med kit keeps `"Bandage"`), `Poses.hold(..., heldId)`,
  and `leftPole` in the use block (the left elbow's pole, `Rig.POLE.Left` blended toward `Poses.usePole`).
- Regression check: 1,360 hand frames of the other 18 items (holds at aim 0 / 0.37 / 1, every use at 31 times and
  two blend values) and the bow, swing, throw and tuck functions are identical to the archived modules (largest
  difference < 1e-6). So the bow numbers above still stand; the bow poses were not re-solved.

**Re-check, same methods as the verifier** (viewport 1568 x 753; hotbar band y 672-736, x 592-976)

| Check | Before | After |
|---|---|---|
| Bandage idle, FOV 72 | a sliver behind hotbar slot 6, item top y 727, 0 px above the band | roll beside the fist, item top y 556, 13,455 px visible outside the hotbar |
| Bandage use, per-frame top of any bandage part (box corners), in game | y 696, never above the band | 448-606 at FOV 72, 420-517 at FOV 100; above the band in 45 of 45 frames at each FOV |
| Bandage use, Edit trace at 60 fps (151 frames) | - | box top at most y 609; >= 3,000 px of the roll visible outside the hotbar in 139 of 151 frames; hidden behind the forearm in 6 |
| Berries idle / eat, FOV 72 | stalk and leaves only | the red cluster above the fist (top y 567); at the mouth, 4,518-11,457 px visible, top y 542-574 |
| 6 % / 12 % circle during the uses, in game | - | bandage and berries: 0 px / 0.000 % at FOV 72 and at FOV 100 |

The uses were accepted by the server (bandage count 3 -> 2, berries 4 -> 3 in both playtests).

**The ContentId failures** (`rbxassetid://128680694903427` and `111183762165020`, "No asset content representation
found while do_not_fallback_to_baseline is set to true"). Both are Studio-baked TexturePacks of the terrain's
MaterialVariants, not items. Serializing every SurfaceAppearance and MaterialVariant in the place
(`SerializationService`) finds `128680694903427` only in `MaterialService.AssistantMaterials["Material:
LS_MeadowGrass"].LS_MeadowGrass1` and `111183762165020` only in `["Material: LS_LichenGranite"].LS_LichenGranite3`.
These are the current overrides for Grass and Rock (`MaterialService:GetBaseMaterialOverride`), so every client that
draws grass or rock terrain fetches them. Open Cloud dates both packs to 2026-11-11T06:04:42Z / 06:04:48Z. The
same message appeared in another agent's playtest for `77422452927444`, the pack of the HunterCabin / Bedroll /
Campfire / Tent cloth SurfaceAppearances (world set). Neither fix-round playtest logged a failure for any
`rbxassetid`. The first one logged `rbxassethash://3d4aec1366ed452a9bf9a6d30d78988e` "Request asset was not found",
which was already in an earlier playtest's log and was not traced.
