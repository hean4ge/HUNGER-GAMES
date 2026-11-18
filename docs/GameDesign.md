# LAST STANDING — Game Design & Architecture Spec (v1)

Working title: **LAST STANDING** (rename freely in `ReplicatedStorage.Shared.Config.GameTitle`).
Roblox Studio place: placeId 120572716460286 (the experience is named "HUNGER GAMES (UNDER DEVELOPMENT + TESTING)"), Team Create / live editing.

**Which arena (18 November 2026).** The game runs on Map 1, the Green Land (`Config.Map = "GreenLand"`): up to 48 contenders on plinths 150 studs from **the Horn**, play radius 1,800. Its numbers and builders are in [design/Map1Build.md](design/Map1Build.md). Sections 1, 10 and 11 below still give the classic forest arena's sizes and names (the Spire, 24 plinths, radius 640); that arena is in `ServerStorage.Vault_ClassicForest` and its numbers apply only if it is restored. The round, the fight, the remotes and the module contract are the same on both.

Lines marked **†** describe code from the afternoon of 18 November that was in `src/` and in the open Studio session but not yet committed or in a saved place version when this page was updated. Everything else is commit `e2226af`, place version 404.

---

## 1. Vision

First-person survival arena. Up to 24 contenders start on plinths around **the Spire** at the centre of a large mixed-biome arena. A horn sounds: rush the Spire for the best loot or flee and scavenge. Manage hunger and thirst, fight with blades, spears and bows, hide in bushes and up trees. Late in the round a closing **border** herds the survivors together. Last one alive wins.

**Original IP only.** The genre resembles a famous book/film franchise. Never use its names or symbols anywhere in the game (code, UI text, instance names, asset searches): no "Hunger Games", "Capitol", "District", "Panem", "Mockingjay", "Tribute", "Cornucopia", "Gamemaker", or character names. Roblox removes games that copy other IP.

Our vocabulary: **contenders** (players), **the Spire** (central structure), **plinths** (start pads), **the border** (closing ring), **the Feast** (midgame restock of the Spire), **the Roll Call** (list of the fallen shown at dusk), **the cannon** (sound when someone falls). On Map 1 the centre is **the Horn**, and player-facing text calls the start sound "the signal".

## 2. Pillars (priority order)

1. **Movement and camera feel** — weighty but agile: momentum, sprint with stamina, crouch, slide, vault/mantle, climbable trees, head-bob synced to footsteps, landing impact, full-body first person (you can see your own legs and torso).
   - **Jumps are low and realistic**: ~3 studs, ~0.4 s in the air. A press starts a short knee dip (`JumpPrepTime` 0.1 s standing, `JumpPrepTimeMoving` 0.06 s on the move), then the take-off; momentum carries through. A held or mashed key can't bunny-hop: jumps are edge-triggered and the feet stay down `JumpGroundTime` (0.2 s) after each landing; repeated hops are lower and cost more stamina. The body plays a generated realistic jump clip in segments (dip → take-off → held air pose → touch-down) with procedural leg tuck and arm balance on top (`Animate`, `CharacterVisuals`); no arms-up default. Landing compression and the eye dip scale with the drop. At the take-off the foot IK lets go of the floor at once (it stops reading the ground and releases its offsets), so the feet leave with the body and the pelvis never lags and snaps; every client poses every nearby character this way (remote take-offs are detected from the replicated Jumping state or the root rising above the floor its feet stood on). The first-person eye dips with the knee bend and is back at full height by the take-off (in step with the clip), then rises with the root (no step-smoothing lag). Looking steeply down in the air, your own body keeps the jump clip's pelvis lift and forward trunk pitch at most at the bind pose and its leg tuck and lean flatten out, so the chest doesn't rise into the view and the hands stay visible (others still see the full pose); any body part within 0.2 studs of the camera is hidden rather than cut open by the near plane. Anything taller than a jump is mantled; fences up to ~5 studs are climbed over (~1 s).
   - **Avatars load as the player has them** (their own body scales and proportions, forced to R15). Movement, camera and body IK measure each rig (`MovementController.measureRig`): ledge reach and probe heights scale with body height, stride/footstep length and clip playback with leg length, foot-IK limits with leg length, and the crouch drops the head toward 4.3 studs as far as the knees allow. Speeds and the jump height are the same for everyone.
   - **Held fast on steep ground** (`MovementController`, `SLOPE.Wedge*`). Ground steeper than walkable can't be walked up: you slide down it. Held fast there (a rock pocket, a V between two faces) or hung up in the air, moving less than 0.5 studs in 1 s, the slide stops pushing (steering still works) and one jump, mantle or climb may start from the spot until you move a stud off it. That is allowed at most once every 2.5 s and only within 1.5 studs above the last ground you stood on, and the jump and the grab reach no higher than the same jump from that ground, so a pocket can't be used to climb a cliff (cliff faces and the mountain wall measured as before). Where even that can't get you out (60° V pits deeper than about 4 studs, the pocket in §11's known limits), Reset is the way out (§4).
2. **Tension** — scarce loot, survival meters, hiding, positional sound (footsteps, the cannon), day → dusk → night, the closing border.
3. **Premium, minimal UI** — stylized-realistic, readable, no clutter.
4. **Every device** — PC, mobile (touch buttons) and gamepad.

## 3. Art direction — stylized-realistic

Realistic lighting, atmosphere and Roblox PBR materials with slightly simplified, chunky shapes. Natural, slightly desaturated palette; warm sun, cool shadows, atmospheric haze.

- Materials: Grass, LeafyGrass, Ground, Mud, Rock, Slate, Basalt, Sand, Snow, Wood, WoodPlanks, Cobblestone, Brick, Concrete, CorrodedMetal, Metal, Fabric. Avoid big SmoothPlastic or Neon surfaces.
- Everything part-built now is a **placeholder to be replaced by Blender meshes later**, so build reusable templates with tidy names.
- UI tokens live in `ReplicatedStorage.Shared.Theme`: off-white text, charcoal translucent panels, ember-orange accent, thin bars, Oswald headings, BuilderSans body.

## 4. Round flow (`ReplicatedStorage.GameState` attribute `Phase`)

`Lobby → Intermission → Countdown → Active → Ending → Lobby`

