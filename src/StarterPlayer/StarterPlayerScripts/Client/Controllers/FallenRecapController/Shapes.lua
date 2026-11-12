--[[
	Shapes (FallenRecapController helper, client) - point clouds for the Roll Call show.
	A cloud is { n = count, x = {}, y = {}, z = {}, c = {Color3} } in stage units (y up, +z toward the viewer),
	shuffled so any prefix is an even sample of the whole shape.

	  Shapes.sampleBust(snapshot: Model) -> cloud      yields; an avatar bust (head, shoulders, chest, accessories)
	  Shapes.mannequin() -> cloud                       yields once; a neutral bust used until a snapshot is ready
	  Shapes.cachedMannequin() -> cloud?               never yields (nil until sampled)
	  Shapes.text(text, capHeight, density, color, maxPoints?) -> cloud
	  Shapes.line(width, thickness, n, color) -> cloud   a thin tapering rule of points
	  Shapes.compose(parts) -> cloud                    parts = { { cloud, scale, x, y, z, take? } }

	Sampling: the model is copied far outside the world and its visible parts are rebuilt with mesh-accurate collision
	(AssetService:CreateMeshPartAsync; avatar parts usually have Box collision). Rays are cast at it from many (mostly
	frontal) directions and each hit becomes a point coloured by the part it hit, lit by a soft key light. Parts that
	can't be rebuilt are sampled as ellipsoids instead.
]]
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")

local PointFont = require(script.Parent:WaitForChild("PointFont"))

local Shapes = {}

local FAR = Vector3.new(-16000, 3200, -16000) -- sampling happens out here, then the copy is destroyed
local RAYS_PER_FRAME = 260
local BUST_UNITS_PER_STUD = 34 -- an R15 bust (about 2.6 studs) becomes ~90 stage units tall
local NEUTRAL_CLOTH = Color3.fromRGB(176, 188, 210)
local NEUTRAL_ACCESSORY = Color3.fromRGB(214, 222, 236)
local DEFAULT_GREY = Color3.fromRGB(163, 162, 165)
local LIGHT_DIR = Vector3.new(0.35, 0.7, -0.62).Unit -- in model space (front = -Z): top-front-right key light

local rng = Random.new()

local function newCloud()
	return { n = 0, x = {}, y = {}, z = {}, c = {} }
end

local function push(cloud, x: number, y: number, z: number, c: Color3)
	local n = cloud.n + 1
	cloud.n = n
	cloud.x[n], cloud.y[n], cloud.z[n], cloud.c[n] = x, y, z, c
end

local function shuffle(cloud)
	local x, y, z, c = cloud.x, cloud.y, cloud.z, cloud.c
	for i = cloud.n, 2, -1 do
		local j = rng:NextInteger(1, i)
		x[i], x[j] = x[j], x[i]
		y[i], y[j] = y[j], y[i]
		z[i], z[j] = z[j], z[i]
		c[i], c[j] = c[j], c[i]
	end
	return cloud
end

local function yieldFrame()
	RunService.Heartbeat:Wait()
end

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- Shade a surface colour by its normal (model space) and lift it toward a holographic glow.
local function shade(base: Color3, normal: Vector3): Color3
	local lambert = math.max(0, normal:Dot(LIGHT_DIR))
	local k = 0.58 + 0.5 * lambert
	local glow = Color3.new(math.min(1, base.R * k), math.min(1, base.G * k), math.min(1, base.B * k))
	-- very dark colours vanish against the night sky: keep a floor of brightness
	local lum = luminance(glow)
	if lum < 0.22 then
		glow = glow:Lerp(Color3.fromRGB(150, 160, 185), (0.22 - lum) / 0.22 * 0.6)
	end
	return glow:Lerp(Color3.fromRGB(235, 240, 255), 0.12)
end

------------------------------------------------------------------------------------------------------------------------
-- Model sampling
------------------------------------------------------------------------------------------------------------------------

