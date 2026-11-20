--[[
	CreatureLooks - what the squirrel, the campfire and their items look like. Server and clients.

	Until the Blender models are uploaded, everything here is built from Parts with Roblox's own materials and particle
	textures. To swap a mesh in, change ONE table, CreatureLooks.Mesh below: give the entry the name of a Model in
	ReplicatedStorage.Assets.<folder> and it is cloned instead of the part-built stand-in. Nothing else changes.

	  Mesh contract (all optional beyond the Root):
	    squirrel   Model, PrimaryPart "Root" (its origin at the feet, -Z = nose, +Y = up, real size about 1.3 studs).
	               Poses: Models (or single parts) named "Pose_Sit", "Pose_Run", "Pose_Climb", "Pose_Still" (and
	               optionally "Pose_Stand"), every part welded to Root; one pose is shown at a time (a missing one falls
	               back to Stand, then Run, then Sit). Each pose sits in the SAME frame: nose -Z, back +Y, feet at the
	               origin; the code itself turns the model nose-up onto a trunk, so the Blender "SquirrelClimb" (built
	               standing up) is turned 90 degrees nose-forward (-Z) and belly-down before it goes in as Pose_Climb.
	               "Pose_Still" is the defeated one lying on its side. A part named "Tail" joined to its parent by a
	               Weld named "TailJoint" is flicked (optional).
	    campfire   Model, PrimaryPart "Root" at the ground centre. Parts named "Ember*" glow only while lit. The flame,
	               smoke, light and spit are added by this module either way.
	    item_*     an ItemModels template (PrimaryPart "Handle" with a "Grip" attachment; see Shared.ItemModels).

	API
	  CreatureLooks.newSquirrel() -> rig          { model, root, parts, body?, head?, tail?, poses? }; root is anchored
	  CreatureLooks.poseSquirrel(rig, pose, t, lift?)   pose: "Stand" | "Nibble" | "Sit" | "Alert" | "Hop" | "Run" |
	                                              "Climb" | "Perch" | "Limp"; t = seconds (for the small motions)
	  CreatureLooks.fade(rig, alpha)              0 = solid, 1 = gone (LocalTransparencyModifier: this client only)
	  CreatureLooks.newCampfire() -> fire         { model, root, flame, sparks, smoke, light, embers, food, foodParts,
	                                              label, prompts = Attachment }
	  CreatureLooks.setCampfire(fire, state, smokeRate)   state: "Unlit" | "Lit" | "Out"
	  CreatureLooks.setSpit(fire, itemId?, cooked)        what hangs over the fire (nil = nothing)
	  CreatureLooks.itemTemplate(itemId) -> Model?        "squirrel" | "cooked_squirrel" | "firewood"
	  CreatureLooks.installItemTemplates()        server, at start: puts the three templates into
	                                              ReplicatedStorage.Assets.Items when it holds none by that name, so
	                                              ItemModels finds them like any Blender item
	The looks: small, matte and blocky, the brief's golden fur (196, 160, 82), a bushy tail held in an S over the back,
	the sitting-up silhouette clear. Nothing graphic anywhere: a hunted squirrel is the same little shape lying still.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CreatureLooks = {}

-- THE ONE TABLE. false = the part-built stand-in. { folder = "Creatures", name = "Squirrel" } = that Model under
-- ReplicatedStorage.Assets.
CreatureLooks.Mesh = {
	-- the Blender models (LS_Creatures_v1, 119629886091854), built by WorldGen.BlenderTemplates.buildCreatures()
	squirrel = { folder = "Creatures", name = "Squirrel" },
	campfire = { folder = "Creatures", name = "CookFire" },
	item_squirrel = false,
	item_cooked_squirrel = false,
	item_firewood = false,
}

local rad = math.rad
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local FUR = rgb(196, 160, 82)
local FUR_DARK = rgb(170, 132, 62)
local CREAM = rgb(234, 216, 172)
local TAIL = rgb(186, 142, 66)
local TAIL_TIP = rgb(226, 200, 138)
local DARK = rgb(34, 28, 24)
local ROAST = rgb(134, 86, 46)
local ROAST_DARK = rgb(98, 60, 32)
local WOOD = rgb(110, 80, 52)
local WOOD_DARK = rgb(84, 60, 40)
local STONE_A = rgb(112, 110, 104)
local STONE_B = rgb(134, 130, 122)
local ASH = rgb(52, 48, 44)
local TWINE = rgb(196, 176, 130)

local function meshSource(key: string): Model?
	local entry = (CreatureLooks.Mesh :: any)[key]
	if type(entry) ~= "table" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(tostring(entry.folder))
	local model = folder and folder:FindFirstChild(tostring(entry.name))
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or M.Plastic -- matte, plain: Roblox's own look (Fabric's weave read olive in shade)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rigid(a: BasePart, b: BasePart): Weld
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = a.CFrame:ToObjectSpace(b.CFrame)
	w.Parent = b
	return w
end

-- A weld that turns `b` about `pivot` (world, rest pose): set weld.C0 = joint.c0 * rotation.
local function hinge(a: BasePart, b: BasePart, pivot: CFrame, name: string)
	local w = Instance.new("Weld")
	w.Name = name
	w.Part0 = a
	w.Part1 = b
	local c0 = a.CFrame:ToObjectSpace(pivot)
	w.C0 = c0
	w.C1 = b.CFrame:ToObjectSpace(pivot)
	w.Parent = b
	return { weld = w, c0 = c0 }
end

---------------------------------------------------------------------------------------------------
-- The squirrel (model space: origin at the feet, -Z = nose, +Y = up)
---------------------------------------------------------------------------------------------------
type Joint = { weld: Weld, c0: CFrame }
export type Rig = {
	model: Model,
	root: BasePart,
	parts: { BasePart },
	body: Joint?,
	head: Joint?,
	tail: Joint?,
	poses: { [string]: { BasePart } }?,
	pose: string?,
}

-- Builds the body shapes into `model`, welded to `root`. limp = the item pose: legs out, tail straight, no joints.
local function buildSquirrelParts(model: Model, root: BasePart, limp: boolean, fur: Color3, furDark: Color3, cream: Color3, tailColor: Color3, tailTip: Color3)
	local body = newPart(model, "Body", V3(0.5, 0.46, 0.78), CF(0, 0.4, 0.04), fur)
	local belly = newPart(model, "Belly", V3(0.36, 0.1, 0.6), CF(0, 0.19, 0), cream)
	rigid(body, belly)
	-- haunches and legs
	for _, side in ipairs({ -1, 1 }) do
		local haunch = newPart(model, "Haunch", V3(0.16, 0.3, 0.36), CF(side * 0.26, 0.27, 0.24), fur)
		rigid(body, haunch)
		local front = newPart(model, "FrontLeg", V3(0.12, 0.24, 0.14),
			if limp then CF(side * 0.17, 0.14, -0.3) * ANG(rad(-50), 0, 0) else CF(side * 0.17, 0.12, -0.24), furDark)
		rigid(body, front)
		local foot = newPart(model, "HindFoot", V3(0.14, 0.08, 0.34),
			if limp then CF(side * 0.22, 0.1, 0.42) * ANG(rad(35), 0, 0) else CF(side * 0.22, 0.04, 0.12), furDark)
		rigid(if limp then body else root, foot)
	end
	-- head
	local head = newPart(model, "Head", V3(0.4, 0.36, 0.38), CF(0, 0.6, -0.5), fur)
	local snout = newPart(model, "Snout", V3(0.22, 0.18, 0.16), CF(0, 0.54, -0.75), cream)
	local nose = newPart(model, "Nose", V3(0.09, 0.07, 0.05), CF(0, 0.6, -0.84), DARK, M.SmoothPlastic)
	local eyes = newPart(model, "Eyes", V3(0.43, 0.09, 0.09), CF(0, 0.66, -0.58), DARK, M.SmoothPlastic)
	rigid(head, snout)
	rigid(head, nose)
	rigid(head, eyes)
	for _, side in ipairs({ -1, 1 }) do
		local ear = newPart(model, "Ear", V3(0.1, 0.17, 0.08), CF(side * 0.13, 0.85, -0.4) * ANG(0, 0, rad(-side * 8)), furDark)
		rigid(head, ear)
	end
	-- tail: three blocks in an S over the back (straight out behind when limp)
	local tailBase, tailMid, tailEnd
	if limp then
		tailBase = newPart(model, "Tail", V3(0.2, 0.2, 0.36), CF(0, 0.38, 0.6), tailColor)
		tailMid = newPart(model, "TailMid", V3(0.3, 0.3, 0.5), CF(0, 0.36, 1.0), tailColor)
		tailEnd = newPart(model, "TailTip", V3(0.26, 0.26, 0.34), CF(0, 0.35, 1.4), tailTip)
	else
		tailBase = newPart(model, "Tail", V3(0.2, 0.2, 0.36), CF(0, 0.52, 0.55) * ANG(rad(50), 0, 0), tailColor)
		tailMid = newPart(model, "TailMid", V3(0.3, 0.34, 0.52), CF(0, 0.86, 0.68) * ANG(rad(84), 0, 0), tailColor)
		tailEnd = newPart(model, "TailTip", V3(0.26, 0.3, 0.36), CF(0, 1.18, 0.56) * ANG(rad(128), 0, 0), tailTip)
	end
	rigid(tailBase, tailMid)
	rigid(tailBase, tailEnd)
	return body, head, tailBase
end

local function collectParts(model: Model): { BasePart }
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

function CreatureLooks.newSquirrel(): Rig
	local source = meshSource("squirrel")
	if source then
		local model = source:Clone()
		local root = model.PrimaryPart :: BasePart
		local poses: { [string]: { BasePart } } = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = d == root
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
			-- a pose is one part named Pose_<Name>, or a Model / Folder named so holding its parts
			local poseName = string.match(d.Name, "^Pose_(%a+)$")
			if poseName then
				local list = poses[poseName] or {}
				poses[poseName] = list
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
				for _, p in ipairs(d:GetDescendants()) do
					if p:IsA("BasePart") then
						table.insert(list, p)
					end
				end
			end
		end
		local rig: Rig = { model = model, root = root, parts = collectParts(model) }
		if next(poses) then
			rig.poses = poses
		end
		local tailPart = model:FindFirstChild("Tail", true)
		local tailWeld = tailPart and tailPart:FindFirstChild("TailJoint")
		if tailWeld and tailWeld:IsA("Weld") then
			rig.tail = { weld = tailWeld, c0 = tailWeld.C0 }
		end
		return rig
	end

	local model = Instance.new("Model")
	model.Name = "Squirrel"
	local root = newPart(model, "Root", V3(0.2, 0.2, 0.2), CF(0, 0, 0), FUR)
	root.Transparency = 1
	root.Anchored = true
	model.PrimaryPart = root
	local body, head, tailBase = buildSquirrelParts(model, root, false, FUR, FUR_DARK, CREAM, TAIL, TAIL_TIP)
	body.CastShadow = true -- one small shadow under it is enough to sit it on the ground
	local rig: Rig = {
		model = model,
		root = root,
		parts = collectParts(model),
		body = hinge(root, body, CF(0, 0.18, 0.32), "BodyJoint"), -- the hips
		head = hinge(body, head, CF(0, 0.52, -0.34), "HeadJoint"), -- the neck
		tail = hinge(body, tailBase, CF(0, 0.42, 0.44), "TailJoint"), -- the rump
	}
	return rig
end

-- pose -> { body pitch, head pitch, tail back } in degrees (positive body / head pitch lifts the nose; positive tail
-- lays it back). The small motions on top are in poseSquirrel.
local POSES: { [string]: { number } } = {
	Stand = { 0, 0, 0 },
	Nibble = { -9, -24, 4 },
	Sit = { 54, -44, -36 },
	Alert = { 60, -50, -30 },
	Hop = { 6, -4, 42 },
	Run = { -3, 4, 62 },
	Climb = { 0, 14, 58 },
	Perch = { 0, 22, 50 },
	Limp = { 0, -10, 70 },
}
local MESH_POSE: { [string]: string } = {
	Stand = "Stand", Nibble = "Stand", Sit = "Sit", Alert = "Sit", Hop = "Run", Run = "Run", Climb = "Climb",
	Perch = "Climb", Limp = "Still",
}

function CreatureLooks.poseSquirrel(rig: Rig, pose: string, t: number, lift: number?)
	local base = POSES[pose] or POSES.Stand
	local bodyPitch, headPitch, tailBack = base[1], base[2], base[3]
	local headYaw = 0
	if pose == "Stand" then
		headYaw = math.sin(t * 0.9) * 22
		tailBack += math.sin(t * 1.7) * 5
	elseif pose == "Nibble" then
		headPitch += math.sin(t * 17) * 3.5
		tailBack += math.sin(t * 1.3) * 4
	elseif pose == "Sit" then
		headYaw = math.sin(t * 0.8) * 38
		tailBack += math.sin(t * 1.5) * 5
	elseif pose == "Alert" then
		local flick = math.max(0, math.sin(t * 9))
		tailBack += flick * flick * flick * 20
	elseif pose == "Hop" or pose == "Run" then
		bodyPitch += (lift or 0) * 26
	elseif pose == "Perch" then
		headYaw = math.sin(t * 1.1) * 30
		local flick = math.max(0, math.sin(t * 5))
		tailBack += flick * flick * 12
	end
	local poses = rig.poses
	if poses then
		local want = MESH_POSE[pose] or "Stand"
		-- a pose the mesh lacks falls back along this chain (the Blender set has Sit, Run, Climb, Still)
		if not poses[want] then
			want = if poses.Stand then "Stand" elseif poses.Run then "Run" elseif poses.Sit then "Sit" else want
		end
		if rig.pose ~= want then
			rig.pose = want
			for name, list in pairs(poses) do
				for _, part in ipairs(list) do
					part.Transparency = if name == want then 0 else 1
				end
			end
		end
	end
	local body, head, tail = rig.body, rig.head, rig.tail
	if body then
		body.weld.C0 = body.c0 * ANG(rad(bodyPitch), 0, 0)
	end
	if head then
		head.weld.C0 = head.c0 * ANG(rad(headPitch), rad(headYaw), 0)
	end
	if tail then
		tail.weld.C0 = tail.c0 * ANG(rad(tailBack), 0, 0)
	end
end

function CreatureLooks.fade(rig: Rig, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	for _, part in ipairs(rig.parts) do
		part.LocalTransparencyModifier = a
	end
end

---------------------------------------------------------------------------------------------------
-- The campfire (model space: origin at the ground centre)
---------------------------------------------------------------------------------------------------
export type Fire = {
	model: Model,
	root: BasePart,
	flame: ParticleEmitter,
	sparks: ParticleEmitter,
	smoke: ParticleEmitter,
	light: PointLight,
	embers: { BasePart },
	foodParts: { BasePart },
	label: TextLabel,
	prompts: Attachment,
	state: string?,
}

local function anchoredPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = newPart(parent, name, size, cframe, color, material)
	p.Anchored = true
	return p
end

local function buildCampfireParts(model: Model): { BasePart }
	local embers = {}
	local ash = anchoredPart(model, "Ash", V3(0.12, 2.1, 2.1), CF(0, 0.06, 0) * ANG(0, 0, rad(90)), ASH, M.Sand)
	ash.Shape = Enum.PartType.Cylinder
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local big = i % 2 == 0
		local size = if big then V3(0.62, 0.42, 0.5) else V3(0.5, 0.34, 0.44)
		anchoredPart(model, "Stone", size,
			CF(math.cos(a) * 1.28, size.Y / 2 - 0.04, math.sin(a) * 1.28) * ANG(0, -a + rad(i * 23), rad((i % 3 - 1) * 7)),
			if big then STONE_A else STONE_B, M.Slate)
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + 0.3
		local lean = rad(52)
		local log = anchoredPart(model, "Log", V3(0.3, 0.3, 1.5),
			CF(math.cos(a) * 0.42, 0.52, math.sin(a) * 0.42) * CFrame.lookAt(Vector3.zero, V3(-math.cos(a), 0, -math.sin(a))) * ANG(lean, 0, 0),
			if i % 2 == 0 then WOOD else WOOD_DARK, M.Wood)
		log.CastShadow = true
	end
	local ember = anchoredPart(model, "Ember", V3(0.7, 0.16, 0.7), CF(0, 0.2, 0) * ANG(0, rad(20), 0), rgb(255, 128, 44), M.Neon)
	table.insert(embers, ember)
	return embers
end

function CreatureLooks.newCampfire(): Fire
	local model: Model
	local root: BasePart
	local embers: { BasePart } = {}
	local source = meshSource("campfire")
	if source then
		model = source:Clone()
		root = model.PrimaryPart :: BasePart
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
				if string.sub(d.Name, 1, 5) == "Ember" then
					table.insert(embers, d)
				end
			end
		end
	else
		model = Instance.new("Model")
		model.Name = "Campfire"
		root = anchoredPart(model, "Root", V3(0.3, 0.3, 0.3), CF(0, 0.3, 0), ASH, M.Sand)
		root.Transparency = 1
		model.PrimaryPart = root
		embers = buildCampfireParts(model)
	end
	model.Name = "Campfire"

	-- the spit: two forked sticks and a bar, with what cooks on it
	for _, side in ipairs({ -1, 1 }) do
		anchoredPart(model, "SpitPost", V3(0.13, 1.7, 0.13), CF(side * 1.62, 0.8, 0) * ANG(0, 0, rad(side * 4)), WOOD_DARK, M.Wood)
		anchoredPart(model, "SpitFork", V3(0.1, 0.32, 0.1), CF(side * 1.6, 1.72, 0.1) * ANG(rad(28), 0, 0), WOOD_DARK, M.Wood)
		anchoredPart(model, "SpitFork", V3(0.1, 0.32, 0.1), CF(side * 1.6, 1.72, -0.1) * ANG(rad(-28), 0, 0), WOOD_DARK, M.Wood)
	end
	anchoredPart(model, "SpitBar", V3(3.5, 0.09, 0.09), CF(0, 1.62, 0), WOOD, M.Wood)
	local foodParts = {
		anchoredPart(model, "Food", V3(0.7, 0.34, 0.36), CF(0, 1.62, 0), FUR, M.Fabric),
		anchoredPart(model, "Food", V3(0.3, 0.26, 0.28), CF(-0.48, 1.62, 0), FUR, M.Fabric),
		anchoredPart(model, "Food", V3(0.36, 0.2, 0.22), CF(0.5, 1.6, 0), TAIL, M.Fabric),
	}
	for _, p in ipairs(foodParts) do
		p.Transparency = 1
	end

	local fireAt = Instance.new("Attachment")
	fireAt.Name = "FireAt"
	fireAt.Position = V3(0, 0.25, 0)
	fireAt.Parent = root
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(255, 214, 120)),
		ColorSequenceKeypoint.new(0.5, rgb(255, 140, 50)),
		ColorSequenceKeypoint.new(1, rgb(190, 60, 24)),
	})
	flame.LightEmission = 0.85
	flame.LightInfluence = 0
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.4, 1.25),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.Lifetime = NumberRange.new(0.5, 0.9)
	flame.Speed = NumberRange.new(2.2, 3.4)
	flame.SpreadAngle = Vector2.new(9, 9)
	flame.Rotation = NumberRange.new(-20, 20)
	flame.RotSpeed = NumberRange.new(-40, 40)
	flame.Acceleration = V3(0, 1.5, 0)
	flame.Rate = 16
	flame.Enabled = false
	flame.Parent = fireAt
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = "rbxasset://textures/particles/SquareParticle.png" -- tiny ember flakes, not twinkle stars
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-120, 120)
	sparks.Color = ColorSequence.new(rgb(255, 190, 110))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(1, 0.02) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Speed = NumberRange.new(2.5, 5)
	sparks.SpreadAngle = Vector2.new(18, 18)
	sparks.Acceleration = V3(0, 2, 0)
	sparks.Rate = 2.5
	sparks.Enabled = false
	sparks.Parent = fireAt
	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = rgb(255, 170, 92)
	light.Range = 26
	light.Brightness = 0
	light.Shadows = true
	light.Enabled = false
	light.Parent = fireAt

	local smokeAt = Instance.new("Attachment")
	smokeAt.Name = "SmokeAt"
	smokeAt.Position = V3(0, 2.1, 0)
	smokeAt.Parent = root
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(120, 112, 104)),
		ColorSequenceKeypoint.new(0.25, rgb(168, 164, 158)),
		ColorSequenceKeypoint.new(1, rgb(206, 204, 200)),
	})
	smoke.LightEmission = 0.12
	smoke.LightInfluence = 0.75
	-- a column that reads from 300 studs by day (a real cost of a fire): wide, fairly dense low down, thinning up
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(0.3, 5),
		NumberSequenceKeypoint.new(1, 14),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.1, 0.38),
		NumberSequenceKeypoint.new(0.65, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(9, 12)
	smoke.Speed = NumberRange.new(5, 6.5)
	smoke.SpreadAngle = Vector2.new(5, 5)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-14, 14)
	smoke.Acceleration = V3(0.35, 0.1, 0.2) -- a light drift: the column leans a little
	smoke.Drag = 0.05
	smoke.Rate = 0
	smoke.Enabled = false
	smoke.Parent = smokeAt

	local prompts = Instance.new("Attachment")
	prompts.Name = "Prompts"
	prompts.Position = V3(0, 0.9, 0)
	prompts.Parent = root

	-- plain white text over the spit (the UI owners restyle it): "Cooking" / "Cooked squirrel"
	local board = Instance.new("BillboardGui")
	board.Name = "SpitLabel"
	board.Size = UDim2.fromOffset(220, 26)
	board.StudsOffsetWorldSpace = V3(0, 2.7, 0)
	board.AlwaysOnTop = false
	board.MaxDistance = 22
	board.LightInfluence = 0
	board.Enabled = false
	board.Parent = root
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Text = ""
	label.Parent = board

	return {
		model = model,
		root = root,
		flame = flame,
		sparks = sparks,
		smoke = smoke,
		light = light,
		embers = embers,
		foodParts = foodParts,
		label = label,
		prompts = prompts,
	}
