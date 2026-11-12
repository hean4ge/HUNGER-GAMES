--[[
	ArenaLayout (v2) - the single source of truth for where things are in the arena: the CLASSIC FOREST ARENA.
	World generation (ServerStorage.WorldGen.TerrainGen), the set dresser (Populate), the border, the compass,
	ambience and the round flow all read it. TerrainGen carves the terrain from these numbers, so if you move
	something here, re-run TerrainGen (see its header) and re-check the dependants.

	CONVENTIONS
	  Angles are degrees clockwise from north. North is -Z, east is +X.
	  polar(angle, r, y) = Vector3(sin(a) * r, y, -cos(a) * r) around Center (0, 0, 0).
	  Heights are absolute studs. Densities are "items per 1000 square studs".

	THE MAP (centre outwards)
	  Meadow     r 0..~150 (lobed edge, meadowEdge(angle)): open grassland, 2-5 studs of relief, tilting gently
	             toward the lake. The Spire plaza is a flat disc r <= PlazaRadius (62) at PlazaY (46).
	             24 launch plates at r = 52 (Plates[i]); a launch tube is carved under each one.
	  Forest     the ring between the meadow and the mountains: rolling eroded hills, ridges, gullies, knolls,
	             rock outcrops and a few clearings (Clearings).
	  Lake       S/SE, closest shore ~190 from the centre: beach toward the meadow (NW shore), the river mouth (NE),
	             rocky granite banks (E/SE), reed shallows (SW, where the marsh outflow enters), an island.
	  Gorge      N/NNE: the river rises at the mountain foot (r ~630), cuts a winding stratified gorge with
	             step-pool cascades through the highland forest, falls 32 studs into a plunge pool in a horseshoe
	             amphitheatre (FallsPool), then meanders E/SE to the lake. Fords, a fallen-log spot and a footbridge
	             spot are in Crossings.
	  Cliffs     W/NW: an escarpment (layered faces, overhangs, scree aprons) with three caves (Caves). A creek
	             springs at its foot, runs past the CreekCave (the hidden healing spot) and cascades into the marsh.
	  Field      E/NE beyond the river: a broad open slope rising east (tall golden grass), a few lone trees/boulders.
	  Marsh      SW: low wetland at MarshLevel with pools, mud, peat hummocks and a dead-tree stand; it drains to the
	             lake through a sluggish outflow channel.
	  Mountains  rise steeply from ~r 660-690 (the border starts at r 640, the invisible Boundary is at r ~712). A
	             continuous cliff band (MountainWall) rings the arena between the two: no way out on foot, by jumping
	             or by mantling.

	HEIGHT / GROUND QUERIES (edit time and on the server; on clients only where terrain has streamed in)
	  groundAt(x, z) -> (y, normal, material)?   raycast on Terrain only, water ignored (the top solid surface;
	                                             over a cave this is the rock above it - use Caves for interiors)
	  heightAt(x, z) -> number?                  same y (falls back to the TerrainData grid when nothing is hit)
	  normalAt(x, z) -> Vector3                  surface normal (Vector3.yAxis when unknown)
	  slopeAt(x, z) -> degrees                   0 = flat
	  waterAt(x, z) -> (waterY?, depth)          terrain water surface above the ground there, and its depth
	  isWater(x, z) -> (boolean, waterY?, depth) true where there is terrain water over the ground
	  moistureAt(x, z) -> 0..1                   wetness (distance/height to water, drainage lines); grid-backed
	  distanceToCliff(position) -> studs         flat distance to the nearest steep (> 50 deg) ground; grid-backed
	  distanceToWater(position) -> studs         flat distance to the nearest water body (analytic)
	  distanceToRiver(position) -> (d, waterY)   kept from v1: river centreline incl. the gorge stream
	  distanceToTrail(position) -> studs         kept from v1
	  forestEdgeDistance(position) -> studs      distance to the nearest open area (meadow, field, lake, marsh,
	                                             clearings); small values = forest edge (boost bushes there)
	  getBiome(position) -> "Meadow"|"Forest"|"Lake"|"Gorge"|"Cliffs"|"Field"|"Marsh"|"Mountains"|"Lobby"
	  isExcluded(position, rule?) -> (boolean, reason?)   the standard exclusion zones (see Exclusions)
	  "Grid-backed" = read from ServerStorage.WorldGen.TerrainData (8-stud grid written by TerrainGen; server and
	  edit time only). Without it they fall back to analytic approximations.

	SET DRESSING DATA: Plates, PlateTube, POIs (+ POIHeights, measured), POIKits, Caves, Crossings (+ CrossingHeights),
	Trails, Clearings, Scatter (per-biome rules naming the realistic assets), AssetInfo (their sizes), Exclusions,
	LootZones, lootTierAt(position), dangerAt(position), MistHollows. Each is documented where it is defined below.
]]
local RunService = game:GetService("RunService")

local ArenaLayout = {}

ArenaLayout.Version = 2
ArenaLayout.Seed = 1337 -- kept from v1: the lobby island and the v1 Populate scripts are seeded by it
ArenaLayout.TerrainSeed = 2611 -- noise seed of the v2 terrain

----------------------------------------------------------------------------------------------------
-- Core numbers
----------------------------------------------------------------------------------------------------
ArenaLayout.Center = Vector3.new(0, 0, 0)
ArenaLayout.PlazaY = 46 -- the flat Spire plaza (terrain surface)
ArenaLayout.MeadowY = 46 -- the meadow undulates 2-5 studs around this
ArenaLayout.BaseHeight = 46 -- v1 name kept (= PlazaY): border centre height, fallback plinth ring, dummies
ArenaLayout.WaterLevel = 34 -- the lake surface (v1 name kept)
ArenaLayout.LakeLevel = 34
-- Water levels sit in the lower half of a 4-stud voxel layer where shallow water matters: Roblox only shows a water
-- surface whose voxel holds no solid, so a level 3.5 studs into a layer needs 1.6 studs of depth to show at all.
ArenaLayout.MarshLevel = 36.5 -- marsh pools (36.5 = 0.5 into a layer: shallow pools render)
ArenaLayout.SnowLine = 300 -- old snow above roughly this height on the mountains

ArenaLayout.PlazaRadius = 62 -- flat disc for the 120-stud SpirePlatform (unrotated, origin = Center)
ArenaLayout.SpireRadius = 28
ArenaLayout.PlinthRingRadius = 52
ArenaLayout.PlinthCount = 24
ArenaLayout.MeadowRadius = 150 -- nominal; the real edge is meadowEdge(angle) (about 125..178)
ArenaLayout.ClearingRadius = 150 -- v1 name kept (= MeadowRadius)
ArenaLayout.PlayRadius = 640 -- the border starts here
ArenaLayout.MountainRadius = 680 -- the mountain wall rises steeply from about here
ArenaLayout.BoundaryRadius = 712 -- invisible backstop wall (workspace.Arena.Boundary)
-- The mountain wall: a cliff band all round whose foot is at TerrainGen.wallFoot(angle) (r footMin..footMax). It
-- starts with a sheer `step`, rises to `height` at ~75 degrees, then ~54 degrees for `upperRise` more: no walkable
-- slope, no ledge, nothing to mantle. Keep set dressing (and anything climbable) off it.
ArenaLayout.MountainWall = { footMin = 651, footMax = 700, step = 18, height = 34, upperRise = 30 }
ArenaLayout.TerrainRadius = 920 -- terrain is generated out to here
ArenaLayout.LobbyPosition = Vector3.new(2600, 160, 0) -- top surface centre of the lobby island
ArenaLayout.LobbyRadius = 90

local CX, CZ = ArenaLayout.Center.X, ArenaLayout.Center.Z
local sin, cos, rad, deg, sqrt, abs, min, max, floor = math.sin, math.cos, math.rad, math.deg, math.sqrt, math.abs, math.min, math.max, math.floor
local atan2 = math.atan2
local HUGE = math.huge

function ArenaLayout.polar(angleDeg: number, radius: number, y: number?): Vector3
	local a = rad(angleDeg)
	return Vector3.new(CX + sin(a) * radius, y or 0, CZ - cos(a) * radius)
end
local polar = ArenaLayout.polar

function ArenaLayout.angleOf(position: Vector3): number
	return deg(atan2(position.X - CX, -(position.Z - CZ))) % 360
end

function ArenaLayout.flatDistance(position: Vector3): number
	local dx, dz = position.X - CX, position.Z - CZ
	return sqrt(dx * dx + dz * dz)
end

local function angleXZ(x: number, z: number): number
	return deg(atan2(x - CX, -(z - CZ))) % 360
end

local function smooth(e0: number, e1: number, x: number): number
	local t = (x - e0) / (e1 - e0)
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end
ArenaLayout._smooth = smooth

----------------------------------------------------------------------------------------------------
-- Launch plates (24, r = 52, plate i at angle (i - 1) * 15, LookVector toward the Spire)
----------------------------------------------------------------------------------------------------
-- Plates[i]: CFrame at the plaza surface (Y = PlazaY), facing the centre. A plate whose bottom face sits on
-- this CFrame is flush with the plaza. Under each plate TerrainGen carves a vertical tube (PlateTube) so the
-- plates can rise out of the ground at the start of a round (the round/day-night owner animates them).
-- NOTE: a SpirePlatform mesh laid over the plaza (r <= 60) covers the tubes: it needs openings at the plates
-- (or the plates rise through it / stand on it, PlateTube.platformTop gives its top offset).
ArenaLayout.Plates = {}
for i = 1, ArenaLayout.PlinthCount do
	local p = polar((i - 1) * 360 / ArenaLayout.PlinthCount, ArenaLayout.PlinthRingRadius, ArenaLayout.PlazaY)
	ArenaLayout.Plates[i] = CFrame.lookAt(p, Vector3.new(CX, ArenaLayout.PlazaY, CZ))
end
ArenaLayout.PlateTube = {
	-- guaranteed clear radius round every plate axis, from the floor to the plaza. Terrain voxels cannot make 24
	-- separate clean shafts 13.6 studs apart (a full voxel reaches ~1.8 studs into its empty neighbour), so
	-- TerrainGen opens ONE annular trench under the plate band (every cell meeting r = 52 +- (radius + 1.8), floor
	-- floorY) and the realistic SpirePlatform (pivot (0, PlazaY, 0), unrotated) covers it with its deck colliders,
	-- leaving the 24 granite-lined openings (r 3.4). Keep the SpirePlatform in place whenever the trench exists.
	radius = 3.6,
	depth = 12, -- from PlazaY down to the tube floor (the SpirePlatform mesh lines each tube with granite to -11.4)
	floorY = ArenaLayout.PlazaY - 12, -- solid floor of every tube
	platformTop = 0.6, -- top of the SpirePlatform mesh above PlazaY (its tread level)
}
function ArenaLayout.platePosition(i: number): Vector3
	return ArenaLayout.Plates[i].Position
end

