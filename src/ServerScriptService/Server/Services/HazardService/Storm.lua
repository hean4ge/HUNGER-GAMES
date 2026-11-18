--[[
	HazardService.Storm - the mountain storm (server).

	A storm cell (a circle of HazardDefs.Storm.Radius) starts up-wind of the contenders it was called for, on the
	side of the south peak, and drifts across them at Drift studs a second (HazardDefs.stormCentreAt). While it is
	active, every few seconds a bolt is called: the ground is marked for StrikeLead seconds (clients draw a closing
	ring and rising sparks there, HazardFx "L"), then the bolt lands. AimChance of the bolts go for a contender who
	is standing in the open inside the cell (never one who is crouching or under cover, never the same one twice
	running); the rest take the highest of a few random points in the cell.
	A bolt hurts within StrikeRadius: Damage inside StrikeCore, falling to DamageEdge at the edge; half when
	crouching; nothing under a roof or rock. A marked contender who simply runs is out of the radius before it lands
	(1.5 s at a walk is 19 studs).
	The wind is published as GameState.HazardWind for whoever flies arrows through it; clients push their own
	exposed contender with it.
]]
local Storm = {}

local nextStrikeAt = 0
local pending: { { [string]: any } } = {}
local lastAimed: Player? = nil
local rng = Random.new()
local stats = { strikes = 0, aimed = 0, hits = 0 }

function Storm.make(ctx, opts: { [string]: any })
	local S = ctx.Defs.Storm
	local alive = #ctx.players
	local tx, tz = opts.x, opts.z
	if not tx then
		-- the highest-standing contender whose cell does not swallow too many of the living
		local maxShare = ctx.Defs.Director.MaxShare
		local best, bestY = nil, -math.huge
		for _, entry in ipairs(ctx.players) do
			local inside = 0
			for _, other in ipairs(ctx.players) do
				local dx, dz = other.pos.X - entry.pos.X, other.pos.Z - entry.pos.Z
				if dx * dx + dz * dz <= S.Radius * S.Radius then
					inside += 1
				end
			end
			if (alive < 4 or inside / alive <= maxShare) and entry.pos.Y > bestY then
				best, bestY = entry, entry.pos.Y
			end
		end
		if not best then
			return nil, "no high ground with few enough contenders on it"
		end
		tx, tz = best.pos.X, best.pos.Z
	end
	-- it comes off the south peak (bearing 180: +Z), so it travels from there toward the contenders
	local peak = Vector3.new(0, 0, 1550)
	local dir = Vector3.new(tx - peak.X, 0, tz - peak.Z)
	if dir.Magnitude < 1 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	-- swing it a little each time, so it is not the same line twice
	local swing = Random.new(math.floor(os.clock() * 1000)):NextNumber(-0.6, 0.6)
	local c, s = math.cos(swing), math.sin(swing)
	dir = Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
	local lead = if opts.force then 40 else S.LeadDistance
	return {
		x = tx - dir.X * lead,
		z = tz - dir.Z * lead,
		radius = S.Radius,
		duration = S.Duration,
		a = dir.X * S.Drift,
		b = dir.Z * S.Drift,
		intensity = tonumber(opts.intensity) or 1,
	}
end

function Storm.begin(ctx, event: { [string]: any })
	table.clear(pending)
	lastAimed = nil
	rng = Random.new(event.seed)
	nextStrikeAt = event.startAt + 1.5
	local butterflies = ctx.modules and ctx.modules.Butterflies
	if butterflies then
		butterflies.recall(ctx)
	end
end

local function exposedIn(ctx, cx: number, cz: number, radius: number): { { [string]: any } }
	local list = {}
	for _, entry in ipairs(ctx.players) do
		local dx, dz = entry.pos.X - cx, entry.pos.Z - cz
		if dx * dx + dz * dz <= radius * radius and not entry.crouched and entry.player ~= lastAimed and not ctx.covered(entry) then
			table.insert(list, entry)
		end
	end
	return list
end

