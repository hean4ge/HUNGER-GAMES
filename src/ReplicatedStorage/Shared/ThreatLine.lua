--[[
	ThreatLine - one format for every arena beat and threat, client and server (PlayabilityPlan P5, QW9):
	    NAME · WHAT TO DO · WHERE · WHEN          e.g. "THE BORDER  ·  HEAD FOR THE SPIRE  ·  1:30"
	Names come from Shared.Lore. The HUD's event line (HUDController) and ArenaService's warnings build their text here,
	so a threat reads the same wherever it shows. Phase 2a's Warden broadcasts should use it too.

	A threat is a table:
	  name     a Shared.Lore key ("Border", "Offering", "LastStand", ...) or literal text
	  verb     optional, joined to the name: "moves" -> "THE BORDER MOVES"
	  action   optional, what to do: "Head for the Spire"
	  where    optional: "at the Spire"
	  seconds  optional, the time left (it counts down, like the HUD clock)
	ThreatLine.line(t, short?) -> "THE BORDER MOVES  ·  HEAD FOR THE SPIRE  ·  0:30"   one sentence-case line (the HUD).
	                              short = true keeps only the name and the time (phones).
	ThreatLine.headline(t) -> (title, sub)   for Announce: ("THE BORDER MOVES IN 30 SECONDS", "Head for the Spire");
	                              without a verb the time goes in the sub: ("THE OFFERING", "The Spire restocks in 45 seconds")
	ThreatLine.clock(seconds) -> "1:30"      ThreatLine.spoken(seconds) -> "30 seconds" | "2 minutes"
	ThreatLine.beats() -> { { key, at, day? } }   the round's scheduled beats from Config, in time order. key is
	                              "RollCall" | "Offering" | "BorderMoves" | "BorderCloses" | "TimeLimit"; at = round-schedule
	                              seconds after the horn (divide by the time scale for real seconds)
	ThreatLine.nextBeat(elapsed, keys?) -> (beat?, scheduleSecondsUntil?)   the first beat still to come (keys: a set
	                              { [key] = true } to consider; default all)
	The border's first movement is the round's own (docs/design/Map1Build.md decision 11: a big ring starts closing
	before Config.Border.ShrinkStartTime, so that it never moves faster than MaxShrinkSpeed):
	ThreatLine.borderMovesAt() -> seconds     this round's start: GameState.BorderShrinkStart (ArenaService), else
	                              Config.Border.ShrinkStartTime. beats() puts "BorderMoves" there.
	ThreatLine.fullRingMovesAt() -> seconds   when a full round's ring first moves, from Config alone (for text written
	                              outside a round; the slide of the ring's centre, under half a minute, is left out)
	ThreatLine.dayPart(seconds) -> "the second morning" | "the first evening" | ...   that moment of the round in
	                              words, from Config.Round.DaySchedule
]]
local Shared = script.Parent
local Config = require(Shared:WaitForChild("Config"))
local Lore = require(Shared:WaitForChild("Lore"))

local ThreatLine = {}

ThreatLine.SEPARATOR = "  ·  " -- the HUD line
ThreatLine.SUB_SEPARATOR = " · " -- inside a headline's sub

local function nameOf(key: any): string
	if type(key) ~= "string" then
		return ""
	end
	local value = (Lore :: any)[key]
	if type(value) == "string" then
		return value
	end
	return key
end

local function title(t: { [string]: any }): string
	local text = string.upper(nameOf(t.name))
	if type(t.verb) == "string" and t.verb ~= "" then
		text ..= " " .. string.upper(t.verb)
	end
	return text
end

-- "1:30", rounded like the HUD clock (Util.formatTime)
function ThreatLine.clock(seconds: number): string
	local s = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- "30 seconds", "1 minute", "2 minutes"
function ThreatLine.spoken(seconds: number): string
	local s = math.max(1, math.floor((tonumber(seconds) or 0) + 0.5))
	if s < 90 then
		return s .. (if s == 1 then " second" else " seconds")
	end
	local m = math.floor(s / 60 + 0.5)
	return m .. (if m == 1 then " minute" else " minutes")
end

-- sentence case for the HUD's line (Quiet style, 18 Nov): "The border moves  ·  Head for the Spire  ·  0:42"
local function capFirst(text: string): string
	return (string.gsub(text, "^%l", string.upper))
end

function ThreatLine.line(t: { [string]: any }, short: boolean?): string
	local head = nameOf(t.name)
	if type(t.verb) == "string" and t.verb ~= "" then
		head ..= " " .. t.verb
	end
	local parts = { capFirst(head) }
	if not short then
		if type(t.action) == "string" and t.action ~= "" then
			table.insert(parts, capFirst(t.action))
		end
		if type(t.where) == "string" and t.where ~= "" then
			table.insert(parts, capFirst(t.where))
		end
	end
	if type(t.seconds) == "number" then
		table.insert(parts, ThreatLine.clock(t.seconds))
	end
	return table.concat(parts, ThreatLine.SEPARATOR)
end

function ThreatLine.headline(t: { [string]: any }): (string, string)
	local head = title(t)
	local hasVerb = type(t.verb) == "string" and t.verb ~= ""
	local timed = type(t.seconds) == "number"
	if timed and hasVerb then
		head ..= " IN " .. string.upper(ThreatLine.spoken(t.seconds))
	end
	local parts = {}
	if type(t.action) == "string" and t.action ~= "" then
		table.insert(parts, t.action)
	end
	if type(t.where) == "string" and t.where ~= "" then
		table.insert(parts, t.where)
	end
	local sub = table.concat(parts, ThreatLine.SUB_SEPARATOR)
	if timed and not hasVerb then
		sub = if sub ~= "" then sub .. " in " .. ThreatLine.spoken(t.seconds) else "In " .. ThreatLine.spoken(t.seconds)
	end
	return head, sub
