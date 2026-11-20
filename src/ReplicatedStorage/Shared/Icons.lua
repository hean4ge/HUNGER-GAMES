--[[
	Icons - every flat icon the card menus show, looked up by name (docs/design/CardMenusAndShop.md section 4.2).
	Client and edit time (it only makes Instances).

	TWO SOURCES, ONE CALL
	  1. The sprite sheet, once the lead has uploaded the blender-icons agent's sheet: set Icons.Sheet.Image to its
	     rbxassetid and fill Icons.Sheet.Cells ({ [name] = { col, row } }, Cell px square cells). Then Icons.make draws
	     an ImageLabel cut from the sheet (ImageRectOffset / ImageRectSize). Nothing is uploaded from here.
	  2. Until then, and for any name the sheet lacks: a clean glyph drawn with plain Frames (no images), in our matte
	     palette, on a 24 x 24 grid. Same silhouette idea as the stand-ins in the design page's icons.js.

	API
	  Icons.make(name, props?) -> GuiObject     props: Instance properties (Size, Position, AnchorPoint, ZIndex,
	                                            LayoutOrder, Parent...) plus Tone (one Color3 to draw every part in,
	                                            e.g. Ink2 for a dimmed or locked icon). Default Size: the parent's full
	                                            size (a 1:1 UIAspectRatioConstraint keeps it square).
	  Icons.has(name) -> boolean                 a glyph or a sheet cell exists for it
	  Icons.names() -> { string }                every glyph name (sorted)
	  Icons.forSkill(skillOrFamilyId) -> name    "whirl", "Axe" -> "whirl"; general skills by their id
	  Icons.forKit(kitId) -> name                "archer" ... ("hunter" draws the Trapper's snare)
	  Icons.forItem(itemId) -> name              a stand-in for an item's 3D view (bandage, apple, water ...)
	  Icons.tint(icon, color)                    recolours a Frame glyph (an image: ImageColor3)
	  Icons.Tones                                the palette the glyphs use (design page 4.2)

	Names: ui (lock, tick, plus, none, coin, cooldown, star, close, edit, acorn, wheel, crate, strongbox, spark,
	inspect, swap), the train menu (menu, loadout, season, daily, ranks, boards), slots (swing, arrow_slot, throw), weapon skills (head_kick, chained_strikes, running_cut, whirl,
	vault_kick, ricochet, piercing_shot), general skills (concentration, second_wind, sprint_burst, quiet_step,
	steady_hands, brace), kits (archer, forager, trapper, medic, climber), traits (unseen, quiet_swish, sweep,
	heavy_throw, firewood, reach, big_throw, armour_breaker, spin_throw, flat_throw, climb, draw_range), items (apple,
	water, bandage, herbs, berries, dried_meat, arrow, throwing_knife), cosmetic slots (skin, kill_effect, kill_icon,
	banner, emote, trail).
]]
local Theme = require(script.Parent:WaitForChild("Theme"))

local Icons = {}

-- The sheet (empty until the lead uploads the icons agent's sheet; then one line each)
Icons.Sheet = {
	Image = "", -- "rbxassetid://..." once uploaded
	Cell = 256, -- px per cell on the sheet
	Cells = {} :: { [string]: { number } }, -- name = { col, row } (0-based)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Icons.Tones = {
	ink = Theme.Colors.Ink, -- #F4F1EA
	ink2 = Theme.Colors.Ink2, -- #BDB8AC
	steel = rgb(167, 174, 178), -- #A7AEB2
	steel2 = rgb(108, 116, 122), -- #6C747A
	wood = rgb(142, 107, 76), -- #8E6B4C
	wood2 = rgb(106, 78, 56), -- #6A4E38
	leather = rgb(90, 69, 53), -- #5A4535
	brass = rgb(201, 162, 78), -- #C9A24E
	brass2 = rgb(156, 122, 52), -- #9C7A34
	sun = Theme.Colors.Sun, -- accent only
	sage = rgb(157, 191, 174), -- #9DBFAE
	leaf = rgb(126, 150, 88), -- muted leaf green
	apple = rgb(176, 84, 66), -- a muted apple red-brown (never a hit colour)
	shade = Theme.Colors.Shade,
	water = rgb(136, 170, 196), -- a pale slate blue
}
local T = Icons.Tones

--[[ Parts on a 24-unit grid. Each part: { kind, ..., tone? }
	{ "r", x, y, w, h, rot?, tone? }        rectangle (top-left x, y), rotated about its centre
	{ "R", x, y, w, h, rot?, tone? }        rounded rectangle (corner = a quarter of the short side)
	{ "c", cx, cy, d, tone? }               filled disc, centre and diameter
	{ "o", cx, cy, d, thick, tone? }        ring
	{ "a", cx, cy, d, thick, keep, rot, tone? }  part of a ring: `keep` (0..1) of it along a straight cut, turned rot deg
	{ "l", x1, y1, x2, y2, thick, tone? }   a straight stroke with round ends
]]
local G: { [string]: { { any } } } = {}

-- UI marks -------------------------------------------------------------------------------------------------------
G.lock = { { "a", 12, 9, 10, 2.2, 0.62, 0, "ink" }, { "R", 5.5, 10.5, 13, 10, 0, "ink" }, { "c", 12, 15, 2.6, "shade" }, { "r", 11.4, 15.5, 1.2, 3, 0, "shade" } }
G.tick = { { "c", 12, 12, 20, "ink" }, { "l", 7.6, 12.4, 10.6, 15.4, 2.4, "shade" }, { "l", 10.6, 15.4, 16.6, 8.8, 2.4, "shade" } }
G.plus = { { "r", 10.8, 4, 2.4, 16, 0, "ink" }, { "r", 4, 10.8, 16, 2.4, 0, "ink" } }
G.none = { { "o", 12, 12, 18, 2.4, "ink2" }, { "l", 6.4, 17.6, 17.6, 6.4, 2.4, "ink2" } }
G.coin = { { "c", 12, 12, 18, "brass" }, { "o", 12, 12, 13, 1.4, "brass2" }, { "r", 10.8, 8.5, 2.4, 7, 0, "brass2" } }
G.cooldown = { { "o", 12, 12, 16, 2, "ink" }, { "r", 11.2, 6.5, 1.6, 6.2, 0, "ink" }, { "r", 11.2, 11.2, 4.6, 1.6, 0, "ink" } }
G.star = { { "r", 7, 7, 10, 10, 45, "sun" }, { "r", 7, 7, 10, 10, 0, "sun" } }
G.close = { { "l", 6, 6, 18, 18, 2.4, "ink" }, { "l", 18, 6, 6, 18, 2.4, "ink" } }
G.edit = { { "l", 6.5, 17.5, 16.5, 7.5, 3.4, "ink" }, { "l", 17.5, 6.5, 18.6, 5.4, 3.4, "ink2" }, { "l", 5, 19, 6, 18, 1.6, "ink2" } }
G.acorn = { { "R", 6.5, 5, 11, 5, 0, "wood2" }, { "r", 11.3, 2.5, 1.4, 3, 0, "wood2" }, { "c", 12, 13.5, 10, "brass" }, { "c", 12, 17, 6, "brass" } }
G.wheel = { { "o", 12, 12, 18, 2, "ink" }, { "l", 12, 3, 12, 21, 1.4, "ink2" }, { "l", 3, 12, 21, 12, 1.4, "ink2" }, { "l", 5.6, 5.6, 18.4, 18.4, 1.4, "ink2" }, { "l", 18.4, 5.6, 5.6, 18.4, 1.4, "ink2" }, { "c", 12, 12, 4, "brass" } }
G.crate = { { "R", 4, 8, 16, 12, 0, "wood" }, { "r", 4, 6, 16, 4, 0, "wood2" }, { "r", 10.5, 9, 3, 4, 0, "brass" }, { "r", 4, 14, 16, 1.2, 0, "wood2" } }
G.strongbox = { { "R", 3.5, 8, 17, 12, 0, "steel2" }, { "r", 3.5, 6, 17, 4, 0, "steel" }, { "r", 10.5, 9.5, 3, 4, 0, "brass" }, { "r", 7, 6, 1.4, 14, 0, "steel" }, { "r", 15.6, 6, 1.4, 14, 0, "steel" } }
G.spark = { { "l", 12, 4, 12, 20, 2, "sun" }, { "l", 4, 12, 20, 12, 2, "sun" }, { "l", 7, 7, 17, 17, 1.4, "sun" }, { "l", 17, 7, 7, 17, 1.4, "sun" } }
G.inspect = { { "o", 10, 10, 11, 2.2, "ink" }, { "l", 14, 14, 19.5, 19.5, 3, "ink" } }
G.swap = { { "l", 5, 9, 18, 9, 2, "ink" }, { "l", 14.5, 5.5, 18, 9, 2, "ink" }, { "l", 19, 15, 6, 15, 2, "ink" }, { "l", 9.5, 18.5, 6, 15, 2, "ink" } }

-- The train menu (MenuHubController) ---------------------------------------------------------------------------
G.menu = { { "R", 4, 5.5, 16, 2.6, 0, "ink" }, { "R", 4, 10.7, 16, 2.6, 0, "ink" }, { "R", 4, 15.9, 16, 2.6, 0, "ink" } }
G.loadout = { { "R", 5, 7, 14, 14, 0, "leather" }, { "a", 12, 7.5, 8, 1.8, 0.5, 0, "wood2" }, { "R", 7.5, 12, 9, 6, 0, "wood" }, { "r", 11, 12, 2, 3, 0, "brass" } }
G.season = { { "r", 5, 3, 1.8, 18, 0, "wood" }, { "r", 6.8, 4, 12, 8, 0, "ink" }, { "r", 6.8, 12, 12, 1.4, 0, "brass" }, { "c", 12.8, 8, 3.4, "sun" } }
G.daily = { { "R", 4, 5.5, 16, 15, 0, "ink" }, { "r", 4, 5.5, 16, 4, 0, "brass" }, { "r", 7.4, 3.5, 1.8, 4, 0, "ink2" }, { "r", 14.8, 3.5, 1.8, 4, 0, "ink2" }, { "l", 8.4, 14.6, 11, 17, 2, "shade" }, { "l", 11, 17, 15.8, 11.6, 2, "shade" } }
G.ranks = { { "R", 6, 3, 12, 10, 0, "steel" }, { "r", 8.5, 9, 7, 7, 45, "steel" }, { "l", 8.5, 7.5, 12, 10.5, 1.8, "shade" }, { "l", 12, 10.5, 15.5, 7.5, 1.8, "shade" }, { "l", 8.5, 11.5, 12, 14.5, 1.8, "shade" }, { "l", 12, 14.5, 15.5, 11.5, 1.8, "shade" } }
G.gear = { { "o", 12, 12, 12, 3.2, "ink" }, { "r", 10.6, 2.5, 2.8, 4, 0, "ink" }, { "r", 10.6, 17.5, 2.8, 4, 0, "ink" }, { "r", 2.5, 10.6, 4, 2.8, 0, "ink" }, { "r", 17.5, 10.6, 4, 2.8, 0, "ink" }, { "r", 5.1, 4.5, 2.8, 4, -45, "ink" }, { "r", 16.1, 4.5, 2.8, 4, 45, "ink" }, { "r", 5.1, 15.5, 2.8, 4, 45, "ink" }, { "r", 16.1, 15.5, 2.8, 4, -45, "ink" }, { "c", 12, 12, 3.4, "ink2" } }
G.boards = { { "r", 9, 6, 6, 14, 0, "ink" }, { "r", 3, 11, 6, 9, 0, "ink2" }, { "r", 15, 13, 6, 7, 0, "ink2" }, { "c", 12, 3.6, 3.4, "sun" } }

-- Trail slots ------------------------------------------------------------------------------------------------------
G.swing = { { "a", 12, 15, 18, 2.2, 0.5, 0, "ink" }, { "l", 4, 15.5, 6, 18, 1.6, "ink2" } }
G.arrow_slot = { { "l", 4, 12, 19, 12, 2, "ink" }, { "l", 15.5, 8.5, 20, 12, 2, "ink" }, { "l", 15.5, 15.5, 20, 12, 2, "ink" }, { "l", 4, 12, 6.5, 9, 1.4, "ink2" }, { "l", 4, 12, 6.5, 15, 1.4, "ink2" } }
G.throw = { { "a", 12, 16, 18, 1.6, 0.5, 0, "ink2" }, { "l", 15, 5, 20, 10, 2.4, "ink" }, { "l", 18, 5, 20, 7, 1.4, "steel" } }
G.trail = { { "a", 14, 18, 22, 2.4, 0.5, 20, "ink" }, { "c", 19.5, 9, 3, "sun" } }

-- Weapon skills (Combat_v3 2.2) ------------------------------------------------------------------------------------
G.head_kick = { { "c", 8, 6, 4, "ink" }, { "l", 8, 9, 10, 15, 2.4, "ink" }, { "l", 10, 13, 18, 8, 2.4, "ink" }, { "l", 10, 15, 8, 21, 2.4, "ink" }, { "a", 18, 9, 7, 1.4, 0.5, 90, "ink2" } }
G.chained_strikes = { { "l", 5, 17, 9, 7, 2.2, "ink" }, { "l", 10, 17, 14, 7, 2.2, "ink" }, { "l", 15, 17, 19, 7, 2.2, "ink" }, { "r", 4, 19, 16, 1.6, 0, "ink2" } }
G.running_cut = { { "l", 3, 12, 5, 12, 1.8, "ink2" }, { "l", 7, 12, 9, 12, 1.8, "ink2" }, { "l", 11, 12, 15, 12, 2, "ink" }, { "l", 14, 7, 20, 12, 2.4, "ink" }, { "l", 14, 17, 20, 12, 2.4, "ink" } }
G.whirl = { { "a", 12, 12, 16, 2.4, 0.82, 35, "ink" }, { "c", 12, 12, 3.4, "ink" }, { "l", 17.6, 4.4, 19.8, 8.6, 2, "ink" } }
G.vault_kick = { { "l", 6, 20, 15, 5, 2, "wood" }, { "l", 15, 5, 17.5, 3.5, 2, "steel" }, { "a", 12, 10, 10, 1.6, 0.5, 300, "ink" }, { "c", 18, 13, 3, "ink" } }
G.ricochet = { { "l", 4, 6, 12, 17, 2.2, "ink" }, { "l", 12, 17, 20, 6, 2.2, "ink" }, { "c", 12, 17.5, 3.6, "sun" } }
G.piercing_shot = { { "l", 3, 12, 21, 12, 2, "ink" }, { "l", 17, 8.5, 21, 12, 2, "ink" }, { "l", 17, 15.5, 21, 12, 2, "ink" }, { "r", 10.5, 6, 2.4, 12, 0, "ink2" } }

-- General skills ---------------------------------------------------------------------------------------------------
G.concentration = { { "o", 12, 12, 15, 2, "ink" }, { "c", 12, 12, 4.4, "ink" }, { "r", 11.2, 2.5, 1.6, 4, 0, "ink" }, { "r", 11.2, 17.5, 1.6, 4, 0, "ink" }, { "r", 2.5, 11.2, 4, 1.6, 0, "ink" }, { "r", 17.5, 11.2, 4, 1.6, 0, "ink" } }
G.second_wind = { { "l", 4, 9, 15, 9, 2, "ink" }, { "a", 15, 6.2, 5.6, 2, 0.6, 90, "ink" }, { "l", 4, 13.5, 18, 13.5, 2, "ink" }, { "a", 18, 16.4, 5.8, 2, 0.6, 90, "ink" }, { "l", 6, 18, 11, 18, 1.6, "ink2" } }
G.sprint_burst = { { "l", 14, 3, 8, 13, 2.6, "ink" }, { "l", 8, 13, 16, 11, 2.6, "ink" }, { "l", 16, 11, 10, 21, 2.6, "ink" } }
G.quiet_step = { { "R", 6, 12, 5, 8, 0, "ink" }, { "R", 13.5, 5, 5, 8, 0, "ink" }, { "c", 8.5, 10, 3, "ink2" }, { "c", 16, 3.6, 3, "ink2" } }
G.steady_hands = { { "R", 6.5, 9, 11, 11, 0, "ink" }, { "r", 6.5, 5, 2.4, 6, 0, "ink" }, { "r", 9.4, 4, 2.4, 6, 0, "ink" }, { "r", 12.3, 4, 2.4, 6, 0, "ink" }, { "r", 15.1, 5, 2.4, 6, 0, "ink" } }
G.brace = { { "R", 6, 3.5, 12, 11, 0, "ink" }, { "r", 8.5, 12, 7, 6, 45, "ink" }, { "r", 11.2, 6, 1.6, 10, 0, "shade" } }

-- Kits (Weapons_v2 3) ----------------------------------------------------------------------------------------------
G.archer = { { "a", 13, 12, 18, 2, 0.32, 270, "wood" }, { "l", 7.5, 4, 7.5, 20, 1, "ink2" }, { "l", 7.5, 12, 20, 12, 1.8, "ink" }, { "l", 17, 9.5, 20.5, 12, 1.8, "ink" }, { "l", 17, 14.5, 20.5, 12, 1.8, "ink" } }
G.forager = { { "c", 12, 14, 12, "apple" }, { "l", 12, 8, 12.8, 4.5, 1.4, "wood2" }, { "R", 13.5, 4.5, 5, 2.6, -20, "leaf" } }
G.trapper = { { "o", 12, 14, 12, 2, "ink" }, { "l", 12, 3, 12, 8, 1.8, "ink" }, { "r", 6.5, 14, 11, 1.4, 0, "ink2" } }
G.medic = { { "R", 4, 6, 16, 12, 0, "ink" }, { "r", 10.6, 8, 2.8, 8, 0, "shade" }, { "r", 8, 10.6, 8, 2.8, 0, "shade" } }
G.climber = { { "r", 6, 9, 12, 12, 45, "steel2" }, { "r", 9.5, 7, 5, 5, 45, "ink" }, { "r", 0, 20.5, 24, 4, 0, "shade" } }

-- Traits (what each weapon already does: Weapons_v2 1.2) -----------------------------------------------------------
G.unseen = { { "a", 12, 12, 18, 2, 0.5, 0, "ink" }, { "c", 12, 12, 6, "ink" }, { "l", 4.5, 19.5, 19.5, 4.5, 2, "ink2" } }
G.quiet_swish = { { "a", 12, 14, 16, 1.6, 0.5, 0, "ink2" }, { "a", 12, 14, 10, 1.6, 0.5, 0, "ink" }, { "c", 12, 14, 2.4, "ink" } }
G.sweep = { { "a", 12, 18, 20, 2.2, 0.5, 0, "ink" }, { "c", 6, 12, 3.6, "ink2" }, { "c", 18, 12, 3.6, "ink2" } }
G.heavy_throw = { { "a", 12, 16, 18, 1.6, 0.5, 0, "ink2" }, { "R", 15, 4, 6, 6, 20, "steel" }, { "l", 10, 13, 16, 7, 2, "wood" } }
G.firewood = { { "R", 3, 13, 18, 5, 0, "wood" }, { "R", 5, 7.5, 14, 5, 0, "wood2" }, { "l", 12, 3, 12, 20, 1.2, "shade" } }
G.reach = { { "l", 3, 12, 21, 12, 2, "ink" }, { "l", 3, 9, 3, 15, 2, "ink2" }, { "l", 21, 9, 21, 15, 2, "ink2" } }
G.big_throw = { { "a", 12, 18, 20, 1.6, 0.5, 0, "ink2" }, { "l", 4, 17, 19, 6, 2.2, "wood" }, { "l", 17.5, 5, 21, 3.5, 2.6, "steel" } }
G.armour_breaker = { { "R", 5, 4, 14, 12, 0, "steel2" }, { "r", 8, 11, 8, 8, 45, "steel2" }, { "l", 7, 6, 17, 18, 2.4, "ink" } }
G.spin_throw = { { "a", 12, 12, 16, 2, 0.8, 300, "ink" }, { "l", 9, 9, 15, 15, 2, "wood" }, { "R", 13, 6, 5, 5, 20, "steel" } }
G.flat_throw = { { "o", 9, 12, 9, 2, "steel" }, { "l", 15, 12, 22, 12, 1.6, "ink2" }, { "l", 2, 16.5, 22, 16.5, 1, "ink2" } }
G.climb = { { "l", 8, 21, 8, 3, 1.6, "ink2" }, { "l", 16, 21, 16, 3, 1.6, "ink2" }, { "l", 8, 7, 16, 7, 1.6, "ink" }, { "l", 8, 12, 16, 12, 1.6, "ink" }, { "l", 8, 17, 16, 17, 1.6, "ink" } }
G.draw_range = { { "o", 12, 12, 16, 1.6, "ink" }, { "o", 12, 12, 8, 1.6, "ink" }, { "c", 12, 12, 2.6, "sun" } }

-- Items (stand-ins for a 3D view) ----------------------------------------------------------------------------------
G.apple = G.forager
G.water = { { "R", 8.5, 7, 7, 14, 0, "water" }, { "r", 10.2, 3.5, 3.6, 4, 0, "steel" } }
G.bandage = { { "R", 4, 8, 16, 8, 0, "ink" }, { "r", 10.6, 9, 2.8, 6, 0, "ink2" } }
G.herbs = { { "l", 12, 21, 12, 9, 1.6, "leaf" }, { "R", 6, 7, 6, 3.4, -35, "leaf" }, { "R", 12, 4, 6, 3.4, 35, "leaf" }, { "R", 12, 11, 6, 3.4, 35, "leaf" } }
G.berries = { { "c", 9, 14, 6, "apple" }, { "c", 15, 14, 6, "apple" }, { "c", 12, 9, 6, "apple" } }
G.dried_meat = { { "R", 5, 8, 14, 9, -15, "wood" }, { "l", 8, 11, 16, 9, 1, "wood2" } }
G.arrow = { { "l", 4, 20, 19, 5, 1.6, "wood" }, { "l", 15.5, 5, 19, 5, 1.8, "steel" }, { "l", 19, 5, 19, 8.5, 1.8, "steel" }, { "l", 4, 20, 4, 16.5, 1.4, "ink2" }, { "l", 4, 20, 7.5, 20, 1.4, "ink2" } }
G.throwing_knife = { { "l", 6, 18, 11, 13, 2.6, "leather" }, { "l", 11, 13, 19, 5, 2, "steel" } }
G.knife = G.throwing_knife
G.short_bow = G.archer
G.climb_pick = { { "l", 6, 20, 15, 7, 2.2, "wood" }, { "a", 15, 9, 10, 2, 0.5, 30, "steel" } }
G.snare = G.trapper

-- Cosmetic slots ---------------------------------------------------------------------------------------------------
G.skin = { { "l", 5, 19, 13, 11, 2.4, "wood" }, { "R", 12, 4, 8, 9, 20, "steel" }, { "c", 18, 17, 4, "sun" } }
G.kill_effect = { { "c", 7, 8, 3, "ink2" }, { "c", 16, 6, 2.4, "ink2" }, { "c", 12, 13, 3.4, "ink" }, { "c", 6, 17, 2.4, "ink2" }, { "c", 18, 15, 3, "ink2" } }
G.kill_icon = { { "o", 12, 12, 18, 2, "ink" }, { "r", 8, 8, 8, 8, 45, "ink2" } }
G.banner = { { "r", 5, 4, 2, 17, 0, "wood" }, { "r", 7, 5, 12, 9, 0, "ink" }, { "r", 7, 13, 12, 1.6, 0, "brass" } }
G.emote = { { "c", 12, 6, 5, "ink" }, { "l", 12, 9, 12, 15, 2.4, "ink" }, { "l", 12, 11, 6, 7, 2.2, "ink" }, { "l", 12, 11, 18, 7, 2.2, "ink" }, { "l", 12, 15, 8, 21, 2.2, "ink" }, { "l", 12, 15, 16, 21, 2.2, "ink" } }

-- Lookups -----------------------------------------------------------------------------------------------------------
local SKILL = {
	Fists = "head_kick", ShortBlade = "chained_strikes", Sword = "running_cut", Axe = "whirl", Spear = "vault_kick",
	Throwing = "ricochet", Bow = "piercing_shot",
}
local KIT = { archer = "archer", forager = "forager", hunter = "trapper", trapper = "trapper", medic = "medic", climber = "climber" }

function Icons.forSkill(id: string?): string
	if type(id) ~= "string" then
		return "none"
	end
	return SKILL[id] or (if G[id] then id else "none")
end

function Icons.forKit(id: string?): string
	return KIT[string.lower(tostring(id or ""))] or "crate"
end

function Icons.forItem(id: string?): string
	if type(id) ~= "string" then
		return "none"
	end
	if G[id] then
		return id
	end
	if string.find(id, "water") or string.find(id, "bottle") then
		return "water"
	end
	return "crate"
end

function Icons.has(name: string): boolean
	return G[name] ~= nil or Icons.Sheet.Cells[name] ~= nil
end

function Icons.names(): { string }
	local out = {}
	for name in pairs(G) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

-- Drawing ------------------------------------------------------------------------------------------------------------
local function toneOf(key: any, override: Color3?): Color3
	if override then
		return override
	end
	return if type(key) == "string" and T[key] then T[key] else T.ink
end

local function corner(f: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = f
end

local function u(v: number): number
	return v / 24
end

local function part(holder: Frame, spec: { any }, i: number, tone: Color3?)
	local kind = spec[1]
	local f = Instance.new("Frame")
	f.Name = "P" .. i
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 0
	if kind == "r" or kind == "R" then
		f.Position = UDim2.fromScale(u(spec[2]), u(spec[3]))
		f.Size = UDim2.fromScale(u(spec[4]), u(spec[5]))
		f.Rotation = spec[6] or 0
		f.BackgroundColor3 = toneOf(spec[7], tone)
		if kind == "R" then
			corner(f, UDim.new(0.25, 0))
		end
	elseif kind == "c" then
		local d = spec[4]
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(u(spec[2]), u(spec[3]))
		f.Size = UDim2.fromScale(u(d), u(d))
		f.BackgroundColor3 = toneOf(spec[5], tone)
		corner(f, UDim.new(1, 0))
	elseif kind == "o" or kind == "a" then
		local d = spec[4]
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(u(spec[2]), u(spec[3]))
		f.Size = UDim2.fromScale(u(d), u(d))
		f.BackgroundTransparency = 1
		corner(f, UDim.new(1, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Ink"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = toneOf(if kind == "o" then spec[6] else spec[8], tone)
		stroke.Thickness = 1 -- set from the drawn size (Icons keeps it in step)
		stroke:SetAttribute("Units", spec[5])
		stroke.Parent = f
		if kind == "a" then
			local keep = math.clamp(spec[6] or 0.5, 0.02, 0.98)
			local g = Instance.new("UIGradient")
			g.Rotation = (spec[7] or 0) + 90 -- keep the part "above" the cut by default (rot 0 = the top half)
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(keep - 0.01, 0),
				NumberSequenceKeypoint.new(keep, 1), NumberSequenceKeypoint.new(1, 1),
			})
			g.Parent = stroke
		end
	elseif kind == "l" then
		local x1, y1, x2, y2, thick = spec[2], spec[3], spec[4], spec[5], spec[6]
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(u((x1 + x2) / 2), u((y1 + y2) / 2))
		f.Size = UDim2.fromScale(u(len + thick), u(thick))
		f.Rotation = math.deg(math.atan2(dy, dx))
		f.BackgroundColor3 = toneOf(spec[7], tone)
		corner(f, UDim.new(1, 0))
	end
	f.Parent = holder
end

-- Ring thickness follows the drawn size (a UIStroke is in pixels, not a share of its frame)
local function keepStrokes(holder: Frame)
	local function apply()
		-- AbsoluteSize includes every UIScale above, and so does a stroke's Thickness: take the scale back out
		local scale = 1
		local node = holder.Parent
		while node and node:IsA("GuiObject") do
			local s = node:FindFirstChildOfClass("UIScale")
			if s then
				scale *= s.Scale
			end
			node = node.Parent
		end
		local px = holder.AbsoluteSize.X / math.max(scale, 0.01)
		if px < 1 then
			return
		end
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("UIStroke") and d.Name == "Ink" then
				local units = d:GetAttribute("Units")
				if type(units) == "number" then
					d.Thickness = math.max(1, units * px / 24)
				end
			end
		end
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	task.defer(apply)
end

local SKIP = { Tone = true }

function Icons.make(name: string, props: { [string]: any }?): GuiObject
	local p = props or {}
	local sheet = Icons.Sheet
	local cell = sheet.Cells[name]
	local out: GuiObject
	if sheet.Image ~= "" and cell then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = sheet.Image
		img.ImageRectOffset = Vector2.new(cell[1] * sheet.Cell, cell[2] * sheet.Cell)
		img.ImageRectSize = Vector2.new(sheet.Cell, sheet.Cell)
		img.ScaleType = Enum.ScaleType.Fit
		if p.Tone then
			img.ImageColor3 = p.Tone
		end
		out = img
	else
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		local parts = G[name] or G.none
		for i, spec in ipairs(parts) do
			part(holder, spec, i, p.Tone)
		end
		keepStrokes(holder)
		out = holder
	end
	out.Name = "Icon"
	out:SetAttribute("IconName", name)
	out.Size = UDim2.fromScale(1, 1)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = out
	local parent = p.Parent
	for key, value in pairs(p) do
		if key ~= "Parent" and not SKIP[key] then
			(out :: any)[key] = value
		end
	end
	if parent then
		out.Parent = parent
	end
	return out
end

function Icons.tint(icon: Instance, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
		return
	end
	for _, d in ipairs(icon:GetDescendants()) do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundColor3 = color
		elseif d:IsA("UIStroke") and d.Name == "Ink" then
			d.Color = color
		end
	end
end

return Icons
