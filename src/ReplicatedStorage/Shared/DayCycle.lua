--[[
	DayCycle - the arena's day/night clock, its lighting look, and the Roll Call show's timeline.
	Shared by:
	  * ArenaService (server): runs the schedule, publishes the clock time base, starts each dusk's Roll Call.
	  * ArenaController.Sky (client): sets Lighting.ClockTime and the whole look every frame (smooth, no stepping) and
	    adds wind gusts on top of the base wind.
	  * FallenRecapController / NotificationController (client): follow the Roll Call timeline and its day caption.
	  * ServerStorage.WorldGen.LightingRig (edit time): writes the look at Config.Round.LobbyClockTime.

	Clock values are "unwrapped" hours: 7.4 = 07:24 on day 1, 31.0 = 07:00 on day 2. Lighting.ClockTime = clock % 24.
	Engine facts, measured in this place (LightingStyle Realistic, GeographicLatitude 44) on 2026-11-11:
	  * the sun rises at 06:00 and sets at 18:00 whatever the latitude;
	  * only one directional light is active. The engine hands the sun over to the moon at 19.25 h and back at 4.75 h
	    (the sun 17.5 degrees below the horizon both ways). Between sunset and 19.25 (and between 4.75 and sunrise)
	    there is no direct light at all; at each switch the moonlight would pop on or off. lookAt() dips Brightness to
	    ~0 around each switch (Knobs.HandoffDusk / HandoffDawn) so the moon fades in after dusk and out before dawn.
	  * ColorShift_Top adds to the sun/moon light (white at noon is roughly +20 % on sunlit surfaces), so it is used as
	    a tint: faint by day, warm at golden hour, blue for moonlight.
	  * the sky light (EnvironmentDiffuseScale) collapses as the sun goes down: on the meadow the ground went from luma 30
	    at 17.0 to 4 at 18.0 and 3-4 at 18.75 / 19.25 / 4.75 with the old flat ambient, darker than under the moon (14-16
	    at 01:00). OutdoorAmbient does carry it (18.75: OutdoorAmbient 76 -> 124 -> 200 gave ground luma 3.7 -> 15 -> 47),
	    so lookAt() eases OutdoorAmbient / Ambient toward a cool twilight fill (Knobs.Twilight*) from late afternoon until
	    the moonlight has faded in, and from the moonlight fading out until the sun is up (twilightFill).

	KNOBS (tune freely)
	  Config.Round.DaySchedule   { { roundSeconds, clock }, ... } piecewise-linear schedule across the round
	  Config.Round.RollCallClockTime   hour of each dusk's Roll Call (19.45: just after the moon takes over)
	  DayCycle.Looks             lighting keyframes by hour of day (0..24), interpolated every frame: the set of the arena
                             this place holds, DayCycle.LookSets[Config.Map] ("GreenLand" = Map 1, "ClassicForest")
  DayCycle.Static            that arena's hour-independent look (water, grass, sun and moon size, far blur on or off):
                             written at edit time by ServerStorage.WorldGen.LightingRig
  DayCycle.Tiers             what each shader tier (Off / Phone / Mid / High) scales; DetailController picks the tier
	  DayCycle.Knobs             global multipliers (night ambient lift, mist, bloom, wind) and the hand-off dips
	  DayCycle.Recap             Roll Call show timings (seconds)

	API
	  DayCycle.clockAt(elapsed) -> clock                 elapsed = round-schedule seconds since the start horn
	  DayCycle.segmentAt(elapsed) -> (t0, c0, t1, c1, nextRate)   schedule segment around `elapsed` (rate = per second)
	  DayCycle.dayOf(clock) -> number                    1-based day of an unwrapped clock
	  DayCycle.rollCallClock(day) -> clock               when that day's Roll Call starts
	  DayCycle.encodeClock(c0, t0, rate, t1, nextRate, day) -> string     GameState "Clock" time base
	  DayCycle.decodeClock(text) -> base?                 { c0, t0, rate, t1, nextRate, day }
	  DayCycle.evalClock(base, serverNow) -> clock
	  DayCycle.lookAt(hour, out?) -> look                interpolated look table at an hour of the day
	  DayCycle.handoffFactor(hour) -> 0..1               the Brightness dip around the sun/moon switches
	  DayCycle.twilightFill(hour) -> 0..1                weight of the twilight fill (1 while there is no direct light)
	  DayCycle.applyTier(look, tier?, deviceTier?) -> look   scales a look in place for a shader tier (bloom, rays, haze, fill)
  DayCycle.applyLook(look, targets, cache?)           writes a look to Lighting / Atmosphere / effects / wind / clouds /
                                                      the water's reflectance and wave size (targets.terrain)
	  DayCycle.recapTimeline(count, mode?) -> timeline    the Roll Call show (see recapTimeline); mode "epilogue" = the
	                                                      short end-of-round show (PlayabilityPlan QW14)
	  DayCycle.recapCaption(day, count, mode?) -> (line1, line2) "DUSK · DAY ONE", "4 FELL TODAY" (the show opens and closes
	                                                      on it; the epilogue reads "DAY TWO")
]]
-- (works from a :Clone() too, which edit-time builders require to dodge Studio's module cache)
local SharedFolder = script.Parent or game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(SharedFolder:WaitForChild("Config"))

local DayCycle = {}

local RoundCfg = Config.Round

DayCycle.DEFAULT_SCHEDULE = {
	{ 0, 7.4 }, -- day 1: the plates rise into a low morning sun
	{ 270, 17.0 }, -- afternoon
	{ 330, 18.5 }, -- golden hour, sunset (18:00)
	{ 345, 19.45 }, -- blue hour; the moon takes over at 19.25; Roll Call 1 at 19.45
	{ 395, 20.45 }, -- the vigil: the clock slows while the fallen are shown
	{ 495, 28.45 }, -- night 1: moonlight
	{ 525, 29.6 }, -- pre-dawn: the moon fades before the 4.75 switch
	{ 555, 31.0 }, -- sunrise (30.0) and morning mist
	{ 800, 41.6 }, -- day 2: the Feast, the border closes
	{ 830, 42.6 }, -- golden hour 2, sunset
	{ 845, 43.45 }, -- blue hour 2; Roll Call 2
	{ 900, 44.55 }, -- the vigil, to the time limit
}

local function schedule()
	local s = RoundCfg.DaySchedule
	if type(s) == "table" and #s >= 2 then
		return s
	end
	return DayCycle.DEFAULT_SCHEDULE
end

-- Round-schedule seconds -> segment (t0, c0, t1, c1) and the rate of the segment after it (hours per second).
function DayCycle.segmentAt(elapsed: number): (number, number, number, number, number)
	local s = schedule()
	local n = #s
	if elapsed <= s[1][1] then
		local a, b = s[1], s[2]
		return a[1], a[2], b[1], b[2], 0
	end
	for i = 1, n - 1 do
		local a, b = s[i], s[i + 1]
		if elapsed < b[1] or i == n - 1 then
			local nextRate = 0
			local c = s[i + 2]
			if c then
				nextRate = (c[2] - b[2]) / math.max(1e-3, c[1] - b[1])
			else
				nextRate = (b[2] - a[2]) / math.max(1e-3, b[1] - a[1]) -- past the end: keep the last rate
			end
			return a[1], a[2], b[1], b[2], nextRate
		end
	end
	local a, b = s[n - 1], s[n]
	return a[1], a[2], b[1], b[2], 0
end

function DayCycle.clockAt(elapsed: number): number
	local t0, c0, t1, c1, nextRate = DayCycle.segmentAt(elapsed)
	if elapsed <= t0 then
		return c0
	end
	if elapsed <= t1 then
		return c0 + (c1 - c0) * (elapsed - t0) / math.max(1e-3, t1 - t0)
	end
	return c1 + (elapsed - t1) * nextRate
end

function DayCycle.dayOf(clock: number): number
	return math.floor(clock / 24) + 1
end

function DayCycle.rollCallClock(day: number): number
	return (day - 1) * 24 + (tonumber(RoundCfg.RollCallClockTime) or 19.45)
end

-- The GameState "Clock" attribute: one string, so the whole time base changes atomically.
-- clock = c0 + (now - t0) * rate until server time t1, then continues at nextRate.
function DayCycle.encodeClock(c0: number, t0: number, rate: number, t1: number, nextRate: number, day: number): string
	return string.format("%.6f;%.4f;%.9f;%.4f;%.9f;%d", c0, t0, rate, t1, nextRate, day)
end

function DayCycle.decodeClock(text: any)
	if type(text) ~= "string" then
		return nil
	end
	local parts = string.split(text, ";")
	if #parts < 6 then
		return nil
	end
	local base = {
		c0 = tonumber(parts[1]),
		t0 = tonumber(parts[2]),
		rate = tonumber(parts[3]),
		t1 = tonumber(parts[4]),
		nextRate = tonumber(parts[5]),
		day = tonumber(parts[6]),
	}
	for _, v in pairs(base) do
		if v ~= v then
			return nil
		end
	end
	if not (base.c0 and base.t0 and base.rate and base.t1 and base.nextRate and base.day) then
		return nil
	end
	return base
end

function DayCycle.evalClock(base, serverNow: number): number
	if serverNow <= base.t0 then
		return base.c0
	end
	if serverNow <= base.t1 then
		return base.c0 + (serverNow - base.t0) * base.rate
	end
	return base.c0 + (base.t1 - base.t0) * base.rate + (serverNow - base.t1) * base.nextRate
end

------------------------------------------------------------------------------------------------------------------------
-- The look (tuned for LightingStyle Realistic + PrioritizeLightingQuality)
------------------------------------------------------------------------------------------------------------------------

local rgb = Color3.fromRGB

-- Global multipliers and engine constants, applied on top of the keyframes.
DayCycle.Knobs = {
	NightAmbientLift = 1.0, -- > 1 brightens night ambient (playability), < 1 darker nights
	MistStrength = 1.0, -- marsh/lake mist emitter rate multiplier
	BloomScale = 1.0,
	SunRaysScale = 1.0,
	ExposureOffset = 0.0, -- added to every keyframe's exposure
	HazeScale = 1.0, -- multiplies every keyframe's AtmDensity (one dial for "how far can I see")
	WindScale = 1.0, -- multiplies the base wind (Looks WindX / WindZ, studs per second)
	GustStrength = 0.75, -- client gusts add up to this fraction of the base wind
	HandoffDusk = 19.25, -- measured: the engine switches the sun's light to the moon's
	HandoffDawn = 4.75, -- measured: the moon's back to the sun's
	HandoffFade = 0.35, -- hours the moonlight takes to fade in after the dusk switch (and out before the dawn one)
	HandoffGuard = 0.1, -- hours of dip on the sun's side of each switch (there is no direct light there anyway)
	HandoffDepth = 0.97, -- Brightness multiplier at the switch = 1 - depth
	-- the twilight fill (twilightFill): OutdoorAmbient / Ambient are eased toward these (never darker than the keyframe)
	-- while the engine gives no direct light, in step with the moonlight's fade in/out at the hand-offs
	-- (a sky-lit shade is blue-cyan: green above red. The old violet (132,136,184) under a warm grade read magenta.)
	TwilightOutdoor = rgb(124, 138, 166), -- same luma as the old fill: meadow ground luma ~19 at 19.25 with the moon off
	TwilightAmbient = rgb(58, 64, 84),
	TwilightEvening = { 16.9, 18.1 }, -- hours: the fill rises as the sky light falls (full from 18.1 to the dusk switch)
	TwilightMorning = { 5.9, 6.8 }, -- hours: the fill goes as the sun climbs (full from the dawn switch to 5.9)
}

--[[
	Keyframes by hour of the day (0..24, the list must start at 0 and end at 24 with the same look).
	Brightness       Lighting.Brightness (sun, or moon at night)
	Exposure         Lighting.ExposureCompensation
	Ambient/Outdoor  Lighting.Ambient / OutdoorAmbient (flat fill indoors / outdoors; kept low: the sky light fills)
	ShiftTop         Lighting.ColorShift_Top (tint of sun-/moon-lit surfaces); ShiftBottom = ColorShift_Bottom
	EnvDiffuse/EnvSpecular   Lighting.EnvironmentDiffuseScale / EnvironmentSpecularScale (sky light, reflections)
	Softness         Lighting.ShadowSoftness (Realistic only)
	Atm*             Atmosphere Density / Offset / Color / Decay / Glare / Haze
	Grade*           ColorCorrection "ArenaGrade" Brightness / Contrast / Saturation / TintColor
	Bloom*           Bloom Intensity / Size / Threshold;  Rays* SunRays Intensity / Spread
	Cloud*           Terrain.Clouds Cover / Density / Color
	DofFar           DepthOfField FarIntensity (low at night so the Roll Call stays sharp)
	WindX/WindZ      Workspace.GlobalWind base (studs/s; grass, clouds, particles); the client adds gusts
	Mist             0..1 low mist over the marsh and the lake (client emitters)
	Night            0..1 how "night" this hour is (night ambient lift, effects that care)
	Stars            Sky.StarCount
	WaterReflect     Terrain.WaterReflectance (calmer and more mirror-like at low sun)
	WaterWave        Terrain.WaterWaveSize (wind-driven by day, glassy at dawn)
	InteriorLight    multiplies the brightness of the arena's one interior lamp (the horn's soft fill light,
	                 targets.interiorLight, attribute BaseBrightness): 1 by day, lower at night, because the night's
	                 exposure would otherwise make the room brighter than it is by day
]]
local NIGHT = {
	Brightness = 2.8, -- moonlight (the engine's moon is far weaker than the sun at the same value; faded in and out
	-- around the hand-offs). Tuned in this place: 1.4 + exposure 0.45 left the ground unreadable away from the moon.
	Exposure = 0.65,
	Ambient = rgb(26, 30, 42),
	Outdoor = rgb(60, 70, 100),
	ShiftTop = rgb(70, 95, 150),
	ShiftBottom = rgb(0, 0, 0),
	EnvDiffuse = 0.8,
	EnvSpecular = 0.8,
	Softness = 0.35,
	AtmDensity = 0.34,
	AtmOffset = 0.2,
	-- a thin, dark night haze: the peaks stand as moonlit silhouettes, never glowing brighter than the ground before them
	AtmColor = rgb(58, 68, 96),
	AtmDecay = rgb(26, 32, 52),
	AtmGlare = 0,
	AtmHaze = 1.1,
	GradeBrightness = 0,
	GradeContrast = 0.12,
	GradeSaturation = -0.28,
	GradeTint = rgb(205, 218, 255),
	BloomIntensity = 0.7,
	BloomSize = 30,
	BloomThreshold = 1.3,
	RaysIntensity = 0,
	RaysSpread = 0.5,
	CloudCover = 0.4,
	CloudDensity = 0.35,
	CloudColor = rgb(170, 180, 205),
	DofFar = 0.02,
	WindX = 3,
	WindZ = 1.5,
	Mist = 1,
	Night = 1,
	Stars = 4500,
}

