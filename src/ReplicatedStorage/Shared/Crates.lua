--[[
	Crates - the five Gold crates of CASES (docs/design/CardMenusAndShop.md sections 2.4, 3.2 to 3.5, 3.10): their
	odds by grade, pity, the Lucky Acorn (better of two), duplicates, Numbered, the Shelf, and each player's own odds.
	Shared by the server (ShopService rolls with these numbers) and the client (ShopController shows them), so the odds
	a player reads are the odds the server rolls. Every table here sums to 100 (Crates.selfCheck()).

	Grades (cosmetics only): Plain, Crafted, Prized, Storied, Fabled (+ Honour: earned-only, never in a crate).
	Weapons show stars, never a grade (their odds stay in Shared.Rewards).

	The catalogue: Shared.Cosmetics (the cosmetics agent's module) when it exists and lists items with a grade and
	"C" among their sources; until then the 44 crate items of section 3.1 below (Crates.Fallback). Either way an item
	is { id, name, type, weapon?, grade, look, tint? }.

	Rules kept (docs/design/RandomItemRules_2026-11-18.md):
	  * odds before buying, per grade and per item, as the player's own (only items they do not own are drawn)
	  * no empty outcome: a crate always gives an item, or Gold back when the player owns the whole grade
	  * pity and the Acorn are probability modifiers: shown as numbers, the shown odds change while they are on
	  * a grade the crate cannot give is not listed (no 0% lines)

	API
	  Crates.Grades                        { "Plain", "Crafted", "Prized", "Storied", "Fabled" } (order = rank)
	  Crates.GradeRank[grade] -> 1..5      Crates.GradeColor[grade] -> Color3   Crates.GradeLabel[grade] -> Color3
	  Crates.List / Crates.ById[id]        { id, name, gold, line, odds = { {grade, pct} }, pity = { storied?, fabled? } }
	  Crates.items() -> { item }           Crates.item(id) -> item?     Crates.pool(grade) -> { item }
	  Crates.acornOdds(crate) -> { {grade, pct} }                       better of two rolls
	  Crates.playerOdds(crate, owned, acorn) -> rows                     per grade: { grade, pct, items = { {id, pct} },
	                                                                     full = owned the whole grade, goldBack }
	  Crates.pityLeft(crate, pity) -> { storied = n?, fabled = n? }       crates until certain (n = this many more)
	  Crates.roll(crate, pity, acorn, rng) -> grade, info               info = { rolls = {g1, g2?}, pity = "Storied"? }
	  Crates.notePity(crate, pity, grade)                                updates { s, f } after a draw (each crate once)
	  Crates.pickItem(grade, owned, rng) -> id?, duplicate               an unowned item of that grade, or nil (Gold back)
	  Crates.goldBack(crate, grade) -> number                           Plain 30% ... Fabled 150% of the crate's price
	  Crates.numberedRoll(rng) -> boolean                               a Fabled arrives Numbered 1 in 10
	  Crates.shelf(dayIndex, owned) -> { id }                            6 a day, the same in every server
	  Crates.shelfPrice(grade) -> number
	  Crates.buildModel(crateId) -> Model                               a part-built crate (Lid is a child Model)
	  Crates.fmt(pct) -> "40%" / "41.44%"                               Crates.comma(n)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = {}

Crates.Grades = { "Plain", "Crafted", "Prized", "Storied", "Fabled" }
Crates.GradeRank = { Plain = 1, Crafted = 2, Prized = 3, Storied = 4, Fabled = 5, Honour = 6 }
Crates.GradeColor = {
	Plain = Color3.fromRGB(163, 157, 144), -- stone #A39D90
	Crafted = Color3.fromRGB(184, 122, 82), -- copper #B87A52
	Prized = Color3.fromRGB(94, 158, 142), -- verdigris #5E9E8E
	Storied = Color3.fromRGB(158, 92, 120), -- mulberry #9E5C78
	Fabled = Color3.fromRGB(201, 211, 224), -- moonstone #C9D3E0
	Honour = Color3.fromRGB(232, 217, 176), -- parchment #E8D9B0
}
-- text in the grade's colour (Storied is lifted for contrast on the dark card)
Crates.GradeLabel = table.clone(Crates.GradeColor)
Crates.GradeLabel.Storied = Color3.fromRGB(197, 138, 163) -- #C58AA3

-- Duplicates: Gold back as a share of the crate's price, only when the player owns the whole grade
Crates.DuplicateShare = { Plain = 0.3, Crafted = 0.4, Prized = 0.6, Storied = 1.0, Fabled = 1.5 }
Crates.NumberedChance = 0.1 -- a Fabled item: 1 in 10 arrives Numbered
Crates.ShelfPrice = { Plain = 400, Crafted = 900, Prized = 2000, Storied = 4500, Fabled = 12000 }
Crates.ShelfPerDay = 6

Crates.List = {
	{ id = "timber", name = "Timber Crate", gold = 300, line = "One cosmetic. Mostly Plain, a fair chance of Crafted.",
		odds = { { "Plain", 70 }, { "Crafted", 25 }, { "Prized", 5 } }, pity = {} },
	{ id = "ironbound", name = "Ironbound Crate", gold = 750, line = "One cosmetic: a skin, kill effect, kill icon, banner or emote.",
		odds = { { "Plain", 45 }, { "Crafted", 35 }, { "Prized", 15 }, { "Storied", 4.5 }, { "Fabled", 0.5 } }, pity = {} },
	{ id = "steel", name = "Steel Crate", gold = 1500, line = "One cosmetic: a skin, kill effect, kill icon, banner or emote.",
		odds = { { "Plain", 20 }, { "Crafted", 40 }, { "Prized", 28 }, { "Storied", 10 }, { "Fabled", 2 } },
		pity = { storied = 15 } },
	{ id = "silverleaf", name = "Silverleaf Crate", gold = 3000, line = "Crafted or better. Storied certain by the 8th.",
		odds = { { "Crafted", 35 }, { "Prized", 40 }, { "Storied", 20 }, { "Fabled", 5 } },
		pity = { storied = 8, fabled = 50 } },
	{ id = "crown", name = "Crown Crate", gold = 6000, line = "Prized or better. Fabled certain by the 20th.",
		odds = { { "Prized", 50 }, { "Storied", 38 }, { "Fabled", 12 } }, pity = { fabled = 20 } },
}
Crates.ById = {}
for i, c in ipairs(Crates.List) do
	c.order = i
	Crates.ById[c.id] = c
end

-- The 44 crate items of season one (section 3.1, source C). Used while Shared.Cosmetics does not exist.
local function I(id, name, kind, weapon, grade, look, tint)
	return { id = id, name = name, type = kind, weapon = weapon, grade = grade, look = look, tint = tint }
end
local rgb = Color3.fromRGB
Crates.Fallback = {
	-- Plain (11)
	I("blued_steel", "Blued Steel", "Skin", "sword", "Plain", "Heat-blued slate blade, plain guard, brown grip.", rgb(96, 112, 130)),
	I("field_green", "Field Green", "Skin", "knife", "Plain", "Olive-drab scales, stonewashed blade.", rgb(104, 112, 74)),
	I("driftwood", "Driftwood", "Skin", "spear", "Plain", "Bleached haft, rope lashing at the socket.", rgb(196, 186, 164)),
	I("birchbark", "Birchbark", "Skin", "short_bow", "Plain", "Limbs wrapped in pale birch bark.", rgb(214, 208, 192)),
	I("bone_grip", "Bone Grip", "Skin", "throwing_knife", "Plain", "Pale bone handles, satin blades.", rgb(222, 212, 188)),
	I("checker_plate", "Checker Plate", "Wrap", nil, "Plain", "Steel parts take a diamond-plate texture.", rgb(150, 156, 160)),
	I("ash_scatter", "Ash Scatter", "Kill effect", nil, "Plain", "The figure greys and blows away as pale ash.", rgb(190, 186, 178)),
	I("crossed_axes", "Crossed Axes", "Kill icon", nil, "Plain", "Two hatchets crossed on a leather disc.", rgb(150, 156, 160)),
	I("oak_and_iron", "Oak and Iron", "Banner", nil, "Plain", "Oak planks with two iron straps.", rgb(142, 107, 76)),
	I("whetstone", "Whetstone", "Emote", nil, "Plain", "Two strokes of a stone, then check the edge.", rgb(140, 140, 136)),
	I("steam_vent", "Steam Vent", "Launch effect", nil, "Plain", "White steam jets from the plinth's base.", rgb(226, 228, 230)),
	-- Crafted (10)
	I("riverstone", "Riverstone", "Skin", "sword", "Crafted", "Grey wave-forged blade, slate cord grip.", rgb(132, 138, 142)),
	I("northwood", "Northwood", "Skin", "hatchet", "Crafted", "Oiled ash haft with three knotwork bands.", rgb(170, 132, 90)),
	I("ironbark", "Ironbark", "Skin", "twin_axe", "Crafted", "Blackened-brown heads, bark-relief haft.", rgb(88, 70, 58)),
	I("antler", "Antler", "Skin", "knife", "Crafted", "Antler handle, brass bolster.", rgb(196, 174, 140)),
	I("brass_spine", "Brass Spine", "Skin", "machete", "Crafted", "Brass-capped spine, tan cord grip.", rgb(201, 162, 78)),
	I("glacier_guide", "Glacier Guide", "Skin", "climb_pick", "Crafted", "Chipped blue-grey enamel, birch haft.", rgb(110, 136, 160)),
	I("petal_fall", "Petal Fall", "Kill effect", nil, "Crafted", "Cream petals drift down in a slow spiral.", rgb(240, 226, 200)),
	I("leaf_swirl", "Leaf Swirl", "Kill effect", nil, "Crafted", "A ring of autumn leaves spins up and away.", rgb(196, 120, 60)),
	I("blade_twirl", "Blade Twirl", "Emote", nil, "Crafted", "Spin the weapon twice and catch it.", rgb(170, 170, 166)),
	I("dust_ring", "Dust Ring", "Launch effect", nil, "Crafted", "A ring of dust rolls out when the plate stops.", rgb(186, 170, 140)),
	-- Prized (11)
	I("temper_line", "Temper Line", "Skin", "sword", "Prized", "Straw-to-blue temper bands up the blade.", rgb(176, 150, 96)),
	I("rime", "Rime", "Skin", "hatchet", "Prized", "Frosted-grey head with a crystalline rime.", rgb(200, 210, 218)),
	I("twin_moons", "Twin Moons", "Skin", "paired_blades", "Prized", "One pale silver blade, one gunmetal.", rgb(180, 186, 194)),
	I("moonring", "Moonring", "Skin", "ring_blade", "Prized", "Satin hoop with an engraved crescent band.", rgb(196, 200, 206)),
	I("verdigris", "Verdigris", "Skin", "leaf_dagger", "Prized", "Copper-green patina, darker in the veins.", rgb(94, 158, 142)),
	I("sandstone", "Sandstone", "Wrap", nil, "Prized", "Banded ochre and buff sandstone surfaces.", rgb(196, 160, 110)),
	I("paper_confetti", "Paper Confetti", "Kill effect", nil, "Prized", "A burst of matte paper in the arena flag colours.", rgb(220, 200, 150)),
	I("wolf_head", "Wolf Head", "Kill icon", nil, "Prized", "A slate-blue wolf head with a cream outline.", rgb(96, 116, 140)),
	I("mountain_dawn", "Mountain Dawn", "Banner", nil, "Prized", "Blue mountains under an apricot sky.", rgb(232, 170, 120)),
	I("campfire_hands", "Campfire Hands", "Emote", nil, "Prized", "Crouch and warm the hands over a small fire.", rgb(214, 140, 70)),
	I("leaf_ring", "Leaf Ring", "Launch effect", nil, "Prized", "Leaves spiral up during the rise.", rgb(150, 160, 80)),
	-- Storied (8)
	I("oakcrown", "Oakcrown", "Skin", "sword", "Storied", "Oak-leaf quillons, brass inlay in the fuller.", rgb(150, 116, 70)),
	I("copperhead", "Copperhead", "Skin", "hatchet", "Storied", "Hammered copper head with verdigris dents.", rgb(184, 112, 70)),
	I("jade_lacquer", "Jade Lacquer", "Skin", "paired_blades", "Storied", "Matte jade hilts with gold-leaf flecks.", rgb(86, 140, 110)),
	I("autumn_leaf", "Autumn Leaf", "Skin", "bow", "Storied", "Limbs carved with amber-to-rust maple leaves.", rgb(190, 110, 56)),
	I("flag_drop", "Flag Drop", "Kill effect", nil, "Storied", "A small arena pennant plants and flutters.", rgb(200, 190, 160)),
	I("frost_over", "Frost Over", "Kill effect", nil, "Storied", "Frost creeps up, then the figure becomes snowflakes.", rgb(210, 226, 240)),
	I("last_one_standing", "Last One Standing", "Emote", nil, "Storied", "Plant the weapon and look out at the horizon.", rgb(160, 150, 130)),
	I("banner_unfurl", "Banner Unfurl", "Launch effect", nil, "Storied", "Your banner drops from a pole behind you.", rgb(180, 150, 110)),
	-- Fabled (4)
	I("glacier", "Glacier", "Skin", "twin_axe", "Fabled", "Milky blue-white frosted stone heads, grey fur collar.", rgb(214, 226, 236)),
	I("stormcaller", "Stormcaller", "Skin", "spear", "Fabled", "A forked lightning line inlaid in silver.", rgb(150, 166, 186)),
	I("recall_beam", "Recall Beam", "Kill effect", nil, "Fabled", "A pale column of light lifts the fallen away.", rgb(236, 236, 226)),
	I("horned_helm", "Horned Helm", "Kill icon", nil, "Fabled", "A horned helm in steel with a brass rim.", rgb(170, 176, 182)),
}

-- The catalogue ------------------------------------------------------------------------------------------------------

local catalogue: { any }? = nil
local byId: { [string]: any } = {}
local byGrade: { [string]: { any } } = {}

local function hasCrateSource(item: any): boolean
	if item.crate == true then
		return true
	end
	local sources = item.sources or item.source
	if type(sources) == "string" then
		return string.find(sources, "C", 1, true) ~= nil
	end
	if type(sources) == "table" then
		for _, s in pairs(sources) do
			if s == "C" or s == "Crate" or s == "crate" then
				return true
			end
		end
	end
	return false
end

local function load()
	if catalogue then
		return
	end
	local list = {}
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and (shared:FindFirstChild("Cosmetics") or shared:FindFirstChild("CosmeticLooks"))
	if module and module:IsA("ModuleScript") then
		local ok, Cos = pcall(require, module)
		local items = ok and type(Cos) == "table" and (Cos.Items or Cos.List or Cos.Catalogue)
		if type(items) == "table" then
			for key, item in pairs(items) do
				if type(item) == "table" and Crates.GradeRank[item.grade] and Crates.GradeRank[item.grade] <= 5
					and hasCrateSource(item) then
					local id = item.id or (if type(key) == "string" then key else nil)
					if type(id) == "string" then
						table.insert(list, { id = id, name = item.name or id, type = item.type or item.kind or "Cosmetic",
							weapon = item.weapon, grade = item.grade, look = item.look or item.line or "", tint = item.tint
								or item.color })
					end
				end
			end
		end
	end
	if #list < 5 then
		list = Crates.Fallback
	end
	table.sort(list, function(a, b)
		local ra, rb = Crates.GradeRank[a.grade], Crates.GradeRank[b.grade]
		if ra ~= rb then
			return ra < rb
		end
		return a.id < b.id
	end)
	catalogue = list
	for _, g in ipairs(Crates.Grades) do
		byGrade[g] = {}
	end
	for _, item in ipairs(list) do
		byId[item.id] = item
		table.insert(byGrade[item.grade], item)
	end
	-- items outside the crates that a player may still own (Season Track, ranks) keep a name for the reveal
	for _, item in ipairs(Crates.Fallback) do
		if not byId[item.id] then
			byId[item.id] = item
		end
	end
end

function Crates.items(): { any }
	load()
	return catalogue :: { any }
end

function Crates.item(id: string): any
	load()
	return byId[id]
end

function Crates.pool(grade: string): { any }
	load()
	return byGrade[grade] or {}
end

-- Numbers -------------------------------------------------------------------------------------------------------------

function Crates.comma(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- "40%", "4.5%", "41.44%", "0.05%" (up to two decimals, trailing zeros dropped)
function Crates.fmt(p: number): string
	local r = math.floor(p * 100 + 0.5) / 100
	local s = string.format("%.2f", r)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s .. "%"
end

-- Better of two rolls: each grade's "this or better" chance q becomes 1 - (1 - q)^2.
function Crates.acornOdds(crate: any): { { any } }
	local rows = crate.odds
	local out = {}
	local n = #rows
	local atLeast = {}
	local acc = 0
	for i = n, 1, -1 do
		acc += rows[i][2] / 100
		atLeast[i] = acc
	end
	for i = 1, n do
		local q = math.min(1, atLeast[i])
		local qNext = if i < n then math.min(1, atLeast[i + 1]) else 0
		local boosted = (1 - (1 - q) ^ 2) - (1 - (1 - qNext) ^ 2)
		out[i] = { rows[i][1], math.floor(boosted * 1e6 + 0.5) / 1e4 }
	end
	return out
end

function Crates.goldBack(crate: any, grade: string): number
	return math.floor(crate.gold * (Crates.DuplicateShare[grade] or 0.3) + 0.5)
end

function Crates.shelfPrice(grade: string): number
	return Crates.ShelfPrice[grade] or 0
end

-- The player's own odds: per grade, and per item among the items they do not own.
function Crates.playerOdds(crate: any, owned: { [string]: any }?, acorn: boolean?): { any }
	load()
	local rows = if acorn then Crates.acornOdds(crate) else crate.odds
	local out = {}
	for _, row in ipairs(rows) do
		local grade, pct = row[1], row[2]
		local fresh = {}
		for _, item in ipairs(byGrade[grade] or {}) do
			if not (owned and owned[item.id] ~= nil) then
				table.insert(fresh, item.id)
			end
		end
		local items = {}
		for _, id in ipairs(fresh) do
			table.insert(items, { id = id, pct = pct / #fresh })
		end
		table.insert(out, { grade = grade, pct = pct, items = items, full = #fresh == 0,
			goldBack = Crates.goldBack(crate, grade) })
	end
	return out
end

-- Crates left until a grade is certain: storied = n means "Storied or better within n more crates".
function Crates.pityLeft(crate: any, pity: any): { [string]: number }
	local p = pity or {}
	local out = {}
	if crate.pity.storied then
		out.storied = math.max(1, crate.pity.storied - (p.s or 0))
	end
	if crate.pity.fabled then
		out.fabled = math.max(1, crate.pity.fabled - (p.f or 0))
	end
	return out
end

local function drawGrade(rows: { { any } }, r: number): string
	local roll = r * 100
	local acc = 0
	for _, row in ipairs(rows) do
		acc += row[2]
		if roll < acc then
			return row[1]
		end
	end
	return rows[#rows][1]
end

-- One crate's grade. pity = { s, f } (crates since Storied+ / since Fabled, before this one).
function Crates.roll(crate: any, pity: any, acorn: boolean?, rng: Random): (string, { [string]: any })
	local p = pity or {}
	local info = { rolls = {} }
	local g1 = drawGrade(crate.odds, rng:NextNumber())
	local grade = g1
	table.insert(info.rolls, g1)
	if acorn then
		local g2 = drawGrade(crate.odds, rng:NextNumber())
		table.insert(info.rolls, g2)
		if Crates.GradeRank[g2] > Crates.GradeRank[grade] then
			grade = g2
		end
	end
	-- pity: the certain grade when this crate is the last one before it
	if crate.pity.fabled and (p.f or 0) + 1 >= crate.pity.fabled and grade ~= "Fabled" then
		grade = "Fabled"
		info.pity = "Fabled"
	elseif crate.pity.storied and (p.s or 0) + 1 >= crate.pity.storied and Crates.GradeRank[grade] < 4 then
		-- Storied or better, in the crate's own Storied : Fabled proportion
		local storied, fabled = 0, 0
		for _, row in ipairs(crate.odds) do
			if row[1] == "Storied" then
				storied = row[2]
			elseif row[1] == "Fabled" then
				fabled = row[2]
			end
		end
		grade = if rng:NextNumber() * (storied + fabled) < storied then "Storied" else "Fabled"
		info.pity = "Storied"
	end
	return grade, info
end

-- After a draw: each crate counts once (an Acorn's second roll does not count twice).
function Crates.notePity(crate: any, pity: any, grade: string)
	local rank = Crates.GradeRank[grade] or 1
	if rank >= 5 then
		pity.f = 0
		pity.s = 0
	elseif rank >= 4 then
		pity.s = 0
		pity.f = (pity.f or 0) + 1
	else
		pity.s = (pity.s or 0) + 1
		pity.f = (pity.f or 0) + 1
	end
end

function Crates.pickItem(grade: string, owned: { [string]: any }?, rng: Random): (string?, boolean)
	load()
	local fresh = {}
	for _, item in ipairs(byGrade[grade] or {}) do
		if not (owned and owned[item.id] ~= nil) then
			table.insert(fresh, item.id)
		end
	end
	if #fresh == 0 then
		return nil, true
	end
	return fresh[rng:NextInteger(1, #fresh)], false
end

function Crates.numberedRoll(rng: Random): boolean
	return rng:NextNumber() < Crates.NumberedChance
end

-- The Shelf: 6 items a day from a fixed order (the same in every server), skipping what the player owns.
-- dayIndex = whole UTC days since 1970. 44 items at 6 a day: every item shows within 8 days.
function Crates.shelf(dayIndex: number, owned: { [string]: any }?): { string }
	load()
	local list = catalogue :: { any }
	local n = #list
	if n == 0 then
		return {}
	end
	-- a fixed shuffle (seeded), so neighbouring days mix grades
	local order = {}
	for i = 1, n do
		order[i] = i
	end
	local r = Random.new(4848)
	for i = n, 2, -1 do
		local j = r:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	local start = (dayIndex * Crates.ShelfPerDay) % n
	local k = 0
	while #out < Crates.ShelfPerDay and k < n do
		local item = list[order[(start + k) % n + 1]]
		if not (owned and owned[item.id] ~= nil) then
			table.insert(out, item.id)
		end
		k += 1
	end
	return out
end

function Crates.dayIndex(t: number?): number
	return math.floor((t or os.time()) / 86400)
end

-- Every odds table sums to 100 (with and without the Acorn). Returns ok, problems.
function Crates.selfCheck(): (boolean, { string })
	local problems = {}
	for _, crate in ipairs(Crates.List) do
		for _, rows in ipairs({ crate.odds, Crates.acornOdds(crate) }) do
			local sum = 0
			for _, row in ipairs(rows) do
				sum += row[2]
			end
			if math.abs(sum - 100) > 0.011 then
				table.insert(problems, string.format("%s sums to %.3f", crate.id, sum))
			end
		end
	end
	return #problems == 0, problems
end

-- 3D: a part-built crate per tier (matte, faceted; Blender models replace these later) -----------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local STYLE = {
	timber = { body = rgb(142, 104, 70), lid = rgb(156, 116, 80), trim = rgb(196, 176, 130), trimKind = "rope" },
	ironbound = { body = rgb(132, 96, 66), lid = rgb(146, 108, 74), trim = rgb(96, 102, 108), trimKind = "bands" },
	steel = { body = rgb(118, 126, 132), lid = rgb(132, 140, 146), trim = rgb(186, 150, 80), trimKind = "latch" },
	silverleaf = { body = rgb(176, 182, 186), lid = rgb(192, 198, 202), trim = rgb(150, 170, 150), trimKind = "leaf" },
	crown = { body = rgb(58, 70, 92), lid = rgb(68, 82, 106), trim = rgb(196, 160, 82), trimKind = "crown" },
	strongbox = { body = rgb(108, 114, 118), lid = rgb(124, 130, 134), trim = rgb(176, 140, 76), trimKind = "latches" },
	masterwork = { body = rgb(70, 74, 80), lid = rgb(84, 88, 94), trim = rgb(206, 170, 90), trimKind = "latches" },
}

-- crate space: bottom centre at the origin, front = -Z. Lid is a Model (PrimaryPart "LidPlate"), hinged at the back
-- top edge: rotate about Lid:GetAttribute("Hinge") (a CFrame) around X to open.
function Crates.buildModel(crateId: string): Model
	local s = STYLE[crateId] or STYLE.timber
	local m = Instance.new("Model")
	m.Name = "Crate_" .. crateId
	local W, H, D = 2.4, 1.3, 1.6
	local base = part(m, "Body", Vector3.new(W, H, D), CFrame.new(0, H / 2, 0), s.body)
	m.PrimaryPart = base
	-- plank seams on the front and sides (thin darker strips)
	if s.trimKind == "rope" or s.trimKind == "bands" then
		for i = 1, 2 do
			local y = H * i / 3
			part(m, "Seam", Vector3.new(W + 0.01, 0.04, D + 0.01), CFrame.new(0, y, 0), s.body:Lerp(Color3.new(0, 0, 0), 0.3))
		end
	end
	-- a foot rail
	part(m, "Foot", Vector3.new(W + 0.08, 0.12, D + 0.08), CFrame.new(0, 0.06, 0), s.body:Lerp(Color3.new(0, 0, 0), 0.25))
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	local LH = 0.32
	local plate = part(lid, "LidPlate", Vector3.new(W + 0.1, LH, D + 0.1), CFrame.new(0, H + LH / 2, 0), s.lid)
	lid.PrimaryPart = plate
	if s.trimKind == "rope" then
		for _, x in ipairs({ -1, 1 }) do
			local h = part(m, "Handle", Vector3.new(0.12, 0.3, 0.6), CFrame.new(x * (W / 2 + 0.07), H * 0.62, 0), s.trim, Enum.Material.Fabric)
			h.Shape = Enum.PartType.Block
		end
		part(m, "Clasp", Vector3.new(0.3, 0.3, 0.06), CFrame.new(0, H - 0.18, -D / 2 - 0.03), rgb(176, 168, 150))
	elseif s.trimKind == "bands" then
		for _, x in ipairs({ -0.7, 0.7 }) do
			part(m, "Band", Vector3.new(0.18, H + 0.02, D + 0.04), CFrame.new(x, H / 2, 0), s.trim, Enum.Material.Metal)
			part(lid, "BandLid", Vector3.new(0.18, LH + 0.04, D + 0.14), CFrame.new(x, H + LH / 2, 0), s.trim, Enum.Material.Metal)
		end
		part(m, "Clasp", Vector3.new(0.3, 0.32, 0.06), CFrame.new(0, H - 0.18, -D / 2 - 0.04), rgb(196, 190, 176))
	elseif s.trimKind == "latch" or s.trimKind == "leaf" or s.trimKind == "crown" then
		-- riveted edges
		for _, x in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				part(m, "Corner", Vector3.new(0.16, H + 0.02, 0.16), CFrame.new(x * (W / 2 - 0.06), H / 2, z * (D / 2 - 0.06)),
					s.body:Lerp(Color3.new(0, 0, 0), 0.22))
			end
		end
		part(m, "Latch", Vector3.new(0.4, 0.4, 0.08), CFrame.new(0, H - 0.22, -D / 2 - 0.04), s.trim, Enum.Material.Metal)
		if s.trimKind == "leaf" then
			local leaf = part(lid, "Leaf", Vector3.new(0.9, 0.06, 0.5), CFrame.new(0, H + LH + 0.03, 0) * CFrame.Angles(0, math.rad(30), 0), s.trim)
			leaf.Shape = Enum.PartType.Cylinder
			leaf.Size = Vector3.new(0.06, 0.55, 0.9)
			leaf.CFrame = CFrame.new(0, H + LH + 0.03, 0) * CFrame.Angles(0, math.rad(30), math.rad(90))
		elseif s.trimKind == "crown" then
			part(lid, "Boss", Vector3.new(0.7, 0.1, 0.5), CFrame.new(0, H + LH + 0.05, 0), s.trim, Enum.Material.Metal)
			for i = -1, 1 do
				part(lid, "Point", Vector3.new(0.12, 0.2, 0.12), CFrame.new(i * 0.24, H + LH + 0.18, 0), s.trim, Enum.Material.Metal)
			end
			part(m, "Rail", Vector3.new(W + 0.12, 0.08, D + 0.12), CFrame.new(0, 0.16, 0), s.trim, Enum.Material.Metal)
		end
	elseif s.trimKind == "latches" then
		for i = -1, 1 do
			part(m, "Latch", Vector3.new(0.26, 0.34, 0.08), CFrame.new(i * 0.6, H - 0.2, -D / 2 - 0.04), s.trim, Enum.Material.Metal)
		end
	end
	lid:SetAttribute("Hinge", CFrame.new(0, H, D / 2 + 0.05))
	lid.Parent = m
	m:SetAttribute("CrateId", crateId)
	return m
end

return Crates
