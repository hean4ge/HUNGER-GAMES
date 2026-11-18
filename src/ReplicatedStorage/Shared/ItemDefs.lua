--[[
	ItemDefs - every item in the game. The Inventory/Loot system owns this file; Combat reads the stats.
	kind: "Melee" | "Bow" | "Throwable" | "Ammo" | "Food" | "Drink" | "Heal" | "Armor" | "Utility"
	Shared fields: id (filled in below), name, kind, rarity, stack (max per slot), desc
	Melee: damage, cooldown, range, windup, staminaCost, [throwable, throwDamage, throwSpeed, throwGravity]
	Bow: ammo, damageMin, damageMax, drawTime, speedMin, speedMax, gravity, headshotMultiplier
	Throwable: damage, speed, gravity, cooldown
	Food / Drink / Heal: hunger, thirst, heal, useTime, [becomes]
	Armor: damageMultiplier, useTime        Utility: [fillsInto] [builds]
	Food that a campfire cooks: cooksInto (item id), [cookTime]. A negative hunger or thirst is a cost (raw meat).
	Presentation (filled with defaults below, override per item):
	  equipSound  Sounds key played locally on equip ("Equip_Blade" | "Equip_Bow" | "Equip_Generic")
	  useLabel    progress label while using a consumable ("Eating" / "Drinking" / "Bandaging" / "Putting on armor")
	  useSound    Sounds key for using it ("Eat" | "Drink" | "Bandage" | "ArmorOn")
	  lootBundle  { id, min, max }: extra items that always come with this one from crates and markers
]]
local Config = require(script.Parent:WaitForChild("Config"))

local ItemDefs = {}

ItemDefs.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

