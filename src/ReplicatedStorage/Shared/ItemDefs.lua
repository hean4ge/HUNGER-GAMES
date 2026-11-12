--[[
	ItemDefs - every item in the game. The Inventory/Loot system owns this file; Combat reads the stats.
	kind: "Melee" | "Bow" | "Throwable" | "Ammo" | "Food" | "Drink" | "Heal" | "Armor" | "Utility"
	Shared fields: id (filled in below), name, kind, rarity, stack (max per slot), desc
	Melee: damage, cooldown, range, windup, staminaCost, [throwable, throwDamage, throwSpeed, throwGravity]
	Bow: ammo, damageMin, damageMax, drawTime, speedMin, speedMax, gravity, headshotMultiplier
	Throwable: damage, speed, gravity, cooldown
	Food / Drink / Heal: hunger, thirst, heal, useTime, [becomes]
	Armor: damageMultiplier, useTime        Utility: [fillsInto]
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
	-- Melee
	fists = { name = "Fists", kind = "Melee", rarity = "Common", stack = 1, hidden = true,
		damage = 8, cooldown = 0.45, range = 5.5, windup = 0.06, staminaCost = 0.03 },
	knife = { name = "Hunting Knife", kind = "Melee", rarity = "Common", stack = 1,
		damage = 22, cooldown = 0.45, range = 6, windup = 0.08, staminaCost = 0.04,
		desc = "Quick, quiet, reliable.", equipSound = "Equip_Blade" },
	machete = { name = "Machete", kind = "Melee", rarity = "Uncommon", stack = 1,
		damage = 32, cooldown = 0.7, range = 7, windup = 0.14, staminaCost = 0.07,
		desc = "Wide, heavy cuts.", equipSound = "Equip_Blade" },
	hatchet = { name = "Hatchet", kind = "Melee", rarity = "Uncommon", stack = 1,
		damage = 36, cooldown = 0.8, range = 6.5, windup = 0.16, staminaCost = 0.08,
		desc = "Short reach, big hits.", equipSound = "Equip_Blade" },
	spear = { name = "Spear", kind = "Melee", rarity = "Rare", stack = 1,
		damage = 30, cooldown = 0.85, range = 9.5, windup = 0.18, staminaCost = 0.08,
		throwable = true, throwDamage = 60, throwSpeed = 150, throwGravity = 45,
		desc = "Long reach. Hold Aim and attack to throw.", equipSound = "Equip_Blade" },
	mace = { name = "Mace", kind = "Melee", rarity = "Rare", stack = 1,
		damage = 46, cooldown = 1.1, range = 7, windup = 0.25, staminaCost = 0.12,
		desc = "Slow and crushing." },
	sword = { name = "Arena Sword", kind = "Melee", rarity = "Epic", stack = 1,
		damage = 40, cooldown = 0.75, range = 8, windup = 0.15, staminaCost = 0.09,
		desc = "The best blade in the arena.", equipSound = "Equip_Blade" },
	-- Ranged
	bow = { name = "Recurve Bow", kind = "Bow", rarity = "Rare", stack = 1, ammo = "arrow",
		damageMin = 14, damageMax = 50, drawTime = 0.9, speedMin = 90, speedMax = 240, gravity = 55,
		headshotMultiplier = Config.Combat.BowHeadshotMultiplier or 2, desc = "Hold to draw, release to fire. Needs arrows.",
		lootBundle = { id = "arrow", min = 4, max = 8 } },
	throwing_knife = { name = "Throwing Knife", kind = "Throwable", rarity = "Uncommon", stack = 6,
		damage = 28, speed = 160, gravity = 40, cooldown = 0.5, desc = "Throw it, then pick it back up.",
		equipSound = "Equip_Blade" },
	arrow = { name = "Arrow", kind = "Ammo", rarity = "Common", stack = 24, desc = "Ammunition for the bow." },
	-- Healing
	herbs = { name = "Healing Herbs", kind = "Heal", rarity = "Common", stack = 6, heal = 10, useTime = 1.5,
		desc = "Crushed leaves that soothe small wounds.", useLabel = "Applying herbs" },
	bandage = { name = "Bandage", kind = "Heal", rarity = "Common", stack = 4, heal = 20, useTime = 2.5,
		desc = "Clean cloth to bind a wound." },
	medkit = { name = "Med Kit", kind = "Heal", rarity = "Epic", stack = 1, heal = 65, useTime = 5,
		desc = "Everything needed to patch up a bad wound.", useLabel = "Treating wounds" },
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
		{ id = "machete", weight = 9, min = 1, max = 1 },
		{ id = "hatchet", weight = 9, min = 1, max = 1 },
		{ id = "bow", weight = 5, min = 1, max = 1 },
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
		{ id = "sword", weight = 7, min = 1, max = 1 },
		{ id = "mace", weight = 7, min = 1, max = 1 },
		{ id = "spear", weight = 8, min = 1, max = 1 },
		{ id = "bow", weight = 10, min = 1, max = 1 },
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

-- Items you fight with (melee weapons, the bow, throwables).
function ItemDefs.isWeapon(id: string?): boolean
	local def = ItemDefs.get(id)
	return def ~= nil and not def.hidden and (def.kind == "Melee" or def.kind == "Bow" or def.kind == "Throwable")
end

return ItemDefs
