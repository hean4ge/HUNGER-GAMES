--[[
	LaunchController - the opening of a round. When the Countdown starts, the launch plates rise out of their launch
	tubes carrying the frozen contenders up into the light: a lift whir, a heavy clunk as each plate locks, a short
	under-light and a camera kick for your own plate, a puff of dust at the rim.

	Purely visual and client-side. The server has already put every contender on top of their plate (root anchored,
	Player.Frozen = true) and never moves the plates. Each client lowers the plates (workspace.Arena.Plinths children:
	a Model pivots as a whole, a BasePart takes its anchored child parts along) and the contenders standing on them
	into the tubes (ArenaLayout.PlateTube, carved by TerrainGen v2), then raises them
	on one shared timeline (GameState LaunchAt / LaunchRise / LaunchDepth, set by RoundService), and finally restores
	the exact server positions, always before the start horn. A plate with no tube under it (nothing to sink into)
	stays put; a contender with no plate model rises only if there is a tube under their feet.
	API:
	  LaunchController.isLaunching() -> boolean
	  LaunchController.getRise() -> number   0..1 progress of the rise (1 when done or idle)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")
local localPlayer = Players.LocalPlayer

local RoundCfg = Config.Round
local SETTLE = 0.32 -- seconds of settle bounce after a plate locks
local RIDER_RADIUS = 4.5 -- a contender this close (flat) to a plate's stand point rides it
local NEAR_EFFECTS = 140 -- other plates within this range get sound / light / dust
local MAX_ASSUMED_PLATE = 4 -- a plate model taller than this is assumed to be a column reaching into the tube
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local LIGHT_COLOR = Color3.fromRGB(255, 226, 188)

local LaunchController = {}

local Controllers: any = nil
local state = nil
local watchedRound = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nearCamera(position: Vector3, range: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= range
end

-- Plates -----------------------------------------------------------------------------------------------------------------

local function platesFolder(): Instance?
	local arena = workspace:FindFirstChild("Arena")
	return arena and arena:FindFirstChild("Plinths")
end

local function pivotOf(plate: Instance): CFrame
	if plate:IsA("Model") then
		return plate:GetPivot()
	end
	return (plate :: BasePart).CFrame
end

-- A BasePart plate's anchored child parts (trim, pedestal, number plate) travel with it: their offsets from the plate.
local function plateGroup(plate: Instance, base: CFrame)
	if plate:IsA("Model") then
		return nil -- PivotTo moves a whole model
	end
	local group = { { part = plate :: BasePart, rel = CFrame.identity } }
	for _, d in ipairs(plate:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored then
			table.insert(group, { part = d, rel = base:ToObjectSpace(d.CFrame) })
		end
	end
	return group
end

-- Put a plate (and everything that belongs to it) at `cf`.
local function placePlate(entry, cf: CFrame)
	local plate = entry.plate
	if plate:IsA("Model") then
		plate:PivotTo(cf)
		return
	end
	if not entry.group then
		(plate :: BasePart).CFrame = cf
		return
	end
	local parts, cfs = {}, {}
	for _, item in ipairs(entry.group) do
		if item.part.Parent then
			table.insert(parts, item.part)
			table.insert(cfs, cf * item.rel)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function anyPart(plate: Instance): BasePart?
	if plate:IsA("BasePart") then
		return plate
	end
	if plate:IsA("Model") and plate.PrimaryPart then
		return plate.PrimaryPart
	end
	return plate:FindFirstChildWhichIsA("BasePart", true)
end

local function standPoint(plate: Instance): Vector3?
	for _, d in ipairs(plate:GetDescendants()) do
		if d:IsA("Attachment") and (d.Name == "Stand" or d.Name == "Spawn" or d.Name == "SpawnPoint") then
			return d.WorldPosition
		end
	end
	local cf, size
	if plate:IsA("Model") then
		cf, size = plate:GetBoundingBox()
	elseif plate:IsA("BasePart") then
		cf, size = plate.CFrame, plate.Size
	else
		return nil
	end
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

local function bottomOf(plate: Instance): number
	if plate:IsA("Model") then
		local cf, size = plate:GetBoundingBox()
		return cf.Position.Y - size.Y / 2
	end
	local part = plate :: BasePart
	return part.Position.Y - part.Size.Y / 2
end

-- How far a plate can sink: the free space between its underside and the tube floor (0 = no tube).
local function tubeDepth(stand: Vector3, plateBottom: number?, exclude: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local maxDepth = tonumber(GameState:GetAttribute("LaunchDepth")) or RoundCfg.LaunchDepth or 10
	local hit = workspace:Raycast(stand + Vector3.new(0, 0.5, 0), Vector3.new(0, -(maxDepth + 30), 0), params)
	if not hit then
		return 0
	end
	local thickness = if plateBottom then math.clamp(stand.Y - plateBottom, 0, MAX_ASSUMED_PLATE) else 0
	local free = (stand.Y - hit.Position.Y) - thickness
	if free < 2.5 then
		return 0
	end
	return math.min(maxDepth, free)
end

-- Sound -------------------------------------------------------------------------------------------------------------------

local function playSound(key: string, opts: { [string]: any }?): Sound?
	local entry = Sounds[key]
	if type(entry) ~= "table" or type(entry.ids) ~= "table" or #entry.ids == 0 then
		return nil
	end
	local o = opts or {}
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = entry.ids[math.random(1, #entry.ids)]
	s.Volume = (entry.volume or 0.5) * (o.volume or 1)
	s.PlaybackSpeed = o.pitch or 1
	local group = SoundService:FindFirstChild(entry.group or "SFX")
	if group and group:IsA("SoundGroup") then
		s.SoundGroup = group
	end
	local holder: Instance = s
	if o.position then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Launch_" .. key
		attachment.WorldPosition = o.position
		attachment.Parent = workspace.Terrain
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = entry.rollMin or 12
		s.RollOffMaxDistance = entry.rollMax or 160
		s.Parent = attachment
		holder = attachment
	else
		s.Parent = SoundService
	end
	if o.region then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(o.region[1], o.region[2])
	end
	s:Play()
	task.delay(o.life or entry.maxLifetime or 10, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
	return s
end

-- Effects -----------------------------------------------------------------------------------------------------------------

local function makeRig(entry, isLocal: boolean)
	local part = anyPart(entry.plate)
	if not part then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "LaunchFX"
	attachment.WorldPosition = entry.stand + Vector3.new(0, 0.15, 0)
	attachment.Parent = part
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Top
	light.Angle = 80
	light.Range = 13
	light.Brightness = 0
	light.Color = LIGHT_COLOR
	light.Shadows = isLocal
	light.Parent = attachment
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = DUST_TEXTURE
	dust.Enabled = false
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.9, 1.7)
	dust.Speed = NumberRange.new(5, 9)
	dust.SpreadAngle = Vector2.new(180, 8)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Acceleration = Vector3.new(0, 1.5, 0)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 5.5) })
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 138, 120))
	dust.LightInfluence = 1
	dust.Parent = attachment
	entry.fx = { attachment = attachment, light = light, dust = dust }
end

local function clearRig(entry)
	if entry.fx then
		local attachment = entry.fx.attachment
		-- the light goes out now; the dust already emitted keeps drifting until the attachment goes
		entry.fx.light.Brightness = 0
		entry.fx.light.Enabled = false
		entry.fx = nil
		task.delay(2.5, function()
			if attachment.Parent then
				attachment:Destroy()
			end
		end)
	end
end

-- Launch -------------------------------------------------------------------------------------------------------------------

local function easeRise(p: number): number
	-- slow start (the lift takes the weight), steady climb, decelerate into the lock
	return p * p * (3 - 2 * p)
end

local function offsetFor(entry, t: number): number
	if entry.depth <= 0 then
		return 0
	end
	if t <= state.launchAt then
		return -entry.depth
	end
	local riseEnd = state.riseEnd
	if t < riseEnd then
		local p = (t - state.launchAt) / math.max(0.05, riseEnd - state.launchAt)
		return -entry.depth * (1 - easeRise(p))
	end
	local after = t - riseEnd
	if after < SETTLE then
		-- a small drop and catch as the lock engages
		return -0.16 * math.sin(math.pi * after / SETTLE)
	end
	return 0
end

local function restoreAll()
	if not state then
		return
	end
	for _, entry in ipairs(state.plates) do
		if entry.plate.Parent and entry.applied ~= 0 then
			placePlate(entry, entry.base)
		end
		entry.applied = 0
		clearRig(entry)
	end
	for _, rider in pairs(state.riders) do
		local root = rider.root
		if root.Parent and root.Anchored and rider.lastSet then
			-- only if we're still the last writer (the server hasn't moved it since)
			if (root.CFrame.Position - rider.lastSet.Position).Magnitude < 0.05 then
				root.CFrame = rider.base
			end
		end
	end
	state = nil
end

local function plateFor(position: Vector3)
	local best, bestD = nil, RIDER_RADIUS
	for _, entry in ipairs(state.plates) do
		local d = Vector2.new(entry.stand.X - position.X, entry.stand.Z - position.Z).Magnitude
		if d < bestD then
			best, bestD = entry, d
		end
	end
	return best
end

local function characterList(): { Instance }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function begin()
	restoreAll()
	local launchAt = tonumber(GameState:GetAttribute("LaunchAt")) or 0
	local rise = tonumber(GameState:GetAttribute("LaunchRise")) or RoundCfg.LaunchRiseTime or 3.4
	local endsAt = tonumber(GameState:GetAttribute("PhaseEndsAt")) or (now() + 10)
	if launchAt <= 0 then
		launchAt = now() + (RoundCfg.LaunchDelay or 0.8)
	end
	-- the plates must be locked (and positions restored) well before the horn
	local riseEnd = math.min(launchAt + rise, endsAt - 0.9)
	if riseEnd - launchAt < 1.2 then
		launchAt = math.max(now(), riseEnd - 1.2)
	end
	state = {
		launchAt = launchAt,
		riseEnd = riseEnd,
		plates = {},
		known = {}, -- [plate instance] = entry
		riders = {},
		started = false,
		locked = false,
		localRider = nil,
		nextScan = 0,
	}
end

-- Pick up plates as they stream in (a plate that arrives mid-rise joins at the current height).
local function scanPlates(t: number)
	if t < state.nextScan then
		return
	end
	state.nextScan = t + 0.25
	local folder = platesFolder()
	if not folder then
		return
	end
	local exclude = nil
	for _, plate in ipairs(folder:GetChildren()) do
		if (plate:IsA("Model") or plate:IsA("BasePart")) and not state.known[plate] then
			local stand = standPoint(plate)
			if stand then
				exclude = exclude or characterList()
				local excl = table.clone(exclude)
				table.insert(excl, plate)
				local entry = {
					plate = plate,
					base = pivotOf(plate),
						group = plateGroup(plate, pivotOf(plate)),
					stand = stand,
					depth = tubeDepth(stand, bottomOf(plate), excl),
					applied = 0,
				}
				state.known[plate] = entry
				table.insert(state.plates, entry)
				if state.started and entry.depth > 0 and nearCamera(entry.stand, NEAR_EFFECTS) and t < state.riseEnd then
					makeRig(entry, false)
				end
				-- riders that were waiting for their plate
				for _, rider in pairs(state.riders) do
					if not rider.plate and (Vector2.new(stand.X - rider.base.X, stand.Z - rider.base.Z)).Magnitude < RIDER_RADIUS then
						rider.plate, rider.depth = entry, entry.depth
						if rider.player == localPlayer then
							state.localRider = rider
						end
					end
				end
			end
		end
	end
end

-- What a rider rides from its base CFrame: the plate it stands on, else its own launch tube - but only on the plate
-- ring. The server sets InArena / Frozen and anchors a contender before it places them (it waits for streaming around
-- their plate first), so in the first frames of the countdown a rider can still be standing in the lobby: they ride
-- nothing until the server's move arrives (step() re-bases them then).
local function assignRider(rider)
	local position = rider.base.Position
	local plate = plateFor(position)
	rider.plate, rider.depth = plate, 0
	if plate then
		rider.depth = plate.depth
		return
	end
	local centre = ArenaLayout.Center or Vector3.zero
	local ring = ArenaLayout.PlinthRingRadius or 52
	local flat = Vector2.new(position.X - centre.X, position.Z - centre.Z).Magnitude
	if math.abs(flat - ring) <= 8 then
		rider.depth = tubeDepth(position - Vector3.new(0, 3, 0), nil, characterList())
	end
end

local function trackRiders()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true and player:GetAttribute("Frozen") == true then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and root.Anchored then
				local rider = state.riders[player]
				if not rider or rider.root ~= root then
					rider = { root = root, base = root.CFrame, lastSet = nil, plate = nil, depth = 0, player = player }
					assignRider(rider)
					state.riders[player] = rider
					if player == localPlayer then
						state.localRider = rider
					end
				end
			end
		end
	end
end

-- Your own lift: the under-light on your plate, the whir (its clunk lands on the lock) and a nudge of the camera. At the
-- start of the rise, or as soon as the server's placement arrives if that only happens once the rise is under way.
local function startLocalLift(t: number)
	local localRider = state.localRider
	if state.localLift or not localRider or localRider.depth <= 0 or t >= state.riseEnd then
		return
	end
	state.localLift = true
	local riseLen = state.riseEnd - state.launchAt
	local late = math.max(0, t - state.launchAt)
	local clunk = 9.5 -- the whir runs up to the clunk at 9.5 s in the source
	local region = { math.max(0, clunk - riseLen - 0.08 + late), clunk + 1.6 }
	local entry = localRider.plate
	if entry and not entry.fx then
		makeRig(entry, true)
	end
	playSound("PlateRise", { region = region, life = riseLen - late + 3 })
	ClientState.cameraImpulse:Fire(Vector3.new(math.rad(0.5), 0, 0), 0.06)
end

local function onRiseStart(t: number)
	local localRider = state.localRider
	local riseLen = state.riseEnd - state.launchAt
	-- the whir runs up to the clunk at 9.5 s in the source, timed to land on the lock
	local clunk = 9.5
	local region = { math.max(0, clunk - riseLen - 0.08), clunk + 1.6 }
	for _, entry in ipairs(state.plates) do
		if entry.depth > 0 and not entry.fx then
			local isLocal = localRider ~= nil and localRider.plate == entry
			if not isLocal and nearCamera(entry.stand, NEAR_EFFECTS) then
				makeRig(entry, false)
			end
		end
	end
	startLocalLift(t)
	-- a few nearby plates heard in 3D
	local heard = 0
	for _, entry in ipairs(state.plates) do
		if heard >= 4 then
			break
		end
		local isLocal = localRider ~= nil and localRider.plate == entry
		if entry.depth > 0 and not isLocal and nearCamera(entry.stand, 90) then
			heard += 1
			playSound("PlateRise", { region = region, position = entry.stand, volume = 0.55, life = riseLen + 3 })
		end
	end
end

local function onLock()
	local localRider = state.localRider
	for _, entry in ipairs(state.plates) do
		if entry.fx then
			entry.fx.dust:Emit(16)
		end
	end
	if localRider and localRider.depth > 0 then
		playSound("PlateLock")
		ClientState.cameraImpulse:Fire(Vector3.new(math.rad(-1.4), 0, math.rad(0.3)), 0.22)
	end
	local heard = 0
	for _, entry in ipairs(state.plates) do
		local isLocal = localRider ~= nil and localRider.plate == entry
		if heard < 5 and entry.depth > 0 and not isLocal and nearCamera(entry.stand, 110) then
			heard += 1
			playSound("PlateLock", { position = entry.stand, volume = 0.7, pitch = 0.95 + math.random() * 0.1 })
		end
	end
end

local function step()
	if not state then
		return
	end
	local phase = GameState:GetAttribute("Phase")
	local t = now()
	if phase ~= "Countdown" or t > state.riseEnd + SETTLE + 0.1 then
		restoreAll()
		return
	end
	scanPlates(t)
	trackRiders()
	if not state.started and t >= state.launchAt then
		state.started = true
		onRiseStart(t)
	end
	if not state.locked and t >= state.riseEnd then
		state.locked = true
		onLock()
	end
	-- plates
	for _, entry in ipairs(state.plates) do
		local off = offsetFor(entry, t)
		if entry.plate.Parent and math.abs(off - entry.applied) > 1e-4 then
			placePlate(entry, entry.base + Vector3.new(0, off, 0))
			entry.applied = off
		end
		if entry.fx then
			-- the under-light swells as the plate climbs and dies away after the lock
			local p = math.clamp((t - state.launchAt) / math.max(0.05, state.riseEnd - state.launchAt), 0, 1)
			local brightness
			if t < state.riseEnd then
				brightness = 2.4 * math.sin(math.pi * math.min(1, p * 1.1)) + 0.4
			else
				brightness = math.max(0, 2.8 * (1 - (t - state.riseEnd) / 0.5))
			end
			entry.fx.light.Brightness = brightness
		end
	end
	-- contenders ride their plate (or their own tube)
	for player, rider in pairs(state.riders) do
		local root = rider.root
		if not root.Parent or not root.Anchored or player.Parent ~= Players then
			state.riders[player] = nil
		else
			-- the server moved it (out of the lobby onto its plate once streaming allowed, or anywhere else): that is the
			-- new truth. Compared with what we last wrote, or with the base when we haven't written (a rider still in the
			-- lobby rides nothing, so nothing was written and the move must still be noticed).
			local expected = rider.lastSet or rider.base
			if (root.CFrame.Position - expected.Position).Magnitude > 0.05 then
				rider.base = root.CFrame
				rider.lastSet = nil
				assignRider(rider)
			end
			local source = rider.plate or rider
			if source.depth > 0 then
				local cf = rider.base + Vector3.new(0, offsetFor(source, t), 0)
				root.CFrame = cf
				rider.lastSet = cf
			end
		end
	end
	-- placed after the rise began: your own whir and light start now
	if state.started and not state.locked then
		startLocalLift(t)
	end
