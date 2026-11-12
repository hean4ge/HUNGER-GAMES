--[[
	Kit - construction helpers for the WorldGen builders (edit time only). Used by AssetBuilder and Populate.

	Template conventions (every Model in ServerStorage.WorldAssets):
	  * WorldPivot = centre of the base on the ground plane (y = 0 in model space), front facing -Z.
	    Populate places a template with model:PivotTo(groundCFrame).
	  * Attributes: Category ("Tree" | "Plant" | "Rock" | "Prop" | "Structure"), Footprint (radius in studs used
	    for spacing) and Sink (studs the pivot is pushed below the ground so bases never float on slopes).
	  * Parts are Anchored with CanTouch = false. Soft foliage (leaves, bushes, reeds) has CanCollide = false and
	    CanQuery = false so players can walk into it and hide.
	  * Special children converted by Populate: BaseParts named "LootPoint" (attributes Tier, Kind) become
	    LootSpawn markers, BaseParts named "EmitterPoint" (attribute SoundKey) become AmbientEmitters, and
	    Attachments named "Foot" get a post or pier down to the terrain.
	  * Unions keep per-part colours but use ONE material, so union parts that share a material.
]]
local GeometryService = game:GetService("GeometryService")

local Kit = {}

Kit.Palette = {
	-- foliage
	PineNeedles = Color3.fromRGB(50, 76, 57),
	PineNeedlesDark = Color3.fromRGB(40, 62, 49),
	PineNeedlesLight = Color3.fromRGB(64, 88, 61),
	OakLeaves = Color3.fromRGB(86, 110, 56),
	OakLeavesDark = Color3.fromRGB(68, 92, 50),
	BirchLeaves = Color3.fromRGB(124, 142, 68),
	BushLeaves = Color3.fromRGB(72, 98, 52),
	BushLeavesDark = Color3.fromRGB(58, 82, 46),
	Moss = Color3.fromRGB(94, 106, 64),
	Reed = Color3.fromRGB(122, 128, 74),
	ReedDry = Color3.fromRGB(150, 138, 92),
	Cattail = Color3.fromRGB(88, 60, 40),
	Berry = Color3.fromRGB(150, 34, 52),
	MushroomCap = Color3.fromRGB(164, 72, 50),
	MushroomCapTan = Color3.fromRGB(176, 140, 96),
	MushroomStem = Color3.fromRGB(222, 212, 190),
	Thatch = Color3.fromRGB(150, 128, 82),
	-- wood
	PineBark = Color3.fromRGB(84, 66, 53),
	OakBark = Color3.fromRGB(90, 72, 57),
	BirchBark = Color3.fromRGB(216, 212, 200),
	BirchMark = Color3.fromRGB(44, 41, 39),
	DeadWood = Color3.fromRGB(106, 98, 88),
	CutWood = Color3.fromRGB(176, 140, 98),
	Timber = Color3.fromRGB(118, 89, 64),
	TimberDark = Color3.fromRGB(80, 61, 46),
	TimberWeathered = Color3.fromRGB(124, 113, 98),
	Planks = Color3.fromRGB(138, 106, 76),
	-- stone and metal
	Rock = Color3.fromRGB(124, 121, 115),
	Slate = Color3.fromRGB(98, 100, 104),
	Basalt = Color3.fromRGB(74, 72, 71),
	Paving = Color3.fromRGB(134, 128, 118),
	PavingDark = Color3.fromRGB(100, 96, 90),
	SpireStone = Color3.fromRGB(112, 108, 103),
	SpireStoneDark = Color3.fromRGB(80, 78, 77),
	DarkMetal = Color3.fromRGB(46, 44, 44),
	Iron = Color3.fromRGB(72, 70, 68),
	-- accents
	Ember = Color3.fromRGB(232, 116, 59),
	EmberDeep = Color3.fromRGB(196, 82, 38),
	EmberGlow = Color3.fromRGB(255, 150, 72),
	Canvas = Color3.fromRGB(150, 138, 104),
	CanvasGreen = Color3.fromRGB(96, 104, 76),
	Charcoal = Color3.fromRGB(38, 36, 35),
	Ash = Color3.fromRGB(72, 68, 64),
	Rope = Color3.fromRGB(160, 140, 100),
	Glass = Color3.fromRGB(255, 200, 130),
	Cloth = Color3.fromRGB(120, 66, 48),
}

Kit.M = Enum.Material

