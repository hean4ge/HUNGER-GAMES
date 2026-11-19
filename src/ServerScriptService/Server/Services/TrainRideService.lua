--[[
	TrainRideService - the road from the station to the red room (docs/design/TrainingAndLoadup.md sections 2 and 5).
	Config.TrainFlow.Enabled = false (or no train lobby in the place) turns all of it off and RoundService runs today's
	flow: Intermission -> Countdown.

	The order with it on (GameState.Phase stays "Intermission" all the way to the call, so every lobby screen, the music
	and the HUD behave as they do today; the steps are GameState.TrainStage):
	  Station   the Intermission. Train A (workspace.Lobby) stands parked; TrainSceneryController holds still.
	  Ride      RideTime s (SoloRideTime alone). The doors seal, the station slides away, the country, the tunnel
	            (TrainRideController draws all of it on each client). MoveLead s before its end, in the dark, every
	            character in train A is moved onto the platform at the side door of train B (the copy parked at the
	            Training Centre) nearest its place, turned toward the nearest arch into the hall; train B's doors open
	            in the same dark (its gangway gaps are wider, they are its doors). The client carries its camera over
	            and turns it to the arch (remote TrainRide "arrive", with `look`) and is in first person from then on.
	  Training  TrainingTime s (SoloTrainingTime alone). The platform lamps come on, train B's doors open. Players
	            have AtTrainingCentre = true. The launch doors open DoorsOpenBefore s before the call (at once when alone):
	            the first `places` in the hall (least recently played first) are held (TrainHeld = true); others see
	            the doors shut (their client keeps the leaves closed for them) and go back to train A at the call.
	            The call comes early: ReadyLead s after every held contender has stood on the disc ReadyHold s
	            (never before MinTraining s of training); alone, ReadyHold s after standing on it.
	  (call)    RoundService.enterCountdown, unchanged (held players are picked first). finish() sends everyone else
	            back to train A and the stage ends.
	Late joiners: during the Station and the Ride they ride with train A; during Training they are put on platform B
	(the hall is streamed in for them first). Skipping: anyone with Rode = true may hold Space (TrainRideController)
	during the Ride; they are put on platform B at once and train straight away.
	The Training Centre: workspace.TrainingCentre when its builder has placed it (its parts named PlatformB, LaunchDoors,
	RedRoom / Disc are used when present); otherwise a Part stand-in hall at Config.TrainFlow.HallCentre, built here.

	API (RoundService):
	  enabled() -> boolean                    the switch is on and the train and hall exist
	  stage() -> string                        "" | "Ride" | "Training"
	  begin(t, solo, places, rank)             the doors seal (rank(a, b) -> a goes before b)
	  step(t, waiting) -> "call" | "cancel" | nil
	  callAt() -> number
	  isHeld(player) -> boolean
	  finish(contenders: { [Player]: any }?)   after the call or a cancel: everyone else back to train A
	  timing(solo) -> ride, training, doorsBefore
	Player attributes: AtTrainingCentre, TrainHeld, Rode, InRedRoom, RedRoomReady.
	GameState attributes: TrainStage, TrainRideStart, TrainRideEnd, TrainCallAt, TrainDoorsAt, TrainDoorsOpen,
	TrainSolo, TrainMoveAt.
]]
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local TrainRideService = {}

local REMOTE = "TrainRide"
local GAP = 4 -- studs each gangway gap of train B is wider than train A's (the gap is its door)
local MOVE_LEAD = 0.6 -- the move happens this long before the ride ends (in the dark)
local SOLO_GROUP = "TrainSolo" -- characters in the red room: they never collide with each other
local WATCH_EVERY = 0.25

local Services = nil
local remote: RemoteEvent? = nil
local built = false
local station: Model? = nil -- workspace.TrainStationB (train B, and the stand-in platform and hall)
local trainB: Model? = nil
local frameA = CFrame.identity -- train A's pivot (workspace.Lobby.WorldPivot)
local frameB = CFrame.identity -- train B's pivot (same local frame)
local gangwaysZ: { number } = {} -- train A's gangway centres, local z, ascending
local carSpans: { { z0: number, z1: number, shift: number } } = {}
local platformSpots: { CFrame } = {}
local vestibulesZ: { number } = {} -- train B's vestibule (side door) centres, local z (frameB)
local hallEntry: Vector3? = nil -- where the platform's way into the hall is (GameState.TrainHallEntry: the marker)
local arches: { Vector3 } = {} -- the hall's ways in from the platform (the set's Arch_* markers, else the stand-in's)
local regions: { { cf: CFrame, size: Vector3 } } = {} -- the station and the hall (late joiners, rescue, AtTrainingCentre)
local hallFloorY = 200
local redRoom: { cf: CFrame, size: Vector3 }? = nil
local disc: BasePart? = nil
local launchDoors: Instance? = nil

local st = {
	stage = "",
	solo = false,
	rideStart = 0,
	rideEnd = 0,
	moveAt = 0,
	moved = false,
	streamed = false,
	trainingStart = 0,
	doorsAt = 0,
	doorsOpen = false,
	callAt = 0,
	early = false,
	places = 48,
	rank = nil :: ((Player, Player) -> boolean)?,
	held = {} :: { [Player]: boolean },
	riders = {} :: { [Player]: boolean },
	skipped = {} :: { [Player]: boolean },
	readySince = {} :: { [Player]: number },
	strayA = {} :: { [Player]: number },
	lastWatch = 0,
	holdLast = nil :: number?, -- (Studio test: TrainHoldTest)
}

-- Helpers ------------------------------------------------------------------------------------------------------------

local function cfg(): { [string]: any }
	local flow = (Config :: any).TrainFlow or {}
	-- Studio test: GameState.TrainFlowLive = true runs the real timings instead of the short Studio ones
	if Config.IsStudio and type(flow.Live) == "table" and GameState:GetAttribute("TrainFlowLive") == true then
		return flow.Live
	end
	return flow
end

local function num(key: string, default: number): number
	local v = tonumber(cfg()[key])
	return if v then v else default
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setAttr(name: string, value: any)
	if GameState:GetAttribute(name) ~= value then
		GameState:SetAttribute(name, value)
	end
end

