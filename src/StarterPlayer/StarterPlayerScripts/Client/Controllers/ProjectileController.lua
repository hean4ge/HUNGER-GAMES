--[[
	ProjectileController - draws projectiles and their impacts. Client only.

	Server -> client
	  ProjectileFired  { id, shooter (UserId), itemId, origin, velocity, gravity, shotId, t }
	  ProjectileImpact { id, position, normal, hitCharacter, part, material, recovered, itemId }
	Every shot flies on the same ballistic path as the server's (origin + v*t + g*t^2/2). Remote shots ease in
	the network delay over their first quarter second so they leave the shooter and still land on time.
	The local player's shots are predicted: CombatController calls predict() at release, the visual leaves the
	weapon and merges onto the true path within its first CONVERGE_DISTANCE studs (so you see your shot fly from the
	bow to where you aimed), and the server echo with the same shotId is matched to it instead of
	spawning a second arrow. Unconfirmed predictions fade after a couple of seconds.
	Landing (ProjectileService.WorldProjectiles; rules in Shared.WorldItems): every arrow, throwing knife and thrown spear
	stays in the world as the server's model (tag WorldProjectile). Our copy stops on the pose the server gives the same
	hit (WorldItems.depth / embedPivot), then takes the server's exact pivot from ProjectileImpact (relative to the body
	part or crate it is stuck in) and falls or sinks the way the server's does (fallTo / fallTime / sink). The server's
	model stays hidden here while our copy is still on its way; once both have landed our copy goes and the model shows,
	in the same frame and on the same pose: one item on screen, no pop. Items stuck in your own head, arms or chest are
	hidden from your first-person view (attributes Host / HostPart) until they come out. A shot the server left nothing
	for sticks for Config.Combat.ArrowStickTime (into other players for a few seconds), as before.
	ArrowWhiz plays when someone else's projectile passes close to the camera.

	API (for the other combat controllers)
	  ProjectileController.predict(shotId, itemId, origin, velocity, gravity, visualOrigin: Vector3?)
	  ProjectileController.impactEffect(position, normal, material: Enum.Material?, kind: "World" | "Water" | "Sparks"?)
	  ProjectileController.surfaceSound(material: Enum.Material?) -> string   Hit_Wood / Hit_Stone / Hit_Metal
	  ProjectileController.buildArrow(length: number?) -> Model   light arrow (tip at the pivot, pointing along -Z)
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldItems = require(Shared:WaitForChild("WorldItems"))

local player = Players.LocalPlayer
local CombatConfig = Config.Combat

local ProjectileController = {}

local ARROW_LENGTH = 2.3
local MAX_STUCK = 40
local WHIZ_RADIUS = 7
local PREDICT_LINK_TIMEOUT = 2.5 -- a predicted shot the server never confirms is removed after this long
local CONVERGE_DISTANCE = 12 -- predicted shots start at the weapon and merge onto the true path over this many studs
local LEAD_EASE_TIME = 0.25 -- remote shots catch up with the server over this long
local CHARACTER_STICK_TIME = 6
local SPIN_RATE = 19 -- radians per second for tumbling thrown knives
local FAR_CULL = 1500 -- shots fired further than this from the camera aren't drawn
local WORLD_WAIT = 30 -- a landed copy waits this long for the server's model before it goes
-- items stuck in these parts of your own body are out of your first-person view (the camera sits in the head)
local OWN_BODY_HIDDEN: { [string]: boolean } = {
	Head = true, UpperTorso = true, Torso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true, ["Left Arm"] = true, ["Right Arm"] = true,
}

local SHAFT_COLOR = Color3.fromRGB(150, 116, 78)
local HEAD_COLOR = Color3.fromRGB(88, 90, 94)
local FLETCH_COLOR = Color3.fromRGB(226, 219, 204)

local SOUND_BY_MATERIAL: { [string]: string } = {
	Metal = "Hit_Metal", CorrodedMetal = "Hit_Metal", DiamondPlate = "Hit_Metal", Foil = "Hit_Metal",
	Wood = "Hit_Wood", WoodPlanks = "Hit_Wood", Fabric = "Hit_Wood", Grass = "Hit_Wood", LeafyGrass = "Hit_Wood",
	Ground = "Hit_Wood", Mud = "Hit_Wood", Sand = "Hit_Wood", Snow = "Hit_Wood", Cardboard = "Hit_Wood",
	Carpet = "Hit_Wood", Leather = "Hit_Wood", Rubber = "Hit_Wood", Plastic = "Hit_Wood", SmoothPlastic = "Hit_Wood",
}

local DUST_COLORS: { [string]: Color3 } = {
	Grass = Color3.fromRGB(112, 120, 82), LeafyGrass = Color3.fromRGB(104, 116, 74), Ground = Color3.fromRGB(122, 102, 78),
	Mud = Color3.fromRGB(92, 74, 54), Sand = Color3.fromRGB(198, 180, 142), Snow = Color3.fromRGB(236, 238, 242),
	Wood = Color3.fromRGB(146, 114, 78), WoodPlanks = Color3.fromRGB(152, 120, 82), Rock = Color3.fromRGB(132, 130, 124),
	Slate = Color3.fromRGB(112, 112, 110), Basalt = Color3.fromRGB(92, 90, 88), Concrete = Color3.fromRGB(162, 160, 154),
	Brick = Color3.fromRGB(152, 102, 82), Cobblestone = Color3.fromRGB(132, 128, 120), Fabric = Color3.fromRGB(180, 160, 120),
	Metal = Color3.fromRGB(160, 160, 160), CorrodedMetal = Color3.fromRGB(132, 102, 82),
}
local SPARK_MATERIALS: { [string]: boolean } = {
	Metal = true, CorrodedMetal = true, DiamondPlate = true, Rock = true, Slate = true, Basalt = true, Concrete = true,
	Cobblestone = true, Brick = true, Granite = true, Marble = true, Pebble = true,
}

type Shot = {
	id: number?,
	shotId: string?,
	isLocal: boolean,
	itemId: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	t0: number,
	lead: number,
	createdAt: number,
	lifetime: number,
	position: Vector3,
	direction: Vector3,
	model: Model?,
	offset: CFrame,
	spin: number,
	visualOffset: Vector3?,
	state: string, -- "Flying" | "Falling" | "Stuck" | "Gone"
	whizzed: boolean,
	impactPlayed: boolean,
	linked: boolean,
	shooterCharacter: Model?,
	pendingImpact: any?,
	pendingDeadline: number,
	stuckEntry: any?,
	trailOn: boolean,
	world: Model?, -- the server's model of this shot, once it is here
	hidingWorld: boolean, -- ...hidden here until our copy has landed
	worldId: number?,
	mayFall: boolean, -- landed in water or a blade on stone: wait for the server's fall before handing over
	fall: { from: CFrame, to: CFrame, t0: number, duration: number, sink: boolean }?,
}

type StuckEntry = { model: Model, expires: number, part: BasePart?, rel: CFrame?, shot: Shot? }

local camera = workspace.CurrentCamera
local fxFolder: Folder? = nil
local flying: { Shot } = {}
local byId: { [number]: Shot } = {}
local byShotId: { [string]: Shot } = {}
local stuck: { StuckEntry } = {}
local arrowTemplate: Model? = nil
local arrowOffset = CFrame.identity
local byProjectile: { [number]: Shot } = {} -- server projectile id -> our copy, until it hands over to the server's model
local worldByShot: { [number]: Model } = {} -- server projectile id -> its model in the world (while streamed in)
local hiddenWhy: { [Instance]: { [string]: boolean } } = {} -- world models hidden here, and why ("landing" / "body")

local characterParams = RaycastParams.new()
characterParams.FilterType = Enum.RaycastFilterType.Include
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true
worldParams.IgnoreWater = false

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function getFolder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientProjectiles"
	folder.Parent = workspace
	fxFolder = folder
	return folder
end

local function upFor(direction: Vector3): Vector3
	return if math.abs(direction.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
end

local function humanoidOf(part: Instance?): Humanoid?
	if not part then
		return nil
	end
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		parent = parent.Parent
	end
	if parent and parent:IsA("Model") then
		return parent:FindFirstChildOfClass("Humanoid")
	end
	return nil
end

local function isLocalCharacterPart(part: Instance?): boolean
	local character = player.Character
	return part ~= nil and character ~= nil and part:IsDescendantOf(character)
end

local function closestOnSegment(p: Vector3, a: Vector3, b: Vector3): Vector3
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return a
	end
	return a + ab * math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
end

local function positionAt(shot: Shot, tau: number): Vector3
	return shot.origin + shot.velocity * tau + Vector3.new(0, -0.5 * shot.gravity * tau * tau, 0)
end

local function velocityAt(shot: Shot, tau: number): Vector3
	return shot.velocity + Vector3.new(0, -shot.gravity * tau, 0)
end

local function shotTime(shot: Shot, now: number): number
	local elapsed = now - shot.t0
	if shot.lead > 0 then
		return elapsed + shot.lead * math.clamp(elapsed / LEAD_EASE_TIME, 0, 1)
	end
	return elapsed
end

function ProjectileController.surfaceSound(material: Enum.Material?): string
	return (material and SOUND_BY_MATERIAL[material.Name]) or "Hit_Stone"
end

--------------------------------------------------------------------------------------------------------------------
-- Models
--------------------------------------------------------------------------------------------------------------------

local function piece(model: Model, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

-- A light arrow: the tip sits on the pivot and the shaft runs back along +Z, so PivotTo(CFrame.lookAt(tip, tip + dir))
-- points it along dir.
function ProjectileController.buildArrow(length: number?): Model
	local len = length or ARROW_LENGTH
	local s = len / ARROW_LENGTH
	local model = Instance.new("Model")
	model.Name = "Arrow"
	local along = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (X) along Z
	local headLength = 0.3 * s
	piece(model, "Shaft", Enum.PartType.Cylinder, Vector3.new(len - headLength * 0.6, 0.075 * s, 0.075 * s),
		CFrame.new(0, 0, headLength * 0.6 + (len - headLength * 0.6) / 2) * along, SHAFT_COLOR, Enum.Material.Wood)
	piece(model, "HeadA", Enum.PartType.Block, Vector3.new(0.04 * s, 0.17 * s, headLength), CFrame.new(0, 0, headLength / 2), HEAD_COLOR, Enum.Material.Metal)
	piece(model, "HeadB", Enum.PartType.Block, Vector3.new(0.17 * s, 0.04 * s, headLength), CFrame.new(0, 0, headLength / 2), HEAD_COLOR, Enum.Material.Metal)
	for i = 0, 2 do
		local color = if i == 0 then Theme.Colors.Accent else FLETCH_COLOR
		piece(model, "Vane", Enum.PartType.Block, Vector3.new(0.02 * s, 0.12 * s, 0.42 * s),
			CFrame.new(0, 0, len - 0.34 * s) * CFrame.Angles(0, 0, i * math.pi * 2 / 3) * CFrame.new(0, 0.085 * s, 0), color, Enum.Material.Fabric)
	end
	piece(model, "Nock", Enum.PartType.Block, Vector3.new(0.09 * s, 0.09 * s, 0.07 * s), CFrame.new(0, 0, len - 0.035 * s), HEAD_COLOR, Enum.Material.SmoothPlastic)
	model.WorldPivot = CFrame.new()
	return model
end

local itemVisual: (itemId: string) -> (Model?, CFrame, number)

-- Flying arrows use the same ItemModels arrow as the bow and the ground pickup (cached), plus a faint trail.
local function arrowVisual(): (Model, CFrame)
	if not arrowTemplate then
		local template, offset = itemVisual("arrow")
		if not template then
			template, offset = ProjectileController.buildArrow(ARROW_LENGTH), CFrame.identity
		end
		local model = template :: Model
		local shaft = model.PrimaryPart or model:FindFirstChild("Shaft") or model:FindFirstChildWhichIsA("BasePart")
		local back = shaft and shaft.CFrame:PointToObjectSpace((model:GetPivot() * offset:Inverse() * CFrame.new(0, 0, 1.9)).Position) or Vector3.zero -- near the fletching
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA"
		a0.Position = back + Vector3.new(0.04, 0, 0)
		a0.Parent = shaft
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailB"
		a1.Position = back - Vector3.new(0.04, 0, 0)
		a1.Parent = shaft
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.Lifetime = 0.16
		trail.MinLength = 0.05
		trail.LightEmission = 0.25
		trail.Color = ColorSequence.new(Color3.fromRGB(240, 236, 226))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		trail.Enabled = false -- switched on once the arrow is at its starting point
		trail.Parent = shaft
		arrowTemplate = model
		arrowOffset = offset
	end
	return (arrowTemplate :: Model):Clone(), arrowOffset
end

-- Thrown weapons use the real item model. Returns the model, the offset that puts its anchor point (tip, or the
-- centre for tumbling knives) on the simulated position with its business end forward, and its spin rate.
itemVisual = function(itemId: string): (Model?, CFrame, number)
	local ok, model = pcall(ItemModels.build, itemId, "world")
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, CFrame.identity, 0
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("JointInstance") or inst:IsA("WeldConstraint") or inst:IsA("ProximityPrompt") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.CastShadow = false
		end
	end
	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local handle = model.PrimaryPart
	local grip = handle and handle:FindFirstChild("Grip")
	local gripPosition = if grip and grip:IsA("Attachment") then grip.WorldPosition else boxCFrame.Position
	local tip = model:FindFirstChild("Tip", true)
	local forward: Vector3
	if tip and tip:IsA("Attachment") and (tip.WorldPosition - gripPosition).Magnitude > 0.1 then
		forward = (tip.WorldPosition - gripPosition).Unit
	else
		-- the longest axis of the bounding box, pointing away from the grip
		local axis = boxCFrame.LookVector
		if boxSize.X >= boxSize.Y and boxSize.X >= boxSize.Z then
			axis = boxCFrame.RightVector
		elseif boxSize.Y >= boxSize.Z then
			axis = boxCFrame.UpVector
		end
		if (boxCFrame.Position - gripPosition):Dot(axis) < 0 then
			axis = -axis
		end
		forward = axis
	end
	local def = ItemDefs.get(itemId)
	local tumbles = def ~= nil and def.kind == "Throwable"
	local anchor = if tumbles or not (tip and tip:IsA("Attachment")) then boxCFrame.Position else (tip :: Attachment).WorldPosition
	local forwardLocal = pivot:VectorToObjectSpace(forward)
	local anchorLocal = pivot:PointToObjectSpace(anchor)
	local align = CFrame.lookAt(Vector3.zero, forwardLocal, upFor(forwardLocal))
	return model, align:Inverse() * CFrame.new(-anchorLocal), if tumbles then SPIN_RATE else 0
end

local function setTrails(model: Model?, enabled: boolean)
	if not model then
		return
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("Trail") then
			inst.Enabled = enabled
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Impact effects
--------------------------------------------------------------------------------------------------------------------

local fxAttachment: Attachment? = nil
local emitters: { [string]: ParticleEmitter } = {}

local function makeEmitter(name: string, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LockedToPart = false
	for key, value in pairs(props) do
		(emitter :: any)[key] = value
	end
	emitter.Parent = fxAttachment
	return emitter
end

local function ensureFx(): Attachment
	if fxAttachment and fxAttachment.Parent and fxAttachment.Parent.Parent then
		return fxAttachment
	end
	local anchor = Instance.new("Part")
	anchor.Name = "FxAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(0, -500, 0)
	anchor.Parent = getFolder()
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	fxAttachment = attachment
	table.clear(emitters)
	emitters.Dust = makeEmitter("Dust", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Lifetime = NumberRange.new(0.35, 0.75),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(35, 35),
		Drag = 6,
		Acceleration = Vector3.new(0, -5, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		LightInfluence = 1,
	})
	emitters.Chips = makeEmitter("Chips", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(7, 13),
		SpreadAngle = Vector2.new(45, 45),
		Drag = 2,
		Acceleration = Vector3.new(0, -40, 0),
		Size = NumberSequence.new(0.09),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) }),
		LightInfluence = 1,
	})
	emitters.Sparks = makeEmitter("Sparks", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(0.12, 0.28),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(50, 50),
		Drag = 3,
		Acceleration = Vector3.new(0, -30, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 150), Color3.fromRGB(255, 140, 60)),
		LightEmission = 1,
		LightInfluence = 0,
	})
	return attachment
