--[[
	Sounds - every sound in the game, by key. Code plays them with Shared.Sfx, e.g. Sfx.play("Cannon").
	Keys are a contract between systems; the Audio system owns this file and fills in the ids.
	Entry fields:
	  ids      list of "rbxassetid://<id>" (one is picked at random). Empty = silent, which is safe.
	  volume   0..10. STARTING levels by role (18 Nov 2026 replacement): the new recordings have not been heard or
	           measured yet. Entries marked "measured" keep their balanced level from before.
	  pitch    { min, max } random playback speed (a narrow natural spread; no recording is pitched into another job)
	  group    "SFX" | "Music" | "Ambience" | "UI"   (SoundGroups in SoundService)
	  looped   true for loops (the caller stops them)
	  rollMin / rollMax   3D distances in studs
	  maxLifetime   seconds before a one-shot is cleaned up (default 12)
	  regions  optional slices of a longer recording: { { id, from, to, gain } } (seconds).
	           The AudioController plays them with Sound.PlaybackRegion, and it also applies them to sounds played
	           through Shared.Sfx on a client (it wraps Sfx.play), so a multi-take file can be cut here without
	           touching any call site. Region-only entries (footsteps, Jump, Mantle, Climb) have empty ids, so
	           Sfx.play on them is a silent no-op.
	  gains    optional { [id] = gain }: evens out takes of one key recorded at different levels (20 Nov measurements)
  layers   optional { { key, delay?, volume? } }: other keys played with this one (AudioController), e.g. a sub boom
  loopRegion  optional { from, to } for a looped entry: only that steady middle loops (AudioController loops)
Music: the Music_* beds, the Sting_* stings and Sounds.MusicCues (which cue plays which bed, how it fades and loops)
  are the MusicController's; custom tracks drop into CUSTOM_MUSIC below.
One recording has one job (SlideLoop is the steady middle of Slide's take, looped: the same job): no id appears under two keys (tools: the audition list names every key's recording).
	Sources: Pro Sound Effects and APM Music libraries on Roblox (licensed, free for any experience), the
	"CharacterAudio" walking/climbing set (AmbientSorcery), and one Creator Store upload (BreathHeavy).
	The game has no blood and no wounds: no voice other than breathing, no wet or tearing impacts, nothing gun-like.
]]
local Sounds = {}

local function def(group: string, volume: number, extra: { [string]: any }?)
	local entry = extra or {}
	entry.ids = entry.ids or {}
	entry.group = group
	entry.volume = volume
	return entry
end

local function rbx(id: number): string
	return "rbxassetid://" .. tostring(id)
end

-- { { from, to, gain }, ... } of one asset -> region list
local function slices(id: number, list: { { number } })
	local out = {}
	for _, s in ipairs(list) do
		table.insert(out, { id = rbx(id), from = s[1], to = s[2], gain = s[3] or 1 })
	end
	return out
end

-- Movement. Footsteps: 8 slices per material from one consistent walking set, gain-normalised per step (measured).
Sounds.Footstep_Grass = def("SFX", 1.2, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 70,
	regions = slices(136419331652727, { { 0, 0.561, 1.15 }, { 0.588, 1.158, 0.82 }, { 1.185, 1.755, 0.92 }, { 1.783, 2.353, 1.15 },
		{ 2.38, 2.95, 1.15 }, { 2.977, 3.547, 1.03 }, { 3.575, 4.145, 0.82 }, { 4.172, 4.712, 1.03 } }) })
Sounds.Footstep_Dirt = def("SFX", 2.8, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 70,
	regions = slices(77727540279198, { { 0, 0.561, 1.24 }, { 0.577, 1.147, 0.75 }, { 1.175, 1.745, 0.88 }, { 1.783, 2.353, 1.35 },
		{ 2.38, 2.95, 1.11 }, { 2.967, 3.537, 0.75 }, { 3.564, 4.134, 1.35 }, { 4.161, 4.712, 0.79 } }) })
Sounds.Footstep_Mud = def("SFX", 2.7, { pitch = { 0.92, 1.04 }, rollMin = 6, rollMax = 70,
	regions = slices(126641432599083, { { 0, 0.561, 1.03 }, { 0.577, 1.147, 0.92 }, { 1.175, 1.745, 1.3 }, { 1.783, 2.353, 0.92 },
		{ 2.38, 2.95, 0.92 }, { 2.967, 3.537, 0.75 }, { 3.564, 4.134, 1.03 }, { 4.332, 4.712, 1.3 } }) })
Sounds.Footstep_Rock = def("SFX", 1.1, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 80,
	regions = slices(137073058360744, { { 0, 0.561, 1.27 }, { 0.577, 1.147, 1.13 }, { 1.175, 1.745, 0.8 }, { 1.783, 2.353, 1.01 },
		{ 2.38, 2.95, 1.01 }, { 2.967, 3.537, 1.01 }, { 3.564, 4.134, 1.13 }, { 4.172, 4.712, 0.75 } }) })
