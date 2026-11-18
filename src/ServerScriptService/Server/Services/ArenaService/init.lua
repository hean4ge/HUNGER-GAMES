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
	  * The arena's own numbers (docs/design/Map1Build.md, decisions 11 and 14) come from Config (laid over it from
	    Config.Maps[Config.Map]) and from Shared.ArenaLayout, never from constants here:
	    - The ring closes in stages when Config.Border.Stages lists them ({ at, over, radius }: Map 1 rests wide open,
	      then closes in four stages with a rest between them), else in one run from ShrinkStartTime over
	      ShrinkDuration. Every stage is warned WarningLeadTime seconds ahead ("THE BORDER MOVES IN 30 SECONDS", "Stage
	      2 of 4"), announced when it moves and when it rests, and published: GameState BorderStage (0 while the ring
	      rests wide open, then the stage's number from its warning on), BorderStageCount, BorderMoving (the wall is
	      moving right now: the wall's pulse), BorderNextMoveAt and BorderMoveEndAt (round-schedule seconds, -1 = none),
	      BorderTargetRadius (where the announced stage stops).
	    - The wall never moves faster than Config.Border.MaxShrinkSpeed (studs a second of round time, the slide of its
	      centre included). A stage always ends when Config says; one that would be too fast starts earlier, as early
	      as it must (never before the stage before it has stopped). The round's own times are published at the
	      Countdown as GameState BorderShrinkStart (the first movement) / BorderShrinkEnd (closed to FinalRadius), in
	      round-schedule seconds (ThreatLine and the HUD's event line read them). GameState.BorderShrinking keeps its
	      meaning: it turns true at ShrinkStartTime, the final closing (music, the event line, a list-only Roll Call),
	      which is the last stage. Earlier stages are slow: BorderRadius falls, warnings say so, nothing else changes.
	    - The ring's centre slides to the Last Stand point in step with its radius (there when it reaches FinalRadius).
	    - Where the Last Stand closes: one of the layout's LastStandPoints when it names them; else, when the layout
	      has Heart.mouths (Map 1), a point 90 to 100 studs out on the centre line of a mouth's open lane; else the
	      classic rule above (PlazaRadius, AssetInfo.Spire.r, FinalSpireGap).
	    - A layout whose Map field is not Config.Map gets one warning at start-up.
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
local EARLY_START = 20 -- seconds before ShrinkStartTime from which the last stage's movement gets its own "slowly" warnings

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
local shrinkStartAt = BorderCfg.ShrinkStartTime -- this round's first movement, round-schedule seconds (<= ShrinkStartTime)
local plan: { { [string]: any } } = {} -- this round's stages (buildPlan): { from, to, fromRadius, radius, moves }
local shrinkRound: any = nil -- the RoundId shrinkStartAt was worked out for (nil outside a round)
local borderRadius = BorderCfg.StartRadius
local warned = {}
local clockKey = nil -- identifies the published time base (avoids re-publishing an identical one)
local currentClock = RoundCfg.LobbyClockTime
local endingClock = nil -- the clock held during Ending
local rollCallSeq = 0

local function newEvents()
	return {
		stageWarned = {}, -- [stage] = true: its warning has gone out (or its time has passed)
		stageStarted = {}, -- [stage] = true: it has started to move
		stageRested = {}, -- [stage] = true: it has stopped
		borderMoving = false, -- the final closing has been announced
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
		finalCenter = nil -- a new point for the new round (resetBorder / centerFor pick it)
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

-- Where the layout says the Last Stand may close (Map1Build.md decision 11: on turf, never on the platform):
--   LastStandPoints   Vector3 points on open ground, when the layout names them;
--   Heart.mouths      (Map 1) the open lane in front of each of the Horn's mouths: a point LAST_STAND_LANE studs out on
--                     the lane's centre line, clear of the platform, the steps and the flower beds.
-- nil when the layout has neither: pickFinalCenter then keeps the classic rule.
local LAST_STAND_LANE = { 90, 100 }

local function layoutLastStandPoints(center: Vector3): { Vector3 }?
	local layout = ArenaLayout :: any
	local list = {}
	if type(layout.LastStandPoints) == "table" then
		for _, p in ipairs(layout.LastStandPoints) do
			if typeof(p) == "Vector3" then
				table.insert(list, Vector3.new(p.X, center.Y, p.Z))
			end
		end
	end
	if #list > 0 then
		return list
	end
	local mouths = if type(layout.Heart) == "table" then layout.Heart.mouths else nil
	if type(mouths) == "table" then
		for _, mouth in ipairs(mouths) do
			local bearing = if type(mouth) == "table" then tonumber(mouth.bearing) else nil
			if bearing then
				local lane = if type(mouth.lane) == "table" then mouth.lane else {}
				local low = math.max(LAST_STAND_LANE[1], (tonumber(lane.fromR) or 0) + 4)
				local high = math.min(LAST_STAND_LANE[2], (tonumber(lane.toR) or math.huge) - 4)
				if high >= low then
					local d = rng:NextNumber(low, high)
					local a = math.rad(bearing)
					table.insert(list, Vector3.new(center.X + math.sin(a) * d, center.Y, center.Z - math.cos(a) * d))
				end
			end
		end
	end
	return if #list > 0 then list else nil
end

-- QW14: close it beside the Spire, not on it: open, level plaza ground FinalSpireGap studs past the Spire's base, so
-- nobody can circle the monolith in the last fight. A layout that says where (above) is followed instead.
local function pickFinalCenter(center: Vector3): Vector3
	if not lastStandOn() then
		return center
	end
	local points = layoutLastStandPoints(center)
	if points then
		return points[rng:NextInteger(1, #points)]
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

-- The shrink as Config times it: (ShrinkStartTime, the second it has closed), round-schedule seconds.
local function nominalShrink(): (number, number)
	local start = BorderCfg.ShrinkStartTime
	return start, start + math.max(1, BorderCfg.ShrinkDuration)
end

-- How far the ring's centre slides while it closes (to the Last Stand point); 0 without the Last Stand.
local function slideDistance(): number
	if not lastStandOn() then
		return 0
	end
	local final = ensureFinalCenter()
	return Vector3.new(final.X - baseCenter.X, 0, final.Z - baseCenter.Z).Magnitude
end

-- This round's closing as a list of stages, in order: { from, to (round-schedule seconds), fromRadius, radius,
-- moves }. Config.Border.Stages gives them ({ at, over, radius }); without it the ring closes in one run from
-- ShrinkStartTime over ShrinkDuration, as it always did.
-- Map1Build.md decision 11: the wall never moves faster than Config.Border.MaxShrinkSpeed. A stage always ends when
-- Config says; one that would be too fast starts earlier, as early as it must (never before the stage before it has
-- stopped, never before the horn). The distance is the radius it loses plus its share of the slide of the ring's
-- centre to the Last Stand point (the centre moves in step with the radius): the far side of the wall moves by both.
-- A stage whose radius the ring is already inside (a smaller starting ring) does not move and is not announced.
local function buildPlan(withSlide: boolean): { { [string]: any } }
	local r0 = startRadius()
	local finalRadius = math.min(BorderCfg.FinalRadius, r0)
	local travel = r0 - finalRadius
	local slide = if withSlide and travel > 0 then slideDistance() / travel else 0
	local speed = tonumber(BorderCfg.MaxShrinkSpeed)
	local stages = BorderCfg.Stages
	if type(stages) ~= "table" or #stages == 0 then
		local nominalStart, closeAt = nominalShrink()
		stages = { { at = nominalStart, over = closeAt - nominalStart, radius = finalRadius } }
	end
	local list = {}
	local radius, previousEnd = r0, 0
	local count = #stages
	for index, stage in ipairs(stages) do
		local at, over, target = tonumber(stage.at), tonumber(stage.over), tonumber(stage.radius)
		if at and over and target then
			if index == count then
				target = finalRadius -- whatever the list says, the last stage ends at the final ring
			end
			target = math.clamp(target, finalRadius, radius)
			local to = math.max(at + math.max(1, over), previousEnd + 1)
			local from = math.min(at, to - 1)
			local distance = (radius - target) * (1 + slide)
			if speed and speed > 0 and distance > 0 then
				from = math.min(from, to - distance / speed)
			end
			from = math.clamp(from, previousEnd, to - 1)
			if speed and speed > 0 and distance / (to - from) > speed + 0.01 then
				warnOnce("stageSpeed" .. index, string.format(
					"Border stage %d would move at %.2f studs/s, over MaxShrinkSpeed %.2f: give it more time in Config.Border.Stages",
					index, distance / (to - from), speed))
			end
			table.insert(list, { from = from, to = to, fromRadius = radius, radius = target, moves = radius - target > 0.01 })
			radius, previousEnd = target, to
		end
	end
	return list
end

-- The second this round's ring has closed to FinalRadius (the Last Stand begins).
local function closeTime(): number
	local last = plan[#plan]
	if last then
		return last.to
	end
	local _, closeAt = nominalShrink()
	return closeAt
end

local function setPlan(list: { { [string]: any } })
	plan = list
	local nominalStart = nominalShrink()
	shrinkStartAt = nominalStart
	for _, stage in ipairs(list) do
		if stage.moves then
			shrinkStartAt = stage.from
			break
		end
	end
	local closeAt = closeTime()
	setAttr("BorderShrinkStart", math.floor(math.min(shrinkStartAt, closeAt - 1) * 10 + 0.5) / 10)
	setAttr("BorderShrinkEnd", closeAt)
	setAttr("BorderStageCount", #list)
end

-- Works out this round's stages and publishes them (the Countdown, once the start radius and the Last Stand point are
-- known; clients count down to GameState.BorderShrinkStart).
local function planShrink()
	setPlan(buildPlan(true))
	shrinkRound = trackedRound
end

local function radiusAt(elapsed: number): number
	local radius = startRadius()
	for _, stage in ipairs(plan) do
		if elapsed <= stage.from then
			return stage.fromRadius
		end
		if elapsed < stage.to then
			return stage.fromRadius + (stage.radius - stage.fromRadius) * (elapsed - stage.from) / (stage.to - stage.from)
		end
		radius = stage.radius
	end
	if not lastStandOn() then
		return radius
	end
	-- the Last Stand: from FinalRadius to nothing (to the practice floor in a practice round)
	local t = math.clamp((elapsed - closeTime()) / math.max(1, BorderCfg.LastStandDuration or 55), 0, 1)
	local floor = math.min(lastStandFloor(), radius)
	return floor + (radius - floor) * (1 - t)
end

-- Where the ring is heading: its own radius until a stage is announced, then that stage's.
local function targetAt(elapsed: number, lead: number): number
	local radius = startRadius()
	for _, stage in ipairs(plan) do
		if elapsed < stage.from - lead then
			return radius
		end
		radius = stage.radius
	end
	return radius
end

-- The ring's centre for a radius: it slides from the Spire to the Last Stand point in step with the radius, so it is
-- there when the ring has closed to FinalRadius and every ring lies inside the one before it.
local function centerFor(radius: number): Vector3
	if not lastStandOn() then
		return baseCenter
	end
	local r0 = startRadius()
	local travel = r0 - BorderCfg.FinalRadius
	local t = if travel > 0 then math.clamp((r0 - radius) / travel, 0, 1) elseif radius < r0 - 0.01 then 1 else 0
	if t <= 0 then
		return baseCenter
	end
	return baseCenter:Lerp(ensureFinalCenter(), t)
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

-- The stage read-outs (for the wall's pulse and for a HUD that wants to count down to the next stage):
--   BorderStage       0 while the ring rests wide open; from a stage's warning on, that stage's number
--   BorderMoving      the wall is moving right now (any stage, and the Last Stand)
--   BorderNextMoveAt  the round-schedule second the next stage starts moving; -1 when none is left
--   BorderMoveEndAt   the round-schedule second the movement under way stops; -1 while the ring rests
local function publishStage(stage: number, moving: boolean, nextMoveAt: number, moveEndAt: number)
	setAttr("BorderStage", stage)
	setAttr("BorderMoving", moving)
	setAttr("BorderNextMoveAt", math.floor(nextMoveAt * 10 + 0.5) / 10)
	setAttr("BorderMoveEndAt", math.floor(moveEndAt * 10 + 0.5) / 10)
end

local function resetBorder()
	baseCenter = computeCenter()
	borderCenter = baseCenter
	if getPhase() == "Countdown" then
		ensureFinalCenter()
		planShrink()
	else
		-- no round: Config's own times (no Last Stand point is picked outside a round)
		setPlan(buildPlan(false))
		shrinkRound = nil
	end
	local r0 = startRadius()
	publishBorder(r0, r0, false)
	publishStage(0, false, math.min(shrinkStartAt, closeTime() - 1), -1)
	setAttr("LastStand", false)
end

local function updateBorder(elapsed: number)
	if shrinkRound ~= trackedRound then
		planShrink() -- (a round whose Countdown this loop never saw)
	end
	local scale = timeScale()
	local lead = BorderCfg.WarningLeadTime
	local count = #plan
	local closeAt = closeTime()
	-- finalStart: Config.Border.ShrinkStartTime, the final closing (GameState.BorderShrinking: the music, the HUD's
	-- line, a list-only Roll Call). With Config.Border.Stages it is the last stage's start. A stage that moves before
	-- it (every stage but the last; the last too when it had to start early to keep to MaxShrinkSpeed) is "slow": its
	-- warnings say so and nothing else changes.
	local finalStart = math.min(BorderCfg.ShrinkStartTime, closeAt - 1)
	local slowly = "Slowly · keep inside the ring"
	local toSpire = "Head for " .. lore("Spire", "the Spire")
	local stageNow, moving, nextMoveAt, moveEndAt = 0, false, -1, -1
	for index, stage in ipairs(plan) do
		if stage.moves then
			local last = index == count
			local slow = not last or stage.from < finalStart - EARLY_START
			local label = if count > 1 then string.format("Stage %d of %d · ", index, count) else ""
			if elapsed >= stage.from - lead then
				stageNow = index
			end
			if elapsed < stage.from and nextMoveAt < 0 then
				nextMoveAt = stage.from
			end
			if elapsed >= stage.from and elapsed < stage.to then
				moving, moveEndAt = true, stage.to
			end
			-- the warning, WarningLeadTime seconds before the stage moves
			if not ev.stageWarned[index] and elapsed >= stage.from - lead then
				ev.stageWarned[index] = true
				if elapsed < stage.from then
					local seconds = math.max(1, math.ceil((stage.from - elapsed) / scale))
					local action = label .. (if slow then slowly else toSpire)
					local title, sub = headline({ name = "Border", verb = "moves", action = action, seconds = seconds },
						string.format("THE BORDER MOVES IN %d SECONDS", seconds), action)
					announce({ style = "Warning", text = title, sub = sub, duration = 6 })
					Sfx.play("BorderWarning")
				end
			end
			-- it moves (the last stage starting on time is announced as the final closing, below)
			if not ev.stageStarted[index] and elapsed >= stage.from then
				ev.stageStarted[index] = true
				if slow and elapsed < math.min(stage.to, if last then finalStart else stage.to) then
					local action = label .. slowly
					local title, sub = headline({ name = "Border", verb = "is moving", action = action }, "THE BORDER IS MOVING", action)
					announce({ style = "Warning", text = title, sub = sub, duration = 5 })
					Sfx.play("BorderWarning")
				end
			end
			-- it rests: say for how long (only when another stage is still to come)
			if not ev.stageRested[index] and elapsed >= stage.to then
				ev.stageRested[index] = true
				local nextStage = nil
				for later = index + 1, count do
					if plan[later].moves then
						nextStage = plan[later]
						break
					end
				end
				if nextStage and elapsed < nextStage.from - lead then
					local border = lore("Border", "the border")
					announce({
						style = "Toast",
						text = string.upper(string.sub(border, 1, 1)) .. string.sub(border, 2) .. " rests",
						sub = "It moves again in " .. tostring(math.max(1, math.ceil((nextStage.from - elapsed) / scale))) .. " seconds",
						duration = 4,
					})
				end
			end
		end
	end
	local lastStand = lastStandOn()
	local standEnd = closeAt + (BorderCfg.LastStandDuration or 55)
	local shrinking = elapsed >= finalStart and elapsed < (if lastStand then standEnd else closeAt)
	if shrinking and not ev.borderMoving then
		ev.borderMoving = true
		local toRing = toSpire .. " and stay inside the ring"
		-- a ring that has been closing in for minutes "closes in" now; one that starts here "is moving", as before
		local before = radiusAt(finalStart - EARLY_START) < startRadius() - 0.5
		local title, sub = headline({ name = "Border", verb = if before then "closes in" else "is moving", action = toRing },
			if before then "THE BORDER CLOSES IN" else "THE BORDER IS MOVING", toRing)
		announce({ style = "Warning", text = title, sub = sub, duration = 5 })
		Sfx.play("BorderWarning")
	end
	if elapsed >= closeAt and not ev.borderClosed then
		ev.borderClosed = true
		ev.borderMoving = true
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
	if lastStand and elapsed >= closeAt and elapsed < standEnd then
		moving, moveEndAt = true, standEnd
	end
	local radius = radiusAt(elapsed)
	local target = if lastStand and ev.borderClosed then lastStandFloor() else targetAt(elapsed, lead)
	borderCenter = centerFor(radius)
	publishBorder(radius, target, shrinking)
	publishStage(stageNow, moving, nextMoveAt, moveEndAt)
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
	count = math.clamp(math.floor(count), 0, math.max(23, (tonumber(RoundCfg.MaxContenders) or 24) - 1)) -- (47 on Map 1)
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
	-- one switch (Map1Build.md decision 14): Config.Map and the layout in the place must be the same arena's. The classic
	-- forest layout (v2) carries no Map field.
	local layoutMap = (ArenaLayout :: any).Map
	if type(layoutMap) ~= "string" then
		layoutMap = "ClassicForest"
	end
	if layoutMap ~= Config.Map then
		warnOnce("map", string.format(
			"Config.Map is %q but Shared.ArenaLayout is the %q arena's: the border, the head count and the timings are another arena's. Set Config.Map (docs/design/Map1Build.md, decision 14).",
			tostring(Config.Map), layoutMap))
	end
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