----------------------------------------------------------------------------------------------------
-- Geometry helpers (polylines and polygons)
----------------------------------------------------------------------------------------------------
-- Catmull-Rom through control points (x, z), linear attributes between them, sampled every `step` studs.
-- controls: { { x, z, level, hw, depth, tag? } } -> samples { { x, z, y (level), hw, depth, s, tag?, ci } }
local function sampleSpline(controls, step: number)
	local out = {}
	local n = #controls
	local along = 0
	local lastX, lastZ
	for i = 1, n - 1 do
		local c0 = controls[max(i - 1, 1)]
		local c1, c2 = controls[i], controls[i + 1]
		local c3 = controls[min(i + 2, n)]
		local segLen = sqrt((c2[1] - c1[1]) ^ 2 + (c2[2] - c1[2]) ^ 2)
		local k = max(2, math.ceil(segLen / step))
		for j = 0, k - 1 do
			local t = j / k
			local t2, t3 = t * t, t * t * t
			local x = 0.5 * ((2 * c1[1]) + (-c0[1] + c2[1]) * t + (2 * c0[1] - 5 * c1[1] + 4 * c2[1] - c3[1]) * t2 + (-c0[1] + 3 * c1[1] - 3 * c2[1] + c3[1]) * t3)
			local z = 0.5 * ((2 * c1[2]) + (-c0[2] + c2[2]) * t + (2 * c0[2] - 5 * c1[2] + 4 * c2[2] - c3[2]) * t2 + (-c0[2] + 3 * c1[2] - 3 * c2[2] + c3[2]) * t3)
			if lastX then
				along += sqrt((x - lastX) ^ 2 + (z - lastZ) ^ 2)
			end
			lastX, lastZ = x, z
			table.insert(out, {
				x = x,
				z = z,
				y = c1[3] + (c2[3] - c1[3]) * t,
				hw = c1[4] + (c2[4] - c1[4]) * t,
				depth = c1[5] + (c2[5] - c1[5]) * t,
				s = along,
				tag = (j == 0) and c1[6] or nil,
				ci = i + t,
			})
		end
	end
	local cl = controls[n]
	along += sqrt((cl[1] - lastX) ^ 2 + (cl[2] - lastZ) ^ 2)
	table.insert(out, { x = cl[1], z = cl[2], y = cl[3], hw = cl[4], depth = cl[5], s = along, tag = cl[6], ci = n })
	return out
end
ArenaLayout._sampleSpline = sampleSpline

-- Nearest point on a sample polyline: (flat distance, interpolated sample fields, segment index, u)
local function nearestOnSamples(samples, x: number, z: number)
	local best, bi, bu = HUGE, 1, 0
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local l2 = dx * dx + dz * dz
		local u = 0
		if l2 > 1e-9 then
			u = ((x - a.x) * dx + (z - a.z) * dz) / l2
			if u < 0 then
				u = 0
			elseif u > 1 then
				u = 1
			end
		end
		local qx, qz = x - (a.x + dx * u), z - (a.z + dz * u)
		local d2 = qx * qx + qz * qz
		if d2 < best then
			best, bi, bu = d2, i, u
		end
	end
	return sqrt(best), bi, bu
end
ArenaLayout._nearestOnSamples = nearestOnSamples

