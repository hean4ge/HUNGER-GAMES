--[[
	SlideFx - what a slide looks and sounds like (client only; the physics is Shared.SlidePhysics in MovementController).

	Spray: two world-space ParticleEmitters at the leading boot of each slider: square grit chips (low-poly: chunky
	faceted flakes in the ground's own terrain colour, thrown forward and up, falling under gravity) and a soft puff of
	dust (none on mud or in water; powder on snow). The rate follows the slide speed, so a fast downhill slide throws
	a long plume and a slow one a trickle; the chips are left behind as you slide past them.
	Sound: AudioController plays the slide's attack ("Slide", one recording); this adds a sustained scrape for long
	slides: the same recording looped quietly under it, fading in after the attack, level and pitch from speed and
	material, fading out when the slide ends.
	Others: contenders within REMOTE_RANGE whose Stance attribute is "Slide" get the spray too (at most REMOTE_MAX,
	nearest first, at a lower rate). Nothing runs while nobody is sliding.
	Budget: 2 emitters per slider, 4 sliders at most, ~45 chips/s and ~14 puffs/s at full speed (halved on low
	graphics quality); one looped Sound, local only.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local SlideFx = {}

local player = Players.LocalPlayer
local Controllers = nil

-- the slide's own recording (Sounds.Slide; today "Gravel Slide 2", PSE): sustained under its attack
local SLIDE_ID = "rbxassetid://9114658419"
local SLIDE_VOLUME = 1
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ok, Sounds = pcall(require, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))
	local entry = ok and type(Sounds) == "table" and Sounds.Slide
	if type(entry) == "table" and type(entry.ids) == "table" and type(entry.ids[1]) == "string" then
		SLIDE_ID = entry.ids[1]
		SLIDE_VOLUME = tonumber(entry.volume) or 1
	end
end
local SQUARE = "rbxasset://textures/particles/SquareParticle.png"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local REMOTE_RANGE = 70
local REMOTE_MAX = 3
local CHIPS_PER_S = 45 -- at full speed
local DUST_PER_S = 14
local FULL_SPEED = 28

-- per material: dust (true/false/"powder"), chip size scale, sound gain and pitch
local LOOK = {
	Grass = { dust = true, chip = 1, gain = 0.8, pitch = 1, earth = true },
	LeafyGrass = { dust = true, chip = 1.1, gain = 0.85, pitch = 0.98, earth = true },
	Ground = { dust = true, chip = 0.9, gain = 1, pitch = 1 },
	Mud = { dust = false, chip = 1.3, gain = 0.8, pitch = 0.82 },
	Sand = { dust = true, chip = 0.6, gain = 0.9, pitch = 1.08 },
	Snow = { dust = "powder", chip = 0.8, gain = 0.6, pitch = 1.15 },
	Glacier = { dust = "powder", chip = 0.6, gain = 0.5, pitch = 1.2 },
	Ice = { dust = false, chip = 0.5, gain = 0.4, pitch = 1.25 },
	Rock = { dust = true, chip = 0.7, gain = 1.1, pitch = 0.95 },
	Slate = { dust = true, chip = 0.7, gain = 1.1, pitch = 0.95 },
	Basalt = { dust = true, chip = 0.7, gain = 1.1, pitch = 0.92 },
	Pebble = { dust = true, chip = 0.75, gain = 1.15, pitch = 1 },
}
local DEFAULT_LOOK = { dust = true, chip = 0.8, gain = 1, pitch = 1 }
local FALLBACK_COLOR = Color3.fromRGB(116, 98, 74)

local qualityScale = 1

local function terrainColor(material: Enum.Material): Color3
	local ok, c = pcall(function()
		return workspace.Terrain:GetMaterialColor(material)
	end)
	return if ok and typeof(c) == "Color3" then c else FALLBACK_COLOR
end

local function makeEmitters(): (Attachment, ParticleEmitter, ParticleEmitter)
	local att = Instance.new("Attachment")
	att.Name = "SlideFx"
	local chips = Instance.new("ParticleEmitter")
	chips.Name = "Chips"
	chips.Texture = SQUARE
	chips.Rate = 0
	chips.Lifetime = NumberRange.new(0.35, 0.7)
	chips.Speed = NumberRange.new(6, 12)
	chips.SpreadAngle = Vector2.new(38, 22)
	chips.Acceleration = Vector3.new(0, -60, 0)
	chips.Drag = 1.5
	chips.Rotation = NumberRange.new(0, 360)
	chips.RotSpeed = NumberRange.new(-360, 360)
	chips.Size = NumberSequence.new(0.16)
	chips.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1) })
	chips.LightInfluence = 1
	chips.LightEmission = 0
	chips.Shape = Enum.ParticleEmitterShape.Box
	chips.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	chips.EmissionDirection = Enum.NormalId.Top
	chips.LockedToPart = false
	chips.Enabled = true
	chips.Parent = att
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = SMOKE
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.6, 1.1)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(50, 30)
	dust.Acceleration = Vector3.new(0, 1.5, 0)
	dust.Drag = 3
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.LightInfluence = 1
	dust.EmissionDirection = Enum.NormalId.Top
	dust.LockedToPart = false
	dust.Enabled = true
	dust.Parent = att
	return att, chips, dust