local TORSO_PARTS = {
	UpperTorso = true, LowerTorso = true, LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true,
	RightLowerArm = true, Torso = true, ["Left Arm"] = true, ["Right Arm"] = true,
}

-- True when raycasts against this part would return a shape that doesn't match what you see.
local function isProxy(part: BasePart): boolean
	if part:IsA("MeshPart") then
		return part.CollisionFidelity == Enum.CollisionFidelity.Box
	end
	return part:FindFirstChildOfClass("SpecialMesh") ~= nil or part:FindFirstChildOfClass("FileMesh") ~= nil
end

local function partColor(part: BasePart, hasShirt: boolean, isAccessory: boolean): Color3
	if isAccessory then
		local textured = part:GetAttribute("_textured") == true
		if part:IsA("MeshPart") then
			textured = textured or part.TextureID ~= ""
		else
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			textured = mesh ~= nil and mesh.TextureId ~= ""
		end
		if part:FindFirstChildOfClass("SurfaceAppearance") then
			textured = true
		end
		local c = part.Color
		local isDefault = math.abs(c.R - DEFAULT_GREY.R) < 0.02 and math.abs(c.G - DEFAULT_GREY.G) < 0.02
		if textured or isDefault then
			return NEUTRAL_ACCESSORY
		end
		return c
	end
	if hasShirt and TORSO_PARTS[part.Name] then
		return NEUTRAL_CLOTH
	end
	return part.Color
end

-- A runtime copy of `part` whose collision follows its mesh, so rays hit what you see (avatar parts usually have
-- Box collision). nil when the part has no mesh to load or loading fails.
local function meshCopy(part: BasePart, fidelity: Enum.CollisionFidelity): MeshPart?
	local meshId, scale, offset = nil, Vector3.one, Vector3.zero
	if part:IsA("MeshPart") then
		meshId = part.MeshId
	else
		local special = part:FindFirstChildOfClass("SpecialMesh")
		if special and special.MeshType == Enum.MeshType.FileMesh then
			meshId, scale, offset = special.MeshId, special.Scale, special.Offset
		end
	end
	if type(meshId) ~= "string" or meshId == "" then
		return nil
	end
	local ok, made = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), { CollisionFidelity = fidelity })
	end)
	if not ok or not made then
		return nil
	end
	local mp = made :: MeshPart
	if part:IsA("MeshPart") then
		mp.Size = part.Size
		mp.CFrame = part.CFrame
	else
		mp.Size = mp.Size * scale -- a SpecialMesh draws at its native size times Scale, whatever the part's size
		mp.CFrame = part.CFrame * CFrame.new(offset)
	end
	mp.Name = part.Name
	mp.Color = part.Color
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanTouch = false
	mp.CanQuery = true
	mp.CastShadow = false
	return mp
end

