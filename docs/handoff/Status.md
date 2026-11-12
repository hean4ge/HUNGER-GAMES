# LAST STANDING: where things stand (12 November 2026)

The Studio place (placeId 120572716460286) was saved as **version 199**, labelled as the restore point before the bigger arena. Nothing has been published to players.

Every script is exported to `src/`, verified byte for byte against Studio; `src/manifest.json` lists them. Each area below was built by one agent, then checked by an independent tester, with a fix round wherever the tester found problems.

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

### Day, night and the round
- **Day/night.** Two days in 15 minutes, with Realistic lighting. Dusk and pre-dawn are playable, and the sun/moon swap is hidden.
- **Launch.** You ride your plate up out of the ground at the start.
- **Roll Call.** The nightly point-cloud display of the fallen opens on a day caption, with no music bed. Its on-screen list says where to look up.

### Playability quick wins (QW1-QW15)
See `docs/design/PlayabilityPlan.md`. Every one is behind a Config switch:
- practice rounds when you're alone
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
  - bow headshot: stays at x2.0
  - Last Stand finale: on
  - runner's caches: on
  - practice rounds on live servers: on
- **Arrow drop.** Arrows land exactly on the crosshair (aim-on-target on). Set `Config.Combat.BowAimOnTarget = false` for realistic drop.
- **Roadmap.** The 8 decisions in `docs/Roadmap.md` section 8 are still open, including the combat-physics defaults.
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
  - Use Studio's Test → Clients and Servers with 2 players, or a private server.
- **Touch and gamepad layouts** on real devices.
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
- **Attacks and battle manoeuvring** (wind-ups, light and heavy attacks, block): you asked to be reminded. See `docs/design/WeaponsAndObjectives.md`, W2, and `docs/research/CombatPhysicsPlan.md`.
- **The weapon roster and bow tuning:** later, at your call. Your notes: make the bow's distance and drawing more accurate; 3–4 bows a round; a 90-damage headshot.

## Suggested next steps
1. A device check: a private test on a phone and a PC.
2. A 2-player test session.
3. The look-dev pass from `docs/research/LookDevPlaybook.md`: valley skybox, atmosphere, eye adaptation, zone looks, firelight.
4. Roadmap Phase 2a, Warden events: your "new challenge every couple of minutes".
5. Combat physics (Part 3), once you confirm Roadmap decision 3.
