--[[
	TrailController - draws cosmetic trails (docs/design/Combat_v3.md section 4; catalogue Shared.Trails) on swings,
	arrows and thrown items, for every player who has one equipped. Client only, purely visual.

	What each player has equipped arrives as player attributes (TrailService): TrailSwing / TrailArrow / TrailThrow.
	  Swings: your own from CombatController.action "Swing" (on the first-person viewmodel's item, or your body's in third
	    person); other players' from the CombatAction remote "Swing" (their EquippedModel). The ribbon shows from just
	    before the strike to the end of the cut plus 0.1 s, nothing on the weapon at rest.
	  Shots: ProjectileController asks TrailController.attachProjectile(...) for a handle when it creates a flying arrow
	    or thrown item, calls handle:follow(position, direction) as it draws it, and handle:release() when it lands or
	    goes. The trail starts Trails.START_AFTER studs from the hand (it never points back at the archer) and, on a hit,
	    lets go and fades where it is (nothing coloured lands on a body).
	Cost (Combat_v3 4.6): per swing or shot at most the recipe's Trails + 2 ParticleEmitters + 2 Beams; particle rates
	capped at Trails.MAX_RATE and 40 alive per emitter, scaled by the detail tier (LocalPlayer DetailTier); others' trails
	not drawn beyond Trails.DRAW_RANGE; at most TIER_CAP[tier] live shot trails and swing trails at once.
	Others' trails follow the viewer's choice: LocalPlayer attribute OthersTrails = "All" | "Natural" | "Off" (Natural
	draws others' Bright trails as Draught). Default All on PC and console, Natural on phones and at the Low tier. Your
	own trails always show to you.

	Emotes (Shared.EmoteFx): J (gamepad: none yet) plays your equipped emote (player attribute EquippedEmote, mirrored
	by TrailService from the shop's Equipped). It plays at once on your own character and goes to the server, which
	relays it to everyone ("emote", userId, id on the Trails remote); a quiet line names it. The game is first person,
	so while your own emote plays the camera eases out to a three-quarter view of you (your body shown, the first-person
	arms hidden) and eases back when it ends or you move. Not during the launch shot. With none equipped the line
	says so.

	API
	  TrailController.playEmote() -> boolean     (what J does)
	  TrailController.attachProjectile(itemId, shooterUserId, isLocal, origin, forcedId?) -> handle?
	      handle:follow(position: Vector3, direction: Vector3)   handle:release()
	  TrailController.swing(itemId, character: Model?, isLocal: boolean, windup: number, forcedId: string?)
	  TrailController.swingOn(part, baseLocal: Vector3, tipLocal: Vector3, id, onAt: number, offAt: number)
	      a ribbon between two points of any part (the Loadout preview on your avatar uses this)
	  TrailController.setOthers(mode)   TrailController.othersMode() -> string
	  TrailController.stats() -> { shots, swings, instances, updateMs }
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Trails = require(Shared:WaitForChild("Trails"))
local EmoteFx = require(Shared:WaitForChild("EmoteFx"))
local Input = require(Shared:WaitForChild("Input"))
local okClientState, ClientState = pcall(function()
	return require(script.Parent.Parent:WaitForChild("ClientState", 5) :: ModuleScript)
end)
if not okClientState then
	ClientState = nil
end

local player = Players.LocalPlayer

local TrailController = {}

local TIER_SCALE = { High = 1, Medium = 0.6, Low = 0.35 } -- particle rates
local TIER_CAP = { High = { shots = 16, swings = 12 }, Medium = { shots = 10, swings = 8 }, Low = { shots = 5, swings = 4 } }
local MAX_ALIVE = 40 -- particles alive per emitter
local SWING_LEAD = 0.05 -- the ribbon starts this long before the strike (the cut is already moving)
local SWING_TAIL = 0.16 -- ...and stops this long after it (the active part 0.06 + 0.1)
local SWING_RATE_MULT = 2.2 -- a swing is short: its particles come a little thicker
local FIST_HALF = 0.28
local SHOT_WIDTH = 1.7 -- shots are seen from further than swings: their ribbons are drawn wider than the recipe's
local SHOT_PARTICLE = 1.5 -- ...and their particles bigger
local DAY_EMISSION_CUT = 0.6 -- by day the glow is cut this much (see daylight())
local FP_SPAN = 0.3 -- first person: the ribbon covers this share of the recipe's span (near the tip)
local FP_FADE = 0.4 -- first person: this much fainter

local Controllers: any = nil
local remote: RemoteEvent? = nil
local fxFolder: Folder? = nil
local live: { any } = {} -- shot handles in flight or fading
local swingsLive = 0
local swingRigs = setmetatable({}, { __mode = "k" }) :: { [BasePart]: any }
local lastUpdateMs = 0
TrailController.lines = nil :: any -- a Signal-like hook for the shop's replies (set in Init if Signal exists)

--------------------------------------------------------------------------------------------------------------------
-- Settings and tier
--------------------------------------------------------------------------------------------------------------------

local function tier(): string
	local t = player:GetAttribute("DetailTier")
	return if TIER_SCALE[t] then t else "High"
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
end

local SETTING_MODES = { [1] = "All", [2] = "Natural", [3] = "Off" } -- Settings "Others' trails" (0 = Auto: by device)

function TrailController.othersMode(): string
	local okState, ClientState = pcall(require, script.Parent.Parent:FindFirstChild("ClientState") :: ModuleScript)
	local chosen = okState and type(ClientState) == "table" and ClientState.settings and SETTING_MODES[tonumber(ClientState.settings.othersTrails) or 0]
	if chosen then
		return chosen
	end
	local mode = player:GetAttribute("OthersTrails")
	if mode == "All" or mode == "Natural" or mode == "Off" then
		return mode
	end
	if isPhone() or tier() == "Low" then
		return Trails.OTHERS_DEFAULT.Phone or "Natural"
	end
	return Trails.OTHERS_DEFAULT.Desktop or "All"
end

function TrailController.setOthers(mode: string)
	if mode == "All" or mode == "Natural" or mode == "Off" then
		player:SetAttribute("OthersTrails", mode)
	end
end

-- The trail id to draw for `owner` in `slot`, after the viewer's setting (nil = none)
local function trailFor(owner: Player?, slot: string, forcedId: string?): string?
	local id = forcedId
	if id == nil then
		if owner == nil then
			return nil
		end
		id = owner:GetAttribute(Trails.ATTR[slot])
		if id == nil then
			id = Trails.DEFAULT[slot]
		end
	end
	if id == "none" or not Trails.get(id) then
		return nil
	end
	if owner ~= player and forcedId == nil then
		local mode = TrailController.othersMode()
		if mode == "Off" then
			return nil
		elseif mode == "Natural" and Trails.get(id).kind == "Bright" then
			id = "draught"
		end
	end
	return id
end

local function getFolder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientTrails"
	folder.Parent = workspace
	fxFolder = folder
	return folder
end

--------------------------------------------------------------------------------------------------------------------
-- Building a recipe
--------------------------------------------------------------------------------------------------------------------

local function colorSeq(c: { Color3 }): ColorSequence
	if #c >= 2 then
		return ColorSequence.new(c[1], c[2])
	end
	return ColorSequence.new(c[1])
end

local function alphaSeq(layer): NumberSequence
	if layer.bands then
		-- bright beats along the length that fade out toward the tail
		local n = layer.bands
		local keys = {}
		for i = 0, n * 2 do
			local t = i / (n * 2)
			local beat = if i % 2 == 0 then 0 else 0.78
			table.insert(keys, NumberSequenceKeypoint.new(t, math.clamp(beat + t * 0.25 * (1 - beat), 0, 1)))
		end
		keys[#keys] = NumberSequenceKeypoint.new(1, 1)
		return NumberSequence.new(keys)
	end
	local a = layer.alpha or { 0, 1 }
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a[1]), NumberSequenceKeypoint.new(1, a[2] or 1) })
end

-- 1 by day, 0 at night (dawn and dusk between). Additive light washes out on a bright meadow, so by day the glowing
-- trails lean on their own colour (lower LightEmission, unlit) and at night on their glow.
local function daylight(): number
	local clock = Lighting.ClockTime
	if clock >= 7 and clock <= 17 then
		return 1
	elseif clock > 5.5 and clock < 7 then
		return (clock - 5.5) / 1.5
	elseif clock > 17 and clock < 18.5 then
		return (18.5 - clock) / 1.5
	end
	return 0
end

local function emission(light: number?): number
	return (light or 0) * (1 - DAY_EMISSION_CUT * daylight())
end

local function newTrail(layer, a0: Attachment, a1: Attachment, parent: Instance): Trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = colorSeq(layer.color)
	trail.Transparency = alphaSeq(layer)
	trail.Lifetime = layer.life or 0.2
	trail.LightEmission = emission(layer.light)
	trail.LightInfluence = if (layer.light or 0) >= 0.5 then 0 else 1
	trail.Brightness = layer.bright or 1
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) })
	if layer.texture then
		trail.Texture = layer.texture
		trail.TextureMode = Enum.TextureMode.Wrap
		trail.TextureLength = layer.texLen or 1
	end
	trail.Enabled = false
	trail.Parent = parent
	return trail
