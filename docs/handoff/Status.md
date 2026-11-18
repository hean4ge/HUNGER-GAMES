# LAST STANDING: where things stand (18 November 2026, afternoon)

The Studio place (placeId 120572716460286) is saved as **version 404**. The repo is at commit `e2226af` on branch `v1`, plus two commits that only touch docs. **Nothing has been published to players yet.** The experience is named "HUNGER GAMES (UNDER DEVELOPMENT + TESTING)" and Studio's start page shows it as "Ages 16+".

`src/` holds every script, and at `e2226af` it matched Studio byte for byte (116 script files, 0 differ). `src/manifest.json` is out of date: it still lists the 96 scripts of version 302 (see `src/README.md`).

**Work was still running when this page was written.** After version 404 a polish round changed the fight, the border wall, the cards and the Roblox Plus button. Those changes are in the open Studio session and in `src/`, but not in a saved version and not committed, and each was tested only by the agent that made it. A second code review then found more faults, and a second fix round started at about 14:40; its results are not in this page. Below, "afternoon round" marks anything in that state.

## Today's work (18 November), after version 351
Map 1 was installed on the morning of 18 November (version 351). Since then: a lighting pass, fixes to the block hands, a code review with 45 findings fixed by four agents, a test with two and three real clients, the Roblox Plus button, and a final check by a lone tester. The final check's verdict was **"go for a public beta, with conditions"** (the conditions are under "Still open").

### What changed, and what the tests confirmed
- **Lighting on Map 1.** Midday is clear and bright: the blue veil is gone, the far range reads as distant mountains, the flower beds show and the lake has its own colour. Dusk is a cool valley floor with warm light on the peaks. The Menu has a new row, **Shaders: Off / Auto / Full**.
  - **Confirmed:** Off, Auto and Full each applied without error, by code and by real clicks in the menu. The look was captured at 09:00, 14:00, 17:30 and 21:00, before and after.
  - Cloud banks lying on the mountains were not built. The sky has Roblox's own clouds only.
- **Night in the wood.** After the lighting pass the forest floor at night was black. The whole night is now brighter, because Roblox gives open ground the same fill light as the wood: at 21:00 the wood floor went from under 1 to 12 (on a 0-255 scale) and the meadow from 22 to 33.
  - **Confirmed:** a tester walked 151 studs through the north wood with the clock held at 21:00, with no stall and the floor and trunks readable.
- **Block hands.** One sword swing used to put the arm across a quarter of the view, and the bow and spear rested over the item bar. Both are fixed.
  - **Confirmed:** over all 15 swing sets no arm block covers more than 13.1 % of a 16:9 screen (it was 27.5 %). At rest the arms cover none of the item bar or the health bars on 16:9 and 16:10. Hands now move with the field-of-view setting.
- **The fight** (review fixes).
  - The server and your own game now use the same rule for when the next swing may start, so the first swing after switching weapons counts. **Confirmed** alone and with two clients.
  - A swing hits the body under your crosshair first; a bystander beside the line no longer takes the hit.
  - The bow needs a real draw. A shot with no draw is refused. **Confirmed:** refused six times out of six, arrows unchanged.
  - The other player sees your swing start before the damage lands. **Confirmed** with two clients: 0.20 s before, for the sword.
  - Hats, wings and other accessories are no longer part of anyone's hit box.
  - Swing, hit, bow and throw sounds go only to players near enough to hear them.
- **The round on a busy or empty server.**
  - **Filling:** on a public server a player who joins during the lobby countdown restarts it at 25 s, never past 90 s in all. With 8 or more already waiting there is no restart. A private server starts with whoever is there. Tested only through a Studio test hook.
  - **48 at most:** when more are waiting than plinths, whoever played least recently goes first. The others get a message and can spectate. Checked by reading only.
  - **Roll Call:** capped at 45 s however many fell (47 fallen used to take 191 s). The cap already shortens the show from 4 fallen up.
  - **A lone tester's ring** starts at 700 studs (it was 520), so the forest edge is inside it. Two players get 860, 24 get 1,469, 48 keep 1,800.
  - **The winner is decided by account id**, not by display name, and so is "you" in the kill feed. **Confirmed** with two clients: only the winner's screen says VICTORY.
