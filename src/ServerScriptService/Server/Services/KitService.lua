--[[
	KitService - the free basic kits (docs/design/Weapons_v2.md section 3; the owner, 18 Nov: "a basic weapons list
	(like kits the players can choose where its sth basic like an arrow some apples etc) that spawns in the half point
	of the game"). Shared.Kits holds the five kits and the numbers.

	THE PICK
	  Remote KitPick(kitId) from the lobby (KitController): the player's kit for their next round. Player attribute
	  Kit = the kit id, set at join (the remembered one, else Kits.Settings.Default). Remembered for the session, and
	  between sessions in DataService's Econ.LastKit. The kit of a round is taken at its call (RoundService.
	  roundStarting): a pick after that counts for the next round.
	  KitPick("bring", weaponId | "") picks the owned weapon to bring (Weapons_v2 2.6; Econ.Bring; player attribute
	  KitBring): it replaces the kit's weapon in the drop (Medic: added), at its Armoury stars. Player attribute
	  KitArmoury = "id:stars,..." lists the owned weapons KitController cycles through (refreshed at join, on a
	  bring pick and after each round).
	  KitPick stays accepted for one version (an old client); the Loadout screen sends LoadoutSet instead.

	THE LOADOUT (docs/design/Combat_v3.md section 3.2; LoadoutController; Shared.LoadoutCatalog)
	  Remote LoadoutSet { kit, bring, specialty, general, trails = { swing, arrow, throw } }: one save when the Loadout
	  screen closes. Each value is checked (the kit exists; the weapon is in the Armoury and may be brought; the
	  Specialty and the general skill exist; each trail fits its slot and is free or owned); a bad value keeps the old one.
	  Player attributes (what the round's code reads):
	    LoadoutSpecialty, LoadoutGeneral        the next round's choice (family id, general skill id)
	    RoundSpecialty, RoundGeneral            locked at the call (RoundService.roundStarting) for that round's contenders
	  The three trails go to TrailService.setLoadout (it owns TrailSwing / TrailArrow / TrailThrow, TrailsOwned and
	  Econ.Trails; never locked: free to change in the train). Without TrailService they are kept for the session here.
	  Remembered in Econ.Loadout = { specialty, general } (DataService keeps it once its sanitizeEcon knows the key;
	  until then for the session only).

	DELIVERY (Kits.Settings.Delivery; Config.Kits.Delivery overrides it: the one-line switch)
	  "Start"     at the horn (RoundService.roundStarted) the kit goes into the bag; what does not fit lands at the feet.
	  "Midpoint"  the middle of the round: the earlier of half the round's length and the moment MidpointShare of the
	              round's contenders are out, never before MinTime (scaled with Studio's StudioTimeScale); practice
	              rounds at PracticeTime. Then for each alive contender, spread over 0..Stagger s:
	    1. WarningLead s before the landing the player alone gets the attribute KitIncoming = { landing server time }
	       (KitController: a soft two-note chime and one thin line "Your kit is coming"); the spot is picked now.
	    2. The parcel (Model "KitParcel", tag KitParcel, attributes OwnerUserId, LandAt, DropHeight, FallTime) appears
	       FallTime s before LandAt at its landing spot; every client draws it falling from DropHeight under its
	       ember-and-charcoal chute (KitController), so the server moves nothing. Persistent streaming: the falling
	       chute is seen from far away.
	    3. At LandAt: a soft thump, a puff of dust, the chute folds beside it, a thin pale smoke ribbon for SmokeTime s,
	       and its Open prompt enables.
	  The spot: dry, walkable ground LandMin..LandMax studs from where the player stands (from the foot of the tree or
	  wall they are on; the nearest dry bank within WaterSearch if they swim; off the Horn's platform onto the turf),
	  at least BorderClearance inside the ring as it will be, open to the sky (never under a crown or the Horn's sails),
	  never on a player. It searches outward in rings until clear.
	OPENING (anyone can steal it)
	  The owner holds E for OwnerOpenTime, anyone else for OtherOpenTime (the server times every hold). Its items spill
	  beside it like a crate's (LootService.openFixed), with Take all for the opener. A dead owner's parcel still lands
	  (if the warning had been given) as loot for anyone. No drop for someone already out at the midpoint.
	Every kit weapon has 1 star. Studio: GameState attribute KitDropNow = true starts the midpoint drop at once (tests).

	API
	  KitService.getKit(player) -> kitId
	  KitService.setKit(player, kitId) -> boolean
	  KitService.deliveryMode() -> "Midpoint" | "Start"
	  KitService.delivered: Signal(player, kitId, parcel?)   a parcel was dropped (or, "Start", the kit given)
]]
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Kits = require(Shared:WaitForChild("Kits"))
local LoadoutCatalog = require(Shared:WaitForChild("LoadoutCatalog"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local Util = require(Shared:WaitForChild("Util"))
local WeaponLooks = require(Shared:WaitForChild("WeaponLooks"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local S = Kits.Settings

local KitService = {}
KitService.delivered = Signal.new()

local PARCEL_TAG = "KitParcel"
local PROMPT_TAG = "LootPrompt"
local REMOTE = "KitPick"
local LOADOUT_REMOTE = "LoadoutSet"

local Services: { [string]: any } = {}
local rng = Random.new()
local picks: { [Player]: string } = {}
local roundKits: { [Player]: string } = {} -- taken at the call
local loadouts: { [Player]: any } = {} -- LoadoutCatalog.sanitize shape: specialty, general, trails
local roundToken = 0
local midpointDone = false

-- canvas, cord and ember (Weapons_v2 1.4: never silver)
local CANVAS = Color3.fromRGB(176, 174, 166)
local TUBE = Color3.fromRGB(226, 224, 216)
local CORD = Color3.fromRGB(112, 96, 74)
local EMBER = Color3.fromRGB(184, 82, 40)
local CHARCOAL = Color3.fromRGB(46, 44, 44)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function call(serviceName: string, method: string, ...): any
	local service = Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[KitService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function isAlive(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end
	local alive = call("PlayerService", "isAlive", player)
	if alive == nil then
		alive = player:GetAttribute("Alive") == true
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return alive == true and humanoid ~= nil and humanoid.Health > 0
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function KitService.deliveryMode(): string
	return if S.Delivery == "Start" then "Start" else "Midpoint"
end

--------------------------------------------------------------------------------------------------------------------
-- The pick
--------------------------------------------------------------------------------------------------------------------

function KitService.getKit(player: Player): string
	local id = picks[player]
	return if Kits.get(id) then id :: string else Kits.default().id
end

function KitService.setKit(player: Player, kitId: any): boolean
	local kit = Kits.get(kitId)
	if not kit then
		return false
	end
	picks[player] = kit.id
	if player.Parent == Players then
		player:SetAttribute("Kit", kit.id)
	end
	-- remembered between sessions in the profile's Econ.LastKit (DataService; refused until the profile has loaded)
	call("DataService", "updateEcon", player, function(econ)
		econ.LastKit = kit.id
	end)
	return true
end

-- The owned weapon a player brings (Weapons_v2 2.6): an id in their Armoury, or "" for the kit's own weapon. It
-- replaces the kit's weapon in the midpoint drop (Medic: it is added). Never the Recurve Bow.
local function armouryOf(player: Player): { [string]: number }
	local econ = call("DataService", "getEcon", player)
	return if type(econ) == "table" and type(econ.Armoury) == "table" then econ.Armoury else {}
end

function KitService.setBring(player: Player, weaponId: any): boolean
	local id = if type(weaponId) == "string" then weaponId else ""
	if id ~= "" then
		local def = ItemDefs.get(id)
		if not def or not def.starred or def.neverOwned or not armouryOf(player)[id] then
			return false
		end
	end
	player:SetAttribute("KitBring", id)
	call("DataService", "updateEcon", player, function(econ)
		econ.Bring = id
	end)
	return true
end

-- The Armoury's ids as a sorted list on the player (KitController cycles BRING through them).
local function publishArmoury(player: Player)
	local ids = {}
	for id, stars in pairs(armouryOf(player)) do
		local def = ItemDefs.get(id)
		if def and def.starred and not def.neverOwned then
			table.insert(ids, id .. ":" .. tostring(stars))
		end
	end
	table.sort(ids)
	player:SetAttribute("KitArmoury", table.concat(ids, ","))
end

-- RewardsService calls this on every state push, so a weapon won on the wheel joins the BRING cycle at once.
function KitService.refreshArmoury(player: Player)
	if player.Parent == Players then
		publishArmoury(player)
	end
end

-- The parcel brings the owned weapon (itemsFor reads Econ.Bring): RewardsService's own fallback stays off.
KitService.deliversOwnedWeapon = true

local function onPick(player: Player, kitId: any, bring: any)
	if not Net.rateLimit(player, REMOTE, 4, 6) then
		return
	end
	if kitId == "bring" then
		publishArmoury(player)
		KitService.setBring(player, bring)
	else
		KitService.setKit(player, kitId)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The Loadout (Combat_v3 3.2): kit, bring, Specialty, general skill and trails in one LoadoutSet
--------------------------------------------------------------------------------------------------------------------

-- Trails belong to TrailService (Shared.Trails; Econ.Trails; the TrailSwing / TrailArrow / TrailThrow and TrailsOwned
-- attributes). The Loadout only forwards the three slots to it. Without TrailService, this keeps them for the session.
local function trailService(): any
	local service = Services.TrailService
	return if service and type(service.setLoadout) == "function" then service else nil
end

local function ownsTrail(player: Player, id: string): boolean
	local service = trailService()
	if service then
		return call("TrailService", "owns", player, id) == true
	end
	return LoadoutCatalog.isFreeTrail(id)
end

local function equippedTrails(player: Player, fallback: any): { [string]: string }
	local out = {}
	for _, slot in ipairs(LoadoutCatalog.Slots) do
		local attr = player:GetAttribute(LoadoutCatalog.SlotAttr[slot])
		out[slot] = if type(attr) == "string" and attr ~= "" then attr else fallback[slot]
	end
	return out
end

local function publishLoadout(player: Player)
	if player.Parent ~= Players then
		return
	end
	local l = loadouts[player] or LoadoutCatalog.defaults(KitService.getKit(player))
	player:SetAttribute("LoadoutSpecialty", l.specialty)
	player:SetAttribute("LoadoutGeneral", l.general)
	if not trailService() then
		for _, slot in ipairs(LoadoutCatalog.Slots) do
			player:SetAttribute(LoadoutCatalog.SlotAttr[slot], l.trails[slot])
		end
	end
end

function KitService.getLoadout(player: Player)
	local l = loadouts[player] or LoadoutCatalog.defaults(KitService.getKit(player))
	return { specialty = l.specialty, general = l.general, trails = equippedTrails(player, l.trails) }
end

-- Sets what a LoadoutSet carries; anything invalid keeps the player's current value. Returns the clean loadout.
function KitService.setLoadout(player: Player, payload: any)
	local p = if type(payload) == "table" then payload else {}
	if p.kit ~= nil and Kits.get(p.kit) and p.kit ~= KitService.getKit(player) then
		KitService.setKit(player, p.kit)
	end
	if p.bring ~= nil and type(p.bring) == "string" and p.bring ~= (player:GetAttribute("KitBring") or "") then
		publishArmoury(player)
		KitService.setBring(player, p.bring)
	end
	local current = KitService.getLoadout(player)
	local clean = {
		specialty = if LoadoutCatalog.specialty(p.specialty) then p.specialty else current.specialty,
		general = if LoadoutCatalog.general(p.general) then p.general else current.general,
		trails = table.clone(current.trails),
	}
	if type(p.trails) == "table" then
		local wanted = {}
		for _, slot in ipairs(LoadoutCatalog.Slots) do
			local id = p.trails[slot]
			if type(id) == "string" and #id <= 24 and id ~= current.trails[slot] then
				wanted[slot] = id
			end
		end
		if next(wanted) then
			if trailService() then
				call("TrailService", "setLoadout", player, wanted) -- each checked there; a bad one is left as it was
				clean.trails = equippedTrails(player, current.trails)
			else
				for slot, id in pairs(wanted) do
					if LoadoutCatalog.trailFits(id, slot) and ownsTrail(player, id) then
						clean.trails[slot] = id
					end
				end
			end
		end
	end
	loadouts[player] = clean
	publishLoadout(player)
	-- (integrate, 20 Nov) the saved loadout cards: up to 4, each value checked against the catalogue, kept in
	-- Econ.Loadout.saved / slot and published as LoadoutSaved (JSON) and LoadoutSlot for the Loadout screen
	local savedList, slot = nil, nil
	if type(p.saved) == "table" then
		savedList = {}
		for i = 1, 4 do
			local s = p.saved[i]
			if type(s) ~= "table" then
				break
			end
			local kit = if Kits.get(s.kit) then s.kit else KitService.getKit(player)
			local c = LoadoutCatalog.sanitize(s, function(id)
				return ownsTrail(player, id)
			end, kit)
			savedList[i] = { name = if type(s.name) == "string" then string.sub(s.name, 1, 20) else nil, kit = kit,
				bring = if type(s.bring) == "string" and #s.bring <= 32 then s.bring else "",
				specialty = c.specialty, general = c.general,
				trails = { swing = c.trails.swing, arrow = c.trails.arrow, throw = c.trails.throw } }
		end
	end
	if type(p.slot) == "number" and p.slot == p.slot then
		slot = math.clamp(math.floor(p.slot), 1, 4)
	end
	call("DataService", "updateEcon", player, function(econ)
		local before = if type(econ.Loadout) == "table" then econ.Loadout else {}
		econ.Loadout = { specialty = clean.specialty, general = clean.general, saved = savedList or before.saved,
			slot = slot or before.slot }
	end)
	if savedList then
		KitService.publishSaved(player, savedList, slot)
	end
	return clean
end

-- LoadoutSaved (JSON list of the saved cards) and LoadoutSlot (the selected one) for the Loadout screen
function KitService.publishSaved(player: Player, list: any, slot: number?)
	if player.Parent ~= Players or type(list) ~= "table" or #list == 0 then
		return
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, list)
	if ok and #json < 4000 then
		player:SetAttribute("LoadoutSaved", json)
	end
	if slot then
		player:SetAttribute("LoadoutSlot", slot)
	end
end

local function onLoadoutSet(player: Player, payload: any)
	if not Net.rateLimit(player, LOADOUT_REMOTE, 2, 4) then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	KitService.setLoadout(player, payload)
end

local function loadPick(player: Player)
	-- the profile loads after join: look for a saved kit for a while
	for _ = 1, 30 do
		if player.Parent ~= Players or picks[player] ~= nil then
			break
		end
		if call("DataService", "isLoaded", player) == true then
			local econ = call("DataService", "getEcon", player)
			local kit = type(econ) == "table" and Kits.get(econ.LastKit)
			if kit then
				picks[player] = kit.id
			end
			if type(econ) == "table" and type(econ.Bring) == "string" then
				player:SetAttribute("KitBring", econ.Bring)
			end
			if type(econ) == "table" and type(econ.Loadout) == "table" and loadouts[player] == nil then
				loadouts[player] = LoadoutCatalog.sanitize(econ.Loadout, nil, KitService.getKit(player))
			end
			if type(econ) == "table" and type(econ.Loadout) == "table" and type(econ.Loadout.saved) == "table" then
				KitService.publishSaved(player, econ.Loadout.saved, econ.Loadout.slot)
			end
			break
		end
		task.wait(1)
	end
	if player.Parent == Players then
		player:SetAttribute("Kit", KitService.getKit(player))
		publishArmoury(player)
		publishLoadout(player)
	end
end

-- The kit's items for this player: the kit, with their brought owned weapon in place of its weapon.
local function itemsFor(player: Player, kit: any): { { id: string, count: number, stars: number? } }
	local items = {}
	local bring = player:GetAttribute("KitBring")
	local owned = if type(bring) == "string" and bring ~= "" then armouryOf(player)[bring] else nil
	local bringDef = owned and ItemDefs.get(bring)
	if bringDef and (not bringDef.starred or bringDef.neverOwned) then
		bringDef = nil
	end
	local replaced = false
	for _, item in ipairs(kit.items) do
		local def = ItemDefs.get(item.id)
		if bringDef and not replaced and def and def.starred then
			replaced = true
			table.insert(items, { id = bringDef.id, count = 1, stars = math.clamp(math.floor(owned), 1, 5) })
		else
			table.insert(items, { id = item.id, count = item.count, stars = if def and def.starred then 1 else nil })
		end
	end
	if bringDef and not replaced then
		table.insert(items, 1, { id = bringDef.id, count = 1, stars = math.clamp(math.floor(owned), 1, 5) })
	end
	-- an owned Short Bow comes with 6 arrows (Weapons_v2 2.6)
	if bringDef and bringDef.kind == "Bow" then
		local hasArrows = false
		for _, item in ipairs(items) do
			if item.id == "arrow" then
				hasArrows = true
			end
		end
		if not hasArrows then
			table.insert(items, { id = "arrow", count = 6 })
		end
	end
	return items
end

--------------------------------------------------------------------------------------------------------------------
-- Giving at the start
--------------------------------------------------------------------------------------------------------------------

local function giveNow(player: Player, kit: any)
	local root = rootOf(player)
	for _, item in ipairs(itemsFor(player, kit)) do
		local added = tonumber(call("InventoryService", "give", player, item.id, item.count, item.stars)) or 0
		local left = item.count - added
		if left > 0 and root then
			call("LootService", "spawnGroundItem", item.id, left, root.Position + Vector3.new(rng:NextNumber(-2, 2), 1, rng:NextNumber(-2, 2)), nil, item.stars)
		end
	end
	KitService.delivered:Fire(player, kit.id, nil)
end

--------------------------------------------------------------------------------------------------------------------
-- The landing spot
--------------------------------------------------------------------------------------------------------------------

local function excludeList(): { Instance }
	local list: { Instance } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	local items = loot and loot:FindFirstChild("Items")
	if items then
		table.insert(list, items)
	end
	for _, dummy in ipairs(CollectionService:GetTagged("TrainingDummy")) do
		table.insert(list, dummy)
	end
	return list
end

local function groundParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList()
	params.IgnoreWater = false
	params.RespectCanCollide = false -- canopies and sails are often not solid, but they still hide the sky
	return params
end

local function solidParams(): RaycastParams
	local params = groundParams()
	params.RespectCanCollide = true
	return params
end

-- The ground under a point (solid geometry and terrain; water counts so we can refuse it).
local function groundBelow(position: Vector3, params: RaycastParams): RaycastResult?
	return workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -220, 0), params)
end

-- The ring as it will be when the parcel lands: its centre and the radius to stay inside.
local function safeRing(): (Vector3, number)
	local center = GameState:GetAttribute("BorderCenter")
	local radius = tonumber(GameState:GetAttribute("BorderRadius"))
	local target = tonumber(GameState:GetAttribute("BorderTargetRadius"))
	if typeof(center) ~= "Vector3" then
		center = Vector3.zero
	end
	radius = radius or tonumber(GameState:GetAttribute("BorderStartRadius")) or 1000
	if target and GameState:GetAttribute("BorderMoving") == true then
		radius = math.min(radius, target)
	end
	return center :: Vector3, (radius :: number) - (S.BorderClearance or 30)
end

local function insideRing(p: Vector3, center: Vector3, r: number): boolean
	return Util.flat(p - center).Magnitude <= r
end

-- Is `spot` (a ground hit) a good landing: dry, gentle, open to the sky from DropHeight, no player on it?
local function goodSpot(hit: RaycastResult?, skyParams: RaycastParams, center: Vector3, r: number): boolean
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.82 then
		return false
	end
	local p = hit.Position
	if not insideRing(p, center, r) then
		return false
	end
	-- open sky: the first thing straight down from the drop height is this ground (no crown, sail or roof over it)
	local top = p + Vector3.new(0, S.DropHeight or 140, 0)
	local sky = workspace:Raycast(top, Vector3.new(0, -(S.DropHeight or 140) - 2, 0), skyParams)
	if not sky or (sky.Position - p).Magnitude > 1.5 then
		return false
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local root = rootOf(other)
		if root and (root.Position - p).Magnitude < 5 then
			return false
		end
	end
	for _, parcel in ipairs(CollectionService:GetTagged(PARCEL_TAG)) do
		if parcel:IsA("Model") and (parcel:GetPivot().Position - p).Magnitude < 6 then
			return false
		end
	end
	-- (wave 27 bug hunt) a practice dummy: the rays above see through it (excludeList) and its stand's platform is solid
	-- ground to them, so a parcel landed on the stand, inside the dummy's legs. Keep a dummy's width away (and its
	-- stand's: the stand stays in CombatService's TrainingDummies folder while a broken dummy respawns).
	local standing = CollectionService:GetTagged("TrainingDummy")
	local folder = workspace:FindFirstChild("TrainingDummies")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			table.insert(standing, child)
		end
	end
	for _, dummy in ipairs(standing) do
		if dummy:IsA("Model") and Util.flat(dummy:GetPivot().Position - p).Magnitude < 5 then
			return false
		end
	end
	return true
end

-- Where to search from: the player's feet; the foot of the tree or wall; off the Horn's platform; the bank of water.
local function searchOrigin(player: Player, solid: RaycastParams): Vector3?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local p = root.Position
	local hit = groundBelow(p, solid)
	if hit then
		p = hit.Position
	end
	-- on the Horn's deck: search from the platform's edge outward
	local hornRadius = ItemDefs.BowBudget.hornRadius or 120
	local d = ArenaLayout.flatDistance(p)
	if hit and hit.Instance and not hit.Instance:IsA("Terrain") and d < hornRadius then
		local out = Util.flat(p)
		out = if out.Magnitude > 1 then out.Unit else Vector3.xAxis
		local edge = out * math.min(hornRadius * 0.6, d + 30)
		local floor = groundBelow(Vector3.new(edge.X, p.Y + 40, edge.Z), solid)
		if floor then
			p = floor.Position
		end
	end
	return p
end

local function findSpot(player: Player): Vector3?
	local solid = solidParams()
	local sky = groundParams()
	local origin = searchOrigin(player, solid)
	if not origin then
		return nil
	end
	local center, r = safeRing()
	-- outside or near the border: search from 30 studs inside the ring, on the line to the player
	if not insideRing(origin, center, r) then
		local dir = Util.flat(origin - center)
		dir = if dir.Magnitude > 1 then dir.Unit else Vector3.xAxis
		local inward = center + dir * math.max(0, r - (S.LandMax or 25))
		local hit = groundBelow(Vector3.new(inward.X, origin.Y + 80, inward.Z), solid)
		origin = if hit then hit.Position else Vector3.new(inward.X, origin.Y, inward.Z)
	end
	local lo, hi = S.LandMin or 15, S.LandMax or 25
	local start = rng:NextNumber(0, math.pi * 2)
	-- the wanted band first, then rings further out (up to WaterSearch beyond it: a swimmer's nearest bank)
	local rings = { lo, (lo + hi) / 2, hi }
	local far = hi + (S.WaterSearch or 60)
	local step = hi + 8
	while step <= far do
		table.insert(rings, step)
		step += 8
	end
	for _, radius in ipairs(rings) do
		local n = math.clamp(math.floor(radius * 0.6), 10, 36)
		for k = 0, n - 1 do
			local a = start + k / n * math.pi * 2
			local q = origin + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			local hit = groundBelow(Vector3.new(q.X, origin.Y + 60, q.Z), solid)
			if goodSpot(hit, sky, center, r) then
				return (hit :: RaycastResult).Position
			end
		end
	end
	-- nothing clear: the nearest walkable ground to them
	local hit = groundBelow(origin, solid)
	return if hit and hit.Material ~= Enum.Material.Water then hit.Position else origin
end

--------------------------------------------------------------------------------------------------------------------
-- The parcel and its chute
--------------------------------------------------------------------------------------------------------------------

local function newPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- The parcel at `ground` (bottom centre): a pale grey canvas block with a white tube strapped on its side, cord tied in a
-- cross and a small ember card tag (Weapons_v2 1.4). Its chute (Model "Chute") is ember and charcoal canvas, open over
-- it; clients move the whole model down from DropHeight while it falls.
local function buildParcel(ground: Vector3, yaw: number): Model
	local model = Instance.new("Model")
	model.Name = "KitParcel"
	local base = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local size = Vector3.new(2.3, 1.5, 1.7)
	local body = newPart(model, "Body", size, base * CFrame.new(0, size.Y / 2, 0), CANVAS, Enum.Material.Fabric)
	body.CanCollide = true
	body.CanQuery = true
	model.PrimaryPart = body
	newPart(model, "Tube", Vector3.new(2.1, 0.5, 0.5), base * CFrame.new(0, 0.55, -size.Z / 2 - 0.22), TUBE, Enum.Material.Plastic, Enum.PartType.Cylinder)
	for _, x in ipairs({ -0.55, 0.55 }) do
		newPart(model, "Strap", Vector3.new(0.14, size.Y + 0.04, size.Z + 0.56), base * CFrame.new(x, size.Y / 2, -0.2), CORD, Enum.Material.Fabric)
	end
	newPart(model, "CordX", Vector3.new(size.X + 0.04, 0.05, 0.12), base * CFrame.new(0, size.Y + 0.02, 0), CORD, Enum.Material.Fabric)
	newPart(model, "CordZ", Vector3.new(0.12, 0.05, size.Z + 0.04), base * CFrame.new(0, size.Y + 0.02, 0), CORD, Enum.Material.Fabric)
	newPart(model, "Tag", Vector3.new(0.34, 0.03, 0.24), base * CFrame.new(0.3, size.Y + 0.05, 0.3) * CFrame.Angles(0, 0.4, 0), EMBER, Enum.Material.SmoothPlastic)
	local prompt = Instance.new("Attachment")
	prompt.Name = "PromptAttachment"
	prompt.Position = Vector3.new(0, 0.1, size.Z / 2 + 0.4)
	prompt.Parent = body
	-- the chute: a shallow dome of 8 alternating ember and charcoal panels on four cords
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	local height, radius = 9.5, 5.2
	local top = base * CFrame.new(0, size.Y + height, 0)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local panel = newPart(chute, "Panel", Vector3.new(radius * 0.82, 0.08, radius * 1.02),
			top * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.9, -radius * 0.48) * CFrame.Angles(math.rad(-20), 0, 0),
			if i % 2 == 0 then EMBER else CHARCOAL, Enum.Material.Fabric)
		panel.CastShadow = true
	end
	newPart(chute, "Crown", Vector3.new(1.4, 0.1, 1.4), top, CHARCOAL, Enum.Material.Fabric)
	for i = 0, 3 do
		local a = (i + 0.5) / 4 * math.pi * 2
		local rim = (top * CFrame.Angles(0, a, 0) * CFrame.new(0, -1.7, -radius * 0.92)).Position
		local foot = (base * CFrame.new(math.sign(math.cos(a)) * 0.9, size.Y, math.sign(math.sin(a)) * 0.6)).Position
		local len = (rim - foot).Magnitude
		local cord = newPart(chute, "Line", Vector3.new(0.05, 0.05, len), CFrame.lookAt((rim + foot) / 2, rim), CORD, Enum.Material.Fabric)
		cord.CastShadow = false
	end
	chute.Parent = model
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

local function dustAndSmoke(model: Model)
	local body = model.PrimaryPart
	if not body then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "LandFx"
	holder.Position = Vector3.new(0, -body.Size.Y / 2 + 0.2, 0)
	holder.Parent = body
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(184, 168, 144))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(3, 6)
	dust.SpreadAngle = Vector2.new(85, 85)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Acceleration = Vector3.new(0, 0.8, 0)
	dust.Drag = 2.5
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Rate = 0
	dust.Parent = holder
	dust:Emit(26)
	-- a thin pale smoke ribbon so others can find it
	local top = Instance.new("Attachment")
	top.Name = "SmokeFx"
	top.Position = Vector3.new(0.6, body.Size.Y / 2, 0.2)
	top.Parent = body
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(226, 222, 212))
	smoke.LightInfluence = 1
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1.6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(2.2, 3)
	smoke.SpreadAngle = Vector2.new(6, 6)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Acceleration = Vector3.new(0.4, 0.2, 0)
	smoke.Rate = 4
	smoke.Parent = top
	task.delay(S.SmokeTime or 20, function()
		smoke.Enabled = false
		task.delay(6, function()
			top:Destroy()
		end)
	end)
	task.delay(2, function()
		holder:Destroy()
	end)
end

-- The chute folds over beside the parcel.
local function foldChute(model: Model)
	local chute = model:FindFirstChild("Chute")
	if chute then
		chute:Destroy()
	end
	local body = model.PrimaryPart
	if not body then
		return
	end
	local bottom = body.CFrame * CFrame.new(0, -body.Size.Y / 2, 0)
	local folded = Instance.new("Model")
	folded.Name = "FoldedChute"
	newPart(folded, "Fold", Vector3.new(3.6, 0.14, 2.4), bottom * CFrame.new(-3.4, 0.07, 0.4) * CFrame.Angles(0, 0.3, math.rad(2)), EMBER, Enum.Material.Fabric)
	newPart(folded, "Fold", Vector3.new(3.0, 0.14, 2.0), bottom * CFrame.new(-3.2, 0.2, 0.5) * CFrame.Angles(0, 0.55, math.rad(-3)), CHARCOAL, Enum.Material.Fabric)
	newPart(folded, "Fold", Vector3.new(2.2, 0.12, 1.4), bottom * CFrame.new(-3.0, 0.32, 0.3) * CFrame.Angles(0, 0.1, 0), EMBER, Enum.Material.Fabric)
	folded.Parent = model
end

local function lootFolder(): Instance
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	local crates = loot and loot:FindFirstChild("Crates")
	return crates or workspace
end

local function openParcel(model: Model, items: { any }, opener: Player)
	if model:GetAttribute("Opened") == true then
		return
	end
	model:SetAttribute("Opened", true)
	local prompt = model:FindFirstChild("KitPrompt", true)
	if prompt then
		prompt:Destroy()
	end
	Sfx.play("CrateOpen", { position = model:GetPivot().Position })
	local loot = Services.LootService
	if loot and type(loot.openFixed) == "function" then
		local ok, err = pcall(loot.openFixed, model, items, opener)
		if not ok then
			warn("[KitService] openFixed failed: " .. tostring(err))
		end
	end
end

local function addPrompt(model: Model, items: { any }, owner: Player?, token: number)
	local body = model.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "KitPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Kit parcel"
	prompt:SetAttribute("PromptLine", "Open kit parcel")
	prompt:SetAttribute("KitOwner", if owner then owner.UserId else 0)
	prompt:SetAttribute("OwnerHold", S.OwnerOpenTime or 0.6) -- KitController shortens the hold on the owner's screen
	prompt.HoldDuration = S.OtherOpenTime or 2.5
	prompt.MaxActivationDistance = (Config.Loot.CratePromptDistance or 8)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("Range", prompt.MaxActivationDistance)
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Parent = body:FindFirstChild("PromptAttachment") or body
	-- each player's hold as the server saw it: when it began and (once let go) when it ended. The engine fires
	-- PromptButtonHoldEnded BEFORE Triggered on the server, so the hold is kept past its end and read by Triggered
	-- (mp-weapons, 19 Nov: clearing it on HoldEnded refused every real hold, so no parcel ever opened with E).
	local holds: { [Player]: { began: number, ended: number? } } = {}
	prompt.PromptButtonHoldBegan:Connect(function(who: Player)
		holds[who] = { began = os.clock() }
	end)
	prompt.PromptButtonHoldEnded:Connect(function(who: Player)
		local h = holds[who]
		if h and not h.ended then
			h.ended = os.clock()
		end
	end)
	prompt.Triggered:Connect(function(who: Player)
		local h = holds[who]
		holds[who] = nil
		if token ~= roundToken or not isAlive(who) then
			return
		end
		local root = rootOf(who)
		if not root or (root.Position - body.Position).Magnitude > (Config.Loot.PickupRange or 10) + 2 then
			return
		end
		local need = if owner == who then (S.OwnerOpenTime or 0.6) else (S.OtherOpenTime or 2.5)
		local t = os.clock()
		if h == nil or (h.ended ~= nil and t - h.ended > 0.5) or (h.ended or t) - h.began < need - 0.25 then
			return -- the server times the hold: a stranger's client cannot shorten it
		end
		openParcel(model, items, who)
	end)
	-- Studio tests only: parcel attribute TestOpenBy = a UserId opens it as that player (no hold)
	if Config.IsStudio then
		model:GetAttributeChangedSignal("TestOpenBy"):Connect(function()
			local who = Players:GetPlayerByUserId(tonumber(model:GetAttribute("TestOpenBy")) or 0)
			if who and token == roundToken then
				openParcel(model, items, who)
			end
		end)
	end
end

-- Drops one player's parcel: the warning now, the landing WarningLead s later.
local function dropFor(player: Player, kit: any, token: number)
	local spot = findSpot(player)
	if not spot then
		return
	end
	local items = itemsFor(player, kit) -- taken now: what they bring is fixed once the parcel is on its way
	local lead = S.WarningLead or 10
	local fall = math.min(S.FallTime or 7, lead)
	local landAt = now() + lead
	player:SetAttribute("KitIncoming", landAt)
	task.delay(lead - fall, function()
		if token ~= roundToken then
			return
		end
		local model = buildParcel(spot, rng:NextNumber(0, math.pi * 2))
		model:SetAttribute("OwnerUserId", player.UserId)
		model:SetAttribute("Kit", kit.id)
		model:SetAttribute("LandAt", landAt)
		model:SetAttribute("DropHeight", S.DropHeight or 140)
		model:SetAttribute("FallTime", fall)
		model:SetAttribute("Opened", false)
		CollectionService:AddTag(model, PARCEL_TAG)
		model.Parent = lootFolder()
		KitService.delivered:Fire(player, kit.id, model)
		task.delay(math.max(0, landAt - now()), function()
			if token ~= roundToken or not model.Parent then
				return
			end
			model:SetAttribute("Landed", true)
			foldChute(model)
			dustAndSmoke(model)
			Sfx.play("Land_Hard", { position = spot, volume = 0.9 })
			addPrompt(model, items, player, token)
			task.delay(S.MarkerTime or 90, function()
				if player.Parent == Players and player:GetAttribute("KitIncoming") == landAt then
					player:SetAttribute("KitIncoming", nil)
				end
			end)
		end)
	end)
end

local function startMidpoint(token: number)
	if midpointDone or token ~= roundToken then
		return
	end
	midpointDone = true
	local list = {}
	for player, kitId in pairs(roundKits) do
		if isAlive(player) then
			table.insert(list, { player = player, kit = Kits.get(kitId) or Kits.default() })
		end
	end
	print(string.format("[KitService] the midpoint: %d kit parcels on their way", #list))
	for _, entry in ipairs(list) do
		task.delay(rng:NextNumber(0, S.Stagger or 20), function()
			if token == roundToken and isAlive(entry.player) then
				local ok, err = pcall(dropFor, entry.player, entry.kit, token)
				if not ok then
					warn("[KitService] drop failed: " .. tostring(err))
				end
			end
		end)
	end
end

-- Watches the round for its midpoint (once a second).
local function watchMidpoint(token: number)
	local started = tonumber(GameState:GetAttribute("RoundStartedAt")) or now()
	local ends = tonumber(GameState:GetAttribute("PhaseEndsAt")) or (started + 1200)
	local length = math.max(60, ends - started)
	local full = tonumber((Config.Round or {}).MaxRoundTime) or length
	local scale = math.max(0.01, length / math.max(1, full)) -- Studio's StudioTimeScale shortens everything alike
	local practice = GameState:GetAttribute("Practice") == true
	local at = if practice then (S.PracticeTime or 60) * scale
		elseif S.MidpointTime then S.MidpointTime * scale
		else length / 2
	local minTime = (S.MinTime or 240) * scale
	local startedCount = math.max(1, tonumber(GameState:GetAttribute("StartedCount")) or 1)
	while token == roundToken and not midpointDone do
		task.wait(1)
		if token ~= roundToken or GameState:GetAttribute("Phase") ~= "Active" then
			return
		end
		local elapsed = now() - started
		local alive = tonumber(GameState:GetAttribute("AliveCount")) or startedCount
		local outShare = 1 - alive / startedCount
		local test = Config.IsStudio and GameState:GetAttribute("KitDropNow") == true
		if test then
			GameState:SetAttribute("KitDropNow", false)
		end
		if test or elapsed >= at or (not practice and outShare >= (S.MidpointShare or 0.5) and elapsed >= minTime) then
			startMidpoint(token)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Round flow
--------------------------------------------------------------------------------------------------------------------

local function onRoundStarting()
	roundToken += 1
	midpointDone = false
	table.clear(roundKits)
	for _, player in ipairs(Players:GetPlayers()) do
		if isAlive(player) then
			roundKits[player] = KitService.getKit(player)
			player:SetAttribute("KitIncoming", nil)
			-- the skills lock at the call (Combat_v3 2.1): the round's code reads these two
			local l = KitService.getLoadout(player)
			player:SetAttribute("RoundSpecialty", l.specialty)
			player:SetAttribute("RoundGeneral", l.general)
		end
	end
end

local function onRoundStarted()
	local token = roundToken
	if KitService.deliveryMode() == "Start" then
		for player, kitId in pairs(roundKits) do
			if isAlive(player) then
				giveNow(player, Kits.get(kitId) or Kits.default())
			end
		end
		return
	end
	task.spawn(watchMidpoint, token)
end

local function onRoundEnded()
	roundToken += 1
	midpointDone = true
	table.clear(roundKits)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("KitIncoming", nil)
		task.spawn(publishArmoury, player)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function KitService.Init(registry)
	Services = registry
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	for _, name in ipairs({ REMOTE, LOADOUT_REMOTE }) do
		if remotes and not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end
	-- the new weapons' part-built looks, until their Blender meshes exist (Shared.WeaponLooks)
	local ok, installed = pcall(WeaponLooks.install)
	if ok and #installed > 0 then
		print("[KitService] stand-in looks for " .. table.concat(installed, ", "))
	elseif not ok then
		warn("[KitService] WeaponLooks.install failed: " .. tostring(installed))
	end
end

function KitService.Start()
	Net.event(REMOTE).OnServerEvent:Connect(onPick)
	Net.event(LOADOUT_REMOTE).OnServerEvent:Connect(onLoadoutSet)
	local round = Services.RoundService
	if round then
		round.roundStarting:Connect(onRoundStarting)
		round.roundStarted:Connect(onRoundStarted)
		round.roundEnded:Connect(onRoundEnded)
	else
		warn("[KitService] RoundService is missing: no kits")
	end
	-- Studio tests: KitDropNow = true drops everyone's kit now (again, if it already came this round)
	GameState:GetAttributeChangedSignal("KitDropNow"):Connect(function()
		if Config.IsStudio and GameState:GetAttribute("KitDropNow") == true and GameState:GetAttribute("Phase") == "Active" then
			GameState:SetAttribute("KitDropNow", false)
			midpointDone = false
			startMidpoint(roundToken)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadPick, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		picks[player] = nil
		roundKits[player] = nil
		loadouts[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPick, player)
	end
end

return KitService
