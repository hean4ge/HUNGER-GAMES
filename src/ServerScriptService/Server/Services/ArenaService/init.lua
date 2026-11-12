--[[
	ArenaService - what the arena itself does during a round.
	  * The day/night clock (Shared.DayCycle, Config.Round.DaySchedule): two days in one round, with a real night
	    between them. The server never steps Lighting.ClockTime; it publishes a time base in the GameState attribute
	    "Clock" (DayCycle.encodeClock: clock at a server time + rate, then the next rate) and every client sets
	    ClockTime and the whole lighting look itself every frame (ArenaController). GameState "Day" = current day.
	  * The border (Config.Border): GameState BorderCenter / BorderRadius / BorderTargetRadius / BorderShrinking,
	    a Warning WarningLeadTime seconds before it moves, and damage to alive contenders outside it
	    (PlayerService.damage, cause "Border", position = the nearest point of the wall).
	  * The Feast (Config.Events): Warning FeastWarning seconds before, then LootService.refillSpire(), the FeastBell
	    and GameState.ArenaEvent = "Feast" for FeastDuration seconds.
	  * The Roll Call ("The Fallen") at each dusk (Config.Round.RollCallClockTime on every day): everyone who fell since
	    the last Roll Call. Announce { style = "RollCall", text = "The Fallen", sub, day, names, entries, startAt,
	    duration, id } and the same payload as JSON in GameState "RollCall" (late joiners join the show mid-way).
	    entries[i] = { name, userId, snapshot } where snapshot names a model in ReplicatedStorage.FallenSnapshots
	    (FallenSnapshots helper: an avatar snapshot taken when they fell; clients turn it into a point cloud).
	    Payload extras (PlayabilityPlan QW14): sky (false = post the names in the 2D list only: a Roll Call that falls
	    once the border moves, so the final fight keeps its music), mode ("epilogue" = the short show, DayCycle),
	    list (false = no 2D list: the epilogue plays behind the winner card, which has the placements).
	  * Playability (docs/design/PlayabilityPlan.md): the border starts at GameState.BorderStartRadius (RoundService,
	    QW3). With Config.Round.LastStand (QW14) the ring keeps closing after ShrinkDuration, from FinalRadius to
	    nothing over Config.Border.LastStandDuration, its centre sliding while it closes to a point beside the Spire
	    (FinalSpireGap studs past the Spire's base, open plaza, picked per round); outside the Last Stand ring the
	    damage rises with every second spent outside, and the border never takes the last contender standing (outside
	    practice). GameState.LastStand = true while the finale runs.
	API:
	  ArenaService.isInsideBorder(position: Vector3) -> boolean   (always true outside Active)
	  ArenaService.getFallen() -> { string }                       this round's fallen, in order
	  ArenaService.getBorder() -> (center: Vector3, radius: number)
	  ArenaService.getClock() -> (clock: number, day: number)      unwrapped hours (31 = 07:00 on day 2)
	  ArenaService.startRollCall(day?) -> boolean                  run a Roll Call now with everyone pending
	  ArenaService.startEpilogue(leadIn?) -> number?               QW14: the short Roll Call of the fallen not yet shown
	                                                               in the sky (RoundService calls it as the round ends);
	                                                               seconds until it is over, or nil when nobody is left
	Practice rounds: the Last Stand ring stops at Config.Border.PracticeLastStandRadius, so a lone contender can survive
	it. Studio: GameState DevEpilogue = n plays the epilogue with n fake fallen (like DevRollCall below).
	Studio only: GameState:SetAttribute("DevRollCall", n) on the server (command bar) runs a Roll Call with n fake
	fallen entries made from the first player's avatar (n = 0 shows the "no one fell" version).
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))
local FallenSnapshots = require(script:WaitForChild("FallenSnapshots"))
local LoreModule = Shared:FindFirstChild("Lore")
local Lore = if LoreModule and LoreModule:IsA("ModuleScript") then require(LoreModule) :: any else nil
local ThreatLineModule = Shared:FindFirstChild("ThreatLine")
local ThreatLine = if ThreatLineModule and ThreatLineModule:IsA("ModuleScript") then require(ThreatLineModule) :: any else nil

-- QW9: the words of the arena's warnings, in Shared.ThreatLine's one format with Shared.Lore's names (the HUD's
-- event line uses the same). Plain fallbacks keep the warnings working if either module is missing.
local function lore(key: string, fallback: string): string
	local value = Lore and Lore[key]
	return if type(value) == "string" then value else fallback