Sounds.Footstep_Wood = def("SFX", 1.08, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 80,
	regions = slices(135105622039627, { { 0, 0.561, 0.92 }, { 1.175, 1.745, 1.04 }, { 1.783, 2.353, 0.82 }, { 2.38, 2.95, 1.3 },
		{ 2.967, 3.537, 0.92 }, { 3.575, 4.145, 1.04 } }) })
Sounds.Footstep_Sand = def("SFX", 0.9, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 60,
	regions = slices(100753939042323, { { 0, 0.561, 1 }, { 0.588, 1.158, 0.88 }, { 1.175, 1.745, 1 }, { 1.783, 2.353, 1 },
		{ 2.38, 2.95, 1.11 }, { 2.967, 3.537, 1 }, { 3.575, 4.145, 1 }, { 4.172, 4.712, 1.11 } }) })
Sounds.Footstep_Snow = def("SFX", 1.24, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 60,
	regions = slices(133192114618261, { { 0, 0.561, 1.13 }, { 0.577, 1.147, 0.9 }, { 1.175, 1.745, 1.13 }, { 1.783, 2.353, 0.9 },
		{ 2.38, 2.95, 0.9 }, { 2.967, 3.537, 1.01 }, { 3.564, 4.134, 1.13 }, { 4.172, 4.712, 0.9 } }) })
Sounds.Footstep_Metal = def("SFX", 1.15, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 90,
	regions = slices(84752055576439, { { 0.001, 0.571, 0.87 }, { 0.599, 1.169, 0.87 }, { 1.196, 1.766, 1.22 }, { 1.793, 2.359, 0.97 },
		{ 2.369, 2.939, 1.22 }, { 2.967, 3.537, 0.87 }, { 3.564, 4.134, 0.87 }, { 4.172, 4.712, 1.22 } }) })
-- wading: six single puddle stomps, one per file (PSE "Puddle Stomps Small Water Splashes" 2, 3, 4, 5, 6, 18)
Sounds.Footstep_Water = def("SFX", 1.0, { pitch = { 0.94, 1.06 }, rollMin = 6, rollMax = 80,
	ids = { rbx(9117946658), rbx(9117946641), rbx(9117946651), rbx(9117946851), rbx(9117946863), rbx(9117947974) } })
Sounds.Jump = def("SFX", 1.1, { pitch = { 0.95, 1.08 }, rollMin = 6, rollMax = 50,
	regions = slices(9113820748, { { 0.268, 0.781, 1 }, { 0.791, 1.311, 1.4 } }) }) -- cloth push-off (PSE, measured)
Sounds.Land_Soft = def("SFX", 2.6, { pitch = { 0.9, 1.05 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9118686853), rbx(9118685780) } }) -- two-foot thud on earth (PSE, measured)
Sounds.Land_Hard = def("SFX", 0.7, { pitch = { 0.92, 1.02 }, rollMin = 8, rollMax = 100, maxLifetime = 4,
	ids = { rbx(9113469796), rbx(9113469775) }, gains = { [rbx(9113469775)] = 3.5 } })
-- "Body Fall Dirt" 4 and 2: a real drop (PSE). 20 Nov: take 2 measured 13.6 dB under take 4; its gain evens them.
Sounds.Slide = def("SFX", 1.0, { pitch = { 0.95, 1.06 }, rollMin = 6, rollMax = 70, maxLifetime = 4,
	ids = { rbx(9114658419) } }) -- "Gravel Slide 2": body and boots on earth (PSE); the caller fades it when the slide ends
-- the scrape held under a long slide (AudioController: level and pitch follow the slide speed). The steady middle of
-- the same take, looped (loopRegion, seconds), so a slide of any length keeps sounding like the same slide.
-- Measured envelope (RMS, 0.1 s): sound from 0.2 s, -20..-29 dB to 1.6 s, tailing off by 2.1 s, silent after.
Sounds.SlideLoop = def("SFX", 0.55, { looped = true, loopRegion = { 0.3, 1.55 }, ids = { rbx(9114658419) } })
-- hand-holds: the climbing loop of the walking set. Mantle and Climb use different slices of it (measured).
Sounds.Mantle = def("SFX", 1.4, { pitch = { 0.95, 1.05 }, rollMin = 6, rollMax = 50,
	regions = slices(114640039515382, { { 0.588, 1.158, 1 }, { 3.575, 4.145, 1.12 }, { 4.183, 4.712, 1.12 } }) })
