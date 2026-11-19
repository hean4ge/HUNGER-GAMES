# Combat v3: moves, skills, the loadout, trails, tier looks and the load-in

*Design page for the builders, 19 Nov 2026. It answers the owner's brief of 19 Nov (section 0) and builds on the code as it is at place version 509 (`CombatService.lua`, `CombatController.lua`, `CharacterVisuals.lua`, `ViewmodelController\Poses.lua`, `Shared\CombatStats.lua`, `Shared\Stars.lua`, `Shared\Kits.lua`, `KitController.lua`). Where it differs from `Weapons_v2.md`, this page wins only where it says so (listed in 0.3); every weapon number, the star rule, kits, Gold and the wheel in Weapons_v2 stay.*

Rules that hold everywhere on this page:
- **Mild rating.** No blood, no wounds, no red hit sparks, no red screen effects, no cries. A hit shows the pale tick and a pale dust puff. Red is allowed as a *trail colour* a player chose; never as a hit effect.
- **Matte world.** Weapons, hands and bodies stay matte (roughness 0.55 or more, `Reflectance` 0, no `Neon`, no lights on weapons). Only cosmetic trails and the load-in ribbon may glow, and only while they play.
- **Quiet UI** (`docs\design\ui\StyleA_Quiet\README.md`, `Shared\Theme.lua`, `Shared\QuietUI.lua`): thin text and matte line icons on the picture, no boxes, no pop-ups. The owner's own words on UI: complexity should not come from "overwhelming them with menus, currencies, abilities and unnecessary statistics". So: two skills a player, one loadout screen, nothing else.
- **Our own designs and names.** Nothing named after a film, a franchise or the reference sheets (the trail sheet's names are not used).
- **Server-authoritative.** Every hit, block, parry, dodge and skill is timed and checked on the server, as melee is today. The client predicts and shows at once; the server confirms.
- **Every number lives in Config** (section 9.1). Every number here is a starting value for playtests.

---

## 0. The brief

### 0.1 The owner's words (19 Nov), split into jobs

| Their words | This page |
|---|---|
| "higher tier weapons should get more polished and detailed in terms of their look" | Section 5 (tier looks, 1★ to 5★ geometry, still matte) |
| "the using animation shouldnt look so rogue and choppy, make its animation look like a real fighting with the weapon type of thing" | Sections 1 and 7 (move sets per weapon family, clips made in Blender, played as baked data) |
| "fix the way you can choose kits or skills beforehand" | Section 3 (one Loadout screen at the rack in the train) |
| "buying trails - for arrows and throwable items" + the two trail pictures | Section 4 (18 trails, Gold prices, preview, equip) |
| "loading into the game arena like this" (the "Nature Trail VFX" video) | Section 6 (the Gathering: leaves and soft light that gather into the player) |
| "we should be able to have skills for diff weapons that a person chooses in a kit or just general skills" + the combat-move sheet | Section 2 (one weapon skill per family, six general skills, one of each a round) |
| "for this trail stuff and reconfig of weapon design make sure u use blendr and vfx" | Blender: section 5 models, section 7 clips, section 4.4 sprite atlas. VFX: Trails, Beams and ParticleEmitters, sections 4 and 6 |
| "once we finish the fighting mechanisms and make it perfect we can work on the training room and loadup to the arena thingy" | Build order 9.3: fighting first. The training room is not on this page |

### 0.2 Their references, as looked at

| File | What is in it | What we take |
|---|---|---|
| `weapons_ref_crossed_blades_2026-11-19.png` | Two black single-edged swords crossed, silver round guards, black diamond-wrapped grips, clipped angled tips, a light honed edge line. | **Paired Blades** (5.4): our own pair, blued-black matte steel, a round guard, diamond cord wrap. |
| `weapons_ref_throwing_dagger_2026-11-19.png` | A black leaf-shaped throwing dagger, a diamond cross-section, a spiral-wrapped grip, a ring pommel. | **Leaf Dagger** (5.5): our own leaf blade and ring pommel. |
| `trails_ref_styles_2026-11-19.webp` | A sheet of glowing line styles: green crackle, hard blue core, thin haze, orange heat, fiery inferno, wavering purple, thin neon pink, pale pulse, narrow blue. | The *kinds* of line (core, haze, crackle, flame, thin neon, pulse) in the catalogue, 4.2. None of its names. |
| `trails_ref_pin_2026-11-19.jpg` | Projectile trails: white-blue lightning, red triangle shards, orange-yellow fire puffs, yellow stars, a blue comet with a plume, a magenta streak, green swirls. | Seven projectile trails in 4.2 (Forked Light, Shardfall, Kindle, Wishing Stars, Comet, Neon Thread, Glowworm). |
| `skills_ref_pin_2026-11-19.jpg` | A move sheet with staff silhouettes: heavy attack, circular attack (hits several), head kick, projection (vault kick off the staff), counter after a perfect parry, charge (runs through enemies), chained attacks (damage grows), concentration (a buff). Each with a damage and stamina note. | All eight, section 1 (heavy, kick, parry, counter for everyone) and section 2 (circular, charge, chained, projection as weapon skills; concentration as a general skill). Their damage and stamina notes are kept as the shape of the numbers (e.g. charge: low damage, high stamina). |
| "Nature Trail VFX" (video, not saved) | Ribbons of leaves and soft green light swirling and settling. | The Gathering, section 6. |

### 0.3 What this page changes in older pages

| Older rule | Where | Now |
|---|---|---|
| "No glow, no beams, no particles on any weapon or star." | Weapons_v2, top rules | Still true for weapons and stars themselves. **Cosmetic trails** (section 4) may glow, only during a swing or a flight, never on the weapon at rest. |
| "A finish change only, the same silhouette and size at every star." | Weapons_v2 2.4 | The **silhouette** stays (readable at 60 studs); **detail inside it** grows with stars: wraps, collars, engraving bands, inlay, edge finish (section 5). |
| Trails "restrained" ("a subtle wind-like trail ... a faint dust effect") | Owner's design direction, 15 Nov | Both: the free and Common trails are the restrained ones; the bright ones the owner showed on 19 Nov are bought. Each player can turn others' bright trails down in Settings (4.6). |
| The `KIT ‹ ›` and `BRING ‹ ›` line, K / B keys | Weapons_v2 3.2, `KitController` | Replaced by the Loadout screen (section 3). |
| Mace retired, 11 weapons | Weapons_v2 1.2 | 13 weapons: + Paired Blades, + Leaf Dagger (5.4, 5.5). |
| "Quick and heavy attacks" was the owner's open question (12 Nov) | OwnerSpecs 18 Nov | Their 19 Nov sheet has "Heavy attack" in it: taken as yes. |

---

## 1. Fighting: the move set

### 1.1 What is there today, and why it looks "rogue and choppy"

Read from the code:
- **One kind of attack.** Attack swings; holding it swings again. The swing set changes (`Poses.SWING`, `SwingChainWindow` 0.45 s), but every swing is the same strength and the same timing. No heavy, no guard, no parry, no dodge, no kick, no knockback, no stagger, no hit-stop (`OwnerSpecs` §"Not in the game at all").
- **Third person is three keyframes.** `CharacterVisuals` plays other players' swings as three poses, W (wound up), M (the cut) and F (follow-through), on the waist, neck, shoulders and elbows, blended with simple easing. Three keys cannot show anticipation, the weight shift, the wrist turning over, the follow-through settling or the return to guard. That is what reads as choppy from outside.
- **First person is waypoints.** `Poses.swing` moves the hands through a few waypoints (W, M, F, optional U, A, B, R). Better than third person, but the arms do not lead with the body, and a chain snaps from the end of one set to the start of the next.
- **Nothing happens to the one who is hit** except the number going down and a camera kick. With no reaction, no hit-stop and no shove, a hit has no weight.
- **The strike is one trace** from the head along the look (`meleeTrace`), so a horizontal slash and a stab hit the same shape of space.

What fixes it, in order of how much it shows:
1. Real clips made in Blender for every move, 8 to 30 keys each, with anticipation, the cut, the follow-through and the settle (section 7).
2. A move set with a reason to use each move: chains that flow, a heavy you hold, guard, parry and counter, a kick, a dodge (this section).
3. Weight on contact: hit-stop, upper-body reactions on the one hit, knockback by impulse, stagger (1.8).
4. The trace follows the swing: three rays across the arc for slashes, a long thin one for stabs (1.9).

### 1.2 Controls

One scheme for every melee weapon; the same buttons on every device. Nothing new to learn for attacking: tap Attack as today.

| Move | PC | Gamepad | Touch |
|---|---|---|---|
| Light attack (chain) | tap Mouse 1 | tap R2 | tap ATTACK |
| Heavy attack | hold Mouse 1 (0.25 s or more), release | hold R2 | hold ATTACK |
| Guard (block) | hold Mouse 2 | hold L2 | hold GUARD (the AIM button's place; it reads GUARD for melee weapons) |
| Parry | press Guard just before a hit lands (the first 0.18 s of a guard) | same | same |
| Counter | Attack within 0.45 s after a parry | same | same |
| Kick (breaks a guard) | Guard + tap Attack | L2 + tap R2 | GUARD + tap ATTACK |
| Throw (throwable melee: hatchet, spear, Twin-Bit Axe, Ring Blade, Leaf Dagger) | Guard + hold Attack, release | L2 + hold R2 | GUARD + hold ATTACK |
| Dodge | Q, or Jump while guarding | A (jump) while holding L2 | JUMP while holding GUARD |
| Weapon skill | R | D-pad left | round skill button (left) |
| General skill | F (at a fire, the fire's F prompt wins while it shows) | D-pad right | round skill button (right) |
| Bow | unchanged: hold Attack to draw, Aim to zoom | unchanged | unchanged |

Why these keys: E, F (only at a fire), X, G, V, C, Ctrl, Shift, M, 1 to 9 are taken (`CookingController`, `InventoryController`, `MovementController`, `CameraController`, `SettingsController`). Q is only used while spectating. On a gamepad R1 / L1 are the hotbar, B is crouch, X interact, D-pad up is Settings and D-pad down is drop; D-pad left and right are free in the arena. Throwing keeps today's feel (the throwable weapons already throw with Aim + Attack); the only change is that the throw needs Attack *held* a moment, so a tap while guarding is a kick.

Touch: GUARD sits where AIM is today (shown for every melee weapon, not only the spear); the two skill buttons are 64 px circles in an arc above ATTACK, each a matte line glyph with a thin cooldown ring and the seconds left in Roboto Mono. Every touch target is at least 44 px.

### 1.3 The moves every melee weapon has

Times in seconds; frames at 30 fps (the Blender clips' rate) in brackets. "Windup" ends at the strike, when damage lands (as today: the server's strike time). "Active" is how long the cut is drawn and the trail shows; the server traces once at the strike (1.9). "Recovery" is after the active part, until the next move can start.

| Move | Windup | Active | Recovery | Stamina | Reach | Damage | Notes |
|---|---|---|---|---|---|---|---|
| Light attack | weapon's `windup` | 0.06 (2) | to the weapon's `cooldown` | weapon's `staminaCost` | weapon's `range` | per chain step, 1.4 | Chains: next press inside recovery, or within `SwingChainWindow` 0.45 s after it ends |
| Heavy attack | hold 0.25 to 0.75 s, then a release windup of 0.12 (light weapons), 0.16 (medium), 0.22 (heavy) | 0.08 (2.4) | 0.45 / 0.55 / 0.70 | 2.2 × the light cost | range + 0.5 (spear and Longsword: + 1.5, a lunge) | × 1.3 at 0.25 s held, rising to × 1.6 at 0.75 s held | Walk at × 0.7 while charging. Full charge is held up to 1.5 s more (0.05 stamina a second), then it lets go by itself. Others see the charge pose: it is readable |
| Guard | 0.10 (3) to raise | held | 0.12 to lower | 0.004 × the raw damage of each blocked hit (× 1.5 for a heavy) | front 120° | blocks a share of melee damage, 1.5 | Walk at × 0.6, no sprint. Arrows and throws are not blocked |
| Parry | the first 0.18 s of a guard (Concentration 0.26) | — | — | 0 | front 120° | the hit does nothing | The attacker's weapon rebounds: stagger 0.5 s (0.8 s if it was a heavy). Missed parry: no new parry window for 0.6 s (holding the guard still blocks) |
| Counter | 0.06 (2) | 0.06 | 0.35 | 0.03 | weapon's range | × 1.5 of the light | Only within 0.45 s after a parry. Heavy stagger, hit-stop 0.10 |
| Kick | 0.16 (5) | 0.08 | 0.35 | 0.07 | 4.5 | 6 (no stars) | On a guarding target: breaks the guard, stagger 0.45 s. On anyone else: stagger 0.4 s. Cooldown 1.2 s. Any hit during its windup cancels it |
| Dodge | 0.15 (5) start-up (the owner's TRIBUTE number) | 0.25 travel (8 studs in the move direction; no direction: a 6-stud backstep) | 0.15 | 0.16 (a third dodge inside 2 s costs double) | — | — | Melee hits miss during the 0.25 s travel. Arrows and throws do not (but you have moved). Cooldown 0.7 s. Not when stamina is under 0.16. Forward is a roll, sideways a hop, back a step |

Weight classes (for the heavy's release and recovery, and the swing sound): **Light** Fists, Hunting Knife, Leaf Dagger, Ring Blade, Paired Blades; **Medium** Longsword, Machete, Hatchet, Climbing Pick, Spear; **Heavy** Twin-Bit Axe.

**What beats what:** an attack beats a kick (any hit cancels the kick's windup); a kick beats a guard; a guard (and a parry) beats an attack; a dodge beats everything melee but costs the most stamina. Behind you (outside the 120° front) a guard does nothing, so flanking still works in a crowd.

The Hunting Knife's unseen hit (40) never applies to a guarding target.

### 1.4 Light chains, per weapon (1★)

"×" is the step's damage against the weapon's `damage`. Steps without a time keep the weapon's own windup and cooldown. The last step of a chain is a little slower and harder, so a chain has a rhythm instead of a metronome.

| Family | Weapon | Steps (what the swing is) | Damage 1★ | Windup / total per step |
|---|---|---|---|---|
| Fists | Fists | 1 jab (left) · 2 cross (right) · 3 hook (left) ×1.25 | 8 · 8 · 10 | 0.06 / 0.45 · same · 0.08 / 0.52 |
| Short blade | Hunting Knife | 1 backhand slash R→L · 2 forehand slash L→R · 3 stab ×1.2 | 20 · 20 · 24 | 0.10 / 0.48 · same · 0.12 / 0.52 |
| Short blade | **Leaf Dagger** (new) | 1 straight stab · 2 reverse slash · 3 hooking stab ×1.2 | 18 · 18 · 21.6 | 0.08 / 0.42 · same · 0.10 / 0.46 |
| Short blade | Ring Blade | 1 hoop slash R→L · 2 hoop backhand · 3 hoop punch ×1.15 | 24 · 24 · 27.6 | 0.12 / 0.55 · same · 0.14 / 0.60 |
| Sword | Longsword | 1 diagonal down R→L · 2 rising cut L→R · 3 flat horizontal · 4 overhead ×1.25 | 36 · 36 · 36 · 45 | 0.16 / 0.62 · same · same · 0.20 / 0.72 |
| Sword | Machete | 1 forehand flat sweep · 2 backhand sweep · 3 overhead chop ×1.2 | 26 · 26 · 31.2 | 0.14 / 0.55 · same · 0.17 / 0.62. Its second-contender sweep (60%) on steps 1 and 2 only |
| Sword | **Paired Blades** (new) | 1 right cut · 2 left cut · 3 right rising · 4 both blades crossing ×1.4 | 19 · 19 · 19 · 26.6 | 0.07 / 0.38 · same · same · 0.12 / 0.50 |
| Axe | Hatchet | 1 diagonal chop · 2 backhand chop · 3 overhead ×1.2 | 34 · 34 · 40.8 | 0.18 / 0.80 · same · 0.22 / 0.90 |
| Axe | Twin-Bit Axe | 1 wide sweep R→L · 2 return sweep L→R ×1.1 (it carries the momentum) | 42 · 46.2 | 0.30 / 0.95 · 0.26 / 0.95 |
| Axe | Climbing Pick | 1 peck · 2 peck · 3 hook-and-pull ×1.15 (on a guarding target it drags the guard down: guard broken, stagger 0.3 s) | 26 · 26 · 29.9 | 0.14 / 0.65 · same · 0.16 / 0.70 |
| Spear | Spear | 1 thrust · 2 thrust · 3 butt swing ×0.8, reach 6, full damage inside 4 studs (the answer to someone who got inside the shaft) | 34 · 34 · 27.2 | 0.20 / 0.70 · same · 0.16 / 0.70 |
| Throwables | Throwing Knives (in hand) | 1 short slash, then Attack again throws (as today: in hand they are throwing items first) | 10 | 0.08 / 0.45 |
| Bow | Recurve, Short Bow | no melee chain. Guard is not available with a bow; Dodge is (it lets the string down) | — | — |

"To down" stays close to Weapons_v2's numbers, so the weapon roles are kept: Longsword 1.40 s (36 + 36 + 36), Paired Blades 1.71 s (five hits: 19, 19, 19, 26.6, 19), Twin-Bit Axe 2.20 s (42 + 46.2 + 42).

### 1.5 Heavy, guard and throw, per weapon (1★ / 5★)

| Weapon | Heavy (what it is) | Heavy at full charge 1★ / 5★ | Guard blocks | Throw (unchanged from Weapons_v2) |
|---|---|---|---|---|
| Fists | haymaker | 12.8 / 12.8 | 40% | — |
| Hunting Knife | lunging stab | 32 / 37.1 | 55% | — |
| Leaf Dagger | lunging stab | 28.8 / 33.4 | 50% | 40, head ×1.6 (64), 150 studs/s, gravity 20, on the crosshair to 30 studs |
| Ring Blade | two-handed hoop drive | 38.4 / 44.5 | 65% (the hoop is a guard) | 38, 140 studs/s, flat |
| Longsword | committed diagonal, lunge +1.5 | 57.6 / 66.8 | 75% | — |
| Machete | double-handed overhead | 41.6 / 48.3 | 65% | — |
| Paired Blades | both blades scissor across | 45.6 / 52.9 (19 × 2.4) | 60% | — |
| Hatchet | overhead with the whole body | 54.4 / 63.1 | 65% | 45, head ×1.6 (72) |
| Twin-Bit Axe | overhead, two hands, a step in | 67.2 / 78.0 | 70% | 65, head capped 95, spinning |
| Climbing Pick | overhead spike | 41.6 / 48.3 | 55% | — |
| Spear | lunge, +1.5 reach | 54.4 / 63.1 | 70% (the shaft) | 60, head capped 95 |

No single hit passes 95 (`CombatStats.hitCap`), whatever the stars or the move.

### 1.6 Stars (the Weapons_v2 rule, kept)

Each star above the first: damage +4%, cooldown −2%, reach +0.15 studs (bows: damage +4%, draw −3%, speed +2%, on-target range +5). These apply to every attack the weapon makes:

| Applies | Does not apply |
|---|---|
| Light steps, heavy, counter and the throw: damage × the star multiplier | Windup (the strike time stays the same at every star, so a 5★ is not harder to read) |
| Each step's total (cooldown): the recovery shortens | Guard share, parry window, dodge, kick (the body, not the weapon) |
| Reach | Skill cooldowns and stamina costs |
| Weapon skills that do "× the weapon's damage" | General skills |

### 1.7 Stamina

Today's bar (0 to 1, `Config.Movement.Stamina`: regen 0.2 a second after 1.0 s, exhausted under 0.25 after hitting 0). Fighting now uses it properly:

| Spend | Cost |
|---|---|
| Light attack | the weapon's `staminaCost` (0.03 to 0.12) |
| Heavy | × 2.2 of that, plus 0.05 a second held at full |
| Block | 0.004 per point of raw damage blocked (a Longsword light: 0.14; a full Twin-Bit Axe heavy: 0.40) |
| Kick / dodge | 0.07 / 0.16 |
| Parry, counter | 0 / 0.03 |
| Skills | section 2 |

At 0 stamina: a guard breaks (heavy stagger 0.8 s), no dodge, attacks still work at half speed (the chain slows, the recovery doubles). Regen waits 1.0 s after any combat spend, as after sprinting.

### 1.8 Weight: hit-stop, reactions, stagger, knockback

From the owner's TRIBUTE spec (15 Nov), with numbers made to fit 48 players and lag.

**Reaction tiers.** Every hit has one tier, from the move:

| Tier | Caused by | The one hit | Knockback (torso) | Hit-stop | Camera |
|---|---|---|---|---|---|
| **Flinch** | Fists, Hunting Knife, Leaf Dagger, Ring Blade, Paired Blades light steps; Throwing Knives; chained skill hits | Upper body only, additive, 0.08 s in, 0.25 s out (the owner's numbers). Legs keep walking ("legs keep walking through a knife hit"). No control lost. | 12 to 20 studs/s | 0.04 s | victim 2° jolt along the hit |
| **Stagger** | Longsword, Machete, Hatchet, Spear, Climbing Pick light steps; arrows (the owner's 0.4 s); kicks; thrown weapons of 38 or more; a parried light | 0.4 s: no attack, no guard, walk × 0.5, no sprint. The torso turns into the hit and one foot steps back (the right foot by quadrant, not a generic flinch). | 22 to 34 | 0.05 s (the owner's 3 frames) | victim 6° jolt along the impact (the owner's number) |
| **Heavy stagger** | Twin-Bit Axe light steps, every heavy at full charge, counters, a broken guard, a parried heavy | 0.7 s (the owner's "heavy weapons add 0.7 s"), a full step back and a torso twist | 30 to 36 | 0.08 s | attacker shake 0.25 for 0.2 s, victim 0.4 for 0.3 s (the owner's numbers) |
| **Knockdown** | Vault Kick (spear skill) only | Down 1.0 s, up in 0.6 s; a dodge after 0.5 s rolls out | 36 + 8 up | 0.08 s | as heavy |

**Poise (no stun-lock in a crowd of 48).** After a stagger or heavy stagger ends, 0.8 s in which new hits only flinch; after a knockdown, 1.5 s. Damage still lands; only the loss of control is limited. So three players on one cannot freeze them to death.

**Knockback by impulse, never by CFrame** (the owner's rule). The speed above × the region (the owner's mass modifiers: Head 1.4, Torso 1.0, Limbs 0.7) × 1.5 for a heavy, then **capped at 36 studs/s**. The owner's spec gives both "a knife shove costs about 1.5 studs of ground" and "decay 12 studs/s²"; those two disagree (12 studs/s² would slide an 18 studs/s knife victim 13.5 studs), so this page keeps their speeds and their 1.5 studs and sets the decay to **108 studs/s²**: a knife shoves 1.5 studs, a Machete 5.4, the hardest hit 6 (the cap). The victim's own client applies it (it owns its body: `AssemblyLinearVelocity` on the root, then the decay), from a `Reaction` message the server sends with the hit; the server checks the distance moved against it (`MovementService`'s checks), as the owner's spec says: "client predicts, server reconciles". Knockback can push someone off a ledge or into water: that is fine and fun.

**Hit-stop is local.** The attacker's view and the victim's view freeze their animation (and the viewmodel) for the hit-stop time; players within 30 studs see the two bodies pause too. The server never pauses: timing on the server is unaffected.

**Sound and spark.** The existing `Hit_Flesh` sound, a lower "thock" on a heavy, a steel "clang" on a block, a bright ring and a pale straw spark on a parry (the recipe in `AnimationPipeline` "Effects recipe": pale straw to grey, never red), a dull thud on a kick.

### 1.9 The hit, on the server

Builds on `onMeleeSwing` (the body check, `meleeFront`, the lag allowance and the 95 cap all stay):

- `MeleeSwing` carries the move: `"L1".."L4"` (chain step), `"H"` (heavy, with its charge), `"K"` (kick), `"C"` (counter). The server checks the step against the chain it holds for that player (a step can only follow the one before it within the chain window), the charge against its own timing (as it times bow draws), and the stamina.
- **The trace follows the swing.** Slashes cast three rays across the arc at the strike (the swing's yaw −15°, 0, +15° from the look; overheads in pitch instead), the owner's "3 rays a swing"; stabs and thrusts one ray with a thinner ball (× 0.7 radius) and the full reach. The first body any ray touches is the target, and the same body never takes two hits from one swing (the owner's "a hit never double-registers").
- **Guard and parry are timed on the server.** `Guard("Start" | "Stop", clientTime)`: the server keeps the guard's start (the client's time, if within `CooldownJitter` 0.12 s of arrival, as swings are timed today). A strike that lands while the target guards, from their front 120°, is blocked; if it lands within the first 0.18 s of that guard, it is parried.
- **Dodge**: `Dodge(direction, clientTime)`; the server holds the 0.25 s travel window from the start-up's end and refuses melee hits on that body inside it. The server checks the 8 studs it moved.
- **Reactions** go out as one `Reaction { tier, from, impulse, hitStop }` to the victim (who applies the knockback) and in the existing `CombatAction` to everyone within `ACTION_RANGE` 220 studs (who play the reaction clip).
- **Others see it start.** `CombatAction "Swing"` already carries `variant` and `lead`; it gains `move` and, for a heavy, a "Charge" message at the hold's start so others see it wind up.

New per-player state in `CombatService`: `chainStep`, `chainEndsAt`, `heavyStart`, `guardStart`, `parryLockUntil`, `dodgeUntil`, `staggerUntil`, `poiseUntil`, `skillReady { weapon, general }`.

---

## 2. Skills

### 2.1 The slot rule

- **Two skills a player.** One **weapon skill** and one **general skill**, chosen before the round in the Loadout (section 3) and locked at the call to the launch.
- **The weapon skill comes from a Specialty.** The player picks one weapon family as their Specialty (Fists, Short blade, Sword, Axe, Spear, Throwing, Bow). That family's skill is on R whenever they hold a weapon of that family; with any other weapon, R is dim and does nothing. So a choice before the round matters in the round (the Archer kit with the Bow specialty is a real build; an Axe specialist hunts for an axe at the Horn), and it is still just one choice.
- **Kits suggest one.** Choosing a kit moves the Specialty to its family if the player has never set one (Archer: Bow; Forager: Short blade; Hunter: Throwing; Climber: Axe; Medic: none suggested). The player can change it.
- **Skills are locked for the first 45 s of a round** (the Horn's opening is about grabbing, not abilities) and in the train. Practice rounds: from the start.
- **Stars never change a skill**, except that weapon skills which do "× the weapon's damage" use the weapon's starred damage.
- Each skill is one press. Skill buttons show only the cooldown ring and seconds; no text, no pop-up.

### 2.2 Weapon skills (one per family)

| Family | Skill | From the owner's sheet | Effect | Numbers (1★) | Stamina | Cooldown | Look (matte; a pale trail and dust only) |
|---|---|---|---|---|---|---|---|
| Fists | **Head Kick** | head kick | A high round kick. Interrupts any swing, draw or skill being wound up. | windup 0.22, reach 4.5, 14 damage, heavy stagger | 0.12 | 10 s | Leg arc with a short pale swish; dust from the planted foot |
| Short blade | **Chained Strikes** | chained attacks: "low damage but grows while chaining, if not interrupted" | Five quick strikes over 1.1 s, stepping 0.5 studs forward with each. Ends on a miss, a parry or a hit taken. | × 0.45, 0.5, 0.55, 0.65, 0.85 of the weapon's damage (knife: 9, 10, 11, 13, 17 = 60); the first four flinch, the last staggers | 0.18 | 16 s | Each strike's trail a little longer; the last one with a soft dust puff |
| Sword | **Running Cut** | charge: "runs on a straight line, hitting every enemy on his way; low damage, high stamina" | 0.2 s crouch, then a 12-stud dash in 0.3 s in the look direction, cutting each contender in a 3-stud-wide lane once (Paired Blades cut twice). Stops at a wall or a steep slope. Parryable from the front. | × 0.6 of the weapon's damage (Longsword 21.6, Machete 15.6, Paired Blades 2 × 11.4); sideways knockback 24; at most 4 contenders | 0.28 | 18 s | Dust along the lane; the blade's trail stretched along the run |
| Axe | **Whirl** | circular attack: "can hit several enemies; low damage, medium stamina" | Pulls the axe across the body (0.35 s, readable), then one full turn in 0.3 s hitting everyone inside the weapon's reach + 1 stud. | × 0.65 of the weapon's damage (Twin-Bit Axe 27.3 and its armour rule, Hatchet 22.1, Climbing Pick 16.9); outward knockback 30; at most 4 contenders | 0.24 | 15 s | A ring of dust at the feet; the axe's trail drawn as a full circle |
| Spear | **Vault Kick** | projection: "powerful kick poised on the staff, able to throw enemies to the ground; medium stamina, low damage" | Plants the spear (0.3 s), vaults 5 studs forward on it and kicks with both feet 0.45 s later (0.75 s after the press). Reach 3 from where you land (about 8 from where you started). | 12 damage (no stars), **knockdown** 1.0 s, knockback 36 + 8 up | 0.24 | 18 s | Dust where the spear plants and where they land |
| Throwing | **Ricochet** | (ours, the brief's "ricochet throw") | Arms your next throw for 4 s (any throw: Throwing Knife, Leaf Dagger, Ring Blade, Hatchet, Spear, Twin-Bit Axe). On its first contact, a contender or a hard surface, it glances once toward the nearest other contender within 20 studs in a 120° cone ahead of it. | the bounce does 70% of the throw's damage | 0 | 14 s | A pale straw spark and a "tink" on the bounce |
| Bow | **Piercing Shot** | (ours, the brief's "piercing shot") | Arms your next full-draw arrow for 6 s (a lighter release keeps it armed). It flies 15% faster and passes through the first contender and thin foliage, and can hit a second. | 100% then 70%; the 90 head cap stays | 0 | 20 s | The equipped arrow trail, drawn straighter and a little longer |

### 2.3 General skills (pick one)

| Skill | From the owner's sheet | Effect | Lasts | Cooldown | What you see / what others see |
|---|---|---|---|---|---|
| **Concentration** | concentration: "critical hits and interruption rate increased; medium stamina, low cooldown" | Parry window 0.18 → 0.26 s; heavies charge 30% faster; attacks cost 30% less stamina. (No critical hits: Mild, and no randomness in damage.) | 6 s | 40 s | You: the screen's edge softens, the breath slows. Others: a slow exhale |
| **Second Wind** | — | Stamina +0.5 at once, Exhausted cleared, and 8 health over 4 s. A 0.4 s hand-to-chest; a hit cancels the health part | instant | 60 s | A deep breath; nothing glows |
| **Sprint Burst** | — | Sprint × 1.25 (26 → 32.5 studs/s) with no stamina drain. Ends when you attack | 3 s | 35 s | A small dust kick at each footfall |
| **Quiet Step** | — | Your footsteps and the rustle of plants carry only 6 studs; crouch-walk 40% faster. Ends when you attack | 8 s | 45 s | You: the world's sound dips a little. Others: nothing |
| **Steady Hands** | — | No bow sway and no hold drain; draw time −15%; throws stay on the crosshair 10 studs further | 8 s | 45 s | The draw ticks on the crosshair stay still |
| **Brace** | — | Knockback on you × 0.5; a stagger becomes a flinch, a heavy stagger a stagger; no knockdown | 4 s | 40 s | You plant your feet: a slightly lower stance others can read |

### 2.4 Balance: 48 players and phones

- Two skills, long cooldowns (10 to 60 s), so a fight is mostly the move set, not the skills. No skill alone takes a healthy contender (the biggest, Chained Strikes on a 5★ knife, is 70).
- Area skills (Whirl, Running Cut) hit at most 4 contenders. A Horn pile-up cannot be cleared with one button.
- Every skill can be answered: Head Kick and Whirl have readable wind-ups (0.22 and 0.35 s); Running Cut and Chained Strikes can be parried; Ricochet and Piercing Shot need a throw or a full draw first; a dodge escapes all of them.
- Server cost: one `Skill(slot, clientTime, direction)` remote (rate limit 2 a second), one spatial query a use (`GetPartBoundsInRadius` or a box along the lane), never per frame.
- Phones: skills fire along the camera, no targeting; buttons are large (1.2) and show their readiness by the ring only.
- To watch: if Specialty Bow plus Steady Hands is everywhere, Steady Hands' draw bonus goes first.

---

## 3. The Loadout: one place to choose kit, weapon, skills and trails

### 3.1 What is wrong with today's line

`KitController` puts `KIT ‹ Archer ›`, a contents line and `BRING ‹ Twin-Bit Axe ★★★★ ›` at the bottom centre of the screen in the train (top centre on touch).

| Problem | Effect |
|---|---|
| One option shown at a time, cycled blind with ‹ › | You cannot see what the choices are without clicking through all five |
| K / Shift+K and B are not shown anywhere | Hidden keys; B will collide with the next thing to want B |
| Gamepad: L1 / R1 cycle the kit only; BRING has no gamepad input | Console players cannot choose what to bring |
| It is always on screen in the train | It sits over the picture the whole time, for players who chose long ago |
| No skills, no trails, no preview | The brief's "choose kits or skills beforehand" and "buying trails" have nowhere to go |
| One `KitPick` remote per click | Five clicks, five server writes |
| Touch: the 30 px arrows at the top centre sit among the status lines | Small targets in a busy place |
| Nothing says when the choice locks | Players change it after the call and wonder why it did not take |

### 3.2 The new Loadout

**Where.** The kit rack in the red train (Weapons_v2 3.2: the orange-framed rack with blue padded trays) becomes the **Loadout rack**. Walk up, the prompt reads `E  Loadout` (gamepad X, touch tap). It can also be opened from anywhere in the train: the thin summary line at the bottom (click or tap it), `L` on a keyboard, D-pad right on a gamepad. It cannot be opened in the arena.

**The summary line** (replaces today's KIT / BRING lines; one line, Ink at 72%, bottom centre on PC, under the status lines on touch):
`Forager · Twin-Bit Axe ★★★★ · Axe: Whirl · Second Wind     L  Loadout`

**The screen.** Opening it eases the camera over 0.4 s to a three-quarter view of your own avatar standing at the rack (left half of the screen). The train stays visible; nothing covers it. On the right, four rows of thin text and matte line icons, all choices of a row visible at once:

```
KIT          Archer   Forager   Hunter   Medic   Climber
             Hunting Knife · Apple ×3 · Water Bottle                (dim: what the parcel holds)

BRING        kit weapon   Twin-Bit Axe ★★★★   Machete ★★★   Longsword ★★★

SKILLS       SPECIALTY   Fists  Short blade  Sword  [Axe]  Spear  Throwing  Bow
                         Whirl · one full turn, hits all near you · 15 s
             GENERAL     Concentration  [Second Wind]  Sprint Burst  Quiet Step  Steady Hands  Brace
                         Stamina back at once, a little health · 60 s

TRAILS       SWING  Draught      ARROW  Comet      THROW  Leafwake      ›

                                                    1,240 Gold        DONE
```

- The chosen item in each row has a 26 × 2 px underline (the hotbar's selected mark) and full Ink; the rest rest at 72%. Hovering (or the gamepad cursor) shows one dim line under the row: what it does, in plain words, with its cooldown.
- **Preview on your avatar.** Choosing anything plays it on your own avatar at the rack, client-only: a kit lays its items on the blue tray in front of you; BRING puts the weapon in your hand at its stars (you see the tier look, section 5); a Specialty plays its skill once; a general skill plays its pose; a trail plays a swing, a shot or a throw with that trail.
- **TRAILS ›** opens the trail strip in the same place (section 4.5): the three slots, then the 18 trails as icons with names, price or "owned".
- **Locked** shows as a thin `LOCKED · launching` line in Sun when the round is called; the rows go to 50% and cannot change.
- Gold balance in Roboto Mono, bottom right; DONE (or Esc / B / tapping outside) closes it.

**Input.**

| | Mouse and keyboard | Gamepad | Touch |
|---|---|---|---|
| Move between choices | hover | D-pad up / down between rows, left / right along a row | tap |
| Choose | click | A | tap |
| Open trails | click `TRAILS ›` | A on the TRAILS row | tap |
| Close | DONE, Esc, L | B | DONE, or tap the avatar side |
| Buy a trail | hold the price for 0.6 s (a thin line fills under it) | hold A 0.6 s | hold 0.6 s |

Touch on phones: rows become two-line strips that scroll sideways with a swipe; icons 56 px, names 16 px, every target 44 px or more; the avatar takes the top third.

**One save.** Choices change locally while the screen is open; closing it sends one `LoadoutSet { kit, bring, specialty, general, trails = { swing, arrow, throw } }` (and at most one every 0.5 s if the player keeps it open and the call comes). The server checks each value (the kit exists; the brought weapon is owned and may be brought; the trails are owned; the general skill exists) and saves it to the profile (`DataService`), as `KitPick` does today. It replaces `KitPick` (keep it accepted for one version so an old client still works).

**Delivery is unchanged:** the kit and the brought weapon still arrive in the midpoint parcel (Weapons_v2 3.3).

---

## 4. Trails

### 4.1 What a trail is

- A **cosmetic** line that follows a swing, an arrow or a thrown item. It never changes damage, speed, range, hit boxes or sound levels. Everyone sees everyone's trails (subject to their own settings, 4.6).
- Three slots: **Swing** (melee swings and skills), **Arrow** (both bows), **Throw** (Throwing Knives, Leaf Dagger, Ring Blade, Hatchet, Spear, Twin-Bit Axe thrown). Each trail says which slots it fits; one trail can be equipped in several slots.
- Made only from `Trail`, `Beam` and `ParticleEmitter` with built-in textures (4.4). Nothing on the weapon at rest.
- **Fair to the shooter:** an arrow or throw trail starts 6 studs after it leaves the hand and lasts 0.25 to 0.45 s, so it never paints a line back to the archer. A trail ends without a burst on a hit: it lets go and fades where it is, so nothing coloured ever lands on a body (Mild).
- Swing trails show only from the end of the windup to the end of the active part plus 0.1 s.

### 4.2 The catalogue: 18 trails

Names are ours. "Natural" are the restrained ones (the owner's 15 Nov direction); "Bright" are the glowing ones from their 19 Nov references.

| # | Trail | Kind | Slots | Rarity · Gold | What it is (colours RGB) | Built from |
|---|---|---|---|---|---|---|
| 1 | **Draught** | Natural | all | Free (default) | A pale wind streak. 236,232,222 → 190,188,182 | Trail, Lifetime 0.14, Transparency 0.55 → 1, LightEmission 0.15 (the `AnimationPipeline` recipe) |
| 2 | **Dust** | Natural | all | Free | A faint grey-brown dust wake | ParticleEmitter (smoke), Rate 25, Size 0.4 → 1.1, Transparency 0.7 → 1, LightEmission 0 |
| 3 | **Thistledown** | Natural | arrow, throw | Common · 300 | Seed fluff drifting off the line | Trail (white, very thin) + ParticleEmitter (sparkle, white, Speed 0.5, Drag 3, slow fall) |
| 4 | **Neon Thread** | Bright | all | Common · 300 | A thin, sharp magenta line (the reference's magenta streak). 255,64,196 | Trail, Width 0.08, LightEmission 1, Lifetime 0.3 |
| 5 | **Hardline** | Bright | all | Common · 300 | A bright blue core with a soft edge (the sheet's hard core). 70,150,255 | Two Trails: a narrow white core and a wider blue one at Transparency 0.6 |
| 6 | **Haze Line** | Bright | all | Common · 300 | A thin cyan line in a faint haze. 60,220,235 | Trail + one wide Trail at Transparency 0.85 |
| 7 | **Leafwake** | Natural | all | Rare · 800 | Green leaves and soft green light (the load-in's sibling). 108,140,72 → 214,190,112 | Trail (green, LightEmission 0.4) + ParticleEmitter (leaf sprite; until the atlas, sparkle tinted green) |
| 8 | **Ember Drift** | Natural | all | Rare · 800 | Orange embers that fall off the line and cool to grey | ParticleEmitter (sparkle, 255,150,60 → 120,110,100, Acceleration 0,−8,0) + a dim orange Trail |
| 9 | **Kindle** | Bright | all | Rare · 800 | Soft fire puffs, orange to yellow (the reference's fire trail) | ParticleEmitter (fire texture, Rate 40, Size 0.6 → 0, LightEmission 0.8) |
| 10 | **Frostbreath** | Natural | swing, arrow | Rare · 800 | White mist with a cold glint | ParticleEmitter (smoke, 230,240,250, Transparency 0.6 → 1) + a few white sparkles |
| 11 | **Pulse** | Bright | all | Rare · 800 | A pale white-cyan line that brightens in beats along its length | Trail with a Transparency sequence of 4 bands, its Texture offset scrolled (TextureMode Wrap) |
| 12 | **Glowworm** | Bright | arrow, throw | Rare · 800 | Green swirls that brighten to yellow at the head (the reference's green swirl) | ParticleEmitter (sparkle, Rotation and RotSpeed, Speed 1, green → yellow) + a short Trail |
| 13 | **Forked Light** | Bright | arrow, throw | Epic · 1,800 | White-blue lightning crackling along the flight (the reference's lightning) | Two Beams between the projectile and a point 3 studs behind, Segments 10, their CurveSize0 / CurveSize1 re-rolled every 0.05 s for the jag; + white sparkles |
| 14 | **Shardfall** | Bright | arrow, throw | Epic · 1,800 | Small triangle shards tumbling off the line, crimson with white flecks (the reference's shards) | ParticleEmitter (shard sprite from the atlas, Rotation random, RotSpeed ±200) + a thin crimson Trail. Until the atlas: sparkle in crimson |
| 15 | **Wishing Stars** | Bright | all | Epic · 1,800 | Gold stars that shrink and fade (the reference's stars) | ParticleEmitter (star sprite from the atlas; until then sparkle in gold) + a faint gold Trail |
| 16 | **Nebula** | Bright | all | Epic · 1,800 | A wavering violet band (the sheet's wavering purple) | Trail with a scrolled noise texture (TextureMode Wrap, TextureSpeed) in violet 150,80,255 + a dim haze Trail |
| 17 | **Comet** | Bright | arrow | Legendary · 4,000 | A blue comet: a bright head and a long cyan plume (the reference's comet) | ParticleEmitter at the head (sparkle, LockedToPart, Size 1.2, Rate 60) + a wide cyan Trail fading over 0.45 s |
| 18 | **Molten** | Bright | swing, throw | Legendary · 4,000 | A heavy orange-white flame with drifting sparks (the sheet's inferno) | Trail (white → orange → dark, Lifetime 0.2) + ParticleEmitter (fire, upward) + sparks |

"None" is always available (no trail at all).

### 4.3 Buying

- **Gold only** (Weapons_v2 section 4). Robux prices are designed but off (`Config.Economy.RobuxTrails = false`), and when switched on they buy the same trails at the same rarity: no trail is Robux-only.
- Prices by rarity: Free · Common 300 · Rare 800 · Epic 1,800 · Legendary 4,000. A casual player (about 350 Gold a day) gets a Rare in about two days, a Legendary in about eleven.
- **Nothing random:** trails are bought by name; never in the wheel or Strongboxes. (Keeps the Strongbox odds as Weapons_v2 states them.)
- Bought for good, for every slot the trail fits. No duplicates, no selling.
- In-world: no shop pop-up. The trail strip in the Loadout is the shop: a trail you do not own shows its price; hold to buy (0.6 s); the line under it fills; a soft brass click; it is yours and equipped in the slot you were on.

### 4.4 Textures: built-in first, one Blender atlas later

- Built-in: `rbxasset://textures/particles/sparkles_main.dds` (soft sparkle), `rbxasset://textures/particles/fire_main.dds` (flame), `rbxasset://textures/particles/smoke_main.dds` (puff), and plain colour Trails (no texture). **Each path is checked to exist in Studio before use** (the pipeline page notes `smoke_main.dds` was never checked); a missing one falls back to the engine's default sparkle.
- The noise used by Pulse and Nebula: a Trail with no texture and a banded Transparency sequence, its offset animated by script, until an atlas exists.
- **The trail atlas (Blender):** one 1024 × 1024 sprite sheet rendered in Blender (two leaf shapes, a triangle shard, a five-point star, an ember, a puff, a ring, a spark), white on transparent so ParticleEmitter colours tint it. It needs **one image upload**, which needs the owner's yes. Until then Leafwake, Shardfall and Wishing Stars use the sparkle tinted, and look close enough to sell.

### 4.5 Preview and equip

- The trail strip in the Loadout: three slots across the top (SWING · ARROW · THROW); below, the trails that fit the chosen slot as small swatches of the trail itself (a ViewportFrame drawing a short static stroke) with the name under it and a price or nothing (owned).
- Choosing one plays it on your avatar at the rack at once: a swing for SWING, a shot into the far end of the car for ARROW, a throw for THROW; it loops while it is selected.
- The kits' and the round's weapons use whatever is equipped; changing trails is free and can be done any time in the train.

### 4.6 Cost and settings

- Per projectile or swing: at most 1 Trail + 1 ParticleEmitter + 2 Beams; particle Rate at most 60, at most 40 alive per emitter.
- Others' trails are not drawn beyond 120 studs, and only the 12 nearest players' swing trails are drawn at once.
- Settings, one line: `OTHERS' TRAILS   All · Natural · Off` (default All on PC and console; Natural on phones and when the graphics quality is low). "Natural" draws the others' Bright trails as Draught. Your own trails always show to you.

---

## 5. Tier looks: 1★ to 5★, and two new weapons

### 5.1 The rule

- **Same silhouette at every star** (length, head, guard size within 5%): anyone reads "that is a Twin-Bit Axe" at 60 studs, whatever its stars.
- **Detail grows inside the silhouette:** each star adds parts and finish (geometry, trims, wraps, bands, inlay, edge), and the top tiers are visibly better made up close and in your own hands.
- **Still matte:** roughness 0.55 or more (brass 0.6), no Reflectance, no Neon, no emissive, no glow. Better materials read through colour, value contrast and crisp facets, not shine.
- Built in Blender (`art\blender\ir_weapons.py`, ItemsReal pipeline) as five variants per weapon, `<id>_t1` to `<id>_t5`, each part tagged with its `Role`. `ItemModels.build(id, variant)` takes the stars and picks the variant; `Stars.applyFinish` still tints by role. Triangle budget: 1★ up to 1,400, 5★ up to 2,500 (the held-item cap).

### 5.2 What each star adds (all weapons)

| Stars | Name | Geometry | Finish |
|---|---|---|---|
| 1★ | Worn | The base model. Two chipped notches on the edge (small facet cuts), a wrap that is loose at the end (one trailing strap), a plain flat pommel. | Dull grey steel with brown-grey patches, faded wood, cracked leather. Edge the same tone as the blade. |
| 2★ | Sound | Clean edge, tidy wrap, ends tucked. | Clean steel, sound wood and leather (the model as authored today). |
| 3★ | Fine | + A **fuller or bevel line** along the blade (a second, narrower bevel strip, 0.03 studs); the grip wrap in a **diamond cross-wrap** (raised ridges in a lattice); a steel **ferrule ring** where grip meets head or guard. | Darker blued steel, fresh leather, a **lighter honed edge strip** along the full cutting edge. |
| 4★ | Superior | + A **brass collar** and **pommel cap** (6 to 12 sided); **two engraved bands** on the blade near the guard or on the axe cheek (inset grooves 0.02 deep); a **rivet row** on leather or the haft (3 to 5 small 6-sided studs); stitched leather on the grip edge. | Dark hardwood, darker steel, matte brass. |
| 5★ | Masterwork | + An **inlay line** along the spine or haft (a darker steel or brass strip set flush); a **layered-steel band** near the edge (alternating dark and light facets, our own pattern-weld look); a **cord knot and short tassel** at the pommel (2 small segments, hangs 0.3 studs); a small **maker's mark** (a punched notch shape) on the ricasso or cheek; the honed edge strip runs to a crisp **clipped tip**. | Near-black blued steel against the pale honed edge (the strongest value contrast, so it reads as "the best" even at 20 studs), walnut, brass. |

### 5.3 Per weapon: what 3★, 4★ and 5★ add

| Weapon | 3★ Fine | 4★ Superior | 5★ Masterwork |
|---|---|---|---|
| Hunting Knife | fuller line; cross-wrapped grip | brass bolster and pommel cap; 3 rivets on the scale | spine inlay; tassel loop through the pommel; layered band by the edge |
| Leaf Dagger (new) | ridge line on both faces; tight spiral wrap | brass ring collar; ring pommel turned (12 → 16 sides) | inlaid central ridge; cord knot through the ring |
| Ring Blade | inner bevel ring; cord wrap tight | brass ferrules engraved with 2 bands | layered band round the outer edge; a second wrap colour (charcoal over oxblood) |
| Longsword | fuller; ferrule | brass guard ends and pommel; 2 engraved bands | spine inlay, layered band, tassel, clipped tip |
| Machete | bevel line; tidy wrap | brass rivets in the grip; lanyard hole lined in brass | layered edge band; spine inlay |
| Paired Blades (new) | diamond wrap visible as raised windows; edge strip | round guards with a brass rim; 2 engraved bands | spine inlay, tassels in two cord colours (one per blade, so the pair reads as a pair) |
| Hatchet | haft ferrule; edge strip | brass wedge in the eye; 3 haft rivets | engraved cheek band; layered edge; leather collar with stitching |
| Twin-Bit Axe | edge strips on both bits | brass collar under the head; 2 cheek bands | layered steel bands on both bits; haft inlay; leather band with a cord knot |
| Climbing Pick | wrist-loop stitching | brass spike ferrule | engraved head band; haft inlay |
| Spear | socket ferrule; head bevel line | brass socket ring and butt cap; binding with 2 colours | engraved head band; haft inlay line; small cord tassel under the head |
| Recurve Bow | grip wrap cross-laid | brass nock beads and limb tip caps | inlaid limb strips (dark horn look), engraved riser band |
| Short Bow | tidy wrap | brass arrow-shelf plate | inlaid limb line |

### 5.4 New weapon: Paired Blades (`paired_blades`)

From the owner's crossed-blades picture; our own design.

**Look.** Two short single-edged swords, each 2.7 studs: a 2.0-stud blade with a gentle curve (3 facets), a straight spine and a **clipped, angled tip**; blued-black matte steel (62, 64, 68) with a pale honed edge strip (176, 176, 170) the full length; a **round guard** 0.42 across (12 sides), satin grey steel (150, 150, 146); a 0.6-stud grip **diamond-wrapped** in black cord over dark grey (five raised diamond windows); a small round pommel cap. Carried crossed on the back with the grips over the shoulders (the owner's picture is two crossed); in hand one in each hand, edges forward.

**Role:** the pressure weapon: the fastest chain and the only 4-step light chain with a strong finisher, weakest guard among swords.

| Damage | Swing every / windup | Reach | Stamina | Guard | To down 1★ / 5★ | Rarity, where |
|---|---|---|---|---|---|---|
| 19 (4th step 26.6) | 0.38 s / 0.07 s | 5.5 | 0.035 | 60% | 1.71 / 1.58 s | Epic: the Horn (tier 3, weight like the Longsword, at most 1 a round), the wheel and Strongboxes. Never in kits. |

```lua
paired_blades = { name = "Paired Blades", kind = "Melee", rarity = "Epic", stack = 1, starred = true,
	damage = 19, cooldown = 0.38, range = 5.5, windup = 0.07, staminaCost = 0.035, offHand = true,
	desc = "Two short blades. Fast chains that finish hard.", equipSound = "Equip_Blade" },
```

**Build note:** both hands hold a blade. `InventoryService` welds the right blade to `RightGripAttachment` today; the left blade is a second model (`paired_blades_L`, the mirror) welded to `LeftGripAttachment` when `offHand = true`, and the viewmodel shows both. **Fallback** if the second hand slips: ship it as the **Wrapped Sabre** (one 3.4-stud single-edged sword, the same blade, round guard and diamond wrap; damage 30, swing every 0.55 s, windup 0.13, reach 7, 3-step chain), and the pair follows.

### 5.5 New weapon: Leaf Dagger (`leaf_dagger`)

From the owner's throwing-dagger picture; our own design.

**Look.** 1.25 studs. A **leaf-shaped blade** 0.65 long, widest a third of the way up, a diamond cross-section (4 faces meeting in a central ridge), blued-black matte steel with pale honed edges; a 0.35 grip with a raised **spiral wrap** in dark cord; a **ring pommel** 0.22 across (a 12-sided ring). Carried in a sheath on the right thigh. In first person, when idle for 6 s, the finger goes through the ring and it turns once in the hand (a small flourish).

**Role:** the quiet thrower. A quick stab up close, and one precise throw you go and pick up.

| Melee | Throw | Special rule | Rarity, where |
|---|---|---|---|
| 18, every 0.42 s, windup 0.08, reach 4.2, stamina 0.035 | 40 (head ×1.6 = 64), 150 studs/s, gravity 20, on the crosshair to 30 studs, stamina 0.05; it stays where it lands | **Silent throw:** no whoosh beyond 10 studs. A thrown hit on someone facing away who was not hurt in 5 s does 50 (the Hunting Knife's unseen rule, thrown) | Uncommon: tier 2 crates and the Horn, the wheel and Strongboxes. Never in kits |

```lua
leaf_dagger = { name = "Leaf Dagger", kind = "Melee", rarity = "Uncommon", stack = 1, starred = true,
	damage = 18, cooldown = 0.42, range = 4.2, windup = 0.08, staminaCost = 0.035,
	throwable = true, throwDamage = 40, throwSpeed = 150, throwGravity = 20, throwHeadMultiplier = 1.6,
	throwOnTargetRange = 30, throwStaminaCost = 0.05, throwUnseenDamage = 50, quietThrow = 10,
	desc = "A leaf blade with a ring. Throw it quietly, then fetch it.", equipSound = "Equip_Blade" },
```

### 5.6 The weapon table now (1★)

| Family | Weapon | Role | Damage | Swing every | Reach | Throw |
|---|---|---|---|---|---|---|
| Fists | Fists | baseline | 8 | 0.45 | 4 | — |
| Short blade | Hunting Knife | quick, quiet; unseen hit 40 | 20 | 0.48 | 4.5 | — |
| Short blade | **Leaf Dagger** | quiet thrower; silent unseen throw 50 | 18 | 0.42 | 4.2 | 40 |
| Short blade | Ring Blade | close slash, flat throw | 24 | 0.55 | 5.5 | 38 |
| Sword | Longsword | the duellist | 36 | 0.62 | 8 | — |
| Sword | Machete | wide cut, second contender 60% | 26 | 0.55 | 7 | — |
| Sword | **Paired Blades** | pressure, fastest chain | 19 | 0.38 | 5.5 | — |
| Axe | Hatchet | short axe and tool, heavy throw | 34 | 0.80 | 5 | 45 |
| Axe | Twin-Bit Axe | heavy, breaks armour, spinning throw | 42 | 0.95 | 7 | 65 |
| Axe | Climbing Pick | climbing tool | 26 | 0.65 | 5 | — |
| Spear | Spear | long reach, big throw | 34 | 0.70 | 9.5 | 60 |
| Throwing | Throwing Knives | quick short throws, stack 6 | 22 / 35 head | 0.5 | — | yes |
| Bow | Recurve Bow / Short Bow | as Weapons_v2 section 6 | 14–50 / 10–36 | draw 0.9 / 0.6 | 60 / 40 on target | — |

---

## 6. The load-in: the Gathering

When a player appears, a swirl of leaves and soft light gathers into them, after the owner's "Nature Trail VFX" video.

### 6.1 When

| Moment | Who sees it |
|---|---|
| The end of the launch, as the player appears on their plinth in the arena | the player (first person) and others within range |
| Spawning into the red train (joining, and coming back after a round) | the player (third person in the train) and others in the car |
| Not: respawns in practice, spectating, late joins mid-round | — |

### 6.2 What it looks like (0.85 s)

Colours from the valley: moss (96, 124, 64), meadow (150, 176, 92), birch gold (214, 190, 112), soft sky light (236, 232, 206).

| Time | Leaves | Light | Body |
|---|---|---|---|
| 0.00 to 0.35 s | 14 small leaves (matte, two shapes, in the moss, meadow and gold colours) sweep in on a rising spiral from 4 studs out, 1.5 turns, from the feet to head height, speeding up | Two ribbons of soft light (Trails on two attachments circling with the leaves) in meadow to sky light, LightEmission 0.35 | The body fades in from the feet up (transparency 1 → 0 through the parts, lowest first) |
| 0.35 to 0.60 s | The spiral tightens to the chest; the leaves shrink and fade into the body | The ribbons close in; one PointLight (brightness 0.3, range 8, birch gold) swells and fades | Fully shown at 0.6 s |
| 0.60 to 0.85 s | 4 leaves fall loose to the feet and fade on the ground | 8 sparkle particles drift up and fade | — |

In first person at the arena: the leaves sweep past the camera and the viewmodel's hands fade in at 0.4 s; the brief glare of the launch's end (`LaunchIntroController\Glare`) comes after it, not on top. Sound: a soft leaf rustle and an airy two-note chime (`Sounds` key `LoadIn_Gather`), quiet.

Matte where it matters: the leaves are matte geometry; only the ribbons and the sparkles have light, for under a second.

### 6.3 Cheap

- Client-only. The server marks the moment with an attribute on the character (`AppearedAt`, server time); each client plays it if it is within 1 s of now (late joiners never see old ones).
- One pooled rig per effect: 14 leaf MeshParts (from the valley's own foliage leaves in Blender, under 40 triangles each), 2 attachments with 2 Trails, 1 ParticleEmitter, 1 PointLight. Moved by script with CFrames, no physics, no tweens per leaf.
- Up to 6 full effects at once (yours and the nearest 5). Beyond that, or further than 80 studs: the ribbons only. Beyond 160 studs: nothing. At low graphics quality: 6 leaves.
- At the launch end all 48 appear at once: each client plays 6 full and up to 42 ribbon-only (84 short Trails for under a second). If that dips frames on phones, the ribbon-only ones are dropped first.

---

## 7. Animation: clips made in Blender, played as data

### 7.1 How

The proven route (`AnimationPipeline_2026-11-18.md`): Blender script → baked joint Transforms → Studio builds a KeyframeSequence with `execute_luau`; no plugin, no FBX import. For the game, **no upload** either: the joint Transforms are baked into ModuleScripts (`ReplicatedStorage.Shared.Clips.<Family>`) and played by a small **clip player** written in `src`:

- **Third person:** a clip player inside `CharacterVisuals` layer 7 (where today's three-key swings are). It sets the joints' Transforms from the clip each frame, interpolating between keys (Catmull-Rom, so motion is smooth at 60 fps from 30 fps data), and replaces the W/M/F shapes. It is the same machinery CharacterVisuals already uses for poses, so no Animator, no asset ids.
- **Upper body by default:** attack, guard, parry, reaction and throw clips drive only `UpperTorso` and up (waist, neck, shoulders, elbows, wrists); the legs keep the locomotion (the owner's "reactions override the upper body layer only; legs keep walking"). The exporter gets the part filter the pipeline page lists as open. **Full body** only for moves that own the legs: dodges, kick, heavy lunges, the skills, knockdown and get-up.
- **Blend rules** (the owner's): reactions additive, 0.08 s in, 0.25 s out; an attack blends in over 0.06 s from wherever the body is (so a chain flows from one step into the next instead of snapping); back to the idle guard over 0.15 s.
- **Fitted to the server:** each clip's hit frame is at the weapon's windup at 1★ (the server's strike time). Stars shorten the recovery only, so the clip's recovery section plays faster at higher stars; the hit frame never moves. The Blender exporter places a key exactly at the hit time (sub-frame) and a `Hit` marker there.
- **First person:** the same moves authored in Blender on the blocky viewmodel arms (camera space, as `Poses` describes it), baked as wrist frames and elbow poles per frame into `Shared.Clips.View<Family>`. `Poses.swing` reads a clip when one exists, and falls back to today's waypoints when not, so nothing breaks while clips arrive.
- **Size:** upper-body clips about 200 bytes a frame, first-person about 60. The whole set below is about 400 KB of data, split by family and loaded when a weapon of that family is first seen.
- **How each clip is made** (the `HUNGER-GAMES:blender-art` skill and `art\blender\anim\ls_anim.py`): keys on hands, feet and torso; anticipation 2 to 4 frames before the cut; the cut over 2 to 3 frames; a follow-through that overshoots and settles; the weapon's weight in how long the body takes to recover (axe longer than knife). Checked in Blender on every frame (no foot slide, no blade through the body or the ground), a contact sheet looked at, then played on a rig in Studio Edit mode before it ships.

### 7.2 The clip list

Times in seconds; "hit" is the strike (damage) time; frame at 30 fps in brackets. Every clip below is made twice: third person (TP) and first person (FP), except where marked.

**Every melee family (one set, held-item agnostic):**

| Clip | Length | Hit / key moment | Body |
|---|---|---|---|
| `guard_in` / `guard_hold` (loop) / `guard_out` | 0.10 / 1.0 / 0.12 | — | upper |
| `block_hit` | 0.25 | contact 0.03 (1) | upper |
| `guard_break` | 0.80 | — | full |
| `parry` | 0.30 | deflect 0.05 (1.5) | upper |
| `kick` | 0.59 | 0.16 (5) | full |
| `dodge_back` / `dodge_left` / `dodge_right` / `dodge_roll` | 0.55 / 0.55 / 0.55 / 0.60 | travel 0.15 to 0.40 | full |
| `react_light_F` / `_B` / `_L` / `_R` (TP only) | 0.33 | — | upper, additive |
| `stagger_F` / `_B` / `_L` / `_R` (TP; FP: the camera jolt) | 0.60 | — | full |
| `heavy_stagger_F` / `_B` | 0.90 | — | full |
| `knockdown` + `getup` | 1.00 + 0.60 | — | full |
| `skill_concentration`, `skill_second_wind`, `skill_brace` | 0.50, 0.40, 0.40 | — | upper |

**Per family:**

| Family | Clip | Length | Hit (frame) |
|---|---|---|---|
| Fists | `fists_light_1` jab · `_2` cross · `_3` hook | 0.45 · 0.45 · 0.52 | 0.06 (2) · 0.06 (2) · 0.08 (2.4) |
| | `fists_heavy_charge` (loop) · `fists_heavy` haymaker | 0.5 · 0.65 | 0.12 (3.6) |
| | `fists_skill_head_kick` | 0.70 | 0.22 (6.6) |
| Short blade | `knife_light_1` backhand · `_2` forehand · `_3` stab | 0.48 · 0.48 · 0.52 | 0.10 (3) · 0.10 (3) · 0.12 (3.6) |
| | `dagger_light_1..3` (Leaf Dagger) | 0.42 · 0.42 · 0.46 | 0.08 · 0.08 · 0.10 |
| | `ring_light_1..3` (Ring Blade) | 0.55 · 0.55 · 0.60 | 0.12 · 0.12 · 0.14 |
| | `shortblade_heavy_charge` · `shortblade_heavy` lunging stab | 0.5 · 0.65 | 0.12 (3.6) |
| | `shortblade_counter` | 0.47 | 0.06 (2) |
| | `shortblade_skill_chained` | 1.20 | 0.06, 0.26, 0.46, 0.66, 0.86 |
| | `dagger_flourish` (FP idle, ring spin) | 1.2 | — |
| Sword | `sword_light_1` diagonal · `_2` rising · `_3` horizontal · `_4` overhead | 0.62 · 0.62 · 0.62 · 0.72 | 0.16 (4.8) · 0.16 · 0.16 · 0.20 (6) |
| | `machete_light_1..3` | 0.55 · 0.55 · 0.62 | 0.14 · 0.14 · 0.17 |
| | `paired_light_1..4` (right, left, right rising, cross) | 0.38 · 0.38 · 0.38 · 0.50 | 0.07 · 0.07 · 0.07 · 0.12 |
| | `sword_heavy_charge` · `sword_heavy` (lunge) · `paired_heavy` (scissor) | 0.5 · 0.79 · 0.65 | 0.16 (4.8); paired 0.12 (3.6) |
| | `sword_counter` · `paired_counter` | 0.47 | 0.06 |
| | `sword_skill_running_cut` | 0.90 | cuts from 0.20 to 0.50 |
| Axe | `hatchet_light_1..3` | 0.80 · 0.80 · 0.90 | 0.18 · 0.18 · 0.22 |
| | `twinaxe_light_1` · `_2` | 0.95 · 0.95 | 0.30 (9) · 0.26 (7.8) |
| | `pick_light_1..3` | 0.65 · 0.65 · 0.70 | 0.14 · 0.14 · 0.16 |
| | `axe_heavy_charge` · `axe_heavy` overhead (twin axe: `twinaxe_heavy`) | 0.5 · 0.79 (twin axe 1.00) | 0.16 (twin axe 0.22) |
| | `axe_counter` | 0.47 | 0.06 |
| | `axe_skill_whirl` | 1.15 | turn from 0.35 to 0.65 |
| Spear | `spear_light_1` thrust · `_2` thrust · `_3` butt swing | 0.70 · 0.70 · 0.70 | 0.20 (6) · 0.20 · 0.16 (4.8) |
| | `spear_heavy_charge` · `spear_heavy` lunge | 0.5 · 0.79 | 0.16 |
| | `spear_counter` | 0.47 | 0.06 |
| | `spear_skill_vault_kick` | 1.25 | 0.75 (the kick lands; 0.3 plant + 0.45) |
| Throwing | `throw_knife` flick · `throw_dagger` · `throw_ring` (flat) · `throw_hatchet` · `throw_spear` · `throw_twinaxe` | 0.50 · 0.45 · 0.55 · 0.70 · 0.60 · 0.90 | release 0.10 · 0.08 · 0.14 · 0.20 · 0.22 · 0.30 |
| | `throw_wind` (the held throw, loop) | 0.4 | — |
| Bow | `bow_nock` · `bow_draw` · `bow_hold` (loop) · `bow_release` (the owner's list) | 0.30 · drawTime · 1.0 · 0.32 | release 0.0 |
| | `bow_dodge_letdown` | 0.25 | — |
| Equip | `equip_<family>` × 7 | 0.32 | — |

That is about 110 clips per view. They are made family by family in the build order (9.3); the Longsword chain is first, as the sample to show the owner.

---

## 8. What is not on this page

- The training room and its trials (the owner: after the fighting is "perfect").
- The owner's video mock-up (they will show it later).
- Shaders, loading for everyone, and server capacity before publishing (the owner's last line: a check at the end, before release).
- Hit regions beyond the head for melee damage (melee hits do the same damage anywhere; region only changes the knockback).
- Durability (Weapons_v2 section 8).

---

## 9. For the builders

### 9.1 Config (new keys)

```lua
Config.Combat.Moves = {
	ChainWindow = 0.45, -- (SwingChainWindow, kept)
	ActiveTime = 0.06,
	Heavy = { MinHold = 0.25, FullHold = 0.75, MinMult = 1.3, FullMult = 1.6, MaxHoldAfterFull = 1.5,
		HoldDrain = 0.05, StaminaMult = 2.2, ReachAdd = 0.5, LungeReachAdd = 1.5, WalkMult = 0.7,
		ReleaseWindup = { Light = 0.12, Medium = 0.16, Heavy = 0.22 },
		Recovery = { Light = 0.45, Medium = 0.55, Heavy = 0.70 } },
	Guard = { RaiseTime = 0.10, LowerTime = 0.12, Arc = 120, WalkMult = 0.6, StaminaPerDamage = 0.004,
		HeavyDrainMult = 1.5, BreakStagger = 0.8,
		Share = { fists = 0.40, knife = 0.55, leaf_dagger = 0.50, ring_blade = 0.65, sword = 0.75, machete = 0.65,
			paired_blades = 0.60, hatchet = 0.65, twin_axe = 0.70, climb_pick = 0.55, spear = 0.70, throwing_knife = 0.40 } },
	Parry = { Window = 0.18, ConcentrationWindow = 0.26, WhiffLock = 0.6, AttackerStagger = 0.5, HeavyAttackerStagger = 0.8 },
	Counter = { Window = 0.45, Windup = 0.06, Recovery = 0.35, Mult = 1.5, Stamina = 0.03, HitStop = 0.10 },
	Kick = { Windup = 0.16, Recovery = 0.35, Reach = 4.5, Damage = 6, Stamina = 0.07, Cooldown = 1.2, GuardBreakStagger = 0.45 },
	Dodge = { Startup = 0.15, Travel = 0.25, Recovery = 0.15, Distance = 8, BackDistance = 6, Stamina = 0.16,
		Cooldown = 0.7, RepeatWindow = 2, RepeatCostMult = 2 },
	ExhaustedAttackSpeed = 0.5,
}
Config.Combat.Reactions = {
	Flinch = { Stagger = 0, HitStop = 0.04, Jolt = 2 },
	Stagger = { Time = 0.4, HitStop = 0.05, Jolt = 6, WalkMult = 0.5 },
	Heavy = { Time = 0.7, HitStop = 0.08, ShakeAttacker = { 0.25, 0.2 }, ShakeVictim = { 0.4, 0.3 } },
	Knockdown = { Down = 1.0, Getup = 0.6, RollOutAfter = 0.5 },
	Poise = { AfterStagger = 0.8, AfterKnockdown = 1.5 },
	Knockback = { Decay = 108, Cap = 36, HeavyMult = 1.5, Region = { Head = 1.4, Torso = 1.0, Limbs = 0.7 },
		Speed = { fists = 12, knife = 18, leaf_dagger = 16, ring_blade = 20, paired_blades = 16, machete = 34, sword = 28,
			hatchet = 30, climb_pick = 24, spear = 26, twin_axe = 36, kick = 30, counter = 36 } },
	HitStopViewRange = 30,
	BlendIn = 0.08, BlendOut = 0.25,
}
Config.Skills = {
	LockedFirst = 45, -- seconds into a real round
	Weapon = {
		Fists = { id = "head_kick", Windup = 0.22, Damage = 14, Reach = 4.5, Stamina = 0.12, Cooldown = 10 },
		ShortBlade = { id = "chained_strikes", Mults = { 0.45, 0.5, 0.55, 0.65, 0.85 }, Gap = 0.2, Step = 0.5, Stamina = 0.18, Cooldown = 16 },
		Sword = { id = "running_cut", Crouch = 0.2, Dash = 12, DashTime = 0.3, Lane = 3, Mult = 0.6, MaxTargets = 4, Knockback = 24, Stamina = 0.28, Cooldown = 18 },
		Axe = { id = "whirl", Windup = 0.35, Spin = 0.3, RadiusAdd = 1, Mult = 0.65, MaxTargets = 4, Knockback = 30, Stamina = 0.24, Cooldown = 15 },
		Spear = { id = "vault_kick", Plant = 0.3, Vault = 5, HitAt = 0.45, Reach = 3, Damage = 12, Knockback = 36, Lift = 8, Stamina = 0.24, Cooldown = 18 },
		Throwing = { id = "ricochet", Armed = 4, Range = 20, Cone = 120, Share = 0.7, Cooldown = 14 },
		Bow = { id = "piercing_shot", Armed = 6, SpeedMult = 1.15, SecondShare = 0.7, Cooldown = 20 },
	},
	General = {
		concentration = { Time = 6, ChargeMult = 1.3, StaminaMult = 0.7, Cooldown = 40 },
		second_wind = { Stamina = 0.5, Heal = 8, HealTime = 4, Cooldown = 60 },
		sprint_burst = { Time = 3, SpeedMult = 1.25, Cooldown = 35 },
		quiet_step = { Time = 8, HearRange = 6, CrouchMult = 1.4, Cooldown = 45 },
		steady_hands = { Time = 8, DrawMult = 0.85, ThrowOnTargetAdd = 10, Cooldown = 45 },
		brace = { Time = 4, KnockbackMult = 0.5, Cooldown = 40 },
	},
	KitSuggests = { archer = "Bow", forager = "ShortBlade", hunter = "Throwing", climber = "Axe" },
}
Config.Trails = {
	Prices = { Common = 300, Rare = 800, Epic = 1800, Legendary = 4000 },
	Free = { "draught", "dust" }, Default = { swing = "draught", arrow = "draught", throw = "draught" },
	StartAfter = 6, -- studs from the hand before an arrow or throw trail shows
	DrawRange = 120, MaxSwingTrails = 12, MaxRate = 60, BuyHold = 0.6,
	OthersDefault = { Desktop = "All", Phone = "Natural" },
}
Config.Economy.RobuxTrails = false
Config.LoadIn = { Duration = 0.85, Leaves = 14, LowLeaves = 6, FullMax = 6, FullRange = 80, RibbonRange = 160,
	Colors = { Moss = Color3.fromRGB(96, 124, 64), Meadow = Color3.fromRGB(150, 176, 92),
		Gold = Color3.fromRGB(214, 190, 112), Sky = Color3.fromRGB(236, 232, 206) } }
```

### 9.2 Code touchpoints

| Script | Change |
|---|---|
| `Shared\ItemDefs.lua` | `paired_blades`, `leaf_dagger` (5.4, 5.5); `family` on every weapon (Fists, ShortBlade, Sword, Axe, Spear, Throwing, Bow) |
| New `Shared\Moves.lua` | The chain tables (1.4), heavy, guard shares, reaction tier per weapon and move, read by both sides (as `CombatStats` is) |
| `Shared\CombatStats.lua` | `CombatStats.move(def, stars, moveId, charge)` → damage, windup, recovery, reach, stamina, reaction; stars as today |
| `CombatService` | Moves on `MeleeSwing`; `Guard`, `Dodge`, `Skill` remotes; parry, counter, kick, poise, reactions; three-ray traces; `Reaction` to the victim; skills (spatial queries) |
| `CombatController` | Tap / hold Attack, Guard on Aim for melee, Kick, the held throw, Dodge, R / F skills; ClientState for the HUD's skill rings; hit-stop on the local view |
| `MovementController` | Dodge travel, the knockback impulse and decay on your own body, guard and charge walk speeds, stagger slow, Sprint Burst, Quiet Step |
| `CharacterVisuals` | The clip player (7.1) in place of W/M/F; reactions; trails on other players' swings; the Gathering on others |
| `ViewmodelController` + `Poses` | First-person clips with fallback to waypoints; hit-stop; the Leaf Dagger flourish; two-handed Paired Blades |
| `ProjectileController` / `ProjectileService` | Projectile trails (with `StartAfter`); Ricochet and Piercing Shot on the server |
| `KitController` → `LoadoutController` | The Loadout screen (section 3), the summary line, the trail strip and buying; `KitPick` replaced by `LoadoutSet` |
| `KitService` | Reads the loadout; unchanged delivery |
| `DataService` | Profile `loadout { kit, bring, specialty, general, trails }`, `trailsOwned` |
| New `EconomyService` (Weapons_v2) | `BuyTrail(id)`: price check, Gold spend, logged |
| `InventoryService` | Off-hand weld for `offHand` items; tier variant on the held model |
| `ItemModels` + `art\blender\ir_weapons.py` | Five variants per weapon (`_t1`..`_t5`), Paired Blades, Leaf Dagger |
| `LaunchController`, `PlayerService` | `AppearedAt` for the Gathering; new `LoadInController` plays it |
| `HUDController` | Two skill rings (and on touch, the GUARD and skill buttons) |
| `SettingsController` | `OTHERS' TRAILS  All · Natural · Off` |
| `art\blender\anim\` | Exporter part filter (upper body), sub-frame hit key, first-person export; one script per family |

### 9.3 Build order (the owner's: fighting first; show each as soon as it runs)

1. **The clip player and the Longsword chain** (TP and FP, Blender to data), plus hit-stop and the upper-body reaction. Show the owner one chain against a dummy, before and after.
2. Light chains and heavies for every family, with their clips.
3. Guard, parry, counter, kick, dodge; stagger, poise and knockback.
4. The tier models in Blender (1★ to 5★ for every weapon), then Paired Blades and Leaf Dagger.
5. The Loadout screen (kit, bring, skills, trails) replacing the K line.
6. Skills, weapon and general.
7. Trails: the 18, buying with Gold, previews; the atlas once the owner says yes to its upload.
8. The Gathering (load-in).
9. Then, per the owner: the training room and the load-up to the arena; their video mock-up; the release check (shaders, loading, servers).

### 9.4 Checks before each is called done

- Two clients in Studio, one with 200 ms of lag: chains, parries and dodges agree on both screens within one frame of the hit.
- A pile of 8 bots on one player: no stun-lock past poise; frame time on a phone at 48 players with trails at "All".
- No red anywhere on a hit; every weapon matte under the arena's lighting (screenshots).
- Each clip looked at as a contact sheet in Blender and in a playtest, first and third person.

---

## 10. Questions for the lead (not for the builders)

1. **Paired Blades or the Wrapped Sabre?** The owner's picture is a crossed pair; the pair needs an off-hand weld and two-handed first-person clips. The page builds the pair and keeps the sabre as the fallback.
2. **Specialty** is the lead's reading of "skills for diff weapons that a person chooses in a kit": one family's skill unlocked, plus one general skill. If the owner wants every family's skill available to everyone, set `Config.Skills.Specialty = false` (R then does the held weapon's skill).
3. **Bright trails vs the 15 Nov "restrained" note.** Their 19 Nov references glow; the page has both kinds and a setting. Worth one line to the owner when trails are shown.
4. **The trail atlas** needs one image upload (the owner's yes). Until then three trails use tinted sparkles.
5. **Knockback numbers:** the owner's spec has a speed-and-decay pair that disagrees with its own "1.5 studs" for a knife; the page keeps the 1.5 studs (decay 108). Say so if the owner asks why a hit pushes less than 13 studs.
6. **"Critical hits"** on the owner's Concentration card are left out (damage stays predictable, and Mild). Concentration widens the parry window instead.
