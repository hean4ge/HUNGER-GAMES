--[[
	Sky (ArenaController helper, client) - the day/night cycle on this client.
	  * Every frame: Lighting.ClockTime from the server's time base (GameState "Clock", decoded by Shared.DayCycle):
	    smooth on every client, no stepping. Then the whole lighting look for that hour (DayCycle.Looks): sun / moon
	    brightness (dipped around the engine's sun/moon switches), exposure, ambient, colour shift, environment light,
	    shadow softness, Atmosphere, the "ArenaGrade" colour correction, Bloom, SunRays, depth of field, clouds, the
	    star count and the wind.
	  * Wind: the look's base Workspace.GlobalWind (grass, clouds, particles) plus slow gusts and a gentle swing in
	    direction (DayCycle.Knobs.GustStrength), written at 10 Hz.
	  * Players in the lobby (not in the arena and not spectating) keep the lobby hour (Config.Round.LobbyClockTime).
	  * Held while the launch intro lights its own set (ClientState.launchShot, LaunchIntroController); the whole look is
	    written again the frame after.
	  * The shader tier (LocalPlayer attribute ShaderTier: Off / Phone / Mid / High, decided by DetailController) scales
    the look through DayCycle.applyTier: bloom, sun rays, haze, fill, the water's tracks, how often the sun and the
    look are written, and how many mist sheets emit. A phone never pays for a full-screen pass it can't afford.
  * Studio only: the workspace attribute DevLookHour (a number) pins the hour on this client, for captures.
  * Low mist sheets over the marsh and the lake at night and dawn (client-local particles, DayCycle look "Mist").
    The sheets are lit by the scene only (no glow of their own); the nearest ones emit, up to the tier's cap.
	    Zones come from ArenaLayout.Lake (shore polygon, or centre + radiusX/radiusZ) and ArenaLayout.Marsh (outline
	    polygon, pools, or centre + radius), else the Swamp/Marsh sector. Each sheet settles on the real water or
	    ground surface (a terrain raycast once that terrain has streamed in), so it follows whichever terrain is built.
	API (through ArenaController): Sky.start(ClientState), Sky.getClock() -> (clock, arenaView), Sky.getLook() -> look,
Sky.getTier() -> (tier name, device tier name)
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local Sky = {}

local ClientState = nil
local base = nil -- decoded "Clock" time base
local clock = Config.Round.LobbyClockTime
local arenaView = false
local look = {}
local cache = {}
local targets = { lighting = Lighting }
local nextTargetScan = 0
local mist = { parts = {}, emitters = {}, built = false, nextUpdate = 0 }
local wind = { nextWrite = 0, x = 0, z = 0 }
local held = false -- the launch intro holds the day cycle (ClientState.launchShot)
local tierName, deviceTier = "High", "High" -- the shader tier (DetailController publishes it)
local tier = DayCycle.Tiers.High
local nextClockWrite, nextLookWrite = 0, 0
local IS_STUDIO = RunService:IsStudio()

local MIST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MIST_SPACING = 56 -- studs between mist sheets over water
local MIST_RATE = 0.85 -- particles per second per sheet at full mist
local MIST_MAX = 150 -- sheets in all
local MIST_LIFT = 2.6 -- studs above the surface

local function findTargets()
	local function child(className: string, name: string?): Instance?
		if name then
			local named = Lighting:FindFirstChild(name)
			if named and named:IsA(className) then
				return named
			end
		end
		return Lighting:FindFirstChildOfClass(className)
	end
	targets.atmosphere = child("Atmosphere")
	local grade = Lighting:FindFirstChild("ArenaGrade")
	if grade and not grade:IsA("ColorCorrectionEffect") then
		grade = nil
	end
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "ArenaGrade"
		grade.Parent = Lighting
	end
	targets.grade = grade
	targets.bloom = child("BloomEffect", "Bloom")
	targets.rays = child("SunRaysEffect", "SunRays")
	targets.dof = child("DepthOfFieldEffect", "DepthOfField")
	targets.sky = child("Sky", "Sky")
	targets.clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	targets.wind = workspace
	targets.terrain = workspace.Terrain
	targets.interiorLight = DayCycle.findInteriorLight() -- the horn's fill light (it streams in with the horn)
	table.clear(cache) -- objects may be new: write everything once
end

local function readBase()
	base = DayCycle.decodeClock(GameState:GetAttribute("Clock"))
end

local function inArenaView(): boolean
	if ClientState == nil then
		return false
	end
	if ClientState.spectating ~= nil then
		return true
	end
	return ClientState.inArena == true
end

-- Mist -----------------------------------------------------------------------------------------------------------------

local function pointXZ(p: any): (number?, number?)
	if typeof(p) == "Vector3" then
		return p.X, p.Z
	elseif typeof(p) == "Vector2" then
		return p.X, p.Y
	elseif type(p) == "table" then
		local x = p[1] or p.x or p.X
		local z = p[2] or p.z or p.Z
		if type(x) == "number" and type(z) == "number" then
			return x, z
		end
	end
	return nil, nil
end

-- A polygon given as { {x, z}, ... } (or Vector3s): its points and bounding box, or nil.
local function polygonOf(list: any)
	if type(list) ~= "table" or #list < 3 then
		return nil
	end
	local xs, zs = {}, {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(list) do
		local x, z = pointXZ(p)
		if not x then
			return nil
		end
		table.insert(xs, x)
		table.insert(zs, z)
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
	end
	return { xs = xs, zs = zs, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function insidePolygon(poly, x: number, z: number): boolean
	local xs, zs = poly.xs, poly.zs
	local n = #xs
	local inside = false
	local j = n
	for i = 1, n do
		if ((zs[i] > z) ~= (zs[j] > z)) and (x < (xs[j] - xs[i]) * (z - zs[i]) / (zs[j] - zs[i]) + xs[i]) then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- Mist sheet positions: { { x, z, y (the layout's water level, refined by a raycast later), strength } }
local function mistSpots()
	local spots = {}
	local function add(x: number, z: number, y: number, strength: number)
		if #spots < MIST_MAX then
			table.insert(spots, { x = x, z = z, y = y, strength = strength })
		end
	end
	local function fillPolygon(poly, y: number, strength: number)
		for gx = poly.minX, poly.maxX, MIST_SPACING do
			for gz = poly.minZ, poly.maxZ, MIST_SPACING * 0.87 do
				local row = math.floor((gz - poly.minZ) / (MIST_SPACING * 0.87))
				local x = gx + (row % 2) * MIST_SPACING * 0.5
				if insidePolygon(poly, x, gz) then
					add(x, gz, y, strength)
				end
			end
		end
	end
	local function fillEllipse(center: any, rx: number?, rz: number?, y: number, strength: number)
		if typeof(center) ~= "Vector3" or type(rx) ~= "number" or type(rz) ~= "number" or rx <= 0 or rz <= 0 then
			return false
		end
		local cx, cz = center.X, center.Z
		local nx = math.ceil(rx * 2 / MIST_SPACING)
		local nz = math.ceil(rz * 2 / MIST_SPACING)
		for ix = 0, nx do
			for iz = 0, nz do
				local x = cx - rx + ix * MIST_SPACING + (iz % 2) * MIST_SPACING * 0.5
				local z = cz - rz + iz * MIST_SPACING
				local dx, dz = (x - cx) / rx, (z - cz) / rz
				if dx * dx + dz * dz <= 1.05 then
					add(x, z, y, strength)
				end
			end
		end
		return true
	end
	local water = ArenaLayout.WaterLevel or 14
	local lake = (ArenaLayout :: any).Lake
	if type(lake) == "table" then
		local y = lake.level or lake.waterY or water
		local shore = polygonOf(lake.shore)
		if shore then
			fillPolygon(shore, y, 1)
		else
			fillEllipse(lake.center, lake.radiusX or lake.radius, lake.radiusZ or lake.radius, y, 1)
		end
	end
	local hasMarsh = false
	for _, key in ipairs({ "Marsh", "Swamp" }) do
		local marsh = (ArenaLayout :: any)[key]
		if type(marsh) == "table" then
			local y = marsh.level or marsh.waterY or water
			local outline = polygonOf(marsh.outline)
			if outline then
				fillPolygon(outline, y, 1.15)
				hasMarsh = true
			elseif type(marsh.pools) == "table" then
				for _, pool in ipairs(marsh.pools) do
					if type(pool) == "table" then
						hasMarsh = fillEllipse(pool.center, pool.radiusX or pool.radius, pool.radiusZ or pool.radius,
							pool.level or y, 1.15) or hasMarsh
					end
				end
			else
				hasMarsh = fillEllipse(marsh.center, marsh.radiusX or marsh.radius, marsh.radiusZ or marsh.radius, y, 1.15)
			end
			break
		end
	end
	if not hasMarsh and type(ArenaLayout.Sectors) == "table" then
		-- no marsh data: the Swamp / Marsh sector, low ground at water level
		for _, sector in ipairs(ArenaLayout.Sectors) do
			if sector.name == "Swamp" or sector.name == "Marsh" then
				local from, to = sector.from, sector.to
				if from > to then
					to += 360
				end
				fillEllipse(ArenaLayout.polar(((from + to) / 2) % 360, 420), 170, 150, water, 1.15)
			end
		end
	end
	return spots
end

-- The shader tier this client runs: DetailController's choice (LocalPlayer attributes ShaderTier / ShaderDevice).
local function readTier()
	local lp = Players.LocalPlayer
	local name = lp and lp:GetAttribute("ShaderTier")
	local device = lp and lp:GetAttribute("ShaderDevice")
	if type(name) ~= "string" or not DayCycle.Tiers[name] then
		name = "High"
	end
	if type(device) ~= "string" or not DayCycle.Tiers[device] then
		device = name
	end
	if name ~= tierName then
		table.clear(cache) -- a tier switches effects on and off: write everything once
	end
	tierName, deviceTier = name, device
	tier = DayCycle.Tiers[name]
end

local function buildMist()
	mist.built = true
	local spots = mistSpots()
	if #spots == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientMist"
	for _, spot in ipairs(spots) do
		local part = Instance.new("Part")
		part.Name = "MistSheet"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Locked = true
		part.Size = Vector3.new(MIST_SPACING * 1.1, 3, MIST_SPACING * 1.1)
		part.CFrame = CFrame.new(spot.x, spot.y + MIST_LIFT, spot.z)
		local e = Instance.new("ParticleEmitter")
		e.Name = "Mist"
		e.Texture = MIST_TEXTURE
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 0
		e.Lifetime = NumberRange.new(10, 15)
		e.Speed = NumberRange.new(0.3, 1.1)
		e.SpreadAngle = Vector2.new(80, 80)
		e.Acceleration = Vector3.new(0.12, 0.03, 0.05)
		e.Drag = 0.4
		e.WindAffectsDrag = true -- the mist drifts with the (gentle) night wind
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 12),
			NumberSequenceKeypoint.new(0.5, 22, 4),
			NumberSequenceKeypoint.new(1, 30, 5),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.8),
			NumberSequenceKeypoint.new(0.7, 0.83),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Color = ColorSequence.new(Color3.fromRGB(206, 214, 226))
		e.LightInfluence = 1
		e.LightEmission = 0 -- lit by the scene only: mist never glows
		e.Brightness = 1
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-5, 5)
		e.Enabled = false
		e.Parent = part
		part.Parent = folder
		table.insert(mist.parts, part)
		table.insert(mist.emitters, { emitter = e, part = part, x = spot.x, z = spot.z, y = spot.y, strength = spot.strength,
			settled = false, tries = 0 })
	end
	folder.Parent = workspace
end

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
surfaceParams.IgnoreWater = false

-- Put a sheet on the real water / ground surface under it (once that terrain has streamed in).
local function settle(entry): boolean
	surfaceParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(entry.x, entry.y + 260, entry.z), Vector3.new(0, -520, 0), surfaceParams)
	if not hit then
		return false
	end
	local y = hit.Position.Y + MIST_LIFT
	entry.position = Vector3.new(entry.x, y, entry.z)
	entry.part.CFrame = CFrame.new(entry.position)
	return true
end

local mistNear = {} -- reused: the sheets in range this update

local function updateMist()
	if not mist.built then
		buildMist()
	end
	local level = (look.Mist or 0)
	if not arenaView then
		level = 0
	end
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local range = tier.mistRange
	local budget = 8 -- surface raycasts per update
	-- the sheets in range, nearest first, up to the tier's cap
	table.clear(mistNear)
	if level * tier.mistRate > 0.02 and tier.mistMax > 0 then
		for _, entry in ipairs(mist.emitters) do
			local dx, dz = entry.x - camPos.X, entry.z - camPos.Z
			local d2 = dx * dx + dz * dz
			entry.d2 = d2
			entry.want = false
			if d2 <= range * range then
				table.insert(mistNear, entry)
			end
		end
		if #mistNear > tier.mistMax then
			table.sort(mistNear, function(a, b)
				return a.d2 < b.d2
			end)
		end
		for i = 1, math.min(#mistNear, tier.mistMax) do
			mistNear[i].want = true
		end
	else
		for _, entry in ipairs(mist.emitters) do
			entry.want = false
		end
	end
	for _, entry in ipairs(mist.emitters) do
		local e = entry.emitter
		local rate = MIST_RATE * level * entry.strength * tier.mistRate
		local on = entry.want and rate > 0.02
		if on and not entry.settled and budget > 0 then
			budget -= 1
			entry.settled = settle(entry)
		end
		if on and entry.settled then
			if math.abs(e.Rate - rate) > 0.01 then
				e.Rate = rate
			end
			if not e.Enabled then
				e.Enabled = true
			end
		elseif e.Enabled then
			e.Enabled = false
		end
	end
end

-- Wind ---------------------------------------------------------------------------------------------------------------

-- 0..1: slow, irregular gusts (a few seconds each, every 5-15 seconds), the same shape on every client
local function gustAt(t: number): number
	local n = math.noise(t * 0.11, 0.37) + 0.55 * math.noise(t * 0.31, 4.21) + 0.25 * math.noise(t * 0.9, 9.73)
	local g = math.clamp((n + 0.05) / 0.55, 0, 1)
	return g * g * (3 - 2 * g)
end

-- Fold gusts and a gentle swing in direction into the look's base wind (in place).
local function applyGusts(t: number)
	local gust = gustAt(t)
	local k = 1 + (DayCycle.Knobs.GustStrength or 0.75) * gust
	local yaw = 0.16 * math.noise(t * 0.03, 2.5) + 0.1 * gust * math.noise(t * 0.4, 7.1)
	local wx, wz = look.WindX * k, look.WindZ * k
	local c, s = math.cos(yaw), math.sin(yaw)
	look.WindX = wx * c - wz * s
	look.WindZ = wx * s + wz * c
end

-- Per frame --------------------------------------------------------------------------------------------------------------

local function step()
	-- the launch intro lights its own set: hold, then write the whole look again (its writes bypassed the cache)
	if ClientState and ClientState.launchShot then
		held = true
		return
	end
	if held then
		held = false
		table.clear(cache)
	end
	arenaView = inArenaView()
	if arenaView and base then
		clock = DayCycle.evalClock(base, workspace:GetServerTimeNow())
	else
		clock = Config.Round.LobbyClockTime
	end
	if IS_STUDIO then
		local pin = workspace:GetAttribute("DevLookHour")
		if type(pin) == "number" then
			clock = pin
		end
	end
	local hour = clock % 24
	local t = os.clock()
	readTier()
	-- the sun's position: every frame, or a few times a second on the low tiers (nobody can see 0.1 of a degree)
	if tier.clockHz <= 0 or t >= nextClockWrite or math.abs(Lighting.ClockTime - hour) > 0.05 then
		nextClockWrite = t + (if tier.clockHz > 0 then 1 / tier.clockHz else 0)
		if math.abs(Lighting.ClockTime - hour) > 1e-4 then
			Lighting.ClockTime = hour
		end
	end
	if t >= nextTargetScan or not (targets.grade and targets.grade.Parent) then
		nextTargetScan = t + 5
		findTargets()
	end
	DayCycle.lookAt(hour, look)
	-- the wind changes slowly: 10 writes a second at most (the cache skips tiny changes)
	if t >= wind.nextWrite then
		wind.nextWrite = t + 0.1
		applyGusts(workspace:GetServerTimeNow())
		wind.x, wind.z = look.WindX, look.WindZ
	else
		look.WindX, look.WindZ = wind.x, wind.z
	end
	DayCycle.applyTier(look, tierName, deviceTier)
	if tier.lookHz <= 0 or t >= nextLookWrite or next(cache) == nil then
		nextLookWrite = t + (if tier.lookHz > 0 then 1 / tier.lookHz else 0)
		DayCycle.applyLook(look, targets, cache)
	end
	if t >= mist.nextUpdate then
		mist.nextUpdate = t + 0.25
		updateMist()
	end
end

function Sky.getClock(): (number, boolean)
	return clock, arenaView
end

function Sky.getLook()
	return look
end

function Sky.getTier(): (string, string)
	return tierName, deviceTier
end

function Sky.start(clientState)
	ClientState = clientState
	readBase()
	GameState:GetAttributeChangedSignal("Clock"):Connect(readBase)
	findTargets()
	local warnedAt = -math.huge
	-- every frame: the next rendered frame shows the new sun, sky and grade. Heartbeat (not a render step) so
	-- ClockTime stays right for anything that reads it even while the window isn't rendering.
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		-- a broken keyframe would freeze the sky: once in a live game, every 5 s in Studio so it can't be missed
		if not ok and (warnedAt == -math.huge or (IS_STUDIO and os.clock() - warnedAt >= 5)) then
			warnedAt = os.clock()
			warn("[ArenaController] sky update failed: " .. tostring(err))
		end
	end)
end

return Sky
