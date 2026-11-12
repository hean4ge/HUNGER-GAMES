# Loot, equipment and modifications

> Pillar file for the [Roadmap](../Roadmap.md) · key `loot-equipment` · written by the loot designer, lightly edited by the lead designer so names match across pillars. Phase numbers inside this file are the pillar's own; the Roadmap's phases are the build order.

**Lead notes (where the Roadmap reconciles this pillar with the others)**

- **Roadmap phases.** This pillar's Phase 1 is Roadmap Phase 4a and its Phase 2 is 4b. Its Phase 3 is split: Patron capsules arrive with the Arena events pillar in Roadmap Phase 3, and strongboxes, special kit and the Legendaries come in Phase 10. Its Phase 4 lands in Roadmap Phase 8, after the profile.
- **Your "EFFECT DROPS (ENCHANTMENTS)" are Citadel modifications**, as your own expanded plan suggests. The paid "visual effects for items" are the Economy pillar's Finishes and Tempers, which never change a number.
- **Citadel drops** are delivered as the Arena events pillar's **Lure**, which the Warden Director places like any other event, instead of on the fixed schedule in §7.4.
- **Keepsakes are parked.** Standard keeps today's empty-handed start; character-specific equipment ships as signature gear in Story and Endless.
- **Saved data** (the collection log, finishes) goes into the one shared profile, `Profiles_v2` (Roadmap Phase 5), not into a separate DataService schema.
- **Renamed:** the collection log is now **the Arms Register**; "the Armoury" is the lobby pavilion where it is shown.
- **Lead review:** the Spire's restock is **the Offering** (IP; the code still says Feast). The Stim Autoinjector is now the **Electrolyte Draught** and the Sedative Dart the **Nettle Dart** (its status is Numbed), because Roblox's Community Standards prohibit depicting lifelike drugs; the Inject use style is dropped. The story example of signature gear is now Oss Reed's spear, and there is no signature bow for the reluctant-hunter archetype.
- **Coordinate first:** agree `InventoryService.absorb` and the `PlayerService` status API with the combat physics work (Roadmap Phase 1) before either side edits `CombatService.applyHit`.

---

Covers all of "4. Loot and equipment" and "Character-specific equipment" from "3. Character and skills". Checked against the live place (read-only) and the original build reports on 2026-11-11.

## 1. What exists today

**1.1 Items: `ReplicatedStorage.Shared.ItemDefs`**

There are 20 items, plus fists, which are hidden.

| id | Name | Kind | Rarity | Stack | Stats |
|---|---|---|---|---|---|
| fists | Fists | Melee (hidden) | – | – | 8 dmg, 0.45 s, reach 5.5 |
| knife | Hunting Knife | Melee | Common | 1 | 22 dmg, 0.45 s, reach 6 |
| machete | Machete | Melee | Uncommon | 1 | 32, 0.7 s, 7 |
| hatchet | Hatchet | Melee | Uncommon | 1 | 36, 0.8 s, 6.5 |
| spear | Spear | Melee + throw | Rare | 1 | 30 in melee, reach 9.5; 60 when thrown at 150 studs/s |
| mace | Mace | Melee | Rare | 1 | 46, 1.1 s, 7 |
| sword | Arena Sword | Melee | Epic | 1 | 40, 0.75 s, 8 |
| bow | Recurve Bow | Bow | Rare | 1 | 14–50 dmg by draw (0.9 s), 90–240 studs/s, ×2 headshot; comes with 4–8 arrows |
| throwing_knife | Throwing Knife | Throwable | Uncommon | 6 | 28 dmg; always lands as a pickup |
| arrow | Arrow | Ammo | Common | 24 | 50% recovered after a world hit |
| herbs | Healing Herbs | Heal | Common | 6 | +10 HP, 1.5 s |
| bandage | Bandage | Heal | Common | 4 | +20 HP, 2.5 s |
| medkit | Med Kit | Heal | Epic | 1 | +65 HP, 5 s |
| berries | Wild Berries | Food | Common | 10 | +12 hunger, 1 s |
| apple | Apple | Food | Common | 5 | +18 hunger, +4 thirst |
| dried_meat | Dried Meat | Food | Uncommon | 3 | +35 hunger, 2 s |
| ration | Ration Pack | Food | Rare | 2 | +55 hunger, +10 thirst, 2.5 s |
| water_bottle | Water Bottle | Drink | Common | 1 | +45 thirst; becomes an Empty Bottle |
| empty_bottle | Empty Bottle | Utility | Common | 1 | refill it at terrain water |
| leather_vest | Leather Vest | Armor | Uncommon | 1 | ×0.85 damage on every hit |
| padded_armor | Padded Armor | Armor | Epic | 1 | ×0.72 damage on every hit |

**1.2 Where loot comes from**
- **Crates and ground items.** At Countdown, `LootService.populate()` puts a crate on every Crate marker. Each crate rolls 2–4 times on `ItemDefs.LootTables[tier]`, re-rolling duplicates, and a bow brings 4–8 arrows. 65% of Ground markers also get one item. There are three crate looks (`ItemModels.buildCrate`), and a crate opens with a 0.6 s hold, spilling its items toward the opener. Ground items glow with a light in their rarity colour, and items of Rare and above also glint.
- **The Offering.** At 590 s, `ArenaService` calls `LootService.refillSpire()`: new tier-3 crates fall 55 studs onto the tier-3 Crate markers within 90 studs of the centre, under an ember beacon.
- **Death and recovery.** `InventoryService.dropAll` scatters every stack and the worn armour. Half of the arrows that hit the world drop as pickups (`Config.Combat.ArrowRecoverChance`). Thrown knives and spears always drop.
- **Markers.** `ServerStorage.ArenaData.LootSpawns` has 169 markers: exactly 10 T3_Crate and 6 T1_Crate, about 25 T2_Crate and about 128 T1_Ground. There are no tier-2 or tier-3 ground markers. `ArenaLayout` v2 `LootZones` plans the forest arena differently: 8 crates and 10 ground markers at the Spire, 4 + 6 at the plaza edge, 6 + 14 at the meadow edge, 2 + 3 at each POI and 1 + 2 at each campsite. The planned set-dressing pass will therefore regenerate the markers. `ArenaLayout.dangerAt()` was written to bias loot quality, but nothing calls it yet.
- **Volume today.** I simulated 4,000 rounds on the real tables and markers. A round starts with about 206 stacks, which is 8.6 per contender for a 6-slot inventory. That includes about 46 weapons (7.5 bows, 2.4 swords, 2.4 maces), about 7 vests, 1.8 Padded Armors, 1.8 Med Kits and about 190 arrows. The Offering adds about 30 stacks, including 3.3 bows. Loot is generous and bows are common.
- **Missing:** Patron capsules, Warden event drops, special caches and rewards.

