# LAST STANDING — Roadmap

*The lead designer's plan, 11 November 2026. It turns your notes ([UserNotes.md](design/UserNotes.md)) into a build order for this game. The five pillar designs hold the detail: [Arena events](design/arena-events.md) · [Loot and equipment](design/loot-equipment.md) · [Economy and cosmetics](design/economy-cosmetics.md) · [Modes and progression](design/modes-progression.md) · [Story and world](design/story-world.md). Sizes are for one strong developer with AI help: **S** a day, **M** a few days, **L** 1–2 weeks, **XL** more. Eight decisions for you are at the end.*

## 1. The vision

LAST STANDING is a first-person survival game staged as a show. Twenty-four contenders rise on the launch plates around the Spire into a realistic forest valley, and from the start horn the Citadel is watching. The arena is not just a map to fight in: it is a controlled spectacle. The Wardens watch every contender and step in about every two minutes, with Ember Rain over open ground, a Splice pack loosed from a hatch, a flood down the gorge or a sector sealed off, so no hiding place stays safe for long. The audience's Favour turns daring and survival into Patron capsules that drift down on parachutes. Alliances form on their own around a fire and break at the border, and each dusk the Roll Call draws the fallen in light across the sky. Around this one round the game grows outward: a story of the Accord told through playable characters, our own past Games to relive and rewrite, the Jubilee Games as special editions, and a fair economy in which Gold and Robux only ever buy looks.

## 2. Glossary

Our own names, used everywhere the game speaks. Anything can be renamed: the names will live in one module (`Shared.Lore`, created in Phase 2), so a rename is a single edit.

| Name | What it is |
|---|---|
| **LAST STANDING** | the show, and the game |
| **contenders** | the players in a round |
| **the Spire** | the central supply monolith (in the lore, the Cleft: the split, iron-bound stone on our sigil) |
| **launch plates** | the 24 plates that raise the contenders into the arena |
| **the border** | the force field that closes in on the Spire |
| **the Roll Call** (the Fallen) | the nightly sky show of everyone who fell that day |
| **the Knell** | one deep toll from the Spire's iron bands for each contender who falls; it replaces today's cannon |
| **the Offering** | the Spire's restock on the second morning (the live code and HUD still say Feast) |
| **the Vale** | the arena valley. The lobby island is **the Tor**, and its courtyard **the Waiting Grounds** |
| **the Accord** | the nation, and the peace it was founded on |
| **the Citadel** | the capital |
| **the Provinces** | the regions, named for their industry: Ironreach, Timberline, Saltmarsh, Graincross, Coalbank (the lore adds Glasswater, Quarrymoor and Loomhallow) |
| **the Chancellor** | the nation's leader; in the story, **Elias Kade** |
| **the Tithe** | the yearly selection ceremony |
| **Laureates** | past winners |
| **the Jubilee Games** | the special edition held every 25 years; in play, a 48-contender event. Each Jubilee has a **Writ**: its announced rule change |
| **the Unbound** | the quiet resistance in the story |
| **the Wardens** | the arena's directors |
| **Warden events** | the challenges the **Warden Director** launches about every two minutes: Ember Rain, Splice Hunt, the Lure, the Miasma, the Floodgate, Rockfall, Cold Snap and Sector Lockdown |
| **Splices** | engineered creatures; first **Splice hounds**, led by a **Packleader** |
| **Patrons** | supporters who send **Patron capsules**: supply capsules on parachutes |
| **Favour** | the audience's support for a contender, earned during a round |
| **Citadel broadcasts** | the show's announcements, read by **the Herald** (the Wardens' synthetic voice) and drawn in the sky on **the Skycast** |
| **the Showcase** | the pre-Games interview |
| **the Assessment** | the training run, graded with the **Mark** (1–10) |
| **Citadel modifications** | engineered upgrades fitted to kit, found in **Citadel cases** |
| **Gold** | the in-game currency |
| **Finishes, Tempers, Trails** | cosmetic looks for items; they never change a number |
| **Standard** | the everyday 24-contender round |
| **the Wardens' Gauntlet** | the premium mode, opened by the **Gauntlet Pass** |
| **Archive Games** | our lore's past Games, played again; **Unbound Records** rewrite how they ended |
| **Endless Arena** | co-op survival against ever-harder Warden events |
| **Private Games** | private servers with a host panel |
| **home Province, Talents, Mastery** | a Province identity, one small sidegrade, and cosmetic weapon mastery |
| **Daily Trials, Seasons, Achievements** | daily goals, eight-week Seasons and one-off feats |
| ***The Hundredth*** | the story campaign, building toward the 100th Games |

## 3. Where we are now

Checked read-only in Studio and against the build reports on 11 November 2026.

