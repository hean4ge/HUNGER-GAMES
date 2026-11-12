# Art style: realistic blockish

*Art director, 12 November 2026. Your note: "the grainy floor is very tacky u can just generate the pebbleish design on blendr ... make it realistic blockish type of thing so the water is good rn the grass is good the shading is good but stuff like the trees and buildings are tacky".*

*Three artists each built the same small set in Blender from scratch: a spruce, an oak, a hunter's cabin, a boulder, and two ground tiles (a pebble path and a forest floor). Each took a different reading of "realistic blockish". Nothing was downloaded or AI-generated. All three sets were imported into Studio beside the same terrain grass and pond, under today's lighting. They were shot at 14:00 and 17:30 next to today's arena.*

*This file compares the three, ranks them, recommends one and sets the rules every new asset follows. [ArenaV3.md](ArenaV3.md) waits on this choice. Nothing in the arena has changed: the test scenes sit apart in `Workspace.StyleTest`.*

**Waiting on you**
- **Which direction?** I recommend **A, "faceted realism"**, with three things borrowed from C (§5). Reply A, B, C or a mix.
- **One check on your words.** If "blockish" meant literal cubes, like Minecraft, then B is the pick, and its colours need lifting first (§3.2). Everything below reads "blockish" as chunky Roblox shapes, not cubes.

**In short (plain English)**
- **A is the pick.** It's built from big flat-shaded facets, like a carved wooden model, so it reads as Roblox and as real at once.
  - It sits naturally beside the grass and water you like, because the terrain grass is faceted too.
  - It stayed clean and readable at noon and at sunset.
  - At about 4,000 triangles a tree, it costs a third as much as the others, and the new 1 km arena needs that.
- **C is second.** It has the richest cabin and the nicest pebble path. But it's smooth and soft, not blockish: the spruce looks like melted clay, the oak like a cloud, and its bark has a fine speckle that reads as grain.
- **B is third.** It's built from cubes, so it reads as Minecraft, not realistic. In game it went nearly black (trunks, roof, both ground tiles), and its pebble path looks like square paving.
- **What we'd take from the others:**
  - C's pebble path.
  - C's leaf shapes for the forest floor, as bigger, fewer leaves in A's calmer colours.
  - C's oak branching and its porch railing.
  - Nothing visual from B, but B shows why colours must stay above a floor (rule 6).
- **Before rolling out:**
  - Fix A's oak: its limbs leave the trunk like spokes, and its bark reads slate-blue.
  - Lift every bark colour.
  - Rebuild the forest floor.
  - Cut the cabin from 15.8k to about 10k triangles.
  - Then check again in Studio at 14:00 and 17:30.

---

## 1. What you asked for, and how we read it

| Your words | What it means for the art |
|---|---|
| "keep the roblox aesthetic and make it look realistic thats all - mainly shading" | Simple, chunky Roblox shapes. Realism comes from true scale, natural colour and the lighting, not from fine detail. |
| "realistic blockish type of thing" | Geometric, chunky forms at true scale. No photos, no noise, no cut-out cards. |
| "the water is good rn the grass is good the shading is good" | Keep terrain water, terrain grass and today's lighting (LightingStyle Realistic). New assets must sit next to them. |
| "stuff like the trees and buildings are tacky" | Replace the photo-textured card trees (TreesReal) and the photo-textured buildings (BuildingsReal). |
| "the grainy floor is very tacky" / "generate the pebbleish design on blendr" | Replace the AI-made ground variants (LS_EarthPath1 and the rest) with tiles modelled in Blender: readable pebbles and leaves, no grain. |
| "you make them yourself" | Everything is modelled and baked by us in Blender. No downloads, no AI images. |

## 2. The test

Each artist built the same set at true scale (1 stud ≈ 0.28 m; the player is 5.5 studs):
- a spruce 35–50 studs tall;
- a climbable oak 25–30 studs tall;
- a log cabin with a porch, about 16 × 12;
- a boulder about 6 studs across;
- a pebble-path tile and a forest-floor tile (1024 px Color, Normal and Roughness).