- **Map and launch.**
  - The ground under the Peak is filled in, so nobody can walk in under it. Surveyed; walked to its north foot by the final tester.
  - The launch intro is readable at low graphics quality, and the hall holds 24 glass cases (two neighbouring plinths share one).
  - The border wall no longer dyes the valley red and pink (found by the final tester at full quality). It is a strong orange sheet only near you.
  - Things far behind you now unload from memory, but only partly: 8,600 to 9,000 plants beyond 1,100 studs stayed loaded for the 40 s watched.
- **Words on screen.** No item text says "wound" any more. The lobby notice boards use Map 1's words (up to forty-eight, the Horn, streams). A scan of every on-screen label in play found no banned word.
- **Two and three real clients.** Seven sessions in Studio: five with two clients, one with three, one with a late joiner. See "Multiplayer" below for what passed.
- **Roblox Plus.** One quiet "ROBLOX PLUS" button in the lobby. See "Roblox Plus" below.
- **Lone loop, final check.** Seven playtests, the last five with Studio focused at 60 fps and full quality: plinth to the Horn with real keys, a crate and Take all, bow 50, sword 40, knife 22 after a switch, a bottle, drinking at the stream (thirst 39 to 77), swimming, deaths by the border, by water, on the plinth, by a fall at the Edge and by Reset, each with the right card and a clean next round. The Boundary stopped the player at radius 1,899.4. No error or warning from the game's scripts in any of them.

### Afternoon round (in Studio and `src/`, not saved, not committed)
- **Sword reach for a cheat: closed.** At version 404 a modified game could land a sword hit from about 15 studs on a real player (honest reach is 10). The server now measures how far each body really moved and allows only that. Against a still target a claim from 11 studs is refused and 10.4 is accepted. Tested alone against dummies, not with two clients.
- **The bow in third person.** At version 404 an archer aiming at you looked idle, with the bow hanging at the hip and its lower limb in the ground. The bow now sits in the left hand with a hold and a draw pose. Seen on the tester's own body, not from a second client's screen.
- **Defeat.** At version 404 a defeated body fell apart into loose limbs and lay for 4 s. It now stays in one piece, topples, fades after 1.8 s over 1 s and is gone. Roblox's own death sound is muted; only the cannon plays. Tested alone.
- **The border wall from far off.** After the first fix the starting ring was barely visible from the plinths. A bright line on the ground and a low band of light above it now mark it from a distance, and the sheet shows within about 60 studs.
- **Cards and lobby.** The item bar and prompts hide while the result card is up, so they no longer show through it. Roblox's chat window starts closed and stays closed at the launch hand-off. HOW TO PLAY fits the screen. The Drink hint hides when thirst is 95 or more. A leaving contender no longer writes a warning to the server log.
- **Roblox Plus.** The member mark is now a small PLUS sign over a member's character in the lobby, and it was seen rendering (with a Studio test switch, not with a real member). The panel fits a phone-sized screen.

### Still open
**The final check's conditions before the game goes public:**
- **The age label.** Studio shows "Ages 16+". The questionnaire has to be filled in for the game as it is now. See `PublishChecklist.md`, section 4.
- **Server size.** The place allows 60 players (earlier readings said 50); a round takes 48. Set it to 48.
- **Saving has never run.** Studio's DataStore is off, so no save or load call has ever been made, by the old code or the new. One short test on a published private server comes first (check 2 below).
- **Save and publish.** The afternoon round is not in a saved version.

