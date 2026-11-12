--[[
	TerrainGen (v2) - deterministic, re-runnable builder for the arena terrain (the CLASSIC FOREST ARENA), the
	lobby island, water, the terrain materials (MaterialService variants), the Boundary backstop and the
	TerrainData grid. Everything is driven by ReplicatedStorage.Shared.ArenaLayout (v2) and seeded by
	ArenaLayout.TerrainSeed, so the same code always produces the same arena.

	PIPELINE (generate):
	  1. coarse heightfield (8-stud cells): regional trend profiles + domain-warped fBm hills + ridged multifractal
	     ridges + knolls + designed landforms, the meadow surface (tilted toward the lake), the mountain wall,
	     broad pre-carved valleys and basins for the water
	  2. erosion on the coarse grid: thermal (talus angle by region) + droplet hydraulic erosion (gullies, drainage,
	     softened ridges, fans); it also records a flow map. Masked off the meadow, lake and marsh.
	  3. fine heightfield (4-stud cells = voxel columns): Catmull-Rom upsample + fine detail and rock knobs, the
	     escarpment (faces + scree aprons), the gorge (step-pool stream between stratified walls, raised rims), the
	     river/creek/outflow channels (asymmetric meander banks, point bars, fords), the falls amphitheatre and
	     plunge pool, the lake (shelves, beach, rocky banks, reed shallows, island), the marsh (pools and peat
	     hummocks), the plaza, gentle POI easing, cave aprons (a ramp meeting each cave floor).
	     Channel beds and banks are SET to the design after erosion (beds exact, so fords stay ~0.8 deep; banks
	     >= water + 0.45 for 6 studs, then easing away), every stepped section gets dry rock sills between its
	     pools, and the lake / marsh shaping never cuts a channel bank (chFloor).
	  3b. the mountain wall: a continuous cliff band all round between the border and the Boundary
	     (TerrainGen.Wall), applied after erosion: impassable on foot, by jumping and by mantling
	  4. fields: water levels (sealed: every water column is closed by banks or more water), slope, curvature,
	     moisture, distance to water and to cliffs, trails, nearW (the highest water level within 12 studs)
	  5. materials per column from slope, height, curvature, moisture, biome masks and noise breakup
	  6. voxels per 64x64 chunk with WriteVoxelChannels, computed with a one-column border: heightfield columns,
	     smooth 3D strata on real cliffs only (escarpment, gorge, falls, high mountains; never near water, on the
	     wall band or on forest knobs), the caves (tunnels with flat floors), the launch-tube trench under the plate
	     band (whole voxel cells, see TerrainGen.Tube; the SpirePlatform covers it), no solid in any voxel holding a
	     water surface, then a water-containment pass (no water voxel is left beside air)
	  7. the lobby island (unchanged from v1), look, materials, lighting (LightingRig when present), streaming,
	     the waterfall curtain (workspace.Arena.Waterfall), the Boundary, the SpirePlatform, the plinths, the loot markers
	     (seatLootMarkers), ServerStorage.WorldGen.TerrainData, Terrain attributes (TerrainVersion = 2)

	EDIT-MODE USAGE (execute_luau / command bar). Studio caches required modules, so require a clone:
	  local TG = require(game.ServerStorage.WorldGen.TerrainGen:Clone())
	  TG.start()                 -- full rebuild on a background thread (~5 s); watch the Terrain attributes
	                             --   TerrainGenStatus / TerrainGenProgress
	  TG.generate(opts)          -- the same, yielding in the caller
	  TG.applyLook()             -- terrain material colours, water, grass, clouds, waterfall mist
	  TG.applyMaterials()        -- MaterialService base-material overrides for the LS_* variants that exist
	  TG.applyLighting()         -- delegates to ServerStorage.WorldGen.LightingRig.apply() when it exists
	  TG.applyStreaming()
	  TG.buildBoundary()         -- the invisible backstop ring (workspace.Arena.Boundary)
	  TG.placeSpirePlatform()    -- workspace.Arena.SpirePlatform (from MeshAssets) over the plate-band trench
	  TG.placePlinths()          -- workspace.Arena.Plinths children onto ArenaLayout.Plates (keeps rotation)
	  TG.seatLootMarkers()       -- ServerStorage.ArenaData.LootSpawns onto the ground (out of water, bores, steeps)
	  TG.buildWaterfall()        -- workspace.Arena.Waterfall: the particle curtain and splash at River.fall
	  TG.writeData()             -- (re)write ServerStorage.WorldGen.TerrainData (5 channel child modules)
	  TG.verify() -> string      -- every check below, plus POI ground and cave floors (yields; ~15 s)
	  TG.check(name) -> string   -- one check: lattice, plaza, tubes, water, voxels, fords, mountains
	  TG.measure() -> string     -- measured POI / crossing heights as Lua text for ArenaLayout (POIHeights, CrossingHeights)
	  TG.heightAt(x, z)          -- ground height from the last generated grid (else ArenaLayout.heightAt)
	  TG.wallFoot(angle)         -- radius where the mountain wall's cliff band starts at that angle
	opts: clear (default true), island (true), look (true), lighting (true), streaming (true), boundary (true),
	      platform (true), plinths (true), loot (true), waterfall (true), data (true), markReady (true), erosion (true)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local CollectionService = game:GetService("CollectionService")

local TerrainGen = {}
TerrainGen.VERSION = 2

local function loadLayout()
	local source = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaLayout")
	if not RunService:IsRunning() then
		local ok, fresh = pcall(function()
			return require(source:Clone())
		end)
		if ok and type(fresh) == "table" then
			return fresh
		end
	end
	return require(source)
end

local Layout = loadLayout()
assert(Layout.Version == 2, "TerrainGen v2 needs ArenaLayout v2")

local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local sin, cos, rad, deg, atan2, exp, log = math.sin, math.cos, math.rad, math.deg, math.atan2, math.exp, math.log
local HUGE = math.huge
local noise = math.noise

local MAT = Enum.Material
local AIR = MAT.Air
-- Material roles (the LS_* MaterialVariants restyle these base materials, see TerrainGen.MaterialVariants):
local GRASS = MAT.Grass -- meadow grass (with terrain grass blades)
local LEAFY = MAT.LeafyGrass -- conifer forest floor (needles, leaves, moss)
local GROUND = MAT.Ground -- bare compacted earth (trails, banks, steep soil)
local MUD = MAT.Mud -- wet mud and peat
local SAND = MAT.Sand -- damp lake sand
local SALT = MAT.Salt -- river pebbles and gravel
local ROCK = MAT.Rock -- lichen-covered granite
local LIME = MAT.Limestone -- layered shale (strata bands)
local BASALT = MAT.Basalt -- scree / broken rock
local SNOW = MAT.Snow -- old snow
local SLATE = MAT.Slate -- (lobby island strata only, unchanged from v1)

local VOX = 4
local CHUNK = 64
local G0 = -960 -- grid origin (studs)
local FN = 480 -- fine cells per side (4 studs)
local CN = 240 -- coarse cells per side (8 studs)
local EMPTY = -1e9
local OUTER = Layout.TerrainRadius or 920
local CX, CZ = Layout.Center.X, Layout.Center.Z
local PLAZA_Y = Layout.PlazaY
local LAKE_Y = Layout.LakeLevel
local MARSH_Y = Layout.MarshLevel
local SHELL = 12 -- solid kept below the lowest surface of each chunk

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function clamp01(x: number): number
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

local function sstep(e0: number, e1: number, x: number): number
	local t = (x - e0) / (e1 - e0)
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local yieldClock = os.clock()
local function maybeYield()
	if os.clock() - yieldClock > 0.03 then
		task.wait()
		yieldClock = os.clock()
	end
end

----------------------------------------------------------------------------------------------------
-- noise (seeded offsets; values are scaled to roughly unit standard deviation)
----------------------------------------------------------------------------------------------------
local trng = Random.new(Layout.TerrainSeed or 2611)
local NX, NZ, NY = table.create(72), table.create(72), table.create(72)
for i = 1, 72 do
	NX[i] = trng:NextNumber(-600, 600) + 0.318
	NZ[i] = trng:NextNumber(-600, 600) + 0.627
	NY[i] = trng:NextNumber(-80, 80) + 0.141
end
local NK = 1 / 0.27 -- math.noise has a standard deviation of about 0.27

local function N(i: number, x: number, z: number, s: number): number
	return noise(x / s + NX[i], z / s + NZ[i], NY[i]) * NK
end

local function N3(i: number, x: number, y: number, z: number, s: number): number
	return noise(x / s + NX[i], y / s + NY[i], z / s + NZ[i]) * NK
end

local function fbm(i: number, x: number, z: number, s: number, oct: number): number
	local sum, amp, f, norm = 0, 1, 1 / s, 0
	local ox, oz, oy = NX[i], NZ[i], NY[i]
	for k = 0, oct - 1 do
		sum += amp * noise(x * f + ox + k * 7.31, z * f + oz - k * 5.17, oy + k * 1.93)
		norm += amp * amp
		amp *= 0.5
		f *= 2.03
	end
	return sum / sqrt(norm) * NK
end

-- ridged multifractal: 0..1, ridge lines near 1
local function ridged(i: number, x: number, z: number, s: number, oct: number): number
	local sum, amp, f, weight, norm = 0, 1, 1 / s, 1, 0
	local ox, oz, oy = NX[i], NZ[i], NY[i]
	for k = 0, oct - 1 do
		local n = noise(x * f + ox + k * 3.71, z * f + oz + k * 6.13, oy - k * 2.31) * 2.2
		local sig = 1 - abs(n)
		if sig < 0 then
			sig = 0
		end
		sig = sig * sig * weight
		weight = clamp01(sig * 1.6)
		sum += sig * amp
		norm += amp
		amp *= 0.5
		f *= 2.08
	end
	return sum / norm
end

----------------------------------------------------------------------------------------------------
-- layout geometry (fast forms)
----------------------------------------------------------------------------------------------------
local function polyPrep(poly)
	local p = { pts = poly, n = #poly, minX = HUGE, maxX = -HUGE, minZ = HUGE, maxZ = -HUGE }
	for _, v in ipairs(poly) do
		p.minX, p.maxX = min(p.minX, v[1]), max(p.maxX, v[1])
		p.minZ, p.maxZ = min(p.minZ, v[2]), max(p.maxZ, v[2])
	end
	return p
end

-- signed distance (negative inside); returns `far` when the point is more than `far` outside the bounding box
local function polySigned(P, x: number, z: number, far: number): number
	if x < P.minX - far or x > P.maxX + far or z < P.minZ - far or z > P.maxZ + far then
		return far
	end
	local pts, n = P.pts, P.n
	local best = HUGE
	local inside = false
	local j = n
	for i = 1, n do
		local a, b = pts[j], pts[i]
		local ax, az, bx, bz = a[1], a[2], b[1], b[2]
		if (bz > z) ~= (az > z) and x < (ax - bx) * (z - bz) / (az - bz) + bx then
			inside = not inside
		end
		local dx, dz = bx - ax, bz - az
		local l2 = dx * dx + dz * dz
		local u = 0
		if l2 > 1e-9 then
			u = ((x - ax) * dx + (z - az) * dz) / l2
			if u < 0 then
				u = 0
			elseif u > 1 then
				u = 1
			end
		end
		local qx, qz = x - (ax + dx * u), z - (az + dz * u)
		local d2 = qx * qx + qz * qz
		if d2 < best then
			best = d2
		end
		j = i
	end
	best = sqrt(best)
	return inside and -best or best
end

local LAKE_P = polyPrep(Layout.Lake.shore)
local MARSH_P = polyPrep(Layout.Marsh.outline)
local FIELD_P = polyPrep(Layout.Field.outline)
local LAKE_C = Layout.Lake.center
local ISLAND = Layout.Lake.island
local POOL = Layout.River.pool
local FALL_TOP = Layout.River.fallTop

-- channels: 1 = river, 2 = creek, 3 = outflow. Each sample gets curvature (kappa) for the meander banks.
local CHANNELS = {
	{ id = 1, samples = Layout.River.samples, reach = 70 },
	{ id = 2, samples = Layout.Creek.samples, reach = 42 },
	{ id = 3, samples = Layout.Outflow.samples, reach = 30 },
}
for _, ch in ipairs(CHANNELS) do
	local smp = ch.samples
	local n = #smp
	local raw = table.create(n, 0)
	for i = 1, n do
		local a, b = smp[max(1, i - 2)], smp[min(n, i + 2)]
		local c = smp[i]
		local t1x, t1z = c.x - a.x, c.z - a.z
		local t2x, t2z = b.x - c.x, b.z - c.z
		local l1, l2 = sqrt(t1x * t1x + t1z * t1z), sqrt(t2x * t2x + t2z * t2z)
		if l1 > 1e-6 and l2 > 1e-6 then
			local cr = (t1x * t2z - t1z * t2x) / (l1 * l2)
			raw[i] = cr / ((l1 + l2) * 0.5)
		end
	end
	for i = 1, n do
		local s, w = 0, 0
		for k = -3, 3 do
			local j = i + k
			if j >= 1 and j <= n then
				s += raw[j]
				w += 1
			end
		end
		smp[i].kappa = s / w
	end
	-- cascade points of the stepped sections (along-channel position s, upper pool level y): every cell within
	-- SILL_HALF studs (along the channel) of one becomes a dry rock sill, so a sill always separates two pools
	local cascades = {}
	for i = 2, n do
		local a, b = smp[i - 1], smp[i]
		if b.cascade and not (a.fall or b.fall) and a.y - b.y > 0.3 then
			table.insert(cascades, { s = (a.s + b.s) * 0.5, y = a.y })
		end
	end
	ch.cascades = cascades
end
local SILL_HALF = 3
local MIN_HW = 3.4
local RIVER_SAMPLES = Layout.River.samples
local POOL_S = Layout.River.poolS or 0
local LIP_S = Layout.River.lipS or 0

local CROSS = {}
for _, c in ipairs(Layout.Crossings) do
	CROSS[c.name] = c
end

----------------------------------------------------------------------------------------------------
-- 1. the regional trend: radial height profiles at key angles (Hermite-interpolated in r and in angle)
----------------------------------------------------------------------------------------------------
local R_KEYS = { 0, 150, 230, 300, 380, 460, 540, 620, 700, 800, 960 }
local PROFILES = {
	{ 0, { 47, 48, 58, 72, 90, 114, 136, 156, 172, 182, 190 } },
	{ 20, { 47, 48, 58, 72, 92, 114, 134, 152, 168, 178, 186 } },
	{ 40, { 47, 48, 57, 66, 86, 110, 128, 146, 160, 170, 178 } },
	{ 55, { 47, 48, 56, 58, 62, 84, 104, 122, 140, 152, 162 } },
	{ 75, { 47, 48, 56, 54, 60, 78, 96, 112, 128, 140, 150 } },
	{ 95, { 46, 47, 55, 51, 58, 76, 94, 108, 124, 136, 146 } },
	{ 115, { 46, 46, 50, 47, 56, 80, 98, 106, 120, 132, 142 } },
	{ 135, { 45, 45, 42, 42, 54, 84, 100, 108, 122, 134, 144 } },
	{ 160, { 45, 44, 40, 40, 46, 66, 88, 104, 120, 132, 142 } },
	{ 185, { 45, 44, 41, 39, 46, 62, 82, 100, 118, 130, 140 } },
	{ 210, { 46, 44, 41, 39, 38, 46, 66, 90, 112, 126, 136 } },
	{ 235, { 46, 45, 43, 40, 39, 48, 68, 92, 114, 128, 138 } },
	{ 255, { 47, 47, 49, 52, 56, 64, 80, 100, 118, 132, 142 } },
	{ 275, { 47, 48, 52, 57, 66, 70, 76, 92, 116, 132, 142 } },
	{ 300, { 48, 48, 54, 60, 70, 75, 80, 94, 116, 132, 142 } },
	{ 325, { 48, 49, 56, 64, 75, 81, 86, 100, 120, 134, 144 } },
	{ 345, { 48, 50, 58, 70, 84, 104, 126, 146, 164, 176, 186 } },
}
local NP = #PROFILES
local NR = #R_KEYS

local function hermite(y1: number, y2: number, m1: number, m2: number, t: number, h: number): number
	local t2, t3 = t * t, t * t * t
	return (2 * t3 - 3 * t2 + 1) * y1 + (t3 - 2 * t2 + t) * h * m1 + (-2 * t3 + 3 * t2) * y2 + (t3 - t2) * h * m2
end

local function radialValue(vals, r: number): number
	if r <= R_KEYS[1] then
		return vals[1]
	elseif r >= R_KEYS[NR] then
		return vals[NR]
	end
	local k = 1
	while R_KEYS[k + 1] < r do
		k += 1
	end
	local r1, r2 = R_KEYS[k], R_KEYS[k + 1]
	local y1, y2 = vals[k], vals[k + 1]
	local m1 = (k > 1) and (vals[k + 1] - vals[k - 1]) / (R_KEYS[k + 1] - R_KEYS[k - 1]) or (y2 - y1) / (r2 - r1)
	local m2 = (k + 2 <= NR) and (vals[k + 2] - vals[k]) / (R_KEYS[k + 2] - R_KEYS[k]) or (y2 - y1) / (r2 - r1)
	return hermite(y1, y2, m1, m2, (r - r1) / (r2 - r1), r2 - r1)
end

-- profile index helpers (wrap around 360 degrees)
local function profAt(idx: number)
	return PROFILES[((idx - 1) % NP) + 1]
end
local function angAt(idx: number): number
	return PROFILES[((idx - 1) % NP) + 1][1] + floor((idx - 1) / NP) * 360
end

local function trendAt(a: number, r: number): number
	local k = 0
	for i = 1, NP do
		if PROFILES[i][1] <= a then
			k = i
		end
	end
	local a1, a2 = angAt(k), angAt(k + 1)
	local a0, a3 = angAt(k - 1), angAt(k + 2)
	local aa = a
	if aa < a1 then
		aa += 360
	end
	local v0 = radialValue(profAt(k - 1)[2], r)
	local v1 = radialValue(profAt(k)[2], r)
	local v2 = radialValue(profAt(k + 1)[2], r)
	local v3 = radialValue(profAt(k + 2)[2], r)
	local h = a2 - a1
	local m1 = (v2 - v0) / (a2 - a0)
	local m2 = (v3 - v1) / (a3 - a1)
	return hermite(v1, v2, m1, m2, (aa - a1) / h, h)
end
TerrainGen._trendAt = trendAt

-- designed landforms (elliptical bumps / hollows): angle, r, along, across, heading, height
local LANDFORMS = {}
local function addForm(angle, r, along, across, heading, height)
	local c = Layout.polar(angle, r)
	local hr = rad(heading)
	table.insert(LANDFORMS, { x = c.X, z = c.Z, ax = sin(hr), az = -cos(hr), along = along, across = across, h = height })
end
addForm(128, 488, 120, 42, 40, 18) -- Watchtower ridge (NE-SW crest over the lake and the field)
addForm(176, 525, 150, 50, 100, 14) -- south ridge
addForm(350, 235, 46, 40, 20, 8) -- north knoll
addForm(62, 232, 70, 34, 160, 6) -- east ridge crest (CampEastRidge)
addForm(318, 268, 22, 22, 0, -2.5) -- GiantTree hollow
addForm(84, 445, 18, 18, 0, 2.5) -- FieldBoulder knoll
addForm(300, 548, 30, 30, 0, 3) -- CampPlateau knoll
addForm(34.5, 445, 15, 13, 30, 6) -- GorgeOverlook knoll
addForm(240, 470, 60, 40, 120, 9) -- SW forest hill beyond the marsh

local function landforms(x: number, z: number): number
	local sum = 0
	for _, f in ipairs(LANDFORMS) do
		local dx, dz = x - f.x, z - f.z
		local u = (dx * f.ax + dz * f.az) / f.along
		local v = (-dx * f.az + dz * f.ax) / f.across
		local q = u * u + v * v
		if q < 5 then
			sum += f.h * exp(-q * 1.6)
		end
	end
	return sum
end

local function hillsNoise(x: number, z: number, amp: number, ridgeAmp: number): number
	if amp <= 0 and ridgeAmp <= 0 then
		return 0
	end
	local wx = 85 * fbm(10, x, z, 460, 3)
	local wz = 85 * fbm(11, x, z, 460, 3)
	local px, pz = x + wx, z + wz
	local big = fbm(12, px, pz, 340, 4)
	local mid = fbm(17, px, pz, 190, 3)
	local knoll = fbm(14, px, pz, 110, 3)
	local bump = N(15, x, z, 38) * 0.7 + N(16, x, z, 19) * 0.3
	-- rolling hills: ~60 studs peak-to-trough over 300+ studs, ~25 over 190, knolls and hollows of ~15
	local h = amp * (big * 14 + mid * 6.5 + knoll * 4.2 + bump * 1.1)
	if ridgeAmp > 0 then
		local rg = ridged(13, px * 0.92 + 31.7, pz * 0.92 - 17.3, 270, 4)
		h += ridgeAmp * (rg - 0.42) * 40
	end
	return h
end

local function meadowHeight(x: number, z: number, r: number, a: number): number
	local tilt = 2.4 * cos(rad(a - 338)) * clamp01(r / 150) ^ 1.3
	local und = 1.5 * fbm(20, x, z, 75, 3) + 0.45 * N(21, x, z, 26)
	local rim = 2.2 * sstep(105, 175, r)
	return PLAZA_Y + tilt + und * sstep(30, 90, r) + rim
end

local function mountainUplift(x: number, z: number, r: number, a: number): (number, number)
	local Rm = Layout.mountainEdge(a) + 10 * N(5, x, z, 150)
	local u = r - Rm
	if u < -70 then
		return 0, u
	end
	local foot = 24 * sstep(-70, 0, u)
	local wall = (88 + 26 * N(6, x, z, 120)) * sstep(-6, 34, u)
	local massif = 0
	if u > 10 then
		-- broad massifs (a low-frequency envelope) carrying warped ridged crests: fewer, bigger peaks and real saddles
		local env = 0.5 + 0.5 * clamp01(0.5 + 0.45 * fbm(9, x, z, 420, 2))
		local rg = ridged(7, x + 70 * fbm(10, x, z, 260, 2), z + 70 * fbm(11, x, z, 260, 2), 300, 5)
		massif = (34 + 190 * rg ^ 1.7 * env) * sstep(10, 210, u)
	end
	local rough = 7 * fbm(8, x, z, 55, 3) * sstep(-10, 40, u)
	return foot + wall + massif + rough, u
end

----------------------------------------------------------------------------------------------------
-- stage 1: coarse heightfield
----------------------------------------------------------------------------------------------------
local function naturalAt(x: number, z: number)
	local dx, dz = x - CX, z - CZ
	local r = sqrt(dx * dx + dz * dz)
	local a = deg(atan2(dx, -dz)) % 360
	local base = trendAt(a, r)
	local medge = Layout.meadowEdge(a)
	local meadowW = 1 - sstep(medge - 28, medge + 38, r)
	local fieldW = 1 - sstep(-25, 30, polySigned(FIELD_P, x, z, 120))
	local lakeSD = polySigned(LAKE_P, x, z, 150)
	local lakeW = 1 - sstep(0, 70, lakeSD)
	local marshSD = polySigned(MARSH_P, x, z, 120)
	local marshW = 1 - sstep(-5, 50, marshSD)
	local amp = (1 - meadowW) * lerp(1, 0.2, fieldW) * lerp(1, 0.3, lakeW) * lerp(1, 0.12, marshW)
	local ramp = (1 - meadowW) * (1 - fieldW) * (1 - lakeW * 0.85) * (1 - marshW)
	local h = base + hillsNoise(x, z, amp, ramp) + landforms(x, z)
	-- keep the basin readable: a soft floor, so the forest never sinks into deep pits beside the meadow or below the
	-- lake (dips under it are compressed, never flattened)
	local floorY = max(LAKE_Y + 3, PLAZA_Y - 3 - 0.02 * max(0, r - medge))
	if h < floorY then
		h = floorY - (floorY - h) * 0.3
	end
	if meadowW > 0 then
		h = lerp(h, meadowHeight(x, z, r, a), meadowW)
	end
	local up, u = mountainUplift(x, z, r, a)
	h += up
	local em = (1 - meadowW) * (1 - lakeW * 0.9) * (1 - marshW * 0.85) * lerp(1, 0.5, fieldW)
	local tl = lerp(0.70, 0.45, fieldW)
	if u > -14 then
		tl = lerp(tl, 2.3, sstep(-14, 8, u))
	end
	if meadowW > 0.5 or lakeSD < 12 or marshSD < 8 then
		tl = 99
	end
	return h, em, tl
end

-- iterate fine/coarse cells near a segment: calls fn(k, x, z, d, side, u) for cells within reach
local function stampSegment(n: number, cell: number, a, b, reach: number, fn)
	local x0, x1 = min(a.x, b.x) - reach, max(a.x, b.x) + reach
	local z0, z1 = min(a.z, b.z) - reach, max(a.z, b.z) + reach
	local i0, i1 = max(0, floor((x0 - G0) / cell)), min(n - 1, floor((x1 - G0) / cell))
	local j0, j1 = max(0, floor((z0 - G0) / cell)), min(n - 1, floor((z1 - G0) / cell))
	local dx, dz = b.x - a.x, b.z - a.z
	local l2 = dx * dx + dz * dz
	local half = cell * 0.5
	for j = j0, j1 do
		local z = G0 + j * cell + half
		for i = i0, i1 do
			local x = G0 + i * cell + half
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
			local d = sqrt(qx * qx + qz * qz)
			if d < reach then
				local side = dx * qz - dz * qx
				fn(j * n + i + 1, x, z, d, side, u)
			end
		end
	end
end

local function buildCoarse(S)
	local n = CN
	local Hc = table.create(n * n, 0)
	local em = table.create(n * n, 0)
	local tal = table.create(n * n, 99)
	for j = 0, n - 1 do
		local z = G0 + 8 * j + 4
		for i = 0, n - 1 do
			local x = G0 + 8 * i + 4
			local k = j * n + i + 1
			Hc[k], em[k], tal[k] = naturalAt(x, z)
		end
		maybeYield()
	end
	-- broad valleys for the lowland river, the creek and the outflow (so erosion drains into them)
	for _, ch in ipairs(CHANNELS) do
		local smp = ch.samples
		for si = 1, #smp - 1 do
			local a, b = smp[si], smp[si + 1]
			local lowland = ch.id ~= 1 or a.s >= POOL_S
			if lowland then
				local slope = (ch.id == 1) and 0.3 or ((ch.id == 2) and 0.45 or 0.2)
				if ch.id == 1 and a.s - POOL_S < 110 then
					slope = 0.95
				end
				stampSegment(n, 8, a, b, ch.reach, function(k, x, z, d, side, u)
					local W = a.y + (b.y - a.y) * u
					local hw = a.hw + (b.hw - a.hw) * u
					local e = max(0, d - hw - 3)
					local up = W + 2.2 + slope * e + 0.006 * e * e
					if Hc[k] > up then
						Hc[k] = up
					end
					tal[k] = max(tal[k], 0.9)
				end)
			end
		end
		maybeYield()
	end
	-- lake and marsh basins
	for j = 0, n - 1 do
		local z = G0 + 8 * j + 4
		for i = 0, n - 1 do
			local x = G0 + 8 * i + 4
			local k = j * n + i + 1
			local sd = polySigned(LAKE_P, x, z, 90)
			if sd < 90 then
				local cap
				if sd < 0 then
					cap = LAKE_Y - 1.5 - 7 * sstep(0, 40, -sd)
				else
					cap = LAKE_Y + 1.2 + 0.2 * sd + 0.004 * sd * sd
				end
				if Hc[k] > cap then
					Hc[k] = cap
				end
			end
			local md = polySigned(MARSH_P, x, z, 90)
			if md < 90 then
				if md < 0 then
					Hc[k] = lerp(Hc[k], MARSH_Y + 0.4, sstep(-2, 20, -md))
				else
					local cap = MARSH_Y + 1.0 + 0.22 * md + 0.004 * md * md
					if Hc[k] > cap then
						Hc[k] = cap
					end
				end
			end
		end
		maybeYield()
	end
	S.Hc, S.em, S.tal = Hc, em, tal
end

----------------------------------------------------------------------------------------------------
-- stage 2: erosion (coarse grid, heights in cell units = studs / 8)
----------------------------------------------------------------------------------------------------
TerrainGen.Erosion = {
	droplets = 110000,
	lifetime = 48,
	inertia = 0.08,
	capacity = 0.12,
	minCapacity = 0.003,
	erode = 0.32,
	deposit = 0.22,
	evaporate = 0.018,
	gravity = 6,
	radius = 2,
	thermalBefore = 5,
	thermalAfter = 8,
	thermalRate = 0.4,
}

local function thermal(hu, tal, iters: number, rate: number)
	local n = CN
	local D2 = 1.41421356
	for _ = 1, iters do
		for j = 1, n - 2 do
			for i = 1, n - 2 do
				local k = j * n + i + 1
				local t = tal[k]
				if t < 50 then
					local h = hu[k]
					local best, bk = 0, 0
					local e
					e = h - hu[k - 1] - t
					if e > best then
						best, bk = e, k - 1
					end
					e = h - hu[k + 1] - t
					if e > best then
						best, bk = e, k + 1
					end
					e = h - hu[k - n] - t
					if e > best then
						best, bk = e, k - n
					end
					e = h - hu[k + n] - t
					if e > best then
						best, bk = e, k + n
					end
					e = h - hu[k - n - 1] - t * D2
					if e > best then
						best, bk = e, k - n - 1
					end
					e = h - hu[k - n + 1] - t * D2
					if e > best then
						best, bk = e, k - n + 1
					end
					e = h - hu[k + n - 1] - t * D2
					if e > best then
						best, bk = e, k + n - 1
					end
					e = h - hu[k + n + 1] - t * D2
					if e > best then
						best, bk = e, k + n + 1
					end
					if best > 0 then
						local m = best * 0.5 * rate
						hu[k] = h - m
						hu[bk] += m
					end
				end
			end
		end
		maybeYield()
	end
end

local function hydraulic(hu, em, flow, P, seed: number)
	local n = CN
	local rng = Random.new(seed)
	local R = P.radius
	local bOff, bW = {}, {}
	local wsum = 0
	for dz = -R, R do
		for dx = -R, R do
			local d = sqrt(dx * dx + dz * dz)
			if d <= R then
				local w = 1 - d / (R + 0.5)
				table.insert(bOff, dz * n + dx)
				table.insert(bW, w)
				wsum += w
			end
		end
	end
	for b = 1, #bW do
		bW[b] /= wsum
	end
	local nb = #bW
	local inertia, capF, minCap = P.inertia, P.capacity, P.minCapacity
	local erodeK, depositK, evap, grav = P.erode, P.deposit, P.evaporate, P.gravity
	local lo, hi = R + 1, n - R - 2
	for drop = 1, P.droplets do
		local x, z
		for _ = 1, 10 do
			local tx, tz = rng:NextNumber(lo, hi), rng:NextNumber(lo, hi)
			local m = em[floor(tz) * n + floor(tx) + 1]
			if m > 0.02 and rng:NextNumber() < m then
				x, z = tx, tz
				break
			end
		end
		if x then
			local dirX, dirZ, speed, water, sed = 0, 0, 1, 1, 0
			for _ = 1, P.lifetime do
				local ix, iz = floor(x), floor(z)
				local fx, fz = x - ix, z - iz
				local k = iz * n + ix + 1
				local h00, h10, h01, h11 = hu[k], hu[k + 1], hu[k + n], hu[k + n + 1]
				local gx = (h10 - h00) * (1 - fz) + (h11 - h01) * fz
				local gz = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
				local hOld = (h00 * (1 - fx) + h10 * fx) * (1 - fz) + (h01 * (1 - fx) + h11 * fx) * fz
				dirX = dirX * inertia - gx * (1 - inertia)
				dirZ = dirZ * inertia - gz * (1 - inertia)
				local len = sqrt(dirX * dirX + dirZ * dirZ)
				if len < 1e-7 then
					break
				end
				dirX /= len
				dirZ /= len
				local nx, nz = x + dirX, z + dirZ
				if nx < lo or nx >= hi or nz < lo or nz >= hi then
					break
				end
				local jx, jz = floor(nx), floor(nz)
				local ux, uz = nx - jx, nz - jz
				local k2 = jz * n + jx + 1
				local hNew = (hu[k2] * (1 - ux) + hu[k2 + 1] * ux) * (1 - uz) + (hu[k2 + n] * (1 - ux) + hu[k2 + n + 1] * ux) * uz
				local dh = hNew - hOld
				local m = em[k]
				local cap = -dh * speed * water * capF
				if cap < minCap then
					cap = minCap
				end
				if sed > cap or dh > 0 then
					local amt = (dh > 0) and min(dh, sed) or (sed - cap) * depositK
					sed -= amt
					amt *= m
					hu[k] += amt * (1 - fx) * (1 - fz)
					hu[k + 1] += amt * fx * (1 - fz)
					hu[k + n] += amt * (1 - fx) * fz
					hu[k + n + 1] += amt * fx * fz
				else
					local amt = min((cap - sed) * erodeK, -dh) * m
					for b = 1, nb do
						local kk = k + bOff[b]
						hu[kk] -= amt * bW[b]
					end
					sed += amt
				end
				flow[k] += water
				local s2 = speed * speed - dh * grav
				speed = (s2 > 0) and sqrt(s2) or 0
				water *= (1 - evap)
				x, z = nx, nz
			end
		end
		if drop % 1500 == 0 then
			maybeYield()
		end
	end
end

local function erodeCoarse(S, enabled: boolean)
	local n = CN
	local Hc, em, tal = S.Hc, S.em, S.tal
	local hu = table.create(n * n, 0)
	for k = 1, n * n do
		hu[k] = Hc[k] / 8
	end
	local flow = table.create(n * n, 0)
	local P = TerrainGen.Erosion
	if enabled then
		thermal(hu, tal, P.thermalBefore, P.thermalRate)
		hydraulic(hu, em, flow, P, (Layout.TerrainSeed or 2611) + 17)
		thermal(hu, tal, P.thermalAfter, P.thermalRate)
	end
	local sumD, maxD = 0, 0
	for k = 1, n * n do
		local h = hu[k] * 8
		local d = abs(h - Hc[k])
		sumD += d
		if d > maxD then
			maxD = d
		end
		Hc[k] = h
	end
	-- flow map -> 0..1 (log scale, normalised by the 99th percentile)
	local sorted = {}
	for k = 1, n * n, 7 do
		if flow[k] > 0 then
			table.insert(sorted, flow[k])
		end
	end
	table.sort(sorted)
	local p99 = sorted[max(1, floor(#sorted * 0.99))] or 1
	local norm = log(1 + p99)
	for k = 1, n * n do
		flow[k] = clamp01(log(1 + flow[k]) / norm)
	end
	S.flowC = flow
	S.erosionStats = string.format("erosion mean|dh| %.2f max %.1f", sumD / (n * n), maxD)
end

----------------------------------------------------------------------------------------------------
-- stage 3: fine heightfield and features
----------------------------------------------------------------------------------------------------
local W25 = { -0.0703125, 0.8671875, 0.2265625, -0.0234375 }
local W75 = { -0.0234375, 0.2265625, 0.8671875, -0.0703125 }

local function upsample(Hc, out)
	local tmp = table.create(FN * CN, 0)
	for jc = 0, CN - 1 do
		local row = jc * CN
		for i = 0, FN - 1 do
			local b = floor(i * 0.5 - 0.25)
			local w = (i % 2 == 0) and W75 or W25
			local s = 0
			for t = 0, 3 do
				local ic = b - 1 + t
				if ic < 0 then
					ic = 0
				elseif ic > CN - 1 then
					ic = CN - 1
				end
				s += w[t + 1] * Hc[row + ic + 1]
			end
			tmp[jc * FN + i + 1] = s
		end
		maybeYield()
	end
	for j = 0, FN - 1 do
		local b = floor(j * 0.5 - 0.25)
		local w = (j % 2 == 0) and W75 or W25
		for i = 0, FN - 1 do
			local s = 0
			for t = 0, 3 do
				local jc = b - 1 + t
				if jc < 0 then
					jc = 0
				elseif jc > CN - 1 then
					jc = CN - 1
				end
				s += w[t + 1] * tmp[jc * FN + i + 1]
			end
			out[j * FN + i + 1] = s
		end
		maybeYield()
	end
end

local function bilinearCoarse(arr, x: number, z: number): number
	local fx = (x - G0) / 8 - 0.5
	local fz = (z - G0) / 8 - 0.5
	local ix, iz = floor(fx), floor(fz)
	if ix < 0 then
		ix, fx = 0, 0
	elseif ix > CN - 2 then
		ix, fx = CN - 2, CN - 2
	end
	if iz < 0 then
		iz, fz = 0, 0
	elseif iz > CN - 2 then
		iz, fz = CN - 2, CN - 2
	end
	local tx, tz = fx - ix, fz - iz
	local k = iz * CN + ix + 1
	return (arr[k] * (1 - tx) + arr[k + 1] * tx) * (1 - tz) + (arr[k + CN] * (1 - tx) + arr[k + CN + 1] * tx) * tz
end

local ESC = Layout.Escarpment

local function buildFine(S)
	local n = FN
	local F = table.create(n * n, 0)
	upsample(S.Hc, F)
	local flow = table.create(n * n, 0)
	-- per-cell region info used later by the materials
	local rMeadow = table.create(n * n, 0)
	local rField = table.create(n * n, 999)
	local rLake = table.create(n * n, 999)
	local rMarsh = table.create(n * n, 999)
	local rEsc = table.create(n * n, 999) -- signed distance to the escarpment top edge (999 = none)
	local rEscH = table.create(n * n, 0) -- cliff height there
	local rMtn = table.create(n * n, -999) -- mountain u (r - mountain edge)
	local rRock = table.create(n * n, 0) -- 0..1 rock-knob / outcrop strength
	for j = 0, n - 1 do
		local z = G0 + 4 * j + 2
		for i = 0, n - 1 do
			local x = G0 + 4 * i + 2
			local k = j * n + i + 1
			local dx, dz = x - CX, z - CZ
			local r = sqrt(dx * dx + dz * dz)
			if r > OUTER then
				F[k] = EMPTY
			else
				local a = deg(atan2(dx, -dz)) % 360
				local medge = Layout.meadowEdge(a)
				local mw = 1 - sstep(medge - 20, medge + 30, r)
				rMeadow[k] = mw
				local fs = polySigned(FIELD_P, x, z, 60)
				local ls = polySigned(LAKE_P, x, z, 80)
				local ms = polySigned(MARSH_P, x, z, 60)
				rField[k], rLake[k], rMarsh[k] = fs, ls, ms
				local u = r - Layout.mountainEdge(a)
				rMtn[k] = u
				local forestish = (1 - mw) * sstep(0, 40, fs) * sstep(0, 30, ls) * sstep(0, 30, ms)
				local amp = lerp(0.15, 1, (1 - mw)) * lerp(0.35, 1, sstep(-10, 30, fs)) * lerp(0.25, 1, sstep(-6, 24, ls)) * lerp(0.25, 1, sstep(0, 24, ms))
				if u > 0 then
					amp = lerp(amp, 2.2, sstep(0, 40, u))
				end
				local detail = amp * (1.3 * fbm(22, x, z, 30, 2) + 0.45 * N(23, x, z, 11))
				-- rock knobs / outcrops in the forest and on the plateaus: rare, low, smooth domes elongated along the
				-- bedding (rock shows on their flanks, soil on their tops; the set dresser adds RockOutcrop meshes)
				local o = N(24, x * 0.86 + z * 0.5, (z * 0.86 - x * 0.5) * 1.7, 70) - 2.05
				local knob = 0
				if o > 0 and forestish > 0 then
					knob = 6.5 * sstep(0, 0.75, o) * forestish
					rRock[k] = clamp01(o * 2.5 + 0.25 * N(25, x, z, 23)) * forestish
				end
				F[k] += detail + knob
				flow[k] = bilinearCoarse(S.flowC, x, z)
				-- the escarpment: face + scree apron in front, plateau behind
				if r > 360 and (a >= 255 and a <= 346) then
					local rTop, H, scree = ESC.at(a)
					if rTop and H > 0.5 then
						rTop += 3.2 * N(40, x, z, 34) + 0.5 * N(41, x, z, 11)
						H *= 1 + 0.1 * N(42, x, z, 90)
						local fw = 7 + 2.5 * (0.5 + 0.5 * clamp01(0.5 + 0.25 * N(43, x, z, 50)))
						local d = r - rTop
						local add
						if d >= 0 then
							local t = 1 - min(1, d / 5)
							add = H - 1.4 * t * t
						elseif d > -fw then
							add = H * ((d + fw) / fw) ^ 1.25
						else
							local uu = -(d + fw)
							if scree > 0.5 and uu < scree then
								add = 0.36 * H * (1 - uu / scree) ^ 1.6
							else
								add = 0
							end
						end
						F[k] += add
						rEsc[k] = d
						rEscH[k] = H
					end
				end
			end
		end
		maybeYield()
	end
	S.F, S.flow = F, flow
	S.rMeadow, S.rField, S.rLake, S.rMarsh, S.rEsc, S.rEscH, S.rMtn, S.rRock = rMeadow, rField, rLake, rMarsh, rEsc, rEscH, rMtn, rRock
end

-- nearest channel per fine cell (river / creek / outflow), then carve
local function stampChannels(S)
	local n = FN
	local chD = table.create(n * n, HUGE)
	local chId = table.create(n * n, 0)
	local chSeg = table.create(n * n, 0)
	local chU = table.create(n * n, 0)
	local chSide = table.create(n * n, 0)
	for _, ch in ipairs(CHANNELS) do
		local smp = ch.samples
		local id = ch.id
		for si = 1, #smp - 1 do
			local a, b = smp[si], smp[si + 1]
			local reach = a.hw + ((id == 1 and a.gorge == 1) and 46 or ch.reach)
			stampSegment(n, 4, a, b, reach, function(k, x, z, d, side, u)
				local key = d - (a.hw + (b.hw - a.hw) * u) * 0.5
				local cur = chD[k]
				if cur == HUGE or key < cur then
					chD[k] = key
					chId[k] = id
					chSeg[k] = si
					chU[k] = u
					chSide[k] = (side >= 0) and d or -d
				end
			end)
		end
		maybeYield()
	end
	S.chD, S.chId, S.chSeg, S.chU, S.chSide = chD, chId, chSeg, chU, chSide
end

local function channelParams(id: number, seg: number, u: number)
	local smp = CHANNELS[id].samples
	local a, b = smp[seg], smp[min(seg + 1, #smp)]
	local W = a.y + (b.y - a.y) * u
	local hw = a.hw + (b.hw - a.hw) * u
	local depth = a.depth + (b.depth - a.depth) * u
	local gorge = a.gorge + ((b.gorge or 0) - (a.gorge or 0)) * u
	local ford = (a.ford or 0) + ((b.ford or 0) - (a.ford or 0)) * u
	local s = a.s + (b.s - a.s) * u
	local kappa = (a.kappa or 0) + ((b.kappa or 0) - (a.kappa or 0)) * u
	local fall = (a.fall or b.fall) and true or false
	-- next to a cascade the bed is a dry rock sill at the upper level, so every step pool is held by rock on its
	-- downstream side (terrain water cannot flow: a water step would stand against air)
	local sill = nil
	if not fall then
		for _, c in ipairs(CHANNELS[id].cascades) do
			if abs(s - c.s) < SILL_HALF then
				sill = c.y
				break
			end
		end
	end
	-- a channel narrower than about two voxel columns is hidden by its banks (a full voxel's surface reaches ~1.8
	-- studs into its neighbour: measured), so the creek and the stream above the falls are at least MIN_HW wide
	if id == 2 or (id == 1 and s < LIP_S) then
		hw = max(hw, MIN_HW)
	end
	return W, hw, depth, gorge, ford, s, kappa, fall, sill
end

local function nearCrossing(name: string, x: number, z: number, radius: number): number
	local c = CROSS[name]
	if not c then
		return 0
	end
	local d = sqrt((x - c.position.X) ^ 2 + (z - c.position.Z) ^ 2)
	return 1 - sstep(radius * 0.5, radius, d)
end

local function carveChannels(S)
	local n = FN
	local F, chD, chId, chSeg, chU, chSide = S.F, S.chD, S.chId, S.chSeg, S.chU, S.chSide
	local WL = S.WL
	local chW = table.create(n * n, EMPTY) -- water level of the nearest channel (for the 3D wall fade)
	local chFloor = table.create(n * n, EMPTY) -- lowest the ground may be here and still hold the channel's water
	local sillCell = table.create(n * n, false) -- dry rock sills between step pools
	for k = 1, n * n do
		local id = chId[k]
		if id > 0 and F[k] ~= EMPTY then
			local j = (k - 1) // n
			local i = (k - 1) - j * n
			local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
			local W, hw, depth, gorge, ford, s, kappa, fall, sill = channelParams(id, chSeg[k], chU[k])
			local sd = chSide[k]
			local d = abs(sd)
			local h = F[k]
			if fall then
				W, gorge = FALL_TOP, 1
			end
			if sill then
				W = sill
			end
			hw += 2.2 * ford
			depth = lerp(depth, 0.55, ford) -- renders about 0.8 deep (beds under water render a little low)
			-- The bed and the banks follow the design exactly. Erosion runs before the channels and can dig the
			-- valley floor below the water (fords 5 deep, banks lower than the stream), so the bed is SET, not only
			-- capped, and the banks never fall below the water near the channel (they ease away beyond 6 studs).
			if id == 1 and gorge > 0.5 then
				-- the gorge: stream bed, a narrow gravel margin, steep walls; raised rims
				local log = nearCrossing("GorgeLog", x, z, 34)
				local bridge = nearCrossing("GorgeFootbridge", x, z, 38)
				local floorHW = hw + lerp(1.6 + 1.2 * (0.5 + 0.5 * clamp01(0.5 + 0.3 * N(44, s, 0, 40))), 0.6, log)
				local steep = lerp(3.4 + 2.2 * clamp01(0.5 + 0.3 * N(45, s, 7, 55)), 6.5, log)
				steep = lerp(steep, 4.2, bridge)
				h += 6.5 * (1 - sstep(floorHW + 4, floorHW + 42, d)) * gorge
				if sill and d < floorHW then
					h = W + 0.3 -- a rock sill across the floor between two step pools
					sillCell[k] = true
					chFloor[k] = h
				elseif d < hw then
					local q = d / hw
					h = W - max(0.3, depth * (1 - q * q) ^ 0.7)
				elseif d < floorHW then
					h = W + 0.35 + 0.15 * (d - hw)
				else
					local cap = W + 0.6 + (d - floorHW) * steep
					if h > cap then
						h = cap
					end
					local fl = W + 0.6 - max(0, d - floorHW - 6) * 0.5
					if h < fl then
						h = fl
					end
					chFloor[k] = fl
				end
				if d < floorHW + 2 then
					chW[k] = W
				end
			else
				-- lowland channel: thalweg toward the outer bank, steep cut bank, gentle point bar
				local A = clamp01(abs(kappa) * 35)
				local ks = (kappa >= 0) and 1 or -1
				local outer = (sd * ks) < 0
				local thal = -ks * 0.35 * A * hw
				if d < hw then
					if sill then
						h = W + 0.3
						sillCell[k] = true
						chFloor[k] = h
					else
						local q = (sd - thal) / hw
						local prof = 1 - q * q
						if prof < 0 then
							prof = 0
						end
						h = W - max(0.3, depth * prof ^ 0.8)
					end
				else
					local e = d - hw
					local cliffSide = (id == 2) and (S.rEsc[k] > -12) and e > 1.5
					local slope
					if outer then
						slope = lerp(0.55, 1.6, A)
					else
						slope = lerp(0.45, 0.12, A)
					end
					if id == 1 and s - POOL_S < 120 and s > POOL_S then
						slope = max(slope, 1.15) -- the ravine below the falls
					end
					local cap = W + 0.45 + slope * e + 0.010 * e * e
					if h > cap and not cliffSide then
						h = cap
					end
					-- the banks hold the water: at least W + 0.45 for 6 studs, then easing away at <= 27 degrees
					local fl = W + 0.45 - max(0, e - 6) * 0.5
					if h < fl then
						h = fl
					end
					chFloor[k] = fl
				end
				if d < hw + 1.5 then
					chW[k] = W
				end
			end
			F[k] = h
			if d < hw + 0.9 and not fall and not sill then
				WL[k] = max(WL[k], W)
			end
		end
		if k % 4000 == 0 then
			maybeYield()
		end
	end
	S.chW, S.chFloor, S.sillCell = chW, chFloor, sillCell
end

-- the falls amphitheatre and the plunge pool
local function carveFalls(S)
	local n = FN
	local F, WL = S.F, S.WL
	local P = POOL.center
	-- downstream direction from the pool, and the lip direction
	local nxt
	for _, smp in ipairs(RIVER_SAMPLES) do
		if smp.s > POOL_S + 14 then
			nxt = smp
			break
		end
	end
	local dnx, dnz = 1, 0
	if nxt then
		dnx, dnz = nxt.x - P.X, nxt.z - P.Z
		local l = sqrt(dnx * dnx + dnz * dnz)
		dnx, dnz = dnx / l, dnz / l
	end
	local L = Layout.River.fall.lip
	local lpx, lpz = L.X - P.X, L.Z - P.Z
	local lipDist = sqrt(lpx * lpx + lpz * lpz)
	local lx, lz = lpx / lipDist, lpz / lipDist
	local Rw = 21
	local floorY = POOL.level + 1.6
	local sheetHW = 5.4 + 1.2
	local reach = 64
	local i0, i1 = max(0, floor((P.X - reach - G0) / 4)), min(n - 1, floor((P.X + reach - G0) / 4))
	local j0, j1 = max(0, floor((P.Z - reach - G0) / 4)), min(n - 1, floor((P.Z + reach - G0) / 4))
	S.fallSheet = {}
	for j = j0, j1 do
		local z = G0 + 4 * j + 2
		for i = i0, i1 do
			local x = G0 + 4 * i + 2
			local k = j * n + i + 1
			local px, pz = x - P.X, z - P.Z
			local rho = sqrt(px * px + pz * pz)
			if rho < reach then
				local c = (rho > 1e-6) and (px * dnx + pz * dnz) / rho or 0
				local open = sstep(0.1, 0.62, c)
				local rw = Rw + 1.6 * N(46, x, z, 14)
				local h = F[k]
				-- lateral distance from the pool->lip axis (the falls corridor)
				local along = px * lx + pz * lz
				local lat = abs(-px * lz + pz * lx)
				local corridor = (along > 0 and lat < sheetHW) and (1 - sstep(sheetHW - 2, sheetHW, lat)) or 0
				local wall = floorY + max(0, rho - rw) * 8.5
				local cap = lerp(wall, h, open)
				if corridor > 0 and rho < lipDist + 2 then
					-- the gorge stream runs to the face; below it the pool reaches the face
					cap = min(cap, lerp(cap, POOL.level - 3, corridor * (1 - sstep(rw - 1, rw + 1.5, rho))))
				end
				if h > cap then
					h = cap
				end
				if rho < POOL.radius then
					local q = rho / POOL.radius
					local bed = POOL.level - 6.2 * (1 - q * q) ^ 0.8
					if h > bed then
						h = bed
					end
				elseif rho < rw and corridor < 0.5 then
					local mrg = floorY + 0.6 * (rho - POOL.radius) / max(1, rw - POOL.radius)
					if h > mrg then
						h = mrg
					end
					if h < POOL.level + 0.45 and open < 0.5 and WL[k] <= h then
						h = POOL.level + 0.45
					end
				end
				F[k] = h
				-- the pool, and its arm under the falls up to the foot of the face
				if rho < POOL.radius + 0.5 or (corridor > 0.25 and rho < rw + 1.5 and h < POOL.level - 0.2) then
					WL[k] = max(WL[k], POOL.level)
				end
				-- The falling water itself is not terrain (terrain water cannot flow: a column of it reads as a
				-- static block of gel). The chute stays dry rock; buildWaterfall() hangs a particle curtain from the
				-- lip to the pool. S.fallSheet keeps the chute cells for the cascade bookkeeping.
				if corridor > 0.5 and rho >= rw - 5 and rho < lipDist + 1 then
					table.insert(S.fallSheet, k)
				end
			end
		end
	end
end

local function carveLake(S)
	local n = FN
	local F, WL, rLake = S.F, S.WL, S.rLake
	local style = Layout.Lake.shoreStyle
	local reach = 80
	local i0 = max(0, floor((LAKE_P.minX - reach - G0) / 4))
	local i1 = min(n - 1, floor((LAKE_P.maxX + reach - G0) / 4))
	local j0 = max(0, floor((LAKE_P.minZ - reach - G0) / 4))
	local j1 = min(n - 1, floor((LAKE_P.maxZ + reach - G0) / 4))
	local IC = ISLAND.center
	for j = j0, j1 do
		local z = G0 + 4 * j + 2
		for i = i0, i1 do
			local x = G0 + 4 * i + 2
			local k = j * n + i + 1
			local sd = rLake[k]
			if sd < reach and F[k] ~= EMPTY then
				local phi = deg(atan2(x - LAKE_C.X, -(z - LAKE_C.Z))) % 360
				local st = style(phi)
				local h = F[k]
				if sd < 0 then
					local dIn = -sd
					local shelfW = lerp(lerp(16, 6, st.rocky), 38, st.reeds)
					local shelfD = lerp(lerp(2.4, 3.2, st.rocky), 1.1, st.reeds)
					local maxD = 11 + 2 * N(47, x, z, 70)
					local bed = LAKE_Y - 0.35 - shelfD * sstep(0, shelfW, dIn) - (maxD - shelfD) * sstep(shelfW, shelfW + 46, dIn)
					bed += 0.45 * N(48, x, z, 13) * sstep(0, 8, dIn)
					if h > bed then
						h = bed
					end
					if h > LAKE_Y - 0.3 then
						h = LAKE_Y - 0.3
					end
				else
					local slope = 0.3
					slope = lerp(slope, 0.11, st.beach)
					slope = lerp(slope, 0.95, st.rocky)
					slope = lerp(slope, 0.06, st.reeds)
					slope = lerp(slope, 0.14, st.mouth)
					local cap = LAKE_Y + 0.4 + slope * sd + 0.006 * sd * sd
					if h > cap then
						h = max(cap, S.chFloor[k]) -- never below a river / creek bank that holds water
					end
					if sd < 6 and h < LAKE_Y + 0.35 and WL[k] <= h then
						h = LAKE_Y + 0.35
					end
				end
				-- the island: a rocky mound rising out of the water
				local ix, iz = x - IC.X, z - IC.Z
				local ri = sqrt(ix * ix + iz * iz)
				if ri < 30 then
					local top = ISLAND.topY + 1.2 * N(49, x, z, 9)
					local q = ri / ISLAND.radius
					local hi = top - 7.6 * q * q - 1.2 * max(0, q - 1) * 6
					if h < hi then
						h = hi
					end
				end
				F[k] = h
				if sd < 6 then
					WL[k] = max(WL[k], LAKE_Y)
				end
			end
		end
		maybeYield()
	end
end

local function carveMarsh(S)
	local n = FN
	local F, WL, rMarsh = S.F, S.WL, S.rMarsh
	local reach = 40
	local i0 = max(0, floor((MARSH_P.minX - reach - G0) / 4))
	local i1 = min(n - 1, floor((MARSH_P.maxX + reach - G0) / 4))
	local j0 = max(0, floor((MARSH_P.minZ - reach - G0) / 4))
	local j1 = min(n - 1, floor((MARSH_P.maxZ + reach - G0) / 4))
	for j = j0, j1 do
		local z = G0 + 4 * j + 2
		for i = i0, i1 do
			local x = G0 + 4 * i + 2
			local k = j * n + i + 1
			local sd = rMarsh[k]
			if sd < reach and F[k] ~= EMPTY then
				local h = F[k]
				if sd < 0 then
					local hum = fbm(50, x, z, 22, 3)
					local pond = fbm(51, x, z, 70, 2)
					local g = MARSH_Y - 0.55 + 1.15 * hum
					if pond < -0.5 then
						g -= (min(1.6, -pond - 0.5)) * 1.6
					end
					if hum > 1.2 then
						g += (hum - 1.2) * 1.2 -- peat hummocks
					end
					h = max(lerp(h, g, sstep(0, 16, -sd)), S.chFloor[k]) -- the creek's last sills and banks stay
				else
					local cap = MARSH_Y + 0.5 + 0.2 * sd + 0.004 * sd * sd
					if h > cap then
						h = max(cap, S.chFloor[k]) -- the creek's step pools keep their banks and sills
					end
					if sd < 5 and h < MARSH_Y + 0.4 and WL[k] <= h then
						h = MARSH_Y + 0.4
					end
				end
				F[k] = h
				if sd < 1 then
					WL[k] = max(WL[k], MARSH_Y)
				end
			end
		end
		maybeYield()
	end
end

-- gentle easing toward a target height inside a footprint (never a plateau)
local function ease(S, cx: number, cz: number, radius: number, target: number?, strength: number, offset: number?)
	local n = FN
	local F = S.F
	local reach = radius * 1.6
	local i0, i1 = max(0, floor((cx - reach - G0) / 4)), min(n - 1, floor((cx + reach - G0) / 4))
	local j0, j1 = max(0, floor((cz - reach - G0) / 4)), min(n - 1, floor((cz + reach - G0) / 4))
	if not target then
		local sum, cnt = 0, 0
		for j = j0, j1 do
			for i = i0, i1 do
				local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
				if (x - cx) ^ 2 + (z - cz) ^ 2 < (radius * 0.6) ^ 2 then
					local h = F[j * n + i + 1]
					if h ~= EMPTY then
						sum += h
						cnt += 1
					end
				end
			end
		end
		target = (cnt > 0) and sum / cnt or nil
	end
	if not target then
		return nil
	end
	target += offset or 0
	for j = j0, j1 do
		for i = i0, i1 do
			local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
			local d = sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
			if d < reach then
				local k = j * n + i + 1
				if F[k] ~= EMPTY and S.WL[k] <= F[k] then
					local w = (1 - sstep(radius * 0.45, reach, d)) * strength
					F[k] += (target - F[k]) * w
				end
			end
		end
	end
	return target
end

local function shapeSpecials(S)
	local n = FN
	local F = S.F
	-- the plaza: exactly flat inside PlazaRadius, blended out to r = 86
	local R = Layout.PlazaRadius
	local i0, i1 = floor((CX - 90 - G0) / 4), floor((CX + 90 - G0) / 4)
	local j0, j1 = floor((CZ - 90 - G0) / 4), floor((CZ + 90 - G0) / 4)
	for j = j0, j1 do
		for i = i0, i1 do
			local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
			local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
			local k = j * n + i + 1
			if r <= R + 2 then
				F[k] = PLAZA_Y
			elseif r < 86 then
				F[k] = lerp(PLAZA_Y, F[k], sstep(R + 2, 86, r))
			end
		end
	end
	-- POIs: gentle easing of structure footprints
	S.poiTargets = {}
	for _, p in ipairs(Layout.POIs) do
		local kind = p.kind
		local strength = ({ Cabin = 0.9, Watchtower = 0.8, Campsite = 0.7, GiantTree = 0.45 })[kind]
		if strength then
			-- the target is always the local average (ArenaLayout.POIHeights are measured outputs, never inputs)
			S.poiTargets[p.name] = ease(S, p.position.X, p.position.Z, p.radius, nil, strength)
		end
	end
	-- crossing ends: both ends of the log and the footbridge eased toward a common height
	for _, name in ipairs({ "GorgeLog", "GorgeFootbridge" }) do
		local c = CROSS[name]
		if c then
			local half = c.span * 0.5 + 3
			local ax, az = c.position.X + c.direction.X * half, c.position.Z + c.direction.Z * half
			local bx, bz = c.position.X - c.direction.X * half, c.position.Z - c.direction.Z * half
			local function avg(px, pz)
				local s, cnt = 0, 0
				for dj = -1, 1 do
					for di = -1, 1 do
						local i = floor((px - G0) / 4) + di
						local j = floor((pz - G0) / 4) + dj
						s += F[j * n + i + 1]
						cnt += 1
					end
				end
				return s / cnt
			end
			local t = (avg(ax, az) + avg(bx, bz)) * 0.5
			ease(S, ax, az, 6, t, 0.85)
			ease(S, bx, bz, 6, t, 0.85)
			S.poiTargets[name] = t
			-- clear the deck corridor: no raised rim may stand above the deck between the two ends
			local cx, cz, dx, dz = c.position.X, c.position.Z, c.direction.X, c.direction.Z
			local reach = half + 6
			for j = floor((cz - reach - G0) / 4), floor((cz + reach - G0) / 4) do
				for i = floor((cx - reach - G0) / 4), floor((cx + reach - G0) / 4) do
					local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
					local along = (x - cx) * dx + (z - cz) * dz
					local lat = abs(-(x - cx) * dz + (z - cz) * dx)
					if abs(along) <= half and lat < 7 then
						local k = j * n + i + 1
						local cap = t - 0.4
						if F[k] > cap then
							F[k] = lerp(F[k], cap, 1 - sstep(3.5, 7, lat))
						end
					end
				end
			end
		end
	end
	-- cave aprons: a ramp in front of each mouth that meets the cave floor at the mouth (about 22 degrees), so the
	-- floor just inside the mouth is the published floor; it never cuts a creek bank (chFloor)
	for _, cave in ipairs(Layout.Caves) do
		local m, nx = cave.path[1], cave.path[2]
		local ox, oz = m.X - nx.X, m.Z - nx.Z
		local l = sqrt(ox * ox + oz * oz)
		ox, oz = ox / l, oz / l
		local hwm = cave.widths[1] * 0.5 + 2
		local reach = 14
		local span = reach + hwm + 4
		for j = floor((m.Z - span - G0) / 4), floor((m.Z + span - G0) / 4) do
			for i = floor((m.X - span - G0) / 4), floor((m.X + span - G0) / 4) do
				local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
				local dx, dz = x - m.X, z - m.Z
				local t = dx * ox + dz * oz -- distance out of the mouth
				local lat = abs(-dx * oz + dz * ox)
				if t >= 0 and t < reach and lat < hwm + 4 then
					local k = j * n + i + 1
					if F[k] ~= EMPTY and S.WL[k] <= F[k] then
						local target = cave.floorY - 0.4 * t
						local w = (1 - sstep(hwm, hwm + 4, lat)) * (1 - sstep(reach - 5, reach, t))
						F[k] = max(F[k] + (target - F[k]) * w, S.chFloor[k])
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- the mountain wall: one continuous cliff band all round, between the border (r 640) and the Boundary (r 712).
-- It is applied after erosion, so no gully or saddle can breach it. Its foot is a sheer `step` (18 studs) in the
-- heightfield, so every path across it - straight or slanting, on any grid - must climb at least that in one step:
-- a contender cannot walk it (MaxWalkableAngle 46), jump it (apex 3) or mantle it (Mantle needs a top with
-- normal.Y >= 0.7 within 7.8 studs). Above the step the face rises at ~75 degrees to `height`, then ~54 degrees,
-- with no ledges (the voxel stage gives wall cells no strata or overhang offsets).
--   foot(angle) = mountainEdge(angle) + offset + wobble * noise  (about r 651..699)
--   base(angle) = the highest ground within `apron` studs inside the foot (max-filtered over +-3 degrees)
--   ground >= base + step + min(height - step, t * face) + min(upperRise, max(0, t - (height - step) / face) * upper)
--   for t = r - foot >= 0; inside the foot (t < 0) the ground is untouched (always <= base)
----------------------------------------------------------------------------------------------------
TerrainGen.Wall = { offset = 2, wobble = 2.5, step = 18, height = 34, face = 3.8, upper = 1.4, upperRise = 30, apron = 60 }
local WALL_BUCKETS = 1440 -- 0.25 degree buckets

local function wallFoot(a: number): number
	local Wp = TerrainGen.Wall
	local ar = rad(a)
	return Layout.mountainEdge(a) + Wp.offset + Wp.wobble * N(57, sin(ar) * 680, -cos(ar) * 680, 90)
end
TerrainGen.wallFoot = wallFoot

local function shapeMountainWall(S)
	local n = FN
	local F = S.F
	local Wp = TerrainGen.Wall
	local NB = WALL_BUCKETS
	local footB = table.create(NB, 0)
	for b = 1, NB do
		footB[b] = wallFoot((b - 0.5) * 360 / NB)
	end
	local function footAt(a: number): number
		local fb = a * NB / 360 - 0.5
		local b0 = floor(fb)
		local t = fb - b0
		local f0, f1 = footB[(b0 % NB) + 1], footB[((b0 + 1) % NB) + 1]
		return f0 + (f1 - f0) * t
	end
	-- 1. the approach band: highest ground per bucket
	local hin = table.create(NB, -HUGE)
	local rMin, rMax = 580, 760
	local cells = {}
	for j = 0, n - 1 do
		local z = G0 + 4 * j + 2
		local dz = z - CZ
		if abs(dz) <= rMax then
			for i = 0, n - 1 do
				local x = G0 + 4 * i + 2
				local dx = x - CX
				local r2 = dx * dx + dz * dz
				if r2 >= rMin * rMin and r2 <= rMax * rMax then
					local k = j * n + i + 1
					if F[k] ~= EMPTY then
						local a = deg(atan2(dx, -dz)) % 360
						local t = sqrt(r2) - footAt(a)
						if t >= -Wp.apron and t <= 0 then
							local b = floor(a * NB / 360) % NB + 1
							if F[k] > hin[b] then
								hin[b] = F[k]
							end
						end
						if t > -2 and t <= 120 then
							table.insert(cells, { k, a, t })
						end
					end
				end
			end
		end
		maybeYield()
	end
	-- 2. max-filter over +-3 degrees (so the wall stands above every nearby approach), then a light blur
	local W3 = 12
	local hmax = table.create(NB, 0)
	for b = 1, NB do
		local m = -HUGE
		for o = -W3, W3 do
			local v = hin[((b - 1 + o) % NB) + 1]
			if v > m then
				m = v
			end
		end
		hmax[b] = (m == -HUGE) and 150 or m
	end
	local base = table.create(NB, 0)
	for b = 1, NB do
		local s = 0
		for o = -4, 4 do
			s += hmax[((b - 1 + o) % NB) + 1]
		end
		base[b] = max(hmax[b], s / 9) -- never below the max-filter
	end
	-- 3. raise the band
	local wall = table.create(n * n, false)
	local raised = 0
	local faceRun = (Wp.height - Wp.step) / Wp.face
	local faceEnd = faceRun + Wp.upperRise / Wp.upper + 2
	for _, c in ipairs(cells) do
		local k, a, t = c[1], c[2], c[3]
		local b0 = floor(a * NB / 360 - 0.5)
		-- the higher of the two nearest buckets: no dip between buckets
		local bh = max(base[(b0 % NB) + 1], base[((b0 + 1) % NB) + 1])
		if t >= 0 then
			local hmin = bh + Wp.step + min(Wp.height - Wp.step, t * Wp.face) + min(Wp.upperRise, max(0, t - faceRun) * Wp.upper)
			if F[k] < hmin then
				F[k] = hmin
				raised += 1
			end
		end
		if t <= faceEnd then
			wall[k] = true
		end
	end
	local lo, hi = HUGE, -HUGE
	for b = 1, NB do
		lo, hi = min(lo, base[b]), max(hi, base[b])
	end
	S.rWall = wall
	S.wallBase = base
	S.wallStats = string.format("wall: %d cells raised, base %.0f..%.0f", raised, lo, hi)
end

----------------------------------------------------------------------------------------------------
-- stage 4: water sealing and fields
----------------------------------------------------------------------------------------------------
local function sealWater(S)
	local n = FN
	local F, WL = S.F, S.WL
	local fixes = 0
	for _ = 1, 4 do
		local changed = 0
		for j = 1, n - 2 do
			for i = 1, n - 2 do
				local k = j * n + i + 1
				local w = WL[k]
				if w > F[k] + 0.05 and not S.sheet[k] then
					for _, kk in ipairs({ k - 1, k + 1, k - n, k + n }) do
						local hn = F[kk]
						if hn ~= EMPTY then
							local wet = WL[kk] > hn + 0.05
							if not wet and hn < w - 0.1 and not S.sheet[kk] then
								-- a dry neighbour below the water: raise it into a bank
								F[kk] = w + 0.35
								changed += 1
							end
						end
					end
				end
			end
		end
		fixes += changed
		maybeYield()
		if changed == 0 then
			break
		end
	end
	S.sealFixes = fixes
end

-- chamfer distance transform: seeds (distance 0) where seed[k] is true; result in studs
local function distanceTransform(seed, cap: number)
	local n = FN
	local D = table.create(n * n, cap)
	for k = 1, n * n do
		if seed[k] then
			D[k] = 0
		end
	end
	local a, b = 4, 5.657
	for j = 1, n - 1 do
		for i = 1, n - 2 do
			local k = j * n + i + 1
			local d = D[k]
			local v = D[k - 1] + a
			if v < d then
				d = v
			end
			v = D[k - n] + a
			if v < d then
				d = v
			end
			v = D[k - n - 1] + b
			if v < d then
				d = v
			end
			v = D[k - n + 1] + b
			if v < d then
				d = v
			end
			D[k] = d
		end
	end
	for j = n - 2, 0, -1 do
		for i = n - 2, 1, -1 do
			local k = j * n + i + 1
			local d = D[k]
			local v = D[k + 1] + a
			if v < d then
				d = v
			end
			v = D[k + n] + a
			if v < d then
				d = v
			end
			v = D[k + n + 1] + b
			if v < d then
				d = v
			end
			v = D[k + n - 1] + b
			if v < d then
				d = v
			end
			D[k] = d
		end
	end
	return D
end

local function computeFields(S)
	local n = FN
	local F, WL = S.F, S.WL
	local slope = table.create(n * n, 0)
	local curv = table.create(n * n, 0)
	local wet = table.create(n * n, false)
	local steep = table.create(n * n, false)
	for j = 1, n - 2 do
		for i = 1, n - 2 do
			local k = j * n + i + 1
			local h = F[k]
			if h ~= EMPTY then
				local hl, hr, hd, hu = F[k - 1], F[k + 1], F[k - n], F[k + n]
				if hl == EMPTY then
					hl = h
				end
				if hr == EMPTY then
					hr = h
				end
				if hd == EMPTY then
					hd = h
				end
				if hu == EMPTY then
					hu = h
				end
				local gx, gz = (hr - hl) / 8, (hu - hd) / 8
				local edge = max(abs(hr - h), abs(hl - h), abs(hu - h), abs(hd - h)) / 4
				local g = max(sqrt(gx * gx + gz * gz), edge * 0.85)
				local sdeg = deg(math.atan(g))
				slope[k] = sdeg
				curv[k] = (hl + hr + hd + hu - 4 * h) / 16
				wet[k] = WL[k] > h + 0.05
				steep[k] = sdeg > 50
			end
		end
		maybeYield()
	end
	S.slope, S.curv, S.wet = slope, curv, wet
	S.dWater = distanceTransform(wet, 400)
	maybeYield()
	-- nearW: the highest water level within 3 cells (12 studs). Below it (+ a margin) the voxel stage keeps every
	-- column true to the sealed heightfield: no strata offsets, no overhangs, vertical occupancy.
	local nearW = table.create(n * n, EMPTY)
	local band = {}
	for k = 1, n * n do
		if wet[k] then
			nearW[k] = WL[k]
		end
		if S.dWater[k] <= 14 then
			table.insert(band, k)
		end
	end
	for _ = 1, 3 do
		local nxt = table.clone(nearW)
		for _, k in ipairs(band) do
			local j = (k - 1) // n
			local i = (k - 1) - j * n
			if i >= 1 and j >= 1 and i <= n - 2 and j <= n - 2 then
				local v = nearW[k]
				for _, kk in ipairs({ k - 1, k + 1, k - n, k + n, k - n - 1, k - n + 1, k + n - 1, k + n + 1 }) do
					if nearW[kk] > v then
						v = nearW[kk]
					end
				end
				nxt[k] = v
			end
		end
		nearW = nxt
		maybeYield()
	end
	S.nearW = nearW
	S.dCliff = distanceTransform(steep, 255)
	maybeYield()
	-- trails: distance to the nearest centreline within 5 studs
	local trailD = table.create(n * n, 99)
	for _, trail in ipairs(Layout.Trails) do
		for ti = 1, #trail - 1 do
			local a = { x = trail[ti].X, z = trail[ti].Z }
			local b = { x = trail[ti + 1].X, z = trail[ti + 1].Z }
			stampSegment(n, 4, a, b, 5, function(k, x, z, d)
				if d < trailD[k] then
					trailD[k] = d
				end
			end)
		end
	end
	S.trailD = trailD
	-- moisture
	local moist = table.create(n * n, 0)
	for j = 0, n - 1 do
		local z = G0 + 4 * j + 2
		for i = 0, n - 1 do
			local x = G0 + 4 * i + 2
			local k = j * n + i + 1
			if F[k] ~= EMPTY then
				local m = 0.95 * exp(-S.dWater[k] / 30) + 0.45 * S.flow[k] + 0.12 * N(52, x, z, 60) + 0.2 * clamp01(curv[k] * 2)
				if S.rMarsh[k] < 10 then
					m += 0.4
				end
				moist[k] = clamp01(m)
			end
		end
		maybeYield()
	end
	S.moist = moist
end

----------------------------------------------------------------------------------------------------
-- stage 5: materials
----------------------------------------------------------------------------------------------------
-- strata bands for steep faces: style 1 = gorge (shale-rich), 2 = escarpment, 3 = mountains / knobs
local function bandHash(band: number): number
	local v = (band * 73856093) % 1000003
	return (v % 1000) / 1000
end

local function strataMat(yc: number, wob: number, layerH: number, style: number)
	local band = floor((yc + wob) / layerH)
	local hsh = bandHash(band)
	if style == 1 then
		if hsh < 0.5 then
			return LIME
		elseif hsh < 0.88 then
			return ROCK
		end
		return BASALT
	elseif style == 2 then
		if hsh < 0.3 then
			return LIME
		elseif hsh < 0.9 then
			return ROCK
		end
		return BASALT
	end
	if hsh < 0.12 then
		return LIME
	elseif hsh < 0.9 then
		return ROCK
	end
	return BASALT
end

-- top / sub material per column and the strata style for its rock
local function chooseColumn(S, k: number, x: number, z: number)
	local h = S.F[k]
	local sl = S.slope[k]
	local wl = S.WL[k]
	local depth = wl - h
	local n1 = N(31, x, z, 26)
	local n2 = N(32, x, z, 9.5)
	local n3 = N(33, x, z, 70)
	local n4 = N(34, x, z, 160)
	local esc, mtn, lake, marsh, field = S.rEsc[k], S.rMtn[k], S.rLake[k], S.rMarsh[k], S.rField[k]
	local meadow = S.rMeadow[k]
	local chd, chid = S.chD[k], S.chId[k]
	local style = 3
	if chid == 1 and S.chW[k] ~= EMPTY and S.gorgeCell[k] then
		style = 1
	elseif esc < 200 then
		style = 2
	end
	-- under water
	if depth > 0.15 then
		if lake < 6 then
			local phi = deg(atan2(x - LAKE_C.X, -(z - LAKE_C.Z))) % 360
			local st = Layout.Lake.shoreStyle(phi)
			if depth < 1.8 then
				if st.reeds > 0.5 then
					return MUD, MUD, style
				elseif st.rocky > 0.5 then
					return (n2 > 0.2) and ROCK or SALT, SALT, style
				elseif st.mouth > 0.5 then
					return (n2 > -0.3) and SALT or SAND, SAND, style
				end
				return (n2 > 1.1) and SALT or SAND, SAND, style
			end
			if st.rocky > 0.6 and depth < 5 then
				return (n2 > -0.2) and ROCK or SALT, ROCK, style
			end
			return (n2 > 1.2) and SALT or MUD, MUD, style
		elseif marsh < 2 then
			return MUD, MUD, style
		elseif chid == 3 then
			return MUD, MUD, style
		end
		-- river / creek / pool beds
		if n2 > 1.0 then
			return ROCK, ROCK, style
		end
		if chid == 1 and not S.gorgeCell[k] and depth > 2.4 and n1 > 0.4 then
			return SAND, SAND, style
		end
		if S.gorgeCell[k] or n1 < -0.2 then
			return BASALT, BASALT, style -- grey angular gravel (gorge beds, riffles)
		end
		return SALT, SALT, style
	end
	-- mountains and snow
	local snowLine = Layout.SnowLine + 22 * n3
	if h > snowLine and sl < 48 then
		return SNOW, SNOW, style
	end
	if h > snowLine - 18 and sl < 26 and n2 > 0.4 then
		return SNOW, SNOW, style
	end
	-- cliffs and steep ground
	if sl > 50 then
		return ROCK, ROCK, style
	end
	if sl > 40 then
		if mtn > -20 or esc < 30 or S.gorgeCell[k] or S.rRock[k] > 0.2 then
			return (n2 > -0.3) and BASALT or ROCK, ROCK, style
		end
		if n1 > 0.6 then
			return ROCK, ROCK, style
		end
		-- steep forest banks: needles still cling up to ~45 degrees, bare soil beyond and in patches
		if n1 > -0.2 or sl > 46 then
			return GROUND, GROUND, style
		end
		return LEAFY, GROUND, style
	end
	-- scree aprons in front of the escarpment
	if esc < 0 and esc > -40 then
		local _, H, scree = ESC.at(deg(atan2(x - CX, -(z - CZ))) % 360)
		if H and scree and scree > 1 and -esc < 9 + scree then
			if n2 > 1.1 then
				return ROCK, BASALT, style
			end
			if -esc > 6 + scree and n1 > 0 then
				return LEAFY, GROUND, style
			end
			return BASALT, BASALT, style
		end
	end
	-- rock knobs / outcrops
	if S.rRock[k] > 0.35 and sl > 22 then
		return ROCK, ROCK, style
	end
	-- lake shore band
	if lake < 9 and h < LAKE_Y + 1.9 + 0.6 * n1 then
		local phi = deg(atan2(x - LAKE_C.X, -(z - LAKE_C.Z))) % 360
		local st = Layout.Lake.shoreStyle(phi)
		if st.reeds > 0.5 then
			return (n2 > 0.6) and LEAFY or MUD, MUD, style
		elseif st.rocky > 0.5 then
			return (n2 > -0.4) and ROCK or SALT, ROCK, style
		elseif st.mouth > 0.4 then
			return (n2 > 0.3) and SALT or SAND, SAND, style
		elseif st.beach > 0.3 then
			return (n2 > 1.3) and SALT or SAND, SAND, style
		end
		return (n2 > 0.4) and GROUND or MUD, GROUND, style
	end
	-- channel banks: point bars, cut banks, gorge margins
	if chid > 0 then
		local W = S.chW[k]
		if W ~= EMPTY and h < W + 1.6 then
			if S.gorgeCell[k] then
				return (n2 > 0.3) and ROCK or BASALT, ROCK, style
			end
			if chid == 3 then
				return MUD, MUD, style
			end
			if sl < 14 then
				return (n2 > 0.9) and SAND or SALT, SALT, style
			end
			return (n1 > 0) and MUD or GROUND, GROUND, style
		end
	end
	-- the marsh
	if marsh < 3 then
		if h < MARSH_Y + 0.35 then
			return MUD, MUD, style
		end
		if n1 > 0.35 then
			return GRASS, MUD, style
		end
		if n2 > 0.9 then
			return MUD, MUD, style
		end
		return LEAFY, MUD, style
	end
	-- trails and trampled ground
	local td = S.trailD[k]
	if td < 1.5 + 0.7 * n2 or (td < 2.6 and n2 > 0.6) then
		return GROUND, GROUND, style
	end
	if S.poiCore[k] and n2 > -0.4 then
		return GROUND, GROUND, style
	end
	-- the plaza (under the SpirePlatform) and the meadow
	local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	if r < Layout.PlazaRadius + 1 then
		return GROUND, GROUND, style -- bare packed earth under the SpirePlatform (no grass blades through the mesh)
	end
	if meadow > 0.55 then
		if r < 74 and n2 > 0.7 then
			return GROUND, GROUND, style
		end
		if n2 > 1.9 then
			return GROUND, GROUND, style
		end
		return GRASS, GROUND, style
	end
	-- the field: grass with dry earthy spots on convex ground
	if field < 0 then
		if S.curv[k] < -0.15 and n1 > 1.5 and n2 > 0.3 then
			return GROUND, GROUND, style -- a few bare, sun-baked spots on the knolls
		end
		return GRASS, GROUND, style
	end
	-- mountains (below the snow): forest floor low down; rock, scree and thin dark turf higher up (no bright meadow
	-- grass: on the benches between crags it read as contour stripes from the arena)
	if mtn > -10 then
		if S.rWall[k] then
			return (n2 > 0.9) and BASALT or ROCK, ROCK, style -- the cliff band
		end
		if h > 210 then
			if n1 > 0.4 or sl > 32 + 6 * n2 then
				return (n2 > 0) and ROCK or BASALT, ROCK, style
			end
			return (n2 > 0.5) and GROUND or LEAFY, GROUND, style
		end
		if sl > 30 and n1 > 0.2 then
			return ROCK, ROCK, style
		end
		return (n2 > 1.0) and GROUND or LEAFY, GROUND, style
	end
	-- forest floor, with grass toward open edges and glades, soil on steeper ground and drainage lines
	local open = max(meadow * 1.6, 1 - sstep(0, 26 + 10 * n1, field), 1 - sstep(0, 22 + 8 * n1, lake), 1 - sstep(0, 18, marsh))
	if S.clearCell[k] then
		open = max(open, 0.8)
	end
	if open + 0.25 * n1 > 0.62 then
		return GRASS, GROUND, style
	end
	if n4 > 1.2 and sl < 24 + 10 * n2 then
		return GRASS, GROUND, style -- sunny glades (a noisy slope limit: no bands along the contours)
	end
	local fl = S.flow[k]
	local cv = S.curv[k]
	-- dry gully beds: only the strongest drainage lines in concave ground, earth with a few washed pebbles
	if fl > 0.93 and cv > 0.03 and sl < 30 then
		return (n2 > 1.0) and SALT or GROUND, GROUND, style
	end
	if fl > 0.88 and cv > 0.05 and n2 > 0.4 then
		return GROUND, GROUND, style
	end
	-- steeper banks: bare soil in patches, a little rock
	if sl > 34 and n1 > 0.45 then
		return GROUND, GROUND, style
	end
	if sl > 30 and n2 > 1.5 then
		return ROCK, GROUND, style
	end
	if esc > 0 and esc < 12 and n2 > 0.2 then
		return ROCK, ROCK, style -- rock lip along the escarpment top
	end
	if n2 > 2.1 then
		return GROUND, GROUND, style
	end
	return LEAFY, GROUND, style
end

local function computeMaterials(S)
	local n = FN
	local top = table.create(n * n, AIR)
	local sub = table.create(n * n, AIR)
	local sty = table.create(n * n, 3)
	-- helper masks: gorge cells, POI cores, clearings
	local gorgeCell = table.create(n * n, false)
	for k = 1, n * n do
		local id = S.chId[k]
		if id == 1 then
			local smp = RIVER_SAMPLES[S.chSeg[k]]
			if smp and (smp.gorge == 1 or smp.fall) and S.chD[k] < 40 then
				gorgeCell[k] = true
			end
		end
	end
	S.gorgeCell = gorgeCell
	local poiCore = table.create(n * n, false)
	for _, p in ipairs(Layout.POIs) do
		if p.kind == "Campsite" or p.kind == "Cabin" or p.kind == "Watchtower" then
			local R = p.radius * 0.55
			local i0, i1 = floor((p.position.X - R - G0) / 4), floor((p.position.X + R - G0) / 4)
			local j0, j1 = floor((p.position.Z - R - G0) / 4), floor((p.position.Z + R - G0) / 4)
			for j = j0, j1 do
				for i = i0, i1 do
					local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
					if (x - p.position.X) ^ 2 + (z - p.position.Z) ^ 2 < R * R then
						poiCore[j * n + i + 1] = true
					end
				end
			end
		end
	end
	S.poiCore = poiCore
	local clearCell = table.create(n * n, false)
	for _, c in ipairs(Layout.Clearings) do
		local R = c.radius
		local i0, i1 = floor((c.center.X - R - G0) / 4), floor((c.center.X + R - G0) / 4)
		local j0, j1 = floor((c.center.Z - R - G0) / 4), floor((c.center.Z + R - G0) / 4)
		for j = j0, j1 do
			for i = i0, i1 do
				local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
				local d = sqrt((x - c.center.X) ^ 2 + (z - c.center.Z) ^ 2)
				if d < R * (0.8 + 0.25 * N(53, x, z, 12)) then
					clearCell[j * n + i + 1] = true
				end
			end
		end
	end
	S.clearCell = clearCell
	for j = 0, n - 1 do
		local z = G0 + 4 * j + 2
		for i = 0, n - 1 do
			local x = G0 + 4 * i + 2
			local k = j * n + i + 1
			if S.F[k] ~= EMPTY then
				top[k], sub[k], sty[k] = chooseColumn(S, k, x, z)
			end
		end
		maybeYield()
	end
	S.top, S.sub, S.sty = top, sub, sty
end

----------------------------------------------------------------------------------------------------
-- stage 6: voxels
----------------------------------------------------------------------------------------------------
local CAVES = {}
for ci, cave in ipairs(Layout.Caves) do
	local pts = {}
	local m, nx = cave.path[1], cave.path[2]
	local ox, oz = m.X - nx.X, m.Z - nx.Z
	local l = sqrt(ox * ox + oz * oz)
	-- extend the tunnel 5 studs out of the mouth so it always opens through the face
	table.insert(pts, { x = m.X + ox / l * 5, z = m.Z + oz / l * 5, y = cave.floorY, hw = cave.widths[1] / 2, H = cave.heights[1] })
	for i, p in ipairs(cave.path) do
		table.insert(pts, { x = p.X, z = p.Z, y = p.Y, hw = cave.widths[i] / 2, H = cave.heights[i] })
	end
	local box = { minX = HUGE, maxX = -HUGE, minZ = HUGE, maxZ = -HUGE, minY = HUGE, maxY = -HUGE }
	for _, p in ipairs(pts) do
		local reach = p.hw + 6
		box.minX, box.maxX = min(box.minX, p.x - reach), max(box.maxX, p.x + reach)
		box.minZ, box.maxZ = min(box.minZ, p.z - reach), max(box.maxZ, p.z + reach)
		box.minY, box.maxY = min(box.minY, p.y - 6), max(box.maxY, p.y + p.H + 6)
	end
	CAVES[ci] = { pts = pts, box = box, seed = 54 + ci }
end

-- air-ness of a point inside the caves (> 0 = inside a cave)
local function caveAir(cave, x: number, y: number, z: number): number
	local pts = cave.pts
	local best, bu, bi = HUGE, 0, 1
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local l2 = dx * dx + dz * dz
		local u = 0
		if l2 > 1e-9 then
			u = clamp01(((x - a.x) * dx + (z - a.z) * dz) / l2)
		end
		local qx, qz = x - (a.x + dx * u), z - (a.z + dz * u)
		local d2 = qx * qx + qz * qz
		if d2 < best then
			best, bu, bi = d2, u, i
		end
	end
	local a, b = pts[bi], pts[bi + 1]
	local floorY = a.y + (b.y - a.y) * bu
	local hw = a.hw + (b.hw - a.hw) * bu
	local H = a.H + (b.H - a.H) * bu
	local lat = sqrt(best)
	local v = y - floorY
	local q = sqrt((lat / hw) ^ 2 + ((v - 0.3 * H) / (0.72 * H)) ^ 2) + 0.1 * N3(cave.seed, x, y, z, 6)
	local inside = (1 - q) * min(hw, 0.72 * H)
	return min(inside, v)
end

local PLATES = {}
for i, cf in ipairs(Layout.Plates) do
	PLATES[i] = cf.Position
end
local TUBE_R = Layout.PlateTube.radius -- guaranteed clear radius of each shaft
local TUBE_FLOOR = Layout.PlateTube.floorY
-- The launch-tube trench. Terrain voxels are 4 studs, and a full voxel's surface reaches ~1.8 studs into an empty
-- neighbour (any partial occupancy pushes it to ~3.5: measured), so v2.0's ring of partially filled voxels
-- rendered as bulges into each shaft (walls 1.5-2 studs from the axis), and clean per-plate shafts would need
-- empty cells out to TUBE_R + 1.8 = 5.4 studs from each axis: with the plates only 13.6 studs apart, neighbouring
-- shafts cannot keep a full voxel between them. So the terrain is opened as ONE clean annular trench under the
-- plate band: every cell whose 4x4 square meets the ring r = PlinthRingRadius +- (TUBE_R + Tube.intrude) is empty
-- from the tube floor up; every other cell is exactly the heightfield (no funnel, no rock collar). The realistic
-- SpirePlatform (pivot (0, PlazaY, 0)) covers the whole ring with its deck colliders and lines the 24 openings
-- (r 3.4) with granite, so from above each plate sits in its own tube; it must be in place whenever the trench
-- is (TerrainGen.placeSpirePlatform). Measured: a 4.8 x 4.8 block and a r 2.8 sphere drop to the floor at every
-- plate, terrain at least 3.6 studs from every axis.
TerrainGen.Tube = { intrude = 1.8 }
local BORE = {}
local function computeBores()
	table.clear(BORE)
	local half = TUBE_R + TerrainGen.Tube.intrude
	local rc = Layout.PlinthRingRadius or 52
	local rIn, rOut = rc - half, rc + half
	local reach = rOut + 4
	for j = floor((CZ - reach - G0) / 4), floor((CZ + reach - G0) / 4) do
		for i = floor((CX - reach - G0) / 4), floor((CX + reach - G0) / 4) do
			local x, z = G0 + 4 * i + 2, G0 + 4 * j + 2
			-- nearest and farthest distance from the centre to the cell's square
			local nx = max(abs(x - CX) - 2, 0)
			local nz = max(abs(z - CZ) - 2, 0)
			local near = sqrt(nx * nx + nz * nz)
			local fx, fz = abs(x - CX) + 2, abs(z - CZ) + 2
			local far = sqrt(fx * fx + fz * fz)
			if far > rIn and near < rOut then
				BORE[j * FN + i + 1] = true
			end
		end
	end
end

local function newVoxelArrays(ny: number)
	local mats, occs, liqs = table.create(16), table.create(16), table.create(16)
	for ix = 1, 16 do
		local mx, ox, lx = table.create(ny), table.create(ny), table.create(ny)
		for iy = 1, ny do
			mx[iy] = table.create(16, AIR)
			ox[iy] = table.create(16, 0)
			lx[iy] = table.create(16, 0)
		end
		mats[ix], occs[ix], liqs[ix] = mx, ox, lx
	end
	return mats, occs, liqs
end

-- strata: smooth periodic ledges (two harmonics) with a resistance that varies smoothly from band to band, so
-- neighbouring voxels never jump (v2.0's per-band sawtooth read as crumpled paper at 4-stud voxels)
local TAU = 2 * math.pi
local function strataProfile(t: number): number
	local band = floor(t)
	local f = t - band
	local r0, r1 = bandHash(band + 17) - 0.5, bandHash(band + 18) - 0.5
	local resist = r0 + (r1 - r0) * (f * f * (3 - 2 * f))
	return 0.42 * sin(TAU * t) + 0.16 * sin(2 * TAU * t + 1.3) + 0.35 * resist
end

-- one voxel column (fine cell k, centre x, z) into m, o, l (materials, solid and liquid occupancy; ny layers
-- from minY). Depends only on the column and the global state, so a column is identical in every chunk that
-- computes it (the water containment below relies on that).
local function columnVoxels(S, k: number, x: number, z: number, minY: number, ny: number, caves, m, o, l)
	local n = FN
	local F, WL = S.F, S.WL
	local h = F[k]
	local w = WL[k]
	local sl = S.slope[k]
	local tMat, sMat, style = S.top[k], S.sub[k], S.sty[k]
	local wob = 3.5 * N(51, x, z, 120) + 0.012 * (x * 0.6 + z * 0.8)
	local layerH = 9 + 2.2 * N(50, x, z, 140)
	-- a Sobel gradient: smoother than central differences on rough faces
	local function hAt(kk: number): number
		local v = F[kk]
		return (v == EMPTY) and h or v
	end
	local hl, hr, hd, hu = hAt(k - 1), hAt(k + 1), hAt(k - n), hAt(k + n)
	local hdl, hdr, hul, hur = hAt(k - n - 1), hAt(k - n + 1), hAt(k + n - 1), hAt(k + n + 1)
	local gx = ((hr - hl) * 2 + (hur - hul) + (hdr - hdl)) / 32
	local gz = ((hu - hd) * 2 + (hur - hdr) + (hul - hdl)) / 32
	local G = sqrt(gx * gx + gz * gz)
	local nY = 1 / sqrt(1 + G * G)
	local hmax = max(h, hl, hr, hd, hu, hdl, hdr, hul, hur)
	local steep = sl > 42
	-- strata ledges and overhangs only on real cliffs (escarpment, gorge walls, falls amphitheatre, the high
	-- mountains); never on the mountain wall band (no ledges to mantle), on forest knobs, or below nearby water
	local strata = steep and not S.rWall[k] and (style ~= 3 or S.rMtn[k] > 40)
	local nw = S.nearW[k]
	local A = 0
	local gxn, gzn = 0, 0
	if strata and G > 1e-6 then
		gxn, gzn = gx / G, gz / G
		A = 2.0 * ((style == 3) and 0.8 or 1.0) * sstep(42, 60, sl)
	end
	local steepScale = lerp(1, nY, sstep(45, 70, sl))
	local bore = BORE[k]
	local boreWall = not bore
		and (BORE[k - 1] or BORE[k + 1] or BORE[k - n] or BORE[k + n] or BORE[k - n - 1] or BORE[k - n + 1] or BORE[k + n - 1] or BORE[k + n + 1])
	local colCaves = nil
	for _, cave in ipairs(caves) do
		local b = cave.box
		if x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ then
			colCaves = colCaves or {}
			table.insert(colCaves, cave)
		end
	end
	-- Roblox neither renders nor raycasts a water surface whose voxel also holds solid (measured: a level 3.5 studs
	-- into a voxel needs 1.6 of depth, one on a voxel boundary 2.0). So in a wet column the voxel holding the
	-- surface gets no solid: a bed inside it drops to that voxel's centre (shallow water is at most 2 studs deeper).
	local surfaceY0 = (w > h + 0.05) and (ceil(w / VOX) * VOX - VOX) or nil
	for iy = 1, ny do
		local y0 = minY + (iy - 1) * VOX
		local yc = y0 + 2
		local D
		-- up to 3 studs above the nearby water every column stays true to the sealed heightfield
		local low = nw ~= EMPTY and yc < nw + 3
		if A > 0 and not low and yc > h - 30 and yc < hmax + 4 then
			local amp = A
			if nw ~= EMPTY then
				amp *= sstep(nw + 3, nw + 7, yc)
			end
			local s = amp * strataProfile((yc + wob) / layerH)
			-- shifted heightfield sample (uphill = into the rock)
			local sx, sz = x + gxn * s, z + gzn * s
			local fx = (sx - G0) / 4 - 0.5
			local fz = (sz - G0) / 4 - 0.5
			local bi, bj = floor(fx), floor(fz)
			local tx, tz = fx - bi, fz - bj
			local kk = bj * n + bi + 1
			local a1, a2, a3, a4 = F[kk], F[kk + 1], F[kk + n], F[kk + n + 1]
			if a1 == EMPTY or a2 == EMPTY or a3 == EMPTY or a4 == EMPTY then
				D = h - yc
			else
				D = ((a1 * (1 - tx) + a2 * tx) * (1 - tz) + (a3 * (1 - tx) + a4 * tx) * tz) - yc
			end
			-- steep faces render true to shape with normal distance, gentle ones with vertical distance
			D *= steepScale
		elseif steep and not low then
			D = (h - yc) * steepScale
		else
			D = h - yc
		end
		if colCaves and D > -4 then
			for _, cave in ipairs(colCaves) do
				local b = cave.box
				if yc >= b.minY and yc <= b.maxY then
					local air = caveAir(cave, x, yc, z)
					if -air < D then
						D = -air
					end
				end
			end
		end
		if bore and yc > TUBE_FLOOR - 4 then
			local fd = TUBE_FLOOR - yc
			if fd < D then
				D = fd
			end
		end
		local occ = D * 0.25
		if occ > 1 then
			occ = 1
		elseif occ < 0 then
			occ = 0
		end
		if y0 == surfaceY0 then
			occ = 0
		end
		local mat = AIR
		if occ > 0 then
			local below = h - yc
			if steep and not low then
				if below < 4.5 and sl <= 46 then
					mat = tMat
				else
					mat = strataMat(yc, wob, layerH, style)
				end
			elseif below < 4.5 and not bore then
				mat = tMat
			elseif bore or boreWall then
				mat = ROCK -- the shafts are lined with rock
			elseif below < 10 then
				mat = sMat
			else
				mat = strataMat(yc, wob, layerH, style)
			end
		end
		local liquid = 0
		if occ < 1 and w > y0 then
			liquid = (w - y0) * 0.25
			if liquid > 1 then
				liquid = 1
			end
		end
		m[iy], o[iy], l[iy] = mat, occ, liquid
	end
end

local NB4 = { -1, 1, -18, 18 }

local function writeArenaChunk(S, cx0: number, cz0: number): boolean
	local n = FN
	local F, WL = S.F, S.WL
	local i0 = (cx0 - G0) // 4
	local j0 = (cz0 - G0) // 4
	-- vertical range over the chunk, its one-column border (computed too, for the water containment; only the inner
	-- 16 x 16 are written) and one more ring (the 3D sampling reads it)
	local minH, maxTop = HUGE, -HUGE
	local hasBore = false
	for jj = max(0, j0 - 2), min(n - 1, j0 + 17) do
		for ii = max(0, i0 - 2), min(n - 1, i0 + 17) do
			local k = jj * n + ii + 1
			local h = F[k]
			if h ~= EMPTY then
				if h < minH then
					minH = h
				end
				if h > maxTop then
					maxTop = h
				end
				if WL[k] > maxTop then
					maxTop = WL[k]
				end
				if BORE[k] then
					hasBore = true
				end
			end
		end
	end
	if maxTop == -HUGE then
		return false
	end
	local caves = {}
	for _, cave in ipairs(CAVES) do
		local b = cave.box
		if b.maxX >= cx0 - 4 and b.minX <= cx0 + CHUNK + 4 and b.maxZ >= cz0 - 4 and b.minZ <= cz0 + CHUNK + 4 then
			table.insert(caves, cave)
			minH = min(minH, b.minY)
		end
	end
	if hasBore then
		minH = min(minH, TUBE_FLOOR - 6)
	end
	local minY = floor((minH - SHELL) / VOX) * VOX
	local maxY = ceil((maxTop + 6) / VOX) * VOX + VOX
	local ny = (maxY - minY) // VOX
	-- 18 x 18 columns: c = iz * 18 + ix + 1 (ix, iz = 0..17; 0 and 17 are the border)
	local cm, co, cl, ctop = {}, {}, {}, {}
	for iz = 0, 17 do
		local j = j0 + iz - 1
		local z = cz0 + (iz - 1) * VOX + 2
		for ix = 0, 17 do
			local i = i0 + ix - 1
			local x = cx0 + (ix - 1) * VOX + 2
			if i >= 1 and i <= n - 2 and j >= 1 and j <= n - 2 then
				local k = j * n + i + 1
				if F[k] ~= EMPTY then
					local c = iz * 18 + ix + 1
					local m, o, l = table.create(ny, AIR), table.create(ny, 0), table.create(ny, 0)
					columnVoxels(S, k, x, z, minY, ny, caves, m, o, l)
					cm[c], co[c], cl[c], ctop[c] = m, o, l, S.top[k]
				end
			end
		end
	end
	-- Water containment: a dry voxel beside a water voxel gets at least that much solid (bank material), so no water
	-- face is ever left standing against air. Each column decides from its own and its neighbours' (unmodified)
	-- values, so two chunks always agree at their seam.
	local filled = 0
	for iz = 1, 16 do
		for ix = 1, 16 do
			local c = iz * 18 + ix + 1
			local o, l, m = co[c], cl[c], cm[c]
			if o then
				for _, d in ipairs(NB4) do
					local ln = cl[c + d]
					if ln then
						for iy = 1, ny do
							local lw = ln[iy]
							if lw > 0.02 and l[iy] <= 0.001 then
								local need = lw + 0.1
								if need > 1 then
									need = 1
								end
								if o[iy] < need then
									o[iy] = need
									if m[iy] == AIR then
										m[iy] = ctop[c]
									end
									filled += 1
								end
							end
						end
					end
				end
			end
		end
	end
	local mats, occs, liqs = newVoxelArrays(ny)
	for iz = 1, 16 do
		for ix = 1, 16 do
			local c = iz * 18 + ix + 1
			local m, o, l = cm[c], co[c], cl[c]
			if m then
				local mx, ox, lx = mats[ix], occs[ix], liqs[ix]
				for iy = 1, ny do
					mx[iy][iz] = m[iy]
					ox[iy][iz] = o[iy]
					lx[iy][iz] = l[iy]
				end
			end
		end
	end
	local region = Region3.new(Vector3.new(cx0, minY, cz0), Vector3.new(cx0 + CHUNK, maxY, cz0 + CHUNK))
	workspace.Terrain:WriteVoxelChannels(region, VOX, {
		SolidMaterial = mats,
		SolidOccupancy = occs,
		LiquidOccupancy = liqs,
	})
	S.containFills = (S.containFills or 0) + filled
	return true
end

local function arenaChunkOrigins()
	local list = {}
	local lo = -math.ceil(OUTER / CHUNK) * CHUNK
	local hi = -lo
	for cx = CX + lo, CX + hi - CHUNK, CHUNK do
		for cz = CZ + lo, CZ + hi - CHUNK, CHUNK do
			local nx = math.clamp(CX, cx, cx + CHUNK) - CX
			local nz = math.clamp(CZ, cz, cz + CHUNK) - CZ
			if nx * nx + nz * nz <= OUTER * OUTER then
				local mx, mz = cx + CHUNK / 2 - CX, cz + CHUNK / 2 - CZ
				table.insert(list, { cx, cz, mx * mx + mz * mz })
			end
		end
	end
	table.sort(list, function(a, b)
		return a[3] < b[3]
	end)
	return list
end

----------------------------------------------------------------------------------------------------
-- the lobby island: identical to v1 (same seed, noise and shape)
----------------------------------------------------------------------------------------------------
local V1 = {}
do
	local rng = Random.new(Layout.Seed)
	V1.OX, V1.OZ, V1.OY = {}, {}, {}
	for i = 1, 48 do
		V1.OX[i] = rng:NextNumber(-400, 400) + 0.318
		V1.OZ[i] = rng:NextNumber(-400, 400) + 0.627
		V1.OY[i] = rng:NextNumber(-50, 50) + 0.141
	end
end
local function v1N(i, x, z, s)
	return noise(x / s + V1.OX[i], z / s + V1.OZ[i], V1.OY[i])
end
local function v1smooth(x)
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	return x * x * (3 - 2 * x)
end
local function v1stratum(yc, wob)
	local band = floor((yc + wob) / 5) % 3
	return (band == 0) and SLATE or ROCK
end
local LOBBY = Layout.LobbyPosition
local LOBBY_R = Layout.LobbyRadius

local function islandColumn(x, z)
	local dx, dz = x - LOBBY.X, z - LOBBY.Z
	local rr = sqrt(dx * dx + dz * dz)
	if rr > LOBBY_R + 24 then
		return nil
	end
	local ang = atan2(dz, dx)
	local edge = LOBBY_R + 9 + 10 * noise(cos(ang) * 1.6 + V1.OX[40], sin(ang) * 1.6 + V1.OZ[40], V1.OY[40])
	if rr > edge then
		return nil
	end
	local topY = LOBBY.Y
	local rim = rr - (LOBBY_R + 2)
	if rim > 0 then
		topY = LOBBY.Y - 1.2 * v1smooth(rim / 6) + 2.2 * max(0, v1N(41, x, z, 7) + 0.1)
	end
	local u = rr / edge
	local thick = 26 + 72 * (1 - u * u) ^ 1.2 * (0.85 + 0.6 * (v1N(42, x, z, 45) + 0.25))
	local spike = 1 - abs(v1N(43, x, z, 20) * 3)
	if spike > 0 then
		thick += spike * spike * 26 * (1 - u)
	end
	return topY, topY - thick, rim
end

local function buildIslandChunk(cx0, cz0)
	local tops, bottoms, rims = {}, {}, {}
	local minY, maxY = HUGE, -HUGE
	for iz = 1, 16 do
		for ix = 1, 16 do
			local x = cx0 + (ix - 1) * VOX + 2
			local z = cz0 + (iz - 1) * VOX + 2
			local t, b, rim = islandColumn(x, z)
			if t then
				local k = (iz - 1) * 16 + ix
				tops[k], bottoms[k], rims[k] = t, b, rim
				minY = min(minY, b)
				maxY = max(maxY, t)
			end
		end
	end
	if maxY == -HUGE then
		return false
	end
	minY = floor(minY / VOX) * VOX - VOX
	maxY = ceil(maxY / VOX) * VOX + VOX
	local ny = (maxY - minY) // VOX
	local mats, occs, liqs = newVoxelArrays(ny)
	for iz = 1, 16 do
		for ix = 1, 16 do
			local k = (iz - 1) * 16 + ix
			local t = tops[k]
			if t then
				local bottom = bottoms[k]
				local x = cx0 + (ix - 1) * VOX + 2
				local z = cz0 + (iz - 1) * VOX + 2
				local n1, n2 = v1N(30, x, z, 24), v1N(31, x, z, 9)
				local topMat
				if rims[k] > 0 then
					topMat = (n2 > 0.1) and SLATE or ROCK
				elseif n2 > 0.4 then
					topMat = GROUND
				elseif n1 > 0.25 then
					topMat = LEAFY
				else
					topMat = GRASS
				end
				local wob = 6 * v1N(35, x, z, 40)
				for iy = 1, ny do
					local y0 = minY + (iy - 1) * VOX
					local solid = min(t - y0 - 2, y0 + 2 - bottom) * 0.25
					if solid > 1 then
						solid = 1
					end
					if solid > 0 then
						local depthBelow = t - (y0 + 2)
						local mat
						if depthBelow < 4.5 then
							mat = topMat
						elseif depthBelow < 9 and rims[k] <= 0 then
							mat = GROUND
						else
							mat = v1stratum(y0 + 2, wob)
						end
						mats[ix][iy][iz] = mat
						occs[ix][iy][iz] = solid
					end
				end
			end
		end
	end
	local region = Region3.new(Vector3.new(cx0, minY, cz0), Vector3.new(cx0 + CHUNK, maxY, cz0 + CHUNK))
	workspace.Terrain:WriteVoxelChannels(region, VOX, { SolidMaterial = mats, SolidOccupancy = occs, LiquidOccupancy = liqs })
	return true
end

local function islandChunkOrigins()
	local list = {}
	local reach = LOBBY_R + 26
	local x0 = floor((LOBBY.X - reach) / CHUNK) * CHUNK
	local z0 = floor((LOBBY.Z - reach) / CHUNK) * CHUNK
	for cx = x0, LOBBY.X + reach, CHUNK do
		for cz = z0, LOBBY.Z + reach, CHUNK do
			table.insert(list, { cx, cz })
		end
	end
	return list
end

----------------------------------------------------------------------------------------------------
-- look: palette, water, grass, clouds, waterfall mist; materials (MaterialService variants)
----------------------------------------------------------------------------------------------------
-- Terrain material colours. They multiply the variant's ColorMap (255 = the texture as authored), so each value is
-- target / texture average: granite lands on ~123 sRGB grey to match the realistic rock and cliff meshes (art
-- director), the strata bands ~100 (darker layered rock), meadow grass a natural olive green, the forest floor
-- nudged from orange-brown toward olive, bare earth from pinkish to a warm soil brown (both read mauve/lilac under
-- the blue distance haze), river pebbles muted.
-- Snow has no variant (the generated snow textures were too blue and dark); it keeps Roblox's own snow.
TerrainGen.Palette = {
	[GRASS] = Color3.fromRGB(212, 206, 232),
	[LEAFY] = Color3.fromRGB(215, 238, 255),
	[GROUND] = Color3.fromRGB(230, 255, 216), -- texture (102,78,66) -> soil brown (92,78,56): no pink cast under haze
	[MUD] = Color3.fromRGB(174, 226, 200), -- texture (88,61,51) -> wet peat (60,54,40)
	[SAND] = Color3.fromRGB(255, 250, 240),
	[SALT] = Color3.fromRGB(205, 198, 182),
	[ROCK] = Color3.fromRGB(248, 248, 250),
	[LIME] = Color3.fromRGB(215, 215, 218),
	[BASALT] = Color3.fromRGB(255, 255, 250),
	[SNOW] = Color3.fromRGB(236, 240, 245),
}

-- MaterialVariants (made with Studio's material generator, 512 px, stored in MaterialService under "Material: LS_*";
-- each prompt produced four candidates LS_X, LS_X1..3). The chosen candidate per role -> { base, studsPerTile }.
-- StudsPerTile: 8 = 64 px/stud on the ground near the eye; rock 12 (seen from further away).
TerrainGen.MaterialVariants = {
	LS_MeadowGrass1 = { base = GRASS, studsPerTile = 8 },
	LS_ForestFloor = { base = LEAFY, studsPerTile = 8 },
	LS_EarthPath1 = { base = GROUND, studsPerTile = 8 },
	LS_WetMud3 = { base = MUD, studsPerTile = 8 },
	LS_DampSand2 = { base = SAND, studsPerTile = 8 },
	LS_RiverPebbles = { base = SALT, studsPerTile = 6 },
	LS_LichenGranite3 = { base = ROCK, studsPerTile = 12 },
	-- the layered-rock granite candidate (was LS_LichenGranite1), re-based on Limestone for the strata bands: every
	-- generated shale carried vivid orange iron streaks
	LS_StrataRock = { base = LIME, studsPerTile = 10 },
	LS_Scree1 = { base = BASALT, studsPerTile = 8 },
}
-- base materials whose override TerrainGen manages: any of these without a variant above goes back to Roblox's own
TerrainGen.ManagedBases = { GRASS, LEAFY, GROUND, MUD, SAND, SALT, ROCK, LIME, BASALT, SNOW }

function TerrainGen.applyMaterials(): string
	local applied, byBase = {}, {}
	for name, info in pairs(TerrainGen.MaterialVariants) do
		local mv = MaterialService:FindFirstChild(name, true)
		if mv and mv:IsA("MaterialVariant") and mv.BaseMaterial == info.base then
			mv.StudsPerTile = info.studsPerTile
			mv.MaterialPattern = Enum.MaterialPattern.Organic
			MaterialService:SetBaseMaterialOverride(info.base, name)
			byBase[info.base] = true
			table.insert(applied, name)
		end
	end
	for _, base in ipairs(TerrainGen.ManagedBases) do
		if not byBase[base] then
			MaterialService:SetBaseMaterialOverride(base, base.Name)
		end
	end
	table.sort(applied)
	return "overrides: " .. table.concat(applied, ", ")
end

function TerrainGen.applyLook()
	local terrain = workspace.Terrain
	for material, color in pairs(TerrainGen.Palette) do
		terrain:SetMaterialColor(material, color)
	end
	-- clear mountain water (LookDevPlaybook 9.3 "Forest day"): dark green-teal, clear shallows, small slow waves
	terrain.WaterColor = Color3.fromRGB(32, 74, 72)
	terrain.WaterTransparency = 0.65
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6
	terrain.Decoration = true
	pcall(function()
		terrain.GrassLength = 0.7
	end)
	-- Terrain.Clouds and GlobalWind belong to the day/night system (LightingRig / DayCycle): not touched here
	-- soft spray drifting up from the plunge pool under the falls
	local mist = terrain:FindFirstChild("WaterfallMist")
	if not mist then
		mist = Instance.new("Attachment")
		mist.Name = "WaterfallMist"
		mist.Parent = terrain
	end
	local base = Layout.River.fall.base
	mist.WorldPosition = Vector3.new(base.X, POOL.level + 1, base.Z)
	local emitter = mist:FindFirstChildOfClass("ParticleEmitter")
	if not emitter then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Spray"
		emitter.Parent = mist
	end
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 242, 245))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 16) })
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, 1.6, 0)
	emitter.Drag = 0.6
	emitter.LightEmission = 0.1
	emitter.LightInfluence = 0.9
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-12, 12)
	emitter.Enabled = true
end

----------------------------------------------------------------------------------------------------
-- lighting: owned by the day/night system (ServerStorage.WorldGen.LightingRig). v1 behaviour as a fallback.
----------------------------------------------------------------------------------------------------
local function ensureChild(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function legacyLighting()
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(70, 72, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(108, 112, 126)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.9
	Lighting.ShadowSoftness = 0.28
	Lighting.ExposureCompensation = 0.1
	Lighting.GeographicLatitude = 44
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	if not RunService:IsRunning() then
		local lobbyHour = 14.5
		pcall(function()
			lobbyHour = require(ReplicatedStorage.Shared.Config:Clone()).Round.LobbyClockTime or lobbyHour
		end)
		Lighting.ClockTime = lobbyHour
	end
	local sky = ensureChild("Sky", "Sky") :: Sky
	sky.CelestialBodiesShown = true
	sky.StarCount = 3000
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 13
	local atmosphere = ensureChild("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.31
	atmosphere.Offset = 0.3
	atmosphere.Color = Color3.fromRGB(198, 207, 218)
	atmosphere.Decay = Color3.fromRGB(104, 118, 138)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.1
	local bloom = ensureChild("BloomEffect", "Bloom") :: BloomEffect
	bloom.Enabled = true
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.85
	local rays = ensureChild("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Enabled = true
	rays.Intensity = 0.06
	rays.Spread = 0.72
	local dof = ensureChild("DepthOfFieldEffect", "DepthOfField") :: DepthOfFieldEffect
	dof.Enabled = true
	dof.FarIntensity = 0.07
	dof.FocusDistance = 200
	dof.InFocusRadius = 420
	dof.NearIntensity = 0
	local grade = ensureChild("ColorCorrectionEffect", "ArenaGrade") :: ColorCorrectionEffect
	grade.Enabled = true
	grade.Brightness = 0.01
	grade.Contrast = 0.1
	grade.Saturation = 0.04
	grade.TintColor = Color3.fromRGB(255, 249, 240)
end

function TerrainGen.applyLighting()
	local rig = ServerStorage:FindFirstChild("WorldGen") and ServerStorage.WorldGen:FindFirstChild("LightingRig")
	if rig and rig:IsA("ModuleScript") then
		local ok, mod = pcall(function()
			return require(RunService:IsRunning() and rig or rig:Clone())
		end)
		if ok and type(mod) == "table" and type(mod.apply) == "function" then
			return mod.apply()
		end
		warn("[TerrainGen] LightingRig could not be used; applying the v1 lighting")
	end
	legacyLighting()
end

function TerrainGen.applyStreaming()
	workspace.StreamingEnabled = true
	workspace.StreamingTargetRadius = 1024
	workspace.StreamingMinRadius = 128
	workspace.StreamOutBehavior = Enum.StreamOutBehavior.Default
	workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.PauseOutsideLoadedArea
end

----------------------------------------------------------------------------------------------------
-- the Boundary: an invisible backstop ring (72 walls) fitted to the terrain at BoundaryRadius
----------------------------------------------------------------------------------------------------
local lastState = nil

local function gridHeight(S, x: number, z: number): number?
	if not S then
		return nil
	end
	local fx = (x - G0) / 4 - 0.5
	local fz = (z - G0) / 4 - 0.5
	local i, j = floor(fx), floor(fz)
	if i < 0 or j < 0 or i >= FN - 1 or j >= FN - 1 then
		return nil
	end
	local tx, tz = fx - i, fz - j
	local k = j * FN + i + 1
	local F = S.F
	local a, b, c, d = F[k], F[k + 1], F[k + FN], F[k + FN + 1]
	if a == EMPTY or b == EMPTY or c == EMPTY or d == EMPTY then
		return nil
	end
	return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz
end

function TerrainGen.buildBoundary(): string
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		return "no workspace.Arena"
	end
	local model = arena:FindFirstChild("Boundary")
	if not model then
		model = Instance.new("Model")
		model.Name = "Boundary"
		model.Parent = arena
	end
	-- rebuilt from scratch (the v1 walls stood at r 699 with other names)
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("BasePart") then
			c:Destroy()
		end
	end
	model:SetAttribute("Radius", Layout.BoundaryRadius or 712)
	local R = Layout.BoundaryRadius or 712
	local count = 72
	local width = 2 * R * sin(math.pi / count) + 2
	local lowest, highest = HUGE, -HUGE
	for i = 1, count do
		local a0 = (i - 1) * 360 / count
		local amid = a0 + 180 / count
		local hmin, hmax = HUGE, -HUGE
		for t = -0.5, 0.5, 0.125 do
			for dr = -10, 10, 5 do
				local p = Layout.polar(amid + t * 360 / count, R + dr)
				local h = gridHeight(lastState, p.X, p.Z) or Layout.heightAt(p.X, p.Z)
				if h then
					hmin, hmax = min(hmin, h), max(hmax, h)
				end
			end
		end
		if hmin == HUGE then
			hmin, hmax = 100, 400
		end
		local bottom = hmin - 30
		local topY = hmax + 260
		local wall = Instance.new("Part")
		wall.Name = string.format("Wall%02d", i)
		local mid = Layout.polar(amid, R + 2, (bottom + topY) / 2)
		wall.Size = Vector3.new(width, topY - bottom, 4)
		wall.CFrame = CFrame.lookAt(mid, Vector3.new(CX, mid.Y, CZ))
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanTouch = false
		wall.CanQuery = false
		wall.CastShadow = false
		wall.Transparency = 1
		wall.Material = Enum.Material.SmoothPlastic
		CollectionService:AddTag(wall, "NoMantle")
		wall.Parent = model
		lowest, highest = min(lowest, bottom), max(highest, topY)
	end
	return string.format("Boundary: %d walls at r=%d, y %.0f..%.0f", count, R, lowest, highest)
end

----------------------------------------------------------------------------------------------------
-- the launch plates: every workspace.Arena.Plinths child whose name ends in its plate number (Plinth01..24)
-- stands on Layout.Plates[i]. Only the position changes (the model keeps its own rotation). Its pivot goes to
-- PlazaY + offset: offset = the PlateOffset attribute when set (the realistic Plinth: 0.6, the SpirePlatform
-- tread), else the model's pivot height above its own base, measured and stored as PlateOffset the first time.
----------------------------------------------------------------------------------------------------
function TerrainGen.placePlinths(): string
	local arena = workspace:FindFirstChild("Arena")
	local folder = arena and arena:FindFirstChild("Plinths")
	if not folder then
		return "plinths: no workspace.Arena.Plinths"
	end
	local moved, skipped = 0, 0
	for _, child in ipairs(folder:GetChildren()) do
		local i = tonumber(string.match(child.Name, "(%d+)$"))
		local plate = i and Layout.Plates[i]
		if plate and (child:IsA("Model") or child:IsA("BasePart")) then
			local pivot = child:GetPivot()
			local offset = child:GetAttribute("PlateOffset")
			if type(offset) ~= "number" then
				local cf, size
				if child:IsA("Model") then
					cf, size = child:GetBoundingBox()
				else
					cf, size = child.CFrame, child.Size
				end
				offset = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
				child:SetAttribute("PlateOffset", offset)
			end
			local p = plate.Position
			child:PivotTo(CFrame.new(p.X, PLAZA_Y + offset, p.Z) * pivot.Rotation)
			moved += 1
		else
			skipped += 1
		end
	end
	return string.format("plinths: %d placed on Layout.Plates (%d skipped)", moved, skipped)
end

----------------------------------------------------------------------------------------------------
-- The realistic SpirePlatform covers the plate-band trench (see computeBores): its deck colliders span r <= 60
-- with the 24 openings, its granite linings make each opening a tube. Placed as workspace.Arena.SpirePlatform,
-- unrotated, so that its Plate_1 attachment lands on Plates[1] at the tread height (PlazaY + platformTop); an
-- existing one is only re-aligned. The Spire and the Plinths stay with the set dresser.
----------------------------------------------------------------------------------------------------
function TerrainGen.placeSpirePlatform(): string
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		return "platform: no workspace.Arena"
	end
	local model = arena:FindFirstChild("SpirePlatform")
	if not model then
		local ma = ServerStorage:FindFirstChild("MeshAssets")
		local src = ma and ma:FindFirstChild("SpirePlatform", true)
		if not (src and src:IsA("Model")) then
			return "platform: NO SpirePlatform asset in ServerStorage.MeshAssets - the plate trench is uncovered"
		end
		model = src:Clone()
		model.Name = "SpirePlatform"
		model.Parent = arena
	end
	model:PivotTo(CFrame.new(CX, PLAZA_Y, CZ))
	-- align by the Plate_1 attachment (the asset's origin is the plaza surface, tread at +platformTop)
	local a1 = model:FindFirstChild("Plate_1", true)
	if a1 and a1:IsA("Attachment") then
		local want = Layout.Plates[1].Position + Vector3.new(0, Layout.PlateTube.platformTop or 0.6, 0)
		local off = want - a1.WorldPosition
		if off.Magnitude > 0.01 then
			model:PivotTo(CFrame.new(off) * model:GetPivot())
		end
		return string.format("platform: SpirePlatform placed, Plate_1 at %s", tostring(a1.WorldPosition))
	end
	return "platform: SpirePlatform placed (no Plate_1 attachment found to check it)"
end

----------------------------------------------------------------------------------------------------
-- Loot markers (ServerStorage.ArenaData.LootSpawns, Parts with Kind / Tier / Source attributes) follow the
-- terrain: each marker's bottom face goes onto the ground under it. A marker whose spot is under water, steeper
-- than 26 degrees, inside the Spire footprint or a launch-tube bore, or outside the play area moves to the nearest
-- good spot (rings outward every 2 studs, up to 48 studs). Only the position changes (yaw is kept); the
-- attributes, names and the folder are untouched. Run after any terrain change (generate() does it).
----------------------------------------------------------------------------------------------------
function TerrainGen.seatLootMarkers(): string
	local ad = ServerStorage:FindFirstChild("ArenaData")
	local folder = ad and ad:FindFirstChild("LootSpawns")
	if not folder then
		return "loot: no ServerStorage.ArenaData.LootSpawns"
	end
	if next(BORE) == nil then
		computeBores()
	end
	-- the ground is the terrain, or the SpirePlatform's deck where it stands (its colliders are queryable)
	local arena = workspace:FindFirstChild("Arena")
	local deck = arena and arena:FindFirstChild("SpirePlatform")
	local include = deck and { workspace.Terrain, deck } or { workspace.Terrain }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.IgnoreWater = false
	local solid = RaycastParams.new()
	solid.FilterType = Enum.RaycastFilterType.Include
	solid.FilterDescendantsInstances = include
	solid.IgnoreWater = true
	local cosMax = cos(rad(26))
	local spireR = (Layout.SpireRadius or 28) - 4
	local function groundY(x: number, z: number): number?
		local hit = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), solid)
		return hit and hit.Position.Y
	end
	-- the bottom height for a footprint (hx, hz half sizes, yaw) at (x, z), or nil when the spot is no good
	local function spot(x: number, z: number, hx: number, hz: number, yaw: number): number?
		local r = sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
		if r > Layout.PlayRadius - 24 or r < spireR then
			return nil
		end
		local top = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), params)
		if not top or top.Material == Enum.Material.Water or top.Normal.Y < cosMax then
			return nil
		end
		local y = top.Position.Y
		local c, s = cos(yaw), sin(yaw)
		local hi, lo = y, y
		for _, q in ipairs({ { hx, hz }, { -hx, hz }, { hx, -hz }, { -hx, -hz } }) do
			local px, pz = x + q[1] * c + q[2] * s, z - q[1] * s + q[2] * c
			local key = floor((pz - G0) / 4) * FN + floor((px - G0) / 4) + 1
			if BORE[key] then
				return nil
			end
			local gy = groundY(px, pz)
			if not gy then
				return nil
			end
			hi, lo = max(hi, gy), min(lo, gy)
		end
		if hi - lo > 1.6 then
			return nil
		end
		-- the bottom rests on the highest corner (minus a little): nothing clips into the slope, little floats
		return max(y, hi - 0.25)
	end
	local seated, moved, failed, maxMove = 0, 0, 0, 0
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("BasePart") then
			local p = m.Position
			local _, yaw = m.CFrame:ToOrientation()
			local hx, hz = m.Size.X * 0.5, m.Size.Z * 0.5
			local bottom = spot(p.X, p.Z, hx, hz, yaw)
			local fx, fz = p.X, p.Z
			if not bottom then
				-- search outward in rings; the angle offset is deterministic per marker position
				local a0 = (p.X * 0.37 + p.Z * 0.61) % 360
				for rr = 2, 48, 2 do
					local steps = max(8, floor(rr * 1.6))
					for s = 0, steps - 1 do
						local a = rad(a0 + s * 360 / steps)
						local qx, qz = p.X + sin(a) * rr, p.Z - cos(a) * rr
						bottom = spot(qx, qz, hx, hz, yaw)
						if bottom then
							fx, fz = qx, qz
							break
						end
					end
					if bottom then
						break
					end
				end
			end
			if bottom then
				local d = sqrt((fx - p.X) ^ 2 + (fz - p.Z) ^ 2)
				if d > 0.01 then
					moved += 1
					maxMove = max(maxMove, d)
				end
				m.CFrame = CFrame.new(fx, bottom + m.Size.Y * 0.5, fz) * CFrame.fromOrientation(0, yaw, 0)
				seated += 1
			else
				failed += 1
			end
		end
	end
	return string.format("loot: %d markers seated (%d moved, furthest %.0f studs), %d without a spot", seated, moved, maxMove, failed)
end

----------------------------------------------------------------------------------------------------
-- The waterfall (workspace.Arena.Waterfall): terrain water cannot flow, so the falling water is a particle
-- curtain hung from the lip (where the gorge stream leaves the top of the face) to the plunge pool, with spray
-- where it lands. Built from River.fall and the generated terrain; rebuilt by generate(). Parts are invisible,
-- non-colliding and non-queryable (raycasts, mantling and the set dresser ignore them).
----------------------------------------------------------------------------------------------------
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function fxPart(name: string, cf: CFrame, size: Vector3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Locked = true
	p.Parent = parent
	return p
end

function TerrainGen.buildWaterfall(): string
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		return "waterfall: no workspace.Arena"
	end
	local model = arena:FindFirstChild("Waterfall")
	if not model then
		model = Instance.new("Model")
		model.Name = "Waterfall"
		model.Parent = arena
	end
	model:ClearAllChildren()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	local P = POOL.center
	local L = Layout.River.fall.lip
	local dir = Vector3.new(P.X - L.X, 0, P.Z - L.Z).Unit
	local across = Vector3.new(-dir.Z, 0, dir.X)
	-- the edge of the face: from the lip toward the pool, the last point still at the lip level
	local edge = Vector3.new(L.X, 0, L.Z)
	for d = 0, 30, 0.5 do
		local q = Vector3.new(L.X, 0, L.Z) + dir * d
		local hit = workspace:Raycast(Vector3.new(q.X, FALL_TOP + 40, q.Z), Vector3.new(0, -120, 0), params)
		if hit and hit.Position.Y < FALL_TOP - 3 then
			break
		end
		edge = q
	end
	local topY = FALL_TOP + 0.4
	local drop = topY - POOL.level
	local width = 9.5
	-- the curtain: a thin box across the stream at the edge (X = across), its Bottom face emitting down and leaning
	-- 8 degrees out over the drop
	local lean = rad(8)
	local upV = Vector3.yAxis * cos(lean) - dir * sin(lean)
	local curtainCF = CFrame.fromMatrix(Vector3.new(edge.X, topY, edge.Z), across, upV)
	local curtain = fxPart("Curtain", curtainCF, Vector3.new(width, 0.4, 1.6), model)
	local t = sqrt(2 * drop / 52) -- time to fall (gravity 52 studs/s^2, small initial speed)
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "Streaks"
	streaks.Texture = SMOKE
	streaks.Shape = Enum.ParticleEmitterShape.Box
	streaks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	streaks.EmissionDirection = Enum.NormalId.Bottom
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.Acceleration = Vector3.new(0, -52, 0)
	streaks.Speed = NumberRange.new(3, 6)
	streaks.SpreadAngle = Vector2.new(4, 4)
	streaks.Lifetime = NumberRange.new(t * 0.92, t * 1.02)
	streaks.Rate = 260
	streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 3.6) })
	streaks.Squash = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 2.8) })
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.15, 0.12),
		NumberSequenceKeypoint.new(0.85, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.Color = ColorSequence.new(Color3.fromRGB(248, 252, 253), Color3.fromRGB(222, 236, 240))
	streaks.LightEmission = 0.3
	streaks.LightInfluence = 0.9
	streaks.Parent = curtain
	local body = streaks:Clone()
	body.Name = "Body"
	body.Rate = 90
	body.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.6), NumberSequenceKeypoint.new(1, 6) })
	body.Squash = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.2) })
	body.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(0.3, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	body.Color = ColorSequence.new(Color3.fromRGB(226, 238, 242))
	body.Parent = curtain
	-- spray where the water lands (the curtain falls ~1.5 studs out from the edge)
	local landing = edge + dir * 1.5
	local splashCF = CFrame.fromMatrix(Vector3.new(landing.X, POOL.level + 0.4, landing.Z), across, Vector3.yAxis)
	local splashPart = fxPart("Splash", splashCF, Vector3.new(width + 1, 0.4, 3), model)
	local splash = Instance.new("ParticleEmitter")
	splash.Name = "Splash"
	splash.Texture = SMOKE
	splash.Shape = Enum.ParticleEmitterShape.Box
	splash.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Speed = NumberRange.new(4, 10)
	splash.SpreadAngle = Vector2.new(40, 40)
	splash.Acceleration = Vector3.new(0, -16, 0)
	splash.Drag = 1.2
	splash.Lifetime = NumberRange.new(0.8, 1.6)
	splash.Rate = 90
	splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	splash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.4, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	splash.Color = ColorSequence.new(Color3.fromRGB(238, 244, 246))
	splash.Rotation = NumberRange.new(0, 360)
	splash.RotSpeed = NumberRange.new(-40, 40)
	splash.LightEmission = 0.2
	splash.LightInfluence = 0.9
	splash.Parent = splashPart
	-- the soft mist drifting up from the pool (applyLook's emitter) sits where the water lands
	local mist = workspace.Terrain:FindFirstChild("WaterfallMist")
	if mist and mist:IsA("Attachment") then
		mist.WorldPosition = Vector3.new(landing.X, POOL.level + 1, landing.Z)
	end
	model:SetAttribute("Edge", Vector3.new(edge.X, topY, edge.Z))
	model:SetAttribute("Drop", drop)
	return string.format("waterfall: curtain %.0f wide, %.1f-stud drop at (%.0f, %.0f)", width, drop, edge.X, edge.Z)
end

----------------------------------------------------------------------------------------------------
-- TerrainData: an 8-stud grid (H, slope, cliff distance, moisture, water depth) for the set dresser
----------------------------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64T = {}
for i = 1, 64 do
	B64T[i - 1] = string.sub(B64, i, i)
end
local function encodeBase64(buf: buffer): string
	local len = buffer.len(buf)
	local out = table.create(math.ceil(len / 3))
	local o = 0
	for i = 0, len - 1, 3 do
		local b1 = buffer.readu8(buf, i)
		local b2 = (i + 1 < len) and buffer.readu8(buf, i + 1) or 0
		local b3 = (i + 2 < len) and buffer.readu8(buf, i + 2) or 0
		local v = b1 * 65536 + b2 * 256 + b3
		local c1 = B64T[v // 262144]
		local c2 = B64T[(v // 4096) % 64]
		local c3 = (i + 1 < len) and B64T[(v // 64) % 64] or "="
		local c4 = (i + 2 < len) and B64T[v % 64] or "="
		o += 1
		out[o] = c1 .. c2 .. c3 .. c4
	end
	return table.concat(out)
end

local function writeTerrainData(S): string
	local cell, origin = 8, -704
	local n = (-origin * 2) // cell
	local bH = buffer.create(n * n * 2)
	local bS, bC, bM, bW = buffer.create(n * n), buffer.create(n * n), buffer.create(n * n), buffer.create(n * n)
	for J = 0, n - 1 do
		for I = 0, n - 1 do
			local fi = (origin + I * cell - G0) // 4
			local fj = (origin + J * cell - G0) // 4
			local hs, sm, cd, mo, wd, cnt = 0, 0, 255, 0, 0, 0
			for dj = 0, 1 do
				for di = 0, 1 do
					local k = (fj + dj) * FN + (fi + di) + 1
					local h = S.F[k]
					if h ~= EMPTY then
						hs += h
						cnt += 1
						sm = max(sm, S.slope[k])
						cd = min(cd, S.dCliff[k])
						mo += S.moist[k]
						wd = max(wd, S.WL[k] - h)
					end
				end
			end
			local idx = J * n + I
			local h = (cnt > 0) and hs / cnt or 0
			buffer.writeu16(bH, idx * 2, math.clamp(floor((h + 64) * 32 + 0.5), 0, 65535))
			buffer.writeu8(bS, idx, math.clamp(floor(sm + 0.5), 0, 90))
			buffer.writeu8(bC, idx, math.clamp(floor(cd + 0.5), 0, 255))
			buffer.writeu8(bM, idx, math.clamp(floor(((cnt > 0) and mo / cnt or 0) * 255 + 0.5), 0, 255))
			buffer.writeu8(bW, idx, math.clamp(floor(max(0, wd) * 10 + 0.5), 0, 255))
		end
		maybeYield()
	end
	local channels = { H = encodeBase64(bH), S = encodeBase64(bS), C = encodeBase64(bC), M = encodeBase64(bM), W = encodeBase64(bW) }
	local wg = ServerStorage:FindFirstChild("WorldGen")
	if not wg then
		return "no ServerStorage.WorldGen"
	end
	local mod = wg:FindFirstChild("TerrainData")
	if not (mod and mod:IsA("ModuleScript")) then
		mod = Instance.new("ModuleScript")
		mod.Name = "TerrainData"
		mod.Parent = wg
	end
	-- one child ModuleScript per channel: a script Source is capped at 200,000 characters (H alone is ~83k)
	local total = 0
	for key, str in pairs(channels) do
		local child = mod:FindFirstChild(key)
		if not (child and child:IsA("ModuleScript")) then
			child = Instance.new("ModuleScript")
			child.Name = key
			child.Parent = mod
		end
		child.Source = "-- TerrainData channel " .. key .. " (base64), generated by TerrainGen v2; do not edit by hand.\nreturn \"" .. str .. "\"\n"
		total += #str
	end
	mod.Source = table.concat({
		"-- TerrainData: generated by ServerStorage.WorldGen.TerrainGen v2 (do not edit by hand).",
		"-- An 8-stud grid over x, z in [-704, 704): cell (I, J) centre = origin + (I + 0.5) * cell. Base64 channels, one child",
		"-- ModuleScript each (a script Source is capped at 200,000 characters):",
		"--   H = u16 (height + 64) * 32, S = u8 slope degrees, C = u8 flat distance to > 50 deg ground (studs, cap 255),",
		"--   M = u8 moisture * 255, W = u8 water depth * 10. Read it through Shared.ArenaLayout (moistureAt, distanceToCliff, ...).",
		"local function channel(name: string): string",
		"\treturn require(script:FindFirstChild(name) :: ModuleScript)",
		"end",
		"return {",
		"\tversion = 2,",
		string.format("\tcell = %d,", cell),
		string.format("\torigin = %d,", origin),
		string.format("\tn = %d,", n),
		"\tchannels = {",
		'\t\tH = channel("H"),',
		'\t\tS = channel("S"),',
		'\t\tC = channel("C"),',
		'\t\tM = channel("M"),',
		'\t\tW = channel("W"),',
		"\t},",
		"}",
		"",
	}, "\n")
	return string.format("TerrainData %dx%d (%d base64 chars in 5 channel modules)", n, n, total)
end

----------------------------------------------------------------------------------------------------
-- public API
----------------------------------------------------------------------------------------------------
function TerrainGen.heightAt(x: number, z: number): number?
	return gridHeight(lastState, x, z) or Layout.heightAt(x, z)
end

function TerrainGen.getState()
	return lastState
end

-- (re)write ServerStorage.WorldGen.TerrainData from the last build (builds first when there is none)
function TerrainGen.writeData(): string
	if not lastState then
		TerrainGen.build()
	end
	return writeTerrainData(lastState)
end

-- cells where a water step is an intended cascade (gorge, creek steps, falls sheet)
local function markCascades(S)
	local ok = {}
	for k = 1, FN * FN do
		local id = S.chId[k]
		if id == 1 or id == 2 then
			local smp = CHANNELS[id].samples
			local a = smp[S.chSeg[k]]
			local b = smp[min(S.chSeg[k] + 1, #smp)]
			if a and ((a.cascade or b.cascade) or a.gorge == 1 or a.fall or b.fall or a.smoothY or b.smoothY) then
				ok[k] = true
			end
		end
	end
	-- (v2.0 hung a vertical water sheet over the falls chute and exempted it from sealing; the chute is dry rock
	-- now, so nothing is exempt: the lip pool gets sealed like any other water)
	for _, k in ipairs(S.fallSheet or {}) do
		ok[k] = true
	end
	S.sheet = {}
	local P = POOL.center
	local i0, j0 = floor((P.X - 60 - G0) / 4), floor((P.Z - 60 - G0) / 4)
	for j = j0, j0 + 30 do
		for i = i0, i0 + 30 do
			ok[j * FN + i + 1] = true
		end
	end
	S.cascadeOK = ok
end

function TerrainGen.build(opts): any
	local o = opts or {}
	local S = {}
	local terrain = workspace.Terrain
	local t0 = os.clock()
	local status = function(text, p)
		terrain:SetAttribute("TerrainGenStatus", text)
		if p then
			terrain:SetAttribute("TerrainGenProgress", p)
		end
	end
	status("coarse heightfield", 0.02)
	buildCoarse(S)
	status("erosion", 0.12)
	erodeCoarse(S, o.erosion ~= false)
	status("fine heightfield", 0.3)
	buildFine(S)
	S.WL = table.create(FN * FN, EMPTY)
	status("channels", 0.38)
	stampChannels(S)
	carveChannels(S)
	status("falls, lake, marsh", 0.44)
	carveFalls(S)
	carveLake(S)
	carveMarsh(S)
	shapeSpecials(S)
	status("mountain wall", 0.48)
	shapeMountainWall(S)
	markCascades(S)
	status("sealing water", 0.5)
	sealWater(S)
	status("fields", 0.53)
	computeFields(S)
	status("materials", 0.58)
	computeMaterials(S)
	S.buildTime = os.clock() - t0
	lastState = S
	return S
end

function TerrainGen.generate(opts: { [string]: any }?)
	local o = opts or {}
	local terrain = workspace.Terrain
	local started = os.clock()
	yieldClock = os.clock()
	local S = TerrainGen.build(o)
	computeBores()
	S.containFills = 0
	if o.clear ~= false then
		terrain:SetAttribute("ArenaTerrainReady", false)
		terrain:Clear()
	end
	local arena = arenaChunkOrigins()
	local island = (o.island ~= false) and islandChunkOrigins() or {}
	local total = #arena + #island
	local done = 0
	terrain:SetAttribute("TerrainGenStatus", "voxels")
	for _, c in ipairs(arena) do
		writeArenaChunk(S, c[1], c[2])
		done += 1
		if done % 4 == 0 then
			terrain:SetAttribute("TerrainGenProgress", 0.6 + 0.35 * done / total)
		end
		maybeYield()
	end
	for _, c in ipairs(island) do
		buildIslandChunk(c[1], c[2])
		done += 1
		maybeYield()
	end
	local notes = {
		S.erosionStats or "",
		"seal fixes " .. tostring(S.sealFixes),
		"containment fills " .. tostring(S.containFills),
		S.wallStats or "",
	}
	if o.look ~= false then
		TerrainGen.applyLook()
		table.insert(notes, TerrainGen.applyMaterials())
	end
	if o.waterfall ~= false then
		table.insert(notes, TerrainGen.buildWaterfall())
	end
	if o.lighting ~= false then
		TerrainGen.applyLighting()
	end
	if o.streaming ~= false then
		TerrainGen.applyStreaming()
	end
	if o.boundary ~= false then
		table.insert(notes, TerrainGen.buildBoundary())
	end
	if o.platform ~= false then
		table.insert(notes, TerrainGen.placeSpirePlatform())
	end
	if o.plinths ~= false then
		table.insert(notes, TerrainGen.placePlinths())
	end
	if o.loot ~= false then
		table.insert(notes, TerrainGen.seatLootMarkers())
	end
	if o.data ~= false then
		table.insert(notes, writeTerrainData(S))
	end
	terrain:SetAttribute("TerrainVersion", TerrainGen.VERSION)
	if o.markReady ~= false then
		terrain:SetAttribute("ArenaTerrainReady", true)
	end
	terrain:SetAttribute("TerrainGenProgress", 1)
	local summary = string.format("done: %d chunks in %.1fs (build %.1fs); %s", total, os.clock() - started, S.buildTime, table.concat(notes, "; "))
	terrain:SetAttribute("TerrainGenStatus", summary)
	return summary
end

function TerrainGen.start(opts: { [string]: any }?)
	workspace.Terrain:SetAttribute("TerrainGenStatus", "starting")
	task.spawn(function()
		local ok, err = xpcall(TerrainGen.generate, debug.traceback, opts)
		if not ok then
			workspace.Terrain:SetAttribute("TerrainGenStatus", "error: " .. tostring(err))
			warn("[TerrainGen] " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- verification (raycasts and voxel reads against the written terrain)
----------------------------------------------------------------------------------------------------
local function terrainParams(ignoreWater: boolean): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = ignoreWater
	return params
end

-- TerrainGen.check(name) -> report string. Each check works on the written terrain (raycasts / voxel reads), the
-- way an outside reviewer measures it; `verify()` runs them all.
--   "lattice"   holes and spikes on a 16-stud lattice inside the play area
--   "plaza"     plaza flatness on a 2-stud grid (r <= 60, off the bores): samples more than 0.25 off PlazaY
--   "tubes"     per plate: axis floor, nearest wall at y 36 / 40 / 44 (32 directions), a 4.8 x 4.8 block cast
--               (axis-aligned and turned to the plate) and a 2.8-radius sphere cast (the realistic Plinth) down
--               the shaft
--   "water"     every wet sample on the 4-stud grid (both grid phases) beside a dry one whose ground is more than
--               0.75 below the water surface (an exposed water face), by water body
--   "voxels"    water voxels (liquid > 0.02) with a horizontal neighbour that is pure air
--   "mountains" a walk search on the 4-stud grid from the r 628-640 ring (uphill steps <= 46 deg): 10-degree
--               sectors that reach r >= 712 and the furthest r; the gentlest radial 1-stud profile
--   "fords"     water depth along each ford's crossing line, and the shallowest line within +-16 studs
local Checks = {}

function Checks.lattice(): string
	if next(BORE) == nil then
		computeBores()
	end
	local S = lastState
	local solid = terrainParams(true)
	local holes, spikes, cols, inTrench = 0, 0, 0, 0
	for z = -640, 640, 16 do
		for x = -640, 640, 16 do
			if x * x + z * z < 640 * 640 then
				cols += 1
				local k = floor((z - G0) / 4) * FN + floor((x - G0) / 4) + 1
				local hit = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), solid)
				if BORE[k] then
					inTrench += 1 -- the plate-band trench (by design; the SpirePlatform covers it)
				elseif not hit then
					holes += 1
				elseif S then
					local g = gridHeight(S, x, z)
					if g and abs(hit.Position.Y - g) > 6 and S.slope[k] < 30 then
						spikes += 1
					end
				end
			end
		end
		maybeYield()
	end
	return string.format("lattice: %d columns, %d holes, %d spikes (> 6 off the grid on < 30 deg); %d in the plate trench", cols, holes, spikes, inTrench)
end

function Checks.plaza(): string
	if next(BORE) == nil then
		computeBores()
	end
	local solid = terrainParams(true)
	-- the terrain plaza inside the plate trench (under the SpirePlatform's inner deck) on a 2-stud grid
	local R = 40
	local total, off, worst = 0, 0, 0
	for z = -R, R, 2 do
		for x = -R, R, 2 do
			if x * x + z * z <= R * R then
				total += 1
				local hit = workspace:Raycast(Vector3.new(x, PLAZA_Y + 40, z), Vector3.new(0, -80, 0), solid)
				local d = hit and abs(hit.Position.Y - PLAZA_Y) or 99
				if d > 0.25 then
					off += 1
				end
				worst = max(worst, d)
			end
		end
	end
	-- the trench extent and the ground just outside it (r 60.5..66, beyond the platform's rim)
	local rIn, rOut, rimLow = HUGE, 0, 0
	for k in pairs(BORE) do
		local j = (k - 1) // FN
		local i = (k - 1) - j * FN
		local r = sqrt((G0 + 4 * i + 2 - CX) ^ 2 + (G0 + 4 * j + 2 - CZ) ^ 2)
		rIn, rOut = min(rIn, r), max(rOut, r)
	end
	for a = 0, 359, 3 do
		for r = 61, 66, 1 do
			local p = Layout.polar(a, r)
			local hit = workspace:Raycast(Vector3.new(p.X, PLAZA_Y + 40, p.Z), Vector3.new(0, -80, 0), solid)
			if hit then
				rimLow = max(rimLow, PLAZA_Y - hit.Position.Y)
			end
		end
	end
	return string.format(
		"plaza: %d samples (r <= %d), %d more than 0.25 off y %.1f (worst %.2f); trench cells r %.1f..%.1f; ground at r 61-66 at most %.2f below the plaza",
		total, R, off, PLAZA_Y, worst, rIn, rOut, rimLow
	)
end

function Checks.tubes(): string
	local solid = terrainParams(true)
	local floorMin, floorMax, wallMin = HUGE, -HUGE, HUGE
	local blockOK, blockTurnedOK, sphereOK = 0, 0, 0
	local worst = {}
	for i, p in ipairs(PLATES) do
		local f = workspace:Raycast(Vector3.new(p.X, PLAZA_Y + 20, p.Z), Vector3.new(0, -40, 0), solid)
		local fy = f and f.Position.Y or -1
		floorMin, floorMax = min(floorMin, fy), max(floorMax, fy)
		local wmin = HUGE
		for _, y in ipairs({ TUBE_FLOOR + 2, 40, PLAZA_Y - 2 }) do
			for a = 0, 348.75, 11.25 do
				local d = Vector3.new(sin(rad(a)), 0, cos(rad(a)))
				local hit = workspace:Raycast(Vector3.new(p.X, y, p.Z), d * 20, solid)
				wmin = min(wmin, hit and hit.Distance or 20)
			end
		end
		wallMin = min(wallMin, wmin)
		local function reaches(hit: RaycastResult?): boolean
			return hit == nil or hit.Position.Y < TUBE_FLOOR + 1.5
		end
		local top = CFrame.new(p.X, PLAZA_Y + 10, p.Z)
		local down = Vector3.new(0, -(PLAZA_Y + 10 - TUBE_FLOOR + 2), 0)
		local b1 = workspace:Blockcast(top, Vector3.new(4.8, 1, 4.8), down, solid)
		local b2 = workspace:Blockcast(CFrame.new(p.X, PLAZA_Y + 10, p.Z) * Layout.Plates[i].Rotation, Vector3.new(4.8, 1, 4.8), down, solid)
		local s1 = workspace:Spherecast(Vector3.new(p.X, PLAZA_Y + 10, p.Z), 2.8, down, solid)
		blockOK += reaches(b1) and 1 or 0
		blockTurnedOK += reaches(b2) and 1 or 0
		sphereOK += reaches(s1) and 1 or 0
		if wmin < 3.6 or not reaches(b1) then
			table.insert(worst, string.format("#%d wall %.2f block %s", i, wmin, b1 and string.format("%.1f", b1.Position.Y) or "floor"))
		end
	end
	return string.format(
		"tubes: floor %.2f..%.2f; nearest wall %.2f studs from the axis (y %d/40/%d, 32 dirs); 4.8 block reaches the floor %d/24 (turned to the plate %d/24); r 2.8 sphere %d/24 %s",
		floorMin, floorMax, wallMin, TUBE_FLOOR + 2, PLAZA_Y - 2, blockOK, blockTurnedOK, sphereOK, table.concat(worst, "; ")
	)
end

-- the water body a grid point belongs to (for the report)
local function waterBody(x: number, z: number): string
	local S = lastState
	if S then
		local k = floor((z - G0) / 4) * FN + floor((x - G0) / 4) + 1
		local id = S.chId[k]
		if S.rLake[k] < 12 then
			return "lake"
		elseif S.rMarsh[k] < 8 then
			return "marsh"
		elseif (S.chD[k] or HUGE) < 30 and id > 0 then
			if id == 1 then
				return S.gorgeCell[k] and "gorge" or "river"
			end
			return (id == 2) and "creek" or "outflow"
		end
		local P = POOL.center
		if (x - P.X) ^ 2 + (z - P.Z) ^ 2 < 40 * 40 then
			return "pool"
		end
	end
	return "other"
end

function Checks.water(): string
	local S = lastState
	if not S then
		return "water: build first"
	end
	local wetP, solid = terrainParams(false), terrainParams(true)
	local cache = {}
	local function sample(x: number, z: number)
		local key = x * 100003 + z
		local c = cache[key]
		if c == nil then
			local g = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), solid)
			local t = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), wetP)
			local gy = g and g.Position.Y or -HUGE
			local wy = (t and t.Material == Enum.Material.Water and t.Position.Y > gy + 0.05) and t.Position.Y or nil
			c = { gy, wy }
			cache[key] = c
		end
		return c[1], c[2]
	end
	local counts, worst, worstAt = {}, {}, {}
	local total, edges, bands = 0, 0, { 0, 0, 0, 0 }
	for _, phase in ipairs({ 0, 2 }) do
		for j = 0, FN - 1 do
			for i = 0, FN - 1 do
				local k = j * FN + i + 1
				if S.F[k] ~= EMPTY and S.dWater[k] <= 4 then
					local x, z = G0 + 4 * i + phase, G0 + 4 * j + phase
					local _, wy = sample(x, z)
					if wy then
						for _, d in ipairs({ { 4, 0 }, { -4, 0 }, { 0, 4 }, { 0, -4 } }) do
							local gy2, wy2 = sample(x + d[1], z + d[2])
							if not wy2 then
								edges += 1
								local drop = wy - gy2
								if drop > 0.75 then
									total += 1
									local body = waterBody(x, z)
									counts[body] = (counts[body] or 0) + 1
									bands[(drop < 1.5) and 1 or (drop < 3) and 2 or (drop < 6) and 3 or 4] += 1
									if drop > (worst[body] or 0) then
										worst[body] = drop
										worstAt[body] = string.format("(%d,%d)", x, z)
									end
								end
							end
						end
					end
				end
			end
			maybeYield()
		end
	end
	local parts = {}
	for body, c in pairs(counts) do
		table.insert(parts, string.format("%s %d (worst %.1f at %s)", body, c, worst[body], worstAt[body]))
	end
	table.sort(parts)
	return string.format(
		"water: %d wet/dry edges checked, %d exposed (> 0.75 below the water: %d at 0.75-1.5, %d at 1.5-3, %d at 3-6, %d over 6) %s",
		edges, total, bands[1], bands[2], bands[3], bands[4], table.concat(parts, ", ")
	)
end

function Checks.voxels(): string
	local S = lastState
	if not S then
		return "voxels: build first"
	end
	local terrain = workspace.Terrain
	local exposed, waterVox, visible = 0, 0, 0
	local where = {}
	for _, c in ipairs(arenaChunkOrigins()) do
		local cx0, cz0 = c[1], c[2]
		local i0, j0 = (cx0 - G0) // 4, (cz0 - G0) // 4
		local wmin, wmax = HUGE, -HUGE
		for jj = j0, j0 + 15 do
			for ii = i0, i0 + 15 do
				local k = jj * FN + ii + 1
				local w = S.WL[k]
				if w and w > EMPTY and w > S.F[k] then
					wmin, wmax = min(wmin, S.F[k]), max(wmax, w)
				end
			end
		end
		if wmax > -HUGE then
			local y0 = floor((wmin - 8) / 4) * 4
			local y1 = ceil((wmax + 8) / 4) * 4
			local region = Region3.new(Vector3.new(cx0 - 4, y0, cz0 - 4), Vector3.new(cx0 + CHUNK + 4, y1, cz0 + CHUNK + 4))
			local ch = terrain:ReadVoxelChannels(region, 4, { "SolidOccupancy", "LiquidOccupancy" })
			local so, lo = ch.SolidOccupancy, ch.LiquidOccupancy
			local size = ch.Size or so.Size
			local sx, sy, sz = size.X, size.Y, size.Z
			for ix = 2, sx - 1 do
				for iy = 1, sy do
					for iz = 2, sz - 1 do
						local l = lo[ix][iy][iz]
						if l > 0.02 then
							waterVox += 1
							for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
								local nx, nz = ix + d[1], iz + d[2]
								if so[nx][iy][nz] == 0 and lo[nx][iy][nz] == 0 then
									exposed += 1
									if l > 0.25 then
										visible += 1
										if #where < 6 then
											table.insert(where, string.format("(%d,%d,%d) l%.2f", cx0 - 4 + (ix - 1) * 4 + 2, y0 + (iy - 1) * 4 + 2, cz0 - 4 + (iz - 1) * 4 + 2, l))
										end
									end
									break
								end
							end
						end
					end
				end
			end
			maybeYield()
		end
	end
	return string.format("voxels: %d water voxels, %d beside pure air (%d of them more than a quarter full) %s", waterVox, exposed, visible, table.concat(where, " "))
end

function Checks.mountains(): string
	local solid = terrainParams(true)
	local R0, R1 = 560, 800
	local nG = floor(R1 / 4)
	local H = {}
	local function key(i: number, j: number): number
		return (j + nG) * (2 * nG + 1) + (i + nG)
	end
	for j = -nG, nG do
		local z = j * 4
		for i = -nG, nG do
			local x = i * 4
			local r2 = x * x + z * z
			if r2 >= R0 * R0 and r2 <= R1 * R1 then
				local hit = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), solid)
				if hit then
					H[key(i, j)] = hit.Position.Y
				end
			end
		end
		maybeYield()
	end
	local tanMax = math.tan(rad(46))
	local queue, head, seen = {}, 1, {}
	for j = -nG, nG do
		for i = -nG, nG do
			local r = sqrt((i * 4) ^ 2 + (j * 4) ^ 2)
			if r >= 628 and r <= 640 and H[key(i, j)] then
				local kk = key(i, j)
				seen[kk] = true
				table.insert(queue, { i, j })
			end
		end
	end
	local sectors, maxR = {}, 0
	while head <= #queue do
		local c = queue[head]
		head += 1
		local i, j = c[1], c[2]
		local h = H[key(i, j)]
		local r = sqrt((i * 4) ^ 2 + (j * 4) ^ 2)
		if r > maxR then
			maxR = r
		end
		if r >= 712 then
			sectors[floor((deg(atan2(i * 4, -j * 4)) % 360) / 10)] = true
		end
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			local ni, nj = i + d[1], j + d[2]
			local nk = key(ni, nj)
			local h2 = H[nk]
			if h2 and not seen[nk] then
				local dist = (d[1] ~= 0 and d[2] ~= 0) and 5.657 or 4
				if h2 - h <= dist * tanMax then
					seen[nk] = true
					table.insert(queue, { ni, nj })
				end
			end
		end
		if head % 4000 == 0 then
			maybeYield()
		end
	end
	local nSec = 0
	for _ in pairs(sectors) do
		nSec += 1
	end
	-- radial 1-stud profiles every degree from r 640 to 712: the steepest single-stud rise on each; report the
	-- gentlest of those (a profile whose steepest rise is small could be climbed)
	local gentlest, gentAngle = HUGE, -1
	for a = 0, 359 do
		local prev = nil
		local steepest = 0
		for r = 640, 712 do
			local p = Layout.polar(a, r)
			local hit = workspace:Raycast(Vector3.new(p.X, 1400, p.Z), Vector3.new(0, -1700, 0), solid)
			local y = hit and hit.Position.Y
			if y and prev then
				steepest = max(steepest, y - prev)
			end
			prev = y
		end
		if steepest < gentlest then
			gentlest, gentAngle = steepest, a
		end
		if a % 30 == 0 then
			maybeYield()
		end
	end
	return string.format(
		"mountains: walk search (uphill <= 46 deg, 4-stud grid) from r 628-640 reaches r >= 712 in %d/36 sectors, furthest r %.0f; every radial profile r 640-712 has a single-stud rise of at least %.2f (gentlest at %d deg)",
		nSec, maxR, gentlest, gentAngle
	)
end

function Checks.fords(): string
	local wetP, solid = terrainParams(false), terrainParams(true)
	local function depthAt(x: number, z: number): number
		local g = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), solid)
		local t = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), wetP)
		if g and t and t.Material == Enum.Material.Water then
			return max(0, t.Position.Y - g.Position.Y)
		end
		return 0
	end
	local out = {}
	for _, c in ipairs(Layout.Crossings) do
		if c.kind == "Ford" then
			local dir = c.direction
			local along = Vector3.new(-dir.Z, 0, dir.X)
			local half = c.span * 0.5 + 6
			local function lineMax(shift: number): number
				local m = 0
				for t = -half, half, 1 do
					local p = c.position + dir * t + along * shift
					m = max(m, depthAt(p.X, p.Z))
				end
				return m
			end
			local onLine = lineMax(0)
			local best, bestShift = onLine, 0
			for shift = -16, 16, 2 do
				local m = lineMax(shift)
				if m < best then
					best, bestShift = m, shift
				end
			end
			table.insert(out, string.format("%s %.2f deep on its line (shallowest line within +-16: %.2f at %+d)", c.name, onLine, best, bestShift))
		end
	end
	return "fords: " .. table.concat(out, ", ")
end

function TerrainGen.check(name: string): string
	local fn = Checks[name]
	if not fn then
		return "unknown check " .. tostring(name)
	end
	yieldClock = os.clock()
	return fn()
end

function TerrainGen.verify(): string
	local out = {}
	for _, name in ipairs({ "lattice", "plaza", "tubes", "water", "voxels", "fords", "mountains" }) do
		table.insert(out, TerrainGen.check(name))
	end
	-- POIs and caves
	local solid = terrainParams(true)
	local pois = {}
	for _, p in ipairs(Layout.POIs) do
		local hit = workspace:Raycast(Vector3.new(p.position.X, 1400, p.position.Z), Vector3.new(0, -1700, 0), solid)
		table.insert(pois, string.format("%s %.1f", p.name, hit and hit.Position.Y or -1))
	end
	table.insert(out, "POI ground: " .. table.concat(pois, ", "))
	local caves = {}
	for _, cave in ipairs(Layout.Caves) do
		local c, m = cave.chamber, cave.mouth
		local up = workspace:Raycast(Vector3.new(c.X, cave.floorY + 2, c.Z), Vector3.new(0, 40, 0), solid)
		local dn = workspace:Raycast(Vector3.new(m.X, cave.floorY + 4, m.Z), Vector3.new(0, -12, 0), solid)
		local from = Vector3.new(m.X, cave.floorY + 2.5, m.Z)
		local mo = workspace:Raycast(from, Vector3.new(c.X, cave.floorY + 2.5, c.Z) - from, solid)
		table.insert(caves, string.format("%s mouth floor %.1f, chamber ceiling +%.1f, mouth->chamber %s", cave.name, dn and dn.Position.Y or -1, up and (up.Position.Y - cave.floorY) or -1, mo and string.format("blocked at %.0f", mo.Distance) or "clear"))
	end
	table.insert(out, "caves: " .. table.concat(caves, "; "))
	return table.concat(out, "\n")
end

-- Ground heights on the written terrain, as Lua text to paste into ArenaLayout (POIHeights, CrossingHeights).
-- POIs: the ground at the centre (caves: the floor measured just inside the mouth; the waterfall: the pool's water
-- surface). Span crossings (log, footbridge): the mean ground height at both ends (centre +- direction * span / 2),
-- where the deck sits.
function TerrainGen.measure(): string
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	local function ground(x, z)
		local hit = workspace:Raycast(Vector3.new(x, 1400, z), Vector3.new(0, -1700, 0), params)
		return hit and hit.Position.Y
	end
	local poi = {}
	for _, p in ipairs(Layout.POIs) do
		local y
		if p.kind == "Spire" then
			y = nil
		elseif p.kind == "Cave" and p.cave and Layout.Caves[p.cave] then
			-- the floor 1 stud inside the mouth (cast down from the tunnel's middle height)
			local cave = Layout.Caves[p.cave]
			local m, nx = cave.path[1], cave.path[2]
			local inward = Vector3.new(nx.X - m.X, 0, nx.Z - m.Z).Unit
			local q = Vector3.new(m.X, cave.floorY + 4, m.Z) + inward
			local hit = workspace:Raycast(q, Vector3.new(0, -14, 0), params)
			y = hit and hit.Position.Y or cave.floorY
		elseif p.kind == "Waterfall" then
			y = POOL.level
		else
			y = ground(p.position.X, p.position.Z)
		end
		if y then
			table.insert(poi, string.format("%s = %.1f", p.name, y))
		end
	end
	local cross = {}
	for _, c in ipairs(Layout.Crossings) do
		if c.kind == "Log" or c.kind == "Footbridge" then
			local half = c.span * 0.5
			local a = ground(c.position.X + c.direction.X * half, c.position.Z + c.direction.Z * half)
			local b = ground(c.position.X - c.direction.X * half, c.position.Z - c.direction.Z * half)
			if a and b then
				table.insert(cross, string.format("%s = %.1f", c.name, (a + b) * 0.5))
			end
		end
	end
	return "ArenaLayout.POIHeights = { " .. table.concat(poi, ", ") .. " }\nArenaLayout.CrossingHeights = { " .. table.concat(cross, ", ") .. " }"
end

return TerrainGen
