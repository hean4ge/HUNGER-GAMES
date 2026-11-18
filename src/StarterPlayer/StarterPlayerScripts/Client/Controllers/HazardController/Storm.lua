--[[
	HazardController.Storm - the mountain storm on this client.

	  the cell     a low deck of dark cloud (one box of slow smoke sheets, HazardLook.cloudEmitter) 120 studs over
	               the cell's centre, drifting with it (HazardDefs.stormCentreAt). It gathers during the warning.
	  under it     the picture darkens and cools (Lighting.HazardGrade), rain falls in a box that rides over the
	               camera and leans with the wind, and the wind pushes your contender while you stand in the open
	               (not when crouching or with something over your head).
	  a strike     HazardFx "L": the ground is marked (a closing pale ring and rising static, HazardLook.strikeMark)
	               for StrikeLead seconds, then the bolt: a jagged line of beams from the cloud (HazardLook.bolt), a
	               white flash of the whole picture, dust at the foot, a camera kick near it, and thunder that comes
	               later the farther away it is.
	Sounds (not in Shared.Sounds yet, silent until the audio owner adds them): Hazard_Thunder (one-shot, positional),
	Hazard_Rain (looped), Hazard_StormWind (looped).
]]
local Storm = {}

local CLOUD_HEIGHT = 120
local SOUND_SPEED = 1100 -- studs a second: thunder trails the flash

local event: { [string]: any }? = nil
local cloud: Part? = nil
local cloudEmitter: ParticleEmitter? = nil
local rain: Part? = nil
local rainEmitter: ParticleEmitter? = nil
local loops: { [string]: Sound | false } = {}
local flash = 0
local coverAt = -math.huge
local covered = false
local nextRumbleAt = 0
local live: { Instance } = {}
local stats = { strikes = 0, inside = 0 }
local rng = Random.new()

local function loop(ctx, key: string, volume: number)
	local sound = loops[key]
	if sound == nil and volume > 0.01 then
		sound = ctx.Sfx.play(key, { looped = true, volume = 0 }) or false
		loops[key] = sound
	end
	if sound then
		sound.Volume = volume
		if volume <= 0.01 and sound.IsPlaying then
			sound:Pause()
		elseif volume > 0.01 and not sound.IsPlaying then
			sound:Resume()
		end
	end
end

local function fadeOut(part: Part?, after: number)
	if not part then
		return
	end
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child.Enabled = false
		end
	end
	task.delay(after, function()
		part:Destroy()
	end)
end

local function clear()
	fadeOut(cloud, 13)
	fadeOut(rain, 1)
	cloud, cloudEmitter, rain, rainEmitter = nil, nil, nil, nil
end

function Storm.setEvent(ctx, e: { [string]: any }?)
	clear()
	event = e
	if not e then
		return
	end
	local Look = ctx.Look
	local deck = Instance.new("Part")
	deck.Name = "StormCloud"
	deck.Transparency = 1
	Look.still(deck)
	local side = math.min(e.radius * 2.1, 2000)
	deck.Size = Vector3.new(side, 30, side)
	local x, z = ctx.Defs.stormCentreAt(e, ctx.now())
	deck.CFrame = CFrame.new(x, ctx.ground(x, z) + CLOUD_HEIGHT, z)
	cloudEmitter = Look.cloudEmitter(deck)
	deck.Parent = ctx.localFolder()
	cloud = deck
	local box = Instance.new("Part")
	box.Name = "StormRain"
	box.Transparency = 1
	Look.still(box)
	box.Size = Vector3.new(90, 1, 90)
	box.CFrame = CFrame.new(ctx.camera.Position + Vector3.new(0, 44, 0))
	rainEmitter = Look.rainEmitter(box)
	box.Parent = ctx.localFolder()
	rain = box
	nextRumbleAt = 0
end

