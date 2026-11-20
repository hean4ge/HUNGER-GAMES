--[[
	SeasonService - the Season Track (docs/design/CardMenusAndShop.md 2.6 and 3.6), XP from rounds and training, and
	the one "Progress" remote and reward granting that DailyService, RankService and LeaderboardService share.
	Numbers: Shared.Progression. Saved by DataService in Econ.Progress (shape: Progression.sanitize).

	XP (from signals only; RoundService, PlayerService and TrainingService are not changed):
	  RoundService.roundStarted  every contender noted with the start time (practice rounds give 0)
	  PlayerService.died         when a contender fell
	  RoundService.roundEnded    Phase "Ending": Progression.roundXP from Placement, Kills, minutes lasted, the win and
	                             the real head count (full from 8, half from 4, as Gold). Taking part is read from
	                             CurrencyService.lastRound (its AFK rule), else "lasted a minute or made a defeat".
	                             Private servers and practice rounds give 0. Studio: Workspace attribute
	                             RewardsPayPractice = true counts a solo practice round (as Gold does).
	  TrainingService.passed     Ranks.TrainingXP per drill passed, at most Ranks.TrainingPerDay a UTC day
	  The same XP goes to the Season Track and to the Level (RankService.addXP). LeaderboardService gets the round.

	Track: 50 tiers of TierXP; free row for everyone, premium row only with Config.Shop.SeasonPremium AND a product id
	(both off: the client never sees the row). After tier 50 every EncoreXP is an Encore (paid when claimed). A new
	season id clears the track (rewards still unclaimed are granted first: nothing is lost).

	Granting (SeasonService.grant(player, reward) -> boolean): Gold here (DataService); crates, Acorns and catalogue
	items through ShopService (grantCrate / grantAcorns / grantCosmetic), trails through TrailService.grant when it
	exists, wheel spins through RewardsService.grantSpins when it exists; titles, trims and stamps are kept here
	(Progress.Honours). Anything whose service is missing or refuses waits in Progress.Owed and is tried again on join
	and every minute, so a claim never loses a reward.

	Remote ReplicatedStorage.Remotes.Progress (created here in Init; not in Net.Names, like RoundResult):
	  client -> server  { t = "get" } · { t = "claim", row = "free" | "prem", tier } · { t = "claimAll" }
	                    { t = "encore" } · { t = "buyPremium" } · { t = "daily" } · { t = "prestige" }
	                    { t = "rankSeen" } · { t = "boards", board, scope }
	  server -> client  { t = "state", s = state } · { t = "claimed", what, rewards } · { t = "rankup", ... }
	                    { t = "levelup", level, gold } · { t = "boards", ... } · { t = "round", xp, parts }
	API: SeasonService.grant, SeasonService.push(player), SeasonService.remote(), SeasonService.addSeasonXP(player, n)
	     SeasonService.progress(player) -> Progress copy, SeasonService.edit(player, fn(progress)) -> boolean
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local SeasonService = {}

local REMOTE_NAME = "Progress"

local Services: any = nil
local remote: RemoteEvent? = nil
local handlers: { [string]: (Player, { [string]: any }) -> () } = {}

type Track = { startedAt: number, diedAt: number? }
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
		warn(string.format("[SeasonService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function has(serviceName: string, method: string): boolean
	local service = Services and Services[serviceName]
	return service ~= nil and type(service[method]) == "function"
end

function SeasonService.remote(): RemoteEvent?
	return remote
end

function SeasonService.send(player: Player, msg: { [string]: any })
	local event = remote
	if event and player.Parent == Players then
		event:FireClient(player, msg)
	end
end

-- handlers for the other progress services: SeasonService.on("daily", fn(player, msg))
function SeasonService.on(t: string, fn: (Player, { [string]: any }) -> ())
	handlers[t] = fn
end

--------------------------------------------------------------------------------------------------------------------
-- Progress access
--------------------------------------------------------------------------------------------------------------------

function SeasonService.progress(player: Player): { [string]: any }?
	local econ = call("DataService", "getEcon", player)
	return if type(econ) == "table" then econ.Progress else nil
end

-- fn(progress) edits it in place; false until the profile has loaded
function SeasonService.edit(player: Player, fn: ({ [string]: any }) -> ()): boolean
	return call("DataService", "updateEcon", player, function(e)
		e.Progress = Progression.sanitize(e.Progress)
		fn(e.Progress)
	end) == true
end

--------------------------------------------------------------------------------------------------------------------
-- Granting
--------------------------------------------------------------------------------------------------------------------

local KEPT_HERE = { title = true, trim = true, stamp = true, slot = true }

-- One try at handing a reward to the service that holds it. true = it is the player's now.
local function deliver(player: Player, r: { [string]: any }): boolean
	local k = r.k
	if k == "gold" then
		local n = math.floor(tonumber(r.n) or 0)
		if n > 0 then
			call("DataService", "increment", player, "Gold", n)
			call("CurrencyService", "log", player, true, n, "Gameplay", "Progress")
		end
		return true
	elseif k == "crate" then
		return call("ShopService", "grantCrate", player, r.id, r.n or 1) == true
	elseif k == "acorn" then
		return call("ShopService", "grantAcorns", player, r.n or 1) == true
	elseif k == "cosmetic" then
		if has("ShopService", "grantCosmetic") and call("ShopService", "grantCosmetic", player, r.id) == true then
			return true
		end
		return call("CosmeticService", "grant", player, r.id) == true
	elseif k == "trail" then
		if has("TrailService", "grant") then
			return call("TrailService", "grant", player, r.id) == true
		end
		-- the trail must be in Shared.Trails (a season trail not added yet waits in Owed)
		local okTrails, Trails = pcall(require, Shared:FindFirstChild("Trails") :: any)
		if not okTrails or type(Trails) ~= "table" or not (Trails.ById and Trails.ById[r.id]) then
			return false
		end
		return call("DataService", "updateEcon", player, function(e)
			e.Trails.Owned[r.id] = true
		end) == true
	elseif k == "spins" then
		return call("RewardsService", "grantSpins", player, r.n or 1) == true
	end
	return false
end

-- Grants one reward. Titles, trims and stamps are kept in Progress; the rest goes to its service, or waits in Owed.
-- Must be called after the claim is marked (so a retry can never pay twice). Returns true when delivered now.
function SeasonService.grant(player: Player, r: { [string]: any }): boolean
	if KEPT_HERE[r.k] then
		if r.k == "slot" then
			return true -- loadout slots follow the Level (RankService.loadoutSlots)
		end
		SeasonService.edit(player, function(p)
			if r.k == "stamp" then
				p.Daily.stamps += 1
			else
				p.Honours[(r.k .. ":" .. tostring(r.id)):sub(1, 40)] = true
			end
		end)
		return true
	end
	if deliver(player, r) then
		return true
	end
	SeasonService.edit(player, function(p)
		if #p.Owed < 64 then
			table.insert(p.Owed, { k = r.k, id = r.id, n = r.n or 1 })
		end
	end)
	return false
end

local function grantAll(player: Player, list: { { [string]: any } })
	for _, r in ipairs(list) do
		SeasonService.grant(player, r)
	end
end

-- Rewards still owed: tried again (on join and every minute)
local function drainOwed(player: Player)
	local p = SeasonService.progress(player)
	if not p or #p.Owed == 0 then
		return
	end
	local delivered = {}
	for i, o in ipairs(p.Owed) do
		if deliver(player, o) then
			delivered[i] = true
		end
	end
	if next(delivered) then
		SeasonService.edit(player, function(q)
			local keep = {}
			for i, o in ipairs(q.Owed) do
				if not delivered[i] then
					table.insert(keep, o)
				end
			end
			q.Owed = keep
		end)
		SeasonService.push(player)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- State for the client
--------------------------------------------------------------------------------------------------------------------

local function claimed(bits: string, tier: number): boolean
	return string.sub(bits, tier, tier) == "1"
end

local function setBit(bits: string, tier: number): string
	local s = bits
	if #s < tier then
		s ..= string.rep("0", tier - #s)
	end
	return string.sub(s, 1, tier - 1) .. "1" .. string.sub(s, tier + 1)
end

-- A season id that is not the current one: whatever free (and bought premium) tiers were reached but not claimed are
-- granted now, then the track starts again.
local function rollSeason(player: Player)
	local cfg = Progression.config()
	local p = SeasonService.progress(player)
	if not p or p.Season.id == cfg.Season.Id then
		return
	end
	local old = p.Season
	local owed = {}
	if old.id ~= "" then
		local tier = Progression.tierOf(old.xp)
		for t = 1, tier do
			if not claimed(old.free, t) then
				table.insert(owed, Progression.FreeRow[t])
			end
			if old.premium and not claimed(old.prem, t) then
				table.insert(owed, Progression.PremiumRow[t])
			end
		end
	end
	local ok = SeasonService.edit(player, function(q)
		q.Season = { id = cfg.Season.Id, xp = 0, free = "", prem = "", premium = false, encore = 0 }
	end)
	if ok then
		grantAll(player, owed)
	end
end

function SeasonService.state(player: Player): { [string]: any }?
	local p = SeasonService.progress(player)
	if not p then
		return nil
	end
	local cfg = Progression.config()
	local start, finish, running = Progression.seasonWindow(os.time())
	local tier, into, need, encores = Progression.tierOf(p.Season.xp)
	local level, lInto, lNeed = Progression.levelOf(p.XP)
	local slots = call("RankService", "loadoutSlots", player) or 2
	return {
		loaded = call("DataService", "isLoaded", player) == true,
		now = os.time(),
		season = {
			id = cfg.Season.Id, name = cfg.Season.Name, start = start, finish = finish, running = running,
			xp = p.Season.xp, tier = tier, into = into, need = need, tiers = cfg.Season.Tiers,
			free = p.Season.free, prem = p.Season.prem, premium = p.Season.premium,
			premiumOn = cfg.PremiumOn, encores = encores, encoreClaimed = p.Season.encore,
		},
		level = { xp = p.XP, level = level, into = lInto, need = lNeed, prestige = p.Prestige, band = Progression.bandOf(level),
			bandShown = p.BandShown, slots = slots },
		daily = call("DailyService", "view", player, p),
		week = p.Week,
		owed = #p.Owed,
		honours = p.Honours,
		gold = tonumber(call("DataService", "get", player, "Gold")) or 0,
	}
end

function SeasonService.push(player: Player)
	local s = SeasonService.state(player)
	if s then
		SeasonService.send(player, { t = "state", s = s })
	end
end

--------------------------------------------------------------------------------------------------------------------
-- XP
--------------------------------------------------------------------------------------------------------------------

-- Season XP only (the Level gets the same XP through RankService.addXP, which calls this)
function SeasonService.addSeasonXP(player: Player, n: number)
	if n <= 0 then
		return
	end
	rollSeason(player)
	local _, _, running = Progression.seasonWindow(os.time())
	if not running then
		return
	end
	SeasonService.edit(player, function(p)
		p.Season.xp += math.floor(n)
	end)
end

local function addXP(player: Player, n: number, reason: string)
	if has("RankService", "addXP") then
		call("RankService", "addXP", player, n, reason) -- the Level, and it calls addSeasonXP
	else
		SeasonService.addSeasonXP(player, n)
	end
end

local function unpaidPractice(): boolean
	if GameState:GetAttribute("Practice") ~= true then
		return false
	end
	return not (Progression.config().IsStudio and workspace:GetAttribute("RewardsPayPractice") == true)
end

local function onRoundStarted(roundId: any)
	if unpaidPractice() then
		round = nil
		return
	end
	local tracks = {}
	local count = 0
	local t = now()
	for _, player in ipairs(Players:GetPlayers()) do
		local contender = call("RoundService", "isContender", player)
		if contender == true or (contender == nil and player:GetAttribute("Alive") == true) then
			tracks[player] = { startedAt = t }
			count += 1
		end
	end
	round = { id = roundId, startedAt = t, tracks = tracks, headcount = count }
end

local function onDied(victim: Player)
	local current = round
	local track = current and current.tracks[victim]
	if track and not track.diedAt and GameState:GetAttribute("Phase") == "Active" then
		track.diedAt = now()
	end
end

local function payRound(player: Player, track: Track, current, winner: Player?, endedAt: number)
	local kills = math.floor(tonumber(player:GetAttribute("Kills")) or 0)
	local lasted = (track.diedAt or endedAt) - track.startedAt
	local won = winner == player and (endedAt - current.startedAt >= 15 or kills > 0)
	local place = math.floor(tonumber(player:GetAttribute("Placement")) or 0)
	local last = call("CurrencyService", "lastRound", player)
	local tookPart = if type(last) == "table" and last.roundId == current.id and last.tookPart ~= nil
		then last.tookPart == true else (kills > 0 or lasted >= 60)
	local headcount = current.headcount
	local studioFull = Progression.config().IsStudio and workspace:GetAttribute("ProgressIgnoreHeadcount") ~= false
	if studioFull then
		headcount = math.max(headcount, Progression.RoundXP.FullFrom)
	end
	local private = game.PrivateServerId ~= "" and not Progression.config().IsStudio
	local total, parts = Progression.roundXP({ tookPart = tookPart, place = place, contenders = headcount, defeats = kills,
		minutes = lasted / 60, won = won, private = private })
	if total > 0 then
		addXP(player, total, "round")
	end
	SeasonService.send(player, { t = "round", xp = total, parts = parts })
	-- the boards (only rounds with 8+ real contenders count; LeaderboardService checks)
	if tookPart and not private then
		call("LeaderboardService", "recordRound", player, {
			won = won, kills = kills, place = place, survived = math.floor(lasted), contenders = headcount,
			realContenders = current.headcount,
		})
	end
end

local function onRoundEnded(winner: Player?)
	local current = round
	round = nil
	if not current or GameState:GetAttribute("Phase") ~= "Ending" or unpaidPractice() then
		return
	end
	local endedAt = now()
	-- after CurrencyService has paid (its taking-part answer is read here)
	task.delay(0.5, function()
		for player, track in pairs(current.tracks) do
			if player.Parent == Players then
				local ok, err = pcall(payRound, player, track, current, winner, endedAt)
				if not ok then
					warn("[SeasonService] XP for " .. player.Name .. " failed: " .. tostring(err))
				end
				SeasonService.push(player)
			end
		end
	end)
end

local function onTrainingPassed(player: Player, _drillId: any)
	local R = Progression.config().Ranks
	local today = Progression.utcDay()
	local paid = false
	SeasonService.edit(player, function(p)
		if p.Train.day ~= today then
			p.Train = { day = today, n = 0 }
		end
		if p.Train.n < R.TrainingPerDay then
			p.Train.n += 1
			paid = true
		end
	end)
	if paid then
		addXP(player, R.TrainingXP, "training")
		SeasonService.push(player)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Claims
--------------------------------------------------------------------------------------------------------------------

local function claimTier(player: Player, row: string, tier: number): { { [string]: any } }?
	local cfg = Progression.config()
	local p = SeasonService.progress(player)
	if not p or p.Season.id ~= cfg.Season.Id then
		return nil
	end
	if tier < 1 or tier > cfg.Season.Tiers or tier ~= math.floor(tier) then
		return nil
	end
	local reached = Progression.tierOf(p.Season.xp)
	if tier > reached then
		return nil
	end
	local reward: { [string]: any }? = nil
	if row == "free" then
		if claimed(p.Season.free, tier) then
			return nil
		end
		reward = Progression.FreeRow[tier]
	elseif row == "prem" then
		if not (cfg.PremiumOn and p.Season.premium) or claimed(p.Season.prem, tier) then
			return nil
		end
		reward = Progression.PremiumRow[tier]
	else
		return nil
	end
	local ok = SeasonService.edit(player, function(q)
		if row == "free" then
			q.Season.free = setBit(q.Season.free, tier)
		else
			q.Season.prem = setBit(q.Season.prem, tier)
		end
	end)
	if not ok or not reward then
		return nil
	end
	SeasonService.grant(player, reward)
	return { reward }
end

local function onClaim(player: Player, msg: { [string]: any })
	local tier = tonumber(msg.tier)
	if not tier then
		return
	end
	rollSeason(player)
	local got = claimTier(player, tostring(msg.row), tier)
	if got then
		SeasonService.send(player, { t = "claimed", what = "tier", row = msg.row, tier = tier, rewards = got })
		call("DataService", "saveSoon", player)
	end
	SeasonService.push(player)
end

local function onClaimAll(player: Player)
	rollSeason(player)
	local p = SeasonService.progress(player)
	if not p then
		return
	end
	local reached = Progression.tierOf(p.Season.xp)
	local all = {}
	for t = 1, reached do
		for _, row in ipairs({ "free", "prem" }) do
			local got = claimTier(player, row, t)
			if got then
				table.insert(all, got[1])
			end
		end
	end
	if #all > 0 then
		SeasonService.send(player, { t = "claimed", what = "all", rewards = all })
		call("DataService", "saveSoon", player)
	end
	SeasonService.push(player)
end

local function onEncore(player: Player)
	local p = SeasonService.progress(player)
	if not p then
		return
	end
	local _, _, _, encores = Progression.tierOf(p.Season.xp)
	if p.Season.encore >= encores then
		return
	end
	local n = p.Season.encore + 1
	if not SeasonService.edit(player, function(q)
		q.Season.encore = n
	end) then
		return
	end
	local list = Progression.encoreReward(n)
	grantAll(player, list)
	SeasonService.send(player, { t = "claimed", what = "encore", encore = n, rewards = list })
	call("DataService", "saveSoon", player)
	SeasonService.push(player)
end

-- Premium (designed, OFF): only with Config.Shop.SeasonPremium and a product id. The receipt goes through ShopService's
-- one receipt handler (registerProduct): granted once, saved before PurchaseGranted.
local function onBuyPremium(player: Player)
	local cfg = Progression.config()
	if not cfg.PremiumOn or not cfg.PremiumProductId then
		return
	end
	local p = SeasonService.progress(player)
	if not p or p.Season.premium then
		return
	end
	pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, cfg.PremiumProductId)
end

local function grantPremium(player: Player, _info: any): boolean
	rollSeason(player)
	local ok = SeasonService.edit(player, function(p)
		p.Season.premium = true
	end)
	if ok then
		SeasonService.push(player)
	end
	return ok
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

local RATE = { get = { 1, 4 }, claim = { 6, 12 }, claimAll = { 0.5, 2 }, encore = { 1, 3 }, buyPremium = { 0.5, 2 },
	daily = { 1, 3 }, prestige = { 0.2, 1 }, rankSeen = { 1, 3 }, boards = { 2, 8 } }

local function onEvent(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.t) ~= "string" then
		return
	end
	local rate = RATE[msg.t]
	if not rate or not Net.rateLimit(player, "Progress_" .. msg.t, rate[1], rate[2]) then
		return
	end
	if msg.t == "get" then
		rollSeason(player)
		SeasonService.push(player)
	elseif msg.t == "claim" then
		onClaim(player, msg)
	elseif msg.t == "claimAll" then
		onClaimAll(player)
	elseif msg.t == "encore" then
		onEncore(player)
	elseif msg.t == "buyPremium" then
		onBuyPremium(player)
	elseif handlers[msg.t] then
		local ok, err = pcall(handlers[msg.t], player, msg)
		if not ok then
			warn("[SeasonService] " .. msg.t .. " failed: " .. tostring(err))
		end
	end
end

local function onJoined(player: Player)
	-- wait for the profile, then settle the season and anything owed
	for _ = 1, 120 do
		if player.Parent ~= Players then
			return
		end
		if call("DataService", "isLoaded", player) == true then
			break
		end
		task.wait(1)
	end
	rollSeason(player)
	drainOwed(player)
	SeasonService.push(player)
end

function SeasonService.Init(services)
	Services = services
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		return
	end
	local existing = folder:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_NAME
		created.Parent = folder
		remote = created
	end
end

function SeasonService.Start()
	if remote then
		remote.OnServerEvent:Connect(onEvent)
	end
	local rs = Services and Services.RoundService
	if rs and rs.roundStarted and rs.roundEnded then
		rs.roundStarted:Connect(onRoundStarted)
		rs.roundEnded:Connect(onRoundEnded)
	else
		warn("[SeasonService] RoundService signals missing: rounds give no XP")
	end
	local ps = Services and Services.PlayerService
	if ps and ps.died then
		ps.died:Connect(onDied)
	end
	local ts = Services and Services.TrainingService
	if ts and ts.passed then
		ts.passed:Connect(onTrainingPassed)
	end
	local cfg = Progression.config()
	if cfg.PremiumOn and cfg.PremiumProductId then
		call("ShopService", "registerProduct", cfg.PremiumProductId, grantPremium)
	end
	-- Studio tests: the command bar has its own copy of every module, so it reaches the live services through this
	-- BindableFunction: ServerStorage.ProgressTest:Invoke(serviceName, methodName, ...) -> result
	if cfg.IsStudio then
		local bf = Instance.new("BindableFunction")
		bf.Name = "ProgressTest"
		bf.OnInvoke = function(serviceName: string, method: string, ...)
			if serviceName == "fakeStores" then
				-- an in-memory player store made here (a function cannot cross from the command bar's VM)
				local data = {}
				local store = {}
				function store:GetAsync(k)
					return data[k]
				end
				function store:UpdateAsync(k, fn)
					local v = fn(data[k])
					if v ~= nil then
						data[k] = v
					end
					return data[k]
				end
				SeasonService._testData = data
				call("DataService", "useTestStore", store)
				call("LeaderboardService", "useTestStores")
				for _, p in ipairs(Players:GetPlayers()) do
					call("DataService", "testRejoin", p)
					task.spawn(onJoined, p)
				end
				return "fake stores on"
			elseif serviceName == "holdLobby" then
				-- no round starts while a menu test runs (two players needed, no solo practice)
				local okCfg, Config = pcall(require, Shared:FindFirstChild("Config") :: any)
				if okCfg and type(Config) == "table" and Config.Round then
					Config.Round.MinPlayers = 2
					Config.Round.SoloPractice = false
				end
				return "lobby held"
			end
			local service = Services and Services[serviceName]
			local fn = service and service[method]
			if type(fn) ~= "function" then
				return "no " .. tostring(serviceName) .. "." .. tostring(method)
			end
			return fn(...)
		end
		bf.Parent = game:GetService("ServerStorage")
	end
	Players.PlayerAdded:Connect(onJoined)
	Players.PlayerRemoving:Connect(function(player)
		local current = round
		if current then
			current.tracks[player] = nil
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onJoined, player)
	end
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(drainOwed, player)
		end
	end
end

return SeasonService
