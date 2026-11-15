--[[
	VoiceRoutingTest - checks Proximity Voice's server rules (ServerScriptService.Server.Services.VoiceService.Routing)
	in Edit mode, with no playtest, no voice and no second player (docs/design/VoiceMode.md, test plan S1).
	Command bar (or execute_luau, Edit):
	  print(require(game.ServerStorage.Dev.VoiceRoutingTest:Clone()).run())
	-> "PASS 4416 checks (VoiceRoutingTest)" or "FAIL n of m" plus the first failures. Run it after installing the drafts
	and after any change to Routing; it must PASS before the test publish.
	What it proves: roles per phase; the living are never on the bench's list; a saved OFF never turns on by itself (a
	slow or failed load stays muted, with no time limit); turning voice off is never rate-limited; and every write order
	Routing.plan produces, from every device state to every target (4 players, 2,176 switches), ends in the target and
	never lets anyone hear the player who isn't allowed to both before and after the switch.
	What it can't prove: what Roblox's voice servers do with the lists (the published safety gate G1-G6 covers that).
]]
local ServerScriptService = game:GetService("ServerScriptService")

local VoiceRoutingTest = {}

local USERS = { 1, 2, 3, 4 }

local function loadRouting(): any
	local module = ServerScriptService:FindFirstChild("Server")
	module = module and module:FindFirstChild("Services")
	module = module and module:FindFirstChild("VoiceService")
	module = module and module:FindFirstChild("Routing")
	assert(module and module:IsA("ModuleScript"), "ServerScriptService.Server.Services.VoiceService.Routing is missing")
	return require(module:Clone()) -- a fresh copy, so an edit made a moment ago counts
end

local function subsets(items: { number }): { { number } }
	local out = {}
	for mask = 0, 2 ^ #items - 1 do
		local set = {}
		for i, id in ipairs(items) do
			if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
				table.insert(set, id)
			end
		end
		table.insert(out, set)
	end
	return out
end

local function keys(set: { [number]: boolean }): string
	local list = {}
	for id in pairs(set) do
		table.insert(list, id)
	end
	table.sort(list)
	return "{" .. table.concat(list, ",") .. "}"
end

local function subsetOf(a: { [number]: boolean }, b: { [number]: boolean }): boolean
	for id in pairs(a) do
		if not b[id] then
			return false
		end
	end
	return true
end

local function intersect(a: { [number]: boolean }, b: { [number]: boolean }): { [number]: boolean }
	local out = {}
	for id in pairs(a) do
		if b[id] then
			out[id] = true
		end
	end
	return out
end

local function describe(state: { [string]: any }): string
	return string.format("%s/%s/{%s}", if state.muted then "muted" else "live", if state.allow then "Allow" else "Deny",
		table.concat(state.list, ","))
end

-- A fake device: applies one planned write the way VoiceService.runSteps does
local function applyStep(state: { [string]: any }, step: { [string]: any }): { [string]: any }
	local nextState = { muted = state.muted, allow = state.allow, list = table.clone(state.list) }
	if step.op == "Muted" then
		nextState.muted = step.value == true
	elseif step.op == "AccessType" then
		nextState.allow = step.value == "Allow"
	elseif step.op == "List" then
		nextState.list = table.clone(step.value)
		table.sort(nextState.list)
	else
		error("unknown op " .. tostring(step.op))
	end
	return nextState
end

