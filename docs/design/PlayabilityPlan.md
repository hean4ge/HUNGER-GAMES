# LAST STANDING — Playability plan

*Lead designer, 11 November 2026. You asked for the game to be easy to play, intuitive and fun. This plan turns web research (onboarding, game feel, survival design and the Roblox platform) and a read-only audit of the live scripts into a list of changes, in order. It keeps your realistic look, our original names and Roblox's rules. It builds on the [Roadmap](../Roadmap.md) and links to it instead of repeating it.*

**In short (plain English)**
- **What goes wrong today.** A newcomer alone on a server waits forever. Nothing tells them how to eat, drink, throw a spear or climb. Their health quietly stops coming back after about 4 minutes, and they usually learn about thirst by dying of it at night. Deaths give no tip, and SPECTATE shows a random survivor instead of the killer. Small rounds are a long, empty walk, and a round can end with nobody winning.
- **The fix, in order.** Fifteen small changes of a day or less each (section 3), starting with a new player's first five minutes: a practice round when you're alone, a one-line hint for whatever you hold, the goal and the opening choice shown on the launch plate, healing and thirst you can see, and deaths that give a tip and show you your killer.
- **The bigger work** (section 4): attacks you can see coming, phones that aim properly, an arena and a clock sized to the number of players, and a Practice Yard on the Tor.
- **It stays realistic.** Help for newcomers fades as they learn and can be switched off. Clues in the world stay physical: canvas straps on crates, worn bark on climbable trees, trails down to water. Nothing in this plan is sold.
- **Start with a test.** Watch 3–5 friends play once now (section 6), so you can see what each change actually improves.

**How to read it**
- Section 1 sets 12 rules (P1–P12), each with its source.
- Section 2 walks through a new player's first 15 minutes today and numbers each friction point (F1–F20).
- Section 3 fixes the worst of them with 15 quick wins of a day or less each, most impact first.
- Section 4 lists the bigger changes (2–10 days) and where they sit in the Roadmap.
- Sections 5–7 give the controls and HUD after the changes, a test to run with 3–5 friends, and five decisions for you.

**Notes**
- Line numbers come from the Studio scripts as read on 11 November 2026. Other agents are editing the place, so if a line has moved, search for the function name.
- A **new player** has played fewer than 3 real rounds. That is the `RoundsPlayed` attribute, read at the Countdown, before `RoundService` adds one at the horn (line 357).
- **Guidance** is the setting proposed in Q1: Auto (help for new players that fades as they learn), Always, or Off.
- Your earlier reports:
  - Movement input after Roblox's controls change is fixed. QW15 guards against it coming back.
  - The bow no longer covers the target. B7 turns that check into a rule for every first-person pose.
  - The realistic jump is in progress (movement:polish). Section 4 adds a response-time test for it.
  - The armour "body flies away" report came from an agent's frozen test camera, not from the game.

---

## 1. The principles