Sounds.Climb = def("SFX", 1.4, { pitch = { 0.92, 1.08 }, rollMin = 6, rollMax = 50,
	regions = slices(114640039515382, { { 0.012, 0.578, 1.35 }, { 1.196, 1.766, 1.12 }, { 1.783, 2.353, 1.26 },
		{ 2.391, 2.961, 0.89 }, { 2.977, 3.547, 1.26 } }) })
Sounds.Swim = def("SFX", 0.7, { pitch = { 0.95, 1.05 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9120589166) } }) -- "Water Splashing Swimming Stroke 2": own strokes, looped by the AudioController (PSE)
Sounds.SwimStroke = def("SFX", 1.5, { -- (20 Nov: 0.6 measured peak -28.5 dB, under the own-swim loop by 21 dB) pitch = { 0.92, 1.04 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9119481690) } }) -- "Splash Slightly Boomy 2": another contender's stroke, 3D (PSE)
Sounds.WaterSplash = def("SFX", 0.95, { pitch = { 0.92, 1.08 }, rollMin = 8, rollMax = 100,
	ids = { rbx(9119481909), rbx(9119476512) } }) -- a body entering water (PSE, measured)
Sounds.Underwater = def("Ambience", 0.5, { looped = true, ids = { rbx(9112889917) } }) -- "Underwater Ambience 1": bed while the camera is under (PSE)
Sounds.BreathHeavy = def("SFX", 0.4, { looped = true, ids = { rbx(124832136911190) } }) -- effort, never distress (Creator Store upload, measured)
Sounds.Heartbeat = def("SFX", 0.22, { looped = true, ids = { rbx(9043365842) } }) -- (APM, measured)

-- Combat. Hits on a contender are dry: cloth and padding, no voice.
Sounds.Swing_Light = def("SFX", 1.2, { pitch = { 0.96, 1.06 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9116904947), rbx(9116904355), rbx(9116904676) }, gains = { [rbx(9116904355)] = 2.4 } })
-- "Metal Tube Swishes" 16, 10, 12: thin metal cutting air (PSE). 20 Nov: take 10 measured 7.8 dB under take 16.
Sounds.Swing_Heavy = def("SFX", 1.2, { pitch = { 0.9, 1.0 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9120729007), rbx(9113305107), rbx(9113318942) } }) -- heavy arm-swing whooshes (PSE)
Sounds.Hit_Flesh = def("SFX", 0.9, { pitch = { 0.94, 1.04 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9119313203), rbx(9119313397) } }) -- "Snowballs Hit Leather Coat Back" 5, 9: dull padded thud (PSE)
Sounds.Hit_Wood = def("SFX", 1.0, { pitch = { 0.92, 1.08 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9120807255), rbx(9120809771) } }) -- single chops into wood (PSE, measured)
Sounds.Hit_Stone = def("SFX", 0.7, { pitch = { 0.94, 1.06 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9116616748), rbx(9116616591) } }) -- metal on stone: sharp hit, muted ring (PSE)
Sounds.Hit_Metal = def("SFX", 0.8, { pitch = { 0.94, 1.06 }, rollMin = 8, rollMax = 100,
	ids = { rbx(9119072660), rbx(9119072674) } }) -- "Shield Clang As Hit" 1, 2 (PSE)
Sounds.Hit_Earth = def("SFX", 2.2, { pitch = { 0.92, 1.06 }, rollMin = 8, rollMax = 80,
	ids = { rbx(9118688024), rbx(9118686201) } }) -- a blade or arrow into soil (PSE). Needs the surface maps to name it.
Sounds.BowDraw = def("SFX", 0.8, { pitch = { 0.97, 1.03 }, rollMin = 6, rollMax = 50, maxLifetime = 4,
	ids = { rbx(9125407169) } }) -- "Bow Stretches Wood Creaking": the limbs and string under load (PSE)
Sounds.BowRelease = def("SFX", 0.6, { pitch = { 0.97, 1.03 }, rollMin = 8, rollMax = 120, maxLifetime = 4,
	ids = { rbx(9113166206), rbx(9113166218) } }) -- "Arrow Out" 1, 2: close launch, the arrow hissing away (PSE)
Sounds.BowDry = def("SFX", 0.6, { pitch = { 0.97, 1.03 }, maxLifetime = 3,
	ids = { rbx(9125406749) } }) -- an empty draw: a short creak (PSE). Needs CombatController to play it for "No arrows".
Sounds.ArrowImpact = def("SFX", 0.9, { pitch = { 0.94, 1.08 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9120949071), rbx(9120951152) } }) -- wood driven into soft ground: a short thunk (PSE)
Sounds.ArrowWhiz = def("SFX", 0.8, { pitch = { 0.98, 1.1 }, rollMin = 4, rollMax = 40,
	ids = { rbx(9114374276), rbx(9114373678) }, gains = { [rbx(9114373678)] = 2.8 } })
