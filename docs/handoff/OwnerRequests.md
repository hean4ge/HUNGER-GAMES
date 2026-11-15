# Everything you've asked for, and where it stands

*Checked on 15 November 2026. Claude re-read all 90 of your messages, the 10 pictures you sent and every reply it gave you. Eight checkers then compared each request with the game's code, the docs and Studio. Dates are your local dates. Your words are quoted as you typed them.*

This page is the one list of your requests. [Status.md](Status.md) says what the game does today; this page says what you asked for and whether it's done. Update both together.

---

## 1. Being built now (the beta update)

You approved this batch with "Yes, all of it" (15 Nov), "Yes, in the beta" for the launch intro, and "do it yourself" for the rest.

| You asked | What's being done |
|---|---|
| **Fix the test plays' findings:** "run many test plays ... if there are game design issues infform me we can fix them and then release it" (14 Nov) | <ul><li>**Border and water:** the day-1 border tip; the water marker coming back after the first drink.</li><li>**Crates:** spilled items where you can see them, and "Take all" staying until used; crates no longer inside each other; loot only inside the border.</li><li>**Weapons:** thrown knives and spears landing on the crosshair; the bow's right-click hint; no sprinting with a drawn bow; arrows no longer filling the slots of a player with no bow.</li><li>**Training dummies:** moved off your path, with a health bar that doesn't cover the compass.</li><li>**Practice rounds:** wording that makes sense when you're alone, and no "#1" for a death.</li><li>**Saving and spectating:** settings no longer reset by a bad save; spectating kept when you respawn.</li><li>**Swings:** the first swing after a heavy weapon now counts.</li><li>**Small bugs:** the rock pocket that traps players; the brief "WAITING FOR PLAYERS" flash; controllers recognised from the first second.</li><li>**HUD:** the draw meter no longer covers far targets; the compass labels; two countdowns at once; the death card over HOW TO PLAY; the settings menu closing at the countdown; a warning when a vest on the ground is worse than yours.</li></ul> |
| **Small rounds:** "why so small" (12 Nov) | Small rounds start with the border at 320 studs, which makes the map feel small. It's being opened up. |
| **Hands:** "dont make the hands like before js make them one blockish realistic ish" (12 Nov); "the hand shouldnt always be in a punching position only when you.re punching" (14 Nov) | <ul><li>The new faceted hands: uploaded, relaxed at rest, a fist only while punching.</li><li>Every item re-posed: bow, spear, food, bottle, bandage, vest, medkit, every weapon.</li><li>The bow keeps the crosshair clear.</li><li>In-game pictures at midday and dusk come to you before release.</li></ul> |
| **Zoom:** "when you press v there should be a slight zoom" (15 Nov) | A slight zoom, gentler than the bow's aim. On V (hold), right stick click on a controller, and a button on phones. |
| **Swings:** "sword hitting, axe chopping etc shouldnt be only one animation be a little dynamic" (15 Nov) | <ul><li>3–4 clearly different swings per weapon, a different one each time (today a bug replays the first unless you click within half a second).</li><li>Other players now see you swing; today they see nothing.</li></ul> |
| **Launch intro:** "change the intro of going up to the arena from the grey room and then up in the circular motion ... semi realistic not hyperrealistic" (14 Nov); "the red room with the metal on top is just the transition room before you go to the survival game and it loads up to the room like the images i sent you" (14 Nov) | Built in Roblox for the beta from parts and lighting: <ul><li>the red room under the net;</li><li>the cut to your glass case;</li><li>the rise on the pole, with the camera circling you;</li><li>then today's plate rise, facing the Spire.</li></ul>You can skip it. The Blender version replaces it when Map 1 ships. |
| **Polish:** "touch up on all the assets so far making sure they are clean and transition animations are smooth" (12 Nov) | Applied to everything this update touches. The full pass comes after the beta (section 4). |
| **The release:** "release it finally today as HUNGER GAMES (BETA)" (14 Nov); "do it yourself" (15 Nov) | <ol><li>A full re-test.</li><li>Pictures for you.</li><li>Save and commit.</li><li>Claude publishes and renames the game in Studio, writes the description, and makes it Public.</li><li>The private-server checks in [PublishChecklist.md](PublishChecklist.md).</li></ol> |

## 2. Decided

You answered "do it yourself" to the open questions on 15 Nov, so these defaults stand until you say otherwise.

