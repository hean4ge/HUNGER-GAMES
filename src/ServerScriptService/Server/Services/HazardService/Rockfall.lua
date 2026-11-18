--[[
	HazardService.Rockfall - boulders down a steep slope (server).

	Chutes: once, at start, the coarse height grid (Shared.Map1Regions, 32-stud nodes) is searched inside the field
	line for steep ground with a long way down: a point where the slope is at least MinSlope and the fall line below
	it runs MinLength studs and drops MinDrop before it flattens. About a hundred stretches qualify, nearly all on the
	south mountain, the ridges and above the stream's dip.

	An event takes the chute whose run passes nearest a contender (within reach, and not on top of too many of the
	living). The boulders' paths are pure arithmetic on the height grid and the event's seed (HazardDefs.boulders,
	HazardDefs.boulderAt), so the server hurts and every client draws from the same numbers and nothing is replicated
	per boulder. A rolling boulder that reaches a contender (its radius + HitReach) hits once: Damage by its speed,
	and a shove (HazardFx "H"). Nothing if something solid stands between the rock and the contender (a crag, a
	boulder, a trunk): that is the shelter. When a boulder stops, a real rock is left there as cover until the round
	ends.
]]
local Rockfall = {}

local chutes: { { [string]: any } } = {}
local chutesReady = false
local boulders: { { [string]: any } } = {}
local hitBy: { [number]: { [Player]: boolean } } = {}
local rested: { [number]: boolean } = {}
local rubble: { Instance } = {}
local stats = { chutes = 0, hits = 0, sheltered = 0 }

