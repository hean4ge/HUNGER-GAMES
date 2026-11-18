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
	One recording has one job: no id appears under two keys (tools: the audition list names every key's recording).
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
	ids = { rbx(9113469796), rbx(9113469775) } }) -- "Body Fall Dirt" 4 and 2: a real drop (PSE)
Sounds.Slide = def("SFX", 1.0, { pitch = { 0.95, 1.06 }, rollMin = 6, rollMax = 70, maxLifetime = 4,
	ids = { rbx(9114658419) } }) -- "Gravel Slide 2": body and boots on earth (PSE); the caller fades it when the slide ends
-- hand-holds: the climbing loop of the walking set. Mantle and Climb use different slices of it (measured).
Sounds.Mantle = def("SFX", 1.4, { pitch = { 0.95, 1.05 }, rollMin = 6, rollMax = 50,
	regions = slices(114640039515382, { { 0.588, 1.158, 1 }, { 3.575, 4.145, 1.12 }, { 4.183, 4.712, 1.12 } }) })
Sounds.Climb = def("SFX", 1.4, { pitch = { 0.92, 1.08 }, rollMin = 6, rollMax = 50,
	regions = slices(114640039515382, { { 0.012, 0.578, 1.35 }, { 1.196, 1.766, 1.12 }, { 1.783, 2.353, 1.26 },
		{ 2.391, 2.961, 0.89 }, { 2.977, 3.547, 1.26 } }) })
Sounds.Swim = def("SFX", 0.7, { pitch = { 0.95, 1.05 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9120589166) } }) -- "Water Splashing Swimming Stroke 2": own strokes, looped by the AudioController (PSE)
Sounds.SwimStroke = def("SFX", 0.6, { pitch = { 0.92, 1.04 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9119481690) } }) -- "Splash Slightly Boomy 2": another contender's stroke, 3D (PSE)
Sounds.WaterSplash = def("SFX", 0.95, { pitch = { 0.92, 1.08 }, rollMin = 8, rollMax = 100,
	ids = { rbx(9119481909), rbx(9119476512) } }) -- a body entering water (PSE, measured)
Sounds.Underwater = def("Ambience", 0.5, { looped = true, ids = { rbx(9112889917) } }) -- "Underwater Ambience 1": bed while the camera is under (PSE)
Sounds.BreathHeavy = def("SFX", 0.4, { looped = true, ids = { rbx(124832136911190) } }) -- effort, never distress (Creator Store upload, measured)
Sounds.Heartbeat = def("SFX", 0.22, { looped = true, ids = { rbx(9043365842) } }) -- (APM, measured)

-- Combat. Hits on a contender are dry: cloth and padding, no voice.
Sounds.Swing_Light = def("SFX", 1.2, { pitch = { 0.96, 1.06 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9116904947), rbx(9116904355), rbx(9116904676) } }) -- "Metal Tube Swishes" 16, 10, 12: thin metal cutting air (PSE)
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
	ids = { rbx(9114374276), rbx(9114373678) } }) -- "Fast Pass By Airy Whooshes" 11, 4 (PSE)
Sounds.ArrowWater = def("SFX", 0.5, { pitch = { 0.96, 1.08 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9125702803) } }) -- an arrow into water: a small plip (PSE). Needs ProjectileController to name it.
Sounds.Throw = def("SFX", 1.2, { pitch = { 0.92, 1.0 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9113318154), rbx(9113318407) } }) -- "Baseball Swish" 2, 5: an arm throw (PSE)
Sounds.Equip_Blade = def("SFX", 0.6, { pitch = { 0.96, 1.04 },
	ids = { rbx(9116194425), rbx(9116190816), rbx(9116190959) } }) -- a knife leaving leather (PSE)
Sounds.Equip_Bow = def("SFX", 0.7, { pitch = { 0.96, 1.04 }, ids = { rbx(9120880314) } }) -- a hand taking hold of wood (PSE)
Sounds.Equip_Generic = def("SFX", 0.6, { pitch = { 0.95, 1.05 }, ids = { rbx(9116252627) } }) -- "Leather Bible 26": a leather grab (PSE)
-- (HitMarker keeps its 1.34-1.42 pitch: CombatController plays the headshot at 1.62, a little brighter than this.)
Sounds.HitMarker = def("UI", 0.7, { pitch = { 1.34, 1.42 }, maxLifetime = 3, ids = { rbx(9120917813) } }) -- a small dry wooden tick (PSE)
Sounds.HitMarkerKill = def("UI", 0.7, { pitch = { 0.96, 1.0 }, maxLifetime = 4, ids = { rbx(9119975775) } }) -- one low wooden knock (PSE)
Sounds.Hurt = def("SFX", 0.9, { pitch = { 0.92, 1.0 }, maxLifetime = 4, ids = { rbx(9119313205) } }) -- "Snowballs Hit Leather Coat Back 4": close muffled thump (PSE)
-- a defeated body reaching the ground, played by the AudioController at the body (no voice). Was the unused "Death".
Sounds.BodyFall = def("SFX", 0.7, { pitch = { 0.94, 1.0 }, rollMin = 8, rollMax = 90, maxLifetime = 5,
	ids = { rbx(9113469691), rbx(9113469779) } }) -- "Body Fall Dirt" 1, 3 (PSE)

-- Items
Sounds.CrateOpen = def("SFX", 0.8, { pitch = { 0.95, 1.05 }, rollMin = 8, rollMax = 90, maxLifetime = 4,
	ids = { rbx(9120873789) } }) -- "Wooden Chest Open Close Cedar Box 9": latch and lid (PSE)