**Faults, most serious first:**
- **The icon and the title.** The experience icon is a golden bird in a ring, close to the films' pin, and the title uses another owner's brand. Together they are a takedown risk. This is your call; three other titles are in `StoreText.md`.
- **Red on hit.** The screen edge flashes red on every hit and pulses red at low health; the damage-direction bars and the kill hit-marker are red. The rule for the age rating is no red hit effects. Not changed yet.
- **Late swings.** The second review found that at version 404 the server never believes the time your game says a swing started, so a swing that arrives late on a slow connection can be refused. A fix is on disk in the second fix round; untested.
- **Spectating for a long time.** The second review found, by reading, that the lobby island could unload under a spectator, whose body stands 8,800 studs from what they are watching. Needs a test.
- **Ragged far ridge at low graphics.** Below about level 13 of Roblox's 21 quality levels the far valley shows as ragged shards with sky in the holes. At full quality it is whole. No code change cures it; the cure is one mesh per tile from Blender.
- **Heather.** Each heather plant is a flat mauve mat 4 to 7 studs wide. On the east ridge they show as purple slabs through the grass, and 175 of them lie on bare white limestone (seen at the Edge).
- **Far forest.** When you walk into one of the far valley's tiles (1,900 studs wide), the dark canopy layer of the whole tile hides, the far slopes with it.
- **A refused swing can still sound like a hit** on the attacker's screen after a lag spike over about 0.35 s. The sound is played at once; only the hit marker waits for the server.
- **Roblox Plus.** Nothing stops the Subscribe window being open at the moment the countdown takes you to your plinth. A real subscription has never been tried.
- **Two firs 2.75 studs apart** held a tester for 24 s. The plants have no minimum distance between trunks.
- **Uphill pace.** From radius 500 the ground climbs about 19°, and the pace drops to 6-9 studs a second with sprint held.
- **A dark view, once.** In one first round the world was flat dark grey behind a normal HUD. It did not happen again in two more first rounds. Cause unknown.
- **Small ones:** on 4:3 screens the bow and spear rest over the end of the health bars; the bottle rides on the side of the hand block; a touch-screen PC gets phone buttons; the lobby's "NEXT ROUND IN ... AT MOST" leaves out the fill rule's extra time; a cancelled countdown is logged as a finished round in the onboarding funnel.

### After you publish: three checks on a private server
1. **Alone** (about 3 minutes).
   - The lobby counts down "PRACTICE ROUND IN", then the launch intro plays and you stand on a plinth facing the Horn.
   - At the signal, 3 TRAINING DUMMY targets stand in front of you. Hit one: a hit marker, and its bar drops.
   - F9 → Server shows no red errors and no `[DataService]` warnings.
2. **Two accounts** (a second account or a friend).
   - **Saving, for the first time ever.** Change a setting (for example the field of view). Play one normal round. Both leave and rejoin: the setting is kept, and the lobby's record card shows the round and the win.
   - **Filling.** On a public server, the second player joins during the countdown: "A contender has arrived" shows and NEXT ROUND IN restarts at 0:25.
   - **The fight.** Swing a sword at the other player while they move away, 8-10 studs off: every hit you see does damage. Draw the bow at each other: the archer raises and draws it.
   - **Defeat.** The loser topples and fades; nothing is left lying. Only the winner's screen says VICTORY.
   - **Roblox Plus.** A non-member sees the ROBLOX PLUS button; pressing SUBSCRIBE opens Roblox's own window. A member sees PLUS MEMBER and has the PLUS sign over their character in the lobby.
3. **The 60-second phone check** (`PublishChecklist.md`, section 2), on a phone and, if you can, a controller. Note the frame rate and memory in the Developer Console.

## What's in the game now

### First person and combat
- **Hands: Roblox-style block arms.** Two square blocks in your own avatar's arm colour on a plain grey sleeve. Matte, with no light, glow or outline on them.
  - **At rest** the empty hands sit low at the bottom corners. Fists come up for a punch, stay 1.5 s, then drop.
  - **Lighting:** they darken with the scene at dusk, at night and under a tree. Dark skin gets a small lift at night so the hand doesn't vanish.
  - **Other styles** are one setting away: `Config.Viewmodel.ArmStyle` ("Blocky", "Faceted", "Avatar", "Classic") and `Config.Viewmodel.Blocky.Variant` ("A" one block, "B" palm, fingers and thumb).