-- "Fast Pass By Airy Whooshes" 11, 4 (PSE). 20 Nov: take 4 measured 9 dB under take 11.
Sounds.ArrowWater = def("SFX", 0.5, { pitch = { 0.96, 1.08 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9125702803) } }) -- an arrow into water: a small plip (PSE). Needs ProjectileController to name it.
Sounds.Throw = def("SFX", 1.2, { pitch = { 0.92, 1.0 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9113318154), rbx(9113318407) } }) -- "Baseball Swish" 2, 5: an arm throw (PSE)
Sounds.Equip_Blade = def("SFX", 0.6, { pitch = { 0.96, 1.04 },
	ids = { rbx(9116194425), rbx(9116190816), rbx(9116190959) }, gains = { [rbx(9116190816)] = 3.5 } })
-- a knife leaving leather (PSE). 20 Nov: take 15 (9116190816) measured 11.5 dB under the sheath pull.
Sounds.Equip_Bow = def("SFX", 0.7, { pitch = { 0.96, 1.04 }, ids = { rbx(9120880314) } }) -- a hand taking hold of wood (PSE)
-- "Leather Bible 26": a leather grab (PSE). Measured 20 Nov: peak -35 dB after volume at 0.6, 13-19 dB under the other
-- equips (inaudible in play); 3.0 puts it at -21 dB, between the bow (-23) and the blade (-17).
Sounds.Equip_Generic = def("SFX", 3.0, { pitch = { 0.95, 1.05 }, ids = { rbx(9116252627) } })
-- (HitMarker keeps its 1.34-1.42 pitch: CombatController plays the headshot at 1.62, a little brighter than this.)
Sounds.HitMarker = def("UI", 0.7, { pitch = { 1.34, 1.42 }, maxLifetime = 3, ids = { rbx(9120917813) } }) -- a small dry wooden tick (PSE)
Sounds.HitMarkerKill = def("UI", 0.7, { pitch = { 0.96, 1.0 }, maxLifetime = 4, ids = { rbx(9119975775) } }) -- one low wooden knock (PSE)
Sounds.Hurt = def("SFX", 0.9, { pitch = { 0.92, 1.0 }, maxLifetime = 4, ids = { rbx(9119313205) } }) -- "Snowballs Hit Leather Coat Back 4": close muffled thump (PSE)
-- a defeated body reaching the ground, played by the AudioController at the body (no voice). Was the unused "Death".
Sounds.BodyFall = def("SFX", 0.7, { pitch = { 0.94, 1.0 }, rollMin = 8, rollMax = 90, maxLifetime = 5,
	ids = { rbx(9113469691), rbx(9113469779) }, gains = { [rbx(9113469779)] = 2.5 } })
-- "Body Fall Dirt" 1, 3 (PSE). 20 Nov: take 3 measured 8.9 dB under take 1.

-- Items
Sounds.CrateOpen = def("SFX", 0.8, { pitch = { 0.95, 1.05 }, rollMin = 8, rollMax = 90, maxLifetime = 4,
	ids = { rbx(9120873789) } }) -- "Wooden Chest Open Close Cedar Box 9": latch and lid (PSE)
Sounds.CrateLand = def("SFX", 1.0, { pitch = { 0.92, 1.02 }, rollMin = 10, rollMax = 140, maxLifetime = 4,
	ids = { rbx(9120871244) } }) -- "Wood Drop Wooden Log Fall 2": heavy wood onto dirt (PSE). Needs LootService to name it.
Sounds.DummyBreak = def("SFX", 0.9, { pitch = { 0.94, 1.04 }, rollMin = 8, rollMax = 90, maxLifetime = 4,
	ids = { rbx(9125992732) } }) -- wood splitting (PSE). Needs CombatService to name it.
-- (20 Nov levels: PickUp measured peak -21 dB and Drop -29 dB after volume, far under the other item sounds at -4..-12;
-- raised to about -11 and -15 dB)
Sounds.PickUp = def("SFX", 2.0, { pitch = { 0.96, 1.06 }, ids = { rbx(9116251623) } }) -- "Leather Bible 11": a hand closing on the thing (PSE)
Sounds.Drop = def("SFX", 4.0, { pitch = { 0.92, 1.05 }, ids = { rbx(9114517148) } }) -- "Foliage Drop 5": a small thing landing in grass (PSE)
Sounds.Eat = def("SFX", 0.7, { pitch = { 0.96, 1.04 }, maxLifetime = 4, ids = { rbx(9113138343) } }) -- "Apple Chew 1": a bite and a chew (PSE)
Sounds.Drink = def("SFX", 1.0, { pitch = { 0.95, 1.05 }, ids = { rbx(9114171960), rbx(9114172109) } }) -- two or three swallows (PSE, measured)
Sounds.CanteenFill = def("SFX", 0.6, { pitch = { 0.96, 1.04 }, rollMin = 6, rollMax = 60, maxLifetime = 4,
	ids = { rbx(9125506910) } }) -- water glugging into a bottle (PSE). Needs the inventory code to name it.
