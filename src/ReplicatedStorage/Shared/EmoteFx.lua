--[[
	EmoteFx - what the season-one emotes and launch effects do (the Crates catalogue's "Emote" and "Launch effect"
	items; equipped in the shop, ShopService keeps them in Econ.Shop.Equipped["Emote"] / ["Launch effect"]).
	Client only, purely visual: nothing here touches movement, combat or hitboxes. Clean only (no blood, no Neon,
	matte parts that never collide, never cast shadows and are never hit by a ray).

	Who has what: TrailService mirrors the equipped ids to player attributes, so every client can draw anyone's:
	  EmoteFx.EMOTE_ATTR  = "EquippedEmote"      EmoteFx.LAUNCH_ATTR = "EquippedLaunchFx"     ("" = none)

	Emotes play one of Roblox's own R15 animations (Roblox-owned, nothing uploaded) on the character's Animator with
	a small effect of their own (ParticleEmitter / Trail / a few parts). An emote ends by itself or as soon as the
	character moves or jumps. TrailController binds the key (J) and relays it through the server so others see it.
	Launch effects play around a contender during the launch: "rise" effects during the plate's rise (the launch
	intro's case, LaunchIntroController), "arrive" effects when the plate stops (on the plinth in the arena).

	API
	  EmoteFx.EMOTES[id] / EmoteFx.LAUNCH[id]     the known ids (catalogue snake case)
	  EmoteFx.emoteName(id) -> string?            EmoteFx.launchName(id) -> string?
	  EmoteFx.playEmote(character, id) -> number?    seconds it runs (nil: unknown id or no humanoid); one at a time per
	                                                 character (a new one ends the last)
	  EmoteFx.stopEmote(character)                   EmoteFx.isPlaying(character) -> boolean
	  EmoteFx.playLaunch(id, phase, anchor, parent?, seconds?) -> (() -> ())?
	      phase "rise" | "arrive"; anchor: a BasePart the effect follows (its top face = the floor under the feet), a
	      function returning that CFrame each frame, or a CFrame (feet, facing -Z); returns a stop function (nil: this effect has nothing for that phase)
	  EmoteFx.launchPhases(id) -> { rise = boolean, arrive = boolean }
]]
local RunService = game:GetService("RunService")

local EmoteFx = {}

EmoteFx.EMOTE_ATTR = "EquippedEmote"
EmoteFx.LAUNCH_ATTR = "EquippedLaunchFx"

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}
local rng = Random.new()
local V3 = Vector3.new

local function anim(id: number): string
	return "rbxassetid://" .. id
end

-- Roblox's own R15 animations (the default Animate script's): usable in every experience, nothing uploaded
local ANIM = {
	slash = anim(522635514),
	lunge = anim(522638767),
	point = anim(507770453),
	wave = anim(507770239),
	cheer = anim(507770677),
}

EmoteFx.EMOTES = {
	whetstone = { name = "Whetstone", anim = ANIM.slash, speed = 0.45, seconds = 2.6, fx = "sparks" },
	blade_twirl = { name = "Blade Twirl", anim = ANIM.lunge, speed = 0.7, seconds = 2.0, fx = "twirl" },
	map_check = { name = "Map Check", anim = ANIM.point, speed = 0.6, seconds = 2.8, fx = "map" },
	campfire_hands = { name = "Campfire Hands", anim = ANIM.wave, speed = 0.35, seconds = 4.5, fx = "campfire" },
	last_one_standing = { name = "Last One Standing", anim = ANIM.cheer, speed = 0.5, seconds = 3.2, fx = "dust" },
}

EmoteFx.LAUNCH = {
	steam_vent = { name = "Steam Vent", rise = "steam" },
	dust_ring = { name = "Dust Ring", arrive = "dustRing" },
	leaf_ring = { name = "Leaf Ring", rise = "leaves" },
	banner_unfurl = { name = "Banner Unfurl", arrive = "banner" },
}

function EmoteFx.emoteName(id: any): string?
	local e = type(id) == "string" and EmoteFx.EMOTES[id]
	return if e then e.name else nil
end

function EmoteFx.launchName(id: any): string?
	local e = type(id) == "string" and EmoteFx.LAUNCH[id]
	return if e then e.name else nil
end

