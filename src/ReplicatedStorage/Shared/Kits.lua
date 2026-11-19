--[[
	Kits - the five free 1-star kits a player picks in the train (docs/design/Weapons_v2.md section 3).
	Server: KitService delivers the pick. Client: KitController shows the pick line in the lobby.

	THE SWITCH: Kits.Settings.Delivery
	  "Midpoint" (default)  the kit comes down as a sponsor parcel near the player at the middle of the round
	  "Start"               the kit goes into the bag at the launch (what does not fit lands at the plinth's foot)
	Config.Kits, when the lead adds it, overrides any key here (Config.Kits.Delivery = "Start" is the one-line change).

	Kits.List          { { id, name, items = { { id, count } }, for } } in display order
	Kits.get(id) -> kit?      Kits.index(id) -> number?      Kits.default() -> kit
	Kits.summary(kit) -> "Short Bow, Arrow ×8, Apple"
	Kits.Settings      timing and landing numbers (below)
]]
local Config = require(script.Parent:WaitForChild("Config"))
local ItemDefs = require(script.Parent:WaitForChild("ItemDefs"))

local Kits = {}

local DEFAULTS = {
	Delivery = "Midpoint", -- "Midpoint" | "Start": the one-line switch
	MidpointTime = nil, -- nil = half of the round's length (600 s on Map 1)
	MidpointShare = 0.5, -- ...or when this share of the round's contenders are out, if sooner
	MinTime = 240, -- never before this many seconds into a real round
	PracticeTime = 60, -- practice rounds
	WarningLead = 10, -- "Your kit is coming" this long before the landing
	Stagger = 20, -- drops spread over 0..Stagger s per player
	DropHeight = 140,
	FallTime = 7,
	LandMin = 15,
	LandMax = 25,
	BorderClearance = 30,
	WaterSearch = 60,
	OwnerOpenTime = 0.6,
	OtherOpenTime = 2.5,
	MarkerTime = 90,
	SmokeTime = 20,
	Default = "forager",
	ShowFrom = 300, -- studs: the falling chute is streamed to everyone this far
}

local settings = {}
do
	local given = if type(Config.Kits) == "table" then Config.Kits else {}
	for key, value in pairs(DEFAULTS) do
		settings[key] = value
	end
	for key, value in pairs(given) do
		settings[key] = value
	end
	if type(settings.Default) == "string" then
		settings.Default = string.lower(settings.Default)
	end
end
Kits.Settings = settings

-- The Trapper kit ships as "Hunter" until the Wire Snare can be set (Weapons_v2 1.2: "If the snare slips, the
-- Trapper kit ships as Hunter (3 throwing knives, dried meat, firewood) and the snare follows").
Kits.List = {
	{ id = "archer", name = "Archer", forWhom = "ranged from mid-round",
		items = { { id = "short_bow", count = 1 }, { id = "arrow", count = 8 }, { id = "apple", count = 1 } } },
	{ id = "forager", name = "Forager", forWhom = "the default for new players",
		items = { { id = "knife", count = 1 }, { id = "apple", count = 3 }, { id = "water_bottle", count = 1 } } },
	{ id = "hunter", name = "Hunter", forWhom = "holding a trail or a camp",
		items = { { id = "throwing_knife", count = 3 }, { id = "dried_meat", count = 1 }, { id = "firewood", count = 1 } } },
	{ id = "medic", name = "Medic", forWhom = "no weapon; survives the second half",
		items = { { id = "bandage", count = 2 }, { id = "herbs", count = 3 }, { id = "water_bottle", count = 1 } } },
	{ id = "climber", name = "Climber", forWhom = "trees, rock and high ground",
		items = { { id = "climb_pick", count = 1 }, { id = "berries", count = 4 }, { id = "firewood", count = 1 } } },
}

local byId = {}
for i, kit in ipairs(Kits.List) do
	kit.index = i
	byId[kit.id] = kit
end

function Kits.get(id: any)
	return if type(id) == "string" then byId[string.lower(id)] else nil
end

function Kits.index(id: any): number?
	local kit = Kits.get(id)
	return kit and kit.index
end

function Kits.default()
	return byId[settings.Default] or byId.forager
end

-- bringId / bringLabel (optional): an owned weapon chosen with BRING. The line then shows what the parcel holds,
-- the same swap as KitService itemsFor: it takes the kit's first starred weapon's place (or leads), a bow adds Arrow ×6.
function Kits.summary(kit: any, bringId: string?, bringLabel: string?): string
	if not kit then
		return ""
	end
	local bringDef = if type(bringId) == "string" and bringId ~= "" then ItemDefs.get(bringId) else nil
	if bringDef and (not bringDef.starred or bringDef.neverOwned) then
		bringDef = nil
	end
	local bringName = bringDef and (bringLabel or bringDef.name)
	local parts = {}
	local replaced, hasArrows = false, false
	for _, item in ipairs(kit.items) do
		local def = ItemDefs.get(item.id)
		if bringName and not replaced and def and def.starred then
			replaced = true
			table.insert(parts, bringName)
		else
			hasArrows = hasArrows or item.id == "arrow"
			local name = if def then def.name else item.id
			if item.count > 1 then
				name = string.format("%s \u{00D7}%d", name, item.count)
			end
			table.insert(parts, name)
		end
	end
	if bringName and not replaced then
		table.insert(parts, 1, bringName)
	end
	if bringDef and bringDef.kind == "Bow" and not hasArrows then
		table.insert(parts, "Arrow \u{00D7}6")
	end
	return table.concat(parts, ", ")
end

return Kits
