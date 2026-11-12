# Combat Physics Plan — LAST STANDING

Research and planning only. Nothing in the Roblox place was changed. Written 2026-11-10.

- **Scope:** realistic, weighty first-person melee and ranged combat. Weapons: fists, knife, machete, hatchet, spear (melee and thrown), mace, sword, bow and arrows, throwing knives. Also armour vests, health, hunger and thirst.
- **Inputs:**
  - the live scripts, read from the running place (Studio Play mode, Server datamodel, read-only);
  - the original combat agent's report;
  - `docs/GameDesign.md`;
  - `art/manifests/Items.manifest.json`;
  - web research, cited as **[S#]** (full list in §8).
- **Code references** use the place's instance paths, e.g. `CombatService.meleeTrace`.
- **Marked unconfirmed:** anything I could not confirm, including community claims I could not verify.

---

## 0. Summary

**Where combat stands now.** The combat code is solid and has good bones:

- server-side damage, rate limits and cooldowns;
- simulated projectiles with client prediction;
- a procedural viewmodel with hit-stop.

What still plays like an arcade game:

1. **Other players' attacks are invisible.** The `CombatAction` remote is broadcast, but no client uses it. Remote players show no wind-up, swing, draw or throw: you are hit by a sound.
2. **Melee is a fat hitscan.** The server does one instant `Spherecast` (radius 2.4) along the camera at the strike frame, plus a flat 3-stud lag allowance. Effective reach is **10.9 to 14.9 studs (3.1 to 4.2 m)**, and the swing's direction and arc don't matter.
3. **Swings have no commitment.** Wind-ups are 60 to 250 ms. The server never learns when a swing started, so a zero-wind-up strike is possible. Stamina costs exist in `ItemDefs` but are never spent.
4. **Hits cause no reactions.** Nobody flinches, staggers, gets interrupted or gets knocked back.
5. **Damage ignores where you hit.** Melee has no hit zones. Armour reduces every hit, including head hits. Hats and hair count as the head.
6. **Projectiles feel off.** Gravity is not the real value and there is no drag. Thrown knives and spears fly 2 to 3 times faster than real ones. Everything sticks, and recovered arrows move to a pickup on the ground instead of staying in the tree.
7. **No lag compensation, no ragdoll design.** The death behaviour is whatever the Avatar Joint Upgrade (AJU) does by default.

**Platform facts that shape the plan:**

- The place already runs the AJU: 15 `AnimationConstraint` and 14 `BallSocketConstraint` joints per character, and `CharacterBreakJointsOnDeath = false`. Ragdolls only need the AnimationConstraints switched off [S1][S3].
- Roblox's Server Authority reached full release on 2026-07-09, but it has **no built-in server rewind for hit detection** yet [S8]. Moving our custom client movement onto it would be a large rewrite.
- **Recommendation:** keep the current networking model and add our own lag-compensated validation now. Keep the combat maths pure, so it can move into `BindToSimulation` later.

**What I propose, in priority order:**

1. **Telegraphed, committed swings.**
   - Wind-up, active and recovery phases, timed and validated by the server.
   - Tap for a light attack, hold for a heavy one.
   - The attack direction comes from your mouse or stick motion, so no extra buttons are needed.
   - Stamina is spent on attacks.
   - Third-person attack poses for everyone watching.
2. **Accurate hits.** The client sweeps the blade along the same arc the viewmodel shows. The server checks each claimed hit against a 1-second position history.
   - Realistic reach, taken from the real weapon models.
   - Blades catch on trees and walls.
   - Body parts only (accessories don't count).
3. **A damage model.** Hit zones, armour that only covers the torso and depends on the damage type, and non-graphic wounds (bleeding, limping, dazed).
4. **Reactions.**
   - Interrupts: a hit cancels the victim's wind-up.
   - Stagger and modest knockback.
   - Procedural flinches on third-person bodies.
   - Hit-stop and "blade drag" on the attacker's viewmodel.
5. **Projectile physics.** Real gravity (35 studs/s²), quadratic drag, damage that falls with impact energy, and arrows that stick, glance or break. Stuck arrows can be pulled out of trees. Spread is deterministic and enforced by the server.
6. **Death ragdolls.** Server-owned corpses that stay until the round ends and react to the killing blow.
7. **Optional:** a simple guard with a perfect-block window, and knockdowns. These depend on your answers in §7.

**Content rating.** Bodies that ragdoll and stay are a realistic consequence of violence, so the game lands on a **Moderate** label (not Mild). I recommend **no blood** [S29].

---

## 1. Current-state audit

### 1.1 Who does what

| Layer | Script (place path) | Role today |
|---|---|---|
| Server | `ServerScriptService.Server.Services.CombatService` | `MeleeSwing` and `RangedRelease` handlers, melee trace, `applyHit`, Studio training dummies |
| Server | `…Services.ProjectileService` | Heartbeat ballistic simulation (no drag), impacts, recovery drops |
| Server | `…Services.PlayerService` | `damage()` (fires `DamageTaken`), death handling (cannon, kill feed, `dropAll`, respawn in the lobby after `RespawnDelay`) |
| Server | `…Services.InventoryService` | `getEquipped`, `removeEquipped` (thrown spear), `getArmorMultiplier` (one flat multiplier), third-person `EquippedModel` plus a "right arm raised" hold animation |
| Server | `…Services.MovementService` | Fall damage; speed sanity check (it only warns, never punishes) |
| Client | `StarterPlayer…Controllers.CombatController` | Input, swing timeline, local melee prediction, bow draw, throws, client-side spread, `DamageTaken` and `HitConfirm` feedback |
| Client | `…Controllers.ProjectileController` | Predicted and remote projectile visuals, sticking, impact effects, arrow whiz |
| Client | `…Controllers.ViewmodelController` (+ `Rig`, `Poses`) | Procedural world-scale arms; swings by weight with hit-stop (animation rate ×0.12) |
| Client | `…Controllers.CharacterVisuals` | Stance poses multiplied into joint `Transform` at `PreSimulation`; works with AJU rigs |
| Client | `…Controllers.MovementController` | Momentum movement; **owns stamina on the client only**; has `addImpulse(v)` (horizontal only); **no `spendStamina`** |
| Shared | `ReplicatedStorage.Shared.ItemDefs`, `Config.Combat`, `Net` | Stats (owned by Inventory), combat tunables, remotes and the token-bucket rate limiter |

### 1.2 How hits are detected, validated and applied today

**Melee**

1. **Client.** `startMelee` runs a timer:
   - wind-up from `ItemDefs.windup` (0.06 to 0.25 s);
   - total time `max(cooldown, windup + strike + 0.08)`;
   - holding Attack auto-repeats, and a press just before the end is buffered.

   At the strike moment, `strike()` fires `MeleeSwing(camera.LookVector)` **once**. It runs `predictMelee`, the same trace as the server without the lag allowance, so sounds, sparks and camera kicks are instant.
2. **Server.** `onMeleeSwing` checks, in order:
   - `Net.rateLimit` (5 per second, burst 3);
   - a finite unit vector (magnitude 0.9 to 1.1);
   - `getContext`: phase is Active, the player isn't Frozen, is an alive contender, and has a live Humanoid, Head and root;
   - `meleeDefFor(equipped)`: ammo and utility items fall back to fists, and bows and throwables are refused;
   - `facingOk`: the flat dot product with the root's look direction is at least −0.2 (about ±100°);
   - `tryCooldown`: `def.cooldown` with 0.12 s of jitter forgiveness.
3. **Server trace** (`meleeTrace`):
   1. From the **server head**, `workspace:Spherecast(radius = 2.4, distance = range + 3)` against an include-list of **whole character models, accessories included**, plus dummies.
   2. If that misses, a point-blank fallback: `GetPartBoundsInRadius(origin + dir·2.4, 2.4)`. A spherecast does not detect parts it starts inside [S11].
   3. A line-of-sight ray to the candidate, with 0.75 studs of slack.
   4. If no character was hit, a thin world ray that only picks the impact sound.
4. **Apply** (`applyHit`): `def.damage × getArmorMultiplier` goes to `PlayerService.damage`. The multiplier is 0.85 for the leather vest and 0.72 for padded armour, on **every** hit.
   - The victim gets `DamageTaken { amount, fromPosition = attacker root, cause }`.
   - The attacker gets `HitConfirm`.
   - Everyone else gets the `Hit_Flesh` sound.
   - Dummies use `Humanoid:TakeDamage` and wobble.

**Ranged and thrown**

- **Bow.**
  - Draw: the server timestamps the start of the draw.
  - Fire: charge is capped by the measured draw time (+0.15 s) and there is a 0.3 s minimum between shots. An arrow is consumed.
  - Speed `lerp(90, 240)` studs/s, damage `lerp(14, 50)`, gravity 55. The head multiplier is ×2, applied when the hit part is named `Head` (accessories resolve to the Head).
  - About 50% of arrows are recovered on world hits.
- **Throwing knife:** cooldown 0.5 s, 160 studs/s, gravity 40, 28 damage, head ×1.6.
- **Spear:** Aim + Attack throws it (`removeEquipped`): 150 studs/s, gravity 45, 60 damage.
- **Origin check.** The reported origin is accepted within 6 + 3 + 0.12 × speed studs of the server head (at least 9 studs), as long as there is line of sight from the head. Otherwise the head is used.
- **Spread is chosen on the client** (`applySpread`). The server accepts the direction as sent, within a facing check of −0.35.
- **`ProjectileService`.**
  - Runs on Heartbeat in sub-steps of at most 1/30 s.
  - Each step casts one ray against characters (shooter excluded) and one world ray. The world ray uses `RespectCanCollide`, so foliage is passed through.
  - No drag. 4 s lifetime. Caps of 300 projectiles in flight and 24 per shooter.
  - Recovered items come back as `LootService.spawnGroundItem`, which drops *below* the impact point.

**Feedback today**

- **Attacker:**
  - style-based camera kicks and shake;
  - viewmodel hit-stop and recoil springs;
  - instant local impact sounds and sparks;
  - a server hit marker (plus the kill sound);
  - the flesh sound plays late when the server confirms a hit the prediction missed.
- **Victim:**
  - a camera kick away from the attacker, shake and the Hurt sound;
  - directional damage arcs in the HUD;
  - a heartbeat at low health.
- **Observers:** swing and impact sounds only. `CombatAction` is sent at the strike, not the wind-up, and nothing on the client consumes it.

### 1.3 Effective numbers today

Effective server reach = `range + MeleeLagTolerance (3) + MeleeHitRadius (2.4)`, measured from the server head to the target's surface. 1 stud = 0.28 m [S19].

| Weapon | Damage | Cooldown (s) | Wind-up (s) | `range` | Effective reach (studs / m) | Hits to kill (100 HP, no armour) | DPS |
|---|---|---|---|---|---|---|---|
| Fists | 8 | 0.45 | 0.06 | 5.5 | 10.9 / 3.1 | 13 | 17.8 |
| Knife | 22 | 0.45 | 0.08 | 6 | 11.4 / 3.2 | 5 | 48.9 |
| Machete | 32 | 0.70 | 0.14 | 7 | 12.4 / 3.5 | 4 | 45.7 |
| Hatchet | 36 | 0.80 | 0.16 | 6.5 | 11.9 / 3.3 | 3 | 45.0 |
| Spear | 30 | 0.85 | 0.18 | 9.5 | 14.9 / 4.2 | 4 | 35.3 |
| Mace | 46 | 1.10 | 0.25 | 7 | 12.4 / 3.5 | 3 | 41.8 |
| Sword | 40 | 0.75 | 0.15 | 8 | 13.4 / 3.8 | 3 | 53.3 |

The real grip-to-tip lengths in `Items.manifest.json` are: knife 1.02, machete 2.08, hatchet 1.46, sword 3.05, mace 2.38 and spear 4.4 (the spear is 7.02 studs long, gripped at its balance point). The current reach is therefore roughly **2 to 3 times the physical reach**.

### 1.4 What feels game-like, or is missing (most important first)

1. **Invisible attacks.** There are no third-person attack, draw or throw animations, so wind-ups can't be read and nobody can react. Remote players hold their weapon in a static raised pose.
2. **Hitscan melee.** One instant, fat sphere along the view. Slashes, chops and stabs share the same hit volume, blades pass through trees, and the reach is huge.
3. **No commitment.** Wind-ups are below human reaction time and can be skipped (see §1.5). Holding the button auto-swings. Missing costs nothing, there is no movement penalty while attacking, and stamina is never spent.
4. **No physical consequence on hit.** No flinch, stagger, interrupt or knockback. A hit is just a number and a camera kick.
5. **Flat damage.**
   - Melee has no head or limb multipliers.
   - Armour reduces head hits too.
   - Big hats and hair enlarge the head hitbox and turn into headshots: `characterFromPart` maps accessories to the Head.
6. **Projectiles.**
   - Bow gravity is 55 studs/s²; real gravity is 35 studs/s² [S19].
   - No drag.
   - The thrown knife (160 studs/s, about 45 m/s or 160 km/h) and spear (150 studs/s, about 42 m/s) are 2 to 3 times realistic speeds (§2.8).
   - No glancing or bouncing.
   - Impact energy doesn't reduce damage at range.
   - Recovered arrows teleport to the ground.
   - Spread is trusted from the client.
7. **No lag compensation.** Melee is checked against the server's view of positions, which is behind what the attacker saw, plus a flat 3-stud allowance. Shots spawn on the server about half a round trip late.
8. **No ragdoll design.**
   - With the AJU and `CharacterBreakJointsOnDeath = false`, death probably already ragdolls by default [S1]. I could not confirm this without a playtest.
   - Either way, the body vanishes when the player is reloaded into the lobby, after `RespawnDelay` (4 s live, 2 s in Studio).
   - The killing blow pushes nothing.
9. **No defence** (blocking or guarding). This is a design decision, see §7.

### 1.5 Exploit surface today

| Issue | Why | Severity |
|---|---|---|
| Zero-wind-up strikes | The server only sees `MeleeSwing` at the strike. It can't tell whether a wind-up happened, so an exploiter can fire strikes back-to-back at the cooldown rate | High (every melee duel) |
| No-spread shots | The client picks the spread and the server accepts the direction | Medium |
| Corner shots | The origin may be ≥ 9 studs from the server head, as long as there is line of sight from the head | Medium |
| Ignoring stamina | Stamina only exists on the client | Medium, once stamina matters |
| Generous reach | It's by design (to cover latency), but it rewards lag | Low (it's a feel problem) |
| Good already | Damage is computed on the server, rate limits exist, ammo and items are consumed on the server, draw time is measured on the server | — |

### 1.6 Platform facts that shape the design (live place)

- **Characters:**
  - R15 with the AJU joints: 15 `AnimationConstraint`s (`IsKinematic = true`), 14 `BallSocketConstraint`s with limits on (for example the wrist has `UpperAngle = 30` and twist limits) and 4 `RigidConstraint`s;
  - `Humanoid.RequiresNeck = true`;
  - `StarterPlayer.CharacterBreakJointsOnDeath = false`;
  - the root's network owner is the player (`PlayerService` calls `SetNetworkOwner(player)`).
- **Workspace:**
  - `AuthorityMode = Automatic`, so Server Authority is off;
  - `StreamingEnabled = true`;
  - `Gravity = 196.2`;
  - only the **Default** collision group exists, so players collide with each other and with anything else.
- **`CharacterVisuals`** already layers poses into joint `Transform` at `PreSimulation`. This is exactly the AJU-recommended way to add procedural animation [S2][S3]. Third-person attack poses and flinches can use the same path.
- **The viewmodel arms are world-scale** (Arms manifest). The blade the player sees is physically meaningful, so the hit detection can match it.

---

## 2. Research findings

### 2.1 Melee hit detection on Roblox

- **Shapecasts.** `WorldRoot:Spherecast`, `Blockcast` and `Shapecast(part, …)` sweep a shape and return the first hit. They do **not** detect parts the shape starts inside, so a point-blank fallback stays necessary [S11][S12].
- **The community standard** is per-frame sweeps of points along the blade.
  - `ShapecastHitbox` (TeamSwordphin, v0.2.5, 2025) puts "DmgPoint" attachments on the blade. Each frame it casts every point from its previous position to its current one, using a ray, block or sphere [S13]. It succeeds `RaycastHitbox` [S14].
  - Its author recommends running detection **on the client** for accuracy and responsiveness, with the server doing sanity checks such as reach, and to "never trust the client" [S13].
  - Its limits: no detection when a cast starts inside a part, and stationary hitboxes register poorly [S13].
- **Fit for us.** We already have world-scale viewmodel blades, and the item manifests give exact Grip and Tip attachments. A per-frame point sweep along a **canonical arc**, which drives the viewmodel too, gives "what you see is what you hit".

### 2.2 Lag compensation

- **Roblox's stance.** The Server Authority full release (2026-07-09) says that "server side rewind" hit detection and time-synchronized remote events are **under examination**, not shipped. Even the Laser Tag template uses plain RemoteEvents, which can be off by about 40 to 50 ms [S8].
- **Industry pattern** (Valve Source engine):
  - the server keeps about 1 s of player positions and hitboxes (`sv_maxunlag` defaults to 1);
  - it rewinds targets to what the shooter saw, adjusted for the client's interpolation;
  - it then tests the hit [S18].
  - I only saw this page through search snippets; the page itself returned 403.
- **Roblox community versions:**
  - snapshot history every server tick for about 1 s, rewound by the tick or time the client sends [S15];
  - SecureCast estimates Roblox's character interpolation buffer at **80 to 100 ms**, and notes that `GetServerTimeNow()` only covers one-way latency [S16];
  - others report that the buffer varies with distance, ping and physics settings [S17];
  - Valve allows up to 1 s of rewind [S18]. We cap it at 0.25 s so that "hit behind cover" moments stay rare and high-ping players have to lead their targets. That cap is my design choice, not a sourced number.
- **Tools:**
  - `Player:GetNetworkPing()` gives the round-trip ping [S25];
  - the "Rewind" framework claims melee support, but I did not verify it [S42].
- **Conclusion.** Build a small `HitHistory` (§4.5). Rewind = client time − interpolation estimate (0.10 s, tunable), capped at 0.25 s.

### 2.3 Server Authority (status as of late 2026)

- **What it is.** Full release on 2026-07-09 [S8][S10]. The server owns the simulation, clients predict, and mispredictions roll back and resimulate [S7].
- **Requirements** [S7]:
  - `Workspace.AuthorityMode = Server`, which also turns on `NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`, Deferred `SignalBehavior`, `UseFixedSimulation` and `StreamingEnabled`;
  - gameplay logic moved into `RunService:BindToSimulation`;
  - the time source must be `time()`;
  - inputs must come through the Input Action System;
  - `AnimationTrack`s can't be cached, because rollback can replace them [S9].
- **Limits** [S8]: 8 animation tracks per Animator; 64 attributes per instance; remotes are not on the shared timeline.
- **A reported risk** [S2], unconfirmed: `AnimationConstraint.Transform` not taking effect with `UseFixedSimulation = true`. That would break our procedural poses.
- **Verdict for us: not now.**
  - Our 2,000-line client momentum movement (`PlatformStand` mantles and climbs, `VectorForce` gravity cancelling) and the `Transform` pose layer would all need porting.
  - Combat would still need our own rewind.
  - So: write combat as pure, time-stamped functions (`CombatMath`, `SwingArc`, `Ballistics`) and revisit when Roblox ships rewind.

### 2.4 Swing weight and commitment

- **Phases.** Mordhau splits every attack into **wind-up → release (active, can deal damage) → recovery**.
  - Being hit during an enemy's wind-up "flinches" (cancels) it.
  - Feints are allowed until about the last 50 ms of the wind-up.
  - A patch cut the parry window from 400 to 350 ms.

  These come from wiki pages and patch notes seen in search snippets [S32]; I couldn't open the pages (HTTP 402).
- **Chivalry 2:**
  - overhead, stab, and left and right slashes;
  - you can drag or accelerate a swing by turning;
  - stabs are the fastest attacks;
  - holding block drains stamina [S33].
- **DayZ (survival):** light and heavy attacks. A heavy attack staggers and costs more stamina, and blocking works against light attacks but not heavy ones [S34].
- **Takeaway.** Survival-arena realism needs readable wind-ups, a short active window and a real recovery, with stamina and movement penalties. Human visual reaction time is about 200 to 250 ms (general knowledge, not sourced), so medium and heavy wind-ups should be longer than ping plus interpolation plus reaction time to be readable.

### 2.5 Blocking, parrying and feints: do they fit?

- **Deep systems** (directional parries, ripostes, feints, morphs, chambers, as in Mordhau and Chivalry 2) reward one-on-one mastery [S32][S33]. They are:
  - latency-sensitive: parry windows of about 350 ms, against telegraphs that arrive about 150 ms late at 100 ms ping plus interpolation;
  - hard on touch and gamepad;
  - a poor fit for a 24-player free-for-all where long duels get third-partied.
- **Simple guard** (DayZ-style [S34]): hold to guard, which drains stamina; heavy and blunt hits break it. Readable and cheap to build.
- **Recommendation:** at most a simple guard with a short perfect-block window. No feints in v1. Options are in §3.6 and the decision is in §7.

### 2.6 Hit reactions

- **Procedural layering on AJU rigs.**
  - Multiply into `AnimationConstraint.Transform` during `RunService.PreSimulation`, and skip the frame when `animator.EvaluationThrottled` is true [S2][S3].
  - Don't write the `RigAttachment.CFrame` values.
  - Don't replicate procedural poses from the server. Evaluate them on each client from small data sent by attribute or `UnreliableRemoteEvent` [S2][S3]. Payloads over 1000 bytes are dropped [S24].
- **Physical flinches.** Setting `IsKinematic = false` lets a joint follow its animation with limited force, through `AngularStrength`, `LinearStrength` (normalized natural frequency, f/60), damping, `MaxForce` and `MaxTorque` [S3].
  - Roblox staff advise keeping the Root (and often the Waist) kinematic to avoid wobble [S2].
  - Mixing kinematic and physical joints can replicate choppily to other viewers, a known issue that is being worked on [S1][S4].
  - So: use **procedural** flinches for other players, and save physical ones for local experiments.
- **IK.** `IKControl` has `Weight` and `SmoothTime` for blending [S27]. The AJU's ball-socket limits can restrict IK chains; the workaround is to disable `LimitsEnabled` on the affected joints [S6]. That only matters if we ever add IK reactions.
- **Knockback ownership.** For a part that a client owns automatically, `ApplyImpulse` can be called from client or server, but a client call on a server-owned part has no effect [S22]. Our characters are owned by their players through an explicit `SetNetworkOwner(player)`, so knockback should be applied by the **victim's client** (`MovementController.addImpulse`). The server only applies impulses to server-owned dummies and corpses.

### 2.7 Ragdolls with the Avatar Joint Upgrade

- **Status.**
  - Live since 2026-01-26 [S1].
  - Phase 2 (2026-05-27) makes it the default, and Phase 3 (a forced migration) is targeted for the end of 2026 [S2].
  - R6 is unaffected.
  - NPC models are not converted [S1].
- **How to ragdoll.**
  - AJU characters have `BallSocketConstraint`s. Disabling or weakening the `AnimationConstraint`s makes them tumble.
  - Turning off `CharacterBreakJointsOnDeath` gives an immediate ragdoll on death [S1].
  - A 2026 community module toggles `AnimationConstraint.Enabled`, adds a Root→LowerTorso weld while ragdolled, swaps the Head and root `CanCollide`, and changes the Humanoid state to `Physics` and later `GettingUp`. It disables the `FallingDown` and `Ragdoll` states on the client [S5].
  - `Physics` is a manual state; `GettingUp` follows `FallingDown` or `Ragdoll`; `Ragdoll` itself is deprecated [S20].
- **Known pain points**, all community reports with no staff fix [S4]:
  - Humanoid state changes reset limb `CanCollide`;
  - ragdolling on the server can behave differently from the client;
  - removing one limb's constraints affected another limb;
  - characters stumble after a ragdoll;
  - replication can be choppy.
- **Network ownership.** The server can force ownership with `SetNetworkOwner(nil)`. The docs advise doing this sparingly, because it can make physics interactions feel jittery for clients [S21].
- **Conclusion.**
  - **Death:** a server-owned corpse is reliable, and it looks the same for every viewer.
  - **Knockdowns of living players:** the victim's client has to drive them, because the client owns the character, so they are fragile and exploitable. Make them an optional later phase.

### 2.8 Projectile physics: real-world anchors

- **Units:**
  - 1 stud = 28 cm and 1 m/s = 3.57 studs/s;
  - real gravity is **35 studs/s²**, and Roblox's default is 196.2 studs/s² (5.6 times real) [S19].
- **Recurve bow.**
  - A 40 to 50 lb recurve with a 350 to 450 grain arrow shoots about **170 to 200 fps (52 to 61 m/s, 185 to 218 studs/s)**.
  - Each pound of draw weight adds about 1.9 to 2.4 fps.
  - These are mostly retailer and forum figures, so treat them as estimates [S38].
  - Today's maximum of 240 studs/s (67 m/s) is a little hot but plausible.
- **Arrow drag.**
  - Measured arrow drag coefficients are about **1.5 (laminar) to 2.6 (turbulent, with point and vanes)** [S39].
  - With Cd ≈ 2, a 25 g arrow and 7.5 mm shaft, k = ½ρC_dA/m ≈ 0.0021 per metre ≈ **0.0006 per stud**. That means about 11% energy loss over 100 studs.
- **Spears.**
  - Club javelin athletes hit targets at **15 to 20 m** with 760 to 800 g wooden spear replicas [S40].
  - I could not extract the measured velocities from the paper. I assume **20 to 23 m/s (71 to 82 studs/s)** for a skilled throw; this is unconfirmed.
- **Throwing knives.**
  - An amateur high-speed measurement found a "normal" throw at about **50 km/h (14 m/s, 50 studs/s)** [S41].
  - Expert claims of about 100 mph exist, but the methods are unclear [S41].
  - I propose 85 studs/s (24 m/s) as a fast, playable compromise.

### 2.9 Camera and viewmodel feedback

- **Hit-stop:**
  - short frozen frames sell weight, and longer stops mean stronger hits;
  - shaking the struck body sells it more, and in Smash the attacker vibrates too [S35][S36].
  - In first-person multiplayer, freeze only the **local viewmodel**, never the world.
- **Trauma-based shake:** shake is driven by a trauma value from 0 to 1 that decays over time [S37]. Our `CameraController` already works this way, with trauma plus a kick spring.
- **Haptics:** `HapticService` and the waveform-based `HapticEffect` can drive gamepad and phone rumble [S28].

### 2.10 Content rules for violence and blood

- **Label tiers** [S29]:
  - **Minimal:** occasional mild violence;
  - **Mild:** repeated mild violence or heavy *unrealistic* blood;
  - **Moderate:** moderate violence or *light realistic* blood;
  - **Restricted:** strong violence or heavy realistic blood, **18+ age-verified only**.
- **Who can play** [S29]:
  - Minimal and Mild games are eligible for Roblox Kids (ages 5 to 8) and Roblox Select (ages 9 to 15);
  - Moderate games are eligible for Roblox Select and standard Roblox (16+).
- **Violence is judged by its consequence** [S29]:
  - "Bodies disappearing the moment their health reaches zero" is Mild.
  - "Non-graphic, realistic-looking depictions of violence and/or death" is Moderate.
  - Any single moment of realistic consequence moves the game to Moderate or above.
  - So **ragdoll corpses mean Moderate.**
- **Blood** [S29]:
  - realistic spatter "from a distance" counts as Light;
  - pools, gushing or *up-close* spatter counts as **Heavy**, which is 18+.
  - First-person melee is always up close, so any realistic blood risks Heavy.
- **Always banned** [S29][S30]: realistic or extreme gore, torture and dismemberment outside Restricted. Uploaded assets with realistic or excessive violence or blood can be moderated whatever the label.
- **Realistic modern firearms** are disallowed outside in-game items [S30]. Not relevant to us.
- **Recommendation:** no blood. Show impact through motion, sound, camera, body reactions, cloth and dust puffs, and status icons.

### 2.11 Anti-exploit guidance

- **Roblox's security guide** [S23]:
  - never trust the client;
  - the server is the source of truth;
  - threat-model every feature: arbitrary arguments, any firing rate, 1,000+ calls per second.

  Exploiters control their own character's physics and can fire remotes with anything.
- **Character-part deletion.** `Workspace.RejectCharacterDeletions` stops clients deleting character parts on the server, and `Default` currently means `Enabled` [S26]. Keep it that way, or exploiters could delete their own head to dodge headshots. My script couldn't read the property, so please check it in Properties.
- **Studio network simulation** (2026-06-02) adds latency, jitter and up to 0.5% packet loss per client, scriptable through `NetworkSettings` [S31]. It is needed for the test plan.

---

## 3. Design proposal

### 3.1 Feel goals

1. **Readable.** You can see an attack coming: third-person wind-up poses, plus an audible wind-up for heavy attacks.
2. **Committed.** Once released, a swing plays out: wind-up, then active, then recovery. Misses cost stamina and time, and attacking slows you.
3. **Weighty.**
   - Mass sets timing, reach, knockback and stagger.
   - Hits connect with hit-stop and blade drag.
   - Slashes catch on trees and walls; stabs don't.
4. **Grounded.** What you see is what you hit. Reach comes from the real weapon models.
5. **Lethal but fair.**
   - Light hits only: kills in 1.8 to 2.8 s.
   - With head hits and heavies: 1.0 to 1.6 s.
   - The head is dangerous, armour matters on the torso, and limbs are forgiving.
6. **Non-graphic.** Impact without gore.
7. **Every device.** No extra buttons: hold for heavy, and the attack direction comes from your look motion.
8. **Latency-honest.** Consistent at 150 ms; rewind is capped at 250 ms.

### 3.2 Core rules

- **Light and heavy.**
  - Tap Attack for a light attack.
  - Hold Attack for at least 0.22 s to wind up a heavy; it releases when you let go, or automatically at full charge.
  - This replaces "hold to keep swinging", so every swing is a deliberate press. You can still buffer a press inside the last 0.2 s of recovery.
- **Directions:**
  - Left, Right, Overhead, Stab;
  - picked at the start of the wind-up from the camera motion of the last 120 ms (dominant horizontal → slash that way; downward → overhead; almost no motion → alternate left and right, or stab when you're moving forward);
  - each weapon restricts its own set (the spear only stabs, the mace has no stab).
  - What each direction changes:

    | Direction | Damage | Wind-up | Arc and reach | Other |
    |---|---|---|---|---|
    | Overhead | +10% | +60 ms | — | — |
    | Stab | −10% | — | narrow, +0.4 reach | never catches on walls |
    | Slash | — | — | wide | can hit 2 targets (where allowed); catches on trees |
- **Interrupts ("flinch").**
  - Taking at least 15 damage after armour, or any heavy hit, during your own wind-up cancels it: the stamina is spent, and you get a 150 ms lockout.
  - Hits during the active window don't cancel, so trades can happen.
- **Stagger.** Heavy hits set the victim's move speed to ×0.5 for 0.35 s (0.6 s for the mace) and lock out attacks for 0.25 s.
- **Movement while attacking.**

  | Phase | Move speed |
  |---|---|
  | Light wind-up | ×0.85 |
  | Heavy wind-up | ×0.70 |
  | Active | ×0.80 |

  - No sprinting during a heavy attack (`stopSprint` is already used for draws and throws).
  - Turn cap: a hit only counts if your look direction stayed within 540°/s (light) or 360°/s (heavy) of where it was at the start. This stops 360° spin-swings without locking the camera.
- **Stamina.** The pool is shared with sprinting (1.0, regenerates 0.2/s after 1.0 s).
  - Attack costs are in §3.3.
  - A whiff costs +0.03, and a clang +0.04.
  - Below the cost of an attack:
    - a light attack is "exhausted": wind-up ×1.35, damage ×0.75;
    - heavy attacks are refused.
- **Survival link.**
  - Hunger or thirst below 15 makes you "Weak": melee damage ×0.85, wind-up ×1.1, stamina regen ×0.75.
  - While bleeding, health doesn't regenerate.

### 3.3 Melee numbers (v1 starting values, all in `Config` / `CombatDefs`)

| Weapon | Type | Directions | Light: wind-up / active / recovery (ms) | Heavy: wind-up / active / recovery (ms) | Damage L / H | Stamina L / H | Knockback L / H (studs/s) | Reach, eye→tip (studs) | Arc | Targets | Special |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Fists | Blunt | L/R hook, jab (stab) | 170 / 90 / 210 | 400 / 100 / 280 | 7 / 15 | .04 / .08 | 2 / 6 | 3.0 | 70° | 1 | Heavy staggers 0.25 s |
| Hunting knife | Cut / pierce | L/R, stab | 190 / 100 / 230 | 380 / 100 / 300 | 20 / 32 | .05 / .09 | 1 / 2 | 3.4 | 80° | 1 | Bleeds; heavy stab head ×2.2 |
| Machete | Cut | L/R, overhead | 280 / 130 / 320 | 560 / 150 / 400 | 30 / 46 | .08 / .14 | 2 / 4 | 4.3 | 110° | 2 (2nd ×0.6) | Bleeds; catches on trees |
| Hatchet | Chop | L/R diagonal, overhead | 310 / 110 / 360 | 600 / 130 / 440 | 34 / 52 | .09 / .15 | 3 / 6 | 3.9 | 90° | 1 | Armour less effective (§3.5); heavy staggers 0.35 s |
| Arena sword | Cut / pierce | L/R, overhead, stab | 280 / 140 / 300 | 560 / 160 / 380 | 34 / 52 | .08 / .14 | 2 / 4 | 5.2 (stab 5.6) | 120° | 2 (2nd ×0.6) | Bleeds; best all-rounder |
| Spear | Pierce | Stab only | 300 / 110 / 380 | 600 / 130 / 480 | 28 / 46 | .08 / .14 | 4 / 8 | 7.0 (heavy lunge 7.8) | Line ±6° | 1 | Keeps distance; never catches |
| Mace | Blunt | L/R diagonal, overhead | 450 / 150 / 480 | 800 / 170 / 600 | 40 / 64 | .13 / .22 | 5 / 11 | 4.6 | 100° | 1 | Armour barely helps; heavy staggers 0.6 s; knockdown candidate |

**How these compare with today:**

- **Reach** = arm extension (about 2.0 studs for the world-scale viewmodel arms) + grip→Tip from the manifest + about 0.3 studs of lean.
  - The server accepts the blade's sweep radius (0.25) + 0.75 tolerance on top.
  - So a knife's effective reach is about 4.4 studs, against 11.4 today.
- **Kill times** (100 HP, light hits, torso, no armour):

  | Weapon | Hits | Time | Today |
  |---|---|---|---|
  | Knife | 5 | ≈2.4 s | 1.9 s |
  | Sword | 3 | ≈1.9 s | 1.65 s |
  | Hatchet | 3 | ≈2.0 s | — |
  | Mace | 3 | ≈2.8 s | 2.45 s |
  | Spear | 4 | ≈2.8 s, at twice the reach of most weapons | — |

  - Head hits shorten them: a sword light to the head is 61, a mace heavy to the head is 115.
  - The slightly longer kill times are offset by interrupts and stagger.

### 3.4 Ranged and thrown numbers

| Weapon | Ready / wind-up | Release speed (studs/s) | Gravity | Drag k (per stud) | Damage | Head ×, limb × | Recovery | Notes |
|---|---|---|---|---|---|---|---|---|
| Recurve bow | Draw 1.0 s to full (minimum 0.25) | 115 → 210 (`charge^0.8`; ≈ 32 → 59 m/s) | 35 | 0.0006 | 55 × KE ratio (minimum 12) | ×2.0 / ×0.7 | 0.35 s | Fatigue after 2.5 s at full draw (exists); `RMB` zoom (exists) |
| Throwing knife | 250 ms | 85 | 35 | 0.002 | 26 × KE ratio | ×1.7 / ×0.7 | 450 ms | Point-first in v1 (no random bounces) |
| Spear (thrown) | Raise ≥ 450 ms | 75 | 35 | 0.0002 | 65 × KE ratio (minimum 30) | ×1.6 / ×0.75 | 700 ms | Leaves your hand; sticks in wood or ground |

- **KE ratio** = (impact speed / the weapon's reference full speed)², clamped to [0.3, 1.3]. Long shots hit softer, and falling projectiles gain a little. Arrows don't knock people back (no Hollywood flying). A thrown spear adds 6 studs/s of knockback.
- **Drop at full draw** (flat launch; my integration, the same integrator proposed in §4.8):

| Distance | Bow today (240, g55, no drag) | **Bow proposed** (210, g35, k .0006) | Knife proposed (85, g35) | Spear proposed (75, g35) |
|---|---|---|---|---|
| 25 studs (7 m) | 0.3 drop, 0.10 s | 0.3 drop, 0.12 s, KE 0.97 | 1.6 drop, aim ↑3.6° | 2.0 drop, aim ↑4.6° |
| 50 studs (14 m) | 1.2, 0.21 s | 1.0, 0.25 s, KE 0.94 | 6.5, ↑7.4° | 7.8, ↑8.9° |
| 100 studs (28 m) | 4.8, 0.42 s | 4.1, 0.49 s, KE 0.89 | — | 31.7, ↑17.6° |
| 200 studs (56 m) | 19.1, 0.83 s | 17.2, 1.01 s, KE 0.81 | — | — |

**What this means in play:**

- The bow keeps today's flat feel at short range. Long shots become the realistic arcing skill.
- Knives and spears become short-range weapons:
  - the knife works out to about 25 to 40 studs;
  - the spear out to about 20 m (70 studs), matching [S40].
- This is a big change from today's near-laser throws (§7, question 7). The fallback "assisted" values are 110 studs/s with gravity 45.

### 3.5 Hit zones, armour and wounds

**Zones** use R15 body parts only; accessory handles are excluded from hit queries:

| Part | Melee | Arrow | Thrown |
|---|---|---|---|
| Head | ×1.8 | ×2.0 | ×1.6–1.7 |
| UpperTorso | ×1.0 | ×1.0 | ×1.0 |
| LowerTorso | ×0.95 | ×0.95 | ×0.95 |
| Upper and lower arms | ×0.7 | ×0.7 | ×0.7 |
| Hands | ×0.55 | ×0.55 | ×0.55 |
| Upper and lower legs | ×0.75 | ×0.75 | ×0.75 |
| Feet | ×0.55 | ×0.55 | ×0.55 |

**Armour** covers the torso only (UpperTorso and LowerTorso). The multiplier depends on the damage type:

| Vest | Cut (knife, machete, sword) | Chop (hatchet) | Blunt (mace, fists) | Pierce (arrow, spear, throwing knife) |
|---|---|---|---|---|
| Leather vest | 0.70 | 0.80 | 0.90 | 0.80 |
| Padded armour (gambeson + plate) | 0.50 | 0.60 | 0.75 | 0.60 |

Head and limb hits are never reduced. That is more impactful than today's flat 0.85 / 0.72, but local to the torso.

**Wounds** (non-graphic status effects, shown as HUD icons plus a neutral dark or desaturated vignette):

- **Bleeding.**
  - Triggered by a cut or pierce hit dealing at least 18 after armour.
  - 1.0 HP/s for 8 s; stacks up to 3 times.
  - A bandage stops all stacks; herbs stop one.
  - No regeneration while bleeding.
- **Limp.** A leg hit gives move speed ×0.85 for 4 s (refreshes).
- **Weakened arm.** An arm hit gives bow draw time ×1.2 and melee wind-up ×1.1 for 4 s.
- **Dazed.** A head hit of at least 30: 1.0 s of muffled audio and a light blur; no camera loss.

### 3.6 Defence options (your choice; see §7)

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **A. None** | Positioning, reach, timing, dodging | Simplest; works at any latency; best for a 24-player FFA | Less melee depth; trading hits decides duels |
| **B. Guard (recommended)** | Hold `Aim` (RMB / L2 / touch "GUARD") with a melee weapon or fists. The guard rises in 120 ms; move ×0.6; no stamina regen | Readable, cheap, works on every device | Needs a lag-tolerant check and new third-person poses |
| **C. Full directional parry, riposte and feint** | Mordhau / Chivalry style | Deep one-on-one skill | Latency-heavy, hard on touch and gamepad, long duels get third-partied [S32][S33] |

**How the guard (B) works:**

- It blocks frontal melee within ±70°.
- Damage taken while guarding:

  | Attacker's weapon | Damage taken |
  |---|---|
  | Sword or machete | ×0.15 |
  | Knife or hatchet | ×0.25 |
  | Fists | ×0.35 |

- Each blocked hit costs stamina: `0.04 + 0.0035 × damage before blocking`.
- A **mace heavy breaks the guard** and staggers for 0.5 s. A guard at 0 stamina breaks too.
- **Perfect block:** a guard raised within 200 ms before impact costs nothing and staggers the attacker for 0.4 s.
- You can't guard against arrows or thrown weapons. The spear can't guard; its `Aim` is the throw stance.
- **No feints in v1.** You can cancel during the first 50% of a wind-up for 0.05 stamina (a light feint).

### 3.7 Death, ragdolls and knockdowns

**Death (recommended):** an AJU physics ragdoll as a **server-owned corpse**:

- It persists until the round ends (cap 24).
- It collides with the world but not with living players.
- The killing blow pushes it:

  | Killing blow | Push (studs/s, at the hit part) |
  |---|---|
  | Melee | 8–20, by weapon weight |
  | Arrow | 2–4 |
  | Thrown spear | 10 |

- It settles, then is anchored to save physics.
- Optionally the loot stays **on the body** and you search it with a prompt, instead of scattering it (today's `dropAll`).
- Either way this means the **Moderate** label (§2.10).

**Knockdowns (optional, a later phase):**

- Example triggers: a non-lethal mace heavy to the head of at least 60, or a heavy hit while at 0 stamina.
- Effect: a 1.6 s ragdoll, then a 0.8 s get-up.
- These are fragile under client ownership (§2.7). The server enforces an action lockout during them.

### 3.8 Feedback spec (no gore)

| Event | Attacker (first person) | Victim | Observers (third person) |
|---|---|---|---|
| Wind-up | Viewmodel pull-back; heavy charge: −1° FOV and creaking grip | — | Wind-up pose (arm back by direction); heavy attacks have a whoosh pre-cue |
| Flesh hit | Hit-stop 45 / 65 / 90 ms (light / medium / heavy weight), then blade drag at 30% speed for 60 ms; camera kick; cut or thud sound by armour; marker coloured by zone; haptic pulse | Camera kick away; directional arc (exists); 120 ms desaturation; grunt; stagger or interrupt | Procedural flinch (waist, neck or limb spring); 3D impact sound; cloth or dust puff tinted by clothing or armour |
| Armour hit | Leather slap or quilted thump; padded plate: a small spark and clank | Muted impact | Same |
| World clang (slash hits a tree or wall first) | Bounce-back recoil, sparks or splinters, +0.04 stamina, +200 ms recovery | — | Clang sound |
| Guard block | Recoil and a blocked sound; a perfect block makes the attacker stagger | Guard shove; stamina flash | Guard pose recoil |
| Kill | Hit-stop ×1.3; `HitMarkerKill` (exists) | Spectate flow (exists) | Ragdoll with impulse; cannon (exists) |
| Arrow impact | Arrow thrum wobble (0.4 s) when it sticks; splinters on stone | Kick, plus the arrow sticks on their body | Arrow stays stuck in the body or tree |

---

## 4. Technical design

### 4.1 Module map

**New modules (combat-owned unless noted):**

- `ReplicatedStorage.Shared.CombatDefs`: per-weapon melee and ranged stats, arcs, directions and damage types. `ItemDefs` stays owned by Inventory, and its old combat fields are kept as fallbacks during the migration.
- `Shared.CombatMath` (pure): zones, armour, damage type, KE scaling, wounds, stamina costs.
- `Shared.SwingArc` (pure): canonical arc sampling, the input→direction rule, point layout on the blade.
- `Shared.Ballistics` (pure): one integrator with gravity and drag, used by both server and client.
- `ServerScriptService.Server.Services.HitHistory`: the ring buffer of character poses.
- `…Services.RagdollService`: corpses (Phase 5), knockdowns (optional).
- `…Services.CombatService.Melee` and `.Validate`: the swing state machine and hit validation (child modules).

**Changed scripts** are listed per phase in §5.

### 4.2 Swing timeline and messages

```
Attacker client                              Server                                   Other clients
press/hold Attack
 └─ MeleeStart(swingId, dir, heavy, look, tC) ─▶ validate (phase, weapon, cooldown, stamina mirror,
    (viewmodel wind-up starts now)                facing); record swing {t0 = tC, dir, look0};
                                                  spend server stamina
                                                  ─ CombatAction{WindUp, userId, dir, heavy, t} ─▶ third-person wind-up
t0 + windup: blade sweep every frame (§4.4)                                                       pose, timed by t
 └─ first contact:
    MeleeHit(swingId, target, part, hitPos,  ─▶ rewind target to tC − interp (§4.5);
             eye, look, tC)                       validate timing / reach / arc / LOS / once-per-target;
    local FX now (sound, hit-stop, kick)          CombatMath damage → PlayerService.damage
                         ◀── HitConfirm{damage, zone, killed, blocked}
                                                  ── DamageTaken{amount, from, zone, knockback,
                                                       stagger, interrupt, bleed} ─▶ victim
                                                  ── CombatHit{victim, part, dir, weight} ─▶ nearby: flinch + sound
world contact first (slash): clang FX ──MeleeHit(..., world = true)─▶ swing ends; recovery penalty
recovery: the server refuses a new MeleeStart until t0 + windup + active + recovery − jitter
```

- **Ids and clock.** `swingId` is a counter per player. `tC = workspace:GetServerTimeNow()` on the client.
- **Pacing.** The server enforces the timeline. A `MeleeHit` outside `[t0 + windup − 0.08, t0 + windup + active + 0.08]` is refused.
- **Interrupts.** The server cancels the victim's pending swing if the hit is processed before that swing's active start, measured in server time. The victim's client receives `interrupt = true` and cancels too.
- **Wind-up cancel** (feint-lite, if adopted): `MeleeCancel(swingId)` is accepted during the first 50% of the wind-up.

### 4.3 Canonical swing arcs (one source for the viewmodel and the hit detection)

```lua
-- Shared.CombatDefs (sketch)
sword = {
	damageType = "Cut", tipFromGrip = 3.05, bladeFromGrip = 0.9,  -- from Items.manifest "Tip"
	armReach = 2.0, sweepRadius = 0.25, maxTargets = 2, secondTargetScale = 0.6,
	light = { windup = 0.28, active = 0.14, recovery = 0.30, damage = 34, stamina = 0.08, knockback = 2 },
	heavy = { windup = 0.56, active = 0.16, recovery = 0.38, damage = 52, stamina = 0.14, knockback = 4, stagger = 0.35 },
	directions = { "Left", "Right", "Overhead", "Stab" },
	arcs = {   -- camera-space; angles in degrees around the pivot, plane tilt for diagonals
		Left = { from = 65, to = -65, tilt = 12 }, Right = { from = -65, to = 65, tilt = -12 },
		Overhead = { from = 70, to = -40, plane = "Vertical" }, Stab = { thrust = 1.1 },
	},
}
```

- `SwingArc.sample(def, dir, t)` returns, at swing time `t`, camera-space positions for **3 points** on the blade: the guard, the middle and the Tip. It rotates the blade about a shoulder pivot by the eased angle.
- `ViewmodelController.Poses.swing` is rewritten to follow `SwingArc` for the active window, with springs added only as cosmetic offsets on top. So the hit volume and the visible blade agree.
- The arcs are data, so the designer can tune them in `CombatDefs`.

### 4.4 Client blade sweep (`CombatController`)

During the active window, every render frame does the following:

1. Sub-step so that no blade point moves more than about 8° (or 0.6 studs) per step, and points never jump.
2. For each blade point: `Spherecast(prevWorld, sweepRadius, curWorld − prevWorld)`.
   - The include-list is **R15 body parts only** of other characters and dummies, cached per character: accessories excluded.
   - A separate world `Raycast` uses the existing world params (`RespectCanCollide`, foliage skipped).
3. On the first step, `GetPartBoundsInRadius` catches targets the blade starts inside, because spherecasts miss those [S11].
4. Order hits along the sweep:
   - world before character → **clang**: the swing stops; send `MeleeHit{world = true, material}`;
   - character first → hit FX now; send `MeleeHit`;
   - keep sweeping until `maxTargets` is reached.
5. Assists:

   | Device | Extra sweep radius |
   |---|---|
   | Touch | +0.15 studs |
   | Gamepad | +0.1 studs |

### 4.5 Server validation with lag compensation

**`HitHistory`:**

- Every Heartbeat, it records `{ t = GetServerTimeNow(), rootCFrame }` per tracked model (players and dummies): 64 entries, about 1.07 s.
- At 10 Hz, it records each body part's CFrame relative to the root (15 parts), which covers crouch, slide and climb poses.
- `sample(model, partName, t)` interpolates between the nearest entries.
- Memory is tiny: 24 × 64 root CFrames plus 24 × 11 × 15 part CFrames.

**Checks on `MeleeHit`** (all thresholds live in `Config.Combat`):

1. Rate limit (8/s), types, finite values; the swing exists, is in its active window and isn't finished; the target hasn't been hit yet by this swing.
2. Time:
   - `tC` must be no later than `now + 0.05`;
   - rewind time `tView = clamp(tC − InterpDelay(0.10), now − MaxRewind(0.25), now)`.
3. Attacker eye: `|eye − HitHistory(attacker head, tC)| ≤ 2.5 + 0.1 × speed`. This replaces today's ≥ 9-stud allowance.
4. Target: `hitPos` must lie inside the rewound part's box, grown by `PartTolerance (0.6)`.
5. Reach and arc:
   - `|hitPos − eye| ≤ reach + sweepRadius + ReachTolerance (0.75)`;
   - the angle of `hitPos` in the swing plane must lie within the arc's range at the claimed time, ±`ArcTolerance (20°)`;
   - for a stab, it must lie within the thrust line ±8°.
6. Turn cap: `angle(look, look0) ≤ TurnCap × (tC − t0) + 20°`.
7. Line of sight: a world raycast `eye → hitPos` must be clear (same world params as today).
8. Apply: `CombatMath.resolve(attackerDef, dir, heavy, partName, victimArmor, victimGuard)` produces `{ damage, zone, bleed, stagger, knockback, interrupt, blocked }`. Then call `CombatService.applyHit`, whose API is unchanged so `ProjectileService` keeps working.

**Guard check** (if adopted): the hit is blocked when the victim's guard was up at any time in `[tView − 0.05, now]` and the attack is within the ±70° front cone of the victim's facing at `tView`. This favours the defender inside the rewind window. A perfect block uses the guard's raise time.

**Players with ping over 250 ms** are compensated only up to the cap, so they must lead their targets. Capped compensation works the same way in Source (`sv_maxunlag`) [S18].

**Note on "client-proposed" hits:** the client never sends damage; it only claims contact. An exploiter's best case is a "perfect" hit inside the tolerances, which is the Roblox-recommended trade-off [S13][S23].

### 4.6 The damage pipeline

```
base       = def[light|heavy].damage × dirMod (overhead 1.1, stab 0.9) × exhaustedScale × weakScale
zone       = CombatMath.zone(partName)                       -- head / torso / arm / hand / leg / foot
armor      = zone is torso ? Armor[vest][damageType] : 1
guard      = blocked ? GuardScale[weaponClass] : 1
damage     = round(base × ZoneMult[zone][attackKind] × armor × guard)
wounds     = bleed if (Cut or Pierce) and damage ≥ 18; limp if leg; weak arm if arm; dazed if head and damage ≥ 30
interrupt  = damage ≥ 15 or heavy;  stagger = heavy ? def.heavy.stagger : 0
knockback  = horizontal(dir) × def.knockback (+ 1.5 studs/s up for heavy blunt hits)
```

- Wounds live in **`PlayerService`** as a small status table: bleed ticks go through `damage(cause = "Bleed")`, and the Survival regen check respects them.
- Bandages and herbs clear bleeding through **`InventoryService.applyUse`**.
- A new cause, `"Bleed"`, keeps kill credit through the existing `KillCreditWindow`.

### 4.7 Reactions in practice

- **The victim's own client** reacts to `DamageTaken`:
  - `MovementController.applyStagger(duration, speedScale)` (new);
  - `MovementController.addImpulse(knockback)` (exists; it's client-owned, see §2.6);
  - `CombatController` cancels the current wind-up when `interrupt` is set;
  - `ViewmodelController` flinches;
  - `CameraController` kicks (exists).
- **Observers** react to `CombatHit` (an `UnreliableRemoteEvent`, sent only to clients within 200 studs, under 100 bytes).
  - `CharacterVisuals` adds a **reaction spring** per joint chain:

    | Part hit | Joints that react |
    |---|---|
    | Torso | Waist, Neck |
    | Head | Neck |
    | Arm | Shoulder, Elbow |
    | Leg | Hip, Knee, plus a root dip |

  - The impulse axis is `up × localDir`, scaled by weight: Light 0.5, Medium 0.8, Heavy 1.2, with peaks of about 8° to 22°.
  - The spring runs at about 6 Hz with ζ ≈ 0.45 and settles in about 0.35 s. It is multiplied into `Transform` at `PreSimulation` and skipped when `EvaluationThrottled` [S2][S3].
- **Third-person attack poses** come from `CombatAction` (WindUp, Strike, Recover, Cancel, Guard, Draw, Release, Throw) in the same layer.
  - `t` is in server time. Viewers start the pose when their display time (`GetServerTimeNow() − interp`) reaches `t`, so the pose lines up with the interpolated body.
  - Authored `AnimationTrack`s can replace these later.
- **Server-side sanity.** `MovementService` gets a short tolerance window after knockback, so a legit shove doesn't trip the speed warning. Attack requests from a staggered player are refused until the stagger ends.

### 4.8 Projectiles

- **One integrator in `Shared.Ballistics`**, used by server and client:

  ```
  a = g − k·|v|·v;   v' = v + a·dt;   x' = x + (v + v')/2·dt
  ```

  - Sub-steps: arrows ≤ 1/60 s, others ≤ 1/30 s.
  - Per-item parameters `g`, `k` and `vRef` come from `CombatDefs`.
- **Damage** = `base × clamp((|v_impact| / vRef)², 0.3, 1.3) × zone × armour`.
  - Characters are queried by **body parts only** (no accessory headshots).
  - Stuck visuals on characters stay as today.
- **Surface response** (`RaycastResult.Material`; I am assuming terrain `MaterialVariant`s report their base material, which needs checking):

| Surface class | Arrow | Throwing knife | Spear |
|---|---|---|---|
| Wood, WoodPlanks, Grass, LeafyGrass, Ground, Mud, Sand, Snow, Fabric | **Sticks** (embed 0.3–0.8 by speed); 60% can be pulled out | Sticks point-first | Sticks (embed 1–1.5); always retrievable |
| Rock, Slate, Basalt, Cobblestone, Brick, Concrete, other stone | Grazing (>55° from the normal): **glances** at 35% speed and falls; otherwise **breaks** 60% / drops 40% | Bounces, drops | Bounces, drops |
| Metal, CorrodedMetal, DiamondPlate | Glances or bounces with sparks; breaks 40% | Bounces | Bounces |
| Water | Drag ×40, sinks: lost | Sinks | Sinks (or floats: designer's call) |
| Non-collidable foliage | Passes through (exists) | Passes | Passes |

- **Stuck pickups.** On a stick, the server creates an **anchored pickup at the impact point** using the hit's exact position and orientation: `LootService.spawnStuckItem(itemId, cframe, part?)`, which follows moving parts. Today's drop to the ground goes away.
  - Players pull arrows out of trees with a short prompt.
  - Stuck arrows also tell a story: they mark where a fight happened.
  - They expire after 60 s or at the round's end. The client visual matches by `id`, so nothing pops.
- **Spawn compensation.** When firing, the server fast-forwards by `min(now − tC, 0.15)`. Those first segments are tested against `HitHistory` boxes at `tC − interp + τ` (a ray-versus-box test in maths), then the projectile continues live, as SecureCast does [S16]. `ProjectileFired.t` carries `tC`, so remote visuals stay consistent.
- **Deterministic spread.**
  - The server gives each player a `SpreadSeed` per round.
  - Client and server both draw a shot's spread from `Random.new(seed + shotIndex)`.
  - The server applies the spread itself, scaled by the larger of its own and the client's movement and air state.
  - The client predicts the same offset, so prediction stays exact, and no-spread exploits stop working.
  - Repeating a `shotIndex` is refused.
- **Thrown wind-ups.** The spear raise (≥ 450 ms) and knife wind-up (250 ms) are timed by the server with the same `Start` + `Release` pattern as the bow draw.

### 4.9 Ragdolls

**Corpse flow** (server; it runs inside `PlayerService.handleDeath` through `RagdollService.onDeath(character, killInfo)`):

1. Set `AnimationConstraint.Enabled = false` on all of them. The BallSocket limits already exist [S1].
2. Body parts get `CanCollide = true` and the root gets `CanCollide = false`. The collision group is `Corpse`, which collides with Default but not with `Characters`; this needs a new `Characters` group assigned at spawn by `PlayerService`.
3. `SetNetworkOwner(nil)` for the whole mechanism. Server-simulated corpses look the same to everyone; the docs advise using this sparingly [S21], and it's acceptable for at most 24 corpses.
4. `ApplyImpulseAtPosition` on the hit part, with the killing blow's direction and weight (§3.7), on the server, which now owns it [S22].
5. Before `loadIntoLobby`:
   - set `player.Character = nil` and move the model to `workspace.Arena.Corpses`;
   - keep the Humanoid so clothing still renders, with names hidden;
   - `CombatService.getTargets` only lists `player.Character` and dummies, so corpses are never targets.

   Arrows can stick in corpses. That is optional: exclude corpses to avoid "corpse shields".
6. Settle: after 8 s, or once speed stays below 0.5, anchor every part.
7. Cleanup on `roundEnded`, and keep only the 24 newest.

**Knockdowns** (optional):

- The server sets the attribute `KnockedUntil` and refuses actions until then.
- The **victim's client** (the network owner):
  - changes to `Physics`;
  - disables the joint `AnimationConstraint`s except Root and Waist [S2];
  - enables a Root→LowerTorso weld [S5];
  - applies the impulse.
- **Getting up:**
  1. Re-enable the joints with `IsKinematic = false` and a low `AngularStrength`.
  2. Ramp the strength to 1 over 0.3 s.
  3. Set `IsKinematic = true` and change to `GettingUp` [S3][S20].
- `MovementService` flags a displacement of more than 3 studs during a knockdown.
- Risks: the `CanCollide` resets and choppiness described in [S4].

### 4.10 Remotes (add to `Net.Names`, the edit-time `Remotes` folder, and GameDesign §9)

| Remote | Dir. | Type | Payload |
|---|---|---|---|
| `MeleeStart` | C→S | RemoteEvent | `(swingId: number, dir: string, heavy: boolean, look: Vector3, tC: number)` |
| `MeleeHit` | C→S | RemoteEvent | `(swingId, target: Model?, part: string, hitPos: Vector3, eye: Vector3, look: Vector3, tC: number, world: boolean?, material: Enum.Material?)` |
| `MeleeCancel` | C→S | RemoteEvent | `(swingId)` (only with feint-lite) |
| `Guard` | C→S | RemoteEvent | `(up: boolean, tC: number)` (only with option B) |
| `RangedRelease` | C→S | existing | add `tC` and `shotIndex`; add `"Raise"` mode for the spear and knife |
| `CombatAction` | S→C (all) | existing, extended | `{ userId, action = WindUp\|Strike\|Recover\|Cancel\|Guard\|Unguard\|Draw\|Release\|Throw, itemId, dir, heavy, swingId, t }` |
| `CombatHit` | S→C (nearby) | **UnreliableRemoteEvent** | `{ victim: Model, part: string, dir: Vector3, weight: string, blocked: boolean }` (< 1000 bytes [S24]) |
| `HitConfirm` | S→attacker | existing | add `zone`, `blocked`, `clang` |
| `DamageTaken` | S→victim | existing | add `zone`, `knockback: Vector3`, `stagger`, `interrupt`, `bleed` |

### 4.11 Anti-exploit matrix

| Attack | Defence |
|---|---|
| Zero-wind-up or fast strikes | The server-timed swing timeline (§4.2); `MeleeHit` is valid only in the active window; a cooldown for each phase |
| Reach or hitbox hacks | Rewound part boxes plus tight tolerances; eye check against `HitHistory`; body-parts-only include list |
| Hitting through walls | Line-of-sight ray `eye → hitPos`; clang ordering |
| Spin-swings or snapping aim mid-swing | Turn cap |
| Time spoofing | `tC` must be ≤ now + 0.05; rewind capped at 0.25 s; `tC` must increase with each swing |
| Repeat or spam | `swingId` / `shotIndex` increase and are used once; `Net.rateLimit` |
| No-spread | Server-applied deterministic spread |
| Ignoring stamina | A server stamina mirror (attacks, guard, and sprint estimated from speed above 17 studs/s, the existing threshold); refuses an attack once it costs more than 0.15 past what's left |
| Ignoring stagger or knockdown | A server-side action lockout; MovementService displacement flag |
| Deleting your own head | `RejectCharacterDeletions` at Default or Enabled [S26] |
| Teleport-then-swing | The attacker's `HitHistory` speed between samples must be below the movement maximum + 10, or their hits are refused for 1 s |

### 4.12 Performance budget (server, 24 players)

| Area | Cost | Budget |
|---|---|---|
| `HitHistory` | about 1,440 root writes per second plus 3,600 part writes per second | Under 0.2 ms a frame |
| Melee validation | Maths plus 1 raycast per claim (rate-limited) | — |
| Projectiles | As today, plus drag maths | Under 0.5 ms with 50 in flight |
| Corpses | Up to 24 × 15 parts until anchored | — |
| **Total combat** | — | **Under 1.5 ms a frame** on the server; measure with the MicroProfiler |

---

## 5. Phased implementation plan

The owner roles match the agents that built each area (from the original build journal):

- **Combat:** the combat and viewmodel engineer.
- **Movement:** movement and camera.
- **Rounds:** server gameplay (players, rounds, survival).
- **Inventory:** inventory and loot.
- **Audio:** sound.
- **UI:** UI/UX.
- **Docs:** whoever owns `docs/GameDesign.md`.

| Phase | Deliverable | Scripts that change (owner) | Exit criteria |
|---|---|---|---|
| **0. Groundwork** (S) | Pure modules and data; no behaviour change | New `Shared.CombatDefs`, `CombatMath`, `SwingArc`, `Ballistics` (Combat); `Config.Combat` keys (Combat); `Net.Names` plus edit-time remotes (Combat); GameDesign §6/§9 (Docs) | SyntaxCheck passes; unit tests in §6.1 pass |
| **1. Telegraphed, committed melee** (L) | Light and heavy; directions; server swing state machine; stamina spent and mirrored; movement penalties; third-person attack poses | `CombatService` + `Melee` (Combat); `CombatController` (Combat); `ViewmodelController.Poses`/`Rig` (Combat); `MovementController.spendStamina`, `applyStagger`, attack speed scale (Movement); `CharacterVisuals` attack-pose layer from `CombatAction` (Movement); HUD stamina flash (UI) | A zero-wind-up exploit is refused; observers see a wind-up ≥ 150 ms before contact at 100 ms ping; your feel review |
| **2. Accurate, lag-compensated hits** (M) | `HitHistory`; client blade sweep; `MeleeHit` validation; body-part hitboxes; clang; cleave | New `HitHistory` (Combat); `CombatService.Validate` (Combat); `CombatController` sweep (Combat); `DummyBuilder` (pose history support) (Combat) | ≥ 95% agreement between client hits and the server at 100 ms ± 20; 0 hits through walls; reach exploits refused |
| **3. Damage model and reactions** (M) | Zones; armour by damage type; wounds; interrupts, stagger, knockback; `CombatHit` flinches; hit-stop, drag, FOV punch, haptics; impact sounds by armour | `CombatMath` (Combat); `PlayerService` wound statuses + `Bleed` cause (Rounds); `InventoryService` armour coverage, bandage clears bleeding (Inventory); `CharacterVisuals` reaction springs (Movement); `MovementController` (Movement); `AudioController` / `Sounds` keys (Audio); `HUDController` zone markers and wound icons (UI) | Your feel review; no gore anywhere |
| **4. Projectile physics** (M) | Drag and real gravity; KE damage; stick / glance / break; stuck pickups; spawn compensation; deterministic spread; thrown wind-ups | `ProjectileService`, `ProjectileController`, `CombatController` (Combat); `LootService.spawnStuckItem` (Inventory) | Client and server paths within 0.2 studs; drop tables match §3.4; pickups work in trees |
| **5. Death ragdolls** (M) | Server-owned corpses; collision groups; killing-blow impulse; settling and cleanup; optional loot-on-body | New `RagdollService` (Combat); `PlayerService.handleDeath` / `loadIntoLobby` and `Characters` collision group (Rounds); `RoundService` cleanup (Rounds); `InventoryService.dropAll` option (Inventory) | 10 deaths in a row stable; identical on 3 clients; CPU within budget; **maturity questionnaire updated** |
| **6. Optional** (M each) | Guard and perfect block; knockdowns; feint-lite; shove | `CombatService`, `CombatController`, `Poses` (Combat); `CharacterVisuals`, `MovementController` (Movement); `RagdollService` (Combat) | Depends on your answers |
| **7. Hardening and tuning** (S, ongoing) | Exploit harness; performance pass; tuning keys; optional live tuning through ConfigService | `ServerStorage.Dev.CombatHarness` (Combat); Config (all) | The §6 suites stay green |

**Ordering:** 1 → 2 → 3 is the critical path for "weighty melee", because reactions need validated hits and readable telegraphs. 4 can run in parallel with 3, and 5 in parallel with 4.

---

## 6. Test plan

### 6.1 Unit tests (Edit mode, pure modules; `rbx-unit-test` skill)

- **`SwingArc`:**
  - points sweep the whole arc;
  - no step is larger than 0.6 studs at 30 fps;
  - every direction stays inside its arc bounds;
  - stab thrust is linear.
- **`HitHistory`:**
  - interpolation is exact at the samples and monotonic between them;
  - clamping at `MaxRewind`;
  - eviction after 1.07 s.
- **Validator matrix**, which must accept or refuse:

  | Case | Expected |
  |---|---|
  | Legit hit | Accept |
  | Early, or late by 1 ms | Refuse |
  | Reach + 0.8 | Refuse |
  | Behind a wall | Refuse |
  | Future `tC` | Refuse |
  | Rewind 0.4 s | Clamped |
  | Spin-swing | Refuse |
  | Repeated `swingId` | Refuse |
  | Dead target | Refuse |

- **`CombatMath`:** zone × armour × damage-type table; wound thresholds; exhausted and weak scaling.
- **`Ballistics`:** matches the analytic solution when drag is 0; the §3.4 tables to ±0.2 studs; client and server determinism with the same seed and `shotIndex`.

### 6.2 Server integration (Edit mode with mocked services)

This is the pattern the original agent already used: the `CombatService._trace` and `ProjectileService._simulate` hooks. Extend it to `Melee` and `Validate` and the projectile surface responses.

### 6.3 Playtests (Studio "Server & Clients", 2–4 players)

- **Network profiles** through Studio network simulation [S31]:

  | Profile | Latency | Jitter | Packet loss |
  |---|---|---|---|
  | Clean | 0 | — | — |
  | Typical | 100 ms (50 in, 50 out) | 20 ms | — |
  | Bad | 200 ms | 40 ms | 0.5% |

- **Strafing dummies:** add a Studio-only patrol to `DummyBuilder`, moving at 13 studs/s.
- **Metrics:** 200 swings per weapon per profile, recording:
  - agreement between client prediction and server confirmation: **≥ 95% on Typical, ≥ 85% on Bad**;
  - hits the server refused that the client showed (they get a "blocked by lag" sound): **≤ 3% on Typical**;
  - hits through walls: **0**.
- **Readability:** record a second client; measure the time from the first visible wind-up pose to contact (**≥ 150 ms** on Typical, for medium and heavy weapons).

### 6.4 Exploit harness (Studio only)

`ServerStorage.Dev.CombatHarness` is driven from a test LocalScript. It forges, and expects refusals for:

- zero-wind-up and rapid `MeleeHit`;
- reach + 2;
- hits through a 1-stud wall;
- `tC` 0.5 s in the future or past;
- reused ids;
- the wrong weapon;
- dead or knocked-down attackers;
- a no-spread `RangedRelease`;
- `shotIndex` replay;
- teleport-then-swing.

### 6.5 Feel review (you)

A checklist per weapon:

- Is the wind-up readable?
- Does the hit feel heavy?
- Is the miss punished?
- Does the reach match the blade?
- Do armour and head hits feel right?

Live A/B keys: `HitStopScale`, `KnockbackScale`, `ReachScale`, `WindupScale`, `ThrowAssist`.

### 6.6 Performance

MicroProfiler during a 4-client brawl with 40 arrows in flight and 10 corpses: the server combat budget is under 1.5 ms per frame; the client sweep is under 0.3 ms per frame (`rbx-perf-profiling` skill).

### 6.7 Content compliance

Capture video of death, ragdoll, impacts and wounds. Check that no asset shows blood or gore. Update the **Maturity & Compliance Questionnaire** before publishing [S29].

---

## 7. Open design questions (for you)

1. **Defence:**
   - (A) no blocking;
   - (B) simple guard + perfect block (recommended);
   - (C) full directional parry, riposte and feint?
2. **Light and heavy input:** tap = light, hold = heavy, replacing "hold to keep swinging"?
3. **Directional attacks:** automatic, picked from your mouse or stick motion at the start of the swing (recommended)? Or explicit inputs?
4. **Ragdoll on death:**
   - persistent server-owned corpses until the round ends, which means a Moderate label (recommended);
   - or bodies that vanish at death, which allows Mild but looks less realistic?
5. **Blood:**
   - none (recommended);
   - or light, distant-only realistic spatter, which risks Heavy (18+) because melee is always up close?
6. **Knockdowns** of living players (a 1.6 s ragdoll and get-up from mace heavies to the head or exhaustion): yes or no?
7. **Thrown-weapon realism:** real-ish speeds with big arcs (knife 85, spear 75 studs/s at gravity 35)? Or "assisted" speeds (about 110 studs/s at gravity 45)? And should thrown knives sometimes bounce off handle-first, or always stick?
8. **Hit zones and wounds:** use zones, torso-only armour, bleeding, limping and dazed? Or keep it simpler?
9. **Reach and pace:** accept realistic reach and longer, readable wind-ups? (Knife about 3.4 studs from the eye against today's effective 11; mace light wind-up 450 ms.)
10. **Stamina gating:** should exhaustion make swings slower and weaker, and block heavy attacks?
11. **Loot on death:** keep scattering the inventory? Or keep it on the corpse, so you search the body?
12. **Third-person animation:** procedural poses first (fast, recommended), then authored Blender animations later? If authored, they have to be uploaded under the experience owner.
13. **Server Authority:** OK to stay on the current model for now and revisit when Roblox ships server-side rewind?

---

## 8. Sources

Official Roblox documentation (create.roblox.com pages were read as `.md` through `http_get` on 2026-11-10):

- [S1] Avatar Joint Upgrade is now live (DevForum, Roblox Physics Team, 2026-01-26) — https://devforum.roblox.com/t/avatar-joint-upgrade-for-physically-simulated-character-movement-is-now-live/4298561
- [S2] AJU Phase 2 rollout and migration recommendations (DevForum, 2026-05-27) — https://devforum.roblox.com/t/avatar-joint-upgrade-aju-phase-2-rollout-updated-migration-recommendations/4656414
- [S3] AnimationConstraint API reference — https://create.roblox.com/docs/reference/engine/classes/AnimationConstraint.md
- [S4] AJU thread, page 10 (community ragdoll reports; choppy-replication known issue) — https://devforum.roblox.com/t/avatar-joint-upgrade-for-physically-simulated-character-movement-is-now-live/4298561?page=10
- [S5] "Smooth ragdoll system" community resource (2026-08-19) — https://devforum.roblox.com/t/smooth-ragdoll-system/4820121
- [S6] AJU vs. IKControl limits report (2026-08-18) — https://devforum.roblox.com/t/avatar-joint-upgrade-causes-ikcontrol-limbs-to-become-incorrectly-restricted-by-generated-ballsocketconstraint-limits/4817993
- [S7] Server authority model — https://create.roblox.com/docs/projects/server-authority.md
- [S8] [Full Release] Server Authority (DevForum, 2026-07-09) — https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993
- [S9] Server authority techniques — https://create.roblox.com/docs/projects/server-authority/techniques.md
- [S10] Roblox newsroom, Server Authority (2026-07; seen in search results only) — https://about.roblox.com/newsroom/2026/07/creating-responsive-cheat-resistant-games-roblox-server-authority
- [S11] WorldRoot (Raycast, Spherecast, Blockcast, Shapecast; no detection of shapes that start intersecting) — https://create.roblox.com/docs/reference/engine/classes/WorldRoot.md
- [S12] Introducing Shapecasts (DevForum; seen in search results only) — https://devforum.roblox.com/t/introducing-shapecasts/2320655
- [S13] ShapecastHitbox (DevForum, TeamSwordphin, 2025, v0.2.5) — https://devforum.roblox.com/t/shapecasthitbox-for-all-your-melee-needs/3624241
- [S14] RaycastHitbox 4.01 (DevForum; seen in search results only) — https://devforum.roblox.com/t/raycast-hitbox-401-for-all-your-melee-needs/374482
- [S15] Server-sided hit detection with lag compensation (DevForum, 2024-12-27) — https://devforum.roblox.com/t/server-sided-hit-detection-with-lag-compensation/3322386
- [S16] SecureCast: server-authoritative projectiles with lag compensation (DevForum, 2023) — https://devforum.roblox.com/t/server-authoritative-projectiles-with-lag-compensation-multi-threading-and-more/2546164
- [S17] Character interpolation period (DevForum, 2021) — https://devforum.roblox.com/t/character-interpolation-period/1523855
- [S18] Valve Developer Community: Lag Compensation (seen in search snippets; the page returned 403) — https://developer.valvesoftware.com/wiki/Lag_Compensation
- [S19] Roblox units (1 stud = 28 cm; real gravity 35 studs/s²) — https://create.roblox.com/docs/physics/units.md
- [S20] HumanoidStateType — https://create.roblox.com/docs/reference/engine/enums/HumanoidStateType.md
- [S21] Network ownership — https://create.roblox.com/docs/physics/network-ownership.md
- [S22] BasePart (ApplyImpulse ownership rules) — https://create.roblox.com/docs/reference/engine/classes/BasePart.md
- [S23] Security and cheat mitigation tactics — https://create.roblox.com/docs/scripting/security/security-tactics.md
- [S24] UnreliableRemoteEvent (1000-byte limit) — https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent.md
- [S25] Player:GetNetworkPing — https://create.roblox.com/docs/reference/engine/classes/Player.md
- [S26] Workspace.RejectCharacterDeletions — https://create.roblox.com/docs/reference/engine/classes/Workspace.md
- [S27] IKControl — https://create.roblox.com/docs/reference/engine/classes/IKControl.md
- [S28] HapticEffect / HapticService — https://create.roblox.com/docs/reference/engine/classes/HapticEffect.md
- [S29] Content maturity and compliance (labels, violence, blood) — https://create.roblox.com/docs/production/promotion/content-maturity.md
- [S30] Roblox Community Standards (violent content and gore; weapons) — https://about.roblox.com/community-standards
- [S31] Expanding Network Simulation in Studio (DevForum, 2026-06-02) — https://devforum.roblox.com/t/expanding-network-simulation-in-studio/4665487
- [S32] Mordhau combat (phases, feint window, parry patch). Search snippets only; the pages were not opened (HTTP 402) — https://mordhau.fandom.com/wiki/Combat and https://steamdb.info/patchnotes/4423941
- [S33] Chivalry 2 combat guide (PC Gamer) — https://www.pcgamer.com/chivalry-2-weapons-classes-guide
- [S34] DayZ melee techniques (4netplayers, community guide) — https://www.4netplayers.com/en/blog/dayz/dayz-melee-techniques-weapons
- [S35] Sakurai on hitstop: Famitsu column translation (Source Gaming, 2015) — https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/ ; 2022 video coverage — https://www.gonintendo.com/contents/13581-sakurai-s-latest-game-dev-video-features-8-hit-stop-techniques
- [S36] "Hitstop / hitfreeze / hitlag" (critpoints) — https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/
- [S37] Squirrel Eiserloh, "Math for Game Programmers: Juicing Your Cameras With Math" (GDC 2016) — https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing
- [S38] Recurve arrow speeds (retailer, forum and magazine figures; estimates) — https://www.bowhunter.com/editorial/3-rules-of-thumb-to-follow-for-consistent-arrow-speed/310532 and https://3riversarchery.com/pdf/Elite_Flex_Recurve_Speeds_and_Draw_Curves.pdf
- [S39] Arrow drag: Miyazaki et al., Sports Engineering 16:43–54 (2013) — https://link.springer.com/doi/10.1007/s12283-012-0102-y ; Park, Proc. IMechE Part P 225 (2011) — https://journals.sagepub.com/doi/10.1177/1754337111407124
- [S40] Milks, Parker & Pope, "External ballistics of Pleistocene hand-thrown spears", Scientific Reports 9:820 (2019), doi:10.1038/s41598-018-37904-w; summary — https://www.sciencedaily.com/releases/2019/01/190125084048.htm (the velocity values were not extracted)
- [S41] Physics of knife throwing (enthusiast site; amateur measurement) — https://knifethrowing.info/physics_of_knife_throwing.html
- [S42] "Rewind" lag compensation framework (community; not verified) — https://text21.github.io/Rewind

### Unconfirmed items

- **Death ragdoll in this place:** the default AJU death with `CharacterBreakJointsOnDeath = false` was not playtested.
- **Mordhau numbers** [S32]: from search snippets only.
- **Bow, spear and knife speeds** [S38][S40][S41]: estimates. The spear velocity is my assumption.
- **Valve page** [S18]: from search snippets.
- **`RaycastResult.Material` with terrain MaterialVariants:** assumed to report the base material.
- **`AnimationConstraint.Transform` with `UseFixedSimulation`** [S2]: a community report.
- **`Workspace.RejectCharacterDeletions`:** my script couldn't read it. Check it in Properties.
- **The "Rewind" framework** [S42].
