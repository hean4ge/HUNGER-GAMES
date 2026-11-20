--[[
	TrainRideController - what each client sees and hears of the road to the arena (TrainRideService on the server;
	docs/design/TrainingAndLoadup.md sections 2 and 5). Off when Config.TrainFlow.Enabled is false.

	At the station (GameState.TrainStage "" or Station, the lobby): train A is parked. Outside the left windows a
	platform with pillars, banners, a canopy and departure boards ("TRAIN DEPARTS 0:25 · THE TRAINING CENTRE"); outside
	the right windows a second, dark train with one red lamp. The scenery stands still (Lobby.Scenery SpeedScale 0).
	These stand-ins are local Parts until the Blender station (set #1) replaces them.
	The ride (TrainStage "Ride", TrainRideStart .. TrainRideEnd): the doors seal (a chuff), the hum and the rumble
	start, the train pulls away smoothly (0 to full speed, smoothstep), the station slides off, the country (the
	scenery band at full speed), then a tunnel whose lamps pass more and more slowly as the brakes bring the train to a
	stop. The cabin lamps dim; MOVE s before the end a dark cover comes up, the server moves everyone into train B
	(remote TrainRide "arrive"), the cover lifts. Reduced Motion: nothing slides; a short fade covers the station
	leaving and the tunnel stands still around the train.
	Arrival (TrainStage "Training"): you stand on the platform at train B's open doors (they slide open, parts tagged
	TrainDoorLeaf, in the dark of the move), in first person, looking at the nearest arch into the hall; the platform
	lamps come on bank by bank with a clunk. A quiet marker ("Training Centre", over the nearest arch) shows the way in
	until you are inside; once the launch doors are open for you, "Launch" over them. The big screen counts to the launch doors, then to the call. The launch doors (a model
	named LaunchDoors, attribute OpenAt) open for you only when you hold a place (player attribute TrainHeld): for the
	others they stay shut (closed on this client, so they collide for this client only).
	The red room: while you are in it (InRedRoom) the line "Stand on the disc", then "Ready" (RedRoomReady); every
	other character in the room or its corridor is hidden on this client (the server keeps them from colliding).
	The skip: with Rode = true, hold Space (gamepad A, or the SKIP line on touch) for Config.TrainFlow.SkipHold s
	during the ride: you are put on platform B at once.
	Per-frame work: only during the ride (one BulkMoveTo of about 90 local parts); otherwise four checks a second.
]]
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local TrainRideController = {}