local DAY = {
	Brightness = 2.6,
	Exposure = 0,
	Ambient = rgb(40, 42, 48),
	Outdoor = rgb(84, 90, 102),
	ShiftTop = rgb(40, 34, 24),
	ShiftBottom = rgb(0, 0, 0),
	EnvDiffuse = 1,
	EnvSpecular = 1,
	Softness = 0.15,
	AtmDensity = 0.28,
	AtmOffset = 0.25,
	AtmColor = rgb(200, 210, 222),
	AtmDecay = rgb(110, 124, 144),
	AtmGlare = 0.3,
	AtmHaze = 1.2,
	GradeBrightness = 0,
	GradeContrast = 0.06,
	GradeSaturation = -0.04,
	GradeTint = rgb(255, 250, 244),
	BloomIntensity = 0.4,
	BloomSize = 26,
	BloomThreshold = 1.8,
	RaysIntensity = 0.04,
	RaysSpread = 0.45,
	CloudCover = 0.5,
	CloudDensity = 0.4,
	CloudColor = rgb(252, 252, 255),
	DofFar = 0.05,
	WindX = 6,
	WindZ = 2.5,
	Mist = 0,
	Night = 0,
	Stars = 4500,
}

local function with(base, changes)
	local t = table.clone(base)
	for k, v in pairs(changes) do
		t[k] = v
	end
	return t
