--[[
	HazardController - the arena's challenges on this client: everything you see, hear and feel of them.
	HazardService (server) decides everything; this only draws it. Numbers: Shared.HazardDefs. Looks: Shared.HazardLook.

	  Butterflies (child)  resting butterflies on the roosts near you; a swarm as a few dozen real two-winged
	                       butterflies in a cloud of particle wings; the blue shimmer and the stagger when stung
	  Fog                  the fog's top seen from above, the fog you stand in, the frost of the cold
	  Storm                the cloud deck, the dark, rain, wind on your contender, marked strikes and bolts
	  Rockfall             the warning dust, the boulders (drawn from the same arithmetic the server hurts with)
	  Screen               a self-contained ScreenGui: the blue edge shimmer, the frost, and one plain white line
	                       of text for hints (to be restyled by the UI owners)

	What it reads: GameState.HazardEvent, the parts in workspace.Hazards, the HazardFx remote, and the LocalPlayer
	attributes HazardStung, HazardChill and DetailTier (DetailController's tier decides every count here).
	Lighting: it never writes the day cycle's own objects. It owns one ColorCorrectionEffect, Lighting.HazardGrade,
	which stacks on the cycle's ArenaGrade; the modules add to it through HazardController.grade.
	Other controllers it touches, each through its public API only: MovementController.addImpulse / stopSprint,
	ClientState.cameraImpulse, Shared.Sfx.

	The cost of all of it is published every second as the LocalPlayer attribute HazardCost
	("avg ms / worst ms per frame; moving parts; emitters on"), so the phone tier can be measured in play.
	HazardController.debug() -> table.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("HazardDefs"))
local Look = require(Shared:WaitForChild("HazardLook"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer

local HazardController = {}

local Controllers: any = nil
local modules: { [string]: any } = {}
local order = { "Screen", "Butterflies", "Fog", "Storm", "Rockfall" }

-- what every child module works through
local ctx = {
	Defs = Defs,
	Look = Look,
	Sfx = Sfx,
	ArenaLayout = ArenaLayout,
	ClientState = ClientState,
	GameState = GameState,
	player = player,
	tier = Look.Tiers.High,
	tierName = "High",
	event = nil :: { [string]: any }?,
	folder = nil :: Folder?, -- client-only parts live here
	camera = CFrame.identity,
	root = nil :: BasePart?,
	rootPos = Vector3.zero,
	inArena = false,
	moving = 0, -- parts moved this frame (cost)
	emitters = 0, -- emitters switched on (cost)
	grade = { brightness = 0, contrast = 0, saturation = 0, tint = Color3.new(1, 1, 1) },
	hint = nil :: string?,
	hintWeight = 0,
}
HazardController.ctx = ctx

local grade: ColorCorrectionEffect? = nil
local gradeOn = false
local cost = { sum = 0, worst = 0, frames = 0, at = 0, text = "" }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local rayFilterAt = -math.huge

function ctx.now(): number
	return workspace:GetServerTimeNow()
end

function ctx.localFolder(): Folder
	local folder = ctx.folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "HazardFxLocal"
	made.Parent = workspace
	ctx.folder = made
	return made
end

-- a ray that sees the world and not the characters or these effects
function ctx.ray(from: Vector3, direction: Vector3): RaycastResult?
	local t = os.clock()
	if t - rayFilterAt > 1 then
		rayFilterAt = t
		local ignore: { Instance } = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other.Character then
				table.insert(ignore, other.Character)
			end
		end
		if ctx.folder then
			table.insert(ignore, ctx.folder)
		end
		local hazards = workspace:FindFirstChild(Defs.FOLDER)
		if hazards then
			table.insert(ignore, hazards)
		end
		rayParams.FilterDescendantsInstances = ignore
	end
	return workspace:Raycast(from, direction, rayParams)
end

-- the ground under a point: the real terrain where it has streamed in, else the coarse grid
function ctx.ground(x: number, z: number): number
	return ArenaLayout.heightAt(x, z) or ArenaLayout.BaseHeight or 0
end

function ctx.shove(v: Vector3, shake: number?)
	local movement = Controllers and Controllers.MovementController
	if movement and type(movement.addImpulse) == "function" then
		movement.addImpulse(v)
	end
	if shake and shake > 0 then
		ClientState.cameraImpulse:Fire(Vector3.new(0.02, 0, 0), shake)
	end
end

function ctx.stopSprint()
	local movement = Controllers and Controllers.MovementController
	if movement and type(movement.stopSprint) == "function" then
		movement.stopSprint()
	end
end

-- Add to this frame's grade. weight 0..1.
function ctx.addGrade(weight: number, brightness: number, contrast: number, saturation: number, tint: Color3?)
	if weight <= 0.001 then
		return
	end
	local g = ctx.grade
	g.brightness += brightness * weight
	g.contrast += contrast * weight
	g.saturation += saturation * weight
	if tint then
		g.tint = g.tint:Lerp(Color3.new(g.tint.R * tint.R, g.tint.G * tint.G, g.tint.B * tint.B), weight)
	end
end

-- Ask for the hint line. The heaviest request of the frame wins.
function ctx.setHint(text: string, weight: number)
	if weight > ctx.hintWeight then
		ctx.hint, ctx.hintWeight = text, weight
	end
end

function ctx.readout(text: string, seconds: number?)
	local screen = modules.Screen
	if screen then
		screen.say(text, seconds or 3)
	end
end

local function applyGrade()
	local g = ctx.grade
	local on = math.abs(g.brightness) > 0.002 or math.abs(g.contrast) > 0.002 or math.abs(g.saturation) > 0.002
		or g.tint.R < 0.995 or g.tint.G < 0.995 or g.tint.B < 0.995
	if not on then
		if gradeOn and grade then
			grade.Enabled = false
			gradeOn = false
		end
		return
	end
	if not grade or grade.Parent ~= Lighting then
		local found = Lighting:FindFirstChild("HazardGrade")
		if found and found:IsA("ColorCorrectionEffect") then
			grade = found
		else
			local made = Instance.new("ColorCorrectionEffect")
			made.Name = "HazardGrade"
			made.Parent = Lighting
			grade = made
		end
	end
	local effect = grade :: ColorCorrectionEffect
	effect.Brightness = g.brightness
	effect.Contrast = g.contrast
	effect.Saturation = g.saturation
	effect.TintColor = g.tint
	if not gradeOn then
		effect.Enabled = true
		gradeOn = true
	end
end

local function readTier()
	local name = player:GetAttribute("DetailTier")
	if type(name) ~= "string" or not Look.Tiers[name] then
		name = "High"
	end
	if name ~= ctx.tierName then
		ctx.tierName = name
		ctx.tier = Look.Tiers[name]
		for _, module in pairs(modules) do
			if type(module.tierChanged) == "function" then
				module.tierChanged(ctx)
			end
		end
	end
end

local function readEvent()
	local event = Defs.decode(GameState:GetAttribute(Defs.ATTR_EVENT))
	local old = ctx.event
	if old and event and old.seq == event.seq and old.kind == event.kind then
		-- the same event with a field changed (a rockfall's end moves): keep the modules' state
		for key, value in pairs(event) do
			old[key] = value
		end
		return
	end
	ctx.event = event
	for _, name in ipairs(order) do
		local module = modules[name]
		if module and type(module.setEvent) == "function" then
			local mine = if event and event.kind == name then event else nil
			local ok, err = xpcall(module.setEvent, debug.traceback, ctx, mine)
			if not ok then
				warn("[HazardController] " .. name .. ".setEvent failed\n" .. tostring(err))
			end
		end
	end
end

local warnedAt = -math.huge

local function frame(dt: number)
	local started = os.clock()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	ctx.camera = camera.CFrame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	ctx.root = if root and root:IsA("BasePart") then root else nil
	ctx.rootPos = if ctx.root then ctx.root.Position else ctx.camera.Position
	ctx.inArena = ClientState.inArena == true or ClientState.spectating ~= nil
	ctx.alive = ClientState.inArena == true and ClientState.alive == true
	ctx.moving, ctx.emitters = 0, 0
	local g = ctx.grade
	g.brightness, g.contrast, g.saturation, g.tint = 0, 0, 0, Color3.new(1, 1, 1)
	ctx.hint, ctx.hintWeight = nil, 0
	local now = ctx.now()
	for _, name in ipairs(order) do
		local module = modules[name]
		if module and type(module.update) == "function" and name ~= "Screen" then
			local ok, err = xpcall(module.update, debug.traceback, ctx, dt, now)
			if not ok and started - warnedAt > 10 then
				warnedAt = started
				warn("[HazardController] " .. name .. ".update failed\n" .. tostring(err))
			end
		end
	end
	applyGrade()
	local screen = modules.Screen
	if screen then
		local ok, err = xpcall(screen.update, debug.traceback, ctx, dt, now)
		if not ok and started - warnedAt > 10 then
			warnedAt = started
			warn("[HazardController] Screen.update failed\n" .. tostring(err))
		end
	end
	-- the cost
	local spent = (os.clock() - started) * 1000
	cost.sum += spent
	cost.frames += 1
	cost.worst = math.max(cost.worst, spent)
	if started - cost.at >= 1 then
		cost.text = string.format("%.3f / %.3f ms; %d parts; %d emitters; tier %s", cost.sum / math.max(cost.frames, 1), cost.worst,
			ctx.moving, ctx.emitters, ctx.tierName)
		if player:GetAttribute("HazardCost") ~= cost.text then
			player:SetAttribute("HazardCost", cost.text)
		end
		cost.sum, cost.frames, cost.worst, cost.at = 0, 0, 0, started
	end
end

local function onFx(kind: any, a: any, b: any, c: any, d: any)
	if kind == "L" then
		local storm = modules.Storm
		if storm and type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
			storm.strike(ctx, Vector3.new(a, b, c), d)
		end
	elseif kind == "H" then
		if type(a) == "number" and type(b) == "number" then
			ctx.shove(Vector3.new(a, 0, b), math.clamp(tonumber(c) or 0.5, 0, 1) * 0.6)
		end
	elseif kind == "S" then
		if type(a) == "string" then
			ctx.readout(a, 3.5)
		end
	end
end

function HazardController.debug(): { [string]: any }
	local out: { [string]: any } = { cost = cost.text, tier = ctx.tierName, event = GameState:GetAttribute(Defs.ATTR_EVENT) }
	for name, module in pairs(modules) do
		if type(module.debug) == "function" then
			out[name] = module.debug(ctx)
		end
	end
	return out
end

function HazardController.Init(registry)
	Controllers = registry
	ctx.Controllers = registry
	for _, name in ipairs(order) do
		local child = script:FindFirstChild(name)
		if child and child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if ok and type(result) == "table" then
				modules[name] = result
			else
				warn("[HazardController] could not load " .. name .. ": " .. tostring(result))
			end
		end
	end
	ctx.modules = modules
end

function HazardController.Start()
	readTier()
	player:GetAttributeChangedSignal("DetailTier"):Connect(readTier)
	for _, name in ipairs(order) do
		local module = modules[name]
		if module and type(module.start) == "function" then
			local ok, err = xpcall(module.start, debug.traceback, ctx)
			if not ok then
				warn("[HazardController] " .. name .. ".start failed\n" .. tostring(err))
			end
		end
	end
	GameState:GetAttributeChangedSignal(Defs.ATTR_EVENT):Connect(readEvent)
	readEvent()
	RunService.RenderStepped:Connect(frame)
	-- the remote is made by HazardService when it starts: without the service there is nothing to hear
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local remote = remotes:WaitForChild(Defs.REMOTE, 60)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(onFx)
		end
	end)
end

return HazardController
