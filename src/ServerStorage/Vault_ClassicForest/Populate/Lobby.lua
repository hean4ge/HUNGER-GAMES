--[[
	Populate.Lobby - the Tor (workspace.Lobby, on the lobby island at ArenaLayout.LobbyPosition) dressed with the
	LandmarksReal lobby set.
	  Kept from v1 (they carry its functions): the stone terrace (courtyard, walkways, overlook, fire dais), the 8
	  SpawnLocations (Lobby.Spawns), the invisible barrier walls (moved to Lobby.Barrier), the AmbientEmitters and the
	  notice-board text (its SurfaceGui is carried onto the new boards' NoticeFace part).
	  Replaced (v1 archived in ServerStorage.Archive_v1.Lobby_v1): the 4 pavilions -> Pavilion on a resized stone base,
	  8 banners -> BannerPole, 8 braziers and the central fire -> Brazier, 10 benches -> Bench, 2 notice boards ->
	  NoticeBoard, 16 lantern posts -> none (the gates and pavilions carry lanterns), the pillar railing -> 66 Railing
	  segments, the stylised garden -> TreesReal / GroundReal plants.
	  Added: a LobbyGate at the head of each main walkway (flanked by its braziers), StoneSteps from the garden up to
	  the courtyard. Only the central fire's light casts shadows (the light budget).
	  Kept functions: the 8 braziers and the central fire burn (v1's Flame, Embers and Smoke emitters, scaled to each
	  bowl, on an attachment FireFx on the Ember part: flames show above the rim from eye level), and v1's climbable
	  garden oak comes back as a realistic OakA (Lobby.OAK_*: its OakA_Bark keeps the Climbable tag).
	Output: workspace.Lobby.Landmarks, .Garden and .Railing (attribute Realistic = true), .Barrier.
]]
local ServerStorage = game:GetService("ServerStorage")

local Lobby = {}

local V3 = Vector3.new
local rad, sin, cos, sqrt = math.rad, math.sin, math.cos, math.sqrt

-- name, keep-clear radius (scale 1), count, scale range, sink
local PLANTS = {
	{ "BirchA", 3.0, 4, { 0.55, 0.72 }, 0.2 },
	{ "SpruceB", 3.2, 3, { 0.5, 0.62 }, 0.2 },
	{ "ConiferYoung", 2.2, 6, { 0.8, 1.2 }, 0.15 },
	{ "SaplingBroadleaf", 2.6, 4, { 0.8, 1.05 }, 0.05 },
	{ "BushA", 3.0, 7, { 0.75, 1.0 }, 0.05 },
	{ "BushB", 3.0, 7, { 0.75, 1.0 }, 0.05 },
	{ "BerryBush", 2.6, 4, { 0.8, 1.0 }, 0.05 },
	{ "BoulderC", 3.0, 2, { 0.8, 1.0 }, 0.5 },
	{ "BoulderB", 1.9, 3, { 0.8, 1.1 }, 0.35 },
	{ "FernA", 1.8, 10, { 0.8, 1.1 }, 0.03 },
	{ "GrassTallA", 1.4, 10, { 0.8, 1.1 }, 0.03 },
	{ "GrassTallB", 1.4, 8, { 0.8, 1.1 }, 0.03 },
	{ "FlowersA", 0.9, 16, { 0.9, 1.2 }, 0.02 },
	{ "FlowersB", 0.9, 14, { 0.9, 1.2 }, 0.02 },
	{ "MossPatch", 1.8, 4, { 0.8, 1.1 }, 0.02 },
}

-- the climbable garden oak (v1's Oak_A): angle (degrees clockwise from north), radius from the Tor's centre, scale.
-- 250 / 70 puts its crown clear of the 225-degree pavilion, the west walkway, the banners and the overlook.
Lobby.OAK_ANGLE = 250
Lobby.OAK_R = 70
Lobby.OAK_SCALE = 0.9

local REPLACED = {
	Pavilion = true, PavilionBase = true, Banner = true, Brazier = true, CentralFire = true, Bench = true,
	NoticeBoard = true, LanternPost = true,
}

function Lobby.build(Ctx): string
	local L = Ctx.Layout
	local C = L.LobbyPosition
	local TOP = C.Y
	local PAVE = TOP + 2.75 -- the terrace paving (v1: WALK = TOP + 2.7, paving + 0.05)
	local FIELD = PAVE + 0.13 -- the inner field round the dais
	local lobby = Ctx.folder(workspace, "Lobby")
	local decor = Ctx.folder(lobby, "Decor")
	local rng = Random.new(Ctx.Seed + 911)
	local terrain = Ctx.terrainParams

	local function at(a: number, r: number, y: number?): Vector3
		local ar = rad(a)
		return V3(C.X + sin(ar) * r, y or TOP, C.Z - cos(ar) * r)
	end
	local function facingC(p: Vector3): CFrame
		return CFrame.lookAt(p, V3(C.X, p.Y, C.Z))
	end
	local function outward(p: Vector3): CFrame
		return CFrame.lookAt(p, p + V3(p.X - C.X, 0, p.Z - C.Z))
	end
	local function ground(x: number, z: number): number
		local hit = workspace:Raycast(V3(x, TOP + 60, z), V3(0, -120, 0), terrain)
		if hit and math.abs(hit.Position.Y - TOP) < 8 then
			return hit.Position.Y
		end
		return TOP
	end

	-- 1. archive the v1 pieces the realistic set replaces (first run only), keeping the notice text
	local archived = 0
	local noticeGui: SurfaceGui? = nil
	local baseLook = nil
	for _, ch in ipairs(decor:GetChildren()) do
		if REPLACED[ch.Name] then
			if ch.Name == "NoticeBoard" and not noticeGui then
				local g = ch:FindFirstChild("Notice", true)
				if g and g:IsA("SurfaceGui") then
					noticeGui = g:Clone()
				end
			end
			if ch.Name == "PavilionBase" and ch:IsA("BasePart") and not baseLook then
				baseLook = { color = ch.Color, material = ch.Material }
			end
			Ctx.archive(ch, "Lobby_v1", "Decor")
			archived += 1
		end
	end
	local oldGarden = lobby:FindFirstChild("Garden")
	if oldGarden and not oldGarden:GetAttribute("Realistic") then
		Ctx.archive(oldGarden, "Lobby_v1")
		archived += 1
	end
	local barrier = Ctx.folder(lobby, "Barrier")
	local oldRail = lobby:FindFirstChild("Railing")
	if oldRail and not oldRail:GetAttribute("Realistic") then
		for _, p in ipairs(oldRail:GetChildren()) do
			if p.Name == "Barrier" then
				p.Parent = barrier
			end
		end
		Ctx.archive(oldRail, "Lobby_v1")
		archived += 1
	end
	local marks = lobby:FindFirstChild("Landmarks")
	if marks and not noticeGui then
		local g = marks:FindFirstChild("Notice", true)
		if g and g:IsA("SurfaceGui") then
			noticeGui = g:Clone()
		end
	end
	if not noticeGui then
		local wa = ServerStorage:FindFirstChild("WorldAssets")
		local t = wa and wa:FindFirstChild("NoticeBoard", true)
		local g = t and t:FindFirstChild("Notice", true)
		if g and g:IsA("SurfaceGui") then
			noticeGui = g:Clone()
		end
	end

	-- 2. rebuild what this step owns
	marks = Ctx.folder(lobby, "Landmarks")
	Ctx.clear(marks)
	local garden = Ctx.folder(lobby, "Garden")
	garden:SetAttribute("Realistic", true)
	Ctx.clear(garden)
	local rail = Ctx.folder(lobby, "Railing")
	rail:SetAttribute("Realistic", true)
	Ctx.clear(rail)
	local count = {}
	local function put(name: string, cf: CFrame, parent: Instance?, opts: any?): Model?
		local o = opts or {}
		o.keep = true
		o.keepTouch = true
		local m = Ctx.spawn(name, cf, parent or marks, o)
		if m then
			count[name] = (count[name] or 0) + 1
		end
		return m
	end
	local function lights(m: Instance?, shadows: boolean, brightness: number?, range: number?)
		if not m then
			return
		end
		for _, l in ipairs(m:GetDescendants()) do
			if l:IsA("Light") then
				l.Shadows = shadows
				if brightness then
					l.Brightness = brightness
				end
				if range then
					l.Range = range
				end
			end
		end
	end

	-- flames, embers and smoke (v1's three emitters, scaled by k to the bowl) on the Ember part, so a fire reads as
	-- burning from eye level, not only as a glow below the rim
	local fires = 0
	local function fireFx(m: Model?, k: number)
		if not m then
			return
		end
		local host: Instance? = nil
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and string.find(d.Name, "Ember", 1, true) then
				host = d
			end
		end
		local att = m:FindFirstChild("Fire", true)
		if not host and not (att and att:IsA("Attachment")) then
			return
		end
		local fx = Instance.new("Attachment")
		fx.Name = "FireFx"
		if host then
			-- at the coals' top, so most of each flame clears the bowl's rim
			fx.Position = V3(0, (host :: BasePart).Size.Y * 0.5 + 0.25 * k, 0)
			fx.Parent = host
		else
			fx.CFrame = (att :: Attachment).CFrame
			fx.Parent = (att :: Attachment).Parent
		end
		local function ns(list)
			local kp = {}
			for _, p in ipairs(list) do
				table.insert(kp, NumberSequenceKeypoint.new(p[1], p[2]))
			end
			return NumberSequence.new(kp)
		end
		local flame = Instance.new("ParticleEmitter")
		flame.Name = "Flame"
		flame.Texture = "rbxasset://textures/particles/fire_main.dds"
		-- (v1's additive flame, LightEmission 1, all but vanished against a daylight sky: half-additive and brighter reads
		-- at noon and still glows at night)
		flame.Rate = 40
		flame.Lifetime = NumberRange.new(0.45, 0.85)
		flame.Speed = NumberRange.new(2.6 * k, 4.4 * k)
		flame.SpreadAngle = Vector2.new(14, 14)
		flame.Acceleration = V3(0, 2.4 * k, 0)
		flame.LightEmission = 0.4
		flame.LightInfluence = 0
		flame.Brightness = 2.2
		flame.Rotation = NumberRange.new(-25, 25)
		flame.RotSpeed = NumberRange.new(-50, 50)
		flame.Size = ns({ { 0, 1.8 * k }, { 0.5, 1.3 * k }, { 1, 0.2 * k } })
		flame.Transparency = ns({ { 0, 0.2 }, { 0.7, 0.5 }, { 1, 1 } })
		flame.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 205, 120)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(250, 128, 52)), ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 52, 28)) })
		flame.EmissionDirection = Enum.NormalId.Top
		flame.Parent = fx
		local embers = Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Texture = "rbxasset://textures/particles/fire_sparks_main.dds"
		embers.Rate = 5
		embers.Lifetime = NumberRange.new(1, 2.2)
		embers.Speed = NumberRange.new(2.85 * k, 6.65 * k)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.Acceleration = V3(0.6 * k, 2 * k, 0)
		embers.Drag = 0.6
		embers.LightEmission = 1
		embers.LightInfluence = 0
		embers.Size = ns({ { 0, 0.18 * k }, { 1, 0.05 * k } })
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(255, 90, 40))
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Parent = fx
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Rate = 1.5
		smoke.Lifetime = NumberRange.new(3.5, 6)
		smoke.Speed = NumberRange.new(2.4 * k, 3.8 * k)
		smoke.SpreadAngle = Vector2.new(8, 8)
		smoke.Acceleration = V3(0.8 * k, 0.6 * k, 0.3 * k)
		smoke.LightEmission = 0
		smoke.LightInfluence = 0.6
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-15, 15)
		smoke.Size = ns({ { 0, 1.33 * k }, { 1, 5.7 * k } })
		smoke.Transparency = ns({ { 0, 0.75 }, { 0.3, 0.7 }, { 1, 1 } })
		smoke.Color = ColorSequence.new(Color3.fromRGB(96, 92, 88), Color3.fromRGB(150, 146, 140))
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = fx
		fires += 1
	end

	-- the central fire on the dais, and the bench ring
	local fire = put("Brazier", CFrame.new(C.X, FIELD + 2.0, C.Z), marks, { scale = 1.5, name = "CentralFire" })
	lights(fire, true, 1.6, 26)
	fireFx(fire, 2.2)
	for k = 0, 7 do
		put("Bench", facingC(at(22.5 + k * 45, 12.5, FIELD)))
	end
	-- the overlook benches (west, toward the arena)
	put("Bench", outward(at(262, 75, PAVE)))
	put("Bench", outward(at(278, 75, PAVE)))

	-- pavilions on a stone base at terrace level
	local deckTop = nil
	for k = 0, 3 do
		local a = 45 + k * 90
		local bottom, top = TOP - 1.6, PAVE - 0.05
		local base = Instance.new("Part")
		base.Name = "PavilionBase"
		base.Size = V3(25.6, top - bottom, 17.6)
		base.CFrame = facingC(at(a, 63, (top + bottom) / 2))
		base.Anchored = true
		base.CanTouch = false
		base.Material = if baseLook then baseLook.material else Enum.Material.Cobblestone
		base.Color = if baseLook then baseLook.color else Color3.fromRGB(98, 96, 92)
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.Parent = marks
		local pav = put("Pavilion", facingC(at(a, 63, top)))
		if pav then
			if not deckTop then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { pav }
				local p = pav:GetPivot().Position
				local hit = workspace:Raycast(p + V3(0, 4, 0), V3(0, -8, 0), params)
				deckTop = if hit then hit.Position.Y - p.Y else 0
			end
			pav:PivotTo(pav:GetPivot() - V3(0, deckTop :: number, 0))
			lights(pav, false, 1.0, 16)
		end
	end

	-- a gate at the head of each main walkway, flanked by braziers
	for _, a in ipairs({ 0, 90, 180, 270 }) do
		local gate = put("LobbyGate", outward(at(a, 47.2, PAVE - 0.05)))
		lights(gate, false, 1.0, 14)
		for _, s in ipairs({ -1, 1 }) do
			local b = put("Brazier", facingC(at(a + s * 12.6, 45.5, PAVE)))
			lights(b, false, 1.2, 16)
			fireFx(b, 1.5)
		end
	end

	-- banner poles on the garden ring
	for k = 0, 7 do
		local p = at(22.5 + k * 45, 51.5)
		put("BannerPole", facingC(V3(p.X, ground(p.X, p.Z) - 0.05, p.Z)))
	end

	-- the notice boards, with the v1 notice text on a face part at the board's surface
	local boards = 0
	for i, a in ipairs({ 45, 225 }) do
		local board = put("NoticeBoard", outward(at(a, 21, PAVE)), marks, { name = "NoticeBoard" })
		if board and noticeGui then
			local att = board:FindFirstChild("Board", true)
			local face = Instance.new("Part")
			face.Name = "NoticeFace"
			face.Size = V3(8.2, 4.9, 0.05)
			local cf = if att and att:IsA("Attachment") then att.WorldCFrame else board:GetPivot() * CFrame.new(0, 5.2, -0.15)
			face.CFrame = cf * CFrame.new(0, 0, -0.26) -- the board's planks are 0.4 in front of the pivot plane
			face.Anchored = true
			face.CanCollide = false
			face.CanQuery = false
			face.CanTouch = false
			face.CastShadow = false
			face.Transparency = 1
			face.Parent = board
			local g = (noticeGui :: SurfaceGui):Clone()
			g.Adornee = nil
			g.Face = Enum.NormalId.Front
			g.Parent = face
			boards += 1
		end
	end

	-- stone steps from the garden up to the courtyard (top step flush with the paving)
	for k = 0, 3 do
		put("StoneSteps", outward(at(11 + k * 90, 52.6, PAVE - 3.0)))
	end

	-- the railing ring (66 segments of 8.04 studs at r 84.5); the invisible barrier walls stay in Lobby.Barrier
	local N, R = 66, 84.5
	for k = 0, N - 1 do
		local p0, p1 = at(k * 360 / N, R), at((k + 1) * 360 / N, R)
		local y = math.min(ground(p0.X, p0.Z), ground(p1.X, p1.Z)) - 0.08
		local mid = V3((p0.X + p1.X) / 2, y, (p0.Z + p1.Z) / 2)
		put("Railing", CFrame.lookAt(mid, V3(C.X, y, C.Z)), rail)
	end
	Ctx.yield()

	-- the garden ring (grass level, r 51-81): realistic plants, clear of walkways, pavilions, banners, steps, overlook
	local reserved = {}
	local function reserve(p: Vector3, r: number)
		table.insert(reserved, { p.X, p.Z, r })
	end
	for k = 0, 3 do
		reserve(at(45 + k * 90, 63), 14.5)
		reserve(at(11 + k * 90, 53.5), 5.5)
	end
	for k = 0, 7 do
		reserve(at(22.5 + k * 45, 51.5), 3)
	end
	reserve(at(270, 76), 10)
	-- the climbable oak (v1's garden Oak_A was the Tor's only climbable tree): a realistic OakA, OakA_Bark tagged
	-- Climbable, queryable and colliding, before the small plants so they keep off its trunk
	local oak = nil
	do
		local p = at(Lobby.OAK_ANGLE, Lobby.OAK_R)
		local y = ground(p.X, p.Z)
		oak = put("OakA", CFrame.new(p.X, y - 0.3, p.Z) * CFrame.Angles(0, rad(rng:NextNumber(0, 360)), 0), garden, { scale = Lobby.OAK_SCALE })
		if oak then
			reserve(p, 4.5)
		end
	end
	local function free(p: Vector3, r: number): boolean
		local dx, dz = p.X - C.X, p.Z - C.Z
		local rr = sqrt(dx * dx + dz * dz)
		if rr < 51 + r or rr > 81 - r then
			return false
		end
		local ang = math.deg(math.atan2(dx, -dz)) % 360
		for _, a in ipairs({ 0, 90, 180, 270 }) do
			if math.rad(math.abs(((ang - a + 180) % 360) - 180)) * rr < 4.5 + r then
				return false
			end
		end
		for _, a in ipairs({ 45, 135, 225, 315 }) do
			if rr < 58.5 and math.rad(math.abs(((ang - a + 180) % 360) - 180)) * rr < 3.8 + r then
				return false
			end
		end
		for _, o in ipairs(reserved) do
			local ex, ez = p.X - o[1], p.Z - o[2]
			if ex * ex + ez * ez < (o[3] + r) ^ 2 then
				return false
			end
		end
		return true
	end
	local planted = 0
	for _, spec in ipairs(PLANTS) do
		local want, tries = spec[3], 0
		while want > 0 and tries < spec[3] * 60 do
			tries += 1
			local p = at(rng:NextNumber(0, 360), rng:NextNumber(52, 80))
			local s = rng:NextNumber(spec[4][1], spec[4][2])
			local r = spec[2] * s
			if free(p, r) then
				local y = ground(p.X, p.Z)
				local m = Ctx.spawn(spec[1], CFrame.new(p.X, y - spec[5], p.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), garden, { scale = s })
				if m then
					reserve(p, r)
					planted += 1
				end
				want -= 1
			end
		end
		Ctx.yield()
	end

	local parts = {}
	for name, n in pairs(count) do
		table.insert(parts, name .. " " .. n)
	end
	table.sort(parts)
	local climbable = 0
	if oak then
		for _, d in ipairs(oak:GetDescendants()) do
			if d:IsA("BasePart") and d:HasTag("Climbable") and d.CanCollide and d.CanQuery then
				climbable += 1
			end
		end
	end
	return string.format("the Tor: %s; %d garden plants; notice text on %d boards; %d fires burning; climbable oak %s; %d v1 groups archived; spawns kept: %d",
		table.concat(parts, ", "), planted, boards, fires, if climbable > 0 then "yes" else "NO", archived, #(lobby:FindFirstChild("Spawns") or lobby):GetChildren())
end

return Lobby