-- Sample `model` (a character or any model) into a cloud in model-root space (studs), keeping points with
-- y >= minY. Options: rays, frontBias (0..1), minY, proxyDensity, precise (rebuild parts with mesh collision),
-- maxRadius (ignore parts farther than this from the reference: avatar parts that were never placed).
local function sampleModel(source: Model, opts)
	local rays = opts.rays or 4200
	local frontBias = opts.frontBias or 0.75
	local wasArchivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = wasArchivable
	if not copy then
		return newCloud()
	end
	local hasShirt = copy:FindFirstChildOfClass("Shirt") ~= nil
	-- strip anything alive; everything anchored, invisible to physics, queryable only where useful
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("Constraint") or d:IsA("JointInstance")
			or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") or d:IsA("Decal") or d:IsA("Tool") then
			d:Destroy()
		end
	end
	local refPart = copy:FindFirstChild("HumanoidRootPart")
	local ref: CFrame = if refPart and refPart:IsA("BasePart") then refPart.CFrame else copy:GetPivot()
	-- move the copy so the reference sits at FAR with no rotation (model space = world - FAR)
	local frame = CFrame.new(FAR)
	copy:PivotTo(frame * ref:Inverse() * copy:GetPivot())
	local minY = opts.minY or -math.huge

	-- rebuild the visible parts in the sampled region with mesh-accurate collision (in parallel; it runs off-thread)
	local candidates = {}
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = false
			local isAccessory = d.Parent ~= nil and d.Parent:IsA("Accessory")
			d:SetAttribute("_acc", isAccessory)
			local invisible = d.Transparency >= 0.95 or d.Name == "HumanoidRootPart"
			local top = d.Position.Y - FAR.Y + d.Size.Magnitude / 2
			-- body parts and accessories only (not a weapon held in a fallback clone of a live character), and not
			-- layered clothing (WrapLayer): its undeformed mesh is a loose shell, the body underneath reads better
			local belongs = (d.Parent == copy or isAccessory) and d:FindFirstChildOfClass("WrapLayer") == nil
			-- nothing far from the body (a part that was never placed)
			local near = opts.maxRadius == nil or (d.Position - FAR).Magnitude < opts.maxRadius
			if not invisible and belongs and near and top >= minY then
				table.insert(candidates, d)
			else
				d.CanQuery = false
			end
		end
	end
	local include = {}
	local proxies = {}
	if opts.precise ~= false then
		local pending = 0
		local replaced = {}
		for _, d in ipairs(candidates) do
			if isProxy(d) or d:IsA("MeshPart") then
				pending += 1
				task.spawn(function()
					local isAccessory = d:GetAttribute("_acc") == true
					local fidelity = if isAccessory then Enum.CollisionFidelity.PreciseConvexDecomposition
						elseif d.Name == "Head" then Enum.CollisionFidelity.Default
						else Enum.CollisionFidelity.Hull
					replaced[d] = meshCopy(d, fidelity) or false
					pending -= 1
				end)
			end
		end
		local waited = 0
		while pending > 0 and waited < 12 do
			waited += RunService.Heartbeat:Wait()
		end
		for _, d in ipairs(candidates) do
			local mp = replaced[d]
			if mp then
				mp:SetAttribute("_acc", d:GetAttribute("_acc") == true)
				local special = d:FindFirstChildOfClass("SpecialMesh")
				if (d:IsA("MeshPart") and d.TextureID ~= "") or (special and special.TextureId ~= "")
					or d:FindFirstChildOfClass("SurfaceAppearance") then
					mp:SetAttribute("_textured", true)
				end
				mp.Parent = d.Parent
				d.CanQuery = false
				d.Transparency = 1
				table.insert(include, mp)
			elseif isProxy(d) then
				d.CanQuery = false
				table.insert(proxies, { part = d, accessory = d:GetAttribute("_acc") == true })
			else
				d.CanQuery = true
				table.insert(include, d)
			end
		end
	else
		for _, d in ipairs(candidates) do
			if isProxy(d) then
				d.CanQuery = false
				table.insert(proxies, { part = d, accessory = d:GetAttribute("_acc") == true })
			else
				d.CanQuery = true
				table.insert(include, d)
			end
		end
	end
	copy.Parent = workspace
	local cloud = newCloud()

	-- bounding box of what we sample (model space): the parts we kept, not the whole model
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local function grow(part: BasePart)
		local half = part.Size.Magnitude / 2
		local p = part.Position - FAR
		lo = lo:Min(p - Vector3.one * half)
		hi = hi:Max(p + Vector3.one * half)
	end
	for _, part in ipairs(include) do
		grow(part)
	end
	for _, entry in ipairs(proxies) do
		grow(entry.part)
	end
	if lo.X == math.huge then
		copy:Destroy()
		return cloud
	end
	lo -= Vector3.new(0.2, 0.2, 0.2)
	hi += Vector3.new(0.2, 0.2, 0.2)
	if minY > lo.Y then
		lo = Vector3.new(lo.X, minY, lo.Z)
	end
	local reach = (hi - lo).Magnitude + 2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.IgnoreWater = true

	if #include > 0 then
		for i = 1, rays do
			-- direction the ray travels (model space). The viewer is in front (-Z), so most rays travel +Z.
			local dir: Vector3
			if rng:NextNumber() < frontBias then
				local yaw = math.rad(rng:NextNumber(-75, 75))
				local pitch = math.rad(rng:NextNumber(-35, 45))
				dir = Vector3.new(math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch))
			else
				dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 0.6), rng:NextNumber(-1, 1))
				if dir.Magnitude < 0.05 then
					dir = Vector3.new(0, 0, 1)
				end
				dir = dir.Unit
			end
			local target = Vector3.new(rng:NextNumber(lo.X, hi.X), rng:NextNumber(lo.Y, hi.Y), rng:NextNumber(lo.Z, hi.Z))
			local origin = target - dir * reach
			local hit = workspace:Raycast(FAR + origin, dir * (reach * 2), params)
			if hit then
				local p = hit.Position - FAR
				if p.Y >= minY then
					local part = hit.Instance :: BasePart
					local base = partColor(part, hasShirt, part:GetAttribute("_acc") == true)
					push(cloud, p.X, p.Y, p.Z, shade(base, hit.Normal))
				end
			end
			if i % RAYS_PER_FRAME == 0 then
				yieldFrame()
				if not copy.Parent then
					break
				end
			end
		end
	end

	-- proxy parts: ellipsoids that fill their box
	local density = opts.proxyDensity or 120 -- points per square stud
	for _, entry in ipairs(proxies) do
		local part = entry.part
		local cf = part.CFrame
		local size = part.Size
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshType == Enum.MeshType.FileMesh then
			size = size * Vector3.new(math.clamp(mesh.Scale.X, 0.5, 1.5), math.clamp(mesh.Scale.Y, 0.5, 1.5), math.clamp(mesh.Scale.Z, 0.5, 1.5))
		end
		local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
		-- Knud Thomsen's approximation of an ellipsoid's surface area
		local p = 1.6075
		local area = 4 * math.pi * (((a * b) ^ p + (a * c) ^ p + (b * c) ^ p) / 3) ^ (1 / p)
		local count = math.clamp(math.floor(area * density), 20, 1400)
		local base = partColor(part, hasShirt, entry.accessory)
		for _ = 1, count do
			-- uniform direction, scaled onto the ellipsoid
			local u = rng:NextNumber(-1, 1)
			local th = rng:NextNumber(0, 2 * math.pi)
			local s = math.sqrt(1 - u * u)
			local d = Vector3.new(s * math.cos(th), u, s * math.sin(th))
			local lp = Vector3.new(d.X * a, d.Y * b, d.Z * c)
			local wp = cf:PointToWorldSpace(lp) - FAR
			if wp.Y >= minY then
				local n = cf:VectorToWorldSpace(Vector3.new(d.X / math.max(a, 1e-3), d.Y / math.max(b, 1e-3), d.Z / math.max(c, 1e-3))).Unit
				push(cloud, wp.X, wp.Y, wp.Z, shade(base, n))
			end
		end
	end
	copy:Destroy()
	return cloud
