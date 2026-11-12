# Arena events, hazards, creatures and the Wardens

> Pillar file for the [Roadmap](../Roadmap.md) · key `arena-events` · written by the arena events designer, lightly edited by the lead designer so names match across pillars. Phase numbers inside this file are the pillar's own; the Roadmap's phases are the build order.

**Lead notes (where the Roadmap reconciles this pillar with the others)**

- **Roadmap phases.** This pillar's Phase 1 ("The Wardens wake up") is Roadmap Phase 2, its Phase 2 ("A living arena") is Roadmap Phase 3, and its Phase 3 ("The show") spreads over Roadmap Phases 8–10.
- **Patron capsule contents** come from one table owned by the Loot pillar (its §7.5), graded Basic, Fine and Gilded at this pillar's 100, 250 and 450 Favour thresholds. The "by need" table in §7 below is its starting point.
- **The Lure is the only bait drop.** Once Citadel modifications exist (Roadmap Phase 4), its gift is a Citadel case, and it replaces the Loot pillar's fixed-schedule Citadel drops, so "one event at a time" still holds.
- **The Herald** is also the Wardens' single synthetic voice in the lore (Story pillar), so text-to-speech fits the fiction.
- **Shared NPC core.** SpliceService sits on a shared `AgentService` (paths, perception, steering) that the story NPCs reuse in Roadmap Phase 7.
- **Renamed for consistency:** the Warden Console is now Warden controls in the Private Games host panel (Modes pillar). The Arena Edict "Long Night" is now **Late Dawn**, so it doesn't clash with the Archive's "The Long Night"; Edicts and the Jubilee Games' Writs share one list of rule changes.
- **Lead review (IP):** the Spire's restock is **the Offering** (the live code still says Feast), so the Edict Early Feast is Early Offering and Feast guards are Offering guards. Splice Hunt is out of the last slot and is never released once five or fewer are alive, and the carrion flock is ordinary crows.
- **Settled by the Roadmap:** no moving wildfire front (too close to a famous film scene), and capsules and Favour are never sold.

---

**The user's headline note (quoted):** "EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES - ESCAPE LAVA RAIN ETC WILD DOGS MUTATED ANIMALS ETC". Our name for this is **Warden events**. They are run by **the Warden Director**, about one every two minutes. **Ember Rain** replaces literal lava, and **Splice hounds** (engineered wild dogs) cover the wild dogs and mutated animals. Six more events join them. Contenders earn **Favour**, Favour brings **Patron capsules**, and **the Herald** reads the **Citadel broadcasts**.

| The notes say (quoted) | Our name |
|---|---|
| "Cornucopia and starting equipment" | the Spire, the launch plates and the starting loot |
| "Gamemaker-controlled challenges" | Warden events, run by the Warden Director |
| "Mutts and genetically engineered animals" | Splices (first species: Splice hounds) |
| "Poisonous environments" | the Miasma, brackish marsh water |
| "Environmental hazards" | Ember Rain, Rockfall, the Floodgate, Cold Snap |
| "Arena manipulation" | Warden arena manipulation |
| "Force fields and restricted zones" | the border, Sector Lockdowns |
| "Randomised match events" | the Director's per-round draw, Arena Edicts |
| "Gamemaker controls" | Warden controls |
| "Sponsor gifts" | Patron capsules |
| "Audience popularity" | Favour |
| "Capitol broadcasts" | Citadel broadcasts (the Herald) |

## 1. What exists today

Checked by reading the live scripts in Studio (read-only) and the build agents' reports.

