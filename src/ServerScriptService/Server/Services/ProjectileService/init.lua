--[[
	ProjectileService - server-side ballistic projectiles: arrows, thrown knives and thrown spears.

	ProjectileService.fire(shooter: Player?, itemId: string, origin: Vector3, velocity: Vector3, gravity: number,
		damage: number, opts?) -> id?   (nil when rejected by the safety caps; CombatService then refunds the item)
	  opts = {
	    shotId: string?              the client's id for its predicted visual (echoed in ProjectileFired)
	    weaponId: string?            what the hit is credited to (default itemId), e.g. "bow" for an arrow
	    headshotMultiplier: number?  default Config.Combat.DefaultHeadshotMultiplier
	    recoverItem: string?         the item that stays in the world where the shot ends up (./WorldProjectiles)
	    lifetime: number?            default Config.Combat.ProjectileMaxLifetime
	  }
	Simulated on Heartbeat with raycasts from the previous to the next position (gravity per item), excluding the
	shooter. Characters get a precise per-part ray; the world ray ignores non-collidable foliage, so arrows fly
	through leaves and bushes. Hits go through CombatService.applyHit (headshot when the part is the Head).
	Where it ends up (./WorldProjectiles, the one registry of spent projectiles): embedded at the impact, on the bed
	under water, in the body part it hit (out again when that body dies, or after Config.Combat.BodyFallOutTime), or,
	for a miss that outlives its lifetime, where the rest of its arc meets the ground. Nothing is ever lost: if that
	fails it becomes a plain ground item (LootService.spawnGroundItem).

	Server -> all clients
	  ProjectileFired  { id, shooter (UserId, 0 = none), itemId, origin, velocity, gravity, shotId, t (server time) }
	  ProjectileImpact { id, position, normal, hitCharacter, part, material, recovered, itemId, headshot,
	                     worldId?, pivot?, rel?, fallTo?, fallTime?, sink? }   (the item it left in the world, its pose,
	                     relative to `part` when it is stuck to it, and the fall or sink that follows)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local World = require(script:WaitForChild("WorldProjectiles"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatConfig = Config.Combat

local MAX_ACTIVE = 300
local MAX_PER_SHOOTER = 24
local MAX_STEP = 1 / 30 -- sub-step long frames so the arc stays accurate
local KILL_HEIGHT = -400

local ProjectileService = {}

local Services: { [string]: any } = {}
local ProjectileFired: RemoteEvent
local ProjectileImpact: RemoteEvent

type Projectile = {
	id: number,
	shooter: Player?,
	shooterCharacter: Model?,
	itemId: string,
	origin: Vector3,
	position: Vector3,
	velocity: Vector3,
	gravity: number,
	damage: number,
	weaponId: string,
	headshotMultiplier: number,
	recoverItem: string?,
	lifetime: number,
	age: number,
}

local active: { [number]: Projectile } = {}
local activeCount = 0
local perShooter: { [Player]: number } = {}
local nextId = 0
local warnedLoot = false

local characterParams = RaycastParams.new()
characterParams.FilterType = Enum.RaycastFilterType.Include

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true
worldParams.IgnoreWater = false

-- Ground items (crates are solid and stay hittable).
local function lootFolder(): Instance?
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	return loot and loot:FindFirstChild("Items")
end

local function remove(p: Projectile)
	if active[p.id] == nil then
		return
	end
	active[p.id] = nil
	activeCount -= 1
	local shooter = p.shooter
	if shooter then
		local left = (perShooter[shooter] or 1) - 1
		perShooter[shooter] = if left > 0 then left else nil
	end
end

local function drop(p: Projectile, position: Vector3, velocity: Vector3?): boolean
	local itemId = p.recoverItem
	if not itemId or position.Y < KILL_HEIGHT * 0.5 then
		return false
	end
	local loot = Services.LootService
	if not loot or type(loot.spawnGroundItem) ~= "function" then
		if not warnedLoot then
			warnedLoot = true
			warn("[ProjectileService] LootService.spawnGroundItem is missing; projectiles can't be recovered")
		end
		return false
	end
	local ok, result = pcall(loot.spawnGroundItem, itemId, 1, position, velocity)
	if not ok then
		warn("[ProjectileService] spawnGroundItem failed: " .. tostring(result))
		return false
	end
	return result ~= nil
end

-- The item stays in the world where the shot ended up (WorldProjectiles). If that fails it becomes a plain ground item
-- instead, so a shot never eats it. (World.land finding no ground means it fell off the world: nothing to leave.)
local function leave(p: Projectile, position: Vector3, place: (...any) -> any, ...: any): any
	if not p.recoverItem then
		return nil
	end
	local ok, entry = pcall(place, p, ...)
	if ok then
		if entry or place == World.land then
			return entry
		end
	else
		warn("[ProjectileService] couldn't leave " .. tostring(p.recoverItem) .. " in the world: " .. tostring(entry))
	end
	drop(p, position + Vector3.new(0, 0.5, 0), nil)
	return nil
end

local function impactPayload(p: Projectile, result: RaycastResult, hitCharacter: boolean, headshot: boolean, entry: any)
	return {
		id = p.id,
		position = result.Position,
		normal = result.Normal,
		hitCharacter = hitCharacter,
		part = if entry and entry.host then entry.host else result.Instance,
		material = result.Material,
		recovered = entry ~= nil,
		itemId = p.itemId,
		headshot = headshot,
		worldId = if entry then entry.id else nil,
		pivot = if entry then entry.pivot else nil,
		rel = if entry then entry.rel else nil,
		fallTo = if entry then entry.fallTo else nil,
		fallTime = if entry then entry.fallTime else nil,
		sink = if entry and entry.sink then true else nil,
	}
end

local function impactCharacter(p: Projectile, result: RaycastResult, humanoid: Humanoid, bodyPart: BasePart?, velocity: Vector3)
	remove(p)
	local alive = humanoid.Health > 0
	local headshot = alive and bodyPart ~= nil and bodyPart.Name == "Head"
	local combat = Services.CombatService
	if alive and combat and type(combat.applyHit) == "function" then
		local damage = p.damage * (if headshot then p.headshotMultiplier else 1)
		local ok, err = pcall(combat.applyHit, p.shooter, humanoid, damage, {
			cause = "Combat",
			weaponId = p.weaponId,
			position = p.origin,
			headshot = headshot,
			hitPosition = result.Position,
		})
		if not ok then
			warn("[ProjectileService] applyHit failed: " .. tostring(err))
		end
	end
	-- it stays in the body part (a body that is already dead lets it fall straight out)
	local entry = leave(p, result.Position, World.stick, result, bodyPart, humanoid, velocity)
	ProjectileImpact:FireAllClients(impactPayload(p, result, true, headshot, entry))
end

local function impactWorld(p: Projectile, result: RaycastResult, velocity: Vector3)
	remove(p)
	local water = result.Material == Enum.Material.Water
	local entry = leave(p, result.Position + result.Normal * 0.5, if water then World.sink else World.embed, result, velocity)
	ProjectileImpact:FireAllClients(impactPayload(p, result, false, false, entry))
end

-- A miss that outlived its lifetime: the rest of its arc is traced to where it meets the ground (no impact effects).
local function expire(p: Projectile)
	remove(p)
	leave(p, p.position, World.land, worldParams)
end

local function withoutShooter(targets: { Instance }, shooterCharacter: Model?): { Instance }
	if not shooterCharacter then
		return targets
	end
	local index = table.find(targets, shooterCharacter)
	if not index then
		return targets
	end
	local list = table.clone(targets)
	table.remove(list, index)
	return list
end

-- The velocity where a sub-step's ray hit, `distance` along its `length`.
local function velocityAt(p: Projectile, gravity: Vector3, dt: number, distance: number, length: number): Vector3
	return p.velocity + gravity * (dt * math.clamp(distance / math.max(length, 1e-6), 0, 1))
end

-- One sub-step. Returns true when the projectile is finished.
local function step(p: Projectile, dt: number, targets: { Instance }): boolean
	p.age += dt
	local gravity = Vector3.new(0, -p.gravity, 0)
	local displacement = p.velocity * dt + gravity * (0.5 * dt * dt)

	local characterHit: RaycastResult? = nil
	local list = withoutShooter(targets, p.shooterCharacter)
	if #list > 0 then
		characterParams.FilterDescendantsInstances = list
		characterHit = workspace:Raycast(p.position, displacement, characterParams)
	end
	local worldHit = workspace:Raycast(p.position, displacement, worldParams)

	if characterHit and (worldHit == nil or characterHit.Distance <= worldHit.Distance) then
		local velocity = velocityAt(p, gravity, dt, characterHit.Distance, displacement.Magnitude)
		local combat = Services.CombatService
		local humanoid, _, bodyPart = nil, nil, nil
		if combat and type(combat.characterFromPart) == "function" then
			humanoid, _, bodyPart = combat.characterFromPart(characterHit.Instance)
		end
		if humanoid then
			impactCharacter(p, characterHit, humanoid, bodyPart, velocity) -- a dead body isn't hurt; it just holds it
		else
			impactWorld(p, characterHit, velocity) -- something else in a target model: it just sticks
		end
		return true
	elseif worldHit then
		impactWorld(p, worldHit, velocityAt(p, gravity, dt, worldHit.Distance, displacement.Magnitude))
		return true
	end

	p.position += displacement
	p.velocity += gravity * dt
	if p.age >= p.lifetime or p.position.Y < KILL_HEIGHT then
		expire(p)
		return true
	end
	return false
end

local function onHeartbeat(dt: number)
	if activeCount <= 0 then
		return
	end
	local combat = Services.CombatService
	local targets: { Instance } = if combat and type(combat.getTargets) == "function" then combat.getTargets(nil) else {}
	local exclude = table.clone(targets)
	local loot = lootFolder()
	if loot then
		table.insert(exclude, loot)
	end
	worldParams.FilterDescendantsInstances = exclude

	local steps = math.max(1, math.ceil(math.min(dt, 0.25) / MAX_STEP))
	local h = math.min(dt, 0.25) / steps
	for _, p in pairs(active) do
		for _ = 1, steps do
			if step(p, h, targets) then
				break
			end
		end
	end
end

local function clearAll()
	table.clear(active)
	table.clear(perShooter)
	activeCount = 0
end

function ProjectileService.fire(
	shooter: Player?,
	itemId: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	damage: number,
	opts: { [string]: any }?
): number?
	if type(itemId) ~= "string" or not Util.isFiniteVector(origin) or not Util.isFiniteVector(velocity) then
		return nil
	end
	if velocity.Magnitude < 1 or activeCount >= MAX_ACTIVE then
		return nil
	end
	if shooter and (perShooter[shooter] or 0) >= MAX_PER_SHOOTER then
		return nil
	end
	local o = opts or {}
	nextId += 1
	local id = nextId
	local p: Projectile = {
		id = id,
		shooter = shooter,
		shooterCharacter = shooter and shooter.Character,
		itemId = itemId,
		origin = origin,
		position = origin,
		velocity = velocity,
		gravity = if Util.isFiniteNumber(gravity) then gravity else 0,
		damage = if Util.isFiniteNumber(damage) then math.max(0, damage) else 0,
		weaponId = if type(o.weaponId) == "string" then o.weaponId else itemId,
		headshotMultiplier = if Util.isFiniteNumber(o.headshotMultiplier)
			then o.headshotMultiplier
			else CombatConfig.DefaultHeadshotMultiplier,
		recoverItem = if type(o.recoverItem) == "string" then o.recoverItem else nil,
		lifetime = if Util.isFiniteNumber(o.lifetime) then o.lifetime else CombatConfig.ProjectileMaxLifetime,
		age = 0,
	}
	active[id] = p
	activeCount += 1
	if shooter then
		perShooter[shooter] = (perShooter[shooter] or 0) + 1
	end
	ProjectileFired:FireAllClients({
		id = id,
		shooter = if shooter then shooter.UserId else 0,
		itemId = itemId,
		origin = origin,
		velocity = velocity,
		gravity = p.gravity,
		shotId = if type(o.shotId) == "string" then o.shotId else "",
		t = workspace:GetServerTimeNow(),
	})
	return id
end

-- Test hook (Edit-mode checks): advance every projectile by dt.
ProjectileService._simulate = onHeartbeat
-- The registry of spent projectiles left in the world (counts, tests).
ProjectileService.world = World

function ProjectileService.Init(registry)
	Services = registry
	ProjectileFired = Net.event("ProjectileFired")
	ProjectileImpact = Net.event("ProjectileImpact")
	World.Init(registry)
end

function ProjectileService.Start()
	World.Start()
	RunService.Heartbeat:Connect(onHeartbeat)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState:GetAttribute("Phase") ~= "Active" then
			clearAll() -- nothing in flight survives the end of a round
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		perShooter[player] = nil
	end)
end

return ProjectileService
