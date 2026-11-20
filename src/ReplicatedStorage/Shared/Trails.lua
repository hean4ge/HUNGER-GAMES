--[[
	Trails - the cosmetic trail catalogue (docs/design/Combat_v3.md section 4). Shared: TrailService (server) checks ids,
	slots and prices against it; TrailController (client) builds the looks from the recipes below.

	A trail is a cosmetic line on a swing, an arrow or a thrown item. It never changes damage, speed, range, hit boxes or
	sound. Built only from Trail, Beam and ParticleEmitter with the engine's own textures (rbxasset://, checked in the
	Player install on 19 Nov: particles/sparkles_main, fire_main, fire_sparks_main, smoke_main, forcefield_glow_main,
	and textures/triangle.png, noise.dds). No uploads. Names are ours.

	Slots: "swing" (melee swings and skills), "arrow" (both bows), "throw" (every thrown weapon).
	Kind: "Natural" (restrained: the owner's 15 Nov direction) or "Bright" (glowing: their 19 Nov references). Settings
	can draw others' Bright trails as Draught (Trails.OTHERS: "All" | "Natural" | "Off").

	API
	  Trails.get(id) -> def?               Trails.list -> { def } in shop order (ids also as Trails.ById)
	  Trails.fits(id, slot) -> boolean     Trails.price(id) -> number (0 = free)
	  Trails.isFree(id) -> boolean         Trails.slotFor(itemId, kind) -> "swing" | "arrow" | "throw"
	  Trails.ATTR[slot] -> the Player attribute that holds the equipped id ("TrailSwing" / "TrailArrow" / "TrailThrow")
	  Trails.OWNED_ATTR = "TrailsOwned" (comma list of the ids bought, set by TrailService on the owner only)

	A recipe (def.look) is a list of layers; each layer is one of
	  { type = "trail", color = {c0, c1?}, width, life, alpha = {a0, a1}, light, bright, texture?, texLen?, swingSpan?, bands? }
	  { type = "particles", texture, color = {c0, c1?}, size = {s0, s1}, alpha = {a0, a1}, rate, life = {min, max},
	    speed = {min, max}, drag?, accel?, spread?, rot?, rotSpeed?, light?, bright?, locked?, spin? }
	  { type = "bolt", color, width, jag, length, every }  -- two Beams in a zig-zag, re-rolled every `every` s
	Widths are studs (a swing ribbon instead covers swingSpan of the blade, from the tip down).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trails = {}

local okCfg, Config = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end)
local cfg = (okCfg and type(Config) == "table" and type(Config.Trails) == "table") and Config.Trails or {}

Trails.PRICES = cfg.Prices or { Free = 0, Common = 300, Rare = 800, Epic = 1800, Legendary = 4000 }
Trails.PRICES.Free = 0
Trails.DEFAULT = cfg.Default or { swing = "draught", arrow = "draught", throw = "draught" }
Trails.START_AFTER = cfg.StartAfter or 6 -- studs from the hand before an arrow or throw trail shows
Trails.DRAW_RANGE = cfg.DrawRange or 120 -- others' trails beyond this are not drawn
Trails.MAX_SWING = cfg.MaxSwingTrails or 12 -- the nearest players whose swing trails are drawn at once
Trails.MAX_RATE = cfg.MaxRate or 60
Trails.BUY_HOLD = cfg.BuyHold or 0.6
Trails.OTHERS_DEFAULT = cfg.OthersDefault or { Desktop = "All", Phone = "Natural" }
Trails.SLOTS = { "swing", "arrow", "throw" }
Trails.ATTR = { swing = "TrailSwing", arrow = "TrailArrow", throw = "TrailThrow" }
Trails.OWNED_ATTR = "TrailsOwned"
Trails.RARITY_ORDER = { "Free", "Common", "Rare", "Epic", "Legendary" }

-- The engine's own textures (rbxasset: shipped with every client, nothing uploaded)
local TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	shard = "rbxasset://textures/triangle.png",
	noise = "rbxasset://textures/noise.dds",
}
Trails.TEX = TEX

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local ALL = { swing = true, arrow = true, throw = true }
local SHOTS = { arrow = true, throw = true }