end

local function newEmitter(layer, at: Attachment, rateMult: number, sizeMult: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = layer.texture
	e.Color = colorSeq(layer.color)
	local s = layer.size or { 0.3, 0 }
	local k = sizeMult or 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s[1] * k), NumberSequenceKeypoint.new(1, (s[2] or 0) * k) })
	e.Transparency = alphaSeq(layer)
	local life = layer.life or { 0.3, 0.5 }
	e.Lifetime = NumberRange.new(life[1], life[2] or life[1])
	local speed = layer.speed or { 0, 0 }
	e.Speed = NumberRange.new(speed[1], speed[2] or speed[1])
	e.Drag = layer.drag or 0
	e.Acceleration = layer.accel or Vector3.zero
	local spread = layer.spread or 0
	e.SpreadAngle = Vector2.new(spread, spread)
	local rot = layer.rot or { 0, 0 }
	e.Rotation = NumberRange.new(rot[1], rot[2] or rot[1])
	local rs = layer.rotSpeed or 0
	e.RotSpeed = NumberRange.new(-rs, rs)
	e.LightEmission = emission(layer.light)
	e.LightInfluence = if (layer.light or 0) >= 0.5 then 0 else 1
	e.Brightness = layer.bright or 1
	e.LockedToPart = layer.locked == true
	e.ZOffset = 0.2
	-- the cap: Trails.MAX_RATE, MAX_ALIVE alive (rate * longest life), scaled by the tier
	local maxLife = life[2] or life[1]
	local rate = math.min((layer.rate or 20) * rateMult, Trails.MAX_RATE, MAX_ALIVE / math.max(maxLife, 0.05))
	e.Rate = math.max(1, rate * (TIER_SCALE[tier()] or 1))
	e.Enabled = false
	e.Parent = at
	return e