end

-- Model space (studs, front = -Z) -> stage units (front = +Z), so the bust faces the viewer.
local function toStage(cloud, scale: number, yOrigin: number)
	local out = newCloud()
	for i = 1, cloud.n do
		push(out, -cloud.x[i] * scale, (cloud.y[i] - yOrigin) * scale, -cloud.z[i] * scale, cloud.c[i])
	end
	return out
end

-- Recentre a cloud horizontally on x = 0, z = 0.
local function centre(cloud)
	if cloud.n == 0 then
		return cloud
	end
	local sx, sz = 0, 0
	local minX, maxX = math.huge, -math.huge
	for i = 1, cloud.n do
		minX = math.min(minX, cloud.x[i])
		maxX = math.max(maxX, cloud.x[i])
		sz += cloud.z[i]
	end
	sx = (minX + maxX) / 2
	sz /= cloud.n
	for i = 1, cloud.n do
		cloud.x[i] -= sx
		cloud.z[i] -= sz
	end
	return cloud
end

local function bounds(cloud)
	local minY, maxY, minX, maxX = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, cloud.n do
		local x, y = cloud.x[i], cloud.y[i]
		if y < minY then minY = y end
		if y > maxY then maxY = y end
		if x < minX then minX = x end
		if x > maxX then maxX = x end
	end
	return minX, maxX, minY, maxY
