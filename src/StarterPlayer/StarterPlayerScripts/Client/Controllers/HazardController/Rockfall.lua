--[[
	HazardController.Rockfall - the rockfall on this client.

	  the warning  at the chute's head: dust trickling and pebbles hopping down the fall line (HazardLook.dustEmitter,
	               pebbleEmitter), a low rumble, the hint line for anyone inside the warning circle.
	  the fall     every boulder is drawn from the same arithmetic the server hurts with (HazardDefs.boulders and
	               boulderAt on the event's seed), so nothing is sent per rock. Each is set on the real ground under
	               its path (one ray a boulder a frame) with the path's own bounce, rolls about the axis across its
	               heading at the rate its speed asks, and drags a dust trail. A boulder passing close shakes the
	               camera. When it stops, it fades and the server's rock (workspace.Hazards.RockfallRubble) is there
	               as cover for the rest of the round.
	Sounds: Hazard_Rumble (looped, not in Shared.Sounds yet: silent until added); Hit_Stone (existing) as a boulder
	sets off and where it stops.
]]
local Rockfall = {}

local event: { [string]: any }? = nil
local list: { { [string]: any } } = {}
local head: Part? = nil
local headDust: ParticleEmitter? = nil
local headPebbles: ParticleEmitter? = nil
local rumble: Sound | false | nil = nil
local stats = { boulders = 0, rolling = 0 }
local shookAt = 0