- **The round loop is complete but not yet proven live.** `RoundService` runs Lobby → Intermission → Countdown → Active → Ending for up to 24 contenders, with hunger, thirst, regeneration, kill credit, spectating and practice rounds. The build agents tested it in sandbox simulations; a full multi-client playtest is still ahead.
- **The classic forest arena is laid out, but the place still has the v1 terrain and dressing.** `ArenaLayout` v2 describes the meadow and Spire plaza, the forest, the lake, the river gorge and falls, the cliffs with three caves, the Field, the marsh and the mountains. The generator in the place is still v1: `ServerStorage.WorldGen.TerrainGen` has `VERSION = 1` (line 26), builds the v1 sectors Highlands, Woodland, Lakeside, Swamp and PineForest (lines 164–168, the same code as `Archive_v1.TerrainGen_v1`), never reads PlateTube, Caves, Escarpment or TerrainSeed, and the `WorldGen.TerrainData` grid that v2 writes is missing. A `VERSION = 2` generator was written before the 11 November network outage but never installed in the place. A full run of it writes `WorldGen.TerrainData`, which is missing, so it hasn't carved this arena. (Update, 12 November: TerrainGen v2.1 is now installed, and the arena is dressed with the realistic art. See [docs/handoff/Status.md](handoff/Status.md).) The place still holds the v1 points of interest and foliage folders, and the Spire is a part-built placeholder without crate alcoves.
- **The realistic art is built but not imported.** Textured trees, ground, landmarks (including the Spire with its crate alcoves and Beacon), buildings, props and items exist as Blender exports. They are already re-exported with tangents (`art/README.md` §11.3: TANGENT, NORMAL and TEXCOORD_0 on every primitive; `ad_finalize` reports 0 problems for all six sets) and wait for one upload each (8 GLBs, 77 PNGs), SurfaceAppearance import and templates.
- **The show's set pieces are built and sandbox-tested (not yet seen live).** The 24 launch plates rise out of their tubes. The clock runs two days in 15 minutes, with a 2.5-minute night. The Offering restocks the Spire at 9:50 (the code and HUD still call it the Feast), the border closes from 10:00 to 13:50, and at each dusk the Roll Call draws the fallen in the sky as point clouds. Every death still fires a cannon, which the Knell replaces in Phase 1. LightingStyle is Realistic, with PrioritizeLightingQuality on. An agent set it in the Edit datamodel on 11 November and read it back; game scripts can't change it at runtime.
- **Movement and first person.** Momentum movement with sprint, stamina, crouch, slide, mantle, climb and swim, and a retuned 3-stud jump. Your original hands are back, holding the mesh items (restored today), and the bow-aim fix is running now. Avatars are still forced to standard proportions.
- **Combat and loot.** Server-checked melee, bow and throws, with predicted projectiles and headshots; 20 items, 6 slots, three crate tiers and 169 loot markers. Other players' attacks aren't animated yet, and armour is one flat multiplier.
- **UI and sound.** HUD, lobby, overlay, settings and spectate screens for PC, phone and gamepad, checked by a layout harness but not yet by eye; a full sound set with ambience, music and ducking.
- **Saving is minimal.** `DataService` saves Wins, TotalKills, RoundsPlayed and Settings (`PlayerStats_v1`, delta saves, no session lock).
- **The lobby island is ready for more.** It has a central fire on a dais, four pavilions, two notice boards and eight banners.
- **Not started:** Warden events, Splices, Favour and Patrons, any Robux code (no script uses `MarketplaceService`), modes, progression and story.
- **The spec lags the code.** `docs/GameDesign.md` is still v1 (its §11 lists the old sectors); update it as each phase lands.

## 4. The master checklist

All 55 items of the notes' master checklist, in their groups and order, with our names. **55 items: 2 Built, 10 Partly built, 43 Not started.** Phase numbers refer to §5; an arrow means the item grows over several phases. The Pillar column links to the detail.

### Your raw notes, line by line

Every line of your raw notes, quoted, with the checklist items that carry it and the phases they land in.