end

-- Bolt: two Beams head -> mid -> tail behind the shot, the joints re-rolled every `every` seconds
local function newBolt(layer, carrier: BasePart)
	local head = Instance.new("Attachment")
	head.Parent = carrier
	local mid = Instance.new("Attachment")
	mid.Parent = carrier
	local tail = Instance.new("Attachment")
	tail.Parent = carrier
	local beams = {}
	for i, pair in ipairs({ { head, mid }, { mid, tail } }) do
		local b = Instance.new("Beam")
		b.Attachment0 = pair[1]
		b.Attachment1 = pair[2]
		b.Color = ColorSequence.new(layer.color)
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 3
		b.FaceCamera = true
		b.Segments = 1
		b.Width0 = layer.width * (if i == 1 then 1 else 0.7)
		b.Width1 = layer.width * (if i == 1 then 0.7 else 0.2)
		b.Transparency = NumberSequence.new(if i == 1 then 0 else 0.15, if i == 1 then 0.15 else 0.7)
		b.Enabled = false
		b.Parent = carrier
		table.insert(beams, b)
	end
	return { mid = mid, tail = tail, beams = beams, layer = layer, next = 0 }
end

local rng = Random.new()

local function rollBolt(bolt)
	local l = bolt.layer
	local j = l.jag
	bolt.mid.Position = Vector3.new(rng:NextNumber(-j, j), rng:NextNumber(-j, j), l.length * rng:NextNumber(0.35, 0.6))
	bolt.tail.Position = Vector3.new(rng:NextNumber(-j, j) * 1.4, rng:NextNumber(-j, j) * 1.4, l.length)
