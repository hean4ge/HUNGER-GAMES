--[[
	Sounds - every sound in the game, by key. Code plays them with Shared.Sfx, e.g. Sfx.play("Cannon").
	Keys are a contract between systems; the Audio system owns this file and fills in the ids.
	Entry fields:
	  ids      list of "rbxassetid://<id>" (one is picked at random). Empty = silent, which is safe.
	  volume   0..10. Levels were measured (RMS) and balanced against each other; quiet field
	           recordings (forest beds) need values above 1, which is intended.
	  pitch    { min, max } random playback speed
	  group    "SFX" | "Music" | "Ambience" | "UI"   (SoundGroups in SoundService)
	  looped   true for loops (the caller stops them)
	  rollMin / rollMax   3D distances in studs
	  maxLifetime   seconds before a one-shot is cleaned up (default 12)
	  regions  optional slices of a longer recording: { { id, from, to, gain } } (seconds).
	           The AudioController plays them with Sound.PlaybackRegion. Region-only entries
	           (footsteps, Jump, Mantle, Climb) have empty ids, so Sfx.play on them is a silent no-op.
	Sources: Pro Sound Effects and APM Music libraries on Roblox (licensed), Material Design UI sounds
	(Google, CC-BY 4.0), the "CharacterAudio" walking/climbing/swimming set, and a few Creator Store uploads.
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

local function concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, item in ipairs(list) do
			table.insert(out, item)
		end
	end
	return out
end

-- Movement. Footsteps: 8 slices per material from one consistent walking set, gain-normalised per step.
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
Sounds.Footstep_Water = def("SFX", 2.1, { pitch = { 1.18, 1.32 }, rollMin = 6, rollMax = 80,
	regions = concat(slices(9114081313, { { 0, 0.418, 0.84 }, { 0.428, 0.868, 1.06 } }),
		slices(9114081686, { { 0, 0.431, 0.94 }, { 0.46, 0.9, 1.19 } })) })
Sounds.Jump = def("SFX", 1.1, { pitch = { 0.95, 1.08 }, rollMin = 6, rollMax = 50,
	regions = slices(9113820748, { { 0.268, 0.781, 1 }, { 0.791, 1.311, 1.4 } }) })
Sounds.Land_Soft = def("SFX", 2.6, { pitch = { 0.9, 1.05 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9118686853), rbx(9118685780) } })
Sounds.Land_Hard = def("SFX", 0.65, { pitch = { 0.9, 1.02 }, rollMin = 8, rollMax = 100,
	ids = { rbx(9113477342), rbx(9113476851) } })
Sounds.Slide = def("SFX", 1.05, { pitch = { 0.95, 1.06 }, rollMin = 6, rollMax = 70, maxLifetime = 4,
	ids = { rbx(9117935335) }, regions = slices(9117935335, { { 0.225, 1.133, 1 }, { 1.143, 2.133, 0.95 } }) })
Sounds.Mantle = def("SFX", 1.4, { pitch = { 0.95, 1.05 }, rollMin = 6, rollMax = 50,
	regions = slices(114640039515382, { { 0.588, 1.158, 1 }, { 3.575, 4.145, 1.12 }, { 4.183, 4.712, 1.12 } }) })
Sounds.Climb = def("SFX", 1.4, { pitch = { 0.92, 1.08 }, rollMin = 6, rollMax = 50,
	regions = slices(114640039515382, { { 0.012, 0.578, 1.35 }, { 0.588, 1.158, 0.75 }, { 1.196, 1.766, 1.12 }, { 1.783, 2.353, 1.26 },
		{ 2.391, 2.961, 0.89 }, { 2.977, 3.547, 1.26 }, { 3.575, 4.145, 0.79 }, { 4.183, 4.712, 0.79 } }) })
Sounds.Swim = def("SFX", 1.0, { pitch = { 0.95, 1.05 }, rollMin = 6, rollMax = 70, ids = { rbx(134896833025703) } })
Sounds.WaterSplash = def("SFX", 0.95, { pitch = { 0.92, 1.08 }, rollMin = 8, rollMax = 100,
	ids = { rbx(9119481909), rbx(9119476512) } })
Sounds.BreathHeavy = def("SFX", 0.4, { looped = true, ids = { rbx(124832136911190) } })
Sounds.Heartbeat = def("SFX", 0.22, { looped = true, ids = { rbx(9043365842) } })

-- Combat
Sounds.Swing_Light = def("SFX", 1.5, { pitch = { 1.02, 1.16 }, rollMin = 6, rollMax = 60,
	ids = { rbx(9119742027), rbx(9119738368), rbx(9119741887), rbx(9119739200) } })
Sounds.Swing_Heavy = def("SFX", 1.3, { pitch = { 0.78, 0.9 }, rollMin = 6, rollMax = 70,
	ids = { rbx(9119740811), rbx(9119739481), rbx(9119742184) } })
Sounds.Hit_Flesh = def("SFX", 0.85, { pitch = { 0.84, 1.0 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9113574268), rbx(9113568548) } })
Sounds.Hit_Wood = def("SFX", 1.0, { pitch = { 0.92, 1.08 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9120807255), rbx(9120809771) } })
Sounds.Hit_Stone = def("SFX", 0.8, { pitch = { 0.9, 1.1 }, rollMin = 8, rollMax = 90,
	ids = { rbx(9118628076), rbx(9118629108) } })
