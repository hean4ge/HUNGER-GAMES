# #ARENA 48: music briefs (20 Nov 2026)

The owner wants the score to feel like a dystopian survival-film score: tense, rhythmic and strange. Every track must be **original**. Do not copy, quote, sample or "sound-alike" any existing film cue, melody or recording. Name the style, never a piece. In a prompt for a music tool, describe the instruments and the mood. Do not name a composer or a film.

## The sound world (shared by every cue)

- **Strings played strangely**: col legno taps, bow scrapes and overpressure, sul ponticello tremolo, harmonics, slow glissandi, bowed metal (cymbal, waterphone), and plucked or prepared piano (paper or bolts on the strings).
- **Low brass**: tuba, bass trombone and contrabass clarinet, held long and swelling, sometimes in clusters. No heroic horn melodies.
- **Odd percussion**: frame drum, log drum, bass drum with the snares off, ticking woodblocks, a clock, scraped tam-tam, and hand claps in uneven groups.
- **Breath and voice**: wordless only. Use breathing in rhythm, whispers with no words, hummed drones, a solo female voice on open vowels, and short "ha" or "hm" pulses. Never intelligible words, never screams.
- **Glitch synth pulses**: dry, clicky sub-pulses, bit-crushed ticks and gated noise. Use them sparingly, as a cold, controlled machine underneath the organic sounds.
- **Silence as tension**: phrases stop dead and gaps are written in. A cue can drop to one held note or nothing for 4-8 bars.
- **Rhythm**: uneven meters (7/8, 5/4, 3+3+2), ostinatos that shift by a beat and stabs off the beat.
- **Mix**: dry and close for the plucks and breaths, with wide reverb only on the low swells. Master each bed around **-16 LUFS** integrated and each sting around **-14 LUFS**. The game sets the level per cue.
- **Rating**: Mild. No gore sounds and no cries. Menace comes from texture and rhythm, never from violence.

## File rules

- Format: OGG or MP3, 44.1 kHz stereo. Each file should be under 7 minutes, which is Roblox's audio limit; most cues here are 1-3 minutes.
- Loops: make the loop body seamless at the bar line. Put any intro before the loop start and any ending tail after the loop end, and write both times down in seconds. They go into `Sounds.MusicCues[<cue>].loop = { start, end }`.
- Stings: no loop. Give the sting a natural decay and end it in silence.
- To drop a track in, upload the file and put its asset id in `CUSTOM_MUSIC.<Cue>` in `src/ReplicatedStorage/Shared/Sounds.lua`. Then set the loop points in `Sounds.MusicCues`, and match the entry's `volume` so the cue's mean level matches the one it replaces. The current targets are listed per cue below, as dB RMS after volume.

## Cues