end

-- A small burst at an impact point, oriented along the surface normal.
function ProjectileController.impactEffect(position: Vector3, normal: Vector3?, material: Enum.Material?, kind: string?)
	if typeof(position) ~= "Vector3" then
		return
	end
	local attachment = ensureFx()
	local n = if typeof(normal) == "Vector3" and normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	local side = n:Cross(if math.abs(n.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis).Unit
	attachment.WorldCFrame = CFrame.fromMatrix(position + n * 0.05, side, n)
	local materialName = if material then material.Name else ""
	if kind == "Water" or material == Enum.Material.Water then
		local dust = emitters.Dust
		dust.Color = ColorSequence.new(Color3.fromRGB(214, 228, 236))
		dust:Emit(10)
		return
	end
	local color = DUST_COLORS[materialName] or Color3.fromRGB(140, 130, 116)
	emitters.Dust.Color = ColorSequence.new(color)
	emitters.Dust:Emit(5)
	emitters.Chips.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.25))
	emitters.Chips:Emit(4)
	if kind == "Sparks" or (kind ~= "Soft" and SPARK_MATERIALS[materialName]) then
		emitters.Sparks:Emit(if kind == "Sparks" then 10 else 6)
	end
end

local function feedback(itemId: string, position: Vector3, normal: Vector3?, material: Enum.Material?, hitCharacter: boolean)
	if hitCharacter then
		Sfx.play("Hit_Flesh", { position = position })
	elseif material == Enum.Material.Water then
		Sfx.play("WaterSplash", { position = position, volume = 0.7 })
		ProjectileController.impactEffect(position, normal, material, "Water")
	else
		Sfx.play(if itemId == "arrow" then "ArrowImpact" else ProjectileController.surfaceSound(material), { position = position })
		ProjectileController.impactEffect(position, normal, material, if itemId == "arrow" then "Soft" else "World")
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Shots
--------------------------------------------------------------------------------------------------------------------