| Question | Decision |
|---|---|
| Map 2's size ("recreated 3 x bigger", 14 Nov) | <ul><li>About **1.75 km across** (radius about 3,100 studs), which is 3× Map 1's area.</li><li>A literal 3× the film's clock would be about 4.4 km. That's too big for 24 players to meet in a 15-minute round, or for the border to bring them together.</li><li>The Blender design so far is 1.46 km.</li></ul> |
| Map 1's challenges ("the challenges of the first movie with a few mix ups each time", 14 Nov) | The upcoming film's hazards, with some of the first film's challenges mixed in, and different mix-ups each round. |
| The ore cableway (yes, "built last", 12 Nov) | It was dropped when the maps changed, and you weren't told. It comes back on Map 1, across the canyon. |
| How much gore | **13+:** wounds you can see, light blood and limping. No severing. A 17+ mode would need age-verified players. |
| Names inside the game | Our own names for now: the Spire, contenders and so on. The experience's title is HUNGER GAMES (BETA). |
| The lobby title | It stays LAST STANDING inside the game. |

## 3. Promised to you earlier and not delivered

Each one now has a home.

| Promise | Where it is now |
|---|---|
| The relaxed hands and the new launch intro in the beta (14 Nov) | Both dropped without asking you. Both are in this update (section 1). |
| A polish pass "once the current work is done" (12 Nov) | Never started. It's partly in this update, and the full pass comes after the beta. |
| Screenshots of the finished world before you played (10 Nov) | Never sent. From now on, pictures come before every release. |
| Arena challenges "every couple of minutes", built early (11 Nov) | Never started. After the beta (section 4). |
| A custom valley sky and a shading pass (10 Nov) | Partly done. The rest is after the beta. |
| The goal line that tells you what to do next (12 Nov) | Designed, not built. After the beta. |
| The cableway (12 Nov) | Section 2. |
| A clean playtest confirming the armour "body flies away" (11 Nov) | It was never a game bug: a test agent had frozen the camera. The release test plays put on vests and armour without problems. |

## 4. After the beta

Your own order from the design direction (14 Nov) is "Build a beautiful and believable Hunger Games arena first", then interaction, events, combat and progression, with money last.

