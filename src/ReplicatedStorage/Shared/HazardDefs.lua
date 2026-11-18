--[[
	HazardDefs - the arena challenges' numbers, lines and wire format. Server (HazardService) and clients
	(HazardController) read the same table, so a warning, a zone or a boulder's path is the same everywhere.
	The looks (colours, parts, particles) are in Shared.HazardLook; nothing here draws anything.

	THE CHALLENGES
	  Butterflies  vivid blue butterflies rest in the flower beds, the gorse and along the paths. Running through a
	               roost (or the called challenge, "the Bloom") raises a swarm that follows the nearest contender.
	               Inside it you are stung. Escape: break their line of sight, get into water, stand in campfire
	               smoke, or outrun them until they tire. Walking past a roost never wakes it.
	  Fog          a cold fog fills a hollow up to a height. Below its top you cannot see far and you lose warmth;
	               once the warmth is gone you lose health. Escape: climb above it (a slope, a tree, a roof), walk out
	               of it, or stand by a fire.
	  Storm        a storm cell comes down off the mountain and drifts across. Lightning marks the ground for a moment
	               and then strikes; the wind pushes anyone in the open. Escape: leave the cell, get under a roof or
	               rock, crouch (a crouching contender is never aimed at and takes half).
	  Rockfall     boulders come down a steep slope in waves. Escape: step out of the fall line, or stand behind rock.

	WHAT IS REPLICATED (all server-decided)
	  GameState attribute HazardEvent   "" or one event, fields joined by "|":
	      kind | seq | warnAt | startAt | endAt | x | z | radius | seed | intensity | a | b | c | d
	    Times are workspace:GetServerTimeNow() seconds. warnAt..startAt = the warning (nothing hurts), startAt..endAt =
	    active. a..d belong to the kind:
	      Butterflies  -
	      Fog          a = the ground at the centre (y), b = the fog's full top (y)
	      Storm        a, b = the cell's drift (studs a second, x and z)
	      Rockfall     a = boulders, b = the chute's side spread (studs)
	  GameState attribute HazardWind    "x,z" studs a second while a storm blows, else nil (for projectiles: see the
	                                    hand-off notes; nothing reads it yet)
	  workspace.Hazards                 a Folder made at run time: one small invisible anchored Part per butterfly
	                                    roost. Attributes: S (state, HazardDefs.Roost.*), K (what it sits in),
	                                    N (how many butterflies, a scale 0..1). A swarm is its roost's part, moved.
	  Player attributes                 HazardChill 0..1 (the fog's cold), HazardStung = server time of the last sting
	  Remote ReplicatedStorage.Remotes.HazardFx (made by HazardService at start; not in Net.Names on purpose: the game
	                                    runs unchanged without this service)
	      "L", x, y, z, strikeAt      lightning: the ground is marked now and struck at strikeAt
	      "H", vx, vz, power          to one player: a boulder or a bolt threw you (a shove and a camera shake)
	      "S", text                   to one player: a plain line for the hazard readout (tests and escapes)
]]
local HazardDefs = {}

HazardDefs.Kinds = { "Butterflies", "Fog", "Storm", "Rockfall" }
HazardDefs.ATTR_EVENT = "HazardEvent"
HazardDefs.ATTR_WIND = "HazardWind"
HazardDefs.FOLDER = "Hazards"
HazardDefs.REMOTE = "HazardFx"

-- Roost states (the part's S attribute)
HazardDefs.Roost = {
	Rest = 0, -- butterflies sit with closed wings; scenery
	Stir = 1, -- the Bloom's warning, or a contender walked close: a few lift and settle
	Swarm = 2, -- up and following someone: the part moves
	Return = 3, -- tired or shaken off: drifting home
	Away = 4, -- the roost is empty for a while
}

HazardDefs.Butterflies = {
	Name = "THE BLUE SWARM",
	-- scenery
	RoostsMin = 10,
	RoostsMax = 26,
	RoostsPer100Studs = 1.6, -- of the round's start radius
	RoostSpacing = 70,
	HeartQuietTime = 60, -- no roost wakes in the round's first minute (the rush to the horn)
	-- waking one
	DisturbRadius = 12,
	DisturbSpeed = 15.5, -- studs a second: running wakes them, walking (13) and crouching never do
	MaxSwarms = 6, -- flying at once, arena-wide (the Bloom may add its own)
	RestCooldown = 50, -- seconds a roost stays quiet after its swarm comes home
	-- the swarm
	SwarmRadius = 7, -- stung inside this
	RiseTime = 1.2, -- the swarm lifts for this long before it moves
	ChaseSpeed = 18, -- fresh: faster than a walk (13), slower than a sprint (21)
	TiredSpeed = 9,
	Stamina = 20, -- seconds of chase before it gives up
	Leash = 80, -- a target this far away is forgotten
	LoseSightTime = 2, -- seconds without a clear line to the target
	WaterTime = 0.8, -- seconds the target is in water
	SmokeRadius = 10, -- studs from a lit campfire
	SmokeTime = 0.8,
	ReturnSpeed = 22,
	-- the sting
	StingInterval = 0.5,
	DamagePerSecond = 3,
	Floor = 25, -- at or under this health the swarm does not hurt ...
	StayTime = 8, -- ... unless you have stood in it this long without a break
	StayDamagePerSecond = 2,
	-- the called challenge
	Warning = 15,
	Duration = 40,
	Radius = 170,
	BloomStamina = 32,
	BloomLeash = 130,
	BloomExtraRoosts = 3, -- temporary roosts put near the contenders when the zone holds too few
	Cause = "Butterflies",
	Herald = "Something blue is waking in the flowers. Walk softly, or find water.",
	Card = "THE BLUE SWARM",
	Hint = "Butterflies · break their sight, find water or smoke, or outrun them",
	Over = "The swarm has settled.",
}

HazardDefs.Fog = {
	Name = "THE COLD FOG",
	Warning = 20,
	Rise = 8, -- seconds from the start until the fog stands at its full top
	Duration = 55,
	Fade = 10, -- the last seconds of the duration: the top sinks back
	Radius = 190, -- + RadiusPerAlive per living contender, up to RadiusMax
	RadiusPerAlive = 4,
	RadiusMax = 300,
	Depth = 13, -- studs from the centre's ground to the fog's top (x intensity, 9 at least)
	WarnDepth = 3, -- the thin ground mist of the warning
	ChillTime = 10, -- seconds under the fog until the warmth is gone
	WarmTime = 5, -- seconds out of it to be warm again
	DamagePerSecond = 2, -- once the warmth is gone
	FireRadius = 12, -- a lit campfire this close keeps you warm even in the fog
	Cause = "Cold",
	Herald = "The valley is filling with cold. Climb above it, or find a fire.",
	Card = "THE COLD FOG",
	Hint = "Cold fog · climb above it or find a fire",
	Over = "The fog is lifting.",
}

HazardDefs.Storm = {
	Name = "THE MOUNTAIN STORM",
	Warning = 20,
	Duration = 60,
	Radius = 230,
	Drift = 4, -- studs a second
	LeadDistance = 120, -- the cell starts this far up-wind of the contenders it was called for
	StrikeEvery = { 2.4, 4.2 }, -- seconds between bolts (divided by the intensity)
	StrikeLead = 1.5, -- seconds the ground is marked before the bolt
	AimChance = 0.45, -- a bolt goes for an exposed standing contender this often; otherwise high ground in the cell
	StrikeRadius = 14,
	StrikeCore = 5,
	Damage = 35, -- inside the core, falling to DamageEdge at the radius
	DamageEdge = 8,
	CrouchScale = 0.5,
	CoverScale = 0, -- under a roof or rock: none
	CoverHeight = 70, -- studs of sky checked over a contender's head
	WindSpeed = 26, -- studs a second, the replicated HazardWind
	WindPush = 5.5, -- studs a second squared on an exposed contender (client)
	Cause = "Lightning",
	Herald = "A storm is coming down off the mountain. Get low. Get under stone.",
	Card = "THE MOUNTAIN STORM",
	Hint = "Storm · leave the high ground, get under cover, stay low",
	Over = "The storm has passed.",
}

HazardDefs.Rockfall = {
	Name = "ROCKFALL",
	Warning = 15,
	Duration = 26, -- the last boulder has stopped by then
	Boulders = { 6, 10 }, -- at intensity 0.6 and 1
	Waves = { 0, 5, 10 }, -- seconds after the start
	WaveJitter = 1.6,
	Spread = 22, -- studs either side of the chute's line
	MeanSpeed = 24, -- studs a second over the whole run
	BoulderRadius = { 3, 5 },
	HitReach = 2.5, -- beyond the boulder's radius
	Damage = { 28, 45 }, -- by how fast the boulder is going
	Radius = 150, -- the warning zone drawn round the chute's middle
	-- chutes (found once from the coarse height grid)
	MinSlope = 0.42, -- rise over run at the top
	RunSlope = 0.1, -- the boulders stop where the ground is flatter than this
	Step = 16,
	MaxSteps = 22,
	MinLength = 110,
	MinDrop = 40,
	Cause = "Rockfall",
	Herald = "The slope is letting go. Get out of the fall line.",
	Card = "ROCKFALL",
	Hint = "Rockfall · step out of the fall line or get behind rock",
	Over = "The slope is still.",
}

-- The director (HazardService.Director): windows in round-schedule seconds. Each round takes PickMin..PickMax of them
-- at random, a random moment inside each, and a random challenge from each one's list.
HazardDefs.Director = {
	QuietStart = 60, -- nothing is called in the first minute
	QuietEnd = 800, -- nothing new after this (the last stand follows at 830)
	Cooldown = 25, -- seconds after an event clears before another may be called
	PickMin = 3,
	PickMax = 4,
	MaxShare = 0.6, -- a zone never holds more than this share of the living (when four or more live)
	FeastGuard = 35, -- no event is active this close to the Offering (Config.Events.FeastTime), either side
	PracticeDamage = 0.5, -- a lone practice round: half damage
	Slots = {
		{ from = 75, to = 130, intensity = 0.6, kinds = { "Butterflies", "Rockfall", "Fog" } },
		{ from = 200, to = 260, intensity = 1, kinds = { "Storm", "Fog", "Butterflies", "Rockfall" } },
		{ from = 400, to = 450, intensity = 1, kinds = { "Fog", "Butterflies" } }, -- the night
		{ from = 505, to = 520, intensity = 1, kinds = { "Fog", "Rockfall" } }, -- before dawn; over before the Offering
		{ from = 640, to = 690, intensity = 1.15, kinds = { "Storm", "Butterflies", "Rockfall" } },
		{ from = 730, to = 760, intensity = 1.15, kinds = { "Storm", "Fog" } },
	},
	MaxUses = { Butterflies = 2, Fog = 1, Storm = 1, Rockfall = 1 },
}

----------------------------------------------------------------------------------------------------
-- The wire format
----------------------------------------------------------------------------------------------------
local FIELDS = { "kind", "seq", "warnAt", "startAt", "endAt", "x", "z", "radius", "seed", "intensity", "a", "b", "c", "d" }

function HazardDefs.encode(event: { [string]: any }): string
	local out = table.create(#FIELDS)
	for i, name in ipairs(FIELDS) do
		local value = event[name]
		if i == 1 then
			out[i] = tostring(value)
		elseif type(value) == "number" then
			-- two decimals: a hundredth of a second, a hundredth of a stud
			out[i] = (string.format("%.2f", value):gsub("%.?0+$", ""))
			if out[i] == "" or out[i] == "-" then
				out[i] = "0"
			end
		else
			out[i] = "0"
		end
	end
	return table.concat(out, "|")
end

function HazardDefs.decode(text: any): { [string]: any }?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local parts = string.split(text, "|")
	if #parts < 10 or HazardDefs[parts[1]] == nil then
		return nil
	end
	local event = { kind = parts[1] }
	for i = 2, #FIELDS do
		event[FIELDS[i]] = tonumber(parts[i]) or 0
	end
	return event
end

-- "Warn" | "Active" | "Over" at server time t
function HazardDefs.phaseAt(event: { [string]: any }, t: number): string
	if t < event.startAt then
		return "Warn"
	elseif t < event.endAt then
		return "Active"
	end
	return "Over"
end

----------------------------------------------------------------------------------------------------
-- Fog: the height of its top at server time t (the same curve on the server and on every client)
----------------------------------------------------------------------------------------------------
function HazardDefs.fogTopAt(event: { [string]: any }, t: number): number
	local F = HazardDefs.Fog
	local base, top = event.a, event.b
	local warnTop = base + F.WarnDepth
	if t <= event.warnAt then
		return base - 2
	elseif t < event.startAt then
		local u = (t - event.warnAt) / math.max(event.startAt - event.warnAt, 0.01)
		return base - 2 + (warnTop - base + 2) * u
	elseif t < event.startAt + F.Rise then
		local u = (t - event.startAt) / F.Rise
		u = u * u * (3 - 2 * u)
		return warnTop + (top - warnTop) * u
	elseif t < event.endAt - F.Fade then
		return top
	elseif t < event.endAt then
		local u = (event.endAt - t) / F.Fade
		u = u * u * (3 - 2 * u)
		return base - 2 + (top - base + 2) * u
	end
	return base - 2
end

----------------------------------------------------------------------------------------------------
-- Storm: where the cell's centre is at server time t
----------------------------------------------------------------------------------------------------
function HazardDefs.stormCentreAt(event: { [string]: any }, t: number): (number, number)
	local dt = math.clamp(t - event.startAt, -HazardDefs.Storm.Warning, event.endAt - event.startAt)
	return event.x + event.a * dt, event.z + event.b * dt
end

----------------------------------------------------------------------------------------------------
-- Rockfall: chutes and boulder paths from the coarse height grid (Shared.Map1Regions), which the server and
-- every client hold in full. Everything below is pure arithmetic on that grid and a seed.
----------------------------------------------------------------------------------------------------
local heightFn: ((number, number) -> number)? = nil
local heightTried = false

local function coarseHeight(): ((number, number) -> number)?
	if not heightTried then
		heightTried = true
		local module = script.Parent:FindFirstChild("Map1Regions")
		if module and module:IsA("ModuleScript") then
			local ok, regions = pcall(require, module)
			if ok and type(regions) == "table" and type(regions.heightAt) == "function" then
				heightFn = regions.heightAt
			end
		end
	end
	return heightFn
end
HazardDefs.coarseHeight = coarseHeight

-- downhill unit direction and slope (rise over run) at a point
local function fallLine(h: (number, number) -> number, x: number, z: number): (number, number, number)
	local e = 24
	local gx = (h(x + e, z) - h(x - e, z)) / (2 * e)
	local gz = (h(x, z + e) - h(x, z - e)) / (2 * e)
	local slope = math.sqrt(gx * gx + gz * gz)
	if slope < 1e-4 then
		return 0, 0, 0
	end
	return -gx / slope, -gz / slope, slope
end
HazardDefs.fallLine = function(x: number, z: number): (number, number, number)
	local h = coarseHeight()
	if not h then
		return 0, 0, 0
	end
	return fallLine(h, x, z)
end

-- The path a boulder takes from (x, z): points { x, y, z } every Step studs down the fall line until the ground
-- flattens, with the distance run. force = true follows any slope at all (the Studio trigger on gentle ground).
function HazardDefs.tracePath(x: number, z: number, force: boolean?): ({ Vector3 }, number)
	local R = HazardDefs.Rockfall
	local h = coarseHeight()
	local points = {}
	if not h then
		return points, 0
	end
	local px, pz = x, z
	local lastDx, lastDz = 0, 0
	local length = 0
	table.insert(points, Vector3.new(px, h(px, pz), pz))
	for step = 1, R.MaxSteps do
		local dx, dz, slope = fallLine(h, px, pz)
		if slope < (if force then 0.02 else R.RunSlope) and step > 2 then
			-- flat: roll out one more step along the way it was going, then stop
			if lastDx ~= 0 or lastDz ~= 0 then
				px += lastDx * R.Step * 0.6
				pz += lastDz * R.Step * 0.6
				length += R.Step * 0.6
				table.insert(points, Vector3.new(px, h(px, pz), pz))
			end
			break
		end
		if dx == 0 and dz == 0 then
			break
		end
		-- momentum: a boulder does not turn on the spot
		if lastDx ~= 0 or lastDz ~= 0 then
			dx, dz = dx * 0.65 + lastDx * 0.35, dz * 0.65 + lastDz * 0.35
			local m = math.sqrt(dx * dx + dz * dz)
			dx, dz = dx / m, dz / m
		end
		px += dx * R.Step
		pz += dz * R.Step
		lastDx, lastDz = dx, dz
		length += R.Step
		table.insert(points, Vector3.new(px, h(px, pz), pz))
	end
	return points, length
end

-- The boulders of one rockfall event: { { release (server time), radius, points, length, duration, spin } }.
function HazardDefs.boulders(event: { [string]: any }): { { [string]: any } }
	local R = HazardDefs.Rockfall
	local list = {}
	local h = coarseHeight()
	if not h then
		return list
	end
	local rng = Random.new(math.floor(event.seed))
	local count = math.clamp(math.floor(event.a + 0.5), 1, 16)
	local spread = if event.b > 0 then event.b else R.Spread
	local dx, dz = fallLine(h, event.x, event.z)
	local sideX, sideZ = -dz, dx
	local force = event.c == 1
	for i = 1, count do
		local wave = R.Waves[((i - 1) % #R.Waves) + 1]
		local offset = rng:NextNumber(-spread, spread)
		local back = rng:NextNumber(-10, 10)
		local sx = event.x + sideX * offset - dx * back
		local sz = event.z + sideZ * offset - dz * back
		local points, length = HazardDefs.tracePath(sx, sz, force)
		local radius = rng:NextNumber(R.BoulderRadius[1], R.BoulderRadius[2])
		local speed = R.MeanSpeed * rng:NextNumber(0.85, 1.2)
		table.insert(list, {
			index = i,
			release = event.startAt + wave + rng:NextNumber(0, R.WaveJitter),
			radius = radius,
			points = points,
			length = length,
			duration = math.max(length / speed, 1.5),
			spin = rng:NextNumber(0.7, 1.3) * (if rng:NextNumber() < 0.5 then -1 else 1),
			tilt = rng:NextNumber(-0.5, 0.5),
		})
	end
	return list
end

-- A boulder at server time t: position (on the coarse ground, its centre), speed 0..1 of its fastest, its heading,
-- and "state": "Wait" before its release, "Roll", "Rest" once it has stopped.
function HazardDefs.boulderAt(b: { [string]: any }, t: number): (Vector3?, number, Vector3, string)
	local points = b.points
	if #points < 2 then
		return nil, 0, Vector3.zAxis, "Rest"
	end
	local u = (t - b.release) / b.duration
	if u <= 0 then
		return points[1] + Vector3.new(0, b.radius * 0.8, 0), 0, Vector3.zAxis, "Wait"
	end
	local state = "Roll"
	if u >= 1 then
		u, state = 1, "Rest"
	end
	-- slow off the mark, fastest two thirds down, easing to a stop
	local e = u * u * (3 - 2 * u)
	local speed = 6 * u * (1 - u) / 1.5 -- 0..1
	local run = e * b.length
	local step = HazardDefs.Rockfall.Step
	local index = math.clamp(math.floor(run / step) + 1, 1, #points - 1)
	local a, c = points[index], points[index + 1]
	local segment = (c - a).Magnitude
	local f = if segment > 0 then math.clamp((run - (index - 1) * step) / segment, 0, 1) else 0
	local p = a:Lerp(c, f)
	-- a bounce that dies as it slows
	local hop = math.abs(math.sin(run * 0.11 + b.index)) * b.radius * 0.9 * speed
	local heading = c - a
	heading = Vector3.new(heading.X, 0, heading.Z)
	if heading.Magnitude > 1e-3 then
		heading = heading.Unit
	else
		heading = Vector3.zAxis
	end
	return p + Vector3.new(0, b.radius * 0.8 + hop, 0), speed, heading, state
end

return HazardDefs