local function removeStuckEntry(entry: StuckEntry?)
	if not entry then
		return
	end
	local index = table.find(stuck, entry)
	if index then
		table.remove(stuck, index)
	end
end

-- Show or hide a world model on this client only, for a reason ("landing": our copy is still on its way; "body": it is
-- in your own head, arms or chest). It shows again once no reason is left.
local function setHidden(model: Model, reason: string, hidden: boolean)
	local why = hiddenWhy[model]
	if not why then
		if not hidden then
			return
		end
		why = {}
		hiddenWhy[model] = why
	end
	why[reason] = if hidden then true else nil
	local hide = next(why) ~= nil
	if not hide then
		hiddenWhy[model] = nil
	end
	local value = if hide then 1 else 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = value
		end
	end
end

local function destroyVisual(shot: Shot)
	shot.state = "Gone"
	shot.fall = nil
	if shot.model then
		shot.model:Destroy()
		shot.model = nil
	end
	removeStuckEntry(shot.stuckEntry)
	shot.stuckEntry = nil
	if shot.shotId and byShotId[shot.shotId] == shot then
		byShotId[shot.shotId] = nil
	end
	local model = shot.world
	shot.world = nil
	if model and shot.hidingWorld and model.Parent then
		setHidden(model, "landing", false) -- our copy went first: the server's shows
	end
	shot.hidingWorld = false
	if shot.id and byProjectile[shot.id] == shot then
		byProjectile[shot.id] = nil
	end