end

function CreatureLooks.setCampfire(fire: Fire, state: string, smokeRate: number?)
	local lit = state == "Lit"
	fire.flame.Enabled = lit
	fire.sparks.Enabled = lit
	fire.light.Enabled = lit
	fire.smoke.Enabled = lit or state == "Out"
	local rate = smokeRate or 2.6
	fire.smoke.Rate = if lit then rate elseif state == "Out" then rate * 0.35 else 0
	for _, ember in ipairs(fire.embers) do
		ember.Transparency = if lit then 0 elseif state == "Out" then 0.6 else 1
		ember.Color = if lit then rgb(255, 128, 44) else rgb(150, 62, 30)
	end
	if fire.state ~= state then
		fire.state = state
		-- burnt out: the logs are charcoal
		if state == "Out" then
			for _, d in ipairs(fire.model:GetChildren()) do
				if d:IsA("BasePart") and d.Name == "Log" then
					d.Color = rgb(44, 40, 38)
				end
			end
		end
	end
end

function CreatureLooks.setSpit(fire: Fire, itemId: string?, cooked: boolean)
	local show = itemId ~= nil and itemId ~= ""
	for i, part in ipairs(fire.foodParts) do
		part.Transparency = if show then 0 else 1
		if cooked then
			part.Color = if i == 3 then ROAST_DARK else ROAST
		else
			part.Color = if i == 3 then TAIL else FUR
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Item templates (ItemModels format: Handle + Grip, parts welded to Handle, LookVector = the business end)
---------------------------------------------------------------------------------------------------
local function newTemplate(itemId: string, gripAt: CFrame): (Model, Part)
	local model = Instance.new("Model")
	model.Name = itemId
	local handle = newPart(model, "Handle", V3(0.05, 0.05, 0.05), gripAt, DARK, M.Plastic)
	handle.Transparency = 1
	model.PrimaryPart = handle
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Parent = handle
	return model, handle