-- Shop order: free first, then by rarity. Colours in the comments are the design page's (4.2).
Trails.list = {
	{ id = "draught", name = "Draught", kind = "Natural", rarity = "Free", slots = ALL,
		desc = "A pale streak of moving air.",
		look = {
			{ type = "trail", color = { rgb(236, 232, 222), rgb(190, 188, 182) }, width = 0.22, life = 0.16,
				alpha = { 0.55, 1 }, light = 0.15, swingSpan = 0.75 },
		} },
	{ id = "dust", name = "Dust", kind = "Natural", rarity = "Free", slots = ALL,
		desc = "A faint wake of trail dust.",
		look = {
			{ type = "particles", texture = TEX.smoke, color = { rgb(150, 132, 108), rgb(170, 160, 146) }, size = { 0.35, 1.1 },
				alpha = { 0.72, 1 }, rate = 25, life = { 0.5, 0.8 }, speed = { 0.2, 0.6 }, drag = 2, spread = 180, light = 0 },
		} },
	{ id = "thistledown", name = "Thistledown", kind = "Natural", rarity = "Common", slots = SHOTS,
		desc = "Seed fluff drifting off the line.",
		look = {
			{ type = "trail", color = { rgb(246, 244, 236) }, width = 0.05, life = 0.3, alpha = { 0.35, 1 }, light = 0.2 },
			{ type = "particles", texture = TEX.sparkle, color = { rgb(250, 248, 240) }, size = { 0.22, 0.12 },
				alpha = { 0.2, 1 }, rate = 24, life = { 0.9, 1.4 }, speed = { 0.3, 0.7 }, drag = 3, accel = Vector3.new(0, -0.6, 0),
				spread = 180, light = 0.3, rotSpeed = 60 },
		} },
	{ id = "neon_thread", name = "Neon Thread", kind = "Bright", rarity = "Common", slots = ALL,
		desc = "A thin, sharp line of magenta light.",
		look = {
			{ type = "trail", color = { rgb(255, 64, 196), rgb(255, 120, 220) }, width = 0.08, life = 0.3, alpha = { 0, 1 },
				light = 1, bright = 3, swingSpan = 0.12 },
			{ type = "trail", color = { rgb(255, 64, 196) }, width = 0.3, life = 0.22, alpha = { 0.8, 1 }, light = 1, bright = 1.5,
				swingSpan = 0.3 },
		} },
	{ id = "hardline", name = "Hardline", kind = "Bright", rarity = "Common", slots = ALL,
		desc = "A white-hot core inside a blue edge.",
		look = {
			{ type = "trail", color = { rgb(235, 245, 255) }, width = 0.07, life = 0.24, alpha = { 0, 1 }, light = 1, bright = 3,
				swingSpan = 0.1 },
			{ type = "trail", color = { rgb(70, 150, 255) }, width = 0.32, life = 0.26, alpha = { 0.55, 1 }, light = 1, bright = 2,
				swingSpan = 0.55 },
		} },
	{ id = "haze_line", name = "Haze Line", kind = "Bright", rarity = "Common", slots = ALL,
		desc = "A thin cyan line in a faint haze.",
		look = {
			{ type = "trail", color = { rgb(60, 220, 235) }, width = 0.06, life = 0.3, alpha = { 0.05, 1 }, light = 1, bright = 2.5,
				swingSpan = 0.1 },
			{ type = "trail", color = { rgb(60, 220, 235), rgb(40, 120, 160) }, width = 0.7, life = 0.32, alpha = { 0.86, 1 },
				light = 1, bright = 1, swingSpan = 0.9 },
		} },
	{ id = "leafwake", name = "Leafwake", kind = "Natural", rarity = "Rare", slots = ALL,
		desc = "Green leaves and soft light, like the valley's wind.",
		look = {
			{ type = "trail", color = { rgb(150, 176, 92), rgb(214, 190, 112) }, width = 0.2, life = 0.28, alpha = { 0.35, 1 },
				light = 0.4, swingSpan = 0.6 },
			{ type = "particles", texture = TEX.shard, color = { rgb(108, 140, 72), rgb(214, 190, 112) }, size = { 0.2, 0.14 },
				alpha = { 0, 1 }, rate = 30, life = { 0.6, 1.0 }, speed = { 0.6, 1.4 }, drag = 2.5, accel = Vector3.new(0, -2.5, 0),
				spread = 180, rot = { 0, 360 }, rotSpeed = 220, light = 0 },
		} },
	{ id = "ember_drift", name = "Ember Drift", kind = "Natural", rarity = "Rare", slots = ALL,
		desc = "Embers that fall off the line and cool to grey.",
		look = {
			{ type = "trail", color = { rgb(255, 140, 60), rgb(150, 70, 30) }, width = 0.1, life = 0.2, alpha = { 0.4, 1 },
				light = 0.6, bright = 1.2, swingSpan = 0.35 },
			{ type = "particles", texture = TEX.sparks, color = { rgb(255, 150, 60), rgb(120, 110, 100) }, size = { 0.18, 0.06 },
				alpha = { 0, 1 }, rate = 34, life = { 0.6, 1.1 }, speed = { 0.5, 1.6 }, drag = 1.5, accel = Vector3.new(0, -8, 0),
				spread = 180, light = 0.7 },
		} },
	{ id = "kindle", name = "Kindle", kind = "Bright", rarity = "Rare", slots = ALL,
		desc = "Soft puffs of flame, orange to yellow.",
		look = {
			{ type = "particles", texture = TEX.fire, color = { rgb(255, 210, 90), rgb(255, 110, 40) }, size = { 0.7, 0 },
				alpha = { 0.15, 1 }, rate = 40, life = { 0.25, 0.4 }, speed = { 0.4, 1.2 }, drag = 2, accel = Vector3.new(0, 3, 0),
				spread = 180, rot = { 0, 360 }, rotSpeed = 90, light = 0.8, bright = 1.5 },
			{ type = "trail", color = { rgb(255, 196, 80), rgb(255, 120, 40) }, width = 0.14, life = 0.16, alpha = { 0.3, 1 },
				light = 1, bright = 1.5, swingSpan = 0.4 },
		} },
	{ id = "frostbreath", name = "Frostbreath", kind = "Natural", rarity = "Rare", slots = { swing = true, arrow = true },
		desc = "White mist with a cold glint.",
		look = {
			{ type = "particles", texture = TEX.smoke, color = { rgb(230, 240, 250) }, size = { 0.4, 1.3 }, alpha = { 0.6, 1 },
				rate = 30, life = { 0.5, 0.9 }, speed = { 0.2, 0.6 }, drag = 2, spread = 180, light = 0.1 },
			{ type = "particles", texture = TEX.sparkle, color = { rgb(220, 240, 255) }, size = { 0.16, 0 }, alpha = { 0.1, 1 },
				rate = 10, life = { 0.4, 0.7 }, speed = { 0.2, 0.5 }, spread = 180, light = 0.8 },
		} },
	{ id = "pulse", name = "Pulse", kind = "Bright", rarity = "Rare", slots = ALL,
		desc = "A pale line that beats along its length.",
		look = {
			{ type = "trail", color = { rgb(220, 250, 255), rgb(120, 220, 240) }, width = 0.12, life = 0.36, light = 1, bright = 2.5,
				bands = 4, swingSpan = 0.3 },
			{ type = "trail", color = { rgb(120, 220, 240) }, width = 0.45, life = 0.3, alpha = { 0.85, 1 }, light = 1, bright = 1,
				swingSpan = 0.6 },
		} },
	{ id = "glowworm", name = "Glowworm", kind = "Bright", rarity = "Rare", slots = SHOTS,
		desc = "Green swirls that brighten to yellow at the head.",
		look = {
			{ type = "trail", color = { rgb(250, 240, 120), rgb(80, 220, 80) }, width = 0.14, life = 0.22, alpha = { 0.1, 1 },
				light = 1, bright = 2 },
			{ type = "particles", texture = TEX.sparkle, color = { rgb(240, 255, 120), rgb(60, 200, 70) }, size = { 0.5, 0.15 },
				alpha = { 0, 1 }, rate = 50, life = { 0.4, 0.7 }, speed = { 1, 2 }, drag = 3, spread = 180, rot = { 0, 360 },
				rotSpeed = 300, light = 1, bright = 1.5, spin = 10 },
		} },
	{ id = "forked_light", name = "Forked Light", kind = "Bright", rarity = "Epic", slots = SHOTS,
		desc = "White-blue lightning crackling along the flight.",
		look = {
			{ type = "bolt", color = rgb(200, 230, 255), width = 0.24, jag = 0.6, length = 3.4, every = 0.05 },
			{ type = "trail", color = { rgb(240, 248, 255), rgb(120, 170, 255) }, width = 0.1, life = 0.3, alpha = { 0, 1 },
				light = 1, bright = 3 },
			{ type = "particles", texture = TEX.sparkle, color = { rgb(220, 236, 255) }, size = { 0.3, 0 }, alpha = { 0, 1 },
				rate = 30, life = { 0.15, 0.3 }, speed = { 2, 5 }, spread = 180, light = 1, bright = 2 },
		} },
	{ id = "shardfall", name = "Shardfall", kind = "Bright", rarity = "Epic", slots = SHOTS,
		desc = "Small crimson shards tumbling off the line.",
		look = {
			{ type = "trail", color = { rgb(220, 30, 60), rgb(150, 10, 40) }, width = 0.08, life = 0.3, alpha = { 0.1, 1 },
				light = 0.8, bright = 1.5 },
			{ type = "particles", texture = TEX.shard, color = { rgb(235, 40, 70), rgb(170, 20, 50) }, size = { 0.38, 0.12 },
				alpha = { 0, 1 }, rate = 36, life = { 0.5, 0.9 }, speed = { 0.8, 2 }, drag = 2, accel = Vector3.new(0, -3, 0),
				spread = 180, rot = { 0, 360 }, rotSpeed = 200, light = 0.5 },
			{ type = "particles", texture = TEX.sparkle, color = { rgb(255, 255, 255) }, size = { 0.14, 0 }, alpha = { 0, 1 },
				rate = 12, life = { 0.3, 0.5 }, speed = { 0.5, 1.5 }, spread = 180, light = 1 },
		} },
	{ id = "wishing_stars", name = "Wishing Stars", kind = "Bright", rarity = "Epic", slots = ALL,
		desc = "Gold stars that shrink and fade.",
		look = {
			{ type = "particles", texture = TEX.sparkle, color = { rgb(255, 230, 120), rgb(255, 200, 70) }, size = { 0.8, 0 },
				alpha = { 0, 1 }, rate = 32, life = { 0.45, 0.7 }, speed = { 0.2, 0.8 }, drag = 2, spread = 180, rot = { 0, 360 },
				rotSpeed = 120, light = 1, bright = 2 },
			{ type = "trail", color = { rgb(255, 236, 160), rgb(255, 210, 90) }, width = 0.12, life = 0.25, alpha = { 0.4, 1 },
				light = 1, bright = 1.5, swingSpan = 0.3 },
		} },
	{ id = "nebula", name = "Nebula", kind = "Bright", rarity = "Epic", slots = ALL,
		desc = "A wavering violet band.",
		look = {
			{ type = "trail", color = { rgb(190, 130, 255), rgb(120, 60, 230) }, width = 0.34, life = 0.32, alpha = { 0.15, 1 },
				light = 1, bright = 2, texture = TEX.noise, texLen = 1.6, swingSpan = 0.5 },
			{ type = "trail", color = { rgb(150, 80, 255) }, width = 0.9, life = 0.36, alpha = { 0.84, 1 }, light = 1, bright = 1,
				swingSpan = 1 },
			{ type = "particles", texture = TEX.glow, color = { rgb(170, 100, 255) }, size = { 0.5, 0.9 }, alpha = { 0.6, 1 },
				rate = 16, life = { 0.3, 0.5 }, speed = { 0.3, 0.8 }, spread = 180, rot = { 0, 360 }, rotSpeed = 60, light = 1 },
		} },
	{ id = "comet", name = "Comet", kind = "Bright", rarity = "Legendary", slots = { arrow = true },
		desc = "A bright blue head and a long cyan plume.",
		look = {
			{ type = "particles", texture = TEX.sparkle, color = { rgb(230, 248, 255), rgb(90, 190, 255) }, size = { 1.2, 0.2 },
				alpha = { 0, 1 }, rate = 60, life = { 0.12, 0.2 }, speed = { 0, 0.3 }, spread = 180, rot = { 0, 360 },
				rotSpeed = 200, light = 1, bright = 2.5, locked = true },
			{ type = "trail", color = { rgb(200, 240, 255), rgb(40, 120, 255) }, width = 0.55, life = 0.45, alpha = { 0.1, 1 },
				light = 1, bright = 2.5 },
			{ type = "particles", texture = TEX.glow, color = { rgb(80, 180, 255) }, size = { 0.6, 1.2 }, alpha = { 0.55, 1 },
				rate = 30, life = { 0.3, 0.5 }, speed = { 0.4, 1.2 }, drag = 2, spread = 180, rot = { 0, 360 }, rotSpeed = 90, light = 1 },
		} },
	{ id = "molten", name = "Molten", kind = "Bright", rarity = "Legendary", slots = { swing = true, throw = true },
		desc = "A heavy orange-white flame with drifting sparks.",
		look = {
			{ type = "trail", color = { rgb(255, 250, 220), rgb(255, 130, 30) }, width = 0.4, life = 0.22, alpha = { 0, 1 },
				light = 1, bright = 2.5, swingSpan = 0.85 },
			{ type = "particles", texture = TEX.fire, color = { rgb(255, 200, 90), rgb(255, 90, 20) }, size = { 0.9, 0.1 },
				alpha = { 0.1, 1 }, rate = 40, life = { 0.25, 0.45 }, speed = { 0.8, 2 }, accel = Vector3.new(0, 6, 0),
				spread = 180, rot = { 0, 360 }, rotSpeed = 120, light = 0.9, bright = 1.5 },
			{ type = "particles", texture = TEX.sparks, color = { rgb(255, 220, 140) }, size = { 0.16, 0.04 }, alpha = { 0, 1 },
				rate = 20, life = { 0.5, 0.9 }, speed = { 2, 5 }, drag = 1, accel = Vector3.new(0, -6, 0), spread = 180, light = 1 },
		} },
	-- Season one's two trails (CardMenusAndShop.md 3.1): earned on the Season Track, never sold (`earned` names where;
	-- TrailService.buy refuses them, SeasonService grants them through TrailService.grant)
	{ id = "resin", name = "Resin", kind = "Natural", rarity = "Common", slots = ALL, earned = "Season Track · free tier 10",
		desc = "A warm amber ribbon with a light core.",
		look = {
			{ type = "trail", color = { rgb(250, 226, 170) }, width = 0.06, life = 0.22, alpha = { 0.1, 1 }, light = 0.4,
				swingSpan = 0.15 },
			{ type = "trail", color = { rgb(214, 150, 64), rgb(150, 96, 40) }, width = 0.24, life = 0.26, alpha = { 0.45, 1 },
				light = 0.3, swingSpan = 0.6 },
		} },
	{ id = "gold_dust", name = "Gold Dust", kind = "Natural", rarity = "Legendary", slots = ALL,
		earned = "Season Track · premium tier 45",
		desc = "A soft gold ribbon with a slow drift of motes.",
		look = {
			{ type = "trail", color = { rgb(236, 206, 132), rgb(190, 150, 80) }, width = 0.2, life = 0.3, alpha = { 0.35, 1 },
				light = 0.5, swingSpan = 0.6 },
			{ type = "particles", texture = TEX.sparkle, color = { rgb(240, 214, 140) }, size = { 0.16, 0.04 }, alpha = { 0.2, 1 },
				rate = 16, life = { 0.8, 1.3 }, speed = { 0.1, 0.4 }, drag = 2, accel = Vector3.new(0, -0.4, 0), spread = 180,
				light = 0.4 },
		} },
}

