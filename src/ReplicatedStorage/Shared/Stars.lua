--[[
	Stars - 1 to 5 stars on every copy of a stack-1 weapon (docs/design/Weapons_v2.md section 2). Shared: the server
	applies them to the stats, clients show them. Better construction, never magic: about +25% from 1 to 5 stars.

	Numbers: Config.Stars when it exists (the lead's Config), else the defaults below (the page's section 9.1).
	Each star above the first adds:
	  melee (and its throw)  damage +4%, cooldown -2%, reach +0.15 studs
	  bows                   damageMin / damageMax +4%, drawTime -3%, speedMax +2%, on-crosshair range +5 studs
	Hard limits whatever the stars: no single hit over HitCap (95); a bow headshot never over its def.headshotCap (90).

	API
	  Stars.MAX                                   5
	  Stars.clamp(n) -> 1..5                      anything odd becomes 1
	  Stars.of(itemId, n?) -> number?             the stars an item copy carries: nil for items without stars
	  Stars.roll(source, rng?) -> 1..5            source "Kit" | "Tier1" | "Tier2" | "Tier3" | "Offering" (or a tier number)
	  Stars.def(itemId, n) -> def                 a read-only copy of the item's def with its stats scaled for n stars
	                                              (cached; def.stars = n). Unstarred items return the plain def.
	  Stars.capHit(damage) -> number              min(damage, HitCap)
	  Stars.capHead(def, damage) -> number        a bow headshot capped at def.headshotCap (and HitCap)
	  Stars.text(n) -> "★★★"                       Stars.label(itemId, n) -> "Machete ★★★" (just the name without stars)
	  Stars.rarity(n) -> "Common".."Legendary"    the loot glint's colour for a weapon on the ground
	  Stars.finish(n) -> "Worn" | "Sound" | "Fine" | "Superior" | "Masterwork"
	  Stars.applyFinish(model, n)                 the matte finish change on a built item model (parts with attribute
	                                              Role: Steel, Wood, Leather, Rope, Brass, Cord). Same silhouette at every
	                                              star; no glow. Safe to call on any model, any number of times.
]]
local Config = require(script.Parent:WaitForChild("Config"))
local ItemDefs = require(script.Parent:WaitForChild("ItemDefs"))

local Stars = {}

local DEFAULTS = {
	Max = 5,
	DamagePerStar = 0.04,
	CooldownPerStar = 0.02,
	ReachPerStar = 0.15,
	BowDrawPerStar = 0.03,
	BowSpeedPerStar = 0.02,
	BowOnTargetPerStar = 5,
	HitCap = 95,
	Odds = { -- percent for 1..5 stars
		Kit = { 100, 0, 0, 0, 0 },
		Tier1 = { 70, 25, 5, 0, 0 },
		Tier2 = { 45, 35, 17, 3, 0 },
		Tier3 = { 20, 35, 30, 13, 2 },
		Offering = { 0, 0, 50, 40, 10 },
	},
}

local cfg = {}
do
	local given = if type(Config.Stars) == "table" then Config.Stars else {}
	for key, value in pairs(DEFAULTS) do
		cfg[key] = if given[key] ~= nil then given[key] else value
	end
	if type(given.Odds) == "table" then
		cfg.Odds = table.clone(DEFAULTS.Odds)
		for key, value in pairs(given.Odds) do
			cfg.Odds[key] = value
		end
	end
end
Stars.Settings = cfg
Stars.MAX = math.max(1, math.floor(tonumber(cfg.Max) or 5))

local GLYPH = "\u{2605}" -- ★
local FINISH = { "Worn", "Sound", "Fine", "Superior", "Masterwork" }

function Stars.clamp(n: any): number
	local v = tonumber(n)
	if not v or v ~= v then
		return 1
	end
	return math.clamp(math.floor(v), 1, Stars.MAX)
end

function Stars.of(itemId: string?, n: any): number?
	if not ItemDefs.isStarred(itemId) then
		return nil
	end
	return Stars.clamp(n)
end

local SOURCE_BY_TIER = { "Tier1", "Tier2", "Tier3" }

function Stars.roll(source: any, rng: Random?): number
	local key = if type(source) == "number" then SOURCE_BY_TIER[source] else source
	local odds = cfg.Odds[key or ""] or cfg.Odds.Tier1
	local total = 0
	for i = 1, Stars.MAX do
		total += math.max(0, tonumber(odds[i]) or 0)
	end
	if total <= 0 then
		return 1
	end
	local r = (if rng then rng:NextNumber() else math.random()) * total
	for i = 1, Stars.MAX do
		r -= math.max(0, tonumber(odds[i]) or 0)
		if r < 0 then
			return i
		end
	end
	return Stars.MAX
end

function Stars.capHit(damage: number): number
	return math.min(damage, tonumber(cfg.HitCap) or 95)
end

function Stars.capHead(def: any, damage: number): number
	local cap = def and tonumber(def.headshotCap)
	if cap then
		damage = math.min(damage, cap)
	end
	return Stars.capHit(damage)
end

