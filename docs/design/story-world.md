# Story mode and the world

> Pillar file for the [Roadmap](../Roadmap.md) · key `story-world` · written by the story designer, lightly edited by the lead designer so names match across pillars. Phase numbers inside this file are the pillar's own; the Roadmap's phases are the build order.

**Lead notes (where the Roadmap reconciles this pillar with the others)**

- **Roadmap phases.** This pillar's Phase 1a (the Showcase and the Assessment) and 1b (Chapter One) are Roadmap Phase 7, after the profile (Phase 5), so the Mark is saved from day one. Its Phases 2–4 are Roadmap Phase 10.
- **Saved progress** goes into the one shared, session-locked profile (`Profiles_v2`), so §4.4 is superseded.
- **Renamed for consistency:** Warden events (was "Interventions"); the Wardens' voice is **the Herald**, who reads the Citadel broadcasts; Arc III chapter 1 is now "The Director"; Patron capsules.
- **Lead review (IP):** the Spire's restock is **the Offering** (was the Feast) and the death signal is **the Knell** (was the cannon). The 25th Games' Writ is the Dusk Writ: 48 contenders is the size of every Jubilee, never a Writ. The flood Games moved to the 68th as the Flood Games, and the Third Jubilee has the Dawn Writ. Arc I's chapter 4 is The Last Dusk, Teo's Grace is restaged, and Glasswater no longer trains its young to win.
- **AgentService** is built with the Splices in Roadmap Phases 2–3 (its core comes with Splice Hunt v0 in Phase 2) and reused here.
- **`Shared.Lore`** is created in Roadmap Phase 2, so Warden events and broadcasts read their names from it; the lore pass on live text stays in Phase 7.
- **One Archive:** these records and the Modes pillar's rule-twist Games form one list; the Modes pillar's "Silent Games" is this Silent Writ.
- **Provinces:** all eight stay in the lore; five are playable home Provinces at launch and the other three join later.
- **Mode boot:** ModeService (Roadmap Phase 5) resolves the mode; StoryService runs the chapters on top of it.

---

**Pillar:** Story mode and the world. **Owns:** "1. Story and narrative" (six items), plus the Showcase (interviews) and the Assessment (training scores) from "7. Capitol systems".

## 1. Current state (checked in Studio and the build reports, 2026-11-11)

| Area | Status | Evidence |
|---|---|---|
| Story, characters, arcs, unlocks, Archive Games | Not started | No story, quest, dialogue or objective code. `script_grep` finds no TeleportService, MarketplaceService, PathfindingService, PrivateServer, Patron or Favour anywhere. |
| Saved progress | Partly built (stats only) | `DataService` saves to store `PlayerStats_v1`, key `Player_<UserId>`. Keys: Wins, TotalKills, RoundsPlayed, Settings. Saves are deltas through UpdateAsync, with no session lock. |
| Round flow | Built (PvP only) | `RoundService` is one hard-wired loop: Lobby → Intermission → Countdown → Active → Ending. A round with exactly one contender is "practice". There is no mode concept. |
| Arena schedule | Built (one schedule) | `ArenaService` runs the clock, border, Offering and Roll Call from Config. `DayCycle.schedule()` reads `Config.Round.DaySchedule` on the server only; clients follow `GameState.Clock`. So a chapter can bring its own day. |
| Sky broadcast | Built, reusable | `FallenRecapController` + `Shapes` + `PointFont` draw static → the Cleft sigil → point-cloud busts with point-letter names, synced by `GameState.RollCall`. `ArenaService.FallenSnapshots` builds R15 models from any HumanoidDescription. |
| Announcements and audio | Built | `NotificationController` styles: Banner, Warning, Toast, Countdown, RollCall, Victory. `AudioController` ducks music under named 2D sounds. |
| Camera | Partly built (no cinematics) | `CameraController`: first person in the arena, Classic in the lobby. It goes hands-off while `ClientState.spectating ~= nil`, a pattern a cinematic hand-off can copy. There is no Scriptable camera anywhere. |
| HUD guidance | Partly built | `HUDController` compass shows Spire and border markers and a next-event line (border, Offering). No objective marker. |
| Showcase stage | Not started (decor only) | `Populate.Lobby` ("the waiting grounds") builds a central fire `Dais`/`DaisTop` ringed by 8 benches, 4 pavilions, 2 `NoticeBoard`s with SurfaceGui faces, and an overlook facing the arena. |
| Assessment pieces | Not started (Studio-only parts) | `DummyBuilder` / `ServerStorage.Dev.TrainingDummy` only spawn in Studio practice rounds. `CombatService` says: "Studio only (Config.IsStudio), practice rounds only". `CombatService` accepts attacks only from alive contenders during Active. `ServerStorage._MovementTestCourse` is a dev course builder. |
| NPCs | Not started | Only the Studio dummies exist. `PlayerService.damage`, `PlayerService.died` and `FallenSnapshots.capture` take Players only. |
| Loaders | Built | Server `Main` and `ClientMain` load any extra ModuleScript in Services and Controllers, so new modules drop in. |

Two cautions:
- No build agent playtested anything. Story mode will stand on systems that still need their first QA pass.
- `docs/GameDesign.md` §11 still lists the v1 sectors. The live `ArenaLayout` uses Meadow, Forest, Field, Lake, Gorge, Cliffs, Marsh and Mountains. StiltHut, FishingShack and RiverMill are retired.

## 2. The design in brief

- **The world is the Accord.** Eight named Provinces have been ruled from the Citadel since the Sundering. The Accord's harshest clause, **the Tithe**, sends three young adults from every Province into **the Vale** each year. 8 × 3 = 24 contenders, one per launch plate.
- **The Wardens run the Games** and broadcast them on **the Skycast**. The Skycast is the point-cloud sky display our Roll Call already uses.
- **Every piece of lore sits on something that exists:**
  - The Spire *is* the Cleft, the split, iron-bound monolith already on our banners, tier-3 crate lids and Roll Call sigil.
  - The lobby island is the Waiting Grounds.
  - The Roll Call is the Wardens' broadcast.