end

-- The classic forest arena's set (vaulted with it: ServerStorage.Vault_ClassicForest). A 640-stud valley.
local CLASSIC = {
	with(NIGHT, { hour = 0 }),
	with(NIGHT, { hour = 4.3 }),
	-- pre-dawn blue hour: the moon has faded (switch at 4.75), mist on the water, still air
	with(NIGHT, {
		hour = 5.3,
		Exposure = 0.55, -- no direct light between the 4.75 switch and sunrise: exposure carries it
		Ambient = rgb(34, 36, 50),
		Outdoor = rgb(74, 78, 106),
		ShiftTop = rgb(160, 150, 200),
		EnvDiffuse = 0.85,
		EnvSpecular = 0.85,
		AtmDensity = 0.42,
		AtmOffset = 0.06,
		AtmColor = rgb(96, 98, 128), -- the peaks stay darker than the brightening sky (5.3: sky ~52, peaks ~35)
		AtmDecay = rgb(70, 64, 96),
		AtmGlare = 0.3,
		AtmHaze = 1.9,
		GradeContrast = 0.1,
		GradeSaturation = -0.16,
		GradeTint = rgb(226, 222, 255),
		BloomIntensity = 0.6,
		BloomSize = 34,
		BloomThreshold = 1.4,
		CloudCover = 0.6,
		CloudDensity = 0.3,
		CloudColor = rgb(196, 194, 214),
		DofFar = 0.06,
		WindX = 2,
		WindZ = 1,
		Night = 0.75,
	}),
	-- sunrise: low warm light through the mist
	with(DAY, {
		hour = 6.15,
		Brightness = 1.6,
		Exposure = 0.15,
		Ambient = rgb(40, 40, 48),
		Outdoor = rgb(86, 90, 108),
		ShiftTop = rgb(180, 120, 80),
		EnvSpecular = 0.9,
		Softness = 0.35,
		AtmDensity = 0.44,
		AtmOffset = 0.06,
		AtmColor = rgb(220, 206, 200),
		AtmDecay = rgb(150, 140, 156),
		AtmGlare = 0.9,
		AtmHaze = 2.2,
		GradeBrightness = 0.01,
		GradeContrast = 0.05,
		GradeSaturation = -0.06,
		GradeTint = rgb(255, 244, 236),
		BloomIntensity = 0.5,
		BloomSize = 40,
		BloomThreshold = 1.45,
		RaysIntensity = 0.12,
		RaysSpread = 0.75,
		CloudCover = 0.65,
		CloudDensity = 0.3,
		CloudColor = rgb(255, 246, 240),
		DofFar = 0.1,
		WindX = 2,
		WindZ = 1,
		Mist = 1,
		Night = 0.2,
	}),
	-- the round opens (7.4): a low east-south-east sun just clear of the peaks, the mist lifting, long shadows
	with(DAY, {
		hour = 7.4,
		Brightness = 2.4,
		Exposure = 0.08,
		Ambient = rgb(42, 40, 46),
		Outdoor = rgb(88, 88, 104),
		ShiftTop = rgb(175, 122, 72),
		Softness = 0.28,
		AtmDensity = 0.35,
		AtmOffset = 0.14,
		AtmColor = rgb(226, 202, 180),
		AtmDecay = rgb(150, 126, 124),
		AtmGlare = 0.85,
		AtmHaze = 1.9,
		GradeBrightness = 0.01,
		GradeContrast = 0.06,
		GradeSaturation = -0.04,
		GradeTint = rgb(255, 244, 232),
		BloomIntensity = 0.45,
		BloomSize = 34,
		BloomThreshold = 1.55,
		RaysIntensity = 0.14,
		RaysSpread = 0.7,
		CloudCover = 0.6,
		CloudDensity = 0.35,
		CloudColor = rgb(255, 246, 240),
		DofFar = 0.07,
		WindX = 3,
		WindZ = 1.5,
		Mist = 0.55,
	}),
	-- mid-morning: the mist has burnt off
	with(DAY, {
		hour = 9.2,
		ShiftTop = rgb(52, 42, 28),
		AtmDensity = 0.3,
		AtmOffset = 0.22,
		AtmColor = rgb(206, 210, 218),
		AtmGlare = 0.35,
		AtmHaze = 1.3,
		RaysIntensity = 0.06,
	}),
	with(DAY, { hour = 13.0 }),
	-- afternoon
	with(DAY, {
		hour = 15.0,
		ShiftTop = rgb(60, 46, 30),
		AtmColor = rgb(212, 208, 204),
		AtmGlare = 0.4,
		AtmHaze = 1.3,
		GradeTint = rgb(255, 247, 238),
		RaysIntensity = 0.06,
	}),
	-- golden hour on the valley floor (the western peaks put the floor in shade from about 16.8; after that the
	-- warm light stays on the slopes and the sky: alpenglow)
	with(DAY, {
		hour = 16.3,
		Brightness = 2.3,
		Exposure = 0.1,
		Ambient = rgb(40, 36, 40),
		Outdoor = rgb(88, 82, 102),
		ShiftTop = rgb(210, 128, 64),
		Softness = 0.25,
		AtmDensity = 0.34,
		AtmOffset = 0.12,
		AtmColor = rgb(236, 188, 148),
		AtmDecay = rgb(120, 96, 120),
		AtmGlare = 0.9,
		AtmHaze = 1.9,
		GradeBrightness = 0.01,
		GradeContrast = 0.1,
		GradeSaturation = 0.04,
		GradeTint = rgb(255, 236, 214),
		BloomIntensity = 0.5,
		BloomSize = 30,
		BloomThreshold = 1.5,
		RaysIntensity = 0.1,
		RaysSpread = 0.6,
		CloudCover = 0.55,
		CloudDensity = 0.45,
		CloudColor = rgb(255, 240, 228),
		WindX = 4,
		WindZ = 2,
	}),
	-- sunset (18:00)
	with(DAY, {
		hour = 18.0,
		Brightness = 1.7,
		Exposure = 0.25,
		Ambient = rgb(38, 34, 42),
		Outdoor = rgb(82, 74, 98),
		ShiftTop = rgb(220, 112, 62),
		Softness = 0.28,
		AtmDensity = 0.37,
		AtmOffset = 0.12,
		AtmColor = rgb(226, 152, 126),
		AtmDecay = rgb(130, 82, 98),
		AtmGlare = 1.0,
		AtmHaze = 2.3, -- the afterglow: at 18.2 the sky (luma ~90) stays brighter than the peaks (60-80); 1.9 left it ~24
		GradeBrightness = 0.01,
		GradeContrast = 0.11,
		GradeSaturation = 0,
		GradeTint = rgb(255, 228, 214),
		BloomIntensity = 0.55,
		BloomSize = 30,
		BloomThreshold = 1.45,
		RaysIntensity = 0.14,
		RaysSpread = 0.65,
		CloudCover = 0.55,
		CloudDensity = 0.45,
		CloudColor = rgb(255, 214, 196),
		DofFar = 0.04,
		WindX = 3.5,
		WindZ = 1.5,
		Mist = 0.15,
		Night = 0.1,
	}),
	-- blue hour: no direct light until the moon takes over (19.25)
	with(NIGHT, {
		hour = 18.75,
		Brightness = 2.0,
		Exposure = 0.55,
		Ambient = rgb(34, 34, 46),
		Outdoor = rgb(76, 78, 108),
		ShiftTop = rgb(120, 110, 170),
		Softness = 0.3,
		-- the haze darker than the sky's glow, so the peaks stand as silhouettes rather than glowing brighter than it
		AtmDensity = 0.4,
		AtmOffset = 0.18,
		AtmColor = rgb(50, 54, 86), -- dark enough that the fill-lit peaks sink to the foreground's level (~18)
		AtmDecay = rgb(34, 30, 58),
		AtmGlare = 0.12,
		AtmHaze = 1.9,
		GradeContrast = 0.12,
		GradeSaturation = -0.12,
		GradeTint = rgb(222, 222, 255),
		BloomThreshold = 1.4,
		CloudCover = 0.5,
		CloudDensity = 0.4,
		CloudColor = rgb(200, 196, 220),
		DofFar = 0.03,
		Mist = 0.6,
		Night = 0.6,
	}),
	with(NIGHT, { hour = 19.7 }),
	with(NIGHT, { hour = 24 }),
}