function Rockfall.start(ctx)
	local R = ctx.Defs.Rockfall
	local h = ctx.Defs.coarseHeight()
	if not h then
		chutesReady = true
		return
	end
	local radius = (ctx.ArenaLayout.PlayRadius or 1800) - 60
	local centre = ctx.ArenaLayout.Center or Vector3.zero
	local lattice = 64
	local done = 0
	for gx = -radius, radius, lattice do
		for gz = -radius, radius, lattice do
			local x, z = centre.X + gx, centre.Z + gz
			if gx * gx + gz * gz <= radius * radius then
				local _, _, slope = ctx.Defs.fallLine(x, z)
				if slope >= R.MinSlope then
					local points, length = ctx.Defs.tracePath(x, z, false)
					local last = points[#points]
					if length >= R.MinLength and points[1].Y - last.Y >= R.MinDrop then
						local dx, dz = last.X - centre.X, last.Z - centre.Z
						if dx * dx + dz * dz <= radius * radius then
							table.insert(chutes, { x = x, z = z, points = points, length = length, drop = points[1].Y - last.Y })
						end
					end
				end
			end
			done += 1
			if done % 400 == 0 then
				task.wait()
			end
		end
	end
	stats.chutes = #chutes
	chutesReady = true
end

-- how near a chute's lower half passes to a point (flat distance)
local function runDistance(chute: { [string]: any }, position: Vector3): number
	local best = math.huge
	local points = chute.points
	for i = math.max(2, math.floor(#points * 0.35)), #points do
		local p = points[i]
		local dx, dz = p.X - position.X, p.Z - position.Z
		local d = dx * dx + dz * dz
		if d < best then
			best = d
		end
	end
	return math.sqrt(best)
end

function Rockfall.make(ctx, opts: { [string]: any })
	local R = ctx.Defs.Rockfall
	if not ctx.Defs.coarseHeight() then
		return nil, "no height grid for this arena"
	end
	local intensity = tonumber(opts.intensity) or 1
	local count = math.floor(R.Boulders[1] + (R.Boulders[2] - R.Boulders[1]) * math.clamp((intensity - 0.6) / 0.4, 0, 1) + 0.5)
	if opts.force and opts.x then
		-- Studio: the slope right above this point, however gentle, so the look can be tested anywhere
		local dx, dz, slope = ctx.Defs.fallLine(opts.x, opts.z)
		if slope < 0.01 then
			dx, dz = 0, -1
		end
		-- prefer a real chute if one runs past
		local at = Vector3.new(opts.x, 0, opts.z)
		local best, bestD = nil, 70
		for _, chute in ipairs(chutes) do
			local d = runDistance(chute, at)
			if d < bestD then
				best, bestD = chute, d
			end
		end
		if best then
			return { x = best.x, z = best.z, radius = R.Radius, duration = R.Duration, a = count, b = R.Spread, intensity = intensity }
		end
		return { x = opts.x - dx * 150, z = opts.z - dz * 150, radius = R.Radius, duration = R.Duration, a = count, b = R.Spread, c = 1,
			intensity = intensity }
	end
	if not chutesReady or #chutes == 0 then
		return nil, "no steep slope found"
	end
	local alive = #ctx.players
	local maxShare = ctx.Defs.Director.MaxShare
	local best, bestScore = nil, math.huge
	for _, chute in ipairs(chutes) do
		local nearest, inside = math.huge, 0
		for _, entry in ipairs(ctx.players) do
			local d = runDistance(chute, entry.pos)
			nearest = math.min(nearest, d)
			if d <= 60 then
				inside += 1
			end
		end
		if nearest <= 55 and (alive < 4 or inside / alive <= maxShare) then
			local score = nearest - chute.drop * 0.05 + math.random() * 10
			if score < bestScore then
				best, bestScore = chute, score
			end
		end
	end
	if not best then
		return nil, "nobody is under a steep slope"
	end
	return { x = best.x, z = best.z, radius = R.Radius, duration = R.Duration, a = count, b = R.Spread, intensity = intensity }
end

function Rockfall.begin(ctx, event: { [string]: any })
	boulders = ctx.Defs.boulders(event)
	table.clear(hitBy)
	table.clear(rested)
	-- the event must last until the last boulder has stopped
	local last = event.startAt
	for _, b in ipairs(boulders) do
		last = math.max(last, b.release + b.duration)
	end
	if last + 1 > event.endAt then
		event.endAt = last + 1
		ctx.GameState:SetAttribute(ctx.Defs.ATTR_EVENT, ctx.Defs.encode(event))
	end
end

local function leaveRock(ctx, b: { [string]: any }, position: Vector3)
	if #rubble >= 40 then
		local old = table.remove(rubble, 1)
		if old then
			old:Destroy()
		end
	end
	local rock = ctx.Look.boulder(b.radius)
	local ground = ctx.ground(position.X, position.Z)
	local cf = CFrame.new(position.X, ground + b.radius * 0.55, position.Z) * CFrame.Angles(b.tilt, b.index * 1.7, b.tilt * 0.6)
	rock:PivotTo(cf)
	for _, part in ipairs(if rock:IsA("BasePart") then { rock } else rock:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = false
		end
	end
	rock.Name = "RockfallRubble"
	rock:SetAttribute("HazardRubble", true)
	rock.Parent = ctx.folder
	table.insert(rubble, rock)
end

function Rockfall.step(ctx, event: { [string]: any }, phase: string, _dt: number, now: number)
	local R = ctx.Defs.Rockfall
	if phase ~= "Active" then
		return
	end
	for _, b in ipairs(boulders) do
		if not rested[b.index] then
			local position, speed, heading, state = ctx.Defs.boulderAt(b, now)
			if position and state == "Roll" then
				-- the coarse grid can sit a few studs off the real ground: test flat distance, and a generous height
				for _, entry in ipairs(ctx.players) do
					local seen = hitBy[b.index]
					if not (seen and seen[entry.player]) then
						local dx, dz = entry.pos.X - position.X, entry.pos.Z - position.Z
						local reach = b.radius + R.HitReach
						if dx * dx + dz * dz <= reach * reach and math.abs(entry.pos.Y - position.Y) < b.radius + 9 and speed > 0.12 then
							if not seen then
								seen = {}
								hitBy[b.index] = seen
							end
							seen[entry.player] = true
							-- shelter: something solid between the rock (a little up the slope, where it came from) and them
							local from = Vector3.new(position.X, entry.pos.Y + 1, position.Z) - heading * (b.radius + 2)
							local to = entry.pos - from
							local hit = ctx.ray(from, to)
							if hit and hit.Instance ~= workspace.Terrain and hit.Distance < to.Magnitude - 1 then
								stats.sheltered += 1
								ctx.fx(entry.player, "S", "THE ROCK TOOK IT FOR YOU")
							else
								stats.hits += 1
								local amount = R.Damage[1] + (R.Damage[2] - R.Damage[1]) * math.clamp(speed, 0, 1)
								ctx.fx(entry.player, "H", heading.X * 26 * speed, heading.Z * 26 * speed, 1)
								ctx.damage(entry, amount, R.Cause, position)
							end
						end
					end
				end
			elseif position and state == "Rest" then
				rested[b.index] = true
				leaveRock(ctx, b, position)
			end
		end
	end
end

function Rockfall.finish(ctx, event: { [string]: any })
	-- any boulder still on its way is put where it would have stopped
	if event and event.startAt and ctx.now() >= event.startAt then
		for _, b in ipairs(boulders) do
			if not rested[b.index] then
				local position = ctx.Defs.boulderAt(b, b.release + b.duration + 1)
				if position and ctx.folder then
					rested[b.index] = true
					leaveRock(ctx, b, position)
				end
			end
		end
	end
	boulders = {}
end

function Rockfall.roundEnd(_ctx)
	for _, rock in ipairs(rubble) do
		rock:Destroy()
	end
	table.clear(rubble)
	boulders = {}
end

function Rockfall.debug(_ctx)
	return { chutes = #chutes, ready = chutesReady, rolling = #boulders, rubble = #rubble, hits = stats.hits, sheltered = stats.sheltered }
end

return Rockfall
