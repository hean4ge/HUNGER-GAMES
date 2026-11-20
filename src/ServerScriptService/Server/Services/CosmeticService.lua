--[[
	CosmeticService - what a player's cosmetics do in the game (docs/design/CardMenusAndShop.md 3.1): the skins on their
	weapons, the kill effect and kill icon a weapon shows when it wins a fight, and their banner and trim. The server
	half; Shared.CosmeticLooks is the look table, Shared.CosmeticFx draws kill effects, Client CosmeticsController shows
	them. Cosmetic only: nothing here touches damage, reach, cooldowns or hitboxes (a skin recolours parts that already
	exist; Stars.def and CombatService never read it).

	Saved: Econ.Looks (DataService) = { s = { [weaponId | "*"] = skinId }, e = { [weaponId | "*"] = effectId },
	  i = { [weaponId | "*"] = iconId }, b = bannerId, t = trimId }   ("*" = every weapon; a weapon's own entry wins)
	Mirrored: player attribute LooksJson (CosmeticLooks.encode), so every client draws anyone's icon, effect and banner.
	Ownership: ShopService.owns (Econ.Shop.Owned, under the item's id or any of its aliases), or a free item (Linen).
	In Studio, the workspace attribute DevAllCosmetics = true counts everything as owned (tests only).

	Remote ReplicatedStorage.Remotes.Looks (created here, like PlusService's: the game works without it):
	  client -> server  "equip", { id = cosmeticId | "", slot = "skin" | "effect" | "icon" | "banner" | "trim"?,
	                               weapon = weaponId | "*"? }        "" with a slot (and weapon) takes it off
	  server -> client  "state", { looks = looks, ok = boolean, why = string? }   after every equip
	Remote ReplicatedStorage.Remotes.KillFx (created here):
	  server -> all clients  { id = effectId, pos = Vector3, victim = userId, killer = userId, weapon = weaponId? }
	  when a defeat was dealt by a player whose weapon (or "*") has a kill effect.

	API (other services)
	  CosmeticService.equip(player, id, weapon?, slot?) -> (ok, why?)   the shop's "equip" calls this with (player, id):
	      a skin goes on its own weapon, a wrap on "*", an effect or icon on "*" (use on all weapons)
	  CosmeticService.unequip(player, slot, weapon?)
	  CosmeticService.getLooks(player) -> looks          CosmeticService.owns(player, id) -> boolean
	  CosmeticService.reskin(player)                     re-applies the skin on the weapon the player holds
	Held weapons: when a character gets its "EquippedModel" (InventoryService), the skin for that weapon is set on it
	(attribute Skin + CosmeticLooks.applySkin); TierLooks keeps it through any later star change. The first-person
	model is skinned on the client (TierLooks reads the local player's LooksJson).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local CosmeticLooks = require(Shared:WaitForChild("CosmeticLooks"))

local CosmeticService = {}

local Services: any = nil
local looksRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil
local cache: { [Player]: any } = {} -- the live looks per player (also before the profile loads: empty)

local SLOT_KIND = { skin = "skin", effect = "effect", icon = "icon", banner = "banner", trim = "trim" }
local KIND_KEY = { skin = "s", effect = "e", icon = "i" }

local function call(serviceName: string, method: string, ...): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	return if ok then result else nil
end

local function remote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local r = folder:FindFirstChild(name)
	if not (r and r:IsA("RemoteEvent")) then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	return r :: RemoteEvent
end

function CosmeticService.getLooks(player: Player): any
	return CosmeticLooks.clean(cache[player])
end

function CosmeticService.owns(player: Player, id: any): boolean
	local item = CosmeticLooks.get(id)
	if not item then
		return false
	end
	if item.free then
		return true
	end
	if Config.IsStudio and workspace:GetAttribute("DevAllCosmetics") == true then
		return true
	end
	if call("ShopService", "owns", player, item.id) == true then
		return true
	end
	for _, alias in ipairs(item.aliases) do
		if call("ShopService", "owns", player, alias) == true then
			return true
		end
	end
	-- earned items kept elsewhere (Season Track, ranks): Econ.Progress.Owned / Econ.Looks.Owned when they exist
	local econ = call("DataService", "getEcon", player)
	for _, bag in ipairs({ econ and econ.Progress and econ.Progress.Owned, econ and econ.Looks and econ.Looks.Owned }) do
		if type(bag) == "table" then
			if bag[item.id] ~= nil then
				return true
			end
			for _, alias in ipairs(item.aliases) do
				if bag[alias] ~= nil then
					return true
				end
			end
		end
	end
	return false
end

local function heldModels(player: Player): { Model }
	local out = {}
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Model") and child.Name == "EquippedModel" then
				table.insert(out, child)
			end
		end
	end
	return out
end

local function skinModel(player: Player, model: Model)
	local id = model:GetAttribute("ItemId")
	if type(id) ~= "string" then
		return
	end
	local skin = CosmeticLooks.skinFor(cache[player], id)
	if skin == nil and model:GetAttribute("Skin") == nil then
		return -- nothing worn and nothing to take off
	end
	CosmeticLooks.applySkin(model, skin or "")
end

function CosmeticService.reskin(player: Player)
	for _, model in ipairs(heldModels(player)) do
		pcall(skinModel, player, model)
	end
end

local function publish(player: Player, ok: boolean?, why: string?)
	local looks = CosmeticLooks.clean(cache[player])
	if player.Parent == Players then
		player:SetAttribute("LooksJson", CosmeticLooks.encode(looks))
	end
	CosmeticService.reskin(player)
	if looksRemote and ok ~= nil then
		looksRemote:FireClient(player, "state", { looks = looks, ok = ok, why = why })
	end
end

local function save(player: Player)
	local looks = CosmeticLooks.clean(cache[player])
	local saved = call("DataService", "updateEcon", player, function(e)
		e.Looks = looks
	end)
	if saved then
		call("DataService", "saveSoon", player)
	end
	return saved == true
end

-- Puts `id` on (weapon or "*"). slot is optional (the item's own kind). Returns ok, why.
function CosmeticService.equip(player: Player, id: any, weapon: any, slot: any): (boolean, string?)
	local item = CosmeticLooks.get(id)
	if not item then
		return false, "unknown"
	end
	if slot ~= nil and SLOT_KIND[slot] ~= item.kind then
		return false, "wrong slot"
	end
	if not CosmeticService.owns(player, item.id) then
		return false, "not owned"
	end
	local looks = CosmeticLooks.clean(cache[player])
	if item.kind == "banner" then
		looks.b = item.id
	elseif item.kind == "trim" then
		looks.t = item.id
	else
		local key = KIND_KEY[item.kind]
		if not key then
			return false, "not wearable"
		end
		local w = if type(weapon) == "string" and #weapon <= 32 and weapon ~= "" then weapon else nil
		if item.kind == "skin" then
			w = if item.weapon == "*" then (w or "*") else item.weapon -- a skin only fits its weapon; a wrap anywhere
			if not CosmeticLooks.fits(item.id, w) and w ~= "*" then
				return false, "wrong weapon"
			end
		else
			w = w or "*"
		end
		looks[key][w] = item.id
	end
	cache[player] = looks
	save(player)
	publish(player, true)
	return true
end

function CosmeticService.unequip(player: Player, slot: any, weapon: any)
	local looks = CosmeticLooks.clean(cache[player])
	if slot == "banner" then
		looks.b = nil
	elseif slot == "trim" then
		looks.t = nil
	elseif KIND_KEY[slot] then
		local w = if type(weapon) == "string" and weapon ~= "" then weapon else "*"
		looks[KIND_KEY[slot]][w] = nil
	else
		return
	end
	cache[player] = looks
	save(player)
	publish(player, true)
end

local function onLooks(player: Player, action: any, data: any)
	if action ~= "equip" or type(data) ~= "table" or not Net.rateLimit(player, "Looks", 4, 8) then
		return
	end
	if data.id == "" or data.id == nil then
		CosmeticService.unequip(player, data.slot, data.weapon)
		return
	end
	local ok, why = CosmeticService.equip(player, data.id, data.weapon, data.slot)
	if not ok then
		publish(player, false, why)
	end
end

-- Kill effects: a defeat dealt by a player plays the effect worn on the weapon that dealt it ("*" for any).
local function onDied(victim: Player, killer: Player?, _cause: any, weaponId: any, position: any)
	if not killer or killer == victim or killer.Parent ~= Players or not fxRemote then
		return
	end
	local weapon = if type(weaponId) == "string" then weaponId else nil
	local effect = CosmeticLooks.effectFor(cache[killer], weapon)
	if not effect then
		return
	end
	local pos = if typeof(position) == "Vector3" then position else nil
	if not pos then
		local character = victim.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		pos = if root and root:IsA("BasePart") then root.Position else nil
	end
	if not pos then
		return
	end
	fxRemote:FireAllClients({ id = effect, pos = pos, victim = victim.UserId, killer = killer.UserId, weapon = weapon })
end

local function watchCharacter(player: Player, character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child.Name == "EquippedModel" then
			task.defer(function() -- (after InventoryService has set ItemId and the star look)
				if child.Parent == character then
					pcall(skinModel, player, child)
				end
			end)
		end
	end)
end

local function onPlayer(player: Player)
	cache[player] = CosmeticLooks.clean(nil)
	player:SetAttribute("LooksJson", CosmeticLooks.encode(cache[player]))
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
	-- the saved looks, once the profile has loaded (DataService has no signal: ask for 2 minutes)
	task.spawn(function()
		for _ = 1, 240 do
			if player.Parent ~= Players then
				return
			end
			if call("DataService", "isLoaded", player) == true then
				local econ = call("DataService", "getEcon", player)
				if econ and type(econ.Looks) == "table" then
					cache[player] = CosmeticLooks.clean(econ.Looks)
					publish(player, nil)
				end
				return
			end
			task.wait(0.5)
		end
	end)
end

function CosmeticService.Init(registry)
	Services = registry
	looksRemote = remote("Looks")
	fxRemote = remote("KillFx")
	;(looksRemote :: RemoteEvent).OnServerEvent:Connect(onLooks)
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

function CosmeticService.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		if not cache[player] then
			onPlayer(player)
		end
	end
	local ps = Services and Services.PlayerService
	if ps and ps.died then
		ps.died:Connect(onDied)
	else
		warn("[CosmeticService] no PlayerService.died: kill effects are off")
	end
end

return CosmeticService