end

-- Public API ----------------------------------------------------------------------------------------------------------------

function LaunchController.isLaunching(): boolean
	return state ~= nil
end

function LaunchController.getRise(): number
	if not state then
		return 1
	end
	return math.clamp((now() - state.launchAt) / math.max(0.05, state.riseEnd - state.launchAt), 0, 1)
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------------

function LaunchController.Init(registry)
	Controllers = registry
end

local function onPhase()
	local phase = GameState:GetAttribute("Phase")
	local roundId = GameState:GetAttribute("RoundId")
	if phase == "Countdown" then
		if watchedRound ~= roundId then
			watchedRound = roundId
			begin()
		end
	else
		restoreAll()
	end
end

function LaunchController.Start()
	GameState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	GameState:GetAttributeChangedSignal("LaunchAt"):Connect(function()
		if GameState:GetAttribute("Phase") == "Countdown" and state then
			local launchAt = tonumber(GameState:GetAttribute("LaunchAt"))
			if launchAt and math.abs(launchAt - state.launchAt) > 0.05 and not state.started then
				watchedRound = nil
				onPhase()
			end
		end
	end)
	-- frozen on a plate and pressing to move: make the countdown caption answer
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not (ClientState.frozen and ClientState.inArena) then
			return
		end
		local key = input.KeyCode
		local moving = key == Enum.KeyCode.W or key == Enum.KeyCode.A or key == Enum.KeyCode.S or key == Enum.KeyCode.D
			or key == Enum.KeyCode.Up or key == Enum.KeyCode.Down or key == Enum.KeyCode.Left or key == Enum.KeyCode.Right
			or key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.Thumbstick1
			or input.UserInputType == Enum.UserInputType.Touch
		if moving then
			local notifications = Controllers and Controllers.NotificationController
			if notifications and notifications.pulseCountdown then
				pcall(notifications.pulseCountdown)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		if state then
			local ok, err = pcall(step)
			if not ok then
				warn("[LaunchController] " .. tostring(err))
				pcall(restoreAll)
				state = nil
			end
		end
	end)
	onPhase()
end

return LaunchController