local cache: { [string]: any } = {}

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

function Stars.def(itemId: string?, n: any): any
	local base = ItemDefs.get(itemId)
	if not base or base.starred ~= true then
		return base
	end
	local s = Stars.clamp(n)
	local key = base.id .. "#" .. s
	local hit = cache[key]
	if hit then
		return hit
	end
	local d = table.clone(base)
	local k = s - 1
	d.stars = s
	local dmg = 1 + (tonumber(cfg.DamagePerStar) or 0.04) * k
	if base.kind == "Melee" then
		d.damage = Stars.capHit(round2(base.damage * dmg))
		d.cooldown = round2(base.cooldown * (1 - (tonumber(cfg.CooldownPerStar) or 0.02) * k))
		d.range = round2(base.range + (tonumber(cfg.ReachPerStar) or 0.15) * k)
		if base.throwDamage then
			d.throwDamage = Stars.capHit(round2(base.throwDamage * dmg))
		end
		if base.unseenDamage then
			d.unseenDamage = Stars.capHit(round2(base.unseenDamage * dmg))
		end
	elseif base.kind == "Bow" then
		d.damageMin = round2(base.damageMin * dmg)
		d.damageMax = Stars.capHit(round2(base.damageMax * dmg))
		d.drawTime = round2(base.drawTime * (1 - (tonumber(cfg.BowDrawPerStar) or 0.03) * k))
		d.speedMax = round2(base.speedMax * (1 + (tonumber(cfg.BowSpeedPerStar) or 0.02) * k))
		if base.onTargetRange then
			d.onTargetRange = base.onTargetRange + (tonumber(cfg.BowOnTargetPerStar) or 5) * k
		end
	end
	table.freeze(d)
	cache[key] = d
	return d
end

function Stars.text(n: any): string
	return string.rep(GLYPH, Stars.clamp(n))
end

function Stars.label(itemId: string?, n: any): string
	local def = ItemDefs.get(itemId)
	if not def then
		return tostring(itemId or "")
	end
	if def.starred ~= true or n == nil then
		return def.name
	end
	return def.name .. "  " .. Stars.text(n)
end

function Stars.rarity(n: any): string
	return ItemDefs.RarityOrder[Stars.clamp(n)] or "Common"
end

function Stars.finish(n: any): string
	return FINISH[Stars.clamp(n)]
end

-- The finish per star and role: a colour the part's own colour is pulled toward, and how far. All matte (no
-- Reflectance, no light). 2 stars is the model as authored ("Sound").
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local FINISH_COLORS = {
	[1] = { Steel = { rgb(150, 146, 138), 0.45 }, Wood = { rgb(150, 132, 108), 0.4 }, Leather = { rgb(118, 100, 84), 0.4 },
		Rope = { rgb(170, 158, 136), 0.3 }, Brass = { rgb(130, 116, 90), 0.5 }, Cord = { rgb(120, 112, 100), 0.3 } },
	[3] = { Steel = { rgb(70, 78, 92), 0.35 }, Leather = { rgb(70, 46, 32), 0.35 }, Wood = { rgb(96, 66, 44), 0.2 } },
	[4] = { Steel = { rgb(72, 78, 90), 0.4 }, Wood = { rgb(72, 46, 30), 0.45 }, Leather = { rgb(58, 38, 28), 0.4 },
		Brass = { rgb(168, 132, 70), 0.6 }, Rope = { rgb(120, 92, 60), 0.3 } },
	[5] = { Steel = { rgb(60, 64, 74), 0.45 }, Wood = { rgb(58, 36, 24), 0.55 }, Leather = { rgb(46, 30, 22), 0.45 },
		Brass = { rgb(176, 138, 72), 0.7 }, Rope = { rgb(100, 76, 50), 0.35 }, Cord = { rgb(40, 36, 34), 0.4 } },
}
-- parts with no Role: guessed from their material
local ROLE_BY_MATERIAL = {
	[Enum.Material.Metal] = "Steel", [Enum.Material.DiamondPlate] = "Steel", [Enum.Material.CorrodedMetal] = "Steel",
	[Enum.Material.Wood] = "Wood", [Enum.Material.WoodPlanks] = "Wood", [Enum.Material.Leather] = "Leather",
	[Enum.Material.Fabric] = "Rope",
}

function Stars.applyFinish(model: Instance?, n: any)
	if not model then
		return
	end
	local s = Stars.clamp(n)
	model:SetAttribute("Stars", s)
	model:SetAttribute("Finish", FINISH[s])
	local table_ = FINISH_COLORS[s]
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local original = d:GetAttribute("BaseColor")
			if typeof(original) ~= "Color3" then
				original = d.Color
				d:SetAttribute("BaseColor", original)
			end
			local role = d:GetAttribute("Role")
			if type(role) ~= "string" then
				role = ROLE_BY_MATERIAL[d.Material]
			end
			local pull = table_ and role and table_[role]
			d.Color = if pull then (original :: Color3):Lerp(pull[1], pull[2]) else original
			d.Reflectance = 0
		end
	end
end

return Stars
