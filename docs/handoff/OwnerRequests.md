# Everything you've asked for, and where it stands

*Checked on 15 November 2026. Claude re-read all 90 of your messages, the 10 pictures you sent and every reply it gave you. Eight checkers then compared each request with the game's code, the docs and Studio. Dates are your local dates. Your words are quoted as you typed them.*

*Updated on 18 November 2026 (afternoon) from that day's test and fix results: finished rows moved to "Done". The place is saved as version 404 and is not published.*

This page is the one list of your requests. [Status.md](Status.md) says what the game does today; this page says what you asked for and whether it's done. Update both together.

---

## 0. Your corrections on 15 November (these come first)

You sent these while the beta update was being built. They override the rows below wherever they differ. Four of them are finished and now sit in "Done": the map, the look, the hands and the zoom.

| You said | What it changes |
|---|---|
| **Your long design prompts:** "dont be a smartass and follow them" | Their build order is the build order: the arena and environment first, made in Blender; then interaction, creatures and events, combat and the match, progression, monetisation. Both prompts are kept word for word in [docs/design/owner](../design/owner). |
| **Multiplayer and launch:** "also make the game multiplayer and playable bug test and launch for beta testing" | <ul><li>**Multiplayer: tested (18 Nov).** Two and three real clients played full rounds against each other in Studio. What passed and what failed is in [Status.md](Status.md), "Multiplayer".</li><li>**Bug test: done on the new map.** A code review's 45 findings went to four fix agents; a few were left on purpose and are listed in Status. A second review found more, and a second fix round was running when this page was updated.</li><li>**Launch: not yet.** Nothing is published. The steps are in [PublishChecklist.md](PublishChecklist.md), section 4.</li></ul> |

### Added on 18 November

| You said | What it changes |
|---|---|
| **The launch:** "after you're done with everything publish the game for all ages" | <ul><li>Claude publishes once the two-player test and the bug hunt are done.</li><li>Roblox sets the age label from a questionnaire that has to describe the game as it is. So the game ships with **no blood and no wounds**. This replaces the "13+ gore" decision in section 2.</li><li>**Checked against Roblox's rules on 18 Nov:** "all ages" is no longer a label you pick. A new game is playable only by age-checked 16+ players at first, and reaches younger players after Roblox's own steps. Answered truthfully, this game should be rated "Mild"; that is Claude's reading of Roblox's definitions and shows for certain only on the questionnaire's preview page. The steps are in [PublishChecklist.md](PublishChecklist.md), section 4.</li></ul> |
| **The all-ages fee:** "No, 16+ for now" (answer to paying Roblox's refundable 1,000 Robux fee) | The game publishes as public for age-checked 16+ players. No fee is paid. Under-16 reach comes later (two months of Plus in a row, your ID check and 2-step verification, then Roblox's 250-play evaluation). |
| **Sounds:** "replace the sound effects" | Every sound effect is replaced. Starts after the current round of fixes. The replacement table is in [SoundTable_2026-11-18.md](../design/SoundTable_2026-11-18.md). |
| **UI:** "fix the UI in a style that i will like also it shouldnt pop up after the game it can appear on one of the physical boards" | <ul><li>A new UI style. You were shown three options on 18 Nov and chose **A, "Quiet"** ("i like a"): no boxes, thin text and small matte icons straight on the picture, things fade when not needed. The mock-ups and rules are in [docs/design/ui/StyleA_Quiet](../design/ui/StyleA_Quiet).</li><li>The result no longer pops up over the screen after a round. It is shown on a physical board in the lobby.</li><li>Not started. Today the result is still a card over the screen.</li></ul> |
| **The rise into the arena:** "when the player is loaded into the game and going up with the animation he should also feel first person toward the end and then slight blinding by the sun when he gets there" | The launch ends in first person, and the sun dazzles you briefly as you come up onto the plinth. Not started. |
| **What comes next:** "when are we going to work on the weapons and starting lobby and the train that taakes them to the prep room before the arena where they get to choose their allies and enter the room (before the transition animation to the arena)" | Order after the three items above: <ol><li>Weapons and fighting.</li><li>The starting lobby.</li><li>The train to the prep room, where players choose allies and enter the room that leads to the launch.</li></ol>Choosing allies in the prep room is new on 18 Nov. Everything you have said about these is gathered in [OwnerSpecs_WeaponsLobbyTrain_2026-11-18.md](../design/OwnerSpecs_WeaponsLobbyTrain_2026-11-18.md). |
| **Roblox Plus:** "i have roblox plus now so all the benefits with game dev r there utilise them" | <ul><li>**Built (18 Nov):** a quiet, opt-in "ROBLOX PLUS" button in the lobby. Roblox pays a creator a bonus when a player subscribes through the game. A real subscription can't be tried in Studio, so it is untested.</li><li>**At launch:** paid private servers switched on (Roblox pays creators when Plus members play in a private server they own). The price is yours to pick, once.</li><li>No fighting advantage for Plus members. A member gets a small mark in the lobby.</li><li>Roblox's pages list no Studio or creator-tool benefit of Plus. For you as a creator it counts toward all-ages publishing (after two months in a row) and gives Marketplace publishing rights.</li></ul> |

