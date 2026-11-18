--[[
	CombatStats - what a weapon does at its star count, and where a bow or a throw is aimed. Shared: the server's
	CombatService and ProjectileService and the client's CombatController read the same numbers from here, so the
	attacker's screen and the server always agree. (Weapons_v2.md sections 2 and 6.)

	Stars come from Shared.Stars when that module exists (it owns the star numbers: Config.Stars): Stars.def(itemId, n),
	the item's def scaled for its stars, for items it marks starred. This file is the thin adapter the design page asks
	for: when Stars is missing, the item is not starred there, or a call fails, the same rule is worked out here from
	Config.Stars (or the page's starting values when Config has no Stars table yet). Each weapon's one special rule
	(CombatStats.Rules) and the bow's on-target range, falloff and head cap are added here.

	CombatStats.clampStars(value) -> 1..5 (anything else: 1)
	CombatStats.melee(def, stars) -> { damage, cooldown, range, windup, staminaCost, throwDamage?, throwSpeed?,
	    throwGravity?, throwOnTarget?, unseenDamage?, sweepShare?, sweepAngle?, insideRange?, insideShare?,
	    armourPierce?, stars }
	CombatStats.bow(def, stars) -> { damageMin, damageMax, drawTime, speedMin, speedMax, gravity, headshotMultiplier,
	    headCap, onTarget, falloffBeyond, falloffMin, stars }
	CombatStats.throwable(def) -> { damage, speed, gravity, cooldown, onTarget? }   (throwing knives have no stars)
	CombatStats.hitCap() -> number   no single weapon hit does more (95)
	CombatStats.falloff(distance, onTarget, beyond, min) -> multiplier   1 within onTarget, down to `min` at
	    onTarget + beyond, `min` past that
	CombatStats.aimDirection(origin, look, crosshair, speed, gravity, onTarget?, maxLiftDegrees?) -> (direction, zero)
	    The release direction. When the point under the crosshair is within onTarget of the origin the arc passes exactly
	    through it. Further (or nothing under the crosshair) the shot is zeroed at onTarget along the look and follows
	    its real arc from there, dropping below the crosshair: the same drop every time, so it can be learned.
	    onTarget nil = the old rule (on the crosshair at any range the lift allows). Returns the point it was zeroed on.
	CombatStats.solve(origin, target, speed, gravity, look, maxLiftDegrees?) -> direction?   the low arc through target
	CombatStats.dropAt(distance, onTarget, speed, gravity) -> studs below the crosshair line at `distance` (flat shot)
]]
local Shared = script.Parent
local Config = require(Shared:WaitForChild("Config"))

local CombatStats = {}

local STARS_DEFAULT = {
	Max = 5,
	DamagePerStar = 0.04,
	CooldownPerStar = 0.02,
	ReachPerStar = 0.15,
	BowDrawPerStar = 0.03,
	BowSpeedPerStar = 0.02,
	BowOnTargetPerStar = 5,
	HitCap = 95,
}
local BOW_DEFAULT = {
	OnTargetRange = 60,
	ShortBowOnTargetRange = 40,
	FalloffBeyond = 90,
	FalloffMin = 0.75,
	HeadshotCap = 90,
	HoldSteadyTime = 2,
	HoldSwayMax = 1.2,
	HoldStaminaDrain = 0.04,
}

-- Each weapon's one special rule (Weapons_v2 1.2). A field on the item's own ItemDefs entry wins over these.
local RULES: { [string]: { [string]: any } } = {
	knife = { unseenDamage = 40 }, -- first hit on someone facing away who was not hurt in the last 5 s
	machete = { sweepShare = 0.6, sweepAngle = 55 }, -- a 2nd contender in the arc takes 60%
	spear = { insideRange = 4, insideShare = 0.6 }, -- weak once they get inside the shaft
	twin_axe = { armourPierce = 0.5 }, -- armour stops half as much
	ring_blade = { throwOnTarget = 45 }, -- the flat throw lands on the crosshair to 45 studs
}
CombatStats.Rules = RULES
CombatStats.UnseenWindow = 5 -- seconds without being hurt for the knife's unseen hit

local function starsConfig(): { [string]: any }
	local cfg = (Config :: any).Stars
	return if type(cfg) == "table" then cfg else STARS_DEFAULT
end

local function bowConfig(): { [string]: any }
	local cfg = (Config :: any).Bow
	return if type(cfg) == "table" then cfg else BOW_DEFAULT
end

local function num(t: { [string]: any }, key: string, fallback: number): number
	local v = t[key]
	return if type(v) == "number" and v == v then v else fallback
end

function CombatStats.config(key: string): any
	local bow = bowConfig()
	local v = bow[key]
	if v == nil then
		v = BOW_DEFAULT[key]
	end
	return v
end

local starsModule: any = nil
local function stars(): any
	if starsModule == nil then
		starsModule = false
		local module = Shared:FindFirstChild("Stars")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				starsModule = result
			end
		end
	end
	return starsModule or nil
end

function CombatStats.clampStars(value: any): number
	local cfg = starsConfig()
	local max = math.floor(num(cfg, "Max", 5))
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(math.floor(value + 0.5), 1, max)
end

function CombatStats.hitCap(): number
	local s = stars()
	if s and type(s.hitCap) == "function" then
		local ok, v = pcall(s.hitCap)
		if ok and type(v) == "number" and v > 0 then
			return v
		end
	end
	return num(starsConfig(), "HitCap", 95)
end

-- (from Shared.Stars when it has one: Stars.multipliers(stars, kind) -> { damage, cooldown, reach, draw, speed, onTarget })
local function steps(starCount: number, kind: string): { [string]: number }
	local s = stars()
	if s and type(s.multipliers) == "function" then
		local ok, m = pcall(s.multipliers, starCount, kind)
		if ok and type(m) == "table" and type(m.damage) == "number" then
			return m
		end
	end
	local cfg = starsConfig()
	local n = starCount - 1
	return {
		damage = 1 + num(cfg, "DamagePerStar", 0.04) * n,
		cooldown = 1 - num(cfg, "CooldownPerStar", 0.02) * n,
		reach = num(cfg, "ReachPerStar", 0.15) * n,
		draw = 1 - num(cfg, "BowDrawPerStar", 0.03) * n,
		speed = 1 + num(cfg, "BowSpeedPerStar", 0.02) * n,
		onTarget = num(cfg, "BowOnTargetPerStar", 5) * n,
	}
end

-- Shared.Stars.def(itemId, n): the item's def with its stats scaled for n stars (the stars module's own numbers and
-- rounding). nil when Stars is missing, the item is not starred there, or the call fails; the rule above is used then.
local function starsDef(def: any, n: number): any
	local s = stars()
	if not (s and type(s.def) == "function" and def.starred == true and type(def.id) == "string") then
		return nil
	end
	local ok, d = pcall(s.def, def.id, n)
	if ok and type(d) == "table" and d.id == def.id then
		return d
	end
	return nil
