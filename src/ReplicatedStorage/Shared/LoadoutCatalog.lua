--[[
	LoadoutCatalog - the one table the Loadout reads (docs/design/Combat_v3.md sections 2, 3 and 4): the seven
	Specialties (one weapon skill each), the six general skills and the trails, with the plain line each shows.
	Both sides read it: LoadoutController draws the rows from it, KitService checks a LoadoutSet against it.

	THE SOURCES
	  Until the combat-moves and trails-vfx modules exist this module holds the page's own lists. When
	  ReplicatedStorage.Shared.Skills or Shared.Trails appear, their entries win field by field (matched by id), so the
	  names, lines, cooldowns and prices shown are always theirs. What it reads from them (any of these is enough):
	    Skills.Weapon[family] = { id, name, line | desc | summary, Cooldown | cooldown }   (family = Fists, ShortBlade, ...)
	    Skills.General[id] or Skills.General = { { id, name, line, Cooldown } }
	    Trails.List or Trails.Catalog = { { id, name, kind, slots = { swing, arrow, throw } | { "swing", ... },
	                                        rarity, price, colors = { Color3, Color3 } } }
	  Config.Skills.Weapon / General cooldowns and Config.Trails.Prices also win over the numbers here.

	API
	  LoadoutCatalog.Specialties   { { id, name, skill = { id, name, line, cooldown } } } in display order
	  LoadoutCatalog.General       { { id, name, line, cooldown } } in display order
	  LoadoutCatalog.Trails        { { id, name, kind, slots = { swing = true, ... }, rarity, price, colors, glow } }
	                               ("none" first: always owned, no trail at all)
	  LoadoutCatalog.Slots         { "swing", "arrow", "throw" }
	  LoadoutCatalog.specialty(id) / general(id) / trail(id) -> entry?
	  LoadoutCatalog.trailFits(id, slot) -> boolean
	  LoadoutCatalog.isFreeTrail(id) -> boolean
	  LoadoutCatalog.suggestedSpecialty(kitId) -> family id
	  LoadoutCatalog.defaults(kitId?) -> { specialty, general, trails = { swing, arrow, throw } }
	  LoadoutCatalog.sanitize(raw, owns?) -> { specialty, general, trails }   owns(trailId) -> boolean (nil: free only)
	  LoadoutCatalog.encodeOwned(set) / decodeOwned(text)   the TrailsOwned attribute ("id,id,...")
]]
local Shared = script.Parent
local Config = require(Shared:WaitForChild("Config"))

local LoadoutCatalog = {}

LoadoutCatalog.Slots = { "swing", "arrow", "throw" }
LoadoutCatalog.SlotNames = { swing = "SWING", arrow = "ARROW", throw = "THROW" }
LoadoutCatalog.SlotAttr = { swing = "TrailSwing", arrow = "TrailArrow", throw = "TrailThrow" } -- Shared.Trails.ATTR

local SPECIALTIES = {
	{ id = "Fists", name = "Fists", skill = { id = "head_kick", name = "Head Kick", line = "A high round kick that breaks any wind-up", cooldown = 10 } },
	{ id = "ShortBlade", name = "Short blade", skill = { id = "chained_strikes", name = "Chained Strikes", line = "Five quick strikes, each a little harder", cooldown = 16 } },
	{ id = "Sword", name = "Sword", skill = { id = "running_cut", name = "Running Cut", line = "A straight dash that cuts all in your lane", cooldown = 18 } },
	{ id = "Axe", name = "Axe", skill = { id = "whirl", name = "Whirl", line = "One full turn, hits all near you", cooldown = 15 } },
	{ id = "Spear", name = "Spear", skill = { id = "vault_kick", name = "Vault Kick", line = "Vault on the spear and kick them down", cooldown = 18 } },
	{ id = "Throwing", name = "Throwing", skill = { id = "ricochet", name = "Ricochet", line = "Your next throw glances on to a second target", cooldown = 14 } },
	{ id = "Bow", name = "Bow", skill = { id = "piercing_shot", name = "Piercing Shot", line = "Your next full draw passes through", cooldown = 20 } },
}

