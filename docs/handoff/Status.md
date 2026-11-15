# LAST STANDING: where things stand (14 November 2026)

The Studio place (placeId 120572716460286) was saved as **version 199**, labelled as the restore point before the bigger arena. Today's release fixes (next section) were saved on top of it as **version 258**. Nothing has been published to players yet.

Every script up to version 258 is exported to `src/`, verified byte for byte against Studio; `src/manifest.json` lists them. Each area below was built by one agent, then checked by an independent tester, with a fix round wherever the tester found problems.

## Release fixes (14 November), after version 199
Four bugs from the QA sweep (26 solo playtests), the wait between practice rounds, and your 90 headshot. Each fix was made by one agent (the headshot value by the lead) and checked by an independent reviewer; the melee reach and the wedge escape needed a second round after review. A final tester then played all of them together in 5 Studio playtests, with real keys and mouse clicks, and found no functional regressions.

### What changed, and what the final check confirmed
- **Training dummies on live servers.** Only Studio practice rounds had them: a Studio-only switch in `CombatService` kept them off live servers. Now every practice round has its 3 dummies, live servers included. A round with 2 or more players never has them.
  - **Confirmed:** 3 dummies in every practice round of the final check, and none left once the round ended. The fixer also ran the live-server path in Studio with live settings: the solo wait, then a practice round with 3 dummies in front of the plate.
- **Your view faces the Spire at the start.** Your view used to keep the way you faced in the lobby, so you could rise looking away from the Spire, and your body flipped between two facings during the rise (the QA counted about 16 flips in 4.6 s). Now the view turns to the Spire once, when you land on your plate, and you can look around freely after that.
  - **Confirmed** on 4 plates, with the lobby view 60-150° away: the view sat exactly on the Spire from the plate, through the rise, until 2.4 s after the horn, with no flips. A turn with the arrow keys during the countdown held through the horn, with no snap back.
- **Getting unstuck.**
  - **The wedge escape.** Held fast for a second in a rock pocket or a V between two steep faces, you now get one jump, mantle or climb out. It reaches no higher than a normal jump from the last ground you stood on, so it can't be used to climb cliffs.
  - **Reset in the arena.** Reset (Esc, R, Enter) now works in the arena once the horn has sounded. On your plate during the countdown it still does nothing. It counts as an elimination (someone who hit you in the last 15 s gets the kill), and the death card says "You reset".
  - The reviewer found two gaps in the first version: from some spots the escape reached half a stud higher than a jump from the ground, and you couldn't steer while held fast. The second round closed both. In the fixers' test pits with 60° sides, you now get out of a 4-stud-deep one with one mantle; a 10-stud-deep one still needs Reset.
  - **Confirmed:** cliff faces and the mountain wall still can't be climbed (the highest points reached match the old code to within a jump's noise). Reset in the arena killed you at once and sent you to the lobby, and the death card read "PRACTICE ROUND · FALLEN · You reset". The QA's rock pocket still holds you (see "Still open").
- **Melee reach.** The server used to land swings that missed on your screen (the QA had sword hits at 11.5 and 13.3 studs, and a spear hit at 14.5). Now a swing lands only if it hit on the attacker's screen, and the server still checks it.
  - The reviewer found two problems in the first version: hits seen on a player moving away were refused, and a cheat could reach further than before. The second round fixed both: against anyone who can move, the server allows the old reach, and no swing reaches further than that.
  - **Confirmed:** sword at 7, 8, 9 and 10 studs: a hit on screen and on the server (40 each). At 11 studs: a miss on both. The fixers found the same edge for the knife (8 studs hits, 9 misses) and the spear (11.5 hits, 12.5 misses), and against a target moving away at normal speed (13 studs/s) all 23 hits seen on screen landed.
- **Bow headshot 90.** A full-draw headshot now does 90 instead of 100 (`Config.Combat.BowHeadshotMultiplier` 1.8, your note), so one arrow can't kill from full health. A full-draw body shot still does 50.
  - **Confirmed:** 90 to the head and 50 to the body at 12 studs. Arrows landed 0.05-0.35 studs from the crosshair point, out to 30 studs.