- **Story mode** is a set of 15–20-minute chapters. Each runs in a reserved server of this same place, solo or co-op up to 3 (one Province's three contenders). Chapters are scripted on top of the real round tech: launch, day and night, border, Offering, Roll Call.
- **Four playable characters and four arcs** make one campaign, *The Hundredth*. It builds to the 100th Games, where the player can bring down **Chancellor Elias Kade** in one of four ways.
- **Five Archive Games** let players relive our own past Games, then rewrite them.
- **Ship order:** the Showcase and the Assessment go into the live lobby first. They are cheap, they give dead and waiting players something to do, and they build tech the story needs. Chapter One comes next. *Lead note (Roadmap): they ship in Roadmap Phase 7, after the profile (Phase 5), so the Mark is saved from day one.*

## 3. Lore bible

### 3.1 The world in one paragraph
Ninety-nine years ago the river republic tore itself apart in the Sundering, and the Citadel won. The last battlefield held the Accord Stone, the old republic's law cut in granite, and Citadel cannon split it. The victors bound the stone with iron and set a fire basket on its crown, **the Beacon**. Beneath it they wrote the peace: **the Accord**. Its three iron bands stand for three duties:
- **the Levy**: each Province's goods
- **the Law**: the Wardens' order
- **the Lot**: the Tithe

Every year since, the Lot has drawn three of age from each Province and sent them into the valley around the stone, **the Vale**. Every Province watches until one is left standing. The stone is the Spire, and the Games are LAST STANDING.

### 3.2 The Cleft, our sigil
The Cleft is already in the game: the Spire's shape, the banners, the tier-3 crate lid and the Roll Call sigil. It shows a stepped base, a monolith split down its upper half, three iron bands and a fire basket.
- **Citadel reading:** *Broken. Bound. Burning.* The Accord holds together what the war split.
- **Unbound reading:** the Cleft with its top band cut. *The stone is already broken; only the iron holds it.* Players find it chalked on rocks and scratched inside crates.

### 3.3 The Citadel
- **Place.** A granite mesa where two rivers meet, east beyond the Vale's mountains. Dressed stone banded in iron, with Skycast masts, the Chancellery, and the Wardens' Hall cut into the rock.
- **The Archive.** Vaults that hold a recording of every Games.
- **Style.** Austere and ceremonial: charcoal wool, brass, black glass, and iron rings worn to show rank. Its excess is ritual, not costume.
- **Names.** Citadel families carry double names (Calder-Voss, Ashby-Lowe). Province names are plain and trade-born (Reed, Holt, Tull, Strand).
- **The Tor.** The contenders wait on the Tor, a crag east of the Vale. Its overlook faces west across the Crest; this is the lobby island.

### 3.4 The Provinces
| Province | Industry | Land | Contenders known for | Banner colour |
|---|---|---|---|---|
| Ironreach | iron ore and forges; made the Spire's straps and the launch plates | northern mountains | strength, blades | gunmetal |
| Timberline | timber and charcoal | high forests | climbing, axes | moss green |
| Saltmarsh | salt pans, fowling, eel traps | tidal marsh, stilt villages | swimming, traps, spears | grey-blue |
| Graincross | grain and mills; the Accord's bread | the central plains | endurance | ochre |
| Coalbank | coal and river barges; the poorest Province | soot valleys | hunger, grit | charcoal |
| Glasswater | glass and lenses; grinds the Skycast's optics; the richest Province | a crater lake | keen sight, long shots | lake teal |
| Quarrymoor | granite and masonry; cut the Spire and the launch tubes | moorland quarries | patience | stone grey |
| Loomhallow | wool, dye and cloth; weaves the banners and the contenders' grey | sheep valleys and dye-works | nimbleness, quiet | madder red |

Province backgrounds as a gameplay system belong to the Modes pillar (home Provinces and Talents); this table is their lore source. *Lead note (Roadmap): home Provinces launch with the first five; Glasswater, Quarrymoor and Loomhallow join in a later Season.*

### 3.5 The Tithe
- Each spring, every Province enters its **of-age**: 18 to 24 is the proposed range. The Wardens draw three names per Province on the Skycast.
- No volunteering, no trading names: *the Lot is the Lot.*
- **The Grace:** the winner's Province is excused that year's Levy.
- Contenders wear **Tithe grey**, the dark fabric sleeves the first-person viewmodel already shows.

### 3.6 The Wardens
A guild of engineers in grey coats with brass collars. They built the border fields that ended the Sundering; now they build the Games. They:
- reshape the Vale each year;
- run the **Warden events**, the user's "a new challenge every couple of minutes" (owned by the Arena events pillar);
- breed **Splices**, engineered creatures, in kennels under their Hall;
- run the Skycast from lens masts on the Vale's crest.

They speak with one synthetic voice, so no Warden is ever heard by name. Head Warden **Odile Sarne** believes the Games are the Accord's art.

### 3.7 The Laureates
Winners swear **the Laureate's Oath**. They serve the Citadel for life, mentor their Province's contenders every year, and appear on the Skycast when called. They are heroes at home and debtors in the Citadel.

| Laureate | Games | Province | Note |
|---|---|---|---|
| Ysolde Barrow | 1st, the First Tithe | Quarrymoor | her name is cut into the Spire's first tread |
| Hask Merrow | 25th, the Dusk Writ | Saltmarsh | Saltmarsh's last Laureate |
| "Number Nine" | 50th, the Silent Writ | unknown | won without a name; his name is an Archive mystery |
| Elias Kade | 68th, the Flood Games | Coalbank | now the Chancellor |
| Edda Kell | 75th, the Dawn Writ | Loomhallow | won the Third Jubilee |
| Maren Holt | 86th | Ironreach | mentor; playable |

### 3.8 The Chancellor
**Elias Kade**, 50, was born in Coalbank, the poorest Province. He was drawn at 19 for the Flood Games, the 68th, and climbed the Crest and held it while the Vale and the Spire drowned below him. Eight years ago he became the first Province-born Chancellor. He is calm, warm, reasonable and certain: *"Every child of the Provinces has a door. I walked through it."* The Provinces love him because he is theirs, and that is what makes him dangerous. The Unbound believe his Games were arranged.

### 3.9 The Games, beat by beat
Each lore beat maps onto the round flow that already exists.

| Lore beat | In the world | System |
|---|---|---|
| the Tithe | names drawn on the Skycast | new Skycast scene, reusing `FallenRecapController` |
| the Waiting Grounds | the holding courtyard on the Tor | the lobby island (`Populate.Lobby`) |
| the Assessment | the Wardens grade each contender with the **Mark** (1–10) | new, §10 |
| the Showcase | the broadcast interview at the fire dais | new, §9 |
| the Rise | the plates rise from granite tubes into the morning | Countdown + `LaunchController` |
| the Scramble | the rush for the Spire's alcoves | Active start; tier-3 crates at `CrateSlot_1..4` |
| the Knell | one toll of the Spire's iron bands per fallen contender | `Sfx` Knell (replaces today's Cannon) |
| the Roll Call | at dusk, the fallen drawn in light | `ArenaService` + `FallenRecapController` |
| the Offering | the Spire restocked at the second dawn | `LootService.refillSpire` |
| the border | the Wardens' field closing on the Spire | `ArenaService` + `ArenaController` |
| the Laureate | the last one standing | Ending / Victory |

**The Vale is the same valley every year.** The Wardens reshape it with water, weather, fire and creatures: *"The Vale is always the same. The Games never are."* This is also what lets every Archive Game reuse our one arena.

Proposed in-world names for captions and the compass:

