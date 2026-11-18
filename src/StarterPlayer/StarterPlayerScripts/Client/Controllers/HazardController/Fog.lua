--[[
	HazardController.Fog - the cold fog on this client.

	  from above   the fog's flat top: one box of slow, wide smoke sheets lying at the top's height over the circle
	               (HazardLook.fogSheetEmitter). During the warning the same box lies a few studs over the ground: a
	               thin mist creeping between the trunks. Its height follows HazardDefs.fogTopAt, the curve the
	               server hurts with.
	  inside it    three rings of pale camera-facing veils (Beams) with a roof round the camera (HazardLook.fogShell,
	               moved with one BulkMoveTo) hide the world by distance: near
	               things are soft, past 70 studs there is only white. They fade in over the last 3 studs as your head
	               goes under the top, so stepping up a slope lifts you out of it visibly. The picture cools and
	               loses colour through Lighting.HazardGrade.
	  the cold     the LocalPlayer attribute HazardChill (0..1, server) frosts the screen's edges (Screen.frost) and
	               the hint line says how to get out.
	Sound: Hazard_ColdWind (looped), not in Shared.Sounds yet, so silent until the audio owner adds it.
]]
local Fog = {}

local event: { [string]: any }? = nil
local sheet: Part? = nil
local sheetEmitter: ParticleEmitter? = nil
local shells: { { part: Part, beams: { Beam }, alpha: number, shown: number } } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local shellsOn = false
local lastTop = math.huge
local wind: Sound? = nil
local windTried = false
local stats = { top = 0, inside = 0 }

-- set a shell's thickness, only when it has moved enough to see (a new NumberSequence per change)
local function showShell(ctx, shell, transparency: number)
	if math.abs(shell.shown - transparency) > 0.015 or (transparency >= 1 and shell.shown < 1) then
		shell.shown = transparency
		ctx.Look.setFogShell(shell.beams, transparency)
	end
end

local function clearShells()
	for _, shell in ipairs(shells) do
		shell.part:Destroy()
	end
	table.clear(shells)
	shellsOn = false
end