- **Lobby** — wait until `Config.Round.MinPlayers` players are in the lobby (Studio solo test: 1). A player alone on a live server gets a practice round instead (Practice mode below).
- **Intermission** — `IntermissionTime` countdown; back to Lobby if players drop below the minimum. Before a lone player's next practice round it is the shorter `PracticeIntermissionTime` (Practice mode below). **Filling a public server** (`RoundService`, `Config.Round.FillExtendOnJoin`): on a live public server a player who joins during the Intermission restarts its countdown at `IntermissionTime` (25 s), never past `FillMaxTime` (90 s) from the Intermission's start; with `FillTarget` (8) or more already waiting there is no restart. The rule is off in Studio and on a private server (`game.PrivateServerId ~= ""`, published as `GameState.PrivateServer`), which starts with whoever is there. **The pick:** a round takes `Config.Round.MaxContenders` at most (48 on Map 1); when more are waiting than plinths, whoever played least recently goes first and the others get a toast and can spectate. If the Intermission ends with two or more present but fewer than two ready (loading or respawning), the pick waits up to `StartHoldTime` (10 s) instead of giving one of them a practice round.
- **Countdown** — the picked lobby players (up to `MaxContenders`) are teleported onto the launch plates (plinths) facing the Spire with `Frozen = true`; loot is populated. **The launch:** every client lowers the plates and their contenders into the launch tubes and raises them back into the morning light on one shared timeline (`GameState.LaunchAt` / `LaunchRise` / `LaunchDepth`, `Config.Round.LaunchDelay/LaunchRiseTime/LaunchDepth`; `LaunchController`): lift whir, a clunk and dust as each plate locks. The server anchors and freezes a contender before it places them (it waits for streaming around their plate), so a client re-bases a rider whenever the server moves their root and lowers them onto their sunken plate from that frame on: the feet stay on the plate for the whole rise. **Facing the Spire:** the server turns each body toward the Spire, but in first person the body follows the camera. So once a round, the first time a client finds its contender frozen and anchored on the plate ring (within 8 studs of r 52), it turns the view to the Spire, 6° down at the Spire and the crates at its foot (`LaunchController` calls `CameraController.faceToward`, which writes the look on 3 frames before the default camera runs). The look is free from then on, and a contender placed late (the server waiting for streaming) still gets the turn. During the rise a client only moves its own root and keeps the facing its camera gives it (other riders keep the server's), so the body never flips between the two. The countdown reads "STAY ON YOUR PLATE · THE ARENA OPENS IN N" and pulses if you try to move. Then the start horn and `Frozen = false`. A real round left with one contender for 1 s during the Countdown is cancelled ("Round cancelled": no winner card, `RoundsPlayed` unchanged). **The launch intro** (`LaunchIntroController`, `Config.Launch`) plays over the Countdown: the full cut (22 s to the signal) when at least `FullCutShare` (0.5) of the contenders haven't seen it this session (player attribute `Launched`), the short cut (12 s) otherwise and in practice rounds. Its hall holds at most 24 glass cases, so on Map 1 two neighbouring plates share one.
- **Active** — two days in one round (`Config.Round.DaySchedule`, `Shared.DayCycle`): day 1 morning (07:24) → golden hour and sunset (18:00, ~310 s) → blue hour → the moon takes over (19.25, ~342 s) → **Roll Call 1** at 19:27 (345 s) while the clock slows for it (the vigil) → a moonlit night of ~2.7 minutes → the moon sets (4.75, ~503 s) → sunrise and morning mist (~534 s) → **the Feast** at 590 s (08:30) → the border shrinks 600–830 s (`Border.ShrinkStartTime/ShrinkDuration`) down to `FinalRadius` → sunset 2 (~812 s) → **Roll Call 2** at 845 s → the vigil until `MaxRoundTime` (900 s). The server publishes the clock as a time base (`GameState.Clock`); clients move the sun and the whole lighting look every frame. The engine swaps the sun's light for the moon's at 19.25 and back at 4.75 (measured at latitude 44); `DayCycle` dips the sun/moon brightness around both so the moonlight fades in and out instead of popping. Between sunset and the moon taking over, and between the moon leaving and sunrise, the engine gives no direct light and the sky light collapses, so `DayCycle` eases OutdoorAmbient/Ambient toward a cool twilight fill (`Knobs.TwilightOutdoor/TwilightAmbient/TwilightEvening/TwilightMorning`, `DayCycle.twilightFill`) in step with the moonlight's fades: dusk and pre-dawn stay a little brighter than the moonlit night instead of going black. The round ends when 1 or 0 contenders are alive, or at `MaxRoundTime` (winner only if exactly one is alive).
- **The border wall** (`ArenaController`, client-local `workspace.Arena.Border`) is a ring of tall Neon panels in orange, placed from `GameState.BorderCenter` / `BorderRadius`. Each panel's transparency depends on its flat distance from the camera: the full sheet (`BASE_TRANSPARENCY` 0.84, firmer while the ring moves) near the camera, thinned to `FAR_TRANSPARENCY` beyond `FADE_FAR`. At full engine quality an unfaded sheet dyed everything behind it (red forest, pink mountains from the plates of a small round). At `e2226af` the fade runs from 60 to 360 studs to 0.965, which left the starting ring barely visible from the plates. **†** The fade now runs from 20 to 64 studs to 0.975, and from afar the wall is told by a bright line on the ground under it (`BorderLine`, 0.15) and a low skirt of light over that line (`BorderSkirt`, 44 studs high, 0.93 from 480 studs out), both laid along the ground from `ArenaLayout.heightAt`. The red grade for standing outside the border applies only in the Active phase.
- **The Roll Call ("The Fallen")** — at each dusk (`RollCallClockTime` = 19.45 of every day, just after the moon takes over) everyone who fell since the last one appears in the sky as a 3D point cloud: TV static → the day caption ("DUSK · DAY ONE" over "4 FELL TODAY") → each fallen contender as a point-cloud bust of their avatar with their name in point letters → all of them together → the day caption again → back to static. Nobody fell: the caption alone, reading "NO ONE FELL TODAY". No emblem frames the fallen and there is never an anthem or music bed: only static hiss and crackle and a low tone that swells in as each piece resolves; whatever music was playing (tension, the final stand) fades out as the static comes up and stays off until the show ends (`AudioController.setMusicSuppressed`). Under trees each client lifts the display (25° up to 57°) to where the canopy leaves it clearest, counting tree crowns (foliage meshes don't take raycasts) as volumes; a dense stand still hides much of it, so the small 2D list of the names at the right edge (with its "look up · in the sky to the S" hint) carries them there. Synced from `GameState.RollCall` (late joiners join mid-way); avatar snapshots in `ReplicatedStorage.FallenSnapshots` (`ArenaService.FallenSnapshots`, `FallenRecapController`). The show is capped at `DayCycle.Recap.MaxTotal` (45 s) by shrinking every entry equally, with a floor of `EntryMin` (0.5 s) an entry, so 47 fallen take 47.7 s instead of 191 s; the cap bites from 4 fallen up. `FallenSnapshots` keeps a snapshot for every contender (`max(40, MaxContenders)`).
- **Ending** — winner announced: `GameState.WinnerUserId` is set first, then `GameState.WinnerName`, and the Announce of style `Victory` carries `winner` and `winnerUserId`. A client shows VICTORY only when the id is its own (`NotificationController`); display names are not unique. Without an id it falls back to the name plus `Alive == true` and `Placement <= 1`. `RoundSummary` is sent, `EndingTime` seconds pass, then everyone is reloaded into the lobby and the arena loot is cleared.
- **Practice mode** (`GameState.Practice = true`) when exactly one contender started the round: the round does not end just because one is alive; it ends on death or timeout. Practice rounds add no Wins, TotalKills or RoundsPlayed.
  - **Alone on a live server** (`Config.Round.SoloPractice`, PlayabilityPlan QW1): one lobby countdown ("PRACTICE ROUND IN", to `GameState.SoloStartAt`) covers `SoloWaitTime` (30 s, counted from joining, so loading is part of it) and the Intermission (25 s): a newcomer is on a plate 55 s after joining and hears the horn 10 s later. A contender who arrives during a practice round ends it `PracticeHandoffTime` (60 s) later, with the lone contender as its winner; one who arrives during its Intermission makes it a full round. In Studio's solo test (`MinPlayers` 1) a round simply starts with you alone, so neither the wait nor the short Intermission below runs (§12).
  - **Going again:** still alone when their practice round ends, a player gets the next one after a short Intermission (`PracticeIntermissionTime` 8 s, never longer than `IntermissionTime`) instead of a second wait: Ending 10 s + 8 s + Countdown 10 s, about 28 s from death to the next horn (it was 75 s). The lobby's PRACTICE ROUND IN bar spans just that Intermission. A contender who arrives during it restarts it as a normal one (25 s, "NEXT ROUND"). Someone left alone later, not straight after their own practice round, waits the full `SoloWaitTime` as before.
  - **Training dummies** (`CombatService`; `Config.Combat.PracticeDummies` 3, tagged `TrainingDummy`) stand in a shallow arc about a dozen studs in front of the contender, toward the Spire, in every practice round during Active, in Studio and on live servers alike (`SoloPractice = false` turns them off live). A round with two or more contenders never has them, and they are cleared when the round ends. Each has `DummyHealth` 200, wobbles when hit, heals to full `DummyRegenDelay` (4 s) after the last hit and, once broken, stands again `DummyRespawnTime` (3 s) later. With none out, their Heartbeat update returns at once (about 0.7 µs of server time a second).
- Players who join mid-round wait in the lobby and can spectate. Leaving mid-round counts as an elimination.
- **Death** — the cannon for everyone, a kill-feed entry, the inventory drops as ground loot, the victim gets `YouDied`, respawns in the lobby after `RespawnDelay` and can spectate the remaining contenders. The kill-feed entry carries `killerUserId` and `victimUserId`, and the HUD marks "you" by id. **Defeat is kept clearly unrealistic, for the age rating: no blood, no wounds.** At `e2226af` nothing handles it: Roblox's default breaks the body into loose limbs, which lie until the respawn. **†** `CombatService.watchDefeat` turns `BreakJointsOnDeath` off as characters load, so the body topples in one piece; `CharacterVisuals` fades it on every client `DEFEAT_FALL` (1.8 s) after it fell, over `DEFEAT_FADE` (1 s); the server then hides it and takes it out of every ray and touch. Roblox's own death sound is muted; only the cannon plays. There is no slow motion and no kill view.
- **Reset** (the Roblox menu's own: Esc → R → Enter) is allowed in the lobby and in the arena once the horn has sounded (`HUDController` sets `ResetButtonCallback`), never while frozen on the plate during the Countdown: it is the way out of a spot you can't leave. It is an elimination with cause "Reset" (`PlayerService`: a contender whose humanoid dies above the void without going through `damage` reset it from their own client). An attacker who hit them within `Config.Survival.KillCreditWindow` (15 s) gets the kill, and the death card reads "You reset" ("You reset · after a fight with <name>" in that case), with no tip.

## 5. Survival

- `Hunger` and `Thirst` 0–100 (player attributes) drain per `Config.Survival` while the player is an alive contender during Active (faster while sprinting). At 0 they cause damage over time.
- Slow regeneration only when both are above `RegenMinStat` and no damage was taken for `RegenDelayAfterDamage`.
- Drink from terrain water (look at water within `DrinkRange` and use the Drink action) or from water bottles; an empty bottle can be filled at water. Food restores hunger.
- Armor (vests) is put on with the primary action and reduces damage.

## 6. Combat

Fists (nothing equipped), knife, machete, hatchet, spear (melee and throw), mace, sword; recurve bow (hold to draw, release to fire, arrows are ammo, projectiles with gravity, headshots: a full draw does 50, and `Config.Combat.BowHeadshotMultiplier` 1.8 makes a full-draw headshot 90, so one arrow can't kill from full health); throwing knives. Server-authoritative hits and damage. Stats in `Shared.ItemDefs` and `Config.Combat`.

**Melee reach** (`CombatController.predictMelee`, `CombatService.onMeleeSwing`). At the strike the attacker's client traces from `CameraController.getBaseCFrame()` (the default first-person camera, 0.5 studs behind the head, so render-step order doesn't matter): first a thin ray along the look, so the body under the crosshair wins; failing that, a sphere of 0.85 × `MeleeHitRadius` (2.04 studs) swept `range` studs along the view; then a point-blank check. A hit on a weapon the target holds counts as a hit on the target. Only living bodies are targets: one that just fell neither takes nor blocks a swing. Accessory parts are outside every hit box (`CanQuery` off, set by `CombatService` as characters load). The client sends `MeleeSwing(lookDirection, predictedHit, variant, target, startTime)` (§9). A swing it showed as a miss never lands. For a swing it showed as a hit, the server sweeps from its own head position and checks the named `target` and no other body, so a bystander beside the line never takes the hit.

How far the server's sweep reaches, measured from the head to the target's surface:
- **Standing still:** `range` + 0.85 × 2.4 − `MELEE_CAMERA_BEHIND` (0.5) + `MELEE_REACH_ALLOWANCE` (0.5; it was 1 until 18 November). For the sword (range 8) that is 10.04 studs, 10.5 root to root: a hit claimed from 10.4 is accepted and one from 11 is refused.
- **The lag allowance.** At `e2226af` it is flat: when anything that can move is in the swing's corridor, the reach is `range + MeleeLagTolerance (3) + MeleeHitRadius` (sword 13.4 from the head). The two-client test showed what that costs: a modified client landed a sword hit from about 15 studs, root to root, on a player who had not moved. **†** The server now measures it (`meleeFront`, `recentTravel`): it samples every body's position each 0.05 s during Active and adds how far the target moved in the last `MELEE_LAG_TIME` (0.25 s) plus how far the attacker moved in the last `MELEE_OWN_LAG` (0.1 s). Two players standing still get no lag allowance. The flat figure above stays as the cap, and a target walking away at full speed already uses it up.

**When the next swing may start** (`CombatService.trySwing`). The server uses the client's own rule: the next swing may start once the cooldown of the weapon that swung last has passed since that swing started, whatever is in hand now. That is what makes the first swing after a weapon switch count. `startTime` is `workspace:GetServerTimeNow()` on the attacker's client when the swing began; the server believes it up to `SWING_LATE` (0.35 s) before the strike arrived, and an early start never pulls the next window earlier, so lateness can't be banked. Known fault at `e2226af`: the start time is thrown away by a range check (`Util.isFiniteNumber` stops at 1e9 and server time is Unix time), so only `CooldownJitter` (0.12 s) is forgiven; a one-line fix was on disk, untested, when this page was updated. Refusals are counted by reason in `CombatService._refusals` and printed in Studio. The attacker's own hit sound and shake are predicted locally, so a refused swing can still sound like a hit; only the hit marker waits for `HitConfirm`.

**What the others see.** When a swing begins the client sends `MeleeSwing("Start", variant)`; the server relays `CombatAction` `Swing` with `lead` = the weapon's windup to the players within 220 studs (at most one start per 0.3 s per attacker, no trace), and `CharacterVisuals` fits the wind-up so the cut crosses at the strike. If no start arrived, the swing is announced at the strike with `lead` 0 and starts wound up. `CombatAction` and the swing, hit, bow and throw sounds go only to players who can see or hear them: within 220 studs for actions, within the sound's roll-off distance plus 30 studs for sounds, measured from the listener's character or from the contender they spectate (`ReplicationFocus`). `CharacterVisuals` caps the per-frame posing of other characters: foot IK and the air pose for the nearest 8, twist and lean for the nearest 24 (4 and 12 on phones and tablets); stances and swings show at any rank. In third person a blade or a throwable is raised by the hold pose (`InventoryService`). At `e2226af` the bow hangs from the right hand with its lower limb in the ground and has no draw pose. **†** The bow is welded to the left hand, and `CharacterVisuals` gives it a hold and a draw pose driven by `CombatAction` `Draw` / `Release`.

**The bow's draw record** (`CombatService`, `RangedRelease`). The client sends `Draw` when the string comes back; the server records it per player (`drawStart`, `drawItem`) and tells the others once per draw. `Fire` needs a recorded draw for that bow: without one there is no shot. The charge is capped by the measured draw time, counted from the later of the `Draw` message and `BOW_RECOVER` (0.32 s) after the last shot, with `CHARGE_JITTER` (0.15 s) forgiven for the network and never banked; a charge under `Config.Combat.MinBowCharge` (0.2) is refused. `Fire`, `Cancel` and a weapon switch (`InventoryService.equippedChanged`) clear the record. A shot's claimed origin may be 3 studs from the server's head position at rest, plus 0.2 per stud/s of speed; further than that, the shot starts at the head. Thrown knives and spears aim along the rendered view, like the bow.

Spent arrows, throwing knives and thrown spears never vanish (`ProjectileService.WorldProjectiles`, rules in `Shared.WorldItems`): they stay embedded where they hit (angled along the flight, sunk by material and speed, fletching out), rest on the bed under water, land where a miss's arc meets the ground, and stick in the body part of a contender or dummy until that body dies or `Config.Combat.BodyFallOutTime` (~30 s) passes, then lie on the ground there. A training dummy lets its items out as it breaks, before its parts are flung (`CombatService` calls `world.releaseFrom`), and a hit on a body that is already dead (the killing shot included) falls straight out. "The ground" is terrain or a part held in place: the drop ray looks past bodies, broken dummy parts and loose parts, and an item lying on a part that is removed drops again. Anyone alive can take them: walking over arrows and throwing knives (`Config.Loot.AutoPickup`, even holding none) or E on the one you look at within reach (`WorldItemController`). They stay until the round's arena cleanup; `Config.Combat.WorldItemCap` (400) per server, oldest first.

## 7. Controls (action names are a contract; bind through `Shared.Input`)

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Sprint | LeftShift (hold) | ButtonL3 (toggle) | toggle button "RUN" |
| Crouch | C or LeftControl (hold); while sprinting = slide | ButtonB | "CROUCH" |
| Jump | Space (Roblox default) | ButtonA | Roblox jump button |
| Attack | MouseButton1 = primary action of the equipped item (swing; hold to draw and release a bow; throw; hold to eat, drink, bandage or put on armor) | ButtonR2 | "ATTACK" |
| Aim | MouseButton2 (bow zoom; spear: hold Aim + Attack to throw) | ButtonL2 | "AIM" (bow/spear only) |
| Zoom | V (hold): 2.5×; while held the mouse wheel moves it between 1.56× and 4× and the hotbar doesn't change (`Config.Camera.Zoom*`, `CameraController`) | ButtonR3 (toggle) | "ZOOM" (toggle) |
| Drink | E, only while looking at water | ButtonX | "DRINK" (only near water) |
| Interact | ProximityPrompts: E | ButtonX | tap |
| Slot1–Slot6 | One–Six; MouseWheel cycles | NextSlot/PrevSlot: ButtonR1/ButtonL1 | tap hotbar slots |
| Drop | G | DPadDown | "DROP" |
| Menu | M | DPadUp | on-screen button |
| SpectatePrev / SpectateNext | Q / E and Left / Right arrows | ButtonL1 / ButtonR1 while spectating | on-screen arrows |

In the lobby: third-person camera, movement only, no attacks. In the arena: locked first person.

## 8. Architecture

```
ReplicatedStorage
  Shared/           ModuleScripts (require anywhere at top level):
                    Config, ItemDefs, ItemModels, Theme, Net, Signal, Spring, Sfx, Sounds, Util, Input (client only), ArenaLayout,
                    WorldItems (spent-projectile poses and reach)
  Remotes/          RemoteEvents (section 9)
  GameState         Configuration with attributes (section 10)
  Assets/           client-visible mesh templates built by ServerStorage.WorldGen.ItemAssets:
                    Items.<itemId> (ItemModels.build), Crates.SupplyCrate1..3 (ItemModels.buildCrate),
                    Viewmodel.<R_|L_ piece> (the Classic first-person arms, kept as a fallback),
                    Viewmodel.StandardArms (default blocky R15 arms: the fallback for R6 and unusual avatars)
                    First person shows block arms by default (`Config.Viewmodel.ArmStyle = "Blocky"`, hand
                    `Blocky.Variant` "A" or "B"): `ViewmodelController.Blocky` builds them from 6 Parts at run time in
                    the avatar's arm colour, matte, with no light on them; `Shade` darkens them with the scene.
                    "Avatar" (the player's own R15 arms), "Faceted" and "Classic" are the other styles
ServerScriptService.Server
  Main              Script: loader
  Services/         ModuleScripts: DataService, PlayerService, MovementService, InventoryService, LootService,
                    CombatService, ProjectileService, ArenaService, RoundService, OnboardingService, PlusService
StarterPlayer.StarterPlayerScripts.Client
  ClientMain        LocalScript: loader
  ClientState       ModuleScript: shared client state + signals (read it before writing client code)
  Controllers/      ModuleScripts: SettingsController, CameraController, MovementController, CharacterVisuals,
                    InventoryController, CombatController, ViewmodelController, ProjectileController, AudioController,
                    ArenaController, HUDController, LobbyController, NotificationController, SpectateController,
                    WorldItemController (the Take prompt for spent arrows, knives and spears),
                    DetailController, LaunchController, LaunchIntroController, FallenRecapController,
                    LootCueController, PlusController (the lobby's Roblox Plus button, panel and member mark)
StarterGui          ScreenGuis HUD, Lobby, Overlay, Menu, Spectate (built by ServerStorage.WorldGen.UIBuilder;
                    Enabled = false at edit time; controllers enable them at runtime)
ServerStorage
  Docs/             notes
  Dev/              SyntaxCheck (compile checker), InputCheck, StudioSync (tools/studio_sync), MPTest (the two- to
                    four-client test, tools/mp_test; never runs in a live game), TrainingDummy (the practice
                    rounds' dummy template; live servers use it too)
  WorldAssets/      templates (trees, rocks, props, buildings)
  WorldGen/         re-runnable edit-time builders: TerrainGen, AssetBuilder, Populate, UIBuilder, ItemAssets
  MeshImports/      raw Open Cloud inserts of the Blender GLBs (LS_Items_v1, LS_Arms_v1), ItemAssets' input
  ArenaData/LootSpawns/   marker Parts tagged LootSpawn
Workspace
  Arena/            Spire, Plinths (Plinth01..Plinth24), POIs, Foliage, Props, Boundary, Loot (runtime), Border (client-local)
  Lobby/            lobby build + SpawnLocations
  Terrain
```

### Module contract

- Every service/controller returns a table `M` with optional `M.Init(registry)` and `M.Start()`.
- `Init` must not yield. `Start` runs in its own thread and may loop.
- Reach other services/controllers **only** through the registry passed to `Init`:
  `local Services; function M.Init(registry) Services = registry end` → later `Services.InventoryService.give(...)`.
  Never require a sibling service/controller at module top level (circular-require risk).
- Shared modules can be required at top level.
- From a controller: `local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))`.

### Version control

The code is exported from Studio to this GitHub repo. Anything that is **not** a script (UI, world geometry, templates) must be reproducible: put its construction code in a builder ModuleScript in `ServerStorage.WorldGen` with a `build()` (or `generate()`) function, and create the edit-time content by running that builder.

### Server service APIs (exact names)

- **PlayerService**: `isAlive(player) -> boolean`; `damage(player, amount, info) -> killed` with `info = { attacker: Player?, cause: "Combat"|"Fall"|"Border"|"Starvation"|"Dehydration"|"Other", weaponId: string?, position: Vector3?, headshot: boolean? }` (fires `DamageTaken` to the victim and handles death exactly once); `heal(player, amount)`; `addHunger(player, delta)`; `addThirst(player, delta)` (both clamp 0..100); `getAlivePlayers() -> {Player}`; `died: Signal(victim: Player, killer: Player?, cause: string)` (cause as in `damage`, plus "Left" for a contender who leaves and "Reset" for one who resets)
- **RoundService**: `getPhase() -> string`; `isPractice() -> boolean`; `roundStarted: Signal(roundId)`; `roundEnded: Signal(winner: Player?)`
- **InventoryService**: `give(player, itemId, count) -> number added`; `take(player, itemId, count) -> boolean`; `consume(...)` (same as take); `has(player, itemId, count) -> boolean`; `count(player, itemId) -> number`; `getEquipped(player) -> (itemId?, slot)` (nil, 0 = fists); `removeEquipped(player) -> itemId?`; `getArmorMultiplier(player) -> number` (1 = no armor); `clear(player)`; `dropAll(player, position)`
- **LootService**: `populate()`; `clearAll()`; `refillSpire()`; `spawnGroundItem(itemId, count, position, velocity?) -> Model?`; `cleared: Signal()` (after every `clearAll`); `inventoryFull(player)` (the INVENTORY FULL toast)
- **CombatService**: `applyHit(attacker: Player?, humanoid: Humanoid, baseDamage: number, info) -> (damageDealt, killed)`
- **ProjectileService**: `fire(shooter, itemId, origin, velocity, gravity, damage, opts) -> id?` (nil = refused by the in-flight caps; `opts.recoverItem` is the item left in the world); `world` = `WorldProjectiles` (`count()`, `get(worldId)`, `stats()`, `releaseFrom(model) -> number` (everything stuck in a body comes out now), `clear()`)
- **ArenaService**: `isInsideBorder(position) -> boolean`; `getFallen() -> {string}`
- **DataService**: `increment(player, key, n)`; `get(player, key) -> any`; `setSettings(player, settings)`
- **MovementService**: no public API
- **PlusService**: no public API. It publishes the Player attribute `PlusMember` and owns the remote `PlusSubscribe` (§9)
- **OnboardingService**: no public API (the analytics funnel, `docs/handoff/PublishChecklist.md` section 3)

Client controllers communicate mainly through `ClientState` fields and signals.

### Code conventions

- Luau with the `task` library (never `wait`/`spawn`/`delay`). No deprecated body movers (use LinearVelocity, AlignPosition, AlignOrientation, VectorForce). `FontFace` with Font objects.
- Validate every RemoteEvent argument on the server (typeof checks, ranges, NaN, `Util.isFiniteVector`, `Net.rateLimit`). Never trust client-reported damage.
- Disconnect per-character connections on death/removal. Don't create Instances every frame. Chunk heavy loops with `task.wait()`.
- Use CollectionService tags. Anchor static geometry. `CanTouch`/`CanQuery = false` where not needed. `CastShadow = false` on small props.
- **StreamingEnabled is ON**: clients must not assume distant parts exist (WaitForChild with timeouts, CollectionService signals); the server calls `player:RequestStreamAroundAsync(position)` before teleporting a player far.
- `Lighting.LightingStyle` is **Realistic**. Game scripts can't change it at runtime, but Studio's command bar or an Edit-mode `execute_luau` can. (`Lighting.Technology` has been retired since Unified Lighting, 2025.) Keep `PrioritizeLightingQuality` on. R15 characters are assumed; fail gracefully on R6. See `docs/research/LookDevPlaybook.md`.

## 9. Remotes (`ReplicatedStorage.Remotes`, all RemoteEvents; get them with `Shared.Net.event(name)`)

Never send arrays with nil holes — use `false` for empty entries.

**Server → client**

| Remote | Payload |
|---|---|
| Announce | `{ style = "Banner"\|"Toast"\|"Warning"\|"Countdown"\|"RollCall"\|"Victory", text, sub?, duration?, names? }`; a `Victory` also carries `winner` (display name) and `winnerUserId` |
| KillFeed | `{ killer: string?, victim: string, killerUserId: number?, victimUserId: number, weapon: string?, weaponName, cause: string, text? }` (`text` = "left the arena" for a leaver) |
| YouDied | `{ placement, total, killer: string?, killerUserId: number?, cause, weapon: string?, weaponName, headshot, phase ("Active"\|"Countdown"), practice }` |
| Sfx | `(key: string, opts { position?, volume?, pitch? }?)` — used by `Shared.Sfx` |
| InventoryUpdate | `{ slots = { [1..6] = { id, count } \| false }, equipped (0 = fists), armor ("" = none) }` |
| ProjectileFired | `{ id, shooter (UserId), itemId, origin, velocity, gravity }` |
| ProjectileImpact | `{ id, position, normal, hitCharacter: boolean, part: BasePart?, material, itemId, headshot, recovered, worldId?, pivot?, rel?, fallTo?, fallTime?, sink? }` (the item left in the world, its pose, relative to `part` when stuck to it, and the fall or sink that follows) |
| HitConfirm | `{ damage, headshot, killed, position?, target = "Player"\|"Dummy", weaponId?, melee }` to the attacker |
| DamageTaken | `{ amount, fromPosition: Vector3?, cause }` |
| CombatAction | `{ userId, action = "Swing"\|"Draw"\|"Release"\|"Throw", itemId, cancelled?, variant?, lead? }` to the other players within 220 studs. `variant`: the swing's set, 1-8. `lead`: seconds from this message to the swing's strike (the windup when sent at the swing's start, 0 when announced at the strike) |
| RoundSummary | `{ winner: string?, duration, placements = { { name, placement, kills } } }` |

**Client → server**

| Remote | Arguments |
|---|---|
| EquipSlot / DropSlot / UseStart / UseFinish / UseCancel | `(slot: number)` (EquipSlot 0..6). EquipSlot is limited to `Config.Inventory.EquipRequestsPerSecond` (8); a request over the limit isn't dropped: the latest slot is applied a moment later |
| Drink | `()` |
| MeleeSwing | Two forms. At the swing's start: `("Start", variant: number?)`. At the strike: `(lookDirection: Vector3, predictedHit: boolean, variant: number?, target: Model?, startTime: number?)` — `predictedHit`: the attacker's own trace touched someone (with false the swing never lands); `variant`: the swing's set, 1-8; `target`: the body that trace touched, the only one the server checks; `startTime`: `workspace:GetServerTimeNow()` when the swing began on the client (§6). The message changed shape on 18 November: client and server ship together |
| RangedRelease | `(shotId: string, origin: Vector3, direction: Vector3, charge: 0..1, mode: "Fire"\|"Throw"\|"Draw"\|"Cancel")` — `Draw`: the bow draw started (the server records it and times the charge); `Cancel`: the draw was let down; `Fire` needs a recorded `Draw` (§6) |
| SetStance | `("Stand"\|"Crouch"\|"Slide"\|"Climb")` |
| SaveSettings | `({ [string]: number })` |
| SpectateTarget | `(target: Player?)` — server sets the requester's ReplicationFocus so streaming follows the spectated contender; kept through Active and Ending. Limited to 2 a second (burst 6); over the limit the latest target is applied a second later |
| TakeWorldItem | `(worldId: number)` — take a spent arrow, knife or spear (the server checks reach: PickupRange + 2, no higher than PickupReachAbove + 1.5 above the root) |

**Roblox Plus** (`PlusService`, `PlusController`). One more RemoteEvent, `ReplicatedStorage.Remotes.PlusSubscribe`, is created by `PlusService` at start. It is not in `Net.Names` on purpose: the game works unchanged without the service.

| Direction | Arguments |
|---|---|
| client → server | `("state")` — ask whether the lobby may show the button (once at start) |
| client → server | `("subscribe")` — the player pressed SUBSCRIBE in the panel they opened themselves |
| server → client | `("state", offer: boolean)` |

`PlusService` reads `Player.HasRobloxSubscription` on join and on change and publishes it as the Player attribute `PlusMember`. The offer is true only when the prompt API exists, the player is not a member, and `PolicyService:GetPolicyInfoForPlayerAsync` says `IsEligibleToPurchaseSubscription` (a failed call counts as no). On `subscribe` it calls `MarketplaceService:PromptRobloxSubscriptionPurchase(player)`, at most once per 10 s per player and never for a contender in the arena. Nothing opens the window on join, spawn, round start or end, or touch; nothing is granted for pressing or closing; no price is in the game's own text; every Roblox call is in a pcall. The member perk is cosmetic and nothing in a round reads it: at `e2226af` `PlusController` adds "· PLUS" to a member's lobby name tag; **†** it is a small PLUS billboard over the member's character in the lobby. `PlusController` also shows "PRIVATE SERVER" above the lobby title when `GameState.PrivateServer` is true. Studio only: workspace attribute `PlusTestOffer = true` shows the offer to a tester who is a member; **†** `PlusTestMember = true / false` makes every player count as a member or a non-member.

## 10. Attributes and tags

- **GameState** (`ReplicatedStorage.GameState`): Phase, PhaseEndsAt (a `workspace:GetServerTimeNow()` timestamp), AliveCount, StartedCount, RoundId, Practice, SoloStartAt (when a lone player's practice round picks its contenders, 0 otherwise), MinPlayers, LobbyCount, BorderCenter (Vector3), BorderRadius, BorderTargetRadius, BorderShrinking, ArenaEvent ("" or "Feast"), WinnerUserId (set before WinnerName and cleared with it; 0 = none), WinnerName, PrivateServer (true on a private server), BorderStartRadius (the round's starting ring), RoundStartedAt, Clock (day/night time base: `DayCycle.decodeClock` → clock at a server time + rate; clients evaluate it every frame), Day, RollCall (JSON of the running Roll Call show, nil otherwise), LaunchAt / LaunchRise / LaunchDepth (the launch plates' rise), LaunchCut ("Full" | "Short" | "") / LaunchCallAt (the launch intro)
- **ReplicatedStorage.FallenSnapshots**: anchored avatar models of this round's fallen (for the Roll Call busts)
- **Player**: Alive (alive contender this round), InArena, Frozen (movement locked), Hunger, Thirst, Armor (item id or ""), Kills (this round), Placement, Wins, TotalKills, RoundsPlayed, SettingsJson, KilledBy (the killer's UserId, or 0), Launched (has seen the full launch cut this session), PlusMember (Roblox Plus member; cosmetic). On the LocalPlayer only: ShaderTier, ShaderDevice, DetailSources (`DetailController`)
- **Character**: Stance ("Stand"|"Crouch"|"Slide"|"Climb"), set by the server from SetStance
- **workspace.Arena**: Center (Vector3), PlayRadius; children Plinths, Boundary, SpirePlatform (covers the launch trench), Waterfall (particle curtain), and the set dressing from `Populate` (§11): Landmarks (the Spire), POIs, Camps, Cliffs, Forest, Flora, Rocks, Ambience. **workspace.Terrain**: ArenaTerrainReady (true once terrain generation is done), TerrainVersion (2), TerrainGenStatus / TerrainGenProgress (the last generation)
- **CollectionService tags**: LootSpawn (marker Part with attributes Tier 1|2|3 and Kind "Crate"|"Ground"), Climbable, NoMantle, AmbientEmitter (Part with attribute SoundKey), Plinth, TrainingDummy, WorldProjectile (a spent arrow, knife or spear in `workspace.Arena.Loot.Projectiles`; attributes ItemId, WorldId, Shot, and Host / HostPart while it is in a body), LooseProjectile (one that can be taken now)

## 11. World layout

`Shared.ArenaLayout` (v2, the classic forest arena) is the single source of truth, and `ServerStorage.WorldGen.TerrainGen` (v2.1; `workspace.Terrain` attribute `TerrainVersion` = 2) builds the terrain from it: seeded, deterministic, re-runnable in Edit mode in about 3 s with `require(game.ServerStorage.WorldGen.TerrainGen:Clone()).start({ lighting = false, streaming = false })`. A run also re-places the SpirePlatform, the plinths, the loot markers, the waterfall effect and the Boundary, and rewrites TerrainData. `TerrainGen.verify()` / `check(name)` re-run the reviewers' checks (water edges, tubes, fords, mountains, voxels, plaza, lattice). Nothing regenerates the world at runtime. Angles are degrees clockwise from north (−Z), east is +X, `ArenaLayout.polar(angle, r, y)`.

- **Heights.** The Spire plaza is a flat disc r ≤ 62 at `PlazaY` = `BaseHeight` = 46. The meadow undulates 42-53. The lake surface (`LakeLevel` = `WaterLevel`) is 34 and the marsh pools 36.5. The border starts at play radius 640; between it and the invisible Boundary (r 712) a continuous cliff band rings the arena (`MountainWall`: an 18-stud sheer step at r 651-700, then ~75° and ~54° faces), so no route leads out on foot, by jumping or by mantling; and terrain runs out to r 920 (snow above about 300). The lobby island top surface is at `LobbyPosition` (2600, 160, 0).
- **Launch plates.** `Plates[i]` holds 24 CFrames at r 52, plate i at (i − 1) · 15°, facing the Spire, Y = `PlazaY`. 4-stud voxels cannot make 24 separate clean shafts 13.6 studs apart, so the terrain has one annular trench under the plate band (floor y 34, at least `PlateTube.radius` 3.6 clear round every axis) and the realistic SpirePlatform (`workspace.Arena.SpirePlatform`, pivot (0, 46, 0), walking surface 46.6) covers it, leaving its 24 granite-lined openings; keep the platform in place. `TerrainGen.placePlinths()` stands the `workspace.Arena.Plinths` models on the plates.
- **Water.** Roblox only shows a water surface whose voxel holds no solid, and banks reach ~1.8 studs over a neighbouring voxel, so channels are at least ~2 voxels wide, shallow water is at most 2 studs deeper than designed, and ford levels sit in the lower half of a voxel layer (fords ~0.5-1.2 deep). The waterfall is a particle curtain (`workspace.Arena.Waterfall`), not terrain water.
- **Biomes** (`getBiome(position)`):
  - **Meadow**: the centre, edge r 125-178.
  - **Forest**: the ring of rolling, eroded hills.
  - **Lake**: S/SE, with an island.
  - **Gorge**: N. The river rises at r 632, cuts a stratified gorge, falls 32 studs into a plunge pool at 36° / r 386, then meanders E/SE to the lake.
  - **Cliffs**: the W/NW escarpment, with three caves.
  - **Field**: E/NE tall grass.
  - **Marsh**: SW.
  - **Mountains** and **Lobby**.
- **Set-dressing data.**
  - `POIs` (with `POIHeights`), `POIKits`, `Caves`, `Crossings` (fords, the fallen-log spot and the footbridge, with `CrossingHeights`), `Trails`, `Clearings` and `MistHollows`.
  - `Scatter`: per-biome rules that name the realistic assets. `AssetInfo` holds their sizes.
  - `Exclusions` / `isExcluded`, and `LootZones` / `lootTierAt` / `dangerAt`.
  - Ground queries: `groundAt`, `heightAt`, `normalAt`, `slopeAt`, `waterAt`, `isWater`, `moistureAt`, `distanceToCliff`, `distanceToWater`, `distanceToRiver`, `distanceToTrail` and `forestEdgeDistance`. The grid-backed ones read `ServerStorage.WorldGen.TerrainData`, an 8-stud grid that TerrainGen writes.
- **Loot markers** (`ServerStorage.ArenaData.LootSpawns`) are re-seated on the ground (or the platform deck) by every terrain run: out of water, steep ground, the Spire footprint and the trench.
- **Terrain materials** are PBR MaterialVariants in `MaterialService`, applied as base-material overrides: meadow grass, forest floor, earth, mud, sand, river pebbles, lichen granite, shale and scree. Snow keeps Roblox's own material. See `TerrainGen.MaterialVariants` and `Palette`.

### Set dressing (`ServerStorage.WorldGen.Populate` v2)

`Populate` places clones of the realistic templates in `ServerStorage.MeshAssets` across the arena and the Tor. It is seeded (`ArenaLayout.Seed`), deterministic, chunked and re-runnable in Edit mode: `local P = require(game.ServerStorage.WorldGen.Populate:Clone())`, then `P.start()` (every step on a background thread, about 11 s; progress in the `workspace.Arena` attributes `PopulateStatus` and `PopulateLog`), or one step at a time: `placeCore`, `placePOIs`, `placeCamps`, `placeCliffs`, `scatter(biome?)`, `buildLobby`, `ambience`. Finish with `P.fixLoot()` (moves any loot marker that scenery blocks), `P.verify()` (gameplay checks) and `P.looks()` (look checks). `P.report()` prints the counts. Each step clears only what it owns. **Re-run it after any terrain rebuild:** TerrainGen moves the ground, not the scenery; then re-run `ServerStorage.WorldGen.WaterPointsBuilder` if the water moved, since the dressing keeps the drinking points open. The part-built v1 is archived in `ServerStorage.Archive_v1` (`Populate_v1`, `Plinths_v1`, `Lobby_v1`).

- **Outputs.**
  - `Landmarks.Spire`: at `Center`, unrotated, pivot (0, `PlazaY`, 0), Persistent. Its child Parts `CrateSlot_1..4` are tier-3 LootSpawn markers in the four niches. They carry `DropIn = false`, so the Offering restocks them in place instead of dropping a crate through the Spire (`LootService.refillSpire`).
  - `Plinths.Plinth01..24`: the realistic Plinth on the SpirePlatform's `Plate_n` attachments. Each has the `Plinth` tag, the `Stand` attachment, `Index` and `PlateOffset` 0.6, and is Persistent. The launch lowers and raises all 24 by 10 studs with their contenders.
  - `POIs`: HunterCabin (4.6 studs behind the POI centre, so the Cabin trail ends in front of its porch), Watchtower, Footbridge (`EndA`/`EndB` on the rims, the deck 1.2 under the rim height so its end sills meet the rims within 0.3-0.4 studs; its end-frame logs are stretched ×1.65 upward, so the cross logs stand 7.0 studs over the deck), the gorge log, stepping stones, a CaveMouth on each cave, the falls rim, the island, the overlook, the giant OakA (×1.6, climbable), the field boulder, the dead stand and a landmark beside each runner's cache (the rules owner's suggestion, or a BoulderC / StumpA where it finds no spot that keeps the clearings free; such a piece carries the attribute `InsteadOf`).
  - `Camps`: six abandoned campsites. They are cold, except CampNorth and CampWest, which smoulder.
  - `Cliffs`, `Forest`, `Flora`, `Rocks`, and `Ambience` (AmbientEmitters for the river, the falls, frogs, wind and the two smouldering fires).
- **Dressing rules.**
  - **Density.** The scatter follows `ArenaLayout.Scatter` for each biome, plus `Populate.Scatter.ADD` (marsh sedge and tufts, lake beach grass), in four passes: trees, then rocks, logs and stumps, then bushes, then ground cover and reeds. Within the tree pass the widest-spaced rules go first (oaks and snags before the dense conifers). After its seeded grid, each rule keeps seeding clumps at random until it reaches **its density × the biome's area inside the play radius**, so exclusions no longer leave stands thin; it stops short only where no valid ground is left, and the log names the reasons (`[refused: ...]`). Extra per-rule limits (wider windows for oaks, birches, pines, mushrooms and moss, ferns and moss on rock ledges in the gorge and the cliffs, the lake rules' shore band) are in `Populate.Scatter.EXTRA`.
  - **Kept clear:**
    - the plaza and plate ring (r < 70) of everything; the meadow core (r < 100) of everything but ground cover;
    - trails: trees stay 3.5 studs plus their trunk from the centreline, bushes and rocks 3 studs plus their radius, ground cover 1.6 studs; and no rock, log, stump, cliff piece or set piece stands in a trail's walking space (an upright cylinder 5.6 wide and 3.6 tall from 1 stud above the ground at every trail sample, `Ctx.blocksTrail`);
    - crossings (their walking line, 8 studs past each landing, on the deck or the bed);
    - cave mouths (a 3.4 × 5 box from 6 studs inside to 12 out);
    - POI footprints (the big buildings by their whole footprint);
    - **loot:** every crate (4.5 studs) and ground item (3 studs) and each runner's cache (6 studs) keeps its clearing free of every piece's **whole bounding box**, crowns, skirts and fronds included (`Ctx.lootClear`); big rock pieces are tested on their collision instead (`Ctx.blocksLoot`);
    - **water:** every drinking point (`Shared.WaterPoints`) keeps a 2 × 3.6 wading box free at the point or 1.5 / 3 studs beside it, and so does every centreline sample of the river, the creek and the outflow for the cliff pieces (a stream may be narrowed, never closed).
  - Trunks, rocks, logs and stumps never overlap, and ground cover never sits inside a trunk or a rock. A low-frequency stand-density field (×0.35 to ×1.75) on trees and young conifers makes thick stands and open glades.
  - **On the ground:**
    - Trees stand upright, with the pivot on the lowest ground round the trunk.
    - Rocks, logs, stumps, POI rocks and cliff pieces are **seated** (`Ctx.seat`): a grid of columns under the piece measures the air between its underside and the ground, and the piece is lowered until half of them (cliff pieces: 60% of the front half) rest on the ground.
    - Flora and rocks follow the ground normal, with random yaw. Logs lie along the contour and touch the ground at both ends; the gorge's logs span the stream from bank to bank, long enough that a third of each end rests on a bank.
    - Reeds and sedge get a wider scale (0.6-1.45), a lean of up to 9°, a non-uniform stretch (height ×0.72-1.35, width ×0.8-1.25), beds that come and go with a noise field and clumps of varied spread, so the marsh and the lake shallows don't repeat one clump.
    - Nothing that grows on land stands in water deeper than 0.6 studs; plants don't grow on bare rock, except ferns and moss on the ledges of the gorge and the cliffs. Beyond r 650, scenery is visual only: no collision and no queries.
  - **Copies:** Atomic streaming, CanTouch off, scatter copies drop the template attributes, CastShadow off on roots and on anything under 3 studs tall, RenderFidelity Automatic, CollisionFidelity as built (Box or Hull; PreciseConvexDecomposition only on cliffs, cave mouths, buildings and the climbable OakA).
  - Crown parts keep their names (Foliage, Branches, Leaves) with CanQuery off, and trunks stay queryable, so the Roll Call's canopy lift keeps working. `OakA_Bark` keeps the Climbable tag.
  - **Cliffs.** CliffFace pieces skin the escarpment, the gorge walls and the falls bowl; RockOutcrops line the escarpment rim. Then a **coverage pass** works from what players see: observers on walkable ground (6-stud grid, slope under 20°) in the Gorge and the Cliffs cast 16 level rays at eye height (5.2 up, 45 long); the 12-stud cell with the most hits on bare steep terrain gets a piece fitted to its face (a CliffFace sized to the face and leaned back to its slope about its front foot, standing up to 2.5 studs in front of the wall's bulges; boulders on low banks and, first, in the winding gorge), and every 12 pieces the rays are cast again (`Sites.COVER_BUDGET` 150), then up to 60 touch-up boulders (`Sites.TOUCHUP_BUDGET`). Every cliff piece must keep trails, loot clearings, cave mouths, crossings and the streams open, and its front must rest on the ground, or it is removed.
  - **The Tor:** the LandmarksReal set replaces the v1 parts: 4 Pavilions, 4 LobbyGates, 9 Braziers (one is the central fire), 8 BannerPoles, 10 Benches, 2 NoticeBoards, 66 Railing segments and 4 StoneSteps, with a realistic garden and **a climbable OakA** (`Lobby.OAK_*`, v1's Oak_A). The 9 fires burn: v1's Flame, Embers and Smoke emitters (27), scaled to each bowl, on a `FireFx` attachment at the coals' top; the flames are half-additive (LightEmission 0.4, Brightness 2.2) so they read against a daylight sky. The terrace, the 8 SpawnLocations, the invisible barrier and the notice text are kept.
  - **Lights:** only the Spire's Beacon and the Tor's central fire cast shadows (20 lights are enabled in all).
- **Scaling with the graphics quality** (`StarterPlayerScripts.Client.Controllers.DetailController`). On each client, beyond a draw distance from the camera, it hides (LocalTransparencyModifier, this client only) the ground cover, ferns, tall grass and reeds, the trees' branch cards and root flares, and, at Low only, whole trees, logs and stumps past 420 studs. Bushes, rocks, cliffs and buildings are never hidden, and within fighting range every tier sees the same cover.

  | Tier | Tufts, flowers, moss | Ferns | Tall grass, reeds | Branch cards | Roots, moss | Whole trees |
  |---|---|---|---|---|---|---|
  | High | 220 | 300 | - | - | - | - |
  | Medium | 130 | 180 | 260 | 320 | 220 | - |
  | Low | 70 | 110 | 170 | 160 | 100 | 420 |

  The tier comes from the workspace attribute `DetailTier` (tests), else the player's graphics level (`SavedQualityLevel` 1-3 Low, 4-6 Medium, 7-10 High), else on Automatic High on PC and consoles and Medium on touch-only devices, one tier lower while a live client stays under 40 fps for 6 s. Roblox's own quality levels do not reduce mesh geometry (measured: Level03 drew more triangles than Automatic), so this is the only lever. A LocalScript can't read Studio's render quality or the engine's running quality level; the controller publishes what it can read as the LocalPlayer attribute `DetailSources`.
- **The Shaders setting** (Menu → GRAPHICS → "Shaders: Off / Auto / Full"; `ClientState.settings.shaders` 0 / 1 / 2, saved with the other settings by `DataService`). `DetailController` turns it into the LocalPlayer attributes `ShaderTier` ("Off" | "Phone" | "Mid" | "High") and `ShaderDevice` (the tier the device would have on Auto), which `ArenaController.Sky` reads; `Shared.DayCycle` (`Tiers`, `applyTier`) scales bloom, sun rays, haze, the fill light, the water tracks, how often the look is written and the mist caps. Auto maps the detail tier (Low → Phone, Medium → Mid, High → High; a touch-only device on automatic is Phone), Full is High, and Off switches bloom and the colour grade off. The launch intro uses no bloom when Shaders is Off. `DayCycle` holds one look per arena, picked by `Config.Map` (`GreenLand`, `ClassicForest`). Studio only: workspace attribute `DevShaders` forces a tier, and `DevLookHour` pins the look's hour. On Map 1 `DetailController` also fades each far-valley canopy shell (`FarCanopy`) when the camera is within 450 to 650 studs of its footprint, and reads `DetailTier` in Studio only.
- **Budgets** (measured on 11 November 2026 on the dev PC, in solo playtests).
  - **Counts.** 28,490 models in `workspace.Arena` (122,312 instances, 46,612 parts, 40.9M mesh triangles at full detail, 16,317 shadow casters, 8,107 colliders). That includes 3,308 trees (plus 893 young conifers and 245 saplings), 2,131 bushes, 5,577 ferns, 6,938 grass tufts, 3,833 tall-grass and sedge clumps, 862 flower patches, 1,466 moss patches, 511 mushroom clumps, 799 reed clumps, 367 logs, 245 stumps, 982 rock pieces and 172 cliff pieces (before this pass: 1,654 trees, 639 young conifers, 1,570 bushes, 3,908 ferns, 6,120 tufts, 2,935 tall grass, 637 rocks, 36 cliff pieces). The Tor holds 210 models (1,634 instances). The client held 187,600 instances during a solo round (143,200 before this pass, 64,700 before any dressing).
  - **Scatter fill** (placed / density × area inside the play radius): every forest rule 100-102%; marsh 100-109%; lake reeds 290/290, shore stones 33/32, shore rocks 46/45, beach grass 129/129, driftwood 4/10, ledges 0/3 (the lake biome's dry shore is a thin ring); gorge ferns, moss and stream rocks 100%, conifers 37/61, logs 3/9; cliffs 79-100%; meadow 80% by design (its rules keep the plaza apron and the core open). Forest trees per 40 × 40 cell: median 5, p90 8, max 13, 17 of 608 cells empty.
  - **Frame time.** Studio throttles its unfocused window to about 15 frames a second (RenderStepped 14.5-15.0/s even in an empty view), so 60 fps can't be observed here; the render thread is the measure: 3.5-4.3 ms per frame (6.7 ms once), and CPU 3.2-4.7 ms, at the plate during the launch and in the densest forest cell. GPU frame time read 0 (not reported in this session).

    | View | Tier | Triangles drawn | Draw calls | Batches | Render thread |
    |---|---|---|---|---|---|
    | Plate 6 looking out, just after the launch | High | 4.66M | 428 | 649 | 4.1 ms |
    | same | Medium | 3.44M (-26%) | 390 | 571 | 3.7 ms |
    | same | Low | 2.50M (-46%) | 346 | 493 | 3.5 ms |
    | Densest forest cell, eye level | High / Medium / Low | 0.72M / 0.70M / 0.68M | 160 / 155 / 154 | 262 / 252 / 247 | 3.8 / 3.6 / 4.3 ms |
    | Plate 1 looking out, Studio quality Automatic / Level03 / Level01 | High | 5.42M / 7.59M / 5.42M | 445 / 523 / 446 | 684 / 790 / 684 | 3.9 / 4.2 / 4.0 ms |
  - **Memory.** In Studio `GetTotalMemoryUsageMb` reports the whole Studio process (9.9 GB here, with the Edit and Server copies, plugins and the undo history of the rebuilds), so it can't stand in for a phone. The client-only graphics tags read: textures 115 MB, mesh parts 6 MB, parts 78 MB, terrain 67-71 MB, particles 16 MB, spatial hash 9-10 MB. Measure on a 3 GB Android phone with the Developer Console.
  - **Knobs.** `Populate.DENSITY_SCALE` (every scatter rule), `Populate.Scatter.DENSITY` (per class) and `Scatter.EXTRA` (per rule, incl. `fill`); `DetailController.TIERS` (draw distances). If a phone runs short, first lower `DENSITY.groundCover` (about 13k flora models), then young conifers and bushes. Never thin the trees at the meadow edge, which the plates look at.
  - **Streaming** (`TerrainGen.applyStreaming`): StreamingEnabled, StreamingTargetRadius 1024 (the whole arena and its mountain backdrop load from the plaza), StreamingMinRadius 128, StreamOutBehavior Default on the classic arena (content streams out under memory pressure) and Opportunistic on Map 1 (`Map1.Terrain.applyStreaming`, set 18 November), StreamingIntegrityMode PauseOutsideLoadedArea. The Spire and the plinths are Persistent; everything else is Atomic.
- **Checks** (`P.verify()` and `P.looks()`, the numbers of this pass): plaza and plates 0 scenery; trails 0 of 1,515 four-stud segments blocked on the centreline by a 2 × 3.6 box sweep (18 at 2.5 studs to either side, by the bridge's posts, trunks just outside the walking width and two cliff pieces); crossings 0; the footbridge deck sweep 0 with 7.0 studs of headroom under its end frames; cave mouths 0; 181 loot markers: 0 inside a collider, 0 without a standing spot in reach, 0 not resting; loot clearings overlapped by foliage: crates 0 of 44, ground items 0 of 129 (by rock pieces, collision-clear: 4 and 3); runner's caches 8 of 8 clear within 6 studs by footprint, each with a landmark; floating: 1 of 1,770 placed pieces has air at all 5 support samples (the CampSouth tent, whose hollow inside is sampled; its edges stand on the ground); eye-level cliff facets (bare terrain among steep hits): Gorge 37%, Cliffs 10%; 106 climbable OakA in the arena and 1 on the Tor; crowns 0 queryable.
- **Known limits.** The Watchtower knoll rises at 42-43° for the 5 studs above the EastFord trail's end, so a contender walking straight up from the trail stalls; the Marsh trail ends in a pool that a contender wades into and stalls in. Both are terrain, with no scenery collider within 4-5 studs. Runner's caches 1 and 2 (the rules owner's spots) are hidden by terrain from the eye on their nearest plate; their 10-stud poles are seen. TreesReal card foliage still reads flat within 8-15 studs (art limit, `art/README.md` 11.7). The CampSouth tent is reported as floating by the 5-sample check (a false positive: hollow tent). A contender at the QA's point in the rock pocket under a CliffFaceC piece in the Cliffs (root at (−330.2, 85.7, −285.2)) can't walk or jump out: the piece's underside is at head height, so the wedge escape's jump (§2) gets no lift. Reset is the way out; walking in from the north ends in a low crawl space you can leave.

## 12. Studio test support

- `Config.Studio.SoloTest` and `FastTimers` apply only in Studio.
- Studio's solo test (`MinPlayers` 1) never runs the live practice flow (the solo wait, the 8 s Intermission before the next practice round). To try it in a playtest, set `Config.Round.MinPlayers = 2` and the `GameState` attribute `MinPlayers` to 2 on the server, and the live timers (`IntermissionTime` 25, `CountdownTime` 10, `EndingTime` 10) on the server and the client.
- `ServerStorage.Dev.SyntaxCheck` compile-checks scripts in Edit mode without running them:
  `return require(game.ServerStorage.Dev.SyntaxCheck).run({ roots })` from `execute_luau` (Edit).
- Lighting at any hour in Edit mode: `require(game.ServerStorage.WorldGen.LightingRig:Clone()).preview(19.2)`; `.apply()` restores the lobby look. The look lives in `Shared.DayCycle.Looks` / `Knobs` (tuned for LightingStyle Realistic; it also drives DepthOfField far blur, `Terrain.Clouds` and the base `Workspace.GlobalWind`, to which clients add gusts). `Knobs.HandoffDusk` / `HandoffDawn` hold the measured sun/moon switch hours.
- Roll Call on demand (Studio play, server command bar): `game.ReplicatedStorage.GameState:SetAttribute("DevRollCall", 6)` shows six fake fallen made from your own avatar (`0` = the "no one fell" version). `GameState:SetAttribute("DevRecapFreeze", 11.5)` holds a running show at that second of its timeline for screenshots (`nil` lets it run on; the show still ends when the server clears `RollCall`). `Config.Round.StudioTimeScale` fast-forwards the whole day/night schedule; to hold a particular hour in a playtest, a temporary server Script can set `Config.Round.DaySchedule` (e.g. `{ { 0, 20.4 }, { 900, 21 } }` for a moonlit night) once the phase is Active.
- A real multiplayer test: `require(game.ServerStorage.Dev.MPTest:Clone()).start({ batch = "B", clients = 2 })` from Edit mode starts a server and 2 to 4 clients as separate Studio processes and plays scripted rounds between them (`tools/mp_test/README.md`). Test players have UserIds -1, -2, ...; DataStores and real ping are not covered. `DevRollCall` accepts up to `MaxContenders - 1` (47) fake fallen.
- The lobby fill rule in Studio: setting the `GameState` attribute `FillTest` to any number turns the rule on, and each change of its value counts as a player joining. `LaunchCutTest = "Full" | "Short"` forces a launch cut.
- `CombatService._refusals`, `_trySwing`, **†** `_meleeFront` and `_recentTravel` (server) and `CharacterVisuals._poseStats` and `_lod` (client) are test hooks.

## Manual steps (can't be done by scripts)

- ~~Lighting → LightingStyle → **Realistic**, with PrioritizeLightingQuality ticked.~~ Done on 11 November 2026 from the Edit datamodel; game scripts can't change it at runtime. The old "Technology → Future" setting is retired.
- Game Settings → Avatar → **R15**.
- Game Settings → Security → **Enable Studio Access to API Services** (to test saved stats in Studio).
- Server size: Creator Dashboard → the game → Configurations → Places → the start place → Access → **Maximum Visitor Count 48** (it read 60 on 18 November 2026; scripts can read `Players.MaxPlayers` but not set it). The launch's other dashboard steps are in `docs/handoff/PublishChecklist.md`, section 4.
