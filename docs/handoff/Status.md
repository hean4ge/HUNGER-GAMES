# LAST STANDING: where things stand (12 November 2026)

The Studio place (placeId 120572716460286) was saved as **version 166**. Nothing has been published to players.

Every script is exported to `src/`, verified byte for byte against Studio; `src/manifest.json` lists them. Each area below was built by one agent, then checked by an independent tester, with a fix round wherever the tester found problems.

## What's in the game now

### First person and combat
- **Hands.** The original v1 part-built hands are back: dark sleeves, cuffs, and block fists in your skin colour.
- **Bow.** The bow sits low-left and rises to the left when you draw.
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

## Suggested next steps
1. A device check: a private test on a phone and a PC.
2. A 2-player test session.
3. The look-dev pass from `docs/research/LookDevPlaybook.md`: valley skybox, atmosphere, eye adaptation, zone looks, firelight.
4. Roadmap Phase 2a, Warden events: your "new challenge every couple of minutes".
5. Combat physics (Part 3), once you confirm Roadmap decision 3.