Trails.ById = {}
for i, def in ipairs(Trails.list) do
	def.order = i
	def.price = Trails.PRICES[def.rarity] or 0
	Trails.ById[def.id] = def
end

-- Free ones (Config.Trails.Free may add to the rarity rule; never makes a priced trail free by accident)
local FREE = {}
for _, def in ipairs(Trails.list) do
	if def.rarity == "Free" then
		FREE[def.id] = true
	end
end
for _, id in ipairs(cfg.Free or {}) do
	if Trails.ById[id] then
		FREE[id] = true
		Trails.ById[id].price = 0
	end
end

function Trails.get(id: any)
	return if type(id) == "string" then Trails.ById[id] else nil
end

function Trails.isFree(id: any): boolean
	return type(id) == "string" and FREE[id] == true
end

-- Where an earned-only trail comes from ("Season Track · free tier 10"), or nil for the trails the shop sells
function Trails.earnedFrom(id: any): string?
	local def = Trails.get(id)
	return if def and type(def.earned) == "string" then def.earned else nil
end

function Trails.price(id: any): number
	local def = Trails.get(id)
	return if def then def.price else 0
end

-- "none" fits every slot (no trail at all)
function Trails.fits(id: any, slot: any): boolean
	if id == "none" then
		return Trails.ATTR[slot] ~= nil
	end
	local def = Trails.get(id)
	return def ~= nil and def.slots[slot] == true
end

-- Which slot a shot or a swing uses: arrows "arrow", any thrown item "throw", everything else "swing".
function Trails.slotFor(itemId: string?, kind: string?): string
	if kind == "swing" then
		return "swing"
	end
	if itemId == "arrow" then
		return "arrow"
	end
	return if kind == "shot" then "throw" else "swing"
end

return Trails