| Piece | Status | Evidence |
|---|---|---|
| Round loop | Built | `RoundService` runs Lobby → Intermission → Countdown → Active → Ending. It has the signals `roundStarting`, `roundStarted`, `roundEnded` and `phaseChanged`, plus `getElapsed()` and `getTimeScale()` (`Config.Round.StudioTimeScale` in Studio). A round with one contender is a practice round. `Server.Main` and `ClientMain` load any new module in `Services/` or `Controllers/` without changes. |
| Day/night clock | Built | `ArenaService.runClock` publishes `GameState.Clock`. `Config.Round.DaySchedule` runs from 07:24, through dusk and a 2.5-minute night (5:45–8:15), to dawn (sunrise at 8:45), day 2, and a final night that reaches 21:00 at 15:00. Clients render the sky in `ArenaController.Sky`. |
| Launch plates | Built | `workspace.Arena.Plinths.Plinth01..24`, each with a `Stand` attachment and a number plate. `LaunchController` raises them using `GameState.LaunchAt/LaunchRise/LaunchDepth`. `RoundService.enterCountdown` freezes contenders facing the Spire. |
| The Spire | Partly built | `workspace.Arena.Spire` is a placeholder built from parts: shafts, fins, four `Brazier` models with `FireFx`, `EmberBed.BeaconFx` and `EmberCore.BeaconLight`. It has no `CrateSlot_1..4`. The textured Blender Spire (LandmarksReal: 22,985 tris, `CrateSlot_1–4`, `Beacon`; 6,028 was the untextured v1 Landmarks.glb) is exported (`art/README.md`) but not imported yet. |
| Starting loot | Built | `LootService.populate()` runs at Countdown over 169 markers in `ServerStorage.ArenaData.LootSpawns`, 10 of them `T3_Crate` markers at the Spire, using `ItemDefs.LootTables[1..3]`. Contenders start empty-handed (`InventoryService.clear`). |
| The border | Built | `Config.Border` shrinks the radius from 640 to 35 between 10:00 and 13:50, with a warning 30 s before. Outside it you take 4 dmg/s, 10 once it has closed (cause "Border"). `ArenaController` draws 96 ForceField panels with a pulse, `BorderHum` and a red tint. The HUD has an alert and a compass marker. |
| The Offering (the code's Feast) | Built | `ArenaService.updateFeast` warns at 9:05. At 9:50 `LootService.refillSpire()` drops tier-3 crates from 55 studs with an orange `FeastBeacon` light, `FeastBell` rings, and `GameState.ArenaEvent` is "Feast" for 30 s. The HUD shows an event line and a pulsing Spire marker, and the tension music plays. |
| The Roll Call | Built | Runs at clock 18.55 each dusk, which is about 5:33 and 13:48. `ArenaService.runRollCall` writes `GameState.RollCall` as JSON, and `FallenRecapController` plays the point-cloud show: static, then the Cleft sigil, then a bust of each fallen contender. Its length comes from `DayCycle.recapDuration(n)`: about 18 s with 0–1 fallen, 74 s with 12, 102 s with 20. |
| Announcements | Built, no broadcast style | The `Announce` styles are Banner, Warning, Toast, Countdown, RollCall and Victory (`NotificationController.onAnnounce`). The headline supports an eyebrow, a rule colour and a sound, but the remote path doesn't pass them through. There is no announcer voice. |
| HUD hooks | Built for the Offering and border only | `HUDController.updateInfo` shows the event line ("THE FEAST IN 0:45"). The compass carries the Spire and border markers. There are an outside-border alert and directional damage arcs. There is no map screen, so the compass is where markers go. |
| Damage plumbing | Built, two small gaps | `PlayerService.damage(player, amount, {cause, attacker, position})` accepts any cause, but only Combat and Border send a `fromPosition`. Death and kill-feed text exist only for Combat, Fall, Border, Starvation, Dehydration and Left. An environmental death credits the last attacker within 15 s (`Survival.KillCreditWindow`). |
| Hitting non-players | Built for dummies | `CombatService.getTargets` returns players plus models tagged `TrainingDummy`, and `ProjectileService` uses it too. `applyHit` calls `Humanoid:TakeDamage` for non-players. `HitConfirm.target` is "Player" or "Dummy". |
| Audio | Built, no event sounds | `Shared.Sounds` has about 80 keys, including `Emit_Fire`, `Emit_Frogs`, `Emit_Wind`, `BorderHum` and the Roll Call static. `AudioController` has the ducking table, the tension and final music rules, pooled voices, and a `footstepAt()` written for NPCs. There are no creature, fire, flood, rock, cold or fog sounds. |
| World data | Built (data; the terrain in the place is still v1, Roadmap §3) | `ArenaLayout` v2 defines the Marsh (`MarshLevel` 35.5) and the River: a gorge, 32-stud falls, a plunge pool and three fords. It also has the Escarpment (W/NW, faces up to 54 studs with scree below), three caves, the Field, `MistHollows`, `dangerAt()` and `getBiome()`. Night and dawn mist sheets cover the marsh and lake (`ArenaController.Sky`). |
| Set dressing | Changing | `workspace.Arena.POIs` still holds the v1 sites that v2 retires (RiverMill, FishingShack, StiltHut), and the foliage folders use v1 biome names. The Part 2 world:set-dressing pass hasn't happened yet, and another team is editing the place. |
| Warden events, creatures, Favour, Patrons, voice | Not started | No script in the place uses `PathfindingService` or `MarketplaceService`, and there is no Favour, sponsor, parachute, hazard or private-server code. The only NPCs are the training dummies, which exist only in Studio. |

None of the base loop has been playtested yet. Every build report says so, and screen capture timed out, so nobody has seen it. Slice 1 has to include a real playtest with several clients.

## 2. Rules every Warden event follows

1. **Pressure, not punishment.** An event creates a situation and the contenders decide the outcome. A contender at full health who reacts sensibly survives any event. One who ignores it can die.
2. **Readable before it hurts.** At least 15 s before an event can hurt anyone, it shows a broadcast card, plays a sound, gives a visible sign in the world and puts a marker on the compass. Damage then ramps up instead of starting at full strength.
3. **One at a time, never personal.** The Director runs one event at a time and aims at areas and groups, never at a named contender. Splice packs pick their prey on their own, like animals do.
4. **Spectacle that stays believable.** Stone, water, fire, cold, fog and animals, physically plausible and lit by the existing day/night look. No neon, no fantasy magic.
5. **Same information for everyone.** Phones get fewer particles but the same warnings. No warning depends on colour alone. Spectators see everything.

## 3. The Warden Director: when events happen in the 15-minute round

| Slot | Broadcast at | Must end by | Purpose | Eligible events |
|---|---|---|---|---|
| (quiet) | 0:00–2:30 | — | the rush to the Spire is the event | none |
| 1 · Opening move | 2:30–2:50 | 3:50 | light (intensity 0.6): thin out the crowd at the Spire | Splice Hunt (small), Rockfall, the Floodgate, Sector Lockdown, the Lure |
| 2 · Afternoon | 4:15–4:30 | 5:25 | the first big hazard | Ember Rain, the Miasma, the Floodgate, Rockfall, Splice Hunt, Sector Lockdown, the Lure |
| (quiet) | about 5:33 | — | Roll Call 1 | none |
| Night | 10 s after Roll Call 1 ends | 8:05 | the night itself is the threat | Cold Snap or the Night Hunt (Splices) |
| Dawn | 8:10–8:15 | 9:00 | short, in the morning mist | the Miasma, Rockfall, the Floodgate, the Lure |
| (quiet) | 9:05–10:20 | — | the Offering warning, the Offering, and the border's warning and start | none |
| 5 · Herding | 10:30–10:45 | 11:35 | push stragglers inward ahead of the border (radius about 560 → 390) | Ember Rain, Splice Hunt, the Lure |
| 6 · Last light | 12:00–12:10 | 13:00 | pressure in the meadow ring (radius about 325 → 170) | Ember Rain |
| (quiet) | 13:00–15:00 | — | Roll Call 2 at 13:48, the border closes at 13:50, the final night | none |

That gives a beat every 1:45–2:15: 2:30, 4:15, about 6:30, 8:10, 9:05 (Offering), 10:00 (border), 10:30, 12:00.

- **One at a time:** a lock runs from the broadcast until 25 s after the event clears. The Offering and the border are fixed parts of the round, not Warden events. Warden events may overlap the border shrink (Slots 5 and 6 are built around it) but never the Offering window. An event is eligible only if it can finish before its slot's "must end by" time.
- **Quiet times:** the first 2:30, any time `GameState.RollCall` is set (the night slot waits for the show to end), the Offering window, everything after 13:00, and no new events once two or fewer contenders are left.
- **Ramp:** intensity is 0.6 in Slot 1, 1.0 from Slot 2 and 1.2 in Slots 5 and 6. Intensity scales zone size, pack size and how fast damage ramps.
- **Choice:** each slot picks from its eligible events. Eligibility depends on the time of day (`DayCycle.clockAt`), the border radius when the event will end, and use so far this round (each event once, Splice Hunt at most twice). Candidate zones are scored on four things:
  - how many contenders are inside (aim for 1–40% of the living, pick again above 60%);
  - how idle they are (no movement or fighting for 90 s scores higher);
  - distance from the last event's zone;
  - staying inside the border as it will be.
  The pick is weighted-random from a seed set each round (`GameState.WardenSeed`, logged for bug reports).
- **Reads the mood:** if three or more contenders died in the last 60 s, prefer an event that does no damage (the Lure, Sector Lockdown) or wait up to 20 s. If no contender has taken damage for 90 s, prefer an event that herds the idle group.
- **Lifecycle:** broadcast and warning (15–30 s) → active (30–60 s, ramping) → clearing (5–15 s) → cooldown. All times are seconds on the round's schedule, read through `RoundService.getElapsed()`, so `StudioTimeScale` speeds them up for testing.

## 4. The first event set

### 4.1 How each event warns you

| Event | The Herald (card and voice) | Sound | Sign in the world | Compass marker and alert |
|---|---|---|---|---|
| **Ember Rain** | "Contenders, look up. The Wardens are setting the sky alight. Find stone, or find water." | distant fire-thunder and crackling; a whistle before each cluster | a rust-red cloud bank gathers over the zone, visible from anywhere, glowing with embers inside; glowing rings appear on the ground 1.5 s before each cluster lands | an icon at the zone's centre; inside: "INSIDE THE EMBER RAIN · GET UNDER STONE" and metres to the edge |
| **The Miasma** | "The low ground is turning. When the frogs fall silent, climb." | the marsh frogs (`Emit_Frogs`) fade to silence, then bubbling and a low hiss | birds burst from the reeds; the marsh mist turns faint yellow-green and thickens into a flat, rising layer | an icon over the marsh; inside: "IN THE MIASMA · CLIMB" |
| **Splice Hunt** | "A Splice pack has been released. They hunt the loud and the alone." | a steel hatch hisses open; a chorus of howls rolls across the arena from that direction; growls when they're close | the hatch's red strobe; the hounds' ember-orange seams (the Wardens' colour) stay visible at night | an icon at the release point for 20 s, then a pulsing "HUNTED" mark at the screen edge when a hound is after you |
| **The Floodgate** | "The Wardens have opened the floodgates above the gorge. Leave the riverbed." | a deep horn from the mountains, the river goes quiet, then a roar from upstream | the river drops for a moment, then muddy foam and debris come down; the spray at the falls doubles | an icon along the gorge; inside: "FLOOD · GET ABOVE THE WATERLINE" |
| **Rockfall** | "The cliffs are coming down. Clear the scree." | stone groaning, trickling pebbles, then heavy impacts | dust streams and bouncing pebbles along the chosen stretch of cliff; a red flare arcs over the top | an icon on that stretch of cliff; inside: "ROCKFALL · OFF THE SCREE" |
| **Cold Snap** | "Tonight the Wardens take the warmth from the air. Find fire. Find shelter." | a bitter wind; ice crackling; your own breathing | breath vapour, frost creeping in from the screen edges, frosted grass (terrain colour changed on each client only), light snow; fires glow brighter | a small warmth icon on the compass for each fire; the Warmth bar appears |
| **Sector Lockdown** | "Sector lockdown. The Marsh seals in thirty seconds. Get out while you can." | survey pylons powering up; the border hum rising along the sector's edges | ember-orange pylons light the sector's edges and ForceField panels rise along them | the sealed sector on the compass; inside: "INSIDE A SEALED SECTOR" and the direction to the nearest way out |
| **The Lure** | "A gift from the Wardens is falling. Only one of you will open it." | a flare launching, then a slow beacon chime as the gift comes down | an orange flare marks the spot; a large parachute drifts down for 12 s | an icon and distance for everyone |

