# Two arenas: the Green Land, the Clock and the road into the Games

*Lead designer, 14 November 2026. This is the one design for both arenas and everything a player passes through before them. It is design only: nothing is built, nothing was committed or uploaded, Roblox Studio was not opened, and `src/` was only read (place version 199).*

*It answers the owner's final direction, in their words: "WATCH THE TRAILER FOR THE UPCOMING HUNGER GAMES AND MAKE THE FIRST MAP LIKE THAT", "AND MAKE THE TRAINS LOOK LIKE THEM TOO", "RECREATE IT ON BLENDR AND MAKE THAT THE FIRST MAP", "FROM NOW TAKE INSPIRATION FROM THE UPCOMNG MOVIE" and "make sure blendr recreates the map assets and game design with semi realistic colour tones". It also answers their correction after the five launch frames: "no this ius the same map the red room with the metal on top is just the transition room before you go to the survivakl game and it loads up to the room like the images i sent you when i said the second map i said it will be like the second map of the original hunger games movie where the map is a clock". The upcoming film is* The Hunger Games: Sunrise on the Reaping *(the 50th Games; in cinemas 20 November 2026).*

*It brings together the work of 14 November:*
- *the visual brief, [UpcomingFilm_Brief.md](UpcomingFilm_Brief.md);*
- *the first Blender pass of Map 1, Map 2, the launch rooms, and the train and station, with renders in `art/previews/Map1`, `art/previews/Map2`, `art/previews/Launch` and `art/previews/Train`;*
- *three working designs (Game 1, Game 2, and the pre-arena flow) and a technical plan, whose content is carried into this document, which replaces them;*
- *a critic's review with 17 required changes. Each one is applied or answered in "What changed after the review".*

**Still in force**
- **[ArenaV3.md](ArenaV3.md):**
  - the TerrainGen v3 core (§7.1);
  - the staged border (§6.5), with its 6.5 studs/s speed limit, and the 18-minute fallback (§6.6);
  - the Director's re-based slots (§6.7);
  - the data, streaming, density and memory budgets (§7.2–7.6).

  Its Vale layout, its mountain wall and its avoid list are superseded. The note at the top of ArenaV3.md says exactly what.
- **[ArtStyle.md](ArtStyle.md):** style A ("faceted realism") and all its rules, and the blender-art skill (`.claude/skills/blender-art/SKILL.md`).
- **[WeaponsAndObjectives.md](WeaponsAndObjectives.md):** the roster and its caps (§2), the acts and the goal line (§3), and onboarding (§4).
- **[arena-events.md](arena-events.md):** the rules every Gamemaker event follows (§2, §3, §5). One correction: its reading of Roblox's Community Standards ("no harming harmless animals") is stricter than Roblox's own rule, and §3.10 replaces it for hunting.
- **Rating:** 13+. No severing and no heavy gore.
- **IP:** the films' terms in documents only. In-game names are open, and no film imagery, logos or text goes into the game or the repo.

**How to read it**
- **Tags:**
  - **C**: confirmed in a trailer frame or still;
  - **L**: likely, from the book or reliable text;
  - **I**: invented by us, in the film's spirit;
  - **S**: from the owner's TRIBUTE spec.
- **Units.** 1 stud ≈ 0.28 m, and a tribute is 5.5 studs tall. A jog is 13 studs/s, a sprint 21 and a swim 8. Bearings are degrees clockwise from north (−Z), r is the distance from the map's centre, and y is up.
- **Words.** This document uses the films' words, with our system names in brackets where they differ:
  - tributes (contenders);
  - the horn (the film's Cornucopia, the code's Spire);
  - plinths (launch plates);
  - the Gamemakers (the Wardens, `WardenService`);
  - mutts (Splices);
  - the Feast (the Offering).

  On-screen text uses tokens such as `{HORN}` until you choose the in-game names.
- **Renders.** Every render named here is a Blender iteration with placeholder plants and flat colours. None of it is the game. A look is approved in game at 14:00 and 17:30 (ArtStyle rule 10), never from a render.

---

## Decisions

### What you told us

| Your direction | What it means here |
|---|---|
| Map 1 is "the green land" of *Sunrise on the Reaping*, made like the trailer | Game 1 on Map 1 (§3): the valley, the misty mountains, the plinth ring, the horn and the flower beds. It is everyone's first game. |
| Map 2 is "the second map of the original hunger games movie where the map is a clock", "recreated 3 x bigger" with "all the challenges in the movie and more" | Game 2 on Map 2 (§4): *Catching Fire*'s 12-sector clock arena. It opens after one round of Map 1. Its size is decision 1. |
| "the red room with the metal on top is just the transition room before you go to the survivakl game and it loads up to the room like the images i sent you" | One launch sequence, the same before both maps (§2): your red room under the metal net, then the hall of glass cases, then the rise on a long pole through the giant round hall. It is a transition, not a map, and it replaces the old grey room. |
| The rise as one semi-real shot with "circular motion" | One continuous shot: the camera circles you as your disc climbs the pole, and the circle ends behind your head as you rise into the arena (§2.4). |
| "AND MAKE THE TRAINS LOOK LIKE THEM TOO" | The film's station and train, with the seven cars of your TRIBUTE spec (§5.1–5.2) |
| A training room "like in the movies", where players "test diff kits and abilities and chests will have diff items based on such" | The Training Centre (§5.3): weapon stations, kits, one small knack each, and crates that lean towards your kit |
| "semi realistic colour tones", with every asset made in Blender | One measured colour translation for every set (§7), and every asset modelled by us (§8) |
| Climbing, hunting, gathering and shelter, the area your design direction "particularly emphasise[s]" | Natural interaction gets its own release, straight after Map 1 (§3.10, §10) |
| "The playable area should not shrink too quickly" | 15-minute rounds stay the default. An 18-minute switch is built and tested first (§3.14, §4.11). |
| 13+ for now; film-faithful places, accepting the IP risk | No blood and no severing. The films' terms appear in documents only, and in-game names stay open. |

### What we decided for you (defaults you can change)

- **Map 1 keeps a radius of 1,800 studs (about 1 km across).** The film's own valley fits that size (§3.2).
- **Map 1 is an open valley held in by a force field, not a crater with a wall.**
  - The first Blender pass read as a round crater.
  - Pass 2 replaces the ring wall and its terraces with natural slopes and separate peaks, and the arena's edge becomes a field all the way round (§3.3).
- **Map 1's heart matches your frame.** 48 plinths stand at r 150 round the horn, and 18 lens-shaped flower beds nearly fill the ring (§3.5).
- **Rigged flower beds go off when you step on them, and you can see them.**
  - Their metal daisies spark from the countdown.
  - Stepping onto a rigged bed lights a 3-second fuse (§3.11).
  - Decision 4 can hide them instead.
- **First rounds are simpler.** While most of a server is in its first three rounds, Game 1 runs an intro set: one creature and four hazards. Everything else unlocks with experience (§3.12).
- **Hunting is in, bloodless and quick.** We checked Roblox's rules first (§3.10).
- **Map 2 runs in its own teleport-only place, reached through a queue.**
  - If the queue hasn't filled after 90 s, you can go with whoever is queued, or practise alone (§4.15).
- **The unlock.** Your first Green Land round counts when your part in it ends: you fall, you win or the round ends. Practice rounds count (§4.15).
- **The launch** plays in full on your first launch of each session, and as an 18-second cut after that. Decision 3 can change this.
- **Kits are small leans, not classes.**
  - Tokens are earned only by playing in the beta.
  - Training never changes how many hits it takes to down anyone (§5.3).
- **The red rain on Map 2 is rust-coloured, not blood-red** (§4.5).
- **The build order follows your own priorities** (design direction §9):
  1. the arena and the launch;
  2. natural interaction;
  3. animals and Gamemaker events;
  4. the Training Centre;
  5. the Clock;
  6. the station and the train;
  7. tokens, last (§10).

### Waiting on you: five decisions

Each one has a default. We build the default unless you say otherwise.

1. **Map 2's size.**
   - Map 2 as rendered is your guide at 1×: R 2,600 studs, 1.46 km across, about twice Map 1's area.
   - It is also about 3× the lagoon that was really built for the film, which is why the brief called it "3× the film".
   - Three times your guide would be about 4.4 km across: R 7,770, 18.6× Map 1's area. At that size 24 players would rarely meet, and phones can't hold it.
   - **We recommend 1×, R 2,600.** If you still want it bigger, name the size. We will build a trial and come back with the largest radius that actually passes our budget audit and the 3 GB phone test, not an estimate.
2. **The horn's colours on Map 1.**
   - (a) White sails with muted plum and dull gold, which are the real set's colours, softened. In shade they read blue-grey, as in your frame. Inside: the cobalt blue and gold fans the second trailer shows. **Recommended.**
   - (b) Blue-grey and teal all over, as the trailer's colour grade shows it.
3. **The launch's length.**
   - The full 38-second shot (red room, glass cases and the rise) on your first launch of each session, then an 18-second cut on later rounds: the red room only as long as loading needs, then the rise. **Recommended.**
   - Or the full shot every round, which adds 28 s per round to today's 10-second countdown.
   - Or the cut every round.
4. **Rigged flower beds: visible or hidden.**
   - Visible: the live beds' metal daisies spark from the countdown, so you can read them from your plinth. **Recommended.**
   - Hidden: they show only when a fuse lights.
5. **The Training Centre becomes the place everyone waits between rounds.** You reach it through the station, and the Tor lobby is retired. **Recommended, from release R4.**

### Also open, but not blocking

- **In-game names or the films' names:** the horn or the Cornucopia, tributes, Gamemakers, mutts, the Feast, the two maps, the station, the kits, the tokens, and so on. Every name on screen is a token, so your answer is a one-line change.
- **The gore rating.**
  - We build for 13+.
  - Your TRIBUTE spec's blood and severing would need Roblox's age-verified 17+ rating.
  - It stays out of this plan until you decide whether you want a separate mode for it.
- **Tokens for Robux,** which your design direction suggests. The default is none in the beta. Later, if you want them, capped packs that only buy time towards the same cap.

The full list, with the default we are using for each, is in §12.

---

## In short (plain English)

- **One road into every Games.**
  - Your first session starts with a short train ride: about 40 s, and you can skip it.
  - The train pulls into the station, and a lift takes you up to the Training Centre, where everyone waits between rounds.
  - When a round is called you go through the launch and into the arena. When you fall, you're back in the Training Centre.
- **The launch is one shot, and it is the same before both maps.**
  1. You wait in your own red room under the metal net while your arena loads.
  2. A disc lifts you into your glass case in the ring of cases.
  3. It carries you up your long pole through the giant round hall while the camera circles you.
  4. A white-out, and your plinth rises in the meadow (Map 1), or your plate surfaces in the lagoon (Map 2).

  It takes 38 s the first time each session and 18 s after that.
- **Map 1, the green land, is the film's valley.** About 1 km across, it has:
  - a green meadow on a hillside shoulder;
  - dark conifer forest on the slopes;
  - limestone crags and misty peaks;
  - a turquoise lake under a mountain that is really a volcano;
  - at its heart, the film's opening shot: a white horn on a cream star-shaped platform, 48 plinths in a ring, and 18 flower beds radiating like a sun.
- **It is everyone's first game, so it teaches.**
  - The first rounds run one creature and four hazards, each with one tell and one counter:
    - rigged flower beds: step off;
    - foul water: read the bank;
    - the force field at the edge: don't touch it, and don't throw anything at it;
    - the night the mountain wakes: leave its slopes;
    - the red birds that dive at movement: stand still, or get under trees.
  - Squirrels, butterflies, fire in the gorse, poison mounds, tear gas, the spiral and the maze unlock as players gain rounds.
- **The valley is alive.** You can:
  - climb trees by their own trunks and limbs;
  - hunt rabbits and birds for food;
  - gather berries and watercress;
  - drink from streams and the dawn rain;
  - shelter under rock.
- **Map 2 is *Catching Fire*'s clock.**
  - A salt lagoon holds the horn on its island. Twelve rock spokes run out to a beach ring, and jungle cut into twelve wedges climbs to a force-field dome.
  - Each 75-second hour, one wedge turns deadly: lightning, red rain, fog, monkeys, jabberjays, the beast, the wave and insects, plus four of our own.
  - The island turns at sunset.
  - A dial shows the next sector a full hour ahead. The one rule: run against the clock.
  - It opens after your first Green Land round.
- **The train and the station look like the film's.**
  - Outside: dark lacquered bullet-nosed trains with glowing red lamps, a tall glass-and-steel hall with a gold sunburst, guards in white armour, and banners and posters of our own.
  - Inside: your seven cars in amber light, brass and burgundy.
- **The Training Centre is the film's gym.**
  - It has four weapon stations and a fitness corner.
  - Step onto a station's mat to try its weapons, and that becomes your kit. Your kit tilts one item in each crate you open towards it, and gives you one small knack.
  - Training earns tokens for five small ranks of Stamina and Strength. It never changes how many hits it takes to down anyone.
- **Colour is semi-real, and it is measured.**
  - Every set is checked against the film's frames within one band: softer than the film, never cartoonish and never colour-graded.
  - Bright colour only ever means loot, danger or a marker.
- **What happens next.**
  - Blender pass 2 fixes what the review found.
  - About 4 weeks after you say go, you can play Map 1 and the launch privately.
  - The Green Land goes public in week 5. The whole plan runs about 19 weeks.

---

## What changed after the review

A critic reviewed the first pass against your frames, the film's frames and the three designs, and asked for 17 changes. I checked each claim against the renders myself, and every visual claim held up. This table says what we did with each change.

| # | The critic asked for | What we did | Where |
|---|---|---|---|
| 1 | Map 1 reads as a crater: open the valley up, put green slopes behind the ring, make the crags bands, soften the cloud, and keep the far peaks visible past the streaming range | Applied | §3.3, §8.2 |
| 2 | Say plainly that Map 2 is the guide at 1×, and get your answer before more Map 2 work | Applied | Decision 1, §4.1 |
| 3 | Map 1's heart: lens-shaped beds, big pale petals, a flared horn, weapon racks, tribute stand-ins in renders, dense conifers on the slopes | Applied | §3.5, §8.2 |
| 4 | One measured colour band for every set | Applied, but measured per surface (ground, foliage, stone, sky) rather than as a whole-frame average | §7 |
| 5 | The launch: navy light, reds back to their sampled strength, the fine net, no light strips on the poles, a new end to the rise | Applied | §2.2, §2.4, §2.8 |
| 6 | The station and train: a narrow, tall hall, a radial fan of blades, cool daylight, a bullet nose, a finer upholstery pattern | Applied. The hall keeps the amber you described, carried in the bounce light and the gold rather than in a uniform wash. | §5.2 |
| 7 | Decorative flowers muted, so they can't be confused with rigged beds; the meadow in broad patches of three tints | Applied | §3.18, §7 |
| 8 | Game 1 asks too much of a first round: run an intro set, and make the beds go off when stepped on | Applied | §3.11–3.12 |
| 9 | The launch is too long: a short cut, a setting for the full shot, end the train ride for a call, measure loading on a phone | Applied, except that the "full launch every time" setting works only in practice rounds and private servers | §2.3, §5.1 |
| 10 | Natural interaction is missing from the ship order: add a phase, with week numbers | Applied | §3.10, §10 |
| 11 | Map 2: a varied jungle, sectors you can tell apart, a dark lava island, one horn design, varied relief | Applied | §4.16 |
| 12 | Engineering gaps: Map 2's jungle density, the island turn, animating the rise on each device, the memory hand-off | Applied. The island turns with nobody on it. | §4.6, §2.10, §9.5–9.6 |
| 13 | A Map 2 queue that might never fill | Applied, and extended: you can go with whoever is queued | §4.15 |
| 14 | One owner page with at most five decisions | Applied. Names and the gore rating stay as standing questions, because they were asked for in this brief. | Decisions, §12 |
| 15 | Pace: test the 18-minute fallback | Applied | §3.14, §4.11 |
| 16 | Label every render, and approve looks in game | Applied | How to read it, §13 |
| 17 | 13+: the red rain must not read as blood | Applied: rust by default | §4.5 |