end

local function forget(shot: Shot)
	if shot.id and byId[shot.id] == shot then
		byId[shot.id] = nil
	end
	if shot.shotId and byShotId[shot.shotId] == shot then
		byShotId[shot.shotId] = nil
	end
	if shot.id and byProjectile[shot.id] == shot then
		byProjectile[shot.id] = nil
	end
end

-- Our copy has landed (and finished any fall) and the server's model is here: swap them in the same frame. Both sit on
-- the same pose, so nothing moves on screen.
local function handover(shot: Shot)
	local model = shot.world
	if not model or shot.state ~= "Stuck" or shot.fall ~= nil then
		return
	end
	shot.world = nil
	if model.Parent and shot.hidingWorld then
		setHidden(model, "landing", false)
	end
	shot.hidingWorld = false
	destroyVisual(shot)
	forget(shot)
end

local function render(shot: Shot, tau: number, position: Vector3)
	local model = shot.model
	if not model then
		return
	end
	local velocity = velocityAt(shot, tau)
	local direction = if velocity.Magnitude > 0.01 then velocity.Unit else shot.direction
	shot.direction = direction
	local display = position
	local facing = direction
	if shot.visualOffset then
		-- smoothstep over the distance flown; the visual points along the path it is actually drawn on
		local speed = math.max(shot.velocity.Magnitude, 1)
		local x = math.clamp(speed * tau / CONVERGE_DISTANCE, 0, 1)
		display = position + shot.visualOffset * (1 - x * x * (3 - 2 * x))
		if x < 1 then
			local apparent = velocity - shot.visualOffset * (6 * x * (1 - x) * speed / CONVERGE_DISTANCE)
			if apparent.Magnitude > 0.01 then
				facing = apparent.Unit
			end
		end
	end
	local look = CFrame.lookAt(display, display + facing, upFor(facing))
	if shot.spin ~= 0 then
		look *= CFrame.Angles(-tau * shot.spin, 0, 0)
	end
	model:PivotTo(look * shot.offset)