-- Property sets applied with Kit.setAll
Kit.SOLID = { Anchored = true, CanCollide = true, CanQuery = true, CanTouch = false }
Kit.SOFT = { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false } -- leaves, bushes, reeds, cloth
Kit.DECOR = { Anchored = true, CanCollide = false, CanQuery = true, CanTouch = false } -- non-solid but hittable
Kit.NOSHADOW = { CastShadow = false }

local SMOOTH = Enum.SurfaceType.Smooth

function Kit.part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	return p
end

function Kit.block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	return Kit.part(name, size, cframe, color, material)
end

function Kit.ball(name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material): Part
	return Kit.part(name, Vector3.new(diameter, diameter, diameter), CFrame.new(position), color, material, Enum.PartType.Ball)
end

function Kit.wedge(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	return Kit.part(name, size, cframe, color, material, Enum.PartType.Wedge)
end

-- Cylinder whose axis runs along cframe.UpVector, centred on cframe.
function Kit.vcyl(name: string, height: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material): Part
	return Kit.part(name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

-- CFrame centred between a and b whose local X axis points from a to b.
function Kit.spanFrame(a: Vector3, b: Vector3): (CFrame, number)
	local delta = b - a
	local length = delta.Magnitude
	local dir = if length > 1e-4 then delta / length else Vector3.yAxis
	local up = if math.abs(dir.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, (a + b) / 2 + dir, up) * CFrame.Angles(0, math.pi / 2, 0)
	return cf, length
end

-- A round rod (cylinder) or a square beam from a to b.
function Kit.rod(name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material, square: boolean?): Part
	local cf, length = Kit.spanFrame(a, b)
	if square then
		return Kit.part(name, Vector3.new(length, diameter, diameter), cf, color, material)
	end
	return Kit.part(name, Vector3.new(length, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

-- A flat board from a to b (thickness along the board's local Y, width along local Z).
function Kit.plank(name: string, a: Vector3, b: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material, roll: number?): Part
	local cf, length = Kit.spanFrame(a, b)
	if roll then
		cf *= CFrame.Angles(roll, 0, 0)
	end
	return Kit.part(name, Vector3.new(length, thickness, width), cf, color, material)
end

-- Root flare: wedges sloping down and away from a vertical trunk of the given radius (appended to list).
function Kit.roots(list: { BasePart }, count: number, radius: number, height: number, length: number, color: Color3, rng: Random)
	local yaw0 = rng:NextNumber(0, 360)
	for i = 0, count - 1 do
		local yaw = math.rad(yaw0 + i * (360 / count) + rng:NextNumber(-12, 12))
		local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		local pos = dir * (radius + length / 2 - 0.5) + Vector3.new(0, height / 2 - 0.35, 0)
		local cf = CFrame.lookAt(pos, pos - dir) * CFrame.Angles(0, math.pi, 0)
		table.insert(list, Kit.wedge("Root", Vector3.new(math.max(0.6, radius * 0.9), height, length), cf, color, Enum.Material.Wood))
	end
	return list
end

-- Square pyramid (4 corner wedges) appended to out. baseCF = centre of the base, apex along baseCF.UpVector.
local QUADS = { { -1, 1, 0 }, { 1, 1, 90 }, { 1, -1, 180 }, { -1, -1, 270 } }
function Kit.pyramid(out: { BasePart }, baseCF: CFrame, width: number, height: number, color: Color3, material: Enum.Material, depth: number?): { BasePart }
	local d = depth or width
	for _, q in ipairs(QUADS) do
		local rotated = q[3] == 90 or q[3] == 270
		local sx = if rotated then d / 2 else width / 2
		local sz = if rotated then width / 2 else d / 2
		local cf = baseCF * CFrame.new(q[1] * width / 4, height / 2, q[2] * d / 4) * CFrame.Angles(0, math.rad(q[3]), 0)
		table.insert(out, Kit.part("Pyramid", Vector3.new(sx, height, sz), cf, color, material, Enum.PartType.CornerWedge))
	end
	return out
end

-- Hemisphere (dome) of the given diameter sitting on cframe (flat side down). Falls back to a squashed block.
function Kit.dome(name: string, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material): BasePart
	local ball = Kit.part(name, Vector3.new(diameter, diameter, diameter), cframe, color, material, Enum.PartType.Ball)
	local cutter = Kit.part("Cutter", Vector3.new(diameter + 1, diameter / 2 + 0.5, diameter + 1), cframe * CFrame.new(0, -diameter / 4 - 0.25, 0), color, material)
	local ok, result = pcall(function()
		return GeometryService:SubtractAsync(ball, { cutter }, { SplitApart = false, CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	cutter:Destroy()
	if ok and type(result) == "table" and result[1] then
		ball:Destroy()
		local dome = result[1] :: BasePart
		dome.Name = name
		dome.Anchored = true
		return dome
	end
	return ball
end

-- Regular octagonal prism (intersection of two squares), axis along cframe.UpVector. width = flat-to-flat.
function Kit.octagon(name: string, width: number, height: number, cframe: CFrame, color: Color3, material: Enum.Material): BasePart
	local a = Kit.part(name, Vector3.new(width, height, width), cframe, color, material)
	local b = Kit.part(name, Vector3.new(width, height, width), cframe * CFrame.Angles(0, math.rad(45), 0), color, material)
	local ok, result = pcall(function()
		return GeometryService:IntersectAsync(a, { b }, { SplitApart = false, CollisionFidelity = Enum.CollisionFidelity.Default })
	end)
	b:Destroy()
	if ok and type(result) == "table" and result[1] then
		a:Destroy()
		local oct = result[1] :: BasePart
		oct.Name = name
		oct.Anchored = true
		oct.CanTouch = false
		return oct
	end
	return a
end

export type UnionOpts = {
	collision: Enum.CollisionFidelity?,
	render: Enum.RenderFidelity?,
	usePartColor: boolean?,
}

-- Unions parts that share one material into a single part (CSG). Falls back to a Model of the parts.
function Kit.union(name: string, parts: { BasePart }, opts: UnionOpts?): Instance
	local o = opts or {}
	assert(#parts > 0, "Kit.union needs parts")
	if #parts == 1 then
		parts[1].Name = name
		return parts[1]
	end
	local main = parts[1]
	local others = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return GeometryService:UnionAsync(main, others, {
			SplitApart = false,
			CollisionFidelity = o.collision or Enum.CollisionFidelity.Default,
			RenderFidelity = o.render or Enum.RenderFidelity.Automatic,
		})
	end)
	if ok and type(result) == "table" and result[1] then
		local u = result[1] :: UnionOperation
		u.Name = name
		u.Anchored = true
		u.CanTouch = false
		u.UsePartColor = o.usePartColor == true
		if o.usePartColor then
			u.Color = main.Color
		end
		for _, p in ipairs(parts) do
			p:Destroy()
		end
		return u
	end
	warn("[Kit] union failed for " .. name .. ": " .. tostring(result))
	local model = Instance.new("Model")
	model.Name = name
	for _, p in ipairs(parts) do
		p.Parent = model
	end
	return model
end

-- Sets properties on root (if a BasePart) and on every BasePart under it.
function Kit.setAll(root: Instance, props: { [string]: any }): Instance
	local function apply(inst: Instance)
		for key, value in pairs(props) do
			(inst :: any)[key] = value
		end
	end
	if root:IsA("BasePart") then
		apply(root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			apply(d)
		end
	end
	return root
end

function Kit.model(name: string, children: { Instance }, attributes: { [string]: any }?, pivot: CFrame?): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, child in ipairs(children) do
		child.Parent = model
	end
	model.WorldPivot = pivot or CFrame.identity
	if attributes then
		for key, value in pairs(attributes) do
			model:SetAttribute(key, value)
		end
	end
	return model
end

function Kit.attrs(inst: Instance, attributes: { [string]: any }): Instance
	for key, value in pairs(attributes) do
		inst:SetAttribute(key, value)
	end
	return inst
end

-- Invisible marker part that Populate turns into a LootSpawn marker. cf = where the item / crate base sits.
function Kit.lootPoint(cframe: CFrame, tier: number, kind: string): Part
	local size = if kind == "Crate" then Vector3.new(4, 2.2, 2.6) else Vector3.new(1, 1, 1)
	local p = Kit.part("LootPoint", size, cframe, Color3.fromRGB(255, 200, 0), Enum.Material.SmoothPlastic)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p:SetAttribute("Tier", tier)
	p:SetAttribute("Kind", kind)
	return p
end

-- Loot point standing on a floor at floorPos (handles the crate half-height).
function Kit.lootOnFloor(floorPos: Vector3, yaw: number, tier: number, kind: string): Part
	local half = if kind == "Crate" then 1.1 else 0.5
	return Kit.lootPoint(CFrame.new(floorPos + Vector3.new(0, half, 0)) * CFrame.Angles(0, yaw, 0), tier, kind)
end

-- Invisible marker part that Populate turns into an AmbientEmitter.
function Kit.emitterPoint(position: Vector3, soundKey: string): Part
	local p = Kit.part("EmitterPoint", Vector3.new(1, 1, 1), CFrame.new(position), Color3.fromRGB(0, 170, 255), Enum.Material.SmoothPlastic)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p:SetAttribute("SoundKey", soundKey)
	return p
end

-- Attachment marking where a support post / pier should reach down to the terrain.
function Kit.foot(parent: BasePart, worldPosition: Vector3, width: number?, material: string?): Attachment
	local a = Instance.new("Attachment")
	a.Name = "Foot"
	a.Parent = parent
	a.WorldPosition = worldPosition
	a:SetAttribute("Width", width or 1.2)
	a:SetAttribute("Material", material or "Wood")
	return a
end

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/fire_sparks_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

export type FireOpts = {
	light: number?, -- PointLight brightness (0 = no light)
	range: number?,
	shadows: boolean?,
	smoke: number?, -- smoke rate multiplier (0 = none)
	sparks: number?,
	rate: number?,
}

-- Flame, ember sparks and smoke emitters plus a warm PointLight. parent: Attachment (point) or BasePart (area).
-- scale 1 = campfire-sized flames.
function Kit.fireFx(parent: Instance, scale: number, opts: FireOpts?)
	local o = opts or {}
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Texture = FIRE_TEXTURE
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 205, 120)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(250, 128, 52)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 52, 28)),
	})
	flame.LightEmission = 1
	flame.LightInfluence = 0
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5 * scale),
		NumberSequenceKeypoint.new(0.55, 1.1 * scale),
		NumberSequenceKeypoint.new(1, 0.15 * scale),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.Lifetime = NumberRange.new(0.45, 0.85)
	flame.Speed = NumberRange.new(2.4 * scale, 4.2 * scale)
	flame.SpreadAngle = Vector2.new(10, 10)
	flame.Rotation = NumberRange.new(-25, 25)
	flame.RotSpeed = NumberRange.new(-50, 50)
	flame.Acceleration = Vector3.new(0, 2.5 * scale, 0)
	flame.Rate = (o.rate or 28) * math.max(1, scale ^ 0.5)
	flame.Parent = parent

	if (o.sparks or 1) > 0 then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Embers"
		sparks.Texture = SPARK_TEXTURE
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(255, 90, 40))
		sparks.LightEmission = 1
		sparks.LightInfluence = 0
		sparks.Size = NumberSequence.new(0.18 * math.max(1, scale * 0.7), 0.05)
		sparks.Lifetime = NumberRange.new(1.0, 2.2)
		sparks.Speed = NumberRange.new(3 * scale, 7 * scale)
		sparks.SpreadAngle = Vector2.new(25, 25)
		sparks.Acceleration = Vector3.new(0.6, 2, 0)
		sparks.Drag = 0.6
		sparks.Rate = 5 * (o.sparks or 1) * math.max(1, scale ^ 0.5)
		sparks.Parent = parent
	end

	if (o.smoke or 1) > 0 then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		smoke.Texture = SMOKE_TEXTURE
		smoke.Color = ColorSequence.new(Color3.fromRGB(96, 92, 88), Color3.fromRGB(150, 146, 140))
		smoke.LightInfluence = 0.6
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.4 * scale),
			NumberSequenceKeypoint.new(1, 6 * scale),
		})
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.3, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Lifetime = NumberRange.new(3.5, 6)
		smoke.Speed = NumberRange.new(2.5 * scale, 4 * scale)
		smoke.SpreadAngle = Vector2.new(8, 8)
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-15, 15)
		smoke.Acceleration = Vector3.new(0.8, 0.6, 0.3)
		smoke.Rate = 2.5 * (o.smoke or 1)
		smoke.Parent = parent
	end

	if (o.light or 1.6) > 0 then
		local light = Instance.new("PointLight")
		light.Name = "FireLight"
		light.Color = Color3.fromRGB(255, 152, 82)
		light.Brightness = o.light or 1.6
		light.Range = math.min(60, o.range or 18 * scale)
		light.Shadows = o.shadows == true
		light.Parent = parent
	end
end

-- HSV jitter for per-instance colour variation.
function Kit.jitter(color: Color3, rng: Random, hue: number, sat: number, val: number): Color3
	local h, s, v = color:ToHSV()
	h = (h + rng:NextNumber(-hue, hue)) % 1
	s = math.clamp(s * (1 + rng:NextNumber(-sat, sat)), 0, 1)
	v = math.clamp(v * (1 + rng:NextNumber(-val, val)), 0, 1)
	return Color3.fromHSV(h, s, v)
end

-- Counts BaseParts under an instance.
function Kit.countParts(root: Instance): number
	local n = if root:IsA("BasePart") then 1 else 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return Kit