end

-- one spray rig per sliding character
local rigs: { [Model]: { att: Attachment, chips: ParticleEmitter, dust: ParticleEmitter, material: Enum.Material? } } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function release(character: Model)
	local r = rigs[character]
	if r then
		rigs[character] = nil
		r.chips.Rate, r.dust.Rate = 0, 0
		-- let the last chips land before the rig goes
		task.delay(1.2, function()
			r.att:Destroy()
		end)
	end
end

local function updateRig(character: Model, root: BasePart, humanoid: Humanoid, speed: number, dir: Vector3,
	scale: number)
	local r = rigs[character]
	if not r then
		local att, chips, dust = makeEmitters()
		att.Parent = workspace.Terrain
		r = { att = att, chips = chips, dust = dust, material = nil }
		rigs[character] = r
	end
	local legs = humanoid.HipHeight + root.Size.Y / 2
	rayParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(legs + 2.5), 0), rayParams)
	if not hit or hit.Material == Enum.Material.Water then
		r.chips.Rate, r.dust.Rate = 0, 0
		return
	end
	local material = hit.Material
	local look = LOOK[material.Name] or DEFAULT_LOOK
	if r.material ~= material then
		r.material = material
		local base = if hit.Instance == workspace.Terrain then terrainColor(material)
			elseif hit.Instance:IsA("BasePart") then (hit.Instance :: BasePart).Color else FALLBACK_COLOR
		local h, s, v = base:ToHSV()
		local dustBase = base
		if look.earth then
			-- a slide tears the turf: the chips are torn grass and the earth under it (green on green would vanish)
			dustBase = terrainColor(Enum.Material.Ground)
			local eh, es, ev = dustBase:ToHSV()
			r.chips.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(h, s, math.clamp(v * 0.8, 0, 1))),
				ColorSequenceKeypoint.new(0.45, Color3.fromHSV(eh, es, math.clamp(ev * 0.8, 0, 1))),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(eh, es * 0.9, math.clamp(ev * 0.95, 0, 1))),
			})
		else
			r.chips.Color = ColorSequence.new(Color3.fromHSV(h, s, math.clamp(v * 0.85, 0, 1)),
				Color3.fromHSV(h, s * 0.9, math.clamp(v * 1.05, 0, 1)))
		end
		local dh, ds, dv = dustBase:ToHSV()
		local dustColor = if look.dust == "powder" then Color3.fromRGB(240, 244, 248)
			else Color3.fromHSV(dh, ds * 0.35, math.clamp(dv * 1.25 + 0.15, 0, 1))
		r.dust.Color = ColorSequence.new(dustColor)
		r.chips.Size = NumberSequence.new(0.22 * look.chip)
	end
	-- the leading boot: ahead of the hips, on the ground; chips are kicked forward and up, a little to the sides
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local foot = Vector3.new(root.Position.X, hit.Position.Y + 0.15, root.Position.Z) + flat * 1.7
	local up = (flat * 0.75 + hit.Normal * 0.9).Unit
	local right = flat:Cross(up)
	if right.Magnitude < 1e-3 then
		right = Vector3.xAxis
	end
	r.att.WorldCFrame = CFrame.fromMatrix(foot, right.Unit, up)
	local k = math.clamp((speed - 4) / (FULL_SPEED - 4), 0, 1)
	r.chips.Speed = NumberRange.new(3 + 6 * k, 6 + 10 * k)
	r.chips.Rate = CHIPS_PER_S * k * scale * qualityScale
	r.dust.Rate = if look.dust then DUST_PER_S * (0.25 + 0.75 * k) * scale * qualityScale else 0
end

-- Sustained scrape (local) ----------------------------------------------------------------------------------------
local loop: Sound? = nil
local loopLevel = 0