end

local function headline(threat: { [string]: any }, fallbackTitle: string, fallbackSub: string): (string, string)
	if ThreatLine and type(ThreatLine.headline) == "function" then
		local ok, title, sub = pcall(ThreatLine.headline, threat)
		if ok and type(title) == "string" and title ~= "" then
			return title, if type(sub) == "string" then sub else ""
		end
	end
	return fallbackTitle, fallbackSub
end

local GameState = ReplicatedStorage:WaitForChild("GameState")
local RoundCfg = Config.Round
local BorderCfg = Config.Border
local EventsCfg = Config.Events

local TICK = 0.2 -- border, events and time-base checks per second: 5 (clients animate the clock every frame)

local ArenaService = {}

local Services = nil
local fallen = {} -- display names, in order of falling (this round)
local pending = {} -- { name, userId, snapshot } fallen since the last Roll Call
local unshown = {} -- QW14: the same entries, kept until a sky show has shown them (the epilogue shows the rest)
local outsideSince = {} -- QW14: [Player] = server time first seen outside the Last Stand ring
local rng = Random.new()
local trackedRound = nil
local borderCenter = Vector3.new(ArenaLayout.Center.X, ArenaLayout.BaseHeight, ArenaLayout.Center.Z)
local baseCenter = borderCenter -- the Spire: where the ring starts
local finalCenter: Vector3? = nil -- QW14: where it closes (beside the Spire, picked once per round)
local borderRadius = BorderCfg.StartRadius
local warned = {}
local clockKey = nil -- identifies the published time base (avoids re-publishing an identical one)
local currentClock = RoundCfg.LobbyClockTime
local endingClock = nil -- the clock held during Ending
local rollCallSeq = 0

local function newEvents()
	return {
		borderWarned = false,
		borderMoving = false,
		borderClosed = false,
		feastWarned = false,
		feastDone = false,
		feastEndsAt = 0,
		rollCallsDone = {}, -- [day] = true
		lastDamageAt = 0,
		lastStandAt = 0, -- server time the Last Stand began
	}
end
local ev = newEvents()