- **Zoom.** Hold V for 2.5×. While it is held the mouse wheel moves it between 1.56× and 4×, and the item bar doesn't change. Right-stick click and the touch ZOOM button switch it on and off. Look speed drops to match. The hands leave the view while you are zoomed, an attack lets go of the zoom, and eating blocks it.
- **Melee.** Fists, knife, machete, hatchet, mace, sword, spear. A swing lands only if it hit on your screen; the server then checks that body and the reach.
- **Bow.** A full-draw body shot does 50 and a headshot 90. Arrows land on the crosshair point. A shot needs a real draw.
- **Thrown knives and spears** land on the crosshair point. Spent arrows, knives and spears stay in the world and can be picked up.
- **Defeat** has no blood and no wounds. See the afternoon round above for how the body falls and fades.

### World: Map 1, the Green Land
- **The valley.** Your Blender map as Roblox terrain out to radius 2,750, with the lake and the stream. Players can go as far as radius 1,800; an invisible wall at 1,900 stops anyone leaving. The Edge, the cliff in the north, is a real drop.
- **The heart.** The blue-grey Horn on its platform, 48 plinths in a ring 150 studs out, and the flower beds.
- **Plants.** 42,583 firs, pines, beeches, heather, gorse, tall grass, flowers and boulders, placed from the Blender masks.
- **The far view.** The far mountains, the Peak, and a far-valley mesh so the valley shows beyond the distance Roblox loads.
- **Loot and water.** 443 loot markers; 87 drinking points on the lake and the stream.
- **The lobby** is the same island, moved to (8800, 160, 0).
- **The old forest arena** is out of the game and can come back: its scripts and data are in `ServerStorage.Vault_ClassicForest`, and place versions 258 and 302 hold all of it.

### Movement
- **Jump.** A realistic jump of about 3.1 studs, with no bunny-hopping. Low walls vault.
- **No tree climbing on Map 1.** The controls list shows "Jump · vault".
- **Getting unstuck.** Reset (Esc, R, Enter) works in the arena after the signal and counts as an elimination. On the plinth it does nothing.

### Day, night and the round
- **Players.** 1 to 48 a round, one per plinth. Alone, you get a practice round with 3 training dummies.
- **Launch.** The red room, the glass cases, the rise up the pole with the camera circling, a white-out, then you stand on your plinth in first person facing the Horn. The long cut (22 s) plays when at least half the contenders haven't seen it; otherwise the short one (12 s). You can skip it.
- **Day/night.** Two days in 15 minutes.
- **The border.** It starts at a radius set by the head count and closes to 60 studs, never faster than 3.5 studs a second. Outside it you lose about 4 health a second.
- **Roll Call.** At dusk the fallen are named in the sky and in a list at the right edge.
- **The result** shows on a card: VICTORY for the winner, "THE ROUND IS OVER" for the rest. (You asked on 18 November for it to move to a board in the lobby; not started.)

### Multiplayer (tested in Studio with two and three clients)
The test harness is `ServerStorage.Dev.MPTest` with tools in `tools/mp_test`. The bots press the game's real inputs. **Passed:**
- both stand in the lobby and see each other; the countdown shows on both screens;
- a real round starts with each on their own plinth, facing the Horn, held until the signal; the intro plays on both;
- sword 40 at 7 and at 10 studs, bow 50 at 20 studs, thrown knife 28 at 14 studs; at 11.5 studs an honest sword swing misses;
- the death card ("ELIMINATED #2 OF 2 ... by Player1 - Arena Sword"), the kill feed on both screens, VICTORY on the winner's only;
- with three: spectating the killer, switching to the other survivor, and the dusk Roll Call naming the fallen on all three;
- back to the lobby after about 23 s, and a second round;
- a contender leaving mid-round ends it properly; one leaving during the countdown gives "Round cancelled";
- a late joiner waits with a timer, can spectate, and plays the next round;
- the border hurts both; loot taken by one is gone for the other; eating and drinking show to the other player;
- third-person walking, sprinting, crouching, weapon holds and the sword swing.

**Failed at version 404,** both worked on in the afternoon round: the sword reach for a modified client, and the bow's third-person look.