| Biome | In-world name |
|---|---|
| Meadow | the Green |
| Forest | Rivenwood |
| Field | the Tallgrass |
| Lake | Stillwater |
| Marsh | the Sump |
| Cliffs | the Shelf |
| Gorge | the Throat |
| Mountains | the Crest |

### 3.10 History of the Games
| Year | Event |
|---|---|
| 0 | The Sundering ends in the Vale. The Accord is signed under the bound stone. |
| 1 | **The First Tithe.** No Skycast yet; names are read out over the radio. Ysolde Barrow wins. |
| 25 | **First Jubilee, the Dusk Writ.** The night runs twice as long (the Late Dawn rule). Hask Merrow wins. |
| 50 | **Second Jubilee, the Silent Writ.** No names: no Showcase, and the Roll Call shows plate numbers only. "Number Nine" wins. |
| 68 | **The Flood Games.** The Wardens dam the river and drown more of the Vale each dawn, until only the Crest stands dry. Elias Kade wins. |
| 75 | **Third Jubilee, the Dawn Writ.** The Spire is restocked every dawn. Edda Kell of Loomhallow wins. |
| 86 | Maren Holt wins. |
| 91 | Kade becomes Chancellor. |
| 99 | Now. Oss Reed is drawn (Arc I). |
| 100 | **Fourth Jubilee, the Centenary Writ.** The Chancellor will light the Beacon himself, the first Chancellor to stand in the Vale since the Sundering (Arc IV). |

Every 25th Games is a Jubilee: the Lot draws six from each Province (48 contenders, the size of the live Jubilee Games), and the Wardens publish that year's **Writ**, a change to the rules, which the Herald announces on the Skycast. No Writ changes how many are drawn or who can be drawn.

### 3.11 The Unbound
No leader and no army. The Unbound are a web of Province guilds and a few Citadel clerks who keep the *true* Archive: everything the Wardens cut from the broadcasts. They pass messages through Patron capsules, chalk marks, and the dead channels of the mentors' wrist receivers.

### 3.12 Tone and content rules
- **Audience.** A Moderate label keeps the game eligible for Roblox Select (ages 9–15) and standard accounts (16+). Select opens only after Roblox's all-ages requirements and evaluation (Roadmap §7), so the first audience is age-checked 16+. Write for both: grief, fear and defiance, never gore.
- **No blood**, matching the combat plan. Deaths are *falls*, carried by the Knell and the Roll Call.
- **Contenders are of age (18–24).** This is a deliberate departure from the source genre; see open questions.
- **Fictional politics only.** No real flags, parties, slogans or groups. A game whose primary theme is a *current* real-world political issue gets the Sensitive Issues descriptor and becomes 16+ only.
- **Original-IP lint.** The banned-terms check (Roadmap §7, built in Roadmap Phase 2) scans the string literals of every script, `StoryDefs` included, plus instance and asset names, the `ServerStorage.WorldGen` builders that write SurfaceGui text, and the services that send Announce text. It matches whole words, flags a review list (cannon, feast, career, victor, quell, sponsor, trinket), and runs with `ServerStorage.Dev.SyntaxCheck` before each publish.
- **Avoid the source's signature beats:**
  - a hunter who volunteers for a sibling
  - two winners at the end
  - special housing for winners
  - a 1–12 score
  - bird or rose symbols
  - a hand-sign salute
  - fire as the heroine's emblem
  - a final standoff where the last two refuse to fight
  - a rival falling from the central structure at the finale
  - a mid-Games rule change that would let two win
  - a co-op run that ends with more than one Laureate
  - a Jubilee that sends past winners back into the arena (in Arc IV the Laureates enter the Vale as raiders and mentors, never as drawn contenders)
  - creatures driving the last contenders onto the central structure
  - a rich Province that trains its young to win
  - a leader reading the 25-year twist
  - a cannon shot for each death, or a national emblem and anthem framing the faces of the dead

## 4. Story mode on Roblox

### 4.1 Shape
1. **Entry.** A STORY button in the lobby opens the chapter board. Players go solo or co-op with up to 3 people: a Roblox party (`SocialService:GetPlayersByPartyId`) or players invited on the same server.
2. **Teleport.**
   - `StoryService` checks every member's unlocks in their saved profile.
   - It then calls `TeleportService:TeleportAsync(game.PlaceId, party, options)` with `options.ReservedServerId = HttpService:GenerateGUID(false)` and `SetTeleportData({ chapter, session })`.
   - Don't use `ShouldReserveServer` or `ReservedServerAccessCode`; both are deprecated.
3. **Boot.** A reserved server of this place (`game.PrivateServerId ~= ""` and `game.PrivateServerOwnerId == 0`) boots in Story mode, and RoundService's PvP loop stays off.
   - StoryService reads `player:GetJoinData().TeleportData` and checks each player's unlocks again, because teleport data is client-visible and unencrypted.
   - It then sets `GameState.Mode` and `GameState.Chapter`.
   - Story-only assets live in `ServerStorage.Story` and are cloned only in story servers.
4. **Co-op is the Province trio.** Player 1 plays the chapter's lead character. Players 2 and 3 take the other two plates as themselves, with their own avatar and name. NPC Province-mates fill any empty plates.
5. **Rejoin.** The session's ReservedServerId is kept in MemoryStore for 30 minutes, so a player who disconnects can be sent back to the same server.
6. **End.** Progress is saved. Players choose "Next chapter" (stay in this server) or "Return to the Waiting Grounds" (teleport to a public server).
7. **Studio.** Reserved servers don't exist in Studio. Setting `GameState:SetAttribute("DevChapter", "c1_tithe")` boots a chapter in Play Solo, the same convention as `DevRollCall`.

### 4.2 What gets built, and where
| Module | New or extend | Job |
|---|---|---|
| `Shared.Lore` | new | names, Provinces and glossary strings, so anything can be renamed in one place |
| `Shared.StoryDefs` | new | arcs, chapters, beats, choices, unlock rules, character presets, Archive records |
| `Services.StoryService` | new | mode boot, party and teleport, chapter runner, checkpoints, saves |
| `Services.AgentService` | new, shared with the Splices owner | NPC rigs; paths on `ArenaLayout.Trails` + PathfindingService; perception; follow, patrol, chase, melee |
| `RoundService` | extend | a *director* hook. Today's PvP loop becomes the default director. StoryService installs its own: contenders that include NPCs, and its own win conditions. PvP behaviour does not change. |
| `ArenaService` | extend | `configure{ schedule, border, feast, rollCall }` per chapter; NPC entries in the Roll Call (userId 0) |
| `ArenaService.FallenSnapshots` | extend | capture from a HumanoidDescription or a model; the builder already uses `CreateHumanoidModelFromDescriptionAsync` |
| `PlayerService`, `CombatService` | extend | NPC attackers in damage info, for the kill feed and kill credit. NPC targets already take hits through `Humanoid:TakeDamage`. |
| `DataService` | extend | story profile and Marks (§4.4) |
| `Controllers.NarrativeController` | new | cuff captions, choice cards, chapter cards, objective marker, and the cinematic camera through `ClientState.cinematic` |
| `Controllers.SkycastController` | new, split out of `FallenRecapController` | generic sky scenes: text, sigil, busts, compositions. The Roll Call becomes one of these scenes. |
| `CameraController` | extend | hands-off while `ClientState.cinematic ~= nil`, the same contract as spectating |
| `HUDController` | extend | objective marker on the compass, plus an objective line |
| `NotificationController` | extend | Announce styles `Radio`, `Chapter`, `Objective` |
| `AudioController`, `SettingsController` | extend | a Voice SoundGroup with its own volume slider; music ducks under voice |
| `LobbyController`, `UIBuilder` | extend | STORY button, chapter board, party panel |
| Remotes | new | `StoryRequest` and `StoryChoice` (client to server), `StoryBeat` (server to client). New GameState attributes: `Mode`, `Chapter`, `StoryObjective`, `Skycast`. |

