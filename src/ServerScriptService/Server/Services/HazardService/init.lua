--[[
	HazardService - the arena's challenges: the server half. HazardController is the client half; the numbers and the
	wire format are in Shared.HazardDefs, the looks in Shared.HazardLook.

	  Butterflies (child module)  the blue butterflies: roosts placed afresh each round, swarms that follow and sting,
	                              and the called challenge that wakes a whole meadow of them
	  Fog                         a cold fog that fills a hollow and takes your warmth
	  Storm                       a storm cell with marked lightning strikes and wind
	  Rockfall                    boulders down a steep slope in waves
	  Director                    picks, for each round, which of them happen and when

	Everything is decided here and replicated compactly (HazardDefs has the list): one GameState attribute for the
	event, one small invisible part per butterfly roost, and the HazardFx remote for lightning and shoves.
	It follows the round through the replicated GameState (Phase, RoundId, RoundStartedAt, Practice, RollCall,
	LastStand, ArenaEvent, the border) and never touches RoundService or ArenaService. It asks PlayerService for
	damage only. Without this service the game runs as before.

	Rules it keeps
	  * One called event at a time, arena-wide. A butterfly swarm follows one contender, and no contender has two.
	    Roosts inside another event's zone stay asleep.
	  * Nothing in the round's first minute, nothing new once the Last Stand begins or with two contenders left,
	    nothing across the Offering or a Roll Call.
	  * Every event warns before it can hurt (HazardDefs.<Kind>.Warning seconds: a card and a line through the
	    Announce remote, and the world shows it).
	  * No gore: a hazard's damage is a number; clients show it as a stagger, a shimmer or a shove.
	  * A lone practice round gets every event at half damage.

	Studio only (ignored on a live server): the Workspace attribute DevHazard, set on the server:
	    "Butterflies" | "Fog" | "Storm" | "Rockfall"   call that event now on the first living contender
	                                                   (DevHazardWarn = seconds of warning, default 6)
	    "Swarm"                                        raise the nearest roost at the first living contender
	    "Stop"                                         end the event and send every swarm home
	    "Plan"                                         print this round's plan
	  DevHazardOff = true keeps the director from calling anything (the triggers above still work).
	HazardService.debug() -> a table of what is going on (tests).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("HazardDefs"))
local Look = require(Shared:WaitForChild("HazardLook"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local HazardService = {}

local TICK = 0.1
local FIRE_TAGS = { "Campfire", "WarmthSource", "HazardSmoke" }
local IS_STUDIO = RunService:IsStudio()

local Services: { [string]: any }? = nil
local modules: { [string]: any } = {}
local Director = nil
local remote: RemoteEvent? = nil

-- the context every child module works through
local ctx = {
	Defs = Defs,
	Look = Look,
	ArenaLayout = ArenaLayout,
	Config = Config,
	GameState = GameState,
	isStudio = IS_STUDIO,
	players = {} :: { { [string]: any } }, -- the living contenders, refreshed every tick
	byPlayer = {} :: { [Player]: { [string]: any } },
	event = nil :: { [string]: any }?, -- the called event, if any
	folder = nil :: Folder?,
	practice = false,
	damageScale = 1,
	roundSeed = 0,
}
HazardService.ctx = ctx

local seq = 0
local roundActive = false
local roundId = nil
local cooldownUntil = 0
local fires: { Vector3 } = {}
local firesAt = -math.huge
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local rayFilterAt = -math.huge

function ctx.now(): number
	return workspace:GetServerTimeNow()
end

function ctx.elapsed(): number
	local rs = Services and Services.RoundService
	if rs and type(rs.getElapsed) == "function" then
		local ok, value = pcall(rs.getElapsed)
		if ok and type(value) == "number" then
			return value
		end
	end
	local startedAt = tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
	return if startedAt > 0 then math.max(0, ctx.now() - startedAt) else 0
end

-- coarse ground height (the height grid); the real terrain where a ray finds it
function ctx.ground(x: number, z: number): number
	local y = ArenaLayout.heightAt(x, z)
	return y or ArenaLayout.BaseHeight or 0
end

function ctx.announce(card: string, line: string?, duration: number?, style: string?)
	Net.event("Announce"):FireAllClients({ style = style or "Warning", text = card, sub = line, duration = duration or 6 })
end

function ctx.fxAll(...: any)
	if remote then
		remote:FireAllClients(...)
	end
end

function ctx.fx(player: Player, ...: any)
	if remote and player.Parent == Players then
		remote:FireClient(player, ...)
	end
end

-- Hurt a contender. amount is the full-round amount: a practice round halves it here.
function ctx.damage(entry: { [string]: any }, amount: number, cause: string, position: Vector3?): boolean
	local ps = Services and Services.PlayerService
	if not ps or type(ps.damage) ~= "function" or amount <= 0 then
		return false
	end
	local ok, killed = pcall(ps.damage, entry.player, amount * ctx.damageScale, { cause = cause, position = position })
	return ok and killed == true
end

-- rays that see the world and not the contenders or this service's own parts
function ctx.ray(from: Vector3, direction: Vector3): RaycastResult?
	local t = os.clock()
	if t - rayFilterAt > 1 then
		rayFilterAt = t
		local ignore = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		if ctx.folder then
			table.insert(ignore, ctx.folder)
		end
		for _, dummy in ipairs(CollectionService:GetTagged("TrainingDummy")) do
			table.insert(ignore, dummy)
		end
		rayParams.FilterDescendantsInstances = ignore
	end
	return workspace:Raycast(from, direction, rayParams)
end

-- waist-deep in water (the terrain's own voxels: the lake and the stream)
function ctx.inWater(entry: { [string]: any }): boolean
	if entry.water ~= nil then
		return entry.water
	end
	local p = entry.pos - Vector3.new(0, 1.2, 0)
	local region = Region3.new(p - Vector3.new(2, 2, 2), p + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local wet = false
	local ok, materials = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if ok and materials then
		local size = materials.Size
		for x = 1, size.X do
			for y = 1, size.Y do
				for z = 1, size.Z do
					if materials[x][y][z] == Enum.Material.Water then
						wet = true
					end
				end
			end
		end
	end
	entry.water = wet
	return wet
end

-- beside a lit fire (whoever builds campfires tags them: see the hand-off notes)
function ctx.nearFire(position: Vector3, radius: number): boolean
	local t = os.clock()
	if t - firesAt > 3 then
		firesAt = t
		table.clear(fires)
		for _, tag in ipairs(FIRE_TAGS) do
			for _, inst in ipairs(CollectionService:GetTagged(tag)) do
				if inst:IsDescendantOf(workspace) and inst:GetAttribute("Lit") ~= false then
					if inst:IsA("BasePart") then
						table.insert(fires, inst.Position)
					elseif inst:IsA("PVInstance") then
						table.insert(fires, inst:GetPivot().Position)
					elseif inst:IsA("Attachment") then
						table.insert(fires, inst.WorldPosition)
					end
				end
			end
		end
		-- the players' own campfires (CookingService): one Configuration each under ReplicatedStorage.Campfires
		local camp = game:GetService("ReplicatedStorage"):FindFirstChild("Campfires")
		if camp then
			for _, c in ipairs(camp:GetChildren()) do
				local at = c:GetAttribute("Position")
				if c:GetAttribute("State") == "Lit" and typeof(at) == "Vector3" then
					table.insert(fires, at)
				end
			end
		end
	end
	for _, p in ipairs(fires) do
		if (p - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- something solid over a contender's head
function ctx.covered(entry: { [string]: any }): boolean
	if entry.cover ~= nil then
		return entry.cover
	end
	local hit = ctx.ray(entry.pos + Vector3.new(0, 3, 0), Vector3.new(0, Defs.Storm.CoverHeight, 0))
	entry.cover = hit ~= nil
	return entry.cover
end

-- is this point inside the called event's zone (any kind but the butterflies, whose zone only wakes roosts)?
function ctx.inEventZone(position: Vector3): boolean
	local event = ctx.event
	if not event or event.kind == "Butterflies" then
		return false
	end
	local x, z = event.x, event.z
	if event.kind == "Storm" then
		x, z = Defs.stormCentreAt(event, ctx.now())
	end
	local dx, dz = position.X - x, position.Z - z
	return dx * dx + dz * dz <= event.radius * event.radius
end

local function refreshPlayers()
	table.clear(ctx.players)
	table.clear(ctx.byPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Alive") == true and player:GetAttribute("InArena") == true then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
				local v = root.AssemblyLinearVelocity
				local stance = character:GetAttribute("Stance")
				local entry = {
					player = player,
					character = character,
					humanoid = humanoid,
					root = root,
					pos = root.Position,
					speed = math.sqrt(v.X * v.X + v.Z * v.Z),
					crouched = stance == "Crouch" or stance == "Slide",
				}
				table.insert(ctx.players, entry)
				ctx.byPlayer[player] = entry
			end
		end
	end
end

local function publish(event: { [string]: any }?)
	local text = if event then Defs.encode(event) else ""
	if GameState:GetAttribute(Defs.ATTR_EVENT) ~= text then
		GameState:SetAttribute(Defs.ATTR_EVENT, text)
	end
end

local function ensureFolder(): Folder
	local folder = ctx.folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = Defs.FOLDER
	made.Parent = workspace
	ctx.folder = made
	return made
end

-- End the called event now (its module tidies up).
local function finish(announceIt: boolean)
	local event = ctx.event
	if not event then
		return
	end
	ctx.event = nil
	local module = modules[event.kind]
	if module and type(module.finish) == "function" then
		local ok, err = xpcall(module.finish, debug.traceback, ctx, event)
		if not ok then
			warn("[HazardService] " .. event.kind .. ".finish failed\n" .. tostring(err))
		end
	end
	publish(nil)
	cooldownUntil = ctx.now() + Defs.Director.Cooldown
	if announceIt then
		local def = Defs[event.kind]
		ctx.announce(def.Over, nil, 4, "Toast")
	end
end

-- Call an event. opts: { x, z (where: else the module chooses from where the contenders are), intensity, warning,
-- force (Studio: make it happen even where it normally would not) }. Returns the event, or nil and why not.
function HazardService.call(kind: string, opts: { [string]: any }?): ({ [string]: any }?, string?)
	local module = modules[kind]
	local def = Defs[kind]
	if not module or type(def) ~= "table" then
		return nil, "no such challenge"
	end
	if not roundActive then
		return nil, "no round is running"
	end
	if ctx.event then
		return nil, "another event is running"
	end
	local o = opts or {}
	refreshPlayers()
	local okMake, made, why = xpcall(module.make, debug.traceback, ctx, o)
	if not okMake then
		warn("[HazardService] " .. kind .. ".make failed\n" .. tostring(made))
		return nil, "error"
	end
	if type(made) ~= "table" then
		return nil, why or "no place for it"
	end
	local event = made
	seq += 1
	local t = ctx.now()
	local warning = tonumber(o.warning) or def.Warning
	event.kind = kind
	event.seq = seq
	event.warnAt = t
	event.startAt = t + warning
	event.endAt = event.startAt + (event.duration or def.Duration)
	event.intensity = event.intensity or tonumber(o.intensity) or 1
	event.seed = event.seed or math.random(1, 2 ^ 20)
	event.radius = event.radius or def.Radius
	event.a, event.b, event.c, event.d = event.a or 0, event.b or 0, event.c or 0, event.d or 0
	ctx.event = event
	publish(event)
	ctx.announce(def.Card, def.Herald, 7, "Warning")
	if type(module.begin) == "function" then
		local ok, err = xpcall(module.begin, debug.traceback, ctx, event)
		if not ok then
			warn("[HazardService] " .. kind .. ".begin failed\n" .. tostring(err))
		end
	end
	if IS_STUDIO then
		print(string.format("[HazardService] %s called at (%.0f, %.0f) r %.0f, intensity %.2f, warning %.0f s, %d living",
			kind, event.x, event.z, event.radius, event.intensity, warning, #ctx.players))
	end
	return event, nil
end

function HazardService.stop()
	finish(false)
	local butterflies = modules.Butterflies
	if butterflies and type(butterflies.recall) == "function" then
		butterflies.recall(ctx)
	end
end

function HazardService.current(): { [string]: any }?
	return ctx.event
end

-- May the director call something now? (the quiet times)
function ctx.quiet(): (boolean, string?)
	if not roundActive then
		return true, "no round"
	end
	if ctx.event then
		return true, "an event is running"
	end
	if ctx.now() < cooldownUntil then
		return true, "cooldown"
	end
	if GameState:GetAttribute("LastStand") == true then
		return true, "the last stand"
	end
	local rollCall = GameState:GetAttribute("RollCall")
	if type(rollCall) == "string" and rollCall ~= "" then
		return true, "the roll call"
	end
	if GameState:GetAttribute("ArenaEvent") == "Feast" then
		return true, "the offering"
	end
	local alive = #ctx.players
	if alive == 0 then
		return true, "nobody is alive"
	end
	if alive <= 2 and not ctx.practice then
		return true, "the final two"
	end
	return false, nil
end

local function startRound()
	roundActive = true
	roundId = GameState:GetAttribute("RoundId")
	ctx.practice = GameState:GetAttribute("Practice") == true
	ctx.damageScale = if ctx.practice then Defs.Director.PracticeDamage else 1
	ctx.roundSeed = (tonumber(roundId) or 0) * 7919 + math.floor(os.clock() * 1000) % 100000
	cooldownUntil = 0
	ensureFolder()
	refreshPlayers()
	for name, module in pairs(modules) do
		if type(module.roundStart) == "function" then
			local ok, err = xpcall(module.roundStart, debug.traceback, ctx)
			if not ok then
				warn("[HazardService] " .. name .. ".roundStart failed\n" .. tostring(err))
			end
		end
	end
	if Director then
		Director.plan(ctx)
	end
end

local function endRound()
	roundActive = false
	finish(false)
	for name, module in pairs(modules) do
		if type(module.roundEnd) == "function" then
			local ok, err = xpcall(module.roundEnd, debug.traceback, ctx)
			if not ok then
				warn("[HazardService] " .. name .. ".roundEnd failed\n" .. tostring(err))
			end
		end
	end
	if GameState:GetAttribute(Defs.ATTR_WIND) ~= nil then
		GameState:SetAttribute(Defs.ATTR_WIND, nil)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("HazardChill") ~= nil then
			player:SetAttribute("HazardChill", nil)
		end
	end
	local folder = ctx.folder
	ctx.folder = nil
	if folder then
		folder:Destroy()
	end
end

local function step(dt: number)
	local phase = GameState:GetAttribute("Phase")
	local active = phase == "Active"
	if active and (not roundActive or GameState:GetAttribute("RoundId") ~= roundId) then
		if roundActive then
			endRound()
		end
		startRound()
	elseif not active and roundActive then
		endRound()
	end
	if not roundActive then
		return
	end
	refreshPlayers()
	local now = ctx.now()
	local event = ctx.event
	if event then
		if now >= event.endAt or GameState:GetAttribute("LastStand") == true then
			finish(now >= event.endAt)
		else
			local module = modules[event.kind]
			if module and type(module.step) == "function" then
				module.step(ctx, event, Defs.phaseAt(event, now), dt, now)
			end
		end
	end
	-- the butterflies live all round, called or not
	local butterflies = modules.Butterflies
	if butterflies and type(butterflies.ambient) == "function" then
		butterflies.ambient(ctx, dt, now)
	end
	if Director and not (IS_STUDIO and workspace:GetAttribute("DevHazardOff") == true) then
		Director.step(ctx, HazardService, now)
	end
end

local function onDevHazard()
	local value = workspace:GetAttribute("DevHazard")
	if type(value) ~= "string" or value == "" then
		return
	end
	workspace:SetAttribute("DevHazard", nil)
	if value == "Stop" then
		HazardService.stop()
		print("[HazardService] stopped")
		return
	elseif value == "Plan" then
		if Director then
			print("[HazardService] plan: " .. Director.describe())
		end
		return
	elseif value == "Swarm" then
		refreshPlayers()
		local first = ctx.players[1]
		if first and modules.Butterflies then
			print("[HazardService] swarm: " .. tostring(modules.Butterflies.raiseNearest(ctx, first)))
		end
		return
	end
	if ctx.event then
		finish(false)
	end
	refreshPlayers()
	local first = ctx.players[1]
	local opts: { [string]: any } = { warning = tonumber(workspace:GetAttribute("DevHazardWarn")) or 6, force = true }
	if first then
		opts.x, opts.z = first.pos.X, first.pos.Z
	end
	local event, why = HazardService.call(value, opts)
	if not event then
		warn("[HazardService] DevHazard " .. value .. ": " .. tostring(why))
	end
end

function HazardService.debug(): { [string]: any }
	local out: { [string]: any } = {
		roundActive = roundActive,
		practice = ctx.practice,
		living = #ctx.players,
		event = if ctx.event then Defs.encode(ctx.event) else "",
		plan = if Director then Director.describe() else "",
	}
	for name, module in pairs(modules) do
		if type(module.debug) == "function" then
			out[name] = module.debug(ctx)
		end
	end
	return out
end

function HazardService.Init(registry)
	Services = registry
	ctx.Services = registry
	for _, name in ipairs(Defs.Kinds) do
		local child = script:FindFirstChild(name)
		if child and child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if ok and type(result) == "table" then
				modules[name] = result
			else
				warn("[HazardService] could not load " .. name .. ": " .. tostring(result))
			end
		end
	end
	local directorModule = script:FindFirstChild("Director")
	if directorModule and directorModule:IsA("ModuleScript") then
		local ok, result = pcall(require, directorModule)
		if ok and type(result) == "table" then
			Director = result
		else
			warn("[HazardService] could not load Director: " .. tostring(result))
		end
	end
	ctx.modules = modules
end

function HazardService.Start()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local existing = folder:FindFirstChild(Defs.REMOTE)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		local made = Instance.new("RemoteEvent")
		made.Name = Defs.REMOTE
		made.Parent = folder
		remote = made
	end
	publish(nil)
	for name, module in pairs(modules) do
		if type(module.start) == "function" then
			task.spawn(function()
				local ok, err = xpcall(module.start, debug.traceback, ctx)
				if not ok then
					warn("[HazardService] " .. name .. ".start failed\n" .. tostring(err))
				end
			end)
		end
	end
	if IS_STUDIO then
		workspace:GetAttributeChangedSignal("DevHazard"):Connect(onDevHazard)
	end
	local last = os.clock()
	local warnedAt = -math.huge
	while true do
		task.wait(TICK)
		local t = os.clock()
		local dt = math.min(t - last, 0.5)
		last = t
		local ok, err = xpcall(step, debug.traceback, dt)
		if not ok and t - warnedAt > 10 then
			warnedAt = t
			warn("[HazardService] step failed\n" .. tostring(err))
		end
	end
end

return HazardService
