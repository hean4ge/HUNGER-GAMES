# Builds PointFont.lua (the Roll Call point-cloud font) from the glyph table rasterised by font_raster.py.
# Usage: python make_pointfont.py <dir containing PointFont_glyphs.lua>
import re, sys, os

here = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "PointFont_glyphs.lua"), encoding="utf-8").read()

glyph_re = re.compile(r'\t\[("(?:\\.|[^"])*")\] = \{ w = (\d+), h = (\d+), y0 = (-?\d+), rows = \{ ([\d, ]+) \} \},')
glyphs = {}
order = []
for m in glyph_re.finditer(src):
    key = m.group(1)
    glyphs[key] = [int(m.group(2)), int(m.group(3)), int(m.group(4)), [int(x) for x in m.group(5).split(",")]]
    order.append(key)

# 'Q' rasterised wrong (overlapping contours filled the counter): rebuild it from 'O' plus a tail
O = glyphs['"O"']
w, h, y0, rows = O[0], O[1], O[2], list(O[3])
def setbit(row, col):
    return row | (1 << (w - 1 - col))
# rows are top-to-bottom; extend 3 rows below for the tail
tail = [[8, 9, 10, 11], [9, 10, 11, 12], [11, 12]]
# also let the tail cut into the last two rows of the bowl
rows[-2] = setbit(setbit(rows[-2], 9), 10)
rows[-1] = setbit(setbit(setbit(rows[-1], 9), 10), 11)
for cols in tail:
    r = 0
    for c in cols:
        r = setbit(r, c)
    rows.append(r)
glyphs['"Q"'] = [w, h + 3, y0 - 3, rows]

# '6' also rasterised solid: it is the '9' turned half round in Oswald
w9, h9, y09, rows9 = glyphs['"9"']
glyphs['"6"'] = [w9, h9, y09, [int(format(r, "0%db" % w9)[::-1], 2) for r in reversed(rows9)]]

def ascii_preview(key):
    w, h, y0, rows = glyphs[key]
    return "\n".join("".join("#" if (r >> (w - 1 - c)) & 1 else "." for c in range(w)) for r in rows)

print(ascii_preview('"Q"'))
print(ascii_preview('"6"'))

out = []
out.append("""--[[
	PointFont (FallenRecapController helper, client) - glyph bitmaps for the Roll Call's point-cloud letters.
	Rasterised from Oswald Bold (SIL Open Font License 1.1, (c) The Oswald Project Authors) with headless Blender by
	art/blender/font_raster.py (make_pointfont.py adds the layout code). Uppercase display face: A-Z, 0-9 and common
	punctuation; accented Latin letters fall back to their base letter, anything else is skipped.
	Glyph: w/h in cells, y0 = row of the glyph's bottom edge relative to the baseline (negative = descends),
	rows = top-to-bottom bitmasks (bit w-1 = leftmost column).
	PointFont.cells(text) -> (xs, ys, width, height): centres of the filled cells in cap-height units (cap height = 1),
	centred on (0, 0) at the middle of the cap height.
]]
local PointFont = {}
""")
out.append("PointFont.CapRows = 22")
out.append("PointFont.Tracking = 0.15 -- gap between glyphs, in cap heights")
out.append("PointFont.SpaceWidth = 0.34 -- in cap heights")
out.append("PointFont.Glyphs = {")
for key in order:
    w, h, y0, rows = glyphs[key]
    out.append("\t[%s] = { w = %d, h = %d, y0 = %d, rows = { %s } }," % (key, w, h, y0, ", ".join(str(r) for r in rows)))
out.append("}")
out.append(r'''
-- Latin-1 letters -> base letters (uppercase display face)
local FOLD = {}
do
	local map = {
		A = "ÀÁÂÃÄÅàáâãäå", C = "Çç", E = "ÈÉÊËèéêë", I = "ÌÍÎÏìíîï", N = "Ññ", O = "ÒÓÔÕÖØòóôõöø",
		U = "ÙÚÛÜùúûü", Y = "Ýýÿ", D = "Ðð", S = "ß",
	}
	for base, chars in pairs(map) do
		for _, code in utf8.codes(chars) do
			FOLD[code] = base
		end
	end
end

local function glyphFor(code: number)
	if code >= 97 and code <= 122 then
		code -= 32
	end
	local ch
	if code < 128 then
		ch = string.char(code)
	else
		ch = FOLD[code]
	end
	if not ch then
		return nil, nil
	end
	return PointFont.Glyphs[ch], ch
end

local cache = {}

function PointFont.cells(text: string): ({ number }, { number }, number, number)
	local cached = cache[text]
	if cached then
		return cached[1], cached[2], cached[3], cached[4]
	end
	local rowsPerCap = PointFont.CapRows
	local xs, ys = {}, {}
	local pen = 0 -- in cells
	local tracking = PointFont.Tracking * rowsPerCap
	local space = PointFont.SpaceWidth * rowsPerCap
	local first = true
	local ok = pcall(function()
		for _, code in utf8.codes(text) do
			if code == 32 or code == 9 then
				pen += space
			else
				local g = glyphFor(code)
				if g then
					if not first then
						pen += tracking
					end
					first = false
					local w, h, y0 = g.w, g.h, g.y0
					for r = 1, h do
						local bits = g.rows[r]
						if bits and bits ~= 0 then
							local cy = y0 + (h - r) + 0.5 -- cell centre, rows from the top
							for c = 0, w - 1 do
								if bit32.btest(bits, bit32.lshift(1, w - 1 - c)) then
									table.insert(xs, pen + c + 0.5)
									table.insert(ys, cy)
								end
							end
						end
					end
					pen += w
				end
			end
		end
	end)
	if not ok then
		xs, ys, pen = {}, {}, 0
	end
	local width = pen / rowsPerCap
	-- centre: x on the advance width, y on the middle of the cap height
	local halfW = pen / 2
	local midY = rowsPerCap / 2
	for i = 1, #xs do
		xs[i] = (xs[i] - halfW) / rowsPerCap
		ys[i] = (ys[i] - midY) / rowsPerCap
	end
	local result = { xs, ys, width, 1 }
	if #text <= 40 then
		cache[text] = result
	end
	return xs, ys, width, 1
end

return PointFont
''')
open(os.path.join(here, "PointFont.lua"), "w", encoding="utf-8").write("\n".join(out))
print("glyphs", len(order))