### 4.3 Chapter scripting
A chapter is data plus small hooks. A beat fires on a trigger and calls services that already exist. Triggers are: time passed, place reached, item taken, NPC fallen, choice made.

```lua
StoryDefs.Chapters.c1_tithe = {
	arc = "tithe", title = "The Tithe", lead = "oss", party = { 1, 3 },
	rules = { schedule = { { 0, 7.4 }, { 300, 17.6 }, { 380, 18.9 } }, border = false, feast = false,
	          contenders = { plates = 24, npcSet = "tithe99" } },
	beats = {
		{ on = "start", skycast = "tithe", province = "Saltmarsh" },
		{ on = "start", objective = { text = "Find your mentor", at = "Lobby.Dais" } },
		{ on = "reach:Lobby.Dais", talk = "maren_c1_meet" },
		{ on = "flag:met_maren", run = "Assessment", stations = 3 },
		{ on = "flag:assessed", run = "Showcase", questions = { "c1_q1", "c1_q2", "c1_q3" } },
		{ on = "flag:showcased", run = "Rise" },
		{ on = "time:20", radio = "maren_c1_run" },
		{ on = "reach:HuntersCabin", set = "sheltered" },
		{ on = "rollcall:1", fallen = "c1_day1" },
	},
}
```

### 4.4 Saved progress
*Lead note (Roadmap): superseded. Story progress, flags and Marks go into the one shared, session-locked profile (`Profiles_v2`, built in Roadmap Phase 5), not into `PlayerStats_v1`. The merge rules below still describe how the story fields combine.*

Story progress lives inside the existing `PlayerStats_v1` key. Version goes from 1 to 2, and a missing table means empty. The new data:
- `Story = { done = { [chapter] = { endings } }, flags = { [flag] = true }, unlocked = { [arc] = true }, choices = { [chapter] = { [choice] = option } } }`
- `BestMark` and `LastMark`

The existing UpdateAsync merges them like this:
- union for `done`, `flags` and `unlocked`
- max for `BestMark`
- for `choices`, the last completed run wins

These parts only ever grow, so two servers can never undo each other's saves. No session lock is needed, for the same reason today's delta stats need none.

### 4.5 NPC contenders: the biggest cost
- **AgentService v1 (Phase 1b):**
  - Rigs built from HumanoidDescription presets.
  - Behaviours: follow, patrol (on a trail graph built from `ArenaLayout.Trails`), chase on sight, and melee with ItemDefs timings through the server damage path.
  - *Scripted falls*: an NPC who is off-screen "falls", the Knell tolls and their bust goes into the Roll Call.
  - This is enough for Chapter One: two hunters, one follower, and everyone else off-screen.
- **AgentService v2 (Phase 2):**
  - Adds looting, hiding in bushes and trees, bow and throwing, eating and drinking, and fleeing.
  - Target: about 20 live NPCs within the server budget.
  - Shares perception and pathing with the Splices.

## 5. Playable characters
| Character | Archetype | Province, age | Arc | How they play | Unlock |
|---|---|---|---|---|---|
| **Oss Reed** | reluctant hunter from a poor Province: a fowler, drawn by the Lot, not chosen | Saltmarsh, 19 | I, The Tithe | spear, traps, swimming; the marsh and the lake | from the start |
| **Maren Holt** | past Laureate turned mentor; keeps a ledger of every contender she lost | Ironreach, 33 | II, The Ledger | In the 99th Games she works from the Wardens' gallery, choosing Patron capsules and speaking through the cuff. In flashback she fights her own 86th Games with blades. | Arc I, chapter 2 |
| **Ines Calder-Voss** | Citadel insider: a junior Warden who designs Warden events | the Citadel, 27 | III, The Hall | infiltration and sabotage in the Wardens' Hall, the tunnels under the plates and the caves | Arc I done |
| **Teo Strand** | the favourite: a lens-grinder's son who has studied every Archive recording | Glasswater, 21 | IV | bow; open ground | Arc IV |

- **Looks.** Each character is a HumanoidDescription preset: catalog layered clothing plus a few Blender accessories. Oss wears Tithe grey, Maren her forge leathers, Ines her Warden coat. In first person you see your character's own sleeves and legs, which `CharacterVisuals` already renders.
- **Perks.** Story perks (for example, Oss swims faster) exist only in story servers. Nothing carries into PvP except cosmetics.
- **Archive Games** use the player's own avatar as an unnamed contender of that year. The exception is a record about one Laureate: the Flood Games record is played as young Elias Kade.

## 6. Arcs, branching and alternative outcomes

### 6.1 The campaign: *The Hundredth*
| Arc | Lead | Chapters | What it's about |
|---|---|---|---|
| I, The Tithe | Oss | 1 The Tithe · 2 The Night · 3 The Offering · 4 The Last Dusk | surviving the 99th Games, and what kind of Laureate you become |
| II, The Ledger | Maren | 1 The Gallery · 2 The 86th (an Archive Game) · 3 The Debt | the mentor's side of the 99th; the price of her Oath |
| III, The Hall | Ines | 1 The Director · 2 Under the Plates · 3 The Archive | the Wardens from inside; the truth about the Flood Games |
| IV, The Hundredth | co-op: Oss, Maren, Ines, Teo | 1 The Centenary Writ · 2 The Siege of the Spire · 3 The Beacon | the 100th Games, with the Chancellor in the Vale |

### 6.2 Choices
- **Two kinds of choice:**
  - *Spoken* choices: choice cards with 2–4 options and no timer.
  - *Acted* choices: what you do, such as running for the Spire or the marsh, sharing water, or sparing a hunter.
  - Both kinds set flags.