---

## 1. Being built now (the beta update)

You approved this batch with "Yes, all of it" (15 Nov), "Yes, in the beta" for the launch intro, and "do it yourself" for the rest. Five of its rows are finished and now sit in "Done": small rounds, the hands, the zoom, the swings and the launch intro.

| You asked | What's being done |
|---|---|
| **Fix the test plays' findings:** "run many test plays ... if there are game design issues infform me we can fix them and then release it" (14 Nov) | Built on 15 Nov on the forest arena, before Map 1. <ul><li>**Seen working again on Map 1 (18 Nov):** loot only inside the border; "Take all"; thrown knives and spears aimed on the crosshair; no "#1" for a practice death; spectating kept when you respawn; the first swing after a heavy weapon counts.</li><li>**Gone with the forest arena:** the rock pocket that trapped players.</li><li>**Not re-checked one by one on Map 1:** the day-1 border tip; the water marker coming back after the first drink; crate spacing; the bow's right-click hint; no sprinting with a drawn bow; arrows not filling a bowless player's slots; the dummies' place and health bar; settings no longer reset by a bad save (saving has never run); the "WAITING FOR PLAYERS" flash; controllers recognised from the first second; the HUD items.</li></ul> |
| **Polish:** "touch up on all the assets so far making sure they are clean and transition animations are smooth" (12 Nov) | Applied to everything this update touches. The full pass comes after the beta (section 4). |
| **The release:** "release it finally today as HUNGER GAMES (BETA)" (14 Nov); "do it yourself" (15 Nov) | <ol><li>A full re-test: done on 18 Nov, alone and with two and three clients.</li><li>Pictures for you.</li><li>Save and commit: version 404 and commit e2226af. The afternoon's later fixes are not saved yet.</li><li>Claude publishes and renames the game in Studio, writes the description, and makes it Public. A draft description and three other titles are in [StoreText.md](StoreText.md).</li><li>The private-server checks in [PublishChecklist.md](PublishChecklist.md) and [Status.md](Status.md).</li></ol>Not released yet. Today the experience is named "HUNGER GAMES (UNDER DEVELOPMENT + TESTING)" and is not published. |

## Done

Built, tested and in the saved place (version 404). Tell Claude if any of these isn't what you meant.