local function wind(ctx): Vector3
	local text = ctx.GameState:GetAttribute(ctx.Defs.ATTR_WIND)
	if type(text) ~= "string" then
		return Vector3.zero
	end
	local parts = string.split(text, ",")
	return Vector3.new(tonumber(parts[1]) or 0, 0, tonumber(parts[2]) or 0)
end

-- HazardFx "L": a bolt will land at `position` at server time `strikeAt`.
function Storm.strike(ctx, position: Vector3, strikeAt: number)
	local cam = ctx.camera.Position
	local distance = (position - cam).Magnitude
	if distance > 1600 or not ctx.inArena then
		return
	end
	local Look = ctx.Look
	local S = ctx.Defs.Storm
	local lead = math.max(strikeAt - ctx.now(), 0)
	local holder = Instance.new("Part")
	holder.Name = "StrikeMark"
	holder.Transparency = 1
	Look.still(holder)
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0))
	local mark: { ParticleEmitter } = {}
	if distance < 500 then
		mark = Look.strikeMark(holder, math.max(lead, 0.4))
	end
	holder.Parent = ctx.localFolder()
	table.insert(live, holder)
	stats.strikes += 1
	local seed = math.floor(position.X * 7 + position.Z * 13) % 100000
	task.delay(lead, function()
		for _, emitter in ipairs(mark) do
			emitter.Enabled = false
		end
		local top = position + Vector3.new(rng:NextNumber(-30, 30), CLOUD_HEIGHT + 20, rng:NextNumber(-30, 30))
		local bolt = Look.bolt(top, position, ctx.tier.boltSegments, seed)
		bolt.Parent = ctx.localFolder()
		-- the flash: the whole picture, by how near
		flash = math.max(flash, math.clamp(1.2 - distance / 900, 0.25, 1))
		if distance < 120 and ctx.alive then
			local strength = 1 - distance / 120
			ctx.ClientState.cameraImpulse:Fire(Vector3.new(math.rad(-2.5) * strength, 0, math.rad(rng:NextNumber(-2, 2)) * strength), 0.5 * strength)
		end
		-- dust at the foot
		if distance < 400 then
			local dust = ctx.Look.dustEmitter(holder, 3)
			dust:Emit(math.floor(10 * ctx.tier.dust + 2))
			dust.Enabled = false
		end
		-- a flicker: on, off, on
		task.delay(0.07, function()
			bolt.Parent = nil
			task.delay(0.05, function()
				bolt.Parent = ctx.localFolder()
				task.delay(0.12, function()
					bolt:Destroy()
				end)
			end)
		end)
		task.delay(distance / SOUND_SPEED, function()
			ctx.Sfx.play("Hazard_Thunder", { position = position, volume = math.clamp(1.3 - distance / 1400, 0.3, 1) })
		end)
		task.delay(3.5, function()
			local index = table.find(live, holder)
			if index then
				table.remove(live, index)
			end
			holder:Destroy()
		end)
	end)
	-- a near strike is called out in words as well as the ring
	if distance < S.StrikeRadius + 4 and ctx.alive then
		ctx.readout("LIGHTNING · MOVE", lead + 0.3)
	end
end

