--[[
	Map1.Scatter - plants the Green Land: conifers, beeches, gorse, heather, boulders, crags, tall grass and
	wildflowers, from the eight Blender masks of the Map 1 data pack (docs/design/Map1Build.md 3.2 and 3.3;
	TwoArenas 9.4; the budgets are ArenaV3 7.5). Edit mode only. The data comes through
	ServerStorage.WorldGen.Map1.Data; the templates are the Models in ServerStorage.WorldAssets.Map1, found by
	their manifest name (Map1.Assets builds them).

	THE RECIPE (the Blender generator's own: scatter_points and scatter in art/blender/map1_green_land.py)
	  A jittered lattice per kind; a lattice point is kept with probability mask x gain. Here the lattice is
	  global and every point belongs to the 80-stud cell that holds its lattice centre; its jitter is reflected
	  back into that cell. Each (cell, kind) has its own Random, seeded from the seed, the kind and the cell, and
	  every candidate draws the same number of values whatever is refused. So a cell's plants depend on nothing
	  but the data and the seed: a window gives exactly the plants a full build puts there, and a build is the
	  same every time.
	  kind         lattice  gain  below y  assets and mix                                  scale       sink
	  Crags        64       0.4   900      M1_Crag_A/B/C 45/35/20                          0.6-1.1     12
	  Conifer      13       1.0   700      M1_Fir_A/B/C 25/25/18, M1_Pine_A/B 17/15        0.82-1.15   0.4
	  Broadleaf    10       1.15  400      M1_Beech_A/B 55/45                              0.8-1.2     0.4
	  Boulders     9        0.5   700      M1_Boulder_A/B/C 50/35/15                       0.7-1.4     0.1
	  Gorse        7        0.7   450      M1_Gorse_A/B                                    0.8-1.4     0.3
	  TallGrass    4.5      0.8   400      M1_TallGrass_A                                  0.8-1.2     0.15
	  Heather      6        0.8   700      M1_Heather_A/B                                  0.8-1.6     0.3
	  Wildflowers  3.6      1.0   200      M1_Wildflowers_A (none past r 1,300)            0.7-1.3     0
	  Yaw is random. The manifests carry no ranges, so the scale ranges are the generator's; a manifest asset
	  with "scale" or "scaleRange" = [lo, hi] overrides its rule's.

	WHERE NOTHING IS PLANTED
	  - the heart's protected disc: nothing inside r 200, thinning in to full density at r 255
	    (Map1_Terrain.json radii.protectedDisc)
	  - every placed landmark of Map1_Layout.json "items", by its manifest bounds turned to its yaw, plus a margin:
	    the platform, the horn, the plinths and rims, the beds, the spiral, the glade, the hedges, the berms, the
	    lone trees. A landmark wider than 120 studs (the peak) is a mass: its bounds are far bigger than the ground
	    it hides. While its mesh is not standing in <parent>.Landmarks an ellipse of 0.85 of its bounds stands in for
	    it; once a ray through the middle of its bounds finds the mesh, rays decide (next line).
	  - under any landmark mesh: when <parent>.Landmarks or .Plinths hold models, a ray from above each plant's spot
	    must reach the ground (it meets only parts that take ray queries: the peak, the hedges, the horn, trunks)
	  - a clearing at each of Map1_Layout.json "sites" (8 studs for trunks and rocks, 4 for small plants)
	  - water and the shore: the cell ring round every wet cell (wider for trees and rocks)
	  - the trails of Map1_Terrain.json: a 6-stud path plus the plant's own body
	  - ground steeper than 46 degrees (crags excepted: they belong on steep ground)
	  - bare ground: the stream bed, cliff rock and the paths' own material (boulders and crags excepted).
	    Limestone is not bare: the heather on the hedge hollow's rocky rim is meant to stand on it.
	  - beyond the play radius (1,800): nothing but conifers, thinned to 0.35 by r 1,860 and to nothing by
	    r 2,100, below y 520. Their trunks collide out to the Boundary (r 1,900); beyond it they are for looks.
	  - no trunk or boulder stands in another, or in a crag; no small plant has its centre in one
	  - opts.keepOut discs, and the loot markers of opts.loot

	CAPS (ArenaV3 7.5)
	  Each kind has a cap inside the play radius (RULES[].cap). When the masks ask for more, the kind is thinned
	  evenly, never cut off part of the way through. Heather is the kind this is for: 15,000.
	  Any 40 x 40 cell: at most 14 trees and 60 plants (a cell is 2 x 2 of them, so the count is exact).
	  stats().budget compares the totals with 90,000 models and 400,000 instances in the place, 30,000 and 130,000
	  in any 1,024-stud disc, 7,000 models in any 300-stud disc.

	WHAT TO EXPECT (S.plan() on 15 November 2026: pack map1_data build 1, seed 50, the peak not yet placed)
	  42,634 models and 112,273 instances (a tree is a Model and two parts, the rest a Model and one, plus 1,748
	  cell folders); 25,545 colliding parts, 50,754 parts casting shadows; planning takes 0.4 s, planting about
	  3,000 models a second.
	  Conifer 24,540 (23,237 inside r 1,800, 660 out to the Boundary, 643 beyond)   Heather 11,734   Gorse 2,846
	  TallGrass 1,004   Wildflowers 892   Boulders 883   Broadleaf 717   Crags 18
	  Heaviest 1,024-stud disc 15,184 models and 40,771 instances; heaviest 300-stud disc 2,247 models.

	WHEN TO RUN IT (Map1Build.md section 5)
	  After the terrain is written (the heights snap to it) and the landmarks are placed (rays then find the peak's
	  mesh; until then its ellipse keeps about the same ground clear). Loot markers: if they exist before the
	  planting pass opts.loot; if they are made after it (the install order), call
	  S.clearAround(markerPositions, 3, { small = true }) so that no gorse or heather hides a marker (Map1.Loot
	  moves its markers off trunks and boulders itself).

	WHAT IT MAKES
	  <parent>.Scatter (a Folder; parent is workspace.Arena unless opts.parent says otherwise)
	    C_<cx>_<cz>      a Folder per 80-stud cell that holds anything (the cell covers x cx*80 .. cx*80+80)
	      M1_Fir_A ...   a Model per plant, a clone of the template, named after it, ModelStreamingMode Atomic
	  Collision and ray queries on trunks, boulders and crags only; shadows from trees, crags and boulders 3 studs
	  or taller; nothing has CanTouch; everything is anchored. Clones carry no attributes (memory, replication).
	  For DetailController the Scatter folder carries DetailClasses = "M1_Fir_A=tree;M1_Heather_A=heath;..."
	  (gorse, boulders and crags are cover and are never hidden, so they are not listed).
	  Seating: the ground height is the data's (bilinear, as Data.heightAt). Trees stand upright on the lowest
	  ground round the trunk; small plants and boulders lie on the slope. Where real terrain is under the point
	  (the install) the height snaps to a terrain raycast when that is within 4 studs of the data.

	EDIT-MODE USE (execute_luau). Studio caches required modules, so require a clone:
	  local S = require(game.ServerStorage.WorldGen.Map1.Scatter:Clone())
	  S.build(opts)      -- plants in the calling thread (yields between cells); returns the stats table
	  S.start(opts)      -- the same on a background thread; returns at once. Watch the parent's attributes
	                     --   ScatterStatus / ScatterProgress; the result lands in its ScatterStats (JSON)
	  S.plan(opts)       -- build with dry = true: the counts for the same options, nothing created (and no
	                     --   attribute written, unless opts.parent names where)
	  S.clear(opts)      -- destroys what build made (the cells of <parent>.Scatter), in batches
	  S.stats(opts)      -- counts what stands in <parent>.Scatter now, by asset and kind, with the budget table
	  S.check(opts)      -- reads the placed models back against the rules above; returns { ok, problems }
	  S.report(stats)    -- stats as text
	  S.clearAround(points, radius, opts)   -- removes the plants within radius of each point (for loot spots found
	                     --   after the planting); opts.small = true removes only the plants that hide a thing
	                     --   without blocking it (gorse, heather, tall grass, flowers) and leaves trees and rocks
	opts (all optional):
	  seed        number; default: the seed in Map1_Terrain.json (50)
	  offset      Vector3 added to every position (a tile at the workbench)
	  window      map studs { minX, maxX, minZ, maxZ }, or grid cells as the terrain writer takes them
	              { col0, col1, row0, row1 }: only plants inside are made
	  parent      the Instance that gets the Scatter folder (default workspace.Arena)
	  kinds       { "Conifer", ... }: only these kinds
	  density     a number, or { Heather = 0.5 }: multiplies the chance of every candidate (of that kind)
	  outer       false: nothing beyond the play radius at all
	  turfFlowers true: the generator's 260 small daisy clumps on the heart's turf (r 55..148), off the beds,
	              the platform and the plinths. Off by default: the heart's disc stays clear.
	  keepOut     { { x =, z =, r = (trunks and rocks), rSmall = (small plants; default r / 2) }, ... }
	  loot        an Instance whose BasePart children are loot markers: 4.5 studs kept clear round a crate marker
	              (attribute Kind == "Crate"), 3 round any other
	  landmarks   Instances to look for covering meshes in (default <parent>.Landmarks and .Plinths), or false
	  snap        false: never raycast the terrain for the height
	  templates   the template container (default ServerStorage.WorldAssets.Map1)
	  standIns    true: a plain stand-in Model for every missing template (tests)
	  data, pack  a loaded Map1.Data table; or the data pack's name (default "map1_data")
	  dry         true: count only
	  collect     true: stats.placements lists every plant as { asset, x, z, scale } (tests)
	  quiet       true: write no status or result attributes
	  keep        true: do not clear the cells that are about to be rebuilt
	  progress    function(done, total, cellName), called about ten times a second
	  slice       seconds of work between two waits (default 0.03)
	Missing templates are skipped softly: the rule shares its plants out over the assets it does have, the stats
	list the names (stats.missing), and a rule with no template at all places nothing.
]]
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local sin, cos, tan, acos, rad = math.sin, math.cos, math.tan, math.acos, math.rad
local clamp = math.clamp
local readu8, readu16, writeu8 = buffer.readu8, buffer.readu16, buffer.writeu8
local PI, TAU, HUGE = math.pi, math.pi * 2, math.huge
local V3 = Vector3.new

local Scatter = {}
Scatter.VERSION = 1
Scatter.MAP = "GreenLand"
Scatter.FOLDER = "Scatter"
Scatter.PACK = "map1_data"
Scatter.TEMPLATES = { "WorldAssets", "Map1" } -- under ServerStorage
Scatter.SEED = 50 -- used when Map1_Terrain.json has no seed
Scatter.CELL = 80 -- studs: one output folder per cell
Scatter.SUB = 40 -- the budget cell (ArenaV3 7.5); CELL must be a whole multiple of it
Scatter.TREES_PER_SUB = 14
Scatter.FLORA_PER_SUB = 60
Scatter.PATH_HALF = 3 -- the trails are a 6-stud path
Scatter.MAX_SLOPE = 46 -- degrees
Scatter.SHADOW_MIN = 3 -- a boulder lower than this (after scale and sink) casts no shadow
Scatter.SNAP_TOLERANCE = 4 -- studs between the data's height and a terrain raycast that still snaps
Scatter.SITE_CLEAR = { solid = 8, small = 4 } -- the clearing at each Layout site
Scatter.ITEM_PAD = { solid = 3, small = 1.5 } -- the margin round a placed landmark's bounds
Scatter.MASS = 120 -- a landmark wider than this is a mass (the peak): see the header
Scatter.MASS_FILL = 0.85
Scatter.PLAY_RADIUS = 1800 -- these three are replaced by Map1_Terrain.json "radii" when it has them
Scatter.BOUNDARY_RADIUS = 1900
Scatter.PROTECTED = { 200, 255 }
Scatter.OUTER = { keep = 0.35, ramp = 60, fadeFrom = 2000, to = 2100, ymax = 520 }
Scatter.TURF = { asset = "M1_Wildflowers_A", count = 260, r0 = 55, r1 = 148, scale = { 0.35, 0.6 }, sink = 0.35 }
Scatter.BUDGET = { models = 90000, instances = 400000, disc1024Models = 30000, disc1024Instances = 130000, disc300Models = 7000 }
-- Material slots (by base material in Map1_Terrain.json) no plant grows on: the stream bed, cliff rock and the paths.
-- Limestone is not in it: the heather of the hedge hollow's rim is meant to stand on it.
Scatter.BARE_BASES = { Salt = true, Sand = true, Rock = true, Ground = true }

-- What each class may do. solid: collides (a tree: its bark only). budget: which 40 x 40 count it adds to.
local CLASS = {
	tree = { solid = true, shadow = true, budget = "tree", steep = true, bare = true, small = false },
	crag = { solid = true, shadow = true, budget = nil, steep = false, bare = false, small = false },
	rock = { solid = true, shadow = true, budget = nil, steep = true, bare = false, small = false },
	bush = { solid = false, shadow = false, budget = "flora", steep = true, bare = true, small = true },
	ground = { solid = false, shadow = false, budget = "flora", steep = true, bare = true, small = true },
	tall = { solid = false, shadow = false, budget = "flora", steep = true, bare = true, small = true },
}
Scatter.CLASS = CLASS

--[[ One rule per mask, in planting order (crags, trees, boulders, then the small plants).
	grid, gain, ymax, rmax   the lattice spacing, the chance multiplier, and the height and radius limits
	assets                   { name, weight } in the generator's mix
	scale, sink, tilt        the size range, studs sunk into the ground, and the random lean (radians, both axes)
	normal                   0 = upright; 1 = lies on the slope; between = partly
	radius                   a tree's trunk radius at scale 1; for the others the body radius when the manifest
	                         has no size
	body                     the share of the asset's smaller footprint side that is its body radius
	shore                    studs kept from the centre of the nearest wet cell
	cap                      the most of this kind inside the play radius
	outer                    also planted, thinned, beyond the play radius (conifers only)
	detail                   DetailController's class; nil = never hidden ]]
Scatter.RULES = {
	{
		kind = "Crags", mask = "Crags", class = "crag", grid = 64, gain = 0.4, ymax = 900,
		assets = { { "M1_Crag_A", 0.45 }, { "M1_Crag_B", 0.35 }, { "M1_Crag_C", 0.20 } },
		scale = { 0.6, 1.1 }, sink = 12, tilt = 0.12, normal = 0, body = 0.38, radius = 11, shore = 14, cap = 80,
	},
	{
		kind = "Conifer", mask = "Conifer", class = "tree", grid = 13, gain = 1.0, ymax = 700,
		assets = { { "M1_Fir_A", 0.25 }, { "M1_Fir_B", 0.25 }, { "M1_Fir_C", 0.18 }, { "M1_Pine_A", 0.17 }, { "M1_Pine_B", 0.15 } },
		scale = { 0.82, 1.15 }, sink = 0.4, tilt = 0, normal = 0, radius = 1.1, shore = 10, cap = 26000, outer = true,
		detail = "tree",
	},
	{
		kind = "Broadleaf", mask = "Broadleaf", class = "tree", grid = 10, gain = 1.15, ymax = 400,
		assets = { { "M1_Beech_A", 0.55 }, { "M1_Beech_B", 0.45 } },
		scale = { 0.8, 1.2 }, sink = 0.4, tilt = 0, normal = 0, radius = 1.4, shore = 10, cap = 1500,
		detail = "tree",
	},
	{
		kind = "Boulders", mask = "Boulders", class = "rock", grid = 9, gain = 0.5, ymax = 700,
		assets = { { "M1_Boulder_A", 0.50 }, { "M1_Boulder_B", 0.35 }, { "M1_Boulder_C", 0.15 } },
		scale = { 0.7, 1.4 }, sink = 0.1, tilt = 0.2, normal = 1, body = 0.42, radius = 2, shore = 8, cap = 2000,
	},
	{
		kind = "Gorse", mask = "Gorse", class = "bush", grid = 7, gain = 0.7, ymax = 450,
		assets = { { "M1_Gorse_A", 0.5 }, { "M1_Gorse_B", 0.5 } },
		scale = { 0.8, 1.4 }, sink = 0.3, tilt = 0, normal = 0.6, body = 0.4, radius = 2.4, shore = 8, cap = 4000,
	},
	{
		kind = "TallGrass", mask = "TallGrass", class = "tall", grid = 4.5, gain = 0.8, ymax = 400,
		assets = { { "M1_TallGrass_A", 1 } },
		scale = { 0.8, 1.2 }, sink = 0.15, tilt = 0, normal = 0.5, body = 0.5, radius = 1.1, shore = 6, cap = 2000,
		detail = "tall",
	},
	{
		kind = "Heather", mask = "Heather", class = "ground", grid = 6, gain = 0.8, ymax = 700,
		assets = { { "M1_Heather_A", 0.5 }, { "M1_Heather_B", 0.5 } },
		scale = { 0.8, 1.6 }, sink = 0.3, tilt = 0.12, normal = 1, body = 0.5, radius = 2.1, shore = 6, cap = 15000,
		detail = "heath",
	},
	{
		kind = "Wildflowers", mask = "Wildflowers", class = "ground", grid = 3.6, gain = 1.0, ymax = 200, rmax = 1300,
		assets = { { "M1_Wildflowers_A", 1 } },
		scale = { 0.7, 1.3 }, sink = 0, tilt = 0, normal = 1, body = 0.5, radius = 2, shore = 6, cap = 2500,
		detail = "ground",
	},
}

----------------------------------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------------------------------
local function cellKey(cx: number, cz: number): number
	return (cx + 4096) * 8192 + (cz + 4096)
end

local function cellName(cx: number, cz: number): string
	return string.format("C_%d_%d", cx, cz)
end

-- The Random seed of one (kind, cell). Cells run from -27 to 26 each way, so (cx + 512) * 65537 + (cz + 512) is
-- distinct per cell, and no two kinds 1,000,003 apart can meet inside that range.
local function seedFor(seed: number, ruleId: number, cx: number, cz: number): number
	return ((seed * 31 + ruleId) * 1000003 + (cx + 512) * 65537 + (cz + 512)) % 4294967296
end

local function dataModule(): any
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local folder = worldGen and worldGen:FindFirstChild("Map1")
	local module = folder and folder:FindFirstChild("Data")
	if not module then
		error("Map1.Scatter: ServerStorage.WorldGen.Map1.Data is missing")
	end
	return require(if RunService:IsRunning() then module else module:Clone())
end

local function findPath(root: Instance, names: { string }): Instance?
	local cur: Instance? = root
	for _, name in ipairs(names) do
		cur = cur and cur:FindFirstChild(name)
	end
	return cur
end

local function count(t: any): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function sortedKeys(t: any): { string }
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- a CFrame at pos whose UpVector is `up`, turned `yaw` radians about it
local function upFrame(pos: Vector3, up: Vector3, yaw: number): CFrame
	local axis = Vector3.yAxis:Cross(up)
	local base = CFrame.new(pos)
	if axis.Magnitude > 1e-5 then
		base = base * CFrame.fromAxisAngle(axis.Unit, acos(clamp(up.Y, -1, 1)))
	end
	return base * CFrame.Angles(0, yaw, 0)
end

----------------------------------------------------------------------------------------------------
-- the data: buffers and the fields made from them
----------------------------------------------------------------------------------------------------
-- ground height at a map point: the same bilinear sum as Data.heightAt, on the raw buffer
local function heightAt(ctx: any, x: number, z: number): number
	local n = ctx.N
	local fx = (x - ctx.OX) / ctx.C - 0.5
	local fz = (z - ctx.OZ) / ctx.C - 0.5
	local i, j = floor(fx), floor(fz)
	if i < 0 then
		i, fx = 0, 0
	elseif i > n - 2 then
		i, fx = n - 2, n - 1
	end
	if j < 0 then
		j, fz = 0, 0
	elseif j > n - 2 then
		j, fz = n - 2, n - 1
	end
	local tx, tz = fx - i, fz - j
	local k = (j * n + i) * 2
	local H = ctx.H
	local a, c = readu16(H, k), readu16(H, k + 2)
	local d, e = readu16(H, k + 2 * n), readu16(H, k + 2 * n + 2)
	return ((a * (1 - tx) + c * tx) * (1 - tz) + (d * (1 - tx) + e * tx) * tz) / ctx.HS
end

-- the index of the grid cell that holds a map point (clamped to the grid)
local function gridIndex(ctx: any, x: number, z: number): number
	local n = ctx.N
	local i = clamp(floor((x - ctx.OX) / ctx.C), 0, n - 1)
	local j = clamp(floor((z - ctx.OZ) / ctx.C), 0, n - 1)
	return j * n + i
end

-- near: for every cell, the distance from its centre to the centre of the nearest wet cell, in eighths of a stud
-- (255 = none within 4 cells). A cell is wet as the terrain writer reads it: a level above its ground.
local function buildNear(ctx: any, reach: number)
	local W, H = ctx.W, ctx.H
	if not W then
		return
	end
	local n, c = ctx.N, ctx.C
	local near = buffer.create(n * n)
	buffer.fill(near, 0, 255)
	local R = 4
	local offs = {}
	for dj = -R, R do
		for di = -R, R do
			local d = sqrt(di * di + dj * dj) * c
			if d <= R * c + 0.01 then
				table.insert(offs, { di, dj, min(254, floor(d * 8 + 0.5)) })
			end
		end
	end
	local lo = clamp(floor((-reach - ctx.OX) / c) - R, 0, n - 1)
	local hi = clamp(floor((reach - ctx.OX) / c) + R, 0, n - 1)
	local wet = 0
	for j = lo, hi do
		local row = j * n
		for i = lo, hi do
			local wr = readu16(W, (row + i) * 2)
			if wr ~= 0 and wr > readu16(H, (row + i) * 2) + 1.6 then
				wet += 1
				for _, o in ipairs(offs) do
					local ii, jj = i + o[1], j + o[2]
					if ii >= 0 and jj >= 0 and ii < n and jj < n then
						local k = jj * n + ii
						if o[3] < readu8(near, k) then
							writeu8(near, k, o[3])
						end
					end
				end
			end
		end
	end
	ctx.near = near
	ctx.wetCells = wet
end

-- which material slots count as bare ground (no plant grows there): the stream bed, rock faces and the paths
local function bareSlots(terrain: any): { [number]: boolean }
	local bare = {}
	for id, slot in pairs(terrain.materialSlots or {}) do
		local n = tonumber(id)
		if n and type(slot) == "table" and Scatter.BARE_BASES[tostring(slot.base)] then
			bare[n] = true
		end
	end
	return bare
end

local function buildTrails(terrain: any): { any }
	local segs = {}
	for _, tr in ipairs(terrain.trails or {}) do
		for k = 1, #tr - 1 do
			local a, b = tr[k], tr[k + 1]
			local ax, az, bx, bz = a[1], a[3], b[1], b[3]
			local vx, vz = bx - ax, bz - az
			local len2 = vx * vx + vz * vz
			if len2 > 1e-6 then
				table.insert(segs, {
					ax = ax, az = az, vx = vx, vz = vz, len2 = len2,
					minX = min(ax, bx), maxX = max(ax, bx), minZ = min(az, bz), maxZ = max(az, bz),
				})
			end
		end
	end
	return segs
end

-- distance from a point to the nearest of the given trail segments
local function trailDistance(segs: { any }, x: number, z: number): number
	local best = HUGE
	for _, s in ipairs(segs) do
		local t = clamp(((x - s.ax) * s.vx + (z - s.az) * s.vz) / s.len2, 0, 1)
		local dx, dz = x - (s.ax + t * s.vx), z - (s.az + t * s.vz)
		local d2 = dx * dx + dz * dz
		if d2 < best then
			best = d2
		end
	end
	return sqrt(best)
end

local function loadContext(opts: any): any
	local Data = opts.data or Scatter._data
	if not Data then
		Data = dataModule()
		Scatter._data = Data
	end
	-- a Data table that is already on another pack (a test's) stays on it unless opts.pack says otherwise
	Data.open(opts.pack or (opts.data and Data.packName and Data.packName()) or Scatter.PACK)
	local terrain = Data.terrain()
	local ctx: any = { Data = Data, terrain = terrain, warnings = {} }
	ctx.N, ctx.C, ctx.OX, ctx.OZ, ctx.HS = Data.N, Data.CELL, Data.ORIGIN_X, Data.ORIGIN_Z, Data.HEIGHT_SCALE
	ctx.MN, ctx.MC = Data.MASK_N, Data.MASK_CELL
	ctx.H = Data.buffer("Height")
	local function optional(name: string): buffer?
		if Data.has(name) then
			return Data.buffer(name)
		end
		table.insert(ctx.warnings, "the pack has no " .. name)
		return nil
	end
	ctx.W = optional("WaterLevel")
	ctx.M = optional("Material")
	ctx.masks = {}
	for _, rule in ipairs(Scatter.RULES) do
		ctx.masks[rule.mask] = optional("Mask_" .. rule.mask)
	end
	if Data.has("Layout") then
		ctx.layout = Data.layout()
	else
		table.insert(ctx.warnings, "the pack has no Layout: no landmark or site is kept clear")
	end
	ctx.assets = {}
	for _, kind in ipairs({ "Plants", "Landmarks", "Skyline", "FarValley" }) do
		local manifest = Data.manifest(kind)
		if type(manifest) == "table" and type(manifest.assets) == "table" then
			for _, a in ipairs(manifest.assets) do
				ctx.assets[a.name] = a
			end
		elseif kind == "Plants" or kind == "Landmarks" then
			table.insert(ctx.warnings, "the pack has no Manifest_" .. kind)
		end
	end
	Data.close()
	local radii = terrain.radii or {}
	ctx.playR = tonumber(radii.play) or Scatter.PLAY_RADIUS
	ctx.boundR = tonumber(radii.boundary) or Scatter.BOUNDARY_RADIUS
	local disc = if type(radii.protectedDisc) == "table" then radii.protectedDisc else Scatter.PROTECTED
	ctx.p0, ctx.p1 = tonumber(disc[1]) or Scatter.PROTECTED[1], tonumber(disc[2]) or Scatter.PROTECTED[2]
	ctx.seed = tonumber(terrain.seed) or Scatter.SEED
	ctx.bare = bareSlots(terrain)
	ctx.trails = buildTrails(terrain)
	return ctx
end

----------------------------------------------------------------------------------------------------
-- footprints: what the landmarks and sites keep clear
----------------------------------------------------------------------------------------------------
local function addFoot(S: any, f: any)
	local c = S.cell
	for cx = floor((f.x - f.reach) / c), floor((f.x + f.reach) / c) do
		for cz = floor((f.z - f.reach) / c), floor((f.z + f.reach) / c) do
			local k = cellKey(cx, cz)
			local list = S.feet[k]
			if not list then
				list = {}
				S.feet[k] = list
			end
			table.insert(list, f)
		end
	end
	S.footCount += 1
end

-- the name of the footprint that holds the point, or nil. small: a small plant (the tighter margin).
-- A mass (the peak) counts by its ellipse only while its mesh is not standing where the rays can find it.
local function footHit(list: { any }?, x: number, z: number, small: boolean): string?
	if not list then
		return nil
	end
	for _, f in ipairs(list) do
		local dx, dz = x - f.x, z - f.z
		local shape = f.shape
		if shape == "disc" then
			local r = if small then f.rSmall else f.rSolid
			if dx * dx + dz * dz < r * r then
				return f.name
			end
		elseif shape == "box" then
			local lx = dx * f.cos - dz * f.sin
			local lz = dx * f.sin + dz * f.cos
			local pad = if small then f.padSmall else f.padSolid
			if lx > f.x0 - pad and lx < f.x1 + pad and lz > f.z0 - pad and lz < f.z1 + pad then
				return f.name
			end
		elseif not f.present then
			local lx = dx * f.cos - dz * f.sin
			local lz = dx * f.sin + dz * f.cos
			local ex, ez = (lx - f.cx) / f.ax, (lz - f.cz) / f.az
			if ex * ex + ez * ez < 1 then
				return f.name
			end
		end
	end
	return nil
end

-- the skyline and the far valley are world-sized meshes for looks: they keep nothing clear
local FAR_TAGS = { Skyline = true, FarValley = true, FarMesh = true, NoCollision = true }
local function isFarMesh(asset: any?, name: string, x: number, z: number): boolean
	if asset then
		if asset.kind == "Skyline" or asset.kind == "FarValley" then
			return true
		end
		for _, tag in ipairs(asset.tags or {}) do
			if FAR_TAGS[tag] then
				return true
			end
		end
		return type(asset.size) == "table" and max(asset.size[1], asset.size[3]) > 2000
	end
	if string.find(name, "Skyline", 1, true) or string.find(name, "FarValley", 1, true) then
		return true
	end
	return abs(x) < 0.001 and abs(z) < 0.001 -- an unknown asset placed at the origin: a world-space mesh
end

local function buildFootprints(S: any)
	local ctx = S.ctx
	S.feet = {}
	S.masses = {}
	S.footCount = 0
	local layout = ctx.layout
	if layout then
		local pad = Scatter.ITEM_PAD
		for _, it in ipairs(layout.items or {}) do
			local name = tostring(it.asset)
			local a = ctx.assets[name]
			local pos = it.position
			if type(pos) == "table" and not isFarMesh(a, name, pos[1], pos[3]) then
				local x, z = pos[1], pos[3]
				local yaw = rad(tonumber(it.yawDegrees) or 0)
				local f: any = { name = name, x = x, z = z, cos = cos(yaw), sin = sin(yaw) }
				if a and type(a.boundsMin) == "table" and type(a.boundsMax) == "table" then
					local x0, x1, z0, z1 = a.boundsMin[1], a.boundsMax[1], a.boundsMin[3], a.boundsMax[3]
					local reach = sqrt(max(x0 * x0, x1 * x1) + max(z0 * z0, z1 * z1))
					if max(x1 - x0, z1 - z0) >= Scatter.MASS then
						f.shape = "mass"
						f.cx, f.cz = (x0 + x1) / 2, (z0 + z1) / 2
						f.ax, f.az = (x1 - x0) / 2 * Scatter.MASS_FILL, (z1 - z0) / 2 * Scatter.MASS_FILL
						f.reach = reach
						f.present = false -- set by newSession when a ray finds its mesh standing there
						table.insert(S.masses, f)
					elseif a.kind == "Tree" then
						-- a lone tree: no other trunk under its crown; small plants up to its own trunk
						f.shape = "disc"
						f.rSolid = max(abs(x0), abs(x1), abs(z0), abs(z1))
						f.rSmall = pad.solid
						f.reach = f.rSolid
					else
						f.shape = "box"
						f.x0, f.x1, f.z0, f.z1 = x0, x1, z0, z1
						f.padSolid, f.padSmall = pad.solid, pad.small
						f.reach = reach + pad.solid
					end
				else
					f.shape = "disc"
					f.rSolid, f.rSmall = 6 + pad.solid, 6 + pad.small
					f.reach = f.rSolid
				end
				addFoot(S, f)
			end
		end
		local sites = layout.sites
		for _, s in ipairs((type(sites) == "table" and sites.items) or {}) do
			local pos = s.position
			if type(pos) == "table" then
				local clear = Scatter.SITE_CLEAR
				addFoot(S, {
					name = "site:" .. tostring(s.id or s.name), shape = "disc", x = pos[1], z = pos[3],
					rSolid = clear.solid, rSmall = clear.small, reach = clear.solid,
				})
			end
		end
	end
	for i, k in ipairs(S.opts.keepOut or {}) do
		local r = tonumber(k.r) or 4
		addFoot(S, {
			name = "keepOut:" .. i, shape = "disc", x = k.x, z = k.z, rSolid = r, rSmall = tonumber(k.rSmall) or r / 2, reach = r,
		})
	end
	local loot = S.opts.loot
	if typeof(loot) == "Instance" then
		local o = S.offset
		for _, d in ipairs(loot:GetDescendants()) do
			if d:IsA("BasePart") then
				local c = if d:GetAttribute("Kind") == "Crate" then 4.5 else 3
				addFoot(S, {
					name = "loot", shape = "disc", x = d.Position.X - o.X, z = d.Position.Z - o.Z,
					rSolid = c + 1.5, rSmall = c, reach = c + 1.5,
				})
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- templates
----------------------------------------------------------------------------------------------------
local function assetBody(S: any, rule: any, name: string): number
	local a = S.ctx.assets[name]
	if rule.body and a and type(a.size) == "table" then
		return rule.body * min(a.size[1], a.size[3])
	end
	return rule.radius
end

local function color3(rgb: any, fallback: Color3): Color3
	if type(rgb) == "table" and #rgb >= 3 then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return fallback
end

-- A plain Model that stands in for a missing template (tests only): blocks sized from the manifest.
local function standIn(S: any, rule: any, name: string): Model
	local a = S.ctx.assets[name]
	local bmin = (a and a.boundsMin) or { -2, 0, -2 }
	local bmax = (a and a.boundsMax) or { 2, 4, 2 }
	local m = Instance.new("Model")
	m.Name = name
	local function block(partName: string, size: Vector3, centre: Vector3, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = partName
		p.Anchored = true
		p.Size = size
		p.CFrame = CFrame.new(centre)
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local parts = (a and a.parts) or {}
	local w, d = bmax[1] - bmin[1], bmax[3] - bmin[3]
	local cx, cz = (bmin[1] + bmax[1]) / 2, (bmin[3] + bmax[3]) / 2
	if rule.class == "tree" then
		local top = bmax[2]
		local trunk = rule.radius * 2
		block(name .. "_Bark", V3(trunk, top * 0.55 - bmin[2], trunk), V3(0, (top * 0.55 + bmin[2]) / 2, 0),
			color3(parts[1] and parts[1].rgb, Color3.fromRGB(112, 98, 86)), Enum.Material.Wood)
		block(name .. "_Needles", V3(w * 0.7, top * 0.7, d * 0.7), V3(cx, top * 0.65, cz),
			color3(parts[2] and parts[2].rgb, Color3.fromRGB(50, 74, 48)), Enum.Material.LeafyGrass)
	else
		local material = if rule.class == "crag" or rule.class == "rock" then Enum.Material.Limestone else Enum.Material.LeafyGrass
		block(name .. "_Body", V3(w, bmax[2] - bmin[2], d), V3(cx, (bmin[2] + bmax[2]) / 2, cz),
			color3(parts[1] and parts[1].rgb, Color3.fromRGB(150, 150, 140)), material)
	end
	-- no PrimaryPart: the pivot is the model's own, the base centre on the ground like the real templates
	m.WorldPivot = CFrame.new()
	return m
end

local function templateRoot(S: any): Instance?
	local given = S.opts.templates
	if typeof(given) == "Instance" then
		return given
	end
	return findPath(ServerStorage, Scatter.TEMPLATES)
end

-- the template Model of an asset, a stand-in when asked for, or nil (remembered)
local function templateOf(S: any, rule: any, name: string): Model?
	local known = S.templates[name]
	if known ~= nil then
		return known or nil
	end
	local found: Instance? = nil
	local root = S.templateRoot
	if root then
		found = root:FindFirstChild(name)
		if not (found and found:IsA("Model")) then
			for _, d in ipairs(root:GetDescendants()) do
				if d.Name == name and d:IsA("Model") then
					found = d
					break
				end
			end
		end
		if not (found and found:IsA("Model")) then
			found = nil
		end
	end
	if not found and S.opts.standIns then
		S.standIns[name] = true
		if not S.dry then
			found = standIn(S, rule, name)
		end
	end
	S.templates[name] = found or false
	if not found and not S.standIns[name] then
		S.missing[name] = 0
	end
	return found :: Model?
end

-- does this part of a clone collide? (class tree: the bark only)
local function partCollides(S: any, rule: any, part: BasePart, info: any?): boolean
	if not CLASS[rule.class].solid then
		return false
	end
	if rule.class ~= "tree" then
		return true
	end
	if info and info.collide ~= nil then
		return info.collide == true
	end
	local n = part.Name
	if string.find(n, "Bark", 1, true) or string.find(n, "Trunk", 1, true) then
		return true
	end
	if string.find(n, "Needles", 1, true) or string.find(n, "Leaves", 1, true) or string.find(n, "Crown", 1, true) then
		return false
	end
	return part.CanCollide
end

-- The model every plant of (asset, visual, shadow) is cloned from: the template with its flags already set, so
-- a placement is a Clone, a ScaleTo and a PivotTo. Kept out of the DataModel; destroyed when the build ends.
local function prototype(S: any, rule: any, name: string, visual: boolean, shadow: boolean): Model?
	local key = name .. (if visual then "|v" else "|c") .. (if shadow then "1" else "0")
	local known = S.protos[key]
	if known ~= nil then
		return known or nil
	end
	local template = templateOf(S, rule, name)
	if not template then
		S.protos[key] = false
		return nil
	end
	local cls = CLASS[rule.class]
	local asset = S.ctx.assets[name]
	local partInfo = {}
	for _, p in ipairs((asset and asset.parts) or {}) do
		partInfo[p.name] = p
	end
	local m = template:Clone()
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	if not S.opts.keepAttributes then
		for attr in pairs(m:GetAttributes()) do
			m:SetAttribute(attr, nil)
		end
	end
	local parts, colliders, casters = 0, 0, 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			local info = partInfo[d.Name]
			local collide = partCollides(S, rule, d, info) and not visual
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = collide
			d.CanQuery = collide
			local cast = cls.shadow and shadow and not (info and info.castShadow == false)
			d.CastShadow = cast
			if collide then
				colliders += 1
			end
			if cast then
				casters += 1
			end
			if not S.opts.keepAttributes then
				for attr in pairs(d:GetAttributes()) do
					d:SetAttribute(attr, nil)
				end
			end
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if parts == 0 then
		m:Destroy()
		S.protos[key] = false
		S.missing[name] = S.missing[name] or 0
		table.insert(S.ctx.warnings, "template " .. name .. " has no parts")
		return nil
	end
	S.protoInfo[m] = { instances = 1 + #m:GetDescendants(), parts = parts, colliders = colliders, casters = casters }
	S.protos[key] = m
	return m
end

-- the rule's mix over the assets that have a template: { names, cum (running weights), total }.
-- A plan (dry) counts the designed mix whatever templates exist; stats.missing still names what has none.
local function buildMix(S: any, rule: any)
	local names, cum, total = {}, {}, 0
	for _, entry in ipairs(rule.assets) do
		local name, weight = entry[1], entry[2]
		local has = templateOf(S, rule, name) ~= nil
		if has or S.dry then
			total += weight
			table.insert(names, name)
			table.insert(cum, total)
		end
	end
	return { names = names, cum = cum, total = total }
end

----------------------------------------------------------------------------------------------------
-- the session: everything one build, plan or check needs
----------------------------------------------------------------------------------------------------
local function parseWindow(ctx: any, w: any): any
	if not w then
		return nil
	end
	local x0, x1, z0, z1
	if w.minX ~= nil or w.x0 ~= nil then
		x0, x1, z0, z1 = w.minX or w.x0, w.maxX or w.x1, w.minZ or w.z0, w.maxZ or w.z1
	else
		local c0, c1, r0, r1 = w.col0 or w[1], w.col1 or w[2], w.row0 or w[3], w.row1 or w[4]
		if not (c0 and c1 and r0 and r1) then
			error("Map1.Scatter: window needs minX, maxX, minZ, maxZ (studs) or col0, col1, row0, row1 (grid cells)")
		end
		x0, x1 = ctx.OX + c0 * ctx.C, ctx.OX + (c1 + 1) * ctx.C
		z0, z1 = ctx.OZ + r0 * ctx.C, ctx.OZ + (r1 + 1) * ctx.C
	end
	if not (x0 and x1 and z0 and z1) or x0 >= x1 or z0 >= z1 then
		error("Map1.Scatter: the window is empty")
	end
	return { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
end

local function newKindStats(): any
	return { candidates = 0, kept = 0, placed = 0, inside = 0, band = 0, beyond = 0, rejected = {} }
end

local function newSession(opts: any): any
	if Scatter.CELL % Scatter.SUB ~= 0 then
		error("Map1.Scatter: CELL must be a whole multiple of SUB")
	end
	local ctx = loadContext(opts)
	local S: any = {
		opts = opts,
		ctx = ctx,
		dry = opts.dry == true,
		cell = Scatter.CELL,
		offset = opts.offset or Vector3.zero,
		seed = tonumber(opts.seed) or ctx.seed,
		playR = ctx.playR,
		p0 = ctx.p0,
		p1 = ctx.p1,
		outer = opts.outer ~= false,
		templates = {},
		protos = {},
		protoInfo = {},
		missing = {},
		standIns = {},
		crags = {},
		turf = {},
		cellTrails = {},
		cellModels = {},
		cellInstances = {},
		subTrees = 0,
		subFlora = 0,
		started = os.clock(),
	}
	S.outerTo = if S.outer then Scatter.OUTER.to else S.playR
	S.visualR = ctx.boundR + 10
	S.maxTan2 = tan(rad(Scatter.MAX_SLOPE)) ^ 2
	S.window = parseWindow(ctx, opts.window)
	S.parent = if typeof(opts.parent) == "Instance" then opts.parent else workspace:FindFirstChild("Arena")
	-- where the status attributes go: a plan writes them only to a parent that was named
	if opts.quiet then
		S.statusTarget = nil
	elseif typeof(opts.parent) == "Instance" then
		S.statusTarget = opts.parent
	elseif not S.dry then
		S.statusTarget = S.parent
	end
	S.templateRoot = templateRoot(S)
	if not S.templateRoot then
		table.insert(ctx.warnings, "no template container (ServerStorage." .. table.concat(Scatter.TEMPLATES, ".") .. ")")
	end
	buildNear(ctx, S.outerTo + S.cell)
	buildFootprints(S)

	-- the kinds of this run
	local wanted = nil
	if type(opts.kinds) == "table" then
		wanted = {}
		for _, k in ipairs(opts.kinds) do
			wanted[k] = true
		end
	end
	S.rules = {}
	S.ruleByKind = {}
	S.kindOfAsset = {}
	for id, rule in ipairs(Scatter.RULES) do
		for _, entry in ipairs(rule.assets) do
			S.kindOfAsset[entry[1]] = rule.kind
		end
		if (not wanted or wanted[rule.kind]) and ctx.masks[rule.mask] then
			local density = opts.density
			local knob = if type(density) == "number" then density elseif type(density) == "table" then (density[rule.kind] or 1) else 1
			local r: any = setmetatable({ id = id, knob = knob, thin = 1, expected = 0, stats = newKindStats() }, { __index = rule })
			r.mix = buildMix(S, rule)
			r.bodies = {}
			r.scales = {}
			r.tops = {}
			for _, entry in ipairs(rule.assets) do
				local name = entry[1]
				local a = ctx.assets[name]
				r.bodies[name] = assetBody(S, rule, name)
				local range = a and (a.scaleRange or a.scale)
				r.scales[name] = if type(range) == "table" and #range == 2 then range else rule.scale
				r.tops[name] = if a and type(a.boundsMax) == "table" then a.boundsMax[2] else 4
			end
			table.insert(S.rules, r)
			S.ruleByKind[rule.kind] = r
		end
	end

	-- what the masks ask for inside the play radius, and the even thinning that keeps each kind under its cap
	local mn, mc = ctx.MN, ctx.MC
	local playR2 = S.playR * S.playR
	local sums = {}
	for _, r in ipairs(S.rules) do
		sums[r] = 0
	end
	for mj = 0, mn - 1 do
		local z = ctx.OZ + (mj + 0.5) * mc
		for mi = 0, mn - 1 do
			local x = ctx.OX + (mi + 0.5) * mc
			local d2 = x * x + z * z
			if d2 <= playR2 then
				local k = mj * mn + mi
				local ramp = 1
				if d2 < S.p1 * S.p1 then
					ramp = clamp((sqrt(d2) - S.p0) / (S.p1 - S.p0), 0, 1)
				end
				if ramp > 0 then
					for _, r in ipairs(S.rules) do
						local v = readu8(ctx.masks[r.mask], k)
						if v > 0 and not (r.rmax and d2 > r.rmax * r.rmax) then
							sums[r] += min(1, v / 255 * r.gain) * ramp
						end
					end
				end
			end
		end
	end
	for _, r in ipairs(S.rules) do
		r.expected = sums[r] * (mc * mc) / (r.grid * r.grid) * r.knob
		if r.cap and r.expected > r.cap then
			r.thin = r.cap / r.expected
		end
	end

	-- landmark meshes that cover the ground, and the terrain to snap to
	S.coverUp = 700
	local marks = opts.landmarks
	if marks ~= false then
		local list = {}
		if type(marks) == "table" then
			list = marks
		elseif typeof(marks) == "Instance" then
			list = { marks }
		elseif S.parent then
			for _, name in ipairs({ "Landmarks", "Plinths" }) do
				local f = S.parent:FindFirstChild(name)
				if f and #f:GetChildren() > 0 then
					table.insert(list, f)
				end
			end
		end
		if #list > 0 then
			local p = RaycastParams.new()
			p.FilterType = Enum.RaycastFilterType.Include
			p.FilterDescendantsInstances = list
			S.coverParams = p
			-- is each mass's own mesh among them? A ray down through the middle of its bounds tells: if so the rays
			-- decide round it, if not its ellipse does.
			local o = S.offset
			for _, f in ipairs(S.masses) do
				local wx = f.x + f.cx * f.cos + f.cz * f.sin + o.X
				local wz = f.z - f.cx * f.sin + f.cz * f.cos + o.Z
				f.present = workspace:Raycast(V3(wx, 6000 + o.Y, wz), V3(0, -9000, 0), p) ~= nil
			end
		end
	end
	S.massesPresent = 0
	for _, f in ipairs(S.masses) do
		if f.present then
			S.massesPresent += 1
		end
	end
	if opts.snap ~= false and not S.dry then
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		p.FilterDescendantsInstances = { workspace.Terrain }
		p.IgnoreWater = true
		S.snapParams = p
	end
	S.snapped, S.unsnapped = 0, 0
	return S
end

local function setStatus(S: any, text: string, progress: number?)
	local target = S.statusTarget
	if target then
		target:SetAttribute("ScatterStatus", text)
		if progress then
			target:SetAttribute("ScatterProgress", clamp(progress, 0, 1))
		end
	end
end

-- the trail segments that pass near a cell (remembered), or false
local function trailsNear(S: any, cx: number, cz: number): any
	local key = cellKey(cx, cz)
	local known = S.cellTrails[key]
	if known ~= nil then
		return known
	end
	local c = S.cell
	local x0, z0 = cx * c, cz * c
	local list = {}
	for _, s in ipairs(S.ctx.trails) do
		if s.maxX > x0 - 24 and s.minX < x0 + c + 24 and s.maxZ > z0 - 24 and s.minZ < z0 + c + 24 then
			table.insert(list, s)
		end
	end
	local value: any = if #list > 0 then list else false
	S.cellTrails[key] = value
	return value
end

local function maybeYield(S: any)
	if os.clock() - S.sliceStart > S.slice then
		task.wait()
		S.sliceStart = os.clock()
	end
end

----------------------------------------------------------------------------------------------------
-- one rule in one cell
----------------------------------------------------------------------------------------------------
local function reject(st: any, why: string)
	local r = st.rejected
	r[why] = (r[why] or 0) + 1
end

-- is the ground at this map point under a landmark's mesh?
local function covered(S: any, x: number, y: number, z: number): boolean
	local p = S.coverParams
	if not p then
		return false
	end
	local o = S.offset
	local up = S.coverUp
	return workspace:Raycast(V3(x + o.X, y + o.Y + up, z + o.Z), V3(0, -(up - 1), 0), p) ~= nil
end

-- the frame of a plant in map space (the offset is added when it is made)
local function frameFor(S: any, rule: any, x: number, y: number, z: number, gx: number, gz: number, scale: number, yaw: number,
	u1: number, u2: number, body: number): CFrame
	local ctx = S.ctx
	local cf
	if rule.normal <= 0 then
		local base = y
		if rule.class == "tree" then
			-- upright on the lowest ground round the trunk, so no side of the foot hangs in the air
			local rr = max(0.7, body)
			for k = 0, 3 do
				local a = yaw + k * (PI / 2) + PI / 4
				local hy = heightAt(ctx, x + cos(a) * rr, z + sin(a) * rr)
				if hy < base then
					base = hy
				end
			end
		end
		cf = CFrame.new(x, base - rule.sink, z) * CFrame.Angles(0, yaw, 0)
	else
		local n = V3(-gx, 1, -gz).Unit
		local up = Vector3.yAxis:Lerp(n, rule.normal).Unit
		-- what is left of the slope under a plant that does not lean all the way: sink its downhill edge
		local left = acos(clamp(up:Dot(n), -1, 1))
		local extra = min(1.2, body * tan(left))
		cf = upFrame(V3(x, y - rule.sink - extra, z), up, yaw)
	end
	if rule.tilt > 0 then
		cf = cf * CFrame.Angles((u1 * 2 - 1) * rule.tilt, 0, (u2 * 2 - 1) * rule.tilt)
	end
	return cf
end

--[[ Evaluates one rule in one cell. env carries what the cell's earlier plants left behind: solids ({ x, z, r }),
	and the tree and flora counts of its four 40-stud sub-cells. Accepted plants are appended to out as
	{ rule, asset, cf, scale, visual, shadow, x, y, z, r, inWindow }; a plant outside opts.window is still decided and
	listed (it takes its place among the solids and the counts, as in a full build) and is dropped by the caller.
	st receives the counts. ]]
local function evalRule(S: any, rule: any, cx: number, cz: number, env: any, out: { any }, st: any)
	local ctx = S.ctx
	local mask = ctx.masks[rule.mask]
	local c = S.cell
	local x0, z0 = cx * c, cz * c
	local x1, z1 = x0 + c, z0 + c
	local playR = S.playR
	local limit = if rule.outer and S.outer then S.outerTo else playR
	if rule.rmax and rule.rmax < limit then
		limit = rule.rmax
	end
	-- the cell's nearest and farthest points from the centre
	local nx, nz = clamp(0, x0, x1), clamp(0, z0, z1)
	if nx * nx + nz * nz > limit * limit then
		return
	end
	local fx, fz = max(abs(x0), abs(x1)), max(abs(z0), abs(z1))
	if fx * fx + fz * fz <= S.p0 * S.p0 then
		return
	end
	-- anything in the mask here?
	local mn, mc = ctx.MN, ctx.MC
	local mi0, mi1 = clamp(floor((x0 - ctx.OX) / mc), 0, mn - 1), clamp(floor((x1 - 0.001 - ctx.OX) / mc), 0, mn - 1)
	local mj0, mj1 = clamp(floor((z0 - ctx.OZ) / mc), 0, mn - 1), clamp(floor((z1 - 0.001 - ctx.OZ) / mc), 0, mn - 1)
	local found = false
	for mj = mj0, mj1 do
		local row = mj * mn
		for mi = mi0, mi1 do
			if readu8(mask, row + mi) ~= 0 then
				found = true
				break
			end
		end
		if found then
			break
		end
	end
	if not found then
		return
	end

	local cls = CLASS[rule.class]
	local s = rule.grid
	local i0, i1 = ceil(x0 / s - 0.5), ceil(x1 / s - 0.5) - 1
	local j0, j1 = ceil(z0 / s - 0.5), ceil(z1 / s - 0.5) - 1
	local rng = Random.new(seedFor(S.seed, rule.id, cx, cz))
	local gain = rule.gain / 255
	local thin = rule.thin * rule.knob
	local p0, p1 = S.p0, S.p1
	local outerSpec = Scatter.OUTER
	local near, M, bare = ctx.near, ctx.M, ctx.bare
	local window = S.window
	local mix = rule.mix
	local sub = Scatter.SUB
	local perRow = c / sub
	local budget = cls.budget
	local trails = trailsNear(S, cx, cz)
	local feet = S.feet[cellKey(cx, cz)]
	local solids = env.solids
	local pathHalf = Scatter.PATH_HALF

	for j = j0, j1 do
		for i = i0, i1 do
			local x = (i + 0.5 + (rng:NextNumber() - 0.5) * 0.9) * s
			local z = (j + 0.5 + (rng:NextNumber() - 0.5) * 0.9) * s
			if x < x0 then
				x = 2 * x0 - x
			elseif x >= x1 then
				x = 2 * x1 - x - 0.001
			end
			if z < z0 then
				z = 2 * z0 - z
			elseif z >= z1 then
				z = 2 * z1 - z - 0.001
			end
			local mi, mj = floor((x - ctx.OX) / mc), floor((z - ctx.OZ) / mc)
			local mv = 0
			if mi >= 0 and mj >= 0 and mi < mn and mj < mn then
				mv = readu8(mask, mj * mn + mi)
			end
			if mv > 0 then
				-- every candidate draws the same six values, whatever becomes of it
				local uKeep, uAsset, uScale, uYaw = rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber()
				local u1, u2 = rng:NextNumber(), rng:NextNumber()
				st.candidates += 1
				local r = sqrt(x * x + z * z)
				local p = min(1, mv * gain) * thin
				local ymax = rule.ymax
				local visual = false
				if r > playR then
					if r >= limit then
						p = 0
					elseif r <= playR + outerSpec.ramp then
						p *= 1 + (outerSpec.keep - 1) * (r - playR) / outerSpec.ramp
					elseif r <= outerSpec.fadeFrom then
						p *= outerSpec.keep
					else
						p *= outerSpec.keep * (outerSpec.to - r) / (outerSpec.to - outerSpec.fadeFrom)
					end
					ymax = min(ymax, outerSpec.ymax)
					visual = r > S.visualR
				elseif r < p1 then
					p *= (r - p0) / (p1 - p0)
				end
				if rule.rmax and r > rule.rmax then
					p = 0
				end
				if uKeep < p then
					st.kept += 1
					local y = heightAt(ctx, x, z)
					local gx = (heightAt(ctx, x + 2, z) - heightAt(ctx, x - 2, z)) / 4
					local gz = (heightAt(ctx, x, z + 2) - heightAt(ctx, x, z - 2)) / 4
					local gi = gridIndex(ctx, x, z)
					local why: string? = nil
					local asset: string? = nil
					local scale, body = 1, 0
					if y >= ymax then
						why = "height"
					elseif cls.steep and gx * gx + gz * gz > S.maxTan2 then
						why = "steep"
					elseif near and readu8(near, gi) < rule.shore * 8 then
						why = "water"
					elseif cls.bare and M and bare[readu8(M, gi)] then
						why = "bare"
					elseif mix.total <= 0 then
						why = "missing"
					else
						local pick = uAsset * mix.total
						asset = mix.names[#mix.names]
						for k, edge in ipairs(mix.cum) do
							if pick < edge then
								asset = mix.names[k]
								break
							end
						end
						local range = rule.scales[asset]
						scale = range[1] + (range[2] - range[1]) * uScale
						body = rule.bodies[asset] * scale
						if trails and trailDistance(trails, x, z) < pathHalf + (if cls.small then body * 0.6 else body + 0.5) then
							why = "trail"
						elseif footHit(feet, x, z, cls.small) then
							why = "site"
						else
							-- trunks, boulders and crags never stand in one another; a small plant never has its centre in one
							for _, o in ipairs(solids) do
								local dx, dz = x - o.x, z - o.z
								local need = if cls.small then o.r * 0.9 elseif rule.class == "tree" then o.r + body + 0.4 else o.r + body
								if dx * dx + dz * dz < need * need then
									why = "overlap"
									break
								end
							end
						end
					end
					local si = 0
					if not why and budget then
						si = floor((z - z0) / sub) * perRow + floor((x - x0) / sub) + 1
						if budget == "tree" then
							if env.trees[si] >= Scatter.TREES_PER_SUB then
								why = "cap"
							end
						elseif env.flora[si] >= Scatter.FLORA_PER_SUB then
							why = "cap"
						end
					end
					if not why and covered(S, x, y, z) then
						why = "cover"
					end
					if why then
						reject(st, why)
					else
						if budget == "tree" then
							env.trees[si] += 1
						elseif budget then
							env.flora[si] += 1
						end
						if not cls.small then
							table.insert(solids, { x = x, z = z, r = body })
						end
						local inWindow = not window or (x >= window.x0 and x < window.x1 and z >= window.z0 and z < window.z1)
						local shadow = cls.shadow
						if rule.class == "rock" then
							shadow = rule.tops[asset] * scale - rule.sink >= Scatter.SHADOW_MIN
						end
						table.insert(out, {
							rule = rule, asset = asset, scale = scale, visual = visual, shadow = shadow, x = x, y = y, z = z, r = r,
							inWindow = inWindow,
							cf = if inWindow then frameFor(S, rule, x, y, z, gx, gz, scale, uYaw * TAU, u1, u2, body) else nil,
						})
					end
				end
			end
		end
	end
end

-- the crags of a cell (remembered): they are planted first and depend on nothing else, so a cell can ask for its
-- neighbours' crags and keep its own plants out of them
local function cragsOf(S: any, cx: number, cz: number): any
	local key = cellKey(cx, cz)
	local known = S.crags[key]
	if known then
		return known
	end
	local rule = S.ruleByKind.Crags
	local entry = { list = {}, stats = newKindStats(), counted = false }
	if rule then
		evalRule(S, rule, cx, cz, { solids = {}, trees = {}, flora = {} }, entry.list, entry.stats)
	end
	S.crags[key] = entry
	return entry
end

local function mergeStats(into: any, from: any)
	for k, v in pairs(from) do
		if type(v) == "number" then
			into[k] += v
		end
	end
	for why, n in pairs(from.rejected) do
		into.rejected[why] = (into.rejected[why] or 0) + n
	end
end

-- The generator's daisies on the heart's turf (opts.turfFlowers): spec.count clumps at a random bearing and radius,
-- as the generator draws them, but only on open turf (off the beds, the platform, the plinths and their rims).
-- Made once from one Random, then bucketed by cell.
local function buildTurf(S: any)
	local spec = Scatter.TURF
	local st = S.turfStats
	local rng = Random.new(seedFor(S.seed, 99, 0, 0))
	local made, tries = 0, 0
	while made < spec.count and tries < spec.count * 8 do
		tries += 1
		local bearing = rng:NextNumber() * TAU
		local r = spec.r0 + (spec.r1 - spec.r0) * rng:NextNumber()
		local scale = spec.scale[1] + (spec.scale[2] - spec.scale[1]) * rng:NextNumber()
		local yaw = rng:NextNumber() * TAU
		local x, z = sin(bearing) * r, -cos(bearing) * r
		local key = cellKey(floor(x / S.cell), floor(z / S.cell))
		st.candidates += 1
		if footHit(S.feet[key], x, z, true) then
			reject(st, "site")
		else
			made += 1
			local list = S.turf[key]
			if not list then
				list = {}
				S.turf[key] = list
			end
			table.insert(list, { x = x, z = z, r = r, scale = scale, yaw = yaw })
		end
	end
end

-- every plant of one cell, in planting order
local function planCell(S: any, cx: number, cz: number): { any }
	local c = S.cell
	local key = cellKey(cx, cz)
	local env: any = { solids = {}, trees = {}, flora = {} }
	local n = (c / Scatter.SUB) ^ 2
	for i = 1, n do
		env.trees[i], env.flora[i] = 0, 0
	end
	local out = {}
	for _, rule in ipairs(S.rules) do
		if rule.kind == "Crags" then
			local own = cragsOf(S, cx, cz)
			if not own.counted then
				own.counted = true
				mergeStats(rule.stats, own.stats)
			end
			for dz = -1, 1 do
				for dx = -1, 1 do
					for _, p in ipairs(cragsOf(S, cx + dx, cz + dz).list) do
						table.insert(env.solids, { x = p.x, z = p.z, r = rule.bodies[p.asset] * p.scale })
						if dx == 0 and dz == 0 then
							table.insert(out, p)
						end
					end
				end
			end
		else
			evalRule(S, rule, cx, cz, env, out, rule.stats)
		end
	end
	local turf = S.turf[key]
	local flowers = S.ruleByKind.Wildflowers
	if turf and flowers then
		local spec = Scatter.TURF
		local ctx = S.ctx
		local st = S.turfStats
		for _, t in ipairs(turf) do
			st.kept += 1
			local x, z = t.x, t.z
			local si = floor((z - cz * c) / Scatter.SUB) * (c / Scatter.SUB) + floor((x - cx * c) / Scatter.SUB) + 1
			if env.flora[si] >= Scatter.FLORA_PER_SUB then
				reject(st, "cap")
			else
				env.flora[si] += 1
				local w = S.window
				local y = heightAt(ctx, x, z)
				local gx = (heightAt(ctx, x + 2, z) - heightAt(ctx, x - 2, z)) / 4
				local gz = (heightAt(ctx, x, z + 2) - heightAt(ctx, x, z - 2)) / 4
				local up = V3(-gx, 1, -gz).Unit
				table.insert(out, {
					rule = flowers, asset = spec.asset, scale = t.scale, visual = false, shadow = false, x = x, y = y, z = z, r = t.r,
					inWindow = not w or (x >= w.x0 and x < w.x1 and z >= w.z0 and z < w.z1),
					cf = upFrame(V3(x, y - spec.sink, z), up, t.yaw), turf = true,
				})
			end
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- making the models
----------------------------------------------------------------------------------------------------
-- Makes one planned plant under `folder`. Returns the prototype's counts, or nil when there is no template.
local function spawn(S: any, p: any, folder: Instance): any
	local proto = prototype(S, p.rule, p.asset, p.visual, p.shadow)
	if not proto then
		S.missing[p.asset] = (S.missing[p.asset] or 0) + 1
		return nil
	end
	local cf = p.cf
	local snap = S.snapParams
	if snap then
		-- the real ground, when it is there and agrees with the data
		local o = S.offset
		local tol = Scatter.SNAP_TOLERANCE
		local hit = workspace:Raycast(V3(p.x + o.X, p.y + o.Y + tol + 0.5, p.z + o.Z), V3(0, -(2 * tol + 1), 0), snap)
		if hit then
			cf = cf + V3(0, hit.Position.Y - o.Y - p.y, 0)
			S.snapped += 1
		else
			S.unsnapped += 1
		end
	end
	local m = proto:Clone()
	if abs(p.scale - 1) > 1e-3 then
		m:ScaleTo(p.scale)
	end
	m:PivotTo(cf + S.offset)
	m.Parent = folder
	return S.protoInfo[proto]
end

local function outputRoot(S: any, create: boolean): Instance?
	local parent = S.parent
	if not parent then
		if not create then
			return nil
		end
		error("Map1.Scatter: no parent (workspace.Arena is missing and opts.parent was not given)")
	end
	local root = parent:FindFirstChild(Scatter.FOLDER)
	if not root and create then
		root = Instance.new("Folder")
		root.Name = Scatter.FOLDER
		root.Parent = parent
	end
	return root
end

-- the cells a run covers, nearest the centre first
local function cellList(S: any): { any }
	local c = S.cell
	local R = S.outerTo
	local x0, x1, z0, z1 = -R, R, -R, R
	local w = S.window
	if w then
		x0, x1, z0, z1 = max(x0, w.x0), min(x1, w.x1), max(z0, w.z0), min(z1, w.z1)
	end
	local cells = {}
	for cz = floor(z0 / c), ceil(z1 / c) - 1 do
		for cx = floor(x0 / c), ceil(x1 / c) - 1 do
			local nx, nz = clamp(0, cx * c, cx * c + c), clamp(0, cz * c, cz * c + c)
			if nx * nx + nz * nz <= R * R then
				local mx, mz = (cx + 0.5) * c, (cz + 0.5) * c
				table.insert(cells, { cx = cx, cz = cz, d2 = mx * mx + mz * mz })
			end
		end
	end
	table.sort(cells, function(a, b)
		if a.d2 ~= b.d2 then
			return a.d2 < b.d2
		elseif a.cz ~= b.cz then
			return a.cz < b.cz
		end
		return a.cx < b.cx
	end)
	return cells
end

-- the heaviest disc of the given radius over the cell counts: { models, instances, x, z }
local function worstDisc(S: any, radius: number): any
	local c = S.cell
	local reach = ceil(radius / c)
	local offs = {}
	for dz = -reach, reach do
		for dx = -reach, reach do
			if (dx * dx + dz * dz) * c * c <= radius * radius then
				table.insert(offs, { dx, dz })
			end
		end
	end
	local best = { models = 0, instances = 0, x = 0, z = 0 }
	local limit = ceil(S.playR / c)
	for cz = -limit, limit - 1 do
		for cx = -limit, limit - 1 do
			local mx, mz = (cx + 0.5) * c, (cz + 0.5) * c
			if mx * mx + mz * mz <= S.playR * S.playR then
				local models, instances = 0, 0
				for _, o in ipairs(offs) do
					local k = cellKey(cx + o[1], cz + o[2])
					local m = S.cellModels[k]
					if m then
						models += m
						instances += S.cellInstances[k]
					end
				end
				if models > best.models then
					best = { models = models, instances = instances, x = mx, z = mz }
				end
			end
		end
	end
	return best
end

local function budgetTable(S: any, models: number, instances: number): any
	local B = Scatter.BUDGET
	local d1024 = worstDisc(S, 1024)
	local d300 = worstDisc(S, 300)
	local b = {
		models = { value = models, cap = B.models },
		instances = { value = instances, cap = B.instances },
		disc1024Models = { value = d1024.models, cap = B.disc1024Models, x = d1024.x, z = d1024.z },
		disc1024Instances = { value = d1024.instances, cap = B.disc1024Instances, x = d1024.x, z = d1024.z },
		disc300Models = { value = d300.models, cap = B.disc300Models, x = d300.x, z = d300.z },
		treesPer40 = { value = S.subTrees, cap = Scatter.TREES_PER_SUB },
		floraPer40 = { value = S.subFlora, cap = Scatter.FLORA_PER_SUB },
	}
	local ok = true
	for _, row in pairs(b) do
		row.ok = row.value <= row.cap
		ok = ok and row.ok
	end
	return b, ok
end

local function detailClasses(): string
	local parts = {}
	for _, rule in ipairs(Scatter.RULES) do
		if rule.detail then
			for _, entry in ipairs(rule.assets) do
				table.insert(parts, entry[1] .. "=" .. rule.detail)
			end
		end
	end
	table.sort(parts)
	return table.concat(parts, ";")
end
Scatter.detailClasses = detailClasses

----------------------------------------------------------------------------------------------------
-- build, plan, start
----------------------------------------------------------------------------------------------------
local function run(opts: any): any
	local S = newSession(opts)
	S.slice = tonumber(opts.slice) or 0.03
	S.sliceStart = os.clock()
	S.turfStats = newKindStats()
	if opts.turfFlowers then
		buildTurf(S)
	end
	local cells = cellList(S)
	local root: Instance? = nil
	if not S.dry then
		root = outputRoot(S, true)
		if root and not S.window and not opts.keep then
			-- a whole build starts from an empty folder (a window replaces only its own cells, below)
			setStatus(S, "clearing the old cells", 0)
			for _, child in ipairs(root:GetChildren()) do
				child:Destroy()
				maybeYield(S)
			end
		end
	end
	setStatus(S, string.format("%s 0/%d cells", if S.dry then "planning" else "planting", #cells), 0)

	-- what a plan counts for a plant it does not make: the manifest's parts and flags
	local function plannedInfo(p: any): any
		local rule = p.rule
		local cls = CLASS[rule.class]
		local a = S.ctx.assets[p.asset]
		local list = if a and type(a.parts) == "table" then a.parts else nil
		local n = if list then #list else (if rule.class == "tree" then 2 else 1)
		local colliders, casters = 0, 0
		for k = 1, n do
			local info = list and list[k]
			local collide = cls.solid and not p.visual
			if collide and rule.class == "tree" then
				collide = if info then info.collide == true else k == 1
			end
			if collide then
				colliders += 1
			end
			if cls.shadow and p.shadow and not (info and info.castShadow == false) then
				casters += 1
			end
		end
		return { instances = 1 + n, parts = n, colliders = colliders, casters = casters }
	end

	local models, instances, parts, colliders, casters = 0, 0, 0, 0, 0
	local byAsset, byDetail = {}, {}
	local collected: { any }? = if opts.collect then {} else nil -- tests: every plant as { asset, x, z, scale }
	local built = 0
	local lastReport = os.clock()
	local perRow = S.cell / Scatter.SUB
	for index, cell in ipairs(cells) do
		local cx, cz = cell.cx, cell.cz
		local key = cellKey(cx, cz)
		local name = cellName(cx, cz)
		if root and not opts.keep then
			local old = root:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		local plan = planCell(S, cx, cz)
		local folder: Instance? = nil
		local cellModels, cellInstances = 0, 0
		local subT, subF = table.create(perRow * perRow, 0), table.create(perRow * perRow, 0)
		for _, p in ipairs(plan) do
			local info = nil
			if not p.inWindow then
				reject(if p.turf then S.turfStats else p.rule.stats, "outsideWindow")
			elseif S.dry then
				info = plannedInfo(p)
				if S.missing[p.asset] then
					S.missing[p.asset] += 1
				end
			else
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = name
				end
				info = spawn(S, p, folder :: Instance)
			end
			if info then
				if collected then
					table.insert(collected, { p.asset, p.x, p.z, p.scale })
				end
				cellModels += 1
				cellInstances += info.instances
				parts += info.parts
				colliders += info.colliders
				casters += info.casters
				byAsset[p.asset] = (byAsset[p.asset] or 0) + 1
				local detail = p.rule.detail or "never"
				byDetail[detail] = (byDetail[detail] or 0) + 1
				local st = if p.turf then S.turfStats else p.rule.stats
				st.placed += 1
				if p.r <= S.playR then
					st.inside += 1
				elseif p.r <= S.ctx.boundR then
					st.band += 1
				else
					st.beyond += 1
				end
				local budget = CLASS[p.rule.class].budget
				if budget then
					local si = floor((p.z - cz * S.cell) / Scatter.SUB) * perRow + floor((p.x - cx * S.cell) / Scatter.SUB) + 1
					if budget == "tree" then
						subT[si] += 1
						S.subTrees = max(S.subTrees, subT[si])
					else
						subF[si] += 1
						S.subFlora = max(S.subFlora, subF[si])
					end
				end
			end
		end
		if cellModels > 0 then
			built += 1
			models += cellModels
			instances += cellInstances + 1 -- the cell's own Folder
			S.cellModels[key] = cellModels
			S.cellInstances[key] = cellInstances + 1
		end
		if folder then
			if cellModels > 0 then
				folder.Parent = root
			else
				folder:Destroy()
			end
		end
		if os.clock() - lastReport > 0.1 or index == #cells then
			lastReport = os.clock()
			setStatus(S, string.format("%s %d/%d cells, %d models", if S.dry then "planning" else "planting", index, #cells, models),
				index / #cells)
			if type(opts.progress) == "function" then
				opts.progress(index, #cells, name)
			end
		end
		maybeYield(S)
	end

	for _, proto in pairs(S.protos) do
		if proto then
			proto:Destroy()
		end
	end
	for name in pairs(S.standIns) do
		local made = S.templates[name]
		if made then
			made:Destroy()
		end
	end

	local stats: any = {
		version = Scatter.VERSION,
		map = Scatter.MAP,
		seed = S.seed,
		cell = S.cell,
		dry = S.dry,
		pack = S.ctx.Data.packName and S.ctx.Data.packName() or nil,
		seconds = os.clock() - S.started,
		cells = { considered = #cells, built = built },
		models = models,
		instances = instances,
		parts = parts,
		colliders = colliders,
		shadowCasters = casters,
		byAsset = byAsset,
		byDetail = byDetail,
		byKind = {},
		missing = S.missing,
		standIns = S.standIns,
		footprints = S.footCount,
		wetCells = S.ctx.wetCells,
		coverRays = S.coverParams ~= nil,
		masses = #S.masses,
		massesPresent = S.massesPresent,
		snapped = S.snapped,
		unsnapped = S.unsnapped,
		warnings = S.ctx.warnings,
	}
	local inside, band, beyond = 0, 0, 0
	for _, rule in ipairs(S.rules) do
		local st = rule.stats
		st.expected = rule.expected
		st.thin = rule.thin
		st.cap = rule.cap
		stats.byKind[rule.kind] = st
		inside += st.inside
		band += st.band
		beyond += st.beyond
	end
	if opts.turfFlowers then
		stats.byKind.TurfFlowers = S.turfStats
		inside += S.turfStats.inside
	end
	stats.inside, stats.band, stats.beyond = inside, band, beyond
	if S.window then
		stats.window = S.window
	end
	if S.offset ~= Vector3.zero then
		stats.offset = { S.offset.X, S.offset.Y, S.offset.Z }
	end
	stats.budget, stats.ok = budgetTable(S, models, instances)
	stats.placements = collected
	stats.templates = if S.templateRoot then S.templateRoot:GetFullName() else nil
	if not S.dry and count(S.missing) > 0 then
		stats.ok = false -- a build that had to leave plants out
	end

	if root then
		root:SetAttribute("Map", Scatter.MAP)
		root:SetAttribute("Seed", S.seed)
		root:SetAttribute("CellSize", S.cell)
		root:SetAttribute("Version", Scatter.VERSION)
		root:SetAttribute("DetailClasses", detailClasses())
		if not S.window then
			root:SetAttribute("Models", models)
			root:SetAttribute("Instances", instances)
		end
	end
	setStatus(S, string.format("%s: %d models, %d instances in %d cells, %.1f s", if S.dry then "planned" else "done", models, instances, built,
		stats.seconds), 1)
	return stats
end

-- a short copy of the stats for an attribute (the parent's ScatterStats)
local function summary(stats: any): string
	local kinds = {}
	for kind, st in pairs(stats.byKind) do
		kinds[kind] = { placed = st.placed, inside = st.inside, band = st.band, beyond = st.beyond }
	end
	local budget = {}
	for name, row in pairs(stats.budget) do
		budget[name] = { row.value, row.cap, row.ok }
	end
	return HttpService:JSONEncode({
		ok = stats.ok, dry = stats.dry, seed = stats.seed, seconds = math.round(stats.seconds * 10) / 10, models = stats.models,
		instances = stats.instances, cells = stats.cells.built, byAsset = stats.byAsset, byKind = kinds, budget = budget,
		missing = stats.missing,
	})
end

-- Plants the map (or opts.window of it). Yields between cells. Returns the stats.
function Scatter.build(opts: any?): any
	if RunService:IsRunning() then
		error("Map1.Scatter: Edit mode only")
	end
	local o = opts or {}
	local stats = run(o)
	-- the result as an attribute, for a caller that started the build and went away (a plan writes it only to a
	-- parent that was named, like the status)
	local target: Instance? = nil
	if o.quiet then
		target = nil
	elseif typeof(o.parent) == "Instance" then
		target = o.parent
	elseif not o.dry then
		target = workspace:FindFirstChild("Arena")
	end
	if target then
		target:SetAttribute("ScatterStats", summary(stats))
	end
	Scatter.last = stats
	return stats
end

-- The counts for the same options without making anything.
function Scatter.plan(opts: any?): any
	local o = table.clone(opts or {})
	o.dry = true
	return Scatter.build(o)
end

-- build on a background thread. Returns at once; the parent's ScatterStatus ends in "done: ..." or "error: ...".
function Scatter.start(opts: any?)
	local o = opts or {}
	local parent = if typeof(o.parent) == "Instance" then o.parent else workspace:FindFirstChild("Arena")
	task.spawn(function()
		local ok, err = xpcall(Scatter.build, debug.traceback, o)
		if not ok then
			warn("[Map1.Scatter] " .. tostring(err))
			if parent then
				parent:SetAttribute("ScatterStatus", "error: " .. string.sub(tostring(err), 1, 300))
			end
		end
	end)
end

Scatter.run = Scatter.build
Scatter.generate = Scatter.start

-- A window in map studs, for opts.window.
function Scatter.windowBox(minX: number, maxX: number, minZ: number, maxZ: number): any
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

function Scatter.windowAround(x: number, z: number, half: number): any
	return { minX = x - half, maxX = x + half, minZ = z - half, maxZ = z + half }
end

----------------------------------------------------------------------------------------------------
-- clear, stats, check
----------------------------------------------------------------------------------------------------
local function rootOf(opts: any?): Instance?
	local o = opts or {}
	local parent = if typeof(o.parent) == "Instance" then o.parent else workspace:FindFirstChild("Arena")
	return parent and parent:FindFirstChild(Scatter.FOLDER)
end

-- Destroys what build made: the cells of <parent>.Scatter (and the folder itself with opts.root = true).
-- Returns the number of cells destroyed. Never touches anything else.
function Scatter.clear(opts: any?): number
	local o = opts or {}
	local root = rootOf(o)
	if not root then
		return 0
	end
	local n = 0
	local last = os.clock()
	for _, child in ipairs(root:GetChildren()) do
		child:Destroy()
		n += 1
		if os.clock() - last > 0.03 then
			task.wait()
			last = os.clock()
		end
	end
	for _, attr in ipairs({ "Models", "Instances" }) do
		root:SetAttribute(attr, nil)
	end
	local parent = root.Parent
	if parent then
		for _, attr in ipairs({ "ScatterStatus", "ScatterProgress", "ScatterStats" }) do
			parent:SetAttribute(attr, nil)
		end
	end
	if o.root then
		root:Destroy()
	end
	return n
end

-- Counts what stands in <parent>.Scatter now.
function Scatter.stats(opts: any?): any
	local o = opts or {}
	local root = rootOf(o)
	local kindOf, budgetOf = {}, {}
	for _, rule in ipairs(Scatter.RULES) do
		for _, entry in ipairs(rule.assets) do
			kindOf[entry[1]] = rule.kind
			budgetOf[entry[1]] = CLASS[rule.class].budget
		end
	end
	local out: any = {
		cells = 0, models = 0, instances = 0, parts = 0, colliders = 0, shadowCasters = 0, byAsset = {}, byKind = {},
		last = Scatter.last,
	}
	if not root then
		return out
	end
	local offset = o.offset or Vector3.zero
	local S: any = { cell = Scatter.CELL, cellModels = {}, cellInstances = {}, subTrees = 0, subFlora = 0 }
	S.playR = tonumber(o.playRadius) or Scatter.PLAY_RADIUS
	local sub = Scatter.SUB
	local subT, subF = {}, {}
	local last = os.clock()
	for _, cell in ipairs(root:GetChildren()) do
		out.cells += 1
		out.instances += 1
		for _, m in ipairs(cell:GetChildren()) do
			out.models += 1
			local n = 1
			for _, d in ipairs(m:GetDescendants()) do
				n += 1
				if d:IsA("BasePart") then
					out.parts += 1
					if d.CanCollide then
						out.colliders += 1
					end
					if d.CastShadow then
						out.shadowCasters += 1
					end
				end
			end
			out.instances += n
			out.byAsset[m.Name] = (out.byAsset[m.Name] or 0) + 1
			local kind = kindOf[m.Name] or "other"
			out.byKind[kind] = (out.byKind[kind] or 0) + 1
			if m:IsA("Model") then
				local p = m:GetPivot().Position - offset
				local key = cellKey(floor(p.X / S.cell), floor(p.Z / S.cell))
				S.cellModels[key] = (S.cellModels[key] or 0) + 1
				S.cellInstances[key] = (S.cellInstances[key] or 0) + n
				local budget = budgetOf[m.Name]
				if budget then
					local sk = cellKey(floor(p.X / sub), floor(p.Z / sub))
					if budget == "tree" then
						subT[sk] = (subT[sk] or 0) + 1
						S.subTrees = max(S.subTrees, subT[sk])
					else
						subF[sk] = (subF[sk] or 0) + 1
						S.subFlora = max(S.subFlora, subF[sk])
					end
				end
			end
		end
		if os.clock() - last > 0.03 then
			task.wait()
			last = os.clock()
		end
	end
	out.budget, out.ok = budgetTable(S, out.models, out.instances)
	return out
end

--[[ Reads the placed models back against the rules: names, streaming mode, anchoring, which parts collide, take
	queries, touch and cast shadows, the play radius, the protected disc and the height above the data's ground.
	Returns { ok, checked, problems = { text, ... } (the first 40), counts = { [problem kind] = n } }. Needs the data
	pack (for the heights); opts as for build (parent, offset, pack). ]]
function Scatter.check(opts: any?): any
	local o = opts or {}
	local root = rootOf(o)
	local result: any = { ok = true, checked = 0, problems = {}, counts = {} }
	if not root then
		result.ok = false
		table.insert(result.problems, "there is no Scatter folder")
		return result
	end
	local ctx = loadContext(o)
	local offset = o.offset or Vector3.zero
	local ruleOf = {}
	for _, rule in ipairs(Scatter.RULES) do
		for _, entry in ipairs(rule.assets) do
			ruleOf[entry[1]] = rule
		end
	end
	local function problem(kind: string, text: string)
		result.ok = false
		result.counts[kind] = (result.counts[kind] or 0) + 1
		if #result.problems < 40 then
			table.insert(result.problems, kind .. ": " .. text)
		end
	end
	local outerTo = Scatter.OUTER.to
	local last = os.clock()
	for _, cell in ipairs(root:GetChildren()) do
		if not cell:IsA("Folder") then
			problem("cell", cell:GetFullName() .. " is a " .. cell.ClassName)
		end
		for _, m in ipairs(cell:GetChildren()) do
			result.checked += 1
			local rule = ruleOf[m.Name]
			if not m:IsA("Model") then
				problem("class", m:GetFullName() .. " is a " .. m.ClassName)
			elseif not rule then
				problem("name", m:GetFullName() .. " is not a Map 1 scatter asset")
			else
				local cls = CLASS[rule.class]
				local pivot = m:GetPivot().Position - offset
				local r = sqrt(pivot.X * pivot.X + pivot.Z * pivot.Z)
				local where = string.format("%s at (%.0f, %.0f)", m.Name, pivot.X, pivot.Z)
				if m.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
					problem("streaming", where .. " is not Atomic")
				end
				if next(m:GetAttributes()) ~= nil and not o.keepAttributes then
					problem("attributes", where .. " carries attributes")
				end
				if r > outerTo + 1 or (r > ctx.playR + 0.5 and not rule.outer) then
					problem("radius", string.format("%s stands at r %.0f", where, r))
				end
				if r < ctx.p0 and not (rule.kind == "Wildflowers" and o.turfFlowers) then
					problem("heart", string.format("%s stands inside the protected disc (r %.0f)", where, r))
				end
				local ground = heightAt(ctx, pivot.X, pivot.Z)
				local low = ground - rule.sink - 3.5 - Scatter.SNAP_TOLERANCE
				if pivot.Y > ground + Scatter.SNAP_TOLERANCE + 0.5 or pivot.Y < low then
					problem("height", string.format("%s is at y %.1f, the ground is %.1f", where, pivot.Y, ground))
				end
				local visual = r > ctx.boundR + 10
				local collides = 0
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						if not d.Anchored then
							problem("anchored", where .. ": " .. d.Name .. " is not anchored")
						end
						if d.CanTouch then
							problem("touch", where .. ": " .. d.Name .. " has CanTouch")
						end
						if d.CanCollide then
							collides += 1
						end
						if d.CanCollide ~= d.CanQuery then
							problem("query", where .. ": " .. d.Name .. " collides and takes queries differently")
						end
						if d.CanCollide and (not cls.solid or visual) then
							problem("collision", where .. ": " .. d.Name .. " collides")
						end
						if d.CastShadow and not cls.shadow then
							problem("shadow", where .. ": " .. d.Name .. " casts a shadow")
						end
					end
				end
				if cls.solid and not visual and collides == 0 then
					problem("collision", where .. " has no colliding part")
				end
				if rule.class == "tree" and collides > 1 then
					problem("collision", where .. " has more than its trunk colliding")
				end
			end
		end
		if os.clock() - last > 0.03 then
			task.wait()
			last = os.clock()
		end
	end
	return result
end

-- Removes the plants whose pivot is within `radius` (flat distance) of any of the points (Vector3s, world space).
-- For loot spots found after the planting. opts.small = true: only the small plants (gorse, heather, tall grass,
-- flowers), which hide a thing on the ground without blocking it. Returns the number removed.
function Scatter.clearAround(points: { Vector3 }, radius: number, opts: any?): number
	local root = rootOf(opts)
	if not root then
		return 0
	end
	local c = Scatter.CELL
	local offset = (opts and opts.offset) or Vector3.zero
	local smallOnly = opts ~= nil and opts.small == true
	local isSmall = {}
	for _, rule in ipairs(Scatter.RULES) do
		for _, entry in ipairs(rule.assets) do
			isSmall[entry[1]] = CLASS[rule.class].small
		end
	end
	local removed = 0
	for _, point in ipairs(points) do
		local px, pz = point.X - offset.X, point.Z - offset.Z
		for cx = floor((px - radius) / c), floor((px + radius) / c) do
			for cz = floor((pz - radius) / c), floor((pz + radius) / c) do
				local cell = root:FindFirstChild(cellName(cx, cz))
				if cell then
					for _, m in ipairs(cell:GetChildren()) do
						if m:IsA("Model") and (not smallOnly or isSmall[m.Name]) then
							local p = m:GetPivot().Position
							local dx, dz = p.X - point.X, p.Z - point.Z
							if dx * dx + dz * dz < radius * radius then
								m:Destroy()
								removed += 1
							end
						end
					end
				end
			end
		end
	end
	return removed
end

-- The stats of build, plan or stats as text.
function Scatter.report(stats: any): string
	local lines = {}
	local function add(...)
		table.insert(lines, string.format(...))
	end
	add("Map1.Scatter%s: %d models, %d instances, %d cells%s", if stats.dry then " (plan)" else "", stats.models or 0, stats.instances or 0,
		(type(stats.cells) == "table" and stats.cells.built) or stats.cells or 0, if stats.seconds then string.format(", %.1f s", stats.seconds) else "")
	if stats.inside then
		add("  inside the play radius %d, out to the Boundary %d, beyond %d", stats.inside, stats.band, stats.beyond)
	end
	if stats.parts then
		add("  parts %d, colliding %d, casting shadows %d", stats.parts, stats.colliders or 0, stats.shadowCasters or 0)
	end
	for _, kind in ipairs(sortedKeys(stats.byKind or {})) do
		local st = stats.byKind[kind]
		if type(st) == "table" then
			local why = {}
			for _, k in ipairs(sortedKeys(st.rejected)) do
				table.insert(why, k .. " " .. st.rejected[k])
			end
			add("  %-12s placed %6d (inside %d, band %d, beyond %d); mask asks %.0f inside%s; refused: %s", kind, st.placed, st.inside, st.band,
				st.beyond, st.expected or 0, if st.thin and st.thin < 1 then string.format(", thinned x%.3f to the cap %d", st.thin, st.cap) else "",
				if #why > 0 then table.concat(why, ", ") else "none")
		else
			add("  %-12s %d", kind, st)
		end
	end
	for _, name in ipairs(sortedKeys(stats.byAsset or {})) do
		add("    %-18s %6d", name, stats.byAsset[name])
	end
	if stats.byDetail then
		local d = {}
		for _, k in ipairs(sortedKeys(stats.byDetail)) do
			table.insert(d, k .. " " .. stats.byDetail[k])
		end
		add("  DetailController classes: %s", table.concat(d, ", "))
	end
	if stats.budget then
		for _, name in ipairs(sortedKeys(stats.budget)) do
			local row = stats.budget[name]
			add("  budget %-18s %7d of %7d  %s%s", name, row.value, row.cap, if row.ok then "ok" else "OVER",
				if row.x then string.format("  (at %.0f, %.0f)", row.x, row.z) else "")
		end
	end
	if stats.missing and count(stats.missing) > 0 then
		local m = {}
		for _, name in ipairs(sortedKeys(stats.missing)) do
			table.insert(m, name .. " (" .. stats.missing[name] .. ")")
		end
		add("  MISSING TEMPLATES: %s", table.concat(m, ", "))
	end
	if stats.standIns and count(stats.standIns) > 0 then
		add("  stand-ins used for: %s", table.concat(sortedKeys(stats.standIns), ", "))
	end
	if stats.snapped then
		add("  heights: %d snapped to the terrain, %d from the data alone", stats.snapped, stats.unsnapped or 0)
		add("  landmark rays %s; %d of %d large landmarks (the peak) found standing, the rest kept clear by an ellipse",
			if stats.coverRays then "on" else "off", stats.massesPresent or 0, stats.masses or 0)
	end
	for _, w in ipairs(stats.warnings or {}) do
		add("  warning: %s", w)
	end
	return table.concat(lines, "\n")
end

return Scatter
