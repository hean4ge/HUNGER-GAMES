--[[
	ItemModels - 3D models for every item, plus supply crates. The Inventory/Loot system's API.
	The models are the Blender meshes in ReplicatedStorage.Assets.Items / .Crates (Items.glb, built into templates by
	ServerStorage.WorldGen.ItemAssets). Keep this API when the art changes; an item with no template gets a plain
	pouch stand-in (and a warning) so nothing breaks.

	ItemModels.build(itemId, variant) -> Model?
	  variant: "world" (default: held by other players, lying on the ground, hotbar icons)
	         | "view"  (first-person viewmodel: no shadows; the bow string is two Beams). Same attachments.
	  Returns nil for unknown ids and hidden items ("fists").
	  The model is built with its Grip at the world origin. PrimaryPart "Handle" is a small invisible part whose
	  orientation equals Grip's (so Handle.CFrame.LookVector is the item's forward). Parts are unanchored, Massless,
	  CanCollide / CanQuery / CanTouch = false, and welded to Handle with Welds (anchor Handle, or weld it to a hand,
	  and the whole item follows). Attribute ItemId on the model; mesh parts carry attribute Role (art role).
	  Attachments (all inside Handle):
	    Grip  where a hand closes around the item (identity in Handle). Place the item with
	          model:PivotTo(handFrame * Handle.Grip.CFrame:Inverse()).
	          LookVector (-Z): along the item toward its business end (blade tip, spear head, axe/mace head,
	                           bottle neck, arrow head, the bow's top limb).
	          UpVector (+Y):   a blade's spine / the back of an axe head; cutting edges face -UpVector.
	          RightVector (+X): the flat of a blade.
	          Matches the Roblox tool convention: align Grip to an R15 RightGripAttachment and the item
	          extends along the forearm, like a held Tool.
	    Tip   on every blade, the spear, hatchet, mace, throwing knife and arrow: the striking point.
	    Also: Mouth (bottles), Torso (vests: the chest cavity, front = LookVector), ArrowRest (bow), Nock (bow, arrow).
	  Bow: Grip at the riser. LookVector runs up the bow to the top limb; UpVector is the SHOOTING direction.
	    StringTop / StringBottom at the limb tips, Nock at the middle of the string (on the -UpVector side), ArrowRest on
	    the shelf (+X side). Nock has attributes RestPosition (Vector3, Handle space) and MaxDraw (studs).
	    "view": the string is two Beams StringTop->Nock->StringBottom, so moving Nock bends it; draw with
	            Nock.Position = RestPosition - Vector3.yAxis * (drawAlpha * MaxDraw). The brass nock bead (part attribute
	            FollowsNock) should move with the Nock.
	    "world": the static string mesh (reads in ViewportFrames, which don't draw Beams).
	  Arrow: Grip (and Nock) at the nock throat, LookVector toward the head. On the bow: Grip on the bow's Nock,
	    LookVector toward ArrowRest (along the bow's UpVector), UpVector = -(the bow's LookVector) so the red cock feather
	    (+RightVector) points away from the riser.
	  Vests and the med kit hang from the Grip along LookVector (held like a bag); their decorated front is the -X face.
	  Real-world scale (studs): knife 1.34, machete 2.52, sword 3.64, spear 7.02, bow 4.53 tall, arrow 3.05, bottle 1.0.

	ItemModels.buildCrate(tier) -> Model   1 plain plank crate, 2 crate with metal corners and rope handles, 3 dark
	  reinforced crate with iron bands and a faint ember glow. All parts anchored. PrimaryPart "Base": invisible
	  collision box of the crate body (CanCollide, CanQuery) whose bottom face is the crate's bottom; the body meshes are
	  visual only. Part "Lid" (its fittings are its children). Attachments in Base: "PromptAttachment" (in front of the
	  crate; the front is Base's LookVector side), "LootPoint" (inside, on the floor), "LidHinge".
	  Attributes: Tier, Opened (false), Hinge (CFrame relative to Base: rotate Lid about its X axis to open, ~100 deg).
	  Straps (PlayabilityPlan QW11, every tier, template or stand-in, built from Parts): two pale canvas straps over the
	  lid and down the front, each buckled with a brass clasp; one clasp glints faintly (ParticleEmitter "Glint" in
	  Attachment "ClaspGlint") so a crate reads at 40-60 studs in the forest. Parts StrapTop / StrapLidFront are
	  children of Lid (they swing with it); StrapBody / Clasp belong to the crate. All carry attribute CrateStrap.
	ItemModels.slackenCrate(model)   once opened (after the lid has swung): the loose strap ends hang down, the clasps
	  fall open and the glint stops, so a looted crate reads as spent.

	ItemModels.restRotation(itemId) -> CFrame   rotation that makes the item lie naturally on the ground
	ItemModels.iconRotation(itemId) -> CFrame   rotation for a hotbar icon seen by a camera looking down -Z
	ItemModels.getExtent(model, direction) -> (min, max)   projections of the model's visible parts on a direction
	ItemModels.renderIcon(viewportFrame, itemId) -> Model?
	  Builds the world model into the ViewportFrame, framed, lit and with a Sky for metal reflections.
	  Call again to swap the item (the previous icon model is removed). Pass nil itemId to just clear it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemDefs = require(script.Parent.ItemDefs)
local Theme = require(script.Parent.Theme)

local ItemModels = {}

local rad = math.rad
local V3 = Vector3.new
local CF = CFrame.new
local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STRING_COLOR = rgb(160, 132, 92) -- the bow string's rope colour (art manifest)
local STRING_WIDTH = 0.012 -- a real string is ~3 mm; it is seen from very close in first person

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[ItemModels] " .. message)
	end
end

-- On a client the first build can come before ReplicatedStorage.Assets has finished replicating: wait for it once
-- (game.Loaded, then the folder) instead of falling back to a stand-in. After that it never waits.
local assetsReady = not RunService:IsClient()
local function assetsFolder(): Instance?
	if not assetsReady then
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		ReplicatedStorage:WaitForChild("Assets", 10)
		assetsReady = true
	end
	return ReplicatedStorage:FindFirstChild("Assets")
end

local function template(folderName: string, name: string): Model?
	local assets = assetsFolder()
	local folder = assets and assets:FindFirstChild(folderName)
	local model = folder and folder:FindFirstChild(name)
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Stand-ins (only when a template is missing)
---------------------------------------------------------------------------------------------------
local function standInPart(model: Model, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function standInItem(itemId: string, def: any): Model
	local model = Instance.new("Model")
	model.Name = itemId
	local tint = (Theme.Rarity and Theme.Rarity[def.rarity]) or rgb(212, 206, 194)
	local cloth = rgb(140, 96, 62)
	local handle = standInPart(model, "Handle", Enum.PartType.Block, V3(0.3, 0.3, 0.3), CF(0, 0, -0.32), cloth, M.Fabric)
	model.PrimaryPart = handle
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.CFrame = CF(0, 0, 0.32)
	grip.Parent = handle
	local parts = {
		standInPart(model, "Pouch", Enum.PartType.Ball, V3(0.5, 0.5, 0.5), CF(0, 0, -0.34), cloth, M.Fabric),
		standInPart(model, "Tie", Enum.PartType.Cylinder, V3(0.05, 0.25, 0.25), CF(0, 0, -0.08) * CFrame.Angles(0, rad(90), 0), tint, M.Fabric),
	}
	for _, p in ipairs(parts) do
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = p
		w.C0 = handle.CFrame:Inverse() * p.CFrame
		w.Parent = p
	end
	return model
end

local function standInCrate(tier: number): Model
	local model = Instance.new("Model")
	local wood = ({ rgb(126, 94, 64), rgb(112, 82, 54), rgb(82, 60, 44) })[tier]
	local base = standInPart(model, "Base", Enum.PartType.Block, V3(4, 1.95, 2.6), CF(0, 0.975, 0), wood, M.WoodPlanks)
	local lid = standInPart(model, "Lid", Enum.PartType.Block, V3(4.06, 0.24, 2.66), CF(0, 2.07, 0), wood, M.WoodPlanks)
	for _, p in ipairs({ base, lid }) do
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = true
		p.Massless = false
	end
	model.PrimaryPart = base
	local prompt = Instance.new("Attachment")
	prompt.Name = "PromptAttachment"
	prompt.Position = V3(0, 0.225, -1.45)
	prompt.Parent = base
	model:SetAttribute("Hinge", CF(0, 0.975, 1.3))
	return model
end

---------------------------------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------------------------------

-- First-person bow: the string mesh becomes two Beams through the Nock, so pulling the Nock bends the string.
local function viewString(model: Model)
	local handle = model.PrimaryPart :: BasePart
	local top = handle:FindFirstChild("StringTop")
	local nock = handle:FindFirstChild("Nock")
	local bottom = handle:FindFirstChild("StringBottom")
	if not (top and nock and bottom) then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("String") then
			d:Destroy()
		end
	end
	for _, pair in ipairs({ { top, nock }, { nock, bottom } }) do
		local beam = Instance.new("Beam")
		beam.Name = "String"
		beam.Attachment0 = pair[1] :: Attachment
		beam.Attachment1 = pair[2] :: Attachment
		beam.Width0 = STRING_WIDTH
		beam.Width1 = STRING_WIDTH
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightInfluence = 1
		beam.Color = ColorSequence.new(STRING_COLOR)
		beam.Transparency = NumberSequence.new(0)
		beam.Parent = handle
	end
end

function ItemModels.build(itemId: string, variant: string?): Model?
	local def = ItemDefs.get(itemId)
	if not def or def.hidden then
		return nil
	end
	local view = variant == "view"
	local source = template("Items", itemId)
	local model: Model
	if source then
		model = source:Clone()
	else
		warnOnce(itemId, string.format("no mesh template ReplicatedStorage.Assets.Items.%s; using a stand-in", itemId))
		model = standInItem(itemId, def)
	end
	model.Name = itemId
	if view then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CastShadow = false
			end
		end
		viewString(model)
	end
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("Variant", if view then "view" else "world")
	return model
end

---------------------------------------------------------------------------------------------------
-- Rest and icon orientations (Handle frame)
---------------------------------------------------------------------------------------------------
local REST_FLAT = CFrame.Angles(0, 0, rad(90)) -- the item's X (blade flat) points up
local REST_FRONT_UP = CFrame.Angles(0, 0, rad(-90)) -- the item's -X (the decorated front of vests, the kit's cross) points up
local REST_UPRIGHT = CFrame.Angles(rad(90), 0, 0) -- the item's forward (neck, stem, tin top) points up
local REST: { [string]: CFrame } = {
	leather_vest = REST_FRONT_UP,
	padded_armor = REST_FRONT_UP,
	medkit = REST_FRONT_UP,
	bandage = CFrame.identity, -- roll on its side, the loose end lying flat
	apple = REST_UPRIGHT,
	water_bottle = REST_UPRIGHT,
	empty_bottle = REST_UPRIGHT,
	ration = REST_UPRIGHT,
}

function ItemModels.restRotation(itemId: string): CFrame
	return REST[itemId] or REST_FLAT
end

-- Long items: forward to the top-right, blade flat facing the camera (+Z), then a small 3D turn.
local DIAGONAL = CFrame.fromMatrix(Vector3.zero, V3(0, 0, 1), V3(-1, 1, 0).Unit, V3(-1, -1, 0).Unit)
-- Flat-faced items (kits, vests): front face (-X) to the camera, their top (+Z) up.
local FACING = CFrame.fromMatrix(Vector3.zero, V3(0, 0, -1), V3(-1, 0, 0), V3(0, 1, 0))
local ICON_DEFAULT = CFrame.Angles(rad(10), rad(-22), 0) * DIAGONAL
local ICON: { [string]: CFrame } = {
	bow = CFrame.Angles(rad(8), rad(-28), 0) * DIAGONAL,
	apple = CFrame.Angles(rad(-18), rad(25), 0) * REST_UPRIGHT,
	water_bottle = CFrame.Angles(0, 0, rad(-16)) * CFrame.Angles(rad(-12), rad(30), 0) * REST_UPRIGHT,
	empty_bottle = CFrame.Angles(0, 0, rad(-16)) * CFrame.Angles(rad(-12), rad(30), 0) * REST_UPRIGHT,
	ration = CFrame.Angles(rad(-20), rad(35), 0) * REST_UPRIGHT,
	bandage = CFrame.Angles(rad(-18), rad(-38), 0),
	medkit = CFrame.Angles(rad(-10), rad(28), 0) * FACING,
	leather_vest = CFrame.Angles(rad(-8), rad(24), 0) * FACING,
	padded_armor = CFrame.Angles(rad(-8), rad(24), 0) * FACING,
	berries = CFrame.Angles(rad(-15), rad(20), 0) * CFrame.Angles(0, 0, rad(-35)) * REST_UPRIGHT,
	herbs = CFrame.Angles(rad(-12), rad(24), 0) * CFrame.Angles(0, 0, rad(-25)) * REST_UPRIGHT,
}

function ItemModels.iconRotation(itemId: string): CFrame
	return ICON[itemId] or ICON_DEFAULT
end

-- Half-extent of a part along a unit direction (exact for blocks, balls and cylinders; mesh parts and wedges use their
-- bounding box).
local function halfExtentAlong(part: BasePart, dir: Vector3): number
	local cf = part.CFrame
	local s = part.Size
	local shape = if part:IsA("Part") then (part :: Part).Shape else Enum.PartType.Block
	if shape == Enum.PartType.Ball then
		return math.min(s.X, s.Y, s.Z) / 2
	elseif shape == Enum.PartType.Cylinder then
		local axisDot = math.abs(cf.RightVector:Dot(dir))
		local radius = math.min(s.Y, s.Z) / 2
		return axisDot * s.X / 2 + radius * math.sqrt(math.max(0, 1 - axisDot * axisDot))
	end
	return math.abs(cf.RightVector:Dot(dir)) * s.X / 2
		+ math.abs(cf.UpVector:Dot(dir)) * s.Y / 2
		+ math.abs(cf.LookVector:Dot(dir)) * s.Z / 2
end

function ItemModels.getExtent(model: Instance, direction: Vector3): (number, number)
	local dir = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.yAxis
	local lo, hi = math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local c = d.Position:Dot(dir)
			local e = halfExtentAlong(d, dir)
			if c - e < lo then
				lo = c - e
			end
			if c + e > hi then
				hi = c + e
			end
		end
	end
	if lo == math.huge then
		local p = if model:IsA("PVInstance") then (model :: PVInstance):GetPivot().Position:Dot(dir) else 0
		return p, p
	end
	return lo, hi
end

function ItemModels.renderIcon(viewport: ViewportFrame, itemId: string?): Model?
	for _, child in ipairs(viewport:GetChildren()) do
		if child:GetAttribute("ItemIcon") and not child:IsA("Camera") then
			child:Destroy()
		end
	end
	if not itemId then
		return nil
	end
	local model = ItemModels.build(itemId, "world")
	if not model then
		return nil
	end
	model:SetAttribute("ItemIcon", true)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	model:PivotTo(ItemModels.iconRotation(itemId))
	local x0, x1 = ItemModels.getExtent(model, Vector3.xAxis)
	local y0, y1 = ItemModels.getExtent(model, Vector3.yAxis)
	local z0, z1 = ItemModels.getExtent(model, Vector3.zAxis)
	local center = V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	model:PivotTo(CF(-center) * model:GetPivot())
	local camera = viewport.CurrentCamera
	if not (camera and camera:GetAttribute("ItemIcon") and camera.Parent == viewport) then
		camera = Instance.new("Camera")
		camera:SetAttribute("ItemIcon", true)
		camera.Parent = viewport
	end
	local cam = camera :: Camera
	cam.FieldOfView = 24
	local tanHalf = math.tan(rad(cam.FieldOfView / 2))
	local absolute = viewport.AbsoluteSize
	local aspect = if absolute.X > 0 and absolute.Y > 0 then absolute.X / absolute.Y else 1
	local fitHeight = ((y1 - y0) / 2) / tanHalf
	local fitWidth = ((x1 - x0) / 2) / (tanHalf * aspect)
	cam.CFrame = CF(0, 0, math.max(fitHeight, fitWidth) * 1.12 + (z1 - z0) / 2 + 0.1)
	viewport.CurrentCamera = cam
	viewport.Ambient = rgb(150, 150, 156)
	viewport.LightColor = rgb(255, 244, 228)
	viewport.LightDirection = V3(-0.55, -0.85, -0.6)
	if not viewport:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "IconSky"
		sky.Parent = viewport
	end
	model.Parent = viewport
	return model
end

---------------------------------------------------------------------------------------------------
-- Supply crates (crate space: bottom centre at the origin, front = -Z)
---------------------------------------------------------------------------------------------------
local STRAP_COLOR = rgb(212, 201, 174) -- pale, slightly weathered canvas (ember stays the colour of arena hazards)
local CLASP_COLOR = rgb(181, 142, 76) -- brass
local GLINT_COLOR = rgb(255, 238, 198)

local function strapPart(name: string, size: Vector3, cframe: CFrame, parent: Instance, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("CrateStrap", true)
	p.Parent = parent
	return p
end

-- Two canvas straps, buckled at the front with brass clasps (sized from the crate's own Base and Lid).
local function addStraps(model: Model)
	local base = model.PrimaryPart
	local lid = model:FindFirstChild("Lid")
	if not (base and lid and lid:IsA("BasePart")) or model:FindFirstChild("Clasp", true) then
		return
	end
	local frame = base.CFrame
	local up, look = frame.UpVector, frame.LookVector -- look = the crate's front
	local function along(part: BasePart, dir: Vector3): number
		return (part.Position - frame.Position):Dot(dir) + halfExtentAlong(part, dir)
	end
	local lidTop = along(lid, up)
	for _, d in ipairs(lid:GetDescendants()) do
		if d:IsA("BasePart") then
			lidTop = math.max(lidTop, along(d, up))
		end
	end
	local front = base.Size.Z / 2
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d ~= base then
			front = math.max(front, along(d, look))
		end
	end
	local bodyTop = base.Size.Y / 2
	local width = base.Size.X
	local depth = math.max(base.Size.Z, lid.Size.Z)
	local strapW = math.clamp(width * 0.08, 0.26, 0.36)
	local thick = 0.035
	local claspY = bodyTop - math.clamp(base.Size.Y * 0.18, 0.2, 0.42)
	local bottom = -bodyTop + math.clamp(base.Size.Y * 0.15, 0.15, 0.35)
	local faceZ = front + thick / 2 + 0.005
	for i, side in ipairs({ -1, 1 }) do
		local x = side * width * 0.24
		local function onFront(y: number, outward: number): CFrame
			return frame * CFrame.new(x, y, 0) + look * outward
		end
		strapPart("StrapTop", Vector3.new(strapW, thick, depth + 0.07), frame * CFrame.new(x, lidTop + thick / 2, 0), lid, STRAP_COLOR, Enum.Material.Fabric)
		-- from the lid's top edge down to the clasp: this end comes loose when the crate is opened
		local tail = lidTop - claspY
		local flap = strapPart("StrapLidFront", Vector3.new(strapW, tail, thick), onFront(lidTop - tail / 2, faceZ), lid, STRAP_COLOR, Enum.Material.Fabric)
		flap:SetAttribute("SlackHang", true)
		local bodyLen = claspY - bottom
		strapPart("StrapBody", Vector3.new(strapW, bodyLen, thick), onFront(claspY - bodyLen / 2, faceZ), model, STRAP_COLOR, Enum.Material.Fabric)
		local clasp = strapPart("Clasp", Vector3.new(strapW + 0.12, 0.26, 0.06), onFront(claspY, front + thick + 0.035), model, CLASP_COLOR, Enum.Material.Metal)
		clasp.Reflectance = 0.2
		clasp:SetAttribute("SlackClasp", true)
		if i == 2 then
			local holder = Instance.new("Attachment")
			holder.Name = "ClaspGlint"
			holder.Position = Vector3.new(strapW * 0.25, 0.05, -0.04) -- on the clasp's front face (its -Z = the crate front)
			local glint = Instance.new("ParticleEmitter")
			glint.Name = "Glint"
			glint.Color = ColorSequence.new(GLINT_COLOR)
			glint.LightEmission = 1
			glint.LightInfluence = 0.35
			glint.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(1, 0),
			})
			glint.Transparency = NumberSequence.new(0.15)
			glint.Lifetime = NumberRange.new(0.35, 0.6)
			glint.Rate = 0.45
			glint.Speed = NumberRange.new(0)
			glint.Rotation = NumberRange.new(0, 360)
			glint.RotSpeed = NumberRange.new(-90, 90)
			glint.ZOffset = 0.3
			glint.LockedToPart = true
			glint.Parent = holder
			holder.Parent = clasp
		end
	end
end

function ItemModels.slackenCrate(model: Model)
	local base = model.PrimaryPart
	if not base then
		return
	end
	local rng = Random.new()
	local back = Vector3.new(-base.CFrame.LookVector.X, 0, -base.CFrame.LookVector.Z)
	back = if back.Magnitude > 1e-3 then back.Unit else Vector3.zAxis
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "Glint" and d.Parent and d.Parent.Name == "ClaspGlint" then
			d.Enabled = false
			d:Clear()
		elseif d:IsA("BasePart") and d:GetAttribute("SlackHang") then
			-- the loose end hangs from where it joins the strap over the lid, wherever the lid is now
			local len = d.Size.Y
			local top = d.CFrame:PointToWorldSpace(Vector3.new(0, len / 2, 0)) + back * 0.04
			d.CFrame = CFrame.lookAt(top, top + back)
				* CFrame.Angles(rng:NextNumber(-0.18, 0.05), 0, rng:NextNumber(-0.1, 0.1))
				* CFrame.new(0, -len / 2, 0)
		elseif d:IsA("BasePart") and d:GetAttribute("SlackClasp") then
			-- the clasp falls open from its lower edge
			local h = d.Size.Y
			d.CFrame = d.CFrame * CFrame.new(0, -h / 2, 0) * CFrame.Angles(math.rad(-50), 0, 0) * CFrame.new(0, h / 2, 0)
			d.Reflectance = 0.08
		end
	end
end

function ItemModels.buildCrate(tier: number?): Model
	local t = math.clamp(math.floor(tonumber(tier) or 1), 1, 3)
	local source = template("Crates", "SupplyCrate" .. t)
	local model: Model
	if source then
		model = source:Clone()
	else
		warnOnce("crate" .. t, string.format("no mesh template ReplicatedStorage.Assets.Crates.SupplyCrate%d; using a stand-in", t))
		model = standInCrate(t)
	end
	model.Name = "SupplyCrate"
	model:SetAttribute("Tier", t)
	model:SetAttribute("Opened", false)
	local ok, err = pcall(addStraps, model)
	if not ok then
		warnOnce("straps", "crate straps failed: " .. tostring(err))
	end
	return model
end

return ItemModels