- **Flags change later chapters.** Mostly in small, visible ways: who is in the Roll Call, who helps you, what Maren says. A few flags change endings.
- **Arc I has two endings:**
  - *The Laureate*: you beat Teo inside the closed border.
  - *Teo's Grace*: needs the flag `spared_sanne` (you spared his Province-mate in chapter 3). Hurt and caught outside the closing border, Teo chooses not to come back in, and the Lot ends with you. There is no standoff on the Spire, and nobody falls from it.
  - Both endings make Oss a Laureate. They decide Glasswater's loyalty and Teo's fate for Arc IV.
  - Optional *Dark Minute*: cut the Skycast relay at the Beacon. Every Province sees static, and the Unbound learn your name.

### 6.3 Bringing down the Chancellor
> The user's note: "DIFFERENT ARCS - KILL SNOW ETC DIFF OPTIONS". Our version: Chancellor Elias Kade, in Arc IV, at the Beacon at dawn on the opening day of the 100th Games.

| Ending | How | What the player sees | Leads to |
|---|---|---|---|
| **Expose** | broadcast the Unbound Record of the Flood Games on the Skycast | the Provinces see proof that their hero's Games were arranged, and refuse the Tithe | the epilogue *The Unbound Year* |
| **Depose** | hold the Spire while the border field fails, then arrest Kade | Kade asks to be judged in the Vale; you make one last choice, to grant it or refuse | the epilogue *The Trial* |
| **Strike** | Kade falls at the Beacon | the fall is never shown: the Beacon goes dark and the Skycast collapses to static. At dusk his bust appears in the Roll Call among the fallen | *The Static*: a second Sundering, the dark ending |
| **The Last Laureate** (hidden) | Maren is alive, you have played the Flood Games' Unbound Record, and you have found Number Nine's name | Kade lights the Beacon and breaks the Lot before every Province: no more Games | the true ending |

Strike stays within the Moderate label: the act is never shown, and the consequence carries the scene.

## 7. Unlockable arcs
Everything is unlocked by playing. Whether any of it is also sold is the user's call (see open questions).

| Unlock | When |
|---|---|
| Arc I, chapter 1 | from the start |
| Arc I, chapters 2–4 | finish the previous chapter |
| Archive: the 86th | Arc I, chapter 2 (Maren tells the story that night) |
| Arcs II and III | finish Arc I |
| Archive: the First Tithe, the Dusk Writ, the Silent Writ, the Flood Games | find that record's **Archive reel**, an in-world collectible hidden in Arcs II and III |
| Unbound Records | finish that record's canon version |
| Arc IV | finish Arcs II and III |
| The Last Laureate ending | the flags listed in §6.3 |

- **Chapter board.** In the lobby, arcs are rows and chapters are cards marked locked, new or done. Endings you have found show as small Cleft marks.
- **Rewards.** The first time you finish a chapter it pays Gold; the Economy pillar sets the amount.

## 8. Archive Games
> The user's notes: "Historical Hunger Games campaigns", and from the expanded plan: "Historical Games – Play through different canonical Games" and "Alternative Timeline – Change established historical outcomes". Ours: the **Archive Games**, the Citadel's recordings of past Games, played again. **Unbound Records** are their rewritten versions.

Each record has:
- a ruleset on the existing arena tech: schedule, number of contenders, border, Offering, Roll Call style, Warden events, starting kit, and the state of the Vale;
- objectives;
- a canon outcome and an Unbound alternative.

| Record | Rules | Canon | Unbound Record | Size |
|---|---|---|---|---|
| The First Tithe (year 1) | no Skycast (names by radio), no Offering, no border, fists and stones, 3 days | Ysolde Barrow wins | you win as a nameless Quarrymoor girl | M |
| The Dusk Writ (25th) | 48 contenders on the Jubilee place's 48-plate ring; the night runs twice as long | Hask Merrow wins | all six from Saltmarsh reach the final three | M, after the Jubilee place |
| The Silent Writ (50th) | no names anywhere: the Roll Call shows plate numbers, everyone wears identical grey | plate 9 wins | learn Number Nine's name and broadcast it | M |
| The Flood Games (68th) | the terrain water rises in a step each dawn; the Spire goes under first and the Crest is the last dry ground | Kade holds the Crest | Kade falls; the epilogue shows a different Chancellor | L (rising water needs a spike) |
| The 86th | Maren's Games: standard rules, more night | Maren wins | Maren brings her Province-mate home | M |

Jubilee-year records (here the 25th and the 50th) are 48-contender Games. Until the Jubilee place exists they can replay at 24 on the classic arena.

*Lead note (Roadmap): these records and the Modes pillar's rule-twist Games (the Drought Games, the Long Night, the Bare Spire, the Closing Ring, the Hunt) form one Archive; the Modes pillar's "Silent Games" is this Silent Writ.*

## 9. The Showcase
> The user's note (expanded plan): "Tribute interviews". Ours: **the Showcase**.

**In PvP (the live lobby):**
- During Intermission, every lobby player gets one Showcase card: the host's question and four answers, one per persona: **Bold**, **Warm**, **Cunning**, **Quiet**. All lines are pre-written. There is no free text, so nothing needs filtering.
- Up to three answers are featured. The player's avatar appears as a stand-in on the fire dais under a spotlight; the server builds it with the FallenSnapshots builder. Their point-cloud bust and line appear on the Skycast above it.
- **Effect:**
  - A persona title for the round, shown on the spectate card and in the kill feed.
  - Optionally, if the Arena events pillar wants a hook: the *kind* of capsule patrons send you (weapons, medicine, tools or food), all of equal value.
  - No answer is right. A player who doesn't answer counts as Quiet.

**In story:** full scenes on the dais with the host, **Perrin Ashby-Lowe**. Each chapter has three questions; each answer sets a flag and changes Favour. These are among the few third-person scenes.

**Sample question:** *"Saltmarsh hasn't brought a Laureate home in three generations. Why should this year be different?"*
- **Bold:** "Because I'm done waiting for the tide."
- **Warm:** "My cousin's watching. I made her a promise."
- **Cunning:** "Who said I'd do it the Saltmarsh way?"
- **Quiet:** "Ask me at the second dusk."

Launch content is about 40 questions with 4 answers each, all localisable. The host's lines start as text-to-speech scratch audio and are recorded later.

## 10. The Assessment
> The user's note (expanded plan): "Training scores". Ours: **the Assessment**, graded with the Wardens' **Mark** from 1 to 10. The scale is deliberately not the source genre's.

**Where:** the **Assessment Hall**, a granite interior entered through a `LobbyGate` at the end of the north walkway. The gate fades you into the Hall, which sits away from the island; call `RequestStreamAroundAsync` first.

**A run:** about 90 seconds across three stations. In PvP you choose the stations; in story they are fixed.

| Station | Tests | Reuses |
|---|---|---|
| The Dummies | blade timing and placement | `CombatService` melee trace, `DummyBuilder` |
| The Long Lane | bow and throwing at 20–60 studs, head zones | `ProjectileService` |
| The Wall | mantle, vault and climb against the clock | `MovementController`, server checkpoints |
| The Hush | cross a lit hall unseen while a lamp sweeps | server raycasts from the lamp |
| The Larder | pick the sound ration over the spoiled one, find clean water and fill a bottle (never poisonous berries or plants) | `ItemDefs`, `InventoryService` |