**Where to look**
- **Start with the comparison sheet:** `art/previews/StyleTest/StyleTest_comparison_sheet.jpg`. It has four columns (today, A, B, C) and eight rows: wide shot, oak trunk, cabin porch and ground tiles, each at 14:00 and 17:30.
- **All 32 Studio captures:** `art/previews/StyleTest/Studio/`.
- **Blender previews:** `art/previews/StyleTest/A/`, `B/` and `C/`.
- **In Studio:** `Workspace.StyleTest` holds Scene_A, Scene_B and Scene_C. The templates are in `ServerStorage.StyleTest.Templates`.
- **Exports and manifests:** `BlenderExports/StyleTest/A/`, `B/` and `C/`.
- **Generators:** `art/blender/style_a.py`, `style_b.py` and `style_c*.py`.

**Today, for reference.** It uses photo-textured logs and roofs, cut-out card foliage, photo bark and the AI-made gravel and moss ground. Up close it's dark and busy, and the path is the grain you called tacky.

## 3. The three options

### 3.1 A: low-poly realism ("faceted realism")

**What it is.** Real silhouettes built from a few chunky volumes with large flat-shaded facets, like a carved model. Colour is painted per facet (light on top, dark underneath) and baked with soft ambient occlusion (AO). There is no grain, no photo texture and no card.

**In game.** It's the cleanest set at both times of day, and the only one whose surfaces match the terrain grass, which is itself made of faceted blades. The cabin is warm brown and handsome at 14:00 and glows at 17:30. The spruce looks crisp and convincing from the porch and from across the clearing.

**Best**
- **The spruce** has drooping, star-lobed tiers. It's the best tree in the test.
- **The cabin** has hewn octagonal logs, projecting corners, a knee-braced porch, a fieldstone chimney and a warm palette.
- **The boulder** is a jointed block with mossy top facets. It reads as real rock and costs only 172 triangles.
- **The ground tiles** are calm.
- **It's the cheapest set:** the trees are 3,850–4,305 triangles.

**Worst**
- **The oak's limbs.** Six limbs leave the trunk at one point like spokes and run straight like beams. Up close it looks built, not grown.
- **The bark is too dark and grey** (about 70,65,56 sRGB). At 14:00 the oak trunk reads slate-blue.
- **The oak crown is about 60 separate clumps.** Close up they look like floating green rocks.
- **The forest floor is made of tiny flakes.** It's calm, but the flakes add fine grain, and its moss patches show the repeat.
- **The cabin is heavy:** 15.8k triangles, with 4.4k in the chimney and 3.8k in the shingles. The green moss course along the eave reads as a stripe of coloured tiles.

**Numbers:** spruce 42.6 studs, 4,305 triangles; oak 27.3 studs, 3,850; cabin 15,788 in 13 parts; boulder 172; GLB 8.3 MB.

### 3.2 B: blocky voxel realism

**What it is.** Everything is built from cubes on a 0.5-stud grid, with one flat colour per cube face and AO baked between the blocks.

**In game.** It's the most literally "blocky", but it reads as Minecraft, not realistic Roblox. The stair-stepped roofs, limbs and spruce edges clash with the smooth grass. It's also by far the darkest:
- the oak trunk is near black at 14:00;
- the cabin is cold grey;
- at 17:30 both ground tiles are black squares.

The cause is dark base colours plus heavy baked occlusion, which Roblox's own shading then darkens again. It looked warm in Blender, and that is why rule 10 exists.

**Best**
- **One simple rule:** everything sits on a grid, so any asset can follow it.
- **The voxel spruce** has a lovely silhouette from a distance.
- **The cabin is cheap:** 4,280 triangles.
- **Its discipline:** no noise, no photos, one colour per face.

