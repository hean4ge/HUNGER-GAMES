# Weapons and objectives

*Lead game designer, 12 November 2026. Your note: "weapon list needs to be improved and game design - what the objectives are etc make it intuitive and inspired from the movie". This plan gives every weapon one clear job, and it gives the round a goal you can always see. It rests on the research brief (the books and films, battle-royale and survival design), the audit of today's game (Studio read-only, place v166, and the repo's `src/` export) and the new arena plan, [ArenaV3.md](ArenaV3.md), which landed while this was being written. Nothing here is built yet. This is the only file it changes.*

**Decisions (owner, 12 November 2026)**
- **Q1, fighting (wind-ups, light and heavy attacks, block):** deferred. The owner said "we will focus on attacks and battle manaeuvouring later remind me". Remind them before starting W2.
- **Q2, the bow:** yes to 3–4 bows a round, a 90-damage headshot, and aim-on-target only within 60 studs. The owner adds: "make the distance and drawing more accurate". The weapons and fighting work as a whole comes later, at the owner's call.
- **Q3, truces:** yes.
- **Q4, the fallen as the audience:** not now. It stays in Roadmap Phase 10.
- **The objectives part** (the goal line, the ten acts, onboarding through the Drill) is not weapons or fighting, so it can be built before them.

**In short (plain English)**
- **What's wrong today.**
  - Six of the nine weapons are the same click with different numbers, and rarity lies about them. The Common knife kills almost as fast as the Epic sword, and the Rare mace and spear lose to it.
  - Bows are everywhere: about 13 a round. A full-draw arrow to the head kills from full health.
  - After the horn, nothing on screen says what to do.