local function lerpSample(samples, i: number, u: number, field: string): number
	local a, b = samples[i], samples[min(i + 1, #samples)]
	return a[field] + (b[field] - a[field]) * u
end
ArenaLayout._lerpSample = lerpSample

-- Polygon (list of {x, z}) helpers
local function pointInPolygon(poly, x: number, z: number): boolean
	local inside = false
	local n = #poly
	local j = n
	for i = 1, n do
		local xi, zi = poly[i][1], poly[i][2]
		local xj, zj = poly[j][1], poly[j][2]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function distanceToPolygonEdge(poly, x: number, z: number): number
	local best = HUGE
	local n = #poly
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local l2 = dx * dx + dz * dz
		local u = 0
		if l2 > 1e-9 then
			u = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / l2, 0, 1)
		end
		local qx, qz = x - (a[1] + dx * u), z - (a[2] + dz * u)
		local d2 = qx * qx + qz * qz
		if d2 < best then
			best = d2
		end
	end
	return sqrt(best)
end

-- Signed distance to a polygon: negative inside.
local function signedPolygonDistance(poly, x: number, z: number): number
	local d = distanceToPolygonEdge(poly, x, z)
	if pointInPolygon(poly, x, z) then
		return -d
	end
	return d
end
ArenaLayout._pointInPolygon = pointInPolygon
ArenaLayout._signedPolygonDistance = signedPolygonDistance

local function polarPolygon(list)
	local poly = {}
	for i, p in ipairs(list) do
		local v = polar(p[1], p[2])
		poly[i] = { v.X, v.Z }
	end
	return poly
end

-- control list in polar form { angle, r, level, hw, depth, tag? } -> world {x, z, ...}
local function polarControls(list)
	local out = {}
	for i, c in ipairs(list) do
		local v = polar(c[1], c[2])
		out[i] = { v.X, v.Z, c[3], c[4], c[5], c[6] }
	end
	return out
end

-- Steps a gradient section of a stream into flat pools with small cascades (`drop` studs each).
-- Cascades sit where the smooth level crosses a multiple of `drop`; the stepped level is never above the smooth one
-- by more than `drop`, and is exactly the smooth level at the section ends.
local function stepLevels(samples, fromS: number, toS: number, drop: number)
	local first, last
	for i, smp in ipairs(samples) do
		if smp.s >= fromS and smp.s <= toS then
			first = first or i
			last = i
		end
	end
	if not first then
		return
	end
	local top = samples[first].y
	for i = first, last do
		local smp = samples[i]
		smp.smoothY = smp.y
		local k = floor((top - smp.y) / drop + 1e-6)
		local stepped = top - k * drop
		if i == last then
			stepped = smp.y
		end
		smp.cascade = (i > first) and (samples[i - 1].y - stepped > 0.01) or false
		smp.y = stepped
	end
end

----------------------------------------------------------------------------------------------------
-- The meadow edge and the mountain edge (functions of angle)
----------------------------------------------------------------------------------------------------
function ArenaLayout.meadowEdge(angleDeg: number): number
	local a = angleDeg
	return 150 + 14 * sin(rad(3 * a + 40)) + 9 * sin(rad(5 * a + 160)) + 5 * sin(rad(9 * a + 20))
end

function ArenaLayout.mountainEdge(angleDeg: number): number
	local a = angleDeg
	return 676 + 10 * sin(rad(4 * a + 30)) + 6 * sin(rad(7 * a + 100))
end

----------------------------------------------------------------------------------------------------
-- The river: spring (r ~630, N) -> stratified gorge with step-pool cascades -> waterfall -> plunge pool ->
-- meanders E/SE -> lake. Control points { angle, r, waterY, halfWidth, depth, tag }.
----------------------------------------------------------------------------------------------------
local RIVER_CONTROLS = {
	{ 3.5, 632, 156, 2.2, 0.8, "spring" },
	{ 5, 610, 151, 3.0, 1.0 },
	{ 8, 590, 142, 3.6, 1.2, "gorge" }, -- the gorge starts here
	{ 12, 568, 130, 4.0, 1.4 },
	{ 17, 548, 120, 4.4, 1.5 },
	{ 14, 526, 111, 4.4, 1.5 },
	{ 18, 506, 103, 4.6, 1.6 },
	{ 25, 488, 97, 4.8, 1.6 },
	{ 24, 466, 92, 4.8, 1.7 },
	{ 29, 446, 89, 5.0, 1.7 },
	{ 33, 426, 87, 5.2, 1.6 },
	{ 34, 410, 86, 5.4, 1.2, "lip" }, -- waterfall lip
	{ 36, 386, 54, 7.0, 6.0, "pool" }, -- plunge pool centre
	{ 44, 366, 53.2, 6.5, 2.6 },
	{ 52, 350, 52.2, 7.0, 2.8 },
	{ 59, 332, 49.9, 7.4, 2.8, "ford" }, -- NorthFord (TerrainGen widens and shallows the bed around fords; a ford level sits <= 2 studs into a voxel layer, or it renders deeper)
	{ 68, 322, 49.8, 7.5, 3.0 },
	{ 78, 330, 48.4, 7.8, 3.2 },
	{ 88, 322, 47.0, 8.0, 3.0 },
	{ 97, 308, 45.6, 8.2, 3.0, "ford" }, -- EastFord
	{ 106, 304, 44.0, 8.4, 3.2 },
	{ 115, 298, 42.2, 8.6, 3.2 },
	{ 123, 286, 40.6, 8.8, 3.0, "ford" }, -- LakeFord (40.6, not 40.0: a level on a voxel boundary needs 2 studs of depth)
	{ 130, 272, 38.0, 9.0, 2.8 },
	{ 137, 260, 36.0, 9.5, 2.4 },
	{ 143, 250, 34.0, 10.0, 2.0, "mouth" },
}

local River = {}
ArenaLayout.River = River
River.width = 16 -- nominal lowland width (it varies 13-22; gorge stream 7-11; fords are wider and shallow)
River.depth = 3.2 -- nominal lowland depth
River.controls = polarControls(RIVER_CONTROLS)
River.samples = sampleSpline(River.controls, 4)
do
	-- find the gorge start, the lip and the pool along the samples
	local gorgeS, lipS, poolS
	for _, smp in ipairs(River.samples) do
		if smp.tag == "gorge" then
			gorgeS = smp.s
		elseif smp.tag == "lip" then
			lipS = smp.s
		elseif smp.tag == "pool" then
			poolS = smp.s
		end
	end
	River.gorgeFromS, River.lipS, River.poolS = gorgeS, lipS, poolS
	-- step-pool cascades in the gorge (3.5-stud drops) and on the spring run (2.5)
	stepLevels(River.samples, 0, gorgeS, 2.5)
	stepLevels(River.samples, gorgeS, lipS, 3.5)
	-- the fall: between the lip and the pool every sample belongs to the waterfall
	for _, smp in ipairs(River.samples) do
		smp.gorge = (smp.s >= gorgeS - 8 and smp.s <= lipS) and 1 or 0
		smp.fall = smp.s > lipS and smp.s < poolS
		if smp.fall then
			smp.y = 54 -- below the face the water is the plunge pool
		end
	end
	-- fords: shallow, wider, gravel; marked on the samples within 14 studs of a "ford" control point
	local fordS = {}
	for _, smp in ipairs(River.samples) do
		if smp.tag == "ford" then
			table.insert(fordS, smp.s)
		end
	end
	for _, smp in ipairs(River.samples) do
		local f = 0
		for _, s in ipairs(fordS) do
			f = max(f, 1 - smooth(6, 16, abs(smp.s - s)))
		end
		smp.ford = f
	end
end
River.points = {}
River.levels = {}
for i, c in ipairs(River.controls) do
	River.points[i] = Vector3.new(c[1], c[3], c[2])
	River.levels[i] = c[3]
end
River.path = {} -- smoothed centreline the terrain carves, Y = water surface (v1 field)
for i, smp in ipairs(River.samples) do
	River.path[i] = Vector3.new(smp.x, smp.y, smp.z)
end
River.pool = { center = polar(36, 386, 54), radius = 18, level = 54 }
River.fallTop = 86 -- waterfall lip water level
River.fall = {
	lip = polar(34, 410, 86), -- top of the falls (centre of the stream at the lip)
	base = polar(35.4, 397, 54), -- where the water hits the pool (the face base)
	top = 86,
	bottom = 54,
	height = 32,
}
River.waterfall = River.fall.base -- v1 field: where the waterfall roars
-- v1 field "upstream" = the stream above the falls (spring -> lip), with its own path
River.upstream = { width = 9, depth = 1.6, level = River.fallTop, springRadius = 5, points = {}, path = {} }
for _, smp in ipairs(River.samples) do
	if smp.s <= (River.lipS or 0) then
		table.insert(River.upstream.path, Vector3.new(smp.x, smp.y, smp.z))
	end
end
for i = 1, 12 do
	River.upstream.points[i] = River.points[i]
end
River.spring = polar(3.5, 632, 156)

----------------------------------------------------------------------------------------------------
-- The creek (W): springs at the foot of the escarpment, runs past the CreekCave, cascades into the marsh.
----------------------------------------------------------------------------------------------------
local CREEK_CONTROLS = {
	{ 334, 440, 74.5, 1.6, 0.6, "spring" },
	{ 326, 428, 73.6, 2.0, 0.8 },
	{ 318, 419, 72.4, 2.2, 0.9 },
	{ 310, 422, 71.0, 2.4, 1.0 },
	{ 304, 433.5, 69.8, 2.4, 1.0, "cave" }, -- beside the CreekCave mouth
	{ 298, 433, 68.6, 2.5, 1.0 },
	{ 290, 416, 67.0, 2.6, 1.0 },
	{ 282, 407, 65.0, 2.6, 1.0 },
	{ 274, 403, 62.4, 2.8, 1.0 },
	{ 267, 400, 59.4, 2.8, 1.0 },
	{ 261, 396, 55.6, 2.8, 1.0 },
	{ 256, 391, 51.2, 3.0, 1.0 },
	{ 252, 386, 46.8, 3.0, 1.0 },
	{ 249, 381, 42.6, 3.0, 1.0 },
	{ 247, 376, 39.0, 3.2, 1.0 },
	{ 245, 370, 36.5, 3.4, 1.0, "mouth" }, -- = MarshLevel
}
local Creek = {}
ArenaLayout.Creek = Creek
Creek.width = 5
Creek.depth = 1
Creek.controls = polarControls(CREEK_CONTROLS)
Creek.samples = sampleSpline(Creek.controls, 4)
do
	local steepFrom
	for _, smp in ipairs(Creek.samples) do
		if not steepFrom and smp.ci >= 10 then
			steepFrom = smp.s
		end
		smp.gorge, smp.ford, smp.fall = 0, 0, false
	end
	stepLevels(Creek.samples, steepFrom or 0, Creek.samples[#Creek.samples].s, 2.2)
end
Creek.path = {}
for i, smp in ipairs(Creek.samples) do
	Creek.path[i] = Vector3.new(smp.x, smp.y, smp.z)
end
Creek.spring = polar(334, 440, 74.5)

----------------------------------------------------------------------------------------------------
-- The marsh (SW) and its outflow to the lake
----------------------------------------------------------------------------------------------------
local Marsh = {}
ArenaLayout.Marsh = Marsh
Marsh.level = ArenaLayout.MarshLevel
Marsh.center = polar(222, 350, ArenaLayout.MarshLevel)
Marsh.radiusX, Marsh.radiusZ = 110, 115 -- an ellipse inside the outline (the client mist uses it)
Marsh.outline = polarPolygon({
	{ 202, 290 }, { 212, 276 }, { 224, 272 }, { 236, 282 }, { 244, 302 }, { 248, 330 }, { 248, 360 },
	{ 244, 388 }, { 236, 410 }, { 224, 425 }, { 212, 428 }, { 203, 414 }, { 198, 390 }, { 196, 360 }, { 197, 322 },
})
Marsh.snags = polar(220, 385) -- the dead-tree stand
local OUTFLOW_CONTROLS = {
	{ 207, 292, 36.5, 2.6, 0.9 }, -- = MarshLevel
	{ 200, 287, 36.0, 3.0, 1.0 },
	{ 192, 284, 35.5, 3.2, 1.0 },
	{ 184, 280, 35.0, 3.4, 1.0 },
	{ 178, 276, 34.5, 3.6, 1.0 },
	{ 172, 272, 34.0, 4.0, 1.0, "mouth" },
}
local Outflow = {}
ArenaLayout.Outflow = Outflow
Outflow.controls = polarControls(OUTFLOW_CONTROLS)
Outflow.samples = sampleSpline(Outflow.controls, 4)
for _, smp in ipairs(Outflow.samples) do
	smp.gorge, smp.ford, smp.fall = 0, 0, false
end
Outflow.path = {}
for i, smp in ipairs(Outflow.samples) do
	Outflow.path[i] = Vector3.new(smp.x, smp.y, smp.z)
end
function ArenaLayout.isInMarsh(position: Vector3, margin: number?): boolean
	return signedPolygonDistance(Marsh.outline, position.X, position.Z) < (margin or 0)
end

----------------------------------------------------------------------------------------------------
-- The lake (S/SE)
----------------------------------------------------------------------------------------------------
local Lake = {}
ArenaLayout.Lake = Lake
Lake.level = ArenaLayout.LakeLevel
Lake.center = polar(158, 285, ArenaLayout.LakeLevel)
Lake.radiusX = 92 -- v1 fields (approximate; the real shore is Lake.shore)
Lake.radiusZ = 92
Lake.depth = 11
-- shore radius around the lake centre by direction phi (degrees clockwise from north)
function Lake.shoreRadius(phi: number): number
	return 90 + 13 * sin(rad(2 * phi + 40)) + 8 * sin(rad(3 * phi + 130)) + 5 * sin(rad(5 * phi + 70))
end
Lake.shore = {} -- polygon {x, z}, 72 points
for k = 0, 71 do
	local phi = k * 5
	local r = Lake.shoreRadius(phi)
	Lake.shore[k + 1] = { Lake.center.X + sin(rad(phi)) * r, Lake.center.Z - cos(rad(phi)) * r }
end
-- Shore character by direction phi from the lake centre (weights 0..1 that overlap softly):
--   beach: NW shore facing the meadow (sand, gentle); rocky: E/SE (granite banks, steep);
--   reeds: SW/W (wide mud shelf 0.5-1.5 deep, the marsh outflow enters); mouth: NE (river delta, pebbles).
local function arcWeight(phi: number, centre: number, half: number): number
	local d = abs(((phi - centre + 180) % 360) - 180)
	return 1 - smooth(half * 0.55, half, d)
end
function Lake.shoreStyle(phi: number)
	return {
		beach = arcWeight(phi, 338, 58),
		rocky = arcWeight(phi, 108, 52),
		reeds = arcWeight(phi, 258, 40),
		mouth = arcWeight(phi, 34, 22),
	}
end
Lake.island = { center = polar(161, 318, 41), radius = 15, topY = 41 }
function ArenaLayout.isInLake(position: Vector3, margin: number?): boolean
	return signedPolygonDistance(Lake.shore, position.X, position.Z) < (margin or 0)
end
function Lake.phiOf(x: number, z: number): number
	return deg(atan2(x - Lake.center.X, -(z - Lake.center.Z))) % 360
end

----------------------------------------------------------------------------------------------------
-- The escarpment (W/NW): top edge line with cliff height and scree apron width (angle, rTop, height, scree)
----------------------------------------------------------------------------------------------------
local ESCARPMENT = {
	{ 344, 490, 0, 0 },
	{ 339, 478, 22, 10 },
	{ 332, 467, 38, 16 },
	{ 324, 458, 48, 22 },
	{ 316, 452, 52, 20 },
	{ 309, 448, 54, 8 },
	{ 304, 447.5, 54, 2 }, -- CreekCave: the creek hugs the face here
	{ 299, 447, 53, 3 },
	{ 293, 447.5, 51, 14 },
	{ 286, 447, 48, 26 }, -- LedgeCave above the scree
	{ 279, 444, 42, 26 },
	{ 272, 438, 32, 20 },
	{ 266, 431, 22, 14 },
	{ 261, 423, 12, 8 },
	{ 257, 415, 0, 0 },
}
local Escarpment = { keys = ESCARPMENT, faceWidth = 8 }
ArenaLayout.Escarpment = Escarpment
-- interpolated keys by angle -> rTop, height, scree (nil outside its angular range)
function Escarpment.at(angleDeg: number)
	local a = angleDeg % 360
	-- the table runs 344 -> 257 (decreasing)
	if a > 344 or a < 257 then
		return nil
	end
	for i = 1, #ESCARPMENT - 1 do
		local k0, k1 = ESCARPMENT[i], ESCARPMENT[i + 1]
		if a <= k0[1] and a >= k1[1] then
			local t = (k0[1] - a) / (k0[1] - k1[1])
			t = t * t * (3 - 2 * t) * 0.35 + t * 0.65
			return k0[2] + (k1[2] - k0[2]) * t, k0[3] + (k1[3] - k0[3]) * t, k0[4] + (k1[4] - k0[4]) * t
		end
	end
	return nil
end
-- Escarpment.line: the top edge as a polyline {x, z} (1-degree steps)
Escarpment.line = {}
for a = 344, 257, -1 do
	local rTop = Escarpment.at(a)
	if rTop then
		local v = polar(a, rTop)
		table.insert(Escarpment.line, { x = v.X, z = v.Z, a = a })
	end
end

----------------------------------------------------------------------------------------------------
-- The tall-grass field (E/NE, beyond the river)
----------------------------------------------------------------------------------------------------
local Field = {}
ArenaLayout.Field = Field
Field.outline = polarPolygon({
	{ 46, 400 }, { 52, 382 }, { 59, 364 }, { 68, 354 }, { 78, 362 }, { 88, 354 }, { 97, 340 }, { 106, 336 },
	{ 115, 332 }, { 121, 345 }, { 123, 400 }, { 120, 450 }, { 112, 500 }, { 100, 530 }, { 85, 545 },
	{ 70, 540 }, { 58, 520 }, { 50, 490 }, { 46, 450 },
})
function ArenaLayout.isInField(position: Vector3, margin: number?): boolean
	return signedPolygonDistance(Field.outline, position.X, position.Z) < (margin or 0)
end

----------------------------------------------------------------------------------------------------
-- Caves (true 3D voxel tunnels). path points are floor centres (Y = floor height), widths/heights per point.
-- The tunnel runs from the mouth (index 1) into the rock; the last point is the chamber centre.
----------------------------------------------------------------------------------------------------
local function cavePath(list)
	local out = {}
	for i, p in ipairs(list) do
		out[i] = polar(p[1], p[2], p[3])
	end
	return out
end
ArenaLayout.Caves = {
	{
		name = "CreekCave",
		note = "hidden beside the creek at the foot of the cliffs: a hiding / healing spot",
		path = cavePath({ { 304, 439, 71.0 }, { 305, 448, 71.2 }, { 305.8, 456, 71.4 }, { 306.5, 463, 71.5 } }),
		-- 4-stud voxels eat about 2 studs of a tunnel's profile: these leave ~6 studs of headroom to walk in
		widths = { 10, 9.5, 9.5, 17 },
		heights = { 9, 9.5, 9, 10 },
	},
	{
		name = "LedgeCave",
		note = "a larger cave in the cliff face above the scree slope",
		path = cavePath({ { 286, 440, 86.0 }, { 286.8, 450, 86.5 }, { 287.5, 460, 87.0 }, { 288.2, 471, 87.2 } }),
		widths = { 12, 10, 9.5, 24 },
		heights = { 10, 9, 8.5, 11.5 },
	},
	{
		name = "Grotto",
		note = "a shallow overhang shelter at the top of the scree",
		path = cavePath({ { 322, 449, 88.0 }, { 322.4, 455, 88.2 }, { 322.8, 460, 88.4 } }),
		widths = { 15, 14, 12 },
		heights = { 9, 8.5, 7.5 },
	},
}
for _, cave in ipairs(ArenaLayout.Caves) do
	cave.floorY = cave.path[1].Y
	cave.mouth = cave.path[1]
	cave.chamber = cave.path[#cave.path]
end
ArenaLayout.Cave = ArenaLayout.Caves[1] -- v1 field (the cave by the stream)

----------------------------------------------------------------------------------------------------
-- Crossings over water. kind: "Ford" (wade, 1 deep, gravel), "Log" (fallen-log spot, span = log length needed),
-- "Footbridge" (span = bridge length needed), "Stepping" (stepping-stone spot). position is the centre
-- (Y = water surface for fords; Y = rim height for spans once measured), direction = unit vector ACROSS the water.
----------------------------------------------------------------------------------------------------
local function acrossAt(samples, position: Vector3): Vector3
	local _, i = nearestOnSamples(samples, position.X, position.Z)
	local a, b = samples[i], samples[min(i + 1, #samples)]
	local d = Vector3.new(b.x - a.x, 0, b.z - a.z)
	if d.Magnitude < 1e-6 then
		return Vector3.xAxis
	end
	d = d.Unit
	return Vector3.new(-d.Z, 0, d.X)
end
ArenaLayout.Crossings = {
	{ name = "NorthFord", kind = "Ford", water = "River", position = polar(59, 332, 49.9), span = 20 },
	{ name = "EastFord", kind = "Ford", water = "River", position = polar(97, 308, 45.6), span = 22 },
	{ name = "LakeFord", kind = "Ford", water = "River", position = polar(123, 286, 40.6), span = 24 },
	{ name = "GorgeLog", kind = "Log", water = "River", position = polar(24.5, 477, 0), span = 20 },
	{ name = "GorgeFootbridge", kind = "Footbridge", water = "River", position = polar(16, 516, 0), span = 40 }, -- the Footbridge asset: EndA/EndB 40 apart
	{ name = "CreekStones", kind = "Stepping", water = "Creek", position = polar(282, 407, 65.0), span = 7 },
	{ name = "OutflowStones", kind = "Stepping", water = "Outflow", position = polar(192, 284, 35.0), span = 8 },
}
-- Deck heights of the span crossings (mean ground at both ends), measured on the generated terrain with
-- TerrainGen.measure(); applied to position.Y below.
ArenaLayout.CrossingHeights = { GorgeLog = 107.2, GorgeFootbridge = 122.7 }
for _, c in ipairs(ArenaLayout.Crossings) do
	local samples = (c.water == "Creek" and Creek.samples) or (c.water == "Outflow" and Outflow.samples) or River.samples
	c.direction = acrossAt(samples, c.position)
	local h = ArenaLayout.CrossingHeights[c.name]
	if h then
		c.position = Vector3.new(c.position.X, h, c.position.Z)
	end
end

----------------------------------------------------------------------------------------------------
-- Points of interest. position.Y = groundY (the terrain height at the centre, measured after generation).
-- radius = footprint (keep trees out; TerrainGen only eases the ground inside it, it never makes a plateau).
-- kind: Spire | Cave | Waterfall | Island | Overlook | GiantTree | Boulder | DeadStand | Cabin | Watchtower |
--       Bridge | Campsite. template: a suggested ServerStorage.WorldAssets / Blender asset name.
-- facing: suggested yaw (degrees, 0 = north) for the structure's front, where it matters.
-- RETIRED from v1 (they do not fit this arena): RiverMill, FishingShack, StiltHut.
----------------------------------------------------------------------------------------------------
-- Ground heights measured on the generated terrain with TerrainGen.measure() (TerrainVersion 2, fix round of
-- 2026-11-11); applied to POI.groundY / position.Y below. Caves: the floor just inside the mouth; FallsPool: the pool
-- surface; GorgeFootbridge: the deck (rim) height = CrossingHeights.GorgeFootbridge (the gorge floor under it is
-- 105.4). Re-measure after any terrain change.
ArenaLayout.POIHeights = {
	CreekCave = 71.7, LedgeCave = 84.6, Grotto = 88.2, FallsPool = 54.0, LakeIsland = 41.7, GorgeOverlook = 103.0,
	GiantTree = 47.5, FieldBoulder = 75.5, MarshSnags = 36.4, HuntersCabin = 54.0, Watchtower = 86.9,
	GorgeFootbridge = 122.7, CampNorth = 42.3, CampEastRidge = 38.9, CampSouth = 41.0, CampWest = 39.1,
	CampPlateau = 143.0, CampHills = 113.1,
}

local function poi(name, kind, angle, r, radius, tier, extra)
	local t = { name = name, kind = kind, position = polar(angle, r), radius = radius, tier = tier }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return t
end
ArenaLayout.POIs = {
	{ name = "Spire", kind = "Spire", position = Vector3.new(CX, ArenaLayout.PlazaY, CZ), radius = ArenaLayout.PlazaRadius, tier = 3, groundY = ArenaLayout.PlazaY, template = "Spire" },
	-- natural landmarks
	poi("CreekCave", "Cave", 304, 439, 9, 2, { cave = 1, template = "CaveMouth", note = "hidden beside the creek; hiding / healing spot" }),
	poi("LedgeCave", "Cave", 286, 440, 12, 2, { cave = 2, template = "CaveMouth" }),
	poi("Grotto", "Cave", 322, 449, 10, 1, { cave = 3, template = "CaveMouth" }),
	poi("FallsPool", "Waterfall", 36, 386, 26, 2, { note = "plunge pool under the 32-stud falls; the amphitheatre is open to the SE" }),
	poi("LakeIsland", "Island", 161, 318, 15, 2),
	poi("GorgeOverlook", "Overlook", 34.5, 445, 10, 2, { note = "rock knoll on the east rim above the lower gorge and the falls" }),
	poi("GiantTree", "GiantTree", 318, 268, 16, 2, { note = "a forest hollow for one giant / hollow tree" }),
	poi("FieldBoulder", "Boulder", 84, 445, 10, 2, { note = "lone big boulder in the tall grass" }),
	poi("MarshSnags", "DeadStand", 220, 385, 24, 1, { note = "dead-tree stand in the marsh" }),
	-- man-made remnants
	poi("HuntersCabin", "Cabin", 196, 468, 20, 2, { template = "HunterCabin", facing = 16, note = "porch toward the Cabin trail (north-north-east)" }),
	poi("Watchtower", "Watchtower", 128, 478, 14, 2, { template = "Watchtower", facing = 308, note = "on the SE ridge over the lake and the field" }),
	poi("GorgeFootbridge", "Bridge", 16, 516, 24, 2, { template = "Footbridge", crossing = "GorgeFootbridge" }),
	poi("CampNorth", "Campsite", 348, 300, 13, 2, { template = "Tent" }),
	poi("CampEastRidge", "Campsite", 78, 232, 13, 2, { template = "Tent" }),
	poi("CampSouth", "Campsite", 172, 440, 13, 1, { template = "Tent" }),
	poi("CampWest", "Campsite", 262, 285, 13, 1, { template = "Tent" }),
	poi("CampPlateau", "Campsite", 300, 548, 13, 2, { template = "Tent" }),
	poi("CampHills", "Campsite", 60, 572, 13, 1, { template = "Tent" }),
	-- RETIRED (v1): { name = "RiverMill", ... }, { name = "FishingShack", ... }, { name = "StiltHut", ... }
}
for _, p in ipairs(ArenaLayout.POIs) do
	local gy = ArenaLayout.POIHeights[p.name] or p.groundY
	if gy then
		p.groundY = gy
		p.position = Vector3.new(p.position.X, gy, p.position.Z)
	end
end
function ArenaLayout.getPOI(name: string)
	for _, p in ipairs(ArenaLayout.POIs) do
		if p.name == name then
			return p
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Clearings: small open glades in the forest (no trees inside; grass/ferns/flowers fine).
----------------------------------------------------------------------------------------------------
ArenaLayout.Clearings = {
	{ center = polar(20, 290), radius = 22 },
	{ center = polar(338, 398), radius = 18 },
	{ center = polar(150, 470), radius = 20 },
	{ center = polar(250, 520), radius = 22 },
	{ center = polar(75, 600), radius = 18 },
	{ center = polar(195, 560), radius = 18 },
	{ center = polar(282, 560), radius = 16 },
	{ center = polar(5, 470), radius = 16 },
}

-- Low, sheltered hollows where ground mist reads well (fog emitters / particles), with a suggested radius.
ArenaLayout.MistHollows = {
	{ center = polar(222, 350), radius = 60 }, -- the marsh
	{ center = polar(220, 400), radius = 30 },
	{ center = polar(36, 386), radius = 22 }, -- falls pool spray
	{ center = polar(258, 330), radius = 20 },
	{ center = polar(150, 300), radius = 40 }, -- over the lake at dawn
}

----------------------------------------------------------------------------------------------------
-- Game trails (painted ground only, never flattened). Waypoints in polar form; smoothed and lightly wobbled.
----------------------------------------------------------------------------------------------------
local TRAIL_ROUTES = {
	{ name = "Beach", { 172, 140 }, { 166, 172 }, { 160, 194 } },
	{ name = "NorthFord", { 55, 140 }, { 57, 200 }, { 58, 268 }, { 59, 316 }, { 60, 348 }, { 63, 384 }, { 70, 410 }, { 78, 432 }, { 84, 440 } },
	{ name = "EastFord", { 100, 140 }, { 98, 220 }, { 97, 292 }, { 99, 326 }, { 106, 360 }, { 116, 420 }, { 126, 470 } },
	{ name = "North", { 6, 140 }, { 9, 230 }, { 13, 310 }, { 18, 372 }, { 21, 420 }, { 21.5, 458 }, { 23.4, 474 } },
	{ name = "Overlook", { 25.8, 480 }, { 29, 468 }, { 33, 452 }, { 34.5, 446 } },
	{ name = "Footbridge", { 21.5, 458 }, { 18, 490 }, { 14.4, 513 } },
	{ name = "Upstream", { 17.8, 520 }, { 19, 545 }, { 15, 580 }, { 9, 612 } },
	{ name = "Falls", { 40, 140 }, { 40, 220 }, { 41, 298 }, { 40, 344 }, { 37, 368 } },
	{ name = "CreekCave", { 292, 140 }, { 294, 230 }, { 298, 320 }, { 301, 392 }, { 302.5, 422 }, { 303.5, 436 } },
	{ name = "LedgeCave", { 298, 380 }, { 291, 404 }, { 287, 424 }, { 286.2, 436 } },
	{ name = "GiantTree", { 325, 140 }, { 320, 210 }, { 318, 256 } },
	{ name = "Marsh", { 228, 140 }, { 225, 210 }, { 222, 268 }, { 220, 330 }, { 220, 376 } },
	{ name = "Cabin", { 190, 140 }, { 192, 230 }, { 193, 280 }, { 190, 316 }, { 188, 380 }, { 192, 440 }, { 195, 460 } },
	{ name = "Shore", { 160, 194 }, { 147, 208 }, { 134, 234 }, { 124, 276 }, { 127, 320 }, { 132, 360 } },
	{ name = "CampNorth", { 350, 140 }, { 349, 220 }, { 348, 292 } },
	{ name = "CampEastRidge", { 57, 200 }, { 68, 218 }, { 77, 228 } },
	{ name = "CampSouth", { 188, 380 }, { 179, 420 }, { 173, 436 } },
	{ name = "CampWest", { 225, 210 }, { 244, 250 }, { 259, 282 } },
	{ name = "Plateau", { 348, 300 }, { 345, 380 }, { 343, 450 }, { 338, 500 }, { 318, 530 }, { 302, 546 } },
	{ name = "CampHills", { 84, 440 }, { 74, 500 }, { 62, 566 } },
}
ArenaLayout.TrailNames = {}
ArenaLayout.Trails = {} -- { { Vector3 } } centrelines (Y = 0), v1 format
do
	local seed = ArenaLayout.TerrainSeed
	for index, route in ipairs(TRAIL_ROUTES) do
		local controls = {}
		for i, wp in ipairs(route) do
			local v = polar(wp[1], wp[2])
			controls[i] = { v.X, v.Z, 0, 0, 0 }
		end
		local samples = sampleSpline(controls, 6)
		local total = samples[#samples].s
		local points = {}
		for i, smp in ipairs(samples) do
			local prev, nxt = samples[max(i - 1, 1)], samples[min(i + 1, #samples)]
			local dx, dz = nxt.x - prev.x, nxt.z - prev.z
			local l = sqrt(dx * dx + dz * dz)
			local wobble = 0
			if l > 1e-6 then
				local fade = min(1, smp.s / 30, (total - smp.s) / 30)
				wobble = math.noise(smp.s / 46 + index * 3.17, seed * 0.0131 + 0.5, index * 0.71) * 5 * fade
				dx, dz = dx / l, dz / l
			end
			points[i] = Vector3.new(smp.x - dz * wobble, 0, smp.z + dx * wobble)
		end
		ArenaLayout.Trails[index] = points
		ArenaLayout.TrailNames[index] = route.name
	end
end

----------------------------------------------------------------------------------------------------
-- Distances to features (analytic)
----------------------------------------------------------------------------------------------------
local function pathDistanceY(samples, x: number, z: number): (number, number)
	local d, i, u = nearestOnSamples(samples, x, z)
	return d, lerpSample(samples, i, u, "y")
end

-- Flat distance to the river centreline (spring to mouth, incl. the gorge stream) and the water surface there.
function ArenaLayout.distanceToRiver(position: Vector3): (number, number)
	return pathDistanceY(River.samples, position.X, position.Z)
end

function ArenaLayout.distanceToCreek(position: Vector3): (number, number)
	return pathDistanceY(Creek.samples, position.X, position.Z)
end

-- Flat distance to the nearest open water (river/creek/outflow channel edge, lake shore, marsh outline, pool).
function ArenaLayout.distanceToWater(position: Vector3): number
	local x, z = position.X, position.Z
	local best = HUGE
	for _, samples in ipairs({ River.samples, Creek.samples, Outflow.samples }) do
		local d, i, u = nearestOnSamples(samples, x, z)
		best = min(best, d - lerpSample(samples, i, u, "hw"))
	end
	best = min(best, signedPolygonDistance(Lake.shore, x, z))
	best = min(best, signedPolygonDistance(Marsh.outline, x, z) + 6) -- marsh pools start a little inside
	local pc = River.pool.center
	best = min(best, sqrt((x - pc.X) ^ 2 + (z - pc.Z) ^ 2) - River.pool.radius)
	return max(0, best)
end

function ArenaLayout.distanceToTrail(position: Vector3): number
	local best = HUGE
	local x, z = position.X, position.Z
	for _, trail in ipairs(ArenaLayout.Trails) do
		for i = 1, #trail - 1 do
			local a, b = trail[i], trail[i + 1]
			local dx, dz = b.X - a.X, b.Z - a.Z
			local l2 = dx * dx + dz * dz
			local u = 0
			if l2 > 0 then
				u = math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / l2, 0, 1)
			end
			local qx, qz = x - (a.X + dx * u), z - (a.Z + dz * u)
			local d2 = qx * qx + qz * qz
			if d2 < best then
				best = d2
			end
		end
	end
	return sqrt(best)
end

-- Signed distance to the escarpment top edge: > 0 behind it (on the plateau), < 0 in front (cliff foot side).
-- Returns HUGE when the angle is outside the escarpment's range.
function ArenaLayout.escarpmentDistance(x: number, z: number): (number, number?, number?)
	local a = angleXZ(x, z)
	local rTop, height, scree = Escarpment.at(a)
	if not rTop then
		return HUGE
	end
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	return r - rTop, height, scree
end

-- Gorge: flat distance to the gorge stream (gorge section only) or the falls amphitheatre.
local GORGE_SAMPLES = {}
for _, smp in ipairs(River.samples) do
	if smp.gorge == 1 or smp.fall then
		table.insert(GORGE_SAMPLES, smp)
	end
end
function ArenaLayout.gorgeDistance(x: number, z: number): number
	if #GORGE_SAMPLES < 2 then
		return HUGE
	end
	local d = nearestOnSamples(GORGE_SAMPLES, x, z)
	local pc = River.pool.center
	return min(d, sqrt((x - pc.X) ^ 2 + (z - pc.Z) ^ 2) - 18)
end

----------------------------------------------------------------------------------------------------
-- Biomes
----------------------------------------------------------------------------------------------------
ArenaLayout.Biomes = { "Meadow", "Forest", "Lake", "Gorge", "Cliffs", "Field", "Marsh", "Mountains", "Lobby" }

-- Coarse angular sectors (compatibility for v1 code that iterates sectors; use getBiome for real queries).
ArenaLayout.Sectors = {
	{ name = "Forest", from = 342, to = 44 },
	{ name = "Field", from = 44, to = 122 },
	{ name = "Lake", from = 122, to = 196 },
	{ name = "Marsh", from = 196, to = 256 },
	{ name = "Cliffs", from = 256, to = 342 },
}

function ArenaLayout.getBiome(position: Vector3): string
	local lobby = ArenaLayout.LobbyPosition
	local lx, lz = position.X - lobby.X, position.Z - lobby.Z
	if lx * lx + lz * lz < (ArenaLayout.LobbyRadius * 2) ^ 2 then
		return "Lobby"
	end
	local x, z = position.X, position.Z
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	local a = angleXZ(x, z)
	if r > ArenaLayout.mountainEdge(a) - 18 then
		return "Mountains"
	end
	if r < ArenaLayout.meadowEdge(a) then
		return "Meadow"
	end
	if signedPolygonDistance(Lake.shore, x, z) < 10 then
		return "Lake"
	end
	if signedPolygonDistance(Marsh.outline, x, z) < 4 then
		return "Marsh"
	end
	if r > 360 and ArenaLayout.gorgeDistance(x, z) < 34 then
		return "Gorge"
	end
	local e = ArenaLayout.escarpmentDistance(x, z)
	if e > -55 and e < 34 then
		return "Cliffs"
	end
	if pointInPolygon(Field.outline, x, z) then
		return "Field"
	end
	return "Forest"
end

-- Distance to the nearest open area (meadow edge, field, lake shore, marsh, clearings); 0 inside one.
function ArenaLayout.forestEdgeDistance(position: Vector3): number
	local x, z = position.X, position.Z
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	local best = max(0, r - ArenaLayout.meadowEdge(angleXZ(x, z)))
	best = min(best, max(0, signedPolygonDistance(Field.outline, x, z)))
	best = min(best, max(0, signedPolygonDistance(Lake.shore, x, z)))
	best = min(best, max(0, signedPolygonDistance(Marsh.outline, x, z)))
	for _, c in ipairs(ArenaLayout.Clearings) do
		best = min(best, max(0, sqrt((x - c.center.X) ^ 2 + (z - c.center.Z) ^ 2) - c.radius))
	end
	return best
end

----------------------------------------------------------------------------------------------------
-- Ground queries (raycasts on Terrain; grid fallback)
----------------------------------------------------------------------------------------------------
local solidParams = RaycastParams.new()
solidParams.FilterType = Enum.RaycastFilterType.Include
solidParams.IgnoreWater = true
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.IgnoreWater = false
local function refreshParams()
	solidParams.FilterDescendantsInstances = { workspace.Terrain }
	waterParams.FilterDescendantsInstances = { workspace.Terrain }
end
refreshParams()

local CAST_TOP = 1400
local DOWN = Vector3.new(0, -CAST_TOP - 200, 0)

-- TerrainData grid (written by TerrainGen): lazily decoded; nil on clients.
local gridData = nil
local B64 = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do
		B64[string.byte(alphabet, i)] = i - 1
	end
end
local function decodeBase64(s: string): buffer
	local n = #s
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local outLen = (n // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = bit32.bor(bit32.lshift(B64[a] or 0, 18), bit32.lshift(B64[b] or 0, 12), bit32.lshift(B64[c] or 0, 6), B64[d] or 0)
		if o < outLen then
			buffer.writeu8(out, o, bit32.extract(v, 16, 8))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.extract(v, 8, 8))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.extract(v, 0, 8))
		end
		o += 3
	end
	return out
end

local function loadGrid()
	if gridData ~= nil then
		return gridData or nil
	end
	gridData = false
	local ok, mod = pcall(function()
		local ss = game:GetService("ServerStorage")
		local wg = ss and ss:FindFirstChild("WorldGen")
		local m = wg and wg:FindFirstChild("TerrainData")
		if not m then
			return nil
		end
		if not RunService:IsRunning() then
			m = m:Clone() -- Studio caches required modules in Edit mode
		end
		return require(m)
	end)
	if ok and type(mod) == "table" and mod.cell then
		local g = { cell = mod.cell, origin = mod.origin, n = mod.n, version = mod.version }
		for key, str in pairs(mod.channels or {}) do
			g[key] = decodeBase64(str)
		end
		gridData = g
	end
	return gridData or nil
end
ArenaLayout._loadGrid = loadGrid

-- bilinear sample of a grid channel ("H" is u16 = (h + 64) * 32, the rest u8)
local function gridSample(key: string, x: number, z: number): number?
	local g = loadGrid()
	if not g or not g[key] then
		return nil
	end
	local n, cell, o = g.n, g.cell, g.origin
	local fx = (x - o) / cell - 0.5
	local fz = (z - o) / cell - 0.5
	local ix, iz = floor(fx), floor(fz)
	local tx, tz = fx - ix, fz - iz
	if ix < 0 or iz < 0 or ix >= n - 1 or iz >= n - 1 then
		return nil
	end
	local b = g[key]
	local function at(i, j)
		local k = j * n + i
		if key == "H" then
			return buffer.readu16(b, k * 2) / 32 - 64
		end
		return buffer.readu8(b, k)
	end
	local v00, v10, v01, v11 = at(ix, iz), at(ix + 1, iz), at(ix, iz + 1), at(ix + 1, iz + 1)
	return (v00 * (1 - tx) + v10 * tx) * (1 - tz) + (v01 * (1 - tx) + v11 * tx) * tz
end
ArenaLayout._gridSample = gridSample

function ArenaLayout.groundAt(x: number, z: number)
	if solidParams.FilterDescendantsInstances[1] ~= workspace.Terrain then
		refreshParams()
	end
	local hit = workspace:Raycast(Vector3.new(x, CAST_TOP, z), DOWN, solidParams)
	if hit then
		return hit.Position.Y, hit.Normal, hit.Material
	end
	return nil
end

function ArenaLayout.heightAt(x: number, z: number): number?
	local y = ArenaLayout.groundAt(x, z)
	if y then
		return y
	end
	return gridSample("H", x, z)
end

function ArenaLayout.normalAt(x: number, z: number): Vector3
	local _, n = ArenaLayout.groundAt(x, z)
	if n then
		return n
	end
	local h0, h1, h2 = gridSample("H", x, z), gridSample("H", x + 4, z), gridSample("H", x, z + 4)
	if h0 and h1 and h2 then
		return Vector3.new(h0 - h1, 4, h0 - h2).Unit
	end
	return Vector3.yAxis
end

function ArenaLayout.slopeAt(x: number, z: number): number
	local n = ArenaLayout.normalAt(x, z)
	return deg(math.acos(math.clamp(n.Y, -1, 1)))
end

-- Terrain water over the ground at (x, z): (waterY?, depth)
function ArenaLayout.waterAt(x: number, z: number)
	if waterParams.FilterDescendantsInstances[1] ~= workspace.Terrain then
		refreshParams()
	end
	local top = workspace:Raycast(Vector3.new(x, CAST_TOP, z), DOWN, waterParams)
	if top and top.Material == Enum.Material.Water then
		local groundY = ArenaLayout.groundAt(x, z) or (top.Position.Y - 1)
		return top.Position.Y, max(0, top.Position.Y - groundY)
	end
	if not top then
		local depth = gridSample("W", x, z)
		if depth and depth > 0.5 then
			local h = gridSample("H", x, z) or 0
			return h + depth / 10, depth / 10
		end
	end
	return nil, 0
end

function ArenaLayout.isWater(x: any, z: number?)
	if typeof(x) == "Vector3" then
		x, z = x.X, x.Z
	end
	local y, depth = ArenaLayout.waterAt(x, z :: number)
	return y ~= nil, y, depth
end

-- 0 (dry) .. 1 (wet): grid-backed; analytic fallback from distance to water.
function ArenaLayout.moistureAt(x: number, z: number): number
	local m = gridSample("M", x, z)
	if m then
		return m / 255
	end
	local d = ArenaLayout.distanceToWater(Vector3.new(x, 0, z))
	return math.clamp(1 - d / 80, 0, 1) * 0.8 + 0.2 * (ArenaLayout.getBiome(Vector3.new(x, 0, z)) == "Marsh" and 1 or 0)
end

-- Flat distance to the nearest steep ground (> 50 degrees): grid-backed; analytic fallback.
function ArenaLayout.distanceToCliff(position: Vector3): number
	local c = gridSample("C", position.X, position.Z)
	if c then
		return c
	end
	local x, z = position.X, position.Z
	local best = abs(ArenaLayout.escarpmentDistance(x, z))
	best = min(best, abs(ArenaLayout.gorgeDistance(x, z) - 10))
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	best = min(best, abs(ArenaLayout.mountainEdge(angleXZ(x, z)) - r))
	return best
end

----------------------------------------------------------------------------------------------------
-- Exclusion zones and scatter rules (for the set dresser)
----------------------------------------------------------------------------------------------------
-- Standard exclusions every scatter pass should respect (studs):
ArenaLayout.Exclusions = {
	plaza = ArenaLayout.PlazaRadius + 8, -- nothing natural inside r < 70 (the Spire plaza and its apron)
	plateRing = { inner = 44, outer = 60 }, -- keep the launch-plate ring clear
	meadowCore = 100, -- no trees, rocks or bushes inside r < 100 (sightlines to the treeline)
	trail = { tree = 3.5, bush = 3, groundCover = 1.6 }, -- from a trail centreline
	water = { land = 0.6, reedsMaxDepth = 1.8, lilyMinDepth = 0.6 }, -- land plants need ground above water
	slope = { tree = 34, bush = 40, groundCover = 44 }, -- max slope in degrees
	cliffEdge = 4, -- no trees within 4 studs of > 50 deg ground (use distanceToCliff)
	caveMouth = 6, -- keep every cave mouth clear (CreekCave: hide it with bushes/ferns 6-12 studs to the sides)
	crossing = 6, -- keep fords, the log spot and the footbridge spot clear
	boundary = ArenaLayout.PlayRadius + 30, -- gameplay props stop here; visual trees may continue
}

-- isExcluded(position, rule?) -> (true, reason) | false
-- rule (optional): { class = "tree"|"bush"|"groundCover"|"rock"|"water", allowWater = boolean }
function ArenaLayout.isExcluded(position: Vector3, rule): (boolean, string?)
	local class = (rule and rule.class) or "tree"
	local x, z = position.X, position.Z
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	local ex = ArenaLayout.Exclusions
	if r < ex.plaza then
		return true, "plaza"
	end
	if class ~= "groundCover" and r < ex.meadowCore then
		return true, "meadowCore"
	end
	local trailLimit = ex.trail[class] or ex.trail.groundCover
	if class ~= "water" and ArenaLayout.distanceToTrail(position) < trailLimit then
		return true, "trail"
	end
	for _, p in ipairs(ArenaLayout.POIs) do
		if p.kind ~= "Spire" then
			local d = sqrt((x - p.position.X) ^ 2 + (z - p.position.Z) ^ 2)
			if d < p.radius and class ~= "groundCover" then
				return true, "poi:" .. p.name
			end
		end
	end
	for _, cave in ipairs(ArenaLayout.Caves) do
		local m = cave.mouth
		if sqrt((x - m.X) ^ 2 + (z - m.Z) ^ 2) < ex.caveMouth then
			return true, "caveMouth"
		end
	end
	for _, c in ipairs(ArenaLayout.Crossings) do
		local d = sqrt((x - c.position.X) ^ 2 + (z - c.position.Z) ^ 2)
		if d < max(ex.crossing, c.span * 0.6) then
			return true, "crossing"
		end
	end
	if class == "tree" then
		for _, c in ipairs(ArenaLayout.Clearings) do
			if sqrt((x - c.center.X) ^ 2 + (z - c.center.Z) ^ 2) < c.radius then
				return true, "clearing"
			end
		end
	end
	if not (rule and rule.allowWater) then
		local wet, _, depth = ArenaLayout.isWater(x, z)
		if wet and depth > ex.water.land then
			return true, "water"
		end
	end
	local maxSlope = ex.slope[class]
	if maxSlope and ArenaLayout.slopeAt(x, z) > maxSlope then
		return true, "slope"
	end
	if class == "tree" and ArenaLayout.distanceToCliff(position) < ex.cliffEdge then
		return true, "cliffEdge"
	end
	return false
end

--[[
	Scatter: per-biome rules for the set dresser. Every rule names the realistic assets directly (the *Real sets in
	art/manifests, imported into ServerStorage.MeshAssets). density = items per 1000 sq studs before clustering and
	exclusions. Fields:
	  assets      asset names; weights (optional, same order) = relative shares, else equal
	  kind        a short label; class = exclusion class for isExcluded ("tree", "bush", "groundCover", "rock", "water")
	  cluster     { radius, min, max } -> place in clumps (seed points at density / average clump size)
	  spacing     minimum distance between two items of this rule (studs, pivot to pivot)
	  slope       { min, max } degrees; height { min, max } studs; moisture { min, max } (0..1, moistureAt)
	  waterDepth  { min, max } studs of water over the ground (class "water" only: reeds, stones in the stream)
	  edgeBoost   density multiplier where forestEdgeDistance < 25 (forest edges, clearings, shores)
	  cliffBoost  density multiplier where distanceToCliff < 18 (talus under cliffs and gorge walls)
	  scale       { min, max } uniform scale; tilt = random lean in degrees
	  tiltToNormal 0..1: blend of the asset's up toward the ground normal (0 = upright: trees; 1 = lies on the slope)
	  sink        studs pushed into the ground (rocks, logs and stumps sink so no edge floats on a slope)
	  align       "contour" = long axis along the contour (logs), "downslope" = front faces down the slope,
	              "outward" = front faces away from the hill (cliff faces), else random yaw
	  where       a placement hint in words
	Sizes (w x h x d studs) and footprint radii are in ArenaLayout.AssetInfo; POI dressing kits in ArenaLayout.POIKits.
	Budget guide (streaming on): ~3,500 trees, ~6,000 bushes and ferns, ~15,000 grass and flower clumps (cheap cards:
	no collision, no shadow) and ~1,500 rocks in the whole arena.
	Placed explicitly (not scattered): Spire + SpirePlatform at Center (unrotated, pivot y = PlazaY), a Plinth on each
	Plates[i] (pivot y = PlazaY + PlateTube.platformTop), one CaveMouth per Caves[i], the Footbridge and the log at
	Crossings, the POI kits.
]]
ArenaLayout.Scatter = {
	Forest = {
		{ assets = { "SpruceA", "SpruceB", "FirA" }, weights = { 0.4, 0.35, 0.25 }, kind = "Conifer", class = "tree", density = 2.2, cluster = { radius = 26, min = 3, max = 8 }, spacing = 8, slope = { 0, 34 }, height = { 0, 300 }, scale = { 0.85, 1.2 }, tilt = 2, where = "the dense mixed-conifer canopy; FirA favours damp valley floors (moisture > 0.45)" },
		{ assets = { "PineA" }, kind = "Pine", class = "tree", density = 0.45, spacing = 12, slope = { 0, 30 }, moisture = { 0, 0.5 }, scale = { 0.9, 1.15 }, tilt = 2, where = "drier ridges and knolls (convex ground)" },
		{ assets = { "ConiferYoung" }, kind = "YoungConifer", class = "bush", density = 0.9, cluster = { radius = 9, min = 2, max = 6 }, spacing = 4, slope = { 0, 36 }, scale = { 0.7, 1.4 }, edgeBoost = 2.5, where = "regrowth at edges, clearings and canopy gaps" },
		{ assets = { "BirchA", "BirchB" }, weights = { 0.65, 0.35 }, kind = "Birch", class = "tree", density = 0.3, cluster = { radius = 14, min = 3, max = 6 }, spacing = 7, slope = { 0, 28 }, moisture = { 0.4, 1 }, scale = { 0.85, 1.15 }, edgeBoost = 2.5 },
		{ assets = { "OakA" }, kind = "Oak", class = "tree", density = 0.1, spacing = 26, slope = { 0, 18 }, height = { 0, 120 }, scale = { 0.9, 1.1 }, edgeBoost = 1.5, where = "the lower forest toward the meadow; climbable (OakA_Bark is tagged Climbable, Perch1-4)" },
		{ assets = { "SnagA", "SnagB" }, kind = "Snag", class = "tree", density = 0.1, spacing = 16, slope = { 0, 36 }, scale = { 0.9, 1.2 } },
		{ assets = { "FallenLogA", "FallenLogB" }, kind = "FallenLog", class = "bush", density = 0.35, spacing = 14, slope = { 0, 26 }, tiltToNormal = 1, sink = 0.35, align = "contour" },
		{ assets = { "StumpA", "StumpB" }, kind = "Stump", class = "bush", density = 0.25, spacing = 10, slope = { 0, 28 }, tiltToNormal = 0.3, sink = 0.3 },
		{ assets = { "BushA", "BushB" }, weights = { 0.55, 0.45 }, kind = "Bush", class = "bush", density = 1.8, cluster = { radius = 9, min = 2, max = 4 }, spacing = 4, slope = { 0, 40 }, scale = { 0.8, 1.25 }, edgeBoost = 2.5, where = "BushA hides a crouching contender" },
		{ assets = { "BerryBush" }, kind = "BerryBush", class = "bush", density = 0.2, spacing = 14, slope = { 0, 30 }, edgeBoost = 3, where = "a forage cue: edges and clearings" },
		{ assets = { "SaplingBroadleaf" }, kind = "Sapling", class = "bush", density = 0.25, spacing = 8, slope = { 0, 30 }, edgeBoost = 3 },
		{ assets = { "FernA", "FernB" }, kind = "Fern", class = "groundCover", density = 5, cluster = { radius = 10, min = 4, max = 10 }, spacing = 2.5, slope = { 0, 44 }, scale = { 0.8, 1.35 }, tiltToNormal = 1, where = "FernA (bracken) on drier, sunnier ground (moisture < 0.5); FernB (sword fern) in damp shade and gullies" },
		{ assets = { "GrassForest" }, kind = "GrassTuft", class = "groundCover", density = 6, cluster = { radius = 8, min = 6, max = 20 }, spacing = 1.2, slope = { 0, 40 }, tiltToNormal = 1, edgeBoost = 2.5, where = "where light reaches the floor: edges, clearings, beside trails" },
		{ assets = { "MushroomsA" }, kind = "Mushrooms", class = "groundCover", density = 0.5, spacing = 5, slope = { 0, 30 }, moisture = { 0.45, 1 }, tiltToNormal = 1, where = "beside logs, stumps and roots" },
		{ assets = { "MossPatch" }, kind = "Moss", class = "groundCover", density = 1.2, spacing = 4, slope = { 0, 45 }, moisture = { 0.35, 1 }, tiltToNormal = 1, where = "damp ground; also on the shaded (north) side of boulders and logs" },
		{ assets = { "BoulderA", "BoulderB", "BoulderC", "BoulderD" }, weights = { 0.4, 0.3, 0.2, 0.1 }, kind = "Boulder", class = "rock", density = 0.45, cluster = { radius = 10, min = 2, max = 5 }, spacing = 4, slope = { 0, 50 }, cliffBoost = 4, scale = { 0.8, 1.4 }, tiltToNormal = 0.6, sink = 0.3 },
		{ assets = { "RockFlat" }, kind = "Slab", class = "rock", density = 0.04, spacing = 30, slope = { 0, 25 }, tiltToNormal = 0.8, sink = 0.4 },
		{ assets = { "RockOutcrop" }, kind = "Outcrop", class = "rock", density = 0.04, spacing = 30, slope = { 15, 45 }, tiltToNormal = 0.5, sink = 1.2, align = "downslope", where = "on and around the terrain's own rock knobs (Rock material at the surface, slope > 22)" },
	},
	Meadow = {
		{ assets = { "FlowersA", "FlowersB" }, kind = "Wildflowers", class = "groundCover", density = 10, cluster = { radius = 14, min = 12, max = 36 }, spacing = 1.2, tiltToNormal = 1, where = "patches, more toward the edge (r > 80); none on the plaza apron (r < 70)" },
		{ assets = { "GrassForest" }, kind = "GrassTuft", class = "groundCover", density = 12, spacing = 1.5, tiltToNormal = 1, where = "denser toward the treeline" },
		{ assets = { "GrassTallA", "GrassTallB" }, kind = "TallGrass", class = "groundCover", density = 2, cluster = { radius = 10, min = 6, max = 16 }, spacing = 1.6, where = "only r > 115, a soft fringe at the treeline" },
		{ assets = { "OakA", "BirchA" }, kind = "LoneTree", class = "tree", density = 0.02, spacing = 60, where = "at most 3-4 in the whole meadow, only r > 115" },
		{ assets = { "BoulderB", "BoulderC" }, kind = "Boulder", class = "rock", density = 0.04, spacing = 30, sink = 0.3, where = "only r > 100" },
	},
	Field = {
		{ assets = { "GrassTallA", "GrassTallB" }, kind = "TallGrass", class = "groundCover", density = 36, spacing = 1.4, slope = { 0, 28 }, scale = { 0.85, 1.25 }, where = "the golden tall grass; leave the trails and a few hollows open" },
		{ assets = { "FlowersB" }, kind = "Wildflowers", class = "groundCover", density = 3, cluster = { radius = 10, min = 6, max = 18 } },
		{ assets = { "OakA", "PineA" }, kind = "LoneTree", class = "tree", density = 0.05, spacing = 45 },
		{ assets = { "BoulderC", "BoulderD" }, kind = "Boulder", class = "rock", density = 0.06, spacing = 30, sink = 0.4 },
		{ assets = { "BushB", "BerryBush" }, kind = "Bush", class = "bush", density = 0.2, spacing = 14, edgeBoost = 3 },
	},
	Lake = {
		{ assets = { "ReedsA" }, kind = "Reeds", class = "water", density = 9, cluster = { radius = 8, min = 4, max = 12 }, spacing = 2.5, waterDepth = { 0.1, 1.8 }, sink = 0.6, where = "densest on the reed shore (Lake.shoreStyle(phi).reeds) and the river mouth" },
		{ assets = { "RiverStones" }, kind = "ShoreStones", class = "rock", density = 1, spacing = 6, tiltToNormal = 1, sink = 0.2, where = "the pebble shores and the river mouth (shoreStyle.mouth / beach), at the waterline" },
		{ assets = { "BoulderB", "BoulderC", "BoulderD" }, kind = "ShoreRock", class = "rock", density = 1.4, spacing = 4, tiltToNormal = 0.6, sink = 0.5, where = "the rocky banks (shoreStyle.rocky > 0.5), half in the water" },
		{ assets = { "RockFlat" }, kind = "Ledge", class = "rock", density = 0.1, spacing = 20, sink = 0.3, where = "a few flat rocks at the rocky banks" },
		{ assets = { "FallenLogA" }, kind = "Driftwood", class = "rock", density = 0.3, spacing = 16, tiltToNormal = 1, sink = 0.2, where = "on the beach just above the waterline" },
		{ assets = { "BirchA", "BirchB" }, kind = "Birch", class = "tree", density = 0.5, cluster = { radius = 12, min = 2, max = 5 }, slope = { 0, 26 } },
	},
	Gorge = {
		{ assets = { "SpruceB", "FirA" }, kind = "Conifer", class = "tree", density = 2.0, spacing = 8, slope = { 0, 32 }, where = "on the rims, at least 5 studs back from the edge" },
		{ assets = { "FernB" }, kind = "Fern", class = "groundCover", density = 7, slope = { 0, 45 }, tiltToNormal = 1, where = "ledges and the damp floor" },
		{ assets = { "MossPatch" }, kind = "Moss", class = "groundCover", density = 3, tiltToNormal = 1, where = "ledges, wet rock beside the stream" },
		{ assets = { "RiverStones", "BoulderA", "BoulderB", "BoulderC" }, weights = { 0.4, 0.25, 0.2, 0.15 }, kind = "StreamRocks", class = "water", density = 2.5, waterDepth = { 0, 1.2 }, sink = 0.3, where = "in and beside the stream" },
		{ assets = { "FallenLogA", "FallenLogB" }, kind = "FallenLog", class = "rock", density = 0.3, where = "a few across the stream or wedged between the walls" },
		{ assets = { "CliffFaceA", "CliffFaceB", "CliffFaceC" }, kind = "CliffFace", class = "rock", density = 0.25, spacing = 22, slope = { 50, 90 }, align = "outward", sink = 3, where = "against the stratified walls, front facing into the gorge" },
		{ assets = { "ScreeA" }, kind = "Scree", class = "rock", density = 0.4, cliffBoost = 2, tiltToNormal = 1, where = "at the foot of the walls" },
	},
	Cliffs = {
		{ assets = { "ScreeA" }, kind = "Scree", class = "rock", density = 2.2, spacing = 4, slope = { 18, 45 }, cliffBoost = 2, tiltToNormal = 1, sink = 0.3, where = "the scree aprons at the cliff foot" },
		{ assets = { "BoulderA", "BoulderB", "BoulderC" }, kind = "Talus", class = "rock", density = 1.5, spacing = 3, slope = { 10, 45 }, cliffBoost = 2, tiltToNormal = 0.6, sink = 0.3 },
		{ assets = { "CliffFaceA", "CliffFaceB", "CliffFaceC" }, kind = "CliffFace", class = "rock", density = 0.3, spacing = 18, slope = { 50, 90 }, align = "outward", sink = 3, where = "hug the terrain face, front facing outward; never over a cave mouth" },
		{ assets = { "SpruceA", "FirA", "PineA" }, kind = "Conifer", class = "tree", density = 1.6, spacing = 9, slope = { 0, 32 }, where = "on the plateau above and below the scree" },
		{ assets = { "FernA", "FernB" }, kind = "Fern", class = "groundCover", density = 4, moisture = { 0.4, 1 }, tiltToNormal = 1 },
		{ assets = { "BushA" }, kind = "Bush", class = "bush", density = 1.2, where = "screen the CreekCave mouth from the creek trail (6-12 studs to the sides)" },
		{ assets = { "MossPatch" }, kind = "Moss", class = "groundCover", density = 1.5, tiltToNormal = 1 },
	},
	Marsh = {
		{ assets = { "SnagA", "SnagB" }, kind = "Snag", class = "tree", density = 0.5, cluster = { radius = 20, min = 4, max = 9 }, spacing = 7, where = "densest around Marsh.snags (the MarshSnags POI)" },
		{ assets = { "ReedsA" }, kind = "Reeds", class = "water", density = 12, cluster = { radius = 7, min = 4, max = 12 }, waterDepth = { 0, 1.5 }, sink = 0.6 },
		{ assets = { "BushB" }, kind = "Bush", class = "bush", density = 0.8, where = "on hummocks (ground above MarshLevel + 0.6)" },
		{ assets = { "FernB" }, kind = "Fern", class = "groundCover", density = 2.5, tiltToNormal = 1 },
		{ assets = { "MossPatch", "MushroomsA" }, weights = { 0.8, 0.2 }, kind = "Moss", class = "groundCover", density = 3, tiltToNormal = 1 },
		{ assets = { "BirchA" }, kind = "Birch", class = "tree", density = 0.25, where = "marsh edges only" },
		{ assets = { "FallenLogB" }, kind = "FallenLog", class = "rock", density = 0.35, tiltToNormal = 1, sink = 0.8, where = "half sunk in the pools" },
	},
	Mountains = {
		{ assets = { "SpruceA", "SpruceB", "FirA" }, kind = "Conifer", class = "tree", density = 0.9, spacing = 10, slope = { 0, 40 }, height = { 0, 250 }, where = "visual only (outside the border); thin out with height" },
		{ assets = { "CliffFaceC" }, kind = "Crag", class = "rock", density = 0.12, slope = { 40, 90 }, align = "outward", sink = 4 },
		{ assets = { "ScreeA" }, kind = "Scree", class = "rock", density = 0.3, slope = { 20, 45 }, tiltToNormal = 1 },
	},
}

-- AssetInfo: realistic asset sizes (w x h x d studs, from art/manifests) and a footprint radius r for spacing and
-- exclusion checks (trees: the lower crown; everything else: half the larger side).
ArenaLayout.AssetInfo = {
	SpruceA = { 18.2, 55.3, 17.1, r = 7 }, SpruceB = { 15.1, 36.2, 15, r = 6 }, FirA = { 12.6, 42.2, 12.8, r = 5 },
	PineA = { 21.3, 54.5, 25.4, r = 4 }, ConiferYoung = { 5.6, 11.8, 5.9, r = 2.6 }, BirchA = { 18.5, 30.3, 19.7, r = 4 },
	BirchB = { 21.8, 28.6, 19.8, r = 5 }, OakA = { 29.2, 28.9, 29.2, r = 10 }, SnagA = { 9, 28.1, 9.2, r = 2.5 },
	SnagB = { 8.9, 20.4, 9.9, r = 2.5 }, FallenLogA = { 15.8, 2, 2.3, r = 8 }, FallenLogB = { 22.4, 3.2, 3.3, r = 11 },
	StumpA = { 5.7, 2.8, 5.6, r = 2.8 }, StumpB = { 4.5, 4.6, 5, r = 2.5 },
	FernA = { 5.9, 2.6, 4.8, r = 2.5 }, FernB = { 4.6, 2.1, 4.2, r = 2.2 }, BushA = { 7.1, 5, 6.6, r = 3.4 },
	BushB = { 7.3, 3.2, 6.8, r = 3.5 }, BerryBush = { 6.2, 4.4, 5.1, r = 3 }, GrassTallA = { 3.5, 3.7, 3.2, r = 1.7 },
	GrassTallB = { 4, 3.3, 3.4, r = 1.8 }, GrassForest = { 1.8, 1.1, 1.6, r = 0.9 }, ReedsA = { 3.3, 6.2, 3.4, r = 1.7 },
	FlowersA = { 2, 1.6, 1.8, r = 1 }, FlowersB = { 1.8, 1.5, 1.7, r = 0.9 }, MushroomsA = { 1.7, 0.6, 1.5, r = 0.8 },
	SaplingBroadleaf = { 6.4, 9.2, 6.5, r = 3 }, MossPatch = { 4.8, 0.3, 3.3, r = 2.4 },
	BoulderA = { 2.3, 2.1, 2.1, r = 1.2 }, BoulderB = { 4.1, 3.6, 3.8, r = 2 }, BoulderC = { 6.7, 5.3, 5.7, r = 3.3 },
	BoulderD = { 11, 7.1, 8.4, r = 5.5 }, RockFlat = { 9.9, 1.9, 7.5, r = 5 }, RiverStones = { 7.2, 1.2, 5.6, r = 3.6 },
	ScreeA = { 8.2, 3.1, 6.5, r = 4 }, CliffFaceA = { 27.3, 22.3, 25.3, r = 13 }, CliffFaceB = { 38.3, 31.9, 32.8, r = 19 },
	CliffFaceC = { 48.4, 44.1, 41.1, r = 24 }, RockOutcrop = { 14.1, 6.4, 16.9, r = 8 }, CaveMouth = { 36.3, 24.6, 31.6, r = 18 },
	HunterCabin = { 26.6, 21.4, 21.5, r = 14 }, Watchtower = { 13.9, 32.6, 13.9, r = 7 }, Footbridge = { 48.5, 6.1, 8.7, r = 24 },
	Tent = { 7, 4.9, 12.9, r = 6.5 }, Campfire = { 3.7, 0.7, 3.7, r = 1.9 }, Woodpile = { 6.6, 3.1, 4, r = 3.3 },
	Barrel = { 2.3, 3.2, 2.3, r = 1.2 }, Lantern = { 0.6, 1.4, 0.6, r = 0.3 }, CratePile = { 6.1, 4.7, 5.4, r = 3 },
	FenceSegment = { 8.5, 4.2, 0.6, r = 4.3 }, Sign = { 4.4, 6.2, 1.5, r = 2.2 }, Bedroll = { 2.5, 0.7, 6.6, r = 3.3 },
	LogBench = { 6.8, 1.7, 1.4, r = 3.4 },
	Spire = { 40, 58.2, 40, r = 20 }, SpirePlatform = { 120, 12.4, 120, r = 60 }, Plinth = { 5.5, 12.4, 5.5, r = 2.8 },
}

-- POIKits: what to place at each POI kind (centre = POI.position, footprint = POI.radius; facing = POI.facing when set).
ArenaLayout.POIKits = {
	Campsite = { "Tent", "Campfire", "Bedroll", "LogBench", "Woodpile", "Lantern (hung from the tent pole)", "optional: Barrel, CratePile (tier 2 camps), 1-2 broken FenceSegment" },
	Cabin = { "HunterCabin (door / porch facing POI.facing)", "Woodpile against the east gable", "Barrel", "3-5 FenceSegment as a small paddock", "Sign where the trail arrives" },
	Watchtower = { "Watchtower (ladder well inside; open front bay toward POI.facing)", "CratePile at its foot", "Lantern on the deck" },
	Bridge = { "Footbridge: X axis = Crossings.GorgeFootbridge.direction (across the gorge), EndA/EndB on the rims, pivot at the centre at the rim height (Crossings[].position.Y)", "a Sign at one end" },
	Cave = { "CaveMouth at the cave mouth (CaveEntrance attachment on Caves[i].mouth, front facing out of the hill)", "CreekCave: BushA / FernB screens 6-12 studs to the sides", "LedgeCave: an old Campfire and Bedroll inside the chamber" },
	Waterfall = { "RiverStones and BoulderB/C round the pool rim", "MossPatch on the wet rocks", "an Emit_Waterfall AmbientEmitter at River.fall.base" },
	Island = { "BirchA x2", "BoulderC", "RockFlat at the waterline" },
	Overlook = { "RockFlat as a ledge at the rim (front toward the gorge)", "RockOutcrop behind it" },
	GiantTree = { "OakA at scale 1.5-1.7 in the hollow (the giant / hollow tree), MossPatch and MushroomsA round its roots" },
	Boulder = { "BoulderD at scale 2.2-2.6 (the lone field boulder), half sunk (sink 1.5)" },
	DeadStand = { "SnagA / SnagB x8-12 inside the radius", "FallenLogB x2 half sunk", "ReedsA round them" },
}

----------------------------------------------------------------------------------------------------
-- Loot zones: tier 3 at the Spire, tier 2 at POIs and the meadow edge, tier 1 scattered.
----------------------------------------------------------------------------------------------------
-- LootZones: { name, center, radius, tier, crates, ground } (suggested counts; crates = SupplyCrate markers,
-- ground = Ground markers). Kind "ring" zones are annuli (inner..radius).
ArenaLayout.LootZones = {
	{ name = "Spire", center = Vector3.new(CX, ArenaLayout.PlazaY, CZ), radius = 34, tier = 3, crates = 8, ground = 10, note = "crates at the Spire's CrateSlot_1..4 plus a ring around it; Feast refill needs >= 4 tier-3 markers within Config.Loot.SpireRefillRadius (90)" },
	{ name = "PlazaEdge", kind = "ring", center = Vector3.new(CX, ArenaLayout.PlazaY, CZ), inner = 62, radius = 90, tier = 3, crates = 4, ground = 6 },
	{ name = "MeadowEdge", kind = "ring", center = Vector3.new(CX, ArenaLayout.PlazaY, CZ), inner = 110, radius = 175, tier = 2, crates = 6, ground = 14, runnerCaches = 8, note = "at the treeline, spread around all angles; plus the 8 runner's caches (ArenaLayout.RunnerCaches, r 150-200): keep them" },
}

-- RunnerCaches (PlayabilityPlan QW7): one runner's cache per 45-degree sector at r 150-200, on open, level ground at
-- the meadow edge, each in sight of the three nearest launch plates (checked against the terrain: the 10-stud pole
-- top from all three, the crate from most). LootService builds a tier-2 crate (ItemDefs.LootTables.Runner) and a pale
-- canvas on a pole beside it. Loot markers: ServerStorage.ArenaData.LootSpawns parts named by `name` (Kind Crate,
-- Tier 2, Runner = true). groundY measured on TerrainVersion 2 (2026-11-11). facing = yaw toward the Spire.
-- Set dresser: keep 6 studs clear around each (crate + pole), and give each a landmark 6-10 studs away (`landmark`
-- is a suggestion: a lone tree, a boulder or a stump).
ArenaLayout.RunnerCaches = {
	{ name = "RunnerCache_1", angle = 28.5, r = 180, groundY = 38.97, landmark = "BoulderC" },
	{ name = "RunnerCache_2", angle = 68.5, r = 157.5, groundY = 37.82, landmark = "OakA" },
	{ name = "RunnerCache_3", angle = 112.5, r = 150, groundY = 45.76, landmark = "StumpA" },
	{ name = "RunnerCache_4", angle = 158.5, r = 150, groundY = 45.85, landmark = "BoulderB" },
	{ name = "RunnerCache_5", angle = 197.5, r = 157.5, groundY = 43.19, landmark = "SnagA" },
	{ name = "RunnerCache_6", angle = 251.5, r = 150, groundY = 47.07, landmark = "BirchA" },
	{ name = "RunnerCache_7", angle = 297.5, r = 192.5, groundY = 44.98, landmark = "FallenLogA" },
	{ name = "RunnerCache_8", angle = 339.5, r = 157.5, groundY = 45.30, landmark = "BoulderC" },
}
for _, c in ipairs(ArenaLayout.RunnerCaches) do
	c.position = polar(c.angle, c.r, c.groundY)
	c.facing = (c.angle + 180) % 360
end
for _, p in ipairs(ArenaLayout.POIs) do
	if p.kind ~= "Spire" then
		table.insert(ArenaLayout.LootZones, {
			name = p.name,
			center = p.position,
			radius = p.radius + 4,
			tier = p.tier,
			crates = (p.kind == "Campsite") and 1 or 2,
			ground = (p.kind == "Campsite") and 2 or 3,
			poi = p.name,
		})
	end
end

-- lootTierAt(position) -> 1 | 2 | 3 : the tier a loot marker at this position should use.
function ArenaLayout.lootTierAt(position: Vector3): number
	local x, z = position.X, position.Z
	local best = 1
	for _, zone in ipairs(ArenaLayout.LootZones) do
		local d = sqrt((x - zone.center.X) ^ 2 + (z - zone.center.Z) ^ 2)
		local inside
		if zone.kind == "ring" then
			inside = d >= (zone.inner or 0) and d <= zone.radius
		else
			inside = d <= zone.radius
		end
		if inside and zone.tier > best then
			best = zone.tier
		end
	end
	return best
end

-- dangerAt(position) -> 0..1: exposure and contest risk (near the Spire, open meadow/field, main water
-- sources and crossings = high; deep forest, caves, the far plateau = low). Use it to bias loot quality
-- (dangerous places deserve better loot) and for AI/spectator hints.
function ArenaLayout.dangerAt(position: Vector3): number
	local x, z = position.X, position.Z
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	local centre = 1 - smooth(40, 260, r)
	local biome = ArenaLayout.getBiome(position)
	local open = (biome == "Meadow" or biome == "Field") and 0.35 or ((biome == "Lake" or biome == "Marsh") and 0.2 or 0)
	local water = 1 - smooth(0, 40, ArenaLayout.distanceToWater(position))
	local crossing = 0
	for _, c in ipairs(ArenaLayout.Crossings) do
		crossing = max(crossing, 1 - smooth(0, 30, sqrt((x - c.position.X) ^ 2 + (z - c.position.Z) ^ 2)))
	end
	return math.clamp(centre * 0.7 + open + water * 0.2 + crossing * 0.15, 0, 1)
end

return ArenaLayout
