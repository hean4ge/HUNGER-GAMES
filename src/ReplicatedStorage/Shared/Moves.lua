--[[
	Moves - the melee move set of Combat v3 (docs/design/Combat_v3.md sections 1 and 2), read by both sides: the
	server (CombatService, SkillService) checks and times every move with these numbers, the client (CombatController,
	SkillController, ViewmodelController, CharacterVisuals) plays them with the same numbers. Pure data and pure
	functions; no state.

	Every number is a starting value for playtests. Config.Combat.Moves, Config.Combat.Reactions and Config.Skills
	(when they exist) override the defaults below key by key (Combat_v3 9.1), so a tune never needs this file.

	  Moves.family(itemId) -> "Fists" | "ShortBlade" | "Sword" | "Axe" | "Spear" | "Throwing" | "Bow"
	  Moves.weight(itemId) -> "Light" | "Medium" | "Heavy"
	  Moves.chainLength(itemId) -> number
	  Moves.step(stats, itemId, index) -> move     a light chain step at the weapon's stars (stats = CombatStats.melee)
	  Moves.heavy(stats, itemId, held, fast?) -> move    held = seconds Attack was held; fast = Concentration
	  Moves.counter(stats, itemId) -> move       Moves.kick() -> move
	  Moves.guardShare(itemId) -> 0..1           Moves.knockSpeed(key) -> studs/s
	  Moves.tier(name) -> { name, time, hitStop, jolt, rank }   (Flinch, Stagger, Heavy, Knockdown)
	  Moves.parse(moveId) -> (kind, index)       "L1".."L4", "H", "C", "K", "S1".."S5" (chained strikes), "HK"
	  Moves.cfg / Moves.reactions / Moves.skills  the merged numbers
	A move: { id, kind = "Light" | "Heavy" | "Counter" | "Kick" | "Skill", damage, windup, total, reach (studs added to
	  the weapon's range), tier, style, variant (the first-person set; CharacterVisuals reads its shape), stab (one
	  thin ray instead of three across the arc), noStars, sweep (the machete's second contender), insideFull (the
	  spear's butt swing: full damage inside the shaft), stamina, knock (studs/s) }.
	Stars (Combat_v3 1.6): damage and the recovery scale with the weapon's stars (stats carry them); the windup never
	changes, so a 5-star is not harder to read. No single hit passes CombatStats.hitCap (95).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))

local Moves = {}

local function merge(defaults: { [string]: any }, over: any): { [string]: any }
	if type(over) ~= "table" then
		return defaults
	end
	for key, value in pairs(over) do
		if type(value) == "table" and type(defaults[key]) == "table" and #value == 0 then
			merge(defaults[key], value)
		else
			defaults[key] = value
		end
	end
	return defaults
end

local combatCfg = (Config.Combat or {}) :: any

-- Combat_v3 9.1 Config.Combat.Moves
Moves.cfg = merge({
	ChainWindow = combatCfg.SwingChainWindow or 0.45,
	ActiveTime = 0.06,
	HoldToHeavy = 0.25, -- seconds Attack must be held before a release is a heavy
	Heavy = {
		MinHold = 0.25, FullHold = 0.75, MinMult = 1.3, FullMult = 1.6, MaxHoldAfterFull = 1.5, HoldDrain = 0.05,
		StaminaMult = 2.2, ReachAdd = 0.5, LungeReachAdd = 1.5, WalkMult = 0.7,
		ReleaseWindup = { Light = 0.12, Medium = 0.16, Heavy = 0.22 },
		Recovery = { Light = 0.45, Medium = 0.55, Heavy = 0.70 },
		Lunge = { sword = true, spear = true, wrapped_sabre = true }, -- + LungeReachAdd instead of ReachAdd
		FullMultOf = { paired_blades = 2.4 }, -- both blades: 19 x 2.4 = 45.6 (Combat_v3 1.5)
	},
	Guard = {
		RaiseTime = 0.10, LowerTime = 0.12, Arc = 120, WalkMult = 0.6, StaminaPerDamage = 0.004, HeavyDrainMult = 1.5,
		BreakStagger = 0.8,
		Share = { fists = 0.40, knife = 0.55, leaf_dagger = 0.50, ring_blade = 0.65, sword = 0.75, machete = 0.65,
			paired_blades = 0.60, wrapped_sabre = 0.70, hatchet = 0.65, twin_axe = 0.70, climb_pick = 0.55, spear = 0.70,
			throwing_knife = 0.40, mace = 0.65 },
	},
	Parry = { Window = 0.18, ConcentrationWindow = 0.26, WhiffLock = 0.6, AttackerStagger = 0.5, HeavyAttackerStagger = 0.8 },
	Counter = { Window = 0.45, Windup = 0.06, Recovery = 0.35, Mult = 1.5, Stamina = 0.03, HitStop = 0.10 },
	Kick = { Windup = 0.16, Recovery = 0.35, Reach = 4.5, Damage = 6, Stamina = 0.07, Cooldown = 1.2, GuardBreakStagger = 0.45,
		Stagger = 0.4 },
	Dodge = { Startup = 0.15, Travel = 0.25, Recovery = 0.15, Distance = 8, BackDistance = 6, Stamina = 0.16,
		Cooldown = 0.7, RepeatWindow = 2, RepeatCostMult = 2 },
	ExhaustedAttackSpeed = 0.5,
	SlashSpread = 15, -- degrees: a slash traces three rays across its arc (-15, 0, +15), the owner's "3 rays a swing"
	StabRadius = 0.7, -- a stab traces one ray with this share of the ball's radius
}, combatCfg.Moves)

-- Combat_v3 9.1 Config.Combat.Reactions
Moves.reactions = merge({
	Flinch = { Time = 0, HitStop = 0.04, Jolt = 2 },
	Stagger = { Time = 0.4, HitStop = 0.05, Jolt = 6, WalkMult = 0.5 },
	Heavy = { Time = 0.7, HitStop = 0.08, Jolt = 9, ShakeAttacker = { 0.25, 0.2 }, ShakeVictim = { 0.4, 0.3 } },
	Knockdown = { Time = 1.6, Down = 1.0, Getup = 0.6, RollOutAfter = 0.5, HitStop = 0.08, Jolt = 9 },
	Poise = { AfterStagger = 0.8, AfterKnockdown = 1.5 },
	Knockback = { Decay = 108, Cap = 36, HeavyMult = 1.5, ChainStep = 0.3, ChainLast = 1.1, Region = { Head = 1.4, Torso = 1.0, Limbs = 0.7 },
		Speed = { fists = 12, knife = 18, leaf_dagger = 16, ring_blade = 20, paired_blades = 16, machete = 34, sword = 28,
			wrapped_sabre = 28, hatchet = 30, climb_pick = 24, spear = 26, twin_axe = 36, mace = 32, throwing_knife = 12,
			kick = 30, counter = 36, arrow = 22, thrown = 26 } },
	HitStopViewRange = 30,
	BlendIn = 0.08, BlendOut = 0.25,
}, combatCfg.Reactions)

-- Combat_v3 9.1 Config.Skills
Moves.skills = merge({
	LockedFirst = 45, -- seconds into a real round (practice rounds: from the start)
	Specialty = true, -- false: R does the held weapon's family skill for everyone (Combat_v3 10.2)
	DefaultGeneral = "concentration", -- until the Loadout has a general skill for a player
	Weapon = {
		Fists = { id = "head_kick", Windup = 0.22, Damage = 14, Reach = 4.5, Stamina = 0.12, Cooldown = 10, Total = 0.7 },
		ShortBlade = { id = "chained_strikes", Mults = { 0.45, 0.5, 0.55, 0.65, 0.85 }, First = 0.06, Gap = 0.2, Step = 0.5,
			Stamina = 0.18, Cooldown = 16, Total = 1.2 },
		Sword = { id = "running_cut", Crouch = 0.2, Dash = 12, DashTime = 0.3, Lane = 3, Mult = 0.6, MaxTargets = 4,
			Knockback = 24, Stamina = 0.28, Cooldown = 18, Total = 0.9 },
		Axe = { id = "whirl", Windup = 0.35, Spin = 0.3, RadiusAdd = 1, Mult = 0.65, MaxTargets = 4, Knockback = 30,
			Stamina = 0.24, Cooldown = 15, Total = 1.15 },
		Spear = { id = "vault_kick", Plant = 0.3, Vault = 5, HitAt = 0.75, Reach = 3, Damage = 12, Knockback = 36, Lift = 8,
			Stamina = 0.24, Cooldown = 18, Total = 1.25 },
		Throwing = { id = "ricochet", Armed = 4, Range = 20, Cone = 120, Share = 0.7, Stamina = 0, Cooldown = 14, Total = 0.3 },
		Bow = { id = "piercing_shot", Armed = 6, SpeedMult = 1.15, SecondShare = 0.7, Stamina = 0, Cooldown = 20, Total = 0.3 },
	},
	General = {
		concentration = { Time = 6, ChargeMult = 1.3, StaminaMult = 0.7, Cooldown = 40, Total = 0.5 },
		second_wind = { Stamina = 0.5, Heal = 8, HealTime = 4, Cooldown = 60, Total = 0.4 },
		sprint_burst = { Time = 3, SpeedMult = 1.25, Cooldown = 35, Total = 0.2 },
		quiet_step = { Time = 8, HearRange = 6, CrouchMult = 1.4, Cooldown = 45, Total = 0.2 },
		steady_hands = { Time = 8, DrawMult = 0.85, ThrowOnTargetAdd = 10, Cooldown = 45, Total = 0.3 },
		brace = { Time = 4, KnockbackMult = 0.5, Cooldown = 40, Total = 0.4 },
	},
	KitSuggests = { archer = "Bow", forager = "ShortBlade", hunter = "Throwing", climber = "Axe" },
}, (Config :: any).Skills)

-- Names shown with a skill (the Loadout and the HUD read these; no text is shown in the round, only the ring).
Moves.SKILL_NAMES = {
	head_kick = "Head Kick", chained_strikes = "Chained Strikes", running_cut = "Running Cut", whirl = "Whirl",
	vault_kick = "Vault Kick", ricochet = "Ricochet", piercing_shot = "Piercing Shot",
	concentration = "Concentration", second_wind = "Second Wind", sprint_burst = "Sprint Burst", quiet_step = "Quiet Step",
	steady_hands = "Steady Hands", brace = "Brace",
}
Moves.GENERAL_ORDER = { "concentration", "second_wind", "sprint_burst", "quiet_step", "steady_hands", "brace" }
Moves.FAMILY_ORDER = { "Fists", "ShortBlade", "Sword", "Axe", "Spear", "Throwing", "Bow" }

Moves.FAMILY = {
	fists = "Fists",
	knife = "ShortBlade", leaf_dagger = "ShortBlade", ring_blade = "ShortBlade",
	sword = "Sword", machete = "Sword", paired_blades = "Sword", wrapped_sabre = "Sword",
	hatchet = "Axe", twin_axe = "Axe", climb_pick = "Axe", mace = "Axe",
	spear = "Spear",
	throwing_knife = "Throwing",
	bow = "Bow", short_bow = "Bow",
}
Moves.WEIGHT = {
	fists = "Light", knife = "Light", leaf_dagger = "Light", ring_blade = "Light", paired_blades = "Light",
	throwing_knife = "Light",
	sword = "Medium", machete = "Medium", wrapped_sabre = "Medium", hatchet = "Medium", climb_pick = "Medium",
	spear = "Medium",
	twin_axe = "Heavy", mace = "Heavy",
}

-- Light hits flinch, medium weapons stagger, the Twin-Bit Axe staggers hard (Combat_v3 1.8).
local LIGHT_TIER = {
	fists = "Flinch", knife = "Flinch", leaf_dagger = "Flinch", ring_blade = "Flinch", paired_blades = "Flinch",
	throwing_knife = "Flinch",
	sword = "Stagger", machete = "Stagger", wrapped_sabre = "Stagger", hatchet = "Stagger", climb_pick = "Stagger",
	spear = "Stagger",
	twin_axe = "Heavy", mace = "Heavy",
}

-- The light chains (Combat_v3 1.4), at 1 star. mult = the step's damage against the weapon's; windup / total in
-- seconds (nil: the weapon's own); style + variant = the first-person swing set (ViewmodelController.Poses: Slash 1
-- falling right-to-left, 2 rising backhand, 3 high flat cut, 4 overhead; Chop 1 overhead, 2 diagonal, 3 flat side;
-- Smash 1 overhead, 2 diagonal; Stab 1 straight, 2 high, 3 low; Punch 1 jab, 2 cross, 3 hook), from which the
-- third-person shape is taken too (CharacterVisuals).
type Step = { mult: number, windup: number?, total: number?, style: string, variant: number, stab: boolean?,
	sweep: boolean?, insideFull: boolean?, reach: number?, label: string? }
local CHAINS: { [string]: { Step } } = {
	fists = {
		{ mult = 1, windup = 0.06, total = 0.45, style = "Punch", variant = 1, stab = true, label = "jab" },
		{ mult = 1, windup = 0.06, total = 0.45, style = "Punch", variant = 2, stab = true, label = "cross" },
		{ mult = 1.25, windup = 0.08, total = 0.52, style = "Punch", variant = 3, label = "hook" },
	},
	knife = {
		{ mult = 1, windup = 0.10, total = 0.48, style = "Slash", variant = 1, label = "backhand slash" },
		{ mult = 1, windup = 0.10, total = 0.48, style = "Slash", variant = 2, label = "forehand slash" },
		{ mult = 1.2, windup = 0.12, total = 0.52, style = "Stab", variant = 1, stab = true, label = "stab" },
	},
	leaf_dagger = {
		{ mult = 1, windup = 0.08, total = 0.42, style = "Stab", variant = 1, stab = true, label = "straight stab" },
		{ mult = 1, windup = 0.08, total = 0.42, style = "Slash", variant = 2, label = "reverse slash" },
		{ mult = 1.2, windup = 0.10, total = 0.46, style = "Stab", variant = 2, stab = true, label = "hooking stab" },
	},
	ring_blade = {
		{ mult = 1, windup = 0.12, total = 0.55, style = "Slash", variant = 1, label = "hoop slash" },
		{ mult = 1, windup = 0.12, total = 0.55, style = "Slash", variant = 2, label = "hoop backhand" },
		{ mult = 1.15, windup = 0.14, total = 0.60, style = "Stab", variant = 1, stab = true, label = "hoop punch" },
	},
	sword = {
		{ mult = 1, windup = 0.16, total = 0.62, style = "Slash", variant = 1, label = "diagonal down" },
		{ mult = 1, windup = 0.16, total = 0.62, style = "Slash", variant = 2, label = "rising cut" },
		{ mult = 1, windup = 0.16, total = 0.62, style = "Slash", variant = 3, label = "flat cut" },
		{ mult = 1.25, windup = 0.20, total = 0.72, style = "Slash", variant = 4, label = "overhead" },
	},
	machete = {
		{ mult = 1, windup = 0.14, total = 0.55, style = "Slash", variant = 3, sweep = true, label = "forehand sweep" },
		{ mult = 1, windup = 0.14, total = 0.55, style = "Slash", variant = 2, sweep = true, label = "backhand sweep" },
		{ mult = 1.2, windup = 0.17, total = 0.62, style = "Chop", variant = 1, label = "overhead chop" },
	},
	paired_blades = {
		{ mult = 1, windup = 0.07, total = 0.38, style = "Slash", variant = 1, label = "right cut" },
		{ mult = 1, windup = 0.07, total = 0.38, style = "Slash", variant = 2, label = "left cut" },
		{ mult = 1, windup = 0.07, total = 0.38, style = "Slash", variant = 3, label = "right rising" },
		{ mult = 1.4, windup = 0.12, total = 0.50, style = "Chop", variant = 2, label = "both blades crossing" },
	},
	wrapped_sabre = {
		{ mult = 1, windup = 0.13, total = 0.55, style = "Slash", variant = 1, label = "diagonal down" },
		{ mult = 1, windup = 0.13, total = 0.55, style = "Slash", variant = 2, label = "rising cut" },
		{ mult = 1.2, windup = 0.16, total = 0.64, style = "Slash", variant = 4, label = "overhead" },
	},
	hatchet = {
		{ mult = 1, windup = 0.18, total = 0.80, style = "Chop", variant = 2, label = "diagonal chop" },
		{ mult = 1, windup = 0.18, total = 0.80, style = "Chop", variant = 3, label = "backhand chop" },
		{ mult = 1.2, windup = 0.22, total = 0.90, style = "Chop", variant = 1, label = "overhead" },
	},
	twin_axe = {
		{ mult = 1, windup = 0.30, total = 0.95, style = "Smash", variant = 2, label = "wide sweep" },
		{ mult = 1.1, windup = 0.26, total = 0.95, style = "Smash", variant = 1, label = "return sweep" },
	},
	mace = {
		{ mult = 1, style = "Smash", variant = 1 },
		{ mult = 1, style = "Smash", variant = 2 },
	},
	climb_pick = {
		{ mult = 1, windup = 0.14, total = 0.65, style = "Chop", variant = 1, label = "peck" },
		{ mult = 1, windup = 0.14, total = 0.65, style = "Chop", variant = 2, label = "peck" },
		{ mult = 1.15, windup = 0.16, total = 0.70, style = "Chop", variant = 3, label = "hook and pull" },
	},
	spear = {
		{ mult = 1, windup = 0.20, total = 0.70, style = "Stab", variant = 1, stab = true, label = "thrust" },
		{ mult = 1, windup = 0.20, total = 0.70, style = "Stab", variant = 2, stab = true, label = "thrust" },
		{ mult = 0.8, windup = 0.16, total = 0.70, style = "Stab", variant = 3, insideFull = true, reach = -3.5,
			label = "butt swing" },
	},
	throwing_knife = {
		{ mult = 10 / 22, windup = 0.08, total = 0.45, style = "Slash", variant = 1, label = "short slash" },
	},
}
Moves.CHAINS = CHAINS

-- The heavy per weapon: its first-person set (the heavies are the chain's biggest cut, wound further).
local HEAVY_SET: { [string]: { style: string, variant: number, stab: boolean? } } = {
	fists = { style = "Punch", variant = 2 }, -- haymaker
	knife = { style = "Stab", variant = 1, stab = true }, leaf_dagger = { style = "Stab", variant = 1, stab = true },
	ring_blade = { style = "Stab", variant = 1, stab = true },
	sword = { style = "Slash", variant = 1 }, wrapped_sabre = { style = "Slash", variant = 1 },
	machete = { style = "Chop", variant = 1 }, paired_blades = { style = "Chop", variant = 2 },
	hatchet = { style = "Chop", variant = 1 }, twin_axe = { style = "Smash", variant = 1 }, mace = { style = "Smash", variant = 1 },
	climb_pick = { style = "Chop", variant = 1 },
	spear = { style = "Stab", variant = 1, stab = true },
	throwing_knife = { style = "Slash", variant = 1 },
}

Moves.TIERS = {
	Flinch = { name = "Flinch", rank = 1 },
	Stagger = { name = "Stagger", rank = 2 },
	Heavy = { name = "Heavy", rank = 3 },
	Knockdown = { name = "Knockdown", rank = 4 },
}
Moves.TIER_BY_RANK = { "Flinch", "Stagger", "Heavy", "Knockdown" }

function Moves.tier(name: string?): { [string]: any }
	local key = if name and Moves.TIERS[name] then name else "Flinch"
	local r = Moves.reactions[key] or {}
	return { name = key, rank = Moves.TIERS[key].rank, time = r.Time or 0, hitStop = r.HitStop or 0.04, jolt = r.Jolt or 2 }
end

function Moves.family(itemId: string?): string
	return (itemId and Moves.FAMILY[itemId]) or "Fists"
end

function Moves.weight(itemId: string?): string
	return (itemId and Moves.WEIGHT[itemId]) or "Medium"
end

local function chainFor(itemId: string?): { Step }
	return (itemId and CHAINS[itemId]) or CHAINS.fists
end

function Moves.chainLength(itemId: string?): number
	return #chainFor(itemId)
end

function Moves.guardShare(itemId: string?): number
	local share = Moves.cfg.Guard.Share
	return (itemId and share[itemId]) or 0.5
end

function Moves.knockSpeed(key: string?): number
	local speeds = Moves.reactions.Knockback.Speed
	return (key and speeds[key]) or 18
end

local function hitCap(): number
	return tonumber(combatCfg.HitCap) or (Config.Weapons and tonumber((Config.Weapons :: any).HitCap)) or 95
end

-- The stars' share of the cooldown (1 at 1 star, 0.92 at 5): the recovery shortens, the windup stays.
local function starPace(stats: any, itemId: string?): number
	local def = ItemDefs.get(itemId)
	local base = def and def.cooldown
	if type(base) == "number" and base > 0 and type(stats) == "table" and type(stats.cooldown) == "number" then
		return math.clamp(stats.cooldown / base, 0.5, 1.2)
	end
	return 1
end

-- The weapon's damage at its stars (stats.damage) against its 1-star damage: what a skill's "x the weapon's damage"
-- and a step's multiplier are applied to.
local function starredDamage(stats: any): number
	return if type(stats) == "table" and type(stats.damage) == "number" then stats.damage else 8
end

function Moves.step(stats: any, itemId: string?, index: number?): { [string]: any }
	local chain = chainFor(itemId)
	local i = math.clamp(math.floor(tonumber(index) or 1), 1, #chain)
	local s = chain[i]
	local windup = s.windup or (if type(stats) == "table" then stats.windup else nil) or 0.1
	local total = (s.total or (if type(stats) == "table" then stats.cooldown else nil) or 0.5)
	if s.total then
		total *= starPace(stats, itemId)
	end
	local tier = LIGHT_TIER[itemId or "fists"] or "Flinch"
	return {
		id = "L" .. i,
		kind = "Light",
		index = i,
		last = i == #chain,
		damage = math.min(starredDamage(stats) * s.mult, hitCap()),
		windup = windup,
		total = math.max(total, windup + 0.12),
		reach = s.reach or 0,
		tier = tier,
		style = s.style,
		variant = s.variant,
		stab = s.stab == true,
		sweep = s.sweep == true,
		insideFull = s.insideFull == true,
		stamina = if type(stats) == "table" then stats.staminaCost or 0.05 else 0.05,
		-- per chain step: the early steps only nudge (28 studs/s pushed the body about 3.6 studs, out of the next
		-- step's reach, so a standing chain lost its third hit); the last step pushes in full
		knock = Moves.knockSpeed(itemId) * (if i == #chain then (Moves.reactions.Knockback.ChainLast or 1)
			else (Moves.reactions.Knockback.ChainStep or 0.3)),
		label = s.label,
	}
end

-- The heavy: held seconds of Attack before the release (MinHold .. FullHold scales MinMult .. FullMult; fast:
-- Concentration charges 30 % faster).
function Moves.heavyMult(itemId: string?, held: number, fast: boolean?): (number, number)
	local H = Moves.cfg.Heavy
	local rate = if fast then (Moves.skills.General.concentration.ChargeMult or 1.3) else 1
	local charge = math.clamp((held * rate - H.MinHold) / math.max(H.FullHold - H.MinHold, 1e-3), 0, 1)
	local full = (itemId and H.FullMultOf[itemId]) or H.FullMult
	local min = H.MinMult * full / H.FullMult
	return min + (full - min) * charge, charge
end

function Moves.heavy(stats: any, itemId: string?, held: number, fast: boolean?): { [string]: any }
	local H = Moves.cfg.Heavy
	local weight = Moves.weight(itemId)
	local mult, charge = Moves.heavyMult(itemId, held, fast)
	local windup = H.ReleaseWindup[weight] or 0.16
	local recovery = (H.Recovery[weight] or 0.55) * starPace(stats, itemId)
	local set = HEAVY_SET[itemId or "fists"] or HEAVY_SET.fists
	local light = LIGHT_TIER[itemId or "fists"] or "Flinch"
	return {
		id = "H",
		kind = "Heavy",
		damage = math.min(starredDamage(stats) * mult, hitCap()),
		charge = charge,
		windup = windup,
		total = windup + 0.08 + recovery,
		reach = if itemId and H.Lunge[itemId] then H.LungeReachAdd else H.ReachAdd,
		-- full charge: a heavy stagger; less: a stagger at least
		tier = if charge >= 0.999 then "Heavy" elseif light == "Heavy" then "Heavy" else "Stagger",
		style = set.style,
		variant = set.variant,
		stab = set.stab == true,
		stamina = (if type(stats) == "table" then stats.staminaCost or 0.05 else 0.05) * H.StaminaMult,
		knock = Moves.knockSpeed(itemId) * (Moves.reactions.Knockback.HeavyMult or 1.5),
		heavyHit = true,
	}
end

function Moves.counter(stats: any, itemId: string?): { [string]: any }
	local C = Moves.cfg.Counter
	local first = Moves.step(stats, itemId, 1)
	return {
		id = "C",
		kind = "Counter",
		damage = math.min(first.damage * C.Mult, hitCap()),
		windup = C.Windup,
		total = C.Windup + Moves.cfg.ActiveTime + C.Recovery,
		reach = 0,
		tier = "Heavy",
		style = first.style,
		variant = first.variant,
		stab = first.stab,
		stamina = C.Stamina,
		knock = Moves.knockSpeed("counter"),
		hitStop = C.HitStop,
	}
end

function Moves.kick(): { [string]: any }
	local K = Moves.cfg.Kick
	return {
		id = "K",
		kind = "Kick",
		damage = K.Damage,
		windup = K.Windup,
		total = K.Windup + 0.08 + K.Recovery,
		range = K.Reach, -- (its own reach, not the weapon's)
		reach = 0,
		tier = "Stagger",
		style = "Kick",
		variant = 1,
		stab = true,
		noStars = true,
		stamina = K.Stamina,
		knock = Moves.knockSpeed("kick"),
	}
end

-- A skill strike sent as a MeleeSwing (Head Kick, the chained strikes): { damage, tier, reach, windup }.
function Moves.skillStrike(stats: any, itemId: string?, moveId: string): { [string]: any }?
	local W = Moves.skills.Weapon
	if moveId == "HK" then
		local S = W.Fists
		return { id = "HK", kind = "Skill", damage = S.Damage, windup = S.Windup, total = S.Total, range = S.Reach, reach = 0,
			tier = "Heavy", style = "Kick", variant = 2, stab = true, noStars = true, stamina = 0, knock = Moves.knockSpeed("kick") }
	end
	local n = string.match(moveId, "^S(%d)$")
	if n then
		local S = W.ShortBlade
		local i = math.clamp(tonumber(n) or 1, 1, #S.Mults)
		local first = Moves.step(stats, itemId, if i % 2 == 1 then 1 else 2)
		return { id = moveId, kind = "Skill", index = i, damage = math.min(starredDamage(stats) * S.Mults[i], hitCap()),
			windup = if i == 1 then S.First else 0, total = S.Gap, reach = 0, tier = if i == #S.Mults then "Stagger" else "Flinch",
			style = first.style, variant = first.variant, stab = first.stab, stamina = 0, knock = Moves.knockSpeed(itemId) }
	end
	return nil
end

-- "L3" -> ("Light", 3); "H" -> ("Heavy", nil); "C" -> Counter; "K" -> Kick; "S2" / "HK" -> ("Skill", ...); else nil.
function Moves.parse(moveId: any): (string?, number?)
	if type(moveId) ~= "string" or #moveId > 4 then
		return nil, nil
	end
	local n = string.match(moveId, "^L(%d)$")
	if n then
		return "Light", tonumber(n)
	elseif moveId == "H" then
		return "Heavy", nil
	elseif moveId == "C" then
		return "Counter", nil
	elseif moveId == "K" then
		return "Kick", nil
	elseif moveId == "HK" then
		return "Skill", 0
	end
	local s = string.match(moveId, "^S(%d)$")
	if s then
		return "Skill", tonumber(s)
	end
	return nil, nil
end

-- The weapon skill of a family (Moves.skills.Weapon[family]) with its id, or nil.
function Moves.weaponSkill(family: string?): { [string]: any }?
	return if family then Moves.skills.Weapon[family] else nil
end

function Moves.generalSkill(id: string?): { [string]: any }?
	return if id then Moves.skills.General[id] else nil
end

-- The Blender clip a move plays (Combat_v3 7.2): "sword_light_2", "twinaxe_heavy", "kick", "spear_skill_vault_kick" ...
-- The clip player (ClipPlayer, Shared.FightClips) is asked for it by this name; nil when the move has none.
local CLIP_PREFIX = {
	fists = "fists", knife = "knife", leaf_dagger = "dagger", ring_blade = "ring", sword = "sword", wrapped_sabre = "sword",
	machete = "machete", paired_blades = "paired", hatchet = "hatchet", twin_axe = "twinaxe", climb_pick = "pick",
	spear = "spear", mace = "twinaxe", throwing_knife = "knife",
}
local FAMILY_CLIP = { Fists = "fists", ShortBlade = "shortblade", Sword = "sword", Axe = "axe", Spear = "spear" }
local HEAVY_CLIP = { paired_blades = "paired_heavy", twin_axe = "twinaxe_heavy" }
local COUNTER_CLIP = { paired_blades = "paired_counter" }
Moves.CLIP_PREFIX = CLIP_PREFIX
function Moves.clipName(itemId: string?, moveId: string?): string?
	local id = itemId or "fists"
	local kind, index = Moves.parse(moveId or "L1")
	local family = FAMILY_CLIP[Moves.family(id)]
	if kind == "Light" then
		return (CLIP_PREFIX[id] or "fists") .. "_light_" .. tostring(index or 1)
	elseif kind == "Heavy" then
		return HEAVY_CLIP[id] or (if family then family .. "_heavy" else nil)
	elseif kind == "Counter" then
		return COUNTER_CLIP[id] or (if family then family .. "_counter" else nil)
	elseif kind == "Kick" then
		return "kick"
	elseif moveId == "HK" then
		return "fists_skill_head_kick"
	elseif kind == "Skill" then
		return "shortblade_skill_chained"
	end
	return nil
end

-- Which way the move's three rays fan: "Yaw" (a side cut), "Pitch" (an overhead), nil (a stab: one ray).
function Moves.fan(move: { [string]: any }): string?
	if move.stab then
		return nil
	end
	local style, variant = move.style, move.variant
	if (style == "Slash" and variant == 4) or (style == "Chop" and variant == 1) or (style == "Smash" and variant == 1) then
		return "Pitch"
	end
	return "Yaw"
end

-- The directions a move traces along, centre first: three rays across the arc for slashes (-15, 0, +15 degrees about
-- the camera's up for a side cut, about its right for an overhead), the look alone for a stab.
function Moves.traceDirections(move: { [string]: any }, look: Vector3): { Vector3 }
	local fan = Moves.fan(move)
	if not fan then
		return { look }
	end
	local a = math.rad(Moves.cfg.SlashSpread or 15)
	local up = Vector3.yAxis
	local right = look:Cross(up)
	if right.Magnitude < 0.05 then
		return { look }
	end
	right = right.Unit
	local axis = if fan == "Yaw" then right:Cross(look).Unit else right
	local function turn(v: Vector3, angle: number): Vector3
		return CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(v)
	end
	return { look, turn(look, a), turn(look, -a) }
end

return Moves
