--[[
	AllyService - allies, which are the truce the owner approved on 12 Nov ("Yes (Recommended)": a temporary truce
	that "ends on any damage, at the Offering's bell, or when four players are left"), chosen in the prep room before
	the round (the owner, 18 Nov: "the prep room before the arena where they get to choose their allies").
	Design: docs/design/TrainingAndLoadup.md section 4. There is always exactly one winner: nothing is shared (loot,
	placement, the win, kill credit are all as before).

	CHOOSING (both must agree, every time)
	  Remote AllyAsk { op = "offer" | "accept" | "leave", target = userId? } from AllyController: the walk-up gesture
	  (look at a player within Reach studs and hold T) and the quiet list send the same thing. An offer waits OfferTime
	  s; the asker sees "No answer" when it runs out. A refusal is never announced. "offer" to someone who has already
	  offered to you is an accept. A group grows when a member and a newcomer accept each other (the others get
	  "<name> joins your truce"); two groups never merge.
	  Where: the prep room is anywhere a waiting player stands before the call (Lobby, Intermission, and the Ride and
	  Training phases when they exist): both players not InArena and not Alive. In the arena (B12, the gesture truce)
	  two alive contenders of a real round may still agree one during Active, under the same caps and end rules, never
	  after the bell, and never with someone who broke a truce with them this round.
	  Group size by head count (prep: players waiting; arena: AliveCount):
	    4 or fewer: none ("Truces need five or more contenders")   5..11: 2   12..23: 3   24 or more: 4
	THE CALL (GameState.Phase becomes "Countdown")
	  The groups lock. Members who were not picked drop out; a group left with one member ends quietly. A practice round
	  or a round of EndAtAlive (4) or fewer contenders ends every truce at once. Pending offers are dropped.
	  Plinths: RoundService.enterCountdown asks AllyService.assignPlinths(chosen, slots, spotCount) (see that function):
	  group members get plinths at least 360 / (2 * group size) degrees apart, everyone else at random in what is left.
	THE TRUCE ENDS
	  * on any damage between allies, from any source with an attacker (melee, arrows, throws, skills): the attacker
	    leaves the group for everyone in it. Damage between allies is never blocked (the page: "a promise, not a
	    shield"): it lands as normal, and it is the break. The one hit and the rest of the group see "<name> broke the
	    truce", the attacker sees "You broke the truce". The two never truce again this round.
	  * for everyone at the Offering's bell (GameState.ArenaEvent becomes "Feast", or the round clock passes
	    Config.Events.FeastTime): no new truce after it this round.
	  * for everyone when AliveCount <= EndAtAlive (4).
	  * a member who falls or leaves drops out; a group left with one ends.
	  Each end: one soft low bell (the bell and four-left ends) and one quiet line ("The truce is over"); the marks fade
	  over 2 s on the clients (AllyController).
	  The round's end (Ending / Lobby) clears every group and the broken pairs without a word.
	TO THE CLIENT (remote AllyUpdate, per player, never broadcast: who is allied with whom is not public)
	  { kind = "state", allies = { { userId, name } }, cap, context = "prep" | "arena" | "", offersIn = { { userId,
	    name, expiresAt } }, offersOut = { { userId, name, expiresAt } }, size }
	  { kind = "line", text, sub?, tone? = "bell" | "soft" }       one quiet line
	  { kind = "ended", reason = "bell" | "four" | "broke" | "fell" | "left" | "call" | "round", text? }
	Studio only (tests): GameState attribute AllyCapTest (a number) replaces the size cap, AllyEndAtTest replaces
	EndAtAlive.

	API
	  AllyService.getAllies(player) -> { Player }        the others in their group (empty when none)
	  AllyService.allied(a, b) -> boolean
	  AllyService.capFor(count) -> number                the largest group at that head count (0: no truces)
	  AllyService.assignPlinths(chosen, slots, spotCount, rng?) -> { [Player]: number }?
	  AllyService.minGapDegrees(size) -> number          360 / (2 * size)
	  AllyService.checkSpacing(assigned, spotCount) -> (ok, worst)   for tests
	  AllyService.changed: Signal(player)                a player's group changed (VoiceService.setAllies hook)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local DEFAULTS = {
	Enabled = true,
	OfferTime = 15, -- seconds an offer waits for its answer
	Reach = 10, -- studs: the walk-up gesture's reach (the server allows a little more for lag)
	EndAtAlive = 4, -- the truce ends for everyone when this many contenders are left (the owner's rule)
	Caps = { { 4, 0 }, { 11, 2 }, { 23, 3 }, { math.huge, 4 } }, -- { up to this head count, largest group }
}
local S = table.clone(DEFAULTS)
if type((Config :: any).Allies) == "table" then
	for k, v in pairs((Config :: any).Allies) do
		S[k] = v
	end
end

local ASK = "AllyAsk"
local UPDATE = "AllyUpdate"
local IS_STUDIO = RunService:IsStudio()

local AllyService = {}
AllyService.changed = Signal.new()

local Services = nil
type Group = { id: number, members: { Player } }
local groups: { [number]: Group } = {}
local groupOf: { [Player]: Group } = {}
local offers: { [Player]: { [Player]: number } } = {} -- offers[from][to] = expiresAt (os.clock)
local broke: { [Player]: { [Player]: boolean } } = {} -- this round: these two never truce again
local nextId = 0
local truceOver = false -- the bell has rung this round: no new truce
local wrapped = false

-- Helpers -----------------------------------------------------------------------------------------------------------

-- Studio tests only (AllyService._test): stand-in players (tables with __fake) and a stand-in phase, so the rules can
-- be run with as many "players" as a test needs. Never set outside Studio.
local fakes = false
local fakePhase: string? = nil

local function phase(): string
	if fakePhase then
		return fakePhase
	end
	return tostring(GameState:GetAttribute("Phase") or "Lobby")
end

local function isPlayer(p: any): boolean
	if fakes and type(p) == "table" and p.__fake then
		return p.Parent ~= nil
	end
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function service(name: string): any
	return Services and Services[name]
end

local function send(p: Player, payload: { [string]: any })
	if fakes and type(p) == "table" and (p :: any).__fake then
		table.insert((p :: any).inbox, payload)
		return
	end
	if isPlayer(p) then
		Net.event(UPDATE):FireClient(p, payload)
	end
end

local function line(p: Player, text: string, sub: string?, tone: string?)
	send(p, { kind = "line", text = text, sub = sub, tone = tone })
end

local function endAtAlive(): number
	local test = if IS_STUDIO then tonumber(GameState:GetAttribute("AllyEndAtTest")) else nil
	return test or tonumber(S.EndAtAlive) or 4
end

function AllyService.capFor(count: number): number
	local test = if IS_STUDIO then tonumber(GameState:GetAttribute("AllyCapTest")) else nil
	if test then
		return math.clamp(math.floor(test), 0, 4)
	end
	for _, row in ipairs(S.Caps) do
		if count <= row[1] then
			return row[2]
		end
	end
	return 4
end

function AllyService.minGapDegrees(size: number): number
	return 360 / (2 * math.max(1, size))
end

local function isContender(p: Player): boolean
	if fakes and type(p) == "table" then
		return (p :: any):GetAttribute("InArena") == true
	end
	local round = service("RoundService")
	if round and type(round.isContender) == "function" then
		local ok, res = pcall(round.isContender, p)
		return ok and res == true
	end
	return p:GetAttribute("InArena") == true
end

local function aliveCount(): number
	if fakes then
		return tonumber(GameState:GetAttribute("AllyAliveTest")) or 0
	end
	local ps = service("PlayerService")
	if ps and type(ps.getAlivePlayers) == "function" then
		local ok, list = pcall(ps.getAlivePlayers)
		if ok and type(list) == "table" then
			return #list
		end
	end
	return tonumber(GameState:GetAttribute("AliveCount")) or 0
end

-- "prep" (waiting before the call), "arena" (an alive contender of a live real round) or nil (no truce here)
local function contextOf(p: Player): string?
	if not isPlayer(p) then
		return nil
	end
	local ph = phase()
	if ph == "Active" then
		if p:GetAttribute("Alive") == true and p:GetAttribute("InArena") == true and isContender(p)
			and (fakes or GameState:GetAttribute("Practice") ~= true) then
			return "arena"
		end
		return nil
	elseif ph == "Countdown" or ph == "Ending" then
		return nil -- the groups are locked (or the round is over)
	end
	if p:GetAttribute("InArena") ~= true and p:GetAttribute("Alive") ~= true then
		return "prep"
	end
	return nil
end

local function headCount(context: string): number
	if context == "arena" then
		return aliveCount()
	end
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if contextOf(p) == "prep" then
			n += 1
		end
	end
	return n
end

local function capIn(context: string?): number
	if not context then
		return 0
	end
	if context == "arena" and (truceOver or aliveCount() <= endAtAlive()) then
		return 0
	end
	return AllyService.capFor(headCount(context))
end

local function nameOf(p: Player): string
	return p.DisplayName
end

local function others(g: Group?, except: Player?): { Player }
	local list = {}
	if g then
		for _, m in ipairs(g.members) do
			if m ~= except then
				table.insert(list, m)
			end
		end
	end
	return list
end

local function pushState(p: Player)
	if not isPlayer(p) then
		return
	end
	local g = groupOf[p]
	local allies = {}
	for _, m in ipairs(others(g, p)) do
		table.insert(allies, { userId = m.UserId, name = nameOf(m) })
	end
	local t = os.clock()
	local offersIn, offersOut = {}, {}
	for from, row in pairs(offers) do
		local at = row[p]
		if at and at > t and isPlayer(from) then
			table.insert(offersIn, { userId = from.UserId, name = nameOf(from), left = at - t })
		end
	end
	for to, at in pairs(offers[p] or {}) do
		if at > t and isPlayer(to) then
			table.insert(offersOut, { userId = to.UserId, name = nameOf(to), left = at - t })
		end
	end
	local context = contextOf(p)
	send(p, {
		kind = "state",
		allies = allies,
		size = if g then #g.members else 1,
		cap = capIn(context),
		context = context or "",
		offersIn = offersIn,
		offersOut = offersOut,
		truceOver = truceOver,
	})
	AllyService.changed:Fire(p)
	local voice = service("VoiceService")
	if voice and type(voice.setAllies) == "function" then
		pcall(voice.setAllies, p, AllyService.getAllies(p))
	end
end

local function pushGroup(g: Group?)
	if g then
		for _, m in ipairs(g.members) do
			pushState(m)
		end
	end
end

local function dropOffersOf(p: Player)
	local touched = {}
	for to in pairs(offers[p] or {}) do
		touched[to] = true
	end
	offers[p] = nil
	for from, row in pairs(offers) do
		if row[p] then
			row[p] = nil
			touched[from] = true
		end
	end
	for q in pairs(touched) do
		pushState(q)
	end
end

local function dissolve(g: Group, reason: string, text: string?, tone: string?)
	groups[g.id] = nil
	local members = g.members
	g.members = {}
	for _, m in ipairs(members) do
		if groupOf[m] == g then
			groupOf[m] = nil
		end
		send(m, { kind = "ended", reason = reason, text = text, tone = tone })
		pushState(m)
	end
end

-- Takes p out of their group. The rest are told `othersText` (if any); a group left with one member ends.
local function removeMember(p: Player, reason: string, othersText: string?, selfText: string?)
	local g = groupOf[p]
	if not g then
		return
	end
	groupOf[p] = nil
	local i = table.find(g.members, p)
	if i then
		table.remove(g.members, i)
	end
	if isPlayer(p) then
		send(p, { kind = "ended", reason = reason, text = selfText })
		pushState(p)
	end
	if #g.members <= 1 then
		local last = g.members[1]
		dissolve(g, reason, othersText or (if last then "The truce is over" else nil))
		return
	end
	for _, m in ipairs(g.members) do
		if othersText then
			line(m, othersText)
		end
	end
	pushGroup(g)
end

local function endAll(reason: string, text: string?, tone: string?)
	local list = {}
	for _, g in pairs(groups) do
		table.insert(list, g)
	end
	for _, g in ipairs(list) do
		dissolve(g, reason, text, tone)
	end
	for from in pairs(offers) do
		offers[from] = nil
	end
end

local function brokeBetween(a: Player, b: Player): boolean
	return (broke[a] ~= nil and broke[a][b] == true) or (broke[b] ~= nil and broke[b][a] == true)
end

local function markBroken(a: Player, b: Player)
	broke[a] = broke[a] or {}
	broke[a][b] = true
	broke[b] = broke[b] or {}
	broke[b][a] = true
end

-- Joins a and b (both agreed). Returns true when they are now allies.
local function link(a: Player, b: Player): boolean
	local ga, gb = groupOf[a], groupOf[b]
	if ga and ga == gb then
		return true
	end
	if ga and gb then
		return false
	end
	local g = ga or gb
	local newcomer = if ga then b elseif gb then a else nil
	if not g then
		nextId += 1
		g = { id = nextId, members = { a, b } }
		groups[g.id] = g
		groupOf[a], groupOf[b] = g, g
	else
		table.insert(g.members, newcomer :: Player)
		groupOf[newcomer :: Player] = g
	end
	-- the offers between these two are settled; an offer either made to anyone else stays open
	if offers[a] then
		offers[a][b] = nil
	end
	if offers[b] then
		offers[b][a] = nil
	end
	if newcomer then
		for _, m in ipairs(g.members) do
			if m == newcomer then
				local names = {}
				for _, o in ipairs(others(g, m)) do
					table.insert(names, nameOf(o))
				end
				line(m, "Truce agreed", table.concat(names, " · "))
			else
				line(m, nameOf(newcomer :: Player) .. " joins your truce")
			end
		end
	else
		line(a, "Truce agreed", nameOf(b))
		line(b, "Truce agreed", nameOf(a))
	end
	pushGroup(g)
	return true
end

-- a asks b (an offer, or the answer to b's offer). Every refusal goes to a alone.
local function ask(a: Player, b: Player, mustBeOffered: boolean)
	if a == b or not isPlayer(a) or not isPlayer(b) or S.Enabled == false then
		return
	end
	local ca, cb = contextOf(a), contextOf(b)
	if not ca or ca ~= cb then
		if ca then
			line(a, "No truce with " .. nameOf(b) .. " here")
		end
		return
	end
	if ca == "arena" then
		-- the gesture's reach (with some slack for lag)
		local ra = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
		local rb = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
		if not (ra and rb and ra:IsA("BasePart") and rb:IsA("BasePart"))
			or (ra.Position - rb.Position).Magnitude > (tonumber(S.Reach) or 10) * 2 + 6 then
			return
		end
		if truceOver then
			line(a, "The truce is over", "No truces after the bell")
			return
		end
	end
	if brokeBetween(a, b) then
		line(a, "No truce with " .. nameOf(b), "A truce between you was broken this round")
		return
	end
	local ga, gb = groupOf[a], groupOf[b]
	if ga and ga == gb then
		return
	end
	local cap = capIn(ca)
	if cap < 2 then
		line(a, if ca == "arena" and truceOver then "The truce is over" else "Truces need five or more contenders")
		return
	end
	if ga and gb then
		line(a, "You are both in a truce", "Leave yours first")
		return
	end
	local size = (if ga then #ga.members else 1) + (if gb then #gb.members else 1)
	if size > cap then
		line(a, "That truce would be too big", string.format("At most %d together in this round", cap))
		return
	end
	local t = os.clock()
	local theirs = offers[b] and offers[b][a]
	if theirs and theirs > t then
		link(a, b)
		return
	end
	if mustBeOffered then
		line(a, "That offer has gone")
		pushState(a)
		return
	end
	offers[a] = offers[a] or {}
	if offers[a][b] and offers[a][b] > t then
		return -- already waiting
	end
	offers[a][b] = t + (tonumber(S.OfferTime) or 15)
	send(b, { kind = "offer", userId = a.UserId, name = nameOf(a), left = S.OfferTime })
	pushState(a)
	pushState(b)
end

local function onAsk(p: Player, payload: any)
	if not Net.rateLimit(p, ASK, 4, 6) or type(payload) ~= "table" then
		return
	end
	local op = payload.op
	if op == "leave" then
		local ph = phase()
		if ph == "Countdown" then
			return -- locked at the call
		end
		local g = groupOf[p]
		if g then
			removeMember(p, "left", nameOf(p) .. " left the truce", "You left the truce")
		end
		return
	end
	local id = tonumber(payload.target)
	local target = if id then Players:GetPlayerByUserId(id) else nil
	if not target then
		return
	end
	if op == "offer" then
		ask(p, target, false)
	elseif op == "accept" then
		ask(p, target, true)
	end
end

-- The damage hook: any damage an ally deals an ally (health actually lost) breaks the truce. It never blocks it.
local function onAllyDamage(victim: Player, attacker: Player)
	local g = groupOf[victim]
	if not g or groupOf[attacker] ~= g then
		return
	end
	for _, m in ipairs(g.members) do
		if m ~= attacker then
			markBroken(attacker, m)
		end
	end
	local text = nameOf(attacker) .. " broke the truce"
	removeMember(attacker, "broke", text, "You broke the truce")
end

local function healthOf(p: Player): number
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return if h then h.Health else 0
end

local function wrapDamage()
	local ps = service("PlayerService")
	if wrapped or not ps or type(ps.damage) ~= "function" then
		return
	end
	wrapped = true
	local original = ps.damage
	ps.damage = function(victim: Player, amount: number, info: any, ...)
		local attacker = if type(info) == "table" then info.attacker else nil
		local watch = attacker ~= nil and groupOf[victim] ~= nil and groupOf[victim] == groupOf[attacker]
		local before = if watch then healthOf(victim) else 0
		local result = original(victim, amount, info, ...)
		if watch and (result == true or healthOf(victim) < before) then
			task.defer(onAllyDamage, victim, attacker)
		end
		return result
	end
end

-- Plinths ------------------------------------------------------------------------------------------------------------

local function ringGap(i: number, j: number, spotCount: number): number
	local d = math.abs(i - j) % spotCount
	d = math.min(d, spotCount - d)
	return d * 360 / spotCount
end

--[[
	The plinth hook for RoundService.enterCountdown. `chosen` are the round's contenders in pick order, `slots` the
	plinth indices the round would use (today: the evenly spread ones), `spotCount` the plinths on the ring (they are
	evenly spaced: plinth i at i * 360 / spotCount degrees). Returns { [Player] = one of `slots` } with every group's
	members at least minGapDegrees(their group size) apart and everyone else at random in the rest, or nil when no
	group has two members among `chosen` (keep today's order). Each slot is used once.
]]
function AllyService.assignPlinths(chosen: { Player }, slots: { number }, spotCount: number, rng: Random?): { [Player]: number }?
	local r = rng or Random.new()
	local n = math.min(#chosen, #slots)
	if n < 2 or spotCount < 2 then
		return nil
	end
	local inRound: { [any]: boolean } = {}
	for i = 1, n do
		inRound[chosen[i]] = true
	end
	local sets: { { any } } = {}
	local seen: { [Group]: boolean } = {}
	for i = 1, n do
		local g = groupOf[chosen[i]]
		if g and not seen[g] then
			seen[g] = true
			local members = {}
			for _, m in ipairs(g.members) do
				if inRound[m] then
					table.insert(members, m)
				end
			end
			if #members >= 2 then
				table.insert(sets, members)
			end
		end
	end
	-- (tests can pass groups of their own: AllyService._groupsFor overrides the lookup)
	if AllyService._groupsFor then
		sets = AllyService._groupsFor(chosen, n)
	end
	if #sets == 0 then
		return nil
	end
	table.sort(sets, function(a, b)
		return #a > #b
	end)

	local free: { number } = {}
	for i = 1, n do
		free[i] = slots[i]
	end
	local assigned: { [any]: number } = {}

	local function takeFree(slot: number)
		local k = table.find(free, slot)
		if k then
			table.remove(free, k)
		end
	end

	-- one group: spread round the ring from a random start, each member at the free slot nearest its even share that
	-- keeps the group's gap; a few random starts before the best effort
	local function place(members: { any }): boolean
		local g = #members
		local need = AllyService.minGapDegrees(g) - 1e-6
		for _ = 1, 40 do
			if #free < g then
				return false
			end
			local start = free[r:NextInteger(1, #free)]
			local picks = { start }
			local ok = true
			for j = 1, g - 1 do
				local target = (start + j * spotCount / g) % spotCount
				local best, bestD = nil, math.huge
				for _, s in ipairs(free) do
					if not table.find(picks, s) then
						local fine = true
						for _, q in ipairs(picks) do
							if ringGap(s, q, spotCount) < need then
								fine = false
								break
							end
						end
						if fine then
							local d = ringGap(s, target, spotCount)
							if d < bestD then
								best, bestD = s, d
							end
						end
					end
				end
				if not best then
					ok = false
					break
				end
				table.insert(picks, best)
			end
			if ok then
				-- members in random order on the picked slots
				local order = table.clone(members)
				for i = #order, 2, -1 do
					local k = r:NextInteger(1, i)
					order[i], order[k] = order[k], order[i]
				end
				for i, m in ipairs(order) do
					assigned[m] = picks[i]
					takeFree(picks[i])
				end
				return true
			end
		end
		return false
	end

	local relaxed = false
	for _, members in ipairs(sets) do
		if not place(members) then
			relaxed = true
			for _, m in ipairs(members) do
				if #free > 0 then
					local k = r:NextInteger(1, #free)
					assigned[m] = free[k]
					table.remove(free, k)
				end
			end
		end
	end
	if relaxed then
		warn("[AllyService] could not keep every ally group apart on the plinths; placed the rest at random")
	end
	-- everyone else at random in what is left
	for i = 1, n do
		local p = chosen[i]
		if assigned[p] == nil and #free > 0 then
			local k = r:NextInteger(1, #free)
			assigned[p] = free[k]
			table.remove(free, k)
		end
	end
	return assigned
end

-- For tests: (true, worst ratio of the gap to the group's minimum) over every pair of allies in `assigned`.
function AllyService.checkSpacing(assigned: { [any]: number }, spotCount: number, sets: { { any } }?): (boolean, number)
	local list = sets
	if not list then
		list = {}
		local seen: { [Group]: boolean } = {}
		for p in pairs(assigned) do
			local g = groupOf[p]
			if g and not seen[g] then
				seen[g] = true
				table.insert(list, g.members)
			end
		end
	end
	local worst = math.huge
	for _, members in ipairs(list :: { { any } }) do
		local placed = {}
		for _, m in ipairs(members) do
			if assigned[m] then
				table.insert(placed, m)
			end
		end
		local need = AllyService.minGapDegrees(#placed)
		for i = 1, #placed do
			for j = i + 1, #placed do
				worst = math.min(worst, ringGap(assigned[placed[i]], assigned[placed[j]], spotCount) / need)
			end
		end
	end
	return worst >= 1 - 1e-6, worst
end

-- Round flow ---------------------------------------------------------------------------------------------------------

local function onCall()
	-- the groups lock; whoever was not picked drops out
	for from in pairs(offers) do
		offers[from] = nil
	end
	local list = {}
	for _, g in pairs(groups) do
		table.insert(list, g)
	end
	local started = if fakes then aliveCount() else tonumber(GameState:GetAttribute("StartedCount")) or 0
	local tooFew = (not fakes and GameState:GetAttribute("Practice") == true) or started <= endAtAlive()
	for _, g in ipairs(list) do
		if tooFew then
			dissolve(g, "call", "No truce this round", "soft")
		else
			for _, m in ipairs(table.clone(g.members)) do
				if not isContender(m) then
					removeMember(m, "call", nameOf(m) .. " is not in this round", "Not in this round · your truce is off")
				end
			end
			if groups[g.id] then
				pushGroup(g)
			end
		end
	end
end

local function onRoundOver()
	for _, g in pairs(groups) do
		for _, m in ipairs(g.members) do
			groupOf[m] = nil
			send(m, { kind = "ended", reason = "round" })
		end
	end
	table.clear(groups)
	table.clear(offers)
	table.clear(broke)
	truceOver = false
	for _, p in ipairs(Players:GetPlayers()) do
		pushState(p)
	end
end

local function elapsed(): number
	local round = service("RoundService")
	if round and type(round.getElapsed) == "function" then
		local ok, v = pcall(round.getElapsed)
		if ok and type(v) == "number" then
			return v
		end
	end
	return 0
end

local function checkEnds()
	if phase() ~= "Active" then
		return
	end
	local feast = tonumber(Config.Events and Config.Events.FeastTime)
	local bell = if fakes then GameState:GetAttribute("AllyBellTest") == true
		else GameState:GetAttribute("ArenaEvent") == "Feast" or (feast ~= nil and elapsed() >= feast)
	if not truceOver and bell then
		truceOver = true
		endAll("bell", "The truce is over", "bell")
		return
	end
	if next(groups) ~= nil and aliveCount() <= endAtAlive() then
		endAll("four", "The truce is over", "bell")
	end
end

local lastPhase = "Lobby"
local function onPhase()
	local ph = phase()
	local old = lastPhase
	lastPhase = ph
	if ph == old then
		return
	end
	if ph == "Countdown" then
		onCall()
	elseif ph == "Ending" or (ph == "Lobby" and (old == "Active" or old == "Countdown")) then
		onRoundOver()
	elseif ph == "Active" then
		checkEnds()
	end
	-- the context (and so the cap) changed for everyone
	for _, p in ipairs(Players:GetPlayers()) do
		pushState(p)
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function AllyService.getAllies(p: Player): { Player }
	return others(groupOf[p], p)
end

function AllyService.allied(a: Player, b: Player): boolean
	return a ~= b and groupOf[a] ~= nil and groupOf[a] == groupOf[b]
end

-- Studio tests only: forget that the bell rang (so a test can agree another truce in the same round).
function AllyService._testReset()
	if IS_STUDIO then
		truceOver = false
		table.clear(broke)
	end
end

-- Studio tests only: the rules with stand-in players. AllyService._test.begin() turns stand-ins on; fake(name, id,
-- attrs) makes one (attrs: InArena, Alive; .inbox collects what the client would have been sent); phase(name) sets a
-- stand-in phase (nil: the real one); the rest call the rules' own functions. GameState attributes AllyAliveTest (the
-- alive count) and AllyBellTest (the bell) stand in for the round while stand-ins are on. finish() clears it all.
AllyService._test = {
	begin = function()
		if IS_STUDIO then
			fakes = true
		end
	end,
	finish = function()
		for _, g in pairs(groups) do
			for _, m in ipairs(g.members) do
				groupOf[m] = nil
			end
		end
		table.clear(groups)
		table.clear(offers)
		table.clear(broke)
		truceOver = false
		fakes = false
		fakePhase = nil
	end,
	fake = function(name: string, id: number, attrs: { [string]: any }?): any
		local model = Instance.new("Model")
		local rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Parent = model
		local f = { __fake = true, Name = name, DisplayName = name, UserId = id, Parent = Players, inbox = {}, attrs = attrs or {}, Character = model }
		function f:GetAttribute(k: string)
			return self.attrs[k]
		end
		return f
	end,
	phase = function(name: string?)
		fakePhase = name
	end,
	ask = function(a: any, b: any, accept: boolean?)
		ask(a, b, accept == true)
	end,
	leave = function(p: any)
		if groupOf[p] then
			removeMember(p, "left", nameOf(p) .. " left the truce", "You left the truce")
		end
	end,
	damage = function(victim: any, attacker: any)
		onAllyDamage(victim, attacker)
	end,
	call = function()
		onCall()
	end,
	roundOver = function()
		onRoundOver()
	end,
	checkEnds = function()
		checkEnds()
	end,
	expire = function()
		for _, row in pairs(offers) do
			for to in pairs(row) do
				row[to] = os.clock() - 1
			end
		end
	end,
	wrapped = function(): boolean
		return wrapped
	end,
}

function AllyService.Init(registry)
	Services = registry
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	for _, name in ipairs({ ASK, UPDATE }) do
		if remotes and not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end
end

function AllyService.Start()
	wrapDamage()
	Net.event(ASK).OnServerEvent:Connect(onAsk)
	GameState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	GameState:GetAttributeChangedSignal("ArenaEvent"):Connect(checkEnds)
	GameState:GetAttributeChangedSignal("AliveCount"):Connect(checkEnds)
	lastPhase = phase()
	local ps = service("PlayerService")
	if ps and ps.died then
		ps.died:Connect(function(victim: Player)
			if groupOf[victim] then
				removeMember(victim, "fell", nil, nil)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		task.delay(2, pushState, p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		dropOffersOf(p)
		if groupOf[p] then
			removeMember(p, "left", nil, nil)
		end
		broke[p] = nil
		for _, row in pairs(broke) do
			row[p] = nil
		end
	end)
	-- offers that ran out ("No answer" to the asker), the end rules, and the head count the caps follow
	local lastCount = -1
	while true do
		task.wait(0.5)
		local t = os.clock()
		for from, row in pairs(offers) do
			for to, at in pairs(row) do
				if at <= t then
					row[to] = nil
					if isPlayer(from) then
						line(from, "No answer", if isPlayer(to) then nameOf(to) else nil)
						pushState(from)
					end
					if isPlayer(to) then
						pushState(to)
					end
				end
			end
			if next(row) == nil then
				offers[from] = nil
			end
		end
		checkEnds()
		-- the cap shown in the quiet list follows the head count
		local count = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if contextOf(p) then
				count += 1
			end
		end
		if count ~= lastCount then
			lastCount = count
			for _, p in ipairs(Players:GetPlayers()) do
				pushState(p)
			end
		end
	end
end

return AllyService