local GENERAL = {
	{ id = "concentration", name = "Concentration", line = "A wider parry, faster heavies, cheaper swings", cooldown = 40 },
	{ id = "second_wind", name = "Second Wind", line = "Stamina back at once, a little health", cooldown = 60 },
	{ id = "sprint_burst", name = "Sprint Burst", line = "Three seconds of faster running, no stamina", cooldown = 35 },
	{ id = "quiet_step", name = "Quiet Step", line = "Your steps carry only a few metres", cooldown = 45 },
	{ id = "steady_hands", name = "Steady Hands", line = "A still bow and a quicker draw", cooldown = 45 },
	{ id = "brace", name = "Brace", line = "Half the knockback, no knockdown", cooldown = 40 },
}

local ALL = { swing = true, arrow = true, throw = true }
local AT = { arrow = true, throw = true }
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Combat_v3 4.2: names are ours. colors = { head, tail } for the swatch and the preview stroke.
local TRAILS = {
	{ id = "none", name = "None", kind = "None", slots = ALL, rarity = "Free", colors = { rgb(120, 120, 120), rgb(120, 120, 120) } },
	{ id = "draught", name = "Draught", kind = "Natural", slots = ALL, rarity = "Free", colors = { rgb(236, 232, 222), rgb(190, 188, 182) } },
	{ id = "dust", name = "Dust", kind = "Natural", slots = ALL, rarity = "Free", colors = { rgb(168, 150, 124), rgb(120, 108, 92) } },
	{ id = "thistledown", name = "Thistledown", kind = "Natural", slots = AT, rarity = "Common", colors = { rgb(250, 250, 244), rgb(220, 220, 210) } },
	{ id = "neon_thread", name = "Neon Thread", kind = "Bright", slots = ALL, rarity = "Common", colors = { rgb(255, 64, 196), rgb(255, 120, 220) }, glow = true },
	{ id = "hardline", name = "Hardline", kind = "Bright", slots = ALL, rarity = "Common", colors = { rgb(230, 240, 255), rgb(70, 150, 255) }, glow = true },
	{ id = "haze_line", name = "Haze Line", kind = "Bright", slots = ALL, rarity = "Common", colors = { rgb(60, 220, 235), rgb(150, 240, 245) }, glow = true },
	{ id = "leafwake", name = "Leafwake", kind = "Natural", slots = ALL, rarity = "Rare", colors = { rgb(108, 140, 72), rgb(214, 190, 112) } },
	{ id = "ember_drift", name = "Ember Drift", kind = "Natural", slots = ALL, rarity = "Rare", colors = { rgb(255, 150, 60), rgb(120, 110, 100) } },
	{ id = "kindle", name = "Kindle", kind = "Bright", slots = ALL, rarity = "Rare", colors = { rgb(255, 196, 70), rgb(255, 110, 40) }, glow = true },
	{ id = "frostbreath", name = "Frostbreath", kind = "Natural", slots = { swing = true, arrow = true }, rarity = "Rare", colors = { rgb(230, 240, 250), rgb(190, 210, 228) } },
	{ id = "pulse", name = "Pulse", kind = "Bright", slots = ALL, rarity = "Rare", colors = { rgb(240, 255, 255), rgb(140, 230, 240) }, glow = true },
	{ id = "glowworm", name = "Glowworm", kind = "Bright", slots = AT, rarity = "Rare", colors = { rgb(240, 236, 90), rgb(90, 210, 90) }, glow = true },
	{ id = "forked_light", name = "Forked Light", kind = "Bright", slots = AT, rarity = "Epic", colors = { rgb(245, 250, 255), rgb(130, 180, 255) }, glow = true },
	{ id = "shardfall", name = "Shardfall", kind = "Bright", slots = AT, rarity = "Epic", colors = { rgb(220, 30, 60), rgb(255, 235, 235) }, glow = true },
	{ id = "wishing_stars", name = "Wishing Stars", kind = "Bright", slots = ALL, rarity = "Epic", colors = { rgb(255, 214, 90), rgb(255, 240, 170) }, glow = true },
	{ id = "nebula", name = "Nebula", kind = "Bright", slots = ALL, rarity = "Epic", colors = { rgb(150, 80, 255), rgb(90, 50, 170) }, glow = true },
	{ id = "comet", name = "Comet", kind = "Bright", slots = { arrow = true }, rarity = "Legendary", colors = { rgb(235, 250, 255), rgb(60, 200, 255) }, glow = true },
	{ id = "molten", name = "Molten", kind = "Bright", slots = { swing = true, throw = true }, rarity = "Legendary", colors = { rgb(255, 245, 220), rgb(255, 120, 30) }, glow = true },
}

