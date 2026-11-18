--[[
	ResultsBoardService - keeps the last round's result for the results board in the lobby (the server half;
	Controllers/ResultsBoardController is the client half, which writes it on the board's SurfaceGui).

	The owner (18 Nov 2026): the result "shouldnt pop up after the game it can appear on one of the physical boards".
	So the full result is not a screen any more: it is on a notice board in the lobby, and this service keeps it.

	What it records, per round (from RoundService and PlayerService signals; nothing else is changed):
	  * at the start horn (RoundService.roundStarted): every contender's name and UserId, and the start time
	  * each fall (PlayerService.died): placement (the Placement attribute PlayerService sets first), cause, time
	  * at the end (RoundService.roundEnded, Phase "Ending"): survivors' placement, everyone's defeats (Kills), the
	    round's length, how many days it ran
	A cancelled round (roundEnded fires while the Phase is still "Countdown") and a practice round change nothing:
	the board keeps the last real round.

	Remote: ReplicatedStorage.Remotes.RoundResult, created here in Init (like PlusService's PlusSubscribe; it is not
	in Net.Names on purpose: the game works unchanged without this service).
	  server -> client  "result", result     to everyone when a round ends; to one player when they ask
	  client -> server  "get"                ask for the last result (ResultsBoardController, once at start)
	  server -> client  "result", nil        there is no result yet (the board shows its empty face)

	result = {
	  roundId, endedAt (server time), contenders (count), days, duration (s),
	  winner = { name, userId, kills, survived } | nil,
	  title = string?                        when there is no winner: "Time's up" / "No survivors"
	  rows = { { place, name, userId, kills, survived (s), cause? } },   every contender, best first
	  facts = { firstFall = { name, time }?, mostDefeats = { name, kills }?, border = n, early = n },
	}
	"early" counts the contenders who fell in the round's first EARLY_WINDOW seconds (mostly at the centre's rush).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local ResultsBoardService = {}

local REMOTE_NAME = "RoundResult"
local EARLY_WINDOW = 60 -- seconds after the horn that count as "fell in the first minute"

local Services: any = nil
local remote: RemoteEvent? = nil
local last: { [string]: any }? = nil -- the last real round's result

type Entry = { name: string, userId: number, place: number, kills: number, diedAt: number?, cause: string? }
local current: { roundId: any, startedAt: number, entries: { [number]: Entry } }? = nil

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
		warn(string.format("[ResultsBoardService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function entryFor(player: Player): Entry?
	local c = current
	if not c then
		return nil
	end
	local e = c.entries[player.UserId]
	if not e then
		e = { name = player.DisplayName, userId = player.UserId, place = 0, kills = 0 }
		c.entries[player.UserId] = e
	end
	return e
end

local function onRoundStarted(roundId: any)
	if GameState:GetAttribute("Practice") == true then
		current = nil
		return
	end
	local startedAt = tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
	current = { roundId = roundId, startedAt = if startedAt > 0 then startedAt else now(), entries = {} }
	for _, player in ipairs(Players:GetPlayers()) do
		local contender = call("RoundService", "isContender", player)
		if contender == true or (contender == nil and player:GetAttribute("Alive") == true) then
			entryFor(player)
		end
	end
end

local function onDied(victim: Player, _killer: Player?, cause: string?)
	local c = current
	if not c or GameState:GetAttribute("Phase") ~= "Active" then
		return
	end
	local e = entryFor(victim)
	if not e then
		return
	end
	e.place = math.floor(tonumber(victim:GetAttribute("Placement")) or 0)
	e.kills = math.floor(tonumber(victim:GetAttribute("Kills")) or e.kills)
	e.diedAt = now()
	e.cause = if type(cause) == "string" then cause else nil
end

local function build(winner: Player?): { [string]: any }?
	local c = current
	if not c then
		return nil
	end
	local endedAt = now()
	local duration = math.max(0, endedAt - c.startedAt)
	-- survivors and everyone still here: the final placement and defeats (RoundService set Placement before this)
	for _, player in ipairs(Players:GetPlayers()) do
		local e = c.entries[player.UserId]
		if e then
			local place = math.floor(tonumber(player:GetAttribute("Placement")) or 0)
			if place > 0 then
				e.place = place
			end
			e.kills = math.floor(tonumber(player:GetAttribute("Kills")) or e.kills)
			-- the fall that ended the round can reach RoundService (which ends the round inside its own died
			-- handler) before it reaches onDied here: a contender who is down but has no time yet fell just now
			if not e.diedAt and player:GetAttribute("Alive") ~= true then
				e.diedAt = endedAt
			end
		end
	end
	local rows = {}
	local count = 0
	for _ in pairs(c.entries) do
		count += 1
	end
	for _, e in pairs(c.entries) do
		local survived = if e.diedAt then math.max(0, e.diedAt - c.startedAt) else duration
		table.insert(rows, {
			place = if e.place > 0 then e.place else count,
			name = e.name,
			userId = e.userId,
			kills = e.kills,
			survived = math.floor(survived + 0.5),
			cause = e.cause,
		})
	end
	table.sort(rows, function(a, b)
		if a.place ~= b.place then
			return a.place < b.place
		end
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.name < b.name
	end)

	-- the round's facts
	local firstFall: { [string]: any }? = nil
	local firstAt = math.huge
	local most: { [string]: any }? = nil
	local border, early = 0, 0
	for _, e in pairs(c.entries) do
		if e.diedAt then
			local t = e.diedAt - c.startedAt
			if t < firstAt then
				firstAt = t
				firstFall = { name = e.name, time = math.floor(math.max(0, t) + 0.5) }
			end
			if t <= EARLY_WINDOW then
				early += 1
			end
			if e.cause == "Border" then
				border += 1
			end
		end
		if e.kills > 0 and (not most or e.kills > most.kills or (e.kills == most.kills and e.name < most.name)) then
			most = { name = e.name, kills = e.kills }
		end
	end

	local days = 1
	local elapsed = call("RoundService", "getElapsed")
	if type(elapsed) == "number" then
		local ok, day = pcall(function()
			return DayCycle.dayOf(DayCycle.clockAt(elapsed))
		end)
		if ok and type(day) == "number" then
			days = math.max(1, math.floor(day))
		end
	end

	local winnerRow = nil
	if winner then
		for _, row in ipairs(rows) do
			if row.userId == winner.UserId then
				winnerRow = { name = row.name, userId = row.userId, kills = row.kills, survived = row.survived }
				break
			end
		end
	end
	local aliveCount = math.floor(tonumber(GameState:GetAttribute("AliveCount")) or 0)
	return {
		roundId = c.roundId,
		endedAt = endedAt,
		contenders = count,
		days = days,
		duration = math.floor(duration + 0.5),
		winner = winnerRow,
		title = if winnerRow then nil elseif aliveCount > 1 then "Time's up" else "No survivors",
		rows = rows,
		facts = { firstFall = firstFall, mostDefeats = most, border = border, early = early },
	}
end

local function onRoundEnded(winner: Player?)
	-- a round cancelled in the Countdown, and a practice round, leave the board as it was
	if GameState:GetAttribute("Phase") ~= "Ending" or GameState:GetAttribute("Practice") == true then
		current = nil
		return
	end
	local ok, result = pcall(build, winner)
	current = nil
	if not ok then
		warn("[ResultsBoardService] could not build the result: " .. tostring(result))
		return
	end
	if result and #result.rows > 0 then
		last = result
		if remote then
			remote:FireAllClients("result", result)
		end
	end
end

function ResultsBoardService.getLast(): { [string]: any }?
	return last
end

function ResultsBoardService.Init(services)
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

function ResultsBoardService.Start()
	local event = remote
	if not event then
		return
	end
	event.OnServerEvent:Connect(function(player: Player, action: any)
		if action == "get" and Net.rateLimit(player, "RoundResult", 0.5, 3) then
			event:FireClient(player, "result", last)
		end
	end)
	local rs = Services and Services.RoundService
	local ps = Services and Services.PlayerService
	if rs and rs.roundStarted and rs.roundEnded then
		rs.roundStarted:Connect(onRoundStarted)
		rs.roundEnded:Connect(onRoundEnded)
	else
		warn("[ResultsBoardService] RoundService signals missing: the results board stays empty")
	end
	if ps and ps.died then
		ps.died:Connect(onDied)
	end
end

return ResultsBoardService