| Cue | When it plays | Tempo · meter | Instruments | Mood | Length · loop | Level target |
|---|---|---|---|---|---|---|
| **Lobby** | The red train lobby, between rounds | ~66 BPM, 4/4 that rubs against a 3-note ostinato | Prepared piano (muted, bolt-buzz), sul tasto viola, a low hummed drone, one distant tuba note every 8 bars, a faint clock tick | A gilded waiting room. Polite on the surface, cold underneath. You are being watched. | 2:30-3:00 · intro 0:00-0:06, loop 0:06-2:50 | -29 dB |
| **Ride** | The train ride to the Training Centre (TrainStage "Ride") | 92 BPM in 7/8 (2+2+3), the train's pulse | Col legno strings in ostinato, a dry synth sub-pulse on the "rail joints", brushed snare (snares off), a breathy "hm" on the off-beat, a celli line rising slowly | Motion you cannot stop. Fast, controlled, quietly fearful. | 2:30 · loop 0:04-2:32 | -28 dB |
| **Training** | The Training Centre hall (AtTrainingCentre / InTraining) | 104 BPM, 4/4 with 5/4 bars | Ticking woodblocks, frame drum, pizzicato basses, short brass stabs, vocal "ha" pulses, glitch ticks; builds in layers every 16 bars | Practice under observation. Focused, competitive, a little cruel. | 2:40 · intro 0:00-0:40, loop 0:40-2:40 | -28 dB |
| **RedRoom** | The red room before the launch (InRedRoom) | No pulse (rubato), with one heartbeat-like low drum at ~50 BPM | Bowed cymbal, contrabass harmonics, overpressure cello scrape, very low brass cluster, a whispered breath every few bars, long silences | Dread. Your name is about to be called. | 2:00 · loop 0:03-1:55 | -29 dB |
| **Rise** | The glass case and the rise up the tube (ClientState.launchShot) | No pulse | A solo female voice on "oo", one note that slowly bends up a semitone; a high string harmonic; a sub swell that grows to the top | Rising into light. Held breath. It should open, not hit; the ambience takes over at the top. | 0:30-0:40 · loop the whole file, or loop 0:04-0:34 | -31 dB |
| **Countdown** | On the plate, the seconds before the horn | 120 BPM ticking (an 8th-note clock) | Clock tick, muted piano repeating one note, a low tuba pedal, bass drum on the downbeat every 2 bars, breathing in time with the clock | The longest ten seconds. Tight and still. **Cut dead at the horn** (the game cuts it in 0.12 s). | 1:00 · loop 0:01-0:57 | -27 dB |
| **Scramble** | From 2.4 s after the horn, for 45 s (the run for the Horn) | 140 BPM in 3+3+2 | Full low percussion (log drums, bass drum, toms), stabbed low brass, string runs in col legno, gasped breath accents, a glitch pulse doubling the kick | Panic and speed. The hardest-hitting cue in the game. It **starts on a downbeat** with no fade (fadeIn 0.25 s). | 1:10 · loop 0:02-1:10 | -24 dB |
| **Explore** | Calm stretches of the round (110 s on, 70 s of silence, repeating) | ~60 BPM, almost no pulse | A deep legato string drone, a single prepared-piano note now and then, a soft breath | Alone in a beautiful, dangerous place. Barely there. | 1:15 · loop 0:04-1:10 | -32 dB |
| **Night** | Arena night (ClockTime between about 19:30 and 06:00) | Rubato | Sul ponticello tremolo swells that rise and vanish, a low hum, distant tam-tam scrape, long silences between phrases | Cold and exposed. Something moves out there. | 3:00+ · loop 0:04-3:20 | -31 dB |
| **Hunt** | The Feast, or 5 or fewer left | 84 BPM, 5/4 | Deep strings in slow glissandi, distant muffled bass drum, pizzicato heartbeat pairs, a whispering breath pulse | Predators circling. Patient, heavy. | 3:00+ · loop 0:05-3:25 | -28 dB |
| **Border** | The border moving or closing (BorderShrinking / BorderMoving) | 112 BPM, rising | A two-note string ostinato that climbs a step every 8 bars, cimbalom or prepared-piano tremolo, glitch ticks speeding up, low brass swells | The walls are coming in. Urgency without panic. | 1:00 · loop 0:01-0:56 | -26 dB |
| **LastStand** | The Last Stand, or 2 left | 132 BPM, 4/4 against 3 | Everything: drums, brass clusters, scraping strings, a choir of breaths, a solo voice on top; drops to a single held note for 2 bars every 16 | The final fight. Huge, but still strange, never triumphant. | 1:30 · intro to 0:28, loop 0:30-0:57 (or a longer body) | -23 dB |
| **Sting_Defeat** | When you fall (YouDied) | No pulse | A low string chord that sinks, a muffled drum hit, a solo voice that fades out on one note | Loss. Quiet and final. No sob, no scream. | 0:12-0:16, ending in silence | -25 dB |
| **Victory** | The winner is named | Rubato | Small string ensemble, solo voice, one soft low-brass swell. Bittersweet, not a fanfare | You survived, and it cost something. | 0:12-0:15 | -21 dB |

## How the game uses them (MusicController)

- One cue at a time, cross-faded with an equal-power curve. A third change during a cross-fade cuts the oldest bed in 0.35 s, so there are never more than two beds plus a sting.
- **Ducks**: under combat, the bed drops to 45 % for 6 s after any hit you give or take. Under an announcement (Warning, Banner, Headline) it drops to 50 %. Under the horn, cannon, feast bell and border warning it follows AudioController's ducks. Under a sting it drops to 15 %.
- **The horn**: the Countdown cuts out, the horn rings alone for 2.4 s, then the Scramble hits. Make the Scramble's first beat strong.
- **The Roll Call** (the fallen in the sky): no music at all (FallenRecapController suppresses it).
- **Volume settings**: Music, Effects and Ambience sliders exist. A master volume is supported in code (`settings.masterVolume`) but has no slider or save key yet.
