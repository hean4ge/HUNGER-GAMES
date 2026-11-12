--[[
	Populate (v2) - set dressing for the classic forest arena and the Tor (the lobby island) with the realistic templates
	in ServerStorage.MeshAssets (TreesReal, GroundReal, LandmarksReal, BuildingsReal, PropsReal). Owner: environment art.
	Seeded (ArenaLayout.Seed plus a salt per step and rule), deterministic (the same terrain, markers and code give the
	same world), chunked (yields every ~20 ms so Studio stays responsive) and re-runnable: each step clears only what it
	owns, then rebuilds it. v1 (part-built, WorldAssets templates) is archived as ServerStorage.Archive_v1.Populate_v1.
	Children: Sites (Spire, plinths, POIs, camps, cliffs, ambience), Scatter (forest, flora, rocks), Lobby (the Tor),
	Audit (report, verify).

	EDIT-MODE USAGE (Studio caches required modules, so require a clone):
	  local P = require(game.ServerStorage.WorldGen.Populate:Clone())
	  P.start(opts?)          generate() on a background thread; returns at once. Progress: workspace.Arena attributes
	                          PopulateStatus / PopulateProgress, and PopulateLog when it is done.
	  P.generate(opts?)       every step below in order (yields in the caller); returns the log
	  P.placeCore()           Landmarks.Spire (with the Spire's 4 niche crate markers) and the 24 realistic Plinths
	  P.placePOIs()           POIs: cabin, watchtower, footbridge, gorge log, stepping stones, the 3 cave mouths and the
	                          natural landmarks (falls pool, island, overlook, giant oak, field boulder, dead stand)
	  P.placeCamps()          Camps: the 6 abandoned campsites (PropsReal kits)
	  P.placeCliffs()         Cliffs: CliffFace / RockOutcrop pieces on the escarpment, the gorge walls and the falls bowl
	  P.scatter(biome?)       Forest, Flora and Rocks from ArenaLayout.Scatter (every biome, or one)
	  P.buildLobby()          the Tor: the LandmarksReal lobby set and a realistic garden (spawns, barrier, board text kept)
	  P.ambience()            Ambience: AmbientEmitters (river, falls, frogs, wind, smouldering camp fires)
	  P.runnerCaches()        the 8 runner's-cache spots: ArenaLayout.RunnerCaches when published, else computed
	  P.report() -> string    models, parts, triangles, shadow casters and colliders per output folder
	  P.verify() -> string    gameplay-safety checks (see Populate.Audit)
	  P.looks() -> string     the look checks: eye-level cliff facets, scatter fill vs ArenaLayout densities, floating
	                          pieces in every folder, loot and runner's-cache clearings by bounding box
	Helpers every step shares (Ctx): seat(model) lowers a piece until its underside rests on the ground (sampled
	columns); lootClear(name, cf, scale) keeps loot clearings free by the whole bounding box; blocksTrail(model) probes
	a player-sized box at the trail samples near a piece; areaIn(biome) is a biome's area inside the play radius.
	opts: steps = { "core", "pois", "camps", "cliffs", "scatter", "lobby", "ambience" } (default: all, in that order)
	      density = multiplier on every scatter density (default Populate.DENSITY_SCALE)

	OUTPUTS (contracts other systems read)
	  workspace.Arena.Landmarks.Spire     at Center, unrotated, pivot (0, PlazaY, 0); its PrimaryPart carries CrateSlot_1..4
	                                      and Beacon. Child Parts CrateSlot_1..4 are LootSpawn markers (Tier 3, Kind Crate,
	                                      DropIn = false: the Offering restocks them in place instead of dropping a crate
	                                      through the Spire). Persistent streaming.
	  workspace.Arena.Plinths.PlinthNN    the realistic Plinth on SpirePlatform Plate_NN (= ArenaLayout.Plates[NN] + 0.6):
	                                      tag Plinth, Stand attachment, attributes Index and PlateOffset (0.6). Persistent.
	  workspace.Arena.Forest / Flora / Rocks / Cliffs / POIs / Camps   template clones: Atomic streaming, CanTouch off,
	                                      scatter copies drop the template attributes. Crown parts (Foliage, Branches,
	                                      Leaves) keep their names and CanQuery = false and trunks stay queryable (the Roll
	                                      Call's canopy lift); OakA_Bark keeps its Climbable tag. Past r 650 scenery is
	                                      visual only (no collision, no queries).
	  workspace.Arena.Ambience            AmbientEmitter parts (attribute SoundKey)
	  workspace.Lobby                     see Populate.Lobby
	  The scatter keeps clear: the plaza and plate ring (r < 70), the meadow core (r < 100; ground cover only), trails,
	  crossings, cave mouths, POI footprints, loot markers (crates 4.5, ground items 3 studs) and the RunnerCaches
	  (6 studs, plus a sightline toward the plates).
]]
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local function fresh(module: ModuleScript): any
	if not RunService:IsRunning() then
		local ok, result = pcall(function()
			return require(module:Clone())
		end)
		if ok and result ~= nil then
			return result
		end
	end
	return require(module)
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = fresh(Shared:WaitForChild("ArenaLayout"))
assert(Layout.Version == 2, "Populate v2 needs ArenaLayout v2")

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local V3 = Vector3.new

local Populate = {}
Populate.VERSION = 2
-- Global multiplier on every ArenaLayout.Scatter density: the performance knob (see docs/GameDesign.md section 11).
Populate.DENSITY_SCALE = 1
Populate.STEPS = { "core", "pois", "camps", "cliffs", "scatter", "lobby", "ambience" }

local Ctx = {}
Populate.Ctx = Ctx
Ctx.Layout = Layout
Ctx.Seed = Layout.Seed or 1337
Ctx.densityScale = Populate.DENSITY_SCALE
Ctx.placed = {}
Ctx.SOURCE = "Populate:v2"
Ctx.VISUAL_R = Layout.PlayRadius + 10 -- scenery beyond this radius is visual only (no collision, no queries)
Ctx.PLAY_R = Layout.PlayRadius

-------------------------------------------------------------------------------- yielding, status, folders
local lastYield = os.clock()
function Ctx.yield()
	if os.clock() - lastYield > 0.02 then
		task.wait()
		lastYield = os.clock()
	end
end

function Ctx.arena(): Instance
	local a = workspace:FindFirstChild("Arena")
	if not a then
		a = Instance.new("Folder")
		a.Name = "Arena"
		a.Parent = workspace
	end
	return a
end

function Ctx.status(text: string, progress: number?)
	local a = Ctx.arena()
	a:SetAttribute("PopulateStatus", text)
	if progress then
		a:SetAttribute("PopulateProgress", math.clamp(progress, 0, 1))
	end
end

function Ctx.folder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

function Ctx.out(name: string): Instance
	return Ctx.folder(Ctx.arena(), name)
end

-- Destroys a folder's children in batches. Only ever used on this module's own generated output.
function Ctx.clear(folder: Instance)
	for i, child in ipairs(folder:GetChildren()) do
		child:Destroy()
		if i % 150 == 0 then
			task.wait()
		end
	end
end

-- Moves v1 content into ServerStorage.Archive_v1.<archiveName>[.<sub>] (nothing from v1 is deleted).
function Ctx.archive(inst: Instance, archiveName: string, sub: string?): Instance
	local dest = Ctx.folder(Ctx.folder(ServerStorage, "Archive_v1"), archiveName)
	if sub then
		dest = Ctx.folder(dest, sub)
	end
	inst.Parent = dest
	return dest
end

-------------------------------------------------------------------------------- templates
local SETS = { "TreesReal", "GroundReal", "LandmarksReal", "BuildingsReal", "PropsReal" }
local templateCache = {}
local infoCache = {}

function Ctx.template(name: string): Model?
	local t = templateCache[name]
	if t and t.Parent then
		return t
	end
	local root = ServerStorage:FindFirstChild("MeshAssets")
	if not root then
		return nil
	end
	for _, set in ipairs(SETS) do
		local folder = root:FindFirstChild(set)
		local m = folder and folder:FindFirstChild(name)
		if m and m:IsA("Model") then
			templateCache[name] = m
			return m
		end
	end
	return nil
end

-- { bmin, bmax (Vector3, pivot space, scale 1), height, tris, parts } of a template
function Ctx.info(name: string)
	local i = infoCache[name]
	if i then
		return i
	end
	local t = Ctx.template(name)
	if not t then
		return nil
	end
	local bmin, bmax = t:GetAttribute("BoundsMin"), t:GetAttribute("BoundsMax")
	if typeof(bmin) ~= "Vector3" or typeof(bmax) ~= "Vector3" then
		local cf, size = t:GetBoundingBox()
		local c = t:GetPivot():PointToObjectSpace(cf.Position)
		bmin, bmax = c - size / 2, c + size / 2
	end
	local parts = 0
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	i = { bmin = bmin, bmax = bmax, height = bmax.Y, tris = tonumber(t:GetAttribute("Tris")) or 0, parts = parts }
	infoCache[name] = i
	return i
end

local ROOTS = "_Roots"

-- Clones template `name` with its pivot (base centre on the ground, front = LookVector) at `cf`. opts:
--   scale       uniform scale (Model:ScaleTo, about the pivot)
--   keep        keep the template's attributes (sites); scatter copies drop them (memory and replication)
--   streaming   Enum.ModelStreamingMode (default Atomic: a model streams in and out whole, no empty containers)
--   noShadow    no part casts a shadow; models under shadowMin (3 studs) never do; roots never do
--   visualOnly  no collision and no queries (scenery nobody can reach)
--   keepTouch   leave CanTouch as built (default: off; nothing in the game listens to Touched on scenery)
--   name        the clone's name (default: the template name)
function Ctx.spawn(name: string, cf: CFrame, parent: Instance?, opts: any?): Model?
	local t = Ctx.template(name)
	if not t then
		warn("[Populate] missing template " .. name)
		return nil
	end
	local o = opts or {}
	local m = t:Clone()
	local s = o.scale or 1
	if math.abs(s - 1) > 1e-3 then
		m:ScaleTo(s)
	end
	m:PivotTo(cf)
	m.ModelStreamingMode = o.streaming or Enum.ModelStreamingMode.Atomic
	if not o.keep then
		for key in pairs(m:GetAttributes()) do
			m:SetAttribute(key, nil)
		end
	end
	local info = Ctx.info(name)
	local small = info ~= nil and info.height * s < (o.shadowMin or 3)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if not o.keepTouch and not d:IsA("TrussPart") then
				d.CanTouch = false
			end
			if not o.keep then
				for key in pairs(d:GetAttributes()) do
					d:SetAttribute(key, nil)
				end
			end
			if small or o.noShadow or string.sub(d.Name, -#ROOTS) == ROOTS then
				d.CastShadow = false
			end
			if o.visualOnly then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
	end
	if o.name then
		m.Name = o.name
	end
	if parent then
		m.Parent = parent
	end
	Ctx.placed[name] = (Ctx.placed[name] or 0) + 1
	return m
end

-------------------------------------------------------------------------------- ground (terrain only)
local TOP = 1400
local DOWN = V3(0, -1800, 0)
local solidParams = RaycastParams.new()
solidParams.FilterType = Enum.RaycastFilterType.Include
solidParams.IgnoreWater = true
local wetParams = RaycastParams.new()
wetParams.FilterType = Enum.RaycastFilterType.Include
wetParams.IgnoreWater = false
local function refreshParams()
	solidParams.FilterDescendantsInstances = { workspace.Terrain }
	wetParams.FilterDescendantsInstances = { workspace.Terrain }
end
refreshParams()
Ctx.terrainParams = solidParams

-- (groundY, normal, material, waterY?, waterDepth) of the terrain under (x, z); placed models never count.
function Ctx.ground(x: number, z: number)
	local top = workspace:Raycast(V3(x, TOP, z), DOWN, wetParams)
	if not top then
		return nil
	end
	if top.Material == Enum.Material.Water then
		local bed = workspace:Raycast(top.Position, V3(0, -400, 0), solidParams)
		if not bed then
			return nil
		end
		return bed.Position.Y, bed.Normal, bed.Material, top.Position.Y, top.Position.Y - bed.Position.Y
	end
	return top.Position.Y, top.Normal, top.Material, nil, 0
end

-- top solid terrain height under (x, z) (water ignored)
function Ctx.height(x: number, z: number): number?
	local hit = workspace:Raycast(V3(x, TOP, z), DOWN, solidParams)
	return hit and hit.Position.Y
end

-- terrain height just under a point (for spots under an overhang or inside a cave)
function Ctx.heightBelow(p: Vector3, reach: number?): number?
	local hit = workspace:Raycast(p, V3(0, -(reach or 30), 0), solidParams)
	return hit and hit.Position.Y
end

-- a CFrame at pos whose UpVector is `up`, turned `yaw` radians about it
function Ctx.upFrame(pos: Vector3, up: Vector3, yaw: number): CFrame
	local u = up.Unit
	local axis = Vector3.yAxis:Cross(u)
	local base = CFrame.new(pos)
	if axis.Magnitude > 1e-5 then
		base = base * CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(u.Y, -1, 1)))
	end
	return base * CFrame.Angles(0, yaw, 0)
end

-------------------------------------------------------------------------------- spatial hash
local Hash = {}
Hash.__index = Hash
function Hash.new(cell: number)
	return setmetatable({ cell = cell, cells = {}, n = 0 }, Hash)
end
local function hkey(ix: number, iz: number): number
	return (ix + 8192) * 16384 + (iz + 8192)
end
function Hash:insert(item)
	local c = self.cell
	local k = hkey(floor(item.x / c), floor(item.z / c))
	local list = self.cells[k]
	if not list then
		list = {}
		self.cells[k] = list
	end
	table.insert(list, item)
	self.n += 1
end
-- fn(item) for the items in every cell touching the square of half size r around (x, z); true from fn stops it
function Hash:any(x: number, z: number, r: number, fn): boolean
	local c = self.cell
	for ix = floor((x - r) / c), floor((x + r) / c) do
		for iz = floor((z - r) / c), floor((z + r) / c) do
			local list = self.cells[hkey(ix, iz)]
			if list then
				for _, item in ipairs(list) do
					if fn(item) then
						return true
					end
				end
			end
		end
	end
	return false
end
Ctx.Hash = Hash

-------------------------------------------------------------------------------- biome and trail grids
local G0, GC, GN = -960, 8, 240 -- biome grid: 8-stud cells over [-960, 960)
local biomeIndex = {}
for i, b in ipairs(Layout.Biomes) do
	biomeIndex[b] = i
end
local biomeGrid: buffer? = nil
Ctx.biomeBounds = {}

function Ctx.buildBiomeGrid()
	if biomeGrid then
		return
	end
	local buf = buffer.create(GN * GN)
	local bounds = {}
	local playR2 = Layout.PlayRadius * Layout.PlayRadius
	for j = 0, GN - 1 do
		local z = G0 + (j + 0.5) * GC
		for i = 0, GN - 1 do
			local x = G0 + (i + 0.5) * GC
			if x * x + z * z < 940 * 940 then
				local b = Layout.getBiome(V3(x, 0, z))
				local v = biomeIndex[b] or 0
				buffer.writeu8(buf, j * GN + i, v)
				if v > 0 then
					local bb = bounds[b]
					if not bb then
						bb = { x0 = math.huge, z0 = math.huge, x1 = -math.huge, z1 = -math.huge, area = 0, areaIn = 0 }
						bounds[b] = bb
					end
					bb.x0, bb.x1 = min(bb.x0, x - GC / 2), max(bb.x1, x + GC / 2)
					bb.z0, bb.z1 = min(bb.z0, z - GC / 2), max(bb.z1, z + GC / 2)
					bb.area += GC * GC
					if x * x + z * z < playR2 then
						bb.areaIn += GC * GC -- inside the play radius: the area the scatter densities are measured on
					end
				end
			end
		end
		Ctx.yield()
	end
	biomeGrid = buf
	Ctx.biomeBounds = bounds
end

-- a biome's area inside the play radius (sq studs, 8-stud grid): density x areaIn / 1000 = the rule's target count
function Ctx.areaIn(biome: string): number
	Ctx.buildBiomeGrid()
	local bb = Ctx.biomeBounds[biome]
	return if bb then bb.areaIn else 0
end

-- the biome at (x, z): 8-stud grid (exact = true asks ArenaLayout.getBiome)
function Ctx.biomeAt(x: number, z: number, exact: boolean?): string?
	if exact or not biomeGrid then
		return Layout.getBiome(V3(x, 0, z))
	end
	local i, j = floor((x - G0) / GC), floor((z - G0) / GC)
	if i < 0 or j < 0 or i >= GN or j >= GN then
		return nil
	end
	local v = buffer.readu8(biomeGrid :: buffer, j * GN + i)
	return if v > 0 then Layout.Biomes[v] else nil
end

local T0, TC, TN = -960, 2, 960 -- trail grid: 2-stud cells, distance to the nearest trail centreline in 1/8 studs
local trailGrid: buffer? = nil
local TRAIL_RANGE = 14

function Ctx.buildTrailGrid()
	if trailGrid then
		return
	end
	local buf = buffer.create(TN * TN)
	buffer.fill(buf, 0, 255)
	for _, trail in ipairs(Layout.Trails) do
		for s = 1, #trail - 1 do
			local a, b = trail[s], trail[s + 1]
			local dx, dz = b.X - a.X, b.Z - a.Z
			local l2 = dx * dx + dz * dz
			local i0 = max(0, floor((min(a.X, b.X) - TRAIL_RANGE - T0) / TC))
			local i1 = min(TN - 1, floor((max(a.X, b.X) + TRAIL_RANGE - T0) / TC))
			local j0 = max(0, floor((min(a.Z, b.Z) - TRAIL_RANGE - T0) / TC))
			local j1 = min(TN - 1, floor((max(a.Z, b.Z) + TRAIL_RANGE - T0) / TC))
			for j = j0, j1 do
				local z = T0 + (j + 0.5) * TC
				for i = i0, i1 do
					local x = T0 + (i + 0.5) * TC
					local u = 0
					if l2 > 0 then
						u = math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / l2, 0, 1)
					end
					local qx, qz = x - (a.X + dx * u), z - (a.Z + dz * u)
					local v = min(254, floor(sqrt(qx * qx + qz * qz) * 8))
					local k = j * TN + i
					if v < buffer.readu8(buf, k) then
						buffer.writeu8(buf, k, v)
					end
				end
			end
		end
		Ctx.yield()
	end
	trailGrid = buf