**Worst**
- **It isn't realistic.** Curves turn into staircases, and the boulder reads as stacked cubes.
- **It's too dark in game.** Its forest floor averages 48,44,32 sRGB, the darkest surface in the test (§8).
- **The pebble path reads as square paving**, not pebbles.
- **The porch's stepped brackets look like battlements**, not braces.
- **The trees are heavy** (12–13k triangles). There's also a risk of pixel cracks along merged faces, and of holes when Roblox simplifies the mesh at a distance.

**Numbers:** spruce 45.5 studs, 12,916 triangles; oak 27.5 studs, 12,022; cabin 4,280; boulder 424; GLB 4.8 MB.

### 3.3 C: smooth stylized realism

**What it is.** Rounded, sculpted forms (smooth blobs and tubes), with soft painted gradients and fine bark detail in the normal map.

**In game.** It has the richest detail, but it's smooth and soft rather than blockish.
- **The cabin** is the most realistic of the three: round logs, end-grain rings, a railed porch and a fieldstone chimney.
- **The trees are stylized.** The spruce looks like melted clay, and the oak crown is a cumulus cloud.

**Best**
- **The cabin's construction**, including the porch railing, which also works as cover.
- **The oak's branching:** the limbs fork and taper like a real oak's.
- **The pebble path:** clear, round pebbles in a light earth bed. It reads as a path from far away.

**Worst**
- **It isn't blockish.** Next to the faceted grass, its soft shapes look like a different game.
- **The bark has a fine speckle** that reads as grain in game, especially at 17:30. That's exactly the quality you disliked.
- **The white chinking** makes high-contrast stripes that look like vinyl siding.
- **The forest floor is orange and busy.** It has the most contrast and the most fine grain of all six tiles (§8).
- **It's heavy:** oak 14.6k triangles, spruce 10.7k, boulder 1.8k.

**Numbers:** spruce 43.7 studs, 10.7k triangles; oak 27.5 studs, 14.6k; cabin 13.8k; boulder 1.8k; GLB 8.5 MB.

### 3.4 Element by element

| Element | A | B | C | Best |
|---|---|---|---|---|
| Spruce | Crisp faceted tiers | Voxel tiers | Soft, melted tiers | **A** |
| Oak crown | Faceted clumps (rocks up close) | Voxel blob | Cumulus cloud | **A**, with fewer and bigger lobes |
| Oak limbs | Straight spokes | Stepped voxels | Forked and tapering | **C**'s structure |
| Bark | Slate-dark | Near black | Speckled | None: lift and warm it |
| Cabin | Warm, faceted, clean | Grey, castle-like | Most detailed; zebra stripes | **A**, plus C's railing |
| Boulder | Jointed faceted block | Stacked cubes | Smooth loaf | **A** |
| Pebble path | Calm, good | Square paving | Clearest pebbles | **C** |
| Forest floor | Calm, slightly grainy | Too dark | Orange and grainy | **A**, rebuilt (§5) |
| Beside the grass and water | Matches | Clashes | Different style | **A** |
| Triangles per tree | ~4k | ~12.5k | 11–15k | **A** |

## 4. Ranking

1. **A, low-poly realism: best overall.**
   - It's the closest to "Roblox, but real". The shapes are chunky and geometric, and true scale, natural colour and today's lighting carry the realism.
   - It matches the faceted terrain grass, and it held up at both times of day.
   - It costs a third as much as the others. That matters for ArenaV3's ~24k forest models and its view budgets (§7.5): ≤ 5M triangles at high quality and ≤ 1.5M on phones.
   - Its far versions (300–800 triangles, ArenaV3 §7.4) and the distant low-poly canopy shells use the same faceted language, so the swap won't change the look.
   - All its weak spots can be fixed within the style.
2. **C, smooth stylized realism: second.** It has the best cabin detail, the best oak branching and the best pebble path. But the look is soft and sculpted, the bark adds grain, and it costs three times as much as A.
3. **B, blocky voxel realism: third.** It's a clear, simple style, but it reads as Minecraft rather than realistic. It went nearly black under our lighting, its path isn't pebbles, and its trees are heavy and risky at a distance.

## 5. Recommendation: faceted realism (A), with three borrowings from C