**1.3 Inventory and hotbar**
- `InventoryService` is the source of truth. It has 6 slots (`Config.Inventory.Slots`), and each holds only `{ id, count }`, with no state of its own. There is one worn armour id (`Player.Armor`). Using items is timed on the server (`UseStart` / `UseFinish`), and the service also handles drinking, bottle refills, armour swaps and auto-equipping weapons.
- `getArmorMultiplier` returns the worn armour's flat `damageMultiplier`. `CombatService.applyHit` applies it to every hit, head hits included.
- The bow can only fire one ammo id (`def.ammo or "arrow"` in `CombatService` and `CombatController`).
- On the client, `InventoryController` predicts equips and already maps the keys One to Nine. `UIBuilder` builds a fixed 6-slot hotbar. `HUDController` shows 3D icons, a rarity line under each slot, an item-name toast ("RARE · RANGED") and an armour line that reads "ARMOR 15%".
- `MovementController.spendStamina` now exists, so melee `staminaCost` is applied. The build report listed it as missing.

**1.4 Art and first-person pipeline**
- **In the game:** the untextured v1 meshes (20 items and 3 crates), inserted as packages. They live in `ServerStorage.MeshImports.LS_Items_v1` and are built into `ReplicatedStorage.Assets.Items`, and the package caveat in `docs/handoff/ItemsArmsNotes.md` still applies. `ItemModels.build` clones the template, or falls back to a stand-in pouch for an id that has none. **New items can therefore be played before their art exists.**
- **Ready but not in the game:** the textured ItemsReal set from `art/blender/items_real.py`. It uses procedural Blender builders and 4 texture sets of 1024² colour, normal, roughness and metalness maps, exported with tangents. `integrate:items-realistic` is scheduled in `docs/handoff/Part2Plan.md`. New items should be built in this style, after that swap.
- **First person:** each item has an entry in `ViewmodelController.Rig.HOLDS`, and each kind has a pose in `Poses.HOLD`: Fists, Blade, Spear, SpearRaised, Bow, Throwable, Item, Armor, Cradle and Carry. The use styles are Eat, Drink, Bandage and Armor. **Third person:** the held model is welded to RightHand. Nothing plays `CombatAction` on other players' characters yet, so two-handed items have no third-person pose.

**1.5 Gaps in this pillar:** durability or any per-item state, modifications, traps, packs, special equipment, Legendary items (the tier exists but nothing uses it), drops driven by need or by events, rewards, and character gear.

## 2. Goals
1. **Real kit, made by the Citadel.** Every item is a real-scale physical object. A modification is an engineered part you can see: a steel plate in a vest pocket, blued steel, a bone whistle behind an arrowhead. Nothing glows and nothing has runes.
2. **Readable on both sides.** The owner reads what a mod does in the HUD. Opponents see it on the model: a burning arrow, a plate, a pack on someone's back.
3. **A scarcity curve that fits 15 minutes.** A tense start, a richer night, a decisive Offering and a lean endgame inside the border.
4. **Choices, not upgrades.** Gear and mods cost something: noise, weight, a slot or light at night. Armour wears out.
5. **Fair.** Nothing that changes a number is sold. Random loot only comes from playing.

## 3. Four decisions that shape the rest
**3.1 Durability.** The game has none today. The decision for each kind of item:
- **Armour: yes, as integrity.** A vest absorbs part of each hit and loses that much integrity. At 0 it is torn and stops protecting until it is mended. The Leather Vest has 40 and the Padded Armor 60, shown on the HUD's existing ArmorLine. Armour becomes a resource, and this slows down whoever wins the Spire.
- **Arrows already break:** only half are recovered. Carbon Arrows are the durable kind, recovered 90% of the time.
- **Traps** have a fixed number of triggers.
- **Melee weapons and bows: no wear in Standard rounds.** A steel blade does not fail in 15 minutes, and a weapon breaking mid-duel feels random. The note "Improved weapon durability." becomes three things: Tempered Edge (holds its edge and cuts through armour), Plate Insert and Carbon Arrows. Weapon wear could be a rule for Endless Arena or Story mode later (an open question).

**3.2 Items carry state.** A slot becomes `{ id, count, mods?, wear?, charges? }`. Only items without state stack. Anything with state has a stack of 1; weapons, armour, packs and canteens already do. `give`, `spawnGroundItem`, `dropAll`, thrown-weapon recovery and `InventoryUpdate` all carry the state, so a fitted plate survives drops, deaths and pickups. The payload change only adds fields, so older clients keep working.

**3.3 Arrows and darts go in a quiver, not the hotbar.** With five arrow types, ammo in slots would fill a 6-slot inventory. The quiver is `inv.ammo = { arrow = 12, broadhead_arrow = 3 }` and holds 24, or 30 with a Rucksack and 40 with the Frame Pack. A new `CycleAmmo` action picks the arrow type: R, DPadRight, or tapping the ammo chip by the draw meter. The bow fires the selected type. `InventoryService.has/take/count` still work for ammo ids, so `CombatService` changes very little.

**3.4 One stat resolver.** `Shared.ItemStats.resolve(itemId, state, wearer?)` returns an item's effective numbers: the base def, then mods, then wear, and later Keepsakes and Talents. Combat, projectiles, the inventory and the HUD read it instead of raw `ItemDefs`. Mods, character gear and the Modes pillar's Talents all plug in at that one place.

## 4. Citadel modifications: the user's "EFFECT DROPS (ENCHANTMENTS)"
The user's "EFFECT DROPS (ENCHANTMENTS)" become **Citadel modifications**: parts engineered in the Citadel's workshops that the Wardens send into the arena to stir things up.

**How players get them**
- **Citadel cases.** A small steel case with the Citadel hallmark and one mod kit inside, opened with a 1 s hold. A quarter of Spire crates hold one, two arrive by parachute at the Offering, three more fall on a schedule (§7.4), and Gilded Patron capsules can carry one.
- **Items that come with a mod.** Weapons and armour roll for a mod: 5% from POI crates, 15% at the Spire and 25% at the Offering.
- **Mod kits in the loot tables.** Uncommon kits at POIs and Rare kits at the Spire.

**How they are fitted.** Hold the kit, then hold Attack for 3 s. The server times it, as it does bandaging. Weapon kits fit the last weapon of the right type you held. Armour kits fit what you wear. Trap kits fit the armed trap you are looking at. The hint says what the kit will fit: "Fit Plate Insert → Leather Vest". Each item takes one mod, which cannot be replaced; Legendaries come with two fixed ones. Once fitted, the item's model changes, its hotbar card gets an ember notch and its name toast reads "LEATHER VEST · PLATE INSERT".