### Roblox Plus
- **The button.** A small "ROBLOX PLUS" button at the end of the lobby's SETTINGS / HOW TO PLAY row. It shows only in the lobby, only to players who aren't members, and only if Roblox says they may buy subscriptions.
- **The panel.** Pressing it opens the game's own panel. It says membership is optional and changes nothing in a round, what a member gets here (the lobby mark), that subscribing from here pays the creator a bonus, and "Not an adult? Ask a parent or guardian first." It shows no price.
- **Subscribing.** Only the SUBSCRIBE button opens Roblox's own window, at most once per 10 s. Nothing opens by itself, ever.
- **Members** see "PLUS MEMBER" in the button's place and have a mark in the lobby. It gives no advantage in a round.
- **Private servers.** "PRIVATE SERVER" shows above the lobby title in one, and the round starts with whoever is there.
- **In Studio** the Subscribe window does not appear, so a real subscription is untested.

### Playability quick wins (QW1-QW15)
See `docs/design/PlayabilityPlan.md`. Every one is behind a Config switch:
- practice rounds when you're alone, with 3 training dummies
- item hints that fade
- the goal and opening choice shown on the plinth
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
- **Chosen by agents today, yours to overrule:**
  - **Grass length:** Roblox's shortest (0.1). It opens the view and shows the flower beds.
  - **Night:** brighter overall, as the price of a walkable wood. One table sets it (`NIGHT_G` in `Shared/DayCycle.lua`).
  - **The border wall:** a strong sheet near you, a ground line and a low band from afar.
  - **Lobby filling:** joins stop restarting the countdown once 8 are waiting (`Config.Round.FillTarget`).
  - **Roll Call length:** 45 s at most (`DayCycle.Recap.MaxTotal`). About 65 would leave lists of up to 8 as long as before.
  - **The long launch cut** plays only when half the contenders are new, so a newcomer on a busy server only sees the short one (`Config.Launch.FullCutShare`).
  - **Roblox's player list** is switched off in the game, so it doesn't cover the kill feed. The Roblox menu still has its players page.
  - **The Plus panel's line** "If you subscribe from here, Roblox pays this game's creator a bonus" was kept as honest disclosure.
- **Not chosen yet, yours:**
  - **The private-server price.** It can't be changed later without cancelling every active private server. See `PublishChecklist.md`, section 4.
  - **The title and the icon** (see "Still open").
  - **The lobby title** still reads LAST STANDING with the tagline "Outlast everyone".
- **Playability plan** (Q1-Q5): extra help for new players on; bow headshot ×1.8 (90 at full draw); Last Stand finale on; runner's caches on; practice rounds on live servers on.
- **Arrow drop.** Arrows land exactly on the crosshair. Set `Config.Combat.BowAimOnTarget = false` for realistic drop.
- **Roadmap.** The 8 decisions in `docs/Roadmap.md` section 8 are still open.
- **The launch (your calls).**
  - **Title:** "HUNGER GAMES (BETA)", chosen on 14 November knowing it's a registered trademark: if its owner complains, Roblox can take the game down.
  - **Audience:** "publish the game for all ages" (18 November), then "No, 16+ for now" to paying Roblox's refundable 1,000 Robux fee. So it launches public for age-checked 16+ players, and under-16 reach comes later.
  - **Content:** no blood and no wounds.
- **Hands:** the block arms above, after you turned down the block fists, the gloves, the avatar arms and the faceted hands.
- **The look:** "roblox with good graphics realistic SHADERS" (15 November). The style-test diorama is stored in `ServerStorage.StyleTest.Diorama`.

