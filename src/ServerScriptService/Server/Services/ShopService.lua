--[[
	ShopService - CASES on the server: the five Gold crates, the Lucky Acorn, the Shelf, cosmetics owned and equipped,
	and every Robux path of the shop (all OFF). docs/design/CardMenusAndShop.md sections 2.4, 3.2 to 3.5, 3.10.
	Numbers and odds: Shared.Crates (the client shows the same tables). Saved in Econ.Shop through DataService.
	The wheel, the Strongboxes and the Armoury stay RewardsService's (CASES calls its remote with a "menu" flag).

	Remote ReplicatedStorage.Remotes.Shop (created in Init)
	  client -> server
	    "state"                               your state
	    "buy", crateId, quantity, useAcorn    buy 1..10 crates with Gold and open them now
	    "open", crateId, useAcorn             open one crate you hold (from the daily reward, Season Track, ranks)
	    "shelf", itemId                       buy today's Shelf item outright for Gold (no chance)
	    "equip", itemId                       equip an owned cosmetic (its slot: "skin:<weapon>", "wrap", or its type)
	    "robux", what, key                    ask for a Robux prompt (only when its Config.Shop switch is on and its id
	                                          is set; paid random items refused for restricted players)
	  server -> client
	    "state", State                        after any change, and when asked
	    "result", Result                      to you, after "buy" / "open": { crate, results = { Draw }, acornUsed,
	                                          goldBack } with Draw = { grade, id?, name, type, weapon?, look, serial?,
	                                          duplicate?, goldBack?, rolls = {g1, g2?}, pity?, lucky?, acorn? } best last
	    "line", text                          one quiet line (not enough Gold, ...)
	  State = { loaded, gold, held = {[crateId]=n}, acorns, acornMax, pity = {[crateId] = {storied?, fabled?}},
	            owned = {[id]=serial}, equipped = {[slot]=id}, shelf = {id...}, shelfDay, restricted, paidRandom,
	            robux = { gold, crates, luck, luckOwned, luckNext, direct } }

	Paid random items (docs/design/RandomItemRules_2026-11-18.md): while every Robux switch is off Gold is earned
	only and no crate is a paid random item: everyone everywhere can buy them. With RobuxGold, RobuxCrates or RobuxLuck
	on, a player whose PolicyService info says ArePaidRandomItemsRestricted (or whose call failed) cannot BUY crates;
	held crates still OPEN and the Shelf stays. Studio only, for tests: Workspace attributes ShopSimulateRobux = true
	(acts as if a Robux switch were on) and ShopPolicyTest = "restricted" | "allowed" (the policy answer).

	Robux receipts: one MarketplaceService.ProcessReceipt for every product (Gold packs too, so CurrencyService's own
	handler is replaced when this one is set; other services add theirs with ShopService.registerProduct). It is set
	only when a switch is on with an id. Each receipt is granted once: its PurchaseId is written into Econ.Shop.Receipts
	in the same profile write as the grant (DataService.saveNow) before PurchaseGranted.

	API
	  ShopService.owns(player, id) -> boolean          ShopService.getOwned(player) -> { [id] = serial }
	  ShopService.grantCrate(player, crateId, n?)      ShopService.grantAcorns(player, n?)  (capped at AcornMax)
	  ShopService.grantCosmetic(player, id) -> boolean ShopService.equipped(player) -> { [slot] = id }
	  ShopService.paidRandomRestricted(player) -> boolean
	  ShopService.registerProduct(productId, fn(player, receiptInfo) -> boolean)
	  ShopService.pushState(player)
]]
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Net = require(Shared:WaitForChild("Net"))
local Rewards = require(Shared:WaitForChild("Rewards"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local ShopService = {}

local REMOTE_NAME = "Shop"
local Services: any = nil
local remote: RemoteEvent? = nil
local rng = Random.new()
local busy: { [Player]: boolean } = {}
local policy: { [Player]: { done: boolean, restricted: boolean } } = {}
local luckOwned: { [Player]: boolean } = {}
local products: { [number]: (Player, any) -> boolean } = {}
local pendingDirect: { [Player]: string } = {}
local localSerial = 0

local function S(): { [string]: any }
	return if type(Config.Shop) == "table" then Config.Shop else {}
end

local function call(serviceName: string, method: string, ...): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[ShopService] %s.%s failed: %s", serviceName, method, tostring(result)))
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

local function line(player: Player, text: string)
	if remote and player.Parent == Players then
		remote:FireClient(player, "line", text)
	end
end

local function validId(v: any): boolean
	return type(v) == "number" and v > 0
end

-- Switches -----------------------------------------------------------------------------------------------------------

local function robuxGold(): boolean
	local E = type(Config.Economy) == "table" and Config.Economy or {}
	return E.RobuxGold == true or S().RobuxGold == true
end

local function crateIds(): { [string]: number }
	local ids = S().CrateProductIds
	return if type(ids) == "table" then ids else {}
end

local function robuxCrates(): boolean
	if S().RobuxCrates ~= true then
		return false
	end
	for _, id in pairs(crateIds()) do
		if validId(id) then
			return true
		end
	end
	return false
end

local function robuxLuck(): boolean
	return S().RobuxLuck == true and validId(S().LuckPassId)
end

local function directBuy(): boolean
	if S().DirectBuy ~= true or type(S().DirectBuyProductIds) ~= "table" then
		return false
	end
	for _, id in pairs(S().DirectBuyProductIds) do
		if validId(id) then
			return true
		end
	end
	return false
end

-- Are crates paid random items right now? (only when Gold, crates or luck can be bought with Robux)
local function paidRandom(): boolean
	if Config.IsStudio and workspace:GetAttribute("ShopSimulateRobux") == true then
		return true
	end
	return robuxGold() or robuxCrates() or robuxLuck()
end

-- Policy -------------------------------------------------------------------------------------------------------------

local function fetchPolicy(player: Player)
	local entry = { done = false, restricted = true } -- the safe default until it answers
	policy[player] = entry
	for attempt = 1, 3 do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if policy[player] ~= entry then
			return
		end
		if ok and type(info) == "table" then
			entry.restricted = info.ArePaidRandomItemsRestricted == true
			entry.done = true
			return
		end
		task.wait(attempt * 3)
	end
	entry.done = true
	entry.restricted = true -- a failed call counts as restricted (RandomItemRules checklist 5)
end

-- The player may not buy paid random items (only ever true while a Robux switch makes crates paid random items).
function ShopService.paidRandomRestricted(player: Player): boolean
	if not paidRandom() then
		return false
	end
	if Config.IsStudio then
		local test = workspace:GetAttribute("ShopPolicyTest")
		if test == "restricted" then
			return true
		elseif test == "allowed" then
			return false
		end
	end
	local entry = policy[player]
	return entry == nil or entry.restricted ~= false
end

-- Lucky Charm (game pass, OFF) ----------------------------------------------------------------------------------------

local function refreshLuck(player: Player)
	if not robuxLuck() then
		luckOwned[player] = false
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, S().LuckPassId)
	luckOwned[player] = ok and owns == true
end

local function hasLuck(player: Player): boolean
	return robuxLuck() and luckOwned[player] == true and not ShopService.paidRandomRestricted(player)
end

-- State --------------------------------------------------------------------------------------------------------------

local function shopOf(player: Player): { [string]: any }?
	local econ = call("DataService", "getEcon", player)
	return econ and econ.Shop
end

local function stateFor(player: Player): { [string]: any }
	local shop = shopOf(player) or {}
	local owned = shop.Owned or {}
	local pity = {}
	for _, crate in ipairs(Crates.List) do
		pity[crate.id] = Crates.pityLeft(crate, (shop.Pity or {})[crate.id])
	end
	local every = math.max(2, tonumber(S().LuckEvery) or 3)
	local luck = hasLuck(player)
	return {
		loaded = call("DataService", "isLoaded", player) == true,
		gold = tonumber(call("DataService", "get", player, "Gold")) or 0,
		held = shop.Held or {},
		acorns = shop.Acorns or 0,
		acornMax = tonumber(S().AcornMax) or 10,
		pity = pity,
		owned = owned,
		equipped = shop.Equipped or {},
		shelf = Crates.shelf(Crates.dayIndex(), owned),
		shelfDay = Crates.dayIndex(),
		opened = shop.Opened or 0,
		maxQuantity = tonumber(S().CrateMaxQuantity) or 10,
		paidRandom = paidRandom(),
		restricted = ShopService.paidRandomRestricted(player),
		robux = {
			gold = robuxGold(),
			crates = robuxCrates() and not ShopService.paidRandomRestricted(player),
			crateIds = if robuxCrates() then crateIds() else {},
			luck = robuxLuck() and not ShopService.paidRandomRestricted(player),
			luckOwned = luck,
			luckNext = if luck then every - (shop.Lucky or 0) else nil,
			direct = directBuy(),
		},
	}
end

function ShopService.pushState(player: Player)
	if remote and player.Parent == Players then
		remote:FireClient(player, "state", stateFor(player))
	end
end

-- Only in the train (an alive contender in a round cannot open the shop)
local function inTrain(player: Player): boolean
	if player:GetAttribute("Alive") == true and GameState:GetAttribute("Phase") == "Active" then
		local contender = call("RoundService", "isContender", player)
		if contender ~= false then
			return false
		end
	end
	return true
end

-- Numbered serials: one counter per item across every server (a DataStore); Studio and failures use a local count
local serialStore: DataStore? = nil
local function nextSerial(itemId: string): number
	if serialStore and not Config.IsStudio then
		local ok, n = pcall(function()
			return (serialStore :: DataStore):IncrementAsync("Serial_" .. itemId, 1)
		end)
		if ok and type(n) == "number" then
			return n
		end
	end
	localSerial += 1
	return localSerial
end

-- Opening ------------------------------------------------------------------------------------------------------------

local function describe(id: string?, grade: string): { [string]: any }
	local item = id and Crates.item(id)
	return {
		grade = grade,
		id = id,
		name = if item then item.name else grade,
		type = if item then item.type else "",
		weapon = item and item.weapon,
		look = if item then item.look else "",
	}
end

-- Opens `count` crates inside one profile edit. source = "buy" | "held". Returns the draws (or nil).
local function openCrates(player: Player, crate: any, count: number, useAcorn: boolean, source: string): ({ any }?, number)
	local draws = {}
	local goldBack = 0
	local luck = hasLuck(player)
	local every = math.max(2, tonumber(S().LuckEvery) or 3)
	local ok = call("DataService", "updateEcon", player, function(e)
		local shop = e.Shop
		if source == "held" then
			if (shop.Held[crate.id] or 0) < count then
				error("no crate held")
			end
			shop.Held[crate.id] -= count
			if shop.Held[crate.id] <= 0 then
				shop.Held[crate.id] = nil
			end
		end
		local pity = shop.Pity[crate.id] or { s = 0, f = 0 }
		for _ = 1, count do
			local lucky = false
			if luck then
				shop.Lucky = (shop.Lucky or 0) + 1
				if shop.Lucky >= every then
					lucky = true
					shop.Lucky = 0
				end
			end
			local acorn = useAcorn and not lucky and shop.Acorns > 0
			if acorn then
				shop.Acorns -= 1
			end
			local grade, info = Crates.roll(crate, pity, acorn or lucky, rng)
			Crates.notePity(crate, pity, grade)
			local id, duplicate = Crates.pickItem(grade, shop.Owned, rng)
			local d = describe(id, grade)
			d.rolls = info.rolls
			d.pity = info.pity
			d.acorn = acorn or nil
			d.lucky = lucky or nil
			if duplicate or not id then
				d.duplicate = true
				d.goldBack = Crates.goldBack(crate, grade)
				d.name = string.format("%s Gold", Crates.comma(d.goldBack))
				goldBack += d.goldBack
			else
				local numbered = grade == "Fabled" and Crates.numberedRoll(rng)
				shop.Owned[id] = if numbered then -1 else 0 -- -1: a serial is fetched just below
				d.numbered = numbered or nil
			end
			table.insert(draws, d)
			shop.Opened = (shop.Opened or 0) + 1
		end
		shop.Pity[crate.id] = pity
	end)
	if not ok then
		return nil, 0
	end
	-- Numbered serials (outside the profile edit: a DataStore call may yield)
	for _, d in ipairs(draws) do
		if d.numbered and d.id then
			local n = nextSerial(d.id)
			d.serial = n
			call("DataService", "updateEcon", player, function(e)
				if e.Shop.Owned[d.id] ~= nil then
					e.Shop.Owned[d.id] = n
				end
			end)
		end
	end
	-- best last (ten reveal cards in a grid end on the best one)
	table.sort(draws, function(a, b)
		local ra, rb = Crates.GradeRank[a.grade] or 0, Crates.GradeRank[b.grade] or 0
		if ra ~= rb then
			return ra < rb
		end
		return (a.duplicate and 0 or 1) < (b.duplicate and 0 or 1)
	end)
	return draws, goldBack
end

-- The cosmetics system (CosmeticService, when it exists) keeps its own owned list for equipping: tell it.
local function notifyOwned(player: Player, id: string)
	local cos = Services and (Services.CosmeticService or Services.CosmeticsService)
	if cos and type(cos.grant) == "function" then
		pcall(cos.grant, player, id)
	end
end

local function finish(player: Player, crate: any, draws: { any }, goldBack: number, spent: number)
	for _, d in ipairs(draws) do
		if d.id and not d.duplicate then
			notifyOwned(player, d.id)
		end
	end
	if goldBack > 0 then
		call("DataService", "increment", player, "Gold", goldBack)
		call("CurrencyService", "log", player, true, goldBack, "Gameplay", "CrateDuplicateGold")
	end
	call("DataService", "saveSoon", player)
	if remote then
		remote:FireClient(player, "result", { crate = crate.id, results = draws, goldBack = goldBack, spent = spent })
	end
	ShopService.pushState(player)
	call("RewardsService", "pushState", player) -- its Gold line
end

local function buy(player: Player, crateId: any, quantity: any, useAcorn: any)
	local crate = type(crateId) == "string" and Crates.ById[crateId]
	if not crate then
		return
	end
	local n = math.clamp(math.floor(tonumber(quantity) or 1), 1, tonumber(S().CrateMaxQuantity) or 10)
	if not call("DataService", "isLoaded", player) then
		line(player, "Your Gold is still loading")
		return
	end
	if ShopService.paidRandomRestricted(player) then
		line(player, "Not available in your region · earn crates from the daily reward and the Season Track")
		return
	end
	local cost = crate.gold * n
	if not call("DataService", "spendGold", player, cost) then
		local have = tonumber(call("DataService", "get", player, "Gold")) or 0
		line(player, string.format("%s × %d is %s Gold · you need %s more", crate.name, n, Crates.comma(cost),
			Crates.comma(math.max(0, cost - have))))
		return
	end
	call("CurrencyService", "log", player, false, cost, "Shop", "Crate_" .. crate.id)
	local draws, goldBack = openCrates(player, crate, n, useAcorn == true, "buy")
	if not draws then
		call("DataService", "increment", player, "Gold", cost)
		line(player, "The crate would not open · your Gold is back")
		ShopService.pushState(player)
		return
	end
	finish(player, crate, draws, goldBack, cost)
end

local function openHeld(player: Player, crateId: any, useAcorn: any)
	local crate = type(crateId) == "string" and Crates.ById[crateId]
	if not crate or not call("DataService", "isLoaded", player) then
		return
	end
	local draws, goldBack = openCrates(player, crate, 1, useAcorn == true, "held")
	if not draws then
		line(player, "No " .. crate.name .. " to open")
		return
	end
	finish(player, crate, draws, goldBack, 0)
end

local function shelfBuy(player: Player, itemId: any)
	if type(itemId) ~= "string" or not call("DataService", "isLoaded", player) then
		return
	end
	local shop = shopOf(player)
	if not shop then
		return
	end
	local today = Crates.shelf(Crates.dayIndex(), shop.Owned)
	if not table.find(today, itemId) then
		line(player, "That is not on the Shelf today")
		return
	end
	local item = Crates.item(itemId)
	local price = Crates.shelfPrice(item.grade)
	if not call("DataService", "spendGold", player, price) then
		line(player, string.format("%s is %s Gold", item.name, Crates.comma(price)))
		return
	end
	local ok = call("DataService", "updateEcon", player, function(e)
		if e.Shop.Owned[itemId] ~= nil then
			error("owned")
		end
		e.Shop.Owned[itemId] = 0
	end)
	if not ok then
		call("DataService", "increment", player, "Gold", price)
		ShopService.pushState(player)
		return
	end
	call("CurrencyService", "log", player, false, price, "Shop", "Shelf_" .. itemId)
	notifyOwned(player, itemId)
	call("DataService", "saveSoon", player)
	local d = describe(itemId, item.grade)
	d.shelf = true
	if remote then
		remote:FireClient(player, "result", { crate = "shelf", results = { d }, goldBack = 0, spent = price })
	end
	ShopService.pushState(player)
end

local function slotFor(item: any): string
	if item.type == "Skin" and item.weapon then
		return "skin:" .. item.weapon
	elseif item.type == "Wrap" then
		return "wrap"
	end
	return tostring(item.type)
end

local function equip(player: Player, itemId: any)
	if type(itemId) ~= "string" then
		return
	end
	local shop = shopOf(player)
	local item = Crates.item(itemId)
	if not shop or not item or shop.Owned[itemId] == nil then
		return
	end
	-- the cosmetics system, when it exists, owns equipping; until then the slot is kept here
	local cos = Services and (Services.CosmeticService or Services.CosmeticsService)
	if cos and type(cos.equip) == "function" then
		pcall(cos.equip, player, itemId)
	end
	call("DataService", "updateEcon", player, function(e)
		e.Shop.Equipped[slotFor(item)] = itemId
	end)
	call("DataService", "saveSoon", player)
	line(player, string.format("%s equipped", item.name))
	ShopService.pushState(player)
end

-- Robux (OFF) ----------------------------------------------------------------------------------------------------------

local function promptRobux(player: Player, what: any, key: any)
	if what == "gold" then
		if not robuxGold() then
			return
		end
		-- packs stay open to restricted players (Gold also buys the Shelf and the Armoury); their crate BUY is refused
		for _, pack in ipairs(Rewards.config().Economy.Packs or {}) do
			if pack.key == key and validId(pack.productId) then
				MarketplaceService:PromptProductPurchase(player, pack.productId)
			end
		end
	elseif what == "crate" then
		local id = robuxCrates() and crateIds()[key]
		if not validId(id) then
			return
		end
		if ShopService.paidRandomRestricted(player) then
			line(player, "Not available in your region")
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)
	elseif what == "luck" then
		if not robuxLuck() or ShopService.paidRandomRestricted(player) then
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, S().LuckPassId)
	elseif what == "direct" then
		local item = type(key) == "string" and Crates.item(key)
		local ids = S().DirectBuyProductIds
		local id = directBuy() and item and type(ids) == "table" and ids[item.grade]
		if not validId(id) then
			return
		end
		pendingDirect[player] = key
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

