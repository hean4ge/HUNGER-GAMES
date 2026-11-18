--[[
	Map1.Audit - the checks of docs/design/Map1Build.md section 6 that code can make, and the contract of its
	section 3 (the layout's fields, the instances, the one switch). STUDIO ONLY, Edit mode. It changes nothing.

	USE (execute_luau, Edit mode; require a clone)
	  local Audit = require(game.ServerStorage.WorldGen.Map1.Audit:Clone())
	  return Audit.run()                               -- every check; the report is one line per check
	  return Audit.run({ only = { "plinths", "loot" } })
	  opts.only / opts.skip   check names (below)
	  opts.layoutModule       the layout to audit (default ReplicatedStorage.Shared.ArenaLayout; before the install
	                          pass Shared.ArenaLayout_GreenLand)
	  opts.arena, opts.lootFolder, opts.waterPoints (a ModuleScript), opts.lobby   other roots than the place's own
	  opts.offset             Vector3: the map stands this far from the origin (a workbench copy)
	  opts.assumeTerrain, opts.terrainRadius, opts.terrainStride   for a part of the map written at a workbench: run the
	                          terrain check anyway, inside this radius, with a ray every terrainStride cells
	  opts.data, opts.config  a loaded Map1.Data / the Config table (else fresh copies)
	Returns (report: string, results: { { name, status, detail } }); status is "PASS", "FAIL", "SKIP" (the thing to
	check is not in the place yet) or "MANUAL". Audit.ok(results) is true when nothing failed.

	THE CHECKS
	  switch      Config.Map is "GreenLand"; the border, head count and wall of Config.Maps.GreenLand fit the layout
	              and the height data (the wall's top is over the ground on the start circle and over the peak)
	  layout      every field of Map1Build.md 3.1, its plates against the data pack's Layout, the functions
	  plinths     workspace.Arena.Plinths: exactly 48 models Plinth01..Plinth48 in ring order, a Stand attachment 1.6
	              over the turf, ground under each, nothing else in the folder
	  terrain     no holes (a ray finds ground under every sampled cell inside the Boundary) and heights against the
	              grid; water voxels in the wet cells; the banks hold the water
	  water       Shared.WaterPoints is Map 1's: every point is a wet cell of the data inside the start ring, and a
	              ray there meets real water (it can be drunk from)
	  loot        every marker: the attributes LootService reads, dry reachable ground, inside the full round's ring,
	              seated on the real floor; a tier-3 marker within SpireRefillRadius; DropIn = false under the sails;
	              the runner's caches; what each round size finds inside its start ring
	  boundary    workspace.Arena.Boundary stands all the way round at BoundaryRadius, solid, invisible, NoMantle
	  peak        nobody can walk in under the Peak's shell: no column on its rim has its underside more than 3 studs
	              over the ground (Map1.Terrain.fillUnder raises the ground there)
	  instances   the instances of Map1Build.md 3.2, and nothing of the forest arena left behind
	  lobby       spawns on the island at LobbyPosition, ground under it, clear of the arena's terrain
	  ambience    the AmbientEmitter parts and their SoundKeys
	  scripts     ServerStorage.Dev.SyntaxCheck over the whole place
	  leftovers   nothing left in the Edit data model by a test (the workbench, probes, test attributes)
	  manual      what only a playtest or a person can check
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local sin, cos, rad, deg = math.sin, math.cos, math.rad, math.deg

local Audit = {}
Audit.VERSION = 1
Audit.MAP = "GreenLand"
Audit.CHECKS = { "switch", "layout", "plinths", "terrain", "water", "loot", "boundary", "peak", "instances", "lobby",
	"ambience", "scripts", "leftovers", "manual" }

local function fresh(module: Instance): any
	return require(if RunService:IsRunning() then module else module:Clone() :: any)
end

local function map1Module(name: string): Instance?
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local folder = worldGen and worldGen:FindFirstChild("Map1")
	return folder and folder:FindFirstChild(name)
end

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

-- a list of problems that keeps its first few in full
local function Problems(limit: number?)
	local self = { count = 0, list = {} }
	function self.add(text: string)
		self.count += 1
		if #self.list < (limit or 6) then
			table.insert(self.list, text)
		end
	end
	function self.text(): string
		if self.count == 0 then
			return ""
		end
		local more = if self.count > #self.list then string.format(" (+%d more)", self.count - #self.list) else ""
		return table.concat(self.list, "; ") .. more
	end
	return self
end

----------------------------------------------------------------------------------------------------
-- the world
----------------------------------------------------------------------------------------------------
local function terrainParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	return params
end

-- the top of the Terrain under (x, z) in map space, or nil
local function terrainY(ctx: any, x: number, z: number, from: number?, length: number?): (number?, Vector3?)
	local top = from or 1400
	local hit = workspace:Raycast(Vector3.new(x, top, z) + ctx.offset, Vector3.new(0, -(length or 1600), 0), ctx.terrainParams)
	if hit then
		return hit.Position.Y - ctx.offset.Y, hit.Normal
	end
	return nil, nil
end

-- true / false: Water voxels in the column at the point; nil when the place has no terrain there at all
local function waterInWorld(ctx: any, x: number, y: number, z: number): boolean?
	local point = Vector3.new(x, y, z) + ctx.offset
	local region = Region3.new(point - Vector3.new(2, 6, 2), point + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials, occupancy = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok or not materials then
		return nil
	end
	local size = materials.Size
	local any = false
	for i = 1, size.X do
		for j = 1, size.Y do
			for k = 1, size.Z do
				local material = materials[i][j][k]
				if material == Enum.Material.Water and occupancy[i][j][k] > 0 then
					return true
				end
				if material ~= Enum.Material.Air then
					any = true
				end
			end
		end
	end
	if any then
		return false
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- the checks: each returns status, detail
----------------------------------------------------------------------------------------------------
local checks: { [string]: (ctx: any) -> (string, string) } = {}

function checks.switch(ctx)
	local C, L, G, value = ctx.config, ctx.layout, ctx.G, ctx.value
	local bad = Problems()
	if C.Map ~= Audit.MAP then
		bad.add(string.format("Config.Map is %q (the numbers below are Config.Maps.%s's)", tostring(C.Map), Audit.MAP))
	end
	if type(C.Maps) ~= "table" or type(C.Maps[Audit.MAP]) ~= "table" then
		return "FAIL", "Config.Maps." .. Audit.MAP .. " is missing"
	end
	local startRadius = value("Border", "StartRadius")
	local maxContenders = value("Round", "MaxContenders")
	if L then
		if L.Map ~= Audit.MAP then
			bad.add(string.format("the layout's Map is %q", tostring(L.Map)))
		end
		if startRadius ~= L.PlayRadius then
			bad.add(string.format("Border.StartRadius %s is not the layout's PlayRadius %s", tostring(startRadius), tostring(L.PlayRadius)))
		end
		if maxContenders ~= L.PlinthCount then
			bad.add(string.format("Round.MaxContenders %s is not the layout's PlinthCount %s", tostring(maxContenders), tostring(L.PlinthCount)))
		end
	end
	if value("Border", "FullContenders") ~= maxContenders then
		bad.add(string.format("Border.FullContenders %s is not Round.MaxContenders %s", tostring(value("Border", "FullContenders")), tostring(maxContenders)))
	end
	local solo = value("Border", "MinStartRadius")
	if not (type(solo) == "number" and solo < startRadius) then
		bad.add("Border.MinStartRadius is not under StartRadius")
	end
	-- the wall: its top over the ground on the start circle and over the peak; its panels close to the circle
	local base = (L and L.BaseHeight) or 46
	local wallTop = base - 110 + value("Border", "WallHeight")
	local highest = 0
	for b = 0, 359.75, 0.25 do
		local x, z = polar(b, startRadius)
		highest = max(highest, G.heightAt(x, z))
	end
	local summit = 0
	for _, item in ipairs(ctx.data.layout().items or {}) do
		local y = tonumber(string.match(tostring(item.note or ""), "summit y (%d+)"))
		if y then
			summit = max(summit, y)
		end
	end
	if wallTop < max(highest, summit) + 20 then
		bad.add(string.format("the wall's top (y %.0f) is not 20 over the start circle's ground (%.0f) and the peak (%.0f)", wallTop, highest, summit))
	end
	local panels = value("Border", "WallPanels")
	local corner = startRadius * (1 / cos(math.pi / panels) - 1)
	if corner > 0.5 then
		bad.add(string.format("with %d panels the wall's corners stand %.2f studs outside the circle", panels, corner))
	end
	-- the shrink: a full ring at MaxShrinkSpeed
	local speed = value("Border", "MaxShrinkSpeed")
	local closeAt = value("Border", "ShrinkStartTime") + value("Border", "ShrinkDuration")
	local firstMove = value("Border", "ShrinkStartTime")
	if type(speed) == "number" and speed > 0 then
		firstMove = math.clamp(closeAt - (startRadius - value("Border", "FinalRadius") + 100) / speed, 0, firstMove)
		if firstMove < 60 then
			bad.add(string.format("a full ring would have to start closing %.0f s into the round to keep to %.1f studs/s", firstMove, speed))
		end
	else
		bad.add("Border.MaxShrinkSpeed is not set: the ring would close at "
			.. string.format("%.1f studs/s", (startRadius - value("Border", "FinalRadius")) / value("Border", "ShrinkDuration")))
	end
	local detail = string.format("Config.Map %s; %d contenders; ring %d (lone %s) to %d, first moving at %.0f s for a full round; wall top y %.0f over ground %.0f and peak %.0f; %d panels (corners %.2f out)",
		tostring(C.Map), maxContenders, startRadius, tostring(solo), value("Border", "FinalRadius"), firstMove, wallTop, highest, summit, panels, corner)
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.layout(ctx)
	local L = ctx.layout
	if not L then
		return "FAIL", "the layout did not load: " .. tostring(ctx.layoutError)
	end
	local bad = Problems(10)
	local function expect(name: string, got: any, want: any)
		if typeof(got) == "Vector3" and typeof(want) == "Vector3" then
			if (got - want).Magnitude > 0.01 then
				bad.add(string.format("%s is %s, not %s", name, tostring(got), tostring(want)))
			end
		elseif type(got) == "number" and type(want) == "number" then
			if abs(got - want) > 1e-6 then
				bad.add(string.format("%s is %s, not %s", name, tostring(got), tostring(want)))
			end
		elseif got ~= want then
			bad.add(string.format("%s is %s, not %s", name, tostring(got), tostring(want)))
		end
	end
	local terrain = ctx.data.terrain()
	local jl = ctx.data.layout()
	expect("Version", L.Version, 3)
	expect("Map", L.Map, Audit.MAP)
	expect("Center", L.Center, Vector3.new(0, 0, 0))
	expect("BaseHeight", L.BaseHeight, terrain.plaza.knollY)
	expect("RingHeight", L.RingHeight, terrain.plaza.plinthRingY)
	expect("PlayRadius", L.PlayRadius, terrain.radii.play)
	expect("BoundaryRadius", L.BoundaryRadius, terrain.radii.boundary)
	expect("TerrainRadius", L.TerrainRadius, terrain.radii.terrainTo)
	expect("PlinthRingRadius", L.PlinthRingRadius, terrain.radii.plinthRing)
	expect("PlinthCount", L.PlinthCount, terrain.plaza.plinths)
	expect("PlinthOffsetDeg", L.PlinthOffsetDeg, terrain.plaza.plinthOffset)
	expect("LobbyPosition", L.LobbyPosition, Vector3.new(8800, 160, 0))
	expect("WaterLevel", L.WaterLevel, terrain.lake.level)
	-- the plates against the export
	local plates = L.Plates
	local exported = {}
	for _, item in ipairs(jl.items or {}) do
		if item.asset == "M1_Plinth" then
			exported[(item.index or 0) + 1] = item
		end
	end
	if type(plates) ~= "table" or #plates ~= L.PlinthCount then
		bad.add(string.format("Plates has %s entries, not %s", tostring(type(plates) == "table" and #plates), tostring(L.PlinthCount)))
	else
		local step = 360 / #plates
		for i, plate in ipairs(plates) do
			local p, s = plate.position, plate.stand
			if typeof(p) ~= "Vector3" or typeof(s) ~= "Vector3" or type(plate.bearing) ~= "number" then
				bad.add(string.format("Plates[%d] lacks position, stand or bearing", i))
			else
				local want = (L.PlinthOffsetDeg or 0) + (i - 1) * step
				if angleBetween(plate.bearing, want) > 0.01 or angleBetween(bearingOf(p.X, p.Z), want) > 0.05 then
					bad.add(string.format("Plates[%d] stands at bearing %.2f, not %.2f", i, bearingOf(p.X, p.Z), want))
				end
				if abs(sqrt(p.X * p.X + p.Z * p.Z) - L.PlinthRingRadius) > 0.05 then
					bad.add(string.format("Plates[%d] is %.2f from the centre", i, sqrt(p.X * p.X + p.Z * p.Z)))
				end
				if abs((s.Y - p.Y) - 1.6) > 0.01 then
					bad.add(string.format("Plates[%d]'s stand point is %.2f over its turf, not 1.6", i, s.Y - p.Y))
				end
				local e = exported[i]
				if e and (Vector3.new(e.position[1], e.position[2], e.position[3]) - p).Magnitude > 0.01 then
					bad.add(string.format("Plates[%d] is not the export's plinth %d", i, i - 1))
				end
			end
		end
	end
	-- where the Last Stand closes (ArenaService's rule)
	local gap = ctx.value("Border", "FinalSpireGap") or { 15, 25 }
	local low, high
	local mouths = type(L.Heart) == "table" and L.Heart.mouths
	if type(L.LastStandPoints) == "table" and #L.LastStandPoints > 0 then
		low, high = math.huge, 0
		for _, p in ipairs(L.LastStandPoints) do
			local d = sqrt(p.X * p.X + p.Z * p.Z)
			low, high = min(low, d), max(high, d)
		end
	elseif type(mouths) == "table" and #mouths > 0 then
		low, high = 90, 100
		for _, mouth in ipairs(mouths) do
			if type(mouth.bearing) ~= "number" then
				bad.add("a Heart.mouths entry has no bearing")
			end
		end
	else
		local spireR = (L.AssetInfo and L.AssetInfo.Spire and L.AssetInfo.Spire.r) or 20
		local cap = (L.PlazaRadius or 62) - 6
		low, high = min(cap, spireR + gap[1]), min(cap, spireR + gap[2])
	end
	if low < 90 - 1e-6 or high > 100 + 1e-6 then
		bad.add(string.format("the Last Stand closes %.0f to %.0f studs out, not 90 to 100", low, high))
	end
	-- no marsh for the mist
	for _, sector in ipairs(L.Sectors or {}) do
		if sector.name == "Marsh" or sector.name == "Swamp" then
			bad.add("Sectors has a " .. sector.name)
		end
	end
	if L.Marsh ~= nil then
		bad.add("the layout has a Marsh table")
	end
	if type(L.Lake) ~= "table" or type(L.Lake.level) ~= "number" or typeof(L.Lake.center) ~= "Vector3" or type(L.Lake.radiusX) ~= "number" then
		bad.add("Lake lacks level, center or radiusX")
	end
	for _, name in ipairs({ "Heart", "Sites", "Trails", "Stream", "Edge" }) do
		if type(L[name]) ~= "table" then
			bad.add(name .. " is missing")
		end
	end
	-- the functions
	for _, name in ipairs({ "polar", "flatDistance", "getBiome", "heightAt" }) do
		if type(L[name]) ~= "function" then
			bad.add(name .. " is not a function")
		end
	end
	local biomes = {}
	if bad.count == 0 or type(L.getBiome) == "function" then
		local ok, err = pcall(function()
			expect("polar(90, 10, 2)", L.polar(90, 10, 2), Vector3.new(10, 2, 0))
			expect("flatDistance((3, 9, 4))", L.flatDistance(Vector3.new(3, 9, 4)), 5)
			local known = { Meadow = true, Forest = true, Lake = true, Cliffs = true, Field = true, Mountains = true, Lobby = true }
			local samples = {
				{ "the centre", Vector3.new(0, 50, 0) }, { "the lake", L.Lake and L.Lake.center or Vector3.new(0, 34, 925) },
				{ "the lobby", L.LobbyPosition }, { "the north wood", Vector3.new(0, 200, -1000) },
				{ "past the terrain", Vector3.new(4000, 0, 4000) }, { "the east ridge", Vector3.new(1400, 300, 0) },
			}
			for _, sample in ipairs(samples) do
				local biome = L.getBiome(sample[2])
				table.insert(biomes, sample[1] .. " " .. tostring(biome))
				if not known[biome] then
					bad.add(string.format("getBiome at %s gives %q, a name the ambience does not know", sample[1], tostring(biome)))
				end
			end
			if L.getBiome(L.LobbyPosition) ~= "Lobby" then
				bad.add("getBiome at LobbyPosition is not Lobby")
			end
			-- it must never error, whatever it is given
			for _, odd in ipairs({ Vector3.new(0 / 0, 0, 0), Vector3.new(1e9, 0, -1e9) }) do
				L.getBiome(odd)
			end
			local h = L.heightAt(0, 0)
			if h ~= nil and type(h) ~= "number" then
				bad.add("heightAt(0, 0) is not a number or nil")
			end
		end)
		if not ok then
			bad.add("a layout function errored: " .. tostring(err))
		end
	end
	local detail = string.format("Version %s, %s plates, Last Stand %.0f to %.0f studs out, biomes: %s", tostring(L.Version),
		tostring(type(plates) == "table" and #plates), low, high, table.concat(biomes, ", "))
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.plinths(ctx)
	local L = ctx.layout
	local folder = ctx.arena and ctx.arena:FindFirstChild("Plinths")
	if not folder then
		return "FAIL", "workspace.Arena.Plinths is missing"
	end
	local count = (L and L.PlinthCount) or 48
	local ring = (L and L.PlinthRingRadius) or 150
	local first = (L and L.PlinthOffsetDeg) or 0
	local step = 360 / count
	local children = folder:GetChildren()
	local bad = Problems(8)
	if #children ~= count then
		bad.add(string.format("%d children, not %d", #children, count))
	end
	local byName = {}
	for _, child in ipairs(children) do
		if not child:IsA("Model") then
			bad.add(child.Name .. " is a " .. child.ClassName .. " (LaunchController would raise it as a plate)")
		elseif not string.match(child.Name, "^Plinth%d%d$") then
			bad.add(child.Name .. " is not named PlinthNN")
		else
			byName[child.Name] = child
		end
	end
	-- the order RoundService uses: by name
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	params.IgnoreWater = true
	local seen, staysUp, grounded, worstTurf = 0, 0, 0, 0
	for i = 1, count do
		local name = string.format("Plinth%02d", i)
		local plinth = byName[name]
		if not plinth then
			bad.add(name .. " is missing")
		else
			seen += 1
			if children[i] ~= plinth then
				bad.add(name .. " is not child " .. i .. " in name order")
			end
			local stand: Attachment? = nil
			for _, d in ipairs(plinth:GetDescendants()) do
				if d:IsA("Attachment") and d.Name == "Stand" then
					stand = d
					break
				end
			end
			if not stand then
				bad.add(name .. " has no Stand attachment")
			else
				local p = stand.WorldPosition - ctx.offset
				local want = first + (i - 1) * step
				local r = sqrt(p.X * p.X + p.Z * p.Z)
				if angleBetween(bearingOf(p.X, p.Z), want) > 0.2 or abs(r - ring) > 0.5 then
					bad.add(string.format("%s stands at bearing %.2f, r %.1f (wanted %.2f, %.0f)", name, bearingOf(p.X, p.Z), r, want, ring))
				end
				local plate = L and L.Plates and L.Plates[i]
				if plate and typeof(plate.stand) == "Vector3" and (plate.stand - p).Magnitude > 0.3 then
					bad.add(string.format("%s's stand point is %.2f from the layout's", name, (plate.stand - p).Magnitude))
				end
				-- ground under it, and the stand point 1.6 over the turf
				local ty = terrainY(ctx, p.X, p.Z, p.Y + 6, 40)
				if ty then
					grounded += 1
					local over = p.Y - ty
					worstTurf = max(worstTurf, abs(over - 1.6))
					if abs(over - 1.6) > 0.5 then
						bad.add(string.format("%s's stand point is %.2f over the turf, not 1.6", name, over))
					end
				elseif ctx.terrainHere then
					bad.add(name .. " has no ground under it")
				end
				-- LaunchController.tubeDepth: free space under the plate; under 2.5 studs it stays up (no bore, decision 6)
				local _, size = plinth:GetBoundingBox()
				local cf = plinth:GetBoundingBox()
				local bottom = cf.Position.Y - size.Y / 2
				local hit = workspace:Raycast(stand.WorldPosition + Vector3.new(0, 0.5, 0), Vector3.new(0, -40, 0), params)
				local thickness = math.clamp(stand.WorldPosition.Y - bottom, 0, 4)
				local free = if hit then (stand.WorldPosition.Y - hit.Position.Y) - thickness else 0
				if free < 2.5 then
					staysUp += 1
				end
			end
		end
	end
	local detail = string.format("%d of %d plinths found; ground under %d; stand points within %.2f of 1.6 over the turf; %d stay up at the launch (no bore), %d would sink",
		seen, count, grounded, worstTurf, staysUp, seen - staysUp)
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	if grounded == 0 then
		return "SKIP", "no terrain under the plinths yet | " .. detail
	end
	return "PASS", detail
end

function checks.terrain(ctx)
	if not ctx.terrainHere then
		return "SKIP", "Map 1's terrain is not in the place (no ground at the centre, or not at the data's height)"
	end
	local G, data = ctx.G, ctx.data
	local L = ctx.layout
	local limit = tonumber(ctx.opts.terrainRadius) or (L and L.BoundaryRadius) or 1900
	local stride = tonumber(ctx.opts.terrainStride) or 8 -- every 8th cell each way: a ray every 32 studs
	local n = G.N
	local samples, holes, off = 0, 0, 0
	local worst = Problems(5)
	local sum, most = 0, 0
	-- under the Peak's shell the ground is raised to the mesh on purpose (Map1.Terrain.fillUnder): not the grid's height
	local landmarks = ctx.arena and ctx.arena:FindFirstChild("Landmarks")
	local peak = landmarks and landmarks:FindFirstChild("Peak")
	local peakParams = RaycastParams.new()
	peakParams.FilterType = Enum.RaycastFilterType.Include
	peakParams.FilterDescendantsInstances = { peak }
	local underPeak = 0
	for row = stride // 2, n - 1, stride do
		for col = stride // 2, n - 1, stride do
			local x, z = G.centre(col, row)
			if peak and x * x + z * z <= limit * limit
				and workspace:Raycast(Vector3.new(x, 1400, z) + ctx.offset, Vector3.new(0, -1600, 0), peakParams) then
				underPeak += 1
			elseif x * x + z * z <= limit * limit then
				samples += 1
				local want = G.height(col, row)
				local got = terrainY(ctx, x, z, want + 60, 140)
				if not got then
					holes += 1
					worst.add(string.format("no ground at (%.0f, %.0f), data y %.1f", x, z, want))
				else
					local diff = abs(got - want)
					sum += diff
					most = max(most, diff)
					-- smooth terrain rounds a slope: the steeper the ground, the further the surface may sit from a cell's height
					local tolerance = 2.5 + 2.8 * math.tan(rad(min(G.slope(col, row), 80)))
					if diff > tolerance then
						off += 1
						worst.add(string.format("(%.0f, %.0f) is at %.1f, data %.1f", x, z, got, want))
					end
				end
			end
		end
		if row % 64 == stride // 2 then
			task.wait()
		end
	end
	-- water: voxels in the wet cells, and banks that hold it
	local wet, missing, banks, leaks = 0, 0, 0, 0
	for row = 1, n - 2 do
		for col = 1, n - 2 do
			local level = data.waterLevel(col, row)
			local x, z = G.centre(col, row)
			if level and (row + col) % 3 == 0 and x * x + z * z <= limit * limit then
				wet += 1
				if waterInWorld(ctx, x, level - 0.5, z) ~= true then
					missing += 1
					worst.add(string.format("no water voxel at (%.0f, %.1f, %.0f)", x, level, z))
				end
				for dr = -1, 1 do
					for dc = -1, 1 do
						if (dr ~= 0 or dc ~= 0) and not G.wet(col + dc, row + dr) then
							banks += 1
							local bx, bz = G.centre(col + dc, row + dr)
							local by = terrainY(ctx, bx, bz, level + 30, 80)
							if by and by < level - 0.75 then
								leaks += 1
								worst.add(string.format("the bank at (%.0f, %.0f) is at %.1f, under the water at %.1f", bx, bz, by, level))
							end
						end
					end
				end
			end
		end
	end
	local detail = string.format("%d rays inside r %d: %d holes, %d off the grid (mean %.2f, worst %.1f studs); %d more under the Peak not compared; %d wet cells sampled: %d without water; %d bank cells: %d under their water",
		samples, limit, holes, off, if samples > holes then sum / (samples - holes) else 0, most, underPeak, wet, missing, banks, leaks)
	-- a hole anywhere fails; the other three allow for smooth terrain rounding a few cells (1 or 2 in a hundred)
	if holes > 0 or off > samples * 0.01 or missing > wet * 0.02 or leaks > banks * 0.01 then
		return "FAIL", worst.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.water(ctx)
	local module = ctx.opts.waterPoints or ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("WaterPoints")
	if not module then
		return "FAIL", "Shared.WaterPoints is missing"
	end
	local ok, WaterPoints = pcall(fresh, module)
	if not ok or type(WaterPoints) ~= "table" or type(WaterPoints.Points) ~= "table" or type(WaterPoints.nearest) ~= "function" then
		return "FAIL", "Shared.WaterPoints did not load as { Points, nearest }: " .. tostring(WaterPoints)
	end
	local G, data = ctx.G, ctx.data
	local limit = ctx.value("Border", "StartRadius")
	local bad = Problems()
	local kinds: { [string]: number } = {}
	local drinkable, undrinkable, unknown = 0, 0, 0
	local waterParams = RaycastParams.new()
	waterParams.FilterType = Enum.RaycastFilterType.Include
	waterParams.FilterDescendantsInstances = { workspace.Terrain }
	waterParams.IgnoreWater = false
	for i, p in ipairs(WaterPoints.Points) do
		local x, y, z, kind = p[1], p[2], p[3], p[4]
		kinds[tostring(kind)] = (kinds[tostring(kind)] or 0) + 1
		if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(kind) ~= "string" then
			bad.add(string.format("point %d is not { x, waterY, z, kind }", i))
		else
			if x * x + z * z > limit * limit then
				bad.add(string.format("point %d is outside the start ring (r %.0f)", i, sqrt(x * x + z * z)))
			end
			local col, row = G.cellAt(x, z)
			local level = data.waterLevel(col, row)
			if not level then
				bad.add(string.format("point %d (%.0f, %.0f) is not on a wet cell of the data: another arena's water?", i, x, z))
			elseif abs(level - y) > 0.6 then
				bad.add(string.format("point %d's level is %.1f, the data's %.1f", i, y, level))
			end
			-- can it be drunk from: a ray down meets Water (InventoryService's own test is a ray from the head)
			local hit = workspace:Raycast(Vector3.new(x, y + 5, z) + ctx.offset, Vector3.new(0, -12, 0), waterParams)
			if hit and hit.Material == Enum.Material.Water then
				drinkable += 1
			elseif hit or waterInWorld(ctx, x, y - 0.5, z) == false then
				undrinkable += 1
				bad.add(string.format("no water to drink at point %d (%.0f, %.1f, %.0f)", i, x, y, z))
			else
				unknown += 1
			end
		end
	end
	local point, distance = WaterPoints.nearest(Vector3.new(0, 50, 0))
	local list = {}
	for kind, count in pairs(kinds) do
		table.insert(list, kind .. " " .. count)
	end
	table.sort(list)
	local detail = string.format("%d points (%s); nearest to the centre %.0f studs; %d with real water under a ray, %d without, %d not checkable (no terrain there)",
		#WaterPoints.Points, table.concat(list, ", "), if point then distance else -1, drinkable, undrinkable, unknown)
	if #WaterPoints.Points == 0 then
		return "FAIL", "no points | " .. detail
	end
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	if drinkable == 0 then
		return "SKIP", "the points fit the data; no terrain to drink from yet | " .. detail
	end
	return "PASS", detail
end

function checks.loot(ctx)
	local folder = ctx.opts.lootFolder
	if not folder then
		local arenaData = ServerStorage:FindFirstChild("ArenaData")
		folder = arenaData and arenaData:FindFirstChild("LootSpawns")
	end
	if not folder then
		return "FAIL", "ServerStorage.ArenaData.LootSpawns is missing"
	end
	local G, data, value, Loot = ctx.G, ctx.data, ctx.value, ctx.Loot
	local heart = data.layout().heart
	local startRadius = value("Border", "StartRadius")
	local margin = tonumber(value("Loot", "BorderMargin")) or -10
	local lootLimit = startRadius + margin
	local refill = tonumber(value("Loot", "SpireRefillRadius")) or 90
	local dropHeight = tonumber(value("Loot", "FeastDropHeight")) or 55
	local spacing = tonumber(value("Loot", "CrateSpacing")) or 5
	local crateMean = ((tonumber(value("Loot", "CrateItemsMin")) or 2) + (tonumber(value("Loot", "CrateItemsMax")) or 4)) / 2
	local chance = tonumber(value("Loot", "GroundSpawnChance")) or 0.65
	local maxContenders = value("Round", "MaxContenders")
	local perHead = tonumber((value("Loot", "Plan") or {}).ItemsPerContender) or 10
	local bad = Problems(8)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	params.IgnoreWater = false
	params.RespectCanCollide = true
	local markers = {}
	local foreign, seated, floating, unseated = 0, 0, 0, 0
	for _, part in ipairs(folder:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Kind") ~= nil then
			local kind, tier = part:GetAttribute("Kind"), part:GetAttribute("Tier")
			local source = part:GetAttribute("Source")
			local p = part.Position - ctx.offset
			local bottom = p.Y - part.Size.Y / 2
			local r = sqrt(p.X * p.X + p.Z * p.Z)
			local label = string.format("%s (%s) at (%.0f, %.0f)", part.Name, tostring(source), p.X, p.Z)
			if not Loot.ownMarker(part) then
				foreign += 1
			end
			if kind ~= "Crate" and kind ~= "Ground" then
				bad.add(label .. ": Kind is " .. tostring(kind))
			end
			if tier ~= 1 and tier ~= 2 and tier ~= 3 then
				bad.add(label .. ": Tier is " .. tostring(tier))
			end
			local runner, dropIn = part:GetAttribute("Runner"), part:GetAttribute("DropIn")
			if runner ~= nil and runner ~= true then
				bad.add(label .. ": Runner is " .. tostring(runner))
			end
			if dropIn ~= nil and dropIn ~= false then
				bad.add(label .. ": DropIn is " .. tostring(dropIn))
			end
			if r > lootLimit then
				bad.add(string.format("%s: r %.0f is outside the full round's loot limit %d", label, r, lootLimit))
			end
			local col, row = G.cellAt(p.X, p.Z)
			if not G.reachable(col, row) then
				bad.add(label .. ": the ground there cannot be walked to from the Horn")
			end
			if G.wet(col, row) then
				bad.add(label .. ": in water")
			end
			-- on the Horn's meshes the floor is the deck or the horn's floor, not the height grid
			local onMesh = r < 50 and (abs(bottom - heart.deckY) < 0.6 or abs(bottom - heart.horn.floorY) < 0.6)
			if not onMesh and abs(bottom - G.heightAt(p.X, p.Z)) > 4 then
				bad.add(string.format("%s: its floor (y %.1f) is %.1f from the data's ground", label, bottom, bottom - G.heightAt(p.X, p.Z)))
			end
			-- the real floor, by LootService's own rays (a crate: 2 above the bottom face, 6 down; an item: 1.5 above, 80 down)
			local from, down = if kind == "Crate" then 2 else 1.5, if kind == "Crate" then 6 else 80
			local hit = workspace:Raycast(Vector3.new(p.X, bottom + from, p.Z) + ctx.offset, Vector3.new(0, -down, 0), params)
			if hit then
				seated += 1
				if kind == "Ground" and bottom - (hit.Position.Y - ctx.offset.Y) > 4 then
					floating += 1
					bad.add(string.format("%s: the floor is %.1f under the marker", label, bottom - (hit.Position.Y - ctx.offset.Y)))
				end
			else
				unseated += 1
				if ctx.terrainHere then
					bad.add(label .. ": LootService's ray finds no floor (the crate would stand in the air or in the ground)")
				end
			end
			table.insert(markers, { part = part, kind = kind, tier = tier, runner = runner == true, dropIn = dropIn, x = p.X, z = p.Z, r = r, bottom = bottom, label = label })
		end
	end
	if #markers == 0 then
		return "FAIL", "no markers in " .. folder:GetFullName()
	end
	if foreign > 0 then
		bad.add(string.format("%d markers were not made by Map1.Loot (the forest arena's?)", foreign))
	end
	-- the Feast: a tier-3 marker near the centre; nothing dropped through the Horn
	local tier3, restocked, dropped = 0, 0, 0
	for _, m in ipairs(markers) do
		if m.tier == 3 and m.r <= refill then
			tier3 += 1
			if m.kind == "Crate" then
				local inside = Loot.insideBy(m.x, m.z, heart.horn.floorTriangle) > 0
				local top = Vector3.new(m.x, m.bottom + dropHeight + 2, m.z) + ctx.offset
				local over = workspace:Raycast(top, Vector3.new(0, -(dropHeight - 3), 0), params)
				if m.dropIn == false then
					restocked += 1
				else
					dropped += 1
					if inside then
						bad.add(m.label .. ": inside the Horn but DropIn is not false (the Feast would drop it through the sails)")
					elseif over then
						bad.add(m.label .. ": something solid is over it within FeastDropHeight but DropIn is not false")
					end
				end
			end
		end
	end
	if tier3 == 0 then
		bad.add(string.format("no tier-3 marker within %d of the centre: the Feast restocks nothing", refill))
	end
	-- the runner's caches
	local sites = 0
	for _, site in ipairs(data.layout().sites.items) do
		if string.sub(site.id, 1, 1) == "F" then
			sites += 1
		end
	end
	local runners = 0
	local soloLimit = Loot.startRadiusFor(ctx.config, 1) + margin
	for _, m in ipairs(markers) do
		if m.runner then
			runners += 1
			if m.kind ~= "Crate" then
				bad.add(m.label .. ": a runner's cache must be a Crate")
			end
			if m.r > soloLimit then
				bad.add(string.format("%s: outside a lone contender's ring (r %.0f > %d)", m.label, m.r, soloLimit))
			end
			local look = m.part.CFrame.LookVector
			local toCentre = Vector3.new(-m.x, 0, -m.z)
			if toCentre.Magnitude > 1 and look:Dot(toCentre.Unit) < 0.9 then
				bad.add(m.label .. ": its front (and its flag) does not face the Horn")
			end
		end
	end
	if runners ~= sites then
		bad.add(string.format("%d runner's caches for %d flag sites", runners, sites))
	end
	-- crates closer than LootService lets them stand (it would move one aside or leave it out)
	local close = 0
	local crates = {}
	for _, m in ipairs(markers) do
		if m.kind == "Crate" then
			table.insert(crates, m)
		end
	end
	for i = 1, #crates do
		for j = i + 1, #crates do
			local a, b = crates[i], crates[j]
			if (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 < spacing * spacing and abs(a.bottom - b.bottom) < 4 then
				close += 1
			end
		end
	end
	if close > 0 then
		bad.add(string.format("%d pairs of crate markers stand closer than CrateSpacing (%g)", close, spacing))
	end
	-- what each round size finds inside its start ring
	local rows = {}
	local thin = nil
	for _, n in ipairs({ 1, 2, 4, 8, 16, 24, 32, 48 }) do
		if n <= maxContenders then
			local limit = Loot.startRadiusFor(ctx.config, n) + margin
			local c, g = 0, 0
			for _, m in ipairs(markers) do
				if m.r <= limit then
					if m.kind == "Crate" then
						c += 1
					else
						g += 1
					end
				end
			end
			local items = c * crateMean + g * chance
			table.insert(rows, string.format("%d: %d+%d = %.0f (%.1f a head)", n, c, g, items, items / n))
			if items / n < perHead * 0.8 then
				thin = n
			end
		end
	end
	if thin then
		bad.add(string.format("a round of %d finds under %.0f expected items a head", thin, perHead * 0.8))
	end
	local detail = string.format("%d markers (%d crates); seated by LootService's ray: %d, no floor: %d; tier-3 within %d: %d (%d restocked in place, %d dropped in); runner's caches %d; by round size (crates+ground = expected items): %s",
		#markers, #crates, seated, unseated, refill, tier3, restocked, dropped, runners, table.concat(rows, " | "))
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	if seated == 0 then
		return "SKIP", "the markers fit the data; no floor in the place to seat them on yet | " .. detail
	end
	return "PASS", detail
end

function checks.boundary(ctx)
	local L = ctx.layout
	local boundary = ctx.arena and ctx.arena:FindFirstChild("Boundary")
	if not boundary then
		return "FAIL", "workspace.Arena.Boundary is missing"
	end
	local radius = (L and L.BoundaryRadius) or 1900
	local parts = {}
	local bad = Problems()
	local notSolid, visible, mantle, wrongRing = 0, 0, 0, 0
	for _, d in ipairs(boundary:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if not d.CanCollide then
				notSolid += 1
			end
			if d.Transparency < 0.95 then
				visible += 1
			end
			if not CollectionService:HasTag(d, "NoMantle") then
				mantle += 1
			end
			local p = d.Position - ctx.offset
			if abs(sqrt(p.X * p.X + p.Z * p.Z) - radius) > 25 then
				wrongRing += 1
			end
		end
	end
	if #parts == 0 then
		return "FAIL", "workspace.Arena.Boundary has no parts"
	end
	if wrongRing > 0 then
		bad.add(string.format("%d walls are not at r %d (the forest arena's ring at 712?)", wrongRing, radius))
	end
	if notSolid > 0 then
		bad.add(notSolid .. " walls are not solid")
	end
	if visible > 0 then
		bad.add(visible .. " walls can be seen")
	end
	if mantle > 0 then
		bad.add(mantle .. " walls lack the NoMantle tag (they could be climbed)")
	end
	-- all the way round: at every bearing a wall holds the point on the ring, 4 and 40 studs over the ground
	local gaps = 0
	for b = 0, 359.5, 0.5 do
		local x, z = polar(b, radius)
		local ground = ctx.G.heightAt(x, z)
		for _, up in ipairs({ 4, 40 }) do
			local point = Vector3.new(x, ground + up, z) + ctx.offset
			local held = false
			for _, part in ipairs(parts) do
				local l = part.CFrame:PointToObjectSpace(point)
				local s = part.Size
				if abs(l.X) <= s.X / 2 + 6 and abs(l.Y) <= s.Y / 2 and abs(l.Z) <= s.Z / 2 + 6 then
					held = true
					break
				end
			end
			if not held then
				gaps += 1
				if gaps <= 3 then
					bad.add(string.format("no wall at bearing %.1f, %d studs over the ground", b, up))
				end
			end
		end
	end
	local detail = string.format("%d walls at r %d; %d gaps in 720 bearings x 2 heights", #parts, radius, gaps)
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.peak(ctx)
	local landmarks = ctx.arena and ctx.arena:FindFirstChild("Landmarks")
	local peak = landmarks and landmarks:FindFirstChild("Peak")
	if not peak or not ctx.terrainHere then
		return "SKIP", "the Peak or Map 1's terrain is not in the place"
	end
	local module = map1Module("Terrain")
	if not module then
		return "FAIL", "ServerStorage.WorldGen.Map1.Terrain is missing"
	end
	local text, survey = fresh(module).surveyUnder({ model = peak, step = 8 })
	if not survey then
		return "FAIL", text
	end
	if survey.rimOpen > 0 then
		return "FAIL", text .. " | a player can walk in under the shell: run Map1.Terrain.fillUnder()"
	end
	return "PASS", text
end

function checks.instances(ctx)
	local arena = ctx.arena
	if not arena then
		return "FAIL", "workspace.Arena is missing"
	end
	local bad = Problems(10)
	local found = {}
	for _, name in ipairs({ "Plinths", "Landmarks", "Skyline", "FarValley", "Scatter", "Boundary" }) do
		local inst = arena:FindFirstChild(name)
		if not inst then
			bad.add("workspace.Arena." .. name .. " is missing")
		else
			table.insert(found, string.format("%s %d", name, #inst:GetDescendants()))
			if #inst:GetChildren() == 0 then
				bad.add("workspace.Arena." .. name .. " is empty")
			end
			if name == "Skyline" or name == "FarValley" then
				-- Persistent, so the far view is there whatever has streamed in
				local models = if inst:IsA("Model") then { inst } else inst:GetChildren()
				for _, model in ipairs(models) do
					if model:IsA("Model") and model.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
						bad.add(string.format("%s is not a Persistent model", model:GetFullName()))
					end
				end
				-- Their meshes are modelled in world space: the holder and every asset in it pivot at the map centre,
				-- unturned. (18 Nov: the whole far valley was found 1,580 studs off and tilted 3.5 degrees, dragged by a
				-- stray click in the 3D view; it showed as shards across the sky. Its parts are Locked since.)
				local holders = { inst }
				for _, child in ipairs(inst:GetChildren()) do
					table.insert(holders, child)
				end
				for _, holder in ipairs(holders) do
					if holder:IsA("Model") then
						local pivot = holder:GetPivot()
						local _, angle = pivot:ToAxisAngle()
						if pivot.Position.Magnitude > 0.05 or math.abs(angle) > 1e-4 then
							bad.add(string.format("%s is out of place: pivot (%.1f, %.1f, %.1f), turned %.2f degrees; it belongs at the map centre, unturned (PivotTo(CFrame.identity))",
								holder:GetFullName(), pivot.X, pivot.Y, pivot.Z, math.deg(angle)))
						end
					end
				end
			end
		end
	end
	-- the builders and the vault
	for _, name in ipairs({ "Data", "Terrain", "Assets", "Scatter", "Loot", "Water", "Audit" }) do
		if not map1Module(name) then
			bad.add("ServerStorage.WorldGen.Map1." .. name .. " is missing")
		end
	end
	if not ServerStorage:FindFirstChild("Vault_ClassicForest") then
		bad.add("ServerStorage.Vault_ClassicForest is missing (the forest arena's scripts and data)")
	end
	if not ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("Map1Regions") then
		bad.add("ReplicatedStorage.Shared.Map1Regions is missing (getBiome on clients)")
	end
	-- nothing of the forest arena left behind
	for _, name in ipairs({ "SpirePlatform", "Waterfall", "RockPocketFill_Cliffs_330_285", "POIs", "Camps", "Cliffs", "Rocks" }) do
		if arena:FindFirstChild(name) then
			bad.add("workspace.Arena." .. name .. " is still there (the forest arena's)")
		end
	end
	if workspace.Terrain:FindFirstChild("WaterfallMist") then
		bad.add("workspace.Terrain.WaterfallMist is still there (the forest arena's falls)")
	end
	for _, tagged in ipairs(CollectionService:GetTagged("LootSpawn")) do
		if tagged:IsDescendantOf(workspace) then
			bad.add("a LootSpawn marker is in the workspace: " .. tagged:GetFullName())
		end
	end
	local L = ctx.layout
	local centre = arena:GetAttribute("Center")
	if centre ~= nil and L and centre ~= L.Center then
		bad.add("workspace.Arena's Center attribute is " .. tostring(centre) .. ", not the layout's Center")
	end
	local playRadius = arena:GetAttribute("PlayRadius")
	if playRadius ~= nil and L and playRadius ~= L.PlayRadius then
		bad.add("workspace.Arena's PlayRadius attribute is " .. tostring(playRadius) .. " (the forest arena's)")
	end
	local detail = "descendants: " .. table.concat(found, ", ")
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.lobby(ctx)
	local L = ctx.layout
	local position = L and L.LobbyPosition
	if typeof(position) ~= "Vector3" then
		return "FAIL", "the layout has no LobbyPosition"
	end
	local lobby = ctx.opts.lobby or workspace:FindFirstChild("Lobby")
	if not lobby then
		return "FAIL", "workspace.Lobby is missing"
	end
	local bad = Problems()
	local spawns, far = 0, 0
	local reach = (L.LobbyRadius or 90) * 2
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Enabled then
			spawns += 1
			local p = d.Position
			if Vector3.new(p.X - position.X, 0, p.Z - position.Z).Magnitude > reach or abs(p.Y - position.Y) > 60 then
				far += 1
			end
		end
	end
	if spawns == 0 then
		bad.add("no enabled SpawnLocation under workspace.Lobby")
	end
	if far > 0 then
		bad.add(string.format("%d of %d spawns are not on the island at LobbyPosition %s (the lobby was not moved with its layout?)", far, spawns, tostring(position)))
	end
	local hit = workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -240, 0))
	if not hit then
		bad.add("no ground at LobbyPosition (PlayerService would build its fallback pad)")
	end
	local terrainRadius = L.TerrainRadius or 2750
	local out = Vector3.new(position.X - L.Center.X, 0, position.Z - L.Center.Z).Magnitude
	if out < terrainRadius + reach then
		bad.add(string.format("LobbyPosition is %.0f from the centre: inside the arena's terrain (r %d)", out, terrainRadius))
	end
	local detail = string.format("%d spawns; ground at LobbyPosition %s; %.0f studs from the Horn", spawns, if hit then string.format("y %.1f", hit.Position.Y) else "none", out)
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.ambience(ctx)
	local soundsModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds")
	local okSounds, Sounds = pcall(fresh, soundsModule)
	if not okSounds or type(Sounds) ~= "table" then
		Sounds = require(soundsModule) :: any
	end
	local L = ctx.layout
	local limit = (L and L.TerrainRadius) or 2750
	local bad = Problems()
	local counts: { [string]: number } = {}
	local total = 0
	for _, inst in ipairs(CollectionService:GetTagged("AmbientEmitter")) do
		if ctx.arena and inst:IsDescendantOf(ctx.arena) then
			total += 1
			local key = inst:GetAttribute("SoundKey")
			counts[tostring(key)] = (counts[tostring(key)] or 0) + 1
			if type(key) ~= "string" or type(Sounds[key]) ~= "table" then
				bad.add(inst:GetFullName() .. " has SoundKey " .. tostring(key) .. ", which Shared.Sounds does not have")
			end
			if key == "Emit_Waterfall" or key == "Emit_Frogs" then
				bad.add(inst:GetFullName() .. " plays " .. tostring(key) .. ": Map 1 has no falls and no marsh (the forest arena's emitter?)")
			end
			local p = if inst:IsA("BasePart") then inst.Position elseif inst:IsA("Attachment") then inst.WorldPosition else nil
			if p and Vector3.new(p.X - ctx.offset.X, 0, p.Z - ctx.offset.Z).Magnitude > limit then
				bad.add(inst:GetFullName() .. " is outside the terrain")
			end
		end
	end
	local list = {}
	for key, count in pairs(counts) do
		table.insert(list, key .. " " .. count)
	end
	table.sort(list)
	local detail = string.format("%d emitters under workspace.Arena (%s)", total, table.concat(list, ", "))
	if total == 0 then
		return "FAIL", "no AmbientEmitter under workspace.Arena (run Map1.Water.build) | " .. detail
	end
	if bad.count > 0 then
		return "FAIL", bad.text() .. " | " .. detail
	end
	return "PASS", detail
end

function checks.scripts(_ctx)
	local dev = ServerStorage:FindFirstChild("Dev")
	local module = dev and dev:FindFirstChild("SyntaxCheck")
	if not module then
		return "FAIL", "ServerStorage.Dev.SyntaxCheck is missing"
	end
	local report = fresh(module).run()
	if type(report) == "string" and string.find(report, "OK", 1, true) and not string.find(report, "FAIL", 1, true) then
		return "PASS", string.sub(report, 1, 160)
	end
	return "FAIL", string.sub(tostring(report), 1, 600)
end

function checks.leftovers(ctx)
	local bad = Problems(10)
	local function present(parent: Instance, name: string, why: string)
		if parent:FindFirstChild(name) then
			bad.add(parent:GetFullName() .. "." .. name .. " (" .. why .. ")")
		end
	end
	present(workspace, "Workbench_Map1", "the builders' workbench")
	present(workspace, "FallbackLobbyPad", "PlayerService's emergency pad")
	present(workspace, "TrainingDummies", "a playtest's dummies")
	present(ReplicatedStorage, "DevInputCheck", "InputCheck's probe")
	present(ServerStorage, "_SyntaxProbes", "SyntaxCheck's probes")
	-- test attributes: DetailTier forces every Studio client's scenery tier, DevShaders / DevLookHour the look
	for _, name in ipairs({ "QA_Lock", "DetailTier", "DevShaders", "DevLookHour" }) do
		if workspace:GetAttribute(name) ~= nil then
			bad.add("workspace attribute " .. name)
		end
	end
	local state = ReplicatedStorage:FindFirstChild("GameState")
	if state then
		for _, name in ipairs({ "LaunchCutTest", "DevRollCall", "DevEpilogue" }) do
			if state:GetAttribute(name) ~= nil then
				bad.add("GameState attribute " .. name)
			end
		end
	end
	-- terrain left in the workbench box (X -15000..-13000, Z -1000..1000)
	local hits = 0
	for x = -14975, -13025, 50 do
		for z = -975, 975, 50 do
			if workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -4000, 0), ctx.terrainParams) then
				hits += 1
			end
		end
	end
	if hits > 0 then
		bad.add(string.format("terrain in the workbench box (%d of 1,600 rays hit)", hits))
	end
	if bad.count > 0 then
		return "FAIL", "left in the place: " .. bad.text()
	end
	return "PASS", "no workbench, probe, test attribute or workbench terrain"
end

function checks.manual(_ctx)
	return "MANUAL", "by a playtest or a person: a lone player's round from launch to the next round (loot, drink, the dummies, "
		.. "the border closing on a mouth lane, the round ending); two clients; frame time and memory on the mid quality level "
		.. "against ArenaV3 section 7; InputCheck in a playtest; the pictures for the owner"
end

----------------------------------------------------------------------------------------------------
-- run
----------------------------------------------------------------------------------------------------
function Audit.ok(results: { any }): boolean
	for _, result in ipairs(results) do
		if result.status == "FAIL" then
			return false
		end
	end
	return true
end

function Audit.run(options: { [string]: any }?): (string, { any })
	assert(not RunService:IsRunning(), "Map1.Audit runs in Edit mode only")
	local opts = options or {}
	local started = os.clock()
	local ctx: { [string]: any } = { opts = opts, offset = opts.offset or Vector3.zero, terrainParams = terrainParams() }
	local lootModule = map1Module("Loot")
	local dataModule = map1Module("Data")
	if not lootModule or not dataModule then
		return "Map1.Audit: ServerStorage.WorldGen.Map1.Loot and .Data are needed", {}
	end
	ctx.Loot = fresh(lootModule)
	local data = opts.data
	if not data then
		data = fresh(dataModule)
		data.load({ "Terrain", "Layout", "Height", "Region", "WaterLevel" })
	end
	ctx.data = data
	ctx.config = opts.config or fresh(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
	ctx.value = function(section: string, key: string): any
		return ctx.Loot.mapValue(ctx.config, section, key)
	end
	ctx.G = opts.ground or ctx.Loot.ground(data, ctx.config)
	ctx.arena = opts.arena or workspace:FindFirstChild("Arena")
	local layoutModule = opts.layoutModule or ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("ArenaLayout")
	if layoutModule then
		local ok, layout = pcall(fresh, layoutModule)
		if ok and type(layout) == "table" then
			ctx.layout = layout
		else
			ctx.layoutError = layout
		end
	else
		ctx.layoutError = "Shared.ArenaLayout is missing"
	end
	-- is Map 1's terrain here? ground at the data's height at the centre and on three rings (the forest arena's own
	-- terrain is at 46 in the middle too, but it ends at r 920 and its hills are elsewhere)
	local found, asked = 0, 0
	for _, r in ipairs({ 0, 500, 1000, 1500 }) do
		for b = 0, 315, 45 do
			if r > 0 or b == 0 then
				asked += 1
				local x, z = polar(b, r)
				local y = terrainY(ctx, x, z)
				if y and abs(y - ctx.G.heightAt(x, z)) < 6 then
					found += 1
				end
			end
		end
	end
	ctx.terrainHere = opts.assumeTerrain == true or found >= asked * 0.8

	local wanted: { [string]: boolean } = {}
	for _, name in ipairs(opts.only or Audit.CHECKS) do
		wanted[name] = true
	end
	for _, name in ipairs(opts.skip or {}) do
		wanted[name] = nil
	end
	local results = {}
	local lines = {}
	local counts = { PASS = 0, FAIL = 0, SKIP = 0, MANUAL = 0 }
	for _, name in ipairs(Audit.CHECKS) do
		if wanted[name] then
			local ok, status, detail = pcall(checks[name], ctx)
			if not ok then
				status, detail = "FAIL", "the check itself errored: " .. tostring(status)
			end
			counts[status] = (counts[status] or 0) + 1
			table.insert(results, { name = name, status = status, detail = detail })
			table.insert(lines, string.format("%-6s %-10s %s", status, name, detail))
			task.wait()
		end
	end
	table.insert(lines, 1, string.format("Map1.Audit: %d pass, %d FAIL, %d skipped (not in the place yet), %d manual; Map 1's terrain %s; %.1f s",
		counts.PASS, counts.FAIL, counts.SKIP, counts.MANUAL, if ctx.terrainHere then "is here" else "is NOT here", os.clock() - started))
	return table.concat(lines, "\n"), results
end

return Audit