end

-- ItemDefs' own names for the same fields (stars-kits, 18 Nov)
local ALIASES: { [string]: string } = {
	armourPierce = "armorPierce",
	insideRange = "closeRange",
	insideShare = "closeShare",
	throwOnTarget = "throwOnTargetRange",
}

local function rule(def: any, key: string): any
	local v = def[key]
	if v == nil and ALIASES[key] then
		v = def[ALIASES[key]]
	end
	if v ~= nil then
		return v
	end
	local r = RULES[def.id]
	return r and r[key]
end

function CombatStats.melee(def: any, starCount: any): { [string]: any }
	local n = if def.starred == false or def.id == "fists" then 1 else CombatStats.clampStars(starCount)
	local m = steps(n, "Melee")
	local unseen = rule(def, "unseenDamage")
	local sd = starsDef(def, n) -- (Shared.Stars' own scaled numbers, when it has this item)
	local cap = CombatStats.hitCap()
	return {
		id = def.id,
		stars = n,
		damage = if sd and sd.damage then sd.damage else math.min((def.damage or 0) * m.damage, cap),
		cooldown = if sd and sd.cooldown then sd.cooldown else (def.cooldown or 0.5) * m.cooldown,
		range = if sd and sd.range then sd.range else (def.range or 5) + m.reach,
		windup = def.windup or 0.1,
		staminaCost = def.staminaCost,
		throwable = def.throwable,
		throwDamage = if sd and sd.throwDamage then sd.throwDamage elseif def.throwDamage then math.min(def.throwDamage * m.damage, cap) else nil,
		throwSpeed = def.throwSpeed,
		throwGravity = def.throwGravity,
		throwHeadMultiplier = def.throwHeadMultiplier,
		throwOnTarget = rule(def, "throwOnTarget"),
		unseenDamage = if sd and sd.unseenDamage then sd.unseenDamage
			elseif type(unseen) == "number" then math.min(unseen * m.damage, cap)
			else nil,
		sweepShare = rule(def, "sweepShare"),
		sweepAngle = rule(def, "sweepAngle"),
		insideRange = rule(def, "insideRange"),
		insideShare = rule(def, "insideShare"),
		armourPierce = rule(def, "armourPierce"),
	}
end

function CombatStats.bow(def: any, starCount: any): { [string]: any }
	local n = CombatStats.clampStars(starCount)
	local m = steps(n, "Bow")
	local bow = bowConfig()
	local base = def.onTargetRange
		or (if def.id == "short_bow" then num(bow, "ShortBowOnTargetRange", 40) else num(bow, "OnTargetRange", 60))
	local sd = starsDef(def, n) -- (Shared.Stars' own scaled numbers; its onTargetRange is already scaled)
	local onTarget = if sd and type(sd.onTargetRange) == "number" and def.onTargetRange then sd.onTargetRange else base + m.onTarget
	return {
		id = def.id,
		stars = n,
		damageMin = if sd and sd.damageMin then sd.damageMin else (def.damageMin or 10) * m.damage,
		damageMax = if sd and sd.damageMax then sd.damageMax else (def.damageMax or 40) * m.damage,
		drawTime = math.max(if sd and sd.drawTime then sd.drawTime else (def.drawTime or 1) * m.draw, 0.05),
		speedMin = def.speedMin or 90,
		speedMax = if sd and sd.speedMax then sd.speedMax else (def.speedMax or 240) * m.speed,
		gravity = def.gravity or 50,
		headshotMultiplier = def.headshotMultiplier or 1.8,
		headCap = math.min(tonumber(def.headshotCap) or num(bow, "HeadshotCap", 90), CombatStats.hitCap()),
		onTarget = onTarget,
		falloffBeyond = num(bow, "FalloffBeyond", 90),
		falloffMin = num(bow, "FalloffMin", 0.75),
	}
end

function CombatStats.throwable(def: any): { [string]: any }
	return {
		id = def.id,
		stars = 1,
		damage = def.damage or 0,
		speed = def.speed or 150,
		gravity = def.gravity or 40,
		cooldown = def.cooldown or 0.5,
		onTarget = rule(def, "throwOnTarget"),
		-- (throwing knives: ItemDefs gives the head damage itself, 35 for 22)
		headshotMultiplier = if type(def.headDamage) == "number" and (def.damage or 0) > 0 then def.headDamage / def.damage else nil,
	}
end

function CombatStats.falloff(distance: number, onTarget: number?, beyond: number?, min: number?): number
	if not onTarget or distance <= onTarget then
		return 1
	end
	local span = math.max(beyond or 90, 1)
	local floor = math.clamp(min or 0.75, 0, 1)
	return 1 - (1 - floor) * math.clamp((distance - onTarget) / span, 0, 1)
end

-- The low arc from origin through target at this speed and gravity; nil when it cannot reach it or would need more than
-- maxLift degrees above the look.
function CombatStats.solve(origin: Vector3, target: Vector3, speed: number, gravity: number, look: Vector3, maxLift: number?): Vector3?
	local delta = target - origin
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local x = flat.Magnitude
	if x < 1 or gravity <= 0 or speed <= 0 then
		return nil
	end
	local v2 = speed * speed
	local disc = v2 * v2 - gravity * (gravity * x * x + 2 * delta.Y * v2)
	if disc < 0 then
		return nil
	end
	local angle = math.atan((v2 - math.sqrt(disc)) / (gravity * x))
	local dir = flat.Unit * math.cos(angle) + Vector3.yAxis * math.sin(angle)
	if math.deg(math.acos(math.clamp(dir:Dot(look), -1, 1))) > (maxLift or 25) then
		return nil
	end
	return dir
end

function CombatStats.aimDirection(origin: Vector3, look: Vector3, crosshair: Vector3?, speed: number, gravity: number, onTarget: number?, maxLift: number?): (Vector3, Vector3?)
	local zero: Vector3? = crosshair
	if onTarget then
		if crosshair == nil or (crosshair - origin).Magnitude > onTarget then
			zero = origin + look * onTarget -- beyond its range the bow is zeroed here and the arrow drops past it
		end
	end
	if zero == nil then
		return look, nil
	end
	return CombatStats.solve(origin, zero, speed, gravity, look, maxLift) or look, zero
end

function CombatStats.dropAt(distance: number, onTarget: number, speed: number, gravity: number): number
	if distance <= onTarget then
		return 0
	end
	return gravity * distance * (distance - onTarget) / (2 * speed * speed)
end

return CombatStats
