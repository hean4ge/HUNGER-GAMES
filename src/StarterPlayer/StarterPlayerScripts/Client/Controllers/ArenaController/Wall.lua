--[[
	ArenaController.Wall - how the border wall looks (client-local parts under workspace.Arena.Border).
	Owner, 18 Nov 2026: "change the colour of the world border to be hollow blue". The wall is a see-through barrier in
	a clear, cool blue (Config.Border.WallColor / WallLineColor): an outline, not a sheet.

	From any distance, the outline. One of each under every panel of the ring, laid along the ground from corner to
	corner (Shared.ArenaLayout.heightAt; the water's surface over the lake):
	  BorderLine    a bright line on the ground
	  BorderRail    a thinner line RailHeight studs above it (over the undergrowth and the low trees)
	  BorderPost    a thin post from the line to the rail at a corner, every PostSpacing studs or so
	All three keep about the same thickness on screen (thicker the farther they are), so the ring is a few pixels of
	line wherever it is seen from and covers no scenery: the valley and the sky keep their own colours. (The orange
	wall before this had a sheet and a 44-stud skirt of light; both dyed whatever was behind them.)

	Close to it, where it can hurt you within seconds:
	  BorderPanel   the sheet: almost empty (SheetNear) within SheetFadeNear studs of the eye, gone by SheetFadeFar
	  the lattice   LatticePost / LatticeBar: thin posts on the ring every 9 to 17 studs and thin bars between them that
	                rise slowly and fade out as they climb, only within LatticeFar studs of the eye and strongest at
	                LatticeNear. The posts stand at fixed bearings (they do not slide along as you walk), and the bars
	                rise faster while the wall moves.
	While the wall moves the outline breathes (Pulse*).

	Cost: Neon parts, no lights, no textures, no particles. The ring is 4 parts a panel (640 on Map 1), laid again only
	when the ring has moved RelayStep studs; the lattice is at most 9 posts and 32 bars (fewer on the Medium and Low
	detail tiers, LocalPlayer attribute DetailTier), moved every frame only while the eye is near the wall.

	API (ArenaController drives it; an Edit-mode preview can too):
	  Wall.build()                                   makes the parts (once)
	  Wall.show(parent) / Wall.hide()
	  Wall.step(dt, center, radius, moving, eye)      every frame while shown
	  Wall.Look                                       the numbers below (read every frame: tune them live)
	  Wall.stats() -> { parts, lattice, nearest }     for tests
	To swap in a mesh later (a Blender lattice tile, once uploads are agreed): Wall.Look.Material and newPart() are the
	one place parts are made.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local BorderCfg = Config.Border

local Wall = {}

local Look = {
	Color = if typeof(BorderCfg.WallColor) == "Color3" then BorderCfg.WallColor else Color3.fromRGB(44, 112, 255),
	LineColor = if typeof(BorderCfg.WallLineColor) == "Color3" then BorderCfg.WallLineColor else Color3.fromRGB(56, 124, 255),
	-- Neon is not lit by the scene, so the outline reads the same at noon and at midnight
	Material = Enum.Material.Neon,
	Thickness = 0.3, -- studs, through the wall
	-- the sheet
	-- (0.92 out to 56 studs, seen in Edit at 10 studs, still dyed the trees behind it dark blue)
	SheetNear = 0.965, -- transparency of the sheet at the eye: you see everything through it
	SheetFadeNear = 6, -- studs (flat) from the eye to the nearest point of a panel: the full SheetNear
	SheetFadeFar = 34, -- no sheet at all from here on
	-- the ground line: half its height per stud of distance (about 0.43 degrees), within Min..Max
	LineTransparency = 0.2,
	LineAngle = 0.0055,
	LineMin = 0.35,
	LineMax = 14,
	-- the rail
	RailHeight = 44,
	RailTransparency = 0.45,
	RailAngle = 0.0026,
	RailMin = 0.3,
	RailMax = 6,
	-- the corner posts
	PostTransparency = 0.55,
	PostAngle = 0.0024,
	PostMin = 0.25,
	PostMax = 5,
	PostSpacing = 28, -- a post at every corner whose neighbours are at least this far apart (every 2nd, 4th... otherwise)
	PostNear = 40, -- nearer than this the corner posts fade out: the lattice's own posts stand there
	-- the lattice
	LatticeSpacing = 9, -- posts at least this far apart (and under twice it)
	LatticeNear = 18, -- studs from the eye: full strength
	LatticeFar = 96, -- none from here on
	LatticeHeight = 40, -- the bars rise through this band above the ground and fade out toward its top
	LatticeBars = 4, -- bars in the band at a time
	LatticeRise = 1.1, -- studs a second ...
	LatticeRiseMoving = 3.2, -- ... and while the wall moves
	LatticeBarTransparency = 0.3, -- a bar at its strongest
	LatticePostTransparency = 0.5,
	LatticeThickness = 0.22,
	-- while the wall moves
	PulseSpeed = 2.6,
	PulseSheet = -0.035, -- added to the sheet at the top of the pulse (a little more solid)
	PulseRail = -0.2, -- and to the rail and the posts (brighter)
	-- housekeeping
	RelayStep = 0.12, -- studs the ring must move before its parts are laid again (about 20 times a second at full speed)
	GroundPerFrame = 4, -- corners whose ground height is read again each frame (8 while the wall moves)
	Below = 110, -- studs the sheet reaches below the border's centre (lake beds, ravines)
}
Wall.Look = Look

local PANEL_COUNT = math.clamp(math.floor(BorderCfg.WallPanels or 96), 24, 256)
local WALL_HEIGHT = BorderCfg.WallHeight or 520
local FINE = PANEL_COUNT * 8 -- the bearings a lattice post can stand at
local MAX_HALF = 4 -- lattice posts on each side of the eye, at most
local MAX_BARS = 4
local SURFACE_CAST_TOP = 1400 -- above the highest terrain (1,143), as ArenaLayout casts
local SURFACE_CAST_DOWN = Vector3.new(0, -1600, 0)
local TWO_PI = 2 * math.pi

local folder: Folder? = nil
local latticeFolder: Folder? = nil
local shown = false

-- the ring: panel i runs from corner i to corner i + 1
local panels: { BasePart } = {}
local panelCF: { CFrame } = {}
local lines: { BasePart } = {}
local lineCF: { CFrame } = {}
local lineH: { number } = {}
local rails: { BasePart } = {}
local railCF: { CFrame } = {}
local railH: { number } = {}
local posts: { BasePart } = {}
local postCF: { CFrame } = {}
local postW: { number } = {}
local cornerX: { number } = {}
local cornerZ: { number } = {}
local cornerY: { number } = {} -- the ground (or the water) under corner i
local runLength: { number } = {}
local cornerNext = 1
local groundDirty = true
local laidCenter: Vector3? = nil
local laidRadius = -1
local panelWidth = 0
local postStep = 1
local surfaceParams: RaycastParams? = nil

-- the lattice
local latPosts: { BasePart } = {}
local latPostCF: { CFrame } = {}
local latBars: { BasePart } = {}
local latBarCF: { CFrame } = {}
local latBarLen: { number } = {}
local slotIndex: { number } = {} -- the fine bearing each lattice post stands at
local slotX: { number } = {}
local slotZ: { number } = {}
local slotY: { number } = {}
local slotRadius: { number } = {}
local slotNext = 1
local latticeOn = false
local latticeHalf = MAX_HALF
local latticeBars = MAX_BARS
local latticePhase = 0
local latticeNearest = -1 -- the fine bearing of the middle post

local pulseTime = 0
local lastLookWrite = 0
local nearestDistance = math.huge

local function newPart(name: string, color: Color3, transparency: number, size: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Look.Material
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.Parent = parent
	return part
end

function Wall.build()
	if folder then
		return
	end
	local ring = Instance.new("Folder")
	ring.Name = "Border"
	local t = Look.Thickness
	for i = 1, PANEL_COUNT do
		panels[i] = newPart("BorderPanel", Look.Color, 1, Vector3.new(4, WALL_HEIGHT, t), ring)
		panelCF[i] = CFrame.identity
		lines[i] = newPart("BorderLine", Look.LineColor, Look.LineTransparency, Vector3.new(4, 2 * Look.LineMin, t), ring)
		lineCF[i] = CFrame.identity
		lineH[i] = Look.LineMin
		rails[i] = newPart("BorderRail", Look.Color, Look.RailTransparency, Vector3.new(4, 2 * Look.RailMin, t), ring)
		railCF[i] = CFrame.identity
		railH[i] = Look.RailMin
		posts[i] = newPart("BorderPost", Look.Color, 1, Vector3.new(2 * Look.PostMin, Look.RailHeight, t), ring)
		postCF[i] = CFrame.identity
		postW[i] = Look.PostMin
		cornerX[i], cornerZ[i], cornerY[i] = 0, 0, ArenaLayout.BaseHeight
		runLength[i] = 4
	end
	local lattice = Instance.new("Folder")
	lattice.Name = "Lattice"
	local lt = Look.LatticeThickness
	for s = 1, 2 * MAX_HALF + 1 do
		latPosts[s] = newPart("LatticePost", Look.Color, 1, Vector3.new(lt, Look.LatticeHeight, lt), lattice)
		latPostCF[s] = CFrame.identity
		slotIndex[s] = -1
		slotX[s], slotZ[s], slotY[s], slotRadius[s] = 0, 0, ArenaLayout.BaseHeight, -1
	end
	for b = 1, 2 * MAX_HALF * MAX_BARS do
		latBars[b] = newPart("LatticeBar", Look.LineColor, 1, Vector3.new(4, lt, lt), lattice)
		latBarCF[b] = CFrame.identity
		latBarLen[b] = 4
	end
	folder = ring
	latticeFolder = lattice
end

-- The ground under a point of the ring. Water counts as ground, so over the lake the line lies on the surface and not
-- on the bed (ArenaLayout.heightAt ignores water); where the terrain has not streamed in the ray finds nothing and
-- heightAt's coarse grid answers (lifted to the lake's level where it lies under it).
local function surfaceAt(x: number, z: number, fallback: number): number
	local params = surfaceParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = false
		params.FilterDescendantsInstances = { workspace.Terrain }
		surfaceParams = params
	end
	local hit = workspace:Raycast(Vector3.new(x, SURFACE_CAST_TOP, z), SURFACE_CAST_DOWN, params)
	if hit then
		return hit.Position.Y
	end
	local heightAt = ArenaLayout.heightAt
	local y = if type(heightAt) == "function" then heightAt(x, z) else nil
	if type(y) ~= "number" then
		return fallback
	end
	local water = tonumber(ArenaLayout.WaterLevel)
	return if water and y < water then water else y
end

-- The ring -------------------------------------------------------------------------------------------------------------

-- Corner i is the left end of panel i: at bearing (i - 1.5) steps, on the circle through the polygon's corners.
local function cornerPoint(center: Vector3, radius: number, i: number): (number, number)
	local a = (i - 1.5) * (TWO_PI / PANEL_COUNT)
	local cornerRadius = radius / math.cos(math.pi / PANEL_COUNT)
	return center.X + math.sin(a) * cornerRadius, center.Z - math.cos(a) * cornerRadius
end

local function readGround(center: Vector3, radius: number, count: number)
	for _ = 1, math.min(count, PANEL_COUNT) do
		local i = cornerNext
		cornerNext = i % PANEL_COUNT + 1
		local x, z = cornerPoint(center, radius, i)
		local y = surfaceAt(x, z, center.Y)
		if math.abs(y - cornerY[i]) > 0.2 then
			cornerY[i] = y
			groundDirty = true
		end
	end
end

-- Panels tangent to the circle at their middle meet at the corners of a regular polygon. Under each: the line and the
-- rail, one straight run from its left corner's ground to its right corner's, standing in the wall's plane; a post at
-- its left corner.
local function layRing(center: Vector3, radius: number)
	local count = PANEL_COUNT
	local t = Look.Thickness
	local width = 2 * radius * math.tan(math.pi / count) + 0.05
	if panelWidth <= 0 or width > panelWidth or (panelWidth - width) > panelWidth * 0.005 then
		panelWidth = width
		local size = Vector3.new(width, WALL_HEIGHT, t)
		for _, panel in ipairs(panels) do
			panel.Size = size
		end
		-- corner posts thin out as the ring closes: every 2nd, 4th ... corner, so they stay PostSpacing apart
		local step = 1
		while width * step < Look.PostSpacing and step < count / 4 do
			step *= 2
		end
		postStep = step
	end
	local y = center.Y - Look.Below + WALL_HEIGHT / 2
	local inwardPoint = Vector3.new(center.X, y, center.Z)
	local stepAngle = TWO_PI / count
	for i = 1, count do
		local a = (i - 1) * stepAngle
		local position = Vector3.new(center.X + math.sin(a) * radius, y, center.Z - math.cos(a) * radius)
		panelCF[i] = CFrame.lookAt(position, inwardPoint) -- width runs along the ring
		cornerX[i], cornerZ[i] = cornerPoint(center, radius, i)
	end
	local railRise = Look.RailHeight
	for i = 1, count do
		local j = i % count + 1
		local px, py, pz = cornerX[i], cornerY[i], cornerZ[i]
		local qx, qy, qz = cornerX[j], cornerY[j], cornerZ[j]
		local run = Vector3.new(qx - px, qy - py, qz - pz)
		local length = math.max(run.Magnitude, 0.01)
		local right = run / length
		local mx, mz = (px + qx) / 2, (pz + qz) / 2
		local inward = Vector3.new(center.X - mx, 0, center.Z - mz).Unit
		local up = inward:Cross(right)
		local cf = CFrame.fromMatrix(Vector3.new(mx, (py + qy) / 2, mz), right, up, inward)
		lineCF[i] = cf
		railCF[i] = cf + Vector3.new(0, railRise, 0)
		if math.abs(length + 0.05 - runLength[i]) > length * 0.005 then
			runLength[i] = length + 0.05
			lines[i].Size = Vector3.new(length + 0.05, 2 * lineH[i], t)
			rails[i].Size = Vector3.new(length + 0.05, 2 * railH[i], t)
		end
		local toCenter = Vector3.new(center.X - px, 0, center.Z - pz).Unit
		postCF[i] = CFrame.lookAt(Vector3.new(px, py + railRise / 2, pz), Vector3.new(px, py + railRise / 2, pz) + toCenter)
	end
	workspace:BulkMoveTo(panels, panelCF, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(lines, lineCF, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(rails, railCF, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(posts, postCF, Enum.BulkMoveMode.FireCFrameChanged)
	laidCenter = center
	laidRadius = radius
	groundDirty = false
end

local function setTransparency(part: BasePart, value: number)
	if value > 0.992 then
		value = 1 -- not drawn at all
	end
	if math.abs(value - part.Transparency) > 0.004 then
		part.Transparency = value
	end
end

-- What each part of the ring shows for where the eye is (about 20 times a second).
local function lookRing(eye: Vector3, moving: boolean, low: boolean)
	local pulse = if moving then 0.5 + 0.5 * math.sin(pulseTime * Look.PulseSpeed) else 0
	local t = Look.Thickness
	local half = panelWidth / 2
	local sheetSpan = math.max(Look.SheetFadeFar - Look.SheetFadeNear, 1)
	local sheet = Look.SheetNear + Look.PulseSheet * pulse
	local railT = math.clamp(Look.RailTransparency + Look.PulseRail * pulse, 0, 1)
	local postT = math.clamp(Look.PostTransparency + Look.PulseRail * pulse, 0, 1)
	local nearest = math.huge
	for i = 1, PANEL_COUNT do
		local cf = panelCF[i]
		local p = cf.Position
		local right = cf.RightVector
		local dx, dz = eye.X - p.X, eye.Z - p.Z
		-- the nearest point of the panel to the eye (flat): a wide panel is "near" wherever along it you stand
		local along = math.clamp(dx * right.X + dz * right.Z, -half, half)
		local nx, nz = dx - right.X * along, dz - right.Z * along
		local distance = math.sqrt(nx * nx + nz * nz)
		if distance < nearest then
			nearest = distance
		end
		local k = math.clamp((distance - Look.SheetFadeNear) / sheetSpan, 0, 1)
		setTransparency(panels[i], sheet + (1 - sheet) * k)
		-- the line and the rail keep about the same height on screen: taller the farther they are
		local middle = math.sqrt(dx * dx + dz * dz)
		local lh = math.clamp(middle * Look.LineAngle, Look.LineMin, Look.LineMax)
		if math.abs(lh - lineH[i]) > lineH[i] * 0.08 then
			lineH[i] = lh
			lines[i].Size = Vector3.new(runLength[i], 2 * lh, t)
		end
		local rh = math.clamp(middle * Look.RailAngle, Look.RailMin, Look.RailMax)
		if math.abs(rh - railH[i]) > railH[i] * 0.08 then
			railH[i] = rh
			rails[i].Size = Vector3.new(runLength[i], 2 * rh, t)
		end
		setTransparency(rails[i], railT)
		-- the post at this panel's left corner
		local post = posts[i]
		if low or (i - 1) % postStep ~= 0 then
			setTransparency(post, 1)
		else
			local cx, cz = eye.X - cornerX[i], eye.Z - cornerZ[i]
			local cd = math.sqrt(cx * cx + cz * cz)
			local fade = math.clamp((cd - Look.PostNear * 0.5) / (Look.PostNear * 0.5), 0, 1)
			setTransparency(post, 1 - (1 - postT) * fade)
			local w = math.clamp(cd * Look.PostAngle, Look.PostMin, Look.PostMax)
			if math.abs(w - postW[i]) > postW[i] * 0.08 then
				postW[i] = w
				post.Size = Vector3.new(2 * w, Look.RailHeight, t)
			end
		end
	end
	nearestDistance = nearest
end

-- The lattice ----------------------------------------------------------------------------------------------------------

local function hideLattice()
	if latticeOn then
		latticeOn = false
		if latticeFolder then
			latticeFolder.Parent = nil
		end
	end
end

local function slotPoint(center: Vector3, radius: number, index: number): (number, number)
	local a = index * (TWO_PI / FINE)
	return center.X + math.sin(a) * radius, center.Z - math.cos(a) * radius
end

local function stepLattice(dt: number, center: Vector3, radius: number, moving: boolean, eye: Vector3, writeLook: boolean)
	local dx, dz = eye.X - center.X, eye.Z - center.Z
	local fromCenter = math.sqrt(dx * dx + dz * dz)
	local far = Look.LatticeFar
	if math.abs(fromCenter - radius) > far or radius < 3 then
		hideLattice()
		return
	end
	if not latticeOn then
		latticeOn = true
		if latticeFolder and folder then
			latticeFolder.Parent = folder
		end
		for s = 1, #slotIndex do
			slotIndex[s] = -1 -- read every post's ground again
		end
	end
	latticePhase += dt * (if moving then Look.LatticeRiseMoving else Look.LatticeRise)
	-- posts stand at fixed bearings: every `step`-th of FINE, the step doubling as the ring closes so that neighbours
	-- stay LatticeSpacing to twice that apart
	local fine = TWO_PI * radius / FINE
	local step = 1
	while fine * step < Look.LatticeSpacing and step < FINE / 4 do
		step *= 2
	end
	local bearing = math.atan2(dx, -dz) -- the eye's own bearing from the centre
	local nearestIndex = math.floor(bearing / (TWO_PI / FINE) / step + 0.5) * step
	if nearestIndex ~= latticeNearest then
		latticeNearest = nearestIndex
		writeLook = true -- every post and bar stands somewhere else now
	end
	local half = latticeHalf
	local slots = 2 * half + 1
	for s = 1, slots do
		local index = nearestIndex + (s - 1 - half) * step
		local x, z = slotPoint(center, radius, index)
		slotX[s], slotZ[s] = x, z
		if slotIndex[s] ~= index or math.abs(slotRadius[s] - radius) > 3 then
			slotIndex[s] = index
			slotRadius[s] = radius
			slotY[s] = surfaceAt(x, z, center.Y)
		end
	end
	-- one post's ground again each frame (the terrain streams in; the ring moves)
	slotNext = slotNext % slots + 1
	slotY[slotNext] = surfaceAt(slotX[slotNext], slotZ[slotNext], center.Y)
	slotRadius[slotNext] = radius

	local near = Look.LatticeNear
	local span = math.max(far - near, 1)
	local height = Look.LatticeHeight
	local thickness = Look.LatticeThickness
	local postAlpha = 1 - Look.LatticePostTransparency
	local barAlpha = 1 - Look.LatticeBarTransparency
	for s = 1, #latPosts do
		local post = latPosts[s]
		if s <= slots then
			local x, y, z = slotX[s], slotY[s], slotZ[s]
			latPostCF[s] = CFrame.new(x, y + height / 2 - 1, z)
			if writeLook then
				local ex, ez = eye.X - x, eye.Z - z
				local strength = 1 - math.clamp((math.sqrt(ex * ex + ez * ez) - near) / span, 0, 1)
				setTransparency(post, 1 - postAlpha * strength)
			end
		elseif writeLook then
			setTransparency(post, 1)
		end
	end
	local bars = latticeBars
	local gap = height / bars
	local b = 0
	for s = 1, 2 * MAX_HALF do
		for m = 1, MAX_BARS do
			b += 1
			local bar = latBars[b]
			if s < slots and m <= bars then
				local h = ((m - 1) * gap + latticePhase) % height
				local px, py, pz = slotX[s], slotY[s] + h, slotZ[s]
				local qx, qy, qz = slotX[s + 1], slotY[s + 1] + h, slotZ[s + 1]
				local run = Vector3.new(qx - px, qy - py, qz - pz)
				local length = math.max(run.Magnitude, 0.01)
				local right = run / length
				local mx, mz = (px + qx) / 2, (pz + qz) / 2
				local inward = Vector3.new(center.X - mx, 0, center.Z - mz).Unit
				latBarCF[b] = CFrame.fromMatrix(Vector3.new(mx, (py + qy) / 2, mz), right, inward:Cross(right), inward)
				if math.abs(length - latBarLen[b]) > length * 0.01 then
					latBarLen[b] = length
					bar.Size = Vector3.new(length, thickness, thickness)
				end
				if writeLook then
					local ex, ez = eye.X - mx, eye.Z - mz
					local strength = 1 - math.clamp((math.sqrt(ex * ex + ez * ez) - near) / span, 0, 1)
					-- a bar comes in at the ground and fades out as it climbs
					local f = h / height
					local climb = math.min(1, f / 0.08) * (1 - f) ^ 1.3
					setTransparency(bar, 1 - barAlpha * strength * climb)
				end
			elseif writeLook then
				setTransparency(bar, 1)
			end
		end
	end
	workspace:BulkMoveTo(latPosts, latPostCF, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(latBars, latBarCF, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Public ---------------------------------------------------------------------------------------------------------------

function Wall.show(parent: Instance)
	Wall.build()
	shown = true
	laidRadius = -1 -- lay it out this frame, and read the ground under every corner
	if folder then
		folder.Parent = parent
	end
end

function Wall.hide()
	shown = false
	hideLattice()
	if folder then
		folder.Parent = nil
	end
end

function Wall.step(dt: number, center: Vector3, radius: number, moving: boolean, eye: Vector3)
	if not shown or not folder then
		return
	end
	radius = math.max(radius, 2)
	if moving then
		pulseTime += dt
	else
		pulseTime = 0
	end
	local fresh = laidRadius < 0
	local moved = fresh or laidCenter ~= center or math.abs(radius - laidRadius) > Look.RelayStep
	readGround(center, radius, if fresh then PANEL_COUNT else Look.GroundPerFrame * (if moving then 2 else 1))
	if moved or groundDirty then
		layRing(center, radius)
	end
	local now = os.clock()
	local writeLook = fresh or now - lastLookWrite >= 1 / 20
	if writeLook then
		lastLookWrite = now
		local tier = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("DetailTier")
		latticeHalf = if tier == "Low" then 2 elseif tier == "Medium" then 3 else MAX_HALF
		latticeBars = if tier == "Low" then 3 else MAX_BARS
		lookRing(eye, moving, tier == "Low")
	end
	stepLattice(dt, center, radius, moving, eye, writeLook)
end

function Wall.stats(): { [string]: any }
	local drawn = 0
	if folder then
		for _, part in ipairs(folder:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				drawn += 1
			end
		end
	end
	return {
		parts = if folder then #folder:GetDescendants() else 0,
		drawn = drawn,
		lattice = latticeOn,
		nearest = nearestDistance,
		postStep = postStep,
		panelWidth = panelWidth,
	}
end

return Wall
