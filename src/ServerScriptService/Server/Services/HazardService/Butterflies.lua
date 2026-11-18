--[[
	HazardService.Butterflies - the blue butterflies (server).

	Roosts: at each round's start, a fresh set of places inside the round's ring where butterflies rest: some of the
	horn's flower beds, gorse and wildflower clumps in the meadow and the wood, and points along the three paths.
	Each is one small invisible anchored part in workspace.Hazards (attributes S = state, K = kind, N = size), which
	clients dress with resting butterflies. A different set every round.

	Waking one: a contender RUNNING (HazardDefs.Butterflies.DisturbSpeed) within DisturbRadius of a resting roost.
	Walking or crouching past never wakes it. The swarm is the roost's own part, moved ten times a second: it lifts,
	then follows its target at ChaseSpeed, slowing as its Stamina runs out. One swarm per contender.

	Inside the swarm (SwarmRadius) a contender is stung: DamagePerSecond in half-second ticks, and the player
	attribute HazardStung is set to the server time (the client staggers and shimmers from it). At or under Floor
	health the stings stop hurting unless the contender has stood in the swarm for StayTime seconds without a break.

	Shaking it off: no clear line from the swarm to the target for LoseSightTime seconds; waist-deep in water for
	WaterTime; beside a lit campfire (SmokeRadius) for SmokeTime; further away than Leash; or simply lasting longer
	than its Stamina. A swarm that loses its target takes another contender only if one is close and in plain sight
	and has no swarm already; otherwise it goes home and the roost sleeps for RestCooldown seconds.

	The called challenge (the Bloom): a circle round where contenders are. During the warning its roosts stir; at the
	start every one of them rises at once, each after a different contender, with more stamina and a longer leash.
	If the circle holds too few roosts, temporary ones are put in the flowers near the contenders.
]]
local Butterflies = {}

local roosts: { { [string]: any } } = {}
local targetOf: { [Player]: { [string]: any } } = {} -- contender -> the swarm on them
local exposure: { [Player]: number } = {} -- seconds stood in a swarm without a break
local stingAt: { [Player]: number } = {}
local plants: { Vector3 }? = nil -- gorse and wildflower clumps, read once
local plantsLoading = false
local nextId = 0
local stats = { woken = 0, stings = 0, shaken = 0, tired = 0 }

local function readPlants()
	if plants or plantsLoading then
		return
	end
	plantsLoading = true
	local list = {}
	local arena = workspace:FindFirstChild("Arena")
	local scatter = arena and arena:FindFirstChild("Scatter")
	if scatter then
		for index, cell in ipairs(scatter:GetChildren()) do
			for _, model in ipairs(cell:GetChildren()) do
				local name = model.Name
				if string.sub(name, 1, 8) == "M1_Gorse" or string.sub(name, 1, 14) == "M1_Wildflowers" then
					if model:IsA("PVInstance") then
						table.insert(list, model:GetPivot().Position)
					end
				end
			end
			if index % 150 == 0 then
				task.wait()
			end
		end
	end
	plants = list
	plantsLoading = false
end

function Butterflies.start(_ctx)
	readPlants()
end

local function setState(roost: { [string]: any }, state: number)
	if roost.state ~= state then
		roost.state = state
		roost.part:SetAttribute("S", state)
	end
end

local function makeRoost(ctx, position: Vector3, kind: string, size: number, temporary: boolean?): { [string]: any }
	local R = ctx.Defs.Roost
	nextId += 1
	local part = Instance.new("Part")
	part.Name = "Roost" .. nextId
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)
	part:SetAttribute("S", R.Rest)
	part:SetAttribute("K", kind)
	part:SetAttribute("N", size)
	part.Parent = ctx.folder
	local roost = {
		id = nextId,
		part = part,
		home = position,
		pos = position,
		kind = kind,
		state = R.Rest,
		quietUntil = 0,
		temporary = temporary == true,
	}
	table.insert(roosts, roost)
	return roost
end

local function clearRoosts()
	for _, roost in ipairs(roosts) do
		if roost.part then
			roost.part:Destroy()
		end
	end
	table.clear(roosts)
	table.clear(targetOf)
	table.clear(exposure)
	table.clear(stingAt)
end