- **The server decides the result.** `AssessmentService` opens a session and sets the player attribute `InAssessment`. While it is set:
  - CombatService and ProjectileService accept that player's attacks only against their own `TrainingDummy` targets, never against players.
  - InventoryService hands out a loaner kit, even though the player is outside the arena.
  - The camera is first person.
- **The verdict** appears as point-cloud numerals over the Wardens' gallery ("MARK 7"), in the same light as the Roll Call.
- **Saved and shown:** BestMark and LastMark are saved and shown on the lobby record card, the spectate card and your line in the Roll Call.
- **PvP effect: reputation only.** Any Favour hook is the Arena events pillar's call, and should be capped. The Assessment's real value is that dead and waiting players get something to do between rounds. That is why it ships first.

## 11. Telling the story in first person
| Channel | Used for | Built on |
|---|---|---|
| **The Skycast** | the Tithe, Writs, the Chancellor's addresses, chapter titles, the Roll Call, endings | `FallenRecapController`, generalised into `SkycastController` |
| **The Herald** (the Wardens' voice) | the arena PA: warnings and Warden events | Announce + text-to-speech assets (`GenerateSpeechAsset`) through a PA filter. The lore says the Wardens use one synthetic voice, so the budget choice becomes a feature. |
| **The cuff** (a brass wrist receiver) | the mentor's voice while you play; captions bottom-centre with the speaker's name | the `Radio` Announce style + the Voice SoundGroup; optional wrist-raise pose in `ViewmodelController` |
| **The stage** | the Showcase, and conversations in the Waiting Grounds (short, third person) | the lobby Dais and the cinematic camera |
| **The Vale itself** | notes in the HuntersCabin, Unbound marks, Province objects hidden in the arena | set dressing and ProximityPrompts |
| **Chapter cards and objectives** | title cards; one objective line plus a compass marker | `NotificationController`, `HUDController` |

**Rules:**
- In the arena, never take the camera for more than about 8 seconds.
- Every cinematic can be skipped (hold to skip).
- Subtitles are on by default, and no information is given by voice alone.
- Choice cards have no timer.
- Touch, gamepad (D-pad + A) and keyboard (1–4) all work.

**Voice:** Roblox text-to-speech is fully released, but English only, with at most 300 characters per request. `GenerateSpeechAsset` saves reusable audio assets. Use it for scratch audio and the Wardens. Record actors for Maren, the host and Kade when the budget allows.

## 12. Cost
Sizes assume one strong developer with AI help: S = a day, M = a few days, L = 1–2 weeks, XL = more.

| Work | Size |
|---|---|
| `Shared.Lore`, plus a lore pass on live UI text (for example "NEXT ROUND" becomes "THE TITHE", and the victory screen gets a Laureate title) | S |
| The Assessment: the Hall set (part-built first), AssessmentService, live dummies, combat in the lobby, saving and showing the Mark | L |
| The Showcase in PvP: cards, featured stand-ins, the Skycast line | M |
| StoryService: reserved servers, mode boot, the Studio hook, RoundService and ArenaService directors | L |
| Story profile in DataService | M |
| NarrativeController: captions, choice cards, objective marker, chapter cards, cinematic hand-off | L |
| SkycastController (generalise the Roll Call show) | M |
| AgentService v1 | L |
| AgentService v2 (full contender AI) | XL |
| Chapter One content: writing, beats, NPC looks, scratch voice, tuning | L |
| Arc I, chapters 2–4 | L each |
| Each Archive record | M (the Flood Games record is L) |
| Arc II and Arc III, including new interiors (the Wardens' gallery and Hall) | XL each |
| Arc IV and its four endings | XL |
| Four character looks (presets plus Blender accessories) | M |
| Recorded voice for the key characters | L, plus external cost |

**Rough calendar:**

| Phase | Contents | Time |
|---|---|---|
| 1a | the Assessment and the Showcase in the live lobby | 2–3 weeks |
| 1b | Chapter One | about 4 weeks |
| 2 | the rest of Arc I, endings, the chapter board, AgentService v2, the 86th | about 2–3 months |
| 3 | Arcs II and III, three more records | about 3–4 months |
| 4 | Arc IV | about 2 months |

## 13. First slice

### Phase 1a: the pre-Games beats in the live lobby (2–3 weeks)
- The Assessment Hall with three stations (the Dummies, the Long Lane, the Wall), the Mark, and BestMark on the record card.
- Showcase cards during Intermission, with featured stand-ins on the dais.
- `Shared.Lore`, plus the lore pass on lobby, intermission and victory text.

**Done when:**
- A dead player can walk into the Hall and earn a Mark.
- The Mark is still on their card after they rejoin.
- They can answer a Showcase card before the next round.
- All of this works on PC, phone and gamepad, with no effect on PvP balance.

### Phase 1b: Chapter One, "The Tithe"
This starts after Phase 1a and the core-loop QA pass, and takes about 4 weeks. It runs solo or co-op up to 3 (the Saltmarsh three) in a reserved server, and lasts 15–18 minutes.

1. **Cold open, 40 seconds, skippable on replays.** Night over the Waiting Grounds. Static assembles into the Cleft, then "THE NINETY-NINTH TITHE · SALTMARSH", then three point-cloud busts with names: Oss, plus either the co-op friends' own avatars or the NPCs Hettie Reed and Bram Tull. The Tithe is drawn as the mirror image of the Roll Call.
2. **Morning in the Waiting Grounds.** Maren Holt waits by the central fire and hands you the cuff.
3. **The Assessment.** A short version with three fixed stations sets your Mark.
4. **The Showcase at golden hour.** Three questions on the dais, with your bust on the Skycast while you answer.
5. **The Rise.** The real countdown and launch, with a story sub-line ("Saltmarsh · plate 7").
6. **The Scramble.** An acted choice. Run for the Spire's alcoves, where Teo Strand and Sanne Voll of Glasswater fight for the crates (AgentService v1), or follow Hettie into the Sump. Maren comments on the cuff either way.
7. **The day.** A compressed schedule brings dusk at about 6 minutes, with Knells and one Warden event. The event is borrowed from the Arena events pillar; if that isn't ready, a scripted fog. You shelter at the HuntersCabin. Hettie: *"It's a trapper's hut. Like home. They built it to look like home."*
8. **The dusk Roll Call.** The existing show, with the day's scripted fallen. Bram is among them if you split up.
9. **End.** Maren on the cuff: *"Six of them. Not you. Sleep in turns."* Then the chapter card, a save, and "Return to the Waiting Grounds".

**Done when:**
- Chapter One completes solo and with 3 players on a live server.
- A player who disconnects can rejoin.
- Progress and flags survive moving to another server.
- A regression playtest shows the PvP Lobby → Ending loop is untouched.

## 14. Dependencies on other pillars
- **Arena events pillar:** chapter beats trigger its Warden events and Splices, and it shares AgentService.
- **Arena events pillar (Citadel systems):** Patrons and Favour read the Showcase persona and the Mark. Citadel broadcasts share SkycastController.
- **Economy pillar:** Gold for finishing chapters, the premium-mode decision, and one shared profile schema in DataService.
- **Modes pillar (home Provinces, Talents):** Province backgrounds use §3.4. Story perks never reach PvP.
- **Economy pillar (cosmetics):** character outfits as PvP cosmetics, if wanted.
- **Modes pillar (modes):** the 48-contender Jubilee ring, which the Jubilee-year records need; Archive Games in the mode select.

## Sources (platform checks)
- [Teleport between places (Roblox Creator Hub)](https://create.roblox.com/docs/projects/teleport) and [TeleportOptions](https://create.roblox.com/docs/reference/engine/classes/TeleportOptions): ReservedServerId; ShouldReserveServer and ReservedServerAccessCode are deprecated; teleport data is visible to the client.
- [Content maturity](https://create.roblox.com/docs/production/promotion/content-maturity) and [Roblox Kids and Select accounts (April 2026)](https://about.roblox.com/newsroom/2026/04/introducing-roblox-kids-and-select-accounts): Moderate content can reach ages 9–15 (Select, after Roblox's all-ages evaluation) and 16+; primary sensitive issues are 16+ only.
- [Roblox Kids and Select (Creator Hub)](https://create.roblox.com/docs/production/publishing/kids-and-select): a new game first reaches only age-checked users 16+, and Select needs the all-ages requirements and an evaluation.
- [Text-to-Speech API full release](https://devforum.roblox.com/t/build-more-immersive-experiences-text-to-speech-api-full-release/3986607) and [beta details](https://devforum.roblox.com/t/beta-text-to-speech-api-from-text-to-voice-content-instantly/3792085): English only, 300 characters per request, GenerateSpeechAsset.
- [Paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items): this pillar sells nothing random.

---

## Checklist items in this pillar

Status, size and Roadmap phase match the master checklist in the [Roadmap](../Roadmap.md).

### 1. “Story mode”

- **Our name:** Story mode, The Hundredth: 15–20-minute chapters in reserved servers of this place, solo or co-op up to 3 (one Province's three contenders), scripted on the real round tech
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 7 → 10
- **Pillar phase:** Phase 1b (Chapter One), then Phase 2 (rest of the framework)
- **From the notes:** "STORY MODE OPTION _ PLAYABLE CHARACCHTERS ETC" (raw notes); "[ ] Story mode" (expanded checklist)
- **Evidence:** There is no story, quest, dialogue or objective code in the place. script_grep finds no TeleportService, PrivateServer or PathfindingService use. RoundService is one hard-wired PvP loop (practice = one contender), and ArenaService runs one schedule from Config, so both need a director/configure hook. Already reusable: LaunchController, DayCycle (DaySchedule is server-side only), ArenaService's Offering, border and Roll Call, and the FallenRecapController sky show. Server Main and ClientMain auto-load new modules.

### 2. “Different playable characters”

- **Our name:** Playable characters: Oss Reed (reluctant hunter, Saltmarsh), Maren Holt (Laureate turned mentor, Ironreach), Ines Calder-Voss (junior Warden, the Citadel insider), Teo Strand (the favourite, Glasswater)
- **Status:** Not started · **Size:** L · **Roadmap phase:** 7 → 10
- **Pillar phase:** Phase 1b (Oss), Phase 3 (Maren, Ines), Phase 4 (Teo)
- **From the notes:** "STORY MODE OPTION _ PLAYABLE CHARACCHTERS ETC"; "[ ] Different playable characters"
- **Evidence:** PlayerService.loadIntoLobby only applies each player's own HumanoidDescription, at standard scales. There are no character presets and no NPC rigs except the Studio-only TrainingDummy (DummyBuilder). ArenaService.FallenSnapshots already builds R15 models from any HumanoidDescription (CreateHumanoidModelFromDescriptionAsync), which character presets and NPC Roll Call busts can reuse. CharacterVisuals already renders the player's body in first person.

### 3. “Different narrative arcs”

- **Our name:** Four arcs: I The Tithe (Oss), II The Ledger (Maren), III The Hall (Ines), IV The Hundredth (co-op finale at the 100th Games, the Fourth Jubilee)
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 7 → 10
- **Pillar phase:** Phase 1b (Arc I, chapter 1), Phase 2 (rest of Arc I), Phase 3 (Arcs II and III), Phase 4 (Arc IV)
- **From the notes:** "DIFFERENT ARCS - KILL SNOW ETC DIFF OPTIONS"; "[ ] Different narrative arcs"
- **Evidence:** There is no dialogue, flag, objective or cinematic code. Some delivery pieces exist: NotificationController's Announce styles (Banner, Warning, Toast, Countdown, RollCall, Victory); the FallenRecapController point-cloud sky show (static, then the Cleft sigil, then busts with PointFont names); AudioController ducking; and a HUD compass with only Spire and border markers. CameraController has no Scriptable mode, but it goes hands-off while spectating, a pattern cinematics can copy.

### 4. “Alternative outcomes — including killing Snow”

- **Our name:** Alternative outcomes, bringing down Chancellor Elias Kade: Expose, Depose, Strike (the fall is never shown; the Skycast cuts to static and his bust appears in the Roll Call) and the hidden ending The Last Laureate; plus Arc I's two endings (The Laureate, Teo's Grace)
- **Status:** Not started · **Size:** L · **Roadmap phase:** 10
- **Pillar phase:** Phase 2 (choice flags and Arc I endings), Phase 4 (the Chancellor's fall)
- **From the notes:** "[ ] Alternative outcomes — including killing Snow" (raw: "KILL SNOW ETC DIFF OPTIONS")
- **Evidence:** DataService (PlayerStats_v1) saves only Wins, TotalKills, RoundsPlayed and Settings, as deltas through UpdateAsync. It stores no flags, choices or endings. The Roll Call already accepts any entry of the form {name, userId, snapshot}, and FallenRecapController handles userId 0, so a scripted fallen Chancellor needs no new renderer.

### 5. “Unlockable story arcs”

- **Our name:** Unlockable arcs, Archive reels and Unbound Records, all earned by play and shown on a chapter board in the lobby
- **Status:** Not started · **Size:** M · **Roadmap phase:** 10
- **Pillar phase:** Phase 2
- **From the notes:** "UNLOCK DIFF ARCS"; "[ ] Unlockable story arcs"
- **Evidence:** There is no unlock data and no chapter UI. LobbyController shows only the title, tagline, record card (Wins, Kills, Rounds), status pill, how-to-play panel and Settings. DataService has no non-additive keys yet; its UpdateAsync would need union and max merges.

### 6. “Historical Hunger Games campaigns”

- **Our name:** Archive Games, our own past Games: the First Tithe, the Dusk Writ, the Silent Writ, the Flood Games, the 86th. Unbound Records are their alternative outcomes
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 10
- **Pillar phase:** Phase 2 (the 86th), Phase 3 (the other records)
- **From the notes:** "[ ] Historical Hunger Games campaigns" (expanded plan: "Historical Games – Play through different canonical Games"; "Alternative Timeline – Change established historical outcomes")
- **Evidence:** ArenaService hard-codes one ruleset from Config.Border, Config.Events and Config.Round. DayCycle.schedule() reads Config.Round.DaySchedule only on the server (clients follow GameState.Clock), so each record's schedule, border and Offering settings need only a server-side configure(). The Jubilee-year records need the Jubilee place's 48-plate ring; ArenaLayout has one ring of 24 at r = 52. Rising water for the Flood Games is untested, because TerrainGen is an edit-time builder.

### 45. “Tribute interviews”

- **Our name:** The Showcase: question cards during Intermission with four personas (Bold, Warm, Cunning, Quiet) and featured stand-ins on the lobby fire dais; full scenes with the host Perrin Ashby-Lowe in story
- **Status:** Not started · **Size:** M · **Roadmap phase:** 7
- **Pillar phase:** Phase 1a (PvP lobby), plus a story scene in Phase 1b
- **From the notes:** "[ ] Tribute interviews" (section 7, "Capitol systems")
- **Evidence:** The stage exists only as decor: Populate.Lobby builds a central fire Dais/DaisTop ringed by 8 benches, 4 pavilions and 2 NoticeBoards with SurfaceGui faces. Intermission lasts 25 s (Config.Round.IntermissionTime), and RoundService only sends a 'NEXT ROUND' banner then. FallenSnapshots plus Shapes.sampleBust can already put a player's point-cloud bust in the sky.

### 46. “Training scores”

- **Our name:** The Assessment: a 90-second run in the Assessment Hall, graded with the Wardens' Mark from 1 to 10 and saved as BestMark and LastMark
- **Status:** Not started · **Size:** L · **Roadmap phase:** 7
- **Pillar phase:** Phase 1a
- **From the notes:** "[ ] Training scores" (section 7, "Capitol systems")
- **Evidence:** Training dummies exist only in Studio practice rounds: the CombatService header says 'Studio only (Config.IsStudio), practice rounds only', and DummyBuilder builds ServerStorage.Dev.TrainingDummy. CombatService accepts attacks only from alive contenders during Active, and InventoryService.give only works for alive contenders, so a lobby combat context is needed. ServerStorage._MovementTestCourse is a dev course builder that can be borrowed from. No score or Mark is stored anywhere.

## Open questions

1. How old are contenders in our lore? Recommended: of age (18–24). That keeps the story inside the Moderate label and sets it apart from the source. Or should they be younger? *(Roadmap: decision 8.)*
2. Who do players play? Proposed: fixed story characters (Oss, Maren, Ines, Teo) in the arcs, and the player's own avatar in the Archive Games. Alternatively, a custom contender with a chosen Province everywhere.
3. Which Chancellor endings ship? Keep the lethal 'Strike' ending, shown only as the Skycast cutting to static and his bust in the Roll Call, or limit endings to Expose and Depose?
4. Is any story content paid? Proposed: every arc is earned by play. If your 'PREMIUM GAMEMODE' should be story, which part is premium (for example Arcs II–IV as a one-time Game Pass), with Arc I always free? Characters and their signature abilities stay earned by play either way, because they work on the Endless ladders. *(Roadmap: decision 6.)*
5. Co-op size: solo plus up to 3 (one Province's three contenders), or bigger parties?
6. Voice: is there budget to record actors for Maren, the host and the Chancellor? Or start with text-to-speech, using the lore's synthetic Wardens' voice (the Herald), and record later? *(Settled in part: text-to-speech first (the Herald), recorded voices when the budget allows.)*
7. Do you approve or want to rename the new lore names? These are: the added Provinces (Glasswater, Quarrymoor, Loomhallow), Chancellor Elias Kade, the Vale, the Tor and the Waiting Grounds, the Skycast, the Mark (1–10), the Unbound, and the in-world biome names. *(Anything can be renamed later.)*
8. In PvP, should the Showcase persona and the Mark stay reputation-only, or may they give a small, capped effect on Favour and Patrons?
9. May story characters' outfits be worn as cosmetics in PvP, given your earlier wish that Roblox avatars look normal?
10. Keep 'the Vale is the same valley every year'? It is cheap, because every Archive Game reuses this arena. Or do you want new arenas for past Games later, at a large art cost each?

## Risks

- NPC contender AI is the biggest risk to cost and quality: a first-person survival story with weak bots feels empty. Chapter One leans on scripted falls (Knell plus Roll Call) and only three live NPCs, and AgentService is shared with the Splices pillar.
- Story mode stands on untested systems. No build agent playtested anything, so movement, combat, the launch and the Roll Call need a full QA pass before chapters are tuned. Phase 1b starts after that pass.
- Turning RoundService and ArenaService into 'directors' could break the live PvP loop. Keep today's loop unchanged as the default director, and run a regression playtest before every release.
- Reserved servers don't run in Studio, and PrivateServerId and JobId are empty in Studio tests. Teleport data is visible to the client and unencrypted. Use the DevChapter hook, check unlocks again from DataService, and never trust teleport data.
- Content cost and scope creep: four arcs of 3–4 chapters, five Archive records and four endings mean months of writing, voice, set work and tuning. Ship Arc I, measure retention, then decide what comes next.
- Original-IP drift: the genre structure is shared, and signature beats or names could creep in over time. Run the banned-term check in SyntaxCheck or CI, and review story beats against the avoid list.
- Maturity: the dark themes (being selected to die, a leader's fall) can reach Roblox Select players aged 9–15 under a Moderate label once the game passes Roblox's all-ages evaluation. Parallels to real politics could trigger the Sensitive Issues descriptor, which means 16+ only. Keep everything fictional and non-graphic, with deaths as falls rather than on-screen kills.
- Roblox text-to-speech is English only and may fall short of the user's quality bar. Recorded voice costs money and needs localisation. Captions-first design means the story never waits on voice.
- DataStore growth: story flags enlarge the PlayerStats_v1 value. Keep it compact and versioned, and only ever merge by union (never delete), so it stays safe across servers.
- Place size and memory: story-only assets in the same place must stay in ServerStorage and be cloned only in story servers. StreamingEnabled rules apply: call RequestStreamAroundAsync before moving players.
- The Assessment Hall brings combat into the lobby. If the InAssessment context leaks, players could be attacked in the lobby. The server must only accept hits on the player's own TrainingDummy targets.