| Your note | Checklist items | Phase |
|---|---|---|
| "STORY MODE OPTION _ PLAYABLE CHARACCHTERS ETC" | 1, 2 | 7 → 10 |
| "DIFFERENT ARCS - KILL SNOW ETC DIFF OPTIONS" | 3, 4 | 7 → 10 |
| "UNLOCK DIFF ARCS" | 5 | 10 |
| "TYPES OF EXPENSES" and "SMALL PACKAGE ETC" | 28–32 | 6a → 6b |
| "SKILLS" | 19 (Talents), also 15 and 17 | 8 (#15: 9 → 10) |
| "PREMIUM GAMEMODE" | 33, 49 | 9 → 10 |
| "GAME ENHANCEMENTS - SMALL MONEY 5 ROBUX E.G" | 32 | 6a → 6b |
| "IN GAME CURRENCY - GOLDS" | 28 | 6a |
| "BUY CURRENCY WITH ROBUX" | 29 | 6a |
| "BUY VISUAL EFFECTS FOR ITEMS" | 35, 36 | 6a → 6b |
| "TRAILS ETC" | 37 | 6a → 6b |
| "EFFECT DROPS (ENCHANTMENTS)" | 22 | 4 |
| "EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES - ESCAPE LAVA RAIN ETC WILD DOGS MUTATED ANIMALS ETC" | 8, 9, 11 | 2 → 3 (#9 also 10) |

### 1. "Story and narrative" (6)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 1 | "Story mode" | Story mode: *The Hundredth*, chapters in reserved servers, solo or co-op up to 3 | Not started | 7 → 10 | XL | [Story](design/story-world.md) |
| 2 | "Different playable characters" | Oss Reed, Maren Holt, Ines Calder-Voss and Teo Strand | Not started | 7 → 10 | L | [Story](design/story-world.md) |
| 3 | "Different narrative arcs" | Four arcs: The Tithe, The Ledger, The Hall, The Hundredth | Not started | 7 → 10 | XL | [Story](design/story-world.md) |
| 4 | "Alternative outcomes — including killing Snow" | Branching endings: Arc I's two endings, then the Chancellor's fall (Expose, Depose, Strike, the Last Laureate) | Not started | 10 | L | [Story](design/story-world.md) |
| 5 | "Unlockable story arcs" | Unlockable arcs, Archive reels and the chapter board | Not started | 10 | M | [Story](design/story-world.md) |
| 6 | "Historical Hunger Games campaigns" | Archive Games as story records: the First Tithe, the Dusk Writ, the Silent Writ, the Flood Games, the 86th | Not started | 10 | XL | [Story](design/story-world.md) |

### 2. "Arena gameplay" (8)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 7 | "Cornucopia and starting equipment" | The Spire, the launch plates and the starting loot | Partly built | 1 | M | [Arena](design/arena-events.md) |
| 8 | "Gamemaker-controlled challenges" | Warden events, picked by the Warden Director about every two minutes | Not started | 2 → 3 | L | [Arena](design/arena-events.md) |
| 9 | "Mutts and genetically engineered animals" | Splices: Splice hounds and their Packleader, more species later | Not started | 2 → 3 → 10 | XL | [Arena](design/arena-events.md) |
| 10 | "Poisonous environments" | The Miasma and brackish marsh water | Not started | 3 | M | [Arena](design/arena-events.md) |
| 11 | "Environmental hazards" | Today's fall, starvation, thirst and void damage, then Ember Rain, Rockfall, the Floodgate and Cold Snap | Partly built | 2 → 3 | XL | [Arena](design/arena-events.md) |
| 12 | "Arena manipulation" | Warden arena manipulation: the Lure, lasting changes, the Offering | Partly built | 2 → 3 | M | [Arena](design/arena-events.md) |
| 13 | "Force fields and restricted zones" | The border and Sector Lockdowns | Partly built | 3 | M | [Arena](design/arena-events.md) |
| 14 | "Randomised match events" | The Director's seeded draw each round, Arena Edicts later | Not started | 2 → 10 | M | [Arena](design/arena-events.md) |

### 3. "Character and skills" (6)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 15 | "Character abilities" | Signature abilities (Story, Endless, Private Games) and Endless Boons | Not started | 9 → 10 | L | [Modes](design/modes-progression.md) |
| 16 | "District-specific backgrounds" | Home Province and Province rank | Not started | 8 | M | [Modes](design/modes-progression.md) |
| 17 | "Skill progression" | Mastery: looks and titles, never power | Not started | 8 | M | [Modes](design/modes-progression.md) |
| 18 | "Character unlocks" | Characters unlocked by play | Not started | 10 | M | [Modes](design/modes-progression.md) |
| 19 | "Specialisations" | Talents: one small sidegrade per contender | Not started | 8 | L | [Modes](design/modes-progression.md) |
| 20 | "Character-specific equipment" | Signature gear for the story characters | Not started | 7 → 10 | L | [Loot](design/loot-equipment.md) |

### 4. "Loot and equipment" (7)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 21 | "Equipment drops" | Supply drops: crates, the Offering, Patron capsules, Citadel cases, Warden strongboxes | Partly built | 3 → 4 → 10 | L | [Loot](design/loot-equipment.md) |
| 22 | "Rare equipment modifications" | Citadel modifications (the raw notes' "EFFECT DROPS (ENCHANTMENTS)") | Not started | 4 | XL | [Loot](design/loot-equipment.md) |
| 23 | "Weapons and armour" | Arena weapons and armour, with armour integrity; two Citadel prototypes later | Built | 1 → 4 → 10 | L | [Loot](design/loot-equipment.md) |
| 24 | "Survival supplies" | Food, water, packs (Satchel, Rucksack, Citadel Frame Pack) and the Steel Canteen | Partly built | 4 | L | [Loot](design/loot-equipment.md) |
| 25 | "Medical supplies" | Field medicine: today's Healing Herbs, Bandage and Med Kit, then Field Dressing, Splint, Antitoxin, Electrolyte Draught and the Mending Kit | Partly built | 4 | M | [Loot](design/loot-equipment.md) |
| 26 | "Rarity tiers" | Common to Legendary; a Legendary is a Citadel prototype, one per round | Partly built | 4 | M | [Loot](design/loot-equipment.md) |
| 27 | "Special rewards" | Offering prizes and Warden strongboxes; the Arms Register, Laureate and Mastery finishes | Not started | 4 → 8 | L | [Loot](design/loot-equipment.md) |

### 5. "Economy and monetisation" (7)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 28 | "Gold currency" | Gold | Not started | 6a | L | [Economy](design/economy-cosmetics.md) |
| 29 | "Buying Gold with Robux" | Gold packs, granted by one receipt handler in StoreService | Not started | 6a | M | [Economy](design/economy-cosmetics.md) |
| 30 | "Small purchase packages" | The Purse and the Satchel (the Contender's Kit later) | Not started | 6a | S | [Economy](design/economy-cosmetics.md) |
| 31 | "Medium and large packages" | The Coffer, the Chest and the Vault | Not started | 6a → 6b | S | [Economy](design/economy-cosmetics.md) |
| 32 | "5 Robux microtransactions" | Pocket buys: the Gold Pouch and the Signal Flare | Not started | 6a → 6b | S | [Economy](design/economy-cosmetics.md) |
| 33 | "Premium game access" | The Gauntlet Pass | Not started | 9 | M | [Economy](design/economy-cosmetics.md) |
| 34 | "Game passes" | Gauntlet Pass, Supporter Crest and Wardrobe Pass (no Prospector Pass at launch; revisit after a month of economy data) | Not started | 6b → 9 | M | [Economy](design/economy-cosmetics.md) |

### 6. "Cosmetics" (7)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 35 | "Visual effects for items" | Finishes (looks for weapons and items) and Tempers (a quiet effect layer) | Not started | 6a → 6b | L | [Economy](design/economy-cosmetics.md) |
| 36 | "Weapon effects" | Elimination effects | Not started | 6b | M | [Economy](design/economy-cosmetics.md) |
| 37 | "Trails" | Trails for arrows, throws and swings | Not started | 6a → 6b | M | [Economy](design/economy-cosmetics.md) |
| 38 | "Character skins" | Province outfits and Citadel couture | Not started | 6b | XL | [Economy](design/economy-cosmetics.md) |
| 39 | "Animations" | Emotes, gestures and Inspect | Partly built | 6b | M | [Economy](design/economy-cosmetics.md) |
| 40 | "Victory effects" | Celebrations, Entrances, the Showcase banner and the Laureate plinth | Not started | 6b | L | [Economy](design/economy-cosmetics.md) |
| 41 | "Parachute effects" | Canopies for Patron capsules | Not started | 6b | M | [Economy](design/economy-cosmetics.md) |

### 7. "Capitol systems" → Citadel systems (6)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 42 | "Gamemaker controls" | Warden controls: Director settings and a Studio trigger, then the host panel, a spectator vote and the Warden's Chair (sized in #49) | Not started | 2 → 8 → 9 → 10 | M | [Arena](design/arena-events.md) |
| 43 | "Sponsor gifts" | Patron capsules | Not started | 3 | L | [Arena](design/arena-events.md) |
| 44 | "Audience popularity" | Favour and the Favourite of the Games | Not started | 3 | M | [Arena](design/arena-events.md) |
| 45 | "Tribute interviews" | The Showcase | Not started | 7 | M | [Story](design/story-world.md) |
| 46 | "Training scores" | The Assessment and the Mark (1–10) | Not started | 7 | L | [Story](design/story-world.md) |
| 47 | "Capitol broadcasts" | Citadel broadcasts: the broadcast card, the Herald and the Skycast | Partly built | 2 → 3 → 7 | M | [Arena](design/arena-events.md) |

### 8. "Game modes and progression" (8)

| # | The notes say | Our name | Status | Phase | Size | Pillar |
|---|---|---|---|---|---|---|
| 48 | "Standard Hunger Games" | Standard: the everyday 24-contender round | Built | 5 → 8 | M | [Modes](design/modes-progression.md) |
| 49 | "Premium game mode" | The Wardens' Gauntlet: the Warden's Chair, premium arenas, Nightmare Endless | Not started | 9 → 10 | XL | [Modes](design/modes-progression.md) |
| 50 | "Story campaigns" | Story unlocks and rewards | Not started | 7 → 10 | M | [Modes](design/modes-progression.md) |
| 51 | "Historical Games" | Archive Games as a mode: a weekly vote in Standard, laurels, the Archive Book | Not started | 8 → 9 | L | [Modes](design/modes-progression.md) |
| 52 | "Alternative timelines" | Unbound Records: Archive Games with rewritten outcomes | Not started | 10 | S | [Modes](design/modes-progression.md) |
| 53 | "Achievements" | Achievements: 20 at launch, 6 of them Roblox badges | Not started | 5 | M | [Modes](design/modes-progression.md) |
| 54 | "Daily challenges" | Daily Trials | Not started | 5 | S | [Modes](design/modes-progression.md) |
| 55 | "Seasonal content" | Seasons | Not started | 9 | L | [Modes](design/modes-progression.md) |

## 5. Phases

### Build order at a glance

| Phase | Goal | Starts after | Size |
|---|---|---|---|
| **1. Foundation** (under way) | The base round looks, moves and fights the way you want, proven in a multi-client playtest | — | XL |
| **2. The Wardens wake up** | Your headline: a new challenge every couple of minutes, and the first Splices | 2a: now, alongside Phase 1; 2b: Phase 1's v2 terrain and set dressing | L + L |
| **3. A living arena** | The full event set, real Splices, Favour, Patron capsules and the Herald | 2 | XL |
| **4. Effect drops and the kit** | Your effect drops as Citadel modifications, then traps, packs and field medicine | 3, and Phase 1's combat damage model | XL |
| **5. The profile** | Saved progress for everything after it: levels, Achievements, Daily Trials | Phase 1's playtest | XL |
| **6. Gold and the store** | Gold, Robux packs and looks, never power | 5 | L, then an XL art track |
| **7. Before the Games, and Chapter One** | The Showcase, the Assessment and the first story chapter | 3 and 5 | XL |
| **8. Who you are, how you play** | Home Provinces, Talents, Mastery, Archive Games and Private Games | 5 and 6a | XL |
| **9. Big modes and Season 1** | Endless Arena, the Wardens' Gauntlet, the Jubilee Games and Seasons | 3 and 8 | XL |
| **10. The story continues** | The rest of the campaign and ongoing live content | 7 | XL, ongoing |

**First public release:** after Phase 6a. That release has the realistic arena with Warden events, Splices, Patron capsules and effect drops, saved progress, and a small, honest store. On these estimates that is roughly 32–41 weeks for one developer: Phase 1's remaining 8–12 weeks, then Phases 2 (3.5–4), 3 (9–12), 4 (6–7.5 of code), 5 (about 3) and 6a (about 2), before Phase 4's art. Phase 4b can move after the release if a date presses.

### Phase 1 — Foundation (under way)

**Goal.** Finish the work already in progress, the rest of the Part 2 and Part 3 plans (`docs/handoff/Part2Plan.md`). When it ends, the base round looks realistic, moves well, fights with weight and has passed a real multi-client playtest.

| Work | Where it stands | What's left | Size |
|---|---|---|---|
| Realistic arena art | Textured trees, ground, landmarks (including the Spire with `CrateSlot_1–4` and the `Beacon`), buildings, props and items are exported from Blender with tangents; none is in the place yet | Upload each set once (8 GLBs, 77 PNGs), import with SurfaceAppearances from the manifests, build templates (integrate:world-assets, integrate:items-realistic) | L |
| Terrain and set dressing | Done on 12 November (see [Status](handoff/Status.md)): TerrainGen v2.1 is installed and Populate v2 dresses the arena. Before that, ArenaLayout v2 was in the place but its generator was not. The place still holds the v1 terrain, v1 points of interest, v1 foliage folders and the part-built Spire | Install TerrainGen v2 in `ServerStorage.WorldGen` and run it (it writes `WorldGen.TerrainData` and sets TerrainVersion 2), then world:set-dressing from `ArenaLayout` v2, with new loot markers from its `LootZones`, hidden-cache markers, and the Spire's broadcast panels (Parts with SurfaceGuis, no new upload) | L + M |
| First-person hands | The original part-built hands are back, holding the mesh items (restored today) | — | done |
| Bow aim | The v1 bow pose hides the target while you aim | The bow:aim-fix pass (running now), then its screen-coverage check again after the ItemsReal swap | S |
| Movement and jump | Momentum movement is in; the jump is retuned to a 3-stud hop with no bunny-hopping | movement:polish: your "jumping is tacky" check, and natural avatar proportions on measured rigs | M |
| Day/night and the Fallen | The two-day cycle and the Roll Call work; LightingStyle is Realistic (set in the Edit datamodel on 11 November) | Hide the sun/moon switch that lands in Roll Call 1, tune readability; open and close the Roll Call on the day caption (DUSK · DAY ONE, 4 FELL TODAY) instead of the Cleft sigil, and never give it an anthem or music bed | S |
| Death signal | Every death fires a cannon (`PlayerService` line 513, `Shared.Sounds.Cannon`, the `AudioController` duck), and the notice board says "Listen for footsteps and the cannon." (`WorldGen.AssetBuilder.Props` line 442) | Swap in the Knell: a licensed struck-iron toll as `Sounds.Knell`; rename the key in `PlayerService` and `AudioController`; rewrite the notice line as "Listen for footsteps and the Knell." | S |
| Look-dev shading | The playbook's 12 prioritised tasks are written up | DayCycle rebalance, valley skybox, terrain PBR, wind, eye adaptation, atmosphere, firelight, budgets | L |
| Playtest | Sandbox-tested only | qa:integration: the full loop with several clients, on low quality levels too | M |
| Combat physics | Planned in `docs/research/CombatPhysicsPlan.md` (phases 0–7) | Committed swings, third-person attack poses (`CombatAction` on other players; CombatPhysicsPlan phase 1), lag-compensated hits, hit zones and torso armour, reactions, real projectile physics, ragdolls, no blood | XL |

**Depends on:** uploads clearing moderation, and decision 3 before combat physics starts.

### Phase 2 — The Wardens wake up

**Goal.** Your headline note, "EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES", in every Standard round, with the first Splices. It comes in two parts, so the headline isn't held behind set dressing and upload moderation.

- **2a — The Director and Ember Rain (L, about 2 weeks).** It starts now, alongside Phase 1, on today's terrain; Ember Rain cover is checked again after set dressing.
  - `WardenService` with the **Warden Director**: six slots a round (about 2:30, 4:15, night, dawn, 10:30 and 12:00), one event at a time, quiet times around the Roll Call and the Offering, zones scored from a per-round seed, and a `DevWarden` trigger for Studio.
  - The **Citadel broadcast** card (text only), the HUD event line, a compass icon and an inside-the-zone alert.
  - **Ember Rain**, with cover checks and fire patches.
  - **The Lure v0**: a tier-3 crate dropped at a contested spot with the existing Offering drop.
  - Damage plumbing: `fromPosition` for every cause, and death and kill-feed text for Fire and Splice.
  - Create `Shared.Lore` (S), so Warden events, broadcasts and later the store read their names from it; Phase 7 keeps the lore pass.
  - The banned-terms check from §7: a `ServerStorage.Dev` script, run with SyntaxCheck before each publish.
- **2b — Splice Hunt v0 (L, about 1.5–2 weeks).** `SpliceService` on the `AgentService` core, after Phase 1's v2 terrain and set dressing, so hound paths are final.
  - 2–4 placeholder hounds in a new `SpliceService` on a shared `AgentService` core. Pathfinding on a budget, at most two hounds biting at once, a 0.45 s lunge warning, bites through `CombatService.applyHit`.

**Depends on:** 2a needs nothing more from Phase 1 to start. 2b, and the second check of Ember Rain cover, need Phase 1's v2 terrain and set dressing, because cover and hound paths need the final world; Phase 3's Floodgate, Rockfall and Miasma need its gorge, escarpment and marsh too. The small edits to `CombatService`, `PlayerService`, `NotificationController` and `HUDController` are coordinated with the Phase 1 teams.

**Done when:**
- **2a:** a Studio round at `StudioTimeScale` 6 runs events in all six slots, never two at once and never during a Roll Call or the Offering; a contender who reacts takes at most 25 Ember Rain damage; everything is cleaned up when the round ends; and a 4-client playtest passes.
- **2b:** hounds reach and bite a contender, never more than two at once, and every weapon can kill one; kill credit works when a rival leads the pack to a contender; and `SpliceService` costs at most 1.5 ms a frame with 4 hounds.

**Size:** L + L (3.5–4 weeks).

### Phase 3 — A living arena

**Goal.** The full first set of Warden events, real Splices, and the audience's part in the show.

- Five more Warden events: **the Miasma** (with brackish marsh water), **the Floodgate**, **Rockfall**, **Cold Snap** and **Sector Lockdown**.
- Real Splices: the Blender hound and its animations, the **Packleader** and its collar cache, the **Night Hunt**.
- **Favour** and **Patron capsules**: earned in the round and never sold. Contents follow need, from one table, graded Basic, Fine and Gilded at 100, 250 and 450 Favour.
- **The Herald's** voice on broadcasts, the Offering and the border, text-to-speech first.
- Telemetry: deaths by cause, and how many contenders come through each event.
- Art: the Blender hound with about 14 animations (L), the Patron capsule and drogue chute (M), the Warden hatch (S), and the Filter Mask and Thermal Wrap that arena-events.md §7 and §9 add (ItemsReal meshes, `Rig.HOLDS` entries and use poses; S each).

**Depends on:** Phase 2, Phase 1's v2 terrain (the Floodgate, Rockfall and the Miasma need its gorge, escarpment and marsh), decision 2, and licensed creature, fire, water and rock sounds.

**Done when** `SpliceService` stays at or under 1.5 ms per server frame with 8 hounds in a 24-contender round; a mid-range phone holds 30 fps through Ember Rain and a night pack; the Floodgate's voxel writes are capped and restore the gorge exactly; and telemetry logs deaths by cause.

**Size:** XL (about 9–12 weeks).

### Phase 4 — Effect drops and the kit

**Goal.** Your "EFFECT DROPS (ENCHANTMENTS)" as **Citadel modifications**: engineered parts the Wardens send into the arena. Never magic, never sold.

- **4a — Citadel modifications (L, 2–2.5 weeks).** Items carry state (mods and wear) through drops, deaths and pickups. `Shared.ItemStats` and leaner loot tables: about 7 stacks per contender instead of 8.6, and fewer bows. Armour integrity and the Mending Kit. A quiver with a `CycleAmmo` key, and Broadhead, Pitch and Whistler arrows, with Bleeding and Burning. Three mods: Plate Insert, Tempered Edge and String Dampers. Citadel cases in Spire crates, at the Offering and as the Lure's gift. Rarity rules and caps.
- **4b — New kit (XL, 4–5 weeks).** Traps and their mods, packs and 6–9 slots, field medicine and statuses, Ghillie Netting, Balanced Haft, Citadel Limbs and the Steel Canteen.

**Done when (4a):** a sandbox run shows each arrow effect, integrity draining and being mended, a fitted mod surviving drop, death and pickup, and the caps holding; then a 2-player playtest confirms the feel.

**Depends on:** Phase 1's combat damage model (agree `InventoryService.absorb` and the `PlayerService` status API first) and the ItemsReal swap.

**Size:** XL: 6–7.5 weeks of code plus about 4–5 weeks of item art and first-person work (loot-equipment.md §12: arrowheads, the Citadel case and kits, 11 mod visuals, 3 traps, packs and netting, medical items, and the new Apply and Place use styles). That is about 10–12 weeks for one developer.

### Phase 5 — The profile

**Goal.** Saved progress, built once for every later phase.

- One profile, **`Profiles_v2`** (key `u_<UserId>`, session-locked with ProfileStore or Roblox's reference pattern), owned by an extended `DataService` that keeps today's API. A one-time import from `PlayerStats_v1`, which stays as a read-only backup.
- `ModeService` and `Shared.Rules`, with a Standard preset equal to today's numbers.
- XP and levels 1–50, 20 Achievements (6 of them Roblox badges), Daily Trials (three that bank up, one free reroll a day, no streaks), the Round Report after each round, and a profile card in the lobby.

**Depends on:** Phase 1's playtest. It can run alongside Phases 3 and 4 if a second developer joins.

**Done when** existing stats survive the import, two servers never write one profile, the Standard timeline is unchanged (the Offering at 590 s, the border from 600 to 830 s), and private servers and practice rounds award nothing.

**Size:** XL (about 3 weeks).

### Phase 6 — Gold and the store

**Goal.** Gold, Robux purchases and looks, never power.

- **6a — Wallet and Armoury (L, about 2 weeks).** **Gold** from rounds: taking part, placement, eliminations and the win, with limits for small and AFK lobbies. `StoreService` with the game's only `ProcessReceipt`. Four Developer Products, the Gold Pouch, Purse, Satchel and Coffer, at 5, 49, 99 and 199 R$ by default (the store shows Roblox's live price). Six **Finishes** and three arrow **Trails**, STORE v0 with an "in your hands" preview, and the Armoury pavilion. **The first public release follows.**
- **6b — Cosmetic depth (XL, 6–8 weeks, mostly art, alongside Phases 7–9 only if someone else makes the art; for one developer it adds 6–8 weeks).** Tempers, elimination effects, swing trails, Entrances, the Showcase banner, Province outfits and Citadel couture with matching first-person sleeves, emotes and Inspect, Celebrations and the Laureate plinth, Canopies, "Buy with Robux", the Contender's Kit, the Chest and the Vault, the Signal Flare, the Supporter Crest and the Wardrobe Pass. Hidden caches: sealed tins in hard places (cave chamber, waterfall shelf, watchtower) with 25–60 Gold, or rarely an unowned Temper; markers placed by the set dressing.

**Depends on:** Phase 5 and the products set up in the Creator Dashboard. 6b also needs the third-person attack poses (Phase 1), the Spire's broadcast panels (Phase 1's set dressing) and Patron capsules (Phase 3).

**Done when** (6a gates the first public release): a round's Gold is still there after a rejoin; a Studio test purchase of the Purse grants 500 Gold exactly once even when ProcessReceipt runs twice with the same PurchaseId; a purchase made while the profile loads waits, then lands; two servers can't hold one profile; no Robux price is hard-coded; a bow finish shows in first person and to a second player, and a dropped bow is plain.

### Phase 7 — Before the Games, and Chapter One

**Goal.** The pre-Games beats in the live lobby, then the first chapter of the story.

- **The Showcase**: a question card in Intermission with four answers (Bold, Warm, Cunning, Quiet); featured answers appear on the fire dais and the Skycast. Reputation only.
- **The Assessment**: a 90-second run in the Assessment Hall (the Dummies, the Long Lane, the Wall), graded with the Mark and saved as BestMark. It gives players who fell or joined late something to do.
- The lore pass on the lobby, Intermission and victory text, through `Shared.Lore` (created in Phase 2). It includes the Offering's live strings and code ids (§7).
- Story tech: `StoryService` (reserved servers, a `DevChapter` Studio hook, director hooks in `RoundService` and `ArenaService`), `NarrativeController`, `SkycastController` (the Roll Call show, generalised) and story NPCs on `AgentService`. `StoryService` writes the game's first teleport and reserved-server code; Phase 9's `MatchService` extends it.
- **Chapter One, "The Tithe"**: 15–18 minutes, solo or co-op for the three Saltmarsh contenders, playing Oss Reed with his signature gear.

**Depends on:** Phases 3 and 5, decision 8, and a voice approach (text-to-speech first).

**Size:** XL (about 8–11 weeks): 2–3 for the Showcase and the Assessment, and about 6–8 for Chapter One (story-world.md §12: StoryService L, NarrativeController L, AgentService v1 for humanoid NPCs L, SkycastController M, Chapter One content L).

### Phase 8 — Who you are, how you play

**Goal.** Identity and variety inside Standard, where most players are.

- **Home Province**, chosen at the central fire, with Province rank and Province standings each Season.
- **Talents**: 15 small sidegrades, three per Province, unlocked by play, with win-rate telemetry and an off switch (decision 7).
- **Mastery**: weapon finishes, trails and titles earned by use, plus the Arms Register and Laureate finishes.
- **Archive Games**: a weekly vote in Standard Intermissions, the first five entries, and laurels.
- **Private Games**: paid private servers with a host panel that includes Warden controls. No XP or Gold.
- The `SecondsToRound` matchmaking signal, 26-player servers and sit-out priority, so late joiners wait less.

**Depends on:** Phases 5 and 6a.

**Size:** XL (about 6 weeks).

### Phase 9 — Big modes and Season 1

**Goal.** More ways to play, and a live cadence.

- `MatchService`: MemoryStore queues, parties, reserved servers and safe teleports.
- **Endless Arena**: co-op waves of Warden events, with Boons.
- **The Wardens' Gauntlet**: the Gauntlet Pass, starting with **the Warden's Chair** (one pass owner directs the Warden events for friends), then Nightmare Endless (premium arenas are separate world builds, XL each, in Phase 10).
- **The Jubilee Games**: the 48-contender place, its performance work and its first weekend, with a Writ.
- One codebase across the start place and the Jubilee place (Packages or the export pipeline, with a build stamp checked at server start).
- **Season 1**: a free 30-tier track, weekly challenges, Province standings, ladders, and the Archive Book queue.

**Depends on:** Phases 3 and 8, Phase 1's TerrainGen v2 (the Jubilee place is built by the same generator), decisions 4 and 5, and enough players online to fill queues.

**Done when** a 48-dummy load harness with Warden events and 8 Splices running keeps server heartbeat at or above 55 Hz, at least 30 fps on a mid-range phone and 60 fps on a mid PC, at the launch and in Ember Rain; `FallenSnapshots` MAX_SNAPSHOTS (40 today) is raised to 48 and the Roll Call groups busts on big days; `CharacterVisuals` POSE_RANGE (150) gets level-of-detail; and a live test with 30 or more players passes before the first Jubilee weekend.

**Size:** XL (8–10 weeks).

### Phase 10 — The story continues, and the long tail

**Goal.** The rest of the campaign, and content that keeps the show fresh.

- Arc I chapters 2–4 with both endings and the chapter board, using `AgentService` v2 for full NPC contenders. Then Arcs II–IV and the Chancellor's fall.
- Archive records with their Unbound Records (the 86th first); character unlocks, signature abilities and signature gear.
- Live content: Warden strongboxes, Citadel prototypes and special kit, new Splice species, Arena Edicts, spectator backing and the event vote, Offering guards, and premium arenas (separate world builds, XL each).

**Depends on:** how Chapter One lands (if it lands well, Arc I can move ahead of Phase 9), and decision 6.

**Size:** XL, ongoing.

## 6. How the pillars fit together

Where the pillar designs overlapped, the roadmap makes one call. The pillar files carry the same calls as lead notes.

| Topic | The call |
|---|---|
| Saved data | One profile, `Profiles_v2` (key `u_<UserId>`, session-locked), owned by an extended `DataService` that keeps today's API. Every pillar's fields go into it, story progress included. |
| Your effect drops | "EFFECT DROPS (ENCHANTMENTS)" are **Citadel modifications**: gameplay parts found in the round, earned only, as your own plan suggests. "BUY VISUAL EFFECTS FOR ITEMS" are **Finishes and Tempers**: looks only. |
| Drops in a round | Patron capsules (Favour), Citadel cases (mod kits), the Lure (the Director's bait event, which replaces fixed-schedule drops), Warden strongboxes (later) and hidden caches (Gold, or rarely a Temper). Capsule contents follow need, from one table. |
| One voice | The Herald reads every Citadel broadcast. In the lore it is the Wardens' single synthetic voice, so text-to-speech fits. |
| Premium | "Premium game access" is the Gauntlet Pass; "Premium game mode" is what it opens, the Wardens' Gauntlet. Warden events and the Jubilee Games stay free. |
| Fair play | Daily Trial rerolls are free once a day and never sold. Private Games pay no XP or Gold. Standard keeps the empty-handed start, so there are no Keepsakes. Players keep their own Roblox avatars at normal proportions, as you asked. |
| One Archive | The Story pillar's lore records and the Modes pillar's rule-twist Games are one list, and the Story pillar sets the years. Arena Edicts and Jubilee Writs share one list of rule changes. |
| Provinces | Eight in the lore (three contenders each makes 24). Five home Provinces with 15 Talents at launch; the other three join in a later Season. |
| The lobby | NE **the Armoury** (finishes, trails, Tempers, the Arms Register) · SE **the Outfitter** (outfits, emotes, the Gold and pass counter) · SW **the Archive** (story chapters, Archive Games) · NW **the Gate** (Endless Arena, the Jubilee Games, the Wardens' Gauntlet, Private Games). The fire dais holds Showcase stand-ins during Intermission and the Laureate statue between rounds. Home Provinces are chosen at the central fire, and the Assessment Hall opens off the north walkway. |
| NPC tech | `SpliceService` sits on a shared `AgentService` (paths, perception, steering), which the story NPCs reuse. |
| Names | Warden events (not "Interventions"), Patron capsules, Daily Trials, Season challenges, hidden caches, the Arms Register (the collection log; the Armoury is the pavilion), Late Dawn (the longer-night rule), and, for IP, the Offering (not "the Feast") and the Knell (not a cannon). |

## 7. Platform rules and IP

**Roblox rules we build to** (checked against Roblox's creator documentation on 11 November 2026):

- **Purchases.** Gold packs and the 5 R$ items are Developer Products, passes give lasting privileges, and Private Games are paid private servers. One `ProcessReceipt`, in `StoreService`, grants only receipts whose status is Open, records each PurchaseId in the profile and saves before it returns `PurchaseGranted`; otherwise it returns `NotProcessedYet` and Roblox retries. Nothing is granted from `PromptProductPurchaseFinished`, and prices come from Roblox at runtime.
- **Nothing random is sold.** Random rewards earned in play need no odds. Anything random sold for Robux, or for Gold bought with Robux, would have to show every outcome's odds before purchase and be blocked where `PolicyService` reports `ArePaidRandomItemsRestricted`, so we sell direct purchases only.
- **Cosmetics never change performance.** Nothing that changes fighting, surviving, moving, loot or information is sold for Robux or Gold: not Talents, Citadel modifications, Patron capsules or Favour. Paid looks keep the plain silhouette, add no light and no camouflage, and are never harder to see or trace than the plain version.
- **Maturity label.** A violent survival game with no blood. Realistic first-person fights with ragdolls that stay are expected to be **Moderate** (the questionnaire decides). Roblox computes the label from the questionnaire: who is hurt, how realistic the setting and art are, and whether bodies react realistically, which it describes as blood and wounds. It doesn't rate ragdolls by name, so submit the planned combat answers before decision 3 locks in ragdolls that stay. Moderate is the most a Roblox Select (ages 9–15) game may carry, but a new game first reaches only age-checked players 16+. It opens to Select after the all-ages publishing requirements and an evaluation. The requirements are an age-checked owner account (adults verify with government ID), two-step verification, the completed questionnaire, and two consecutive months of Roblox Plus or Premium or a one-time refundable fee. The evaluation needs 250 unique plays by highly engaged age-checked players within 60 days (Creator Hub › Audience Reach), followed by a safety review. Plan the first public release for a 16+ audience. Splices crumble to ash, growl before they lunge, and there are no jump scares. Update the questionnaire as hazards, creatures and ragdolls ship.
- **No pressure on young players.** No fake sales or restarting timers, no "act now" wording, no purchase prompt without a click, nothing for sale on the death screen and no streaks. Daily Trials bank up, and Season challenges stay open all Season.
- **Data.** A session-locked profile under UserId keys, so data-erasure requests work; rewards decided on the server; every remote validated and rate-limited.
- **Audio.** Replace the Creator Store sounds whose source is unconfirmed before publishing, and credit the CC-BY Material Design sounds.

**Original IP**

- Anything that ships (code, UI text, asset names, story) uses our names. The franchise's names appear only in these docs, inside quotes from your notes.
- A banned-terms check (a `ServerStorage.Dev` script, run with SyntaxCheck before each publish) scans the string literals of every script, plus instance and asset names. That includes the `ServerStorage.WorldGen` builders that write SurfaceGui text and the services that send Announce text. It matches whole words on lowercased text: use a Luau frontier pattern such as `%f[%a]tribute%f[%A]`, because a plain match hits every GetAttribute call. Besides the hard bans, it flags a review list: cannon, feast, career, victor, quell, sponsor, trinket.
- Keep away from the source's signature beats:
  - volunteering for a sibling, two winners, a hand-sign salute, bird or rose emblems, and a 1–12 training score;
  - a cannon shot for each death, and a national emblem and anthem framing the faces of the dead;
  - engineered wasps, voice-mimicking birds, creatures with the faces of the fallen, and creatures driving the last contenders onto the central structure;
  - poison berries as a weapon, a trident as a signature weapon, and silver parachutes;
  - a clock-face arena, and a wall of fire chasing one contender (so there is no wildfire-front event);
  - a final standoff where the last two refuse to fight, a rival falling from the central structure at the finale, a mid-Games rule change that would let two win, and a co-op run that ends with more than one Laureate;
  - a leader reading the 25-year twist, and a Jubilee that sends past winners back into the arena (in Arc IV the Laureates enter the Vale as raiders and mentors, never as drawn contenders);
  - a rich Province that trains its young to win.
- The source has a named feast at its central structure, so ours is **the Offering**, presented our own way: the ember beacon, the bell and the Spire's alcoves. The Phase 7 lore pass renames the live strings in `ArenaService` (lines 294 and 306) and `HUDController` (lines 827–833) through `Shared.Lore`, and the code ids (`Config.Events.FeastTime`, `FeastBell`, `FeastBeacon`, `ArenaEvent = "Feast"`) are renamed in the same pass.

Sources: [paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items) · [content maturity](https://create.roblox.com/docs/production/promotion/content-maturity) · [developer products](https://create.roblox.com/docs/production/monetization/developer-products) · [private servers](https://create.roblox.com/docs/production/monetization/private-servers) · [Kids and Select](https://create.roblox.com/docs/production/publishing/kids-and-select).

## 8. Decisions for you

Each can be answered in a few words. The recommendation comes first.

| # | Question | Recommendation |
|---|---|---|
| 1 | Can a Warden event kill a contender who ignores it? | **Yes.** Anyone who reacts loses at most about 25 health. |
| 2 | Splices: realistic engineered wolf-dogs with ember-lit seams that crumble to ash, or something more monstrous? | **Realistic.** It fits your look and keeps the Moderate label. |
| 3 | Combat physics with the plan's defaults: a simple guard with a perfect-block window, tap for a light attack and hold for a heavy one, ragdolls that stay, no blood? | **Yes.** Phase 1's last step waits on it. |
| 4 | Everyday mode: the 24-contender Standard, with the 48-contender Jubilee Games as scheduled weekends? | **Yes.** Your plan made 48 the base, but 48-player queues won't fill at launch. |
| 5 | Premium mode: a one-time Gauntlet Pass (about 499 R$) that starts with the Warden's Chair, while Warden events and the Jubilee stay free? | **Yes.** |
| 6 | Story: all arcs earned by play, or Arcs II–IV sold? | **Earned by play.** Arc I is free either way. If arcs are ever sold, their characters and signature abilities still unlock only by play, so no bought ability reaches a ladder. |
| 7 | Standard: one small Talent per contender, unlocked by play and never sold? | **Yes**, with an off switch in Private Games. |
| 8 | In our lore, are contenders adults (18–24)? | **Yes.** It keeps the story Moderate and further from the source. |