-- linen tearing (PSE). 20 Nov: the second take (9113834008) measured peak -55 dB raw, near silence, so half of all
-- bandaging made no sound; it is dropped.
Sounds.Bandage = def("SFX", 0.65, { pitch = { 0.95, 1.05 }, ids = { rbx(9113827551) } })
Sounds.ArmorOn = def("SFX", 1.0, { pitch = { 0.95, 1.05 }, maxLifetime = 4, ids = { rbx(9113241604) } }) -- "Backpack Movement 2": canvas, straps (PSE)
Sounds.InventoryFull = def("UI", 0.9, { pitch = { 0.96, 1.0 }, maxLifetime = 3, ids = { rbx(9125654847) } }) -- a dull knock on wood: "no" (PSE)

-- Round
Sounds.Cannon = def("SFX", 2.5, { pitch = { 0.8, 0.82 }, maxLifetime = 15, ids = { rbx(9114363528) },
	layers = { { key = "Cannon_Sub" } } }) -- the only sound of a defeat (PSE, measured); the sub boom gives it weight
-- layer under the cannon's crack: "Deep Hits Big Reverberant Booms Rumbling Tail" (PSE), 4.4 s, rms -20.7 dB raw.
-- At 0.45 it sits about 8 dB under the crack (cannon -18.9 dB rms after volume). TO AUDITION.
Sounds.Cannon_Sub = def("SFX", 0.45, { pitch = { 0.86, 0.88 }, maxLifetime = 8, ids = { rbx(9125484367) } })
Sounds.CountdownTick = def("UI", 0.8, { pitch = { 0.98, 1.0 }, maxLifetime = 3, ids = { rbx(9120896809) } }) -- "Wood Impact 1": one hollow knock a number (PSE)
-- "Horn Blow 4": a ram's horn (PSE). Measured 20 Nov: rms -26.1 dB at 1.0, 7 dB under the cannon, though it is the
-- round's start signal; raised to 1.8 (-21 dB) with a deep swell under it (StartHorn_Low).
Sounds.StartHorn = def("SFX", 1.8, { pitch = { 0.98, 1.0 }, maxLifetime = 15, ids = { rbx(9114820717) },
	layers = { { key = "StartHorn_Low" } } })
