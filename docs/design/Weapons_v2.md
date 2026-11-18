# Weapons v2: the list, stars, kits, Gold, the wheel and the bow

*Design page for the builders, 18 Nov 2026. It follows the owner's words of 12, 15 and 18 Nov (quoted in section 0). Where it departs from older pages, this page wins for this update: `WeaponsAndObjectives.md` (19 items, W1 to W5), `economy-cosmetics.md` (its "nothing random for sale, power never for sale" charter) and `loot-equipment.md` (Citadel modifications) are older and are overridden only where this page says so.*

Rules that hold everywhere on this page:
- **Mild rating.** No blood, no wounds, no red hit effects, no cries, no "HEADSHOT" text. Hits show a pale tick; a fallen contender falls and fades as today.
- **Quiet UI** (`docs\design\ui\StyleA_Quiet\README.md`, `Shared\Theme.lua`, `Shared\QuietUI.lua`): thin text and matte icons on the picture, no boxes, no pop-ups. Results go on the board in the train.
- **Look:** "roblox with good graphics", matte, blocky, semi realistic. No glow, no beams, no particles on any weapon or star.
- **Our own designs.** Shapes and feel from the trailer frames, no names, logos, emblems or signature props from the films (section 1.3).
- **Every number lives in Config** (section 9). Every value here is a starting value for playtests.

---

## 0. What the owner asked for

| Date | Their words | Where this page answers |
|---|---|---|
| 18 Nov | "we should have a basic weapons list (like kits the players can choose where its sth basic like an arrow some apples etc) that spawns in the half point of the game" | Kits, section 3 |
| 18 Nov | "so the epic ones will be drawn in a wheel and can also be bought with in game currency like in hypershot by buying loot boxes etc ygwim?" | Gold, section 4; the wheel and Strongboxes, section 5 |
| 18 Nov | (epic items: harder hits or only looks?) "overall weapon stats better and have stars etc" | Stars, section 2 |
| 18 Nov | "also we can now design our own weapons based on how they look in the trailer for the new hunger games right?" | New weapons, section 1 |
| 15 Nov | "a smaller collection of useful objects, each with a clear purpose"; "Bows and arrows. Knives. Axes. Spears. Other appropriate weapons."; rarity as "availability, quality and usefulness, rather than ... fantasy-style magical properties" | Section 1 (11 weapons, one job each) |
| 12 Nov | (bow: 3 to 4 a round, 90 headshot, on the crosshair only within 60 studs) "yes and make the distance and drawing more accurate but again we will deal with weapons and fighting later" | The bow, section 6 |
| 12 Nov | "we will focus on attacks and battle manaeuvouring later remind me" | Later list, section 8 |
| 18 Nov | "Yes, weapons next" | This page |

**The lead's reading, not confirmed by the owner:** "spawns in the half point of the game" means each player picks a free kit before the round and it is delivered to them at the middle of the round, so the opening is still a scramble at the Horn. One Config switch (`Config.Kits.Delivery = "Start"`) gives the kit at the launch instead.

---

## 1. The weapon list

### 1.1 What exists today (`ItemDefs.lua`, `CombatService.lua`)