ItemDefs.Items = {
	-- Melee (Weapons_v2 section 1.2: 1-star numbers; Shared.Stars scales them per copy)
	fists = { name = "Fists", kind = "Melee", rarity = "Common", stack = 1, hidden = true,
		damage = 8, cooldown = 0.45, range = 4, windup = 0.06, staminaCost = 0.03 },
	knife = { name = "Hunting Knife", kind = "Melee", rarity = "Common", stack = 1, starred = true,
		damage = 20, cooldown = 0.48, range = 4.5, windup = 0.10, staminaCost = 0.04,
		unseenDamage = 40, -- first hit on someone facing away and not hurt in 5 s (CombatService)
		desc = "Quick, quiet, reliable.", equipSound = "Equip_Blade" },
	machete = { name = "Machete", kind = "Melee", rarity = "Uncommon", stack = 1, starred = true,
		damage = 26, cooldown = 0.55, range = 7, windup = 0.14, staminaCost = 0.06,
		sweepShare = 0.6, sweepAngle = 55, -- a 2nd contender in the arc takes 60% (CombatService)
		desc = "Wide cuts. Best when two are close.", equipSound = "Equip_Blade" },
	hatchet = { name = "Hatchet", kind = "Melee", rarity = "Uncommon", stack = 1, starred = true,
		damage = 34, cooldown = 0.80, range = 5, windup = 0.18, staminaCost = 0.08,
		throwable = true, throwDamage = 45, throwSpeed = 110, throwGravity = 45, throwHeadMultiplier = 1.6,
		desc = "A short axe and a tool. One heavy throw.", equipSound = "Equip_Blade" },
	spear = { name = "Spear", kind = "Melee", rarity = "Rare", stack = 1, starred = true,
		damage = 34, cooldown = 0.70, range = 9.5, windup = 0.20, staminaCost = 0.07,
		closeShare = 0.6, closeRange = 4, -- 60% inside 4 studs (CombatService)
		throwable = true, throwDamage = 60, throwSpeed = 110, throwGravity = 45,
		desc = "Long reach. Hold Aim and attack to throw.", equipSound = "Equip_Blade" },
	mace = { name = "Mace", kind = "Melee", rarity = "Rare", stack = 1, starred = true, retired = true,
		damage = 46, cooldown = 1.1, range = 7, windup = 0.25, staminaCost = 0.12,
		desc = "Slow and crushing." }, -- retired from loot (Weapons_v2): the id and model stay so nothing breaks
	sword = { name = "Longsword", kind = "Melee", rarity = "Epic", stack = 1, starred = true,
		damage = 36, cooldown = 0.62, range = 8, windup = 0.16, staminaCost = 0.08,
		desc = "The duellist's blade. The Horn's prize.", equipSound = "Equip_Blade" },
	twin_axe = { name = "Twin-Bit Axe", kind = "Melee", rarity = "Rare", stack = 1, starred = true,
		damage = 42, cooldown = 0.95, range = 7, windup = 0.30, staminaCost = 0.12,
		armorPierce = 0.5, -- armour stops half as much (CombatService)
		throwable = true, throwDamage = 65, throwSpeed = 95, throwGravity = 50, throwStaminaCost = 0.10, throwSpin = true,
		desc = "Slow, heavy, breaks armour. Throw it end over end.", equipSound = "Equip_Blade" },
	ring_blade = { name = "Ring Blade", kind = "Melee", rarity = "Rare", stack = 1, starred = true,
		damage = 24, cooldown = 0.55, range = 5.5, windup = 0.12, staminaCost = 0.05,
		throwable = true, throwDamage = 38, throwSpeed = 140, throwGravity = 12, throwHeadMultiplier = 1.6,
		throwOnTargetRange = 45, throwStaminaCost = 0.06,
		desc = "A steel hoop. Thrown, it flies flat and fast.", equipSound = "Equip_Blade" },
	climb_pick = { name = "Climbing Pick", kind = "Melee", rarity = "Uncommon", stack = 1, starred = true,
		damage = 26, cooldown = 0.65, range = 5, windup = 0.14, staminaCost = 0.06,
		climbSpeedMultiplier = 1.2, climbDrainMultiplier = 0.7, -- in hand while climbing (MovementController)
		desc = "Climb faster and longer with it in hand.", equipSound = "Equip_Blade" },
	-- Ranged
	bow = { name = "Recurve Bow", kind = "Bow", rarity = "Rare", stack = 1, starred = true, ammo = "arrow",
		damageMin = 14, damageMax = 50, drawTime = 0.9, speedMin = 90, speedMax = 240, gravity = 55,
		onTargetRange = 60, headshotCap = 90, neverOwned = true,
		headshotMultiplier = Config.Combat.BowHeadshotMultiplier or 2, desc = "Hold to draw, release to fire. Needs arrows.",
		lootBundle = { id = "arrow", min = 5, max = 5 } },
	short_bow = { name = "Short Bow", kind = "Bow", rarity = "Uncommon", stack = 1, starred = true, ammo = "arrow",
		damageMin = 10, damageMax = 36, drawTime = 0.6, speedMin = 80, speedMax = 190, gravity = 60,
		onTargetRange = 40, headshotCap = 65, headshotMultiplier = 1.8, staminaCost = 0.03,
		desc = "A light, quick bow. Weaker than the recurve. Needs arrows.",
		lootBundle = { id = "arrow", min = 4, max = 6 } },
	throwing_knife = { name = "Throwing Knife", kind = "Throwable", rarity = "Uncommon", stack = 6,
		damage = 22, headDamage = 35, speed = 120, gravity = 40, cooldown = 0.5, desc = "Throw it, then pick it back up.",
		equipSound = "Equip_Blade" },
	wire_snare = { name = "Wire Snare", kind = "Utility", rarity = "Uncommon", stack = 2,
		desc = "A wire loop for a trail. (Setting it comes in a later update.)" },
	arrow = { name = "Arrow", kind = "Ammo", rarity = "Common", stack = 24, desc = "Ammunition for the bow." },
	-- Healing
	herbs = { name = "Healing Herbs", kind = "Heal", rarity = "Common", stack = 6, heal = 10, useTime = 1.5,
		desc = "Crushed leaves that restore a little health.", useLabel = "Applying herbs" },
	bandage = { name = "Bandage", kind = "Heal", rarity = "Common", stack = 4, heal = 20, useTime = 2.5,
		desc = "Clean cloth that restores some health." },
	medkit = { name = "Med Kit", kind = "Heal", rarity = "Epic", stack = 1, heal = 65, useTime = 5,
		desc = "Everything needed to restore a lot of health.", useLabel = "Using the kit" },
	-- Food and drink
	berries = { name = "Wild Berries", kind = "Food", rarity = "Common", stack = 10, hunger = 12, useTime = 1.0,
		desc = "A handful of tart berries." },
	apple = { name = "Apple", kind = "Food", rarity = "Common", stack = 5, hunger = 18, thirst = 4, useTime = 1.2,
		desc = "Crisp and a little juicy." },
	dried_meat = { name = "Dried Meat", kind = "Food", rarity = "Uncommon", stack = 3, hunger = 35, useTime = 2.0,
		desc = "Salted strips. Keeps you going." },
	ration = { name = "Ration Pack", kind = "Food", rarity = "Rare", stack = 2, hunger = 55, thirst = 10, useTime = 2.5,
		desc = "A sealed tin and an energy bar." },
	water_bottle = { name = "Water Bottle", kind = "Drink", rarity = "Common", stack = 1, thirst = 45, useTime = 1.6,
		becomes = "empty_bottle", desc = "Clean water. Keep the bottle." },
	empty_bottle = { name = "Empty Bottle", kind = "Utility", rarity = "Common", stack = 1, fillsInto = "water_bottle",
		desc = "Look at water and press Drink to fill it." },
	-- Hunting and cooking (WildlifeService, CookingService; the numbers are weighed in Shared.WildlifeConfig).
	-- cooksInto / cookTime: what a lit campfire's spit turns it into, and after how many seconds.
	-- builds: holding it and looking at the ground offers "Build fire" (CookingController).
	squirrel = { name = "Squirrel", kind = "Food", rarity = "Common", stack = 3, hunger = 8, thirst = -8, useTime = 2.4,
		cooksInto = "cooked_squirrel", cookTime = 6, useLabel = "Eating it raw",
		desc = "Raw. It fills little and leaves you thirsty. Cook it over a fire." },
	cooked_squirrel = { name = "Cooked Squirrel", kind = "Food", rarity = "Uncommon", stack = 3, hunger = 40, useTime = 2.2,
		desc = "Roasted over a fire. A proper meal." },
	firewood = { name = "Firewood", kind = "Utility", rarity = "Common", stack = 2, builds = "campfire",
		desc = "Dry sticks. Hold them, look at the ground and build a fire." },
	-- Armor
	leather_vest = { name = "Leather Vest", kind = "Armor", rarity = "Uncommon", stack = 1, damageMultiplier = 0.85, useTime = 1.5,
		desc = "Takes the edge off incoming hits." },
	padded_armor = { name = "Padded Armor", kind = "Armor", rarity = "Epic", stack = 1, damageMultiplier = 0.72, useTime = 2.5,
		desc = "Quilted layers and a steel plate." },
}