Build everything in A's language. Before rolling out, take these pieces and make these fixes:

| Element | Take | Change before scaling |
|---|---|---|
| Spruce | A as it is | Lift the bark (rule 6). Make a far version of 300–800 triangles. |
| Oak and other broadleaf trees | A's facets and crown colour, plus **C's limb structure** | Limbs fork two or three times and taper, never spokes from one point. Merge the ~60 clumps into 5–8 big faceted lobes that read as one crown with gaps. Make the bark warmer and lighter. |
| Cabin and other buildings | A's cabin, plus **C's porch railing** | Chinking at most 40 levels lighter than the logs. Scatter moss across the shingles instead of a green eave stripe. Merge shingle rows and simplify the chimney, aiming for ≤ 10k triangles. |
| Boulders and cliffs | A | None. |
| Pebble path | **C's tile** | About 10% darker and slightly warmer, so it doesn't glare at noon. Keep 10 studs per tile. |
| Forest floor | A's calm palette, plus **C's whole-leaf shapes** | Fewer, bigger leaves (0.4–0.8 stud). No fragments under 0.25 stud. No moss patches: moss becomes its own material. Mean luma about 80–90. |

## 6. Style rules (every asset)

1. **True scale, few volumes.**
   - Every asset keeps its real size and silhouette: 1 stud ≈ 0.28 m, player 5.5, door 4 × 7.5, spruce 35–50, oak 25–30, ArenaV3's giants 105–175.
   - Build it from a handful of chunky volumes.
   - Model or paint nothing smaller than about 0.25 stud, except trim on buildings and items.
   - Check it as a silhouette at 100 studs: it should still say what it is.
2. **Facets are the "blocks".**
   - Surfaces are flat-shaded facets sized to the object:
     - 1–2.5 studs on trees and buildings;
     - 2–6 studs on cliffs and giant trunks;
     - 0.5–1.5 studs on rocks, bushes and props;
     - 0.1–0.4 studs on held items and the first-person hands.
   - Built pieces are chamfered prisms: logs, planks, posts, stones, shingle strips.
   - There are no smooth blobs, no cube staircases and no cut-out cards anywhere, including ferns, bushes and tufts. The terrain grass is Roblox's own, and it stays.
3. **Grow living things; build built things.**
   - **Trees** have a tapered 6–9-sided trunk with root flare. Limbs fork two or three times and thin out, never spokes from one point.
   - **Conifers** have drooping, star-lobed tiers that shrink up the trunk.
   - **Broadleaf trees** have 5–8 big faceted lobes forming one crown, flatter underneath, with gaps that show the limbs.
   - **Rocks and cliffs** are jointed blocks and strata with flat fracture faces, not eggs and not stacks of cubes.
   - **Buildings and props** are made of their real members, as chamfered prisms: hewn logs with projecting corners, plank decks, single fieldstones with mortar gaps, staggered shingle strips.
4. **Paint colour; don't texture it.**
   - Each facet carries a flat or gently graded colour. It's lighter and warmer on tops, tips and outer surfaces, and darker and cooler underneath and inside.
   - Vary it ±6% per volume and ±3% per facet, with a slight warm–cool drift.
   - Use no photo textures, and no noise, speckle or grain finer than about 0.3 stud on any surface.
   - Normal maps only round the edges (bevels of 0.03–0.12 stud) and add broad shapes: bark plates, plank grain, adze dimples.
5. **Let Roblox light it.**
   - Bake ambient occlusion only, never sunlight or cast shadows.
   - Multiply the AO into the colour so that no texel falls below half its painted value. Deeper contact shadow is the engine's job.
   - Make everything matte: roughness 0.75–0.95, metalness 0. Metal on items and glass are the only shiny surfaces.
   - Author for LightingStyle Realistic and today's LightingRig.