--[[
	Map 1, the Green Land: an alpine valley 1,800 studs across under mountains 2,600 to 7,600 studs away. The look is
	"Roblox with good graphics": the same world, lit to feel real. Bright, clean daylight; a warm sun and a cool
	sky-lit shade; crisp shadows; clear air whose haze only starts to show on the far range; nothing glowing.
	Against the classic set:
	  * the air is about two thirds as thick by the number (0.18 by day against 0.28) and far clearer to the eye:
	    the classic density, tuned for 600-stud views, laid a blue veil over the whole valley and greyed the
	    mountains out. Seen in Studio from above the ring: 0.10 shows no air at all, 0.20 puts the far range in a
	    pale blue distance while the meadow keeps its green;
	  * every fill (Ambient / Outdoor) has green above red, so shade and dusk are cool, never magenta;
	  * sunset haze is pale peach, not red-brown, and the grade's tint stays near neutral once the floor is in shade;
	  * no far blur (the mountains are the view); bloom only reaches the sun, the sky's glare and glitter on water;
	  * two more tracks: the water's reflectance and wave size.
]]
local NIGHT_G = {
	Brightness = 2.8, -- moonlight, as tuned in this place for a readable ground
	Exposure = 0.65,
	-- The fill where the sky is blocked. Measured in Studio at 21:00: the night's ground light is the sky light, and
	-- under the North Wood's canopy none of it arrives, so with the classic (26,30,42) the forest floor was luma 0.
	-- (64,72,98) brings it to about 5 and the open meadow from 18 to about 24. A wood at night stays dark.
	Ambient = rgb(64, 72, 98),
	Outdoor = rgb(60, 70, 100),
	ShiftTop = rgb(70, 95, 150),
	ShiftBottom = rgb(0, 0, 0),
	EnvDiffuse = 0.8,
	EnvSpecular = 0.8,
	Softness = 0.35,
	AtmDensity = 0.2,
	AtmOffset = 0.2,
	AtmColor = rgb(58, 68, 96),
	AtmDecay = rgb(26, 32, 52),
	AtmGlare = 0,
	AtmHaze = 1.1,
	GradeBrightness = 0,
	GradeContrast = 0.08, -- 0.12 crushed the darkest tones to black
	GradeSaturation = -0.25,
	GradeTint = rgb(208, 220, 255),
	BloomIntensity = 0.4,
	BloomSize = 30,
	BloomThreshold = 1.4,
	RaysIntensity = 0,
	RaysSpread = 0.5,
	CloudCover = 0.4,
	CloudDensity = 0.35,
	CloudColor = rgb(170, 180, 205),
	DofFar = 0,
	WindX = 3,
	WindZ = 1.5,
	Mist = 0.8,
	Night = 1,
	Stars = 4500,
	WaterReflect = 0.6, -- the moon's path on the lake
	WaterWave = 0.08,
	InteriorLight = 0.45, -- the horn at night: a dim, warm room, not a lantern
}

local DAY_G = {
	Brightness = 2.8,
	Exposure = -0.08,
	Ambient = rgb(36, 40, 48),
	Outdoor = rgb(76, 86, 104), -- a cool, sky-blue shade
	ShiftTop = rgb(52, 42, 26), -- a faint warm key
	ShiftBottom = rgb(0, 0, 0),
	EnvDiffuse = 1,
	EnvSpecular = 1,
	Softness = 0.12, -- crisp midday shadows
	AtmDensity = 0.18,
	AtmOffset = 0.3,
	AtmColor = rgb(212, 220, 226),
	AtmDecay = rgb(124, 138, 156),
	AtmGlare = 0.3,
	AtmHaze = 1.6,
	GradeBrightness = 0,
	GradeContrast = 0.08,
	GradeSaturation = 0.05,
	GradeTint = rgb(255, 251, 246),
	BloomIntensity = 0.3,
	BloomSize = 30,
	BloomThreshold = 1.9, -- the sun, the sky's glare, glitter on the lake; never the pale sails or the limestone
	RaysIntensity = 0.05,
	RaysSpread = 0.55,
	CloudCover = 0.56,
	CloudDensity = 0.55,
	CloudColor = rgb(250, 250, 252),
	DofFar = 0,
	WindX = 7,
	WindZ = 3,
	Mist = 0,
	Night = 0,
	Stars = 4500,
	WaterReflect = 0.4,
	WaterWave = 0.15,
	InteriorLight = 1,
}

