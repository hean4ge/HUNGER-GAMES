--[[
	ProjectileService - server-side ballistic projectiles: arrows, thrown knives and thrown spears.

	ProjectileService.fire(shooter: Player?, itemId: string, origin: Vector3, velocity: Vector3, gravity: number,
		damage: number, opts?) -> id?   (nil when rejected by the safety caps)
	  opts = {
	    shotId: string?              the client's id for its predicted visual (echoed in ProjectileFired)
	    weaponId: string?            what the hit is credited to (default itemId), e.g. "bow" for an arrow
	    headshotMultiplier: number?  default Config.Combat.DefaultHeadshotMultiplier
	    recoverItem: string?         ground item left behind (via LootService.spawnGroundItem)
	    recoverChance: number?       0..1 for world impacts (default 1)
	    recoverAnywhere: boolean?    always drop it: on characters, in water and when it times out (thrown weapons)
	    lifetime: number?            default Config.Combat.ProjectileMaxLifetime
	  }
	Simulated on Heartbeat with raycasts from the previous to the next position (gravity per item), excluding the
	shooter. Characters get a precise per-part ray; the world ray ignores non-collidable foliage, so arrows fly
	through leaves and bushes. Hits go through CombatService.applyHit (headshot when the part is the Head).

	Server -> all clients
	  ProjectileFired  { id, shooter (UserId, 0 = none), itemId, origin, velocity, gravity, shotId, t (server time) }
	  ProjectileImpact { id, position, normal, hitCharacter, part, material, recovered, itemId, headshot }
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatConfig = Config.Combat

local MAX_ACTIVE = 300
local MAX_PER_SHOOTER = 24
local MAX_DROP_SPEED = 60
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
	recoverChance: number,
	recoverAnywhere: boolean,
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

local function impactCharacter(p: Projectile, result: RaycastResult, humanoid: Humanoid, bodyPart: BasePart?)
	remove(p)
	local headshot = bodyPart ~= nil and bodyPart.Name == "Head"
	local damage = p.damage * (if headshot then p.headshotMultiplier else 1)
	local combat = Services.CombatService
	if combat and type(combat.applyHit) == "function" then
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
	local recovered = false
	if p.recoverAnywhere then
		local back = if p.velocity.Magnitude > 0.01 then p.velocity.Unit * -4 else Vector3.zero
		recovered = drop(p, result.Position + Vector3.new(0, 0.4, 0), Vector3.new(0, 3, 0) + back)
	end
	ProjectileImpact:FireAllClients({
		id = p.id,
		position = result.Position,
		normal = result.Normal,
		hitCharacter = true,
		part = result.Instance,
		material = result.Material,
		recovered = recovered,
		itemId = p.itemId,
		headshot = headshot,
	})
end

local function impactWorld(p: Projectile, result: RaycastResult)
	remove(p)
	local recovered = false
	if p.recoverItem then
		local water = result.Material == Enum.Material.Water
		if p.recoverAnywhere or (not water and math.random() < p.recoverChance) then
			recovered = drop(p, result.Position + result.Normal * 0.5, nil)
		end
	end
	ProjectileImpact:FireAllClients({
		id = p.id,
		position = result.Position,
		normal = result.Normal,
		hitCharacter = false,
		part = result.Instance,
		material = result.Material,
		recovered = recovered,
		itemId = p.itemId,
		headshot = false,
	})
end

local function expire(p: Projectile)
	remove(p)
	if p.recoverAnywhere and p.position.Y > KILL_HEIGHT * 0.5 then
		local velocity = p.velocity
		if velocity.Magnitude > MAX_DROP_SPEED then
			velocity = velocity.Unit * MAX_DROP_SPEED
		end
		drop(p, p.position, velocity)
	end
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
		local combat = Services.CombatService
		local humanoid, _, bodyPart = nil, nil, nil
		if combat and type(combat.characterFromPart) == "function" then
			humanoid, _, bodyPart = combat.characterFromPart(characterHit.Instance)
		end
		if humanoid and humanoid.Health > 0 then
			impactCharacter(p, characterHit, humanoid, bodyPart)
		else
			impactWorld(p, characterHit) -- a body or something else that can't be hurt: it just sticks
		end
		return true
	elseif worldHit then
		impactWorld(p, worldHit)
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
		recoverChance = if Util.isFiniteNumber(o.recoverChance) then o.recoverChance else 1,
		recoverAnywhere = o.recoverAnywhere == true,
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

function ProjectileService.Init(registry)
	Services = registry
	ProjectileFired = Net.event("ProjectileFired")
	ProjectileImpact = Net.event("ProjectileImpact")
end

function ProjectileService.Start()
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
