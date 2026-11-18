--[[
	Map1.Data - typed access to the Map 1 data pack ("map1_data", written by tools/map1/pack.py from the Blender
	exports; the contract is docs/design/Map1Build.md 3.3). STUDIO ONLY: the pack is a local file that
	ServerStorage.Dev.StudioSync reads (open, blob). Nothing here runs in a live server; the game's own code reads
	ReplicatedStorage.Shared.Map1Regions instead.

	THE PACK
	  Height        1376 x 1376 uint16   y = value / 32
	  Material      1376 x 1376 uint8    slot ids (Map1_Terrain.json "materialSlots")
	  Region        1376 x 1376 uint8    region ids (Map1_Terrain.json "regions")
	  WaterLevel    1376 x 1376 uint16   y = value / 32 after the packer's repairs; 0 = dry
	  Mask_<Name>   688 x 688 uint8      density 0..255 on 8-stud cells: Conifer, Broadleaf, Gorse, Heather, Boulders,
	                                     Crags, TallGrass, Wildflowers
	  Terrain, Layout                    the two JSON files as text
	  Manifest_Landmarks, _Plants, _Skyline, _FarValley   the asset manifests as text
	All grids are row-major, row 0 at the north edge (z = -2752), little-endian. A cell is one 4-stud voxel column:
	its centre is x = -2752 + 4 * (col + 0.5), z = -2752 + 4 * (row + 0.5). Columns and rows count from 0.
	The grid facts (size, cell, origin) are read from the Terrain blob's "grid" when the pack opens.

	USE (Edit mode, execute_luau or another builder; Studio caches required modules, so require a clone):
	  local Data = require(game.ServerStorage.WorldGen.Map1.Data:Clone())
	  Data.load()                          -- opens the pack, decodes the four grids, Terrain and Layout, closes it
	  Data.load({ "Height", "Mask_Conifer" })   -- or only what you need (anything else still loads on first use)
	  Data.height(col, row)                -- studs, or nil outside the grid
	  Data.material(col, row)              -- slot id 1..10
	  Data.region(col, row)                -- region id 1..10
	  Data.waterLevel(col, row)            -- studs, or nil when the cell is dry
	  Data.heightAt(x, z)                  -- bilinear between cell centres (world x, z; the map's own frame)
	  Data.cellAt(x, z) -> col, row        -- the cell that holds the point (may be outside the grid: Data.inGrid)
	  Data.cellCentre(col, row) -> x, z
	  Data.mask("Conifer") -> buffer       -- 688 x 688 bytes; Data.maskValue(name, mcol, mrow); Data.maskAt(name, x, z)
	  Data.terrain(), Data.layout()        -- the decoded JSON tables (HttpService:JSONDecode)
	  Data.manifest("Landmarks")           -- the decoded manifest (nil when the pack has none by that name)
	  Data.slot(id), Data.regionName(id)   -- legend entries from Terrain.json
	  Data.buffer("Height")                -- the raw buffer, for inner loops: buffer.readu16(b, (row * Data.N + col) * 2)
	  Data.close()                         -- lets go of the open pack (decoded buffers stay); Data.release() drops all
	Reading is lazy: a blob is decoded and checked against the pack's own fingerprint the first time it is asked
	for, and the pack stays open until Data.close() or Data.load() (which closes it when it is done).
]]
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local floor = math.floor

local Data = {}
Data.VERSION = 1
Data.PACK = "map1_data"
Data.VERIFY = true -- check each blob against the pack's FNV-1a fingerprint when it is first read (about 0.1 s per MB)

Data.GRIDS = { "Height", "Material", "Region", "WaterLevel" }
Data.MASKS = { "Conifer", "Broadleaf", "Gorse", "Heather", "Boulders", "Crags", "TallGrass", "Wildflowers" }
Data.TEXTS = { "Terrain", "Layout", "Manifest_Landmarks", "Manifest_Plants", "Manifest_Skyline", "Manifest_FarValley" }

-- Grid facts. These are the contract's values; Data.open() replaces them with the Terrain blob's own "grid".
Data.N = 1376 -- cells per side
Data.CELL = 4 -- studs per cell
Data.ORIGIN_X = -2752 -- the west edge of column 0
Data.ORIGIN_Z = -2752 -- the north edge of row 0
Data.HEIGHT_SCALE = 32 -- raw units per stud (Height and WaterLevel)
Data.MASK_N = 688
Data.MASK_CELL = 8

local pack: any = nil -- the open StudioSync pack
local packName: string? = nil
local buffers: { [string]: buffer } = {}
local decoded: { [string]: any } = {}
local factsRead = false
local bufH: buffer?, bufM: buffer?, bufR: buffer?, bufW: buffer? = nil, nil, nil, nil

local function studioSync(): any
	local dev = ServerStorage:FindFirstChild("Dev")
	local module = dev and dev:FindFirstChild("StudioSync")
	if not module then
		error("Map1.Data: ServerStorage.Dev.StudioSync is missing (see tools/studio_sync/README.md, bootstrap)")
	end
	return require(if RunService:IsRunning() then module else module:Clone())
end

local function expectedBytes(name: string): number?
	local n, mn = Data.N, Data.MASK_N
	if name == "Height" or name == "WaterLevel" then
		return n * n * 2
	elseif name == "Material" or name == "Region" then
		return n * n
	elseif string.sub(name, 1, 5) == "Mask_" then
		return mn * mn
	end
	return nil
end

local function bind(name: string, b: buffer)
	if name == "Height" then
		bufH = b
	elseif name == "Material" then
		bufM = b
	elseif name == "Region" then
		bufR = b
	elseif name == "WaterLevel" then
		bufW = b
	end
end

local function readFacts()
	factsRead = true
	if not (buffers.Terrain or (pack and pack:info("Terrain"))) then
		warn("[Map1.Data] the pack has no Terrain blob; keeping the contract's grid facts")
		return
	end
	local grid = Data.terrain().grid
	if type(grid) ~= "table" then
		error("Map1.Data: Terrain.json has no grid")
	end
	Data.N = grid.width
	Data.CELL = grid.studsPerPixel
	Data.ORIGIN_X = grid.origin[1]
	Data.ORIGIN_Z = grid.origin[2]
	if grid.height ~= grid.width then
		error(string.format("Map1.Data: the grid is %d x %d; a square grid is expected", grid.width, grid.height))
	end
	if type(grid.masks) == "table" then
		Data.MASK_N = grid.masks.width
		Data.MASK_CELL = grid.masks.studsPerPixel
	end
	-- the encoding is stated as text in the file ("16-bit: y_studs = value / 32"): refuse a different divisor
	local stated = tonumber(string.match(tostring(grid.heightEncoding or ""), "/%s*(%d+)"))
	if stated and stated ~= Data.HEIGHT_SCALE then
		error(string.format("Map1.Data: heights are value / %d in this pack; this module expects / %d", stated, Data.HEIGHT_SCALE))
	end
end

----------------------------------------------------------------------------------------------------
-- the pack
----------------------------------------------------------------------------------------------------
-- Opens the pack and reads the grid facts. Safe to call again; another pack name drops everything first.
function Data.open(name: string?)
	local wanted = name or Data.PACK
	if packName ~= nil and packName ~= wanted then
		Data.release()
	end
	if not pack then
		pack = studioSync().open(wanted)
		packName = wanted
	end
	if not factsRead then
		readFacts()
	end
	return Data
end

function Data.isOpen(): boolean
	return pack ~= nil
end

function Data.packName(): string
	return packName or Data.PACK
end

-- Lets go of the pack (the 20 MB of text GetObjects loaded). Buffers already decoded stay usable.
function Data.close()
	if pack then
		pack:close()
		pack = nil
	end
end

-- Drops the pack and every decoded buffer.
function Data.release()
	Data.close()
	packName = nil
	table.clear(buffers)
	table.clear(decoded)
	bufH, bufM, bufR, bufW = nil, nil, nil, nil
	factsRead = false
end

-- The names of the blobs in the pack (opens it).
function Data.names(): { string }
	Data.open(packName)
	return pack:names()
end

function Data.has(name: string): boolean
	if buffers[name] then
		return true
	end
	Data.open(packName)
	return pack:info(name) ~= nil
end

-- The exact bytes of one blob (decoded once, then cached).
function Data.buffer(name: string): buffer
	local b = buffers[name]
	if b then
		return b
	end
	Data.open(packName)
	if not pack:info(name) then
		error(string.format("Map1.Data: the pack %s has no blob named %s", Data.packName(), name))
	end
	b = pack:blob(name, Data.VERIFY)
	if name ~= "Terrain" and not factsRead then
		readFacts()
	end
	local want = expectedBytes(name)
	if want and buffer.len(b) ~= want then
		error(string.format("Map1.Data: %s is %d bytes; the grid facts need %d", name, buffer.len(b), want))
	end
	buffers[name] = b
	bind(name, b)
	return b
end

-- For tests: use these bytes for a blob instead of the pack's (a buffer, or a string for the text blobs).
function Data.inject(name: string, value: buffer | string)
	local b = if type(value) == "string" then buffer.fromstring(value) else value
	buffers[name] = b
	decoded[name] = nil
	bind(name, b)
	if name == "Terrain" then
		factsRead = false
		readFacts()
	end
end

-- Decodes the named blobs (default: the four grids, Terrain and Layout), then closes the pack.
function Data.load(names: { string }?)
	Data.open(packName)
	local list = names or { "Terrain", "Layout", "Height", "Material", "Region", "WaterLevel" }
	for _, name in ipairs(list) do
		Data.buffer(name)
	end
	Data.close()
	return Data
end

function Data.text(name: string): string
	return buffer.tostring(Data.buffer(name))
end

function Data.json(name: string): any
	local value = decoded[name]
	if value == nil then
		value = HttpService:JSONDecode(Data.text(name))
		decoded[name] = value
	end
	return value
end

function Data.terrain(): any
	return Data.json("Terrain")
end

function Data.layout(): any
	return Data.json("Layout")
end

-- Data.manifest("Landmarks") -> the decoded manifest, or nil when the pack does not carry it
function Data.manifest(kind: string): any
	local name = "Manifest_" .. kind
	if not Data.has(name) then
		return nil
	end
	return Data.json(name)
end

-- legend entries: { base = "Grass", tint = { r, g, b }, note = "..." } and the region's name
function Data.slot(id: number): any
	return Data.terrain().materialSlots[tostring(id)]
end

function Data.regionName(id: number): string?
	return Data.terrain().regions[tostring(id)]
end

----------------------------------------------------------------------------------------------------
-- cells
----------------------------------------------------------------------------------------------------
function Data.inGrid(col: number, row: number): boolean
	local n = Data.N
	return col >= 0 and row >= 0 and col < n and row < n
end

-- the cell that holds the world point (not clamped: test with Data.inGrid)
function Data.cellAt(x: number, z: number): (number, number)
	return floor((x - Data.ORIGIN_X) / Data.CELL), floor((z - Data.ORIGIN_Z) / Data.CELL)
end

function Data.cellCentre(col: number, row: number): (number, number)
	return Data.ORIGIN_X + Data.CELL * (col + 0.5), Data.ORIGIN_Z + Data.CELL * (row + 0.5)
end

function Data.heightRaw(col: number, row: number): number?
	local n = Data.N
	if col < 0 or row < 0 or col >= n or row >= n then
		return nil
	end
	return buffer.readu16(bufH or Data.buffer("Height"), (row * n + col) * 2)
end

function Data.height(col: number, row: number): number?
	local n = Data.N
	if col < 0 or row < 0 or col >= n or row >= n then
		return nil
	end
	return buffer.readu16(bufH or Data.buffer("Height"), (row * n + col) * 2) / Data.HEIGHT_SCALE
end

function Data.material(col: number, row: number): number?
	local n = Data.N
	if col < 0 or row < 0 or col >= n or row >= n then
		return nil
	end
	return buffer.readu8(bufM or Data.buffer("Material"), row * n + col)
end

function Data.region(col: number, row: number): number?
	local n = Data.N
	if col < 0 or row < 0 or col >= n or row >= n then
		return nil
	end
	return buffer.readu8(bufR or Data.buffer("Region"), row * n + col)
end

-- the water surface over the cell in studs, or nil when the cell is dry
function Data.waterLevel(col: number, row: number): number?
	local n = Data.N
	if col < 0 or row < 0 or col >= n or row >= n then
		return nil
	end
	local raw = buffer.readu16(bufW or Data.buffer("WaterLevel"), (row * n + col) * 2)
	if raw == 0 then
		return nil
	end
	return raw / Data.HEIGHT_SCALE
end

function Data.isWet(col: number, row: number): boolean
	local n = Data.N
	if col < 0 or row < 0 or col >= n or row >= n then
		return false
	end
	return buffer.readu16(bufW or Data.buffer("WaterLevel"), (row * n + col) * 2) ~= 0
end

----------------------------------------------------------------------------------------------------
-- world points
----------------------------------------------------------------------------------------------------
-- ground height at a world point: bilinear between the four nearest cell centres (clamped at the grid's edge)
function Data.heightAt(x: number, z: number): number
	local n = Data.N
	local b = bufH or Data.buffer("Height")
	local fx = (x - Data.ORIGIN_X) / Data.CELL - 0.5
	local fz = (z - Data.ORIGIN_Z) / Data.CELL - 0.5
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
	local a, c = buffer.readu16(b, k), buffer.readu16(b, k + 2)
	local d, e = buffer.readu16(b, k + 2 * n), buffer.readu16(b, k + 2 * n + 2)
	return ((a * (1 - tx) + c * tx) * (1 - tz) + (d * (1 - tx) + e * tx) * tz) / Data.HEIGHT_SCALE
end

function Data.materialAt(x: number, z: number): number?
	local col, row = Data.cellAt(x, z)
	return Data.material(col, row)
end

function Data.regionAt(x: number, z: number): number?
	local col, row = Data.cellAt(x, z)
	return Data.region(col, row)
end

function Data.waterLevelAt(x: number, z: number): number?
	local col, row = Data.cellAt(x, z)
	return Data.waterLevel(col, row)
end

----------------------------------------------------------------------------------------------------
-- masks (688 x 688 bytes, 8-stud cells on the same origin)
----------------------------------------------------------------------------------------------------
function Data.mask(name: string): buffer
	return Data.buffer("Mask_" .. name)
end

-- density 0..255 of one mask cell (0 outside the grid)
function Data.maskValue(name: string, mcol: number, mrow: number): number
	local n = Data.MASK_N
	if mcol < 0 or mrow < 0 or mcol >= n or mrow >= n then
		return 0
	end
	return buffer.readu8(buffers["Mask_" .. name] or Data.mask(name), mrow * n + mcol)
end

-- density 0..255 at a world point (the mask cell that holds it)
function Data.maskAt(name: string, x: number, z: number): number
	local c = Data.MASK_CELL
	return Data.maskValue(name, floor((x - Data.ORIGIN_X) / c), floor((z - Data.ORIGIN_Z) / c))
end

-- a line per blob: name, bytes, loaded or not (opens the pack)
function Data.describe(): string
	Data.open(packName)
	local lines = { string.format("pack %s: grid %d x %d, cell %d, origin (%d, %d); masks %d x %d, cell %d",
		Data.packName(), Data.N, Data.N, Data.CELL, Data.ORIGIN_X, Data.ORIGIN_Z, Data.MASK_N, Data.MASK_N, Data.MASK_CELL) }
	for _, name in ipairs(pack:names()) do
		local info = pack:info(name)
		table.insert(lines, string.format("  %-22s %9d bytes  %s%s", name, info.bytes, info.fnv, if buffers[name] then "  (loaded)" else ""))
	end
	return table.concat(lines, "\n")
end

return Data