local MOVE = 0.6 -- the server moves everyone this long before the ride ends (TrainRideService MOVE_LEAD)
local FULL = 60 -- studs a second at full speed (the near scenery layer's speed)
local TUNNEL_LEN = 520
local TUNNEL_DIST = 300 -- studs the train travels inside the tunnel before it stops

local Controllers = nil
local flow = (Config :: any).TrainFlow or {}
local frameA = CFrame.identity
local localFolder: Folder? = nil
local stationParts: { BasePart } = {}
local stationBase: { CFrame } = {}
local tunnelParts: { BasePart } = {}
local tunnelBase: { CFrame } = {}
local boardLabels: { TextLabel } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local ui: { [string]: any } = {}

local ride = {
	start = 0,
	finish = 0,
	profile = {} :: { number }, -- distance travelled at each PROFILE_DT step
	tunnelFrom = 0, -- distance at which the train's nose is at the tunnel mouth
	hum = nil :: Sound?,
	rumble = nil :: Sound?,
	sealed = false,
	dimmed = false,
	covered = false,
	reduced = false,
	faded = false,
}
local PROFILE_DT = 0.05

local leaves: { [BasePart]: { base: CFrame, open: boolean, tween: Tween? } } = {}
local lampsOn = false
local pendingCarry: { transform: CFrame, deadline: number, look: Vector3? }? = nil
local arrivalLook: Vector3? = nil -- the arch to turn to after the move, at each of arrivalTurns (os.clock)
local arrivalTurns: { number } = {}
local marker: { gui: BillboardGui?, anchor: Part?, label: TextLabel? } = {}
local skipHeldSince: number? = nil
local skipSent = false
local hidden: { [Model]: { [BasePart]: boolean } } = {}
local lastSlow = 0
local cabinLights: { { light: Light, base: number } } = {}

-- Helpers ------------------------------------------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stage(): string
	return GameState:GetAttribute("TrainStage") or ""
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function inTrainA(p: Vector3): boolean
	local l = frameA:PointToObjectSpace(p)
	return math.abs(l.X) <= 11.5 and l.Y > -4 and l.Y < 16 and l.Z > -100 and l.Z < 174
end

local function nearTrainA(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - frameA.Position).Magnitude < 700
end

local function scenery(): Instance?
	local lobby = workspace:FindFirstChild("Lobby")
	return lobby and lobby:FindFirstChild("Scenery")
end

local function setSpeedScale(v: number)
	local folder = scenery()
	if folder and folder:GetAttribute("SpeedScale") ~= v then
		folder:SetAttribute("SpeedScale", v) -- this client only: TrainSceneryController reads it
	end
end

-- The ride's speed (studs a second) at tau seconds into a ride of length R: a smooth pull-away, the cruise, the brakes
-- bringing it to a stop 0.3 s before the move (the train stands still in the dark)
local function speedAt(tau: number, R: number): number
	local accel = math.min(6, R * 0.24)
	local stopAt = R - MOVE - 0.3
	local brake = math.min(6.5, R * 0.3)
	if tau <= 0 or tau >= stopAt then
		return 0
	end
	local up = smooth(tau / accel)
	local down = 1 - smooth((tau - (stopAt - brake)) / brake)
	return FULL * math.min(up, down)
end

local function buildProfile(R: number)
	table.clear(ride.profile)
	local d = 0
	local n = math.ceil(R / PROFILE_DT)
	for i = 0, n do
		ride.profile[i + 1] = d
		local tau = i * PROFILE_DT
		d += speedAt(tau + PROFILE_DT / 2, R) * PROFILE_DT
	end
	-- the tunnel: the nose is at its mouth TUNNEL_DIST studs before the stop (less on a short ride)
	local total = ride.profile[#ride.profile]
	ride.tunnelFrom = math.max(total * 0.45, total - TUNNEL_DIST)
end

local function distanceAt(tau: number): number
	local p = ride.profile
	if #p == 0 then
		return 0
	end
	local f = math.clamp(tau / PROFILE_DT, 0, #p - 1)
	local i = math.floor(f)
	local a = p[i + 1]
	local b = p[math.min(i + 2, #p)]
	return a + (b - a) * (f - i)
end

-- Building the local stand-ins round train A -------------------------------------------------------------------------

local function localPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, list: { BasePart }, base: { CFrame }): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frameA * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = localFolder
	table.insert(list, p)
	table.insert(base, cf)
	return p
end

local function buildLocal()
	local folder = Instance.new("Folder")
	folder.Name = "TrainRideLocal"
	folder.Parent = workspace
	localFolder = folder
	local steel = Color3.fromRGB(46, 48, 52)
	local concrete = Color3.fromRGB(96, 96, 98)
	local oxblood = Color3.fromRGB(96, 28, 30)
	local gold = Color3.fromRGB(176, 140, 66)
	local S, SB = stationParts, stationBase
	-- the platform (left windows, local -X), the guards' aisle and the other train (right windows, local +X)
	localPart("Platform", Vector3.new(15, 1.4, 300), CFrame.new(-18.1, -0.9, 35), concrete, Enum.Material.Concrete, S, SB)
	localPart("Edge", Vector3.new(0.8, 0.06, 300), CFrame.new(-11.1, -0.17, 35), Color3.fromRGB(196, 170, 96), Enum.Material.SmoothPlastic, S, SB)
	localPart("Aisle", Vector3.new(16, 1.4, 300), CFrame.new(19, -0.9, 35), concrete, Enum.Material.Concrete, S, SB)
	localPart("OtherTrain", Vector3.new(21, 12.5, 262), CFrame.new(38, 5.2, 40), Color3.fromRGB(24, 22, 26), Enum.Material.SmoothPlastic, S, SB)
	localPart("OtherWindows", Vector3.new(21.2, 3.2, 240), CFrame.new(38, 6.4, 44), Color3.fromRGB(44, 40, 34), Enum.Material.Glass, S, SB)
	local lamp = localPart("OtherLamp", Vector3.new(3, 1.6, 0.6), CFrame.new(38, 4, -91.4), Color3.fromRGB(255, 92, 48), Enum.Material.Neon, S, SB)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 92, 48)
	glow.Range = 18
	glow.Brightness = 1.2
	glow.Parent = lamp
	-- the shed: pillars every 24 studs, a canopy, banners, a gold fan over the middle
	for k = 0, 12 do
		local z = -110 + k * 24
		localPart("PillarL", Vector3.new(1.2, 24, 1.2), CFrame.new(-23.5, 11.8, z), steel, Enum.Material.Metal, S, SB)
		localPart("PillarR", Vector3.new(1.2, 24, 1.2), CFrame.new(28, 11.8, z), steel, Enum.Material.Metal, S, SB)
		if k % 2 == 1 then
			localPart("Banner", Vector3.new(0.2, 8, 3.2), CFrame.new(-22.8, 13, z), oxblood, Enum.Material.Fabric, S, SB)
			localPart("BannerBar", Vector3.new(0.24, 0.5, 3.2), CFrame.new(-22.78, 15.2, z), gold, Enum.Material.SmoothPlastic, S, SB)
		end
	end
	localPart("Canopy", Vector3.new(60, 1, 300), CFrame.new(2, 24.3, 35), Color3.fromRGB(58, 62, 66), Enum.Material.Glass, S, SB).Transparency = 0.35
	for k = 0, 9 do
		local a = math.rad(-72 + k * 16)
		localPart("Fan", Vector3.new(0.6, 0.3, 18), CFrame.new(2, 23.4, 35) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -9), gold,
			Enum.Material.Metal, S, SB)
	end
	-- departure boards facing the train
	for _, z in ipairs({ -10, 70 }) do
		local board = localPart("Board", Vector3.new(0.4, 2.6, 9), CFrame.new(-16, 11, z), Color3.fromRGB(16, 18, 20),
			Enum.Material.SmoothPlastic, S, SB)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Right
		gui.CanvasSize = Vector2.new(900, 260)
		gui.LightInfluence = 0
		gui.Brightness = 1.3
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = Color3.fromRGB(236, 200, 120)
		label.TextScaled = true
		label.FontFace = Theme.Fonts.Mono
		label.Text = "THE TRAINING CENTRE"
		label.Parent = gui
		table.insert(boardLabels, label)
	end
	-- the tunnel: two walls, a roof and lamps every 24 studs (it slides in from ahead, -Z)
	local T, TB = tunnelParts, tunnelBase
	local dark = Color3.fromRGB(28, 27, 26)
	localPart("TunnelL", Vector3.new(2, 18, TUNNEL_LEN), CFrame.new(-14, 6, -TUNNEL_LEN / 2), dark, Enum.Material.Slate, T, TB)
	localPart("TunnelR", Vector3.new(2, 18, TUNNEL_LEN), CFrame.new(14, 6, -TUNNEL_LEN / 2), dark, Enum.Material.Slate, T, TB)
	localPart("TunnelRoof", Vector3.new(30, 2, TUNNEL_LEN), CFrame.new(0, 16, -TUNNEL_LEN / 2), dark, Enum.Material.Slate, T, TB)
	localPart("TunnelFloor", Vector3.new(30, 1, TUNNEL_LEN), CFrame.new(0, -3.2, -TUNNEL_LEN / 2), dark, Enum.Material.Slate, T, TB)
	localPart("Portal", Vector3.new(34, 6, 3), CFrame.new(0, 17, -1.5), Color3.fromRGB(62, 58, 54), Enum.Material.Concrete, T, TB)
	for k = 0, math.floor(TUNNEL_LEN / 24) - 1 do
		local z = -12 - k * 24
		for _, sx in ipairs({ -1, 1 }) do
			localPart("TunnelLamp", Vector3.new(0.4, 0.5, 1.4), CFrame.new(sx * 12.9, 9, z), Color3.fromRGB(255, 200, 130),
				Enum.Material.Neon, T, TB)
		end
	end
	localPart("CableRun", Vector3.new(0.3, 0.3, TUNNEL_LEN), CFrame.new(-12.8, 11, -TUNNEL_LEN / 2), Color3.fromRGB(18, 18, 18),
		Enum.Material.SmoothPlastic, T, TB)
	for _, p in ipairs(tunnelParts) do
		p.Transparency = 1
	end
	for _, p in ipairs(stationParts) do
		table.insert(moveParts, p)
		table.insert(moveCFrames, p.CFrame)
	end
	for _, p in ipairs(tunnelParts) do
		table.insert(moveParts, p)
		table.insert(moveCFrames, p.CFrame)
	end
end

-- the station's and the tunnel's places for distance d travelled (d of the tunnel's mouth past the nose)
local function placeLocal(stationD: number, tunnelD: number?)
	local back = Vector3.new(0, 0, 1)
	local n = #stationParts
	for i = 1, n do
		moveCFrames[i] = frameA * (CFrame.new(back * math.min(stationD, 900)) * stationBase[i])
	end
	local showTunnel = tunnelD ~= nil
	for i, p in ipairs(tunnelParts) do
		local off = if tunnelD then tunnelD - 97 else 4000
		moveCFrames[n + i] = frameA * (CFrame.new(back * off) * tunnelBase[i])
		local want = if showTunnel then 0 else 1
		if p.Transparency ~= want then
			p.Transparency = want
		end
	end
	workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- UI ------------------------------------------------------------------------------------------------------------------

local function buildUi()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TrainRide"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 25
	screen.Parent = player:WaitForChild("PlayerGui")
	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Size = UDim2.fromScale(1, 1)
	cover.ZIndex = 10
	cover.Parent = screen
	local function line(name: string, y: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, y, 0)
		label.Size = UDim2.new(0.8, 0, 0, 24)
		label.BackgroundTransparency = 1
		label.TextColor3 = Theme.Colors.Ink
		label.TextTransparency = 0.1
		label.FontFace = Theme.Fonts.Medium
		label.TextSize = 16
		label.Text = ""
		label.Visible = false
		label.RichText = true
		label.Parent = screen
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Shade
		stroke.Transparency = 0.55
		stroke.Parent = label
		return label
	end
	ui.screen = screen
	ui.cover = cover
	ui.skip = line("Skip", 0.86)
	ui.room = line("Room", 0.72)
	-- touch: the SKIP line is a button you hold
	local button = Instance.new("TextButton")
	button.Name = "SkipTouch"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(0.5, 0, 0.86, 0)
	button.Size = UDim2.new(0, 220, 0, 36)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Visible = false
	button.Parent = screen
	button.MouseButton1Down:Connect(function()
		skipHeldSince = os.clock()
	end)
	button.MouseButton1Up:Connect(function()
		skipHeldSince = nil
	end)
	ui.skipTouch = button
end

local function cover(to: number, time: number)
	if not ui.cover then
		return
	end
	TweenService:Create(ui.cover, TweenInfo.new(time, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 - to }):Play()
end

local function flash(hold: number)
	cover(1, 0.15)
	task.delay(0.15 + hold, function()
		cover(0, 0.35)
	end)
end

-- Doors ---------------------------------------------------------------------------------------------------------------

local function registerLeaf(leaf: Instance)
	if leaf:IsA("BasePart") and not leaves[leaf] then
		leaves[leaf] = { base = leaf.CFrame, open = false }
	end
end

-- a leaf (and anything on it) to open or shut, sliding along its own axis by its Slide attribute
local function setLeaf(leaf: BasePart, open: boolean, time: number)
	local entry = leaves[leaf]
	if not entry then
		registerLeaf(leaf)
		entry = leaves[leaf]
	end
	if not entry or entry.open == open then
		return
	end
	entry.open = open
	local slide = tonumber(leaf:GetAttribute("Slide")) or 0
	local axis = if leaf:GetAttribute("SlideAxis") == "X" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local target = if open then entry.base * CFrame.new(axis * slide) else entry.base
	if entry.tween then
		entry.tween:Cancel()
	end
	local children = {}
	for _, c in ipairs(leaf:GetChildren()) do
		if c:IsA("BasePart") then
			table.insert(children, { part = c, rel = leaf.CFrame:ToObjectSpace(c.CFrame) })
		end
	end
	if time <= 0 then
		leaf.CFrame = target
	else
		local tween = TweenService:Create(leaf, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = target })
		entry.tween = tween
		tween:Play()
		if #children > 0 then
			local conn
			conn = RunService.RenderStepped:Connect(function()
				for _, c in ipairs(children) do
					c.part.CFrame = leaf.CFrame * c.rel
				end
				if tween.PlaybackState ~= Enum.PlaybackState.Playing then
					conn:Disconnect()
				end
			end)
		end
	end
	if time <= 0 then
		for _, c in ipairs(children) do
			c.part.CFrame = leaf.CFrame * c.rel
		end
	end
end

-- The station's and the hall's parts that this controller drives (launch doors, screens, platform lamps), found by a
-- walk of both sets at most every 3 s (the Blender set has about 3,500 instances: no walk 4 times a second).
local found = { at = -math.huge, doors = {} :: { Instance }, screens = {} :: { BasePart }, lamps = {} :: { any } }
local function scanSets(): typeof(found)
	local t = os.clock()
	if t - found.at < 3 then
		return found
	end
	found.at = t
	local doors, screens, lamps = {}, {}, {}
	for _, rootName in ipairs({ "TrainStationB", "TrainingCentre" }) do
		local root = workspace:FindFirstChild(rootName)
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d.Name == "LaunchDoors" and d:GetAttribute("OpenAt") ~= nil then
					table.insert(doors, d)
				elseif d:IsA("BasePart") and d:GetAttribute("TrainScreen") then
					table.insert(screens, d)
				elseif d:IsA("Light") and d.Parent and (d.Parent.Name == "LampHead" or string.sub(d.Parent.Name, 1, 9) == "PlatLamp_") then
					table.insert(lamps, d)
				end
			end
		end
	end
	found.doors, found.screens, found.lamps = doors, screens, lamps
	return found
end

local function launchDoorModels(): { Instance }
	return scanSets().doors
end

local function updateDoors(t: number)
	local s = stage()
	-- train B's side doors
	local station = workspace:FindFirstChild("TrainStationB")
	local trainB = station and station:FindFirstChild("TrainB")
	local openAt = trainB and tonumber(trainB:GetAttribute("DoorsOpenAt")) or 0
	local openB = (s == "Training" or s == "Ride") and openAt > 0 and t >= openAt -- (they open in the dark of the move)
	for _, leaf in ipairs(CollectionService:GetTagged("TrainDoorLeaf")) do
		if leaf:IsA("BasePart") then
			local late = openB and t - openAt > 1.5
			setLeaf(leaf, openB, if late then 0 else 1.2)
		end
	end
	-- the launch doors: open for those who hold a place (alone: always)
	local mine = player:GetAttribute("TrainHeld") == true
	for _, model in ipairs(launchDoorModels()) do
		local at = tonumber(model:GetAttribute("OpenAt")) or 0
		local open = s == "Training" and at > 0 and t >= at and mine
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") and d:GetAttribute("Slide") ~= nil then
				setLeaf(d, open, if t - at > 1.5 then 0 else 1.2)
			end
		end
		local lamp = model:FindFirstChild("DoorLamp")
		if lamp and lamp:IsA("BasePart") then
			lamp.Color = if s == "Training" and at > 0 and t >= at then Color3.fromRGB(230, 40, 34) else Color3.fromRGB(70, 20, 20)
		end
	end
end

local function setPlatformLamps(on: boolean, sequenced: boolean)
	if on == lampsOn then
		return
	end
	lampsOn = on
	found.at = -math.huge -- a fresh walk: the hall may have streamed in since
	for _, d in ipairs(scanSets().lamps) do
		if d.Parent then
			local bank = tonumber(d.Parent:GetAttribute("Bank")) or 0
			local head = d.Parent :: BasePart
			local isHead = head.Name == "LampHead"
			local function apply()
				d.Enabled = on
				if isHead then
					head.Color = if on then Color3.fromRGB(255, 232, 196) else Color3.fromRGB(40, 40, 40)
				end
			end
			if sequenced and on then
				task.delay(bank * 0.13, apply)
			else
				apply()
			end
		end
	end
	if on and sequenced then
		Sfx.play("PlateLock", { pitch = 0.85, volume = 0.6 })
	end
end

-- The red room: others hidden --------------------------------------------------------------------------------------

local function hideCharacter(model: Model, hide: boolean)
	local entry = hidden[model]
	if hide then
		if not entry then
			entry = {}
			hidden[model] = entry
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 1
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	elseif entry then
		hidden[model] = nil
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		end
	end
end

local function updateRoom()
	local meIn = player:GetAttribute("InRedRoom") == true
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local model = other.Character
			if model then
				hideCharacter(model, other:GetAttribute("InRedRoom") == true)
			end
		end
	end
	for model in pairs(hidden) do
		if not model.Parent then
			hidden[model] = nil
		end
	end
	if ui.room then
		if meIn then
			local ready = player:GetAttribute("RedRoomReady") == true
			ui.room.Text = if ready then "Ready" else "Stand on the disc"
			ui.room.TextTransparency = if ready then 0.45 else 0.1
			ui.room.Visible = true
		else
			ui.room.Visible = false
		end
	end
end

-- Boards ------------------------------------------------------------------------------------------------------------

local function updateBoards(t: number)
	local phase = GameState:GetAttribute("Phase") or "Lobby"
	local s = stage()
	local text
	if s == "Ride" then
		text = "DEPARTED · THE TRAINING CENTRE"
	elseif phase == "Intermission" and s ~= "Training" then
		local left = (tonumber(GameState:GetAttribute("PhaseEndsAt")) or t) - t
		text = string.format("TRAIN DEPARTS %s · THE TRAINING CENTRE", Util.formatTime(left))
	elseif phase == "Active" or phase == "Countdown" then
		text = string.format("IN THE ARENA · %d REMAIN", math.floor(tonumber(GameState:GetAttribute("AliveCount")) or 0))
	else
		text = "THE TRAINING CENTRE · NEXT TRAIN SOON"
	end
	for _, label in ipairs(boardLabels) do
		if label.Text ~= text then
			label.Text = text
		end
	end
	-- the hall's big screen
	local callAt = tonumber(GameState:GetAttribute("TrainCallAt")) or 0
	local doorsAt = tonumber(GameState:GetAttribute("TrainDoorsAt")) or 0
	local screenText = "THE TRAINING CENTRE"
	if s == "Training" then
		if GameState:GetAttribute("TrainDoorsOpen") == true then
			screenText = string.format("THE CALL IN %s", Util.formatTime(callAt - t))
		else
			screenText = string.format("DOORS OPEN IN %s", Util.formatTime(doorsAt - t))
		end
	end
	for _, d in ipairs(scanSets().screens) do
		local gui = d:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label and label.Text ~= screenText then
			label.Text = screenText
		end
	end
end

-- The ride, per frame -------------------------------------------------------------------------------------------------

local function stopSounds()
	for _, key in ipairs({ "hum", "rumble" }) do
		local s = (ride :: any)[key]
		if s then
			s:Stop()
			s:Destroy()
			;(ride :: any)[key] = nil
		end
	end
end

local function cabinLamps(scale: number)
	if #cabinLights == 0 then
		local lobby = workspace:FindFirstChild("Lobby")
		local lamps = lobby and lobby:FindFirstChild("Lamps")
		if lamps then
			for _, d in ipairs(lamps:GetDescendants()) do
				if d:IsA("Light") then
					table.insert(cabinLights, { light = d, base = d.Brightness })
				end
			end
		end
	end
	for _, l in ipairs(cabinLights) do
		l.light.Brightness = l.base * scale
	end
end

local function resetRide()
	stopSounds()
	ride.sealed = false
	ride.dimmed = false
	ride.covered = false
	ride.faded = false
	cabinLamps(1)
	setSpeedScale(0)
	placeLocal(0, nil)
	skipSent = false
	skipHeldSince = nil
	if ui.skip then
		ui.skip.Visible = false
		ui.skipTouch.Visible = false
	end
end

local function rideFrame(t: number)
	local R = ride.finish - ride.start
	local tau = t - ride.start
	-- Studio test only (pictures): GameState attribute TrainRideFreeze (seconds) holds the ride's clock there
	local freeze = if Config.IsStudio then tonumber(GameState:GetAttribute("TrainRideFreeze")) else nil
	if freeze then
		tau = freeze
	end
	if not ride.sealed then
		ride.sealed = true
		ride.reduced = GuiService.ReducedMotionEnabled
		buildProfile(R)
		Sfx.play("Launch_Seal", { pitch = 0.8, volume = 1.2 })
		ride.hum = Sfx.play("Launch_RoomTone", { looped = true, pitch = 0.55, volume = 0.5 })
		ride.rumble = Sfx.play("Hazard_Rumble", { looped = true, pitch = 0.42, volume = 0 })
		if tau > 1 then
			-- joined mid-ride: no pull-away sound
		end
	end
	local v = speedAt(tau, R)
	local d = distanceAt(tau)
	if ride.hum then
		ride.hum.Volume = 0.18 + 0.35 * (v / FULL)
	end
	if ride.rumble then
		ride.rumble.Volume = 0.55 * (v / FULL)
	end
	if not nearTrainA() then
		return
	end
	if ride.reduced then
		-- Reduced Motion: nothing slides; a fade covers the station going, the tunnel stands round the train
		setSpeedScale(0)
		if not ride.faded and tau >= 0.4 then
			ride.faded = true
			flash(0.3)
			task.delay(0.3, function()
				if stage() == "Ride" then
					placeLocal(2000, 290) -- the tunnel's mouth past the tail: the whole train inside
				end
			end)
		end
	else
		setSpeedScale(v / FULL)
		local tunnelD = if d >= ride.tunnelFrom - 600 then d - ride.tunnelFrom else nil
		placeLocal(d, tunnelD)
	end
	-- the cabin dims in the tunnel; the cover comes up for the move
	local dim = smooth((d - ride.tunnelFrom) / 80)
	cabinLamps(1 - 0.65 * dim)
	if not ride.covered and tau >= R - MOVE - 0.25 then
		ride.covered = true
		cover(1, 0.25)
	end
end

local function skipFrame(t: number)
	local canSkip = stage() == "Ride" and player:GetAttribute("Rode") == true and not skipSent
		and t < (tonumber(GameState:GetAttribute("TrainMoveAt")) or 0) - 1
	local root = rootPart()
	canSkip = canSkip and root ~= nil and inTrainA(root.Position)
	if ui.skip then
		if canSkip then
			local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			ui.skip.Text = if touch then "Hold SKIP to skip the ride" elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
				then "Hold A to skip the ride" else "Hold Space to skip the ride"
			ui.skip.Visible = true
			ui.skipTouch.Visible = touch
		else
			ui.skip.Visible = false
			ui.skipTouch.Visible = false
		end
	end
	if canSkip and skipHeldSince and os.clock() - skipHeldSince >= (tonumber(flow.SkipHold) or 0.6) then
		skipSent = true
		skipHeldSince = nil
		local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("TrainRide")
		if remote then
			(remote :: RemoteEvent):FireServer({ kind = "skip" })
		end
	end
end

-- The quiet marker: on the platform it shows the way into the hall ("Training Centre"); once the launch doors are open
-- for you, the way to them ("Launch"). Nothing shows inside the hall before that, in the red room or anywhere else.
local function updateMarker()
	local s = stage()
	local here = player:GetAttribute("AtTrainingCentre") == true
	local inHall = player:GetAttribute("InTraining") == true
	local target: Vector3? = nil
	local text = ""
	if here and (s == "Training" or s == "Ride") and player:GetAttribute("InRedRoom") ~= true then
		if not inHall then
			local v = GameState:GetAttribute("TrainHallEntry")
			local best = if typeof(v) == "Vector3" then v else nil
			local me = rootPart()
			for k = 1, 9 do
				local a = GameState:GetAttribute("TrainHallArch" .. k)
				if typeof(a) ~= "Vector3" then
					break
				end
				if me and (not best or (a - me.Position).Magnitude < (best - me.Position).Magnitude) then
					best = a
				end
			end
			target = if best then best + Vector3.new(0, 7, 0) else nil -- (in the archway, just over head height)
			text = "Training Centre"
		elseif GameState:GetAttribute("TrainDoorsOpen") == true and player:GetAttribute("TrainHeld") == true then
			local v = GameState:GetAttribute("TrainLaunchEntry")
			target = if typeof(v) == "Vector3" then v + Vector3.new(0, 9, 0) else nil -- (in the open doorway)
			-- (hunt2_1) the word is wider than the doorway: in its plane the jambs cut it ("aunch"); a few studs out into
			-- the hall nothing stands in front of it
			local hall = GameState:GetAttribute("TrainHallEntry")
			if target and typeof(v) == "Vector3" and typeof(hall) == "Vector3" then
				local out = Vector3.new(hall.X - v.X, 0, hall.Z - v.Z)
				if out.Magnitude > 0.1 then
					target += out.Unit * 4
				end
			end
			text = "Launch"
		end
	end
	local root = rootPart()
	if target and root and (Vector3.new(target.X, root.Position.Y, target.Z) - root.Position).Magnitude < 3 then
		target = nil -- you are there
	end
	if not target then
		if marker.gui then
			marker.gui.Enabled = false
		end
		return
	end
	if not marker.anchor then
		local anchor = Instance.new("Part")
		anchor.Name = "TrainWayMarker"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Parent = localFolder or workspace
		local gui = Instance.new("BillboardGui")
		gui.Name = "Way"
		gui.AlwaysOnTop = false -- (it stands in the open archway or doorway: nothing hides it from the way there)
		gui.LightInfluence = 0
		gui.Size = UDim2.fromOffset(180, 46)
		gui.Adornee = anchor
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Name = "Line"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 22)
		label.FontFace = Theme.Fonts.Medium
		label.TextSize = 15
		label.TextColor3 = Theme.Colors.Ink
		label.TextTransparency = 0.1
		label.Parent = gui
		local chevron = Instance.new("TextLabel")
		chevron.Name = "Chevron"
		chevron.BackgroundTransparency = 1
		chevron.Position = UDim2.fromOffset(0, 20)
		chevron.Size = UDim2.new(1, 0, 0, 22)
		chevron.FontFace = Theme.Fonts.Medium
		chevron.TextSize = 18
		chevron.Text = "▼"
		chevron.TextColor3 = Theme.Colors.Ink
		chevron.TextTransparency = 0.25
		chevron.Parent = gui
		for _, l in ipairs({ label, chevron }) do
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.Colors.Shade
			stroke.Transparency = 0.55
			stroke.Parent = l
		end
		marker.anchor, marker.gui, marker.label = anchor, gui, label
	end
	if marker.anchor and marker.anchor.Position ~= target then
		marker.anchor.CFrame = CFrame.new(target)
	end
	if marker.label and marker.label.Text ~= text then
		marker.label.Text = text
	end
	if marker.gui then
		marker.gui.Enabled = true
	end
end

local lastStage = ""
local arrivedAt = 0

local function frame(dt: number)
	local t = now()
	local s = stage()
	if s ~= lastStage then
		local old = lastStage
		lastStage = s
		if s == "Ride" then
			ride.start = tonumber(GameState:GetAttribute("TrainRideStart")) or t
			ride.finish = tonumber(GameState:GetAttribute("TrainRideEnd")) or (t + 25)
			ride.sealed = false
		elseif old == "Ride" then
			stopSounds()
			setSpeedScale(0)
			placeLocal(0, nil)
			cabinLamps(1)
		end
		if s == "Training" then
			arrivedAt = t
			setPlatformLamps(true, old == "Ride")
			if ride.covered then
				task.delay(0.15, function()
					cover(0, 0.45)
				end)
				ride.covered = false
			end
		elseif s == "" then
			setPlatformLamps(false, false)
			resetRide()
		end
	end
	if s == "Ride" then
		rideFrame(t)
		skipFrame(t)
	end
	-- the camera follows the move (the server moved the character; this frame's camera comes along)
	local carry = pendingCarry
	if carry then
		local root = rootPart()
		if root and not inTrainA(root.Position) then
			local camera = workspace.CurrentCamera
			if camera then
				camera.CFrame = carry.transform * camera.CFrame
				camera.Focus = carry.transform * camera.Focus
				-- then turned to the arch into the hall (again as the dark lifts: the view switches to first person
				-- around now, and that switch can undo a turn made a frame too early)
				arrivalLook = carry.look
				arrivalTurns = { os.clock(), os.clock() + 0.35, os.clock() + 0.8 }
			end
			pendingCarry = nil
		elseif os.clock() > carry.deadline then
			pendingCarry = nil
		end
	end
	if arrivalLook and #arrivalTurns > 0 and os.clock() >= arrivalTurns[1] then
		table.remove(arrivalTurns, 1)
		local cameraController = Controllers and Controllers.CameraController
		local root = rootPart()
		if root and cameraController and type(cameraController.faceToward) == "function" then
			-- eyes nearly level (CameraController owns the view's base turn)
			cameraController.faceToward(Vector3.new(arrivalLook.X - root.Position.X, 0, arrivalLook.Z - root.Position.Z), -6)
		end
		if #arrivalTurns == 0 then
			arrivalLook = nil
		end
	end
	if t - lastSlow >= 0.25 then
		lastSlow = t
		updateDoors(t)
		updateRoom()
		updateBoards(t)
		updateMarker()
		if s == "Training" and not lampsOn then
			setPlatformLamps(true, false)
		end
		if s == "Ride" and player:GetAttribute("AtTrainingCentre") == true and not lampsOn then
			setPlatformLamps(true, false) -- a skipper: the platform is lit for them
		end
	end
	local _ = dt + arrivedAt
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function TrainRideController.Init(registry)
	Controllers = registry
end

function TrainRideController.Start()
	if flow.Enabled ~= true then
		return
	end
	local lobby = workspace:WaitForChild("Lobby", 30)
	if not lobby or not lobby:IsA("Model") or lobby:GetAttribute("TrainLobby") ~= true then
		return
	end
	frameA = lobby.WorldPivot
	buildLocal()
	buildUi()
	placeLocal(0, nil)
	setSpeedScale(0)
	for _, leaf in ipairs(CollectionService:GetTagged("TrainDoorLeaf")) do
		registerLeaf(leaf)
	end
	CollectionService:GetInstanceAddedSignal("TrainDoorLeaf"):Connect(registerLeaf)
	CollectionService:GetInstanceRemovedSignal("TrainDoorLeaf"):Connect(function(leaf)
		leaves[leaf :: BasePart] = nil
	end)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("TrainRide", 30)
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end
			if payload.kind == "arrive" and typeof(payload.transform) == "CFrame" then
				pendingCarry = { transform = payload.transform, deadline = os.clock() + 2,
					look = if typeof(payload.look) == "Vector3" then payload.look else nil }
				if not ride.covered then
					ride.covered = true
					cover(1, 0.1)
				end
			elseif payload.kind == "fade" then
				flash(tonumber(payload.time) or 0.4)
				if payload.why == "skip" then
					setPlatformLamps(true, false)
				end
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			skipHeldSince = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			skipHeldSince = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(frame, dt)
		if not ok then
			warn("[TrainRideController] " .. tostring(err))
		end
	end)
	local _ = Controllers
end

return TrainRideController
