# Game modes, progression and character skills

> Pillar file for the [Roadmap](../Roadmap.md) · key `modes-progression` · written by the modes designer, lightly edited by the lead designer so names match across pillars. Phase numbers inside this file are the pillar's own; the Roadmap's phases are the build order.

**Lead notes (where the Roadmap reconciles this pillar with the others)**

- **Roadmap phases.** This pillar's Phase 1 ("The Round Report") is Roadmap Phase 5, its Phase 2 is Phase 8, its Phase 3 is Phase 9 and its Phase 4 is Phase 10. Story wiring starts with Chapter One in Phase 7.
- **One premium name:** "Premium Arena" is now **the Wardens' Gauntlet** (the Economy pillar's name), opened by the Gauntlet Pass.
- **One profile:** the store is `Profiles_v2` (the Economy pillar's name), owned by an extended `DataService`; there is no separate `ProfileService`.
- **One Archive:** the Story pillar's lore records and these rule-twist Games form one list, and the Story pillar sets their years and Laureates. "The Silent Games" is now the Story pillar's **Silent Writ**. A Jubilee's announced twist is its **Writ**, and "the Long Dark" is now **Late Dawn**, shared with the Arena Edicts.
- **Provinces:** the lore has eight. Home Provinces launch with these five and their 15 Talents; Glasswater, Quarrymoor and Loomhallow join in a later Season.
- **Lobby:** the pavilions are shared with the store. One plan: NE the Armoury, SE the Outfitter, SW the Archive, NW the Gate. The MODES panel stays the one-tap route.
- **Aligned with the Story pillar:** the character examples now use its cast (Maren Holt unlocks during Arc I).
- **Lead review (IP and fairness):** the Spire's restock is **the Offering** (was the Feast), the death signal is **the Knell**, and the Archive entry the Iron Harvest is **the Bare Spire**. The 25th Games' Writ is the Dusk Writ, and the flood Games are the 68th. Achievements that need the Gauntlet Pass pay no XP, Province XP or Gold, and Endless ladders count only characters and signature abilities unlocked by play.

---

Scope: all of checklist group "8. Game modes and progression" (8 items) and five items of "3. Character and skills". Names follow the glossary. Where a note is referenced it is quoted first, then given our name.

## 1. Where we are today

I read this in the live place (read-only) and checked it against the build agents' reports. There is **one mode, one place and one server loop**.

| Area | Status | Evidence |
|---|---|---|
| Standard round loop | Built | `RoundService`: Lobby → Intermission → Countdown → Active → Ending. `Config.Round`: MinPlayers 2, MaxContenders 24, Intermission 25 s, Countdown 10 s, MaxRoundTime 900 s, Ending 10 s |
| Arena schedule | Built | `ArenaService`: the two-day clock, the Offering at 590 s, the border from 600 to 830 s, and a Roll Call at each dusk |
| Launch plates | Built | 24 Parts in `Workspace.Arena.Plinths` (r 52, 15° apart). `LaunchController` raises them out of their tubes |
| Persistence | Built (3 counters) | `DataService`: DataStore `PlayerStats_v1` holds Wins, TotalKills, RoundsPlayed and Settings. `increment` rejects every other key. Saves are additive deltas through UpdateAsync |
| Lobby UI | Built | `LobbyController`: status pill, record card (Wins/Kills/Rounds), how-to-play, settings, spectate. There is no mode, profile or shop UI |
| Modes, matchmaking, teleports, parties | Not started | No `TeleportService`, `MemoryStoreService`, `MessagingService` or `MatchmakingService` in any script. There are no other places |
| Monetisation hooks | Not started | No `MarketplaceService`, `ProcessReceipt`, game pass or `PolicyService` code |
| XP, levels, currency, unlocks | Not started | No matches anywhere. `Theme.Colors.Gold` is only a UI colour |
| Achievements, dailies, seasons, badges, leaderboards | Not started | No `BadgeService`, `OrderedDataStore`, achievement, daily or season code |
| Provinces, Talents, abilities, characters | Not started | No matches. Gameplay reads only global `Config` and `ItemDefs` values, with no per-player modifiers |

### 1.1 Standard, exactly as it runs today

| Phase (`GameState.Phase`) | Live length | What happens |
|---|---|---|
| Lobby | until 2 players are waiting (1 in Studio) | The lobby island at (2600, 160, 0), on the same server as the arena. Third person, movement only. Status pill "WAITING FOR PLAYERS 1 / 2", record card, how-to-play, settings, and SPECTATE while a round runs |
| Intermission | 25 s | "NEXT ROUND" banner. Drops back to Lobby if fewer than 2 are waiting |
| Countdown | 10 s | Up to 24 lobby players are shuffled, spread evenly over the 24 launch plates and frozen facing the Spire. Loot is populated. The plates rise from their tubes on a shared timeline (delay 0.8 s, rise 3.4 s, depth 10). The countdown reads "STAY ON YOUR PLATE · THE ARENA OPENS IN N" |
| Active | up to 900 s | Start horn. Day 1 from 07:24. Dusk falls at 285–345 s, with Roll Call 1 at clock 18:33 (≈333 s). Then a 2.5-minute night and the dawn of day 2 at 495–555 s. The border warning comes at 570 s. The Offering is at 590 s: a warning 45 s before, Tier-3 crates fall at the Spire, and `ArenaEvent = "Feast"` for 30 s. The border shrinks from r 640 to r 35 between 600 and 830 s (4 damage/s outside, 10/s once closed). Roll Call 2 comes at ≈827 s, then the final night runs to 900 s. Hunger and thirst drain throughout, with regeneration and fall and void deaths |
| Ending | 10 s | Victory announcement and the RoundSummary table (placement, kills). Then everyone in the arena goes back to the lobby and the loot is cleared |

**Win rule.** The last contender alive wins. At 900 s there is a winner only if exactly one is alive. Otherwise the survivors share 1st place, the screen says "TIME'S UP" and nobody gets a win.

**Death.** The cannon fires (the Knell replaces it in Roadmap Phase 1), the kill feed updates and the victim sees a "#7 OF 24" card. Their items scatter, they return to the lobby after 4 s and they can spectate. Leaving counts as an elimination ("left the arena"), with kill credit to an attacker who hit them in the last 15 s.

**Joining and practice.** Players who join mid-round wait in the lobby. Practice mode only happens when a single contender starts a round. Live servers need 2 players, so it is effectively Studio-only.

**Stats.** RoundsPlayed counts at the start horn and TotalKills at each kill. Wins counts at Ending, except in practice and walkovers (a round under 15 s with no kill).

**What's missing.** No rewards beyond those three numbers, no matchmaking beyond Roblox's default server fill, no parties and no teleports. The rounds-players report says the loop was proven in sandbox simulations but "Not playtested" live.

### 1.2 What the code means for this pillar

- **Config is global, and clients read it directly.** `HUDController` builds "THE FEAST IN / THE BORDER MOVES IN" from `Config.Events.FeastTime` and `Config.Border.ShrinkStartTime` (lines 824–825). `RoundService`, `ArenaService`, `DayCycle`, `LaunchController` and `PlayerService` hold `Config.Round` references. A few values are copied into locals when the module loads (`PlayerService` MAX_HEALTH, `FallenSnapshots` MAX_SNAPSHOTS = 40, `CharacterVisuals` POSE_RANGE = 150). Modes need a replicated ruleset, not hand edits to Config.
- **The plate code doesn't care how many plates there are.** `RoundService.findPlinths` takes any number of `Plinth*` children sorted by name, spreads contenders evenly when there are fewer than plates, and caps the count at `MaxContenders`. `LaunchController` animates whatever is in `Arena.Plinths`. So 48 plates need data, not new logic.
- **DataService saves additive deltas.** That is right for counters, but it can't safely hold unlock sets, a wallet or a receipt ledger. Progression needs a session-locked profile, and so do teleports between servers.
- **The biggest retention gap in Standard: a mid-round joiner waits in the lobby until the round ends,** up to about 15 minutes, with spectating as the only thing to do. The mode plan fixes this with a matchmaking signal and real things to do in the lobby.
- **Progression can listen to signals that already exist:** `PlayerService.died(victim, killer, cause)`, `RoundService.roundStarting / roundStarted / roundEnded / phaseChanged`, and `InventoryService.changed / equippedChanged`. Missing, and small to add: crate opened, item used, hit landed, Roll Call survived.

## 2. Design principles

1. **The arena stays fair.** Power is never sold and never grinds upwards. Competitive modes get only small horizontal sidegrades. Bigger powers live only in PvE (Endless, Story) or private games.
2. **One rules engine, many modes.** A mode is a data preset over the existing round. Most new modes reuse the classic arena and the start place.
3. **Keep players together.** Add variety inside Standard servers first (the Archive vote). Party PvE uses instant reserved servers. Cross-server queues are only for the Jubilee and premium maps.
4. **Respect players' time.** No appointment pressure: Daily Trials bank up, there are no streaks, nothing expires mid-Season and every timer is accurate. Roblox's guidance asks creators to avoid pushy or urgent messages with minors, and the Moderate label that the combat plan recommends admits 9–15-year-olds (Roblox Select) once the game passes Roblox's all-ages evaluation.
5. **Look and feel.** The lobby island does the job diegetically (pavilions, notice boards, Province banners, a Laureate statue). The UI is premium and minimal on the `Theme` tokens. Reward moments are short and skippable.
6. **Original IP.** This applies everywhere, including lore that the Story pillar writes for Archive entries and Jubilee Writs (see Risks).

## 3. The modes

### 3.1 At a glance

| The note | Our mode | Contenders | Where it runs | How you get there | Phase | Size |
|---|---|---|---|---|---|---|
| "Standard Hunger Games · Traditional survival competition." | **Standard** | 24 (2 to start) | start place, public servers | join the experience | built; polish P1–P2 | M |
| "Historical Games · Play through different canonical Games." | **Archive Games** | 24 | Standard servers (vote); reserved servers (Archive Book) | Intermission vote / queue | P2 / P3 | L |
| "Endless Arena · Survive escalating Gamemaker interventions." | **Endless Arena** | 1–6, co-op | start place, reserved server | Endless pavilion, instant | P3 | L |
| "Second Quarter Quell · 48-tribute special edition." | **The Jubilee Games** | 48 | Jubilee place, reserved servers | scheduled queue | P3 | XL |
| "Private Games · Custom rules and private matches." | **Private Games** | 1–24 | start place, Roblox private servers | the experience page's Servers tab | P2 | M |
| "PREMIUM GAMEMODE" / "Premium Arena · Additional maps, experiences and challenges." | **The Wardens' Gauntlet** | varies | premium places, reserved servers | the Gate pavilion (Gauntlet Pass) | P3 | XL |
| "Story Mode · Character-driven campaigns." / "Alternative Timeline · Change established historical outcomes." | **Story campaigns, alternative timelines** | 1–3 | story places / reserved servers | Archive pavilion → chapter | P4 | M (this pillar's hooks) |

### 3.2 Standard: keep it the everyday mode

| Change | Phase | Size |
|---|---|---|
| Becomes the `Standard` preset in `Shared.Modes`, holding today's numbers exactly. A golden sandbox test proves the 900 s timeline is unchanged | P1 | S |
| Pays progression: XP, Province XP, Mastery, Trials and achievements (section 5) | P1–P2 | (section 5) |
| **Matchmaking signal.** The server publishes `MatchmakingService:SetServerAttribute("SecondsToRound", n)`: 0 in Lobby/Intermission, otherwise an estimate from the phase clock and AliveCount. A custom server signal makes joiners prefer servers about to start. Roblox's Friends, Occupancy and Latency signals stay. This attacks the 15-minute wait | P2 | S |
| **Server size 26**: 24 contenders plus 2 slots that Roblox's server-fill setting keeps for friends. `RoundService` picks first the players who sat out the last round | P2 | S |
| **Talents on**, one slot (5.4) | P2 | L |
| **Archive vote** in Intermission (3.3) | P2 | M |
| **While you wait**, the lobby pavilions offer Endless solo (instant), the Archive Book and Story, while the pill keeps showing "NEXT ROUND IN 2:10" | P3 | S |
| Warden events from the Arena events pillar ("EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES") slot into ArenaService's schedule. This pillar only needs each event tagged with a tier, so Endless and Archive entries can reuse it | Arena events pillar | – |

### 3.3 Archive Games

"Historical Games · Play through different canonical Games" and "Historical Games completion" become **Archive Games**: past Games of our own lore, written by the Story pillar. Each entry is a rules preset over the classic arena, stored as data in `Shared.Modes.Archive` with these fields:

- name, year, blurb and Laureate (Story pillar)
- map (Classic)
- rule deltas over Config and ItemDefs loot weights
- an optional Warden event schedule (Arena events pillar)
- three laurels: Played, Top 5, Won

**The first six entries.** Years are placeholders. All but The Hunt reuse systems that exist today.

| Entry | Twist | Rules it touches | Extra work |
|---|---|---|---|
| The Drought Games | Rivers and the lake can't be drunk (sips hurt). Bottles are twice as common. Thirst drains 25% faster | `Config.Survival`, loot weights | a flag in InventoryService's Drink handler |
| The Long Night | The round starts at dusk and stays night. One Roll Call, at dawn | `DaySchedule`, `RollCallClockTime` | a night-look check by the look-dev owner |
| The Bare Spire | The Spire starts empty. Weapons are spread over Tier-1/2 markers. The Offering is the only Tier-3 | per-tier loot tables, Spire zone off until the Offering | a LootService override hook |
| The Silent Writ (50th) | No Knell, kill feed, alive counter or Roll Call names: you never know who is left | announce and HUD flags | flags in HUDController and NotificationController |
| The Closing Ring | The border moves from 180 s. The round is 8 minutes | `Config.Border`, `MaxRoundTime`, compressed `DaySchedule` | none |
| The Hunt | Splices hunt from the first night | Warden event schedule | the Arena events pillar's creatures |

*Lead note (Roadmap): one Archive. The Story pillar's lore records (the First Tithe, the Dusk Writ, the Silent Writ, the Flood Games, the 86th) and these rule-twist Games form one list, and the Story pillar sets their years and Laureates.*

**How players reach them.**

- **Weekly featured entry, inside Standard servers (P2).** In Intermission, if at least 4 players are waiting, a 15-second vote appears: "STANDARD / ARCHIVE: THE DROUGHT GAMES". It uses GameState `VoteOptions` and `VoteEndsAt` and a `ModeVote` remote. A tie goes to Standard, and a server never plays two Archive rounds in a row. The countdown names the entry and the HUD shows a small "ARCHIVE · THE DROUGHT GAMES" chip. LiveConfig picks each week's entry.
- **The Archive Book (P3).** The Archive pavilion lists every entry with its lore, its Laureate and your laurels. "Play this entry" queues for a 24-contender reserved server, which starts with 12 or more after 60 s.

**Completion.** All three laurels earn the entry's launch-plate skin. A win earns that year's Laureate as a character (5.6). Laurels also count toward achievements and Season challenges.

**Alternative timelines** add "Games that never happened" entries (3.8).

### 3.4 Endless Arena

"Endless Arena · Survive escalating Gamemaker interventions", with the raw note "EVERY COUPLE OF MINUTES A NEW CHALLENGE ARISES - ESCAPE LAVA RAIN ETC WILD DOGS MUTATED ANIMALS ETC", becomes **Endless Arena**: you and up to five friends against the Wardens, with no rival contenders.

| | |
|---|---|
| Players | 1–6, co-op, no PvP |
| Server | a reserved server of the start place with `Mode = "Endless"`. It uses the classic arena, so no new place |
| Loop | The party launches from the plates. A Warden event arrives every 120 s (about 90 s of event, 30 s of calm). Tier = 1 + floor((wave − 1) / 3). From wave 10 two events overlap; from wave 15 there is no calm. The border holds at r 400 so the party stays together. The Spire restocks every 5 waves (the Offering). Day and night keep turning, one day per 8 waves, and each dusk's Roll Call shows the party's fallen |
| Boons | After each wave survived, every living player picks 1 of 3 Endless-only, run-scoped Boons. Examples: +15 max health, bow draw −20%, Splice damage −20%, hunger −30%, healing +30%, stamina regen +30%. They are free and random, so they are not a paid random item |
| Fallen teammates | Come back at the next Offering if anyone is still alive. This needs a late-spawn path in PlayerService |
| End and score | The run ends when everyone is down. Score = waves survived, then time. Weekly ladders for Solo and Party (OrderedDataStore keyed by week). Ladder runs count only characters and signature abilities unlocked by play. |
| Rewards | 50 XP per wave, about Standard's XP per minute. Endless achievements and Trials. Province XP at 50% |
| Never | Paid revives, continues or Boons |
| Later | Nightmare Endless (the Wardens' Gauntlet): starts at tier 3, with its own ladder |
| Depends on | The Arena events pillar's Warden event library: at least 6 events across 3 tiers, each with a telegraph and a duration |

### 3.5 The Jubilee Games (48 contenders)

The note "Second Quarter Quell · 48-tribute special edition" becomes **the Jubilee Games**: our lore's special edition, held every 25 years, with 48 contenders. The expanded plan suggests making it "the foundational game experience".

**Recommendation.** Keep the 24-contender Standard as the everyday mode. It fills at low player counts and the arena is tuned for 24. Run the Jubilee as an event: Jubilee weekends at first, then always on once the hub regularly has several hundred players online. A 48-contender queue that doesn't fill is worse than no queue.

| | Standard today | The Jubilee |
|---|---|---|
| Place | start place | **a Jubilee place** in the same universe, reachable by teleport only, MaxPlayers 48 |
| Contenders | 24 | 48. It starts at 40 or more after 60 s of queueing, or 32 or more after 120 s. RoundService already spreads contenders evenly over the plates |
| Play radius (border start) | 640 | **760**: 1.41× the area, which gives each contender 37.8k studs² against 53.6k today. Deliberately busier, because it's a spectacle |
| Mountains / boundary / terrain | 680 / 712 / 920 | 800 / 832 / 1,040 |
| Plaza (flat disc) | r 62 | **r 110** |
| Launch plates | 24 at r 52, 15° apart (13.6 studs) | **48 at r 100, 7.5° apart (13.1 studs)**. One ring, so every plate has the same run to the Spire loot: about 40 studs against about 18 today |
| Spire loot | zone r 34: 8 crates, 10 ground items. Offering refill radius 90 | zone r 60: 14 crates, 18 ground items. Refill radius 95, inside the ring. Every other loot zone gets 50% more markers |
| Round | 900 s | **1,200 s**: Standard's day schedule × 4/3. Roll Call 1 at ≈444 s, a 200 s night, the Offering at ≈785 s, the border from 800 to ≈1,105 s down to r 45, Roll Call 2 at ≈1,103 s |
| Jubilee Writ | – | One announced rule change (the Jubilee's Writ) per Jubilee, from a list that only touches rules: Double Offering (≈400 s and ≈785 s), Empty Spire (no Spire loot until the Offering), Late Dawn (night twice as long), the Early Border |
| Roll Call | one bust per fallen, in sequence | **Grouped**: on a day with more than 8 fallen, busts come four at a time (≈4.75 s per group). The show stays under ~70 s and the 2D name list stays complete |

**How it's built.** World art makes a Jubilee variant of `ArenaLayout`: horizontal positions scaled by 760/640 ≈ 1.19, `PlazaRadius` 110, `PlinthCount` 48, `PlinthRingRadius` 100, and scaled `LootZones`. The re-runnable `TerrainGen` and `Populate` builders turn it into the Jubilee place. Then the `Jubilee` preset in `Shared.Modes` sets MaxContenders 48, MaxRoundTime 1200, and the DaySchedule, Border and Events. RoundService, LaunchController and LootService already work from these numbers.

**Fallback** if the scaled map slips: copy the classic place, flatten the plaza to r 110 and carve 48 tubes at r 100. That's denser (26.8k studs² each) but can ship in days, not weeks.

**Performance budget.** These are the code paths that strain at 48:

| Risk at 48 | Where | Fix |
|---|---|---|
| Every character within 150 studs is posed each frame, which at the start is almost the whole plate ring | `CharacterVisuals` POSE_RANGE = 150 | pose only the nearest 12; beyond 60 studs update at 15 Hz |
| Up to 47 avatar snapshots replicate to every client, and the cap is 40 | `FallenSnapshots` MAX_SNAPSHOTS = 40 | 48 in the Jubilee preset; strip layered clothing beyond a part budget; clients drop their local copy once the point cloud is baked |
| The Roll Call takes at least 4.15 s per fallen: a 30-fallen night would last ≈2.5 min, the whole night | `DayCycle.recapTimeline`, `FallenRecapController` | grouped mode (above) |
| Dust, whir and clunk on 48 plates | `LaunchController` | effects on the nearest 8 plates only |
| Kill-feed bursts in the opening seconds | `HUDController` | coalesce bursts ("3 contenders fell") |
| Too many projectiles in flight | `ProjectileService` | cap in-flight shots (e.g., 64) |

**Targets.** At least 30 fps on a mid-range phone and 60 fps on a mid PC at the launch, with server heartbeat at 55 Hz or better. Measure first with a 48-dummy load harness in a Studio server (`DummyBuilder` rigs walking scripted paths), then run a live test with 30 or more players before the first Jubilee weekend.

**Rewards.** The same XP per minute as Standard (a win adds 400). Jubilee achievements, a Jubilee plate skin for a top-10 finish, and the "Jubilee Laureate" title for a win.

### 3.6 Private Games

"Private Games · Custom rules and private matches" becomes **Private Games**: Roblox private servers of the start place, with a host panel.

**Platform setup.**

- Turn on private servers in the Creator Dashboard (Audience → Access Settings), paid monthly in Robux. The Economy pillar sets the price.
- Since 24 September 2026, Roblox Plus includes one free private server per game; servers bought at our price are unaffected. Roblox pays creators up to 100 Robux a month per Plus subscriber whose own playtime in that server reaches 60 cumulative minutes in the billing cycle.
- Paid access to the whole game can't be combined with private servers, so the base game stays free.
- Some under-13 players can't join private servers because of parental controls. Private Games must never be the only way to reach any content.

**How the server knows.** The host is `game.PrivateServerOwnerId`, plus any co-hosts they appoint. `ModeService` sees `PrivateServerId ~= ""` and `PrivateServerOwnerId ~= 0` and sets `Mode = "Private"`.

**Presets:**

- Standard
- Practice: 1 player with training dummies (today they spawn in Studio only, in `CombatService`)
- any Archive entry the host holds a laurel in
- Endless (co-op)

**Toggles** map onto existing Config:

| Toggle | Config it sets |
|---|---|
| Contenders 2–24 | `MaxContenders` |
| Players needed to start (1 allowed) | `MinPlayers` |
| Round length 8/15/20/30 min | `MaxRoundTime`, scaled `DaySchedule` |
| Day/night: normal, always day, long night | `DaySchedule` |
| Border on/off, start, speed, final radius, damage | `Config.Border` |
| The Offering on/off, time | `Config.Events` |
| Survival drain ×0.5–×2, regen on/off | `Config.Survival` |
| Fall damage on/off | `Config.Movement.FallDamage` |
| Loot scarce/standard/rich | `GroundSpawnChance`, `CrateItemsMin/Max` |
| Starting kit (none, knife, bow + 10 arrows, random Tier-2) | given through `InventoryService.give` at the horn |
| Talents on/off | (Talents) |
| Training dummies | `PracticeDummies` |
| Warden events on/off, frequency, which ones | once the Arena events pillar ships them |

**Behaviour.**

- Changes apply from the next round.
- A host can save up to 5 presets in their profile.
- Preset names are fixed labels, so there is no free text to filter.
- **No progression at all**: no XP, Gold, Province XP, Mastery, Trials, Wins or ladders. Only a few "Host" achievements. This closes the door on win trading and alt farming.
- Later (P4): "Launch on the Jubilee map" teleports the private group into a reserved server of the Jubilee place.

### 3.7 The Wardens' Gauntlet (premium mode)

"PREMIUM GAMEMODE" and "Premium Arena · Additional maps, experiences and challenges … The premium mode should ideally offer additional experiences rather than exclusive competitive advantages" become **the Wardens' Gauntlet** (the Economy pillar's name): one Game Pass, the Gauntlet Pass.

**A one-time Game Pass.** The Economy pillar sets the price. The server checks `MarketplaceService:UserOwnsGamePassAsync` on join, caches the result in the profile and grants instantly on `PromptGamePassPurchaseFinished`. It is not a subscription: Robux subscriptions must cost at least 49 Robux a month and deliver their benefits for the whole term, and a one-time pass avoids a recurring charge on a young audience.

**Contents, in build order:**

1. **The Warden's Chair** (party of 3–12, in a reserved server of the start place). One pass owner directs the arena from above with a recharging budget. They can trigger telegraphed Warden events in zones, open or seal areas, and drop supply capsules, while their friends play the round as contenders. This makes the notes' vision playable: "the arena … should feel like a controlled spectacle … the Gamemakers intervene" becomes the Wardens intervening. The director can't target a single contender. Rewards are titles and cosmetics only. Achievements that need the pass (the Warden's Chair, premium maps, Nightmare Endless) pay no XP, Province XP or Gold, so the pass never speeds up Talents.
2. **Premium maps.** New arenas, each a place world art builds (for example a winter or a coastal arena), played on Standard rules from a Gauntlet queue. A party can enter when at least one member owns the pass ("bring up to 3 friends"), so a paywall never splits friends.
3. **Nightmare Endless.** Endless from tier 3, with its own ladder.

**Guarantees.** Identical XP and Gold rates. No exclusive Talents, weapons or stat items. No premium-only ladder positions in free modes.

### 3.8 Story campaigns and alternative timelines (unlocks and rewards only)

The Story pillar designs the arcs. This pillar defines when they open and what they pay. The raw notes "STORY MODE OPTION _ PLAYABLE CHARACCHTERS ETC", "DIFFERENT ARCS - KILL SNOW ETC DIFF OPTIONS" and "UNLOCK DIFF ARCS" become **Story campaigns**: original characters (Oss Reed, the reluctant hunter; Maren Holt, the Laureate turned mentor; Ines Calder-Voss, the Citadel insider; Teo Strand, the favourite: Story pillar §5), plus **alternative timelines** where you change history, up to the Chancellor's fall.

| | Opens when | Rewards |
|---|---|---|
| Prologue | level 1, optional (it doubles as a tutorial) | XP, a starter title |
| Arc 1 | level 3 | First-clear XP per chapter (about a Standard round's worth per 10 minutes). Gold for finishing the arc. The arc's protagonist as a character (5.6), the arc's outfit, a title and a badge |
| Later arcs | when the previous arc's finale is done; some also need a laurel in the Archive entry the arc is set in | the same pattern, plus lore entries in the Archive Book |
| Alternative timelines | when the canonical arc they branch from is finished, so players know the history before they change it | An alternate-history Archive entry ("the Games that never happened", playable from the Archive Book), an alternate outfit and a timeline badge |

- Branch choices live in `profile.story.flags`, and checkpoints save per chapter.
- Chapters run in reserved servers (solo or co-op for 1–3) of story places or the start place. `ModeService` resolves `Mode = "Story"` with a chapter id from the match ticket.
- Replays award Mastery and achievements but no more XP, so chapters can't be farmed.
- Whether any arc is paid content is the user's decision (see open questions).

## 4. From the lobby to a mode

### 4.1 The island as the hub

The lobby already has four Pavilions, two NoticeBoards (the art kit's board has a SurfaceGui face), eight Banners, a Dais, a central fire and benches, all in `Workspace.Lobby.Decor`, built by `ServerStorage.WorldGen.Populate.Lobby`. Give each of them a job:

| Lobby piece | Becomes |
|---|---|
| Pavilion 1 | **The Archive**: the Archive Book, story arcs and timelines |
| Pavilion 2 | **Endless Arena**: start solo or with your party; the weekly ladder |
| Pavilion 3 | **The Jubilee Hall**: the Jubilee queue and schedule; event notices |
| Pavilion 4 | **The Wardens' Gauntlet and Private Games**: the pass ("View pass"), the Warden's Chair, and the host panel inside private servers |
| The Dais | **The reigning Laureate**: this server's last Standard winner as a bronze statue. It's a FallenSnapshots-style avatar capture with a metal material |
| NoticeBoards | Daily Trials and the Season board (SurfaceGui) |
| Banners | **Province standings**, each in its Province's colours |
| Central fire | where a new player chooses a home Province |

*Lead note (Roadmap): the pavilions are shared with the Economy pillar's store. One plan: NE the Armoury, SE the Outfitter, SW the Archive (story chapters and Archive Games), NW the Gate (Endless Arena, the Jubilee Games, the Wardens' Gauntlet, Private Games). The MODES panel stays the one-tap route on phones and gamepads.*

Walking into a pavilion opens its card, through a ProximityPrompt or a zone. The same cards are one tap away in a MODES panel (`LobbyController`) for phones and gamepads. Standard needs no trip, because you're already in it.

### 4.2 Places and servers

| Place | Server type | Modes |
|---|---|---|
| Start place (120572716460286): island + classic arena | public | Standard, the Archive vote |
| | private (Roblox private servers) | Private Games |
| | reserved (by teleport, GUID `ReservedServerId`) | Endless, Archive Book matches, the Warden's Chair, story chapters on the classic arena |
| Jubilee place | reserved, MaxPlayers 48 | the Jubilee Games |
| Premium map places | reserved | premium maps |
| Story places | reserved | story chapters that need other scenes |

All places share the universe's DataStores, badges and memory stores. They run one codebase, through Packages or the repo export pipeline, with a build stamp checked when a server starts. New places are teleport-only.

### 4.3 Queues, parties and teleports

- **Standard.** Roblox matchmaking, plus the custom `SecondsToRound` signal. Roblox Party members (`Player.PartyId`) join together.
- **Instant modes** (Endless, the Warden's Chair, story chapters). The hub server writes a match ticket into a MemoryStore hash map: `Matches/<guid>` = mode, variant, roster and rules. Then it calls `TeleportService:TeleportAsync(placeId, partyPlayers, options)` with `options.ReservedServerId = guid`. That GUID-based call is the current method; `ReserveServerAsync` access codes are legacy. The reserved server is created by the first teleport.
- **Queued modes** (the Jubilee, Archive Book, premium maps). `MatchService` runs in every hub server:
  - It adds a ticket, for a whole party of up to 4, to `MemoryStoreSortedMap("Queue_<mode>")`, with a 120 s expiry that a heartbeat refreshes.
  - One server holds a 10 s lease in `MemoryStoreHashMap("Leases")`. Every 2 s it forms matches from the available tickets (first in, first out, whole parties only), writes `Matches/<guid>` and announces it on MessagingService.
  - Each hub server teleports its own ticket holders. Because messages are best-effort, servers also poll their tickets.
  - Quotas are ample: memory is 64 KB + 1.2 KB per user, and requests are 1,000 + 120 per minute per concurrent user.
- **You can queue while you play.** Queued players keep playing Standard. A ticket counts as available only while its players are in the lobby, not alive in the arena, so nobody is pulled out mid-fight. The pill reads "JUBILEE QUEUE · 31 / 48".
- **Arrival.** `ModeService` reads `Matches/<game.PrivateServerId>`, which equals the GUID. Teleport data is never trusted for anything that matters.
- **Return.** At Ending, "BACK TO THE ISLAND" (or an automatic return after 20 s) sends the party to the start place's public servers in one `TeleportAsync` call. "PLAY AGAIN" queues again; Endless restarts in place.
- **Failure.** Every teleport runs in a pcall with up to 5 retries and a 15 s back-off on Flooded. `TeleportInitFailed` puts the ticket back at the front of the queue. A custom teleport screen (`SetTeleportGui`) shows the mode card. TeleportAsync works in Studio Test and Team Test, so all of this can be tested locally.

### 4.4 What a server does when it starts (`ModeService`)

1. **Resolve the mode.** Public → Standard. `PrivateServerOwnerId ~= 0` → Private. Reserved (`PrivateServerId ~= ""` with owner 0) → read the match ticket.
2. **Publish it.** Set `GameState.Mode`, `ModeVariant` and `RulesJson` before any phase starts.
3. **Apply the rules.** `Shared.Rules` runs on the server and on every client. It overlays the mode's deltas onto the Config tables in place, from `RulesJson`, and keeps a copy of the defaults, so all code that reads `Config.X.Y` when it runs keeps working. Values copied into locals at load (`FallenSnapshots` MAX_SNAPSHOTS, `PlayerService` MAX_HEALTH, …) move to reads at use time wherever a mode changes them. New code uses `Rules.get`.
4. **Handle per-round changes.** The Archive vote and host edits apply at Countdown, before `LootService.populate`. `ArenaService` publishes the round's event times (`FeastAt`, `BorderShrinkAt`), so `HUDController` stops reading `Config.Events` directly. Instant modes skip Lobby and Intermission and go to Countdown once the roster has arrived (or after 20 s).

## 5. Progression

### 5.1 Profile v2 (shared infrastructure; built here first)

- **Storage.** A new DataStore, `Profiles_v2`, keyed `u_<UserId>` and session-locked. Use the open-source ProfileStore module or an in-house `UpdateAsync` lock that can take over a stale lock. Locking is required once players teleport between servers. Unlock sets, a wallet and a receipt ledger also can't be saved as additive deltas.
- **Schema.** `stats` (Wins, TotalKills, RoundsPlayed and new counters), `settings`, `level` {xp, level}, `province` {home, changes, ranks}, `talent` {equipped}, `mastery`, `characters` {unlocked, equipped}, `achievements` {done, progress}, `trials` {slots, lastRefillDay, rerollDay}, `season` {id, xp, claimed}, `archive` (laurels per entry), `endless` {best}, `story` {chapters, flags}, `presets` (Private Games), `passes` (ownership cache). `wallet` and `receipts` belong to the Economy pillar: `ProcessReceipt` writes the `PurchaseId` in the same save that grants the product, and returns `PurchaseGranted` only after that save succeeds.
- **Migration.** The first load copies Wins, TotalKills, RoundsPlayed and Settings from `PlayerStats_v1`. The v1 key is kept read-only as a backup. Deltas that old servers write during the rollout are reconciled once. Retroactive achievements are granted from these stats.
- **Facade.** `DataService.increment / get / setSettings` and the `Wins`, `TotalKills`, `RoundsPlayed` and `SettingsJson` attributes keep working, so `RoundService`, `PlayerService`, `LobbyController` and `SettingsController` don't change.
- **Replication and erasure.** A compact `ProfileSync` remote sends the profile on load and on change. Nametag and UI values go out as attributes (`Level`, `Province`, `Talent`, `Title`). All data stays under UserId keys so erasure requests can be honoured.

### 5.2 Account level

"Account levels" becomes **Level** (1–50 in Seasons 0 and 1, raised later).

XP for a Standard round:

| Source | XP |
|---|---|
| In the round at the start horn | 50 |
| Time alive | 2 per 10 s (up to 180) |
| Placement | top 10 +40 · top 5 +80 · top 3 +120 · win +250 |
| Eliminations | +25 each; the first 6 count |
| Each Roll Call survived | +20 |
| Crates opened | +2 each; the first 10 count |
| A Daily Trial / an achievement | 150–400 / 100–500 |

- **A typical round pays 150–350 XP.**
- **AFK guard.** A player who doesn't move or act for 60 s in Active gets only the participation XP.
- **Curve.** XP to the next level = 400 + 40 × (level − 1). Level 10 takes ≈5,000 XP (about 25 rounds); level 50 takes ≈67,000.
- **Rewards.** Gold at every level (the Economy pillar sets amounts) and a cosmetic every 5 levels (a title, a banner frame or a plate-skin variant). Endless opens at level 2 and the Archive Book at level 3. **Levels never raise stats.**
- **Laureate.** Your first Standard win stamps the Laureate title on your profile and adds your name to the island's Hall of Laureates, a weekly wins board.

### 5.3 Home Province and Province rank

"District-specific backgrounds" and "District reputation" become **Home Province** and **Province rank**.

**Choosing.** A new player chooses a home Province at the central fire after their first round, or right away. The five Provinces are:

- Ironreach (iron and steel)
- Timberline (timber)
- Saltmarsh (fishing and salt)
- Graincross (grain)
- Coalbank (coal)

The Story pillar owns the final list, crests and lore, and the system works for any number of Provinces. *Lead note (Roadmap): the lore has eight Provinces; home Provinces launch with these five and their 15 Talents, and Glasswater, Quarrymoor and Loomhallow join in a later Season.* The choice screen shows each Province's banner, crest and industry vignette, its three Talents, and its outfit on the player's own avatar in a ViewportFrame.

**What the background does.** It puts the crest on your nametag and Showcase card, your Province's colours on your launch plate (from rank 4), its banner in the lobby, and its voice lines on your intro. On its own it gives no stat bonus.

**Switching.** The first switch within 24 hours is free; after that, one free switch per Season. Ranks are kept per Province.

**Province XP** is 50% of all your XP while that Province is home, plus **Province Deeds**: two per Province. Examples: Timberline, climb 150 studs of trunks in a round. Saltmarsh, swim 200 studs. Graincross, eat five foods. Ironreach, land eight melee hits. Coalbank, heal 60 health.

**Ranks 1–10** need 0 / 1,000 / 2,500 / 4,500 / 7,000 / 10,000 / 14,000 / 19,000 / 25,000 / 32,000 Province XP in total:

| Rank | Reward |
|---|---|
| 1 | crest, banner, nametag colour, **Talent A** |
| 2 | **Talent B** |
| 3 | **Talent C**, about 4–5 hours in, so every Talent is within reach early |
| 4 | Province launch-plate skin |
| 5 | outfit I |
| 6 | title |
| 7 | outfit II |
| 8 | Province victory celebration |
| 9 | Province trail |
| 10 | "Champion of <Province>" title and the full outfit |

**Province standings (each Season).** The table ranks Provinces by average Province XP per active member (3 or more rounds in the Season), so a small Province can win. The lobby banners show the table, and the winning Province's members get a crest flourish for the next Season. A weekly Spotlight doubles one Province's Deeds. Favour (the Arena events pillar's Favour, and the Story pillar's Showcase) could feed Province XP later.

### 5.4 Talents (specialisations)

"SKILLS", "Specialisations" and the plan's "District-based skill specialisations" become **Talents**: one per contender, from their home Province.

**Rules:**

1. **One slot** in competitive modes: Standard, Archive (unless an entry overrides it), the Jubilee and premium maps. Hosts can turn Talents off in Private Games. Endless adds Boons on top. Story uses the characters' own abilities instead.
2. **Sidegrades only.** Each upside is about 6–15% on one narrow axis and comes with a cost on another. No Talent touches loot rolls, border damage or information (no extra HUD and no seeing through walls).
3. **Unlocked by play.** All three of a Province's Talents are unlocked by Province rank 3, about 4–5 hours in. They are never sold and never boosted.
4. **Visible.** Players choose a Talent in the lobby, it locks at Countdown, and the death card shows the killer's Talent next to their weapon, so fairness can be seen.
5. **Balanced from data.** `AnalyticsService` custom events log Talent, placement and kills for every round. Any Talent whose win rate drifts more than 2 points from the average over 2,000 rounds gets retuned. LiveConfig can switch a Talent off without a publish.

**Starting values, to playtest:**

| Province | Rank | Talent | Upside | Cost | Hooks |
|---|---|---|---|---|---|
| Ironreach | 1 | Forgehand | melee cooldown −6% | thirst drains +6% | CombatService + CombatController cooldowns; PlayerService tick |
| Ironreach | 2 | Tempered | worn armour blocks 3 points more (vest 0.85→0.82, padded 0.72→0.69) | sprint stamina drain +6% | `InventoryService.getArmorMultiplier`; MovementController |
| Ironreach | 3 | Steady Arm | thrown knives and spears fly 10% faster | bow draw time +8% | CombatService throw speed; bow `drawTime` on server and client |
| Timberline | 1 | Treeline | climb speed +15%, climbing stamina −15% | swim speed −10% | MovementController (Climb, Swim) |
| Timberline | 2 | Woodsman | hatchet and machete damage +5% | bow damage −5% | CombatService |
| Timberline | 3 | Highwire | fall damage starts at 16 studs instead of 13 | hunger drains +6% | MovementService fall damage; PlayerService |
| Saltmarsh | 1 | Tidewalker | swim +15%; wading slows you 25% less | climb speed −10% | MovementController |
| Saltmarsh | 2 | Spearfisher | spear reach +0.5 stud, thrown spear damage +6% | knife, machete and sword damage −4% | CombatService |
| Saltmarsh | 3 | Brine | thirst drains −10% | hunger drains +8% | PlayerService |
| Graincross | 1 | Forager | food restores 20% more hunger | thirst drains +6% | InventoryService use; PlayerService |
| Graincross | 2 | Harvest Hands | eat and drink 20% faster | herbs, bandages and med kits take 10% longer | InventoryService server-timed use + InventoryController |
| Graincross | 3 | Long Rows | sprint stamina lasts 8% longer | climb speed −10% | MovementController |
| Coalbank | 1 | Pit Medic | healing items heal 15% more | food restores 10% less | InventoryService |
| Coalbank | 2 | Deep Lungs | natural regen 0.6 → 0.75 per s | regen waits 10 s after damage instead of 8 | PlayerService |
| Coalbank | 3 | Tunnel Sense | crouch speed 6.5 → 7.3 | slide distance −10% | MovementController |

**Implementation.**

- `Shared.Talents` holds the table.
- `TalentService` validates `EquipTalent`, locks the choice at `roundStarting` and sets the `Talent` player attribute.
- Server hooks multiply values in PlayerService, InventoryService, CombatService and MovementService.
- `MovementController` and `CombatController` read the attribute for the values the client drives (climb, swim, crouch, predicted cooldowns). MovementService's speed sanity check allows for them.
- Melee `staminaCost` is applied: `CombatController` (lines 452, 570) calls `MovementController.spendStamina` (line 2705).

### 5.5 Mastery (skill progression)

"Skill progression" and "Character-specific progression" become **Mastery** in the competitive modes. Mastery gives looks and titles, never power. Real power growth happens only where it can't hurt fairness: characters' skill trees in Story and Boons in Endless.

- **Tracks.** Blades (knife, machete, hatchet, sword), Mace, Spear, Bow, Throwing knives and Fists, plus Fieldcraft (crates, water, food) and Movement (climbing, swimming, sliding).
- **Points from use.** A hit is worth 1, an elimination 5, a headshot 3, and a bow hit or throw from 40 studs or more 3. Each track has 10 ranks, at 50 / 150 / 300 / 500 / 800 / 1,200 / 1,700 / 2,300 / 3,000 / 4,000 points.
- **Rewards:**
  - weapon finishes at ranks 3, 6 and 9 (blackened steel, etched, gilded). This is the user's "BUY VISUAL EFFECTS FOR ITEMS", earned instead of bought.
  - arrow trails at Bow 5 and Bow 10 ("TRAILS")
  - an elimination effect at rank 8. It must not be gory (ash, embers or leaves), because the game targets a Moderate label with no blood.
  - a title at rank 10 ("Bowyer").
- **Shared cosmetics.** Variants render through `ItemModels` and `ReplicatedStorage.Assets`. The Economy pillar owns the cosmetics catalogue, so earned and bought looks share one system.
- **Mastery seals** appear on the Showcase card (Story pillar).

### 5.6 Characters (unlocks and signature abilities)

"Character unlocks" and "For example, winning the Second Quarter Quell campaign could unlock Haymitch as a playable character in compatible modes" become **Characters**: original story characters. For example, Maren Holt, the Laureate turned mentor, unlocks during Arc I (Story pillar §5) and becomes playable in compatible modes.

**Ways to unlock a character:**

- finish a story arc (its protagonist)
- win an Archive entry (that year's Laureate)
- reach Province rank 10 (that Province's champion)
- reach the last free tier of a Season track (the Season's featured character's outfit)

**Where a character can be used:**

| Mode | Character | Signature ability | Talent | Boons |
|---|---|---|---|---|
| Standard, Jubilee, premium maps | looks only: an opt-in outfit over your own avatar, an intro card, a voice line on the plate | – | ✓ | – |
| Archive | looks only; a later "Laureates' Archive" entry gives everyone a character with abilities | per entry | ✓ unless overridden | – |
| Endless | ✓ | ✓ | ✓ | ✓ |
| Story | the chapter's character | ✓, and it grows through the story (a character skill tree) | – | – |
| Private | host toggle | host toggle | host toggle | in the Endless preset |

**Signature abilities.** "Character abilities" become **signature abilities**: one per character, designed with the Story pillar. An example is the reluctant hunter's Quiet Step: silent footsteps for 8 s. They work only in Story, Endless and private games where the host allows them.

**Own avatars by default.** Characters never replace players' own avatars by default, since the user wants the Roblox character to look "the same as a normal one". The outfit is opt-in and keeps the player's own body.

### 5.7 Achievements

"Achievement systems" and "Arena achievements" become **Achievements**. They run on one data-driven engine (`Shared.Objectives` + `ObjectivesService`) that also drives Daily Trials and Season challenges.

**Events** come from existing services, plus a few small new signals (marked new):

- `PlayerService.died`, extended with weapon, headshot and distance
- `RoundService.roundEnded`, extended with placements
- from `ArenaService` (new): Roll Call survived, the Offering, the border closed
- `LootService.crateOpened` (new)
- `InventoryService.used` (new)
- the Drink handler
- server-side Stance changes (Climb, Slide)
- `CombatService.hit` (new)
- biome visits, sampled every 2 s from `ArenaLayout.getBiome`

**Launch set of 20.** ★ marks the 6 Roblox badges; Roblox lets each game create 5 badges free per day.

| Achievement | Condition |
|---|---|
| Contender ★ | play a round |
| Laureate ★ | win a round |
| Night Watch | survive a Roll Call |
| At the Offering | be within 60 studs of the Spire at the Offering and live 30 s |
| River Drinker | drink from open water 10 times |
| Quartermaster | open 50 crates |
| Bowyer's Eye | land 10 bow headshots |
| Long Throw | eliminate a contender with a throw from 40+ studs |
| Treetop | climb 25 trees |
| Cartographer | visit 6 biomes in one round |
| Creek Cave | find the hidden healing cave |
| Ten Nights | survive 10 Roll Calls |
| Last Light | win at night |
| By a Thread | win with under 10 health |
| Quiet Laureate ★ | win with no eliminations |
| Arsenal | eliminate contenders with six different weapons |
| Steady Hand | finish top 5 ten times |
| Veteran ★ | play 100 rounds |
| Trialist | finish 10 Daily Trials |
| Rising ★ | reach level 10 |

**Later sets.** Phase 2 adds Province, Mastery and Archive sets. Phase 3 adds Endless, Jubilee and Season sets. Story arcs bring their own.

**Rewards.** XP, a little Gold and titles; achievements that need the Gauntlet Pass pay titles and cosmetics only (3.7). Badges go out through `BadgeService:AwardBadgeAsync` in a pcall, with a retry queue.

### 5.8 Daily Trials

"Daily objectives" becomes **Daily Trials**.

- **Three slots.** A new Trial arrives each day at 00:00 UTC if a slot is free, and up to three bank up. Nothing expires and there are no streaks: Roblox calls appointment mechanics unpopular, and we don't punish missed days.
- **One free reroll a day.** Rerolls are never sold.
- **A pool of about 25 templates** in three difficulties:
  - Easy: open 4 crates · eat 3 foods · drink from open water twice · survive 5 minutes · visit 3 biomes · climb a tree
  - Medium: top 10 twice · survive the first Roll Call · land 5 bow hits · 2 eliminations · swim 150 studs · open a Tier-3 crate · play an Archive Game
  - Hard: top 3 · win a round · reach the border's final circle · reach Endless wave 6 · a thrown elimination
- **Rewards.** 150 / 250 / 400 XP, plus Gold (the Economy pillar) and Season XP. Trials count in every mode except Private Games and the Warden's Chair.

### 5.9 Seasons

"Seasonal challenges" becomes **Seasons**: each Season is one year of the Games in our lore.

- **Length.** 8 weeks. Season 0 (the Preseason) starts with the first slice. Season 1 starts with Phase 3.
- **Season track.** 30 tiers of 1,000 Season XP each. All XP counts 1:1, plus Season challenges. Free rewards: Gold, titles, a plate skin, a banner, and a trail at tier 30. An optional paid track is the Economy pillar's call: cosmetics only, sold as one Developer Product per Season, because passes are permanent.
- **Season challenges.** Five a week. Each stays open until the Season ends.
- **Each Season ships:**
  - one new Archive entry
  - one or two Warden events (Arena events pillar)
  - a cosmetic set (Economy pillar)
  - a Province Spotlight rotation
  - at least one Jubilee weekend
  - ladder resets (wins, Endless)
  - Province standings and the next Season's crest flourish
  - that year's chronicle (Story pillar)
- **No false scarcity.** Say up front whether a Season reward comes back later. Timers are accurate and never restart.

### 5.10 What each mode awards

| Mode | XP | Province XP | Mastery | Trials / Season | Wins & ladders | Gold |
|---|---|---|---|---|---|---|
| Standard | ✓ | 50% | ✓ | ✓ | ✓ | ✓ |
| Archive | ✓ (+100 the first time per entry) | 50% | ✓ | ✓ | laurels | ✓ |
| Jubilee | ✓ (win +400) | 50% | ✓ | ✓ | Jubilee wins | ✓ |
| Endless | 50 per wave | 50% | ✓ | ✓ | Endless ladder | ✓ |
| Premium maps | ✓ (same rates) | 50% | ✓ | ✓ | ✓ | ✓ |
| The Warden's Chair | – | – | – | – | – | titles and cosmetics only |
| Private Games | – | – | – | – | – | Host achievements only |
| Story | first clear | – | ✓ | story Trials | – | when an arc is finished |

Studio practice rounds award nothing, as they already do for Wins.

## 6. Fairness and platform rules

- **Power is never sold.** No Talents, ranks, Boons, revives, continues, loot, or XP boosts that speed up Talent unlocks, whether for Robux or for Gold. Gold buys cosmetics (Economy pillar).
- **Equal XP per minute in every rewarded mode.** No premium multipliers.
- **No paid random items in this pillar.** Trial and level rewards are fixed, and Boons are free. If the Economy pillar adds any paid randomness, it must disclose the odds and respect `PolicyService` `ArePaidRandomItemsRestricted`.
- **No appointment pressure.** Trials bank up, there are no streaks, and Season challenges stay open until the Season ends. Copy is neutral ("View pass", not "GET IT NOW"), and countdowns are accurate and never restart. This follows Roblox's monetisation guidance for minors.
- **Private servers.** Under-13 players may be blocked by parental controls, so no content is reachable only through Private Games.
- **Moderate maturity label** (the combat plan's recommendation): no blood, non-gory elimination effects. Update the questionnaire whenever a mode adds hazards or creatures.
- **Data safety.** Profiles are session-locked. Receipts are idempotent: a PurchaseId ledger is written in the same save as the grant, and `PurchaseGranted` is returned only after that save. Rewards are server-authoritative, and every remote is validated with type and range checks plus `Net.rateLimit`.
- **No player free text in mode UIs** (presets and labels only). Anything players type is filtered through TextService.
- **IP lint.** The banned-terms check (Roadmap §7, built in Roadmap Phase 2) is a `ServerStorage.Dev` script, run with SyntaxCheck before each publish. It scans the string literals of every script (`Shared.Modes`, `Shared.Objectives`, `Shared.Provinces`, `Shared.Talents` and UIBuilder included), plus instance and asset names, the `ServerStorage.WorldGen` builders that write SurfaceGui text and the services that send Announce text. It matches whole words and flags a review list: cannon, feast, career, victor, quell, sponsor, trinket.

## 7. Build plan: modules, remotes, attributes

**New server services** (`ServerScriptService.Server.Services`, same Init/Start registry contract):

| Module | Job | Size |
|---|---|---|
| `DataService` (extended: profile v2) | session-locked v2 profile, migration, autosave, `ProfileSync`; keeps today's DataService API | M |
| `ModeService` | resolves the mode, `Shared.Rules` overlay, per-round rules, votes, win-condition and roster hooks for RoundService | M |
| `ProgressionService` | XP, levels, Province XP and ranks, Mastery, unlock grants, the round report | M |
| `ObjectivesService` | achievements, Daily Trials, Season challenges, BadgeService | M |
| `TalentService` | equip and lock Talents, per-player modifiers, telemetry | M (+ L of hooks) |
| `MatchService` | MemoryStore queues, leader lease, MessagingService, TeleportAsync, parties, return trips | L |
| `LiveConfig` | remote config: featured Archive, Jubilee window, Talent switches | S |
| `SeasonService` | Season windows, the track, standings, weekly ladders | M |
| `EndlessService` | waves, Boons, respawns, scoring | L |

**New shared data modules:** `Shared.Modes`, `Shared.Rules`, `Shared.Progression`, `Shared.Provinces`, `Shared.Talents`, `Shared.Objectives`, `Shared.Seasons`.

**New client controllers:** `ModesController` (pavilions, MODES panel, queue pill), `ProfileController`, `RoundReportController` (it takes over after NotificationController's RoundSummary), `ProvinceController` (the first choice), `HostPanelController`. `UIBuilder` builds the Modes, Profile, RoundReport and HostPanel ScreenGuis. `Populate.Lobby` adds the NoticeBoard SurfaceGuis, pavilion signage, the Dais statue anchor and the Province banners.

**Remotes** (added to `Net.Names` and the spec):

- Server → client: `ProfileSync`, `RoundReport` (`{ lines = { {label, xp} }, level, levelUps, provinceXp, trials, achievements, unlocks }`), `QueueState`.
- Client → server: `ChooseProvince(id)`, `EquipTalent(id)`, `EquipCharacter(id | false)`, `RerollTrial(slot)`, `ModeVote(option)`, `QueueJoin(mode, variant?)`, `QueueLeave()`, `HostRules(table)` (owner and co-hosts only), `ClaimSeasonTier(tier)`.

**Attributes:**

- GameState: `Mode`, `ModeVariant`, `RulesJson`, `VoteOptions`, `VoteEndsAt`, `FeastAt`, `BorderShrinkAt`.
- Player: `Level`, `Province`, `ProvinceRank`, `Talent`, `Title`, `Character`, `QueueMode`.

**Existing modules to extend:**

| Module | Change |
|---|---|
| `RoundService` | rules per round, the Intermission vote, sit-out priority, placements on `roundEnded`, ModeService win and roster hooks, skip-lobby for instant modes |
| `ArenaService` | rules for the clock, border and Offering; publish `FeastAt` / `BorderShrinkAt`; grouped Roll Call |
| `PlayerService` | `died` info (weapon, headshot, distance), per-player drain and regen multipliers, a late spawn into an active round |
| `InventoryService` / `LootService` | `used` / `crateOpened` signals, Talent multipliers, per-mode loot overrides |
| `CombatService` / `ProjectileService` | a `hit` signal, Talent multipliers |
| `MovementController` / `MovementService` | Talent modifiers, server-side Stance events, sanity limits |
| `HUDController` | read event times from GameState; mode chip |
| `LobbyController` | profile card instead of the record card; MODES button; queue pill |
| `NotificationController` | hand off from RoundSummary to the RoundReport |
| `CharacterVisuals`, `FallenSnapshots`, `DayCycle`, `FallenRecapController`, `LaunchController` | the Jubilee performance work (3.5) |

## 8. Phases

| Phase | Weeks (one strong dev + AI) | Contents | Checklist items it moves |
|---|---|---|---|
| **1: first slice** | ~3 | Profile v2; ModeService and Rules with the Standard preset; XP and levels; the round report; 20 achievements and 6 badges; Daily Trials; the profile panel. Stretch: Province choice | Standard, Achievements, Daily challenges, (Province backgrounds) |
| **2: identity and variety** | ~5–6 | Province ranks and Deeds; 15 Talents with telemetry; Mastery; the Archive vote with 5 entries and laurels; the Private Games host panel; LiveConfig; the matchmaking signal and sit-out priority; Preseason standings | Specialisations, Province backgrounds, Skill progression, Historical Games, Standard |
| **3: big modes and Season 1** | ~8–10 | MatchService (queues, parties, reserved servers); Endless Arena (once ≥6 Warden events exist); the Jubilee place and its first weekend; Season 1 (track, challenges, standings, ladders); the Gauntlet Pass and the Warden's Chair; the Archive Book queue | Premium game mode, Seasonal content, Historical Games |
| **4: story and long tail** | ongoing | Story unlock and reward wiring, characters and signature abilities, alternative timelines and what-if Archive entries, premium maps as world art delivers them, the Laureates' Archive, an always-on Jubilee if the player count allows, private Jubilees | Story campaigns, Alternative timelines, Character unlocks, Character abilities |

## 9. The first slice: "The Round Report" (Phase 1, about 3 weeks)

**Goal.** Every Standard round pays out visible, persistent progress, on the foundations every later mode needs. The slice carries no balance risk (no Talents yet) and adds no new places.

**What gets built:**

1. **Profile v2** (M): `Profiles_v2` with a session lock, migration from `PlayerStats_v1`, the DataService facade and `ProfileSync`.
2. **ModeService, Shared.Modes and Shared.Rules** (M): resolves Standard, Private and Studio. The Standard preset holds today's numbers. ArenaService publishes `FeastAt` and `BorderShrinkAt`, and HUDController reads them.
3. **ProgressionService** (M): the XP table, levels 1–50, the AFK guard, and Gold hooks stubbed for the Economy pillar.
4. **ObjectivesService** (M): 20 achievements (6 badges); Daily Trials with 3 banked slots, 25 templates and 1 reroll; the new signals in LootService, InventoryService, CombatService and ArenaService, and the richer `PlayerService.died`.
5. **UI** (M):
   - the RoundReport after the RoundSummary: XP lines tick in, level-up flourish in the ember accent, Trial ticks, new achievements. At most 6 s, skippable.
   - the lobby profile panel, which replaces the record card
   - Daily Trials on a lobby NoticeBoard
   - all built by UIBuilder, with layouts for phone, tablet, desktop and gamepad.

**Stretch** (otherwise the first task of Phase 2): choosing a home Province at the central fire, as identity only (nametag crest, banner, colours).

**Done when:**

- Existing Wins, TotalKills, RoundsPlayed and Settings survive migration on a test key.
- Two servers loading one profile never both write, and a rejoin never duplicates XP.
- A sandbox run of RoundService and ArenaService on the Standard preset reproduces today's timeline to the second: the Offering at 590 s, the border 600–830 s, Roll Calls at ≈333 and ≈827 s, the end at 900 s.
- In a 3-client Studio test every contender gets a correct RoundReport, levels, achievements and Trial progress persist across sessions, and badges award.
- Private servers and Studio practice rounds award nothing.
- The new UI passes the existing numeric layout harness on 8 phone and tablet sizes and 3 desktop sizes.

## 10. What this pillar needs from the others

- **Arena events:** a Warden event library (`startEvent(id, tier, opts)`, telegraphs, durations, tier tags). Endless, The Hunt, Jubilee Writs and the Warden's Chair use it.
- **Economy:** the Gold wallet and grant API inside Profile v2, the receipt ledger, the cosmetics catalogue (plate skins, weapon finishes, trails, outfits, celebrations), the Gauntlet Pass, private-server pricing and the optional Season track.
- **Story:** the Province list and crests, Archive entry texts and Laureates, characters and signature abilities, arcs, timelines, and each Season's chronicle.
- **Arena events and Story (Patrons, Favour, the Showcase):** the Showcase card (crest, Talent, character, Mastery seals), and Favour as a possible source of Province XP.
- **World:** the Jubilee `ArenaLayout` variant and generated place, premium maps, and lobby pavilion dressing.
- **Movement and rounds owners:** CharacterVisuals LOD, a grouped Roll Call, and live multi-client QA of the Standard loop. That QA is already in the Part 2 plan as qa:integration.

---

## Checklist items in this pillar

Status, size and Roadmap phase match the master checklist in the [Roadmap](../Roadmap.md).

### 48. “Standard Hunger Games”

- **Our name:** Standard (LAST STANDING, 24 contenders)
- **Status:** Built · **Size:** M · **Roadmap phase:** 5 → 8
- **Pillar phase:** Phase 1 (preset and rewards) → Phase 2 (matchmaking signal, sit-out priority, Talents, Archive vote)
- **From the notes:** "Standard Hunger Games · Traditional survival competition." We keep it as the everyday 24-contender mode. It becomes the 'Standard' preset and gains progression, a SecondsToRound matchmaking signal, a server size of 26 with sit-out priority, Talents and the Archive vote. The same mode list's Jubilee (XL, Phase 3), Endless Arena (L, Phase 3) and Private Games (M, Phase 2) are designed in this section but aren't separate checklist items.
- **Evidence:** RoundService runs Lobby→Intermission→Countdown→Active→Ending with Config.Round MinPlayers 2, MaxContenders 24, Intermission 25 s, Countdown 10 s, MaxRoundTime 900 s, Ending 10 s. ArenaService runs the two-day clock, the Offering at 590 s, the border 600–830 s (r 640→35) and Roll Calls at ≈333 s and ≈827 s. Workspace.Arena.Plinths holds 24 Parts. DataService PlayerStats_v1 stores Wins, TotalKills and RoundsPlayed. There is no mode layer, matchmaking or reward system. The rounds-players build report says the loop was proven in sandbox simulations but 'Not playtested' live.

### 49. “Premium game mode”

- **Our name:** The Wardens' Gauntlet (premium mode)
- **Status:** Not started · **Size:** XL · **Roadmap phase:** 9 → 10
- **Pillar phase:** Phase 3
- **From the notes:** Raw: "PREMIUM GAMEMODE". Plan: "Premium Arena · Additional maps, experiences and challenges" and "The premium mode should ideally offer additional experiences rather than exclusive competitive advantages." We make it one one-time Game Pass. It holds the Warden's Chair (a pass owner directs telegraphed Warden events for friends), premium arena maps (a party can enter if one member owns the pass) and Nightmare Endless. XP and Gold rates are identical and nothing gives power.
- **Evidence:** No MarketplaceService, game pass, ProcessReceipt or PolicyService code in any script (script_grep: 0 matches for each). The universe has a single place (120572716460286). LobbyController has no mode or shop UI.

### 50. “Story campaigns”

- **Our name:** Story campaigns (unlocks and rewards)
- **Status:** Not started · **Size:** M · **Roadmap phase:** 7 → 10
- **Pillar phase:** Phase 4 (on Profile v2 from Phase 1 and MatchService from Phase 3)
- **From the notes:** Raw: "STORY MODE OPTION _ PLAYABLE CHARACCHTERS ETC", "DIFFERENT ARCS - KILL SNOW ETC DIFF OPTIONS", "UNLOCK DIFF ARCS". Plan: "Story Mode · Character-driven campaigns." The Story pillar writes the original-character campaigns. This pillar wires unlocks and rewards. The prologue opens at level 1 and Arc 1 at level 3. Each finale opens the next arc, and some arcs also need an Archive laurel. Rewards are first-clear XP per chapter, Gold per arc, the protagonist as a character, plus an outfit, title and badge. Chapters run in reserved servers through ModeService.
- **Evidence:** No story, chapter or campaign code (script_grep 'ampaign' and 'hapter': 0 matches). No TeleportService or reserved servers. DataService can't hold any progress beyond 3 counters and Settings.

### 51. “Historical Games”

- **Our name:** Archive Games
- **Status:** Not started · **Size:** L · **Roadmap phase:** 8 → 9
- **Pillar phase:** Phase 2 (vote, 5 entries, laurels) → Phase 3 (Archive Book queue)
- **From the notes:** "Historical Games · Play through different canonical Games." and "Historical Games completion." These become Archive Games: past Games from our own lore as rules presets on the classic arena. A weekly featured entry comes up by Intermission vote inside Standard servers. The Archive Book gives each entry three laurels (Played · Top 5 · Won), and a win unlocks that year's Laureate. The first set is the Drought Games, the Long Night, the Bare Spire, the Silent Writ and the Closing Ring, with the Hunt once Splices exist.
- **Evidence:** There is no mode or ruleset layer. Config is global, and clients read it directly: HUDController lines 824–825 use Config.Events.FeastTime and Config.Border.ShrinkStartTime. RoundService has no vote or per-round rules hook. There is no lore data.

### 52. “Alternative timelines”

- **Our name:** Alternative timelines
- **Status:** Not started · **Size:** S · **Roadmap phase:** 10
- **Pillar phase:** Phase 4
- **From the notes:** "Alternative Timeline · Change established historical outcomes." and raw "KILL SNOW ETC DIFF OPTIONS". The Story pillar designs the alternative timelines, up to the Chancellor's fall. This pillar's part: a timeline opens once the canonical arc it branches from is finished, and branch choices are saved in profile.story.flags. Rewards are a 'Games that never happened' Archive entry, an alternate outfit and a timeline badge.
- **Evidence:** No story, branch or save-flag code. PlayerStats_v1 stores only Wins, TotalKills, RoundsPlayed and Settings.

### 53. “Achievements”

- **Our name:** Achievements
- **Status:** Not started · **Size:** M · **Roadmap phase:** 5
- **Pillar phase:** Phase 1 (first slice)
- **From the notes:** "Achievement systems." and "Arena achievements." These become Achievements on one data-driven engine (ObjectivesService + Shared.Objectives), shared with Daily Trials and Season challenges. 20 ship at launch, 6 of them Roblox badges. Contender, Laureate and Veteran are granted retroactively from v1 stats.
- **Evidence:** No BadgeService or achievement code (script_grep: 0 matches). DataService.increment rejects every key except Wins, TotalKills and RoundsPlayed. Hook signals that exist: PlayerService.died and RoundService.roundEnded. Missing: crate opened, item used, hit landed, Roll Call survived.

### 54. “Daily challenges”

- **Our name:** Daily Trials
- **Status:** Not started · **Size:** S · **Roadmap phase:** 5
- **Pillar phase:** Phase 1 (first slice)
- **From the notes:** "Daily objectives." / checklist "Daily challenges". These become Daily Trials: three slots, a new Trial each day, up to three banked. There are no streaks and nothing expires. One free reroll a day, never sold. Rewards are 150/250/400 XP plus Gold and Season XP.
- **Evidence:** No daily or objective code and no per-day state. DataService's PlayerStats_v1 holds 3 counters and Settings.

### 55. “Seasonal content”

- **Our name:** Seasons
- **Status:** Not started · **Size:** L · **Roadmap phase:** 9
- **Pillar phase:** Phase 3 (Season 1); the Preseason clock and standings come in Phase 2
- **From the notes:** "Seasonal challenges." / checklist "Seasonal content". These become 8-week Seasons, each one year of the Games in our lore. Each has a 30-tier free track (an optional paid cosmetic track is the Economy pillar's call) and weekly challenges that stay open until the Season ends. Each Season brings a new Archive entry, Warden events, a Jubilee weekend, Province standings and ladder resets.
- **Evidence:** No season, ladder, OrderedDataStore or leaderboard code (script_grep: 0 matches).

### 15. “Character abilities”

- **Our name:** Signature abilities (plus Endless Boons)
- **Status:** Not started · **Size:** L · **Roadmap phase:** 9 → 10
- **Pillar phase:** Phase 3 (Endless Boons) → Phase 4 (signature abilities with the story characters)
- **From the notes:** Raw: "SKILLS"; checklist "Character abilities". These become signature abilities of original characters, one each (e.g. the reluctant hunter's Quiet Step). They work only in Story, Endless and host-enabled Private Games. Endless also has run-only Boons. Competitive modes use Talents instead.
- **Evidence:** No ability or perk code: script_grep 'bilit' matches only unrelated Roblox Animate and visibility code. Movement, combat and survival read global Config values with no per-player modifiers (MovementController, CombatService, PlayerService).

### 16. “District-specific backgrounds”

- **Our name:** Home Province and Province rank
- **Status:** Not started · **Size:** M · **Roadmap phase:** 8
- **Pillar phase:** Phase 1 stretch (choice) → Phase 2 (ranks, Deeds, standings)
- **From the notes:** "District-specific backgrounds" and "District reputation." These become a home Province: Ironreach, Timberline, Saltmarsh, Graincross or Coalbank (the Story pillar sets the final list), chosen at the lobby's central fire. It gives a crest, colours, a banner, a plate skin, voice lines and an outfit. Province rank 1–10 comes from 50% of XP plus Province Deeds, and seasonal Province standings show on the lobby banners.
- **Evidence:** No Province data or identity choice anywhere (script_grep 'rovince': 0 matches). PlayerService loads each player's own avatar through GetHumanoidDescriptionFromUserIdAsync with normalised scales. The lobby has 8 Banner models and a CentralFire that could carry this.

### 17. “Skill progression”

- **Our name:** Mastery
- **Status:** Not started · **Size:** M · **Roadmap phase:** 8
- **Pillar phase:** Phase 2
- **From the notes:** "Skill progression" and "Character-specific progression." In competitive modes this becomes Mastery: 10 ranks per weapon family, fieldcraft and movement. Rewards are weapon finishes, trails, non-gory elimination effects and titles. Real power growth happens only in Story (character skill trees) and Endless (Boons).
- **Evidence:** No XP, level or mastery code. The only persistent progress is the 3 lifetime counters in PlayerStats_v1. ItemModels.build only knows the 'world' and 'view' variants, with no cosmetic finishes.

### 18. “Character unlocks”

- **Our name:** Characters
- **Status:** Not started · **Size:** M · **Roadmap phase:** 10
- **Pillar phase:** Phase 4 (the profile field is ready from Phase 1)
- **From the notes:** "Character unlocks" and "winning the Second Quarter Quell campaign could unlock Haymitch as a playable character in compatible modes". These become Characters: original story characters, e.g. Maren Holt, the Laureate turned mentor, unlocks during Arc I. Other ways to unlock one: win an Archive entry, reach Province rank 10, or reach the last free tier of a Season track. In Standard, the Jubilee and premium maps they are looks only (an opt-in outfit over your own avatar). They are fully playable, with signature abilities, in Story and Endless, and in Private Games if the host turns it on.
- **Evidence:** No character roster or unlock code. PlayerService always loads the player's own HumanoidDescription. The profile has no field for unlocks (DataService stores 3 counters and Settings).

### 19. “Specialisations”

- **Our name:** Talents
- **Status:** Not started · **Size:** L · **Roadmap phase:** 8
- **Pillar phase:** Phase 2
- **From the notes:** "Specialisations" and the plan's "District-based skill specialisations." These become Talents: one slot in competitive modes, three per home Province, 15 at launch (e.g. Treeline: climb +15% / swim −10%). All are unlocked by Province rank 3 (about 4–5 hours) and never sold. Win-rate telemetry applies a ±2-point retune rule, and LiveConfig can switch any Talent off.
- **Evidence:** No Talent or perk code (script_grep 'Talent': 0 matches). All tuning is global in Config (Movement, Survival, Combat) and ItemDefs. Melee staminaCost is applied: CombatController (lines 452, 570) calls MovementController.spendStamina (line 2705).

## Open questions

1. Which mode should be the everyday game? We recommend the 24-contender Standard, which fills at low player counts and is the size the arena is tuned for. Your expanded plan suggests the 48-contender Jubilee. We'd run the Jubilee as scheduled weekends until enough players are online. *(Roadmap: decision 4.)*
2. Talents in Standard: should every contender get one small sidegrade Talent (recommended: all unlocked within about 5 hours, never sold, and a 'no Talents' toggle in Private Games)? Or should Standard stay 'pure', with Talents only in Archive, Endless and Private Games? *(Roadmap: decision 7.)*
3. Should any story arcs or alternative timelines be paid content, for example part of the Gauntlet Pass, or should all story be earned by play? *(Roadmap: decision 6.)*
4. The Wardens' Gauntlet: a one-time Game Pass (recommended) or a monthly subscription? And which do we build first: the Warden's Chair party mode (cheaper, reuses the arena) or a second arena map? *(Roadmap: decision 5 (the Warden's Chair first).)*
5. Friends will team up in free-for-all modes, so how big can parties be? Our proposal is up to 4 in Standard and the Jubilee queue and up to 6 in Endless. The alternative is solo-only for the Jubilee.
6. Provinces: do we launch with the five named ones (Ironreach, Timberline, Saltmarsh, Graincross, Coalbank)? And how often can a player change home Province (proposed: one free change per Season)? *(Settled in part: these five at launch, the lore's other three later.)*
7. In competitive modes, may players wear an unlocked story character's outfit over their own avatar (opt-in, cosmetic only)? Or should those modes always show players' own Roblox avatars?
8. Season cadence: is 8 weeks per Season sustainable for your team, with each Season bringing one Archive entry, one or two Warden events and a Jubilee weekend?
9. When several contenders survive the 15-minute limit, do we keep 'TIME'S UP, nobody wins', or add a short sudden-death finale so every round crowns a Laureate?
10. Private Games: paid Roblox private servers only (Roblox Plus members get them free and Roblox still pays us), or also free code-based custom lobbies?
11. Level gates: should Endless open at level 2 and the Archive Book at level 3, or should everything be open from the first minute?

## Risks

- The player base splits across modes, and 48-contender queues never fill at launch numbers. Mitigation: Archive Games run as a vote inside Standard servers, Endless and story chapters are instant reserved servers, the Jubilee runs only as scheduled weekends with a 32-contender start floor, and LiveConfig can switch modes on and off without a publish.
- Talents or Province ranks get read as pay-to-win or a veteran advantage. Mitigation: all Talents unlock by Province rank 3 (about 4–5 hours) and are never sold or boosted. A ±2-point win-rate rule over 2,000 rounds triggers retuning, LiveConfig can switch any Talent off, the death card shows the killer's Talent, and hosts can turn Talents off in Private Games.
- Moving from additive stat deltas to session-locked profiles while players teleport between hub and reserved servers risks lost or duplicated progress and receipts. Mitigation: ProfileStore-style locking, a migration dry run on test keys, PlayerStats_v1 kept as a read-only backup, a PurchaseId ledger written in the same save as the grant, and DataStore version history for rollbacks.
- The mode-aware rules refactor could break the tuned Standard loop. Config is held by reference in RoundService, ArenaService, DayCycle, LaunchController and PlayerService, copied into locals in places (FallenSnapshots MAX_SNAPSHOTS, PlayerService MAX_HEALTH), and read directly on clients (HUDController lines 824–825). Mitigation: the Shared.Rules overlay keeps defaults, the Standard preset equals today's values, and the sandbox simulation suite the rounds agent used is re-run as a golden test.
- Jubilee performance on phones: 48 avatars at the plate ring, CharacterVisuals posing every character within 150 studs, up to 47 replicated FallenSnapshots (the cap is 40 today) and a sequential Roll Call of at least 4.15 s per fallen. Mitigation: LOD caps, a grouped Roll Call, effects only on the nearest plates, a 48-dummy load harness, and a live test with 30+ players before the first weekend. Fallback: the classic map with a 48-plate ring.
- The universe gains several places (start, Jubilee, premium maps, story), and their code can drift apart. Mitigation: share code through Packages or the repo export pipeline, check a build stamp when each server starts, and keep the place-specific ArenaLayout variants as data.
- This pillar depends on others: Warden events (Endless, the Hunt, the Warden's Chair, Jubilee Writs), story characters (character unlocks, signature abilities, Archive lore), the Economy pillar (Gold, cosmetics, passes) and world art (Jubilee map, premium maps). Mitigation: phases are ordered so each mode ships with what exists, Endless waits for at least 6 Warden events, and Gold rewards are stubbed and queued until the wallet exists.
- Daily and seasonal systems drift into appointment pressure or false scarcity for a 9–15 audience, or paid randomness slips in. Mitigation: Trials bank up with no streaks, Season challenges stay open until the Season ends, timers are accurate and never restart, copy is neutral ('View pass'), and there are no paid random items, continues or revives. The Moderate label is kept by avoiding blood and gory elimination effects and updating the questionnaire.
- IP drift in lore content: Archive years, Jubilee Writs or the mentor's backstory could mirror franchise specifics, such as a 48-contender special edition won by the mentor archetype. Mitigation: glossary review of every story-pillar text, and the banned-terms check (Roadmap §7) over every script's string literals and every instance and asset name before each publish.
- Players farm XP or trade wins in private servers or with friends, or farm while AFK. Mitigation: Private Games give no progression, the AFK guard limits idle players to participation XP, elimination and crate XP are capped per round, walkovers already don't count as Wins, and chapter replays give no XP.
- Each mode switch costs a teleport and a load of the large arena, and failed teleports strand players. Mitigation: a custom teleport screen, pcall with retries and back-off, TeleportInitFailed re-queues the ticket, Standard stays in the hub, and Endless and Archive reuse the start place.
- Scope: 13 items, several of them L or XL, could produce breadth without depth. Mitigation: phase gates, and a first slice limited to the foundations every later item needs (profile, rules engine, XP, objectives).
