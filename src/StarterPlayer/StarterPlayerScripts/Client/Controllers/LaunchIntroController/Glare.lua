--[[
	LaunchIntroController.Glare - the sun in your eyes as you come up into the arena (the owner, 18 Nov: "slight
	blinding by the sun when he gets there"). One smooth rise and one smooth fall of light, never a flash, no sprite
	and no hard white frame.
	  * The rise belongs to the launch shot (LaunchIntroController.stepShot): the set's light floods and a cover in
	    this module's colour comes over the picture, up to `peak` at the cut onto your plinth. The cut between the set
	    and the arena hides under it. Glare.sky(hour) gives that colour, the peak and how far the set floods.
	  * The fall is here (Glare.begin / update / finish), from the cut: the cover clears while the picture, over-bright
	    with a soft bloom, settles as the eyes adjust. The exposure (Lighting.ExposureCompensation) and the "Bloom"
	    effect are raised on top of the day cycle's own values and taken off again; the cover's pale warm colour is the
	    tint.
	It follows the real sun (Lighting:GetSunDirection() at the arena's hour, read every frame):
	  strength = how high the sun is  x  the cloud  x  how far you look toward it  x  shade
	    sun height   0 below the horizon, full from about 13 degrees up (a round starts at 07:24 with the sun 19 up)
	    cloud        1 up to the day cycle's usual cover (0.6), down to 0.4 under a closed sky
	    toward it    1 looking at the sun, 0.3 with it beside or behind you (everyone gets a little)
	    shade        0.55 when something solid stands between your eyes and the sun (one raycast, a moment in)
	  A strong glare (daylight, facing the sun) lifts the exposure by EXPOSURE stops and takes 2 s to settle; a gentle
	  one (dawn, cloud, the sun behind you) lifts it a little and takes 1.5 s; at night nothing is lifted and the
	  cover, dark then, clears in under a second. Turning away during the fall lets it go faster; turning toward the
	  sun never brings it back up (the level only ever falls).
	"Shaders: Off" (opts.bloom = false; there is no bloom, and that player asked for a plain picture): nothing in
	Lighting is touched. The same pale cover fades by itself over the same time, a plain fade.
	The day cycle (ArenaController.Sky) writes its look on Heartbeat and remembers what it wrote; this module writes on
	top before every rendered frame and, at the end, writes the day cycle's own value back (opts.getLook, the look the
	sky is showing; for the first frames after a shot, while the sky has not written yet, the same look worked out here
	with DayCycle.lookAt and applyTier).
	API:
	  Glare.arenaHour() -> number                the arena's hour of the day as ArenaController.Sky shows it
	  Glare.sky(hour?) -> { hour, day (0..1 daylight), cloud (0.4..1), color: Color3 (the cover), peak (its alpha at
	                        the cut), flood (how far the set's light floods before the cut: 1 by day, under 0 at night) }
	  Glare.begin(opts) -> state                 opts.from (the cover's alpha now), opts.bloom (false = Shaders: Off),
	                                             opts.sky (Glare.sky's table), opts.getLook (() -> the sky's look),
	                                             opts.fresh (true straight after a shot: the sky's look is not written
	                                             yet, and the sun is put at the arena's hour at once)
	  Glare.update(state, dt) -> (alpha, color, done)    once before every rendered frame; the cover to draw
	  Glare.finish(state)                        takes everything off again (safe to call twice)
	Studio only: LocalPlayer attribute LS_LaunchGlareFreeze = seconds holds the fall at that moment (for stills);
	LS_LaunchGlare (JSON) reports each glare when it ends: hour, the sun's height, the cloud, the facing, shade,
	strength, seconds, the exposure it added at most.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local localPlayer = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()

local PEAK = 0.95 -- the cover's alpha at the cut: near white, the picture still just there
local DAY_COLOR = Color3.fromRGB(255, 247, 234) -- a pale warm white: the faint warm tint
local NIGHT_COLOR = Color3.fromRGB(10, 13, 22) -- at night the cut passes through the dark, with no light at all
local EXPOSURE = 1.3 -- stops added at full strength, at the cut (under the cover: what shows is its fall)
local BLOOM_INTENSITY = 0.8 -- added to the bloom's Intensity at full strength
local BLOOM_THRESHOLD = 0.9 -- taken off its Threshold at full strength (the day's 1.9 becomes 1.0: sky and lit ground glow)
local BLOOM_THRESHOLD_MIN = 0.7
local BLOOM_SIZE = 12 -- added to its Size at full strength (never over the shader tier's own cap)
local SUN_FULL = 0.25 -- the sun direction's Y from which the daylight counts as full (about 13 degrees up)
local SHADE = 0.55 -- strength left when something solid hides the sun
local RAY = 3000 -- studs the shade test looks toward the sun
local GRACE = 0.15 -- seconds in which the strength may still be set (the first frames after the cut, under the cover)
local TRUST_FRAMES = 3 -- after a shot the sky's own look is taken from this frame on

local Glare = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- 0..1 daylight from the sun direction's Y
local function daylight(sunY: number): number
	return smooth((sunY + 0.03) / SUN_FULL)
end

-- The arena's hour as ArenaController.Sky works it out for a contender (the "Clock" time base; in Studio the
-- workspace attribute DevLookHour pins it).
function Glare.arenaHour(): number
	if IS_STUDIO then
		local pin = workspace:GetAttribute("DevLookHour")
		if type(pin) == "number" and pin == pin then
			return pin % 24
		end
	end
	local ok, clock = pcall(function()
		local base = DayCycle.decodeClock(GameState:GetAttribute("Clock"))
		return if base then DayCycle.evalClock(base, workspace:GetServerTimeNow()) else nil
	end)
	if ok and type(clock) == "number" and clock == clock then
		return clock % 24
	end
	return (tonumber(Config.Round.LobbyClockTime) or 14) % 24
end

-- What the launch shot needs before the cut, from the hour alone (the shot holds the day cycle, so Lighting still
-- shows the lobby's sun then). The sun rises at 06:00 and sets at 18:00 in this engine whatever the latitude; in this
-- place (GeographicLatitude 44) its direction is (0.937 sin a, -0.937 cos a, 0.35) with a = hour / 24 of a turn
-- (read in Studio on 18 Nov at 14:30: (-0.570, 0.743, 0.350)), so its height is -0.937 cos a.
function Glare.sky(hour: number?): { [string]: any }
	local h = (if type(hour) == "number" and hour == hour then hour else Glare.arenaHour()) % 24
	local day = daylight(-0.937 * math.cos(math.pi * h / 12))
	local cover = 0.5
	local ok, look = pcall(DayCycle.lookAt, h)
	if ok and type(look) == "table" and type(look.CloudCover) == "number" then
		cover = look.CloudCover
	end
	local cloud = 1 - 0.6 * smooth((cover - 0.6) / 0.3)
	local light = day * (0.7 + 0.3 * cloud)
	return {
		hour = h,
		day = day,
		cloud = cloud,
		color = NIGHT_COLOR:Lerp(DAY_COLOR, light ^ 0.7),
		peak = PEAK,
		flood = lerp(-0.35, 1, light),
	}
end

-- the shader tier as ArenaController.Sky reads it (DetailController's LocalPlayer attributes)
local function tierNames(): (string, string)
	local name = localPlayer:GetAttribute("ShaderTier")
	local device = localPlayer:GetAttribute("ShaderDevice")
	if type(name) ~= "string" or not DayCycle.Tiers[name] then
		name = "High"
	end
	if type(device) ~= "string" or not DayCycle.Tiers[device] then
		device = name
	end
	return name, device
end

-- the arena's bloom, found as ArenaController.Sky finds it
local function bloomEffect(): BloomEffect?
	local named = Lighting:FindFirstChild("Bloom")
	if named and named:IsA("BloomEffect") then
		return named
	end
	return Lighting:FindFirstChildOfClass("BloomEffect")
end

-- The day cycle's own values under the glare: the look the sky is showing, else the arena's look worked out here.
local function baseLook(g): { [string]: any }
	if g.getLook and g.frames >= g.trustAt then
		local ok, look = pcall(g.getLook)
		if ok and type(look) == "table" and type(look.Exposure) == "number" and look.Tier ~= nil then
			return look
		end
	end
	local own = g.look
	DayCycle.lookAt(Glare.arenaHour(), own)
	local name, device = tierNames()
	DayCycle.applyTier(own, name, device)
	return own
end

-- Something solid between the eyes and the sun: the ground, the horn, a trunk. Clear things (glass, an unseen wall)
-- are looked past, three at most.
local function shaded(eye: Vector3, sun: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore: { Instance } = {}
	if localPlayer.Character then
		table.insert(ignore, localPlayer.Character)
	end
	params.FilterDescendantsInstances = ignore
	for _ = 1, 3 do
		local hit = workspace:Raycast(eye + sun * 1.5, sun * RAY, params)
		if not hit then
			return false
		end
		local inst = hit.Instance
		if inst:IsA("Terrain") or inst.Transparency < 0.5 then
			return true
		end
		table.insert(ignore, inst)
		params.FilterDescendantsInstances = ignore
	end
	return false
end

-- How strong the glare is this frame, 0..1, from the real sun and where the camera looks.
local function measure(g): number
	local sun = Lighting:GetSunDirection()
	local day = daylight(sun.Y)
	g.sunY, g.day = sun.Y, day
	local cam = workspace.CurrentCamera
	if not cam or day <= 0 then
		g.facing = 0
		return 0
	end
	local dot = cam.CFrame.LookVector:Dot(sun)
	g.facing = dot
	if g.shade == nil and g.t >= 0.04 then
		local ok, hit = pcall(shaded, cam.CFrame.Position, sun)
		g.shade = ok and hit == true
	end
	local toward = 0.3 + 0.7 * smooth((dot + 0.1) / 0.9)
	return clamp01(day * g.cloud * toward * (if g.shade then SHADE else 1))
end

-- seconds the fall takes: 1.5 (gentle) to 2 (strong) by day, under a second at night
local function duration(day: number, strength: number): number
	return lerp(0.9, lerp(1.5, 2.0, strength), smooth(day / 0.3))
end

local function write(g, boost: number)
	local base = baseLook(g)
	if type(base.Exposure) ~= "number" then
		return
	end
	Lighting.ExposureCompensation = base.Exposure + EXPOSURE * boost
	g.wrote = true
	local fx = bloomEffect()
	if fx and type(base.BloomIntensity) == "number" and base.BloomIntensity > 0.01 and type(base.BloomSize) == "number"
		and type(base.BloomThreshold) == "number" then
		local name = tierNames()
		local cap = math.max(base.BloomSize, tonumber(DayCycle.Tiers[name].bloomSizeMax) or 56)
		fx.Intensity = base.BloomIntensity + BLOOM_INTENSITY * boost
		fx.Size = math.min(cap, base.BloomSize + BLOOM_SIZE * boost)
		fx.Threshold = math.max(math.min(base.BloomThreshold, BLOOM_THRESHOLD_MIN), base.BloomThreshold - BLOOM_THRESHOLD * boost)
		g.wroteBloom = true
	end
end

function Glare.begin(opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local sky = if type(o.sky) == "table" then o.sky else Glare.sky()
	local from = clamp01(tonumber(o.from) or tonumber(sky.peak) or PEAK)
	local g = {
		from = from,
		alpha = from,
		boost = math.huge,
		bloom = o.bloom ~= false,
		color = if typeof(sky.color) == "Color3" then sky.color else DAY_COLOR,
		cloud = clamp01(tonumber(sky.cloud) or 1),
		hour = tonumber(sky.hour),
		getLook = if type(o.getLook) == "function" then o.getLook else nil,
		trustAt = if o.fresh == true then TRUST_FRAMES else 1,
		look = {},
		t = 0,
		frames = 0,
		peak = 0,
		ended = false,
	}
	if o.fresh == true then
		-- the arena's own sun from the first frame (the day cycle, held during the shot, writes the same hour a moment
		-- later): the strength is read from it
		pcall(function()
			local hour = Glare.arenaHour()
			if math.abs(Lighting.ClockTime - hour) > 1e-3 then
				Lighting.ClockTime = hour
			end
		end)
	end
	return g
end

function Glare.update(g, dt: number): (number, Color3, boolean)
	local step = if dt == dt then math.clamp(dt, 0, 0.1) else 0
	g.frames += 1
	g.t += step
	local tau = g.t
	local frozen = false
	if IS_STUDIO then
		local hold = localPlayer:GetAttribute("LS_LaunchGlareFreeze")
		if type(hold) == "number" and hold == hold then
			tau, frozen = math.max(0, hold), true
		end
	end
	-- how strong: set in the first moment (under the cover), then it follows the camera slowly
	local live = measure(g)
	if g.strength == nil or g.t < GRACE or frozen then
		g.strength = live
		g.length = duration(g.day, live)
	else
		g.strength += (live - g.strength) * (1 - math.exp(-5 * step))
	end
	local strength, length = g.strength, g.length
	local x = clamp01(tau / length)
	-- the cover: with the shaders it clears early and the over-bright picture carries the rest; without them it is the
	-- whole effect and fades over the full time
	local alpha
	if g.bloom then
		alpha = g.from * (1 - smooth(tau / lerp(0.5, 0.85, strength))) ^ 1.3
	else
		alpha = g.from * lerp(1 - smooth(tau / 0.55), (1 - x) ^ 2, 0.25 + 0.75 * strength)
	end
	-- the eyes adjusting: fast at first, then a long soft tail
	local boost = strength * (1 - x) ^ 2.2
	if not frozen and g.t >= GRACE then
		-- one rise and one fall: from here the level only ever goes down
		alpha = math.min(alpha, g.alpha)
		boost = math.min(boost, g.boost)
	end
	g.alpha, g.boost = alpha, boost
	if g.t >= 0.04 then
		g.peak = math.max(g.peak, boost)
	end
	if g.bloom then
		write(g, boost)
	end
	return alpha, g.color, (not frozen) and tau >= length
end

function Glare.finish(g)
	if type(g) ~= "table" or g.ended then
		return
	end
	g.ended = true
	if g.wrote then
		local ok, base = pcall(baseLook, g)
		if ok and type(base) == "table" then
			pcall(function()
				if type(base.Exposure) == "number" then
					Lighting.ExposureCompensation = base.Exposure
				end
			end)
			if g.wroteBloom then
				pcall(function()
					local fx = bloomEffect()
					if fx and type(base.BloomIntensity) == "number" then
						fx.Intensity = base.BloomIntensity
						fx.Size = base.BloomSize
						fx.Threshold = base.BloomThreshold
					end
				end)
			end
		end
	end
	if IS_STUDIO then
		pcall(function()
			local function round(v: any): any
				return if type(v) == "number" and v == v then math.floor(v * 1000 + 0.5) / 1000 else nil
			end
			local json = HttpService:JSONEncode({
				hour = round(Glare.arenaHour()), sunY = round(g.sunY), day = round(g.day), cloud = round(g.cloud),
				facing = round(g.facing), shade = g.shade == true, strength = round(g.strength), seconds = round(g.length),
				exposure = round(EXPOSURE * g.peak), bloom = g.bloom, from = round(g.from), frames = g.frames,
				wrote = g.wrote == true,
			})
			localPlayer:SetAttribute("LS_LaunchGlare", json)
			print("[LaunchIntroController] glare ended: " .. json)
		end)
	end
end

return Glare