Sounds.CrateLand = def("SFX", 1.0, { pitch = { 0.92, 1.02 }, rollMin = 10, rollMax = 140, maxLifetime = 4,
	ids = { rbx(9120871244) } }) -- "Wood Drop Wooden Log Fall 2": heavy wood onto dirt (PSE). Needs LootService to name it.
Sounds.DummyBreak = def("SFX", 0.9, { pitch = { 0.94, 1.04 }, rollMin = 8, rollMax = 90, maxLifetime = 4,
	ids = { rbx(9125992732) } }) -- wood splitting (PSE). Needs CombatService to name it.
Sounds.PickUp = def("SFX", 0.6, { pitch = { 0.96, 1.06 }, ids = { rbx(9116251623) } }) -- "Leather Bible 11": a hand closing on the thing (PSE)
Sounds.Drop = def("SFX", 0.8, { pitch = { 0.92, 1.05 }, ids = { rbx(9114517148) } }) -- "Foliage Drop 5": a small thing landing in grass (PSE)
Sounds.Eat = def("SFX", 0.7, { pitch = { 0.96, 1.04 }, maxLifetime = 4, ids = { rbx(9113138343) } }) -- "Apple Chew 1": a bite and a chew (PSE)
Sounds.Drink = def("SFX", 1.0, { pitch = { 0.95, 1.05 }, ids = { rbx(9114171960), rbx(9114172109) } }) -- two or three swallows (PSE, measured)
Sounds.CanteenFill = def("SFX", 0.6, { pitch = { 0.96, 1.04 }, rollMin = 6, rollMax = 60, maxLifetime = 4,
	ids = { rbx(9125506910) } }) -- water glugging into a bottle (PSE). Needs the inventory code to name it.
Sounds.Bandage = def("SFX", 0.65, { pitch = { 0.95, 1.05 }, ids = { rbx(9113827551), rbx(9113834008) } }) -- linen tearing (PSE)
Sounds.ArmorOn = def("SFX", 1.0, { pitch = { 0.95, 1.05 }, maxLifetime = 4, ids = { rbx(9113241604) } }) -- "Backpack Movement 2": canvas, straps (PSE)
Sounds.InventoryFull = def("UI", 0.9, { pitch = { 0.96, 1.0 }, maxLifetime = 3, ids = { rbx(9125654847) } }) -- a dull knock on wood: "no" (PSE)

-- Round
Sounds.Cannon = def("SFX", 2.5, { pitch = { 0.8, 0.82 }, maxLifetime = 15, ids = { rbx(9114363528) } }) -- the only sound of a defeat (PSE, measured)
Sounds.CountdownTick = def("UI", 0.8, { pitch = { 0.98, 1.0 }, maxLifetime = 3, ids = { rbx(9120896809) } }) -- "Wood Impact 1": one hollow knock a number (PSE)
Sounds.StartHorn = def("SFX", 1.0, { pitch = { 0.98, 1.0 }, maxLifetime = 15, ids = { rbx(9114820717) } }) -- "Horn Blow 4": a ram's horn (PSE)
Sounds.Victory = def("Music", 0.56, { maxLifetime = 20, ids = { rbx(83315768373322) } }) -- (APM, measured)
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
Sounds.Launch_Seal = def("SFX", 0.7, { maxLifetime = 4, ids = { rbx(9113059926) } }) -- "Air Chuff 4": the case sealing (PSE)
Sounds.Launch_Rise = def("SFX", 0.6, { looped = true, ids = { rbx(9118747853) } }) -- "Interior Wind Turbo Shaft 5": shaft air on the way up (PSE)
Sounds.Launch_Arrive = def("SFX", 0.6, { maxLifetime = 4, ids = { rbx(9125807267) } }) -- "Rising Whoosh Hissing Suck Burst": the shaft noise cutting off (PSE)
Sounds.Launch_Glare = def("SFX", 0.25, { maxLifetime = 9, ids = { rbx(9114630613) } }) -- "Gong No Hit 2": a soft ring under the sun glare (PSE)

-- UI: physical, soft and short (a switch, wood, paper), never a bleep
Sounds.UIClick = def("UI", 0.8, { pitch = { 0.98, 1.04 }, maxLifetime = 2, ids = { rbx(9119717523) } }) -- "Switch Click Toggle Button 2" (PSE)
Sounds.UIHover = def("UI", 0.3, { pitch = { 1.0, 1.06 }, maxLifetime = 2, ids = { rbx(9119717950) } }) -- "Switch Clicks Metallic Dull Pops 7", barely there (PSE)
Sounds.Notify = def("UI", 0.5, { pitch = { 0.98, 1.02 }, maxLifetime = 3, ids = { rbx(9120917609) } }) -- one soft wooden note (PSE)
Sounds.UIOpen = def("UI", 0.6, { pitch = { 0.98, 1.04 }, maxLifetime = 3, ids = { rbx(9118835802) } }) -- a leather-bound book opening (PSE). For panels; nothing plays it yet.
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

-- Music (looped; the AudioController picks the track by game state and keeps it subtle)
Sounds.Music_Lobby = def("Music", 0.63, { looped = true, ids = { rbx(1842361805) } })
Sounds.Music_Tension = def("Music", 0.4, { looped = true, ids = { rbx(1843822275), rbx(1843866957) } })
Sounds.Music_Final = def("Music", 0.35, { looped = true, ids = { rbx(1837850904) } })

return Sounds