-- "Energy Blast Big Deep Horn Swell Reverberant" (PSE), 7 s, blooms 1.6 s in, under the horn's held note. TO AUDITION.
Sounds.StartHorn_Low = def("SFX", 0.45, { pitch = { 0.94, 0.95 }, maxLifetime = 9, ids = { rbx(9125544480) } })
-- the winner: "Lost (sting a)" (APM, KPM Dark Drama), 13 s: small strings and a wordless soprano, more bittersweet than
-- the old brass fanfare ("Conquering Heroes Link" 83315768373322). TO AUDITION. A custom id goes in CUSTOM_MUSIC.Victory.
Sounds.Victory = def("Music", 1.0, { maxLifetime = 16, ids = { rbx(9043590268) } })
Sounds.BorderWarning = def("UI", 0.7, { pitch = { 0.8, 0.82 }, maxLifetime = 8, ids = { rbx(9114820892) } }) -- "Horn Blow 6": a second, lower horn call (PSE)
Sounds.BorderHum = def("SFX", 0.5, { looped = true, rollMin = 20, rollMax = 200, ids = { rbx(9116386858) } }) -- "Magic Force Field Constant 2": the wall (PSE)
Sounds.FeastBell = def("SFX", 0.8, { pitch = { 0.98, 1.0 }, maxLifetime = 15, ids = { rbx(9113804175) } }) -- one large bell, long ring (PSE)
-- (no Sounds.RollCall: the Roll Call never has an anthem or a music bed, only the static and the low tone below)
-- The Fallen (Roll Call show in the sky, FallenRecapController) and the launch plates (LaunchController).
-- Owned by the day/night system. `region` = { from, to } seconds of the source used (PlaybackRegion).
-- Levels measured with an AudioAnalyzer: static bed ~-22 dB RMS, bell hum ~-26 dB (faded in as each piece assembles),
-- lift whir ~-29 dB with its clunk at 9.5 s.
Sounds.RollCallStatic = def("SFX", 0.3, { looped = true, region = { 1.0, 17.5 }, ids = { rbx(9126097384) } }) -- TV static, constant (PSE)
Sounds.RollCallCrackle = def("SFX", 0.2, { looped = true, ids = { rbx(9117163436) } }) -- optical noise: zaps, pops (PSE)
Sounds.RollCallBurst = def("SFX", 0.3, { maxLifetime = 5, ids = { rbx(9117060042), rbx(9118026602) } }) -- static bursts (PSE)
Sounds.RollCallTone = def("SFX", 1.0, { maxLifetime = 22, ids = { rbx(9126005605) } }) -- low resolving tone: deep bell hum (PSE)
Sounds.RollCallToneSoft = def("SFX", 0.6, { maxLifetime = 14, ids = { rbx(9126005637) } }) -- the same, softer, per contender (PSE)
Sounds.PlateRise = def("SFX", 1.6, { rollMin = 14, rollMax = 140, maxLifetime = 9, ids = { rbx(9116982970) } }) -- lift whir + clunk (PSE)
Sounds.PlateLock = def("SFX", 0.6, { rollMin = 14, rollMax = 150, maxLifetime = 4, ids = { rbx(9125681884) } }) -- one heavy metal thunk, short ring (PSE)
-- The launch shot's own sounds (LaunchIntroController reads ids[1] and the volume; it passes pitch and looping itself).
Sounds.Launch_RoomTone = def("SFX", 0.36, { looped = true, ids = { rbx(9112795463) } }) -- "Hollow Rumble 1": the hall (PSE, the level it had as the old BorderHum)
-- "Air Chuff 4": the case sealing (PSE). 20 Nov: peak -30 dB after volume at 0.7, 20 dB under the launch's other
-- sounds; 2.5 puts it at -19 dB.
Sounds.Launch_Seal = def("SFX", 2.5, { maxLifetime = 4, ids = { rbx(9113059926) } })
Sounds.Launch_Rise = def("SFX", 0.6, { looped = true, ids = { rbx(9118747853) } }) -- "Interior Wind Turbo Shaft 5": shaft air on the way up (PSE)
Sounds.Launch_Arrive = def("SFX", 0.6, { maxLifetime = 4, ids = { rbx(9125807267) } }) -- "Rising Whoosh Hissing Suck Burst": the shaft noise cutting off (PSE)
Sounds.Launch_Glare = def("SFX", 0.25, { maxLifetime = 9, ids = { rbx(9114630613) } }) -- "Gong No Hit 2": a soft ring under the sun glare (PSE)

-- UI: physical, soft and short (a switch, wood, paper), never a bleep
Sounds.UIClick = def("UI", 0.8, { pitch = { 0.98, 1.04 }, maxLifetime = 2, ids = { rbx(9119717523) } }) -- "Switch Click Toggle Button 2" (PSE)
Sounds.UIHover = def("UI", 0.3, { pitch = { 1.0, 1.06 }, maxLifetime = 2, ids = { rbx(9119717950) } }) -- "Switch Clicks Metallic Dull Pops 7", barely there (PSE)
Sounds.Notify = def("UI", 0.5, { pitch = { 0.98, 1.02 }, maxLifetime = 3, ids = { rbx(9120917609) } }) -- one soft wooden note (PSE)
-- (20 Nov: peak -32 dB after volume at 0.6, 26 dB under UIClick; 4.0 puts it at -15)
Sounds.UIOpen = def("UI", 4.0, { pitch = { 0.98, 1.04 }, maxLifetime = 3, ids = { rbx(9118835802) } }) -- a leather-bound book opening (PSE). For panels; nothing plays it yet.
Sounds.Board_Line = def("SFX", 0.7, { pitch = { 0.96, 1.04 }, rollMin = 6, rollMax = 60, maxLifetime = 3,
	ids = { rbx(9120917794) } }) -- a slat settling on a physical board, 3D (PSE). For the results board; nothing plays it yet.