function Storm.update(ctx, dt: number, now: number)
	local e = event
	-- the flash decays whatever else happens
	if flash > 0 then
		ctx.addGrade(flash, 0.45, -0.1, -0.2, nil)
		flash = math.max(0, flash - dt * 7)
	end
	if not e or not cloud or not ctx.inArena then
		loop(ctx, "Hazard_Rain", 0)
		loop(ctx, "Hazard_StormWind", 0)
		if rainEmitter and rainEmitter.Enabled then
			rainEmitter.Enabled = false
		end
		return
	end
	local S = ctx.Defs.Storm
	local phase = ctx.Defs.phaseAt(e, now)
	local x, z = ctx.Defs.stormCentreAt(e, now)
	cloud.CFrame = CFrame.new(x, ctx.ground(x, z) + CLOUD_HEIGHT, z)
	ctx.moving += 1
	-- the cloud gathers over the warning and thins as it goes
	local build = if phase == "Warn" then math.clamp((now - e.warnAt) / math.max(e.startAt - e.warnAt, 1), 0.2, 1)
		elseif phase == "Active" then math.clamp((e.endAt - now) / 8, 0, 1) else 0
	local emitter = cloudEmitter :: ParticleEmitter
	local rate = ctx.tier.cloudSheets * 0.9 * build
	if rate > 0.05 then
		if math.abs(emitter.Rate - rate) > 0.1 then
			emitter.Rate = rate
		end
		emitter.Enabled = true
		ctx.emitters += 1
	elseif emitter.Enabled then
		emitter.Enabled = false
	end
	-- under it?
	local cam = ctx.camera.Position
	local dx, dz = cam.X - x, cam.Z - z
	local flat = math.sqrt(dx * dx + dz * dz)
	local inside = math.clamp((e.radius + 30 - flat) / 60, 0, 1)
	local weight = inside * (if phase == "Active" then build else build * 0.5)
	stats.inside = weight
	-- darker and cooler, not night: the first test at -0.13 read as dusk
	ctx.addGrade(weight, -0.07, 0.06, -0.25, Color3.fromRGB(226, 232, 244))
	local w = wind(ctx)
	local raining = phase == "Active" and weight > 0.05
	local rainBox = rain :: Part
	local rainE = rainEmitter :: ParticleEmitter
	if raining then
		-- the rain leans with the wind: the box tilts so its underside faces into the fall
		local fall = Vector3.new(0, -95, 0) + w * 0.9
		local up = -fall.Unit
		local right = up:Cross(Vector3.zAxis)
		if right.Magnitude < 1e-3 then
			right = Vector3.xAxis
		end
		right = right.Unit
		rainBox.CFrame = CFrame.fromMatrix(cam + Vector3.new(0, 44, 0) - w * 0.4, right, up)
		local want = ctx.tier.rainRate * weight
		if math.abs(rainE.Rate - want) > 2 then
			rainE.Rate = want
		end
		rainE.Enabled = true
		ctx.emitters += 1
		ctx.moving += 1
	elseif rainE.Enabled then
		rainE.Enabled = false
	end
	loop(ctx, "Hazard_Rain", if raining then weight * 0.8 else 0)
	loop(ctx, "Hazard_StormWind", weight * 0.7)
	-- distant rumbles while it gathers
	if phase == "Warn" and now >= nextRumbleAt then
		nextRumbleAt = now + rng:NextNumber(4, 7)
		ctx.Sfx.play("Hazard_Thunder", { position = Vector3.new(x, ctx.ground(x, z) + CLOUD_HEIGHT, z), volume = 0.35, pitch = 0.8 })
	end
	-- the wind on your own contender, out in the open
	if phase == "Active" and ctx.alive and inside > 0.5 and ctx.root then
		local t = os.clock()
		if t - coverAt > 0.5 then
			coverAt = t
			covered = ctx.ray(ctx.rootPos + Vector3.new(0, 3, 0), Vector3.new(0, S.CoverHeight, 0)) ~= nil
		end
		local character = ctx.player.Character
		local stance = character and character:GetAttribute("Stance")
		local low = stance == "Crouch" or stance == "Slide"
		if not covered and not low and w.Magnitude > 0.1 then
			-- gusts: the push breathes
			local gust = 0.6 + 0.4 * math.noise(t * 0.7, 3.1)
			ctx.shove(w.Unit * S.WindPush * gust * dt, nil)
		end
	end
	if ctx.alive and (inside > 0.3) and phase ~= "Over" then
		ctx.setHint(S.Hint, 1.5)
	end
end

function Storm.debug(_ctx)
	return { on = event ~= nil, strikes = stats.strikes, inside = stats.inside, live = #live }
end

return Storm
