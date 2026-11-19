# The Training Centre and the road to the arena

*Design page, 19 Nov 2026 (wave 14, design-training). Written against the repo at Studio version 588. Nothing in `src\`, Studio or Blender was changed for it.*

**The owner, today:** "Training room first".

This page settles how a round now starts, in this order:
1. The red train standing at a station (the lobby).
2. The train departs and rides.
3. It arrives at the Training Centre: kits, skills, fitness and allies.
4. Everyone walks through a door into the red room.
5. The existing launch intro plays, then the arena.

Every number here is a default the lead can tune in `Config`. The launch, the server's countdown and the round's clock are not touched.

Pictures (scratch, made for this page):
- `C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave14\design-training\training_centre_plan.png`: the hall's plan.
- `C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave14\design-training\round_timeline.png`: the timeline.

---

## 0. The answer in twelve lines

1. **Two new server phases** go between today's Intermission and Countdown: `Ride` (25 s) and `Training` (90 s). Everything else in `RoundService` keeps its timing.
2. **The lobby is the red train, parked** in a station built from the owner's picture. The scenery stands still until the doors seal.
3. **The ride is 25 s, for everyone, every round.** Anyone who has ridden once this session can hold Space to skip it, and gets that time back as training time.
4. **The arrival is invisible.** In the dark of the tunnel, with the train standing still, everyone is moved to the same spot in an identical copy of the train parked at the Training Centre. The platform lamps come on and the side doors open.
5. **The Training Centre** is a hall of 220 × 150 × 36 studs. It holds archery lanes (targets at 20, 40 and 60 studs), a blade and axe circle (dummies that block, parry and strike), a spear and throwing range, a survival corner and a fitness corner. Each station has an orange mat that picks your kit and a chest that lends you that station's items.
6. **"Chests will have diff items based on such":** in the arena, one item in each crate you open comes from your kit's shelf. That item replaces one of the crate's rolls, so the crate never gives more.
7. **"Improve their physical attributes":** three permanent, capped attributes (Stamina, Strength and Fieldcraft), bought with tokens that are earned by training and playing. The largest effect is 10%. None of them changes damage, health, armour or top speed, and none is for sale.
8. **Allies are the truce the owner already approved,** chosen in the hall. Both players must agree. A group can have 2 to 4 members, depending on how many are playing. Allies see a small sage mark over each other's heads and a tick on the compass.
9. **The truce ends** on any damage between allies, at the Offering's bell, or when four contenders are left. Allies never get plinths near each other.
10. **The launch doors open 40 s before the call.** A 12-stud corridor leads to a real red room, where each player sees only themself on the disc. If everyone is already in, the call comes early.
11. **The hand-off:** at the call, the camera rises out of your own eyes, up through the hex frame, into today's opening shot. After that the shot runs exactly as it does today (22 s Full, 12 s Short).
12. **Before the Horn:** a normal round takes **2:42** from the start of the Intermission (today it takes 0:47). A lone player reaches a practice round in **at most 1:57** after joining (today 1:07).

---

## 1. What exists today (read from the code)

| Piece | Where | What it does now |
|---|---|---|
| Round state machine | `RoundService.lua` | `Lobby → Intermission (25 s; each join restarts it, never past 90 s from its start) → Countdown → Active → Ending (10 s+) → Lobby`. Contenders are picked **at the call** (`enterCountdown`): whoever played least recently goes first, at most `MaxContenders` (48 on Map 1), spread evenly round the plinths from a random offset. `practice = picked == 1`. |
| Alone on a server | `RoundService.step`, `Config.Round` | `SoloWaitTime` 30 s from joining, then the Intermission, then the Short cut: 1:07 from joining to the horn. Still alone afterwards: `PracticeIntermissionTime` 8 s. |
| The launch | `Config.Launch`, `LaunchIntroController` | Full: 22 s countdown, rise at 15.4 s. Short: 12 s, rise at 6.2 s. The red room is built from Parts **on each client** at (−12000, 600, 900): you, alone, seen from above through the hex frame, with the net at 10.6 studs. Nobody walks into it. |
| The lobby | `BlenderTemplates.buildTrainLobby`, `LS_TrainLobby_v1` (118495945857547) | Four cars (Nose, Lounge, Dining, Observation), 267.8 studs long, interior 19 wide and 10.5 high, **end doors only**. 48 spawn pads. It sits at x 8800, floor y 200, roughly z −127 to +140, kept loaded at all times (`Persistent`). |
| The view out of the train | `TrainSceneryController` | Hills, trees and poles slide past the windows **all the time** (60, 18 and 6 studs/s). There is no station and no parked state. |
| Loadout | `LoadoutStationBuilder`, `LoadoutController`, `KitService`, `LoadoutCatalog` | A rack at the front of the Lounge car. The Loadout holds a kit (Archer, Forager, Hunter, Medic, Climber), a Specialty (Fists, Short blade, Sword, Axe, Spear, Throwing, Bow, each with one skill), one general skill and three trails. The choices **lock at the call**. The kit arrives as a parcel at the round's midpoint. |
| Prize wheel, case, Armoury | `WheelBuilder` | On the front bulkhead of the Observation car. Gold only; no Robux (`Config.Economy.RobuxGold = false`). |
| Results board | `LobbyBoardBuilder` | A physical board in the Lounge car. |
| Training dummies | `CombatService`, `DummyBuilder` | Burlap R15 dummies, **practice rounds only**, during Active. A dummy guards while its attribute `Guard` is true; `_npcStrike` lets a dummy strike. No hits are accepted outside a round. |
| Allies, truces | none | Not built. `VoiceMode.md` has an allies-only whisper wired up but switched off, waiting for a `TruceService`. |
| Station, Training Centre, walk-in red room | Blender pass 2 only | The station kit is in `Train.manifest.json` (shed bay, gold fan, boards, banner, poster, guard; not uploaded). `LaunchRedRoom.glb` has 9,748 triangles, a 30 × 24 interior and the net at 20 (not uploaded). Nothing has been made for the Training Centre. |

---

## 2. The flow

### 2.1 Phases and timings

The table below covers a normal round with two or more players. Times run from the start of the Intermission. See `round_timeline.png`.

| Time | Phase (`GameState.Phase`) | What players see and do |
|---|---|---|
| 0:00 | `Intermission` (unchanged, 25 s) | **At the station.** The train is parked. Outside the left-hand windows: the platform, two rows of guards, banners and the gold fan overhead. Outside the right-hand windows: a second dark train with a red lamp, as in the owner's picture. The departure boards read "TRAIN DEPARTS 0:25 · THE TRAINING CENTRE". Everything in the train works as it does today: Loadout, wheel, results board, How to Play. Joins restart the countdown under today's fill rule (90 s at most). |
| 0:25 | `Ride` (new, `RideTime` 25 s) | **The doors seal** with a pneumatic thump, the outside sound dies, and the 52 Hz hum starts. 0:25 to 0:31: the platform slides away, speeding up from 0 to 60 studs/s. 0:31 to 0:39: country. 0:39 to 0:43: the bridge backdrop. 0:43 to 0:50: a tunnel, lamps passing more and more slowly, the brakes, the guards' boots. Players stay inside the train and can keep using the Loadout and the wheel. |
| 0:49.4 | (inside `Ride`) | **The move.** The train is dark and standing still. The server moves every character from train A to the same place in train B: `B:GetPivot() * A:GetPivot():Inverse()`. Each client moves its camera by the same transform in the same frame. A 0.4 s dark cover hides any streaming hitch. |
| 0:50 | `Training` (new, `TrainingTime` 90 s) | **Arrival.** The platform lamps come on bank by bank with a clunk (1 s). The side doors on the platform side slide open (1.2 s). The hall is through three arches, 30 studs away. The status line reads "Doors open in 0:50". |
| 1:40 | `Training`, doors open | **The launch doors open** under the big screen with a low two-tone, and the lamp over them turns red. Places are now held for this round (§2.3). The status line reads "The doors are open · the call in 0:40 · walk to the red room". |
| 2:20 | `Countdown` (unchanged) | **The call** is today's `enterCountdown`, plus the allies' plinth rule (§4.5). The launch intro starts from the real red room (§5.3). |
| 2:42 / 2:32 | `Active` | The Horn, after the Full / Short cut. |

**Ending early.** The call comes 5 s after every held contender has stood inside the red room for 3 s, and never before 30 s of training. A server where everyone is ready gets from the doors sealing to the Horn in about 25 + 35 + 22 = 82 s.

**Why 90 s of training.** It is time to try two stations and pick a kit, or to run one fitness drill and agree a truce. It is also the length of one track lap plus one archery drill plus the walk. The owner asked for a "short ride", so the ride is 25 s. That is also the time the client needs to stream the Training Centre in. The total of about 2.5 minutes is in line with the pre-round of other battle games, and every second of it can be played. If the owner finds it long, the lead sets `TrainingTime` to 60 s and nothing else changes.

**What does not change:** `Countdown` and its lengths (22 / 12 s), `LaunchAt`, `LaunchRise`, `AnnounceLast`, `MaxRoundTime` (20 min on Map 1), `Ending`, the fill rule, `StartHoldTime`, and the least-recently-played pick.

### 2.2 Alone on a server (practice)

| Time from joining | What happens |
|---|---|
| 0:00 to 0:20 | At the station, alone. "Practice in 0:30 · or wait for contenders". `SoloWaitTime` drops from 30 to 20 s, because the ride now covers the rest of the wait. |
| 0:20 to 0:30 | The Intermission (`SoloIntermissionTime` 10 s). |
| 0:30 to 0:45 | **A short ride** (`SoloRideTime` 15 s): the doors seal, the station slides away, then straight into the tunnel. It can be skipped as in §2.4. |
| 0:45 on | **Training, with the launch doors open from the start.** Walk in when you are ready: the call comes 3 s after you stand on the disc, or at 60 s (`SoloTrainingTime`). |
| Call + 12 s | The Short cut and the Horn. The practice round is today's: arena dummies, "PRACTICE ROUND". |

The longest wait is 1:57 from joining. A player who walks in after 30 s of training waits about 1:30. Still alone after the practice round, they go back to the station train, as `loadIntoLobby` does today. Then come the short Intermission (8 s), the short ride and training again.

If a second player arrives during the solo ride or training, this becomes a real round at the call (`picked == 2`, as today). If the call is less than 30 s away, it moves to 30 s, so the newcomer can step off the train and choose a kit.

### 2.3 Who goes, and edge cases

| Case | Rule |
|---|---|
| **Joins during `Intermission`** | Spawns in train A, as today. Restarts the Intermission under the fill rule. |
| **Joins during `Ride`** | Spawns in train A and rides the rest of the way. The move takes them along with everyone else. |
| **Joins during `Training`** | Spawns on platform B in front of an open door (`RequestStreamAroundAsync` first). Is a candidate at the call. |
| **Joins after the call** (Countdown, Active, Ending) | Spawns in train A at the station, as today. Can spectate. Rides with the next round. |
| **More than 48 in the hall** | When the launch doors open, the first 48 are held, least recently played first (today's order). A player who arrives later takes any free place up to 48. Those not held see "This round is full · you are first on the next train", and the launch doors stay shut for them: the door's collider is on for them only, and their client shows it closed. At the call they go back to train A under a 0.6 s fade and can spectate. |
| **Spectating** | Spectating only happens during `Active`. Waiting and fallen players are in train A, which stands parked at the station all round. The boards read "IN THE ARENA · 9 REMAIN". SPECTATE works as today. No ride runs while a round is live. |
| **The fallen and the round's end** | Unchanged: the death card, then train A. After `Ending`, everyone is in train A for the next Intermission. |
| **Leaving during Ride or Training** | No special rule. At the call, one candidate means a practice round and none means back to `Lobby`, as `enterCountdown` does today. |
| **Standing still (AFK)** | Picked at the call like everyone else, as today. They miss the red room walk-in and get today's dip to black instead (§5.3). |
| **Falling or getting stuck in the hall** | No damage from anything in the Training Centre. A body 40 studs under the hall floor is put back on platform B (today's `LobbyFallDepth` rule, applied to the hall). |
| **Reduce Motion** | The scenery stands still during the ride. A 0.6 s fade covers the station leaving and the tunnel, and the phase timings stay the same. |
| **Studio** (`FastTimers`) | `RideTime` 6, `TrainingTime` 20 and doors open at 8 s, next to today's `IntermissionTime` 6. |

### 2.4 Skipping the ride

- **Who:** anyone with the player attribute `Rode` (set at the end of their first ride this session).
- **How:** hold Space, A, or the SKIP line on touch for 0.6 s (today's launch skip hold).
- **What happens:** a 0.4 s fade, then you are standing on platform B in front of a door. You see the platform lamps lit and the train's doors open; the train is local to you until the real arrival. You can train straight away.
- **Why skipping helps:** it gives you more training time, never a shorter wait for anyone else.

### 2.5 Server shape (for the builder)

- **`RoundService`**
  - New phases `Ride` and `Training`, entered from the end of the Intermission. The order is `enterIntermission → enterRide → enterTraining → enterCountdown`.
  - `rescueStrays` also runs in the new phases.
  - The doors-open moment holds the contender list (`heldContenders`). `enterCountdown` picks from that list first, then from anyone in the hall up to the plate count.
  - New `Config.Round` keys: `RideTime` 25, `SoloRideTime` 15, `TrainingTime` 90, `SoloTrainingTime` 60, `DoorsOpenBefore` 40, `ReadyHold` 3, `ReadyLead` 5, `MinTraining` 30, `LateJoinFloor` 30, `SoloWaitTime` 20, `SoloIntermissionTime` 10.
- **`PlayerService`**
  - `loadIntoTraining(player)`: spawns on platform B.
  - Player attribute `InTraining` (true from arrival to the call). In the hall, `damage()` refuses any damage when the victim is `InTraining`.
  - `getLobbyPlayers` already counts everyone who is not in the arena, so the hall counts as waiting.
- **The move:** one server function, `RideService.arrive()`. It runs `PivotTo` on every character inside train A's bounds, then fires `RideArrive {transform}` to each client for the camera.

---

## 3. The Training Centre

### 3.1 The hall

From the owner's words "like in the movies", and from the trailer frames `trailer1_79.7s.png` and `trailer1_82.7s.png`: teal padded walls on a slant with white diagonal ribs, a blue-grey chequered floor, orange equipment, round downlights and stacked colour-bar boards. These are our own shapes and our own boards. No film names, crests or frames.

```
                         RED ROOM 30x24  (disc under the hex)
                               |  corridor 6 x 12
   +------------------- LAUNCH DOORS · big screen -------------------+
   | SURVIVAL CORNER    |                        | SPEAR & THROWING   |
   | fire, snares,      |    running track       | boards 10..50      |
   | plants, trough     |   +--------------+     |--------------------|
   |--------------------|   |  THE FLOOR   |     | ARCHERY LANES (6)  |
   | BLADE & AXE CIRCLE |   | benches, kit |     |  targets 60        |
   | ring r14, 4 dummies|   | board, allies|     |  targets 40        |
   |--------------------|   | obstacle run |     |  targets 20        |
   | FITNESS CORNER     |   +--------------+     |  shooting line     |
   | wall, bikes, weights                        |                    |
   +----------------- three arches -------------------------------------+
     PLATFORM B (arrival)          the red train, copy B