-- Ambience beds (looped, 2D; mixed by the AudioController per biome and time of day)
Sounds.Amb_ForestDay = def("Ambience", 2.0, { looped = true, ids = { rbx(9112806424) } }) -- "Jungle Dawn 1": light birds, woods (PSE loop)
Sounds.Amb_ForestNight = def("Ambience", 0.6, { looped = true, ids = { rbx(9112764891) } }) -- "Crickets Night 3" (PSE loop)
Sounds.Amb_Swamp = def("Ambience", 0.63, { looped = true, ids = { rbx(9112763270) } }) -- (PSE, measured)
Sounds.Amb_Highlands = def("Ambience", 2.0, { looped = true, ids = { rbx(9112832288) } }) -- (PSE, measured)
Sounds.Amb_Lake = def("Ambience", 0.7, { looped = true, ids = { rbx(9120572331) } }) -- "Water Lap Small Waves 1": lake shore (PSE)
Sounds.Amb_Lobby = def("Ambience", 1.8, { looped = true, ids = { rbx(9112832297) } }) -- (PSE, measured)
Sounds.Amb_PineForest = def("Ambience", 1.4, { looped = true, ids = { rbx(9112761455) } }) -- (PSE, measured)
Sounds.Amb_Wind = def("Ambience", 1.2, { looped = true, ids = { rbx(9116258282) } }) -- "Leaves Rustle Wind Blowing Through Trees 2" (PSE)
-- Emitters (looped, 3D on AmbientEmitter parts; SoundKey attribute)
Sounds.Emit_River = def("Ambience", 0.6, { looped = true, rollMin = 15, rollMax = 120, ids = { rbx(9119646409), rbx(9119646356) } }) -- (PSE, measured)
Sounds.Emit_Waterfall = def("Ambience", 0.45, { looped = true, rollMin = 25, rollMax = 220, ids = { rbx(9116496316) } }) -- (PSE, measured)
Sounds.Emit_Fire = def("Ambience", 0.7, { looped = true, rollMin = 6, rollMax = 50, ids = { rbx(9112780193) } }) -- "Fireplace Constant Burning Flame 1" (PSE loop)
Sounds.Emit_Wind = def("Ambience", 0.35, { looped = true, rollMin = 30, rollMax = 200, ids = { rbx(9114057128) } }) -- "Desert Wind Whistley Light Gusts 2" (PSE)
Sounds.Emit_Frogs = def("Ambience", 1.4, { looped = true, rollMin = 15, rollMax = 120, ids = { rbx(9112762863) } }) -- (PSE, measured)

-- Arena challenges (HazardController; integrate 18 Nov, public ProSoundEffects library audio, nothing uploaded)
Sounds.Hazard_Flutter = def("SFX", 0.5, { looped = true, ids = { rbx(9113992932) } }) -- "Creature Wings 3": bat or flying insect flaps
Sounds.Hazard_Sting = def("SFX", 0.35, { ids = { rbx(9113977177) } }) -- "Creature Mix Big Flying Insects 1": a soft buzz-tap
Sounds.Hazard_ColdWind = def("Ambience", 0.6, { looped = true, ids = { rbx(9113203785) } }) -- "Attic Wind Whistley Cold Hollow 1"
Sounds.Hazard_Thunder = def("SFX", 0.9, { rollMin = 60, rollMax = 1600, ids = { rbx(9120020225), rbx(9120019063) } }) -- "Thunder Lightning 3 / 4": crack + rumble tail
Sounds.Hazard_Rain = def("Ambience", 0.7, { looped = true, ids = { rbx(9112854469) } }) -- "Rain On Water 1" (loop)
Sounds.Hazard_StormWind = def("Ambience", 0.9, { looped = true, ids = { rbx(9116258282) } }) -- same take as Amb_Wind (leaves and wind)
Sounds.Hazard_Rumble = def("SFX", 0.8, { looped = true, rollMin = 20, rollMax = 400, ids = { rbx(9125875511) } }) -- "Rock Rumble Constant Scraping Movement Rolling"