| Mod | Note it answers | Fits | Effect | What you see | Rarity | Phase |
|---|---|---|---|---|---|---|
| Plate Insert | "Improved weapon durability." | vests | +25 integrity; pierce multiplier 0.1 better | a steel plate showing in the front pocket | Rare | 1 |
| Tempered Edge | "Improved weapon durability." | knife, machete, hatchet, sword | armour loses twice what it absorbs from your hits | blued blade, bright honed bevel, hallmark | Rare | 1 |
| String Dampers | "Special arrow types." (the bow side) | bows | draw, release and arrow whiz heard at 40% of the range | two fur silencers on the string | Uncommon | 1 |
| Citadel Limbs | "Special arrow types." | Recurve Bow | draw 0.9 → 0.72 s; no tremble before 4 s | black laminated limbs with ember tips | Epic | 2 |
| Balanced Haft | "Improved weapon durability." | spear, throwing knife | throws 20% faster and drop 20% less | brass balance ring and cord wrap | Rare | 2 |
| Ghillie Netting | "Enhanced camouflage." | body layer, with or without a vest | concealment 0.5; off while sprinting; tinted to the biome it was found in | jute strips over the shoulders and back | Uncommon | 2 |
| Chameleon Weave | "Enhanced camouflage." | body layer | concealment 0.7; tint matches the ground within 2 s; cancelled by flares and fire within 20 studs | matte cloak with a slow tone shift | Epic | 2 |
| Load Straps | "Increased carrying capacity." | packs | +1 slot; halves the pack's sprint penalty | compression straps and a side pouch | Uncommon | 2 |
| Spring Coil | "Improved trap effectiveness." | Wire Snare | holds 4 s; re-arms once | steel spring at the stake | Rare | 2 |
| Steel Wire | "Improved trap effectiveness." | snare, tripwire | no glint; visible only within 4 studs instead of 6 | thin dark wire | Uncommon | 2 |
| Barbed Stakes | "Improved trap effectiveness." | Stake Trap | its hit also causes Bleeding | barbed stake tips | Rare | 2 |

**Concealment** is a server-side number, the character attribute `Concealment`. Splices from Warden events notice a concealed contender at (1 − concealment) of their usual range. Other players just see the netting or weave on the model; there are no transparency tricks. Sprinting, flares and firelight expose you.

## 5. New and expanded categories
**5.1 Special arrows and darts**, for "Special arrow types.". They all sit in the quiver, and the bow's draw curve is unchanged.

| Ammo | Rarity | Damage (full draw) | Effect | Recovered | Look | Phase |
|---|---|---|---|---|---|---|
| Arrow | Common | 50 | – | 50% | today's arrow | – |
| Carbon Arrow | Uncommon | 50, flatter (gravity ×0.85) | – | 90% | black shaft, ember fletching | 1 |
| Broadhead | Rare | 45 | a body hit causes Bleeding | 50% from the world, never from a body | three-blade steel head | 1 |
| Pitch Arrow | Rare | 40 | burns in flight, lighting up the archer at night. A body hit sets the target Burning (2 HP/s for 3 s). A world hit leaves a fire patch (radius 5 studs, 8 s, 4 HP/s) that does not spread and goes out in water | never | head wrapped in rag and pitch | 1 |
| Whistler | Uncommon | 30 | shrieks in flight (heard up to 60 studs). On a world hit, everyone hears 3 s of footsteps and brush at that spot (`AudioController.footstepAt`) | 50% | drilled bone whistle behind a blunt head | 1 |
| Flare Arrow | Rare | 30 | a magnesium flare lights 45 studs for 20 s and cancels concealment there | never | brass flare canister head | 3 |
| Dart / Toxin Dart / Nettle Dart | Common / Rare / Rare | 6 / 6 / 4 | – / Poisoned (1.5 HP/s for 8 s, no regeneration) / Numbed (5 s at −20% speed, no sprint) | 50% / never / never | colour-banded darts | 3 |

**5.2 Traps**, for "Snares, tripwires and improvised traps.". Traps catch people and raise alarms; they never kill outright.

| Trap | Rarity | Placing | Effect | Triggers | Look |
|---|---|---|---|---|---|
| Wire Snare | Uncommon | 1 s on ground up to a 30° slope; arms after 2 s | holds a leg for 2.5 s (tap Interact to wriggle free in about 1 s), 5 dmg, a loud snap, a ping for the owner | 1; the owner re-arms it in 2 s | coiled brass wire on a whittled stake |
| Tripwire Kit | Uncommon | two stakes 4–14 studs apart (two presses) | a can of pebbles clatters, heard up to 70 studs; the owner gets a ping with a direction | 3 | two stakes, wire, a tin can |
| Stake Trap | Rare | 1.5 s in grass or soft ground | 25 dmg and −30% speed for 3 s (a Limp once wounds exist) | 2 | spring board with sharpened stakes under leaves |

**Rules for traps**
- Each contender can have 3 armed traps, and the arena 40 at once.
- No traps within 70 studs of the Spire during the first 60 s, on or within 8 studs of a launch plate, or in water.
- Others can spot a trap's glint or wire within 6 studs. Crouch and interact for 2 s to disarm and take it.
- Traps stay after their owner falls, but the owner pings stop.

**5.3 Packs and carrying capacity**, for "Backpacks, food, water." and "Increased carrying capacity.".

| Pack | Rarity | Slots | Quiver | Cost | Look |
|---|---|---|---|---|---|
| none | – | 6 | 24 | – | a hip quiver comes with the bow |
| Satchel | Uncommon | 7 | 24 | – | canvas shoulder bag |
| Rucksack | Rare | 8 | 30 | sprint −3% | waxed canvas, leather straps |
| Citadel Frame Pack | Epic | 9 | 40 | sprint −5%, stamina drain +5% | aluminium frame, ember strap tags |

**Rules for packs**
- You wear one pack, in a new Back slot. Hold Attack to put it on, as with armour.
- Everyone can see a pack on your back.
- When you fall, the pack drops and its extra slots scatter like the rest of your items.
- Slots 7–9 use the keys 7–9, which `InventoryController` already maps.

**5.4 Special equipment**, for "Blow darts, technical equipment and rare tools.".

| Item | Rarity | Use | Phase |
|---|---|---|---|
| Blowpipe | Rare | hold Attack to puff; Aim steadies; useful to about 40 studs; nearly silent (heard within 8 studs); darts go in the quiver | 3 |
| Field Glasses | Uncommon | Aim zooms 4× and steadies. In daylight, others see a lens glint when you face the sun | 3 |
| Hand Flare | Uncommon | thrown; burns 25 s and lights 35 studs; cancels concealment | 3 |
| Pry Bar | Uncommon | blunt melee weapon (24 dmg); opens Warden strongboxes in 2 s instead of 6 and Citadel cases silently | 3 |
| Grapple Line | Epic | climb marked cliff faces in the Cliffs biome; needs the movement owner | later |

**5.5 Field medicine**, for "Bandages, medicines, treatment supplies." and "Improved medical equipment.".

| Item | Rarity | Use time | Effect | Phase |
|---|---|---|---|---|
| Healing Herbs | Common | 1.5 s | +10 HP; halves any Poison left | today, plus the cure in 1 |
| Bandage | Common | 2.5 s | +20 HP; stops one Bleeding stack | today, plus the cure in 1 |
| Field Dressing | Uncommon | 2 s | +25 HP; stops all Bleeding | 1 |
| Mending Kit | Uncommon | 3 s | +25 integrity to the armour you wear | 1 |
| Splint | Uncommon | 3 s | +10 HP; cures Limp, once wounds exist | 2 |
| Antitoxin | Rare | 1.5 s | cures Poisoned and Numbed | 2 |
| Electrolyte Draught | Epic | 2 s, drunk | +30 HP over 10 s; stamina regenerates ×1.6 and you cannot become exhausted for 20 s; one at a time | 2 |
| Med Kit | Epic | 5 s | +65 HP; also stops Bleeding and cures Limp | today, plus the cures in 1–2 |