local function dropVisual(b: { [string]: any }, fade: boolean)
	local model = b.model
	if not model then
		return
	end
	b.model, b.part, b.trail = nil, nil, nil
	if fade then
		for _, d in ipairs(if model:IsA("BasePart") then { model } else model:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		task.delay(0.6, function()
			model:Destroy()
		end)
	else
		model:Destroy()
	end
end

local function clear()
	for _, b in ipairs(list) do
		dropVisual(b, false)
	end
	table.clear(list)
	if head then
		local old = head
		head, headDust, headPebbles = nil, nil, nil
		for _, child in ipairs(old:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		task.delay(4, function()
			old:Destroy()
		end)
	end
end

function Rockfall.setEvent(ctx, e: { [string]: any }?)
	clear()
	event = e
	if not e then
		return
	end
	list = ctx.Defs.boulders(e)
	stats.boulders = #list
	-- the chute's head, its top face turned down the fall line
	local dx, dz = ctx.Defs.fallLine(e.x, e.z)
	if dx == 0 and dz == 0 then
		dz = -1
	end
	local up = Vector3.new(dx, 0.5, dz).Unit
	local right = up:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local part = Instance.new("Part")
	part.Name = "RockfallHead"
	part.Transparency = 1
	ctx.Look.still(part)
	part.Size = Vector3.new(ctx.Defs.Rockfall.Spread * 2, 1, 6)
	part.CFrame = CFrame.fromMatrix(Vector3.new(e.x, ctx.ground(e.x, e.z) + 1.5, e.z), right, up)
	headDust = ctx.Look.dustEmitter(part, 4)
	headPebbles = ctx.Look.pebbleEmitter(part)
	part.Parent = ctx.localFolder()
	head = part
end

local function realGround(ctx, x: number, y: number, z: number): number?
	local hit = ctx.ray(Vector3.new(x, y + 40, z), Vector3.new(0, -90, 0))
	return if hit then hit.Position.Y else nil
end

local function build(ctx, b: { [string]: any })
	local model = ctx.Look.boulder(b.radius)
	local part: BasePart? = if model:IsA("BasePart") then model else (model :: Model).PrimaryPart
	if not part then
		model:Destroy()
		return
	end
	b.model, b.part = model, part
	b.rot = CFrame.Angles(b.tilt, b.index * 1.7, b.tilt * 0.6)
	b.last = nil
	if ctx.tier.dust > 0 then
		local trail = ctx.Look.dustEmitter(part, b.radius * 0.8)
		trail.Rate = 0
		b.trail = trail
	end
	model.Parent = ctx.localFolder()
end

local function setRumble(ctx, volume: number, at: Vector3?)
	if rumble == nil and volume > 0.01 then
		rumble = ctx.Sfx.play("Hazard_Rumble", { looped = true, volume = 0, position = at }) or false
	end
	if rumble then
		rumble.Volume = volume
		if volume <= 0.01 and rumble.IsPlaying then
			rumble:Pause()
		elseif volume > 0.01 and not rumble.IsPlaying then
			rumble:Resume()
		end
	end
end

function Rockfall.update(ctx, dt: number, now: number)
	local e = event
	if not e or not ctx.inArena then
		setRumble(ctx, 0, nil)
		for _, b in ipairs(list) do
			dropVisual(b, false)
		end
		return
	end
	local R = ctx.Defs.Rockfall
	local phase = ctx.Defs.phaseAt(e, now)
	local cam = ctx.camera.Position
	local h = ctx.Defs.coarseHeight()
	-- the head's trickle: building over the warning, then quieter once the rocks are coming
	if head and headDust and headPebbles then
		local u = if phase == "Warn" then math.clamp((now - e.warnAt) / math.max(e.startAt - e.warnAt, 1), 0, 1)
			elseif phase == "Active" then 0.3 else 0
		local near = (head.Position - cam).Magnitude < 700
		local dustRate = if near then (2 + 10 * u) * ctx.tier.dust else 0
		local pebbleRate = if near then (1 + 14 * u) * ctx.tier.dust else 0
		if math.abs(headDust.Rate - dustRate) > 0.2 then
			headDust.Rate = dustRate
		end
		if math.abs(headPebbles.Rate - pebbleRate) > 0.2 then
			headPebbles.Rate = pebbleRate
		end
		if dustRate > 0 then
			ctx.emitters += 2
		end
	end
	-- the boulders
	local rolling, nearest = 0, math.huge
	local shake = 0
	for _, b in ipairs(list) do
		local position, speed, heading, state = ctx.Defs.boulderAt(b, now)
		if not position or (position - cam).Magnitude > 900 then
			dropVisual(b, false)
			continue
		end
		if state == "Wait" then
			if b.model then
				dropVisual(b, false)
			end
			continue
		end
		if state == "Rest" then
			if b.model and not b.done then
				b.done = true
				ctx.Sfx.play("Hit_Stone", { position = position, volume = 1.2, pitch = 0.6 })
				dropVisual(b, true)
			end
			continue
		end
		if not b.model then
			if b.done then
				continue
			end
			build(ctx, b)
			if not b.model then
				continue
			end
			ctx.Sfx.play("Hit_Stone", { position = position, volume = 1, pitch = 0.55 })
		end
		rolling += 1
		-- sit it on the real ground with the path's own bounce
		local y = position.Y
		if h then
			local coarse = h(position.X, position.Z)
			local real = realGround(ctx, position.X, coarse, position.Z)
			if real then
				y = real + (position.Y - coarse)
			end
		end
		local p = Vector3.new(position.X, y, position.Z)
		-- roll: about the axis across its heading, by the distance gone
		if b.last then
			local moved = Vector3.new(p.X - b.last.X, 0, p.Z - b.last.Z).Magnitude
			local axis = Vector3.yAxis:Cross(heading)
			if axis.Magnitude > 1e-3 and moved > 0 then
				b.rot = CFrame.fromAxisAngle(axis.Unit, moved / b.radius * b.spin) * b.rot
			end
		end
		b.last = p
		b.model:PivotTo(CFrame.new(p) * b.rot)
		ctx.moving += 1
		if b.trail then
			local rate = 14 * speed * ctx.tier.dust
			if math.abs(b.trail.Rate - rate) > 0.5 then
				b.trail.Rate = rate
			end
			ctx.emitters += 1
		end
		local d = (p - cam).Magnitude
		nearest = math.min(nearest, d)
		if d < 35 then
			shake = math.max(shake, (1 - d / 35) * speed)
		end
	end
	stats.rolling = rolling
	if shake > 0.05 and ctx.alive and os.clock() - shookAt > 0.2 then
		shookAt = os.clock()
		ctx.ClientState.cameraImpulse:Fire(Vector3.zero, shake * 0.35)
	end
	-- the rumble: from the head while it warns, from the nearest rock while they roll
	local fromHead = if head then (head.Position - cam).Magnitude else math.huge
	local loud = if phase == "Warn" then math.clamp(1 - fromHead / 500, 0, 1) * 0.6
		elseif rolling > 0 then math.clamp(1 - nearest / 260, 0, 1) else 0
	setRumble(ctx, loud, if head then head.Position else nil)
	-- the hint, inside the warning circle
	if ctx.alive and phase ~= "Over" then
		local dx, dz = ctx.rootPos.X - e.x, ctx.rootPos.Z - e.z
		if dx * dx + dz * dz <= e.radius * e.radius or nearest < 60 then
			ctx.setHint(R.Hint, 1.4)
		end
	end
end

function Rockfall.debug(_ctx)
	return { on = event ~= nil, boulders = stats.boulders, rolling = stats.rolling }
end

return Rockfall
