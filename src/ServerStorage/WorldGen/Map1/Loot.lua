--[[
	Map1.Loot - the loot markers of Map 1, the Green Land (docs/design/Map1Build.md 3.2; TwoArenas.md 3.5, 3.6, 3.9).
	STUDIO ONLY, Edit mode. It fills ServerStorage.ArenaData.LootSpawns from the data pack "map1_data" (Map1.Data):
	the Layout blob (Map1_Layout.json) says where the Horn, its racks, mouths and sails, the runner's flags and the 48
	sites are; the Height, WaterLevel and Region grids say where the ground is dry, reachable and gentle.

	WHAT LootService READS (ServerScriptService.Server.Services.LootService, collectMarkers and populate)
	  Every BasePart under ServerStorage.ArenaData.LootSpawns with attribute Kind = "Crate" | "Ground":
	    Tier    1 | 2 | 3        the loot table (ItemDefs.LootTables)
	    Runner  true             a runner's cache: a tier-2 crate with the runner's table and a pale flag beside it
	    DropIn  false            the Feast restocks this crate in place instead of dropping it from FeastDropHeight
	  A crate stands on the marker's bottom face (snapped by a 6-stud ray), its front along the marker's LookVector; a
	  ground item rests on the ground under the marker's bottom face. Each round a crate stands on EVERY Crate marker and
	  an item lies on Config.Loot.GroundSpawnChance of the Ground markers that are inside the round's start ring
	  (GameState.BorderStartRadius + Config.Loot.BorderMargin). The Feast restocks the tier-3 markers within
	  Config.Loot.SpireRefillRadius of the centre. So the marker set IS the amount of loot.
	This builder writes exactly those attributes, plus Source = "Map1:<group>:<id>" (what made the marker) and the tag
	LootSpawn, on Parts of the size the forest arena's markers had (4 x 2.2 x 2.6, invisible, not solid).

	THE SET (counts for Config.Maps.GreenLand: 48 contenders, 10 expected items a head)
	  the Horn's floor   6 tier-3 crates beside the six racks (DropIn = false: under the sails) and 6 tier-3 ground
	                     markers on the floor between them
	  the deck           6 tier-2 crates, two beside each mouth, and 6 tier-2 ground markers on the landings
	  the steps' foot    6 tier-3 crates on the knoll at the foot of each flight, in the mouth lanes: open sky, so the
	                     Feast drops them in (they are inside SpireRefillRadius)
	  the supply bags    24 tier-1 ground markers on the turf 11 studs in front of the plinth ring, one between every
	                     pair of plinths
	  runner's caches    the 8 sites F1..F8 (r 340): tier-2 crates with Runner = true, facing the Horn
	  the 40 other sites by kind (SITES below, TwoArenas 3.6): tier-2 crates and tier-1 ground markers round each
	                     anchor, and a tier-3 "prize" crate at five of them. The table is written for
	                     Plan.SiteContenders (24) and its counts grow with Config.Round.MaxContenders
	  scattered          tier-1 ground markers at one density over the whole field (r 190 to the start radius less 20),
	                     weighted by region, as many as bring a full round to Plan.ItemsPerContender a head
	Every marker is on dry ground that can be walked to from the Horn (a flood fill over the height grid: slopes up to
	Config.Movement.Slope.MaxWalkableAngle, water is swum), away from water, on a gentle slope, inside the full round's
	loot limit. A site whose anchor is in water or on a cliff is moved to the nearest good ground and the report says so
	(a site with no gentle ground near it, a crest or the peak's shoulder, is allowed RULES.SteepExtra more slope).
	DETERMINISTIC: the same data and Config give the same markers (Random.new(Loot.SEED) for the scattered ones).

	SEATING. When the place holds Map 1 (terrain written, landmarks placed) each marker is also checked against the
	real world: a ray finds the real floor, a crate's spot must be clear (GetPartsInPart with a crate-sized probe), and
	a tier-3 crate near the centre with anything solid over it within FeastDropHeight gets DropIn = false. The Horn's
	markers sit on its meshes (the ray starts 3 studs over the designed floor and must not find bare terrain). A
	marker on the open ground is looked for from RULES.CoverProbe studs up, so a mesh over the spot (the peak, a
	hedge, a boulder, a trunk) is met first and the spot counts as taken. A marker whose spot is taken moves to the
	nearest clear one (the Horn's stay on their own floor); one that finds none is "blocked": a scattered marker
	is then left out of the build, a designed one is left where it was planned and listed as a problem. With no world there at all (a dry run before the terrain is written) the data alone decides
	and the report counts those markers "by the data alone": run it again after the landmarks are in.

	USE (execute_luau, Edit mode; Studio caches required modules, so require a clone)
	  local Loot = require(game.ServerStorage.WorldGen.Map1.Loot:Clone())
	  return Loot.build()                       -- replaces this builder's markers in ServerStorage.ArenaData.LootSpawns
	  return Loot.build({ dryRun = true })      -- builds nothing: the report only
	  opts.data       a loaded Map1.Data (else this loads its own copy)
	  opts.parent     the folder to fill (default ServerStorage.ArenaData.LootSpawns, made if missing)
	  opts.clearAll   true: empty the folder first, whatever made its markers (default: only this builder's own are
	                  replaced, and markers of another arena left in it are reported)
	  opts.seat       false: never look at the world (data only)
	  opts.offset     Vector3 added to every world position (a workbench copy of the map)
	  opts.config     the Config table to read (default: a fresh copy of Shared.Config)
	Returns (report: string, stats: table). Loot.plan(opts) returns the marker list without building.
	Loot.ground(data, config) is the walkable-ground analysis (Map1.Audit and Map1.Water use it too).
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local sin, cos, rad, deg, atan = math.sin, math.cos, math.rad, math.deg, math.atan

local Loot = {}
Loot.VERSION = 1
Loot.MAP = "GreenLand"
Loot.SEED = 50117 -- the scattered markers' seed: change it and they fall elsewhere
Loot.SOURCE = "Map1" -- every marker's Source attribute starts with this
Loot.TAG = "LootSpawn"

local MARKER_SIZE = Vector3.new(4, 2.2, 2.6) -- the forest arena's marker size (LootService reads the bottom face)
local PROBE_SIZE = Vector3.new(3.6, 1.9, 2.3) -- LootService's crate probe
local GOLDEN = 137.50776

-- Builder details (the COUNTS are Config's: Config.Maps.GreenLand.Loot.Plan, Round.MaxContenders).
local RULES = {
	CrateSlope = 20, -- degrees: a crate needs gentler ground than this
	GroundSlope = 30, -- a ground marker
	CrateWater = 2, -- cells (4 studs each) kept clear of water round a crate
	GroundWater = 1, -- round a ground marker
	EdgeMargin = 20, -- studs kept inside the full round's loot limit (start radius + BorderMargin)
	SiteSearch = 80, -- studs: how far a site's anchor may move to reach good ground
	SteepExtra = 8, -- degrees a crate's slope limit is relaxed by where a site has no gentler ground (then the search doubles)
	CoverProbe = 200, -- studs above a marker on the open ground from where the seating ray starts: a mesh over the spot blocks it
	SiteFirstRing = 6, -- studs from the anchor to the first marker (a tree or a hedge may stand on the anchor)
	SiteSpacing = 6, -- studs between a site's markers (LootService keeps crates CrateSpacing = 5 apart)
	ScatterFrom = 190, -- scattered markers start outside the Heart's turf
	ScatterSpacing = 45, -- studs between scattered markers
	ScatterClear = 22, -- studs between a scattered marker and any other marker
	SeatTolerance = 3, -- studs the real floor may differ from the data before a spot counts as blocked
	SailHalfWidth = 14, -- studs either side of a sail's ground line that count as "under the sail" without a world
	-- scattered markers by region (Map1_Terrain.json "regions"): relative density
	RegionWeight = {
		Heart = 0, Iris = 1.0, NorthWood = 1.2, EastRidge = 0.8, WestRidge = 0.8, SouthMountain = 0.7, Lake = 1.0,
		Edge = 0.6, Crest = 0, Outside = 0,
	},
}
Loot.RULES = RULES

-- The sites by kind (TwoArenas 3.6's "Loot" column, for Plan.SiteContenders = 24 contenders). crates: tier-2 crates;
-- ground: tier-1 ground markers (the design's forage is ground loot until there is a forage system); prize: one
-- tier-3 crate at the anchor; first: studs from the anchor to the first marker. F1..F8 are the runner's caches.
local SITES: { [string]: { kind: string, crates: number?, ground: number?, prize: boolean?, first: number? } } = {
	B1 = { kind = "LoneTree", ground = 1, first = 8 },
	B2 = { kind = "LoneTree", ground = 1, first = 8 },
	B3 = { kind = "LoneTree", ground = 1, first = 8 },
	B4 = { kind = "Crossing", ground = 2 },
	B5 = { kind = "Water", crates = 1, ground = 2 },
	B6a = { kind = "Cover", crates = 1, ground = 1 },
	B6b = { kind = "Water", ground = 2 },
	B7 = { kind = "Lookout", crates = 1, ground = 1 },
	B8a = { kind = "Path", ground = 2 },
	B8b = { kind = "Path", ground = 2 },
	B9 = { kind = "Water", ground = 3 },
	B10a = { kind = "Berms", ground = 4 },
	B10b = { kind = "Berms", ground = 3 },
	C1 = { kind = "Landmark", prize = true },
	C2 = { kind = "Landmark", crates = 2, ground = 2, prize = true },
	C3 = { kind = "Landmark", crates = 3, ground = 4, prize = true },
	C4 = { kind = "Water", crates = 2, ground = 3 },
	C5 = { kind = "Forage", ground = 5 },
	C6 = { kind = "Water", crates = 2, ground = 3 },
	C7 = { kind = "Water", crates = 1, ground = 2 },
	C8 = { kind = "Shelter", crates = 2, ground = 1 },
	C9 = { kind = "Scree", ground = 2 },
	C10 = { kind = "Shelter", crates = 2, ground = 1 },
	C11 = { kind = "Shelter", crates = 2, ground = 1 },
	C12 = { kind = "Cover", crates = 1, ground = 2 },
	C13 = { kind = "Crossing", crates = 1, ground = 2 },
	C14 = { kind = "Lookout", crates = 1, ground = 1 },
	D1 = { kind = "Water", ground = 2 },
	D2 = { kind = "Landmark", prize = true },
	D3 = { kind = "Edge", crates = 1 },
	D4 = { kind = "Lookout", prize = true },
	D5 = { kind = "Lookout", crates = 1 },
	D6 = { kind = "Lookout", crates = 1 },
	S1 = { kind = "Berm", ground = 2 },
	S2 = { kind = "Berm", ground = 2 },
	S3 = { kind = "Berm", ground = 2 },
	S4 = { kind = "Berm", ground = 2 },
	S5 = { kind = "Berm", ground = 2 },
	S6 = { kind = "Berm", ground = 2 },
	S7 = { kind = "Berm", ground = 2 },
}
Loot.SITES = SITES

----------------------------------------------------------------------------------------------------
-- modules
----------------------------------------------------------------------------------------------------
local function map1Folder(): Instance
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local folder = worldGen and worldGen:FindFirstChild("Map1")
	if not folder then
		error("Map1.Loot: ServerStorage.WorldGen.Map1 is missing")
	end
	return folder
end

-- a module's table, from a copy in Edit mode (Studio caches a required module for the whole session)
local function fresh(module: Instance): any
	return require(if RunService:IsRunning() then module else module:Clone() :: any)
end

local function loadData(opts: { [string]: any }): any
	if opts.data then
		return opts.data
	end
	local module = map1Folder():FindFirstChild("Data")
	if not module then
		error("Map1.Loot: ServerStorage.WorldGen.Map1.Data is missing")
	end
	local data = fresh(module)
	data.load({ "Terrain", "Layout", "Height", "Region", "WaterLevel" })
	return data
end

local function loadConfig(opts: { [string]: any }): any
	return opts.config or fresh(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end

-- Config's value for Map 1 whatever Config.Map says today: Config.Maps.GreenLand[section][key], else Config[section][key].
local function mapValue(config: any, section: string, key: string): any
	local maps = config.Maps
	local map = if type(maps) == "table" then maps[Loot.MAP] else nil
	local over = if type(map) == "table" then map[section] else nil
	if type(over) == "table" and over[key] ~= nil then
		return over[key]
	end
	local base = config[section]
	return if type(base) == "table" then base[key] else nil
end
Loot.mapValue = mapValue

-- The border's starting radius for n contenders: RoundService.startRadiusFor with Map 1's numbers.
local function startRadiusFor(config: any, n: number): number
	local full = tonumber(mapValue(config, "Border", "StartRadius")) or 1800
	if mapValue(config, "Border", "ScaleWithContenders") == false then
		return full
	end
	local solo = min(tonumber(mapValue(config, "Border", "MinStartRadius")) or full, full)
	local most = max(2, tonumber(mapValue(config, "Border", "FullContenders")) or tonumber(mapValue(config, "Round", "MaxContenders")) or 48)
	local t = sqrt(math.clamp((n - 1) / (most - 1), 0, 1))
	return floor(solo + (full - solo) * t + 0.5)
end
Loot.startRadiusFor = startRadiusFor

----------------------------------------------------------------------------------------------------
-- the ground: what can be walked to from the Horn, what is dry, how steep it is
----------------------------------------------------------------------------------------------------
-- Loot.ground(data, config, opts?) -> G
--   G.reachable(col, row)   walked to from the centre on slopes up to MaxWalkableAngle (water is swum), inside radius
--   G.wet(col, row), G.nearWater(col, row, cells), G.height(col, row), G.slope(col, row) degrees, G.region(col, row)
--   G.cellAt(x, z), G.centre(col, row), G.heightAt(x, z), G.radius (the flood's limit), G.reachCount
--   G.good(x, z, maxSlope, waterCells, maxRadius) -> (boolean, reason?)   the test every marker passes
function Loot.ground(data: any, config: any, opts: { [string]: any }?): any
	local o = opts or {}
	local n: number = data.N
	local cell: number = data.CELL
	local ox: number, oz: number = data.ORIGIN_X, data.ORIGIN_Z
	local scale: number = data.HEIGHT_SCALE
	local H: buffer = data.buffer("Height")
	local W: buffer = data.buffer("WaterLevel")
	local R: buffer = data.buffer("Region")
	local terrain = data.terrain()
	local playRadius = tonumber(o.radius) or tonumber(terrain.radii and terrain.radii.play) or 1800
	local slopeCfg = config.Movement and config.Movement.Slope
	local maxAngle = tonumber(o.maxAngle) or tonumber(slopeCfg and slopeCfg.MaxWalkableAngle) or 46
	local maxStep = cell * math.tan(rad(maxAngle)) * scale -- raw height units between neighbouring cells

	local reach = buffer.create(n * n)
	local queue = table.create(700000)
	local head, tail = 1, 0
	local r2 = playRadius * playRadius
	local c0, r0 = floor((0 - ox) / cell), floor((0 - oz) / cell)
	local start = r0 * n + c0
	buffer.writeu8(reach, start, 1)
	tail += 1
	queue[tail] = start
	local count = 0
	while head <= tail do
		local idx = queue[head]
		head += 1
		count += 1
		local row = idx // n
		local col = idx - row * n
		local h = buffer.readu16(H, idx * 2)
		local wet = buffer.readu16(W, idx * 2) ~= 0
		for k = 1, 4 do
			local nc = if k == 1 then col + 1 elseif k == 2 then col - 1 else col
			local nr = if k == 3 then row + 1 elseif k == 4 then row - 1 else row
			if nc >= 0 and nr >= 0 and nc < n and nr < n then
				local j = nr * n + nc
				if buffer.readu8(reach, j) == 0 then
					local x = ox + cell * (nc + 0.5)
					local z = oz + cell * (nr + 0.5)
					if x * x + z * z <= r2 then
						local step = buffer.readu16(H, j * 2) - h
						if (wet and buffer.readu16(W, j * 2) ~= 0) or (step <= maxStep and step >= -maxStep) then
							buffer.writeu8(reach, j, 1)
							tail += 1
							queue[tail] = j
						end
					end
				end
			end
		end
	end
	table.clear(queue)

	local G = { N = n, CELL = cell, radius = playRadius, reachCount = count, maxAngle = maxAngle, reachBuffer = reach }

	local function inGrid(col: number, row: number): boolean
		return col >= 0 and row >= 0 and col < n and row < n
	end
	function G.cellAt(x: number, z: number): (number, number)
		return floor((x - ox) / cell), floor((z - oz) / cell)
	end
	function G.centre(col: number, row: number): (number, number)
		return ox + cell * (col + 0.5), oz + cell * (row + 0.5)
	end
	function G.reachable(col: number, row: number): boolean
		return inGrid(col, row) and buffer.readu8(reach, row * n + col) == 1
	end
	function G.wet(col: number, row: number): boolean
		return inGrid(col, row) and buffer.readu16(W, (row * n + col) * 2) ~= 0
	end
	function G.nearWater(col: number, row: number, cells: number): boolean
		for dr = -cells, cells do
			for dc = -cells, cells do
				local c, r = col + dc, row + dr
				if inGrid(c, r) and buffer.readu16(W, (r * n + c) * 2) ~= 0 then
					return true
				end
			end
		end
		return false
	end
	function G.height(col: number, row: number): number
		col = math.clamp(col, 0, n - 1)
		row = math.clamp(row, 0, n - 1)
		return buffer.readu16(H, (row * n + col) * 2) / scale
	end
	-- the ground's slope at a cell, degrees, from its four neighbours
	function G.slope(col: number, row: number): number
		local gx = (G.height(col + 1, row) - G.height(col - 1, row)) / (2 * cell)
		local gz = (G.height(col, row + 1) - G.height(col, row - 1)) / (2 * cell)
		return deg(atan(sqrt(gx * gx + gz * gz)))
	end
	function G.region(col: number, row: number): number
		if not inGrid(col, row) then
			return 0
		end
		return buffer.readu8(R, row * n + col)
	end
	function G.regionName(col: number, row: number): string
		return (terrain.regions and terrain.regions[tostring(G.region(col, row))]) or "Outside"
	end
	function G.heightAt(x: number, z: number): number
		return data.heightAt(x, z)
	end
	function G.good(x: number, z: number, maxSlope: number, waterCells: number, maxRadius: number?): (boolean, string?)
		if maxRadius and x * x + z * z > maxRadius * maxRadius then
			return false, "outside"
		end
		local col, row = G.cellAt(x, z)
		if not inGrid(col, row) then
			return false, "outside"
		end
		if buffer.readu8(reach, row * n + col) ~= 1 then
			return false, "unreachable"
		end
		if G.nearWater(col, row, waterCells) then
			return false, "water"
		end
		if G.slope(col, row) > maxSlope then
			return false, "steep"
		end
		return true, nil
	end
	return G
end

----------------------------------------------------------------------------------------------------
-- geometry helpers (map space: X east, Z south, bearings clockwise from north)
----------------------------------------------------------------------------------------------------
local function polar(bearing: number, r: number): (number, number)
	local a = rad(bearing)
	return sin(a) * r, -cos(a) * r
end

local function bearingOf(x: number, z: number): number
	return deg(math.atan2(x, -z)) % 360
end

local function angleBetween(a: number, b: number): number
	local d = abs(a - b) % 360
	return min(d, 360 - d)
end

local function vec(t: any): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- How far inside a convex polygon the point (x, z) is: the distance to its nearest edge, negative outside.
-- poly = { { x, y, z }, ... } in order round the polygon (the layout's deckPolygon and floorTriangle).
local function insideBy(x: number, z: number, poly: { any }): number
	local n = #poly
	local area = 0
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		area += a[1] * b[3] - b[1] * a[3]
	end
	local sign = if area >= 0 then 1 else -1
	local best = math.huge
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		local ex, ez = b[1] - a[1], b[3] - a[3]
		local len = sqrt(ex * ex + ez * ez)
		if len > 1e-6 then
			best = min(best, sign * (ex * (z - a[3]) - ez * (x - a[1])) / len)
		end
	end
	return best
end
Loot.insideBy = insideBy

-- A marker of the Horn keeps to its floor: m.within = { poly, margin } (at least margin inside), m.outside = { poly,
-- margin } (at least margin outside).
local function allowed(m: any, x: number, z: number): boolean
	if m.within and insideBy(x, z, m.within.poly) < m.within.margin then
		return false
	end
	if m.outside and insideBy(x, z, m.outside.poly) > -m.outside.margin then
		return false
	end
	return true
end

-- the flat unit vector from (x, z) toward the centre (north when it is the centre)
local function toCentre(x: number, z: number): Vector3
	local m = sqrt(x * x + z * z)
	if m < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return Vector3.new(-x / m, 0, -z / m)
end

----------------------------------------------------------------------------------------------------
-- the plan: every marker as data
----------------------------------------------------------------------------------------------------
-- A marker: { name, kind = "Crate" | "Ground", tier, x, y (its floor), z, look = Vector3, source, runner?, dropIn?,
--             group, cover = "sky" | "roof" | nil (the layout's own answer for DropIn), from = studs above y the
--             seating ray starts (the Horn's markers; RULES.CoverProbe for the rest), floorIsMesh = true when the
--             floor is a landmark's mesh }
function Loot.plan(options: { [string]: any }?): ({ any }, { [string]: any })
	local opts = options or {}
	local data = loadData(opts)
	local config = loadConfig(opts)
	local layout = data.layout()
	local terrain = data.terrain()
	local G = opts.ground or Loot.ground(data, config)
	local heart = layout.heart
	local stats: { [string]: any } = { moved = {}, short = {}, problems = {} }
	local markers: { any } = {}

	local maxContenders = tonumber(mapValue(config, "Round", "MaxContenders")) or 48
	local plan = mapValue(config, "Loot", "Plan") or {}
	local itemsPerContender = tonumber(plan.ItemsPerContender) or 10
	local siteContenders = max(1, tonumber(plan.SiteContenders) or 24)
	local siteScale = maxContenders / siteContenders
	local startRadius = tonumber(mapValue(config, "Border", "StartRadius")) or tonumber(terrain.radii.play) or 1800
	local lootLimit = startRadius + (tonumber(mapValue(config, "Loot", "BorderMargin")) or -10)
	local maxRadius = min(lootLimit - RULES.EdgeMargin, G.radius - RULES.EdgeMargin)
	local crateMean = ((tonumber(mapValue(config, "Loot", "CrateItemsMin")) or 2) + (tonumber(mapValue(config, "Loot", "CrateItemsMax")) or 4)) / 2
	local groundChance = tonumber(mapValue(config, "Loot", "GroundSpawnChance")) or 0.65
	local refillRadius = tonumber(mapValue(config, "Loot", "SpireRefillRadius")) or 90

	local function add(m: any)
		m.look = m.look or toCentre(m.x, m.z)
		if not allowed(m, m.x, m.z) then
			table.insert(stats.problems, string.format("%s at (%.1f, %.1f) is planned off its floor (the layout's deck or horn floor has changed?)",
				m.source, m.x, m.z))
		end
		table.insert(markers, m)
		return m
	end
	-- no marker closer than `spacing` to one already planned
	local function clearOf(x: number, z: number, spacing: number): boolean
		local s2 = spacing * spacing
		for _, m in ipairs(markers) do
			local dx, dz = m.x - x, m.z - z
			if dx * dx + dz * dz < s2 then
				return false
			end
		end
		return true
	end

	-- 1. The Horn's floor: a tier-3 crate beside each rack, toward the middle of the floor along the bisector of the
	-- corner the rack stands in (the two racks of a corner keep their 6 studs), and tier-3 ground markers between.
	local horn = heart.horn
	local floorY = horn.floorY
	local corners = (terrain.plaza and terrain.plaza.starPoints) or { 0, 120, 240 }
	for i, spot in ipairs(horn.rackSpots) do
		local x, z = spot[1], spot[3]
		local b = bearingOf(x, z)
		local corner = corners[1]
		for _, c in ipairs(corners) do
			if angleBetween(b, c) < angleBetween(b, corner) then
				corner = c
			end
		end
		local ux, uz = polar(corner, 1) -- out toward the corner
		add({
			name = "T3_Crate", kind = "Crate", tier = 3, x = x - ux * 4.2, y = floorY, z = z - uz * 4.2,
			look = Vector3.new(-ux, 0, -uz), source = "HornFloor:Rack" .. i, group = "HornFloor", cover = "roof",
			from = 3, floorIsMesh = true, within = { poly = horn.floorTriangle, margin = 2.2 },
		})
	end
	local inradius = tonumber(horn.floorInradius) or 10.5
	for k = 0, 5 do
		local x, z = polar(30 + 60 * k, min(4, inradius * 0.4))
		add({
			name = "T3_Ground", kind = "Ground", tier = 3, x = x, y = floorY, z = z, source = "HornFloor:Floor" .. (k + 1),
			group = "HornFloor", cover = "roof", from = 3, floorIsMesh = true, within = { poly = horn.floorTriangle, margin = 1 },
		})
	end

	-- 2. The deck and the foot of the steps, mouth by mouth. u = out through the mouth, t = along the deck's edge.
	local deckY = heart.deckY
	local knollY = heart.knollY
	for i, mouth in ipairs(heart.mouths) do
		local b = mouth.bearing
		local ux, uz = polar(b, 1)
		local tx, tz = -uz, ux
		local stairTopR = sqrt(mouth.stairTop[1] ^ 2 + mouth.stairTop[3] ^ 2)
		local stairFootR = sqrt(mouth.stairFoot[1] ^ 2 + mouth.stairFoot[3] ^ 2)
		local halfStair = (tonumber(mouth.stairWidth) or 18) / 2
		local laneHalf = tonumber(mouth.lane and mouth.lane.halfWidth) or 9
		for _, side in ipairs({ -1, 1 }) do
			-- a tier-2 crate on the deck beside the landing, its front to the lane
			local radial, along = stairTopR - 5.5, side * (halfStair + 2.5)
			add({
				name = "T2_Crate", kind = "Crate", tier = 2, x = ux * radial + tx * along, y = deckY, z = uz * radial + tz * along,
				look = Vector3.new(ux, 0, uz), source = string.format("Deck:Mouth%.0f%s", b, if side < 0 then "L" else "R"),
				group = "Deck", from = 3, floorIsMesh = true,
				within = { poly = heart.deckPolygon, margin = 1.5 }, outside = { poly = horn.floorTriangle, margin = 3 },
				-- other spots on the deck to try when the first is taken by the mesh (radial, along)
				alternatives = { { stairTopR - 7.5, side * (halfStair + 2.5) }, { stairTopR - 5.5, side * (halfStair + 4.5) }, { stairTopR - 3.5, side * (halfStair + 1.5) } },
				frame = { ux = ux, uz = uz, tx = tx, tz = tz },
			})
			-- a tier-2 ground marker on the landing in front of the doorway, off its centre line
			local gr, ga = stairTopR - 2.6, side * (halfStair * 0.6)
			add({
				name = "T2_Ground", kind = "Ground", tier = 2, x = ux * gr + tx * ga, y = deckY, z = uz * gr + tz * ga,
				source = string.format("Deck:Landing%.0f%s", b, if side < 0 then "L" else "R"), group = "Deck", from = 3,
				floorIsMesh = true,
				within = { poly = heart.deckPolygon, margin = 1 }, outside = { poly = horn.floorTriangle, margin = 2 },
			})
			-- a tier-3 crate on the knoll at the foot of the steps, inside the lane's edge: the Feast drops it in
			local fr, fa = stairFootR + 5, side * (laneHalf - 2.5)
			local fx, fz = ux * fr + tx * fa, uz * fr + tz * fa
			add({
				name = "T3_Crate", kind = "Crate", tier = 3, x = fx, y = G.heightAt(fx, fz), z = fz,
				look = Vector3.new(ux, 0, uz), source = string.format("Steps:Mouth%.0f%s", b, if side < 0 then "L" else "R"),
				group = "Steps", cover = "sky", knollY = knollY,
			})
		end
	end

	-- 3. The supply bags: one tier-1 ground marker between every pair of plinths, 11 studs in front of the ring.
	local plaza = terrain.plaza or {}
	local plinthCount = tonumber(plaza.plinths) or tonumber(heart.plinth and heart.plinth.count) or 48
	local plinthStep = tonumber(plaza.plinthStep) or (360 / plinthCount)
	local plinthOffset = tonumber(plaza.plinthOffset) or 0
	local ringR = tonumber(heart.plinthRingRadius) or tonumber(terrain.radii.plinthRing) or 150
	for k = 0, plinthCount / 2 - 1 do
		local b = plinthOffset + (2 * k + 0.5) * plinthStep
		local x, z = polar(b, ringR - 11)
		add({
			name = "T1_Ground", kind = "Ground", tier = 1, x = x, y = G.heightAt(x, z), z = z,
			source = string.format("Bags:%03d", floor(b * 10 + 0.5)), group = "Bags",
		})
	end

	-- 4. The sites. A site's anchor is moved to the nearest ground good enough for a crate when it is in water, on a
	-- cliff or out of reach; its markers go on a golden-angle spiral round the anchor, each on good ground.
	-- Returns the anchor, how far it moved and the crate slope limit that found it. The rules relax in steps for a
	-- site on steep ground (a crest, the peak's shoulder): the usual slope within SiteSearch, then SteepExtra more,
	-- then SteepExtra more within twice the distance.
	local function findAnchor(x: number, z: number): (number?, number?, number, number)
		local steps = {
			{ RULES.CrateSlope, RULES.SiteSearch },
			{ RULES.CrateSlope + RULES.SteepExtra, RULES.SiteSearch },
			{ RULES.CrateSlope + RULES.SteepExtra, RULES.SiteSearch * 2 },
		}
		for _, step in ipairs(steps) do
			local slope, search = step[1], step[2]
			if G.good(x, z, slope, RULES.CrateWater, maxRadius) then
				return x, z, 0, slope
			end
			local c0, r0 = G.cellAt(x, z)
			local reachCells = ceil(search / G.CELL)
			local best, bx, bz = math.huge, nil, nil
			for dr = -reachCells, reachCells do
				for dc = -reachCells, reachCells do
					local cx, cz = G.centre(c0 + dc, r0 + dr)
					local d = sqrt((cx - x) ^ 2 + (cz - z) ^ 2)
					if d < best and d <= search and G.good(cx, cz, slope, RULES.CrateWater, maxRadius) then
						best, bx, bz = d, cx, cz
					end
				end
			end
			if bx then
				return bx, bz, best, slope
			end
		end
		return nil, nil, math.huge, RULES.CrateSlope
	end
	-- the k-th spot of the spiral round (ax, az) that is good ground and clear of the other markers
	local function spiral(ax: number, az: number, first: number, maxSlope: number, waterCells: number, spacing: number, salt: number): (number?, number?)
		for k = 0, 160 do
			local r = first + 2.5 * floor(k / 5)
			local x, z = polar((k + salt) * GOLDEN, r)
			x, z = ax + x, az + z
			if G.good(x, z, maxSlope, waterCells, maxRadius) and clearOf(x, z, spacing) then
				return x, z
			end
		end
		return nil, nil
	end

	local siteIds = {}
	local sitesById = {}
	for _, site in ipairs(layout.sites.items) do
		table.insert(siteIds, site.id)
		sitesById[site.id] = site
	end
	local runnerIndex = 0
	local unknownSites = {}
	for _, id in ipairs(siteIds) do
		local site = sitesById[id]
		local sx, sz = site.position[1], site.position[3]
		local ax, az, movedBy, crateSlope = findAnchor(sx, sz)
		if not ax then
			table.insert(stats.problems, string.format("site %s (%s): no good ground within %d studs; no markers", id, tostring(site.name), RULES.SiteSearch))
		else
			if movedBy > 0.5 or crateSlope > RULES.CrateSlope then
				table.insert(stats.moved, string.format("%s %.0f%s", id, movedBy,
					if crateSlope > RULES.CrateSlope then string.format(" (on a slope up to %d degrees)", crateSlope) else ""))
			end
			-- a crate's spot: the anchor's slope limit first, SteepExtra more when the spiral finds none
			local function crateSpot(first: number, salt: number): (number?, number?)
				local x, z = spiral(ax, az, first, crateSlope, RULES.CrateWater, RULES.SiteSpacing, salt)
				if not x then
					x, z = spiral(ax, az, first, RULES.CrateSlope + RULES.SteepExtra, RULES.CrateWater, RULES.SiteSpacing, salt)
				end
				return x, z
			end
			if string.sub(id, 1, 1) == "F" then
				-- a runner's cache: a tier-2 crate, its front (and its flag) to the Horn
				runnerIndex += 1
				add({
					name = "RunnerCache_" .. runnerIndex, kind = "Crate", tier = 2, runner = true, x = ax, y = G.heightAt(ax, az), z = az,
					source = "Runner:" .. id, group = "Runner",
				})
			else
				local spec = SITES[id]
				if not spec then
					table.insert(unknownSites, id)
					spec = { kind = "Unknown", ground = 1 }
				end
				local first = spec.first or RULES.SiteFirstRing
				local want = { crates = 0, ground = 0, prize = 0 }
				local got = { crates = 0, ground = 0, prize = 0 }
				if spec.prize then
					want.prize = 1
					-- at the anchor itself when it is free (the heart of the spiral, the glade's middle), else beside it
					local px, pz = ax, az
					if not clearOf(px, pz, RULES.SiteSpacing) then
						px, pz = crateSpot(first, 0)
					end
					if px then
						got.prize = 1
						add({
							name = "T3_Crate", kind = "Crate", tier = 3, x = px, y = G.heightAt(px, pz), z = pz,
							source = string.format("Site:%s:Prize", id), group = "Prize", anchor = { ax, az, first },
						})
					end
				end
				want.crates = ceil((spec.crates or 0) * siteScale - 1e-6)
				for i = 1, want.crates do
					local x, z = crateSpot(first, i)
					if x then
						got.crates += 1
						add({
							name = "T2_Crate", kind = "Crate", tier = 2, x = x, y = G.heightAt(x, z), z = z,
							look = if (x - ax) ^ 2 + (z - az) ^ 2 > 1 then Vector3.new(ax - x, 0, az - z).Unit else nil,
							source = string.format("Site:%s:Crate%d", id, i), group = "Site" .. string.sub(id, 1, 1),
							anchor = { ax, az, first },
						})
					end
				end
				want.ground = ceil((spec.ground or 0) * siteScale - 1e-6)
				for i = 1, want.ground do
					local x, z = spiral(ax, az, first, RULES.GroundSlope, RULES.GroundWater, RULES.SiteSpacing * 0.6, 40 + i)
					if x then
						got.ground += 1
						add({
							name = "T1_Ground", kind = "Ground", tier = 1, x = x, y = G.heightAt(x, z), z = z,
							source = string.format("Site:%s:Ground%d", id, i), group = "Site" .. string.sub(id, 1, 1),
						})
					end
				end
				if got.crates < want.crates or got.ground < want.ground or got.prize < want.prize then
					table.insert(stats.short, string.format("%s crates %d/%d ground %d/%d prize %d/%d", id, got.crates, want.crates,
						got.ground, want.ground, got.prize, want.prize))
				end
			end
		end
	end
	if #unknownSites > 0 then
		table.insert(stats.problems, "sites in the layout that this builder's table does not know (given 1 ground marker each): "
			.. table.concat(unknownSites, ", "))
	end
	for id in pairs(SITES) do
		if not sitesById[id] then
			table.insert(stats.problems, "site " .. id .. " is in this builder's table but not in the layout")
		end
	end

	-- 5. Scattered tier-1 ground markers: one density over the field, as many as bring a full round's expected loot to
	-- ItemsPerContender a head.
	local function expected(list: { any }): number
		local total = 0
		for _, m in ipairs(list) do
			total += if m.kind == "Crate" then crateMean else groundChance
		end
		return total
	end
	local fixedCount = #markers
	local fixedExpected = expected(markers)
	local target = itemsPerContender * maxContenders
	local scatterWanted = max(0, ceil((target - fixedExpected) / groundChance - 1e-6))
	local rng = Random.new(Loot.SEED)
	local from2, to2 = RULES.ScatterFrom ^ 2, maxRadius ^ 2
	local maxWeight = 0
	for _, w in pairs(RULES.RegionWeight) do
		maxWeight = max(maxWeight, w)
	end
	-- a coarse hash of the scattered markers, for the spacing test
	local bucket = RULES.ScatterSpacing
	local hash: { [number]: { any } } = {}
	local function key(x: number, z: number): number
		return floor(x / bucket) * 4096 + floor(z / bucket)
	end
	local function farFromScattered(x: number, z: number): boolean
		local s2 = RULES.ScatterSpacing ^ 2
		for dx = -1, 1 do
			for dz = -1, 1 do
				local list = hash[key(x + dx * bucket, z + dz * bucket)]
				if list then
					for _, m in ipairs(list) do
						if (m.x - x) ^ 2 + (m.z - z) ^ 2 < s2 then
							return false
						end
					end
				end
			end
		end
		return true
	end
	local scattered, tries = 0, 0
	local fixed = table.clone(markers)
	while scattered < scatterWanted and tries < scatterWanted * 400 + 2000 do
		tries += 1
		local r = sqrt(from2 + rng:NextNumber() * (to2 - from2))
		local a = rng:NextNumber() * 360
		local roll = rng:NextNumber()
		local x, z = polar(a, r)
		local col, row = G.cellAt(x, z)
		local weight = RULES.RegionWeight[G.regionName(col, row)] or 0
		if roll * maxWeight < weight and G.good(x, z, RULES.GroundSlope, RULES.GroundWater, maxRadius) and farFromScattered(x, z) then
			local clear = true
			local c2 = RULES.ScatterClear ^ 2
			for _, m in ipairs(fixed) do
				if (m.x - x) ^ 2 + (m.z - z) ^ 2 < c2 then
					clear = false
					break
				end
			end
			if clear then
				scattered += 1
				local m = add({
					name = "T1_Ground", kind = "Ground", tier = 1, x = x, y = G.heightAt(x, z), z = z,
					source = string.format("Scatter:%s:%d", G.regionName(col, row), scattered), group = "Scatter",
				})
				local k = key(x, z)
				hash[k] = hash[k] or {}
				table.insert(hash[k], m)
			end
		end
	end
	if scattered < scatterWanted then
		table.insert(stats.problems, string.format("scattered markers: %d of %d placed (%d tries)", scattered, scatterWanted, tries))
	end

	-- the layout's own answer for DropIn (no world needed): inside the Horn, or beside a sail's ground line
	local coreR = tonumber(horn.coreCornerRadius) or 21
	local function underHorn(x: number, z: number): boolean
		local r = sqrt(x * x + z * z)
		if r <= inradius then
			return true
		end
		for _, sail in ipairs(heart.sails or {}) do
			local hem = sail.hemTip
			local hemR = sqrt(hem[1] ^ 2 + hem[3] ^ 2)
			local sx, sz = polar(sail.bearing, 1)
			local along = x * sx + z * sz
			local across = abs(x * sz - z * sx)
			if along >= 0 and along <= hemR and across <= RULES.SailHalfWidth then
				return true
			end
		end
		return r <= coreR * 0.5
	end
	for _, m in ipairs(markers) do
		m.r = sqrt(m.x * m.x + m.z * m.z)
		if m.kind == "Crate" and m.tier == 3 and m.r <= refillRadius then
			m.feast = true
			if m.cover == "roof" or (m.cover ~= "sky" and underHorn(m.x, m.z)) then
				m.dropIn = false
			end
		end
	end

	stats.fixedCount = fixedCount
	stats.fixedExpected = fixedExpected
	stats.scatterWanted = scatterWanted
	stats.scattered = scattered
	stats.target = target
	stats.expected = expected(markers)
	stats.maxRadius = maxRadius
	stats.lootLimit = lootLimit
	stats.maxContenders = maxContenders
	stats.itemsPerContender = itemsPerContender
	stats.siteScale = siteScale
	stats.crateMean = crateMean
	stats.groundChance = groundChance
	stats.refillRadius = refillRadius
	stats.reachCount = G.reachCount
	stats.ground = G
	stats.config = config
	stats.data = data
	return markers, stats
end

----------------------------------------------------------------------------------------------------
-- the world: seat a planned marker on what is really there
----------------------------------------------------------------------------------------------------
local function rayParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

-- The real floor under a planned marker: (y, instance) or nil when the world has nothing there.
local function floorAt(m: any, x: number, z: number, y: number, offset: Vector3, params: RaycastParams): (number?, Instance?)
	-- a marker of the Horn names how far over its floor the ray starts (it stands under the sails or beside a wall);
	-- on the open ground the ray comes from high up, so a mesh over the spot (the peak, a hedge, a boulder) is met first
	-- and the spot counts as taken
	local from = m.from or RULES.CoverProbe
	local origin = Vector3.new(x, y + from, z) + offset
	local hit = workspace:Raycast(origin, Vector3.new(0, -(from + 14), 0), params)
	if hit then
		return hit.Position.Y - offset.Y, hit.Instance
	end
	return nil, nil
end

local probe: Part? = nil
local function crateSpotClear(cf: CFrame, exclude: { Instance }): boolean
	local p = probe
	if not p then
		p = Instance.new("Part")
		p.Name = "Map1LootProbe"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = PROBE_SIZE
		probe = p
	end
	p.CFrame = cf * CFrame.new(0, 1.25, 0)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	overlap.RespectCanCollide = true
	for _, part in ipairs(workspace:GetPartsInPart(p, overlap)) do
		if not part:IsA("Terrain") then
			return false
		end
	end
	return true
end

-- Seats every planned marker. Returns counts; sets m.seated ("world" | "data" | "blocked"), m.y, m.x, m.z, m.dropIn.
local function seatAll(markers: { any }, stats: { [string]: any }, opts: { [string]: any }): { [string]: number }
	local offset: Vector3 = opts.offset or Vector3.zero
	local G = stats.ground
	local config = stats.config
	local dropHeight = tonumber(mapValue(config, "Loot", "FeastDropHeight")) or 55
	local exclude: { Instance } = {}
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	if loot then
		table.insert(exclude, loot)
	end
	if typeof(opts.parent) == "Instance" then
		table.insert(exclude, opts.parent)
	end
	local params = rayParams(exclude)
	local scatter = arena and arena:FindFirstChild("Scatter")
	local counts = { world = 0, data = 0, blocked = 0, moved = 0, dropInFalse = 0, covered = 0, dropped = 0 }
	stats.notes = stats.notes or {}

	local function tryAt(m: any, x: number, z: number, y: number): (boolean, number?)
		local fy, inst = floorAt(m, x, z, y, offset, params)
		if not fy then
			return false, nil -- nothing there: the data decides
		end
		if abs(fy - y) > RULES.SeatTolerance then
			return false, fy -- something stands there, or the terrain is not the data's
		end
		if m.floorIsMesh and inst and inst:IsA("Terrain") then
			return false, fy -- the deck or the Horn's floor was expected
		end
		-- a plant or a stone is never a floor: a boulder under 3 studs high passed the height test above, and a crate
		-- stood on top of it (the North Beach, 18 Nov)
		if inst and scatter and inst:IsDescendantOf(scatter) then
			return false, fy
		end
		if m.kind == "Crate" then
			local look: Vector3 = m.look
			local cf = CFrame.lookAt(Vector3.new(x, fy, z) + offset, Vector3.new(x, fy, z) + offset + look)
			if not crateSpotClear(cf, exclude) then
				return false, fy
			end
		end
		return true, fy
	end

	for _, m in ipairs(markers) do
		local ok, fy = tryAt(m, m.x, m.z, m.y)
		if ok then
			m.y = fy
			m.seated = "world"
			counts.world += 1
		elseif fy == nil then
			m.seated = "data"
			counts.data += 1
		else
			-- the spot is taken: the marker's own alternatives, then a few steps round it
			local found = false
			local candidates: { { number } } = {}
			if m.alternatives and m.frame then
				for _, alt in ipairs(m.alternatives) do
					local x = m.frame.ux * alt[1] + m.frame.tx * alt[2]
					local z = m.frame.uz * alt[1] + m.frame.tz * alt[2]
					if allowed(m, x, z) then
						table.insert(candidates, { x, z, m.y })
					end
				end
			end
			local slope = if m.kind == "Crate" then RULES.CrateSlope else RULES.GroundSlope
			local water = if m.kind == "Crate" then RULES.CrateWater else RULES.GroundWater
			for k = 1, 24 do
				local dx, dz = polar(k * GOLDEN, 3 + 1.5 * floor(k / 4))
				local x, z = m.x + dx, m.z + dz
				if m.floorIsMesh then
					if allowed(m, x, z) then
						table.insert(candidates, { x, z, m.y })
					end
				elseif G.good(x, z, slope, water, stats.maxRadius) then
					table.insert(candidates, { x, z, G.heightAt(x, z) })
				end
			end
			for _, c in ipairs(candidates) do
				local good, y = tryAt(m, c[1], c[2], c[3])
				if good then
					m.x, m.z, m.y = c[1], c[2], y
					m.seated = "world"
					counts.world += 1
					counts.moved += 1
					found = true
					break
				end
			end
			if not found then
				m.seated = "blocked"
				counts.blocked += 1
				-- A scattered marker with no clear spot is left out (Loot.build): under the peak's shell three of them
				-- lay 100 to 200 studs inside the mesh, out of reach, and every rebuild brought them back. A designed
				-- marker (the Horn, a site, a runner's cache) stays at its planned place and is listed as a problem.
				if m.group == "Scatter" then
					m.dropped = true
					counts.dropped += 1
					table.insert(stats.notes, string.format("%s at (%.0f, %.0f): no clear spot on the real ground (data y %.1f, world y %.1f)",
						m.source, m.x, m.z, m.y, fy))
				else
					table.insert(stats.problems, string.format("%s at (%.0f, %.0f): no clear spot on the real ground (data y %.1f, world y %.1f); left at its planned place",
						m.source, m.x, m.z, m.y, fy))
				end
			end
		end
		-- the Feast: anything solid over a tier-3 crate near the centre means it is restocked in place
		if m.feast then
			local top = Vector3.new(m.x, m.y + dropHeight + 2, m.z) + offset
			local hit = workspace:Raycast(top, Vector3.new(0, -(dropHeight - 3), 0), params)
			if hit then
				counts.covered += 1
				m.dropIn = false
			end
		end
		if m.dropIn == false then
			counts.dropInFalse += 1
		end
	end
	return counts
end

----------------------------------------------------------------------------------------------------
-- build
----------------------------------------------------------------------------------------------------
local function lootFolder(): Folder
	local data = ServerStorage:FindFirstChild("ArenaData")
	if not data then
		data = Instance.new("Folder")
		data.Name = "ArenaData"
		data.Parent = ServerStorage
	end
	local folder = data:FindFirstChild("LootSpawns")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LootSpawns"
		folder.Parent = data
	end
	return folder :: Folder
end

local function ownMarker(inst: Instance): boolean
	local source = inst:GetAttribute("Source")
	return type(source) == "string" and string.sub(source, 1, #Loot.SOURCE + 1) == Loot.SOURCE .. ":"
end
Loot.ownMarker = ownMarker

local function makePart(m: any, offset: Vector3): Part
	local p = Instance.new("Part")
	p.Name = m.name
	p.Size = MARKER_SIZE
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local centre = Vector3.new(m.x, m.y + MARKER_SIZE.Y / 2, m.z) + offset
	p.CFrame = CFrame.lookAt(centre, centre + m.look)
	p:SetAttribute("Kind", m.kind)
	p:SetAttribute("Tier", m.tier)
	p:SetAttribute("Source", Loot.SOURCE .. ":" .. m.source)
	if m.runner then
		p:SetAttribute("Runner", true)
	end
	if m.dropIn == false then
		p:SetAttribute("DropIn", false)
	end
	CollectionService:AddTag(p, Loot.TAG)
	return p
end

-- Expected loot inside each round size's ring: { n, radius, crates, ground, items, perHead }.
function Loot.table(markers: { any }, stats: { [string]: any }, sizes: { number }?): { any }
	local config = stats.config
	local margin = tonumber(mapValue(config, "Loot", "BorderMargin")) or -10
	local rows = {}
	for _, n in ipairs(sizes or { 1, 2, 4, 8, 12, 16, 24, 32, 48 }) do
		if n <= stats.maxContenders then
			local radius = startRadiusFor(config, n)
			local limit = radius + margin
			local crates, ground = 0, 0
			for _, m in ipairs(markers) do
				if (m.r or sqrt(m.x * m.x + m.z * m.z)) <= limit then
					if m.kind == "Crate" then
						crates += 1
					else
						ground += 1
					end
				end
			end
			local items = crates * stats.crateMean + ground * stats.groundChance
			table.insert(rows, { n = n, radius = radius, crates = crates, ground = ground, items = items, perHead = items / n })
		end
	end
	return rows
end

function Loot.build(options: { [string]: any }?): (string, { [string]: any })
	assert(not RunService:IsRunning(), "Map1.Loot builds in Edit mode only")
	local opts = options or {}
	local started = os.clock()
	local markers, stats = Loot.plan(opts)
	local offset: Vector3 = opts.offset or Vector3.zero
	local parent: Instance? = nil
	if not opts.dryRun then
		parent = opts.parent or lootFolder()
	end

	local seat = { world = 0, data = #markers, blocked = 0, moved = 0, dropInFalse = 0, covered = 0, dropped = 0 }
	if opts.seat ~= false then
		seat = seatAll(markers, stats, { offset = offset, parent = parent })
		-- blocked scattered markers are not built (and not counted in the tables below)
		if seat.dropped > 0 then
			local kept = {}
			for _, m in ipairs(markers) do
				if not m.dropped then
					table.insert(kept, m)
				end
			end
			markers = kept
		end
	else
		for _, m in ipairs(markers) do
			m.seated = "data"
			if m.dropIn == false then
				seat.dropInFalse += 1
			end
		end
	end

	local foreign = 0
	if parent then
		for _, child in ipairs(parent:GetChildren()) do
			if opts.clearAll or ownMarker(child) then
				child:Destroy()
			elseif child:IsA("BasePart") and child:GetAttribute("Kind") ~= nil then
				foreign += 1
			end
		end
		local box = Instance.new("Folder") -- built outside the DataModel, then moved in one step per chunk
		for i, m in ipairs(markers) do
			makePart(m, offset).Parent = box
			if i % 200 == 0 then
				for _, part in ipairs(box:GetChildren()) do
					part.Parent = parent
				end
				task.wait()
			end
		end
		for _, part in ipairs(box:GetChildren()) do
			part.Parent = parent
		end
		box:Destroy()
		parent:SetAttribute("Map", Loot.MAP)
		parent:SetAttribute("LootSeed", Loot.SEED)
		parent:SetAttribute("LootMarkers", #markers)
	end

	-- the report
	local byGroup: { [string]: { crates: number, ground: number } } = {}
	local order = {}
	local crates, ground, tier3Near, runners, farthest = 0, 0, 0, 0, 0
	for _, m in ipairs(markers) do
		local g = byGroup[m.group]
		if not g then
			g = { crates = 0, ground = 0 }
			byGroup[m.group] = g
			table.insert(order, m.group)
		end
		if m.kind == "Crate" then
			g.crates += 1
			crates += 1
		else
			g.ground += 1
			ground += 1
		end
		if m.tier == 3 and m.r <= stats.refillRadius then
			tier3Near += 1
		end
		if m.runner then
			runners += 1
		end
		farthest = max(farthest, m.r)
	end
	local lines = {}
	table.insert(lines, string.format("Map1.Loot: %d markers (%d crates, %d ground)%s in %.1f s", #markers, crates, ground,
		if parent then " -> " .. parent:GetFullName() else " (dry run: nothing built)", os.clock() - started))
	local groups = {}
	for _, name in ipairs(order) do
		table.insert(groups, string.format("%s %d+%d", name, byGroup[name].crates, byGroup[name].ground))
	end
	table.insert(lines, "  by group (crates+ground): " .. table.concat(groups, ", "))
	table.insert(lines, string.format("  plan: %d contenders x %g items = %g; fixed markers give %.1f; %d scattered asked, %d placed; the set gives %.1f (a crate = %g, a ground marker = %g)",
		stats.maxContenders, stats.itemsPerContender, stats.target, stats.fixedExpected, stats.scatterWanted, stats.scattered,
		stats.expected, stats.crateMean, stats.groundChance))
	table.insert(lines, string.format("  tier-3 markers within %d of the centre: %d (%d with DropIn = false); runner's caches: %d; farthest marker r %.0f (limit %d)",
		stats.refillRadius, tier3Near, seat.dropInFalse, runners, farthest, stats.lootLimit))
	table.insert(lines, string.format("  seated on the world: %d (moved to a clear spot: %d); by the data alone: %d; blocked: %d (%d of them scattered markers, left out); tier-3 crates with something over them: %d",
		seat.world, seat.moved, seat.data, seat.blocked, seat.dropped, seat.covered))
	for _, note in ipairs(stats.notes or {}) do
		table.insert(lines, "  left out: " .. note)
	end
	local rows = Loot.table(markers, stats)
	local cells = {}
	for _, row in ipairs(rows) do
		table.insert(cells, string.format("%d: r %d, %d+%d, %.0f items, %.1f a head", row.n, row.radius, row.crates, row.ground, row.items, row.perHead))
	end
	table.insert(lines, "  by round size (contenders: start radius, crates+ground inside, expected items): " .. table.concat(cells, " | "))
	if #stats.moved > 0 then
		table.insert(lines, "  site anchors moved to good ground (id, studs): " .. table.concat(stats.moved, ", "))
	end
	if #stats.short > 0 then
		table.insert(lines, "  sites with fewer markers than planned: " .. table.concat(stats.short, "; "))
	end
	if foreign > 0 then
		table.insert(lines, string.format("  WARNING: %d markers in the folder were not made by this builder (another arena's?). Loot.build({ clearAll = true }) removes them.", foreign))
	end
	for _, problem in ipairs(stats.problems) do
		table.insert(lines, "  PROBLEM: " .. problem)
	end
	stats.seat = seat
	stats.rows = rows
	stats.markers = markers
	stats.foreign = foreign
	stats.crates = crates
	stats.groundMarkers = ground
	stats.tier3Near = tier3Near
	return table.concat(lines, "\n"), stats
end

return Loot