local function fire(player: Player, payload: { [string]: any })
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function rootOf(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, root, humanoid
end

local function inBox(cf: CFrame, size: Vector3, p: Vector3): boolean
	local l = cf:PointToObjectSpace(p)
	return math.abs(l.X) <= size.X / 2 and math.abs(l.Y) <= size.Y / 2 and math.abs(l.Z) <= size.Z / 2
end

-- inside train A (its local frame: x across, z along, the floor at y 0)
local function inTrainA(p: Vector3): boolean
	local l = frameA:PointToObjectSpace(p)
	return math.abs(l.X) <= 11.5 and l.Y > -4 and l.Y < 16 and l.Z > -100 and l.Z < 174
end

local function inStation(p: Vector3): boolean
	for _, r in ipairs(regions) do
		if inBox(r.cf, r.size, p) then
			return true
		end
	end
	return false
end

local function inArenaRound(player: Player): boolean
	return player:GetAttribute("InArena") == true or player:GetAttribute("Alive") == true
end

-- the shift (local z) train B adds at a point of train A: the gangway gaps grow by GAP each
local function shiftAt(localZ: number): number
	for i, gz in ipairs(gangwaysZ) do
		if math.abs(localZ - gz) <= 1.6 then
			return carSpans[i].shift + GAP / 2
		end
	end
	local best, bestD = 0, math.huge
	for _, span in ipairs(carSpans) do
		local d = if localZ < span.z0 then span.z0 - localZ elseif localZ > span.z1 then localZ - span.z1 else 0
		if d < bestD then
			best, bestD = span.shift, d
		end
	end
	return best
end

local function transformFor(p: Vector3): CFrame
	local l = frameA:PointToObjectSpace(p)
	return frameB * CFrame.new(0, 0, shiftAt(l.Z)) * frameA:Inverse()
end

local function rootOffset(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2
end

local function placeAt(player: Player, ground: CFrame)
	local character, root, humanoid = rootOf(player)
	if not character or not root or not humanoid then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(ground + Vector3.new(0, rootOffset(humanoid, root) + 0.05, 0))
end

local function platformSpot(): CFrame
	if #platformSpots == 0 then
		return CFrame.new(num("HallX", 8800), hallFloorY, 3080)
	end
	local base = platformSpots[math.random(1, #platformSpots)]
	return base * CFrame.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 2)
end

local function trainASpot(): CFrame
	local lobby = workspace:FindFirstChild("Lobby")
	local spawns = lobby and lobby:FindFirstChild("Spawns")
	local list = if spawns then spawns:GetChildren() else {}
	if #list > 0 then
		local s = list[math.random(1, #list)]
		if s:IsA("BasePart") then
			local look = Vector3.new(s.CFrame.LookVector.X, 0, s.CFrame.LookVector.Z)
			local p = s.Position + Vector3.new(0, s.Size.Y / 2, 0)
			return CFrame.lookAt(p, p + (if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, 1)))
		end
	end
	return frameA
end

local function setCollisionSolo(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local group = if on then SOLO_GROUP else "Default"
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d.CollisionGroup ~= group then
			d.CollisionGroup = group
		end
	end
end

local function setPlayerFlags(player: Player, training: boolean)
	if player:GetAttribute("AtTrainingCentre") ~= training then
		player:SetAttribute("AtTrainingCentre", training)
	end
	if not training then
		if player:GetAttribute("InRedRoom") then
			player:SetAttribute("InRedRoom", false)
			setCollisionSolo(player, false)
		end
		if player:GetAttribute("RedRoomReady") then
			player:SetAttribute("RedRoomReady", false)
		end
	end
end

-- Move a player to a spot far away: a short dark cover on their screen, the area streamed in first.
local function sendTo(player: Player, ground: CFrame, why: string)
	fire(player, { kind = "fade", time = 0.4, why = why })
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, ground.Position, 4)
		task.wait(0.15)
		placeAt(player, ground)
	end)
end

-- Building ----------------------------------------------------------------------------------------------------------

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function strip(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("BaseScript") or d:IsA("ModuleScript")
			or d:IsA("SpawnLocation") then
			d:Destroy()
		else
			for _, tag in ipairs(CollectionService:GetTags(d)) do
				CollectionService:RemoveTag(d, tag)
			end
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(root)) do
		CollectionService:RemoveTag(root, tag)
	end
end

-- Train B: the cars of workspace.Lobby, copied at the platform, each car moved along so its gangway gap is a door.
local function buildTrainB(lobby: Model, parent: Instance, at: CFrame)
	frameA = lobby.WorldPivot
	frameB = at
	-- cars in order along the train
	local cars = {}
	for _, name in ipairs({ "Nose", "Lounge", "Dining", "Observation" }) do
		local car = lobby:FindFirstChild(name)
		if car and car:IsA("Model") then
			local cf, size = car:GetBoundingBox()
			local lz = frameA:PointToObjectSpace(cf.Position).Z
			table.insert(cars, { model = car, z = lz, half = size.Z / 2 })
		end
	end
	table.sort(cars, function(a, b)
		return a.z < b.z
	end)
	local loungeIndex = 1
	for i, c in ipairs(cars) do
		if c.model.Name == "Lounge" then
			loungeIndex = i
		end
	end
	table.clear(carSpans)
	for i, c in ipairs(cars) do
		table.insert(carSpans, { z0 = c.z - c.half, z1 = c.z + c.half, shift = (i - loungeIndex) * GAP, model = c.model })
	end
	table.clear(gangwaysZ)
	for _, child in ipairs(lobby:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, 7) == "Gangway" then
			table.insert(gangwaysZ, frameA:PointToObjectSpace(child:GetPivot().Position).Z)
		end
	end
	table.sort(gangwaysZ)
	-- (the gangway between car i and i + 1 takes carSpans[i].shift + GAP / 2: one gangway between each pair)

	local model = Instance.new("Model")
	model.Name = "TrainB"
	local bodyColour = Color3.fromRGB(120, 28, 26)
	for _, span in ipairs(carSpans) do
		local copy = span.model:Clone()
		strip(copy)
		local move = frameB * CFrame.new(0, 0, span.shift) * frameA:Inverse()
		copy:PivotTo(move * copy:GetPivot())
		copy.Parent = model
		local body = copy:FindFirstChild("TrainLobby_" .. span.model.Name .. "_Body")
		if body and body:IsA("BasePart") then
			bodyColour = body.Color
		end
	end
	-- the rest of the train's insides (lamps, the rack, the wheel, the boards), each by where it stands
	for _, name in ipairs({ "Lamps", "Landmarks", "Rewards", "LoadoutStation" }) do
		local source = lobby:FindFirstChild(name)
		if source then
			local copy = source:Clone()
			strip(copy)
			if copy:IsA("Model") then
				local cf = copy:GetBoundingBox()
				local move = transformFor(cf.Position)
				copy:PivotTo(move * copy:GetPivot())
			else
				for _, d in ipairs(copy:GetChildren()) do
					if d:IsA("BasePart") then
						d.CFrame = transformFor(d.Position) * d.CFrame
					elseif d:IsA("Model") then
						d:PivotTo(transformFor(d:GetBoundingBox().Position) * d:GetPivot())
					end
				end
			end
			copy.Parent = model
		end
	end
	-- the vestibules: each gangway gap is a small room with the door on the platform side (+X, local)
	local doors = Instance.new("Folder")
	doors.Name = "Doors"
	doors.Parent = model
	local dark = Color3.fromRGB(40, 30, 28)
	table.clear(platformSpots)
	table.clear(vestibulesZ)
	for i, gz in ipairs(gangwaysZ) do
		local shift = (carSpans[i] and carSpans[i].shift or 0) + GAP / 2
		local zc = gz + shift
		local gapLen = 3 + GAP
		local v = Instance.new("Model")
		v.Name = "Vestibule" .. i
		local f = function(x, y, z)
			return frameB * CFrame.new(x, y, zc + z)
		end
		local floor = part("Floor", Vector3.new(21, 0.6, gapLen), f(0, -0.3, 0), Color3.fromRGB(58, 46, 40), Enum.Material.WoodPlanks, v)
		floor.CanCollide = true
		part("Roof", Vector3.new(21, 1.2, gapLen), f(0, 11.4, 0), bodyColour, Enum.Material.SmoothPlastic, v)
		part("Far", Vector3.new(0.6, 11, gapLen), f(-10.2, 5.2, 0), bodyColour, Enum.Material.SmoothPlastic, v)
		part("Lintel", Vector3.new(0.6, 3, gapLen), f(10.2, 9.9, 0), bodyColour, Enum.Material.SmoothPlastic, v)
		-- the two leaves (8.4 high): they slide apart along the train on the client (TrainRideController), into the car
		-- walls on each side; until then they are a wall
		for k, side in ipairs({ -1, 1 }) do
			local leaf = part("Leaf" .. (if k == 1 then "A" else "B"), Vector3.new(0.4, 8.4, gapLen / 2),
				f(10.2, 4.2, side * gapLen / 4), Color3.fromRGB(150, 38, 32), Enum.Material.SmoothPlastic, v)
			leaf.CanCollide = true
			leaf:SetAttribute("SlideAxis", "Z")
			leaf:SetAttribute("Slide", side * (gapLen / 2 - 0.2))
			CollectionService:AddTag(leaf, "TrainDoorLeaf")
		end
		local lamp = part("Lamp", Vector3.new(0.3, 0.2, 1.2), f(0, 10.6, 0), Color3.fromRGB(255, 214, 170), Enum.Material.Neon, v)
		local light = Instance.new("PointLight")
		light.Range = 10
		light.Brightness = 0.8
		light.Color = Color3.fromRGB(255, 196, 140)
		light.Parent = lamp
		for _, d in ipairs(v:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Floor" and string.sub(d.Name, 1, 4) ~= "Leaf" then
				d.CanCollide = d.Name ~= "Lamp"
			end
		end
		v.Parent = doors
		table.insert(vestibulesZ, zc)
		-- where a late joiner or a skipper stands: on the platform just off the door, facing the hall (local +X)
		local out = frameB * CFrame.new(16, 0, zc)
		table.insert(platformSpots, CFrame.lookAt(out.Position, (frameB * CFrame.new(40, 0, zc)).Position))
	end
	model.WorldPivot = frameB
	model.Parent = parent
	trainB = model
end

-- The stand-in Training Centre (Parts): the platform, the hall shell with its arches and big screen, the launch doors,
-- the corridor and a plain red room with the disc. Hall coordinates as in the design page section 3.1.
-- `other` = TrainingService's own stand-in shell (workspace.TrainingStations.TrainingStandIn: floor, 14-high walls,
-- a closed LaunchDoors block, its PlatformB) when it has built one: then only what it lacks is built here (no floor,
-- walls or roof; its closed door block is hidden and these sliding doors stand in its gap; its platform is used).
-- `roomOnly` (the Blender TrainingCentre stands: it has the platform, the hall, the doors and the corridor): only the
-- red room is built, behind the corridor's end (its south wall at hall z -87.5).
local function buildStandIn(parent: Instance, centre: Vector3, other: Instance?, roomOnly: boolean?)
	local m = Instance.new("Model")
	m.Name = if roomOnly then "RedRoomStandIn" else "HallStandIn"
	local shell = other == nil and not roomOnly
	local cz = -75 - 1 - 6 -- centre z of the corridor (it runs from the wall to 12 studs north)
	local teal = Color3.fromRGB(78, 112, 118)
	local tealDark = Color3.fromRGB(52, 74, 79)
	local floorA = Color3.fromRGB(104, 116, 122)
	local floorB = Color3.fromRGB(150, 158, 162)
	local steel = Color3.fromRGB(70, 74, 80)
	local oxblood = Color3.fromRGB(92, 28, 30)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(centre + Vector3.new(x, y, z))
	end
	local function solid(name, size, cf, color, mat)
		local p = part(name, size, cf, color, mat, m)
		p.CanCollide = true
		return p
	end
	if not roomOnly then
	if shell then
	-- the floor: a chequer of 30-stud squares (two tones), 220 x 150
	local floor = Instance.new("Model")
	floor.Name = "Floor"
	floor.Parent = m
	for ix = 0, 6 do
		for iz = 0, 4 do
			local w = if ix == 6 then 40 else 30
			local x0 = -110 + ix * 30
			local p = part("Tile", Vector3.new(w, 1, 30), at(x0 + w / 2, -0.5, -75 + iz * 30 + 15),
				if (ix + iz) % 2 == 0 then floorA else floorB, Enum.Material.Fabric, floor)
			p.CanCollide = true
		end
	end
	-- walls (36 high), the north one with the launch doors' opening (8 wide, 14 high), the south one with three arches
	solid("WallWest", Vector3.new(2, 36, 150), at(-111, 18, 0), teal, Enum.Material.Fabric)
	solid("WallEast", Vector3.new(2, 36, 150), at(111, 18, 0), teal, Enum.Material.Fabric)
	solid("WallNorthW", Vector3.new(106, 36, 2), at(-57, 18, -76), teal, Enum.Material.Fabric)
	solid("WallNorthE", Vector3.new(106, 36, 2), at(57, 18, -76), teal, Enum.Material.Fabric)
	solid("WallNorthTop", Vector3.new(8, 22, 2), at(0, 25, -76), teal, Enum.Material.Fabric)
	local arches = { -40, 0, 40 }
	local x0 = -110
	for i, ax in ipairs(arches) do
		local left = ax - 7
		solid("WallSouth" .. i, Vector3.new(left - x0, 36, 2), at((x0 + left) / 2, 18, 76), teal, Enum.Material.Fabric)
		solid("ArchTop" .. i, Vector3.new(14, 22, 2), at(ax, 25, 76), teal, Enum.Material.Fabric)
		x0 = ax + 7
	end
	solid("WallSouthEnd", Vector3.new(110 - x0, 36, 2), at((x0 + 110) / 2, 18, 76), teal, Enum.Material.Fabric)
	-- the white diagonal ribs on the long walls (one colour accent, matte)
	for k = 0, 9 do
		local z = -67 + k * 15
		for _, sx in ipairs({ -1, 1 }) do
			part("Rib", Vector3.new(0.4, 30, 0.8), at(sx * 109.8, 18, z) * CFrame.Angles(math.rad(28), 0, 0),
				Color3.fromRGB(214, 220, 218), Enum.Material.SmoothPlastic, m)
		end
	end
	local roof = solid("Roof", Vector3.new(224, 2, 154), at(0, 37, 0), tealDark, Enum.Material.SmoothPlastic)
	roof.CastShadow = true
	-- downlights: round panels with lights (no shadows: phones)
	for ix = -2, 2 do
		for iz = -1, 1 do
			local lamp = part("Downlight", Vector3.new(6, 0.4, 6), at(ix * 42, 35.8, iz * 45), Color3.fromRGB(236, 240, 240),
				Enum.Material.Neon, m)
			lamp.Shape = Enum.PartType.Cylinder
			lamp.Size = Vector3.new(0.4, 6, 6)
			lamp.CFrame = at(ix * 42, 35.8, iz * 45) * CFrame.Angles(0, 0, math.rad(90))
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Left -- after the turn the cylinder's axis is vertical: +X local is up, -X down
			light.Angle = 120
			light.Range = 46
			light.Brightness = 1.4
			light.Color = Color3.fromRGB(232, 240, 244)
			light.Shadows = false
			light.Parent = lamp
		end
	end
	else
		-- TrainingService's shell: its closed door block gives way to the sliding doors; its 12-wide gap narrows to 8
		local block = other and other:FindFirstChild("LaunchDoors")
		if block and block:IsA("BasePart") then
			block.Transparency = 1
			block.CanCollide = false
			block.CanQuery = false
		end
		for _, sx in ipairs({ -1, 1 }) do
			solid("DoorJamb", Vector3.new(2, 14, 2), at(sx * 5, 7, -76), teal, Enum.Material.Fabric)
		end
	end
	-- the big screen over the launch doors (over the other shell's lower wall when that one stands)
	local screen = part("BigScreen", Vector3.new(28, 9, 0.6), at(0, if shell then 26 else 19, -74.6), Color3.fromRGB(18, 22, 24), Enum.Material.SmoothPlastic, m)
	screen:SetAttribute("TrainScreen", true)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(1400, 450)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = screen
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "THE TRAINING CENTRE"
	label.TextColor3 = Color3.fromRGB(226, 232, 230)
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.Parent = gui
	-- orange marks only what you can use: here, the launch doors' frame lamp turns red when they open
	-- the launch doors: two steel leaves (4 x 14) that slide sideways into the wall
	local doorsModel = Instance.new("Model")
	doorsModel.Name = "LaunchDoors"
	doorsModel.Parent = m
	for k, side in ipairs({ -1, 1 }) do
		local leaf = part("Leaf" .. (if k == 1 then "A" else "B"), Vector3.new(4, 14, 1), at(side * 2, 7, -75.6), steel,
			Enum.Material.DiamondPlate, doorsModel)
		leaf.CanCollide = true
		leaf:SetAttribute("SlideAxis", "X")
		leaf:SetAttribute("Slide", side * 4)
		part("Panel", Vector3.new(3, 10, 0.2), at(side * 2, 7.5, -75), oxblood, Enum.Material.SmoothPlastic, leaf).Anchored = true
	end
	local lamp = part("DoorLamp", Vector3.new(2.4, 0.8, 0.8), at(0, 15.2, -74.9), Color3.fromRGB(70, 20, 20), Enum.Material.Neon, doorsModel)
	lamp:SetAttribute("DoorLamp", true)
	-- the corridor: 6 wide, 9 high, 12 long, oxblood with red strips at floor level
	solid("CorridorFloor", Vector3.new(6, 1, 12), at(0, -0.5, cz), Color3.fromRGB(84, 90, 98), Enum.Material.DiamondPlate)
	solid("CorridorW", Vector3.new(1, 9, 12), at(-3.5, 4.5, cz), oxblood, Enum.Material.SmoothPlastic)
	solid("CorridorE", Vector3.new(1, 9, 12), at(3.5, 4.5, cz), oxblood, Enum.Material.SmoothPlastic)
	solid("CorridorRoof", Vector3.new(8, 1, 12), at(0, 9.5, cz), oxblood, Enum.Material.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		local strip = part("Strip", Vector3.new(0.2, 0.3, 12), at(sx * 2.9, 0.4, cz), Color3.fromRGB(200, 40, 36), Enum.Material.Neon, m)
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 60, 50)
		l.Range = 8
		l.Brightness = 0.7
		l.Parent = strip
	end
	end -- not roomOnly
	-- the red room: 30 x 24, 22 high; the disc at the centre (8 across) under a hex frame
	local rz = cz - 6 - 12 -- room centre: it runs 24 studs north of the corridor
	local room = Instance.new("Model")
	room.Name = "RedRoom"
	room.Parent = m
	local function rsolid(name, size, cf, color, mat)
		local p = part(name, size, cf, color, mat, room)
		p.CanCollide = true
		return p
	end
	rsolid("Floor", Vector3.new(30, 1, 24), at(0, -0.5, rz), Color3.fromRGB(84, 90, 98), Enum.Material.DiamondPlate)
	rsolid("WallN", Vector3.new(32, 22, 1), at(0, 11, rz - 12.5), Color3.fromRGB(122, 30, 30), Enum.Material.SmoothPlastic)
	rsolid("WallW", Vector3.new(1, 22, 24), at(-15.5, 11, rz), Color3.fromRGB(122, 30, 30), Enum.Material.SmoothPlastic)
	rsolid("WallE", Vector3.new(1, 22, 24), at(15.5, 11, rz), Color3.fromRGB(122, 30, 30), Enum.Material.SmoothPlastic)
	rsolid("WallS_W", Vector3.new(12, 22, 1), at(-9, 11, rz + 12.5), Color3.fromRGB(122, 30, 30), Enum.Material.SmoothPlastic)
	rsolid("WallS_E", Vector3.new(12, 22, 1), at(9, 11, rz + 12.5), Color3.fromRGB(122, 30, 30), Enum.Material.SmoothPlastic)
	rsolid("WallS_Top", Vector3.new(6, 13, 1), at(0, 15.5, rz + 12.5), Color3.fromRGB(122, 30, 30), Enum.Material.SmoothPlastic)
	rsolid("Roof", Vector3.new(32, 1, 26), at(0, 22.5, rz), Color3.fromRGB(60, 18, 18), Enum.Material.SmoothPlastic)
	local d = part("Disc", Vector3.new(0.3, 8, 8), at(0, 0.15, rz) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 148, 150),
		Enum.Material.SmoothPlastic, room)
	d.Shape = Enum.PartType.Cylinder
	d.CanCollide = false
	d:SetAttribute("RedRoomDisc", true)
	for k = 0, 5 do
		local a = math.rad(k * 60)
		local r = 5.2
		part("Hex", Vector3.new(6, 0.6, 0.6), at(math.cos(a) * r, 20.5, rz + math.sin(a) * r) * CFrame.Angles(0, -a + math.rad(90), 0),
			Color3.fromRGB(60, 120, 118), Enum.Material.Metal, room)
	end
	local glow = part("RoomLight", Vector3.new(1, 1, 1), at(0, 19, rz), Color3.fromRGB(255, 90, 80), Enum.Material.SmoothPlastic, room)
	glow.Transparency = 1
	local rl = Instance.new("PointLight")
	rl.Color = Color3.fromRGB(255, 80, 70)
	rl.Range = 30
	rl.Brightness = 1.2
	rl.Parent = glow
	if roomOnly then
		-- the sill between the set's corridor (it ends at z -87) and the room's doorway
		rsolid("Sill", Vector3.new(8, 1, 2), at(0, -0.5, -87.5), Color3.fromRGB(84, 90, 98), Enum.Material.DiamondPlate)
		m.Parent = parent
		return m
	end
	-- the platform: 320 long, 14.5 wide, its top level with the train's floor; lamp banks that come on at arrival
	local pz = 75 + 1 + 7.25 -- the platform's centre: from the hall's south wall to the train's side
	local otherPlatform = other and other:FindFirstChild("PlatformB")
	if otherPlatform and otherPlatform:IsA("BasePart") then
		pz = otherPlatform.Position.Z - centre.Z
		-- (the other shell's platform is 220 long: the train is longer, so its ends get this platform's extensions)
		for _, sx in ipairs({ -1, 1 }) do
			solid("PlatformEndB", Vector3.new(50, 2, otherPlatform.Size.Z), at(sx * 135, -1, pz), Color3.fromRGB(64, 66, 70), Enum.Material.Concrete)
		end
	else
		local platform = solid("PlatformB", Vector3.new(320, 4, 14.5), at(0, -2, pz), Color3.fromRGB(64, 66, 70), Enum.Material.Concrete)
		platform:SetAttribute("PlatformB", true)
	end
	local edgeZ = if otherPlatform and otherPlatform:IsA("BasePart") then pz + otherPlatform.Size.Z / 2 - 0.65 else pz + 6.6
	part("Edge", Vector3.new(320, 0.08, 0.8), at(0, 0.04, edgeZ), Color3.fromRGB(196, 170, 96), Enum.Material.SmoothPlastic, m)
	local lamps = Instance.new("Folder")
	lamps.Name = "PlatformLamps"
	lamps.Parent = m
	for k = 0, 7 do
		local x = -140 + k * 40
		solid("Post", Vector3.new(0.6, 12, 0.6), at(x, 6, pz - 4), Color3.fromRGB(40, 42, 46), Enum.Material.Metal)
		local head = part("LampHead", Vector3.new(3, 0.5, 1.2), at(x, 12, pz - 3.4), Color3.fromRGB(40, 40, 40), Enum.Material.Neon, lamps)
		head:SetAttribute("Bank", k)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 110
		light.Range = 24
		light.Brightness = 1.6
		light.Color = Color3.fromRGB(255, 226, 190)
		light.Shadows = false
		light.Enabled = false
		light.Parent = head
	end
	-- a roof over the platform and the train, and the tunnel's dark far wall behind the train (no sky through the windows)
	solid("PlatformRoof", Vector3.new(330, 1, 44), at(0, 18, pz + 9), Color3.fromRGB(36, 38, 42), Enum.Material.SmoothPlastic)
	solid("TrackWall", Vector3.new(330, 20, 1), at(0, 8, pz + 7.25 + 21 + 3), Color3.fromRGB(30, 31, 34), Enum.Material.Concrete)
	solid("TrackBed", Vector3.new(330, 1, 26), at(0, -4.5, pz + 7.25 + 13), Color3.fromRGB(34, 32, 30), Enum.Material.Slate)
	for _, sx in ipairs({ -1, 1 }) do
		solid("PlatformEnd", Vector3.new(1, 20, 44), at(sx * 165, 8, pz + 9), Color3.fromRGB(30, 31, 34), Enum.Material.Concrete)
	end
	m.Parent = parent
	return m
end

local function findNamed(root: Instance, names: { string }, className: string?): Instance?
	for _, d in ipairs(root:GetDescendants()) do
		if (not className or d:IsA(className)) and table.find(names, d.Name) then
			return d
		end
	end
	return nil
end

local function build()
	if built then
		return
	end
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby or not lobby:IsA("Model") or lobby:GetAttribute("TrainLobby") ~= true then
		warn("[TrainRideService] workspace.Lobby is not the train lobby: the train flow is off")
		return
	end
	local centre = (cfg().HallCentre :: Vector3?) or Vector3.new(8800, 200, 3000)
	hallFloorY = centre.Y
	local holder = Instance.new("Model")
	holder.Name = "TrainStationB"
	holder.ModelStreamingMode = Enum.ModelStreamingMode.Default
	-- the Blender set (built here at runtime when the place does not carry it: TrainingCentreBuilder.ensure)
	local worldGen = game:GetService("ServerStorage"):FindFirstChild("WorldGen")
	local builder = worldGen and worldGen:FindFirstChild("TrainingCentreBuilder")
	if builder and builder:IsA("ModuleScript") and cfg().BlenderSet ~= false then
		local okB, errB = pcall(function()
			require(builder).ensure()
		end)
		if not okB then
			warn("[TrainRideService] TrainingCentreBuilder.ensure failed: " .. tostring(errB))
		end
	end
	local hall = workspace:FindFirstChild("TrainingCentre")
	local standIn: Instance? = nil
	local platformPart: BasePart? = nil
	local blenderSet = hall ~= nil and hall:GetAttribute("BlenderSet") == true
	local trainMarker: BasePart? = nil
	if blenderSet and hall then
		-- the set's own names: the platform's collider, its doors, the TrainB marker; the red room is ours (behind the
		-- corridor) until the Blender red room is placed
		local p = hall:FindFirstChild("TC_Platform_Platform_Col", true)
		platformPart = if p and p:IsA("BasePart") then p else nil
		launchDoors = hall:FindFirstChild("LaunchDoors")
		local markers = hall:FindFirstChild("Markers")
		local tm = markers and markers:FindFirstChild("TrainB")
		trainMarker = if tm and tm:IsA("BasePart") then tm else nil
		local d = findNamed(hall, { "Disc", "RedRoomDisc", "LaunchDisc" }, "BasePart")
		if d and d:IsA("BasePart") and d.Parent and d.Parent.Name ~= "Markers" then
			disc = d
		end
		if not disc then
			local room = buildStandIn(holder, centre, nil, true)
			local dd = room:FindFirstChild("Disc", true)
			disc = if dd and dd:IsA("BasePart") then dd else nil
			local cf, size = room:GetBoundingBox()
			redRoom = { cf = cf * CFrame.new(0, 0, 3), size = size + Vector3.new(0, 4, 6) }
		end
	elseif hall then
		local p = findNamed(hall, { "PlatformB", "Platform_B", "ArrivalPlatform" }, "BasePart")
		platformPart = if p and p:IsA("BasePart") then p else nil
		launchDoors = findNamed(hall, { "LaunchDoors", "LaunchDoor", "Doors_Launch" })
		local d = findNamed(hall, { "Disc", "RedRoomDisc", "LaunchDisc" }, "BasePart")
		disc = if d and d:IsA("BasePart") then d else nil
		local rr = findNamed(hall, { "RedRoom", "LaunchRedRoom" })
		if rr and rr:IsA("Model") then
			local cf, size = rr:GetBoundingBox()
			redRoom = { cf = cf, size = size + Vector3.new(0, 4, 0) }
		end
	end
	if blenderSet and (not platformPart or not launchDoors or not disc) then
		warn(string.format("[TrainRideService] the TrainingCentre set lacks platform %s, doors %s, disc %s", tostring(platformPart ~= nil),
			tostring(launchDoors ~= nil), tostring(disc ~= nil)))
	end
	if not blenderSet and (not platformPart or not launchDoors or not disc) then
		-- the parts the hall set does not have yet come from the stand-in (all of it when there is no set). TrainingService
		-- builds its own shell when there is no set (it starts at the same moment: a few seconds' grace to see it).
		local other: Instance? = nil
		if not hall then
			local deadline = os.clock() + 6
			repeat
				local stations = workspace:FindFirstChild("TrainingStations")
				other = stations and stations:FindFirstChild("TrainingStandIn")
				if not other then
					task.wait(0.25)
				end
			until other or os.clock() > deadline
		end
		standIn = buildStandIn(holder, centre, other)
		if not platformPart then
			local own = standIn:FindFirstChild("PlatformB")
			local theirs = other and other:FindFirstChild("PlatformB")
			platformPart = (if own and own:IsA("BasePart") then own elseif theirs and theirs:IsA("BasePart") then theirs else nil) :: BasePart?
		end
		if not launchDoors then
			launchDoors = standIn:FindFirstChild("LaunchDoors")
		end
		if not disc then
			local room = standIn:FindFirstChild("RedRoom")
			disc = room and room:FindFirstChild("Disc") :: BasePart?
			if room and room:IsA("Model") then
				local cf, size = room:GetBoundingBox()
				redRoom = { cf = cf * CFrame.new(0, 0, 3), size = size + Vector3.new(0, 4, 6) } -- the corridor's end too
			end
		end
	end
	-- train B: parked along the platform's far edge, nose west, its doors (local +X) toward the hall
	local pcf, psize = platformPart and platformPart.CFrame or CFrame.new(centre + Vector3.new(0, -2, 83.25)), platformPart and platformPart.Size or Vector3.new(320, 4, 14.5)
	local top = pcf.Position.Y + psize.Y / 2
	local farZ = pcf.Position.Z + psize.Z / 2 -- the platform's track-side edge (the hall is north of it)
	local trainCentreX = centre.X
	local midLocal = 41 -- the train's middle in its own frame (nose -101 .. tail 183, with the wider gaps)
	local origin = Vector3.new(trainCentreX - midLocal, top, if trainMarker then trainMarker.Position.Z else farZ + 10.5)
	buildTrainB(lobby, holder, CFrame.lookAt(origin, origin + Vector3.new(-1, 0, 0)))
	holder.Parent = workspace
	station = holder
	-- where the station and the hall are (late joiners, rescue, AtTrainingCentre)
	table.clear(regions)
	local cf, size = holder:GetBoundingBox()
	table.insert(regions, { cf = cf, size = size + Vector3.new(8, 40, 8) })
	if hall and hall:IsA("Model") then
		local hcf, hsize = hall:GetBoundingBox()
		table.insert(regions, { cf = hcf, size = hsize + Vector3.new(8, 40, 8) })
	end
	if not redRoom and disc then
		redRoom = { cf = disc.CFrame, size = Vector3.new(30, 24, 24) }
	end
	-- the way into the hall from the platform (the set's middle arch, else the stand-in's) and the launch doors: the
	-- client's quiet markers point at them (GameState TrainHallEntry, TrainLaunchEntry)
	local markers = hall and hall:FindFirstChild("Markers")
	table.clear(arches)
	for k = 1, 9 do
		local a = markers and markers:FindFirstChild("Arch_" .. k)
		if a and a:IsA("BasePart") then
			table.insert(arches, a.Position)
		end
	end
	if #arches == 0 then
		for _, ax in ipairs({ -40, 0, 40 }) do
			table.insert(arches, centre + Vector3.new(ax, 0, 76))
		end
	end
	local arch = markers and (markers:FindFirstChild("Arch_2") or markers:FindFirstChild("Arch_1"))
	hallEntry = if arch and arch:IsA("BasePart") then arch.Position else centre + Vector3.new(0, 0, 76)
	GameState:SetAttribute("TrainHallEntry", hallEntry)
	for k, a in ipairs(arches) do
		GameState:SetAttribute("TrainHallArch" .. k, a) -- (the client's marker points at the nearest one)
	end
	local lm = markers and markers:FindFirstChild("LaunchDoors")
	local launchAt = if lm and lm:IsA("BasePart") then lm.Position
		elseif launchDoors and launchDoors:IsA("Model") then launchDoors:GetPivot().Position
		elseif launchDoors and launchDoors:IsA("BasePart") then launchDoors.Position
		else centre + Vector3.new(0, 0, -75)
	GameState:SetAttribute("TrainLaunchEntry", Vector3.new(launchAt.X, hallFloorY, launchAt.Z))
	built = true
	print(string.format("[TrainRideService] train B and %s ready at (%d, %d, %d)", if hall then "the TrainingCentre" else "the stand-in hall",
		centre.X, centre.Y, centre.Z))
end

-- The ride ----------------------------------------------------------------------------------------------------------

function TrainRideService.timing(solo: boolean?): (number, number, number)
	if solo then
		return num("SoloRideTime", 15), num("SoloTrainingTime", 60), math.huge
	end
	return num("RideTime", 25), num("TrainingTime", 90), num("DoorsOpenBefore", 40)
end

function TrainRideService.enabled(): boolean
	return cfg().Enabled == true and built
end

function TrainRideService.stage(): string
	return st.stage
end

function TrainRideService.callAt(): number
	return st.callAt
end

function TrainRideService.isHeld(player: Player): boolean
	return st.held[player] == true
end

local function publish()
	setAttr("TrainStage", st.stage)
	setAttr("TrainSolo", st.solo)
	setAttr("TrainRideStart", st.rideStart)
	setAttr("TrainRideEnd", st.rideEnd)
	setAttr("TrainMoveAt", st.moveAt)
	setAttr("TrainCallAt", st.callAt)
	setAttr("TrainDoorsAt", st.doorsAt)
	setAttr("TrainDoorsOpen", st.doorsOpen)
	if trainB then
		-- train B's doors open in the dark of the move: the riders stand at them, open behind them, when it lifts
		trainB:SetAttribute("DoorsOpenAt", if st.stage == "Training" or (st.stage == "Ride" and st.moved) then st.moveAt else 0)
	end
	if launchDoors then
		launchDoors:SetAttribute("OpenAt", if st.doorsOpen then st.doorsAt else 0)
	end
end

function TrainRideService.begin(t: number, solo: boolean, places: number, rank: ((Player, Player) -> boolean)?): boolean
	if not TrainRideService.enabled() then
		return false
	end
	-- one player on the whole server rides and trains alone (the solo timings), whatever the server's minimum is (a
	-- Studio or private server can start a round with one); a second arrival makes it a full round (step)
	local here = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and not inArenaRound(player) then
			here += 1
		end
	end
	if here <= 1 then
		solo = true
	end
	local ride, training, doorsBefore = TrainRideService.timing(solo)
	st.stage = "Ride"
	st.solo = solo == true
	st.rideStart = t
	st.rideEnd = t + ride
	st.moveAt = st.rideEnd - MOVE_LEAD
	st.moved = false
	st.streamed = false
	st.trainingStart = st.rideEnd
	st.callAt = st.rideEnd + training
	st.doorsAt = if st.solo then st.rideEnd else st.callAt - math.min(doorsBefore, training)
	st.doorsOpen = false
	st.early = false
	st.places = math.max(1, places)
	st.rank = rank
	table.clear(st.held)
	table.clear(st.riders)
	table.clear(st.skipped)
	table.clear(st.readySince)
	table.clear(st.strayA)
	publish()
	print(string.format("[TrainRideService] the doors seal: ride %.1f s, training %.1f s, doors at +%.1f s, the call at +%.1f s%s",
		ride, training, st.doorsAt - t, st.callAt - t, if st.solo then " (alone)" else ""))
	return true
end

-- Arrival spots: each rider arrives standing on the platform just outside the side door of train B nearest their place
-- in the car (the doors open in the dark, so they stand open behind them), turned toward the nearest arch into the
-- hall. Twenty in front of each door (sixty in all). `look` is that arch, for the
-- client's camera. (The game's MovementController drives every character each frame, so a scripted walk off the train
-- is not possible from here: arriving at the open doors is the dependable way.)
local function arrivalSpot(localZ: number, used: { [number]: number }): (CFrame, Vector3)
	local best, bestD = 1, math.huge
	for i, zc in ipairs(vestibulesZ) do
		local d = math.abs(localZ - zc)
		if d < bestD then
			best, bestD = i, d
		end
	end
	local zc = vestibulesZ[best] or (localZ + shiftAt(localZ))
	local k = used[best] or 0
	used[best] = k + 1
	-- four abreast (2 studs apart, the door's width), five rows from the platform edge back toward the hall's wall
	local row, col = (k // 4) % 5, (k % 4) - 1.5
	local at = frameB * CFrame.new(13.5 + row * 1.9, 0, zc + col * 2.0 + (if k >= 20 then 1 else 0))
	local look = (frameB * CFrame.new(40, 0, zc)).Position
	local nearestD = math.huge
	for _, a in ipairs(arches) do
		local d = (Vector3.new(a.X, at.Y, a.Z) - at.Position).Magnitude
		if d < nearestD then
			look, nearestD = Vector3.new(a.X, at.Y, a.Z), d
		end
	end
	return CFrame.lookAt(at.Position, look), look
end

-- every character in train A goes to the platform at the door of train B nearest their place, turned toward the hall
-- (the dark covers it)
local function doMove()
	st.moved = true
	local moved = 0
	local used = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character, root, humanoid = rootOf(player)
		if character and root and humanoid and not inArenaRound(player) and inTrainA(root.Position) then
			local l = frameA:PointToObjectSpace(root.Position)
			local ground, look = arrivalSpot(l.Z, used)
			local target = ground + Vector3.new(0, rootOffset(humanoid, root) + 0.05, 0)
			local transform = target * root.CFrame:Inverse()
			st.riders[player] = true
			moved += 1
			-- the server moves the character (one authority: no double move); the client, already dark, carries its
			-- camera over when it sees its character land and turns it to `look` (the arch into the hall)
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(transform * character:GetPivot())
			player:SetAttribute("AtTrainingCentre", true) -- (first person from the arrival: CameraController)
			fire(player, { kind = "arrive", transform = transform, at = st.rideEnd, look = look })
		end
	end
	publish() -- (train B's doors open now, in the dark)
	print(string.format("[TrainRideService] the move: %d in train A -> the platform at train B's doors", moved))
end

local function openDoors(t: number)
	st.doorsOpen = true
	st.doorsAt = math.min(st.doorsAt, t)
	publish()
	print(string.format("[TrainRideService] the launch doors open; the call at +%.1f s", st.callAt - t))
end

-- the held places: the first `places` in the hall, least recently played first (RoundService's rank); a place freed
-- by a leaver or a newcomer's arrival is taken by the next in line
local function fillHeld()
	local count = 0
	for player in pairs(st.held) do
		if player.Parent ~= Players then
			st.held[player] = nil
			st.readySince[player] = nil
		else
			count += 1
		end
	end
	if count >= st.places then
		return
	end
	local waiting = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local _, root = rootOf(player)
		if root and not st.held[player] and not inArenaRound(player) and inStation(root.Position) then
			table.insert(waiting, player)
		end
	end
	if st.rank then
		table.sort(waiting, st.rank)
	end
	for _, player in ipairs(waiting) do
		if count >= st.places then
			break
		end
		st.held[player] = true
		count += 1
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local want = if st.doorsOpen then st.held[player] == true else nil
		if player:GetAttribute("TrainHeld") ~= want then
			player:SetAttribute("TrainHeld", want)
		end
	end
end

-- per player, a few times a second: late joiners and the fallen to platform B, AtTrainingCentre, the red room
local function watch(t: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local character, root = rootOf(player)
		if not character or not root or inArenaRound(player) then
			st.strayA[player] = nil
			continue
		end
		local p = root.Position
		local training = st.stage == "Training" or (st.stage == "Ride" and (st.moved or st.skipped[player] == true))
		if training and inTrainA(p) then
			-- spawned in train A after the move (joined, reset, fell): to the platform once their load has settled
			local since = st.strayA[player]
			if not since then
				st.strayA[player] = t
			elseif t - since > 0.6 then
				st.strayA[player] = nil
				sendTo(player, platformSpot(), "late")
			end
		else
			st.strayA[player] = nil
		end
		local here = inStation(p)
		if training and here and p.Y < hallFloorY - 30 then
			sendTo(player, platformSpot(), "fell") -- under the hall: back on the platform (nothing here does damage)
		end
		setPlayerFlags(player, training and here)
		-- the red room
		local inRoom = training and redRoom ~= nil and inBox(redRoom.cf, redRoom.size, p)
		if (player:GetAttribute("InRedRoom") == true) ~= inRoom then
			player:SetAttribute("InRedRoom", inRoom)
			setCollisionSolo(player, inRoom)
		end
		local onDisc = false
		if inRoom and disc then
			local flat = Vector3.new(p.X - disc.Position.X, 0, p.Z - disc.Position.Z)
			local radius = math.max(disc.Size.Y, disc.Size.Z, if disc.Shape == Enum.PartType.Cylinder then 0 else disc.Size.X) / 2
			onDisc = flat.Magnitude <= radius + 0.6 and math.abs(p.Y - disc.Position.Y) < 6
		end
		if onDisc and st.doorsOpen and st.held[player] then
			st.readySince[player] = st.readySince[player] or t
		else
			st.readySince[player] = nil
		end
		local ready = st.readySince[player] ~= nil and t - st.readySince[player] >= num("ReadyHold", 3)
		if player:GetAttribute("RedRoomReady") ~= ready then
			player:SetAttribute("RedRoomReady", ready)
		end
	end
end

-- the early call: every held contender (still here) has stood on the disc ReadyHold s
local function earlyCall(t: number)
	if st.early or not st.doorsOpen then
		return
	end
	local any = false
	for player in pairs(st.held) do
		if player.Parent == Players then
			any = true
			if player:GetAttribute("RedRoomReady") ~= true then
				return
			end
		end
	end
	if not any then
		return
	end
	st.early = true
	local at = if st.solo then t else math.max(st.trainingStart + num("MinTraining", 30), t + num("ReadyLead", 5))
	if at < st.callAt then
		st.callAt = at
		publish()
		print(string.format("[TrainRideService] everyone is on the disc: the call at +%.1f s", at - t))
	end
end

function TrainRideService.step(t: number, waiting: number): string?
	if st.stage == "" then
		return nil
	end
	if waiting <= 0 then
		return "cancel"
	end
	if st.stage == "Ride" then
		if not st.streamed and t >= st.rideEnd - math.min(10, (st.rideEnd - st.rideStart) * 0.6) then
			-- stream the hall in for every rider (the move must not land anyone in an unloaded area)
			st.streamed = true
			local target = platformSpot().Position
			for _, player in ipairs(Players:GetPlayers()) do
				if not inArenaRound(player) then
					task.spawn(pcall, player.RequestStreamAroundAsync, player, target, 8)
				end
			end
		end
		if not st.moved and t >= st.moveAt then
			doMove()
		end
		if t >= st.rideEnd then
			st.stage = "Training"
			st.trainingStart = st.rideEnd
			for player in pairs(st.riders) do
				if player.Parent == Players then
					player:SetAttribute("Rode", true)
				end
			end
			publish()
		end
	end
	-- Studio test only (pictures of the stations): GameState attribute TrainHoldTest = true holds the training clock
	-- (the doors and the call wait); clearing it lets the clock run on from where it was held
	if Config.IsStudio and st.stage == "Training" then
		local held = GameState:GetAttribute("TrainHoldTest") == true
		if held then
			st.holdLast = st.holdLast or t
			local dt = t - st.holdLast
			st.holdLast = t
			if dt > 0 then
				if not st.doorsOpen then
					st.doorsAt += dt
				end
				st.callAt += dt -- (a lone round's doors are open from the start: its call waits too)
				publish()
			end
		else
			st.holdLast = nil
		end
	end
	-- a contender arrives while one player practises: a real round at the call, with time to choose a kit
	if st.solo and waiting >= 2 then
		st.solo = false
		local floor = t + num("LateJoinFloor", 30)
		if st.callAt < floor then
			st.callAt = floor
		end
		publish()
	end
	if t - st.lastWatch >= WATCH_EVERY then
		st.lastWatch = t
		watch(t)
		if st.doorsOpen then
			fillHeld()
			earlyCall(t)
		end
	end
	if st.stage == "Training" then
		if not st.doorsOpen and t >= st.doorsAt then
			openDoors(t)
			fillHeld()
		end
		if t >= st.callAt then
			return "call"
		end
	end
	return nil
end

-- After the call (or a cancel): the stage ends; everyone left in the station or the hall goes back to train A.
function TrainRideService.finish(contenders: { [Player]: any }?)
	if st.stage == "" then
		return
	end
	local wasDoors = st.doorsOpen
	st.stage = ""
	st.doorsOpen = false
	st.early = false
	st.solo = false
	st.rideStart, st.rideEnd, st.moveAt, st.callAt, st.doorsAt = 0, 0, 0, 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		setPlayerFlags(player, false)
		if player:GetAttribute("TrainHeld") ~= nil then
			player:SetAttribute("TrainHeld", nil)
		end
		local picked = contenders ~= nil and contenders[player] ~= nil
		local _, root = rootOf(player)
		if not picked and root and not inArenaRound(player) and inStation(root.Position) then
			sendTo(player, trainASpot(), if wasDoors and contenders then "full" else "back")
		end
	end
	table.clear(st.held)
	table.clear(st.readySince)
	publish()
end

-- Remote: the skip (hold Space on the ride, once ridden this session)
local function onRemote(player: Player, payload: any)
	if type(payload) ~= "table" or not Net.rateLimit(player, REMOTE, 2, 3) then
		return
	end
	if payload.kind == "skip" then
		if st.stage ~= "Ride" or st.moved or player:GetAttribute("Rode") ~= true or st.skipped[player] then
			return
		end
		local _, root = rootOf(player)
		if not root or inArenaRound(player) or not inTrainA(root.Position) then
			return
		end
		st.skipped[player] = true
		sendTo(player, platformSpot(), "skip")
		player:SetAttribute("AtTrainingCentre", true)
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function TrainRideService.Init(registry)
	Services = registry
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder then
		local r = folder:FindFirstChild(REMOTE)
		if not r then
			r = Instance.new("RemoteEvent")
			r.Name = REMOTE
			r.Parent = folder
		end
		remote = r :: RemoteEvent
	end
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(SOLO_GROUP) then
			PhysicsService:RegisterCollisionGroup(SOLO_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(SOLO_GROUP, SOLO_GROUP, false)
	end)
	st.stage = ""
	publish()
end

function TrainRideService.Start()
	if cfg().Enabled ~= true then
		return
	end
	local ok, err = pcall(build)
	if not ok then
		warn("[TrainRideService] building train B failed: " .. tostring(err))
	end
	if remote then
		remote.OnServerEvent:Connect(onRemote)
	end
	Players.PlayerRemoving:Connect(function(player)
		st.held[player] = nil
		st.riders[player] = nil
		st.skipped[player] = nil
		st.readySince[player] = nil
		st.strayA[player] = nil
	end)
	-- a character that loads while its player is in the red room keeps the shared collision group out
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("InRedRoom", false)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			player:SetAttribute("InRedRoom", false)
		end)
	end
	local _ = Services
end

return TrainRideService
