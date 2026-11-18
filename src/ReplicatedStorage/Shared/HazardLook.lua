--[[
	HazardLook - what the arena challenges look like: every colour, size, part recipe and particle recipe in one place.
	HazardController (client) builds from it; HazardService (server) uses only HazardLook.boulder for the rocks a
	rockfall leaves behind. The numbers that decide who is hurt are in Shared.HazardDefs, never here.

	SWAPPING IN BLENDER MESHES
	  Everything is built from Parts, WedgeParts, Beams and ParticleEmitters with Roblox's own textures, because
	  nothing has been uploaded. When a mesh is in the place, put a Model (PrimaryPart set) or a BasePart under
	  ReplicatedStorage.HazardAssets and name it in HazardLook.Templates below. That table is the only change:
	    Templates.ButterflyWingL / ButterflyWingR   one wing each, hinge edge along the part's -Y face
	    Templates.Boulder                           one rock, about 2 studs across (it is scaled to the radius)
	  The boulder also falls back to the map's own M1_Boulder rocks (workspace.Arena.Scatter) before the part-built one.

	The style: Roblox's own blocky look, matte (SmoothPlastic / Slate), no Neon parts. Saturated colour is kept for
	the hazard itself (the butterflies' blue). Nothing here is red, and nothing shows a wound.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HazardLook = {}

HazardLook.Templates = {
	ButterflyWingL = nil :: string?,
	ButterflyWingR = nil :: string?,
	Boulder = nil :: string?,
}

HazardLook.Textures = {
	Square = "rbxasset://textures/particles/SquareParticle.png",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}

HazardLook.Colors = {
	-- the butterflies (brief: blue 70,126,186; the trailer's are a brighter sky blue with dark undersides)
	WingBlue = { Color3.fromRGB(52, 128, 214), Color3.fromRGB(70, 150, 226), Color3.fromRGB(96, 176, 236) },
	WingDark = Color3.fromRGB(26, 36, 58),
	StingEdge = Color3.fromRGB(72, 150, 232),
	-- fog (brief: 224,226,214, taken a little cooler for a mountain valley)
	Fog = Color3.fromRGB(222, 228, 230),
	Frost = Color3.fromRGB(226, 238, 248),
	-- storm
	Cloud = Color3.fromRGB(74, 80, 92),
	Rain = Color3.fromRGB(196, 208, 222),
	Bolt = Color3.fromRGB(224, 232, 255),
	-- rock
	Rock = Color3.fromRGB(122, 120, 116),
	Dust = Color3.fromRGB(168, 158, 142),
}

-- How much of each effect a detail tier draws (DetailController publishes the tier as LocalPlayer.DetailTier).
HazardLook.Tiers = {
	High = {
		butterflies = 34, -- real two-winged butterflies in the nearest swarm
		restButterflies = 7, -- sitting on a roost
		swarmsDrawn = 3, -- swarms with real butterflies (the others are particles only)
		wingRate = 70, -- particle wings a second in a swarm
		shimmer = true,
		roostRange = 150, -- studs: resting butterflies are built inside this
		fogShells = 3,
		fogSheets = 36,
		fogRate = 1,
		cloudSheets = 14,
		rainRate = 240,
		boltSegments = 9,
		dust = 1,
	},
	Medium = {
		butterflies = 22,
		restButterflies = 5,
		swarmsDrawn = 2,
		wingRate = 44,
		shimmer = true,
		roostRange = 110,
		fogShells = 3,
		fogSheets = 18,
		fogRate = 0.7,
		cloudSheets = 9,
		rainRate = 130,
		boltSegments = 7,
		dust = 0.6,
	},
	Low = { -- the phone tier
		butterflies = 12,
		restButterflies = 3,
		swarmsDrawn = 1,
		wingRate = 22,
		shimmer = false,
		roostRange = 80,
		fogShells = 2,
		fogSheets = 8,
		fogRate = 0.4,
		cloudSheets = 5,
		rainRate = 60,
		boltSegments = 5,
		dust = 0.3,
	},
}

function HazardLook.tier(name: any)
	return HazardLook.Tiers[name] or HazardLook.Tiers.High
end

local function template(name: string?): Instance?
	if not name then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("HazardAssets")
	return folder and folder:FindFirstChild(name)
end

local function still(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Locked = true
end
HazardLook.still = still

----------------------------------------------------------------------------------------------------
-- Butterflies
----------------------------------------------------------------------------------------------------
HazardLook.Butterfly = {
	Span = 0.46, -- one wing, root to tip (a wingspan of about 0.9 with the gap: the brief's 0.6 to 0.8 read too small in play)
	Chord = 0.52,
	Thickness = 0.04,
	FlapHz = { 9, 13 },
	FlapUp = 1.3, -- radians above level at the top of the stroke
	FlapDown = -0.35,
	RestAngle = 1.42, -- wings closed over the back
	RestOpenEvery = { 3, 9 }, -- a sitting butterfly opens its wings now and then
}

-- A wing's place on the body (body: -Z is forward, +Y up). The wedge's long side lies along the body; its point
-- trails. Multiply: bodyCFrame * CFrame.Angles(0, 0, -angle) * WingL, bodyCFrame * CFrame.Angles(0, 0, angle) * WingR.
do
	local half = HazardLook.Butterfly.Span / 2
	HazardLook.WingL = CFrame.fromMatrix(Vector3.new(-half, 0, 0), Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1))
	HazardLook.WingR = CFrame.fromMatrix(Vector3.new(half, 0, 0), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1))
end

-- One butterfly: two wing parts (not parented; the caller parents them). scale 0.8..1.25.
function HazardLook.butterflyWings(scale: number, shade: number): (BasePart, BasePart)
	local B = HazardLook.Butterfly
	local blues = HazardLook.Colors.WingBlue
	local color = blues[((shade - 1) % #blues) + 1]
	local function wing(templateName: string?): BasePart
		local source = template(templateName)
		local part: BasePart
		if source and source:IsA("BasePart") then
			part = source:Clone()
			part.Size = part.Size * scale
		else
			local wedge = Instance.new("WedgePart")
			wedge.Size = Vector3.new(B.Thickness, B.Span * scale, B.Chord * scale)
			wedge.Material = Enum.Material.SmoothPlastic
			wedge.Color = color
			part = wedge
		end
		part.Name = "Wing"
		still(part)
		return part
	end
	return wing(HazardLook.Templates.ButterflyWingL), wing(HazardLook.Templates.ButterflyWingR)
end

local function sequence(points: { { number } }): NumberSequence
	local keys = table.create(#points)
	for i, p in ipairs(points) do
		keys[i] = NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0)
	end
	return NumberSequence.new(keys)
end
HazardLook.sequence = sequence

-- The body of a swarm: square flecks that squash flat and open again as they fly (they read as beating wings), and
-- flash from blue to the dark underside. This is where "hundreds of wings" come from.
function HazardLook.wingEmitter(parent: Instance, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Wings"
	e.Texture = HazardLook.Textures.Square
	e.Rate = rate
	e.Lifetime = NumberRange.new(1.3, 2.1)
	e.Speed = NumberRange.new(2.5, 7)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Drag = 1.2
	e.Acceleration = Vector3.new(0, 1.2, 0)
	e.Rotation = NumberRange.new(-35, 35)
	e.RotSpeed = NumberRange.new(-160, 160)
	e.Size = sequence({ { 0, 0.34, 0.08 }, { 1, 0.3, 0.08 } })
	local squash, colors = {}, {}
	local beats = 9
	local blues = HazardLook.Colors.WingBlue
	for i = 0, beats * 2 do
		local t = i / (beats * 2)
		-- open (a little wide) -> shut to a line -> open
		table.insert(squash, NumberSequenceKeypoint.new(t, if i % 2 == 0 then 0.5 else -2.6))
		if i % 2 == 0 then
			table.insert(colors, ColorSequenceKeypoint.new(t, blues[(i / 2) % #blues + 1]))
		else
			table.insert(colors, ColorSequenceKeypoint.new(t, blues[1]:Lerp(HazardLook.Colors.WingDark, 0.55)))
		end
	end
	e.Squash = NumberSequence.new(squash)
	e.Color = ColorSequence.new(colors)
	e.Transparency = sequence({ { 0, 1 }, { 0.08, 0 }, { 0.9, 0 }, { 1, 1 } })
	e.LightEmission = 0.12
	e.LightInfluence = 0.85
	e.Brightness = 1.25
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Parent = parent
	return e
end

-- A soft blue glitter through the cloud (not on the phone tier).
function HazardLook.shimmerEmitter(parent: Instance, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Shimmer"
	e.Texture = HazardLook.Textures.Sparkle
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Size = sequence({ { 0, 0.1 }, { 0.5, 0.42, 0.1 }, { 1, 0.1 } })
	e.Transparency = sequence({ { 0, 1 }, { 0.3, 0.45 }, { 1, 1 } })
	e.Color = ColorSequence.new(Color3.fromRGB(150, 205, 250))
	e.LightEmission = 0.5
	e.LightInfluence = 0.5
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

----------------------------------------------------------------------------------------------------
-- Fog
----------------------------------------------------------------------------------------------------
-- A sheet of the fog's top, seen from the slopes above it.
function HazardLook.fogSheetEmitter(parent: Instance): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "FogTop"
	e.Texture = HazardLook.Textures.Smoke
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Lifetime = NumberRange.new(7, 10)
	e.Speed = NumberRange.new(0.2, 0.8)
	e.SpreadAngle = Vector2.new(85, 85)
	e.Acceleration = Vector3.new(0.25, -0.02, 0.1)
	e.Drag = 0.3
	e.Size = sequence({ { 0, 18 }, { 0.5, 30, 4 }, { 1, 36, 5 } })
	e.Transparency = sequence({ { 0, 1 }, { 0.2, 0.5 }, { 0.75, 0.56 }, { 1, 1 } })
	e.Color = ColorSequence.new(HazardLook.Colors.Fog)
	e.LightInfluence = 1
	e.LightEmission = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-4, 4)
	e.Enabled = false
	e.Parent = parent
	return e
end

-- One shell of the fog a contender stands in: a sphere seen from inside (a mesh with negative scale shows its inner
-- face). Three of them at growing distances hide the world by distance, for three draw calls and no particles.
function HazardLook.fogShell(radius: number): (Part, SpecialMesh)
	local part = Instance.new("Part")
	part.Name = "FogShell"
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(2, 2, 2)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = HazardLook.Colors.Fog
	part.Transparency = 1
	still(part)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(-radius, -radius, -radius)
	mesh.Parent = part
	return part, mesh
end
HazardLook.FogShells = { { radius = 22, alpha = 0.3 }, { radius = 42, alpha = 0.5 }, { radius = 70, alpha = 0.72 } }

----------------------------------------------------------------------------------------------------
-- Storm
----------------------------------------------------------------------------------------------------
function HazardLook.cloudEmitter(parent: Instance): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "StormCloud"
	e.Texture = HazardLook.Textures.Smoke
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = 0
	e.Lifetime = NumberRange.new(9, 13)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(80, 80)
	e.Size = sequence({ { 0, 70 }, { 0.5, 110, 12 }, { 1, 120, 12 } })
	e.Transparency = sequence({ { 0, 1 }, { 0.2, 0.32 }, { 0.8, 0.4 }, { 1, 1 } })
	e.Color = ColorSequence.new(HazardLook.Colors.Cloud)
	e.LightInfluence = 0.8
	e.LightEmission = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-3, 3)
	e.Enabled = false
	e.Parent = parent
	return e
end

function HazardLook.rainEmitter(parent: Instance): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Rain"
	e.Texture = HazardLook.Textures.Square
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.45, 0.6)
	e.Speed = NumberRange.new(85, 105)
	e.SpreadAngle = Vector2.new(4, 4)
	e.Size = NumberSequence.new(0.09)
	e.Squash = NumberSequence.new(2.9) -- a long thin streak
	e.Transparency = sequence({ { 0, 0.55 }, { 1, 0.7 } })
	e.Color = ColorSequence.new(HazardLook.Colors.Rain)
	e.LightInfluence = 1
	e.LightEmission = 0.1
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Enabled = false
	e.Parent = parent
	return e
end

-- The mark on the ground before a bolt (a closing ring and rising sparks), on an attachment.
function HazardLook.strikeMark(parent: Instance, lead: number): { ParticleEmitter }
	local ring = Instance.new("ParticleEmitter")
	ring.Name = "Mark"
	ring.Texture = HazardLook.Textures.Ring
	ring.Rate = 3
	ring.Lifetime = NumberRange.new(lead * 0.5)
	ring.Speed = NumberRange.new(0)
	ring.Size = sequence({ { 0, 13 }, { 1, 2 } })
	ring.Transparency = sequence({ { 0, 1 }, { 0.3, 0.45 }, { 1, 0.2 } })
	ring.Color = ColorSequence.new(HazardLook.Colors.Bolt)
	ring.LightEmission = 0.8
	ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	ring.EmissionDirection = Enum.NormalId.Top
	ring.Parent = parent
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Static"
	sparks.Texture = HazardLook.Textures.Sparks
	sparks.Rate = 26
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(6, 16)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Size = sequence({ { 0, 0.5 }, { 1, 0.1 } })
	sparks.Color = ColorSequence.new(HazardLook.Colors.Bolt)
	sparks.LightEmission = 1
	sparks.Parent = parent
	return { ring, sparks }
end

-- A bolt from `top` to `ground`: a jagged line of beams (white core over a wider pale blue), made of `segments`
-- pieces from a seed. Returns the folder that holds it; the caller destroys it.
function HazardLook.bolt(top: Vector3, ground: Vector3, segments: number, seed: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Bolt"
	local rng = Random.new(seed)
	local anchor = Instance.new("Part")
	anchor.Name = "BoltAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(ground)
	still(anchor)
	anchor.Parent = folder
	local previous: Attachment? = nil
	for i = 0, segments do
		local u = i / segments
		local p = top:Lerp(ground, u)
		if i > 0 and i < segments then
			local wander = (1 - u) * 22 + 5
			p += Vector3.new(rng:NextNumber(-wander, wander), 0, rng:NextNumber(-wander, wander))
		end
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = p
		attachment.Parent = anchor
		attachment.WorldPosition = p
		if previous then
			for pass = 1, 2 do
				local beam = Instance.new("Beam")
				beam.Attachment0 = previous
				beam.Attachment1 = attachment
				beam.FaceCamera = true
				beam.Segments = 1
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Brightness = if pass == 1 then 4 else 1.5
				local width = if pass == 1 then 1.1 else 4.2
				beam.Width0 = width * (1.25 - u * 0.5)
				beam.Width1 = width * (1.25 - (u + 1 / segments) * 0.5)
				beam.Color = ColorSequence.new(if pass == 1 then Color3.new(1, 1, 1) else HazardLook.Colors.Bolt)
				beam.Transparency = NumberSequence.new(if pass == 1 then 0 else 0.6)
				beam.Parent = anchor
			end
		end
		previous = attachment
	end
	local light = Instance.new("PointLight")
	light.Color = HazardLook.Colors.Bolt
	light.Range = 60
	light.Brightness = 6
	light.Shadows = false
	light.Parent = anchor
	return folder
end

----------------------------------------------------------------------------------------------------
-- Rock
----------------------------------------------------------------------------------------------------
local scatterRock: BasePart? = nil

local function findScatterRock(): BasePart?
	if scatterRock and scatterRock.Parent then
		return scatterRock
	end
	local arena = workspace:FindFirstChild("Arena")
	local scatter = arena and arena:FindFirstChild("Scatter")
	if not scatter then
		return nil
	end
	local checked = 0
	for _, cell in ipairs(scatter:GetChildren()) do
		for _, name in ipairs({ "M1_Boulder_B", "M1_Boulder_A", "M1_Boulder_C" }) do
			local model = cell:FindFirstChild(name)
			if model then
				local best: BasePart? = nil
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and (not best or d.Size.Magnitude > best.Size.Magnitude) then
						best = d
					end
				end
				if best then
					scatterRock = best
					return best
				end
			end
		end
		checked += 1
		if checked > 400 then
			break
		end
	end
	return nil
end

-- A boulder about `radius` studs in radius. One part where a rock mesh is at hand (a template, else one of the
-- map's own boulders), else a model of three matte blocks. Returns the instance to move with PivotTo.
function HazardLook.boulder(radius: number): PVInstance
	local source = template(HazardLook.Templates.Boulder)
	local rock: BasePart? = nil
	if source and source:IsA("BasePart") then
		rock = source
	elseif source and source:IsA("Model") and source.PrimaryPart then
		rock = source.PrimaryPart
	else
		rock = findScatterRock()
	end
	if rock then
		local part = rock:Clone()
		for _, child in ipairs(part:GetChildren()) do
			if not child:IsA("SurfaceAppearance") and not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		local biggest = math.max(part.Size.X, part.Size.Y, part.Size.Z)
		part.Size = part.Size * (radius * 2 / math.max(biggest, 0.1))
		part.Name = "HazardBoulder"
		still(part)
		part.CastShadow = true
		return part
	end
	local model = Instance.new("Model")
	model.Name = "HazardBoulder"
	local d = radius * 2
	local recipe = {
		{ Vector3.new(d * 0.82, d * 0.7, d * 0.78), CFrame.Angles(0.3, 0.5, 0.2) },
		{ Vector3.new(d * 0.6, d * 0.78, d * 0.62), CFrame.new(d * 0.12, d * 0.05, -d * 0.1) * CFrame.Angles(0.9, 0.2, 0.7) },
		{ Vector3.new(d * 0.7, d * 0.5, d * 0.66), CFrame.new(-d * 0.1, -d * 0.08, d * 0.12) * CFrame.Angles(0.2, 1.1, 0.5) },
	}
	for i, r in ipairs(recipe) do
		local part = Instance.new("Part")
		part.Name = "Rock" .. i
		part.Size = r[1]
		part.CFrame = r[2]
		part.Material = Enum.Material.Slate
		part.Color = HazardLook.Colors.Rock:Lerp(Color3.new(0, 0, 0), 0.06 * i)
		still(part)
		part.CastShadow = true
		part.Parent = model
		if i == 1 then
			model.PrimaryPart = part
		end
	end
	return model
end

-- Dust: the trickle that warns of a rockfall, and the trail a rolling boulder leaves.
function HazardLook.dustEmitter(parent: Instance, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dust"
	e.Texture = HazardLook.Textures.Smoke
	e.Rate = 0
	e.Lifetime = NumberRange.new(2.2, 3.6)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, 0.8, 0)
	e.Drag = 0.8
	e.Size = sequence({ { 0, size * 0.5 }, { 1, size * 1.7, size * 0.2 } })
	e.Transparency = sequence({ { 0, 1 }, { 0.15, 0.55 }, { 1, 1 } })
	e.Color = ColorSequence.new(HazardLook.Colors.Dust)
	e.LightInfluence = 1
	e.LightEmission = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Parent = parent
	return e
end

-- Pebbles: small grey squares hopping down the chute during the warning.
function HazardLook.pebbleEmitter(parent: Instance): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Pebbles"
	e.Texture = HazardLook.Textures.Square
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.8, 1.5)
	e.Speed = NumberRange.new(8, 18)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Size = sequence({ { 0, 0.3, 0.12 }, { 1, 0.3, 0.12 } })
	e.Color = ColorSequence.new(HazardLook.Colors.Rock)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-400, 400)
	e.LightInfluence = 1
	e.Parent = parent
	return e
end

return HazardLook