-- Grants for a receipt; return true once granted (the receipt id is written with it).
local function grantFor(player: Player, productId: number, purchaseId: string): boolean
	-- Gold packs
	for _, pack in ipairs(Rewards.config().Economy.Packs or {}) do
		if robuxGold() and validId(pack.productId) and pack.productId == productId then
			call("DataService", "increment", player, "Gold", pack.gold)
			call("CurrencyService", "log", player, true, pack.gold, "IAP", pack.key)
			return true
		end
	end
	-- one crate (into Held: opened from the OPEN tab)
	for crateId, id in pairs(crateIds()) do
		if robuxCrates() and id == productId and Crates.ById[crateId] then
			return call("DataService", "updateEcon", player, function(e)
				e.Shop.Held[crateId] = (e.Shop.Held[crateId] or 0) + 1
			end) == true
		end
	end
	-- a Shelf item for Robux: the item the player chose, else another of that grade they do not own, else its Gold
	local ids = S().DirectBuyProductIds
	if directBuy() and type(ids) == "table" then
		for grade, id in pairs(ids) do
			if id == productId then
				local want = pendingDirect[player]
				local owned = ShopService.getOwned(player)
				local item = want and Crates.item(want)
				local pick = if item and item.grade == grade and owned[want] == nil then want else nil
				if not pick then
					pick = Crates.pickItem(grade, owned, rng)
				end
				if not pick then
					-- the whole grade is owned already: its Shelf price in Gold instead
					call("DataService", "increment", player, "Gold", Crates.shelfPrice(grade))
					return true
				end
				return call("DataService", "updateEcon", player, function(e)
					e.Shop.Owned[pick] = 0
				end) == true
			end
		end
	end
	local custom = products[productId]
	if custom then
		local ok, result = pcall(custom, player, { ProductId = productId, PurchaseId = purchaseId })
		return ok and result == true
	end
	return false
