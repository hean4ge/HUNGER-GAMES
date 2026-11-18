--[[
	Map1.Terrain - turns the Map 1 data pack ("the Green Land", Blender's height, material and water grids) into
	Roblox terrain. Edit mode only. The data comes through ServerStorage.WorldGen.Map1.Data; nothing is generated
	here: Blender made the heights, the packer repaired the water (docs/design/Map1Build.md, decisions 4 and 5).

	WHAT IT WRITES
	  One voxel column per grid cell (4 studs), out to Params.terrainRadius (2,750), in chunks of 16 x 16 columns
	  (64 x 64 studs), each with one WriteVoxelChannels call (SolidMaterial, SolidOccupancy, LiquidOccupancy).
	  A chunk's box runs from Params.shellInner (64) studs under its lowest ground (Params.shellOuter, 24, beyond
	  Params.shellRadius, 1,952) to just above its highest ground or water. The lowest ground is taken over the
	  chunk and one column all round it, so two neighbouring boxes always overlap by at least the thinner shell.
	  No plinth bores (decision 6).

	THE VOXEL RULES (ported from the classic arena's TerrainGen: columnVoxels and writeArenaChunk)
	  - occupancy = (ground - voxel centre) / 4, clamped to 0..1: the smooth surface. On faces steeper than 42
	    degrees the distance is scaled toward the distance along the normal (Params.steepNormal).
	  - no solid in the voxel that holds a water surface: Roblox neither draws nor raycasts water whose voxel also
	    holds solid. A bed inside that voxel drops out of it.
	  - liquid fills every voxel under the level that is not full of solid.
	  - the containment pass: a voxel with no water beside a water voxel gets at least that much solid (plus
	    Params.containExtra), so no water face stands against air. Each column decides from its own and its
	    neighbours' unmodified values, so two chunks agree at their seam.
	  - the bed under water is written Params.wetBias lower than the grid, because a narrow channel's bed is drawn
	    high (measured; see Params).
	  - materials: the cell's slot (Slots below) for the top two voxels and whatever a lower neighbour leaves in
	    view (Params.topDepth, topMax), the slot's "sub" material under it (Params.subDepth), Params.deep (Rock)
	    below. Roblox's own materials; no MaterialVariant is used.
	Nothing is kept in a Lua table per cell: the grids stay in buffers, a chunk uses small scratch arrays, and full
	or empty voxel rows are shared between the chunk's columns.

	EDIT-MODE USE (execute_luau). Studio caches required modules, so require a clone:
	  local T = require(game.ServerStorage.WorldGen.Map1.Terrain:Clone())
	  T.generate(opts)        -- starts the write on a background thread and returns at once. Watch the attributes
	                          --   workspace.Terrain Map1Status / Map1Progress, or call T.status().
	  T.run(opts)             -- the same work in the calling thread (it yields); returns the summary
	  T.plan(opts)            -- counts chunks and voxels for the same options without writing anything
	  T.preflight()           -- checks the data against the rules the writer relies on (water, the heart, slots)
	  T.verify(opts)          -- checks the written terrain: tops against the grid, holes, sealed water, no solid
	                          --   above a water surface. Returns text; the last line says PASS or FAIL.
	                          --   (It waits 0.3 s first: rays just after a write meet the old collision mesh.)
	  T.clearRegion(minX, maxX, minZ, maxZ, opts)   -- FillRegion Air in tiles (world studs). Never Terrain:Clear.
	  T.clearOldArena(opts)   -- the classic arena's terrain box (see Params.oldArenaHalf)
	  T.applyLook()           -- one colour per base material from the Blender palette, the water colour, and the
	                          --   base materials back to Roblox's own textures. GLOBAL: it changes the whole place.
	  T.lookSnapshot() / T.restoreLook(snapshot)    -- read and put back what applyLook changes
	  T.applyLook({ remember = true }) ... T.restoreLook()   -- a look for a test: the old one waits in an attribute
	  T.applyStreaming()      -- today's streaming numbers
	  T.buildBoundary(opts)   -- the invisible backstop at Params.boundaryRadius, following the ground
	  T.fillUnder(opts)       -- raises the ground under a landmark shell (the Peak) to its underside, so nobody
	                          --   walks in under its skirt. Run it after the terrain AND the landmarks are in.
	  T.surveyUnder(opts)     -- the same survey without writing: how many columns are open, and where
	  T.windowBox(minX, maxX, minZ, maxZ) / T.windowAround(x, z, radius)   -- a window from map studs
	opts for generate / run / plan / verify:
	  offset   Vector3, multiples of 4. Everything is written at map position + offset (a tile at the workbench).
	  window   { col0, col1, row0, row1 } (first and last column and row, from 0, inclusive) or the same four as
	           named fields. Only these columns are written. In a window smaller than the grid, a wet cell on the
	           window's outer ring is written as a dry bank, so the tile holds its own water.
	  clear    generate / run: FillRegion Air over the window's box first (default false)
	  dry      generate / run: build and time every chunk's arrays but write nothing (a rehearsal)
	  force    generate: start even when Map1Status says a run is in progress
	  pack     the data pack's name (default "map1_data")
	  look, streaming, boundary   generate / run: also call applyLook / applyStreaming / buildBoundary (default false)
	generate() and run() refuse to write over the lobby (a SpawnLocation of workspace.Lobby inside the written
	disc): move the lobby first (decision 3), or pass allowLobby = true.
]]
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local floor, ceil, sqrt, abs, min, max = math.floor, math.ceil, math.sqrt, math.abs, math.min, math.max
local atan, deg, sin, cos, rad = math.atan, math.deg, math.sin, math.cos, math.rad
local readu16, readu8 = buffer.readu16, buffer.readu8
local HUGE = math.huge

local MAT = Enum.Material
local AIR = MAT.Air

local Writer = {}
Writer.VERSION = 1
Writer.PACK = "map1_data"

Writer.Params = {
	terrainRadius = 2750, -- voxels out to here (Terrain.json radii.terrainTo replaces it when present)
	shellInner = 64, -- studs of solid under the lowest ground of a chunk that reaches inside shellRadius
	shellRadius = 1952,
	shellOuter = 24, -- the same for chunks wholly beyond shellRadius
	headroom = 6, -- empty studs written above the highest ground or water of a chunk
	-- The slot's top material reaches this far down (further where a neighbour is lower or the face is steep).
	-- It must cover the voxel under the highest one: where the highest voxel is thin, Roblox paints the surface
	-- with the material of the full voxel beneath it. With the classic 4.5 the sub material (Ground) showed through
	-- the grass in bands along the contours (seen on the heart tile, 15 November 2026).
	topDepth = 8.5,
	subDepth = 14, -- the slot's sub material reaches this far down; Params.deep below
	-- A soil slot (one whose sub material differs from its top: grass, forest floor) never paints more than this
	-- much of an exposed face: a cliff under a grass cell shows turf, a band of earth, then rock. Every other slot
	-- paints its whole exposed face (a limestone crag is limestone to its foot).
	topMax = 12,
	deep = MAT.Rock,
	steepNormal = true, -- scale the occupancy ramp toward the normal distance on faces steeper than 42 degrees
	steepFloor = 0.1, -- the smallest scale (a face of 84 degrees or more)
	bank = 0.35, -- a window's rim: a wet cell becomes a dry bank this far above its water
	-- The containment pass: a voxel with no water beside a water voxel holds at least that water's occupancy plus
	-- containExtra, and never less than containMin. The classic writer used + 0.1, which stands the bank 2.4 studs
	-- over the water (measured: a column's top is its highest voxel's centre + 4 x that voxel's occupancy). On
	-- Map 1's stream, two or three cells wide, that bank leans over the water: - 0.1 (1.6 studs) hides fewer cells
	-- and still leaves no water voxel beside a voxel of air. Measured on the heart tile, 15 November 2026.
	containExtra = -0.1,
	containMin = 0.05,
	-- Studs taken off the bed under water before it becomes voxels. Measured: in a channel a few cells wide the
	-- bed is drawn about half a stud above the grid (depth 0.57 where the grid says 1.03; 46 of 182 stream columns
	-- showed no water). With 0.5 the depth is drawn as designed (0.96 for 0.97) and 179 of 182 columns show water.
	wetBias = 0.5,
	sliceSeconds = 0.03, -- work at most this long, then wait a frame
	boundaryRadius = 1900, -- Terrain.json radii.boundary replaces it when present
	boundaryWalls = 144, -- about 83 studs each
	boundaryAbove = 260, -- wall top above the highest ground near it
	boundaryBelow = 30, -- wall foot below the lowest ground near it
	wallStep = 16, -- verify: a column with a neighbour this much higher is "at the foot of a wall"
	oldArenaHalf = 960, -- the classic arena's voxel grid ran from -960 to 960 (its terrain reaches r 924: measured)
	clearMinY = -128,
	clearMaxY = 1408,
	clearTile = 256,
}

-- Blender's material slots (Map1_Terrain.json "materialSlots") as Roblox's own terrain materials.
--   top: what the cell shows. sub: under the top, down to Params.subDepth.
Writer.Slots = {
	[1] = { top = MAT.Grass, sub = MAT.Ground }, -- heart turf
	[2] = { top = MAT.Grass, sub = MAT.Ground }, -- Iris meadow
	[3] = { top = MAT.Grass, sub = MAT.Ground }, -- dry slopes and ridge grass
	[4] = { top = MAT.LeafyGrass, sub = MAT.Ground }, -- forest floor
	[5] = { top = MAT.Ground, sub = MAT.Ground }, -- paths and bare earth
	[6] = { top = MAT.Sand, sub = MAT.Sand }, -- stream bed and lake floor
	[7] = { top = MAT.Mud, sub = MAT.Mud }, -- lake and stream margins
	[8] = { top = MAT.Limestone, sub = MAT.Limestone }, -- crags, ridges, boulder fields
	[9] = { top = MAT.Rock, sub = MAT.Rock }, -- cliff faces, canyon, the peak's core
	[10] = { top = MAT.Basalt, sub = MAT.Basalt }, -- tan scree
}
-- One colour per base material (Terrain:SetMaterialColor). A material that several slots share takes the tint of
-- the slot named here; every other material takes the tint of its own slot.
Writer.ColorSlot = { Grass = 2 }

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local VOX = 4
local CH = 16 -- columns per chunk side
local EMPTY = -1e9
local INV = 1 / 32
local TAN42 = math.tan(rad(42))
local TAN30 = math.tan(rad(30))
local TAN46 = math.tan(rad(46))

local function sstep(e0: number, e1: number, x: number): number
	local t = (x - e0) / (e1 - e0)
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

local sliceStart = os.clock()
local sliceSeconds = 0.03
local function maybeYield(reserve: number?)
	if os.clock() - sliceStart + (reserve or 0) > sliceSeconds then
		task.wait()
		sliceStart = os.clock()
	end
end

local function setStatus(text: string, progress: number?)
	local terrain = workspace.Terrain
	terrain:SetAttribute("Map1Status", text)
	if progress then
		terrain:SetAttribute("Map1Progress", progress)
	end
end

local function loadData(): any
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local folder = worldGen and worldGen:FindFirstChild("Map1")
	local module = folder and folder:FindFirstChild("Data")
	if not module then
		error("Map1.Terrain: ServerStorage.WorldGen.Map1.Data is missing")
	end
	return require(if RunService:IsRunning() then module else module:Clone())
end

----------------------------------------------------------------------------------------------------
-- state: the grids (buffers), the wet cells, nearW (the highest water level within 3 cells)
----------------------------------------------------------------------------------------------------
local S: any = nil

local function prepare(packName: string?): any
	local wanted = packName or Writer.PACK
	if S and S.pack == wanted then
		return S
	end
	local Data = loadData()
	Data.open(wanted)
	Data.load({ "Terrain", "Height", "Material", "WaterLevel" })
	local spec = Data.terrain()
	if Data.CELL ~= VOX then
		error(string.format("Map1.Terrain: the grid's cell is %s studs; a voxel column is %d", tostring(Data.CELL), VOX))
	end
	if Data.HEIGHT_SCALE ~= 32 then
		error("Map1.Terrain: heights must be value / 32")
	end
	local n = Data.N
	local st = {
		pack = wanted,
		Data = Data,
		spec = spec,
		N = n,
		OX = Data.ORIGIN_X,
		OZ = Data.ORIGIN_Z,
		H = Data.buffer("Height"),
		W = Data.buffer("WaterLevel"),
		M = Data.buffer("Material"),
	}
	local radii = spec.radii or {}
	st.terrainRadius = tonumber(radii.terrainTo) or Writer.Params.terrainRadius
	st.boundaryRadius = tonumber(radii.boundary) or Writer.Params.boundaryRadius
	maybeYield()
	-- the wet cells: a level more than 0.05 above the ground under it (the same test as the classic writer)
	local H, W = st.H, st.W
	local wetCells = {}
	local notAbove = 0
	for k = 0, n * n - 1 do
		local wr = readu16(W, k * 2)
		if wr ~= 0 then
			if wr > readu16(H, k * 2) + 1.6 then
				wetCells[#wetCells + 1] = k
			else
				notAbove += 1
			end
		end
	end
	st.wetCells = wetCells
	st.levelNotAboveGround = notAbove
	maybeYield()
	-- nearW: the highest water level within 3 cells (12 studs), in raw units; 0 = no water near. Below it (+ 3) a
	-- column stays true to the heightfield: plain vertical occupancy.
	local nearW = buffer.create(n * n * 2)
	local nc = ceil(n / CH)
	local chunkWet = buffer.create(nc * nc)
	for _, k in ipairs(wetCells) do
		local j = k // n
		local i = k - j * n
		local wr = readu16(W, k * 2)
		for jj = max(0, j - 3), min(n - 1, j + 3) do
			for ii = max(0, i - 3), min(n - 1, i + 3) do
				local kk = (jj * n + ii) * 2
				if readu16(nearW, kk) < wr then
					buffer.writeu16(nearW, kk, wr)
				end
			end
		end
		-- a chunk "has water" when a wet cell lies in it or in the one-column ring round it
		for cj = max(0, (j - 1) // CH), min(nc - 1, (j + 1) // CH) do
			for ci = max(0, (i - 1) // CH), min(nc - 1, (i + 1) // CH) do
				buffer.writeu8(chunkWet, cj * nc + ci, 1)
			end
		end
	end
	st.nearW = nearW
	st.NC = nc
	st.chunkWet = chunkWet
	S = st
	return st
end

-- opts -> the run's numbers (window, offset, radius, shells)
local function context(st: any, o: any): any
	local P = Writer.Params
	local n = st.N
	local window = o.window
	local wc0, wc1, wr0, wr1 = 0, n - 1, 0, n - 1
	if window then
		wc0 = window.col0 or window[1]
		wc1 = window.col1 or window[2]
		wr0 = window.row0 or window[3]
		wr1 = window.row1 or window[4]
		if not (wc0 and wc1 and wr0 and wr1) then
			error("Map1.Terrain: window needs col0, col1, row0, row1")
		end
		wc0, wc1, wr0, wr1 = max(0, floor(wc0)), min(n - 1, floor(wc1)), max(0, floor(wr0)), min(n - 1, floor(wr1))
		if wc0 > wc1 or wr0 > wr1 then
			error("Map1.Terrain: the window is empty")
		end
	end
	local offset = o.offset or Vector3.zero
	if offset.X % VOX ~= 0 or offset.Y % VOX ~= 0 or offset.Z % VOX ~= 0 then
		error("Map1.Terrain: offset must be whole multiples of 4 studs on every axis")
	end
	local R = o.radius or st.terrainRadius
	local slotTop, slotSub = {}, {}
	for id, slot in pairs(Writer.Slots) do
		slotTop[id] = slot.top
		slotSub[id] = slot.sub or slot.top
	end
	return {
		st = st,
		terrain = workspace.Terrain,
		wc0 = wc0,
		wc1 = wc1,
		wr0 = wr0,
		wr1 = wr1,
		windowed = wc0 > 0 or wr0 > 0 or wc1 < n - 1 or wr1 < n - 1,
		ox = offset.X,
		oy = offset.Y,
		oz = offset.Z,
		R2 = R * R,
		R = R,
		shellR2 = P.shellRadius * P.shellRadius,
		shellInner = P.shellInner,
		shellOuter = P.shellOuter,
		headroom = P.headroom,
		topDepth = P.topDepth,
		subDepth = P.subDepth,
		topMax = P.topMax,
		deep = P.deep,
		steepNormal = P.steepNormal,
		steepFloor = P.steepFloor,
		bank = P.bank,
		containExtra = P.containExtra,
		containMin = P.containMin,
		wetBias = P.wetBias,
		slotTop = slotTop,
		slotSub = slotSub,
		dry = o.dry == true,
		tpl = {},
		channels = {},
		chunks = 0,
		voxels = 0,
		solidRows = 0,
		filled = 0,
		luaTime = 0,
		engineTime = 0,
		maxCall = 0,
		maxNy = 0,
	}
end

-- the column the writer aims for: ground and water level (nil when dry), with the window's rim rule
local function target(ctx: any, i: number, j: number): (number?, number?)
	local st = ctx.st
	if i < ctx.wc0 or i > ctx.wc1 or j < ctx.wr0 or j > ctx.wr1 then
		return nil, nil
	end
	local xc, zc = st.OX + VOX * (i + 0.5), st.OZ + VOX * (j + 0.5)
	if xc * xc + zc * zc > ctx.R2 then
		return nil, nil
	end
	local k2 = (j * st.N + i) * 2
	local hr, wr = readu16(st.H, k2), readu16(st.W, k2)
	if wr > hr + 1.6 then
		if ctx.windowed and (i == ctx.wc0 or i == ctx.wc1 or j == ctx.wr0 or j == ctx.wr1) then
			return wr * INV + ctx.bank, nil
		end
		return hr * INV, wr * INV
	end
	return hr * INV, nil
end

-- the classic writer's slope measure (central differences, and the steepest single step), as a tangent
local function slopeTan(st: any, i: number, j: number): number
	local n, H = st.N, st.H
	local il, ir = max(i - 1, 0), min(i + 1, n - 1)
	local jd, ju = max(j - 1, 0), min(j + 1, n - 1)
	local h = readu16(H, (j * n + i) * 2) * INV
	local hl, hr = readu16(H, (j * n + il) * 2) * INV, readu16(H, (j * n + ir) * 2) * INV
	local hd, hu = readu16(H, (jd * n + i) * 2) * INV, readu16(H, (ju * n + i) * 2) * INV
	local gx, gz = (hr - hl) * 0.125, (hu - hd) * 0.125
	local e = max(abs(hr - h), abs(hl - h), abs(hu - h), abs(hd - h)) * 0.25
	return max(sqrt(gx * gx + gz * gz), e * 0.85)
end

-- chunks (ci, cj) that hold window columns inside the radius, nearest the map's centre first
local function chunkList(ctx: any): { { number } }
	local st = ctx.st
	local list = {}
	for cj = ctx.wr0 // CH, ctx.wr1 // CH do
		for ci = ctx.wc0 // CH, ctx.wc1 // CH do
			local x0 = st.OX + VOX * max(ci * CH, ctx.wc0)
			local x1 = st.OX + VOX * (min(ci * CH + CH - 1, ctx.wc1) + 1)
			local z0 = st.OZ + VOX * max(cj * CH, ctx.wr0)
			local z1 = st.OZ + VOX * (min(cj * CH + CH - 1, ctx.wr1) + 1)
			local nx = math.clamp(0, x0, x1)
			local nz = math.clamp(0, z0, z1)
			if nx * nx + nz * nz <= ctx.R2 then
				local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
				list[#list + 1] = { ci, cj, mx * mx + mz * mz }
			end
		end
	end
	table.sort(list, function(a, b)
		if a[3] ~= b[3] then
			return a[3] < b[3]
		elseif a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[1] < b[1]
	end)
	return list
end

----------------------------------------------------------------------------------------------------
-- one chunk
----------------------------------------------------------------------------------------------------
-- scratch for the 18 x 18 columns of a chunk and its ring: c = (row in chunk + 1) * 18 + (column in chunk + 1) + 1
local cH, cW = table.create(324, EMPTY), table.create(324, EMPTY)
local cScale, cLowY, cSurf = table.create(324, 1), table.create(324, 0), table.create(324, EMPTY)
local cTopM, cSubM = table.create(324, AIR), table.create(324, AIR)
local cTopD, cSubD = table.create(324, 0), table.create(324, 0)
local cFull, cEmptyY = table.create(324, 0), table.create(324, 0)
local cNb = table.create(324, false)
local NB4 = { -1, 1, -18, 18 }

local function templates(ctx: any, nz: number)
	local t = ctx.tpl[nz]
	if not t then
		t = { table.create(nz, ctx.deep), table.create(nz, 1), table.create(nz, 0), table.create(nz, AIR) }
		ctx.tpl[nz] = t
	end
	return t
end

-- Fills the scratch with each column's ground and water and returns the chunk's box:
-- ia, ib, ja, jb (the window's columns and rows in this chunk), minY, maxY, wetAny. nil when nothing is written.
local function chunkBox(ctx: any, ci: number, cj: number)
	local st = ctx.st
	local N, H, W = st.N, st.H, st.W
	local OX, OZ = st.OX, st.OZ
	local wc0, wc1, wr0, wr1 = ctx.wc0, ctx.wc1, ctx.wr0, ctx.wr1
	local ia, ib = max(ci * CH, wc0), min(ci * CH + CH - 1, wc1)
	local ja, jb = max(cj * CH, wr0), min(cj * CH + CH - 1, wr1)
	if ia > ib or ja > jb then
		return nil
	end
	local R2, windowed, bank, wetBias = ctx.R2, ctx.windowed, ctx.bank, ctx.wetBias
	local minH, maxTop = HUGE, -HUGE
	local wetAny, inner = false, 0
	for j = ja - 1, jb + 1 do
		local zc = OZ + VOX * (j + 0.5)
		local rowOK = j >= wr0 and j <= wr1
		local base = (j - ja + 1) * 18 - ia + 2
		for i = ia - 1, ib + 1 do
			local h, w = EMPTY, EMPTY
			if rowOK and i >= wc0 and i <= wc1 then
				local xc = OX + VOX * (i + 0.5)
				if xc * xc + zc * zc <= R2 then
					local k2 = (j * N + i) * 2
					local hr, wr = readu16(H, k2), readu16(W, k2)
					h = hr * INV
					if wr > hr + 1.6 then
						if windowed and (i == wc0 or i == wc1 or j == wr0 or j == wr1) then
							h = wr * INV + bank
						else
							w = wr * INV
							h -= wetBias
							wetAny = true
						end
					end
					if h < minH then
						minH = h
					end
					local top = if w ~= EMPTY then w else h
					if top > maxTop then
						maxTop = top
					end
					if i >= ia and i <= ib and j >= ja and j <= jb then
						inner += 1
					end
				end
			end
			local c = base + i
			cH[c] = h
			cW[c] = w
		end
	end
	if inner == 0 then
		return nil
	end
	-- the shell: thick where the chunk reaches inside shellRadius
	local x0, x1 = OX + VOX * ia, OX + VOX * (ib + 1)
	local z0, z1 = OZ + VOX * ja, OZ + VOX * (jb + 1)
	local nxp, nzp = math.clamp(0, x0, x1), math.clamp(0, z0, z1)
	local shell = if nxp * nxp + nzp * nzp <= ctx.shellR2 then ctx.shellInner else ctx.shellOuter
	local minY = floor((minH - shell) / VOX) * VOX
	local maxY = ceil((maxTop + ctx.headroom) / VOX) * VOX + VOX
	return ia, ib, ja, jb, minY, maxY, wetAny
end

local function writeChunk(ctx: any, ci: number, cj: number): boolean
	local t0 = os.clock()
	local ia, ib, ja, jb, minY, maxY, wetAny = chunkBox(ctx, ci, cj)
	if not ia then
		return false
	end
	local st = ctx.st
	local N, H, M, NW = st.N, st.H, st.M, st.nearW
	local nx, nz = ib - ia + 1, jb - ja + 1
	local ny = (maxY - minY) // VOX
	local DEEP = ctx.deep
	local slotTop, slotSub = ctx.slotTop, ctx.slotSub
	local topDepth, subExtra, topMax = ctx.topDepth, ctx.subDepth - ctx.topDepth, ctx.topMax
	local steepNormal, steepFloor = ctx.steepNormal, ctx.steepFloor
	local containExtra, containMin = ctx.containExtra, ctx.containMin

	-- per column: steepness, materials, how deep the column is plain rock, where it is empty
	for j = ja, jb do
		local jd = if j > 0 then j - 1 else j
		local ju = if j < N - 1 then j + 1 else j
		local base = (j - ja + 1) * 18 - ia + 2
		for i = ia, ib do
			local c = base + i
			local h = cH[c]
			if h ~= EMPTY then
				local il = if i > 0 then i - 1 else i
				local ir = if i < N - 1 then i + 1 else i
				local hl, hr = readu16(H, (j * N + il) * 2) * INV, readu16(H, (j * N + ir) * 2) * INV
				local hd, hu = readu16(H, (jd * N + i) * 2) * INV, readu16(H, (ju * N + i) * 2) * INV
				local hdl, hdr = readu16(H, (jd * N + il) * 2) * INV, readu16(H, (jd * N + ir) * 2) * INV
				local hul, hur = readu16(H, (ju * N + il) * 2) * INV, readu16(H, (ju * N + ir) * 2) * INV
				local scale = 1
				if steepNormal then
					local gx, gz = (hr - hl) * 0.125, (hu - hd) * 0.125
					local e = max(abs(hr - h), abs(hl - h), abs(hu - h), abs(hd - h)) * 0.25
					local g = max(sqrt(gx * gx + gz * gz), e * 0.85)
					if g > TAN42 then
						-- a Sobel gradient for the normal: smoother than central differences on rough faces
						local sx = ((hr - hl) * 2 + (hur - hul) + (hdr - hdl)) / 32
						local sz = ((hu - hd) * 2 + (hur - hdr) + (hul - hdl)) / 32
						local nY = 1 / sqrt(1 + sx * sx + sz * sz)
						scale = 1 + (nY - 1) * sstep(45, 70, deg(atan(g)))
						if scale < steepFloor then
							scale = steepFloor
						end
					end
				end
				cScale[c] = scale
				local nw = readu16(NW, (j * N + i) * 2)
				cLowY[c] = if nw ~= 0 then nw * INV + 3 else -HUGE
				local slot = readu8(M, j * N + i)
				cTopM[c] = slotTop[slot] or DEEP
				cSubM[c] = slotSub[slot] or DEEP
				-- the top material covers everything of the column a lower neighbour leaves in view
				local low = min(hl, hr, hd, hu, hdl, hdr, hul, hur)
				local td = h - low + 2
				if td < topDepth then
					td = topDepth
				end
				if scale < 1 and 4 / scale + 4.5 > td then
					td = 4 / scale + 4.5 -- a steep face is part-filled this far down before the first full voxel
				end
				if td > topMax and cTopM[c] ~= cSubM[c] then
					td = topMax
				end
				local sd = td + subExtra
				cTopD[c], cSubD[c] = td, sd
				local reach = 4 / scale
				if reach < sd then
					reach = sd
				end
				cFull[c] = h - reach
				local w = cW[c]
				local top = h
				if w ~= EMPTY then
					top = w + 2
					cSurf[c] = ceil(w / VOX) * VOX - VOX
				else
					cSurf[c] = EMPTY
				end
				local nb = false
				if wetAny then
					for d = 1, 4 do
						local wn = cW[c + NB4[d]]
						if wn ~= EMPTY then
							nb = true
							if wn + 2 > top then
								top = wn + 2
							end
						end
					end
				end
				cNb[c] = nb
				cEmptyY[c] = top
			end
		end
	end

	-- the voxel arrays [x][y][z]. Rows (one x, one y, all z) that are plain rock or plain air are shared tables.
	local tpl = templates(ctx, nz)
	local fullM, fullO, zero, airM = tpl[1], tpl[2], tpl[3], tpl[4]
	local mats, occs, liqs = table.create(nx), table.create(nx), table.create(nx)
	local filled, solidRows = 0, 0
	for ix = 1, nx do
		local rowFull, rowEmpty = HUGE, -HUGE
		for jz = 1, nz do
			local c = jz * 18 + ix + 1
			if cH[c] == EMPTY then
				rowFull = -HUGE
			else
				if cFull[c] < rowFull then
					rowFull = cFull[c]
				end
				if cEmptyY[c] > rowEmpty then
					rowEmpty = cEmptyY[c]
				end
			end
		end
		-- layer iy has its centre at minY + 4 * (iy - 1) + 2
		local nFull = 0
		if rowFull > -HUGE then
			nFull = floor((rowFull - minY - 2) / VOX) + 1
			if nFull < 0 then
				nFull = 0
			elseif nFull > ny then
				nFull = ny
			end
		end
		local firstEmpty = 1
		if rowEmpty > -HUGE then
			firstEmpty = ceil((rowEmpty - minY - 2) / VOX) + 1
		end
		if firstEmpty <= nFull then
			firstEmpty = nFull + 1
		elseif firstEmpty > ny + 1 then
			firstEmpty = ny + 1
		end
		local mx, ox, lx = table.create(ny), table.create(ny), table.create(ny)
		for iy = 1, nFull do
			mx[iy], ox[iy], lx[iy] = fullM, fullO, zero
		end
		for iy = nFull + 1, firstEmpty - 1 do
			mx[iy], ox[iy], lx[iy] = table.clone(airM), table.clone(zero), table.clone(zero)
		end
		for iy = firstEmpty, ny do
			mx[iy], ox[iy], lx[iy] = airM, zero, zero
		end
		solidRows += nFull
		mats[ix], occs[ix], liqs[ix] = mx, ox, lx
		for jz = 1, nz do
			local c = jz * 18 + ix + 1
			local h = cH[c]
			if h ~= EMPTY then
				local w, yFull, scale, lowY, surf = cW[c], cFull[c], cScale[c], cLowY[c], cSurf[c]
				local tM, sM, tD, sD, nb = cTopM[c], cSubM[c], cTopD[c], cSubD[c], cNb[c]
				local last = ceil((cEmptyY[c] - minY - 2) / VOX)
				if last > firstEmpty - 1 then
					last = firstEmpty - 1
				end
				for iy = nFull + 1, last do
					local y0 = minY + (iy - 1) * VOX
					local yc = y0 + 2
					if yc <= yFull then
						mx[iy][jz] = DEEP
						ox[iy][jz] = 1
					else
						local below = h - yc
						local occ = below
						if scale < 1 and yc >= lowY then
							occ = below * scale
						end
						occ *= 0.25
						if occ > 1 then
							occ = 1
						elseif occ < 0 then
							occ = 0
						end
						if y0 == surf then
							occ = 0 -- the voxel that holds the water surface holds no solid
						end
						local liquid = 0
						if w ~= EMPTY and occ < 1 and w > y0 then
							liquid = (w - y0) * 0.25
							if liquid > 1 then
								liquid = 1
							end
						end
						if nb and liquid <= 0.001 then
							-- containment: the neighbour's water at this layer, from its own unmodified column
							for d = 1, 4 do
								local cn = c + NB4[d]
								local wn = cW[cn]
								if wn ~= EMPTY and wn > y0 and (cH[cn] - yc < 4 or y0 == ceil(wn / VOX) * VOX - VOX) then
									local need = (wn - y0) * 0.25
									if need > 1 then
										need = 1
									end
									if need > 0.02 then
										need += containExtra
										if need > 1 then
											need = 1
										elseif need < containMin then
											need = containMin
										end
										if occ < need then
											occ = need
											filled += 1
										end
									end
								end
							end
						end
						if occ > 0 then
							mx[iy][jz] = if below < tD then tM elseif below < sD then sM else DEEP
							ox[iy][jz] = occ
						end
						if liquid > 0 then
							lx[iy][jz] = liquid
						end
					end
				end
			end
		end
	end

	local region = Region3.new(
		Vector3.new(st.OX + VOX * ia + ctx.ox, minY + ctx.oy, st.OZ + VOX * ja + ctx.oz),
		Vector3.new(st.OX + VOX * (ib + 1) + ctx.ox, maxY + ctx.oy, st.OZ + VOX * (jb + 1) + ctx.oz)
	)
	local channels = ctx.channels
	channels.SolidMaterial, channels.SolidOccupancy, channels.LiquidOccupancy = mats, occs, liqs
	local t1 = os.clock()
	if not ctx.dry then
		ctx.terrain:WriteVoxelChannels(region, VOX, channels)
	end
	local t2 = os.clock()
	local count = nx * ny * nz
	ctx.chunks += 1
	ctx.voxels += count
	ctx.solidRows += solidRows
	ctx.filled += filled
	ctx.luaTime += t1 - t0
	ctx.engineTime += t2 - t1
	if count > ctx.maxCall then
		ctx.maxCall = count
	end
	if ny > ctx.maxNy then
		ctx.maxNy = ny
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- windows
----------------------------------------------------------------------------------------------------
-- the window that covers a box given in map studs (not offset)
function Writer.windowBox(minX: number, maxX: number, minZ: number, maxZ: number, packName: string?)
	local st = prepare(packName)
	local n = st.N
	return {
		col0 = math.clamp(floor((minX - st.OX) / VOX), 0, n - 1),
		col1 = math.clamp(ceil((maxX - st.OX) / VOX) - 1, 0, n - 1),
		row0 = math.clamp(floor((minZ - st.OZ) / VOX), 0, n - 1),
		row1 = math.clamp(ceil((maxZ - st.OZ) / VOX) - 1, 0, n - 1),
	}
end

function Writer.windowAround(x: number, z: number, radius: number, packName: string?)
	return Writer.windowBox(x - radius, x + radius, z - radius, z + radius, packName)
end

-- the world box (studs) a run with these options writes into: minX, maxX, minZ, maxZ
local function worldBox(ctx: any): (number, number, number, number)
	local st = ctx.st
	return st.OX + VOX * ctx.wc0 + ctx.ox, st.OX + VOX * (ctx.wc1 + 1) + ctx.ox, st.OZ + VOX * ctx.wr0 + ctx.oz, st.OZ + VOX * (ctx.wr1 + 1) + ctx.oz
end

----------------------------------------------------------------------------------------------------
-- clearing (never Terrain:Clear: the lobby island is terrain too)
----------------------------------------------------------------------------------------------------
local function lobbyInside(minX: number, maxX: number, minZ: number, maxZ: number, margin: number): boolean
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return false
	end
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			local p = d.Position
			if p.X > minX - margin and p.X < maxX + margin and p.Z > minZ - margin and p.Z < maxZ + margin then
				return true
			end
		end
	end
	return false
end

-- Empties the terrain in a world box, in tiles, with FillRegion Air. opts: minY, maxY, tile, allowLobby.
function Writer.clearRegion(minX: number, maxX: number, minZ: number, maxZ: number, opts: any?): string
	assert(not RunService:IsRunning(), "Map1.Terrain works in Edit mode only")
	local o = opts or {}
	local P = Writer.Params
	local x0, x1 = floor(minX / VOX) * VOX, ceil(maxX / VOX) * VOX
	local z0, z1 = floor(minZ / VOX) * VOX, ceil(maxZ / VOX) * VOX
	local y0 = floor((o.minY or P.clearMinY) / VOX) * VOX
	local y1 = ceil((o.maxY or P.clearMaxY) / VOX) * VOX
	if x1 <= x0 or z1 <= z0 or y1 <= y0 then
		error("Map1.Terrain.clearRegion: the box is empty")
	end
	if not o.allowLobby and lobbyInside(x0, x1, z0, z1, 160) then
		error("Map1.Terrain.clearRegion: the lobby stands in or beside this box (pass allowLobby = true to clear it anyway)")
	end
	local tile = o.tile or P.clearTile
	local terrain = workspace.Terrain
	local started = os.clock()
	local tiles = 0
	sliceSeconds = P.sliceSeconds
	sliceStart = os.clock()
	for x = x0, x1 - 1, tile do
		for z = z0, z1 - 1, tile do
			terrain:FillRegion(
				Region3.new(Vector3.new(x, y0, z), Vector3.new(min(x + tile, x1), y1, min(z + tile, z1))),
				VOX,
				AIR
			)
			tiles += 1
			maybeYield()
		end
	end
	return string.format(
		"cleared x %d..%d, z %d..%d, y %d..%d: %d tiles in %.1fs", x0, x1, z0, z1, y0, y1, tiles, os.clock() - started
	)
end

-- The classic forest arena's terrain. Its voxel grid ran from -960 to 960 on x and z and its terrain reaches
-- r 924 and y 6..451 (measured in Studio on 15 November 2026). opts: half, minY, maxY, centre (Vector3).
function Writer.clearOldArena(opts: any?): string
	local o = opts or {}
	local half = o.half or Writer.Params.oldArenaHalf
	local centre = o.centre or Vector3.zero
	return Writer.clearRegion(centre.X - half, centre.X + half, centre.Z - half, centre.Z + half, {
		minY = o.minY or -64,
		maxY = o.maxY or 640,
		tile = o.tile,
		allowLobby = o.allowLobby,
	})
end

----------------------------------------------------------------------------------------------------
-- preflight: the data against the rules the writer relies on. Reads only.
----------------------------------------------------------------------------------------------------
function Writer.preflight(opts: any?): string
	local o = opts or {}
	local st = prepare(o.pack)
	local n, H, W, M = st.N, st.H, st.W, st.M
	local spec = st.spec
	local lines, bad = {}, 0
	local function report(ok: boolean, text: string)
		if not ok then
			bad += 1
		end
		table.insert(lines, (if ok then "ok    " else "WRONG ") .. text)
	end
	-- water
	local levels, leaks, worstLeak, steps, deepRule = {}, 0, 0, 0, 0
	local minDepth, maxDepth = HUGE, 0
	for _, k in ipairs(st.wetCells) do
		local j = k // n
		local i = k - j * n
		local wr, hr = readu16(W, k * 2), readu16(H, k * 2)
		levels[wr] = (levels[wr] or 0) + 1
		local w = wr * INV
		local into = w - (ceil(w / VOX) * VOX - VOX) -- how far the level sits into its voxel layer (0 < into <= 4)
		if into < 0.5 - 1e-6 or into > 2 + 1e-6 then
			deepRule += 1
		end
		local depth = (wr - hr) * INV
		minDepth, maxDepth = min(minDepth, depth), max(maxDepth, depth)
		for d = 1, 4 do
			local ii = i + (if d == 1 then -1 elseif d == 2 then 1 else 0)
			local jj = j + (if d == 3 then -1 elseif d == 4 then 1 else 0)
			if ii >= 0 and jj >= 0 and ii < n and jj < n then
				local kk = (jj * n + ii) * 2
				local hn, wn = readu16(H, kk), readu16(W, kk)
				if wn > hn + 1.6 then
					if wn ~= wr then
						steps += 1 -- two pools of different levels touch: there should be a dry sill between them
					end
				elseif hn < wr - 3.2 then
					leaks += 1 -- dry ground beside the water and more than 0.1 below it
					worstLeak = max(worstLeak, (wr - hn) * INV)
				end
			end
		end
	end
	local levelList = {}
	for wr, count in pairs(levels) do
		table.insert(levelList, { wr, count })
	end
	table.sort(levelList, function(a, b)
		return a[1] < b[1]
	end)
	local levelText = {}
	for _, e in ipairs(levelList) do
		table.insert(levelText, string.format("%.2f (%d)", e[1] * INV, e[2]))
	end
	table.insert(lines, string.format("water: %d wet cells, depth %.2f..%.2f, levels %s", #st.wetCells, if minDepth == HUGE then 0 else minDepth, maxDepth, table.concat(levelText, ", ")))
	report(st.levelNotAboveGround == 0, string.format("%d cells carry a water level that is not above their ground (written dry)", st.levelNotAboveGround))
	report(deepRule == 0, string.format("%d wet cells have a level outside 0.5..2 studs into its voxel layer (the voxel rule)", deepRule))
	report(steps == 0, string.format("%d wet neighbours with different levels and no sill between them (counted from both sides)", steps))
	report(leaks == 0, string.format("%d dry cells beside water lie more than 0.1 below it (worst %.2f); the containment pass banks them", leaks, worstLeak))
	maybeYield()
	-- slots and the heart
	local seen, unknown = {}, 0
	local knollOff, ringOff, knollN, ringN = 0, 0, 0, 0
	local plaza = spec.plaza or {}
	local knollY, ringY = tonumber(plaza.knollY) or 46, tonumber(plaza.plinthRingY) or 44.3
	local flatTo = tonumber(plaza.flatTo) or 50
	local ringR = tonumber((spec.radii or {}).plinthRing) or 150
	local lowest, highest = HUGE, -HUGE
	for j = 0, n - 1 do
		local zc = st.OZ + VOX * (j + 0.5)
		for i = 0, n - 1 do
			local k = j * n + i
			local slot = readu8(M, k)
			if not seen[slot] then
				seen[slot] = true
				if not Writer.Slots[slot] then
					unknown += 1
				end
			end
			local hr = readu16(H, k * 2)
			if hr < lowest then
				lowest = hr
			end
			if hr > highest then
				highest = hr
			end
		end
		if abs(zc) < ringR + 8 then
			for i = (n // 2) - 40, (n // 2) + 39 do
				local xc = st.OX + VOX * (i + 0.5)
				local r = sqrt(xc * xc + zc * zc)
				local h = readu16(H, (j * n + i) * 2) * INV
				if r < flatTo - 3 then
					knollN += 1
					knollOff = max(knollOff, abs(h - knollY))
				elseif r >= ringR - 2 and r <= ringR + 2 then
					ringN += 1
					ringOff = max(ringOff, abs(h - ringY))
				end
			end
		end
		if j % 64 == 0 then
			maybeYield()
		end
	end
	local slotList = {}
	for slot in pairs(seen) do
		table.insert(slotList, slot)
	end
	table.sort(slotList)
	local slotText = {}
	for _, slot in ipairs(slotList) do
		local info = Writer.Slots[slot]
		table.insert(slotText, string.format("%d=%s", slot, if info then info.top.Name else "?"))
	end
	table.insert(lines, string.format("heights %.2f..%.2f; slots in the data: %s", lowest * INV, highest * INV, table.concat(slotText, " ")))
	report(unknown == 0, string.format("%d slot ids in the data have no entry in Terrain.Slots (written as %s)", unknown, Writer.Params.deep.Name))
	report(knollOff <= 0.25, string.format("the knoll (r < %d): %d cells, at most %.3f off y %.2f", flatTo - 3, knollN, knollOff, knollY))
	report(ringOff <= 0.3, string.format("the plinth ring (r %d..%d): %d cells, at most %.3f off y %.2f", ringR - 2, ringR + 2, ringN, ringOff, ringY))
	table.insert(lines, 1, string.format("preflight %s: %s", st.pack, if bad == 0 then "the data fits the writer's rules" else bad .. " things are WRONG"))
	return table.concat(lines, "\n")
end

----------------------------------------------------------------------------------------------------
-- plan: what a run would write
----------------------------------------------------------------------------------------------------
function Writer.plan(opts: any?): string
	local o = opts or {}
	local st = prepare(o.pack)
	local ctx = context(st, o)
	local chunks, voxels, largest, tallest, wet = 0, 0, 0, 0, 0
	local inner, outer = 0, 0
	local nc = st.NC
	for _, c in ipairs(chunkList(ctx)) do
		local ia, ib, ja, jb, minY, maxY, wetAny = chunkBox(ctx, c[1], c[2])
		if ia then
			local count = (ib - ia + 1) * (jb - ja + 1) * ((maxY - minY) // VOX)
			chunks += 1
			voxels += count
			largest = max(largest, count)
			tallest = max(tallest, maxY - minY)
			if wetAny then
				wet += 1
			end
			local x0, x1 = st.OX + VOX * ia, st.OX + VOX * (ib + 1)
			local z0, z1 = st.OZ + VOX * ja, st.OZ + VOX * (jb + 1)
			local nxp, nzp = math.clamp(0, x0, x1), math.clamp(0, z0, z1)
			if nxp * nxp + nzp * nzp <= ctx.shellR2 then
				inner += count
			else
				outer += count
			end
		end
		if chunks % 256 == 0 then
			maybeYield()
		end
	end
	local minX, maxX, minZ, maxZ = worldBox(ctx)
	return string.format(
		"plan: %d chunks (%d with water), %d voxels (%d under the %d-stud shell, %d under the %d-stud shell), largest call %d voxels, tallest box %d studs; world box x %d..%d, z %d..%d; chunk grid %d x %d",
		chunks, wet, voxels, inner, ctx.shellInner, outer, ctx.shellOuter, largest, tallest, minX, maxX, minZ, maxZ, nc, nc
	)
end

----------------------------------------------------------------------------------------------------
-- look, streaming
----------------------------------------------------------------------------------------------------
-- base material -> Color3, from the slot tints of Terrain.json
local function lookColors(spec: any): { [Enum.Material]: Color3 }
	local chosen: { [Enum.Material]: number } = {}
	for id = 1, 63 do
		local slot = Writer.Slots[id]
		if slot and spec.materialSlots[tostring(id)] then
			local preferred = Writer.ColorSlot[slot.top.Name]
			if preferred == id or (preferred == nil and chosen[slot.top] == nil) then
				chosen[slot.top] = id
			end
		end
	end
	local colors = {}
	for material, id in pairs(chosen) do
		local tint = spec.materialSlots[tostring(id)].tint
		colors[material] = Color3.fromRGB(tint[1], tint[2], tint[3])
	end
	return colors
end

-- every base material the writer can put down
local function usedMaterials(): { Enum.Material }
	local seen, list = {}, {}
	local function add(material: Enum.Material?)
		if material and not seen[material] then
			seen[material] = true
			table.insert(list, material)
		end
	end
	for id = 1, 63 do
		local slot = Writer.Slots[id]
		if slot then
			add(slot.top)
			add(slot.sub)
		end
	end
	add(Writer.Params.deep)
	return list
end

-- What applyLook changes, as plain values: { colors = { Grass = { r, g, b } }, overrides = { Grass = "name" },
-- water = { r, g, b } }. Keep it (the vault's Settings) or hand it to restoreLook.
function Writer.lookSnapshot(): any
	local terrain = workspace.Terrain
	local snapshot = { colors = {}, overrides = {}, water = {} }
	for _, material in ipairs(usedMaterials()) do
		local c = terrain:GetMaterialColor(material)
		snapshot.colors[material.Name] = { floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5) }
		local ok, name = pcall(function()
			return MaterialService:GetBaseMaterialOverride(material)
		end)
		if ok then
			snapshot.overrides[material.Name] = name
		end
	end
	local w = terrain.WaterColor
	snapshot.water = { floor(w.R * 255 + 0.5), floor(w.G * 255 + 0.5), floor(w.B * 255 + 0.5) }
	return snapshot
end

-- Puts back a snapshot. With no argument it uses the one applyLook({ remember = true }) left in the Terrain
-- attribute Map1LookBefore, and removes that attribute.
function Writer.restoreLook(snapshot: any?): string
	local terrain = workspace.Terrain
	local fromAttribute = false
	if snapshot == nil then
		local text = terrain:GetAttribute("Map1LookBefore")
		if type(text) ~= "string" then
			return "no look to restore: the Terrain attribute Map1LookBefore is not set"
		end
		snapshot = HttpService:JSONDecode(text)
		fromAttribute = true
	end
	local count = 0
	for name, c in pairs(snapshot.colors or {}) do
		terrain:SetMaterialColor((MAT :: any)[name], Color3.fromRGB(c[1], c[2], c[3]))
		count += 1
	end
	for name, override in pairs(snapshot.overrides or {}) do
		MaterialService:SetBaseMaterialOverride((MAT :: any)[name], override)
	end
	if snapshot.water and snapshot.water[1] then
		terrain.WaterColor = Color3.fromRGB(snapshot.water[1], snapshot.water[2], snapshot.water[3])
	end
	if fromAttribute then
		terrain:SetAttribute("Map1LookBefore", nil)
	end
	return string.format("look restored: %d material colours, the overrides and the water colour", count)
end

-- One colour per base material from the Blender palette, the lake's water colour, and Roblox's own textures on
-- every material the writer uses (the classic arena's LS_ overrides come off those materials). The water colour is
-- the lighting look's when Shared.DayCycle has one for this map (else the export's). The other water properties,
-- the grass and the lighting are left as they are: WorldGen.LightingRig.apply() writes those. This changes the whole place, the lobby island
-- included. opts.pack, opts.overrides = false (leave the overrides alone), opts.remember = true (keep what was
-- there in the Terrain attribute Map1LookBefore, for restoreLook() with no argument: a look put on for a test).
function Writer.applyLook(opts: any?): string
	local o = opts or {}
	local Data = loadData()
	Data.open(o.pack or Writer.PACK)
	Data.load({ "Terrain" })
	local spec = Data.terrain()
	local terrain = workspace.Terrain
	if o.remember and terrain:GetAttribute("Map1LookBefore") == nil then
		terrain:SetAttribute("Map1LookBefore", HttpService:JSONEncode(Writer.lookSnapshot()))
	end
	local notes = {}
	for material, color in pairs(lookColors(spec)) do
		terrain:SetMaterialColor(material, color)
		table.insert(notes, string.format("%s (%d,%d,%d)", material.Name, floor(color.R * 255 + 0.5), floor(color.G * 255 + 0.5), floor(color.B * 255 + 0.5)))
	end
	table.sort(notes)
	local removed = {}
	if o.overrides ~= false then
		for _, material in ipairs(usedMaterials()) do
			local ok, name = pcall(function()
				return MaterialService:GetBaseMaterialOverride(material)
			end)
			if ok and name ~= "" and name ~= material.Name then
				-- a base material's own name is "no override" (MaterialService's <Material>Name default)
				MaterialService:SetBaseMaterialOverride(material, material.Name)
				table.insert(removed, material.Name .. " (was " .. name .. ")")
			end
		end
		table.sort(removed)
	end
	local water = spec.lake and spec.lake.waterColor
	-- the lighting look owns the water (Shared.DayCycle.StaticSets.GreenLand, written by WorldGen.LightingRig): its
	-- colour wins over the Blender export's, so the two never disagree
	do
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		local module = shared and shared:FindFirstChild("DayCycle")
		if module then
			local ok, DayCycle = pcall(function()
				local copy = module:Clone()
				local result = require(copy)
				copy:Destroy()
				return result
			end)
			local static = ok and type(DayCycle) == "table" and DayCycle.StaticSets and DayCycle.StaticSets.GreenLand
			local c = static and static.WaterColor
			if typeof(c) == "Color3" then
				water = { floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5) }
			end
		end
	end
	if water then
		terrain.WaterColor = Color3.fromRGB(water[1], water[2], water[3])
	end
	return string.format(
		"look: %s; water (%s); overrides removed: %s",
		table.concat(notes, ", "),
		if water then table.concat(water, ",") else "unchanged",
		if #removed > 0 then table.concat(removed, ", ") else "none"
	)
end

-- the classic numbers (TerrainGen.applyStreaming) with ArenaV3 7.4's StreamOutBehavior
function Writer.applyStreaming(): string
	workspace.StreamingEnabled = true
	workspace.StreamingTargetRadius = 1024
	workspace.StreamingMinRadius = 128
	-- Opportunistic (docs/design/ArenaV3.md 7.4): what lies beyond the target radius streams out again. With Default a
	-- client kept everything it had passed (measured 18 Nov: 20,253 of 25,567 loaded plants were beyond 1,024 studs).
	workspace.StreamOutBehavior = Enum.StreamOutBehavior.Opportunistic
	workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.PauseOutsideLoadedArea
	return "streaming: target 1024, minimum 128, StreamOutBehavior Opportunistic, PauseOutsideLoadedArea"
end

----------------------------------------------------------------------------------------------------
-- the Boundary: an invisible backstop ring fitted to the ground at Params.boundaryRadius
----------------------------------------------------------------------------------------------------
-- opts: parent (default workspace.Arena), offset (Vector3), radius, walls, above, below, pack, dry (measure only)
function Writer.buildBoundary(opts: any?): string
	assert(not RunService:IsRunning(), "Map1.Terrain works in Edit mode only")
	local o = opts or {}
	local P = Writer.Params
	local st = prepare(o.pack)
	local Data = st.Data
	local R = o.radius or st.boundaryRadius
	local count = o.walls or P.boundaryWalls
	local above, below = o.above or P.boundaryAbove, o.below or P.boundaryBelow
	local offset = o.offset or Vector3.zero
	local parent = o.parent
	if parent == nil then
		parent = workspace:FindFirstChild("Arena")
	end
	if not parent and not o.dry then
		return "no workspace.Arena"
	end
	local model = nil
	if not o.dry then
		model = parent:FindFirstChild("Boundary")
		if not model then
			model = Instance.new("Model")
			model.Name = "Boundary"
			model.Parent = parent
		end
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				child:Destroy()
			end
		end
		model:SetAttribute("Radius", R)
	end
	local width = 2 * R * sin(math.pi / count) + 2
	local lowest, highest, tallest = HUGE, -HUGE, 0
	local step = 360 / count
	for index = 1, count do
		-- bearings as ArenaLayout.polar: 0 = north (-Z), clockwise
		local mid = (index - 0.5) * step
		local hmin, hmax = HUGE, -HUGE
		for t = -0.5, 0.5, 0.125 do
			local a = rad(mid + t * step)
			local sa, ca = sin(a), cos(a)
			-- the ground the wall stands on, and the ground a contender can stand on just inside it
			for dr = -64, 12, 4 do
				local r = R + dr
				local h = Data.heightAt(sa * r, -ca * r)
				if dr >= -12 and h < hmin then
					hmin = h
				end
				if h > hmax then
					hmax = h
				end
			end
		end
		local bottom, top = hmin - below, hmax + above
		local a = rad(mid)
		local centre = Vector3.new(sin(a) * (R + 2), (bottom + top) / 2, -cos(a) * (R + 2)) + offset
		if model then
			local wall = Instance.new("Part")
			wall.Name = string.format("Wall%03d", index)
			wall.Size = Vector3.new(width, top - bottom, 4)
			wall.CFrame = CFrame.lookAt(centre, Vector3.new(offset.X, centre.Y, offset.Z))
			wall.Anchored = true
			wall.CanCollide = true
			wall.CanTouch = false
			wall.CanQuery = false
			wall.CastShadow = false
			wall.Transparency = 1
			wall.Material = Enum.Material.SmoothPlastic
			CollectionService:AddTag(wall, "NoMantle")
			wall.Parent = model
		end
		lowest, highest, tallest = min(lowest, bottom), max(highest, top), max(tallest, top - bottom)
		if index % 24 == 0 then
			maybeYield()
		end
	end
	return string.format(
		"Boundary: %d walls at r=%d, %.1f wide, y %.0f..%.0f, tallest %.0f (%d above the ground within 64 studs inside)%s",
		count, R, width, lowest + offset.Y, highest + offset.Y, tallest, above, if o.dry then " [measured only, nothing built]" else ""
	)
end

----------------------------------------------------------------------------------------------------
-- the run
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
-- the ground under a landmark shell (the Peak)
----------------------------------------------------------------------------------------------------
-- The Peak is a mesh shell on top of a lower hill of real terrain. Its collision is solid from the skin down to a
-- flat underside at the model's base (y 190), and on its north side the real ground lies 10 to 110 studs under that
-- base: the skirt hung in the air over about 380 studs of rim, a player walked in under it and, the skin being
-- one-sided, looked out unseen (found in play, 18 Nov). fillUnder raises the ground in every column under the model
-- to just under its underside. The result is a steep bank of terrain that meets the skirt all round.
-- Map1.Audit's "peak" check fails while any rim column is open. A new terrain write puts the hill back as the data
-- has it: run fillUnder again after it (and after placeLandmarks).
--   opts.model   the landmark (default workspace.Arena.Landmarks.Peak)
--   opts.gap     a column is open when its underside is more than this over the ground (default 3: less than a body)
--   opts.under   the fill stops this far under the underside (default 0: up to it)
--   opts.widen   each column's block is this much wider than the step (default 4: a block the size of one column
--                only half fills its voxels, and the smooth surface then sags between columns; cracks 3 to 17
--                studs high were left that way on the first run)
--   opts.step    studs between columns (default 4, the voxel size)
--   opts.passes  the survey and fill are repeated up to this many times while columns are still open (default 3)
local function underSurvey(o: any): (any, string?)
	local model = o.model
	if model == nil then
		local arena = workspace:FindFirstChild("Arena")
		local landmarks = arena and arena:FindFirstChild("Landmarks")
		model = landmarks and landmarks:FindFirstChild("Peak")
	end
	if not model then
		return nil, "no landmark (workspace.Arena.Landmarks.Peak is missing)"
	end
	local step = o.step or 4
	local gap = o.gap or 3
	local cf, size = model:GetBoundingBox()
	local x0 = floor((cf.Position.X - size.X / 2) / step) * step + step / 2
	local x1 = cf.Position.X + size.X / 2
	local z0 = floor((cf.Position.Z - size.Z / 2) / step) * step + step / 2
	local z1 = cf.Position.Z + size.Z / 2
	local top = cf.Position.Y + size.Y / 2 + 50
	local meshParams = RaycastParams.new()
	meshParams.FilterType = Enum.RaycastFilterType.Include
	meshParams.FilterDescendantsInstances = { model }
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	groundParams.IgnoreWater = true
	local reach = top + 600
	local out = { model = model, step = step, columns = {}, footprint = 0, open = 0, rim = 0, rimOpen = 0, largest = 0, sample = nil }
	local covered: { [number]: boolean } = {}
	local nz = floor((z1 - z0) / step) + 1
	local i = 0
	local x = x0
	while x <= x1 do
		local j = 0
		local z = z0
		while z <= z1 do
			local skin = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -reach, 0), meshParams)
			if skin then
				out.footprint += 1
				covered[i * (nz + 2) + j] = true
				local under = workspace:Raycast(Vector3.new(x, top - reach, z), Vector3.new(0, reach, 0), meshParams)
				local underY = if under then under.Position.Y else skin.Position.Y
				local ground = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -reach, 0), groundParams)
				if ground and underY - ground.Position.Y > gap then
					out.open += 1
					out.largest = max(out.largest, underY - ground.Position.Y)
					table.insert(out.columns, { x = x, z = z, i = i, j = j, ground = ground.Position.Y, under = underY, material = ground.Material })
				end
			end
			j += 1
			z += step
		end
		i += 1
		x += step
		if i % 24 == 0 then
			task.wait()
		end
	end
	-- the rim: columns under the model with a neighbour that is not; an open one is a way in
	local function isCovered(a: number, b: number): boolean
		return covered[a * (nz + 2) + b] == true
	end
	for key in pairs(covered) do
		local a, b = key // (nz + 2), key % (nz + 2)
		if not (isCovered(a + 1, b) and isCovered(a - 1, b) and isCovered(a, b + 1) and isCovered(a, b - 1)) then
			out.rim += 1
		end
	end
	for _, c in ipairs(out.columns) do
		if not (isCovered(c.i + 1, c.j) and isCovered(c.i - 1, c.j) and isCovered(c.i, c.j + 1) and isCovered(c.i, c.j - 1)) then
			out.rimOpen += 1
			if not out.sample then
				out.sample = string.format("(%.0f, %.0f): ground %.0f, underside %.0f", c.x, c.z, c.ground, c.under)
			end
		end
	end
	return out, nil
end

function Writer.surveyUnder(opts: any?): (string, any)
	local s, problem = underSurvey(opts or {})
	if not s then
		return "surveyUnder: " .. tostring(problem), nil
	end
	return string.format("%s: %d columns under it (every %d studs), %d open (underside more than %g over the ground, the largest by %.0f); rim columns %d, open %d%s",
		s.model:GetFullName(), s.footprint, s.step, s.open, (opts and opts.gap) or 3, s.largest, s.rim, s.rimOpen,
		if s.sample then "; e.g. " .. s.sample else ""), s
end

function Writer.fillUnder(opts: any?): string
	assert(not RunService:IsRunning(), "Map1.Terrain works in Edit mode only")
	local o = opts or {}
	local s, problem = underSurvey(o)
	if not s then
		return "fillUnder: " .. tostring(problem)
	end
	local keep = o.under or 0
	local wide = (o.step or 4) + (o.widen or 4)
	local terrain = workspace.Terrain
	local filled, volume = 0, 0
	local first = s
	local after = s
	for _ = 1, o.passes or 3 do
		if after.open == 0 then
			break
		end
		for n, c in ipairs(after.columns) do
			local lo, hi = c.ground - 4, c.under - keep
			if hi - lo > 0.5 then
				local material = c.material
				if material == MAT.Air or material == MAT.Water then
					material = MAT.Rock
				end
				terrain:FillBlock(CFrame.new(c.x, (lo + hi) / 2, c.z), Vector3.new(wide, hi - lo, wide), material)
				filled += 1
				volume += (hi - lo) * s.step * s.step
			end
			if n % 400 == 0 then
				task.wait()
			end
		end
		task.wait(0.3) -- rays just after a write meet the old collision mesh
		after = underSurvey(o) or after
	end
	return string.format("fillUnder %s: %d of %d columns under it were open (the largest gap %.0f studs; %d on the rim); filled %d columns, about %d voxels. After: %d open, %d on the rim",
		first.model:GetFullName(), first.open, first.footprint, first.largest, first.rimOpen, filled, floor(volume / 64), after.open, after.rimOpen)
end

function Writer.status(): string
	local terrain = workspace.Terrain
	return string.format("%s | %s", tostring(terrain:GetAttribute("Map1Status")), tostring(terrain:GetAttribute("Map1Progress")))
end

-- removes the two attributes a run leaves on workspace.Terrain
function Writer.clearStatus()
	workspace.Terrain:SetAttribute("Map1Status", nil)
	workspace.Terrain:SetAttribute("Map1Progress", nil)
end

-- The write, in the calling thread. Yields every Params.sliceSeconds of work. Returns the summary.
function Writer.run(opts: any?): string
	assert(not RunService:IsRunning(), "Map1.Terrain works in Edit mode only")
	local o = opts or {}
	local P = Writer.Params
	local started = os.clock()
	sliceSeconds = P.sliceSeconds
	sliceStart = os.clock()
	setStatus("running: reading the data pack", 0)
	local st = prepare(o.pack)
	local ctx = context(st, o)
	local minX, maxX, minZ, maxZ = worldBox(ctx)
	if not o.allowLobby and not ctx.dry then
		-- the written disc in world studs, cut to the window's box
		local R = ctx.R
		local bx0, bx1 = max(minX, ctx.ox - R), min(maxX, ctx.ox + R)
		local bz0, bz1 = max(minZ, ctx.oz - R), min(maxZ, ctx.oz + R)
		if lobbyInside(bx0, bx1, bz0, bz1, 120) then
			error("Map1.Terrain: the lobby stands inside the area to write. Move it first (Map1Build.md decision 3), or pass allowLobby = true")
		end
	end
	local notes = {}
	if o.clear and not ctx.dry then
		setStatus("running: clearing", 0.01)
		table.insert(notes, Writer.clearRegion(minX, maxX, minZ, maxZ, { allowLobby = o.allowLobby }))
	end
	local list = chunkList(ctx)
	local total = #list
	local prepared = os.clock() - started
	setStatus(string.format("running: voxels, %d chunks", total), 0.02)
	local writeStart = os.clock()
	for index, c in ipairs(list) do
		-- yield first when this chunk would take the slice past its limit
		maybeYield(if ctx.chunks > 0 then (ctx.luaTime + ctx.engineTime) / ctx.chunks else 0)
		writeChunk(ctx, c[1], c[2])
		if index % 16 == 0 then
			setStatus(string.format("running: voxels, chunk %d of %d", index, total), 0.02 + 0.96 * index / total)
		end
	end
	local wall = os.clock() - writeStart
	if ctx.dry then
		table.insert(notes, "DRY RUN: the arrays were built and timed, nothing was written")
	else
		if o.look then
			table.insert(notes, Writer.applyLook({ pack = o.pack }))
		end
		if o.streaming then
			table.insert(notes, Writer.applyStreaming())
		end
		if o.boundary then
			table.insert(notes, Writer.buildBoundary({ pack = o.pack, offset = o.offset }))
		end
	end
	local busy = ctx.luaTime + ctx.engineTime
	local summary = string.format(
		"done: %d chunks, %d voxels in %.1fs (data %.1fs; writing %.1fs by the clock: %.2fs building the arrays, %.2fs in WriteVoxelChannels; %.2f ms a chunk, %.0f ns a voxel); largest call %d voxels (%d layers); %d full rows shared; containment fills %d; world box x %d..%d, z %d..%d%s",
		ctx.chunks, ctx.voxels, os.clock() - started, prepared, wall, ctx.luaTime, ctx.engineTime,
		if ctx.chunks > 0 then 1000 * busy / ctx.chunks else 0,
		if ctx.voxels > 0 then 1e9 * busy / ctx.voxels else 0,
		ctx.maxCall, ctx.maxNy, ctx.solidRows, ctx.filled, minX, maxX, minZ, maxZ,
		if #notes > 0 then "; " .. table.concat(notes, "; ") else ""
	)
	setStatus(summary, 1)
	return summary
end

-- Starts the write on a background thread and returns at once. Progress: workspace.Terrain attributes Map1Status
-- (text; "done: ..." or "error: ..." at the end) and Map1Progress (0..1).
function Writer.generate(opts: any?): string
	assert(not RunService:IsRunning(), "Map1.Terrain works in Edit mode only")
	local o = opts or {}
	local current = workspace.Terrain:GetAttribute("Map1Status")
	if type(current) == "string" and string.sub(current, 1, 8) == "running:" and not o.force then
		error("Map1.Terrain: a run seems to be in progress (" .. current .. "); pass force = true if it died")
	end
	setStatus("running: starting", 0)
	task.spawn(function()
		local ok, err = xpcall(Writer.run, debug.traceback, o)
		if not ok then
			setStatus("error: " .. tostring(err))
			warn("[Map1.Terrain] " .. tostring(err))
		end
	end)
	return "started; watch workspace.Terrain Map1Status / Map1Progress"
end

----------------------------------------------------------------------------------------------------
-- verify: the written terrain against the grid (raycasts and voxel reads)
----------------------------------------------------------------------------------------------------
local function terrainParams(ignoreWater: boolean): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = ignoreWater
	return params
end

local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return 0
	end
	return sorted[math.clamp(ceil(#sorted * p), 1, #sorted)]
end

-- opts: offset, window, pack as for the run; samples (default 6000), seed, radius (check inside this radius only),
-- lattice (studs between lattice columns, default 16), tolerance (default 2)
function Writer.verify(opts: any?): string
	local o = opts or {}
	local P = Writer.Params
	sliceSeconds = P.sliceSeconds
	sliceStart = os.clock()
	local st = prepare(o.pack)
	local ctx = context(st, o)
	local n, H = st.N, st.H
	-- rays right after a write still meet the old collision mesh: give the engine a few frames first
	task.wait(o.settle or 0.3)
	local started = os.clock()
	local solid, wetParams = terrainParams(true), terrainParams(false)
	local topY = st.spec.heights and (st.spec.heights.max + 200) or 1400
	local rayFrom, rayDown = topY + ctx.oy, Vector3.new(0, -(topY + 400), 0)
	local tolerance = o.tolerance or 2
	local lines, failed = {}, 0
	local function report(ok: boolean, text: string)
		if not ok then
			failed += 1
		end
		table.insert(lines, (if ok then "PASS  " else "FAIL  ") .. text)
	end
	local function castGround(i: number, j: number): number?
		local x, z = st.OX + VOX * (i + 0.5) + ctx.ox, st.OZ + VOX * (j + 0.5) + ctx.oz
		local hit = workspace:Raycast(Vector3.new(x, rayFrom, z), rayDown, solid)
		return if hit then hit.Position.Y - ctx.oy else nil
	end

	-- 1. tops against the grid: random dry columns
	local want = o.samples or 6000
	local rng = Random.new(o.seed or 20261115)
	-- classes: 1 under 30 degrees, 2 30 to 46, 3 over 46, 4 beside water (the containment pass raises those banks),
	-- 5 at the foot of a wall: a neighbour stands more than Params.wallStep higher. A wall's face is drawn about 2
	-- studs out from its own column, over the middle of the column at its foot (measured on the Edge: the ray
	-- down the foot column meets the face 54 studs up), so that column's middle says nothing about its ground.
	local names = { "under 30 deg", "30 to 46 deg", "over 46 deg", "beside water", "foot of a wall" }
	local errs = { {}, {}, {}, {}, {} }
	local over = { 0, 0, 0, 0, 0 }
	local wallStep = P.wallStep
	local holes, taken, tries = 0, 0, 0
	local worst = {}
	while taken < want and tries < want * 40 do
		tries += 1
		local i, j = rng:NextInteger(ctx.wc0, ctx.wc1), rng:NextInteger(ctx.wr0, ctx.wr1)
		local h, w = target(ctx, i, j)
		if h and not w then
			taken += 1
			local class = 0
			for d = 1, 4 do
				local _, wn = target(ctx, i + (if d == 1 then -1 elseif d == 2 then 1 else 0), j + (if d == 3 then -1 elseif d == 4 then 1 else 0))
				if wn then
					class = 4
				end
			end
			local g = slopeTan(st, i, j)
			if class == 0 then
				class = if g < TAN30 then 1 elseif g <= TAN46 then 2 else 3
				if class == 3 then
					local k2 = (j * n + i) * 2
					local hr = readu16(H, k2) + wallStep * 32
					if (i > 0 and readu16(H, k2 - 2) > hr) or (i < n - 1 and readu16(H, k2 + 2) > hr)
						or (j > 0 and readu16(H, k2 - 2 * n) > hr) or (j < n - 1 and readu16(H, k2 + 2 * n) > hr) then
						class = 5
					end
				end
			end
			local y = castGround(i, j)
			if not y then
				holes += 1
			else
				local e = abs(y - h)
				table.insert(errs[class], e)
				if e > tolerance then
					over[class] += 1
					table.insert(worst, { e, i, j, y - h, deg(atan(g)), class })
				end
			end
			if taken % 200 == 0 then
				maybeYield()
			end
		end
	end
	local dryTotal, dryOver = 0, 0
	local detail = {}
	for class = 1, 5 do
		local list = errs[class]
		table.sort(list)
		local sum = 0
		for _, e in ipairs(list) do
			sum += e
		end
		if class < 4 then
			dryTotal += #list
			dryOver += over[class]
		end
		table.insert(detail, string.format(
			"      %-13s %5d columns: mean %.2f, 99th percentile %.2f, worst %.2f, %d more than %g off",
			names[class], #list, if #list > 0 then sum / #list else 0, percentile(list, 0.99), list[#list] or 0, over[class], tolerance
		))
	end
	table.sort(worst, function(a, b)
		return a[1] > b[1]
	end)
	for index = 1, min(8, #worst) do
		local e = worst[index]
		table.insert(detail, string.format(
			"      off by %+.2f at column %d, row %d (map x %d, z %d; %.0f deg; %s)",
			e[4], e[2], e[3], st.OX + VOX * e[2] + 2, st.OZ + VOX * e[3] + 2, e[5], names[e[6]]
		))
	end
	local gentleOK = over[1] == 0
	local share = if dryTotal > 0 then 1 - dryOver / dryTotal else 0
	report(
		taken >= min(want, 5000) and holes == 0 and gentleOK and share >= 0.99,
		string.format(
			"tops: %d random dry columns, %.2f%% within %g studs of the grid away from water and from the foot of a wall (every one under 30 degrees: %s), %d rays found no ground",
			taken, share * 100, tolerance, if gentleOK then "yes" else "NO", holes
		)
	)
	for _, line in ipairs(detail) do
		table.insert(lines, line)
	end
	maybeYield()

	-- 2. the lattice: no holes
	local stepCells = max(1, floor((o.lattice or 16) / VOX))
	local latticeN, latticeHoles, spikes = 0, 0, 0
	local holeAt = {}
	for j = ctx.wr0, ctx.wr1 do
		if j % stepCells == 0 then
			for i = ctx.wc0, ctx.wc1 do
				if i % stepCells == 0 then
					local h = target(ctx, i, j)
					if h then
						latticeN += 1
						local y = castGround(i, j)
						if not y then
							latticeHoles += 1
							if #holeAt < 6 then
								table.insert(holeAt, string.format("(%d,%d)", st.OX + VOX * i + 2, st.OZ + VOX * j + 2))
							end
						elseif abs(y - h) > 6 and slopeTan(st, i, j) < TAN30 then
							spikes += 1
						end
					end
				end
			end
			maybeYield()
		end
	end
	report(
		latticeN > 0 and latticeHoles == 0 and spikes == 0,
		string.format("lattice: %d columns every %d studs, %d holes %s, %d spikes (more than 6 off the grid under 30 degrees)", latticeN, stepCells * VOX, latticeHoles, table.concat(holeAt, " "), spikes)
	)

	-- 3 and 4. water: voxels beside or over pure air, solid at or above a water surface
	local terrain = workspace.Terrain
	local waterVox, exposed, visible, openBelow, solidAbove, drySurface, wetColumns = 0, 0, 0, 0, 0, 0, 0
	local where = {}
	local nc = st.NC
	for _, c in ipairs(chunkList(ctx)) do
		local ci, cj = c[1], c[2]
		if readu8(st.chunkWet, cj * nc + ci) == 1 then
			local ia, ib = max(ci * CH, ctx.wc0), min(ci * CH + CH - 1, ctx.wc1)
			local ja, jb = max(cj * CH, ctx.wr0), min(cj * CH + CH - 1, ctx.wr1)
			local bedMin, levelMax = HUGE, -HUGE
			for j = ja, jb do
				for i = ia, ib do
					local h, w = target(ctx, i, j)
					if w then
						bedMin, levelMax = min(bedMin, h), max(levelMax, w)
					end
				end
			end
			if levelMax > -HUGE then
				local y0 = floor((bedMin - 8) / VOX) * VOX
				local y1 = ceil((levelMax + 8) / VOX) * VOX
				local region = Region3.new(
					Vector3.new(st.OX + VOX * (ia - 1) + ctx.ox, y0 + ctx.oy, st.OZ + VOX * (ja - 1) + ctx.oz),
					Vector3.new(st.OX + VOX * (ib + 2) + ctx.ox, y1 + ctx.oy, st.OZ + VOX * (jb + 2) + ctx.oz)
				)
				local ch = terrain:ReadVoxelChannels(region, VOX, { "SolidOccupancy", "LiquidOccupancy" })
				local so, lo = ch.SolidOccupancy, ch.LiquidOccupancy
				local sy = #so[1]
				for j = ja, jb do
					for i = ia, ib do
						local ix, iz = i - ia + 2, j - ja + 2
						local sox, lox = so[ix], lo[ix]
						for iy = 1, sy do
							local l = lox[iy][iz]
							if l > 0.02 then
								waterVox += 1
								local open = (so[ix - 1][iy][iz] == 0 and lo[ix - 1][iy][iz] == 0)
									or (so[ix + 1][iy][iz] == 0 and lo[ix + 1][iy][iz] == 0)
									or (sox[iy][iz - 1] == 0 and lox[iy][iz - 1] == 0)
									or (sox[iy][iz + 1] == 0 and lox[iy][iz + 1] == 0)
								if open then
									exposed += 1
									if l > 0.25 then
										visible += 1
										if #where < 6 then
											table.insert(where, string.format("(%d,%d,%d)", st.OX + VOX * i + 2, y0 + (iy - 1) * VOX + 2, st.OZ + VOX * j + 2))
										end
									end
								end
								if iy > 1 and sox[iy - 1][iz] == 0 and lox[iy - 1][iz] == 0 then
									openBelow += 1
								end
							end
						end
						local _, w = target(ctx, i, j)
						if w then
							wetColumns += 1
							local surfaceIy = (ceil(w / VOX) * VOX - VOX - y0) // VOX + 1
							if lox[surfaceIy][iz] <= 0 then
								drySurface += 1
							end
							for iy = surfaceIy, sy do
								if sox[iy][iz] > 0 then
									solidAbove += 1
									break
								end
							end
						end
					end
				end
				maybeYield()
			end
		end
	end
	report(
		visible == 0 and openBelow == 0,
		string.format(
			"sealed water: %d water voxels in %d wet columns; %d beside pure air (%d of them more than a quarter full %s), %d over pure air",
			waterVox, wetColumns, exposed, visible, table.concat(where, " "), openBelow
		)
	)
	report(
		solidAbove == 0 and drySurface == 0,
		string.format("water surfaces: %d wet columns with solid in or above the voxel that holds the surface, %d whose surface voxel holds no water", solidAbove, drySurface)
	)

	-- The same from outside: a ray down the middle of each wet column finds the water surface, and the bed under
	-- it. Told apart: the lake's level, and the stream's pools (two or three cells wide, so a bank can lean over
	-- the middle of a cell). Up to 3,000 columns of each.
	local lakeLevel = tonumber(st.spec.lake and st.spec.lake.level) or 34
	local groups = {
		{ name = "at the lake's level", list = {} },
		{ name = "stream pools", list = {} },
	}
	for _, k in ipairs(st.wetCells) do
		local j = k // n
		local i = k - j * n
		local _, w = target(ctx, i, j)
		if w then
			table.insert(groups[if abs(w - lakeLevel) < 0.01 then 1 else 2].list, k)
		end
	end
	local rayBad = 0
	local rayText = {}
	for _, group in ipairs(groups) do
		local list = group.list
		local rayN, noSurface, offLevel, bedAbove, depthSum, designSum, shallowest = 0, 0, 0, 0, 0, 0, HUGE
		for index = 1, #list, max(1, #list // 3000) do
			local k = list[index]
			local j = k // n
			local i = k - j * n
			local h, w = target(ctx, i, j)
			rayN += 1
			local x, z = st.OX + VOX * (i + 0.5) + ctx.ox, st.OZ + VOX * (j + 0.5) + ctx.oz
			local top = workspace:Raycast(Vector3.new(x, rayFrom, z), rayDown, wetParams)
			local bed = workspace:Raycast(Vector3.new(x, rayFrom, z), rayDown, solid)
			local bedY = if bed then bed.Position.Y - ctx.oy else -HUGE
			if not top or top.Material ~= MAT.Water then
				noSurface += 1
			else
				local surfaceY = top.Position.Y - ctx.oy
				if abs(surfaceY - w) > 0.6 then
					offLevel += 1
				end
				depthSum += surfaceY - bedY
				designSum += w - h
				shallowest = min(shallowest, surfaceY - bedY)
			end
			if bedY > w - 0.05 then
				bedAbove += 1
			end
			if rayN % 200 == 0 then
				maybeYield()
			end
		end
		local seen = rayN - noSurface
		group.rayN, group.noSurface = rayN, noSurface
		rayBad += offLevel
		table.insert(rayText, string.format(
			"      %-20s %5d columns: %d with no water to hit from above, %d with ground at or above the level, %d with the surface more than 0.6 off its level; mean depth %.2f (the grid says %.2f), shallowest %.2f",
			group.name, rayN, noSurface, bedAbove, offLevel, if seen > 0 then depthSum / seen else 0, if seen > 0 then designSum / seen else 0, if shallowest == HUGE then 0 else shallowest
		))
	end
	-- the lake must show everywhere but its very rim; a stream cell may hide under its banks, most must not
	local lake, pools = groups[1], groups[2]
	local lakeOK = lake.rayN == 0 or lake.noSurface <= 0.02 * lake.rayN
	local poolsOK = pools.rayN == 0 or pools.noSurface <= 0.1 * pools.rayN
	report(
		rayBad == 0 and lakeOK and poolsOK,
		string.format(
			"water by raycast: the surface shows in %d of %d columns at the lake's level (at least 98%% wanted) and in %d of %d stream columns (at least 90%% wanted)",
			lake.rayN - lake.noSurface, lake.rayN, pools.rayN - pools.noSurface, pools.rayN
		)
	)
	for _, text in ipairs(rayText) do
		table.insert(lines, text)
	end
	-- Water faces, the classic writer's own check: a point where a ray finds water, beside a point 4 studs away
	-- with no water whose ground is more than 0.75 below that water. Points at cell centres and at cell corners.
	local boxX0, boxX1 = st.OX + VOX * ctx.wc0 + 2, st.OX + VOX * (ctx.wc1 + 1) - 2
	local boxZ0, boxZ1 = st.OZ + VOX * ctx.wr0 + 2, st.OZ + VOX * (ctx.wr1 + 1) - 2
	local groundAt, waterAt = {}, {}
	local function sample(sx: number, sz: number): (number, number?)
		local key = sx * 100003 + sz
		local gy = groundAt[key]
		if gy == nil then
			local from = Vector3.new(sx + ctx.ox, rayFrom, sz + ctx.oz)
			local ground = workspace:Raycast(from, rayDown, solid)
			local top = workspace:Raycast(from, rayDown, wetParams)
			gy = if ground then ground.Position.Y else -HUGE
			groundAt[key] = gy
			waterAt[key] = if top and top.Material == MAT.Water and top.Position.Y > gy + 0.05 then top.Position.Y else false
		end
		return gy, waterAt[key] or nil
	end
	local edges, faces, worstFace, faceAt = 0, 0, 0, ""
	local bands = { 0, 0, 0 }
	for _, group in ipairs(groups) do
		for index, k in ipairs(group.list) do
			local j = k // n
			local i = k - j * n
			for phase = 0, 2, 2 do
				local sx, sz = st.OX + VOX * i + phase, st.OZ + VOX * j + phase
				local _, wy = sample(sx, sz)
				if wy then
					for d = 1, 4 do
						local nx = sx + (if d == 1 then -VOX elseif d == 2 then VOX else 0)
						local nz = sz + (if d == 3 then -VOX elseif d == 4 then VOX else 0)
						if nx > boxX0 and nx < boxX1 and nz > boxZ0 and nz < boxZ1 and nx * nx + nz * nz < ctx.R2 then
							local gy2, wy2 = sample(nx, nz)
							if not wy2 then
								edges += 1
								local drop = wy - gy2
								if drop > 0.75 then
									faces += 1
									bands[if drop < 1.5 then 1 elseif drop < 3 then 2 else 3] += 1
									if drop > worstFace then
										worstFace = drop
										faceAt = string.format("(%d,%d)", nx, nz)
									end
								end
							end
						end
					end
				end
			end
			if index % 100 == 0 then
				maybeYield()
			end
		end
	end
	report(
		faces == 0,
		string.format(
			"water faces by raycast: %d edges between a wet point and a dry one; at %d the dry ground is more than 0.75 below the water (%d by 0.75 to 1.5, %d by 1.5 to 3, %d by more; worst %.2f %s)",
			edges, faces, bands[1], bands[2], bands[3], worstFace, faceAt
		)
	)
	local minX, maxX, minZ, maxZ = worldBox(ctx)
	table.insert(lines, 1, string.format("verify %s: world box x %d..%d, z %d..%d, %.1fs", st.pack, minX, maxX, minZ, maxZ, os.clock() - started))
	table.insert(lines, if failed == 0 then "verify: ALL PASS" else string.format("verify: %d FAILED", failed))
	return table.concat(lines, "\n")
end

return Writer