Sounds.Hit_Metal = def("SFX", 0.9, { pitch = { 0.92, 1.08 }, rollMin = 8, rollMax = 100,
	ids = { rbx(9116689192), rbx(9116688613), rbx(9119742750) } })
Sounds.BowDraw = def("SFX", 0.7, { pitch = { 0.97, 1.03 }, rollMin = 6, rollMax = 50, ids = { rbx(109171490051533) } })
Sounds.BowRelease = def("SFX", 0.5, { pitch = { 0.95, 1.05 }, rollMin = 8, rollMax = 120, ids = { rbx(609348009) } })
Sounds.ArrowImpact = def("SFX", 0.8, { pitch = { 0.9, 1.1 }, rollMin = 8, rollMax = 90,
	ids = { rbx(129408941397748), rbx(9120807255) } })
Sounds.ArrowWhiz = def("SFX", 0.8, { pitch = { 0.95, 1.15 }, rollMin = 4, rollMax = 40, ids = { rbx(9114156616) } })
Sounds.Throw = def("SFX", 1.5, { pitch = { 0.86, 0.96 }, rollMin = 6, rollMax = 60, ids = { rbx(9119738654), rbx(9119742292) } })
Sounds.Equip_Blade = def("SFX", 0.7, { pitch = { 0.95, 1.05 }, ids = { rbx(9119742750), rbx(9119744718), rbx(9119744642) } })
Sounds.Equip_Bow = def("SFX", 0.8, { pitch = { 0.95, 1.05 }, ids = { rbx(9120877442) } })
Sounds.Equip_Generic = def("SFX", 0.3, { pitch = { 0.92, 1.02 }, ids = { rbx(9117515557) } })
Sounds.HitMarker = def("UI", 1.3, { pitch = { 1.34, 1.42 }, ids = { rbx(9119744642), rbx(9119744718) } })
Sounds.HitMarkerKill = def("UI", 0.24, { pitch = { 1.7, 1.74 }, maxLifetime = 4, ids = { rbx(118897948050872) } })
Sounds.Hurt = def("SFX", 0.8, { pitch = { 0.72, 0.82 }, ids = { rbx(9113568548), rbx(9113574268) } })
Sounds.Death = def("SFX", 0.8, { pitch = { 0.92, 1.0 }, rollMin = 8, rollMax = 120, ids = { rbx(9113476851) } })

-- Items
Sounds.CrateOpen = def("SFX", 0.4, { pitch = { 0.95, 1.05 }, rollMin = 8, rollMax = 90, ids = { rbx(116841971399984) } })
Sounds.PickUp = def("SFX", 0.45, { pitch = { 1.12, 1.28 }, ids = { rbx(9117515557) } })
Sounds.Drop = def("SFX", 2.6, { pitch = { 0.9, 1.05 }, ids = { rbx(9118686853), rbx(9118685780) } })
Sounds.Eat = def("SFX", 0.8, { pitch = { 0.95, 1.05 }, ids = { rbx(96143714118880) } })
Sounds.Drink = def("SFX", 1.0, { pitch = { 0.95, 1.05 }, ids = { rbx(9114171960), rbx(9114172109) } })
Sounds.Bandage = def("SFX", 0.65, { pitch = { 0.95, 1.05 }, ids = { rbx(9113827551), rbx(9113836527) } })
Sounds.ArmorOn = def("SFX", 3.0, { pitch = { 0.95, 1.05 }, ids = { rbx(9113468529) } })
Sounds.InventoryFull = def("UI", 3.0, { pitch = { 0.62, 0.66 }, ids = { rbx(114030580225727) } })