| You asked | What was done |
|---|---|
| **The map:** "i told you to vault the map that u are using and to recreate the map of the trailers i sent and images"; "you ignored the map generation requests i made ... generate the ... map in blendr before you go doing [the rest]" (15 Nov); "WATCH THE TRAILER ... MAKE THE FIRST MAP LIKE THAT" (14 Nov) | <ul><li>Map 1, made in Blender, is the game's arena since 18 Nov: the valley out to radius 2,750, the Horn, 48 plinths, the lake and the stream, 42,583 plants, the far mountains.</li><li>The forest arena is vaulted: out of the game, and kept in `ServerStorage.Vault_ClassicForest` and place versions 258 and 302 so it can come back.</li><li>What went wrong before: Claude had moved this to "after the beta" without your OK.</li><li>Not in yet: the film's hazards and creatures, the cableway, the sites' buildings, tree climbing.</li></ul> |
| **The look:** "it should just be roblox with good graphics realistic SHADERS like how minecraft shaders make minecraft feel real without changing the whole game and making it look ugly" (15 Nov) | <ul><li>A lighting pass on Roblox's own look for Map 1 (18 Nov): clear air, sun, water, mist, dusk and night. No different art style laid over the game.</li><li>A "Shaders: Off / Auto / Full" row in the Menu.</li><li>Not built: cloud banks lying on the mountains.</li></ul> |
| **Hands:** "fix the hands make them robloxy"; "why is there aweird glowy light around the hands just make them not glossy" (15 Nov); "dont make the hands like before js make them one blockish realistic ish" (12 Nov); "the hand shouldnt always be in a punching position only when you.re punching" (14 Nov) | <ul><li>Roblox-style block arms in your avatar's arm colour, matte, with no light on them. The faceted hands are out.</li><li>Relaxed at rest; fists come up only for a punch.</li><li>Every item and swing re-posed. No swing covers more than 13.1 % of the screen, and the bow and spear rest clear of the item bar (18 Nov).</li></ul> |
| **Zoom:** "when you press v there should be a slight zoom" (15 Nov); "v should have a better zoom then it has now" (15 Nov) | Hold V for 2.5×; the mouse wheel takes it from 1.56× to 4× while held. Right-stick click on a controller and a ZOOM button on phones (neither tried on a real device). |
| **Swings:** "sword hitting, axe chopping etc shouldnt be only one animation be a little dynamic" (15 Nov) | <ul><li>Different swings per weapon, a different one each time: 4 for the sword, knife and machete, 3 for the hatchet, the spear and the punch, 2 for the mace.</li><li>Other players see you swing, from its start (seen with two clients, 18 Nov).</li></ul> |
| **Launch intro:** "change the intro of going up to the arena from the grey room and then up in the circular motion ... semi realistic not hyperrealistic" (14 Nov); "the red room with the metal on top is just the transition room before you go to the survival game and it loads up to the room like the images i sent you" (14 Nov) | Built in Roblox from parts and lighting, and seen on two clients at once (18 Nov): <ul><li>the red room under the net;</li><li>the cut to your glass case;</li><li>the rise on the pole, with the camera circling you;</li><li>a white-out, then you stand on your plinth facing the Horn.</li></ul>You can skip it. The Blender-made rooms have not replaced it. Your 18 Nov addition (first person at the end, the sun's glare) is in section 0. |
| **Small rounds:** "why so small" (12 Nov) | On Map 1 a lone player's border starts at 700 studs and two players' at 860 (it was 320 on the forest arena). 48 players get 1,800. |

## 2. Decided

You answered "do it yourself" to the open questions on 15 Nov, so these defaults stand until you say otherwise.

| Question | Decision |
|---|---|
| Map 2's size ("recreated 3 x bigger", 14 Nov) | <ul><li>About **1.75 km across** (radius about 3,100 studs), which is 3× Map 1's area.</li><li>A literal 3× the film's clock would be about 4.4 km. That's too big for 24 players to meet in a 15-minute round, or for the border to bring them together.</li><li>The Blender design so far is 1.46 km.</li></ul> |
| Map 1's challenges ("the challenges of the first movie with a few mix ups each time", 14 Nov) | The upcoming film's hazards, with some of the first film's challenges mixed in, and different mix-ups each round. |
| The ore cableway (yes, "built last", 12 Nov) | It was dropped when the maps changed, and you weren't told. It comes back on Map 1, across the canyon. |
| How much gore | **None (18 Nov):** you asked for the game to be published for all ages, so there is no blood and no wounds. Before that the decision was 13+ (wounds, light blood, limping). |
| Who can play at launch | **Age-checked 16+ players ("No, 16+ for now", 18 Nov).** No fee is paid. Younger players come later. |
| Names inside the game | Our own names: the Horn (Map 1's centre), contenders and so on. The title you chose for the experience is HUNGER GAMES (BETA). |
| The lobby title | It stays LAST STANDING inside the game. |

## 3. Promised to you earlier and not delivered

Each one now has a home.

| Promise | Where it is now |
|---|---|
| The relaxed hands and the new launch intro in the beta (14 Nov) | Both dropped without asking you at the time. Both are built now ("Done"). |
| A polish pass "once the current work is done" (12 Nov) | Never started as a full pass. It's partly in this update, and the full pass comes after the beta. |
| Screenshots of the finished world before you played (10 Nov) | Never sent. From now on, pictures come before every release. |
| Arena challenges "every couple of minutes", built early (11 Nov) | Never started. After the beta (section 4). |
| A custom valley sky and a shading pass (10 Nov) | The shading pass is done on Map 1 (18 Nov, "Done"). A custom sky is not built; the sky has Roblox's own clouds. |
| The goal line that tells you what to do next (12 Nov) | Designed, not built. After the beta. |
| The cableway (12 Nov) | Section 2. |
| A clean playtest confirming the armour "body flies away" (11 Nov) | It was never a game bug: a test agent had frozen the camera. The release test plays put on vests and armour without problems. |

## 4. After the beta

Your own order from the design direction (14 Nov) is "Build a beautiful and believable Hunger Games arena first", then interaction, events, combat and progression, with money last. Your 18 Nov order for what comes next is in section 0.

| Area | What you asked | State |
|---|---|---|
| **Map 2** | The second film's clock arena, bigger, with all its challenges "and more", unlocked after one game on Map 1 (14 Nov) | Designed; Blender pass 1 done. Its size is decided (section 2). |
| **The launch rooms in Blender** | The red room, the glass cases and the pole hall, semi-real | Blender pass 2 done. The game still uses the Roblox-built intro. |
| **The world art** | "the grainy floor is very tacky ... generate the pebbleish design on blendr ... you make them yourself ... realistic blockish ... trees and buildings are tacky" (12 Nov) | The forest arena's trees, buildings and ground left the game with the vault. Map 1's plants and landmarks are our own Blender models on Roblox's own terrain materials. The lobby is unchanged. |
| **Fighting** (you asked to be reminded) | "we will focus on attacks and battle manaeuvouring later remind me" (12 Nov): wind-ups, quick and heavy attacks, blocking | Not started. First in your 18 Nov order, after the sounds, the UI and the rise. |
| **Weapons and the bow** (reminder) | "weapon list needs to be improved" (12 Nov). For the bow: 3–4 a round, on-target aim only within 60 studs, and "make the distance and drawing more accurate" | Only the 90-damage headshot is done. The rest waits for the weapons work ([WeaponsAndObjectives.md](../design/WeaponsAndObjectives.md)). |
| **Truces** | "Yes" (12 Nov) | Designed, not built. |
| **Objectives** | "what the objectives are etc make it intuitive and inspired from the movie" (12 Nov) | Designed: the goal line and the round's ten acts. Not built. |
| **Arena challenges** | "EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES - ESCAPE LAVA RAIN ETC WILD DOGS MUTATED ANIMALS" (11 Nov); events "periodically" with a reason, and a border that does "not shrink too quickly" (14 Nov) | Designed per map, not built. Today the only events are the Feast, the border, the Roll Call and the Last Stand. On Map 1 the border never moves faster than 3.5 studs a second. The early first border closing you picked on 12 Nov was never built. |
| **Natural interaction** | Climbing trees, hunting squirrels and birds, gathering, shelter, tracking, water (14 Nov) | Drinking from the lake and the stream exists. Map 1 has no tree climbing yet. Wildlife and hunting are not started. |
| **The train and station** | "AND MAKE THE TRAINS LOOK LIKE THEM TOO" (14 Nov); the TRIBUTE spec's seven cars | Blender pass 2 done. Your TRIBUTE spec says "Build the arena combat loop before the train", so it follows the fighting work. Third in your 18 Nov order. |
| **The training room** | "train goes to training room like in the movies and people get to test diff kits and abilities and chests will have diff items based on such" (14 Nov) | Designed (the Training Centre), not built. |
| **The TRIBUTE spec** | Hit regions, wounds, blood, knockback and stagger, new movement values, a full animation set (14 Nov) | Not started. Wounds and blood are out since 18 Nov (no blood, no wounds). The new movement values change the "weighty + agile" feel you picked on 10 Nov, so you'll be asked first. Stock R15 stays. |
| **Voice chat** | "a mode for people to be able to vc - with voicechat proxiimity" (14 Nov) | Designed and drafted ([VoiceMode.md](../design/VoiceMode.md)). It goes in after the release. Its whisper key moves off V, which is now the zoom. |
| **Loading screen** (reminder) | "remind me we still need a loading screen animation" (14 Nov) | Not started. This is your reminder. |
| **Ads** (reminder) | "advertise on twitter youtube and tiktok" (14 Nov) | After the beta is public. Claude can draft the posts and clips; posting is yours. |
| **Showcase video** (reminder) | "make a show case video after using seeddance and blendr and show the game" (14 Nov) | After the release. You need to sign in to Higgsfield with /mcp first. |
| **Progression and money** | Gold, buying Gold with Robux, training tokens and attributes, game passes, tasteful cosmetics, story mode and other modes (11 and 14 Nov) | Not started. Arena first, as you wrote, with no pay-to-win and no pushy pop-ups. |
| **Kits, the wheel and loot boxes** | "we should have a basic weapons list (like kits the players can choose where its sth basic like an arrow some apples etc) that spawns in the half point of the game - so the epic ones will be drawn in a wheel and can also be bought with in game currency like in hypershot by buying loot boxes etc ygwim?" (18 Nov) | Not started; part of the weapons work. **Decided 18 Nov:** epic items have "overall weapon stats better and have stars etc": they are stronger, with a star rating. This replaces "no pay-to-win" for weapons. Still open: what "the half point" means (Claude's reading: your chosen kit arrives for you at the middle of the round). Paid random items have Roblox rules: odds must be shown, they are switched off in some countries, and the ratings form must say so. |

## 5. Still open

These are your calls. The defaults are in use meanwhile.

- **For the launch:**
  - the title and the icon: the icon (a golden bird in a ring) is close to the films' pin, and with the title it is a takedown risk. Three other titles are in [StoreText.md](StoreText.md);
  - the private-server price, which can't be changed later without cancelling every active private server.
- **From the test plays:**
  - hunger drains slowly (a full bar lasts 14 minutes, so it rarely matters);
  - bag size (6 slots, or 7–8);
  - taller avatars can climb higher ledges than shorter ones.
- **The eight roadmap questions (11 Nov):**
  - whether challenges can kill;
  - realistic or monstrous hounds;
  - the fighting model;
  - 24 or 48 players (Map 1 is built for 48);
  - a premium pass;
  - story arcs earned or sold;
  - perks;
  - adult story characters.

  See [Roadmap.md](../Roadmap.md) section 8.
- **Map details:** the horn's colours, how long the launch lasts, whether the flower-bed traps are visible or hidden, and whether the Training Centre becomes the waiting area. See [TwoArenas.md](../design/TwoArenas.md), "Waiting on you".
- **Training tokens for Robux:** your 14 Nov direction says yes; the older plans said no.
- **Things only you can do:**
  - the launch steps on your Roblox account: the age check or ID check, 2-step verification, keeping Plus active, and sending the age questionnaire. See [PublishChecklist.md](PublishChecklist.md), section 4;
  - add the universe:write permission to the API key, so Claude can manage the game's settings directly;
  - make a workbench copy of the place for building the maps.
- **The Blender connector:** it's built (tools/blender_mcp). Approve the "blender" server when a session asks you, and it's live.

## 6. Your standing rules

- **Look:** "it should just be roblox with good graphics realistic SHADERS"; "you are not incorporating realisim you are emmulating it to the game design of roblox natural asethetic"; "semi realistic not hyperrealistic which makes the game tacky"; semi-realistic colour tones.
- **Our own art:** made by us in Blender, "instead of taking it from the opensource asset list online".
- **Hands:** one design: "robloxy" block arms, "not glossy" (15 Nov, replacing "blockish realistic ish"). Relaxed unless punching. Never bring back an old version.
- **No blood and no wounds** (18 Nov), so the game can be rated for all ages.
- **Motion:** weighty, smooth and varied, never like a stock Roblox avatar.
- **The films:** film-faithful places, launch, trains and challenges. No film frames, logos or text anywhere in the game or the repo.
- **Working style:** ask about aesthetics and the player's experience ("ask me if you have any questions regarding user aesthetic and user experience design"). Otherwise act ("cant you switch it yourself", "you do what you think is necessary", "do it yourself"). Use multi-agent workflows, keep every running agent updated, and understand all your messages before acting ("read through all my prompts first and understand what you are doing").