local function land(ctx, strike: { [string]: any })
	local S = ctx.Defs.Storm
	stats.strikes += 1
	for _, entry in ipairs(ctx.players) do
		local d = (entry.pos - strike.position).Magnitude
		if d <= S.StrikeRadius then
			local amount = S.Damage
			if d > S.StrikeCore then
				local u = (d - S.StrikeCore) / (S.StrikeRadius - S.StrikeCore)
				amount = S.Damage + (S.DamageEdge - S.Damage) * u
			end
			if entry.crouched then
				amount *= S.CrouchScale
			end
			if ctx.covered(entry) then
				amount *= S.CoverScale
			end
			if amount > 0 then
				stats.hits += 1
				local away = entry.pos - strike.position
				away = Vector3.new(away.X, 0, away.Z)
				local push = if away.Magnitude > 0.1 then away.Unit * 14 else Vector3.zero
				ctx.fx(entry.player, "H", push.X, push.Z, amount / S.Damage)
				ctx.damage(entry, amount, S.Cause, strike.position)
			end
		end
	end
end

function Storm.step(ctx, event: { [string]: any }, phase: string, _dt: number, now: number)
	local S = ctx.Defs.Storm
	local GameState = ctx.GameState
	local wind = nil
	if phase == "Active" then
		local dir = Vector3.new(event.a, 0, event.b)
		if dir.Magnitude > 0.01 then
			dir = dir.Unit * S.WindSpeed
		end
		wind = string.format("%.1f,%.1f", dir.X, dir.Z)
	end
	if GameState:GetAttribute(ctx.Defs.ATTR_WIND) ~= wind then
		GameState:SetAttribute(ctx.Defs.ATTR_WIND, wind)
	end
	-- bolts that were marked land when their time comes (also after the last second of the event)
	for index = #pending, 1, -1 do
		local strike = pending[index]
		if now >= strike.at then
			table.remove(pending, index)
			land(ctx, strike)
		end
	end
	if phase ~= "Active" or now < nextStrikeAt or now > event.endAt - S.StrikeLead - 0.5 then
		return
	end
	local gap = rng:NextNumber(S.StrikeEvery[1], S.StrikeEvery[2]) / math.max(event.intensity, 0.4)
	nextStrikeAt = now + gap
	local cx, cz = ctx.Defs.stormCentreAt(event, now)
	local position: Vector3? = nil
	if rng:NextNumber() < S.AimChance then
		local exposed = exposedIn(ctx, cx, cz, event.radius)
		if #exposed > 0 then
			local entry = exposed[rng:NextInteger(1, #exposed)]
			lastAimed = entry.player
			stats.aimed += 1
			position = Vector3.new(entry.pos.X, ctx.ground(entry.pos.X, entry.pos.Z), entry.pos.Z)
		end
	end
	if not position then
		lastAimed = nil
		-- high ground: the highest of a few random points, but never right on a contender
		local bestY = -math.huge
		for _ = 1, 5 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local reach = math.sqrt(rng:NextNumber()) * event.radius * 0.9
			local px, pz = cx + math.cos(angle) * reach, cz + math.sin(angle) * reach
			local py = ctx.ground(px, pz)
			if py > bestY then
				bestY = py
				position = Vector3.new(px, py, pz)
			end
		end
	end
	if position then
		local at = now + S.StrikeLead
		table.insert(pending, { position = position, at = at })
		ctx.fxAll("L", math.floor(position.X * 10) / 10, math.floor(position.Y * 10) / 10, math.floor(position.Z * 10) / 10, at)
	end
end

function Storm.finish(ctx, _event: { [string]: any })
	table.clear(pending)
	if ctx.GameState:GetAttribute(ctx.Defs.ATTR_WIND) ~= nil then
		ctx.GameState:SetAttribute(ctx.Defs.ATTR_WIND, nil)
	end
end

function Storm.debug(_ctx)
	return { strikes = stats.strikes, aimed = stats.aimed, hits = stats.hits, pending = #pending }
end

return Storm
