--[[
	LoadInController - "the Gathering" (docs/design/Combat_v3.md section 6): when a player appears, a swirl of leaves and
	soft light gathers into them, after the owner's "Nature Trail VFX" reference. Client only, purely visual, 0.85 s.

	When
	  * In the red train: a character spawning there (joining, or back after a round): InArena not true.
	  * At the arena: a player's InArena turning true (put on their plinth). Everyone's plays together at the end of the
	    launch: once this client's launch shot has handed the camera back (ClientState.launchShot) and the plates have
	    risen (GameState LaunchAt + LaunchRise), at most WAIT_MAX seconds after.
	  * A character attribute AppearedAt (server time) set by a server, if one ever is, plays it when within 1 s of now.
	  Never twice for one character within 2 s. Not while spectating someone else's view of it (it simply plays where they are).

	What (0.00 - 0.85 s), valley colours: moss, meadow, birch gold, soft sky light
	  0.00 - 0.35  14 matte leaves (two shapes: a round birch leaf and a pointed one) sweep in on a rising spiral from 4 studs
	               out, 1.5 turns, from the feet to head height, speeding up; two soft light ribbons (Trails) circle with them;
	               the body fades in from the feet up (others only: your own body is the camera's in first person)
	  0.35 - 0.60  the spiral tightens to the chest; the leaves shrink into the body; one PointLight swells and fades
	  0.60 - 0.85  4 leaves fall loose to the feet and fade; 8 sparkles drift up
	Matte where it matters: the leaves are plain SmoothPlastic parts; only the ribbons and sparkles have light, briefly.

	Cheap
	  Pooled rigs, moved with one workspace:BulkMoveTo a frame (no physics, no tweens). Full effects for at most FULL_MAX
	  at once (you first, then the nearest), within FULL_RANGE; beyond that or past it the ribbons only (pool by tier),
	  beyond RIBBON_RANGE nothing. Low detail tier: 6 leaves.

	API
	  LoadInController.play(character, opts?) -> boolean   opts.full = true forces a full rig (the Loadout preview)
	  LoadInController.stats() -> { full, ribbons, updateMs }
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local okSfx, Sfx = pcall(require, Shared:WaitForChild("Sfx"))
local okSounds, Sounds = pcall(require, Shared:WaitForChild("Sounds"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local cfg = (type(Config.LoadIn) == "table" and Config.LoadIn) or {}
local DURATION = cfg.Duration or 0.85
local LEAVES = cfg.Leaves or 14
local LOW_LEAVES = cfg.LowLeaves or 6
local FULL_MAX = cfg.FullMax or 6
local FULL_RANGE = cfg.FullRange or 80
local RIBBON_RANGE = cfg.RibbonRange or 160
local COLORS = cfg.Colors or {}
local MOSS = COLORS.Moss or Color3.fromRGB(96, 124, 64)
local MEADOW = COLORS.Meadow or Color3.fromRGB(150, 176, 92)
local GOLD = COLORS.Gold or Color3.fromRGB(214, 190, 112)
local SKY = COLORS.Sky or Color3.fromRGB(236, 232, 206)
local LEAF_COLORS = { MOSS, MEADOW, GOLD, Color3.fromRGB(122, 150, 74), Color3.fromRGB(186, 178, 96) }
local RIBBON_POOL = { High = 24, Medium = 12, Low = 6 }
local WAIT_MAX = 20
local REPEAT_GUARD = 2
local PARK = CFrame.new(0, -5000, 0)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local LEAF_SIZE = 0.34

local LoadInController = {}

local folder: Folder? = nil
local fullPool: { any } = {}
local ribbonPool: { any } = {}
local active: { any } = {}
local lastPlayed = setmetatable({}, { __mode = "k" }) :: { [Model]: number }
local queued: { { character: Model, at: number } } = {}
local lastUpdateMs = 0
local rng = Random.new()

local function tier(): string
	local t = player:GetAttribute("DetailTier")
	return if t == "Low" or t == "Medium" or t == "High" then t else "High"
end

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "ClientLoadIn"
	f.Parent = workspace
	folder = f
	return f
end

local function plainPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = PARK
	return p
end

-- A ribbon: an invisible carrier with a soft Trail (meadow to sky light)
local function newRibbon(parent: Instance)
	local carrier = plainPart("Ribbon", Vector3.new(0.1, 0.1, 0.1))
	carrier.Transparency = 1
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.14, 0)
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.14, 0)
	a1.Parent = carrier
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(SKY, MEADOW)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.3) })
	trail.Lifetime = 0.32
	trail.LightEmission = 0.35
	trail.LightInfluence = 0.4
	trail.Brightness = 1.4
	trail.FaceCamera = true
	trail.MinLength = 0.04
	trail.Enabled = false
	trail.Parent = carrier
	carrier.Parent = parent
	return { part = carrier, trail = trail }
