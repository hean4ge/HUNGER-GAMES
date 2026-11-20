--[[
	TrainingService - the Training Centre's stations (docs/design/TrainingAndLoadup.md sections 3.2, 3.3 and 3.5).
	Shared.TrainingStations holds every number and place; TrainingController (client) draws the guidance and runs the
	two timing drills (bike, weights).

	THE HALL
	  The hall is workspace.TrainingCentre when that set exists (its pivot is the floor's centre; its empties move the
	  stations: see TrainingStations), else a stand-in shell built here at TrainingStations.HallOrigin
	  (place (8800, 200, 3000)): floor, low teal walls, no roof. The stations' working props are always built here,
	  in workspace.TrainingStations: orange mats, chests, lanes and pop-up targets, boards, the ring and its four
	  dummies, the survival corner, the climbing wall, bikes, the bench, the track's gates and the obstacle run.
	  Nothing here runs per frame while nobody is in the hall (the player scan is 6 times a second).

	PLAYER ATTRIBUTES (set here)
	  InTraining (boolean)          the character stands in the hall. CombatService and PlayerService should refuse any
	                                damage to such a player and accept hits on TrainingDummy bodies from them (needs).
	  TrainingBay (string | nil)    the station whose bay they stand in
	  TrainingCooldownScale (0.25)  while InTraining: SkillService multiplies cooldowns by it (needs)
	  TrainingTokens, TrainedStamina, TrainedStrength, TrainedFieldcraft (numbers, this session; DataService keys later)

	BORROWED ITEMS (attribute on nothing; kept here)
	  A chest (hold E 0.6 s) lends its station's TrainingStations.chestItems through InventoryService.give and records
	  exactly what it gave. They go back (InventoryService.take, never more than was lent) when the player leaves that
	  station's bay, leaves the hall (the launch doors are in its north wall), or at the call (Phase "Countdown").
	  InventoryService.give answers 0 outside a round for anyone who is not an alive contender, so lending in the hall
	  needs InventoryService to accept InTraining players (needs).

	THE DUMMIES (section 3.3): ServerStorage.Dev.TrainingDummy clones, tagged TrainingDummy, in this folder (never in
	  CombatService's practice folder). Target: wobbles, heals after 4 s. Blocker: lifts its arm 0.3 s early, then
	  guards 1.5 s in every 3 (no parry). Parrier: when a player near it starts a swing (MeleeSwing "Start"), it guards
	  at once 40% of the time with a fresh GuardAt, so CombatService's parry window catches the blow. Striker: a slow
	  overhead every 4 s (0.9 s tell, then CombatService._npcStrike "H") at the nearest player in front within 7 studs;
	  a hit staggers and takes no health (any health it did take, in a practice round, is healed back at once).

	DRILLS (one at a time per player; results go to the client as one quiet line)
	  archery  a lane's orange line: 6 pop-up targets at 20/40/60, 4 s each, 1 s apart; 4 hits pass; the centre counts double
	  throwing the orange line: 5 throws (counted from RangedRelease "Throw"), 3 hits on boards at 20 or more pass
	  blades   the ring's centre pad: 25 s, 8 clean hits on the blocker and parrier and 2 guarded striker blows
	  survival light the fire (hold E 2 s), fill a bottle at the trough, keep the 3 sound plants (none spoiled),
	           bandage the dummy, all in 45 s from the first
	  wall     from the climber's mat to the top in under 8 s     bike   20 s in the green (client gauge)
	  weights  10 clean lifts on the beat (client)                lap    the four gates in under 19 s
	  run      vault, mantle, slide, pad to pad in under 12 s
	  A pass pays 1 token (TokensPerDay a day) and 1 more the first time, and adds 1 to the attribute it trains.

	REMOTE ReplicatedStorage.Remotes.Training (created here at start; not in Net.Names, like PlusSubscribe)
	  server -> client  { t = "drill", id, station, name, state = "run" | "done", score, total, need, points?, endsAt?,
	                      passed?, text?, token? }  { t = "line", text, sub? }  { t = "weights", total, period, start }
	  client -> server  { t = "bike", green, seat }  { t = "weights", clean, beats }

	API
	  TrainingService.isTraining(player) -> boolean
	  TrainingService.hallCFrame() -> CFrame
	  TrainingService.reclaim(player, reason?)         borrowed items back now
	  TrainingService.reclaimAll(reason?)
	  TrainingService.passed: Signal(player, drillId)
	  TrainingService._state(player), _build(), _dummies() test hooks
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Kits = require(Shared:WaitForChild("Kits"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local StationSign = require(Shared:WaitForChild("StationSign"))
local TS = require(Shared:WaitForChild("TrainingStations"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local REMOTE_NAME = "Training"
local DUMMY_TAG = "TrainingDummy"
local FOLDER_NAME = "TrainingStations"
local SCAN = 1 / 6 -- seconds between player scans
local C = TS.Colors

local TrainingService = {}
TrainingService.passed = Signal.new()

local Services: { [string]: any } = {}
local remote: RemoteEvent? = nil
local folder: Folder? = nil
local hallCF = TS.HallOrigin
local rng = Random.new()

type Drill = { id: string, station: string, name: string, startedAt: number, endsAt: number, score: number,
	total: number, need: number, points: number?, extra: { [string]: any } }
local states: { [Player]: { [string]: any } } = {}

-- the built world, by station
local lanes: { { start: BasePart, targets: { { model: Model, distance: number, up: boolean } }, owner: Player? } } = {}
local boards: { { model: Model, distance: number } } = {}
local dummies: { { model: Model, stance: string, data: { [string]: any } } } = {}
local mats: { { part: BasePart, station: string, kit: string?, specialty: string? } } = {}
local pads: { [string]: BasePart } = {}
local survival: { fire: BasePart?, flame: ParticleEmitter?, plants: { { part: BasePart, sound: boolean } } } = { plants = {} }
local bikes: { Seat } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function call(service: string, fn: string, ...: any): any
	local s = Services[service]
	if s and type(s[fn]) == "function" then
		local ok, result = pcall(s[fn], ...)
		if ok then
			return result
		end
		warn(string.format("[TrainingService] %s.%s failed: %s", service, fn, tostring(result)))
	end
	return nil
end

local function send(player: Player, payload: { [string]: any })
	if remote and player.Parent == Players then
		(remote :: RemoteEvent):FireClient(player, payload)
	end
end

local function line(player: Player, text: string, sub: string?)
	send(player, { t = "line", text = text, sub = sub })
end

local function stateFor(player: Player): { [string]: any }
	local st = states[player]
	if not st then
		st = { lent = {}, lentStation = nil, bay = nil, inHall = false, drill = nil, mat = nil, passedEver = {},
			tokensToday = 0, survival = nil, wall = nil, lap = nil, run = nil, bike = nil, weights = nil }
		states[player] = st
	end
	return st
end

--------------------------------------------------------------------------------------------------------------------
-- Places
--------------------------------------------------------------------------------------------------------------------

local overrides: { [string]: CFrame } = {} -- "Station_<id>" and "TS_<id>.<spot>" empties of the set, as world CFrames
-- The Blender set (TrainingCentreBuilder, attribute BlenderSet): TrainingStations' numbers follow its layout, so the
-- working props stand where its art is. Its art is the look: the props' own shapes that it already draws (stands,
-- chests, the ring, the fire pit, the wall, bikes, the rack, the obstacles) are built invisible (prompts, seats and pads
-- kept), and its burlap dummies lend their look to the working dummies. Its "Station_<Name>" markers are not ours.
local blender = false
local blenderSet: Instance? = nil

local function readSet()
	table.clear(overrides)
	local set = workspace:FindFirstChild("TrainingCentre")
	if not (set and set:IsA("Model")) then
		hallCF = TS.HallOrigin
		blender, blenderSet = false, nil
		return false
	end
	hallCF = set:GetPivot()
	blender = set:GetAttribute("BlenderSet") == true
	blenderSet = if blender then set else nil
	if blender then
		return true
	end
	for _, inst in ipairs(set:GetDescendants()) do
		local cf: CFrame? = nil
		if inst:IsA("Attachment") then
			cf = inst.WorldCFrame
		elseif inst:IsA("BasePart") then
			cf = inst.CFrame
		end
		if cf then
			local station = inst:GetAttribute("TrainingStation")
			local spot = inst:GetAttribute("TrainingSpot")
			if type(station) == "string" then
				overrides["Station_" .. station] = cf
			elseif string.sub(inst.Name, 1, 8) == "Station_" then
				overrides[string.lower(inst.Name)] = cf
			end
			if type(spot) == "string" then
				overrides["TS_" .. spot] = cf
			elseif string.sub(inst.Name, 1, 3) == "TS_" then
				overrides[inst.Name] = cf
			end
		end
	end
	return true
end

-- The world CFrame of a station's origin.
local function stationCF(station: any): CFrame
	local o = overrides["Station_" .. station.id] or overrides["station_" .. station.id]
	if o then
		return o
	end
	return hallCF * CFrame.new(station.origin)
end

-- The world CFrame of a station's spot (its floor point, turned by the spot's yaw), or at `offset` from the origin.
local function spotCF(station: any, name: string?, offset: Vector3?, yaw: number?): CFrame
	if name then
		local o = overrides["TS_" .. station.id .. "." .. name]
		if o then
			return o
		end
		local spot = station.spots[name]
		if spot then
			return stationCF(station) * CFrame.new(spot.pos) * CFrame.Angles(0, math.rad(spot.yaw or 0), 0)
		end
	end
	return stationCF(station) * CFrame.new(offset or Vector3.zero) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

local function toHall(position: Vector3): Vector3
	return hallCF:PointToObjectSpace(position)
end

--------------------------------------------------------------------------------------------------------------------
-- Building (Parts: the stand-in look until the Blender set lands)
--------------------------------------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	if props then
		for k, val in pairs(props) do
			(p :: any)[k] = val
		end
	end
	p.Parent = parent
	return p
end

-- With the Blender set: a prop shape its art already draws stays as an invisible holder (prompt, seat, pad) or goes.
local function artDraws(p: BasePart, keepCollide: boolean?): BasePart
	if blender then
		p.Transparency = 1
		p.CastShadow = false
		if not keepCollide then
			p.CanCollide = false
			p.CanQuery = false
		end
	end
	return p
end

local function floorLabel(p: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = Color3.fromRGB(32, 24, 18)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.12, 0)
	pad.PaddingRight = UDim.new(0.12, 0)
	pad.PaddingTop = UDim.new(0.3, 0)
	pad.PaddingBottom = UDim.new(0.3, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = p
end

local function prompt(parent: Instance, action: string, hold: number, lineText: string, range: number?): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "TrainingPrompt"
	pr.ActionText = action
	pr.HoldDuration = hold
	pr.MaxActivationDistance = range or 8
	pr.RequiresLineOfSight = false
	pr.Style = Enum.ProximityPromptStyle.Custom -- HUDController draws Custom prompts in the arena; TrainingController in the hall
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.GamepadKeyCode = Enum.KeyCode.ButtonX
	pr.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pr:SetAttribute("PromptLine", lineText)
	CollectionService:AddTag(pr, "TrainingPrompt")
	pr.Parent = parent
	return pr
end

-- A target: a Model with its own Humanoid (so CombatService.characterFromPart and the arrow and throw code treat it as a
-- body) and a nested "Bull" Model with another: a hit on the centre is told apart by which Humanoid lost health.
local function makeTarget(parent: Instance, name: string, cf: CFrame, diameter: number, square: boolean): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = part(model, "HumanoidRootPart", Vector3.new(0.4, 0.4, 0.4), cf, C.Board,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local faceCF = cf * CFrame.Angles(0, math.rad(90), 0) -- a cylinder's round faces look along its X axis
	if square then
		part(model, "Board", Vector3.new(0.5, diameter, diameter), faceCF, C.Board, { CanCollide = true })
	else
		part(model, "Board", Vector3.new(0.5, diameter, diameter), faceCF, C.Board, { Shape = Enum.PartType.Cylinder, CanCollide = true })
	end
	part(model, "Ring", Vector3.new(0.52, diameter * 0.62, diameter * 0.62), faceCF, Color3.fromRGB(70, 74, 78),
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })
	part(model, "RingInner", Vector3.new(0.54, diameter * 0.46, diameter * 0.46), faceCF, C.Board,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = 10000
	humanoid.Health = 10000
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model.PrimaryPart = root

	local bull = Instance.new("Model")
	bull.Name = "Bull"
	local broot = part(bull, "HumanoidRootPart", Vector3.new(0.3, 0.3, 0.3), cf, C.Ring,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	-- (thicker than the board, so a shot at the centre meets it first)
	part(bull, "Head", Vector3.new(1.4, diameter * 0.26, diameter * 0.26), faceCF, C.Ring,
		{ Shape = Enum.PartType.Cylinder, CanCollide = true })
	local bh = humanoid:Clone()
	bh.Parent = bull
	bull.PrimaryPart = broot
	bull.Parent = model
	CollectionService:AddTag(model, DUMMY_TAG)
	model.Parent = parent
	return model
end

local function setTargetUp(model: Model, up: boolean)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
			-- (wave 27 bug hunt) with the Blender set its own targets always stand there: a "down" ghost at 0.82 hung
			-- 1.4 studs in front of each one, 18 doubled, see-through targets down the lanes. With the set, down = gone.
			inst.Transparency = if up then 0 elseif blender then 1 else 0.82
			if inst.Name == "Board" or inst.Name == "Head" then
				inst.CanQuery = up
				inst.CanCollide = up
			end
		end
	end
	model:SetAttribute("Up", up)
end

local function buildShell(root: Instance)
	local shell = Instance.new("Model")
	shell.Name = "TrainingStandIn"
	local h = TS.HallSize
	-- a chequered floor of 22-stud squares in the hall's two tones
	local tile = 22
	local nx, nz = math.ceil(h.X / tile), math.ceil(h.Z / tile)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = -h.X / 2 + tile * (ix + 0.5)
			local z = -h.Z / 2 + tile * (iz + 0.5)
			local sx = math.min(tile, h.X / 2 - (x - tile / 2))
			local sz = math.min(tile, h.Z / 2 - (z - tile / 2))
			local cx = x - tile / 2 + sx / 2
			local cz = z - tile / 2 + sz / 2
			part(shell, "Floor", Vector3.new(sx, 2, sz), hallCF * CFrame.new(cx, -1, cz),
				if (ix + iz) % 2 == 0 then C.Floor else C.FloorLight, { Material = Enum.Material.Fabric })
		end
	end
	local wallH = 14
	local function wall(name: string, size: Vector3, pos: Vector3)
		part(shell, name, size, hallCF * CFrame.new(pos), C.Teal, { Material = Enum.Material.Fabric, CastShadow = true })
	end
	-- north wall with the launch doors' gap (x -6..6), south wall with three arches' gaps, east and west whole
	wall("WallN_W", Vector3.new(h.X / 2 - 6, wallH, 2), Vector3.new(-(h.X / 2 + 6) / 2, wallH / 2, -h.Z / 2 - 1))
	wall("WallN_E", Vector3.new(h.X / 2 - 6, wallH, 2), Vector3.new((h.X / 2 + 6) / 2, wallH / 2, -h.Z / 2 - 1))
	for i, seg in ipairs({ { -110, -24 }, { -12, 12 }, { 24, 110 } }) do
		local w = seg[2] - seg[1]
		wall("WallS_" .. i, Vector3.new(w, wallH, 2), Vector3.new((seg[1] + seg[2]) / 2, wallH / 2, h.Z / 2 + 1))
	end
	wall("WallE", Vector3.new(2, wallH, h.Z + 4), Vector3.new(h.X / 2 + 1, wallH / 2, 0))
	wall("WallW", Vector3.new(2, wallH, h.Z + 4), Vector3.new(-h.X / 2 - 1, wallH / 2, 0))
	-- the launch doors (closed: the red room is the launch's work) and the arrival platform's edge
	part(shell, "LaunchDoors", Vector3.new(12, wallH, 1), hallCF * CFrame.new(0, wallH / 2, -h.Z / 2 - 1),
		Color3.fromRGB(96, 34, 34), { Material = Enum.Material.Metal })
	part(shell, "PlatformB", Vector3.new(h.X, 2, 14), hallCF * CFrame.new(0, -1, h.Z / 2 + 9), Color3.fromRGB(58, 60, 62),
		{ Material = Enum.Material.Concrete })
	shell:SetAttribute("StandIn", true)
	shell.Parent = root
end

-- which way a mat's sign faces, in the mat's frame (hall frame: x east, z north negative)
local FACE_DIRS = {
	n = Vector3.new(0, 0, -1), s = Vector3.new(0, 0, 1), e = Vector3.new(1, 0, 0), w = Vector3.new(-1, 0, 0),
}

local function buildMat(model: Instance, station: any, spec: any)
	local spot = station.spots[spec.spot]
	local size = spot.size or Vector3.new(6, 0.2, 6)
	local cf = spotCF(station, spec.spot) * CFrame.new(0, size.Y / 2 + 0.02, 0)
	local p = part(model, "Mat_" .. spec.spot, size, cf, C.Use, { CanCollide = false, CanQuery = false, CanTouch = false,
		Material = Enum.Material.Fabric })
	local words = if spec.kit then string.upper((Kits.get(spec.kit) or { name = spec.kit }).name)
		else string.upper(spec.specialty == "ShortBlade" and "Short blade" or spec.specialty)
	-- the name stands on a small sign beside the mat (20 Nov: the owner asked for standing signs, not words lying on
	-- the floor). TrainingStations' mats carry where: sign = { at = mat-local floor offset, face = "n"|"s"|"e"|"w" }.
	local okSign, err = pcall(function()
		-- default: the board looks toward the hall's middle (the way people come from) and stands on the mat's far side,
		-- so it is read across the mat and never stands in the way onto it
		local s = spec.sign or {}
		local toMid = cf:VectorToObjectSpace(hallCF.Position - cf.Position)
		local faceKey = s.face or (if math.abs(toMid.X) >= math.abs(toMid.Z)
			then (if toMid.X >= 0 then "e" else "w") else (if toMid.Z >= 0 then "s" else "n"))
		local dir = FACE_DIRS[faceKey] or FACE_DIRS.e
		local at = s.at or Vector3.new(-dir.X * (size.X / 2 + 0.9), 0, -dir.Z * (size.Z / 2 + 0.9))
		local base = cf * CFrame.new(at.X, -size.Y / 2 - 0.02, at.Z)
		local look = base:VectorToWorldSpace(dir)
		StationSign.make({
			Name = "Sign_" .. spec.spot,
			CFrame = CFrame.lookAt(base.Position, base.Position + look),
			Title = words,
			Caption = if spec.kit then "Kit · stand on the mat" else "Specialty · stand on the mat",
			Icon = spec.kit or s.icon,
			Width = s.width,
			Parent = model,
		})
	end)
	if not okSign then
		warn("[TrainingService] sign for " .. tostring(spec.spot) .. " failed: " .. tostring(err))
		floorLabel(p, words)
	end
	if spec.kit then
		artDraws(p) -- the set's orange kit mats (the blade circle's Specialty mats are ours alone)
	end
	table.insert(mats, { part = p, station = station.id, kit = spec.kit, specialty = spec.specialty })
end

local onChest: (player: Player, stationId: string) -> ()
local chestParts: { [string]: BasePart } = {} -- station id -> its chest's box (the prompt's reach, onChest)

local function buildChest(model: Instance, station: any)
	if not station.chest or not station.spots.chest then
		return
	end
	local cf = spotCF(station, "chest")
	local box = artDraws(part(model, "Chest", Vector3.new(4, 2.2, 2.6), cf * CFrame.new(0, 1.1, 0), C.Steel,
		{ Material = Enum.Material.Metal }))
	artDraws(part(model, "ChestLid", Vector3.new(4.1, 0.5, 2.7), cf * CFrame.new(0, 2.45, 0), C.Use))
	artDraws(part(model, "ChestTrim", Vector3.new(4.12, 0.3, 2.72), cf * CFrame.new(0, 0.4, 0), C.Use))
	local names = {}
	for _, item in ipairs(TS.chestItems(station.id)) do
		local def = ItemDefs.get(item.id)
		local n = if def then def.name else item.id
		table.insert(names, if item.count > 1 then string.format("%s \u{00D7}%d", n, item.count) else n)
	end
	-- The prompt sits on an anchor 3.4 above the floor, not in the low box: Roblox shows a prompt only while its point
	-- is on screen, and in first person a chest's centre (1.1 up) drops out of view 4 studs away, just where a player
	-- stops to press E (wave 15: two real presses at 3.4 to 3.9 studs lent nothing, the prompt had hidden). One press,
	-- no hold, from up to 9 studs (onChest also lends to a player just over the bay's edge, at the fitness chest).
	chestParts[station.id] = box
	local anchor = Instance.new("Attachment")
	anchor.Name = "PromptAnchor"
	anchor.Position = Vector3.new(0, 2.3, 0)
	anchor.Parent = box
	local pr = prompt(anchor, "Borrow", 0, station.chestLine or ("Borrow " .. table.concat(names, ", ")), 9)
	pr.Triggered:Connect(function(player)
		onChest(player, station.id)
	end)
end

local function dummyTemplate(): Model?
	local dev = ServerStorage:FindFirstChild("Dev")
	local template = dev and dev:FindFirstChild("TrainingDummy")
	if template and template:IsA("Model") then
		return template
	end
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local builder = worldGen and worldGen:FindFirstChild("DummyBuilder")
	if builder and builder:IsA("ModuleScript") then
		local ok, result = pcall(function()
			return require(builder :: ModuleScript).create()
		end)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			return result
		end
	end
	return nil
end

local function motorOf(model: Model, partName: string, motorName: string): Motor6D?
	local p = model:FindFirstChild(partName)
	local m = p and p:FindFirstChild(motorName)
	return if m and m:IsA("Motor6D") then m else nil
end

local onDummyDamaged: (entry: any, amount: number) -> ()

local function spawnDummy(parent: Instance, cf: CFrame, stance: string, label: string, tagged: boolean): { [string]: any }?
	local template = dummyTemplate()
	if not template then
		warn("[TrainingService] no training dummy template (ServerStorage.Dev.TrainingDummy)")
		return nil
	end
	local model = template:Clone()
	model.Name = "Training" .. stance
	model:PivotTo(cf)
	model:SetAttribute("TrainingStance", stance)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		model:Destroy()
		return nil
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = 400
	humanoid.Health = 400
	local head = model:FindFirstChild("Head")
	local bar = head and head:FindFirstChild("HealthBar")
	if bar and bar:IsA("BillboardGui") then
		bar.Size = UDim2.fromOffset(132, 26)
		-- (wave 27 bug hunt) a fixed 132 px name at any distance up to DummyBuilder's 80: from across the hall the four
		-- blade-circle names (dummies 11 studs apart) piled into one another ("Parrier Striker Blocker Target").
		-- Within 34 studs 11 studs is wider than 132 px on a 750 px-tall screen, so they never touch.
		bar.MaxDistance = 34
		local nameLabel = bar:FindFirstChild("Name", true) or bar:FindFirstChildWhichIsA("TextLabel", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = string.upper(label)
		end
	end
	local entry = {
		model = model, stance = stance, humanoid = humanoid,
		data = { lastHit = 0, wobble = 0, wobbleTime = 0, axis = Vector3.xAxis, last = humanoid.Health, next = 0,
			phase = "rest", phaseAt = 0, waist = motorOf(model, "UpperTorso", "Waist"),
			shoulder = motorOf(model, "RightUpperArm", "RightShoulder"), lshoulder = motorOf(model, "LeftUpperArm", "LeftShoulder") },
	}
	-- the set's burlap dummy at this spot lends its look (colour and material per R15 limb) and steps aside: its
	-- limbs and body collider go, its steel stand stays under this one
	local setDummies = blenderSet and blenderSet:FindFirstChild("Dummies")
	local art = setDummies and setDummies:FindFirstChild(if stance == "Patient" then "BandageDummy" else "Dummy_" .. stance)
	if art then
		local looks = {}
		for _, p in ipairs(art:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "Stand" and p.Name ~= "TC_Dummy_Stand_Col" and p.Name ~= "RootMarker" then
				if not looks[p.Name] then
					looks[p.Name] = { p.Color, p.Material }
				end
				p:Destroy()
			end
		end
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				local look = looks[p.Name]
				if look then
					p.Color, p.Material = look[1], look[2]
				elseif p.Parent == model then
					p.Transparency = 1 -- the old dummy's trims (belt, tie, eyes, chest target): not on the burlap one
					p.CanQuery = false
				end
			end
			if p:IsA("Decal") then
				p.Transparency = 1
			end
		end
	end
	local d = entry.data
	d.waistC0 = d.waist and d.waist.C0
	d.shoulderC0 = d.shoulder and d.shoulder.C0
	d.lshoulderC0 = d.lshoulder and d.lshoulder.C0
	humanoid.HealthChanged:Connect(function(health)
		local lost = d.last - health
		d.last = health
		if lost > 0.01 then
			onDummyDamaged(entry, lost)
		end
		if health < humanoid.MaxHealth * 0.35 then
			humanoid.Health = humanoid.MaxHealth -- a training dummy never breaks
			d.last = humanoid.MaxHealth
		end
	end)
	if tagged then
		CollectionService:AddTag(model, DUMMY_TAG)
	end
	model.Parent = parent
	return entry
end

local onPrompt: (player: Player, what: string, index: number?) -> ()

local function buildStation(root: Instance, station: any)
	local model = Instance.new("Model")
	model.Name = station.id
	for _, spec in ipairs(station.mats or {}) do
		buildMat(model, station, spec)
	end
	buildChest(model, station)
	local origin = stationCF(station)

	if station.id == "archery" then
		local width = station.laneWidth
		local first = -(station.lanes - 1) / 2 * width
		for i = 1, station.lanes do
			local x = first + (i - 1) * width
			local lane = { targets = {}, owner = nil }
			local start = part(model, "LaneStart" .. i, Vector3.new(width - 1, 0.2, 2.5), origin * CFrame.new(x, 0.12, 0), C.Use,
				{ CanCollide = false, CanQuery = false, CanTouch = false })
			lane.start = start
			if i < station.lanes then
				artDraws(part(model, "Divider" .. i, Vector3.new(0.3, 0.3, 64), origin * CFrame.new(x + width / 2, 0.15, -31), C.Line,
					{ CanCollide = false, CanQuery = false }))
			end
			for k, distance in ipairs(station.targetDistances) do
				local depth = (station.targetDepths and station.targetDepths[k]) or distance
				local base = origin * CFrame.new(x, 0, -depth)
				local height = station.targetHeight or 5.4
				artDraws(part(model, "Stand", Vector3.new(0.5, height - 2, 0.5), base * CFrame.new(-1.2, (height - 2) / 2, 0.4), C.Use,
					{ CanQuery = false }))
				artDraws(part(model, "Stand", Vector3.new(0.5, height - 2, 0.5), base * CFrame.new(1.2, (height - 2) / 2, 0.4), C.Use,
					{ CanQuery = false }))
				-- facing the shooting line (south, +z in hall space)
				local t = makeTarget(model, "Target" .. i .. "_" .. distance, base * CFrame.new(0, height, 0) * CFrame.Angles(0, math.pi, 0), 4.2, false)
				setTargetUp(t, false)
				table.insert(lane.targets, { model = t, distance = distance, up = false })
			end
			table.insert(lanes, lane)
		end
		artDraws(part(model, "Backstop", Vector3.new(station.lanes * width, 12, 1), origin * CFrame.new(0, 6, -(station.targetDepths and station.targetDepths[3] + 2 or 64)), C.Pad,
			{ Material = Enum.Material.Fabric }))
	elseif station.id == "throwing" then
		local start = part(model, "ThrowLine", station.spots.start.size, spotCF(station, "start") * CFrame.new(0, 0.12, 0), C.Use,
			{ CanCollide = false, CanQuery = false, CanTouch = false })
		pads.throwing = start
		for i, distance in ipairs(station.boardDistances) do
			local base = origin * CFrame.new(distance + (station.boardFront or 0), 0, (station.boardOffsets and station.boardOffsets[i]) or 0)
			artDraws(part(model, "Post", Vector3.new(0.6, 4, 0.6), base * CFrame.new(0.5, 2, 0), C.Wood, { CanQuery = false }))
			-- facing the throwing line (west, -x)
			local b = makeTarget(model, "Board" .. distance, base * CFrame.new(0, station.boardHeight or 5.5, 0) * CFrame.Angles(0, math.rad(90), 0), 4.6, true)
			b:SetAttribute("Distance", distance)
			table.insert(boards, { model = b, distance = distance })
		end
		artDraws(part(model, "Hay", Vector3.new(4, 6, 24), spotCF(station, "backstop") * CFrame.new(0, 3, 0), C.Hay, { Material = Enum.Material.Fabric }))
	elseif station.id == "blades" then
		artDraws(part(model, "Ring", Vector3.new(0.3, station.ringRadius * 2, station.ringRadius * 2),
			origin * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Pad,
			{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, Material = Enum.Material.Fabric }))
		local pad = part(model, "CentrePad", station.spots.start.size, origin * CFrame.new(0, 0.3, 0), C.Use,
			{ CanCollide = false, CanQuery = false, CanTouch = false })
		pads.blades = pad
		for _, spec in ipairs(station.dummies) do
			local a = math.rad(spec.angle)
			local offset = Vector3.new(math.sin(a), 0, math.cos(a)) * station.dummyRadius
			local at = (origin * CFrame.new(offset)).Position
			local cf = CFrame.lookAt(at, Vector3.new(origin.Position.X, at.Y, origin.Position.Z))
			local entry = spawnDummy(model, cf, spec.stance, spec.name, true)
			if entry then
				table.insert(dummies, entry)
			end
		end
	elseif station.id == "survival" then
		local fcf = spotCF(station, "fire")
		artDraws(part(model, "FirePit", Vector3.new(1, 5, 5), fcf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(78, 74, 70), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Slate }))
		local logs = artDraws(part(model, "Logs", Vector3.new(3.2, 0.7, 0.7), fcf * CFrame.new(0, 1.3, 0), C.Wood, { Material = Enum.Material.Wood }))
		artDraws(part(model, "Logs2", Vector3.new(3.2, 0.7, 0.7), fcf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, math.rad(90), 0), C.Wood,
			{ Material = Enum.Material.Wood }))
		-- the same soft flame as the arena's cook fire (Shared.CreatureLooks), not Roblox's cartoon Fire object
		local flame = Instance.new("ParticleEmitter")
		flame.Name = "Flame"
		flame.Texture = "rbxasset://textures/particles/fire_main.dds"
		flame.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 214, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 140, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 60, 24)),
		})
		flame.LightEmission = 0.85
		flame.LightInfluence = 0
		flame.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(0.4, 1.6),
			NumberSequenceKeypoint.new(1, 0.3),
		})
		flame.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		flame.Lifetime = NumberRange.new(0.5, 0.9)
		flame.Speed = NumberRange.new(2.4, 3.6)
		flame.SpreadAngle = Vector2.new(9, 9)
		flame.Rotation = NumberRange.new(-20, 20)
		flame.RotSpeed = NumberRange.new(-40, 40)
		flame.Acceleration = Vector3.new(0, 1.5, 0)
		flame.EmissionDirection = Enum.NormalId.Top
		flame.Rate = 22
		flame.Enabled = false
		flame.Parent = logs
		local light = Instance.new("PointLight")
		light.Name = "FireLight"
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Range = 14
		light.Brightness = 1.4
		light.Enabled = false
		light.Parent = logs
		survival.fire = logs
		survival.flame = flame
		prompt(logs, "Light", 2, "Light the fire", 9).Triggered:Connect(function(player)
			onPrompt(player, "fire")
		end)
		local tcf = spotCF(station, "trough")
		artDraws(part(model, "Trough", Vector3.new(8, 2.4, 3), tcf * CFrame.new(0, 1.2, 0), C.Wood, { Material = Enum.Material.Wood }))
		local water = artDraws(part(model, "TroughWater", Vector3.new(7.4, 0.2, 2.4), tcf * CFrame.new(0, 2.3, 0), Color3.fromRGB(70, 112, 124),
			{ CanCollide = false, Material = Enum.Material.Glass, Transparency = 0.25 }))
		prompt(water, "Fill", 1, "Fill a bottle", 8).Triggered:Connect(function(player)
			onPrompt(player, "water")
		end)
		local pcf = spotCF(station, "plants")
		artDraws(part(model, "PlantTable", Vector3.new(16, 3, 4), pcf * CFrame.new(0, 1.5, 0), C.Wood, { Material = Enum.Material.Wood }))
		local step = station.plantStep or 2.5
		for i, sound in ipairs(station.plants) do
			local x = -(#station.plants - 1) / 2 * step + (i - 1) * step
			artDraws(part(model, "Pot" .. i, Vector3.new(1.4, 1.2, 1.4), pcf * CFrame.new(x, 3.6, 0), Color3.fromRGB(150, 96, 66),
				{ Material = Enum.Material.Slate }))
			local leaf = part(model, "Plant" .. i, Vector3.new(1.8, 1.8, 1.8), pcf * CFrame.new(x, 5, 0),
				if sound then Color3.fromRGB(96, 132, 70) else Color3.fromRGB(122, 104, 66),
				{ Shape = Enum.PartType.Ball, Material = Enum.Material.Grass })
			if not sound then
				leaf.Size = Vector3.new(1.6, 1.1, 1.6) -- wilted: low and brown, never anything that looks poisonous
				leaf.CFrame = pcf * CFrame.new(x, 4.6, 0)
			end
			if blender then
				-- the set draws the six plants (Plant_1..6: green or dry); this is the prompt's holder over its pot
				leaf.Size = Vector3.new(1.4, 1.4, 1.4)
				leaf.CFrame = pcf * CFrame.new(x, 4.3, 0)
				artDraws(leaf)
			end
			table.insert(survival.plants, { part = leaf, sound = sound })
			local pr = prompt(leaf, "Keep", 0.4, "Keep this plant", 5)
			pr.MaxActivationDistance = 5
			pr.Triggered:Connect(function(player)
				onPrompt(player, "plant", i)
			end)
		end
		local patient = spawnDummy(model, spotCF(station, "patient"), "Patient", "Patient", false)
		if patient then
			local torso = patient.model:FindFirstChild("UpperTorso") or patient.model.PrimaryPart
			if torso then
				prompt(torso, "Bandage", 1.5, "Bandage the dummy", 8).Triggered:Connect(function(player)
					onPrompt(player, "bandage")
				end)
			end
		end
	elseif station.id == "fitness" then
		local w = station.spots.wall
		local wcf = spotCF(station, "wall")
		if not blender then -- (the set's wall: its collider is tagged Climbable, its holds are orange)
			local wall = part(model, "ClimbWall", w.size, wcf * CFrame.new(0, w.size.Y / 2, 0), C.Teal,
				{ Material = Enum.Material.Slate, CastShadow = true })
			CollectionService:AddTag(wall, "Climbable")
			for i = 1, 26 do
				local hz = rng:NextNumber(-w.size.Z / 2 + 1, w.size.Z / 2 - 1)
				local hy = rng:NextNumber(1.5, w.size.Y - 1)
				part(model, "Hold", Vector3.new(0.5, 0.7, 0.9), wcf * CFrame.new(w.size.X / 2 + 0.2, hy, hz), C.Use,
					{ CanCollide = false, CanQuery = false })
			end
		end
		local t = station.spots.wallTop
		part(model, "WallTop", t.size, spotCF(station, "wallTop") * CFrame.new(0, -t.size.Y / 2, 0), C.Steel,
			{ Material = Enum.Material.Metal })
		for i = 1, 4 do
			local name = "bike" .. i
			local bcf = spotCF(station, name)
			artDraws(part(model, "BikeFrame" .. i, Vector3.new(1, 2, 4.5), bcf * CFrame.new(0, 1, 0), C.Use, { Material = Enum.Material.Metal }))
			artDraws(part(model, "BikeBar" .. i, Vector3.new(2.6, 0.4, 0.4), bcf * CFrame.new(0, 3.4, -1.9), C.Steel))
			local seat = Instance.new("Seat")
			seat.Name = "BikeSeat" .. i
			seat.Size = Vector3.new(2, 0.6, 2)
			seat.CFrame = bcf * CFrame.new(0, station.bikeSeatHeight or 2.3, 0.8)
			if blender then
				seat.Transparency = 1
			end
			seat.Anchored = true
			seat.Color = C.Pad
			seat.Material = Enum.Material.Fabric
			seat.TopSurface = Enum.SurfaceType.Smooth
			seat:SetAttribute("TrainingBike", i)
			seat.Parent = model
			table.insert(bikes, seat)
		end
		local bcf = spotCF(station, "bench")
		artDraws(part(model, "Bench", Vector3.new(2.4, 1.8, 6), bcf * CFrame.new(0, 0.9, 0), C.Pad, { Material = Enum.Material.Fabric }))
		artDraws(part(model, "RackPost", Vector3.new(0.4, 5, 0.4), bcf * CFrame.new(-1.6, 2.5, -2.4), C.Steel))
		artDraws(part(model, "RackPost", Vector3.new(0.4, 5, 0.4), bcf * CFrame.new(1.6, 2.5, -2.4), C.Steel))
		local bar = artDraws(part(model, "Barbell", Vector3.new(6, 0.3, 0.3), bcf * CFrame.new(0, 4.4, -2.4), C.Steel, { Material = Enum.Material.Metal }))
		artDraws(part(model, "Plate", Vector3.new(0.4, 1.8, 1.8), bcf * CFrame.new(-2.6, 4.4, -2.4), C.Use, { Shape = Enum.PartType.Cylinder }))
		artDraws(part(model, "Plate", Vector3.new(0.4, 1.8, 1.8), bcf * CFrame.new(2.6, 4.4, -2.4), C.Use, { Shape = Enum.PartType.Cylinder }))
		prompt(bar, "Lift", 0, "Start 10 lifts", 8).Triggered:Connect(function(player)
			onPrompt(player, "weights")
		end)
	elseif station.id == "track" then
		local s = station.spots
		pads.lap = part(model, "LapLine", s.lapStart.size, spotCF(station, "lapStart") * CFrame.new(0, 0.12, 0), C.Use,
			{ CanCollide = false, CanQuery = false, CanTouch = false })
		for i, g in ipairs(station.gates) do
			for side = -1, 1, 2 do
				local along = if i % 2 == 1 then Vector3.new(0, 0, side * station.gateRadius) else Vector3.new(side * station.gateRadius, 0, 0)
				artDraws(part(model, "Gate" .. i, Vector3.new(0.6, 5, 0.6), origin * CFrame.new(g + along + Vector3.new(0, 2.5, 0)), C.Line,
					{ CanCollide = false, CanQuery = false }))
			end
		end
		pads.runStart = part(model, "RunStart", s.runStart.size, spotCF(station, "runStart") * CFrame.new(0, 0.12, 0), C.Use,
			{ CanCollide = false, CanQuery = false, CanTouch = false })
		pads.runEnd = part(model, "RunEnd", s.runEnd.size, spotCF(station, "runEnd") * CFrame.new(0, 0.12, 0), C.Use,
			{ CanCollide = false, CanQuery = false, CanTouch = false })
		-- (the set draws and collides its own vault box, mantle wall and slide bar: TrainingCentreBuilder.prepare lifts the
		-- bar to the same 4.6 underside)
		if not blender then
			part(model, "Vault", s.vault.size, spotCF(station, "vault") * CFrame.new(0, s.vault.size.Y / 2, 0), C.Use, { Material = Enum.Material.Fabric })
			part(model, "Mantle", s.mantle.size, spotCF(station, "mantle") * CFrame.new(0, s.mantle.size.Y / 2, 0), C.Teal, { Material = Enum.Material.Fabric })
			-- its underside 4.6 off the floor: a standing body (head about 5.2) meets it, a crouch or a slide (Config CrouchHeadTop 4.3) passes
			part(model, "SlideBar", s.slide.size, spotCF(station, "slide") * CFrame.new(0, 5.1, 0), C.Use)
			-- rails either side of the run, so it is run through and not round
			local a, b = spotCF(station, "runStart"), spotCF(station, "runEnd")
			local runCF = CFrame.lookAt((a.Position + b.Position) / 2, b.Position) * CFrame.Angles(0, math.rad(90), 0)
			local len = (b.Position - a.Position).Magnitude
			for side = -1, 1, 2 do
				part(model, "SlidePost", Vector3.new(0.5, 4, 0.5), spotCF(station, "slide") * CFrame.new(0, 2, side * 3), C.Steel)
				part(model, "RunRail", Vector3.new(len, 1, 0.4), runCF * CFrame.new(0, 0.5, side * 4.4), C.Line, { CanQuery = false })
			end
		end
	end
	model.Parent = root
end

local function build()
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	table.clear(lanes)
	table.clear(boards)
	table.clear(dummies)
	table.clear(mats)
	table.clear(chestParts)
	table.clear(pads)
	table.clear(bikes)
	survival = { plants = {} }
	local hasSet = readSet()
	local root = Instance.new("Folder")
	root.Name = FOLDER_NAME
	if not hasSet then
		buildShell(root)
	end
	for _, station in ipairs(TS.List) do
		local ok, err = pcall(buildStation, root, station)
		if not ok then
			warn("[TrainingService] building " .. station.id .. " failed: " .. tostring(err))
		end
	end
	root.Parent = workspace
	folder = root
	-- The set's archery targets stand one behind the other on each lane, and their invisible colliders are always
	-- solid: the 20-stud target's collider caught every arrow shot at the 40 and 60 (mp-training, 19 Nov). Arrows and
	-- throws are ray casts, so those colliders stop answering queries; the pop-up faces in front of them are the targets.
	-- (CanQuery can only be off while CanCollide is off: the faces are head high on their stands, nobody walks into them)
	if blenderSet then
		for _, d in ipairs(blenderSet:GetDescendants()) do
			if d:IsA("BasePart") and string.match(d.Name, "^TC_Archery_Target_.*_Col$") then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
	end
	for _, seat in ipairs(bikes) do
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local humanoid = seat.Occupant
			local player = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
			if player then
				stateFor(player).bike = { seat = seat, since = os.clock() }
			end
		end)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Tokens and results
--------------------------------------------------------------------------------------------------------------------

local function award(player: Player, drillId: string, gives: string?): number
	local st = stateFor(player)
	local tokens = 0
	if st.tokensToday < TS.TokensPerDay then
		tokens += 1
		st.tokensToday += 1
	end
	if not st.passedEver[drillId] then
		st.passedEver[drillId] = true
		tokens += 1 -- the first pass ever (this session until DataService keeps DrillsPassed)
	end
	if tokens > 0 then
		player:SetAttribute("TrainingTokens", (tonumber(player:GetAttribute("TrainingTokens")) or 0) + tokens)
	end
	if gives then
		local key = "Trained" .. gives
		player:SetAttribute(key, (tonumber(player:GetAttribute(key)) or 0) + 1)
	end
	TrainingService.passed:Fire(player, drillId)
	return tokens
end

local function sendDrill(player: Player, drill: Drill, extra: { [string]: any }?)
	local payload = { t = "drill", id = drill.id, station = drill.station, name = drill.name, state = "run",
		score = drill.score, total = drill.total, need = drill.need, points = drill.points, endsAt = drill.endsAt }
	if extra then
		for k, val in pairs(extra) do
			payload[k] = val
		end
	end
	send(player, payload)
end

-- Ends a drill: one quiet result line ("ARCHERY · 5 / 6 · passed"), the token, the sound.
local function finishDrill(player: Player, passed: boolean, text: string, gives: string?)
	local st = stateFor(player)
	local drill = st.drill
	st.drill = nil
	st.needLeave = true -- a start pad starts again only after the player steps off it
	local id = if drill then drill.id else "drill"
	local tokens = if passed then award(player, id, gives) else 0
	if Config.IsStudio then
		print(string.format("[TrainingService] %s: %s (+%d token)", player.Name, text, tokens))
	end
	send(player, { t = "drill", id = id, station = drill and drill.station, name = drill and drill.name, state = "done",
		passed = passed, text = text, token = tokens, score = drill and drill.score, total = drill and drill.total })
	if drill and drill.id == "archery" then
		local lane = lanes[drill.extra.lane]
		if lane then
			lane.owner = nil
			for _, t in ipairs(lane.targets) do
				t.up = false
				setTargetUp(t.model, false)
			end
		end
	end
end

local function startDrill(player: Player, station: any, def: any, extra: { [string]: any }?, total: number?, need: number?): Drill
	local st = stateFor(player)
	local now = os.clock()
	local drill: Drill = { id = def.id, station = station.id, name = def.name, startedAt = now,
		endsAt = serverNow() + (def.time or 30), score = 0, total = total or def.total or 1, need = need or def.need or 1,
		points = nil, extra = extra or {} }
	drill.extra.clockEnd = now + (def.time or 30)
	drill.extra.def = def
	st.drill = drill
	sendDrill(player, drill, { line = def.line })
	return drill
end

--------------------------------------------------------------------------------------------------------------------
-- Borrowed items
--------------------------------------------------------------------------------------------------------------------

function TrainingService.reclaim(player: Player, reason: string?)
	local st = states[player]
	if not st or next(st.lent) == nil then
		return
	end
	local back = 0
	for itemId, count in pairs(st.lent) do
		local have = tonumber(call("InventoryService", "count", player, itemId)) or 0
		local n = math.min(have, count)
		if n > 0 and call("InventoryService", "take", player, itemId, n) == true then
			back += n
		end
	end
	table.clear(st.lent)
	st.lentStation = nil
	if back > 0 and player.Parent == Players then
		line(player, "Borrowed items returned", reason)
		pcall(Sfx.playFor, player, "Drop", { volume = 0.5 })
	end
end

function TrainingService.reclaimAll(reason: string?)
	for player in pairs(states) do
		TrainingService.reclaim(player, reason)
	end
end

local warnedLend = false
onChest = function(player: Player, stationId: string)
	if not Net.rateLimit(player, "TrainingChest", 2, 3) then
		return
	end
	local st = stateFor(player)
	if not st.inHall then
		return
	end
	if st.bay ~= stationId then
		-- at the chest but a step over its bay's edge (the fitness chest stands 6 studs from it): still the chest's
		local box = chestParts[stationId]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (box and root and (root.Position - box.Position).Magnitude <= 12) then
			return
		end -- (the scan hands what it lends back once the player walks into a third bay)
	end
	if st.lentStation and st.lentStation ~= stationId then
		TrainingService.reclaim(player, "Each station lends its own")
	end
	local given = 0
	local wanted = 0
	for _, item in ipairs(TS.chestItems(stationId)) do
		-- top up to the chest's count (arrows refill), counting what this chest already lent
		local have = tonumber(call("InventoryService", "count", player, item.id)) or 0
		local lentNow = st.lent[item.id] or 0
		local missing = item.count - math.min(have, lentNow)
		if lentNow == 0 and have >= item.count then
			missing = 0 -- the player's own copy is enough
		end
		if missing > 0 then
			wanted += missing
			local n = tonumber(call("InventoryService", "give", player, item.id, missing, 1)) or 0
			if n > 0 then
				st.lent[item.id] = lentNow + n
				given += n
			end
		end
	end
	if given > 0 then
		st.lentStation = stationId
		pcall(Sfx.playFor, player, "PickUp", { volume = 0.6 })
		local station = TS.get(stationId)
		line(player, "Borrowed for training", "They stay in the " .. string.lower(station and station.name or "bay"))
	elseif wanted == 0 then
		line(player, "You have this station's items")
	else
		line(player, "Nothing to borrow right now", "Your bag may be full")
		if not warnedLend and Config.IsStudio then
			warnedLend = true
			warn("[TrainingService] InventoryService.give lent nothing: it only gives to alive contenders (the hall needs the InTraining gate)")
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Mats
--------------------------------------------------------------------------------------------------------------------

local function onMat(player: Player, mat: any)
	if mat.kit then
		if call("KitService", "setKit", player, mat.kit) ~= false then
			local kit = Kits.get(mat.kit)
			line(player, string.upper(kit and kit.name or mat.kit) .. " · " .. (TS.KitLines[mat.kit] or "your kit"),
				"Kit lands mid-round · free to change until the call")
		end
	elseif mat.specialty then
		local clean = call("KitService", "setLoadout", player, { specialty = mat.specialty })
		if type(clean) == "table" and clean.specialty == mat.specialty then
			local words = if mat.specialty == "ShortBlade" then "SHORT BLADE" else string.upper(mat.specialty)
			line(player, words .. " · your Specialty", "Its skill is yours this round · skills recharge fast in the hall")
		end
	end
	pcall(Sfx.playFor, player, "UIClick", { volume = 0.5 })
end

local function onPad(p: BasePart, position: Vector3, margin: number?): boolean
	local lp = p.CFrame:PointToObjectSpace(position)
	local m = margin or 0
	return math.abs(lp.X) <= p.Size.X / 2 + m and math.abs(lp.Z) <= p.Size.Z / 2 + m and lp.Y > -2 and lp.Y < 6
end

--------------------------------------------------------------------------------------------------------------------
-- Drills: archery, throwing, blades
--------------------------------------------------------------------------------------------------------------------

local function archeryStart(player: Player, laneIndex: number)
	local lane = lanes[laneIndex]
	if not lane or lane.owner then
		return
	end
	local station = TS.get("archery")
	local def = station.drill
	lane.owner = player
	local order = {}
	for i = 1, #lane.targets do
		table.insert(order, i)
		table.insert(order, i)
	end
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local drill = startDrill(player, station, def, { lane = laneIndex, order = order, step = 0, nextAt = os.clock() + 1,
		current = nil, hitThis = false }, #order, def.need)
	drill.points = 0
end

local function archeryTick(player: Player, drill: Drill, now: number)
	local x = drill.extra
	local lane = lanes[x.lane]
	if not lane then
		return
	end
	local def = x.def
	if x.current and now >= x.downAt then
		x.current.up = false
		setTargetUp(x.current.model, false)
		x.current = nil
		x.nextAt = now + def.gapTime
	end
	if not x.current and now >= x.nextAt then
		x.step += 1
		if x.step > #x.order then
			local passed = drill.score >= drill.need
			finishDrill(player, passed, string.format("ARCHERY · %d / %d · %s", drill.score, drill.total,
				if passed then "passed" else "4 to pass"))
			return
		end
		local t = lane.targets[x.order[x.step]]
		t.up = true
		setTargetUp(t.model, true)
		x.current = t
		x.hitThis = false
		x.downAt = now + def.upTime
		sendDrill(player, drill, { up = t.distance })
	end
end

local function throwingStart(player: Player)
	local station = TS.get("throwing")
	startDrill(player, station, station.drill, { throws = 0, lastThrowAt = nil, hitBoards = {} }, station.drill.total, station.drill.need)
end

local function bladesStart(player: Player)
	local station = TS.get("blades")
	local def = station.drill
	startDrill(player, station, def, { hits = 0, guards = 0 }, def.hitsNeed + def.guardsNeed, def.hitsNeed + def.guardsNeed)
end

-- The nearest player in training to a point, within `range` studs.
local function nearestTrainee(position: Vector3, range: number, filter: ((Player, BasePart) -> boolean)?): (Player?, BasePart?)
	local best, bestRoot, bestD = nil, nil, range
	for player, st in pairs(states) do
		if st.inHall then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local d = (root.Position - position).Magnitude
				if d <= bestD and (not filter or filter(player, root)) then
					best, bestRoot, bestD = player, root, d
				end
			end
		end
	end
	return best, bestRoot
end

local function targetOwner(model: Model): (Player?, any, string?)
	-- archery: a lane's popped target
	for _, lane in ipairs(lanes) do
		for _, t in ipairs(lane.targets) do
			if t.model == model or model:IsDescendantOf(t.model) then
				return lane.owner, t, "archery"
			end
		end
	end
	for _, b in ipairs(boards) do
		if b.model == model or model:IsDescendantOf(b.model) then
			return nil, b, "throwing"
		end
	end
	return nil, nil, nil
end

-- Who struck this body just now (CombatService.applyHit marks training bodies with TrainingHitBy / TrainingHitAt):
-- the player, or nil when nobody known struck it in the last half second (then the nearest trainee is credited).
local function struckBy(model: Instance?): Player?
	-- (a target's centre ring is its own body, the child "Bull": a hit there marks it, not the target)
	local bull = model and model:FindFirstChild("Bull")
	if bull then
		local uid, at = bull:GetAttribute("TrainingHitBy"), bull:GetAttribute("TrainingHitAt")
		if type(uid) == "number" and type(at) == "number" and os.clock() - at <= 0.5 then
			return Players:GetPlayerByUserId(uid)
		end
	end
	local m = model
	for _ = 1, 3 do
		if not m or m == workspace then
			return nil
		end
		local uid, at = m:GetAttribute("TrainingHitBy"), m:GetAttribute("TrainingHitAt")
		if type(uid) == "number" and type(at) == "number" and os.clock() - at <= 0.5 then
			return Players:GetPlayerByUserId(uid)
		end
		m = m.Parent
	end
	return nil
end

-- A target's or board's Humanoid lost health: a hit. Health goes straight back.
local function onTargetHit(model: Model, isBull: boolean)
	local owner, entry, kind = targetOwner(model)
	local root = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart?
	local striker = struckBy(model)
	if kind == "archery" and owner and striker and striker ~= owner then
		owner = nil -- another player's arrow in this lane: no point for the lane's owner
	end
	if kind == "archery" and owner then
		local st = states[owner]
		local drill = st and st.drill
		if drill and drill.id == "archery" and drill.extra.current == entry and not drill.extra.hitThis then
			drill.extra.hitThis = true
			drill.score += 1
			drill.points = (drill.points or 0) + (if isBull then 2 else 1)
			sendDrill(owner, drill, { hit = entry.distance, bull = isBull })
			-- a hit drops the target at once and brings the next one a little sooner
			drill.extra.downAt = math.min(drill.extra.downAt, os.clock() + 0.25)
		end
	elseif kind == "throwing" and root then
		local player = if striker then striker else nearestTrainee(root.Position, 70, function(p)
			local s = states[p]
			return s and s.drill ~= nil and s.drill.id == "throwing"
		end)
		local st = player and states[player]
		local drill = st and st.drill
		if drill and drill.id == "throwing" and entry.distance >= (drill.extra.def.minDistance or 20) and not drill.extra.hitBoards[drill.extra.throws] then
			drill.extra.hitBoards[drill.extra.throws] = true -- one hit per throw
			drill.score += 1
			sendDrill(player :: Player, drill, { hit = entry.distance, bull = isBull })
		end
	end
	if root then
		Sfx.play("Hit_Wood", { position = root.Position, volume = 0.7 })
	end
end

local function watchTargets()
	local function watch(model: Model, isBull: boolean)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local last = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < last - 0.01 then
				humanoid.Health = humanoid.MaxHealth
				last = humanoid.MaxHealth
				onTargetHit(if isBull then model.Parent :: Model else model, isBull)
			else
				last = health
			end
		end)
	end
	for _, lane in ipairs(lanes) do
		for _, t in ipairs(lane.targets) do
			watch(t.model, false)
			local bull = t.model:FindFirstChild("Bull")
			if bull and bull:IsA("Model") then
				watch(bull, true)
			end
		end
	end
	for _, b in ipairs(boards) do
		watch(b.model, false)
		local bull = b.model:FindFirstChild("Bull")
		if bull and bull:IsA("Model") then
			watch(bull, true)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The dummies (section 3.3)
--------------------------------------------------------------------------------------------------------------------

local ARM_UP = CFrame.Angles(0, 0, math.rad(-70)) -- the padded arm lifted across the body: the tell
local ARM_STRIKE = CFrame.Angles(math.rad(150), 0, 0) -- the striker's arm over its head

local function setArm(entry: any, pose: string)
	local d = entry.data
	if d.armPose == pose then
		return
	end
	d.armPose = pose
	if d.shoulder and d.shoulderC0 then
		d.shoulder.C0 = if pose == "guard" then d.shoulderC0 * ARM_UP
			elseif pose == "raise" then d.shoulderC0 * ARM_STRIKE
			else d.shoulderC0
	end
	if d.lshoulder and d.lshoulderC0 then
		d.lshoulder.C0 = if pose == "guard" then d.lshoulderC0 * CFrame.Angles(0, 0, math.rad(70)) else d.lshoulderC0
	end
end

local function setGuard(entry: any, on: boolean, parry: boolean)
	local model = entry.model
	if on then
		model:SetAttribute("GuardAt", if parry then serverNow() else serverNow() - 30) -- (an old GuardAt: block, never parry)
		model:SetAttribute("Guard", true)
		setArm(entry, "guard")
	else
		model:SetAttribute("Guard", false)
		setArm(entry, "rest")
	end
end

local function rootOf(model: Model): BasePart?
	local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if r and r:IsA("BasePart") then r else nil
end

-- A blow landed on a dummy: wobble it, and count it for a blades drill when it was a clean hit on the blocker or parrier.
onDummyDamaged = function(entry: any, amount: number)
	local d = entry.data
	d.lastHit = os.clock()
	d.wobble = math.min(1.35, d.wobble * 0.5 + 0.6)
	d.wobbleTime = 0
	if entry.stance ~= "Blocker" and entry.stance ~= "Parrier" then
		return
	end
	if entry.model:GetAttribute("Guard") == true then
		return -- blocked: not clean
	end
	local root = rootOf(entry.model)
	if not root then
		return
	end
	local player = struckBy(entry.model) or nearestTrainee(root.Position, 14, function(p)
		local s = states[p]
		return s and s.drill ~= nil and s.drill.id == "blades"
	end)
	local drill = player and states[player] and states[player].drill
	if drill and drill.id == "blades" then
		drill.extra.hits = math.min(drill.extra.def.hitsNeed, drill.extra.hits + 1)
		drill.score = drill.extra.hits + drill.extra.guards
		sendDrill(player :: Player, drill, { hits = drill.extra.hits, guards = drill.extra.guards })
	end
end

local function inFrontOf(model: Model, position: Vector3, maxDot: number): boolean
	local root = rootOf(model)
	if not root then
		return false
	end
	local to = position - root.Position
	to = Vector3.new(to.X, 0, to.Z)
	if to.Magnitude < 0.1 then
		return true
	end
	return root.CFrame.LookVector:Dot(to.Unit) >= maxDot
end

local function strikerTick(entry: any, now: number)
	local d = entry.data
	local root = rootOf(entry.model)
	if not root then
		return
	end
	if d.phase == "rest" then
		if now >= d.next then
			local player, proot = nearestTrainee(root.Position, 7.5, function(_, r)
				return inFrontOf(entry.model, r.Position, 0.2)
			end)
			if player and proot then
				d.phase = "tell"
				d.phaseAt = now
				d.victim = player
				setArm(entry, "raise")
				Sfx.play("Swing_Heavy", { position = root.Position, volume = 0.35, pitch = 0.8 })
			else
				d.next = now + 0.5
			end
		end
	elseif d.phase == "tell" and now - d.phaseAt >= 0.9 then
		d.phase = "rest"
		d.next = now + 4 - 0.9
		setArm(entry, "rest")
		local player: Player? = d.victim
		d.victim = nil
		local character = player and player.Character
		local proot = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (player and proot and humanoid and (proot.Position - root.Position).Magnitude <= 9) then
			return
		end
		local before = humanoid.Health
		local combat = Services.CombatService
		if not (combat and type(combat._npcStrike) == "function") then
			return
		end
		local ok, result, dealt = pcall(combat._npcStrike, entry.model, character, "H", "sword")
		if not ok then
			warn("[TrainingService] striker: " .. tostring(result))
			return
		end
		if humanoid.Health < before then
			-- (a practice round: Active and an alive contender, so the blow did harm; nobody is hurt in the hall)
			call("PlayerService", "heal", player, before - humanoid.Health)
		end
		if result == "Hit" and (tonumber(dealt) or 0) <= 0 and type(combat.react) == "function" then
			pcall(combat.react, nil, character, "Stagger", { position = root.Position, knock = 8 })
		end
		local st = states[player :: Player]
		local drill = st and st.drill
		if drill and drill.id == "blades" and (result == "Blocked" or result == "Parried" or result == "Dodged") then
			drill.extra.guards = math.min(drill.extra.def.guardsNeed, drill.extra.guards + 1)
			drill.score = drill.extra.hits + drill.extra.guards
		end
		if drill and drill.id == "blades" then
			sendDrill(player :: Player, drill, { hits = drill.extra.hits, guards = drill.extra.guards, strike = result })
		elseif result then
			send(player :: Player, { t = "strike", result = result })
		end
	end
end

local function updateDummies(dt: number)
	local now = os.clock()
	local anyone = false
	for _, st in pairs(states) do
		if st.inHall then
			anyone = true
			break
		end
	end
	for _, entry in ipairs(dummies) do
		local d = entry.data
		local humanoid = entry.humanoid
		if humanoid.Parent and now - d.lastHit > 4 and humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = humanoid.MaxHealth
			d.last = humanoid.MaxHealth
		end
		if d.waist and d.waistC0 then
			if d.wobble > 0.002 then
				d.wobbleTime += dt
				d.wobble *= math.exp(-3.2 * dt)
				d.waist.C0 = d.waistC0 * CFrame.fromAxisAngle(d.axis, d.wobble * math.rad(13) * math.sin(d.wobbleTime * 16))
			elseif d.wobble ~= 0 then
				d.wobble = 0
				d.waist.C0 = d.waistC0
			end
		end
		if anyone then
			if entry.stance == "Blocker" then
				local t = now % 3
				if t < 0.3 then
					if d.armPose ~= "guard" then
						setArm(entry, "guard") -- the tell: the arm lifts 0.3 s before the guard
					end
				elseif t < 1.8 then
					if entry.model:GetAttribute("Guard") ~= true then
						setGuard(entry, true, false)
					end
				elseif entry.model:GetAttribute("Guard") == true or d.armPose ~= "rest" then
					setGuard(entry, false, false)
				end
			elseif entry.stance == "Parrier" then
				if d.guardUntil and now >= d.guardUntil then
					d.guardUntil = nil
					setGuard(entry, false, false)
				end
			elseif entry.stance == "Striker" then
				strikerTick(entry, now)
			end
		elseif entry.model:GetAttribute("Guard") == true then
			setGuard(entry, false, false)
		end
	end
end

-- MeleeSwing "Start" from a player near the parrier: it guards inside the wind-up 40% of the time.
local function onSwingStart(player: Player, kind: any)
	if kind ~= "Start" then
		return
	end
	local st = states[player]
	if not (st and st.inHall) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, entry in ipairs(dummies) do
		if entry.stance == "Parrier" then
			local droot = rootOf(entry.model)
			if droot and (droot.Position - root.Position).Magnitude <= 10 and inFrontOf(entry.model, root.Position, 0)
				and not entry.data.guardUntil and rng:NextNumber() < 0.4 then
				setGuard(entry, true, true)
				entry.data.guardUntil = os.clock() + 0.7
			end
		end
	end
end

-- RangedRelease "Throw": counts a throwing drill's throws.
local function onRanged(player: Player, _shotId: any, _origin: any, _direction: any, _charge: any, mode: any)
	if mode ~= "Throw" then
		return
	end
	local st = states[player]
	local drill = st and st.drill
	if drill and drill.id == "throwing" and drill.extra.throws < drill.total then
		drill.extra.throws += 1
		drill.extra.lastThrowAt = os.clock()
		sendDrill(player, drill, { throws = drill.extra.throws })
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Survival corner, weights, bikes
--------------------------------------------------------------------------------------------------------------------

local function survivalDrill(player: Player): Drill?
	local st = stateFor(player)
	if st.drill and st.drill.id == "survival" then
		return st.drill
	end
	if st.drill then
		return nil -- another drill is running
	end
	local station = TS.get("survival")
	local drill = startDrill(player, station, station.drill, { fire = false, water = false, plants = {}, kept = 0,
		spoiled = false, bandage = false }, 4, 4)
	return drill
end

local function survivalScore(player: Player, drill: Drill, said: string?)
	local x = drill.extra
	local plantsDone = x.kept >= 3 and not x.spoiled
	drill.score = (if x.fire then 1 else 0) + (if x.water then 1 else 0) + (if plantsDone then 1 else 0) + (if x.bandage then 1 else 0)
	sendDrill(player, drill, { fire = x.fire, water = x.water, plants = x.kept, spoiled = x.spoiled, bandage = x.bandage, said = said })
	if drill.score >= 4 then
		finishDrill(player, true, string.format("SURVIVAL · 4 / 4 · passed in %d s", math.floor(os.clock() - drill.startedAt + 0.5)),
			drill.extra.def.gives)
	end
end

onPrompt = function(player: Player, what: string, index: number?)
	local st = stateFor(player)
	if not st.inHall then
		return
	end
	if what == "weights" then
		if st.drill or (st.weights and os.clock() - st.weights.startedAt < 25) then
			return
		end
		local station = TS.get("fitness")
		local def = station.drills.weights
		st.weights = { startedAt = os.clock() }
		send(player, { t = "weights", total = def.total, period = def.period, line = def.line })
		return
	end
	if st.bay ~= "survival" then
		return
	end
	local drill = survivalDrill(player)
	if not drill then
		return
	end
	local x = drill.extra
	if what == "fire" then
		x.fire = true
		if survival.flame then
			survival.flame.Enabled = true
			local light = survival.fire and survival.fire:FindFirstChild("FireLight")
			if light then
				(light :: PointLight).Enabled = true
			end
			task.delay(20, function()
				if survival.flame then
					survival.flame.Enabled = false
				end
				if light then
					(light :: PointLight).Enabled = false
				end
			end)
		end
		Sfx.play("Emit_Fire", { position = survival.fire and survival.fire.Position, volume = 0.5 })
		survivalScore(player, drill, "The fire is lit")
	elseif what == "water" then
		-- a borrowed empty bottle becomes a full one; without one the drill still counts the trip
		if (tonumber(call("InventoryService", "count", player, "empty_bottle")) or 0) > 0
			and call("InventoryService", "take", player, "empty_bottle", 1) == true then
			local n = tonumber(call("InventoryService", "give", player, "water_bottle", 1)) or 0
			if n > 0 and st.lent.empty_bottle then
				st.lent.empty_bottle = math.max(0, st.lent.empty_bottle - 1)
				st.lent.water_bottle = (st.lent.water_bottle or 0) + n
			end
		end
		x.water = true
		pcall(Sfx.playFor, player, "CanteenFill", { volume = 0.6 })
		survivalScore(player, drill, "Bottle filled")
	elseif what == "plant" and index then
		local plant = survival.plants[index]
		if not plant or x.plants[index] then
			return
		end
		x.plants[index] = true
		if plant.sound then
			x.kept += 1
			survivalScore(player, drill, "Sound · keep it")
		else
			x.spoiled = true
			survivalScore(player, drill, "Spoiled · leave those")
		end
	elseif what == "bandage" then
		x.bandage = true
		pcall(Sfx.playFor, player, "Bandage", { volume = 0.6 })
		survivalScore(player, drill, "Bandaged")
	end
end

local function onClient(player: Player, payload: any)
	if type(payload) ~= "table" or not Net.rateLimit(player, "Training", 4, 6) then
		return
	end
	local st = stateFor(player)
	if payload.t == "bike" then
		local bike = st.bike
		local green = tonumber(payload.green)
		if not (bike and green and green == green) then
			return
		end
		local seated = os.clock() - bike.since
		local def = TS.get("fitness").drills.bike
		green = math.clamp(green, 0, seated + 0.5) -- never more green than time on the saddle
		st.bike = nil
		local passed = green >= def.green
		st.drill = { id = def.id, station = "fitness", name = def.name, startedAt = bike.since, endsAt = 0, score = 0, total = 0,
			need = 0, extra = {} }
		finishDrill(player, passed, string.format("BIKE · %d s in the green · %s", math.floor(green), if passed then "passed" else "20 to pass"),
			def.gives)
	elseif payload.t == "weights" then
		local w = st.weights
		local clean, beats = tonumber(payload.clean), tonumber(payload.beats)
		if not (w and clean and beats) or clean ~= clean or beats ~= beats then
			return
		end
		st.weights = nil
		local def = TS.get("fitness").drills.weights
		local elapsed = os.clock() - w.startedAt
		beats = math.clamp(math.floor(beats), 0, 30)
		clean = math.clamp(math.floor(clean), 0, beats)
		if elapsed < beats * def.period * 0.8 then
			clean = math.floor(elapsed / (def.period * 0.8)) -- faster than the beat can go: count only what fits
		end
		local passed = clean >= def.need
		st.drill = { id = def.id, station = "fitness", name = def.name, startedAt = w.startedAt, endsAt = 0, score = clean,
			total = def.total, need = def.need, extra = {} }
		finishDrill(player, passed, string.format("WEIGHTS · %d / %d clean · %s", clean, def.total, if passed then "passed" else "10 to pass"),
			def.gives)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The scan: hall, bays, mats, start pads, the wall, the lap and the run
--------------------------------------------------------------------------------------------------------------------

local function leaveHall(player: Player, st: { [string]: any }, reason: string?)
	st.inHall = false
	st.bay = nil
	st.mat = nil
	st.wall, st.lap, st.run = nil, nil, nil
	if st.drill then
		finishDrill(player, false, string.upper(st.drill.name) .. " · stopped")
	end
	TrainingService.reclaim(player, reason or "They stay in the hall")
	if player.Parent == Players then
		player:SetAttribute("InTraining", nil)
		player:SetAttribute("TrainingBay", nil)
		player:SetAttribute("TrainingCooldownScale", nil)
	end
end

local function scanPlayer(player: Player, st: { [string]: any }, now: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		if st.inHall then
			leaveHall(player, st)
		end
		return
	end
	local p = toHall(root.Position)
	if not TS.inHall(p, 3) then
		if st.inHall then
			leaveHall(player, st)
		end
		return
	end
	if p.Y < -TS.FallDepth + 6 then
		root.CFrame = hallCF * CFrame.new(TS.Arrival) -- fell out of the hall: back to the arrival spot
		root.AssemblyLinearVelocity = Vector3.zero
		return
	end
	if not st.inHall then
		st.inHall = true
		player:SetAttribute("InTraining", true)
		player:SetAttribute("TrainingCooldownScale", TS.CooldownScale)
	end
	local bay = TS.bayAt(p)
	if bay ~= st.bay then
		if st.lentStation and st.lentStation ~= bay then
			TrainingService.reclaim(player, "They stay in their bay")
		end
		local drill = st.drill
		if drill and drill.station ~= bay and not (drill.station == "fitness" and drill.id == "wall") then
			finishDrill(player, false, string.upper(drill.name) .. " · left the bay")
		end
		st.bay = bay
		player:SetAttribute("TrainingBay", bay)
	end

	-- mats
	local onMatNow = nil
	for _, mat in ipairs(mats) do
		if mat.station == bay and onPad(mat.part, root.Position, 0.5) then
			onMatNow = mat
			break
		end
	end
	if onMatNow ~= st.mat then
		st.mat = onMatNow
		if onMatNow then
			onMat(player, onMatNow)
		end
	end

	local drill = st.drill
	if st.needLeave then
		local onStart = (pads.throwing and onPad(pads.throwing, root.Position, 0.5)) or (pads.blades and onPad(pads.blades, root.Position, 0.5))
		for _, lane in ipairs(lanes) do
			onStart = onStart or onPad(lane.start, root.Position, 0.5)
		end
		if not onStart then
			st.needLeave = false
		end
	end
	-- running drills
	if drill then
		if drill.id == "archery" then
			archeryTick(player, drill, now)
		elseif drill.id == "throwing" then
			local x = drill.extra
			local done = x.throws >= drill.total and x.lastThrowAt and now - x.lastThrowAt > 1.6
			if done or now >= x.clockEnd then
				local passed = drill.score >= drill.need
				finishDrill(player, passed, string.format("THROWING · %d / %d · %s", drill.score, drill.total,
					if passed then "passed" else "3 to pass"))
			end
		elseif drill.id == "blades" then
			local x = drill.extra
			if x.hits >= x.def.hitsNeed and x.guards >= x.def.guardsNeed then
				finishDrill(player, true, string.format("BLADES · %d hits · %d guarded · passed in %d s", x.hits, x.guards,
					math.floor(now - drill.startedAt + 0.5)))
			elseif now >= x.clockEnd then
				finishDrill(player, false, string.format("BLADES · %d / %d hits · %d / %d guarded", x.hits, x.def.hitsNeed,
					x.guards, x.def.guardsNeed))
			end
		elseif drill.id == "survival" then
			if now >= drill.extra.clockEnd then
				finishDrill(player, false, string.format("SURVIVAL · %d / 4 · 45 s to do all four", drill.score))
			end
		end
	elseif st.needLeave then
		-- (just finished on a start pad: step off first)
	elseif bay == "archery" then
		for i, lane in ipairs(lanes) do
			if onPad(lane.start, root.Position, 0.3) then
				archeryStart(player, i)
				break
			end
		end
	elseif bay == "throwing" and pads.throwing and onPad(pads.throwing, root.Position, 0.3) then
		throwingStart(player)
	elseif bay == "blades" and pads.blades and onPad(pads.blades, root.Position, 0.3) then
		bladesStart(player)
	end

	-- fitness: the climbing wall (from the climber's mat to the top)
	if bay == "fitness" or (st.wall and st.wall.startedAt) then
		local station = TS.get("fitness")
		local def = station.drills.wall
		local w = st.wall
		local onClimbMat = onMatNow ~= nil and onMatNow.kit == "climber"
		if onClimbMat then
			st.wall = { armed = true }
		elseif w and w.armed and not w.startedAt then
			w.startedAt = now
			send(player, { t = "drill", id = def.id, station = "fitness", name = def.name, state = "run", score = 0, total = 1,
				need = 1, endsAt = serverNow() + def.time, line = def.line })
		end
		w = st.wall
		if w and w.startedAt then
			local top = station.spots.wallTop
			local tp = stationCF(station):PointToObjectSpace(root.Position) - top.pos
			if tp.Y >= -1 and math.abs(tp.X) <= top.size.X / 2 + 1 and math.abs(tp.Z) <= top.size.Z / 2 + 1 then
				local time = now - w.startedAt
				st.wall = nil
				local passed = time <= def.time
				st.drill = { id = def.id, station = "fitness", name = def.name, startedAt = w.startedAt, endsAt = 0, score = 1,
					total = 1, need = 1, extra = {} }
				finishDrill(player, passed, string.format("CLIMB · top in %.1f s · %s", time, if passed then "passed" else "8 s to pass"),
					def.gives)
			elseif now - w.startedAt > 20 or (bay ~= "fitness") then
				st.wall = nil
			end
		end
	end

	-- the track: a lap through the four gates, and the obstacle run
	if bay == "track" and not drill then
		local station = TS.get("track")
		local origin = stationCF(station)
		local lp = origin:PointToObjectSpace(root.Position)
		local lap = st.lap
		if pads.lap and onPad(pads.lap, root.Position, 0.5) then
			if lap and lap.gate > #station.gates then
				local time = now - lap.startedAt
				local def = station.drills.lap
				st.lap = nil
				local passed = time <= def.time
				st.drill = { id = def.id, station = "track", name = def.name, startedAt = lap.startedAt, endsAt = 0, score = 1,
					total = 1, need = 1, extra = {} }
				finishDrill(player, passed, string.format("LAP · %.1f s · %s", time, if passed then "passed" else "19 s to pass"), def.gives)
			elseif not lap or lap.gate == 2 then
				st.lap = { startedAt = now, gate = 2, armed = true }
			end
		elseif lap then
			if lap.armed and lap.gate == 2 and not lap.announced then
				lap.announced = true
				local def = station.drills.lap
				lap.startedAt = now
				send(player, { t = "drill", id = def.id, station = "track", name = def.name, state = "run", score = 0, total = 4,
					need = 4, endsAt = serverNow() + def.time, line = def.line })
			end
			local g = station.gates[lap.gate]
			if g and (Vector3.new(lp.X, 0, lp.Z) - g).Magnitude <= station.gateRadius then
				lap.gate += 1
				send(player, { t = "drill", id = "lap", station = "track", name = "Lap", state = "run", score = lap.gate - 2,
					total = 4, need = 4, endsAt = serverNow() + math.max(0, station.drills.lap.time - (now - lap.startedAt)) })
			end
			if now - lap.startedAt > 45 then
				st.lap = nil
			end
		end
		-- the obstacle run: leave the start pad, cross the three obstacles' lane, reach the far pad
		local run = st.run
		if pads.runStart and onPad(pads.runStart, root.Position, 0.3) then
			st.run = { armed = true, seen = {} }
		elseif run then
			if run.armed and not run.startedAt then
				run.startedAt = now
				local def = station.drills.run
				send(player, { t = "drill", id = def.id, station = "track", name = def.name, state = "run", score = 0, total = 3,
					need = 3, endsAt = serverNow() + def.time, line = def.line })
			end
			for i, name in ipairs({ "vault", "mantle", "slide" }) do
				-- in the obstacle's own frame (local x runs along the run): over it, or under it, within its width
				local q = spotCF(station, name):PointToObjectSpace(root.Position)
				if math.abs(q.X) < 1.6 and math.abs(q.Z) < 4.2 then
					run.seen[i] = true
				end
			end
			if pads.runEnd and onPad(pads.runEnd, root.Position, 0.3) then
				local time = now - run.startedAt
				local count = (if run.seen[1] then 1 else 0) + (if run.seen[2] then 1 else 0) + (if run.seen[3] then 1 else 0)
				local def = station.drills.run
				st.run = nil
				local passed = time <= def.time and count == 3
				st.drill = { id = def.id, station = "track", name = def.name, startedAt = run.startedAt, endsAt = 0, score = count,
					total = 3, need = 3, extra = {} }
				finishDrill(player, passed, string.format("OBSTACLE RUN · %.1f s · %s", time,
					if passed then "passed" elseif count < 3 then "take all three" else "12 s to pass"), def.gives)
			elseif now - run.startedAt > 30 then
				st.run = nil
			end
		end
	end

	-- a bike rider who stands up without a result: forget the ride
	if st.bike and humanoid.SeatPart ~= st.bike.seat then
		st.bike = nil
	end
end

local scanAccum = 0
local function onHeartbeat(dt: number)
	updateDummies(dt)
	scanAccum += dt
	if scanAccum < SCAN then
		return
	end
	scanAccum = 0
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local st = stateFor(player)
		local ok, err = pcall(scanPlayer, player, st, now)
		if not ok then
			warn("[TrainingService] scan: " .. tostring(err))
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- API and lifecycle
--------------------------------------------------------------------------------------------------------------------

function TrainingService.isTraining(player: Player): boolean
	local st = states[player]
	return st ~= nil and st.inHall == true
end

function TrainingService.hallCFrame(): CFrame
	return hallCF
end

TrainingService._state = function(player: Player)
	return states[player]
end
TrainingService._build = function()
	build()
	watchTargets()
end
TrainingService._dummies = function()
	return dummies
end
TrainingService._onClient = onClient

function TrainingService.Init(registry)
	Services = registry
end

function TrainingService.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		local r = Instance.new("RemoteEvent")
		r.Name = REMOTE_NAME
		r.Parent = remotes
		remote = r
	end
	;(remote :: RemoteEvent).OnServerEvent:Connect(onClient)
	-- extra listeners on the combat remotes (CombatService keeps its own; these only read)
	Net.event("MeleeSwing").OnServerEvent:Connect(onSwingStart)
	Net.event("RangedRelease").OnServerEvent:Connect(onRanged)

	-- the Blender set: the place does not carry it yet, so it is built here at start (TrainRideService asks too; the
	-- second caller waits for the first)
	local flow = (Config :: any).TrainFlow
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local builder = worldGen and worldGen:FindFirstChild("TrainingCentreBuilder")
	if builder and builder:IsA("ModuleScript") and not (type(flow) == "table" and flow.BlenderSet == false) then
		local ok, err = pcall(function()
			require(builder).ensure()
		end)
		if not ok then
			warn("[TrainingService] TrainingCentreBuilder.ensure failed: " .. tostring(err))
		end
	end
	build()
	watchTargets()

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	-- at the call borrowed items go back (they never reach the red room's plinths)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState:GetAttribute("Phase") == "Countdown" then
			for player, st in pairs(states) do
				if st.drill then
					pcall(finishDrill, player, false, string.upper(st.drill.name) .. " · the call")
				end
				TrainingService.reclaim(player, "The call")
			end
		end
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return TrainingService
