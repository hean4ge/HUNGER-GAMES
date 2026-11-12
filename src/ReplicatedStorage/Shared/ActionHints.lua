--[[
	ActionHints - the one line under the crosshair that says what the held item does (PlayabilityPlan QW2).
	Built from the numbers in ItemDefs, so the line stays true when items are retuned. Client only (button names come
	from Shared.Glyphs, so every device sees its own buttons).

	ActionHints.ACTIONS = { "Eat", "Drink", "Heal", "Wear", "Bow", "Spear", "Knife", "Fill", "Ammo", "Climb" }
	    also the order of the 3-bit use counters packed into settings.hintsSeen (10 actions = 30 bits)
	ActionHints.forItem(def?) -> string?      the action a held item teaches (nil: nothing to teach, e.g. a sword)
	ActionHints.build(action, def?, device?, ctx?) -> { text, keys, action, stage }?
	    text: the line with button names in [brackets], e.g. "HOLD [LMB] EAT · +12 HUNGER"
	    keys: those button names in order ({ "LMB" }); stage: "full" | "key" (ctx.keyOnly: just the button, "[LMB]")
	    ctx.arrows: arrows carried (the bow line counts them); ctx.climbing: "[C] LET GO" while on a trunk
	ActionHints.touchLabel(def?, aiming?) -> string   the big touch button: EAT, DRINK, HEAL, WEAR, DRAW, THROW, ATTACK
	ActionHints.count(hintsSeen, action) -> 0..7      ActionHints.bump(hintsSeen, action) -> hintsSeen (stops at 7)
	ActionHints.split(text) -> { { text: string, key: boolean } }   for renderers that draw the [KEY] parts as key caps
	ActionHints.keyOf(name, device?) -> string        a button name ("Attack", "Aim", "Drink", "Crouch", "Drop"...)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local Input = require(Shared:WaitForChild("Input"))

local ActionHints = {}

ActionHints.ACTIONS = { "Eat", "Drink", "Heal", "Wear", "Bow", "Spear", "Knife", "Fill", "Ammo", "Climb" }
local INDEX: { [string]: number } = {}
for i, name in ipairs(ActionHints.ACTIONS) do
	INDEX[name] = i - 1
end

local HEAL_VERB: { [string]: string } = { bandage = "BANDAGE", herbs = "APPLY", medkit = "TREAT" }
local TOUCH_USE: { [string]: string } = { Food = "EAT", Drink = "DRINK", Heal = "HEAL", Armor = "WEAR" }

function ActionHints.forItem(def: any): string?
	if type(def) ~= "table" then
		return nil
	end
	local kind = def.kind
	if kind == "Food" then
		return "Eat"
	elseif kind == "Drink" then
		return "Drink"
	elseif kind == "Heal" then
		return "Heal"
	elseif kind == "Armor" then
		return "Wear"
	elseif kind == "Bow" then
		return "Bow"
	elseif kind == "Melee" and def.throwable then
		return "Spear"
	elseif kind == "Throwable" then
		return "Knife"
	elseif kind == "Utility" and def.fillsInto then
		return "Fill"
	elseif kind == "Ammo" then
		return "Ammo"
	end
	return nil
end

-- The touch label of the big ATTACK button for what you hold.
function ActionHints.touchLabel(def: any, aiming: boolean?): string
	if type(def) ~= "table" then
		return "ATTACK"
	end
	local use = TOUCH_USE[def.kind]
	if use then
		return use
	elseif def.kind == "Bow" then
		return "DRAW"
	elseif def.kind == "Throwable" then
		return "THROW"
	elseif def.kind == "Melee" and def.throwable and aiming then
		return "THROW"
	end
	return "ATTACK"
end

function ActionHints.keyOf(name: string, device: string?): string
	local d = device or Input.device()
	if d == "Touch" and name == "Attack" then
		return "ATTACK"
	end
	return Glyphs.forAction(name, d) or string.upper(name)
end

local function stats(def: any): string
	local parts = {}
	if tonumber(def.hunger) then
		table.insert(parts, string.format("+%d HUNGER", def.hunger))
	end
	if tonumber(def.thirst) then
		table.insert(parts, string.format("+%d THIRST", def.thirst))
	end
	if tonumber(def.heal) then
		table.insert(parts, string.format("+%d HEALTH", def.heal))
	end
	return table.concat(parts, " ")
end

local function keysIn(text: string): { string }
	local keys = {}
	for key in string.gmatch(text, "%[([^%]]+)%]") do
		table.insert(keys, key)
	end
	return keys
end

-- (full line, key-only line) for an action on a device.
local function lines(action: string, def: any, device: string, ctx: { [string]: any }): (string?, string?)
	local touch = device == "Touch"
	local attack = ActionHints.keyOf("Attack", device)
	if action == "Eat" or action == "Drink" or action == "Heal" or action == "Wear" then
		local verb
		if action == "Eat" then
			verb = "EAT"
		elseif action == "Drink" then
			verb = "DRINK"
		elseif action == "Heal" then
			verb = HEAL_VERB[def and def.id or ""] or "HEAL"
		else
			verb = "PUT ON"
		end
		local tail
		if action == "Wear" then
			local mult = tonumber(def and def.damageMultiplier) or 1
			tail = string.format("-%d%% DAMAGE", math.floor((1 - mult) * 100 + 0.5))
		else
			tail = if def then stats(def) else ""
		end
		if touch then
			local button = ActionHints.touchLabel(def, false)
			return string.format("HOLD [%s] · %s", button, tail), string.format("[%s]", button)
		end
		return string.format("HOLD [%s] %s · %s", attack, verb, tail), string.format("[%s]", attack)
	elseif action == "Bow" then
		local arrows = math.max(0, math.floor(tonumber(ctx.arrows) or 0))
		local count = if arrows == 0 then "NO ARROWS" elseif arrows == 1 then "1 ARROW" else string.format("%d ARROWS", arrows)
		if touch then
			return string.format("HOLD [DRAW] · LET GO TO SHOOT · %s", count), "[DRAW]"
		end
		return string.format("HOLD [%s] DRAW · RELEASE TO SHOOT · %s", attack, count), string.format("[%s]", attack)
	elseif action == "Spear" then
		local aim = ActionHints.keyOf("Aim", device)
		if touch then
			return string.format("[ATTACK] STAB · [%s] THEN [THROW]", aim), string.format("[%s] [THROW]", aim)
		end
		return string.format("[%s] STAB · HOLD [%s] + [%s] THROW", attack, aim, attack), string.format("[%s] + [%s]", aim, attack)
	elseif action == "Knife" then
		if touch then
			return "[THROW] · PICK IT UP AFTER", "[THROW]"
		end
		return string.format("[%s] THROW · PICK IT UP AFTER", attack), string.format("[%s]", attack)
	elseif action == "Fill" then
		if touch then
			return "LOOK AT WATER · TAP [FILL]", nil
		end
		return string.format("LOOK AT WATER · [%s] FILL", ActionHints.keyOf("Drink", device)), nil
	elseif action == "Ammo" then
		return "AMMO · EQUIP THE BOW TO SHOOT", nil
	elseif action == "Climb" then
		local crouch = ActionHints.keyOf("Crouch", device)
		if ctx.climbing then
			return string.format("[%s] LET GO", crouch), string.format("[%s]", crouch)
		end
		return string.format("PUSH FORWARD TO CLIMB · [%s] LET GO", crouch), nil
	end
	return nil, nil
end

function ActionHints.build(action: string, def: any, device: string?, ctx: { [string]: any }?)
	local c = ctx or {}
	local d = device or Input.device()
	local full, keyOnly = lines(action, def, d, c)
	local text = if c.keyOnly then keyOnly else full
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local keys = keysIn(text)
	return {
		text = text,
		keys = if #keys > 0 then keys else nil,
		action = action,
		stage = if c.keyOnly then "key" else "full",
	}
end

-- 3 bits per action, packed into one number (settings.hintsSeen).
function ActionHints.count(hintsSeen: number?, action: string): number
	local index = INDEX[action]
	local packed = math.floor(tonumber(hintsSeen) or 0)
	if index == nil or packed <= 0 then
		return 0
	end
	return bit32.band(bit32.rshift(packed, index * 3), 7)
end

function ActionHints.bump(hintsSeen: number?, action: string): number
	local index = INDEX[action]
	local packed = math.clamp(math.floor(tonumber(hintsSeen) or 0), 0, 2 ^ 30 - 1)
	if index == nil then
		return packed
	end
	local current = bit32.band(bit32.rshift(packed, index * 3), 7)
	if current >= 7 then
		return packed
	end
	return packed + bit32.lshift(1, index * 3)
end

function ActionHints.split(text: string): { { text: string, key: boolean } }
	local parts = {}
	local position = 1
	while position <= #text do
		local s, e, key = string.find(text, "%[([^%]]+)%]", position)
		if not s then
			table.insert(parts, { text = string.sub(text, position), key = false })
			break
		end
		if s > position then
			table.insert(parts, { text = string.sub(text, position, s - 1), key = false })
		end
		table.insert(parts, { text = key, key = true })
		position = e + 1
	end
	return parts
end

return ActionHints