local function buildShells(ctx)
	clearShells()
	local Look = ctx.Look
	local count = math.clamp(ctx.tier.fogShells, 1, #Look.FogShells)
	-- the phone tier keeps the outer shells (they hide the most for the cost)
	local sides = Look.FogShellSides[ctx.tierName] or 6
	for i = #Look.FogShells - count + 1, #Look.FogShells do
		local recipe = Look.FogShells[i]
		local part, beams = Look.fogShell(recipe.radius, sides)
		part.Parent = ctx.localFolder()
		table.insert(shells, { part = part, beams = beams, alpha = recipe.alpha, shown = 1 })
	end
	table.clear(moveParts)
	table.clear(moveCFrames)
	for i, shell in ipairs(shells) do
		moveParts[i] = shell.part
		moveCFrames[i] = CFrame.identity
	end
end

local function clear()
	if sheet then
		local old = sheet
		sheet, sheetEmitter = nil, nil
		local emitter = old:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			emitter.Enabled = false
		end
		-- the sheets already in the air drift away on their own
		task.delay(10, function()
			old:Destroy()
		end)
	end
	clearShells()
	lastTop = math.huge
end

function Fog.setEvent(ctx, e: { [string]: any }?)
	clear()
	event = e
	if not e then
		return
	end
	local part = Instance.new("Part")
	part.Name = "FogSheet"
	part.Transparency = 1
	ctx.Look.still(part)
	local side = math.min(e.radius * 2, 2000)
	part.Size = Vector3.new(side, 1, side)
	part.CFrame = CFrame.new(e.x, e.a, e.z)
	sheetEmitter = ctx.Look.fogSheetEmitter(part)
	part.Parent = ctx.localFolder()
	sheet = part
	buildShells(ctx)
end

function Fog.tierChanged(ctx)
	if event then
		buildShells(ctx)
	end
end

local function setWind(ctx, volume: number)
	if volume > 0.01 and not wind and not windTried then
		windTried = true
		wind = ctx.Sfx.play("Hazard_ColdWind", { looped = true, volume = 0 })
	end
	if wind then
		wind.Volume = volume * 0.6
		if volume <= 0.01 and wind.IsPlaying then
			wind:Pause()
		elseif volume > 0.01 and not wind.IsPlaying then
			wind:Resume()
		end
	end
end

function Fog.update(ctx, _dt: number, now: number)
	local screen = ctx.modules.Screen
	local chill = tonumber(ctx.player:GetAttribute("HazardChill")) or 0
	if screen then
		screen.frost = if ctx.alive then chill else 0
	end
	local e = event
	if not e or not sheet or not ctx.inArena then
		if shellsOn then
			for _, shell in ipairs(shells) do
				showShell(ctx, shell, 1)
			end
			shellsOn = false
		end
		if sheetEmitter and sheetEmitter.Enabled then
			sheetEmitter.Enabled = false
		end
		setWind(ctx, 0)
		if chill > 0.2 and ctx.alive then
			ctx.setHint(ctx.Defs.Fog.Hint, 1)
		end
		return
	end
	local F = ctx.Defs.Fog
	local top = ctx.Defs.fogTopAt(e, now)
	stats.top = top
	-- the sheet lies just under the top (its particles rise a little)
	if math.abs(top - lastTop) > 0.15 then
		lastTop = top
		sheet.CFrame = CFrame.new(e.x, top - 1.5, e.z)
	end
	local phase = ctx.Defs.phaseAt(e, now)
	local emitter = sheetEmitter :: ParticleEmitter
	if phase == "Over" or top <= e.a - 1.5 then
		if emitter.Enabled then
			emitter.Enabled = false
		end
	else
		-- enough sheets to lie edge to edge over the circle at the tier's density; fewer in the warning's mist
		local area = math.pi * e.radius * e.radius
		local each = 30 * 30
		local life = 8.5
		local rate = area / each / life * ctx.tier.fogRate * (if phase == "Warn" then 0.45 else 1)
		rate = math.min(rate, ctx.tier.fogSheets)
		if math.abs(emitter.Rate - rate) > 0.1 then
			emitter.Rate = rate
		end
		if not emitter.Enabled then
			emitter.Enabled = true
		end
		ctx.emitters += 1
	end
	-- inside it?
	local cam = ctx.camera.Position
	local dx, dz = cam.X - e.x, cam.Z - e.z
	local flat = math.sqrt(dx * dx + dz * dz)
	local edge = math.clamp((e.radius - flat) / 25, 0, 1) -- the circle's rim is soft
	local depth = top - cam.Y
	local under = math.clamp((depth + 0.5) / 3, 0, 1) * edge
	stats.inside = under
	if under > 0.01 then
		local at = CFrame.new(cam)
		for i, shell in ipairs(shells) do
			moveCFrames[i] = at
			showShell(ctx, shell, 1 - shell.alpha * under)
		end
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		shellsOn = true
		ctx.moving += #shells
		ctx.addGrade(under, 0.06, -0.18, -0.4, Color3.fromRGB(226, 236, 246))
	elseif shellsOn then
		for _, shell in ipairs(shells) do
			showShell(ctx, shell, 1)
		end
		shellsOn = false
	end
	-- near the fog, and in it: the cold wind
	local nearTop = math.clamp(1 - math.abs(depth) / 30, 0, 1) * math.clamp((e.radius + 40 - flat) / 40, 0, 1)
	setWind(ctx, math.max(under, nearTop * 0.4) * (if phase == "Active" then 1 else 0.3))
	-- the hint: in the fog, or near it when it is coming
	if ctx.alive then
		if under > 0.3 or chill > 0.2 then
			ctx.setHint(F.Hint, 1 + chill)
		elseif phase == "Warn" and flat < e.radius then
			ctx.setHint(F.Hint, 0.5)
		end
	end
end

function Fog.debug(_ctx)
	return { on = event ~= nil, top = stats.top, inside = stats.inside, shells = #shells }
end

return Fog