Today both `InventoryService` (`onUseStart`) and `InventoryController` refuse treatment at full health ("You're not hurt"). Both must allow it when the item would cure a status.

**5.6 Survival supplies.** Food and water stay as they are. New: the **Steel Canteen** (Uncommon). It holds 3 drinks of +30 thirst, refills at water and keeps its `charges` in the item state. Packs are in §5.3.

**5.7 Armour and Legendary prototypes**

| Armour | Rarity | Integrity | Multiplier: cut / chop / blunt / pierce |
|---|---|---|---|
| Leather Vest | Uncommon | 40 | 0.70 / 0.80 / 0.90 / 0.80 |
| Padded Armor | Epic | 60 | 0.50 / 0.60 / 0.75 / 0.60 |
| with a Plate Insert | – | +25 | pierce 0.1 better |
| Citadel Plate Carrier | Legendary | 110 | 0.45 / 0.50 / 0.70 / 0.40 |

The damage-type multipliers come from `docs/research/CombatPhysicsPlan.md` §3.5. Until hit zones exist, integrity applies to every hit, as the flat multiplier does today. Once they exist, it applies to the torso only. The second Legendary is the **Citadel Compound Bow**: a 0.6 s draw, 16–54 dmg, 90–270 studs/s, no tremble, and String Dampers built in.

## 6. Rarity tiers
The five tiers and colours already exist (`ItemDefs.RarityOrder`, `Theme.Rarity`). What changes is that each tier now has a meaning, a set of places it spawns and a cap.

| Tier | Meaning | Where it spawns | Cap |
|---|---|---|---|
| Common (grey) | basic tools, food, plain arrows | everywhere | – |
| Uncommon (green) | better basics, simple traps, Uncommon kits | campsites, POIs | – |
| Rare (blue) | bows, spears, maces, special arrows, Rare kits | a few at POIs; the Spire | – |
| Epic (purple) | Arena Sword, Padded Armor, Med Kit, Frame Pack, Epic kits | the Spire, the Offering, Gilded capsules | Patron capsules only carry Epic items after the Offering |
| Legendary (amber) | Citadel prototypes | the Offering roll, Warden strongboxes, Gilded capsules | 1 per round, announced |

Two more rules:
- **Danger bias.** POI rolls get up to 10% extra chance of using the next tier's table, scaled by `ArenaLayout.dangerAt()`, so dangerous places pay better.
- **Mods stay separate from rarity.** A mod never changes an item's rarity colour; it shows as the ember notch. Legendaries carry a brass Citadel seal on the mesh rather than a stronger glow.

## 7. Drop sources and spawn tables
**7.1 Sources**

| Source | When and where | Table | Notes |
|---|---|---|---|
| Scatter | about 110 tier-1 ground markers, 40% chance each | Scatter | food, water, herbs, plain arrows, a few knives, snares, flares |
| Campsites | 7 tier-1 crates, 1–2 rolls | Camp | basics, snares, tripwires, satchels |
| POIs | about 29 tier-2 crates (1–3 rolls) and about 50 ground markers (40%) | POI / POIGround | most real weapons, vests, traps, packs, Uncommon kits |
| The Spire | 12 tier-3 crates (2–3 rolls) and 16 ground markers (60%) | Spire / SpireGround | Epic weapons and armour, special arrows, Rare kits; 25% of crates hold a Citadel case |
| The Offering (590 s) | Spire crates refilled | Spire, plus extras | 2 Citadel cases by parachute; a 50% Legendary roll if none has spawned |
| Citadel drops | 3 per round, at POIs inside the border | CitadelCase | announced; the case lands under a drogue chute |
| Patron capsules | earned Favour (the Arena events pillar) | Patron, by need (§7.5) | lands 20–35 studs away; only the recipient can open it for the first 8 s |
| Warden strongboxes | the end of each Warden event | Strongbox | a noisy 6 s open, or 2 s with a Pry Bar |
| Fallen contenders | on death | – | as today; packs drop too |

**7.2 Tables.** Weights first, then counts in brackets; tuned for the v2 marker plan. `LootService.rollItems` already skips unknown ids, so each row can be added when its item exists. The tables should filter out unknown ids when they load, though, so the odds stay right.
- **Scatter:** berries 16 (2–5), apple 11 (1–3), herbs 9 (1–3), water bottle 8, bandage 6 (1–2), empty bottle 5, dried meat 5, arrows 5 (2–4), Wire Snare 3, knife 2, Hand Flare 2.
- **Camp:** bandage 7, dried meat 7, water bottle 7, arrows 6 (3–6), knife 5, herbs 5, hatchet 4, Wire Snare 4, throwing knife 3, Satchel 3, Hand Flare 3, canteen 2, Tripwire Kit 2.
- **POI:** arrows 7 (5–9), machete 6, hatchet 6, bandage 6, dried meat 6, water bottle 6, Leather Vest 5, throwing knife 4 (2–3), knife 3, Pry Bar 3, bow 3 (plus 4–8 arrows), Carbon Arrows 3 (3–5), Field Dressing 3, ration 3, Wire Snare 3, Tripwire Kit 3, Satchel 3, spear 2, Whistlers 2 (2–3), canteen 2, Field Glasses 2, Uncommon kit 2, Rucksack 1, Stake Trap 1, Blowpipe 1 (plus 6–10 darts).
- **POIGround:** arrows 8 (3–6), bandage 7, dried meat 7, herbs 6, apple 6, water bottle 6, throwing knife 3, knife 3, Wire Snare 3, Hand Flare 3, Whistlers 1, Field Dressing 1.
- **Spire:** bow 6, arrows 6 (8–12), spear 6, Arena Sword 5, mace 5, Leather Vest 4, throwing knife 4 (3–5), ration 4, water bottle 4, Rare kit 4, Broadheads 3 (3–5), Padded Armor 3, Med Kit 3, Field Dressing 3, Rucksack 3, Pitch Arrows 2 (2–4), Flare Arrows 2 (2–3), Stake Trap 2, Antitoxin 1, Blowpipe 1.
- **SpireGround:** arrows 8 (4–8), bandage 5, water bottle 5, throwing knife 4, ration 4, Field Dressing 3, knife 3, Broadheads 2, spear 2, Hand Flare 2.
- **CitadelCase:** an Uncommon kit 50%, Rare 40%, Epic 10%. At the Offering and in Gilded capsules: Rare 70%, Epic 30%.
- **Legendary:** the Citadel Compound Bow or the Citadel Plate Carrier, 50/50, never twice in one round.

**7.3 Loot per round** (simulated over 4,000 rounds)

