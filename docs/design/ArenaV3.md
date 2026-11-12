# The Vale v3: a wider, wilder arena

*Lead level designer, 12 November 2026. Design only: nothing here is built yet. It answers your note "whats up with the maps man why so small and why so flattish with no adventurish things", your pick of a 3× wider arena, and your answer "whats in the hunger games movie whats it like". It rests on three research passes (the film arenas, big battle-royale maps, Roblox at this scale) and a read-only audit of today's world code in Studio and `src/` (12 November). Studio was only read for this document: nothing was edited and no playtest was started or stopped.*

**Decisions (owner, 12 November 2026)**
- **Where to build:** the lead's call. It's built in the main place after a labelled restore point. Today's world is archived, not deleted, and the place's version history can roll back to the restore point.
- **Pacing:** 15-minute rounds with the early first closing: 3:15–5:15, r 1,800 → 1,250, drifting up to 200 studs toward a seeded bearing.
- **The Greyvein ore cableway:** yes, built last.
- **Art:** every new asset uses the style the owner picks from the realistic-blockish style test (`docs/design/ArtStyle.md`). The build starts once that choice is made.

**In short (plain English)**
- **Bigger.** The play area grows from 1,280 to 3,600 studs across (about 1 km), 7.9× the area. A jog from the Spire to the edge takes about 2¼ minutes.
- **Real ground.** The Vale becomes a true mountain valley. The Spire's clearing sits in a basin. Forest ridges rise 100–200 studs around it. Inside the border there is a 90–140-stud escarpment, a canyon up to 200 studs deep, a 76-stud waterfall, a flat-topped butte and two peaks (520 and about 600 high). Today the hills are about 60 studs from top to bottom.
- **Adventure.** 29 named sites:
  - giant climbable trees and a route through the treetops;
  - caves, two of which run right through a ridge to another region;
  - a river with rapids, a great waterfall with a cave behind it, and a long lake with islands;
  - two rope bridges over the canyon, and lookouts;
  - the ruins of people who lived here before the Games: a mill, a dam, a mine, a stone fort, a fire lookout, a hunters' camp, a quarry and an orchard.
- **The films' feel, in our own designs.** One crisp artificial object, the Spire, stands in an open clearing. Around it, a wilderness grows older, wilder and richer in hidden water the farther you go. Every refuge is also a trap, and the Wardens keep herding. Nothing signature is copied (§1).
- **Pacing.** The round stays 15 minutes. The border closes in three stages:
  - 3:15–5:15, to r 1,250, its circle drifting toward a different side each round;
  - 8:10–9:25, to r 800;
  - 10:00–13:50, to the Spire, as today.

  The wide start feels sparse and wild; by the Offering the pace is back to today's.
- **Runs on phones.** Scenery is dense where people go and light elsewhere, and each player's own device places the small ground cover round them. Distant views use level of detail, and the ridges hide most of the map from any one spot. The server holds at most 90k scenery models, and any one player's streamed area holds about what today's whole arena holds. The launch, when all 24 players stream the area round the Spire, is the tightest case (§7.5).
- **Build.** Six phases, about 6 weeks with agents working in parallel. It starts with the layout data, TerrainGen v3 and the staged border (§9). Four questions for you are at the end (§10).

**Kept exactly as today**
- The Spire at the centre (0, 0, 0), the plaza (a flat disc of r 62 at y 46) and the realistic SpirePlatform.
- The 24 launch plates at r 52, the trench under them and its `TerrainGen.Tube.maxCentreR` 59 cap.
- The Spire's four crate slots.
- The Offering at 9:50, the final closing (10:00–13:50) and the Last Stand.
- The lake level (34) and the marsh level (36.5).
- Every movement number.

---

## 1. The feel

Ten pillars. Each one names the film feel it borrows. Every one of those feels is a generic genre element; none of them is a signature beat.

| # | Pillar | What it means in the Vale | The film feel it captures |
|---|---|---|---|
| 1 | **Wild first, built second** | The ground is mostly natural, and the only crisp artificial object is the Spire. Human traces are old and broken (a mill, a dam, a mine, a fort), left from before the Games. | A strange supply object set down in real wilderness |
| 2 | **The forest gets older the deeper you go** | Near the Green the trees are light pine and birch. Farther out the woods are dense and mixed, and at the edges stand old-growth giants, with deep caves and hidden springs. | The arena reveals itself as you cross it, so exploring pays |
| 3 | **Real ground** | A basin ringed by ridges, a canyon, an escarpment, buttes and peaks. Height costs time to climb and pays you back: views, ground others can't see, ways to escape. | Steep, wet waterfall country; a field hidden below a drop |
| 4 | **Every refuge is a trap** | Each site has a use, a risk and a tell. A tree you escape into can pin you there. A cave you heal in always has a second mouth. A ford where you drink is where you get ambushed. | Climb to escape while the pack waits below; the cave where the wounded hide |
| 5 | **Water is the spine** | A ladder of water. The lake and the river always flow and are always contested. Each quarter has a creek, and there are hidden springs and pools. Thirst sends you on your first journey. | Water first, then shelter and warmth |
| 6 | **Adventure is a route, not a room** | Climbs, caves, bridges, treetops, swims, leaps into deep water. Every site has two or more ways in and out; nothing is a dead end. | Chases, escapes and crossings |
| 7 | **Beauty where danger is highest** | The falls, the golden grass, the beach and the canopy are the most exposed places, or the ones events hit most. | Lush but perilous |
| 8 | **The Wardens keep it moving** | The staged border and the Warden events pull and push about every two minutes, so no hiding place stays safe for long. | The organisers herd everyone together when things go quiet |
| 9 | **Readable before it hurts** | Landmarks at three scales, a physical tell for every danger, and the same cover on every device within fighting range. | Rules you can learn and decode |
| 10 | **Big but never empty, and it runs on a phone** | A site within about 50 s at a jog and something to notice every 8–15 s. Scenery is dense where people go and light elsewhere. | Meetings are rare and sharp |

