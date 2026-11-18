--[[
	HazardService.Director - which challenges a round gets, and when.

	At the start horn it draws a plan from the round's seed: PickMin..PickMax of HazardDefs.Director.Slots (a lone
	practice round always gets PickMin), a moment inside each slot's window, and an order of preference among that
	slot's challenges (shuffled; a challenge is used at most MaxUses times a round). So no two rounds run alike:
	"a few mix ups each time".

	When a slot's moment comes it calls the first of its challenges that can find a place: each challenge chooses its
	own zone from where the living contenders are and how many there are (the lowest for the fog, the highest for the
	storm, the one under a slope for the rockfall, the one among the most roosts for the butterflies), and refuses a
	zone that would hold more than MaxShare of the living. A slot waits up to its window's end (and 40 s beyond for a
	Roll Call or a cooldown to pass), then is dropped.

	Never: in the first minute (QuietStart), after QuietEnd or once the Last Stand has begun, with two contenders
	left (a practice round's lone contender excepted), during a Roll Call, across the Offering, or while another
	event runs. The intensity of a slot scales the zone and the damage ramp of what it calls.
]]
local Director = {}

local plan: { { [string]: any } } = {}
local uses: { [string]: number } = {}
local log: { string } = {}

function Director.plan(ctx)
	local D = ctx.Defs.Director
	local rng = Random.new(ctx.roundSeed + 101)
	table.clear(plan)
	table.clear(uses)
	table.clear(log)
	local indices = {}
	for i = 1, #D.Slots do
		indices[i] = i
	end
	for i = #indices, 2, -1 do
		local j = rng:NextInteger(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	local want = if ctx.practice then D.PickMin else rng:NextInteger(D.PickMin, D.PickMax)
	local picked = {}
	for i = 1, math.min(want, #indices) do
		table.insert(picked, indices[i])
	end
	table.sort(picked)
	for _, index in ipairs(picked) do
		local slot = D.Slots[index]
		local kinds = table.clone(slot.kinds)
		for i = #kinds, 2, -1 do
			local j = rng:NextInteger(1, i)
			kinds[i], kinds[j] = kinds[j], kinds[i]
		end
		table.insert(plan, {
			slot = index,
			at = rng:NextNumber(slot.from, slot.to),
			to = slot.to,
			intensity = slot.intensity,
			kinds = kinds,
			done = false,
		})
	end
	if ctx.isStudio then
		print("[HazardService] plan (seed " .. tostring(ctx.roundSeed) .. "): " .. Director.describe())
	end
end

function Director.describe(): string
	local parts = {}
	for _, item in ipairs(plan) do
		table.insert(parts, string.format("%d:%02d %s%s", math.floor(item.at / 60), math.floor(item.at % 60), table.concat(item.kinds, "/"),
			if item.done then " (" .. tostring(item.result) .. ")" else ""))
	end
	return table.concat(parts, "; ")
end

function Director.step(ctx, service, now: number)
	local D = ctx.Defs.Director
	local elapsed = ctx.elapsed()
	if elapsed < D.QuietStart then
		return
	end
	for _, item in ipairs(plan) do
		if not item.done and elapsed >= item.at then
			if elapsed > item.to + 40 or elapsed >= D.QuietEnd then
				item.done, item.result = true, "dropped: its time passed"
				return
			end
			local quiet, why = ctx.quiet()
			if quiet then
				if why == "the last stand" or why == "the final two" then
					item.done, item.result = true, "dropped: " .. why
				end
				return -- wait
			end
			-- not across the Offering: the event must be over, or not begin, within FeastGuard of it
			local feast = tonumber(ctx.Config.Events and ctx.Config.Events.FeastTime) or -1e9
			local scale = 1
			local rs = ctx.Services and ctx.Services.RoundService
			if rs and type(rs.getTimeScale) == "function" then
				local ok, value = pcall(rs.getTimeScale)
				if ok and type(value) == "number" and value > 0 then
					scale = value
				end
			end
			for _, kind in ipairs(item.kinds) do
				local def = ctx.Defs[kind]
				local span = (def.Warning + def.Duration) * scale -- in round-schedule seconds
				local crossesFeast = elapsed - D.FeastGuard < feast and elapsed + span + D.FeastGuard > feast
				if (uses[kind] or 0) < (D.MaxUses[kind] or 1) and not crossesFeast then
					local event, reason = service.call(kind, { intensity = item.intensity })
					if event then
						uses[kind] = (uses[kind] or 0) + 1
						item.done, item.result = true, kind
						table.insert(log, string.format("%.0f %s", elapsed, kind))
						return
					end
					item.tried = (item.tried or "") .. kind .. ": " .. tostring(reason) .. ". "
				end
			end
			-- nothing could be placed now: try again in a few seconds until the window is over
			item.at = elapsed + 8
			if item.at > item.to + 40 then
				item.done, item.result = true, "dropped: " .. tostring(item.tried or "no challenge fits")
			end
			return
		end
	end
end

return Director