| | Today (current markers) | Proposed (v2 marker plan) |
|---|---|---|
| Stacks at the start | ~206 (8.6 per contender) | ~173 (7.2) |
| Weapons | ~46 (1.9 per contender) | ~31 (1.3) |
| Bows at the start / added by the Offering | 7.5 / 3.3 | 4.5 / 2.5 |
| Swords + maces at the start / added by the Offering | 4.8 / 4.8 | 4.2 / 4.2 |
| Vests / Padded Armor | 7.1 / 1.8 | 5.0 / 1.3 |
| Arrows | ~190 | ~125 plain + ~24 special |
| Mod kits | 0 | ~3 at the start, ~2 from the Offering's tables, 2 Offering cases and 3 Citadel drops: about 10, plus 2–3 items that come with a mod |
| Traps / packs | 0 / 0 | ~10 / ~5 |

**7.4 How drops are paced across the round.** This uses `Config.Round.DaySchedule` and `Config.Events`.

| Time | Drop |
|---|---|
| 0:00 | the launch: the Spire and the world are stocked |
| ~2:00 | Patron capsules can start arriving (Favour thresholds) |
| 3:30 | Citadel drop 1 at a tier-2 POI, announced ("A CITADEL CASE IS FALLING · WATCHTOWER") |
| 5:45 | Roll Call 1, then night: capsules lean toward flares and Flare Arrows |
| 6:45 | Citadel drop 2: the case blinks a beacon in the dark |
| 9:50 | the Offering: the Spire is refilled, 2 Citadel cases fall and the Legendary roll happens |
| 11:30 | Citadel drop 3, inside the final third of the border; capsules favour medicine |
| 13:47 | Roll Call 2; last fights until 15:00 |

`ArenaService` owns the schedule (`Config.Events.CitadelDrops = {210, 405, 690}`) and calls a new `LootService.dropCase(kind, position, opts)`. Warden events run on their own schedule, owned by the Arena events pillar, and end with a strongbox.

*Lead note (Roadmap): the Citadel drops are delivered as the Arena events pillar's **Lure**, which the Warden Director places like any other Warden event, instead of on this fixed schedule. One event at a time still holds.*

**7.5 Patron capsules (what goes inside).** The Arena events pillar decides how Favour is earned. This pillar picks the contents from the contender's needs, with a little randomness:
- **Health below 50, or a status:** Field Dressing, Bandage ×2 or Antitoxin. A Med Kit only after the Offering.
- **Hunger or thirst below 35:** a Water Bottle or Canteen, or a Ration Pack.
- **Only fists or a knife:** a spear or machete. A bow and arrows only from Fine capsules and up.
- **Holding a bow with fewer than 6 arrows:** 8 arrows and 2 special arrows.
- **At night:** a Hand Flare or Flare Arrows.
- **No armour:** a Leather Vest, or a Mending Kit if your armour is below 50%.