local USE_LABELS = { Food = "Eating", Drink = "Drinking", Heal = "Bandaging", Armor = "Putting on armor" }
local USE_SOUNDS = { Food = "Eat", Drink = "Drink", Heal = "Bandage", Armor = "ArmorOn" }

for id, def in pairs(ItemDefs.Items) do
	def.id = id
	def.desc = def.desc or ""
	def.equipSound = def.equipSound or (if def.kind == "Bow" then "Equip_Bow" else "Equip_Generic")
	def.useLabel = def.useLabel or USE_LABELS[def.kind]
	def.useSound = def.useSound or USE_SOUNDS[def.kind]
end

-- Loot tables by tier. 1 = scattered and campsites, 2 = POI crates, 3 = the Spire.
-- Weapons_v2 section 7: the Recurve Bow is in no random table (LootService places this round's 3 or 4 on purpose:
-- ItemDefs.BowBudget), the Mace is retired, the Short Bow is capped per round (ItemDefs.RoundCaps). Each weapon's stars
-- are rolled by LootService from Shared.Stars (the source's odds).
ItemDefs.LootTables = {
	[1] = {
		{ id = "berries", weight = 18, min = 2, max = 5 },
		{ id = "apple", weight = 12, min = 1, max = 3 },
		{ id = "water_bottle", weight = 10, min = 1, max = 1 },
		{ id = "empty_bottle", weight = 6, min = 1, max = 1 },
		{ id = "herbs", weight = 10, min = 1, max = 3 },
		{ id = "bandage", weight = 8, min = 1, max = 2 },
		{ id = "knife", weight = 8, min = 1, max = 1 },
		{ id = "arrow", weight = 8, min = 3, max = 6 },
		{ id = "throwing_knife", weight = 4, min = 1, max = 3 },
		{ id = "dried_meat", weight = 5, min = 1, max = 1 },
	},
	[2] = {
		{ id = "machete", weight = 8, min = 1, max = 1 },
		{ id = "hatchet", weight = 8, min = 1, max = 1 },
		{ id = "ring_blade", weight = 5, min = 1, max = 1 },
		{ id = "climb_pick", weight = 4, min = 1, max = 1 },
		{ id = "twin_axe", weight = 2, min = 1, max = 1 },
		{ id = "short_bow", weight = 3, min = 1, max = 1 },
		{ id = "arrow", weight = 10, min = 5, max = 10 },
		{ id = "throwing_knife", weight = 7, min = 2, max = 4 },
		{ id = "leather_vest", weight = 6, min = 1, max = 1 },
		{ id = "dried_meat", weight = 10, min = 1, max = 2 },
		{ id = "bandage", weight = 10, min = 1, max = 3 },
		{ id = "water_bottle", weight = 10, min = 1, max = 1 },
		{ id = "knife", weight = 6, min = 1, max = 1 },
		{ id = "spear", weight = 3, min = 1, max = 1 },
		{ id = "ration", weight = 4, min = 1, max = 1 },
		{ id = "herbs", weight = 4, min = 1, max = 2 },
	},
	[3] = {
		{ id = "sword", weight = 5, min = 1, max = 1 },
		{ id = "twin_axe", weight = 7, min = 1, max = 1 },
		{ id = "spear", weight = 8, min = 1, max = 1 },
		{ id = "machete", weight = 4, min = 1, max = 1 },
		{ id = "hatchet", weight = 4, min = 1, max = 1 },
		{ id = "ring_blade", weight = 4, min = 1, max = 1 },
		{ id = "arrow", weight = 12, min = 8, max = 14 },
		{ id = "padded_armor", weight = 5, min = 1, max = 1 },
		{ id = "leather_vest", weight = 6, min = 1, max = 1 },
		{ id = "medkit", weight = 5, min = 1, max = 1 },
		{ id = "ration", weight = 8, min = 1, max = 2 },
		{ id = "water_bottle", weight = 8, min = 1, max = 1 },
		{ id = "throwing_knife", weight = 6, min = 3, max = 5 },
		{ id = "bandage", weight = 6, min = 2, max = 3 },
	},
}

-- The runner's caches (PlayabilityPlan QW7): tier-2 crates at the meadow edge (loot markers with Runner = true). Each
-- holds one pick from `weapon`, everything in `always`, and `extraRolls` normal rolls from LootTables[extraTier].
ItemDefs.LootTables.Runner = {
	weapon = {
		{ id = "knife", weight = 1, min = 1, max = 1 },
		{ id = "throwing_knife", weight = 1, min = 2, max = 2 },
	},
	always = {
		{ id = "water_bottle", min = 1, max = 1 },
	},
	extraTier = 1,
	extraRolls = 1,
}

-- The owner's bow rule (12 Nov: "3 to 4 per round"; Weapons_v2 section 6). LootService.populate places them on purpose:
-- one in a tier-3 crate at the Horn, the rest in tier-2 site crates at least MinSpacing apart (one per site). If only
-- `small` were placed, the Offering (LootService.refillSpire) adds one, so a round never has more than `full`.
-- (Config.Bow, when the lead adds it, overrides these: PerRound = { small, full, fullFrom }, OfferingTopUp.)
ItemDefs.BowBudget = {
	itemId = "bow",
	small = 3, -- fewer than fullFrom contenders
	full = 4,
	fullFrom = 16,
	hornRadius = 120, -- "at the Horn": tier-3 crates this close to the centre
	minSpacing = 300, -- studs between the site crates that carry one
	offeringTopUp = true,
	arrows = 5, -- each placed bow comes with this many arrows
}
local bowCfg = Config.Bow
if type(bowCfg) == "table" then
	local per = bowCfg.PerRound
	if type(per) == "table" then
		ItemDefs.BowBudget.small = tonumber(per.small) or ItemDefs.BowBudget.small
		ItemDefs.BowBudget.full = tonumber(per.full) or ItemDefs.BowBudget.full
		ItemDefs.BowBudget.fullFrom = tonumber(per.fullFrom) or ItemDefs.BowBudget.fullFrom
	end
	if bowCfg.OfferingTopUp ~= nil then
		ItemDefs.BowBudget.offeringTopUp = bowCfg.OfferingTopUp == true
	end
end

-- At most this many of an item come out of random rolls in one round (Weapons_v2: Short Bows at most 6).
ItemDefs.RoundCaps = {
	short_bow = (type(bowCfg) == "table" and tonumber(bowCfg.ShortBowPerRound)) or 6,
}

function ItemDefs.get(id: string?)
	if id == nil then
		return nil
	end
	return ItemDefs.Items[id]
end

-- Items whose primary action is "use" (hold to eat, drink, bandage or put on armor) instead of attacking.
function ItemDefs.isConsumable(id: string?): boolean
	local def = ItemDefs.get(id)
	return def ~= nil and (def.kind == "Food" or def.kind == "Drink" or def.kind == "Heal" or def.kind == "Armor")
end

-- Weapons that carry 1 to 5 stars per copy (Shared.Stars): every stack-1 weapon, not throwing knives, arrows or fists.
function ItemDefs.isStarred(id: string?): boolean
	local def = ItemDefs.get(id)
	return def ~= nil and def.starred == true
end

-- Items you fight with (melee weapons, the bow, throwables).
function ItemDefs.isWeapon(id: string?): boolean
	local def = ItemDefs.get(id)
	return def ~= nil and not def.hidden and (def.kind == "Melee" or def.kind == "Bow" or def.kind == "Throwable")
end

return ItemDefs