end

local function newRig(full: boolean)
	local model = Instance.new("Folder")
	model.Name = if full then "Gathering" else "GatheringRibbons"
	local rig = { full = full, folder = model, leaves = {}, ribbons = {}, parts = {}, cframes = {}, busy = false }
	rig.ribbons[1] = newRibbon(model)
	rig.ribbons[2] = newRibbon(model)
	table.insert(rig.parts, rig.ribbons[1].part)
	table.insert(rig.parts, rig.ribbons[2].part)
	if full then
		for i = 1, LEAVES do
			local round = i % 2 == 0
			local leaf: Part
			if round then
				leaf = plainPart("Leaf", Vector3.new(0.035, LEAF_SIZE, LEAF_SIZE))
				leaf.Shape = Enum.PartType.Cylinder -- a round birch leaf (a disc)
			else
				leaf = plainPart("Leaf", Vector3.new(LEAF_SIZE * 0.72, 0.035, LEAF_SIZE * 0.72)) -- turned 45 degrees: a pointed leaf
			end
			leaf.Color = LEAF_COLORS[(i - 1) % #LEAF_COLORS + 1]
			leaf.Transparency = 0
			leaf.Parent = model
			table.insert(rig.leaves, { part = leaf, round = round, size = leaf.Size, phase = 0, spin = 0, lift = 0, loose = false })
			table.insert(rig.parts, leaf)
		end
		local center = plainPart("Glow", Vector3.new(0.1, 0.1, 0.1))
		center.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 8
		light.Brightness = 0
		light.Shadows = false
		light.Parent = center
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = SPARKLE
		sparks.Color = ColorSequence.new(SKY, GOLD)
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		sparks.Lifetime = NumberRange.new(0.6, 0.9)
		sparks.Speed = NumberRange.new(1, 2.2)
		sparks.SpreadAngle = Vector2.new(40, 40)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Acceleration = Vector3.new(0, 1, 0)
		sparks.Drag = 1.5
		sparks.LightEmission = 0.7
		sparks.LightInfluence = 0.3
		sparks.Rate = 0
		sparks.Enabled = true
		sparks.Parent = center
		center.Parent = model
		rig.center = center
		rig.light = light
		rig.sparks = sparks
		table.insert(rig.parts, center)
	end
	for i = 1, #rig.parts do
		rig.cframes[i] = PARK
	end
	model.Parent = getFolder()
	return rig
end

local function takeRig(full: boolean): any?
	local pool = if full then fullPool else ribbonPool
	for _, rig in ipairs(pool) do
		if not rig.busy then
			return rig
		end
	end
	local cap = if full then FULL_MAX else (RIBBON_POOL[tier()] or 12)
	if #pool >= cap then
		return nil
	end
	local rig = newRig(full)
	table.insert(pool, rig)
	return rig
end

local function countBusy(pool): number
	local n = 0
	for _, rig in ipairs(pool) do
		if rig.busy then
			n += 1
		end
	end
	return n
end

-- The body fades in from the feet up (others only)
local function bodyParts(character: Model, root: BasePart)
	local list = {}
	local feet = root.Position.Y - 3
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.LocalTransparencyModifier < 1 then
			table.insert(list, { part = d, h = math.clamp((d.Position.Y - feet) / 5.5, 0, 1) })
			d.LocalTransparencyModifier = 1
		end
	end
	return list
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function LoadInController.play(character: Model?, opts: { [string]: any }?): boolean
	if not character or not character.Parent then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local now = os.clock()
	if lastPlayed[character] and now - lastPlayed[character] < REPEAT_GUARD then
		return false
	end
	local camera = workspace.CurrentCamera
	local distance = if camera then (root.Position - camera.CFrame.Position).Magnitude else 0
	local isOwn = character == player.Character
	if not isOwn and distance > RIBBON_RANGE then
		return false
	end
	local wantFull = (opts and opts.full) or isOwn or distance <= FULL_RANGE
	local rig = nil
	if wantFull then
		rig = takeRig(true)
	end
	if not rig then
		rig = takeRig(false)
	end
	if not rig then
		return false
	end
	lastPlayed[character] = now
	rig.busy = true
	local leafCount = if tier() == "Low" then math.min(LOW_LEAVES, #rig.leaves) else #rig.leaves
	for i, leaf in ipairs(rig.leaves) do
		leaf.phase = (i - 1) / math.max(leafCount, 1) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		leaf.spin = rng:NextNumber(6, 12) * (if rng:NextNumber() < 0.5 then -1 else 1)
		leaf.lift = rng:NextNumber(-0.35, 0.35)
		leaf.radius = rng:NextNumber(3.4, 4.4)
		leaf.loose = i > leafCount - 4 -- the last 4 fall loose to the feet
		leaf.on = i <= leafCount
		leaf.part.Size = leaf.size
		leaf.part.Transparency = 0
	end
	for _, r in ipairs(rig.ribbons) do
		r.trail.Enabled = false
	end
	local entry = {
		rig = rig, character = character, root = root, t0 = now, own = isOwn, fadeBody = nil, sparked = false,
		started = false, slow = 1,
	}
	-- Studio only, for pictures: workspace attribute LS_LoadInSlowMo = n plays it n times slower
	local slow = workspace:GetAttribute("LS_LoadInSlowMo")
	if RunService:IsStudio() and type(slow) == "number" and slow >= 1 and slow <= 40 then
		entry.slow = slow
	end
	if not isOwn then
		entry.fadeBody = bodyParts(character, root)
	end
	table.insert(active, entry)
	if okSfx and okSounds and (isOwn or distance < 40) then
		local key = if Sounds.LoadIn_Gather then "LoadIn_Gather" else "Hazard_Flutter"
		if Sounds[key] then
			pcall(Sfx.play, key, { position = root.Position, volume = if key == "LoadIn_Gather" then nil else 0.35 })
		end
	end
	return true
end

local function finish(entry)
	local rig = entry.rig
	for _, r in ipairs(rig.ribbons) do
		r.trail.Enabled = false -- (before the carriers move away, so no stroke is drawn to the park)
	end
	-- the ribbons stay where they are while their last strokes fade; the leaves and the glow park at once
	for i = 3, #rig.parts do
		rig.cframes[i] = PARK
	end
	workspace:BulkMoveTo(rig.parts, rig.cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if rig.light then
		rig.light.Brightness = 0
	end
	if entry.fadeBody then
		for _, item in ipairs(entry.fadeBody) do
			if item.part.Parent and item.part.LocalTransparencyModifier ~= 0 then
				item.part.LocalTransparencyModifier = 0
			end
		end
	end
	-- the ribbons' last strokes fade over their lifetime before the rig is reused
	task.delay(0.4, function()
		rig.busy = false
	end)
end

local TAU = math.pi * 2

local function step(entry, now: number): boolean
	local t = (now - entry.t0) / entry.slow
	local rig = entry.rig
	local root = entry.root
	if not root.Parent or t >= DURATION then
		finish(entry)
		return false
	end
	local base = root.Position
	local feetY = base.Y - 2.9
	local headY = base.Y + 1.7
	local chestY = base.Y + 0.6
	-- the shared spiral at time t: angle offset, radius, height (0..1 of feet to head) and a shrink
	local function spiral(phase: number, r0: number, lift: number): (Vector3, number, number)
		local angle, radius, y, scale
		if t < 0.35 then
			local u = t / 0.35
			local e = u * u -- speeding up
			angle = phase + TAU * 1.5 * e
			radius = r0 + (1.6 - r0) * e
			y = feetY + (headY - feetY) * e + lift * (1 - e)
			scale = 1
		else
			local u = math.clamp((t - 0.35) / 0.25, 0, 1)
			local e = smooth(u)
			angle = phase + TAU * 1.5 + TAU * 0.7 * u
			radius = 1.6 + (0.25 - 1.6) * e
			y = headY + (chestY - headY) * e
			scale = 1 - e
		end
		return Vector3.new(base.X + math.cos(angle) * radius, y, base.Z + math.sin(angle) * radius), angle, scale
	end
	local parts, cframes = rig.parts, rig.cframes
	-- ribbons (indices 1 and 2)
	for k = 1, 2 do
		local position, angle = spiral((k - 1) * math.pi, 3.8, 0)
		cframes[k] = CFrame.new(position) * CFrame.Angles(0, -angle, 0)
		local on = t < 0.6
		local trail = rig.ribbons[k].trail
		if trail.Enabled ~= on and entry.started then
			if on then
				trail:Clear() -- (no stroke from where the rig was parked)
			end
			trail.Enabled = on
		end
	end
	entry.started = true -- (the trails switch on from the second frame, once the carriers stand on the spiral)
	-- leaves
	for i, leaf in ipairs(rig.leaves) do
		local index = 2 + i
		if not leaf.on then
			cframes[index] = PARK
		elseif leaf.loose and t >= 0.5 then
			-- falls loose: from where the spiral left it, drifting down to the feet, fading out
			local u = math.clamp((t - 0.5) / (DURATION - 0.5), 0, 1)
			local angle = leaf.phase + TAU * 2.1 + u * 1.2
			local radius = 1.0 + u * 0.6
			local y = chestY + (feetY + 0.1 - chestY) * smooth(u)
			cframes[index] = CFrame.new(base.X + math.cos(angle) * radius, y, base.Z + math.sin(angle) * radius)
				* CFrame.Angles(math.sin(t * leaf.spin) * 0.8, angle, math.cos(t * leaf.spin * 0.7) * 0.6)
			if u > 0.5 then
				leaf.part.Transparency = (u - 0.5) * 2
			end
			if leaf.part.Size ~= leaf.size * 0.8 then
				leaf.part.Size = leaf.size * 0.8
			end
		else
			local position, angle, scale = spiral(leaf.phase, leaf.radius, leaf.lift)
			if leaf.loose then
				scale = math.max(scale, 0.8)
			end
			if scale <= 0.02 then
				cframes[index] = PARK
			else
				local tilt = CFrame.Angles(t * leaf.spin, -angle, math.sin(t * leaf.spin) * 0.7)
				if not leaf.round then
					tilt *= CFrame.Angles(0, math.pi / 4, 0) -- the square plate turned to a point
				end
				cframes[index] = CFrame.new(position) * tilt
				if scale < 1 then
					leaf.part.Size = leaf.size * scale
				end
			end
		end
	end
	-- the glow and the sparkles
	if rig.center then
		local index = #parts
		cframes[index] = CFrame.new(base.X, chestY, base.Z)
		local glow = if t < 0.35 then 0 elseif t < 0.5 then (t - 0.35) / 0.15 else math.max(0, 1 - (t - 0.5) / 0.25)
		rig.light.Brightness = 0.3 * glow
		if not entry.sparked and t >= 0.6 then
			entry.sparked = true
			rig.sparks:Emit(8)
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	-- the body, feet first (others only)
	if entry.fadeBody then
		for _, item in ipairs(entry.fadeBody) do
			local show = smooth((t - 0.05 - item.h * 0.4) / 0.12)
			local want = 1 - show
			if item.part.Parent and math.abs(item.part.LocalTransparencyModifier - want) > 0.02 then
				item.part.LocalTransparencyModifier = want
			end
		end
	end
	return true
end

local function update()
	if #active == 0 then
		return
	end
	local t0 = os.clock()
	for i = #active, 1, -1 do
		local ok, alive = pcall(step, active[i], t0)
		if not ok then
			warn("[LoadInController] " .. tostring(alive))
			pcall(finish, active[i])
			table.remove(active, i)
		elseif not alive then
			table.remove(active, i)
		end
	end
	lastUpdateMs = (os.clock() - t0) * 1000
end

function LoadInController.stats()
	return { full = countBusy(fullPool), ribbons = countBusy(ribbonPool), pooledFull = #fullPool,
		pooledRibbons = #ribbonPool, updateMs = lastUpdateMs, active = #active }
end

--------------------------------------------------------------------------------------------------------------------
-- When
--------------------------------------------------------------------------------------------------------------------

-- The launch is still showing (the intro has the camera, or the plates are still rising)
local function launchBusy(): boolean
	if ClientState.launchShot == true then
		return true
	end
	local at = GameState:GetAttribute("LaunchAt")
	local rise = GameState:GetAttribute("LaunchRise")
	if type(at) == "number" and type(rise) == "number" then
		local now = workspace:GetServerTimeNow()
		return now >= at - 1 and now < at + rise
	end
	return false
end

-- Arena arrivals all play together at the end of the launch: you first, then the nearest
local function flush()
	if #queued == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else Vector3.zero
	table.sort(queued, function(a, b)
		local ownA, ownB = a.character == player.Character, b.character == player.Character
		if ownA ~= ownB then
			return ownA
		end
		local ra, rb = a.character:FindFirstChild("HumanoidRootPart"), b.character:FindFirstChild("HumanoidRootPart")
		local da = if ra and ra:IsA("BasePart") then (ra.Position - from).Magnitude else math.huge
		local db = if rb and rb:IsA("BasePart") then (rb.Position - from).Magnitude else math.huge
		return da < db
	end)
	local list = queued
	queued = {}
	for _, item in ipairs(list) do
		if os.clock() - item.at < WAIT_MAX + 5 then
			LoadInController.play(item.character)
		end
	end
end

local function queueArrival(target: Player)
	local character = target.Character
	if not character then
		return
	end
	table.insert(queued, { character = character, at = os.clock() })
end

local function watchPlayer(target: Player)
	local wasInArena = target:GetAttribute("InArena") == true
	target:GetAttributeChangedSignal("InArena"):Connect(function()
		local now = target:GetAttribute("InArena") == true
		if now and not wasInArena then
			task.delay(0.1, queueArrival, target) -- (the body is moved to the plinth with the same change)
		end
		wasInArena = now
	end)
	local function onCharacter(character: Model)
		task.delay(0.15, function()
			if character.Parent and target:GetAttribute("InArena") ~= true then
				LoadInController.play(character) -- spawned in the train
			end
		end)
		character:GetAttributeChangedSignal("AppearedAt"):Connect(function()
			local at = character:GetAttribute("AppearedAt")
			if type(at) == "number" and math.abs(workspace:GetServerTimeNow() - at) <= 1 then
				LoadInController.play(character)
			end
		end)
	end
	target.CharacterAdded:Connect(onCharacter)
	if target.Character then
		-- already here when we joined: no Gathering for an old arrival, only the AppearedAt hook
		target.Character:GetAttributeChangedSignal("AppearedAt"):Connect(function()
			local at = target.Character and target.Character:GetAttribute("AppearedAt")
			if type(at) == "number" and math.abs(workspace:GetServerTimeNow() - at) <= 1 then
				LoadInController.play(target.Character)
			end
		end)
	end
end

function LoadInController.Init(_controllers) end

function LoadInController.Start()
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	RunService.RenderStepped:Connect(update)
	-- arrivals wait for the launch to finish showing (at most WAIT_MAX)
	while true do
		task.wait(0.1)
		if #queued > 0 then
			local oldest = queued[1].at
			if not launchBusy() or os.clock() - oldest > WAIT_MAX then
				flush()
			end
		end
	end
end

return LoadInController