-- Music (20 Nov 2026, wave 18). The MusicController plays one cue at a time and cross-fades between them (see its
-- header for when each cue plays). The owner asked for tense, rhythmic, strange music in the spirit of a dystopian
-- survival film score, ORIGINAL (nothing copied or sampled). Until custom tracks exist, each cue uses a licensed APM or
-- PSE library track (Roblox's licensed partners, free for any experience), all marked TO AUDITION: chosen by their
-- descriptions, lengths and measured loudness (AudioAnalyzer RMS, wave18/music-sfx/notes.md), not yet heard.
-- Levels: volume puts each track's mean RMS at the cue's target (beds -29..-23 dB, stings -25..-21 dB, before the
-- Music volume setting), so cues swap without a jump in loudness.
--
-- CUSTOM TRACKS DROP IN HERE: put the uploaded asset id against the cue (a number). A custom id replaces the library
-- pick for that cue; set its loop points in MusicCues below (or leave `loop` nil to loop the whole file). Briefs for
-- each cue: docs/design/MusicBriefs_2026-11-20.md.
local CUSTOM_MUSIC: { [string]: number? } = {
	Lobby = nil, Ride = nil, Training = nil, RedRoom = nil, Rise = nil, Countdown = nil, Scramble = nil, Explore = nil,
	Night = nil, Hunt = nil, Border = nil, LastStand = nil, Sting_Defeat = nil, Victory = nil,
}
local function music(cue: string, libraryId: number, volume: number, extra: { [string]: any }?)
	local entry = extra or {}
	entry.looped = if entry.looped == nil then true else entry.looped
	entry.ids = { rbx(CUSTOM_MUSIC[cue] or libraryId) }
	entry.custom = CUSTOM_MUSIC[cue] ~= nil
	return def("Music", volume, entry)
end
-- beds (looped)
Sounds.Music_Lobby = music("Lobby", 9043586295, 0.78) -- "The Missing (c)" (APM, KPM Dark Drama), 184 s: dark strings, mystery
Sounds.Music_Ride = music("Ride", 9043585671, 0.35) -- "The Investigation (a)" (APM), 164 s: ostinato, synth pulses, ticking perc
Sounds.Music_Training = music("Training", 9042732171, 0.55) -- "Expedition" (APM, JGM Experimental Vocal Score), 173 s: ticking perc, galloping drums
Sounds.Music_RedRoom = music("RedRoom", 9043585865, 1.0) -- "The Monster in You (b)" (APM), 161 s: growling low strings, tremolo, scraped metal
Sounds.Music_Rise = music("Rise", 9125603134, 0.58) -- "Heavenly Presence Eerie Choral Tones Dark Rumbly 2" (PSE), 36 s loop: wordless choir
Sounds.Music_Countdown = music("Countdown", 1840049721, 0.34) -- "Drum Drone (a 60)" (APM, Drones and Pulses), 62 s: bass drum, timpani, triangle
Sounds.Music_Scramble = music("Scramble", 9042732871, 0.47) -- "Lost Voices" (APM, JGM), 102 s: drones, synth brass, pounding drums (0-70 s)
Sounds.Music_Explore = music("Explore", 1840046933, 0.21) -- "Strings Drone (b)" (APM, Drones and Pulses), 76 s: deep legato string drone
Sounds.Music_Night = music("Night", 9043585893, 0.49) -- "Night Search (b)" (APM), 210 s: string swells with long silences
Sounds.Music_Hunt = music("Hunt", 9043585698, 0.79) -- "Guilty (b)" (APM), 215 s: deep strings, glissandi, distant thumps
Sounds.Music_Border = music("Border", 9044407196, 0.5) -- "Back to the Shadows 60A" (APM), 62 s: sinister string waves, cimbalom
Sounds.Music_LastStand = music("LastStand", 9042734591, 0.45) -- "Whale Song" (APM, JGM), 62 s: synth swells, impacts, looming strings
-- stings (one-shots; the MusicController ducks the bed to duckBed for duckTime seconds)
Sounds.Sting_Defeat = music("Sting_Defeat", 9043590038, 0.65, { looped = false, maxLifetime = 17, duckBed = 0.15, duckTime = 12 })
-- "Guilty (sting a)" (APM), 16 s: deep strings, distant thumps, a fragile wordless soprano. Played when you fall.
if CUSTOM_MUSIC.Victory then
	Sounds.Victory.ids = { rbx(CUSTOM_MUSIC.Victory :: number) } -- (Victory itself is defined with the round sounds)
end

-- Cue -> track, level (0..1 of the entry's volume), fades (seconds) and loop points (seconds; LoopRegion, so the
-- intro plays once and the body loops; nil = the whole file). cutIn: the cue that is leaving fades out at most this
-- fast (the horn's hard cut into the scramble). startAt: where in the file the cue begins.
Sounds.MusicCues = {
	Lobby = { key = "Music_Lobby", level = 1, fadeIn = 4, fadeOut = 3, loop = { 6, 172 } },
	Ride = { key = "Music_Ride", level = 1, fadeIn = 3, fadeOut = 3, loop = { 4, 152 } },
	Training = { key = "Music_Training", level = 1, fadeIn = 4, fadeOut = 3, startAt = 40, loop = { 70, 163 } },
	RedRoom = { key = "Music_RedRoom", level = 1, fadeIn = 3, fadeOut = 2, loop = { 3, 150 } },
	Rise = { key = "Music_Rise", level = 0.8, fadeIn = 2, fadeOut = 1.5 },
	Countdown = { key = "Music_Countdown", level = 1, fadeIn = 1.5, fadeOut = 0.12, loop = { 1, 57 } }, -- cut dead at the horn
	Scramble = { key = "Music_Scramble", level = 1, fadeIn = 0.25, fadeOut = 5, loop = { 2, 70 } },
	Explore = { key = "Music_Explore", level = 1, fadeIn = 8, fadeOut = 8, loop = { 4, 70 } },
	Night = { key = "Music_Night", level = 1, fadeIn = 8, fadeOut = 6, loop = { 4, 200 } },
	Hunt = { key = "Music_Hunt", level = 1, fadeIn = 5, fadeOut = 5, loop = { 5, 205 } },
	Border = { key = "Music_Border", level = 1, fadeIn = 3, fadeOut = 4, loop = { 1, 56 } },
	LastStand = { key = "Music_LastStand", level = 1, fadeIn = 2, fadeOut = 3, startAt = 28, loop = { 30, 57 } },
}

return Sounds