## Not verified yet: needs you or a published test
- **A phone.** Never tried on a real one. The phone layout, the touch buttons, the phone shader tier and the frame rate are all untested.
- **A controller.** Never tried with a real one.
- **Saving.** No save or load has ever run (see "Still open").
- **Real lag.** A Studio test has no ping. Whether hits on a moving player still land at 150-300 ms is unknown.
- **More than three players.** Three clients and a server took about 12 GB on this PC. The 48 cap and the pick order were checked by reading only.
- **A real Roblox Plus subscription,** and how the Subscribe window behaves for a child's account.
- **A real private server** and a real public one: the fill rule ran only through a Studio test hook.
- **A full 15-minute round at real speed.** Dusk, night and the border were reached by speeding up time or holding the clock.
- **The Roll Call's figure in the sky** with two or more players: the message and the list reached every client; the figure was never in a picture.
- **Sound.** Nobody has listened. The sound messages reach the right clients.
- **The long launch cut** with a hall full of contenders, and weak devices.
- **The HUD on a true 16:9 window.** Studio's play window was 1854 × 753. The hands were measured against a 16:9 layout; the rest was not.
- **The analytics funnel.** It only logs in a published game.

## Known issues
- **Everything under "Faults" above.**
- **Night is brighter than the lighting pass first left it** (see "Defaults").
- **17:30 has no direct sun on the valley floor:** the west range blocks it. Deliberate.
- **The round opens at 07:24,** when the sun may still be behind the east range. Not looked at.
- **The ground under the Peak** shows as a dark steep bank under its skirt. A new terrain write removes the fill: run `Map1.Terrain.fillUnder()` again afterwards. `Map1.Terrain.verify()` will report the raised ground as off the grid.
- **A lone tester's ring (700)** takes in the forest edge but not the lake (radius about 800).
- **Hands, open points:** a black avatar's hand stays near black at night; in a wind-up the forearm stands along the right edge as a dark block of about 12 % of the screen; at field of view 55 the bow hand covers 3 % of the health bars.
- **A minimum-power arrow** (21 damage) can be loosed 0.03 s after starting a draw. It can't be repeated faster than an honest archer shoots.
- **The server trusts where a player's own game says they are.** There is no speed or teleport check.
- **Arrows in water** rest on the bed; a real wooden arrow would float.
- **Small art notes:** the dried meat looks raw; the ration is eaten as a sealed tin; vests on the ground look like a rolled mat.

## Queued: the polish pass (the owner's request, 12 November)
"touch up on all the assets so far making sure they are clean and transition animations are smooth and good quality".
- **Assets:** check every model, texture and placement for floating parts, seams, z-fighting, stretched UVs, wrong scale and leftover test objects.
- **Transitions:** smooth every animation hand-off: first-person equip and switching, the bow's draw and release, eating and drinking; third-person walk, run, jump and land; camera and launch moments; HUD and UI fades.
- **Done when:** in-game captures and frame-by-frame checks show no pops or snaps.

## Reminders for the owner
- **Someone at the PC took the controls in three test sessions on the morning of 18 November** (ran to the Horn, opened crates, hit the 520 ring). It isn't confirmed that this was you. If it was: in one of them a test script kept clearing your items, and the far valley was out of place across the sky. Both were the test and a since-fixed fault, not the game as it is now.
- **Your requests of 18 November, not started:** new sound effects; a new UI style, with the result on a board in the lobby; the rise ending in first person with the sun dazzling you. Then weapons and fighting, the starting lobby, and the train to the prep room. See `OwnerRequests.md`.
- **After the beta release (you asked, 14 November):** a loading-screen animation; advertising on Twitter, YouTube and TikTok; a showcase video made with Seedance and Blender. Seedance runs through Higgsfield, which needs signing in with `/mcp` first.
- **Your design documents** are kept word for word in `docs/design/owner/`, and your 18 November specs in `docs/design/OwnerSpecs_WeaponsLobbyTrain_2026-11-18.md`.
- **Attacks and battle manoeuvring** (wind-ups, light and heavy attacks, block): you asked to be reminded. See `docs/design/WeaponsAndObjectives.md`, W2.

## Suggested next steps
1. Finish the second fix round, test it, save the place and commit.
2. Decide the title and the icon.
3. The launch steps in `PublishChecklist.md`, section 4: server size 48, the questionnaire, publish for age-checked 16+.
4. The three checks on a private server above, saving first.
5. Your 18 November requests, in your order: sounds, UI, the rise; then weapons, the lobby, the train.