end
Shapes.bounds = bounds

--[[
	An avatar bust from a snapshot model. Stage units: the neck sits at y = 0, the chest is cropped ~1 stud below it.
	cloud.top / cloud.bottom / cloud.width are its extents.
]]
function Shapes.sampleBust(snapshot: Model)
	local root = snapshot:FindFirstChild("HumanoidRootPart")
	local torso = snapshot:FindFirstChild("UpperTorso") or snapshot:FindFirstChild("Torso")
	local head = snapshot:FindFirstChild("Head")
	if not (torso and torso:IsA("BasePart")) then
		return nil
	end
	local ref = if root and root:IsA("BasePart") then root.CFrame else snapshot:GetPivot()
	local torsoLocal = ref:PointToObjectSpace(torso.Position)
	local neckY = torsoLocal.Y + torso.Size.Y / 2
	if head and head:IsA("BasePart") then
		neckY = ref:PointToObjectSpace(head.Position).Y - head.Size.Y / 2
	end
	local minY = torsoLocal.Y - torso.Size.Y * 0.18
	local model = sampleModel(snapshot, { rays = 6400, frontBias = 0.78, minY = minY, proxyDensity = 120, maxRadius = 12 })
	local cloud = toStage(model, BUST_UNITS_PER_STUD, neckY)
	centre(cloud)
	shuffle(cloud)
	local minX, maxX, minYs, maxYs = bounds(cloud)
	cloud.top, cloud.bottom, cloud.width = maxYs, minYs, maxX - minX
	return cloud
end

------------------------------------------------------------------------------------------------------------------------
-- A thin horizontal rule (the line under the day caption)
------------------------------------------------------------------------------------------------------------------------

-- n points along a rule `width` stage units long centred on (0, 0), tapering at both ends.
function Shapes.line(width: number, thickness: number, n: number, color: Color3)
	local cloud = newCloud()
	for _ = 1, math.max(1, math.floor(n)) do
		local x = (rng:NextNumber() - 0.5) * width
		local taper = 1 - (2 * math.abs(x) / math.max(width, 1e-3)) ^ 4
		if rng:NextNumber() < taper then
			local k = 0.78 + rng:NextNumber() * 0.22
			push(cloud, x, (rng:NextNumber() - 0.5) * thickness, (rng:NextNumber() - 0.5) * thickness,
				Color3.new(color.R * k, color.G * k, color.B * k))
		end
	end
	cloud.width, cloud.top, cloud.bottom = width, thickness / 2, -thickness / 2
	return cloud
end

------------------------------------------------------------------------------------------------------------------------
-- The neutral bust used until a contender's snapshot has been sampled
------------------------------------------------------------------------------------------------------------------------