end

local function finishTemplate(model: Model, handle: Part)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d ~= handle then
			for _, w in ipairs(d:GetChildren()) do
				if w:IsA("Weld") then
					w:Destroy()
				end
			end
		end
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d ~= handle then
			rigid(handle, d)
		end
	end
	model:PivotTo(CFrame.identity)
end

function CreatureLooks.itemTemplate(itemId: string): Model?
	local source = meshSource("item_" .. itemId)
	if source then
		local copy = source:Clone()
		copy.Name = itemId
		return copy
	end
	if itemId == "squirrel" then
		-- the same little shape lying still, held by the tail: +X is the flank that faces up on the ground
		local model, handle = newTemplate(itemId, CF(0, 0.36, 1.3))
		buildSquirrelParts(model, handle, true, FUR, FUR_DARK, CREAM, TAIL, TAIL_TIP)
		finishTemplate(model, handle)
		return model
	elseif itemId == "cooked_squirrel" then
		-- a roast on a stick
		local model, handle = newTemplate(itemId, CF(0, 0, 0.62))
		newPart(model, "Stick", V3(0.08, 0.08, 1.7), CF(0, 0, -0.1), WOOD, M.Wood)
		newPart(model, "Roast", V3(0.36, 0.32, 0.66), CF(0, 0, -0.42), ROAST, M.Fabric)
		newPart(model, "Roast", V3(0.28, 0.26, 0.24), CF(0, 0.02, -0.84), ROAST, M.Fabric)
		newPart(model, "Char", V3(0.37, 0.08, 0.2), CF(0, 0.13, -0.3), ROAST_DARK, M.Fabric)
		newPart(model, "Char", V3(0.37, 0.08, 0.16), CF(0, 0.13, -0.58), ROAST_DARK, M.Fabric)
		for _, side in ipairs({ -1, 1 }) do
			newPart(model, "Leg", V3(0.12, 0.14, 0.26), CF(side * 0.2, -0.12, -0.24) * ANG(rad(-20), 0, 0), ROAST_DARK, M.Fabric)
			newPart(model, "Leg", V3(0.1, 0.12, 0.2), CF(side * 0.19, -0.12, -0.62) * ANG(rad(20), 0, 0), ROAST_DARK, M.Fabric)
		end
		finishTemplate(model, handle)
		return model
	elseif itemId == "firewood" then
		-- five sticks tied with twine, carried like a bundle
		local model, handle = newTemplate(itemId, CF(0, 0.2, 0))
		local spots = { { -0.16, -0.08, 1.4, 4 }, { 0, -0.1, 1.55, -3 }, { 0.16, -0.08, 1.35, 6 }, { -0.08, 0.06, 1.5, -5 }, { 0.08, 0.06, 1.3, 2 } }
		for i, s in ipairs(spots) do
			newPart(model, "Stick", V3(0.15, 0.15, s[3]), CF(s[1], s[2], (i % 2 - 0.5) * 0.12) * ANG(0, rad(s[4]), 0),
				if i % 2 == 0 then WOOD else WOOD_DARK, M.Wood)
		end
		for _, z in ipairs({ -0.36, 0.36 }) do
			newPart(model, "Twine", V3(0.52, 0.36, 0.07), CF(0, -0.02, z), TWINE, M.Fabric)
		end
		finishTemplate(model, handle)
		return model
	end
	return nil
end

function CreatureLooks.installItemTemplates()
	if not RunService:IsServer() then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end
	local items = assets:FindFirstChild("Items")
	if not items then
		items = Instance.new("Folder")
		items.Name = "Items"
		items.Parent = assets
	end
	for _, itemId in ipairs({ "squirrel", "cooked_squirrel", "firewood" }) do
		if not items:FindFirstChild(itemId) then
			local model = CreatureLooks.itemTemplate(itemId)
			if model then
				model:SetAttribute("StandIn", true) -- built from Parts at run time; a Blender template of the same name wins
				model.Parent = items
			end
		end
	end
end

return CreatureLooks