end

--------------------------------------------------------------------------------------------------------------------
-- Shots (arrows and thrown items)
--------------------------------------------------------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

function Handle:follow(position: Vector3, direction: Vector3)
	if self.released then
		return
	end
	local dir = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.zAxis
	local up = if math.abs(dir.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	self.carrier.CFrame = CFrame.lookAt(position, position + dir, up)
	if not self.on and (position - self.origin).Magnitude >= Trails.START_AFTER then
		self.on = true
		for _, t in ipairs(self.trails) do
			t:Clear() -- (no stroke back to where the carrier was made: the trail starts here, 6 studs out)
			t.Enabled = true
		end
		for _, e in ipairs(self.emitters) do
			e.Enabled = true
		end
		for _, bolt in ipairs(self.bolts) do
			rollBolt(bolt)
			for _, b in ipairs(bolt.beams) do
				b.Enabled = true
			end
		end
	end
end

function Handle:release()
	if self.released then
		return
	end
	self.released = true
	self.fadeAt = os.clock()
	for _, t in ipairs(self.trails) do
		t.Enabled = false -- what is drawn stays and fades where it is
	end
	for _, e in ipairs(self.emitters) do
		e.Enabled = false
	end
	for _, bolt in ipairs(self.bolts) do
		for _, b in ipairs(bolt.beams) do
			b.Enabled = false
		end
	end
end

local function countShots(): number
	local n = 0
	for _, h in ipairs(live) do
		if not h.released then
			n += 1
		end
	end
	return n
end

function TrailController.attachProjectile(itemId: string, shooterUserId: number?, isLocal: boolean, origin: Vector3, forcedId: string?)
	local slot = if itemId == "arrow" then "arrow" else "throw"
	local owner = if isLocal then player else (if shooterUserId then Players:GetPlayerByUserId(shooterUserId) else nil)
	local id = trailFor(owner, slot, forcedId)
	if not id then
		return nil
	end
	local camera = workspace.CurrentCamera
	if owner ~= player and camera and (origin - camera.CFrame.Position).Magnitude > Trails.DRAW_RANGE + 40 then
		return nil -- far away: not drawn (Trails.DRAW_RANGE, with room for the shot to come closer)
	end
	if owner ~= player and countShots() >= TIER_CAP[tier()].shots then
		return nil
	end
	local def = Trails.get(id)
	local carrier = Instance.new("Part")
	carrier.Name = "Trail_" .. id
	carrier.Size = Vector3.new(0.1, 0.1, 0.1)
	carrier.Transparency = 1
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CastShadow = false
	carrier.CFrame = CFrame.new(origin)
	local handle = setmetatable({
		id = id, carrier = carrier, origin = origin, trails = {}, emitters = {}, bolts = {}, on = false, released = false,
		fadeAt = 0, keep = 0.3,
	}, Handle)
	local center = Instance.new("Attachment")
	center.Parent = carrier
	for _, layer in ipairs(def.look) do
		if layer.type == "trail" then
			local w = (layer.width or 0.2) * 0.5 * SHOT_WIDTH
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(-w, 0, 0)
			a0.Parent = carrier
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(w, 0, 0)
			a1.Parent = carrier
			table.insert(handle.trails, newTrail(layer, a0, a1, carrier))
			handle.keep = math.max(handle.keep, (layer.life or 0.2) + 0.1)
		elseif layer.type == "particles" then
			table.insert(handle.emitters, newEmitter(layer, center, 1, SHOT_PARTICLE))
			handle.keep = math.max(handle.keep, (layer.life and (layer.life[2] or layer.life[1]) or 0.5) + 0.1)
		elseif layer.type == "bolt" and tier() ~= "Low" then
			table.insert(handle.bolts, newBolt(layer, carrier))
		end
	end
	carrier.Parent = getFolder()
	table.insert(live, handle)
	return handle
end

--------------------------------------------------------------------------------------------------------------------
-- Swings
--------------------------------------------------------------------------------------------------------------------

-- A ribbon rig on a part (built once per part and trail; rebuilt when the trail changes)
-- fp: your own first-person viewmodel. Its blade is a few studs from the eye, so a full-width camera-facing ribbon
-- would fill the screen: there the ribbon hugs the tip (FP_SPAN of the recipe's span), lies in the plane of the cut
-- (FaceCamera off), is fainter and shorter-lived, and its particles are smaller.
local function swingRig(part: BasePart, baseLocal: Vector3, tipLocal: Vector3, id: string, fp: boolean?)
	local rig = swingRigs[part]
	if rig and rig.id == id and rig.base == baseLocal and rig.tip == tipLocal and rig.fp == (fp == true)
		and rig.folder.Parent then
		return rig
	end
	if rig and rig.folder.Parent then
		rig.folder:Destroy()
	end
	local def = Trails.get(id)
	local folder = Instance.new("Folder")
	folder.Name = "SwingTrail"
	local tipAt = Instance.new("Attachment")
	tipAt.Name = "TrailTip"
	tipAt.Position = tipLocal
	tipAt.Parent = part
	rig = { id = id, base = baseLocal, tip = tipLocal, fp = fp == true, folder = folder, trails = {}, emitters = {},
		token = 0, attachments = { tipAt } } -- (the attachments go with the rig)
	for _, layer in ipairs(def.look) do
		if layer.type == "trail" then
			local span = math.clamp(layer.swingSpan or 0.5, 0.05, 1) * (if fp then FP_SPAN else 1)
			local a0 = Instance.new("Attachment")
			a0.Name = "TrailBase"
			a0.Position = tipLocal + (baseLocal - tipLocal) * span
			a0.Parent = part
			table.insert(rig.attachments, a0)
			local trail = newTrail(layer, a0, tipAt, folder)
			if fp then
				trail.FaceCamera = false
				trail.Lifetime *= 0.7
				local keys = {}
				for _, k in ipairs(trail.Transparency.Keypoints) do
					table.insert(keys, NumberSequenceKeypoint.new(k.Time, k.Value + (1 - k.Value) * FP_FADE))
				end
				trail.Transparency = NumberSequence.new(keys)
			end
			table.insert(rig.trails, trail)
		elseif layer.type == "particles" and #rig.emitters < 2 then
			table.insert(rig.emitters, newEmitter(layer, tipAt, SWING_RATE_MULT, if fp then 0.45 else 1))
		end
		-- (bolts are for shots only)
	end
	folder.Parent = part
	swingRigs[part] = rig
	folder.Destroying:Connect(function()
		for _, a in ipairs(rig.attachments) do
			a:Destroy()
		end
	end)
	return rig
end

local function setSwing(rig, on: boolean)
	for _, t in ipairs(rig.trails) do
		if on then
			t:Clear() -- (no stroke joining this cut to the end of the last one)
		end
		t.Enabled = on
	end
	for _, e in ipairs(rig.emitters) do
		e.Enabled = on
	end
end

function TrailController.swingOn(part: BasePart, baseLocal: Vector3, tipLocal: Vector3, id: string, onAt: number, offAt: number,
	fp: boolean?)
	if not part or not part.Parent or not Trails.get(id) then
		return
	end
	local rig = swingRig(part, baseLocal, tipLocal, id, fp)
	rig.token += 1
	local token = rig.token
	swingsLive += 1
	task.delay(math.max(onAt, 0), function()
		if rig.token == token and rig.folder.Parent then
			setSwing(rig, true)
		end
	end)
	task.delay(math.max(offAt, onAt + 0.05), function()
		swingsLive = math.max(0, swingsLive - 1)
		if rig.token == token and rig.folder.Parent then
			setSwing(rig, false)
		end
	end)
end

-- Where the blade is on an item model: (part, base, tip) in that part's space
local function bladeOf(model: Instance): (BasePart?, Vector3?, Vector3?)
	local handle = if model:IsA("Model") then model.PrimaryPart else nil
	local tip: Attachment? = nil
	local grip: Attachment? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") then
			if d.Name == "Tip" and not tip then
				tip = d
			elseif d.Name == "Grip" and not grip then
				grip = d
			end
		end
	end
	if tip and tip.Parent and tip.Parent:IsA("BasePart") then
		local part = tip.Parent :: BasePart
		local base = if grip then part.CFrame:PointToObjectSpace(grip.WorldPosition) else Vector3.zero
		-- the ribbon covers the blade: from a third of the way up from the grip to the tip
		return part, base + (tip.Position - base) * 0.3, tip.Position
	end
	if handle then
		-- no Tip: the far end of the model along the item's forward (Handle LookVector, Shared.ItemModels)
		local _, size = (model :: Model):GetBoundingBox()
		local len = math.max(size.X, size.Y, size.Z) * 0.85
		return handle, Vector3.new(0, 0, -len * 0.35), Vector3.new(0, 0, -len)
	end
	return nil, nil, nil
end

local function handOf(container: Instance): BasePart?
	local hand = container:FindFirstChild("RightHand", true) or container:FindFirstChild("Right Arm", true)
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- A swing by `character` (nil + isLocal: your own first-person viewmodel). windup = seconds until the strike.
function TrailController.swing(itemId: string, character: Model?, isLocal: boolean, windup: number, forcedId: string?)
	local owner = if isLocal then player else (if character then Players:GetPlayerFromCharacter(character) else nil)
	local id = trailFor(owner, "swing", forcedId)
	if not id then
		return
	end
	local camera = workspace.CurrentCamera
	local container: Instance? = nil
	if isLocal then
		local vm = Controllers and Controllers.ViewmodelController
		local visible = vm and type(vm.isVisible) == "function" and vm.isVisible()
		if visible and camera then
			container = camera:FindFirstChild("Viewmodel")
		end
		if not container then
			container = player.Character
		end
	else
		container = character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not camera or ((root :: BasePart).Position - camera.CFrame.Position).Magnitude > Trails.DRAW_RANGE then
			return
		end
		if swingsLive >= TIER_CAP[tier()].swings then
			return
		end
	end
	if not container then
		return
	end
	local part, base, tip = nil, nil, nil
	if itemId ~= "fists" then
		local item = container:FindFirstChild("EquippedModel")
		if not item and container.Name == "Viewmodel" then
			-- the viewmodel's held item: the model under it that is not the arms
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Model") and child.Name ~= "AvatarArms" and child.Name ~= "ArmShade" and child.PrimaryPart then
					item = child
					break
				end
			end
		end
		if item then
			part, base, tip = bladeOf(item)
		end
	end
	if not part then
		local hand = handOf(container)
		if hand then
			part, base, tip = hand, Vector3.new(0, FIST_HALF, 0), Vector3.new(0, -FIST_HALF, 0)
		end
	end
	if not part or not base or not tip then
		return
	end
	local strike = math.max(windup or 0.1, 0)
	TrailController.swingOn(part, base, tip, id, strike - SWING_LEAD, strike + SWING_TAIL, container.Name == "Viewmodel")
end

--------------------------------------------------------------------------------------------------------------------
-- Frame update: bolts, and handles that have faded
--------------------------------------------------------------------------------------------------------------------

local function update()
	local t0 = os.clock()
	for i = #live, 1, -1 do
		local h = live[i]
		if h.released then
			if t0 - h.fadeAt > h.keep then
				h.carrier:Destroy()
				table.remove(live, i)
			end
		elseif h.on then
			for _, bolt in ipairs(h.bolts) do
				if t0 >= bolt.next then
					bolt.next = t0 + bolt.layer.every
					rollBolt(bolt)
				end
			end
		elseif h.carrier.Parent == nil then
			table.remove(live, i)
		end
	end
	lastUpdateMs = (os.clock() - t0) * 1000
end

function TrailController.stats()
	local instances = 0
	if fxFolder then
		instances = #fxFolder:GetDescendants()
	end
	return { shots = countShots(), fading = #live - countShots(), swings = swingsLive, instances = instances,
		updateMs = lastUpdateMs, tier = tier(), others = TrailController.othersMode() }
end

--------------------------------------------------------------------------------------------------------------------
-- The shop requests (the Loadout screen calls these)
--------------------------------------------------------------------------------------------------------------------

function TrailController.buy(id: string, slot: string?)
	if remote then
		remote:FireServer("buy", id, slot)
	end
end

function TrailController.equip(slot: string, id: string)
	if remote then
		remote:FireServer("equip", slot, id)
	end
end

-- A list of the ids you own (free ones included)
function TrailController.owned(): { [string]: boolean }
	local out = {}
	for _, def in ipairs(Trails.list) do
		if Trails.isFree(def.id) then
			out[def.id] = true
		end
	end
	local csv = player:GetAttribute(Trails.OWNED_ATTR)
	if type(csv) == "string" then
		for id in string.gmatch(csv, "[^,]+") do
			out[id] = true
		end
	end
	return out
end

--------------------------------------------------------------------------------------------------------------------

-- Emotes ------------------------------------------------------------------------------------------------------------------

local function quietLine(text: string)
	local notes = Controllers and Controllers.NotificationController
	if notes and type(notes.toast) == "function" then
		pcall(notes.toast, text, nil, 1.6)
	end
end

local lastEmoteAt = 0
local EMOTE_CAM = "TrailEmoteCamera"

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- your own emote seen from outside: a three-quarter view of you while it plays (first person shows nothing of it)
local function emoteCamera(character: Model)
	local cam = workspace.CurrentCamera
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not cam or not (root and root:IsA("BasePart")) or not humanoid then
		return
	end
	pcall(function()
		RunService:UnbindFromRenderStep(EMOTE_CAM)
	end)
	local savedType = cam.CameraType
	local fromCF = cam.CFrame
	local t0 = os.clock()
	local ending: number? = nil
	local endFrom: CFrame? = nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local function goal(): CFrame
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local dir = CFrame.Angles(0, math.rad(-28), 0) * (if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis)
		local from = root.Position + Vector3.yAxis * 1.2
		local dist = 9
		local hit = workspace:Spherecast(from, 0.6, dir * dist, params)
		if hit then
			dist = math.max(3, hit.Distance - 0.4)
		end
		return CFrame.lookAt(from + dir * dist + Vector3.yAxis * 0.6, root.Position + Vector3.yAxis * 0.1)
	end
	local function setLocal(container: Instance?, value: number)
		if container then
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = value
				end
			end
		end
	end
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(EMOTE_CAM, Enum.RenderPriority.Camera.Value + 3, function()
		local playing = EmoteFx.isPlaying(character) and character.Parent ~= nil and humanoid.Health > 0
			and not (ClientState and ClientState.launchShot)
		if not playing and not ending then
			ending = os.clock()
			endFrom = cam.CFrame
		end
		if ending then
			local k = smooth01((os.clock() - ending) / 0.3)
			local head = character:FindFirstChild("Head")
			local back = if head and head:IsA("BasePart") then CFrame.new(head.Position) * (fromCF - fromCF.Position) else fromCF
			cam.CFrame = (endFrom :: CFrame):Lerp(back, k)
			if k >= 1 or not character.Parent then
				RunService:UnbindFromRenderStep(EMOTE_CAM)
				setLocal(cam:FindFirstChild("Viewmodel"), 0)
				cam.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
				cam.CameraSubject = humanoid
			end
			return
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = fromCF:Lerp(goal(), smooth01((os.clock() - t0) / 0.35))
		setLocal(character, 0)
		setLocal(cam:FindFirstChild("Viewmodel"), 1)
	end)
end

function TrailController.playEmote(): boolean
	if ClientState and ClientState.launchShot then
		return false
	end
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	local id = player:GetAttribute(EmoteFx.EMOTE_ATTR)
	if type(id) ~= "string" or id == "" then
		quietLine("No emote equipped")
		return false
	end
	if os.clock() - lastEmoteAt < 2 then
		return false
	end
	local seconds = EmoteFx.playEmote(player.Character, id)
	if not seconds then
		return false
	end
	lastEmoteAt = os.clock()
	quietLine(EmoteFx.emoteName(id) or "Emote")
	pcall(emoteCamera, player.Character)
	if remote then
		remote:FireServer("emote")
	end
	return true
end

local function onEmoteRelay(userId: any, id: any)
	local other = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not other or other == player or not other.Character then
		return
	end
	local root = other.Character:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if root and cam and (root.Position - cam.CFrame.Position).Magnitude > 250 then
		return
	end
	EmoteFx.playEmote(other.Character, id)
end

local function onCombatAction(payload: any)
	if type(payload) ~= "table" or payload.action ~= "Swing" or payload.cancelled then
		return
	end
	local other = Players:GetPlayerByUserId(tonumber(payload.userId) or 0)
	if not other or other == player or not other.Character then
		return
	end
	local itemId = if type(payload.itemId) == "string" then payload.itemId else "fists"
	TrailController.swing(itemId, other.Character, false, tonumber(payload.lead) or 0.1)
end

function TrailController.Init(registry)
	Controllers = registry
	local ok, Signal = pcall(require, Shared:WaitForChild("Signal"))
	if ok then
		TrailController.lines = Signal.new()
	end
end

function TrailController.Start()
	local combat = Controllers and Controllers.CombatController
	if combat and combat.action then
		combat.action:Connect(function(name: string, data: any)
			if name == "Swing" and type(data) == "table" then
				local ok, err = pcall(TrailController.swing, data.itemId or "fists", nil, true, data.windup or 0.1)
				if not ok then
					warn("[TrailController] " .. tostring(err))
				end
			end
		end)
	end
	local okRemote, combatAction = pcall(Net.event, "CombatAction")
	if okRemote and combatAction then
		combatAction.OnClientEvent:Connect(function(payload)
			local ok, err = pcall(onCombatAction, payload)
			if not ok then
				warn("[TrailController] " .. tostring(err))
			end
		end)
	end
	RunService.Heartbeat:Connect(update)
	Input.bind("Emote", function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			local ok, err = pcall(TrailController.playEmote)
			if not ok then
				warn("[TrailController] " .. tostring(err))
			end
		end
		return Enum.ContextActionResult.Pass
	end, { keys = { Enum.KeyCode.J }, priority = 1000 })
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local r = folder:WaitForChild("Trails", 30)
	if r and r:IsA("RemoteEvent") then
		remote = r
		r.OnClientEvent:Connect(function(kind, value, extra)
			if kind == "emote" then
				local ok, err = pcall(onEmoteRelay, value, extra)
				if not ok then
					warn("[TrailController] " .. tostring(err))
				end
				return
			end
			if TrailController.lines then
				TrailController.lines:Fire(kind, value)
			end
		end)
	end
end

return TrailController