**What we rejected, and why**
- **Whole-frame colour averages (part of #4).**
  - The brief's own rule takes the sky about 40% below the film's saturation.
  - A frame with a lot of sky would therefore fail by design, and a frame with a lot of meadow would pass while its sky was wrong.
  - So the band is measured per surface class instead.
- **A per-player "full launch every time" setting on live servers (part of #9).**
  - Every contender in a round shares one clock. If one player could choose the full shot, they could add 20 s to everyone's round.
  - The setting works in practice rounds and private servers, where it costs nobody else any time.
- **Carrying players round on the turning island (one option in #12).** Nobody rides it. The deck is cleared, then sealed while it turns (§4.6), which removes the physics risk instead of testing around it.
- **Two ideas from the earlier working papers, not from the critic:**
  - Game 1 suggested letting your kit bias Map 1's outer supply bags and runner's flags. We kept the simpler rule: only crates you open lean towards your kit, so the rush for the horn is the same bet for everyone.
  - The pre-arena paper wanted the pole hall's spoked ring widened to 220 studs. The Blender build already solves the same problem with an opening in the roof over each pole.

---

## 1. The road into the Games

```
 JOIN
  |-- first session? --yes--> THE TRAIN  (about 40 s; skip any time; ends early if a round is about to be called)
  |                               |
  no                              v
  +------------------------> THE STATION  (doors open; about 10 s to the lift)
                                  |
                                  v
       +--------------------> THE TRAINING CENTRE  (wait, train, pick a kit; the Clock gate)
       |                          |  the call
       |                          v
       |                    THE LAUNCH  (38 s the first time each session, 18 s after; one shot, one clock)
       |                    red room > tube > glass case > pole rise > white-out > plinth or plate
       |                          |
       |                          v
       +-- fall, or round ends -- THE ARENA  (Map 1; Map 2 in its own place once unlocked)
```

**How long it takes**

| You are | From joining to first control | From joining to the start signal |
|---|---|---|
| New and alone, once the train ships (R6) | About 5 s, on the train | About 1:40 if you walk straight through the launch doors; about 2:00 if you wait for the timer; about 0:56 if you skip the train |
| New and alone, before the train ships (R1–R5) | About 5 s | About 0:45 through the launch doors; about 1:05 if you wait |
| Returning and alone | About 5 s, at the station | About 0:55 through the launch doors; about 1:30 if you wait (today it's 1:05) |
| On a full server, between rounds | As above | The Intermission (25 s), plus the launch (18–38 s) |
| On a full server, while a round is running | As above | You train or spectate until it ends. The boards show the longest you might wait. |

- **The price of the train.** The owner asked for it, so the first session now takes about 35 s longer than today, and the skip gets it back.
- **How the wait is kept short.**
  - For a first-session player alone on a server, the practice timer is 25 s, counted from reaching the training floor.
  - The launch doors stand 15 studs from the lift.
  - Every launch after your first one in a session is the 18-second cut.
- **We watch it.** The funnel logs every step (§6.8), so if newcomers drop off on the train or in the red room, we'll see it.

**Where each space lives**
- **The start place** holds the hub (the Training Centre, the lift and the station), the train siding and Map 1.
  - The hub and the siding sit "backstage", about 10,000 studs west of the map's centre.
  - That is far outside both arenas and their streaming range.
- **The launch is not a place.** Each device builds its own copy at the call and throws it away after the arrival (§2.10).
- **The Clock place** holds Map 2 and a small waiting room for the fallen. The same code runs in both places (§6.1).

---

## 2. The launch: one sequence before both maps

### 2.1 What it is

In the owner's words, the red room "is just the transition room before you go to the survivakl game and it loads up to the room like the images i sent you". So there is one launch sequence. It plays before Map 1 and before Map 2, and it replaces the old grey room. Its three rooms are stacked as one vertical set and filmed as one shot:

1. **The red room, the transition room.**
   - Your own red room under a dark metal net, with red rails, a steel grate floor and a teal hexagonal frame over your disc, seen from above.
   - You wait here while your arena loads.
   - C: T1 @120.2 s, and the owner's frames `launch_1_red_room_net_a.png` and `_b.png`.
2. **The hall of glass cases.**
   - It "loads up" to a dim blue hall, where every tribute stands in a tall glass case in a ring.
   - C: T1 @125.9 s, and `launch_2_glass_cases.png`.
3. **The rise.**
   - Your disc carries you up a long metal pole through a giant dark round hall, with a huge spoked ring and light bars in the ceiling. Every tribute rises on their own pole.
   - The camera circles you as you go: the owner's "circular motion".
   - Then a white-out, and the arena.
   - C: T1 @124.7 s and @127.2 s, and `launch_3_pole_hall_wide.png` and `launch_3_pole_rise.png`.

### 2.2 The set, and what Blender pass 2 changes

The first pass is `art/blender/launch_rooms.py`. Its exports are three GLBs (2.1 MB in all) with a manifest, in `BlenderExports\Launch`.

| Room | As built in pass 1 | What pass 2 changes |
|---|---|---|
| **The red room** (`LaunchRedRoom`) | <ul><li>Oxblood walls, 30 × 24 × 20, with a concrete base course.</li><li>A roof of red panels with a square net on both faces.</li><li>A teal hexagonal frame of bolted square tube, 14 across the flats, over a dusty-rose lift disc.</li><li>A blue-grey steel deck with white stripes, black square-mesh grates over red-lit pits, a red rail round the disc, red lamp housings and an upper walkway.</li><li>9,572 triangles.</li></ul> | <ul><li>**The net, to the brief's spec:** 1.2-stud cells and 0.25-stud bars, set at 45° to the hex frame, with a slight sag. It can be an alpha-cut net texture on a sagging plane, or real bars under 4k triangles. Pass 1's net reads as a heavy cage of thick bars, square to the frame.</li><li>**The grates read black.** Red shows only in the floor openings, not as a glow under every grate.</li><li>**The figure in the shot is your own stand-in.** Pass 1 rendered a figure styled like the film's escort.</li></ul> |
| **The case hall** (`LaunchCaseBay` ×48, `LaunchCaseGallery` ×8, `LaunchRiserDisc` ×48) | <ul><li>48 cases, each 4.3 × 4.8 × 11, at r 110 facing the centre.</li><li>Oxblood posts, glass on three sides, a top light, and a dark-red disc.</li><li>A maroon wall unit with a white light panel between each pair of cases.</li><li>A curved walkway under a gantry of strip lights.</li></ul> | <ul><li>**Lit dim navy,** as in the film: cool blue-white keys and a navy ambient (brief §2.7). Pass 1 reads neutral charcoal, because the sampled blues went to grey.</li><li>**Reds back to their sampled strength:** the rails at about 0.53 saturation and the case discs at about 0.33. Pass 1 pushed them to 0.69 and 0.60, against the brief's own "10–20% less saturated" rule.</li></ul> |
| **The pole hall** (`LaunchPoleHallSegment` ×8, `LaunchPoleHallCrown`, `LaunchPole` ×48) | <ul><li>360 studs across, with a dark shell and a truss dome.</li><li>A spoked ring 194 across, with 48 spokes and a hub of 12 spots.</li><li>Light bars in rings at r 104–174, and an opening in the roof over each pole.</li><li>48 poles: 12-sided, 1 stud thick, with copper bands every 15 studs.</li></ul> | <ul><li>**No light strips on the poles.** The film's poles are dark rods, and its light bars are on the ceiling ring and the walls. Pass 1's dashed strips turn the hall into a curtain of light.</li><li>**Lit like the case hall:** navy and blue steel, with red accents.</li></ul> |
| **Budgets** | <ul><li>20k unique triangles; about 150k drawn when every case and pole is instanced.</li><li>Each room's colours packed into one small palette texture.</li></ul> | <ul><li>Unchanged.</li><li>In a 24-tribute round, the discs and poles of the empty cases are skipped.</li></ul> |

**The case ring matches the plinth ring.**
- Case *i* stands at the bearing of plinth *i*, so the tribute beside you in the cases is the one beside you at the horn.
- Map 1 has 48 plinths, and a 24-tribute round lights every second case.
- Map 2's 24 plates also use every second case.

### 2.3 Two cuts on one clock

**The rule.** `LaunchService` runs the **full shot** if any contender in the round hasn't launched yet in this session. Otherwise it runs the **short cut**. Everyone in a round sees the same cut, on the same clock, and everyone arrives together.

**The full shot: 38 s from the call to the start signal (34 s in practice)**

| Time from the call (s) | Stage | Length (s) |
|---|---|---|
| 0.0–0.4 | Fade to black on the training floor | 0.4 |
| 0.4–8.0 | **The red room:** you wait while the arena streams in | 7.6 at least (4.0 in practice) |
| 8.0–11.0 | **Up the teal tube** into your glass case | 3 |
| 11.0–15.0 | **The cases:** the camera pulls back through the glass and sweeps along the row | 4 |
| 15.0–24.0 | **The rise:** 120 studs up the pole in 9 s, while the camera circles 270° | 9 |
| 24.0–25.0 | **White-out.** The cut into the arena hides here. | 1 |
| 25.0–28.0 | **The arrival:** your plinth rises out of its tube (Map 1), or your plate surfaces (Map 2). The circle ends behind your head, facing the horn, and you're in first person at 28.0. | 3 |
| 28.0–38.0 | **On the plinth:** 10 down to 1, with the goal line | 10 |
| 38.0 | The start signal | — |

**The short cut: 18 s**

| Time from the call (s) | Stage | Length (s) |
|---|---|---|
| 0.0–0.4 | Fade | 0.4 |
| 0.4–3.0 | **The red room,** only as long as loading needs | 2.6 at least |
| 3.0–8.0 | **The rise:** a cut straight to your disc leaving the case, then 180° of the circle, ending on the low-angle frame | 5 |
| 8.0–9.0 | White-out | 1 |
| 9.0–12.0 | The arrival | 3 |
| 12.0–18.0 | On the plinth: 6 down to 1 | 6 |
| 18.0 | The start signal | — |

**Compared with today**
- Today's Countdown lasts 10 s.
- The full shot adds 28 s, but only for the first launch of a session.
- The short cut adds 8 s.

**The full-launch setting.** A player setting, "Full launch every time", is honoured only in practice rounds and private servers. On public servers the rule above decides, so one player can never add 20 s to everyone's round.

**Measured before we lock it.** Task T0 measures the real stream-in time on a 3 GB Android after moving from the hub. The red-room minimums (7.6 s and 2.6 s) are then set from that measurement.

### 2.4 The shot

| Stage | The camera | You | Around you |
|---|---|---|---|
| **Red room** | <ul><li>Straight down from just above the hex tube's mouth, about 15 studs above your head, so the hexagon frames the shot as in your frame.</li><li>A slow zoom, field of view 50 → 42 over 6 s.</li><li>If the wait runs on, a drift of 4° a second, so the loop never shows.</li></ul> | <ul><li>Your own avatar in the white launch cape, idling.</li><li>At 6 s you look up into the tube.</li></ul> | <ul><li>Oxblood walls under the net.</li><li>The steel deck, black grates, and red light in the floor openings.</li><li>The red rails, and a guard on the walkway.</li><li>On your first launch, the escort (our own character) says one line by the rail.</li></ul> |
| **Up the tube** | <ul><li>Rises ahead of you at your speed: 40 studs, easing in and out.</li><li>Looks down past the teal ribs and bolted plates.</li><li>Clears the top of your case, levels off, and swings down in front of the glass.</li></ul> | Rising | The tube |
| **The cases** | <ul><li>At face height just outside your glass, looking past you along the row (your frame).</li><li>Then it pulls back and arcs 40° round the hall.</li></ul> | You turn to look along the row | <ul><li>Your six nearest neighbours in their cases.</li><li>The navy hall, its light bars, and guards in front of the cases.</li></ul> |
| **The rise** | <ul><li>Drops to knee height, 6.5–8.5 studs out, looking up at you.</li><li>Circles 270° anticlockwise, seen from above, while climbing with you; field of view 50 → 62.</li><li>**New in pass 2:** in the last 1.5 s it settles into the film's low-angle, whole-body frame (T1 @127.2 s), instead of pass 1's cramped close-up of the cloak and the pole under the roof opening.</li></ul> | You look up at the ring | <ul><li>Dark poles.</li><li>The spoked ring and the light bars streaming past.</li><li>The others rising at staggered heights.</li></ul> |
| **White-out** | Holds the low-angle frame as light floods the opening, until the frame goes white | — | — |
| **Arrival** | <ul><li>Out of the white: 14 studs straight above your plinth, looking down (the film's arrival, T1 @129.2 s).</li><li>It circles the last 90° while dropping behind your head, then pushes into your eyes over 1 s.</li><li>That completes one full turn.</li></ul> | Your plinth rises 10 studs, then locks with a clunk and a puff of dust | The arena |

- **The letterbox.** The red room is shown at 2.39:1. The letterbox opens during the first 3 s of the rise, as the film's picture opens to full height when the tributes rise (L).
- **Reduce Motion.** With Roblox's Reduce Motion setting on (`GuiService.ReducedMotionEnabled`), the circle becomes a slow, straight push up the pole.
- **The short cut** starts with your case already open. It circles 180° in 5 s and ends on the same low-angle frame.

### 2.5 "It loads up": how the arena loads during the shot

**At the call**
- The server places every contender at once, anchored and frozen, at the bottom of their plinth's shaft (Map 1) or their plate's column (Map 2).
- It asks the engine to stream the area round each one (`Player:RequestStreamAroundAsync`, with a 15 s cap).
- From then on your character is your streaming focus, so the arena streams in under the whole shot.
- The launch set itself is scenery your own device builds (§2.10), so it needs no streaming at all.

**When your device is ready.** All three must be true:
1. the server has placed you;
2. your plinth, the horn and the view you'll arrive to have streamed in;
3. that view's meshes have preloaded (`ContentProvider:PreloadAsync`, 6 s at most).

**If you're ready by the end of the red room's minimum,** the shot runs on the shared clock.

**If you're not:**
- Your red room keeps looping, with "THE ARENA IS LOADING".
- Once you're ready, the shot jumps to wherever everyone else has got to: mid-rise, the arrival, or straight onto your plinth.
- If you're still not ready at the white-out, the white holds until you are.
- If you're still not ready at the start signal, the server holds you as it does today, and streaming's pause mode covers the rest.

**Other cases**
- **Skipping.** After the first second, hold Jump for 1 s. You cut to the dark of your tube in the arena, in first person, and rise with everyone at the arrival. Skipping saves no time and shows you nothing early.
- **Leaving.** A contender who leaves during the launch counts as "Left".
- **Riding the train in your first session.**
  - If a round is about to be called while you ride (the Intermission starts), the train's arrival starts at once, so you reach the training floor in time.
  - If the call comes first anyway, you go straight to your red room, with no kit for that round.
- **Map 2.**
  - The teleport to the Clock place ends in your red room. You arrive held in place, and your device builds the red room round you.
  - The shot carries on once the roster is in, or after 20 s.
  - On Map 2 the red room is literally the room between the two places.

### 2.6 The other contenders

- **Your six nearest neighbours** (three each side) appear as their real avatars, in the white launch cape.
  - They are copies, made on your device, of their real characters, which stand in their own shafts near yours.
  - They are stripped down to anchored models, the way FallenSnapshots builds the Roll Call busts.
- **Everyone else** is one shared cloaked figure, hood up, with skin-tone hands.
- **Empty cases stay dark.** A practice round shows only you.
- **Staggered heights.**
  - Each other rider runs a few tenths of a second ahead of or behind the clock, set by their position in the ring.
  - So your neighbours end up 6–16 studs above or below you, as in the film's wide frame.
  - Your own rider is always on the clock, and everyone arrives together.
- **Each device animates every rider itself,** from the shared start time (`GameState.LaunchCallAt`). The server sends no rider positions, so phones don't stutter (critic #12c).

### 2.7 The arrival on each map

| Map | You come up through | Notes |
|---|---|---|
| Map 1 | A brass-rimmed tube in daisy-flecked turf, onto your plinth (48 at r 150), in low, warm morning light with long shadows (C, T1 @129.2 s) | `LaunchController`'s plate rise, retimed |
| Map 2 | The lagoon: your plate surfaces with a burst of spray between two rock spokes (24 at r 210) | A water collar and spray. Swimming is held off during the rise, so the anchored body doesn't start swimming. |

### 2.8 Light and sound

**Light.** Each device swaps in a lighting profile for each space and blends between them over 1 s. The arena's own daylight returns under the white-out.

| Space | Ambient (about) | Lights | Exposure |
|---|---|---|---|
| Red room | (30, 18, 20) | One cool white key down the tube; red light only in the floor openings; white lenses in the red lamp housings | +0.2 |
| Case hall | Navy, about (24, 34, 52) | Cool blue-white keys over the cases, the light bars, and a soft top light in each case | +0.3 |
| Pole hall | Navy, about (14, 20, 32) | The 12 hub spots; the light bars on the ceiling ring and the walls, none on the poles; a key light that rides up with you; bloom threshold 1.4 | +0.3 |

- **The measured target.**
  - In the film, the halls' shadows are blue: blue minus red is +22 to +24 in `art/previews/Launch/colour_check.json`.
  - Pass 1 reached +7 to +8 in the halls, and −18 on the steel deck.
  - Pass 2 aims for +15 to +25. The steel paint stays neutral, and the light carries the blue.
- **Lights on phones.** Each device lights only its own rider and the 4 nearest. Low graphics turns the decorative lights off.

**Sound (I)**
- **Red room:** a low hum, ventilation, and the intercom in the Gamemakers' synthetic voice ("Plinth seventeen. Stand on the disc.").
- **The tube:** a pneumatic hiss and the disc's whir.
- **The cases:** the light bars' buzz and a heartbeat.
- **The hall:** a huge reverb, the whir rising in pitch, and one sustained chord. Never an anthem.
- **White-out:** the sound swells, then cuts to silence.
- **Arrival:** wind, birds and a distant cowbell on Map 1; surf and insects on Map 2.

### 2.9 On screen

| Stage | On screen |
|---|---|
| Red room | <ul><li>No HUD, only the letterbox.</li><li>A title card from 1.5 to 6 s: "{MAP NAME}" over "PLINTH 17 · ARCHER KIT".</li><li>If you're late: "THE ARENA IS LOADING".</li><li>For returning players: "HOLD [SPACE] TO SKIP", with the device's own button.</li></ul> |
| Tube, cases and rise | Nothing. The letterbox opens during the rise. |
| On the plinth | <ul><li>Today's countdown.</li><li>The goal line. Map 1: "RUSH {HORN} · OR RUN FOR A PALE FLAG". Map 2: "SWIM FOR {HORN} · OR RUN YOUR SPOKE TO A PALE FLAG".</li></ul> |

### 2.10 How it's built

- **The set is built on each device.**
  - Its template is `ReplicatedStorage.Assets.LaunchSet`: the three GLBs, about 15 MB in memory and 20k unique triangles. It preloads while you're on the training floor.
  - At the call, each device builds its own red room, the ring of cases, the hall and the stand-ins, at a fixed spot far from every server model. It destroys them after the arrival.
  - Nobody sees anyone else's red room.
  - This replaces the technical plan's server-held halls. There's nothing to stream and nothing to keep in memory per player.
- **The server.** `LaunchService`:
  - picks the cut;
  - publishes `GameState.LaunchCallAt`, `LaunchCut` and `Map`;
  - gives each contender `PlateIndex`, places them in their shaft and requests streaming;
  - collects `PlateReady`;
  - unfreezes everyone at the start signal.

  `RoundService` hands its Countdown to `LaunchService`, and announces numbers only in the last 10 s. Today it announces every second of the phase, which would print 38, 37 and so on over the shot.
- **Each device.** `LaunchController` v2, or a new `LaunchCinematic` beside it, runs:
  - the set and the stand-ins;
  - the camera keys (the manifest's `rise.keys`, at 10 a second);
  - the lighting profiles, the letterbox and the white-out;
  - skipping and the late-loader jump.

  It then hands back to the plinth rise it already does. `CameraController`, `HUDController` and `NotificationController` stand down while `ClientState.cinematic` is set.
- **`Config.Launch`:**

  | Setting | Value |
  |---|---|
  | `RedRoomMin` | 7.6 (practice 4; short cut 2.6) |
  | `Tube` | 3 |
  | `Cases` | 4 |
  | `Rise` | 9 (short cut 5) |
  | `Whiteout` | 1 |
  | `Arrive` | 3 |
  | `OnPlate` | 10 (short cut 6) |
  | `OrbitRadius` | 6.5–8.5 |
  | `NeighbourAvatars` | 6 |
  | `SkipHold` | 1 |
  | `LoadTimeout` | 6 |
  | `FullEverySession` | true |

- **Streaming.** Frustum streaming stays off during the launch. Streaming follows your character in its shaft, not the camera in the set.
- **Budget.**
  - At most 350k triangles drawn: about 200k for the set, the rest for the six avatars and the cloaked figures.
  - At most 16 lights, 2 of them casting shadows.
  - At least 30 fps in the pole hall with 24 riders, on a 3 GB phone.

### 2.11 Done when

- **Timing.** In an 8-client test with one client throttled:
  - everyone hears the start signal within ±0.1 s;
  - the throttled client joins at the current stage.
- **No pops.** A frame-by-frame capture shows no pop at either hidden cut, or at the switch to first person. The camera stays at least 1.8 studs from every pole and case.
- **The cuts.**
  - The full shot runs 38.0 s (34.0 s in practice), and the short cut 18.0 s.
  - The rule picks the full shot whenever any contender hasn't launched yet in this session.
- **Phones.**
  - The pole hall holds 30 fps with 24 riders on a 3 GB Android.
  - A phone on its plinth just after the arrival, having come from the hub, stays within 1.2 GB.
- **Pass 2's fixes show** both in the renders and in game, under their own light:
  - navy halls with blue shadows;
  - the fine net at 45°;
  - dark poles;
  - the low-angle end frame.

---

## 3. Game 1 on Map 1: the Green Land

*Sources: brief §1, the owner's frame `map1_green_land_owner_frame.png` (T1 @1.7 s), and the trailer frames the brief lists. The book's arena is an eye: the horn is its pupil, the meadow its iris, the forest tapers to a point in the north, and the mountain to a point in the south (L).*

### 3.1 What Game 1 has to do

| # | Goal | On this map |
|---|---|---|
| G1 | **Teach the whole game, one rule at a time** | The intro set (§3.12): one creature and four hazards, each with one tell and one counter |
| G2 | **No hidden rule kills you** | Every hazard warns by sound and by shape, with a line for new players. Damage ramps up. Nothing unavoidable downs a tribute at full health (PlayabilityPlan P4, arena-events §2). |
| G3 | **The prettiest places are the most dangerous** | The flower beds, the lake, the gorse and the spiral. The film aimed for "vivid but natural" on purpose (brief [10], [11]). |
| G4 | **Different every time** | 14 seeded mix-ups each round (§3.13) |
| G5 | **Fair at 13+** | No blood from hazards, mutts or animals. No jump scares. Nothing is lethal from full health if you react. |
| G6 | **Runs on a 3 GB phone** | ArenaV3 §7's budgets (§3.19) |
| G7 | **A valley you can live in** | Climbing, hunting, gathering, water and shelter (§3.10), as the owner's design direction asks |

**The lesson plan** (intro rounds; the line in the last column is shown to new players by Guidance Auto)

| When | The lesson | How the map teaches it | Line for new players |
|---|---|---|---|
| On the plinth | Rush or run | The three loot rings and the pale runner's flags are in plain view | RUSH {HORN} · OR RUN FOR A PALE FLAG |
| From 0:00 | Every danger has a tell | The live beds' metal daisies spark from the countdown. Step on one and its fuse hisses for 3 s. The mouth lanes have no beds. | STEP OFF THE FLOWERS · 3 |
| First drink (about 3:30–5:00) | Water first, and read the water | The water marker points only to clean water. Foul water has a still rabbit, a silent bank and a white crust. | FIND CLEAN WATER · 140 m |
| Any time | The valley feeds you | Rabbits flee and can be hunted; berries and cress grow by the water; you can climb a tree to look round | First-time hints (§3.10) |
| 2:30 | Events are chances too | A sponsor drop lands in the open | The drop's card |
| 3:15 | The arena closes in | Stage 1's card, the field moving in, a tick on the compass | MOVE IN AHEAD OF THE BORDER · 140 m |
| 4:15 | A creature has one counter | The crimson flock: stand still, or get under trees or rock | BIRDS · STAND STILL OR GET UNDER TREES |
| 5:45 | Count the fallen | The Roll Call in the sky | LOOK UP · THE ROLL CALL |
| Night | Get away from the mountain | In erupting rounds, the mountain wakes | LEAVE THE MOUNTAIN |
| Dawn | Rain is clean water | Drink from the sky | DRINK THE RAIN · LOOK UP AND [E] |
| 9:50 | The gamble at the centre | The Feast, with the rigged beds re-armed round it | The Feast lines (W&O P12) |
| 12:00 | The heart is the last trap | Every bed is rigged, and they blow in a wave round the ring | STAY OFF THE FLOWER BEDS |
| 13:50 | One winner | The Last Stand closes on a mouth lane | OUTLAST 2 MORE |

### 3.2 Size: a radius of 1,800 studs stays

**The numbers**
- The play radius is 1,800 studs (504 m), so the arena is about 1 km across.
- The start ring holds 10.18M square studs, and the horn to the edge is 138 s at a jog.

**Why the film supports it**
- In the high aerial (FE @26.9 s), the plinth ring is a small disc on a broad grassy shoulder.
- 300–500 m of open grass runs out before scrub, forest and steep ground take over (brief §1.2).
- A 1 km disc holds all of that: an open meadow about 336 m across (to r 600), then forest, crags and the lake, with real-looking mountains behind.

**Why not bigger**
- The book's meadow "went on for miles". But ArenaV3's grids (§7.2), scatter caps (§7.5) and phone memory (§7.6) are sized for r 1,800, and so is the 15-minute round.
- In a first game, rivals would also be too far apart.

This matches the owner's earlier "about 3x wider".

### 3.3 Shape: an open valley, not a crater

**What pass 1 got wrong.** `art/previews/Map1/overview_aerial.png` and `birdseye_34.png` show a round crater:
- ArenaV3's wall and terraces as concentric rings;
- a flat-topped plateau ring;
- stretched backdrop walls up to about 1,000 studs high all round;
- a flat, single-tint plain in the middle.

At ground level (the compare sheets in `References\compare\Map1`), there are two more problems:
- a hard-edged white cloud slab cuts through the mountains;
- the crests end in needle spikes.

The film shows an open valley instead. Green slopes rise close behind the ring, forest covers the lower flanks, limestone crags band the upper slopes, peaks stand at different distances in haze, and soft cloud sits at mid-slope under a blue sky with cumulus.

**What pass 2 builds**
1. **A field holds you in, not a wall.**
   - A force field runs all the way round at the play radius (r 1,800). It is invisible until it's touched: then it ripples in hexagons and hums.
   - Invisible Boundary walls at r 1,900 back it up.
   - In the north (345°–15°), the field stands on the Edge's cliff lip at r 1,760, where the book's tributes discover it.
   - There is no ring wall, no terrace and no plateau. Beyond the field the land carries on as slopes, saddles and separate peaks, out to r 2,750, for looks only.
   - This is also the owner's direction: "The boundary should feel like an actual technological containment system."
2. **The plinth ring stays level, on a shoulder.**
   - Green slopes climb 100–150 studs between r 500 and r 900 on at least two sides: the North Wood and the lids. That is the hillside rising close behind the ring in your frame.
   - The meadow has folds of 15–40 studs.
   - ArenaV3's slope budget still holds: at least 85% of the play disc is under 30°, and at least half of it is under 15°.
3. **Forest.**
   - Dense, dark conifers on the slopes.
   - Broadleaf clumps only in hollows and along water.
   - Open grass on the shoulder.
4. **Rock.**
   - Limestone crags as bands on the upper slopes, with heather and scree below them.
   - No spikes on the crests.
   - Peaks stand at different distances in haze.
5. **Cloud.**
   - Soft, broken banks that hug the flanks below the peaks, at y 250–400, under a blue sky with cumulus. Never hard-edged planes.
   - In game, this is Roblox's Clouds and Atmosphere, plus a few soft cloud-bank meshes with faded edges on the far flanks.
6. **The far range.**
   - The peaks and ridges 1,400–2,600 studs from the plinths are beyond the 1,024-stud streaming radius, where models without level of detail vanish (ArenaV3 §7.4).
   - They become Persistent low-poly skyline meshes, or SLIM, with the farthest range painted into our own skybox.
   - The view out of the south mouth (T2 @49.9 s) is checked at phone quality.

**Done when:**
- a re-rendered overview shows no concentric ring;
- the T1 @1.7 s and @40.2 s matches show hillside and layered peaks behind the horn.

**Regions and heights after pass 2**

| Region | Where | Heights (y) | What's there | Tag |
|---|---|---|---|---|
| **The Heart** | r 0–200 | Knoll 46; platform deck 52; plinth ring 44.3; turf to r 180 | The horn, 48 plinths, 18 flower beds, 6 teardrop beds | C layout, I numbers |
| **The Iris** (the meadow) | r 200–600; its edge wavers between 520 and 700 | 30–70, in folds of 15–40; the stream runs in a dip 6–12 deep | Open grass in three tints, tree clumps in the hollows, gorse banks, white limestone boulders, the flower mounds (berms), three lone trees | C look, I places |
| **The North Wood** | 300°–60°, r 500–1,750 | Climbs from about 60 at r 500 to 160–200 by r 900, then to 210–240 near the Edge; two ravines 20–40 deep | Dense dark pines and firs, beech at the lower edge, clearings of tall pale grass; the spiral, the glade, the wreck, the pools and the holly maze | C look, L hedge, I places |
| **The Shoulders** | 60°–120° and 240°–300°, r 600–1,150 | 70–180, climbing, with gullies | Dry grass, gorse, heather, boulders, pine stands in the gullies; the East Brook | I |
| **The Lids** (the ridges) | 60°–120° and 240°–300°, r 1,150–1,800 | 180–420; crag bands 40–80 high on the upper slopes | Conifers low down, then limestone and heather; a rock shelter at each foot | C look, I layout |
| **The South Mountain** | 120°–240°, r 600–1,800 | Lake bowl 34–60; scree fans 150–400; the summit at 640 (180°, r 1,550); 5 gullies | The volcano's peak, tan scree, crag bands with heather, burnt pines | C look, L volcano, I layout |
| **The Lake** | 160°–200°, r 800–1,050 (about 650 × 250) | Water at 34; floor about 20 | Turquoise water, rocky grass shores, a beach on the north side | C look, I place |
| **The Edge** | 345°–15°, r 1,750–1,760 | Flat ground at 240, then a 107-stud cliff over a canyon | The field's discovery place, the generator's hum, a light beam from the canyon at night | L, I numbers |
| **Beyond the field** | r 1,800–2,750 | Slopes and separate peaks up to about 1,000 | Backdrop only; skyline meshes past r 2,000 | I |

- **The lake is scaled down.** The real Lago del Valle covers 22–24 ha; ours covers 1.3 ha. The valley is compressed, but its look is kept.

### 3.4 The map, to scale

One column is 60 studs and one row is 120 studs. North is up. The sites keep the bearings and radii of §3.6, and pass 2's reshaped slopes don't move them.

```
                  XXXXXXXXXXXXEXXXXXXXXXXXX
              XXXXXXTTTTTTTTTTTTTTTTTTTTTXXXXXX
           XXXXXTTTTTTTTTTTTTTMTTTTTTTTTTTTTTXXXXX
         XXXTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTXXX
       XXXTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTXXX
     XXXTTTTTTTTTTTTTTTTTTTTTTTTTTTTTWTTTTTTTTTTTTTTTXXX
   XXXTTTTTTTTTTTTTTTTTTTFTTTTTTTTTTTTTTTTTTTTTTTTTTTTTXXX
  XXXTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTXXX
 XXX^^TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT^^XXX
XXX^^^^^^^TTTTTTTTTTTTSTTTTTTTTTTTTTTTTTTTTTTTTTTTT^^^^^^^XXX
XX^^^^^^^^^^^TTTTTTTTTTTTTTTTTTLTTTTTKTTTTTTTTTT^^^^^^^^^^^XX
XX^^^^^^^^^^^,,,,TTTT~~TT........Z..TTTTTTT~G,,,^^^^^^^^^^^XX
X^^^^^^^^^^^,,,,,,,,T~~...............TTT,,~,,,,,^^^^^^^^^^^X
X^^^^^^^^^^^,,,,,,,,,~~.................,,,~,,,,,^^^^^^^^^^^X
X^^^^^^^^^^,,,,,,,,,,.~~..1..ooo..2.....,,,~,,,,,,^^^^^^^^^^X
^^^^^^^^^^^,,,,,,,,,,..~~...ooHoo.......,,~,,,,,,,^^^^^^^^^^^
X^^^^^^^^^O,,,,,,,,,,...~4...ooo........,N~,,,,,,,R^^^^^^^^^X
X^^^^^^^^^^^,,,,,A,,,....~....3.....D.~~,,,,,,,,,^^^^^^^^^^^X
X^^^^^^^^^^^,,,,,,,,.....~5..........~~..,,,,,,,,^^^^^^^^^^^X
XX^^^^^^^^^^^,,,,:::......~...7......~...:::,,,,^^^^^^^^^^^XX
XX^^^^^^^^^^^:::::::::....~.........~~.:::::::::^^^^^^^^^^^XX
XXX^^^^^^^:::::::::::::::.~........~~::::::::::::::^^^^^^^XXX
 XXX^^:::::::::::::::::::~~~~~B~~~~~::C::::::::::::::::^^XXX
  XXX::::::::::::::Q:::::~~~~~~~~~~~::::::::::::::::::::XXX
   XXX:::::::::::::::::::::::::::::::::::::::::::::::::XXX
     XXX::::::::::::::::::::::Y::::::::::::::::::::::XXX
       XXX:::::::::::::::::::::::::::::::::::::::::XXX
         XXX:::::::::::::::::::::::::::::::::::::XXX
           XXXXX::::::::::::::P::::::::::::::XXXXX
              XXXXXX:::::::::::::::::::::XXXXXX
                  XXXXXXXXXXXX:XXXXXXXXXXXX
```

**Ground**
- `o` the Heart (`H` the horn)
- `.` the Iris
- `T` the North Wood
- `,` the Shoulders
- `^` the Lids
- `:` the South Mountain
- `~` water
- `X` the field line, with backdrop slopes and peaks beyond it

**Sites**
- `1 2 3`: the lone trees (NW, NE, S)
- `4` the Stepping Stones, `5` the Stream Bend, `7` the South Fold
- `Z` the Cress Spring, `D` the Daisy Spring, `N` the East Brook Ford
- `L` the Butterfly Lane, `K` the Apple Knoll
- `S` the Crimson Spiral, `F` the Fern Pools, `G` the Flower-Sun Glade, `W` the wreck
- `M` the Hedge Hollow, `E` the Edge
- `A` the West Gully Pines
- `B` the North Beach, `C` the Lake Cave, `Q` the Flock Scree
- `R` the Grotto, `O` the Overhang
- `Y` the Shoulder Cairn, `P` the peak (scenery)

### 3.5 The heart

| Element | Numbers | Notes | Tag |
|---|---|---|---|
| **The horn** | <ul><li>6 sails in 3 pairs: the inner sails stand 50 studs above the deck, the outer ones 36.</li><li>The outer skirts flare to 20–26 studs (pass 2; pass 1's narrow A-frame read as a closed cone).</li><li>A hollow centre 36 across.</li><li>A-frame mouths 16 tall and 14 wide, at 60°, 180° and 300°.</li></ul> | <ul><li>You can walk in.</li><li>Inside: weapon racks, chests, cobalt-blue panels and gold fans (decision 2).</li><li>The south mouth frames the peak.</li></ul> | C shape, L colours, I sizes |
| **The platform** | <ul><li>A three-pointed star, 100 across its points (at 0°, 120° and 240°), 6 high, with its deck at 52.</li><li>Cream panels and a teal glass band.</li><li>Bronze steps at each mouth: 18 wide, 4 risers of 1.5.</li></ul> | You can mantle onto it anywhere: 6 is under the 6.5 limit | C, L, I |
| **The plinths** | <ul><li>48 at r 150, at bearings 3.75° + 7.5° × k, 19.6 studs apart.</li><li>Each is a drum 4.3 across and 1.6 tall with a copper top.</li><li>Each stands in a brass-rimmed tube 7.2 across, flush with the turf, with a turf collar about 15 across.</li></ul> | <ul><li>24 tributes stand on every second plinth, 39 studs apart.</li><li>Smaller rounds are spread evenly, as `RoundService` does today.</li><li>Empty plinths rise too, so the ring always reads as the film's.</li></ul> | C, I |
| **The flower beds** | <ul><li>18, lens-shaped, at 15° spacing: 6 in each third of the ring.</li><li>They run from the platform's foot (r about 55) to r about 135.</li><li>16–20 studs wide at the widest, about 1:4–1:5, like the film's. Pass 1 built needles about 1:12.</li><li>Mounded 1–1.5.</li><li>A five-colour cycle (yellow, red, pink, lavender, magenta), rotated each round.</li></ul> | The three mouth lanes are open turf, and so are the narrow gaps between beds | C |
| **The teardrops** | <ul><li>6 big pale petals: a periwinkle-and-white one on one side of each mouth lane, and a marigold one on the other.</li><li>The front pair is the "pale radial pattern at the centre" in your frame. Pass 1 left it a sliver.</li></ul> | Never rigged | C |
| **The fuse daisies** | <ul><li>3 on each rigged bed, along its crest at r about 65, 95 and 120.</li><li>Each is 1.2 across: brass-yellow metal, a copper centre, and a fuse cord down the stalk.</li></ul> | At least 18 studs from any plinth (the outer daisy is 31 away) | C (T2 @126.2 s), I |
| **The turf** | A fresher green disc out to r 180, with daisies and dandelions | — | C |
| **The lone trees** | <ul><li>One round beech on each mouth bearing, at r 300.</li><li>Climbable, with a rest fork at 16 and a perch at 22.</li></ul> | — | C (one is seen), I |

**Fairness at the start**
- **Every plinth gets the same run.**
  - Every plinth stands 3.75° off a bed's centre line, halfway to the turf gap beside it.
  - So every straight run in is the same: veer slightly onto the gap, or cross a bed.
- **The lane-side plinths are shared out.**
  - Six plinths look straight down a mouth lane: the two beside each lane.
  - In a full round, the 24 tributes stand on either the odd or the even plinths, and each set holds three of those six.
  - So the round's random offset never favours anyone.
- **Distance.**
  - A sprint to the nearest mouth takes 5.7–6.5 s.
  - The plinths at the star's points are the farthest from a mouth, but they can mantle the platform's edge.
- **What you can see.** From any plinth, the horn hides about a 30° wedge of the far side of the ring.

**The three loot rings** (WeaponsAndObjectives §3.2's value gradient; every placement scales at one per three tributes, with W&O's floors)

| Ring | Where | What it holds (24 tributes) |
|---|---|---|
| **Outer: white supply bags** (C: "white supply bags on the floor") | r 125–142, on the turf at the beds' outer tips; 8 clusters | A water bottle, plus one of: a bandage, 2 throwing knives, 4 stones, charcoal tablets or a satchel |
| **The deck** | Racks on the bronze steps at the three mouths (r 25–40) | 2 machetes, 2 hatchets, a war club, 2 spears, the bow with 5 arrows (at one mouth, chosen by the seed), 6 arrows and 2 leather vests |
| **The horn's interior** | r 0–18: racks and chests on the cream floor | The longsword (always, from 8 tributes up), padded armour, med kits, rope, a fire kit, field glasses, flares and special arrows |

- **The Feast** restocks the deck and the interior (`LootService.refillHorn`).
- **Tridents.** The film's horn walls carry tridents, and our roster has none. Adding one is the weapons pass's call (§12).

### 3.6 Sites

- **Spacing.** Neighbouring sites are 220–450 studs apart near the horn, and 450–700 farther out: 17–54 s at a jog.
- **Coverage.** No walkable point inside r 1,750 is more than 650 studs from a site.

**Ring B: the Iris, 15–45 s from the plinths**

| # | Site | Bearing, r | What it is | Why go, and the risk | Loot |
|---|---|---|---|---|---|
| B1–B3 | **The lone trees** | 300°, 60°, 180°; r 300 | Round beeches, 28 tall, on the mouth bearings | The first cover, and a perch for scouting. Archers can see you climb. | 1 ground marker each |
| B4 | **The Stepping Stones** | 255°, 340 | The stream's crossing: five stones and a ford 0.8 deep, in the dip | Water and stone heaps. The dip hides ambushers, and the stream may be foul this round. | 2 ground, plus stones |
| B5 | **The Stream Bend** | 215°, 470 | A pool under a gorse bank, with berries | Water, forage and a sponsor-drop spot. May be foul. | 1 crate, 2 forage |
| B6 | **The Gorse Banks and the Daisy Spring** | 110°–122°, 430–440 | A band of gorse 4–6 tall round a spring pool | Water and cover. The gorse burns, and butterflies rest in it. | 1 crate, 2 ground |
| B7 | **The South Fold** | 180°, 480 | A knoll of white boulders that hides the lake | A lookout over the lake, and a sponsor-drop spot. Its top is open. | 1 crate |
| B8 | **The Butterfly Lane** | 5°, 560–760 | The gorse-lined path into the wood (C, T2 @114.2 s) | The way north. The butterflies live here. | 3 ground |
| B9 | **The Cress Spring** | 20°, 520 | A spring pool with watercress | The nearest water on the north side. May be foul. | 1 ground, 2 forage |
| B10 | **The West and East Berms** | 320°, 450 (5 berms); 75°, 480 (4 berms) | Flower mounds with brass plaques (L) | Loot round them. Pollen and hatches in later rounds. | 2 ground each |

**Ring C: 50–100 s out**

| # | Site | Bearing, r | What it is | Why go, and the risk | Loot |
|---|---|---|---|---|---|
| C1 | **The Crimson Spiral** | 330°, 900 | A three-turn spiral of red flower hedges, 50 across (C, T2 @55.9 s) | A prize at its heart. Waves of pollen in later rounds. | Prize spot |
| C2 | **The Flower-Sun Glade** | 60°, 1,000 | A golden grass circle 24 across, ringed by 16 small flower beds; the East Brook rises beside it | The sponsor drop's favourite spot. It's open. | 2 crates, prize spot |
| C3 | **The wreck** | 20°, 1,250 | A crashed hovercraft hull of our own design, in a burnt scar | The best loot in the wood. Long sightlines across the scar. | 3 crates, 4 ground, prize spot (the cockpit) |
| C4 | **The Fern Pools** | 345°, 1,150 | Three karst pools under pines | Water, and a place to camp. May be foul. | 2 crates, 3 ground |
| C5 | **The Apple Knoll** | 35°, 700 | Six small apple trees at the wood's edge (L) | Food. The knoll is open. | 4 forage, 1 ground |
| C6 | **The North Beach** | 180°, 800 | The lake's beach | The lake is always clean. The flock circles overhead, and it's wide open. | 2 crates, 3 ground |
| C7 | **The Delta** | 197°, 790 | The stream's mouth, with reeds and stones | Water. Open. | 1 crate, 2 ground |
| C8 | **The Lake Cave** | 150°, 980 | A limestone shelter with two mouths, on the east shore | Shelter from the eruption and the flock. It invites a siege, so it has two ways out. | 2 crates |
| C9 | **The Flock Scree** | 215°, 1,150 | A tan scree fan above the lake's west end (C, T2 @135.4 s) | A fast slide down. The flock's territory. | Stones, 1 ground |
| C10 | **The Grotto** | 95°, 1,200 | A cave at the foot of the east lid | Shelter. Far out. | 2 crates |
| C11 | **The Overhang** | 265°, 1,200 | A deep overhang at the foot of the west lid | Shelter. Far out. | 2 crates |
| C12 | **The West Gully Pines** | 250°, 800 | Pines in a gully on the west shoulder | Cover. It can burn. | 1 crate, 2 ground |
| C13 | **The East Brook Ford** | 100°, 700 | The brook's crossing | Water. An ambush point, and it may be foul. | 1 crate, 2 ground |
| C14 | **The Burnt Pines** | 195°, 1,280 | Dead pines on the slope above the scree | A lookout over the lake. It's inside the eruption's zone. | 1 crate |

**Ring D: 100–135 s out.** These sites are for the bold. Stage 1's border passes r 1,750 at 3:25, r 1,600 at 3:58 and r 1,300 at 5:04, unless the drift points their way.

| # | Site | Bearing, r | What it is | Why go, and the risk | Loot |
|---|---|---|---|---|---|
| D1 | **The Hollow Spring** | 10°, 1,480 | A spring in a fern hollow | Water near the maze. May be foul. | 2 ground |
| D2 | **The Hedge Hollow** | 0°, 1,600 | A V-shaped holly maze (C, TVk @8.8 s; L) | A prize at its heart, and the way to the Edge. The maze slows you while the border comes. | Prize spot |
| D3 | **The Edge** | 345°–15°, 1,750 | Dry ground, a 107-stud cliff, the field | The field's secret, and the hum. The field bites. | 1 crate |
| D4 | **The Shoulder Cairn** | 180°, 1,250 | A ledge on the peak's north face, reached by the Summit Trail (about 2 minutes from the beach) | A prize, and a view of the whole eye. It's in the eruption's zone. | Prize spot |
| D5, D6 | **The East and West Crests** | 80° and 280°, 1,600 | Lookouts on the lids | Scouting. Exposed, and they close at about 4:00. | 1 crate each |

- **The summit is scenery.** It stands at 640, at r 1,550. The trail to it takes over 3 minutes from the beach, and stage 1 takes it at 4:09.
- **The 16 berms:**
  - 5 in the West Berms and 4 in the East Berms;
  - 7 single berms, at 350°/r 640, 40°/680, 100°/820, 260°/760, 150°/560, 315°/820 and 70°/930.

### 3.7 Water

| Water | Course | Can it be foul? | Notes |
|---|---|---|---|
| **The lake** | 160°–200°, r 800–1,050; level 34 | Never | Always clean, and always exposed |
| **The Wildflower Stream** | Spring pool at 315°/720 → 295°/560 → 275°/420 → the Stepping Stones (255°/340) → the Stream Bend (215°/470) → the Delta (197°/790) → the lake | Yes, the whole stream | A stony bed in a dip 6–12 deep, with wildflowers on both banks (C, T2 @128.7 s) |
| **The East Brook** | Spring at 55°/960, beside the glade → 80°/780 → the ford (100°/700) → 115°/560 → 135°/600 → 150°/760 → the lake at 160°/860 | Yes, the whole brook | — |
| **The Daisy Spring** | 122°, r 440 | Yes, on its own | Beside the gorse banks |
| **The Cress Spring** | 20°, r 520 | Yes, on its own | The north's nearest water |
| **The Fern Pools and the Hollow Spring** | 345°/1,150 and 10°/1,480 | Yes, together | Karst pools that sink into the limestone |
| **Rain** | Anywhere under open sky while it rains | Never | §3.11 |

- **Water levels follow pass 2's terrain.** Every designed level must sit in the lower half of its 4-stud voxel layer.
  - Pass 1 had three stream pools that broke this rule: 54.42, 42.2 and 39.13.
  - Pass 2 snaps the levels in the generator, and the packer refuses any data that breaks the rule (§9.3).
- **How far water is** (measured on Game 1's layout):
  - with no foul water, the farthest any plinth is from water is 419 studs, 32 s at a jog;
  - with any two foul sources, it's 621 studs at most, and the randomiser enforces a limit of 650;
  - with any two foul sources, at least two clean ones stay inside stage 2's ring (r 800).

### 3.8 Routes, climbing and sightlines

**The main paths.** Each one bends round folds, so no straight stretch shows more than about 250 studs ahead.

| Path | Leaves the heart at | What it links | Length | At a jog |
|---|---|---|---|---|
| **North Path** | 0° (a star point) | The Butterfly Lane, the Cress Spring, the wreck, the Hollow Spring, the Hedge Hollow, the Edge | About 2,000 | About 2:35 |
| **Glade Path** | The 60° mouth | The NE lone tree, the East Berms, the Apple Knoll, the glade, the East Crest | About 1,900 | About 2:25 |
| **East Path** | 120° (a star point) | The gorse banks, the Daisy Spring, the East Brook Ford, the Grotto | About 1,400 | About 1:50 |
| **Lake Path** | The 180° mouth | The S lone tree, the South Fold and the North Beach; then east to the Lake Cave, or west to the Delta, the Flock Scree and the Summit Trail | About 1,000 to the beach | 1:15 to the beach |
| **West Path** | 240° (a star point) | The Stepping Stones, the Stream Bend, the West Gully Pines, the Overhang, the West Crest | About 1,900 | About 2:25 |
| **Spiral Path** | The 300° mouth | The NW lone tree, the West Berms, the stream's spring, the spiral, the Fern Pools | About 1,300 | About 1:40 |
| **The Iris Round** | — | A loop at r about 560 through every ring-B site | About 3,500 | About 4:30 |
| **The Wood Round** | — | A loop at r about 1,100 from 300° to 60°: the Fern Pools, the wreck, the glade | About 1,600 | About 2:00 |

- **Game trails** lead down to every water source and ford (PlayabilityPlan B7).
- **Crossings:** the Stepping Stones, the Delta's stones, the East Brook Ford, two fords on the stream's upper reach, and a fallen pine across the North Wood's west ravine.
- **Swimming.** You can always swim, at 8 studs/s. The lake is about 250 across: a 31 s swim.
- **High ground:**
  - the lone trees and one tall pine in 15 in the North Wood are climbable (§3.10);
  - the crag bands can be climbed by gully scrambles with mantles of 6 studs or less;
  - scree chutes are the fast way down (Basalt, ArenaV3 §5.6), and the Flock Scree slide takes about 10 s;
  - every crag that can't be climbed looks sheer (PlayabilityPlan B7);
  - a 40-stud fall does about 56 damage, and a 58-stud fall kills.

**Sightlines and cover**
- **From the plinths:** 250–450 studs across the meadow.
- **In the meadow:** something breaks the view every 40–80 studs.
- **In the stream's dip:** you can't see a crouched tribute from the heart.
- **In the North Wood:** 60–120 studs, which is bow range.
- **Across the lake:** 600 studs or more.
- **Cover heights** (ArenaV3 §5.7):
  - anything 6.3 studs or taller hides someone standing;
  - anything 3.6–4.5 tall hides a crouched head;
  - the flower beds (1–1.5) and the berms (1.5) are not cover.

### 3.9 Loot

| Where | Crates | Ground | Forage | Items (expected) |
|---|---|---|---|---|
| The heart: the interior and the deck (tier 3) | 8 | 6 racks | — | About 30 |
| The heart: the outer bags | — | 8 clusters | — | About 16 |
| The runner's flags (8, tier 2) | 8 | — | — | About 24 |
| Ring B sites | 3 | 24 | 8 | About 38 |
| Ring C sites | 22 | 36 | 8 | About 85 |
| Ring D sites | 3 | 4 | — | About 10 |
| Prize spots (5; 2 stocked each round) | 5 | — | — | About 4 |
| Trails, game trails and berms | — | 70 | 12 | About 60 |
| **Total** | **49** | **148** | **28** | **About 270** |

- **How much that is.** About 11 items per tribute; today's arena gives about 10. The Feast and the sponsor drops add the rest.
- **The tuning rule** (W&O): the median number of items held at 5:00 and at 10:00 should sit between today's figure and 1.3× today's.
- **The runner's flags.**
  - Eight pale flags stand at r 340, at bearings 22.5° + 45° × k, each beside a landmark.
  - Each is about 190 studs from its nearest plinth: 9 s at a sprint, just past one sprint bar. So running away still beats the scramble (ArenaV3 §6.2).
  - Their poles are 14 studs tall.

### 3.10 Natural interaction: climbing, hunting, gathering and shelter

The owner's design direction (§2.2) calls this the area they "particularly emphasise". It ships as its own release, straight after the Green Land (§10, R2).

- **Climbing trees by their own shape.**
  - A climbable tree carries a `Climbable` tag on its trunk mesh, and `Perch` attachments at its forks.
  - You push into the trunk to climb. Your hands and feet follow the trunk's facets and limbs, and the forks are rest points.
  - There's no ladder, no button prompt and no floating handhold.
  - Climbable trees on Map 1:
    - the three lone beeches;
    - one tall pine in 15 in the North Wood, with forks no more than 40 studs apart;
    - the apple trees.

    On Map 2, the climbable jungle giants follow the same rule.
  - The cost: archers can see a climber.
- **Wildlife.** These are ordinary animals, not mutts: rabbits, squirrels and songbirds near players, and frogs at clean water.
  - Each player's area shows up to 12 at a time. The server keeps them light (§6.4).
  - They flee when you come close: a rabbit bolts at 25 studs if you walk and 40 if you sprint.
  - They freeze if you crouch still.
  - Birds burst out of cover when anyone passes. That is the owner's "tracking": a flush of birds tells you someone is there.
- **Hunting for food.**
  - A bow, a thrown knife, a spear or a stone can take a rabbit, a squirrel or a bird.
  - The animal goes limp and fades into a food item within 2 s. No blood, no wounds, no struggling, and no trapping a live animal.
  - The food is game meat: +25 hunger, or +40 if it's cooked at a fire kit or a lit fire.
  - It takes skill, as the owner asked: small, fast targets that flee.
- **Roblox's rules, checked on 14 November 2026.**
  - The Community Standards forbid "Depicting or glorifying human, animal, or fictional creature abuse and torture" ([Community Standards](https://about.roblox.com/community-standards)).
  - The content-ratings questionnaire treats violence against non-humans, "such as animals", as something you declare ([Content ratings](https://create.roblox.com/docs/production/promotion/content-ratings)).
  - So quick, bloodless hunting for food is allowed, as long as it never reads as abuse or torture, and the questionnaire must declare violence against animals.
  - arena-events.md read the rule as "no harming harmless animals", which is stricter than Roblox's own rule, and this section replaces it for wildlife. Its other limits stay: nothing is harvested from a mutt, and nothing tortures or traps a live animal. If a snare comes later, it shows only the catch, never a struggling animal.
  - The foul-water tell, a still rabbit with no wounds, is fine under the same rule.
- **Gathering.**
  - Map 1 has 28 forage markers: berries on the gorse banks, watercress at the springs, apples on the Apple Knoll, and mushrooms in the wood.
  - Forage is always safe to eat. The book's poisoned forage becomes the foul-water system instead, so there's one poison rule to learn, not two.
- **Water.** Streams, springs, the lake and the dawn rain. A bottle fills at any clean water.
- **Shelter.** The rock shelters (the Lake Cave, the Grotto and the Overhang), dense tree crowns and the horn. Shelter stops the flock's dives and the eruption's bombs.
- **First-time hints:**
  - "A RABBIT · HUNT IT FOR FOOD"
  - "CLIMB · PUSH INTO THE TRUNK"
  - "BERRIES · [E]"

### 3.11 The challenges

**Rules every challenge follows** (arena-events §2, §3 and §5)
- **Warn before a zone hurts:** at least 15 s, and usually 20–30. The warning is a card, a sound, a sign in the world and a compass icon.
- **Warn before a single hit:** at least 1 s for a bird's dive, 2 s for the swarm's charge, and 3 s for a daisy.
- **A tribute who reacts survives.** The table below gives the time each challenge takes to down a healthy tribute who does nothing.
- **One Gamemaker event at a time.** The beds, the water and the field are part of the map, not events.
- **Never personal.** Events aim at areas and groups. Mutts pick prey by noise and smell, as animals do.
- **The same information on every device.** Phones get fewer particles, never fewer warnings, and no tell depends on colour alone.
- **13+.** No blood or wounds. A mutt that dies goes limp and fades. Coughing, never coughing blood. No jump scares.
- **Kill credit.** A hazard death within 15 s of a hit credits the hitter. A daisy or a berm that a tribute lit credits that tribute.
- **New damage causes:** Bloom, Foul, Pollen, Squirrel, Flock, Swarm, Fire, Eruption, Field, Rebound and Gas.

**All twelve challenges**

| Challenge | Set | Where | When | Tell | One counter | Time to down a healthy tribute who does nothing | Cause |
|---|---|---|---|---|---|---|---|
| **Rigged flower beds** | Intro | 3 of the 18 beds; every bed at 12:00 | Stepped on, shot or burnt | Metal daisies sparking from the countdown; a 3 s hiss | Step off the bed | Never: 35 per blast at most | Bloom |
| **Foul water** | Intro | 2 of the 5 sources | Any drink | A still rabbit, a silent bank, a white crust | Drink elsewhere; charcoal; rain | Never, from 3 sips (about 54) | Foul |
| **The field** | Intro | Round the edge, on the Edge cliff, and on the closing border | Always | A shimmer within 30 studs; the hum; ripples | Don't touch it, or shoot into it | 20 per touch | Field, Rebound |
| **The mountain wakes** | Intro | The South Mountain | Night, in erupting rounds | Smoke all round; 30 s of tremors | Leave the slopes; get rock overhead | Bombs 25 each; the gel 10 a second | Eruption |
| **The crimson flock** | Intro (the one creature) | Over the lake and the scree; open ground near a group | On its territory; Slot 2 | Shrieks; a 1 s shadow | Stand still; get under trees or rock | 20 s or more | Flock |
| **Golden squirrels** | Full | From a hatch berm | Slot 2 or 5 | The hatch's 15 s warning; chattering | Get into water; drop food | 15 s or more | Squirrel |
| **Blue butterflies** | Full | The Butterfly Lane, the gorse | Sprinting past them; Slot 2 or 5 | A blue shimmer; a 2 s white flash | Fire, water, or just jog away | 45 s or more | Swarm |
| **The flower mounds** | Full | 16 berms: 4 hatches, 4 pollen, 2 gas plants, 6 plain | Near them or on them | Big nodding flowers; a haze; the marks on the plaques | Walk round | About 18 per puff | Pollen |
| **Fire in the gorse** | Full | Gorse, heather, pines, hedges | Slot 2 or 5; fires tributes light; the eruption | A smoke column 20 s ahead; crackling | Cross a firebreak | About 16 s inside the flames | Fire |
| **Tear gas** | Full | Just inside the ring | Slot 5 | A whine overhead; falling canisters | Go upwind and uphill | About 55 s | Gas |
| **The spiral and the maze** | Full | The Crimson Spiral; the Hedge Hollow | Always | A sigh and a shimmer; the maze's walls | Wait in an air pocket; burn a shortcut | About 3 s per pollen wave, if you keep moving | Pollen |
| **The Sweep** (night searchlights, ours) | Full | The inner valley | Night, in rounds without an eruption | A drone; beams | Get under cover; stay still | No damage | — |

Two beats are not hazards: **sponsor drops** (the Lure, arena-events §4: a 20 s flare, a 12 s descent, and a gift worth fighting for; two gifts with 13 or more alive) and **the dawn rain**.

**The intro set in detail**

*The rigged flower beds (the Bloom).* C: a metal daisy fizzes like a lit fuse (T2 @126.2 s), then a fireball tears through a flower bed (T2 @127.4 s).
- **Where.** 3 of the 18 beds, one in each third of the ring, picked by the seed. Each has 3 fuse daisies standing up out of the bed and sparking from the countdown. Decision 4 can hide them until a fuse lights.
- **What lights a daisy:**
  - stepping onto a rigged bed lights the daisy nearest to you;
  - an arrow, a stone, a thrown knife, a spear or a hatchet hitting a daisy;
  - fire: a flare, a pitch arrow, a fire patch or a neighbouring blast.

  Each daisy blows only once. Nothing lights while tributes are frozen on their plinths.
- **The fuse.** 3 s: a hiss you can hear 80 studs away, a fountain of sparks, and the cord glowing up the stalk. A new player on a lit bed, or within 4 studs of one, sees STEP OFF THE FLOWERS · 3.
- **The blast.**
  - A fireball column 10 studs tall.
  - 35 damage within 2 studs, falling to 12 at 6 studs, plus Burning (2 a second for 3 s) within 3 studs.
  - A shove of 18 studs/s away from the daisy.
  - The bed is then charred and inert, and smokes for 10 s.
- **Counters:**
  - step off: from a bed's centre line, its edge is 8–10 studs away, under a second at a jog;
  - use the mouth lanes and the turf gaps, which have no beds;
  - light the daisy beside a rival.
- **Re-arming.** At the Feast's warning (8:20), the rigged beds get fresh daisies.
- **The Garden Wakes (12:00).**
  - 15 s before, a daisy rises in every bed, at r about 80 and about 110. That's 36, plus any rigged daisies still standing.
  - The Gamemakers then light one bed every 2.5 s, in a wave that turns round the ring from a seeded bed, in a seeded direction. A full turn takes 45 s.
  - The lanes and the gaps stay safe.
- **Fairness.** Two blasts can't down a healthy tribute (70, plus 6 from Burning). The daisies read by their shape, so players who can't tell colours apart see them too. Because the beds go off when stepped on, the first lesson is learnt on the first step, not in the middle of the scramble.

*Foul water.* L: in the book, a rabbit drinks beside Haymitch and dies, and charcoal tablets from his pack save him (Ink and Imaginings recap, ch. 15–16; LitCharts, ch. 16).
- **Where.** 2 of the 5 foul units in §3.7, picked each round. The lake is never foul.
- **Three tells,** none of them colour alone:
  1. a rabbit lies still at the bank by each drinking point, with no wounds;
  2. the bank is silent: no frogs or insects, where clean water has them;
  3. a white crust coats the stones at the waterline.
- **For new players.** The first time they look at foul water, a hint reads FOUL WATER · SOMETHING DIED HERE · CHARCOAL CLEANS IT. The water marker points only to clean water.
- **The effect.**
  - A sip still gives +10 thirst, but it makes you Sick: 1.5 damage a second for 12 s per sip, stacking up to 36 s, with no healing while you're Sick.
  - A tribute who drinks foul water coughs, and you can hear it 30 studs away.
  - Three sips cost about 54 health.
- **Counters.** Read the tells. Drink from the lake, from another source, or from the rain. Charcoal tablets cure Sick, and clean a bottle filled at a foul source.

*The field.* L: beyond the hedge is a sheer cliff over a canyon, and a force field there "repels objects thrown at it"; a tribute's axe bounces off it and kills her (the recap, ch. 22–24).
- **Where:**
  - all round the arena at r 1,800;
  - on the Edge's cliff lip (345°–15°, r 1,760), where the book's tributes discover it;
  - on the closing border, which is the same field moving inward.
- **Tells.**
  - It's invisible beyond 30 studs. Within 30 studs, a faint shimmer of hexagons shows.
  - The generator's hum is loudest at the Edge, and at night a thin beam rises from the canyon.
  - Wherever anything strikes the field, a hexagonal ripple shows.
- **The effect.**
  - The outer field does 20 damage when you touch it (10 the first time in a round), and throws you 16 studs back.
  - Anything thrown that hits any field surface comes straight back along the mirrored path, at 85% speed and full damage, and it can hit whoever threw it.
  - The closing border never blocks bodies. Outside it, you take today's border damage.
- **Counters.** Don't touch it. Don't shoot at someone standing in front of it. Fight with your back to it. Bank shots are allowed.
- **Fairness.**
  - A rebound kill counts as "Rebound". The credit goes to the target the thrower was aiming at, but only if that target hit the thrower in the last 15 s.
  - The first time a projectile rebounds within 60 studs of a new player, a hint shows: THE FIELD THROWS BACK WHAT'S THROWN AT IT.

*The mountain wakes.* C: the peak erupts at night above the valley, and the pines burn (the IMAX clip). L: the mountain is an artificial volcano with flames, a toxic wind, clear sparkly ash and a burning gel that sets hard and glassy (brief §1.8).
- **The mountain's mood** (§3.13): dormant, restless or erupting.
- **When.** The warning comes 10 s after Roll Call 1 ends (about 6:30–7:00), and the eruption 30 s after that.
- **Tells.**
  - All round, the smoke column is thicker and warm at its base, and at the Roll Call it glows from below.
  - 30 s ahead: tremors (the camera shakes 0.3° at most), a rumble, skittering pebbles, and the flock bursting off the lake.
  - The card reads THE MOUNTAIN WAKES · LEAVE THE SOUTH SLOPES.
- **The effect,** for 75 s:
  - a fire fountain at the summit;
  - bombs on the slopes and the lake's south shore, each marked by a glowing ring 1.5 s before it lands: 25 damage at the centre, 8 at 6 studs, and a fire patch;
  - gel down 2 of the 5 gullies, at no more than 3 studs/s, doing 10 a second plus Burning. After 60 s it sets into a glassy crust you can walk on, which makes new cover and new routes;
  - clear, sparkly ash over the valley for 60 s;
  - embers that light the pines on the mountain. In intro rounds the fire stays on the mountain's slopes; in full rounds it can reach the near ends of the lids.
- **Counters.** Leave the zone: north of the lake is safe. Shelter under rock. Keep to the ribs between the gullies. Cross the gel only once it has set.
- **Fairness.**
  - The zone is about 13% of the night's ring.
  - If it holds more than 60% of the living at the warning, the bombs land only above y 300.

*The crimson flock.* C: crimson long-necked birds dive at a tribute on scree (T2 @135.4 s). L: waterbird mutts kill a tribute (the recap, ch. 23).
- **Where.** A flock of 12 circles the lake all round. It's a landmark, and harmless at a distance.
- **Triggers:**
  1. **Territory:** a tribute who stays on the open scree or the lake's south shore for 15 s;
  2. **the Director:** in Slot 2, the flock flies to open ground round a group (a 150-stud zone) for 40 s.
- **Tells.**
  - The flock shrieks and circles lower. On its own territory, that gives 5 s before the first dive.
  - A diving bird tucks its wings, and its shadow streaks across the ground towards you for 1 s.
- **The effect.**
  - A dive does 12 damage, and armour helps.
  - Each tribute is dived at most once every 2.5 s.
  - Each bird has 12 health.
- **Counters.**
  - Get under cover: tree crowns, rock overhangs or the horn.
  - Crouch and stay still for 3 s: they hunt movement.
  - Swat the diver in the last half second.
  - Water doesn't help: these are waterbirds. That's the opposite of the squirrels, on purpose.

**The full set in brief**

| Challenge | Trigger and tell | Effect | Counters and fairness |
|---|---|---|---|
| **Golden squirrels** (L: the book's carnivorous squirrel mutts) | A hatch berm releases them near a group, with a 15 s warning (the mound trembles, the flowers part on brass blades, a red strobe pulses, a hiss rises). A chattering chorus. They stop all at once, in step, with a copper glint in the eyes: their one wrong trait. | A pack of 8, plus 1 for every 4 tributes alive, 12 at most. 12 health each. They run at 16 studs/s and climb trees. A nip does 4, with at most 2 on one tribute at once (6.7 a second at most), and a swarm slows you by 15%. They hunt for 50 s. | Any water 0.6 deep or more. Food holds them for 8 s. Any hit kills one. Fire scatters them for 6 s. At least 15 s to down a tribute who does nothing. They leave alone anyone under 25 health who doesn't attack, and nothing is released once 5 or fewer are left. |
| **Blue butterflies** (C: T2 @113.7–114.7 s; L: they sting with a shock, and Haymitch burns the swarm) | Sprinting within 8 studs of a resting group, or the Director's swarm of 60 rising from the lane in daylight. A blue shimmer you can see 200 studs away; the wing edges flash white 2 s before they sting. | Sprinting past: 10 sting for 6 s at 1 a second. The swarm hunts the noisiest within 250 studs for 40 s: 2 a second inside it, a 0.3 s stagger every 4 s, and a 1 s knock-down with 40 or more on you. It moves at 11 studs/s. | A flare kills half the swarm; a gas-plant berm kills all within 10 studs. Water at least 2 deep for 3 s. Crouch still in dense gorse for 5 s. Or jog away: 13 beats 11. At least 45 s to down; knock-downs are never lethal. Phones draw 30 butterflies, not 60. |
| **The flower mounds** (L: the book's single-flower berms, bee-balm pollen, the "gas plant" and the mutt hatches) | 16 berms, each 6–10 across and 1.5 high, with a brass plaque engraved with a flower and no words. Pollen plaques add a cloud mark, gas-plant plaques a flame mark; hatch berms and plain berms look the same. | Pollen: a small puff every 6 s within 6 studs, a big one if you step on. Inside the haze (8 studs, 6 s): 3 a second, plus Choking (stamina recovers at half speed for 8 s). Gas plant: fire sets off a 12 s flame column (5-stud radius, 6 a second), which kills butterflies within 10. Hatch: releases squirrels. | Walk round. No pollen berm sits on a trail. A gas plant is a trap, or the book's own counter to the swarm. |
| **Fire** (C: T1 @113.8 s, @94.4 s and @96.8 s; T2 @119.2 s) | The Director lights one edge of a scrub slope, never within 100 studs of a tribute, with a smoke column 20 s ahead. Tributes' fires: at most 3 burn at once. | 16-stud fuel cells: gorse burns 15 s, heather 12, dry grass 8, pines 25, hedge 20. Fire spreads downwind, and faster uphill, at no more than 4 studs/s with the wind, 2 across it and 1 into it. 6 a second inside a burning cell, 1 a second within 4 studs. Burnt ground stays charred. | Move across the wind. Cross a path, a stream, scree, rock or turf. Stand on burnt ground, or get in the water. Rain puts every fire out. A firebreak is within 150 studs of every point of scrub; a TerrainGen check enforces it. |
| **Tear gas** (L: a hovercraft drops tear gas on tributes) | An unseen hovercraft whines overhead; 3–5 canisters fall trailing smoke for 2 s | Each makes a grey-green cloud 25 across that drifts downwind for 40 s. Inside: your sight blurs at the edges, stamina doesn't recover, you cough loudly, and after 5 s it does 2 a second. The gas settles in dips. | Go upwind and uphill. About 55 s to down. Reduce Motion turns off the blur's wobble. |
| **The Crimson Spiral** (C: T2 @55.9 s) | 50 across, three turns, about 280 studs of path; hedges 4.5 tall and 2.5 thick; paths 4 wide with three air pockets | Every 20 s the hedges breathe out: a sigh, then a gold shimmer runs out from the heart at 10 studs/s, doing 3 a second plus Choking | Wait in a pocket, then walk on. Fire burns a gap through one hedge wall in 10 s. The prize at the heart is stocked in half of rounds. |
| **The Hedge Hollow** (C: TVk @8.8 s; L: the book's V-shaped hedge) | A V-shaped holly maze at r 1,600, its point reaching the Edge. Walls 16 tall and 5 thick, paths 6 wide; three gates on the south side, one open each round. | It takes 60–90 s to walk through. A tribute who reaches it at about 3:00 has under a minute before stage 1's border arrives. | Some wall segments burn: fire opens a gap in 12 s. The prize is at the heart. |
| **The Sweep** (I, from an unplaced IMAX night shot) | A low drone; 3–4 white beams fall from the dark sky and sweep slow arcs. Each spot is 14 studs wide and moves at 7 studs/s at most. | Standing in a beam for 1 s makes you Lit for 8 s: a soft outline shows you through foliage to everyone within 200 studs (8 outlines at most). No damage. 70 s. | Get under dense trees or rock, into the horn or the spiral. Or crouch still in tall grass and move between sweeps. |

**Later (v1.1 onward):** ladybugs in the maze, the quill porcupine, deer and fox mutts, glass-winged bats at night, the Glitch (a rare malfunction in which every hatch opens and gives itself away), and the Sub-A tunnels (C, T2 @112.2–124.4 s).

### 3.12 The intro set and the full set

**Why there are two sets.** On launch day every player is new. Twelve systems in one 15-minute round meant about twelve lessons: four different counters at 4:15, and a blast at 0:30 in the middle of the scramble. The intro set teaches five rules, one at a time, each learnable on the first try.

**How a round picks its set.**
- At the call, the server reads each contender's `GreenLandRounds`.
- If at least half of them have finished fewer than 3 rounds, the round runs the intro set. Otherwise it runs the full set.
- A practice round runs the intro set for a player with fewer than 3 rounds.

**The intro set**
- **Standing hazards:** the rigged beds (including the Garden Wakes), foul water and the field.
- **Slot 1:** a sponsor drop.
- **Slot 2:** the crimson flock.
- **The night:**
  - the mountain wakes in 60% of rounds, and its fire stays on the mountain;
  - otherwise, a quiet night: stars, owls, and the generator's beam from the canyon.
- **Dawn:** the dawn rain.
- **Slot 5:** a second sponsor drop.
- **Slot 6:** the Garden Wakes.
- **Left out:** squirrels, butterflies, fire in the gorse, tear gas and the Sweep. The berms are plain mounds, and the spiral and the maze are places with prizes but no pollen waves.

**The full set** runs everything in §3.11.
- Slot 2 draws the featured mutt (squirrels 40%, the flock 30%, butterflies 30%), or the gorse fire if a group sits in scrub.
- Slot 5 draws tear gas, the gorse fire or the swarm.

### 3.13 The per-round mix ("a few mix ups each time you play it")

`Mix.roll` is seeded at the call (§6.3).
- **Public part.** `GameState.RoundMix` holds only what players are meant to see, such as the rigged beds if they're visible.
- **Hidden part.** Hidden choices reach devices only when they trigger.
- **The seed** is logged with the round and shown in the round summary.
- **No repeats.** The server remembers its last three mixes, to avoid repeating them.

| # | Mix-up | Options and weights | Rules | Intro rounds |
|---|---|---|---|---|
| 1 | **The live colour** | 5 colours, equal weights | Not the same as the server's last round | Yes |
| 2 | **The colour order** | Rotation 0–4 | — | Yes |
| 3 | **Foul water** | 2 of the 5 units | Every plinth within 650 studs of clean water; 2 or more clean sources inside r 800; never the lake | Yes |
| 4 | **The berms** | Of 16: 4 hatches, 4 pollen, 2 gas plants, 6 plain | Hatches at r 320 or more, at least one in each half of the map; no pollen on a trail; gas plants near gorse | All plain |
| 5 | **The featured mutt** | Squirrels 40 / the flock 30 / butterflies 30 | Not the same three rounds running | Always the flock |
| 6 | **The mountain's mood** | Full set: dormant 25 / restless 40 / erupting 35. Intro set: erupting 60 / restless 25 / dormant 15. | At most 2 eruptions in a row | Yes |
| 7 | **The gel gullies** | 2 of 5 | At least one flows into the lake | Yes |
| 8 | **The wind** | 8 bearings; light 70 / fresh 30 | Sets `Workspace.GlobalWind`'s direction | Yes |
| 9 | **The rain** | Dawn 60 / afternoon 20 / none 20 | — | Yes |
| 10 | **The hedge gate** | 1 of 3 | — | Yes (the maze is open, without hazards) |
| 11 | **The prize spots** | 2 of 5 stocked | — | Yes |
| 12 | **The bow's mouth** | 1 of 3 | — | Yes |
| 13 | **The sponsor-drop spot** | 1 of 7 | Inside stage 1's ring | Yes |
| 14 | **The border's drift** | ArenaV3's seeded bearing | ArenaV3 §6.5 | Yes |

A player notices three to five of these in a round.

### 3.14 The round timeline: 15 minutes, with an 18-minute switch

A full round of 24. The HUD clock counts down from 15:00.

| Time | Beat | Intro set | Full set |
|---|---|---|---|
| Before 0:00 | The launch (§2), then the arrival | — | — |
| On the plinth | 10 s (6 s in the short cut). The heart and the valley in morning light (07:24, low and warm from the east, mist in the hollows, the cloud bank on the flanks). | The live beds' daisies sparking | The same |
| 0:00 | **The start signal** (the film has a gong; its name is open) | — | — |
| 0:00–0:45 | **The scramble** | The rigged beds are armed | The same |
| 0:45–2:30 | **Day one.** Water first; kit up; hunt or gather. | The flock circles the lake | The butterflies rest in the lane, too |
| 2:15 | Stage 1's warning card | — | — |
| 2:30 | **Slot 1** | A sponsor drop | The same |
| 3:15–5:15 | **Stage 1:** r 1,800 → 1,250, drifting up to 200 towards the seeded bearing | — | — |
| 3:30–4:05 | An afternoon shower (20% of rounds) | — | — |
| 4:10 | THE LIGHT IS GOING | — | — |
| 4:15 | **Slot 2** | The crimson flock | The featured mutt, or the gorse fire |
| About 5:10 | Sunset | — | — |
| 5:45 | **Roll Call 1:** the fallen in the sky | — | — |
| About 6:30–8:05 | **The night** | The mountain wakes (60%), or a quiet night | The mountain wakes (35%); otherwise the Sweep (restless rounds also get tremors and a rockfall at dusk) |
| 7:10 | Stage 2's warning card | — | — |
| 8:10–9:25 | **Stage 2:** → r 800. Dawn. | — | — |
| 8:20 | The Feast's warning (90 s); the rigged beds re-arm | — | — |
| 8:20–9:00 | **Dawn rain** (60% of rounds): fires go out; drink and fill bottles | — | — |
| 9:50 | **The Feast** at the horn | — | — |
| 10:00–13:50 | **The final closing:** → r 35 | — | — |
| 10:30 | **Slot 5** | A second sponsor drop | Tear gas, the gorse fire or the swarm |
| 12:00 | **Slot 6: the Garden Wakes** | Yes | Yes |
| 13:48 | Roll Call 2 (the list only, while the border moves) | — | — |
| 13:50–14:45 | **The Last Stand,** closing on a mouth lane | — | — |
| By 15:00 | The winner, and the eye shot | — | — |

- **A beat every 1–2 minutes.** That matches the owner's "new challenge every couple of minutes".
- **Why 15 minutes stays.**
  - The staged border is built for this size.
  - The Feast (590 s), the final closing (600–830 s), both Roll Calls and the Last Stand stay exactly where today's code expects them.
  - Roblox players drift away from long rounds (PlayabilityPlan P1 and P10).
- **The tension.** The owner chose this pacing on 12 November (ArenaV3's decisions), but their design direction of 14 November says the area "should not shrink too quickly".
- **The 18-minute switch** (`Config.Round.Extended`, ArenaV3 §6.6):
  - the extra 3 minutes go into day one;
  - stage 1, and everything after it, moves 3 minutes later.

  It is built in Phase 1 and tested in the first playtests, Map 2 first (§4.11). Telemetry decides between the two.
- **Small rounds run faster** (PlayabilityPlan B3's head-count clock): a round of 2 runs about 6:50, a round of 4 about 7:30, and a round of 8 about 10:00. The Director's slots scale with the clock.

### 3.15 Small rounds, practice and the Drill

- **The start ring.** r0 = clamp(1,800 × √(N/24), 520, 1,800), as ArenaV3 re-bases QW3.
- **Loot** scales at one placement per three tributes, and mutt packs scale with the head-count.
- **What always runs:** the rigged beds and the Garden Wakes.
- **Damage by head-count** (arena-events §5):
  - with 6–12 alive, zones are 130 studs at most;
  - with 3–5 alive, no mutts are released;
  - with 2, no new events start.
- **Practice** (one tribute): half damage, and the intro set.
- **The Drill.** For a player alone on a live server, a practice round runs the Drill (W&O §4.2) on Map 1:
  1. open the supply bag by your plinth;
  2. drink at the stream;
  3. climb the lone tree;
  4. shoot the practice daisy 40 studs away, and watch its fuse from safety;
  5. "READY · A FULL ROUND STARTS WHEN TRIBUTES ARRIVE".

  Until the Training Centre ships (R4), the Drill also keeps W&O's weapon steps: take a weapon from the rack, strike a dummy, throw a stone. After R4, those steps move to the Training Centre's stations.

### 3.16 The finale and one winner

- **Where it ends.**
  - The final closing slides its centre back to the horn (ArenaV3 §6.5).
  - The Last Stand (QW14, 13:50–14:45) closes on the middle of one mouth lane, at r about 100 on a seeded mouth: open turf between two teardrop beds, at the foot of the bronze steps. It's the film's bloodbath ground.
  - `ArenaService.pickFinalCenter` reads Map 1's `LastStandPoints`.
- **No hazards in the Last Stand.** No blast ever takes the last two at once, and the border never takes the last tribute.
- **One winner.** On a timeout, the healthiest tribute wins.
- **The winner's shot** (I, after the book's ending).
  - The camera pulls straight up from the winner, about 900 studs in 6 s, until the valley reads as the eye.
  - The skyline meshes and canopy shells are Persistent, so the eye reads even past the streaming radius.

### 3.17 Goal lines and death tips

These follow WeaponsAndObjectives §3.9's format. The danger lines outrank everything else.

| When | Line (PC and gamepad) | Phone |
|---|---|---|
| On a lit bed, or within 4 studs of one | STEP OFF THE FLOWERS · 3 | OFF THE BED |
| Sick | SICK · [4] CHARCOAL TABLET, or SICK · DON'T DRINK THERE AGAIN | SICK |
| Being dived at | BIRDS · STAND STILL OR GET UNDER TREES | STAND STILL |
| In the eruption's zone | LEAVE THE MOUNTAIN · 120 m, or, under rock, STAY UNDER THE ROCK | LEAVE THE MOUNTAIN |
| Within 30 studs of the field | THE FIELD · DON'T TOUCH IT | DON'T TOUCH |
| Thirsty while it rains | DRINK THE RAIN · LOOK UP AND [E] | DRINK THE RAIN |
| Thirsty (new players only) | FIND CLEAN WATER · 140 m | CLEAN WATER · 140 m |
| Hungry, with a rabbit in view (new players only) | A RABBIT · HUNT IT FOR FOOD | HUNT IT |
| Full set: in the pollen | WALK OUT OF THE POLLEN | OUT OF THE POLLEN |
| Full set: hunted by squirrels | SQUIRRELS · INTO THE WATER 40 m · OR DROP FOOD | INTO THE WATER |
| Full set: in the swarm | SWARM · FIRE OR WATER · OR JOG AWAY | SWARM |
| Full set: near the fire | GET CLEAR OF THE FIRE · PATH 30 m | CLEAR OF THE FIRE |
| Full set: in the gas | GAS · GO UPHILL, UPWIND | GET OUT |
| Full set: lit by a searchlight | YOU'RE LIT · GET UNDER COVER | GET UNDER COVER |

**Death tips, shown the first time** (they extend QW4's tips; every number comes from the data)

| Cause | Tip |
|---|---|
| Bloom | The flower beds are rigged. A metal daisy fizzes for 3 seconds before it blows: step off the bed. The lanes in front of {HORN}'s mouths have no beds. |
| Foul | That water was foul. A still rabbit or a silent bank means poison. Charcoal tablets clean a bottle, and rain is always safe. |
| Flock | The red birds dive at movement in the open. Stand still, or get under trees or rock. |
| Eruption | When the mountain wakes, leave its slopes. Rock overhead stops what falls. |
| Field | The field bites when you touch it. |
| Rebound | The field throws back whatever is thrown at it. |
| Pollen | Big nodding flowers breathe poison. Walk round the mound, and keep upwind. |
| Squirrel | Squirrels climb but never swim. Step into any stream, or throw them your food. |
| Swarm | Fire burns the swarm, and water sheds it. They're slower than your jog. |
| Fire | Fire runs downwind through gorse and heather. Cross a path, a stream or bare rock: it can't. |
| Gas | The gas sinks and drifts with the wind. Go uphill and upwind. |

### 3.18 Colour on Map 1

- **The base palette** is the brief's §1.10: sky, haze, three grass tints, needles, broadleaf, bark, forest floor, gorse, heather, the five bed colours, the teardrops, the spiral, the hedge, limestone, scree, the lake, the horn, the platform, the plinths and the rims.
- **Pass 2's colour fixes** (critic #4 and #7):
  - **Haze and cloud.** The haze and the cloud slab brighten and grey the whole frame. Pass 1's matches measured about 0.45× the film's saturation and 30–40% brighter. Pass 2 thins the haze and replaces the slab (§3.3), and every match must pass §7's band.
  - **The meadow** is painted in the brief's three grass tints, in broad patches. Every pass-1 render showed one flat tint.
  - **Decorative flowers** are sparse, small and muted: "small accents, only where they mean forage" (ArtStyle §7).
    - The stream's wildflowers become muted blue (120,130,156) and muted yellow (178,170,110).
    - The full bed palette belongs to the hazard beds and the berms only.
    - If decoration and rigged beds shared a palette, nobody could learn "step off the flowers".

**Additions to the palette**
- tall pale grass (138,140,96);
- lupins (120,104,168);
- the rabbit (142,124,104), with a belly of (210,200,184).

**Hazards, creatures and effects** (sampled, then softened; the samples are trimmed means)

| Element | Sampled from the frame | The tone we paint | Notes |
|---|---|---|---|
| Fuse daisy petals | #ac9358 (T2 @126.2 s) | #c4a44c, satin metal (metalness 0.6, roughness 0.45) | Reads against the buttercup beds by its shape and sheen |
| Fuse daisy centre | — | Copper #b07046 | The same as the plinth tops: "a start, a fuse" |
| Fireball | #d78039, #943605 (T2 @127.4 s) | A flame ramp: (255,214,150) → (232,140,72) → (150,62,30) → smoke (90,86,84) | Emissive; light, not paint |
| Smoke | #2f3940, graded teal | (88,90,92), neutral | The grade taken out |
| Scorched ground | #473932 (T1 @113.8 s) | An ash scatter of (72,62,54) | Never below luma 40 |
| Butterflies | #3b779c (T2 @114.2 s) | Wing tops (70,126,186), undersides (44,74,110); the charge flash (236,244,255) | A signal |
| Crimson birds | #83141f (T2 @135.4 s, graded) | Body (184,58,70); a steel needle beak (226,214,206) | A signal |
| The spiral (bee balm) | #6a2930 (T2 @55.9 s) | #962c38 | A signal |
| Pollen haze | — | (216,192,112), transparency 0.7 | A signal |
| Golden squirrels | — | Fur (196,160,82), belly (220,200,150), a copper eye glint (176,112,70) | A signal |
| The eruption's fountain | #d87a49 (IMAX) | An emissive ramp (255,200,140) → (220,96,40) | — |
| Gel / glassy crust | — | Core (232,104,44), skin (120,40,20) / crust (84,82,86), roughness 0.25 | The crust is the one glassy surface outdoors |
| Ash (the book's "clear, sparkly") | — | (232,236,240) sparkle, transparency 0.6 | — |
| Tear gas | — | (168,176,152) | — |
| The field's ripple | — | Hexagons (214,230,234), transparency 0.85; a flash of (240,248,250) | Not neon blue |
| Hatch strobe | — | Emissive (200,48,40) | A signal |
| Searchlights | #82b1d2 (IMAX) | Light (206,222,236) | — |
| Plaques | — | Brass (170,136,80) | — |

**The lighting looks**

| Look | Values | Notes |
|---|---|---|
| **Day** | The brief's §1.7: Atmosphere Density 0.30, Offset 0.22, Colour (204,212,218), Decay (120,134,150), Haze 1.4 (pass 2 tunes it against the band), Glare 0.35. Clouds Cover 0.55, Density 0.45. ColorCorrection Contrast 0.06, Saturation −0.02. A soft cloud bank on the flanks at y 250–400, and mist in the hollows in the morning. | The south view is backlit at noon |
| **Golden hour and night** | DayCycle's looks | A standing tribute reads at 60 studs in greyscale (B7) |
| **The eruption** (in over 8 s, held, out over 20 s) | Tint (255,236,222), Brightness +0.03; Atmosphere Colour → (122,96,86), Decay → (96,64,52), Density +0.04; clouds → (196,170,160), as if lit from below; Bloom 0.6 → 0.9 | Lit through the lighting, never orange-teal, and never with real lights |
| **Dawn rain** | Clouds Cover 0.92, Density 0.75; Atmosphere Density 0.44, Haze 2.6, Glare 0; Saturation −0.08, Brightness −0.04; `GlobalWind` × 1.6 | — |
| **Inside the gas** (only for those inside it) | Blur 6; Tint (220,228,206) | — |

### 3.19 Phone budgets on Map 1 (ArenaV3 §7)

| Measure | Cap | Map 1's main cost | How we keep under it |
|---|---|---|---|
| Server models and instances | ≤ 90k models, ≤ 400k instances | North Wood trees and scrub | Density zones; each device places its own ground cover |
| Any streamed disc (r 1,024) | ≤ 30k models, ≤ 130k instances | The disc round the horn: the meadow, the wood's edge and the lake | The meadow is light (a clump every 40–80 studs). The launch, with 24 devices streaming that disc, is the binding case. |
| Fighting range (any r 300 disc) | ≤ 7k models | The heart: about 130 models | Trivial |
| Triangles drawn at the worst views | High ≤ 5M, Medium ≤ 3M, phones ≤ 1.5M and ≤ 800 draw calls | Views across the meadow to the wooded slopes | Far meshes past about 250 studs; canopy shells past about 900 (420 on Low); haze from 500; Persistent skyline meshes |
| Client memory | ≤ 1.2 GB; PlaceMemory ≤ 650 MB; ≤ 160k instances | The plinth just after the launch | §9.6 |
| Terrain graphics | ≤ 110 MB | The steep south and the lids | Crags and the peak are meshes |
| Textures | ≤ 160 MB; ≤ 12 terrain material sets | About 18 new 1,024 sets (about 70 MB); 10 terrain slots | Drop to 512 px if the phone test is tight |
| Effects | ≤ 28 emitters near the camera on High, ≤ 12 on phones | Fire and the eruption | `FxBudget` (§6.7); the eruption lights the valley through the lighting |
| Server time | Fire ≤ 0.5 ms at 2 Hz; mutts ≤ 1.5 ms; hazard checks ≤ 0.3 ms | — | Heartbeat stays at 55 Hz or more with 24 players |

- **The heart at full detail** is about 135k triangles: under 3% of High's budget.
  - The horn and platform: about 21.5k.
  - The 48 plinths: one shared mesh.
  - The 18 beds: each with a 300-triangle far mesh past 300 studs.
- **Where we measure, on a real 3 GB Android:**
  - a plinth at the launch, with 24 clients;
  - the Shoulder Cairn, with the whole eye in view;
  - the Edge, looking south;
  - the densest cell of the North Wood;
  - the eruption night;
  - the Garden Wakes.

### 3.20 Game 1 is done when

- **The build passes its checks.** Every TerrainGen and Populate check passes, and Audit passes its gate (§9.3–9.4).
- **It runs on a phone.** A 3 GB Android holds 30 fps at a plinth during the launch with 24 clients, and on the eruption night.
- **The look.**
  - The overview shows an open valley, with no concentric ring.
  - The T1 @1.7 s and @40.2 s matches show hillside and layered peaks behind the horn.
  - Every match passes §7's colour band.
- **The pace.** In tests with 4 and with 8 clients, the median time to the first encounter is 3:00 or less (QW3's test).
- **New players learn.**
  - They have no thirst deaths in their second and third rounds.
  - At least 70% of tributes caught in each hazard survive it.
  - In intro rounds, the rigged beds down no more than 10% of a lobby.
- **The valley works.** A tester climbs every climbable tree without a prompt, and a hunted animal shows no blood and fades into food within 2 s.

---

## 4. Game 2 on Map 2: the Clock

*Sources:*
- *brief §3;*
- *the owner's reference `map2_clock_arena_reference.png`, a fan-made "sector trap overview";*
- *the book's chapters 22–24 (LitCharts, Shmoop, SoftSchools);*
- *the real set seen from the air (theblaze.com, slashfilm.com).*

*Map 2 is* Catching Fire*'s arena, the second film's: "like the second map of the original hunger games movie where the map is a clock". It opens after one round of Map 1.*

### 4.1 Its size, said plainly (decision 1)

**What was built**
- The rendered Map 2 is **your guide at 1×**: R 2,600 studs, 1.46 km across, measured with the guide's own scale bar.
- That is about twice Map 1's area (21.2M square studs, against 10.2M).

**Why the brief called it "3×"**
- The lagoon that was really built for the film was roughly 120–170 m across.
- Three times that is your guide's lagoon, about 500 m.
- So R 2,600 is "3× the film" only by that reading. It is not three times your guide.

**What a bigger answer would cost**

| Reading of "3 x bigger" | Across | R (studs) | Area against Map 1 | What breaks |
|---|---|---|---|---|
| **Your guide at 1× (recommended)** | 1.46 km | 2,600 | 2.1× | Nothing: it fits every budget, and one 75-second hour per sector gives a full hour's warning |
| 3× the "about 1 km" first read off the guide | 3.0 km | 5,360 | 8.9× | <ul><li>ArenaV3's grids and scatter caps.</li><li>The jungle would have to be about a ninth as dense.</li><li>Rivals would average about 1 km apart.</li><li>An hour would need about 2 minutes, so a round would take about 24 minutes.</li></ul> |
| 3× your guide, as measured | 4.35 km | 7,770 | 18.6× | Can't be built at our quality. Phones can't hold it, and 24 players would rarely meet. |

**If you still want it bigger**
- Name the size.
- We will build a trial at that radius in the workbench, run `Audit.report` and the 3 GB phone test, and come back with **the largest radius that actually passes**, not an estimate.
- Every layout value is a fraction of R, both in the Blender generator and in the game's data, so a new R is a re-export and a re-import.
- Map 2's second Blender pass waits for your answer. Nothing else in this plan does.

### 4.2 How the clock runs

**One round is one turn of the clock.**
- The arena's day runs from **noon at the start signal to midnight at 15:00**, so **each arena hour lasts 75 s**.
- Each sector's horror fires once, in order, starting with the storm in the 12-to-1 sector.
- That follows the book: lightning at noon and midnight, and one horror per section for one hour (L: SoftSchools, Shmoop).
- **The sun follows the dial**, so you can read the hour from the sky:
  - noon overhead at the start;
  - golden light from 16:00 (5:00 on the round's clock);
  - sunset at 18:00 (7:30);
  - the moon at 19:15 (9:04);
  - midnight at the end.
- **One exception: the vigil.** While the fallen are shown (from 9:19), the sky slows down, then catches up by 15:00. The `DaySchedule` keys are {0 s, 12.0}, {559 s, 19.45}, {629 s, 20.2} and {900 s, 24.0}.
- **The dial itself never pauses.** It's the rule players learn.

| Hour | Starts | Sky | Sector that fires | Its hazard (default) |
|---|---|---|---|---|
| 12 | 0:00 | 12:00 | 12 to 1 | The storm: the start signal |
| 1 | 1:15 | 13:00 | 1 to 2 | The red rain |
| 2 | 2:30 | 14:00 | 2 to 3 | The fog |
| 3 | 3:45 | 15:00 | 3 to 4 | The troop (monkeys) |
| 4 | 5:00 | 16:00 | 4 to 5 | The birds (jabberjays) |
| 5 | 6:15 | 17:00 | 5 to 6 | Quickmud (ours) |
| 6 | 7:30 | 18:00 | 6 to 7 | The beast |
| 7 | 8:45 | 19:00 | 7 to 8 | The false sun (ours) |
| 8 | 10:00 | 20:00 | 8 to 9 | Falling timber (ours) |
| 9 | 11:15 | 21:00 | 9 to 10 | The crab tide (ours) |
| 10 | 12:30 | 22:00 | 10 to 11 | The wave and the surge |
| 11 | 13:45 | 23:00 | 11 to 12 | The swarm (insects) |
| 12 | 15:00 | 24:00 | 12 to 1 | The midnight storm: the end |

**Why this shape**
- **Not two laps.** With 37.5-s hours, the warnings would fall below arena-events' 15–30 s, and the fog and the wave would have no time to move.
- **No random start hour.** Starting at 12 is what makes the film's order work:
  - its jungle horrors (hours 1–6) land mid-round, while people are spread through the jungle;
  - its water horrors (hours 9–11) land at the end, once the border has closed onto the lagoon;
  - and the storm frames both ends.
- **Enough time to get out.** A 75-s hour gives everyone a full hour's notice. A jog covers 975 studs in that time, and the farthest anyone can be from a sector's edge is 673.

**What a sector is**
- **The hour lines.** The 12 spokes, their landing spurs on the beach, and the stony gullies that carry them on up to the dome are the clock's hour lines.
- **Sector h** is everything between hour line h and hour line h+1, going clockwise: its slice of lagoon, its two plates, its stretch of beach and its wedge of jungle. So 12-to-1 is 0°–30°.
- **Only inside the border.** A hazard only hurts inside the border. Outside it, the hazard's look still plays: from the island you watch the wave come down sector 10's hillside under the moon.

**Warned three ways**
1. **The dial, a full hour ahead.**
   - A 12-segment ring sits in the HUD's top band, left of the compass: 64 px on PC, 48 on phones.
   - It shows the hand, the live sector (in the ember accent, outlined), the next sector (pulsing in its last 20 s), the finished sectors (dimmed), and your own bearing as a dot.
   - Under the compass: "SECTOR 4 · {SECTOR NAME}".
   - An unseen hour (5, 7, 8 or 9) shows "?" until it is next.
2. **20 s before its hour.**
   - The hazard's own sign appears in the world: a cloud deck, a fog bank, a silence, wheeling birds or darkening sand.
   - A card names it, for example "THE FOG · SECTOR 2 · 0:20", with a compass marker and the NEXT line.
   - Damage then ramps up. It never starts at full strength.
3. **On the hour.**
   - A deep chime (our own sound) rings across the arena.
   - A shimmer runs up the dome along the new sector's two hour lines. You can see it from anywhere, even under the canopy.

**The one rule: run against the clock**
- Danger moves clockwise. The sector that has just cleared stays safe for the next eleven hours.
- So the shortest safe move is usually anticlockwise, across the nearest hour line.
- The hour lines themselves are the best place to wait out an hour: open, stony gullies, one step from either side.

| r | Sector width | Middle of a sector to its edge | At a jog |
|---|---|---|---|
| 1,000 (the beach) | 524 | 259 | 20 s |
| 1,400 | 733 | 362 | 28 s |
| 1,800 | 942 | 466 | 36 s |
| 2,600 (the dome) | 1,361 | 673 | 52 s |

**Fairness, every hour**
1. **Two warnings.** A full hour ahead on the dial, and 20 s ahead in the world.
2. **A counter within reach.** Every hazard has a counter within 150 studs of any point in its zone: shelter, height, water, keeping moving or staying still.
3. **Damage ramps up.** Someone at full health who reacts within 10 s loses at most about 25. Someone who ignores a hazard can die (Roadmap decision 1).
4. **Never personal.** A hazard aims at a place. Creatures pick prey the way the mutt brain does: the loud, the alone, the idle.
5. **One live sector at a time.** The next sector's warning signs overlap only the last 5 s of the previous one clearing.
6. **The same information on every device.** No warning depends on colour alone.
7. **Scaled to who's left:**

   | Alive | What runs |
   |---|---|
   | 13 or more | Full size |
   | 6–12 | Creature groups at ×0.7 |
   | 3–5 | No new creature attacks; the zones, the surge and the swarm still play |
   | 2 | Only the surge, the swarm and the final storm |
   | Practice | Half damage |

8. **Kill credit.** A hazard death within 15 s of a hit goes to the hitter.
9. **13+.** No gore, no remains and no blood on anyone. No jump scares: every creature growls or screeches before it strikes. No mimicked voices.

**Teaching it, in your first Clock round** (working wording)

| When | What you see |
|---|---|
| On the plate | The goal line: SWIM FOR {HORN} · OR RUN YOUR SPOKE TO A PALE FLAG (phone: HORN OR FLAG). Under the countdown: THE STORM COMES FIRST · SECTOR 12. |
| 1:15 | A card, for first-timers only: IT'S A CLOCK · Each hour one sector turns deadly · Watch the dial |
| The first time you're in the next sector with 20 s or less to go | RUN AGAINST THE CLOCK · LEAVE SECTOR 5 · 0:18 |
| The first time you look at the lagoon while thirsty | SALT WATER · IT WON'T QUENCH YOUR THIRST · FIND A SPRING OR TAP A BOTTLE PALM |

### 4.3 The map plan

**The frame**
- **The play radius is R 2,600** (decision 1).
- **The dome stands at R.** It is the force field and the outer wall.
- **Beyond it:**
  - invisible Boundary walls at 2,610;
  - jungle terrain out to 2,900, for looks only;
  - a low horizon-ring mesh of distant jungle hills at 3,200–3,600, under haze.
- **There is no mountain wall.** The dome is the wall.

**A section from the centre out**
```
r   0 ── 62 ── 120 ── 210 ───── 520 ──────── 910 ── 1,090 ───── 1,500 ───── 2,100 ───── 2,600 ── 2,900
    deck  apron rocks plates    tide stones  beach   lower jungle  middle      upper        dome    visual
y   46    42-45 →34   36.0      36.5         34→40   40→110        110→195     195→260      │       jungle
    └─ the island ─┘└──── the salt lagoon: floor 10 (24 deep) to r 350, 20 at r 600, 30 at r 860 ────┘
    the 12 spokes run r 120 → 910 along 0°, 30°, …; their gullies carry the hour lines on up to r 2,600
```

**Regions**

| Region | Where | Heights (y) | What's there | Tag |
|---|---|---|---|---|
| **The island** | r 0–120; a rock skirt to 135 | Deck 46 (inside r 62); apron 42–45; the skirt down to the water | <ul><li>The horn on the deck. The deck is the part that turns.</li><li>6 rack spots on the apron, and 12 spoke roots.</li><li>Dark, jointed lava rock (§4.16).</li></ul> | C (the island), I |
| **The horn** | On the deck, 90 long north to south; its tail points to 12 and its mouth to 6 | Shards 40 tall at the mouth and 12 at the tail; the floor in three 1.5-stud steps | <ul><li>10–14 faceted steel shards splayed outwards (one design, §4.16).</li><li>8 alcoves.</li><li>Two warm lamps in the mouth, so the night finale reads.</li></ul> | C (film still and concept art), L (tail to 12), I |
| **The plates** | 24 at r 210, at bearings 7.5° + 15° × k | Tops at 36.0, on columns from the floor | <ul><li>27 studs from the nearest spoke, 55 from the next plate, 90 from the island.</li><li>They stay up all round, as perches.</li></ul> | C (plates in the water), I |
| **The lagoon** | r 0–910 | Water at 34; floor 10 to r 350, 20 at 600, 30 at 860 | Salt water, a swell, surf on the island rocks, darker weed patches | C, L (salt) |
| **The Shallows** | Sector 9, r 760–900 | Floor 32–33, so 1–2 deep and wadeable | A sand bar, reef rocks, and rock pools with shellfish | I |
| **The spokes** | 12, along 0°, 30°, …; r 120 to the shore (760–830) | Deck at 35.6, 1.6 above the water; a swimmer can climb out up to 3.8 | <ul><li>10 wide, of tumbled lava rock.</li><li>A root on the apron, and a landing spur on the beach.</li><li>An hour marker of our own design on each landing rock (§4.16).</li></ul> | C (three on the set), L (twelve), I |
| **The tide stones** | Midway along each spoke, r 505–535 | Top at 36.5; boulders up to 43 | <ul><li>22 wide, with 2–3 boulders giving cover 4–7 high.</li><li>A pale runner's flag on a 14-stud pole.</li></ul> | I |
| **The beach** | r 910–1,090 | 34 → 40 | Sand, with a wet band to 950; driftwood; shrubs along the top; a camp in the middle of each sector | C |
| **The hour lines** | 0°, 30°, …; r 1,090–2,600 | Gullies 12–20 wide and 4–10 deep | Open stony floor, and gaps in the canopy that you can see from the island | I |
| **The lower jungle** | r 1,090–1,500 | 40 → 110, folded | The densest jungle: most of the sites, the bottle palms and the shelters | C (palm jungle), I |
| **The middle jungle** | r 1,500–2,100 | 110 → 195; ravines 10–30 deep | Canopy giants, springs, ridges | I |
| **The upper jungle** | r 2,100–2,600 | 195 → 260; crags to 300 | Thinner and rockier; the Fog Shelf; the head of the Wave Channel | I |
| **The lightning tree** | 15°, r 1,220 | Base about 60; crown about 240 (180 tall) | Bleached and split. It stands above the canopy as seen from every plate. | L (the tree in sector 12), I (its place) |
| **The dome** | r 2,600 | — | Invisible until touched; the flaw is somewhere on it | L, I |

**Already in Blender pass 1:**
- the sectors lie between the spokes, as in your guide and the book;
- the gullies continue the spokes;
- the lightning tree stands at 15°, in the middle of the 12-to-1 sector;
- the plates are at r 210.

**Still owed by pass 2** (Game 2's changes 3–7):
- a tide stone on each spoke;
- each sector's landforms, placed inside the border at its hour;
- shelters: 12 each in sectors 1 and 7, and 4–6 elsewhere;
- 3–4 climbable giants per sector, with rest forks no more than 45 studs apart;
- terrain to r 2,900 only, then the horizon ring.

### 4.4 The twelve sectors

**What every sector has:**
- a beach camp at its middle bearing;
- two lower sites and one middle site;
- one spring (6 of the 12 flow each round);
- about 10 bottle palms;
- 3–4 climbable giants;
- 4–12 shelters.

**What makes each one different.** The "seen from the island" column is new in pass 2 (§4.16): every sector gets one silhouette and one canopy tint, so you can read the clock from the world, not only from the dial.

| Sector | Bearings | Working name | Hazard | Its ground | Seen from the island |
|---|---|---|---|---|---|
| 12 to 1 | 0–30° | The Storm Wedge | The storm | A scorched clearing round the lightning tree; Strike Ridge, a bare spine along 15°; 4 storm pools | The bleached lightning tree, 180 tall; a grey, scorched canopy |
| 1 to 2 | 30–60° | The Red Steps | The red rain | A stepped ravine along 45° with rock shelves; 12 shelters; the Overlook | Red-earth scars in a bronze-tinted canopy |
| 2 to 3 | 60–90° | The Fog Shelf | The fog | A basin at the rim where mist pools; the Giants' Stair, 4 climbable giants along 75° | A pale fringe of ghost trees at the rim, and the four giants |
| 3 to 4 | 90–120° | The Fig Grove | The troop | Giant strangler figs with a canopy at 70–90; the Quiet Path along the top of the beach; Troop Rock | The darkest canopy: domed fig crowns |
| 4 to 5 | 120–150° | The Rookery | The birds | Bleached dead snags 40–70 tall; Echo Hollow; a nest platform 30 up the tallest snag | White snags, and basalt pinnacles above the canopy |
| 5 to 6 | 150–180° | The Creek Flats | Quickmud | A tidal creek mouth across the beach at 165°; mud gullies; the Root Bridge; the Mud Terraces | A mud fan and mangroves |
| 6 to 7 | 180–210° | The Scored Wood | The beast | The darkest canopy, with claw-scored trunks; the High Rocks, boulders 7–12 high; the Flattened Glade | A gorge mouth and dark giants |
| 7 to 8 | 210–240° | The Red Bank | The false sun | An open red-earth bank above the beach; the Shade Rocks; 12 shelters; Sun Crag | The open red bank, with fan palms |
| 8 to 9 | 240–270° | The Tall Stand | Falling timber | The tallest palms, 55–65; the Nut Grove; the Leaning Ridge | Emergent palms above the canopy |
| 9 to 10 | 270–300° | The Shallows | The crab tide | The sand bar and reef in the lagoon; the Rock Pools; the biggest tide stone | The lava reef shelf and a coconut grove |
| 10 to 11 | 300–330° | The Wave Channel | The wave | A smooth channel 300 wide along 315°, from the rim to the beach, with ridges 30–40 higher on both sides; the Breakwater; a rock trough you can slide down | A bare, scoured stripe down the hillside, with flattened palms |
| 11 to 12 | 330–360° | The Hives | The swarm | Dense, dark jungle with clay hive spires 8–15 tall; the Great Spire | Ochre clay spires |

### 4.5 The hazards

- **Every hour runs the same cycle** on the Gamemakers' engine:
  - its warning signs from 20 s before the hour;
  - active from the hour, usually until 50–55 s past it;
  - clearing by 60 s past;
  - then quiet until the next hour.
- **New damage causes:** Lightning, RedRain, Fog, Troop, Quickmud, Beast, Heat, Timber, Crabs, Wave, Swarm, Dome, Geyser, Riptide and Sting.

| Hour | Hazard | Its tell | What it does | The counter | Fairness and 13+ |
|---|---|---|---|---|---|
| 12 | **The storm** (L) | Seen from the plates during the countdown: a black cloud deck over 0–30°, the tree's crown crackling blue, thunder | <ul><li>The tree is struck at 0, 25 and 50 s past the hour. Each strike has a 3-s build: the trunk glows, a hum rises, and a blue ring of 25 studs lights the ground. It does 60 at the trunk and 20 at the ring, with a knock-down.</li><li>Every 3 s, one exposed contender in the sector (on the beach, a ridge or a clearing, not under canopy) gets an 8-stud ring at their feet for 2 s, then a bolt: 35 at the centre, 10 at the edge. Nobody gets a ring more than once every 8 s.</li><li>A wet storm fills the 4 storm pools.</li></ul> | Get under the canopy, off the beach and ridges, and away from the tree. Step out of a ring. | A ring gives 2 s, and most of the sector is canopy. A flash and a knock-down, with no burns. |
| 1 | **The red rain** (L) | The cloud deck turns rust-red; heavy drops spatter the leaves; a drumming rises | <ul><li>Heavy **rust-coloured** rain over the sector's land, and you can see only about 50 studs.</li><li>In the open: 1 a second for 10 s, then 2. Dense canopy halves it. Stone, a hollow, or wading in the lagoon stops it.</li><li>A rust tint stays at the edges of the screen until you wade into salt water.</li><li>The sector's spring runs rust and undrinkable for the rest of the round.</li></ul> | Cross an hour line; get under one of the 12 shelters, none more than about 150 studs away; or get into the lagoon. | <ul><li>Rust (#7a4026 on surfaces), not the brief's darker red, so it can't read as blood (critic #17).</li><li>Surfaces lose the tint in 60 s, and nothing marks a character.</li><li>A darker red comes back only if the maturity questionnaire's blood questions clear it and you want it.</li><li>All 50 s in the open costs 90; reacting within 10 s costs about 10.</li></ul> |
| 2 | **The fog** (L) | A milky bank forms along the start line; birds burst out of the canopy; a long hiss | <ul><li>At the hour the fog pours **downhill** at 12 studs/s for 55 s, to about r 1,340, then lifts. It never reaches the beach, and never flows uphill. It is 30 studs deep.</li><li>Its front is a thin edge with no damage.</li><li>Its core does 1 a second, rising to 3, and leaves you Fogged: stamina returns at half speed, and you can't sprint for 8 s after you leave unless you wash in salt water.</li></ul> | Stay ahead of it downhill (a jog is 13); go uphill past the start line; step out sideways; climb a giant above 30 studs; wash in the lagoon. | Anyone who moves when the signs start never enters the core. No blisters: a pale vignette, a cough and a status icon. |
| 3 | **The troop** (L) | Chattering swells, branches shake, the troop gathers in the Fig Grove's canopy | <ul><li>In its zone, you set off an attack if you sprint, fight or shoot, or if you linger more than 4 s under a tree with monkeys in it.</li><li>A screech and a branch snap give 1 s of warning. Then 3–5 monkeys drop and bite for 6 each (at most 3 at once), and chase at 17 studs/s for 12 s.</li><li>At most 2 groups at once. A monkey has 20 health.</li></ul> | Walk or crouch through without stopping. Sprint for the sand or the water. Fight back with sweeps. | They leave alone anyone under 25 health who hasn't attacked them. No new groups once 3 or fewer remain. They look engineered but believable, with one wrong trait. |
| 4 | **The birds** (L) | Black-grey flocks wheel over the Rookery; hour lines 4 and 5 start to shimmer; "SEALS IN 0:20" | <ul><li>A transparent barrier stands along both hour lines and across the waterline, out to the border, for 45 or 60 s. It blocks bodies and projectiles both ways.</li><li>Inside, the birds mimic the arena's own sounds round you: footsteps, a bow's creak, crate lids, splashes.</li><li>No damage.</li></ul> | Be out before it seals: the dial showed it a full hour ahead. Or slip in at the last second to shake off a chaser. Inside, trust your eyes. | <ul><li>Harmless.</li><li>If more than 40% of the living are inside, it seals for only 20 s.</li><li>No voices and no screams, and never the sound of a fallen contender.</li></ul> |
| 5 | **Quickmud** (I) | The sand darkens and glistens; bubbles; crabs scuttle away | <ul><li>Sector 5's beach, creek and gullies turn to mud: speed ×0.5.</li><li>Move slower than 6 studs/s for 2 s and you start to sink; after 4 s you're Stuck, taking 2 a second.</li><li>Tap Jump to struggle free (about 2 s), or anyone can pull you out.</li></ul> | Keep moving; get onto rock, roots or driftwood; go uphill; or leave. | It never kills on its own: the danger is a rival finding you stuck. You sink to the waist, never under. |
| 6 | **The beast** (L that it exists, I its look) | Sector 6's jungle goes silent; then heavy breathing, snapping branches and fresh claw marks | <ul><li>An unseen hunter stalks at 12 studs/s and charges at 18. You see only the plants bending, and a dark mass for 0.2 s when it lunges.</li><li>Each lunge has 1 s of warning: a growl, and the plants ahead bursting apart.</li><li>A hit does 30, then it pulls back for 8 s. Three hits drive it off for the hour.</li></ul> | Leave the jungle for the beach or the water; climb; stand on the High Rocks; stay in a group of 3 or more, which it won't approach. | A tribute at full health survives 3 lunges. It leaves the weak alone. No remains and no gore. |
| 7 | **The false sun** (I) | At dusk a white-hot disc rises over the sector's rim; heat shimmer; cicadas | <ul><li>Sector 7 blazes white while the rest of the arena falls into dusk.</li><li>In its light, out of shade, thirst drains 9× faster. Below 30 thirst, you also take 1 a second.</li></ul> | Shade, rock or the lagoon; drink; or leave. It's the only bright place in the arena for that hour, so fights gather there. | Slow, and you can see it coming. No burns. |
| 8 | **Falling timber** (I) | Trees creak and sway with no wind; leaves rain down | <ul><li>First, nuts and dead fronds fall. A 4-stud ring shows for 1.5 s, then the hit does 15, and coconuts are left behind.</li><li>Then 6–10 marked trees topple across the slope, never towards the water, each with 4 s of warning (a crack, a lean, dust at the root). Each crushes a strip 6 by 55 for 50 and a knock-down.</li><li>The fallen trunks stay as cover and bridges.</li></ul> | Get to open ground, the beach or a gully, and read the lean. Running for the water is always safe. | 50 can't kill a healthy tribute. A knock-down, with nothing crushed on screen. |
| 9 | **The crab tide** (I) | The water in the slice boils with shells; a clatter rises | <ul><li>A carpet of crabs pours onto every bit of land in the slice, the island and the spokes included. It spreads 120 studs inland at 8 studs/s, holds, then pulls back.</li><li>In the carpet: 2 a second and speed ×0.7, unless you stand on something at least 2.5 high.</li><li>Swimmers are left alone.</li></ul> | Get up on a boulder, a log, a plate, the deck or a tree; outrun it; swim. | Pinches only, no gore. |
| 10 | **The wave and the surge** (L) | A rumble 25 s ahead; birds flee; a white line rises at the rim; "THE WAVE · SECTOR 10 · THE LAGOON WILL RISE" | <ul><li>A wall of water 60–80 high runs down the Wave Channel at 35 studs/s. Anyone in it is swept to the beach and takes about 25.</li><li>About 37 s later, **the surge**: the lagoon stands 6 studs higher for about 20 s. The spokes and plates go under, and anyone on them is pushed off into deep water. The deck and the high rocks stay dry.</li></ul> | Be on the deck, the high rocks or inside the horn; don't be fighting on the spokes round 13:00. If you're swept off, swim. | The surge does no damage, and there's no drowning. In a full round you watch the wave come down the far hillside, which is your warning for the surge. |
| 11 | **The swarm** (L for the sound, I for the swarm) | Clicking rises from the Hives; dark motes lift from the spires; "THE SWARM · IT FINDS WHOEVER STANDS STILL" | <ul><li>It starts in sector 11, then hunts anywhere inside the border.</li><li>Anyone who has moved less than 15 studs in 6 s draws a cloud: a whine gives 3 s of warning, then it does 3 a second and follows you for 10 s.</li></ul> | Keep moving (40 studs shakes it), get into water, or stand within 12 studs of a fire or a lit flare. | It can't touch anyone who keeps moving. In the Last Stand it stops the last two or three waiting each other out. Dark motes, never insects on skin. |

**The wildcards.** Our own hazards, swapped in by the mix (§4.10):

| Wildcard | Where | What it does | Counter |
|---|---|---|---|
| **Riptide** | The lagoon | A current sweeps the slice's water clockwise at 6 studs/s; eddies drag swimmers under for 2 s at a time (2 a second while under) | Get onto a spoke, a plate or the shore |
| **Jelly bloom** | The lagoon | The slice's water turns milky, and faceted jellyfish sting swimmers for 3 a second | Get out of the water |
| **Salt geysers** | The beach and the lagoon | Vents go off in turn. Each gives a 2-s hiss and a steam ring, then a column 20 high: 25 damage, and a launch into the air. At most one near any contender every 6 s. | Step off the ring |
| **Ember Rain** (arena-events §4) | Land | In a circle of 90–150 studs inside the sector | Get under stone or into water, or leave the circle |

### 4.6 The island turns at sunset, and the horn restocks

| | |
|---|---|
| **The warning** | At 6:00, 90 s ahead: "AT SUNSET THE ISLAND TURNS · THE HORN WILL BE RESTOCKED". In the last 10 s, anyone on the deck sees "OFF THE DECK · THE ISLAND TURNS · 0:08". |
| **At 7:30** | A jolt throws everyone on the deck (r 62 or less) 15–25 studs outward, onto the apron or into the water, with no damage. |
| **During the turn** | <ul><li>For 15 s, a ring barrier stands at the deck's edge, built from the border's panels with collision on. **Nobody rides the turn.**</li><li>The deck and the horn turn by a seeded 90°, 150°, 210° or 270°, inside the island's fixed rock ring.</li><li>The 12 spokes meet the fixed ring, never the turning deck, so nothing has to line up with them.</li></ul> |
| **At 7:45** | The barrier drops, and the horn's floor opens: the restock rises with a bell. That is the Feast, open for 30 s: an alcove refill, or "by need" once W5 lands (half the living plus one, 8 at most). |
| **After it** | The horn's tail no longer points at 12, but the dial is still right. Trust the dial, not the horn. That's the book's moment, when the tributes lose track of which strip is twelve (L: LitCharts, SoftSchools). |
| **How it's built** | <ul><li>Anchored meshes, which the server steps 10 times a second along a shared timeline. Each device smooths the motion.</li><li>Nothing has to carry a character, which removes the physics risk the critic raised (#12b).</li><li>The jolt uses `HazardImpulse`, and the restock uses `LootService.refillHorn`.</li><li>**The fallback:** turn only the horn's shards, and keep the deck still.</li></ul> |

### 4.7 The dome, the border and the flaw

- **The dome** (L) stands at R. It is invisible until touched.
  - A touch does 20 (cause: Dome) and throws you back 12 studs, with a hex ripple that anyone within 200 studs can see.
  - Arrows and thrown weapons bounce back off it, the same rule as Map 1's field (§6.5).
  - Only the outer jungle meets it, so it matters only before stage 1 has closed.
- **The closing border** is drawn the same way, as an inner field. It follows ArenaV3's rules: it never blocks bodies, and it hurts you while you're outside it.
- **The flaw** (I, after the book).
  - A seeded 8 × 8-stud square wavers somewhere on the dome, 80–200 studs above the ground at the rim.
  - You can see it within 60 studs, or through field glasses.
  - It's a side goal: "FIND THE FLAW IN THE DOME". Shoot it for Favour and a parcel.
- **Parked for a longer mode:** Beetee's wire and the dome-breaking ending. A one-lap round has no later strike to use.

### 4.8 Fresh water

The lagoon is salt (L), so fresh water is the round's hidden fight.

| Source | Where | How many | Rule |
|---|---|---|---|
| **The lagoon** | r 0–910 | — | <ul><li>Salt. A sip gives no thirst, costs 3 health, and shows the salt-water hint.</li><li>Wading in it washes off the red rain's tint and the fog.</li><li>Never a goal marker.</li></ul> |
| **Springs** | One in a ravine in each sector, r 1,300–2,000 | 12, of which 6 flow each round | A dry spring shows damp moss |
| **Storm pools** | Sector 12, r 1,150–1,400 | 4 | They fill during a wet noon storm (2 rounds in 4), and stay full |
| **Bottle palms** (the film's water trees) | The lower jungle, r 1,100–1,700 | About 10 per sector, 120 in all | <ul><li>They need a **tap** (the film's spile). Hold [E] for 1 s to tap one, then drink (+10 a sip) or fill a bottle.</li><li>A tapped palm keeps trickling for everyone for the rest of the round, so it becomes a contested water point.</li></ul> |
| **Coconuts** | Under coconut palms on the beach and in the lower jungle | About 72, plus what falling timber drops | +12 thirst, +6 hunger |

- **About 12 taps a round:** 4 on the horn's racks, 3 at the spoke roots, a quarter of the runner's caches, and about 1 crate in 8.
- **The water marker** points only at fresh water. `WaterPoints` gains the kinds Spring, Pool and Tree, and the lagoon is Salt.

### 4.9 Loot

About 312 markers give about 330 items: 14 per contender, the same as ArenaV3 §6.1.

| Where | Markers | What they roll | Items |
|---|---|---|---|
| The horn's alcoves | 8 crates | Tier 3. One always holds a longsword (with 8 or more contenders). The rest roll padded armour, med kits, at most one more bow, special arrows, a rucksack, a fire kit, rope and field glasses. | About 24 |
| The apron racks | 6, at 30°, 90°, …, so every plate sees two | WeaponsAndObjectives §3.2's rack set, plus 4 taps | About 16 |
| The spoke roots | 12 tarps at r 112–125 | A water bottle, plus one of: a bandage, 2 throwing knives, 4 stones, a tap (on 3 of the 12) or a satchel | About 24 |
| The tide stones | 12 runner's caches with pale flags; 6 stocked each round | The runner's table: a weapon, a bottle and one roll; a tap in 1 of 4 | About 18 |
| The spoke landings | 12 | Tier 1 | About 7 |
| The beach camps | 48 | Tier 1 | About 50 |
| The lower sites | 96 | Tier 2 crates; tier 1–2 on the ground | About 95 |
| The middle sites | 48 | Tier 2 crates; tier 1–2 on the ground | About 50 |
| The prize spots | 6; 2 stocked each round | Tier 3 | About 6 |
| Trails and ravines | 64 | Tier 1 | About 40 |

All of WeaponsAndObjectives' caps still apply: at most 5 bows (no more than one per two contenders), at most 3 longswords, and one Legendary.

### 4.10 The per-round mix

Everything is seeded at the call, and logged. The clock stays learnable, but no two rounds are the same.

| Mix-up | What varies | How players find out |
|---|---|---|
| **The unseen hours** | Hours 5, 7, 8 and 9 keep their defaults, or swap for a wildcard that suits the hour: hour 5 can take any; hours 7 and 8 take salt geysers or Ember Rain; hour 9 takes the riptide, the jelly bloom or salt geysers. No swaps in 25% of rounds, one in 50%, two in 25%. | Each "?" on the dial is revealed one hour ahead |
| **The film hours' moods** | <ul><li>The storm is dry or wet; the red rain light or heavy.</li><li>The fog has one front or two; the troop is 20 or 40 strong.</li><li>The birds seal for 45 or 60 s; the beast is one or a pair.</li><li>The wave is single or double; the swarm thin or thick.</li></ul> | On each hour's card ("THE FOG · TWO FRONTS") |
| **The island's turn** | 90°, 150°, 210° or 270° | When it turns |
| **Fresh water** | Which 6 of the 12 springs flow, and whether the storm pools fill | In the world: damp moss, or a trickle |
| **Loot** | Which 6 tide stones carry a flag, which 2 of the 6 prize spots are stocked, and the Legendary roll at the restock | The flags can be seen from the plates |
| **The border's drift** | A seeded bearing, up to 150 studs | On stage 1's card |
| **Falling timber** | Which 6–10 trees are marked | By their lean |
| **The flaw** | Where it sits on the dome | By sharp eyes |

**The film's order never changes:** 12, 1, 2, 3, 4, 6, 10 and 11. That's what makes the clock a skill. A veteran knows the hours, but never the round.

### 4.11 The round timeline: 15 minutes, with an 18-minute switch

A full round of 24.

| Time | Sky | What happens |
|---|---|---|
| Before 0:00 | — | <ul><li>The teleport into the Clock place lands you in your red room.</li><li>The launch (§2) plays, and your plate surfaces in a burst of spray.</li><li>The countdown runs, with the dial at 12 and the storm deck building over 12-to-1.</li></ul> |
| 0:00 | 12:00 | The start signal, and the first strike on the lightning tree: **the clock starts**. Swim 27 studs to a spoke, then run in to the horn (about 9 s) or out to a flag (about 20 s). |
| 0:45 | — | The scramble ends. The tuning target: 25–40% of contenders down by 2:30. |
| 1:15 | 13:00 | Hour 1: the red rain |
| 2:15 | — | Stage 1's card |
| 2:30 | 14:00 | Hour 2: the fog |
| 3:15–6:05 | — | **Stage 1:** 2,600 → 1,800, the outer jungle |
| 3:45 | 15:00 | Hour 3: the troop |
| 5:00 | 16:00 | Hour 4: the birds; the golden light begins |
| 5:30 | — | Stage 2's card |
| 6:00 | — | The warning that the island will turn |
| 6:15 | 17:00 | Hour 5: an unseen hour (quickmud by default) |
| 6:30–7:40 | — | **Stage 2:** 1,800 → 1,350. The beach and the lower jungle stay inside. |
| 7:30 | 18:00 | Hour 6: the beast. Sunset: **the island turns**, and the restock opens at 7:45 for 30 s. |
| 8:45 | 19:00 | Hour 7: an unseen hour (the false sun by default), in the dusk |
| 9:19 | 19:27 | **The Fallen** in the night sky over open water: the grouped show, four busts at a time, about 70 s at most. The sky's vigil runs. |
| 9:30 | — | The final closing's card |
| 10:00 | 20:00 | Hour 8: an unseen hour (falling timber by default). **The final closing:** 1,350 → 35 by 13:50. |
| 11:15 | 21:00 | Hour 9: an unseen hour (the crab tide by default) |
| 12:30 | 22:00 | Hour 10: the wave on the far hillside, then **the surge** at about 13:07–13:37 over the spokes and the plates |
| 13:45 | 23:00 | Hour 11: the swarm, inside the border |
| 13:50–14:45 | — | The Last Stand on the island |
| 15:00 | 24:00 | Hour 12: the midnight storm. If more than one contender is still standing, the healthiest wins. |

- **The acts:**
  1. the Rise;
  2. the Scramble;
  3. learning the clock (0:45–5:00);
  4. the jungle (5:00–7:30);
  5. sunset and the island's turn;
  6. dusk and the Fallen;
  7. the closing night (10:00–13:50);
  8. the Last Stand;
  9. midnight and the victor.

  There's a beat every 1 to 1½ minutes.
- **Why 15 minutes.**
  - 12 hours × 75 s = 900 s, so one turn of the clock is one round.
  - 75 s is the shortest fair hour.
  - By 6:05, stage 1 has shrunk Map 2 to Map 1's whole size, so the middle and the end play at Map 1's pace.
- **The 18-minute switch** (`Config.Round.Extended`) gives 90-s hours, multiplying every time above by 1.2.
  - The critic pointed out that both maps close their outer half by 5–6 minutes, against the owner's "should not shrink too quickly".
  - So the first Clock playtests run both lengths, before Map 1's.
- **The Clock place's settings set the round's time scale to exactly 1.** Small rounds don't run faster here, because the hours must stay 75 s.

### 4.12 The border

| Stage | Card | Moves | Radius | Fastest point on the ground |
|---|---|---|---|---|
| 1 · the outer jungle | 2:15 | 3:15–6:05 (170 s) | 2,600 → 1,800, drifting up to 150 towards the seeded bearing | 5.6 studs/s |
| 2 · the middle | 5:30 | 6:30–7:40 (70 s) | 1,800 → 1,350, centre kept | 6.4 |
| 3 · the final closing | 9:30 | 10:00–13:50 (230 s) | 1,350 → 35, the centre sliding back to the horn | 6.4 |
| The Last Stand | — | 13:50–14:45 | 35 → 0, at a point 15–25 studs off the horn's flank | — |

- **The drift cap is 150, not ArenaV3's 200.** With 200, the far side of the final closing would move at 6.6 studs/s, over the 6.5 limit.
- **No stage moves during the Roll Call.**
- **The radius in the late hours:** about 920 at 11:15, 490 at 12:30, 290 at 13:05, 150 at 13:30 and 64 at 13:45.

### 4.13 Small rounds and practice

- **A smaller start.** r0 = clamp(2,600 × √(N/24), 1,300, 2,600).
  - The floor of 1,300 keeps the beach and a band of jungle in play.
  - Below r0 1,730, the circle's centre starts 0.25 × r0 towards the seeded bearing.
  - Every stage scales by r0 / 2,600.
- **The clock still runs.** A sector whose zone lies entirely outside the border plays only its look.
- **Solo practice.** "PRACTISE THE CLOCK" opens a reserved server for one player, with half damage and the full dial. It runs as a drill:
  1. swim to a spoke;
  2. open a flag;
  3. tap a bottle palm;
  4. outlast one hour;
  5. wash in the lagoon.

### 4.14 The finale and one winner

- **The surge** at about 13:07 drives everyone onto the island's high rock and into the horn.
- **The swarm** at 13:45 punishes anyone who stands still inside the shrinking ring.
- **The Last Stand** closes on the island. The border never takes the last contender, and a timeout goes to the healthiest.
- **The ending plays the midnight storm,** whenever the last rival falls:
  - behind the winner's card, the hand sweeps to 12, the storm breaks and the tree is struck;
  - the dome flickers;
  - the camera pulls straight up to show the clock face: the 12 hour lines, the lagoon and the island.

  It nods to the film's climax without copying its shot.

### 4.15 The unlock and the queue

**Where it's saved**
- `GreenLandRounds` joins `DataService.STATS`, and is saved as an additive change, the same safe scheme as `Wins`.
- `ClockUnlocked` means `GreenLandRounds` ≥ `Config.Modes.Clock.UnlockRounds` (1).
  - It's mirrored as a player attribute, for the interface only.
  - The server re-checks the saved counter on every queue request, and again on arrival in the Clock place. It never trusts teleport data.
- `ClockRounds` is counted alongside, for telemetry.
- Profile v2 (§10, Phase 9) carries both counters over later.
- **If your record fails to load,** the gate says so and stays locked.

**What counts**
- **The rule.** Your Green Land round counts when your part in it ends: you fall, you win, or the round ends. Leaving early doesn't count.
- **Practice rounds count,** so a lone beta player isn't locked out.
- **When counting starts.** It starts when the Green Land ships (R1). Rounds on today's arena don't count.

**What a locked player sees** (working wording)

| Where | State | What it shows |
|---|---|---|
| **The Clock Gate:** an arch with a 12-hour dial in the Training Centre, or on the interim lobby before R4 | Locked | The dial is dark, its hand stopped at 12. "{CLOCK} · LOCKED · Play one round of {GREEN LAND} to open it · 0 / 1" |
| The MODES card, for phones and gamepads | Locked | The same card, greyed out |
| The summary of your first Green Land round | Unlocking | An extra line: "NEW ARENA · {CLOCK} IS OPEN" |
| Back in the hub, once | Unlocked | A toast, "A SECOND ARENA IS OPEN · {CLOCK} · at the Gate"; the dial lights and starts ticking |
| The Gate | Open | "{CLOCK} · Twelve hours, twelve sectors · 15 min · 8–24 players · [QUEUE]", then "{CLOCK} QUEUE · 5 / 8" |
| A party with a locked member | — | "EVERYONE IN THE PARTY MUST PLAY {GREEN LAND} FIRST · [name] hasn't yet" |
| Before Map 2 ships | Anyone | "{CLOCK} · COMING SOON · Your first round of {GREEN LAND} already opens it" |

**Getting there**
- **The queue in each server** (R5).
  - Step into the Gate to queue. You keep playing Green Land rounds while you wait, and your ticket counts only while you're in the hub.
  - When 8 queued players are waiting between rounds, the server writes a match ticket (the roster and the seed) under a new ID in a MemoryStore, then calls `TeleportService:TeleportAsync` with `TeleportOptions.ReservedServerId` set to that ID. The first teleport with a new ID creates the server. (`ShouldReserveServer` and access codes are deprecated.)
  - Teleports run with retries and back-off.
- **If the queue hasn't filled after 90 s** (critic #13):
  - the pill offers "GO NOW · 3 QUEUED". That starts a smaller round with everyone queued, and its start ring scales down;
  - a player queued alone is offered "PRACTISE {CLOCK}" instead.
  - The pill always shows the live count.
- **On arrival,** `ModeService` reads the ticket. The call comes once the roster is in, or after 20 s.
- **The way back.** At the round's end, one teleport returns everyone to the start place's hub. The fallen can go back early.
- **Later,** queue v2 is modes-progression's cross-server `MatchService`.
- **The settings:** `Config.Modes.Clock = { UnlockRounds = 1, MinQueue = 8, GoNowAfter = 90, GoNowMin = 2 }`.

### 4.16 Look and readability: pass 2 (critic #11)

| # | What pass 1 shows | What pass 2 does |
|---|---|---|
| a | <ul><li>A uniform carpet of identical round crowns.</li><li>A "picket fence" of identical trunks along the beach (`compare_plate_rise.png`, `sector_reads.png`).</li></ul> | Production palms, canopy giants, tree ferns and understory at varied heights. Understory hides the line of trunks along the beach. |
| b | The twelve `sector_reads` panels are nearly indistinguishable, so nobody can read the clock from the world | <ul><li>One landmark silhouette and one canopy tint per sector, visible from the island and the beach (§4.4).</li><li>An hour marker of our own design on each spoke's landing rock: a lava-rock pillar carrying its hour in bronze, with a small lamp that lights at dusk.</li></ul> |
| c | In daylight the island reads as a beige stepped temple (`compare_film_horn_jungle.png`) | The brief's dark, jointed lava rock (#605c58), with the steps worked into the rock |
| d | The horn looks like two different objects: a horizontal claw of girders in one render, an upright dark crystal burst in another | One design, to brief §3.4: 10–14 splayed steel shards, the tail to 12 and the mouth to 6, rendered in daylight |
| e | Uniform radial ridges in the jungle's relief (the hillshade in `data_maps.png`) | Ridges and ravines of varied width and length, so the jungle stops reading as a turned dish |

**Also in pass 2:**
- the style A texture bakes (pass 1's manifest says "NOT baked");
- far meshes for the spokes;
- 12 canopy shells and the horizon ring;
- TimberPond's water level snapped to the voxel rule (182.25 breaks it);
- the jungle scatter, at about **0.5× Map 1's density**, proved by `Audit.report` (§4.18).

### 4.17 Colour on Map 2

The rule is §7's. Every value is checked in game at 14:00 and 17:30.

**Surfaces**

| Element | Tone | Luma | Note |
|---|---|---|---|
| The lagoon | `WaterColor` #266260, transparency 0.55, reflectance 0.6 | 85 | The Shallows look lighter only because sand shows through |
| Sand / wet sand | #c6bca0 / #968c74 | 188 / 140 | — |
| Lava rock (the island, the spokes, the tide-stone boulders) | #605c58 | 93 | Below the stone band on purpose; never darker |
| The horn's shards | #acaeae, metalness 0.85, roughness 0.4 | 174 | — |
| Palm fronds / canopy / tree ferns | #4c5c34 / #405630 / #465e38 | 86 / 79 / 86 | The leaf green channel is 86–94. The per-sector tints of §4.4 vary these by ±8%. |
| Trunks (palm, bottle palm, strangler fig) | #7e6e5a / #7c6c56 / #827462 | 110–118 | In the bark band, warm |
| Jungle floor | #60543e | 85 | In the forest-floor band |
| The hour-line pebbles | #8e8a7e | 138 | A pale seam you can see from the island |
| The Red Bank's earth | #8c6a4e | 111 | In the path band |
| The lightning tree and the Rookery's snags | #b0aa9c / #a49e92 | 170 / 158 | Bleached landmarks, above the band on purpose |
| The plates | Steel #969896, copper top #b07046 | 151 / 123 | The copper top means "your start", as on Map 1 |

**Signals and hazards** (the only saturated colour)

| Signal | Colour |
|---|---|
| Lightning bolts and rings | Emissive (224,232,255) |
| The red rain / its tint on surfaces | Rust streaks at low opacity / #7a4026 |
| The fog / its edge | #e0e2d6 / a faint sick yellow, #d8d4a0 |
| The false sun | An emissive disc (255,248,232), with shimmer |
| Quickmud | A wet sheen, #4a4034 |
| The birds' barrier / the dome's ripple | (170,200,220) at 0.85 transparency / hexagons (168,200,216) |
| Crabs / the swarm / the beast's glimpse | #9a5a3c / #2c2a26 / #2a2826 (luma 40, the floor for blacks) |
| Monkeys / birds | #965c34 / #404248, with a faint blue sheen |
| The wave's face / foam | #2e6c68 / #e2e6e4 |
| The dial | Theme tokens: ember for the live hour, muted amber for the next, off-white for your own dot |

**The light by hour**

| Sky | Round | Look |
|---|---|---|
| 12:00–16:00 | 0:00–5:00 | A tropical day: zenith #7098be, horizon #c4d0d4; Atmosphere Density 0.36, Colour #d2d6ce; towering cumulus |
| 16:00–18:00 | 5:00–7:30 | Golden hour: a warm key light, and the lagoon glows |
| 18:00–19:30 | 7:30–9:22 | A softened pink dusk (214,176,176), then the blue hour; the moon at 19:15 |
| 19:30–24:00 | 9:22–15:00 | The dome's night: our own starfield and a bright moon. OutdoorAmbient lifted to about (64,72,92), so open water and the island stay readable; two warm lamps in the horn's mouth. |
| During each hour | — | The storm (slate and cold rain), the red rain (rust), the fog (milky) and the false sun (white-hot), each blended in by how far into the sector you are |

### 4.18 Phone budgets on Map 2

| Measure | Target | Map 2's estimate | How |
|---|---|---|---|
| Server models and instances | ≤ 90k / ≤ 400k | About 68k / about 330k | <ul><li>The jungle is "fewer, bigger" at **about 0.5× Map 1's density**: the lower band ×1, the middle ×0.55, the upper ×0.33.</li><li>The brief's 0.85× would come to about 90k models in the jungle alone, which is the whole server cap (critic #12a).</li><li>Each device places its own ground cover.</li></ul> |
| Any streamed disc (r 1,024) | ≤ 30k / ≤ 130k | About 14k at worst (a disc centred at r 1,300–1,500) | The launch disc round the plates is 75% water |
| One 40 × 40-stud cell | ≤ 14 trees, ≤ 60 plants | ≤ 8 trees, ≤ 40 plants | — |
| Triangles drawn at the worst view | Phones ≤ 1.5M and ≤ 800 draw calls; High ≤ 5M | <ul><li>The plates at the launch: well under 1.5M.</li><li>The top of the beach looking along the ring: about 1.2–1.5M (the one to watch).</li><li>The rim looking down a sector: about 1.0M.</li></ul> | Canopy shells past about 900 studs; far meshes on palms, giants and spokes (the 12 spokes are about 466k triangles at full detail and about 0.1M with far meshes) |
| Terrain graphics | ≤ 110 MB | Below Map 1 at the launch, where half the disc is water | — |
| Textures and terrain sets | ≤ 160 MB; ≤ 12 sets | 10 terrain slots | — |
| Effects near the camera | ≤ 25–30 emitters | One live sector at a time; particles only within about 150 studs; 300 instanced crabs, 60 flock birds, 6 foam emitters on the wave | `FxBudget` (§6.7) |
| Server time for creatures | ≤ 1.5 ms a frame | At most 8 monkeys and 1–2 beasts, in one sector at a time | — |
| Terrain writes | — | None: the surge is a water-surface mesh and a push | A real voxel rise is a stretch goal, after a 3 GB phone test |

**Where we measure, on a real 3 GB Android:**
- a plate at the launch;
- the top of the beach looking along the ring;
- inside the Fig Grove;
- the island during the surge.

### 4.19 Game 2 is done when

- **The build passes its checks.**
  - Terrain generates in 120 s or less, and every Map 2 check passes (§9.3).
  - `Audit.report` passes at the decided radius.
- **The clock works.**
  - Each sector fires once, with the dial a full hour ahead and its world sign 20 s ahead.
  - The day schedule holds, and the island turns with nobody on it.
  - The surge never stalls the server for more than 50 ms.
- **It's fair and safe.** Game 2's fairness rules hold in the fairness harness, no voices are mimicked, and the rain is rust.
- **The queue works.** A queue of 8, or "go now" after 90 s, teleports together and comes back to the hub.
- **Players learn the clock.** In their rounds 2–3, at least 70% of players leave the next sector before its hour, and nobody who held a tap or found a spring dies of thirst.
- **You can tell the sectors apart.** A tester names 10 of 12 sectors from the island, without the dial.

---

## 5. The train, the station and the Training Centre

*Sources:*
- *brief §4 (the train and the station) and §5 (the training centre);*
- *the owner's frame `train_station_owner_frame.png` (T1 @35.7 s);*
- *the owner's TRIBUTE spec §9 (the train) and design direction §3 (training and tokens);*
- *a read of `src/` at version 199.*

### 5.1 The train

**What it's for**
- **The feeling** (S): "the last calm before the arena ... a moving hotel that's kidnapping you". Inside it's soft, warm and expensive; outside, a country gets poorer.
- **Its job in the game.** It's a first-session intro that:
  - teaches walking and looking, with nothing at stake;
  - sets up the story;
  - covers the first load.

**When you ride it**
- **Your first session only,** tracked by a saved `TrainRides` counter. The ride starts as soon as your character loads.
- **Skipping.** Hold Jump for 1 s while a ring fills. After a 0.6 s fade you're at the station, with the doors opening.
- **It never costs you a round.**
  - While you ride, you count as waiting.
  - If a round is about to be called (the Intermission starts), the arrival starts at once (critic #9).
  - If the call still comes first, the escort says "We're here", and you go straight to your red room, with no kit for that round.
- **Riding again.** The parked train at the station keeps its vestibule door open. Walk in, and it departs for you.
- **Returning players** spawn in a parked train's vestibule as its doors open (about 3 s), and walk out onto the platform.
- **You never see the train's outside until its door opens,** as the spec asks: the first outside view is the parked train at the station.

**The journey** (times from boarding)

| Time | What happens | Tag |
|---|---|---|
| 0.0 | <ul><li>You stand in the vestibule, facing the closing door.</li><li>Through its window: the departure platform, a riveted slate-blue railcar, and two guards in gas-mask visors.</li><li>The door seals with a pneumatic thump, and the outside sound dies.</li></ul> | S, C (T2 @33.2 s) |
| 0–4 | "HOLD [SPACE] TO SKIP", with the device's own button | I |
| 1.5–7 | The train pulls away | I |
| 7–24 | Night. The outskirts pass: slag heaps, fence lines under floodlights, a mine head fading behind | S |
| 24–32 | The train crosses a tall twin-pylon cable-stayed bridge over a reservoir between dark hills | C (T2 @24.7 s) |
| 32 on | Dark country, with the train's amber windows reflected in the glass | C, S |
| **Arrival starts** | At whichever comes first: you step into the observation car after at least 35 s aboard; 60 s pass; or a round is about to be called | I |
| +0–4 | "Arriving" on the PA. The train enters a tunnel: darkness, passing lights, brakes, the guards' boots on steel. | S |
| +4.6 | A 0.6 s fade. You're in the parked train's vestibule at the station, and the door opens. | I |

Walking straight from the vestibule to the observation car takes about 28 s. A player who just walks arrives at about 40 s; one who stops at everything arrives at about 60 s.

**The cars, front to back.** These are the spec's seven cars, in the film's materials. The guard car moves to the front, behind the sealed cab, so your walk runs from the door to the glazed tail without passing through it.

| Spec car | What's in it (S) | In the film's look (C, brief §4.4) | The beat |
|---|---|---|---|
| 7 Guard | Grey steel; four guards who stand the whole trip | Riveted grey steel; our own faceted white armour | Seen through the locked door's window |
| 1 Vestibule | Brass handrails, a pleated leather bench, one wilting flower in a bud vase | Geometric upholstery on the bench, brass rails | The door seals |
| 2 Dining | Mahogany with inlaid filigree, white linen, crystal that rings with the sway, a chandelier, a meal nobody wants | A hammered cream-gold ceiling, wood and brass arches, amber cove light; plates and runner carry our own motif, never a seal or crest | The table |
| 3 Lounge | Velvet club chairs, a globe drinks cabinet, a bolted-down piano, a wall screen whose light is the only cool colour | Oxblood velvet, brass, the screen's cool blue | The cabinet; the screen |
| 4 Corridor | Narrow, with brass fittings, patterned carpet, doors on both sides | Round-cornered brass windows all along | The night outside |
| 5 Compartment | Two bunks, a fold-down basin, a mirror with a chipped corner, a window seat, a pressed uniform, a brass plaque | The uniform is the white launch cape you'll wear in the red room | The window seat |
| 6 Observation | Glass on three sides, a curved bench | The night bridge recedes behind the glass | The view |

**The beats.** You only walk; there are no prompts.

| Beat | Where | It starts when | What happens | It ends when |
|---|---|---|---|---|
| The seal | Vestibule | You spawn | The thump; the outside sound muffles; the platform slides away | By itself |
| The table | Dining | You walk into the one pulled-out chair, which sits you on touch | <ul><li>Nobody speaks for 8 s. The crystal rings, the cutlery shifts and the chandelier swings.</li><li>Then the mentor says one line of our own ("Eat. Nobody in there will feed you."), and the silence returns.</li></ul> | You jump (the hint shows after 6 s) |
| The cabinet | Lounge | You come within 4 studs | The globe splits open, and your hands pour a glass of cordial in first person. Roblox allows alcohol only under its strictest age restrictions, and we're 13+. | By itself |
| The screen | Lounge | You step onto the rug in front of it | A 20 s loop: our host, last year's champion as a point-cloud bust, a launch-cape fashion segment, and a teaser of this year's arena | You step off |
| The window seat | Compartment | You touch the seat | You sit, the camera eases to the glass, and the country passes | You jump |
| The view | Observation | You walk in | The bench faces back down the line, and the bridge recedes if you're in time | You leave |

**Motion and sound**
- **The train stands still, and the world moves (I).**
  - Each device runs a scenery band outside the windows, in three layers: near posts and floodlights at about 120 studs/s; slag heaps, sheds and the bridge's pylons in the middle; far hills at about 8 studs/s.
  - Pieces are recycled as they pass.
- **The sway is the camera's.**
  - The camera rolls 1.5° and floats 0.4 studs on a slow sine, and the chandeliers swing.
  - The floors stay still, so walking stays smooth.
  - With Reduce Motion on, the camera stays level.
- **Sound** (S): a 52 Hz hum under everything, the glass chime and the cutlery, a distant door, and the guards' boots as the train slows.

**How it's built**
- **The ride train** is one server-side train in the siding, shared by every first-session rider.
  - Riders are in a collision group that doesn't collide with itself, and each device hides the other riders.
  - It's held for first-time riders only (`PersistentPerPlayer`, §9.5).
- **Everything that moves runs on each device:** the scenery band, the sway, the lamps, the door seal and the people's idle loops.
- **The arrival.** In the journey's last 10 s, the server pre-loads the station round the vestibule (`Player:RequestStreamAroundAsync`), then moves the character under the fade.
- **The people:** the escort, the mentor, two attendants and four guards. They are static rigs with idle loops, voiced with text-to-speech first (story-world.md §11).

### 5.2 The station

**Stepping off**
- The parked train stands at platform A.
- Straight ahead, a gold sunburst of ten tapered blades fans down through the oval in the coffered ceiling.
- Guards in white armour stand in two rows along a narrow aisle, banners of our own hang overhead, and a second train waits at platform B.

**The walk to the lift**
- It takes about 5 s, past a departure board showing:
  - "NEXT GAMES 0:42 · {MAP 1 NAME}";
  - "IN THE ARENA · 9 REMAIN";
  - "ARRIVALS", with the newest players' names.
- The lift is at the head of the concourse. The doors close, the ride takes 4 s, and the doors open on the training floor.
- The move between the two buildings happens behind the closed doors, so it works the same on every device.

**What pass 2 changes** (critic #6; `art/previews/Train/compare_station.png` and `compare_train.png`)

| # | What pass 1 shows | What pass 2 builds |
|---|---|---|
| a | The hall reads wide and low, with the trains small and far apart, because of the brief's 66-stud concourse | **A tall, narrow glazed shed:** the concourse narrowed to 30–40 studs, the glazed walls raised, so the trains loom on either side of a narrow aisle of guards, as in the film |
| b | The gold sculpture reads as a winged figure: two groups of blades converging on a hanging pendant | **The brief's radial fan:** 10 tapered blades through the oval, with no pendant. That also keeps it clear of an eagle-emblem read. |
| c | A uniform amber wash, about 2× the film's saturation (render chroma about 40, against 18–22 in the frames) | <ul><li>Cool white daylight through the glazing, against gold and amber accents.</li><li>The amber the owner named stays in the bounce light and the gold, not in a wash over everything.</li><li>Inside the train, the amber coves stay, toned down to the band (§7).</li></ul> |
| d | A blunt faceted barrel of a nose, with a matte maroon side under a grey roof | <ul><li>A **bullet capsule** that tapers over about one car width, keeping the gold-rimmed lamp and its red-orange core.</li><li>A mostly **black lacquer** body with a maroon band and gold pinstripes (brief §4.3).</li></ul> |
| e | Large blobs of upholstery pattern | The film's small arcs and rings, at a smaller, tighter repeat |

**Also in pass 2:**
- **Textures.** The train and station move from 129 textures in 33 sets (25.4 MB of GLB) to palette or atlas textures, like the launch set (critic #12d).
- **The guard.** It's a static statue in pass 1, and becomes a shared rig.
- **The departure platform** seen through the vestibule door stays optional. It's cut first if art time runs short.

### 5.3 The Training Centre

**What it's for.** In the film, the tributes train side by side, watch each other and decide what to show (C, T1 @79.2–83.2 s; shot in Berlin's ICC, L). In our game the hall does three jobs:
1. **It's the waiting floor** (decision 5). Everyone waits here between rounds, and a player who joins mid-round always has something to do.
2. **It's a safe place to learn every weapon** before the arena.
3. **It's where you pick your kit and train your body.**

**The hall**
```
                                N  big screen; a gallery above (later)
   +------------------------------------------------------------------+
   | BLADES RING          |                       | SPEAR & THROWING   |
   | 3 dummies, padded    |                       | orange spear racks,|
   | spinning post, cart  |                       | throwing boards    |
   |----------------------|      THE FLOOR        |--------------------|
   | FITNESS              |   benches, kit board, | ARCHERY RANGE      |
   | bikes, weights,      |   the Clock Gate      | lane 80 long,      |
   | climbing wall, rope; |                       | targets 15-60,     |
   | the obstacle run     |                       | the hoop wheel     |
   |----------------------|                       |--------------------|
   | SURVIVAL CORNER      |                       | THE LAUNCH DOORS   |
   | food table, trough,  |        LIFT           | two guards         |
   | bandage dummy        |                       |                    |
   +------------------------------------------------------------------+
                                S  (up from the station)
```
- **Size (I):** 220 × 150 studs, 36 high.
  - The middle stays open for waiting and watching.
  - Each station is a bay of about 50 × 45, with an orange mat at its mouth.
  - The launch doors are 15 studs from the lift.
- **Look** (C, brief §5):
  - teal padded, angled wall panels (#4e7076) with white diagonal ribs;
  - a blue-grey chequered carpet (#68747a and #969ea2);
  - round downlights and stacked colour-bar signs;
  - safety-orange equipment (#c4682c).

  Orange marks what you can use (ArtStyle rule 9), so nothing else in the hall is orange.
- **Light (I):** cool-neutral downlights, an ambient of about (64,72,76), no sun, and at most two lights casting shadows.
- **The big screen** on the north wall shows:
  - "NEXT GAMES IN 0:25 · {MAP NAME}";
  - the names of those chosen at the call;
  - during a round, "IN THE ARENA · 9 REMAIN" and the kill feed.
- **No render exists yet.** It's a new Blender set (T32 in §10). Its look is approved in game before it ships.

**The stations**

| Station | Kit | What you borrow, only while on the mat | The drill (step on the start line) | To pass | The knack you can feel here |
|---|---|---|---|---|---|
| Archery range | Archer | A recurve bow and 12 arrows, refilled | Pop-up targets at 15–60 studs; the head ring scores double; the hoop wheel turns | 4 hits from 6 targets in 30 s | Steady Draw |
| Blades ring | Blades | Machete, hatchet, war club and longsword | Moving pads on the dummies | 8 clean hits in 20 s | Quick Hands |
| Spear and throwing | Hunter | A spear and 6 throwing knives | Boards at 10–30 studs | 3 hits from 5 throws | Strong Arm |
| Survival corner | Survivor | 2 bandages, 2 herbs and an empty bottle | Pick sound food over spoiled, fill the bottle at the trough, bandage the dummy | All three in 40 s | Field Medic |
| Fitness: bikes and the run | (Stamina) | — | Keep the bike's gauge in the green for 20 s, or run the obstacle course round the hall (vault, mantle, slide) | The pace held, or the run in under 25 s | — |
| Fitness: weights and the wall | (Strength) | — | Lift 10 times in rhythm, or climb the climbing wall | 10 clean lifts, or the top in 20 s | — |

- **Borrowed items stay on the mat.** You can't drop them or carry them off. They vanish with a soft clunk when you step off, and at the call.
- **Training hits targets and dummies only, never people.** Arrows pass through anyone who wanders onto the range.
- **The survival drill never uses poisonous plants** (the Larder rule, story-world.md §10).

**Picking a kit**
- **Step onto a station's orange mat,** and its kit becomes yours. A toast says what that means: "ARCHER KIT · Crates lean to arrows · Steady Draw".
- **Or tap KIT,** a chip under the status pill, and pick from Archer, Blades, Hunter, Survivor or None. That's the easy way on a phone or a gamepad.
- **The kit board** by the lift shows all four kits, one line each.
- **You can change it freely until the call,** when it locks.
  - Your last kit is remembered.
  - A newcomer who hasn't picked plays with None.
- **Everyone can see your kit:** a small glyph by your name in the hall, and your kit on the death and spectate cards.

**What a kit does in the arena**
1. **One item in each crate you open comes from your kit's shelf.** Crates already roll their contents when they're opened, so the opener is known.

   | Kit | Tier 1 crates | Tier 2 crates | Tier 3 crates (the horn's alcoves) |
   |---|---|---|---|
   | Archer | 3–6 arrows | 5–10 arrows | A recurve bow with 5 arrows*, otherwise 8–14 arrows |
   | Blades | A hunting knife | A machete, a hatchet or a leather vest | A longsword*, a war club or padded armour |
   | Hunter | 1–3 throwing knives | A spear, or 2–4 throwing knives | A spear, or 3–5 throwing knives |
   | Survivor | A water bottle, 1–3 herbs or an apple | 2–3 bandages, a water bottle or dried meat | A med kit or a ration |

   \* Only while the round's caps allow: bows at one per two contenders and 5 at most; longswords at one per six and 3 at most. If a cap blocks the pick, the next item on the shelf is used.

   **The rules**
   - The pick replaces a roll; it never adds one.
   - Only crates you open lean. These never do:
     - ground items;
     - the horn's racks and bags in plain view;
     - the runner's caches;
     - the Feast;
     - sponsor gifts.

     So the rush for the horn is the same bet for everyone.
   - The effect is noticeable, not decisive. An Archer who opens four tier-1 crates finds about 4–5 lots of arrows; a player with no kit finds about one.
2. **One small knack, with a cost.** The values come from modes-progression's Talents table, so they're already sized as sidegrades.

   | Kit | Knack | Upside | Cost |
   |---|---|---|---|
   | Archer | Steady Draw | Full draw 10% sooner (0.90 → 0.81 s) | The draw's creak carries 15% further |
   | Blades | Quick Hands | Melee swings recover 6% sooner | Thirst drains 6% faster |
   | Hunter | Strong Arm | Thrown spears and knives fly 10% faster | Bow draw 8% slower |
   | Survivor | Field Medic | Healing items heal 15% more | Food fills 10% less |

   - **One ability slot.** A knack replaces the planned Province Talents in Standard rounds; the two never stack.
   - **Tuning.** Any kit whose win rate drifts more than 2 points from the average over 2,000 rounds is retuned.

**Training, tokens, Stamina and Strength** (the owner's design direction §3, in its simplest fair form)
- **Two trainable attributes: Stamina and Strength.** Hunger and thirst stay needs, as the owner wrote.
- **Tokens** (the name is open) come from:
  - passing a drill: 1 token, at most 6 a day;
  - playing a real round: 1 token, plus 1 for a top-5 finish, at most 6 a day;
  - the first pass of each station ever: 1 extra token.

  Practice rounds and private servers pay no tokens.
- **Ranks.** Each attribute has five ranks, costing 2, 4, 6, 8 and 10 tokens. Every spend asks you to confirm.

| Rank | Stamina: a full sprint from full (today 9.1 s), and recovery | Strength: stamina per melee swing, and climb and mantle time |
|---|---|---|
| 1 | 9.3 s, recovery ×1.02 | ×0.96, ×0.97 |
| 2 | 9.5 s, ×1.04 | ×0.92, ×0.94 |
| 3 | 9.6 s, ×1.06 | ×0.88, ×0.91 |
| 4 | 9.8 s, ×1.08 | ×0.84, ×0.88 |
| 5 | 10.0 s, ×1.10 | ×0.80, ×0.85 |

**What keeps it fair**
- **Training never changes how many hits it takes to down anyone.** There's no damage or armour bonus at all. Even a 5% damage bonus would let a knife down a contender in a leather vest in 6 hits instead of 7.
- **The gap is small, and it closes fast.** A casual player maxes both attributes in about a week, because of the daily caps.
- **Ranks show on the death card,** and they're off in practice rounds, private servers and events.
- **Robux.** None in the beta: the economy plan's charter says power is never sold. If token packs come later, they only buy time towards the same cap (§12).

**The call, and waiting**
- **With two or more waiting,** the Intermission (25 s) runs on the training floor: "NEXT GAMES IN 0:25 · KITS LOCK AT THE CALL". At the call:
  - up to 24 contenders are chosen;
  - borrowed items vanish;
  - the chosen fade to their red rooms.
- **If you're not chosen,** you stay and train. The screen says "THE GAMES HAVE BEGUN · YOU'RE IN THE NEXT ONE".
- **Alone on a server,** the pill says "PRACTICE IN 0:55 · OR WALK THROUGH THE LAUNCH DOORS".
  - For a first-session player the timer is 25 s, counted from reaching the training floor.
  - For everyone else it's 55 s, counted from joining.
- **After you fall, or when the round ends,** you come back into the recovery bay by the lift, with the death card as today.
- **Voice.** If proximity voice is on, the fallen and the waiting can talk here. The hall is far out of earshot of the arena (VoiceMode's rule).

**How it's built**
- **A training context.** New player attributes, `InTraining` and `OnMat`, let `InventoryService` hand out borrowed items outside a round, and let `CombatService` and `ProjectileService` accept hits on training targets, never on players.
- **Dummies on live servers.** Today `CombatService` wires its dummies only in Studio (W&O §4.2 found this), and the training dummies need it on live servers too.
- **Zones, not prompts.** The mats, the start lines, the doors and the boards are zones that each device checks and the server confirms.
- **Saved data:** `TrainingTokens`, `StaminaRank`, `StrengthRank` and `KitLast`. They live in Profile v2 (§10, Phase 9).

### 5.4 Done when

- **The train.**
  - The ride needs no prompts, skip works, and a coming round ends it in time.
  - It takes 60 s or less, and riders never block or see each other.
  - The dining car holds 30 fps on a 3 GB phone.
- **The station.**
  - Returning players reach the lift in 10 s or less.
  - The re-render matches the film's proportions: a tall, narrow hall, the radial fan of blades, cool daylight, and the colour band in §7.
- **The Training Centre.**
  - Nobody can damage another player in the hub.
  - One item in each crate opened comes from the kit's shelf, with the exceptions above.
  - The bow and longsword caps hold over 20 simulated rounds.
  - Knacks never change the hits needed to down anyone.
  - Its look is approved in game before it ships.

---

## 6. Shared systems

### 6.1 One codebase, two places

```
UNIVERSE  "HUNGER GAMES (BETA)"
├─ Start place 120572716460286 (public)            ├─ Clock place (new, teleport-only, reserved servers)
│   Workspace.MapId = "GreenLand"                   │   Workspace.MapId = "Clock"
│   Arena: Map 1 terrain + Populate output          │   Arena: Map 2 terrain + Populate output
│   Backstage, x ≈ -10,000 (far west of the map):   │   Backstage, x ≈ -10,000:
│     Hub: Training Centre - lift - station         │     waiting room (the fallen, the end card)
│     Siding: ride train + its scenery band         │
│   ReplicatedStorage.Assets.LaunchSet (template)   │   ReplicatedStorage.Assets.LaunchSet (template)
└─ one src/ in both (build stamp checked at start); shared DataStores, MemoryStores and badges
```

- **Why two places.**
  - Each server then holds one map, and stays inside ArenaV3's budgets.
  - The code assumes one arena per place.
  - The testers' place stays untouched.
- **The build stamp.** Each server publishes it on start, and a teleport is refused if the two places don't match.

### 6.2 The map registry, modes and names

- **`Shared.Maps`.** Each map has:
  - its id and place id;
  - its unlock rule and its settings overlay;
  - its layout modules (each under about 60k characters);
  - its ground-cover rules;
  - its generated WaterPoints and BiomeGrid.
- **`Shared.ArenaLayout`** becomes a facade. It returns the layout for `workspace:GetAttribute("MapId")`, with the API its 20 callers use today. Today's forest map stays as `Vale2`, for regression tests only.
- **`ModeService`** works out the map and the mode, then applies the map's settings overlay before anything reads `Config` (modes-progression §4.4).
  - Values a service copies when it loads (such as `MAX_HEALTH`) are read when they're used instead.
  - The Clock's overlay sets the round's time scale to exactly 1.
- **`Shared.Names`** holds every in-game name as a token, with a neutral default, until the owner decides.
  - `Dev.NameCheck` fails a build that writes a name into UI text without going through it.
  - `Shared.Lore` folds into it.
- **Start order.**
  - Server: `DataService`, then `ModeService`, then `PlayerService` and today's services, then `LaunchService`, `WardenService`, `CreatureService` and `WeatherService`, then `RoundService`.
  - Each device: `WardenController`, `CreatureController` and `WeatherController` load after `ArenaController`.

### 6.3 The challenge director and the mix

```
WardenService (server)
  Schedule.Slots   Map 1: arena-events §3 as ArenaV3 §6.7 re-bases it, with Game 1's pools (§3.11-3.12)
  Schedule.Clock   Map 2: hour h fires sector h at 75*h s; its world sign 20 s ahead; one live sector at a time
  Standing         hazards set at the call from the mix, live all round (beds, foul water, the field)
  Events/<Id>      one module per challenge: definition, prepare(mix), start/tick/stop, zone, damage, counters
  Zones            circle, polygon, ring band, sector wedge, moving front, volume: inside(), edgeDistance()
  Mix              the per-round randomiser; picks the intro or full set on Map 1
  Damage loop      0.2 s ticks through PlayerService.damage with the event's cause; credit to a hitter within 15 s
WardenController (each device)  draws every event from GameState.WardenEventData
Shared.Challenges               ids, tells, HUD lines (Names tokens), glyphs, sound and effect keys
```

- **Each event's life.** Every event goes warn (15–30 s), then active (ramping up), then clear, then cooldown, and a lock holds until 25 s after it clears.
- **Quiet times.** No event starts:
  - in the first 2:30;
  - during a Roll Call or the Feast's window;
  - with two or fewer alive;
  - after 13:00 on Map 1.
- **Size** scales with how many are alive.
- **Testing.** `DevWarden` fires any event in Studio, and late joiners draw the running events.
- **The mix.**
  - `Mix.roll(map, seed, headcount)` returns a public half and a hidden half.
  - Each event gets its own sub-seed, so its effects (ember clusters, fire fronts) are the same on every device and can't be predicted without the round's seed.
- **Fairness by test.** `Dev.WardenSim` stands a simulated contender at full health at the worst point of each zone, and moves it towards the counter after 10 s. It must lose 25 health or less.

### 6.4 Creatures

**The engine**
- **`CreatureService`, on the server.**
  - Each creature is a light agent: a position, a velocity, a state and a target, with no Humanoid.
  - Its brain is a state machine: idle, wander, flee, stalk, engage, lunge, recover, return.
  - Its senses follow arena-events §6:
    - hearing: a sprint at 60 studs, a fight at 50, walking at 25, crouching at 8;
    - sight: 45 studs in a 120° cone;
    - smell: 12 studs.
  - Long trips plan over the 8-stud navigation channel with A*. Short-range steering avoids trunks and rocks (`NavObstacles`).
  - Brains tick 10 times a second near players and twice a second far away.
- **The state stream.** An `UnreliableRemoteEvent`, `CreatureState`, sends 10 frames a second, packed into buffers. The engine drops any payload over 1,000 bytes, so each frame carries about 60 creatures at most, and each device gets only those within 300 studs.
- **`CreatureController`, on each device.** Pooled rigs, smoothed between frames: at most 30 animated rigs within 150 studs. Swarms are up to 200 instanced meshes.
- **Hits.** Each creature has a hit capsule. `CombatService` and `ProjectileService` test arrows and blades against it.

**The species**

| Species | Map | Server | On each device | Counter |
|---|---|---|---|---|
| Wildlife: rabbit, squirrel, songbird, frogs | 1 and 2 | Up to 12 near players; flee only | Rigs | — (hunt them for food, §3.10) |
| Crimson flock | 1 | One flock and up to 4 divers | 8–15 flocking birds | Stand still, or take cover |
| Golden squirrel pack | 1 | 6–12 agents and one pack brain | Rigs 1.2–1.5 studs long | Water |
| Blue butterflies | 1 | 1–3 swarms, each one volume | 40–80 butterflies each | Fire, water, or a jog |
| Monkey troop | 2 | 20–40 members, up to 8 attacking at once | Rigs in the canopy | §4.5 |
| Jabberjays | 2 | One flock | Flocking birds | §4.5 |
| The beast | 2 | One unseen agent | Tracks, breath, bending plants | §4.5 |
| Crab tide | 2 | A moving front | Instanced crabs | §4.5 |
| Insects | 2 | One swarm that picks idle players | Clouds and clicking | Keep moving |

**Budgets**
- On the server: at most 40 active agents, 2 ms or less a frame, and 2 raycasts per agent per tick.
- On the network: 3 KB/s or less per device.
- Art: 3k triangles or less, and one texture set, per species, with Blender animations uploaded under the experience's owner.

**13+.** Every creature growls or screeches before it attacks, and there are no jump scares. Hits throw sparks or puffs, never blood. Mutts dissolve when they die, and hunted wildlife fades into food (§3.10).

### 6.5 Fields: the edge, the border and the dome

There is one field technology, used in four places:
- Map 1's outer field at r 1,800;
- Map 1's Edge, on the north cliff;
- Map 2's dome;
- the closing border on both maps.

| Behaviour | Outer field / Edge / dome | Closing border |
|---|---|---|
| Seen | Invisible beyond 30 studs; a faint hexagon shimmer within 30; a ripple wherever anything strikes it | Today's border panels, re-skinned as the same hexagon field |
| Bodies | Blocked. A touch does 20 (10 the first time on Map 1) and throws you 12–16 studs back. | Never blocked. Outside it, you take today's border damage. |
| Thrown things | Come straight back along the mirrored path: at 85% speed and full damage on Map 1, and at half speed on the dome | The same as the outer field |
| Sound | The generator's hum | The border's own sound |

**How it's built**
- `ProjectileService` reflects a projectile off any surface tagged `Field`, and off the border circle analytically (`Shared.Border.radiusAt`).
- After a rebound, a projectile stops excluding its shooter.
- Kill credit for a rebound goes to the target the thrower was aiming at, but only if that target hit the thrower in the last 15 s.

### 6.6 Water kinds and statuses

- **Water kinds.** `WaterPointsBuilder` v3 generates points for each map, with kinds a round can change:
  - **Clean**;
  - **Foul** (Map 1);
  - **Salt** (Map 2);
  - **Spring, Pool and Tree** (Map 2);
  - **Rain**, anywhere under open sky while it rains.

  The coverage check: every walkable 16-stud cell inside the border is within 300 studs of fresh water, or 400 when every optional spring is dry.
- **Statuses.** These are new statuses, each shown as a thin icon and a timer by the vitals:
  - Sick, Choking, Stung, Burning and Gassed (Map 1);
  - Fogged, Soaked and Stuck (Map 2);
  - Lit (the Sweep).

  They're built on W&O's W4 status API, or a minimal version of it first.

### 6.7 Weather and effects: one budget, phone-friendly

- **`WeatherService`** (server) runs Map 1's weather from the mix: morning mist in the hollows, the cloud bank on the flanks, the dawn rain, and the wind.
  - Map 2 has a humid day, a pink dusk and the dome's stars. Its storms belong to the Director.
  - Published as `GameState.Weather`.
- **`WeatherController`** (each device):
  - rain and ash fall from one or two emitters round the camera;
  - an upward ray every 0.25 s stops the rain under cover;
  - it sets the sky's overlays through `Sky.setOverlay`.

**The rules for every effect**
1. **Warnings come first.** Every warning shows at full strength on every graphics tier. Only the spectacle scales.
2. **Everything goes through `FxBudget`:**

   | Tier | Emitters near the camera | Live particles | Lights without shadows |
   |---|---|---|---|
   | High | 30 | 4,000 | 8 |
   | Medium | 20 | 2,000 | 8 |
   | Low | 12 | 800 | 8 |

   Only the key light casts shadows, and at most 3 transparent layers overlap.
3. **Big effects are meshes with flipbook textures:** fireball columns, lava, fog walls and the wave front.
4. **No real lights for wide events.** The eruption and the fires shift the lighting by distance, and their glow comes from glowing meshes.
5. **Detail falls off with distance:** full within 150 studs, reduced out to 400, then only glow cards and smoke.
6. **Effects appear only near players,** and come from pools.

### 6.8 Teaching: goal lines, hints and death tips

- **The goal line.** Every new rule has a line in WeaponsAndObjectives §3.9's format, and danger lines outrank everything else (§3.17 and §4.2).
- **Hints and tips.** First-time hints and death tips extend QW4's, and every number in them comes from the data.
- **Funnel steps** (`OnboardingService`):
  - BoardedTrain, SkippedTrain, ReachedTraining, PickedKit, PassedDrill;
  - LaunchFull, LaunchShort, LaunchSkipped, RedRoomOverrun (by device);
  - SawBloom, SteppedOffBed, DrankClean, ReadFoul, Climbed, Hunted;
  - SurvivedEvent, SurvivedNight;
  - ClockUnlocked, ClockQueued, ClockGoNow.
- **Hazard telemetry** compares, for each hazard, how many were caught against how many survived. The target is 70% or more surviving.

### 6.9 Saved data

| Key | What it is | When |
|---|---|---|
| `GreenLandRounds` | Green Land rounds finished (§4.15) | R1, in today's `PlayerStats_v1`, saved as an additive change |
| `ClockRounds` | Clock rounds finished | R5 |
| `TrainRides` | The train's "seen" counter | R6 |
| `KitLast` | Your last kit | R4 |
| `TrainingTokens`, `StaminaRank`, `StrengthRank` | Training | R7, in the session-locked Profile v2 |

**Why tokens wait for Profile v2.** Spending tokens across two servers could go below zero, or count twice, in a save that records only additive changes. Counters are safe in v1.

### 6.10 Light for each space

`SpaceLightingController` applies a profile from `Shared.Spaces` whenever the camera enters a space, and blends over 1 s. The switches hide under cuts and fades.

| Space | Ambient (about) | Key light | Notes |
|---|---|---|---|
| Red room | (30, 18, 20) | A cool white key down the tube | Red only in the floor openings |
| Case hall | Navy (24, 34, 52) | Cool blue-white keys | Blue shadows (§2.8) |
| Pole hall | Navy (14, 20, 32) | 12 hub spots; the ceiling ring and wall bars | Bloom threshold 1.4 |
| Station | Cool, about (62, 64, 68) | White daylight through the glazing | Warm amber in the bounce and the gold (§5.2) |
| Train | Amber coves; outside at night, about (40, 48, 70) | Swinging chandeliers; the cool screen | Toned to the band (§7) |
| Training Centre | (64, 72, 76) | Cool-neutral downlights | At most 2 lights with shadows |
| Arena | From each map's day looks | Sun and moon | The arena's sky takes over only in the arena |

---

## 7. Colour: one measured translation

**The rule** (brief, all four parts):
1. Sample the frame: the owner's frame first, then the clearest trailer frame.
2. Take out the film's grade: no teal in the shadows, the sky about 40% less saturated, flesh and stone back to neutral.
3. Soften towards natural: lighter in the shadows, slightly warmer, and about 10–20% less saturated than the film.
4. Clamp into ArtStyle's light band (rule 6):
   - natural surfaces stay in their ranges;
   - built surfaces stay between luma 55 and 215;
   - things that must read black go no lower than luma 40.
5. Keep saturation only for signals: hazards, loot, the copper start plates and warning lights.
6. In interiors, darkness comes from the light, never from the paint.

**What pass 1 measured** (critic #4, matched panels against the frames)

| Set | Saturation against the film | Brightness | Cause |
|---|---|---|---|
| Map 1 | About 0.45× (0.20 against 0.41–0.47) | 30–40% brighter (mean luma 137–148 against 98–114) | The haze and the hard cloud slab grey and brighten the whole frame |
| Launch halls | 0.45–0.6× (lit saturation 0.26–0.33 against 0.47–0.57) | Close | Sampled blues went to neutral grey, and the reds went the other way |
| Station | About 2× (0.46–0.48 against 0.23) | — | A uniform amber light wash |
| Train | Nose 1.7×; interiors 1.3–1.6× | — | Warm light rigs |
| Map 2 | Natural; no vivid pixels (`art/previews/Map2/tones.json`) | Mean luma 97–123 | — |

**The band: a pass-or-fail check on every comparison render**

It is measured per surface class, matched region against region, not as whole-frame averages. That's our one change to critic #4, because step 2 above takes the sky down on purpose.

| Surface class | Our saturation, against the film's | Our brightness, against the film's |
|---|---|---|
| Ground, foliage, stone, water and built surfaces | 0.65–0.85× | −10% to +20% (shadows a little lighter is allowed) |
| Sky and haze | 0.45–0.65× | −10% to +25% |
| Interiors lit by their own lights | 0.65–0.85× | −10% to +20% |

Two checks apply to every render, whatever its class:
- every painted surface inside ArtStyle's light band;
- vivid pixels (saturation over 0.6 and value over 0.35) at 1% or less, outside the signals.

**The tools**
- `colour_check.py` (Map 1 and the launch) and the tones tool (Map 2 and the train) move into the repo as `tools/art/colour_band.py`, with the band above.
- Pass 2 of every set runs it on every comparison render, and a failing render isn't shown to the owner.

**What each set changes**
- **Map 1:** the haze, the cloud slab, the meadow's three tints, and muted decorative flowers (§3.3, §3.18).
- **The launch:** cool keys and a navy ambient carry the blue; the reds go back to their sampled saturation (§2.2, §2.8).
- **The station:** cool daylight instead of the amber wash.
- **The train:** the cove light toned down (§5.2).
- **Map 2:** keeps its natural tones; it adds the sector tints and the dark lava island (§4.16).

---

## 8. The art list

Every asset is modelled by us in Blender, by a seeded generator in `art/blender/`, run headless as `art/README.md` shows, and following the blender-art skill and ArtStyle style A. Reference images are for study only. None goes into the game or the repo.

### 8.1 What the first Blender pass delivered

| Set | Generator | What it exported | State |
|---|---|---|---|
| **Map 1** | `map1_green_land.py` (seed 50) | <ul><li>A 16-bit heightmap, 1,376² at 4 studs a pixel (±2,752).</li><li>10 material slots, regions and water, and 8 scatter masks.</li><li>`Map1_Terrain.json` and `Map1_Layout.json` (158 placements).</li><li>55 landmarks: 80k triangles, 11.5 MB.</li><li>13 placeholder plants.</li></ul> | <ul><li>The slope budget passes (86.2% of the disc under 30°, 50.7% under 15°).</li><li>The shape, the sky, the beds and the horn need pass 2 (§3.3, §3.5).</li><li>The plants are placeholders of 20–510 triangles, and nothing is baked.</li></ul> |
| **Map 2** | `map2_clock_arena.py` (seed 75) | <ul><li>Fine (1,376²) and coarse (888²) 16-bit heights.</li><li>Material, sector, region, water-depth and canopy masks.</li><li>`Map2_terrain.json`.</li><li>13 landmarks: 42k triangles, 3.3 MB.</li></ul> | <ul><li>Reads as the clock from above.</li><li>The jungle, the island, the horn and the sector reads need pass 2 (§4.16).</li><li>No jungle plants are exported, and nothing is baked.</li></ul> |
| **The launch** | `launch_rooms.py` | <ul><li>Three GLBs (2.1 MB): the red room, the case hall and the pole hall.</li><li>Palette textures.</li><li>The rise's camera keys at 10 a second.</li><li>The light rigs.</li></ul> | <ul><li>The structure matches the film.</li><li>The light, the net, the poles and the end of the rise need pass 2 (§2.2).</li></ul> |
| **The train and the station** | `train_sotr.py` (seed 50) | <ul><li>Six GLBs (25.4 MB), with 34 assets.</li><li>129 textures in 33 sets.</li><li>Layout, colliders, lighting and motion data.</li></ul> | <ul><li>The interiors catch the film's materials.</li><li>The hall's proportions, the sculpture, the light, the nose and the upholstery need pass 2 (§5.2).</li></ul> |
| **The Training Centre** | — | — | Not started (T32) |

**Approval.** Nothing has been seen in Roblox yet. Every set is approved in game at 14:00 and 17:30, or under its own interior light, before it ships (ArtStyle rule 10).

### 8.2 Pass 2: what each set changes

| Set | Changes | Done when |
|---|---|---|
| **Map 1** (T2) | <ul><li>**The valley:** the open valley and the field instead of the crater (§3.3).</li><li>**The heart:** lens-shaped beds 16–20 wide, starting at the platform's foot; big pale front petals; the horn's skirts flared to 20–26; racks and the cobalt interior; tribute stand-ins in the comparison renders (§3.5).</li><li>**Forest and colour:** dense dark conifers on the slopes; the meadow in three tints; muted decorative flowers (§3.18).</li><li>**What Game 1 needs:** its sites, springs, pools and the East Brook; water levels on the voxel rule; plinth collars and tube liners.</li><li>**Data:** masks at 8 studs.</li></ul> | <ul><li>The overview shows no concentric ring.</li><li>The T1 @1.7 s and @40.2 s matches show hillside and layered peaks behind the horn.</li><li>Every match passes §7's band, and the slope budget still holds.</li><li>Every site has an anchor and a kit id.</li></ul> |
| **The launch** (T3) | <ul><li>Navy light and blue shadows; reds back to their sampled strength.</li><li>The fine net at 45°, with a sag; black grates, with red only in the floor openings.</li><li>Your own stand-in in the red room.</li><li>Dark poles.</li><li>The low-angle end frame (§2.2, §2.4).</li></ul> | <ul><li>In the halls, blue minus red is +15 to +25.</li><li>The reds are within ±0.05 of their sampled saturation.</li><li>The budgets are unchanged.</li></ul> |
| **Map 2** (T36, after decision 1) | <ul><li>Game 2's changes 3–7 (§4.3).</li><li>The varied jungle, the sector silhouettes and tints, the hour markers, the dark lava island, one horn design, and varied relief (§4.16).</li><li>The style A bakes, far meshes for the spokes, 12 canopy shells and the horizon ring.</li><li>TimberPond's water level snapped.</li></ul> | <ul><li>A tester names 10 of 12 sectors from the island, from renders.</li><li>Every part is under 5k triangles.</li><li>The band passes.</li><li>The data validator passes.</li></ul> |
| **The train and the station** (T44) | <ul><li>The tall, narrow hall, the radial fan of blades, and cool daylight.</li><li>The bullet nose and the black lacquer body; the finer upholstery (§5.2).</li><li>Palette or atlas textures instead of 33 sets.</li><li>A rigged guard.</li></ul> | <ul><li>The re-render matches the film's proportions.</li><li>The band passes.</li><li>The textures fit within 80 MB.</li></ul> |

**Pass 2 result (15 November).** All three sets came out closer to the film, but none passes §7's band yet, so no pass 2 render goes to you. Each set had a fix, an independent review and a follow-up fix. The band is measured by `tools/art/colour_band.py` against the specs in `tools/art/specs/` (art/README.md §14).
- **Map 1:**
  - **What changed:** the crater is gone, and the valley sides now climb 113–122 studs. The heart has its lens beds, pale petals and a flared horn with a modelled interior. The whole map uses one sunlit Day look instead of lights tuned per shot.
  - **Band:** 0 of 6 matches pass, and 5 of 33 regions.
  - **Still unlike the film:** the far forest and the mountains read grey, the cloud bank is a row of puffs, the peak is striped and single, and the stream reads as a canal. Every plant is a placeholder. Game 1's sites, anchors and kit ids aren't started.
- **The launch:**
  - **What changed:** frame A looks steeply down the red shaft at your stand-in on the rose disc. The wide shot is level, with the ring as an ellipse overhead. The case hall is a tight row of booths with lit discs.
  - **Band:** 2 of 6 matches pass, and 16 of 26 regions.
- **The train and the station:**
  - **What changed:** the gold fan is now broad blades. The ceiling has 6-stud coffers with visible downlights. The lacquer is semi-gloss, the cars are lamp-lit again and the upholstery rings interlock. On the night bridge the windows show as a line of amber lights.
  - **Band:** 0 of 5 matches pass, and 13 of 25 regions.
  - **Still to fix:** the textures are still about 634 MB, against the 80 MB target.
- **Calls still to make (the art lead's, not yours):**
  - the blue-minus-red floor on the rise frames, which is set aside for now, as the film does;
  - the oxblood, which is held at the band;
  - a hall blue-minus-red window measured relative to the film's own value;
  - the case hall's reference frame;
  - Map 1's brief grass tints, which measure 0.92–1.29× the film;
  - the station, where your frame and T1 disagree.
- **Not checked in Studio.** Nothing from pass 2 has been looked at in Studio yet.

### 8.3 New art still to make

| Kit | Pieces | Budget (triangles) |
|---|---|---|
| **Map 1: the heart** | The horn (3 sail pairs, the interior, the racks); the star platform and its steps; the plinth and collar (one mesh, used 48 times); the tube liner; 18 lens beds in 3 lengths, with far meshes; 6 teardrops; the fuse daisy (armed and spent); charred bed variants; white supply bags; 3 lone beeches | Per brief §1.11; the collar about 500 |
| **Map 1: plants and trees** | Pines with pinkish trunks (2), firs (2), beech (2), oak, apple, a burnt pine; gorse and burnt gorse, heather and burnt heather, bracken, wildflowers, tall pale grass, lupins, cress; daisies and dandelions (each device's ground cover) | Trees 3–5k plus a far mesh of 300–800; plants 200–900 |
| **Map 1: rock** | Limestone crag bands (6), white boulders (5), peak modules (6), scree pieces, the shelter arches (the Lake Cave, the Grotto, the Overhang), the Edge's cliff modules, and the Persistent skyline meshes for the far range | Crags ≤ 4k; boulders 150–400; skyline ≤ 6k per sector |
| **Map 1: sites** | The crimson spiral, the glade's beds, the holly hedge kit (with a burnt-gap piece), the wreck (our own hovercraft design), 16 berms with plaques and hatches, the field's emitter stakes along the Edge, the canyon generator (backdrop only) | Wreck ≤ 12k; berms ≤ 1.5k; every part under 5k |
| **Map 1: the volcano** | The fire fountain, a bomb, gel and crust ribbon segments, a glowing vent | ≤ 3k each |
| **Creatures and wildlife** | <ul><li>Map 1: the golden squirrel, the crimson waterbird, the butterfly and the ladybug.</li><li>Map 2: the monkey, the jabberjay, the crab and the jellyfish. The beast has no model: only bending plants and claw marks.</li><li>Ordinary wildlife: the rabbit (alive, and still), a tree squirrel, a songbird and a frog.</li></ul> | Squirrel about 700; bird about 900; monkey 0.8–1.5k; butterfly about 40; crab 100–200; rabbit about 600 |
| **Map 2** | <ul><li>The island: lava-rock ring modules and apron blocks; the turning deck.</li><li>Spokes: modules, root, spur and tide stone.</li><li>The plate and its column; the lightning tree.</li><li>Palms: coconut, tall, and the bottle palm with a tapped version.</li><li>Climbable giants and the strangler fig; the understory.</li><li>Shelters; the sector pieces (snags, hive spires, driftwood, the Root Bridge).</li><li>12 canopy shells, the horizon ring, and 12 hour markers.</li></ul> | Giants ≤ 12k; palms 3–4k; shells ≤ 4k each; horizon ≤ 6k |
| **Map 2: hazards** | Storm and rust cloud decks, fog sheets, the wave front, the surge's water surface, the false-sun disc, the barrier and dome ripple textures, the flaw | ≤ 2k each; the wave ≤ 5k |
| **Items** | Game meat (raw and cooked), the tap, the coconut, charcoal tablets (today's purifying tablets, renamed) | 100–600 |
| **The launch: extras** | The white launch cape (2–3 bones; our own trim); the cloaked stand-in figure; Map 1's brass tube rim; Map 2's water collar | Cape ≤ 1k; figure ≤ 1.5k; rim ≤ 1k |
| **The Training Centre** | <ul><li>The shell: angled padded wall panels with ribs, ceiling modules with downlights, the chequered floor, the big screen, the launch doors.</li><li>The orange equipment: spear racks, a weapon cart, the hoop wheel, archery butts, pop-up targets, a training dummy, a padded spinning post, throwing boards, bikes, a weights rack, a climbing wall (tagged Climbable), a rope, obstacle blocks, a food table, a trough, a bandage dummy, the kit board.</li><li>The Clock Gate arch with its dial.</li></ul> | Hall ≤ 60k; modules ≤ 5k; props 200–1,500; the Gate ≤ 8k |
| **People** | The guard (our own faceted white armour, black harness and visor, plus a gas-mask variant); the trainer, the escort, the mentor and the attendants | Guard ≤ 4k; one shared rig everywhere |
| **The train's scenery band** | The departure platform (optional), slag heaps, fences and floodlights, the mine head, hills, the reservoir, the twin-pylon bridge, the tunnel mouth | ≤ 2k each |
| **Effects** | Fire and smoke flipbooks, sparks, pollen, sparkly ash, gas, rain, the field's hexagon ripple, the beam cone | Texture sets only |

### 8.4 Rules for every piece

- **Style A.** Every piece follows ArtStyle's rules: true scale, facets as the "blocks", paint rather than texture, matte surfaces, the light band, and gameplay reads first.
- **Creatures.** Every mutt has a believable faceted body and one wrong trait. Ordinary wildlife has none.
- **Nothing from the films.** No piece copies the films' objects, logos or text. Plaques carry glyphs, never words. Banners, posters, boards, emblems, uniforms and the hour markers are our own.
- **Labelled renders.** Every render is labelled "Blender iteration, placeholder plants" until the production art replaces the placeholders (critic #16).

---

## 9. Technical plan

### 9.1 The pipeline

```
Blender generator (seeded) -> BlenderExports/<Map>/ (16-bit heights, 8-bit masks, Terrain.json, Layout.json, GLBs, manifests)
  -> tools/mapdata/pack_mapdata.py: validate + encode -> src/ServerStorage/WorldGen/MapData/<Map>/ (Spec, parts, Manifest)
    -> workbench Studio: TerrainGen.generate({ map = "GreenLand" }) -> voxels, TerrainData, BiomeGrid, nav grid, markers
      -> MapAssets.build(map), after the upload -> ServerStorage.MeshAssets.<Map>.* templates
        -> Populate.generate({ map = ... }) -> workspace.Arena dressing; the Audit budget gate
```

- **Where it runs.** Everything runs in Edit mode in the workbench copy (task O1 in §10), never at runtime, and never in the live place.
- **Why not Studio's heightmap importer.** It would skip the deterministic builder, its voxel-safe water and its checks.
- **Why not EditableImage.** It would need the images uploaded first.

### 9.2 The map data

**How it's encoded** (measured on the 14 November exports)
- **Heights** are stored to 1/16 stud. Each value is predicted from its neighbours, and only the difference is kept.
- **Masks** are stored as runs of equal values, and density masks at 8 studs.
- **The text** is base64, split into parts of at most 196,608 characters.
- **`Spec`** turns `Terrain.json` and `Layout.json` into Luau tables.
- **`Manifest`** holds each part's size and a hash, and TerrainGen refuses any part whose hash doesn't match.
- **It stays on the server.** The data sits in ServerStorage, so it's never sent to players.

**The sizes**
- **Map 1:** about 3.0M characters in 21 modules:
  - fine heights 1.29M;
  - coarse heights 0.66M;
  - materials 0.27M;
  - regions and water 0.03M;
  - 8 scatter masks 0.80M.
- **Map 2:** about 3.9M characters in 24 modules:
  - fine heights 2.53M;
  - coarse heights to ±2,944 only, 0.73M;
  - materials, sectors and regions 0.17M;
  - water depth 0.27M;
  - canopy 0.25M.

### 9.3 TerrainGen v3, per map

**The modules** (ArenaV3 §7.1, re-cut for imported data)

| Module | What it does |
|---|---|
| `TerrainGen` | The driver |
| `.Grid` | The buffer grids |
| `.Import` | New: decodes the map data and checks the hashes |
| `.Shape` | The heart, the bores, and the field line |
| `.Erode` | `Vale2` only; Blender's data arrives already shaped |
| `.Water` | Water levels, the voxel rule, sealing, salt flags |
| `.Materials` | The material slots |
| `.Voxels` | 128-stud chunks, written in vertical slabs that skip air |
| `.Data` | TerrainData, the BiomeGrid and the navigation channel |
| `.Checks` | Every check below |

**Map 1's heart gates.** `validate()` refuses any heart that differs from `Spec.Heart`:
- the knoll at 46 and the deck at 52;
- 48 plinths at r 150, on bearings 3.75 + 7.5k;
- the ring at y 44.3, and a tube radius of 3.6;
- turf to r 180;
- a protected disc at r 200–255, inside which only the heart's shaping writes terrain.

**The plinth bores**
- There are 48 separate bores, each with a brass tube liner, and a turf collar that hides the voxel steps at the rim.
- A sightline gate places eyes 5.2 studs above the ground at r 160, 200 and 300, on 96 bearings, and fails the run if any bore wall shows.

**Map 2's gates**
- The island deck is at y 46 (±0.25) inside r 62, with 12 ramps.
- Each of the 24 plates has at least 6 studs of water under it.
- The lagoon floor sits at 10, 20 and 30 (±2).
- Terrain under each spoke stays at least 1 stud below its deck at 35.6.

**Water**
- **The voxel rule.** Every designed water level must sit in the lower half of its 4-stud voxel layer.
  - Pass 1 broke it four times: Map 1 at 54.42, 42.2 and 39.13, and Map 2 at 182.25.
  - The generators snap the levels, and the packer refuses data that breaks the rule.
- **Fords** stay 0.5–1.2 deep, and every body of water is sealed.
- **Salt.** The lagoon is flagged salt.

**Materials**
- Each map has ten slots, set with `Terrain:SetMaterialSlot`. A slot's base material decides its footsteps and grip.
- **Map 1:**
  - three Grass slots (turf, meadow, dry);
  - LeafyGrass for the forest floor, Ground for paths, Salt for stream beds and Mud for banks;
  - Limestone for crags, Rock for cliffs, and Basalt for scree.
- **Map 2:**
  - two Sand (beach and wet sand);
  - two Rock (lava and plain);
  - LeafyGrass, Mud and Salt;
  - two Ground (laterite and seared);
  - Grass.
- **Expanded Terrain.** The first workbench test settles whether the slots need it.

**The checks.** `generate` ends with a pass or a fail.
- **The heart, the bores and the plates:** as above.
- **Water:** as above.
- **Edges:**
  - Map 1's field line is closed at r 1,800, with the Edge cliff carrying it between 345° and 15°;
  - Map 2's dome sits at R.
- **Thickness:** at least 16 voxels of rock over every shelter and cave.
- **Walkability:**
  - Map 1: at least 85% of the play disc under 30°;
  - Map 2: at least 98% of the land under 30°.
- **Reach:** a path search reaches every site and crate from the horn, on foot or by swimming.
- **Relief:** each region's height range is within ±15% of its design.
- **Fidelity:** the terrain is within ±2 studs of the Blender heights on 99% of columns.
- **Water reach:** every plinth is within 650 studs of clean water in the worst foul mix (Map 1).
- **Firebreaks:** every point of scrub is within 150 studs of a break (Map 1).
- **Determinism:** a second run gives byte-identical terrain.

**The runtime grids**
- **TerrainData** is an 8-stud grid kept on the server, with height, cover, moisture, water, tree cover, fuel and a navigation channel. Map 1 takes 12 parts and Map 2 18.
- **BiomeGrid** is a 16-stud grid on each device: Map 1 76.8k characters, Map 2 about 158k.

**Generation time** (estimates; T9 and T37 measure them)
- TerrainGen: 120 s or less for each map.
- Populate: 150 s or less on Map 1, and 180 s or less on Map 2.
- A full rebuild: about 3–5 minutes.
- Studio memory: about 40 MB for Map 1's grids and 60 MB for Map 2's, far under ArenaV3's 1 GB ceiling.

### 9.4 Populate v3

| Step | Map 1 | Map 2 |
|---|---|---|
| `core` (Persistent) | The horn and platform; 48 plinths with collars and liners; 18 beds with far meshes; 6 teardrops; 3 lone trees | The horn, the deck and its rock ring; 24 plates; 12 spokes, with far meshes |
| `landmarks` | `Layout.json`: the spiral, the glade, the maze, the 16 berms, the peak, the crag bands, the skyline meshes | The placements, plus the tide stones and the hour markers |
| `sites` | Game 1's site kits (§3.6) | Game 2's camps, sites, shelters and climbable giants |
| `loot` | The planner runs before the scatter, so its markers are kept clear | The same |
| `scatter` | Masks × zone multipliers × class caps, in 512-stud tiles | The canopy mask × zones |
| `shells` | Low-poly canopy shells per forest region, shown past about 900 studs (420 on Low) | 12 wedge shells and the horizon ring |
| `hazards` | Anchors: bed outlines, berm roles, hatches, vents, gel paths, gas spots, searchlight routes | Sector anchors: storm decks, fog fronts, timber pivots, the wave channel, the hives |
| Then | Ambience, `NavObstacles`, wildlife spawn areas, `fixLoot`, `verify`, `looks` and `report` | The same |

**Density zones** (ArenaV3 §7.5)
- **Map 1:**
  - full density everywhere the plinths can see (to r 700), at every site plus 30 studs, near trails and near water;
  - the North Wood's slopes are dense dark conifers, with broadleaf only in hollows;
  - the lids' upper slopes and the South Mountain are open high ground: trees ×0.3–0.5, rocks ×2;
  - past the field, density is ×0.35, for looks only.
- **Map 2:**
  - about 0.5× Map 1's density in all;
  - the lower band ×1, the middle ×0.55, the upper ×0.33.

**Other rules**
- **Ground cover.** Each device scatters its own ground cover round its camera, from the same seeded rules.
- **Hiding cover stays shared.** Tall grass, bracken, gorse and bushes are on the server, so everyone sees the same places to hide.
- **`DetailClass`.** Every placed model carries a `DetailClass` attribute, so new assets need no code change in `DetailController`.

**The budget gate.** `Audit.report` enforces:
- at most 90k models and 400k instances per place;
- at most 30k models and 130k instances in any 1,024-stud disc;
- at most 7k models in any 300-stud disc;
- at most 14 trees and 60 plants in any 40 × 40-stud cell.

### 9.5 Where each pre-arena set lives, and how it streams

| Set | Where | Streaming | Held by | Size |
|---|---|---|---|---|
| **The launch set** | A template in `ReplicatedStorage`, built on each device at the call | None: it's built on the device and destroyed after the arrival | Each contender's own device, during the launch | 20k unique triangles; about 15 MB in memory |
| **The hub:** the Training Centre, the lift, the station and two parked trains | Backstage, about 2,500 studs from the siding and more than 4,000 from the arena | `PersistentPerPlayer` | Players in the hub; released at the call | The Training Centre ≤ 60k triangles; the station and trains about 75k |
| **The ride train and its scenery band** | The siding | `PersistentPerPlayer`; the band on each device | First-time riders | About 60k triangles |
| **The Clock place's waiting room** | Backstage in the Clock place | `PersistentPerPlayer` | The fallen | Small |

- **Why per player, not plain Persistent.** Plain Persistent would keep every set in every phone's memory during the round. `AddPersistentPlayer` gives the "never streams out" guarantee only to the players who need it.
- **The hand-off** (critic #12d):
  1. **At the call,** a contender's hub is released (`RemovePersistentPlayer`), their device builds the launch set, and the arena streams round their shaft.
  2. **At the arrival,** the launch set is destroyed.
  3. **After the round,** the hub is held again behind the recovery bay's fade.

  So a phone on its plinth just after the launch never holds the hub, the launch and the arena's busiest area all at once. The 3 GB phone test checks exactly that moment.

### 9.6 Budgets for a 3 GB phone

**Data limits**

| Limit | Value | Our worst case |
|---|---|---|
| Script source | 200,000 characters | TerrainGen's modules under 120k each; data parts of 196,608 |
| `WriteVoxelChannels` | 4,194,304 voxels per call | A slab of 32 × 32 × at most 175 voxels |
| Unreliable remote | 1,000 bytes; larger payloads are dropped | Creature frames packed to fit |
| GameState JSON attributes | Under 4 KB each | `RoundMix` (its public part) 2 KB; `WardenEventData` 1 KB |
| Uploads | 20 MB per GLB; 16 images per texture folder | The largest is `Map1_Landmarks` at 11.5 MB |
| DataStore and MemoryStore | 4 MB per key | Saved records under 1 KB; tickets under 1 KB |

**Streaming** (ArenaV3 §7.4)
- **Settings, in both places:**
  - a target radius of 1,024 and a minimum of 128;
  - Opportunistic stream-out;
  - pause outside the loaded area;
  - the Improved model-streaming behaviour.
- **Persistent:** the heart sets, the runner's poles, Map 1's skyline meshes and canopy shells, and Map 2's lightning tree, island and shells.
- **Atomic:** all other scenery.
- **SLIM and mesh streaming** are tried on 2–3 models first.

**Triangles drawn at the worst views.** Phones at most 1.5M and 800 draw calls; Medium at most 3M; High at most 5M.

| View | Main cost | How we keep it down |
|---|---|---|
| Map 1: a plinth during the arrival | The wooded slopes 400–1,000 studs away; the lids; 24 avatars | Far meshes past about 250 studs; shells past about 900; haze from 500 |
| Map 1: the Edge, looking south | The whole North Wood below | Shells; SLIM on groups of trees |
| Map 1: the eruption night | Flames, ash, lava | `FxBudget`; glowing meshes, no lights |
| Map 2: a plate during the arrival | 12 spokes, about 466k triangles at full detail | Spoke far meshes, bringing them to about 0.1M |
| Map 2: the beach, and the rim looking back | The jungle | Far meshes, 12 shells, the horizon ring |
| The pole hall during the rise | About 150k triangles and the stand-ins | Instancing; only the nearest rider lights |

**Memory** (Medium settings, at the worst view)

| Measure | Target |
|---|---|
| Total client memory | 1.2 GB or less |
| PlaceMemory | 650 MB or less |
| Client instances | 160k or less |
| Terrain graphics | 110 MB or less |
| Textures | 160 MB or less |
| Scenery meshes | 250 MB (our allocation, to be measured) |
| 24 avatars | 120 MB (our allocation) |
| Creatures and effects | 40 MB (our allocation) |
| A pre-arena set while you hold it | 80 MB (our allocation) |
| Server memory with 24 at the launch | 3 GB or less |

**CPU:** the Director under 1 ms a frame, creatures under 2 ms, and the fire spread under 0.5 ms.

**Where it's measured.** On a real 3 GB Android, at six places:
1. a plinth just after the launch, arriving from the hub;
2. the densest forest or jungle cell;
3. the eruption night;
4. the pole hall with 24 riders;
5. the dining car;
6. spectating from the hub.

### 9.7 The scripts that change

**`ReplicatedStorage.Shared`**
- `ArenaLayout` becomes a facade.
- New modules: `Maps`, `Border`, `Names`, `Challenges`, `Loadouts`, `Modifiers`, `Spaces`, `FxBudget` and W&O's `Objectives`.
- `Config` gains `Launch`, `Modes`, `Wardens`, `Creatures`, `Weather`, `Fx` and `Round.Extended`, and changes to `Loot`, `Survival` and `Camera`.
- `DayCycle` gets a schedule for each map, `ThreatLine` beats for each stage and hour, and `WaterPoints` its new kinds.
- `ItemDefs` gains:
  - each map's loot tables;
  - game meat, the tap, the coconut and the capsule;
  - the kits' shelves.
- `Net` gains the remotes `WardenFx`, `HazardImpulse`, `CreatureState` (unreliable), `ChooseLoadout`, `QueueJoin`, `QueueLeave`, `TrainSkip` and `LiftCall`.

**Server services**
- `RoundService`: hands the Countdown to `LaunchService`; takes its plinths from the map; counts Green Land rounds; runs small rounds faster, except on Map 2.
- `PlayerService`: `loadIntoHub`; placement at the call; per-player persistence; the train's rules.
- `ArenaService`:
  - `Shared.Border`, with the field rules;
  - each map's clock and Feast;
  - the Roll Call trap fixed, so it uses the final stage's start (600 s) to decide that the border is moving;
  - the island's turn;
  - where the Last Stand closes.
- `LootService`: the planner's output; `refillHorn`; the kits' lean; capsules; the salt rule.
- `InventoryService`: rain, coconuts, taps, salt and foul water, game meat, and borrowed items.
- `CombatService` and `ProjectileService`: creatures and wildlife as targets; no player damage in the hub; field rebounds.
- `MovementService` and `MovementController`:
  - climbing by a tree's shape;
  - pushes from hazards (`applyImpulse`);
  - the water cushion;
  - quickmud;
  - the limits on knacks and ranks.
- `DataService`: the new counters; then Profile v2.
- `OnboardingService`: the funnel steps (§6.8).
- **New:**
  - `ModeService` and `LaunchService`;
  - `WardenService`, with `Schedule`, `Events`, `Zones` and `Mix`;
  - `CreatureService`, with `Species`, `Brain`, `Senses` and `Nav`;
  - `WeatherService`, `LoadoutService`, `HubService`, `TrainService`, `TrainingService` and `MatchService`.

**On each device**
- `LaunchController` becomes v2.
- `CameraController` gains a cinematic mode.
- `ArenaController` and `Sky` gain field panels, ripples, sky overlays and the cloud bank.
- `HUDController` gains:
  - region and site ticks on the compass;
  - the dial and the NEXT line;
  - the kit chip and the queue pill.
- `NotificationController` gains the broadcast cards and the new death tips.
- `DetailController` reads `DetailClass` and handles shells.
- **New:** `WardenController`, `CreatureController`, `WeatherController`, `GroundCoverController`, `SpaceLightingController`, `HubController` and `TrainController`.

**`ServerStorage.WorldGen`**
- `TerrainGen` is split into modules, with the import path.
- `MapData` is new, and generated.
- `Populate` becomes v3. The Tor's builder (`Lobby`) is archived at R4.
- `WaterPointsBuilder` becomes v3.
- **New builders:** `MapAssets`, `PreArenaBuilder` and `EventAssets`.

**Dev tools:** `NameCheck`, `LaunchSim`, `WardenSim`, `LootSim` and `BudgetCapture`.

**The repo**
- `tools/mapdata/pack_mapdata.py` and `tools/art/colour_band.py`.
- The second passes of the four Blender generators.
- New generators for the Training Centre, the plants, the creatures, the hazards and the kits.
- New sections in `art/README.md` for Map 1, Map 2 and the launch.

**Not in this plan**
- W&O's combat work (W2 onward).
- The TRIBUTE spec's blood and severing.
- Money and cosmetics.
- The 48-player Jubilee.

---

## 10. Build order and phases

Every Studio task runs in the workbench copy, never in the live place, and only one terrain or Populate run happens at a time, behind a lock. **U** marks an upload that waits for your go-ahead. Weeks count from your go-ahead on the five decisions. The phases overlap, because agents work in parallel.

**Releases**

| Release | Week | What's in it | Its gate |
|---|---|---|---|
| R0 | Today | v199 as "HUNGER GAMES (BETA)" on today's arena | You publish it. It's not part of this plan. |
| **M1, the first playable** | End of week 4 | Map 1's world (pass-2 terrain, the heart, dressing, loot and water) and the new launch, in the workbench copy, private | <ul><li>You play it.</li><li>Its look is approved in Studio at 14:00 and 17:30.</li></ul> |
| **R1, the Green Land** | End of week 5 | Map 1 and the launch, public; the staged border and the field; the interim lobby; the goal line for the beats that exist | <ul><li>A 3 GB Android holds 30 fps or more, within 1.2 GB, on its plinth just after the launch.</li><li>3 rounds without a crash, and an 8-client playtest.</li><li>The publish checklist.</li><li>Your look approval.</li></ul> |
| **R2, the living valley** | End of week 7 | Climbing, wildlife, hunting and gathering; the standing hazards (rigged beds, foul water, the field's rebound, the Garden Wakes) and the dawn rain | <ul><li>The fairness harness passes.</li><li>No blood anywhere.</li><li>The maturity questionnaire is updated.</li></ul> |
| **R3, the Gamemakers** | End of week 10 | The Director and the mix; the intro set's events (sponsor drops, the flock, the mountain wakes); then the full set; creatures; weather | <ul><li>20 seeded rounds all differ.</li><li>The phone effects budget holds during the eruption.</li><li>Intro rounds run only the intro set.</li></ul> |
| **R4, the Training Centre** | End of week 11 | The hub, kits, knacks, the crates' lean, the Clock Gate (locked) | <ul><li>Nobody hurts anyone in the hub.</li><li>The caps hold.</li></ul> |
| **R5, the Clock** | End of week 15 | Map 2's place, the unlock, the queue with "go now", the clock, its sectors and creatures | A queued round from the Gate and back, at the size you chose |
| **R6, the station and the train** | End of week 16 | The first-session ride, the station, the lift | The dining car holds 30 fps on a 3 GB phone |
| **R7, training tokens** | End of week 19 | Profile v2; Stamina and Strength | <ul><li>Saves survive a server hop.</li><li>Nothing can be bought with Robux.</li></ul> |

If the launch runs late, R1 ships with the plinth's arrival rise only, and the launch follows as R1.1.

### Phase 0 · Set-up and decisions (days 1–2)

| # | Task | Done when |
|---|---|---|
| O1 | (You) A workbench copy of the place, in the same universe, with ArenaV3's three switches on, published privately | It opens for one agent alone, and the live place is untouched |
| O2 | (You) The five decisions | Recorded at the top of this document |
| T0 | Baseline: v199 on a 3 GB Android and a mid-range PC (the plate at the launch, the densest forest cell, the Tor), plus the real stream-in time after a move from the hub | Frame rate, memory tags, instance counts, draw stats and the stream-in time are in Status.md, and the red-room minimums are set from them |

**Phase done when:** the workbench exists, the five decisions are recorded, and the baseline is in Status.md.

### Phase 1 · Foundations (weeks 1–2)

| # | Task | Needs | Done when |
|---|---|---|---|
| T1 | `mapdata-pack`: the packer, the validator and a Python round-trip (`tools/mapdata`) | — | <ul><li>Both maps decode, heights within 1/16 stud and masks exactly.</li><li>Every part is 196,608 characters or less; Map 1 totals 3.1M or less, Map 2 4.0M or less.</li><li>The validator checks extents, encodings, the voxel rule, slots and asset names.</li></ul> |
| T2 | `blender-map1-pass2` (§8.2) | O2 | <ul><li>The overview shows no concentric ring.</li><li>The two key matches show hillside and layered peaks.</li><li>The beds are 16–20 wide.</li><li>The slope budget holds, and every match passes the colour band.</li><li>T1's validator passes.</li></ul> |
| T3 | `blender-launch-pass2` (§8.2) | — | <ul><li>In the halls, blue minus red is +15 to +25.</li><li>The reds are within ±0.05 of their samples.</li><li>The net, the poles and the end frame are fixed.</li><li>The budgets are unchanged.</li></ul> |
| T4 | `colour-band`: `tools/art/colour_band.py` (§7) | — | It reproduces the critic's pass-1 numbers, within ±0.03 saturation and ±5 luma |
| T5 | `terrain-v3-core`: ArenaV3's T2, plus the import path | — | <ul><li>v2's terrain regenerates within 1 stud on 99% of columns, and every v2 check passes.</li><li>Map 1's data decodes in 2 s or less.</li><li>Every module is under 200k characters.</li></ul> |
| T6 | `maps-registry`: `Shared.Maps`, the facade, `ModeService`, `Shared.Names` | — | <ul><li>With `Vale2`, a solo round plays exactly as v199.</li><li>With `GreenLand`, all 20 callers read Map 1's values.</li><li>`NameCheck` fails a raw name in UI text.</li></ul> |
| T7 | `border-and-field`: `Shared.Border` with a table per map; the field rules; the 18-minute switch | T6 | <ul><li>An 8-bearing sweep shows no point faster than 6.5 studs/s, and the horn stays at least a third of r0 inside every ring.</li><li>Projectiles rebound off the field and the border.</li><li>Roll Call 1 plays in the sky.</li><li>`Round.Extended` moves stage 1 by 3:00.</li></ul> |
| T8 | `art-map1-production` (Blender) | T2 | <ul><li>Trees are 3–5k triangles, with far meshes of 300–800, and the skyline meshes and shells are made.</li><li>The art checks report no problems.</li><li>GLBs are under 20 MB, with at most 16 images per folder.</li><li>The colour band passes.</li></ul> |

**Phase done when:**
- both maps' data round-trips;
- v2's terrain regenerates;
- a solo round on `Vale2` plays as v199;
- the border sweep passes;
- the Map 1 and launch pass-2 renders pass the band and their Done-whens.

### Phase 2 · The Map 1 world (weeks 2–4)

| # | Task | Needs | Done when |
|---|---|---|---|
| T9 | `terrain-map1` | T1, T2, T5 | <ul><li>Generation takes 120 s or less.</li><li>Every check in §9.3 passes, and the output is deterministic.</li><li>TerrainData and the BiomeGrid are written.</li></ul> |
| T10 | `lobby-interim`: the Tor moves to the hub slot (your go-ahead) | T9 | <ul><li>Nothing is left inside r 2,750.</li><li>A solo round runs lobby → plinth → lobby with 4 s or less of streaming on a phone.</li></ul> |
| T11 | `mapassets-map1` (U1) | T8 | <ul><li>Every asset is a template with its manifest values, pivots within 0.05 studs, its far mesh paired and its `DetailClass` set.</li><li>`MapAssets.verify()` passes.</li></ul> |
| T12 | `populate-map1` | T9, T11 | <ul><li>`Audit.report` passes the gate.</li><li>The bores and the three mouth lanes are clear, and the runner's flags can be seen.</li><li>It runs in 150 s or less, and `NavObstacles` is written.</li></ul> |
| T13 | `loot-map1` | T12 | <ul><li>The three rings and the site markers are placed.</li><li>A 20-round simulation at 4, 8, 16 and 24 contenders matches W&O's counts, with 3–4 bows at 24.</li><li>The Feast restocks the horn.</li></ul> |
| T14 | `round-map1`: 48 plinths, the arrival rise, WaterPoints v3, the goal line, the funnel | T7, T12 | <ul><li>4- and 8-client rounds run from the Intermission to the end, with both Roll Calls, the Feast and the Last Stand on a mouth lane.</li><li>Water coverage passes.</li></ul> |
| T15 | `client-map1`: `DetailClass`, ground cover, the sky and cloud bank, the compass, the map page, the field's panels, spectating | T12 | <ul><li>Ground cover costs 1 ms a frame or less while sprinting.</li><li>The compass names the regions and the nearby sites.</li><li>A 3 GB Android on a plinth holds 30 fps or more within 1.2 GB.</li></ul> |

**Phase done when:**
- terrain generates in 120 s or less, with every check passing and deterministic output;
- Audit passes;
- 4- and 8-client rounds run end to end;
- the phone test passes.

### Phase 3 · The launch (weeks 3–4, alongside Phase 2)

| # | Task | Needs | Done when |
|---|---|---|---|
| T16 | `launch-import` (U2): the template in `ReplicatedStorage` | T3 | <ul><li>The set matches the manifest: 48 bays, poles and discs within 0.05 studs.</li><li>The light rigs are in.</li></ul> |
| T17 | `launch-service`: the cut rule, placement at the call, readiness, late loaders, the Clock's red-room arrival | T6, T16 | <ul><li>The throttled 8-client test passes (§2.11).</li><li>The full shot runs 38 s, practice 34 s and the cut 18 s.</li><li>Nothing waits more than 15 s for streaming.</li></ul> |
| T18 | `launch-client`: `LaunchController` v2, the stand-ins, the camera, the lighting profiles, the letterbox, skipping, Reduce Motion | T17 | <ul><li>No pops at the cuts.</li><li>The camera stays 1.8 studs or more from every pole and case.</li><li>The pole hall holds 30 fps or more with 24 riders on a 3 GB phone.</li></ul> |

**Phase done when:** §2.11 is met in the workbench. **M1** follows at the end of week 4, and **R1** at the end of week 5, after T48's gate.

### Phase 4 · The living valley (weeks 5–7)

| # | Task | Needs | Done when |
|---|---|---|---|
| T19 | `climbing`: `Climbable` trunk meshes, `Perch` attachments, hands that follow the facets | T12 | <ul><li>Every climbable tree can be climbed by pushing into it, with no prompt, on PC, phone and gamepad.</li><li>The rest forks hold.</li><li>Falls hurt as today.</li></ul> |
| T20 | `wildlife`: rabbits, squirrels, songbirds and frogs (flee, freeze, flush), on the creature engine's light path | T12 | <ul><li>Up to 12 near players.</li><li>They flee and flush believably in 20 observed encounters.</li><li>0.3 ms or less on the server.</li></ul> |
| T21 | `hunting-gathering`: hits on wildlife, game meat, cooking, the forage markers; the maturity questionnaire's "violence against non-humans" | T20 | <ul><li>No blood, and the animal fades into food within 2 s.</li><li>The hunger values hold.</li><li>W&O's items-held rule passes.</li><li>The questionnaire is updated.</li></ul> |
| T22 | `standing-hazards-map1`: the rigged beds (stepped on, shot or lit), the Garden Wakes, foul water and Sick, the field's touch and rebound | T7, T14 | <ul><li>Every hazard passes the 25-health test.</li><li>The foul tells show.</li><li>The rebound credit rule holds.</li><li>Nothing bleeds.</li></ul> |
| T23 | `weather-v1`: the dawn rain you can drink, mist and the cloud bank | T15 | <ul><li>You can drink the rain.</li><li>No rain falls under cover.</li><li>One emitter round the camera.</li></ul> |
| T24 | `art-wildlife-items` (U3a) | T8 | <ul><li>The rigs are within budget, with their animations.</li><li>The art checks pass.</li></ul> |

**Phase done when:**
- the owner's "climb, hunt, gather" loop works in an 8-client test;
- every standing hazard passes the fairness harness;
- R2 ships.

### Phase 5 · The Gamemakers (weeks 6–10)

| # | Task | Needs | Done when |
|---|---|---|---|
| T25 | `warden-engine`: slots, locks, quiet times, scaling, broadcasts, `DevWarden`, `WardenController` | T6 | <ul><li>`DevWarden` fires any event.</li><li>Late joiners see the running events.</li><li>The card, the line, the compass and the alert work on PC, phone and gamepad.</li></ul> |
| T26 | `round-mix`: 14 mix-ups; the choice between the intro and the full set | T25 | <ul><li>20 seeded rounds give each mix-up at least 2 values.</li><li>Hidden choices are never sent early.</li><li>Intro rounds run only the intro set.</li></ul> |
| T27 | `creature-engine` | T20 | <ul><li>40 agents with 24 players cost 2 ms or less.</li><li>Frames stay at 1,000 bytes or less, and 3 KB/s or less per client.</li><li>No creature leaves the play radius.</li></ul> |
| T28 | `intro-events`: sponsor drops, the flock, the mountain wakes (with fire on the mountain) | T25–T27 | <ul><li>Each counter works on the first try.</li><li>The eruption never hurts anyone off the mountain.</li><li>The night holds 30 fps on Medium on a 3 GB phone.</li></ul> |
| T29 | `full-set`: squirrels, butterflies, the berms, the gorse fire, tear gas, the puzzles, the Sweep | T28 | <ul><li>Fire never crosses a firebreak.</li><li>Every challenge passes the 25-health test.</li><li>The Sweep stays within 8 outlines.</li></ul> |
| T30 | `art-hazards-creatures` (U3b, with animations) | T24 | Rigs are 3k triangles or less, plus the hazard meshes and flipbooks |
| T31 | `fx-budget` | T28 | <ul><li>Each tier's caps hold at the worst views.</li><li>Warnings never drop on Low.</li></ul> |

**Phase done when:**
- every event passes the fairness test;
- 20 seeded rounds differ;
- the creature and effects budgets hold on a 3 GB phone;
- no blood anywhere;
- R3 ships.

### Phase 6 · The Training Centre (weeks 8–11; its art from week 6)

| # | Task | Needs | Done when |
|---|---|---|---|
| T32 | `art-training-centre` (Blender, U4) | — | <ul><li>The brief's §5 look, in 60k triangles or less.</li><li>The colour band passes, and doors are 4 × 7.5.</li><li>It's approved in game.</li></ul> |
| T33 | `hub`: everyone waits in the Training Centre (decision 5); the Tor archived | T32 | <ul><li>Persistence switches at the call.</li><li>QW1's practice hand-off still works.</li></ul> |
| T34 | `loadouts`: kits, knacks, the crates' lean, locking at the call | T33 | <ul><li>The lean follows §5.3.</li><li>The caps hold over 20 rounds.</li><li>Knacks never change the hits needed to down anyone.</li></ul> |
| T35 | `training-stations`: borrowed items, drills, live dummies | T33 | <ul><li>Nobody takes damage in the hub.</li><li>Borrowed items stay on the mat.</li></ul> |

**Phase done when:** §5.4's Training Centre items pass, and R4 ships.

### Phase 7 · The Clock (weeks 9–15; it starts once decision 1 is made)

| # | Task | Needs | Done when |
|---|---|---|---|
| T36 | `blender-map2-pass2` (§8.2) | Decision 1 | <ul><li>A tester names 10 of 12 sectors from renders.</li><li>The colour band passes.</li><li>The validator passes.</li></ul> |
| T37 | `clock-place` (you add the place) and `terrain-map2` | T5, T36 | <ul><li>Both places report the same build stamp.</li><li>Generation takes 120 s or less, and every Map 2 check passes.</li></ul> |
| T38 | `mapassets-populate-map2` (U5) | T37 | <ul><li>Audit passes at the chosen radius, at about 0.5× density.</li><li>Populate takes 180 s or less.</li></ul> |
| T39 | `water-loot-map2` | T38 | <ul><li>Salt water is refused.</li><li>6 of 12 springs flow.</li><li>Taps and coconuts work.</li><li>Coverage counts fresh water only.</li></ul> |
| T40 | `clock-engine`: the hours, the dial, the day schedule, the island's turn (nobody riding), the dome, the surge (a mesh and a push) | T25, T38 | <ul><li>Each sector fires once, with the dial an hour ahead and the world sign 20 s ahead.</li><li>The island turns with nobody on it.</li><li>No server hitch over 50 ms.</li></ul> |
| T41 | `sector-hazards` and `creatures-map2` | T40, T27 | <ul><li>Game 2's fairness rules hold.</li><li>No voices are mimicked, and the rain is rust.</li></ul> |
| T42 | `unlock-queue`: the counter, the Gate, the queue, "go now" at 90 s, the live count, the way back | T6 | <ul><li>Exactly one count per finished round.</li><li>A queue of 8, or "go now", teleports in one call.</li><li>The return lands everyone in the hub.</li></ul> |
| T43 | `clock-playtest`: 15 against 18 minutes | T41, T42 | Telemetry on deaths by hour, how far players roam, and drop-off decides the default (critic #15) |

**Phase done when:** §4.19 passes, and R5 ships.

### Phase 8 · The station and the train (weeks 12–16)

| # | Task | Needs | Done when |
|---|---|---|---|
| T44 | `blender-train-pass2` (§8.2) | — | <ul><li>The proportions and the band pass.</li><li>The textures fit within 80 MB.</li></ul> |
| T45 | `station-train-import` (U6) and `train-ride` | T44, T33 | §5.4's train and station items pass |

**Phase done when:** §5.4 passes in full, and R6 ships.

### Phase 9 · Profile v2 and training tokens (weeks 15–19)

| # | Task | Needs | Done when |
|---|---|---|---|
| T46 | `profile-v2` (modes-progression §5.1) | — | <ul><li>Saves are session-locked, and survive a server hop and a crash test.</li><li>v1 and the counters migrate once.</li></ul> |
| T47 | `tokens`: 5 Stamina and 5 Strength ranks | T46, T34 | <ul><li>`MovementService` accepts exactly these values.</li><li>Nothing can be bought with Robux.</li></ul> |

**Phase done when:** R7 ships.

### Every release

| # | Task | Done when |
|---|---|---|
| T48 | `qa-release`: the release's gate (a 3 GB Android, 3 rounds without a crash, multi-client playtests, the publish checklist, your look approval at 14:00 and 17:30) | The gate in the releases table passes before you publish |
| T49 | `docs`: GameDesign §4 and §8–§11, Status.md and the Roadmap | They describe what shipped |
| T50 | `swap`: the same seeded builders run in the live place after QA, and you publish | The live place changes only through the builders |

**If time runs short, cut in this order:**
1. the Sweep;
2. the departure platform;
3. quickmud, and the toppling trees in falling timber;
4. the ladybugs and the other v1.1 creatures.

---

## 11. Risks

| Risk | What we do about it | The fallback |
|---|---|---|
| **The owner's first ask, Map 1's look, could still miss** after pass 2 | Fixed targets (§3.3); the two key matches and the band are gates; M1 puts the owner in the valley at week 4 | Another Blender pass before R1; R1 waits for the owner's look approval |
| **Map 2's size decision** could stall the Clock | Every layout value is a fraction of R; only T36 waits for it | Build R 2,600 and offer the trial at the owner's size afterwards |
| **The terrain material slots** (`SetMaterialSlot`) may need Expanded Terrain, which can cause meshing bugs in Team Create | Test one slot in the workbench first; generate with one Studio session open | Merge the slots so each base material is used once |
| **SLIM, mesh streaming and shells** are untested on our faceted trees | Test 2–3 models first | Persistent low-poly shells per region past 900 studs, haze from 500 |
| **Every art import waits on an upload approval** (U1–U6); creature animations must be uploaded under the experience's owner | Ask for each set as its art passes its checks | Code tasks run on part-built stand-ins until then |
| **48 separate plinth bores** may show voxel steps at the rims | Tube liners, turf collars, and the sightline gate | One ring-shaped trench under a ring of collar meshes |
| **Designed water levels** that break the voxel rule won't render | The generators snap the levels; the packer refuses bad data | — |
| **Code drift between the two places** | One `src/`, a build stamp checked at start, teleports refused across a mismatch; test teleports in published private servers | — |
| **A quiet beta may never fill the Clock's queue** | "Go now" after 90 s, solo practice, and the live count | A lower `MinQueue` setting |
| **The surge** writing terrain could stall servers | It's a mesh and a push by default, with no terrain writes | — |
| **Creature costs** with 24 players | Light agents, packed frames, a 300-stud interest radius, A* on the coarse grid; caps of 40 agents and 2 ms | Fewer agents per event; more of each flock drawn only on devices |
| **Effects on phones**: fire, the eruption, fog and gas | `FxBudget`'s caps per tier; meshes and flipbooks; glow through the lighting | Low tier cuts the spectacle, never the warning |
| **Memory at the hand-off**: the hub, the launch and the arena on one phone | Release the hub at the call, destroy the launch at the arrival, measure that exact moment (§9.5) | Shorter streaming radius in the hub; smaller launch textures |
| **The launch on slow phones** | The loop and jump rules; the white holds; skip; the short cut; red-room times set from T0's measurement | R1 ships with the arrival rise only |
| **Lighting switches** between the halls, the station and the arena flash or show the wrong exposure | Switches hide under cuts and fades; each device lights only its own rider and the 4 nearest | Low tier turns decorative lights off |
| **Moving the hub** breaks what `PlayerService`, `LobbyController` and `RoundService` assume today | Keep the Tor build until T33's tests pass; before R4, the Tor moves to the backstage slot | — |
| **Tokens in a v1 save** could go below zero or count twice | Tokens wait for the session-locked Profile v2 | — |
| **Hunting could be read as cruelty** | Bloodless, quick, food only, no trapping a live animal; the questionnaire updated (§3.10) | Switch hunting off with one setting and keep the wildlife fleeing only |
| **The intro set could make early rounds feel thin** | A beat every 1–2 minutes still holds; the full set unlocks at 3 rounds; telemetry watches drop-off | Unlock one full-set creature from round 2 |
| **IP**: the title and the film-faithful places carry a takedown risk the owner accepted | Every name through `Shared.Names`; no film text, logos or imagery; our own emblems, posters and designs | Rename through the tokens |
| **Maturity**: the red rain, creatures, fire and gas must stay 13+ | Rust rain, no blood, growls before every attack, no jump scares; the questionnaire updated with each release | — |
| **Scope**: about 50 tasks over about 19 weeks, all in the workbench | One terrain or Populate run at a time, behind a lock; challenges as small modules on one engine | The cut order in §10 |

---

## 12. Open questions for you

### 12.1 The five that block (our default in brackets)

1. **Map 2's size.** [Your guide at 1×: R 2,600, 1.46 km across. A literal 3× of your guide is 4.4 km, 18.6× Map 1's area: 24 players would rarely meet, and phones can't hold it. If you want it bigger, we test your size and come back with the largest radius that passes.]
2. **The horn's colours on Map 1.** [White, muted plum and dull gold outside, reading blue-grey in shade, with the cobalt-blue interior and gold fans. Or blue-grey and teal all over.]
3. **The launch's length.** [The full 38 s shot on your first launch of each session, then an 18 s cut. Or full every round (+28 s a round), or the cut every round.]
4. **Rigged flower beds.** [Visible: the daisies spark from the countdown. Or hidden until a fuse lights.]
5. **The Training Centre as the place everyone waits between rounds,** retiring the Tor lobby. [Yes, from R4.]

### 12.2 Standing questions (they don't block this plan)

- **In-game names or the films' names.** Which to use for:
  - the horn (or the Cornucopia), tributes, Gamemakers, mutts, the Feast, the start signal (the film's gong) and the edge's field;
  - the two maps ("the Green Land" and "the Clock" are working names), the regions and the sectors;
  - the station, the Training Centre, the four kits, the tokens;
  - the escort, the mentor and the guards.

  Every name on screen is a token in `Shared.Names`, so this is a one-line change whenever you decide.
- **The gore rating.**
  - We build for 13+: no blood and no severing.
  - Your TRIBUTE spec's blood and severing would need Roblox's age-verified 17+ rating.
  - Do you want a separate 17+ mode later, or should the game stay 13+?

### 12.3 Everything else, with the default we're using

| Question | Our default |
|---|---|
| Tokens for Robux, which your direction suggests | None in the beta. Later, capped packs that only buy time towards the same cap. |
| What unlocks the Clock | Your first Green Land round, counted when your part in it ends: fall, win or round end, but not leaving. Practice rounds count. |
| Where Map 2 runs | Its own teleport-only place; a queue of 8; "go now" after 90 s; solo practice |
| The round's length | 15 minutes, with the 18-minute switch tested on Map 2 first (T43) |
| How often the mountain erupts | 35% of full rounds; 60% of intro rounds |
| The Sweep (searchlights, our own idea) | Kept, in the full set only, on nights without an eruption |
| The dawn rain as safe water (our own idea; the book's chapters don't confirm it) | Kept, in 60% of rounds |
| A trident or a fishing spear | Left to the weapons pass. W&O's IP guard rails ruled the trident out before you chose film-faithful places. |
| Beetee's wire and the dome-breaking ending on Map 2 | Parked for a longer mode |
| The 48-player Jubilee on Map 1's 48 plinths | Later; it needs its own place and tests |
| A scored private session in front of the Gamemakers (the film's 1–12 score is on the Roadmap's avoid list) | Later, through the Assessment's Mark 1–10 |
| Where the Stamina and Strength ranks apply | Standard rounds on both maps; off in practice, private servers and events |
| The white launch cape as a cosmetic in the arena | No: it's for the launch only |
| Jabberjays | They mimic only the arena's own sounds, never voices |
| The hovercraft | Unseen for the tear gas; our own hull design for the wreck |

---

## 13. Renders to look at

All of these are Blender iterations with placeholder plants and flat colours, from the first pass. The comparison sheets (`compare_*`) put a film frame beside our render. They are kept out of git, because they contain film frames.

| # | What | File | What to look at | What pass 2 changes |
|---|---|---|---|---|
| 1 | The launch: the pole hall | `art/previews/Launch/compare_wide.png` | The round hall, the spoked ring, a pole for every tribute | Navy light; dark poles with no light strips |
| 2 | The launch: the rise, as one shot | `art/previews/Launch/rise_path_sheet.png` | Eight frames along the 270° circle: your "circular motion" | The end becomes the film's low-angle, whole-body frame |
| 3 | The launch: the low-angle rise | `art/previews/Launch/compare_rise.png` | The film's framing, matched | Navy and blue-steel light |
| 4 | The launch: the glass cases | `art/previews/Launch/compare_cases.png` | The curving ring of oxblood-framed cases | Dim navy instead of charcoal |
| 5 | Map 2 against your guide | `art/previews/Map2/compare_guide_topdown.png` | The clock reads from above: lagoon, island, 12 spokes, beach, wedges. It's your guide at its own scale, which is decision 1. | A varied jungle; a silhouette and tint per sector |
| 6 | Map 2 from the air | `art/previews/Map2/overview_high_aerial.png` | The whole clock | As above |
| 7 | Map 1 against your frame | `C:\Users\USER\OneDrive\Documents\LastStanding\References\compare\Map1\compare_owner_t1_1.7s.png` | The heart's layout: the ring, the beds, the horn | The open valley and slopes behind the ring, soft cloud, lens-shaped beds, a flared horn (§3.3, §3.5) |
| 8 | Map 1: the horn's mouth | `C:\Users\USER\OneDrive\Documents\LastStanding\References\compare\Map1\compare_t2_49.9s.png` | The film's cobalt-and-gold interior against ours: decision 2 | Racks, the chosen colours, layered peaks with soft cloud |
| 9 | The train inside | `art/previews/Train/compare_interiors.png` | Brass windows, burgundy upholstery, the hammered vault | A finer upholstery pattern; toned-down amber |
| 10 | The train at night | `art/previews/Train/exterior_night_bridge.png` | The train crossing the twin-pylon bridge | A bullet nose and black lacquer |

Also worth a look:
- `art/previews/Map1/overview_aerial.png`, to see why Map 1 is being reshaped: it reads as a crater;
- `art/previews/Train/compare_station.png`, for the station's proportions;
- `art/previews/Map2/sector_reads.png`, the twelve sector panels that pass 2 must make distinct.

---

## Sources

**Project documents.** In `docs/`:
- GameDesign.md and handoff/Status.md;
- design/UpcomingFilm_Brief.md, ArenaV3.md, ArtStyle.md, WeaponsAndObjectives.md, arena-events.md, PlayabilityPlan.md, modes-progression.md and story-world.md;
- design/owner/GameDesignDirection_2026-11-14.md and design/owner/TributeSpec_BloodAndMovement_2026-11-14.md.

Also `art/README.md`, `.claude/skills/blender-art/SKILL.md`, the four Blender generators and their manifests, and `src/` at version 199 (read only).

**The owner's frames** (study only), in `C:\Users\USER\OneDrive\Documents\LastStanding\References\owner\`:
- `map1_green_land_owner_frame.png`;
- `map2_clock_arena_reference.png`;
- `launch_1_red_room_net_a.png` and `launch_1_red_room_net_b.png`;
- `launch_2_glass_cases.png`;
- `launch_3_pole_rise.png` and `launch_3_pole_hall_wide.png`;
- `train_station_owner_frame.png`.

**Videos** (the brief's codes):
- T1, Official Trailer: https://www.youtube.com/watch?v=fS35YSjopjE
- T2, Official Trailer 2: https://www.youtube.com/watch?v=lYXtL5TreOE
- FE, Official Fan Edit Trailer: https://www.youtube.com/watch?v=Dr060OLTodE
- TVk, TV spot "keep": https://www.youtube.com/watch?v=ITJWMDcOizk
- IMAX film clip: https://www.youtube.com/watch?v=ilUGc9ozPY4

**The books and the films' sets**
- Wikipedia, *Sunrise on the Reaping*: https://en.wikipedia.org/wiki/Sunrise_on_the_Reaping
- Ink and Imaginings, chapter-by-chapter recap: https://inkandimaginings.com/sunrise-on-the-reaping-chapter-by-chapter-recap/
- LitCharts, *Sunrise on the Reaping* chapter 16: https://www.litcharts.com/lit/sunrise-on-the-reaping/chapter-16
- LitCharts, *Catching Fire* chapter 23: https://www.litcharts.com/lit/catching-fire/chapter-23
- Shmoop, *Catching Fire* chapter 23: https://www.shmoop.com/study-guides/catching-fire/chapter-23-summary.html
- SoftSchools, *Catching Fire* chapters 22–24: https://www.softschools.com/literature/summary/catching_fire/catching_fire_chapters_22_24_summary
- The real *Catching Fire* lagoon set from the air:
  - https://www.theblaze.com/news/2013/01/31/google-earth-satellite-image-reveals-outdoor-water-park-set-for-hunger-games-sequel
  - https://www.slashfilm.com/quarter-quell-arena-from-the-hunger-games-catching-fire-revealed/

**Roblox** (checked on 14 November 2026)
- Community Standards (animal abuse and torture are prohibited): https://about.roblox.com/community-standards
- Content ratings (violence against non-humans, "such as animals", is declared in the questionnaire): https://create.roblox.com/docs/production/promotion/content-ratings
- Content maturity (alcohol only under the strictest age restrictions): https://create.roblox.com/docs/production/promotion/content-maturity
- Model streaming, level of detail, `AddPersistentPlayer`: https://create.roblox.com/docs/reference/engine/classes/Model.md and https://create.roblox.com/docs/reference/engine/enums/ModelStreamingMode
- Streaming, and its techniques (`RequestStreamAroundAsync`): https://create.roblox.com/docs/workspace/streaming and https://create.roblox.com/docs/workspace/streaming/techniques
- The 1,000-byte cap on unreliable remote events: https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent.md
- `ReservedServerId`, and the deprecation of `ShouldReserveServer`: https://create.roblox.com/docs/reference/engine/classes/TeleportOptions.md
- Terrain (`WriteVoxelChannels`, `SetMaterialSlot`): https://create.roblox.com/docs/reference/engine/classes/Terrain.md
- `Highlight` (at most 31 shown at once): https://create.roblox.com/docs/reference/engine/classes/Highlight
- Accessibility (Reduce Motion): https://create.roblox.com/docs/en-us/production/publishing/accessibility