local PRICES = { Free = 0, Common = 300, Rare = 800, Epic = 1800, Legendary = 4000 }
local KIT_SUGGESTS = { archer = "Bow", forager = "ShortBlade", hunter = "Throwing", climber = "Axe", medic = "Fists" }
local DEFAULT_GENERAL = "second_wind"
local DEFAULT_TRAIL = "draught"

--------------------------------------------------------------------------------------------------------------------
-- The other modules win when they exist
--------------------------------------------------------------------------------------------------------------------

local function optional(name: string): any
	local module = Shared:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function lineOf(src: any): string?
	local v = src.line or src.desc or src.summary or src.description
	return if type(v) == "string" and v ~= "" then v else nil
end

local function cooldownOf(src: any): number?
	local v = src.Cooldown or src.cooldown
	return if type(v) == "number" then v else nil
end

local function merge(dst: any, src: any)
	if type(src) ~= "table" then
		return
	end
	if type(src.name) == "string" and src.name ~= "" then
		dst.name = src.name
	end
	dst.line = lineOf(src) or dst.line
	dst.cooldown = cooldownOf(src) or dst.cooldown
end

do
	local cfg = type(Config.Skills) == "table" and Config.Skills or {}
	local skills = optional("Skills")
	for _, spec in ipairs(SPECIALTIES) do
		if type(cfg.Weapon) == "table" then
			merge(spec.skill, cfg.Weapon[spec.id])
		end
		if skills and type(skills.Weapon) == "table" then
			merge(spec.skill, skills.Weapon[spec.id])
		end
		if type(cfg.KitSuggests) == "table" then
			for kit, family in pairs(cfg.KitSuggests) do
				if type(kit) == "string" and type(family) == "string" then
					KIT_SUGGESTS[string.lower(kit)] = family
				end
			end
		end
	end
	for _, g in ipairs(GENERAL) do
		if type(cfg.General) == "table" then
			merge(g, cfg.General[g.id])
		end
		if skills and type(skills.General) == "table" then
			local src = skills.General[g.id]
			if src == nil then
				for _, entry in ipairs(skills.General) do
					if type(entry) == "table" and entry.id == g.id then
						src = entry
					end
				end
			end
			merge(g, src)
		end
	end

	local tcfg = type(Config.Trails) == "table" and Config.Trails or {}
	if type(tcfg.Prices) == "table" then
		for rarity, price in pairs(tcfg.Prices) do
			if type(price) == "number" then
				PRICES[rarity] = price
			end
		end
	end
	local trails = optional("Trails")
	local list = trails and (trails.list or trails.List or trails.Catalog)
	if type(list) == "table" and #list > 0 then
		local byId = {}
		for _, t in ipairs(TRAILS) do
			byId[t.id] = t
		end
		local out = { TRAILS[1] } -- "none" stays first
		for _, src in ipairs(list) do
			if type(src) == "table" and type(src.id) == "string" and src.id ~= "none" then
				local t = byId[src.id] or { id = src.id, name = src.id, kind = "Bright", slots = ALL, rarity = "Rare",
					colors = { rgb(236, 232, 222), rgb(190, 188, 182) } }
				if type(src.name) == "string" then
					t.name = src.name
				end
				if type(src.kind) == "string" then
					t.kind = src.kind
				end
				if type(src.rarity) == "string" then
					t.rarity = src.rarity
				end
				if type(src.price) == "number" then
					t.price = src.price
				end
				if type(src.slots) == "table" then
					local slots = {}
					for k, v in pairs(src.slots) do
						if type(k) == "string" and v == true then
							slots[k] = true
						elseif type(v) == "string" then
							slots[v] = true
						end
					end
					if next(slots) then
						t.slots = slots
					end
				end
				if type(src.colors) == "table" and typeof(src.colors[1]) == "Color3" then
					t.colors = { src.colors[1], src.colors[2] or src.colors[1] }
				elseif type(src.look) == "table" and type(src.look[1]) == "table" and type(src.look[1].color) == "table"
					and typeof(src.look[1].color[1]) == "Color3" then
					local c = src.look[1].color
					t.colors = { c[1], c[2] or c[1] }
				end
				t.line = lineOf(src) or t.line
				if type(trails.price) == "function" then
					local ok, price = pcall(trails.price, src.id)
					if ok and type(price) == "number" then
						t.price = price
					end
				end
				table.insert(out, t)
			end
		end
		TRAILS = out
	end
	if type(tcfg.Free) == "table" then
		for _, t in ipairs(TRAILS) do
			for _, id in ipairs(tcfg.Free) do
				if t.id == id then
					t.rarity = "Free"
				end
			end
		end
	end
	for _, t in ipairs(TRAILS) do
		t.price = t.price or PRICES[t.rarity] or 0
		if t.rarity == "Free" then
			t.price = 0
		end
	end
	if type(tcfg.Default) == "table" and type(tcfg.Default.swing) == "string" then
		DEFAULT_TRAIL = tcfg.Default.swing
	end