-- Round
Sounds.Cannon = def("SFX", 2.5, { pitch = { 0.8, 0.82 }, maxLifetime = 15, ids = { rbx(9114363528) } })
Sounds.CountdownTick = def("UI", 0.6, { pitch = { 1.44, 1.46 }, ids = { rbx(9120807255) } })
Sounds.StartHorn = def("SFX", 1.1, { pitch = { 0.98, 1.0 }, maxLifetime = 15, ids = { rbx(5692517175) } })
Sounds.Victory = def("Music", 0.56, { maxLifetime = 20, ids = { rbx(83315768373322) } })
Sounds.BorderWarning = def("UI", 0.8, { pitch = { 0.84, 0.86 }, maxLifetime = 8, ids = { rbx(9119561244) } })
Sounds.BorderHum = def("SFX", 0.8, { looped = true, rollMin = 20, rollMax = 200, ids = { rbx(9112795463) } })
Sounds.FeastBell = def("SFX", 0.63, { pitch = { 0.78, 0.8 }, maxLifetime = 15, ids = { rbx(118897948050872) } })
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
Sounds.PlateLock = def("SFX", 0.45, { rollMin = 14, rollMax = 150, maxLifetime = 4, ids = { rbx(9116903113) } }) -- hollow metal clunk (PSE)

-- UI
Sounds.UIClick = def("UI", 2.5, { pitch = { 1.0, 1.06 }, ids = { rbx(3623733749) } })
Sounds.UIHover = def("UI", 0.6, { pitch = { 1.3, 1.36 }, ids = { rbx(123087446204451) } })
Sounds.Notify = def("UI", 0.12, { pitch = { 2.08, 2.12 }, maxLifetime = 4, ids = { rbx(118897948050872) } })

-- Ambience beds (looped, 2D; mixed by the AudioController per biome and time of day)
Sounds.Amb_ForestDay = def("Ambience", 5.6, { looped = true, ids = { rbx(9112749254), rbx(9113444290) } })
Sounds.Amb_ForestNight = def("Ambience", 0.71, { looped = true, ids = { rbx(9112837706) } })
Sounds.Amb_Swamp = def("Ambience", 0.63, { looped = true, ids = { rbx(9112763270) } })
Sounds.Amb_Highlands = def("Ambience", 2.0, { looped = true, ids = { rbx(9112832288) } })
Sounds.Amb_Lake = def("Ambience", 0.71, { looped = true, ids = { rbx(9120570701) } })
Sounds.Amb_Lobby = def("Ambience", 1.8, { looped = true, ids = { rbx(9112832297) } })
Sounds.Amb_PineForest = def("Ambience", 1.4, { looped = true, ids = { rbx(9112761455) } })
Sounds.Amb_Wind = def("Ambience", 1.6, { looped = true, ids = { rbx(5799870105) } })
-- Emitters (looped, 3D on AmbientEmitter parts; SoundKey attribute)
Sounds.Emit_River = def("Ambience", 0.6, { looped = true, rollMin = 15, rollMax = 120, ids = { rbx(9119646409), rbx(9119646356) } })
Sounds.Emit_Waterfall = def("Ambience", 0.45, { looped = true, rollMin = 25, rollMax = 220, ids = { rbx(9116496316) } })
Sounds.Emit_Fire = def("Ambience", 0.8, { looped = true, rollMin = 6, rollMax = 50, ids = { rbx(150367086) } })
Sounds.Emit_Wind = def("Ambience", 0.25, { looped = true, rollMin = 30, rollMax = 200, ids = { rbx(9114625552) } })
Sounds.Emit_Frogs = def("Ambience", 1.4, { looped = true, rollMin = 15, rollMax = 120, ids = { rbx(9112762863) } })

-- Music (looped; the AudioController picks the track by game state and keeps it subtle)
Sounds.Music_Lobby = def("Music", 0.63, { looped = true, ids = { rbx(1842361805) } })
Sounds.Music_Tension = def("Music", 0.4, { looped = true, ids = { rbx(1843822275), rbx(1843866957) } })
Sounds.Music_Final = def("Music", 0.35, { looped = true, ids = { rbx(1837850904) } })

return Sounds
