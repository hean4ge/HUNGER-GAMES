--[[
	AllyTest - a Studio multiplayer test of allies (AllyService / AllyController): one server and two clients started
	with StudioTestService, like ServerStorage.Dev.MPTest, and logging in its "[MPT]" format so tools/mp_test/readlog.py
	and shots.ps1 read it. Studio only; nothing here runs in a live game.

	From execute_luau, in Edit mode:
	  return require(game.ServerStorage.Dev.AllyTest:Clone()).start({})
	Arguments: failsafe (default 320 s), lock (QA_Lock label, default "allies").
	Also (no Studio processes): AllyTest.spacing(runs) runs AllyService.assignPlinths over random groups and reports
	the worst gap against 360 / (2 * group size).
]]
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local AllyTest = {}

function AllyTest.start(args: { [string]: any }?): string
	if not RunService:IsStudio() or RunService:IsRunning() then
		return "AllyTest: Edit mode in Studio only"
	end
	local a: { [string]: any } = table.clone(args or {})
	a.suite = "allytest"
	local label = tostring(a.lock or "allies")
	a.lock = nil
	local lock = workspace:GetAttribute("QA_Lock")
	if type(lock) == "string" and string.sub(lock, 1, #label + 1) ~= label .. "|" then
		local t = tonumber(string.match(lock, "|(%d+)$")) or 0
		if os.time() - t < 540 then
			return "AllyTest: Studio is locked by " .. lock
		end
	end
	if not StudioTestService.EditModeActive then
		return "AllyTest: a test is already running"
	end
	local driverSource = script:FindFirstChild("Driver")
	local botSource = script:FindFirstChild("Bot")
	if not (driverSource and botSource) then
		return "AllyTest: Driver or Bot is missing (require a :Clone() of the module)"
	end
	for _, child in ipairs(ServerScriptService:GetChildren()) do
		if child.Name == "ALT_Driver" then
			child:Destroy()
		end
	end
	workspace:SetAttribute("QA_Lock", label .. "|" .. os.time())
	local driver = driverSource:Clone()
	driver.Name = "ALT_Driver"
	local bot = botSource:Clone()
	bot.Name = "ALT_Bot"
	bot.Parent = driver
	driver.Parent = ServerScriptService
	task.spawn(function()
		local ok, result = pcall(function()
			return StudioTestService:ExecuteMultiplayerTestAsync(2, a)
		end)
		print("[MPT][EDIT] allytest finished ok=" .. tostring(ok) .. " result=" .. tostring(result))
		local left = ServerScriptService:FindFirstChild("ALT_Driver")
		if left then
			left:Destroy()
		end
		workspace:SetAttribute("QA_Lock", nil)
	end)
	return string.format("AllyTest started at %d", os.time())
end

-- The plinth rule without any Studio process: random rounds of 5..48 contenders on a ring of 48, groups as large as
-- the cap allows, as many of them as fit. Returns a summary line.
function AllyTest.spacing(runs: number?): string
	local Ally = require(ServerScriptService.Server.Services.AllyService)
	local rng = Random.new(19112026)
	local n = math.floor(tonumber(runs) or 200)
	local worst, fails, groupsPlaced, byCap = math.huge, 0, 0, {}
	for run = 1, n do
		local count = rng:NextInteger(5, 48)
		local spots = 48
		local cap = Ally.capFor(count)
		local chosen = {}
		for i = 1, count do
			chosen[i] = { name = "P" .. i }
		end
		-- the slots the round uses today: evenly spread from a random offset
		local offset = rng:NextInteger(0, spots - 1)
		local slots = {}
		for k = 0, count - 1 do
			slots[k + 1] = ((math.floor(k * spots / count) + offset) % spots) + 1
		end
		-- groups: everyone in a full group when run is even (the worst case), else a random share
		local sets = {}
		local i = 1
		while i + cap - 1 <= count and cap >= 2 do
			local size = if run % 2 == 0 then cap else rng:NextInteger(2, cap)
			if i + size - 1 > count then
				break
			end
			local members = {}
			for j = i, i + size - 1 do
				table.insert(members, chosen[j])
			end
			table.insert(sets, members)
			i += size
			if run % 2 == 1 and rng:NextNumber() < 0.3 then
				i += 1
			end
		end
		Ally._groupsFor = function()
			return sets
		end
		local ok, assigned = pcall(Ally.assignPlinths, chosen, slots, spots, Random.new(run))
		Ally._groupsFor = nil
		if not ok then
			return "assignPlinths error: " .. tostring(assigned)
		end
		if #sets > 0 then
			if not assigned then
				fails += 1
				continue
			end
			-- every slot used once, everyone placed
			local used, placed = {}, 0
			for _, s in pairs(assigned) do
				if used[s] then
					fails += 1
				end
				used[s] = true
				placed += 1
			end
			if placed ~= count then
				fails += 1
			end
			local good, w = Ally.checkSpacing(assigned, spots, sets)
			if not good then
				fails += 1
			end
			worst = math.min(worst, w)
			groupsPlaced += #sets
			byCap[cap] = (byCap[cap] or 0) + 1
		end
	end
	return string.format("spacing: %d rounds, %d groups placed, %d failures, worst gap = %.2f x the minimum (cap 2: %d rounds, 3: %d, 4: %d)",
		n, groupsPlaced, fails, worst, byCap[2] or 0, byCap[3] or 0, byCap[4] or 0)
end

-- The truce rules with stand-in players (AllyService._test), on a Play server (Server data model). Every check is the
-- service's own code; only who the players are, the phase, the head count and the bell are stood in. Returns lines.
function AllyTest.rules(): string
	local Ally = require(ServerScriptService.Server.Services.AllyService)
	local T = Ally._test
	local GS = game:GetService("ReplicatedStorage").GameState
	local out = {}
	local function check(id: string, pass: boolean, detail: string?)
		table.insert(out, string.format("%s %s%s", if pass then "PASS" else "FAIL", id, if detail then " · " .. detail else ""))
	end
	local function said(p: any, needle: string): boolean
		for _, m in ipairs(p.inbox) do
			local text = tostring(m.text or "") .. " " .. tostring(m.sub or "")
			if string.find(text, needle, 1, true) then
				return true
			end
		end
		return false
	end
	local function lines(p: any): string
		local t = {}
		for _, m in ipairs(p.inbox) do
			if m.kind == "line" or (m.kind == "ended" and m.text) or m.kind == "offer" then
				table.insert(t, m.kind .. ":" .. tostring(m.text or m.name) .. (if m.sub then " | " .. m.sub else "") .. (if m.tone then " (" .. m.tone .. ")" else ""))
			end
		end
		return table.concat(t, "; ")
	end
	local function clear(...)
		for _, p in ipairs({ ... }) do
			table.clear(p.inbox)
		end
	end
	local function lastState(p: any): any
		for i = #p.inbox, 1, -1 do
			if p.inbox[i].kind == "state" then
				return p.inbox[i]
			end
		end
		return nil
	end
	local keep = { cap = GS:GetAttribute("AllyCapTest"), alive = GS:GetAttribute("AllyAliveTest"), bell = GS:GetAttribute("AllyBellTest"), endAt = GS:GetAttribute("AllyEndAtTest") }
	local ok, err = pcall(function()
		T.begin()
		GS:SetAttribute("AllyCapTest", nil)
		GS:SetAttribute("AllyEndAtTest", nil)
		GS:SetAttribute("AllyBellTest", false)
		T.phase("Training")
		local F = {}
		for i, n in ipairs({ "Wren", "Ash", "Cole", "Dara", "Esk", "Finn", "Gale", "Hale", "Ivo", "Juno", "Kai" }) do
			F[n] = T.fake(n, -100 - i, {})
		end
		local W, A, C, D, E = F.Wren, F.Ash, F.Cole, F.Dara, F.Esk

		-- 1. few players: no truce
		T.ask(W, A)
		check("cap.fewPlayers", said(W, "Truces need five or more contenders") and not Ally.allied(W, A), lines(W))
		-- 2. both must agree: an offer alone is not a truce; the answer makes it
		GS:SetAttribute("AllyCapTest", 2)
		clear(W, A)
		T.ask(W, A)
		local offered = false
		for _, m in ipairs(A.inbox) do
			offered = offered or (m.kind == "offer" and m.name == "Wren")
		end
		check("agree.offerOnly", offered and not Ally.allied(W, A), "Ash got: " .. lines(A))
		T.ask(A, W, true)
		check("agree.both", Ally.allied(W, A) and said(W, "Truce agreed") and said(A, "Truce agreed"), lines(W) .. " / " .. lines(A))
		local s = lastState(W)
		check("state.private", s ~= nil and #s.allies == 1 and s.allies[1].name == "Ash" and s.cap == 2, "Wren's state allies=" .. tostring(s and #s.allies) .. " cap=" .. tostring(s and s.cap))
		-- 3. the cap: a pair is full at 2
		clear(C)
		T.ask(C, W)
		check("cap.full", said(C, "too big") and not Ally.allied(C, W), lines(C))
		-- 4. at 4: a member and a newcomer agree, the group grows and the rest are told
		GS:SetAttribute("AllyCapTest", 4)
		clear(W, A, C)
		T.ask(C, W)
		T.ask(W, C)
		check("grow.join", Ally.allied(C, A) and said(A, "Cole joins your truce") and said(C, "Truce agreed"), lines(A) .. " / " .. lines(C))
		-- 5. two groups never merge
		T.ask(D, E)
		T.ask(E, D)
		clear(D)
		T.ask(D, W)
		check("groups.noMerge", said(D, "You are both in a truce") and not Ally.allied(D, W), lines(D))
		-- 6. leaving: the one who leaves and the rest see it; two stay allied
		clear(W, A, C)
		T.leave(A)
		check("leave", not Ally.allied(A, W) and Ally.allied(W, C) and said(A, "You left the truce") and said(W, "Ash left the truce"), lines(A) .. " / " .. lines(W))
		-- 7. the call: whoever is not picked drops out; a group left with one ends
		W.attrs.InArena, C.attrs.InArena, D.attrs.InArena, E.attrs.InArena = true, true, false, true
		W.attrs.Alive, C.attrs.Alive, E.attrs.Alive = true, true, true
		GS:SetAttribute("AllyAliveTest", 12)
		T.phase("Countdown")
		clear(D, E)
		T.call()
		check("call.notPicked", not Ally.allied(D, E) and said(D, "Not in this round") and said(E, "Dara is not in this round"), lines(D) .. " / " .. lines(E))
		check("call.keeps", Ally.allied(W, C), "Wren and Cole still allied: " .. tostring(Ally.allied(W, C)))
		-- 8. at the call no changes are taken
		clear(E)
		T.ask(E, W)
		check("call.locked", not Ally.allied(E, W) and #E.inbox == 0, "Esk got: " .. lines(E))
		-- 9. the arena: damage between allies ends it (the attacker leaves, both told); never again this round
		T.phase("Active")
		clear(W, C)
		T.damage(C, W) -- Wren hits Cole
		check("hit.breaks", not Ally.allied(W, C) and said(C, "Wren broke the truce") and said(W, "You broke the truce"), lines(C) .. " / " .. lines(W))
		clear(W)
		T.ask(W, C)
		check("hit.neverAgain", said(W, "A truce between you was broken this round"), lines(W))
		-- 10. a group of three: the attacker leaves, the other two stay allied
		local G, H, I = F.Gale, F.Hale, F.Ivo
		for _, p in ipairs({ G, H, I, F.Juno, F.Kai }) do
			p.attrs.InArena, p.attrs.Alive = true, true
		end
		T.ask(G, H)
		T.ask(H, G)
		T.ask(I, G)
		T.ask(G, I)
		check("arena.gestureGroup", Ally.allied(G, I) and Ally.allied(H, I), "three allied in the arena: " .. tostring(Ally.allied(H, I)))
		clear(G, H, I)
		T.damage(H, I) -- Ivo hits Hale
		check("hit.threeLeaveOne", Ally.allied(G, H) and not Ally.allied(I, G) and said(G, "Ivo broke the truce") and said(H, "Ivo broke the truce") and said(I, "You broke the truce"),
			lines(G) .. " / " .. lines(I))
		-- 11. the Offering's bell ends every truce, with the bell; none after it
		clear(G, H)
		GS:SetAttribute("AllyBellTest", true)
		T.checkEnds()
		local bellTone = false
		for _, m in ipairs(G.inbox) do
			bellTone = bellTone or (m.kind == "ended" and m.reason == "bell" and m.tone == "bell" and m.text == "The truce is over")
		end
		check("bell.ends", not Ally.allied(G, H) and bellTone and said(H, "The truce is over"), lines(G))
		clear(F.Juno)
		T.ask(F.Juno, F.Kai)
		check("bell.noNew", said(F.Juno, "No truces after the bell"), lines(F.Juno))
		-- 12. four left ends it (the bell forgotten for the test)
		Ally._testReset()
		GS:SetAttribute("AllyBellTest", false)
		T.ask(F.Juno, F.Kai)
		T.ask(F.Kai, F.Juno)
		local before = Ally.allied(F.Juno, F.Kai)
		clear(F.Juno, F.Kai)
		GS:SetAttribute("AllyAliveTest", 4)
		T.checkEnds()
		local four = false
		for _, m in ipairs(F.Kai.inbox) do
			four = four or (m.kind == "ended" and m.reason == "four" and m.text == "The truce is over")
		end
		check("four.ends", before and not Ally.allied(F.Juno, F.Kai) and four, lines(F.Kai))
		clear(F.Juno)
		T.ask(F.Juno, F.Kai)
		check("four.noNew", said(F.Juno, "Truces need five or more contenders"), lines(F.Juno))
		-- 13. too few at the call: no truce this round
		GS:SetAttribute("AllyAliveTest", 12)
		T.phase("Training")
		for _, p in ipairs({ F.Juno, F.Kai }) do
			p.attrs.InArena, p.attrs.Alive = false, false
		end
		Ally._testReset()
		T.ask(F.Juno, F.Kai)
		T.ask(F.Kai, F.Juno)
		GS:SetAttribute("AllyAliveTest", 4)
		T.phase("Countdown")
		F.Juno.attrs.InArena, F.Kai.attrs.InArena = true, true
		clear(F.Juno)
		T.call()
		check("call.tooFew", not Ally.allied(F.Juno, F.Kai) and said(F.Juno, "No truce this round"), lines(F.Juno))
		-- 14. the round's end clears everything quietly
		T.phase("Active")
		GS:SetAttribute("AllyAliveTest", 12)
		Ally._testReset()
		F.Juno.attrs.Alive, F.Kai.attrs.Alive = true, true
		T.ask(F.Juno, F.Kai)
		T.ask(F.Kai, F.Juno)
		local wasAllied = Ally.allied(F.Juno, F.Kai)
		T.phase("Ending")
		T.roundOver()
		check("round.clears", wasAllied and not Ally.allied(F.Juno, F.Kai) and #Ally.getAllies(F.Juno) == 0, "allied before the end: " .. tostring(wasAllied))
		check("damage.hookInstalled", T.wrapped(), "PlayerService.damage wrapped by this instance: " .. tostring(T.wrapped()))
	end)
	T.finish()
	GS:SetAttribute("AllyCapTest", keep.cap)
	GS:SetAttribute("AllyAliveTest", keep.alive)
	GS:SetAttribute("AllyBellTest", keep.bell)
	GS:SetAttribute("AllyEndAtTest", keep.endAt)
	if not ok then
		table.insert(out, "ERROR " .. tostring(err))
	end
	return table.concat(out, "\n")
end

return AllyTest