6. **Keep colours in the light band.**
   - Under Roblox lighting, baked AO and the sky's blue fill turn dark colours black or slate. That happened to all of B, and to every oak trunk at 14:00.
   - These targets are the mean sRGB per surface, after AO. They are roughly real-world albedo.

   | Surface | Target | In the test (§8) |
   |---|---|---|
   | Bark | 95–120, warm: red at least 25 above blue | All three oaks are 70–76: too dark |
   | Conifer needles | green channel 55–80 | A 43, B 53, C 47 |
   | Broadleaf leaves | green channel 65–95 | A 48, B 74, C 62 |
   | Hewn and weathered wood | 90–130 | A cabin 92 and C cabin 109: good |
   | Stone | 105–140 | Boulders 75–90: lift them |
   | Forest-floor tile | luma 80–95 | A 82, B 44, C 66 |
   | Path tile | luma 100–120 | A 114, B 72, C 105 |
   | Chinking and mortar | at most 40 above their neighbours | A's ~165 on ~90 logs reads as stripes |

   - Strong saturated colour is kept for gameplay signals only: loot, hazards and markers.
7. **Ground tiles are modelled, readable and calm.**
   - Terrain MaterialVariants are top-down bakes of modelled elements at true scale, on a flat matte bed:
     - rounded pebbles of 0.3–1.2 stud;
     - whole leaves of 0.4–0.8 stud;
     - twigs, cones and needles.
   - No element is smaller than 0.25 stud.
   - Nothing stands out (moss patches, big stones, bright leaves), because standouts show the repeat. Those become their own material or props.
   - Tiles are seamless 1024 px Color, Normal and Roughness, at 8–12 studs per tile, with MaterialPattern Organic.
   - **Measured check (§8):** luma spread (standard deviation) ≤ 18, and fine grain ≤ 5.
8. **Budgets for a 1 km arena.**

   | Asset | Triangles |
   |---|---|
   | Trees | 3–5k, plus a far mesh of 300–800 |
   | Giant trees | ≤ 12k, each part under 5k |
   | Bushes and ferns | 200–900 |
   | Boulders | 150–400 |
   | Cliff modules | ≤ 4k |
   | Small buildings | ≤ 10k, each part under 5k |
   | Props | 200–1,500 |
   | Items | 300–1,500 |

   - Use at most 3 MeshParts per tree: bark, crown, and roots if needed.
   - Give each tree species or building one 1024 texture set. Props, plants and rocks share 1024 atlases.
   - Aim for 10–25 px per stud on world assets.
9. **Gameplay reads first.**
   - Walkable and climbable surfaces (porch decks, limb tops, ledges) read flat and lit, and carry their tags (Climbable, Perch attachments).
   - Cover looks solid.
   - Canopies, bushes and ferns don't collide, so players can hide in them.
   - Doors are 4 × 7.5.
   - Faces that must not be climbed look sheer (PlayabilityPlan B7).
   - Loot, hazards and interactables are the only high-contrast, saturated things in a scene. World assets never compete with them.
10. **Approve it in game, not in Blender.**
    - B looked warm in Blender and went black in Studio.
    - Every new asset, or batch of assets, goes into the StyleTest diorama next to terrain grass and water. It's captured at 14:00 and 17:30 with `LightingRig.preview` before it ships.
    - Blender renders are for iterating only.

## 7. The rules by category

