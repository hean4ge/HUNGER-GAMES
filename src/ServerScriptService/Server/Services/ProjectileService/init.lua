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
	    headCap: number?             a headshot never does more than this (bows: 90, Config.Bow.HeadshotCap)
	    onTarget: number?            full damage within this many studs of the origin; beyond it the damage falls off
	    falloffBeyond, falloffMin    ... linearly to falloffMin at onTarget + falloffBeyond (CombatStats.falloff)
	    armourPierce: number?        0..1, how much of the victim's armour it ignores (Twin-Bit Axe 0.5)
	    recoverStars: number?        the stars of a thrown weapon, kept on what it leaves in the world
	    pierce: { secondShare }?     Piercing Shot: passes through the first contender (no impact there), then hits at
	                                 secondShare of the damage (Combat_v3 2.2)
	    ricochet: { share, range, cone }?  Ricochet: on the first contact (a contender or a hard surface) it glances once
	                                 toward the nearest other living contender within range in a cone ahead of it, as a
	                                 new projectile at share of the damage (no target in reach: an ordinary impact)
	  }
	Simulated on Heartbeat with raycasts from the previous to the next position (gravity per item), excluding the
	shooter. Characters get a precise per-part ray; the world ray ignores non-collidable foliage, so arrows fly
	through leaves and bushes. Hits go through CombatService.applyHit (headshot when the part is the Head).
	Where it ends up (./WorldProjectiles, the one registry of spent projectiles): embedded at the impact, on the bed
	under water, in the body part it hit (out again when that body dies, or after Config.Combat.BodyFallOutTime), or,
	for a miss that outlives its lifetime, where the rest of its arc meets the ground. Nothing is ever lost: if that
	fails it becomes a plain ground item (LootService.spawnGroundItem).

	Server -> all clients
	  ProjectileFired  { id, shooter (UserId, 0 = none), itemId, origin, velocity, gravity, shotId, t (server time),
	                     stars? (a thrown weapon's) }
	  ProjectileImpact { id, position, normal, hitCharacter, part, material, recovered, itemId, headshot,
	                     worldId?, pivot?, rel?, fallTo?, fallTime?, sink?, lost? }   (the item it left in the world, its
	                     pose, relative to `part` when it is stuck to it, the fall or sink that follows, and lost = it sank
	                     into deep water and goes once down)
	Thrown melee weapons (19 Nov 2026: every one can be thrown) fly end over end and stick edge- or point-first by
	Shared.ThrowLooks (./WorldProjectiles), keep their stars and their star look where they land, and anyone takes them
	back with E.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CombatStats = require(Shared:WaitForChild("CombatStats"))
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
	headCap: number?,
	onTarget: number?,
	falloffBeyond: number?,
	falloffMin: number?,
	armourPierce: number?,
	recoverStars: number?,
	pierce: { secondShare: number }?,
	ricochet: { share: number, range: number, cone: number }?,
	skip: { Instance }?,
	opts: { [string]: any },
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
	local ok, result = pcall(loot.spawnGroundItem, itemId, 1, position, velocity, p.recoverStars)
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
		if entry and p.recoverStars and typeof(entry.model) == "Instance" then
			-- a thrown weapon keeps its stars (the "Stars" attribute ground items carry, Weapons_v2 9.2)
			entry.model:SetAttribute("Stars", p.recoverStars)
		end
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
		lost = if entry and entry.lost then true else nil, -- deep water: it goes once it has sunk
	}
end

local function hurt(p: Projectile, result: RaycastResult, humanoid: Humanoid, bodyPart: BasePart?): boolean
	local headshot = humanoid.Health > 0 and bodyPart ~= nil and bodyPart.Name == "Head"
	local combat = Services.CombatService
	if humanoid.Health > 0 and combat and type(combat.applyHit) == "function" then
		-- distance falloff past the on-target range, then the headshot, then its cap (a bow: never over 90)
		local travelled = (result.Position - p.origin).Magnitude
		local damage = p.damage * CombatStats.falloff(travelled, p.onTarget, p.falloffBeyond, p.falloffMin)
		if headshot then
			damage *= p.headshotMultiplier
			if p.headCap then
				damage = math.min(damage, p.headCap)
			end
		end
		local ok, err = pcall(combat.applyHit, p.shooter, humanoid, damage, {
			cause = "Combat",
			weaponId = p.weaponId,
			position = p.origin,
			headshot = headshot,
			hitPosition = result.Position,
			armourPierce = p.armourPierce,
			distance = travelled,
		})
		if not ok then
			warn("[ProjectileService] applyHit failed: " .. tostring(err))
		end
	end
	return headshot
end

-- Ricochet: the nearest living contender (not the shooter, not the one just hit) within range, inside the cone
-- ahead of the flight. Returns its torso position, or nil.
local function ricochetTarget(p: Projectile, at: Vector3, heading: Vector3, hitModel: Instance?): Vector3?
	local r = p.ricochet
	local combat = Services.CombatService
	if not r or not combat or type(combat.getTargets) ~= "function" then
		return nil
	end
	local flat = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.zAxis
	local cosHalf = math.cos(math.rad((r.cone or 120) / 2))
	local best, bestD = nil, (r.range or 20)
	for _, model in ipairs(combat.getTargets(p.shooterCharacter, true)) do
		if model ~= hitModel and model:IsA("Model") then
			local root = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local to = root.Position - at
				local d = to.Magnitude
				if d > 0.5 and d < bestD and flat:Dot(to / d) >= cosHalf then
					best, bestD = root.Position, d
				end
			end
		end
	end
	return best
end

-- The glance: a new projectile from the contact toward the target, at share of the damage, same item and options.
local function glance(p: Projectile, at: Vector3, target: Vector3, skipModel: Instance?): boolean
	local r = p.ricochet :: any
	local speed = math.max(p.velocity.Magnitude, 40)
	local o = table.clone(p.opts)
	o.ricochet = nil
	o.shotId = nil
	o.skip = if skipModel then { skipModel } else nil
	-- aim a little above the torso for the drop over the short glance
	local t = (target - at).Magnitude / speed
	local aimAt = target + Vector3.new(0, 0.5 * p.gravity * t * t, 0)
	local id = ProjectileService.fire(p.shooter, p.itemId, at, (aimAt - at).Unit * speed, p.gravity, p.damage * (r.share or 0.7), o)
	return id ~= nil
end

local function impactCharacter(p: Projectile, result: RaycastResult, humanoid: Humanoid, bodyPart: BasePart?, velocity: Vector3): boolean
	local model = humanoid.Parent
	if p.pierce then
		-- Piercing Shot: through the first contender; the flight goes on at secondShare (no impact message here, so the
		-- clients' own flight of it carries on too)
		hurt(p, result, humanoid, bodyPart)
		p.damage *= p.pierce.secondShare or 0.7
		p.pierce = nil
		p.skip = p.skip or {}
		table.insert(p.skip :: { Instance }, model :: Instance)
		return false
	end
	if p.ricochet then
		local target = ricochetTarget(p, result.Position, velocity, model)
		if target then
			remove(p)
			local headshot = hurt(p, result, humanoid, bodyPart)
			ProjectileImpact:FireAllClients(impactPayload(p, result, true, headshot, nil))
			if not glance(p, result.Position, target, model) then
				drop(p, result.Position + Vector3.new(0, 0.5, 0), nil)
			end
			return true
		end
	end
	remove(p)
	local headshot = hurt(p, result, humanoid, bodyPart)
	-- it stays in the body part (a body that is already dead lets it fall straight out)
	local entry = leave(p, result.Position, World.stick, result, bodyPart, humanoid, velocity)
	ProjectileImpact:FireAllClients(impactPayload(p, result, true, headshot, entry))
	return true
end

local function impactWorld(p: Projectile, result: RaycastResult, velocity: Vector3)
	if p.ricochet and result.Material ~= Enum.Material.Water then
		-- a hard surface: glance off it toward a contender ahead of the reflected heading
		local n = result.Normal
		local bounced = velocity - 2 * velocity:Dot(n) * n
		local at = result.Position + n * 0.3
		local target = ricochetTarget(p, at, bounced, nil)
		if target then
			remove(p)
			ProjectileImpact:FireAllClients(impactPayload(p, result, false, false, nil))
			if not glance(p, at, target, nil) then
				drop(p, at, nil)
			end
			return
		end
	end
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
	if p.skip then
		list = table.clone(list)
		for _, skipped in ipairs(p.skip :: { Instance }) do
			local index = table.find(list, skipped)
			if index then
				table.remove(list, index)
			end
		end
	end
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
			-- a dead body isn't hurt; it just holds it (a piercing arrow goes on: impactCharacter returns false)
			if not impactCharacter(p, characterHit, humanoid, bodyPart, velocity) then
				p.position += displacement.Unit * (characterHit.Distance + 0.05)
				p.velocity = velocity
				return false
			end
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
		headCap = if Util.isFiniteNumber(o.headCap) then o.headCap else nil,
		onTarget = if Util.isFiniteNumber(o.onTarget) then o.onTarget else nil,
		falloffBeyond = if Util.isFiniteNumber(o.falloffBeyond) then o.falloffBeyond else nil,
		falloffMin = if Util.isFiniteNumber(o.falloffMin) then o.falloffMin else nil,
		armourPierce = if Util.isFiniteNumber(o.armourPierce) then o.armourPierce else nil,
		recoverStars = if Util.isFiniteNumber(o.recoverStars) then o.recoverStars else nil,
		pierce = if type(o.pierce) == "table" then { secondShare = tonumber(o.pierce.secondShare) or 0.7 } else nil,
		ricochet = if type(o.ricochet) == "table"
			then { share = tonumber(o.ricochet.share) or 0.7, range = tonumber(o.ricochet.range) or 20, cone = tonumber(o.ricochet.cone) or 120 }
			else nil,
		skip = if type(o.skip) == "table" then o.skip else nil,
		opts = o,
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
		stars = p.recoverStars, -- (a thrown weapon flies with its own star look)
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