end

-- Leave our copy at `pivot`, following `part` when it moves (a body, a crate lid).
local function stickAt(shot: Shot, pivot: CFrame, part: BasePart?, duration: number, rel: CFrame?)
	local model = shot.model
	if not model then
		return
	end
	setTrails(model, false)
	shot.trailOn = false
	shot.fall = nil
	model:PivotTo(pivot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.CastShadow = true -- like the server's model it hands over to
		end
	end
	shot.state = "Stuck"
	removeStuckEntry(shot.stuckEntry)
	local entry: StuckEntry = { model = model, expires = os.clock() + duration, part = nil, rel = nil, shot = shot }
	if part and part.Parent and (rel ~= nil or not part.Anchored or humanoidOf(part) ~= nil) then
		entry.part = part
		entry.rel = rel or part.CFrame:ToObjectSpace(pivot)
	end
	table.insert(stuck, entry)
	shot.stuckEntry = entry
	while #stuck > MAX_STUCK do
		local oldest = table.remove(stuck, 1)
		if oldest then
			if oldest.shot then
				oldest.shot.stuckEntry = nil
				destroyVisual(oldest.shot)
			else
				oldest.model:Destroy()
			end
		end
	end
end

local function stickTime(): number
	return CombatConfig.ArrowStickTime or 20
end

-- Our copy falls (or sinks) the way the server's item does, then hands over.
local function startFall(shot: Shot, from: CFrame, to: any, duration: any, sink: any)
	if typeof(to) ~= "CFrame" or type(duration) ~= "number" or duration <= 0 then
		return
	end
	shot.fall = { from = from, to = to, t0 = os.clock(), duration = math.min(duration, 3), sink = sink == true }
	shot.state = "Falling"
	local entry = shot.stuckEntry
	if entry then
		entry.part = nil -- it falls in world space
		entry.rel = nil
	end
	local model = shot.world
	if model and not shot.hidingWorld then
		shot.hidingWorld = true
		setHidden(model, "landing", true)
	end
end

-- Where our copy stops at a hit: the pose the server gives the same hit (Shared.WorldItems).
local function hitPivot(shot: Shot, result: RaycastResult, hitCharacter: boolean): CFrame
	local velocity = velocityAt(shot, shotTime(shot, os.clock()))
	local dir = if velocity.Magnitude > 0.01 then velocity.Unit else shot.direction
	shot.direction = dir
	local depth = if result.Material == Enum.Material.Water
		then 0.25
		else WorldItems.depth(shot.itemId, result.Material, velocity.Magnitude, math.abs(dir:Dot(result.Normal)), hitCharacter)
	return WorldItems.embedPivot(shot.itemId, result.Position + dir * depth, dir)
end

-- Put our copy where the server says the item ended up.
local function settle(shot: Shot, info: any)
	if not shot.impactPlayed then
		shot.impactPlayed = true
		feedback(shot.itemId, info.position, info.normal, info.material, info.hitCharacter)
	end
	local part = info.part
	if not shot.model or (info.hitCharacter and isLocalCharacterPart(part)) then
		destroyVisual(shot) -- in your own body: the server's item is out of your view
		return
	end
	if info.worldId then
		-- the server's exact pose (relative to what it is stuck in), so the hand-over to its model is seamless
		shot.worldId = info.worldId
		local pivot = if part and info.rel then part.CFrame * info.rel else info.pivot
		if typeof(pivot) ~= "CFrame" then
			pivot = shot.model:GetPivot()
		end
		stickAt(shot, pivot, part, WORLD_WAIT, if info.fallTo then nil else info.rel)
		if not shot.world and shot.id then
			local model = worldByShot[shot.id]
			if model and model.Parent then
				shot.world = model
			end
		end
		if info.fallTo then
			startFall(shot, pivot, info.fallTo, info.fallTime, info.sink)
		end
		handover(shot)
		return
	end
	-- nothing was left in the world for this shot: stick for a while, then go (as before)
	local pivot = WorldItems.embedPivot(shot.itemId, info.position + shot.direction * 0.5, shot.direction)
	if info.hitCharacter then
		if shot.itemId == "arrow" and part then
			stickAt(shot, pivot, part, CHARACTER_STICK_TIME)
		else
			destroyVisual(shot)
		end
		return
	end
	stickAt(shot, pivot, part, stickTime())
end

local function localImpact(shot: Shot, result: RaycastResult, hitCharacter: boolean)
	shot.position = result.Position
	if not shot.impactPlayed then
		shot.impactPlayed = true
		feedback(shot.itemId, result.Position, result.Normal, result.Material, hitCharacter)
	end
	local part = result.Instance :: BasePart
	if hitCharacter and isLocalCharacterPart(part) then
		destroyVisual(shot) -- in your own body: the server's item is out of your view
	else
		-- the pose the server gives the same hit; it waits there for the server's model
		shot.mayFall = result.Material == Enum.Material.Water or WorldItems.glances(shot.itemId, result.Material)
		stickAt(shot, hitPivot(shot, result, hitCharacter), part, WORLD_WAIT)
	end
	if shot.state == "Flying" then
		shot.state = "Stuck"
	end
	if not shot.mayFall then
		handover(shot)
	end
end

-- The server's model of a spent projectile arrived (or streamed in).
local function onWorldAdded(model: Instance)
	if not model:IsA("Model") then
		return
	end
	if model:GetAttribute("Host") == player.UserId and OWN_BODY_HIDDEN[tostring(model:GetAttribute("HostPart"))] then
		setHidden(model, "body", true) -- in your own head, arms or chest: out of your first-person view
	end
	local key = model:GetAttribute("Shot")
	if type(key) ~= "number" or key <= 0 then
		return
	end
	worldByShot[key] = model
	local shot = byProjectile[key]
	if not shot or shot.state == "Gone" then
		return
	end
	shot.world = model
	if shot.state == "Stuck" and not shot.fall and not (shot.mayFall and not shot.worldId) then
		handover(shot)
	elseif not shot.hidingWorld then
		shot.hidingWorld = true
		setHidden(model, "landing", true) -- our copy is still on its way: one on screen at a time
	end
end

local function onWorldRemoved(model: Instance)
	hiddenWhy[model] = nil
	local key = model:GetAttribute("Shot")
	if type(key) ~= "number" or worldByShot[key] ~= model then
		return
	end
	worldByShot[key] = nil
	local shot = byProjectile[key]
	if shot and shot.world == model then
		shot.world = nil
		shot.hidingWorld = false
		if shot.state ~= "Flying" then
			destroyVisual(shot) -- taken (or streamed away) before our copy went: it goes too
			forget(shot)
		end
	end
end

-- Out of a body (or settled after a fall): it shows for everyone, you included.
local function onLooseAdded(model: Instance)
	local why = hiddenWhy[model]
	if model:IsA("Model") and why and why.body then
		setHidden(model, "body", false)
	end
end

-- Ground items (crates are solid and stay hittable).
local function lootFolder(): Instance?
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	return loot and loot:FindFirstChild("Items")
end

local function targetModels(): { Instance }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, dummy in ipairs(game:GetService("CollectionService"):GetTagged("TrainingDummy")) do
		if dummy:IsA("Model") and dummy:IsDescendantOf(workspace) then
			table.insert(list, dummy)
		end
	end
	return list
end

local function newShot(itemId: string, origin: Vector3, velocity: Vector3, gravity: number, isLocal: boolean): Shot
	local model: Model?, offset, spin = nil, CFrame.identity, 0
	if itemId == "arrow" then
		model, offset = arrowVisual()
	else
		model, offset, spin = itemVisual(itemId)
	end
	local now = os.clock()
	local shot: Shot = {
		id = nil,
		shotId = nil,
		isLocal = isLocal,
		itemId = itemId,
		origin = origin,
		velocity = velocity,
		gravity = gravity,
		t0 = now,
		lead = 0,
		createdAt = now,
		lifetime = (CombatConfig.ProjectileMaxLifetime or 4) + 0.3,
		position = origin,
		direction = if velocity.Magnitude > 0.01 then velocity.Unit else Vector3.new(0, 0, -1),
		model = model,
		offset = offset,
		spin = spin,
		visualOffset = nil,
		state = "Flying",
		whizzed = isLocal,
		impactPlayed = false,
		linked = not isLocal,
		shooterCharacter = nil,
		pendingImpact = nil,
		pendingDeadline = 0,
		stuckEntry = nil,
		trailOn = false,
		world = nil,
		hidingWorld = false,
		worldId = nil,
		mayFall = false,
		fall = nil,
	}
	if model then
		model:PivotTo(CFrame.new(0, -1000, 0)) -- out of sight until the first render
		model.Parent = getFolder()
	end
	table.insert(flying, shot)
	return shot
end

function ProjectileController.predict(shotId: string, itemId: string, origin: Vector3, velocity: Vector3, gravity: number, visualOrigin: Vector3?)
	if type(shotId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
		return
	end
	local shot = newShot(itemId, origin, velocity, gravity or 0, true)
	shot.shotId = shotId
	shot.shooterCharacter = player.Character
	if typeof(visualOrigin) == "Vector3" and (visualOrigin - origin).Magnitude < 6 then
		shot.visualOffset = visualOrigin - origin
	end
	byShotId[shotId] = shot
	render(shot, 0, origin)
end

local function onFired(data: any)
	if type(data) ~= "table" or type(data.id) ~= "number" or type(data.itemId) ~= "string" then
		return
	end
	if typeof(data.origin) ~= "Vector3" or typeof(data.velocity) ~= "Vector3" then
		return
	end
	local shooterId = tonumber(data.shooter) or 0
	if shooterId == player.UserId and type(data.shotId) == "string" and data.shotId ~= "" then
		local predicted = byShotId[data.shotId]
		if predicted then
			byShotId[data.shotId] = nil
			predicted.id = data.id
			predicted.linked = true
			byId[data.id] = predicted -- even if it already landed here, so its impact isn't heard twice
			if predicted.state ~= "Gone" then
				byProjectile[data.id] = predicted
			end
			return
		end
	end
	if (data.origin - camera.CFrame.Position).Magnitude > FAR_CULL then
		return -- nowhere near us (e.g. waiting in the lobby)
	end
	local gravity = tonumber(data.gravity) or 0
	local shot = newShot(data.itemId, data.origin, data.velocity, gravity, false)
	shot.id = data.id
	byId[data.id] = shot
	byProjectile[data.id] = shot
	if type(data.t) == "number" then
		shot.lead = math.clamp(workspace:GetServerTimeNow() - data.t, 0, 0.5)
	end
	local shooter = Players:GetPlayerByUserId(shooterId)
	shot.shooterCharacter = shooter and shooter.Character
	shot.whizzed = shooter == player
	render(shot, 0, data.origin)
end

local function onImpact(data: any)
	if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
		return
	end
	local info = {
		position = data.position,
		normal = if typeof(data.normal) == "Vector3" then data.normal else Vector3.yAxis,
		part = if typeof(data.part) == "Instance" and data.part:IsA("BasePart") then data.part else nil,
		material = if typeof(data.material) == "EnumItem" then data.material else nil,
		hitCharacter = data.hitCharacter == true,
		recovered = data.recovered == true,
		itemId = if type(data.itemId) == "string" then data.itemId else "arrow",
		worldId = if type(data.worldId) == "number" then data.worldId else nil,
		pivot = if typeof(data.pivot) == "CFrame" then data.pivot else nil,
		rel = if typeof(data.rel) == "CFrame" then data.rel else nil,
		fallTo = if typeof(data.fallTo) == "CFrame" then data.fallTo else nil,
		fallTime = if type(data.fallTime) == "number" then data.fallTime else nil,
		sink = data.sink == true,
	}
	local shot = if type(data.id) == "number" then byId[data.id] else nil
	if shot then
		byId[data.id] = nil
		if shot.state == "Flying" then
			local remaining = (info.position - shot.position).Magnitude
			if remaining > 4 then
				-- still on its way here: let it arrive, then land it exactly where the server did
				shot.pendingImpact = info
				local speed = math.max(shot.velocity.Magnitude, 20)
				shot.pendingDeadline = shotTime(shot, os.clock()) + remaining / speed + 0.15
				return
			end
			shot.position = info.position
		end
		if shot.state ~= "Gone" then
			settle(shot, info)
		elseif not shot.impactPlayed then
			shot.impactPlayed = true
			feedback(shot.itemId, info.position, info.normal, info.material, info.hitCharacter)
		end
		return
	end
	-- A shot we never drew (streamed in late, or it timed out locally): just land it.
	if (info.position - camera.CFrame.Position).Magnitude > FAR_CULL then
		return
	end
	feedback(info.itemId, info.position, info.normal, info.material, info.hitCharacter)
	if info.worldId then
		return -- the server's model shows by itself
	end
	if info.itemId == "arrow" and not info.recovered and not info.hitCharacter and info.material ~= Enum.Material.Water then
		local ghost = newShot("arrow", info.position, -info.normal, 0, false)
		ghost.impactPlayed = true
		ghost.direction = -info.normal
		local index = table.find(flying, ghost)
		if index then
			table.remove(flying, index)
		end
		stickAt(ghost, WorldItems.embedPivot("arrow", info.position - info.normal * 0.5, -info.normal), info.part, stickTime())
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Frame update
--------------------------------------------------------------------------------------------------------------------

local function castSegment(shot: Shot, from: Vector3, to: Vector3, targets: { Instance }, worldExclude: { Instance }): (RaycastResult?, boolean)
	local displacement = to - from
	if displacement.Magnitude < 1e-4 then
		return nil, false
	end
	local characterHit: RaycastResult? = nil
	local list = targets
	if shot.shooterCharacter then
		local index = table.find(targets, shot.shooterCharacter)
		if index then
			list = table.clone(targets)
			table.remove(list, index)
		end
	end
	if #list > 0 then
		characterParams.FilterDescendantsInstances = list
		characterHit = workspace:Raycast(from, displacement, characterParams)
	end
	worldParams.FilterDescendantsInstances = worldExclude
	local worldHit = workspace:Raycast(from, displacement, worldParams)
	if characterHit and (worldHit == nil or characterHit.Distance <= worldHit.Distance) then
		local humanoid = humanoidOf(characterHit.Instance)
		return characterHit, humanoid ~= nil and humanoid.Health > 0
	end
	return worldHit, false
end

local nextSweep = 0

local function update(_dt: number)
	local now = os.clock()
	if now >= nextSweep then
		-- forget finished shots the server never reported an impact for
		nextSweep = now + 5
		for id, shot in pairs(byId) do
			if shot.state == "Gone" and now - shot.createdAt > 10 then
				byId[id] = nil
			end
		end
		for shotId, shot in pairs(byShotId) do
			if now - shot.createdAt > 10 then
				byShotId[shotId] = nil
			end
		end
		for id, shot in pairs(byProjectile) do
			if shot.state == "Gone" then
				byProjectile[id] = nil
			end
		end
		for id, model in pairs(worldByShot) do
			if model.Parent == nil then
				worldByShot[id] = nil
			end
		end
	end
	if #flying > 0 then
		local cameraPosition = camera.CFrame.Position
		local targets = targetModels()
		local worldExclude = table.clone(targets)
		table.insert(worldExclude, getFolder())
		table.insert(worldExclude, camera)
		local loot = lootFolder()
		if loot then
			table.insert(worldExclude, loot)
		end
		for i = #flying, 1, -1 do
			local shot = flying[i]
			if shot.state == "Flying" then
				local tau = shotTime(shot, now)
				local position = positionAt(shot, tau)
				local previous = shot.position
				local pending = shot.pendingImpact
				if pending then
					local step = position - previous
					if step:Dot(pending.position - position) <= 0 or tau >= shot.pendingDeadline then
						shot.position = pending.position
						shot.pendingImpact = nil
						settle(shot, pending)
					end
				else
					local hit, hitCharacter = castSegment(shot, previous, position, targets, worldExclude)
					if hit then
						localImpact(shot, hit, hitCharacter)
					end
				end
				if shot.state == "Flying" then
					if not shot.whizzed then
						local closest = closestOnSegment(cameraPosition, previous, position)
						if (closest - cameraPosition).Magnitude < WHIZ_RADIUS and (previous - cameraPosition).Magnitude > 2.5 then
							shot.whizzed = true
							Sfx.play("ArrowWhiz", { position = closest })
						end
					end
					shot.position = position
					render(shot, tau, position)
					if not shot.trailOn then
						shot.trailOn = true
						setTrails(shot.model, true)
					end
					if tau > shot.lifetime then
						destroyVisual(shot)
						forget(shot)
					elseif shot.isLocal and not shot.linked and now - shot.createdAt > PREDICT_LINK_TIMEOUT then
						destroyVisual(shot)
						forget(shot)
					end
				end
			end
			if shot.state ~= "Flying" then
				table.remove(flying, i)
			end
		end
	end

	for i = #stuck, 1, -1 do
		local entry = stuck[i]
		local shot = entry.shot
		local expired = now > entry.expires or entry.model.Parent == nil
		if not expired and shot and shot.isLocal and not shot.linked and now - shot.createdAt > PREDICT_LINK_TIMEOUT then
			expired = true -- the server never confirmed this shot
		end
		local part = entry.part
		if not expired and part and part.Parent == nil then
			expired = true
		end
		if expired then
			table.remove(stuck, i)
			if shot then
				shot.stuckEntry = nil
				destroyVisual(shot)
				forget(shot)
			else
				entry.model:Destroy()
			end
		elseif shot and shot.fall then
			local fall = shot.fall
			local alpha = (now - fall.t0) / fall.duration
			if alpha < 1 then
				entry.model:PivotTo(WorldItems.fallPose(fall.from, fall.to, alpha, fall.sink))
			else
				entry.model:PivotTo(fall.to)
				-- landed: hand over once the server's model has landed too (it started a moment earlier)
				local model = shot.world
				local settled = model == nil or (model:GetPivot().Position - fall.to.Position).Magnitude < 0.05
				if settled or now - fall.t0 > fall.duration + 0.35 then
					shot.fall = nil
					shot.state = "Stuck"
					handover(shot)
				end
			end
		elseif part and entry.rel then
			entry.model:PivotTo(part.CFrame * entry.rel)
		end
	end
end

function ProjectileController.Init(_registry)
end

function ProjectileController.Start()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = workspace.CurrentCamera or camera
	end)
	Net.event("ProjectileFired").OnClientEvent:Connect(onFired)
	Net.event("ProjectileImpact").OnClientEvent:Connect(onImpact)
	CollectionService:GetInstanceAddedSignal(WorldItems.TAG):Connect(onWorldAdded)
	CollectionService:GetInstanceRemovedSignal(WorldItems.TAG):Connect(onWorldRemoved)
	CollectionService:GetInstanceAddedSignal(WorldItems.LOOSE_TAG):Connect(onLooseAdded)
	for _, model in ipairs(CollectionService:GetTagged(WorldItems.TAG)) do
		onWorldAdded(model)
	end
	RunService:BindToRenderStep("ProjectileController", Enum.RenderPriority.Camera.Value + 5, update)
end

return ProjectileController
