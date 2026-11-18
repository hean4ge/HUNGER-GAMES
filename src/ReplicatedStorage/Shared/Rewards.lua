--[[
	Rewards - Gold, the wheel, Strongboxes and the Armoury: the numbers and the odds (docs/design/Weapons_v2.md
	sections 4 and 5), shared by the server (CurrencyService, RewardsService) and the client (WheelController,
	CurrencyController) so the odds a player reads are the odds the server rolls.

	Every value here is a starting value. Config.Economy / Config.Wheel / Config.Strongbox, when they exist in
	Shared.Config, are laid over these defaults key by key (Weapons_v2 section 9.1 names them there).

	Roblox's rules (scratchpad wave8/rules/rules.md, read 18 Nov 2026) and where they changed the page:
	  * Gold is earned-only while Economy.RobuxGold is false: no developer product, pack or ad reward may ever grant
	    Gold or a spin while it is off. Then the wheel and the boxes are not "paid random items".
	  * With RobuxGold on, a spin or box paid with Gold is a paid random item: odds before every purchase (always shown
	    anyway), and players whose PolicyService info says ArePaidRandomItemsRestricted (or whose policy call failed)
	    cannot buy them (RewardsService checks on the server). The free daily spin and the Armoury stay open.
	  * No staking earned Gold on a draw that can return less than the stake (Community Standards, simulated gambling):
	    the page's 40 and 80 Gold wheel segments are below a paid spin's 150. So a PAID spin pays a Gold segment as at
	    least the stake (PaidGoldFloor), and a paid duplicate gives back at least the stake. The free spin keeps the
	    page's values. Wheel weapons never cost less than the stake to buy outright (Armoury 800).
	  * A weapon the player already owns at that star or better is the "once-only" case: the draw picks among the
	    pool weapons they do not have at that star first, so the shown star odds are their real odds; a duplicate (all
	    nine already owned at that star or better) is paid back in Gold.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rewards = {}

Rewards.Defaults = {
	Economy = {
		RobuxGold = false, -- Gold packs for Robux: designed, OFF. Turning it on makes the wheel and boxes paid random items.
		FullRewardsFrom = 8, -- real contenders for full round Gold
		HalfRewardsFrom = 4, -- 4 to 7 pay half; under 4 pay only taking part
		DailySoftCap = 3000, -- round Gold in a UTC day after which round Gold halves
		TakePart = 10,
		Placing = { { 1, 100 }, { 2, 70 }, { 3, 55 }, { 5, 40 }, { 10, 25 }, { 24, 12 }, { 48, 5 } }, -- { up to place, Gold }
		Defeat = 15,
		DefeatMax = 8,
		PerMinute = 2,
		MinutesMax = 20, -- 40 Gold
		Win = 50,
		FirstRoundOfDay = 50,
		FirstWinOfDay = 100,
		Challenge = 20,
		ChallengeMax = 3,
		AfkMove = 30, -- studs moved in the first AfkWindow seconds (or any action) to count as taking part
		AfkWindow = 60,
		-- Studio only: a test round with one or two players pays as if full (the head count rule would pay 10)
		StudioIgnoreHeadcount = true,
		-- Robux packs (OFF). ProductId 0 = no developer product exists; none is created by code. Prices are read from
		-- Roblox (GetProductInfoAsync) when the switch is on, never shown from here.
		Packs = {
			{ key = "Pouch", gold = 50, defaultPrice = 5, productId = 0 },
			{ key = "Purse", gold = 500, defaultPrice = 49, productId = 0 },
			{ key = "Satchel", gold = 1050, defaultPrice = 99, productId = 0 },
			{ key = "Coffer", gold = 2200, defaultPrice = 199, productId = 0 },
			{ key = "Chest", gold = 4600, defaultPrice = 399, productId = 0 },
			{ key = "Vault", gold = 9600, defaultPrice = 799, productId = 0 },
		},
	},
	Wheel = {
		FreePerDay = 1,
		SpinCost = 150,
		PaidPerDay = 10,
		Pity4 = 25, -- a 4-star or better weapon is certain by this spin without one
		SpinTime = 3.6, -- seconds the wheel turns
		PaidGoldFloor = true, -- a paid spin's Gold segment pays at least the stake (rules.md section 5)
	},
	Strongbox = {
		Cost = 400,
		MasterworkCost = 1200,
		Pity4 = 8,
		Pity5 = 40,
		DuplicateGold = { [3] = 100, [4] = 300, [5] = 900 }, -- free draws; a paid duplicate gives back at least the stake
	},
	Armoury = {
		Buy3 = 800, -- any pool weapon at 3 stars, chosen: the sure path, no chance
		Raise4 = 2500,
		Raise5 = 6000,
	},
}

-- the prize pool (never the Recurve Bow, throwing knives, arrows, armour or food)
Rewards.Pool = { "knife", "machete", "hatchet", "spear", "sword", "twin_axe", "ring_blade", "climb_pick", "short_bow" }
Rewards.InPool = {}
for _, id in ipairs(Rewards.Pool) do
	Rewards.InPool[id] = true
end
-- names for ids ItemDefs does not have yet (the new weapons land with the stars-kits work)
Rewards.FallbackNames = {
	knife = "Hunting Knife", machete = "Machete", hatchet = "Hatchet", spear = "Spear", sword = "Longsword",
	twin_axe = "Twin-Bit Axe", ring_blade = "Ring Blade", climb_pick = "Climbing Pick", short_bow = "Short Bow",
}

-- The wheel: outcomes with the page's chances (percent), and the segments as drawn (their sizes add to each
-- outcome's chance, so every segment is drawn at its true size). Angles run clockwise from the top, in degrees.
Rewards.WheelOutcomes = {
	{ key = "g40", kind = "gold", gold = 40, chance = 30 },
	{ key = "g80", kind = "gold", gold = 80, chance = 22 },
	{ key = "g200", kind = "gold", gold = 200, chance = 8 },
	{ key = "w3", kind = "weapon", stars = 3, chance = 28 },
	{ key = "w4", kind = "weapon", stars = 4, chance = 10 },
	{ key = "w5", kind = "weapon", stars = 5, chance = 2 },
}
-- 13 segments, alternating so no two of a kind touch: { outcome key, percent of the wheel }
Rewards.WheelSegments = {
	{ "g40", 7.5 }, { "w3", 28 / 3 }, { "g80", 11 }, { "w4", 5 }, { "g40", 7.5 }, { "w3", 28 / 3 }, { "g200", 8 },
	{ "g40", 7.5 }, { "w5", 2 }, { "g80", 11 }, { "w3", 28 / 3 }, { "g40", 7.5 }, { "w4", 5 },
}

Rewards.BoxOdds = {
	strongbox = { { 3, 72 }, { 4, 24 }, { 5, 4 } },
	masterwork = { { 4, 85 }, { 5, 15 } },
}

local merged: { [string]: any }? = nil

-- Defaults with Config.Economy / Config.Wheel / Config.Strongbox / Config.Armoury laid over them.
function Rewards.config(): { [string]: any }
	if merged then
		return merged
	end
	local out = {}
	local Config: any = nil
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Config")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			Config = result
		end
	end
	for section, values in pairs(Rewards.Defaults) do
		local t = table.clone(values)
		local over = Config and Config[section]
		if type(over) == "table" then
			for k, v in pairs(over) do
				t[k] = v
			end
		end
		out[section] = t
	end
	out.IsStudio = Config ~= nil and Config.IsStudio == true
	merged = out
	return out
end

function Rewards.weaponName(id: string): string
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("ItemDefs")
	if module then
		local ok, defs = pcall(require, module)
		local def = ok and defs and defs.Items and defs.Items[id]
		if def and type(def.name) == "string" then
			return def.name
		end
	end
	return Rewards.FallbackNames[id] or id
end

function Rewards.starText(n: number): string
	return string.rep("★", math.clamp(math.floor(n or 0), 0, 5))
end

function Rewards.outcome(key: string): { [string]: any }?
	for _, o in ipairs(Rewards.WheelOutcomes) do
		if o.key == key then
			return o
		end
	end
	return nil
end

-- A segment's start and end angle (degrees clockwise from the top) and its centre.
function Rewards.segmentAngles(index: number): (number, number, number)
	local a = 0
	for i, seg in ipairs(Rewards.WheelSegments) do
		local span = seg[2] * 3.6
		if i == index then
			return a, a + span, a + span / 2
		end
		a += span
	end
	return 0, 0, 0
end

-- Gold a wheel Gold outcome pays: the page's value, or at least the stake on a paid spin.
function Rewards.wheelGold(outcome: { [string]: any }, paid: boolean): number
	local cfg = Rewards.config().Wheel
	local gold = outcome.gold or 0
	if paid and cfg.PaidGoldFloor ~= false then
		gold = math.max(gold, cfg.SpinCost)
	end
	return gold
end

local function fmt(p: number): string
	if math.abs(p - math.floor(p)) < 1e-6 then
		return string.format("%d%%", p)
	end
	return string.format("%.1f%%", p)
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
Rewards.comma = comma

-- The one thin odds line shown before a spin or a box (rules.md section 2: every outcome, numerically).
function Rewards.wheelOddsLine(paid: boolean): string
	local parts = {}
	for _, o in ipairs(Rewards.WheelOutcomes) do
		if o.kind == "gold" then
			table.insert(parts, string.format("%s Gold %s", comma(Rewards.wheelGold(o, paid)), fmt(o.chance)))
		else
			table.insert(parts, string.format("%s weapon %s", Rewards.starText(o.stars), fmt(o.chance)))
		end
	end
	return table.concat(parts, "  ·  ")
end

function Rewards.boxOddsLine(kind: string): string
	local parts = {}
	for _, row in ipairs(Rewards.BoxOdds[kind] or {}) do
		table.insert(parts, string.format("%s %s", Rewards.starText(row[1]), fmt(row[2])))
	end
	return table.concat(parts, "  ·  ")
end

-- Draws a star count from a { { stars, percent } } table with a random number r in [0, 1).
function Rewards.drawStars(odds: { { number } }, r: number): number
	local roll = r * 100
	local acc = 0
	for _, row in ipairs(odds) do
		acc += row[2]
		if roll < acc then
			return row[1]
		end
	end
	return odds[#odds][1]
end

-- Picks a pool weapon for `stars`: one the player does not own at that star or better, if any (else any, flagged as
-- a duplicate). armoury = { [id] = stars }. Returns id, duplicate.
function Rewards.pickWeapon(armoury: { [string]: number }, stars: number, rng: Random): (string, boolean)
	local fresh = {}
	for _, id in ipairs(Rewards.Pool) do
		if (armoury[id] or 0) < stars then
			table.insert(fresh, id)
		end
	end
	if #fresh > 0 then
		return fresh[rng:NextInteger(1, #fresh)], false
	end
	return Rewards.Pool[rng:NextInteger(1, #Rewards.Pool)], true
end

-- Gold for a round (Weapons_v2 4.1). r = { tookPart, place, contenders (real), defeats, minutes, won, practice,
-- private, challenges, firstRoundOfDay, firstWinOfDay, dayGoldSoFar }. Returns total and the parts.
function Rewards.roundGold(r: { [string]: any }): (number, { [string]: number })
	local E = Rewards.config().Economy
	local parts = {}
	if r.practice or r.private or not r.tookPart then
		return 0, parts
	end
	parts.takePart = E.TakePart
	local headcount = r.contenders or 0
	local share = if headcount >= E.FullRewardsFrom then 1 elseif headcount >= E.HalfRewardsFrom then 0.5 else 0
	if share > 0 then
		local place = r.place or 0
		if place > 0 then
			for _, row in ipairs(E.Placing) do
				if place <= row[1] then
					parts.placing = row[2]
					break
				end
			end
		end
		parts.defeats = math.min(r.defeats or 0, E.DefeatMax) * E.Defeat
		parts.time = math.min(math.floor(r.minutes or 0), E.MinutesMax) * E.PerMinute
		parts.win = if r.won then E.Win else nil
		parts.challenges = math.min(r.challenges or 0, E.ChallengeMax) * E.Challenge
		for k, v in pairs(parts) do
			if k ~= "takePart" then
				parts[k] = math.floor(v * share + 0.5)
			end
		end
	end
	local total = 0
	for _, v in pairs(parts) do
		total += v
	end
	-- the daily soft cap halves round Gold past it (daily bonuses below are not round Gold)
	local before = r.dayGoldSoFar or 0
	if before + total > E.DailySoftCap then
		local over = before + total - math.max(before, E.DailySoftCap)
		local cut = math.floor(over / 2)
		parts.softCap = -cut
		total -= cut
	end
	if r.firstRoundOfDay then
		parts.firstRound = E.FirstRoundOfDay
		total += E.FirstRoundOfDay
	end
	if r.firstWinOfDay and r.won then
		parts.firstWin = E.FirstWinOfDay
		total += E.FirstWinOfDay
	end
	return total, parts
end

function Rewards.utcDay(t: number?): string
	return os.date("!%Y-%m-%d", t or os.time()) :: string
end

return Rewards
