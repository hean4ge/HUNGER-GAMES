--[[
	CurrencyService - Gold: what a round pays, the PolicyService answer per player, and Gold for Robux (designed, OFF).
	Numbers: Shared.Rewards (docs/design/Weapons_v2.md section 4.1). Saved by DataService (the Gold stat, Econ.Daily).

	Earning, from signals only (RoundService and PlayerService are not changed):
	  RoundService.roundStarted  every contender is noted with where they stood and when (Practice rounds pay nothing)
	  PlayerService.died         the time a contender fell
	  RoundService.roundEnded    Phase "Ending" (a cancelled Countdown pays nothing): each contender still on the server
	                             is paid by Rewards.roundGold from their Placement and Kills attributes, the minutes they
	                             lasted, the win (the Wins rule: 15 s or a defeat), the real head count and the daily cap
	  Taking part: moved AfkMove studs in the first AfkWindow seconds, or made a defeat, or lasted past that window
	  having moved at all. Private servers and practice rounds pay 0.
	  Nothing shows mid-round. The player gets "round" on the Rewards remote at the end; CurrencyController writes it on
	  the results board in the train ("Your round +62 Gold") and on the quiet Gold line while they are in the train.

	PolicyService (rules.md section 3): GetPolicyInfoForPlayerAsync once per player in a pcall, cached for the session.
	  CurrencyService.paidRandomBlocked(player) -> boolean
	    false while Economy.RobuxGold is off (Gold cannot be bought, so nothing paid with it is a paid random item);
	    with it on: true when ArePaidRandomItemsRestricted, and true when the call failed or has not answered yet.

	Gold for Robux (Economy.RobuxGold, OFF; no developer product exists or is created here):
	  With the switch on and a pack's productId set, MarketplaceService.ProcessReceipt is set once here. Each receipt is
	  granted once per PurchaseId: a receipt already in the "GoldReceipts_v1" store is acknowledged; otherwise the Gold
	  goes to the player's profile and is saved (DataService.saveNow), then the receipt is recorded, and only then
	  PurchaseGranted. A player not here, a profile not loaded or a failed save is NotProcessedYet (the Gold is taken
	  back so the retry cannot add it twice). A crash between the save and the record can only grant twice, never lose.
	  If another script ever needs ProcessReceipt, the handler must move to one place (rules.md section 7).

	API:
	  CurrencyService.balance(player) -> number
	  CurrencyService.creditChallenge(player)             an arena challenge done this round (paid at the end, 3 at most)
	  CurrencyService.lastRound(player) -> { gold, parts, balance }?
	  CurrencyService.paidRandomBlocked(player) -> boolean
]]
local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared:WaitForChild("Rewards"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local CurrencyService = {}

local REMOTE_NAME = "Rewards"
local SAMPLE_EVERY = 2

local Services: any = nil
local remote: RemoteEvent? = nil
local policy: { [Player]: { done: boolean, restricted: boolean } } = {}
local lastRounds: { [Player]: { [string]: any } } = {}

type Track = { start: Vector3?, moved: number, last: Vector3?, startedAt: number, diedAt: number?, challenges: number }
local round: { id: any, startedAt: number, tracks: { [Player]: Track }, headcount: number }? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function call(serviceName: string, method: string, ...): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[CurrencyService] %s.%s failed: %s", serviceName, method, tostring(result)))
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
CurrencyService._getRemote = getRemote

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function CurrencyService.balance(player: Player): number
	return tonumber(call("DataService", "get", player, "Gold")) or 0
end

-- Analytics (Weapons_v2 9.2: every change logged). Never lets a failure reach the caller.
function CurrencyService.log(player: Player, source: boolean, amount: number, transaction: string, sku: string?)
	if amount <= 0 then
		return
	end
	pcall(function()
		AnalyticsService:LogEconomyEvent(player,
			if source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			"Gold", amount, CurrencyService.balance(player), transaction, sku)
	end)
end

-- Policy ----------------------------------------------------------------------------------------------------------

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
	-- the call failed: treated as restricted for this session (rules.md checklist 5)
	entry.done = true
	entry.restricted = true
end

function CurrencyService.paidRandomBlocked(player: Player): boolean
	if Rewards.config().Economy.RobuxGold ~= true then
		return false
	end
	local entry = policy[player]
	return entry == nil or entry.restricted ~= false
end

-- Round earnings ----------------------------------------------------------------------------------------------------

-- A practice round pays nothing. Studio only: Workspace attribute RewardsPayPractice = true pays a solo test round
-- as a real one (a lone Studio player always gets a practice round).
local function unpaidPractice(): boolean
	if GameState:GetAttribute("Practice") ~= true then
		return false
	end
	return not (Rewards.config().IsStudio and workspace:GetAttribute("RewardsPayPractice") == true)
end

local function onRoundStarted(roundId: any)
	if unpaidPractice() then
		round = nil
		return
	end
	local startedAt = now()
	local tracks = {}
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local contender = call("RoundService", "isContender", player)
		if contender == true or (contender == nil and player:GetAttribute("Alive") == true) then
			local root = rootOf(player)
			tracks[player] = { start = root and root.Position, last = root and root.Position, moved = 0, startedAt = startedAt, challenges = 0 }
			count += 1
		end
	end
	local current = { id = roundId, startedAt = startedAt, tracks = tracks, headcount = count }
	round = current
	-- movement in the first AfkWindow seconds (one cheap sample per contender every 2 s)
	task.spawn(function()
		local window = Rewards.config().Economy.AfkWindow
		local t = 0
		while round == current and t < window do
			task.wait(SAMPLE_EVERY)
			t += SAMPLE_EVERY
			for player, track in pairs(current.tracks) do
				local root = rootOf(player)
				if root and not track.diedAt then
					local p = root.Position
					if track.last then
						local step = (p - track.last).Magnitude
						if step < 200 then -- not a teleport (the launch hand-off)
							track.moved += step
						end
					end
					track.last = p
				end
			end
		end
	end)
end

local function onDied(victim: Player)
	local current = round
	local track = current and current.tracks[victim]
	if track and not track.diedAt and GameState:GetAttribute("Phase") == "Active" then
		track.diedAt = now()
	end
end

function CurrencyService.creditChallenge(player: Player)
	local current = round
	local track = current and current.tracks[player]
	if track then
		track.challenges += 1
	end
end

local function send(player: Player, ...)
	local event = remote
	if event and player.Parent == Players then
		event:FireClient(player, ...)
	end
end

local function payRound(player: Player, track: Track, current, winner: Player?, endedAt: number)
	local E = Rewards.config().Economy
	local kills = math.floor(tonumber(player:GetAttribute("Kills")) or 0)
	local lasted = (track.diedAt or endedAt) - track.startedAt
	local tookPart = track.moved >= E.AfkMove or kills > 0 or (lasted >= E.AfkWindow and track.moved > 2)
	local won = winner == player and (endedAt - current.startedAt >= 15 or kills > 0)
	local place = math.floor(tonumber(player:GetAttribute("Placement")) or 0)
	local headcount = current.headcount
	if Rewards.config().IsStudio and E.StudioIgnoreHeadcount then
		headcount = math.max(headcount, E.FullRewardsFrom)
	end
	local econ = call("DataService", "getEcon", player)
	local loaded = call("DataService", "isLoaded", player) == true
	local today = Rewards.utcDay()
	local daily = econ and econ.Daily or {}
	local sameDay = daily.day == today
	local args = {
		tookPart = tookPart,
		place = place,
		contenders = headcount,
		defeats = kills,
		minutes = lasted / 60,
		won = won,
		practice = false,
		private = game.PrivateServerId ~= "" and not Rewards.config().IsStudio,
		challenges = track.challenges,
		dayGoldSoFar = if sameDay then daily.roundGold or 0 else 0,
		-- the daily bonuses need the saved day, so they wait for a loaded profile
		firstRoundOfDay = loaded and tookPart and not (sameDay and daily.firstRound),
		firstWinOfDay = loaded and won and not (sameDay and daily.firstWin),
	}
	local total, parts = Rewards.roundGold(args)
	if total > 0 then
		call("DataService", "increment", player, "Gold", total)
		CurrencyService.log(player, true, total, "Gameplay", "RoundReward")
	end
	if loaded and tookPart then
		local roundOnly = total - (parts.firstRound or 0) - (parts.firstWin or 0)
		call("DataService", "updateEcon", player, function(e)
			if e.Daily.day ~= today then
				e.Daily = { day = today, free = 0, paid = 0, roundGold = 0, firstRound = false, firstWin = false }
			end
			e.Daily.roundGold += math.max(0, roundOnly)
			if parts.firstRound then
				e.Daily.firstRound = true
			end
			if parts.firstWin then
				e.Daily.firstWin = true
			end
		end)
	end
	local result = { gold = total, parts = parts, balance = CurrencyService.balance(player), roundId = current.id,
		tookPart = tookPart }
	lastRounds[player] = result
	send(player, "round", result)
end

local function onRoundEnded(winner: Player?)
	local current = round
	round = nil
	if not current or GameState:GetAttribute("Phase") ~= "Ending" or unpaidPractice() then
		return
	end
	local endedAt = now()
	for player, track in pairs(current.tracks) do
		if player.Parent == Players then
			local ok, err = pcall(payRound, player, track, current, winner, endedAt)
			if not ok then
				warn("[CurrencyService] paying " .. player.Name .. " failed: " .. tostring(err))
			end
		end
	end
end

function CurrencyService.lastRound(player: Player): { [string]: any }?
	return lastRounds[player]
end

-- Gold for Robux (OFF) -------------------------------------------------------------------------------------------------

local receipts: DataStore? = nil
local granting: { [string]: boolean } = {}

local function packFor(productId: number): { [string]: any }?
	for _, pack in ipairs(Rewards.config().Economy.Packs or {}) do
		if pack.productId and pack.productId > 0 and pack.productId == productId then
			return pack
		end
	end
	return nil
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local pack = packFor(info.ProductId)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not pack or not player or not receipts then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not call("DataService", "isLoaded", player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(info.PurchaseId)
	if granting[id] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	granting[id] = true
	local key = "Receipt_" .. id
	-- 1. granted before (on any server)?
	local readOk, record = pcall(function()
		return (receipts :: DataStore):GetAsync(key)
	end)
	if not readOk then
		granting[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if record ~= nil then
		granting[id] = nil
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- 2. the Gold, saved before anything is acknowledged; a failed save takes it back and Roblox asks again later
	call("DataService", "increment", player, "Gold", pack.gold)
	if call("DataService", "saveNow", player) ~= true then
		call("DataService", "increment", player, "Gold", -pack.gold)
		granting[id] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- 3. the record (a failure here can only grant twice, never lose a purchase)
	local writeOk, err = pcall(function()
		(receipts :: DataStore):SetAsync(key, { userId = info.PlayerId, gold = pack.gold, at = os.time() })
	end)
	if not writeOk then
		warn("[CurrencyService] receipt " .. id .. " granted but not recorded: " .. tostring(err))
	end
	CurrencyService.log(player, true, pack.gold, "IAP", pack.key)
	call("RewardsService", "pushState", player)
	granting[id] = nil
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function CurrencyService.Init(services)
	Services = services
	remote = getRemote()
end

function CurrencyService.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(fetchPolicy, player)
	end
	Players.PlayerAdded:Connect(fetchPolicy)
	Players.PlayerRemoving:Connect(function(player)
		policy[player] = nil
		lastRounds[player] = nil
		local current = round
		if current then
			current.tracks[player] = nil
		end
	end)
	local rs = Services and Services.RoundService
	local ps = Services and Services.PlayerService
	if rs and rs.roundStarted and rs.roundEnded then
		rs.roundStarted:Connect(onRoundStarted)
		rs.roundEnded:Connect(onRoundEnded)
	else
		warn("[CurrencyService] RoundService signals missing: rounds pay no Gold")
	end
	if ps and ps.died then
		ps.died:Connect(onDied)
	end
	local E = Rewards.config().Economy
	if E.RobuxGold == true then
		local any = false
		for _, pack in ipairs(E.Packs or {}) do
			if pack.productId and pack.productId > 0 then
				any = true
			end
		end
		if any then
			local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, "GoldReceipts_v1")
			if ok then
				receipts = store
				MarketplaceService.ProcessReceipt = processReceipt
			end
		end
	end
end

return CurrencyService