end

-- flat distance to the nearest trail centreline: exact (ArenaLayout.distanceToTrail) within 8 studs of a trail,
-- grid-coarse (+-1.4) beyond, 31.9 when far
function Ctx.trailDistance(x: number, z: number): number
	if not trailGrid then
		return Layout.distanceToTrail(V3(x, 0, z))
	end
	local i, j = floor((x - T0) / TC), floor((z - T0) / TC)
	if i < 0 or j < 0 or i >= TN or j >= TN then
		return 99
	end
	local d = buffer.readu8(trailGrid :: buffer, j * TN + i) / 8
	if d < 8 then
		return Layout.distanceToTrail(V3(x, 0, z))
	end
	return d
end

-------------------------------------------------------------------------------- loot markers, runner caches, keep-outs
-- Every LootSpawn marker: ServerStorage.ArenaData.LootSpawns and tagged markers in the world (the Spire's niches).
function Ctx.lootMarkers(): { BasePart }
	local list, seen = {}, {}
	local ad = ServerStorage:FindFirstChild("ArenaData")
	local folder = ad and ad:FindFirstChild("LootSpawns")
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			local kind = d:GetAttribute("Kind")
			if d:IsA("BasePart") and (kind == "Crate" or kind == "Ground") then
				seen[d] = true
				table.insert(list, d)
			end
		end
	end
	for _, d in ipairs(CollectionService:GetTagged("LootSpawn")) do
		if not seen[d] and d:IsA("BasePart") and d:IsDescendantOf(workspace) then
			table.insert(list, d)
		end
	end
	return list
end

-- The 8 runner's caches (PlayabilityPlan QW7) as positions: ArenaLayout.RunnerCaches when it is published (the rules
-- owner's list: entries are Vector3s or { position | angle, r, groundY, landmark }), else one open spot per 45-degree
-- sector at r 150-200: inside the meadow or at its edge (in sight of the plates), flat over a 6-stud radius, off
-- trails and water, 14+ studs from any loot marker. Deterministic.
function Ctx.runnerCaches(): { Vector3 }
	if type(Layout.RunnerCaches) == "table" and #Layout.RunnerCaches > 0 then
		local list = {}
		for _, c in ipairs(Layout.RunnerCaches) do
			if typeof(c) == "Vector3" then
				table.insert(list, c)
			elseif type(c) == "table" then
				local p = c.position
				if typeof(p) ~= "Vector3" and c.angle and c.r then
					p = Layout.polar(c.angle, c.r, c.groundY or 0)
				end
				if typeof(p) == "Vector3" then
					table.insert(list, p)
				end
			end
		end
		if #list > 0 then
			return list
		end
	end
	if Ctx._caches then
		return Ctx._caches
	end
	local markers = {}
	for _, m in ipairs(Ctx.lootMarkers()) do
		table.insert(markers, m.Position)
	end
	local out = {}
	for k = 0, 7 do
		local best, bestScore = nil, -math.huge
		for a = k * 45 + 8, k * 45 + 37, 2 do
			local edge = Layout.meadowEdge(a)
			for r = 150, 200, 4 do
				local p = Layout.polar(a, r)
				local y, n, _, wy = Ctx.ground(p.X, p.Z)
				if y and not wy and n.Y > math.cos(math.rad(12)) then
					local biome = Layout.getBiome(p)
					local trail = Layout.distanceToTrail(p)
					if trail > 9 and (biome == "Meadow" or biome == "Forest") and Layout.distanceToWater(p) > 14 then
						local lo, hi = y, y
						for t = 0, 5 do
							local qy = Ctx.height(p.X + math.sin(t * math.pi / 3) * 6, p.Z + math.cos(t * math.pi / 3) * 6)
							if qy then
								lo, hi = min(lo, qy), max(hi, qy)
							end
						end
						local nearLoot = math.huge
						for _, q in ipairs(markers) do
							nearLoot = min(nearLoot, V3(q.X - p.X, 0, q.Z - p.Z).Magnitude)
						end
						if hi - lo < 2.5 and nearLoot > 14 then
							local inside = math.clamp((edge - 6 - r) / 10, -2, 1) -- in the open meadow: seen from the plates
							local mid = 1 - math.abs(a - (k * 45 + 22.5)) / 22.5 -- spread evenly
							local score = inside * 3 + mid * 1.5 - (hi - lo) * 0.6 - math.abs(r - 160) / 40 + min(trail, 24) / 48
							if score > bestScore then
								bestScore, best = score, V3(p.X, y, p.Z)
							end
						end
					end
				end
			end
			Ctx.yield()
		end
		if best then
			table.insert(out, V3(floor(best.X * 10 + 0.5) / 10, floor(best.Y * 10 + 0.5) / 10, floor(best.Z * 10 + 0.5) / 10))
		end
	end
	Ctx._caches = out
	return out
end

-- Keep-out circles: { x, z, r, cover = true when ground cover must stay out too, why }
Ctx.keepOut = Hash.new(16)
local KEEPOUT_MAX = 34 -- the largest keep-out radius (for the hash query)
function Ctx.addKeepOut(x: number, z: number, r: number, cover: boolean, why: string)
	Ctx.keepOut:insert({ x = x, z = z, r = min(r, KEEPOUT_MAX), cover = cover, why = why })
end

-- the reason a footprint of radius `rad` at (x, z) is kept out, or nil
function Ctx.keptOut(x: number, z: number, rad: number, isCover: boolean): string?
	local reason = nil
	Ctx.keepOut:any(x, z, rad + KEEPOUT_MAX, function(c)
		if isCover and not c.cover then
			return false
		end
		local dx, dz = c.x - x, c.z - z
		local lim = c.r + rad
		if dx * dx + dz * dz < lim * lim then
			reason = c.why
			return true
		end
		return false
	end)
	return reason
end

-- Loot markers alone (for the placed set pieces): { x, z, r = 4.5 for crates, 3 for ground items }
Ctx.lootHash = Hash.new(16)
-- true when a footprint of radius `rad` at (x, z) would sit on a loot marker's clearing
function Ctx.lootNear(x: number, z: number, rad: number): boolean
	return Ctx.lootHash:any(x, z, rad + 5, function(c)
		local dx, dz = c.x - x, c.z - z
		local lim = c.r + rad
		return dx * dx + dz * dz < lim * lim
	end)
end

-------------------------------------------------------------------------------- footprints, seating, clearances
-- The footprint of template `name` placed at cf with `scale`: its bounding box (template bounds) projected on the
-- ground, as a rectangle in a yaw-only frame: (frame, x0, x1, z0, z1). Exact for upright pieces, the projected box's
-- bounding rectangle for tilted ones.
function Ctx.footRect(name: string, cf: CFrame, scale: number?)
	local info = Ctx.info(name)
	if not info then
		return nil
	end
	local s = scale or 1
	local lv = cf.LookVector
	local fl = V3(lv.X, 0, lv.Z)
	if fl.Magnitude < 0.05 then
		fl = V3(cf.UpVector.X, 0, cf.UpVector.Z)
		if fl.Magnitude < 0.05 then
			fl = V3(0, 0, -1)
		end
	end
	local o = V3(cf.X, 0, cf.Z)
	local base = CFrame.lookAt(o, o + fl.Unit)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	local a, b = info.bmin * s, info.bmax * s
	for _, cx in ipairs({ a.X, b.X }) do
		for _, cy in ipairs({ a.Y, b.Y }) do
			for _, cz in ipairs({ a.Z, b.Z }) do
				local w = cf * V3(cx, cy, cz)
				local l = base:PointToObjectSpace(V3(w.X, 0, w.Z))
				x0, x1, z0, z1 = min(x0, l.X), max(x1, l.X), min(z0, l.Z), max(z1, l.Z)
			end
		end
	end
	return base, x0, x1, z0, z1
end

-- flat distance from (x, z) to a footprint rectangle (0 inside)
function Ctx.rectDistance(base: CFrame, x0: number, x1: number, z0: number, z1: number, x: number, z: number): number
	local l = base:PointToObjectSpace(V3(x, 0, z))
	local dx = max(x0 - l.X, 0, l.X - x1)
	local dz = max(z0 - l.Z, 0, l.Z - z1)
	return sqrt(dx * dx + dz * dz)
end

-- true when template `name` at cf / scale keeps every loot clearing (crates 4.5, ground items 3) and every runner's-
-- cache clearing (6) free by its whole bounding box (crowns, skirts and fronds included): loot stays in plain sight
function Ctx.lootClear(name: string, cf: CFrame, scale: number?, margin: number?): boolean
	local base, x0, x1, z0, z1 = Ctx.footRect(name, cf, scale)
	if not base then
		return true
	end
	local m = margin or 0.25
	local reach = max(-x0, x1, -z0, z1) + 6.5 + m
	return not Ctx.lootHash:any(cf.X, cf.Z, reach, function(c)
		return Ctx.rectDistance(base, x0, x1, z0, z1, c.x, c.z) < c.r + m
	end)
end

-- Air under a placed model: for a grid of columns over its bounding box, (the model's underside) - (the ground), with
-- rays up from below the model onto it (include filter) and down onto the terrain from above it (water ignored: a rock
-- in a pool rests on the bed). Columns where the model has no geometry are skipped. opts.region = "front" samples
-- only the front half (the LookVector side: cliff faces), opts.grid = columns per side (default 4).
local seatParams = RaycastParams.new()
seatParams.FilterType = Enum.RaycastFilterType.Include
function Ctx.gaps(m: Model, opts: any?): { number }
	local o = opts or {}
	local cf, size = m:GetBoundingBox()
	local n = o.grid or 4
	local yExt = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
	local bottom, top = cf.Y - yExt, cf.Y + yExt
	seatParams.FilterDescendantsInstances = { m }
	local gaps = {}
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local u, v = -1 + (i + 0.5) * 2 / n, -1 + (j + 0.5) * 2 / n
			if not (o.region == "front" and v > 0) then
				local w = cf * V3(u * size.X * 0.45, 0, v * size.Z * 0.45)
				local hit = workspace:Raycast(V3(w.X, bottom - 1, w.Z), V3(0, top - bottom + 2, 0), seatParams)
				if hit then
					local g = workspace:Raycast(V3(w.X, top + 1, w.Z), V3(0, -(top - bottom) - 60, 0), solidParams)
					if g then
						table.insert(gaps, hit.Position.Y - g.Position.Y)
					end
				end
			end
		end
	end
	return gaps
end

-- Lowers a placed model until `share` of its sampled columns rest on the ground (gap <= tol), by at most maxDrop.
-- Returns (drop, smallest gap after the drop or nil when nothing was sampled).
function Ctx.seat(m: Model, opts: any?): (number, number?)
	local o = opts or {}
	local share, tol, maxDrop = o.share or 0.5, o.tol or 0.25, o.maxDrop or 6
	local gaps = Ctx.gaps(m, o)
	if #gaps == 0 then
		return 0, nil
	end
	table.sort(gaps)
	local q = gaps[max(1, math.ceil(#gaps * share))]
	local drop = 0
	if q > tol then
		drop = min(q - tol * 0.5, maxDrop)
		m:PivotTo(m:GetPivot() - V3(0, drop, 0))
	end
	return drop, gaps[1] - drop
end

-- one reusable, invisible, unqueryable probe part (overlap tests on collision geometry)
local probeParams = OverlapParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Include
probeParams.RespectCanCollide = true
function Ctx.probePart(): Part
	local p = Ctx._probe
	if p and p.Parent then
		return p
	end
	p = Instance.new("Part")
	p.Name = "PopulateProbe"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = workspace
	Ctx._probe = p
	return p
end
function Ctx.releaseProbe()
	if Ctx._probe then
		Ctx._probe:Destroy()
		Ctx._probe = nil
	end
end

-- true when model m stands in a trail's walking space: an upright cylinder 5.6 wide (the trail's width: 2.8 to each
-- side of the centreline) and 3.6 tall, from 1 stud above the ground, at any trail sample (2 studs apart) within its
-- reach touches m's collision geometry
function Ctx.blocksTrail(m: Model): boolean
	if not Ctx.trailPts then
		return false
	end
	local cf, size = m:GetBoundingBox()
	local reach = sqrt(size.X * size.X + size.Z * size.Z) / 2 + 4
	local probe = Ctx.probePart()
	probe.Shape = Enum.PartType.Cylinder
	probe.Size = V3(3.6, 5.6, 5.6)
	probeParams.FilterDescendantsInstances = { m }
	return Ctx.trailPts:any(cf.X, cf.Z, reach, function(t)
		local dx, dz = t.x - cf.X, t.z - cf.Z
		if dx * dx + dz * dz > reach * reach then
			return false
		end
		local gy = Ctx.height(t.x, t.z)
		if not gy then
			return false
		end
		probe.CFrame = CFrame.new(t.x, gy + 2.8, t.z) * CFrame.Angles(0, 0, math.pi / 2)
		return #workspace:GetPartsInPart(probe, probeParams) > 0
	end)
end

-- true when model m's collision geometry reaches into a loot clearing (crates 4.5, ground items 3, runner's caches
-- 6; from the ground to 5 studs up): the precise test for big rock pieces whose bounding boxes are mostly buried
function Ctx.blocksLoot(m: Model): boolean
	local cf, size = m:GetBoundingBox()
	local reach = sqrt(size.X * size.X + size.Z * size.Z) / 2 + 6.5
	local probe = Ctx.probePart()
	probe.Shape = Enum.PartType.Cylinder
	probeParams.FilterDescendantsInstances = { m }
	return Ctx.lootHash:any(cf.X, cf.Z, reach, function(c)
		local gy = c.y or Ctx.height(c.x, c.z)
		if not gy then
			return false
		end
		probe.Size = V3(5, 2 * c.r, 2 * c.r)
		probe.CFrame = CFrame.new(c.x, gy + 2.7, c.z) * CFrame.Angles(0, 0, math.pi / 2)
		return #workspace:GetPartsInPart(probe, probeParams) > 0
	end)
end

-- true when model m closes the water a contender wades or drinks at: at every drinking point (Shared.WaterPoints,
-- QW10) within reach and, with streams = true, at every centreline sample of the river, the creek and the outflow
-- (the gorge floor stays a walkable stream), a player-sized box (2 x 3.6 x 2, from 1 stud above the bed) must fit
-- at the point or 1.5 / 3 studs to either side of it (across the stream). A piece may narrow a stream, never close it.
function Ctx.blocksWater(m: Model, streams: boolean?): boolean
	if not Ctx.waterPts then
		return false
	end
	local cf, size = m:GetBoundingBox()
	local reach = sqrt(size.X * size.X + size.Z * size.Z) / 2 + 2
	local probe = Ctx.probePart()
	probe.Shape = Enum.PartType.Block
	probe.Size = V3(2, 3.6, 2)
	probeParams.FilterDescendantsInstances = { m }
	return Ctx.waterPts:any(cf.X, cf.Z, reach, function(w)
		if w.stream and not streams then
			return false
		end
		local dx, dz = w.x - cf.X, w.z - cf.Z
		if dx * dx + dz * dz > reach * reach then
			return false
		end
		local across = if w.ax then V3(w.ax, 0, w.az) else V3(1, 0, 0)
		for _, off in ipairs({ 0, 1.5, -1.5, 3, -3 }) do
			local q = V3(w.x, 0, w.z) + across * off
			local bed = Ctx.heightBelow(V3(q.X, w.y + 4, q.Z), 40) or (w.y - 1)
			probe.CFrame = CFrame.new(q.X, bed + 2.8, q.Z)
			if #workspace:GetPartsInPart(probe, probeParams) == 0 then
				return false -- room to wade here
			end
		end
		return true
	end)
end

local prepared = false
-- Builds the grids and keep-outs every placement step uses (once per required copy of this module).
function Ctx.prepare()
	if prepared then
		return
	end
	Ctx.status("prepare: biome grid")
	Ctx.buildBiomeGrid()
	Ctx.status("prepare: trail grid")
	Ctx.buildTrailGrid()
	Ctx.status("prepare: keep-outs")
	local ko = Ctx.keepOut
	for _, m in ipairs(Ctx.lootMarkers()) do
		local crate = m:GetAttribute("Kind") == "Crate"
		Ctx.addKeepOut(m.Position.X, m.Position.Z, if crate then 4.5 else 3, true, "loot")
		local bottom = m.Position.Y - m.Size.Y / 2
		Ctx.lootHash:insert({ x = m.Position.X, z = m.Position.Z, r = if crate then 4.5 else 3, y = bottom })
	end
	-- the water contenders wade and drink at (Ctx.blocksWater): the drinking points and the stream centrelines
	Ctx.waterPts = Hash.new(16)
	local okWP, WP = pcall(function()
		return fresh(Shared:WaitForChild("WaterPoints", 2) :: ModuleScript)
	end)
	if okWP and type(WP) == "table" and type(WP.Points) == "table" then
		for _, p in ipairs(WP.Points) do
			Ctx.waterPts:insert({ x = p[1], y = p[2], z = p[3] })
		end
	end
	for _, ch in ipairs({ Layout.River, Layout.Creek, Layout.Outflow }) do
		if type(ch) == "table" and type(ch.samples) == "table" then
			local ss = ch.samples
			for i, s in ipairs(ss) do
				if not s.fall then
					-- across the flow, for the side-by-side wading boxes
					local a, b = ss[max(1, i - 1)], ss[min(#ss, i + 1)]
					local t = V3(b.x - a.x, 0, b.z - a.z)
					t = if t.Magnitude > 1e-3 then t.Unit else V3(0, 0, 1)
					Ctx.waterPts:insert({ x = s.x, y = s.y, z = s.z, stream = true, ax = -t.Z, az = t.X })
				end
			end
		end
	end
	-- trail samples every 2 studs (Ctx.blocksTrail)
	Ctx.trailPts = Hash.new(16)
	for _, trail in ipairs(Layout.Trails) do
		for s = 1, #trail - 1 do
			local a, b = trail[s], trail[s + 1]
			local n = max(1, math.ceil((b - a).Magnitude / 2))
			for k = 0, n - 1 do
				local p = a:Lerp(b, k / n)
				Ctx.trailPts:insert({ x = p.X, z = p.Z })
			end
		end
	end
	for _, c in ipairs(Ctx.runnerCaches()) do
		Ctx.addKeepOut(c.X, c.Z, 6, true, "runnerCache")
		-- the cache's 6-stud clearing counts as a loot clearing for every piece (bounding boxes included)
		Ctx.lootHash:insert({ x = c.X, z = c.Z, r = 6, cache = true })
		-- a sightline toward the plates: no trees, bushes or rocks on the radial line in from the cache
		local r = sqrt(c.X * c.X + c.Z * c.Z)
		local dir = V3(-c.X / r, 0, -c.Z / r)
		for d = 8, r - 95, 8 do
			Ctx.addKeepOut(c.X + dir.X * d, c.Z + dir.Z * d, 5, false, "cacheSightline")
		end
	end
	for _, cave in ipairs(Layout.Caves) do
		local m = cave.mouth
		Ctx.addKeepOut(m.X, m.Z, 12, true, "caveMouth")
		-- the approach to the mouth (a few studs out of the hill)
		local q = cave.path[2]
		local out = V3(m.X - q.X, 0, m.Z - q.Z)
		if out.Magnitude > 1e-3 then
			out = out.Unit
			Ctx.addKeepOut(m.X + out.X * 12, m.Z + out.Z * 12, 8, false, "caveApproach")
		end
	end
	for _, c in ipairs(Layout.Crossings) do
		local r = max(Layout.Exclusions.crossing, c.span * 0.6) + 2
		Ctx.addKeepOut(c.position.X, c.position.Z, r, false, "crossing")
		-- both landings
		local d = c.direction
		for _, s in ipairs({ -1, 1 }) do
			local e = c.position + d * (s * (c.span * 0.5 + 3))
			Ctx.addKeepOut(e.X, e.Z, 5, false, "crossing")
		end
	end
	for _, poi in ipairs(Layout.POIs) do
		if poi.kind ~= "Spire" then
			Ctx.addKeepOut(poi.position.X, poi.position.Z, poi.radius, false, "poi:" .. poi.name)
		end
	end
	prepared = true
	return ko
end

-------------------------------------------------------------------------------- steps
local function child(name: string)
	local m = script:FindFirstChild(name)
	assert(m, "[Populate] missing child module " .. name)
	return require(m)
end

local function run(label: string, fn, ...): string
	local t0 = os.clock()
	local ok, result = xpcall(fn, debug.traceback, ...)
	local line = string.format("%s: %s (%.1fs)", label, if ok then tostring(result) else ("FAILED " .. tostring(result)), os.clock() - t0)
	if not ok then
		warn("[Populate] " .. line)
	end
	return line
end

function Populate.placeCore(): string
	Ctx.prepare()
	return child("Sites").core(Ctx)
end

function Populate.placePOIs(): string
	Ctx.prepare()
	return child("Sites").pois(Ctx)
end

function Populate.placeCamps(): string
	Ctx.prepare()
	return child("Sites").camps(Ctx)
end

function Populate.placeCliffs(): string
	Ctx.prepare()
	return child("Sites").cliffs(Ctx)
end

function Populate.scatter(biome: string?): string
	Ctx.prepare()
	return child("Scatter").run(Ctx, biome)
end

function Populate.buildLobby(): string
	return child("Lobby").build(Ctx)
end

function Populate.ambience(): string
	Ctx.prepare()
	return child("Sites").ambience(Ctx)
end

function Populate.runnerCaches(): { Vector3 }
	return Ctx.runnerCaches()
end

function Populate.report(): string
	return child("Audit").report(Ctx)
end

function Populate.verify(): string
	Ctx.prepare()
	local ok, res = pcall(child("Audit").verify, Ctx)
	Ctx.releaseProbe()
	return if ok then res else ("verify FAILED: " .. tostring(res))
end

function Populate.looks(): string
	Ctx.prepare()
	local ok, res = pcall(child("Audit").looks, Ctx)
	Ctx.releaseProbe()
	return if ok then res else ("looks FAILED: " .. tostring(res))
end

-- Moves loot markers that scenery colliders block (inside a rock, a trunk, a wall) to the nearest clear, flat spot
-- with room to stand beside it. The Spire's niche markers and the runner's caches are never moved. Returns what moved.
function Populate.fixLoot(): string
	Ctx.prepare()
	return child("Audit").fixLoot(Ctx)
end

local STEP_FN = {
	core = Populate.placeCore,
	pois = Populate.placePOIs,
	camps = Populate.placeCamps,
	cliffs = Populate.placeCliffs,
	scatter = function()
		return Populate.scatter(nil)
	end,
	lobby = Populate.buildLobby,
	ambience = Populate.ambience,
}

function Populate.generate(opts: any?): string
	local o = opts or {}
	Ctx.densityScale = o.density or Populate.DENSITY_SCALE
	Ctx.placed = {}
	local steps = o.steps or Populate.STEPS
	local log = {}
	local t0 = os.clock()
	for i, step in ipairs(steps) do
		Ctx.status(step, (i - 1) / #steps)
		local fn = STEP_FN[step]
		if fn then
			table.insert(log, run(step, fn))
		else
			table.insert(log, step .. ": unknown step")
		end
	end
	Ctx.releaseProbe()
	Ctx.status("done", 1)
	table.insert(log, string.format("total %.1fs", os.clock() - t0))
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint("Populate v2")
	end)
	return table.concat(log, "\n")
end

function Populate.start(opts: any?): string
	Ctx.status("starting", 0)
	task.spawn(function()
		local log = Populate.generate(opts)
		Ctx.arena():SetAttribute("PopulateLog", log)
	end)
	return "Populate v2 started (watch workspace.Arena.PopulateStatus)"
end

return Populate
