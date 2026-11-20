--[[
	HazardController.Butterflies - the blue butterflies on this client.

	The server gives one small invisible part per roost in workspace.Hazards (attribute S = HazardDefs.Roost state).
	This module dresses the ones that have streamed in:

	  resting   within the tier's roostRange: a handful of butterflies perched on whatever is under the roost
	            (flowers, gorse, turf), wings closed over their backs, each opening them slowly now and then; one
	            more circles lazily above. A perched butterfly is moved only while its wings open, so a meadow of
	            roosts costs almost nothing. Stirring (the called challenge's warning): they hover and flutter.
	  a swarm   the cloud's body is particles: square flecks that squash shut and open as they fly and flash from
	            blue to the dark underside (HazardLook.wingEmitter), so a few dozen parts read as hundreds of wings.
	            Through it fly the real ones: two wedge wings each, flapping, every one on its own orbit round a
	            point that trails the swarm's centre at its own pace, so the cloud strings out when it chases and
	            balls up when it catches you. Real butterflies are drawn for the nearest swarms only (the tier's
	            swarmsDrawn); the others are particles alone.
	  stung     the screen's edges shimmer blue (Screen.sting) by how deep in the swarm you are; each sting tick
	            (the LocalPlayer attribute HazardStung) is a stagger: the sprint breaks, a shove against your run and
	            to one side, a small camera kick. A flutter loop rises as a swarm closes (sound key Hazard_Flutter:
	            not in Shared.Sounds yet, so it is silent until the audio owner adds it).

	All wings of all butterflies are moved with one workspace:BulkMoveTo a frame.
]]
local Butterflies = {}

local views: { [Instance]: { [string]: any } } = {}
local pool: { { [string]: any } } = {}
local made = 0
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local moveCount = 0
local candidates: { { [string]: any } } = {}
local rng = Random.new()
local flutter: Sound? = nil
local flutterTried = false
local lastStung = 0
local stats = { roosts = 0, resting = 0, flying = 0, swarms = 0 }

local TAU = math.pi * 2
local EYE_BUBBLE = 2.2 -- no flying butterfly comes nearer the camera than this (studs)

local function acquire(ctx): { [string]: any }
	local b = table.remove(pool)
	if not b then
		made += 1
		local scale = rng:NextNumber(0.8, 1.25)
		local l, r = ctx.Look.butterflyWings(scale, made)
		b = { l = l, r = r, scale = scale }
	end
	local F = ctx.Look.Butterfly
	b.hz = rng:NextNumber(F.FlapHz[1], F.FlapHz[2])
	b.phase = rng:NextNumber(0, TAU)
	local folder = ctx.localFolder()
	b.l.Parent = folder
	b.r.Parent = folder
	return b
end

local function release(b: { [string]: any })
	b.l.Parent = nil
	b.r.Parent = nil
	table.insert(pool, b)
end

local function push(part: BasePart, cf: CFrame)
	moveCount += 1
	moveParts[moveCount] = part
	moveCFrames[moveCount] = cf
end

local function pose(ctx, b: { [string]: any }, body: CFrame, angle: number)
	local Look = ctx.Look
	push(b.l, body * CFrame.Angles(0, 0, -angle) * Look.WingL)
	push(b.r, body * CFrame.Angles(0, 0, angle) * Look.WingR)
end

----------------------------------------------------------------------------------------------------
-- Resting
----------------------------------------------------------------------------------------------------
local function releaseRest(view: { [string]: any })
	if view.rest then
		for _, b in ipairs(view.rest) do
			release(b)
		end
		view.rest = nil
	end
	if view.flit then
		release(view.flit)
		view.flit = nil
	end
end

local function buildRest(ctx, view: { [string]: any })
	local F = ctx.Look.Butterfly
	local home = view.part.Position
	local count = math.max(2, math.floor(ctx.tier.restButterflies * (view.n or 1) + 0.5))
	view.rest = {}
	for i = 1, count do
		local b = acquire(ctx)
		-- perch on whatever is under a point near the roost
		local angle = rng:NextNumber(0, TAU)
		local reach = rng:NextNumber(0.4, 3.6)
		local above = home + Vector3.new(math.cos(angle) * reach, 5, math.sin(angle) * reach)
		local hit = ctx.ray(above, Vector3.new(0, -11, 0))
		local spot = if hit then hit.Position else Vector3.new(above.X, home.Y - 1, above.Z)
		local yaw = rng:NextNumber(0, TAU)
		b.perch = CFrame.new(spot + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rng:NextNumber(-0.25, 0.1), 0, 0)
		b.nextOpen = os.clock() + rng:NextNumber(0.5, F.RestOpenEvery[2])
		b.openUntil = 0
		b.placed = false
		table.insert(view.rest, b)
	end
	if ctx.tierName ~= "Low" then
		local flit = acquire(ctx)
		flit.orbit = rng:NextNumber(1.4, 2.6)
		flit.turn = rng:NextNumber(0.7, 1.3) * (if rng:NextNumber() < 0.5 then -1 else 1)
		view.flit = flit
	end
end

local function animateRest(ctx, view: { [string]: any }, t: number, stir: boolean)
	local F = ctx.Look.Butterfly
	for index, b in ipairs(view.rest) do
		if stir then
			-- up off the flowers, hovering and beating
			local lift = 0.8 + 0.6 * math.sin(t * 1.7 + b.phase) + 0.25 * index
			local sway = Vector3.new(math.sin(t * 2.3 + b.phase) * 0.5, lift, math.cos(t * 1.9 + b.phase * 1.3) * 0.5)
			local beat = 0.5 + 0.5 * math.sin(t * b.hz * TAU + b.phase)
			pose(ctx, b, b.perch + sway, F.FlapDown + (F.FlapUp - F.FlapDown) * beat)
			b.placed = false
		else
			local opening = t < b.openUntil
			if opening then
				-- a slow open and close, twice
				local u = 1 - (b.openUntil - t) / 2.4
				local open = math.sin(u * math.pi) * (0.5 + 0.5 * math.sin(u * TAU * 2 - math.pi / 2))
				pose(ctx, b, b.perch, F.RestAngle - open * 1.15)
				b.placed = false
			elseif not b.placed then
				pose(ctx, b, b.perch, F.RestAngle)
				b.placed = true
			elseif t >= b.nextOpen then
				b.openUntil = t + 2.4
				b.nextOpen = t + 2.4 + rng:NextNumber(F.RestOpenEvery[1], F.RestOpenEvery[2])
			end
		end
	end
	local flit = view.flit
	if flit then
		local home = view.part.Position
		local a = t * flit.turn + flit.phase
		local p = home + Vector3.new(math.cos(a) * flit.orbit, 1.3 + 0.5 * math.sin(t * 1.3 + flit.phase), math.sin(a) * flit.orbit)
		local ahead = Vector3.new(-math.sin(a) * flit.turn, 0.2 * math.cos(t * 1.3 + flit.phase), math.cos(a) * flit.turn)
		local beat = 0.5 + 0.5 * math.sin(t * flit.hz * TAU)
		pose(ctx, flit, CFrame.lookAt(p, p + ahead), F.FlapDown + (F.FlapUp - F.FlapDown) * beat)
	end
end

----------------------------------------------------------------------------------------------------
-- Swarms
----------------------------------------------------------------------------------------------------
local function releaseFlyers(view: { [string]: any })
	if view.flyers then
		for _, b in ipairs(view.flyers) do
			release(b)
		end
		view.flyers = nil
	end
end

local function dropSwarm(view: { [string]: any })
	releaseFlyers(view)
	if view.cloud then
		-- let the particles already in the air finish
		local cloud = view.cloud
		view.cloud = nil
		for _, child in ipairs(cloud:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		task.delay(2.5, function()
			cloud:Destroy()
		end)
	end
	view.centre = nil
end

local function ensureCloud(ctx, view: { [string]: any })
	if view.cloud then
		return
	end
	local radius = ctx.Defs.Butterflies.SwarmRadius
	local cloud = Instance.new("Part")
	cloud.Name = "SwarmCloud"
	cloud.Shape = Enum.PartType.Ball
	cloud.Size = Vector3.new(radius * 1.5, radius * 1.5, radius * 1.5)
	cloud.Transparency = 1
	ctx.Look.still(cloud)
	cloud.CFrame = CFrame.new(view.part.Position)
	view.wings = ctx.Look.wingEmitter(cloud, ctx.tier.wingRate * (view.n or 1))
	view.haze = ctx.Look.hazeEmitter(cloud, (ctx.tier.hazeRate or 4) * (view.n or 1))
	if ctx.tier.shimmer then
		view.shimmer = ctx.Look.shimmerEmitter(cloud, 9)
	end
	cloud.Parent = ctx.localFolder()
	view.cloud = cloud
	view.centre = view.part.Position
	view.bornAt = os.clock()
end

local function ensureFlyers(ctx, view: { [string]: any })
	if view.flyers then
		return
	end
	local radius = ctx.Defs.Butterflies.SwarmRadius
	local count = math.max(4, math.floor(ctx.tier.butterflies * (view.n or 1) + 0.5))
	view.flyers = {}
	for _ = 1, count do
		local b = acquire(ctx)
		-- more of them near the middle than at the edge
		b.orbit = 0.8 + (rng:NextNumber() ^ 1.6) * (radius - 0.8)
		b.turn = rng:NextNumber(1.3, 3.4) * (if rng:NextNumber() < 0.5 then -1 else 1) * (3 / (b.orbit + 1.5))
		b.height = rng:NextNumber(-1.8, 2.4)
		b.bob = rng:NextNumber(0.3, 1.1)
		b.bobHz = rng:NextNumber(0.6, 1.9)
		b.tilt = rng:NextNumber(-0.5, 0.5) -- the orbit's plane leans
		b.rate = rng:NextNumber(1.8, 6) -- how fast its own centre follows the swarm's
		b.follow = view.centre or view.part.Position
		table.insert(view.flyers, b)
	end
end

local function animateFlyers(ctx, view: { [string]: any }, dt: number, t: number, loose: number)
	local F = ctx.Look.Butterfly
	local centre = view.centre
	local grow = math.clamp((t - (view.bornAt or t)) / 1.4, 0.15, 1) * loose
	local eye = ctx.camera.Position
	for _, b in ipairs(view.flyers) do
		b.follow = b.follow:Lerp(centre, math.min(1, dt * b.rate))
		local a = t * b.turn + b.phase
		local r = b.orbit * grow
		local c, s = math.cos(a), math.sin(a)
		local y = b.height * grow + b.bob * math.sin(t * b.bobHz * TAU + b.phase) + s * r * b.tilt
		local p = b.follow + Vector3.new(c * r, y, s * r)
		-- the swarm sits on its target, so orbits pass through the target's own head: a wing a few tenths of a stud
		-- from the eye filled a third of the screen as one flat blue slab (hunt 20 Nov). Kept outside a small bubble
		-- round the camera, they still swirl close past the view.
		local fromEye = p - eye
		local eyeDistance = fromEye.Magnitude
		if eyeDistance < EYE_BUBBLE then
			p = eye + (if eyeDistance > 1e-3 then fromEye / eyeDistance else Vector3.yAxis) * EYE_BUBBLE
		end
		-- heading: along its orbit, pulled toward where the swarm is going
		local ahead = Vector3.new(-s * b.turn, b.bob * math.cos(t * b.bobHz * TAU + b.phase) * 0.6, c * b.turn) + (centre - b.follow) * 0.4
		if ahead.Magnitude < 1e-3 then
			ahead = Vector3.zAxis
		end
		local beat = 0.5 + 0.5 * math.sin(t * b.hz * TAU + b.phase)
		pose(ctx, b, CFrame.lookAt(p, p + ahead), F.FlapDown + (F.FlapUp - F.FlapDown) * beat)
	end
end

----------------------------------------------------------------------------------------------------
-- The roost parts
----------------------------------------------------------------------------------------------------
local function forget(part: Instance)
	local view = views[part]
	if not view then
		return
	end
	views[part] = nil
	releaseRest(view)
	dropSwarm(view)
	if view.connection then
		view.connection:Disconnect()
	end
end

local function adopt(part: Instance)
	-- the folder also holds a rockfall's leftover rocks: only parts with a roost state are roosts
	if views[part] or not part:IsA("BasePart") or part:GetAttribute("S") == nil then
		return
	end
	local view = { part = part, state = part:GetAttribute("S") or 0, n = part:GetAttribute("N") or 1, kind = part:GetAttribute("K") }
	view.connection = part:GetAttributeChangedSignal("S"):Connect(function()
		view.state = part:GetAttribute("S") or 0
	end)
	views[part] = view
end

local function watch(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		adopt(child)
	end
	folder.ChildAdded:Connect(adopt)
	folder.ChildRemoved:Connect(forget)
end

local function stagger(ctx)
	if not ctx.alive then
		return
	end
	local root = ctx.root
	local v = if root then root.AssemblyLinearVelocity else Vector3.zero
	local side = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	if side.Magnitude > 0.05 then
		side = side.Unit
	end
	ctx.stopSprint()
	-- against the run, and a little to one side: a stumble, and you are slower for it
	ctx.shove(Vector3.new(-v.X, 0, -v.Z) * 0.45 + side * 3.5, 0.14)
	ctx.ClientState.cameraImpulse:Fire(Vector3.new(math.rad(rng:NextNumber(-1.6, 1.6)), math.rad(rng:NextNumber(-2, 2)), math.rad(rng:NextNumber(-2.4, 2.4))), 0)
	ctx.Sfx.play("Hazard_Sting")
end

function Butterflies.start(ctx)
	local name = ctx.Defs.FOLDER
	local existing = workspace:FindFirstChild(name)
	if existing then
		watch(existing)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == name and child:IsA("Folder") then
			watch(child)
		end
	end)
	workspace.ChildRemoved:Connect(function(child)
		if child.Name == name then
			for part in pairs(views) do
				forget(part)
			end
		end
	end)
	ctx.player:GetAttributeChangedSignal("HazardStung"):Connect(function()
		local at = ctx.player:GetAttribute("HazardStung")
		if type(at) == "number" and at ~= lastStung then
			lastStung = at
			stagger(ctx)
		end
	end)
end

function Butterflies.tierChanged(_ctx)
	-- rebuild everything at the new counts
	for _, view in pairs(views) do
		releaseRest(view)
		releaseFlyers(view)
		if view.cloud then
			view.cloud:Destroy()
			view.cloud = nil
		end
	end
end

local function setFlutter(ctx, volume: number)
	if volume > 0.01 and not flutter and not flutterTried then
		flutterTried = true
		flutter = ctx.Sfx.play("Hazard_Flutter", { looped = true, volume = 0 })
	end
	if flutter then
		flutter.Volume = volume
		if volume <= 0.01 and flutter.IsPlaying then
			flutter:Pause()
		elseif volume > 0.01 and not flutter.IsPlaying then
			flutter:Resume()
		end
	end
end

function Butterflies.update(ctx, dt: number, _now: number)
	local Roost = ctx.Defs.Roost
	local B = ctx.Defs.Butterflies
	local screen = ctx.modules.Screen
	local t = os.clock()
	local cam = ctx.camera.Position
	moveCount = 0
	table.clear(candidates)
	stats.roosts, stats.resting, stats.flying, stats.swarms = 0, 0, 0, 0
	local sting, nearest = 0, math.huge
	for part, view in pairs(views) do
		if not part:IsDescendantOf(workspace) then
			forget(part)
			continue
		end
		stats.roosts += 1
		local state = view.state
		local position = (part :: BasePart).Position
		local distance = (position - cam).Magnitude
		if not ctx.inArena then
			releaseRest(view)
			dropSwarm(view)
		elseif state == Roost.Swarm or state == Roost.Return then
			releaseRest(view)
			ensureCloud(ctx, view)
			-- the server moves the part ten times a second: glide between its steps
			view.centre = view.centre:Lerp(position, math.min(1, dt * 9))
			view.cloud.CFrame = CFrame.new(view.centre)
			ctx.moving += 1
			ctx.emitters += if view.shimmer then 3 else 2
			stats.swarms += 1
			local rate = ctx.tier.wingRate * (view.n or 1) * (if state == Roost.Return then 0.5 else 1)
			if view.wings.Rate ~= rate then
				view.wings.Rate = rate
			end
			view.distance = distance
			table.insert(candidates, view)
			if state == Roost.Swarm then
				local d = (ctx.rootPos - view.centre).Magnitude
				nearest = math.min(nearest, d)
				sting = math.max(sting, math.clamp(1 - (d - B.SwarmRadius * 0.6) / (B.SwarmRadius * 0.9), 0, 1))
			end
		else
			dropSwarm(view)
			if state ~= Roost.Away and distance <= ctx.tier.roostRange then
				if not view.rest then
					buildRest(ctx, view)
				end
				animateRest(ctx, view, t, state == Roost.Stir)
				stats.resting += #view.rest + (if view.flit then 1 else 0)
			else
				releaseRest(view)
			end
		end
	end
	-- real butterflies in the nearest swarms only
	if #candidates > 1 then
		table.sort(candidates, function(a, b)
			return a.distance < b.distance
		end)
	end
	for index, view in ipairs(candidates) do
		if index <= ctx.tier.swarmsDrawn and view.distance < 240 then
			ensureFlyers(ctx, view)
			animateFlyers(ctx, view, dt, t, if view.state == Roost.Return then 1.5 else 1)
			stats.flying += #view.flyers
		else
			releaseFlyers(view)
		end
	end
	if moveCount > 0 then
		-- trim the reused arrays to this frame's length
		for i = #moveParts, moveCount + 1, -1 do
			moveParts[i] = nil
			moveCFrames[i] = nil
		end
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		ctx.moving += moveCount
	end
	if screen then
		screen.sting = if ctx.alive then sting else 0
	end
	if sting > 0.15 and ctx.alive then
		ctx.setHint(B.Hint, 2)
	end
	setFlutter(ctx, if ctx.inArena then math.clamp(1 - nearest / 45, 0, 1) ^ 1.5 else 0)
end

function Butterflies.debug(_ctx)
	return { roosts = stats.roosts, resting = stats.resting, flying = stats.flying, swarms = stats.swarms, made = made, pooled = #pool }
end

return Butterflies
