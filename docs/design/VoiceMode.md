# Proximity Voice: design

*Written 14 November 2026 for the owner's request: "i also want to add a mode for people to be able to vc - with voicechat proxiimity". Lead review of the first draft and the critic's notes; section 11 says what changed and what was turned down.*

**Status: nothing is installed and none of it has run.** Studio stays with the testers until release QA is done. The code exists only as drafts in the repo folder `drafts/voice_mode/` (section 6), all of it behind `Config.Voice.Enabled = false`. They are written against place version 199: re-check them against the release fixes before applying (section 7, step 3). Real voice can only be tested in a published game with two or more voice-enabled accounts [24].

## In plain English (for the owner)

- **What you get.** Players with Roblox voice can talk to whoever is standing near them. Close up you hear them clearly, a few metres away they get quieter, and about 30 m away in the arena you can't hear them at all. Everyone gets an **ON / OFF** switch on the lobby card, and their choice is remembered.
- **The dead can't help the living.** The moment someone dies, the living can't hear them any more. The fallen and spectators can still talk to each other.
- **It's one "mode" for everyone, not separate servers.** Splitting players into voice servers and no-voice servers would make rounds slower to fill during the beta. Roblox already puts voice users together when it picks a server. Voice-only servers are drafted for later, switched off.
- **Safe by default.** The first public version only uses Roblox's own voice system, plus our distance settings and a few rules on top. Roblox's mute, block, report and volume controls keep working as Roblox built them. A richer version adds walls that muffle voices, hearing "through the eyes" of the player you spectate, and a shared channel for spectators. That version only goes in if a test with real accounts shows that Roblox's mute, block and volume controls still work with it.
- **Privacy.** If a player turns voice **OFF**, nothing turns it back on by itself. Not a slow or failed save load, not Settings › Reset, not a lost message. Nothing is ever recorded by us.
- **Not for today's release.** Nothing changes for the beta today. After the testers are done, install it, test it in a private copy with two or three voice accounts, then switch it on.
- **One thing to know now.** Voice is already on for this game (`voiceChatEnabled = true`). Today's beta launches with Roblox's plain proximity voice for eligible players (13+ and age-checked) [19][21], whatever we do. Under those rules a dead player's body can still be heard for about 4 seconds, and there are no game controls for voice yet.

## 1. How the mode works for players

**The switch.** The lobby card, under SETTINGS and HOW TO PLAY, shows **PROXIMITY VOICE [ON / OFF]**. One line underneath says what that means:

- *"On · players near you hear you. In a round, the fallen only hear each other."*
- *"Off · you don't hear voice, and nobody hears you."*