- **Shorter wait between practice rounds.** Still alone after a practice round, you now go again after an 8-second Intermission instead of the whole wait: about 28 s from death to the next horn (it was 75 s). A newcomer still gets a practice round about a minute after joining, and a player who arrives makes it a normal round.
  - **Confirmed** with live timings: 28.35 s from death to the horn, with the lobby counting "PRACTICE ROUND IN 0:08" down to 0:00.
- **The whole round.** A practice round sped up 6 times ran from start to finish: a crate, eating, drinking, the Offering, the border, the Last Stand, the Roll Call, the result card, the lobby and the next round. SyntaxCheck: 111 scripts compiled cleanly. The console was clean in all 5 playtests, apart from Studio's usual DataStore note.
- **Scripts changed** (11, at the sizes the final tester confirmed in Studio): `CombatService` 38,125 bytes, `CombatController` 36,337, `CameraController` 29,486, `LaunchController` 24,367, `MovementController` 109,975, `HUDController` 77,301, `NotificationController` 64,360, `PlayerService` 37,183, `RoundService` 29,035, `LobbyController` 16,078 and `Config` 25,176.

### Still open
- **The QA's rock pocket** under a cliff face in the Cliffs (about −330, 86, −285) still holds you: walking and jumping can't get you out, because the rock's underside is at head height. Reset gets you out at once.
- **Crate items, once.** In one test round the items spilled from a crate couldn't be taken with E until the tester jumped. The next round worked (Take all, then Take). The loot code wasn't changed today, and the cause is unknown.
- **The lobby flashes "WAITING FOR PLAYERS 1 / 2"** for about 0.1 s before the 8-second practice countdown. Cosmetic.
- **The Roblox menu after Reset** reported itself open again right after it closed. That's most likely the test's simulated keys; check by hand that it closes.
- **Melee, the trade-offs of the new rule:**
  - The attacker's game now decides misses. If its swing prediction (`CombatController.predictMelee`) ever breaks, melee stops landing for everyone.
  - A cheat that always claims a hit reaches no further than before against players, and 1.1 studs past the honest reach against dummies.
  - Studio can't show real ping. On a laggy server, a hit you see on someone moving sideways may still be refused, as before.
  - The check counts on the camera and combat scripts running in today's order each frame. If their render priorities change, the reach allowance shrinks to about 0.1 stud.
