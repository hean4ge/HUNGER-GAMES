--[[
	Progression - the numbers for the Season Track, the daily reward, Level ranks and the leaderboards
	(docs/design/CardMenusAndShop.md sections 2.5 to 2.8 and 3.6 to 3.9). Shared by the server (SeasonService,
	DailyService, RankService, LeaderboardService) and the client (SeasonController, DailyController, RanksController),
	so what a card shows is what the server pays.

	Config.Season / Config.Daily / Config.Ranks / Config.Boards are laid over the defaults here, key by key.
	The premium row is on only when Config.Shop.SeasonPremium is true AND Config.Shop.SeasonPremiumProductId is set.

	Saved data (DataService, Econ.Progress; sanitize() below is the only shape that is ever stored):
	  Progress = {
	    XP, Prestige, LevelPaid          Level XP since the last Prestige; Prestige 0..10; the highest level paid its Gold
	    Seeded                           true once an older save's rounds were turned into Level XP (RankService)
	    Band, BandShown                  the highest rank band granted (1 = Recruit .. 10 = Paragon) and shown in the train
	    Season = { id, xp, free, prem, premium, encore }   free / prem are claim strings ("1" = claimed) per tier
	    Daily = { last, next, streak, stamps }             last claimed UTC day, the next card (1..7), claims ever, stamps
	    Week = { key, Wins, Elims, Top5, Survive }         this ISO week's board values (Survive = best seconds)
	    Train = { day, n }                                 training passes paid XP today
	    Owed = { { k, id, n } }                           rewards waiting for the service that holds them (crates ...)
	    Honours = { [id] = true }                          earned-only marks this service keeps (titles, trims)
	  }
	A save from before this (no Progress) loads as a new player's Progress: level 1, tier 0, day 1.

	Rewards are tables { k = kind, n = amount?, id = string? }:
	  gold n · crate id n · acorn n · spins n · cosmetic id · trail id · title id · trim id · stamp
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = {}

Progression.Defaults = {
	Season = {
		Id = "S1",
		Name = "The First Ride",
		StartUnix = 1794787200, -- Monday 16 Nov 2026 00:00 UTC (the lead moves this to the launch day)
		Days = 42,
		Tiers = 50,
		TierXP = 1000,
		EncoreXP = 2500,
	},
	Daily = {
		Enabled = true,
		StampsForTrim = 4,
	},
	Ranks = {
		LevelBase = 400,
		LevelStep = 40,
		GoldPerLevel = 100,
		MaxLevel = 100,
		MaxPrestige = 10,
		Arena = false,
		TrainingXP = 25, -- XP for a passed drill in the Training Centre
		TrainingPerDay = 8, -- passes paid XP in a UTC day
	},
	Boards = {
		Enabled = true,
		ReadEvery = 120, -- seconds between reads of one board
		ReadStagger = 20, -- seconds between boards
		ReadTop = 50,
		FullFrom = 8, -- real contenders a round needs to count on the boards
		WritesSpread = 10, -- seconds the round-end writes are spread over
	},
}

-- XP per round (3.6). Shares like Gold: full from 8 real contenders, half from 4, under 4 only taking part.
Progression.RoundXP = {
	TakePart = 100,
	Placing = { { 1, 200 }, { 2, 150 }, { 3, 120 }, { 5, 90 }, { 10, 60 }, { 24, 30 }, { 48, 10 } },
	Defeat = 20,
	DefeatMax = 8,
	PerMinute = 5,
	MinutesMax = 20, -- 100 XP
	Win = 100,
	FullFrom = 8,
	HalfFrom = 4,
}

-- Crate ids as ShopService knows them (Shared/Crates.lua).
Progression.Crates = {
	Timber = "timber", Ironbound = "ironbound", Steel = "steel", Silverleaf = "silverleaf", Crown = "crown",
}
local C = Progression.Crates

local merged: { [string]: any }? = nil
function Progression.config(): { [string]: any }
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
	for section, values in pairs(Progression.Defaults) do
		local t = table.clone(values)
		local over = Config and Config[section]
		if type(over) == "table" then
			for k, v in pairs(over) do
				t[k] = v
			end
		end
		out[section] = t
	end
	local shop = Config and Config.Shop
	out.PremiumOn = type(shop) == "table" and shop.SeasonPremium == true and type(shop.SeasonPremiumProductId) == "number"
		and shop.SeasonPremiumProductId > 0
	out.PremiumProductId = if out.PremiumOn then shop.SeasonPremiumProductId else nil
	out.IsStudio = Config ~= nil and Config.IsStudio == true
	merged = out
	return out
end

--------------------------------------------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------------------------------------------

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
Progression.comma = comma

-- Names for cosmetic ids this module grants (the catalogue, Shared/Cosmetics, has the rest)
Progression.Names = {
	sk_hatchet_camp = "Camp Orange", resin = "Resin", wr_cobalt = "Cobalt Enamel",
	bn_ride = "The First Ride", bn_oak = "Oak and Iron", bn_dawn = "Mountain Dawn",
	ki_axes = "Crossed Axes", ki_compass = "Compass Star", le_dust = "Dust Ring",
	em_last = "Last One Standing", trim_warden = "Warden trim", trim_sentinel = "Sentinel trim",
	trim_paragon = "Paragon frame", trim_regular = "Regular trim", banner_top48 = "Top 48",
	sk_taxe_sunforge = "Sunforge Bronze", sk_bow_hornbow = "Hornbow", em_map = "Map Check",
	ke_feather = "Feather Burst", ke_bell = "Bell Toll", ki_laurel = "Laurel",
	gold_dust = "Gold Dust", sk_sword_starfall = "Starfall", slot_loadout = "Loadout slot",
}
-- Grades for the tile edge (Theme.Grade when it exists): nil = a plain reward (Gold, a crate, an Acorn)
Progression.Grades = {
	sk_hatchet_camp = "Plain", resin = "Plain", wr_cobalt = "Crafted", bn_ride = "Honour",
	bn_oak = "Plain", bn_dawn = "Prized", ki_axes = "Plain", ki_compass = "Crafted",
	le_dust = "Crafted", em_last = "Storied", trim_warden = "Honour", trim_sentinel = "Honour",
	trim_paragon = "Honour", trim_regular = "Honour", banner_top48 = "Honour", sk_taxe_sunforge = "Storied",
	sk_bow_hornbow = "Prized", em_map = "Crafted", ke_feather = "Prized", ke_bell = "Prized",
	ki_laurel = "Storied", gold_dust = "Fabled", sk_sword_starfall = "Fabled",
}

local CRATE_NAMES = { timber = "Timber Crate", ironbound = "Ironbound Crate", steel = "Steel Crate",
	silverleaf = "Silverleaf Crate", crown = "Crown Crate" }

function Progression.rewardText(r: { [string]: any }): string
	local k = r.k
	if k == "gold" then
		return comma(r.n or 0) .. " Gold"
	elseif k == "crate" then
		local name = CRATE_NAMES[r.id] or "Crate"
		return if (r.n or 1) > 1 then string.format("%d %ss", r.n, name) else name
	elseif k == "acorn" then
		return if (r.n or 1) > 1 then string.format("%d Lucky Acorns", r.n) else "Lucky Acorn"
	elseif k == "spins" then
		return string.format("%d wheel spin%s", r.n or 1, if (r.n or 1) == 1 then "" else "s")
	elseif k == "stamp" then
		return "a stamp"
	elseif k == "title" then
		return "Title: " .. tostring(r.id)
	elseif k == "slot" then
		return "Loadout slot " .. tostring(r.n or "")
	end
	return Progression.Names[r.id or ""] or tostring(r.id or k)
end

-- One line for a list of rewards ("Steel Crate + a stamp")
function Progression.rewardsText(list: { { [string]: any } }): string
	local parts = {}
	for _, r in ipairs(list) do
		table.insert(parts, Progression.rewardText(r))
	end
	return table.concat(parts, " + ")
end

--------------------------------------------------------------------------------------------------------------------
-- Time
--------------------------------------------------------------------------------------------------------------------

function Progression.utcDay(t: number?): string
	return os.date("!%Y-%m-%d", t or os.time()) :: string
end

-- Seconds until the next 00:00 UTC
function Progression.secondsToNextDay(t: number?): number
	local now = t or os.time()
	return 86400 - (now % 86400)
end

-- The day number (days since 1970) of a "YYYY-MM-DD" UTC day, or nil
function Progression.dayNumber(day: string): number?
	local y, m, d = string.match(day or "", "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	local t = os.time({ year = tonumber(y) :: number, month = tonumber(m) :: number, day = tonumber(d) :: number, hour = 12 })
	-- os.time reads the table as local time on some hosts: the noon anchor keeps the floor on the right day
	local utc = os.date("!*t", t) :: any
	local fix = (utc.hour - 12) * 3600
	return math.floor((t - fix) / 86400)
end

-- ISO week of a time: "2026-47", and the unix time of the Monday 00:00 UTC that starts the next week
function Progression.isoWeek(t: number?): (string, number)
	local now = t or os.time()
	local days = math.floor(now / 86400)
	local wday = (days + 3) % 7 -- 0 = Monday (1970-01-01 was a Thursday)
	local monday = days - wday
	local thursday = monday + 3 -- the ISO year is the year of this week's Thursday
	local th = os.date("!*t", thursday * 86400) :: any
	local week = math.floor((th.yday - 1) / 7) + 1
	return string.format("%04d-%02d", th.year, week), (monday + 7) * 86400
end

--------------------------------------------------------------------------------------------------------------------
-- Level and ranks (3.8)
--------------------------------------------------------------------------------------------------------------------

-- XP from level n to n + 1
function Progression.levelCost(n: number): number
	local R = Progression.config().Ranks
	return R.LevelBase + R.LevelStep * n
end

-- Total XP to reach level L from level 1
function Progression.totalFor(level: number): number
	local R = Progression.config().Ranks
	local m = level - 1
	return R.LevelBase * m + R.LevelStep * m * (m + 1) / 2
end

-- level, XP into it, XP it needs (need 0 at the top)
function Progression.levelOf(xp: number): (number, number, number)
	local R = Progression.config().Ranks
	local level = 1
	local left = math.max(0, xp)
	while level < R.MaxLevel do
		local cost = Progression.levelCost(level)
		if left < cost then
			return level, left, cost
		end
		left -= cost
		level += 1
	end
	return R.MaxLevel, 0, 0
end

-- The ten Level ranks. Emblem colours: stone, copper, steel, brass, moonstone, parchment (StyleA palette)
Progression.Ranks = {
	{ name = "Recruit", level = 1, chevrons = 1, metal = "stone", rewards = {} },
	{ name = "Runner", level = 10, chevrons = 2, metal = "stone",
		rewards = { { k = "slot", n = 3 }, { k = "cosmetic", id = "bn_oak" } } },
	{ name = "Scout", level = 20, chevrons = 1, metal = "copper",
		rewards = { { k = "slot", n = 4 }, { k = "acorn", n = 2 } } },
	{ name = "Tracker", level = 30, chevrons = 2, metal = "copper",
		rewards = { { k = "cosmetic", id = "ki_axes" }, { k = "crate", id = C.Steel, n = 1 } } },
	{ name = "Pathfinder", level = 40, chevrons = 2, metal = "steel",
		rewards = { { k = "cosmetic", id = "le_dust" }, { k = "acorn", n = 2 } } },
	{ name = "Ranger", level = 50, chevrons = 3, metal = "steel",
		rewards = { { k = "cosmetic", id = "ki_compass" }, { k = "crate", id = C.Silverleaf, n = 1 } } },
	{ name = "Warden", level = 60, chevrons = 2, metal = "brass",
		rewards = { { k = "trim", id = "trim_warden" }, { k = "acorn", n = 3 } } },
	{ name = "Vanguard", level = 70, chevrons = 3, metal = "brass",
		rewards = { { k = "cosmetic", id = "em_last" } } },
	{ name = "Sentinel", level = 80, chevrons = 3, metal = "moonstone",
		rewards = { { k = "trim", id = "trim_sentinel" }, { k = "crate", id = C.Crown, n = 1 } } },
	{ name = "Paragon", level = 90, chevrons = 3, metal = "parchment",
		rewards = { { k = "trim", id = "trim_paragon" }, { k = "cosmetic", id = "bn_dawn" } } },
}
Progression.Metals = {
	stone = Color3.fromRGB(163, 157, 144), copper = Color3.fromRGB(184, 122, 82), steel = Color3.fromRGB(167, 174, 178),
	brass = Color3.fromRGB(201, 162, 78), moonstone = Color3.fromRGB(201, 211, 224), parchment = Color3.fromRGB(232, 217, 176),
}

-- The band index (1..10) of a level
function Progression.bandOf(level: number): number
	local band = 1
	for i, r in ipairs(Progression.Ranks) do
		if level >= r.level then
			band = i
		end
	end
	return band
end

function Progression.rankOf(level: number): { [string]: any }
	return Progression.Ranks[Progression.bandOf(level)]
end

--------------------------------------------------------------------------------------------------------------------
-- Season Track (3.6)
--------------------------------------------------------------------------------------------------------------------

local function gold(n: number) return { k = "gold", n = n } end

-- Free row: Gold on 35 tiers (4,000 in all), 4 Timber, 2 Ironbound, 1 Steel, 4 Acorns, 4 items
local FREE_SPECIAL = {
	[2] = { k = "cosmetic", id = "sk_hatchet_camp" },
	[4] = { k = "crate", id = C.Timber, n = 1 },
	[7] = { k = "acorn", n = 1 },
	[10] = { k = "trail", id = "resin" },
	[12] = { k = "crate", id = C.Timber, n = 1 },
	[15] = { k = "crate", id = C.Ironbound, n = 1 },
	[18] = { k = "acorn", n = 1 },
	[20] = { k = "crate", id = C.Timber, n = 1 },
	[23] = { k = "crate", id = C.Ironbound, n = 1 },
	[25] = { k = "cosmetic", id = "wr_cobalt" },
	[26] = { k = "crate", id = C.Timber, n = 1 },
	[30] = { k = "acorn", n = 1 },
	[35] = { k = "crate", id = C.Steel, n = 1 },
	[40] = { k = "acorn", n = 1 },
	[50] = { k = "cosmetic", id = "bn_ride" },
}
local FREE_GOLD = { [21] = 300, [45] = 300, [29] = 200 }
Progression.FreeRow = {}
for tier = 1, 50 do
	Progression.FreeRow[tier] = FREE_SPECIAL[tier] or gold(FREE_GOLD[tier] or 100)
end

-- Premium row (designed, OFF): fixed items only, never Gold, crates or Acorns
local PREM_SPECIAL = {
	[1] = { k = "cosmetic", id = "sk_taxe_sunforge" },
	-- (integrate, 20 Nov: ids as Shared.CosmeticLooks' aliases spell them, so the item equips and shows in a round)
	[21] = { k = "cosmetic", id = "sk_bow_horn" },
	[22] = { k = "cosmetic", id = "ki_compass" },
	[23] = { k = "cosmetic", id = "em_map" },
	[24] = { k = "cosmetic", id = "ke_feathers" },
	[25] = { k = "cosmetic", id = "ke_bell" },
	[26] = { k = "cosmetic", id = "ki_laurel" },
	[45] = { k = "trail", id = "gold_dust" },
	[50] = { k = "cosmetic", id = "sk_sword_starfall" },
}
local TITLES = { "Night Rider", "Stoker", "Brakeman", "Conductor", "Signalman", "Fireman", "Porter", "Guard",
	"Switchman", "Lampman", "Coalman", "Linesman", "Flagman", "Dispatcher" }
Progression.PremiumRow = {}
do
	local t = 0
	for tier = 1, 50 do
		if PREM_SPECIAL[tier] then
			Progression.PremiumRow[tier] = PREM_SPECIAL[tier]
		elseif tier % 3 == 0 then
			Progression.PremiumRow[tier] = { k = "trim", id = string.format("trim_s1_%02d", tier) }
		else
			t = t % #TITLES + 1
			Progression.PremiumRow[tier] = { k = "title", id = TITLES[t] }
		end
	end
end

-- Encore (after tier 50, every EncoreXP): the free row's Gold and Acorn tiers again, in order; numbered trims at
-- Encores 1, 2, 3, 5, 7 and 10
Progression.EncoreTrims = { [1] = true, [2] = true, [3] = true, [5] = true, [7] = true, [10] = true }
local ENCORE_POOL = {}
for tier = 1, 50 do
	local r = Progression.FreeRow[tier]
	if r.k == "gold" or r.k == "acorn" then
		table.insert(ENCORE_POOL, r)
	end
end
function Progression.encoreReward(n: number): { { [string]: any } }
	local list = { ENCORE_POOL[(n - 1) % #ENCORE_POOL + 1] }
	if Progression.EncoreTrims[n] then
		table.insert(list, { k = "trim", id = string.format("trim_encore_%02d", n) })
	end
	return list
end

-- tier reached (0..Tiers), XP into the next, XP a tier needs, encores reached
function Progression.tierOf(seasonXP: number): (number, number, number, number)
	local S = Progression.config().Season
	local xp = math.max(0, seasonXP)
	local tier = math.min(S.Tiers, math.floor(xp / S.TierXP))
	if tier < S.Tiers then
		return tier, xp - tier * S.TierXP, S.TierXP, 0
	end
	local over = xp - S.Tiers * S.TierXP
	local encores = math.floor(over / S.EncoreXP)
	return S.Tiers, over - encores * S.EncoreXP, S.EncoreXP, encores
end

-- The season's end (unix), and whether it is running now
function Progression.seasonWindow(t: number?): (number, number, boolean)
	local S = Progression.config().Season
	local now = t or os.time()
	local start = tonumber(S.StartUnix) or 0
	local finish = start + S.Days * 86400
	return start, finish, now >= start and now < finish
end

--------------------------------------------------------------------------------------------------------------------
-- Daily reward (3.7)
--------------------------------------------------------------------------------------------------------------------

Progression.DailyRewards = {
	{ { k = "gold", n = 150 } },
	{ { k = "crate", id = C.Timber, n = 1 } },
	{ { k = "gold", n = 300 } },
	{ { k = "spins", n = 2 } },
	{ { k = "crate", id = C.Ironbound, n = 1 } },
	{ { k = "acorn", n = 1 }, { k = "gold", n = 300 } },
	{ { k = "crate", id = C.Steel, n = 1 }, { k = "stamp" } },
}

--------------------------------------------------------------------------------------------------------------------
-- Round XP
--------------------------------------------------------------------------------------------------------------------

-- r = { tookPart, place, contenders, defeats, minutes, won, practice, private }. Returns total and parts.
function Progression.roundXP(r: { [string]: any }): (number, { [string]: number })
	local X = Progression.RoundXP
	local parts = {}
	if r.practice or r.private or not r.tookPart then
		return 0, parts
	end
	parts.takePart = X.TakePart
	local headcount = r.contenders or 0
	local share = if headcount >= X.FullFrom then 1 elseif headcount >= X.HalfFrom then 0.5 else 0
	if share > 0 then
		local place = r.place or 0
		if place > 0 then
			for _, row in ipairs(X.Placing) do
				if place <= row[1] then
					parts.placing = row[2]
					break
				end
			end
		end
		parts.defeats = math.min(r.defeats or 0, X.DefeatMax) * X.Defeat
		parts.time = math.min(math.floor(r.minutes or 0), X.MinutesMax) * X.PerMinute
		parts.win = if r.won then X.Win else nil
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
	return total, parts
end

--------------------------------------------------------------------------------------------------------------------
-- Leaderboards (3.9)
--------------------------------------------------------------------------------------------------------------------

-- key: what is written; all / week: which OrderedDataStores exist; max: keep the best (not a sum)
Progression.Boards = {
	{ id = "Wins", name = "Wins", sub = "rounds won", all = true, week = true },
	{ id = "Elims", name = "Eliminations", sub = "defeats dealt", all = true, week = true },
	{ id = "Top5", name = "Top 5 finishes", sub = "weekly only", all = false, week = true },
	{ id = "Survive", name = "Longest survival", sub = "one round, weekly", all = false, week = true, max = true, time = true },
	{ id = "Level", name = "Level", sub = "and Prestige, all time", all = true, week = false, max = true, level = true },
	{ id = "RP", name = "Arena Rank", sub = "season, later", all = false, week = false, later = true },
}
function Progression.board(id: string): { [string]: any }?
	for _, b in ipairs(Progression.Boards) do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- The OrderedDataStore name of a board ("LB_Wins_All", "LB_Wins_W2026-47")
function Progression.boardKey(id: string, scope: string, t: number?): string
	if scope == "all" then
		return string.format("LB_%s_All", id)
	end
	local week = Progression.isoWeek(t)
	return string.format("LB_%s_W%s", id, week)
end

-- A Level board value: prestige x 1000 + level
function Progression.levelValue(prestige: number, level: number): number
	return prestige * 1000 + level
end

--------------------------------------------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------------------------------------------

local function count(v: any, max: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.clamp(math.floor(v), 0, max)
end

local function bits(v: any): string
	if type(v) ~= "string" then
		return ""
	end
	local s = string.sub(v, 1, 64)
	return (string.gsub(s, "[^01]", "0"))
end

local function str(v: any, max: number): string
	return if type(v) == "string" and #v <= max then v else ""
end

function Progression.sanitize(raw: any): { [string]: any }
	local src = if type(raw) == "table" then raw else {}
	local out = {
		XP = count(src.XP, 1e9),
		Prestige = count(src.Prestige, 10),
		LevelPaid = count(src.LevelPaid, 100),
		Band = count(src.Band, 10),
		BandShown = count(src.BandShown, 10),
		Seeded = src.Seeded == true, -- an older save's past rounds were turned into Level XP once
	}
	local s = if type(src.Season) == "table" then src.Season else {}
	out.Season = {
		id = str(s.id, 16),
		xp = count(s.xp, 1e8),
		free = bits(s.free),
		prem = bits(s.prem),
		premium = s.premium == true,
		encore = count(s.encore, 10000),
	}
	local d = if type(src.Daily) == "table" then src.Daily else {}
	out.Daily = {
		last = str(d.last, 10),
		next = math.max(1, count(d.next, 7)),
		streak = count(d.streak, 1e6),
		stamps = count(d.stamps, 1e5),
	}
	local w = if type(src.Week) == "table" then src.Week else {}
	out.Week = {
		key = str(w.key, 10),
		Wins = count(w.Wins, 1e6),
		Elims = count(w.Elims, 1e7),
		Top5 = count(w.Top5, 1e6),
		Survive = count(w.Survive, 1e6),
	}
	local tr = if type(src.Train) == "table" then src.Train else {}
	out.Train = { day = str(tr.day, 10), n = count(tr.n, 1000) }
	out.Owed = {}
	if type(src.Owed) == "table" then
		for _, o in ipairs(src.Owed) do
			if type(o) == "table" and type(o.k) == "string" and #o.k <= 12 and #out.Owed < 64 then
				table.insert(out.Owed, { k = o.k, id = if type(o.id) == "string" and #o.id <= 40 then o.id else nil,
					n = count(o.n, 1e6) })
			end
		end
	end
	out.Honours = {}
	if type(src.Honours) == "table" then
		local n = 0
		for id, v in pairs(src.Honours) do
			if type(id) == "string" and #id <= 40 and v == true and n < 128 then
				out.Honours[id] = true
				n += 1
			end
		end
	end
	return out
end

return Progression