- **The new list: 19 weapons and tools, each with one job, one tell and one counter.**
  - All nine of today's weapons stay. Two are renamed, and all are retuned.
  - New are Stones and a Sling, so nobody is ever helpless near water, plus a Hatchet you can throw, a Blowpipe, snares and tripwires.
  - A small survival kit joins them: a Fire Kit, Rope, Purifying Tablets, Field Glasses and a Hand Flare.
  - Rarity now means power. In a straight fight nothing Common downs a healthy contender in under 2 seconds (only the knife's ambush from behind is quicker), and the Epic Longsword takes 1.4.
- **The round tells a story.** You rise on the plates, then rush the Spire or run. You find water and shelter, and you survive the night and the Roll Call. You gamble on the Offering on the second morning, then outlast the closing border.
- **One line under the compass always says what to do now,** for example "FIND WATER · 140 m". A second line says what's next, for example "NEXT · ROLL CALL AT DUSK · 3:12".
- **Inspired by the films, but our own.** It borrows the structure of the source's arenas:
  - a countdown on the plates;
  - a central pile you can see from the start;
  - water first, then a cold night;
  - gifts from outside;
  - a restock that draws everyone in;
  - a closing finale.

  Every name, shape and rule is ours, and none of the source's signatures appears: no trident, no poison berries, no colour-coded arrows, no cannon, no horn-shaped centre.
- **Small rounds work too.** Fewer contenders means fewer prizes at the Spire, and the faster clock PlayabilityPlan B3 plans keeps a round of 2–4 to about 7 minutes.
- **Build order: five phases.** The first takes about 1½ weeks and needs no new art:
  - retune the weapons;
  - put the Spire's prizes in plain view;
  - cut the number of bows;
  - add the goal line;
  - make the practice-round dummies work on live servers.

**How to read it.** §1 sets the rules, §2 the roster, §3 the round and the objective tracker, §4 how the first round teaches it all, §5 the balance tables, §6 the build plan (by phase and by script) and §7 four questions for you. The review notes at the end list what the design review changed.

**Conventions**
- **Times** are minutes:seconds after the horn, on the full 24-contender schedule. The HUD clock counts down from 15:00, so 9:50 after the horn shows as 5:10. Once PlayabilityPlan B3 lands, rounds of fewer than 16 run on a faster clock, and every time here scales with it.
- **Beats marked "v3"** arrive with the ArenaV3 Vale, such as the border's first two stages. Everything else works on today's arena too.
- **Distances** are in studs (1 stud ≈ 0.28 m). The HUD prints metres.
- **Buttons.** "[LMB]", "[RMB]" and "[E]" mean "this device's button". The HUD prints the right one through `Shared.Glyphs`.

---

## 1. Design goals

| # | Rule | What it means in play |
|---|---|---|
| 1 | **One job, one tell, one counter** | Every item is the best at one thing. It shows that thing to others through a shape, a sound or a pose, and something you can find beats it. If two items share a job, one of them goes. |
| 2 | **Read it at a glance** | You read the shape first (it must read at 60 studs), then the material, then the sound. Names say the job: Longsword, War Club, Throwing Knives. Rarity colour appears only on loot and in the HUD, never on a weapon in someone's hands. |
| 3 | **Rarity means power, then scarcity** | Within a role, the rarer weapon kills faster. Time to down a healthy, unarmoured contender with light hits: Common at least 2.0 s, Uncommon about 1.8 s, Rare 1.6 s, Epic 1.4 s. The knife's unseen hit and the War Club are the two deliberate exceptions (§5.1). The round's single Legendary comes only from contested drops. |
| 4 | **No single hit kills a healthy contender** | Every hit is capped at 95 damage, and a full-draw headshot does 90. You always get one chance to react. |
| 5 | **The films' kind of kit, never their signatures** | Old, physical tools: bows, knives, spears, axes, slings, snares, flint and rope. None of these: a trident and net, poison berries as a weapon, colour-coded or exploding arrows, a weapon locked to its owner, anything that bounces off the border (§2.8). |
| 6 | **Survival kit matters as much as a blade** | Water, shelter, fire and medicine decide who lives. A runner with a bottle, a fire kit and a pocket of stones is as ready as a rusher with a machete. |
| 7 | **Always know what to do next** | One goal line, set by the phase and by your own state (thirsty, unarmed, wounded, night), plus the next beat. Every arena beat is also a goal. |
| 8 | **Fun in the first minute, fair in every death** | You hold something within 30 s whether you rush or run. Every threat has a tell. Every death card names the counter to what killed you. |

---

## 2. The weapon roster

### 2.1 At a glance

19 entries: 6 melee weapons, 2 thrown, 4 ranged (with four kinds of arrow and two of dart), 2 traps and 5 tools. Fists stay as the hidden baseline. Food, medicine, armour and packs sit around them (§2.2).

| # | Name (`id`) | Role | Rarity | Its one job | Its tell | Beaten by |
|---|---|---|---|---|---|---|
| 1 | **Hunting Knife** (`knife`) | light melee | Common | a quick, quiet ambush: the first hit on someone who isn't looking does double | a faint swish; held low | reach (the spear); armour |
| 2 | **Machete** (`machete`) | light melee, sweep | Uncommon | a wide sweep that catches two at once: the blade for the scramble | the arm cocks back wide | reach (the spear); the Longsword |
| 3 | **Hatchet** (`hatchet`) | heavy melee, throwable, tool | Uncommon | downs in three chops; one heavy throw; splits firewood | raised beside the head | a quicker blade in the gap after a chop (it has no guard, W2); dodging the throw, then closing in |
| 4 | **War Club** (`mace`) | heavy melee, armour-breaker | Uncommon | armour stops only half as much against it; each hit staggers | dragged back over the shoulder with an iron scrape | stepping back from the slow swing; anything with range |
| 5 | **Spear** (`spear`) | reach, throwable | Rare | outreaches every blade; a big throw | the shaft drawn back | getting inside 4 studs; making them throw, then closing in |
| 6 | **Longsword** (`sword`) | duellist | Epic | the best blade, with the best guard | the guard pose, blade across the body | ranged weapons; refusing the duel |
| 7 | **Stones** (`stones`) | thrown, improvised | Common | free harassment: a hit spoils a draw | an overarm lob | they barely hurt, so close in |
| 8 | **Throwing Knives** (`throwing_knife`) | thrown | Uncommon | quick throws at short range; finishing a runner | a flick from the shoulder; a bandolier on the chest | cover; making them run out |
| 9 | **Sling** (`sling`) | simple ranged | Uncommon | lobbed stones at mid range: the archer's counter | an arm whirling overhead and a whirr | closing in while it whirls |
| 10 | **Recurve Bow** (`bow`) | ranged | Rare | kills at range | the draw's creak, heard at 45 studs | stones, knives and slings spoil the draw; trees; closing in |
| 11 | **Blowpipe** (`blowpipe`) | stealth ranged | Rare | silent darts; Nettle Darts slow | a cane raised to the lips | short range; it barely hurts |
| 12 | **Citadel Compound Bow** (`compound_bow`) | ranged | Legendary | the round's one Citadel prototype: a fast, quiet draw | cams and cables; the Herald announces it | the same as the bow |
| 13 | **Wire Snare** (`wire_snare`) | trap | Uncommon | holds a leg for 2.5 s on a trail | wire glints within 6 studs; a loud snap | walking crouched; a knife cuts you free |
| 14 | **Tripwire Kit** (`tripwire`) | trap, alarm | Uncommon | rattles when crossed and tells its owner | stakes and wire within 6 studs | stepping over; disarming and taking it |
| 15 | **Fire Kit** (`fire_kit`) | tool | Uncommon | a campfire: warmth, faster healing and light; it lights Pitch Arrows | glow at night, smoke by day, a crackle | anyone can stamp it out, and a fire draws hunters |
| 16 | **Rope** (`rope`) | tool | Uncommon | a fixed line down a ledge or cliff, for anyone to use | a rope hanging from a stake | it can be followed, or cut at its stake |
| 17 | **Purifying Tablets** (`purifying_tablets`) | tool | Uncommon | make brackish water safe to drink | — | — |
| 18 | **Field Glasses** (`field_glasses`) | tool | Uncommon | look far, and see what a contender carries | a lens glint in the sun | staying out of the open |
| 19 | **Hand Flare** (`hand_flare`) | tool | Uncommon | lights the dark for 25 s | the flare itself | it shows where you threw it from |

### 2.2 The numbers

All values are starting values for playtests. They work in today's hit model (one strike per swing, as `CombatService` checks it), and phase W2 (§6) adds heavy attacks and a guard (§5.4).

**Melee.** "Swing every" is the cooldown. "Reach" is the item's `range`; the server adds its 3-stud lag allowance and 2.4-stud sweep on top. Times are light hits on a 100-health contender with no armour.
- **Effective reach in W1,** from the attacker's head to the target's body as `CombatService` measures it: fists 9.4, knife 9.9, hatchet 10.4, machete and War Club 12.4, Longsword 13.4, spear 14.9 studs.
- **Why three ranges drop.** With today's ranges the flat allowance squeezes every blade into 10.9–14.9 studs, so the spear's edge over the knife would be 3.5 studs. The knife (6 → 4.5), the hatchet (6.5 → 5) and fists (5.5 → 4) come down, so that edge is 5 studs and reach becomes a real job. CombatPhysicsPlan phase 2's real reach later shrinks every blade (the knife to about 4.4).

| Weapon | Type | Damage | Swing every | Wind-up | Reach | To down | Time | Special |
|---|---|---|---|---|---|---|---|---|
| Fists (hidden) | blunt | 8 | 0.45 s | 0.06 s | 4 | 13 hits | 5.46 s | — |
| Hunting Knife | cut | 20 | 0.48 s | 0.10 s | 4.5 | 5 | 2.02 s | **Unseen hit:** the first hit on someone facing away who hasn't been hurt in the last 5 s does 40 (4 hits, 1.54 s). Its swing is heard only within 12 studs. It cuts you out of a snare at once. |
| Machete | cut | 26 | 0.55 s | 0.14 s | 7 | 4 | 1.79 s | **Sweep:** a second contender in the swing's arc (±55°) takes 60% (16). In W4 a clean hit on an unarmoured body also starts Bleeding. |
| Hatchet | chop | 34 | 0.80 s | 0.18 s | 5 | 3 | 1.78 s | **Throw** (hold Aim, then Attack): 45, or 72 to the head, at 110 studs/s with gravity 45. It stays where it lands until someone takes it. **Firewood:** a fire you light with a hatchet in your bag burns twice as long. |
| War Club | blunt | 44 | 0.95 s | 0.32 s | 7 | 3 | 2.22 s | **Armour-breaker:** armour stops only half as much against it, so it takes 3 hits through any vest. In W2 every hit staggers the target (half speed for 0.35 s, no attacks for 0.25 s), and a heavy hit breaks a guard. |
| Spear | pierce | 34 | 0.70 s | 0.20 s | 9.5 | 3 | 1.60 s | **Reach:** the longest of any blade. Within 4 studs of its target (measured like reach, from the head to the point it hits) it does only 60% (20). **Throw:** 60 (capped at 95 to the head), at 110 studs/s with gravity 45. |
| Longsword | cut | 36 | 0.62 s | 0.16 s | 8 | 3 | 1.40 s | **The duellist:** in W2 it has the best guard (it lets through 15%), and a perfect block makes your next light hit within 0.6 s land ×1.3. |

**Ranged and thrown.** The bow keeps today's draw and speeds. Throws move from today's near-laser speeds to the "assisted" values in CombatPhysicsPlan §3.4.

| Weapon | Type | Damage, body / head | Draw or cycle | Speed / gravity | Useful range | Ammo | Special |
|---|---|---|---|---|---|---|---|
| Recurve Bow | pierce | 14–50 by draw / ×1.8 (90 at full draw) | 0.9 s draw; about 1.1 s a shot | 90–240 / 55 | point-and-shoot inside 60 studs; real drop beyond, to about 150 | Field Arrows, plus special arrows from W4 | The creak is heard at 45 studs (built: QW9). In W2 a hit on the archer cancels the draw. |
| Citadel Compound Bow | pierce | 16–54 by draw / capped at 95 | 0.6 s draw; about 0.8 s a shot | 90–270 / 55 | as the bow | as the bow | Its creak is heard at only 18 studs. One per round, announced. |
| Sling | blunt | 12–34 by whirl / ×1.5 (51 at a full whirl) | 1.0 s whirl; about 1.25 s a shot | 80–150 / 55 | 10–70, lobbed | Stones | The whirl is heard at 35 studs. A hit cancels a bow draw or a heavy wind-up. |
| Throwing Knives | pierce | 22 / 35 | 0.5 s | 120 / 40 | 5–30 | themselves (a stack of 6) | They always stay where they land (built). A hit cancels a draw. |
| Stones | blunt | 10 / 20 | 0.6 s | 90 / 55 | 5–25 | themselves (a stack of 8) | A hit cancels a draw. Gather 3 at a time from stone heaps by the water and on scree. Walk over thrown ones to pick them up. Thrown stones crumble 30 s after landing and never count toward `Config.Combat.WorldItemCap` (400, oldest first), so stone throws can't push spent arrows out of the world. |
| Blowpipe | pierce | Dart 8 / 12; Nettle Dart 4, plus Numbed | 0.8 s | 140 / 30 | 5–40 | Darts | Heard only within 8 studs. Numbed: 20% slower and no sprinting, for 5 s. |

**Arrows and darts.** Arrows go in a quiver from W4 (12 arrows; 16 with a Rucksack, 20 with a Frame Pack). Until then they sit in the hotbar, as today.

| Ammo | Rarity | Full-draw damage | Effect | Lost or kept | Look |
|---|---|---|---|---|---|
| Field Arrows (`arrow`) | Common | 50 | — | They stay where they land (built), but 1 in 3 break on stone or metal. | a four-faceted steel bodkin; grey fletching |
| Broadhead (`broadhead_arrow`) | Rare | 45 | A body hit starts Bleeding: 1 a second for 6 s, stacking to 3. A bandage stops one stack. | 1 in 2 break on any hit, and one never comes back out of a body | three flat steel blades |
| Pitch Arrow (`pitch_arrow`) | Rare | 40 when lit, 35 unlit | Light it by drawing within 6 studs of a fire: a campfire, a brazier, a Hand Flare or a fire patch. A body hit starts Burning (2 a second for 3 s). Where it lands it leaves a 5-stud fire patch for 8 s, which never spreads and goes out in water. While nocked it lights you up too. | always used up | a rag-and-pitch wrap bound with cord |
| Whistler (`whistler_arrow`) | Uncommon | 30 | It shrieks in flight (heard at 60 studs). Where it lands, 3 s of footsteps and rustling play, a decoy. | as Field Arrows | a drilled bone whistle behind a blunt head |
| Dart (`dart`) | Common | 8 | — | 1 in 2 lost in the grass | a cane needle with a cotton tuft |
| Nettle Dart (`nettle_dart`) | Rare | 4 | Numbed for 5 s | always used up | the same needle with a nettle-leaf wrap |

**Traps and tools.** Every trap and tool is used by holding Attack while it's in your hand, so none of them needs a new button.

| Item | Stack | Use | Effect | Limits | Its cost or counter |
|---|---|---|---|---|---|
| Wire Snare | 2 | Hold 1 s on the ground (slopes up to 30°); it arms 2 s later | It holds a leg for 2.5 s and does 5 damage, with a loud snap; the owner gets a ping with a direction. Tap [E] to wriggle free in about 1 s, or a knife frees you at once. It never kills. | 3 armed per contender and 40 in the Vale. None within 70 studs of the Spire in the first 60 s, within 8 studs of a plate, or in water. | The wire glints within 6 studs. Crouch and hold [E] for 2 s to disarm it and take it. |
| Tripwire Kit | 1 | Set two stakes 4–14 studs apart | A tin of pebbles rattles (heard at 70 studs), and the owner gets a ping with a direction | 3 triggers; the same placement limits | The same 6-stud rule |
| Fire Kit | 2 | Hold 3 s on dry ground, a cave floor included | A campfire for 2 minutes, or 4 with a hatchet in your bag. Within 12 studs, health comes back twice as fast once you haven't been hit for 8 s. It is a warmth source for Cold Snap, lights Pitch Arrows and lights 30 studs around it. | 8 fires in the Vale at once | Its glow shows from about 300 studs at night and its smoke by day, and the crackle carries 40 studs. Anyone can stamp it out by holding [E] for 1 s. |
| Rope | 2 | Stand at a ledge and hold 2 s | A climbable rope hangs down to 40 studs below (ArenaV3's FixedRope asset, tagged `Climbable`). Anyone can climb it, and you take it back with [E] (2 s). | — | Others can follow you down. Any blade cuts it at its stake in 1 s, but not while someone is on it, so a cut rope closes a route and never drops anyone (a 40-stud fall does about 55 damage) |
| Purifying Tablets | 4 | Fill a bottle at brackish water | One tablet is used and the bottle comes out clean. Brackish water (the Sump, the Drowned Pines, the reeds; scum on the surface tells you, PlayabilityPlan B7) gives +10 thirst a sip and costs 3 health without one. | — | — |
| Field Glasses | 1 | Hold [RMB] | 4× zoom, held steady. Hold a contender in view for 1 s and a small tag shows their weapon and armour for 6 s. | — | Others see a lens glint in daylight while you face the sun |
| Hand Flare | 2 | [LMB] throws it | It burns 25 s and lights 35 studs around it. It lights Pitch Arrows. | — | Everyone sees it, and where it was thrown from |

**Around the weapons** (most of it exists already):
- **Food, drink and medicine:** unchanged ([loot-equipment.md](loot-equipment.md) §1.1). Its planned field medicine (Field Dressing, Splint, Antitoxin) arrives with the statuses in W4.
- **Armour:** damage now depends on the damage type (table below). Integrity, armour that wears out, follows later with loot-equipment §5.7's values. This table is softer than §5.7's on purpose (there a Leather Vest takes cuts at ×0.70): until integrity exists armour never wears out, so it must protect less. §5.7's values and integrity replace this table together, in Roadmap 4a.

  | Armour | Rarity | Cut | Chop | Blunt | Pierce | Today (flat) |
  |---|---|---|---|---|---|---|
  | Leather Vest | Uncommon | ×0.80 | ×0.85 | ×1.00 | ×0.85 | ×0.85 |
  | Padded Armor | Epic | ×0.65 | ×0.72 | ×0.85 | ×0.72 | ×0.72 |
  | Citadel Plate Carrier (W4) | Legendary | ×0.55 | ×0.60 | ×0.80 | ×0.50 | — |

  Until hit zones exist (CombatPhysicsPlan phase 3), armour applies to every hit, as today.
- **Packs** (W4, loot-equipment §5.3): the Satchel (7 slots), the Rucksack (8 slots, a 16-arrow quiver) and the Citadel Frame Pack (9 slots, a 20-arrow quiver, 5% slower sprint). A pack is worn on the back, where everyone can see it. These quivers replace loot-equipment §3.3 and §5.3's 24, 30 and 40, so arrows stay scarce.

### 2.3 Feel and animation

Each weapon gets one first-person feel and one tell that others can see and hear. The third-person poses arrive in W2, through `CharacterVisuals` playing the `CombatAction` remote that today only the bow's creak uses.

| Item | In your hands (first person) | What others see | What others hear |
|---|---|---|---|
| Hunting Knife | A fast backhand slash and a short stab from a low grip. Light camera kicks. | held low; quick flicks | a faint swish, within 12 studs |
| Machete | A wide flat sweep that drags a little through its arc; in W2 the heavy attack is a diagonal cleave | the arm cocked back wide | a heavy swish |
| Hatchet | An overhead chop that bites, with a short hit-stop. To throw, it draws back over the shoulder and turns once in flight. | the hatchet raised beside the head | a grunt, then a thunk |
| War Club | A slow wind-up, then a big smash with a long hit-stop and a dip of the camera | the club dragged back over the shoulder | an iron scrape on the wind-up |
| Spear | Two-handed thrusts. To throw: raise it to the shoulder, take a step, hurl. | the shaft drawn back | the wood creaks as it draws back |
| Longsword | Clean diagonal cuts and a stab. In W2, a guard: the blade across the body, ringing when it blocks. | the guard pose | a ring of steel |
| Stones | A quick overarm lob | the arm going up | a dull thud where it lands |
| Throwing Knives | A flick from the shoulder, then the next one is drawn from the bandolier | the flick | a hiss in flight |
| Sling | Hold to whirl: the pouch circles overhead two or three times a second and the view sways a little; let go to release | an arm circling above the head, readable at 60 studs | a rising whum-whum, heard at 35 studs |
| Recurve Bow | As built: raised to the left, the string drawn to under the chin | the drawn bow | the creak, at 45 studs (built) |
| Blowpipe | Both hands raise the cane to the lips; a sharp breath sends the dart; you thumb in the next one (0.6 s) | the cane at the lips | a soft puff, within 8 studs |
| Citadel Compound Bow | Like the bow but faster, with a click from the cams at full draw | the drawn bow, cams turning | a muted creak, at 18 studs |
| Snare and Tripwire | Kneel with your hands down and set it (1 s). A sprung snare jerks the loop tight. | someone kneeling | the snap; the rattle of the can |
| Fire Kit | Kneel, strike flint on steel twice, blow on the tinder, and the flame catches (3 s) | sparks, then a fire | striking, then the crackle |
| Rope | Kneel at the edge, two taps on the stake, then throw the coil over (2 s) | the rope hanging | a stake being knocked in |
| Purifying Tablets | You drop a tablet into the bottle's neck as it fills | — | — |
| Field Glasses | Both hands raise them, and the view narrows into a soft binocular mask | the glasses raised; the glint | — |
| Hand Flare | Strike the cap for sparks, then an underarm throw | the flare | a hiss |

### 2.4 Where each item is found

The sources are the same on both arenas.
- **The Spire's three rings** (§3.2): the outer ring, the steps and the alcoves.
- **Site crates:** tier 2. Today these are the POIs; in v3 they are the sites in rings B to D and the three hot zones.
- **Camps and ground:** tier 1, on trails and at camps.
- **Runner's caches:** the 8 pale flags.
- **Prize spots** (v3): six tier-3 spots, two of them stocked each round.
- **The Offering, the Lure** (Roadmap Phase 2a) and **Patron capsules** (Phase 3).

The counts per round below come from a 20,000-round simulation on today's markers; §5.6 gives the method. On the v3 markers the loot planner sets the totals ([ArenaV3](ArenaV3.md) §6.1, task T10). The caps in the last column hold on any map.

| Item | The Spire | Site crates | Camps and ground | Runner's caches | Offering, Lure, prize spots | Patron capsules | Per round (24 contenders) |
|---|---|---|---|---|---|---|---|
| Hunting Knife | — | — | yes | 40% of caches | — | the first gift for anyone holding only fists | ~6.1 |
| Machete | 2 on the steps | yes | — | — | — | for fists or a knife only | ~5.3 |
| Hatchet | 2 on the steps | yes | camps | 10% of caches | — | for fists or a knife only | ~6.6 |
| War Club | 1 on the steps; alcoves and plaza crates | yes | — | — | — | — | ~4.6 |
| Spear | 2 on the steps; plaza crates | rare | — | — | — | Fine capsules | ~4.0 |
| Longsword | always 1 in an alcove from 8 contenders up (§3.2), sometimes a second | — | — | — | the Offering (50%); prize spots | Gilded, after the Offering | ~1.9 at the start; **at most 3 a round, and one per six contenders** (at least 1) |
| Recurve Bow | 1 on the steps' rack (restocked at the Offering); at most 1 in an alcove | **none**, except a fixed rack in the Watchtower's cab | — | — | prize spots, within the cap | **never** | ~2.5 at the start + 1; **at most 5 a round, and one per two contenders** |
| Citadel Compound Bow | — | — | — | — | the Offering's or the Lure's Legendary roll | **never**: capsules never carry a bow (a Gilded one may carry the Plate Carrier instead) | **at most 1 Legendary a round** |
| Sling (with 4 stones) | plaza crates | yes | — | 10% of caches | — | for runners holding only fists | ~3.7 |
| Throwing Knives | 2 pairs on the outer ring; plaza crates | yes | — | 40% of caches | — | — | ~8.3 stacks (~18 knives) |
| Stones | 2 heaps on the outer ring | — | heaps by every water point and on scree (unlimited) | with the sling | — | — | ~23 as loot, plus the heaps |
| Blowpipe (with 8 darts) | alcoves (W4) | rare | — | — | — | — | ~0.5–1 |
| Field Arrows | 6 on the steps; plaza crates; 5 with each bow | yes | camps and ground (rare) | — | 2 full quivers (8 each) | 8 for an archer under 6 | ~44 at the start + 16 |
| Broadhead, Pitch Arrow | alcoves | — | — | — | the Offering | 2 special arrows for an archer | ~3 + 3 of each |
| Whistler | — | yes | — | — | — | — | ~3 |
| Wire Snare | — | yes | yes | — | — | — | ~4.3 |
| Tripwire Kit | — | yes | — | — | — | — | ~1.7 |
| Fire Kit | alcoves and plaza crates | yes | camps | — | the Offering | at night or during Cold Snap | ~3.9 |
| Rope | alcoves | yes | camps | — | — | — | ~3.1 |
| Purifying Tablets | plaza crates | yes | yes | — | the Offering | near brackish water | ~8.6 tablets |
| Field Glasses | alcoves | yes | — | — | — | — | ~1.8 |
| Hand Flare | — | yes | yes | — | — | at night | ~3.6 |

**Patron Requests** (§3.10) also drop a Patron parcel beside you when you complete one, at most 12 a round. Each parcel holds one tool, chosen by your need: tablets, a fire kit, a rope, the field glasses, a ration, bandages, or arrows for an archer. It is a parcel, not a tin, so it can't be mistaken for the tripwire's can, the tablet tin or the Gold caches' sealed tins (Roadmap Phase 6b).

### 2.5 Art: realistic blockish

**Style rules for every new item**
- **Built from blocks.** Every piece is a box, a wedge or a prism of 6–12 sides, with a small chamfer (0.03–0.06 studs) so its edges catch the light. No smooth subdivision and no sculpted organic shapes. Sizes and proportions are real.
- **Detail lives in the material, not the mesh.** Use the ItemsReal material library (`art/blender/tex_items_mats.py`): forged and carbon steel, wrought iron, brass, oiled hardwood, leather, cord, canvas and bone. Wear sits on real edges, grime in crevices, and the grain follows each piece.
- **Silhouette first.** Every role has an outline others can read at 60 studs, and its own way of being carried: the bow across the back, the spear upright, the club on the shoulder, the sword in a scabbard, the sling at the belt, a pack on the back.
- **No glow and no runes.** Rarity shows on loot and in the HUD. The one Legendary carries a brass Citadel seal.
- **Our own models only.** Everything is built in the ItemsReal Blender pipeline (`items_real.py`, `ir_geo.py`, `ir_weapons.py`, plus a new `ir_kit.py`). Nothing comes from the Creator Store or open-source packs.
- **Budgets.**
  - At most 2,500 triangles for a held item.
  - One 1024 texture set per group, dropping to 512 if the 3 GB phone test is tight.
  - The Grip sits at the origin, pointing along +Z, with a Tip attachment. Bows also keep Nock, StringTop, StringBottom and ArrowRest; the blowpipe adds Mouth, and the sling adds Pouch.
- **First person.** Every hold is authored against the restyled first-person arms being made now: your own Roblox avatar's arms, kept blocky and lit like the world, as you asked (`Config.Viewmodel.ArmStyle` "Avatar" in the live place). So a hold must fit any avatar's arm size and skin, adds no sculpted hands or sleeves, and must pass the bow-aim screen-coverage check: nothing covers the crosshair area.
- **When the style test is approved,** these shapes follow it. They are already written in its terms.

| Item | Shape, built from blocks | Materials (the maker, for flavour) | How others see it carried | Triangles |
|---|---|---|---|---|
| Hunting Knife | 1.35 studs long. The blade is one tapered wedge with a separate bevel strip; the clip point is a single facet. A brass guard bar, a grip of three stacked leather washers and a square pommel cap. | satin carbon steel, brass, oiled leather; an Ironreach stamp on the blade | a sheath on the right hip | ~1,200 |
| Machete | 2.5 studs. A long flat slab of a blade that widens to a squared, chamfered tip. The full tang runs between two walnut slabs with three brass pins; a lanyard loop at the end. | grey steel with a bright edge, walnut | blade-down at the left hip | ~1,000 |
| Hatchet | 2.1 studs. An eight-sided ash haft with a slight taper. The head is a box plus a flared trapezoid bit, with a square poll at the back; a leather band at the grip. | dark forged iron with a bright honed edge, ash, rawhide; Timberline | hung head-down at the belt | ~1,000 |
| War Club | 2.8 studs. An eight-sided hickory haft and a six-sided iron head ringed with six flat flanges (no spikes); a leather grip and a wrist thong. | wrought iron with rivets, hickory, leather | over the shoulder | ~1,800 |
| Spear | 7 studs. A six-sided ash shaft and a leaf-shaped head made of two mirrored wedges with a centre ridge. A socket ferrule with two rivets, a cord binding at the balance point (where the hand goes) and an iron butt cap. | steel, ash, linen cord | carried upright | ~2,400 |
| Longsword | 3.7 studs. A diamond-section blade (four long facets) with an inset fuller strip. A square-ended crossguard, a cord-wrapped grip of stacked rings and an eight-sided puck of a pommel. | bright forged steel, brass, waxed cord; Ironreach | in a leather scabbard on the left hip | ~2,400 |
| Stones | River stones in three sizes: chamfered blocks of 10–14 sides. A heap is 7–9 of them. They share the granite of the Blender-made pebble ground the style test is building, so a heap reads as part of the ground. | wet, dark granite by the water; pale, dry granite on scree | — | ~200 each; ~1,500 a heap |
| Throwing Knives | 1 stud. A flat blade of all steel and a cord-wrapped grip block, with no guard. | carbon steel, cord | a leather bandolier across the chest that shows how many are left (1–6) | ~800 |
| Sling | Two braided cords (each a chain of six thin blocks) and a cupped leather pouch with stitched edges; a finger loop. | leather, wool cord; Loomhallow | coiled at the belt | ~900 |
| Recurve Bow | Exists (ItemsReal). New: a hip quiver, a leather box tube that shows the nocks of what's inside. | — | across the back, with the hip quiver | built |
| Arrowheads | Field: a four-faceted bodkin. Broadhead: three flat triangular blades set 120° apart. Pitch: a rough block of rag bound with cord and blackened. Whistler: a bone cylinder with two drilled holes. All four on the shared shaft. | steel; rag and pitch; bone | the heads show in the quiver | ~300 each |
| Blowpipe | 4 studs. An eight-sided cane tube with three node rings and a bone mouthpiece block; a dart pouch at the belt. Darts are thin needles with a cotton tuft (Dart) or a wrap of nettle leaf (Nettle Dart). | cane, bone, cotton | across the back | ~900 |
| Citadel Compound Bow | A blocky skeleton riser with cut-outs, black laminated limbs, brass cam wheels (eight-sided discs) and cables. A brass Citadel seal on the riser. | blued steel, black laminate, brass | across the back | ~2,500 |
| Wire Snare | A coil of brass wire (a torus of eight-sided segments) on a whittled six-sided stake. Set, it is a loop on the ground tied to a bent sapling that jerks up when sprung. | brass, green wood | the loop on the ground | ~700 |
| Tripwire Kit | Two stakes, a dark wire between them and a tin can holding pebbles. | tinplate, wood, iron wire | the stakes and the wire | ~600 |
| Fire Kit and campfire | The kit: a hinged tin box, a faceted dark flint, a C-shaped steel striker and a square of char-cloth. The fire: a ring of eight chunky stones round four crossed logs. | tinplate, flint (Quarrymoor), steel; bark and charred wood | the fire, its glow and its smoke | ~700, and ~1,200 for the fire |
| Rope | A coil (a torus of laid-rope segments) with an iron stake. Fixed, it reuses ArenaV3's FixedRope. | hemp, iron | the hanging rope | ~800 |
| Purifying Tablets | A small round tin with a cork and our own printed label; four white tablets. | tinplate, paper, cork | — | ~300 |
| Field Glasses | Two eight-sided barrels on a hinge block, wrapped in leather, with brass rims and a neck strap. | brass, leather, glass (Glasswater lenses) | on the chest; the glint | ~900 |
| Hand Flare | A paper-wrapped cylinder with a brass striker cap. Lit, it gives white-hot light, sparks and smoke. | paper, brass | its light | ~300 |
| Patron parcel | A small block of waxed canvas tied with cord in a cross, with an ember-coloured card tag. | waxed canvas, cord, card | — | ~300 |
| The Spire's racks (W1) | A-frame racks (two trestles and a pole), a low plank table, and canvas tarps on the outer ring. Built from Parts in W1, with no upload; meshed later. | planks with nail heads, canvas | — | Parts at first |

### 2.6 Today's nine weapons in the new list

Every code id stays (`mace`, `sword`, `arrow` and the rest), so saves, loot markers and art templates keep working. Only the names and numbers change.

| Today | Becomes | Decision | What changes |
|---|---|---|---|
| Hunting Knife (Common) | Hunting Knife (Common) | keep, rebalance | 22 → 20 damage; 0.45 → 0.48 s a swing; reach 6 → 4.5. The unseen hit, a quiet swing, and it cuts you out of a snare. Time to down 1.88 → 2.02 s. |
| Machete (Uncommon) | Machete (Uncommon) | keep, rework | 32 → 26 damage; 0.70 → 0.55 s. The sweep catches a second target for 60%. 2.24 → 1.79 s. |
| Hatchet (Uncommon) | Hatchet (Uncommon) | keep, rework | 36 → 34 damage; still 0.80 s; reach 6.5 → 5. It can be thrown (45; 72 to the head) and splits firewood. 1.76 → 1.78 s. |
| Spear (Rare) | Spear (Rare) | keep, rebalance | 30 → 34 damage; 0.85 → 0.70 s; 60% within 4 studs. The throw stays at 60 but flies at 110 studs/s instead of 150. 2.73 → 1.60 s. |
| Mace (Rare) | **War Club** (Uncommon) | rename, rework | 46 → 44 damage; 1.10 → 0.95 s. Armour stops only half as much; it staggers from W2. 2.45 → 2.22 s, and still 2.22 s through any armour. It moves down a tier because it is slow against the unarmoured. |
| Arena Sword (Epic) | **Longsword** (Epic) | rename, rebalance | 40 → 36 damage; 0.75 → 0.62 s; the best guard from W2. 1.65 → 1.40 s. |
| Recurve Bow (Rare) | Recurve Bow (Rare) | keep, rebalance | Headshots go from ×2 to ×1.8 (90). Point-and-shoot aim only inside 60 studs. About 3.5 bows a round instead of about 13, with 5 arrows each instead of 4–8. |
| Arrow (Common) | **Field Arrows** (Common) | rename | They stay where they land (built), but 1 in 3 break on stone or metal. A 12-arrow quiver from W4. |
| Throwing Knife (Uncommon) | **Throwing Knives** (Uncommon) | rename, rebalance | 28 → 22 damage, so 5 hits instead of 4. 160 → 120 studs/s. A hit cancels a draw (W2). |

None of today's weapons is dropped.

### 2.7 Left out on purpose

- **Material grades** (a Worn, a Forged and a Citadel version of each weapon). Rarity already means power. Citadel modifications ([loot-equipment.md](loot-equipment.md) §4) give upgrades within a role that you can see on the model. Three versions of every weapon would make the list harder to read. Look at it again after a month of play.
- **A crossbow.** A third long-range killer would undo the bow's scarcity, and its slow reload makes for dull duels.
- **Night Lenses.** They would be far too strong at night, which is already near black under the trees. The Hand Flare gives light at a price.
- **Carbon and Flare Arrows** (loot-equipment §5.1). Arrows that stay where they land make "recovered more often" pointless, and the Hand Flare already does the Flare Arrow's job.
- **Toxin darts.** Nettle Darts slow you without poison. That keeps us well clear of the source's poison beats and of Roblox's rules on lifelike drugs.
- **The Stake Trap.** Traps stay non-lethal for now: they catch you and raise the alarm (loot-equipment open question 6).
- **A water-fouling event,** which the research suggested. ArenaV3 §6.8 rules out any drought or fouling that leaves only the lake, because that is too close to a source beat. The Vale varies which springs flow from round to round instead.

### 2.8 IP guard rails for this list

- No trident or net. Berries are food. No wasps.
- **Special arrows** are single, plain historical heads: three-blade steel, rag and pitch, a bone whistle. They are never a colour-coded set, never explosive, and no weapon is ever locked to its owner.
- **The border.** Thrown weapons and arrows that reach it stop and fall; nothing bounces back off it.
- **Rope is rope.** No taps for drawing water from trees.
- **Patron capsules** come down under an ember-and-charcoal chute, never a silver one.
- **Packs** are plain canvas or leather, never orange, and the outer ring never lays out one fixed, pre-packed set.
- **Fire** is a tool, never anyone's emblem.
- **The Spire** stays a split monolith: no horn shape, no eye-shaped plaza. The Vale is not a meadow of flowers.
- **The Provinces.** Item descriptions may say where a thing was made ("Ironreach steel"), but no Province has a signature weapon.
- **For Roadmap §7's review list:** colour-coded or explosive arrows, weapons locked to their owner, projectiles reflected by the border, tree taps, an eye-shaped centre and a flower meadow.
- **Outside this plan, for the Roadmap owner:** the Jubilee Games (48 contenders every 25th year) mirror the source's newest film, which opens on 20 November 2026. Change the Jubilee's cadence or size before Phase 9.

---

## 3. Objectives and round flow

### 3.1 The round in acts

Each act has one main goal, and the goal line (§3.9) states it. The timeline is ArenaV3's (§6.5–6.7). Its stages 1 and 2 don't exist on today's arena, where the same acts run without them.

| Act | When | What happens | What you should do | The film beat it echoes, in our words |
|---|---|---|---|---|
| 1 · **The Rise** | the Countdown (10 s) | The plates rise and you stand frozen. The Spire's prizes lie in plain view. | Choose: rush or run. | the plates and the stillness before the start |
| 2 · **The Scramble** | 0:00–0:45 | The horn sounds, and the mix drops to breath, heartbeat and a low tone for about 10 s. | Grab one thing and go, or make for a pale flag. | the rush for the central supplies, against fleeing them |
| 3 · **Day One** | 0:45–4:10 | 1:30: Patron Requests begin. 2:30: stage 1's warning and the Lure (v3). 3:30–5:00: stage 1 closes the Reaches (v3). | Arm yourself, find water, gear up, and choose where to spend the night. | water first; scattering across the arena |
| 4 · **Dusk** | 4:10–5:45 | The light starts to go. 4:15: the afternoon's Warden event. At 5:45 the Roll Call draws the fallen in the sky. | Get out of sight, and count who's left. | the nightly tally of the fallen |
| 5 · **The Night** | 5:45–8:10 | Cold and dark, with Cold Snap or the Night Hunt about 6:40. Truces form round fires. 7:10: stage 2's warning (v3). | Survive. Fire or no fire, hide or hunt. | the cold first night, when a fire buys warmth and costs secrecy |
| 6 · **Dawn** | 8:10–9:50 | The Heart closes at 8:10–9:25 (v3). The Offering's warning at 8:20. | Move in, and decide whether you need the Offering. | the arena herding everyone together |
| 7 · **The Offering** | 9:50 | The Spire restocks with what the living need, and there is not enough for everyone. | Go if you need it; set an ambush if you don't. | the restock at the centre that draws everyone in |
| 8 · **The Closing** | 10:00–13:50 | The border closes on the Spire, with Warden events at 10:30 and 12:00. | Fill up, heal, stay inside. | the closing net |
| 9 · **The Last Stand** | 13:50, or from W5 as soon as three remain (§3.8) | The ring closes to nothing beside the Spire. | Outlast them. | the finale |
| 10 · **The Laureate** | Ending | One winner, always, and the epilogue Roll Call. | — | one victor |

### 3.2 The Rise and the Scramble: the opening choice

**The Spire becomes a visible value gradient.** Today its prizes are shut in crates, so "RUSH THE SPIRE FOR WEAPONS" asks for a blind choice. In the new layout every plate sees three rings:

| Ring | Where | What lies there | The choice it offers |
|---|---|---|---|
| **The outer ring** | 8–15 studs in from the plates, on canvas tarps: 8 clusters, one between every three plates | Each cluster holds a Water Bottle and one of: a Bandage, a pair of Throwing Knives, a heap of 4 Stones (from W3), or (from W4) a Satchel | Grab in 2–3 s and go |
| **The steps** | 25–35 studs in, on wooden racks and a plank table: in place of v3's 6 tier-3 ground markers, or on today's map 6 of the 10 plaza crates (today has no tier-3 ground markers) | 2 Machetes, 2 Hatchets, a War Club, 2 Spears, a Recurve Bow with 5 arrows, 6 Field Arrows and 2 Leather Vests | The weapons are in plain view: a real bet |
| **The alcoves** | the Spire's 4 crate slots, plus the 4 plaza crates | One alcove always holds a Longsword. The rest roll Padded Armor, Med Kits, at most one more bow, special arrows, a Rucksack, a Fire Kit, Rope and Field Glasses. | The best kit, deepest in |

- **The sound.** At the horn the music and world sound duck to breath, heartbeat and our own low tone for about 10 s.
- **The runner's caches** (built, QW7) keep their pale flags. Each now holds:
  - one weapon: a Hunting Knife (40%), two Throwing Knives (40%), a Hatchet (10%) or a Sling with 4 stones (10%; until W3 the knife takes its share);
  - a Water Bottle;
  - one roll of ground loot.
- **The tuning target:** 25–40% of a full lobby down by 2:30. Telemetry logs deaths by act. If fewer fall, the rush isn't a bet; if more fall, too many players sit out the round.
- **Small rounds stage less.** Today every Spire crate fills whatever the headcount, so 2 contenders find about 47 stacks between them and the choice disappears. Each Spire placement now scales at one per three contenders (N), with floors:
  - tarps: N ÷ 3, rounded up (at least 2, at most 8);
  - rack weapons: N ÷ 3, rounded up (at least 3, and the bow is always one); one Leather Vest below 12 contenders;
  - alcoves and plaza crates stocked: N ÷ 3, rounded up (at least 2, at most 8);
  - the guaranteed Longsword needs 8 or more contenders.

  With 24 that is exactly the layout above; with 4 it is 2 tarps, 3 rack weapons and 2 crates.

### 3.3 Day One: water, a kit, a place for the night

- **Water comes first.** Thirst empties in 9 minutes, or about 6 while sprinting. Every runner finds a bottle at a flag, and from 60 thirst down the goal line points to the nearest water, by name in v3 (Greenbrook, North Beach).
- **The kit ladder.** When nothing is pressing, the day-one goal names the first thing you lack: healing, then a water bottle, then armour (§3.9, P14).
- **Places for the night:** caves, the Millrace, the Old Redoubt's cellar, the Hunters' Rest, camps, the Watchtower and the giant trees (v3). Today's arena has the three caves, the hunter's cabin, the campsites and the Watchtower.
- **Warden events** (Roadmap Phase 2a). Every event is also a goal: its action becomes the goal line (§3.9, D2–D8).
- **Patron Requests** begin at 1:30 (§3.10).

### 3.4 Dusk, the Roll Call and the night

- **4:10:** a short card, "THE LIGHT IS GOING · Find shelter before dark". The goal points to the nearest shelter.
- **5:45, Roll Call 1** (built). After it, a card: "4 FELL TODAY · 9 REMAIN", with "The night begins · The Offering waits at the Spire on the second morning". Contenders now plan their night around the Offering.
- **Fire is the night's big choice.** A fire warms you through Cold Snap, heals you twice as fast and lights Pitch Arrows. Its glow also shows from about 300 studs, and its smoke by day. The first time you light one, a tip: "Your fire warms you and heals you faster, but everyone can see it."
- **The night event** is Cold Snap or the Night Hunt ([arena-events.md](arena-events.md)). In v3 about 26 warmth sources lie inside the night ring, and player fires add to them.
- **Truces** (PlayabilityPlan B12, phase W5) form round fires. They end on damage, when the Offering's bell rings, or when four are left. B12 also ended them when the border starts moving; with v3's first stage at 3:30 that would be far too soon, so the Offering's bell, ten seconds before the final closing, takes its place.
- **The Knell** (Roadmap Phase 1) replaces the cannon. Proposed addition: each toll also puts out one of the fire-cups round the Spire's Beacon (one per contender, 24 in a full round), so the count of the fallen reads from anywhere in the Vale.

### 3.5 Patrons and Favour

Favour and Patron capsules arrive in Roadmap Phase 3. Most of the design stays as arena-events.md §7 and loot-equipment.md §7.5 have it:
- capsules at 100, 250 and 450 Favour;
- contents that follow your need;
- an ember-and-charcoal chute;
- no weapon once you hold one of Rare or better, and **never a bow**, the Legendary bow included (loot-equipment §7.5 allowed a bow from Fine capsules up; that goes, to keep bows scarce).

Two changes:
1. **Notes that coach.** Every capsule note is a short, true tip about your situation, generated from the same state as the goal line. For example: "Clean water 60 m north-east." "Your bottle is empty." "Someone has been following your tracks."
2. **Favour for survival craft as well as fights:**
   - +10 for your first drink from a stream;
   - +10 for your first fire;
   - +20 for each night survived;
   - +20 to +40 for each Patron Request.

   Today's design leaves a quiet player near 90 Favour, short of the first capsule. With these awards, quiet players reach it too.

### 3.6 The Offering

**It stays at 9:50, as ArenaV3 keeps it.** Its warning moves to 8:20, 90 s ahead (`FeastWarning` 45 → 90, ArenaV3 task T3). What changes is how it reads and what it holds, so that going is a gamble and not just the way the border pushes you anyway:

- **It's announced at the Roll Call,** four minutes ahead, so contenders plan for it through the night.
- **Its stakes are public.** During the warning, line 2 lists what was actually put out: "THE OFFERING · MEDICINE · ARROWS · BLADES · 1:30".
- **There's never enough for everyone (from W5).** In W1 the steps' rack gets a fresh bow (within the bow cap), and the alcoves and plaza crates stocked at the start (§3.2) restock from an Offering table. From W5 the number of prizes is half the living, rounded down, plus one, but always fewer than the living and at most 8: 2 living get 1 prize, 4 get 3, 10 get 6, and 14 or more get 8. They are chosen by what the living need:
  - Med Kits and bandages for the wounded;
  - full quivers for archers who are low;
  - blades for anyone holding only fists or a knife;
  - water for the thirsty.

  The round's Legendary roll (50%, if none has appeared yet) comes on top.
- **Never personal.** No pack is labelled for anyone, and nothing carries a name.
- **The HUD fix.** Today's line "THE OFFERING · THE SPIRE IS RESTOCKED" can never show, because the border's branches in `HUDController.eventLine` return first. Give the Offering's window priority on line 2.
- **Truces end at the bell.**

### 3.7 Warden events

- **They slot into the acts** as ArenaV3 §6.7 re-bases them:
  - 2:30: the Lure only (v3);
  - 4:15: the first big hazard;
  - the night event;
  - no dawn slot while stage 2 moves;
  - 10:30 and 12:00.
- **Every event is also a goal** (§3.9, D2–D8). The event's own warning card and threat line stay as arena-events.md §8 has them; the goal line repeats just its one action.
- **No water event.** There is no drought or fouling event (§2.7). Brackish water stays where it is (the Sump, the Drowned Pines, the reeds), and Purifying Tablets are its answer.

### 3.8 The closing border and the Last Stand

- **As built (QW14):** the final closing runs 10:00–13:50, then the Last Stand closes the ring to nothing beside the Spire by about 14:45. A timeout goes to the healthiest contender.
- **New in W5, a headcount trigger.** It fires once three or fewer remain, at least two have fallen, and Roll Call 1 has passed:
  1. The Knell tolls once at each survivor's position. That gives a direction to listen for, not a ping on a map.
  2. The border warning plays.
  3. 30 s later the border closes on the Last Stand point at up to half a jog (6.5 studs/s, ArenaV3's speed limit).

  Rounds that start with 4 or more no longer drag on once the field thins, and the end always comes to the last three. A round that starts with 2 or 3 can never have two fallen, so it relies on PlayabilityPlan B3's faster clock instead (a round of 2 runs about 6:50). B3 should land before W5's playtests.
- **One Laureate, always.** No shared win, and no standoff.

### 3.9 The objective tracker

**Layout**
- **Two lines under the compass,** centred in the HUD's top band:
  - **Line 1, GOAL.** Off-white Oswald. The most important thing to do now, plus a detail: a distance, the button to press, or what you lack. In danger it turns ember. A matching marker sits on the compass, one at a time: water, a pale flag, shelter, a fire, the Spire, a Request's place or the border.
  - **Line 2, NEXT.** Today's event line with "NEXT ·" in front. It is dim while the beat is more than a minute away and ember inside the last minute.
- **The OUTSIDE THE BORDER alert folds into line 1,** in the danger tone, so the band never holds more than two lines.
- **Phones** show the short form of line 1, and line 2 only in its last minute.
- **A setting** under Settings → Interface: Objective line **Full** (the default), **Goal only** (no distances and no markers) or **Off**. Danger goals always show.
- **New players** (Guidance Auto, built: Q1) get the button in the detail. After 3 real rounds the button drops out.
- **No flicker.** The goal is worked out every 0.25 s but changes at most once every 2 s, except for danger.
- **No overlap with ArenaV3's compass** (§5.8), which already shows the region's name and the sites you've seen. The goal line doesn't repeat them.
- **The marker logic replaces QW10's water drop,** so there is one code path for every goal marker.

**Which goal wins.** The groups go in order: Danger (D), then Body (B), then Phase and need (P). Within a group, the first row that applies wins.

**The goal line, exact wording**

| # | When | Goal line (PC and gamepad) | Phone | Compass marker | Ends when |
|---|---|---|---|---|---|
| D1 | You're outside the border | GET BACK INSIDE THE BORDER · 42 m | BACK INSIDE · 42 m | the border | you're inside |
| D2 | You're inside Ember Rain | GET UNDER STONE OR LEAVE · EDGE 30 m | UNDER STONE · 30 m | the zone's edge | you're covered, or out of it |
| D3 | The Miasma covers your head | CLIMB OUT OF THE MIASMA | CLIMB OUT | — | your head is above it |
| D4 | The Floodgate's reach | GET ABOVE THE WATERLINE | GET HIGH | — | you're above it |
| D5 | Rockfall's stretch | GET OFF THE SCREE | OFF THE SCREE | — | you're off it |
| D6 | A sealed sector | LEAVE THE SEALED SECTOR · 60 m | LEAVE · 60 m | the nearest way out | you're out |
| D7 | Cold Snap, with Warmth under 40 | GET WARM · FIRE 120 m | WARM UP · 120 m | the nearest fire | Warmth is over 60 |
| D8 | A Splice hound is hunting you | HUNTED · CLIMB, SWIM OR FIGHT | HUNTED | — | the hound gives up or falls |
| D9 | You're snared | WRIGGLE FREE · TAP [E] | TAP [E] | — | you're free |
| B1 | You're Bleeding (W4) | STOP THE BLEEDING · [4] BANDAGE, or STOP THE BLEEDING · FIND A BANDAGE | BANDAGE [4] | — | the bleeding stops |
| B2 | Health is under 35% | PATCH UP · [4] BANDAGE, or with nothing to heal BREAK OFF · HIDE AND RECOVER (BREAK OFF · EAT AND DRINK TO HEAL when hunger or thirst is 55 or less, since health only comes back above that) | HEAL UP | — | health is over 50%, or 20 s pass |
| B3 | Thirst is 25 or less | DRINK NOW · [3] WATER BOTTLE, or with nothing to drink DRINK NOW · WATER 80 m | DRINK · 80 m | water | thirst is over 40 |
| B4 | Hunger is 25 or less | EAT NOW · [2] APPLE, or with no food FIND FOOD · CRATES AND CAMPS | EAT, or FIND FOOD | — | hunger is over 40 |
| P1 | You're on your plate | RUSH THE SPIRE · OR RUN FOR A PALE FLAG | SPIRE OR FLAG | the Spire and the flags | the horn |
| P2 | The first 45 s, within 70 studs of the Spire | GRAB WHAT YOU CAN · THEN GET OUT | GRAB AND GO | — | 0:45, or you're 70 studs out |
| P3 | The first 45 s, running | REACH A PALE FLAG · 60 m | PALE FLAG · 60 m | the nearest unopened cache | it's opened, or 0:45 |
| P4 | The Last Stand | OUTLAST 2 MORE; with one rival left, ONE RIVAL LEFT | the same | — | the end |
| P5 | The final closing is moving | STAY INSIDE THE BORDER · HEAD FOR THE SPIRE, or within 120 m of its edge STAY INSIDE · BORDER 42 m | STAY INSIDE | the Spire, plus a tick at the edge | the Last Stand |
| P6 | A border stage is moving (v3) and you're outside the ring it closes to | MOVE IN AHEAD OF THE BORDER · 140 m | MOVE IN · 140 m | the edge of the new ring | you're inside it |
| P7 | You hold only your fists | ARM YOURSELF · PALE FLAG 60 m, or · STONES AT THE WATER 40 m (from W3), or · OPEN A CRATE | ARM YOURSELF | the flag or the stone heap | you hold any weapon |
| P8 | Thirst under 60, with nothing to drink | FIND WATER · 140 m (v3 names it: FIND WATER · GREENBROOK 140 m) | WATER · 140 m | water | you drink or fill a bottle |
| P9 | From 60 s before sunset until the Roll Call | FIND SHELTER BEFORE DARK · CAVE 210 m | SHELTER · 210 m | the nearest shelter | you're inside one, or the Roll Call starts |
| P10 | The Roll Call is on | LOOK UP · THE ROLL CALL | LOOK UP | — | the show ends |
| P11 | Night | SURVIVE THE NIGHT · STAY OUT OF SIGHT; by your own fire SURVIVE THE NIGHT · YOUR FIRE CAN BE SEEN; in Cold Snap SURVIVE THE NIGHT · STAY WARM | SURVIVE THE NIGHT | — | dawn (8:10) |
| P12 | From the Offering's warning to 60 s after it | THE OFFERING · MEDICINE AT THE SPIRE if you're under 60% health; · ARROWS AT THE SPIRE if you hold a bow with fewer than 6 arrows; · BLADES AT THE SPIRE if you hold only fists or a knife; otherwise THE OFFERING · RISK IT OR HIDE | OFFERING · MEDICINE (and so on) | the Spire, pulsing | the window ends |
| P13 | From 9:25 until the final closing starts | GET READY · FILL YOUR BOTTLE (if it's empty), or GET READY · HEAL UP (if you're under 70%) | GET READY | water | the closing starts |
| P14 | Day one, with nothing above | GEAR UP BEFORE DUSK · NO HEALING YET (then · NO WATER BOTTLE YET, then · NO ARMOUR YET) | GEAR UP | — | you hold all three |
| P15 | Nothing at all is pressing | HUNT OR HIDE · 17 REMAIN | HUNT OR HIDE | — | — |

Notes on the table:
- **The border and the finale come first.** P4–P6 outrank the needs below them, because the border and the Last Stand won't wait while you arm or drink.
- **Markers point only inside the border** as it will be 60 s from now. A shelter, fire or spring beyond the closing ring (the bothy and the ranger station at night, for example) never becomes the goal.
- **Slot numbers** ("[4]") are the slot the item sits in. Once PlayabilityPlan B2's HEAL button exists, B1 and B2 read "[H] BANDAGE".
- **Every number and name comes from the game's data.** Distances come from `Shared.WaterPoints` and `ArenaLayout`, item names from `ItemDefs`, and place names from `Shared.Lore`. A retune or a rename changes the text by itself.

**The next line, exact wording**

| Coming up | Line 2 |
|---|---|
| The Roll Call | NEXT · ROLL CALL AT DUSK · 3:12 |
| A border stage (v3) | NEXT · THE BORDER MOVES · 0:45 |
| The Offering, more than 90 s away | NEXT · THE OFFERING · 4:05 |
| The Offering's warning, its last 90 s | THE OFFERING · MEDICINE · ARROWS · BLADES · 1:30 (listing what was actually put out) |
| The Offering is open | THE OFFERING · THE SPIRE IS RESTOCKED |
| The final closing | NEXT · THE BORDER MOVES · HEAD FOR THE SPIRE · 0:30 |
| The Last Stand | NEXT · THE LAST STAND · 1:20 |
| A Warden event (W5) | NEXT · EMBER RAIN · OVER THE TALLGRASS · 0:18 (arena-events.md §8) |
| A Patron Request, when no beat is within 60 s | REQUEST · DRINK AT THE GREAT FALLS · +25 (in W3, before Favour exists: REQUEST · DRINK AT THE GREAT FALLS · A GIFT) |

**Act cards.** These are short `Announce` cards, one per act change. The horn itself gets none: QW6 keeps the first sprint clear.

| When | Style | Title | Sub-line |
|---|---|---|---|
| 4:10, 60 s before sunset | Toast | THE LIGHT IS GOING | Find shelter before dark |
| After Roll Call 1 | Banner | 4 FELL TODAY · 9 REMAIN | The night begins · The Offering waits at the Spire on the second morning |
| 8:20, the Offering's warning | Warning | THE OFFERING | Medicine, arrows and blades at the Spire · not enough for everyone |
| 9:50 | Banner | THE OFFERING | The Spire is restocked (built) |
| The headcount trigger (W5) | Banner | THREE REMAIN | The Last Stand begins |
| The first time you light a fire | Toast | YOUR FIRE | Warmth and faster healing · everyone can see it |
| Your truce ends (W5) | Toast | TRUCE OVER | — |

### 3.10 Side goals: Patron Requests

These are optional goals that reward exploring.
- **One at a time.** At most one new offer every 90 s, from 1:30 until the final closing starts, and none during a Roll Call or the Offering's window (arena-events.md §3's quiet times).
- **Safe to follow.** A Request never sends you into an active Warden zone, or outside the border as it will be in 2 minutes.
- **The reward.** In W3 a Request pays a **Patron parcel**, whose tool follows your need (§2.4). From W5 it also pays Favour.
- **The parcel** drops beside you when you complete the Request, so nobody can camp it at the place. Only you can open it for its first 10 s (0.8 s, [E]), as with a Patron capsule (arena-events.md §7); after that, anyone can.
- **Limits, so Requests don't flood the Vale with loot.** Each contender completes at most 3 a round, and once 12 parcels have dropped in a round the Director stops offering parcel Requests (from W5, Favour-only Requests carry on).
- **The wording.** When offered: "A PATRON ASKS · DRINK AT THE GREAT FALLS", with the sub-line "+25 Favour · a gift when you get there". When done: "+25 FAVOUR · you drank at the Great Falls".

| Request (exact) | The place (v3 · today's arena) | Offered when | Reward |
|---|---|---|---|
| DRINK AT THE GREAT FALLS | the Cauldron (9) · the falls pool | day one, thirst under 80 | +25; a parcel |
| CLIMB THE LONE ELDER | its crown hide (1) · a tall Climbable tree | day one | +20; a parcel |
| CLIMB THE WATCHTOWER | the cab (13) · the Watchtower | day one | +20; a parcel. The fixed bow rack is up there too, if nobody has beaten you to it. |
| SHELTER IN THE SINKHOLE BEFORE DUSK | the Sinkhole (6) · any cave | 3:30–5:45 | +30; a parcel |
| LIGHT A FIRE BEFORE DUSK | anywhere | you carry a Fire Kit; before 5:45 | +30 |
| CROSS THE THROAT BY ITS ROPE BRIDGE | the Upper or Lower Swing (8) · the gorge footbridge | day one | +20; a parcel |
| SWIM TO KETTLE ISLAND | Kettle Island (14) · the lake island | day one | +20; a parcel |
| WALK ECHO RUN | the cave through the ridge (18) · — | day one | +25; a parcel |
| REACH THE FIRE LOOKOUT | Lantern Peak (22) · — | inside the ring only | +30; a parcel |
| FIND THE HIDDEN SPRING | the spring (28) · — | inside the ring only | +30; a parcel |
| OPEN A RUNNER'S CACHE | the nearest flag | the first 2 minutes, if you ran | +10 |
| CLAIM THE LURE | the Lure | while it falls (arena-events.md) | the Lure's own +25 (arena-events.md §7), not paid twice; no parcel |
| BRING DOWN A SPLICE | — | during a Splice Hunt | the hunt's own +15, or +40 for the Packleader; no parcel |
| CATCH SOMEONE IN YOUR SNARE | — | you've set a snare | +20 |
| BRING DOWN THE MARKED | a rough bearing (a 45° arc, refreshed every 30 s) | after Roll Call 1 (W5) | a Gilded capsule (loot-equipment.md §9) |

**Marked by the Wardens (W5).** After Roll Call 1, the contender with the most kills is Marked, if they have at least 2; with nobody on 2, nobody is Marked. Ties go to the one with more Favour.
- The Marked contender sees "YOU ARE MARKED · The others know roughly where you are".
- They earn +5 Favour for every 30 s they survive while Marked.
- The Mark ends when they fall or when the Last Stand begins.

### 3.11 After you fall: the audience (W5)

A third or more of a lobby can be out by 2:30, so the fallen get a part in the show, much as audiences back contenders in the source.

- **The death card** gets BACK A CONTENDER, next to SPECTATE (which opens on your killer; built) and CONTINUE.
- **Backing a contender.**
  - You get one free token a round. It brings your chosen contender's next Patron capsule 25 Favour closer. At most 3 tokens count for any one contender.
  - They see "A FALLEN CONTENDER BACKS YOU".
  - You can't back someone in your own party (PlayabilityPlan B12), so friends can't funnel Favour to each other.
  - This replaces arena-events.md §7's backing (+10% Favour gain per backer, up to +50%), because a flat 25 shows on screen at once.
- **The vote.** 15 s before a Warden slot, spectators see two cards, for example "EMBER RAIN · THE TALLGRASS" against "THE FLOODGATE · THE THROAT". When both are eligible, the Director runs the winner.
- **The rules.** Never for Robux. Nothing bought ever changes a number. A vote picks a zone, never a contender.
- **Scheduling.** The Roadmap puts spectator backing and the event vote in Phase 10. This plan brings them forward to W5, beside Phase 3's Favour, which needs your yes (§7, Q4).

---

## 4. Onboarding: the first round teaches it all

### 4.1 In the lobby

- **One line under the title on every device:** "LAST ONE STANDING WINS · Rush the Spire or run". It replaces "Outlast everyone.", so phones, where HOW TO PLAY doesn't open by itself, get the goal too.
- **HOW TO PLAY** keeps its three-step line on PC (QW6).

### 4.2 Alone on a server: the Drill

The live practice round (QW1) becomes a guided drill of 3–5 minutes on the real arena. It is called the Drill because "Trial" already names the Daily Trials (Roadmap glossary). It first needs a fix: `CombatService.Start` wires the dummies only inside `if Config.IsStudio`, so on a published server none ever appears. Move that wiring out, and keep only the dev hooks Studio-only.

| Step | Goal line (exact) | Placed for the Drill | Done when |
|---|---|---|---|
| 1 | OPEN THE CRATE · 12 m | a tier-1 crate 12 studs ahead of your plate | you open it |
| 2 | TAKE A WEAPON FROM THE RACK · 20 m | a rack with a Hunting Knife, a Spear, and a Recurve Bow with 5 Field Arrows; a stone heap beside it (from W3) | a weapon is in your hand |
| 3 | STRIKE A DUMMY · [LMB] | the 3 training dummies | three hits land |
| 4 | THROW THE SPEAR · [RMB] + [LMB], or (from W3) THROW A STONE · [LMB] | the spear on the rack, or the stone heap | a throw hits |
| 5 | SHOOT A DUMMY · HOLD [LMB] TO DRAW | the bow on the rack | an arrow hits |
| 6 | DRINK AT THE WATER · 60 m | the nearest water point, with its marker | you take a sip |
| 7 | CLIMB A TREE · PUSH FORWARD INTO IT | the nearest climbable tree within 40 studs | a climb starts |
| 8 | READY · A FULL ROUND STARTS WHEN CONTENDERS ARRIVE | — | — |

- **It never stalls.** Doing a later step first ticks the earlier ones, and each step moves on after 45 s anyway.
- **Arrivals.** When someone arrives, QW1's hand-off still ends the practice 60 s later.
- **Telemetry.** Each step is an onboarding funnel step (`OnboardingService`), so you can see where newcomers stall.

### 4.3 The first real rounds

PlayabilityPlan B6's three "First Steps" (open a crate, eat or drink, survive to the first Roll Call) become the first round's natural goal lines, not a separate list. Finishing all three still earns the "First Dusk" badge once Phase 5's badges exist.

| Moment | What teaches it | Exact text |
|---|---|---|
| On the plate | the goal line, and the plate caption (built) | RUSH THE SPIRE · OR RUN FOR A PALE FLAG |
| The horn | the mix drops for about 10 s; the sprint hint (built) | [SHIFT] SPRINT |
| The first pickup of each weapon | the weapon card (§4.4) | e.g. HATCHET · UNCOMMON / 3 HITS · [RMB] + [LMB] THROW |
| Holding it | the action hint under the crosshair, which fades after 3 uses (built; now for melee too) | [LMB] SWING · 3 HITS |
| Thirst under 60 | the THIRSTY card (built), then the goal | FIND WATER · 140 m |
| The first time you look at brackish water | a hint at the water | BRACKISH WATER · IT WILL MAKE YOU SICK · TABLETS CLEAN IT |
| The first fire you light | a short card | YOUR FIRE · Warmth and faster healing · everyone can see it |
| 4:10 | an act card | THE LIGHT IS GOING · Find shelter before dark |
| The first Roll Call | the goal line | LOOK UP · THE ROLL CALL |
| After it | an act card | 4 FELL TODAY · 9 REMAIN |
| The first Offering | the goal, set by your need | THE OFFERING · MEDICINE AT THE SPIRE |
| The first death | a death tip naming the counter (§4.5) | see below |
| From round 4 | the goal line drops the buttons; the weapon cards keep their compare line | — |

### 4.4 Weapon cards (exact wording)

- **When it shows.** The card appears above the hotbar when you pick a weapon up, or hover it in the hotbar.
- **What's on it.** Line 1 is the name and the rarity. Line 2 comes from `ItemDefs`, so it stays true after any retune.
- **The compare line.** A third line compares it with the weapon in your hand (unarmoured time to down, and reach), and is left out when they're equal, for example "▲ KILLS FASTER · ▼ SHORTER REACH".
- **Where it lives.** The card replaces the first-pickup description in `HUDController.flashItemName`.

| Item | Line 1 | Line 2 |
|---|---|---|
| Hunting Knife | HUNTING KNIFE · COMMON | 5 HITS · DOUBLE FROM BEHIND · QUIET |
| Machete | MACHETE · UNCOMMON | 4 HITS · SWEEPS TWO |
| Hatchet | HATCHET · UNCOMMON | 3 HITS · [RMB] + [LMB] THROW |
| War Club | WAR CLUB · UNCOMMON | 3 HITS · ARMOUR HARDLY HELPS · SLOW |
| Spear | SPEAR · RARE | 3 HITS · LONGEST REACH · [RMB] + [LMB] THROW |
| Longsword | LONGSWORD · EPIC | 3 HITS · THE BEST BLADE (from W2: · [RMB] GUARD) |
| Stones | STONES · COMMON | [LMB] THROW · SPOILS A DRAW · MORE BY THE WATER |
| Throwing Knives | THROWING KNIVES · UNCOMMON | 5 HITS · [LMB] THROW · PICK THEM UP |
| Sling | SLING · UNCOMMON | HOLD [LMB] TO WHIRL · USES STONES · SPOILS A DRAW |
| Recurve Bow | RECURVE BOW · RARE | 2 BODY SHOTS · HOLD [LMB] TO DRAW · 5 ARROWS |
| Blowpipe | BLOWPIPE · RARE | SILENT · [LMB] PUFF · NETTLE DARTS SLOW |
| Citadel Compound Bow | CITADEL COMPOUND BOW · LEGENDARY | 2 BODY SHOTS · THE FASTEST DRAW · QUIET |
| Wire Snare | WIRE SNARE · UNCOMMON | HOLD [LMB] TO SET · HOLDS A LEG |
| Tripwire Kit | TRIPWIRE KIT · UNCOMMON | SET TWO STAKES · RATTLES WHEN CROSSED |
| Fire Kit | FIRE KIT · UNCOMMON | HOLD [LMB] TO LIGHT · WARMTH AND HEALING · SEEN FROM FAR |
| Rope | ROPE · UNCOMMON | AT A LEDGE, HOLD [LMB] · CLIMB DOWN SAFELY |
| Purifying Tablets | PURIFYING TABLETS · UNCOMMON | FILL A BOTTLE AT BRACKISH WATER · IT COMES OUT CLEAN |
| Field Glasses | FIELD GLASSES · UNCOMMON | HOLD [RMB] · SEE WHAT THEY CARRY |
| Hand Flare | HAND FLARE · UNCOMMON | [LMB] THROW · LIGHT FOR 25 s |

### 4.5 Death tips that teach the counter (exact wording)

These extend QW4's tips in `NotificationController`, chosen by the killing weapon. The second line shows the second time the same weapon kills you. Today's tips for thirst, hunger, the border, falls, the spear's throw and throwing knives stay.
- **Numbers come from the data.** Every number in a tip is read from `ItemDefs` and `Config`, as QW4's tips are, so a retune changes the text. Tips speak metres, never studs.
- **Tips follow the build.** A tip that names the flinch (a stone, a knife or a sling stone spoils a draw) shows only once W2 has shipped it; until then the bow keeps QW4's tips.

| Killed by | First time | Second time |
|---|---|---|
| Hunting Knife, from behind | A knife hits twice as hard on someone who isn't looking. When you stop, put your back to a tree or a rock. | Crouched footsteps are quiet. Look behind you before you open a crate. |
| Hunting Knife | A knife needs 5 hits and has the shortest reach. Keep it at a spear's length, or out-hit it with a hatchet or a War Club. | — |
| Machete | A machete's sweep catches two at once. Don't fight beside a rival in front of one. | A machete reaches less than a spear. Fight it from a spear's length, and make it swing at air. |
| Hatchet | A hatchet downs you in 3 but swings slowly. Step back after each chop and strike in the gap. | — |
| Hatchet, thrown | A thrown hatchet hits for 45 and leaves their hand. Close in before they fetch it. | — |
| War Club | Armour hardly helps against a club. Stay out of its long swing, and strike while it recovers. | — |
| Spear, in melee | A spear outreaches every blade, but within 2 steps it's clumsy. Get inside its reach. | — |
| Longsword | The Longsword is the best blade in the Vale. Don't duel it: throw, shoot, or wear its owner down. | — |
| Recurve Bow | A stone, a throwing knife or a sling stone spoils a draw. Listen for the creak, then break line of sight. | A full-draw arrow hits for 50, and 90 to the head. Move from tree to tree, and never stop in the open. |
| Sling | A sling must whirl before it throws. Close the distance while you can hear it. | — |
| Stones | A stone barely hurts, but it spoils your aim. Don't draw a bow in the open while someone is throwing. | — |
| Blowpipe | Nettle darts slow you for 5 seconds. A blowpipe is quiet, not far-reaching: break line of sight. | — |
| Killed while snared | Snares glint when you're close (about 2 m). On trails, walk crouched and watch the ground. | — |
| Burning (W4) | Fire goes out in water. Step into a stream or the lake. | — |
| Bleeding (W4) | Each bandage stops one bleeding wound. Carry two, and bandage before you run. | — |

---

## 5. Balance tables

All values are for a 100-health contender. "Hits · time" counts from the first wind-up (light hits only, unless a row says otherwise). Today's numbers use the live `ItemDefs`.

### 5.1 Melee: time to down

Armour uses the multipliers in §2.2. The War Club ignores half of any armour.

| Weapon (rarity, type) | No armour | Leather Vest | Padded Armor | Today, no armour | Today, Leather / Padded |
|---|---|---|---|---|---|
| Fists (blunt) | 13 · 5.46 s | 13 · 5.46 s | 15 · 6.36 s | 13 · 5.46 s | 15 · 6.36 s / 18 · 7.71 s |
| Hunting Knife (Common, cut) | 5 · 2.02 s | 7 · 2.98 s | 8 · 3.46 s | 5 · 1.88 s | 6 · 2.33 s / 7 · 2.78 s |
| Hunting Knife, unseen first hit | 4 · 1.54 s | 6 · 2.50 s | 7 · 2.98 s | — | — |
| Machete (Uncommon, cut) | 4 · 1.79 s | 5 · 2.34 s | 6 · 2.89 s | 4 · 2.24 s | 4 · 2.24 s / 5 · 2.94 s |
| Hatchet (Uncommon, chop) | 3 · 1.78 s | 4 · 2.58 s | 5 · 3.38 s | 3 · 1.76 s | 4 · 2.56 s / 4 · 2.56 s |
| War Club (Uncommon, blunt) | 3 · 2.22 s | 3 · 2.22 s | 3 · 2.22 s | 3 · 2.45 s (Mace) | 3 · 2.45 s / 4 · 3.55 s |
| Spear (Rare, pierce) | 3 · 1.60 s | 4 · 2.30 s | 5 · 3.00 s | 4 · 2.73 s | 4 · 2.73 s / 5 · 3.58 s |
| Spear, within 4 studs | 5 · 3.00 s | 6 · 3.70 s | 7 · 4.40 s | — | — |
| Longsword (Epic, cut) | 3 · 1.40 s | 4 · 2.02 s | 5 · 2.64 s | 3 · 1.65 s (Arena Sword) | 3 · 1.65 s / 4 · 2.40 s |

What the table shows:
- **The ladder now holds** against the unarmoured: Common 2.02 s, Uncommon 1.78–1.79 s, Rare 1.60 s, Epic 1.40 s. The War Club is the deliberate exception: slow against the unarmoured, but the fastest weapon short of the Epic against a Leather Vest, and the fastest of all against Padded Armor.
- **Each triangle shows in the numbers.** Blades beat the unarmoured. The War Club beats armour. Inside 4 studs, the knife and the hatchet beat the spear, and at the spear's reach, the spear beats them.
- **Fists stay far behind,** at 5.5 s or more.

### 5.2 Ranged and thrown

| Weapon | Damage, body / head | Hits to down: none / Leather / Padded | Time, unarmoured |
|---|---|---|---|
| Recurve Bow, full draw | 50 / 90 | 2 / 3 / 3 | 2.00 s (a head shot and a body shot: also 2 shots) |
| Recurve Bow, half draw | 32 / 58 | 4 / 4 / 5 | 2.40 s |
| Citadel Compound Bow, full draw | 54 / 95 (the cap) | 2 / 3 / 3 | 1.40 s |
| Sling, full whirl | 34 / 51 | 3 / 3 / 4 | 3.50 s |
| Throwing Knives | 22 / 35 | 5 / 6 / 7 | 2.25 s |
| Stones | 10 / 20 | 10 / 10 / 12 | 5.60 s: they spoil a draw rather than kill |
| Spear, thrown (once) | 60 / 95 | leaves 40 health; you need another weapon to finish | — |
| Hatchet, thrown (once) | 45 / 72 | leaves 55 health: fetch it, then two chops | — |
| Blowpipe, Dart | 8 / 12 | — (a support weapon) | — |

Every single hit is capped at 95, so no arrow, throw or swing downs a healthy contender alone.

### 5.3 Who wins at what range

Distances run from the attacker's head to the target's body, at W1's effective reach (§2.2). CombatPhysicsPlan phase 2's real reach later shrinks every melee band to about half.

| Distance | Favoured | Why | How the other side wins |
|---|---|---|---|
| 0–4 studs, touching | the Hunting Knife, the Hatchet, the Longsword | quick swings; the spear does 60% this close | step back to a spear's length; guard (W2) |
| 4–10 studs, arm's reach | the Longsword, then the Spear | every blade reaches, and these two down you fastest | get inside 4 studs of a spear; guard (W2); armour |
| 10–15 studs, past the short blades | the Spear (to 14.9), the Longsword (to 13.4), the Machete and the War Club (to 12.4) | the knife (9.9) and the hatchet (10.4) can't reach | close the gap at a sprint; throw |
| 15–30 studs, throwing range | a thrown spear or hatchet, Throwing Knives, the Sling | quick throws | cover; make them throw, then close in |
| 30–60 studs, bow range | the Recurve Bow | point-and-shoot aim | stones, knives and sling stones spoil the draw; listen for the creak; trees |
| Beyond 60 studs | the bow, for a skilled archer | only the bow reaches, with real drop | break line of sight; zig-zag |
| At any range, against armour | the War Club up close; the Broadhead at range (W4) | armour stops only half as much; bleeding ignores armour | keep moving; don't trade blows |

### 5.4 Heavy attacks and the guard (W2)

Phase W2 builds CombatPhysicsPlan phase 1 with these values. Light wind-ups grow to readable lengths, and the TTK harness checks that the ladder in §5.1 still holds in the same order, allowing +0.3 s for the longer wind-ups. Real fights mix in heavy hits and head hits and land at about 1.2–2.0 s.

| Weapon | Light: damage · wind-up | Heavy: damage · wind-up | What the heavy adds | Stamina, light / heavy | Guard lets through |
|---|---|---|---|---|---|
| Fists | 8 · 0.17 s | 15 · 0.40 s | staggers for 0.25 s | 0.04 / 0.08 | 35% |
| Hunting Knife | 20 · 0.19 s | 32 · 0.38 s, a stab | the unseen double applies to light hits only | 0.05 / 0.09 | 25% |
| Machete | 26 · 0.28 s | 40 · 0.56 s, a cleave that catches two | — | 0.08 / 0.14 | 20% |
| Hatchet | 34 · 0.31 s | 52 · 0.60 s | staggers for 0.35 s | 0.09 / 0.15 | can't guard (its Aim is the throw) |
| War Club | 44 · 0.45 s | 66 · 0.80 s | breaks a guard; staggers for 0.6 s | 0.13 / 0.22 | 25% |
| Spear | 34 · 0.30 s | 50 · 0.60 s, a lunge with 0.8 more reach | — | 0.08 / 0.14 | can't guard (its Aim is the throw) |
| Longsword | 36 · 0.28 s | 54 · 0.56 s | a perfect block makes its riposte ×1.3 | 0.08 / 0.14 | **15%** |

Where this table departs from CombatPhysicsPlan, on purpose:
- **A guard goes by the defender's weapon.** CombatPhysicsPlan §3.6 sets what a guard lets through by the attacker's weapon. Here it goes by the weapon doing the guarding, so the Longsword's best guard (15%) is a real job. A weapon whose Aim is its throw (the spear and the hatchet) can't guard.
- **Only the machete sweeps.** CombatPhysicsPlan §3.3 gives the sword a two-target slash too. Here the Longsword hits one target, so the sweep stays the machete's job.

The rules under every weapon, as CombatPhysicsPlan §3.2 and §3.6 have them:
- A guard stops a light attack. A heavy attack (the club's) or a guard run out of stamina breaks it.
- A light hit interrupts a heavy wind-up.
- **The flinch:** a stone, a sling stone, a throwing knife or any melee hit cancels the target's bow draw or heavy wind-up. This widens CombatPhysicsPlan §3.2's interrupt, which needs 15 damage after armour, so a stone (10) still spoils a draw.

### 5.5 Ammo economy

Arrows, throwing knives and thrown spears already stay in the world where they land; GameDesign.md §6 describes the new world-projectile system. So **retrieving ammo, not finding it, is what limits an archer.** You must go and pick it up, often in the open.

| Ammo | Where it comes from in a 24-contender round | Carried | Lost when | Recovered how |
|---|---|---|---|---|
| Field Arrows | ~44 at the start (5 with each bow, 6 on the steps, bundles in crates), ~16 at the Offering, 8 in each capsule for an archer who is low | the hotbar until W4, then the quiver: 12 (16 with a Rucksack, 20 with a Frame Pack) | 1 in 3 that hit stone or metal break | everything else stays where it lands: walk over it, or press [E]. An arrow in a body falls out after ~30 s, or when that body falls. |
| Broadhead | ~3 at the start, ~3 at the Offering | the quiver | 1 in 2 on any hit; never back out of a body | as Field Arrows |
| Pitch Arrow | ~3 + ~3 | the quiver | always used up | — |
| Whistler | ~3 | the quiver | as Field Arrows | as Field Arrows |
| Stones | ~23 as loot, plus heaps at every water point and on scree (3 a gather; a heap refills 60 s after it empties) | a stack of 8 | 30 s after landing (thrown stones crumble; the heaps refill) | walk over them within 30 s |
| Throwing Knives | ~18 at the start | a stack of 6 | never: blades glance off stone and fall | walk over them (built) |
| Thrown spear or hatchet | each one | 1 | never | [E] where it lies (built for the spear) |
| Darts | 8 with each blowpipe; Nettle Darts at the Offering | the quiver | 1 in 2 lost in the grass | [E] |

**An archer's round in numbers**
- You pick up a bow with 5 arrows. To fill a quiver of 12 you open one or two arrow bundles, or collect what's been shot.
- A kill costs about 4 arrows, needing 2 hits at about a 50% hit rate. You get back about 3 of the 4 if you hold the ground afterwards.
- So an archer who wins fights stays supplied, and a hunted archer runs dry. That's the tension we want.
- With about 3.5 bows a round, that comes to roughly 15–20 arrows per bow before recovery.

### 5.6 Loot per round, today and proposed

Both columns are 20,000 simulated rounds on today's markers: 14 Spire crates, 24 tier-2 crates, 8 runner's caches, 6 tier-1 crates and 129 ground markers. The proposed column puts the steps' racks in place of 6 of the Spire's 10 plaza crates (today's map has no tier-3 ground markers; §6.2, W1) and adds the outer ring. It uses the tables in §2.4, with ground spawns at 35% (65% today) and site crates at 2 rolls each.

On the v3 markers, ArenaV3's planner sets the volume (~345 items, ~14 per contender: ArenaV3 §6.1). There, the share of weapons and tools follows these tables, and the caps hold whatever the total.

| | Today | Proposed (today's markers) |
|---|---|---|
| Stacks at the start | ~248 (10.4 per contender) | ~181 (7.5 per contender) |
| At the Spire at the start | ~47, all inside crates | ~50, ~29 of them in plain view |
| Weapon stacks | ~71 | ~43 |
| Bows: at the start + the Offering | ~8.6 + ~4.6 | ~2.5 + 1, plus a 1-in-4 chance of the Legendary |
| Longswords (Arena Swords) | ~3.4 + ~3.4 | ~1.9 + 0.5 |
| Padded Armor | ~2.5, plus more at the Offering | ~0.9 + 0.5 |
| Med Kits | ~2.5, plus ~2.5 at the Offering | ~1.7 + ~2 |
| Arrows at the start / the Offering | ~213 / ~87 | ~44 Field and ~8 special / ~16 Field and ~6 special |
| Water Bottles | ~31 | ~26 |
| Tools: fire kits, ropes, tablets, glasses, flares | 0 | ~3.9, ~3.1, ~8.6 tablets, ~1.8, ~3.6 |
| Traps | 0 | ~6 |

---

## 6. Build plan

### 6.1 Phases at a glance

Each phase splits into tracks that run in parallel: data and code, art, animation and first person, HUD and sound, and QA. Sizes assume agents working in parallel, as in the Roadmap.

| Phase | Goal | Size | Starts after | Where it fits in the Roadmap |
|---|---|---|---|---|
| **W1 · Clear jobs, a visible goal** | the retune, the Spire in plain view, scarcer bows, the goal line, weapon cards, death tips, the Drill | ~1½ weeks; no new meshes | now, with PlayabilityPlan B3 (the clock scaled to the headcount) for small rounds | alongside Phase 1. Its edits to `CombatService`, `CombatController` and `AudioController` are small and additive, because the combat-physics work rewrites those files. |
| **W2 · Fights you can read** | third-person wind-ups, light and heavy attacks, the guard, stagger and the flinch | ~2 weeks | Roadmap decision 3 (§7, Q1) | CombatPhysicsPlan phase 1, inside Phase 1's combat physics |
| **W3 · The improvised kit** | Stones, the Sling, snares and tripwires, the Fire Kit, Rope, tablets, Field Glasses, the Hand Flare, Patron Requests v0 | ~3 weeks of code, with the art alongside | W1; it runs in parallel with W2 (mostly different scripts), but Stones and the Sling ship with or after W2's flinch, because spoiling a draw is their job | brings a slice of Phase 4b forward |
| **W4 · Quiver, arrows and packs** | item state, the quiver, four arrow types, statuses, the blowpipe, packs, the Legendary | ~2½ weeks | W2 (the damage model and the status API) | Phase 4a's quiver and arrows, and Phase 4b's packs |
| **W5 · The living show** | event goals, Requests that pay Favour, the Offering by need, the headcount Last Stand, truces, the Marked, the audience | ~2 weeks | Phase 2a's Director; alongside Phase 3's Favour | Phases 2a and 3 (arena-events.md) |

ArenaV3 runs alongside all five. Its border stages (task T3), its compass and event line (T12) and its water points (T11) touch `HUDController`, `ThreatLine` and `WaterPoints` too, so W1's HUD work layers on top of theirs (§6.4).

### 6.2 The phases, track by track

**W1 · Clear jobs, a visible goal (~1½ weeks)**

| Track | Tasks | Done when |
|---|---|---|
| Data and code | **`ItemDefs`:** the retune and renames (§2.2, §2.6), with a shorter `range` for fists, the knife and the hatchet; new fields `damageType`, `job`, `verb`, `hold`, `armour`, `backstab`, `cleave`, `minRange` and `armourPierce`; `throwable` on the hatchet. **`CombatService`:** armour by damage type, the unseen hit, the machete's second target, the spear's penalty within 4 studs, the club's half-armour rule, every hit capped at 95, and the training dummies' wiring moved out of the Studio-only block. **`InventoryService.absorb(player, damage, damageType)`:** the one armour entry point loot-equipment §11 already names (no integrity until Roadmap 4a), so there is no second, throwaway `getArmorMultiplier` signature. **`Config`:** `BowHeadshotMultiplier` 1.8, `BowAssistRange` 60, `MaxSingleHit` 95, throws at 110 and 120 studs/s. **Loot:** bows out of the tier-2 table; the Spire's three rings and the Watchtower's rack as fixed placements; the alcove and per-round caps, scaled to the headcount (§2.4, §3.2); the Offering table. On today's markers the Spire keeps its 4 crate slots and 4 of its 10 plaza crates; the other 6 are switched off. **`WorldItems`:** a hatchet entry. **`ArenaService`:** the Roll Call's sub-line announces the Offering. | The QA harness passes the ladder (§5.1) and the 95 cap. The loot simulation gives 3–5 bows a round and about 7.5 stacks per contender on today's markers, and a 4-contender run stages 2 tarps, 3 rack weapons and at most 2 bows. A dummy test shows the unseen hit, the machete's second target, the spear's penalty and the club through Padded Armor. A published practice round has its 3 dummies. |
| Art | The Spire's staging, built from Parts in the blockish style with no upload: 2 A-frame racks and a plank table on the steps, 8 canvas tarps on the outer ring, a rack in the Watchtower's cab, and the Drill's rack. | From three different plates, the tarps and the bow on its rack are in plain view (screenshots in the report). |
| Animation and first person | The hatchet keeps its Blade hold (`ViewmodelController` reads the new `def.hold`, because today any throwable melee weapon gets the Spear hold), with a raised aim pose and a throw. Re-run the bow's screen-coverage check. | The hatchet's throw reads in first person, and nothing covers the crosshair area. |
| HUD and sound | A new `Shared.Objectives`; the goal line and its compass marker; "NEXT ·" on the event line; the border alert folded into the goal; the Objective line setting; weapon cards with ▲/▼; a melee action hint, and "CHOP" for the hatchet; the death tips (§4.5); the lobby tagline; the act cards; the Offering line fix (§3.6). Sound: duck the mix at the horn, and quiet the knife's swing. | A unit test passes for all the states in §3.9. The layout harness is clean on PC, phone and gamepad, and the top band never shows more than two lines. |
| QA | `ServerStorage.Dev.WeaponHarness` (time to down from `ItemDefs`) and a loot simulator; a playtest with 4–8 clients; a regression run of QW1–QW15. | Harness and simulation are green. In the playtest at least 80% of runners hold a weapon within 25 s, and at three random moments 5 of 5 testers can say what they should do. |

**W2 · Fights you can read (~2 weeks; after Roadmap decision 3)**

| Track | Tasks | Done when |
|---|---|---|
| Data and code | The server's swing state machine, with wind-ups validated; tap for light, hold for heavy (§5.4); stamina spent; the guard and perfect block (if decision 3 says yes); stagger; the flinch (any stone, sling stone, throwing knife or melee hit cancels a draw or heavy wind-up). | A swing with no wind-up is refused. In a 2-client test a stone cancels a full draw 10 times in 10. |
| Art | — | — |
| Animation and first person | Heavy wind-ups for every swing style, and the guard pose. `CharacterVisuals` plays `CombatAction` on other players: wind-up, swing, draw, throw and guard. Third-person carry poses: the bow on the back with a hip quiver, the spear upright, the club on the shoulder, the sword in its scabbard. | At 100 ms ping, an observer sees a wind-up at least 150 ms before contact (CombatPhysicsPlan's exit test). |
| HUD and sound | GUARD on the weapon cards and hints; the stamina flash. One sound tell per class: the spear's draw-back, the club's scrape, the sword's ring. | In a blind test a listener names the weapon class from its sound 8 times in 10. |
| QA | CombatPhysicsPlan §6's tests; the TTK harness on W2's timings; your feel review. | The suites are green, and you sign off the feel. |

**W3 · The improvised kit (~3 weeks)**

| Track | Tasks | Done when |
|---|---|---|
| Data and code | **New items:** `stones`, `sling`, `wire_snare`, `tripwire`, `fire_kit`, `rope`, `purifying_tablets`, `field_glasses` and `hand_flare`. **A new `KitService`** for placed things (snares, tripwires, campfires, ropes): placement checked on the server, caps, owner pings, cleanup when the round ends, `WarmthSource` tags on fires, and no cutting a rope while someone is on it. **Stone heaps** that refill, and thrown stones that crumble after 30 s outside `WorldItemCap`. **The sling** as a charged weapon, like the bow, that uses stones. **Healing ×2** near a fire. **Tablets** used at brackish water, and brackish water that costs health without one (coordinated with arena-events' Miasma). **Patron Requests v0** (one at a time; a parcel on completion; at most 3 per contender and 12 parcels a round). | A sandbox round shows each tool working, and no parcel drops after a round's 12th. The caps hold: 3 traps each, 40 in the Vale, 8 fires. A second client sees a fire from 300 studs at night and climbs a placed rope. Snares never kill. |
| Art | The IR_Kit set in the ItemsReal pipeline: stones and heaps, the sling, the snare (set and sprung), the tripwire, the fire kit and campfire, the rope (reusing ArenaV3's FixedRope), tablets, field glasses, the hand flare and the Patron parcel. | Every item passes the review renders (close-up and at gameplay distance), and `ad_finalize` reports 0 problems. |
| Animation and first person | Holds: Sling (the whirl) and Raise (the glasses). Use styles: Place (kneel, hands down), Strike (flint and steel), Fix (the rope at a ledge) and Tablet (dropped into the bottle). | Each reads in first and third person, and the coverage check passes. |
| HUD and sound | Hints for the new items (a second `hintsSeen` number); the stones count on the sling's hint; trap pings as a 3 s tick on the compass; the fire, shelter and Request markers; Requests on line 2. Sounds: the whirl, the snap, the rattle, the strike, the crackle and the hiss. | Every new hint shows on PC, phone and gamepad. |
| QA | A regression run for the new items; 24 players with 8 fires and 40 traps on a 3 GB Android phone. | 30 fps holds, with no new console errors. |

**W4 · Quiver, arrows and packs (~2½ weeks)**

| Track | Tasks | Done when |
|---|---|---|
| Data and code | **Item state and the quiver** (loot-equipment §3.2–3.3), with CycleAmmo on R or D-pad right, both already reserved. **Arrows:** the Broadhead, the Pitch Arrow and the Whistler; arrows break 1 in 3 on stone or metal (`WorldProjectiles`). **Statuses** (Bleeding, Burning, Numbed) through `PlayerService`, with no blood. **The blowpipe** and its darts. **Packs:** the Satchel, Rucksack and Frame Pack, the Back slot and 7–9 slots; Satchels join the outer ring. **The Legendary:** the Citadel Compound Bow, from the Offering's and the Lure's Legendary roll. | A sandbox run shows each arrow's effect. Over 300 hits on stone, 33% ±5 break. The statuses show no blood. A pack's slots survive death and pickup. A round never holds two Legendaries. |
| Art | Arrowheads, darts and the blowpipe; the compound bow; packs worn on any avatar size; quivers that show what's inside. | The renders pass, and packs fit five avatar sizes. |
| Animation and first person | The Blowpipe hold; nocking each type of arrow; the Pitch Arrow's flame in view; packs in third person. | The coverage check passes with every arrow type nocked. |
| HUD and sound | The ammo chip by the draw meter; status icons with a neutral vignette; 7–9 slots on phones; the Back slot. Sounds: the whistler's shriek and the blowpipe's puff. | The layout harness is clean on a phone with 9 slots. |
| QA | A 2-player playtest on arrows and packs, checked against the ammo economy in §5.5. | Arrow counts per archer sit within §5.5's ranges. |

**W5 · The living show (~2 weeks)**

| Track | Tasks | Done when |
|---|---|---|
| Data and code | **Objectives v2:** the event goals (D2–D8), Warmth and Hunted. **Requests that pay Favour;** capsule notes that coach; Favour for survival craft. **The Offering by need** (half the living, rounded down, plus one; always fewer than the living, at most 8). **The headcount Last Stand.** **Truces** that end at the Offering or when four are left. **Marked by the Wardens.** **The fallen's** Patron token and the event vote. | At `StudioTimeScale` 6 a round shows every beat. The Offering always puts out fewer prizes than there are contenders alive (at most 8). The headcount trigger fires at three. There is no path from Robux to any of it. |
| Art | The Beacon's 24 fire-cups, one going dark at each Knell; the Marked tag; the vote cards. | The fire-cups read from the Green's edge. |
| Animation and first person | The Truce gesture on B12's gesture wheel. | It reads at 30 studs. |
| HUD and sound | The audience screens (BACK A CONTENDER, the vote cards); the event goals; the Marked tag; at the headcount, the Knell from each survivor's position. | Every exact line in §3.9–3.11 shows. |
| QA | A full round with 8 clients. Telemetry: deaths by act, the share who reach water by 4:00, and the Offering's turnout. | 30–60% of the living turn out for the Offering, and no new player dies of thirst in rounds 2–3. |

### 6.3 Changes by script

| Script | Change | Phase |
|---|---|---|
| `ReplicatedStorage.Shared.ItemDefs` | The retune and renames; the fields `damageType`, `job`, `verb`, `hold`, `armour`, `backstab`, `cleave`, `minRange` and `armourPierce`; `throwable` on the hatchet; the loot tables (no bows in tier 2; Spire, Alcove, Offering and Runner tables; the caps) | W1 |
| | `stones`, `sling`, `wire_snare`, `tripwire`, `fire_kit`, `rope`, `purifying_tablets`, `field_glasses`, `hand_flare` | W3 |
| | `broadhead_arrow`, `pitch_arrow`, `whistler_arrow`, `dart`, `nettle_dart`, `blowpipe`, `compound_bow`, `satchel`, `rucksack`, `frame_pack`, `plate_carrier` | W4 |
| `Shared.Config` | `Combat.BowHeadshotMultiplier` 1.8, `BowAssistRange` 60, `MaxSingleHit` 95; throw speeds; `Loot.GroundSpawnChance` 0.35 on today's map (v3's planner sets its own); `Objectives` thresholds | W1 |
| | the kit's caps; `stones` in `Loot.AutoPickup`; `Survival.BrackishDamage` 3 | W3 |
| | `Combat.ArrowBreakOnStone` 0.35; the quiver sizes | W4 |
| `Shared.Objectives` (new) | The goal rules and their exact text (§3.9), as a pure module that can be unit-tested | W1, then W5 |
| `Shared.ActionHints` | The melee line, "CHOP" for the hatchet, a second packed `hintsSeen2` (today's 30 bits are full); then hints for the new items | W1, W3 |
| `Shared.ThreatLine` | "NEXT ·" in front of future beats; the Offering's stakes. Layered on ArenaV3's per-stage beats. | W1 |
| `Shared.Lore` | Names the goals speak (pale flag, the Drill, Patron parcel, Patron Request, the Marked) | W1, W3, W5 |
| `Shared.WaterPoints` (and `WorldGen.WaterPointsBuilder`) | A name and a kind for each point (lake, river, creek, spring, brackish); this round's flowing springs (ArenaV3 T11) | W1, W3 |
| `Shared.ArenaLayout` | `SpireStaging` (ring and rack spots), `BowPerches` (the Watchtower), `Shelters`; then `StoneHeaps` and `RequestSpots`. ArenaV3's layout (T1) supplies the v3 versions. | W1, W3 |
| `Shared.Sounds` | The horn's low tone; the class tells; the kit's sounds; the arrows' sounds | W1–W4 |
| `Shared.ItemModels` | Racks and tarps built from Parts; fallbacks for the heap, campfire and parcel. New items play with today's stand-in pouch until their meshes exist. | W1, W3 |
| `Shared.Input` | CycleAmmo on R and D-pad right (already reserved) | W4 |
| `Server.Services.CombatService` | Damage types, the unseen hit, the sweep, `minRange`, `armourPierce`, the 95 cap, live practice dummies | W1 |
| | The swing state machine, heavy attacks, the guard, stagger, the flinch | W2 |
| | The sling; the blowpipe; choosing ammo | W3, W4 |
| `ProjectileService` and its `WorldProjectiles` | Hatchet throws | W1 |
| | Stones and flares as world items; the flinch on a hit | W3 |
| | Arrow types; arrows breaking on stone; fire patches; the Whistler's decoy | W4 |
| `InventoryService` | `absorb(player, damage, damageType)`, the entry point loot-equipment §11 names | W1 |
| | The kit's uses (Place, Strike, Fix); tablets at brackish water | W3 |
| | The quiver, packs and the Back slot | W4 |
| `LootService` | Fixed placements and caps scaled to the headcount, the new tables, the Offering table | W1 |
| | Stone heaps and Patron parcels | W3 |
| | The Offering by need | W5 |
| `KitService` (new) | Placed snares, tripwires, campfires and ropes | W3 |
| `PlayerService` | Healing near a fire; the `Snared` attribute | W3 |
| | Statuses and their damage causes (the Knell is Roadmap Phase 1's) | W4 |
| `ArenaService` | The Roll Call's sub-line announces the Offering; the Offering's stakes | W1 |
| | The headcount Last Stand; truces ending; the Marked | W5 |
| `RoundService` | The Drill's step state in practice rounds | W1 |
| | The audience's tokens | W5 |
| `OnboardingService` | The Drill's funnel steps; telemetry on the goals | W1 |
| `DataService` | New `SETTING_LIMITS` keys: `objectives` and `hintsSeen2` | W1 |
| FavourService and PatronService (arena-events.md, new) | Requests that pay Favour; capsule notes that coach | W5 |
| `Client.Controllers.HUDController` | The goal line, the NEXT prefix, the compass's goal marker, weapon cards, the Offering line fix | W1 |
| | Trap ticks and the new markers | W3 |
| | The ammo chip and status icons | W4 |
| `NotificationController` | The death tips (§4.5) and the act cards | W1 |
| | The audience's cards | W5 |
| `CombatController` | The hatchet's throw path; a `MELEE_STYLE` entry for the club | W1 |
| | Light and heavy attacks, and the guard | W2 |
| | The sling's whirl | W3 |
| | The blowpipe and CycleAmmo | W4 |
| `InventoryController` | Weapon cards on pickup and on hover | W1 |
| | The kit's use flows, the heap's prompt, the brackish hint | W3 |
| `ViewmodelController` (`Rig`, `Poses`) | The hatchet's hold and throw (`def.hold`) | W1 |
| | Heavy attacks and the guard | W2 |
| | Sling, Raise, Place, Strike, Fix and Tablet | W3 |
| | The Blowpipe | W4 |
| `CharacterVisuals` | `CombatAction` poses; carry poses | W2 |
| | Packs | W4 |
| `AudioController` | The horn's duck; the quiet knife | W1 |
| | The class tells | W2 |
| | The kit's emitters | W3 |
| | The Whistler and the puff | W4 |
| `ProjectileController` | Stones and the flare | W3 |
| | Arrows, darts and the Pitch Arrow's flame | W4 |
| `SettingsController` | The Objective line setting | W1 |
| `LobbyController` and `WorldGen.UIBuilder` | The tagline; the goal label in the HUD's top band | W1 |
| `SpectateController` | BACK A CONTENDER | W5 |
| `art/blender` (`items_real.py`, `ir_weapons.py`, a new `ir_kit.py`) and `WorldGen.ItemAssets` | The new meshes and their templates | W3, W4 |
| `WorldGen.Populate` | Racks, tarps and the Watchtower's rack | W1 |
| | Stone heaps | W3 |
| | The Beacon's fire-cups | W5 |
| `ServerStorage.Dev` | `WeaponHarness` and `LootSim` | W1 |
| `docs/GameDesign.md` §6, §9, §10 | Updated as each phase lands; not by this plan | each phase |

### 6.4 What the ArenaV3 tasks should supply

| ArenaV3 task | What this plan needs from it |
|---|---|
| T1 · layout-v3 | **The Spire's staging spots:** 8 tarps on the outer ring, the racks on the steps (in place of the 6 tier-3 ground markers), and the 4 crate slots plus the 4 plaza crates. **A fixed bow rack** in the Watchtower's cab (Watchtower Ridge, site 13). **Shelters** for the dusk goal: the caves, the Millrace, the Redoubt's cellar, the Hunters' Rest, the bothy and the ranger station. The goal only points at those inside the border, so the bothy and the ranger station, which sit outside the night ring on purpose (ArenaV3 §6.8), count only while the ring still holds them. **Request spots:** the sites in §3.10. **Ledges** where a placed rope makes a new route. |
| T10 · loot-v3 | The tables and per-round caps in §2.4. The prize spots roll the Alcove table and share its caps. |
| T11 · events-data-v3 | **Water points** with a name and a kind (lake, river, creek, spring, brackish), and which springs flow this round. **Stone heaps** on North Beach, the gravel bars and fords, and the scree under the Rust Wall and in the Throat. |
| T12 · client-v3 | The goal line sits in the same top band as the stage-aware event line and the compass's region name. Agree the layout once, in `UIBuilder`. |

---

## 7. Questions for you

| # | Question | Recommendation |
|---|---|---|
| Q1 | **How fights work (Roadmap decision 3).** Before the new weapons arrive, should fights get visible wind-ups, tap-for-light and hold-for-heavy attacks, and a simple guard with a perfect-block window? | **Yes.** Most of the counters depend on it: the club breaking a guard, the Longsword's riposte, stones spoiling a draw. W1 works without it; W2 needs your answer. |
| Q2 | **The bow as a prize.** About 3–4 bows a round instead of about 13. A headshot does 90 instead of 100. Point-and-shoot aim only inside 60 studs, with real drop beyond. | **Yes.** No arrow downs anyone from full health, the bow is worth fighting over again, and close fights belong to blades. |
| Q3 | **Truces.** Should two contenders be able to agree a temporary truce with a gesture? Each would see a small mark over the other. It would end on any damage, when the Offering's bell rings, or when four are left, and there would always be one winner. | **Yes.** Alliances that form and break are one of the films' best beats, and the automatic endings stop teams from forming. |
| Q4 | **The fallen as the audience.** Should players who fall be able to back one living contender with a free Patron token, and vote between two Warden events? Never for Robux. The Roadmap had this for much later (Phase 10); this brings it forward. | **Yes.** A third of a lobby can be out by 2:30. It gives them a reason to stay and watch, and it is the most film-like feeling we can add. |

---

## Sources

- **The research brief for this plan.** The weapons and kit across the four arenas; the opening scramble and its numbers; herding by the arena; gifts from outside; the mid-round restock; the finale; one job per weapon (Halo 3, Apex); rarity (Fortnite, PUBG, BedWars); counter triangles (Schreiber); readability (Team Fortress 2); objectives (Warzone, Apex, The Culling); spectators (Darwin Project, a Roblox game in this genre). The full links are in the brief.
- **The audit of today's game.** Items and combat (`ItemDefs` 22–79; `CombatService` 764–812, 883–910 and 969–980), loot (`ItemDefs` 93–149; `LootService`; the live markers), the round flow (`RoundService`, `ArenaService`, `Config`), and the HUD and messages (`HUDController` 1160–1271, `NotificationController`, `ActionHints`).
- **Checked again for this plan,** read-only: `ItemDefs` and `Config` in Studio (they match the repo); `src/` for `CombatService`, `LootService`, `RoundService`, `ArenaService`, `HUDController`, `ThreatLine`, `Lore`, `ActionHints`, `NotificationController`, `ViewmodelController.Poses`, `CombatController` and `ArenaLayout`.
- **Project docs:** [Roadmap.md](../Roadmap.md) §2, §5, §7 and §8; [loot-equipment.md](loot-equipment.md); [arena-events.md](arena-events.md); [PlayabilityPlan.md](PlayabilityPlan.md); [ArenaV3.md](ArenaV3.md) §1, §4, §5.8 and §6; [story-world.md](story-world.md) §3; [CombatPhysicsPlan.md](../research/CombatPhysicsPlan.md) §1.3 and §3; [GameDesign.md](../GameDesign.md) §6; [art/README.md](../../art/README.md) §9.
- **Simulations,** 20,000 rounds each, on the live tables and today's markers: time to down, and loot per round (built from the audit's loot simulation). The scripts sit in the session's scratch folder, not in the repo; QA's `WeaponHarness` and `LootSim` (W1) replace them.

---

## Review notes

*Design review, 12 November 2026. Checked against the research brief, the audit, ArenaV3, the other design docs, the repo's `src/` and a read-only look at the live place. Every time-to-down in §5.1 and §5.2 recomputes exactly from its damage, cooldown, wind-up and armour. The fixes are made in place; this table says where.*

| Check | Verdict | What this review changed |
|---|---|---|
| Intuitive for a brand-new player | Yes: one goal line, weapon cards and the Drill | The Last Stand and the moving border now outrank "arm yourself" and "find water", and markers never point outside the border (§3.9). Tips read numbers from the data, speak metres, and teach the flinch only once W2 ships it (§4.5). "The Trial" is now **the Drill**, because the Daily Trials own the word (§4.2). |
| Fun at 24 | Yes | Patron Requests could have dropped a reward per player every 90 s. Now the parcel drops on completion, at most 3 per contender and 12 a round, and the Lure and Splice Requests don't pay twice (§3.10). Party members can't back each other (§3.11). |
| Fun at 2–4 | Not before this review: 2 contenders found the whole Spire stocked, and the headcount finale can never fire with 2–3 | The Spire's staging, the bow and Longsword caps and the Offering's prizes now scale with the headcount (§2.4, §3.2, §3.6). W1 pairs with PlayabilityPlan B3's faster clock (§3.8, §6.1). |
| Balanced and readable, with counters | Mostly: the rarity ladder holds | Reach barely mattered, because every blade reached 10.9–14.9 studs. Fists, the knife and the hatchet now reach less, and §5.3 uses real distances (§2.2). The hatchet can't guard, since its Aim is the throw (§5.4). The machete's counter matches its numbers: armour slows it least of the blades (§2.1, §4.5). Stones and the Sling wait for W2's flinch, because spoiling a draw is their job (§6.1). |
| Objectives clear and short | Yes | The acts' times no longer overlap (§3.1). B2 no longer says "recover" when hunger or thirst stops healing. The Longsword's card says "the best blade", since the knife swings faster (§4.4). |
| Film-inspired, no signatures | Yes | Packs are never orange or a pre-packed set, and "no horn" now says horn shape (§2.8). |
| Buildable with our systems | Yes, with fixes | Today's map has no tier-3 ground markers, so the racks replace 6 plaza crates (§3.2, §5.6). Armour goes through loot-equipment's `InventoryService.absorb`. Thrown stones crumble outside `WorldItemCap`, so they can't push arrows out of the world. Nobody can cut a rope with someone on it (a 40-stud fall does about 55 damage). The live place confirms that the dummies are still Studio-only (`CombatService` 982–993) and that spent arrows stay in the world (`WorldProjectiles`). |
| Agrees with the other docs | Now it does | Each deliberate departure now names the rule it replaces: softer armour until integrity exists (loot-equipment §5.7), smaller quivers (§3.3, §5.3), no bow in capsules (§7.5), the audience token and its earlier date (arena-events §7, Roadmap Phase 10), the truce rule (B12), and the guard, the flinch and the machete-only sweep (CombatPhysicsPlan). The parcel isn't called a tin, because the Roadmap's Gold caches are sealed tins. |

**Also changed for your notes.** §2.5 authors every first-person hold for your own avatar's arms, kept blocky with realistic shading, and the stone heaps share the Blender pebble ground the style test is building.

**Still open**
- Re-run the loot simulation (QA's `LootSim`, W1) with the small-round staging, the Offering formula and the parcel cap. §5.6's proposed totals predate them.
- Bleeding differs between loot-equipment §8 (6 s, and a bandage stops one stack) and CombatPhysicsPlan §3.5 (8 s, and a bandage stops all). This plan follows loot-equipment; whoever builds the W4 status API settles it.
- The live place has moved past the v166 `src/` export (`WorldProjectiles`, `Config.Viewmodel`), so line numbers cited from `src/` may have shifted.
