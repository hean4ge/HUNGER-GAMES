# What the owner specified: weapons, lobby, train, prep room, the room, and the launch change

*Scope agent, 18 Nov 2026. Read-only work: nothing in the repo, Studio or Blender was changed.*

## How to read this

- **Quotes are the owner's own words, typos included.** They contain the films' terms (place names, guard names). Those stay in documents only; the standing decision is our own names inside the game (OwnerRequests.md section 2).
- **Dates are UTC, from the session transcript.** The PC runs at UTC+6. OwnerRequests.md files the messages of 15 Nov 01:10 to 02:31 UTC under "14 Nov", and the two design documents carry "2026-11-14" in their file names. They are the same messages.
- **prompts.md stops at 15 Nov 12:04 UTC.** It is missing eight later messages of 15 Nov (zoom, varied swings, "vault the map", "robloxy" hands, "smartass"). I re-ran the extractor on the main session; the full list is in `C:\Users\USER\AppData\Local\Temp\claude\160badb4bb8c277a\11b358ff-9bed-48e1-9783-158702fa3779\scratchpad\wave4\scope\prompts_full\prompts.md`.
- **The owner's pictures are not in `docs\design\owner`.** They are in `C:\Users\USER\OneDrive\Documents\LastStanding\References\owner\` (8 files). I viewed the five launch frames and the station frame.
- **Status.md is out of date** (14 Nov, the forest arena). The code in `src\` and OwnerRequests.md are current.

## The owner's order

Today's message (18 Nov 08:09 UTC) gives the road into a round in this order:

> "when are we going to work on the weapons and starting lobby and the train that taakes them to the prep room before the arena where they get to choose their allies and enter the room (before the transition animation to the arena)"

1. Weapons (and fighting).
2. The starting lobby.
3. The train, which takes players from the lobby to the prep room.
4. The prep room, where they choose allies.
5. "the room" they enter.
6. The transition animation (the launch), then the arena.

Their TRIBUTE spec agrees on weapons before the train (15 Nov 01:10 UTC): "Build order is at the bottom; do not let the model start with the train." and "Build the arena combat loop before the train. The train is the reward for a system that already works."

**One thing that must not be dropped silently.** Their design direction (15 Nov 01:10 UTC, section 9) puts two steps before combat: "2. Player interaction: Implement movement, climbing, hunting, resource collection, inventory and basic survival." and "3. Animals and environmental events". Neither is built (tree climbing is partial; no wildlife, hunting or events beyond the Feast and the border). Today's message moves weapons, lobby and train ahead of them. The lead should say so to the owner in one line, so it is their choice and not ours.

---

## 1. Weapons and fighting

### What the owner said

| Date (UTC) | Their words |
|---|---|
| 11 Nov 00:59 | "the idea is a hunger games game - first person - good motion physics etc" |
| 11 Nov 05:50 | "lets work on shaders shading etc and also combat physics at some point" |
| 11 Nov 06:17 | "btw bow animations - doesnt let you see when your shooting somebody" |
| 11 Nov 14:52 | "fix the bow and arrow aiming mechanism i cant even see where im shooting" |
| 11 Nov 15:05 (pasted notes) | "Weapons: Bows, knives, spears, axes." · "Protection: Armour, protective clothing." · "Traps: Snares, tripwires and improvised traps." · "Special equipment: Blow darts, technical equipment and rare tools." · "Special arrow types." · "These should feel like equipment from Panem, not fantasy magic." |
| 12 Nov 14:22 | "dont make the arrows dissapear and make them able to pick up after they are shot" |
| 12 Nov 14:55 | "also weapon list needs to be improved and game design - what the objectives are etc make it intuitive and inspired from the movie" |
| 12 Nov 16:41, question card | Asked "Fighting: should attacks have visible wind-ups, a quick and a heavy attack, and a simple block with a perfect-block window?", they answered: **"we will focus on attacks and battle manaeuvouring later remind me"** |
| 12 Nov 16:41, same card | Asked "The bow: make it a rarer prize (3–4 per round instead of about 13), with a 90-damage headshot, and arrows that land exactly on the crosshair only within 60 studs?", they answered: **"yes and make the distance and drawing more accurate but again we will deal with weapons and fighting later"** |
| 12 Nov 16:41, same card | Asked "Truces: may two players agree a temporary truce with a gesture? It ends on any damage, at the Offering's bell, or when four players are left.", they answered: **"Yes (Recommended)"** |
| 15 Nov 01:15 | "also the hand shouldnt always be in a punching position only when you.re punching should it be like that" |
| 15 Nov 12:12 | "and sword hitting, axe chopping etc shouldnt be only one animation be a little dynamic" |

**From the TRIBUTE spec (15 Nov 01:10 UTC; `docs\design\owner\TributeSpec_BloodAndMovement_2026-11-14.md`).** These are the sentences on fighting that do not depend on blood or severing:

- Pillars (line 7 on): "Weight over speed. Every animation and physics impulse reads as mass. Nobody in this game moves like a Roblox default avatar."
- Hitboxes (line 36 on): "Hitboxes are slightly larger than the mesh (0.15 stud inflation) so combat feels generous, and overlap order is explicit so a hit never double-registers." Priority, first match wins: Head, UpperTorso, LowerTorso, UpperArm L/R, UpperLeg L/R, LowerArm L/R, LowerLeg L/R, Hand L/R, Foot L/R.
- The weapons the spec names, with its per-hit values: "Knife slash 1", "Knife stab 1.5", "Machete 1.5", "Spear thrust 2", "Arrow, >60 studs/s 3", "Arrow, <60 studs/s 1", "Arrow, head 3 instant kill".
- The bow: "the bow's draw time and the target's distance both matter. A snap shot at range won't take an arm; a full draw at 15 studs will."
- Knockback (line 105 on): "Impulse-based, never CFrame-based. Server applies AssemblyLinearVelocity, client predicts, server reconciles." · "massModifier by region: Head 1.4, Torso 1.0, Limbs 0.7. A 60 kg character takes ~18 studs/s from a knife and ~34 from a machete. Decay 12 studs/s², so a knife shove costs about 1.5 studs of ground."
- Stagger and hit-stop: "Arrows add a stagger: 0.4s where input is ignored, camera jolts 6° along the impact vector, and a HitStop freezes both animations for 3 frames (0.05s). Heavy weapons add 0.7s" · "Directional stagger animations per quadrant — the character steps back with the correct foot and rotates the torso into the hit, never a generic flinch."
- Screen shake on a heavy hit: "0.25 magnitude for 0.2s on the attacker, 0.4 for 0.3s on the victim" (written for severing).
- Movement (line 114 on): "Roblox defaults are floaty. Replace them." Walk 12, Run 20, Sprint 26 studs/s with 8 s stamina, Crouch 5, ground accel 45, decel 60, air control 0.35, turn cap 9 rad/s on ground and 4 in air, momentum carry 0.85. "0.12s of acceleration lag before the character visibly commits, 4° of lean into strafe and 6° into sprint, footstep IK planting on slopes so feet don't skate, a 0.3s recovery pause after landing from any fall over 8 studs, and a 0.15s startup on every dodge."
- Animations (line 136): "Combat: slash_L, slash_R, stab, overhead, block, parry, dodge_roll, bow_nock, bow_draw, bow_hold, bow_release." · "Reactions override the upper body layer only; legs keep walking through a knife hit." · "reactions are additive at 0.08s in, 0.25s out."
- Cost limits: "Hitbox raycasts: 3 per swing, 1 per arrow, RaycastParams filtered to a character whitelist".
- Build order (line 183 on): rig and collision groups; region hitboxes and wound counter; wound decals; severing; "Knockback, stagger, hitstop"; "Movement physics rewrite"; "Full animation set and blend rules"; the train; "Audio pass"; "Balance and tuning".

**From the design direction (15 Nov 01:10 UTC; `docs\design\owner\GameDesignDirection_2026-11-14.md`):**

- Section 2.1: "Inside and around the Cornucopia are weapons, backpacks, food, water and other survival equipment." · "There should be meaningful differences between the available equipment. Some items should be immediately useful, while others should require players to take greater risks to obtain them." · "The opening should feel tense and unpredictable, rather than like an ordinary countdown followed by a conventional team fight."
- Section 4: "Equipment should feel like physical objects that belong in the world." · "I would avoid introducing an enormous inventory of artificial items or hundreds of unnecessary equipment variations." · "The focus should be on a smaller collection of useful objects, each with a clear purpose."
- Section 4.1, weapons: "Bows and arrows. Knives. Axes. Spears. Other appropriate weapons." Special equipment: "Traps. Special ammunition. Rare tools."
- Section 4.2: "rarity should primarily represent availability, quality and usefulness, rather than introducing fantasy-style magical properties." · "a particularly rare bow might have superior construction or durability, rather than inexplicably dealing magical damage."
- Section 9: "4. Combat and match structure: Implement weapons, damage, elimination, starting platforms and the overall match lifecycle."

**What their later words remove.** 18 Nov 05:16 UTC: "after you're done with everything publish the game for all ages". The lead recorded this as no blood and no wounds. So the spec's custom severable rig, wound stages, blood effects, severing and limb loss (sections 2, 4, 5 and the wound counter of 3) are not built. The owner has never been asked to confirm that trade in plain words (see Decisions).

### What exists today

- **In the game** (`src\ReplicatedStorage\Shared\ItemDefs.lua`): fists and nine weapons.

  | Weapon | Rarity | Damage | Swing every | Reach |
  |---|---|---|---|---|
  | Hunting Knife | Common | 22 | 0.45 s | 6 |
  | Machete | Uncommon | 32 | 0.70 s | 7 |
  | Hatchet | Uncommon | 36 | 0.80 s | 6.5 |
  | Spear | Rare | 30 (thrown 60) | 0.85 s | 9.5 |
  | Mace | Rare | 46 | 1.10 s | 7 |
  | Arena Sword | Epic | 40 | 0.75 s | 8 |
  | Recurve Bow | Rare | 14 to 50 by draw, head ×1.8 (90) | 0.9 s draw | arrows at 90 to 240 studs/s |
  | Throwing Knife | Uncommon | 28 | 0.5 s | thrown at 160 studs/s |
  | Arrow | Common | ammunition, stack 24 | | |

  Also two armours (Leather Vest ×0.85, Padded Armor ×0.72), three healing items, four foods, the bottle.
- **Built and working:** one click, one strike per swing; a swing lands only if it hit on the attacker's screen, and the server checks reach; arrows, throwing knives and thrown spears stay where they land and can be picked up; the bow keeps the crosshair clear; thrown weapons land on the crosshair; 3 to 4 different swings per weapon, and other players see them (`Config.Combat.SwingChainWindow`, `ThirdPersonSwings`); block arms that are relaxed unless punching; three training dummies in practice rounds.
- **Bow, against the owner's "yes":**

  | Their note | State |
  |---|---|
  | 90-damage headshot | Built (`BowHeadshotMultiplier = 1.8`) |
  | 3 to 4 bows a round | Not built. Bows are still in the tier-2 table (weight 5) and the tier-3 table (weight 10), with no cap anywhere in the loot code |
  | On-target aim only within 60 studs | Not built. `BowAimOnTarget = true` at every range, zeroed at 100 studs; there is no 60-stud limit |
  | "make the distance and drawing more accurate" | Not built. Damage depends on the draw alone; distance changes nothing |
- **Not in the game at all:** wind-ups other players can read, quick and heavy attacks, block, parry, dodge roll, kick, hit regions other than the head, knockback, stagger, hit-stop, truces. I searched `src\` for each; none exists.
- **In Blender:** all nine weapons, the armours and supplies as realistic models (`ItemsReal.glb`, previews in `art\previews\ItemsReal\`). No new weapon has been modelled.
- **In the docs:** `docs\design\WeaponsAndObjectives.md` (12 Nov) is a full plan: 19 weapons and tools, numbers, where each is found, five build phases (W1 to W5). `docs\research\CombatPhysicsPlan.md` covers the fighting model. Both were written before the owner's two documents of 15 Nov and have not been reconciled with them.

### What is missing, in the owner's order

1. **The weapons list, shown to the owner** (owed, see Reminders). Their own list is bows and arrows, knives, axes, spears, "other appropriate weapons", plus traps, special arrows and rare tools, and "a smaller collection of useful objects, each with a clear purpose". The 19-entry plan must be checked against that sentence before anything is built.
2. **The bow as they agreed it:** 3 to 4 a round; on-target aim only within 60 studs and real drop beyond; draw time and distance both mattering to what an arrow does.
3. **Region hitboxes** in their priority order, 0.15 studs generous, three rays a swing and one an arrow. No wound counter.
4. **Knockback, stagger and hit-stop** with their numbers.
5. **Attacks and battle manoeuvring:** slash left and right, stab, overhead, block, parry, dodge roll with its 0.15 s start-up. This is the item they asked to be reminded of.
6. **Movement to their table** (walk 12, run 20, sprint 26 with 8 s of stamina, and the rest).
7. **The animation set and its blend rules,** in first person and on other players' bodies.
8. **Truces,** which they approved on 12 Nov (see section 4, allies).
9. **Audio pass, then balance and tuning** (their steps 9 and 10).

---

## 2. The starting lobby

### What the owner said

| Date (UTC) | Their words |
|---|---|
| 18 Nov 08:09 | "the weapons and starting lobby and the train that taakes them to the prep room" |
| 18 Nov 08:09 | (the result screen) "it shouldnt pop up after the game it can appear on one of the physical boards" |

That is all. They have never described how the lobby should look or what is in it. Three other lines touch it:

- 15 Nov 01:12: "remind me we still need a loading screen animation" (what a player sees before the lobby).
- 15 Nov 01:58: "i also want to add a mode for people to be able to vc - with voicechat proxiimity".
- 18 Nov 05:18: "i have roblox plus now so all the benefits with game dev r there utilise them" (the lead put a Plus button in the lobby).

### What exists today

- **In the game:** "the Tor", a stone terrace on its own island 8,800 studs east of the Horn, radius 90. It has a courtyard, walkways, an overlook, a fire dais, 4 pavilions, 8 banners, 8 braziers and a central fire, 10 benches, a climbable oak, 8 spawn points, and **2 physical notice boards** with text on them. It was built on 11 Nov in the older realistic style and only moved when Map 1 went in.
- **On screen in the lobby** (`LobbyController`): the title LAST STANDING, a record card, a status pill ("NEXT ROUND IN 0:12" and so on), HOW TO PLAY, SETTINGS, and the Roblox Plus button.
- **In Blender:** the lobby kit of 11 Nov (pavilion, gate, brazier, banner pole, bench, notice board, railing, steps) inside `LandmarksReal.glb`.
- **In the docs:** `TwoArenas.md` decision 5 proposes retiring the Tor and making the Training Centre the place everyone waits. The owner never answered it. Today's order keeps a starting lobby, with the train between it and the prep room, so that proposal no longer fits their words.

### What is missing

1. A decision on what the starting lobby is (see Decisions): the owner has given no look for it.
2. The round's result on one of the physical boards instead of the pop-up (the UI agents have this).
3. A place in the lobby to board the train, and the call that sends everyone to it.
4. Whatever is on the other boards: the next round's countdown, who is in the arena. The station model already has two departure boards.

---

## 3. The train

### What the owner said

| Date (UTC) | Their words |
|---|---|
| 15 Nov 01:10 | TRIBUTE spec, section 9, in full below |
| 15 Nov 01:10 | "add skills when in game train goes to training room like in the movies and people get to test diff kits and abilities and chests will have diff items based on such - make it like the movie in that sense" |
| 15 Nov 01:31 | "WATCH THE TRAILER FOR THE UPCOMING HUNGER GAMES AND MAKE THE FIRST MAP LIKE THAT" then "AND MAKE THE TRAINS LOOK LIKE THEM TOO" |
| 15 Nov 01:36 | "(train station bit) look past the pause buttons" with one picture (`train_station_owner_frame.png`) |
| 15 Nov 01:41 | "make sure blendr recreates the map assets and game design with semi realistic colour tones" |
| 18 Nov 08:09 | "the train that taakes them to the prep room before the arena" |

**Their station picture shows:** a tall, narrow glazed hall in daylight; two dark trains with rounded noses and one glowing red-orange lamp each, facing the camera on either side of a central aisle; two rows of guards in white armour in the aisle; hanging banners; a departure board over each track; a large gold sculpture overhead; tall posters at the sides.

**TRIBUTE spec, section 9, word for word:**

> "9. The train
> Scene purpose: the last calm before the arena. It has to feel like a moving hotel that's kidnapping you. Everything is soft, warm and expensive, and the windows show a country getting poorer.
>
> Exterior
> Seven cars, brushed silver, bullet-nosed, seamless panel gaps, a faint warm glow leaking from every window at night. Magnetic levitation — no wheels, no bogies, no track noise beyond a low hum and a hiss at speed. Reflections slide across the flank. Station lamps smear into long streaks.
>
> Layout
> Car 1 — Vestibule. Brass handrails, pleated leather bench, a single wilting flower in a bud vase. The door seals with a pneumatic thump and the outside sound dies.
>
> Car 2 — Dining. Mahogany panelling with inlaid silver filigree, white linen, crystal that rings when the train sways, low warm sconces, a chandelier on a gimbal that never quite stops moving. Silverware laid for a meal nobody wants. Plates carry the Capitol seal. The table has a runner embroidered with all twelve district crests, District 12's corner worn thin.
>
> Car 3 — Lounge. Velvet club chairs, a globe drinks cabinet, a piano bolted to the floor. A wall screen loops Capitol propaganda — fashion segments, arena recaps, a smiling host. The screen's light is the only cool colour in the car.
>
> Car 4 — Corridor. Narrow, brass fittings, a strip of patterned carpet, doors on both sides. Two of them lead to the tribute compartments; the rest are locked.
>
> Car 5 — Compartment (District 12). Two bunks, one made up in silk, one in plain cotton. A fold-down basin, a mirror with a chipped corner, a window seat. Every surface is bolted. A pressed uniform hangs waiting. Under the window, a small brass plaque with the district number.
>
> Car 6 — Observation. Glass on three sides, floor-to-ceiling, a curved bench. This is where the districts go past — slag heaps, fence lines, floodlights, a mine head at District 12 fading behind. The glass is spotless and the view is not.
>
> Car 7 — Guard. Grey steel, no decoration, four white-armoured Peacekeepers standing the whole trip. They don't sit.
>
> Motion and feel
> Constant 1.5° roll and 0.4-stud vertical float on a slow sine, out of phase front to back. Loose objects slide with the sway. Chandelier and hanging lamps swing on their own inertia. Speed lines and dust motes streak past the windows. The hum is 52 Hz, and it gets into the score.
>
> Camera: 28mm, handheld, close to faces, shallow depth. The train is shot from inside; the player never sees the exterior until the door opens.
>
> Interactive beats: sit at the table (awkward silence timer), pour from the cabinet, watch the propaganda screen, stand at the observation window as District 12 passes. Each beat is a prompt-free proximity trigger, no button.
>
> Sound: rail hum, glass chime, cutlery shift, distant door thump, the piano's pedal squeak, the guard's boot on steel when the train slows."

Also from the spec: "StreamingEnabled on, train cars as separate models with ModelStreamingMode = Persistent" (section 10) and "The train, car by car" (build order, step 8).

**Two of their own lines pull apart on the outside of the train.** The spec says "brushed silver". Twenty minutes later they wrote "MAKE THE TRAINS LOOK LIKE THEM TOO" and sent the station picture, whose trains are dark. The later message and the picture win; Blender already follows them (black lacquer, a maroon band, gold pinstripes).

### What exists today

- **In the game:** nothing. No train, station or ride code in `src\`. Nothing has been uploaded to Roblox.
- **In Blender, pass 2** (`art\blender\train_sotr.py`; exports in `C:\Users\USER\OneDrive\Documents\LastStanding\BlenderExports\Train\`, written 15 Nov):
  - 6 GLB files, 27.7 MB, 34 assets, 59,748 triangles, no reported problems.
  - **Outside:** a nose car (also the tail, turned round), a body car, an observation car, an outer door.
  - **Inside, all seven cars of the spec:** vestibule, dining, lounge, corridor, compartment, observation, guard. Each is 72 to 79 studs long and about 10.5 wide.
  - **Moving pieces:** chandelier, pendant lamp, the sliding doors, the globe's lid, the bud vase, a crystal glass, and a night backdrop with a bridge.
  - **The station:** entrance hall, a train shed in 24-stud slices, the gold fan of ten blades, banner, departure board, poster and guard, all our own designs.
  - 20 pictures in `art\previews\Train\`. I looked at the station match and the dining car: both read as the owner's picture and spec, in flat faceted colour.
- **Still open from the design's own pass-2 list:** the manifest still lists 130 textures to upload in 33 sets. `TwoArenas.md` asked for these to be packed into a few palette textures first.
- **In the docs:** `TwoArenas.md` section 5.1 and 5.2 design the ride. It makes the ride first-session only, about 40 s, skippable, and puts the guard car at the front. Those are the designer's choices, not the owner's words.

### What is missing, in the owner's order

1. The fighting work first ("Build the arena combat loop before the train").
2. Textures packed, then the upload (uploads are permanent; the owner approved uploading Blender art on 11 Nov).
3. The train "car by car", 1 to 7: shells, interiors, collision, doors, and each car kept loaded as its own model.
4. Motion: the 1.5° roll and 0.4-stud float, sliding loose objects, swinging lamps, streaks past the windows, the country going past the observation glass.
5. The four beats, each started by walking up, no button: the table, the cabinet, the screen, the observation window.
6. Sound: the 52 Hz hum, glass, cutlery, door, piano pedal, the guard's boot.
7. Boarding in the lobby and arriving at the prep room, for up to 48 players at once. The spec is written for one player; it says nothing about a crowd in a car 10.5 studs wide.
8. The station from their picture, at whichever end it belongs (see Decisions).

---

## 4. The prep room, where players choose allies

### What the owner said

| Date (UTC) | Their words |
|---|---|
| 15 Nov 01:10 | "add skills when in game train goes to training room like in the movies and people get to test diff kits and abilities and chests will have diff items based on such - make it like the movie in that sense" |
| 15 Nov 01:10, design direction 3.2 | "Introduce a separate training environment where players can improve their physical attributes." Activities: "Running and endurance exercises. Weight training. Climbing exercises. Archery practice. Weapon handling. Physical obstacle courses." · "Completing training activities awards players progression tokens or training coins." |
| 15 Nov 01:10, design direction 3 | "There is no need to introduce a complicated character-class system or give every character special supernatural abilities." · "A player who has trained should have a genuine advantage in certain situations, but should not become so powerful that a new player has no chance of surviving against them." |
| 18 Nov 08:09 | "the prep room before the arena where they get to choose their allies" |

**Reading.** In both messages the train's destination is this room: "train goes to training room" (15 Nov) and "the train that taakes them to the prep room" (18 Nov). So the prep room and the training room are one place. The lead should say this back to the owner in one line when showing the plan.

**"Choosing allies" is new today.** Nothing in any design document covers choosing allies before a round. What their earlier words say about teams and alliances:

- 11 Nov 15:05 (pasted notes): "the Capitol watches, the Gamemakers intervene, sponsors influence survival, alliances form and the environment is deliberately manipulated."
- 12 Nov 16:41: "Yes (Recommended)" to a temporary truce by gesture that "ends on any damage, at the Offering's bell, or when four players are left."
- 15 Nov 01:10, design direction 2.4: "Players need enough time to explore, hunt, collect resources, form alliances and establish themselves within the environment."
- 15 Nov 01:10, design direction 7: "Other tributes begin approaching. Alliances, confrontations and strategic decisions determine who survives."
- 15 Nov 01:10, design direction 2.1: the opening should not feel like "an ordinary countdown followed by a conventional team fight."
- 15 Nov 01:58: proximity voice chat.

They have never asked for teams, shared wins or duos. The game is last one standing.

**A minimal honest version.** Choosing an ally in the prep room is the truce they already approved, agreed before the round instead of by gesture inside it:

- Two players choose each other in the prep room; both must agree.
- In the arena each sees a small mark over the other. Nothing else changes: no shared loot, no shared win.
- It ends the way they approved: on any damage between them, at the Offering's bell, or when four players are left. There is always one winner.
- Allies do not get neighbouring plinths, so an alliance is not a bloc at the Horn against players who came alone.
- The group size is theirs to set (see Decisions). Their own "four players are left" rule means a group of up to four can never reach the end still allied.

### What exists today

- **In the game:** nothing. No prep room, kits, stations, ally or truce code. The training dummies of practice rounds exist and can be reused.
- **In Blender:** nothing. No model and no picture of this room.
- **In the docs:** `TwoArenas.md` section 5.3, "the Training Centre": a hall of 220 × 150 studs with four weapon stations (archery, blades, spear and throwing, survival) and a fitness corner; stepping on a station's mat picks your kit; a kit makes one item in each crate you open come from its shelf and gives one small "knack"; training earns tokens for Stamina and Strength. `UpcomingFilm_Brief.md` section 5 has the look. The kit and crate parts follow the owner's sentence closely. The token ranks and the knack numbers are the designer's.

### What is missing

1. The room itself, modelled in Blender in the project's style and approved in game.
2. Stations where players "test diff kits and abilities".
3. Kits that change what "chests" give in the arena.
4. Choosing allies (new): how two players choose each other, how it shows in the room and in the arena, and the truce rules behind it.
5. The door to "the room" (section 5), and the call that locks kits and allies.
6. Later, per their direction: training activities that pay tokens, and the attributes they buy.

---

## 5. The room they enter before the launch animation

### What the owner said

| Date (UTC) | Their words |
|---|---|
| 15 Nov 01:17 | "also change the intro of going up to the arena from the grey room and then up in the circular motion - as as animation frame till you are at the top - and it should look semi realistic not hyperrealistic which makes the game tacky" |
| 15 Nov 01:40 | "(entering the second arena from this red room with metal net on top) (this is map one)" with five pictures |
| 15 Nov 01:46 | "no this ius the same map the red room with the metal on top is just the transition room before you go to the survivakl game and it loads up to the room like the images i sent you" |
| 18 Nov 08:09 | "and enter the room (before the transition animation to the arena)" |

**Reading.** "The room" is the red room: on 15 Nov they called it "the transition room before you go to the survival game", and today they place entering it just before the transition animation. What is new today is that the player enters it, coming from the prep room. Until now it has only been a camera shot.

**Their pictures show:**
- `launch_1_red_room_net_a.png`: looking straight down through a teal hexagonal frame at one figure standing in a dark red room, with a fine diamond net across the top.
- `launch_1_red_room_net_b.png`: from above, a figure in a white cape on a steel deck with black grates, a red rail and two red lamp housings, net panels in the floor.
- `launch_2_glass_cases.png`: a dim blue hall with a row of tall glass cases, a figure standing in each.
- `launch_3_pole_hall_wide.png`: a huge dark round hall with a spoked ring of lights in the ceiling and many thin poles, a figure part-way up each.
- `launch_3_pole_rise.png`: from below, a caped figure on a disc rising up a pole between light bars.

### What exists today

- **In the game:** a red room built from plain parts inside the launch intro (`LaunchIntroController\Set.lua`). Each player's device builds its own copy for the shot and deletes it afterwards. It is seen only from the overhead camera, for about 4.5 s in the full shot and 1.6 s in the short one. Nobody walks into it, and there is no door to it from anywhere.
- **In Blender, pass 2:** `LaunchRedRoom.glb` (9,748 triangles; interior 30 × 24 studs, net at 20 high), with pictures in `art\previews\Launch\`. Not uploaded, not in the game.
- **In the docs:** `TwoArenas.md` section 2 (the launch) and its "launch doors" in the Training Centre, 15 studs from the lift, which lead to the launch.

### What is missing

1. A red room a player can walk into from the prep room: a door, the deck, the disc under the hexagonal frame.
2. The trigger: once the player stands on the disc and the round is called, the transition animation starts from there.
3. The Blender room in place of the part-built one, so the room walked into and the room in the shot are the same.
4. What a player who has not entered by the call sees. The simplest rule: the call puts them on their disc.

---

## 6. Today's launch change: first person toward the end, then the sun

### What the owner said

| Date (UTC) | Their words |
|---|---|
| 15 Nov 01:17 | "up in the circular motion - as as animation frame till you are at the top" |
| 15 Nov 01:34 | The second launch picture source: "where [the film's lead] is coming up on a longer metal pole" (a character's name is left out here) |
| 18 Nov 08:09 | "when the player is loaded into the game and going up with the animation he should also feel first person toward the end and then slight blinding by the sun when he gets there" |

Two words carry the request. "also": the circling camera stays, and first person is added. "slight": the sun dazzles, it does not wipe the screen.

### What exists today

`LaunchIntroController` (1,500 lines), running on Map 1 with `Config.Launch.Intro = true`:

- **Full shot,** about 15 s to the hand-off inside a 22 s countdown: red room from above, a dip to black, the glass cases, then the rise up the pole with the camera circling once.
- **Short cut,** 6.2 s inside a 12 s countdown: red room, then the rise with about a third of a circle.
- **The end of the rise is third person.** The camera finishes low and in front of the player, looking up at their whole body. It never enters their eyes.
- **Then a full white-out.** Exposure and bloom flood for about a quarter of a second, then a white cover fills the whole frame until the hand-off. At the hand-off the player is in first person on the plinth and the white fades over 0.6 s. The white also hides a late-loading arena for up to 1.5 s.
- **On Map 1 the plinth does not rise.** The plinths stand on the turf with no shaft under them, so the player is simply standing there when the white clears.
- **The design had more than was built.** `TwoArenas.md` section 2.4 ends with the camera dropping behind the player's head and pushing "into your eyes over 1 s" on arrival. The beta version left that out.
- **In Blender, pass 2, not in the game:** the red room, the glass-case hall and the pole hall as three GLB files (`BlenderExports\Launch\`, 48 cases and 48 poles), with pictures in `art\previews\Launch\`. The game's set is built from plain parts and holds at most 24 cases, so on Map 1 two neighbouring plinths share one.
- **The sun at that moment:** rounds start at 07:24 in-game, a low morning sun. Players face the Horn from all round the ring, so some face the sun and some have it behind them.

### What is missing

1. **First person before the top.** In the last part of the rise the camera leaves its circle and settles into the player's own eyes, still rising, looking up the pole toward the opening and the light.
2. **A slight dazzle in place of the white wall.** As the player comes out onto the plinth: a short over-bright moment with sun rays that eases off in about a second, never a fully white frame. Every player gets it whichever way they face; it is stronger for those looking toward the sun.
3. **The same clock.** Both cuts keep their lengths, so the server's timing and the countdown do not change.
4. **A cover only for late loaders.** The full white stays as a fallback for a device whose arena has not loaded, since a slight dazzle hides nothing.
5. **Checks:** shaders off, low graphics, Reduce Motion, skip, and the Map 1 case where the plinth does not rise.

No decision is needed from the owner. Show them a short clip of the new ending.

---

## 7. Reminders the lead owes the owner on fighting

The lead told the owner today that weapons and fighting "includes the weapons list and bow notes I owe you".

**Reminder 1: attacks and battle manoeuvring.**
- Their words (12 Nov 16:41 UTC): "we will focus on attacks and battle manaeuvouring later remind me".
- The question they put off: "should attacks have visible wind-ups, a quick and a heavy attack, and a simple block with a perfect-block window?"
- What they have written since (15 Nov, TRIBUTE spec): "Combat: slash_L, slash_R, stab, overhead, block, parry, dodge_roll, bow_nock, bow_draw, bow_hold, bow_release." So block, parry and a dodge roll are in their own spec. The quick-and-heavy question is still unanswered.

**Reminder 2: the weapons list.**
- Their words (12 Nov 14:55 UTC): "also weapon list needs to be improved and game design - what the objectives are etc make it intuitive and inspired from the movie".
- And (15 Nov, design direction 4): "The focus should be on a smaller collection of useful objects, each with a clear purpose." Weapons: "Bows and arrows. Knives. Axes. Spears. Other appropriate weapons."
- Today's list is the nine in section 1. The proposed list in `WeaponsAndObjectives.md` keeps all nine (the mace becomes the War Club, the Arena Sword the Longsword), and adds Stones, a Sling, a Blowpipe, a one-per-round compound bow, a Wire Snare, a Tripwire Kit, a Fire Kit, Rope, Purifying Tablets, Field Glasses and a Hand Flare, with three special arrows and two darts. The owner has never seen this list.

**Reminder 3: the bow notes.**
- Their words (12 Nov 16:41 UTC), to "make it a rarer prize (3–4 per round instead of about 13), with a 90-damage headshot, and arrows that land exactly on the crosshair only within 60 studs?": "yes and make the distance and drawing more accurate but again we will deal with weapons and fighting later".
- Where each stands: the 90 headshot is built. 3 to 4 bows a round, on-target aim only within 60 studs, and "distance and drawing more accurate" are not.
- Their own gloss on distance and drawing (15 Nov): "the bow's draw time and the target's distance both matter."

**Reminder 4: truces.** They said yes on 12 Nov. Not built. It is the base for today's "choose their allies".

**Reminder 5: varied swings.** "sword hitting, axe chopping etc shouldnt be only one animation be a little dynamic" (15 Nov 12:12 UTC). Built; tell them it is in, and that the fighting work builds on it.

Other reminders they asked for, not about fighting: a loading screen animation; ads on Twitter, YouTube and TikTok; a showcase video (all 15 Nov 01:12 to 01:13 UTC).

---

## 8. Decisions that are the owner's and not answered anywhere

1. **Allies: how many, and is it the truce you already approved?** Default: yes, it is that truce, agreed in the prep room; up to three allies (a group of four); it ends on damage between allies, at the Offering's bell, or when four are left; one winner always.
2. **What the starting lobby is.** They have given no look for it. Two honest options: keep the stone terrace that exists and add a platform for the train; or make the station hall from their own picture the lobby, with its departure boards as the "physical boards". Default: the station hall, because it is the only pre-arena place they have shown us besides the launch rooms.
3. **Does everyone ride the train before every round?** Their sentence makes the train the way from the lobby to the prep room. `TwoArenas.md` estimates the walk through the seven cars at 40 to 60 s. Default: the full ride on a player's first round of a session, and a short arrival (about 10 s) before later rounds.
4. **Quick and heavy attacks.** Reminder 1: block, parry and dodge roll are in their spec; whether a held attack is a slower, harder hit is still theirs to say. Default: yes.
5. **The blood and severing in their spec.** Their all-ages instruction of 18 Nov removes it. They should hear that in one plain line, with the choice of a separate older-audience mode later. Default: none.

**Settled by their words, so not asked:** the train comes after fighting; the trains and station look like their picture; the prep room is the training room; kits change what crates give; the red room is the room before the launch; the launch is one circling shot that now ends in first person with a slight sun dazzle; the bow's four notes; their movement numbers (the lead should tell them these change how moving feels, and let them try it, not ask again).

---

## 9. Where earlier work departs from their words

- `TwoArenas.md` makes the Training Centre the place everyone waits and retires the lobby. Today's order has a starting lobby, then the train, then the prep room.
- `TwoArenas.md` makes the train a first-session extra that can be skipped. Their words make it the way to the prep room.
- `TwoArenas.md` moves the guard car from last to first. Their spec lists it as Car 7.
- `WeaponsAndObjectives.md` proposes 19 weapons and tools. Their later direction asks for "a smaller collection".
- The launch intro in the game ends in third person and a full white screen. The design already called for an ending in the player's eyes.
- The train's textures were to be packed before upload. The export still has 130.
- OwnerRequests.md says the result board is "in the lobby". Their words are "one of the physical boards"; if the lobby changes, the board goes with whatever lobby they choose.