function VoiceRoutingTest.run(): string
	local Routing = loadRouting()
	local passed, failed, notes = 0, 0, {}
	local function check(ok: boolean, label: string)
		if ok then
			passed += 1
		else
			failed += 1
			if #notes < 12 then
				table.insert(notes, "  FAIL " .. label)
			end
		end
	end

	-- 1. Roles
	check(Routing.role(false, true) == "Open", "no round: an alive player is Open")
	check(Routing.role(false, false) == "Open", "no round: everyone is Open")
	check(Routing.role(true, true) == "Contender", "round running: alive = Contender")
	check(Routing.role(true, false) == "Bench", "round running: not alive = Bench")
	local roster = {
		{ key = "alive1", id = 11, alive = true },
		{ key = "fallen", id = 12, alive = false },
		{ key = "alive2", id = 13, alive = true },
		{ key = "lateJoiner", id = 14, alive = false },
	}
	local roles, bench = Routing.assign(roster, true)
	check(roles.alive1 == "Contender" and roles.alive2 == "Contender", "assign: the living are contenders")
	check(roles.fallen == "Bench" and roles.lateJoiner == "Bench", "assign: the fallen and late joiners are on the bench")
	check(#bench == 2 and bench[1] == 12 and bench[2] == 14, "assign: the bench list is exactly the bench, sorted")
	for _, id in ipairs(bench) do
		check(id ~= 11 and id ~= 13, "assign: no living contender is on the bench list")
	end
	local openRoles, openBench = Routing.assign(roster, false)
	check(openRoles.fallen == "Open" and #openBench == 0, "assign: no round running: nobody on the bench")

	-- 2. The choice: a saved OFF never turns on by itself
	check(Routing.choice({ loadState = "Loading" }, true) == nil, "choice: still loading = unknown (muted), however long")
	check(Routing.choice({ loadState = "Failed" }, true) == nil, "choice: the load failed = unknown (muted)")
	check(Routing.choice({ loadState = "Loaded", saved = false }, true) == false, "choice: saved OFF stays OFF")
	check(Routing.choice({ loadState = "Loaded", saved = true }, false) == true, "choice: saved ON stays ON")
	check(Routing.choice({ loadState = "Loaded" }, true) == true, "choice: loaded, never chosen = DefaultOn (true)")
	check(Routing.choice({ loadState = "Loaded" }, false) == false, "choice: loaded, never chosen = DefaultOn (false)")
	check(Routing.choice({ loadState = "Failed", explicit = true }, false) == true, "choice: an explicit ON wins")
	check(Routing.choice({ loadState = "Loaded", saved = true, explicit = false }, true) == false, "choice: an explicit OFF wins")

	-- 3. Desired device states
	local bench3 = { 2, 3 }
	local d = Routing.desired("Bench", true, false, {}, bench3, "Proximity")
	check(d.allow == true and not d.muted and #d.list == 2 and d.list[1] == 2 and d.list[2] == 3, "desired: bench = Allow + the bench")
	d.list[1] = 99
	check(bench3[1] == 2, "desired: the bench list is copied, not shared")
	d = Routing.desired("Contender", true, false, {}, bench3, "Proximity")
	check(d.allow == false and #d.list == 0 and not d.muted, "desired: contender = Deny + empty (anyone in range)")
	d = Routing.desired("Contender", true, true, { 4 }, bench3, "Proximity")
	check(d.allow == true and #d.list == 1 and d.list[1] == 4, "desired: whisper = Allow + allies only")
	d = Routing.desired("Contender", true, true, {}, bench3, "Proximity")
	check(d.allow == false, "desired: whisper with no allies = normal voice")
	d = Routing.desired("Open", true, false, {}, bench3, "Proximity")
	check(d.allow == false and #d.list == 0 and not d.muted, "desired: open = Deny + empty")
	check(Routing.desired("Open", nil, false, {}, bench3, "Proximity").muted == true, "desired: unknown choice = muted")
	check(Routing.desired("Open", false, false, {}, bench3, "Proximity").muted == true, "desired: OFF = muted")
	check(Routing.desired("Bench", true, false, {}, bench3, "Off").muted == true, "desired: ServerMode Off = muted")

	-- 4. Requests: turning voice off is never rate-limited or dropped
	check(Routing.exempt("SetVoice", false) == true, "exempt: SetVoice(false)")
	check(Routing.exempt("SetVoice", true) == false, "exempt: not SetVoice(true)")
	check(Routing.exempt("Whisper", true) == false and Routing.exempt("Whisper", false) == false, "exempt: not Whisper")

	-- 5. Every write order, from every device state to every target the rules can produce
	local states = {}
	for _, muted in ipairs({ false, true }) do
		for _, allow in ipairs({ false, true }) do
			for _, list in ipairs(subsets(USERS)) do
				table.insert(states, { muted = muted, allow = allow, list = list })
			end
		end
	end
	local targets = {}
	for _, muted in ipairs({ false, true }) do
		for _, list in ipairs(subsets(USERS)) do
			table.insert(targets, { muted = muted, allow = true, list = list })
		end
		table.insert(targets, { muted = muted, allow = false, list = {} })
	end
	for _, current in ipairs(states) do
		for _, target in ipairs(targets) do
			local steps = Routing.plan(current, target)
			local label = describe(current) .. " -> " .. describe(target)
			local allowed = intersect(Routing.audience(current, USERS), Routing.audience(target, USERS))
			local s = current
			local leaked = nil
			for i, step in ipairs(steps) do
				s = applyStep(s, step)
				if i < #steps and not subsetOf(Routing.audience(s, USERS), allowed) then
					leaked = string.format("step %d of %d lets %s hear", i, #steps, keys(Routing.audience(s, USERS)))
					break
				end
			end
			check(leaked == nil, label .. ": " .. tostring(leaked))
			check(s.muted == target.muted and s.allow == target.allow and Routing.sameList(s.list, target.list),
				label .. ": ends in " .. describe(s))
			if current.muted == target.muted and current.allow == target.allow and Routing.sameList(current.list, target.list) then
				check(#steps == 0, label .. ": no writes when nothing changes")
			end
		end
	end

	local total = passed + failed
	if failed == 0 then
		return string.format("PASS %d checks (VoiceRoutingTest)", total)
	end
	return string.format("FAIL %d of %d checks (VoiceRoutingTest)\n%s", failed, total, table.concat(notes, "\n"))
end

return VoiceRoutingTest