local function ensureLoop(): Sound
	if loop and loop.Parent then
		return loop
	end
	local s = Instance.new("Sound")
	s.Name = "SlideScrape"
	s.SoundId = SLIDE_ID
	s.Looped = true
	s.Volume = 0
	local group = SoundService:FindFirstChild("SFX")
	if group and group:IsA("SoundGroup") then
		s.SoundGroup = group
	end
	s.Parent = SoundService
	loop = s
	return s
end

local function updateLoop(dt: number, sliding: boolean, age: number, speed: number, material: Enum.Material?)
	local look = (material and LOOK[material.Name]) or DEFAULT_LOOK
	local k = math.clamp(speed / FULL_SPEED, 0, 1.2)
	-- the attack is AudioController's one-shot; the sustain comes in under it after ~0.35 s
	local target = if sliding then 0.55 * SLIDE_VOLUME * k * look.gain * math.clamp((age - 0.35) / 0.4, 0, 1) else 0
	local rate = if target > loopLevel then 3 else 6
	loopLevel += (target - loopLevel) * (1 - math.exp(-rate * dt))
	if loopLevel < 0.005 and not sliding then
		if loop and loop.IsPlaying then
			loop:Stop()
		end
		loopLevel = 0
		return
	end
	local s = ensureLoop()
	if not s.IsPlaying then
		local len = s.TimeLength
		s.TimePosition = if len > 1 then math.random() * len * 0.6 else 0
		s:Play()
	end
	s.Volume = loopLevel
	s.PlaybackSpeed = look.pitch * (0.82 + 0.3 * math.min(k, 1))
end

-- Frame -----------------------------------------------------------------------------------------------------------
local lastRemoteScan = 0
local remoteList: { Model } = {}

local active: { [Model]: boolean } = {}

local function step(dt: number)
	table.clear(active)
	-- local slider
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local sliding = ClientState.moveState == "Slide" and root ~= nil and humanoid ~= nil
	local movement = Controllers and Controllers.MovementController
	local info = movement and type(movement.getSlide) == "function" and movement.getSlide() or nil
	local speed, age, material = 0, 0, nil
	if sliding and root and humanoid then
		local v = (root :: BasePart).AssemblyLinearVelocity
		local h = Vector3.new(v.X, 0, v.Z)
		speed = h.Magnitude
		age = if info and info.active then info.age else 1
		material = if info and info.active then info.material else humanoid.FloorMaterial
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if grounded and speed > 3 then
			updateRig(character :: Model, root :: BasePart, humanoid, speed, h, 1)
			active[character :: Model] = true
		end
	end
	updateLoop(dt, sliding, age, speed, material)

	-- nearby sliders (Stance attribute, MovementService)
	local now = os.clock()
	if now - lastRemoteScan > 0.25 then
		lastRemoteScan = now
		table.clear(remoteList)
		local here = root and (root :: BasePart).Position
		if here then
			local found = {}
			for _, other in ipairs(Players:GetPlayers()) do
				local ch = other.Character
				if other ~= player and ch and ch:GetAttribute("Stance") == "Slide" then
					local r = ch:FindFirstChild("HumanoidRootPart")
					if r and r:IsA("BasePart") then
						local d = (r.Position - here).Magnitude
						if d < REMOTE_RANGE then
							table.insert(found, { ch = ch, d = d })
						end
					end
				end
			end
			table.sort(found, function(a, b)
				return a.d < b.d
			end)
			for i = 1, math.min(REMOTE_MAX, #found) do
				table.insert(remoteList, found[i].ch)
			end
		end
	end
	for _, ch in ipairs(remoteList) do
		if ch.Parent and ch:GetAttribute("Stance") == "Slide" then
			local r = ch:FindFirstChild("HumanoidRootPart")
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if r and r:IsA("BasePart") and hum then
				local v = r.AssemblyLinearVelocity
				local h = Vector3.new(v.X, 0, v.Z)
				if h.Magnitude > 3 then
					updateRig(ch, r, hum, h.Magnitude, h, 0.6)
					active[ch] = true
				end
			end
		end
	end
	for ch in pairs(rigs) do
		if not active[ch] then
			release(ch)
		end
	end
end

function SlideFx.Init(registry)
	Controllers = registry
end

function SlideFx.Start()
	local function readQuality()
		local ok, level = pcall(function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
		end)
		-- 0 = automatic; 1..10 manual
		qualityScale = if ok and type(level) == "number" and level > 0 and level <= 3 then 0.5 else 1
	end
	readQuality()
	task.spawn(function()
		while true do
			task.wait(10)
			readQuality()
		end
	end)
	local warnedAt = -math.huge
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and os.clock() - warnedAt > 10 then
			warnedAt = os.clock()
			warn("[SlideFx] " .. tostring(err))
		end
	end)
end

return SlideFx
