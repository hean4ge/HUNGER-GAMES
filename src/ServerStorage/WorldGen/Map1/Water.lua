--[[
	Map1.Water - Map 1's drinking-water points and its ambience emitters (docs/design/Map1Build.md 3.2, install step 7).
	STUDIO ONLY, Edit mode. Both come from the data pack "map1_data" (Map1.Data): the WaterLevel grid AFTER the
	packer's repairs (the water that is really written as voxels), the Height grid, the Region grid and the Layout.

	1. ReplicatedStorage.Shared.WaterPoints (PlayabilityPlan QW10): the water a thirsty newcomer is pointed to on the
	   compass. HUDController requires the module and calls WaterPoints.nearest(position, accept?) -> (point,
	   flatDistance, kind); nothing else reads it. This builder rewrites the module's Source in the same form the forest
	   arena's builder wrote: Points = { { x, waterY, z, kind } } at the water's surface, and the same nearest().
	   A point is a wet cell at least MIN_DEPTH deep that touches dry ground a contender can walk to (the lake's shore
	   all the way round, both banks of the stream), kind "Lake" (the lake's own region) or "Stream", kept SPACING
	   studs apart and inside the full round's start ring. Where the place already holds Map 1's terrain every point is
	   also checked against the real voxels (Water in the voxel column at the surface): a dry one is dropped and
	   reported. Before the terrain is written the report says the points are unverified.
	2. The ambience emitters AudioController plays: Parts tagged AmbientEmitter with attribute SoundKey (a Shared.Sounds
	   key), in workspace.Arena.Ambience. "Emit_River" along the stream every RIVER_STEP studs (not in the lake), and
	   "Emit_Wind" 12 studs over the four exposed sites (the two crests, the Edge, the shoulder). Map 1 has no
	   waterfall and no marsh. The lake itself is the "Lake" biome bed (ArenaLayout.getBiome).

	USE (execute_luau, Edit mode; require a clone)
	  local Water = require(game.ServerStorage.WorldGen.Map1.Water:Clone())
	  return Water.build()                    -- rewrites Shared.WaterPoints and this builder's emitters
	  return Water.build({ dryRun = true })   -- writes nothing: the report (the second result holds .source)
	  opts.data, opts.config   a loaded Map1.Data / the Config table (else fresh copies)
	  opts.module          the ModuleScript to write (default ReplicatedStorage.Shared.WaterPoints, made if missing)
	  opts.emitterParent   the folder for the emitters (default workspace.Arena.Ambience, made if missing)
	  opts.points = false / opts.emitters = false   do only the other half
	  opts.verify = false  never look at the terrain
	  opts.offset          Vector3 added to every world position (a workbench copy of the map)
	After a real build the repo must take the new module: export it and pull it (tools/studio_sync/README.md).
	Deterministic: the same data gives the same module text and the same emitters.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max

local Water = {}
Water.VERSION = 1
Water.SOURCE = "Map1:Water" -- the emitters' Source attribute

local MIN_DEPTH = 0.4 -- studs of water over the ground (the forest builder's rule)
local SPACING = 30 -- studs between kept points
local EDGE_MARGIN = 20 -- studs kept inside the full round's start radius
local RIVER_STEP = 60 -- studs of stream between two Emit_River emitters
local WIND_SITES = { "D5", "D6", "D3", "D4" } -- the East and West Crests, the Edge, the Shoulder Cairn
local WIND_HEIGHT = 12

local function fresh(module: Instance): any
	return require(if RunService:IsRunning() then module else module:Clone() :: any)
end

local function map1Module(name: string): Instance
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local folder = worldGen and worldGen:FindFirstChild("Map1")
	local module = folder and folder:FindFirstChild(name)
	if not module then
		error("Map1.Water: ServerStorage.WorldGen.Map1." .. name .. " is missing")
	end
	return module
end

----------------------------------------------------------------------------------------------------
-- the points
----------------------------------------------------------------------------------------------------
-- Every candidate: { x, y, z, kind, order } from the grids alone.
local function candidates(data: any, G: any, maxRadius: number): { any }
	local n: number = data.N
	local terrain = data.terrain()
	local lake = terrain.lake or {}
	local lakeX = (lake.centre and lake.centre[1]) or 0
	local lakeZ = (lake.centre and lake.centre[3]) or 0
	-- the stream's centreline, to order its points from the spring to the lake
	local line = (terrain.stream and terrain.stream.pointsRoblox) or {}
	local function along(x: number, z: number): number
		local best, bestS, s = math.huge, 0, 0
		for i = 1, #line - 1 do
			local ax, az, bx, bz = line[i][1], line[i][3], line[i + 1][1], line[i + 1][3]
			local ex, ez = bx - ax, bz - az
			local len2 = ex * ex + ez * ez
			local len = sqrt(len2)
			local u = if len2 > 0 then math.clamp(((x - ax) * ex + (z - az) * ez) / len2, 0, 1) else 0
			local px, pz = ax + ex * u, az + ez * u
			local d = (x - px) ^ 2 + (z - pz) ^ 2
			if d < best then
				best, bestS = d, s + len * u
			end
			s += len
		end
		return bestS
	end

	local list = {}
	local r2 = maxRadius * maxRadius
	for row = 1, n - 2 do
		for col = 1, n - 2 do
			local level = data.waterLevel(col, row)
			if level then
				local x, z = G.centre(col, row)
				if x * x + z * z <= r2 and level - G.height(col, row) >= MIN_DEPTH then
					-- it must touch dry ground that can be walked to
					local shore = false
					for dr = -1, 1 do
						for dc = -1, 1 do
							if (dr ~= 0 or dc ~= 0) and not G.wet(col + dc, row + dr) and G.reachable(col + dc, row + dr) then
								shore = true
							end
						end
					end
					if shore then
						local isLake = G.regionName(col, row) == "Lake"
						local order
						if isLake then
							-- round the lake, clockwise from its north shore
							order = (math.deg(math.atan2(x - lakeX, -(z - lakeZ))) % 360)
						else
							order = along(x, z)
						end
						table.insert(list, { x = x, y = level, z = z, kind = if isLake then "Lake" else "Stream", order = order })
					end
				end
			end
		end
	end
	-- the stream first (spring to lake), then the lake's shore (clockwise): a fixed order for the spacing pass
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "Stream"
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.z < b.z
	end)
	return list
end

-- Is there real water at the point? true / false, or nil when the place has no terrain there at all.
local function waterInWorld(point: Vector3): boolean?
	local region = Region3.new(point - Vector3.new(2, 6, 2), point + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, materials, occupancy = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok or not materials then
		return nil
	end
	local size = materials.Size
	local any = false
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				local material = materials[x][y][z]
				if material == Enum.Material.Water and occupancy[x][y][z] > 0 then
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

local HEADER = [[
--[=[
	WaterPoints - the drinkable water a thirsty newcomer is pointed to (PlayabilityPlan QW10). Client and server.
	GENERATED by ServerStorage.WorldGen.Map1.Water for Map 1, the Green Land (%d points): do not edit by hand, re-run
	the builder after the terrain changes. Each point is { x, waterY, z, kind } at the water's surface; kind is
	Lake | Stream. Every point is a cell of the data pack's repaired water grid, at least %.1f deep, beside dry ground
	that can be walked to (%s).
	  WaterPoints.nearest(position, accept?) -> (point: Vector3?, flatDistance: number, kind: string?)
	    accept(point: Vector3, kind: string) -> boolean   optional filter, e.g. only points inside the border
]=]
local WaterPoints = {}

WaterPoints.Points = {
]]

local FOOTER = [[
}

local vectors: { Vector3 } = {}
for i, p in ipairs(WaterPoints.Points) do
	vectors[i] = Vector3.new(p[1], p[2], p[3])
end

function WaterPoints.nearest(position: Vector3, accept: ((Vector3, string) -> boolean)?): (Vector3?, number, string?)
	local best, bestD, bestKind = nil, math.huge, nil
	for i, v in ipairs(vectors) do
		local dx, dz = v.X - position.X, v.Z - position.Z
		local d = dx * dx + dz * dz
		if d < bestD then
			local kind = WaterPoints.Points[i][4]
			if accept == nil or accept(v, kind) then
				best, bestD, bestKind = v, d, kind
			end
		end
	end
	return best, if best then math.sqrt(bestD) else math.huge, bestKind
end

return WaterPoints
]]

-- Water.points(data, G, opts) -> kept points, stats
function Water.points(data: any, G: any, maxRadius: number, opts: { [string]: any }): ({ any }, { [string]: any })
	local offset: Vector3 = opts.offset or Vector3.zero
	local list = candidates(data, G, maxRadius)
	local kept = {}
	local stats = { candidates = #list, close = 0, dryInWorld = 0, verified = 0, unverified = 0, Lake = 0, Stream = 0 }
	local bucket = SPACING
	local hash: { [number]: { any } } = {}
	local function key(x: number, z: number): number
		return floor(x / bucket) * 4096 + floor(z / bucket)
	end
	local s2 = SPACING * SPACING
	for _, p in ipairs(list) do
		local near = false
		for dx = -1, 1 do
			for dz = -1, 1 do
				local cell = hash[key(p.x + dx * bucket, p.z + dz * bucket)]
				if cell then
					for _, q in ipairs(cell) do
						if (q.x - p.x) ^ 2 + (q.z - p.z) ^ 2 < s2 then
							near = true
						end
					end
				end
			end
		end
		if near then
			stats.close += 1
		else
			local real: boolean? = nil
			if opts.verify ~= false then
				real = waterInWorld(Vector3.new(p.x, p.y, p.z) + offset)
			end
			if real == false then
				stats.dryInWorld += 1
			else
				if real == true then
					stats.verified += 1
				else
					stats.unverified += 1
				end
				table.insert(kept, p)
				stats[p.kind] += 1
				local k = key(p.x, p.z)
				hash[k] = hash[k] or {}
				table.insert(hash[k], p)
			end
		end
	end
	stats.kept = #kept
	return kept, stats
end

function Water.source(points: { any }, verifiedNote: string): string
	local lines = table.create(#points)
	for i, p in ipairs(points) do
		lines[i] = string.format("\t{ %.1f, %.1f, %.1f, %q },", p.x, p.y, p.z, p.kind)
	end
	-- (a long string drops the newline right after its opening bracket, so HEADER and FOOTER start with their text)
	return string.format(HEADER, #points, MIN_DEPTH, verifiedNote) .. table.concat(lines, "\n") .. "\n" .. FOOTER
end

----------------------------------------------------------------------------------------------------
-- the emitters
----------------------------------------------------------------------------------------------------
-- Water.emitterPlan(data, G) -> { { key, x, y, z } }
function Water.emitterPlan(data: any, G: any, maxRadius: number): { any }
	local terrain = data.terrain()
	local layout = data.layout()
	local list = {}
	-- the stream: walk its centreline; an emitter where there is water within three cells and it is not the lake
	local line = (terrain.stream and terrain.stream.pointsRoblox) or {}
	local walked, nextAt = 0, RIVER_STEP / 3
	for i = 1, #line - 1 do
		local ax, az, bx, bz = line[i][1], line[i][3], line[i + 1][1], line[i + 1][3]
		local len = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		while len > 0 and nextAt <= walked + len do
			local u = (nextAt - walked) / len
			local x, z = ax + (bx - ax) * u, az + (bz - az) * u
			local col, row = G.cellAt(x, z)
			local level: number? = nil
			local bestD = math.huge
			for dr = -3, 3 do
				for dc = -3, 3 do
					local l = data.waterLevel(col + dc, row + dr)
					if l and G.regionName(col + dc, row + dr) ~= "Lake" then
						local d = dr * dr + dc * dc
						if d < bestD then
							bestD, level = d, l
						end
					end
				end
			end
			if level and x * x + z * z <= maxRadius * maxRadius then
				table.insert(list, { key = "Emit_River", x = x, y = level + 1.5, z = z })
			end
			nextAt += RIVER_STEP
		end
		walked += len
	end
	-- wind over the exposed sites
	local byId = {}
	for _, site in ipairs((layout.sites and layout.sites.items) or {}) do
		byId[site.id] = site
	end
	for _, id in ipairs(WIND_SITES) do
		local site = byId[id]
		if site then
			local x, z = site.position[1], site.position[3]
			-- the Edge's anchor is on the cliff face: the wind sounds from the lip, the higher ground beside it
			local y = G.heightAt(x, z)
			for dr = -12, 12, 4 do
				for dc = -12, 12, 4 do
					y = max(y, G.heightAt(x + dc * 4, z + dr * 4))
				end
			end
			table.insert(list, { key = "Emit_Wind", x = x, y = y + WIND_HEIGHT, z = z })
		end
	end
	return list
end

local function emitterPart(e: any, offset: Vector3): Part
	local p = Instance.new("Part")
	p.Name = e.key
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(Vector3.new(e.x, e.y, e.z) + offset)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p:SetAttribute("SoundKey", e.key)
	p:SetAttribute("Source", Water.SOURCE)
	CollectionService:AddTag(p, "AmbientEmitter")
	return p
end

local function ambienceFolder(): Instance
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		error("Map1.Water: workspace.Arena is missing")
	end
	local folder = arena:FindFirstChild("Ambience")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Ambience"
		folder.Parent = arena
	end
	return folder
end

----------------------------------------------------------------------------------------------------
-- build
----------------------------------------------------------------------------------------------------
function Water.build(options: { [string]: any }?): (string, { [string]: any })
	assert(not RunService:IsRunning(), "Map1.Water builds in Edit mode only")
	local opts = options or {}
	local started = os.clock()
	local Loot = fresh(map1Module("Loot"))
	local data = opts.data
	if not data then
		data = fresh(map1Module("Data"))
		data.load({ "Terrain", "Layout", "Height", "Region", "WaterLevel" })
	end
	local config = opts.config or fresh(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
	local G = opts.ground or Loot.ground(data, config)
	local startRadius = tonumber(Loot.mapValue(config, "Border", "StartRadius")) or G.radius
	local maxRadius = min(startRadius, G.radius) - EDGE_MARGIN
	local offset: Vector3 = opts.offset or Vector3.zero
	local result: { [string]: any } = {}
	local lines = {}

	if opts.points ~= false then
		local kept, stats = Water.points(data, G, maxRadius, opts)
		local note = if stats.verified > 0 and stats.unverified == 0 then "all checked against the terrain's voxels"
			elseif stats.verified > 0 then string.format("%d checked against the terrain's voxels, %d not", stats.verified, stats.unverified)
			else "not yet checked against the terrain"
		local source = Water.source(kept, note)
		result.points, result.pointStats, result.source = kept, stats, source
		local where = "(dry run: nothing written)"
		if not opts.dryRun then
			local module = opts.module
			if not module then
				local shared = ReplicatedStorage:WaitForChild("Shared")
				module = shared:FindFirstChild("WaterPoints")
				if not module then
					module = Instance.new("ModuleScript")
					module.Name = "WaterPoints"
					module.Parent = shared
				end
			end
			(module :: ModuleScript).Source = source
			where = "-> " .. module:GetFullName()
		end
		table.insert(lines, string.format("Map1.Water points: %d kept of %d shore cells (Stream %d, Lake %d; %d too close, %d dry in the world) %s; %s; %d bytes",
			stats.kept, stats.candidates, stats.Stream, stats.Lake, stats.close, stats.dryInWorld, where, note, #source))
		if stats.kept == 0 then
			table.insert(lines, "  PROBLEM: no water point at all")
		end
	end

	if opts.emitters ~= false then
		local plan = Water.emitterPlan(data, G, maxRadius)
		result.emitters = plan
		local counts: { [string]: number } = {}
		for _, e in ipairs(plan) do
			counts[e.key] = (counts[e.key] or 0) + 1
		end
		local where = "(dry run: nothing built)"
		if not opts.dryRun then
			local parent: Instance = opts.emitterParent or ambienceFolder()
			local removed = 0
			for _, child in ipairs(parent:GetChildren()) do
				if child:GetAttribute("Source") == Water.SOURCE then
					child:Destroy()
					removed += 1
				end
			end
			local others = 0
			for _, child in ipairs(parent:GetChildren()) do
				if CollectionService:HasTag(child, "AmbientEmitter") then
					others += 1
				end
			end
			for _, e in ipairs(plan) do
				emitterPart(e, offset).Parent = parent
			end
			where = string.format("-> %s (%d of this builder's replaced; %d other emitters left in it)", parent:GetFullName(), removed, others)
			if others > 0 then
				table.insert(lines, string.format("  WARNING: %d emitters in %s were not made by this builder (the forest arena's river, falls and frogs?)",
					others, parent:GetFullName()))
			end
		end
		local kinds = {}
		for key, count in pairs(counts) do
			table.insert(kinds, key .. " " .. count)
		end
		table.sort(kinds)
		table.insert(lines, string.format("Map1.Water emitters: %d (%s) %s", #plan, table.concat(kinds, ", "), where))
	end
	table.insert(lines, string.format("  %.1f s", os.clock() - started))
	return table.concat(lines, "\n"), result
end

return Water