local mannequinCache = nil
local mannequinBusy = false
function Shapes.mannequin()
	while mannequinBusy do
		yieldFrame()
	end
	if mannequinCache then
		return mannequinCache
	end
	mannequinBusy = true
	local model = Instance.new("Model")
	local tone = Color3.fromRGB(196, 204, 222)
	local function part(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = tone
		p.Anchored = true
		p.Parent = model
		return p
	end
	local root = part("HumanoidRootPart", Enum.PartType.Block, Vector3.new(2, 2, 1), CFrame.new(0, 0, 0))
	root.Transparency = 1
	part("UpperTorso", Enum.PartType.Block, Vector3.new(2, 1.6, 1), CFrame.new(0, 0.6, 0))
	part("Head", Enum.PartType.Ball, Vector3.new(1.25, 1.25, 1.25), CFrame.new(0, 2.05, 0))
	part("Neck", Enum.PartType.Cylinder, Vector3.new(0.5, 0.55, 0.55), CFrame.new(0, 1.45, 0) * CFrame.Angles(0, 0, math.rad(90)))
	part("LeftUpperArm", Enum.PartType.Ball, Vector3.new(0.95, 1.4, 0.95), CFrame.new(-1.3, 0.75, 0))
	part("RightUpperArm", Enum.PartType.Ball, Vector3.new(0.95, 1.4, 0.95), CFrame.new(1.3, 0.75, 0))
	local ok, raw = pcall(sampleModel, model, { rays = 3800, frontBias = 0.8, minY = 0.2 })
	model:Destroy()
	mannequinBusy = false
	if not ok then
		mannequinCache = newCloud()
		return mannequinCache
	end
	local cloud = toStage(raw, BUST_UNITS_PER_STUD, 1.42)
	centre(cloud)
	shuffle(cloud)
	local minX, maxX, minY, maxY = bounds(cloud)
	cloud.top, cloud.bottom, cloud.width = maxY, minY, maxX - minX
	mannequinCache = cloud
	return cloud
end

------------------------------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------------------------------

-- Points inside the glyphs of `text` (PointFont), centred on (0, 0). capHeight in stage units; density = fraction of
-- glyph cells that get a point (each jittered inside its cell).
function Shapes.text(text: string, capHeight: number, density: number, color: Color3, maxPoints: number?)
	local xs, ys, width, height = PointFont.cells(text)
	local cloud = newCloud()
	local count = #xs
	if count == 0 then
		cloud.width, cloud.top, cloud.bottom = 0, 0, 0
		return cloud
	end
	local cell = capHeight / PointFont.CapRows
	local want = math.floor(count * density)
	if maxPoints then
		want = math.min(want, maxPoints)
	end
	want = math.max(want, math.min(count, 24))
	local order = table.create(count)
	for i = 1, count do
		order[i] = i
	end
	for i = count, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for k = 1, math.min(want, count) do
		local i = order[k]
		local jx = (rng:NextNumber() - 0.5) * cell
		local jy = (rng:NextNumber() - 0.5) * cell
		local jz = (rng:NextNumber() - 0.5) * capHeight * 0.12
		local shadeK = 0.86 + rng:NextNumber() * 0.14
		push(cloud, xs[i] * capHeight + jx, ys[i] * capHeight + jy, jz,
			Color3.new(color.R * shadeK, color.G * shadeK, color.B * shadeK))
	end
	cloud.width = width * capHeight
	cloud.top = height * capHeight / 2
	cloud.bottom = -height * capHeight / 2
	return cloud
end

------------------------------------------------------------------------------------------------------------------------
-- Composition
------------------------------------------------------------------------------------------------------------------------

--[[
	Merge clouds into one shuffled cloud. parts = { { cloud = c, scale = s, x = dx, y = dy, z = dz?, take = n? } }
	`take` points are used from each (default: all). The merged cloud is shuffled.
]]
function Shapes.compose(parts)
	local out = newCloud()
	for _, p in ipairs(parts) do
		local cloud = p.cloud
		if cloud and cloud.n > 0 then
			local take = math.min(p.take or cloud.n, cloud.n)
			local s = p.scale or 1
			local dx, dy, dz = p.x or 0, p.y or 0, p.z or 0
			for i = 1, take do
				push(out, cloud.x[i] * s + dx, cloud.y[i] * s + dy, cloud.z[i] * s + dz, cloud.c[i])
			end
		end
	end
	return shuffle(out)
end

-- Non-yielding: the cached neutral bust, or nil while it is still being sampled.
function Shapes.cachedMannequin()
	return mannequinCache
end

Shapes.newCloud = newCloud
Shapes.shuffle = shuffle

return Shapes
