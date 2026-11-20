--[[
	ArenaController.Hex - the honeycomb tile of the border wall (owner, 20 Nov 2026: "make the border have opaque
	slightly transparent blue hexagonal shape").

	One tile of a pointy-top honeycomb (hexagons with vertical sides), seamless when repeated: TILE_W x TILE_H pixels,
	which is sqrt(3) x 3 hexagon edges (two rows of cells). Each cell: a bright, almost white-blue outline with a soft
	blue glow either side, and a lightly tinted blue inside that deepens toward the outline (a soft bevel), so the
	wall reads as a sheet of glass cells: mostly see-through in the middle, solid at the seams.

	Where the picture comes from, first that works:
	  1. Config.Border.HexImage ("rbxassetid://..."): the same tile as a PNG, uploaded by the lead
	     (tools/border/hex_tile.png is made by tools/border/make_hex_tile.py with these exact numbers).
	  2. An EditableImage drawn here once at start (no upload; 111 x 192 pixels, 85 KB). Needs the experience's
	     "Allow Mesh / Image APIs" setting in a live server, and fails on a phone short of memory: then
	  3. nothing (Hex.content returns nil) and the wall keeps its old outline and rising lattice.

	API:
	  Hex.content(lineColor, glowColor) -> (Content | string | nil, source: string)   cached after the first call
	  Hex.TILE_W, Hex.TILE_H   pixels; the tile is sqrt(3) x 3 hexagon edges
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Hex = {}

local EDGE = 64 -- pixels in one hexagon edge
local TILE_W = 111 -- round(sqrt(3) * EDGE)
local TILE_H = 3 * EDGE
Hex.TILE_W = TILE_W
Hex.TILE_H = TILE_H

-- the look of one cell (the PNG generator uses the same numbers)
local LINE_HALF = 2.4 -- pixels: half the width of the outline's solid core
local LINE_SOFT = 1.2 -- pixels of anti-aliasing at the core's edge
local GLOW_FALL = 6.5 -- pixels: the glow beside the outline falls by e every this far
local GLOW_ALPHA = 0.5
local FILL_ALPHA = 0.13 -- the middle of a cell
local BEVEL_ALPHA = 0.3 -- added toward the outline
local CORE_WHITE = 0.4 -- how far the outline's core is lifted toward white

local cached: any = nil
local cachedSource = "none"
local tried = false

local SQ3 = math.sqrt(3)
local APOTHEM = SQ3 / 2 * EDGE

-- distance (pixels) from point (x, y) to the outline of the cell it is in
local function edgeDistance(x: number, y: number): number
	local best = math.huge
	local w = SQ3 * EDGE
	for j = -1, 2 do
		local cy = j * 1.5 * EDGE
		local shift = if j % 2 == 0 then 0 else w / 2
		for i = -1, 1 do
			local dx = x - (i * w + shift)
			local dy = y - cy
			-- pointy-top hexagon: the sides' normals at 0, 60 and 120 degrees
			local d = math.max(math.abs(dx), math.abs(dx * 0.5 + dy * SQ3 / 2), math.abs(dx * 0.5 - dy * SQ3 / 2))
			if d < best then
				best = d
			end
		end
	end
	return APOTHEM - best
end

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

function Hex.pixels(lineColor: Color3, glowColor: Color3): buffer
	local data = buffer.create(TILE_W * TILE_H * 4)
	local sx = SQ3 * EDGE / TILE_W -- the tile is a whole pixel wide; stretch the geometry by 0.1% to fit
	local core = lineColor:Lerp(Color3.new(1, 1, 1), CORE_WHITE)
	local offset = 0
	for py = 0, TILE_H - 1 do
		for px = 0, TILE_W - 1 do
			local e = edgeDistance((px + 0.5) * sx, py + 0.5)
			local coreA = 1 - smooth(LINE_HALF - LINE_SOFT, LINE_HALF + LINE_SOFT, e)
			local glowA = GLOW_ALPHA * math.exp(-math.max(e - LINE_HALF, 0) / GLOW_FALL)
			local inside = math.clamp(1 - e / APOTHEM, 0, 1)
			local fillA = FILL_ALPHA + BEVEL_ALPHA * inside ^ 3
			local softA = glowA + fillA * (1 - glowA)
			local a = coreA + softA * (1 - coreA)
			-- colour: the core over the glow over the fill (straight alpha)
			local k = if a > 0 then coreA / a else 0
			local c = glowColor:Lerp(core, k)
			buffer.writeu8(data, offset, math.floor(c.R * 255 + 0.5))
			buffer.writeu8(data, offset + 1, math.floor(c.G * 255 + 0.5))
			buffer.writeu8(data, offset + 2, math.floor(c.B * 255 + 0.5))
			buffer.writeu8(data, offset + 3, math.floor(math.clamp(a, 0, 1) * 255 + 0.5))
			offset += 4
		end
	end
	return data
end

function Hex.content(lineColor: Color3, glowColor: Color3): (any, string)
	if tried then
		return cached, cachedSource
	end
	tried = true
	local id = Config.Border and Config.Border.HexImage
	if type(id) == "string" and id ~= "" then
		cached, cachedSource = id, "asset"
		return cached, cachedSource
	end
	local ok, result = pcall(function()
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(TILE_W, TILE_H) })
		if not image then
			return nil
		end
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(TILE_W, TILE_H), Hex.pixels(lineColor, glowColor))
		return Content.fromObject(image)
	end)
	if ok and result then
		cached, cachedSource = result, "editable"
	else
		cached, cachedSource = nil, "none"
		if not ok then
			warn("[ArenaController.Hex] no hex tile, the wall keeps its outline: " .. tostring(result))
		end
	end
	return cached, cachedSource
end

return Hex