local GREEN_LAND = {
	with(NIGHT_G, { hour = 0 }),
	with(NIGHT_G, { hour = 4.3 }),
	-- pre-dawn: no direct light (the moon's hand-off is at 4.75), mist on the lake, still air
	with(NIGHT_G, {
		hour = 5.3,
		Exposure = 0.55,
		Ambient = rgb(56, 62, 84),
		Outdoor = rgb(70, 78, 106),
		ShiftTop = rgb(150, 150, 200),
		EnvDiffuse = 0.85,
		EnvSpecular = 0.85,
		AtmDensity = 0.28,
		AtmOffset = 0.06,
		AtmColor = rgb(96, 100, 128),
		AtmDecay = rgb(68, 68, 96),
		AtmGlare = 0.3,
		AtmHaze = 1.9,
		GradeContrast = 0.1,
		GradeSaturation = -0.14,
		GradeTint = rgb(228, 228, 255),
		BloomIntensity = 0.45,
		BloomSize = 34,
		BloomThreshold = 1.45,
		CloudCover = 0.6,
		CloudDensity = 0.3,
		CloudColor = rgb(196, 196, 214),
		WindX = 2,
		WindZ = 1,
		Mist = 1,
		Night = 0.75,
		WaterReflect = 0.7,
		WaterWave = 0.05,
		InteriorLight = 0.6,
	}),
	-- sunrise: low warm light through the mist
	with(DAY_G, {
		hour = 6.15,
		Brightness = 1.7,
		Exposure = 0.15,
		Ambient = rgb(38, 40, 48),
		Outdoor = rgb(82, 90, 108),
		ShiftTop = rgb(184, 124, 80),
		EnvSpecular = 0.9,
		Softness = 0.35,
		AtmDensity = 0.28,
		AtmOffset = 0.06,
		AtmColor = rgb(226, 212, 202),
		AtmDecay = rgb(156, 150, 164),
		AtmGlare = 0.8,
		AtmHaze = 2.2,
		GradeBrightness = 0.01,
		GradeContrast = 0.05,
		GradeSaturation = -0.03,
		GradeTint = rgb(255, 246, 238),
		BloomIntensity = 0.45,
		BloomSize = 40,
		BloomThreshold = 1.5,
		RaysIntensity = 0.12,
		RaysSpread = 0.75,
		CloudCover = 0.62,
		CloudDensity = 0.35,
		CloudColor = rgb(255, 244, 236),
		WindX = 2,
		WindZ = 1,
		Mist = 1,
		Night = 0.2,
		WaterReflect = 0.7,
		WaterWave = 0.05,
	}),
	-- 7.4, the arrival: a low sun in the east-south-east, long shadows, the last mist on the water
	with(DAY_G, {
		hour = 7.4,
		Brightness = 2.5,
		Exposure = 0.05,
		Ambient = rgb(38, 40, 48),
		Outdoor = rgb(84, 92, 110), -- Roblox grass has no back-light: the fill keeps it from going dark facing the sun
		ShiftTop = rgb(186, 128, 74),
		Softness = 0.3,
		AtmDensity = 0.22,
		AtmOffset = 0.14,
		AtmColor = rgb(230, 214, 196),
		AtmDecay = rgb(152, 142, 148),
		AtmGlare = 0.7,
		AtmHaze = 1.8,
		GradeBrightness = 0.01,
		GradeContrast = 0.07,
		GradeSaturation = 0.02,
		GradeTint = rgb(255, 246, 236),
		BloomIntensity = 0.4,
		BloomSize = 36,
		BloomThreshold = 1.6,
		RaysIntensity = 0.14,
		RaysSpread = 0.7,
		CloudCover = 0.6,
		CloudDensity = 0.45,
		CloudColor = rgb(255, 246, 238),
		WindX = 3,
		WindZ = 1.5,
		Mist = 0.6,
		WaterReflect = 0.6,
		WaterWave = 0.07,
	}),
	-- mid-morning: the mist has burnt off, the air has cleared
	with(DAY_G, {
		hour = 9.5,
		Brightness = 2.75,
		Exposure = -0.06,
		ShiftTop = rgb(84, 62, 36),
		Softness = 0.18,
		AtmDensity = 0.19,
		AtmOffset = 0.22,
		AtmGlare = 0.35,
		AtmHaze = 1.5,
		RaysIntensity = 0.07,
		RaysSpread = 0.6,
		WaterWave = 0.13,
	}),
	-- midday: bright, clean alpine daylight. The sun stands in the south, over the lake and the peak.
	with(DAY_G, { hour = 12.5 }),
	-- afternoon
	with(DAY_G, {
		hour = 15.0,
		Brightness = 2.75,
		Exposure = -0.06,
		ShiftTop = rgb(76, 56, 32),
		Softness = 0.18,
		AtmColor = rgb(218, 220, 220),
		AtmGlare = 0.35,
		GradeTint = rgb(255, 249, 242),
		RaysIntensity = 0.07,
		RaysSpread = 0.6,
	}),
	-- golden hour: the last direct sun on the valley floor
	with(DAY_G, {
		hour = 16.4,
		Brightness = 2.5,
		Exposure = 0.02,
		Ambient = rgb(36, 38, 46),
		Outdoor = rgb(80, 88, 108),
		ShiftTop = rgb(216, 134, 66),
		Softness = 0.28,
		AtmDensity = 0.18,
		AtmOffset = 0.14,
		AtmColor = rgb(238, 210, 180),
		AtmDecay = rgb(142, 140, 160),
		AtmGlare = 0.8,
		AtmHaze = 1.9,
		GradeBrightness = 0.01,
		GradeContrast = 0.09,
		GradeSaturation = 0.04,
		GradeTint = rgb(255, 243, 228),
		BloomIntensity = 0.4,
		BloomSize = 34,
		BloomThreshold = 1.6,
		RaysIntensity = 0.12,
		RaysSpread = 0.65,
		CloudCover = 0.55,
		CloudDensity = 0.5,
		CloudColor = rgb(255, 238, 224),
		WindX = 4.5,
		WindZ = 2,
		WaterReflect = 0.55,
		WaterWave = 0.13,
	}),
	-- the valley floor in shade, warm light still on the peaks and the cloud: a cool, clean shade (not purple)
	with(DAY_G, {
		hour = 17.3,
		Brightness = 2.2,
		Exposure = 0.32,
		Ambient = rgb(36, 38, 46),
		Outdoor = rgb(88, 98, 122),
		ShiftTop = rgb(222, 128, 64),
		Softness = 0.3,
		AtmDensity = 0.17,
		AtmOffset = 0.14,
		AtmColor = rgb(232, 214, 198),
		AtmDecay = rgb(148, 150, 172),
		AtmGlare = 0.75,
		AtmHaze = 2.0,
		GradeBrightness = 0.01,
		GradeContrast = 0.08,
		GradeSaturation = 0,
		GradeTint = rgb(255, 249, 242),
		BloomIntensity = 0.4,
		BloomSize = 32,
		BloomThreshold = 1.6,
		RaysIntensity = 0.08,
		RaysSpread = 0.65,
		CloudCover = 0.55,
		CloudDensity = 0.5,
		CloudColor = rgb(255, 232, 216),
		WindX = 4,
		WindZ = 2,
		Mist = 0.05,
		Night = 0.05,
		WaterReflect = 0.6,
		WaterWave = 0.11,
		InteriorLight = 0.85,
	}),
	-- sunset (18:00): a pale peach afterglow (Haze 2.3 keeps the sky brighter than the peaks)
	with(DAY_G, {
		hour = 18.0,
		Brightness = 1.7,
		Exposure = 0.4,
		Ambient = rgb(34, 36, 44),
		Outdoor = rgb(76, 82, 104),
		ShiftTop = rgb(224, 116, 62),
		Softness = 0.32,
		AtmDensity = 0.18,
		AtmOffset = 0.12,
		AtmColor = rgb(236, 196, 168),
		AtmDecay = rgb(150, 134, 150),
		AtmGlare = 0.9,
		AtmHaze = 2.3,
		GradeBrightness = 0.01,
		GradeContrast = 0.09,
		GradeSaturation = -0.02,
		GradeTint = rgb(253, 247, 245),
		BloomIntensity = 0.42,
		BloomSize = 32,
		BloomThreshold = 1.55,
		RaysIntensity = 0.1,
		RaysSpread = 0.65,
		CloudCover = 0.55,
		CloudDensity = 0.45,
		CloudColor = rgb(250, 226, 212),
		WindX = 3.5,
		WindZ = 1.5,
		Mist = 0.15,
		Night = 0.1,
		WaterReflect = 0.65,
		WaterWave = 0.1,
		InteriorLight = 0.7,
	}),
	-- blue hour: no direct light until the moon takes over (19.25); the twilight fill carries the ground
	with(NIGHT_G, {
		hour = 18.75,
		Brightness = 2.0,
		Exposure = 0.55,
		Ambient = rgb(56, 62, 84),
		Outdoor = rgb(72, 80, 108),
		ShiftTop = rgb(112, 116, 170),
		Softness = 0.3,
		AtmDensity = 0.24,
		AtmOffset = 0.18,
		AtmColor = rgb(52, 58, 88),
		AtmDecay = rgb(34, 34, 58),
		AtmGlare = 0.12,
		AtmHaze = 1.9,
		GradeContrast = 0.11,
		GradeSaturation = -0.12,
		GradeTint = rgb(226, 230, 255),
		BloomThreshold = 1.45,
		CloudCover = 0.5,
		CloudDensity = 0.4,
		CloudColor = rgb(198, 200, 222),
		Mist = 0.5,
		Night = 0.6,
		WaterReflect = 0.65,
		InteriorLight = 0.55,
	}),
	with(NIGHT_G, { hour = 19.7 }),
	with(NIGHT_G, { hour = 24 }),
}

-- Tracks added after the classic set was written: filled in once, so every keyframe of every set has every key.
local NEW_KEY_DEFAULTS = { WaterReflect = 1, WaterWave = 0.15, InteriorLight = 1 } -- the classic arena's fixed values
for _, key in ipairs(CLASSIC) do
	for name, value in pairs(NEW_KEY_DEFAULTS) do
		if key[name] == nil then
			key[name] = value
		end
	end
end

DayCycle.LookSets = { ClassicForest = CLASSIC, GreenLand = GREEN_LAND }
DayCycle.LookSet = if DayCycle.LookSets[Config.Map] then Config.Map else "ClassicForest"
DayCycle.Looks = DayCycle.LookSets[DayCycle.LookSet]

-- Hour-independent values of each arena's look. ServerStorage.WorldGen.LightingRig writes them at edit time (they are
-- saved with the place); nothing writes them while the game runs.
--   GrassLength 0.1 (the engine's shortest): Roblox's grass blades at 0.7 stood knee-high and filled the lower half
--   of every eye-height view on the open meadow, hiding the flower beds. At 0.1 the ground still reads as grass that
--   moves in the wind, and the view is the valley. (Seen in Studio: 0.3 still hid a boulder; 0.1 does not.)
--   Water: reflectance 0.7 made the lake a pale sheet of sky; at 0.4 by day it keeps its own blue-green.
DayCycle.StaticSets = {
	GreenLand = {
		WaterColor = rgb(28, 92, 108), -- an alpine lake: deep blue-green; also how it reads where water draws opaque
		WaterTransparency = 0.5,
		WaterWaveSpeed = 8,
		GrassLength = 0.1,
		SunAngularSize = 12,
		MoonAngularSize = 6,
		FarBlur = false,
	},
	ClassicForest = {
		WaterTransparency = 0.65, -- (its water colour belongs to the vault's Settings)
		GrassLength = 0.7,
		SunAngularSize = 12,
		MoonAngularSize = 5,
		FarBlur = true,
	},
}
DayCycle.Static = DayCycle.StaticSets[DayCycle.LookSet]

local NUMBER_KEYS = {
	"Brightness", "Exposure", "EnvDiffuse", "EnvSpecular", "Softness", "AtmDensity", "AtmOffset", "AtmGlare", "AtmHaze",
	"GradeBrightness", "GradeContrast", "GradeSaturation", "BloomIntensity", "BloomSize", "BloomThreshold",
	"RaysIntensity", "RaysSpread", "CloudCover", "CloudDensity", "DofFar", "WindX", "WindZ", "Mist", "Night", "Stars",
	"WaterReflect", "WaterWave", "InteriorLight",
}
local COLOR_KEYS = { "Ambient", "Outdoor", "ShiftTop", "ShiftBottom", "AtmColor", "AtmDecay", "GradeTint", "CloudColor" }

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Brightness multiplier around the engine's sun/moon switches (1 away from them, ~0 at the switch).
function DayCycle.handoffFactor(hour: number): number
	local K = DayCycle.Knobs
	local function dip(center: number, before: number, after: number): number
		local d = ((hour - center + 12) % 24) - 12 -- hours from the switch, negative before it
		local x
		if d < 0 then
			if d <= -before then
				return 1
			end
			x = -d / before
		else
			if d >= after then
				return 1
			end
			x = d / after
		end
		return 1 - K.HandoffDepth * (1 - smooth(x))
	end
	return math.min(
		dip(K.HandoffDusk, K.HandoffGuard, K.HandoffFade), -- dusk: the moonlight fades in after the switch
		dip(K.HandoffDawn, K.HandoffFade, K.HandoffGuard) -- dawn: it fades out before the switch
	)
end

-- Weight of the twilight fill at an hour (0..1): 1 while the engine gives no direct light (sunset .. the dusk switch,
-- the dawn switch .. sunrise), easing in as the sky light falls in the late afternoon, out as the moonlight fades in
-- (exactly complementary to handoffFactor's fade), back in as the moonlight fades before dawn, and out as the sun climbs.
function DayCycle.twilightFill(hour: number): number
	local K = DayCycle.Knobs
	local h = hour % 24
	local e0, e1 = K.TwilightEvening[1], K.TwilightEvening[2]
	local m0, m1 = K.TwilightMorning[1], K.TwilightMorning[2]
	local dusk, dawn, fade = K.HandoffDusk, K.HandoffDawn, K.HandoffFade
	if h >= e0 and h < e1 then
		return smooth((h - e0) / (e1 - e0))
	elseif h >= e1 and h < dusk then
		return 1
	elseif h >= dusk and h < dusk + fade then
		return 1 - smooth((h - dusk) / fade) -- the moonlight takes over
	elseif h >= dawn - fade and h < dawn then
		return smooth((h - (dawn - fade)) / fade) -- the moonlight fades out
	elseif h >= dawn and h < m0 then
		return 1
	elseif h >= m0 and h < m1 then
		return 1 - smooth((h - m0) / (m1 - m0))
	end
	return 0
end

-- Interpolated look at an hour of the day (0..24). Reuses `out` when given (no garbage per frame).
function DayCycle.lookAt(hour: number, out: { [string]: any }?): { [string]: any }
	local looks = DayCycle.Looks
	hour = hour % 24
	local a, b = looks[1], looks[#looks]
	for i = 1, #looks - 1 do
		if hour >= looks[i].hour and hour <= looks[i + 1].hour then
			a, b = looks[i], looks[i + 1]
			break
		end
	end
	local span = b.hour - a.hour
	local t = if span > 1e-6 then smooth(math.clamp((hour - a.hour) / span, 0, 1)) else 0
	local look = out or {}
	for _, key in ipairs(NUMBER_KEYS) do
		local va, vb = a[key], b[key]
		look[key] = va + (vb - va) * t
	end
	for _, key in ipairs(COLOR_KEYS) do
		look[key] = a[key]:Lerp(b[key], t)
	end
	local knobs = DayCycle.Knobs
	-- night ambient lift: scale the ambient colours by how "night" this hour is
	local night = math.clamp(look.Night or 0, 0, 1)
	local lift = 1 + (knobs.NightAmbientLift - 1) * night
	if lift ~= 1 then
		local function scale(c: Color3): Color3
			return Color3.new(math.min(1, c.R * lift), math.min(1, c.G * lift), math.min(1, c.B * lift))
		end
		look.Ambient = scale(look.Ambient)
		look.Outdoor = scale(look.Outdoor)
	end
	-- the twilight fill: no darker than the keyframe, eased toward the cool fill while there is no direct light
	local fill = DayCycle.twilightFill(hour)
	if fill > 0 then
		local function lift(c: Color3, target: Color3): Color3
			local l = c:Lerp(target, fill)
			return Color3.new(math.max(c.R, l.R), math.max(c.G, l.G), math.max(c.B, l.B))
		end
		look.Outdoor = lift(look.Outdoor, knobs.TwilightOutdoor)
		look.Ambient = lift(look.Ambient, knobs.TwilightAmbient)
	end
	look.Twilight = fill
	-- hide the engine's sun/moon switch
	look.Brightness *= DayCycle.handoffFactor(hour)
	look.Exposure += knobs.ExposureOffset
	look.AtmDensity = math.clamp(look.AtmDensity * knobs.HazeScale, 0, 1)
	look.BloomIntensity *= knobs.BloomScale
	look.RaysIntensity *= knobs.SunRaysScale
	look.WindX *= knobs.WindScale
	look.WindZ *= knobs.WindScale
	look.Mist = math.clamp(look.Mist * knobs.MistStrength, 0, 1)
	look.hour = hour
	look.Tier = nil -- applyTier marks the look it has scaled
	return look
end

--[[
	Shader tiers. DetailController decides the tier and publishes it as the LocalPlayer attribute ShaderTier;
	ArenaController.Sky calls applyTier(look, tier) between lookAt and applyLook. The engine still scales shadows,
	draw distance and water detail with the player's graphics level underneath: no script can change that. A tier
	decides only what the game adds on top, so a phone gets a planned look and never pays for a full-screen pass
	it cannot afford.
	  fill / nightFill   multiply Outdoor and Ambient (nightFill at full night): a touch more fill where no shadows draw
	  contrast           added to GradeContrast
	  bloom, bloomSizeMax   multiply BloomIntensity (0 switches the effect off), cap BloomSize
	  rays               multiplies RaysIntensity (0 switches the effect off)
	  dof                multiplies DofFar (0 switches the effect off)
	  haze               added to AtmDensity (softens the line where a weak device's world stops)
	  neutral            "Shaders: Off": no grade, no glare, no colour shift, default shadow softness
	  water              the WaterReflect / WaterWave tracks are written
	  clockHz / lookHz   sun position / look writes per second (0 = every frame)
	  mistRate / mistMax / mistRange   mist sheets: rate multiplier, how many emit at once (nearest first), range
]]
DayCycle.Tiers = {
	Off = {
		fill = 1.2, nightFill = 1.1, contrast = 0, bloom = 0, bloomSizeMax = 24, rays = 0, dof = 0, haze = 0,
		neutral = true, water = false, clockHz = 4, lookHz = 10, mistRate = 0, mistMax = 0, mistRange = 0,
	},
	Phone = {
		fill = 1.0, nightFill = 1.12, contrast = 0.02, bloom = 0.6, bloomSizeMax = 24, rays = 0, dof = 0, haze = 0.03,
		neutral = false, water = false, clockHz = 4, lookHz = 10, mistRate = 0.4, mistMax = 6, mistRange = 220,
	},
	Mid = {
		fill = 1.0, nightFill = 1.0, contrast = 0, bloom = 0.85, bloomSizeMax = 40, rays = 0.8, dof = 0, haze = 0.01,
		neutral = false, water = true, clockHz = 0, lookHz = 30, mistRate = 0.7, mistMax = 14, mistRange = 340,
	},
	High = {
		fill = 1.0, nightFill = 1.0, contrast = 0, bloom = 1, bloomSizeMax = 56, rays = 1, dof = 1, haze = 0,
		neutral = false, water = true, clockHz = 0, lookHz = 0, mistRate = 1, mistMax = 28, mistRange = 460,
	},
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Scales a look in place for a shader tier ("Off" | "Phone" | "Mid" | "High"; nil or unknown = High). Call it after
-- lookAt. deviceTier is the tier the device would have on Auto: "Off" takes its haze from it.
function DayCycle.applyTier(look, tierName: string?, deviceTier: string?)
	local name = if tierName and DayCycle.Tiers[tierName] then tierName else "High"
	local tier = DayCycle.Tiers[name]
	local haze = tier.haze
	if tier.neutral then
		local device = deviceTier and DayCycle.Tiers[deviceTier]
		haze = if device and not device.neutral then device.haze else 0
	end
	local night = math.clamp(look.Night or 0, 0, 1)
	local fill = tier.fill * (1 + (tier.nightFill - 1) * night)
	if fill ~= 1 then
		local o, a = look.Outdoor, look.Ambient
		look.Outdoor = Color3.new(math.min(1, o.R * fill), math.min(1, o.G * fill), math.min(1, o.B * fill))
		look.Ambient = Color3.new(math.min(1, a.R * fill), math.min(1, a.G * fill), math.min(1, a.B * fill))
	end
	look.GradeContrast += tier.contrast
	look.BloomIntensity *= tier.bloom
	look.BloomSize = math.min(look.BloomSize, tier.bloomSizeMax)
	look.RaysIntensity *= tier.rays
	look.DofFar *= tier.dof
	look.AtmDensity = math.clamp(look.AtmDensity + haze, 0, 1)
	if tier.neutral then
		look.GradeBrightness = 0
		look.GradeContrast = 0
		look.GradeSaturation = 0
		look.GradeTint = WHITE
		look.AtmGlare = 0
		look.ShiftTop = BLACK
		look.Softness = 0.2
	end
	look.Tier = name
	return look
end

local function differs(a: any, b: any, eps: number): boolean
	if a == nil or b == nil then
		return true
	end
	local kind = typeof(a)
	if kind == "Color3" then
		return math.abs(a.R - b.R) > eps or math.abs(a.G - b.G) > eps or math.abs(a.B - b.B) > eps
	elseif kind == "Vector3" then
		return (a - b).Magnitude > eps
	end
	return math.abs(a - b) > eps
end

--[[
	Writes a look. targets = { lighting = Lighting, atmosphere = Atmosphere?, grade = ColorCorrectionEffect?,
	bloom = BloomEffect?, rays = SunRaysEffect?, sky = Sky?, dof = DepthOfFieldEffect?, clouds = Clouds?,
	wind = Workspace?, terrain = Terrain?, interiorLight = PointLight? }. cache (optional table) remembers what was written so unchanged properties are skipped
	(cheap to call every frame). The wind written is (look.WindX, 0, look.WindZ): the client folds its gusts into those.
]]
function DayCycle.applyLook(look, targets, cache: { [string]: any }?)
	local c = cache or {}
	local function set(obj: Instance?, prop: string, key: string, value: any, eps: number)
		if not obj then
			return
		end
		if cache and not differs(c[key], value, eps) then
			return
		end
		c[key] = value;
		(obj :: any)[prop] = value
	end
	-- an effect at zero is switched off, so the engine skips its full-screen pass
	local function setOn(obj: Instance?, key: string, on: boolean)
		if not obj or (cache and c[key] == on) then
			return
		end
		c[key] = on;
		(obj :: any).Enabled = on
	end
	local L = targets.lighting
	set(L, "Brightness", "Brightness", look.Brightness, 0.002)
	set(L, "ExposureCompensation", "Exposure", look.Exposure, 0.001)
	set(L, "Ambient", "Ambient", look.Ambient, 0.001)
	set(L, "OutdoorAmbient", "Outdoor", look.Outdoor, 0.001)
	set(L, "ColorShift_Top", "ShiftTop", look.ShiftTop, 0.001)
	set(L, "ColorShift_Bottom", "ShiftBottom", look.ShiftBottom, 0.001)
	set(L, "EnvironmentDiffuseScale", "EnvDiffuse", look.EnvDiffuse, 0.002)
	set(L, "EnvironmentSpecularScale", "EnvSpecular", look.EnvSpecular, 0.002)
	set(L, "ShadowSoftness", "Softness", look.Softness, 0.002)
	local A = targets.atmosphere
	set(A, "Density", "AtmDensity", look.AtmDensity, 0.001)
	set(A, "Offset", "AtmOffset", look.AtmOffset, 0.001)
	set(A, "Color", "AtmColor", look.AtmColor, 0.002)
	set(A, "Decay", "AtmDecay", look.AtmDecay, 0.002)
	set(A, "Glare", "AtmGlare", look.AtmGlare, 0.003)
	set(A, "Haze", "AtmHaze", look.AtmHaze, 0.003)
	local G = targets.grade
	set(G, "Brightness", "GradeBrightness", look.GradeBrightness, 0.001)
	set(G, "Contrast", "GradeContrast", look.GradeContrast, 0.001)
	set(G, "Saturation", "GradeSaturation", look.GradeSaturation, 0.001)
	set(G, "TintColor", "GradeTint", look.GradeTint, 0.001)
	local B = targets.bloom
	set(B, "Intensity", "BloomIntensity", look.BloomIntensity, 0.002)
	set(B, "Size", "BloomSize", look.BloomSize, 0.1)
	set(B, "Threshold", "BloomThreshold", look.BloomThreshold, 0.002)
	setOn(B, "BloomOn", look.BloomIntensity > 0.01)
	local R = targets.rays
	set(R, "Intensity", "RaysIntensity", look.RaysIntensity, 0.002)
	set(R, "Spread", "RaysSpread", look.RaysSpread, 0.002)
	setOn(R, "RaysOn", look.RaysIntensity > 0.005)
	local D = targets.dof
	set(D, "FarIntensity", "DofFar", look.DofFar, 0.002)
	setOn(D, "DofOn", look.DofFar > 0.005)
	-- the water's two tracks: only where the tier writes them (a look no tier has scaled, as at edit time, writes them)
	local T = targets.terrain
	local tier = look.Tier and DayCycle.Tiers[look.Tier]
	if T and (tier == nil or tier.water) then
		set(T, "WaterReflectance", "WaterReflect", look.WaterReflect, 0.01)
		set(T, "WaterWaveSize", "WaterWave", look.WaterWave, 0.005)
	end
	local CL = targets.clouds
	set(CL, "Cover", "CloudCover", look.CloudCover, 0.003)
	set(CL, "Density", "CloudDensity", look.CloudDensity, 0.003)
	set(CL, "Color", "CloudColor", look.CloudColor, 0.003)
	local H = targets.interiorLight
	if H then
		local base = H:GetAttribute("BaseBrightness")
		set(H, "Brightness", "InteriorLight", (if type(base) == "number" then base else 0.5) * look.InteriorLight, 0.004)
	end
	local W = targets.wind
	if W then
		set(W, "GlobalWind", "Wind", Vector3.new(look.WindX, 0, look.WindZ), 0.05)
	end
	local S = targets.sky
	if S then
		set(S, "StarCount", "Stars", math.floor(look.Stars + 0.5), 49)
	end
end

-- The arena's interior lamp (the horn's fill light), or nil: for applyLook's targets.interiorLight.
function DayCycle.findInteriorLight(): PointLight?
	local arena = workspace:FindFirstChild("Arena")
	local landmarks = arena and arena:FindFirstChild("Landmarks")
	local horn = landmarks and landmarks:FindFirstChild("Horn")
	local light = horn and horn:FindFirstChild("HornLight", true)
	if light and light:IsA("PointLight") then
		return light
	end
	return nil
end

------------------------------------------------------------------------------------------------------------------------
-- The Roll Call ("The Fallen") show timeline
------------------------------------------------------------------------------------------------------------------------

DayCycle.Recap = {
	LeadIn = 1.0, -- seconds between the server announcing a Roll Call and the show starting (clients sync to it)
	StaticIn = 2.6, -- TV static fades in and crackles
	CaptionAssemble = 2.2, -- the static streams into the day caption ("DUSK · DAY ONE" / "4 FELL TODAY")
	CaptionHold = 2.8,
	Break = 0.65, -- a shape breaks back into static before the next one
	Assemble = 1.9, -- static streams into a fallen contender's bust and name
	AssembleMin = 1.4, -- (on a big day each one assembles faster)
	HoldMax = 3.0, -- seconds each bust holds (shorter when many fell)
	HoldMin = 1.5,
	HoldStep = 0.09,
	SingleExtra = 1.5, -- extra hold when only one contender fell (there is no group finale)
	FinaleAssemble = 2.4, -- all of the day's fallen together
	FinaleHold = 4.6,
	CloseAssemble = 1.8, -- the day caption again, to close
	CloseHold = 2.6,
	NoneAssemble = 2.2, -- nobody fell: the caption alone ("NO ONE FELL TODAY")
	NoneHold = 5.4,
	Dissolve = 1.5, -- back into static
	StaticOut = 0.9,
	FadeOut = 1.5, -- the static thins out and is gone
}

local DAY_WORDS = { "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN" }

-- The day caption the show opens and closes on: ("DUSK · DAY ONE", "4 FELL TODAY").
function DayCycle.recapCaption(day: number, count: number, mode: string?): (string, string)
	day = math.max(1, math.floor(tonumber(day) or 1))
	count = math.max(0, math.floor(tonumber(count) or 0))
	local line1 = (if mode == "epilogue" then "DAY " else "DUSK · DAY ") .. (DAY_WORDS[day] or tostring(day))
	local line2 = if count == 0 then "NO ONE FELL TODAY" else string.format("%d FELL TODAY", count)
	return line1, line2
end

--[[
	recapTimeline(count) -> {
	  count, total,
	  segments = { { kind = "static"|"caption"|"none"|"person"|"finale"|"dissolve", index?, t0, tb, t1, t2, t3? } },
	  revealAt = { [i] = seconds when person i is fully assembled },
	}
	static -> caption (opens) -> each fallen contender -> all of them together (2+) -> caption (closes) -> dissolve.
	Nobody fell: static -> the caption with "NO ONE FELL TODAY" ("none") -> dissolve.
	mode "epilogue" (QW14, behind the winner card, about 20 s): static -> caption -> all of them together ("finale"; one
	fallen: that "person") -> dissolve. revealAt[i] = when the group (or the one) is assembled.
	For each segment: t0 = start, tb = end of the break into static (= t0 when there is none), t1 = assembled,
	t2 = hold end (next segment starts). "dissolve": t1 = fully static, t2 = static thinning starts, t3 = gone.
	caption index: 1 = the opening caption, 2 = the closing one.
]]
function DayCycle.recapTimeline(count: number, mode: string?)
	local R = DayCycle.Recap
	count = math.max(0, math.floor(count))
	local segments = {}
	local revealAt = {}
	local t = 0
	table.insert(segments, { kind = "static", t0 = 0, tb = 0, t1 = R.StaticIn, t2 = R.StaticIn })
	t = R.StaticIn
	if mode == "epilogue" and count > 0 then
		table.insert(segments, { kind = "caption", index = 1, t0 = t, tb = t, t1 = t + R.CaptionAssemble,
			t2 = t + R.CaptionAssemble + R.CaptionHold })
		t += R.CaptionAssemble + R.CaptionHold
		local tb = t + R.Break
		local t1 = tb + R.FinaleAssemble
		if count == 1 then
			table.insert(segments, { kind = "person", index = 1, t0 = t, tb = tb, t1 = t1, t2 = t1 + R.FinaleHold })
		else
			table.insert(segments, { kind = "finale", t0 = t, tb = tb, t1 = t1, t2 = t1 + R.FinaleHold })
		end
		for i = 1, count do
			revealAt[i] = t1
		end
		t = t1 + R.FinaleHold
	elseif count == 0 then
		table.insert(segments, { kind = "none", t0 = t, tb = t, t1 = t + R.NoneAssemble, t2 = t + R.NoneAssemble + R.NoneHold })
		t += R.NoneAssemble + R.NoneHold
	else
		table.insert(segments, { kind = "caption", index = 1, t0 = t, tb = t, t1 = t + R.CaptionAssemble,
			t2 = t + R.CaptionAssemble + R.CaptionHold })
		t += R.CaptionAssemble + R.CaptionHold
		local hold = math.clamp(R.HoldMax - R.HoldStep * (count - 1), R.HoldMin, R.HoldMax)
		if count == 1 then
			hold += R.SingleExtra
		end
		local assemble = math.clamp(R.Assemble - 0.05 * math.max(0, count - 6), R.AssembleMin, R.Assemble)
		for i = 1, count do
			local tb = t + R.Break
			local t1 = tb + assemble
			table.insert(segments, { kind = "person", index = i, t0 = t, tb = tb, t1 = t1, t2 = t1 + hold })
			revealAt[i] = t1
			t = t1 + hold
		end
		if count >= 2 then
			local tb = t + R.Break
			local t1 = tb + R.FinaleAssemble
			table.insert(segments, { kind = "finale", t0 = t, tb = tb, t1 = t1, t2 = t1 + R.FinaleHold })
			t = t1 + R.FinaleHold
		end
		local tb = t + R.Break
		local t1 = tb + R.CloseAssemble
		table.insert(segments, { kind = "caption", index = 2, t0 = t, tb = tb, t1 = t1, t2 = t1 + R.CloseHold })
		t = t1 + R.CloseHold
	end
	local d1 = t + R.Dissolve
	local d2 = d1 + R.StaticOut
	local d3 = d2 + R.FadeOut
	table.insert(segments, { kind = "dissolve", t0 = t, tb = t, t1 = d1, t2 = d2, t3 = d3 })
	return { count = count, total = d3, segments = segments, revealAt = revealAt }
end

function DayCycle.recapDuration(count: number, mode: string?): number
	return DayCycle.recapTimeline(count, mode).total
end

return DayCycle