| # | We design by this rule | Source |
|---|---|---|
| P1 | **Fun in the first minute, a round within two.** Nobody waits with nothing to do. A lone player still gets a round. | Roblox ranks first-play bounce (players who leave within 60 s, or within 61–180 s) among its most important signals for Home recommendations: [Discovery](https://create.roblox.com/docs/discovery). New users should reach the fun within about 5 minutes: [Engagement](https://create.roblox.com/docs/production/analytics/engagement). |
| P2 | **Teach at the moment of use, then get out of the way.** A hint appears the first time an action is needed, shows this device's button, and fades once learned. It comes back only for a player who is stuck. | [Roblox onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques) (contextual tutorials, timed hints); [World 1-1 as the tutorial](https://www.gamedeveloper.com/design/how-miyamoto-built-i-super-mario-bros-i-legendary-world-1-1) |
| P3 | **Say less, show more.** People read about a fifth of the words on a screen. One line in the line of sight beats a panel of 13 rows. | [NN/g: how little users read](https://www.nngroup.com/articles/how-little-do-users-read/); [Roblox onboarding](https://create.roblox.com/docs/production/game-design/onboarding) (teach what to do and why) |
| P4 | **No hidden rule may kill you.** Anything that can hurt you shows before it bites: on the meter, in the body, in the world. | [NN/g heuristic 1, visibility of system status](https://www.nngroup.com/articles/ten-usability-heuristics/); [The Long Dark's contextual HUD](https://www.gamedeveloper.com/design/long-dark-survival-game-hud-ui) |
| P5 | **Every threat has a tell.** A wind-up before a swing, a creak before an arrow. Arena threats follow one format: a sound, then a sign, then the event. | [Enemy attacks and telegraphing](https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing); [Readability in action games](https://www.gamedeveloper.com/game-platforms/designing-for-difficulty-readability-in-arpgs); [zone warnings: audio about 30 s and visuals about 15 s ahead](https://uefncentral.com/id/blog/advanced-battle-royale-zone-mechanics-uefn); [arena-events.md](arena-events.md) §2, rule 2 |
| P6 | **Every death teaches.** Say what killed you, how, and what would have saved you. Then let the player watch the one who did it. | [Making death fun](https://www.gamedeveloper.com/design/making-death-fun-something-medal-of-honor-needs-to-fix-for-launch-); [DOORS' death tips](https://rblxguide.com/games/doors/entities/guiding-light); [Fortnite solos spectate your eliminator](https://www.oneesports.gg/fortnite/how-to-spectate-in-fortnite-2-easy/) |
| P7 | **Every press gets an answer.** The first visible reaction comes within about 4 frames (67 ms at 60 fps). A refused action still answers with a sound or a line. | [Measuring responsiveness (Mick West)](https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games); [Game feel (Swink)](https://www.gamedeveloper.com/design/game-feel-the-secret-ingredient); [NN/g heuristic 9](https://www.nngroup.com/articles/ten-usability-heuristics/) |
| P8 | **Forgive quietly.** Invisible grace windows (coyote time, input buffers, prompts that don't flicker) make realistic movement feel fair without looking gamey. | [Celeste and forgiveness](https://maddymakesgames.com/articles/celeste_and_forgiveness/) |
| P9 | **Both choices at the horn must pay.** Rushing the Spire and running for the trees are both real bets. | [Designing PUBG's maps](https://www.gamedeveloper.com/design/designing-the-giant-battle-royale-maps-of-i-playerunknown-s-battlegrounds-i-); [top-tier gear snowballs](https://www.gamedeveloper.com/design/examining-my-gameplay-issue-with-battle-royale-design) |
| P10 | **Pace in peaks and rests, sized to who is there.** A beat every couple of minutes, a rest after a peak, an arena that fits the head-count, and a finale that always ends. | [The AI Systems of Left 4 Dead (Booth, 2009)](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf); [PUBG Update 42.1 zones](https://pubg.com/news/10179); [a zone timed to the players left](https://www.pcgamer.com/pubgs-savage-map-has-a-blue-zone-that-adjusts-its-timing-based-on-the-number-of-players-left) |
| P11 | **Realism comes from the world, the body and the sound, not from hiding information.** Keep the HUD thin and contextual. Make actions feel physical through breath, cloth, dust and hands. Never hide what a decision needs. | [Removing the HUD (Iacovides et al., CHI PLAY 2015)](https://oro.open.ac.uk/46759); [Juice It or Lose It](https://www.gamedeveloper.com/design/video-is-your-game-juicy-enough-); [Valve: art that serves play](https://www.gamedeveloper.com/art/in-depth-how-valve-makes-art-to-enhance-gameplay) |
| P12 | **Every device, every player, and nothing sold that changes play.** Every action works on touch, gamepad and keyboard. Nothing is told by colour or sound alone. | [Most Roblox sessions are on mobile](https://create.roblox.com/docs/input/mobile); [Roblox adaptive design](https://create.roblox.com/docs/production/publishing/adaptive-design); [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/); [Roadmap](../Roadmap.md) §7 |

**Guard rails for everything below**
- **Realism.** Help for new players is temporary and can be switched off (Q1). Hints use the HUD's existing thin key-cap style: no bouncing cartoon UI and no floating damage numbers. In-world cues are physical: canvas straps on crates, worn bark on climbable trees, game trails to water, birds that flush, a dry swallow when you're thirsty.
- **Original IP.** All copy uses our names: contenders, the Spire, launch plates, the Offering, the Knell, the Roll Call, the Tor. The code, the HUD's event line (`HUDController` 827–833) and the server's warnings (`ArenaService` 294 and 306) still say "Feast"; QW9 retires the player-facing strings early. New text goes through the banned-terms check ([Roadmap](../Roadmap.md) §7).
- **Roblox rules.** Nothing in this plan is sold, and nothing is for sale on the death screen. Phones are a required test device.

---

## 2. A new player's first 15 minutes, today

Times use the live `Config`. Studio's FastTimers shorten the lobby and the countdown. A solo Studio test is always a practice round (`Config` lines 318–327), so it can't show real pacing; a Studio test with 4–8 clients and FastTimers off can.

| When | What the player sees and does | Friction |
|---|---|---|
| 0:00, join | Lands on the Tor in third person. The title, "Outlast everyone.", a record card (0 · 0 · 0) and, on PC and tablets, the HOW TO PLAY panel already open: 4 tips and 13 control rows (`LobbyController` line 365; `SettingsController` 68–113; `UIBuilder` TIPS 24–29). Five notice-board lines, one of them wrong: "late in the day the border closes in", though it moves at 10:00, on the second morning (`WorldGen.AssetBuilder.Props` 438–444). | **F1** A wall of text, with the goal buried in it. → QW6 |
| Alone on the server | "WAITING FOR PLAYERS 1 / 2", forever: live servers need 2 players (`Config` line 14; `LobbyController` 206). Practice rounds and training dummies exist, but only in Studio (`RoundService` 427; `CombatService` 26, 597–607). | **F2** Nothing to do and no end in sight. → QW1 |
| A round is running | "ROUND IN PROGRESS · 9 REMAIN", with no end time (`LobbyController` 215). Someone who joins at the horn waits up to 945 s. The lobby allows movement only ([GameDesign](../GameDesign.md) §7). | **F3** A 15-minute wait with no end shown. → QW4, B4, B9 |
| Intermission, 25 s | "NEXT ROUND · Contenders are chosen in 25 seconds" (`RoundService` 445–453). | — |
| Countdown, 10 s | Teleported onto a launch plate. It rises from 0.8 s to 4.2 s, then the player stands frozen for about 6 s under "Stay on your plate · the arena opens in N" (`RoundService` 388). These are the most-watched 10 seconds of the round. | **F4** They say nothing about the goal or the choice. → QW6 |
| The horn, 0:00 | "GO" and the horn. 1.6 s later "SURVIVE · Last one standing wins" covers the screen for 4 s (`RoundService` 362–371), while the player is sprinting. | **F5** The banner hides the first sprint, and nothing says how to sprint. → QW6 |
| 0:01–0:30, the rush | Neighbours stand 13.6 studs apart, and the Spire's 10 tier-3 crates are 32.5 studs away, holding about a dozen weapons for up to 24 rushers. A crate is a 0.6 s hold. Then 2–4 items spill, and each needs its own E press (`LootService` 810–822 and 446–465). Rivals swing and draw without moving: no client listens to the `CombatAction` remote (`Shared.Net` 17; `ViewmodelController` 624 hears only the local signal). A full-draw bow headshot does 100, exactly a full health bar (`ItemDefs` 44–47; `Config` 71). | **F6** 3–5 presses per crate in the scrum. → QW8 · **F7** Attacks you can't see coming. → B1, QW9 · **F8** One arrow nobody heard kills from full health. → QW9 |
| 0:05–0:30, the run | The first ground loot turns up in 5–15 s, usually food. A ground marker holds a weapon about 9% of the time (65% spawn chance × 12/89 of the tier-1 weight; `Config` 304, `ItemDefs` 92–103). The first weapon crate is usually 200–400 studs out. Crates carry no mark beyond their mesh, and the realistic crates will blend in even more (`LootService` 804–838). | **F9** Running away leaves you unarmed for half a minute or more. → QW7 · **F10** Crates are hard to spot. → QW11 |
| The first item | A 1.8 s toast: "Wild Berries · COMMON · FOOD" (`HUDController` 481–509). Nothing says "hold left click to eat". `ItemDefs` holds instructions ("Hold Aim and attack to throw.", line 36; "Look at water and press Drink to fill it.", line 71), but no script shows them (line 84). The only hint in the arena is Drink, while looking at water (`InventoryController` 579–647). Throwing the spear, filling a bottle and climbing a tree are never taught. | **F11** Items never explain themselves. → QW2 |
| Any time | A click in the first moment after switching items is dropped (`CombatController` 90, 651–662). Pressing an empty slot puts your weapon away (`InventoryController` 407–409). Holding Attack keeps eating past full (203–215). G throws away the whole stack. Attacking while climbing does nothing, and nothing says why (`CombatController` 143–145). | **F12** Presses and items lost without a word. → QW12 |
| About 4:03 (2:32 if sprinting) | Thirst passes 55 and health stops coming back. Nothing on screen says so (`PlayerService` 774–778; `Config` 77–79). | **F13** A hidden rule. → QW5 |
| 0:40–9:05 | The opening music ends at 0:40. Roll Call 1 at 5:45 is the only scheduled beat before the Offering warning at 9:05. The HUD shows the next event only in its last 60 s (`HUDController` 818–835). | **F14** An empty middle. → QW9, Phase 2a |
| About 6:45, at night | Thirst turns LOW (25%; `HUDController` 53) after Roll Call 1, in the dark. Along the plate bearings the nearest water is 192–444 studs from the Spire, and 8 of the 24 bearings cross none. The compass shows only the Spire (`HUDController` 739–771). Thirst runs out at 9:00 and kills at about 10:07. | **F15** The first survival lesson arrives as a death. → QW5, QW10 |
| Death | The cannon (the Knell soon), the kill feed, and "#7 OF 24 · You died of thirst" with no lesson (`NotificationController` 461–486). SPECTATE opens on the first survivor in alphabetical order, not on your killer (`SpectateController` 45–60, 366–367). The card closes itself after 15 s, and the player is back in the lobby 4 s after death. | **F16** A death that teaches nothing. → QW4 |
| 9:05–15:00 | The Offering at 9:50, then the border closes from 10:00 to 13:50 (640 → 35 studs). Roll Call 2 at 14:05 turns off all music, the final-stand track included, for about 70–100 s (`FallenRecapController` 582–583). At 15:00 with two or more alive: "TIME'S UP · Nobody claims the win" (`RoundService` 328–330). | **F17** A finale that can fizzle out. → QW14 |
| Ending, 10 s | A victory panel and a top-10 table. Only the winner's stats move; 23 of 24 leave with nothing (`RoundService` 341–344). The next horn is 45 s later. | **F18** Nothing to show for a good run. → B5, B6 |
| Small rounds | With 2–8 contenders the border still starts at 640 studs and still waits until 10:00. The nearest rival is about 200–400 studs away, and other players' footsteps carry 90 studs (`AudioController` 52). Under the Warden plan, a 2-contender round would get no events at all ([arena-events.md](arena-events.md) §3 and §5). | **F19** An empty walk in the woods. → QW3, B3, Phase 2a (section 4) |
| Every device | Touch: ATTACK and DRAW are plain buttons, so holding one probably can't steer the camera (check on a phone; `Shared.Input` 96–187). "Look sensitivity" changes only the mouse (`CameraController` 280–292). Gamepad hints print "X" for ButtonX (`HUDController` 1024–1035), which is Square on PlayStation; an X there means Cross, the jump button. Keyboard sprint and crouch are hold-only. | **F20** Controls that fit only the mouse. → QW13, B2, B11 |

---

## 3. Quick wins

Fifteen changes of a day or less each, ordered by how much they improve a new player's first 15 minutes. Sizes assume one developer with AI help, as in the Roadmap.

| # | Quick win | Fixes | Main scripts | Size |
|---|---|---|---|---|
| QW1 | Never wait alone | F2 | RoundService, CombatService, LobbyController | 1 day |
| QW2 | Say what the held item does | F11 | InventoryController, HUDController, CombatController, new Shared.ActionHints, DataService | 1 day |
| QW3 | Small rounds start small | F19 | RoundService, ArenaService, LootService, ArenaController | ½ day |
| QW4 | Deaths that teach, and a wait with an end | F16, F3 | NotificationController, SpectateController, PlayerService, LobbyController | 1 day |
| QW5 | Show thirst and healing | F13, F15 | PlayerService, HUDController, NotificationController, AudioController | 1 day |
| QW6 | The goal and the choice, where players look | F1, F4, F5 | RoundService, LobbyController, WorldGen.AssetBuilder.Props | ½ day |
| QW7 | Make running away pay | F9 | ItemDefs, LootService, loot markers | 1 day |
| QW8 | Loot a crate in one press | F6 | LootService, InventoryService, HUDController | 1 day |
| QW9 | Threats you can see coming | F7, F8, F14 | HUDController, ArenaService, AudioController, ItemDefs | 1 day |
| QW10 | Point to water when thirsty | F15 | HUDController, new Shared.WaterPoints | 1 day |
| QW11 | Crates you can spot | F10 | ItemModels, LootService, a client controller | 1 day |
| QW12 | Never swallow a press or an item | F12 | CombatController, InventoryController, InventoryService | 1 day |
| QW13 | Controls that fit every device | F20 | SettingsController, CameraController, MovementController, HUDController, DataService | 1 day |
| QW14 | Every round ends with one winner | F17 | ArenaService, RoundService, FallenRecapController, NotificationController | 1 day (+½ for the epilogue) |
| QW15 | Measure the first session and guard the controls | all | new OnboardingService, a Studio input check | 1 day |

**Order of work.** Run the baseline test in section 6 first, so you can tell what helped. Then build QW15 (it protects everything else), then QW1–QW6, which together cover a new player's first five minutes, then the rest in order. Do QW3 and QW14 together, because both change the border in `ArenaService`, and QW2 with QW13, because both change the hint under the crosshair and the button names it prints.

### QW1 · Never wait alone (1 day) — fixes F2

**What changes, where**
- `RoundService.step` (lines 508–518): on a live server, once one player has waited alone in the Lobby for 30 s, start Intermission anyway, and don't drop back to Lobby at line 513 for that solo Intermission. `enterCountdown` already makes a one-contender round a practice round (line 427), with its own banner and countdown caption (lines 366–367 and 388).
- `CombatService.wantDummies` (line 598): remove the `Config.IsStudio` condition, so live practice rounds get the 3 training dummies (`Config.Combat.PracticeDummies`, line 275).
- `RoundService.activeTick` (lines 455–470): if someone arrives in the lobby during a practice round, announce "A CONTENDER HAS ARRIVED · A FULL ROUND STARTS SOON" and end the practice 60 s later. End it with the lone contender as the winner, so the card reads "[name] · survived the practice round" (`endRound`, line 327) instead of today's practice line "You were eliminated" (line 333). The newcomer then hears the horn of a full round about 1:45 after joining (60 s + Ending 10 s + Intermission 25 s + Countdown 10 s), instead of up to 15 minutes.
- `RoundService.enterActive` (line 357): don't add to RoundsPlayed in practice, so new-player help keeps counting real rounds. Practice already gives no Wins (line 342).
- `LobbyController.updateStatus` (line 206): while alone, one countdown to the practice round that covers both the 30 s wait and the Intermission, for example "PRACTICE ROUND IN 0:55 · OR WAIT FOR CONTENDERS" (on phones, "PRACTICE IN 0:55"). `RoundService` publishes when it will start (for example `GameState.SoloStartAt`) so the pill can count down.

**Why.** P1. A newcomer who meets "WAITING FOR PLAYERS 1 / 2" leaves within the first minute that Roblox counts against us ([Discovery](https://create.roblox.com/docs/discovery)). Roblox developers advise solo play for when few players are online ([DevForum: not enough players at launch](https://devforum.roblox.com/t/worried-my-multiplayer-game-wont-have-enough-players-at-launch/4807146)). In a Roblox battle-royale playtest, the tester's first complaint was a 15-second solo wait ([DevForum playtest](https://devforum.roblox.com/t/playtest-where-am-i-losing-players%E2%80%94before-during-or-after-their-first-match/4780000)).

**Verify.** Alone on a published server: from joining to the horn takes 70 s or less, and the 3 dummies are there, 3 times out of 3. A second player who joins during the practice hears the horn of a full round within 2:00 of joining.

### QW2 · Say what the held item does (1 day) — fixes F11

**What changes, where**
- A new `ReplicatedStorage.Shared.ActionHints` builds one line per item kind from the numbers in `ItemDefs`, so the line stays true when you retune. Keyboard examples (gamepad shows its own buttons, touch names its button):

  | Held (or in reach) | Hint under the crosshair |
  |---|---|
  | Food | HOLD [LMB] EAT · +12 HUNGER |
  | Water Bottle | HOLD [LMB] DRINK · +45 THIRST |
  | Bandage | HOLD [LMB] BANDAGE · +20 HEALTH |
  | Leather Vest | HOLD [LMB] PUT ON · −15% DAMAGE |
  | Recurve Bow | HOLD [LMB] DRAW · RELEASE TO SHOOT · 6 ARROWS |
  | Spear | [LMB] STAB · HOLD [RMB] + [LMB] THROW |
  | Throwing Knife | [LMB] THROW · PICK IT UP AFTER |
  | Empty Bottle | LOOK AT WATER · [E] FILL |
  | Arrows | AMMO · EQUIP THE BOW TO SHOOT |
  | A climbable tree within reach | PUSH FORWARD TO CLIMB · [C] LET GO |

- Show it in the slot the HUD already draws under the crosshair: `HUDController.updateInteract` (1037–1062) draws it with its key cap, fed by a new `ClientState.actionHint`. Don't route it through `InventoryController.setHint` (lines 579–598): that function also binds Drink to E whenever any hint shows (`bindDrink`, line 597), so an item hint would capture E and keep it from reaching crate prompts (the script's header, lines 17–19, keeps Drink off while a prompt shows for exactly this reason). Looking at water still takes priority. Both hints stay up for 0.25 s after the look ray leaves their target, so they don't flicker as you look around (P8; the water check runs every 0.15 s, `HINT_INTERVAL`, line 46). The climb line shows when a `Climbable` trunk is within `Config.Movement.Climb.Reach` (2.5 studs); climbing starts by pushing into it or jumping at it (`MovementController` line 2177).
- Fade it by use: the full line for the first 3 successful uses of each action, then only the key cap for the next 3, then nothing. If a player stalls (holds food for 10 s with Hunger under 40), the hint comes back once. Store the counts as one number, `hintsSeen`, with 3 bits per action (10 actions fit in 30 bits), added to `DataService.SETTING_LIMITS` (lines 34–42) with the range 0 to 2^30; today it accepts only 7 keys.
- The item toast (`HUDController.flashItemName`, 481–509) gets the item's `desc` from `ItemDefs` as a third line, for the first 3 pickups of each item.
- Touch (`CombatController.refreshTouchButtons`, 677–694): the big button reads EAT, DRINK, HEAL or WEAR instead of USE, and THROW while a spear is aimed. The DRINK button reads FILL while you hold an empty bottle; today its label is fixed (`InventoryController` line 567) while the hint already says "Fill bottle".

**Why.** P2 and P3. Roblox recommends short tutorials triggered by normal play, such as picking up a new item, and timed hints only for players who stall ([onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques); [Roblox staff on first-time experiences](https://devforum.roblox.com/t/learn-more-about-first-time-user-experience-onboarding/2621940)).

**Verify.** With 5 newcomers and no coaching, at least 4 eat or drink within 20 s of first holding food or water, and at least 3 throw a spear the first time they hold one. After their third successful use of an action, no tester sees its full line again, and E still opens a crate while an item hint is showing.

### QW3 · Small rounds start small (½ day) — fixes F19

**What changes, where**
- At the Countdown, set the border's starting radius from the number of contenders picked, N: r0 = clamp(640 × √(N/24), 320, 640). That is 320 studs for up to 6 contenders, 370 at 8, 453 at 12 and 640 at 24. From 6 contenders up, the arena is as crowded as a full round.
- `RoundService.enterCountdown` (lines 397–443) publishes r0 (for example as `GameState.BorderStartRadius`) before `LootService.populate` runs (line 441). `ArenaService.resetBorder` and `radiusAt` (200–224) start from it instead of `Config.Border.StartRadius`. To put the wall in view from the plates, `ArenaController.wallShouldShow` (line 170) must show it during the Countdown too; today it shows the wall only in Active. Its fallback to `Config.Border.StartRadius` (lines 55 and 249) should read the published radius as well.
- `LootService.populate` skips markers more than 30 studs outside r0, so the loot is where the people are.
- The lake's near shore, a beach facing the meadow at about r 192 to the south-south-east (`ArenaLayout` lines 534–560), stays inside the 320 floor, so water stays reachable.

**Why.** P10. The closing zone exists to bring players together, and big battle royales tune it to how many players there are and announce it up front ([PUBG Update 42.1](https://pubg.com/news/10179); [PC Gamer on the Savage zone](https://www.pcgamer.com/pubgs-savage-map-has-a-blue-zone-that-adjusts-its-timing-based-on-the-number-of-players-left)). With 4 contenders spread over r 640, the nearest rival is about 284 studs away on average; over r 320, about 142.

**Verify.** In a 4-player test, the median time from the horn to first seeing a rival is 3:00 or less.

### QW4 · Deaths that teach, and a wait with an end (1 day) — fixes F16 and F3

**What changes, where**
- A tip goes under the cause line (`NotificationController.causeLine`, lines 461–486), chosen by cause and weapon class. If the same cause kills a player twice, the second tip is more specific.

  | Cause | Tip |
  |---|---|
  | Thirst | Look at any stream or the lake and press [E]. Fill empty bottles too. |
  | Hunger | Hold [LMB] with food in hand. Berries and apples are common in crates and on the ground. |
  | Border | From the second morning the border closes on the Spire. Head in when the timer shows. |
  | Fall | Drops of more than about 4 m hurt. Climb down, or drop into water. |
  | Bow | An archer needs about a second to draw. Keep moving, zig-zag, and break their line of sight behind trees. |
  | Melee | Fists barely scratch. Arm yourself before you fight, and back off to bandage when a fight turns against you. |
  | Thrown spear | A thrown spear hits for 60, more than half your health. Keep moving, and keep cover between you and anyone carrying one. |

  Every tip must be something the player can see or do today. Rivals show no wind-up yet (F7), so "step back when their weapon goes up" waits for B1; switch the melee tip to it then. Arrows land where the crosshair points (`Config.Combat.BowAimOnTarget`, lines 282–287), so the bow tip is about the draw, not about arrow drop.

- One line of progress: "OUTLASTED 15 OF 24 · 6:12", from the placement, the total and `RoundStartedAt` (`showDeath`, 511–553).
- Watch your killer. Add `killerUserId` to the YouDied payload (`PlayerService`, 492–499) and set a `KilledBy` attribute on the victim. SPECTATE (`NotificationController`, 1111–1118) then calls `SpectateController.start(killer)`. `start` already accepts a target (lines 355–367), and gamepad selection lands on SPECTATE. When the contender you are watching falls, `onTargetLost` (255–269) follows their killer instead of the next name in the alphabet.
- The lobby pill (`LobbyController`, line 215) reads "ROUND IN PROGRESS · 9 REMAIN · NEXT ROUND IN 6:57 AT MOST": the time left from `PhaseEndsAt`, plus the 45 s of Ending, Intermission and Countdown. A countdown reads better than a clock time here, because the HUD clock counts down too.

**Why.** P6, and P1 for the end time. A death screen that shows who, how and what to change reads as fair ([Making death fun](https://www.gamedeveloper.com/design/making-death-fun-something-medal-of-honor-needs-to-fix-for-launch-)). DOORS gives a tip about what killed you and gets more precise on repeats ([DOORS](https://rblxguide.com/games/doors/entities/guiding-light)). Fortnite solos show you the player who eliminated you ([ONE Esports](https://www.oneesports.gg/fortnite/how-to-spectate-in-fortnite-2-easy/)).

**Verify.** Every tester who dies of thirst or hunger can say how to drink or eat before the next round (5 of 5). In a 3-client test, SPECTATE opens on the killer 10 times in 10. Every tester waiting in the lobby can say when the next round starts.

### QW5 · Show thirst and healing (1 day) — fixes F13 and part of F15

**What changes, where**
- `PlayerService.contenderTick` (lines 774–778) already works out whether you are healing. Publish it as a player attribute, `Regen`: true or false, and empty at full health.
- `HUDController` vitals (`setStat`, about 233–273):
  - a faint tick at 55 on the Hunger and Thirst bars (the healing line);
  - a slow shimmer on the health bar while `Regen` is true;
  - when it is false, health is under 90 and a meter is at 55 or below, a dim reason under the bar: "NOT HEALING · THIRSTY" (or HUNGRY). In the 8 s after a hit (`Config` line 79), when the meters aren't the reason, it shows nothing;
  - when a meter is empty, the line turns red: "DEHYDRATED · LOSING HEALTH" (or STARVING). At 0 you lose 1.5 health a second (`Config` line 76), and today nothing on screen says why.
- One-time cards for new players, as `NotificationController` toasts. Cards never show during a Roll Call; they wait until it ends.
  - Thirst below 60 (about 3:36 at a jog, in daylight): "THIRSTY · Streams and the lake are drinkable. Look at the water and press [E]."
  - Hunger below 60 (about 5:36): "HUNGRY · Berries and apples are common in crates and on the ground. Hold [LMB] to eat."
- One low-health line for every signal. A new `Config.Feedback.LowHealth = 0.35` drives the LOW tag (`HUDController` line 53, now 0.3), the red vignette (line 1068, now 0.4) and the heartbeat (`AudioController` around line 1266, now 0.45).

**Why.** P4. Keep players informed of the system's state ([NN/g heuristic 1](https://www.nngroup.com/articles/ten-usability-heuristics/)); The Long Dark makes its needs contextual and keeps red for real danger ([Game Developer](https://www.gamedeveloper.com/design/long-dark-survival-game-hud-ui)). Today healing stops at about 4:03 and LOW comes at about 6:45, in the dark (`Config.Survival`, lines 70–85).

**Verify.** At least 4 of 5 testers drink before thirst turns LOW. No deaths by thirst or hunger in rounds 2 and 3. Asked "why did your health stop coming back?", at least 4 of 5 answer that they needed to drink or eat.

### QW6 · The goal and the choice, where players look (½ day) — fixes F1, F4 and F5

**What changes, where**
- The countdown caption (`RoundService`, line 388; the big number stays): for the first 4 seconds, while the plate rises, "Last one standing wins"; once the plate locks, "Rush the Spire for weapons · or run for the trees" (on phones, "Rush the Spire · or run").
- Remove the "SURVIVE" banner after the horn (line 369), so nothing covers the first sprint. Keep the PRACTICE ROUND banner (line 367), which tells a lone player what kind of round this is. For new players, show a 3-second key hint instead: "[SHIFT] SPRINT" (gamepad: L3; touch, with QW13's Auto sprint: "PUSH THE STICK ALL THE WAY TO SPRINT").
- The lobby (`LobbyController`, line 365): open HOW TO PLAY by default only until the first round has been played, and put a three-step line at its top: "RISE ON YOUR PLATE → TAKE GEAR AT THE SPIRE, OR RUN → OUTLAST THE BORDER". The control rows stay below it.
- Correct the control rows (`SettingsController` CONTROLS, 68–113), which the lobby panel shows too. "Aim · throw the spear: Right click" (line 76) becomes "Aim · with a spear, Aim + Attack throws". Add "Let go of a climb: C" (gamepad B, touch CROUCH). The crouch row becomes "Crouch · quieter footsteps · slide while sprinting" (line 73): crouching cuts your footsteps to 35% volume and about half the range for other players (`AudioController` TUNE, lines 55–56), a real stealth tool that nothing mentions today.
- Fix the notice board (`ServerStorage.WorldGen.AssetBuilder.Props`, 438–444): "On the second morning the border closes in." The Knell line is already a Phase 1 task.

**Why.** P3. Players read little and judge a game within minutes, so teach what to do and why ([Roblox onboarding](https://create.roblox.com/docs/production/game-design/onboarding); [NN/g](https://www.nngroup.com/articles/how-little-do-users-read/)). In a Roblox battle-royale playtest, the tester never understood the win condition ([DevForum playtest](https://devforum.roblox.com/t/playtest-where-am-i-losing-players%E2%80%94before-during-or-after-their-first-match/4780000)).

**Verify.** After round 1, 5 of 5 testers can answer "How do you win?" and "What could you do when the horn went?". No tester mentions a banner in the way. At the end, at least 3 of 5 can say that crouching makes their footsteps quieter.

### QW7 · Make running away pay (1 day) — fixes F9

**What changes, where**
- Add 8 runner's caches, one in each 45° sector at r 150–200, each by a landmark. Each is a tier-2 crate with a guaranteed basic weapon (a Hunting Knife, or 2 Throwing Knives) and a Water Bottle, plus one normal tier-1 roll. A new `ItemDefs.LootTables.Runner` holds the table, and `LootService.populate` uses it when a marker has `Runner = true`.
- Place the markers in `ServerStorage.ArenaData.LootSpawns` now, and add them to the meadow-edge entries of ArenaLayout v2's `LootZones`, so the set-dressing pass keeps them.
- Mark each cache with a pale canvas cloth tied to a pole, visible from the plates (built from Parts, no upload).
- The Spire keeps the power: the tier-3 crates and the Offering stay as they are.

**Why.** P9. In PUBG, remote ground pays less but is safer, and choosing where to go is what gives players a sense of control ([PUBG's maps](https://www.gamedeveloper.com/design/designing-the-giant-battle-royale-maps-of-i-playerunknown-s-battlegrounds-i-); [why PUBG hooks players](https://www.gamedeveloper.com/business/how-can-pubg-be-addictive-to-billions-of-people-)). Today a runner finds a weapon at about 9% of ground markers, and the tier-2 crates sit mostly at r 250–640.

**Verify.** Over 5 rounds, testers who run hold a weapon within 25 s of the horn in at least 80% of runs. At least 3 of 5 call running "a good choice".

### QW8 · Loot a crate in one press (1 day) — fixes F6

**What changes, where**
- `LootService.openCrate`: after the 0.6 s open, the opener gets "Take all [E]" on the crate for 3 s. It puts every spilled item that fits into the bag through `InventoryService.give`. For those 3 s it takes priority over the single-item prompts. Whatever doesn't fit stays on the ground for anyone.
- Arrows and throwing knives you already carry are picked up when you walk over them (checked on the server against `Config.Loot.PickupRange`, line 305).
- `HUDController.setSlot` (458–479): a short "+4 ARROWS" line in the item's rarity colour whenever a stack grows, and the item toast for every new item (today it shows only when what you hold changes, 1352–1363).
- "Inventory full" says how to fix it: "INVENTORY FULL · [G] DROP THE HELD ITEM" (the two calls at `LootService` lines 385 and 398, through its `toast` helper, 172–180).

**Why.** P7. Xbox's accessibility guidelines recommend simpler schemes such as automatic pick-up ([XAG 107](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107)). The scrum at the Spire is where newcomers die without knowing why.

**Verify.** At the Spire, a crate's contents reach the hotbar within 1.5 s of the open finishing (today it takes 3–5 presses and 2–4 s). In the test recordings, the median number of presses per crate is 2 or fewer.

### QW9 · Threats you can see coming (1 day) — fixes F8 and F14, and part of F7

**What changes, where**
- **Always show what's next.** The event line (`HUDController.updateInfo`, lines 818–835) always shows the next beat, dimmed while it is more than a minute away: "ROLL CALL AT DUSK · 4:12" → "THE OFFERING · 2:05" → "THE BORDER MOVES · 0:30". Times count down, like the HUD clock.
- **One threat format.** Build the line on one shared formatter, `Shared.ThreatLine`: NAME · WHAT TO DO · WHERE · WHEN, for example "THE BORDER · HEAD FOR THE SPIRE · 1:30". `ArenaService`'s Offering and border warnings use it too (lines 230–247 and 289–306). This is the first slice of Phase 2a's "HUD event line" ([Roadmap](../Roadmap.md) §5), and WardenService will reuse it. The copy says THE OFFERING. Read the names from `Shared.Lore`, which Phase 2a creates. That retires today's player-facing "THE FEAST" strings (`HUDController` 827–833, `ArenaService` 294 and 306) ahead of the Phase 7 lore pass that [Roadmap](../Roadmap.md) §7 scheduled for them.
- **Hear the bow.** `AudioController` listens to the `CombatAction` remote, which no client listens to today. On "Draw" it plays the bow's creak (`Sounds.BowDraw`, `Shared.Sounds` line 112) at the archer, for anyone within about 45 studs, and stops it on release or cancel. The server already sends "Draw" when a draw starts (`CombatService` header, line 9).
- **Survive one arrow.** `ItemDefs.bow.headshotMultiplier` goes from 2 to 1.8 (line 46), so a full-draw headshot does 90 instead of 100 (see Q2).

**Why.** P5. A clear warning before damage makes the damage feel fair ([Enemy attacks and telegraphing](https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing)). Battle-royale zone guides put the audio about 30 s and the visuals about 15 s ahead ([UEFN Central](https://uefncentral.com/id/blog/advanced-battle-royale-zone-mechanics-uefn)), and Natural Disaster Survival names each disaster up front ([Screenwise](https://screenwiseapp.com/guides/natural-disaster-survival)). Raising the time to kill gives the victim a moment to react ([Realm Royale on time to kill](https://pcgamesn.com/realm-royale/realm-royale-ttk)). Today the HUD says nothing about what comes next until 8:50.

**Verify.** At 7:00, at least 4 of 5 testers can say what comes next and roughly when. In a 2-client test, a listener names "a bow" within 1 s of an unseen draw at 30 studs, 9 times in 10. No tester dies to a single arrow from full health.

### QW10 · Point to water when thirsty (1 day) — fixes F15

**What changes, where**
- Precompute about 40 drinkable water points once, in Edit mode (the lake shore, the fords, the streams), into a small `Shared.WaterPoints` module. A small `ServerStorage.WorldGen` builder writes it from ArenaLayout's lake and river data, or from `WorldGen.TerrainData` where present, following the repo's rule that generated content comes from a builder ([GameDesign](../GameDesign.md) §8).
- `HUDController.updateCompass` (739–771): with Guidance on, when Thirst is below 50 (about 4:30 at a jog) and you carry nothing to drink, show a water-drop marker with the distance in metres to the nearest point. It pulses with QW5's thirsty card and fades after your first drink of the round. Guidance Auto shows it to new players, like the rest of the help (Q1).
- The same ribbon points to safety while the border moves: within about 80 m of its edge, "BORDER 42 m" sits next to the Spire distance, with a tick toward the nearest edge. Today the border appears on the compass only once you are outside it (763–771).

**Why.** P4. A thirsty newcomer has no way to find water today. Roblox's onboarding techniques use markers and trails that suggest a direction without forcing it, such as Jailbreak's footprints ([onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques)). In a controlled first-person study, a compass was the weakest way to navigate and a path drawn in the world the best, so B7 adds game trails later ([Peacocke et al. 2018](https://www.yorku.ca/mack/ec2018.html)).

**Verify.** The median time from the marker appearing to the first sip is 40 s or less. No new player dies of thirst in rounds 1–3.

### QW11 · Crates you can spot (1 day) — fixes F10

**What changes, where**
- `ItemModels.buildCrate`: add a pale canvas strap and a brass clasp with a faint glint that reads at 40–60 studs in the forest. It is built from Parts, so it needs no upload, and it must survive the swap to the ItemsReal crates (integrate:items-realistic). The strap is pale rather than ember because ember orange stays the colour of Warden hazards (B10).
- When a crate is opened (`LootService.openCrate` sets its `Opened` attribute, around lines 725–737), the strap hangs loose and the glint stops, so looted crates read as spent.
- For new players, during the first 90 s of a round: an outline-only `Highlight` on the nearest 8 unopened crates within 25 studs, drawn on the client. Roblox draws at most 31 Highlights at once.
- Common ground items glint too, more faintly. Today only Rare and better glint (`LootService` line 424).

**Why.** P3 and P11. Highlight what players should notice, in their line of sight ([onboarding techniques](https://create.roblox.com/docs/production/game-design/onboarding-techniques)). One game fixed its biggest onboarding drop with a single icon ([DevForum funnel case](https://devforum.roblox.com/t/3064458)). Key items must stand out from a desaturated world ([Valve](https://www.gamedeveloper.com/art/in-depth-how-valve-makes-art-to-enhance-gameplay)).

**Verify.** Shown 10 forest screenshots with a crate at 40 studs, testers point to the crate within 3 s in 9 of 10. Runners open their first crate within 40 s of the horn (median).

### QW12 · Never swallow a press or an item (1 day) — fixes F12

**What changes, where**
- A small client helper, `Feedback.deny(reason)`, plays one short deny sound and shows a toast at most once every 1.5 s per reason. Use it when:
  - you attack or use an item while climbing, mantling or swimming: "LET GO TO FIGHT · [C]" (`CombatController` 143–145);
  - you release the bow under 20% draw: "DRAW LONGER TO SHOOT", the first 3 times (569–573);
  - you try to sprint with no stamina: "OUT OF BREATH".
- A click during the switch time (0.32 s, or 0.44 s for the bow) is kept and fires when the item is ready: `BUFFER_WINDOW` (`CombatController` line 90) covers the whole switch.
- Pressing an empty slot no longer puts your weapon away (`InventoryController.select`, 407–409); the slot shakes and the deny sound plays. Pressing the slot you hold still puts it away, and the item toast then says "FISTS".
- Food and drink: refuse food at Hunger 95 or more ("YOU'RE FULL") and drinks at Thirst 95 or more ("YOU'RE NOT THIRSTY"), on the client (`InventoryController.startUse`, 252–265) and on the server (`InventoryService.onUseStart`). Holding Attack stops before an item would waste more than half its value.
- Drop: tapping G (gamepad: D-pad down) drops one; holding it for 0.4 s drops the stack. A toast says what fell: "DROPPED ARROWS ×24".

**Why.** P7. Players feel a game as slow or broken when a press gets no answer ([Mick West](https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games)), and preventing errors beats explaining them ([NN/g heuristics 1 and 9](https://www.nngroup.com/articles/ten-usability-heuristics/)).

**Verify.** In the recordings, presses with no visible or audible answer: 1 or fewer per player per round. No tester loses a stack by accident.

### QW13 · Controls that fit every device (1 day) — fixes F20

**What changes, where**
- A CONTROLS section in `SettingsController.DEFS` (lines 51–65), saved through SaveSettings (with new keys in `DataService.SETTING_LIMITS`). Every row there is a slider today, so a choice such as Hold / Toggle / Auto can be a 3-step slider (0–2, with a `format` that prints the word) and needs no new row type:
  - **Sprint:** Hold, Toggle or Auto. Auto sprints whenever you push fully forward, while you have stamina. The defaults are Hold on keyboard, Toggle on gamepad (today's L3) and Auto on touch. It reuses `MovementController.setSprintToggle` (line 616).
  - **Crouch:** Hold or Toggle.
  - **Controller look speed** and **touch look speed** (0.5–2×). Today "Look sensitivity" changes only the mouse (`CameraController` 280–292). Apply them by scaling the stock camera's gamepad and touch bindings, and apply them again whenever Roblox's own settings change. First check in Studio that today's slider still changes mouse speed at all: it sets `UserInputService.MouseDeltaSensitivity` (`CameraController` line 290), but the controls audit found Roblox's camera now reads the mouse through its own input binding.
  - **Field of view** in horizontal degrees for the player's own screen. Today the slider shows vertical degrees (`SettingsController` 53–55), and the default of 72 is about 104° across on a 16:9 screen (`Config` line 235). Lower the slider's floor from 70 to 55 (about 86° across), for players who feel sick or want bigger targets; the server already accepts 50–120 (`DataService` line 35).
- One helper, `Shared.Glyphs.forKey(keyCode)`, for every button name. It uses `UserInputService:GetStringForKeyCode` and `GetImageForKeyCode`, and replaces the hard-coded names in the action hint (`HUDController` 1024–1035, which prints "X" for any controller), in `InventoryController` line 589 and in the gamepad control rows (`SettingsController` 84–97).

**Why.** P12. Every action must work on every input, and each input mode must be tested ([adaptive design](https://create.roblox.com/docs/production/publishing/adaptive-design)). Offer toggles for long holds and a sensitivity per input ([XAG 107](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107)). Roblox gives each platform its own button glyphs ([cross-platform guide](https://create.roblox.com/docs/projects/cross-platform)).

**Verify.** The 60-second device checklist (QW15) passes on PC, phone and gamepad. A PlayStation tester sees Square on the drink hint. A phone tester crosses the meadow without touching RUN.

### QW14 · Every round ends with one winner (1 day) — fixes F17

**What changes, where**
- **The Last Stand** (`ArenaService.radiusAt`, 200–207, and `borderDamage`, 258–283): after 830 s the ring keeps closing, from 35 studs to nothing by about 885 s. Outside it, damage rises the longer you stay out: 10 per second, plus 2 more for every second outside. Its card: "THE LAST STAND · THE RING CLOSES TO NOTHING". ("Last light" is already Warden slot 6 in [arena-events.md](arena-events.md) §3 and an Achievement in [modes-progression.md](modes-progression.md), so the finale needs another name.)
- **Close it beside the Spire, not on it.** As the ring closes, its centre slides to a point 15–25 studs from the Spire on open plaza ground, picked per round (`ArenaService.computeCenter`, 193–198, always uses the Spire today). Nobody can circle the monolith to break line of sight, and the last fight stays off the central structure, clear of the source's finale beats that [Roadmap](../Roadmap.md) §7 lists.
- **The timeout becomes a safety net** (`RoundService.endRound`, 328–330): if two still stand at 900 s, the healthier one wins, then the one with more kills. "Nobody claims the win" never appears outside practice. This also keeps us clear of a final pair who refuse to fight, a source beat that [Roadmap](../Roadmap.md) §7 rules out.
- **Roll Call 2 doesn't silence the finale.** It falls at 14:05 (845 s), always after the border has closed at 13:50, in the middle of the final fight. Post its names in the small 2D list only (`NotificationController.showRollCall`, line 753) and skip the sky show, so the final-stand music keeps playing (`FallenRecapController` 582–583 switches it off today). The sky show itself keeps its no-music rule, which also keeps it clear of the source's anthem beat.
- **Keep the day's signature moment** (+½ day; Q3). After the step above, Day 2's sky show never plays during a round. So play a short version of it, the day caption and that day's fallen together (about 20 s), behind the winner card for everyone, the dead and spectators included. Ending grows from 10 s to about 25 s for it.

**Why.** P10. PUBG's late zones close nearer the centre and hurt more the longer you stay out ([PUBG Update 42.1](https://pubg.com/news/10179)). The peak belongs at the end of the round, not a rest ([Booth, 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)).

**Verify.** A Studio test with 4 clients at `StudioTimeScale` 6 ends with a named winner 10 times in 10, the last fight happens on open ground beside the Spire, and the final-stand music is heard in every final minute.

### QW15 · Measure the first session and guard the controls (1 day) — all frictions

**What changes, where**
- A new `ServerScriptService.Server.Services.OnboardingService` logs Roblox's onboarding funnel with `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)`. It runs on the server only, works only in published games, and counts the first time each step happens. The steps:
  1. joined;
  2. moved within 10 s;
  3. on a launch plate;
  4. left the plate (more than 10 studs after the horn);
  5. opened a crate;
  6. equipped an item;
  7. ate or drank;
  8. survived to Roll Call 1;
  9. finished a round;
  10. on a plate for round 2.

  Most come from signals that already exist (`RoundService.roundStarting`, `roundStarted` and `roundEnded`, `PlayerService.died`, `InventoryService.equippedChanged`) and from `GameState.RollCall`, which `ArenaService` sets at each dusk. Add two small signals: a crate opened (`LootService.openCrate`, 713–738) and an item used (in `InventoryService`, where a use finishes). No script uses AnalyticsService today.
- A Studio-only input check, kept with the Dev tools. It runs on the client during a playtest and lists every `Shared.Input` action expected in each state (lobby, plate, arena, spectating). `Input.isBound` (line 246) only says that a name is bound, so add a small `Input.describe(name)` that returns the action's keys and touch button. The check fails if an action has no keyboard, gamepad or touch binding.
- A 60-second checklist on each device before every publish and after every Roblox client update: move, look, sprint, jump, attack, open a crate, drink, eat, spectate.

**Why.** P1 and P12. Find and fix the largest early drop first ([funnel events](https://create.roblox.com/docs/production/analytics/funnel-events); [DevForum funnel case](https://devforum.roblox.com/t/3064458)). Watch errors and every input mode after each update ([Retention](https://create.roblox.com/docs/production/analytics/retention); [adaptive design](https://create.roblox.com/docs/production/publishing/adaptive-design)). "I can't even move" after a Roblox controls change is exactly the regression this catches, and funnel step 2 would show it live within a day.

**Verify.** In a published test, all 10 steps appear for every tester in the Creator Dashboard funnel. The input check fails when Attack is deliberately unbound, and passes otherwise.

### Working alongside the agents already building

- QW11 changes `ItemModels.buildCrate` while integrate:items-realistic swaps the crates. Agree the strap with that work.
- QW9 and QW12 touch `CombatController` and `AudioController`, which the combat-physics work will rewrite. Keep these changes small and note them for that team.
- QW3 changes the starting radius. Phase 2a's zone scoring must read the published radius, not `Config.Border.StartRadius`.
- QW9's formatter is the seed of Phase 2a's event line. Build it once.
- QW2 and QW13 both change the hint under the crosshair (`ClientState.interactHint`, `HUDController.hintKeyFor`). Build `Shared.Glyphs` first, then the action hints on top of it.

---

## 4. Bigger changes

Each takes 2–10 days. The last column says where it fits in the [Roadmap](../Roadmap.md).

| # | Change | Size | Fixes | Where it fits |
|---|---|---|---|---|
| B1 | **Rival attacks you can read.** Third-person wind-up, swing, draw and throw poses, driven by `CombatAction` through `CharacterVisuals`, with one tell per weapon class, and the whoosh starts with the wind-up. Wind-ups must outlast ping, interpolation and reaction time ([CombatPhysicsPlan](../research/CombatPhysicsPlan.md) §2.4). Another player sees a swing start about 150 ms late at 100 ms ping, so today's 0.14–0.25 s wind-ups for medium and heavy weapons (`ItemDefs` 27–42) would show at or after the hit. Use that plan's longer timings (its decision 9 proposes a 450 ms light swing for the mace). With it: a short flinch (a melee hit stops the victim's sprint and slows them to ×0.75 for 0.5 s), and melee times-to-kill that follow rarity. Today a Rare mace (2.2 s) kills slower than a Common knife (1.8 s) ([CombatPhysicsPlan](../research/CombatPhysicsPlan.md) §1.3). | 4–6 days | F7 | Phase 1, "Combat physics": build CombatPhysicsPlan phase 1's poses first, ahead of hit zones and ragdolls. The plan's own exit test applies: observers see a wind-up at least 150 ms before contact at 100 ms ping. |
| B2 | **Aim with the thumb that attacks, on a phone layout that fits.** Dragging on ATTACK, DRAW or THROW turns the camera: `Shared.Input` publishes the touch movement and `CameraController` applies it first each frame. ATTACK gets a hit area of about 110 px. Buttons are laid out from Roblox's live jump button (Roblox moved it on 30 April 2026), at least 60 px from the screen sides, with at most 7 buttons including jump. DROP becomes a long-press on a hotbar slot. A HEAL button (also H, or D-pad left) appears at health 70 or less when you carry healing, and uses it without changing what you hold. Light aim assist on touch and gamepad only (turning slows to about 0.6× within about 1.5° of a visible contender in range; never through cover; Off, Low or Standard). A Vibration slider and a few rumble cues (hit, hurt, full draw). | 4–6 days | F20 | Phase 1 UI, before any playtest with phones. First check on a real phone whether holding DRAW freezes the view today. |
| B3 | **Scale the round's clock to the head-count.** `GameState.TimeScale = clamp(24 / (N + 8), 1, 2.2)`, read by the three timeScale helpers (`RoundService` 88–96, `ArenaService` 118–127, `HUDController` 111–119), with `StudioTimeScale` on top. Hunger and thirst drain at the same scale, and the Roll Call must still fit its vigil. A round of 2 runs about 6:50, 4 about 7:30, 8 about 10:00, and 16 or more the full 15:00. The countdown names it: "6 CONTENDERS · THE BORDER MOVES IN 5:50" (a countdown, like the HUD clock). | 3–4 days | F19 | Phase 1, before qa:integration, so your multi-client test isn't judged on a 24-player schedule. Phase 2a's Director slots inherit it, because they run on `RoundService.getElapsed()`. Phase 5's done-when says "the Standard timeline is unchanged (the Offering at 590 s, the border from 600 to 830 s)"; with B3 that holds at 16 or more contenders, so put the scaling rule in `Shared.Rules`' Standard preset when Phase 5 creates it. |
| B4 | **The Practice Yard on the Tor.** A free, ungraded early slice of Phase 7's Assessment Hall, off the north walkway: a trough to drink from and fill bottles at, food to eat, a crate to open, a bow lane with dummies at 15, 30 and 50 studs, a spear rack, and a wall to mantle and climb. Attacks work only inside it and never on players. The kit is cleared at the Countdown (`RoundService` line 415 already does this). A TRAIN button on the death card; new players spawn by its gate. | 5–8 days | F3 | Pull it forward from Phase 7 into Phases 1–2. Phase 7 then adds the Mark and the timed run. |
| B5 | **"How you fell", and personal bests.** A 20-second damage log for each contender in `PlayerService.damage`. YouDied carries the rows (who, weapon, damage, hits, headshots) and the killer's remaining health, and the death card shows 2–3 lines, for example "Mira · Hatchet ×3 · 86 (1 to the head) · Fall 14 · Mira was left on 37". Bests (`BestPlacement`, `LongestSurvival`) are saved with a best-of merge inside DataService's UpdateAsync, shown as "NEW BEST" and on the lobby card. | 2–3 days | F16, F18 | The recap in Phase 1 UI. The bests are the first lines of Phase 5's Round Report. |
| B6 | **First Steps.** For new players, three lines at the top left that tick off: open a supply crate · eat or drink · survive to the first Roll Call. Finishing all three earns a Roblox badge, "First Dusk", and a banner in the lobby. No streaks and no timers. | 2 days | F18 | The first slice of Phase 5's Achievements (20 at launch, 6 of them badges). |
| B7 | **Readable realism.** A greyscale check in the look-dev scenes: a default avatar standing, crouched and at a tree line, at 25, 60 and 120 studs, in day, golden hour, moonlit night and dawn mist. A standing contender must read by value alone at 60 studs, and contenders, crates and the border must read with shadows off (quality levels below 4). One look for each thing you can use: climbable trees have low branch stubs at 3–5 studs and a worn band of bark at hand height; fences low enough to get over (up to 6.5 studs, `Config.Movement.Mantle`) share one top rail; surfaces you can't mantle look sheer or wet; brackish water has scum on it. The Spire's Beacon rises as a soft column of light from dusk, and game trails lead down to water and the fords. Make Phase 1's bow screen-coverage check permanent for every first-person pose: nothing covers the centre of the screen. | 3–5 days | F10, F15 | Phase 1 look-dev shading and set dressing ([LookDevPlaybook](../research/LookDevPlaybook.md) §7.2, §9, §13). |
| B8 | **A sound language.** One sound per meaning. Today the kill confirm, the Offering bell and the UI notify are one sample at three pitches, and "I got hit" reuses "I hit someone" (`Shared.Sounds` 104–105, 121–123, 143, 160). Your own hurt becomes a grunt and a muffled thud; a kill gets its own low thunk; refusals get a dry deny. Every action also gets a finishing beat: a swallow when a drink lands, a crunch when food is eaten, and a lid creak as someone starts to open a crate, which rivals nearby can hear (today they hear only the open itself, `LootService` line 734). Body cues for hunger (a stomach growl) and thirst (a dry swallow), beside the existing breathing and heartbeat. A mix that favours the biggest threat among the 16 world voices (close, facing you, weapon raised). Forest tells: sprinters flush birds, and the frogs fall silent around anyone moving through the marsh. | 3–5 days | F7, F13 | Phase 1 "UI and sound", together with the swap of Creator Store sounds of unconfirmed source before publishing ([Roadmap](../Roadmap.md) §7, Audio). |
| B9 | **Back into play fast.** Publish `SecondsToRound` with `MatchmakingService:SetServerAttribute`, so joiners land in servers about to start a round. A PLAY NOW button on the death card and in the lobby teleports the player (and their party) to another public server, and the signal steers them to one whose round starts within about 60 s. Roblox's matchmaking pages don't say whether teleports use custom signals, so confirm it in a published test before relying on it. | 3–5 days | F3 | Move Phase 8's SecondsToRound item to before the first public release. PLAY NOW needs the game's first teleport code, which Phase 7's StoryService would otherwise write; build that piece here or earlier. |
| B10 | **Comfort and accessibility.** A HUD scale (80–150%), and text that follows Roblox's `PreferredTextSize`. When `ReducedMotionEnabled` is on, head bob and shake start at 25%, and panels respect `PreferredTransparency`. One meaning per colour: red is harm to you, ember is Warden hazards only, off-white is you and neutral messages, and rarity colours appear only on loot. Rarity pips 1–5 on the hotbar slots, because Rare and Epic look alike to players with deuteranopia. A Contextual HUD mode, in which the meters fade while steady above 55 (Full stays the default for new players). An optional "Show sound cues" ring for footsteps within about 35 studs (never crouched ones), bow draws and nearby fights. A "Screen pulses" slider for the pulsing vignettes. Keep the low-health vignette in the top and outer corners so it never hides a flanker; today's vignettes darken all four edges (`HUDController` 1064–1080). Draw the loot prompts in the game's own style (`ProximityPromptStyle.Custom`: Theme fonts, this device's button, a hold ring like the use ring) instead of Roblox's default (`LootService` lines 453 and 817). | 4–6 days | F20 | Phase 1 UI, finished before the Phase 6a public release. |
| B11 | **Input on Roblox's Input Action System.** Rebuild `Shared.Input` on input contexts (Arena, Lobby, Spectate, Menu), each action with keyboard, gamepad and touch bindings. Use `PreferredInput` instead of the last-input guess (`Shared.Input` 35–46) and `TouchEnabled`, which touch laptops now report. One bindings table (`Shared.Bindings`) generates the controls page, the hints and the lobby panel, and allows rebinding on PC. Delete the `GetControls()` fallback (`MovementController` 527–542). | 4–6 days | F20 | Phases 1–3, finished before the first public release. Roblox makes the new input system the default in early 2027 and removes the old player scripts by mid-2027, the same kind of change that broke movement. |
| B12 | **Play with friends.** An INVITE button on the lobby, death and victory screens. Party members (up to 4; party size is still open question 5 in [modes-progression.md](modes-progression.md)) join the same server and stay together in the lobby. Their launch plates stay random: neighbouring plates would turn a party into a bloc at the Spire rush against solo players. After death, SPECTATE still opens on your killer (QW4), with living friends next in the order. A small gesture wheel (T, gamepad Y in the arena, or a touch button) for the many players without chat: Wave, Point, Follow me, Danger, Truce. When two contenders offer each other a Truce, each sees a small mark over the other until either deals damage or the border starts moving. No hand-sign salute and nothing like one ([Roadmap](../Roadmap.md) §7). | 4–6 days | — | Before the first public release, since Roblox ranks days spent playing with friends. Full parties and queues come with Phase 9's MatchService ([modes-progression.md](modes-progression.md) proposes a party cap of 4). |

**Too big for this plan, but worth planning for**
- **AI stand-ins (XL).** Honestly labelled AI contenders on Phase 2b's AgentService core. They loot, drink, drift in with the border, and fight at a readable pace. They fill rounds up to 8 when few humans are on and soften a new player's first rounds, and they never count for Wins or Kills. Fortnite and Apex use bots this way ([Fortnite](https://www.oneesports.gg/fortnite/fortnite-is-getting-improved-matchmaking-logic-and-bots-for-new-players/); [Apex](https://gameriv.com/apex-legends-adds-orientation-matches-to-make-the-game-friendly-for-new-players/)). Until then, QW1 covers empty servers.
- **A second chance for early fallers (L).** A one-time 1v1 in a pit on the Tor for anyone who falls before Roll Call 1; the winner goes back in. Revisit it once B3, B4 and B9 have cut the wait and you can measure what is left.

**Inputs to work already planned (no new rows)**
- **Phase 1, movement:polish.** Test the new jump against a budget of about 4 frames from press to first motion (about 67 ms at 60 fps; [Mick West](https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games)), filmed at 60 fps on PC and on a mid-range phone. Answer a refused jump with a small eye dip and a scuff. Add a 0.15 s ledge-grab buffer and about 0.4 studs of corner correction ([Celeste](https://maddymakesgames.com/articles/celeste_and_forgiveness/)). If testers still call starts heavy, raise the push-off for the first 0.1 s only (`PushAcceleration` 48, `Config` line 104) and leave top speed alone, so the weight stays in the skid and the carve.
- **Phase 1, art import and qa:integration.** Test on the phones most players have, not only a mid-range one (the [LookDevPlaybook](../research/LookDevPlaybook.md) §7.2 tests "one real mid-range phone", and Roadmap Phases 3 and 9 name a mid-range phone). Roblox says most players are on lower-spec phones, and about 60% of its Android players have 2–4 GB of RAM ([testing on hardware](https://create.roblox.com/docs/performance-optimization/test-on-hardware)). A crash in the first minutes counts as a bounce (P1). Add a 3 GB Android phone (Moto G05 or Oppo A18 class) as a "done when" device: at least 30 fps at the launch with 24 contenders, in the Spire fight and through the Roll Call, and no out-of-memory crash in a full round. With 8 GLBs and 77 PNGs being imported now, measure memory on that phone first. If it is tight, move the playbook's §7.3 texture budget down one step (512 by default, 1024 for hero assets such as the Spire), as Roblox's [memory guide](https://create.roblox.com/docs/projects/performance-optimization/memory) advises; the realistic look then scales with the quality level instead of shutting these players out.
- **Phase 2a.** Build the Lure v0 first: it fills the empty middle of the round with code that exists (`LootService.refillSpire`'s falling crates). Use QW9's formatter for every Warden broadcast. Give the Director's "reads the mood" rule ([arena-events.md](arena-events.md) §3) an intensity value per contender, with build-up, peak, fade and rest ([Booth, 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)). Let small rounds have events too: §3 allows no new events once two or fewer contenders are left (line 86), so a round that starts with 2 gets none at all. Apply that rule only to rounds that started with more than 2, and run a 2-contender round at Slot 1's light intensity (0.6).
- **Phase 3, Favour.** Let quiet play reach a Patron capsule. Under [arena-events.md](arena-events.md) §7, a contender who only hides and scavenges earns about 90 Favour in a full round (+1 every 10 s), short of the first capsule at 100 unless a Warden event catches them (+30) or they make the last 8 (+10). Capsules that follow need, such as water for the thirsty or a hunting knife for someone with only fists, should reach those players too. Add small awards for survival skill, such as a first drink from a stream or a night survived. Catch-up help that favours whoever is behind is a long-standing pattern ([Mario Kart's position-based items](https://en.wikipedia.org/wiki/Mario_Kart)).
- **Phase 5.** QW4's progress line, B5's bests and B6's First Steps become the Round Report's first lines.
- **Phase 7.** The Practice Yard (B4) becomes the Assessment Hall.

---

## 5. Controls and HUD after the changes

Gamepad buttons are written as Xbox name / PlayStation name. The last column names the change that adds or alters the row.

| Action | Keyboard and mouse | Gamepad | Touch | Change |
|---|---|---|---|---|
| Move | W A S D | left stick | left thumbstick | — |
| Look | mouse | right stick (its own speed setting) | drag on the right half, or while holding ATTACK or DRAW | QW13, B2 |
| Sprint | Shift: Hold (default), Toggle or Auto | L3: Toggle (default), Hold or Auto | Auto (default): a full push sprints; RUN to switch | QW13 |
| Crouch · slide while sprinting | C or Ctrl: Hold or Toggle | B / Circle | CROUCH | QW13 |
| Jump · vault · climb (push into a ledge or a climbable tree) | Space | A / Cross | jump button | — |
| Let go of a climb | C or Ctrl | B / Circle | CROUCH | QW6 lists it |
| Attack · use the held item (hold to eat, drink, heal, put on armour or draw the bow) | left click | RT / R2 | ATTACK, which reads DRAW, THROW, EAT, DRINK, HEAL or WEAR | QW2 |
| Aim (bow zoom; with a spear, Aim + Attack throws) | right click (hold) | LT / L2 | AIM toggle (bow, spear); ATTACK reads THROW while a spear is aimed | QW2 |
| Open a crate (hold) · take · take all | E | X / Square | tap the prompt | QW8 |
| Drink · fill a bottle (while looking at water) | E | X / Square | DRINK or FILL (near water) | QW2, QW13 |
| Heal (at health 70 or less, when carrying healing) | H | D-pad left | HEAL (appears when needed) | B2 |
| Select item | 1–6, mouse wheel | LB / L1 and RB / R1 | tap a slot | QW12 |
| Drop | G: tap for one, hold for the stack | D-pad down: tap for one, hold for the stack | long-press a slot (the DROP button until B2) | QW12, B2 |
| Gestures | T | Y / Triangle (hold) | gesture button | B12 |
| Menu | M | D-pad up | menu button | — |
| Spectate: previous · next · leave | Q / E or ← / →, Backspace | LB / L1, RB / R1, B / Circle | ‹ ›, back | — |

**Reserved keys.** R and D-pad right are planned for CycleAmmo in Phase 4a ([loot-equipment.md](loot-equipment.md) §3.3), and F for Inspect in Phase 6b ([economy-cosmetics.md](economy-cosmetics.md)), which also names D-pad right. B11's single bindings table settles that clash; until then, bind nothing new there. STORE is planned on B and D-pad left in the lobby only ([economy-cosmetics.md](economy-cosmetics.md)), so D-pad left can be Heal in the arena. Y opens SPECTATE in the lobby (`LobbyController` line 176), so the gesture wheel holds Y only in the arena. M stays Menu until there is a map.

| HUD element | What it shows | When | Change |
|---|---|---|---|
| Health | the value and the ghost bar; a shimmer while healing; "NOT HEALING · THIRSTY" when a meter blocks healing, and a red "DEHYDRATED" or "STARVING" when one is empty; LOW at 35%, with the vignette and heartbeat on the same line | always (hidden at full in Contextual mode) | QW5, B10 |
| Hunger and Thirst | the value, with a tick at 55 (the healing line); LOW at 25% | always (they fade while steady above 55 in Contextual mode) | QW5, B10 |
| Stamina | appears when used, hides when full | as today | — |
| Action hint, under the crosshair | what the held item does, with this device's button; Drink or Fill at water; how to climb, the first few times | the first uses, fading as learned | QW2, QW13 |
| Cards | THIRSTY and HUNGRY, once each for new players; never during a Roll Call | new players | QW5 |
| Compass | the Spire; water when you are thirsty (Guidance); the distance to the border near its edge | as needed | QW10 |
| Event line | always the next beat: the Roll Call, the Offering, the border, and later Warden events | always in the arena | QW9 |
| Hotbar | slots, counts and the rarity line (and pips); "+4 ARROWS"; the item toast with its description for first pickups; "FISTS" when unarmed | always | QW2, QW8, QW12, B10 |
| Top right | the clock, "N REMAIN", the kill feed | as today | — |
| Death card | placement and cause; a tip; "OUTLASTED 15 OF 24 · 6:12"; how you fell; SPECTATE (your killer), TRAIN, PLAY NOW, CONTINUE | on death | QW4, B4, B5, B9 |
| Lobby | the three-step line; HOW TO PLAY open only before the first round; the pill with the time left, or the solo practice timer; the record card with bests | in the lobby | QW1, QW4, QW6, B5 |
| First Steps | three goals at the top left | new players | B6 |
| Touch buttons (7 at most, with jump) | ATTACK (it relabels), AIM, RUN (hidden on Auto), CROUCH, DRINK or FILL near water, HEAL when needed, jump | phones and tablets | QW2, QW13, B2 |

---

## 6. A first-time-player test with 3–5 friends

**Who.** 3–5 friends who haven't seen the game. Mix the devices: at least one phone, ideally an inexpensive Android one, because most Roblox sessions are on mobile and most of those phones are lower-spec, and one controller if you can. You host and watch; if possible, a second person takes notes.

**Where.** A published copy of the place on live settings: two players to start, real timers, saving, and the onboarding funnel, which only logs in published games. If you have to use Studio, run a team test with `Config.Studio.SoloTest` and `FastTimers` off (lines 318–322). Ask your friends whether you may record their screens and voices, and record only if they agree.

**Run it twice:** once now as a baseline, and once after the quick wins, with new friends if you can, because people who have played already know the game.

**What you say.** Only this: "It's a survival game on Roblox. Play it the way you'd play anything new. I can't answer questions while you play, but please say out loud what you're thinking." Don't coach. If someone is stuck for more than 2 minutes, note where, then help.

**The session.** 10 minutes to set up, 3 rounds (about 45 minutes) with 2 minutes of questions after each, then 10 minutes at the end.

**What to watch** (note the time of each):
- The first 60 s in the lobby: do they read the panel, close it, or wander off? (F1)
- The 10 s on the plate: do they look around, or read the caption? (F4)
- The first 10 s after the horn: do they rush or run? Ask why afterwards. (F5, F9)
- The first item: do they try to use it, and how? Watch for the first spear throw, bow draw, bottle fill and tree climb. (F11)
- Thirst and hunger: when do they first notice? Do they find water? (F13, F15)
- Every "is it broken?", every "how do I…?", and every press that does nothing. (F12, F20)
- Each death: what do they say in the first 5 seconds? (F16)
- After death: do they press SPECTATE or CONTINUE, or leave? What do they do while they wait? (F3)
- The middle of the round: do they get lost or bored? (F14, F19)
- Phones: can they aim the bow while holding DRAW? Do the buttons fit their thumbs? (F20)

**What to ask after each round** (2 minutes):
1. How do you win?
2. What killed you, and what would you do differently?
3. What was the most confusing moment?
4. What was the best moment?
5. From 1 to 5, how much do you want to play another round right now?

**What to ask at the end** (10 minutes):
- Which of these didn't you know how to do: eat, drink, fill a bottle, throw the spear, climb a tree, open a crate, spectate, change a setting?
- If your health stopped coming back, why did it?
- From 1 to 5: easy to learn · fun · fair deaths · looked good.
- What would make you come back tomorrow?

**What to measure**

| Measure | How | Target after the quick wins |
|---|---|---|
| Can say how to win after round 1 | question 1 | 5 of 5 |
| Join → first movement | recording | 10 s or less each |
| Horn → first crate opened | recording | median 20 s or less for rushers, 40 s or less for runners |
| Horn → weapon in hand | recording | median 30 s or less |
| First eat and first drink without help | recording | at least 4 of 5 in round 1 |
| Drank before thirst turned LOW | recording | at least 4 of 5 |
| Deaths by thirst or hunger | death cards | none after round 1 |
| Spear thrown or bow fired correctly the first time | recording | at least 3 of 5 |
| Presses with no answer | recording tally | 1 or fewer per player per round |
| "How do I…?" questions | observer tally | 2 or fewer per player per session |
| Can name what killed them and how to avoid it | question 2 | at least 4 of 5 |
| Watched their killer after death | recording | at least 4 of 5 of those who died |
| First sighting of a rival in a small round | recording | 3:00 or less after the horn |
| Phone: aimed while holding DRAW | recording | yes |
| "Another round right now?" | question 5 | median 4 or more |
| Started a 4th round without being asked | watch | at least 3 of 5 |
| Came back the next day without being asked | ask them; funnel step 1 the next day | note it |

**A sheet to log on**

| Tester | Device | Round | Time | What happened | Friction |
|---|---|---|---|---|---|
| A | phone | 1 | 0:42 | Held berries, tapped USE twice and gave up (eating needs a hold) | F11 |
| | | | | | |

**Afterwards.** Check the funnel (QW15) the next day. List the three biggest drops and the three most repeated "how do I…?" questions; they choose the next quick wins. Fix the largest early drop first. Once the game is public, Roblox's Experiments can A/B test hint timings, for example the thirst card at 60% against 45% ([Roblox onboarding](https://create.roblox.com/docs/production/game-design/onboarding)).

---

## 7. Questions for you

| # | Question | Recommendation |
|---|---|---|
| Q1 | **Help for new players.** Should a player's first 3 rounds show extra help (action hints, a crate outline, a water marker and one-time cards) that then fades, with a Guidance setting (Auto, Always, Off)? | **Yes, Auto by default.** Regulars get the clean, realistic screen, and newcomers aren't lost. |
| Q2 | **Bow headshots.** Lower the bow's headshot multiplier from 2 to 1.8, so a full-draw headshot does 90 and a healthy, unarmoured contender always survives one arrow? | **Yes.** Deaths to an arrow nobody heard are the ones that make new players quit, and the bow stays the strongest ranged weapon. It pairs with [loot-equipment.md](loot-equipment.md)'s open decision 2 (from 7.5 to 4.5 bows a round), which Phase 4a's leaner loot tables already plan. |
| Q3 | **The end of the round.** Should the ring close to nothing after 13:50 ("the Last Stand"), beside the Spire rather than on it, so every round has exactly one winner, with a timeout settled by health? And should Day 2's Roll Call become a short epilogue behind the winner card, since its sky show can no longer play during the finale? | **Yes to both.** "Nobody claims the win" is an anticlimax, and a pair who wait out the clock is too close to a source beat. The epilogue keeps the Roll Call, the show's signature moment, in every round. |
| Q4 | **The opening choice.** Add 8 runner's caches at the meadow edge, each with a guaranteed basic weapon and water, marked with pale cloth you can see from the plates? | **Yes.** Running becomes a real choice, and the Spire still holds the best gear. |
| Q5 | **Quiet servers.** Start a practice round with training dummies after 30 s alone on a live server now, and later fill quiet rounds with clearly labelled AI stand-ins that never count for Wins or Kills? | **Yes to both.** Build the stand-ins on Phase 2b's AgentService. |

---

## Sources

Code references are given inline as script paths and line numbers (Studio, read-only, 11 November 2026). The pillar designs and research docs are linked where they are used.

**Roblox**
- Discovery and ranking signals: https://create.roblox.com/docs/discovery
- Engagement: https://create.roblox.com/docs/production/analytics/engagement
- Retention: https://create.roblox.com/docs/production/analytics/retention
- Onboarding: https://create.roblox.com/docs/production/game-design/onboarding
- Onboarding techniques: https://create.roblox.com/docs/production/game-design/onboarding-techniques
- Onboarding funnel events: https://create.roblox.com/docs/production/analytics/funnel-events
- Funnel case study (DevForum): https://devforum.roblox.com/t/3064458
- First-time experience, Roblox staff (DevForum): https://devforum.roblox.com/t/learn-more-about-first-time-user-experience-onboarding/2621940
- A Roblox battle-royale playtest (DevForum): https://devforum.roblox.com/t/playtest-where-am-i-losing-players%E2%80%94before-during-or-after-their-first-match/4780000
- Not enough players at launch (DevForum): https://devforum.roblox.com/t/worried-my-multiplayer-game-wont-have-enough-players-at-launch/4807146
- Mobile input: https://create.roblox.com/docs/input/mobile
- Adaptive design: https://create.roblox.com/docs/production/publishing/adaptive-design
- Cross-platform guide: https://create.roblox.com/docs/projects/cross-platform
- Input Action System: https://create.roblox.com/docs/input/input-action-system
- Input Action System release and migration (DevForum): https://devforum.roblox.com/t/full-release-input-action-system-ias-newly-converted-player-scripts/4678416
- PreferredInput (DevForum): https://devforum.roblox.com/t/full-release-introducing-preferredinput-and-improved-touch-capabilities/3750890
- The moved touch controls (DevForum): https://devforum.roblox.com/t/full-release-the-future-of-character-movement-character-controller-library/4565267
- UI position and size, touch buttons: https://create.roblox.com/docs/ui/position-and-size
- Matchmaking attributes and signals: https://create.roblox.com/docs/matchmaking/attributes-and-signals
- Accessibility: https://create.roblox.com/docs/production/publishing/accessibility
- Invite prompts: https://create.roblox.com/docs/production/promotion/invite-prompts
- Party API (DevForum): https://devforum.roblox.com/t/party-api-is-here-enable-connected-player-experiences-and-drive-deeper-engagement/3676068
- Age checks for chat: https://about.roblox.com/newsroom/2025/11/roblox-requires-age-checks-limits-minor-and-adult-chat
- Testing on low-end hardware: https://create.roblox.com/docs/performance-optimization/test-on-hardware
- Memory and texture budgets: https://create.roblox.com/docs/projects/performance-optimization/memory
- Matchmaking: https://create.roblox.com/docs/matchmaking
- GameAnalytics 2026 Roblox report: https://www.gameanalytics.com/reports/2026-roblox-report

**Onboarding, readability and feel**
- NN/g, how little users read: https://www.nngroup.com/articles/how-little-do-users-read/
- NN/g, ten usability heuristics: https://www.nngroup.com/articles/ten-usability-heuristics/
- World 1-1: https://www.gamedeveloper.com/design/how-miyamoto-built-i-super-mario-bros-i-legendary-world-1-1
- Portal's playtesting: https://www.gamedeveloper.com/pc/best-of-gdc-the-secrets-of-i-portal-i-s-huge-success
- Rust's Tutorial Island: https://rust.facepunch.com/news/lighting-the-way
- Game feel (Swink): https://www.gamedeveloper.com/design/game-feel-the-secret-ingredient
- Measuring responsiveness (Mick West): https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games
- Celeste and forgiveness: https://maddymakesgames.com/articles/celeste_and_forgiveness/
- Juice It or Lose It: https://www.gamedeveloper.com/design/video-is-your-game-juicy-enough-
- Enemy attacks and telegraphing: https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing
- Readability in action games: https://www.gamedeveloper.com/game-platforms/designing-for-difficulty-readability-in-arpgs
- Valve, art that serves play: https://www.gamedeveloper.com/art/in-depth-how-valve-makes-art-to-enhance-gameplay
- Removing the HUD (Iacovides et al., CHI PLAY 2015): https://oro.open.ac.uk/46759
- In-world guides versus a compass (Peacocke et al. 2018): https://www.yorku.ca/mack/ec2018.html
- The Long Dark's HUD: https://www.gamedeveloper.com/design/long-dark-survival-game-hud-ui
- Hunt: Showdown's sound language: https://blog.playstation.com/?p=221483
- Impact feel (Lin et al. 2022): https://arxiv.org/abs/2208.06155

**Survival and battle-royale design**
- Making death fun: https://www.gamedeveloper.com/design/making-death-fun-something-medal-of-honor-needs-to-fix-for-launch-
- DOORS death tips: https://rblxguide.com/games/doors/entities/guiding-light
- Fortnite spectating: https://www.oneesports.gg/fortnite/how-to-spectate-in-fortnite-2-easy/
- Fortnite bots for new players: https://www.oneesports.gg/fortnite/fortnite-is-getting-improved-matchmaking-logic-and-bots-for-new-players/
- Apex Orientation Matches: https://gameriv.com/apex-legends-adds-orientation-matches-to-make-the-game-friendly-for-new-players/
- PUBG Update 42.1: https://pubg.com/news/10179
- A zone timed to the players left: https://www.pcgamer.com/pubgs-savage-map-has-a-blue-zone-that-adjusts-its-timing-based-on-the-number-of-players-left
- Designing PUBG's maps: https://www.gamedeveloper.com/design/designing-the-giant-battle-royale-maps-of-i-playerunknown-s-battlegrounds-i-
- Why PUBG hooks players: https://www.gamedeveloper.com/business/how-can-pubg-be-addictive-to-billions-of-people-
- Top-tier gear in battle royales: https://www.gamedeveloper.com/design/examining-my-gameplay-issue-with-battle-royale-design
- The AI Systems of Left 4 Dead (Booth, 2009): https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf
- Zone warnings in battle royales: https://uefncentral.com/id/blog/advanced-battle-royale-zone-mechanics-uefn
- Natural Disaster Survival: https://screenwiseapp.com/guides/natural-disaster-survival
- Time to kill (Realm Royale): https://pcgamesn.com/realm-royale/realm-royale-ttk
- DayZ's slow pressure: https://www.gamedeveloper.com/design/dean-hall-discusses-i-dayz-i-s-development-process
- Catch-up items (Mario Kart): https://en.wikipedia.org/wiki/Mario_Kart

**Accessibility and input**
- Game Accessibility Guidelines: https://gameaccessibilityguidelines.com/full-list/
- No information by colour alone: https://gameaccessibilityguidelines.com/ensure-no-essential-information-is-conveyed-by-a-colour-alone/
- Xbox Accessibility Guideline 107 (input): https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107
- Xbox Accessibility Guideline 117 (motion and camera): https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/117
- Mobile shooter controls (CoD Mobile): https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls
- Aim assist (Halo): https://www.halopedia.org/Aim_assist

---

## Review notes

*Design review, 11 November 2026. Checked read-only in Studio: client and shared scripts during a playtest, server scripts once Studio was back in Edit mode. Also checked against the Roadmap and the pillar docs. Almost every line reference held. What changed:*

**Corrections**
- **QW2.** Item hints no longer go through `InventoryController.setHint`, which also binds Drink to E (line 597) and would have blocked crate prompts. The fade counter needs 3 bits per action, not 2.
- **QW3.** The border wall shows only in Active (`ArenaController.wallShouldShow`, line 170), so it needs a change before it can be seen from the plates. ArenaController is added to QW3's scripts.
- **QW4.** Three tips taught things players can't see today: rival wind-ups (not until B1), arrow drop (the crosshair solve removes it) and a raised spear. They now teach something visible. The lobby pill counts down instead of showing a clock time.
- **QW14.** "Last Light" already names Warden slot 6 and an Achievement, so the finale is now "the Last Stand", and it closes beside the Spire, not on it. Roll Call 2 always falls after the border has closed, so the old condition was always true and Day 2's sky show would never play. A short epilogue keeps it (Q3).
- **B1.** Wind-ups of "at least 0.2 s" contradicted CombatPhysicsPlan §2.4: another player sees a swing about 150 ms late.
- **B3.** "MOVES AT 5:50" read as a clock time on a countdown HUD, so it now says "IN". Phase 5's "Standard timeline is unchanged" check holds only at 16 or more contenders.
- **B7.** A vault tops out at 3.4 studs and a mantle at 6.5, so the fence rule uses 6.5. **B12.** Neighbouring plates would start a party as a bloc in a free-for-all, and "spectate a friend first" contradicted QW4. Plates stay random, and SPECTATE still opens on your killer.
- **QW10 and Q1.** The water marker showed for 5 rounds against Q1's 3. It now follows the new-player rule.

**Added from the research and audits**
- A plain-English summary at the top.
- **QW1.** One countdown for a lone player, and an early practice end that says "survived the practice round".
- **QW2.** The climb hint, hints that don't flicker (P8 promised this but no quick win did it), and FILL on the touch button.
- **QW5.** The reason shows only when a meter is the cause, and a meter at 0 gets a red DEHYDRATED or STARVING state.
- **QW6.** Corrected control rows (the spear row was wrong), crouching taught as quieter, and the practice banner kept.
- **QW9.** Names come from `Shared.Lore`, which retires the HUD's live "THE FEAST" strings early.
- **QW10.** Border distance on the compass, which section 5 already listed.
- **QW13.** Choices as stepped sliders, an FOV floor of 55, and a check that the mouse slider still works.
- **QW15.** `Input.describe`, and the two signals the funnel still needs.
- **B8.** Finishing beats. **B9.** The matchmaking caveat. **B10.** A vignette that never hides a flanker, and loot prompts in the game's own style.
- **Planned work.** A 3 GB Android test device and texture budget for the art import, Warden events in 2-contender rounds, Favour that reaches quiet players, and a push-off tweak for movement:polish.
- **Smaller notes.** The reserved-key notes, a low-cost phone in the friends test, A/B tests with Experiments, and Q2's link to the bow-count decision.

**Checked and kept.** The IP rule holds: no source names appear, and "Feast" and "cannon" only describe live code. Nothing is sold, and the realism guard rails stand. Every friction-row time was recomputed from `Config`. The only size change is QW14's extra half day for the epilogue.

**For other docs (not edited here).** [arena-events.md](arena-events.md) §1 and §3 still give the old Roll Call times (5:33 and 13:48; `Config` now gives 5:45 and 14:05). Roadmap Phase 1 places the cannon at `PlayerService` line 513; it is at line 482 now.