- Melee: one strike per swing, `damage`, `cooldown`, `range` (+ the server's `MeleeLagTolerance` 3 and `MeleeHitRadius` 2.4), `windup`, `staminaCost` (a fraction of a 0 to 1 bar). Throwable melee (spear) uses `throwDamage`, `throwSpeed`, `throwGravity`.
- Bow: damage and speed lerp with the draw (`damageMin..Max`, `speedMin..Max`), `drawTime` 0.9, `MinBowCharge` 0.2, headshot ×1.8 (90). `BowAimOnTarget = true` at every range, zeroed at `BowZeroDistance` 100. No 60-stud limit, distance changes nothing.
- Throwables: `throwing_knife` stack 6. Thrown and shot items stay where they land and can be picked up.
- Inventory slots are `{ id, count }`. **No durability anywhere. No stars. No owned items, no Gold** (only `Theme.Colors.Gold`).
- Loot: tiers 1 (ground, camps), 2 (site crates, runner's caches), 3 (the Horn). The bow sits in tier 2 (weight 5) and tier 3 (weight 10) with **no cap**: about 13 a full round.
- Health 100. Armour flat: Leather Vest ×0.85, Padded Armor ×0.72.

### 1.2 The list for this update: 11 weapons, one job each

Ids stay for every weapon kept, so saves, markers and art keep working. "To down" = time to take a healthy, unarmoured contender from 100 to 0 with plain hits (wind-up + gaps). 5★ values in section 2.

| # | Weapon (`id`) | Status | Role, its one job | Damage | Swing every / wind-up | Reach or range | Stamina a use | To down | How it feels different |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Hunting Knife (`knife`) | keep, rebalance | short blade: quick, quiet | 20; **40 unseen** (first hit on someone facing away, not hurt in 5 s) | 0.48 s / 0.10 s | 4.5 | 0.04 | 2.02 s | Fast backhand and stab, swish heard only within 12 studs. The ambusher's blade. |
| 2 | Machete (`machete`) | keep, rework | wide cut for the scramble | 26; a 2nd contender in the arc (±55°) takes 60% | 0.55 s / 0.14 s | 7 | 0.06 | 1.79 s | Flat sweep that drags through its arc. Best when two are close. |
| 3 | Hatchet (`hatchet`) | keep, rework | short axe and tool; one heavy throw | 34; throw 45 (head ×1.6 = 72) at 110 studs/s, gravity 45 | 0.80 s / 0.18 s | 5 | 0.08 | 1.78 s | Chop that bites with a short hit-stop. Splits firewood: a fire lit with it in your bag burns twice as long. |
| 4 | Spear (`spear`) | keep, rebalance; look from the trailer's pale staves | long reach; big throw | 34; 60% inside 4 studs; throw 60 (head capped 95) at 110 studs/s | 0.70 s / 0.20 s | 9.5 | 0.07 | 1.60 s | Two-handed thrusts. Keeps everyone at the end of the shaft; weak once they get inside. |
| 5 | Longsword (`sword`) | keep, rebalance, **new look** (T1 @82.7 s) | the duellist | 36 | 0.62 s / 0.16 s | 8 | 0.08 | 1.40 s | Clean diagonal cuts. The best blade; the Horn's prize. |
| 6 | **Twin-Bit Axe** (`twin_axe`) | **new** (T2 @130.8 s); replaces the Mace in loot | heavy hitter and armour-breaker; a spinning throw | 42; armour stops half as much; throw 65 (head capped 95) at 95 studs/s, gravity 50, turning end over end | 0.95 s / 0.30 s | 7 | 0.12 (throw 0.10) | 2.20 s | Slow, wide, heavy swing with a camera dip; others read the wind-up. Throwing it leaves you empty-handed until you pick it back up. |
| 7 | **Ring Blade** (`ring_blade`) | **new** (T2 @129.2 s) | close slash, flat throw | 24; throw 38 (head ×1.6 = 61) at 140 studs/s, gravity 12 | 0.55 s / 0.12 s | 5.5; the throw lands on the crosshair to 45 studs | 0.05 (throw 0.06) | 2.32 s (1.64 s at 5★; 4 hits from 3★) | Held through the hoop like a knuckle guard. Thrown, it flies flat and fast with almost no drop; it is your only weapon while it is in the air. |
| 8 | **Climbing Pick** (`climb_pick`) | **new** (the alpine valley) | tool weapon: climbing | 26 | 0.65 s / 0.14 s | 5 | 0.06 | 2.09 s | In hand while climbing a `Climbable` (trees, rock): climb speed ×1.2, `ClimbDrain` ×0.7. A short overhead peck. |
| 9 | Recurve Bow (`bow`) | keep; **owner's bow rules** (section 6) | the long-range killer, 3 to 4 a round | 14 to 50 by draw; head ×1.8, **never over 90** | 0.9 s draw; about 1.1 s a shot | on the crosshair to 60 studs; real drop beyond, useful to about 150 | 0.04 a draw | 2 full-draw body hits | Creak heard at 45 studs (built). Comes with 5 arrows. Never in the wheel or boxes. |
| 10 | **Short Bow** (`short_bow`) | **new**: the kit bow | a weaker, quicker bow | 10 to 36 by draw; head ×1.8 (65) | 0.6 s draw; about 0.8 s a shot | on the crosshair to 40 studs; drop beyond, useful to about 90 | 0.03 a draw | 3 full-draw body hits | Lighter creak (heard at 30 studs). Speed 80 to 190, gravity 60. Shoots the same arrows. |
| 11 | Throwing Knives (`throwing_knife`) | keep, rebalance | quick short throws | 22 / 35 head | 0.5 s | 120 studs/s, gravity 40; useful 5 to 30 | 0.03 | 5 hits | A flick from the shoulder. Stack of 6. No stars (section 2.1). |
| — | Arrow (`arrow`) | keep | ammunition, stack 24 | — | — | — | — | — | No stars. Stays where it lands (built). |
| — | Fists (`fists`, hidden) | keep | baseline | 8 | 0.45 s | 4 | 0.03 | — | — |
| — | Mace (`mace`) | **retired from loot** | — | — | — | — | — | — | The id and model stay so nothing breaks; no table spawns it. The Twin-Bit Axe takes its job. |

**One support item for the Trapper kit** (traps are on the owner's 11 Nov list: "Traps: Snares, tripwires and improvised traps"):

| Item (`id`) | Stack | Use | Effect | Limits |
|---|---|---|---|---|
| **Wire Snare** (`wire_snare`) | 2 | Hold Attack 1 s on ground under 30°; arms 2 s later | Holds a leg 2.5 s and does 5 damage, a loud snap; the owner gets a ping with a direction. Tap E to wriggle free in about 1 s; a knife frees you at once. Never kills. | 3 armed per contender, 40 in the arena. None within 70 studs of the Horn in the first 60 s, within 8 studs of a plinth, or in water. The wire glints within 6 studs; crouch and hold E 2 s to disarm and take it. |

If the snare slips, the Trapper kit ships as "Hunter" (3 throwing knives, dried meat, firewood) and the snare follows.

### 1.3 The trailer frames: every weapon visible, and what we make of it

I looked at the frames in `References\trailer\`. Only these show weapons. Nothing below is copied; each new model is our own Blender design in the ItemsReal pipeline.

| Frame | What is there (look only) | What we make |
|---|---|---|
| T2 @130.8 s | A double-bit axe thrown end over end: a long, straight, pale ash handle with a darker band near the grip and a small steel collar, and a broad, symmetrical head of dark matte grey steel whose two bits flare wide into curved edges. | **Twin-Bit Axe** |
| T2 @129.2 s (the Horn's deck) | A large flat ring of bright steel, about a forearm and a half across, held from the inside at a short grip, swung like a slashing hoop. | **Ring Blade** (see IP note below) |
| T2 @129.2 s (the Horn's walls) | Navy walls with gold edging carry racks: a fan of slim steel poles with three-pronged forked heads, bundles of arrows, and on the right short axes with flat steel heads and pale handles hung head-up. | Rack props for the Horn. **No three-pronged weapon** (a trident is a signature of the films; standing rule in WeaponsAndObjectives §2.8). |
| T1 @82.7 s (training hall) | Long, narrow, straight single-edged blades of bright steel with a small crossguard and a plain dark grip, about an arm and a half long, swung by trainees in white. | **Longsword's new look** |
| T1 @79.7 s (training hall) | An orange-framed trolley with blue padded trays holding rows of short knives with dark grips; an orange A-frame rack of pale wooden staves; a white spoked wheel used as a target. | Hunting Knife and Spear looks; the orange trolley and rack become **the kit racks in the train** (section 3.2) |
| T2 @124.4 s | A pale grey canvas backpack with a white cylindrical tube strapped down one side. | Not a weapon. The look of the **kit parcel** and a later quiver. |
| T2 @126.2 s | Sparks spraying from a gold, daisy-shaped metal fitting on a rod, like a fuse or charge. | **Not used.** No explosives. |

**IP note for the lead:** if the steel ring turns out to be one named character's signature weapon in the new film, swap the Ring Blade for a **Hook Knife** (same numbers, a short curved blade with a ring pommel). The game never names it after anything in the films either way.

### 1.4 Looks for the new and reworked models (Blender, `art\blender\ir_weapons.py`)

Style: blocks, wedges and 6 to 12 sided prisms with 0.03 to 0.06 stud chamfers; detail in matte materials (roughness 0.55 or more); held items at most 2,500 triangles; Grip at the origin along +Z with a Tip attachment (bows keep Nock, StringTop, StringBottom, ArrowRest).

| Weapon | Shape | Materials and colours | Carried (third person) |
|---|---|---|---|
| Twin-Bit Axe | 3.4 studs. Eight-sided straight ash haft, a dark leather band at the grip, a steel collar under the head. The head: a central block with two mirrored flared wedges, each edge a shallow arc of 3 facets with a bright bevel strip. | pale ash, dark leather, dark matte grey forged steel, a lighter honed edge | over the shoulder |
| Ring Blade | A flat steel hoop 2.2 studs across (16 straight segments), the outer edge a bevel strip; a short grip bar across the inside wrapped in cord, a small brass ferrule each end. | satin grey steel, waxed charcoal cord, dull brass | hung at the hip |
| Climbing Pick | 2 studs. Six-sided hickory haft, a curved pick of 4 bent segments with a square adze at the back, a wrist loop and a steel spike at the foot. | hickory, dark iron, rawhide | at the belt, head down |
| Short Bow | 3.6 studs. A plain flat-limbed bow, limbs as two tapered slabs, a leather grip block, no recurve tips. | pale yew-coloured wood, tan leather, linen string | across the back |
| Longsword (new look) | 3.7 studs. A narrow straight single-edged blade (a long wedge with a back spine strip), a small square crossguard, a plain grip of stacked rings, a flat disc pommel. | bright forged steel, blackened iron guard, dark leather | in a scabbard on the left hip |
| Kit parcel | A pale grey canvas block with a white tube strapped on its side, cord tied in a cross, a small ember-coloured card tag. Its chute is ember and charcoal canvas, **never silver**. | canvas, cord, card | — |

---

## 2. Stars

### 2.1 What a star is

- Every copy of a **stack-1 weapon** (all of 1.2 except throwing knives, arrows and fists) carries **1 to 5 stars**. Ammunition, throwing knives, food, medicine, armour and snares have no stars.
- Stars are "availability, quality and usefulness" (the owner's 15 Nov rule): better construction, never magic. A 5★ weapon is the same weapon, better made.
- **About +25% in total from 1★ to 5★,** so a 5★ never beats a better player with a 1★.
- **No durability.** Nothing wears out in this update; stars do not add it. (Durability is on the later list.)

### 2.2 What each star raises

Each star above the first adds:

| Weapon type | Damage | Speed | Reach or range | 1★ to 5★ in total |
|---|---|---|---|---|
| Melee (and its throw) | +4% (×1.16 at 5★) | cooldown −2% (×0.92 at 5★) | +0.15 studs (+0.6 at 5★) | about +26% damage a second, +0.6 studs |
| Bows | `damageMax` and `damageMin` +4% (×1.16) | `drawTime` −3% (×0.88) | on-crosshair range +5 studs (recurve 60 to 80, short bow 40 to 60); `speedMax` +2% (×1.08) | about +25% |

Two hard limits, whatever the stars:
- **No single hit over 95.** No single hit kills a healthy contender.
- **A bow headshot never does more than 90** (the owner's number, so one arrow never kills).

### 2.3 Every weapon at 1★ and 5★

| Weapon | Damage 1★ / 5★ | Swing every 1★ / 5★ | Reach 1★ / 5★ | To down 1★ / 5★ |
|---|---|---|---|---|
| Hunting Knife | 20 / 23.2 | 0.48 / 0.44 s | 4.5 / 5.1 | 2.02 / 1.87 s |
| Machete | 26 / 30.2 | 0.55 / 0.51 s | 7 / 7.6 | 1.79 / 1.66 s |
| Hatchet | 34 / 39.4 | 0.80 / 0.74 s | 5 / 5.6 | 1.78 / 1.65 s |
| Spear | 34 / 39.4 | 0.70 / 0.64 s | 9.5 / 10.1 | 1.60 / 1.49 s |
| Longsword | 36 / 41.8 | 0.62 / 0.57 s | 8 / 8.6 | 1.40 / 1.30 s |
| Twin-Bit Axe | 42 / 48.7 | 0.95 / 0.87 s | 7 / 7.6 | 2.20 / 2.05 s |
| Ring Blade | 24 / 27.8 | 0.55 / 0.51 s | 5.5 / 6.1 | 2.32 / 1.64 s (4 hits from 3★) |
| Climbing Pick | 26 / 30.2 | 0.65 / 0.60 s | 5 / 5.6 | 2.09 / 1.93 s |
| Recurve Bow | 14–50 / 16.2–58 (head 90 cap) | draw 0.90 / 0.79 s | on target 60 / 80 studs | — |
| Short Bow | 10–36 / 11.6–41.8 (head 65 / 75) | draw 0.60 / 0.53 s | on target 40 / 60 studs | — |

### 2.4 How stars show (no glow, no beams)

| Where | What the player sees |
|---|---|
| Hotbar | A row of up to 5 small matte stars under the slot icon, `Theme` text colour at 70%; 4★ and 5★ stars in a matte `Theme.Colors.Gold`. |
| Equip line | The thin item line reads "Machete ★★★" for 2 s on equip, then fades. |
| The model in hand and on others' bodies | **A finish change only**, the same silhouette and size at every star (fair to read at 60 studs): 1★ *Worn* (dull, scuffed steel, faded wood); 2★ *Sound* (clean); 3★ *Fine* (darker blued steel, fresh leather wrap); 4★ *Superior* (brass fittings, darker hardwood); 5★ *Masterwork* (a fine etched band on the blade or limb, brass and dark walnut). All matte. Built by `ItemModels.build(id, variant)` with `variant = stars`, swapping colours and MaterialVariants on parts tagged by `Role`. |
| On the ground and in a crate's spill | The existing loot glint takes its colour from the stars for weapons: 1★ Common, 2★ Uncommon, 3★ Rare, 4★ Epic, 5★ Legendary (`ItemDefs.RarityOrder`). Looking at it within 12 studs shows the thin label "Twin-Bit Axe ★★★★". |
| Third person, other players | Only the finish. No stars over heads, no name tags. |
| Results board in the train | A player's best weapon of the round is listed with its stars. |

### 2.5 Where each star count comes from

| Source | 1★ | 2★ | 3★ | 4★ | 5★ | Kept after the round? |
|---|---|---|---|---|---|---|
| Kits | 100% | — | — | — | — | no |
| Ground and camps (tier 1) | 70% | 25% | 5% | — | — | no |
| Site crates and runner's caches (tier 2) | 45% | 35% | 17% | 3% | — | no |
| The Horn (tier 3) | 20% | 35% | 30% | 13% | 2% | no |
| The Offering (785 s) | — | — | 50% | 40% | 10% | no |
| The wheel and Strongboxes | section 5 | | | | | **yes, owned** |

### 2.6 Owned versus found: the recommendation

**Wheel and Strongbox prizes are owned and kept between rounds. Weapons found in the arena are per round.**

How it works:
- The **Armoury** holds the player's best star of each weapon id they have won or bought (one entry per id).
- Before each round the player may **bring one owned weapon.** It replaces the weapon in their kit and arrives **with the kit, in the midpoint drop** (section 3). Nobody starts the round with an owned weapon (unless the owner flips `Config.Kits.Delivery` to "Start").
- In the round it is a lent copy: it can be dropped, taken by whoever defeats you and used by them for that round. Nothing owned is ever lost; it is back in your Armoury next round.
- The **Recurve Bow is never owned** and never in the wheel or boxes, so the owner's 3 to 4 bows a round stays true. An owned Short Bow comes with 6 arrows.

Why:
- It is what the owner described: "bought with in game currency like in hypershot", where what you win is yours.
- The midpoint drop keeps the opening fair: everyone fights the Horn with what they grab.
- The +25% ceiling and one owned weapon a round keep skill first.
- Per-round prizes would make the wheel feel empty; a full loadout of owned weapons from the start would make the Horn pointless.

---

## 3. Kits

### 3.1 The five kits (all 1★, all free)

| Kit | Contents | Who it is for |
|---|---|---|
| **Archer** | Short Bow 1★, 8 arrows, 1 apple | ranged from mid-round |
| **Forager** | Hunting Knife 1★, 3 apples, Water Bottle | the default for new players |
| **Trapper** | Wire Snare ×2, Throwing Knives ×2, Dried Meat | holding a trail or a camp |
| **Medic** | Bandage ×2, Healing Herbs ×3, Water Bottle | no weapon; survives the second half |
| **Climber** | Climbing Pick 1★, Wild Berries ×4, Firewood | trees, rock and high ground |

- **Bring one owned weapon** (2.6): it replaces the kit's weapon (Medic: it is added). The kit's food and tools still come.
- A kit's choice is remembered for the player's next round. A new player gets Forager.

### 3.2 Picking it in the train (quiet UI)

- **Physical:** the five kits lie on an orange-framed rack with blue padded trays along one side of the red train car (the look of the training hall trolley, T1 @79.7 s). Each has a small paper card with its name. Walk up and press E to take it; your pick sits a little forward on its tray, for you only.
- **On screen:** one thin line under the lobby status: `KIT  Archer  ‹ ›` and, below it, `BRING  Twin-Bit Axe ★★★★  ‹ ›` (cycles through owned weapons and "kit weapon"). Clicking the arrows or pressing K cycles. The contents show as one thin line of item names while hovering. No panel, no pop-up.
- The choice locks at the call to the launch.

### 3.3 Delivery at the middle of the round

**When:** `Config.Kits.Delivery = "Midpoint"` (default) or `"Start"`.
- Midpoint = the earlier of **600 s** (half of `Config.Round.MaxRoundTime`, 1,200 on Map 1) and the moment **half of the round's contenders are out**, never before **240 s**. Practice rounds: 60 s.
- "Start": the kit goes into the bag at the launch hand-off; what does not fit lands at the plinth's foot.

**How it lands:**
1. 10 s before, the player alone hears a soft two-note chime and sees one thin line: "Your kit is coming". The landing spot is picked now and does not follow them.
2. Drops are spread over 0 to 20 s per player, so the sky fills over time, not in one frame.
3. The parcel falls from 140 studs under an ember-and-charcoal canvas chute over 7 s, lands with a soft thump and a puff of dust, and the chute folds over beside it.
4. The spot: dry, walkable ground **15 to 25 studs from the player**, inside the ring and at least 30 studs inside where the ring will be when it lands, never on a player, never under a tree crown or the Horn's sails (it searches outward in rings until clear).

**How it is marked:**
- **The owner:** a small matte parcel icon at the screen edge pointing to it, with its distance in thin text, until it is opened or for 90 s.
- **Everyone:** the falling chute can be seen from about 300 studs. On the ground a thin pale smoke ribbon rises from it for 20 s. No name on it.

**Others can steal it:**
- Anyone can open it. The owner opens it in 0.6 s (`CrateOpenTime`); anyone else holds E for 2.5 s.
- Its items spill beside it like a crate's, with "Take all" for the opener (`Config.Loot.TakeAll`).
- An unopened parcel stays until the round's cleanup.

**Edge cases:**

| Situation at the warning | What happens |
|---|---|
| Dead or out before the midpoint | No drop. The kit is not delivered. |
| Dies after the warning | The parcel still lands, as ordinary loot for anyone. |
| In a tree or climbing | It lands 15 to 25 studs from the foot of the tree or the wall, on the ground. |
| Swimming or on the lake | The nearest dry bank within 60 studs; failing that, the nearest walkable ground to them. |
| On the Horn deck | On the turf, 15 to 25 studs out from the platform edge. |
| Near or outside the border | 30 studs or more inside the ring as it will be at landing. |
| Bag full | Items spill beside the parcel (as now for crates). |

---

## 4. Gold (the currency)

**Gold** is the one currency, earned in play. The owner named it in their own notes ("IN GAME CURRENCY - GOLDS"). It buys Strongboxes, wheel spins and Armoury items. Buying Gold with Robux is designed below but **OFF** (`Config.Economy.RobuxGold = false`).

### 4.1 Earning

| Source | Gold | Rule |
|---|---|---|
| Taking part | 10 | Started the round and not AFK (moved 30+ studs or acted in the first 60 s) |
| Placing (48 contenders) | 1st 100 · 2nd 70 · 3rd 55 · 4th–5th 40 · 6th–10th 25 · 11th–24th 12 · 25th–48th 5 | From `RoundService.endRound`; survivors at the time limit share 1st, as today |
| Defeats | 15 each, at most 8 a round | Kill credit from `PlayerService.died` |
| Time survived | 2 per full minute alive, at most 40 | |
| Winning | +50 | Same rule as the Wins stat (15 s or a kill, never practice) |
| First round of the day / first win of the day | +50 / +100 | Days run on UTC |
| Arena challenges (when they exist) | 20 each, at most 3 a round | |
| Practice rounds, private servers | 0 | |

**Fair play:** full Gold needs 8 or more real contenders; 4 to 7 pay half; under 4 pay only taking part. After 3,000 round Gold in a UTC day, round Gold halves.

**What a player earns:** a mid-table round is about 40 to 70 Gold; a win with 3 defeats about 300. A casual player (5 rounds a day) earns about 350 a day: roughly one Strongbox a day.

### 4.2 Costs

| Thing | Gold |
|---|---|
| Wheel spin | 1 free a day (UTC), then 150 each, at most 10 paid a day |
| Strongbox | 400 |
| Masterwork Strongbox | 1,200 |
| Armoury: any wheel weapon at 3★, chosen (no chance) | 800 |
| Armoury: raise an owned weapon 3★ → 4★ | 2,500 |
| Armoury: raise an owned weapon 4★ → 5★ | 6,000 |

The Armoury gives a sure path to any weapon, so nobody must gamble.

### 4.3 Gold with Robux (designed, OFF)

| Pack | Default price | Gold |
|---|---|---|
| Pouch | 5 R$ | 50 |
| Purse | 49 R$ | 500 |
| Satchel | 99 R$ | 1,050 |
| Coffer | 199 R$ | 2,200 |
| Chest | 399 R$ | 4,600 |
| Vault | 799 R$ | 9,600 |

Built as Developer Products with one `ProcessReceipt` handler that grants once per PurchaseId (economy-cosmetics §4, §8.4). Prices are always read from Roblox, never hard-coded in the UI.

**When it is switched on,** Strongboxes and paid spins become paid random items under Roblox's rules: odds shown before every purchase (they already are, 5.4), and for any player whose `PolicyService` info has `ArePaidRandomItemsRestricted`, Strongboxes and paid spins are hidden (the free daily spin and the Armoury stay). The lead should tell the owner in one line that with this switch on, Robux can buy weapon power, which players may call pay-to-win.

---

## 5. The wheel and Strongboxes

### 5.1 What is in them

The prize pool: Hunting Knife, Machete, Hatchet, Spear, Longsword, Twin-Bit Axe, Ring Blade, Climbing Pick, Short Bow. Never the Recurve Bow, throwing knives, arrows, armour or food. Within a star count every weapon in the pool is equally likely.

### 5.2 The wheel

| Segment | Chance |
|---|---|
| 40 Gold | 30% |
| 80 Gold | 22% |
| 200 Gold | 8% |
| a 3★ weapon | 28% |
| a 4★ weapon | 10% |
| a 5★ weapon | 2% |

Segments are drawn on the wheel at their true sizes. One free spin a day; paid spins 150 Gold.

### 5.3 Strongboxes

| Box | Cost | 3★ | 4★ | 5★ |
|---|---|---|---|---|
| Strongbox | 400 | 72% | 24% | 4% |
| Masterwork Strongbox | 1,200 | — | 85% | 15% |

### 5.4 Odds, pity and duplicates

- **Odds are always shown:** on a brass plaque beside the wheel, and as one thin line before any paid spin or box ("3★ 72% · 4★ 24% · 5★ 4%").
- **Pity (per player, saved):**
  - Strongboxes (both kinds count together): a 4★ or better is certain by the 8th box without one; a 5★ is certain by the 40th box without one. The count shows in thin text: "5★ within 23 boxes".
  - The wheel: a 4★ or better weapon is certain by the 25th spin without one.
- **Duplicates:** the Armoury keeps the best star of each weapon. A higher star replaces the old one (shown as "Machete ★★★ → ★★★★"). The same or a lower star gives Gold back: 3★ 100, 4★ 300, 5★ 900.

### 5.5 Presentation: strong effects, quiet style

**The wheel is a physical object in the red train**, mounted on the end bulkhead of the car: about 6 studs across, a brass rim, 12 to 16 matte enamel segments in the train's own colours (oxblood, cream, charcoal, brass), our own simple marks on each (a small item silhouette or a Gold coin), and a leather tongue that clicks over brass pegs. Beside it a steel case on a counter, where prizes come out and Strongboxes are opened.

| Beat | What happens |
|---|---|
| Start | Walk up, press E. The camera eases to the wheel over 0.4 s; the train's ambient sound dips. |
| Spin | The player's arm pulls the wheel. It spins 3 to 4 s with loud, slowing clicks and a slight camera shake on each late click. |
| Last click | 0.3 s of slow motion, then a heavy stop. A warm lamp above the wheel lights the winning segment. No beam, no glow. |
| Prize | The case's lid lifts with a pneumatic hiss; the item rises on a small plinth, turning slowly, under a soft spot. Its stars appear one at a time, each with a click and a brief light tick. |
| 4★ | A lower chime and the car's lights dip slightly while the spot holds. |
| 5★ | A brass bell, the car's lights dim for 1.5 s with only the spot on the case, a puff of dust from the case, and others in the car hear the bell. |
| Strongbox | A steel box on the counter: three latch clicks, the lid opens, then the same star reveal. |

Other players in the car see your spin and your prize. Nothing is announced to the whole server. The results board in the train lists the day's 5★ wins with a player's display name only if they allow it in Settings (default off).

---

## 6. The bow: the owner's notes

| Their note | The rule we build | Config |
|---|---|---|
| **3 to 4 bows a round** | A per-round bow budget. Fewer than 16 contenders: 3; 16 or more: 4. At the round start LootService places them on purpose: 1 on the Horn's rack (in a tier-3 crate) and the rest in tier-2 site crates at least 300 studs from each other, at most one per site. The bow leaves every random table. If 3 were placed, the Offering adds 1, so a round never has more than 4. Bows dropped by the fallen are not new bows. Short Bows are separate: kits, plus tier-2 crates (weight 3, at most 6 a round). | `Config.Bow.PerRound = { small = 3, full = 4, fullFrom = 16 }`, `Config.Bow.OfferingTopUp = true` |
| **On the crosshair within 60 studs, drifting beyond** | The release direction is solved so the arrow passes exactly through the point under the crosshair **only when that point is within the bow's on-target range** (recurve 60, short bow 40, +5 a star). Beyond it the bow is zeroed at that range and the arrow follows its real arc, dropping below the crosshair. No random spread: the drop is the same every time, so it can be learned. At a full recurve draw (240 studs/s, gravity 55, zeroed at 60) it drops about **1.9 studs at 100 studs and 6.5 at 150**; at half draw about 4 at 100. | `BowAimOnTarget = true`, new `Config.Bow.OnTargetRange = 60` (short bow 40), `BowZeroDistance` = the on-target range |
| **"make the distance and drawing more accurate"** (their 15 Nov gloss: "the bow's draw time and the target's distance both matter") | **Drawing:** damage and speed follow the real draw, as now, and the server still times every draw. The crosshair's two thin ticks close in as the draw fills and meet at full draw, so the player sees the draw. Holding a full draw longer than 2 s starts a slow sway (growing to 1.2° over 3 s) and drains 0.04 stamina a second; at empty stamina the string lets down. **Distance:** an arrow does full damage within the on-target range, then loses damage linearly to 75% at 90 studs beyond it (recurve: 75% at 150). The arrow's flight is simulated from the eye line for its first 2 studs, so the arrow seen leaving the bow and the hit agree. | `Config.Bow.HoldSteadyTime = 2`, `HoldSwayMax = 1.2`, `HoldStaminaDrain = 0.04`, `FalloffBeyond = 90`, `FalloffMin = 0.75` |
| **A 90-damage headshot** | Kept (built: ×1.8). Capped at 90 whatever the stars, so one arrow never takes a healthy contender. **Mild check:** a headshot is only a number. It shows the same pale hit tick with a duller "tock" sound; no text, no red, no blood, no head reaction beyond the normal hit, no cry. Roblox's maturity guide puts repeated unrealistic violence without blood at Mild; the lead confirms against the questionnaire before release. | `BowHeadshotMultiplier = 1.8`, new `Config.Bow.HeadshotCap = 90` |

Arrows per bow: the Recurve comes with 5 (was 4 to 8); the Archer kit's Short Bow with 8; an owned Short Bow with 6.

---

## 7. Where items are found (this update)

| Item | Kits | Ground (t1) | Site crates and caches (t2) | The Horn (t3) | The Offering | Wheel and boxes |
|---|---|---|---|---|---|---|
| Hunting Knife | Forager | yes | caches | — | — | yes |
| Machete | — | — | yes | yes | — | yes |
| Hatchet | — | camps | yes | yes | — | yes |
| Spear | — | — | rare | yes | — | yes |
| Longsword | — | — | — | yes (1 to 2) | 50% | yes |
| Twin-Bit Axe | — | — | rare | yes | yes | yes |
| Ring Blade | — | — | yes | yes | — | yes |
| Climbing Pick | Climber | — | yes (near rock and the north wood) | — | — | yes |
| Recurve Bow | — | — | the bow budget only | 1 on the rack | +1 if only 3 | **never** |
| Short Bow | Archer | — | weight 3, at most 6 | — | — | yes |
| Throwing Knives | Trapper | yes | yes | yes | — | — |
| Wire Snare | Trapper | — | yes | — | — | — |

The Mace leaves all tables.

---

## 8. Later: remind the owner

Their words, 12 Nov: "we will focus on attacks and battle manaeuvouring later remind me". None of this is in this update:

| Item | From their TRIBUTE spec (15 Nov) or the 12 Nov question |
|---|---|
| Quick and heavy attacks | "should attacks have visible wind-ups, a quick and a heavy attack" (still unanswered) |
| Block, with a perfect-block window | same question; "block" in their animation list |
| Parry | "parry" in their animation list |
| Dodge roll | "dodge_roll", "a 0.15s startup on every dodge" |
| Directional swings | "slash_L, slash_R, stab, overhead" |
| Knockback, stagger, hit-stop | their numbers (stagger 0.4 s, hit-stop 0.05 s, knockback by impulse) |
| Hit regions | head first, 0.15-stud generous hitboxes, 3 rays a swing |
| Durability | "a particularly rare bow might have superior construction or durability" |
| Truces / allies | approved 12 Nov; "choose their allies" in the prep room (18 Nov) |

---

## 9. For the builders

### 9.1 Config (new and changed keys)

```lua
Config.Stars = {
	Max = 5,
	DamagePerStar = 0.04, CooldownPerStar = 0.02, ReachPerStar = 0.15, -- melee and melee throws
	BowDrawPerStar = 0.03, BowSpeedPerStar = 0.02, BowOnTargetPerStar = 5,
	HitCap = 95,
	Odds = { -- per source, 1..5 stars, percent
		Kit = { 100, 0, 0, 0, 0 }, Tier1 = { 70, 25, 5, 0, 0 }, Tier2 = { 45, 35, 17, 3, 0 },
		Tier3 = { 20, 35, 30, 13, 2 }, Offering = { 0, 0, 50, 40, 10 },
	},
}
Config.Bow = {
	PerRound = { small = 3, full = 4, fullFrom = 16 }, OfferingTopUp = true,
	OnTargetRange = 60, ShortBowOnTargetRange = 40,
	HoldSteadyTime = 2, HoldSwayMax = 1.2, HoldStaminaDrain = 0.04,
	FalloffBeyond = 90, FalloffMin = 0.75, HeadshotCap = 90,
	ShortBowPerRound = 6,
}
Config.Kits = {
	Delivery = "Midpoint", -- "Midpoint" | "Start": the one-line switch
	MidpointTime = nil, -- nil = half of Config.Round.MaxRoundTime (600 on Map 1)
	MidpointShare = 0.5, MinTime = 240, PracticeTime = 60,
	WarningLead = 10, Stagger = 20, DropHeight = 140, FallTime = 7,
	LandMin = 15, LandMax = 25, BorderClearance = 30, WaterSearch = 60,
	OwnerOpenTime = 0.6, OtherOpenTime = 2.5, MarkerTime = 90, SmokeTime = 20,
	Default = "Forager", BringOwned = true,
}
Config.Economy = {
	RobuxGold = false, -- Gold packs: designed, OFF
	FullRewardsFrom = 8, HalfRewardsFrom = 4, DailySoftCap = 3000,
	-- earning and prices: sections 4.1 and 4.2
}
Config.Wheel = { FreePerDay = 1, SpinCost = 150, PaidPerDay = 10, Pity4 = 25 }
Config.Strongbox = { Cost = 400, MasterworkCost = 1200, Pity4 = 8, Pity5 = 40,
	DuplicateGold = { [3] = 100, [4] = 300, [5] = 900 } }
-- Config.Combat: BowZeroDistance follows the on-target range; ThrowAimOnTarget stays.
```

### 9.2 Code touchpoints

| Script | Change |
|---|---|
| `Shared\ItemDefs.lua` | New items (`twin_axe`, `ring_blade`, `climb_pick`, `short_bow`, `wire_snare`), new numbers (section 1.2), `starred = true` on stack-1 weapons, Mace out of every table, bows out of the random tables. |
| `InventoryService` | Slots become `{ id, count, stars? }`; stars travel with drops, pickups, death scatter and the client's inventory copy. Items with different stars never stack. |
| `LootService` + `Map1\Loot.lua` | Roll stars per source (`Config.Stars.Odds`); place the bow budget; Short Bow cap; the Offering's top-up; the kit parcel drop (spot search, chute, open times, spill). Ground items carry a `Stars` attribute. |
| `CombatService`, `ProjectileService` | Apply stars to damage, cooldown, reach, draw time and speed; the 95 hit cap and the 90 bow-head cap; distance falloff; the server checks reach with the starred range. Twin-Bit Axe armour rule; machete sweep; knife unseen hit; spear inside-4-studs rule. |
| `CombatController` | On-target range per bow and star; zero at that range beyond it; draw ticks on the crosshair; hold sway and stamina drain; Ring Blade and Twin-Bit Axe throws. |
| `ItemModels`, `art\blender\ir_weapons.py` | Four new models, the Longsword's new look, the parcel and chute; the five star finishes as variants. |
| HUD / `QuietUI` | Hotbar stars, equip line, ground label, the parcel's edge marker, kit and bring lines in the lobby, odds lines. |
| `DataService` | A saved profile with Gold, the Armoury (`{ [weaponId] = stars }`), pity counts, the last kit and the daily spin date; session-locked (economy-cosmetics §8.3). |
| New `EconomyService` | Gold earning and spending (server only; every change logged with `AnalyticsService:LogEconomyEvent`), the wheel, Strongboxes, the Armoury; Robux packs behind `RobuxGold`. |
| Lobby (the red train) | Kit racks, the wheel and its prize case. |

### 9.3 Build order

1. Stars in `ItemDefs`, inventory and combat (no UI yet), the 95 and 90 caps.
2. The bow rules (budget, on-target range, drop, draw ticks, falloff).
3. The new weapons in code with stand-in models, then their Blender models.
4. Kits and the midpoint drop.
5. Gold, the saved profile and the Armoury.
6. The wheel and Strongboxes in the train.
7. Star finishes and the star display.

Each step is shown to the owner as soon as it runs.

---

## 10. Questions for the lead (not for the builders)

1. The midpoint reading of "spawns in the half point of the game" is the lead's; the switch makes "Start" one line.
2. The economy charter said nothing random and no power for sale; the owner's 18 Nov words replace it. Turning on Robux Gold makes weapon power buyable with Robux: the owner should hear that in one line before the switch is flipped.
3. The Ring Blade IP check (1.3).
4. If every player picks Archer, there are many Short Bows. They are clearly weaker (36 max, on target to 40 studs). If the owner wants bows rarer still, cap Archer kits at a quarter of the contenders and give the rest Forager.