**Avoid.** These are the source's signature beats, checked against Roadmap §7 and the research. The ones §7 doesn't list yet belong there at its next edit.
- A clock-face arena: no equal pie wedges, no hazards on an hourly timetable, no spinning ground.
- A horn-shaped or golden central cache. No mines round the plates, no 60-second wait, no cache on an island reached by radial causeways, no swimming start.
- Engineered insects or a dropped nest, voice-mimicking birds, creatures with the faces of the fallen, and creatures driving the last contenders onto the Spire.
- A wall of fire chasing someone. Nothing volcanic: Ember Rain never looks like lava, so there are no glowing flows, no erupting peak, no lava lake and no peak that smokes (the bothy's chimney on the Frostback stays a thin, low wisp).
- A flood that drowns the whole arena, or a dam that bursts. The Floodgate is a local surge down one canyon. *(Story note: the 68th "Flood Games" in story-world.md §3.10, where a dammed river drowns the Vale, sits close to a source beat. That's for the story lead to look at.)*
- A deadly flower meadow, a rule that everything is poisoned except rain, tapping trees for water, or a scripted drought that dries everything but the lake. We vary which springs flow from round to round instead.
- A fog that hunts people or blisters them, blood rain, a lightning tree, a giant wave, a visible weak spot in the border, or an edge field that throws weapons back.
- A hedge maze, a bombed stadium with tunnels and snakes, gifts that explode.
- Names: no site is a "horn" or "cornucopia", and nothing is named after a place in the source.

---

## 2. Size and shape

| | Today (v2) | The Vale v3 |
|---|---|---|
| Play radius (where the border starts in a full round) | 640 | **1,800**: 3,600 across, about 1 km |
| Area inside the start ring | 1.29M sq studs | 10.18M (7.9×) |
| Area per contender (24) | 54k: a 230-stud square each | 424k: a 650-stud square each |
| The Green (meadow) edge | r 125–178 | r 190–291 (nominal 240). Not 3× bigger: a 450-stud meadow would be a 30-second run under bowshot. |
| Mountain wall foot | r 651–700 | r 1,814–1,878 (`MountainRadius` 1,846) |
| Wall profile | an 18-stud sheer step, then +34 at ~75° and +30 at ~54° | the same 18-stud step, then +60 at ~75° and +120 at ~54° |
| Invisible Boundary | r 712 (72 walls) | r 1,900 (144 walls) |
| Terrain reaches | r 920 | r 2,700. The massif crest is 700–1,000 high at r 2,150–2,450 and falls to ~120 at r 2,750, so from the Tor it looks like real mountains. |
| Highest point inside the border | ~103 (an overlook) | ~620 (the Frostback); Lantern Peak is 520 |
| Hills, top to bottom | ~60 | 100–200 in the forest; 250 or more from a valley floor to a plateau |
| The Tor (lobby) | (2,600, 160, 0) | (3,600, 300, 0), beyond the new terrain (§7.7) |

**Crossing times** on flat ground. Real routes add 25–40% for bends and climbs.

| Trip | Studs | Jog (13/s) | Sprint (21/s; a full bar lasts 9 s) | Sprint and jog in turns (≈17.8/s) |
|---|---|---|---|---|
| Plate to the Green's edge | ~190 | 15 s | 9 s (one bar) | 11 s |
| Spire to the starting border | 1,800 | 138 s | 86 s | 101 s |
| Edge to edge | 3,600 | 277 s | 171 s | 202 s |
| Between neighbouring sites | 450–700 | 35–54 s | 21–33 s | 25–39 s |
| A 200-stud climb on a 20° trail | ~585 of trail | ~65 s | — | — |

**How 24 contenders fill it.** At first the nearest rival is about three times farther away than today. The staged border brings that back to today's pace by the Offering.

The table gives the average distance to the nearest rival if contenders were spread at random. Real players bunch up at water, sites and the Spire, so real gaps are shorter.

| Moment | Ring | Alive (typical) | Nearest rival, v3 | Today |
|---|---|---|---|---|
| After the scatter (1:00–3:15) | 1,800 | 24 | ~326 | ~116 (r 640) |
| The night (after stage 1) | 1,250 | 20 | ~248 | ~127 |
| The Offering (after stage 2) | 800 | 14 | ~190 | ~152 |
| 12:00, midway through the final closing | ~400 | 8 | ~125 | ~101 |

Footsteps carry 90 studs and you see 60–120 studs through the forest, so early meetings come from shared pulls rather than chance: water, sites, the Spire, events. That gives the quiet, tense opening the films have. The stages and the Warden events (§6) still give every contender a pull about every two minutes.

**Small rounds start smaller.** This keeps QW3, re-based on the new size. The start ring is r0 = clamp(1,800 × √(N/24), 520, 1,800):
- Every contender gets the same space as in a full round, down to 2 contenders. (A floor of 640 would give 2 or 3 contenders more room each than a full round, the opposite of what QW3 is for.)
- Every stage radius scales by r0 / 1,800.
- **Small rounds drift from the start.** When r0 is under 1,200, the start circle's centre sits 0.25 × r0 from the Spire toward the round's seeded bearing (§6.5), so it reaches 1.25 × r0 on that side. Each small round then takes in a different slice of the high ground and the water (and, from 4 contenders up, the nearest ring C sites), not only the Green and ring B.
- Loot more than 30 studs outside the start circle is skipped, as today, measured from the circle's centre.
- At equal space per contender, each contender meets rivals about as often as in a full round (about 80% as often with 4 contenders, half as often with 2). QW3's own test still applies (T14): with 4 players, the median time from leaving the plaza to first seeing or hearing a rival is 3:00 or less. If that fails, the next lever is PlayabilityPlan B3 (the round's clock scaled to the head-count). `Shared.Border` inherits it, because it runs on `RoundService.getElapsed()`.

| Contenders | 2 | 3 | 4 | 6 | 8 | 12 | 16 | 20 | 24 |
|---|---|---|---|---|---|---|---|---|---|
| Start ring, v3 | 520 | 636 | 735 | 900 | 1,039 | 1,273 | 1,470 | 1,643 | 1,800 |
| Today | 320 | 320 | 320 | 320 | 370 | 453 | 523 | 584 | 640 |

`Config.Border.MinStartRadius` goes from 320 to 520. `ScaleWithContenders` stays on.

---

## 3. Region map

North is up (−Z) and east is to the right (+X). One column is 60 studs and one row is 120 studs, so the drawing is to scale. The numbers are the sites in §4, and `@` is the Spire. The sketch was drawn from the same coordinates as the tables below.

```
                      XXXXXXXXXX^XXXXXXXXXX
                  XXXX^^^FROSTBACK^^^^^^^^^XXXX
              XXXX^^^^^^^^^^~~^^^^^^^^^^^^^^^^^XXXX
            XX^^^^^^^^^^^^^^^~~~~~20^^^^^^^^^^^^^^^XX
          XX^^HIGH COUNTRY^^^^^^^^^^~~^^^^^^^^^^^^^ttXX
        XX^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~~^^^^^GREYVEIN^XX
      XX^^^^^^^^^^^22^^^^^TTTTttttttttt^^~^^^^^^tCRAGS^^^XX
     XX^^^^^^^^^^^^^^^^#TTTTTTtttttttttttt#9#^tt^^^^^^^^^^XX
    XX^^^^^^^^^^^^^^^##TTTT19TTttttTHROATtt=#t^^^^^^^^^^^^^XX
   XX^^^^^^^^^^^^^SENTINELSTTTTttttttttttt#~#ttt^^^^^^^^^^^^XX
  XX^THE SHELF^^^18#ttRIVENWOODttttttttttt#8#tttt^10^^^^^^^^^XX
  XX^^^^29^^^^^^^#~ttttttt~tttttt1tttttttt#=#ttttt^^^^^^^^^^^XX
 XX^^^^^^^^^^^^^##~tttttt6~ttttttttttttttt#~ttttttt^^^^^^^^^^^XX
 XX^^^^^^^^^^^^^#t~ttttttt~ttttt..tttttttt#~#tttttt""^^^^^^^^^XX
 XX^^^^^^^^^^17##tt~tttttt~ttGREEN..tttttt2~t#"""""""^^^^^^^^^XX
 X^^^^^^^^^^^^^##tt~tttt5tt~....@...tttttt~tt#"~""""""^^^^^^^^^X
 XX^^^^^^^^^^^^##Ttt~tttttt~t.......BOTTOMSt#""11"~~"::^^^^^^^XX
 XX^tTTTTTTTTTTTTTtt~ttttttt~tttt4~~ttttt3t#tTALLGRASS~###::::XX
 XXtttTTTTTTTTTTTTTttt~,,,tt~ttt~~~~~~~ttt#t""""""""":#^24^:::XX
  XXttTTTTTTTTT16TTTt,,,15,~~7tt~~~~~ttttttt""""""""::#^^^#::XX
  XXELDERWOODTTT=TT~~~~,,,,,tttt~~~~~~ttt13tttt"12"::::::::::XX
   XXtttTTT~~TTTTTTTSUMP,,,ttttt~~~14~tttttttttttt::::::::::XX
    XXtttT28TTTTTTTTTtttttttttttt~~~~~tttttttttt:::::::::::XX
     XXtttTTTTTTTTTttttttttttttttSTILLttttttTABLELANDS::::XX
      XXttttTTTTTttttttttttttttttWATERtttt25:::::::::::::XX
        XXttttTTttttttttttttttttt~~~~~t##tttt::::::::::XX
          XXttttttttttttttttttt####26#tttttttt:::::::XX
            XXttttttt27ttttttttttt~tttttttttttt::::XX
              XXXXttSOUTHERN REACHEStttttttttttXXXX
                  XXXXtttttttt~ttttttttttttXXXX
                      XXXXXXXXXXtXXXXXXXXXX
```

Legend:
- `.` the Green (meadow) and `@` the Spire.
- `t` forest, `T` old-growth giants, `"` tall grass, `,` marsh, `:` dry pine tablelands.
- `~` water: the lake, the tarn, the river and the creeks.
- `#` cliffs and canyon walls, `^` high ground (plateaus, crags, peaks).
- `=` rope bridges.
- `X` the mountain wall, which can't be climbed. The invisible Boundary runs along its outer edge.

**What changes the most.** The north is high: the river is born in a mountain tarn, runs across a plateau and drops over the Great Falls into a canyon east of the Green. The south is low: the long lake runs from the Green's beach to cliffs at its far end. The escarpment and its plateau hold the west. The east holds the hidden Tallgrass and the buttes beyond it. The marsh and the old-growth valley lie to the south-west.

| Region (in-world name) | Biome in code | Where (bearing°, r) | Size (studs) | Relief target (y) | What it is |
|---|---|---|---|---|---|
| **The Green** | Meadow | the centre, r 0–240 (edge 190–291) | ~480 across | Plaza 46 (flat to r 64); meadow 42–58; a rim of low folds at 60–80 (r 230–330) | The clearing, the Spire and the plates (unchanged), the beach to the south, Greenbrook to the west |
| **Rivenwood** | Forest | the near ring N, NW, W and NE, r 240–1,000 | a ring ~600 wide | Valley floors 50–90, ridges 150–200, ravines 20–40 deep | Light pine and birch near the Green, mixed forest farther out |
| **The Bottoms** | Forest (lowland) | E–SE, 60°–145°, r 250–760 | 500 × 700 | 40–100, with river terraces; the Breaks bluff on its east edge rises to 150–170 | The river's meanders, the fords and the Millrace |
| **Stillwater** | Lake | S–SE, 160°–175°, r 250–1,300 | ~1,050 × 330 | Water 34, up to 14 deep; north beach 34–40; east bluffs 70–120; the Lakehead cliffs at the south end, 150–165 high (top at 190–200) | The long lake beside the Green, with Kettle Island and the Stack |
| **The Sump** | Marsh | SW, 205°–240°, r 480–950 | 500 × 380 | 34–44 (water 36.5); its rim rises to 70–90 | The marsh basin, the Drowned Pines, the Miasma's home |
| **The Elderwood** | OldGrowth (new) | SW–WSW, 220°–268°, r 900–1,650 | 750 × 600 | Valley floor 45 rising to 160; side ridges 250–330; the Elderbrook ravine 40–60 deep | The oldest forest: giants, the Canopy Grove, the Hidden Spring |
| **The Shelf** | Cliffs + Highland (new) | W–NW, 258°–340°, r 1,000–1,800 | 800 × 900 | Foot 110–150; the escarpment face (the Rust Wall) 90–140 tall; plateau 240–300; a tor to 340; the quarry floor 200 | The escarpment and the high plateau behind it |
| **The Sentinels** | OldGrowth (conifer) | NW–NNW, 316°–352°, r 650–1,140 | 550 × 500 | Slopes rising from 90 to 300 | Giant conifers on the slope below the High Country |
| **The High Country** | Highland + Alpine (new) | N, 330°–40°, r 1,150–1,800 | 1,300 × 650 | Plateau 280–340; Lantern Peak 520; the Frostback 560–620, with snow from ~540 | The river's head, the tarn and its dam, the peaks |
| **The Throat** | Gorge | NE: along x ≈ 650, from 35° r 1,150 to 75° r 670 | 780 × 150–250 | Floor 180 falling to 100; rims 250–300 (W) and 300–380 (E); walls 80–200 deep; the Great Falls drop 76 | The canyon below the Great Falls |
| **Greyvein Crags** | Crags (new) | NE–E, 45°–95°, r 1,180–1,800 | 800 × 650 | 280–440, with cliff bands of 40–80 and talus fields | The mine and the Jumbles |
| **The Tallgrass** | Field | E, 78°–125°, r 780–1,260 | 700 × 480 | Basin 80–120, rising east to 160. The Breaks' crest (150–170) hides it from the Green. | The golden grass basin |
| **The Anvil Tablelands** | Tablelands (new) | E–SE, 95°–148°, r 1,260–1,800 | 900 × 550 | Mesas 180–260; dry ravines 30–50 deep; the Anvil 330, with cliffs of 70–90 | Dry pine and buttes |
| **The Southern Reaches** | Forest (hills) | S–SSW, 148°–220°, r 1,300–1,800 | 1,100 × 500 | Hills 120–260; the hanging valley above the lake at ~200 | Rolling hill forest, the Lost Orchard, the top of the Lakehead cliffs |
| **The Crest** (mountain wall) | Mountains | wall foot r 1,814–1,878; Boundary 1,900; terrain to 2,700 | a ring | Foot 150–600 (lowest in the south; highest in the north, where the Frostback's snowfield runs up to it); the wall's faces rise 18 + 60 + 120; the massif 700–1,000 | Can't be climbed: it closes the valley |

**Why it won't feel flat any more.**
- From the plates (eye height ~52) the forest edge fills the view up to about 14°. Above that you see the Sentinels' spires, the Lone Elder, the Greyvein headframe, the falls' spray, Lantern Peak (~19°), the Frostback and the snowy massif all round (~19°). It reads as a valley, not as a disc of hills.
- In the forest, the ridges and ravines hide what lies beyond them. Long views exist only from high ground (§5).
- The Field sits in ground the Green can't see: the Tallgrass lies behind the Breaks' crest, as the research advised.

**Slope budget** (it keeps the drama walkable; movement is walkable up to 46° and slows uphill):
- At least 85% of the land under 30°.
- At least half of the walkable land under 15°. There you keep full stamina recovery and at least 77% of your speed uphill (`Slope.UphillDrainAngle` 15, `UphillSlowdown` 0.9), so the crossing times above and the border's pace still hold. A 20° slope already costs 31% of your speed and all stamina recovery.
- No more than 10% at 30–46°: steep and slow, but walkable.
- No more than 5% you can't walk: only the cliffs we design.
- Trails stay at 20° or less, using switchbacks, and never pass 30°.

**Water levels.** Every water level sits in the lower half of a 4-stud voxel layer, 4k + 0.5 to 4k + 2, because Roblox only shows water in a voxel that holds no solid. The audit's examples (62.5, 98.5, 142.5) are 2.5 studs into their layers; use values like 64.5, 100.5 and 144.5 instead.

| Water | Level (y) | Notes |
|---|---|---|
| Stillwater | 34 | Unchanged. The floor is at ~20. |
| The Sump | 36.5 | Unchanged |
| Highwater tarn | 300.5 | Held by Highwater Dam |
| The plateau stream | 272.5 (the spillway pool at the foot of the 34-stud dam) falling to 256.5 | Riffles and two fords, one of them the Lip Ford 40 studs upstream of the falls |
| The Great Falls | 256.5 falling to 180.5 (76) | Into the Cauldron, at least 12 deep where you land |
| The Throat | 180.5 falling to 100.5 | Rapids, two cascades (12 and 8 studs) and a log jam |
| The Bottoms | 100.5 falling to 34 | Meanders, three fords, the Millrace weir (76.5 down to 68.5) |
| Creeks, one per quarter | Greenbrook 132.5 → 36.5 · Shelf Creek 140.5 → 36.5 · Elderbrook 164.5 → 36.5 · Tallgrass Run 172.5 → 84.5 · Lakehead Run 236.5 → 196.5, then Lakehead Falls (26) and a stepped ravine down to 34 · Frost Rill, into the tarn | Greenbrook passes the Green's west edge (~r 300), about 15 s from the nearest plates |
| Quarry pond | 196.5 | The flooded quarry pit |
| Hidden springs and pools | 10 (§4) | 7 of them are optional, and 4 of those flow in any one round (§6) |

---

## 4. Adventure sites

There are 29 named sites (plus the Spire), in three rings by distance from the plates:
- ring B, r 250–700: minor sites, 15–50 s from the plates;
- ring C, r 700–1,300: major sites, 55–100 s away;
- ring D, r 1,300–1,750: remote sites, 100–130 s away.

Neighbouring sites are about 300–450 studs apart near the Green and 450–700 farther out, roughly 25–54 s at a jog. Each entry gives:
- **what** the site is;
- **why** you'd go: its loot (tier and markers), what you do there, and its risk and its tell;
- **how you get in and out**;
- its bearing, distance (r) and height (y), and its size.

Section 6 gives the loot totals.

### Ring B: near the Green (r 250–700)

Six of the seven have one crate rolled on the runner's table, so it holds a basic weapon; the Drowned Pines has none. Every site has 2–3 ground markers and some forage.

**1 · The Lone Elder** · 5°, r 520 · knoll top y ~95 · 60 × 60
- **What:** a 130-stud ancient oak alone on a knoll north of the Green, with a hollow at its foot. It is the first giant you see from the plates.
- **Why go:** 1 crate in the hollow and 2 ground. Its crown hide, about 105 up, is the nearest high view to the Spire: the whole Green, the beach and the mouth of the Throat.
  - *Risk:* the most visible perch in the Vale. Archers can stand on the knoll, and Splice hounds wait below.
  - *Tell:* low branch stubs and a worn band of bark at hand height, the climbable look from PlayabilityPlan B7.
- **In and out:** the High Road runs past the knoll. Climb the trunk: rest forks at 38 and 76, then the hide. The only safe way down is the trunk, because a fall of 58 studs or more kills.

**2 · The Notch and Breaks Ford** · 80°, r 600 · y 85–150 · 200 × 120
- **What:** the slot where Tallgrass Run cuts through the Breaks bluff to meet the river, with the river's widest ford just below it.
- **Why go:** 1 crate on a gravel bar, 3 ground, and water. It is the only low gap between the Bottoms and the hidden Tallgrass, so it's a natural chokepoint and a favourite spot for the Lure.
  - *Risk:* 30 studs of open ford, and the slot is a funnel 12 studs wide.
  - *Tell:* the creek echoing in the slot, and gravel worn by boots.
- **In and out:** wade the ford (0.5–1.2 deep), walk the ledge beside the creek through the slot, or climb the Breaks' scree on either side (slow and exposed).

**3 · The Millrace** · 115°, r 600 · y 70–80 · 120 × 90
- **What:** a stone mill on the river with half its roof still standing, a broken water wheel, a timber flume, and a weir with an 8-stud drop.
- **Why go:** 2 crates (ground floor and loft) and 3 ground. It is the first real building east of the Green: stone cover from Ember Rain, a hearth for Cold Snap, and water at the door.
  - *Risk:* dark inside, with two doors and a loft window. The weir walkway is 30 studs of open crossing.
  - *Tell:* the wheel's creak and the roar of the weir.
- **In and out:** the Mill Road from the Green; the weir walkway across the river; the two doors; the loft window, which drops into the millrace for a quick swim downstream.

**4 · North Beach and the Old Jetty** · 166°, r 250–330 · y 34–40 · 260 × 80
- **What:** the Green runs straight down to a sand-and-pebble beach on Stillwater. A half-sunk timber jetty points at Kettle Island.
- **Why go:** 1 crate at the end of the jetty, 3 ground, and forage in the reeds. It is the nearest water to the plates (~200 studs, 10 s at a sprint) and the first drink of the round.
  - *Risk:* after the Spire, the most exposed ground in the Vale. The whole southern half of the Green looks down on it.
  - *Tell:* reeds and frogs at the west end mark where you can wade in the shallows.
- **In and out:** walk down from the Green; dive off the jetty and swim to Kettle Island (~370 studs, about 45 s); wade west through the reeds to the Drowned Pines.

**5 · Charcoal Hollow** · 270°, r 500 · y ~80 · 80 × 80
- **What:** an old charcoal burners' clearing: grassed-over kiln mounds, a collapsed lean-to, stacks of cordwood and a cold fire ring.
- **Why go:** 1 crate under the lean-to and 3 ground. It is the nearest warmth source on the Green's west side for Cold Snap. The cordwood stacks are the only hard cover.
  - *Risk:* you stand in the open while others watch from the trees.
  - *Tell:* blackened ground and the stacked cordwood.
- **In and out:** the Charcoal Road (the west spoke) and the Inner Round cross here; three gaps in the treeline.

**6 · The Sinkhole** · 310°, r 560 · rim y ~100, floor ~64 · 50 across, 36 deep
- **What:** a collapsed pit in the forest with fern-hung walls, a spring pool at the bottom, and a low side passage that runs 60 studs out to a ravine.
- **Why go:** 1 crate in the side passage, 2 ground, and hidden water that isn't on the compass. It is a sheltered place to wait out the night.
  - *Risk:* whoever holds the rim has the drop on you, and the ramp down is slow and in plain view.
  - *Tell:* cool air and an echoing drip near the rim.
- **In and out:** a spiral ramp of rock and roots (mantle steps of 6 studs or less); a root ladder (Climbable); the side passage out to the ravine. With two mouths it is never a dead end.

**7 · Drowned Pines** · 200°, r 480 · y 34–40 · 150 × 120
- **What:** a flooded grove where the Sump drains into Stillwater: grey pine trunks standing in knee- to chest-deep water among the reeds.
- **Why go:** 2 ground and forage. Hide crouched among the trunks and reeds. It is the quickest way from the Green to the Sump.
  - *Risk:* wading is slow and the splashes carry. The Miasma reaches this far.
  - *Tell:* the grey trunks, which you can see from the beach.
- **In and out:** wade from the west end of the beach; take the Causeway's stepping stones; swim out into the lake.

### Ring C: the middle Vale (r 700–1,300)

Most sites have 2 tier-2 crates (3 at the Mine, the Redoubt and the Sentinels; 1 at Echo Run), 2–4 ground markers and forage. Four of them (9, 10, 14 and 16) also hold one of the six tier-3 prize spots (§6).

**8 · The Throat Crossings** · Upper Swing 40°, r 1,070 · Lower Swing 56°, r 780 · canyon floor y 180 falling to 100 · the canyon is 780 long and 150–250 wide
- **What:** two rope bridges over the canyon and the canyon floor between them, with rapids, gravel bars and a log jam.
  - The Upper Swing spans 70 studs, its deck about 85 above the water.
  - The Lower Swing spans 55 studs, about 90 above the water.
  - Both cross the narrow inner gorge between ledges well below the rims (the canyon is 150–250 wide at the top); paths climb from each anchor ledge to its rim.
- **Why go:** 1 crate at each bridge's west anchor, 2 ground on the gravel bars, and water. The bridges are the only quick ways across the canyon.
  - *Risk:* a bridge is a long, loud, exposed walk with nowhere to hide, and archers can wait on the far rim. A fall from a bridge kills, because the rapids are too shallow to break it (only the Floodgate's surge is deep enough to land in). The Floodgate makes the canyon floor deadly.
  - *Tell:* the planks creak, so footsteps on a bridge carry 120 studs. On the floor, the river's noise hides your footsteps.
- **In and out:**
  - the two bridges;
  - the Spray Steps at the falls end and the talus ramp at the canyon mouth;
  - a fixed rope down the west wall from the Lower Swing's ledge to the canyon floor (Climbable, two 40-stud pitches with a ledge between, §5.2);
  - the Greyvein gallery's ladders on the east wall;
  - the log jam, to cross the canyon floor.

**9 · The Great Falls, the Cauldron and the Veil** · 35°, r 1,150 · lip y 256.5, pool 180.5 · amphitheatre 220 × 160
- **What:** the river drops 76 studs off the High Country into a deep plunge pool, the Cauldron, inside a horseshoe of cliffs. Behind the curtain of water a ledge leads into the Veil, a cave with a spring, and a chimney climbs from it to the east rim.
- **Why go:** 2 crates on the Cauldron's gravel beach, 3 ground, and a tier-3 prize spot in the Veil's chamber. It is the most beautiful place in the Vale and the loudest. Jumping from the lip into the pool is survivable, and it's the fastest way down.
  - *Risk:* the roar hides footsteps and the spray hides people. The ledge fits one person at a time, and the Floodgate doubles the falls.
  - *Tell:* the spray plume above the trees, a landmark you can see from the plates. The falls thin to a trickle just before the Floodgate.
- **In and out:** the Spray Steps (a switchback path down the west wall); the leap from the lip; the ledge into the Veil, then a stepped passage that climbs about 50 studs inside the rock and a 30-stud chimney (Climbable) up to the east rim, about 80 studs above the pool in all; swim or wade out down the Throat.

**10 · Greyvein Mine** · 60°, r 1,250 · yard y ~330 · 260 × 200
- **What:** an abandoned iron mine on the crags.
  - Above ground: a 45-stud timber headframe over a shaft, ore bins, a collapsed bunkhouse and a forge shed, with rails running into two adits (horizontal tunnels).
  - Underground: the Greyvein Workings run 250 studs west through the ridge and open as a gallery on the Throat's east wall, 40 studs above the river. They drop about 140 studs on the way (the yard is at ~330, the gallery at ~190), through inclined drifts of 20° or less and two 30-stud ladder shafts with landings.
- **Why go:** a secondary hot zone, with 3 crates, 4 ground and a tier-3 prize spot deep in the workings. The forge is a warmth source and the adits are stone cover.
  - *Risk:* Rockfall from the crag above the yard. Underground you see about 15 studs, footsteps echo, and a collapsed stretch forces a crouched squeeze.
  - *Tell:* the headframe on the skyline, visible from the plates; timber props creaking; dust trickling down before a Rockfall.
- **In and out:**
  - the mine road up from the Hunters' Rest, or the crag path from the Jumbles;
  - through the Workings to the canyon gallery, then ladders down to a ledge and the canyon floor;
  - the headframe's ladder up to the platform by its wheel, a lookout;
  - optionally, an old ore cableway across the Throat (question 4).

**11 · The Tallgrass and the Lone Stone** · 95°, r 950 · basin y 80–120 · 700 × 480
- **What:** a hidden basin of chest-high golden grass behind the Breaks, with a few lone oaks and, in the middle, the Lone Stone: a house-sized boulder 22 studs high.
- **Why go:** 2 crates (at the Lone Stone and at a lone oak), 3 ground, and berry thickets along the edge. Crouched in the grass you are almost invisible (hounds see you at only 0.4× their range). The Lone Stone is the only high point: three mantles to its top.
  - *Risk:* nobody on the Green can see into the basin, so you never know who is already in the grass. Sprinting through it is loud, and Ember Rain favours open ground.
  - *Tell:* the gold of the grass, seen from the Breaks' crest; footsteps rustling before you see anyone.
- **In and out:** over the Breaks' crest by any of four game trails, through the Notch, or in from the Hunters' Rest or the tablelands. There are no fences.

**12 · The Hunters' Rest** · 120°, r 1,100 · y ~140 · 100 × 80
- **What:** an abandoned hunters' camp under a giant oak at the field's south-east edge: canvas lean-tos, an empty drying rack, a woodpile, a hunting blind on stilts facing the grass, and a plank platform 40 studs up the giant.
- **Why go:** 2 crates and 3 ground; the blind's crate favours bows and arrows. The fire ring is a warmth source, and the blind and the platform overlook the whole Tallgrass.
  - *Risk:* the blind is a box with one door, and the platform's only way down is the trunk.
  - *Tell:* canvas flapping in the wind, and in some rounds a thin curl of smoke.
- **In and out:** the Mill Road from the Notch; the mine road north; the tablelands south; a rope ladder (Climbable) and the trunk up to the platform.

**13 · Watchtower Ridge** · 138°, r 780 · y 110–125 · 140 × 80
- **What:** the existing timber Watchtower and a ruined signal hut on a granite bluff over Stillwater's east shore.
- **Why go:** 2 crates (the tower's cab and the hut) and 3 ground. The view runs down the lake to the Lakehead cliffs, over the Bottoms to the Green, and east into the Tallgrass.
  - *Risk:* the tower's ladder is the only way up, and the shore below is a Lure spot.
  - *Tell:* the tower's outline, seen from the beach.
- **In and out:** the Shore Path; the bluff path south to the Sawpit; the ladder; a 70-stud jump into deep water from the Leap Ledge below the tower (y ~104), which you survive. From the top of the bluff the drop is 76–91 studs, too far.

**14 · Stillwater Isles** · Kettle Island 162°, r 700 · the Stack 172°, r 1,000 · Kettle Island 70 × 50 (top y ~52) · the Stack 25 across, 45 high
- **What:** two islands.
  - Kettle Island is wooded, with an abandoned camp and a rowboat pulled up on its beach.
  - The Stack is a granite pillar rising from the lake, with a sea cave at the waterline. It is built from TorPillar meshes, not terrain: at 25 studs across it is thinner than Expanded Terrain's 16-voxel rule (§7.1).
- **Why go:** a secondary hot zone.
  - Kettle Island: 2 crates and 2 ground.
  - The Stack: a tier-3 prize spot in its sea cave, reached only by swimming.

  If you get there first, the islands are the safest night camp in the Vale, because hounds avoid deep water.
  - *Risk:* swimming is slow and you can't fight in the water, so archers on the shore have all the time they want. The Lure likes the island.
  - *Tell:* the rowboat's bow on the beach.
- **In and out:**
  - swim from the Old Jetty (~370 studs, ~45 s), from the east bluffs (~180 studs) or from the Drowned Pines;
  - swim into the Stack's cave;
  - haul out onto the ledge at the cave mouth (3.8 studs or less above the water, `Swim.ExitMaxHeight`), then climb a 40-stud crack (Climbable) to the top, a lookout over the lake.

**15 · The Cutters' Stilts** · 225°, r 720 · y 36–46 · 200 × 160
- **What:** the heart of the Sump: an old peat cutters' hut on stilts, rotting duckboards between hummocks, and a stand of dead trees.
- **Why go:** 2 crates (the hut and the cutting platform) and 3 ground. The hut is the only dry roof in the marsh.
  - *Risk:* this is the Miasma's home. The fog rises to about 44, and the hut floor (46) is the one spot just above it, so everyone runs there. Mud slows you to 72%.
  - *Tell:* the frogs fall silent before the Miasma.
- **In and out:** the Causeway's duckboards from the Drowned Pines; the Elderwood path; or wade anywhere (slow and loud).

**16 · The Canopy Grove** · 245°, r 1,150 · floor y ~95 · 160 × 120
- **What:** five ancient oaks, 120–140 tall, in the Elderwood, with crowns that touch.
  - Old hunters' platforms 40–80 up are linked by rope walks and by two limbs lodged between neighbouring crowns.
  - The Hollow Oak has a hollow at its foot that you can walk into.
- **Why go:** 2 crates (in the Hollow Oak and on the highest platform), 3 ground, and a tier-3 prize spot on the crown platform of the tallest giant. There is a 250-stud route through the treetops. Hounds can't reach you up there, and the dense crowns halve Ember Rain.
  - *Risk:* the rope walks sway and creak. A fall from 40 hurts and from 58 kills, and a climber is a slow target for archers below.
  - *Tell:* rope ladders hanging to the ground, one per tree.
- **In and out:** five trunks (Climbable, with a rest fork about every 38 studs), three rope ladders and the lodged limbs. On the ground: the path to the Sump and the Elderbrook rope bridge.

**17 · The Old Redoubt** · 275°, r 1,120 · on the Shelf's rim, y ~255 · 120 × 110
- **What:** a ruined star-shaped stone fort from the Sundering, on a spur of the Shelf: broken curtain walls, a gate arch, a 30-stud stump of a round tower with a stair inside, and a vaulted cellar.
- **Why go:** a secondary hot zone, with 3 crates (one in the cellar) and 4 ground. The cellar is stone cover from Ember Rain and the best night shelter on the Shelf. The tower looks over the Green, Charcoal Hollow and the Canopy Grove.
  - *Risk:* the courtyard is a killing ground watched from the tower and the walls. The cellar has one stair, and Rockfall hits the slope below the spur.
  - *Tell:* the tower and the line of the walls on the Shelf's edge, seen from the Green.
- **In and out:**
  - the Switchbacks up the Rust Wall, from the south;
  - the rim path from Echo Run's upper mouth;
  - across the plateau from the west;
  - the breach in the east wall, reached by a chain of mantles up the scree (fast but exposed).

**18 · Echo Run** · lower mouth 300°, r 960 (y ~128) · upper mouth 306°, r 1,180 (y ~238) · about 270 studs of passage (the mouths are 247 apart)
- **What:** a cave that runs right through the Shelf and climbs 110 studs inside it: an echoing chamber, a drip pool, a squeeze, and a stepped shaft up to a sinkhole on the plateau.
- **Why go:** 1 crate in the chamber, 2 ground, and the drip pool for water. It is the hidden way up the Shelf, and shelter from Ember Rain and Cold Snap.
  - *Risk:* it's dark, and footsteps echo (they carry 1.5× as far). Hounds smell you at 12 studs, and with two mouths, people can come in at both ends.
  - *Tell:* Shelf Creek springs from the lower mouth; cold air and echoes.
- **In and out:** the lower mouth, by the creek in the forest; the upper mouth, out of the plateau sinkhole by mantle steps; a side window onto the ledges of the Rust Wall.

**19 · The Sentinels** · 340°, r 880 · slope y 150–230 · 220 × 160
- **What:** three giant conifers (155–175 tall) and two dead giants on the slope below the High Country. The tallest holds the Perch, an old hide of lashed poles about 130 up.
- **Why go:** 2 crates at the giants' feet, 2 ground, and 1 crate in the Perch. The Perch overlooks the whole north: the Green, the Throat, Lantern Peak and the dam. It fits one person, so holding it is a duel.
  - *Risk:* a long climb in plain view, with rest forks at 40, 80 and 120.
  - *Tell:* the giants' spires above the canopy, visible from the northern plates.
- **In and out:** the High Road and the Sinkhole Path; the trunks; the slope trail up to the High Country.

### Ring D: the far Vale (r 1,300–1,750)

Each site has 1–2 crates and 2–3 ground markers, with a weapon and a vest guaranteed at every site, because the first border stage (from 3:15) will push their visitors back in. Two of them, Lantern Peak (22) and the Anvil (24), hold the other two tier-3 prize spots.

**20 · Highwater Dam** · 5°, r 1,400 · crest y 306 · the dam is 220 long and 34 high; the tarn is 300 × 170
- **What:** a stone dam holding the Highwater tarn at the head of the river, with a crest walkway, a two-floor gatehouse holding the sluice wheel, and a spillway chute that feeds the river. It is the source of the Floodgate.
- **Why go:** 2 crates in the gatehouse and 2 ground. The crest is the only crossing at the river's head, the tarn is clean water, and the gatehouse is stone cover.
  - *Risk:* the crest is 220 studs of open walkway, a shooting gallery from both ends.
  - *Tell:* before the Floodgate the sluice wheel turns and a horn sounds from the dam.
- **In and out:** the High Road's switchbacks from the south; the crest, east to west; the shore paths; the spillway, a one-way slide into the plateau stream's pool; or swim across the tarn.

**21 · The Frostback and the Bothy** · 352°, r 1,690 · y 560–620 · snowfield 400 × 250
- **What:** a snowy shoulder of mountain under the northern rim, with a bothy (a one-room stone herders' hut with a hearth) and a snowmelt pool.
- **Why go:** 2 crates and 2 ground. It is the highest ground in the Vale and the only view over all of it, and the bothy's hearth is the only warmth up high.
  - *Risk:* snow slows you to 80% and the climb is long. Cold Snap bites hardest here.
  - *Tell:* in some rounds, a thin, low wisp from the bothy's chimney. Never a column: a snowy summit that smokes would read as a volcano (§1).
- **In and out:** the snow ramp from the High Country (slow going up, a fast slide coming down); a scramble along a rock spur from Lantern Peak's saddle.

**22 · Lantern Peak and the Fire Lookout** · 325°, r 1,380 · summit y 520 · tower 40 tall
- **What:** a rocky summit with a ranger's fire lookout (a glazed cab on a timber tower, reached by stairs) and a survey cairn.
- **Why go:** 1 crate at the foot of the tower, 2 ground, and a tier-3 prize spot in the cab. It is the best lookout inside the border, over the Green, the Shelf, the Throat, the dam and the Sentinels. At night the cab's lantern is lit, a landmark from anywhere in the north.
  - *Risk:* exposed on every side, with one stair up the tower.
  - *Tell:* the tower by day, the lantern by night.
- **In and out:** the summit trail (switchbacks up from the Sentinels' slope, about 2 minutes); a scramble up the west ridge (a chain of mantles) from the Shelf plateau; the saddle across to the Frostback.

**23 · The Jumbles** · 40°, r 1,600 · y 380–440 · 220 × 160
- **What:** a field of house-sized boulders fallen from the crags: a maze of gaps, crawl-throughs and tunnels between the blocks, with a hidden pool in the largest chamber.
- **Why go:** 2 crates, 3 ground and hidden water. The maze is good against hounds, because the gaps are narrow, and bad for archers.
  - *Risk:* you can't see 10 studs ahead, so an ambush can come from anywhere. A Rockfall stretch sits above it.
  - *Tell:* water trickling inside.
- **In and out:** six or more gaps round the edge; the crag path to the mine; the edge of the High Country.

**24 · The Anvil** · 105°, r 1,500 · base y ~250, summit ~330 · the butte is 260 × 200, with cliffs of 70–90
- **What:** a flat-topped butte ringed by sheer cliffs, with a natural arch at its south end, springs at its foot (the source of Tallgrass Run) and a survey cairn on top.
- **Why go:** 2 crates and 2 ground at its foot by the springs, and a tier-3 prize spot on the summit, which looks out over the Tallgrass, the Hunters' Rest, the mine and the lake.
  - *Risk:* there are only two ways up, so the top is a trap if both are held. On the Chimney you can't fight back.
  - *Tell:* the arch and the flat top on the eastern skyline.
- **In and out:** the Chimney on the west side (an 80-stud Climbable crack in two pitches, with one rest ledge between); the Ramp (a narrow ledge spiralling up the south face, exposed).

**25 · The Sawpit and the Log Chute** · 150°, r 1,250 · y ~190 · camp 120 × 80; chute 300 long
- **What:** an old logging camp on the ridge above Stillwater's east shore: a sawpit with a rotted saw frame, stacked logs, a bunk tent and a timber log chute that runs 300 studs down to the lake.
- **Why go:** 2 crates and 2 ground, and the stacked logs are hard cover. The chute is the fastest way to the water: about 15 seconds of sliding, ending in a splash.
  - *Risk:* the chute is one-way and loud, and it drops you in the water in front of anyone on the shore.
  - *Tell:* the chute's trestle, visible from the lake.
- **In and out:** the Shore Path from Watchtower Ridge; the Outer Round to Lakehead and the Hunters' Rest; the chute (down only).

**26 · Lakehead Falls and the Ranger Station** · 172°, r 1,390 · cliff top y 190–200 · 160 × 120
- **What:** on the cliffs at the lake's south end:
  - a log ranger station: a cabin with a hearth and a rusted radio mast;
  - Lakehead Falls, which drops 26 studs into a pool on a ledge before the stream cascades down a stepped ravine to the lake;
  - the Lake Grotto, a cave at the waterline below.
- **Why go:** 2 crates in the station and 2 ground. The station gives you a roof and a hearth. The Leap, a ledge 66 studs above deep water, is the fastest way down to the lake.
  - *Risk:* the station has one door, and its windows face the trail; the cliff edge.
  - *Tell:* the radio mast on the skyline.
- **In and out:** the Outer Round; the ravine steps down to the lake and the Grotto; the Leap; the trails of the Southern Reaches.

**27 · The Lost Orchard** · 205°, r 1,550 · y ~180 · 200 × 150
- **What:** an overgrown orchard of old apple trees around a roofless stone farmhouse, with a well and trough and a root cellar.
- **Why go:** 2 crates (in the cellar and the house), 2 ground, and six forage spots with apples. There is water at the trough, and the root cellar is stone shelter.
  - *Risk:* it is the farthest site from the Spire, so the first border stage will make you run. The orchard rows give 120-stud sightlines.
  - *Tell:* windfall apples in the grass, which glint like ground loot.
- **In and out:** open on all four sides; the trails of the Southern Reaches; the cellar, with a hatch and a second, half-collapsed exit.

**28 · The Hidden Spring** · 238°, r 1,580 · y ~165 · 90 × 70
- **What:** the head of the Elderwood: a fern-filled grotto where Elderbrook wells out of a mossy rock wall into a clear pool, ringed by giant trees. No marked trail leads there.
- **Why go:** 1 crate behind the spring's little fall and 2 ground; clean water in the far west; the quietest place in the Vale. It stays off the compass until you have found it.
  - *Risk:* a valley head with only one obvious way in.
  - *Tell:* the sound of water, and the ferns thickening as you walk up the brook.
- **In and out:** up Elderbrook along the valley path; a goat path of mantle steps up the valley side to the Shelf plateau.

**29 · Spirestone Quarry** · 290°, r 1,520 · rim y ~285, floor ~200 · pit 240 × 180
- **What:** the old granite quarry where the Spire's stone was cut; in the lore, by the masons of Quarrymoor. It has stepped benches, a derrick mast, rows of cut blocks, a quarrymen's shed and a flooded pit.
- **Why go:** 2 crates (in the shed and at the derrick's base) and 3 ground. The benches form a giant staircase of 6-stud mantles, the cut blocks are hard cover, and the pond is water.
  - *Risk:* the pit is a bowl watched from its rim, and a Rockfall stretch runs along the high bench.
  - *Tell:* the derrick mast, visible across the Shelf plateau.
- **In and out:** the bench staircase; the ramp of the old haul road; swim across the pond; the north-rim path to Lantern Peak.

### Between the sites

On every route, something small turns up every 100–200 studs (8–15 s at a jog). Most of these hold nothing, or one ground item.

| Feature | Count | What it's for |
|---|---|---|
| Abandoned camps | 14 | One ground marker each. Eight have fire rings that count as warmth sources, and three smoulder in any given round. |
| Warden hatches | 16 | Splice Hunt releases, at least one in each region except the Green and the Crest, so no pack ever comes out beside the Spire. Never inside a cave. |
| Berry thickets and fruit trees | ~30 | Forage |
| Fallen trees, upturned root plates, hollow logs | ~20 | Hiding spots and cover. Root Hollow (40°, r 470) has a pond in the pit its roots left. Two fallen giants serve as natural bridges. |
| Springs, pools and seeps | ~15 | Water. Some flow only in some rounds. |
| Boulder piles, outcrops, rock shelters | ~25 | Cover, and low ledges to climb |
| Cairns and chalk marks | ~10 | Lore. Four lead to the hidden caches of Roadmap Phase 6b. |

### The brief's list, ticked off

| You asked for | Where |
|---|---|
| Huge ancient trees and treetop routes | 1, 12, 16 (the 250-stud treetop route), 19; fallen giants at Root Hollow and in the Elderbrook ravine |
| Cave networks, some linking regions | 18 Echo Run (the lowland to the Shelf), 10 the Greyvein Workings (the Crags to the Throat), 9 the Veil (the Cauldron to the canyon rim); also 6, 14, 23 and 26 |
| A river system with rapids, a big waterfall and pools | 20 (the river's head), 9, 8, 2, 3 |
| A lake with islands | 4, 7, 13, 14, 25, 26 |
| Canyons with rope bridges | 8 (two bridges), and the Elderbrook ravine bridge by 16 |
| High lookouts | 22, 21, 17, 13, 24, 19, 1 |
| A hunters' camp | 12 |
| A collapsed mine | 10 |
| An old dam or mill | 20 and 3 |
| A ranger tower | 22, plus the ranger station at 26 |
| A ruined stone outpost | 17 |
| Hidden places that reward exploring | 6, the Veil (9), the Stack's cave (14), the Hollow Oak (16), 18, 23, 27's cellar, 28 |

---

## 5. Routes and traversal

### 5.1 Main paths

**Eight spokes leave the Green.** Each one bends round folds and knolls, so no straight stretch shows more than about 250 studs ahead.

| Spoke | Heads | Links | Length |
|---|---|---|---|
| The High Road | N | 1, then the Sentinels' east edge and switchbacks up to 20 | ~1,450 |
| The Falls Road | NE | Root Hollow, the Throat's west rim, 8 and 9 | ~1,200 |
| The Mill Road | E | 3, 2, 11, 12 and 24 | ~1,500 |
| The Shore Path | SE | the river-mouth ford, 13 and 25 | ~1,300 |
| The Beach Path | S | 4 (then swim to 14) | ~300 |
| The Causeway | SW | 7, 15, 16 and 28 | ~1,600 |
| The Charcoal Road | W | 5, the Switchbacks up the Rust Wall, 17 and 29 | ~1,550 |
| The Sinkhole Path | NW | 6, 18 and 22 | ~1,400 |

**The rest of the network:**
- **The Inner Round** (r ~600; ~3,800 studs, about 5 minutes at a jog) links the ring B sites. It crosses the river at Breaks Ford and at the Millrace weir, and swings north along the beach round the head of the lake.
- **The Outer Round** (r ~1,250, ~8,000 studs) links the ring C and D sites along the rims: the top of the Rust Wall, the canyon's edge, the lake bluffs. It is there for finding your way; nobody walks all of it.
- **Game trails** lead down to every water source and ford (PlayabilityPlan B7).

That makes about 55 routes and 24,000 studs (~24 km) of trail, against 20 routes and ~6 km today.

### 5.2 Climbing and high ground

| High ground | Ways up | Fast way down |
|---|---|---|
| The Shelf (the Rust Wall, 90–140 high) | The Switchbacks (a trail; ~60 s, safe). The Ledges (a gully with a chain of about 12 mantles; ~45 s, exposed. A 6-stud mantle costs about 0.1 stamina, so the chain takes more than a full bar and you stop to breathe on a ledge halfway). Echo Run (hidden; ~45 s). The south scree (slow). | Slide down the south scree (~10 s), or go back through Echo Run |
| The High Country | The High Road's switchbacks (~2½ minutes from the Green); the Sentinels' slope trail; the Spray Steps and the Lip Ford by the falls | The spillway slide; the leap off the falls into the Cauldron |
| Lantern Peak | The summit trail (~2 minutes); the west-ridge scramble (~70 s) | The scree chute on its east face |
| The Frostback | The snow ramp (~2 minutes, slow on snow); the spur scramble | Slide down the snow ramp (~15 s) |
| The Anvil | The Chimney (80 studs in two pitches with one rest; ~20 s); the Ramp (~40 s) | None: you go down the way you came |
| Greyvein Crags | The mine road (switchbacks); the crag path | Scree chutes |
| The giant trees | Climbable trunks with a rest fork at most every 40 studs (a full stamina bar climbs about 61) | Back down the trunk; a fall of 58 studs or more kills |
| The Throat's walls | The fixed rope (two 40-stud pitches); the gallery's ladders; the Spray Steps; the talus at the canyon mouth | The leap off the falls |
| The mountain wall | Never | — |

Rules:
- Every escarpment and butte has at least two ways up: one slow and safe, one fast and exposed. On the Anvil both are risky, by design.
- Mantle steps are 6 studs or less. The limit is 6.5, or 7.8 with a jump.
- Faces that must not be climbed look sheer or wet (B7), and designed cliffs have no ledges to mantle.
- Every Climbable route (trunks, ropes, chimneys, cracks, rope ladders) has a fork or ledge to rest on at most every 45 studs. A full stamina bar climbs about 61 studs (`ClimbSpeed` 5.5, `ClimbDrain` 0.09/s), and at 0 you fall.
- Giant trees keep today's climbing stamina (`ClimbDrain` 0.09/s). The rest forks do the work, so no new stamina rule is needed.

### 5.3 Crossings

There are 23 crossings in all (7 today), about 400–700 studs apart along each big water edge. Each is a natural ambush point. Swimming always works too, at 8 studs/s.

| Kind | Count | Where |
|---|---|---|
| Fords (0.5–1.2 deep) | 8 | Breaks Ford, the Mill Ford and the river-mouth ford in the Bottoms; the High Ford and the Lip Ford on the plateau stream; one each on Greenbrook, Shelf Creek and Tallgrass Run |
| Rope bridges | 3 | The Upper and Lower Swings over the Throat; the Elderbrook ravine bridge (a 45-stud span) |
| Logs | 4 | The fallen giant over the Elderbrook ravine; the Throat's log jam; a log over the plateau stream; a log over Greenbrook by Root Hollow |
| Built crossings | 3 | The dam crest (220 long); the Millrace weir walkway (30); the Causeway's duckboards |
| Stepping stones | 5 | The Drowned Pines; Greenbrook; the Sump's outflow; Lakehead Run above the falls; Shelf Creek by Echo Run |

### 5.4 Treetops

- **The Canopy Grove** (16): about 250 studs of route through five crowns, with platforms 40–80 up, three rope walks (20–40 long) and two lodged limbs.
- **Single giants with a hide:** the Lone Elder (1, ~105 up), the Sentinels' Perch (19, ~130), the Hunters' Rest platform (12, 40).
- **Rules:**
  - Rope walks never break.
  - The sway is drawn on each client only; the surface you walk on doesn't move.
  - Footsteps on planks are loud.
  - Hounds can't climb and give up after 12 s.
  - Crown parts keep `CanQuery` off, so the Roll Call can still lift its display above the canopy.

### 5.5 Swims

| Swim | Distance | Time at 8/s (with sprint strokes: 11.5/s, about 14 s per stamina bar) |
|---|---|---|
| The Old Jetty to Kettle Island | ~370 | ~46 s (~34 s) |
| Kettle Island to the Stack | ~300 | ~38 s (~28 s) |
| The east bluffs to Kettle Island | ~180 | ~22 s (~16 s) |
| Across the Highwater tarn | ~300 | ~38 s |
| The Cauldron, the quarry pond | 40–70 | under 10 s |

You can't use a weapon while you swim, and hounds avoid deep water.

### 5.6 Fast lanes

The fast lanes are natural and each one has a cost. There are no ziplines unless you choose the old ore cableway (question 4).
1. **The river's current.** In the Bottoms and the Throat the water pushes downstream at 4–8 studs/s. This is a new current zone along the river samples, using the same `MovementController.applyImpulse` hook the Floodgate needs. That hook doesn't exist yet (arena-events.md §9 plans it), so T12 builds it if Phase 3 hasn't. Swimming downstream reaches 12–16 studs/s with no stamina, but you are exposed and can't fight.
2. **Snow and scree chutes.** On snow or the scree material steeper than 20°, a slide doesn't time out until the slope eases. Today a slide ends after 3.5 s at most (`Slide.HardMaxTime`), so this is a small MovementController change. Up to 26–28 studs/s, and loud: the scree rattles. Scree is the Basalt base material (`LS_Scree1`), and the rule reads the base material, so Basalt stays reserved for scree.
3. **The log chute** at the Sawpit: a `Chute` tag with the same rule. One way, down to the lake.
4. **Leaps into deep water:** the Great Falls (76), Watchtower Ridge (70), the Leap at Lakehead (66) and the Stack (45).
   - New rule: water breaks a fall only if it is at least 4 studs deep and the fall is at most 90 studs (`Config.Movement.FallDamage.WaterCushionMaxHeight = 90`, `WaterCushionMinDepth = 4`). Designed leaps stay at 80 or less. The margin is needed because `MovementService` measures a fall from its highest point (a jump adds 3 studs) and the Floodgate raises the water. Today any water voxel within about 4 studs of the landing breaks any fall (`MovementService.inWater`), so the shallow rapids under a rope bridge would save you.
5. **Game trails:** clear ground where you can keep up a sprint-and-jog pace (~17.8 studs/s). They are predictable, so they're easy to ambush.

### 5.7 Sightlines and cover

| Where | Typical clear view | Made by |
|---|---|---|
| Forest | 60–120 studs, which is bow range | the stand-density field (×0.35–1.75) |
| Thickets (the Elderwood floor, young growth) | 30–60 | ferns, saplings, fallen trees |
| Glades and clearings (about 30) | 150 or more | open ground for ambushes |
| Open ground (the Green, the Tallgrass, the beaches, the plateaus) | cover at least every 150–250 studs | folds, boulders, lone trees, the Lone Stone, driftwood |
| Ridges and lookouts | 400–1,000 or more | for scouting; far beyond bow range |

Cover heights:
- High cover starts at 6.3 studs, enough to hide someone standing.
- Low cover is 3.6–4.5 studs, enough to hide a crouched head (4.3).
- Anything 1.8 studs or lower doesn't count as cover.

### 5.8 Finding your way

Landmarks come at three scales:
- **Large, seen from every clearing, shore and ridge:**
  - **The Spire's Beacon plume.** By day it is a pale column of smoke rising 300–400 studs from the fire basket and leaning with the wind; by night the embers light it from below. It is drawn as a beam on the Spire, which is Persistent, so it shows from anywhere in the Vale.
  - **The rim,** with one shape per side:
    - north, the Twins: two snow peaks above the Frostback;
    - east, Greyspear: a pyramid peak behind the Anvil;
    - south, the Gap: a notch in the far wall beyond the lake;
    - west, the long Rust Wall of the Shelf.
  - **And:** Lantern Peak with its cab lit at night, the snow of the Frostback, and the spray plume of the Great Falls.
- **Medium, 40–100 studs tall,** which hide what's behind them and invite a climb: the Lone Elder, the Sentinels, the Canopy Grove, the Anvil, the Lone Stone, the Greyvein headframe, the Redoubt's tower, the Watchtower, the Stack and the quarry derrick.
- **Small, every 100–200 studs:** the features in §4.

The world also gives cues without any UI:
- the sun's path from east to west;
- every stream runs toward the lake, to the south or south-east;
- the roar of the falls;
- the Knell from the Spire.

The HUD helps too:
- The compass keeps the Spire marker. It adds the name of the region you are in, a tick for each named site within ~250 m once you have seen it, and the next border.
- A map page in the Menu (M) shows the Vale, the sites you've found and the border stages. Today there is no map screen (arena-events.md §1).

Every lookout sees at least two sites within 1,000 studs, and the Beacon plume. Contenders more than about 1,024 studs away aren't drawn, because they stream out (§7.4). A lookout shows you people within that range; beyond it you read the land, smoke, the falls and the border.

Footsteps carry 90 studs today (`AudioController` `RemoteRange`). The planks of a rope bridge (120 studs) and the echo in a cave (1.5×) need a longer range for those surfaces only; T12 adds it.

---

## 6. Loot and pacing

### 6.1 Loot markers by region

Loot grows with the number of contenders and with the walking a big map costs, not with its area: eight times today's density would be about 1,450 markers.

| Where | Crates | Ground | Forage | Markers | Expected items per round |
|---|---|---|---|---|---|
| The Spire and plaza | 8 tier 3 (the 4 crate slots and 4 more) | 6 tier 3 | — | 14 | ~28 |
| The Green's edge (r 190–300) | 8 runner's caches + 6 tier 2 | 16 tier 1–2 | 4 | 34 | ~55 |
| Ring B, 7 sites | 7 (6 on the runner's table, so a basic weapon each, and 1 tier 2) | 18 tier 1 | 7 | 32 | ~37 |
| Ring C, 12 sites | 26 tier 2 (3 at each hot zone) | 34 tier 1–2 | 10 | 70 | ~95 |
| Ring D, 10 sites | 18 tier 2 (a weapon and a vest at every site) | 22 tier 2 | 10 | 50 | ~67 |
| Tier-3 prize spots (9, 10, 14, 16, 22, 24) | 6 tier 3, two stocked in any round | — | — | 6 | ~6 |
| Trails, camps and small features | — | 74 tier 1 (60 on trails, 14 at camps) | 14 | 88 | ~56 |
| **Total** | **79** | **170** | **45** | **294** | **~345** |

How these compare with today and what has to change:
- **Today:** 181 markers (52 crates and 129 ground) give about 240 items per round. v3 gives about 1.45× the items, about 14 per contender against 10.
- **Why more:** each contender can reach only a small share of the Vale in a round, walking costs time, and every adventure site has to pay.
- **Config.Loot changes:**
  - `GroundSpawnChance` goes from 0.65 to 0.6.
  - A new `SiteStockChance` of 0.85 applies to ring C and D crates, and a new `PrizeStockCount` of 2.
  - A new `LootTables.Forage` holds berries and apples, for the forage markers at berry thickets, fruit trees and the orchard.
  - Crates keep 2–4 items.
- **The telemetry check:** the median number of items a contender holds at 5:00 and at 10:00 should sit between today's and 1.3× today's. If it runs higher, lower `GroundSpawnChance` first.
- **The planner:** the markers come from a new v3 loot planner (§7.8). Today's markers come from the retired v1 layout.

### 6.2 Runner's caches

The 8 runner's caches move:
- **Where:** one per 45° sector at the Green's new edge, r 230–300 (today r 150–193). Each stands by a landmark, in sight of its three nearest plates.
- **The crate:** a tier-2 crate on the runner's table (a hunting knife or two throwing knives, a water bottle and one tier-1 roll), as today.
- **Why there:** they sit 180–250 studs from the plates, 9–12 s at a sprint, just past one sprint bar, so running away still beats the scrum.
- **The pole:** the canvas pole grows from 10 to 14 studs, because it is now seen from about 200 studs instead of 110.
- **After the v3 terrain:** re-place the caches and re-measure their `groundY`, then re-run QW7's sightline check.

### 6.3 Hot zones

- **The Spire:** the 14 tier-3 markers and the Offering. You rush it or run, as today.
- **Three secondary hot zones, about 120° apart.** Each can be seen from some of the plates and each is tied to a Warden event:
  - **Greyvein Mine** (60°): its headframe stands on the skyline, in Rockfall country.
  - **Stillwater Isles** (165°): across the open water from the southern plates, and the Lure's favourite.
  - **The Old Redoubt** (275°): its tower stands on the Shelf's rim. The open Shelf draws Ember Rain, and the Redoubt sits in its own Sector Lockdown cell.

  The Mine and the Redoubt hold 3 crates and 4 ground markers each. The Isles hold 2 crates and 2 ground, with the Stack's prize spot as the third crate.
- **Magnets without much loot:** the North Beach, the fords, the Great Falls and the dam crest.
- **Danger scoring:** `ArenaLayout.dangerAt` is re-based. The centre's weight runs out over r 40–520 (today 40–260). Open ground (the Green, the Tallgrass, the plateaus, the beaches) and crossings (fords, bridges, the dam crest) add to it.

### 6.4 Different every round

These are seeded at the Countdown from the round's seed, and logged:
- 85% of ring C and D crates are stocked, and 2 of the 6 prize spots.
- 4 of the 7 optional springs flow; the dry ones show cracked mud.
- 3 of the 14 camps smoulder, and the bothy and the Hunters' Rest may show smoke.
- At most one rope crossing is down (a broken-bridge model). It is always one with another crossing within 300 studs, and never both Throat bridges.
- The border drifts toward a seeded side: during stage 1 in a full round, from the start in a small one (§6.5).

A veteran knows the Vale, but never the round.

### 6.5 The border closes in stages

| Stage | Warning card | Moves | Radius | Speed | What it does |
|---|---|---|---|---|---|
| 1 · the Reaches close | 2:15 (135 s) | 3:15–5:15 (195–315 s) | 1,800 → 1,250 | 4.6 studs/s on the radius; at most 6.25 on the ground, on the side away from the drift | Takes the outer half of the Vale; ends 30 s before Roll Call 1 (345 s) |
| The night holds | — | 5:15–8:10 | 1,250 | — | Cold Snap or the Night Hunt |
| 2 · the Heart | 7:10 (430 s) | 8:10–9:25 (490–565 s) | 1,250 → 800 | 6.0 studs/s | The dawn beat. The Offering's warning comes at 8:20, 90 s ahead (`Config.Events.FeastWarning` 45 → 90 when r0 is 1,200 or more). |
| 3 · the final closing (today's) | 9:30 (570 s) | 10:00–13:50 (600–830 s) | 800 → 35 | 3.3 studs/s on the radius; at most 4.2 while the centre slides back | As today, but from a wider start (today 640 → 35 at 2.6 studs/s) |
| The Last Stand | — | 13:50–14:45 (830–885 s) | 35 → 0 | — | Unchanged |

Rules:
- **Drift.** Each round has a seeded bearing. During stage 1 the circle's centre moves up to 200 studs from the Spire toward it, so on that side the ring still reaches r ~1,450 and one outer region stays open longer. Stage 2 keeps that centre, and stage 3 slides it back to the Spire (`ArenaService.centerAt` today slides the centre only during the last stage).
- **The Spire always stays inside.** It is at least 1,050 studs inside the ring after stage 1 and at least 600 after stage 2. The final stage ends on the Spire, and the Last Stand keeps `FinalSpireGap`.
- **Speed.** No point of the ring moves faster than half a jog (6.5 studs/s), measured on the ground, not only on the radius. When the centre drifts, the side away from the drift closes faster than the radius shrinks: 550 + 200 studs in 120 s is 6.25 studs/s. That is why stage 1 takes 120 s and stage 2 keeps stage 1's centre. A 90 s stage 1 with a 300-stud drift would sweep the far side at 9.4 studs/s, faster than a swimmer (8). On the side away from the drift, a contender at the edge when stage 1 starts needs about 60 s at a jog to get inside, and the card gives 60 s before the wall moves.
- **Small rounds** scale every radius by r0 / 1,800. With 8 contenders, for example: 1,039 → 721 → 462 → 35. When r0 is under 1,200 the drift comes earlier and bigger: the start circle's centre already sits 0.25 × r0 toward the bearing, stage 1 keeps it, stage 2 brings it back to 0.11 × r0 (the full round's 200 studs, scaled) and stage 3 to the Spire. No point then moves faster than 6.2 studs/s, and the Spire stays at least a third of r0 inside every ring.
- **Warnings.** Stages 1 and 2 warn 60 s ahead and stage 3 warns 30 s ahead, as today. Each stage gets:
  - its broadcast card;
  - its threat-line beat ("THE BORDER · HEAD FOR THE SPIRE · 0:45");
  - a tick on the compass;
  - the wall.

  If Roll Call 1 is still running at 7:10, stage 2's card waits until the show ends. Even with 22 fallen it ends by about 7:30 (`DayCycle.recapDuration`), which still leaves about 40 s.
- **The Roll Call trap (from the audit).** `ArenaService.updateRollCall` (line 577) treats `elapsed >= ShrinkStartTime` as "the border is moving", and that turns a Roll Call into its list-only version. It must use the final stage's start (600 s). Stages 1 and 2 never overlap a Roll Call.
- **One function.** All of this lives in one shared module: `Shared.Border.radiusAt(elapsed, r0)` and `centerAt(elapsed, seed)`. ArenaService, RoundService, HUDController, ThreatLine, ArenaController and the Warden Director all read it.

### 6.6 Round length: keep 15 minutes

- **It fits.** The staged border fits the bigger Vale into 15 minutes. By the Offering (9:50) a rival is about as far away as today (~190 studs against ~152).
- **Nothing else moves.** The Offering (590 s), the final closing (600–830 s), both Roll Calls and the Last Stand stay exactly where today's code and the Roadmap expect them. Roadmap Phase 5's "done when" checks that the Standard timeline is unchanged.
- **Session length.** Roblox players judge a game in its first minutes and drift away from long rounds, and 15 minutes is already long (PlayabilityPlan P1 and P10).
- **The fallback.** If playtests show the first day is too rushed, go to 18 minutes. The extra 3 minutes go into day 1 (`Config.Round.DaySchedule`), and stage 1 moves later by the same amount (question 2).

### 6.7 The Warden Director's slots, re-based

arena-events.md §3, adjusted for the v3 Vale in full rounds:

| Slot | Today | In the v3 Vale |
|---|---|---|
| 1 · 2:30 | a light event | Only the Lure, a pull rather than a push. It lands inside the stage 1 circle and is broadcast at least 15 s after stage 1's card. In small rounds (r0 under 1,200) it runs as today. |
| 2 · 4:15 | the first big hazard | Unchanged, but its zone must lie inside the stage 1 circle. It overlaps stage 1's move by design. |
| Night | Cold Snap or the Night Hunt | Unchanged; the warmth sources are in §6.8 |
| Dawn · 8:10 | a short event | Dropped while stage 2 moves, because the border is the dawn beat and the Offering's earlier warning (8:20) opens its quiet window. Small rounds (r0 under 1,200) run it as today and keep the 45 s Offering warning, so their quiet window still starts at 9:05. |
| 5 · 10:30 | herding, radius ~560 → 390 | radius ~700 → 485 |
| 6 · 12:00 | radius ~325 → 170 | radius ~400 → 200 |

That still gives a beat every 1–2 minutes: 2:30, 3:15, 4:15, 5:45 (Roll Call 1), ~6:40 (the night), 8:10, 9:50, 10:00, 10:30 and 12:00.

These rows change arena-events.md §3 for full v3 rounds only. Roadmap Phase 2a still builds all six slots (its "done when" runs on today's arena), and the Director skips the Dawn slot only while a stage-2 border is moving.

### 6.8 Warden events in the new Vale

| Event | Where it plays in v3 | What changes |
|---|---|---|
| Ember Rain | Open ground and groups of contenders: the Green's rim, the Tallgrass, the Shelf plateau, the High Country, the shores, the mine yard, the quarry | The radius stays 90–150, so the edge is never more than 150 studs away. The Director aims at groups, and may run two zones in Slots 2 and 5 when 13 or more are alive. Stone cover: caves, the Redoubt's cellar, the adits, the mill, the gatehouse, the bothy, the station and the Spire's alcoves. The giants' crowns count as dense cover (half damage), read from a new tree-cover channel in TerrainData. |
| The Miasma | The Sump, the Drowned Pines and Stillwater's western reeds | One zone per marsh, from the layout's list. The fog rises from 36.5 to about 44. You escape up the Sump's rim slopes, onto the stilt hut (46) or the duckboard platforms. Fog particles are capped. |
| Splice Hunt and the Night Hunt | 16 hatches, at least one in each region except the Green and the Crest, in outcrops and old foundations. Never inside a cave, because snakes released into tunnels is a source beat. No release once five or fewer are alive, as arena-events.md already rules. | Hounds are released within about 200 studs of the chosen group. Long trips are split into legs along the trails, because of Roblox's 20,000-node path limit. Refuges: the giants, the Anvil, deep water. Caves and the Jumbles become close fights. |
| The Floodgate | Highwater Dam's sluice, then the plateau stream, over the Great Falls and down the Throat | The active stretch is about 820 studs, from the Lip Ford over the falls to the canyon mouth (the surge takes about 27 s at 30 studs/s), and the event runs only when someone is within 100 studs of it. Tells: the dam's horn, then the falls thin to a trickle for about 8 s, then roar. Escape onto the canyon's ledges, the bridges, the gallery or the Spray Steps. Anyone swept over the falls lands in the Cauldron and lives (the water-cushion cap of 90 leaves room for the raised water). About 2–3k voxels change in all, written at most 1–2k per step. |
| Rockfall | 12 stretches: the Rust Wall (4), the Throat's walls (3), the crags and the Jumbles (3), the Lakehead cliffs (1), the quarry's high bench (1) | The same rules. The boulders stay where they land, as new cover. |
| Cold Snap | Night 1, inside the stage 1 ring (r 1,250, drifted up to 200 studs) | About 32 warmth sources and shelters inside r 1,450, so that whichever way the night ring drifted, warmth is within about 300 studs of anywhere inside it (the promise relaxes from 250): the camps' fire rings, the Spire's braziers, the Millrace, Charcoal Hollow, the Hunters' Rest, the mine's forge, the Redoubt's cellar, Kettle Island's camp, the caves and the rock shelters. The remote hearths (the bothy, the station, the orchard) sit outside the night ring in most rounds, on purpose: the cold pulls people in. |
| Sector Lockdown | About 40 lockdown cells inside the current ring, each at most ~500 studs across, bounded by ridges, rivers and cliffs. The Green is never sealed. | It seals one cell where contenders are idle, or two neighbouring cells when 13 or more are alive, with a 30 s warning; the farthest point is at most 250 studs from a way out, 19 s at a jog. Never equal wedges, never on a timetable. The walls follow natural edges, so there are fewer panels. |
| The Lure | Contested open spots: the Green's rim, Breaks Ford, the dam crest, the Tallgrass, the North Beach, the Redoubt's courtyard, the mine yard, Kettle Island | Three gifts when 13 or more are alive (two today), always inside the current ring |

Two rules carry over unchanged:
- Every zone can be left at a jog within its warning (arena-events.md §5).
- There is no new drought event, because a drought that leaves only the lake is too close to a source beat. Variety comes from the springs instead (§6.4).

---

## 7. Technical plan

### 7.1 TerrainGen v3

**Split it into modules.** TerrainGen is 142,667 characters, 71% of Roblox's 200,000-character script cap, and v3 adds list-driven carving and a backdrop writer. So the first job is to split it into a driver and child modules:

| Module | What it holds |
|---|---|
| `TerrainGen` (the driver) | `start`, `generate`, `measure`, `verify`, `check`; the progress attributes; `applyLook` and `applyStreaming` |
| `.Grid` | Grids stored in buffers, and the index maths |
| `.Shape` | Height profiles, noise, landforms, escarpments, canyons, peaks, the easing of the plaza and site footprints, the mountain wall, the backdrop heights |
| `.Water` | Channels from the layout's lists, lakes, marshes, falls, pools, fords, springs |
| `.Erode` | Droplet and thermal erosion on the coarse grid |
| `.Materials` | The material and MaterialVariant of every column; Expanded Terrain's material slots |
| `.Voxels` | The arena chunk writer, the backdrop writer, caves, the plate trench, the lobby island |
| `.Data` | The TerrainData channels and the client biome grid |
| `.Checks` | Every check, old and new (below) |

**Grids and memory.**
- **Today:** G0 −960, FN 480 (4-stud cells) and CN 240 (8-stud cells), with about 35 dense per-cell Luau tables, about 129 MB in all. The same layout stretched to the new size would need about 1.16 GB, which would likely run Studio out of memory.
- **v3:**
  - A fine 4-stud grid covers only the play area and the wall: ±1,952 (FN 976, 0.95M cells).
  - A coarse 8-stud grid covers ±2,752 (CN 688), offset 100 cells from the fine grid.
  - The arrays live in `buffer`s: f32 for heights, levels and distances; u8 or u16 for masks and materials. That is about 100 MB.
- **The backdrop:** a new `writeBackdropChunk` writes everything past r 1,952 straight from the coarse grid. It has no channels, caves or water; its materials follow slope and height, under a thin shell.

**Relief: the knobs that make v2 flat, and their v3 values.**
- **Height profiles** (`R_KEYS`, lines 317–336): 12 keys, {0, 240, 450, 700, 950, 1,200, 1,450, 1,700, 1,880, 2,150, 2,450, 2,750}, with one profile per region of §3.
- **`hillsNoise`** (lines 425–443), today about 60 studs top to bottom. The v3 values give about 150–180 studs top to bottom; the slope budget in §3 still applies.

  | Noise layer | Today | v3 |
  |---|---|---|
  | warp | 85 @ 460 | 180 @ 900 |
  | big | 14 @ 340 | 34 @ 760 |
  | mid | 6.5 @ 190 | 14 @ 380 |
  | knoll | 4.2 @ 110 | 7 @ 170 |
  | bump | — | unchanged |
  | ridged | 40 @ 270 | 85 @ 560 |
- **Landforms** go from 9 (lines 401–409) to about 35 ridges, mesas, knolls and hollows. On top of those come named shapes from the layout:
  - escarpments: the Rust Wall, the Lakehead cliffs, the Breaks, the Anvil's ring, the crag bands;
  - canyons: the Throat, the Elderbrook ravine;
  - peaks: Lantern Peak, the Frostback, the Anvil, the Greyvein crag, the Shelf tor;
  - basins: the Green, Stillwater, the Sump, the tarn, the quarry pit, the Sinkhole.
- **`meadowHeight`** (446–448): r / 150 becomes r / 240, and the rim's `sstep(105, 175)` becomes `sstep(170, 290)`.
- **`mountainUplift`** (459–465):
  - the wall term: 88 + 26·N becomes 150 + 40·N;
  - the massif: 34 + 190·rg^1.7 over `sstep(10, 210)` becomes 60 + 650·rg^1.7 over `sstep(10, 520)`;
  - the envelope scales: 420/260/300 become 900/600/700.
- **The basin floor** in `naturalAt` (491): one floor per basin, not one for the single lake.
- **Erosion** (620–634): droplets go from 110,000 to about 870,000 over the bigger coarse grid; their lifetime goes from 48 to 72 (longer gullies); thermal erosion is unchanged.
- **Snow:** `SnowLine` goes from 300 to 540. The audit proposed 640; this is lower so the Frostback inside the border is snowy. North-facing slopes get patchy snow from about 500.

**Water.**
- **Today:** one river. `CHANNELS` numbers the River 1, the Creek 2 and the Outflow 3, and their behaviour is keyed on that number (lines 994, 1036, 1131, 1910, 2101). The lake, marsh, field, pool, falls top and island are each a single shape (252–265).
- **v3:** lists built from the layout's Rivers, Streams, Lakes, Marshes, Falls and Pools, with flags on each channel (kind, gorge, minimum half-width, muddy, reach, current).
  - `carveFalls` (1169–1252) runs once per falls. The Great Falls needs a bigger plunge radius (about 40) and reach (about 120).
  - `carveLake` (1254) and `carveMarsh` (1322) run once per body, each with its own islands, and the shore style comes from the nearest lake (1891–1907, 1968–1981).
  - Crossing ends (1441) are shaped for every Log, Footbridge and RopeBridge crossing; today only GorgeLog and GorgeFootbridge, by name.
  - The waterfall particles and mist (2780–2812, 3195) and the cascade pools (3459–3466) come once per fall.

**Caves.**
- `CAVES` (2160–2179) is already list-driven and copes with 10.
- New support for:
  - two mouths per cave;
  - a chamber, a squeeze and a drip pool;
  - at least 6 studs of headroom after the 4-stud voxels eat about 2.
- With Expanded Terrain on, the rock above any terrain cave must be at least 16 voxels (64 studs) thick; any thinner stretch is lined with cave-kit meshes.
- Thin rock features follow the same rule: the Stack, the Anvil's arch, tors and rock pillars are meshes (CliffsReal2), not terrain.
- The Greyvein Workings and the Jumbles are meshes inside a carved space.

**The mountain wall, the Boundary and the backdrop.**
- **`TerrainGen.Wall`** (1523): offset 2, wobble 2.5, face 3.8, upper 1.4 and the 18-stud step all stay; the step is what stops anyone walking, jumping or mantling out. Height goes from 34 to 60, `upperRise` from 30 to 120, and the apron from 60 to 90.
- **`wallFoot`** (1529): its noise radius goes from 680 to `MountainRadius` (1,846), keeping the ~90-stud wobble.
- **`shapeMountainWall`:**
  - the scan band (1551) goes from 580/760 to 1,740/1,960;
  - `WALL_BUCKETS` (1524) goes from 1,440 to 4,320;
  - `W3` (1582) stays 12 buckets, which is now ±1°.
- **`buildBoundary`** (2929–2986): 72 walls become 144 at R 1,900, and `topY = hmax + 260` stays.
- **The massif** comes from the coarse grid: a crest 700–1,000 high at r 2,150–2,450, falling to about 120 at r 2,750.

**Materials.**
- With Expanded Terrain on, use tinted material slots on the existing MaterialVariants: several grass shades, wet and dry earth, mossy and bare granite, iron-stained granite for the Rust Wall, and snow.
- Port the voxel writes from the `SolidMaterial` channel to `SolidMaterialIndex`.
- Keep to about 12 distinct terrain texture sets, because terrain textures aren't streamed.
- Each slot keeps a base material, and `Config.Movement.Surfaces`, the footstep sounds and the chute rule all read the base. So a slot's base decides how it walks and sounds, and Basalt stays reserved for scree.
- Check that Cold Snap's per-client `SetMaterialColor` still works with slots.

**The plaza rim: no trench or dip visible past the platform edge.**

How it works today:
- The terrain has one ring-shaped trench under the 24 plates, with its floor at y 34.
- The 120-stud SpirePlatform covers it, and its deck edge is at r 60.5.
- Cells straddling that edge used to leave a dip up to 3 studs deep all round the platform.
- Commit 74dbf21 fixed this: no trench cell may have its centre beyond r 59 (`TerrainGen.Tube.maxCentreR`), and the ground was measured at or above the deck top from r 61 outward.

v3 keeps that fix and makes it impossible to lose again:
1. **Fixed inputs.** `validate()` refuses any change to Center, PlazaY 46, PlazaRadius 62, PlinthRingRadius 52, PlateTube, the SpirePlatform's pivot, or `Tube {intrude 1.8, maxCentreR 59}`.
2. **A protected disc.** Every new pass is masked to zero inside r 100 and fades in over r 100–140: big relief, landforms, erosion droplets, thermal erosion, channel carving, terrain decals. Only `shapeSpecials` writes inside that disc. Greenbrook stays at least 150 studs from the plaza's edge.
3. **No moat.** The blend ring between r 64 and 90 is clamped to no lower than PlazaY − 0.3. Today its lerp can dip below the plaza where the meadow tilts toward the lake. The meadow may fall away only beyond r 90, at 1 in 8 or gentler.
4. **Hard gates in `Checks.plaza`.** A failure stops the run and reports it.
   - Inside r 40, no sample is more than 0.25 off y 46 (as today).
   - On 120 bearings, the ground at r 61–70 is never more than 0.3 below y 46.
   - New sightline test: from eyes 5.2 studs above the ground at r 70, 90 and 120, on 48 bearings (on the plates and between them), rays aimed at the deck edge (r 58–62, y 45) must hit the SpirePlatform, or terrain at y 45.5 or higher. That way no trench wall can be seen from outside.
5. **`Checks.tubes`** stays as today: terrain at least 3.6 studs from every plate's axis, and a 4.8 × 4.8 block and an r 2.8 sphere both drop to the floor at every plate.
6. After each run, also re-run P.verify's plate checks and the PlateCollar placement (`Populate.Sites.core`, commit 74dbf21).

**Checks.** `TerrainGen.verify()` runs them all, and `generate()` ends with a pass or fail summary.

| Check | Passes when |
|---|---|
| plaza | the four gates above |
| tubes | as today (above) |
| water | every body renders (its level is in the lower half of a voxel layer); nothing leaks over a bank; fords are 0.5–1.2 deep |
| mountains | none of the wall's sectors can be walked, jumped or mantled up to the Boundary. The radii come from the layout (start ring 1,788–1,800, Boundary 1,900), replacing the hard-coded 560/800 (line 3885), 628–640 (3910), 712 (3927) and 640–712 (3956), and ±640 at line 3631. |
| thickness | with Expanded Terrain, no terrain over caves, rims or arches is thinner than 16 voxels |
| walkability (new) | the slope budget holds in every region; every trail is 30° or less; every escarpment and butte has the ways up listed in §5.2 |
| reach (new) | a coarse path search over walkable cells reaches every site and every crate from the Spire on foot |
| caves (new) | headroom of 6 studs or more; two mouths where the design says two; no Warden hatch inside |
| relief (new) | each region's measured top-to-bottom is within ±15% of its target in §3 |
| measure | re-measures `POIHeights`, `CrossingHeights` and `RunnerCaches.groundY`, and prints them for ArenaLayout |

### 7.2 Data limits

| Limit | Today | v3 |
|---|---|---|
| Script source cap (200,000 characters) | ArenaLayout 76,780; TerrainGen 142,667; Populate's Sites 58,931 | ArenaLayout splits into child modules (Water, Relief, Sites, Trails, Scatter, Loot, Regions), each under ~60k. TerrainGen splits as in §7.1. Sites splits into a core module and a kits module. |
| TerrainData (an 8-stud grid) | n 176, origin −704. H takes 82,698 characters, and S, C, M and W 41,398 each, in 5 modules. | n 480, origin −1,920, which covers the Boundary. Details below the table. |
| Client biome grid | None. AudioController calls `getBiome` 5 times every 0.2 s. | `Shared.BiomeGrid`: 16-stud cells, 240 × 240 bytes (57,600), about 77k characters in one module |
| Terrain voxels | 1.93M cells (out to r 920) | About 13M cells with today's 12-stud shell, or 27–30M with the 64-stud shell Expanded Terrain needs. That is far inside the engine's ±32,000-stud extents, and each write stays far under its 4,194,304-voxel cap. |
| Place file (100 MB) | — | Terrain grows about 8.6×. With Expanded Terrain it is saved as its own asset (250 MB limit) outside the place file. This is the recommended setup. |
| Server instances | 28,465 scenery models, 121,982 instances | At most 90k models and 400k instances (§7.5) |

How TerrainData's channels are stored in v3:
- **H** (u16) takes 614,400 characters, in 4 parts.
- **C, M and W** (u8) take 307,200 characters each, in 2 parts each.
- **S** is dropped: it is written but never read.
- **T**, a new tree-cover channel for Ember Rain, takes 2 parts.
- That makes 12 modules and about 1.84M characters.
- The base64 strings are split only at multiples of 4 characters. The index module joins the parts, so `ArenaLayout.loadGrid` and `gridSample` don't change.
- The server decodes it once, in about 0.2 s (an estimate).

### 7.3 Generation time

| Step | Today | v3 (estimates: measure them) |
|---|---|---|
| `TerrainGen.generate` | ~3 s | 30–60 s. Chunks go from 716 to about 1,450 at 128 × 128 studs (5,760 at today's 64), erosion work grows 6–7×, and the grids move to buffers. Parallel Luau (Actors) can work out the columns; the voxel writes stay serial. |
| TerrainData and the biome grid | under 1 s | ~5 s |
| Populate, every step | ~11 s | 60–150 s |
| The loot planner and WaterPoints | ~1 s | ~5 s |
| A full rebuild | ~15 s | about 3–4 minutes |

Rules for running it:
- Edit mode only, never at runtime.
- Keep `maybeYield` at 30 ms and keep the progress attributes.
- Run a full rebuild only when nobody else is editing terrain (in the workbench copy, §9).

### 7.4 Streaming and level of detail

**Streaming settings** (`TerrainGen.applyStreaming`):

| Setting | Today | v3 | Why |
|---|---|---|---|
| `StreamingTargetRadius` | 1,024 | 1,024 (keep) | A streamed disc is then about the size of today's whole arena |
| `StreamingMinRadius` | 128 | 128 (keep) | Roblox advises a small minimum so that phones short of memory can scale down. Raise it to 256 only if the phone test (T14) shows pop-in at sprint (21 studs/s) or slide (28) speed. |
| `StreamOutBehavior` | Default | Opportunistic | Otherwise a contender who crosses the Vale keeps all of it loaded until a phone runs out of memory |
| `StreamingIntegrityMode` | PauseOutsideLoadedArea | PauseOutsideLoadedArea (keep) | The mode Roblox recommends: it pauses you only when you move into ground that hasn't loaded at all. MinimumRadiusPause would pause you whenever the minimum radius isn't fully in, which happens more often on a phone. |

- Only the Spire, the 24 plinths and the 8 runner's-cache poles are Persistent, as today. All scenery stays Atomic.
- Set `ModelStreamingBehavior` to Improved by hand.

**Past 1,024 studs**, models without level of detail vanish and terrain drops to a coarse version. So:
1. **Landmarks.** Set `Model.LevelOfDetail` to SLIM (or StreamingMesh) on landmark-sized pieces: cliff and outcrop groups, buildings and towers, the headframe, the dam, the giants, cave mouths and the dressing on the mountain wall.
   - Test two or three first. How SLIM treats our cut-out leaf cards is unverified.
   - One large map reported an 8–12 ms cost in `updateInstancedClusters2`.
2. **Far forests.** Group trees into Models of about 128 × 128 studs (SLIM ignores Folders) and try SLIM on those.
   - The fallback is about 20 Persistent low-poly canopy shells, one per forest region, with no collision, queries or shadows.
   - DetailController shows them only past ~900 studs (past 420 on Low).
3. **Forest floor colour.** Darken the terrain under forests to a forest-floor colour, so the coarse terrain still reads as woodland.
4. **Haze.** Tune Atmosphere so the haze thickens between about 500 and 1,500 studs. It hides level-of-detail and streaming seams; phones may draw only about 500 studs.
5. **Mesh streaming.** Turn on `Workspace.MeshStreamingAndImprovedLoDs` (a manual switch; restart Studio and test in a published place). It is the only setting that cuts mesh triangles with distance: Roblox's test scene went from 1.08M to 0.40M.
   - Then look at the trees at 250, 500 and 1,000 studs.
   - If the crowns thin out, give each tree a far mesh (300–800 triangles) that is swapped in past about 300 studs.
6. **RenderFidelity** stays Automatic.

**Occlusion culling** now uses terrain on every platform, so the ridges and basins hide most of the Vale from any valley floor. Trees don't hide each other from the culler; terrain and big opaque rocks do.

**Spectating and the plates:**
- `PlayerService.onSpectateTarget` (lines 1032–1048) calls `RequestStreamAroundAsync(root, 3)` before it sets `ReplicationFocus`.
- SpectateController fades out and shows "moving to …" while the target is more than 1,024 studs from the camera.
- PlayerService already streams around each plate at the Countdown, with a 4 s timeout (line 729). Re-time that on a phone.

**Distant contenders.** With Opportunistic streaming, contenders more than 1,024 studs away vanish, but that is beyond any weapon's range. `EnableSLIMAvatars` can be tried as an option.

### 7.5 Density budget for scatter

**Why the scatter can't just scale.** Each scatter rule fills its density × the biome's area (`Scatter`, line 638). With 7.9× the area that would mean about:
- 228k models and 976k instances;
- 130k shadow casters;
- 330M triangles at full detail.

**Zones** (a new `Ctx.zone(x, z, class)` multiplier) for what the server places:

| Zone | Where | Density compared with today |
|---|---|---|
| Core band | The Green's edge (r 190–330), which the plates look at; everything inside r 400, where the finale is fought; site footprints plus 30 studs; within 12 studs of trail centrelines and 20 of water | ×1 (today's density) |
| Interior forest | The rest of the forest inside the border | Canopy trees ×0.8; young conifers and saplings ×0.5; bushes ×0.6; ferns ×0.3. The LeafyGrass forest floor carries the look. |
| Old growth | The Elderwood and the Sentinels | Giants are placed by hand. Trees ×0.6, but OakA scaled 1.3–1.6× and ferns ×1.2: fewer, bigger trees. |
| Open high ground | The Shelf plateau, the High Country, the crags, the tablelands | Trees ×0.3–0.5, wind-stunted; rocks ×2 |
| Outside the border | r over 1,810 | Trees ×0.35, for looks only (no collision, no queries, nothing under 3 studs); kept below y 520 |
| Ground cover, everywhere | Tufts, flowers, moss and mushrooms | Not placed by the server: each client scatters them (below) |

**Rule and setting changes:**
- `Field.TallGrass` drops from density 36 to 16, in patchy beds.
- `Meadow.GrassTuft` drops from 12 to 5 (now a client rule); the terrain's grass blades fill in.
- Each class gets a hard cap.
- New rule sets for the new biomes: OldGrowth, Highland, Alpine, Crags and Tablelands.
- `Ctx.spawn`'s `shadowMin` rises from 3 to 6 studs.

**Ground cover is scattered on each client.** Tufts, flowers, moss and mushrooms are about 45% of today's flora models and a quarter of the arena's instances, they never hide anyone, and DetailController already hides them past 70–220 studs. So each client places them round the camera, within its tier's distance, from pooled clones and the same seeded rules, and keeps them off trails, water points and spawned loot. Tall grass, reeds, ferns and bushes stay replicated, so hiding cover is the same for everyone. Keep the rules simple enough to move to Roblox's coming Object Scattering later. The Roblox research brief recommends this. It is part of the plan rather than a fallback, because the budgets below can't be met without it.

**Expected result:** Forest ~24k, replicated flora ~29k (ferns, tall grass, reeds, bushes), Rocks ~7k, Cliffs ~1.2k, sites and camps ~1k. That is about 62k models and ~360k instances on the server at today's ratios (about 10 instances per tree, 3 per flora piece), and 30–35k shadow casters. Kept on the server, ground cover would add about 23k models and 70k instances and break the 400k cap.

**Budget near the player.** `Audit.report` checks the first four rows at edit time and fails the run when one is broken.

| Where | Models | Instances | Triangles |
|---|---|---|---|
| The whole Vale, on the server | ≤ 90k | ≤ 400k | — |
| Any streamed disc (r 1,024) | ≤ 30k: about today's whole arena (28.5k) | ≤ 130k | ≤ 45M at full detail |
| Fighting range (any r 300 disc) | ≤ 7k | ≤ 30k | ≤ 10M at full detail |
| Any 40 × 40 cell | ≤ 14 trees and ≤ 60 flora models | — | — |
| Drawn at the worst views: the plates at the launch, Lantern Peak, the Frostback, the Canopy Grove, the Upper Swing | — | — | High ≤ 5M (today 4.66M at the plates); Medium ≤ 3M; phones ≤ 1.5M and ≤ 800 draw calls |
| An eye-level view in the densest forest | — | — | ≤ 1M on every tier (today 0.72M) |

The phone figure assumes mesh streaming's cloud LoDs (§7.4). DetailController's tiers can't get there alone: today's Low tier still draws 2.50M triangles at the plates (GameDesign §11).

**The disc round the Spire is the binding case.** At the launch all 24 clients stream it, and it holds the r 400 core, the Green's edge and the densest knot of trails. At today's density the inside of r 700 alone would hold about 34k models and 146k instances (today's 28.5k and 122k fill r 640), more than the whole disc may hold. Even with ground cover on the clients and the zones above, a rough count puts the Spire disc near 35k models and 170–180k instances. So T9 tunes the interior multipliers until `Audit.report` passes for the disc centred on the Spire. If it can pass only by thinning the trees the plates look at, keep the trees, measure the launch on a 3 GB Android (§7.6), and let that test set the cap.

**If the Spire disc or phones still run short:**
1. Shorten the client ground-cover distance on Low and Medium.
2. Then thin the young conifers and bushes in the interior zone.
3. Then cut parts per tree: today a tree is about 10 instances (MeshParts plus their SurfaceAppearances), and merging crown and branch parts beyond fighting range saves about a third.
4. Never thin the trees at the Green's edge, which the plates look at.

**Folder layout.** Output goes into sub-folders, one per 512-stud tile inside each biome folder, so neither Explorer nor DetailController's watchers ever face a folder with 40k children.

**`DetailController` tiers** (lines 55–59): the distance in studs past which each class is hidden. "Never" means never hidden.

| Tier | Tufts, flowers, moss | Ferns | Tall grass, reeds | Branch cards | Roots, small detail | Whole trees | Bushes | Rocks |
|---|---|---|---|---|---|---|---|---|
| High | 220 | 300 | 700 | 900 | 500 | never | never | never |
| Medium | 130 | 180 | 300 | 320 | 220 | 1,100 | 700 | 600 |
| Low | 70 | 110 | 300 | 160 | 100 | 600 | 350 | 300 |

Other DetailController changes:
- `CELL` goes from 40 to 64, so a streamed disc holds about 800 cells instead of about 2,050.
- It also watches the Rocks folder.
- Giants are never hidden; past about 400 studs they swap to their far mesh (a new swap in DetailController, T12).
- DetailController no longer hides ground cover; the client scatter above only places it within each tier's distance.
- Tall grass, reeds, bushes and rocks, the cover that can hide a contender, are never hidden within 300 studs on any tier. That is why Medium and Low tall grass rise from 260 and 170 to 300.

### 7.6 Memory on phones

Roblox publishes no memory limit for phones, but most mobile crashes are memory-related. These are our targets for a 3–4 GB phone on Medium, at the worst view:

| Measure (Developer Console) | Target |
|---|---|
| Total client memory | ≤ 1.2 GB |
| PlaceMemory | ≤ 650 MB |
| Client instances | ≤ 160k. Measured on 12 November in a solo playtest: 137k, of which 124k are the whole of today's arena, so about 13k is everything else. Add the 24 contenders' characters and the client ground-cover pool on top of a 130k streamed disc. |
| Terrain graphics | ≤ 110 MB. Today it is 67–71 MB for the whole r 920 terrain (2.66M sq studs of gentle ground). A streamed v3 disc is 1.24× that area, steeper, with coarse terrain drawn beyond it, and Expanded Terrain's client savings are paused. |
| Server memory | ≤ 3 GB with 24 contenders at the launch (Roblox caps a server at about 6.4 GB) |
| Textures | ≤ 160 MB (texture streaming). At most ~12 terrain material sets at 1,024 px, since terrain textures aren't streamed. |
| Frame rate | 30 fps at the least, 60 as the target |
| Crashes | none in 3 full rounds, and none on an Android phone with under 2 GB |

Measure on a real 3 GB Android at:
- a plate at the launch, while all 24 clients stream the same disc;
- the Canopy Grove;
- Lantern Peak;
- the Upper Swing;
- the end of a sprint across the whole Vale.

### 7.7 Moving the Tor

**Why it must move.** The lobby sits at `ArenaLayout.LobbyPosition` (2,600, 160, 0), and its parts span x 2,514–2,686. That is inside the new terrain, which reaches r 2,700.

**The new position: (3,600, 300, 0).**
- The island then spans x ~3,480–3,720, about 780 studs past the terrain's edge and still east of the Vale (story-world.md §3.3).
- From the plates, the crest at r ~2,300 rises about 18° and hides the island, which would sit at about 4°.
- The nearest contender is always more than 1,700 studs away, so the Tor never streams in during a round.

**Steps.** Do these in one session, and only with your go-ahead:
1. Move the kept v1 parts of `workspace.Lobby` (Decor, the 8 Spawns, the 60-part Barrier, AmbientEmitters) by (1,000, 140, 0).
2. Run `TerrainGen.generate`. `islandColumn` and `buildIslandChunk` rebuild the island at the new `LobbyPosition`, and `terrain:Clear()` removes the old one.
3. Run `Populate.buildLobby`, which rebuilds Landmarks, Garden and Railing relative to `LobbyPosition` (Lobby.lua, line 57).
4. Move `RealAssets.lineup`'s default origin (line 751) from (4,200, 200, 0) to (−6,000, 300, 0), so the dev lineup never appears near the Tor.
5. Test a solo round from the lobby to a plate and back, on a phone too.

**These follow on their own:**
- `PlayerService.fallbackLobbyGround` (lines 170–195) and `lobbyTick` (`LobbyPosition.Y − 80`, line 821);
- `getBiome`'s Lobby test;
- AudioController's lobby ambience.

### 7.8 Every change from the audit, by script

Line numbers are from today's scripts, which match Studio byte for byte. Other agents are editing, so if a line has moved, search for the name.

**`ReplicatedStorage.Shared.ArenaLayout`**

| What (line) | Today | v3 |
|---|---|---|
| `Version` (61) | 2 | 3 |
| `PlayRadius` (85) | 640 | 1,800 |
| `MountainRadius` (86) | 680 | 1,846 |
| `mountainEdge(a)` (339) | 676 + 10 sin(4a+30) + 6 sin(7a+100), so 660–692 | 1,846 + 20 sin(4a+30) + 12 sin(7a+100), so 1,814–1,878 |
| `MountainWall` (91) | {651, 700, step 18, height 34, upperRise 30} | {1,812, 1,880, 18, 60, 120} |
| `BoundaryRadius` (87) | 712 | 1,900 |
| `TerrainRadius` (92) | 920 | 2,700 |
| `MeadowRadius`, `ClearingRadius` (83–84) | 150 | 240 |
| `meadowEdge(a)` (334) | 150 plus sines of 14, 9 and 5, so 125–178 | 240 + 26 sin(3a+40) + 16 sin(5a+160) + 9 sin(9a+20), so 190–291 |
| `SnowLine` (77) | 300 | 540 |
| `LobbyPosition` (93) | (2,600, 160, 0) | (3,600, 300, 0); `LobbyRadius` 90 stays |
| `Exclusions` (1207–1218) | meadowCore 100 | 160. The plaza and plate-ring exclusions stay; `boundary` follows PlayRadius. |
| `dangerAt` (1493) | `smooth(40, 260)` | `smooth(40, 520)`, plus open ground and crossings |
| River, Creek, Outflow, Lake, Marsh, Field, Escarpment, River.pool and River.fall (346–635) | one of each | Lists: Rivers, Streams, Lakes (each with its level, shore, style and islands), Marshes, Fields, Escarpments, Falls, Pools and Canyons. The v2 names stay as aliases for the main entry until every caller loops over the lists. |
| `getBiome`, `distanceToWater`, `distanceToCliff`, `forestEdgeDistance` (879–1003) | Each hard-codes the one gorge, the escarpment band, the lake and the marsh | They loop over the lists, with bounding-box early-outs, and know the new biomes: OldGrowth, Highland, Alpine, Crags, Tablelands |
| `Sectors` (949–955) | Five v1 wedges of 60–86° | Regions (14, §3) and about 40 lockdown cells |
| `POIs` (743–766) | 18 | The Spire, 29 sites, 14 camps and the small features, each with its kit |
| `Caves` (648–671) | 3, with 13–36 studs of passage | 10 (§4) |
| `Crossings` (694–713) | 7 | 23 (§5.3) |
| `Clearings` (786), `MistHollows` (798) | 8 and 5 | ~30 and ~15 |
| `Trails` (809–830) | 20 routes, ~6 km | ~55 routes, ~24 km |
| `LootZones` (1430) | MeadowEdge r 110–175, 6 crates, 14 ground | r 190–300, 6 crates, 16 ground; zones for each site come from the site list |
| `RunnerCaches` (1440–1449) | r 150–193 | r 230–300, re-measured |
| `POIHeights`, `CrossingHeights`, `RunnerCaches.groundY` | measured on v2 | re-measured with `TerrainGen.measure()` after the first v3 run |
| New tables | — | Giants (with their climb data), Bridges, Springs (with the optional flag), WarmthSources, WardenHatches (16), RockfallSegments (12), LureSpots, WindSpots (~16), PrizeSpots (6), and `validate()` |
| `CAST_TOP` (1020) | 1,400 | Keep: the terrain stays below about 1,300 |
| Kept as is | Center; PlazaY, MeadowY and BaseHeight 46; LakeLevel 34; MarshLevel 36.5; PlazaRadius 62; SpireRadius 28; PlinthRingRadius 52; Plates; PlateTube | unchanged |

**`ServerStorage.WorldGen.TerrainGen`, `TerrainData` and `WaterPointsBuilder`**

| What (line) | Today | v3 |
|---|---|---|
| Grids (106–108) | G0 −960, FN 480, CN 240 | fine ±1,952 (FN 976) and coarse ±2,752 (CN 688), in buffers |
| `OUTER` (110) | 920 | 2,700 |
| `R_KEYS` and the profiles (317–336) | keys up to 960 | 12 keys up to 2,750, one profile per region |
| `LANDFORMS` (401–409) | 9 | ~35, plus the named shapes |
| Noise, meadow, uplift, basin floors, erosion (425–634) | §7.1 | §7.1 |
| Channels and the single shapes (252–265; 947; 994, 1036, 1131, 1910, 2101; 1169–1366; 1441; 1891–1981) | one of each, keyed by id or name | lists with flags (§7.1) |
| The wall and the Boundary (1511–1630, 2929–2986) | wall height 34; 72 walls | §7.1; 144 walls |
| `CAVES` (2160–2179) | 3 | 10, with two-mouth support and the thickness check |
| `Tube` (2227) | intrude 1.8, maxCentreR 59 | keep (the plaza rim) |
| `arenaChunkOrigins` (2417–2558), `SHELL` | 64-stud chunks (716), a 12-stud shell | 128-stud chunks (about 1,450 including the backdrop); a 64-stud shell with Expanded Terrain; the backdrop writer |
| The lobby island (2588–2698) | at LobbyPosition | follows the new LobbyPosition |
| Waterfall effects (2780–2812, 3195, 3459–3466) | one fall | one set per fall and pool |
| `applyStreaming` (2900–2906) | 1,024 / 128 / Default / PauseOutsideLoadedArea | 1,024 / 128 / Opportunistic / PauseOutsideLoadedArea (§7.4) |
| `writeTerrainData` (3336–3418) | n 176, origin −704, 5 channels | n 480, origin −1,920; channels in parts; no S; adds T and the biome grid |
| Checks (3631, 3885, 3910, 3927, 3956) | ±640, 560/800, 628–640, 712, 640–712 | from PlayRadius and BoundaryRadius, plus the new checks (§7.1) |
| `workspace.Arena`'s `PlayRadius` attribute | 640, stale (nothing reads it) | set from the layout on every run |
| `TerrainData` index | 5 child modules | 12 parts; the index joins them (§7.2) |
| `WaterPointsBuilder` (15, 16, 63, 80, 128) | `PLAY_RADIUS` 620; one river; one lake (a point every 20°); a ±120 marsh grid capped at 5 points; 52 points in all | `PlayRadius` − 20. It loops over Lakes, Rivers, Streams, Marshes and Springs, with lake points every ~30 studs of shore: ~300–400 points, which `WaterPoints.nearest` can still scan every time. A coverage report checks that every walkable 16-stud cell inside the border is within 300 studs of a point (400 when every optional spring is dry). |

**`ServerStorage.WorldGen.Populate` and `RealAssets`**

| What (line) | Today | v3 |
|---|---|---|
| init: the biome grid (360, 379) | −960 / 8 / 240, with a 940² test | −2,752 / 8 / 688, with (TerrainRadius + 20)² |
| init: the trail grid (424) | −960 / 2 / 960 | −1,920 / 2 / 1,920 (a 3.7 MB buffer) |
| init: `VISUAL_R` (89) | PlayRadius + 10 | follows on its own (1,810) |
| init: `shadowMin` (235) | 3 | 6 |
| init: the runner's-cache search (541) | r 150–200 | the MeadowEdge band, r 230–300 |
| init: `KEEPOUT_MAX` (582) | 34 | 64 |
| init: the steps | core, POIs, camps, cliffs, scatter, lobby, ambience | Adds a `loot` step (the marker planner) that runs before scatter, because `Ctx.prepare` turns markers into keep-outs. Also adds the v3 site kits, the giants and the bridges; `Ctx.zone` multipliers and caps for each class; output in 512-stud tiles. The scatter no longer places tufts, flowers, moss or mushrooms (the clients do, §7.5). |
| Scatter `EXTRA` (74–175) | Mountains.Conifer maxR 860, heightFade {170, 300}, density 0.7 · Scree minR 715, maxR 860, maxCount 60 · Meadow.LoneTree minR 118, max 4 · Meadow.Boulder 100 / 8 · Meadow.TallGrass minR 115 · Wildflowers 80 · Field.LoneTree max 8 · Gorge.FallenLog max 9 | 2,300, {560, 760}, 0.35 · 1,903, 2,200, 240 · 200, 10 · 170 / 24 · 190 · 120 · 24 · 30 |
| Scatter `stand()` noise (266–269) | 150 / 55 | 300 / 110: bigger stands and glades |
| Scatter fill target (638) | density × the biome's area | × the zone multiplier, capped for each class |
| Sites `COVER_BUDGET`, `TOUCHUP_BUDGET` (37–38) | 150, 60 | 600, 150 |
| Sites cave dressing (410, 421) | by name (CreekCave, LedgeCave) | a dressing field on each cave's entry |
| Sites falls and river (503, 854, 1478, 1491) | the one `River.fall` and `River.samples` | loops over Falls and Rivers |
| Sites frogs (1500–1503) | within 115, at most 6 | per marsh, by its area |
| Sites wind (1522) | 4 fixed spots | `Layout.WindSpots`: ~16 high points |
| Audit (743, 1083) | 650², −640 to 600 | (PlayRadius + 10)², ±PlayRadius, plus the budget gate (§7.5) |
| `RealAssets.lineup` (751) | (4,200, 200, 0) | (−6,000, 300, 0) |

**`ReplicatedStorage.Shared.Config`**

| What (line) | Today | v3 |
|---|---|---|
| `Border` (67–94) | StartRadius 640; MinStartRadius 320; one shrink at 600–830 s; WallHeight 520; WallPanels 96; WarningLeadTime 30 | StartRadius 1,800; MinStartRadius 520; `Stages` (§6.5) with the drift (200 studs in stage 1; 0.25 × r0 from the start when r0 is under 1,200); WallHeight 800; WallPanels 160; warnings 60, 60 and 30. Damage, FinalRadius 35, the Last Stand values, FinalSpireGap and PracticeLastStandRadius all stay. |
| `Events.FeastWarning` (98) | 45 | 90 when r0 is 1,200 or more; 45 in smaller rounds (§6.7) |
| `Loot` (335–368) | GroundSpawnChance 0.65 | 0.6, plus SiteStockChance 0.85, PrizeStockCount 2 and `LootTables.Forage` |
| `Movement` comment (121) | "1300-stud arena" | Updated; speeds unchanged |
| `Movement.FallDamage` | any water breaks any fall | `WaterCushionMaxHeight` 90, `WaterCushionMinDepth` 4; designed leaps stay at 80 or less (§5.6) |
| `Movement.Slide` | `HardMaxTime` 3.5 everywhere | Chute materials (Snow, and Basalt for scree) and the `Chute` tag: no time-out on slopes over 20° |
| `Survival.VoidHeight` (116) | −80 | Keep: the v3 terrain stays above 0 |

**Server services**

| Script (lines) | Today | v3 |
|---|---|---|
| ArenaService: `radiusAt` (320–335), `centerAt` (312–318), `updateBorder` (360–417), `updateRollCall` (577) | one shrink | Stage-aware through `Shared.Border`. The centre slides only in the last stage, each stage gets its own warning and headline, and the Roll Call check uses the final stage's start. Adds `getBorderAt(t)` for the Director. |
| RoundService: `startRadiusFor` (128–136), fallback 640 (130) | clamp(640·√(N/24), 320, 640) | clamp(1,800·√(N/24), 520, 1,800), with every stage radius × r0 / 1,800 and the round's seeded drift bearing published with r0; the fallback comes from Config |
| PlayerService: `onSpectateTarget` (1032–1048), the plate wait (729), the lobby (170–195, 821) | — | Streams around the target before setting `ReplicationFocus`; the plate wait is re-timed on a phone; the lobby follows `LobbyPosition` |
| LootService: `populate` (1221–1268), the runner's poles (1021–1067) | — | `SiteStockChance` and `PrizeStockCount`; the QW3 skip (line 1236) measures from the start circle's centre, not from the Spire (`ArenaLayout.flatDistance` today); the poles grow from 10 to 14 |
| MovementService (server) and MovementController: fall damage (`MovementService.inWater`, line 71), slides, climbing (2110–2125) | — | The water-cushion rule (depth and height, on the server), chutes, river current zones (`applyImpulse`, new); climbing unchanged |

**Client controllers**

| Script (lines) | Today | v3 |
|---|---|---|
| HUDController: `updateCompass` (1025+), fallback 640 (1067), `BORDER_NEAR_METERS` (87), `eventLine` (1170–1195) | The Spire, the border edge and the water drop; 80 m | The region's name and site ticks; the fallback comes from Config; 120 m; a stage-aware event line; a map page in the Menu |
| ThreatLine: beats (138–142) | one BorderMoves beat | one for each stage |
| ArenaController: `PANEL_COUNT` (39), `WALL_HEIGHT` (40), `WALL_BELOW` (41) | 96, 520, 110 | 160, 800, 110 |
| ArenaController.Sky: mist zones (182–223), `MIST_MAX` (43–46), the fallback ellipse (223) | one lake and one marsh; 150 | from the lists; 240; from the layout |
| AudioController: `BIOME_MIX` and `BIOME_ENV` (101–147), five `getBiome` calls every 0.2 s (136, 1436), `RemoteRange` 90 (55) | Every footstep is simulated within 90 studs | Entries for the new biomes; reads `Shared.BiomeGrid` instead; footsteps on bridge planks heard to 120 studs and in caves 1.5× as far |
| DetailController: `TIERS` (55–59), `CELL` (45), the folders it watches (326) | Flora and Forest | §7.5; 64; Rocks as well; giants never hidden and swapped to their far mesh past ~400 |
| New client ground-cover scatter | — | Tufts, flowers, moss and mushrooms placed round the camera from pooled clones and the seeded rules (§7.5) |
| SpectateController | no distance logic | A fade and "moving to …" for far targets |
| DayCycle looks | AtmDensity 0.28–0.44 and Haze 1.1–2.2, tuned for ~700-stud views | Re-tuned so the crest at 2,000–2,700 still reads and the haze hides level-of-detail seams past ~500 |
| FallenRecapController | Camera-relative (STAGE_DISTANCE 170) | No change |

**Docs to update after the build** (the build agents do this; this document edits nothing else):
- GameDesign.md §11, including its streaming note: "the whole arena loads from the plaza" stops being true.
- Status.md.
- PlayabilityPlan.md QW3's numbers and its small-round drift, and QW7's cache radius (r 230–300).
- arena-events.md: the numbers in §3–§5, and line 48's Roll Call sigil note.
- Roadmap §7's list of beats to avoid (§1 above).
- Roadmap §5:
  - Phase 2a's six slots: the Dawn slot is skipped in full v3 rounds (§6.7).
  - Phase 2b's hound paths and Ember Rain cover check, and Phase 3's Floodgate, Rockfall and Miasma, wait for "the final world". That is now the v3 world (T9), or the workbench while it is built.
  - Phase 5's "done when" says "the border from 600 to 830 s". It becomes "the final stage from 600 to 830 s".

---

## 8. New art

### 8.1 Reuse first

The 64 templates in `ServerStorage.MeshAssets` still do most of the work:

| Templates | Where they go in v3 |
|---|---|
| **TreesReal (14):** SpruceA/B, FirA, PineA, ConiferYoung, BirchA/B, OakA, SnagA/B, FallenLogA/B, StumpA/B | Every forest. OakA at 1.3–1.6× scale in the Elderwood. SnagA/B for the Drowned Pines and the Sump's dead stand. SpruceB and PineA wind-stunted (0.7–0.9×) on the plateaus. FallenLogB as the base of the log jam. |
| **GroundReal flora (14)** | All ground cover. GrassTallA/B in the Tallgrass, tinted dry in the tablelands through `SurfaceAppearance.Color`. ReedsA by the lake and in the Sump. BerryBush for forage. FernA/B packed densely on the Elderwood floor. |
| **GroundReal rocks and cliffs (12):** BoulderA–D, RockFlat, RiverStones, ScreeA, CliffFaceA–C, RockOutcrop, CaveMouth | Boulders everywhere. RiverStones and RockFlat for fords and stepping stones. CliffFaceA–C on the smaller faces. CaveMouth on the mouths of 6 of the 10 caves. |
| **BuildingsReal (3):** HunterCabin, Watchtower, Footbridge | HunterCabin as the Ranger Station's shell (with the radio mast) and as the Hunters' Rest's stove hut. Watchtower at Watchtower Ridge, and its frame under the hunting blind. Footbridge over the Millrace flume and at the Spray Steps. |
| **PropsReal (10):** Tent, Campfire, Woodpile, Barrel, Lantern, CratePile, FenceSegment, Sign, Bedroll, LogBench | The 14 camps, the Hunters' Rest, the Sawpit, Kettle Island, the mine yard and the quarry shed |
| **LandmarksReal (11)** | The Spire, the SpirePlatform and the Plinths, unchanged. A Brazier at the Redoubt. The rest stay on the Tor. |

### 8.2 New assets

All of them come from the Blender pipeline (art/README.md §8–§11), with its usual limits:
- procedural and seeded, with `ad_finalize` reporting 0 problems;
- at most 20,000 triangles per mesh part and 20 MB per GLB;
- at most 16 upload images per texture folder, at 1,024 px;
- the existing texture sheets (granite, bark, wood, kit) reused wherever possible.

LandmarksReal.glb has only 0.38 MB of headroom, so everything goes into new GLBs. Sizes are W × H × D in studs.

**GiantsReal.glb** uses TreesReal's bark and leaf sheets plus one new giant-bark sheet. Two art risks are settled first in T4:
- **Tiled bark.** A 130-stud trunk can only keep its texel density by repeating its bark (UVs outside 0..1), and art/README §11.7 lists repeating UVs as not yet verified in Roblox. Test one trunk in Studio before modelling the set.
- **Leaves up close.** TreesReal's leaf cards read as flat shelves within 8–15 studs (art/README §11.7), and a crown hide or platform puts you inside the crown. Round each hide and platform, use smaller, denser cards or a leaf-cluster mesh.

| Asset | Size | Triangles | Notes |
|---|---|---|---|
| ElderOakA | 110 × 135 × 105 | ~30k: trunk and limbs 12k, crown cards 15k, roots 3k, split into parts | Climbable trunk zones; rest forks at 38 and 76 (tagged Floor); a crown hide for two at ~105; a walk-in hollow 6 × 9 × 6; `LinkN` attachments toward its neighbours; a far mesh of 800 |
| ElderOakB | 95 × 120 × 100 | ~28k | No hollow; limbs aimed for the grove's links |
| SentinelPineA | 45 × 170 × 45 | ~24k | Branch stubs in whorls; forks at 40, 80 and 120; the Perch at ~130 (lashed poles, room for one); a far mesh of 600 |
| SentinelPineB | 40 × 155 × 40 | ~22k | No hide |
| GhostSnagGiant | 30 × 120 × 30 | ~9k | Dead, with a split top; climbable |
| FallenGiant | 170 × 16 × 18 | ~10k | You can walk along its top; its root plate is 30 across; it bridges a 40–60-stud ravine |
| RootPlate | 32 × 26 × 10 | ~5k | Root Hollow: cover, with a hollow underneath |
| OrchardApple | 18 × 16 × 18 | ~4k | Fruit cards that read as forage |
| SpruceFar, BroadleafFar | — | 300–600 each | For the looks-only band outside the border, and as far swaps |

**TraverseReal.glb** shares the BuildingsReal wood sheet and new rope and canvas sheets.

| Asset | Size | Triangles | Notes |
|---|---|---|---|
| Rope bridge kit: AnchorFrame, DeckSegment (straight and sagging), side ropes, BrokenEnd | anchor 6 × 9 × 4; segment 4 × 0.6 × 4.5 | anchor 1.2k; segment 500; broken end 2k. A 70-stud span (about 18 segments) is ~11k. | The deck collides (Box); the ropes don't; the sway is drawn on each client only |
| Canopy kit: PlatformRing, PlatformSmall, RopeWalk segment, CanvasHide, RopeLadder | ring 12 × 2 × 12 (fits a trunk 10–16 across); small 8 × 2 × 8; walk segment 4 long; hide 8 × 6 × 8; ladder 2 × 40 × 0.5 | 2.5k; 1.5k; 600; 2k; 900 | The rope ladder has a Climbable collider |
| LogJam | 40 × 8 × 18 | ~8k | Walkable, across the Throat's floor |
| FixedRope | 0.4 × 40 | ~400 | Climbable |
| LogChute segment, on a trestle | 4 × 3 × 2.5 | ~400 each. 300 studs is about 75 segments, ~30k, split into parts. | Tagged `Chute` |
| HaulLine, only if question 4 says yes | stations 12 × 10 × 8 | 5k per station; trolley 400 | The cable is a Beam |

**CavesReal.glb** uses the GroundReal granite tile.

| Asset | Size | Triangles | Notes |
|---|---|---|---|
| CaveArchS/M/L | 16, 24 and 36 wide | 3–7.5k | For mouths where CaveMouth doesn't fit |
| Cave interior pieces: WallPanel, CeilingSlab, Pillar, Squeeze, DripPoolRim, Chimney | 20 × 14 × 6; 20 × 6 × 20; 8 × 14 × 8; 10 × 6 × 12; 12 × 2 × 12; 8 × 32 × 8 | 2.5k; 2.5k; 1.5k; 2k; 1.5k; 3k | They line the thin parts of terrain caves (the 16-voxel rule). The Chimney's inner face is Climbable. |
| Mine adit kit: Straight, Bend, Junction, Collapse, LadderShaft, OreCart, Rails | Straight 8 long; LadderShaft 6 × 30 × 6 | 2.5k; 2.5k; 3k; 2.5k; 2.5k; 1.2k; 400 per 8 studs | The Greyvein Workings |
| BoulderGiant, LoneStone | 24 × 18 × 22; 30 × 22 × 26 | 3k each | The Jumbles (laid out with gaps) and the Tallgrass |

**CliffsReal2.glb** uses the GroundReal granite plus an iron-stained version for the Rust Wall.

| Asset | Size | Triangles |
|---|---|---|
| CliffFaceD | 60 × 55 × 45 | ~9k |
| CliffFaceE | 90 × 80 × 55 | ~12k (2 parts) |
| CanyonWall tile | 40 × 60 × 20 | ~7k |
| Overhang | 30 × 18 × 20 | ~5k |
| TorPillar (the Shelf tor, the top of the Stack, the crags) | 20 × 60 × 20 | ~7k |
| ScreeB (scree fields and slides) | 20 × 6 × 16 | ~3k |
| RapidsRocks, 4 variants (rounded, wet) | 6–14 across | 1.5–3k each |
| FallsLip and PlungeRim (the Great Falls) | 40 × 12 × 20 and a ring | ~5k and ~4k |
| Arch (the Anvil's) | 50 × 30 × 15 | ~6k |

**RuinsReal.glb** uses a new weathered-stone sheet plus the BuildingsReal wood sheet.

| Asset | Size | Triangles |
|---|---|---|
| Redoubt kit: WallStraight, WallCorner, WallBreach, GateArch, TowerStump (with its stair), CellarVault (interior), RubblePile | wall 12 × 10 × 3; gate 16 × 14 × 6; tower 14 × 30 × 14; vault 16 × 8 × 12 | 2k; 2.2k; 2.5k; 4k; 8k; 5k; 1.2k. About 40k as built. |
| Millhouse (half its roof standing), WaterWheelBroken, Flume segment, Weir | 24 × 20 × 16; 14 × 14 × 3; Weir 40 × 8 × 6 | ~12k; 4k; 600; 4k |
| Dam: DamSection (11 make the 220-stud dam), Spillway, Gatehouse (two floors), SluiceWheel | 20 × 36 × 18; 20 × 36 × 30; 14 × 16 × 12 | 3.5k; 5k; 12k; 1.5k |
| Farmhouse ruin, Well and trough, root-cellar hatch | 20 × 10 × 14 | 8k; 1.5k; 1k |
| Bothy, with a hearth | 12 × 8 × 9 | 5k |
| Survey cairn | — | 600 |

**SitesReal.glb** uses the BuildingsReal sheets.

| Asset | Size | Triangles |
|---|---|---|
| MineHeadframe (a ladder and a platform by the wheel), OreBin, Bunkhouse ruin, ForgeShed (`Hearth` attachment), PowderStore | 16 × 45 × 16; 12 × 14 × 10; 20 × 10 × 12; 12 × 9 × 10; 6 × 5 × 6 | 10k; 5k; 8k; 5k; 2k |
| FireLookout (flights of stairs and a glazed cab 12 × 9 × 12 with a warm lantern light) | 14 × 40 × 14 | ~14k |
| Ranger Station additions: a radio mast, and a porch and shutters on the HunterCabin shell | mast 0.5 × 25 | 800; 2k |
| Hunters' Rest: HuntingBlind on stilts, LeanTo, DryingRack | 8 × 14 × 8; 10 × 6 × 8 | 3k; 1.5k; 1k. The rack is empty, with no animals, following the Community Standards note in arena-events.md §6. |
| Sawpit: SawpitFrame, LogDeck (plus the existing Tent) | 10 × 6 × 4; 16 × 5 × 8 | 2k; 3k |
| Quarry: Derrick (a 40-stud mast with a 30-stud boom), CutBlocks in 3 sizes, QuarryShed | 10 × 8 × 8 for the shed | 6k; 400–800; 4k |
| Old Jetty, Rowboat, Duckboard segment, StiltHut | 40 × 3 × 6; —; 4 long; 12 × 14 × 10 | 3k; 2k; 300; 5k |

**Effects** need no meshes:
- the Beacon plume: a Beam with one smoke texture, which is one image upload;
- the spray and mist at the falls: one set of emitters per fall;
- spindrift on the Frostback.

**In total** that is about 95 new assets and about 450k triangles of templates. What matters at runtime is how many sit near a player (§7.5).

**Review:**
- Each set is reviewed with `ad_review.py` at eye level next to the 5.5-stud figure.
- In Studio, the giants and the canopy kit get a climb test, and the bridges a deck sweep.

**Placed in the Vale**, roughly:
- 14 standing giants: 5 in the Canopy Grove, 3 Sentinels and 2 dead giants beside them, the Lone Elder, the Hunters' Rest's oak, and 2 dead giants on the High Country.
- 2 fallen giants.
- 3 rope bridges, with broken versions for the rounds when one is down.
- 8 canopy platforms and 5 rope walks.
- About 1,200 cliff pieces, mostly the existing A–C with the new D and E on the big faces.
- 10 caves and about 25 buildings and ruins.

---

## 9. Build plan

### 9.1 Phases

| Phase | When (agents in parallel) | Goal | Starts after |
|---|---|---|---|
| 0 · Decide and set up | 1–2 days | Your answers (§10); the workbench copy of the place; the manual switches below; a baseline of today's frame times and memory on a PC and a 3 GB Android | — |
| 1 · Foundations | weeks 1–2 | The layout data, TerrainGen's new core, the staged border, the first art | Phase 0 |
| 2 · Ground and water | weeks 2–4 | The v3 terrain, TerrainData, the Tor's move | The layout data and TerrainGen's core |
| 3 · Dressing, loot and event data | weeks 3–5 | Populate v3, the loot planner, water points, warmth sources, hatches | The v3 terrain, and the art as each batch lands |
| 4 · Client and look | weeks 4–5 | Level of detail, the HUD, sound, the look-dev pass | The dressing |
| 5 · QA and the swap | weeks 5–6 | Checks, playtests and phone tests; then the same builders run in the main place | Everything |

The swap is simple because TerrainGen and Populate are seeded and deterministic. Once v3 passes in the workbench, the main place runs the same builders, and nothing has to be copied across by hand.

**Manual steps only you can do,** in Studio's Properties window in the workbench place:
1. Workspace → `ExpandedTerrain` on; then save, close and reopen (in Team Create, wait about 15 s).
2. Workspace → `MeshStreamingAndImprovedLoDs` → Enabled; then restart Studio.
3. Workspace → `ModelStreamingBehavior` → Improved.
4. Publish the workbench as a private test. SLIM and mesh streaming only work in a published place with Team Create on.

### 9.2 Agent tasks

Each task is one agent. Tasks in the same phase run in parallel.

| # | Task | Phase | Needs | Scope | Done when |
|---|---|---|---|---|---|
| T1 | **layout-v3** | 1 | — | ArenaLayout v3: the lists, the 14 regions and ~40 lockdown cells, the 29 sites and 14 camps with their kits, 10 caves, 23 crossings, ~55 trails, the water list, giants, bridges, springs, warmth sources, hatches, Rockfall stretches, Lure spots, prize spots, the Roadmap Phase 6b hidden-cache spots; child modules; queries loop over the lists; `validate()` | Every module is under 200k characters. `validate()` reports 0 problems: all water drains downhill to Stillwater or ends in the tarn or a pond; every level is in the lower half of a voxel layer; site anchors are at least 280 studs apart (the Throat Crossings and the Great Falls are one canyon complex and exempt); no walkable point inside r 1,750 is more than 650 studs (50 s at a jog) from a site or a camp, so camps fill the gaps that §4's sites leave at the east, west and south-east rim and round the Lost Orchard (~850 studs from its nearest site); every Climbable route rests at most every 45 studs; every site and region has at least 2 entrances; trails link every site to the Spire; the plaza block is identical to v2's. The v2 callers (River, Lake, Marsh) still run. |
| T2 | **terrain-v3-core** | 1 | — | Split TerrainGen; buffer grids; the fine and coarse extents; carving driven by the lists; the backdrop writer; 128-stud chunks | On the v2 data in the workbench, the output matches today's terrain (heights within 1 stud on 99% of columns) and every existing check passes. A generate run adds at most 1 GB to Studio's memory. Every child module is under 200k characters. |
| T3 | **border-stages** | 1 | — | `Shared.Border`; `Config.Border.Stages` and the seeded drift; stage-aware ArenaService, RoundService, HUDController, ThreatLine and ArenaController; the new QW3 numbers; `FeastWarning` 90 (45 in small rounds); LootService's skip measured from the start circle's centre; the Roll Call trap | At `StudioTimeScale` 6 on today's arena (stages scaled to 640), every stage shows its card, threat line, compass tick and wall. Roll Call 1 plays in the sky. The Last Stand still starts at 830 s. Small-round radii match §2. `getBorderAt(t)` returns the staged radius and centre. A sweep of 8 drift bearings, at full size and at r0 520–1,199, samples 360 points of the ring every second: none moves faster than 6.5 studs/s, and the Spire stays inside every ring by at least a third of r0. |
| T4 | **art-giants-traverse** | 1 | — | GiantsReal and TraverseReal | `ad_finalize` reports 0 problems. Each GLB is under 20 MB with at most 16 images, and the triangles are within budget. In Studio, a 5.5-stud R15 reaches every rest fork with at least 30% stamina left; a 2 × 3.6 box sweeps every bridge deck clear; `RealAssets.verify()` passes. Before the rest of the set is modelled, one giant trunk shows repeating bark at its planned texel density, and from inside a crown hide the leaves read as foliage, not as cards, at 3 studs (§8.2). |
| T5 | **terrain-v3-world** | 2 | T1, T2 | The v3 relief, water, falls, caves, wall, backdrop and materials; the plaza rim gates | `generate()` takes 90 s or less in Edit mode. Every check in §7.1 passes: plaza, tubes, water, mountains, thickness, walkability, reach, caves and relief, the last within ±15% of §3. |
| T6 | **terrain-data-v3** | 2 | T5 | TerrainData in parts, the T channel, `Shared.BiomeGrid` | At 200 sample points, `moistureAt`, `distanceToCliff`, `waterAt` and `getBiome` agree between the grid and the analytic version (±1 cell). A biome lookup on the client costs under 0.05 ms. |
| T7 | **lobby-move** | 2 | T5, and your go-ahead | The Tor to (3,600, 300, 0) (§7.7) | A solo round goes from the lobby to a plate and back, with streaming waits of 4 s or less on a phone. The Tor never enters a contender's streamed area during a round and can't be seen from any plate. The RealAssets lineup has moved. |
| T8 | **art-caves-cliffs-ruins-sites** | 2–3 | — | CavesReal, CliffsReal2, RuinsReal, SitesReal, and the far meshes | The same art checks as T4, plus a walk-through of each building and of the adit kit (door 4 × 7.5, at least 6 studs of headroom, colliders leave the openings open). |
| T9 | **dressing-v3** | 3 | T5, T6 and the art | Populate v3: zones and caps; no server ground cover (§7.5); the 512-stud tiles; the site kits; the giants and their climb paths; the bridges; the cliff coverage pass at the new budgets | `Audit.report`: at most 90k models and 400k instances; at most 30k models and 130k instances in any 1,024-stud disc, the disc centred on the Spire included (or the cap the launch test on a 3 GB Android sets, §7.5), and 7k models in any 300-stud disc. Every P.verify check passes at the v3 radii (plaza and plates 0, trails 0 blocked, crossings 0, cave mouths 0, loot clearings 0, runner's caches 8 of 8 in view). Populate takes 150 s or less. |
| T10 | **loot-v3** | 3 | T9 | The loot planner (the new step), LootZones v3, the Config.Loot changes, prize spots, forage, and the per-round seed of §6.4 (stocking, which springs flow, which camps smoulder, the downed rope crossing), published for the other systems | The planner produces §6.1's markers by region (±10%). P.fixLoot and P.verify pass. A 20-round simulation gives 300–380 items per round, and every ring D site has a weapon and a vest. |
| T11 | **events-data-v3** | 3 | T9 | Regions and lockdown cells, the 16 hatches, the 12 Rockfall stretches, warmth sources, the Floodgate's reach, the Lure spots, the tree-cover grid; WaterPointsBuilder v3 | For each of 16 drift bearings, every point inside that round's night ring is within 300 studs of a warmth source or shelter inside it. In every lockdown cell, and every pair of neighbouring cells sealed together, the farthest point is within 250 studs of a way out. No hatch is in the Green or the Crest, and every hatch has a path to its region's trails. Water coverage is 300 studs or better everywhere inside the border (400 with every optional spring dry). |
| T12 | **client-v3** | 4 | T9 | DetailController's tiers and the giants' far-mesh swap; the client ground-cover scatter; ArenaController's panels and height (panels more than ~1,000 studs from the camera hidden outside the Countdown, to keep LookDevPlaybook §7.3's limit of 2–3 transparent layers); Sky's mist lists; AudioController's biomes, the biome grid and the longer footstep range on planks and in caves; the compass's region name and site ticks; the map page in the Menu; spectate streaming; the river current (and `applyImpulse`, if Phase 3 hasn't built it); chutes; the water-cushion rule in MovementService (server) | The compass names the region and shows nearby sites. The map shows the found sites and the border stages. Spectating a target 3,000 studs away fades in without empty ground. A scripted fall test passes: 76 studs into the Cauldron and 70 from the Leap Ledge do no damage, 85 onto the Throat's rapids kills, and 95 into deep water kills. Chutes and the current behave as §5.6 says on PC, phone and gamepad. Two clients place the same ground cover, which costs at most 1 ms a frame on a phone while sprinting. Within 300 studs no tall grass, reed, bush or rock is hidden on any tier. |
| T13 | **look-dev-v3** | 4 | T9 | Atmosphere and haze for 500–1,500 studs, the Beacon plume, the falls' spray, snow, night under the giants | From the Frostback and Lantern Peak, haze hides level-of-detail and streaming seams at every hour. The Beacon plume shows from the rim by day and by night. B7's greyscale checks pass in the new biomes. Night under the giants is dark but playable (LookDevPlaybook §13). At the Great Falls, at most 25–30 particle emitters are active near the camera (LookDevPlaybook §7.3), and only the nearest fall runs at full rate. |
| T14 | **qa-v3** | 5 | everything | The automated checks, playtests, device tests, an IP review, then the swap | All TerrainGen and Populate checks pass. In 4-client and 8-client playtests with FastTimers off, the median time from leaving the plaza to first seeing or hearing a rival is 2:30 or less with 8 clients and 3:00 or less with 4 (QW3's test), and the median gap between encounters is 3:00 or less. New players have no thirst deaths in rounds 2–3. Heatmaps show every region visited at least once every 5 rounds. A 3 GB Android holds 30 fps or better at the plates, in the Canopy Grove and on Lantern Peak, with client memory at 1.2 GB or less and no crash in 3 rounds; a mid PC holds 60 fps. Every name and line passes §1's avoid list. |

**Risks and how the plan handles them:**
- **Big rebuilds block Studio for minutes.** Run them in the workbench, one agent at a time, behind a lock attribute on `workspace.Terrain` while `generate()` runs.
- **TerrainGen's memory.** The buffers (T2) come before any 3× run; a build with Luau tables would likely run Studio out of memory.
- **SLIM and mesh streaming are new.** Test them on 2–3 models before relying on them; the fallbacks are in §7.4.
- **Expanded Terrain.** Roblox paused its client memory savings on 27 October 2026 after crashes. Don't count on them until they come back; the 1,024-stud streaming radius is what bounds memory. Editing terrain in Team Create with it on can cause meshing bugs, so a `generate()` run happens with only one Studio session open in the workbench.
- **The Roadmap waits on the world.** Phase 2b's hound paths and Ember Rain cover check, and Phase 3's Floodgate, Rockfall and Miasma, were planned on the v2 world. Build them against the workbench as it settles, or after T9. The 6 weeks here also push back the first public release unless they run beside Phases 2 and 3.
- **Too quiet in the middle.** If playtests show the middle of the round is empty, the first levers are:
  1. stage 1 to r 1,150 instead of 1,250;
  2. two Lure gifts in Slot 1;
  3. more forage and water at the ring C sites, so people stop there.

---

## 10. Questions for you

1. **Where should v3 be built?**
   - *Recommendation: in a separate workbench copy of the place, in the same experience, with Expanded Terrain and mesh streaming switched on there.* When it passes QA, the same builders run in the main place.
   - Building straight into the shared place would block you and the other agents for minutes at a time and break today's arena for several weeks.
2. **Round length?**
   - *Recommendation: keep 15 minutes.* The staged border fits it, and the Offering, the final closing and both Roll Calls stay exactly where the code and the Roadmap expect them.
   - The alternative is 18 minutes, with the extra time spent on a longer first day.
3. **The first closing.** At 3:15–5:15 the border takes the outer half of the Vale (r 1,800 down to 1,250). Its circle drifts up to 200 studs toward a different side each round, so one outer region stays in play for longer.
   - *Recommendation: yes, as described.*
   - The alternative keeps the whole Vale open until the night and closes in two stages: 1,800 down to 1,100 over 7:20–9:15 (about 6.1 studs/s), then the final closing from 1,100. You get longer exploring, but a sparser middle of the round.
4. **An old ore cableway?** One abandoned cableway at Greyvein Mine: hold a trolley and ride about 450 studs across the Throat in about 22 s, one way and downhill. One rider at a time, loud and exposed; let go and you fall.
   - *Recommendation: yes, one, built last.* It needs a small new movement feature.
   - The alternative is none. The Vale's fast lanes then stay natural: the river's current, snow and scree chutes, the log chute and leaps into deep water.

---

## Sources

- **The research briefs** for this document:
  - *Film arenas:* the novels and films through bookanalysis.com, GradeSaver, LitCharts, Wikipedia and the 2012 production notes. Used only for the generic feel and for the avoid list.
  - *Big maps:* PUBG, Apex Legends, Warzone, Fortnite, Hunt: Showdown, Nintendo's CEDEC 2017 field-design talk, The Level Design Book.
  - *Roblox at this scale:* the creator documentation on instance streaming, SLIM, mesh streaming and improved LoDs, custom terrain materials (Expanded Terrain), occlusion culling and the performance guides, plus the DevForum announcements up to November 2026.

  The links are in those briefs.
- **The audit (12 November 2026):** Studio read-only (place 120572716460286; the studio_id in the brief wasn't connected, so the only open instance of the same place was used) and `src/`, byte for byte the same as Studio, including commit 74dbf21 (the plaza trench cap and PlateCollar).
- **Project docs:** GameDesign.md §11, Roadmap.md §2 and §7, design/arena-events.md, design/PlayabilityPlan.md (QW3, QW7, QW10, B7, P1, P10), research/LookDevPlaybook.md §7–§8, design/story-world.md §3, art/README.md §3, §8–§11, and the live `ArenaLayout.lua`, `Config.lua` and `TerrainGen.lua`.

---

## Review notes

*Design review, 12 November 2026.* This document was checked against the three research briefs, the audit, Roadmap.md, arena-events.md, PlayabilityPlan.md and the live code. Studio was only read: the Server and Client datamodels of instance 5766363b (a Play session someone else had started; the brief's studio_id wasn't connected). Nothing was edited there, and no playtest was started or stopped. The scripts read were `Config`, `ArenaLayout`, `TerrainGen`, `ArenaService`, `RoundService`, `LootService`, `MovementService`, `AudioController`, `DetailController` and `DayCycle`. Only this file was changed.

**Fixed in this document**
- **The border broke its own speed rule.** A 300-stud drift during a 90 s stage 1 swept the far side at 9.4 studs/s, faster than a swimmer. Now stage 1 runs 3:15–5:15 with a 200-stud drift (6.25 studs/s at worst), stage 2 keeps that centre, and T3 sweeps every bearing to prove it (§6.5).
- **Small rounds.** A 640 floor gave 2–3 contenders more room each than a full round, the opposite of QW3. The floor is now 520. Small rounds drift from the start, so they reach the high ground too, and QW3's 4-player test is in T14 (§2).
- **The Offering's warning.** 90 s would have overlapped the Dawn slot that small rounds keep. It is 90 s only when r0 is 1,200 or more (§6.7).
- **Phones.**
  - The doc's own figures broke its caps: about 435k server instances against a 400k cap, and a Spire disc far over 30k models. Ground cover now goes to the clients, as the Roblox brief advised, and the Spire disc is named as the binding case, with the phone test as the judge (§7.5).
  - Streaming keeps a minimum radius of 128 and `PauseOutsideLoadedArea`, as Roblox recommends. The doc had raised the radius to 256 and switched to the stricter `MinimumRadiusPause`.
  - The client-instance target now uses the count measured today (137k), and the terrain-memory target allows for steeper ground.
- **Buildability.**
  - Four climbs didn't reach the height they had to climb: the Anvil's chimney, the Veil's chimney, the Throat's fixed rope and the Stack's crack. Now that they are longer, every Climbable route rests at least every 45 studs, within one stamina bar (about 61 studs).
  - The water-cushion cap goes from 80 to 90. `MovementService` measures a fall from its highest point, and the Great Falls jump had 1 stud of margin.
  - Smaller items: the Workings' 140-stud drop; the Stack is built from meshes; Basalt is reserved for scree; `applyImpulse` doesn't exist yet; footsteps on planks and in caves need more than today's 90-stud range; the giants' bark and close-up leaves are checked first in T4.
- **"Done when" lines.** T1's spacing rule failed the doc's own layout on 7 pairs, so it now measures anchors and coverage. T3, T4, T9, T11, T12, T13 and T14 gained measurable checks.
- **Geometry.** Echo Run's length; the Floodgate's stretch (about 820 studs); the Lakehead cliffs; the plateau stream below the dam; the Crest's north foot; the Watchtower jump; swim times with sprint stamina; Lantern Peak's angle; crate counts in rings C and D.
- **IP.** "At the horn" became "at the launch". The bothy's smoke is a thin wisp, so the snowy Frostback never reads as a volcano (the next film opens on 20 November 2026). No Warden hatch is in the Green or on the Crest.

**For the lead (lives in other documents)**
- If "horn" joins the banned-terms review list, as the film research suggests, two sound words would be flagged: the "start horn" (Roadmap §1, arena-events §7–§8) and the Floodgate's horn (arena-events §4.1, kept here to match).
- The Jubilee Games' 48 contenders (Roadmap Phase 9) sit close to a source twist, as the film research notes. They would also halve the room per contender in this Vale, and the SpirePlatform has only 24 openings.
- The Roadmap edits listed in §7.8 (Phase 2a's six slots, the world that Phases 2b and 3 wait for, Phase 5's "done when"), and the risk to the release date in §9.2.
- Still estimates until they are measured: the 62k-model server total, the Spire-disc count, the generation times and every phone budget.
