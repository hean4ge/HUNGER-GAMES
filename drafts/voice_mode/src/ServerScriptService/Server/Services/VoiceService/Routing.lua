--[[
	Routing - Proximity Voice's server rules as pure functions (docs/design/VoiceMode.md). No services, no instances:
	VoiceService feeds it plain tables and runs the writes it plans; ServerStorage.Dev.VoiceRoutingTest checks every rule
	in Edit mode, and voice_mode/_tools/routing_model.py model-checks plan() exhaustively.

	A device state is { muted: boolean, allow: boolean, list: { number } } (list sorted, UserIds):
	  allow = false (AccessType Deny): everyone except the list may hear the device; we only ever use an empty list.
	  allow = true  (AccessType Allow): only the list may hear it.
	  muted = true: nobody hears it.

	  Routing.assign(roster, running) -> (roles, bench)
	      roster = { { key: any, id: number, alive: boolean } }; roles[key] = "Open" | "Contender" | "Bench";
	      bench = the sorted UserIds of every Bench player (the stands: the fallen, late joiners, the lobby)
	  Routing.choice(st, defaultOn) -> boolean?
	      st = { explicit: boolean?, saved: boolean?, loadState: "Loading" | "Loaded" | "Failed" }
	      The player's Proximity voice choice. nil = not known yet: the player stays muted, however long that takes.
	      There is no time limit after which it turns on by itself.
	  Routing.desired(role, on, whisper, allies, bench, serverMode) -> state
	  Routing.plan(current, target) -> { { op: "Muted" | "AccessType" | "List", value: any } }
	      The writes that take a device from current to target. No intermediate state lets anyone hear the player who
	      isn't allowed to both before and after the switch: mute first, unmute last; when narrowing to an allow list,
	      the type goes before the list; when opening up, the list is emptied before the type.
	  Routing.audience(state, everyone) -> { [number]: true }   who could hear a device in that state (tests)
	  Routing.exempt(action, value) -> boolean   requests that are never rate-limited or dropped: SetVoice(false)
	  Routing.sameList(a, b) -> boolean    Routing.sortedIds(list) -> { number }
]]
local Routing = {}

function Routing.sortedIds(list: { any }?): { number }
	local out = {}
	if type(list) == "table" then
		for _, value in ipairs(list) do
			local id = tonumber(value)
			if id then
				table.insert(out, id)
			end
		end
	end
	table.sort(out)
	return out
end

function Routing.sameList(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

function Routing.role(running: boolean, alive: boolean): string
	if not running then
		return "Open"
	end
	return if alive then "Contender" else "Bench"
end

function Routing.assign(roster: { { [string]: any } }, running: boolean): ({ [any]: string }, { number })
	local roles = {}
	local bench = {}
	for _, entry in ipairs(roster) do
		local role = Routing.role(running, entry.alive == true)
		roles[entry.key] = role
		if role == "Bench" then
			table.insert(bench, entry.id) -- listeners: everyone on the bench, with or without a microphone
		end
	end
	table.sort(bench)
	return roles, bench
end

function Routing.choice(st: { [string]: any }, defaultOn: boolean): boolean?
	if st.explicit ~= nil then
		return st.explicit == true -- chosen this session: newer than any saved copy
	end
	if st.loadState == "Loaded" then
		if st.saved ~= nil then
			return st.saved == true
		end
		return defaultOn -- loaded, never chosen
	end
	return nil -- still loading, or the load failed: unknown, so muted until the player chooses
end

function Routing.desired(role: string, on: boolean?, whisper: boolean, allies: { number }, bench: { number },
	serverMode: string): { [string]: any }
	local muted = serverMode == "Off" or on ~= true
	if role == "Bench" then
		return { muted = muted, allow = true, list = table.clone(bench) }
	end
	if role == "Contender" and whisper and #allies > 0 then
		return { muted = muted, allow = true, list = table.clone(allies) }
	end
	return { muted = muted, allow = false, list = {} }
end

function Routing.plan(current: { [string]: any }, target: { [string]: any }): { { [string]: any } }
	local steps = {}
	local tempMuted = false
	if target.muted and not current.muted then
		table.insert(steps, { op = "Muted", value = true })
	end
	if target.allow then
		if not current.allow then
			if #current.list > 0 and not target.muted and not current.muted then
				-- Allow with a deny list that isn't empty would let exactly the excluded players in: mute for the switch
				table.insert(steps, { op = "Muted", value = true })
				tempMuted = true
			end
			table.insert(steps, { op = "AccessType", value = "Allow" })
		end
		if not Routing.sameList(current.list, target.list) then
			table.insert(steps, { op = "List", value = table.clone(target.list) })
		end
	else
		if #current.list > 0 then
			table.insert(steps, { op = "List", value = {} }) -- with Allow: nobody; with Deny: widening to the target anyway
		end
		if current.allow then
			table.insert(steps, { op = "AccessType", value = "Deny" })
		end
	end
	if not target.muted and (current.muted or tempMuted) then
		table.insert(steps, { op = "Muted", value = false })
	end
	return steps
end

function Routing.audience(state: { [string]: any }, everyone: { number }): { [number]: boolean }
	local out = {}
	if state.muted then
		return out
	end
	local listed = {}
	for _, id in ipairs(state.list) do
		listed[id] = true
	end
	for _, id in ipairs(everyone) do
		if (state.allow and listed[id]) or (not state.allow and not listed[id]) then
			out[id] = true
		end
	end
	return out
end

function Routing.exempt(action: any, value: any): boolean
	return action == "SetVoice" and value == false
end

return Routing