-- A fresh set of roosts for this round.
function Butterflies.roundStart(ctx)
	clearRoosts()
	if not plants then
		readPlants()
	end
	local B = ctx.Defs.Butterflies
	local GameState = ctx.GameState
	local layout = ctx.ArenaLayout
	local rng = Random.new(ctx.roundSeed + 11)
	local ring = tonumber(GameState:GetAttribute("BorderStartRadius")) or tonumber(GameState:GetAttribute("BorderRadius")) or 700
	local centre = layout.Center or Vector3.zero
	local count = math.clamp(math.floor(ring / 100 * B.RoostsPer100Studs + 0.5), B.RoostsMin, B.RoostsMax)
	local chosen: { Vector3 } = {}

	local function free(p: Vector3, spacing: number): boolean
		local dx, dz = p.X - centre.X, p.Z - centre.Z
		if dx * dx + dz * dz > (ring - 30) ^ 2 then
			return false
		end
		for _, q in ipairs(chosen) do
			local ex, ez = p.X - q.X, p.Z - q.Z
			if ex * ex + ez * ez < spacing * spacing then
				return false
			end
		end
		return true
	end
	local function take(list: { Vector3 }, want: number, kind: string, spacing: number, lift: number)
		local tries = 0
		local taken = 0
		while taken < want and tries < want * 40 and #list > 0 do
			tries += 1
			local p = list[rng:NextInteger(1, #list)]
			if free(p, spacing) then
				table.insert(chosen, p)
				makeRoost(ctx, p + Vector3.new(0, lift, 0), kind, rng:NextNumber(0.7, 1))
				taken += 1
			end
		end
	end

	-- the horn's flower beds: a few, well apart
	local beds = {}
	local heart = layout.Heart
	if type(heart) == "table" then
		for _, key in ipairs({ "beds", "teardrops" }) do
			for _, bed in ipairs(heart[key] or {}) do
				if typeof(bed.position) == "Vector3" then
					table.insert(beds, bed.position)
				end
			end
		end
	end
	take(beds, math.min(4, math.floor(count / 4)), "bed", 55, 1.6)
	-- along the paths
	local paths = {}
	for _, trail in ipairs(layout.Trails or {}) do
		for i = 1, #trail - 1 do
			for _, u in ipairs({ 0.25, 0.75 }) do
				local p = trail[i]:Lerp(trail[i + 1], u)
				-- a little off the path, where the gorse grows
				local side = Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14))
				local x, z = p.X + side.X, p.Z + side.Z
				table.insert(paths, Vector3.new(x, ctx.ground(x, z), z))
			end
		end
	end
	take(paths, math.floor(count / 4), "path", B.RoostSpacing, 1.4)
	-- gorse and wildflowers for the rest
	take(plants or {}, count - #chosen, "gorse", B.RoostSpacing, 2.2)
	if ctx.isStudio then
		print(string.format("[HazardService] butterflies: %d roosts inside r %.0f (%d plants known)", #roosts, ring, #(plants or {})))
	end
end

function Butterflies.roundEnd(_ctx)
	clearRoosts()
end

local function release(roost: { [string]: any })
	local target = roost.target
	if target and targetOf[target] == roost then
		targetOf[target] = nil
	end
	roost.target = nil
end

local function sendHome(ctx, roost: { [string]: any }, why: string?)
	local R = ctx.Defs.Roost
	local target = roost.target
	release(roost)
	if roost.state == R.Swarm then
		setState(roost, R.Return)
		if target and why then
			ctx.fx(target, "S", why)
		end
	end
end

-- Every swarm goes home (the Studio "Stop", and a non-butterfly event taking over a zone).
function Butterflies.recall(ctx)
	for _, roost in ipairs(roosts) do
		sendHome(ctx, roost, nil)
	end
end

local function launch(ctx, roost: { [string]: any }, entry: { [string]: any }, now: number, bloom: boolean)
	local B = ctx.Defs.Butterflies
	local R = ctx.Defs.Roost
	roost.target = entry.player
	targetOf[entry.player] = roost
	roost.launchedAt = now
	roost.stamina = if bloom then B.BloomStamina else B.Stamina
	roost.leash = if bloom then B.BloomLeash else B.Leash
	roost.lost, roost.wet, roost.smoke = 0, 0, 0
	roost.sightAt, roost.sight = 0, true
	roost.bloom = bloom
	setState(roost, R.Swarm)
	stats.woken += 1
end

-- The nearest living contender to a point who has no swarm on them and is not inside another event's zone.
local function freeTarget(ctx, position: Vector3, reach: number, needSight: boolean): { [string]: any }?
	local best, bestD = nil, reach
	for _, entry in ipairs(ctx.players) do
		if not targetOf[entry.player] and not ctx.inEventZone(entry.pos) then
			local d = (entry.pos - position).Magnitude
			if d < bestD then
				local seen = true
				if needSight then
					local to = entry.pos - position
					local hit = ctx.ray(position, to)
					seen = hit == nil
				end
				if seen then
					best, bestD = entry, d
				end
			end
		end
	end
	return best
end

function Butterflies.raiseNearest(ctx, entry: { [string]: any }): string
	local R = ctx.Defs.Roost
	local best, bestD = nil, math.huge
	for _, roost in ipairs(roosts) do
		if roost.state == R.Rest or roost.state == R.Stir then
			local d = (roost.pos - entry.pos).Magnitude
			if d < bestD then
				best, bestD = roost, d
			end
		end
	end
	if not best then
		return "no resting roost"
	end
	if targetOf[entry.player] then
		return "that contender has a swarm already"
	end
	launch(ctx, best, entry, ctx.now(), false)
	return string.format("roost %d (%s) %.0f studs away", best.id, best.kind, bestD)
end

local function stepSwarm(ctx, roost: { [string]: any }, dt: number, now: number)
	local B = ctx.Defs.Butterflies
	local entry = roost.target and ctx.byPlayer[roost.target]
	if not entry then
		-- the target fell or left: look for another, else go home
		release(roost)
		local other = freeTarget(ctx, roost.pos, 45, true)
		if other then
			roost.target = other.player
			targetOf[other.player] = roost
			roost.lost, roost.wet, roost.smoke = 0, 0, 0
		else
			sendHome(ctx, roost, nil)
		end
		return
	end
	local age = now - roost.launchedAt
	if age < B.RiseTime then
		-- lifting out of the flowers
		local lift = roost.home + Vector3.new(0, 3.2 * (age / B.RiseTime), 0)
		roost.pos = lift
		roost.part.CFrame = CFrame.new(lift)
		return
	end
	local chase = age - B.RiseTime
	if chase >= roost.stamina then
		stats.tired += 1
		sendHome(ctx, roost, "THE SWARM TIRED")
		return
	end
	local aim = entry.pos + Vector3.new(0, 0.6, 0)
	local to = aim - roost.pos
	local distance = to.Magnitude
	if distance > roost.leash then
		stats.shaken += 1
		sendHome(ctx, roost, "YOU OUTRAN THE SWARM")
		return
	end
	-- sight, water, smoke
	if now >= roost.sightAt then
		roost.sightAt = now + 0.3
		roost.sight = distance < 3 or ctx.ray(roost.pos, to) == nil
	end
	roost.lost = if roost.sight then 0 else roost.lost + dt
	roost.wet = if ctx.inWater(entry) then roost.wet + dt else 0
	roost.smoke = if ctx.nearFire(entry.pos, B.SmokeRadius) then roost.smoke + dt else 0
	local why = nil
	if roost.lost >= B.LoseSightTime then
		why = "THE SWARM LOST SIGHT OF YOU"
	elseif roost.wet >= B.WaterTime then
		why = "THE SWARM WILL NOT FOLLOW YOU INTO WATER"
	elseif roost.smoke >= B.SmokeTime then
		why = "THE SMOKE DROVE THE SWARM OFF"
	elseif ctx.inEventZone(entry.pos) then
		why = ""
	end
	if why then
		stats.shaken += 1
		local shaken = roost.target
		release(roost)
		local other = freeTarget(ctx, roost.pos, 40, true)
		if other and other.player ~= shaken then
			roost.target = other.player
			targetOf[other.player] = roost
			roost.lost, roost.wet, roost.smoke = 0, 0, 0
			if why ~= "" then
				ctx.fx(shaken, "S", why)
			end
		else
			roost.target = shaken -- so the line reaches them
			sendHome(ctx, roost, if why ~= "" then why else nil)
		end
		return
	end
	-- fly: fresh and fast, then tiring
	local u = chase / roost.stamina
	local speed = B.ChaseSpeed + (B.TiredSpeed - B.ChaseSpeed) * u * u
	if distance > 0.5 then
		local stepLength = math.min(distance, speed * dt)
		roost.pos += to.Unit * stepLength
		roost.part.CFrame = CFrame.new(roost.pos)
	end
end

local function stepReturn(ctx, roost: { [string]: any }, dt: number, now: number)
	local B = ctx.Defs.Butterflies
	local R = ctx.Defs.Roost
	local to = roost.home - roost.pos
	local distance = to.Magnitude
	if distance <= 1 then
		roost.pos = roost.home
		roost.part.CFrame = CFrame.new(roost.home)
		roost.quietUntil = now + B.RestCooldown
		if roost.temporary then
			setState(roost, R.Away)
			roost.removeAt = now + 3
		else
			setState(roost, R.Rest)
		end
		return
	end
	roost.pos += to.Unit * math.min(distance, B.ReturnSpeed * dt)
	roost.part.CFrame = CFrame.new(roost.pos)
end

-- Called every tick of a running round, called event or not.
function Butterflies.ambient(ctx, dt: number, now: number)
	local B = ctx.Defs.Butterflies
	local R = ctx.Defs.Roost
	local flying = 0
	for _, roost in ipairs(roosts) do
		if roost.state == R.Swarm then
			flying += 1
		end
	end
	-- running through a roost wakes it
	local awake = ctx.elapsed() >= B.HeartQuietTime
	if awake then
		for _, entry in ipairs(ctx.players) do
			if entry.speed >= B.DisturbSpeed and not targetOf[entry.player] and flying < B.MaxSwarms
				and not ctx.inEventZone(entry.pos) then
				for _, roost in ipairs(roosts) do
					if (roost.state == R.Rest or roost.state == R.Stir) and now >= roost.quietUntil then
						local d = roost.pos - entry.pos
						if d.X * d.X + d.Z * d.Z <= B.DisturbRadius * B.DisturbRadius and math.abs(d.Y) < 14 then
							launch(ctx, roost, entry, now, false)
							flying += 1
							break
						end
					end
				end
			end
		end
	end
	-- fly
	for index = #roosts, 1, -1 do
		local roost = roosts[index]
		if roost.state == R.Swarm then
			stepSwarm(ctx, roost, dt, now)
		elseif roost.state == R.Return then
			stepReturn(ctx, roost, dt, now)
		elseif roost.state == R.Away and roost.removeAt and now >= roost.removeAt then
			roost.part:Destroy()
			table.remove(roosts, index)
		end
	end
	-- sting
	local inside: { [Player]: Vector3 } = {}
	for _, roost in ipairs(roosts) do
		if roost.state == R.Swarm and now - roost.launchedAt >= B.RiseTime then
			for _, entry in ipairs(ctx.players) do
				if not inside[entry.player] and (entry.pos - roost.pos).Magnitude <= B.SwarmRadius and not ctx.inWater(entry) then
					inside[entry.player] = roost.pos
				end
			end
		end
	end
	for _, entry in ipairs(ctx.players) do
		local player = entry.player
		local from = inside[player]
		if from then
			exposure[player] = (exposure[player] or 0) + dt
			if now >= (stingAt[player] or 0) then
				stingAt[player] = now + B.StingInterval
				local health = entry.humanoid.Health
				local perSecond = B.DamagePerSecond
				if health <= B.Floor then
					-- the swarm alone does not finish anyone, unless they stand in it
					perSecond = if exposure[player] >= B.StayTime then B.StayDamagePerSecond else 0
				end
				local amount = perSecond * B.StingInterval
				if amount > 0 and health - amount * ctx.damageScale <= B.Floor and exposure[player] < B.StayTime then
					-- never through the floor in one tick
					amount = math.max(0, (health - B.Floor) / ctx.damageScale - 0.01)
				end
				player:SetAttribute("HazardStung", now)
				stats.stings += 1
				if amount > 0 then
					ctx.damage(entry, amount, B.Cause, from)
				end
			end
		elseif exposure[player] then
			exposure[player] -= dt * 2
			if exposure[player] <= 0 then
				exposure[player] = nil
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- The called challenge: the Bloom
----------------------------------------------------------------------------------------------------
local function inCircle(p: Vector3, event: { [string]: any }): boolean
	local dx, dz = p.X - event.x, p.Z - event.z
	return dx * dx + dz * dz <= event.radius * event.radius
end

function Butterflies.make(ctx, opts: { [string]: any })
	local B = ctx.Defs.Butterflies
	local R = ctx.Defs.Roost
	local x, z = opts.x, opts.z
	if not x then
		-- the contender with the most resting roosts within reach (and then the most company)
		local best, bestScore = nil, -1
		for _, entry in ipairs(ctx.players) do
			local score = 0
			for _, roost in ipairs(roosts) do
				if roost.state == R.Rest and (roost.pos - entry.pos).Magnitude < B.Radius then
					score += 2
				end
			end
			for _, other in ipairs(ctx.players) do
				if other ~= entry and (other.pos - entry.pos).Magnitude < B.Radius then
					score += 1
				end
			end
			score += math.random() * 0.5
			if score > bestScore then
				best, bestScore = entry, score
			end
		end
		if not best then
			return nil, "nobody to call it on"
		end
		x, z = best.pos.X, best.pos.Z
	end
	return { x = x, z = z, radius = B.Radius, duration = B.Duration }
end

function Butterflies.begin(ctx, event: { [string]: any })
	local B = ctx.Defs.Butterflies
	local R = ctx.Defs.Roost
	local rng = Random.new(event.seed)
	-- enough roosts near the contenders in the circle, or the challenge has no teeth
	local inZone = {}
	for _, entry in ipairs(ctx.players) do
		if inCircle(entry.pos, event) then
			table.insert(inZone, entry)
		end
	end
	local near = 0
	for _, roost in ipairs(roosts) do
		if roost.state == R.Rest and inCircle(roost.pos, event) then
			near += 1
		end
	end
	local want = math.min(math.max(#inZone, 2), 6)
	local extra = math.clamp(want - near, 0, B.BloomExtraRoosts)
	for i = 1, extra do
		local anchor = inZone[((i - 1) % math.max(#inZone, 1)) + 1]
		local base = if anchor then anchor.pos else Vector3.new(event.x, 0, event.z)
		local angle = rng:NextNumber(0, math.pi * 2)
		local reach = rng:NextNumber(38, 62)
		local px, pz = base.X + math.cos(angle) * reach, base.Z + math.sin(angle) * reach
		makeRoost(ctx, Vector3.new(px, ctx.ground(px, pz) + 1.6, pz), "bloom", 1, true)
	end
	for _, roost in ipairs(roosts) do
		if roost.state == R.Rest and inCircle(roost.pos, event) then
			roost.quietUntil = 0
			setState(roost, R.Stir)
		end
	end
end

function Butterflies.step(ctx, event: { [string]: any }, phase: string, _dt: number, now: number)
	local B = ctx.Defs.Butterflies
	local R = ctx.Defs.Roost
	if phase ~= "Active" then
		return
	end
	-- every stirring roost in the circle rises, each at a different contender; those with no one in reach wait
	for _, roost in ipairs(roosts) do
		if roost.state == R.Stir and inCircle(roost.pos, event) then
			local target = freeTarget(ctx, roost.pos, B.BloomLeash, false)
			if target then
				launch(ctx, roost, target, now, true)
			end
		end
	end
end

function Butterflies.finish(ctx, _event: { [string]: any })
	local R = ctx.Defs.Roost
	for _, roost in ipairs(roosts) do
		if roost.state == R.Stir then
			setState(roost, R.Rest)
		elseif roost.state == R.Swarm and roost.bloom then
			sendHome(ctx, roost, nil)
		end
		if roost.temporary and roost.state == R.Rest then
			setState(roost, R.Away)
			roost.removeAt = ctx.now() + 2
		end
	end
end

function Butterflies.debug(_ctx)
	local list = {}
	for _, roost in ipairs(roosts) do
		table.insert(list, string.format("%d:%s:%d@%.0f,%.0f,%.0f", roost.id, roost.kind, roost.state, roost.pos.X, roost.pos.Y, roost.pos.Z))
	end
	return { roosts = #roosts, woken = stats.woken, stings = stats.stings, shaken = stats.shaken, tired = stats.tired, list = table.concat(list, " ") }
end

return Butterflies
