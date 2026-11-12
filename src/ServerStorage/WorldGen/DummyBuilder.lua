--[[
	DummyBuilder - builds the R15 training dummy used in Studio practice rounds (see CombatService).
	  DummyBuilder.create() -> Model   a fresh, unparented dummy (also used at runtime as a fallback)
	  DummyBuilder.build() -> Model    (re)creates ServerStorage.Dev.TrainingDummy at edit time
	Look: a stitched burlap mannequin with rope bindings and a painted target on the chest, held up by a wooden post
	on a plank platform. The post and platform are the child Model "Stand", which CombatService detaches at spawn so
	the stand stays put when the dummy is knocked apart and respawns.
	Rig: standard R15 part names, rig attachments and Motor6Ds; the HumanoidRootPart is anchored and can't be hit.
	Pivot: the centre of the platform top (where the feet stand), facing -Z.
	Placeholder parts; swap the internals for a Blender mesh later and keep the names.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local DummyBuilder = {}

local BURLAP = Color3.fromRGB(191, 164, 118)
local BURLAP_DARK = Color3.fromRGB(166, 139, 98)
local ROPE = Color3.fromRGB(112, 86, 58)
local WOOD = Color3.fromRGB(112, 80, 52)
local WOOD_DARK = Color3.fromRGB(80, 57, 38)
local TARGET_RED = Color3.fromRGB(186, 70, 48)
local TARGET_LIGHT = Color3.fromRGB(226, 214, 190)
local STITCH = Color3.fromRGB(54, 41, 30)

local ARM_DROP = math.rad(65) -- arm angle from straight down: an A-pose, like a scarecrow
local MAX_HEALTH = 200

local function make(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- Decorative detail welded to a body part. Not hittable itself (hits land on the body part underneath).
local function detail(body: BasePart, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = make(body.Parent :: Instance, name, shape, size, cframe, color, material)
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function joint(name: string, attachmentName: string, part0: BasePart, part1: BasePart, position: Vector3)
	local world = CFrame.new(position)
	local a0 = Instance.new("Attachment")
	a0.Name = attachmentName
	a0.CFrame = part0.CFrame:ToObjectSpace(world)
	a0.Parent = part0
	local a1 = Instance.new("Attachment")
	a1.Name = attachmentName
	a1.CFrame = part1.CFrame:ToObjectSpace(world)
	a1.Parent = part1
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = a0.CFrame
	motor.C1 = a1.CFrame
	motor.Parent = part1
end

local function buildHealthBar(head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(3.2, 0, 0.62, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.56, 0)
	label.Text = "TRAINING DUMMY"
	label.TextScaled = true
	label.FontFace = Theme.Fonts.Heading
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeColor3 = Theme.Colors.Panel
	label.TextStrokeTransparency = 0.55
	label.Parent = gui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, 0)
	track.Size = UDim2.new(1, 0, 0.26, 0)
	track.BackgroundColor3 = Theme.Colors.Panel
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = gui
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Theme.Colors.Health
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
end

local function buildStand(model: Model)
	local stand = Instance.new("Model")
	stand.Name = "Stand"
	stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local function standPart(name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material)
		local p = make(stand, name, shape, size, cframe, color, material)
		p.Anchored = true
		p.CanCollide = true
		return p
	end
	local platform = standPart("Platform", Enum.PartType.Cylinder, Vector3.new(0.36, 4.3, 4.3),
		CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(90)), WOOD, Enum.Material.WoodPlanks)
	standPart("Rim", Enum.PartType.Cylinder, Vector3.new(0.22, 4.55, 4.55),
		CFrame.new(0, -0.26, 0) * CFrame.Angles(0, 0, math.rad(90)), WOOD_DARK, Enum.Material.Wood)
	standPart("Post", Enum.PartType.Block, Vector3.new(0.46, 4.75, 0.46), CFrame.new(0, 2.375, 0.8), WOOD_DARK, Enum.Material.Wood)
	standPart("PostFoot", Enum.PartType.Block, Vector3.new(1.05, 0.34, 1.05), CFrame.new(0, 0.17, 0.8), WOOD, Enum.Material.Wood)
	standPart("Crossbar", Enum.PartType.Block, Vector3.new(2.7, 0.34, 0.34), CFrame.new(0, 4.42, 0.84), WOOD_DARK, Enum.Material.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		local brace = standPart("Brace", Enum.PartType.Block, Vector3.new(0.22, 1.25, 0.22),
			CFrame.new(0.42 * sx, 0.62, 0.8) * CFrame.Angles(0, 0, math.rad(-32 * sx)), WOOD, Enum.Material.Wood)
		brace.CastShadow = false
	end
	platform.Name = "Platform"
	stand.PrimaryPart = platform
	stand.Parent = model
	return stand
end

function DummyBuilder.create(): Model
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local body: { [string]: Part } = {}
	local function bodyPart(name: string, size: Vector3, cframe: CFrame, color: Color3?): Part
		local p = make(model, name, Enum.PartType.Block, size, cframe, color or BURLAP, Enum.Material.Fabric)
		body[name] = p
		return p
	end

	local root = make(model, "HumanoidRootPart", Enum.PartType.Block, Vector3.new(2, 2, 1), CFrame.new(0, 3.24, 0),
		BURLAP, Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.Anchored = true
	root.CanQuery = false
	root.CastShadow = false

	local sides = { { name = "Left", sign = -1 }, { name = "Right", sign = 1 } }
	for _, side in ipairs(sides) do
		local x = 0.48 * side.sign
		bodyPart(side.name .. "UpperLeg", Vector3.new(0.78, 1.22, 0.78), CFrame.new(x, 2.13, 0), BURLAP_DARK)
		bodyPart(side.name .. "LowerLeg", Vector3.new(0.66, 1.2, 0.66), CFrame.new(x, 0.92, 0), BURLAP_DARK)
		bodyPart(side.name .. "Foot", Vector3.new(0.72, 0.32, 1.0), CFrame.new(x, 0.16, -0.08), BURLAP_DARK)
	end
	local lowerTorso = bodyPart("LowerTorso", Vector3.new(1.75, 0.5, 0.95), CFrame.new(0, 2.99, 0))
	local upperTorso = bodyPart("UpperTorso", Vector3.new(1.95, 1.55, 1.05), CFrame.new(0, 4.015, 0))
	local head = bodyPart("Head", Vector3.new(1.15, 1.2, 1.15), CFrame.new(0, 5.44, 0))
	lowerTorso.CanCollide = true
	upperTorso.CanCollide = true
	head.CanCollide = true

	local armJoints = {}
	for _, side in ipairs(sides) do
		local rotation = CFrame.Angles(0, 0, ARM_DROP * side.sign)
		local dir = rotation:VectorToWorldSpace(Vector3.new(0, -1, 0))
		local shoulder = Vector3.new(1.0 * side.sign, 4.5, 0)
		local elbow = shoulder + dir * 1.16
		local wrist = elbow + dir * 1.04
		bodyPart(side.name .. "UpperArm", Vector3.new(0.62, 1.12, 0.62), CFrame.new(shoulder + dir * 0.6) * rotation)
		bodyPart(side.name .. "LowerArm", Vector3.new(0.56, 1.02, 0.56), CFrame.new(elbow + dir * 0.51) * rotation)
		bodyPart(side.name .. "Hand", Vector3.new(0.6, 0.38, 0.6), CFrame.new(wrist + dir * 0.19) * rotation, BURLAP_DARK)
		armJoints[side.name] = { shoulder = shoulder, elbow = elbow, wrist = wrist }
	end

	-- Rig (R15 names)
	joint("Root", "RootRigAttachment", root, lowerTorso, Vector3.new(0, 2.99, 0))
	joint("Waist", "WaistRigAttachment", lowerTorso, upperTorso, Vector3.new(0, 3.24, 0))
	joint("Neck", "NeckRigAttachment", upperTorso, head, Vector3.new(0, 4.79, 0))
	for _, side in ipairs(sides) do
		local n = side.name
		local x = 0.48 * side.sign
		local arm = armJoints[n]
		joint(n .. "Shoulder", n .. "ShoulderRigAttachment", upperTorso, body[n .. "UpperArm"], arm.shoulder)
		joint(n .. "Elbow", n .. "ElbowRigAttachment", body[n .. "UpperArm"], body[n .. "LowerArm"], arm.elbow)
		joint(n .. "Wrist", n .. "WristRigAttachment", body[n .. "LowerArm"], body[n .. "Hand"], arm.wrist)
		joint(n .. "Hip", n .. "HipRigAttachment", lowerTorso, body[n .. "UpperLeg"], Vector3.new(x, 2.74, 0))
		joint(n .. "Knee", n .. "KneeRigAttachment", body[n .. "UpperLeg"], body[n .. "LowerLeg"], Vector3.new(x, 1.52, 0))
		joint(n .. "Ankle", n .. "AnkleRigAttachment", body[n .. "LowerLeg"], body[n .. "Foot"], Vector3.new(x, 0.32, 0))
	end

	-- Rope bindings, stitched face and the painted target
	detail(lowerTorso, "Belt", Enum.PartType.Block, Vector3.new(1.85, 0.2, 1.05), CFrame.new(0, 3.16, 0), ROPE, Enum.Material.Fabric)
	detail(head, "NeckTie", Enum.PartType.Cylinder, Vector3.new(0.18, 1.0, 1.0),
		CFrame.new(0, 4.92, 0) * CFrame.Angles(0, 0, math.rad(90)), ROPE, Enum.Material.Fabric)
	detail(head, "Topknot", Enum.PartType.Ball, Vector3.new(0.42, 0.42, 0.42), CFrame.new(0, 6.08, 0.05), BURLAP_DARK, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		detail(head, "Eye", Enum.PartType.Ball, Vector3.new(0.17, 0.17, 0.17), CFrame.new(0.24 * sx, 5.56, -0.56), STITCH, Enum.Material.Fabric)
	end
	detail(head, "Mouth", Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.05), CFrame.new(0, 5.2, -0.58), STITCH, Enum.Material.Fabric)
	local facing = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (X) pointing out of the chest (-Z)
	detail(upperTorso, "TargetOuter", Enum.PartType.Cylinder, Vector3.new(0.04, 1.12, 1.12), CFrame.new(0, 4.06, -0.545) * facing, TARGET_RED, Enum.Material.Fabric)
	detail(upperTorso, "TargetRing", Enum.PartType.Cylinder, Vector3.new(0.04, 0.76, 0.76), CFrame.new(0, 4.06, -0.56) * facing, TARGET_LIGHT, Enum.Material.Fabric)
	detail(upperTorso, "TargetCentre", Enum.PartType.Cylinder, Vector3.new(0.04, 0.36, 0.36), CFrame.new(0, 4.06, -0.575) * facing, TARGET_RED, Enum.Material.Fabric)
	for _, side in ipairs(sides) do
		local lowerArm = body[side.name .. "LowerArm"]
		detail(lowerArm, "Cuff", Enum.PartType.Block, Vector3.new(0.64, 0.14, 0.64), lowerArm.CFrame * CFrame.new(0, -0.4, 0), ROPE, Enum.Material.Fabric)
		local lowerLeg = body[side.name .. "LowerLeg"]
		detail(lowerLeg, "Cuff", Enum.PartType.Block, Vector3.new(0.74, 0.14, 0.74), lowerLeg.CFrame * CFrame.new(0, -0.44, 0), ROPE, Enum.Material.Fabric)
		local upperArm = body[side.name .. "UpperArm"]
		detail(upperArm, "Wrap", Enum.PartType.Block, Vector3.new(0.68, 0.12, 0.68), upperArm.CFrame * CFrame.new(0, 0.3, 0), ROPE, Enum.Material.Fabric)
	end

	buildHealthBar(head)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.HipHeight = 2.24
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = true
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH
	humanoid.Parent = model

	buildStand(model)

	model.PrimaryPart = root
	root.PivotOffset = root.CFrame:ToObjectSpace(CFrame.new(0, 0, 0)) -- model pivot = the platform top
	return model
end

function DummyBuilder.build(): Model
	local dev = ServerStorage:FindFirstChild("Dev")
	if not dev then
		dev = Instance.new("Folder")
		dev.Name = "Dev"
		dev.Parent = ServerStorage
	end
	local old = dev:FindFirstChild("TrainingDummy")
	if old then
		old:Destroy()
	end
	local model = DummyBuilder.create()
	model.Parent = dev
	return model
end

return DummyBuilder
