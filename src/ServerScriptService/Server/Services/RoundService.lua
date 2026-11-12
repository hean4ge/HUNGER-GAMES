--[[
	RoundService - the round state machine (docs/GameDesign.md section 4).
	  Lobby -> Intermission -> Countdown -> Active -> Ending -> Lobby
	Keeps ReplicatedStorage.GameState current: Phase, PhaseEndsAt, AliveCount, StartedCount, RoundId, Practice,
	MinPlayers, LobbyCount, WinnerName, RoundStartedAt, and LaunchAt / LaunchRise / LaunchDepth at each Countdown (the
	launch plates rise on every client: LaunchController). (ArenaService owns the border, clock and ArenaEvent.)
	Playability (docs/design/PlayabilityPlan.md):
	  QW1  never wait alone: a lone player on a live server gets a practice round after Config.Round.SoloWaitTime s,
	       counted from joining for a newcomer (player attribute JoinedAt = server time they joined)
	       (GameState.SoloStartAt = server time its contenders are chosen, 0 otherwise). A player who arrives during a
	       practice round ends it PracticeHandoffTime s later (PhaseEndsAt moves up; the lone contender is the winner).
	       Practice rounds add no Wins and no RoundsPlayed.
	  QW3  GameState.BorderStartRadius at each Countdown: clamp(640 * sqrt(N / 24), 320, 640) for N contenders (set
	       before LootService.populate; ArenaService and the wall start from it).
	  Q1   player attribute NewPlayer at each Countdown: RoundsPlayed < Config.Guidance.NewPlayerRounds.
	  QW6  no banner at the horn of a real round (it covered the first sprint); practice rounds keep PRACTICE ROUND.
	  QW14 a timeout with two or more alive goes to the healthiest, then the most kills (Config.Round.LastStand);
	       the epilogue Roll Call (ArenaService.startEpilogue) plays behind the winner card and Ending grows to fit it.

	API:
	  RoundService.getPhase() -> string
	  RoundService.isPractice() -> boolean
	  RoundService.roundStarted: Signal(roundId)          the start horn (Phase becomes "Active")
	  RoundService.roundEnded: Signal(winner: Player?)    the round is decided (Phase becomes "Ending"); also fires
	                                                      with nil if a countdown is cancelled because everyone left
	Extra:
	  RoundService.roundStarting: Signal(roundId)         contenders are on their plinths (Phase becomes "Countdown")
	  RoundService.phaseChanged: Signal(newPhase, oldPhase)
	  RoundService.getRoundId() -> number
	  RoundService.isContender(player) -> boolean         picked for the current round
	  RoundService.getElapsed() -> number                 round-schedule seconds since the horn (0 outside Active/Ending)
	  RoundService.getTimeScale() -> number               Config.Round.StudioTimeScale in Studio, else 1

	Announce styles used: "Banner" (phase changes), "Countdown" (one per second: "5".."1", then "GO"), "Toast",
	"Victory" (text = winner's display name or a no-winner title, plus `winner` = name or nil).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local RoundCfg = Config.Round

local TICK = 0.1

local RoundService = {}
RoundService.roundStarted = Signal.new()
RoundService.roundEnded = Signal.new()
RoundService.roundStarting = Signal.new()
RoundService.phaseChanged = Signal.new()

local Services = nil
local phase = "Lobby"
local phaseEndsAt = 0
local roundId = 0
local practice = false
local roundStartedAt = 0
local contenders = {} -- [Player] = { name, userId, placement, kills } for this round (kept for leavers too)
local lastCountdownSecond = nil
local rng = Random.new()
local warned = {}
local strays = {} -- [Player] = time first seen in the arena while no round was running
local soloSince: number? = nil -- QW1: when the one waiting player started waiting alone
local joinedAt: { [Player]: number } = {} -- QW1: server time each player joined (a newcomer's wait counts from here)
local soloRound = false -- QW1: this Intermission was started for a lone player (it doesn't drop back to Lobby)
local handoffAt = 0 -- QW1: the practice round ends at this server time because a contender arrived

-- Helpers ----------------------------------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[RoundService] " .. message)
end

local function call(serviceName: string, method: string, ...: any): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		warnOnce(serviceName .. "." .. method, serviceName .. "." .. method .. " is not available")
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[RoundService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function timeScale(): number
	if Config.IsStudio then
		local scale = tonumber(RoundCfg.StudioTimeScale)
		if scale and scale > 0 then
			return scale
		end
	end
	return 1
end

local function minPlayers(): number
	return math.max(1, math.floor(tonumber(RoundCfg.MinPlayers) or 2))
end

local function playerService()
	return Services and Services.PlayerService
end

-- QW1: lone players get practice rounds on servers that need more than one player to start
local function soloEnabled(): boolean
	return RoundCfg.SoloPractice ~= false and minPlayers() > 1
end

-- QW3: the border's starting radius for n contenders (the arena is as crowded as a full round from 6 up)
local function startRadiusFor(n: number): number
	local border = Config.Border
	local full = border.StartRadius or 640
	if border.ScaleWithContenders == false then
		return full
	end
	local r = full * math.sqrt(math.max(1, n) / math.max(1, border.FullContenders or 24))
	return math.floor(math.clamp(r, math.min(border.MinStartRadius or 320, full), full) + 0.5)
end

-- QW14: who wins a timeout: the healthiest, then the one with more kills
local function healthOf(player: Player): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.Health else 0
end

local function rankSurvivors(alive: { Player })
	table.sort(alive, function(a, b)
		local ha, hb = math.floor(healthOf(a) * 10 + 0.5), math.floor(healthOf(b) * 10 + 0.5)
		if ha ~= hb then
			return ha > hb
		end
		local ka, kb = tonumber(a:GetAttribute("Kills")) or 0, tonumber(b:GetAttribute("Kills")) or 0
		if ka ~= kb then
			return ka > kb
		end
		return a.UserId < b.UserId
	end)
end

local function setAttr(name: string, value: any)
	if GameState:GetAttribute(name) ~= value then
		GameState:SetAttribute(name, value)
	end
end

local function announce(payload: { [string]: any })
	Net.event("Announce"):FireAllClients(payload)
end

local function setPhase(newPhase: string, duration: number?)
	local old = phase
	phase = newPhase
	phaseEndsAt = if duration then now() + duration else 0
	-- PhaseEndsAt first, so clients reacting to Phase already see the new deadline
	GameState:SetAttribute("PhaseEndsAt", phaseEndsAt)
	GameState:SetAttribute("Phase", newPhase)
	if old ~= newPhase then
		RoundService.phaseChanged:Fire(newPhase, old)
	end
end

local function shuffle(list: { any })
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Plinths ----------------------------------------------------------------------------------------------------------

local function arenaCenter(): Vector3
	local arena = workspace:FindFirstChild("Arena")
	local center = arena and arena:GetAttribute("Center")
	if typeof(center) == "Vector3" then
		return center
	end
	return ArenaLayout.Center
end

local function raycastDown(origin: Vector3, distance: number, include: { Instance }?): Vector3?
	local params = RaycastParams.new()
	params.IgnoreWater = true
	if include then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
	else
		local characters = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(characters, p.Character)
			end
		end
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = characters
	end
	local hit = workspace:Raycast(origin, Vector3.new(0, -distance, 0), params)
	return if hit then hit.Position else nil
end

local function faceSpire(position: Vector3, center: Vector3): CFrame
	local target = Vector3.new(center.X, position.Y, center.Z)
	if (target - position).Magnitude < 0.1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, target)
end

-- Where a contender's feet go on a plinth: an Attachment named Stand/Spawn/SpawnPoint if the plinth has one,
-- otherwise the top surface at its centre.
local function plinthStandPoint(plinth: Instance): Vector3?
	for _, d in ipairs(plinth:GetDescendants()) do
		if d:IsA("Attachment") and (d.Name == "Stand" or d.Name == "Spawn" or d.Name == "SpawnPoint") then
			return d.WorldPosition
		end
	end
	local cf, size
	if plinth:IsA("BasePart") then
		cf, size = plinth.CFrame, plinth.Size
	elseif plinth:IsA("Model") then
		cf, size = plinth:GetBoundingBox()
	else
		return nil
	end
	local top = cf.Position + Vector3.new(0, size.Y / 2, 0)
	return raycastDown(top + Vector3.new(0, 4, 0), size.Y + 8, { plinth }) or top
end

-- The plinth instances in name order: workspace.Arena.Plinths children named Plinth.. (or tagged Plinth),
-- else every child of that folder, else anything tagged Plinth.
local function findPlinths(): { Instance }
	local arena = workspace:FindFirstChild("Arena")
	local folder = arena and arena:FindFirstChild("Plinths")
	local list = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if string.sub(child.Name, 1, 6) == "Plinth" or CollectionService:HasTag(child, "Plinth") then
				table.insert(list, child)
			end
		end
		if #list == 0 then
			list = folder:GetChildren()
		end
	end
	if #list == 0 then
		for _, tagged in ipairs(CollectionService:GetTagged("Plinth")) do
			if tagged:IsDescendantOf(workspace) then
				table.insert(list, tagged)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

-- Feet CFrames facing the Spire, in plinth order.
local function getPlinthSpots(): { CFrame }
	local center = arenaCenter()
	local spots = {}
	for _, plinth in ipairs(findPlinths()) do
		local point = plinthStandPoint(plinth)
		if point then
			table.insert(spots, faceSpire(point, center))
		end
	end
	if #spots == 0 then
		warnOnce("plinths", "workspace.Arena.Plinths is missing or empty; using a fallback ring around the Spire.")
		local count = ArenaLayout.PlinthCount or 24
		for i = 1, count do
			local ring = ArenaLayout.polar((i - 1) * 360 / count, ArenaLayout.PlinthRingRadius, ArenaLayout.BaseHeight)
			local ground = raycastDown(ring + Vector3.new(0, 60, 0), 140) or ring
			table.insert(spots, faceSpire(ground, center))
		end
	end
	return spots
end

-- Round summary ----------------------------------------------------------------------------------------------------

local function buildSummary(winnerName: string?, duration: number)
	local placements = {}
	for _, info in pairs(contenders) do
		table.insert(placements, { name = info.name, placement = info.placement, kills = info.kills, userId = info.userId })
	end
	table.sort(placements, function(a, b)
		if a.placement ~= b.placement then
			return a.placement < b.placement
		end
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.name < b.name
	end)
	return { winner = winnerName, duration = math.floor(duration + 0.5), placements = placements }
end

-- Phases -----------------------------------------------------------------------------------------------------------

-- Back to the lobby: reload everyone who was in the arena, clear loot and inventories, reset round attributes.
local function finishRound(cancelled: boolean?)
	if cancelled then
		RoundService.roundEnded:Fire(nil)
	end
	local ps = playerService()
	for _, player in ipairs(Players:GetPlayers()) do
		local inRound = player:GetAttribute("InArena") == true or player:GetAttribute("Alive") == true
		call("InventoryService", "clear", player)
		player:SetAttribute("Kills", 0)
		player:SetAttribute("Placement", 0)
		ps.clearSpectate(player)
		if inRound then
			ps.loadIntoLobby(player) -- also resets Alive/InArena/Frozen/Hunger/Thirst/Armor
		end
	end
	task.spawn(call, "LootService", "clearAll")
	table.clear(contenders)
	practice = false
	roundStartedAt = 0
	lastCountdownSecond = nil
	handoffAt = 0
	GameState:SetAttribute("BorderStartRadius", Config.Border.StartRadius)
	GameState:SetAttribute("Practice", false)
	GameState:SetAttribute("AliveCount", 0)
	GameState:SetAttribute("StartedCount", 0)
	GameState:SetAttribute("WinnerName", "")
	GameState:SetAttribute("RoundStartedAt", 0)
	setPhase("Lobby")
end

local function endRound(winner: Player?, reason: string)
	if phase ~= "Active" then
		return
	end
	local ps = playerService()
	local duration = math.max(0, now() - roundStartedAt)
	local alive = ps.getAlivePlayers()
	-- QW14: every round ends with one winner. A timeout with two or more alive is settled by health, then kills.
	if not winner and #alive > 1 and not practice and RoundCfg.LastStand ~= false then
		rankSurvivors(alive)
		winner = alive[1]
		reason = "tiebreak"
	end
	-- survivors share first place (exactly one survivor is the winner); after a tiebreak they're placed in its order
	for i, player in ipairs(alive) do
		local place = if reason == "tiebreak" then i else 1
		player:SetAttribute("Placement", place)
		local info = contenders[player]
		if info then
			info.placement = place
		end
	end
	for player, info in pairs(contenders) do
		if player.Parent == Players then
			info.kills = tonumber(player:GetAttribute("Kills")) or info.kills
		end
		if info.placement <= 0 then
			info.placement = #alive + 1
		end
	end

	local winnerName = if winner then winner.DisplayName else nil
	GameState:SetAttribute("WinnerName", winnerName or "")
	GameState:SetAttribute("AliveCount", #alive)
	-- QW14: the epilogue (a short Roll Call of the fallen not yet shown in the sky) plays behind the winner card
	local endingTime = RoundCfg.EndingTime
	if not practice and RoundCfg.Epilogue ~= false then
		local length = call("ArenaService", "startEpilogue", RoundCfg.EpilogueLeadIn or 2.5)
		if type(length) == "number" and length > 0 then
			endingTime = math.max(endingTime, length + 1)
		end
	end
	setPhase("Ending", endingTime)

	local text, sub
	if winner then
		text = winnerName
		sub = if practice then "survived the practice round"
			elseif reason == "tiebreak" then "wins at the final horn · the healthiest left standing"
			else "is the last one standing"
	elseif reason == "timeout" and #alive > 1 then
		text = "TIME'S UP"
		sub = string.format("%d contenders survived. Nobody claims the win.", #alive)
	elseif practice then
		text = "PRACTICE OVER"
		sub = "You were eliminated. A new round starts soon."
	else
		text = "NO SURVIVORS"
		sub = "The arena claimed everyone"
	end
	announce({ style = "Victory", text = text, sub = sub, winner = winnerName, duration = endingTime })
	Net.event("RoundSummary"):FireAllClients(buildSummary(winnerName, duration))
	-- a walkover (everyone else left before anything happened) doesn't count as a win
	local earned = duration >= 15 or (tonumber(if winner then winner:GetAttribute("Kills") else 0) or 0) > 0
	if winner and not practice and earned then
		call("DataService", "increment", winner, "Wins", 1)
	end
	RoundService.roundEnded:Fire(winner)
end

local function enterActive(t: number)
	roundStartedAt = t
	GameState:SetAttribute("RoundStartedAt", roundStartedAt)
	announce({ style = "Countdown", text = "GO", duration = 1.2 })
	setPhase("Active", RoundCfg.MaxRoundTime / timeScale())
	local ps = playerService()
	for player in pairs(contenders) do
		if player.Parent == Players and ps.isAlive(player) then
			ps.setFrozen(player, false)
			if not practice then -- new-player help counts real rounds only (QW1)
				call("DataService", "increment", player, "RoundsPlayed", 1)
			end
		end
	end
	Sfx.play("StartHorn")
	local id = roundId
	-- QW6: nothing covers the first sprint. The goal was on the plate caption; new players get the sprint key under the
	-- crosshair (HUDController). Only a practice round gets a banner, to say what kind of round this is.
	if practice then
		task.delay(1.6, function()
			if phase == "Active" and roundId == id and practice then
				announce({ style = "Banner", text = "PRACTICE ROUND", sub = "Explore, loot and test your gear", duration = 4 })
			end
		end)
	end
	RoundService.roundStarted:Fire(roundId)
end

local function countdownTick(t: number)
	if #playerService().getAlivePlayers() == 0 then
		announce({
			style = "Toast",
			text = if practice then "Practice cancelled" else "Round cancelled",
			sub = if practice then "You left your plate before the horn" else "Every contender left",
			duration = 3,
		})
		finishRound(true)
		return
	end
	local remaining = math.ceil(phaseEndsAt - t)
	if remaining >= 1 and remaining ~= lastCountdownSecond then
		lastCountdownSecond = remaining
		announce({
			style = "Countdown",
			text = tostring(remaining),
			-- {N} = the seconds left, filled in by the client (NotificationController) so it never lags the number
			sub = if practice then "Practice round · the arena opens in {N}" else "Stay on your plate · the arena opens in {N}",
			duration = 1,
		})
	end
	if t >= phaseEndsAt then
		enterActive(t)
	end
end

local function enterCountdown()
	local ps = playerService()
	local candidates = ps.getLobbyPlayers()
	shuffle(candidates)
	local spots = getPlinthSpots()
	local count = math.min(#candidates, RoundCfg.MaxContenders or 24, #spots)
	if count <= 0 then
		setPhase("Lobby")
		return
	end

	table.clear(contenders)
	local offset = rng:NextInteger(0, #spots - 1)
	local picked = 0
	for i = 1, count do
		local player = candidates[i]
		-- spread contenders evenly around the ring when there are fewer than plinths
		local index = ((math.floor((i - 1) * #spots / count) + offset) % #spots) + 1
		call("InventoryService", "clear", player)
		if ps.prepareContender(player, spots[index]) then
			picked += 1
			contenders[player] = { name = player.DisplayName, userId = player.UserId, placement = 0, kills = 0 }
		end
	end
	if picked == 0 then
		setPhase("Lobby")
		return
	end

	roundId += 1
	practice = picked == 1
	lastCountdownSecond = nil
	roundStartedAt = 0
	GameState:SetAttribute("RoundId", roundId)
	GameState:SetAttribute("Practice", practice)
	GameState:SetAttribute("StartedCount", picked)
	GameState:SetAttribute("AliveCount", picked)
	GameState:SetAttribute("WinnerName", "")
	GameState:SetAttribute("RoundStartedAt", 0)
	handoffAt = 0
	-- QW3: small rounds start small. Published before the loot is placed (LootService skips markers outside it).
	GameState:SetAttribute("BorderStartRadius", startRadiusFor(picked))
	-- Q1: this round's new players (RoundsPlayed is read here, before the horn adds one)
	local newRounds = (Config.Guidance and tonumber(Config.Guidance.NewPlayerRounds)) or 3
	for player in pairs(contenders) do
		player:SetAttribute("NewPlayer", (tonumber(player:GetAttribute("RoundsPlayed")) or 0) < newRounds)
	end
	-- the launch: every client raises the plates out of their tubes on this shared timeline (LaunchController)
	GameState:SetAttribute("LaunchAt", now() + (RoundCfg.LaunchDelay or 0.8))
	GameState:SetAttribute("LaunchRise", RoundCfg.LaunchRiseTime or 3.4)
	GameState:SetAttribute("LaunchDepth", RoundCfg.LaunchDepth or 10)
	setPhase("Countdown", RoundCfg.CountdownTime)
	task.spawn(call, "LootService", "populate")
	RoundService.roundStarting:Fire(roundId)
end

local function enterIntermission(solo: boolean?)
	setPhase("Intermission", RoundCfg.IntermissionTime)
	local seconds = math.floor(RoundCfg.IntermissionTime + 0.5)
	if solo then
		setAttr("SoloStartAt", phaseEndsAt)
		announce({
			style = "Banner",
			text = "PRACTICE ROUND",
			sub = string.format("No other contenders yet · it starts in %d seconds", seconds),
			duration = 4,
		})
		return
	end
	announce({
		style = "Banner",
		text = "NEXT ROUND",
		sub = string.format("Contenders are chosen in %d seconds", seconds),
		duration = 4,
	})
end

local function activeTick(t: number)
	local alive = playerService().getAlivePlayers()
	setAttr("AliveCount", #alive)
	if practice then
		if #alive == 0 then
			endRound(nil, "eliminated")
			return
		end
		-- QW1: a contender arrived while a lone player practises: the practice ends soon and a full round follows
		local handoff = tonumber(RoundCfg.PracticeHandoffTime)
		if handoff and handoffAt == 0 and playerService().getWaitingCount() >= 1 then
			handoffAt = t + math.max(5, handoff)
			if handoffAt < phaseEndsAt then
				phaseEndsAt = handoffAt
				GameState:SetAttribute("PhaseEndsAt", phaseEndsAt)
			end
			announce({ style = "Banner", text = "A CONTENDER HAS ARRIVED", sub = "A full round starts soon", duration = 5 })
		end
	elseif #alive <= 1 then
		endRound(alive[1], "last")
		return
	end
	if t >= phaseEndsAt then
		endRound(if #alive == 1 then alive[1] else nil, if handoffAt > 0 then "handoff" else "timeout")
	end
end

-- Safety net: outside a round nobody should be in the arena. If a transition ever failed half-way,
-- send stragglers back to the lobby instead of leaving them stuck.
local function rescueStrays(t: number)
	local ps = playerService()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true or player:GetAttribute("Alive") == true then
			local since = strays[player]
			if not since then
				strays[player] = t
			elseif t - since > 5 then
				strays[player] = nil
				warn("[RoundService] " .. player.Name .. " was in the arena outside a round; returning them to the lobby")
				call("InventoryService", "clear", player)
				ps.loadIntoLobby(player)
			end
		else
			strays[player] = nil
		end
	end
	for player in pairs(strays) do
		if player.Parent ~= Players then
			strays[player] = nil
		end
	end
end

local function step()
	local ps = playerService()
	local t = now()
	local waiting = ps.getWaitingCount()
	setAttr("LobbyCount", waiting)
	if phase == "Lobby" or phase == "Intermission" then
		rescueStrays(t)
	elseif next(strays) then
		table.clear(strays)
	end
	if phase == "Lobby" then
		if waiting >= minPlayers() then
			soloSince = nil
			soloRound = false
			setAttr("SoloStartAt", 0)
			enterIntermission(false)
		elseif waiting == 1 and soloEnabled() then
			-- QW1: never wait alone. One countdown covers the wait and the Intermission (LobbyController shows it).
			local wait = math.max(0, tonumber(RoundCfg.SoloWaitTime) or 30)
			if not soloSince then
				-- a newcomer's wait counts from joining, so loading is part of it (join to horn: Wait + Intermission +
				-- Countdown, 65 s live); someone left alone later on waits the full SoloWaitTime from now
				local lone = ps.getLobbyPlayers()[1]
				local joined = if lone then joinedAt[lone] else nil
				soloSince = if joined and t - joined < wait then joined else t
			end
			setAttr("SoloStartAt", math.floor((soloSince + wait + RoundCfg.IntermissionTime) * 10 + 0.5) / 10)
			if t - soloSince >= wait then
				soloRound = true
				enterIntermission(true)
			end
		elseif soloSince or soloRound then
			soloSince = nil
			soloRound = false
			setAttr("SoloStartAt", 0)
		end
	elseif phase == "Intermission" then
		if soloRound and waiting >= minPlayers() then
			soloRound = false -- someone arrived during the practice countdown: this is a full round now
			setAttr("SoloStartAt", 0)
		end
		if waiting < minPlayers() and not (soloRound and waiting >= 1) then
			soloSince = nil
			soloRound = false
			setAttr("SoloStartAt", 0)
			announce({ style = "Toast", text = "Waiting for players", sub = "The countdown resumes when enough contenders are here", duration = 3 })
			setPhase("Lobby")
		elseif t >= phaseEndsAt then
			soloSince = nil
			soloRound = false
			setAttr("SoloStartAt", 0)
			enterCountdown()
		end
	elseif phase == "Countdown" then
		setAttr("AliveCount", #ps.getAlivePlayers())
		countdownTick(t)
	elseif phase == "Active" then
		activeTick(t)
	elseif phase == "Ending" then
		if t >= phaseEndsAt then
			finishRound(false)
		end
	else
		setPhase("Lobby")
	end
end

-- Keep this round's results current as contenders fall (including those who leave).
local function onDied(victim: Player, killer: Player?, _cause: string)
	local info = contenders[victim]
	if info then
		info.placement = tonumber(victim:GetAttribute("Placement")) or info.placement
		info.kills = tonumber(victim:GetAttribute("Kills")) or info.kills
	end
	local killerInfo = if killer then contenders[killer] else nil
	if killerInfo and killer then
		killerInfo.kills = tonumber(killer:GetAttribute("Kills")) or (killerInfo.kills + 1)
	end
end

-- Public API ---------------------------------------------------------------------------------------------------------

function RoundService.getPhase(): string
	return phase
end

function RoundService.isPractice(): boolean
	return practice
end

function RoundService.getRoundId(): number
	return roundId
end

function RoundService.isContender(player: Player): boolean
	return contenders[player] ~= nil
end

function RoundService.getElapsed(): number
	if roundStartedAt <= 0 or (phase ~= "Active" and phase ~= "Ending") then
		return 0
	end
	return math.max(0, (now() - roundStartedAt) * timeScale())
end

RoundService.getTimeScale = timeScale

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function RoundService.Init(registry)
	Services = registry
	roundId = tonumber(GameState:GetAttribute("RoundId")) or 0
end

function RoundService.Start()
	local ps = playerService()
	if not ps then
		warn("[RoundService] PlayerService is missing; rounds can't run.")
		return
	end
	ps.died:Connect(onDied)
	local function onPlayerAdded(player: Player)
		if not joinedAt[player] then
			joinedAt[player] = now()
			player:SetAttribute("JoinedAt", math.floor(joinedAt[player] * 100 + 0.5) / 100)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		joinedAt[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	GameState:SetAttribute("MinPlayers", minPlayers())
	GameState:SetAttribute("RoundId", roundId)
	GameState:SetAttribute("Practice", false)
	GameState:SetAttribute("AliveCount", 0)
	GameState:SetAttribute("StartedCount", 0)
	GameState:SetAttribute("WinnerName", "")
	GameState:SetAttribute("RoundStartedAt", 0)
	GameState:SetAttribute("SoloStartAt", 0)
	GameState:SetAttribute("BorderStartRadius", Config.Border.StartRadius)
	setPhase("Lobby")
	while true do
		local ok, err = pcall(step)
		if not ok then
			warnOnce("step:" .. tostring(err), "Round step failed: " .. tostring(err))
		end
		task.wait(TICK)
	end
end

return RoundService
