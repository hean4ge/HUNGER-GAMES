--[[
	RewardsService - the wheel, Strongboxes and the Armoury in the train (docs/design/Weapons_v2.md sections 2.6, 4.2, 5),
	server side. Every draw is rolled here; clients only animate what this sends. Numbers and odds: Shared.Rewards.
	The objects are workspace.Lobby.Rewards (ServerStorage.WorldGen.WheelBuilder): Wheel, Case, Masterwork, Armoury.

	Remote ReplicatedStorage.Remotes.Rewards (created in Init, like ResultsBoardService's RoundResult):
	  client -> server
	    "state"                 ask for your state
	    "spin"                  spin the wheel (free if today's free spin is left, else SpinCost Gold)
	    "box", "strongbox" | "masterwork"
	    "buy", weaponId         Armoury: a pool weapon at 3 stars, Buy3 Gold (no chance)
	    "raise", weaponId       Armoury: 3 -> 4 (Raise4) or 4 -> 5 (Raise5)
	    "bring", weaponId | ""  the owned weapon to bring next round ("" = the kit's own weapon)
	  server -> client
	    "state", State          to you: after a change, and when you ask
	    "spin", Spin            to everyone (others in the car watch it); Spin = { userId, name, segment, angle,
	                            startAt (server time), duration, paid, prize }
	    "box", Box              to everyone; Box = { userId, name, kind, startAt, prize }
	    "line", text            to you: one quiet line (not enough Gold, the wheel is turning, ...)
	    "round", RoundGold      to you, from CurrencyService at the end of a round
	  prize = { kind = "gold" | "weapon", gold?, id?, name?, stars?, before? (stars owned before), duplicate?, goldBack? }
	  State = { loaded, gold, freeLeft, paidLeft, spinCost, armoury, bring, pity = { wheel4, box4, box5 } (draws left
	            until certain), paidBlocked, robuxGold, busyUntil }

	Rules kept (scratchpad wave8/rules/rules.md; Shared.Rewards header):
	  * odds are shown before every draw (the plaque, the odds line, the Armoury board); stars are outcomes in them
	  * no losing outcome: every wheel segment and box gives Gold or a weapon; a paid Gold segment pays at least the
	    stake; a paid duplicate gives back at least the stake
	  * paid random draws are refused on the server for CurrencyService.paidRandomBlocked players (only ever true with
	    Economy.RobuxGold on); their free daily spin and the Armoury stay
	  * pity (a probability modifier) is shown as a number of draws left, per player
	One spin on the wheel at a time (it is one physical wheel), one box at a time at the case, one draw per player at
	a time. Only players in the train and near the object can draw. A draw saves within a few seconds (saveSoon).

	The owned weapon a player brings (Weapons_v2 2.6) arrives with the kit at the midpoint. When KitService exists
	(stars-kits) its parcel delivers it (it reads Econ.Bring), unless it sets KitService.deliversOwnedWeapon = false;
	BRING on the Armoury board goes through KitService.setBring, and every state push calls KitService.refreshArmoury
	(when it has one) so its KitArmoury list follows new prizes.
	Without KitService this service hands it over itself, into the bag, at the same moment (Config.Kits.Delivery "Start" =
	at the launch, else the midpoint: the earlier of half of MaxRoundTime and half the contenders out, never before
	240 s; practice 60 s). Studio only: Workspace attribute RewardsDeliveryTest = seconds after the horn.

	API:
	  RewardsService.getBring(player) -> (weaponId?, stars?)   the owned weapon to bring this round, if any
	  RewardsService.getArmoury(player) -> { [id] = stars }
	  RewardsService.pushState(player)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rewards = require(Shared:WaitForChild("Rewards"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local RewardsService = {}

local REMOTE_NAME = "Rewards"
local USE_DISTANCE = 16 -- studs from the object's prompt part
local BOX_TIME = 5.5 -- seconds the case is busy with a box reveal
local REVEAL_TIME = 4.5 -- after the wheel stops

local Services: any = nil
local remote: RemoteEvent? = nil
local rng = Random.new()
local wheelBusyUntil = 0
local caseBusyUntil = 0
local playerBusy: { [Player]: number } = {}

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
		warn(string.format("[RewardsService] %s.%s failed: %s", serviceName, method, tostring(result)))
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
	if remote then
		remote:FireClient(player, "line", text)
	end
end

local function corner(): Instance?
	local lobby = workspace:FindFirstChild("Lobby")
	return lobby and lobby:FindFirstChild("Rewards")
end

-- the part a player must stand near for an object ("Wheel", "Case", "Masterwork", "Armoury")
local function anchorOf(name: string): BasePart?
	local c = corner()
	local obj = c and c:FindFirstChild(name)
	local spot = obj and obj:FindFirstChild("PromptSpot", true)
	return if spot and spot:IsA("BasePart") then spot else nil
end

local function near(player: Player, name: string): boolean
	local spot = anchorOf(name)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not spot or not root or not root:IsA("BasePart") then
		return false
	end
	-- in the train, not in the arena: an alive contender in a round cannot draw
	if player:GetAttribute("Alive") == true and GameState:GetAttribute("Phase") == "Active" then
		local contender = call("RoundService", "isContender", player)
		if contender ~= false then
			return false
		end
	end
	return (root.Position - spot.Position).Magnitude <= USE_DISTANCE
end

-- CASES (ShopController) sends the same actions with a "menu" flag: allowed anywhere in the train, never by an alive
-- contender in a round. The draw still plays its reveal at the steel case, where others in the car watch.
local function inTrain(player: Player): boolean
	if player:GetAttribute("Alive") == true and GameState:GetAttribute("Phase") == "Active" then
		local contender = call("RoundService", "isContender", player)
		if contender ~= false then
			return false
		end
	end
	return true
end

local function reachable(player: Player, name: string, menu: boolean?): boolean
	if menu == true then
		return inTrain(player)
	end
	return near(player, name)
end

-- Paid random draws refused: CurrencyService's answer (Gold for Robux) or ShopService's (any Robux switch of the shop)
local function blocked(player: Player): boolean
	return call("CurrencyService", "paidRandomBlocked", player) == true
		or call("ShopService", "paidRandomRestricted", player) == true
end

local function today(): string
	return Rewards.utcDay()
end

local function freshDaily(e: any)
	if e.Daily.day ~= today() then
		e.Daily = { day = today(), free = 0, paid = 0, roundGold = 0, firstRound = false, firstWin = false }
	end
end

function RewardsService.getArmoury(player: Player): { [string]: number }
	local econ = call("DataService", "getEcon", player)
	return if econ then econ.Armoury else {}
end

-- Free wheel spins given (the daily reward's day 4: SeasonService / DailyService). They wait in Econ.BonusSpins and
-- are used after the day's own free spin, before any paid one. True once saved.
function RewardsService.grantSpins(player: Player, n: number): boolean
	n = math.floor(tonumber(n) or 0)
	if n <= 0 or not call("DataService", "isLoaded", player) then
		return false
	end
	local ok = call("DataService", "updateEcon", player, function(e)
		e.BonusSpins = math.min(20, (tonumber(e.BonusSpins) or 0) + n)
	end)
	if not ok then
		return false
	end
	call("DataService", "saveSoon", player)
	RewardsService.pushState(player)
	return true
end

function RewardsService.getBring(player: Player): (string?, number?)
	local econ = call("DataService", "getEcon", player)
	if not econ or econ.Bring == "" or not Rewards.InPool[econ.Bring] then
		return nil, nil
	end
	local stars = econ.Armoury[econ.Bring]
	if not stars or stars < 1 then
		return nil, nil
	end
	return econ.Bring, stars
end

local function stateFor(player: Player): { [string]: any }
	local cfg = Rewards.config()
	local econ = call("DataService", "getEcon", player) or {}
	local daily = econ.Daily or {}
	local sameDay = daily.day == today()
	local pity = econ.Pity or {}
	return {
		loaded = call("DataService", "isLoaded", player) == true,
		gold = call("CurrencyService", "balance", player) or 0,
		freeLeft = math.max(0, cfg.Wheel.FreePerDay - (if sameDay then daily.free or 0 else 0)) + (tonumber(econ.BonusSpins) or 0),
		paidLeft = math.max(0, cfg.Wheel.PaidPerDay - (if sameDay then daily.paid or 0 else 0)),
		spinCost = cfg.Wheel.SpinCost,
		armoury = econ.Armoury or {},
		bring = econ.Bring or "",
		pity = {
			wheel4 = math.max(1, cfg.Wheel.Pity4 - (pity.wheel4 or 0)),
			box4 = math.max(1, cfg.Strongbox.Pity4 - (pity.box4 or 0)),
			box5 = math.max(1, cfg.Strongbox.Pity5 - (pity.box5 or 0)),
		},
		paidBlocked = blocked(player),
		robuxGold = cfg.Economy.RobuxGold == true,
		wheelBusyUntil = wheelBusyUntil,
	}
end

function RewardsService.pushState(player: Player)
	call("KitService", "refreshArmoury", player) -- its KitArmoury list (when KitService offers it)
	if remote and player.Parent == Players then
		remote:FireClient(player, "state", stateFor(player))
	end
end

-- A weapon prize into the Armoury (or Gold back for a duplicate). Runs inside updateEcon's fn.
local function grantWeapon(e: any, stars: number, stake: number?): { [string]: any }
	local cfg = Rewards.config()
	local id, duplicate = Rewards.pickWeapon(e.Armoury, stars, rng)
	local before = e.Armoury[id] or 0
	local prize = { kind = "weapon", id = id, name = Rewards.weaponName(id), stars = stars, before = before }
	if duplicate then
		local back = cfg.Strongbox.DuplicateGold[stars] or 0
		if stake then
			back = math.max(back, stake) -- a paid draw never returns less than its stake
		end
		prize.duplicate = true
		prize.goldBack = back
	else
		e.Armoury[id] = stars
	end
	return prize
end

local function begin(player: Player): boolean
	if (playerBusy[player] or 0) > now() then
		return false
	end
	return true
end

-- The wheel -----------------------------------------------------------------------------------------------------------

local function spin(player: Player)
	local cfg = Rewards.config()
	if not near(player, "Wheel") then
		return
	end
	if not call("DataService", "isLoaded", player) then
		line(player, "Your Gold is still loading")
		return
	end
	if wheelBusyUntil > now() then
		line(player, "The wheel is turning")
		return
	end
	if not begin(player) then
		return
	end
	local econ = call("DataService", "getEcon", player)
	if not econ then
		return
	end
	local sameDay = econ.Daily.day == today()
	local free = (if sameDay then econ.Daily.free else 0) < cfg.Wheel.FreePerDay
	local bonus = not free and (tonumber(econ.BonusSpins) or 0) > 0 -- the daily reward's spins (grantSpins)
	local paid = not free and not bonus
	if paid then
		if blocked(player) then
			line(player, "Paid spins are not available on this account · your free spin comes back tomorrow")
			return
		end
		if (if sameDay then econ.Daily.paid else 0) >= cfg.Wheel.PaidPerDay then
			line(player, "No more spins today")
			return
		end
		if not call("DataService", "spendGold", player, cfg.Wheel.SpinCost) then
			line(player, string.format("A spin is %s Gold", Rewards.comma(cfg.Wheel.SpinCost)))
			return
		end
		call("CurrencyService", "log", player, false, cfg.Wheel.SpinCost, "Shop", "WheelSpin")
	end

	-- the outcome
	local outcome
	local pityHit = (econ.Pity.wheel4 + 1) >= cfg.Wheel.Pity4
	if pityHit then
		-- certain: a 4- or 5-star weapon, in the wheel's own 10 : 2 proportion
		outcome = Rewards.outcome(if rng:NextNumber() * 12 < 10 then "w4" else "w5")
	else
		local roll = rng:NextNumber() * 100
		local acc = 0
		for _, o in ipairs(Rewards.WheelOutcomes) do
			acc += o.chance
			if roll < acc then
				outcome = o
				break
			end
		end
		outcome = outcome or Rewards.WheelOutcomes[1]
	end
	local prize
	local ok = call("DataService", "updateEcon", player, function(e)
		freshDaily(e)
		if free then
			e.Daily.free += 1
		elseif bonus then
			e.BonusSpins = math.max(0, (e.BonusSpins or 0) - 1)
		else
			e.Daily.paid += 1
		end
		e.Draws += 1
		if outcome.kind == "weapon" then
			prize = grantWeapon(e, outcome.stars, if paid then cfg.Wheel.SpinCost else nil)
		else
			prize = { kind = "gold", gold = Rewards.wheelGold(outcome, paid) }
		end
		if outcome.kind == "weapon" and outcome.stars >= 4 then
			e.Pity.wheel4 = 0
		else
			e.Pity.wheel4 += 1
		end
	end)
	if not ok or not prize then
		if paid then
			call("DataService", "increment", player, "Gold", cfg.Wheel.SpinCost) -- give the stake back
		end
		line(player, "The wheel is stuck · try again")
		return
	end
	local goldIn = (prize.gold or 0) + (prize.goldBack or 0)
	if goldIn > 0 then
		call("DataService", "increment", player, "Gold", goldIn)
		call("CurrencyService", "log", player, true, goldIn, "Gameplay", "WheelPrize")
	end
	call("DataService", "saveSoon", player)

	-- where it stops: a segment of that outcome, somewhere inside it (never on a peg line)
	local choices = {}
	for i, seg in ipairs(Rewards.WheelSegments) do
		if seg[1] == outcome.key then
			table.insert(choices, i)
		end
	end
	local segment = choices[rng:NextInteger(1, #choices)]
	local a0, a1, mid = Rewards.segmentAngles(segment)
	local half = (a1 - a0) / 2
	local angle = mid + (rng:NextNumber() * 2 - 1) * half * 0.6
	local duration = cfg.Wheel.SpinTime + rng:NextNumber() * 0.5
	local startAt = now() + 0.25
	wheelBusyUntil = startAt + duration + REVEAL_TIME
	playerBusy[player] = wheelBusyUntil
	if remote then
		remote:FireAllClients("spin", {
			userId = player.UserId,
			name = player.DisplayName,
			segment = segment,
			angle = angle,
			startAt = startAt,
			duration = duration,
			paid = paid,
			pity = pityHit,
			prize = prize,
		})
	end
	RewardsService.pushState(player)
end

-- Strongboxes -----------------------------------------------------------------------------------------------------------

local function openBox(player: Player, kind: any, menu: boolean?)
	local cfg = Rewards.config()
	if kind ~= "strongbox" and kind ~= "masterwork" then
		return
	end
	if not reachable(player, if kind == "masterwork" then "Masterwork" else "Case", menu) then
		return
	end
	if not call("DataService", "isLoaded", player) then
		line(player, "Your Gold is still loading")
		return
	end
	if blocked(player) then
		line(player, "Strongboxes are not available on this account · the Armoury sells every weapon")
		return
	end
	if caseBusyUntil > now() then
		line(player, "The case is open · a moment")
		return
	end
	if not begin(player) then
		return
	end
	local cost = if kind == "masterwork" then cfg.Strongbox.MasterworkCost else cfg.Strongbox.Cost
	if not call("DataService", "spendGold", player, cost) then
		line(player, string.format("%s is %s Gold", if kind == "masterwork" then "A Masterwork Strongbox" else "A Strongbox",
			Rewards.comma(cost)))
		return
	end
	call("CurrencyService", "log", player, false, cost, "Shop", if kind == "masterwork" then "MasterworkStrongbox" else "Strongbox")

	local prize
	local pityNote
	local ok = call("DataService", "updateEcon", player, function(e)
		local odds = Rewards.BoxOdds[kind]
		local stars
		if e.Pity.box5 + 1 >= cfg.Strongbox.Pity5 then
			stars = 5
			pityNote = "5"
		elseif e.Pity.box4 + 1 >= cfg.Strongbox.Pity4 then
			-- certain 4 or better, in the box's own proportion of 4 to 5
			local four, five = 0, 0
			for _, row in ipairs(odds) do
				if row[1] == 4 then
					four = row[2]
				elseif row[1] == 5 then
					five = row[2]
				end
			end
			stars = if rng:NextNumber() * (four + five) < four then 4 else 5
			pityNote = "4"
		else
			stars = Rewards.drawStars(odds, rng:NextNumber())
		end
		prize = grantWeapon(e, stars, cost)
		if stars >= 5 then
			e.Pity.box5 = 0
			e.Pity.box4 = 0
		elseif stars >= 4 then
			e.Pity.box4 = 0
			e.Pity.box5 += 1
		else
			e.Pity.box4 += 1
			e.Pity.box5 += 1
		end
		e.Draws += 1
	end)
	if not ok or not prize then
		call("DataService", "increment", player, "Gold", cost)
		line(player, "The box would not open · your Gold is back")
		return
	end
	if prize.goldBack and prize.goldBack > 0 then
		call("DataService", "increment", player, "Gold", prize.goldBack)
		call("CurrencyService", "log", player, true, prize.goldBack, "Gameplay", "DuplicateGold")
	end
	call("DataService", "saveSoon", player)
	local startAt = now() + 0.2
	caseBusyUntil = startAt + BOX_TIME
	playerBusy[player] = caseBusyUntil
	if remote then
		remote:FireAllClients("box", { userId = player.UserId, name = player.DisplayName, kind = kind, startAt = startAt,
			pity = pityNote, prize = prize })
	end
	RewardsService.pushState(player)
end

-- The Armoury (no chance: open to everyone) ----------------------------------------------------------------------------

local function armoury(player: Player, action: string, id: any, menu: boolean?)
	local cfg = Rewards.config()
	if type(id) ~= "string" or (not Rewards.InPool[id] and not (action == "bring" and id == "")) then
		return
	end
	if not reachable(player, "Armoury", menu) then
		return
	end
	if not call("DataService", "isLoaded", player) then
		line(player, "Your Gold is still loading")
		return
	end
	local econ = call("DataService", "getEcon", player)
	if not econ then
		return
	end
	local owned = econ.Armoury[id] or 0
	if action == "bring" then
		if id ~= "" and owned < 1 then
			return
		end
		local kit = Services and Services.KitService
		if kit and type(kit.setBring) == "function" then
			call("KitService", "setBring", player, id) -- keeps its KitBring attribute and Econ.Bring together
		else
			call("DataService", "updateEcon", player, function(e)
				e.Bring = id
			end)
		end
		call("DataService", "saveSoon", player)
		RewardsService.pushState(player)
		return
	end
	local cost, to
	if action == "buy" and owned < 3 then
		cost, to = cfg.Armoury.Buy3, 3
	elseif action == "raise" and owned == 3 then
		cost, to = cfg.Armoury.Raise4, 4
	elseif action == "raise" and owned == 4 then
		cost, to = cfg.Armoury.Raise5, 5
	else
		return
	end
	if not call("DataService", "spendGold", player, cost) then
		line(player, string.format("%s %s is %s Gold", Rewards.weaponName(id), Rewards.starText(to), Rewards.comma(cost)))
		return
	end
	local ok = call("DataService", "updateEcon", player, function(e)
		if (e.Armoury[id] or 0) < to then
			e.Armoury[id] = to
		end
	end)
	if not ok then
		call("DataService", "increment", player, "Gold", cost)
		return
	end
	call("CurrencyService", "log", player, false, cost, "Shop", "Armoury_" .. id .. "_" .. to)
	call("DataService", "saveSoon", player)
	line(player, string.format("%s %s → %s", Rewards.weaponName(id), Rewards.starText(math.max(owned, 0)), Rewards.starText(to)))
	RewardsService.pushState(player)
end

-- The owned weapon at the kit's moment (only while KitService does not deliver it) ---------------------------------

local function kitsConfig(): { [string]: any }
	local ok, Config = pcall(require, Shared:WaitForChild("Config"))
	local k = ok and Config and Config.Kits
	return if type(k) == "table" then k else {}
end

local function deliveryTime(practice: boolean): number
	local K = kitsConfig()
	if Rewards.config().IsStudio then
		local t = workspace:GetAttribute("RewardsDeliveryTest")
		if type(t) == "number" then
			return t
		end
	end
	if K.Delivery == "Start" then
		return 0
	end
	if practice then
		return tonumber(K.PracticeTime) or 60
	end
	local ok, Config = pcall(require, Shared:WaitForChild("Config"))
	local maxTime = if ok and Config and Config.Round then tonumber(Config.Round.MaxRoundTime) or 1200 else 1200
	return math.max(tonumber(K.MinTime) or 240, tonumber(K.MidpointTime) or maxTime / 2)
end

local function giveBring(player: Player)
	local id, stars = RewardsService.getBring(player)
	if not id or player:GetAttribute("Alive") ~= true then
		return
	end
	local added = call("InventoryService", "give", player, id, 1, stars)
	if (tonumber(added) or 0) > 0 then
		if id == "short_bow" then
			call("InventoryService", "give", player, "arrow", 6)
		end
		line(player, string.format("Your %s %s is in your bag", Rewards.weaponName(id), Rewards.starText(stars or 0)))
	end
end

local function onRoundStarted(roundId: any)
	local kit = Services and Services.KitService
	if kit and kit.deliversOwnedWeapon ~= false then
		return -- KitService's parcel brings it (its itemsFor reads Econ.Bring)
	end
	local practice = GameState:GetAttribute("Practice") == true
	local at = deliveryTime(practice)
	local K = kitsConfig()
	local contenders = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if call("RoundService", "isContender", player) == true then
			table.insert(contenders, player)
		end
	end
	task.spawn(function()
		local share = tonumber(K.MidpointShare) or 0.5
		local minTime = if practice then 0 else (tonumber(K.MinTime) or 240)
		while true do
			task.wait(1)
			if GameState:GetAttribute("Phase") ~= "Active" or call("RoundService", "getRoundId") ~= roundId then
				return
			end
			local elapsed = tonumber(call("RoundService", "getElapsed")) or 0
			local out = 0
			for _, p in ipairs(contenders) do
				if p.Parent ~= Players or p:GetAttribute("Alive") ~= true then
					out += 1
				end
			end
			local halfOut = at > 0 and #contenders >= 2 and out >= #contenders * share and elapsed >= minTime
			if elapsed >= at or halfOut then
				break
			end
		end
		for _, player in ipairs(contenders) do
			if player.Parent == Players then
				pcall(giveBring, player)
			end
		end
	end)
end

-- Lifecycle -------------------------------------------------------------------------------------------------------------

local function onEvent(player: Player, action: any, arg: any, flag: any)
	local menu = flag == "menu"
	if type(action) ~= "string" then
		return
	end
	if action == "state" then
		if Net.rateLimit(player, "RewardsState", 1, 4) then
			RewardsService.pushState(player)
		end
		return
	end
	if not Net.rateLimit(player, "RewardsDraw", 1, 2) then
		return
	end
	if action == "spin" then
		spin(player)
	elseif action == "box" then
		openBox(player, arg, menu)
	elseif action == "buy" or action == "raise" or action == "bring" then
		armoury(player, action, arg, menu)
	end
end

function RewardsService.Init(services)
	Services = services
	remote = getRemote()
end

function RewardsService.Start()
	local event = remote
	if not event then
		warn("[RewardsService] no Remotes folder: the wheel is off")
		return
	end
	event.OnServerEvent:Connect(onEvent)
	Players.PlayerRemoving:Connect(function(player)
		playerBusy[player] = nil
	end)
	local rs = Services and Services.RoundService
	if rs and rs.roundStarted then
		rs.roundStarted:Connect(onRoundStarted)
	end
	-- each player's state once their profile has answered (Gold attribute changes say when)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Gold"):Connect(function()
			RewardsService.pushState(player)
		end)
		task.delay(2, RewardsService.pushState, player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return RewardsService