- **Never tested with 2 real players:** no dummies in a 2-player round, the practice hand-off, and a sword hit on a moving player rest on code reading and a stand-in target. See check 2 below.
- **Small tidy-ups, for later:** the "late impact" sound in `CombatController.onHitConfirm` can no longer play; the 0.85 swing-radius factor is written in two scripts; and two comments are out of date (the `DummyBuilder` header still says "Studio practice rounds", and the `Config.Combat.MeleeLagTolerance` comment doesn't mention the melee cap).
- **Checking the bow in Edit mode:** a `require` of `Config` there can still return the old 2 from Studio's cache. Check it in a playtest.
- **Not in today's fixes** (the rest of the QA list, at your call): the day-1 border tip, the water marker, Take all, throws landing on the crosshair, the bow's right-click hint, loot inside the border, crate spacing, dummy placement and health bar, the practice wording and "#1", sprinting while the bow is drawn, and the first swing after switching from a heavy weapon to a light one. Also two bugs the voice review found: settings overwritten by an early or failed-load save, and spectating cleared by the respawn.

### After you publish: three checks on a private server
1. **Training dummies on a live server** (alone, about 3 minutes).
   - Join a private server alone. The lobby counts down "PRACTICE ROUND IN" (about a minute from joining), then the practice round starts.
   - On your plate your view faces the Spire. At the horn, 3 TRAINING DUMMY targets stand about 13-17 studs in front of you, toward the Spire.
   - Hit one: a hit marker, and its bar drops; it heals 4 s later. Break one: it falls apart and is back 3 s later.
   - In F9 → Server there's no "[CombatService] No ServerStorage.Dev.TrainingDummy template" warning.
   - Reset (Esc, R, Enter): the card says "You reset", the menu closes, and the next practice round's horn comes about 28 s later.
2. **One 2-player test** (a second account or a friend).
   - The second player joins during your practice round: "A CONTENDER HAS ARRIVED" shows, the practice ends within 60 s, and its dummies are gone when it ends.
   - The next round, with both of you, has no dummies.
   - Take a sword from a crate and swing at the other player while they move away, 8-10 studs off: every hit you see does damage, and a swing you see miss never does.
   - While you're both in, also try the 2-player items under "Not verified yet": spectating your killer, a rival's bow creak, the runner-up's death card.
   - **Saving, for the first time for real.** Studio never saves (its DataStore is off) and practice rounds add no stats, so this path has never run. Before that round, change a setting (for example the field of view). After the round, both of you leave and rejoin: the setting is kept, and the lobby's record card shows the round (and the win or kill) added.
3. **The 60-second phone check** (`docs/handoff/PublishChecklist.md`, section 2): the nine steps on a phone (move, look, sprint, jump, attack, open a crate, drink, eat, spectate), and on a PC and a controller if you can. At the crate, take the items straight away (the pickup that failed once), and note the frame rate and memory in the Developer Console.

## What's in the game now

### First person and combat
- **Hands: your own avatar's arms.** First person shows your Roblox avatar's R15 arms, with your skin colour and your shirt. They rebuild about a second after you change your avatar.
  - **Lighting:** `ViewmodelController.Shade` lights them like the world, five times a second: an exposure that follows the scene, a soft sky light when no sun or moon reaches them, and a shade layer so black sleeves keep their shape. Dusk, night and forest shade darken them with the scene.
  - **Poses:** every hold and action was re-posed for the avatar arms, so elbows bend and wrists stay under 58°. Eating, drinking, bandaging, the vest and the med kit were redone, and the hands mostly stay off the hotbar.
  - **Fallback:** R6 or unusually shaped avatars get standard blocky arms in their skin colour. `Config.Viewmodel.ArmStyle = "Classic"` brings back the old part-built hands.
  - **Checked by:** a builder, two independent testers (look, and numbers), a fix round, and a final in-game check by the lead at noon and dusk with the sword, bow, apple and bottle.
- **Arrows stay and can be picked up.** Spent arrows, throwing knives and thrown spears no longer vanish.
  - They stick in trees, walls, crates and the ground, sink to the bottom in water, and drop at a body's feet when it dies or after about 30 s.
  - Walk over arrows and knives to take them, or look at one and press E ("Take Arrow"). The server checks reach.
  - Cleared between rounds; at most 400 per server, oldest first. 400 on the ground caused no measurable slowdown.
  - An independent tester found arrows from a broken dummy's head floating 12 studs up; the fix round made them drop first. The lead re-checked E pickup in game.
- **Bow.** The bow sits low-left and rises to the left when you draw. The avatar arms keep the crosshair clear: 0 px in the 6 % circle over 1,428 measured bow frames.
  - Across about 20,000 measured frames, nothing covered the crosshair area. A dummy at 30 or 60 studs was never hidden.
  - Arrows land on the crosshair point (`Config.Combat.BowAimOnTarget`).
  - A full-draw body shot does 50 and a headshot 90 (since 14 November).
- **Melee.** A swing lands only if it hit on your screen; the server still checks the reach (since 14 November).
- **Body facing.** In first person the character's body faced backwards, so the server threw away every shot and swing. A `CameraController` Focus fix solved it: 22 of 22 test arrows and every sword hit now count.
- **Items.** All items are the realistic ItemsReal models. The drinking, armour, bandage (wrap) and berries animations were redone.

### World
- **Terrain v2.1.** A forest valley:
  - meadow with the Spire plaza
  - forest on rolling hills
  - lake with an island
  - river gorge with a waterfall
  - cliffs with 3 walk-in caves
  - field and marsh
  - a mountain wall that can't be climbed
  - Fords are wadeable, and no loot is buried.
- **Set dressing.** `ServerStorage.WorldGen.Populate` v2 places about 28,500 realistic models. That covers:
  - the forest and ground cover
  - cliff faces
  - the Spire with 4 crate slots
  - 24 realistic launch plinths
  - the hunter's cabin, watchtower, footbridge, cave mouths and 6 campsites
  - the rebuilt lobby (the Tor)
  - `DetailController` hides distant ground cover and tree detail on lower settings.
- **Realistic art.** 64 world templates live in `ServerStorage.MeshAssets`, built by `ServerStorage.WorldGen.RealAssets`. Every file was uploaded once: 8 models and 25 roughness/metalness maps. The importer made the colour and normal images. All ids are in `art/manifests/RealSets.assetIds.json`.

### Movement
- **Jump.** A realistic jump of about 3.1 studs: quick crouch, no floaty hang, momentum kept, and harder landings dip further.
  - No bunny-hopping.
  - Ledges climb up to 7 studs; fences and low walls vault.
- **Avatars.** They keep their normal Roblox proportions. Crouch, climb and first person were checked with differently sized bodies.
- **Getting unstuck.** Held fast on steep rock, you get one jump, mantle or climb out, and Reset works in the arena after the horn (since 14 November).

### Day, night and the round
- **Day/night.** Two days in 15 minutes, with Realistic lighting. Dusk and pre-dawn are playable, and the sun/moon swap is hidden.
- **Launch.** You ride your plate up out of the ground at the start, with your view turned to the Spire.
- **Roll Call.** The nightly point-cloud display of the fallen opens on a day caption, with no music bed. Its on-screen list says where to look up.

### Playability quick wins (QW1-QW15)
See `docs/design/PlayabilityPlan.md`. Every one is behind a Config switch:
- practice rounds when you're alone, with 3 training dummies (live servers too)
- item hints that fade
- the goal and opening choice shown on the plate
- visible thirst and healing
- deaths that teach, and spectating your killer
- a smaller border in small rounds
- crates you can spot, and "Take all"
- runner's caches
- a threat line that announces what's coming
- a water marker
- controls options for touch and gamepad
- the Last Stand finale, so every round has one winner
- an analytics funnel

## Defaults chosen for your open decisions
You can change any of these.
- **Playability plan** (Q1-Q5):
  - extra help for new players: on (Guidance Auto)
  - bow headshot: x1.8, so a full-draw headshot does 90 (your note; changed from x2.0 on 14 November)
  - Last Stand finale: on
  - runner's caches: on
  - practice rounds on live servers: on, with the training dummies
- **Arrow drop.** Arrows land exactly on the crosshair (aim-on-target on). Set `Config.Combat.BowAimOnTarget = false` for realistic drop.
- **Roadmap.** The 8 decisions in `docs/Roadmap.md` section 8 are still open, including the combat-physics defaults.
- **Beta launch (your call, 14 November).**
  - **Title:** "HUNGER GAMES (BETA)". You chose it knowing it's a registered trademark: if its owner complains, Roblox can take the game down. Everything inside the game stays original to keep that risk low.
  - **Timing:** after your next two requests.
  - **Steps:** you press File → Publish in Studio. Then either rename it and make it Public in Game Settings, or grant the assistant the `universe:write` permission and it does that part.
  - **On 14 November** the experience was still "Untitled Experience", Private, rated 13+.
- **First-person hands: being remade.** You turned down the block fists, the realistic gloves and the R15 avatar arms. You asked for "blockish realistic ish" hands: bare hands built from chunky flat facets with real fingers, in the same style as the world. A preview comes to you before they go in the game.
- **Art style for the remake: waiting on your pick.** The style test (`docs/design/ArtStyle.md`, sheet in `art/previews/StyleTest/`) recommends A, "faceted realism", with C's pebble path, leaf litter, oak branching and porch railing. B (cubes) only if "blockish" meant literal cubes. The test diorama stays in `Workspace.StyleTest` (x 7000, far outside the arena) until you've picked.

## Not verified yet: needs you or a published test
- **Real frame rate and memory on devices.**
  - Studio caps its window at 15 fps while agents work. The measured render times (CPU 3.5-6.8 ms, GPU 0.7-3.8 ms) leave room for 60 fps on this PC.
  - The world draws 2.4-4.9 million triangles. Test on a 3 GB Android phone with the Developer Console.
  - If it struggles, the knobs are `Populate.Scatter.DENSITY.groundCover` and the `DetailController` tiers. Roblox's own quality levels don't reduce mesh detail.
- **Anything that needs 2 or more players:**
  - SPECTATE opening on your killer
  - hearing a rival's bow creak
  - the health tiebreak and the runner-up's death card
  - the practice-to-full-round hand-off
  - no training dummies in a 2-player round, and a melee hit on a player who is moving
  - Use Studio's Test → Clients and Servers with 2 players, or a private server (check 2 above).
- **Touch and gamepad layouts** on real devices (check 3 above).
- **The analytics funnel.** It only logs in a published game.
- **Saving stats and settings.** Turn on Game Settings → Security → "Enable Studio Access to API Services" to test DataStores in Studio.

## Known issues
- **Gorge walls.** About a third of the steep rock you see at eye level is still bare voxel terrain. Cliff pieces can't go nearer the wadeable stream.
- **Trees.** The card foliage looks flat within 8-15 studs. The meadow's terrain grass blades are tall up close.
- **Roll Call under trees.** A dense canopy still hides about half of it. The list and its "look up" hint cover that.
- **Night under trees** is near black. A custom night skybox and exposure work belong to the look-dev pass.
- **Small art notes:**
  - the dried meat looks raw
  - the ration is eaten as a sealed tin
  - vests lying on the ground look like a rolled mat
- **TexturePack upload errors: fixed.** They came from two unused raw-import SurfaceAppearances whose EmissiveMaskContent pointed at `rbxassetid://24`. Both were removed, and the console is clean.
- **Avatar arms, open points** (for the polish pass):
  - Black sleeves still read near-black at dusk and at night.
  - In the forest at night the arms are about 3x as bright as the floor, because the canopy's foliage isn't raycast-able, so the cover darkening is weak.
  - Drinking and the vest put-on bring a large arm block into the right of the screen for a moment.
  - 3D layered clothing isn't shown on the arms; only the classic shirt and body colours are.
  - Avatars with unusual proportions, Rthro and R6 (the StandardArms fallback) were not tested in game.
  - The FOV setting (`ClientState.settings.fov`) didn't change the camera in two agents' playtests. Worth checking on its own.
- **Solo rounds feel small.** In a 1-player practice round the border starts at radius 320, so 82 of 181 loot markers are skipped and the hunter's cabin (about 470 studs out) is outside the border. The arena v3 build must revisit the small-round border.
- **Arrows in water** rest on the bed (a real wooden arrow would float); in the 11-stud-deep lake you have to dive for them.

## Queued: the polish pass (the owner's request, 12 November)
After the current work (avatar arms, arrows, the art-style remake, the arena v3 build): "touch up on all the assets so far making sure they are clean and transition animations are smooth and good quality".
- **Assets:** check every model, texture and placement for floating parts, seams, z-fighting, stretched UVs, wrong scale and leftover test objects.
- **Transitions:** smooth every animation hand-off:
  - first-person equip and switching weapons, the bow's draw, release and lowering, eating, drinking and armour, the wall tuck
  - third-person locomotion: walk, run, sprint, jump, fall, land, mantle and climb
  - camera and launch moments, and HUD and UI fades
- **Done when:** in-game captures and frame-by-frame checks show no pops or snaps.

## Reminders for the owner
- **After the beta release (you asked, 14 November):**
  - a loading-screen animation;
  - advertising on Twitter, YouTube and TikTok;
  - a showcase video made with Seedance and Blender, with game footage. Seedance runs through Higgsfield, which needs signing in with `/mcp` first.
- **Your design documents (14 November)** are kept word for word in `docs/design/owner/`:
  - the TRIBUTE blood, severing and movement spec;
  - the game design direction.

  Still open: how much gore (severing pushes the Roblox age rating up), and whether to use the films' own names. Also queued: the movie-style training room before the arena, where you try kits and abilities and the chests stock items to match.
- **Attacks and battle manoeuvring** (wind-ups, light and heavy attacks, block): you asked to be reminded. See `docs/design/WeaponsAndObjectives.md`, W2, and `docs/research/CombatPhysicsPlan.md`.
- **The weapon roster and bow tuning:** later, at your call. Your notes: make the bow's distance and drawing more accurate; 3–4 bows a round; a 90-damage headshot (done 14 November).

## Suggested next steps
1. Publish, then the three checks on a private server above: the dummies, a 2-player test and the phone.
2. The rest of the QA list, at your call (see "Not in today's fixes").
3. The look-dev pass from `docs/research/LookDevPlaybook.md`: valley skybox, atmosphere, eye adaptation, zone looks, firelight.
4. Roadmap Phase 2a, Warden events: your "new challenge every couple of minutes".
5. Combat physics (Part 3), once you confirm Roadmap decision 3.