The voice lines don't name places; the card says where ("over the Field").

### 4.2 How each event plays

| Event | Where and when | How long | Damage (cause) | What contenders can do | Scaling | What it leaves |
|---|---|---|---|---|---|---|
| Ember Rain | a circle of open or forested ground where contenders are; Slots 2, 5 and 6 | 20 s warning; 45 s active (10 s ramp, 25 s peak, 10 s fade) | in the open: 1/s rising to 3/s ("Fire"). Each cluster does 15 at its centre down to 5 at 6 studs and leaves a fire patch (6 studs wide, 12 s, 4/s) | leave (the edge is never more than 150 studs away); get under stone (caves, overhangs, the cabin, the watchtower, the footbridge, the Spire's alcoves) for no damage; dense tree cover halves it; water stops it | radius 90 + 3 per contender alive (90–150; ×0.8 in Slot 6) | scorch marks and smouldering patches for 60 s |
| The Miasma | the Marsh plus 40 studs and the lake's reed shallows; Slot 2, Dawn, and Slot 5 if still inside the border | 20 s warning; the fog rises from 35.5 to about 43 over 10 s, holds 25 s, sinks over 10 s | 3/s while your head is below the top of the fog ("Miasma"), ×1.5 when sprinting | climb out; stand on causeways, hummocks or the stand of dead trees; walk, don't run | fixed zone; skipped if it holds more than 60% of the living | nothing (marsh water stays brackish all round) |
| Splice Hunt | a Warden hatch near contenders (at GiantTree, LedgeCave, HuntersCabin, FieldBoulder, CampNorth or the Watchtower) | howls 15 s before release; the hunt lasts 75 s (60 s in Slot 1; the Night Hunt runs until 8:05) | bite 12, Packleader 16 ("Splice"); armour reduces it | climb a tree or a rock (hounds can't climb); swim (they avoid deep water); fight in a narrow spot; hide early, crouched in tall grass; kill the Packleader | 2 hounds + 1 per 6 contenders alive, up to 6; ×0.6 in Slot 1. No release once five or fewer are alive | the Packleader's collar cache, if it falls |
| The Floodgate | the gorge from the spring past the falls to the NorthFord; before 10:00 | 20 s warning; the surge travels about 30 studs/s; the water stays 6 studs higher for 30 s, then drops over 15 s | 4/s while swept along ("Flood"); going over the falls into the plunge pool is survivable (landing in water does no fall damage) | get above the waterline (the gorge rims, trails, the footbridge); don't cross at fords | fixed zone; only if a contender is within 80 studs of the gorge | the fords stay deep for 60 s; driftwood on the banks gives cover |
| Rockfall | one of four stretches of the Escarpment and the scree below it; before 10:00 | 15 s warning; 8–12 boulders in 2–3 waves over 12 s | 25–45 depending on impact speed ("Rockfall") | get off the scree, or shelter in a cave mouth (CreekCave, LedgeCave, Grotto) or close under an overhang, because falling rock bounces outward | fixed number of boulders | the boulders stay where they land until the round ends, as new cover and blocked trails |
| Cold Snap | the whole arena, on night 1 | announced 10 s after Roll Call 1; starts to bite 20 s later; lasts until 8:05 | a Warmth bar drains from 100: −2/s in the open, −4/s when wet, +6/s within 18 studs of a fire, +3/s in shelter. At 0: 1.5/s ("Cold") and slower stamina regen | find a fire (the campsites, the Spire's braziers, the cabin hearth, all tagged `WarmthSource`), a cave or the cabin; share the fire or fight for it | arena-wide; there is a source of warmth within about 250 studs of anywhere | nothing |
| Sector Lockdown | one of the `ArenaLayout.Sectors`, from radius 180 out to the border; before 10:00 | 25 s warning; sealed for 45 s | being inside counts as being outside the border: 4/s ("Sealed") | leave in time; like the border, the walls never block movement | never a sector holding more than 40% of the living | nothing |
| The Lure | a contested open spot between groups (high `ArenaLayout.dangerAt`: a ford, the Field, the lake shore, the edge of the plaza) | 20 s flare; 12 s descent; open for 60 s | none | it's bait: ambush, rush it or ignore it; whoever opens it first gets +25 Favour | two gifts when 13 or more are alive | a fight |

How they work in code:
- **Ember Rain cover:** every 0.5 s the server casts a ray straight up from each contender in the zone against solid geometry. Leaves have `CanQuery = false`, so trees don't count as cover. The half cover under dense trees comes from a coarse grid of tree cover that `Populate` builds in Studio. The clusters come from a seed, so every client draws the same impacts from `WardenEventData.seed` and the server time, and the server applies damage at the same moments.
- **The Floodgate:** take a snapshot of the gorge with `Terrain:ReadVoxels`. Fill only the empty voxels below the rising waterline, about 1–2k voxels per step, twice a second, then restore the snapshot afterwards. Contenders caught in the surge get pushed downstream along `ArenaLayout.River.path` on their own client (`HazardImpulse` → `MovementController.applyImpulse`). If the terrain writes misbehave, fall back to a wave mesh drawn on the clients with the same damage zone.
- **Rockfall:** the boulders reuse rock meshes from `ServerStorage.WorldAssets.Rocks` and are simulated on the server (network owner nil). Damage comes from the server checking moving boulders against nearby contenders, not from `Touched`. Each boulder is anchored once it stops.
- **Cold Snap:** the Warmth bar is a fourth thin bar beside the vitals and only appears while the event runs. Each client frosts its own grass with `Terrain:SetMaterialColor` and brightens its own fire lights.
- **Sector Lockdown:** turn `ArenaController`'s ring of border panels into general wall segments. The damage reuses the logic of `ArenaService.borderDamage`.

## 5. Fairness and scaling

- The warning is at least 15 s: Splices give 15 s plus the time it takes them to reach you, and most events give 20–30 s. Every zone can be left at a jog within its warning (13 studs/s covers the 150 studs at most to the edge).
- A contender who leaves or takes cover within 10 s of an event starting takes at most about 25 damage. Standing in the open for all 45 s of Ember Rain is lethal (about 115 damage).
- A zone never holds more than 60% of the living when it starts. The Director favours idle groups, which discourages camping without punishing hiding itself.
- The existing rule stands: an environmental death within 15 s of being hit credits whoever hit you. A rival who knocks you into a fire patch or leads a pack to you gets the kill, and the Wardens never take a kill that no contender helped with.
- Splice packs leave contenders under 25% health alone unless those contenders attack them.
- By contenders alive:
  - 13 or more: everything at full size.
  - 6–12: zones up to 130 studs and 4 hounds.
  - 3–5: zones up to 100 studs placed between contenders to bring them together; no Splice Hunt.
  - 2: no new events; the final duel belongs to them.
  - Practice (one contender): events at half damage and two hounds.

## 6. Splices: engineered creatures

**Look and tone.** Splice hounds are big, lean engineered wild dogs, about 2.8 studs (90 cm) at the shoulder.
- **Body:** synthetic plates grafted along the spine and shoulders, ember-orange lights along the seams (the Wardens' colour, which also keeps them visible at night), and a steel collar with a status light. The Packleader is larger and wears a heavier collar.
- **Art:** realistic PBR materials from the Blender pipeline, at most 8k tris with one 1K texture set.
- **Hits and deaths:** a hit throws sparks and ember flecks, never blood. At 0 health the seams flare and the body crumbles into ash and embers in about 1.5 s.
- **Content maturity:** Roblox's current Content Maturity questionnaire counts creatures that "poof into smoke" as having an unrealistic consequence. It counts non-realistic monsters with mild tension and ominous music as "Scary", and jump scares and sustained tension as "Horrifying". So the hounds always growl before they lunge, there are no jump-scare stings, and no Splice ever resembles a fallen contender.
- **Community Standards:** they ban animal cruelty at every rating, so there are no traps, no harming harmless animals, and nothing to harvest from a Splice.

**Pack brain (server, 5 times a second).** One per pack.
- **Choosing prey:** scores contenders up for noise (sprinting or fighting), isolation (distance to the nearest other contender), idleness and being inside the hunting ground. Scores down contenders already being hunted, under 25% health, swimming, or up a tree. It reassesses every 3 s.
- **Attack turns:** at most two hounds attack one contender at a time; the rest circle at 8–12 studs on opposite sides.
- **Howls:** the pack howls when it's released and when it finds prey.

**Each hound (server, 10 times a second, spread across frames).**
1. Emerge from the hatch.
2. Track: follow a path to where the prey was last seen.
3. Stalk: within 35 studs, trot low, keep to its side and growl.
4. Engage: when it's this hound's turn, close to 4 studs.
5. Lunge: a 0.45 s warning (it crouches, snarls and its seams flare).
6. Bite: it hits if the prey is within 4.5 studs and inside a 60° cone in front of it at that moment, with a small shove.
7. Recover for 1.2 s, back off 6–8 studs, and repeat.

Hounds trot at 14 and chase at 19 studs/s. That is faster than a jog (13) and slower than a sprint (21), but sprint stamina lasts only about 9 s, so you have to climb, swim or fight. If the prey stays out of reach for 12 s (up a tree, in deep water), the hound circles and barks, then picks new prey. The pack is called back when the hunt timer ends, or when the Packleader and half the pack are down. The hounds then run for the hatch and dissolve.

**Senses.**
- **Hearing:** a sprint within 60 studs, a fight within 50, walking within 25, crouching within 8. The server already knows who is sprinting (above `Survival.SprintSpeedThreshold`, 17) and who is crouched (`Character.Stance`).
- **Smell:** always within 12 studs.
- **Sight:** within 45 studs in a 120° cone, checked with a line-of-sight ray. Against a contender crouched in tall grass the range is ×0.4.

This matches how contenders already hear each other (crouched footsteps are quieter and carry less far), so their instincts about stealth still work.

**Networking.**
- **Rig:** each hound is a Humanoid rig owned by the server, kept in `workspace.Arena.Splices`.
- **Ownership:** call `HumanoidRootPart:SetNetworkOwner(nil)` after parenting, and set it again whenever it changes.
- **Streaming:** `ModelStreamingMode = Atomic`, with climbing turned off.
- **Animation:** plays on the server's Animator, which replicates it.
- **Clients:** add only looks and sound: seam flicker, breath in the cold night air, and paw steps through `AudioController.footstepAt`.

**Pathfinding.**
- **Path:** one `Path` per hound with AgentRadius 2, AgentHeight 3, AgentCanJump true, AgentCanClimb false and WaypointSpacing 6.
- **Costs:** `Water = 30`, `Mud = 2`, `Snow = 3`, and `math.huge` for a `Hazard` PathfindingModifier label placed over active event zones.
- **Recompute:** when the prey has moved more than 12 studs from the path's end, at most every 1.2 s per hound and 4 times a second across all hounds.
- **Short range:** within 30 studs and with a clear line of sight, chase directly with `MoveTo`. On `Path.Blocked`, compute again.
- **Stuck:** if a hound moves less than 1 stud in 1.5 s, it hops, then finds a new path, then gives up on that prey.
- **Limits:** hounds never leave the play radius, and they dissolve if caught outside a closed border.
- **Long trips:** a Roblox path search can use at most 20,000 nodes, which a forested 1,300-stud arena can run out of, so long trips are split into legs between trail points (`ArenaLayout.Trails`).

**Performance budget.**
- **Server:** at most 6 hounds per pack and 8 alive in total, and at most 2 raycasts per hound per tick. Target: 1.5 ms per server frame or less with 8 hounds (MicroProfiler label `SpliceService`).
- **Clients:** at most 2 particle emitters per hound. Their sounds go through the pooled voices, with priority over footsteps.

**Animations** (made in Blender and uploaded under the experience's owner so they play):
- Movement: idle, sniff, trot, gallop, stalk, turn in place.
- Combat: lunge and bite, hit reactions left and right.
- Pack behaviour: howl, barking up a tree, flee.
- Death: collapse, plus the dissolve effect.

**Combat and loot.**
- **Being hit:** a `Splice` tag joins `CombatService.getTargets`, so melee and every projectile can hit them. `applyHit` sends Splice hits to `SpliceService.onHit`, which plays the hit reaction, turns the hound on its attacker and awards Favour on a kill. `HitConfirm.target` becomes "Creature".
- **Biting:** bites go through `CombatService.applyHit(nil, humanoid, damage, { cause = "Splice", position = hound })`. Vests reduce them, and the damage arcs point at the hound.
- **Health:** 60, or 110 for the Packleader.
- **Loot:** ordinary hounds drop nothing. The Packleader's collar breaks open into a cache with one roll from `LootTables[3]` (`LootService.spawnGroundItem`).

**Later species (Phase 3):**
- **A Splice boar:** a heavy charger that drives contenders out of cover.
- **A carrion flock:** ordinary crows, not a Splice, that gather over a contender who stays in one place and so give them away. They are never engineered by the Wardens to spy and never copy sounds, because engineered spy birds are a source signature.

Stay away from engineered insects and birds that mimic voices: both are too close to the source material.

## 7. Favour and Patrons

**Favour** is the audience's support. It lasts one round only: it is a Player attribute, `Favour`, reset at the start horn.

| Earned by | Favour |
|---|---|
| Staying alive | +1 every 10 s |
| An elimination (kill credit, including credited environmental kills) | +40 |
| An elimination of the contender with the most Favour | +25 more |
| Style: a bow headshot · a long shot (over 35 m) · a kill while two or more rivals hit you in the last 10 s · surviving 15 s after dropping under 10 health | +10 · +10 · +20 · +15 |
| Being caught in a Warden event and still alive when it clears | +30 |
| Killing a Splice hound · the Packleader | +15 · +40 |
| Being first to open the Lure | +25 |
| Fighting at the Offering (damage dealt near the Spire while it runs) | +1 per 5 damage, up to +30 |
| Being among the last 8 · 5 · 3 · 2 | +10 · +20 · +30 · +50 |

**Patron capsules** arrive at 100, 250 and 450 Favour, at most three per contender per round.

- **What's inside follows your need.** Each capsule holds two items:

| The Patron sees | First item | Second item |
|---|---|---|
| Health under 40% | bandage ×2 (a med kit at 450+ Favour) | water bottle or apple |
| Thirst under 35 | water bottle | berries ×3 |
| Hunger under 35 | ration pack | water bottle |
| Fists only | hunting knife for the first gift, then a machete or hatchet | bandage |
| A bow with fewer than 6 arrows | arrows ×8 | dried meat |
| Cold Snap running | Thermal Wrap (new item) | dried meat |
| The Miasma nearby | Filter Mask (new item) | healing herbs ×2 |
| None of these | one roll from `LootTables[2]` | apple |

  A contender already holding a tier-3 weapon gets no weapons, and once three or fewer remain capsules hold only consumables. Each capsule carries a short note card from a set of fixed lines, for example "From a Patron in Saltmarsh: drink first, fight later."
- **How it arrives.**
  - **Landing spot:** 14–30 studs from the recipient, with open sky for 200 studs above, a slope under 30°, dry ground, inside the border, outside event zones, in the recipient's line of sight and away from rivals. If nothing fits, it lands at their feet.
  - **Descent:** a steel capsule on a small drogue parachute takes 8 s to come down from about 160 studs, trailing orange smoke and chiming softly, so everyone nearby sees and hears it.
  - **Code:** clients animate the descent on a shared timeline and the server places the real crate when it lands. That is a new `LootService.spawnCapsule(items, landing, opts)` next to `spawnCrate` and `dropCrateIn`, with the model from a new `ItemModels.buildCapsule()` until the Blender capsule replaces it.
  - **Opening:** hold for 0.8 s. Only the recipient can open it for the first 10 s, then anyone can.
- **Limits:** at most two capsules in the air at once. They wait during Roll Calls, and none arrive in the last 60 s.
- **Never sold.** Capsules and Favour can only be earned. Selling them would be pay-to-win. Paid random contents would also fall under Roblox's paid-random-items rules: the odds shown before purchase, and blocked wherever `PolicyService` reports paid random items as restricted. Robux only buys looks: capsule paint, parachute canopy and smoke colour. These are the Economy pillar's Canopies (the notes' "Parachute effects"); other players see them and they change nothing in play.

**Audience popularity.**
- **On the HUD:** a small gold Favour chip next to "17 REMAIN", with three dots showing progress to the next capsule. Gains show as toasts ("+30 · came through the Ember Rain").
- **Herald callouts:** for big moments, at most one every 45 s. Names appear in text only.
- **Round summary:** `RoundSummary` gets a `favour` value per row, and the victory screen names the **Favourite of the Games** (the most Favour).
- **Phase 3, spectators:** eliminated players may back one contender (free; each backer adds +10% to that contender's Favour gain, up to +50%). They may also vote between two eligible Warden events 15 s before a slot. Nothing is staked and no currency changes hands.

## 8. Citadel broadcasts

**The Herald** (a working name) is the Citadel's announcer, heard over the arena's loudspeakers. In the lore it is the Wardens' single synthetic voice (Story pillar §3.6).
- **Voice:** cool and theatrical, run through a loudspeaker chain built with the Audio API's effects: band-pass, light distortion and a long outdoor reverb.
- **Lines:** fixed, either generated with Roblox's text-to-speech (`AudioTextToSpeech` / `GenerateSpeechAsset`, which offers a fixed set of English voices and up to 300 characters per request) or recorded by a voice actor.
- **Names and subtitles:** the voice never says a player's name; names appear only in text. Subtitles are always on.

| Moment | Line |
|---|---|
| The start horn | "Contenders. The arena is open. The Citadel is watching." |
| An event clears | "The embers are spent." · "The air in the hollows is clean again." · "The hunt is over. The pack is called home." · "The river remembers its banks." · "The stone has settled. The paths have changed." · "Dawn. The cold lets go." · "The seal lifts." · "The gift has been claimed." |
| A Patron's gift (heard by the recipient only) | "A Patron has taken an interest in you." |
| The Offering and the border (the existing cards gain a voice) | "The Spire has been restocked." / "The border is closing. Make for the Spire." |
| Two remain | "Two remain. The Citadel holds its breath." |

**The broadcast card** is a new `Announce` style:

`{ style = "Broadcast", eyebrow = "CITADEL BROADCAST", text = "EMBER RAIN", sub = "Over the Field in 20 s · find stone or water", glyph = "EmberRain", vo = "VO_EmberRain_Warn", duration = 6 }`

- **The card:** reuses the existing headline (Oswald title, eyebrow line, ember-orange rule). It adds a 48 px line icon and a 0.25 s burst of static as it appears, borrowing the Roll Call's look and its `RollCallBurst` sound. Then the Herald speaks.
- **After it:**
  - the HUD event line ("EMBER RAIN · THE FIELD · 0:18", then "EMBER RAIN · 0:41 LEFT");
  - the compass icon;
  - the inside-the-zone alert, in the same place as the border alert.
- **Lobby, spectators and the end:** players in the lobby get a one-line toast ("In the arena: Ember Rain over the Field") and spectators get the full card. A toast follows when it clears ("THE EMBER RAIN HAS PASSED · 7 came through it").
- **Never during a Roll Call:** broadcasts don't play while one is running.

## 9. How it plugs into the existing round loop

- **RoundService:**
  - **Start:** `roundStarted` sets up the round (seed, random offsets inside each slot).
  - **Ending:** on `phaseChanged`, Ending stops every event and calls the Splices back.
  - **Lobby:** `WardenService.clearArena()` restores flooded voxels and removes boulders, scorch marks and capsules.
  - **Schedule:** `getElapsed()`, `getTimeScale()` and `isPractice()` drive it.
- **ArenaService** keeps the clock, the border, the Offering and the Roll Call. Add `getBorderAt(elapsed)` (wrapping its local `radiusAt`) so a zone can be checked against the border as it will be when the event ends. The Director reads `GameState.RollCall` for the Roll Call quiet time and `Config.Events.FeastTime/FeastWarning` for the Offering window. Warden events use their own attributes, so `ArenaEvent` keeps meaning "Feast" for the HUD and audio code that read it.
- **The border:** Slots 5 and 6 put zones inside the shrinking ring to herd contenders inward. Sector Lockdown runs only before 10:00. Hounds caught outside a closed border dissolve.
- **The Offering:** stays a quiet window. Phase 3 could add "Offering guards": a small pack at the Spire during the Offering when 8 or more are alive.
- **The clock:** `DayCycle.clockAt` decides night and dawn eligibility. Cold Snap and the Night Hunt own night 1, and the Miasma at dawn sits in the existing dawn mist.
- **The Roll Call:** deaths from events reach it unchanged through `PlayerService.died`.
- **The Spire:** the Herald's line plays at the start horn. Once the Blender Spire with `CrateSlot_1..4` is imported, its alcoves count as cover from Ember Rain.
- **Late joiners and spectators:** `WardenEventData` is JSON holding a seed and server times, like the Roll Call's data, so they can render an event that's already under way.

| Module | New or extended | Change |
|---|---|---|
| `Server.Services.WardenService` (with `Events/*` modules) | new | the Director, event lifecycle, zone damage checks, broadcasts, and a `DevWarden` trigger for Studio |
| `Server.Services.SpliceService` | new | packs, hound brains, path budget, attack turns, hits, dissolving, drops |
| `Server.Services.FavourService`, `PatronService` | new | Favour sources and thresholds; capsule contents, landing spot and delivery queue |
| `PlayerService` | extend | send `fromPosition` for any cause that has a position |
| `CombatService` | extend | add the `Splice` tag to `getTargets`; send hits to `SpliceService`; `HitConfirm.target = "Creature"`; a server-side `hit` signal for Favour |
| `LootService` | extend | a public `dropCrate` (for the Lure v0) and `spawnCapsule` |
| `MovementController` | extend | `applyImpulse` for the flood's current and bite shoves (the `HazardImpulse` remote) |
| `Client.Controllers.WardenController` | new | event visuals from the seed, fog, frost, flood foam, pylons and walls, local sound cues |
| `ArenaController.Sky` | extend | `setOverlay(id, look, weight)` for event skies; a mist style per zone |
| `HUDController`, `NotificationController` | extend | event icons on the compass, the event line, the zone alert, the Warmth bar, the Favour chip; the `Broadcast` style; death and kill-feed text for the new causes |
| `Shared.Sounds`, `AudioController` | extend | about 30 new keys; a ducking entry for the broadcast sting; tension music during events |
| `Shared.Config` | extend | `Config.Wardens`, `Config.Splices`, `Config.Favour`, `Config.Patrons` |
| `Shared.ArenaLayout` | extend | `WardenHatches`, candidate Ember Rain zones, `RockfallSegments` |
| `ServerStorage.WorldGen.EventAssets` | new builder | hatches, pylons, flare launchers, the placeholder hound and capsule (rebuildable, per the spec's version-control rule) |
| `Shared.ItemDefs` | extend (Phase 2) | `filter_mask`, `thermal_wrap` |

**What gets shared between server and clients:**
- **GameState attributes:** `WardenEvent` ("" or an event id), `WardenEventData` (JSON: id, name, phase, zone, warnAt, startAt, endAt, seed, intensity) and `WardenSeed`.
- **Player attributes:** `Favour` and `Warmth`.
- **Remotes:** `WardenFx`, `HazardImpulse` and `FavourGain`.
- **Tags:** `Splice`, `WarmthSource`, `WardenHatch` and `PatronCapsule`.
- **Damage causes:** "Fire", "Miasma", "Splice", "Flood", "Rockfall", "Cold" and "Sealed".

All of this state lives on the server; clients only render it.

## 10. Phases

| Phase | Contents | Size |
|---|---|---|
| 1 · The Wardens wake up | the Director, broadcast cards, Ember Rain, Splice Hunt v0, the Lure v0, the damage plumbing, Studio triggers | L |
| 2 · A living arena | the Miasma (plus brackish water), the Floodgate, Rockfall, Cold Snap, Sector Lockdown; Favour and Patron capsules; the Blender hound and its animations, the Packleader and the Night Hunt; the Herald's voice; telemetry (deaths by cause, how many survive each event) | XL (about 6–8 weeks) |
| 3 · The show | Arena Edicts (one random rule per round: Lean Year, Late Dawn, Hunting Season, Heavy Mist, Early Offering); spectator backing and the event vote; Warden controls in the Private Games host panel; Offering guards; new Splice species; a set of events for the Jubilee Games | XL, ongoing |

## 11. First build slice: "The Wardens wake up" (L, about 2 weeks)

1. **`WardenService`**, with `Events/EmberRain`, `Events/SpliceHunt` and `Events/Lure`: the slot schedule (`Config.Wardens`), one event at a time, the quiet times, zone scoring, the round's seed and the GameState attributes. Trigger an event in Studio with `GameState:SetAttribute("DevWarden", "EmberRain")`. Repeats are allowed while only three events exist.
2. **The broadcast card:** the `Broadcast` style, the HUD event line, the compass icon, the inside-the-zone alert and the lobby toast. Text only; no voice yet.
3. **Ember Rain:** server-side exposure and cover checks; clusters from the seed, each warned by a ground ring, with fire patches; `WardenController` visuals (cloud bank, falling embers, scorch marks); the new `Sky.setOverlay` hook; six new sounds.
4. **Splice Hunt v0:** 2–4 placeholder hounds made by a builder in `WorldGen` (like `DummyBuilder`) as Humanoid rigs owned by the server. Pathfinding with a shared compute budget, attack turns, the lunge warning, and bites through `CombatService.applyHit`. The `Splice` tag in `getTargets`, `HitConfirm` "Creature", dissolving on death, and the call back to the hatch.
5. **The Lure v0:** a tier-3 crate dropped at a contested spot using the existing Offering drop.
6. **Plumbing:** `fromPosition` for every cause with a position, and death and kill-feed text for "Fire" and "Splice".

**Done when** all of these hold:
- A Studio round with `StudioTimeScale` 6 runs events in all six slots, never two at once and never during a Roll Call or the Offering window.
- A contender at full health who reacts takes 25 Ember Rain damage or less; one who stands in the open dies.
- Hounds reach and bite a contender, never more than two at once. Every weapon and arrow can kill them, and they give up on prey that is up a tree or swimming.
- Kill credit works when a rival led the pack to a contender.
- `SpliceService` stays at 1.5 ms per frame or less with 4 hounds.
- Everything is cleaned up when the round ends.
- A playtest with 4 clients (Test > Clients and Servers) passes.

**Depends on** nothing that blocks it. Coordinate the small edits to `CombatService`, `PlayerService`, `NotificationController` and `HUDController` with the team editing the place now, and check the Splice paths again after the v2 set-dressing pass.

---

## Checklist items in this pillar

Status, size and Roadmap phase match the master checklist in the [Roadmap](../Roadmap.md).

### 7. “Cornucopia and starting equipment”

- **Our name:** The Spire, the launch plates and the starting loot
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 1
- **Pillar phase:** Phase 1: the import belongs to the world:set-dressing pass; this pillar adds the start-horn broadcast and makes the Spire's alcoves count as Ember Rain cover
- **From the notes:** “Cornucopia and starting equipment”
- **Evidence:** Built: Plinth01–24 in workspace.Arena.Plinths, each with a Stand attachment and a number plate, rising on GameState.LaunchAt/LaunchRise/LaunchDepth (LaunchController). RoundService.enterCountdown freezes contenders facing the Spire. LootService.populate() fills 169 LootSpawns markers, 10 of them T3_Crate at the Spire. Contenders start empty-handed (InventoryService.clear at Countdown). Not yet: workspace.Arena.Spire is a placeholder built from parts (4 Braziers with FireFx, EmberBed.BeaconFx) with no CrateSlot_1..4. The Blender Spire with CrateSlot_1-4 and Beacon is exported (art/README.md) but not imported, and the POIs and foliage are still the v1 set.

### 8. “Gamemaker-controlled challenges”

- **Our name:** Warden events, run by the Warden Director
- **Status:** Not started · **Size:** L · **Roadmap phase:** 2 → 3
- **Pillar phase:** Phase 1 (first slice)
- **From the notes:** “Gamemaker-controlled challenges”; raw note: “EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES - ESCAPE LAVA RAIN ETC”
- **Evidence:** Not started: `script_grep` "Warden" finds nothing in the place. Only fixed parts of the round exist, in ArenaService's step that runs 5 times a second: the Offering (warning at 545 s, restock at 590 s), the border (600–830 s) and the Roll Calls at clock 18.55. GameState.ArenaEvent is only '' or 'Feast', and the Warning/Banner announcements and the HUD event line cover just those. There is no event pool, director or hazard code anywhere in the place.

### 9. “Mutts and genetically engineered animals”

- **Our name:** Splices (first species: Splice hounds and their Packleader)
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 2 → 3 → 10
- **Pillar phase:** Phase 1 (v0 pack with placeholder hounds) → Phase 2 (Blender hound, animations, Packleader, Night Hunt) → Phase 3 (new species)
- **From the notes:** “Mutts and genetically engineered animals”; raw note: “WILD DOGS MUTATED ANIMALS”
- **Evidence:** No script uses PathfindingService and there is no creature or NPC code in the place. The only non-player targets are the training dummies, which exist only in Studio (CombatService.getTargets/applyHit, which already damage non-player Humanoids). Existing hooks to build on: AudioController.footstepAt (written for NPCs) and ProjectileService, which also uses CombatService.getTargets.

### 10. “Poisonous environments”

- **Our name:** The Miasma (poison fog in the low ground) and brackish marsh water
- **Status:** Not started · **Size:** M · **Roadmap phase:** 3
- **Pillar phase:** Phase 2
- **From the notes:** “Poisonous environments”
- **Evidence:** The only mist is visual: ArenaController.Sky draws mist sheets over the marsh and lake at night and dawn. ArenaLayout v2 already provides the Marsh (MarshLevel 35.5), isInMarsh(), MistHollows and the lake's reed shallows. PlayerService has no poison cause, and all water drinks the same (Config.Survival.DrinkPerSip 10).

### 11. “Environmental hazards”

- **Our name:** Today's fall, starvation, thirst and void damage, then Ember Rain, Rockfall, the Floodgate (flash flood in the gorge) and Cold Snap
- **Status:** Partly built · **Size:** XL · **Roadmap phase:** 2 → 3
- **Pillar phase:** Phase 1 (Ember Rain) → Phase 2 (Rockfall, the Floodgate, Cold Snap)
- **From the notes:** “Environmental hazards”; raw note: “ESCAPE LAVA RAIN”
- **Evidence:** Built survival hazards: fall damage (MovementService, from 13 to 58 studs, none in water), death below y −80, starvation and dehydration at 1.5 dmg/s (PlayerService), and border damage at 4 or 10 dmg/s. There are no event hazards and no fire, flood, rock, cold or fog sounds in Shared.Sounds. ArenaLayout v2 has the data these events need: the river gorge, the 32-stud falls, the plunge pool, the fords, the Escarpment with its scree, and three caves.

### 12. “Arena manipulation”

- **Our name:** Warden arena manipulation: lasting changes after events, Sector Lockdowns, the Lure, the Offering
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 2 → 3
- **Pillar phase:** Phase 1 (the Lure v0) → Phase 2 (boulders, deep fords, scorch marks, Sector Lockdown)
- **From the notes:** “Arena manipulation”
- **Evidence:** The Offering is built: ArenaService.updateFeast calls LootService.refillSpire, which drops tier-3 crates from 55 studs with an orange FeastBeacon light. The border shrink also reshapes the play space. Nothing else changes the arena during a round: no lasting debris, sealed areas or bait drops.

### 13. “Force fields and restricted zones”

- **Our name:** The border and Sector Lockdowns
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 3
- **Pillar phase:** Phase 2
- **From the notes:** “Force fields and restricted zones”
- **Evidence:** The border is built: Config.Border shrinks it from 640 to 35 studs over 600–830 s with a 30 s warning; outside it you take 4 dmg/s, 10 once it has closed (cause 'Border'). ArenaController draws a ring of 96 ForceField panels with a pulse, BorderHum and a red tint, and the HUD shows an outside-border alert and a compass marker. There are no sealed sectors or other restricted zones.

### 14. “Randomised match events”

- **Our name:** The Director's per-round draw, plus Arena Edicts (one random rule per round)
- **Status:** Not started · **Size:** M · **Roadmap phase:** 2 → 10
- **Pillar phase:** Phase 1 (the seeded draw ships with the Director) → Phase 3 (Arena Edicts)
- **From the notes:** “Randomised match events”
- **Evidence:** Every part of the round is fixed in Config (Events.FeastTime 590, Border.ShrinkStartTime 600, Round.DaySchedule). The only randomness per round is the loot rolls (ItemDefs.LootTables) and which plate each contender gets (RoundService shuffle).

### 42. “Gamemaker controls”

- **Our name:** Warden controls: the Director's settings, a Studio trigger, and later Warden controls in the Private Games host panel, a spectator vote and the Warden's Chair (sized in #49)
- **Status:** Not started · **Size:** M · **Roadmap phase:** 2 → 8 → 9 → 10
- **Pillar phase:** Phase 1 (Config.Wardens settings and the 'DevWarden' Studio trigger) → Phase 3 (host-panel Warden controls, spectator vote)
- **From the notes:** “Gamemaker controls”
- **Evidence:** Only Studio settings exist: Config.Round.StudioTimeScale, Config.Studio.SoloTest/FastTimers, and the GameState 'DevRollCall' attribute (ArenaService). There are no event triggers and no private-server logic (no script uses PrivateServerId).

### 43. “Sponsor gifts”

- **Our name:** Patron capsules (supply capsules on parachutes, earned with Favour)
- **Status:** Not started · **Size:** L · **Roadmap phase:** 3
- **Pillar phase:** Phase 2
- **From the notes:** “Sponsor gifts”
- **Evidence:** There is no gift, sponsor or parachute code. Pieces to reuse: LootService's local spawnCrate and dropCrateIn (the Offering's drop from the sky with a FeastBeacon light), the crate tiers in ItemModels.buildCrate, and LootService's server-checked prompts. No script uses MarketplaceService, which is right: gifts must never be for sale.

### 44. “Audience popularity”

- **Our name:** Favour and the Favourite of the Games
- **Status:** Not started · **Size:** M · **Roadmap phase:** 3
- **Pillar phase:** Phase 2
- **From the notes:** “Audience popularity”
- **Evidence:** There is no Favour or popularity code. The inputs already exist: PlayerService.died(victim, killer, cause), the Player Kills and Placement attributes, KillFeed and the RoundSummary placements. CombatService sends HitConfirm to the attacker but has no server-side hit signal yet.

### 47. “Capitol broadcasts”

- **Our name:** Citadel broadcasts: the Herald's voice and the broadcast card
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 2 → 3 → 7
- **Pillar phase:** Phase 1 (broadcast card, text only) → Phase 2 (the Herald's voice)
- **From the notes:** “Capitol broadcasts”
- **Evidence:** The Announce remote has Banner, Warning, Toast, Countdown, RollCall and Victory styles (NotificationController.onAnnounce). The headline already supports an eyebrow, a rule colour and a sound, but the remote path doesn't pass them through. The Roll Call sky show (FallenRecapController: static, the Cleft sigil, then busts) sets the look for broadcasts, and stings duck the mix (AudioController DUCKS). There is no announcer voice and there are no event cards.

## Open questions

1. Cadence: is about one Warden event every two minutes right (six per round, none in the first 2:30 or the last two minutes), or would you rather have fewer, bigger events? *(Roadmap: decision 1.)*
2. Lethality: should an event be able to kill a contender at full health who ignores it completely? The proposal is yes, while a sensible reaction costs about 25 health at most. Or should events never kill on their own? *(Roadmap: decision 1.)*
3. Splice look: realistic engineered wolf-dogs with ember-orange seams that crumble to ash (scary but not horrifying), or something more monstrous? *(Roadmap: decision 2.)*
4. Should contenders be able to lead a Splice pack onto rivals and get the kill credit, and should the Packleader's collar drop loot?
5. Favour: should each contender see only their own, or everyone's (with an audience favourite shown during the round)?
6. Patron gifts: contents based on what you need (proposed) or surprises? Can they include weapons, and is three per round the right limit? *(Settled in part: contents follow need, from one table (Loot pillar §7.5).)*
7. Does Favour turn into Gold at the end of a round, and at what rate, or does it only matter during the round?
8. Spectators: may eliminated players vote between two Warden events, or back a contender? Both would be free, with nothing staked.
9. The Herald: Roblox's built-in text-to-speech voices or a hired voice actor? And what persona and name? *(Settled in part: the Herald is the Wardens' synthetic voice in the lore, so text-to-speech comes first.)*
10. Names: keep or rename Ember Rain, the Miasma, Splice Hunt and Splice hounds, the Floodgate, Rockfall, Cold Snap, Sector Lockdown, the Lure, the Herald, Favour and Patron capsules? *(Anything can be renamed later.)*
11. A moving wildfire front in a later phase: great spectacle, but closer to a famous film scene than Ember Rain. In or out? *(Settled: out (IP).)*
12. Private servers: should owners get Warden controls in the host panel to set how often events happen, choose which events run, and trigger one now? Roblox allows that as a reason to buy a private server. *(Settled: yes, as Warden controls in the Private Games host panel (Roadmap Phase 8).)*
13. Please confirm the rule: Patron capsules and Favour are never sold for Robux or Gold, and only cosmetic capsule and parachute styles are. *(Settled: never sold (Roadmap platform rules).)*

## Risks

- Performance on phones and on the server: 6–8 server-simulated hounds, event particles and the flood's terrain writes all add up. Mitigation: hard caps (at most 8 hounds, 4 path computations per second), pooled effects that scale with graphics quality, and MicroProfiler budgets in slice 1's 'done when' list.
- Pathfinding over a forested terrain arena 1,300 studs across can run out of Roblox's 20,000-node search budget and fail while content streams in. The v2 set dressing isn't placed yet, so hound paths must be checked again after the world:set-dressing pass. Fallbacks: chase directly at short range, and split long trips into legs between trail points.
- Fairness: random hazards that kill feel cheap. Mitigation: the warning rules, damage that ramps up, the existing 15 s kill-credit rule, picking another zone when one holds too many contenders, and telemetry on deaths by cause for each event.
- Clashes with fixed parts of the round: a Roll Call lasts from about 18 s to about 102 s depending on how many fell, and the border shrinks during Slots 5 and 6. The Director must read GameState.RollCall and check that each event can finish before its slot ends.
- Parallel edits: another team is changing the place now, and ArenaService, HUDController, NotificationController and Config are shared files. Keep this pillar's changes additive: new services and controllers, small hook edits, and separate WardenEvent attributes so the 'Feast' meaning of ArenaEvent doesn't change.
- Content maturity: night hunts and first-person fights with creatures. Keep Splice deaths unrealistic (they dissolve), no blood, and no jump scares; jump scares count as 'Horrifying' fear in the questionnaire and would raise the label. No cruelty mechanics either, since Community Standards ban them at every rating.
- Closeness to the source material: some genre scenes are strongly tied to it (engineered wasps, birds that mimic voices, creatures with fallen contenders' features, a wall of fire chasing one contender, an arena laid out like a clock with timed zones, a pack driving the last contenders onto the central structure). Avoid them, and review names, lines and creature designs before shipping. The source has a named feast at its central structure, so ours is the Offering, with its own presentation.
- Monetisation drift: selling Patron capsules or Favour would be pay-to-win, and paid random contents would fall under Roblox's paid-random-items policy (odds shown before purchase, PolicyService restrictions). Make 'capsules come only from Favour' a hard rule in PatronService.
- Flood terrain writes: they cost replication bandwidth, must restore the terrain exactly, and can clash with TerrainGen reruns. Take a snapshot and restore it for each flood, cap the voxel writes, and keep the wave-mesh fallback ready.
- The base loop hasn't been playtested and nobody has seen it running (build reports, screen-capture timeouts). Event work may uncover bugs in the base loop, which is why slice 1 includes a playtest with 4 clients.
- Audio and voice: the audio agent flagged several Creator Store sounds whose source it couldn't confirm, and the text-to-speech voices are limited. Find licensed creature, fire, water and rock sounds, and choose the Herald's voice early.
- Scope: eight events, creatures, Favour and Patrons together are XL. Ship in slices and use telemetry to judge each one before adding more.