function EmoteFx.launchPhases(id: any): { rise: boolean, arrive: boolean }
	local e = type(id) == "string" and EmoteFx.LAUNCH[id]
	return { rise = e ~= nil and e.rise ~= nil, arrive = e ~= nil and e.arrive ~= nil }
end

-- Pieces ---------------------------------------------------------------------------------------------------------------

local function part(parent: Instance, size: Vector3, color: Color3, cf: CFrame?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if cf then
		p.CFrame = cf
	end
	p.Parent = parent
	return p
end

local function seq(...): NumberSequence
	local pts = { ... }
	local keys = {}
	for i = 1, #pts, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(pts[i], pts[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function emitter(at: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Shape = Enum.ParticleEmitterShape.Box
	for k, v in pairs(props) do
		(e :: any)[k] = v
	end
	e.Parent = at
	return e
end

local function cs(a: Color3, b: Color3?): ColorSequence
	return ColorSequence.new(a, b or a)
end

-- an effect's own folder, followed each frame to `follow()` (a CFrame), cleaned up by the returned stop
local function holder(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = "EmoteFx_" .. name
	m.Parent = parent
	return m
end

local function stopAfter(m: Instance, emitters: { ParticleEmitter }, linger: number)
	for _, e in ipairs(emitters) do
		e.Enabled = false
	end
	task.delay(linger, function()
		m:Destroy()
	end)
end

-- Emote effects (around a character) -----------------------------------------------------------------------------------

local function bodyPart(character: Model, names: { string }): BasePart?
	for _, n in ipairs(names) do
		local p = character:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local EMOTE_FX = {}

-- whetstone: a small grey stone in the left hand, amber sparks off the right as it strokes
function EMOTE_FX.sparks(character: Model, m: Model)
	local right = bodyPart(character, { "RightHand", "Right Arm" })
	local left = bodyPart(character, { "LeftHand", "Left Arm" })
	local ems = {}
	local stone: Part? = nil
	if left then
		stone = part(m, V3(0.5, 0.22, 0.28), Color3.fromRGB(120, 122, 120))
	end
	if right then
		local a = Instance.new("Attachment")
		a.Parent = right
		a.Position = V3(0, -0.4, 0)
		table.insert(ems, emitter(a, {
			Texture = TEX.spark, Color = cs(Color3.fromRGB(255, 214, 140), Color3.fromRGB(232, 182, 90)),
			Size = seq(0, 0.18, 1, 0), Lifetime = NumberRange.new(0.25, 0.45), Rate = 26,
			Speed = NumberRange.new(5, 9), SpreadAngle = Vector2.new(50, 50), Acceleration = V3(0, -18, 0),
			LightEmission = 0.6, Drag = 2,
		}))
		m.Destroying:Connect(function()
			a:Destroy()
		end)
	end
	return function()
		if stone and left then
			stone.CFrame = left.CFrame * CFrame.new(0, -0.55, 0)
		end
	end, ems
end

-- blade twirl: a silver glint ribbon round the right hand (a Trail on a spinning point)
function EMOTE_FX.twirl(character: Model, m: Model)
	local right = bodyPart(character, { "RightHand", "Right Arm" })
	if not right then
		return nil, {}
	end
	local p = part(m, V3(0.1, 0.1, 0.1), Color3.new(1, 1, 1))
	p.Transparency = 1
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = V3(0, 0.15, 0), V3(0, -0.15, 0)
	a0.Parent, a1.Parent = p, p
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.22
	t.Color = cs(Color3.fromRGB(236, 238, 240), Color3.fromRGB(190, 196, 204))
	t.Transparency = seq(0, 0.3, 1, 1)
	t.LightEmission = 0.3
	t.FaceCamera = true
	t.Parent = p
	local t0 = os.clock()
	return function()
		local a = (os.clock() - t0) * 14
		p.CFrame = right.CFrame * CFrame.new(math.cos(a) * 1.3, -0.6, math.sin(a) * 1.3)
	end, {}
end

-- map check: a pale folded map held up in both hands
function EMOTE_FX.map(character: Model, m: Model)
	local right = bodyPart(character, { "RightHand", "Right Arm" })
	local head = bodyPart(character, { "Head" })
	local sheet = part(m, V3(1.6, 1.1, 0.04), Color3.fromRGB(226, 214, 186))
	local line = part(m, V3(1.2, 0.05, 0.045), Color3.fromRGB(150, 120, 90))
	return function()
		if right and head then
			local cf = head.CFrame * CFrame.new(0.2, -0.9, -1.3) * CFrame.Angles(math.rad(-30), 0, 0)
			sheet.CFrame = cf
			line.CFrame = cf * CFrame.new(0, 0.1, -0.01)
		end
	end, {}
end

-- campfire hands: a small fire of three logs in front, warm light and a little smoke
function EMOTE_FX.campfire(character: Model, m: Model)
	local root = bodyPart(character, { "HumanoidRootPart" })
	if not root then
		return nil, {}
	end
	local hip = 3
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hip = hum.HipHeight + root.Size.Y / 2
	end
	local base = root.CFrame * CFrame.new(0, -hip, -2.6)
	base = CFrame.new(base.Position) * (root.CFrame - root.CFrame.Position)
	for i = 0, 2 do
		part(m, V3(1.5, 0.3, 0.3), Color3.fromRGB(96, 66, 44),
			base * CFrame.Angles(0, math.rad(i * 60), 0) * CFrame.new(0, 0.15, 0))
	end
	local core = part(m, V3(0.6, 0.2, 0.6), Color3.fromRGB(60, 52, 48), base * CFrame.new(0, 0.3, 0))
	core.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 10
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = core
	local ems = {
		emitter(core, {
			Texture = TEX.fire, Color = cs(Color3.fromRGB(255, 196, 110), Color3.fromRGB(226, 110, 50)),
			Size = seq(0, 0.9, 1, 0.2), Lifetime = NumberRange.new(0.5, 0.8), Rate = 30, Speed = NumberRange.new(2, 3.5),
			SpreadAngle = Vector2.new(12, 12), Transparency = seq(0, 0.2, 1, 1), LightEmission = 0.7,
			EmissionDirection = Enum.NormalId.Top,
		}),
		emitter(core, {
			Texture = TEX.smoke, Color = cs(Color3.fromRGB(150, 146, 140)), Size = seq(0, 0.6, 1, 2.2),
			Lifetime = NumberRange.new(1.6, 2.4), Rate = 6, Speed = NumberRange.new(2, 3), Transparency = seq(0, 0.7, 1, 1),
			EmissionDirection = Enum.NormalId.Top, RotSpeed = NumberRange.new(-30, 30),
		}),
	}
	return nil, ems
end

-- last one standing: a slow drift of dust round the feet as you look out
function EMOTE_FX.dust(character: Model, m: Model)
	local root = bodyPart(character, { "HumanoidRootPart" })
	if not root then
		return nil, {}
	end
	local p = part(m, V3(5, 0.2, 5), Color3.new(1, 1, 1))
	p.Transparency = 1
	local ems = {
		emitter(p, {
			Texture = TEX.smoke, Color = cs(Color3.fromRGB(196, 182, 156)), Size = seq(0, 0.8, 1, 2.4),
			Lifetime = NumberRange.new(1.5, 2.5), Rate = 10, Speed = NumberRange.new(0.5, 1.5),
			Transparency = seq(0, 0.65, 1, 1), Acceleration = V3(1.5, 0.3, 0), RotSpeed = NumberRange.new(-20, 20),
		}),
	}
	local hum = character:FindFirstChildOfClass("Humanoid")
	local hip = if hum then hum.HipHeight + root.Size.Y / 2 else 3
	return function()
		p.CFrame = root.CFrame * CFrame.new(0, -hip + 0.2, 0)
	end, ems
end

-- Playing an emote -------------------------------------------------------------------------------------------------------

local playing: { [Model]: { stop: () -> () } } = {}

function EmoteFx.isPlaying(character: Model?): boolean
	return character ~= nil and playing[character] ~= nil
end

function EmoteFx.stopEmote(character: Model)
	local p = playing[character]
	if p then
		playing[character] = nil
		p.stop()
	end
end

function EmoteFx.playEmote(character: Model?, id: any): number?
	local def = type(id) == "string" and EmoteFx.EMOTES[id]
	if not def or not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	EmoteFx.stopEmote(character)
	local m = holder(workspace, id)
	local track: AnimationTrack? = nil
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		pcall(function()
			local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
			local a = Instance.new("Animation")
			a.AnimationId = def.anim
			track = (animator :: any):LoadAnimation(a)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0.2, 1, def.speed or 1)
		end)
	end
	local step, ems = nil, {}
	local okFx, s, e = pcall(EMOTE_FX[def.fx], character, m)
	if okFx then
		step, ems = s, e or {}
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local stopped = false
	local function stop()
		if stopped then
			return
		end
		stopped = true
		if conn then
			conn:Disconnect()
		end
		if track then
			pcall(function()
				track:Stop(0.3)
			end)
		end
		stopAfter(m, ems, 1.5)
	end
	playing[character] = { stop = stop }
	conn = RunService.Heartbeat:Connect(function()
		local moving = humanoid.MoveDirection.Magnitude > 0.1 or humanoid.Jump
		if os.clock() - t0 > def.seconds or moving or humanoid.Health <= 0 or not character.Parent then
			if playing[character] and playing[character].stop == stop then
				playing[character] = nil
			end
			stop()
			return
		end
		if step then
			pcall(step)
		end
	end)
	return def.seconds
end

-- Launch effects ----------------------------------------------------------------------------------------------------------

local function anchorCF(anchor: any): CFrame
	if typeof(anchor) == "CFrame" then
		return anchor
	elseif type(anchor) == "function" then
		return anchor()
	end
	local p = anchor :: BasePart
	return p.CFrame * CFrame.new(0, p.Size.Y / 2, 0)
end

local LAUNCH_FX = {}

-- steam vent: white steam jets from four points round the base, up past you
function LAUNCH_FX.steam(anchor: any, m: Model)
	local ems = {}
	local nodes = {}
	for i = 0, 3 do
		local p = part(m, V3(0.4, 0.2, 0.4), Color3.new(1, 1, 1))
		p.Transparency = 1
		local a = math.rad(45 + i * 90)
		nodes[i + 1] = { part = p, offset = CFrame.new(math.cos(a) * 2.4, 0.2, math.sin(a) * 2.4) }
		table.insert(ems, emitter(p, {
			Texture = TEX.smoke, Color = cs(Color3.fromRGB(240, 242, 244), Color3.fromRGB(214, 218, 222)),
			Size = seq(0, 0.7, 0.4, 2.2, 1, 3.6), Lifetime = NumberRange.new(1.0, 1.6), Rate = 22,
			Speed = NumberRange.new(9, 14), SpreadAngle = Vector2.new(8, 8), Transparency = seq(0, 0.35, 0.6, 0.7, 1, 1),
			EmissionDirection = Enum.NormalId.Top, Drag = 1.5, RotSpeed = NumberRange.new(-40, 40),
			Rotation = NumberRange.new(0, 360),
		}))
	end
	return function()
		local cf = anchorCF(anchor)
		for _, n in ipairs(nodes) do
			n.part.CFrame = cf * n.offset
		end
	end, ems
end

-- leaf ring: matte leaves spiral up round you, tumbling
function LAUNCH_FX.leaves(anchor: any, m: Model)
	local colors = { Color3.fromRGB(150, 160, 80), Color3.fromRGB(196, 140, 60), Color3.fromRGB(120, 140, 70),
		Color3.fromRGB(176, 110, 56) }
	local leaves = {}
	for i = 1, 16 do
		local p = part(m, V3(0.42, 0.04, 0.26), colors[(i - 1) % #colors + 1])
		-- (no Trail: on a rising disc a world-space trail drew long green bars down the shaft)
		leaves[i] = { part = p, phase = rng:NextNumber(0, math.pi * 2), r = rng:NextNumber(2.2, 3.4),
			climb = rng:NextNumber(0, 1), speed = rng:NextNumber(0.25, 0.45), spin = rng:NextNumber(2, 4) }
	end
	local t0 = os.clock()
	return function()
		local cf = anchorCF(anchor)
		local t = os.clock() - t0
		for _, l in ipairs(leaves) do
			local u = (l.climb + t * l.speed) % 1
			local a = l.phase + t * 2.2
			local y = u * 9
			l.part.CFrame = cf * CFrame.new(math.cos(a) * l.r, y, math.sin(a) * l.r)
				* CFrame.Angles(t * l.spin, a, t * l.spin * 0.7)
			l.part.Transparency = if u > 0.85 then (u - 0.85) / 0.15 else 0
		end
	end, {}
end

-- dust ring: a ring of dust rolls out across the ground when the plate stops
function LAUNCH_FX.dustRing(anchor: any, m: Model)
	local cf = anchorCF(anchor)
	local ems = {}
	for i = 0, 11 do
		local a = math.rad(i * 30)
		local p = part(m, V3(0.5, 0.2, 0.5), Color3.new(1, 1, 1), cf * CFrame.new(math.cos(a) * 2.2, 0.1, math.sin(a) * 2.2)
			* CFrame.Angles(0, -a, 0))
		p.Transparency = 1
		local e = emitter(p, {
			Texture = TEX.smoke, Color = cs(Color3.fromRGB(196, 180, 150), Color3.fromRGB(170, 156, 130)),
			Size = seq(0, 1.2, 1, 3.4), Lifetime = NumberRange.new(1.0, 1.6), Rate = 0, Speed = NumberRange.new(8, 12),
			SpreadAngle = Vector2.new(10, 25), Transparency = seq(0, 0.45, 1, 1), EmissionDirection = Enum.NormalId.Right,
			Drag = 3, Acceleration = V3(0, 1, 0), RotSpeed = NumberRange.new(-40, 40), Rotation = NumberRange.new(0, 360),
		})
		e:Emit(6)
		table.insert(ems, e)
	end
	return nil, ems
end

-- banner unfurl: a pole rises behind you and your banner drops from it
function LAUNCH_FX.banner(anchor: any, m: Model)
	local cf = anchorCF(anchor) * CFrame.new(0, 0, 2.2)
	part(m, V3(0.2, 7, 0.2), Color3.fromRGB(70, 60, 52), cf * CFrame.new(0, 3.5, 0))
	part(m, V3(2.6, 0.16, 0.16), Color3.fromRGB(150, 120, 70), cf * CFrame.new(0, 6.9, -0.2))
	local cloth = part(m, V3(2.4, 0.05, 0.05), Color3.fromRGB(180, 150, 110), cf * CFrame.new(0, 6.85, -0.25))
	local hem = part(m, V3(2.4, 0.12, 0.08), Color3.fromRGB(120, 92, 64), cf * CFrame.new(0, 6.8, -0.25))
	local t0 = os.clock()
	return function()
		local k = math.clamp((os.clock() - t0) / 0.9, 0, 1)
		k = 1 - (1 - k) ^ 3
		local h = 0.05 + 3.6 * k
		cloth.Size = V3(2.4, h, 0.05)
		cloth.CFrame = cf * CFrame.new(0, 6.85 - h / 2, -0.25) * CFrame.Angles(math.rad(2 * math.sin(os.clock() * 3)), 0, 0)
		hem.CFrame = cf * CFrame.new(0, 6.85 - h, -0.25)
	end, {}
end

function EmoteFx.playLaunch(id: any, phase: string, anchor: any, parent: Instance?, seconds: number?): (() -> ())?
	local def = type(id) == "string" and EmoteFx.LAUNCH[id]
	local kind = def and (if phase == "rise" then def.rise elseif phase == "arrive" then def.arrive else nil)
	if not kind or anchor == nil then
		return nil
	end
	local m = holder(parent or workspace, id)
	local ok, step, ems = pcall(LAUNCH_FX[kind], anchor, m)
	if not ok then
		m:Destroy()
		warn("[EmoteFx] " .. tostring(step))
		return nil
	end
	ems = ems or {}
	local conn: RBXScriptConnection? = nil
	local done = false
	local function stop()
		if done then
			return
		end
		done = true
		if conn then
			conn:Disconnect()
		end
		stopAfter(m, ems, 2)
	end
	if step then
		pcall(step)
		conn = RunService.RenderStepped:Connect(function()
			if typeof(anchor) == "Instance" and not anchor.Parent then
				stop()
				return
			end
			pcall(step)
		end)
	end
	local life = seconds or (if kind == "banner" then 9 elseif kind == "dustRing" then 2.5 else 6)
	task.delay(life, stop)
	return stop
end

return EmoteFx