-- Helpers ----------------------------------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[ArenaService] " .. message)
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
		warn(string.format("[ArenaService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getPhase(): string
	return GameState:GetAttribute("Phase") or "Lobby"
end

local function announce(payload: { [string]: any })
	Net.event("Announce"):FireAllClients(payload)
end

local function setAttr(name: string, value: any)
	if GameState:GetAttribute(name) ~= value then
		GameState:SetAttribute(name, value)
	end
end

local function timeScale(): number
	local rs = Services and Services.RoundService
	if rs and type(rs.getTimeScale) == "function" then
		local ok, scale = pcall(rs.getTimeScale)
		if ok and type(scale) == "number" and scale > 0 then
			return scale
		end
	end
	return 1
end

local function roundStartedAt(): number
	return tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
end

-- Round-schedule seconds since the start horn.
local function roundElapsed(): number
	local startedAt = roundStartedAt()
	if startedAt <= 0 then
		return 0
	end
	return math.max(0, (now() - startedAt) * timeScale())
end

local function clearRollCall()
	if GameState:GetAttribute("RollCall") ~= nil then
		GameState:SetAttribute("RollCall", nil)
	end
end

local function ensureRound()
	local id = GameState:GetAttribute("RoundId") or 0
	if id ~= trackedRound then
		trackedRound = id
		table.clear(fallen)
		table.clear(pending)
		table.clear(unshown)
		table.clear(outsideSince)
		ev = newEvents()
		endingClock = nil
		finalCenter = nil -- a new point for the new round (resetBorder / centerAt pick it)
	end
end

-- Clock time base ----------------------------------------------------------------------------------------------------

-- Publish "clock = c0 at server time t0, moving `rate` hours per second until t1, then `nextRate`".
local function publishClock(c0: number, t0: number, rate: number, t1: number, nextRate: number)
	local day = DayCycle.dayOf(c0)
	local key = string.format("%.4f|%.2f|%.8f|%.2f|%.8f", c0, t0, rate, t1, nextRate)
	if key == clockKey then
		return
	end
	clockKey = key
	GameState:SetAttribute("Clock", DayCycle.encodeClock(c0, t0, rate, t1, nextRate, day))
end

local function holdClock(clock: number)
	currentClock = clock
	publishClock(clock, 0, 0, 0, 0) -- rate 0: the anchor time doesn't matter
	setAttr("Day", DayCycle.dayOf(clock))
end

-- During Active: the schedule segment we're in, converted from round-schedule seconds to server time.
local function runClock(elapsed: number)
	local scale = timeScale()
	local startedAt = roundStartedAt()
	local s0, c0, s1, c1, nextRate = DayCycle.segmentAt(elapsed)
	local t0 = startedAt + s0 / scale
	local t1 = startedAt + s1 / scale
	local rate = (c1 - c0) / math.max(1e-3, t1 - t0)
	publishClock(c0, t0, rate, t1, nextRate * scale)
	currentClock = DayCycle.clockAt(elapsed)
	setAttr("Day", DayCycle.dayOf(currentClock))
end

-- Border -----------------------------------------------------------------------------------------------------------

local function computeCenter(): Vector3
	local arena = workspace:FindFirstChild("Arena")
	local center = arena and arena:GetAttribute("Center")
	local base = if typeof(center) == "Vector3" then center else ArenaLayout.Center
	return Vector3.new(base.X, ArenaLayout.BaseHeight, base.Z)
end

local function lastStandOn(): boolean
	return RoundCfg.LastStand ~= false
end

-- QW14 in practice: a lone contender has no rival to outlast, so the Last Stand ring stops at
-- Config.Border.PracticeLastStandRadius instead of nothing. Standing in it survives the practice round; staying out
-- still teaches what the border does.
local function lastStandFloor(): number
	if GameState:GetAttribute("Practice") == true then
		return math.clamp(tonumber(BorderCfg.PracticeLastStandRadius) or 0, 0, BorderCfg.FinalRadius)
	end
	return 0
end

-- QW3: this round's starting radius (RoundService publishes it at the Countdown)
local function startRadius(): number
	local r0 = tonumber(GameState:GetAttribute("BorderStartRadius"))
	if r0 and r0 > 0 then
		return r0
	end
	return BorderCfg.StartRadius
end

-- QW14: close it beside the Spire, not on it: open, level plaza ground FinalSpireGap studs past the Spire's base, so
-- nobody can circle the monolith in the last fight.
local function pickFinalCenter(center: Vector3): Vector3
	if not lastStandOn() then
		return center
	end
	local info = ArenaLayout.AssetInfo and ArenaLayout.AssetInfo.Spire
	local spireR = tonumber(info and info.r) or 20
	local gap = BorderCfg.FinalSpireGap or { 15, 25 }
	local low, high = tonumber(gap[1]) or 15, tonumber(gap[2]) or tonumber(gap[1]) or 25
	local maxR = (ArenaLayout.PlazaRadius or 62) - 6
	local characters = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(characters, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local fallback: Vector3? = nil
	for _ = 1, 16 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local d = math.min(maxR, spireR + rng:NextNumber(math.min(low, high), math.max(low, high)))
		local p = Vector3.new(center.X + math.sin(angle) * d, center.Y, center.Z - math.cos(angle) * d)
		fallback = fallback or p
		local hit = workspace:Raycast(p + Vector3.new(0, 80, 0), Vector3.new(0, -140, 0), params)
		if hit and math.abs(hit.Position.Y - center.Y) < 2 and hit.Normal.Y > 0.96 then
			return p
		end
	end
	return fallback or center
end

-- While the border closes, its centre slides from the Spire to finalCenter (slow enough that each ring holds the next).
local function ensureFinalCenter(): Vector3
	if not finalCenter then
		local ok, point = pcall(pickFinalCenter, baseCenter)
		finalCenter = if ok and typeof(point) == "Vector3" then point else baseCenter
	end
	return finalCenter :: Vector3
end

local function centerAt(elapsed: number): Vector3
	if not lastStandOn() then
		return baseCenter
	end
	local t = math.clamp((elapsed - BorderCfg.ShrinkStartTime) / math.max(1, BorderCfg.ShrinkDuration), 0, 1)
	return baseCenter:Lerp(ensureFinalCenter(), t)
end

local function radiusAt(elapsed: number): number
	local r0 = startRadius()
	local start = BorderCfg.ShrinkStartTime
	if elapsed <= start then
		return r0
	end
	local closeAt = start + math.max(1, BorderCfg.ShrinkDuration)
	if elapsed <= closeAt or not lastStandOn() then
		local t = math.clamp((elapsed - start) / math.max(1, BorderCfg.ShrinkDuration), 0, 1)
		return r0 + (BorderCfg.FinalRadius - r0) * t
	end
	-- the Last Stand: from FinalRadius to nothing (to the practice floor in a practice round)
	local t = math.clamp((elapsed - closeAt) / math.max(1, BorderCfg.LastStandDuration or 55), 0, 1)
	local floor = lastStandFloor()
	return floor + (BorderCfg.FinalRadius - floor) * (1 - t)
end

local function publishBorder(radius: number, target: number, shrinking: boolean)
	borderRadius = radius
	setAttr("BorderCenter", borderCenter)
	local current = GameState:GetAttribute("BorderRadius")
	local rounded = math.floor(radius * 100 + 0.5) / 100
	if type(current) ~= "number" or math.abs(current - rounded) >= 0.05 or (rounded == target and current ~= rounded) then
		GameState:SetAttribute("BorderRadius", rounded)
	end
	setAttr("BorderTargetRadius", target)
	setAttr("BorderShrinking", shrinking)
end

local function resetBorder()
	baseCenter = computeCenter()
	borderCenter = baseCenter
	if getPhase() == "Countdown" then
		ensureFinalCenter()
	end
	local r0 = startRadius()
	publishBorder(r0, r0, false)
	setAttr("LastStand", false)
end

local function updateBorder(elapsed: number)
	local scale = timeScale()
	local shrinkStart = BorderCfg.ShrinkStartTime
	local shrinkEnd = shrinkStart + BorderCfg.ShrinkDuration
	if not ev.borderWarned and elapsed >= shrinkStart - BorderCfg.WarningLeadTime and elapsed < shrinkStart then
		ev.borderWarned = true
		local seconds = math.max(1, math.ceil((shrinkStart - elapsed) / scale))
		local toSpire = "Head for " .. lore("Spire", "the Spire")
		local title, sub = headline({ name = "Border", verb = "moves", action = toSpire, seconds = seconds },
			string.format("THE BORDER MOVES IN %d SECONDS", seconds), toSpire)
		announce({ style = "Warning", text = title, sub = sub, duration = 6 })
		Sfx.play("BorderWarning")
	end
	local lastStand = lastStandOn()
	local shrinking = elapsed >= shrinkStart
		and elapsed < (if lastStand then shrinkEnd + (BorderCfg.LastStandDuration or 55) else shrinkEnd)
	if shrinking and not ev.borderMoving then
		ev.borderMoving = true
		ev.borderWarned = true
		local toSpire = "Head for " .. lore("Spire", "the Spire") .. " and stay inside the ring"
		local title, sub = headline({ name = "Border", verb = "is moving", action = toSpire }, "THE BORDER IS MOVING", toSpire)
		announce({ style = "Warning", text = title, sub = sub, duration = 5 })
		Sfx.play("BorderWarning")
	end
	if elapsed >= shrinkEnd and not ev.borderClosed then
		ev.borderClosed = true
		ev.borderMoving = true
		ev.borderWarned = true
		if lastStand then
			-- QW14: the finale. The ring closes to nothing beside the Spire.
			ev.lastStandAt = now()
			local title = "THE LAST STAND"
			if Lore and type(Lore.upper) == "function" then
				local ok, name = pcall(Lore.upper, "LastStand")
				if ok and type(name) == "string" and name ~= "" then
					title = name
				end
			end
			local sub = if lastStandFloor() > 0 then "The ring closes in · stay inside it" else "The ring closes to nothing"
			announce({ style = "Warning", text = title, sub = sub, duration = 6 })
			Sfx.play("BorderWarning")
		else
			local border = lore("Border", "the border")
			announce({
				style = "Toast",
				text = string.upper(string.sub(border, 1, 1)) .. string.sub(border, 2) .. " has closed",
				sub = "Outside it, you won't last long",
				duration = 4,
			})
		end
	end
	local target = if not ev.borderWarned then startRadius()
		elseif lastStand and ev.borderClosed then lastStandFloor()
		else BorderCfg.FinalRadius
	borderCenter = centerAt(elapsed)
	publishBorder(radiusAt(elapsed), target, shrinking)
	setAttr("LastStand", lastStand and ev.borderClosed) -- GameState.LastStand: the finale is on (HUD)
end

local function borderDamage(t: number)
	if t - ev.lastDamageAt < 1 then
		return
	end
	local dt = if ev.lastDamageAt > 0 then math.min(t - ev.lastDamageAt, 2) else 1
	ev.lastDamageAt = t
	local ps = Services and Services.PlayerService
	if not ps then
		return
	end
	local dps = if ev.borderClosed then BorderCfg.LateDamagePerSecond else BorderCfg.DamagePerSecond
	local lastStand = lastStandOn()
	local alive = ps.getAlivePlayers()
	local health = {}
	for _, player in ipairs(alive) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		health[player] = if humanoid then humanoid.Health else 0
	end
	if lastStand then
		-- weakest first: if the ring takes several at once, the healthiest is the last one standing
		table.sort(alive, function(a, b)
			return health[a] < health[b]
		end)
	end
	local standing = #alive
	for _, player in ipairs(alive) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = root.Position
			local dx, dz = p.X - borderCenter.X, p.Z - borderCenter.Z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance > borderRadius then
				local k = borderRadius / math.max(distance, 0.001)
				local edge = Vector3.new(borderCenter.X + dx * k, p.Y, borderCenter.Z + dz * k)
				local amount = dps * dt
				if lastStand and ev.borderClosed then
					-- the Last Stand: the longer you stay out, the more it hurts
					local since = outsideSince[player]
					if not since then
						since = t
						outsideSince[player] = t
					end
					local outFor = math.max(0, t - math.max(since, ev.lastStandAt))
					amount = ((BorderCfg.LastStandDamagePerSecond or 10) + (BorderCfg.LastStandDamageRamp or 2) * outFor) * dt
				end
				-- the border never takes the last contender standing: every round has a winner (a lone practice
				-- contender can still learn what the border does)
				if lastStand and standing <= 1 and GameState:GetAttribute("Practice") ~= true then
					amount = math.min(amount, math.max(0, (health[player] or 0) - 1))
				end
				if amount > 0 and ps.damage(player, amount, { cause = "Border", position = edge }) then
					standing -= 1
				end
			else
				outsideSince[player] = nil
			end
		end
	end
end

-- The Feast ----------------------------------------------------------------------------------------------------------

local function updateFeast(elapsed: number, t: number)
	local feastTime = EventsCfg.FeastTime
	if not ev.feastWarned and elapsed >= feastTime - EventsCfg.FeastWarning and elapsed < feastTime then
		ev.feastWarned = true
		local seconds = math.max(1, math.ceil((feastTime - elapsed) / timeScale()))
		local spire = lore("Spire", "the Spire")
		local restocks = string.upper(string.sub(spire, 1, 1)) .. string.sub(spire, 2) .. " restocks"
		local title, sub = headline({ name = "Offering", action = restocks, seconds = seconds },
			string.upper(lore("Offering", "the Offering")), string.format("%s in %d seconds", restocks, seconds))
		announce({ style = "Warning", text = title, sub = sub, duration = 6 })
	end
	if not ev.feastDone and elapsed >= feastTime then
		ev.feastDone = true
		ev.feastWarned = true
		task.spawn(call, "LootService", "refillSpire")
		Sfx.play("FeastBell")
		setAttr("ArenaEvent", "Feast")
		ev.feastEndsAt = t + (EventsCfg.FeastDuration or 30)
		local spire = lore("Spire", "the Spire")
		announce({
			style = "Banner",
			text = string.upper(lore("Offering", "the Offering")),
			sub = string.upper(string.sub(spire, 1, 1)) .. string.sub(spire, 2) .. " has been restocked",
			duration = 5,
		})
	end
	if ev.feastEndsAt > 0 and t >= ev.feastEndsAt then
		ev.feastEndsAt = 0
		setAttr("ArenaEvent", "")
	end
end

-- The Roll Call ------------------------------------------------------------------------------------------------------

local function rollCallSub(day: number, count: number): string
	if count == 0 then
		return string.format("Day %d · No one fell", day)
	elseif count == 1 then
		return string.format("Day %d · One contender fell", day)
	end
	return string.format("Day %d · %d contenders fell", day, count)
end

-- opts (QW14): { sky = false (2D list only), mode = "epilogue", list = false (no 2D list), leadIn = seconds }.
-- Returns true and the seconds from now until the show is over.
local function runRollCall(day: number, entries: { { [string]: any } }, opts: { [string]: any }?): (boolean, number)
	local options = opts or {}
	local names = {}
	for _, entry in ipairs(entries) do
		table.insert(names, entry.name)
	end
	rollCallSeq += 1
	local leadIn = tonumber(options.leadIn) or DayCycle.Recap.LeadIn or 1
	local startAt = now() + leadIn
	local duration = DayCycle.recapDuration(#entries, options.mode)
	local payload = {
		style = "RollCall",
		text = "The Fallen",
		sub = rollCallSub(day, #entries),
		day = day,
		names = names,
		entries = entries,
		startAt = startAt,
		duration = duration,
		id = string.format("%s-%d-%d", tostring(GameState:GetAttribute("RoundId") or 0), day, rollCallSeq),
		sky = options.sky ~= false,
		mode = options.mode,
		list = options.list ~= false,
	}
	local ok, json = pcall(HttpService.JSONEncode, HttpService, payload)
	if ok then
		GameState:SetAttribute("RollCall", json)
	end
	announce(payload)
	local id = payload.id
	task.delay(duration + 2, function()
		local current = GameState:GetAttribute("RollCall")
		if type(current) == "string" and string.find(current, id, 1, true) then
			clearRollCall()
		end
	end)
	return true, leadIn + duration
end

local function updateRollCall(clock: number, elapsed: number)
	local day = DayCycle.dayOf(clock)
	if ev.rollCallsDone[day] or clock + 1e-6 < DayCycle.rollCallClock(day) then
		return
	end
	ev.rollCallsDone[day] = true
	local entries = table.clone(pending)
	table.clear(pending)
	-- QW14: once the border moves the final fight is on. Its Roll Call (Roll Call 2, 14:05) posts the names in the 2D
	-- list only: the sky show and its silence would stop the final-stand music. The epilogue shows them in the sky.
	local sky = not (lastStandOn() and elapsed >= BorderCfg.ShrinkStartTime)
	if sky then
		table.clear(unshown)
	end
	runRollCall(day, entries, { sky = sky })
end

-- Loop ---------------------------------------------------------------------------------------------------------------

local lastPhase = nil

local function step()
	ensureRound()
	local phase = getPhase()
	local t = now()
	if phase == "Active" then
		local elapsed = roundElapsed()
		runClock(elapsed)
		updateBorder(elapsed)
		updateFeast(elapsed, t)
		updateRollCall(currentClock, elapsed)
		borderDamage(t)
		endingClock = nil
	elseif phase == "Ending" then
		-- hold the clock and the border where the round ended
		if endingClock == nil then
			endingClock = if roundStartedAt() > 0 then DayCycle.clockAt(roundElapsed()) else currentClock
			holdClock(endingClock)
		end
		if ev.feastEndsAt > 0 and t >= ev.feastEndsAt then
			ev.feastEndsAt = 0
			setAttr("ArenaEvent", "")
		end
	else
		if phase == "Countdown" then
			holdClock(DayCycle.clockAt(0))
		else
			holdClock(RoundCfg.LobbyClockTime)
		end
		resetBorder()
		ev.feastEndsAt = 0
		setAttr("ArenaEvent", "")
		if phase ~= lastPhase and phase == "Countdown" then
			clearRollCall()
		end
	end
	lastPhase = phase
end

local function onDied(victim: Player, _killer: Player?, _cause: string)
	ensureRound()
	local ok, name = pcall(function()
		return victim.DisplayName
	end)
	if not (ok and type(name) == "string" and name ~= "") then
		return
	end
	table.insert(fallen, name)
	local snapOk, snapshot = pcall(FallenSnapshots.capture, victim, victim.Character)
	local entry = {
		name = name,
		userId = victim.UserId,
		snapshot = if snapOk and type(snapshot) == "string" then snapshot else "",
	}
	table.insert(pending, entry)
	table.insert(unshown, entry)
end

-- Studio: fake Roll Call entries made from the first player's avatar ---------------------------------------------------

local DEV_NAMES = {
	"Ashgrove_Kid", "TheQuietOne", "x_Wren_x", "Marrow", "SilasVane", "Juniper_Fox", "Bramble99", "Captain_Halloway",
	"Odessa", "nightjar_", "Kestrel", "Ivy", "Tamsin_R", "Hollowbrook", "Quill", "Emberly", "Rook", "Sable_Moss",
	"Thistle", "Corvin_07", "Lark", "Ferris", "Wynn",
}

local function devRollCall(count: number, opts: { [string]: any }?)
	count = math.clamp(math.floor(count), 0, 23)
	local source = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			source = p
			break
		end
	end
	local entries = {}
	if count > 0 then
		local snapshot = ""
		if source then
			local ok, name = pcall(FallenSnapshots.capture, source, source.Character)
			if ok then
				snapshot = name
			end
		end
		for i = 1, count do
			local name = if i == 1 and source then source.DisplayName else DEV_NAMES[((i - 2) % #DEV_NAMES) + 1]
			table.insert(entries, { name = name, userId = if source then source.UserId else 0, snapshot = snapshot })
		end
	end
	-- give the snapshot a moment to build and replicate before the show starts
	task.delay(if count > 0 then 2 else 0, function()
		local _, day = ArenaService.getClock()
		runRollCall(day, entries, opts)
	end)
end

-- Public API ---------------------------------------------------------------------------------------------------------

function ArenaService.isInsideBorder(position: Vector3): boolean
	if typeof(position) ~= "Vector3" or getPhase() ~= "Active" then
		return true
	end
	local dx, dz = position.X - borderCenter.X, position.Z - borderCenter.Z
	return dx * dx + dz * dz <= borderRadius * borderRadius
end

function ArenaService.getFallen(): { string }
	return table.clone(fallen)
end

function ArenaService.getBorder(): (Vector3, number)
	return borderCenter, borderRadius
end

function ArenaService.getClock(): (number, number)
	return currentClock, DayCycle.dayOf(currentClock)
end

function ArenaService.startRollCall(day: number?): boolean
	local entries = table.clone(pending)
	table.clear(pending)
	table.clear(unshown)
	local _, currentDay = ArenaService.getClock()
	return (runRollCall(day or currentDay, entries))
end

-- QW14: the epilogue. The fallen not yet shown in the sky (Roll Call 2 is list-only during the finale; or the round
-- ended before dusk) get the short show - the day caption, then all of them together - behind the winner card.
-- Returns the seconds until it is over, or nil when there is no one to show.
function ArenaService.startEpilogue(leadIn: number?): number?
	ensureRound()
	if #unshown == 0 then
		return nil
	end
	local entries = table.clone(unshown)
	table.clear(unshown)
	table.clear(pending)
	local _, length = runRollCall(DayCycle.dayOf(currentClock), entries, { mode = "epilogue", list = false, leadIn = leadIn })
	return length
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function ArenaService.Init(registry)
	Services = registry
	borderCenter = computeCenter()
end

function ArenaService.Start()
	local ps = Services and Services.PlayerService
	if ps and ps.died then
		ps.died:Connect(onDied)
	else
		warnOnce("died", "PlayerService.died is not available; the Roll Call will be empty.")
	end
	local rs = Services and Services.RoundService
	if rs and rs.roundStarting then
		-- a new round: last round's snapshots and show go
		rs.roundStarting:Connect(function()
			FallenSnapshots.clear()
			clearRollCall()
		end)
	end
	FallenSnapshots.folder()
	clearRollCall()
	if RunService:IsStudio() then
		GameState:GetAttributeChangedSignal("DevRollCall"):Connect(function()
			local n = GameState:GetAttribute("DevRollCall")
			if type(n) == "number" then
				GameState:SetAttribute("DevRollCall", nil)
				devRollCall(n)
			end
		end)
		-- QW14 test: GameState DevEpilogue = n plays the epilogue (short show, no 2D list) with n fake fallen, e.g.
		-- behind a practice round's winner card
		GameState:GetAttributeChangedSignal("DevEpilogue"):Connect(function()
			local n = GameState:GetAttribute("DevEpilogue")
			if type(n) == "number" then
				GameState:SetAttribute("DevEpilogue", nil)
				devRollCall(math.max(1, n), { mode = "epilogue", list = false, leadIn = RoundCfg.EpilogueLeadIn or 2.5 })
			end
		end)
	end
	resetBorder()
	-- the initial replicated value only; clients drive ClockTime from the "Clock" time base from here on
	Lighting.ClockTime = RoundCfg.LobbyClockTime % 24
	holdClock(RoundCfg.LobbyClockTime)
	while true do
		local ok, err = pcall(step)
		if not ok then
			warnOnce("step:" .. tostring(err), "Arena step failed: " .. tostring(err))
		end
		task.wait(TICK)
	end
end

return ArenaService