end

local granting: { [string]: boolean } = {}
local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player or not call("DataService", "isLoaded", player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(info.PurchaseId)
	if granting[id] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local shop = shopOf(player)
	if shop and table.find(shop.Receipts, id) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- granted before
	end
	granting[id] = true
	local goldBefore = tonumber(call("DataService", "get", player, "Gold")) or 0
	local econBefore = call("DataService", "getEcon", player)
	local ok = grantFor(player, info.ProductId, id)
	if ok then
		call("DataService", "updateEcon", player, function(e)
			table.insert(e.Shop.Receipts, 1, id)
			while #e.Shop.Receipts > 40 do
				table.remove(e.Shop.Receipts)
			end
		end)
	end
	-- saved (grant and receipt id in one write) before Roblox is told
	if not ok or call("DataService", "saveNow", player) ~= true then
		-- undo, so Roblox's retry cannot grant twice
		local goldNow = tonumber(call("DataService", "get", player, "Gold")) or 0
		if goldNow ~= goldBefore then
			call("DataService", "increment", player, "Gold", goldBefore - goldNow)
		end
		if econBefore then
			call("DataService", "updateEcon", player, function(e)
				e.Shop = econBefore.Shop
			end)
		end
		granting[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	granting[id] = nil
	pendingDirect[player] = nil
	ShopService.pushState(player)
	call("RewardsService", "pushState", player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
ShopService._processReceipt = processReceipt -- Studio tests
-- Studio tests only: as if the player owned the Lucky Charm pass (the switch and its id must still be set)
function ShopService._setLuck(player: Player, owned: boolean)
	if Config.IsStudio then
		luckOwned[player] = owned == true
	end
end

function ShopService.registerProduct(productId: number, fn: (Player, any) -> boolean)
	if validId(productId) and type(fn) == "function" then
		products[productId] = fn
		ShopService._ensureReceipts()
	end
end

local receiptsSet = false
function ShopService._ensureReceipts()
	if receiptsSet then
		return
	end
	local any = next(products) ~= nil or robuxCrates() or directBuy()
	if robuxGold() then
		for _, pack in ipairs(Rewards.config().Economy.Packs or {}) do
			if validId(pack.productId) then
				any = true
			end
		end
	end
	if any then
		receiptsSet = true
		MarketplaceService.ProcessReceipt = processReceipt
	end
end

-- Grants for other services --------------------------------------------------------------------------------------------

function ShopService.getOwned(player: Player): { [string]: number }
	local shop = shopOf(player)
	return if shop then shop.Owned else {}
end

function ShopService.owns(player: Player, id: string): boolean
	return ShopService.getOwned(player)[id] ~= nil
end

function ShopService.equipped(player: Player): { [string]: string }
	local shop = shopOf(player)
	return if shop then shop.Equipped else {}
end

function ShopService.grantCrate(player: Player, crateId: string, n: number?): boolean
	if not Crates.ById[crateId] then
		return false
	end
	local ok = call("DataService", "updateEcon", player, function(e)
		e.Shop.Held[crateId] = (e.Shop.Held[crateId] or 0) + math.max(1, math.floor(n or 1))
	end) == true
	if ok then
		call("DataService", "saveSoon", player)
		ShopService.pushState(player)
	end
	return ok
end

function ShopService.grantAcorns(player: Player, n: number?): boolean
	local max = tonumber(S().AcornMax) or 10
	local ok = call("DataService", "updateEcon", player, function(e)
		e.Shop.Acorns = math.min(max, (e.Shop.Acorns or 0) + math.max(1, math.floor(n or 1)))
	end) == true
	if ok then
		call("DataService", "saveSoon", player)
		ShopService.pushState(player)
	end
	return ok
end

function ShopService.grantCosmetic(player: Player, id: string): boolean
	if type(id) ~= "string" or #id > 32 then
		return false
	end
	local ok = call("DataService", "updateEcon", player, function(e)
		if e.Shop.Owned[id] == nil then
			e.Shop.Owned[id] = 0
		end
	end) == true
	if ok then
		call("DataService", "saveSoon", player)
		ShopService.pushState(player)
	end
	return ok
end

-- Lifecycle -------------------------------------------------------------------------------------------------------------

local function onEvent(player: Player, action: any, a: any, b: any, c: any)
	if type(action) ~= "string" then
		return
	end
	if action == "state" then
		if Net.rateLimit(player, "ShopState", 1, 4) then
			ShopService.pushState(player)
		end
		return
	end
	if not Net.rateLimit(player, "ShopAction", 2, 4) then
		return
	end
	if not inTrain(player) then
		return
	end
	if busy[player] then
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		if action == "buy" then
			buy(player, a, b, c)
		elseif action == "open" then
			openHeld(player, a, b)
		elseif action == "shelf" then
			shelfBuy(player, a)
		elseif action == "equip" then
			equip(player, a)
		elseif action == "robux" then
			promptRobux(player, a, b)
		end
	end)
	busy[player] = nil
	if not ok then
		warn("[ShopService] " .. tostring(action) .. " failed: " .. tostring(err))
	end
end

function ShopService.Init(services)
	Services = services
	remote = getRemote()
end

function ShopService.Start()
	local event = remote
	if not event then
		warn("[ShopService] no Remotes folder: CASES is off")
		return
	end
	local okCheck, problems = Crates.selfCheck()
	if not okCheck then
		warn("[ShopService] odds tables do not sum to 100: " .. table.concat(problems, "; "))
	end
	if not Config.IsStudio then
		local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, "ShopSerials_v1")
		if ok then
			serialStore = store
		end
	end
	event.OnServerEvent:Connect(onEvent)
	local function join(player: Player)
		task.spawn(fetchPolicy, player)
		task.spawn(refreshLuck, player)
		player:GetAttributeChangedSignal("Gold"):Connect(function()
			if remote then
				remote:FireClient(player, "gold", player:GetAttribute("Gold"))
			end
		end)
		task.delay(2, ShopService.pushState, player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		join(player)
	end
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(function(player)
		policy[player] = nil
		luckOwned[player] = nil
		busy[player] = nil
		pendingDirect[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if bought and passId == S().LuckPassId then
			luckOwned[player] = true
			ShopService.pushState(player)
		end
	end)
	-- the one receipt handler, after CurrencyService has started (this one handles the Gold packs too)
	task.defer(ShopService._ensureReceipts)
end

return ShopService