| Area | What you asked | State |
|---|---|---|
| **Map 1** | The green land from *Sunrise on the Reaping* ("WATCH THE TRAILER ... MAKE THE FIRST MAP LIKE THAT", 14 Nov), recreated in Blender in semi-real colour tones | Blender pass 2 is done (commit 13a5c7c) but not yet good enough to show you. About 4 weeks to a playable build ([TwoArenas.md](../design/TwoArenas.md)). |
| **Map 2** | The second film's clock arena, bigger, with all its challenges "and more", unlocked after one game on Map 1 (14 Nov) | Designed; Blender pass 1 done. Its size is now decided (section 2). |
| **The launch rooms in Blender** | The red room, the glass cases and the pole hall, semi-real | Blender pass 2 done. They replace the Roblox-built intro when Map 1 ships. |
| **The world art** | "the grainy floor is very tacky ... generate the pebbleish design on blendr ... you make them yourself ... realistic blockish ... trees and buildings are tacky" (12 Nov) | Not started in the game. The trees, buildings and AI-made ground are still in. They'll be remade in the faceted style of the new hands (style A, which also answers the style test). |
| **Fighting** (you asked to be reminded) | "we will focus on attacks and battle manaeuvouring later remind me" (12 Nov): wind-ups, quick and heavy attacks, blocking | Not started. This is your reminder. |
| **Weapons and the bow** (reminder) | "weapon list needs to be improved" (12 Nov). For the bow: 3–4 a round, on-target aim only within 60 studs, and "make the distance and drawing more accurate" | Only the 90-damage headshot is done. The rest waits for the weapons work ([WeaponsAndObjectives.md](../design/WeaponsAndObjectives.md)). |
| **Truces** | "Yes" (12 Nov) | Designed, not built. |
| **Objectives** | "what the objectives are etc make it intuitive and inspired from the movie" (12 Nov) | Designed: the goal line and the round's ten acts. Not built. |
| **Arena challenges** | "EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES - ESCAPE LAVA RAIN ETC WILD DOGS MUTATED ANIMALS" (11 Nov); events "periodically" with a reason, and a border that does "not shrink too quickly" (14 Nov) | Designed per map, not built. Today the only events are the Feast, the border, the Roll Call and the Last Stand. The early first border closing you picked on 12 Nov was never built, and your 14 Nov direction asks for a slow border, so the two are settled together with the maps. |
| **Natural interaction** | Climbing trees, hunting squirrels and birds, gathering, shelter, tracking, water (14 Nov) | Water and partial tree climbing exist. Climbing to the top, wildlife and hunting are not started. |
| **The train and station** | "AND MAKE THE TRAINS LOOK LIKE THEM TOO" (14 Nov); the TRIBUTE spec's seven cars | Blender pass 2 done. Your TRIBUTE spec says "Build the arena combat loop before the train", so it follows the fighting work. |
| **The training room** | "train goes to training room like in the movies and people get to test diff kits and abilities and chests will have diff items based on such" (14 Nov) | Designed (the Training Centre), not built. |
| **The TRIBUTE spec** | Hit regions, wounds, blood, knockback and stagger, new movement values, a full animation set (14 Nov) | Not started. The 13+ parts come with the fighting work. The new movement values change the "weighty + agile" feel you picked on 10 Nov, so you'll be asked first. The custom severable rig is out at 13+, and stock R15 stays. |
| **Voice chat** | "a mode for people to be able to vc - with voicechat proxiimity" (14 Nov) | Designed and drafted ([VoiceMode.md](../design/VoiceMode.md)). It goes in after the release. Its whisper key moves off V, which is now the zoom. |
| **Loading screen** (reminder) | "remind me we still need a loading screen animation" (14 Nov) | Not started. This is your reminder. |
| **Ads** (reminder) | "advertise on twitter youtube and tiktok" (14 Nov) | After the beta is public. Claude can draft the posts and clips; posting is yours. |
| **Showcase video** (reminder) | "make a show case video after using seeddance and blendr and show the game" (14 Nov) | After the release. You need to sign in to Higgsfield with /mcp first, and the dry-looking waterfall gets fixed before filming. |
| **Progression and money** | Gold, buying Gold with Robux, training tokens and attributes, game passes, tasteful cosmetics, story mode and other modes (11 and 14 Nov) | Not started. Arena first, as you wrote, with no pay-to-win and no pushy pop-ups. |

## 5. Still open

These are your calls. The defaults are in use meanwhile.

- **From the test plays:**
  - hunger drains slowly (a full bar lasts 14 minutes, so it rarely matters);
  - bag size (6 slots, or 7–8);
  - taller avatars can climb higher ledges than shorter ones.
- **The eight roadmap questions (11 Nov):**
  - whether challenges can kill;
  - realistic or monstrous hounds;
  - the fighting model;
  - 24 or 48 players;
  - a premium pass;
  - story arcs earned or sold;
  - perks;
  - adult story characters.

  See [Roadmap.md](../Roadmap.md) section 8.
- **Map details:** the horn's colours, how long the launch lasts, whether the flower-bed traps are visible or hidden, and whether the Training Centre becomes the waiting area. See [TwoArenas.md](../design/TwoArenas.md), "Waiting on you".
- **Training tokens for Robux:** your 14 Nov direction says yes; the older plans said no.
- **Two things only you can do:**
  - add the universe:write permission to the API key, so Claude can manage the game's settings directly;
  - make a workbench copy of the place for building the maps.
- **The Blender connector:** it's built (tools/blender_mcp). Approve the "blender" server when a session asks you, and it's live.

## 6. Your standing rules

- **Look:** "you are not incorporating realisim you are emmulating it to the game design of roblox natural asethetic"; "semi realistic not hyperrealistic which makes the game tacky"; semi-realistic colour tones.
- **Our own art:** made by us in Blender, "instead of taking it from the opensource asset list online".
- **Hands:** one blockish, realistic-ish design. Relaxed unless punching. Never bring back an old version.
- **Motion:** weighty, smooth and varied, never like a stock Roblox avatar.
- **The films:** film-faithful places, launch, trains and challenges. No film frames, logos or text anywhere in the game or the repo.
- **Working style:** ask about aesthetics and the player's experience ("ask me if you have any questions regarding user aesthetic and user experience design"). Otherwise act ("cant you switch it yourself", "you do what you think is necessary", "do it yourself"). Use multi-agent workflows, keep every running agent updated, and understand all your messages before acting ("read through all my prompts first and understand what you are doing").
