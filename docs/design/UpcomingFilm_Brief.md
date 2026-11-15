# The green land, the launch, the clock and the train: visual and layout brief

*Art director, 14 November 2026. The owner's final direction, in their words: "WATCH THE TRAILER FOR THE UPCOMING HUNGER GAMES AND MAKE THE FIRST MAP LIKE THAT", "AND MAKE THE TRAINS LOOK LIKE THEM TOO", "RECREATE IT ON BLENDR", "make sure blendr recreates the map assets and game design with semi realistic colour tones", and the correction after the launch-room frames: "the red room with the metal on top is just the transition room before you go to the survivakl game ... the second map ... will be like the second map of the original hunger games movie where the map is a clock". The upcoming film is* The Hunger Games: Sunrise on the Reaping *(the 50th Games, in cinemas 20 November 2026).*

*This brief rests on the owner's eight frames (each one matched to an official trailer), three research passes (trailer frames, web images, book and press text) and my own colour sampling of the captured frames. It is design only: nothing is built yet. The reference images are for study only. None of them is in the repo, and none may go into the game, traced or not. Every asset is modelled by us in Blender, following `.claude/skills/blender-art/SKILL.md`.*

**Still in force**
- From [ArenaV3.md](ArenaV3.md): the TerrainGen v3 core (§7.1), the staged border (§6.5), and the streaming, density and memory budgets (§7.4–7.6). Its Vale layout and its avoid list are superseded.
- [ArtStyle.md](ArtStyle.md) style A ("faceted realism") and all of its rules.
- The 13+ rating: no severing and no heavy gore.
- IP: we use the films' terms in documents. In-game names are an open decision. No film imagery, logos or text goes into the game.

## In short (plain English)

- **Map 1, the green land, is a glacial valley shaped like an eye.** In the book, the arena seen from above is an eye. The golden horn is the pupil and a ring of spring meadow is the iris. Forest tapers to a point in the north and the mountain tapers to a point in the south. The film shot it in a limestone valley in Spain.
  - Our version keeps the play radius of 1,800 studs (about 1 km across), because the film's own geography fits it (§1.2).
  - Long limestone ridges with heather form the east and west "eyelids".
  - A turquoise lake lies under a sharp peak, and the peak is the volcano.
- **The heart of Map 1 is the film's opening shot.** A crown of six white sails stands on a low cream platform with three mouths. 48 steel plinths with copper tops ring it at 120 studs. 15 long, pointed flower beds radiate between them like the rays of a sun.
- **One launch sequence serves both maps, as one vertical set and one camera shot.** It runs in three stages:
  1. The red room under a metal net, where you wait while the map loads.
  2. A disc lifts you up a teal hexagonal tube into a tall glass case. The case is one of a ring at the foot of a giant round hall.
  3. Your case's disc rides a long pole up through the hall while the camera circles you. Light floods in, and you rise out of a brass-rimmed tube in the meadow (Map 1) or out of the lagoon (Map 2).
- **Map 2 is the clock.** A saltwater lagoon holds an island with a horn of steel shards. Twelve rock spokes run to a sand beach, and jungle climbs to a force field. The jungle is cut into twelve wedges, and each hour of the clock sets off one wedge's horror. We keep every hazard from the book and the film, and add our own for the four sectors nobody saw.
- **Map 2's size needs your answer.** The owner's reference is a fan-made guide. Its own scale bar measures the arena at 1.45 km across, not 1 km, so a literal 3× would be about 4.4 km (§3.2). That breaks every budget we have. The real film set's lagoon was roughly 120–170 m across. Three times that is the fan guide's lagoon, and so the fan guide's 1.45 km arena already is "3× the film". **I recommend R = 2,600 studs (1.46 km).**
- **The train and station follow the film.** The station is a vaulted hall of steel and glass in amber light, with a gold sunburst hanging through the ceiling. Two glossy black and maroon trains have bullet noses and glowing red lamps. Guards in white armour stand in rows, and dark banners hang overhead. The film's colours override the TRIBUTE spec's "brushed silver"; the spec's seven cars stay.
- **Colour.** Every colour below starts as a value sampled from a frame and ends as a softer, natural tone in ArtStyle's light band. The film's grade pushes skies to cerulean and shadows to teal; we take both out. Saturated colour stays only on gameplay signals: the flower beds (they are hazards), loot, the copper start plates and the warning lights.

**Waiting on you**
1. **Map 2's size** (§3.2): R = 2,600 studs (recommended), or the literal 3× (R 5,360 from the plan's "about 1 km", or R 7,770 from the measured 1.45 km), which needs new budgets.
2. **48 plinths on Map 1** (§1.4): the film shows 48. I recommend building 48. A 24-player round stands on every second plinth, and the 48-player Jubilee mode fills them all (Roadmap decision 4).
3. **The horn's colours** (§1.4): white, muted plum and dull gold. That is the real set's colouring, softened, and the sky light turns the white blue-grey in shade, as in the trailer. Or the trailer's teal.
4. **In-game names** for the horn, the plinths, the guards and the station stay open, as you asked.

**How to read it**
- **Tags.** **C** confirmed: seen in a frame or still. **L** likely: from the book or reliable text. **I** invented: our fill-in, in the film's spirit.
  - Unplaced or unverified trailer shots are never C. When we use one, it is tagged I, and the text says what it came from.
