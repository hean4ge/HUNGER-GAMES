--[[
	TrailService - cosmetic trails: who owns which, buying them with Gold, what each player has equipped
	(docs/design/Combat_v3.md section 4; the catalogue is Shared.Trails).

	Saved in the profile through DataService (Econ.Trails = { Owned = { [id] = true }, Swing, Arrow, Throw }).
	Gold: DataService.spendGold, logged with CurrencyService.log (a Sink, "Shop", "Trail_<id>"). Nothing random: a
	trail is bought by name, for good, for every slot it fits. No Robux (Config.Economy.RobuxTrails stays off).

	Replication: player attributes, so every client draws everyone's trails with no extra traffic.
	  TrailSwing / TrailArrow / TrailThrow   the equipped id per slot ("none" = no trail)
	  TrailsOwned                            comma list of the trails this player bought (the free ones are not listed)

	Remote "Trails" (created here like CurrencyService's "Rewards"):
	  client -> server  ("buy", id, slot?)       buy it (and equip it in `slot` when it fits)
	                    ("equip", slot, id)      equip an owned or free trail, or "none"
	  server -> client  ("line", text)           one quiet line for the shop (not enough Gold, ...)
	                    ("bought", id)           it is yours

	API (for the Loadout: LoadoutSet carries trails = { swing, arrow, throw })
	  TrailService.owns(player, id) -> boolean
	  TrailService.equip(player, slot, id) -> boolean     checks ownership and the slot; saves with the next write
	  TrailService.buy(player, id, slot?) -> (boolean, string?)
	  TrailService.equipped(player) -> { swing, arrow, throw }
	  TrailService.setLoadout(player, trails) -> boolean   all three at once (each checked; a bad one is left as it was)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Trails = require(Shared:WaitForChild("Trails"))

local TrailService = {}

local REMOTE_NAME = "Trails"
local KEY = { swing = "Swing", arrow = "Arrow", throw = "Throw" }
local LOAD_WAIT = 120 -- seconds a joining player's profile is waited for before the defaults are shown

local Services: any = nil
local remote: RemoteEvent? = nil
local busy: { [Player]: boolean } = {}

local function call(serviceName: string, method: string, ...): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[TrailService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function getRemote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		return nil
	end
	local existing = folder:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local created = Instance.new("RemoteEvent")
	created.Name = REMOTE_NAME
	created.Parent = folder
	return created
end

local function send(player: Player, ...)
	if remote and player.Parent == Players then
		remote:FireClient(player, ...)
	end
end

local function econTrails(player: Player): { [string]: any }
	local econ = call("DataService", "getEcon", player)
	local t = econ and econ.Trails
	return if type(t) == "table" then t else { Owned = {}, Swing = "", Arrow = "", Throw = "" }
end

-- What is equipped in a slot: the saved id when it is still valid for that player, else the default
local function resolve(player: Player, t: { [string]: any }, slot: string): string
	local id = t[KEY[slot]]
	if id == "none" then
		return "none"
	end
	if type(id) == "string" and id ~= "" and Trails.fits(id, slot)
		and (Trails.isFree(id) or (type(t.Owned) == "table" and t.Owned[id] == true)) then
		return id
	end
	return Trails.DEFAULT[slot] or "draught"
end

local function publish(player: Player)
	if player.Parent ~= Players then
		return
	end
	local t = econTrails(player)
	for _, slot in ipairs(Trails.SLOTS) do
		player:SetAttribute(Trails.ATTR[slot], resolve(player, t, slot))
	end
	local owned = {}
	for id in pairs(type(t.Owned) == "table" and t.Owned or {}) do
		if Trails.get(id) then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	player:SetAttribute(Trails.OWNED_ATTR, table.concat(owned, ","))
end

function TrailService.owns(player: Player, id: string): boolean
	if id == "none" or Trails.isFree(id) then
		return Trails.get(id) ~= nil or id == "none"
	end
	local t = econTrails(player)
	return Trails.get(id) ~= nil and type(t.Owned) == "table" and t.Owned[id] == true
end

function TrailService.equipped(player: Player): { [string]: string }
	local t = econTrails(player)
	return { swing = resolve(player, t, "swing"), arrow = resolve(player, t, "arrow"), throw = resolve(player, t, "throw") }
end

function TrailService.equip(player: Player, slot: string, id: string): boolean
	if type(slot) ~= "string" or not KEY[slot] or type(id) ~= "string" then
		return false
	end
	if not Trails.fits(id, slot) or not TrailService.owns(player, id) then
		return false
	end
	local ok = call("DataService", "updateEcon", player, function(econ)
		econ.Trails = econ.Trails or { Owned = {} }
		econ.Trails[KEY[slot]] = id
	end)
	if not ok then
		return false
	end
	publish(player)
	return true
end

function TrailService.setLoadout(player: Player, trails: any): boolean
	if type(trails) ~= "table" then
		return false
	end
	local all = true
	for _, slot in ipairs(Trails.SLOTS) do
		local id = trails[slot]
		if id ~= nil and id ~= player:GetAttribute(Trails.ATTR[slot]) then
			all = TrailService.equip(player, slot, id) and all
		end
	end
	return all
end

function TrailService.buy(player: Player, id: string, slot: string?): (boolean, string?)
	local def = Trails.get(id)
	if not def then
		return false, "That trail is not in the shop"
	end
	if busy[player] then
		return false, nil
	end
	if TrailService.owns(player, id) then
		if slot and Trails.fits(id, slot) then
			TrailService.equip(player, slot, id)
		end
		return true, nil
	end
	local earned = Trails.earnedFrom(id)
	if earned then
		return false, string.format("%s is earned, not sold · %s", def.name, earned)
	end
	if not call("DataService", "isLoaded", player) then
		return false, "Your Gold is still loading"
	end
	busy[player] = true
	local price = def.price
	if not call("DataService", "spendGold", player, price) then
		busy[player] = nil
		return false, string.format("%s is %d Gold", def.name, price)
	end
	local ok = call("DataService", "updateEcon", player, function(econ)
		econ.Trails = econ.Trails or { Owned = {} }
		econ.Trails.Owned = econ.Trails.Owned or {}
		econ.Trails.Owned[id] = true
		if slot and KEY[slot] and def.slots[slot] then
			econ.Trails[KEY[slot]] = id
		end
	end)
	if not ok then
		call("DataService", "increment", player, "Gold", price) -- the Gold goes back
		busy[player] = nil
		return false, "The trail could not be saved · your Gold is back"
	end
	call("CurrencyService", "log", player, false, price, "Shop", "Trail_" .. id)
	call("DataService", "saveSoon", player)
	busy[player] = nil
	publish(player)
	return true, nil
end

-- A trail given, not bought (the Season Track's Resin and Gold Dust; SeasonService). True once it is owned and saved.
function TrailService.grant(player: Player, id: string): boolean
	if type(id) ~= "string" or not Trails.get(id) then
		return false
	end
	if TrailService.owns(player, id) then
		return true
	end
	if not call("DataService", "isLoaded", player) then
		return false
	end
	local ok = call("DataService", "updateEcon", player, function(econ)
		econ.Trails = econ.Trails or { Owned = {} }
		econ.Trails.Owned = econ.Trails.Owned or {}
		econ.Trails.Owned[id] = true
	end)
	if not ok then
		return false
	end
	call("DataService", "saveSoon", player)
	publish(player)
	return true
end

local function onRequest(player: Player, action: any, a: any, b: any)
	if not Net.rateLimit(player, "Trails", 4, 6) then
		return
	end
	if action == "buy" then
		if type(a) ~= "string" or #a > 24 then
			return
		end
		local slot = if type(b) == "string" and KEY[b] then b else nil
		local ok, why = TrailService.buy(player, a, slot)
		if ok then
			send(player, "bought", a)
		elseif why then
			send(player, "line", why)
		end
	elseif action == "equip" then
		if type(a) ~= "string" or type(b) ~= "string" or #b > 24 then
			return
		end
		if not TrailService.equip(player, a, b) then
			local def = Trails.get(b)
			if def and not TrailService.owns(player, b) then
				send(player, "line", string.format("%s is %d Gold", def.name, def.price))
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	-- defaults at once (so others see a trail even before the profile answers), the saved ones once it has loaded
	for _, slot in ipairs(Trails.SLOTS) do
		player:SetAttribute(Trails.ATTR[slot], Trails.DEFAULT[slot] or "draught")
	end
	player:SetAttribute(Trails.OWNED_ATTR, "")
	local waited = 0
	while player.Parent == Players and not call("DataService", "isLoaded", player) and waited < LOAD_WAIT do
		task.wait(0.5)
		waited += 0.5
	end
	publish(player)
end

function TrailService.Init(services)
	Services = services
	remote = getRemote()
end

function TrailService.Start()
	if remote then
		remote.OnServerEvent:Connect(function(player, ...)
			local ok, err = pcall(onRequest, player, ...)
			if not ok then
				warn("[TrailService] " .. tostring(err))
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return TrailService
