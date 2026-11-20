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

	The honeycomb (owner, 20 Nov 2026: "make the border have opaque slightly transparent blue hexagonal shape"). When a
	hex tile is to hand (ArenaController.Hex: Config.Border.HexImage, or an EditableImage drawn at start), it takes the
	place of the sheet, the lattice and the corner posts: every panel carries a SurfaceGui (unlit, LightInfluence 0)
	with
	  Cells    the tile, repeated: bright blue-white outlines with a soft glow, lightly tinted cells. Fixed to the ring
	           and to world height (a whole number of cells round the ring, rows every 1.5 edges of height), so the
	           cells run on across the panels' seams. Full strength from the ground to HexSolid studs up, fading out
	           by HexBand; strongest within HexNear of the eye, gone by HexFar (fainter, never a tint, far away).
	  Shimmer  the same tile again, shown only in a soft band that climbs from the ground and fades as it rises,
	           its phase sliding along the ring (a slow diagonal wave; faster while the wall moves; none on Low).
	  Glow     a soft blue band on the ground, over the BorderLine: the bright edge where the wall meets the ground.
	Only the panels within HexFar have their SurfaceGui Enabled; the rail fades out where the cells show (from far
	away the ring is still the line and the rail). Without a tile the wall is exactly as before.

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
local Hex = require(script.Parent:WaitForChild("Hex"))

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
	RelayNear = 200, -- studs: panels nearer the eye than this move every RelayStep; the rest every 4th
	RelayStep = 0.12, -- studs the ring must move before its parts are laid again (about 20 times a second at full speed)
	GroundPerFrame = 4, -- corners whose ground height is read again each frame (8 while the wall moves)
	Below = 110, -- studs the sheet reaches below the border's centre (lake beds, ravines)
	-- the honeycomb (owner, 20 Nov: "opaque slightly transparent blue hexagonal shape"); see the header
	HexEdge = 5.5, -- studs in one hexagon edge (a cell is 9.5 wide and 11 tall)
	HexBelow = 6, -- the cells start this far under the ground at the panel's lower corner (hidden by it: no gap on a
	-- slope, or where a panel's corners stand on a shore and its middle over the water)
	HexSolid = 30, -- full strength from the ground up to here ...
	HexBand = 150, -- ... fading out to nothing by here (studs above the ground)
	HexNear = 26, -- studs (flat) from the eye to the nearest point of a panel: full strength
	HexFar = 520, -- none from here on (Medium: 340, Low: 240); from the plates a faint mesh on the nearest stretch
	HexCurve = 1.1, -- strength = (1 - (d - near) / (far - near)) ^ HexCurve
	HexTransparency = 0.04, -- of the cells at full strength (the tile's own alpha makes them see-through)
	HexBrightness = 1.15, -- the SurfaceGui's light (unlit: the same at noon and at midnight)
	-- the shimmer: a soft band of brighter cells rising from the ground and fading as it climbs, its phase sliding
	-- along the ring so it reads as a slow diagonal wave
	ShimmerAlpha = 0.6,
	ShimmerFrom = 0.3, -- no shimmer on panels weaker than this (far away: nobody sees it, and it costs a layer)
	ShimmerWidth = 9, -- studs, half the band's height
	ShimmerRise = 110, -- studs it climbs before it starts again
	ShimmerPeriod = 6.5, -- seconds to climb ...
	ShimmerPeriodMoving = 2.6, -- ... and while the wall moves
	ShimmerSlant = 1 / 260, -- climbs per stud along the ring (the wave's slant)
	-- the brighter edge on the ground, inside each panel (over the BorderLine)
	GlowHeight = 7,
	GlowTransparency = 0.25, -- at the ground, at full strength
	HexLayoutsPerLook = 6, -- panels whose cells are laid again per look (20 a second) while the ring closes
	RailFrom = 0.5, -- with the honeycomb on, the rail and the corner posts show only from this share of HexFar out ...
	RailFull = 0.8, -- ... at full strength from this share: the honeycomb is the wall where it shows
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
local PANEL_OVERLAP = 0.05 -- studs each panel is wider than its chord (no gaps at the corners)
local RELAY_SPLIT = 4 -- while the ring moves, a far panel is laid again every 4th time

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

-- the honeycomb: per panel a SurfaceGui with the cells, the shimmer and the ground glow
local hexOn = false -- a tile was found (Hex.content); otherwise the old lattice
local hexSource = "none"
local hexGuis: { SurfaceGui } = {}
local hexCells: { ImageLabel } = {}
local hexShimmer: { ImageLabel } = {}
local hexShimmerGrad: { UIGradient } = {}
local hexCellsGrad: { UIGradient } = {}
local hexGlow: { Frame } = {}
local hexClip: { Frame } = {}
local hexEnabled: { boolean } = {}
local hexStrength: { number } = {}
local hexDirty: { boolean } = {}
local hexKey: { number } = {} -- the ground the cells' fade was last laid for
local hexBottom: { number } = {} -- world height of the cells' label (bottom, top)
local hexTop: { number } = {}
local hexFace = Enum.NormalId.Front -- Front faces the centre; Back while the eye is outside the ring
local hexTileW = 1 -- studs, fitted so a whole number of tiles goes round the ring
local hexEnabledCount = 0
local hexCursor = 1 -- the next panel lookRing looks at to lay again
local nearPanel: { boolean } = {} -- within Look.RelayNear of the eye (lookRing): laid every RelayStep while moving
local relayTake: { boolean } = {}
local shimmerTime = 0
-- which way the canvas runs along the ring on the Front face (+1: the same way as the panels are numbered)
local U_SIGN = 1
local layoutHex: (number) -> () -- below, with the honeycomb

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

local function newImage(name: string, image: any, parent: Instance): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	if type(image) == "string" then
		label.Image = image
	else
		label.ImageContent = image
	end
	label.ScaleType = Enum.ScaleType.Tile
	label.ResampleMode = Enum.ResamplerMode.Default
	label.ImageTransparency = 1
	label.Parent = parent
	return label
end

-- One SurfaceGui per panel, made once; only the panels near the eye are Enabled (lookRing).
local function buildHex()
	local image, source = Hex.content(Look.LineColor, Look.Color)
	hexSource = source
	if not image then
		return
	end
	for i = 1, PANEL_COUNT do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "BorderHex"
		gui.Enabled = false
		gui.Face = hexFace
		gui.LightInfluence = 0
		gui.Brightness = Look.HexBrightness
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		-- everything inside is laid out by scale, but GUI layout rounds to whole canvas pixels: at 40 a pixel is
		-- 0.025 studs, so the panels' cells meet without a gap (at 2 the seams showed)
		gui.PixelsPerStud = 40
		gui.ClipsDescendants = true
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		-- the panel's own chord: neighbouring panels overlap by PANEL_OVERLAP, and two layers of cells there would
		-- draw a thin bright seam
		local clip = Instance.new("Frame")
		clip.Name = "Clip"
		clip.BackgroundTransparency = 1
		clip.BorderSizePixel = 0
		clip.ClipsDescendants = true
		clip.Parent = gui
		hexClip[i] = clip
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.BorderSizePixel = 0
		glow.BackgroundColor3 = Look.LineColor
		glow.BackgroundTransparency = 1
		glow.ZIndex = 1
		local glowGrad = Instance.new("UIGradient")
		glowGrad.Rotation = 90 -- top to bottom: clear at the top, solid on the ground
		glowGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 0.82),
			NumberSequenceKeypoint.new(0.9, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		glowGrad.Parent = glow
		glow.Parent = clip
		local cells = newImage("Cells", image, clip)
		cells.ZIndex = 2
		local cellsGrad = Instance.new("UIGradient")
		cellsGrad.Rotation = 90
		cellsGrad.Parent = cells
		local shimmer = newImage("Shimmer", image, clip)
		shimmer.ZIndex = 3
		local shimmerGrad = Instance.new("UIGradient")
		shimmerGrad.Rotation = 90
		shimmerGrad.Parent = shimmer
		gui.Parent = panels[i]
		hexGuis[i] = gui
		hexCells[i] = cells
		hexCellsGrad[i] = cellsGrad
		hexShimmer[i] = shimmer
		hexShimmerGrad[i] = shimmerGrad
		hexGlow[i] = glow
		hexEnabled[i] = false
		hexStrength[i] = 0
		hexDirty[i] = true
		hexKey[i] = math.huge
		hexBottom[i], hexTop[i] = 0, 1
	end
	hexOn = true
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
	local ok, err = pcall(buildHex)
	if not ok then
		hexOn = false
		warn("[ArenaController.Wall] honeycomb off: " .. tostring(err))
	end
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
local relayPanels: { BasePart } = {}
local relayPanelCF: { CFrame } = {}
local relayLines: { BasePart } = {}
local relayLineCF: { CFrame } = {}
local relayRails: { BasePart } = {}
local relayRailCF: { CFrame } = {}
local relayPhase = 0

-- full: every panel. Otherwise (while the ring moves) the panels near the eye (nearPanel, from lookRing) and every
-- RELAY_SPLIT-th of the rest in turn: far away a step of a few tenths of a stud is a fraction of a pixel, and laying
-- all 640 parts every RelayStep cost about 1.4 ms a frame on a PC while the ring closed.
local function layRing(center: Vector3, radius: number, full: boolean)
	local count = PANEL_COUNT
	relayPhase = (relayPhase + 1) % RELAY_SPLIT
	table.clear(relayPanels)
	table.clear(relayPanelCF)
	table.clear(relayLines)
	table.clear(relayLineCF)
	table.clear(relayRails)
	table.clear(relayRailCF)
	local t = Look.Thickness
	local width = 2 * radius * math.tan(math.pi / count) + PANEL_OVERLAP
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
		cornerX[i], cornerZ[i] = cornerPoint(center, radius, i)
		relayTake[i] = full or nearPanel[i] or i % RELAY_SPLIT == relayPhase
		if relayTake[i] then
			local a = (i - 1) * stepAngle
			local position = Vector3.new(center.X + math.sin(a) * radius, y, center.Z - math.cos(a) * radius)
			local cf = CFrame.lookAt(position, inwardPoint) -- width runs along the ring
			panelCF[i] = cf
			table.insert(relayPanels, panels[i])
			table.insert(relayPanelCF, cf)
		end
	end
	local railRise = Look.RailHeight
	for i = 1, count do
		if not relayTake[i] then
			continue
		end
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
		table.insert(relayLines, lines[i])
		table.insert(relayLineCF, cf)
		table.insert(relayRails, rails[i])
		table.insert(relayRailCF, railCF[i])
		if math.abs(length + 0.05 - runLength[i]) > length * 0.005 then
			runLength[i] = length + 0.05
			lines[i].Size = Vector3.new(length + 0.05, 2 * lineH[i], t)
			rails[i].Size = Vector3.new(length + 0.05, 2 * railH[i], t)
		end
		local toCenter = Vector3.new(center.X - px, 0, center.Z - pz).Unit
		postCF[i] = CFrame.lookAt(Vector3.new(px, py + railRise / 2, pz), Vector3.new(px, py + railRise / 2, pz) + toCenter)
	end
	workspace:BulkMoveTo(relayPanels, relayPanelCF, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(relayLines, relayLineCF, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(relayRails, relayRailCF, Enum.BulkMoveMode.FireCFrameChanged)
	if not hexOn then -- with the honeycomb on the posts never show
		workspace:BulkMoveTo(posts, postCF, Enum.BulkMoveMode.FireCFrameChanged)
	end
	laidCenter = center
	laidRadius = radius
	groundDirty = false
	if hexOn then
		-- a whole number of tiles round the ring
		local around = count * (panelWidth - PANEL_OVERLAP)
		local tile = math.sqrt(3) * Look.HexEdge
		hexTileW = around / math.max(1, math.floor(around / tile + 0.5))
		-- laid again by lookRing, a few panels at a time (HexLayoutsPerLook): while the ring closes it is laid out
		-- here every RelayStep, but its cells only drift by thousandths of a stud between two of those
		for i = 1, count do
			if relayTake[i] then
				hexDirty[i] = true
			end
		end
	end
end

-- The honeycomb ---------------------------------------------------------------------------------------------------------

-- Lays panel i's cells, shimmer and glow on its canvas. The pattern is fixed to the ring and to world height: a cell
-- column every hexTileW studs of the ring (a whole number of them round it, so no seam), a cell row every 1.5 edges of
-- world height, whatever the panel's own ground. The cells' label spans whole tiles from under the ground to above the
-- fade, so its own left and top edges fall on tile edges.
function layoutHex(i: number)
	hexDirty[i] = false
	local width = math.max(panelWidth - PANEL_OVERLAP, 0.01) -- the chord; the clip frame spans just that
	hexClip[i].Position = UDim2.fromScale(PANEL_OVERLAP / 2 / panelWidth, 0)
	hexClip[i].Size = UDim2.fromScale(width / panelWidth, 1)
	local height = WALL_HEIGHT
	local top = panelCF[i].Position.Y + height / 2
	local tileW = hexTileW
	local tileH = 3 * Look.HexEdge
	local j = i % PANEL_COUNT + 1
	local ground = math.min(cornerY[i], cornerY[j])
	-- horizontal: the arc (along the ring, in the canvas's own direction) at the canvas's left edge
	local sign = if hexFace == Enum.NormalId.Front then U_SIGN else -U_SIGN
	local left = sign * (i - 1) * width - width / 2
	local l0 = math.floor(left / tileW) * tileW
	local r0 = math.ceil((left + width) / tileW) * tileW
	-- vertical: world heights
	local b0 = math.floor((ground - Look.HexBelow - 2) / tileH) * tileH
	local t0 = math.ceil((ground + Look.HexBand) / tileH) * tileH
	local spanX, spanY = math.max(r0 - l0, 0.01), math.max(t0 - b0, 0.01)
	local cells = hexCells[i]
	local shimmer = hexShimmer[i]
	local position = UDim2.fromScale((l0 - left) / width, (top - t0) / height)
	local size = UDim2.fromScale(spanX / width, spanY / height)
	local tile = UDim2.fromScale(tileW / spanX, tileH / spanY)
	cells.Position, cells.Size, cells.TileSize = position, size, tile
	shimmer.Position, shimmer.Size, shimmer.TileSize = position, size, tile
	hexBottom[i], hexTop[i] = b0, t0
	local glowH = Look.GlowHeight
	hexGlow[i].Position = UDim2.fromScale(0, (top - ground - glowH) / height)
	hexGlow[i].Size = UDim2.fromScale(1, (glowH + 1) / height)
	-- the fade only changes with the ground under the panel
	local key = math.floor(ground * 4 + 0.5) + b0 * 1000
	if key == hexKey[i] then
		return
	end
	hexKey[i] = key
	local function at(y: number): number -- 0 at the label's top, 1 at its bottom
		return math.clamp((t0 - y) / spanY, 0, 1)
	end
	local solid, band = Look.HexSolid, Look.HexBand
	local raw = {
		{ 0, 1 },
		{ at(ground + band), 1 },
		{ at(ground + solid + (band - solid) * 0.55), 0.8 },
		{ at(ground + solid + (band - solid) * 0.22), 0.4 },
		{ at(ground + solid), 0 },
		{ at(ground - Look.HexBelow), 0 },
		{ at(ground - Look.HexBelow - 1.5), 1 },
		{ 1, 1 },
	}
	local points = {}
	local last = -1
	for _, p in ipairs(raw) do
		local t = p[1]
		if t > last + 0.0005 and t <= 1 then
			table.insert(points, NumberSequenceKeypoint.new(t, p[2]))
			last = t
		end
	end
	if points[#points].Time < 1 then
		table.insert(points, NumberSequenceKeypoint.new(1, 1))
	end
	hexCellsGrad[i].Transparency = NumberSequence.new(points)
	-- the shimmer's band: a soft window around 0.5, slid up and down by Offset (stepHex)
	local half = math.clamp(Look.ShimmerWidth / spanY, 0.002, 0.2)
	hexShimmerGrad[i].Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - half, 1),
		NumberSequenceKeypoint.new(0.5 - half * 0.3, 0.35),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.5 + half * 0.3, 0.35),
		NumberSequenceKeypoint.new(0.5 + half, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Every frame, on the panels that show: the shimmer's band climbs from the ground and fades as it rises.
local function stepHex(dt: number, moving: boolean, low: boolean)
	if hexEnabledCount == 0 then
		return
	end
	shimmerTime += dt / (if moving then Look.ShimmerPeriodMoving else Look.ShimmerPeriod)
	local rise = Look.ShimmerRise
	local slant = Look.ShimmerSlant
	local width = panelWidth
	for i = 1, PANEL_COUNT do
		if hexEnabled[i] then
			local shimmer = hexShimmer[i]
			local strength = hexStrength[i]
			if low or strength <= Look.ShimmerFrom then
				if shimmer.ImageTransparency < 1 then
					shimmer.ImageTransparency = 1
				end
			else
				local phase = (shimmerTime + (i - 1) * width * slant) % 1
				local j = i % PANEL_COUNT + 1
				local ground = math.min(cornerY[i], cornerY[j])
				local y = ground + phase * rise
				local spanY = hexTop[i] - hexBottom[i]
				local f = (hexTop[i] - y) / spanY -- 0 top, 1 bottom
				hexShimmerGrad[i].Offset = Vector2.new(0, f - 0.5)
				local fade = math.min(1, phase / 0.06) * (1 - phase) ^ 1.4
				shimmer.ImageTransparency = 1 - Look.ShimmerAlpha * strength * fade
			end
		end
	end
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
local function lookRing(eye: Vector3, moving: boolean, tier: any, layoutAll: boolean)
	local low = tier == "Low"
	local pulse = if moving then 0.5 + 0.5 * math.sin(pulseTime * Look.PulseSpeed) else 0
	-- the honeycomb faces the eye: the centre's side, or the outside while the eye is beyond the ring
	local hexNear, hexSpan, railNear, railSpan = 0, 1, 0, 1
	if hexOn then
		hexNear = Look.HexNear
		local far = if low then math.min(Look.HexFar, 240) elseif tier == "Medium" then math.min(Look.HexFar, 340) else Look.HexFar
		hexSpan = math.max(far - hexNear, 1)
		railNear = far * Look.RailFrom
		railSpan = math.max(far * (Look.RailFull - Look.RailFrom), 1)
		local c = laidCenter
		if c then
			local ox, oz = eye.X - c.X, eye.Z - c.Z
			local face = if ox * ox + oz * oz > laidRadius * laidRadius then Enum.NormalId.Back else Enum.NormalId.Front
			if face ~= hexFace then
				hexFace = face
				for i = 1, PANEL_COUNT do
					hexGuis[i].Face = face
					hexDirty[i] = true
				end
				layoutAll = true -- the cells run the other way on this face: lay every shown panel now
			end
		end
	end
	local count = 0
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
		nearPanel[i] = distance < Look.RelayNear
		if distance < nearest then
			nearest = distance
		end
		if hexOn then
			-- the cells take the sheet's place
			setTransparency(panels[i], 1)
			local strength = (1 - math.clamp((distance - hexNear) / hexSpan, 0, 1)) ^ Look.HexCurve
			local on = strength > 0.012
			local fresh = false
			if on ~= hexEnabled[i] then
				hexEnabled[i] = on
				hexGuis[i].Enabled = on
				fresh = on
				if not on then
					hexStrength[i] = 0
				end
			end
			if on then
				count += 1
				-- a panel that has just come on is laid now; the rest in turn, a few a look (below)
				if hexDirty[i] and (fresh or layoutAll) then
					layoutHex(i)
				end
				if math.abs(strength - hexStrength[i]) > 0.004 then
					hexStrength[i] = strength
					local cellsT = 1 - (1 - Look.HexTransparency) * strength
					local cells = hexCells[i]
					if math.abs(cells.ImageTransparency - cellsT) > 0.003 then
						cells.ImageTransparency = cellsT
					end
					hexGlow[i].BackgroundTransparency = 1 - (1 - Look.GlowTransparency) * math.min(1, strength * 1.3)
				end
			end
		else
			local k = math.clamp((distance - Look.SheetFadeNear) / sheetSpan, 0, 1)
			setTransparency(panels[i], sheet + (1 - sheet) * k)
		end
		-- with the honeycomb on, the rail and the posts (the outline for far away) give way to it close up
		local railFade = if railNear > 0 then math.clamp((distance - railNear) / railSpan, 0, 1) else 1
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
		setTransparency(rails[i], 1 - (1 - railT) * railFade)
		-- the post at this panel's left corner
		local post = posts[i]
		-- with the honeycomb on, no posts: the ring reads as the line and the rail, not a fence
		if low or hexOn or (i - 1) % postStep ~= 0 then
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
	hexEnabledCount = count
	if hexOn and count > 0 and not layoutAll then
		local budget = Look.HexLayoutsPerLook
		for _ = 1, PANEL_COUNT do
			if budget <= 0 then
				break
			end
			local i = hexCursor
			hexCursor = i % PANEL_COUNT + 1
			if hexEnabled[i] and hexDirty[i] then
				layoutHex(i)
				budget -= 1
			end
		end
	end
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
		-- in part while the ring moves; all of it when it is laid afresh or only the ground changed
		layRing(center, radius, fresh or not moved)
	end
	local now = os.clock()
	local writeLook = fresh or now - lastLookWrite >= 1 / 20
	if writeLook then
		lastLookWrite = now
		local tier = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("DetailTier")
		latticeHalf = if tier == "Low" then 2 elseif tier == "Medium" then 3 else MAX_HALF
		latticeBars = if tier == "Low" then 3 else MAX_BARS
		lookRing(eye, moving, tier, fresh)
	end
	if hexOn then
		stepHex(dt, moving, latticeBars < MAX_BARS) -- no shimmer on the Low tier
	else
		stepLattice(dt, center, radius, moving, eye, writeLook)
	end
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
		hex = hexOn,
		hexSource = hexSource,
		hexPanels = hexEnabledCount,
		hexTileW = hexTileW,
	}
end

return Wall