end

-- The round-schedule second at which Config.Round.DaySchedule reaches `clock` (unwrapped hours), if it does.
local function secondsAtClock(clock: number): number?
	local s = Config.Round.DaySchedule
	if type(s) ~= "table" then
		return nil
	end
	for i = 1, #s - 1 do
		local a, b = s[i], s[i + 1]
		if b[2] > a[2] and clock >= a[2] and clock <= b[2] then
			return a[1] + (clock - a[2]) / (b[2] - a[2]) * (b[1] - a[1])
		end
	end
	return nil
end

-- The clock (unwrapped hours) Config.Round.DaySchedule reaches at a round-schedule second.
local function clockAtSeconds(seconds: number): number?
	local s = Config.Round.DaySchedule
	if type(s) ~= "table" or #s == 0 then
		return nil
	end
	if seconds <= s[1][1] then
		return s[1][2]
	end
	for i = 1, #s - 1 do
		local a, b = s[i], s[i + 1]
		if seconds <= b[1] then
			return a[2] + (seconds - a[1]) / math.max(1e-6, b[1] - a[1]) * (b[2] - a[2])
		end
	end
	return s[#s][2]
end

local ORDINALS = { "first", "second", "third", "fourth" }

-- "the second morning": the day and the part of it the round's clock shows at `seconds` (round-schedule seconds).
function ThreatLine.dayPart(seconds: number): string
	local clock = clockAtSeconds(tonumber(seconds) or 0)
	if not clock then
		return "later in the round"
	end
	local day = math.floor(clock / 24) + 1
	local hour = clock % 24
	if hour < 5 and day > 1 then
		day -= 1 -- the small hours belong to the night that began the evening before ("the first night")
	end
	local part = if hour >= 5 and hour < 12 then "morning"
		elseif hour >= 12 and hour < 17 then "afternoon"
		elseif hour >= 17 and hour < 21 then "evening"
		else "night"
	return "the " .. (ORDINALS[day] or "last") .. " " .. part
end

-- When a full round's ring first moves, from Config alone: ShrinkStartTime, or earlier when the ring is too big to
-- close in ShrinkDuration at MaxShrinkSpeed (ArenaService's rule, without the slide of the ring's centre).
function ThreatLine.fullRingMovesAt(): number
	local border = Config.Border
	-- a staged border (Config.Border.Stages) first moves at its first stage
	local stages = border.Stages
	if type(stages) == "table" and type(stages[1]) == "table" and tonumber(stages[1].at) then
		return tonumber(stages[1].at) :: number
	end
	local start = tonumber(border.ShrinkStartTime) or 0
	local speed = tonumber(border.MaxShrinkSpeed)
	if speed and speed > 0 then
		local closeAt = start + (tonumber(border.ShrinkDuration) or 0)
		local travel = math.max(0, (tonumber(border.StartRadius) or 0) - (tonumber(border.FinalRadius) or 0))
		return math.clamp(closeAt - travel / speed, 0, start)
	end
	return start
end

-- When this round's ring first moves: ArenaService publishes it at the Countdown; Config's time otherwise.
function ThreatLine.borderMovesAt(): number?
	local nominal = tonumber(Config.Border.ShrinkStartTime)
	if not nominal then
		return nil
	end
	local state = game:GetService("ReplicatedStorage"):FindFirstChild("GameState")
	local own = if state then tonumber(state:GetAttribute("BorderShrinkStart")) else nil
	if own and own >= 0 and own < nominal then
		return own
	end
	return nominal
end

local cachedBeats: { { [string]: any } }? = nil
local cachedMoves: number? = nil -- the BorderMoves time cachedBeats was built with

function ThreatLine.beats(): { { [string]: any } }
	local moves = ThreatLine.borderMovesAt()
	if cachedBeats and cachedMoves == moves then
		return cachedBeats
	end
	local list = {}
	local rollCall = tonumber(Config.Round.RollCallClockTime) or 19.45
	for day = 1, 3 do
		local at = secondsAtClock((day - 1) * 24 + rollCall)
		if at then
			table.insert(list, { key = "RollCall", at = at, day = day })
		end
	end
	local offering = tonumber(Config.Events.FeastTime)
	if offering then
		table.insert(list, { key = "Offering", at = offering })
	end
	local finalStart = tonumber(Config.Border.ShrinkStartTime)
	if moves and finalStart then
		-- it first moves at the round's own time; it has closed when Config says, whenever it started
		table.insert(list, { key = "BorderMoves", at = moves })
		table.insert(list, { key = "BorderCloses", at = finalStart + (tonumber(Config.Border.ShrinkDuration) or 0) })
	end
	local limit = tonumber(Config.Round.MaxRoundTime)
	if limit then
		table.insert(list, { key = "TimeLimit", at = limit })
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	cachedBeats = list
	cachedMoves = moves
	return list
end

function ThreatLine.nextBeat(elapsed: number, keys: { [string]: boolean }?): ({ [string]: any }?, number?)
	for _, beat in ipairs(ThreatLine.beats()) do
		if beat.at > elapsed and (keys == nil or keys[beat.key]) then
			return beat, beat.at - elapsed
		end
	end
	return nil, nil
end

return ThreatLine