Settings › VOICE has the same switch, plus *Players and muting ›*. Voice volume is there too, in the full version only (with the safe version, Roblox's own voice volume controls do that job). The choice is saved as `settings.voiceOn`.

- A player who never chose starts **On** (`DefaultOn`), but only once their saved settings have loaded. Until then their microphone stays closed and they hear nobody. The card reads *"Loading your voice setting… voice stays off until it's in."*
- If the load fails, voice stays off for that visit. The card says *"Off · your saved setting didn't load. Turn voice on to talk and listen."*

**Who can use it.** Only accounts Roblox allows to use voice (13+, age-checked, voice turned on) [19][21]. Everyone else sees *"Not on your account. Roblox voice needs its 13+ age check; text chat works as usual."* Nothing else in the game changes for them. Roblox's own "unlock voice" prompts may appear inside the game [21].

**What a voice player sees.**
- **Mic chip** (in the arena and while spectating). It reads `VOICE · NEARBY`, `VOICE · THE STANDS`, `VOICE · WHISPER · ALLIES ONLY`, `MIC OFF · …`, `VOICE OFF` or `VOICE · LOADING YOUR SETTING`. A dot lights while you talk. It sits at the left middle on desktop, and at the top right on touch (left of DROP).
- **Who's talking near you.** Up to 4 rows (3 on phones), loudest first. A row appears only when you can actually hear that voice (4% or more). `ShowTalkerNames = false` would show "SOMEONE NEARBY" to contenders instead of names.
- **VOICE panel** (PLAYERS › on the card, or Settings › Players and muting). It lists every player with voice on this server, each with:
  - **MUTE / UNMUTE:** on your device only, for this server;
  - **BLOCK:** Roblox's own block prompt. A player you blocked on Roblox shows **BLOCKED**.

  It also says how to report someone.
- **Three one-line tips**, each shown at most twice per player: in the lobby, when the round starts, and after you fall.

**Whisper (off until truces exist).** The owner said yes to truces. A contender with truce allies can hold **V** (or D-pad left) to whisper. Only those allies hear it, and only within 18 studs (about 6 m). It is wired up but switched off (`Config.Voice.Whisper.Enabled = false`) until a TruceService calls `VoiceService.setAllies`.

**Voice-only servers (phase 2, off).** When the game has enough players, `Config.Voice.VoiceServers.Enabled = true` adds a **VOICE-ONLY SERVER ›** link to the card.
- It moves voice users to reserved servers that only voice users can join, found through MemoryStore.
- A player without voice who arrives there is sent back to a regular server.
- Roblox never matchmakes into reserved servers, so these need our own queue [25][26][28].

**Why one shared pool for the beta:**
1. Players are the scarcest thing. A 24-contender round needs one full pool (see `docs/design/modes-progression.md`).
2. Roblox's matchmaking already scores how many players in a server share your voice setting (the Voice Chat signal, weight 1 by default). The weight can be raised per place under Creator Dashboard › Configurations › Matchmaking [25].
3. A real "no voice" server would need a second place, because voice settings belong to a place [4]. Muting every microphone still leaves Roblox's voice buttons on screen.

## 2. Who hears whom: the dead and spectator rules

The server gives every player a **voice role**, kept in the `VoiceRole` attribute, and writes who may hear them onto Roblox's own voice object for that player (`AudioDeviceInput`: an access list and a mute) [4][6]. The list is set on the server and passed to every client [7].

| When | Role | Who can hear them |
|---|---|---|
| No round running (Lobby, Intermission, Ending) | **Open** | Anyone in range |
| A round running (Countdown, Active; later the train, training room and launch: `Config.Voice.RoundPhases`) and alive | **Contender** | Anyone in range: other contenders, and spectators watching nearby |
| A round running and **not** alive: the fallen, late joiners, everyone in the lobby | **Bench** ("the stands") | **Only the stands.** The living are never on that list, wherever they stand or look. |
| A contender holding V with truce allies (off for now) | Contender, whispering | Only those allies, from close up |

**The rules for the dead and for spectators:**

1. **Death switches you at once.** When a contender dies, `PlayerService.handleDeath` calls `VoiceService.onEliminated` right after `Alive` goes false, before the cannon sounds. From that moment the living can't hear the body, even standing next to it. (Today, without this work, the body can still be heard for the 4 s `RespawnDelay`.)
2. **The writes can't leak.** Every change to a player's voice object is written in an order that never lets anyone hear them who isn't allowed both before and after the change. It goes: mute first, unmute last; when narrowing, switch to an allow list before setting the list; when opening up, empty the list before switching back. This is model-checked for every possible case (section 8, S1).
3. **The stands can't reach the arena.** That covers the fallen, spectators, late joiners and the lobby during a round.
4. **The stands hear each other.**
   - On the Tor, by distance.
   - In the full version only (`Spectators.StandsBus`), every spectator also hears every other spectator, with no distance, whoever each one is watching.
5. **Spectators hear the arena.**
   - Full version: through the ears of the contender they watch, facing where their own camera faces.
   - Safe version: from their orbiting camera.
6. **Spectating keeps working after you respawn.** A fallen player who starts spectating before they respawn on the Tor keeps following the contender they watch after the respawn. (In today's code the respawn quietly cleared it. That pulled streaming back to the Tor, 2,600 studs away, and would have dropped them from the stands' channel. This is fixed in the same patch.)
7. **When the round ends, everyone is Open again.** The fallen are on the Tor and the winner is in the arena, so distance keeps them apart.
8. **Not covered: text chat.** The fallen can still type in the general text channel.

## 3. The proximity numbers

Distances are in studs. An R15 contender is about 5.2 studs tall, so 1 stud is about 0.33 m. The fade between *full* and *silent* is the inverse-distance law raised to `Shape`, times a taper that reaches zero at *silent* (`VoiceController.Curves`). The same numbers are used in both versions: on our listener in the full version, and on Roblox's own emitters in the safe one.

| Profile (`Config.Voice.Profiles`) | Full volume up to | Silent from | How loud in between | Used for |
|---|---|---|---|---|
| **Arena** (8 / 90 / 0.8) | 8 studs (~2.6 m) | 90 (~30 m) | 16: −4.9 dB · 32: −10.4 · 48: −14.8 · 64: −19.9 · 80: −28.8 | contenders and spectators in a round |
| **Social** (15 / 110 / 0.6) | 15 (~5 m) | 110 (~36 m) | 30: −3.8 dB · 50: −7.5 · 75: −12.8 · 100: −23.9 | the Tor; later the station and the training room |
| **Cabin** (8 / 45 / 0.9) | 8 | 45 (~15 m) | 16: −5.8 dB · 30: −14.1 · 40: −24.6 | train cars and the launch room (coming) |
| **Whisper** (4 / 18 / 1) | 4 | 18 (~6 m) | 8: −6.8 dB · 12: −13.0 · 16: −23.6 | a truce ally's whisper |
| *Today's built-in voice, for comparison* (Legacy) | 7 | 80 | 16: −2.3 dB · 32: −7.3 · 48: −14.3 · 64: −26.4 | linear-squared [3] |

- **Launch plates.** Neighbouring plates are 13.6 studs apart, so contenders next to each other hear one another at about −3.7 dB. Across the 104-stud ring is silent.
- **Talking gives you away.** Footsteps carry 60–90 studs, about as far as a voice.
- **Rooms and zones.** A part tagged `VoiceZone` with a `VoiceProfile` attribute (for example `"Cabin"`) sets the profile inside its box. A `VoiceRoom` attribute (one per train car) muffles voices that come from other rooms.

**Walls and terrain (full version only).** Five times a second, a ray runs from your ear to each of the 8 nearest speakers' heads. Terrain, rock, cliffs, buildings and tree trunks block it. Foliage crowns don't, because they have `CanQuery` off.

| Muffling knob (`Config.Voice.Occlusion`) | Value | What it does |
|---|---|---|
| `Volume` | 0.55 | a blocked voice keeps 55% of its volume (−5 dB) |
| `HighGainDb` | −24 dB | treble lost behind a wall |
| `MidGainDb` | −6 dB | mids lost behind a wall |
| `Smoothing` | 6 /s | about 0.4 s to muffle or clear |

`"Engine"` would hand muffling to Roblox's acoustic simulation, a Studio switch [15]. It is untested against the arena's 46,612 parts, so it stays off until it has been measured on a phone.

## 4. Safety

**Roblox's own tools.** We can't move or hide any of them [22]:
- the mic toggle;
- the speaker icon over each voice user (tap it to mute that user);
- Block (voice and text);
- Report Abuse, with a voice option;
- the voice volume controls (`EnableVoiceVolumeControls`: a global slider and per-player volume, available only with `UseAudioApi` on [1]);
- leaving voice in Settings.

**What we add:**
- the ON / OFF choice;
- our own per-player mute list;
- a BLOCK button that opens Roblox's own block prompt [13];
- a voice volume slider (full version only).

On every client the game also honours Roblox's block list and mute events (`GetCore("GetBlockedUserIds")`, `PlayerBlockedEvent`, `PlayerUnblockedEvent`, `PlayerMutedEvent`, `PlayerUnmutedEvent` [13]). A player you blocked is silent in our audio chain and in the stands' channel. They are never listed as talking, and the panel shows them as BLOCKED.

**What is proven and what isn't.** The server sets each player's access list, which is Roblox's documented way to choose who hears a device [4][6][7]. The docs don't say two things:
- **Where Roblox applies the list.** It could be on its voice servers or only on each client. A modified client might therefore still receive a stream it isn't listed for.
- **Whether Roblox's own mute, block, volume and age-group rules still apply when a game wires a voice device itself.** That is what the full version does for muffling and the stands' channel. Roblox's announcement says that with `UseAudioApi` on, "the behavior is entirely up to you" [5].

The unofficial API listing shows a hidden `MutedByLocalUser` property on the voice device itself [7]. That *suggests* Roblox's mute works on the device, which would reach our wires too, but nothing documents it. Hence the rule:

> **The safe version ships first.** `Config.Voice.ClientGraph = "Default"` and `Spectators.StandsBus = false` are the defaults in the code. The full version (`"Custom"` plus the stands' channel) is switched on only after the published safety gate, G1–G5 in section 8, passes in full. If any check fails, the public build stays on the safe version.

In the safe version our code never re-wires Roblox's voice. It only gives Roblox's emitters our distance curves. While you mute a player, block them or turn voice off, it moves that player's emitter to a silent group on your device, and moves it back only once, and only if nothing else changed it in the meantime. It can make Roblox's voice quieter, never louder than Roblox left it. (The first draft's "Engine" option rewrote Roblox's emitters every half second, which could have undone Roblox's own mute. It is gone.)

**Privacy: OFF stays OFF.** Each of these is a rule in the code, and each has a test:
- The server keeps a player muted until their saved choice has loaded or they choose. There is no time limit after which it opens by itself, and a failed load stays muted (Routing.choice).
- The client sends a voice choice only when the player flips the switch. Turning voice off also mutes the player's own device on their own client at once, as Roblox's push-to-talk sample does [6]. It stays muted while the choice is off, so a late message from the server can't reopen it.
- A request to turn voice **off** is never rate-limited or dropped. Other voice requests that arrive too fast are applied a moment later instead of being dropped, and an OFF cancels any ON still waiting.
- If the server still shows something other than the player's choice 2 seconds later, the client sends the choice again. The card always shows what the server actually applied (`VoiceOn` / `VoiceHold`).
- Settings › Reset leaves the voice choice alone.
- The game saves only the settings that changed, and the server merges them into what's stored. An early save, or a session whose load failed, can no longer overwrite saved settings, including a saved OFF, with defaults.

**Never recorded by us.**
- No `AudioRecorder`. It can't record a voice device anyway [12].
- No speech-to-text, no transcripts, no audio work on the server.
- The talking lights read loudness (`RmsLevel`) on each listener's own device only, and never send it. Roblox gives no voice spectra [11].
- Roblox itself may record voice for moderation. It deletes recordings after a week when nothing is reported or detected [23].

**Policy.**
- Answer "yes" to player voice and communication in the Maturity & Compliance questionnaire [20].
- Talking isn't the game's main activity, so the 16+ limit for social-hangout experiences shouldn't apply [20].
- Don't point players to off-platform voice (Discord and similar). Roblox restricts social links in experiences [19].

**Known limits and risks:**
- **The speaker icon gives hiders away.** Roblox shows a speaker icon over every voice user. Community reports say it can't be hidden or moved and stays on top [29]. In a hiding game that marks voice users.
- **Age groups.** Roblox connects voice only between similar age groups and Trusted Connections [19][27]. Some players in the panel won't hear each other.
- **Modified clients.**
  - Distance and muffling run on each device, so a modified client could hear living contenders from further than 90 studs.
  - Only the access lists are set by the server (see above).
- **Voice suspensions.** A suspended player can neither speak nor hear, reportedly for about 5 minutes, and has to rejoin [30].
- **The fallback.** If `UseAudioApi` isn't Enabled, there are no voice devices for our rules to use. Voice is then Roblox's old built-in voice, and the server logs a warning after 30 s [2].
- **Studio can't test voice locally** [24].

## 5. The Studio settings to flip

> **Read first:** `VoiceChatService.UseAudioApi = Enabled` changes voice for **every player in the place** as soon as it is published, whatever `Config.Voice.Enabled` says. That flag only switches our scripts. `UseAudioApi` switches Roblox's own voice from its old built-in system to the Audio API one [1][2]. So it goes into the private test copy first, and into the live place only in the same publish that switches our scripts on. `studio/ApplyVoiceSettings.lua` enforces this: on the live place it refuses unless `Config.Voice.Enabled` is already true there **and** `APPLY_TO_LIVE_PLACE = true` is set in the script.

| Setting | Where | Value | Notes |
|---|---|---|---|
| Experience voice (universe) | Studio › Game Settings › Communication, or the Creator Dashboard | **On**: already on (`voiceChatEnabled = true`) | Max players must be 100 or fewer; ours is 24 [4][18] |
| `VoiceChatService.UseAudioApi` | `ApplyVoiceSettings.lua` (command bar, Edit mode) or the Properties window | **Enabled** | Automatic still means the old built-in voice today, and "will be updated to mean Enabled in the future" [2] |
| `VoiceChatService.EnableDefaultVoice` | same | **true** (the default) | Roblox keeps making each player's voice device and emitter [1] |
| `VoiceChatService.DefaultDistanceAttenuation` | same | **Legacy** | Roblox's own voice keeps today's 7–80 stud fade wherever our curves don't apply [3] |
| `VoiceChatService.EnableVoiceVolumeControls` | Properties window only (scripts can't set it) | leave **on** if shown | Roblox's own voice volume controls [1] |
| `SoundService.DefaultListenerLocation` | Properties | leave **Default / Camera** | In the safe version, spectators hear from their camera |
| `SoundService.AcousticSimulationEnabled` | Properties | leave **off** | Trial later, on a phone [15] |
| `ReplicatedStorage.Remotes.VoiceRequest` | made by `ApplyVoiceSettings.lua` | a RemoteEvent | Listed in `Shared.Net` |
| `Config.Voice.Enabled`, `ClientGraph`, `Spectators.StandsBus` | `ReplicatedStorage.Shared.Config` (a script edit) | true, then `"Default"` / false, or `"Custom"` / true **only if the gate passed** | |
| Matchmaking, Voice Chat signal weight (later, optional) | Creator Dashboard › Configurations › Matchmaking | above 1 | Puts voice users together more often [25] |
| Maturity & Compliance questionnaire | Creator Dashboard | voice and communication: **yes** | [20] |

To undo it after Studio has been closed (Ctrl+Z only works straight away), run `studio/RevertVoiceSettings.lua` with the "before" values that ApplyVoiceSettings printed, set `Config.Voice.Enabled = false`, and publish.

## 6. The code drafts, and where each file goes

Every draft is in the repo folder `drafts/voice_mode/`, copied there unchanged from the session's temporary scratchpad. These are drafts, not game scripts: nothing reads them, and `src/` stays the exact copy of Studio.

The Studio location follows the repo's `src/` layout. `init.lua` is the ModuleScript itself, and the files beside it are its child ModuleScripts.

| Draft (under `voice_mode/src/`) | Studio location | New or changed | What it does |
|---|---|---|---|
| `ReplicatedStorage/Shared/Config.lua` | `ReplicatedStorage.Shared.Config` | changed | `Config.Voice`: Enabled false, safe graph, every number |
| `ReplicatedStorage/Shared/Net.lua` | `…Shared.Net` | changed | adds `VoiceRequest` to `Net.Names` |
| `ReplicatedStorage/Shared/Lore.lua` | `…Shared.Lore` | changed | `Lore.Stands = "the stands"` |
| `ServerScriptService/Server/Main.server.lua` | `ServerScriptService.Server.Main` | changed | loader order: `VoiceService` last |
| `…/Server/Services/DataService.lua` | `…Services.DataService` | changed | voice settings keys; the `SettingsLoaded` attribute; settings **merged** on save; a Studio-only test hook (`workspace` attribute `DevFailSettingsLoad`) |
| `…/Server/Services/PlayerService.lua` | `…Services.PlayerService` | changed | `Spectating` attribute; the death switch (`onEliminated`); keeps a spectator's target across their respawn |
| `…/Server/Services/RoundService.lua` | `…Services.RoundService` | changed | `isRoundRunning()` |
| `…/Server/Services/VoiceService/init.lua` | `…Services.VoiceService` (ModuleScript) | **new** | roles, access lists, mutes; reads every device back every 5 s |
| `…/Server/Services/VoiceService/Routing.lua` | child `Routing` | **new** | the rules as pure functions (tested) |
| `…/Server/Services/VoiceService/VoiceServers.lua` | child `VoiceServers` | **new** | phase 2, voice-only servers (off) |
| `ServerStorage/Dev/VoiceRoutingTest.lua` | `ServerStorage.Dev.VoiceRoutingTest` | **new** | the Edit-mode rules test (S1) |
| `StarterPlayer/StarterPlayerScripts/Client/ClientMain.client.lua` | `…Client.ClientMain` | changed | loader order: `VoiceController` last |
| `…/Client/ClientState.lua` | `…Client.ClientState` | changed | the voice settings keys, `ClientState.voice`, `voiceChanged` |
| `…/Client/Controllers/LobbyController.lua` | `…Controllers.LobbyController` | changed | `mountCard()` for the voice card |
| `…/Client/Controllers/SettingsController.lua` | `…Controllers.SettingsController` | changed | VOICE section; saves only changed keys; Reset keeps the voice choice |
| `…/Client/Controllers/VoiceController/init.lua` | `…Controllers.VoiceController` (ModuleScript) | **new** | how voice sounds; the choice; blocks; the UI state |
| `…/Client/Controllers/VoiceController/Curves.lua` | child `Curves` | **new** | the distance curves |
| `…/Client/Controllers/VoiceController/Hud.lua` | child `Hud` | **new** | mic chip, talkers, lobby card, VOICE panel (built at runtime from Theme; UIBuilder doesn't change) |

**Also in `voice_mode/`:**
- **`patches/voice_mode.diff`**: all 18 files as one git patch. It applies cleanly to today's `src/`, reproduces every draft byte for byte, and keeps LF line endings. It carries each original file's blob id, so `git apply --3way` can merge it if the testers changed a file.
- **`studio/ApplyVoiceSettings.lua` and `studio/RevertVoiceSettings.lua`**: the command-bar scripts.
- **`src/ReplicatedStorage/Shared/Config.Voice.snippet.lua`**: the Config block on its own, for a hand merge.
- **`_tools/`**:
  - `make_diff.py` makes the patch;
  - `luau_check.py` and `names_check.py` are the structural checks;
  - `routing_model.py` is the write-order model check;
  - `compare_tree.py` does the byte compare;
  - `make_patches.py` made the first drafts and is retired: it refuses to run, because it would overwrite this review.
- **`ProximityVoice.sketch.luau`**: the early research sketch. Not for install.

**Two changes act even with `Enabled = false`.** Both are fixes to existing behaviour, and both are in the regression checks (S3 and S6):
1. Settings save only what changed and are merged on the server.
2. A spectator keeps their target across their respawn.

Everything else is inert while `Enabled` is false, apart from the new `SettingsLoaded` attribute.

## 7. How to apply it after the release testing

1. **Wait** until the testers have finished release QA and handed Studio back.
2. **Bring `src/` up to date with Studio**, the usual export that includes whatever the testers changed, and commit it on `v1`.
3. **Apply the patch** from the repo root:
   - check it with `git -c core.autocrlf=false apply --check <path>\voice_mode\patches\voice_mode.diff`;
   - if that's clean, apply it with `git -c core.autocrlf=false apply <path>\voice_mode\patches\voice_mode.diff`;
   - if a file changed during QA, use `git -c core.autocrlf=false apply --3way <path>\voice_mode\patches\voice_mode.diff` instead, and resolve any conflict by hand. (A trial in a throwaway clone merged cleanly around a tester's edit inside one of our hunks.)
4. **Put the scripts into Studio**:
   - the 7 new ModuleScripts: VoiceService with its children Routing and VoiceServers, VoiceController with its children Curves and Hud, and `ServerStorage.Dev.VoiceRoutingTest`;
   - the 11 changed scripts.
5. **In Studio, Edit mode:** run S1 (the rules test) and S2 (SyntaxCheck). Both must pass.
6. **Play tests in Studio:** S3–S7 (section 8).
7. **Make the private test copy.** Use File › Publish to Roblox As… › a *new* experience, kept private, that only you and the testers can join. Then:
   - check its Communication settings have voice on;
   - run `ApplyVoiceSettings.lua` there;
   - set `Config.Voice.Enabled = true`, `ClientGraph = "Custom"` and `Spectators.StandsBus = true` for the gate run;
   - publish, and run the published tests P1–P10 and the gate G1–G5 with two or three voice accounts.
8. **Decide the version.**
   - If every G check passes, ship `"Custom"` with the stands' channel on.
   - If any fails, ship `"Default"` with it off, and re-run P1, P4 and P5 in that version.
   - If the safe version also fails a G check, don't switch voice on. Keep `Enabled = false` and report it to Roblox.
9. **Go live in one publish.** In the live place:
   - set `Config.Voice.Enabled = true` and the chosen version;
   - set `APPLY_TO_LIVE_PLACE = true` in `ApplyVoiceSettings.lua` and run it;
   - answer the questionnaire;
   - publish.
10. **Watch the first day.** Join a public server, look at the Developer Console (no `[VoiceService]` or `[VoiceController]` warnings), and read player reports.
11. **Taking it out** if needed: set `Config.Voice.Enabled = false`, run `RevertVoiceSettings.lua`, and publish.

Later: matchmaking weight; the acoustic simulation trial; the whisper, once truces exist; voice-only servers, when there are enough players.

## 8. Test plan

Studio can test the rules, the UI states and the attributes with a single client. **Real voice can only be tested in a published game with two or more voice-enabled accounts:** Studio's local Clients-and-Servers test can't connect voice [24]. Write down pass or fail for every line, with the date and the accounts used.

### In Studio (after release QA; no real voice needed)

| # | Check | Pass when |
|---|---|---|
| S1 | Edit mode, command bar: `print(require(game.ServerStorage.Dev.VoiceRoutingTest:Clone()).run())` | `PASS 4416 checks`. It covers roles, the bench list, the choice rules (saved OFF stays OFF; a slow or failed load stays muted), never limiting an OFF, and all 2,176 write orders. (The same write-order model already passes on this PC: `routing_model.py`, 0 failures.) |
| S2 | `return require(game.ServerStorage.Dev.SyntaxCheck).run()` | no errors in the new or changed scripts |
| S3 | Play Solo with `Enabled = false` | No voice card or chip and no `[Voice…]` output; the game plays as before. With API access on: change two settings, leave and rejoin, and both are kept; `SettingsJson` still holds every earlier key; Reset still resets camera and audio. |
| S4 | Play Solo with `Enabled = true` (Studio has no voice device) | No errors. The card shows "Checking your voice settings…", then "Connecting to voice…", "Roblox's standard voice is on here." or "Not on your account…". No VOICE rows in Settings. In the lobby the Player has `VoiceRole = "Open"`, `VoiceHold = ""` and `SettingsLoaded = true`; during the solo practice round, `VoiceRole = "Contender"`. |
| S5 | Set `workspace:SetAttribute("DevFailSettingsLoad", true)` in Edit mode, then Play Solo | `SettingsLoaded = false`, `VoiceHold = "NotLoaded"` and `VoiceOn = false`, and still false 60 s later (no time limit). Remove the attribute afterwards. |
| S6 | Test › Clients and Servers, 2 players; start a round | (a) When A dies, A's `VoiceRole` turns `Bench` before the KillFeed shows the cannon; B stays `Contender`. (b) A presses SPECTATE within 4 s; after A respawns on the Tor, A's `Spectating` is still true and the server's `ReplicationFocus` for A is still B's root. (c) At round end everyone is `Open` and `Spectating` is false. |
| S7 | Settings › Reset with `voiceOn = 0` set (Enabled = true) | `voiceOn` is still 0 after Reset; the other settings reset |

### In a published private test copy (two or more voice-enabled 13+ accounts in one server; three is better, one on a phone)

Use `ClientGraph = "Custom"` and `Spectators.StandsBus = true` for these runs, unless a line says otherwise.

| # | Check | Pass when |
|---|---|---|
| P1 | Both join | Both see PROXIMITY VOICE **ON**; the mic chip reads `VOICE · NEARBY` in the arena; each sees the other in "who's talking" while they talk |
| P2 | Distance, in a round | Clear at about 5 studs; clearly quieter by 30; faint by 80; silent by 95. On the Tor: clear to 15, faint by 100, silent by 115 |
| P3 | Walls (Custom) | Behind a cliff or the cabin the voice muffles within about half a second; bushes and tree crowns don't muffle |
| P4 | **Death switch** | From the cannon on, the living (A) hear nothing from the fallen (B), even standing at B's body; B, spectating A, hears A |
| P5 | **The stands** | B and C (both fallen) watch *different* contenders and hear each other at the same volume; A (alive) hears neither; B's chip reads `VOICE · THE STANDS · 1 WATCHING` |
| P6 | Spectator ears | B watching A hears A at full volume and hears other contenders as A would |
| P7 | **OFF stays OFF** | B turns voice OFF on the card: within a second A can't hear B and B hears nobody. B leaves and rejoins: still OFF. Settings › Reset: still OFF. B turns it ON: A hears B again. |
| P8 | Late joiner | C joins mid-round: contenders can't hear C; C hears players on the Tor |
| P9 | Our mute list | A mutes B in the VOICE panel: only A stops hearing B; the card says `PLAYERS · 1 MUTED ›`; UNMUTE restores it |
| P10 | Phone and logs | On a 3 GB Android phone in the arena with 2+ talkers, the frame rate matches voice-off (Developer Console). No `changed under us`, `Couldn't set` or `failed` voice warnings on the server or clients during the session |

### The safety gate (record each line for the arena voice **and** the stands' channel)

| # | Check | Pass when |
|---|---|---|
| G1 | Roblox's speaker-icon mute (A taps the icon over B) | A stops hearing B in both paths; unmuting restores it |
| G2 | Roblox's mute from the player list or menu | same as G1 |
| G3 | Block: from our BLOCK button, and from Roblox's menu | A and B can't hear each other in any path; the panel shows BLOCKED; unblocking restores it |
| G4 | Roblox's voice volume (the global slider and B's own slider) | Turning B down, or to zero, changes what A hears in both paths |
| G5 | Age groups: two accounts in different age groups that aren't Trusted Connections | They never hear each other in any path |
| G6 | Report (sanity check) | Roblox's menu › Report offers voice for B. Open the form, check it, and cancel: don't file a test report. |

**The rule.** If G1–G5 all pass, the public build uses `"Custom"` with the stands' channel. If any fails, it uses `"Default"` with the stands' channel off, and P1, P4 and P5 are re-run in that version.

## 9. Performance and limits for 24 players

- **Server.** It works only on events: a death, a phase change, a join or leave, a choice. Every 5 s it reads each device back (three properties and a list of at most 24 IDs) and writes only differences. A death rewrites at most 23 access lists.
- **Client, full version.** Each other voice user gets about 10 local audio objects: analyzer, fader, equalizer, emitter, an attachment and wires. That's about 230 for 23 voices, made on join or respawn.
  - Every frame: the ear and up to 23 attachment positions, any muffle fades, and at most 4 talking bars.
  - 10 times a second: up to 23 loudness reads. 5 times a second: at most 8 rays. Twice a second: housekeeping.
- **Client, safe version.** One analyzer per voice, plus curve writes when the profile changes.
- **Roblox's limits.** Voice servers hold up to 100 players [18]; ours hold 24. The streams are Roblox's own.

## 10. Additions for docs/GameDesign.md

- **§8 Services:**
  - VoiceService: `isEnabled`, `getRole`, `onEliminated`, `refresh`, `setAllies`, `changed`, `debugState`; children `Routing` (pure rules) and `VoiceServers` (phase 2);
  - `RoundService.isRoundRunning()`.
- **§8 Controllers:**
  - VoiceController: `isAvailable`, `isOn`, `setOn`, `hasOwnVolume`, `isMuted`, `setMuted`, `mutedCount`, `openPanel`, `closePanel`, `getTalkers`, `debugState`; children `Curves` and `Hud`;
  - `LobbyController.mountCard`.
- **§8 ServerStorage.Dev:** VoiceRoutingTest.
- **§9 Remotes, client to server:** `VoiceRequest(action: "SetVoice" | "Whisper" | "JoinVoiceServer" | "LeaveVoiceServer", value: boolean?)`.
- **§10 Attributes:**
  - GameState: `VoiceMode`;
  - Player: `VoiceRole`, `VoiceOn`, `VoiceHold`, `VoiceWhisper`, `VoiceAllies`, `Spectating`, `SettingsLoaded`;
  - workspace (Studio only): `DevFailSettingsLoad`;
  - the tag `VoiceZone` (attributes `VoiceProfile`, `VoiceRoom`);
  - settings: `voiceOn`, `voiceVolume`, `voiceTips`;
  - Lore: `Stands`.
- **DataService** in §8: settings are merged key by key when saved.
- **Manual steps:** section 5 of this document.

## 11. What changed after the review

The critic's notes arrived cut off after item 4. Items 5–7 below follow the verdict's one-line list of blocking problems.

| Critic item | Decision | What changed |
|---|---|---|
| 1. Safety rests on untested assumptions stated as facts | **Accepted, and taken further** | The safe version (`"Default"`, no stands' channel) is now the code default. The full version needs gate G1–G5 to pass. "Engine" is removed rather than patched. The safe version only ever makes Roblox's emitters quieter. Every version honours Roblox's block list and mute events. The claims in this document are qualified (section 4). |
| 2a. Tips wiped saved settings | **Accepted** | Settings saves send only the changed keys, and the server merges them. Keys not changed this session take the saved value. Tips wait until `SettingsLoaded` plus 2 s (stricter than "until SettingsJson exists", which is also set after a failed load). |
| 2b. Reset turned the mic on | **Accepted** | `voiceOn` has `keepOnReset` |
| 2c. Slow or failed loads fell back to ON | **Accepted** | DataService publishes `SettingsLoaded`. The server holds the player muted until it is true or they choose; the 20 s fallback is gone. The save merge also means a failed-load session can't erase a stored OFF. |
| 2d. OFF requests could be dropped | **Accepted** | OFF is never limited. Each action has its own limit, and over-limit requests are applied shortly instead of dropped. OFF cancels a waiting ON. The client mutes its own device at once and keeps it muted. The UI follows `VoiceOn` / `VoiceHold`, and the choice is resent after 2 s. (The push-to-talk sample is on the AudioDeviceInput page [6], not the voice chat guide.) |
| 2e. SetVoice sent from the SettingsJson handler | **Accepted** | Only `setOn` sends, from the card, the panel or the player's own move of the Settings row (`onPlayerChange`) |
| 3. Listener inside another player's Head | **Accepted, with a different mechanism** | The listener and every emitter of ours sit on Attachments of our own under `workspace.Terrain`, moved every frame and rebuilt if removed. New ones start parked far away, not at the world origin (the Spire). Each maintenance step, and the context handler, is guarded on its own. **Turned down:** `AudioListener.PositionType = Instance` / `PositionInstance`. It exists [8], but parenting to our own Attachment uses the long-documented parent rule [8][9] and fixes the bug equally, with no newer property to depend on. |
| 4. Respawn cleared the spectate state | **Accepted** (the server-side option) | PlayerService keeps the target, `ReplicationFocus` and `Spectating` across the respawn while the round is Active and the target is alive. "SpectateController: no change" is now true for that reason. *One nuance:* with `StreamOutBehavior` Default the arena streams out only under memory pressure, so "very likely" is mostly true on phones. The fix applies regardless. |
| 5. The 5 s backstop never read the devices | **Accepted** | Every pass reads `Muted`, `AccessType` and the list back and rewrites differences. Failed writes are retried and drift is logged. The backstop also re-finds devices and re-reads the saved choice. |
| 6. ApplyVoiceSettings changes live voice whatever `Enabled` says | **Accepted** | The live-place guard, `DefaultDistanceAttenuation = Legacy`, `RevertVoiceSettings.lua`, the rollout order (test copy first, then both switches in one live publish), and the warning in section 5 |
| 7. Nothing tested the routing rules | **Accepted** | The rules are moved into the pure `Routing` module. `ServerStorage.Dev.VoiceRoutingTest` runs 4,416 checks in Edit mode. `routing_model.py` was run on this PC: 2,176 switches, 0 failures. |

**Also changed in the lead review:**
- Only known `VoiceRequest` actions get rate-limit buckets.
- The child modules load with timeouts, so a missing file can't stall a loader.
- A Studio hook (`DevFailSettingsLoad`) lets S5 test the failed-load path.
- `make_patches.py` is retired; `make_diff.py` makes a patch that `--3way` can merge.
- The name scanner now knows the keyword `else`.

## Sources

1. VoiceChatService: https://create.roblox.com/docs/reference/engine/classes/VoiceChatService
2. AudioApiRollout: https://create.roblox.com/docs/reference/engine/enums/AudioApiRollout
3. VoiceChatDistanceAttenuationType: https://create.roblox.com/docs/reference/engine/enums/VoiceChatDistanceAttenuationType
4. Voice chat guide: https://create.roblox.com/docs/chat/voice-chat
5. Audio API beta announcement: https://devforum.roblox.com/t/new-audio-api-beta-elevate-sound-and-voice-in-your-experiences/2848873
6. AudioDeviceInput (and its push-to-talk sample): https://create.roblox.com/docs/reference/engine/classes/AudioDeviceInput
7. AudioDeviceInput, API listing (unofficial): https://robloxapi.github.io/ref/class/AudioDeviceInput.html
8. AudioListener: https://create.roblox.com/docs/reference/engine/classes/AudioListener ; ListenerPositionType: https://create.roblox.com/docs/reference/engine/enums/ListenerPositionType
9. AudioEmitter: https://create.roblox.com/docs/reference/engine/classes/AudioEmitter ; API listing (unofficial): https://robloxapi.github.io/ref/class/AudioEmitter.html
10. DistanceAttenuationMode: https://create.roblox.com/docs/reference/engine/enums/DistanceAttenuationMode
11. AudioAnalyzer: https://create.roblox.com/docs/reference/engine/classes/AudioAnalyzer
12. AudioRecorder: https://create.roblox.com/docs/reference/engine/classes/AudioRecorder
13. StarterGui (GetCore and SetCore): https://create.roblox.com/docs/reference/engine/classes/StarterGui
14. Wire, AudioFader, AudioDeviceOutput: https://create.roblox.com/docs/reference/engine/classes/Wire , https://create.roblox.com/docs/reference/engine/classes/AudioFader , https://create.roblox.com/docs/reference/engine/classes/AudioDeviceOutput
15. Acoustic simulation, full release: https://devforum.roblox.com/t/full-release-acoustic-simulation-emit-audio-with-presence/4307121
16. Player and character destroy behaviour: https://devforum.roblox.com/t/new-player-and-character-destroy-behavior-enabled-by-default/3161577
17. Instance streaming: https://create.roblox.com/docs/workspace/streaming
18. Voice in servers of up to 100: https://devforum.roblox.com/t/voice-chat-is-now-supported-in-servers-of-up-to-100-users/4534031
19. Age checks for chat and links: https://devforum.roblox.com/t/age-checks-to-access-chat-studio-team-create-and-links-on-roblox/4079702 ; https://about.roblox.com/newsroom/2026/01/roblox-age-checks-required-to-chat ; https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
20. Content maturity: https://create.roblox.com/docs/production/promotion/content-maturity
21. Turning on voice (Help): https://en.help.roblox.com/hc/en-us/articles/34506487801364-How-do-I-turn-on-Voice-Chat
22. Voice FAQ (Help): https://en.help.roblox.com/hc/en-us/articles/4405807645972-Voice-FAQ ; experience controls: https://devforum.roblox.com/t/get-ready-for-updated-experience-controls/3163001
23. Staying safe in voice, recordings (Help): https://en.help.roblox.com/hc/articles/5704050147604
24. Testing voice: https://devforum.roblox.com/t/give-us-the-ability-to-better-test-voice-chat-api/3176821 ; https://create.roblox.com/docs/studio/testing-modes ; https://devforum.roblox.com/t/test-voice-chat-in-studio/2441552
25. Matchmaking (private and reserved servers are filtered out): https://create.roblox.com/docs/matchmaking ; default weights: https://create.roblox.com/docs/matchmaking/scoring ; signals: https://create.roblox.com/docs/matchmaking/attributes-and-signals ; customizing: https://create.roblox.com/docs/matchmaking/customize-matchmaking
26. Reserved servers: https://create.roblox.com/docs/projects/teleport-private-servers ; TeleportOptions: https://create.roblox.com/docs/reference/engine/classes/TeleportOptions
27. Chat groups API: https://devforum.roblox.com/t/new-chat-apis-teleport-users-who-can-chat-together/4337233
28. Voice-only servers, community practice: https://devforum.roblox.com/t/is-it-possible-to-make-dedicated-voice-chat-only-servers-using-teleportservice/2022494
29. The speaker icon can't be hidden (community): https://devforum.roblox.com/t/hide-roblox-voice-chat-icon-above-characters-heads/3432685 ; https://devforum.roblox.com/t/allow-spacial-voice-ui-to-be-hiddenconfigured/1618628
30. Voice suspensions (community report): https://devforum.roblox.com/t/voice-chat-suspensions-heavily-impede-gameplay/3898247