| Category | Shape | Facet size | Colour | Triangles |
|---|---|---|---|---|
| Trees (spruce, pine, birch, oak, giants) | Rule 3: tapered trunks, forked limbs, tiered or lobed crowns | 1–2.5 studs (giants 2–6) | Bark 95–120, warm; needles and leaves per rule 6 | 3–5k plus a far mesh; giants ≤ 12k |
| Plants (bushes, ferns, tufts, flowers) | Closed faceted clumps and folded faceted fronds with real back faces; never cards | 0.3–1 stud | Greens as the trees; flowers and berries are small accents, only where they mean forage | 200–900 |
| Rocks and cliffs | Jointed blocks and strata; moss only on upward facets | Rocks 0.5–1.5; cliffs 2–6 | Stone 105–140, with gentle bands by stratum | Boulders 150–400; cliff modules ≤ 4k |
| Buildings | Real members as chamfered prisms; enterable through 4 × 7.5 doors | 1–2.5 studs | Wood 90–130; chinking and mortar at most +40 | ≤ 10k, each part under 5k |
| Props (crates, barrels, racks, signs) | As buildings, smaller; planks and hoops as members | 0.3–1 stud | As buildings; loot crates may carry the UI accent | 200–1,500 |
| Items and first-person hands | Chamfered prisms; the hands keep the blocky Roblox arm, and realism comes from the shading | 0.1–0.4 stud | Matte painted colour; metal is the only shiny surface | 300–1,500 |
| Ground tiles | Rule 7: modelled pebbles, leaves and twigs, rendered top-down | No element under 0.25 stud | Forest floor luma 80–95; paths 100–120 | 1024 px at 8–12 studs per tile |

## 8. Measurements

**Ground tiles.** These are the 1024 px Color maps as exported. Luma is Rec. 709 on the sRGB values.
- **Spread:** the standard deviation of luma.
- **Fine grain:** the standard deviation of luma minus a box blur about 0.1 stud wide.
- **Mid detail:** the same, between blurs of 0.1 and 0.5 stud.

Readable shapes show up as high mid detail with low fine grain. Grain shows up as high fine grain.

| Tile | Studs per tile | Mean sRGB | Mean luma | Spread | Fine grain | Mid detail |
|---|---|---|---|---|---|---|
| A pebble path | 8 | 126,113,96 | 114 | 16.6 | 4.3 | 9.5 |
| A forest floor | 10 | 95,81,63 | 82 | 13.1 | **6.7** | 8.3 |
| B pebble path | 8 | 78,71,62 | **72** | 15.5 | 5.4 | 10.2 |
| B forest floor | 8 | 48,44,32 | **44** | 10.5 | 4.7 | 6.9 |
| C pebble path | 10 | 113,104,92 | 105 | 20.1 | 4.8 | **12.8** |
| C forest floor | 12 | 83,63,44 | 66 | **21.7** | **9.2** | 13.7 |

**What the tile numbers show**
- **C's pebble path** has the clearest shapes for little grain.
- **C's forest floor** is the grainiest and busiest.
- **A's forest floor** is calm but carries more fine grain than either good path.
- **B's tiles** are too dark to survive the lighting.

**Asset atlases.** These are approximate: texels with red above green count as bark or wood, and texels with green above red count as foliage. AO and padding are included.

| Asset | Bark or wood | Foliage |
|---|---|---|
| A oak | 70,65,56 | 35,48,20 |
| A spruce | 41,33,27 | 28,43,25 |
| B oak | 76,69,60 | 52,74,30 |
| B spruce | 58,46,36 | 34,53,34 |
| C oak | 72,63,52 | 44,62,33 |
| C spruce | 68,50,37 | 26,47,36 |
| A, B and C cabins | 92,79,66 · 81,73,64 · 109,96,82 | — |
| A, B and C boulders (whole atlas) | 90,88,77 · 75,74,69 · 89,89,70 | — |

## 9. Next steps (once you pick)

1. **Style set A, version 4,** with the §5 changes: the new oak, lifted bark, C's path, the rebuilt forest floor and the lighter cabin. Re-shoot the same eight Studio shots, and you confirm.
2. **Fold the rules into the shared Blender helpers:** facet painting, the AO bake with its floor, the value check from §8, and the far-mesh export. Every generator then follows them by default.
3. **Rebuild in ArenaV3's order.** Trees and the forest floor go first, because they fill most of the screen. Then come rocks and cliffs, then buildings and props, then items and the first-person hands.
4. **Replace the terrain ground variants** (LS_EarthPath1, LS_ForestFloor and the rest) with the new tiles.
   - Check whether the terrain colour tints them. B's import notes found that `TerrainGen.Palette` tints Ground and LeafyGrass. If it does, set those to white so the tiles show as authored.
   - Leave the grass, the water and the lighting as they are.