There are three capsule grades: Basic (up to Uncommon), Fine (up to Rare) and Gilded (Epic after the Offering; may hold a Citadel case or the round's single Legendary). The capsule is a matte steel canister under an ember-and-charcoal drogue chute, and it trails smoke when it lands, so everyone knows where it is.

**7.6 Warden strongboxes.** Each strongbox holds one Rare-or-better item from the Spire table, plus a mod kit 60% of the time (Rare; Epic 15%). Opening it takes 6 s and sounds a klaxon. With a Pry Bar it takes 2 s and stays quiet.

## 8. Balance for a 15-minute round
**Hits to kill** a 100 HP contender. The integrity model is on the left of each cell, today's flat multiplier in brackets.

| Weapon | No armour | Leather 40 | Padded 60 | Padded + Plate 85 |
|---|---|---|---|---|
| Hunting Knife (cut 22) | 5 (5) | 7 (6) | 8 (7) | 9 (7) |
| Machete (cut 32) | 4 (4) | 5 (4) | 5 (5) | 6 (5) |
| Hatchet (chop 36) | 3 (3) | 4 (4) | 5 (4) | 5 (4) |
| Mace (blunt 46) | 3 (3) | 3 (3) | 3 (4) | 3 (4) |
| Arena Sword (cut 40) | 3 (3) | 4 (3) | 4 (4) | 5 (4) |
| Spear (pierce 30) | 4 (4) | 5 (4) | 6 (5) | 7 (5) |
| Arrow, full draw (pierce 50) | 2 (2) | 3 (3) | 4 (3) | 4 (3) |

- In the first fight, armour adds about one hit, then it wears out. The mace stays a 3-hit armour breaker. A tempered sword kills padded armour plus a plate in 4 hits instead of 5.
- **Statuses** stay non-graphic: a HUD icon and a desaturated vignette, never blood. They deal damage through `PlayerService.damage` with new causes `Bleed`, `Fire`, `Poison` and `Trap`, and kill credit for a status death uses `KillCreditWindow`.
  - **Bleeding:** 1 HP/s for 6 s per stack, up to 3 stacks, and no regeneration while it lasts.
  - **Burning:** 2 HP/s for 3 s.
  - **Poisoned:** 1.5 HP/s for 8 s.
  - **Numbed:** 5 s.
  - **Snared:** up to 2.5 s.
- **Caps:** one Legendary per round. One mod per item. 3 traps per contender and 40 in the arena. At most 4 fire patches at once, and none in the first 30 s.
- **Keeping leaders in check:** armour wears, Mending Kits are scarce (about 3 per round), Patron capsules weigh need, and a well-stocked contender is visibly carrying a pack.

## 9. Special rewards
**During the round:**
- The Offering's Citadel cases and Legendary roll, announced as "A CITADEL PROTOTYPE LIES IN THE OFFERING".
- Warden strongboxes and the scheduled Citadel drops.
- Optionally, with the Arena events pillar: the leader after Roll Call 1 is "marked by the Wardens", and whoever eliminates them earns a Gilded capsule.

**After the round** (saved, and always the same reward for the same achievement):
- **The Arms Register**, a collection log kept in the lobby's Armoury pavilion. The first time you find or use each item and each mod, it is recorded. Completing a category unlocks a cosmetic finish such as "Field-worn" leather or "Blued" steel.
- **Laureate finishes.** Winning gives a laurel finish to the weapon you won with.
- **Mastery finishes**, for example from bow kills.

Gold amounts are set by the Economy pillar. Rewards are earned only. If a reward ever involves chance, it must be free: Roblox does not count random rewards earned through play as paid random items. Keys, rerolls and capsule openings are never sold.

## 10. Character-specific equipment
- **Standard rounds: Keepsakes.** Before a round you choose one Keepsake you have unlocked, and it starts in slot 1 at Countdown (`InventoryService.give` on `RoundService.roundStarting`). Keepsakes are small and equal in value, about one Uncommon item: a Wire Snare, a Hand Flare, a Field Dressing, a Steel Canteen or a Satchel. If the Modes pillar uses Province backgrounds, each Province suggests one, for example a snare for Timberline or a canteen for Saltmarsh. They are unlocked by playing and never sold, because they affect play. Their cosmetic variants can be sold. *Lead note (Roadmap): parked. Standard keeps today's empty-handed start; character-specific equipment ships as signature gear in Story and Endless.*
- **Story mode: signature gear** for each playable character, built from existing items with a fixed mod. For example, Oss Reed's fowling spear is a Spear with a Balanced Haft (story-world §5 gives him spear, traps and swimming). Signature gear unlocks through that character's arcs.
- **Data:** a `DataService` v2 schema holds the Arms Register, the Keepsakes you have unlocked and the one you have selected, migrated from `PlayerStats_v1`. The picker goes in `LobbyController`.

## 11. Code changes by module

| Where | Change | Phase |
|---|---|---|
| `Shared.ItemDefs` | new kinds Trap, Pack, Kit, Blowpipe, Tool; fields `damageType`, `integrity`, `armour` (multiplier table), `ammoFamily`, `effect`, `slots`, `quiver`, `fits`, `charges`; the new ids | 1–3 |
| `Shared.LootTables` (new) | the per-source tables, the chance of an item coming with a mod, per-round caps and the Legendary table; replaces `ItemDefs.LootTables` | 1 |
| `Shared.ItemStats` (new) | `resolve()`, used by combat, projectiles, the inventory and the HUD | 1 |
| `InventoryService` | slot state; the quiver and ammo selection; `absorb(player, damage, damageType, zone?)` replaces `getArmorMultiplier` in `applyHit`; fitting kits and putting on packs through `UseFinish`; 6–9 slots; the Back slot; `InventoryUpdate` gets new fields | 1–2 |
| `LootService` | `rollFrom(source, context)` with caps and the danger bias; `spawnGroundItem(..., state?)` (attribute `State`); `dropCase()` for Citadel cases, capsules and strongboxes (parachute descent, recipient-only window); Offering extras | 1–3 |
| `CombatService`, `CombatController`, `Shared.Input` | fire the selected ammo; damage from `ItemStats`; pass the damage type to `absorb`; a `CycleAmmo` action; the blowpipe | 1, 3 |
| `ProjectileService`, `ProjectileController` | `opts.effect` on impact (status, fire patch, decoy noise, flare light); recovered items keep their state | 1 |
| `PlayerService` | a small set of statuses with damage causes and status attributes, built so that the combat plan's wounds (its Phase 3) extend it | 1–2 |
| `TrapService`, `TrapController` (both new) | a `PlaceItem(slot, cframe, cframe2?)` remote, checked on the server; arming; overlap checks 10 times a second; owner pings; caps; cleanup in `clearAll` | 2 |
| `ArenaService` | Offering extras (Phase 1); the Citadel drop schedule and strongbox hooks (Phase 3) | 1, 3 |
| `HUDController`, `WorldGen.UIBuilder` | the mod notch and "ITEM · MOD" toast; ArmorLine shows integrity; an ammo chip; 6–9 slots; a Back-slot chip; status icons | 1–2 |
| `ViewmodelController` (`Rig`, `Poses`) | `Rig.HOLDS` entries; new use styles Apply and Place; new holds Blowpipe and Raise | 1–3 |
| `CharacterVisuals` | show packs, netting and plates on other players, fitted to each avatar's measured rig; later, play `CombatAction` so two-handed items have a third-person pose | 2–3 |
| `AudioController`, `Shared.Sounds` | new sound keys; the String Dampers range; decoys through `footstepAt` | 1–3 |
| `ItemModels`, `WorldGen.ItemAssets` | `build(id, variant, state)` adds mod parts (tagged Role "Mod"); `ICON`/`REST` entries; templates | every phase |
| `DataService` | the v2 schema (§10) | 4 |
| `docs/GameDesign.md` §8–10 | the new remotes, payload fields, attributes and tags | every phase |

## 12. Art and first-person cost
Every new item needs:
- a builder in the ItemsReal style: about 40–80 lines with the `ir_geo` helpers, grip at the origin pointing +Z;
- a manifest entry with Grip and Tip attachments (plus Nock, Mouth, Back or Ground where it needs them);
- a texture set, an `ItemAssets` template, `ICON`/`REST` rotations, a `Rig.HOLDS` entry and sound keys.

With AI help that is about half a day for a small item and 1–2 days for a medium one.

| Group | Meshes | Texture set | First person | Third person / world | Cost |
|---|---|---|---|---|---|
| 5 arrows, 3 darts | head variants on the shared shaft; Nock + Tip | new IR_Kit | existing arrow hold and nocking | flame and smoke (Pitch), light (Flare) | S each, ~2 days |
| Citadel case, 7 mod kits, Mending Kit | small props with a Grip | IR_Kit | Item/Carry hold plus a new Apply use style | on the ground and under a parachute | S each, ~3 days |
| 11 mod visuals on their targets | add-on parts or material variants, tagged Role "Mod" | IR_Kit and existing sets | must pass the bow-aim screen-coverage check again | readable on other players | S–M each, ~4 days |
| 3 traps | stake, coil, board, can; armed and sprung states | new IR_Traps | new Place use style (kneel, hands down) | placed models, sprung animation | M each, ~4 days |
| 3 packs, Ghillie Netting, Chameleon Weave | worn, with a Back attachment; must fit any avatar size | new IR_Wear | none | accessories scaled to the measured rig | M each, ~6 days |
| 4 medical items, canteen | – | IR_Kit | existing Cradle/Grip holds and Bandage/Drink uses | – | S each, ~2 days |
| Blowpipe, Field Glasses, Hand Flare, Pry Bar | Grip + Tip; the blowpipe also needs SupportGrip and Mouth | new IR_Special | new Blowpipe and Raise holds (M each); the flare uses the Throwable hold, the pry bar the Blade hold | two-handed third-person poses | S–M each, plus ~3 days of poses |
| 2 Legendaries | a compound bow with cams and cables that keeps Nock, StringTop, StringBottom and ArrowRest; a plate carrier | IR_Special | the existing Bow and Armor holds | – | M each, ~3 days |
| Patron capsule and chute, Warden strongbox | – | new IR_Drops | – | descent, chute collapse, lid | M each, ~3 days |

**In total:** about 38 meshes and 11 mod add-ons. That means 5 new texture sets (20 PNG uploads) and one GLB upload per phase batch, reusing asset ids and never re-uploading to get around moderation. It adds up to roughly 6–7 weeks of art and 2 weeks of first-person work, spread across the phases.

## 13. Guard rails
- **Nothing that changes a stat is sold**, for Robux or for Gold (which Robux can buy): no mod kits, Citadel cases, capsules, packs or Keepsakes. Gold buys cosmetic finishes only. The Wardens' Gauntlet (the premium mode) gets different loot tables and modes, not stronger items in Standard.
- **No paid random items.** Roblox counts random items bought directly or through Robux-bought currency as paid random items. Those need percentage odds shown before purchase and must respect `PolicyService` `ArePaidRandomItemsRestricted`. All random loot here is earned in play.
- **Cosmetics must not affect what other players can read.** Weapon finishes, trails and other paid visuals only touch parts tagged Finishable, and they must never:
  - hide a functional cue such as a Pitch Arrow's flame, the mod notch or a plate;
  - make the wearer or their shots harder to see: no camouflage patterns, no very dark worn items, no near-white worn items on snow maps, and no trail or capsule smoke less visible than the default;
  - add light at night;
  - change a silhouette or hitbox.
- **Content.** Statuses use icons and vignettes, with no blood, and fire looks realistic but not gory. With ragdolls the combat plan already expects a Moderate label, which can reach Roblox Select players (9–15) once the game passes Roblox's all-ages evaluation. So there are no timed offers on gear, no near-miss reveal animations and no streak pressure.
- **Original IP.** Stay away from survival props that are iconic of the source franchise: poisonous berries as a weapon, wasp nests, silver sponsor parachutes, a trident as a signature weapon. Capsule chutes are ember and charcoal. No signature bow for the reluctant-hunter archetype.

## 14. Phases

| Phase | Scope | Size |
|---|---|---|
| 1. Foundations and Citadel effect drops | item state, `ItemStats`, `LootTables` v2 with the table cut, armour integrity and the Mending Kit, the quiver and `CycleAmmo`, Carbon, Broadhead, Pitch and Whistler arrows, Bleeding and Burning, Plate Insert, Tempered Edge and String Dampers, Citadel cases at the Spire and the Offering, rarity rules and caps | L (2–2.5 weeks) |
| 2. New categories | traps and their three mods; packs, Load Straps and 6–9 slots; field medicine and statuses (with the combat plan's Phase 3); Ghillie Netting and Chameleon Weave; Balanced Haft; Citadel Limbs; the canteen | XL (4–5 weeks) |
| 3. Drops and special kit | Patron capsules (with the Arena events pillar), Warden strongboxes (with the Arena events pillar), Citadel drops, blowpipe and darts, Field Glasses, Hand Flare, Flare Arrow, Pry Bar, the two Legendaries and their reveal | XL (~4 weeks) |
| 4. Progression | the Arms Register, Laureate and mastery finishes, Keepsakes and signature gear, `DataService` v2, the readability rules for cosmetics (with the Economy pillar's cosmetics) | L (~2 weeks) |

The art for each phase runs in parallel, using stand-in pouches until the meshes land. ItemsReal should be integrated first, so new items do not sit next to the untextured v1 set.

## 15. First slice: "Citadel effect drops"
The aim is to make the user's "EFFECT DROPS (ENCHANTMENTS)" playable in a normal round in about two weeks. The scope is the core of Phase 1, in five parts.

1. **Item state.** Add slot state, the additive `InventoryUpdate` fields, `Shared.ItemStats` and `Shared.LootTables` with the reduced tables.
2. **Armour integrity.** `InventoryService.absorb` with damage types, the integrity line on the HUD, and the Mending Kit.
3. **The quiver.** `CycleAmmo`, and the Broadhead, Pitch and Whistler arrows with Bleeding, a fire patch and the decoy noise.
4. **Mod kits.** Plate Insert, Tempered Edge and String Dampers, fitted by holding Attack; the ember notch and "ITEM · MOD" toast.
5. **Citadel cases.** One in 25% of Spire crates, and two by parachute at the Offering.

**Art:** stand-ins on day one, then one IR_Kit batch: three arrowheads, the case, the kits and blued-steel variants.

**It is done when:**
- a sandboxed server simulation, like the build agents used, shows each arrow effect, integrity draining and being mended, a fitted mod surviving drop, death and pickup, and the caps holding;
- then a two-player playtest confirms the feel.

Sources: [Roblox paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items), [Roblox content maturity](https://create.roblox.com/docs/production/promotion/content-maturity).

---

## Checklist items in this pillar

Status, size and Roadmap phase match the master checklist in the [Roadmap](../Roadmap.md).

### 21. “Equipment drops”

- **Our name:** Supply drops: crates, ground caches, the Offering, Citadel cases, Patron capsules and Warden strongboxes
- **Status:** Partly built · **Size:** L · **Roadmap phase:** 3 → 4 → 10
- **Pillar phase:** Phase 1 (LootTables v2, Citadel cases at the Spire and the Offering), then Phase 3 (Patron capsules, Warden strongboxes, scheduled Citadel drops)
- **From the notes:** "Equipment drops" (4. Loot and equipment)
- **Evidence:** Built: LootService.populate() puts crates on Crate markers (2–4 rolls from ItemDefs.LootTables[1..3], three crate looks via ItemModels.buildCrate) and an item on 65% of Ground markers. LootService.refillSpire() drops tier-3 crates from 55 studs at the Offering (ArenaService, Config.Events.FeastTime = 590). InventoryService.dropAll scatters a fallen contender's items, and ProjectileService recovers 50% of arrows. ServerStorage.ArenaData.LootSpawns has 169 markers (exactly 10 T3 crates and 6 T1 crates, about 25 T2 crates and 128 T1 ground). None of them match ArenaLayout v2's LootZones yet. Not built: Patron capsules, Warden event drops and Citadel cases; no code for them exists anywhere in the place.

### 22. “Rare equipment modifications”

- **Our name:** Citadel modifications: mod kits in Citadel cases, fitted to weapons, armour, bows, packs and traps
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 4
- **Pillar phase:** Phase 1 (item state, ItemStats and kits, plus Plate Insert, Tempered Edge and String Dampers), then Phase 2 (the other eight mods)
- **From the notes:** "EFFECT DROPS (ENCHANTMENTS)" (raw notes), filed as "Rare equipment modifications" in the expanded plan
- **Evidence:** Not started. InventoryService slots hold only { id, count }, with no per-item state. ItemDefs has no mod fields. Searching every script for durability, mods or enchantments finds nothing. The HUD shows only an item's rarity and kind (HUDController.flashItemName).

### 23. “Weapons and armour”

- **Our name:** Arena weapons and armour, with armour integrity and two Citadel prototypes
- **Status:** Built · **Size:** L · **Roadmap phase:** 1 → 4 → 10
- **Pillar phase:** Phase 1 (armour integrity, selectable ammo), then Phase 3 (the Legendary Compound Bow and Plate Carrier)
- **From the notes:** "Weapons and armour" (Weapons: bows, knives, spears, axes. Protection: armour, protective clothing)
- **Evidence:** ItemDefs has the Hunting Knife, Machete, Hatchet, Spear (melee and thrown), Mace, Arena Sword, Recurve Bow and arrows, Throwing Knife, Leather Vest (×0.85) and Padded Armor (×0.72). Combat is server-authoritative in CombatService and ProjectileService (combat-viewmodel build report). The meshes are LS_Items_v1, in ReplicatedStorage.Assets.Items. Gaps: InventoryService.getArmorMultiplier applies one flat multiplier to every hit, head hits included. The bow can only fire one ammo id (def.ammo or "arrow" in CombatService). The textured ItemsReal set is not integrated yet (docs/handoff/Part2Plan.md).

### 24. “Survival supplies”

- **Our name:** Survival supplies and packs: Satchel, Rucksack, Citadel Frame Pack and Steel Canteen
- **Status:** Partly built · **Size:** L · **Roadmap phase:** 4
- **Pillar phase:** Phase 2
- **From the notes:** "Survival supplies" (Survival: Backpacks, food, water); also "Increased carrying capacity."
- **Evidence:** Food and water are built: Wild Berries, Apple, Dried Meat, Ration Pack, and the Water Bottle, which turns into an Empty Bottle and is refilled at terrain water (InventoryService onDrink). There are no backpacks and no way to carry more: Config.Inventory.Slots is fixed at 6 and WorldGen.UIBuilder builds a fixed 6-slot hotbar. InventoryController already maps the keys One to Nine.

### 25. “Medical supplies”

- **Our name:** Field medicine: today's Healing Herbs, Bandage and Med Kit, then Field Dressing, Splint, Antitoxin, Electrolyte Draught and the Mending Kit
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 4
- **Pillar phase:** Phase 1 (Bleeding, the Field Dressing and the Mending Kit, alongside Broadhead Arrows), then Phase 2
- **From the notes:** "Medical supplies" (Medical: Bandages, medicines, treatment supplies); also "Improved medical equipment."
- **Evidence:** Built: Healing Herbs (+10 HP, 1.5 s), Bandage (+20, 2.5 s) and Med Kit (+65, 5 s, Epic), timed on the server through UseStart and UseFinish in InventoryService. There are no status effects (no Bleed or Poison anywhere in the code), so medicine has nothing to cure. Both InventoryService and InventoryController refuse healing at full health ("You're not hurt").

### 26. “Rarity tiers”

- **Our name:** Rarity tiers from Common to Legendary, where Legendary means a Citadel prototype (one per round)
- **Status:** Partly built · **Size:** M · **Roadmap phase:** 4
- **Pillar phase:** Phase 1
- **From the notes:** "Rarity tiers"
- **Evidence:** ItemDefs.RarityOrder defines five tiers and Theme.Rarity gives their colours. LootService lights ground items in their rarity colour and adds a glint for Rare and above. The HUD shows a rarity line on each slot and in the item-name toast. Legendary is unused, rarity sets no caps and no spawn rules, and ArenaLayout.dangerAt(), which was written to bias loot quality, is never called.

### 27. “Special rewards”

- **Our name:** Special rewards: Offering prizes, Warden strongboxes, the Arms Register collection, and Laureate and mastery finishes
- **Status:** Not started · **Size:** L · **Roadmap phase:** 4 → 8
- **Pillar phase:** Phase 3 (prizes during the round), then Phase 4 (saved rewards)
- **From the notes:** "Special rewards"
- **Evidence:** DataService (store PlayerStats_v1) saves only Wins, TotalKills, RoundsPlayed and Settings. The RoundSummary remote carries only placements and kills. The place has no reward, collection or currency code, and no MarketplaceService usage.

### 20. “Character-specific equipment”

- **Our name:** Keepsakes (Standard rounds) and signature gear (Story mode)
- **Status:** Not started · **Size:** L · **Roadmap phase:** 7 → 10
- **Pillar phase:** Phase 4 (after playable characters and DataService v2)
- **From the notes:** "Character-specific equipment" (3. Character and skills)
- **Evidence:** DataService has no characters, loadouts or unlocks. Contenders start every round empty-handed: RoundService calls InventoryService.clear at Countdown, and items are only given to alive contenders. LobbyController has no loadout picker.

## Open questions

1. Durability: is armour integrity plus arrow breakage enough (recommended)? Or should weapons also wear out or break, as in survival sims, perhaps only in Endless Arena or Story mode?
2. Loot density: should the start go from about 8.6 to about 7 stacks per contender, and from 7.5 to 4.5 bows, so it feels scarcer and tenser? Or should today's generous loot stay?
3. Ammo: should arrows and darts move out of the hotbar into a quiver, with R to switch arrow type (recommended)? Or should ammo stay in slots?
4. Mods: should players fit mod kits themselves (recommended), or only find mods already fitted on items? And should each item be limited to one mod?
5. Camouflage: is the Chameleon Weave (an adaptive Citadel textile) too science-fiction for the realism you want? Or should only the jute Ghillie Netting ship?
6. Traps: should they stay non-lethal (holds, alarms and at most 25 damage; recommended)? Or should lethal pits and deadfalls be allowed?
7. Legendary 'Citadel prototypes': do you want them at all (at most one per round, announced at the Offering)? Are the Compound Bow and the Plate Carrier the right first two?
8. Patron capsules: should their contents depend on what the contender needs (recommended), or be random within each grade? Should fallen players be able to steer them with free votes (never Robux)? *(Settled: by need, from one table.)*
9. Character-specific equipment in Standard rounds: should players start with a small Keepsake of equal value for everyone? Or should Standard rounds get cosmetic-only versions, with functional signature gear only in Story mode? *(Settled: Standard keeps the empty-handed start; signature gear in Story and Endless.)*
10. Ground loot cue: keep the coloured rarity light and glint (easy to read, a little gamey)? Or switch to a subtler, more realistic glint?
11. Names: approve or rename Citadel case, Citadel modifications, Pitch Arrow, Whistler, Broadhead, Warden strongbox, Keepsake and the Arms Register. *(The collection log is now the Arms Register; anything can be renamed later.)*

## Risks

- Item state touches the core of the round loop: InventoryService, LootService, ProjectileService recoveries, dropAll, the HUD and the viewmodel. A bug there can lose or duplicate items. To guard against it, only add fields to InventoryUpdate, and re-run the build agents' sandboxed round simulations before every playtest.
- The combat physics plan (docs/research/CombatPhysicsPlan.md, Phase 3) also changes armour by damage type and adds wounds. If two teams edit CombatService.applyHit and PlayerService at the same time, the changes will collide. Agree on InventoryService.absorb and the PlayerService status API first.
- Ranged weapons could dominate. Today's tables already give about 11 bows a round. Special arrows on top of that would make archers too strong unless the reduced loot tables ship at the same time.
- Phones: up to 9 slots, an ammo chip, a Back slot and status icons have to fit on a hotbar that already overlaps the thumbstick zone (UI build report).
- Traps and fire near the launch plates and the Spire, or traps nobody can see, will cause griefing and frustration. The exclusion zones, caps and the 6-stud visibility rule are needed from the first build.
- Performance at night: fire patches, flares and Pitch Arrows add lights and particles in rounds with 24 players. Cap how many can exist at once and keep the effects on the client.
- Camouflage is drawn on each player's client, so exploiters can ignore it. Only its effect on Splices, which runs on the server, can be enforced.
- Art volume and visual review: about 38 meshes, 11 mod add-ons, 5 texture sets (20 PNG uploads) and several GLB versions, all waiting on moderation. The original agents could not take screenshots in Studio, so the user should review the renders. The ItemsReal swap, including the package caveat, must land first, or new textured items will sit next to the untextured v1 ones.
- Pay-to-win drift: selling mod kits, cases, capsules, packs or Keepsakes for Robux, or for Gold bought with Robux, would break the rule that cosmetics never change performance. If those purchases had random contents, Roblox's paid-random-item rules would also apply: odds shown before purchase and PolicyService restrictions.
- IP drift: some survival props are iconic of the source franchise, such as poisonous berries used as a weapon, wasp nests, silver sponsor parachutes and a trident as a signature weapon. Review every new item against the IP list.
- Saved rewards and Keepsakes need a DataService v2 schema with a safe migration from PlayerStats_v1.
- Content label: statuses and fire must stay non-graphic, with no blood. Otherwise the answers to the maturity questionnaire change.