```

- **Size:** 220 × 150 studs, 36 high. The hall's own coordinates: x −110 to 110 (east positive), z −75 to 75 (north negative). Floor centre at **place (8800, 200, 3000)**.
- **Bays:**
  - Survival corner (NW): x −110 to −40, z −75 to −20.
  - Blade and axe circle (W): x −110 to −40, z −20 to 30. The ring's centre is at (−75, 7.5).
  - Fitness corner (SW): x −110 to −40, z 30 to 75.
  - Spear and throwing range (NE): x 40 to 110, z −75 to −35.
  - Archery lanes (E): x 40 to 110, z −35 to 75.
  - The floor: x −40 to 40, with the running track round it.
- **The launch doors:** at (0, −75), under the big screen.
- **Arrival:** three arches at z 75 from platform B.
- **Walks:** from a train door to the floor centre, about 30 studs (2.3 s at walk speed 13). From the floor centre to the disc, about 100 studs (8 s walking, 5 s sprinting).
- **Light:** cool-neutral downlights, ambient about (64, 72, 76), no sun, at most two lights casting shadows. Matte everywhere (ArtStyle). **Orange marks what you can use** (ArtStyle rule 9): mats, chests, racks, bikes, the climbing wall's holds. Nothing else in the hall is orange.
- **The big screen** over the launch doors reads "DOORS OPEN IN 0:50", then "THE CALL IN 0:40", then the names of those held. It is a SurfaceGui, like the results board.

### 3.2 The stations

| Station | Kit picked by its mat | What its chest lends you | Specialty and skill to try | The drill (step on the start line) | Pass |
|---|---|---|---|---|---|
| **Archery lanes** (6 lanes, 8 wide) | Archer | Short Bow and 12 arrows, refilled | Bow: Piercing Shot. General: Steady Hands | Pop-up targets at **20, 40 and 60 studs**, each up for 4 s; the head ring counts double. 60 is the bow's on-target limit from the owner's bow notes. | 4 hits from 6 targets in 30 s |
| **Blade and axe circle** (padded ring, r 14) | none: you keep your kit, and the circle sets your Specialty | Knife, Machete, Hatchet, Sword, Twin-Bit Axe | Fists: Head Kick. Short blade: Chained Strikes. Sword: Running Cut. Axe: Whirl | Four dummies (§3.3): land 8 clean hits on the blocker and parrier, and block or parry 2 of the striker's blows | All of it in 25 s |
| **Spear and throwing range** | Hunter | Spear and 6 throwing knives | Spear: Vault Kick. Throwing: Ricochet | Boards at 10, 20, 30, 40 and 50 studs | 3 hits from 5 throws at 20 or more |
| **Survival corner** | Forager (plants mat), Medic (bandage mat) | Firewood, an empty bottle, 2 bandages, 2 herbs | General: Second Wind, Quiet Step | Light the fire (hold E for 2 s at the pit); fill the bottle at the trough; sort six plants into sound and spoiled (never poisonous: the Larder rule); bandage the dummy | All four in 45 s |
| **Fitness corner** | Climber (the wall's mat) | Climbing pick | General: Sprint Burst, Brace | Climbing wall (24 high, Climbable): reach the top. Bikes: hold the gauge in the green for 20 s. Weights: 10 lifts on the beat. | Top in under 8 s; 20 s in the green; 10 clean lifts |
| **Track and obstacle run** (round the floor) | none | none | none | One lap of the track (300 studs). The obstacle run inside it: vault box, mantle wall, slide bar. | Lap in under 19 s (9 s of sprint at 21, then walk at 13); run in under 12 s |

**Rules in the hall:**
- **Mats:** step onto an orange mat and its kit is yours. A quiet line says what that means, for example "ARCHER · crates lean to arrows · kit lands mid-round". The Loadout rack, the KIT chip and the kit board on the floor do the same thing, for phones and gamepads. Picks stay free until the call (today's lock, unchanged).
- **Borrowed items** come from the station's chest (hold E 0.6 s, like a crate) and stay in that station's bay. Leave the bay and they vanish with a soft clunk; they also vanish at the launch doors and at the call. They are never your round's items.
- **Skills in the hall:** your Specialty's skill and your general skill work in the hall with **cooldowns × 0.25**, so you can try them several times in 90 s.
- **Nobody can damage a player in the hall.** Arrows and throws pass through people on the ranges. Hits count on targets and dummies only. `CombatService` accepts a hit on a `TrainingDummy` outside `Active` only when the attacker is `InTraining`.
- **Drill results** show as one thin line ("ARCHERY · 5 / 6 · passed"). Passing pays a token (§3.5).

### 3.3 Dummies that block and parry

These are the existing `DummyBuilder` dummies with a stance. Their Blender mesh comes later (§6), keeping the R15 names. The stance uses the `Guard` attribute and `_npcStrike` from Combat v3.

| Dummy | What it does | What you learn |
|---|---|---|
| Target | Stands and wobbles when hit. Heals after `DummyRegenDelay` (4 s). | Reach and swing timing |
| Blocker | Raises its guard for 1.5 s every 3 s, and shows it 0.3 s early by lifting its padded arm | Wait out a block, or break it with a heavy |
| Parrier | Guards inside your wind-up 40% of the time, with today's parry window. A parried swing staggers you, with no damage. | Mixing quick and heavy swings |
| Striker | A slow overhead every 4 s: 0.9 s of wind-up, then `_npcStrike`. A hit staggers you and takes no health (`InTraining`). | Blocking, the perfect parry, the dodge roll |

The arena's practice-round dummies are unchanged.

### 3.4 "Chests will have diff items based on such": what a kit does in the arena

The kit already brings its parcel at the midpoint (`KitService`, unchanged). The training choice also leans the crates: **one item in each crate you open comes from your kit's shelf.** `LootService` already knows who opens each crate.

| Kit | Tier 1 crate | Tier 2 crate | Tier 3 crate (by the Horn) |
|---|---|---|---|
| Archer | 3 to 5 arrows | 5 to 8 arrows, or 1 time in 4 a Short Bow if the round's cap allows | 8 to 12 arrows |
| Forager | 2 apples or 3 berries | A water bottle or a knife | A ration or a machete |
| Hunter | 1 or 2 throwing knives | A spear, or 2 or 3 throwing knives | A spear, or 3 or 4 throwing knives |
| Medic | A bandage, or 2 herbs | 2 bandages, or a water bottle | A medkit |
| Climber | 3 berries, or firewood | A climbing pick (once per round per player), or a leather vest | Padded armour, or a ration |

**Rules for the lean:**
- The pick **replaces** one of the crate's rolls, so a crate never gives more. Only crates you open lean.
- These never lean: ground items, the Horn's racks in plain view, the Offering's crates, sponsor parcels, kit parcels.
- **The caps hold:** the Recurve Bow budget (3 or 4 per round) never comes from a lean. The Short Bow obeys `ItemDefs.RoundCaps` (6); if a cap blocks a pick, the next line on the shelf is used.
- **Size of the effect:** noticeable, not decisive. An Archer who opens four tier-1 crates finds about four more lots of arrows than a player who chose no station.

### 3.5 The fitness corner: "improve their physical attributes"

**The decision: permanent, small, capped ranks.** No per-session boost. The owner's design direction (3.2 and 3.3) describes exactly this:
- "Completing training activities awards players progression tokens or training coins."
- "Attribute improvements should have defined maximums, and the differences between lower-level and higher-level players should remain relatively modest."
- "should not become so powerful that a new player has no chance."

A per-session boost would turn every pre-round into treadmill time, when it should be time for kits, skills and allies. Ranks that build over days reward training without forcing it.

| Attribute | Trained at | At rank 5 (each rank gives a fifth) |
|---|---|---|
| **Stamina** | Track, obstacle run, bikes | Sprint drain × 0.91 (a full sprint lasts 9.1 → 10.0 s); recovery × 1.10 |
| **Strength** | Weights, climbing wall | Stamina per melee swing × 0.85; climb speed × 1.10 (5.5 → 6.05); climb drain × 0.90 |
| **Fieldcraft** | Survival corner | Hunger and thirst drain × 0.92 (the owner's "improving hunger or thirst management") |

**Tokens:**
- 1 per drill passed, at most 8 a day.
- 1 per real round played, plus 1 for a top-5 finish, at most 6 a day.
- 1 extra the first time you ever pass each drill.
- Private servers and events pay none.

**Prices:** the five ranks cost 2, 4, 6, 8 and 10 tokens, so 30 per attribute and 90 for all three. That is about eight days of steady play. Every spend asks you to confirm. Spending happens at the kit board.

**What keeps it fair:**
- Nothing changes damage, health, armour, top speed or how many hits it takes to down anyone.
- Ranks show on the death card. They are off in private servers and events.

**No Robux.** The owner's direction 3.3 allows token packs later, but only to reach the same cap faster. Nothing is sold now: no Robux products, and `RobuxGold` is off. `RandomItemRules` section 6 covers stat items if packs ever come.

**Saved data:** `TrainingTokens`, `StaminaRank`, `StrengthRank`, `FieldcraftRank`, `DrillsPassed` (a bit set), and `TokensToday` with its date.

---

## 4. Allies

The owner approved this rule on 12 Nov ("Yes (Recommended)"): a temporary truce that "ends on any damage, at the Offering's bell, or when four players are left". On 18 Nov they asked for players to "choose their allies" in the prep room. Allies are that truce, agreed before the round instead of by gesture inside it. There is always exactly one winner.

### 4.1 Choosing

- **Walk up and ask:** look at a player within 10 studs and hold **T** for 0.4 s (gamepad: D-pad up). On touch, a thin "Ally" line appears beside the crosshair when you look at someone within 10 studs; tap it. This is the Truce from the gesture wheel planned in PlayabilityPlan B12, in the same key.
- **The answer:** they see one line for 15 s: "Wren offers a truce · hold T to accept". Silence or walking away is a no, and the asker sees "No answer". A refusal is never announced.
- **The quiet list:** the Loadout gets an ALLIES row listing the players in the hall, each with "offer" or "accept". This is for phones, gamepads and anyone shy. No boxes, just text and lines (UI style A, Quiet).
- **Both must agree, every time.** A group grows when a member and a newcomer accept each other. The other members get a line ("Wren joins your truce") and can leave by holding T on the group's line.
- **Changes are free until the call.** At the call the groups lock. In the arena the gesture truce from B12 still works between two contenders, under the same caps and end rules, but never with someone who broke a truce with you this round.

### 4.2 Group size

The cap goes by how many players are in the hall when the group forms. This means a group can never be a large share of a small round.

| Players in the hall | Largest group |
|---|---|
| 4 or fewer | No truces ("Truces need five or more contenders"). The four-left rule would end them at the Horn anyway. |
| 5 to 11 | 2 |
| 12 to 23 | 3 |
| 24 or more | 4 (the owner's default: up to three allies) |

### 4.3 How allies are shown

- **Over the head:** a small sage double bar (a new `Theme.Colors.Ally`, about #9DBFAE; one colour, one meaning, B10). It sits 1.2 studs above the head at a fixed 14 px on screen, with no name and no health bar. It shows through walls within 60 studs, so nobody hits an ally by mistake, and in line of sight out to 300.
- **On the compass:** a short sage tick with the ally's initial, at their bearing.
- **In the hall:** the same mark as soon as the group forms. The quiet list shows the group.
- **Voice:** the allies-only whisper in `VoiceMode.md` (hold V, 18 studs) switches on once `TruceService` calls `VoiceService.setAllies`.

### 4.4 The truce rules (as approved)

- **Nothing is shared:** no shared loot, no shared win, no shared placement. Kill credit is normal.
- **Damage is never blocked.** The truce is a promise, not a shield.
- **It ends on any damage between allies,** whatever the source (melee, arrows, throws, skills). The attacker leaves the group for everyone in it. The one who was hit sees "Wren broke the truce". If two or more members remain, they stay allied.
- **It ends for everyone at the Offering's bell** (785 s into a Map 1 round), **or when four contenders are left** (`AliveCount ≤ 4`).
- **A member who falls or leaves** simply drops out.
- **When a truce ends:** one soft low bell, one quiet line ("The truce is over"), the marks fade over 2 s and the compass ticks go.

### 4.5 No neighbouring plinths

At the call, `enterCountdown` places group members at least **360 / (2 × group size) degrees** apart on the plinth ring: 90° for a pair, 60° for three, 45° for four. On Map 1's full ring of 48, that is 12, 8 or 6 plinths apart, which at radius 150 means 236, 157 or 118 studs of arc. Within those limits everyone is placed at random. This way a group is never a bloc at the Horn against players who came alone.

---

## 5. The red room entrance

### 5.1 The door

- **Where:** a pair of steel doors, 8 wide and 14 high, with oxblood panels and a red lamp over them, at the north wall under the big screen. Two of our own guards in white armour stand beside it (the station's guard model).
- **Opening:** shut until 40 s before the call. Then a low two-tone sounds, the lamp turns red, and the doors slide open in 1.2 s.
- **Who may pass:** only held contenders. Anyone else sees the doors closed (§2.3).
- **At the threshold,** borrowed items go back with a clunk.

### 5.2 The walk

- **The corridor:** 6 wide, 9 high, 12 long. Oxblood walls, red light strips at floor level, and the red room's blue-grey steel floor with white stripes.
- **The room:** the corridor opens onto the back walkway of the red room. This is the Blender `LaunchRedRoom`: a 30 × 24 interior with the net at 20, the deck, the black grates, the red rail with its two lamps, and the dusty-rose disc under the teal hex frame. Its centre is at place (8800, 200, 2901).
- **"Your own room":** inside the room and corridor, each client hides every other character (`LocalTransparencyModifier` 1, no name tag), and characters there are in a collision group that does not collide with itself. Each player stands alone on the same disc, as each contender stands alone in their own room in the owner's pictures (`launch_1_red_room_net_a.png` and `_b.png`).
- **Walk times:** from the doors to the disc is about 24 studs (2 s). A line at the entry reads "Stand on the disc". On the disc, a faint "Ready" appears, which counts toward the early call (§2.1).

### 5.3 The hand-off into the existing launch

- **The server:** at the call, today's `enterCountdown` runs unchanged: the pick, `prepareContender` on the plinth, `launchCut`, `LaunchCallAt` and `LaunchAt`.
- **The set:** when the room exists in the world, `LaunchIntroController.Set` uses it as `set.red` (its pivot is the origin, its disc is the lift) instead of building the Part red room at (−12000, 600, 900). Set's header already plans for this: "The Blender set can replace this one later behind the same API". The pole hall stays where it is.
- **A player standing in the room:** the shot's first beat (`look`: 1.0 s Full, 0.8 s Short) becomes the camera rising **out of your own eyes, straight up the shaft, through the hex frame,** to today's overhead framing. Your stand-in is where you stand: on the disc, or placed on it if you were off it. The server moves your real character to the plinth underneath this, as it does today. From there the shot is today's: the lift, the dip, the glass cases (Full), the rise, first person, the glare.
- **A player outside the room:** stragglers, AFK players, late joiners. Today's opening: a short dip to black into the red room shot.
- **The red room's height:** the walk-in room has the net at 20 studs, where the Part set has it at 10.6. The overhead camera reads `set.red.hexY`, so it moves up by itself. Check in Studio that the stand-in still fills the hex frame; if it does not, narrow the opening shot's field of view (no change in timing).
- **Untouched:** the Full and Short lengths, `LaunchAt`, the plinth hand-off, the glare, the skip.

---

## 6. The set list for Blender

**How they are built:** the same way as the existing sets (`art\README.md`): seeded generators in `art\blender`, 1 unit = 1 stud, a manifest per set in `art\manifests`, colliders and markers as attachments, built in game by a `BlenderTemplates.build*` function like `buildTrainLobby`.

**The look:** "Roblox with good graphics", semi-real, matte, realistic shaders on simple shapes. Palette textures, not one texture per object. The pass-2 train and station export still carries 130 textures in 33 sets; pack them into palettes before upload. Uploads of today's Blender models for this game are approved by the owner.

### 6.1 Where everything sits

| Set | Place | Why there |
|---|---|---|
| Station A (the lobby's station) | Around the existing train: train at x 8800, z −127 to 140, floor y 200. The second track is at x 8838, with a guards' aisle from x 8812 to 8826 between the trains. | The train lobby stays where it is. |
| Ride scenery | The existing `Lobby.Scenery` band, plus the station's platform pieces and a tunnel band (client-moved) | Only `TrainSceneryController` moves them |
| Train copy B, platform B, the Training Centre | Hall floor centre (8800, 200, 3000). Platform B at z 3083 to 3091. Train B's centre line at z 3097.5, running east-west. | 3,000 studs from the lobby and about 9,300 from the Horn: out of earshot (VoiceMode) and streamed separately |
| Corridor and red room | North of the hall: corridor z 2913 to 2925, room z 2889 to 2913, disc at (8800, 200, 2901) | Through the launch doors |
| Pole hall and glass cases | Unchanged: client-built at (−12000, 600, 0) | Seen only in the shot |

**Streaming:** the station and train A stay `Persistent`, as today. The hall, train B and the red room are one model with normal streaming. Each rider's client asks for the hall in the last 10 s of the ride (`RequestStreamAroundAsync` on the server for each rider).

### 6.2 What to make, with triangle budgets

"Unique" counts each mesh once. "Drawn" counts every copy in view. The aim is **at most about 80k triangles drawn in any view** and 30 fps on a 3 GB phone (PlayabilityPlan's test device).

| # | Set | Contents | Reuse | Unique | Drawn |
|---|---|---|---|---|---|
| 1 | **Station A, from the owner's picture** (`train_station_owner_frame.png`) | A tall, narrow glazed shed in 24-stud bays (12 bays cover the 268-stud train). Platform floor. A central aisle with two rows of guards in white armour. A banner on each pillar. A departure board over each track. The gold fan of ten blades overhead. Tall posters (our own). The second train beside ours: dark lacquer, a rounded nose, one red-orange lamp. | Pass-2 station kit: ShedBay 2,052, FloorBay 340, ShedEnd 724, Sunburst 2,172, Board 644, Banner 242, Poster 107, Guard 650. Train_NoseCar 4,158 and BodyCar 2,796 for the second train. | 16k | 60k (12 bays, 12 guards, 3 boards, 8 banners, the other train) |
| 2 | **The ride's new pieces** | A tunnel bay (24 studs: dark walls, a cable run, a lamp every bay), a signal and an end portal. The platform's pillars, guards and boards that slide away as the train leaves. | The scenery band and BridgeBackdrop (1,692) from pass 2 | 2k | 8k |
| 3 | **Train changes** | Sliding **side doors** for the Lounge and Dining cars, two per side per car, 6 × 8, about 150 triangles a leaf. They open on the platform side at B and stay shut at A. Edit `train_lobby.py`, re-export, rebuild both copies. | The whole train mesh; copy B is the same asset | 1k | 10k (copy B) |
| 4 | **Platform B** | A dark platform, 290 long, with lamp banks that switch on. Tunnel mouths at both ends. Three arches up into the hall. | Tunnel bay from #2 | 5k | 10k |
| 5 | **The hall's shell** | Teal padded panels on a slant (#4e7076) with white diagonal ribs. A chequered carpet in a two-tone palette (#68747a / #969ea2). A coffered ceiling with round downlights. Stacked colour-bar boards (our own). The big screen's frame. The north wall's door frame. | none | 14k | 20k |
| 6 | **Archery lanes** | Lane dividers and the shooting-line rail. Pop-up targets on orange stands (about 260 each, 18 of them). The backstop net. A turning hoop wheel (later). | none | 3k | 8k |
| 7 | **Blade and axe circle** | A padded ring of r 14. **A Blender training dummy** (about 1,200; R15 part names kept, to replace `DummyBuilder`'s parts). A spinning post. An orange weapon cart like the trailer's trolley. | The dummy is reused at the survival corner and in practice rounds | 3.5k | 7k |
| 8 | **Spear and throwing range** | Throwing boards (5), orange spear racks (2), hay bales as a backstop | none | 1.5k | 3k |
| 9 | **Survival corner** | A fire pit, snare stakes (3), a plant table with 6 pots, a trough | CookFire from `LS_Creatures_v1` | 2k | 3.5k |
| 10 | **Fitness corner and track** | A climbing wall, 30 × 24, with orange holds (tag `Climbable`). A weight rack, bench and plates. 4 bikes with orange frames. A rope. The track's lane painted into the floor texture. Vault box, mantle wall and slide bar. | none | 4.5k | 6k |
| 11 | **Station chests and mats** | One chest mesh with an orange trim (about 350, 5 copies). Flat mats. | none | 0.5k | 2k |
| 12 | **The floor (prep area)** | Benches (8). The kit board (kits, the ranks and the token count). | none | 1.5k | 2.5k |
| 13 | **The launch doors and corridor** | Door leaves and frame, the red lamp, the corridor shell with red strips | Guard from #1 | 2.5k | 3.5k |
| 14 | **The red room, walk-in** | Pass-2 `LaunchRedRoom.glb`, with an entry cut into the back walkway and colliders on the deck, stairs and rail | Pass 2 as is | 0 new (9,748) | 9.7k, behind the doors |
| | **The hall in one view** (#4 to #13 plus train B) | | | ~41k new | ~70k |

**Build order inside the art** ("Training room first"):
1. **#5 to #12 as a Part blockout** in Studio, so the stations can be played this week.
2. **Then the Blender hall** (#5 to #13), approved in game.
3. **#3 and #4** (side doors, platform B).
4. **#1 and #2** (station and ride).
5. **#14:** the red room, once the walk-in is wired.

---

## 7. What gets built, in order

| Step | Work | Files | Done when |
|---|---|---|---|
| 1 | **The hall as a Part blockout,** at the place in §6.1, with the five stations, mats, chests and the existing dummies. Reached for now with a test command. | New `WorldGen/TrainingCentreBuilder.lua` | You can walk every station in Studio |
| 2 | **The training context:** `InTraining`; borrowed items; drills; hits on dummies outside `Active`; no player damage; skills at × 0.25 cooldown | New `TrainingService`; `CombatService` (one gate); `InventoryService` (borrowed items); new `TrainingController` | The four dummies block, parry and strike; each drill passes and fails as written |
| 3 | **The phases:** `Ride` and `Training`; the move; the doors; held places; early call; the solo path | `RoundService`, `PlayerService`, `Config.Round`, new `RideService`; `TrainSceneryController` gets parked, departing, riding and tunnel states; `LobbyController` gets the new status lines | A full round from the station to the Horn in 2:42; 1:57 alone; launch timings unchanged (logged `LaunchCallAt` and `LaunchAt` match today) |
| 4 | **The red room walk-in and hand-off** | `LaunchIntroController` and `Set` (a world `set.red`, the eyes-up opening, hiding others in the room) | The shot starts from where you stand, at both cuts, with skip, with Reduce Motion and with shaders off |
| 5 | **Allies** | New `TruceService` and `TruceController`; `HUDController` (mark and compass tick); `RoundService.enterCountdown` (spacing); `VoiceService.setAllies` | Offer, accept, leave and list work; the three end rules fire; spacing holds over 20 simulated calls |
| 6 | **The crate lean** | `LootService` (roll at open), `Kits.Lean` table | Over 20 simulated rounds, the bow caps hold and the lean never adds an item |
| 7 | **Tokens and ranks** | `DataService` keys; the kit board | Daily caps hold; rank 5 numbers match §3.5; nothing touches damage |
| 8 | **The Blender sets,** #5 to #14 then #1 to #4 | `art\blender\training_centre.py` (new), `train_lobby.py`, `train_sotr.py` (station), `BlenderTemplates.buildTrainingCentre` / `buildStation` | Approved in game, under the budgets |

---

## 8. Defaults the lead can tell the owner in one line each (no need to ask)

- **The prep room and the training room are one place,** the Training Centre. The owner's own words send the train to both.
- **The train rides every round, for 25 s.** Anyone who has ridden it can skip, and gets more training time.
- **Training lasts 90 s.** The launch doors open 40 s before the call, and the call comes early once everyone is in. From the station to the Horn is about 2.5 minutes.
- **Allies are your truce,** chosen in the hall: both agree, groups of up to 4 (fewer in small rounds), never on neighbouring plinths, one winner always.
- **Training gives small permanent ranks** in Stamina, Strength and Fieldcraft (at most 10%), from tokens earned by playing. There are no damage bonuses and nothing is for sale.

## 9. Where this departs from earlier pages

- **`TwoArenas.md` 5.1:** the ride was for the first session only, about 40 to 60 s, with a walk through seven cars. Here it is **every round, 25 s, inside the four-car train that exists**. That follows the owner's 18 Nov sentence, where the train is the way to the prep room. The seven-car walk-through and its beats (`TRIBUTE` spec section 9) stay as later work for the cars the owner described.
- **`TwoArenas.md` 5.3:** the Training Centre was where everyone waits between rounds. Here **the station train is the lobby** (the owner's order of 18 Nov), and the hall is used before each round.
- **`TwoArenas.md` 5.3 kits:** it had four kits with "knacks". Here the five kits that exist are kept (`Shared.Kits`) and the existing Specialties and skills (`LoadoutCatalog`) are used. No knack is added.
- **`TwoArenas.md` 5.3 ranks:** it had two attributes. Here there are three, adding Fieldcraft for the owner's "hunger or thirst management".
- **`LaunchIntroController.Set`:** its red room is lower (net at 10.6) than Blender's (20). The walk-in room uses Blender's, so check the framing (§5.3).

## Sources

- **The owner's words:** `docs\design\OwnerSpecs_WeaponsLobbyTrain_2026-11-18.md` sections 3 to 5 and 8; `docs\design\owner\GameDesignDirection_2026-11-14.md` sections 3.2 and 3.3; PlayabilityPlan B12 (the truce gesture); `docs\handoff\OwnerRequests.md` (Truces: "Yes").
- **Their pictures:** `C:\Users\USER\OneDrive\Documents\LastStanding\References\owner\train_station_owner_frame.png`, `launch_1_red_room_net_b.png`; the trailer frames `trailer1_79.7s.png` and `trailer1_82.7s.png` (training hall), `trailer2_33.4s.png` (train and guard).
- **Code:** `RoundService.lua`, `PlayerService.lua`, `Config.lua` (`Round`, `Launch`, `Kits`), `KitService.lua`, `Kits.lua`, `LoadoutCatalog.lua`, `CombatService.lua` (dummies), `DummyBuilder.lua`, `BlenderTemplates.lua` / `BlenderData.lua` (the train lobby), `TrainSceneryController.lua`, `LoadoutStationBuilder.lua`, `WheelBuilder.lua`, `LaunchIntroController\init.lua` and `Set.lua`, `LootService.lua`, `ArenaLayout.lua`.
- **Art:** `art\manifests\TrainLobby.manifest.json` (10,040 triangles, 267.8 long), `Train.manifest.json` (the station kit), `Launch.manifest.json` (the red room, 9,748).