end

LoadoutCatalog.Specialties = SPECIALTIES
LoadoutCatalog.General = GENERAL
LoadoutCatalog.Trails = TRAILS
LoadoutCatalog.Prices = PRICES

local specById, genById, trailById = {}, {}, {}
for i, s in ipairs(SPECIALTIES) do
	s.index = i
	specById[s.id] = s
end
for i, g in ipairs(GENERAL) do
	g.index = i
	genById[g.id] = g
end
for i, t in ipairs(TRAILS) do
	t.index = i
	trailById[t.id] = t
end

function LoadoutCatalog.specialty(id: any)
	return if type(id) == "string" then specById[id] else nil
end

function LoadoutCatalog.general(id: any)
	return if type(id) == "string" then genById[id] else nil
end

function LoadoutCatalog.trail(id: any)
	return if type(id) == "string" then trailById[id] else nil
end

function LoadoutCatalog.trailFits(id: any, slot: string): boolean
	local t = LoadoutCatalog.trail(id)
	return t ~= nil and t.slots[slot] == true
end

function LoadoutCatalog.isFreeTrail(id: any): boolean
	local t = LoadoutCatalog.trail(id)
	return t ~= nil and (t.rarity == "Free" or t.id == "none")
end

function LoadoutCatalog.suggestedSpecialty(kitId: any): string
	local family = type(kitId) == "string" and KIT_SUGGESTS[string.lower(kitId)] or nil
	return if family and specById[family] then family else "Fists"
end

function LoadoutCatalog.defaults(kitId: any)
	return {
		specialty = LoadoutCatalog.suggestedSpecialty(kitId),
		general = DEFAULT_GENERAL,
		trails = { swing = DEFAULT_TRAIL, arrow = DEFAULT_TRAIL, throw = DEFAULT_TRAIL },
	}
end

-- A clean loadout from anything (a remote's payload, a stored profile). owns(trailId) says a bought trail is owned;
-- without it only free trails pass. Unknown or unowned values fall back to the defaults.
function LoadoutCatalog.sanitize(raw: any, owns: ((string) -> boolean)?, kitId: any)
	local src = if type(raw) == "table" then raw else {}
	local out = LoadoutCatalog.defaults(kitId)
	if specById[src.specialty] then
		out.specialty = src.specialty
	end
	if genById[src.general] then
		out.general = src.general
	end
	local trails = if type(src.trails) == "table" then src.trails else {}
	for _, slot in ipairs(LoadoutCatalog.Slots) do
		local id = trails[slot]
		if type(id) == "string" and LoadoutCatalog.trailFits(id, slot)
			and (LoadoutCatalog.isFreeTrail(id) or (owns ~= nil and owns(id) == true)) then
			out.trails[slot] = id
		end
	end
	return out
end

function LoadoutCatalog.encodeOwned(set: { [string]: any }): string
	local ids = {}
	for id, v in pairs(set) do
		if v and trailById[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function LoadoutCatalog.decodeOwned(text: any): { [string]: boolean }
	local set = {}
	if type(text) == "string" then
		for id in string.gmatch(text, "[%w_]+") do
			set[id] = true
		end
	end
	return set
end

return LoadoutCatalog