- **Video sources** (each one is listed with its link in [Sources](#sources)):

  | Code | Video | Link |
  |---|---|---|
  | T1 | Official Trailer | https://www.youtube.com/watch?v=fS35YSjopjE |
  | T2 | Official Trailer 2 | https://www.youtube.com/watch?v=lYXtL5TreOE |
  | FE | Official Fan Edit Trailer | https://www.youtube.com/watch?v=Dr060OLTodE |
  | SH | official vertical short | https://www.youtube.com/shorts/wHfz2bj22V0 |
  | TVn, TVk | TV spots "no idea" and "keep" | https://www.youtube.com/watch?v=VVX1poVhssg and https://www.youtube.com/watch?v=ITJWMDcOizk |
  | IMAX | IMAX film clip | https://www.youtube.com/watch?v=ilUGc9ozPY4 |

  A local frame is `References\trailer\<video>_<time>.png`, for example `trailer1_40.2s.png` for T1 @40.2 s. Text sources are numbered [1]–[49]. The student write-ups [13]–[15] are trailer readings, not production sources.
- **Sampled colours** are trimmed means of a region of a captured frame. The frames are compressed YouTube streams and carry the film's colour grade, so they are evidence, not targets. The tools and overlays are in `%TEMP%\claude\...\scratchpad\arenas_v5\brief_tools\`.
- **Semi-real tones** are the base colours we paint: the mean sRGB of a surface after baked AO, as in ArtStyle rule 6. Luma is Rec. 709 on sRGB, as ArtStyle §8 uses.
- **Scale:** 1 stud ≈ 0.28 m, and a player is 5.5 studs tall. Bearings are degrees clockwise from north (−Z), and r is the distance from the map centre, as in ArenaV3.

### The colour translation rule (all four parts)

| Step | What we do | Why |
|---|---|---|
| 1 | Sample the frame (owner frame first, then the clearest trailer frame). | Evidence of hue and relative value |
| 2 | Take out the grade: no teal in shadows, sky saturation down by about 40%, flesh and stone back to neutral. | The trailer pushes cerulean skies (#047fa6) and teal shadows (#16343a forest, #1f353c plinths from the air). Roblox's sky fill adds its own cool shade, so a grade baked into the paint would double up. |
| 3 | Soften toward natural: lighter in the shadows, slightly warmer, about 10–20% less saturated than the film. | "Semi realistic colour tones", in ArtStyle's light band |
| 4 | Clamp into the band. Natural surfaces use ArtStyle §6 rule 6 (bark 95–120, needles G 55–80, leaves G 65–95, wood 90–130, stone 105–140, forest floor luma 80–95, paths luma 100–120). Built and painted surfaces stay between luma 55 and 215. Things that must read black (grates, lacquer, harness straps) go no lower than luma 40. | ArtStyle §3.2 and §6: dark paint goes black under AO and Roblox shading. Bright paint glares at noon under Realistic lighting. |
| 5 | Keep saturation only for signals: hazards (the flower beds, fire, mutts), loot, the copper start plates and warning lights. | ArtStyle rule 9 |
| 6 | Darkness in interiors comes from the lights, not the paint. | The launch halls are near black on film. Painted near black, they would be black holes in Roblox. |

---

## 1. Map 1: the green land

### 1.1 What the film shows

- **The opening aerial** is the owner's frame `owner\map1_green_land_owner_frame.png`, which is T1 @1.7 s, and the same drone take appears in T2 @43.9–46.4 s. It shows (C):
  - a lush valley of rolling grass under misty mountains, with a cloud bank at mid-slope;
  - dark conifer forest on the left slope; rounded tree clumps, a gully and a gorse slope with boulders on the right;
  - a ring of 48 plinths on a gentle knoll, with a tribute on each (TVn @6.1–7.1 s prints "48 COMPETITORS");
  - long pointed flower beds radiating from the horn;
  - the horn on a cream platform.
- **The owner's "pale stone radial pattern at the centre" is not paving.** At full resolution it is three things (C, T1 @1.7 s detail crops):
  - a periwinkle and white flower bed in front of the horn;
  - the cream face of the platform;
  - the horn's long shadow across the beds.
- **The location** is the Valle de Lago glacial valley in Somiedo Natural Park, Asturias, Spain. The horn was built in a meadow near Lago del Valle, and Teverga's beech forest was used too. The shoot ran from July to August 2025 (L [1][3][4]).
  - Production laid bright artificial turf inside the starting circle and used CG for the rest of the meadow (L [1]).
  - A set photo shows that turf meeting dry hay outside the circle (C, `web\map1_set_photo_cornucopia_white_plum_gold_base.png` [16]).
- **The look** was pushed "vivid but natural" on purpose: a lush, beautiful arena that contrasts with the killing (L [10][11]).
- **The book's plan** is the eye: the golden horn is the pupil, the spring-green meadow is the iris, and forest and mountain taper to points north and south. The meadow "went on for miles" (L [19][17]).
  - Haymitch has the forest on his left and a snow-capped mountain across from it. He heads north into the forest because the arena sun rises in the east (L [20][21]).
  - The mountain is an artificial volcano (L [17][18]). A night eruption is in the film (C, IMAX contact sheet `web\map1_imax_clip_volcano_forest_fire_sheet.png`).

### 1.2 Shape and size: why the radius stays at 1,800 studs

**Size.** The play radius stays at **r 1,800 studs (504 m), so the arena is about 1 km across.** ArenaV3's wall, Boundary (r 1,900) and backdrop (to r 2,700) stay with it.
- **The film's geography fits a ~1 km disc** (L, FE @26.9 s, `fanedit_26.9s_detail_ring_in_landscape.png`).
  - In the high aerial, the whole plinth ring is a small disc about a tenth of the frame wide, on a broad grassy shoulder.
  - Open grass runs about 300–500 m around the ring before scrub, forest and steep ground take over. Slopes and valleys go on past 1 km.
  - So a 1 km play disc holds the ring, an iris of open meadow about 300 m across, forest, crags and the lake, with real mountains as the backdrop.
- **The real place supports it.** Lago del Valle is a glacial lake of about 22–24 ha at about 1,550 m, ringed by peaks (L [5][6]). One glacial valley walled by limestone is the film's whole arena (L [1]), and a 1 km slice of it is what the trailers show.
- **The book's "miles" of meadow would argue for more.** But our budgets are built for r 1,800: ArenaV3 §7.2's grids, §7.5's scatter caps and §7.6's phone memory. So is the 15-minute round, at 138 s from the centre to the edge at a jog.
- **The eye changes how the land inside the circle is used, not the circle.** The staged border still starts at r 1,800 and closes on the horn.

**Shape (I, from the book's eye [19]).** The valley floor is an almond whose long axis runs north–south.
- Its tips are at 0° (r 1,750, the north edge) and 180° (r 1,700, under the peak).
- It is widest east and west, where the floor meets the ridges at about r 1,150.
- From the air: a green iris, dark forest to the north, grey and tan mountain to the south, and limestone ridges as the lids. The winner's closing camera can pull straight up and show the eye (I, after the book's ending shot [19]).

**Schematic** (not to scale; north up):

```
                         N 0°
                  . . . EDGE . . .            EDGE  cliff and force field over the canyon (r 1,750)
              . '  ^  HEDGE HOLLOW  ^ ' .     HEDGE holly wall in a grassy hollow (r 1,600)
           .'  ^^  TTTTTTTTTTTTTTTTT  ^^ '.   T     the North Wood: pines and firs, beech at its edge
         .' ^^^^  TTTT@TTTTTTTT*TTTTT ^^^^'.  @     crimson spiral clearing; * flower-sun glade
        / ^^^^^^  tttt,,,,,,,,,,,,tttt ^^^^^\ ^     east and west ridges: limestone, heather, gorse
       | ^^^^^^  t,,,,,,,,,,,,,,,,,,,t ^^^^^ |
   W   | ^^^^^  t,,,,~,,(( O )),,,,,,,t ^^^^ |  E   ,  the Iris: meadow with folds, clumps, boulders
       | ^^^^^^  t,,,~~,,,,,,,,,,,,,,t ^^^^^ |    O  the horn; (( )) the 48 plinths and 15 flower spokes
        \ ^^^^^^  ::,~~,,,,,,,,,,,:: ^^^^^^/  ~  the stony wildflower stream, then the lake
         '. ^^^^  ::::~~~~LAKE~~:::: ^^^^.'   :  scree fans and boulder fields
           '.  ^^  :::: PEAK ::::  ^^  .'     PEAK the sharp limestone horn-peak: the volcano
              ' .  :::::VVV:::::  . '
                  ' . . S . . '
                         S 180°
```

### 1.3 Regions, landforms and heights

Heights are y in studs, with the horn knoll at 46, the same base as ArenaV3's PlazaY. Water levels follow ArenaV3 §3's voxel rule.

| Region | Where (bearing, r) | Landforms and heights | What is there | Tag |
|---|---|---|---|---|
| **The Heart** | the centre, r 0–160 | A low dome: platform deck 52 on the knoll top at 46; the plinth ring at r 120, about 1.5 lower (1 in 80); turf to r 150 | The horn, 48 plinths, 15 flower spokes, 6 teardrop beds, bright turf | C (layout), I (numbers) |
| **The Iris** | r 160–600, its edge wavering between 520 and 700 | Meadow at 30–60 in soft folds; knolls up to +15; a long dip 6–12 deep carrying the stony stream from the north-west to the lake | Open grass, tree clumps in the hollows, gorse thickets, white limestone boulders, flower berms, three lone round trees in front of the mouths | C (look), I (positions) |
| **The North Wood** | 300°–60°, r 600–1,750, narrowing to the north tip | Floor rising from 60 to 220–260, with ravines 20–40 deep | Dense pines and firs, beech at the lower edge, clearings of tall pale grass, the crimson spiral, the flower-sun glade, the hedge hollow at the tip | C (look), L (holly hedge), I (layout) |
| **The South Mountain** | 120°–240°, r 600–1,800 | From 60 at its foot to the summit at about 640 (180°, r 1,550); scree fans 150–400; crag bands 40–80 high | The sharp limestone peak (the volcano), tan scree, grey crags with magenta heather, boulder fields, the lake at its foot | C (look), L (volcano), I (layout) |
| **The Lake** | 160°–200°, r 800–1,050 | Water at 34, up to 14 deep; rocky grass shores | A turquoise mountain lake under the peak | C (look), I (place) |
| **The East and West Ridges** (the lids) | 60°–120° and 240°–300°, r 1,150–1,800 | Feet at 70–90, crests at 320–420 near r 1,550–1,750; gullies | Conifer forest on the lower slopes, gorse, then limestone and heather to the crest; tree clumps in the gullies | C (look), I (layout) |
| **The Edge** | the north tip, r 1,750–1,800 | Flat dry ground at about 240, then a sheer cliff of about 107 studs (30 m) into a rocky canyon outside the Boundary | The force field at the lip; a generator's hum and light in the canyon | L (book [17][23]), I (numbers) |
| **The Crest** | everywhere else | ArenaV3 §2's wall: the 18-stud sheer step (r 1,814–1,878), Boundary r 1,900, massif to r 2,700 | Real limestone mountains beyond, holding the low cloud | I (ArenaV3 core) |
| **Sub-A** (later) | under the north | Corridors | Green pipes, blue cabinets, fluorescent tubes (C, T2 @124.4 s); the book's catacombs with the giant water tank (L [29][22]) | C, L |

Slope budget: ArenaV3 §3. At least 85% of the land is under 30°, and the only faces you can't walk are the crags, the cliff Edge and the peak, all by design.

**Cover in the Iris.** The film's meadow is open, and ArenaV3 warned that a wide meadow becomes a shooting gallery. So there is a break in the line of sight every 40–80 studs (I): a dip, a tree clump, a gorse thicket, a boulder or a berm. The view from the plinths stays open.

### 1.4 The heart: the horn, the platform, the plinths and the flower spokes

**The horn** (C: T1 @40.2 s detail, `trailer1_40.2s_detail_horn.png`; T2 @49.9 s; set photo [16])
- **Shape.** Six tall, narrow, pointed sails in three pairs around a hollow centre. In each pair, a shorter, wider outer sail half-encloses a taller inner one, and the outer sails flare out at the foot like tent skirts.
  - The sails are folded planes with seams fanning out from the base (C).
  - The "dark central spike" in the trailers is the A-frame mouth: two inner faces meeting at the top (C, T1 @40.2 s). The fan wiki confirms it: white outer faces, deep purple inner faces, and gold strips fanning like sunbeams from quarter-circle motifs at the base (L [16]).
- **The interior** is a hollow tent you walk into (C, T2 @49.9 s; FE @72.2 s):
  - navy inner walls with gold edges and gold battens;
  - a cream floor, with brass threshold blocks at the ramps;
  - swords, axes and tridents hanging on the walls, and white supply bags on the floor.

  The bloodbath happens on this deck (C, T2 @129.2 s).
- **Colour.** The trailer grades the horn teal and blue-grey. The real set is white with dark plum inner faces and gold edges, on a gold-yellow base (L, fan-account set photo [16]).
  - We paint the real colours, softened. The sky fill turns the white blue-grey on its shaded side by itself.
- **Size.** About 12–15 m tall (L, estimated against the tributes).

**Ours** (I, in the film's shape):
- **Layout:** three-fold symmetric, with the three mouths facing 60°, 180° and 300°. The south mouth frames the peak, as the film's view out of the mouth does (C, T2 @49.9 s).
- **Sails:**
  - inner sails 50 studs above the deck, outer sails 36;
  - the outer skirts flare to 20–26 studs at the base;
  - the hollow centre is about 36 studs across.
- **Mouths:** A-frames 16 studs tall and 14 wide at the deck.

**The platform** (C: a low block with cream panels, vertical joints, a teal band along the top edge and dark bronze steps at the mouth; L: a three-pointed star in plan, with a stair in the middle of each side [16])
- **Plan and height:** a three-pointed star, 100 studs across the points (the points face 0°, 120° and 240°), standing 6 studs (1.7 m) high. That is within the film's 1.5–3 m, and a player can mantle it anywhere.
- **Cladding:** cream stone panels 6 × 3 studs, with 0.15-stud joints.
- **Band:** a 1.2-stud band of muted teal glass under the coping.
- **Steps:** at each mouth, a bronze stepped block 18 studs wide with four risers of 1.5 studs.

**The plinths** (C)
- **Film:** short drums about 1–1.2 m wide and 0.4–0.5 m tall. The sides are pale brushed steel and the top is a polished copper plate (FE @37.4 s). From the air they read dark (T1 @1.7 s), and the set photo shows them pale stone grey.
- **Arrival:** each tribute first comes up through a tube in the grass with a thick brass rim, flush with turf full of dandelions and daisies (C, T1 @129.2 s).
- **Ours:**
  - 48 plinths at r 120, every 7.5°, offset 3.75° so that each mouth bearing falls between two plinths;
  - each drum 4.3 studs across and 1.6 tall, with a 0.25-stud copper top plate;
  - each standing in its tube: inner diameter 7.2 studs (PlateTube radius 3.6), with a 0.6-stud brass rim flush with the turf.
  - At 7.5° the plinths are 15.7 studs (4.4 m) apart, inside the film's 4–5 m (L estimate).

**The flower spokes** (C: long, narrow, mounded beds, pointed at both ends, radiating from the platform to the ring in alternating colours, ankle to knee high, packed with flowers on turf; T1 @1.7 s detail crops, T2 @43.9 s, LNE set photo [9])
- **Ours (I):**
  - 15 spokes every 24° starting at 0°, so the three mouth bearings (60°, 180°, 300°) fall halfway between two spokes and stay open as approach lanes;
  - each spoke runs from the platform (r 35–55) to just inside the ring (r 110): 55–75 studs long, 9 studs at its widest, mounded 1–1.5 studs, pointed at both ends;
  - colours in a five-step cycle repeated round the circle: buttercup yellow, poppy red, rose pink, lavender, magenta (C colours).
  - Each mouth lane is flanked by two teardrops (C, T2 @49.9 s; T1 @40.2 s): a periwinkle and white one (30 × 12 studs) and a marigold one (22 × 10 studs). The periwinkle teardrops are the owner's "pale radial pattern".
  - A fallen cape or two lying on the grass is a nice touch (C, LNE photo [9]).
- **The turf** inside r 150 is a fresher green than the meadow, as on the set (C).

**Lone trees.** One lone round tree stands on each mouth bearing at r 260, just past the ring (C: one is seen from the mouth in T2 @49.9 s; I: three, one per mouth).

### 1.5 Plants

| Plant | Where | Film or book | Style A form and size | Tag |
|---|---|---|---|---|
| Meadow grass | Heart and Iris | lush spring green (C); turf inside the ring (C); dry hay outside it on the set (C) | Terrain grass in three tints (§1.11) | C |
| Dandelions and daisies | the turf around the tubes | C, T1 @129.2 s | 0.5–0.8-stud faceted heads in ground cover | C |
| Flower-spoke flowers | 15 spokes, 6 teardrops | C | Mounded bed meshes with 0.3–0.6-stud faceted heads | C |
| Wildflowers (yellow, blue, white) | along the stony stream | C, T2 @128.7 s | Low clumps, 0.5–1.2 studs | C |
| Pines (tall, pinkish trunks) and firs | North Wood, ridge feet | C (T1 @1.7 s; T2 @114.2 s) | Spruce and pine of style A, 35–50 studs; pines with tall clear trunks | C |
| Beech and oak | clumps in the Iris hollows, the North Wood's edge, lone trees | C (rounded clumps); L (Teverga beech forest [1][4]) | Broadleaf of style A, 25–35 studs, 5–8 crown lobes | C, L |
| Gorse and broom | the Iris edge, ridge slopes, along forest paths | C (T1 @1.7 s; T2 @114.2 s) | Faceted bush clumps 3–6 tall, 4–10 across, with yellow flower lumps | C |
| Heather (magenta and pink) | crags, ridges, mountain slopes | C (FE @37.4 s, @64.4 s; T2 @49.9 s, @54.2 s) | Low faceted mats 0.8–1.5 studs | C |
| Bracken and fern | the outer Iris, forest floor | C (location photo [9]) | Folded faceted fronds 2–3 studs | C |
| Tall pale grass | forest clearings | C (T2 @55.9 s) | Tall-grass clumps 2.5–3.5 studs | C |
| Crimson spiral maze | North Wood clearing (330°, r 900) | C (T2 @55.9 s): a mounded spiral of red and magenta flower hedges about waist high, 10–15 m across | 50 studs across, three turns; hedges 4 tall, 2.5 thick; paths 4 wide | C, I (place) |
| Holly hedge | the hedge hollow (350°–10°, r 1,600) | C: a dark green hedge wall 4–5 m tall in a grassy hollow ringed by rocky slopes and purple flowers (TVk @8.8 s); L: the book's V-shaped holly maze at the north edge [17][23] | Walls 16 tall, 5 thick, in a V-shaped maze; purple lupin and heather around it | C, L |
| Flower-sun glade | North Wood clearing (60°, r 1,000) | Unplaced in the footage (FE @25.4 s: a golden grass circle ringed by peach pompoms, with spokes of rose, magenta, lavender and coral) | A 24-stud grass circle with 16 flower spokes 12–20 long; a lure spot | I |
| Apple trees and fruit bushes; a katniss patch | Iris and wood edges | L (book [17]) | Small faceted fruit trees 14–18 studs | L |

### 1.6 Water

| Water | Where | Look | Tag |
|---|---|---|---|
| The lake | the mountain's foot, level 34 | Turquoise and clear, with rocky grass shores and limestone boulders (C, T2 @54.2 s; SH @26.4 s) | C, I (place) |
| The stony stream | through the Iris dip, from 60.5 down to 34 in riffles | A shallow stream bed of pale pebbles with wildflowers on both banks (C, T2 @128.7 s) | C |
| Poison | every stream (book) | Crystal clear, with a tell such as a dead rabbit at the bank. In the book, rain is the only safe water [17][21]. | L |
| Rain showers | anywhere | Short showers; the book's last about 20 minutes [18] | L |
| The canyon river | below the Edge, outside the Boundary | Heard rather than seen; it carries the generator's hum | I |

### 1.7 Sky and light

- **Day (C):** a high sun with hard shadows, and the horn's long shadow wedge across the beds (T1 @1.7 s). Azure sky and big cumulus (T1 @40.2 s; L, book [21]).
  - A cloud bank lies on the mountain flanks at mid-slope, and wisps hang round the peak (T1 @1.7 s; T2 @49.9 s).
- **The hero shots (C):**
  - backlit, with sun rays through the cloud behind the horn and the dark crag mountain (T1 @77.7 s);
  - the arrival in low, warm side-light (T1 @129.2 s).
- **Night (C):** pine forest fires with falling embers (T1 @96.8 s; T2 @120.2 s). The eruption lights the peak from inside (IMAX).
- **The sky is artificial (L).** The dead are projected on it. When it fails, the real night sky shows through (book [22][24]).
- **Ours (I), starting values on LookDevPlaybook §9's "Forest day":**
  - Atmosphere Density 0.30, Offset 0.22, Color (204,212,218), Decay (120,134,150), Haze 1.4, Glare 0.35;
  - Clouds Cover 0.55, Density 0.45, Color (246,246,248);
  - ColorCorrection Contrast 0.06, Saturation −0.02, Tint (255,250,244);
  - the low cloud bank as slow particle sheets at y 250–400 on the flanks (LookDevPlaybook §6), colour (222,226,226);
  - morning mist in the hollows at the start.
- **The sun's path** rises in the east (book [20]) and stands over the south at noon, behind the peak. From the horn, the hero view south is backlit, like T1 @77.7 s.

### 1.8 Hazards seen or described

Each one gets a tell first and a model or effect of its own. Nothing is a recoloured NPC.

| Hazard | Source | Where | What it looks like in our style | Tag |
|---|---|---|---|---|
| Flower beds that explode | T2 @126.2 s (a yellow metal daisy fizzes sparks like a lit fuse); T2 @127.4 s (a fireball from a bed) | the spokes and the berms | The tell: one "fuse daisy" in a bed hisses and sparks for 2–3 s. Then a fireball column 8–12 studs high, and the bed is left charred | C |
| Fire through heath and scrub | T1 @113.8 s (a wall of fire across a scrub slope); the top-down shot of burning shrubs (`web\map1_trailer2_burning_flower_shrubs_top_down.png`) | gorse and heather slopes | Flame sheets running along the bushes, embers and smoke; the facets left charred at (54,50,48) | C |
| Night forest fire | T1 @94.4 s, @96.8 s; T2 @120.2 s; IMAX | the North Wood and the ridges | Burning pines, falling embers, an orange glow under the canopy | C |
| Blue butterfly swarms | T2 @114.2 s (a swarm knocks a tribute down); the book's stinging, taser-like butterflies [17] | gorse-lined forest paths, the Iris | 40–80 faceted butterflies, wingspan 0.6–0.8 studs, in blue (70,126,186), crackling when they sting | C, L |
| Crimson long-necked birds | T2 @135.4 s (diving at a tribute on scree); the book's candy-pink needle-beaked waterbirds [17] | the scree and the lake | Flamingo-like faceted birds 4–5 studs tall, wingspan 6, crimson-pink (190,60,72), in flocks of 8–15 | C, L |
| The volcano | IMAX (a night eruption above the valley); the book: flames, a toxic wind, clear sparkly ash, a burning gel that sets hard and glassy [17][18] | the south peak and its slopes | The tell is a smoking vent and tremors. Then fire fountains, sparkly ash, and emissive gel flows that cool into a glassy dark crust (84,82,86) | C, L |
| The force field | T2 per [28] (it is brushed, and an axe rebounds); the book's edge [17][23] | the Edge and the Crest | Invisible until touched, then a faint ripple of hexagons. Whether thrown things bounce back is a game design call | L |
| Berm hatches | the book: raised berms of one poisonous flower each, with a brass plaque, hiding hatches to Sub-A [17][24] | the Iris and the wood | Round berms 6–10 studs across with a small brass plaque. A hatch opens like an iris for Warden releases | L |
| Golden squirrels in packs | the book [17] | the wood | 1.2–1.5-stud faceted squirrels in golden fur (196,160,82). No gore is shown | L |
| Ladybugs posing as holly berries | the book [17] | the hedge hollow | Berries that swell and burst in a red puff (13+) | L |
| The quill porcupine | the book [17] | the wood | Bear-sized at about 8 studs long, firing steel quills; it cries like a baby | L |
| Foxes, spiked-hoof fawns, glass-winged bats | the book [17] | the wood; bats in Sub-A | Faceted animals, each with one wrong trait (ArtStyle's creature rule) | L |
| Malfunctions | the book after the tank blast: the sky dies, an apple tree sprays blue sparks, a stream steams, trees drip blood, stumps belch glowing gas [18][22] | anywhere | Dark red sap only, never gore (13+) | L |
| Tear gas from a hovercraft; an earthquake | the book [18][24] | the wood | Grey-green gas sheets; ground shake and falling rocks | L |
| A hovercraft crash | the trailer pass lists it among T2's hazard shots; its frame is not in our set | a set piece | A crashed hull in the North Wood as a site | C (per the research pass), I (place) |
| A thrown axe at the edge | T2 @130.8 s (a tribute hurls an axe); the book: Silka's axe rebounds off the force field [23][28] | the Edge | The ripple of §1.9 where the axe strikes | C, L |

**Mixed up each round (I):**
- which spoke colour is "live";
- the order of the colours round each third;
- which berms hide hatches;
- the volcano's mood, from quiet to smoking;
- the wind that steers fires;
- which stream runs clean (if the design keeps any clean);
- where the hedge maze opens.

### 1.9 The edge

- **North (L, book):** beyond the wood, the holly hedge maze guarded by ladybug mutts, then flat dry ground, then a sheer cliff of about 100 ft over a rocky canyon. In the canyon is the generator, under a force field that throws back anything thrown at it [17][23].
- **Ours (I):**
  - the hedge hollow at r 1,600;
  - flat dry ground to r 1,750;
  - the cliff Edge, a 107-stud drop;
  - the force field along the lip.

  At night a thin beam of light rises from the canyon. It is an unplaced IMAX shot used as a landmark (I).
- **Everywhere else (I):** ArenaV3's mountain wall. The owner wants the boundary to feel like "an actual technological containment system" (`owner/GameDesignDirection_2026-11-14.md` §2.4), so the force field's ripple shows anywhere the wall is touched.

### 1.10 Palette: sampled, then the semi-real tones

| Element | Sampled sRGB (frame) | Semi-real tone | Luma | Notes |
|---|---|---|---|---|
| Sky, zenith | #047fa6 (T1 @1.7 s); #168cb4 (owner frame) | #6892ba (104,146,186) | 140 | Skybox. About 40% less saturated than the grade |
| Sky, horizon | #7dafc5 (T1 @40.2 s); #76a2be (FE @37.4 s) | #b4c8d6 (180,200,214) | 197 | Skybox |
| Cumulus | #cedce3 (T1 @40.2 s) | #f6f6f8 (246,246,248) | 246 | `Terrain.Clouds.Color` |
| Low cloud bank, mist | #bdc9cd (T1 @1.7 s); #c3cdcf (owner) | #dee2e2 (222,226,226) | 225 | Particle sheets |
| Haze, far ridges | #6894a3 (T1 @1.7 s); #7098a7 (owner) | Atmosphere #ccd4da (204,212,218); far ridges read about #80929c | 211 | Atmosphere colour |
| Turf, the Heart | #59771b (T1 @1.7 s, between beds); #58721e | #5c7836 (92,120,54) | 109 | The fresher grass inside the ring |
| Meadow, the Iris | #6f8357, #5f7647 (T1 @1.7 s detail); #616e2d (SH @26.4 s) | #6a7c42 (106,124,66) | 116 | Olive spring green |
| Dry slope grass | #5f603b (FE @26.9 s); #868a5e (TVk @8.8 s) | #808050 (128,128,80) | 125 | Ridges and the outer Iris, like the set's hay |
| Conifer needles | #16343a (T1 @1.7 s); #263a37 (T2 @49.9 s) | #384c34 (56,76,52) | 70 | G 76: in ArtStyle's 55–80 band |
| Broadleaf clumps | #193132 (T1 @1.7 s); #293a30 (T2 @49.9 s) | #485a34 (72,90,52) | 83 | G 90: in the 65–95 band |
| Pine bark | #36323f (T2 @114.2 s, in shade) | #7c6050 (124,96,80) | 101 | Pinkish and warm; red minus blue is 44 |
| Beech bark | none sampled | #7a705e (122,112,94) | 113 | Mean 109 |
| Forest floor | none sampled | #645642 (100,86,66) | 88 | In the 80–95 band |
| Gorse flowers | #a99a35 (T2 @114.2 s) | #ccb042 (204,176,66) | 174 | On a bush body of #3e4e2a |
| Heather | #753c4c (FE @37.4 s); #886070 (T2 @54.2 s) | #845470 (132,84,112) | 96 | Muted magenta-purple |
| Pink heather | #d9a595 (FE @64.4 s) | #b6808a (182,128,138) | 140 | |
| Spoke: buttercup yellow | #b4a844 (T1 @1.7 s detail); sunlit #d6cb7b | #ccb448 (204,180,72) | 177 | Signal: kept moderately saturated |
| Spoke: poppy red | #954853 (T1 @1.7 s detail); sunlit #c58782 | #b24644 (178,70,68) | 93 | Signal |
| Spoke: rose pink | #a67e8e (T1 @1.7 s detail); sunlit #d4afb9 | #c68e9c (198,142,156) | 155 | Signal |
| Spoke: lavender | #6d7c91 (T1 @1.7 s detail); sunlit #8599ae | #888ab8 (136,138,184) | 141 | Signal |
| Spoke: magenta | #866576 (T2 @43.9 s) | #9e567e (158,86,126) | 104 | Signal |
| Teardrop: periwinkle and white | #65889b (T1 @1.7 s); #6993b7 (T2 @49.9 s) | #7c98c6 (124,152,198), flecked #dad8cc | 149 | Signal |
| Teardrop: marigold | #ba9226 (T2 @49.9 s) | #d4983c (212,152,60) | 158 | Signal |
| Crimson spiral | #67242b (T2 @55.9 s) | #962c38 (150,44,56) | 67 | Signal |
| Bed foliage | none sampled | #42582e (66,88,46) | 80 | Under the flower heads |
| Holly hedge | #272a22 (TVk @8.8 s) | #34482e (52,72,46) | 66 | G 72 |
| Limestone crags | #b4a697 sunlit (FE @37.4 s); #b5c0a3 (FE @64.4 s); shaded #507886 (T2 @54.2 s) | #9c988c (156,152,140) | 152 | Above ArtStyle's stone band on purpose: the region's pale limestone must read from 1 km away. Check it for glare at 14:00. |
| White boulders | #d6d7cf (FE @64.4 s) | #a4a298 (164,162,152) | 162 | Above the stone band, like the crags; check for glare |
| Tan scree | #7a665c (T2 @135.4 s) | #8c7c68 (140,124,104) | 126 | |
| Dark rock (canyon, peak core) | #5e6266 (T2 @135.4 s) | #6c6a64 (108,106,100) | 106 | |
| Stream pebbles | none sampled | #7e786a (126,120,106) | 120 | Path band |
| Lake water | #205255 (T2 @54.2 s); #1e4b59 (SH @26.4 s) | `WaterColor` #285e64 (40,94,100); Transparency 0.6, Reflectance 0.6 | 83 | One water look per map |
| Horn, outer sails | #428298 lit, #1c657d shade (T1 @40.2 s, graded teal); set photo white | #d0d2ce (208,210,206) | 209 | Matte paint, roughness 0.8 |
| Horn, inner faces | #17273e (T1 @40.2 s); #3a424d (T2 @49.9 s); set photo plum | #4a3c5c (74,60,92) | 65 | Plum-navy, a dark accent |
| Horn, gold edges and battens | #6f5722 (T1 @40.2 s); #6b4c23 (T2 @49.9 s) | #b48e4a (180,142,74) | 145 | Satin metal: metalness 0.7, roughness 0.45 |
| Platform cladding | #42514c face in shade (T1 @40.2 s); sunlit #d2c29d | #beb292 (190,178,146) | 178 | Cream stone panels |
| Platform glass band | #0c748d (T1 @40.2 s) | #467880 (70,120,128) | 110 | Glass, roughness 0.2 |
| Bronze steps and thresholds | #252d2c (T1 @40.2 s) | #786040 (120,96,64) | 99 | Aged bronze |
| Horn floor | #877d66 (T2 @49.9 s) | #b8ae94 (184,174,148) | 174 | |
| Plinth sides | #c5b8a4 (FE @37.4 s, warm grade); #1f353c from the air | #969896 (150,152,150) | 151 | Brushed steel: metalness 0.8, roughness 0.45 |
| Plinth top plate | #c8833c (FE @37.4 s) | #b07046 (176,112,70) | 123 | Polished copper. A signal: "your start" |
| Tube rim | #786040 (T1 @129.2 s) | #96784e (150,120,78) | 123 | Brass, flush with the turf |

### 1.11 In style A: elements, terrain and meshes

**Elements**

| Element | Size (studs) | Facets | Colour | Triangles |
|---|---|---|---|---|
| Horn sails (6) | inner 50 tall, outer 36; skirts 20–26 wide | Each sail is 6–10 long triangular facets fanning from the base, 2–4 studs wide there, with 0.15-stud chamfered seams; gold edge strips 0.4 wide | sails, inner faces, gold (§1.10) | ≤ 4.5k per pair |
| Horn interior | 36 across | Panels 2–3 studs; battens 0.3 × 0.3 fanning from quarter-circle plates at the base; weapon racks are props | inner faces, gold, floor | ≤ 4k |
| Platform (star) | 100 across the points, 6 high | Panels 6 × 3 with 0.15 joints; chamfer 0.1 | cladding, band, bronze | ≤ 4k |
| Plinth and tube rim (×48) | drum 4.3 across, 1.6 tall; rim 8.4 across | 16-sided drum (facets about 0.85); 24-sided rim | steel, copper, brass | ~500 each, with one shared mesh |
| Flower spokes (15) and teardrops (6) | 55–75 × 9 × 1.5; teardrops 30 × 12 and 22 × 10 | A mound of 1–2-stud facets painted in the flower colour, with faceted flower heads of 0.3–0.6 studs along the crest and edges; no cards | §1.10 | 2.5–3.5k each, plus a far mesh of about 300 |
| Fuse daisy | 1.2 across | Item-class facets 0.1–0.4 | yellow, copper | ~300 |
| Crimson spiral | 50 across, hedges 4 × 2.5 | Hedge blocks with 0.5–1-stud facets, flower heads painted on | crimson, bed foliage | ≤ 6k in two parts |
| Holly hedge kit | modules 16 tall, 5 thick, 12 long | 0.8–1.5-stud facets; berries as 0.3-stud lumps | hedge green, red berries | ≤ 1.5k per module |
| Conifers and broadleaf trees | ArtStyle sizes | ArtStyle rules 2–3 | §1.10 | 3–5k, plus a far mesh |
| Gorse, heather, bracken, wildflowers | as in §1.5 | 0.3–1-stud facets | §1.10 | 200–900 |
| Limestone crags and boulders | crag modules up to 120 tall; boulders 2–8 | Jointed blocks with bedding planes; cliffs 2–6-stud facets, rocks 0.5–1.5 | limestone, boulders | cliffs ≤ 4k; boulders 150–400 |
| Berms with plaques | 6–10 across, 1.5 high | as the spokes; the plaque is a 0.8 × 0.5 brass prop | flower colour, brass | ≤ 1.5k |
| Mutts and animals | squirrels 1.2–1.5; birds 4–5 tall; porcupine about 8 long | ArtStyle creature rules: few bones, one wrong trait each | §1.8 | 300–3k |

**Terrain materials.** These use Expanded Terrain's tinted slots, as ArenaV3 §7.1 plans: about 12 sets, and each slot's base material decides its footsteps.

| Ground | Base material | Tint target (rendered mean) |
|---|---|---|
| Heart turf | Grass, slot "turf" | #5c7836 |
| Iris meadow | Grass, slot "meadow" | #6a7c42 |
| Dry slopes and ridge grass | Grass, slot "dry" | #808050 |
| Forest floor (needle litter) | LeafyGrass | luma 80–95, about #645642 |
| Paths and bare earth | Ground | ArtStyle path band |
| Stream beds | Salt (the river-pebble variant) | #7e786a |
| Lake and stream margins | Mud | ArenaV3's wet peat |
| Crags, ridges, boulder fields | Limestone | #9c988c |
| Cliff faces, canyon, the peak's core | Rock | #6c6a64 |
| Tan scree | Basalt, scree slot tinted tan (Basalt stays reserved for scree) | #8c7c68 |
| Water | Water | `WaterColor` #285e64 |

There is no snow (the film shows none) and no CrackedLava on visible slopes. The eruption is effects plus a glassy crust mesh.

**What must be Blender meshes:**
- the horn (sails, interior, racks) and the star platform with its steps;
- the plinth, the tube rim and the fuse daisy;
- the flower spokes, teardrops and berms with their plaques;
- the crimson spiral, the hedge kit, and the flower-sun glade's beds;
- every tree, bush, heather mat, bracken frond and wildflower clump;
- the limestone crag, boulder and peak modules (the peak is too thin for terrain, as ArenaV3 §7.1 rules);
- the lava crust;
- the hovercraft wreck;
- every animal and mutt.

**What terrain carries:** the ground everywhere, the lake and streams, the scree fans, and the ridge and mountain masses under the crag meshes.

**Build note.** TerrainGen's fixed plaza inputs (ArenaV3 §7.1, "Fixed inputs") change for Map 1:
- 48 plates at r 120 (was 24 at r 52);
- the turf disc r 150 (was 62);
- the protected disc moves out to about r 170–210.

The Countdown's plate code reads these values (GameDesign §4, §11).

---

## 2. The launch sequence (before both maps)

### 2.1 What the film shows

The owner's frames all come from T1 (C, research pass):

| Frame | Time | Owner frame |
|---|---|---|
| Red room A | T1 @120.2 s | `owner\launch_1_red_room_net_a.png` |
| Red room B | T1 @122.7 s | `owner\launch_1_red_room_net_b.png` |
| Pole hall, wide | T1 @124.7 s | `owner\launch_3_pole_hall_wide.png` |
| Glass cases | T1 @125.9 s | `owner\launch_2_glass_cases.png` |
| The rise | T1 @127.2 s | `owner\launch_3_pole_rise.png` |

- **The red room (C).**
  - Looking straight down through a hexagonal frame of square teal steel tube with bolted joints, about 4 m across the flats.
  - Below is a narrow oxblood room with thin red vertical rails.
  - Outside the hexagon, a dark square-mesh net (cells about 0.3–0.4 m) is stretched over red surfaces, and a pink round disc lies on the floor (T1 @120.2 s; T2 @101.7 s).
- **The steel deck (C).**
  - Blue-grey painted steel plate with large black floor grates (about 2 × 1.2 m), white border stripes, and red mesh under the grates.
  - Waist-high red tubular rails, red lamp housings with white lights, grey concrete walls and steps.
  - A guard in white armour with a rifle, another on an upper walkway, and a dark cavernous ceiling (T1 @122.7 s; T2 @102.8 s).
- **The hall of glass cases (C).**
  - A dim navy hall with rows of white linear ceiling lights.
  - Tall glass cases about 3 m tall and 1.2 m wide, framed by square oxblood posts.
  - Each tribute stands on a round dark-red disc on a post, with a maroon wall unit and a white light panel nearby (T1 @125.9 s; T2 @133.3 s).
- **The pole hall (C, with sizes L).**
  - A giant dark round hall, estimated 80–120 m across and 30–40 m high.
  - The ceiling holds a huge spoked ring (40–64 spokes, about 50–60 m across) with a dark hub ringed by about 12 spotlights, concentric rings of LED bars and a steel truss dome.
  - Thin poles run from floor to ceiling, one per tribute, and tributes ride small discs up them.
  - The floor is a ring of red and white wedges (T1 @124.7 s; T2 @133.9 s).
  - A ring of tall grey booths with dark niches stands round the floor, with the poles rising behind them (C, SH @16.4 s). So the glass-case ring probably stands at the poles' feet (L).
- **The location of the rise** was Berlin's Velodrom, a round hall under a 142 m steel truss roof (L [32][33][34][35]).
  - The film shows all the tributes rising from one shared room, unlike the book's separate tubes (L [14]).
  - The rise is the IMAX moment: the picture opens to full height as they rise (L [12][11]).
- **The arrival (C).** A straight-down shot of the tribute rising out of the brass-rimmed tube into sunlit grass (T1 @128.2–129.7 s).
- **The order.** The trailers cut red room, steel room, pole hall, glass cases, rise, grass. The film's true order is not shown. We follow the owner's order: red room, then glass cases, then the rise.
- **Caution** (from a student write-up [15], unverified). Red room A shows a Capitol woman looking up through the hexagon, and the write-up places her on a stand at the reaping. That frame may not be the launch at all. We follow the owner's reading anyway: the red room with the metal on top is the transition room. Red room B, the tribute in his launch cape on the steel deck, does fit a pre-launch room.
- **The book (L [21][31]).** A hovercraft lands the tributes inside the arena's underground. They change into arena clothes in launch rooms, stand on a metal plate, a tube closes round them and they rise into blinding sunlight.

### 2.2 Layout: one vertical set

Everything is one continuous set, so the camera can take it as one shot (I). It sits outside the map or deep under it, and the cut into the arena hides in the whiteout at the top.

```
  ARENA        plate rises out of its tube (Map 1: brass rim in the meadow; Map 2: the lagoon)      y   0
  ────────────────────────────────────────────── whiteout ─────────────────────────────────────
               ceiling of the pole hall: the spoked ring, one aperture over every pole              y −20
     ║    ║    ║    ║    ║    ║    ║    ║    ║          the poles (one per contender), 120 studs of rise
     ║    ║    ║    ║    ║    ║    ║    ║    ║          the pole hall: 360 across, 130 tall
   [▯]  [▯]  [▯]  [▯]  [▯]  [▯]  [▯]  [▯]  [▯]          the ring of glass cases on the walkway level (r 110)
  ─┴────┴────┴────┴────┴────┴────┴────┴────┴──────     walkway level                                y −150
       ┴  the hexagonal tube (14 across the flats)
    ┌─────┐
    │ RED │  the red room: oxblood walls, net ceiling, steel deck, red rails (one per contender)        y −190
    └─────┘
```

### 2.3 The red room (the transition room, while the map loads)

- **Look (C).** Oxblood walls; a ceiling of dark square-mesh net over red panels; the teal hexagonal tube mouth in the ceiling; a blue-grey steel deck with black grates and white stripes; red mesh glowing under the grates; red rails round your spot; red lamp housings with white lights; a guard on the upper walkway.
- **Ours (I):**
  - a room 30 × 24 studs, 20 high to the net;
  - the hex tube 14 studs across the flats, with bolted plates;
  - net cells 1.2 studs, with bars of 0.25 (the smallest size ArtStyle allows);
  - grates 7 × 4.3 studs;
  - rails 3.6 studs high, 0.55 across;
  - lamp housings 2 studs;
  - your floor disc 7.2 studs across in dusty rose, the same size as the arena's plate tube.
- **Who is in it.** Each player sees their own room, client-local: themselves, a guard and an intercom.
  - Another player's room is never visible.
  - The room loops calmly for as long as the map takes to load. That is the owner's "it loads up to the room".

### 2.4 The hall of glass cases

- **Look (C):** the navy hall, white strip lights, oxblood posts, glass with grey reflections, a dark red disc on a post in each case, a maroon wall unit.
- **Ours (I):**
  - the cases form a ring at the foot of the pole hall: 48 cases at r 110, about 14.4 studs apart (24 in use in a standard round);
  - a curved walkway runs in front of them, with linear lights overhead;
  - each case is 4.3 wide and 11 tall: oxblood posts 0.8 × 0.8 studs, glass panes, and a disc 3.6 across on a post;
  - the other players stand in their own cases. This is the film's frame: a row of tributes in cases along a walkway (C).

### 2.5 The pole hall and the rise

- **Ours (I):**
  - the hall is 360 studs across (100 m) and 130 tall;
  - the spoked ring is 190 across with 48 spokes. Its hub is 40 across, with 12 spotlights aimed down;
  - concentric LED bars run at r 60, 95, 130 and 165, under a truss dome;
  - each pole is 1 stud across and 12-sided, with an edge-lit strip and copper bands. The poles run from the case tops to the ceiling;
  - the floor ring between the cases and the outer wall (r 120–180) is wedges of oxblood and pale grey, sloping up like a banked track. The wedges are C; the slope is I, after the Velodrom.
- **The rise:** 120 studs in about 9 s. The disc carries you out of the top of your case and up the pole toward an aperture in the ring.
- **The camera: one shot with circular motion (I, the owner's ask).** The film's own camera is static or pushes in slowly (C, T1 @126.7–127.7 s); the circling is our addition.
  1. **The red room:** straight down through the hex tube, pushing in slowly (the film's framing). This loops while the map loads.
  2. **Up the tube:** the deck plate lifts and the camera rises ahead of you up the tube, with teal ribs passing (about 3 s).
  3. **The cases:** you arrive in your glass case. The camera pulls out through the glass and sweeps along the curving row of cases (about 4 s).
  4. **The rise:** the disc rides the pole. The camera circles 270° round you and climbs with you, with the spoked ring overhead and light bars streaming past (about 8 s).
  5. **The whiteout:** light floods the aperture (about 1 s).
  6. **The arrival:** in the arena, your plate rises out of its tube. The camera finishes its circle and settles behind your head facing the horn (about 3 s). Then first person.

### 2.6 The arrival on each map

| Map | You come up through | It looks like | Tag |
|---|---|---|---|
| Map 1 | A brass-rimmed tube in the turf, onto your plinth | The straight-down shot of T1 @129.2 s: dandelions, daisies and long morning shadows | C |
| Map 2 | The lagoon: your plate surfaces with spray, between two rock spokes | The Catching Fire still of Katniss rising in the water with a causeway behind her; plates standing in the water in the concept art | C |

### 2.7 Light

The darkness of these spaces comes from the lighting, never the paint (I). The set holds no plants, no water and no hazards, and its only sky is the whiteout at the top.

| Space | Ambient | Lights | Exposure | Other |
|---|---|---|---|---|
| Red room | about (30,18,20) | One cool white key falling through the hex tube; red uplight from under the grates; white lamps in the red housings | +0.2 | — |
| Glass cases | navy, about (24,34,48) | SurfaceLights on the light-bar meshes; a soft white top-light in each case | — | — |
| Pole hall | near black, about (12,16,24) | The 12 hub spots aimed down; emissive LED rings; the poles' edge strips; a key that rides up with each rider | +0.3, so a rider stays readable | Bloom threshold 1.4 so the bars glow |

### 2.8 Palette: sampled, then the semi-real tones

| Element | Sampled sRGB (frame) | Semi-real tone | Luma | Notes |
|---|---|---|---|---|
| Oxblood walls and net backing | #281616 (owner A); #271717 (T1 @120.7 s) | #702e2e (112,46,46) | 60 | Dark accent |
| Net and grating | #1d4250 (owner A) | #3e5256 (62,82,86) | 78 | Dark teal-grey steel |
| Hexagonal tube frame | #205766 (owner A); #1e5664 (T1 @120.7 s) | #42727a (66,114,122) | 104 | Painted steel, bolted plates |
| Floor disc | #5c4d5a (owner A) | #966068 (150,96,104) | 108 | Dusty rose |
| Steel deck plate | #205169 (owner B, graded); #7e919e (research) | #788288 (120,130,136) | 128 | Painted steel |
| Floor grates | #031a2a (owner B); #081d2b (T1 @122.7 s) | #2c2e30 (44,46,48) | 46 | Reads black over the void |
| Red mesh under the grates | #1c1015 (owner B) | #78282a (120,40,42) | 57 | Lit from below |
| Red rails | #592a38 (owner B); #492531 (T1 @122.7 s); #4d252b (T2 @102.8 s) | #9c3032 (156,48,50) | 71 | Painted steel tube |
| White stripes | #697c87 (T1 @122.7 s, graded) | #cecec8 (206,206,200) | 206 | |
| Lamp housings | #582d3b (owner B) | #962e30 (150,46,48), emitters (245,240,232) | 68 | |
| Concrete walls and steps | #2a3945 (T2 @102.8 s, graded) | #7e7e7a (126,126,122) | 126 | |
| Glass hall shell | #123a4f (owner); #172e3d (T1 @125.9 s) | #36404e (54,64,78) | 63 | |
| Case posts | #4b353c (owner, red pixels); #442b2e (T2 @133.3 s) | #6e363c (110,54,60) | 66 | |
| Case discs | #452e30 (T2 @133.3 s) | #7e3236 (126,50,54) | 66 | |
| Case glass | #062a3d (owner, a reflection) | Glass tinted #c4d2d6 (196,210,214), Transparency 0.65, Reflectance 0.2 | — | |
| Light bars and panels | #dfe6ed (owner glass hall); #e2e6e9 (owner pole hall) | emissive #ecf0f4 (236,240,244) | — | The only Neon-like parts |
| Pole hall shell | #143040 (owner wide); #080d13 (owner rise) | #3a424e (58,66,78) | 65 | |
| Spoked ring and truss | #0d2132 (owner wide) | #606872 (96,104,114) | 103 | Edges catch the spots |
| Poles | none sampled (steel to copper, edge-lit) | steel #a4a6a8 (164,166,168); copper bands #b07046 | 166 | Metal |
| Floor wedges | red #5d403e, pale #8c9498 (T2 @133.9 s) | #7c3636 (124,54,54) and #b0b2b0 (176,178,176) | 69 / 177 | |
| Booths and cases from the hall | #576264 (T2 @133.9 s) | #7c8080 (124,128,128) | 127 | |
| Rider's disc rim | #0d141b (owner rise, graded) | #6e2c30 (110,44,48) | 58 | |
| Launch cape (optional cosmetic) | #7b8790 (owner rise, a white cloak in blue light) | white #d8d8d4 with trim #343e52 | 216 / 61 | White hooded capes with dark trim (C); sleeves in district colours (C, T2 @133.3 s) |

### 2.9 In style A, and what must be meshes

There is no terrain here: every surface is a Blender mesh. Built pieces are chamfered prisms with 1–2.5-stud facets for the architecture, 0.3–1 for props, and painted colour with an AO floor (ArtStyle rules 2–5). Metal is used only on the poles, rails, deck plate and bolts; glass only on the cases.

| Kit | Pieces | Triangles |
|---|---|---|
| Red room | walls, net ceiling (two parts), hex tube with bolts, deck tiles, grates, rails, lamp housings, upper walkway, guard (a shared NPC) | ≤ 10k for the room, net ≤ 2 × 4k |
| Glass case | posts, panes, the disc on its post, header light | ≤ 1.5k, one mesh reused 48 times |
| Pole hall | 8 identical 45° wall and floor segments, the ring and hub, LED ring meshes, the truss dome in 8 segments, a pole (one mesh) | each module ≤ 5k |
| The arrival | the tube rim (Map 1); the plate's water collar (Map 2) | ≤ 1k |

---

## 3. Map 2: the clock arena at 3×

### 3.1 What we have to go on

- **The new film shows no clock or sectors.** No *Sunrise on the Reaping* trailer, spot or short does (C, research pass). Map 2 comes from *Catching Fire* material and the book.
- **The owner's reference** is `owner\map2_clock_arena_reference.png`, the "sector trap overview".
  - It shows 12 wedges like a clock face round a saltwater lagoon, the island, spokes, a beach ring and jungle, with a trap by sector.
  - It is a fan-made, book-based guide of the same kind as the "75th Hunger Games Arena Visual Guide" (L [41][47]).
- **The real set** was "The Beach" at Clayton County International Park, Jonesboro, Georgia (C, satellite view `web\map2_film_set_satellite_lagoon_jonesboro.png` [41][42]).
  - A round green lagoon sits inside a sand ring, with an island ringed by dark rocks holding the horn.
  - Only 3 rock causeways were built (at about 11, 12 and 6 o'clock); the other spokes are visual effects (C).
- **The jungle and beaches** were shot on Oahu, Hawaii (L [43]; [44] is unverified).
- **The horn as filmed** is long, splayed grey metal girders on dark rock against a palm jungle (C, `web\map2_film_still_cornucopia_girders_jungle.png` [16]).
  - The concept art is a cluster of faceted silver-grey shards on a black lava-rock island with surf, and plates standing in the water (C, `web\map2_concept_art_cornucopia_faceted.png` [16]). It is very close to our style A.
- **The book's clock** (L [45][46]):
  - 12 is lightning striking the tree at noon and midnight;
  - 1 is blood rain;
  - 2 is fog;
  - monkeys come at 3 or 4, depending on the source;
  - jabberjays come at about 4;
  - 10 is the wave;
  - the horn's tail points to 12.

### 3.2 Size: what "3×" means, and my recommendation

**Measured on the owner's reference, with its own scale bar** (`arenas_v5\text_research\clock_measure_overlay.png` and my re-measurement):
- The scale bar gives 1 km = 345 px. Its zero sits about 21 px off the left edge of the crop, and the mile bar agrees.
- The arena disc's radius is about 250 px, so the arena is **about 1.45 km across**, not 1 km.
- The lagoon water's radius is about 88 px (0.35 of the arena's radius), so the water is **about 0.5 km across**.
- The beach runs out to about 105 px (0.42 R).
- The fan guide is a fan estimate, not a film measurement (L [41]).

**The real set.** The satellite view has no scale bar. Judging by the trucks parked beside the lagoon (about 0.28–0.35 m per pixel), the built lagoon is **roughly 120–170 m across**. This is a rough estimate (I, ±25%).

| Reading of "3× the film arena" | Arena across | R (studs) | Area vs Map 1 | Verdict |
|---|---|---|---|---|
| The plan's figure (the disc as "about 1 km") × 3 | 3.0 km | 5,360 | 8.9× | Breaks ArenaV3's budgets. The jungle would have to be 1/9 as dense, and an average of 24 rivals is about 1 km apart. |
| The measured fan guide (1.45 km) × 3 | 4.35 km | 7,770 | 18.6× | Not buildable on Roblox at our quality |
| **3× the real set's lagoon, which equals the fan guide at its own scale** | **1.46 km** | **2,600** | **2.1×** | **Recommended.** 3 × 120–170 m is a lagoon of 360–510 m; the fan guide's lagoon is about 500 m. This is the film arena at 3× and the reference's own proportions. |

**Why 2,600 works, and what it costs** (I):
- **Ground at the start.** The plates sit near the centre, so the streamed disc at the start is mostly water. The binding case moves to the beach.
- **Scatter.** The jungle ring is 1.7× Map 1's whole area. To stay under ArenaV3's 90k-model server cap, the jungle uses fewer, bigger pieces (giant canopy trees and palms) at about 0.85× Map 1's average density, with ground cover scattered on each client (ArenaV3 §7.5).
- **Grids.** The fine grid grows to about ±2,750, which doubles ArenaV3 §7.1's ~100 MB of buffers. The coarse grid grows to ±3,550, and generation time roughly doubles (§7.3).
- **The border.** The stage radii scale by 2,600 / 1,800 = 1.44. Stage 1 then sweeps about 1,080 studs on the side away from the drift, so it needs about 170 s (or a smaller drift) to hold ArenaV3 §6.5's 6.5 studs/s limit.

### 3.3 Shape, regions and heights

Sizes are given as fractions of the arena radius R, with studs at R = 2,600. The water level is 34.

| Region | Where | Size and heights | What is there | Tag |
|---|---|---|---|---|
| **The island** | centre, r 0–0.045R (0–120) | Black lava rock 6–10 above the water, ringed by tumbled rocks and surf | The horn, its mouth open toward 6 o'clock and its tail pointing to 12 | C (island), L (tail to 12) |
| **The plates** | r 0.08R (210) | 24 plates, 2 per wedge, at a quarter and three-quarters of the wedge's arc; the nearest spoke is about 27 studs away (a 4 s swim) | Plates surfacing in deep water | C (plates in the water), I (numbers) |
| **The lagoon** | r 0–0.35R (0–910) | Salt water; 24 deep (6.7 m) in the middle, shelving to 2–4 over a sand bed near the beach | Green-teal water, swell, surf on the island rocks | C (look), L (salt) |
| **The 12 spokes** | the island to the beach, at the 12 clock bearings (12 at 0°, 3 at 90°) | 790 long, 10 wide, 1–2 above the water; tumbled basalt blocks with a walkable top | Low rock causeways, washed by waves | C (three built, in the satellite view), L (all twelve, the rest added in visual effects [42]), I (size) |
| **The beach ring** | r 0.35–0.42R (910–1,090) | Sand from 34 to 40; each spoke lands on a low rock spur | White sand, driftwood, beach grass at the top edge | C |
| **The jungle** | r 0.42R–R (1,090–2,600) | Climbs from 40 at the beach to about 120 at 0.6R and about 260 at the rim; folds and ravines | Dense palms, broadleaf canopy, tree ferns, big-leaf understory, lianas | C (the palm jungle in the film still), I (heights) |
| **The sector lines** | the 12 radial lines (at 15°, 45°, …) | Dry stony gullies running from the rim to the beach | Lets players read where one wedge ends and the next begins | I |
| **The lightning tree** | 12 o'clock, r 0.47R (1,220) | 180 tall, the tallest tree in the arena | Bleached and split by strikes | L (the tree in sector 12), I (place, size) |
| **The rim** | r = R | Jungle meets the force field. The dome rises overhead, and the jungle seems to go on beyond it | The edge | L (book; the fan guide's dome section), I (the jungle beyond) |

### 3.4 The horn and the island

- **Film (C).** Splayed grey girders on dark rock, low and long. The concept art has faceted silver shards like a broken crystal.
- **Ours (I).**
  - A cluster of 10–14 long, faceted steel shards splaying out from the centre: 40 tall at the mouth and 90 long, with the tail to 12 and the mouth to 6.
  - Each shard is a 4–6-sided prism with 2–4-stud facets and chamfered edges.
  - Inside are racks and crates on a stepped basalt floor.
  - The island rock is jointed basalt blocks (cliff-class facets of 2–6), with surf particles round its rim.

### 3.5 Plants, water, sky and light

- **Plants.** All are style A, with no cards anywhere: fronds are folded faceted strips.

  | Plant | Size (studs) | Tag |
  |---|---|---|
  | Coconut palms with curved, ringed trunks | 35–60 | C, film still |
  | Broadleaf canopy giants | 60–90; the lightning tree 180 | I |
  | Tree ferns | 10–20 | I |
  | Big-leaf understory, leaves 3–5 studs across | — | I |
  | Lianas as faceted ropes | — | I |
  | Beach grass and low shrubs on the beach's top edge | — | I |

- **Water (L [47]).** The lagoon is salt: the fan guide names a saltwater wave, and the fog washes off in salt water. Where fresh water comes from is a game design decision.
- **Sky (I).** A tropical, humid day:
  - zenith #7098be, horizon #c4d0d4;
  - Atmosphere Density 0.36, Color #d2d6ce;
  - towering cumulus;
  - a pink dusk like the concept art, softened to about (214,176,176).
- **Night (I).** The dome's projected stars.
- **The sector storms (I).** Local cloud decks (mesh plus particles) at about 400 studs over a single wedge.

### 3.6 The twelve sectors

At R = 2,600 a wedge is about 570 studs wide at the beach and 1,360 at the rim. A sector event fills its wedge from the rim to the beach, with a sharp radial edge you can see from outside. Particles are spawned near players only.

| Hour | Hazard | Source | How it looks in our style | Tag |
|---|---|---|---|---|
| 12 | Lightning strikes the tallest tree at noon and midnight | book; fan guide | A black cloud deck and rain over the wedge, blue-white bolts (224,232,255) hitting the lightning tree, thunder | L |
| 1 | Blood rain | book; fan guide ("heavy, choking downpour") | Thick dark red rain (112,28,30) that stains surfaces rust-red while it falls; no pools or gore (13+). Fallback: rust rain | L |
| 2 | Poison fog | book; fan guide (it withers limbs, reaches the beach, and salt water purges it) | A wall of milky fog (224,226,214) rolling down from the rim to the beach, with a faint sick-yellow edge | L |
| 3 | Monkey mutts | fan guide (passive until triggered; sharp teeth); book | A troop of 20–40 faceted monkeys, 3–4 studs, orange-brown (150,92,52), waiting in the canopy | L |
| 4 | Jabberjays | fan guide (a transparent barrier keeps you in; the birds mimic a loved one's cries); book | Dark grey birds (64,66,72) with a blue sheen; the wedge's edges shimmer as the barrier rises | L |
| 5 | (not encountered) | fan guide "?" | Ours: **sinking sand.** The beach and gullies turn to sucking mud; the sand darkens and bubbles | I |
| 6 | A beast | fan guide: guessed from what was left | Ours: never fully seen. Flattened undergrowth, claw-scored trunks, heavy breathing in the fog; no remains (13+) | L (exists), I (look) |
| 7 | (not encountered) | fan guide "?" | Ours: **the heat lamp.** The sky over the wedge goes white-hot with heat shimmer; shade and water matter | I |
| 8 | (not encountered) | fan guide "?" | Ours: **falling timber.** Nuts and branches rain down, then trees topple across the paths | I |
| 9 | (not encountered) | fan guide "?" | Ours: **the crab tide.** Engineered land crabs, 1–2 studs, pour up from the water across the beach and up the wedge | I |
| 10 | The wave | book; fan guide (it fills the sector and washes out to the beach) | A wall of water 60–80 studs high sweeps down the wedge, the lagoon surges, and the island and spokes flood for a moment | L |
| 11 | Insects | fan guide ("assumed deadly"; only buzzing and clicking were heard) | Mostly sound: clouds of dark insects in the canopy, clicking. Ours: they swarm whoever stays | L, I |
| Edge | The force field | book; the fan guide's dome section | Invisible until touched, then a hexagonal ripple. Ours: a faint wavering square shows to a sharp eye, a weak point to find | L, I |
| Centre | Ours: the island turns | — | The island and the horn rotate to scramble bearings | I |

### 3.7 The edge

- **Book and fan guide (L).** The force field is a dome; the fan guide draws it in cross-section. It ends the jungle at the edge, and the jungle seems to go on beyond it.
- **Ours (I).**
  - The rim terrain carries on as visual-only jungle for 300 studs beyond the field, behind the Boundary.
  - The dome is invisible against the sky except for a ripple when touched.
  - ArenaV3's wall step isn't needed here: the field is the wall, backed by the invisible Boundary.

### 3.8 Palette: sampled, then the semi-real tones

| Element | Sampled sRGB (frame) | Semi-real tone | Luma | Notes |
|---|---|---|---|---|
| Lagoon water | #67a4a7 (owner guide); #617777 (satellite); #344852 (concept, shallows) | `WaterColor` #266260 (38,98,96); Transparency 0.55, Reflectance 0.6 | 85 | Green-teal |
| Beach sand | #e1dcca (satellite); #c4d0c5 (owner guide) | #c6bca0 (198,188,160); wet margin #968c74 | 188 | |
| Lava rock (island, spokes) | #333439 (satellite); #2d2f2c (film still); #110f0f (concept) | #605c58 (96,92,88) | 93 | Below ArtStyle's stone band on purpose, as the dark identity rock; never darker |
| Horn shards | #c7c4bd (film still girders); #969493 (concept) | #acaeae (172,174,174) | 174 | Brushed steel: metalness 0.85, roughness 0.4 |
| Palm fronds | #56573f (film still) | #4c5c34 (76,92,52) | 86 | G 92 |
| Canopy | #536040 (owner guide) | #405630 (64,86,48) | 79 | |
| Palm trunks | none sampled | #7e6e5a (126,110,90) | 112 | Bark band |
| Tree ferns | none sampled | #465e38 (70,94,56) | 86 | |
| Jungle floor | none sampled | #60543e (96,84,62) | 85 | Forest-floor band |
| Lightning tree | none sampled | #b0aa9c (176,170,156) | 170 | Bleached dead wood: a landmark, above the bark band on purpose |
| Surf and foam | #bdc1c4 (concept) | #e2e6e4 (226,230,228) | 229 | Particles |
| Sky | #bd9dac (concept, pink dusk) | day: zenith #7098be, horizon #c4d0d4; haze #d2d6ce | — | |
| Fog | none sampled | #e0e2d6 (224,226,214) | 225 | Hazard |
| Blood rain | none sampled | #701c1e (112,28,30) | 46 | Hazard; restrained |
| Monkeys / jabberjays | none sampled | #965c34 / #404248 | 101 / 66 | Creatures |

### 3.9 In style A: terrain and meshes

**Terrain materials**

| Ground | Base material | Notes |
|---|---|---|
| Lagoon and surge | Water | `WaterColor` #266260 |
| Beach and lagoon shelf | Sand | #c6bca0 |
| Island, rock ring, spoke bases, reef | Rock, a dark "lava" slot | Tinted to #605c58. Not on Basalt: a slot's base sets its footsteps, and Basalt stays reserved for scree (ArenaV3 §7.1) |
| Jungle floor | LeafyGrass | luma 80–95 |
| Wet gullies, the 5 o'clock sinking sand | Mud | Its look is a mesh overlay when it triggers |
| Rim cliffs and jungle outcrops | Rock | |
| Sector-line gullies | Salt (the pebble variant) | |

**What must be Blender meshes:**
- the horn's shards and its interior;
- the spoke tops (tumbled basalt modules, so the walkable top is clean);
- the island's rock ring;
- every palm, canopy giant, the lightning tree, tree fern, understory clump and liana;
- driftwood and beach shrubs;
- the plates and their water collars;
- the creatures (monkeys, jabberjays, crabs, the beast's tracks);
- the cloud decks and the wave (a mesh front plus particles).

**Triangle budgets.** As ArtStyle §6 rule 8: palms 3–4k with a far mesh, giants ≤ 12k, the horn ≤ 10k in parts under 5k.

---

## 4. The train and the station

### 4.1 What the film shows

**The station** (C: the owner frame `owner\train_station_owner_frame.png` is T1 @35.7 s; FE @29.0 s; T2 @62.2–64.2 s)
- **The view:** symmetrical, one point, down two platforms.
- **The ceiling:** in the foreground, a coffered concrete ceiling with round downlights, cut by a large oval opening.
- **The sculpture:** through the opening hangs a huge gold sculpture of about 8–10 long tapered blades fanning out like a sunburst.
- **The shed:** beyond is a long train shed with tall glazed walls of white steel mullions and stepped fins, glowing amber-pink from behind.
- **The sign:** a white cross-beam carries gold lettering. It is film text, never copied.
- **Location:** the Messe Berlin south entrance (L [32][33]). The training centre was shot next door in the ICC (L [32]).

**The trains** (C, T1 @35.7 s detail `trailer1_35.7s_detail_trains.png`)
- One dark bullet-nosed train at each platform.
- Glossy black bodies with deep maroon panels and thin gold pinstripes.
- A rounded capsule nose with a large round lamp housing and a glowing red-orange core.
- The nose is about 3–3.5 m tall, and the lamp 0.8–1 m across (L estimate).

**The dressing** (C)
- Narrow dark maroon-brown banners with pointed bottoms, each with a gold vertical arrow and a round gold emblem.
- Tall propaganda posters on the side walls.
- Black departure boards with white and amber rows.
- Rows of guards in white armour, black harnesses and white helmets.

**On the move** (C, T2 @24.7–26.7 s): at night, a long train with an amber strip of windows and a red-orange headlight crosses a tall twin-pylon cable-stayed bridge over a reservoir between dark hills.

**Inside the train** (C, FE @0.2–11.0 s and @75.8–77.6 s; TVn @12.9–18.6 s)
- Long benches in a bold retro geometric pattern: burgundy-brown with cream arcs and dots.
- Large round-cornered windows in thick polished brass frames.
- A curved ceiling of hammered, quilted cream-gold panels.
- Warm amber cove light, and wood and brass arches.

**The District 12 platform** (C, T2 @33.2 s): guards with black gas-mask visors and rifles beside a riveted slate-blue railcar with chains and a ladder, against weathered concrete.

**The book** (L [40]): Haymitch is carried aboard in handcuffs. There is a dining table with plates and silverware, a TV recap, and a forced birthday cake on camera. At the Capitol, a district's tributes step off in handcuffs, and the station is plastered with slogans.

**The owner's TRIBUTE spec §9** (`owner/TributeSpec_BloodAndMovement_2026-11-14.md`) asks for seven bullet-nosed, brushed-silver cars on magnetic levitation, a warm glow from every window at night, and the interior beats.
- The owner's later "make the trains look like them too" means **the film's black, maroon and gold replace brushed silver.**
- Everything else in §9 stays: the seven cars and their rooms, the maglev hum and sway, and the beats.

### 4.2 The station hall

All of this is ours (I), in the film's layout (C):
- **The hall:** 170 studs wide (48 m) and 420 long (118 m) in the part you walk, with the shed receding beyond as a cheap backdrop.
- **Across it, from west to east:**

  | Strip | Width (studs) |
  |---|---|
  | Glazed wall | — |
  | Guideway bay A | 22 |
  | Platform A | 30 |
  | Central concourse | 66 |
  | Platform B | 30 |
  | Guideway bay B | 22 |
  | Glazed wall | — |

- **The entrance end:** a coffered concrete ceiling 40 high, with coffers 12 studs square (ribs 1 stud, chamfered) and round downlights. It is cut by an oval opening 100 × 50.
- **The sculpture:** 10 gold blades, 40–70 studs long, fan down through the oval from the high roof at 80. They are tapered 5–6-sided prisms with 1.5–2.5-stud facets.
- **The shed walls:** 60 high. White mullions every 6 studs with stepped fins, and amber-pink light behind them (an emissive backdrop plus warm SurfaceLights).
- **The portal:** a white cross-beam 6 high at the shed's mouth. It carries our own sign or none: no film lettering.
- **Banners:** 5 × 18 studs, maroon-brown, with pointed bottoms, hanging in two rows down the concourse. Their gold motif is ours, never the film's arrow-and-roundel.
- **Boards:** departure boards 10 × 5 on posts, with our own text in white and amber.
- **Posters:** 14 × 24 on the side walls, with our own art, such as a heroic faceted guard. No film character, no film slogan.
- **Guards:** white-armoured NPCs (helmet, chest plate, black harness, black visor) standing in rows on both platforms. They are a faceted design of our own, with our own chest emblem.

### 4.3 The trains

- **Ours (I):**
  - 7 cars: the nose car is 90 studs long and the rest 80; each is 11.5 wide and 13 tall (3.6 m);
  - on a raised concrete guideway, with no wheels (spec §9);
  - the nose is a faceted capsule (1–2-stud facets) ending in a lamp housing 3.5 across: a gold-rimmed ring round a glowing core 2 across;
  - the body is lacquered black, with a maroon band along the flank and gold pinstripes of 0.25 studs;
  - the windows are round-cornered in brass frames and glow amber at night;
  - doors are 4 × 7.5.
- **Finish:** an exception to ArtStyle's matte rule. The black lacquer and maroon are semi-gloss (roughness 0.3, metalness 0.2), because a matte black train reads as a hole. Its shape comes from the station's reflections, as in the film.

### 4.4 The cars inside (spec §9, in the film's look)

The spec's rooms are the owner's own design, so they are tagged I (owner's spec). The materials come from the film's interiors (C).

| Car | Spec §9 | In the film's look | Tag |
|---|---|---|---|
| 1 Vestibule | brass handrails, pleated leather bench, a bud vase; a pneumatic door | the geometric upholstery; brass rails | I (spec), C (look) |
| 2 Dining | mahogany with silver filigree, white linen, crystal, a chandelier on a gimbal | hammered cream-gold ceiling panels, wood and brass arches. Plates and table runners carry our own motifs, not the Capitol seal or district crests, until names are decided | I, C |
| 3 Lounge | velvet club chairs, a globe drinks cabinet, a bolted piano, a propaganda screen (the only cool light) | oxblood velvet, brass, amber cove light; the screen's cool blue | I, C |
| 4 Corridor | narrow, brass fittings, patterned carpet, doors both sides | the round-cornered brass windows run along it | I, C |
| 5 Compartment | two bunks (silk and cotton), basin, chipped mirror, window seat, brass plaque | the upholstery on the window seat | I, C |
| 6 Observation | glass on three sides, curved bench; the districts pass outside | the night bridge (C, T2 @24.7 s); slag heaps and fences (spec) | I, C |
| 7 Guard | grey steel, four guards standing | the District 12 grey-steel look | I, C |

**Motion (spec §9):** a 1.5° roll and a 0.4-stud float on a slow sine, chandeliers and lamps swinging, and a 52 Hz hum.

### 4.5 Light

| Place | Light |
|---|---|
| Station | Warm amber key from the glazed walls; ColorShift_Top about (200,140,90); Ambient about (70,56,44); warm downlights. The amber-pink light behind the glass reads as a late-day sky |
| Train | Amber cove SurfaceLights, a warm chandelier PointLight that swings, and the cool blue screen in the lounge |
| Night journey | Moonlit blue outside and amber windows inside |

### 4.6 Palette: sampled, then the semi-real tones

| Element | Sampled sRGB (frame) | Semi-real tone | Luma | Notes |
|---|---|---|---|---|
| Coffered concrete | #333333 (T1 @35.7 s, in shade); #6b615f (research) | #948e86 (148,142,134) | 143 | Warm concrete |
| Gold blades | #8a6535 (T1 @35.7 s); #d29654, highlight #e7c19b (research) | #ba8e4e (186,142,78) | 147 | Brushed gold: metalness 0.9, roughness 0.3 |
| Glazing glow | #e9e3e0 (T1 @35.7 s) | backdrop #f8e8de (248,232,222) | — | Emissive |
| Mullions, fins, cross-beam | #897b6e (cross-beam in shade) | #d4d0c8 (212,208,200) | 208 | |
| Train body | #141115 (T1 @35.7 s detail) | #2e282c (46,40,44) | 42 | Lacquered black, semi-gloss |
| Train panels | #602d2d (T1 @35.7 s detail) | #702e30 (112,46,48) | 60 | Semi-gloss |
| Gold pinstripes | #92754f (T1 @35.7 s detail) | #b8925a (184,146,90) | 150 | |
| Nose lamp core | #b5442c (T1 @35.7 s detail); #a72c18 (research) | emissive #e85834 (232,88,52) | — | A light |
| Banners | #281c1a (T1 @35.7 s detail) | #58302e (88,48,46) | 56 | Fabric |
| Banner gold motif | #5f492c (T1 @35.7 s detail) | #b08a50 (176,138,80) | 142 | Our own motif |
| Guard armour | #968778 (T1 @35.7 s, warm light); #e5ccaa (research) | #d6d4ce (214,212,206); harness #303032 | 212 / 48 | |
| Departure boards | #2d2d2e (T1 @35.7 s) | #2c2c2e (44,44,46), with rows #e8e8e2 and #ecac4c | 44 | |
| Platform floor | none sampled | #6e6862 (110,104,98), roughness 0.4 | 105 | Polished stone |
| Upholstery | #26130c (FE @1.4 s) | #642e26 (100,46,38), motif #ceb48e | 57 / 183 | |
| Brass frames | #9d6130 (FE @1.4 s) | #b4844a (180,132,74) | 138 | Metal |
| Hammered ceiling | #cd9a76 (FE @3.8 s, lit) | #c6a67e (198,166,126) | 170 | Faceted panels: style A by nature |
| Wood arches and panelling | #6a3619, #875027 (research) | #84543c (132,84,60) | 92 | Wood band |
| District railcar | #324b5b (T2 @33.4 s) | #586874 (88,104,116) | 101 | Riveted steel |
| District concrete | #35393c (T2 @33.4 s) | #7e7c76 (126,124,118) | 124 | |

### 4.7 In style A, and what must be meshes

There is no terrain here, except a valley with a reservoir seen from the train at night, which can be a low backdrop.

**What must be Blender meshes:**
- **The station kit:** coffer modules, the oval opening ring, the 10 blades, mullion and fin modules, platform edges, the guideway, the cross-beam, banners, boards, posters as our own textures, benches and lamps. Each module is ≤ 5k.
- **The train:** the nose car and a body car, each ≤ 10k with every part under 5k, plus the shared interior kits per car.
- **The guard NPC.**
- **The bridge and reservoir backdrop.**
- **The District 12 railcar and platform.**

**IP: what we never copy** (owner's rule): the station lettering, the banner emblem, the posters' character and slogans, the departure-board text, the guards' chest emblem, the dining plates' seal and the district crests.

---

## 5. Appendix: the training centre (for the training-room brief)

**What the film shows** (C, T1 @79.2–83.2 s; `web\training_centre_gym.png`)
- A big gym with teal padded angled wall panels and white diagonal ribs.
- A blue-grey chequered carpet.
- Safety-orange equipment frames: spear racks, an orange cart with blue padded weapon trays, a white hoop wheel target and exercise bikes.
- Stacked colour-bar wayfinding signs and round ceiling downlights.
- Tributes in white training suits with district-colour trim; trainers in orange; guards at the back.
- It was shot in Berlin's ICC (L [32]).

**Ours (I):** equipment orange is the interactable signal (ArtStyle rule 9).

| Element | Sampled | Semi-real tone |
|---|---|---|
| Carpet | #4b636c (T1 @82.7 s) | chequered #68747a and #969ea2 |
| Wall panels | #43565e | #4e7076 |
| Equipment frames | #7f4924 | #c4682c |
| Ribs | — | #d6d6d0 |

---

## 6. What we couldn't confirm

- **Colour.** Every sample comes from compressed, graded streams. The semi-real tones are a judgement within ArtStyle's band, and they must be checked in game at 14:00 and 17:30 (ArtStyle rule 10). The interiors need their own lighting rigs.
- **The horn's real colours** come from a fan-account set photo (L). The plinths read differently in each source: pale steel and copper close up (FE @37.4 s), dark from the air, pale stone on set. Steel and copper is the closest view.
- **The launch rooms.**
  - Red room A may come from the reaping (a student write-up [15], unverified).
  - The film's order of the rooms isn't shown.
  - The glass-case ring sitting at the poles' feet is an inference from SH @16.4 s (L).
  - No official stills, concept art or production-design interview describes these rooms. A fan site's design quotes are unverified [48].
- **The Velodrom and Messe Berlin locations** come from Joyn and the fan wiki (L). The station's Messe Berlin link also rests on a fan post (unverified) [49].
- **Map 1's layout is ours.** The eye comes from the book. The film shows one valley, but not where things sit in it.
- **Unplaced footage.** The flower-sun macro (FE @25.4 s), the light beam (IMAX) and the red machinery shots (T2 @132.4 s; TVn @2.2–4.2 s) are used only as invented set pieces, or not at all.
- **Map 2's size.**
  - The fan guide's 1.45 km is a fan estimate.
  - The real lagoon's 120–170 m is a rough estimate from vehicles.
  - Sectors 5, 7, 8 and 9 were never seen, so their hazards are ours.
  - Whether the film showed the blood rain, the insects and the beast is not confirmed by our references; the fan guide and the book list them.
- **Volcanic colour.** The book's ash is clear and sparkly, and its "lava" is a gel that sets glassy [18]. The film's eruption is orange fire. We follow the film for the eruption and the book for the crust.

---

## Sources

**Owner frames** (study only). The trailer pass matched the seven film frames to T1; the clock reference is a fan guide. They are in `C:\Users\USER\OneDrive\Documents\LastStanding\References\owner\`:
- `map1_green_land_owner_frame.png`
- `map2_clock_arena_reference.png`
- `launch_1_red_room_net_a.png`
- `launch_1_red_room_net_b.png`
- `launch_2_glass_cases.png`
- `launch_3_pole_rise.png`
- `launch_3_pole_hall_wide.png`
- `train_station_owner_frame.png`

**Trailer frames:** `C:\Users\USER\OneDrive\Documents\LastStanding\References\trailer\` (66 frames and crops, named by video and second).

**Web references:** `C:\Users\USER\OneDrive\Documents\LastStanding\References\web\` (31 captures). Each one's source link is in that folder's `index.md`.

**My colour sampling:** `%TEMP%\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\arenas_v5\brief_tools\`, which holds `sampler.py`, the `spec_*.json` regions and the box overlays in `out\`.

**Videos**
- The Lionsgate channel search, for the video list: https://www.youtube.com/@LionsgateMovies/search?query=sunrise%20on%20the%20reaping
- The videos coded T1, T2, FE, SH, TVn, TVk and IMAX: see "How to read it".
- Two videos show no locations: the reveal teaser (https://www.youtube.com/watch?v=a0Ptnzz4jAw) and the "machine" spot (https://www.youtube.com/watch?v=H_qdtNXFtJA).

**Text and images**
1. WorldAtlas, the real places behind Panem: https://www.worldatlas.com/destination/the-real-places-behind-panem-in-sunrise-on-the-reaping.html
2. Screen Rant, filming arena video: https://screenrant.com/hunger-games-sunrise-on-the-reaping-filming-arena-video/
3. Idealista, Somiedo: https://www.idealista.com/en/news/lifestyle-in-spain/2025/09/19/856113-the-spanish-natural-park-where-the-hunger-games-will-be-filmed
4. Wikipedia, the film: https://en.wikipedia.org/wiki/The_Hunger_Games:_Sunrise_on_the_Reaping
5. Wikipedia, Saliencia Lakes: https://en.wikipedia.org/wiki/Saliencia_Lakes
6. Turismo Asturias, Valle del Lago route: https://www.turismoasturias.es/en/senderismo/rutas/senderistas/valle-del-lago-lago-del-valle
7. Screen Rant, arena filming photos: https://screenrant.com/hunger-games-sunrise-on-the-reaping-haymitch-quarter-quell-arena-filming-photos/
8. Screen Rant, arena costumes: https://screenrant.com/hunger-games-sunrise-on-the-reaping-haymitch-arena-tribute-costumes-set-photos/
9. La Nueva España gallery, 31 July 2025, photos by Mario Canteli: https://www.lne.es/fotos/occidente/2025/07/31/imagenes-primeras-escenas-nueva-entrega-120219332.html
10. EW via Yahoo, inside the creation of the arena: https://www.yahoo.com/entertainment/movies/articles/inside-creation-hunger-games-sunrise-153000912.html
11. Gizmodo, the colour: https://gizmodo.com/why-the-hunger-games-sunrise-on-the-reaping-is-so-colorful-despite-its-dark-story-2000825567
12. The Direct, the IMAX arena opening: https://thedirect.com/article/sunrise-on-the-reaping-hunger-games-catching-fire-arena-opening
13. Iron Studios, trailer analysis: https://ironstudios.eu/blogs/news/hunger-games-sunrise-on-the-reaping-trailer-analysis
14. Her Campus UCLA, trailer breakdown: https://www.hercampus.com/school/ucla/breaking-down-the-new-sunrise-on-the-reaping-trailer/
15. MHS Cat Talk, everything you missed: https://mhscattalk.com/13013/entertainment/everything-you-missed-from-the-sunrise-on-the-reaping-trailer/
16. Hunger Games Wiki, Cornucopia (text and images)
    - page: https://thehungergames.fandom.com/wiki/Cornucopia
    - set photo: https://static.wikia.nocookie.net/thehungergames/images/8/81/50th_Hunger_Games_Cornucopia.jpg
    - Catching Fire concept art: https://static.wikia.nocookie.net/thehungergames/images/c/c4/CF_cornucopia_concept_art.jpg
    - Catching Fire film still: https://static.wikia.nocookie.net/thehungergames/images/3/39/Download3.jpg
17. Hunger Games Wiki, 50th Games arena: https://thehungergames.fandom.com/wiki/50th_Hunger_Games_arena
18. Hunger Games Wiki, 50th Games: https://thehungergames.fandom.com/wiki/50th_Hunger_Games
19. Goodreads reader note (the eye, chapter 25): https://www.goodreads.com/notes/214333691-sunrise-on-the-reaping/14195726-chris-walker
20. LitCharts, *Sunrise on the Reaping* chapter 14: https://www.litcharts.com/lit/sunrise-on-the-reaping/chapter-14
21. LitCharts, chapter 15: https://www.litcharts.com/lit/sunrise-on-the-reaping/chapter-15
22. LitCharts, chapter 18: https://www.litcharts.com/lit/sunrise-on-the-reaping/chapter-18
23. LitCharts, chapter 22: https://www.litcharts.com/lit/sunrise-on-the-reaping/chapter-22
24. Ink and Imaginings, chapter recap: https://inkandimaginings.com/sunrise-on-the-reaping-chapter-by-chapter-recap/
25. Wikipedia, the novel: https://en.wikipedia.org/wiki/Sunrise_on_the_Reaping
26. Filmspeak, first trailer: https://filmspeak.net/news-2/2026/4/15/return-to-the-games-haymitchs-brutal-origin-revealed-in-first-sunrise-on-the-reaping-trailer
27. Winter is Coming, the book twist: https://winteriscoming.net/i-can-t-believe-the-sunrise-on-the-reaping-trailer-included-this-major-book-twist
28. Syfy, Trailer 2 easter eggs: https://www.syfy.com/syfy-wire/the-hunger-games-sunrise-on-the-reaping-easter-eggs-revealed-in-new-trailer
29. Hunger Games Wiki, Catacombs: https://thehungergames.fandom.com/wiki/Catacombs
30. Winter is Coming, Trailer 2 breakdown: https://winteriscoming.net/the-hunger-games-sunrise-on-the-reaping-trailer-breakdown-second-quarter-quell
31. Hunger Games Wiki, Launch Room: https://thehungergames.fandom.com/wiki/Launch_Room
32. Joyn, five filming locations in Germany: https://www.joyn.de/bts/themen/filme/sunrise-on-the-reaping-diese-fuenf-drehorte-liegen-in-deutschland-214510
33. Hunger Games Wiki, filming locations: https://thehungergames.fandom.com/wiki/Filming_locations
34. Wikipedia, Velodrom: https://en.wikipedia.org/wiki/Velodrom
35. Structurae, Velodrom: https://structurae.net/en/structures/velodrom
36. Den of Geek, cast exclusive (costumes): https://www.denofgeek.com/movies/hunger-games-mckenna-grace-joseph-zada-give-exclusive-sunrise-on-the-reaping/
37. ScreenCrush, first look: https://screencrush.com/hunger-games-sunrise-reaping-first-look/
38. Blackwell's, synopsis (48 tributes): https://blackwells.co.uk/bookshop/product/Sunrise-on-the-Reaping-by-Suzanne-Collins/9780702349065
39. Filmofilia, 48 tributes: https://www.filmofilia.com/sunrise-on-the-reaping-second-trailer-48-tributes-227945/
40. LitCharts, chapter 4 (the train): https://www.litcharts.com/lit/sunrise-on-the-reaping/chapter-4
41. TheBlaze, the Google Earth set (and the fan guide's credit): https://www.theblaze.com/news/2013/01/31/google-earth-satellite-image-reveals-outdoor-water-park-set-for-hunger-games-sequel
42. /Film, the Quarter Quell arena: https://www.slashfilm.com/quarter-quell-arena-from-the-hunger-games-catching-fire-revealed/ (image: https://www.slashfilm.com/wp/wp-content/images/The-Hunger-Games-Catching-Fire-Quarter-Quell-arena.jpg)
43. IBTimes, Hawaii: https://ibtimes.com.au/hunger-games-catching-fire-quarter-quell-scenes-shot-hawaii-photos-1264955
44. Atlas of Wonders (travel site, unverified): https://www.atlasofwonders.com/2023/08/where-was-catching-fire-filmed.html
45. LitCharts, *Catching Fire* chapter 23: https://www.litcharts.com/lit/catching-fire/chapter-23
46. Hunger Games Wiki, 75th Games: https://thehungergames.fandom.com/wiki/75th_Hunger_Games (still: https://static.wikia.nocookie.net/thehungergames/images/7/70/The_hunger_games_catching_fire-still_2.jpg)
47. The fan visual guide: https://static.wikia.nocookie.net/thehungergames/images/b/b2/Catching-Fire-Arena2.jpg
48. Play Hunger Game (fan breakdown, unverified): https://www.playhungergame.com/sunrise-on-the-reaping-trailer/
49. PanemPropaganda on X (fan account; rumour)
    - the station: https://x.com/panempropaganda/status/2044394640170680519
    - the parade: https://x.com/panempropaganda/status/1987242873385808229
    - the horn's build: https://x.com/panempropaganda/status/1948005292534292605
